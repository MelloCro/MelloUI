--------------------------------------------------------------------------------
-- MelloUI - Cooldown Timers
--
-- Countdown text on cooldown swipes: large outlined numbers that
-- change colour and size with the time left (red when about to finish, yellow
-- under a minute, dim white for minutes, grey for hours). Covers the action
-- bars (including pet, stance and flyout buttons) and the aura / crowd control
-- icons on nameplates.
--
-- The Cooldown widget methods are hooked on their shared metatable, so every
-- cooldown frame reports its start and duration here. The text is only drawn
-- when those values are plain numbers; secret values (possible on enemy
-- nameplate auras) leave Blizzard's own countdown numbers in place instead.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Area = MelloUI.Area   -- (2.1.6: each kind of cooldown is an area's: CATEGORY_AREA)
local Perf = MelloUI.Perf:Scope("CooldownText")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer

local M = MelloUI:RegisterModule("CooldownText", {
	title = "Cooldown Timers",
	desc = "Large countdown numbers on action bar cooldowns and nameplate auras, coloured by time left.",
	icon = "Interface\\Icons\\Spell_Nature_TimeStop",
	flavour = "Countdowns on every cooldown, coloured by how long you still have to wait.",
	-- (one look, the Bars audit's point 1, the user's yes: Q9's fold -- no master; On Action Bars and Nameplate
	-- Auras are its switches, each where its rows are; Core.lua's MERGES folds an older save's master into them)
	tweak = { label = "Cooldown Timers", desc = "Countdown numbers on action bar cooldowns and nameplate auras, coloured by the time left.", order = 3, always = true },
	switches = { "actionBars", "nameplates" },
	defaults = {
		actionBars = true,
		nameplates = true,
		minDuration = 2,
		fontRatio = 0.5,
		tenths = false,
		colorByTime = true,
		fightNumbers = true,   -- the game's own numbers while cooldown times are secret (2.1.63's hand-over)
		sweep = "game",        -- the dark sweep's darkness on action buttons: "game", "dark", "darker"
	},
	options = {
		{ type = "header", name = "Show On" },
		{ type = "toggle", key = "actionBars", name = "Action Bars", desc = "Timers on action, pet and stance buttons." },
		{ type = "toggle", key = "nameplates", name = "Nameplate Auras", desc = "Timers on the game's nameplate auras." },
		{ type = "header", name = "Timer" },
		{ type = "slider", key = "minDuration", name = "Minimum Duration", min = 1, max = 10, step = 0.5,
		  format = function(v) return string.format("%.1fs", v) end,
		  desc = "Cooldowns shorter than this show no timer. 2 seconds skips the global cooldown." },
		{ type = "slider", key = "fontRatio", name = "Text Size", min = 0.3, max = 0.8, step = 0.05, percent = true,
		  desc = "Timer text size, relative to the icon." },
		{ type = "toggle", key = "tenths", name = "Show Tenths Below 5s", desc = "Shows 4.3 instead of 5 in a cooldown's last seconds." },
		{ type = "toggle", key = "colorByTime", name = "Colour And Size By Time Left", desc = "Timers turn red and larger under 5 seconds, yellow under a minute, and smaller for minutes and hours. Off: all white." },
		-- (a German player: in fights the game's numbers count the global cooldown too, "2, then 1"; "if we make the
		-- dark overlay a step darker, the number is not needed and it looks nicer")
		{ type = "toggle", key = "fightNumbers", name = "Numbers In Fights", new = "2.1.66",
		  desc = "In fights the game hides cooldown times from addons, and its own numbers count instead, the global cooldown too. Off: only the dark sweep shows the time left." },
		{ type = "dropdown", key = "sweep", name = "Sweep Darkness", new = "2.1.66",
		  values = { { value = "game", label = "The Game's" }, { value = "dark", label = "Dark" }, { value = "darker", label = "Darker" } },
		  desc = "How dark the sweep over an action button runs while it cools down. Back to the game's after a /reload." },
	},
})

