--------------------------------------------------------------------------------
-- MelloUI - Cooldown Timers
--
-- OmniCC style countdown text on cooldown swipes: large outlined numbers that
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
local Perf = MelloUI.Perf:Scope("CooldownText")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer

local M = MelloUI:RegisterModule("CooldownText", {
	title = "Cooldown Timers",
	desc = "OmniCC style countdown numbers on action bar cooldowns and nameplate auras, coloured by time left.",
	icon = "Interface\\Icons\\Spell_Nature_TimeStop",
	flavour = "Countdowns on every cooldown, coloured by how long you still have to wait.",
	group = "Frames and bars",
	tweak = { label = "Cooldown Timers", desc = "Countdown numbers on action bar cooldowns and nameplate auras, coloured by the time left.", order = 3 },
	defaults = {
		actionBars = true,
		nameplates = true,
		minDuration = 2,
		fontRatio = 0.5,
		tenths = false,
		colorByTime = true,
	},
	options = {
		{ type = "header", name = "Show On" },
		{ type = "toggle", key = "actionBars", name = "Action Bars", desc = "Action, pet, stance and flyout buttons." },
		{ type = "toggle", key = "nameplates", name = "Nameplate Auras", desc = "Buff, debuff and crowd control icons on nameplates." },
		{ type = "header", name = "Timer" },
		{ type = "slider", key = "minDuration", name = "Minimum Duration", min = 1, max = 10, step = 0.5,
		  format = function(v) return string.format("%.1fs", v) end,
		  desc = "Cooldowns shorter than this show no text (2 s skips the global cooldown)." },
		{ type = "slider", key = "fontRatio", name = "Text Size", min = 0.3, max = 0.8, step = 0.05, percent = true,
		  desc = "Text height relative to the icon size." },
		{ type = "toggle", key = "tenths", name = "Show Tenths Below 5s", desc = "Show 4.3 instead of 5 when the cooldown is about to finish." },
		{ type = "toggle", key = "colorByTime", name = "Colour By Time Left", desc = "Red under 5 s, yellow under a minute, dim white for minutes, grey for hours." },
	},
})

--------------------------------------------------------------------------------
-- Styles (OmniCC defaults)
--------------------------------------------------------------------------------

local SOON = 5
local STYLES = {
	soon    = { r = 1.0, g = 0.1, b = 0.1, scale = 1.3 },
	seconds = { r = 1.0, g = 1.0, b = 0.1, scale = 1.0 },
	minutes = { r = 0.8, g = 0.8, b = 0.9, scale = 0.8 },
	hours   = { r = 0.7, g = 0.7, b = 0.7, scale = 0.75 },
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

local function SetNativeNumbersHidden(cooldown, hidden)
	if cooldown.SetHideCountdownNumbers then
		hidingNumbers = true
		cooldown:SetHideCountdownNumbers(hidden)
		hidingNumbers = false
	end
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
	if pending[cooldown] == nil and not (timer and (timer.expires or timer.nativeHidden ~= nil)) then
		return
	end
	if cooldown.IsForbidden and cooldown:IsForbidden() then
		return
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
	if not M.db[category] then
		StopTimer(cooldown, true)
		return
	end
	if not IsPlainNumber(start) or not IsPlainNumber(duration) then
		-- Secret values: leave Blizzard's own numbers alone.
		StopTimer(cooldown, true)
		return
	end
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

-- Blizzard asked for its own numbers shown or hidden (called guarded: one
-- function for every call, no closure made per call)
local function NumbersRequested(cooldown, hidden)
	local wantsHidden = hidden and true or false
	requestedHidden[cooldown] = wantsHidden
	local timer = timers[cooldown]
	if timer and active[cooldown] and not wantsHidden then
		-- Blizzard wants its numbers back while ours are showing; keep ours.
		timer.nativeHidden = false
		SetNativeNumbersHidden(cooldown, true)
	end
end

local function InstallHooks()
	if hooksInstalled then
		return
	end
	local probe = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
	local meta = getmetatable(probe)
	local index = meta and meta.__index
	if type(index) ~= "table" then
		return
	end
	hooksInstalled = true

	hooksecurefunc(index, "SetCooldown", function(cooldown, start, duration, modRate)
		StartTimer(cooldown, start, duration, modRate)
	end)
	if type(index.SetCooldownDuration) == "function" then
		hooksecurefunc(index, "SetCooldownDuration", function(cooldown, duration, modRate)
			StartTimer(cooldown, GetTime(), duration, modRate)
		end)
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
		StopTimer(cooldown, true)
	end)
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

function M:OnEnable(db)
	self.db = db
	InstallHooks()
	Wake()
end

function M:OnDisable()
	-- the tick stops at its next turn (the module is off)
	for cooldown in pairs(timers) do
		StopTimer(cooldown, true)
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	-- Force fonts and styles to be re-evaluated on the next tick.
	for cooldown, timer in pairs(timers) do
		timer.styleName = nil
		timer.size = nil
		if active[cooldown] then
			local category = Category(cooldown)
			if not category or not db[category] then
				StopTimer(cooldown, true)
			end
		end
	end
end

MelloUI:Profile("CooldownText", "timer tick (10/s)", Tick)
MelloUI:Profile("CooldownText", "cooldown hooks", StartTimer)
