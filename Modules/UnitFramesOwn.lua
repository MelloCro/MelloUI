--------------------------------------------------------------------------------
-- MelloUI - Unit Frames: MelloUI's own unit frames (fr-17, 2026-11-01; the user, asked whether MelloUI's unit
-- frames are its own like ElvUI's -- they were the game's frames dressed -- picked "2": "Rebuild the player, target,
-- focus and pet frames as MelloUI's own, in all three skins, the way the party frames were done")
--
-- Stage 1: the player frame. While Unit Frames is on, the player frame on the screen is ours: a secure unit button
-- (a click targets you, a right click opens your menu, an item dropped on it is put on) built as the game's own
-- PlayerFrame is built -- PlayerFrame.xml and Camelot's PlayerFrame.lua of this client (1.60.1.70425): the same parts
-- under the same keys (PlayerFrameContainer.PlayerPortrait, PlayerFrameContent.PlayerFrameContentMain.
-- HealthBarsContainer.HealthBar ...), the same sizes, places, layers and the game's own pictures -- so every dresser
-- of MelloUI's (Unit Frames, the painted skin, Class Icons, Bar Textures, Bar Text, Dark Mode, Healer Frames, the
-- meter's tab, the frame effects, the Fader) dresses it as it dressed the game's, through MelloUI.Units (below). Its
-- bars are our own StatusBars handed the unit's health and power as the game hands them (a secret value goes to the
-- bar as it is, never read or compared); its name, portrait, level, rest and combat state, leader crown, PvP badge,
-- group number, ready check, threat flash and the numbers on the portrait follow the unit's own events.
--
-- It stands ON the game's frame: a child of the game's PlayerFrame over its whole rect, at its level. So it takes
-- the game frame's place, size and alpha as they are and as they change -- the active Edit Mode layout, Edit
-- Layout's place and size (EditMode 3:1, its *Base moves), the installer's layout, Fit to this screen, a profile's
-- places, the Fader -- and whatever hangs on the game's PlayerFrame stays with it (the pet frame, the totems and
-- class bars under it, the locked cast bar, Edit Layout's attaching by the name "PlayerFrame"). Nobody's frame moves.
--
-- The game's frame kept away while ours stands in, by taint-safe means only (fr-16's, the party frames'): its two
-- holders of art and content (PlayerFrameContainer, PlayerFrameContent) at alpha 0 (an alpha is never protected and
-- no game code writes theirs); out of a fight its mouse off (the frame, its two bars' hover) and Edit Mode's
-- selection box on it unseen and click-through; the events of its own code let go (the frame's and its bars',
-- each one's registrations and units kept to give back exactly), its vehicle events left with it (they swap the pet
-- frame's unit). No key written on it or its regions, no hook on them, nothing of it shown, hidden or moved. Its
-- children of other jobs (the pet frame, the totem and class bars, the cast bar) are never touched.
-- Turned off (Unit Frames off): ours hidden, the game's given back as it was; a dresser that dressed the game's frame
-- meanwhile (hooks can't be taken off) asks for a /reload once (MelloUI:AskReload).
--
-- Stage 2 (Modules/UnitFramesTarget.lua): the target frame and its target of target, the same way. Stage 3 (the same
-- file): the focus frame and its focus target. Stage 4 (Modules/UnitFramesPet.lua): the pet frame.
--
-- MelloUI.Units (the one way every module finds a unit frame -- the game's, or ours while it stands in):
--   Units.Player() -> frame          the player frame on the screen: ours while it stands in, else the game's
--   Units.PlayerName() -> fontstring  its name (the game's PlayerName, ours)
--   Units.PlayerLevel() -> fontstring its level (the game's PlayerLevelText, ours)
--   Units.Target() -> frame          the target frame on the screen (ours: MelloUITargetFrame, else TargetFrame)
--   Units.TargetToT() -> frame       its target of target (ours: MelloUITargetFrameToT, else TargetFrameToT)
--   Units.Focus() / Units.FocusToT() the focus frame and its focus target (ours: MelloUIFocusFrame / ...ToT, stage 3)
--   Units.Pet() -> frame             the pet frame on the screen (ours: MelloUIPetFrame, stage 4, else PetFrame)
--   Units.PetPart(key) -> region     its part by the game's global name's key: "texture" (PetFrameTexture), "portrait",
--                                     "name", "health", "mana", "healthMask", "manaMask", "flash", "attack", "hit"
--   Units.Frame(name) -> frame       the frame on the screen for the game's global `name` ("TargetFrame" ...)
--   Units.Own(key) -> frame | nil     ours for "player" / "target" / "targettarget" / "focus" / "focustarget" / "pet"
--                                     while it stands in
--   Units.Away(obj) -> bool           obj is (in) a game frame kept away now (the game's PlayerFrame itself, its art
--                                     and content holders and what is in them -- never its other children)
--   Units.Fade(owner, regions, selves, roots) / Units.Quiet(owner, mouse, motion, boxes) / Units.Return(owner)
--                                     a game frame kept away (its holders' alpha at once, its mouse and Edit Mode's
--                                     box out of a fight) and given back exactly, by owner (one system for each frame)
--   Units.Parts                       the building pieces ours are made with (Atlas, Tex, Font, Holder, Bar ...)
--   Units.Hook(fname, fn)             a post-hook of the game's update function `fname` (UnitFrame_Update,
--                                     PlayerFrame_ToPlayerArt ...) that skips the game's frames kept away, and runs
--                                     for ours too when ours does that update (Units.Notify)
--   Units.Notify(fname, ...)          ours did what `fname` does: its hooks run with ours
--   Units.Texts(f)                    a frame's bars' values as text, as the game's TextStatusBar (fr-16's, moved
--                                     here from Group Frames: the party portraits and the player frame share it)
--   Units.Silence(f, events, owner, depth) / Units.Unsilence(owner)  a game frame's events let go / given back
-- The bus: 'units' (key, on) when ours comes or goes (the dressers lay their look on the frame Units.Player() gives).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("UnitFrames (own)")
local hooksecurefunc = Perf.hooksecurefunc
local Shared = Perf.Shared
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text

local WEAK = { __mode = "k" }
local U = {
	own = {},                              -- [key] = our frame while it stands in
	mine = setmetatable({}, WEAK),         -- [frame] = true: one of ours (never kept away)
	roots = setmetatable({}, WEAK),        -- [a game holder kept away] = its owner (what is in it is away too)
	selves = setmetatable({}, WEAK),       -- [a game frame kept away] = its owner (itself only: not its other children)
	awayOf = setmetatable({}, WEAK),       -- [object] = the answer, kept until the next change
	after = {},                            -- [fname] = { fn, ... } run after the game's or ours
	silenced = {},                         -- [owner] = { [game frame] = { { event, unit1, unit2 }, ... } }
	given = {},                            -- [owner] = { [game region] = { alpha =, mouse =, motion = } as it was }
}
MelloUI.Units = U

-- the game's global frame names -> the key of ours that stands in for it
local NAMES = { PlayerFrame = "player", TargetFrame = "target", TargetFrameToT = "targettarget", FocusFrame = "focus",
	FocusFrameToT = "focustarget", PetFrame = "pet" }

--------------------------------------------------------------------------------
-- Finding the frames
--------------------------------------------------------------------------------

function U.Player()
	return U.own.player or _G.PlayerFrame
end

function U.Target()
	return U.own.target or rawget(_G, "TargetFrame")
end

function U.TargetToT()
	return U.own.targettarget or rawget(_G, "TargetFrameToT")
end

function U.Focus()
	return U.own.focus or rawget(_G, "FocusFrame")
end

function U.FocusToT()
	return U.own.focustarget or rawget(_G, "FocusFrameToT")
end

-- (stage 4, Modules/UnitFramesPet.lua) the pet frame on the screen, and its parts by the game's global names
function U.Pet()
	return U.own.pet or rawget(_G, "PetFrame")
end

local PET_GLOBALS = { frame = "PetFrame", texture = "PetFrameTexture", portrait = "PetPortrait", name = "PetName",
	health = "PetFrameHealthBar", mana = "PetFrameManaBar", healthMask = "PetFrameHealthBarMask",
	manaMask = "PetFrameManaBarMask", flash = "PetFrameFlash", attack = "PetAttackModeTexture", hit = "PetHitIndicator" }
function U.PetPart(key)
	local f = U.own.pet
	if f and f.parts then
		return f.parts[key]
	end
	local name = PET_GLOBALS[key]
	return name and rawget(_G, name) or nil
end

function U.Frame(name)
	local key = NAMES[name]
	return (key and U.own[key]) or rawget(_G, name)
end

function U.Own(key)
	return U.own[key]
end

function U.PlayerName()
	local f = U.own.player
	if f then
		return f.name
	end
	return _G.PlayerName
end

function U.PlayerLevel()
	local f = U.own.player
	if f then
		return f.levelText
	end
	return _G.PlayerLevelText
end

-- obj is the game's frame kept away, or in one of its holders kept away (cached until the next change)
function U.Away(obj)
	if type(obj) ~= "table" or next(U.selves) == nil then
		return false
	end
	local known = U.awayOf[obj]
	if known ~= nil then
		return known
	end
	local away, cur = false, obj
	for _ = 1, 10 do
		if type(cur) ~= "table" or U.mine[cur] then
			break
		end
		if U.selves[cur] then
			away = (cur == obj)
			break
		end
		if U.roots[cur] then
			away = true
			break
		end
		local fn = cur.GetParent
		if type(fn) ~= "function" then
			break
		end
		local ok, p = pcall(fn, cur)
		cur = ok and p or nil
	end
	U.awayOf[obj] = away
	return away
end

local function Changed()
	wipe(U.awayOf)
end

-- the game's update function `fname` hooked once per fn: skipped for a game frame kept away, run for ours on
-- Units.Notify. (`fname` may not exist on this client: then ours only)
function U.Hook(fname, fn)
	local list = U.after[fname]
	if not list then
		list = {}
		U.after[fname] = list
	end
	for i = 1, #list do
		if list[i] == fn then
			return
		end
	end
	list[#list + 1] = fn
	if type(rawget(_G, fname)) == "function" then
		hooksecurefunc(fname, function(first, ...)
			if not U.Away(first) then
				fn(first, ...)
			end
		end)
	end
end

function U.Notify(fname, ...)
	local list = U.after[fname]
	if not list then
		return
	end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

--------------------------------------------------------------------------------
-- A game frame's events let go and given back (fr-16's, from Group Frames: one system). Each frame's own
-- registrations, units included, kept by owner to give back exactly; looked at again on every pass (the game may
-- register a bar's unit events again). A frame's event list, never a key of theirs; out of a fight.
--   Units.Silence(f, events, owner, depth)   `depth`: how deep into its children (0: the frame alone)
--   Units.Unsilence(owner)
--   Units.Silenced(owner) -> its table ([frame] = { { event, u1, u2 }, ... })
--------------------------------------------------------------------------------

function U.Silenced(owner)
	local t = U.silenced[owner]
	if not t then
		t = setmetatable({}, WEAK)
		U.silenced[owner] = t
	end
	return t
end

local SilenceKids
function U.Silence(f, events, owner, depth)
	if type(f) ~= "table" or type(f.IsEventRegistered) ~= "function" or U.mine[f] then
		return
	end
	local all = U.Silenced(owner)
	local had = all[f] or {}
	all[f] = had
	for _, e in ipairs(events) do
		local ok, on, u1, u2 = pcall(f.IsEventRegistered, f, e)
		if ok and on == true then
			local kept = false
			for _, r in ipairs(had) do
				if r[1] == e then
					r[2], r[3], kept = u1, u2, true
				end
			end
			if not kept then
				had[#had + 1] = { e, u1, u2 }
			end
			pcall(f.UnregisterEvent, f, e)
		end
	end
	if (depth or 0) > 0 and type(f.GetChildren) == "function" then
		SilenceKids(events, owner, depth - 1, f:GetChildren())
	end
end

-- (the frames in it, walked without a table: select)
SilenceKids = function(events, owner, depth, ...)
	for i = 1, select("#", ...) do
		U.Silence(select(i, ...), events, owner, depth)
	end
end

function U.Unsilence(owner)
	local all = U.silenced[owner]
	if not all then
		return
	end
	for f, had in pairs(all) do
		for _, r in ipairs(had) do
			if r[2] ~= nil then
				pcall(f.RegisterUnitEvent, f, r[1], r[2], r[3])
			else
				pcall(f.RegisterEvent, f, r[1])
			end
		end
		all[f] = nil
	end
end

--------------------------------------------------------------------------------
-- A game frame kept away and given back, by owner (one system for each of ours: the player frame's, the target's,
-- its target of target's). Method calls only -- SetAlpha, EnableMouse, EnableMouseMotion -- each region's own as it
-- was kept to give back exactly; never a key written on theirs, nothing shown, hidden or moved.
--   Units.Fade(owner, regions, selves, roots)  `regions` at alpha 0 at once (an alpha: in a fight too, never
--                                              protected); `selves`: game frames away themselves (not their other
--                                              children); `roots`: holders away with all in them (Units.Away)
--   Units.Quiet(owner, mouse, motion, boxes)   out of a fight: `mouse` frames' mouse off, `motion` bars' hover off,
--                                              `boxes` (Edit Mode's selection) unseen and click-through
--   Units.Return(owner)                        all given back: alphas, mouse, events (Units.Unsilence), the away marks
--------------------------------------------------------------------------------

local function Alpha(r)
	local ok, a = pcall(r.GetAlpha, r)
	return (ok and Num(a)) or 1
end

local function Mouse(r)
	local ok, on = pcall(r.IsMouseEnabled, r)
	return ok and on == true
end

local function MouseMotion(r)
	if type(r.IsMouseMotionEnabled) ~= "function" then
		return Mouse(r)
	end
	local ok, on = pcall(r.IsMouseMotionEnabled, r)
	return ok and on == true
end

-- (a region's record: its own values kept the first time each is touched)
local function Was(owner, r)
	local given = U.given[owner]
	if not given then
		given = {}
		U.given[owner] = given
	end
	local was = given[r]
	if not was then
		was = {}
		given[r] = was
	end
	return was
end

function U.Fade(owner, regions, selves, roots)
	for _, r in ipairs(regions or {}) do
		if r then
			local was = Was(owner, r)
			if was.alpha == nil then
				was.alpha = Alpha(r)
			end
			pcall(r.SetAlpha, r, 0)
		end
	end
	for _, s in ipairs(selves or {}) do
		if s then
			U.selves[s] = owner
		end
	end
	for _, r in ipairs(roots or {}) do
		if r then
			U.roots[r] = owner
		end
	end
	Changed()
end

function U.Quiet(owner, mouse, motion, boxes)
	if InCombatLockdown() then
		return
	end
	for _, r in ipairs(mouse or {}) do
		if r then
			local was = Was(owner, r)
			if was.mouse == nil then
				was.mouse = Mouse(r)
			end
			pcall(r.EnableMouse, r, false)
		end
	end
	for _, bar in ipairs(motion or {}) do
		if bar then
			local was = Was(owner, bar)
			if was.motion == nil then
				was.motion = MouseMotion(bar)
			end
			if bar.EnableMouseMotion then
				pcall(bar.EnableMouseMotion, bar, false)
			else
				pcall(bar.EnableMouse, bar, false)
			end
		end
	end
	for _, box in ipairs(boxes or {}) do
		if box then
			local was = Was(owner, box)
			if was.alpha == nil then
				was.alpha = Alpha(box)
			end
			if was.mouse == nil then
				was.mouse = Mouse(box)
			end
			pcall(box.SetAlpha, box, 0)
			pcall(box.EnableMouse, box, false)
		end
	end
end

function U.Return(owner)
	U.Unsilence(owner)
	for r, was in pairs(U.given[owner] or {}) do
		if was.alpha ~= nil then
			pcall(r.SetAlpha, r, was.alpha)
		end
		if was.mouse ~= nil then
			pcall(r.EnableMouse, r, was.mouse)
		end
		if was.motion ~= nil then
			if r.EnableMouseMotion then
				pcall(r.EnableMouseMotion, r, was.motion)
			else
				pcall(r.EnableMouse, r, was.motion)
			end
		end
	end
	U.given[owner] = nil
	for k, o in pairs(U.selves) do
		if o == owner then
			U.selves[k] = nil
		end
	end
	for k, o in pairs(U.roots) do
		if o == owner then
			U.roots[k] = nil
		end
	end
	Changed()
end

-- (the reload ask, once a session, for any of ours standing in on a game frame dressed meanwhile: MelloUI:AskReload)
function U.AskReload()
	MelloUI:AskReload("Unit Frames is on: type /reload to finish putting the game's unit frames away.")
end

--------------------------------------------------------------------------------
-- A frame's bars' values as text, as the game's (TextStatusBar: its Status Text setting -- the statusText CVar --
-- keeps them shown, else while the bar is under the mouse; statusTextDisplay: the value and its most, the share,
-- both -- the share on the left, the value on the right). The client's string helpers take the secret values as they
-- are (BreakUpLargeNumbers, AbbreviateLargeNumbers, SetFormattedText); the share is the client's own
-- (UnitHealthPercent / UnitPowerPercent) rounded up as the game's through a step curve; "Dead" at none, as the
-- game's. (fr-16's, moved here from Group Frames' party portraits, which call it.)
--   f.texts   { health = { center, left, right }, mana = { center, left, right } }
--   f.unit, f.hovered ("health" / "mana" / nil), f.capNumeric (the game's capNumericDisplay: large numbers short)
--------------------------------------------------------------------------------

local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if ok and not Secret(v) then
		return v
	end
	return nil
end

-- connected (the player always; a member as the game says -- a refused or secret answer counts as connected)
function U.Connected(unit)
	if unit == "player" then
		return true
	end
	return Ask(UnitIsConnected, unit) ~= false
end

-- (2.1.16; the user, 2026-11-07: "unitframes showing around 10% hp even when the person is dead") gone: dead or a ghost,
-- as the game says (a refused or secret answer: not gone; a hunter feigning death: not gone). The one rule of every bar
-- showing a unit's health or power: a gone unit's reads empty, whatever the client still hands out for it (the game's
-- own frames show that as it is; a ghost's can be well above none)
function U.Gone(unit)
	return Ask(UnitIsDeadOrGhost, unit) == true and Ask(rawget(_G, "UnitIsFeignDeath"), unit) ~= true
end

-- what a bar shows of a unit's value (handed on as it is: it may be secret; never tested)
function U.Value(unit, value)
	if U.Gone(unit) then
		return 0
	end
	return value
end

-- true once each time f's unit goes or comes back: a death brings no event of the power's, and may bring none of the
-- health's, so whichever event comes first paints both bars
function U.GoneChanged(f)
	local gone = U.Gone(f.unit)
	local changed = gone ~= (f.gone or false)
	f.gone = gone
	return changed
end

do
	local ceil = { made = false, curve = nil }
	-- (x in (k-1, k] hundredths -> k: the game's math.ceil of the share times 100)
	local function Ceil()
		if ceil.made then
			return ceil.curve
		end
		ceil.made = true
		local CU = rawget(_G, "C_CurveUtil")
		if type(CU) ~= "table" or type(CU.CreateCurve) ~= "function" then
			return nil
		end
		local ok, c = pcall(function()
			local made = CU.CreateCurve()
			local E = rawget(_G, "Enum")
			if E and E.LuaCurveType then
				made:SetType(E.LuaCurveType.Step)
			end
			made:AddPoint(0, 0)
			for k = 1, 100 do
				made:AddPoint((k - 1) / 100 + 1e-7, k)
			end
			return made
		end)
		ceil.curve = ok and c or nil
		return ceil.curve
	end

	local function Share(fn, unit, ...)
		local c = Ceil()
		if not (c and type(fn) == "function") then
			return nil
		end
		local ok, v = pcall(fn, unit, ...)
		return ok and v or nil
	end

	local function Set(fs, fmt, ...)
		if fs then
			pcall(fs.SetFormattedText, fs, fmt, ...)
			fs:Show()
		end
	end

	local function Clear(t)
		for _, fs in pairs(t) do
			fs:SetText("")
			fs:Hide()
		end
	end

	-- (the two settings read once and kept until a frame's CVAR_UPDATE says so -- Units.TextsChanged: a bar's text is
	-- asked on every power tick)
	local cvars = { display = nil, always = false, at = 0 }
	function U.TextsChanged()
		cvars.display = nil
	end
	local function Mode()
		-- (and at most a second old: a change no listener heard -- neither frame on then -- is read in time)
		local now = GetTime()
		if cvars.display == nil or now - cvars.at > 1 then
			cvars.at = now
			local get = type(C_CVar) == "table" and C_CVar.GetCVar or rawget(_G, "GetCVar")
			cvars.display = Ask(get, "statusTextDisplay") or "NUMERIC"
			cvars.always = Ask(get, "statusText") == "1"
		end
		return cvars.display, cvars.always
	end

	local function Big(f, v)
		local short = f.capNumeric and rawget(_G, "AbbreviateLargeNumbers")
		if short then
			local ok, s = pcall(short, v)
			if ok then
				return s
			end
		end
		return BreakUpLargeNumbers(v)
	end

	-- one bar's text (`t`: its center / left / right strings; `power`: the mana bar, its power token)
	local function One(f, t, power, hovered)
		local mode, always = Mode()
		if not (always or hovered) or not t then
			if t then
				Clear(t)
			end
			return
		end
		local unit = f.unit
		local gone = U.Gone(unit)
		local cur, max
		if power then
			cur, max = UnitPower(unit), UnitPowerMax(unit)
		else
			max = UnitHealthMax(unit)
			cur = U.Connected(unit) and UnitHealth(unit) or max
		end
		local plainMax = Num(max)
		Clear(t)
		if plainMax and plainMax <= 0 then
			return
		end
		if not power and f.deadText ~= false and gone then
			-- (f.deadText: a bar's own zero text -- the target's bars show none: its "Dead" is a text of the frame's; false:
			-- no zero text at all, the numbers at none -- the pet's bar, as the game's sets none)
			local dead = f.deadText
			if dead == nil then
				dead = rawget(_G, "DEAD") or "Dead"
			end
			Set(t.center, "%s", dead)
			return
		end
		-- (gone: the numbers say what its bar says, none)
		local value, most = Big(f, gone and 0 or cur), Big(f, max)
		local share
		if mode == "PERCENT" or mode == "BOTH" then
			if gone then
				share = 0
			elseif power then
				share = Share(rawget(_G, "UnitPowerPercent"), unit, nil, false, Ceil())
			else
				share = Share(rawget(_G, "UnitHealthPercent"), unit, false, Ceil())
			end
		end
		if mode == "BOTH" and share ~= nil then
			local okT, _, token = pcall(UnitPowerType, unit)
			if not power or (okT and Text(token) == "MANA") then
				Set(t.left, "%d%%", share)
			end
			Set(t.right, "%s", value)
		elseif mode == "PERCENT" and share ~= nil then
			Set(t.center, "%d%%", share)
		else
			Set(t.center, "%s / %s", value, most)
		end
	end

	function U.Texts(f)
		local t = f and f.texts
		if t then
			local hover = f.hovered
			One(f, t.health, false, hover == "health")
			One(f, t.mana, true, hover == "mana")
		end
	end
end

--------------------------------------------------------------------------------
-- A frame's box of auras on its hover, as the game's (PartyMemberBuffTooltip: PartyMemberFrameMixin:OnEnter puts it
-- at the member's 47,-25, PetFrameMixin:OnEnter at the pet's 60,-35 -- in the game's tooltip border its buffs, up to
-- 16, and on a line under them its debuffs, up to 8, eight a row, 2 apart; shown while it has one; gone once the mouse
-- is on neither): one per frame of ours, made with it, its auras the game's aura container's -- read only while it
-- shows (its groups off else), the count of what it shows our own buttons' (their show and hide), never an aura of the
-- unit's. (fr-16's, moved here from Group Frames' party portraits, which call it.)
--   U.DressAura(b)                 an aura button as the game's party aura (PartyAuraFrameTemplate)
--   U.AuraBox(f, x, y, dress)      f's box (nil: no aura container in this client); dress: its buttons' dresser
--   U.AuraBoxOn(box) / Off(box)    on the frame's OnEnter / OnLeave
--------------------------------------------------------------------------------

do
	local AURA = { size = 15, gap = 2 }
	local BOX = { buffs = 16, debuffs = 8, row = 8, pad = 8 }
	local DEBUFF_BORDER = "Interface\\Buttons\\UI-Debuff-Overlays"   -- (the game's party aura border)
	local BORDER_COORDS = { 0.296875, 0.5703125, 0, 0.515625 }

	local function Call(obj, method, ...)
		local fn = obj and obj[method]
		if type(fn) ~= "function" then
			return false
		end
		return (pcall(fn, obj, ...))
	end

	-- (PartyAuraFrameTemplate: 15 square, its cooldown reversed and without numbers, its count at the bottom right, the
	-- debuff border in its dispel type's colour)
	function U.DressAura(b)
		b:SetSize(AURA.size, AURA.size)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(b)
		local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		cd:SetPoint("CENTER", b, "CENTER", 0, -1)
		cd:SetSize(AURA.size, AURA.size)
		Call(cd, "SetReverse", true)
		Call(cd, "SetHideCountdownNumbers", true)
		local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		count:SetJustifyH("RIGHT")
		count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 5, 0)
		local border = b:CreateTexture(nil, "OVERLAY")
		border:SetTexture(DEBUFF_BORDER)
		border:SetTexCoord(BORDER_COORDS[1], BORDER_COORDS[2], BORDER_COORDS[3], BORDER_COORDS[4])
		border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
		border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
		Call(b, "SetIcon", icon)
		Call(b, "SetDurationCooldown", cd)
		Call(b, "SetApplicationCount", count)
		local E = rawget(_G, "Enum")
		local styles = type(E) == "table" and E.CustomAuraButtonDispelTypeTextureStyle
		local style = type(styles) == "table" and styles.PreserveAsset or nil
		if style ~= nil then
			Call(b, "AddDispelTypeTexture", border, { style = style, showWhenHarmful = true, showWithoutDispelType = true })
		end
	end

	local function Groups(box, on)
		Call(box.auras, "SetAuraGroupEnabled", "buffs", on)
		Call(box.auras, "SetAuraGroupEnabled", "debuffs", on)
	end

	-- shown while its frame (or itself) is under the mouse and it holds an aura
	local function Seen(box)
		box:SetShown((box.on and next(box.shown) ~= nil) and true or false)
	end

	local OnButton = Shared("a frame's aura box: a button shown or hidden", function(b)
		local box = b.box
		if box then
			box.shown[b] = b:IsShown() or nil
			Seen(box)
		end
	end, "script")

	local OnUpdate = Shared("a frame's aura box: the mouse still on it or its frame", function(box)
		if not (box.member:IsMouseOver() or box:IsMouseOver()) then
			box.on = false
			Groups(box, false)
			box:Hide()
		end
	end, "script")

	function U.AuraBox(f, x, y, dress)
		local ok, box = pcall(CreateFrame, "Frame", nil, UIParent, "TooltipBackdropTemplate")
		local okC, c = false, nil
		if ok then
			okC, c = pcall(CreateFrame, "AuraContainer", nil, box, "CustomAuraContainerTemplate")
		end
		if not (okC and type(c) == "table" and type(c.AddAuraGroup) == "function") then
			return nil
		end
		dress = dress or U.DressAura
		box:Hide()
		box:SetFrameStrata("TOOLTIP")
		box:EnableMouse(true)
		box.member, box.auras, box.shown, box.on = f, c, {}, false
		c:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
		box:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
		box:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
		Call(c, "SetFlowLayoutPadding", BOX.pad, BOX.pad, BOX.pad, BOX.pad)
		Call(c, "SetFlowLayoutMaximumLineSize", BOX.row * AURA.size + (BOX.row - 1) * AURA.gap)
		local function DressBoxAura(b)
			dress(b)
			b.box = box
			Perf.HookScript(b, "OnShow", OnButton)
			Perf.HookScript(b, "OnHide", OnButton)
		end
		for _, g in ipairs({ { "buffs", "HELPFUL", BOX.buffs }, { "debuffs", "HARMFUL", BOX.debuffs } }) do
			Call(c, "AddAuraGroup", g[1], g[2], { maxFrameCount = g[3], initializeFrame = DressBoxAura,
				layout = { elementSpacing = AURA.gap, lineSpacing = AURA.gap, elementWidth = AURA.size,
					elementHeight = AURA.size, forceNewLine = g[1] == "debuffs" } })
			Call(c, "SetAuraGroupEnabled", g[1], false)
		end
		Call(c, "SetUnit", f.unit)
		Perf.SetScript(box, "OnUpdate", OnUpdate)
		return box
	end

	function U.AuraBoxOn(box)
		if box then
			box.on = true
			Groups(box, true)
			Seen(box)
		end
	end

	-- (off now unless it shows -- then its own update lets it go once the mouse is on neither)
	function U.AuraBoxOff(box)
		if box and not box:IsShown() then
			box.on = false
			Groups(box, false)
		end
	end
end

--------------------------------------------------------------------------------
-- The player frame of ours (stage 1). Its parts as the game's PlayerFrame.xml (client 70425) lays them, with
-- Camelot's PlayerFrame.lua over it (the name centred, 116 wide, at 149,-37; the level in its circle; the PvP badge
-- the circle's faction icon at 22,-65 with its timer to its left) and PlayerFrame_ToPlayerArt's visuals (the health
-- bar's box 124 x 15 at 87,-46, the bar 20 high 3 above it in its mask; the mana bar 124 x 10 at 87,-61; the flash
-- and status glow), the game's own pictures (atlases) on each.
--------------------------------------------------------------------------------

local P = { frame = nil, wanted = false, standing = false, usedGame = false }
U.P = P

local ART = {
	frame = "UI-HUD-UnitFrame-Player-PortraitOn",
	vehicle = "UI-HUD-UnitFrame-Player-PortraitOn-Vehicle",
	res = "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource",
	flash = "UI-HUD-UnitFrame-Player-PortraitOn-InCombat",
	status = "UI-HUD-UnitFrame-Player-PortraitOn-Status",
	mask = "UI-HUD-UnitFrame-Player-Portrait-Mask",
	health = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
	healthMask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask",
	mana = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
	manaMask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask",
	circle = "UI-HUD-UnitFrame-SmallCircle",
	pvp = "UI-HUD-UnitFrame-SmallCircle-Alliance",
	leader = "UI-HUD-UnitFrame-Player-Group-LeaderIcon",
	guide = "UI-HUD-UnitFrame-Player-Group-GuideIcon",
	role = "roleicon-tiny-tank",
	corner = "UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment",
	attack = "UI-HUD-UnitFrame-Player-CombatIcon",
	rest = "UI-HUD-UnitFrame-Player-Rest-Flipbook",
	groupLeft = "UI-HUD-UnitFrame-Player-GroupIndicatorLeft",
	groupRight = "UI-HUD-UnitFrame-Player-GroupIndicatorRight",
	groupMid = "_UI-HUD-UnitFrame-Player-GroupIndicatorMid",
}
-- (the game's status glow pulse, PlayerFrame_OnUpdate: from full to 55/255 and back, half a second each way)
local PULSE = { low = 55 / 255, half = 0.5 }

local function Atlas(t, atlas, size)
	if atlas then
		pcall(t.SetAtlas, t, atlas, size and true or false)
	end
end

local function Tex(parent, layer, sub, atlas, size)
	local t = parent:CreateTexture(nil, layer, nil, sub or 0)
	Atlas(t, atlas, size)
	return t
end

local function Crisp(t)
	if not t then
		return
	end
	if t.SetTexelSnappingBias then
		t:SetTexelSnappingBias(0)
	end
	if t.SetSnapToPixelGrid then
		t:SetSnapToPixelGrid(false)
	end
end

local function Font(parent, layer, sub, object)
	local fs = parent:CreateFontString(nil, layer)
	local font = rawget(_G, object)
	if font then
		fs:SetFontObject(font)
	end
	fs:SetDrawLayer(layer, sub or 0)
	return fs
end

local function Holder(parent, levelOf)
	local h = CreateFrame("Frame", nil, parent)
	h:SetAllPoints(parent)
	if levelOf then
		h:SetFrameLevel(levelOf:GetFrameLevel())
	end
	return h
end

-- a region's anchors copied from the game's twin where it reads plainly (`map`: the game's frames -> ours), else
-- `fallback` laid (the XML's own: setAllPoints and anchors on one frame, the rest loop's, resolve as the client does)
local function CopyPoints(region, game, map, fallback)
	local ok, n = pcall(function() return game:GetNumPoints() end)
	if ok and type(n) == "number" and not Secret(n) and n > 0 then
		local points = {}
		for i = 1, n do
			local okP, point, rel, relPoint, x, y = pcall(game.GetPoint, game, i)
			if not okP or Secret(point) or Secret(x) or Secret(y) then
				points = nil
				break
			end
			local to = rel and map[rel]
			if rel and not to then
				points = nil
				break
			end
			points[i] = { point, to, relPoint, x, y }
		end
		if points then
			region:ClearAllPoints()
			for _, p in ipairs(points) do
				region:SetPoint(p[1], p[2], p[3], p[4], p[5])
			end
			return
		end
	end
	fallback()
end

-- a bar's fill (nil where a client -- a test's world -- has none) and a mask added to a texture that has one
local function FillOf(bar)
	local fn = bar.GetStatusBarTexture
	return type(fn) == "function" and fn(bar) or nil
end

local function Masked(tex, mask)
	if tex and mask and tex.AddMaskTexture then
		-- (once: a mask added again masks twice -- its soft edge darker)
		if tex.GetNumMaskTextures and tex.GetMaskTexture then
			for i = 1, tex:GetNumMaskTextures() do
				if tex:GetMaskTexture(i) == mask then
					return
				end
			end
		end
		tex:AddMaskTexture(mask)
	end
end

local function Bar(parent, w, h)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetSize(w, h)
	b:SetFrameLevel(parent:GetFrameLevel())   -- (useParentLevel)
	b:SetMinMaxValues(0, 1)
	b:SetValue(1)
	return b
end

-- a bar's three texts (TextStatusBar's: the value centred, the share on the left, the value on the right) on
-- `parent`; `at` the template's own offsets where they differ ({ center = x, left = x, right = x })
local function TextsOn(bar, parent, at)
	local t = {}
	at = at or {}
	for key, def in pairs({ center = { "CENTER", 0 }, left = { "LEFT", 2 }, right = { "RIGHT", -2 } }) do
		local fs = Font(parent, "OVERLAY", 1, "TextStatusBarText")
		fs:SetPoint(def[1], parent, def[1], at[key] or def[2], 0)
		fs:Hide()
		t[key] = fs
	end
	return t
end

function P.Build()
	local game = _G.PlayerFrame
	if P.frame or type(game) ~= "table" or InCombatLockdown() then
		return P.frame
	end
	local f = CreateFrame("Button", "MelloUIPlayerFrame", game, "SecureUnitButtonTemplate")
	U.mine[f] = true
	f:SetAllPoints(game)
	f:SetFrameLevel(game:GetFrameLevel())
	f:SetHitRectInsets(6, 0, 4, 9)
	f:SetAttribute("unit", "player")
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:SetAttribute("toggleForVehicle", true)
	f:RegisterForClicks("AnyUp")
	MelloUI:ClickCast(f)   -- (2.1.21: click-cast addons -- Clique -- on it, as on the game's own frame)
	f.unit, f.frameType, f.disablePortraitMask, f.state = "player", "Player", true, "player"
	-- (deadText false: its bar's numbers at none -- the game's player health bar has no zero text)
	f.capNumeric, f.deadText = true, false
	f:Hide()
	local gc = rawget(game, "PlayerFrameContainer")
	local gContent = rawget(game, "PlayerFrameContent")
	local gMain = gContent and rawget(gContent, "PlayerFrameContentMain")
	local gCtx = gContent and rawget(gContent, "PlayerFrameContentContextual")
	local map = { [game] = f }

	-- the art: the portrait in its mask, the frame's picture (its vehicle and class resource twins), the flash
	local c = Holder(f)
	f.PlayerFrameContainer = c
	map[gc or c] = c
	local portrait = Tex(c, "BACKGROUND", 1)
	portrait:SetSize(60, 60)
	portrait:SetPoint("TOPLEFT", c, "TOPLEFT", 24, -19)
	c.PlayerPortrait = portrait
	local mask = c:CreateMaskTexture()
	Atlas(mask, ART.mask)
	mask:SetSize(60, 60)
	mask:SetPoint("TOPLEFT", c, "TOPLEFT", 24, -19)
	Masked(portrait, mask)
	c.PlayerPortraitMask = mask
	local vehicle = Tex(c, "BACKGROUND", 2, ART.vehicle, true)
	vehicle:SetPoint("CENTER", c, "CENTER", -2, 0)
	vehicle:Hide()
	c.VehicleFrameTexture = vehicle
	local art = Tex(c, "BACKGROUND", 2, ART.frame, true)
	art:SetPoint("CENTER", c, "CENTER", 0, 0)
	Crisp(art)
	c.FrameTexture = art
	local res = Tex(c, "BACKGROUND", 2, ART.res, true)
	res:SetPoint("CENTER", c, "CENTER", 0, -1.5)
	res:Hide()
	Crisp(res)
	c.AlternatePowerFrameTexture = res
	local flash = Tex(c, "OVERLAY", 0, ART.flash, true)
	flash:SetPoint("CENTER", c, "CENTER", 0, 0)
	flash:Hide()
	Crisp(flash)
	c.FrameFlash = flash
	if gc then
		map[rawget(gc, "PlayerPortrait") or portrait] = portrait
	end

	-- the content: the name, the status glow, the level in its circle, the PvP badge, the numbers, the bars
	local content = Holder(f)
	f.PlayerFrameContent = content
	local main = Holder(content)
	content.PlayerFrameContentMain = main
	if gContent then
		map[gContent] = content
	end
	if gMain then
		map[gMain] = main
	end
	local name = Font(main, "OVERLAY", 1, "GameFontNormalSmall")
	name:SetSize(116, 12)
	name:SetJustifyH("CENTER")
	name:SetJustifyV("MIDDLE")
	name:SetPoint("CENTER", main, "TOPLEFT", 149, -37)
	name:SetWordWrap(false)
	f.name = name
	main.Name = name
	local status = Tex(main, "OVERLAY", 2, ART.status, true)
	status:SetPoint("TOPLEFT", c, "TOPLEFT", 17, -14)
	status:Hide()
	main.StatusTexture = status
	local circle = Tex(main, "OVERLAY", 3, ART.circle, true)
	circle:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 13, 7)
	main.LevelBackgroundCircle = circle
	local pvp = Tex(main, "OVERLAY", 4, ART.pvp, true)
	pvp:SetScale(0.8)
	pvp:SetPoint("TOP", main, "TOPLEFT", 22, -65)
	pvp:Hide()
	main.PvpBackgroundIcon = pvp
	local level = Font(main, "OVERLAY", 4, "WhiteLargeNumberFont")
	if not rawget(_G, "WhiteLargeNumberFont") then
		level:SetFontObject(rawget(_G, "NumberFont_GameLarge") or rawget(_G, "GameFontHighlightLarge"))
	end
	level:SetJustifyH("RIGHT")
	level:SetJustifyV("MIDDLE")
	level:SetPoint("CENTER", circle, "CENTER", 0, -0.5)
	f.levelText = level
	main.LevelText = level
	local hit = Holder(main, main)
	main.HitIndicator = hit
	local hitText = Font(hit, "OVERLAY", 0, "NumberFontNormalHuge")
	hitText:SetPoint("CENTER", hit, "TOPLEFT", 54, -50)
	hitText:Hide()
	hit.HitText = hitText

	local hc = CreateFrame("Frame", nil, main)
	hc:SetFrameLevel(main:GetFrameLevel())
	hc:SetSize(124, 15)
	hc:SetPoint("TOPLEFT", main, "TOPLEFT", 87, -46)
	main.HealthBarsContainer = hc
	local health = Bar(hc, 124, 20)
	health:SetPoint("TOPLEFT", hc, "TOPLEFT", 0, 3)
	health:SetStatusBarTexture(ART.health)
	local fill = FillOf(health)
	if fill then
		fill:SetDrawLayer("BACKGROUND", 0)
	end
	Crisp(fill)
	health.Background = Tex(health, "BACKGROUND", 2)
	health.Background:SetAllPoints(health)
	health.Background:SetColorTexture(0, 0, 0, 1)
	health.Background:Hide()
	hc.HealthBar = health
	local texts = TextsOn(health, hc)
	hc.HealthBarText, hc.LeftText, hc.RightText = texts.center, texts.left, texts.right
	-- (TextStatusBar's own keys on the bar, as SetBarText lays them: Bar Text fades these and hangs its value on them)
	health.TextString, health.LeftText, health.RightText = texts.center, texts.left, texts.right
	local hmask = hc:CreateMaskTexture()
	Atlas(hmask, ART.healthMask, true)
	hmask:SetHeight(32)
	hmask:SetPoint("TOPLEFT", health, "TOPLEFT", -2, 6)
	Masked(fill, hmask)
	Masked(health.Background, hmask)
	hc.HealthBarMask = hmask
	health.unit, health.unitFrame, health.lockColor, health.capNumericDisplay = "player", f, true, true

	local area = Holder(main, main)
	main.ManaBarArea = area
	local mana = Bar(area, 124, 10)
	mana:SetPoint("TOPLEFT", area, "TOPLEFT", 87, -61)
	mana:SetStatusBarTexture(ART.mana)
	Crisp(FillOf(mana))
	area.ManaBar = mana
	local mtexts = TextsOn(mana, mana)
	mana.ManaBarText, mana.LeftText, mana.RightText = mtexts.center, mtexts.left, mtexts.right
	mana.TextString = mtexts.center
	local mmask = mana:CreateMaskTexture()
	Atlas(mmask, ART.manaMask, true)
	mmask:SetWidth(128)
	mmask:SetPoint("TOPLEFT", mana, "TOPLEFT", -2, 2)
	Masked(FillOf(mana), mmask)
	mana.ManaBarMask = mmask
	mana.unit, mana.unitFrame, mana.lockColor, mana.capNumericDisplay = "player", f, true, true
	local alt = Holder(main, main)
	alt:Hide()
	main.AlternatePowerBarArea = alt
	f.texts = { health = texts, mana = mtexts }

	-- the contextual: the leader / guide crown, the role, the corner piece and the combat swords, the PvP icons and
	-- timer, the ready check, the rest loop, the group number
	local ctx = Holder(content)
	content.PlayerFrameContentContextual = ctx
	if gCtx then
		map[gCtx] = ctx
	end
	ctx.LeaderIcon = Tex(ctx, "OVERLAY", 1, ART.leader, true)
	ctx.LeaderIcon:SetPoint("TOPLEFT", ctx, "TOPLEFT", 86, -10)
	ctx.LeaderIcon:Hide()
	ctx.GuideIcon = Tex(ctx, "OVERLAY", 1, ART.guide, true)
	ctx.GuideIcon:SetPoint("TOPLEFT", ctx, "TOPLEFT", 86, -10)
	ctx.GuideIcon:Hide()
	ctx.RoleIcon = Tex(ctx, "OVERLAY", 1, ART.role)
	ctx.RoleIcon:SetSize(12, 12)
	ctx.RoleIcon:SetPoint("TOPLEFT", ctx, "TOPLEFT", 196, -27)
	ctx.RoleIcon:Hide()
	ctx.PlayerPortraitCornerIcon = Tex(ctx, "OVERLAY", 1, ART.corner, true)
	ctx.PlayerPortraitCornerIcon:SetPoint("TOPLEFT", ctx, "TOPLEFT", 58.5, -53.5)
	ctx.PVPIcon = Tex(ctx, "OVERLAY", 2)
	ctx.PVPIcon:SetPoint("TOP", ctx, "TOPLEFT", 25, -50)
	ctx.PVPIcon:Hide()
	ctx.PrestigePortrait = Tex(ctx, "OVERLAY", 2)
	ctx.PrestigePortrait:SetSize(50, 52)
	ctx.PrestigePortrait:SetPoint("TOPLEFT", ctx, "TOPLEFT", -2, -38)
	ctx.PrestigePortrait:Hide()
	ctx.AttackIcon = Tex(ctx, "OVERLAY", 3, ART.attack, true)
	ctx.AttackIcon:SetPoint("TOPLEFT", ctx, "TOPLEFT", 64, -62)
	ctx.AttackIcon:Hide()
	ctx.PrestigeBadge = Tex(ctx, "OVERLAY", 3)
	ctx.PrestigeBadge:SetSize(30, 30)
	ctx.PrestigeBadge:SetPoint("CENTER", ctx.PrestigePortrait, "CENTER", 0, 0)
	ctx.PrestigeBadge:Hide()
	local timer = Font(ctx, "OVERLAY", 4, "GameFontNormalSmall")
	timer:SetPoint("RIGHT", pvp, "LEFT", 2, 0)
	timer:Hide()
	ctx.PvpTimerText = timer
	local okR, rc = pcall(CreateFrame, "Frame", nil, ctx, "ReadyCheckStatusTemplate")
	if okR and type(rc) == "table" then
		rc:SetSize(40, 40)
		rc:SetPoint("CENTER", portrait, "CENTER", 0, 0)
		rc:SetFrameLevel(rc:GetFrameLevel() + 2)
		rc:Hide()
		ctx.ReadyCheck = rc
	end
	local loop = CreateFrame("Frame", nil, ctx)
	loop:SetSize(20, 20)
	CopyPoints(loop, gCtx and rawget(gCtx, "PlayerRestLoop") or loop, map, function()
		loop:ClearAllPoints()
		loop:SetPoint("TOPLEFT", ctx, "TOPLEFT", 64, -6)
	end)
	loop:Hide()
	local zzz = Tex(loop, "ARTWORK", 0, ART.rest)
	zzz:SetSize(30, 30)
	zzz:SetPoint("CENTER", loop, "CENTER", 0, 0)
	loop.RestTexture = zzz
	-- (its flipbook made through MelloUI.Anim, played by it: Reduce Motion aware)
	local A = MelloUI.Anim
	local group = A and A.Group and A:Group(loop, "REPEAT")
	if group and group.SetToFinalAlpha then
		group:SetToFinalAlpha(true)
	end
	local okF, flip = false, nil
	if group then
		okF, flip = pcall(group.CreateAnimation, group, "FlipBook")
	end
	if okF and flip then
		flip:SetTarget(zzz)
		flip:SetDuration(1.5)
		flip:SetOrder(1)
		pcall(flip.SetFlipBookRows, flip, 7)
		pcall(flip.SetFlipBookColumns, flip, 6)
		pcall(flip.SetFlipBookFrames, flip, 42)
		pcall(flip.SetFlipBookFrameWidth, flip, 0)
		pcall(flip.SetFlipBookFrameHeight, flip, 0)
		pcall(flip.SetSmoothing, flip, "NONE")
	end
	loop.PlayerRestLoopAnim = group
	ctx.PlayerRestLoop = loop
	local gi = CreateFrame("Frame", nil, ctx)
	gi:SetSize(10, 16)
	gi:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", 210, -29)
	gi:Hide()
	gi.GroupIndicatorLeft = Tex(gi, "BACKGROUND", 0, ART.groupLeft, true)
	gi.GroupIndicatorLeft:SetPoint("TOPLEFT", gi, "TOPLEFT", 0, 0)
	gi.GroupIndicatorRight = Tex(gi, "BACKGROUND", 0, ART.groupRight, true)
	gi.GroupIndicatorRight:SetPoint("TOPRIGHT", gi, "TOPRIGHT", 0, 0)
	local mid = Tex(gi, "BACKGROUND", 0, ART.groupMid, true)
	mid:SetPoint("LEFT", gi.GroupIndicatorLeft, "RIGHT", 0, 0)
	mid:SetPoint("RIGHT", gi.GroupIndicatorRight, "LEFT", 0, 0)
	gi.Text = Font(gi, "BACKGROUND", 0, "GameFontHighlightSmall")
	gi.Text:SetAlpha(0.7)
	gi.Text:SetPoint("LEFT", gi, "LEFT", 20, 2)
	ctx.GroupIndicator = gi

	-- the game's own keys of a unit frame (UnitFrame_Initialize's) for the modules that read them
	f.portrait, f.healthbar, f.manabar = portrait, health, mana
	f.threatIndicator = flash
	flash.unit, flash.feedbackUnit = "player", "player"
	f.feedbackText, f.feedbackFontHeight = hitText, 30   -- (CombatFeedback_Initialize's)
	P.frame = f
	P.Scripts(f)
	return f
end

--------------------------------------------------------------------------------
-- What it shows, as the game's code shows it (PlayerFrame.lua, UnitFrame.lua): read on the unit's events only
--------------------------------------------------------------------------------

local function Main(f)
	return f.PlayerFrameContent.PlayerFrameContentMain
end
local function Ctx(f)
	return f.PlayerFrameContent.PlayerFrameContentContextual
end

local function Yes(fn, ...)
	return Ask(fn, ...) == true
end

-- A unit's name on one of our frames, as the game's UnitFrame_Update has it. (2.1.16; the user, 2026-11-07, in Ragefire
-- Chasm: "name on the target of target is not correct", a mob's old name over the right portrait and bars) The game can
-- hand a name out as a secret; GetUnitName's own test of it raises in our code, a pcall swallowed that, and the text kept
-- the last name it had. MelloUI:UnitNameAs reads it either way; a secret goes to SetText as it is, never compared; no
-- name at all leaves the text empty, never an old one. `shape(text, unit)` changes a plain name (the follower prefix).
function U.LayName(f, unit, shape)
	local text = MelloUI:UnitNameAs(unit, "both")
	if Secret(text) then
		pcall(f.name.SetText, f.name, text)
		return
	end
	if text ~= nil and shape then
		text = shape(text, unit)
	end
	pcall(f.name.SetText, f.name, text or "")
end

function P.Name(f)
	U.LayName(f, "player")
	U.Notify("UnitFrame_Update", f)
end

function P.Portrait(f)
	local portrait = f.portrait
	local replace = rawget(_G, "UnitFrame_ShouldReplacePortrait")
	if replace and Ask(replace, f) == true then
		local _, class = UnitClass("player")
		local atlas = class and Ask(rawget(_G, "GetClassAtlas"), class)
		if atlas then
			Atlas(portrait, atlas)
			U.Notify("UnitFramePortrait_Update", f)
			return
		end
	end
	pcall(SetPortraitTexture, portrait, "player", true)
	U.Notify("UnitFramePortrait_Update", f)
end

function P.Health(f)
	local hb = f.healthbar
	pcall(hb.SetMinMaxValues, hb, 0, UnitHealthMax("player"))
	pcall(hb.SetValue, hb, U.Value("player", UnitHealth("player")))
	U.Notify("UnitFrameHealthBar_Update", hb, "player")
	U.Texts(f)
end

function P.Power(f)
	local mb = f.manabar
	pcall(mb.SetMinMaxValues, mb, 0, UnitPowerMax("player"))
	pcall(mb.SetValue, mb, U.Value("player", UnitPower("player")))
	U.Texts(f)
end

-- the power's picture (UnitFrameManaBar_UpdateType: "UI-HUD-UnitFrame-Player-PortraitOn-Bar-<Mana|Rage|...>", the
-- dead or a ghost's grey at half)
function P.PowerType(f)
	local mb = f.manabar
	local okT, powerType, token, altR, altG, altB = pcall(UnitPowerType, "player")
	token = okT and Text(token) or nil
	local colours = rawget(_G, "PowerBarColor")
	local info = token and type(colours) == "table" and colours[token] or nil
	-- (2.1.9: a colour picked on Look > Colours, on the colourable fill)
	local pr, pg, pb = MelloUI.Colours.PowerPicked(token)
	if pr then
		mb:SetStatusBarTexture(ART.mana .. "-Status")
		mb:SetStatusBarColor(pr, pg, pb)
	elseif type(info) == "table" and info.atlasElementName then
		mb:SetStatusBarTexture("UI-HUD-UnitFrame-Player-PortraitOn-Bar-" .. info.atlasElementName)
		mb:SetStatusBarColor(1, 1, 1)
	elseif type(info) == "table" and info.atlas then
		mb:SetStatusBarTexture(info.atlas)
		mb:SetStatusBarColor(1, 1, 1)
	else
		mb:SetStatusBarColor(1, 1, 1)
		if Num(altR) then
			mb:SetStatusBarTexture(ART.mana .. "-Status")
			mb:SetStatusBarColor(altR, altG, altB)
		else
			mb:SetStatusBarTexture(ART.mana)
		end
	end
	local fill = FillOf(mb)
	Crisp(fill)
	-- (a new picture keeps the mask)
	Masked(fill, mb.ManaBarMask)
	local gone = Yes(UnitIsDead, "player") or Yes(UnitIsGhost, "player")
	if fill then
		fill:SetDesaturated(gone)
		fill:SetAlpha(gone and 0.5 or 1)
	end
	if okT and not Secret(powerType) then
		mb.powerType, mb.powerToken = powerType, token
	end
	U.Notify("UnitFrameManaBar_UpdateType", mb)
	P.Power(f)
end

-- the level (Camelot: white; green while it is scaled to another), shown where the role icon is not
function P.Level(f)
	local level, effective = Ask(UnitLevel, "player"), Ask(UnitEffectiveLevel, "player")
	local fs = f.levelText
	if effective and level and effective ~= level then
		fs:SetVertexColor(0.1, 1, 0.1, 1)
	else
		local get = rawget(_G, "PlayerFrame_GetLevelRGBA")
		local okC, r, g, b, a = pcall(get or function() return 1, 1, 1, 1 end)
		if okC and Num(r) then
			fs:SetVertexColor(r, g, b, a)
		else
			fs:SetVertexColor(1, 1, 1, 1)
		end
	end
	local shown = effective or level
	if shown ~= nil then
		fs:SetText(shown)
	end
end

-- the role (Camelot's PlayerFrame_ShowRoleIconInsideInstances: never): the level shown
function P.Roles(f)
	local ctx = Ctx(f)
	local inside = rawget(_G, "PlayerFrame_ShowRoleIconInsideInstances")
	local hasIcon = false
	local _, kind = GetInstanceInfo()
	if kind ~= "none" and inside and Ask(inside) == true then
		local role = Ask(UnitGroupRolesAssigned, "player")
		local atlas = (role == "TANK" and "roleicon-tiny-tank") or (role == "HEALER" and "roleicon-tiny-healer")
			or (role == "DAMAGER" and "roleicon-tiny-dps") or nil
		if atlas then
			Atlas(ctx.RoleIcon, atlas)
			hasIcon = true
		end
	end
	ctx.RoleIcon:SetShown(hasIcon)
	f.levelText:SetShown(not hasIcon)
	U.Notify("PlayerFrame_UpdateRolesAssigned")
end

function P.Leader(f)
	local ctx = Ctx(f)
	if Yes(UnitIsGroupLeader, "player") then
		local lfg = Yes(HasLFGRestrictions)
		ctx.LeaderIcon:SetShown(not lfg)
		ctx.GuideIcon:SetShown(lfg)
	else
		ctx.LeaderIcon:Hide()
		ctx.GuideIcon:Hide()
	end
end

-- the rest loop (its flipbook through MelloUI.Anim: under Reduce Motion its first picture, still)
local function RestLoop(f, on)
	local loop = Ctx(f).PlayerRestLoop
	local A, group = MelloUI.Anim, loop.PlayerRestLoopAnim
	loop:SetShown(on and true or false)
	if not (A and group) then
		return
	end
	if on then
		A:PlayGroup(group)
	else
		A:StopGroup(group)
	end
end

-- a glow's pulse (the game's OnUpdate's: the player's status glow, the pet's attack glow -- from full to 55/255 and
-- back, half a second each way): an engine BOUNCE while it shows (MelloUI.Anim:Pulse, still at full under Reduce
-- Motion), never an OnUpdate. One for every frame of ours (Units.Parts.Pulse(f, region, on): f keeps the pulse)
local function GlowPulse(f, region, on)
	local A = MelloUI.Anim
	if not (A and A.Pulse) then
		return
	end
	if on then
		f.pulse = A:Pulse(region, PULSE.low, 1, PULSE.half, 1)
	elseif f.pulse then
		A:StopGroup(f.pulse)
		region:SetAlpha(1)
	end
end
local function Pulse(f, on)
	GlowPulse(f, Main(f).StatusTexture, on)
end

-- (PlayerFrame_UpdateStatus, 70425's order: attacking, resting, in a fight, else)
function P.Status(f)
	local ctx, status = Ctx(f), Main(f).StatusTexture
	local attack, corner = ctx.AttackIcon, ctx.PlayerPortraitCornerIcon
	if f.inCombat then
		status:SetVertexColor(1, 0, 0, 1)
		status:Show()
		attack:Show()
		corner:Hide()
		RestLoop(f, false)
	elseif Yes(rawget(_G, "IsResting")) then
		status:SetVertexColor(1, 0.88, 0.25, 1)
		status:Show()
		attack:Hide()
		corner:Show()
		RestLoop(f, true)
	elseif f.onHateList then
		attack:Show()
		corner:Hide()
		RestLoop(f, false)
	else
		status:Hide()
		attack:Hide()
		corner:Show()
		RestLoop(f, false)
	end
	local okS, shown = pcall(status.IsShown, status)
	Pulse(f, okS and shown == true)
end

-- the PvP badge (the game's own secret-safe helper, Camelot's elements: the circle's faction icon) and its timer
local Timer
function P.PvP(f)
	local main = Main(f)
	local util = rawget(_G, "UnitFrameUtil")
	local info
	if type(util) == "table" and type(util.UpdateUnitPvPIndicator) == "function" then
		pcall(util.UpdateUnitPvPIndicator, { pvpIcon = main.PvpBackgroundIcon }, "player", true)
		local okI, i = pcall(util.GetUnitPvPIndicatorDisplayInfo, "player", true)
		info = okI and i or nil
	end
	local ffa = info and Ask(function() return info.isFreeForAll end)
	local showIcon = info and Ask(function() return info.showPvPIcon end)
	if ffa or showIcon == false then
		Ctx(f).PvpTimerText:Hide()
		f.timeLeft = nil
		Timer(f)
	end
end

local OnTimer = Shared("your player frame's PvP timer (while it runs)", function(self, elapsed)
	local f = P.frame
	local fs = f and Ctx(f).PvpTimerText
	if not (f and f.timeLeft) then
		self:SetScript("OnUpdate", nil)
		if fs then
			fs:Hide()
		end
		return
	end
	f.timeLeft = f.timeLeft - elapsed * 1000
	if f.timeLeft < 0 then
		fs:Hide()
		f.timeLeft = nil
		self:SetScript("OnUpdate", nil)
		return
	end
	local fmt = rawget(_G, "SecondsToTimeAbbrev")
	if fmt then
		pcall(fs.SetFormattedText, fs, fmt(math.floor(f.timeLeft / 1000)))
	end
end, "script")

Timer = function(f)
	local holder = Ctx(f).PlayerRestLoop:GetParent()
	if f.timeLeft then
		holder:SetScript("OnUpdate", OnTimer)
	else
		holder:SetScript("OnUpdate", nil)
	end
end

function P.PvPTimer(f)
	local fs = Ctx(f).PvpTimerText
	if Yes(rawget(_G, "IsPVPTimerRunning")) then
		fs:Show()
		f.timeLeft = Num(Ask(rawget(_G, "GetPVPTimer")))
	else
		fs:Hide()
		f.timeLeft = nil
	end
	Timer(f)
end

function P.Ready(f)
	local rc = Ctx(f).ReadyCheck
	if not rc then
		return
	end
	local state = Ask(GetReadyCheckStatus, "player")
	if state == "ready" then
		pcall(rawget(_G, "ReadyCheck_Confirm"), rc, 1)
	elseif state == "notready" then
		pcall(rawget(_G, "ReadyCheck_Confirm"), rc, 0)
	elseif state then
		pcall(rawget(_G, "ReadyCheck_Start"), rc)
	else
		rc:Hide()
	end
end

function P.Group(f)
	local gi = Ctx(f).GroupIndicator
	gi:Hide()
	if not Yes(IsInRaid) then
		return
	end
	local me = Ask(UnitName, "player")
	local n = Num(Ask(GetNumGroupMembers)) or 0
	for i = 1, math.min(n, rawget(_G, "MAX_RAID_MEMBERS") or 40) do
		local okR, who, _, subgroup = pcall(rawget(_G, "GetRaidRosterInfo"), i)
		if okR and not Secret(who) and who == me and Num(subgroup) then
			gi.Text:SetText((rawget(_G, "GROUP") or "Group") .. " " .. subgroup)
			gi:SetWidth((Num(gi.Text:GetWidth()) or 30) + 40)
			gi:Show()
			break
		end
	end
end

-- the threat flash (UnitFrame_UpdateThreatIndicator: the unit's own threat -- the player's, the pet's (Units.Parts.Threat,
-- stage 4); a secret one shows none)
function P.Threat(f)
	local flash, unit = f.threatIndicator, f.unit or "player"
	local okS, s = pcall(rawget(_G, "UnitThreatSituation"), unit)
	local status = okS and Num(s) or nil
	if Yes(rawget(_G, "IsThreatWarningEnabled")) and not Yes(UnitIsDead, unit) and status and status > 0 then
		local okC, r, g, b = pcall(rawget(_G, "GetThreatStatusColor"), status)
		if okC and Num(r) then
			flash:SetVertexColor(r, g, b)
		end
		flash:Show()
	else
		flash:Hide()
	end
end

-- the numbers on the portrait (CombatFeedback: the game's own helpers on our text -- f.feedbackText; their fade while
-- one shows only, on `runner`, a frame of ours: the player's HitIndicator, the pet's text holder). One for every frame
-- of ours: Units.Feedback(f, runner, event, flags, amount, kind)
local OnFeedback = Shared("your unit frames' portrait numbers (while one shows)", function(self, elapsed)
	local f = self.owner
	if not (f and f.feedbackText) then
		self:SetScript("OnUpdate", nil)
		return
	end
	pcall(rawget(_G, "CombatFeedback_OnUpdate"), f, elapsed)
	if not f.feedbackText:IsShown() then
		self:SetScript("OnUpdate", nil)
	end
end, "script")

function U.Feedback(f, runner, event, flags, amount, kind)
	local fn = rawget(_G, "CombatFeedback_OnCombatEvent")
	if type(fn) ~= "function" or not runner then
		return
	end
	local ok = pcall(fn, f, event, flags, amount, kind)
	if ok then
		runner.owner = f
		runner:SetScript("OnUpdate", OnFeedback)
	end
end

function P.Feedback(f, event, flags, amount, kind)
	U.Feedback(f, Main(f).HitIndicator, event, flags, amount, kind)
end

-- the art as PlayerFrame_ToPlayerArt lays it (the class resource picture while the game's class bar shows: never on
-- Forever), then everything once
function P.Art(f)
	local c = f.PlayerFrameContainer
	local altBar = Ask(rawget(_G, "PlayerFrame_GetAlternatePowerBar") or function() return nil end)
	c.VehicleFrameTexture:Hide()
	Atlas(c.FrameTexture, ART.frame)
	c.FrameTexture:SetShown(altBar == nil)
	c.AlternatePowerFrameTexture:SetShown(altBar ~= nil)
	U.Notify("PlayerFrame_ToPlayerArt", f)
	U.Notify("PlayerFrame_UpdateArt", f)
	U.Notify("PlayerFrame_UpdatePlayerNameTextAnchor")
end

MelloUI:On("colours", function()
	local f = U.own.player
	if f then
		P.PowerType(f)
	end
end, "Unit Frames: your power's colour")

function P.Update(f)
	f = f or P.frame
	if not f then
		return
	end
	P.Name(f)
	P.Portrait(f)
	P.PowerType(f)
	P.Health(f)
	P.Level(f)
	P.Roles(f)
	P.Leader(f)
	P.Status(f)
	P.PvP(f)
	P.PvPTimer(f)
	P.Ready(f)
	P.Group(f)
	P.Threat(f)
end

--------------------------------------------------------------------------------
-- Its scripts and events (only while it stands in)
--------------------------------------------------------------------------------

local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED", "PLAYER_ENTER_COMBAT",
	"PLAYER_LEAVE_COMBAT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING",
	"PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
	"PVP_TIMER_UPDATE", "PLAYER_ROLES_ASSIGNED", "HONOR_LEVEL_UPDATE", "PLAYER_PVP_FLAG_CHANGED", "PORTRAITS_UPDATED",
	"CVAR_UPDATE", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA" }
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
	"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_LEVEL",
	"UNIT_FACTION", "UNIT_FLAGS", "UNIT_COMBAT", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_CONNECTION" }

local HANDLERS = {
	PLAYER_ENTERING_WORLD = function(f)
		f.inCombat, f.onHateList = nil, Yes(UnitAffectingCombat, "player") or nil
		P.Update(f)
	end,
	PLAYER_LEVEL_UP = function(f) P.Level(f) end,
	PLAYER_LEVEL_CHANGED = function(f) P.Level(f) end,
	UNIT_LEVEL = function(f) P.Level(f) end,
	PLAYER_ENTER_COMBAT = function(f) f.inCombat = 1 P.Status(f) end,
	PLAYER_LEAVE_COMBAT = function(f) f.inCombat = nil P.Status(f) end,
	PLAYER_REGEN_DISABLED = function(f) f.onHateList = 1 P.Status(f) end,
	PLAYER_REGEN_ENABLED = function(f) f.onHateList = nil P.Status(f) end,
	PLAYER_UPDATE_RESTING = function(f) P.Status(f) end,
	PARTY_LEADER_CHANGED = function(f) P.Group(f) P.Leader(f) P.Ready(f) end,
	GROUP_ROSTER_UPDATE = function(f) P.Group(f) P.Leader(f) P.Ready(f) end,
	READY_CHECK = function(f) P.Ready(f) end,
	READY_CHECK_CONFIRM = function(f) P.Ready(f) end,
	READY_CHECK_FINISHED = function(f)
		local rc = Ctx(f).ReadyCheck
		local fin = rawget(_G, "ReadyCheck_Finish")
		if rc and fin then
			pcall(fin, rc, rawget(_G, "DEFAULT_READY_CHECK_STAY_TIME") or 10)
		end
	end,
	PVP_TIMER_UPDATE = function(f) P.PvPTimer(f) end,
	PLAYER_ROLES_ASSIGNED = function(f) P.Roles(f) end,
	ZONE_CHANGED_NEW_AREA = function(f) P.Roles(f) end,
	HONOR_LEVEL_UPDATE = function(f) P.PvP(f) end,
	PLAYER_PVP_FLAG_CHANGED = function(f) P.PvP(f) end,
	UNIT_FACTION = function(f) P.PvP(f) end,
	UNIT_FLAGS = function(f) P.PvP(f) end,
	PORTRAITS_UPDATED = function(f) P.Portrait(f) end,
	UNIT_PORTRAIT_UPDATE = function(f) P.Portrait(f) end,
	UNIT_MODEL_CHANGED = function(f) P.Portrait(f) end,
	UNIT_NAME_UPDATE = function(f) P.Name(f) end,
	UNIT_HEALTH = function(f) P.Health(f) end,
	UNIT_MAXHEALTH = function(f) P.Health(f) end,
	UNIT_CONNECTION = function(f) P.Health(f) end,
	UNIT_POWER_FREQUENT = function(f) P.Power(f) end,
	UNIT_POWER_UPDATE = function(f) P.Power(f) end,
	UNIT_MAXPOWER = function(f) P.Power(f) end,
	UNIT_DISPLAYPOWER = function(f) P.PowerType(f) end,
	PLAYER_DEAD = function(f) P.PowerType(f) P.Health(f) P.Threat(f) end,
	PLAYER_ALIVE = function(f) P.PowerType(f) P.Health(f) end,
	PLAYER_UNGHOST = function(f) P.PowerType(f) P.Health(f) end,
	UNIT_THREAT_SITUATION_UPDATE = function(f) P.Threat(f) end,
	UNIT_COMBAT = function(f, _, event, flags, amount, kind) P.Feedback(f, event, flags, amount, kind) end,
	CVAR_UPDATE = function(f, cvar)
		if cvar == "statusText" or cvar == "statusTextDisplay" then
			U.TextsChanged()
			U.Texts(f)
		end
	end,
}

local OnEvent = Shared("your player frame (MelloUI's own): its unit's events", function(self, event, ...)
	local fn = HANDLERS[event]
	if fn then
		fn(self, ...)
	end
end, "script")

local function Listen(f, on)
	if on then
		for _, e in ipairs(EVENTS) do
			pcall(f.RegisterEvent, f, e)
		end
		for _, e in ipairs(UNIT_EVENTS) do
			pcall(f.RegisterUnitEvent, f, e, "player")
		end
	else
		f:UnregisterAllEvents()
	end
end

-- the bar under the mouse shows its text (Units.Texts), as the game's bars do on their hover: read each frame while
-- one of ours is under the mouse only (our bars take no mouse: the clicks are the frame's). Each of ours says which
-- bar is under the mouse (f.HoverAt(f) -> "health" / "mana" / nil); one hover watch for all of ours
local hover = { frame = nil, over = nil }
local OnHoverUpdate = Shared("your unit frames under the mouse: their bars' texts", function(self)
	local f = hover.over
	if not (f and f:IsVisible() and f:IsMouseOver()) then
		self:Hide()
		return
	end
	local at = f.HoverAt and f.HoverAt(f) or nil
	if at ~= f.hovered then
		f.hovered = at
		U.Texts(f)
	end
end, "script")

-- its tooltip, as the game's (UnitFrame_OnEnter: the unit's tooltip at the default place, the right-click line)
local OnEnter = Shared("your unit frames' tooltip", function(self)
	local enter = rawget(_G, "UnitFrame_OnEnter")
	if type(enter) ~= "function" or not pcall(enter, self) then
		if rawget(_G, "GameTooltip_SetDefaultAnchor") then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		if pcall(GameTooltip.SetUnit, GameTooltip, self.unit or "player") then
			GameTooltip:Show()
		end
	end
	if self.HoverAt then
		if not hover.frame then
			hover.frame = CreateFrame("Frame")
			hover.frame:Hide()
			Perf.SetScript(hover.frame, "OnUpdate", OnHoverUpdate)
		end
		hover.over = self
		hover.frame:Show()
	end
	-- (its box of auras, the pet's: PetFrameMixin:OnEnter)
	U.AuraBoxOn(self.buffBox)
end, "script")

local OnLeave = Shared("your unit frames' tooltip away", function(self)
	local leave = rawget(_G, "UnitFrame_OnLeave")
	if type(leave) ~= "function" or not pcall(leave, self) then
		GameTooltip:Hide()
	end
	if hover.frame and hover.over == self then
		hover.frame:Hide()
		hover.over = nil
	end
	if self.hovered then
		self.hovered = nil
		U.Texts(self)
	end
	U.AuraBoxOff(self.buffBox)
end, "script")

-- (the player frame's bars under the mouse)
local function PlayerHoverAt(f)
	local main = Main(f)
	return (main.HealthBarsContainer:IsMouseOver() and "health") or (main.ManaBarArea.ManaBar:IsMouseOver() and "mana")
		or nil
end

-- an item dropped on it is put on (PlayerFrame_OnReceiveDrag)
local OnDrop = Shared("an item dropped on your player frame", function()
	local equip = rawget(_G, "AutoEquipCursorItem")
	if Yes(rawget(_G, "CursorHasItem")) and type(equip) == "function" then
		pcall(equip)
	end
end, "script")

-- a frame of ours' tooltip and its bars' hover texts (the player's, the target's: one OnEnter / OnLeave)
function U.Tooltip(f, hoverAt)
	f.HoverAt = hoverAt
	Perf.HookScript(f, "OnEnter", OnEnter)
	Perf.HookScript(f, "OnLeave", OnLeave)
end

function P.Scripts(f)
	Perf.SetScript(f, "OnEvent", OnEvent)
	U.Tooltip(f, PlayerHoverAt)
	Perf.SetScript(f, "OnReceiveDrag", OnDrop)
end

--------------------------------------------------------------------------------
-- The game's frame kept away while ours stands in, and given back
--------------------------------------------------------------------------------

-- the events of the game's player frame's own code (PlayerFrame_OnLoadBase, UnitFrame_Initialize, its bars,
-- TextStatusBar, the cost prediction). Two kinds stay with it: its vehicle events (they swap the pet frame's unit) and
-- the world entered (its art laid once -- PlayerFrame_ToPlayerArt: the pet frame's unit and update, the totems', the
-- class bar's, the buffs' -- on its own unseen parts; the dressers' hooks skip it, Units.Hook)
local GAME_EVENTS = { "PLAYER_LEVEL_CHANGED", "UNIT_FACTION", "PLAYER_ENTER_COMBAT",
	"PLAYER_LEAVE_COMBAT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING",
	"PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
	"PVP_TIMER_UPDATE", "PLAYER_ROLES_ASSIGNED", "HONOR_LEVEL_UPDATE", "PLAYER_PVP_FLAG_CHANGED", "UNIT_COMBAT",
	"UNIT_MAXPOWER", "PLAYTIME_CHANGED", "UNIT_NAME_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_PORTRAIT_UPDATE",
	"PORTRAITS_UPDATED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION",
	"UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_THREAT_SITUATION_UPDATE",
	"UNIT_THREAT_LIST_UPDATE", "CVAR_UPDATE", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
	"UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "VARIABLES_LOADED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"UNIT_CONNECTION", "UNIT_AURA", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTED" }
local OWNER = "player frame"

local function GameParts()
	local game = _G.PlayerFrame
	if type(game) ~= "table" then
		return nil
	end
	local content = rawget(game, "PlayerFrameContent")
	local main = content and rawget(content, "PlayerFrameContentMain")
	local hc = main and rawget(main, "HealthBarsContainer")
	local area = main and rawget(main, "ManaBarArea")
	return game, rawget(game, "PlayerFrameContainer"), content, hc and rawget(hc, "HealthBar"),
		area and rawget(area, "ManaBar"), rawget(game, "Selection")
end

-- their art and content unseen at once (an alpha: in a fight too, never protected); the game's frame away itself, its
-- two holders with all in them (Units.Away)
function P.FadeGame()
	local game, art, content = GameParts()
	if not game then
		return
	end
	U.Fade(OWNER, { art or false, content or false }, { game }, { art or false, content or false })
end

-- the rest out of a fight: the mouse off, Edit Mode's selection box unseen and click-through, the events let go
function P.QuietGame()
	local game, _, content, health, mana, selection = GameParts()
	if not game or InCombatLockdown() then
		return
	end
	U.Quiet(OWNER, { game }, { health or false, mana or false }, { selection or false })
	U.Silence(game, GAME_EVENTS, OWNER, 0)
	U.Silence(content, GAME_EVENTS, OWNER, 5)
end

function P.GiveBack()
	local game = GameParts()
	U.Return(OWNER)
	-- (never run the game's code on its frame from ours: its own events bring it up to date from now on)
	return game
end

--------------------------------------------------------------------------------
-- Standing in and going (Unit Frames on and off). Made out of a fight only (a secure button); a login or /reload in
-- a fight keeps the game's frame (dressed as before) until the fight ends, then ours.
--------------------------------------------------------------------------------

local function Later(fn, key)
	local S = MelloUI.Schedule
	if InCombatLockdown() and S and S.WhenOutOfCombat then
		S:WhenOutOfCombat(fn, key)
	elseif not InCombatLockdown() then
		fn()
	end
end

local function Stand()
	if not P.wanted or P.standing then
		return
	end
	local f = P.Build()
	if not f then
		return
	end
	P.standing = true
	U.own.player = f
	-- (the game's frame dressed meanwhile -- Unit Frames switched on after a login with it off, or given back and
	-- on again, or a login in a fight: hooks of the dressers on its regions can't be taken off) a /reload asked
	-- for, once a session (MelloUI:AskReload)
	if P.usedGame then
		U.AskReload()
	end
	P.FadeGame()
	P.QuietGame()
	Listen(f, true)
	f:Show()
	P.Art(f)
	f.inCombat, f.onHateList = nil, Yes(UnitAffectingCombat, "player") or nil
	P.Update(f)
	MelloUI:Fire("units", "player", true)
end

local function Go()
	if P.wanted or not P.standing then
		return
	end
	local f = P.frame
	P.standing = false
	U.own.player = nil
	if f then
		Listen(f, false)
		f:Hide()
	end
	P.GiveBack()
	P.usedGame = true
	MelloUI:Fire("units", "player", false)
end

-- on (`login`: the login's own frame, before any module dresses a frame: nothing to ask then)
function P.Start(login)
	if P.wanted and (P.standing or login) then
		return
	end
	P.wanted = true
	-- (on later than the login's own frame, or a fight there: the game's frame has been dressed by then)
	if not login or InCombatLockdown() then
		P.usedGame = true
	end
	Later(Stand, "MelloUI own player frame")
end

function P.Stop()
	P.wanted = false
	Later(Go, "MelloUI own player frame")
end

-- (the Unit Frames module's switch, Modules/UnitFrames.lua: P.Start(true) at the login's own frame -- its
-- OnLoginFrame, before the modules come up -- then P.Start / P.Stop with its OnEnable / OnDisable)

-- (/ufdump own) what stands where: ours, the game's holders, the events let go
function U.Dump(add)
	local game, art, content = GameParts()
	add(("own player frame: %s (standing %s, wanted %s)"):format(tostring(P.frame and P.frame:GetName()),
		tostring(P.standing), tostring(P.wanted)))
	if game then
		add(("game PlayerFrame: alpha %.2f, art %.2f, content %.2f, mouse %s"):format(Alpha(game), art and Alpha(art) or -1,
			content and Alpha(content) or -1, tostring(Mouse(game))))
	end
	local n = 0
	for _, had in pairs(U.Silenced(OWNER)) do
		n = n + #had
	end
	add(("events let go: %d"):format(n))
	-- (the other frames of ours add their lines: Modules/UnitFramesTarget.lua)
	for _, more in ipairs(U.dumps) do
		more(add)
	end
end
U.dumps = {}

-- the building pieces ours are made with, for the other frames of ours (one set: Modules/UnitFramesTarget.lua)
U.Parts = { Atlas = Atlas, Tex = Tex, Crisp = Crisp, Font = Font, Holder = Holder, CopyPoints = CopyPoints,
	FillOf = FillOf, Masked = Masked, Bar = Bar, TextsOn = TextsOn, Ask = Ask, Yes = Yes, Later = Later, Alpha = Alpha,
	Mouse = Mouse, Pulse = GlowPulse, Threat = P.Threat }