-- the sweep's darkness for each choice (nil: the game's own, left alone)
local SWEEP_ALPHA = { dark = 0.85, darker = 0.95 }

-- the game's own numbers held back while cooldown times are secret (Numbers In Fights off)
function M.SweepOnly()
	return type(M.db) == "table" and M.db.fightNumbers == false or false
end


--------------------------------------------------------------------------------
-- Styles (the usual countdown colours and sizes)
--------------------------------------------------------------------------------

local SOON = 5
-- (the colours: MelloUI.Meaning's cooldown* keys)
local function Style(key, scale)
	local c = MelloUI.Meaning[key]
	return { r = c[1], g = c[2], b = c[3], scale = scale }
end
local STYLES = {
	soon    = Style("cooldownSoon", 1.3),
	seconds = Style("cooldownSeconds", 1.0),
	minutes = Style("cooldownMinutes", 0.8),
	hours   = Style("cooldownHours", 0.75),
}
local PLAIN = { r = 1, g = 1, b = 1, scale = 1 }

local function Describe(remaining)
	if remaining < SOON then
		if M.db.tenths then
			return string.format("%.1f", remaining), "soon"
		end
		return tostring(math.ceil(remaining)), "soon"
	elseif remaining < 60 then
		return tostring(math.ceil(remaining)), "seconds"
	elseif remaining < 3600 then
		return string.format("%dm", math.ceil(remaining / 60)), "minutes"
	elseif remaining < 86400 then
		return string.format("%dh", math.ceil(remaining / 3600)), "hours"
	end
	return string.format("%dd", math.ceil(remaining / 86400)), "hours"
end

--------------------------------------------------------------------------------
-- Timer registry
--------------------------------------------------------------------------------

local timers = setmetatable({}, { __mode = "k" })     -- [cooldown] = timer
local active = {}                                      -- [cooldown] = true while counting
local pending = setmetatable({}, { __mode = "k" })    -- [cooldown] = { start, duration, modRate, tries }
local requestedHidden = setmetatable({}, { __mode = "k" }) -- [cooldown] = what Blizzard last asked for
-- [cooldown] = true: one of ours cleared by the game, stopped at the next
-- tick unless it is set again first. The game clears and sets some cooldowns
-- again on EVERY frame (the target of target's auras: its OnUpdate runs
-- RefreshAuras); a stop and a start each time wrote the game's own numbers
-- flag back and forth and laid our text again, every frame (0.17.0,
-- docs/plans/fps-portrait-fix.md: write only when something changed)
local cleared = setmetatable({}, { __mode = "k" })
local hidingNumbers = false
local hooksInstalled = false

-- The 10/s tick (below) runs only while a timer counts or a cooldown waits
-- for its nameplate; anything that starts either wakes it. A timer that
-- sets itself again, not a script on every frame (a long cooldown kept one
-- running for its whole length -- /melloperf, 2026-09-24).
local TICK = 0.1
local ticking = false
local Tick   -- the tick itself, below

local function Wake()
	if not ticking then
		ticking = true
		C_Timer.After(TICK, Tick)
	end
end

local function IsPlainNumber(v)
	if type(v) ~= "number" then
		return false
	end
	if issecretvalue and issecretvalue(v) then
		return false
	end
	return true
end

-- (2.1.66, the follow-up to pull request #59) an action button's sweep at the darkness asked for: written once a
-- button (its first cooldown) and again only right after the game wrote its own (GameSwiped, a post-hook of the
-- cooldowns' SetSwipeColor) -- never on every SetCooldown (CLAUDE.md: no write-back on a path the game runs on every
-- update). The game's own transparent sweep while its spell cast animation plays (ActionButton's PlaySpellCastAnim,
-- alpha 0) is left as it is until the game shows its sweep again. "The Game's": nothing written; a button already
-- darkened keeps it until a /reload
-- [cooldown] = the darkness this module wrote last; HIDDEN: the game hid the sweep (left so until it shows it again);
-- false: the game wrote its own visible colour
local swept = setmetatable({}, { __mode = "k" })
local HIDDEN = "hidden"
local sweeping = false                             -- (our own write: not taken for the game's)

local function SweepWanted()
	return SWEEP_ALPHA[type(M.db) == "table" and M.db.sweep or "game"]
end

local function SweepWrite(cooldown, a)
	sweeping = true
	pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, a)
	sweeping = false
	swept[cooldown] = a
end

local function Sweep(cooldown)
	local a = SweepWanted()
	local now = swept[cooldown]
	if a and now ~= a and now ~= HIDDEN and cooldown.SetSwipeColor then
		SweepWrite(cooldown, a)
	end
end

-- the game wrote a sweep colour on a cooldown this module darkened: darkened again, unless the game hid it (alpha 0:
-- left hidden, even through a SetCooldown, until the game shows its sweep again)
local function GameSwiped(cooldown, _, _, _, alpha)
	if sweeping or swept[cooldown] == nil then
		return
	end
	if not (IsPlainNumber(alpha) and alpha > 0) then
		swept[cooldown] = HIDDEN
		return
	end
	swept[cooldown] = false
	local a = SweepWanted()
	if a then
		local count = MelloUI.Perf and MelloUI.Perf.WriteBack
		if count then
			count("CooldownText: the sweep's darkness after the game's")
		end
		SweepWrite(cooldown, a)
	end
end

local function Category(cooldown)
	if cooldown.noCooldownCount then
		return nil
	end
	local parent = cooldown:GetParent()
	if not parent then
		return nil
	end
	if parent.cooldown == cooldown or parent.chargeCooldown == cooldown then
		if parent.action ~= nil or parent.HotKey or parent.icon then
			return "actionBars"
		end
	end
	local frame = parent
	for _ = 1, 8 do
		if not frame then
			break
		end
		local name = frame.GetName and frame:GetName()
		if name and name:match("^NamePlate%d") then
			return "nameplates"
		end
		frame = frame:GetParent()
	end
	return nil
end

-- (2.1.6) a kind of cooldown counted: its switch on and its area MelloUI's (MelloUI.Area) -- an area off keeps the
-- game's own numbers there
local CATEGORY_AREA = { actionBars = "actionbars", nameplates = "nameplates" }
local function CategoryOn(db, category)
	return (db and db[category] and Area.On(CATEGORY_AREA[category])) and true or false
end

local function SetNativeNumbersHidden(cooldown, hidden)
	if cooldown.SetHideCountdownNumbers then
		hidingNumbers = true
		cooldown:SetHideCountdownNumbers(hidden)
		hidingNumbers = false
	end
end

-- (2.1.63; the user, 2026-11-21: "out of nowhere sometimes the cooldown numbers dont appear on the buttons") an action
-- button's cooldown whose time the game hands as a secret -- while it restricts addons' cooldowns: a fight, an
-- encounter, a keystone, a PvP match, some maps (GetActionCooldown's SecretWhenCooldownsRestricted) -- cannot be
-- counted here, and the game's own numbers stood hidden by its Countdown For Cooldowns option (off by default): none
-- at all. Those the cooldown's own numbers count instead (the widget reads a secret itself), shown whatever that
-- option asks, from Minimum Duration up; given back as it ends, or to ours once its time is plain again.
local handed = setmetatable({}, { __mode = "k" })   -- [cooldown] = { hidden = the game's wish, min = its own minimum }

local function HandOver(cooldown)
	if handed[cooldown] then
		return
	end
	local wish = requestedHidden[cooldown]
	if wish == nil and cooldown.GetHideCountdownNumbers then
		local ok, v = pcall(cooldown.GetHideCountdownNumbers, cooldown)
		wish = ok and v == true
	end
	local min = 0
	if cooldown.GetMinimumCountdownDuration then
		local ok, v = pcall(cooldown.GetMinimumCountdownDuration, cooldown)
		min = ok and IsPlainNumber(v) and v or 0
	end
	handed[cooldown] = { hidden = wish and true or false, min = min }
	SetNativeNumbersHidden(cooldown, M.SweepOnly())
	local want = math.floor((tonumber(M.db and M.db.minDuration) or 2) * 1000 + 0.5)
	if cooldown.SetMinimumCountdownDuration and want ~= min then
		pcall(cooldown.SetMinimumCountdownDuration, cooldown, want)
	end
end

local function HandBack(cooldown)
	local h = handed[cooldown]
	if not h then
		return
	end
	handed[cooldown] = nil
	if cooldown.SetMinimumCountdownDuration then
		pcall(cooldown.SetMinimumCountdownDuration, cooldown, h.min)
	end
	SetNativeNumbersHidden(cooldown, h.hidden)
end

local function GetTimer(cooldown)
	local timer = timers[cooldown]
	if not timer then
		local fs = cooldown:CreateFontString(nil, "OVERLAY")
		-- Always start with a valid font so SetText never runs on a bare string.
		fs:SetFontObject(GameFontHighlightOutline or NumberFontNormal or GameFontNormal)
		fs:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
		fs:SetJustifyH("CENTER")
		timer = { text = fs, cooldown = cooldown, nativeHidden = nil }
		timers[cooldown] = timer
	end
	return timer
end

local function StopTimer(cooldown, restoreNative)
	local timer = timers[cooldown]
	-- nothing counting, nothing waiting and nothing to put back: the game
	-- clears and re-sets cooldowns all the time (some on every frame), and a
	-- timer already stopped needs no second stop
	if pending[cooldown] == nil and handed[cooldown] == nil
		and not (timer and (timer.expires or timer.nativeHidden ~= nil)) then
		return
	end
	if cooldown.IsForbidden and cooldown:IsForbidden() then
		return
	end
	if restoreNative then
		HandBack(cooldown)   -- (2.1.63: counted by its own numbers -- given back first)
	end
	active[cooldown] = nil
	pending[cooldown] = nil
	if not timer then
		return
	end
	timer.expires = nil
	timer.text:SetText("")
	timer.text:Hide()
	if restoreNative and timer.nativeHidden ~= nil then
		SetNativeNumbersHidden(cooldown, timer.nativeHidden)
		timer.nativeHidden = nil
	end
end

-- Nameplate aura icons can report a secret width (their layout is protected
-- on enemy plates); fall back to the parent's size, then a fixed icon size.
local FALLBACK_WIDTH = 20

local function UsableWidth(cooldown)
	local width = cooldown:GetWidth()
	if IsPlainNumber(width) then
		return width
	end
	local parent = cooldown:GetParent()
	width = parent and parent:GetWidth()
	if IsPlainNumber(width) then
		return width
	end
	return FALLBACK_WIDTH
end

local function ApplyFont(timer, style)
	local cooldown = timer.cooldown
	local width = UsableWidth(cooldown)
	if width < 12 then
		return false
	end
	local base = math.floor(width * (tonumber(M.db.fontRatio) or 0.5) + 0.5)
	local size = math.max(6, math.floor(base * style.scale + 0.5))
	if timer.size ~= size or timer.fontPath == nil then
		local object = GameFontHighlightOutline or NumberFontNormal
		local path = object:GetFont()
		timer.fontPath = path
		timer.size = size
		timer.text:SetFont(path, size, "OUTLINE")
	end
	return true
end

local function UpdateTimer(cooldown, timer, now)
	local remaining = timer.expires - now
	if remaining <= 0 then
		StopTimer(cooldown, true)
		return
	end
	local text, styleName = Describe(remaining)
	local style = M.db.colorByTime and STYLES[styleName] or PLAIN
	if styleName ~= timer.styleName then
		if not ApplyFont(timer, style) then
			-- No usable size yet (hidden or collapsed button); try again later.
			timer.styleName = nil
			timer.lastText = nil
			timer.text:Hide()
			return
		end
		timer.styleName = styleName
		timer.text:SetTextColor(style.r, style.g, style.b)
	end
	if not timer.fontPath then
		return
	end
	if text ~= timer.lastText then
		timer.lastText = text
		timer.text:SetText(text)
	end
	timer.text:Show()
end

local function StartTimer(cooldown, start, duration, modRate)
	if not M.isEnabled or (cooldown.IsForbidden and cooldown:IsForbidden()) then
		return
	end
	-- (the countdown addons' convention: a cooldown that asks for none -- the
	-- configurator's Bars stage sample, its own frame -- is never counted,
	-- nor looked at again)
	if cooldown.noCooldownCount then
		return
	end
	-- cleared and set again in the same moment: the same cooldown is still
	-- counting, nothing to write
	if cleared[cooldown] then
		cleared[cooldown] = nil
		local timer = timers[cooldown]
		if timer and timer.expires and IsPlainNumber(start) and IsPlainNumber(duration) then
			local d = duration
			if IsPlainNumber(modRate) and modRate > 0 and modRate ~= 1 then
				d = d / modRate
			end
			if math.abs(start + d - timer.expires) < 0.01 then
				return
			end
		end
	end
	local category = Category(cooldown)
	if not category then
		-- Nameplate aura icons get their cooldown before Blizzard parents them
		-- to the nameplate; look again on the next ticks.
		local entry = pending[cooldown]
		local tries = entry and entry.tries or 0
		if tries < 5 then
			-- the entry kept and filled again (a cooldown can wait through
			-- several SetCooldowns)
			if not entry then
				entry = {}
				pending[cooldown] = entry
			end
			entry.start, entry.duration, entry.modRate, entry.tries = start, duration, modRate, tries + 1
			Wake()
		else
			pending[cooldown] = nil
		end
		return
	end
	pending[cooldown] = nil
	if not CategoryOn(M.db, category) then
		StopTimer(cooldown, true)
		return
	end
	if category == "actionBars" then
		Sweep(cooldown)
	end
	if not IsPlainNumber(start) or not IsPlainNumber(duration) then
		-- Secret values: Blizzard's own numbers (2.1.63: on an action button, shown to count it -- HandOver)
		if not handed[cooldown] then
			StopTimer(cooldown, true)
		end
		if category == "actionBars" then
			HandOver(cooldown)
		end
		return
	end
	HandBack(cooldown)   -- (2.1.63: plain again -- counted here)
	if modRate ~= nil and IsPlainNumber(modRate) and modRate > 0 and modRate ~= 1 then
		duration = duration / modRate
	end
	if duration <= 0 or duration < (tonumber(M.db.minDuration) or 2) then
		StopTimer(cooldown, true)
		return
	end
	local timer = GetTimer(cooldown)
	timer.expires = start + duration
	timer.styleName = nil
	timer.lastText = nil
	if timer.nativeHidden == nil then
		timer.nativeHidden = requestedHidden[cooldown] or false
		SetNativeNumbersHidden(cooldown, true)
	end
	active[cooldown] = true
	Wake()
	UpdateTimer(cooldown, timer, GetTime())
end

--------------------------------------------------------------------------------
-- Update loop
--------------------------------------------------------------------------------

local retry = {}   -- the waiting cooldowns of one tick, the list kept from tick to tick
Tick = function()
	-- cleared first: a tick that fails is started again by the next cooldown
	ticking = false
	if not M.isEnabled then
		return
	end
	-- the cleared ones not set again since: stopped now
	for cooldown in pairs(cleared) do
		cleared[cooldown] = nil
		StopTimer(cooldown, true)
	end
	local now = GetTime()
	if next(pending) then
		local n = 0
		for cooldown, entry in pairs(pending) do
			retry[n + 1], retry[n + 2] = cooldown, entry
			n = n + 2
		end
		for i = 1, n, 2 do
			local cooldown, entry = retry[i], retry[i + 1]
			retry[i], retry[i + 1] = nil, nil
			StartTimer(cooldown, entry.start, entry.duration, entry.modRate)
		end
	end
	for cooldown in pairs(active) do
		local timer = timers[cooldown]
		if timer and timer.expires then
			UpdateTimer(cooldown, timer, now)
		else
			active[cooldown] = nil
		end
	end
	-- nothing counting and nothing waiting: rest until StartTimer wakes it
	-- (a retry above that found its nameplate has set it again already)
	if next(active) ~= nil or next(pending) ~= nil then
		Wake()
	end
end

--------------------------------------------------------------------------------
-- Hooks (shared Cooldown metatable)
--------------------------------------------------------------------------------

-- These public getters return real-time values by default, including any speed modifier.
-- Never read timing fields or calculate with restricted values.
local function ReadDurationObject(duration)
	if duration:HasSecretValues() ~= false then
		return nil
	end
	-- Our numeric tick uses GetTime; an object with another clock must stay on its native path.
	if duration:GetClock() ~= nil then
		return nil
	end
	return duration:GetStartTime(), duration:GetTotalDuration()
end

local function DurationObjectChanged(cooldown, duration)
	cleared[cooldown] = nil
	if not M.isEnabled or (cooldown.IsForbidden and cooldown:IsForbidden()) then
		StopTimer(cooldown, true)
		return
	end
	if not (issecretvalue and issecretvalue(duration)) then
		local ok, start, seconds = pcall(ReadDurationObject, duration)
		if ok and IsPlainNumber(start) and IsPlainNumber(seconds) then
			if not Category(cooldown) then
				StopTimer(cooldown, true)
			end
			StartTimer(cooldown, start, seconds)
			return
		end
	end
	-- The native setter bypasses SetCooldown. If its timing is restricted or unavailable,
	-- retire our previous number instead of leaving it over the new cooldown (2.1.63: on an action button, its own
	-- numbers count it -- HandOver)
	if Category(cooldown) == "actionBars" and CategoryOn(M.db, "actionBars") then
		if not handed[cooldown] then
			StopTimer(cooldown, true)
		end
		HandOver(cooldown)
		return
	end
	StopTimer(cooldown, true)
end

-- Blizzard asked for its own numbers shown or hidden (called guarded: one
-- function for every call, no closure made per call)
local function NumbersRequested(cooldown, hidden)
	local wantsHidden = hidden and true or false
	requestedHidden[cooldown] = wantsHidden
	-- (2.1.63) counted by its own numbers: the wish kept for when it is given back, the numbers left showing
	local h = handed[cooldown]
	if h then
		h.hidden = wantsHidden
		if wantsHidden ~= M.SweepOnly() then
			SetNativeNumbersHidden(cooldown, M.SweepOnly())
		end
		return
	end
	local timer = timers[cooldown]
	if timer and active[cooldown] then
		-- Remember the caller's latest choice for when our countdown ends or hands back to the native widget.
		timer.nativeHidden = wantsHidden
		if not wantsHidden then
			-- Blizzard wants its numbers back while ours are showing; keep ours until the handoff.
			SetNativeNumbersHidden(cooldown, true)
		end
	end
end

local function InstallHooks()
	if hooksInstalled then
		return
	end
	-- (one probe, ever: a client whose cooldowns hand no method table gets
	-- none of the hooks, and is not probed again)
	hooksInstalled = true
	local probe = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
	local meta = getmetatable(probe)
	local index = meta and meta.__index
	if type(index) ~= "table" then
		return
	end

	hooksecurefunc(index, "SetCooldown", function(cooldown, start, duration, modRate)
		StartTimer(cooldown, start, duration, modRate)
	end)
	if type(index.SetCooldownDuration) == "function" then
		hooksecurefunc(index, "SetCooldownDuration", function(cooldown, duration, modRate)
			StartTimer(cooldown, GetTime(), duration, modRate)
		end)
	end
	if type(index.SetCooldownFromDurationObject) == "function" then
		hooksecurefunc(index, "SetCooldownFromDurationObject", DurationObjectChanged)
	end
	if type(index.SetCooldownUNIX) == "function" then
		hooksecurefunc(index, "SetCooldownUNIX", function(cooldown, start, duration, modRate)
			if IsPlainNumber(start) then
				StartTimer(cooldown, start - (GetServerTime() - GetTime()), duration, modRate)
			end
		end)
	end
	-- every cooldown in the game is cleared through here, some on every
	-- frame: StopTimer returns at once for one that is not ours
	hooksecurefunc(index, "Clear", function(cooldown)
		local timer = timers[cooldown]
		if timer and timer.expires then
			-- one of ours: stopped at the next tick unless set again first
			if not cleared[cooldown] then
				cleared[cooldown] = true
				Wake()
			end
			return
		end
		StopTimer(cooldown, true)
	end)
	-- (2.1.66) the game's own sweep colour on a cooldown this module darkened (GameSwiped: one table read for the rest)
	if type(index.SetSwipeColor) == "function" then
		hooksecurefunc(index, "SetSwipeColor", GameSwiped)
	end
	hooksecurefunc(index, "SetHideCountdownNumbers", function(cooldown, hidden)
		if hidingNumbers then
			return
		end
		-- 'hidden' can derive from a secret aura duration; never let that raise.
		pcall(NumbersRequested, cooldown, hidden)
	end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

-- a switch on: the hooks on every cooldown are wanted (none made while both
-- are off -- they cannot be taken off again once made)
local function Wanted(db)
	return db ~= nil and (db.actionBars ~= false or db.nameplates ~= false)
end

function M:OnEnable(db)
	self.db = db
	if Wanted(db) then
		InstallHooks()
	end
	Wake()
end

function M:OnDisable()
	-- the tick stops at its next turn (the module is off)
	wipe(cleared)
	for cooldown in pairs(timers) do
		StopTimer(cooldown, true)
	end
	for cooldown in pairs(handed) do
		HandBack(cooldown)
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if (key == "actionBars" or key == "nameplates") and value then
		InstallHooks()
	end
	if key == "fightNumbers" then
		for cooldown in pairs(handed) do
			SetNativeNumbersHidden(cooldown, M.SweepOnly())
		end
	end
	if key == "sweep" then
		for cooldown in pairs(swept) do
			Sweep(cooldown)
		end
	end
	-- Force fonts and styles to be re-evaluated on the next tick.
	for cooldown, timer in pairs(timers) do
		timer.styleName = nil
		timer.size = nil
		if active[cooldown] then
			local category = Category(cooldown)
			if not category or not CategoryOn(db, category) then
				StopTimer(cooldown, true)
			end
		end
	end
	-- (2.1.63) Action Bars off: the cooldowns its own numbers counted given back to the game's wish
	if not CategoryOn(db, "actionBars") then
		for cooldown in pairs(handed) do
			HandBack(cooldown)
		end
	end
end

-- (2.1.6) an area's switch moved (MelloUI.Area): its timers stopped (the game's numbers back), or counted again from
-- the next cooldown the game sets there
for _, area in pairs(CATEGORY_AREA) do
	Area.Listen(area, function()
		if M.isEnabled and M.db then
			M:OnSettingChanged("area", nil, M.db)
		end
	end, "CooldownText: the " .. area .. " area")
end

MelloUI:Profile("CooldownText", "timer tick (10/s)", Tick)
MelloUI:Profile("CooldownText", "cooldown hooks", StartTimer)
