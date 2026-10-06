--------------------------------------------------------------------------------
-- MelloUI - Swing Timers (0.17.1)
--
-- A shot bar and a melee bar in MelloUI's look, replacing the game's swing
-- timers (the user, 2026-10-01: "I would love to see better swing timers.
-- The first is for shots and has two stages. Stage 1: you can move, shot is
-- on cooldown. Stage 2 (red): Don't move, shot is loading. The second is for
-- melee swings, that should also work for wands and all weapons";
-- docs/plans/swing-timers.md, the picked looks A Cast Bar and B Hairline in
-- docs/plans/next-update-refs/swing_looks.jpg).
--
-- The bars:
--   shot    a bow, gun, crossbow or thrown weapon's Auto Shot (PLAYER_SWING
--           Ranged), two stages (the user's second /mello swing log,
--           2026-10-02: moving holds the shot back -- it fired 0.36-0.58 s
--           after the player stopped): reloading, cream, shrinking from both
--           ends to the middle over the cycle less the aim (moving is fine);
--           then the aim, red, growing from the middle over B.AIM while the
--           player stands still ("Hold"); moving empties it and it waits
--           ("Moving"), standing still starts it again.
--   melee   the main hand's swings (PLAYER_SWING MainHand), pale; the off
--           hand's on a thinner bar under it (60 % of its height, shown with
--           an off-hand weapon only); a wand's shots ("Shoot (wand)") on the
--           main hand's bar, as the user asked.
-- Each fill is a StatusBar the ENGINE counts down (MelloUI.Anim:Timer, the
-- Center fill style) with its seconds written by the engine too
-- (Anim:TimerText): no Lua each frame, and the bars hidden while nothing
-- runs (Show: In Combat), or idle at rest (Show: Always). Out of range (the
-- game's own check, PLAYER_SWING_RANGE_UPDATE) a bar is at 0.4, as the
-- game's.
-- The looks (Kit:IsOn("castbar"), the cast bars' painted look):
--   castbar   A: the cast bar's own bracket (Kit:Replace "ui-castingbar-frame"),
--             the bar's name above it on the left, its seconds on the right
--   hairline  B: the same piece as the thin rim (bar = "rimhair"), no text
--   the cast bars' look off: the game's own swing timer bar (its ground,
--   frame and the hand's fill: MelloUI.Look.GameSwing), the labels in the
--   game's font and white (docs/plans/game-look.md wave 3); the bars still
--   empty from both ends to the middle, as ours
-- Both stand on the UI Shade's Cast Bars area (Kit:ShadeElement).
-- The game's swing timers are switched off while this is on (its own CVar,
-- showSwingTimer, held by MelloUI:HoldCVar; the player's value comes back
-- when this is off), out of combat only -- and held off: switched on again
-- in the game's settings, it is off again at once (CVAR_UPDATE; in a fight
-- at its end), as the damage meter holds the game's meter. Never a Hide or SetPoint on the
-- game's Edit Mode frames.
-- Two Edit Layout movers, "Shot Timer" and "Swing Timer", just above the
-- player's cast bar by default, with the Width and Height in their boxes.
-- Nothing at login while off; while on, the bars are made on the first
-- swing (In Combat) or the first entering of the world (Always).
--
-- /mello swing log (plan section 2): the shot's timing as this client gives
-- it. For LOG_TIME seconds it prints, with the seconds since the log began:
--   PLAYER_SWING (duration, type) and the time since the last of its type;
--   START_AUTOREPEAT_SPELL / STOP_AUTOREPEAT_SPELL;
--   your UNIT_SPELLCAST_START / STOP / SUCCEEDED / FAILED / INTERRUPTED with
--   the spell (Auto Shot 75, Shoot 5019);
--   PLAYER_STARTED_MOVING / PLAYER_STOPPED_MOVING;
--   PLAYER_SWING_RANGE_UPDATE and UNIT_ATTACK_SPEED;
-- and on its first line your weapons' speeds, the ranged slot's weapon and
-- the game's own swing timer setting (showSwingTimer). Made on the first
-- log, never at login.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("SwingTimers")
local Shared = Perf.Shared
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local W = MelloUI.Widgets

local NEW = "0.17.1"
local M = MelloUI:RegisterModule("SwingTimers", {
	title = "Swing Timers",
	desc = "A shot bar and a melee bar in MelloUI's look in place of the game's swing timers: each swing and shot counted down, the off hand under the main hand, a wand's shots on the melee bar. The game's own swing timers are switched off while this is on, and come back as you had them when it is off.",
	icon = "Interface\\Icons\\Ability_Marksmanship",
	flavour = "Every swing and shot at a glance.",
	role = "replaces",
	slash = "swing",
	new = NEW,
	enabledByDefault = false,
	-- (not on the installer's Features step: its two columns are full; it is
	-- switched on in the settings window)
	installer = false,
	-- the player's own game setting, given back when off: never in a profile
	keep = { "savedSwing" },
	defaults = { shot = true, melee = true, offhand = true, look = "castbar", text = true, show = "combat", width = 200,
		height = 10 },
	options = {
		{ type = "toggle", key = "shot", name = "Shot Bar", new = NEW,
		  desc = "The shot bar for a bow, gun, crossbow or thrown weapon while Auto Shot is on: cream, shrinking to the middle while it reloads (you can move), then red, growing from the middle while you aim: stand still, moving holds the shot back." },
		{ type = "toggle", key = "melee", name = "Melee Bar", new = NEW,
		  desc = "The melee bar: each swing of your main hand counted down, shrinking to the middle. A wand's shots (Shoot) count down on it too." },
		{ type = "toggle", key = "offhand", name = "Off Hand Bar", new = NEW,
		  desc = "A thinner bar under the melee bar for your off-hand weapon's swings, while you carry one." },
		{ type = "dropdown", key = "look", name = "Look", new = NEW,
		  values = { { value = "castbar", label = "Cast Bar" }, { value = "hairline", label = "Hairline" } },
		  desc = "Cast Bar: the cast bar's frame, with the bar's name and the seconds left. Hairline: a thin rim on a soft shade, nothing else. With the cast bars' painted look off, both are a plain bar." },
		{ type = "toggle", key = "text", name = "Label And Time", new = NEW,
		  desc = "The bar's name above it on the left (Auto Shot, Main Hand, Shoot (wand)) and the seconds left on the right." },
		{ type = "slider", key = "width", name = "Width", new = NEW, min = 100, max = 400, step = 5,
		  desc = "How wide the bars are. Also in Edit Layout (right-click a bar there)." },
		{ type = "slider", key = "height", name = "Height", new = NEW, min = 6, max = 24, step = 1,
		  desc = "How tall the bars are; the off hand's is 60 % of it. Also in Edit Layout." },
		{ type = "dropdown", key = "show", name = "Show", new = NEW,
		  values = { { value = "combat", label = "In Combat" }, { value = "always", label = "Always" } },
		  desc = "In Combat: a bar shows in a fight once it swings or shoots, and fades out when the fight ends (the shot bar also when Auto Shot stops). Always: each bar shows while you carry a weapon for it, at rest between swings." },
	},
})

--------------------------------------------------------------------------------
-- The bars
--------------------------------------------------------------------------------

-- sizes in UI units: the label row above a bar, the off hand's bar under the
-- main hand's (OFF of its height, GAP between), the label's size, the
-- dimming out of range (the game's OUT_OF_RANGE_ALPHA), the fades
local B = { ABOVE = 14, GAP = 5, OFF = 0.6, LABEL = 11, OUT = 0.4, FADE_IN = 0.15, FADE_OUT = 0.6, CAST_GAP = 30,
	BAR_GAP = 8,
	AIM = 0.5 }   -- the shot's aim at the cycle's end (Classic's Auto Shot; the user's log: 0.36-0.58 s after stopping)
local CVAR = "showSwingTimer"
local TYPE = { main = 0, off = 1, ranged = 2 }
local TEXT = { shot = "Auto Shot", main = "Main Hand", wand = "Shoot (wand)", off = "Off Hand",
	shotMover = "Shot Timer", meleeMover = "Swing Timer", hold = "Hold", moving = "Moving" }
local MOVER = { shot = "swingshot", melee = "swingmelee" }
local KINDS = { "shot", "melee" }

-- state: the bars made ([kind] = ui), in a fight, Auto Shot on, which bars
-- swung this fight, the ranged weapon a wand, the CVar's write waiting for
-- the fight's end, the range per swing type (true: out)
local S = { bars = {}, fight = false, autoShot = false, ran = {}, wand = false, cvarDue = false, out = {},
	looking = false, hasRanged = nil, hasOff = nil,
	-- the shot's stage ("reload", "aim", "wait"; nil: none), when its aim is
	-- due, and the player moving
	shotStage = nil, aimAt = 0, moving = false }
local Shot = {}   -- the shot bar's two stages (below)

local function On()
	return M.isEnabled and true or false
end

local function Size()
	local db = M.db
	local w = Num(db and db.width) or 200
	local h = Num(db and db.height) or 10
	return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- a label: MelloUI's text font and the palette while the cast bars wear the
-- kit, the game's small white font in its look (MelloUI.Look)
local function StyleText(fs, size)
	MelloUI.Look.Text(fs, "text", size, { area = "castbar" })
	fs:SetShadowOffset(1, -1)
end

-- one track: a frame and the fill (a StatusBar the engine counts down, from
-- both ends to the middle); `hand` the game's fill for it in its look
local function NewTrack(holder, colour, hand)
	local track = CreateFrame("Frame", nil, holder)
	local fill = CreateFrame("StatusBar", nil, track)
	fill:SetAllPoints(track)
	fill:SetStatusBarTexture(W.BarFill("castbars"))
	local style = _G.Enum and _G.Enum.StatusBarFillStyle
	if style and style.Center and fill.SetFillStyle then
		pcall(fill.SetFillStyle, fill, style.Center)
	end
	fill:SetStatusBarColor(colour[1], colour[2], colour[3])
	fill:SetMinMaxValues(0, 1)
	fill:SetValue(0)
	return { frame = track, fill = fill, colour = colour, hand = hand }
end

-- the default place: just above the player's cast bar (the shot bar above
-- the melee bar), else above the screen's bottom middle
local function Home(kind)
	return function(holder)
		holder:ClearAllPoints()
		local cast = _G.PlayerCastingBarFrame
		local _, h = Size()
		local up = B.CAST_GAP + (kind == "shot" and (B.ABOVE + h + B.GAP + h * B.OFF + B.BAR_GAP) or 0)
		if type(cast) == "table" and cast.GetObjectType then
			holder:SetPoint("BOTTOM", cast, "TOP", 0, up)
		else
			holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220 + up)
		end
		return true
	end
end

local Lay, Look   -- (below)

local function Build(kind)
	local ui = S.bars[kind]
	if ui then
		return ui
	end
	local holder = CreateFrame("Frame", "MelloUISwing" .. (kind == "shot" and "Shot" or "Melee"), UIParent)
	holder:SetFrameStrata("MEDIUM")
	holder:SetClampedToScreen(true)
	holder:SetAlpha(0)
	holder:Hide()
	ui = { kind = kind, holder = holder, shown = false }
	S.bars[kind] = ui
	local Meaning = MelloUI.Meaning
	ui.main = NewTrack(holder, kind == "shot" and Meaning.swingShot or Meaning.swingMelee,
		kind == "shot" and "ranged" or "main")
	ui.tracks = { ui.main }
	if kind == "melee" then
		ui.off = NewTrack(holder, Meaning.swingMelee, "off")
		ui.tracks[2] = ui.off
	end
	local label = holder:CreateFontString(nil, "OVERLAY")
	StyleText(label, B.LABEL)
	label:SetPoint("BOTTOMLEFT", ui.main.frame, "TOPLEFT", 2, 2)
	label:SetText(kind == "shot" and TEXT.shot or TEXT.main)
	ui.label = label
	local time = holder:CreateFontString(nil, "OVERLAY")
	StyleText(time, B.LABEL)
	time:SetPoint("BOTTOMRIGHT", ui.main.frame, "TOPRIGHT", -2, 2)
	ui.time = time
	ui.timed = MelloUI.Anim:TimerText(time, ui.main.fill)
	if kind == "shot" then
		-- (the aim's word in the seconds' place: "Hold", "Moving")
		local state = holder:CreateFontString(nil, "OVERLAY")
		StyleText(state, B.LABEL)
		state:SetPoint("BOTTOMRIGHT", ui.main.frame, "TOPRIGHT", -2, 2)
		state:Hide()
		ui.state = state
	end
	local key = MOVER[kind]
	ui.entry = MelloUI:RegisterMover(holder, holder, { key = key, default = Home(kind), min = 0.5, max = 2, base = 1,
		label = kind == "shot" and TEXT.shotMover or TEXT.meleeMover, page = "SwingTimers", when = On, placeholder = true,
		settings = { "SwingTimers.width", "SwingTimers.height" } })
	if not MelloUI:RestorePosition(key, holder) then
		Home(kind)(holder)
	end
	Lay(ui)
	Look(ui)
	return ui
end

-- the sizes: the label row, the main bar, the off hand's under it
Lay = function(ui)
	local w, h = Size()
	local offH = math.max(3, math.floor(h * B.OFF + 0.5))
	local main, off = ui.main.frame, ui.off and ui.off.frame
	main:ClearAllPoints()
	main:SetPoint("TOPLEFT", ui.holder, "TOPLEFT", 0, -B.ABOVE)
	main:SetPoint("TOPRIGHT", ui.holder, "TOPRIGHT", 0, -B.ABOVE)
	main:SetHeight(h)
	local height = B.ABOVE + h
	if off then
		off:ClearAllPoints()
		off:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -B.GAP)
		off:SetPoint("TOPRIGHT", main, "BOTTOMRIGHT", 0, -B.GAP)
		off:SetHeight(offH)
		height = height + B.GAP + offH
	end
	ui.holder:SetSize(w, height)
	for _, t in pairs(ui.tracks) do
		if t.rep and t.rep.Refit then
			pcall(t.rep.Refit, t.rep)
		end
		if t.game then
			MelloUI.Look.GameSwing(t.frame, t.fill, t.hand, true, t == ui.off and offH or h)   -- (its inset by its height)
		end
	end
end

-- the look of one track: the cast bar's bracket (A) or its hairline (B)
-- while the cast bars wear the kit, else the game's own swing timer bar
local function LookTrack(t, kit, bar, height)
	MelloUI.Look.GameSwing(t.frame, t.fill, t.hand, false)
	t.fill:SetStatusBarTexture(W.BarFill("castbars"))
	t.fill:SetStatusBarColor(t.colour[1], t.colour[2], t.colour[3])
	local Kit = MelloUI.Kit
	if kit and t.rep == nil and Kit and Kit.Replace then
		local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(t.fill)
		local ok, rep = pcall(Kit.Replace, Kit, t.fill, { as = "ui-castingbar-frame", parent = t.fill, rect = t.fill,
			noFade = true, bar = bar, layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub })
		t.rep = ok and rep or false
		if t.rep and Kit.ShadeElement then
			-- (the UI Shade's Cast Bars area, as the cast bars' own)
			pcall(function()
				Kit:ShadeElement(t.frame, "castbars", { anchor = rawget(t.rep, "trough") }):Add(t.rep)
			end)
		end
	end
	local rep = t.rep
	if rep then
		if kit then
			if rep.SetBar then
				rep:SetBar(bar)
			end
			rep:Enable()
			pcall(rep.Refit, rep)
		else
			rep:Disable()
		end
	end
	t.game = not (kit and rep)
	if t.game then
		MelloUI.Look.GameSwing(t.frame, t.fill, t.hand, true, height)
	end
end

Look = function(ui)
	local Kit = MelloUI.Kit
	local kit = Kit and Kit.IsOn and Kit:IsOn("castbar") and true or false
	local db = M.db
	local hairline = db and db.look == "hairline"
	local bar = hairline and "rimhair" or "castbar"
	local _, h = Size()
	LookTrack(ui.main, kit, bar, h)
	if ui.off then
		LookTrack(ui.off, kit, bar, math.max(3, math.floor(h * B.OFF + 0.5)))
	end
	-- A's label and seconds (B: the bar alone)
	local text = not hairline and not (db and db.text == false)
	ui.textOn = text
	ui.label:SetShown(text)
	ui.time:SetShown(text and ui.timed)
	if ui.kind == "shot" then
		Shot.Paint(ui)
	end
end

local function LookAll()
	for _, ui in pairs(S.bars) do
		Look(ui)
	end
end

--------------------------------------------------------------------------------
-- What shows
--------------------------------------------------------------------------------

-- The weapons as last read plainly (the user's video, 2026-10-02: in a fight
-- the speeds are secret -- UnitAttackSpeed and UnitRangedDamage are
-- SecretWhenUnitStatsRestricted -- and the shot bar, asking on each swing,
-- read "no ranged weapon" and hid for the rest of the fight, Show: Always
-- too). Read when the world loads, a weapon changes and a fight ends; a
-- secret read keeps what was known; a shot or an off-hand swing proves its
-- weapon.
local function ReadWeapons()
	local ok, main, off, ranged = pcall(_G.UnitAttackSpeed, "player")
	if not ok or Secret(main) or Secret(off) or Secret(ranged) then
		return
	end
	if ranged == nil and _G.UnitRangedDamage then
		local okR, r = pcall(_G.UnitRangedDamage, "player")
		if not okR or Secret(r) then
			return
		end
		ranged = r
	end
	S.hasOff = type(off) == "number" and off > 0
	S.hasRanged = type(ranged) == "number" and ranged > 0
end

local function HasOffHand()
	if S.hasOff == nil then
		ReadWeapons()
	end
	return S.hasOff == true
end

local function HasRanged()
	if S.hasRanged == nil then
		ReadWeapons()
	end
	return S.hasRanged == true
end

-- the ranged slot's weapon a wand (its swings on the melee bar)
local function ReadWand()
	S.wand = false
	local okI, item = pcall(_G.GetInventoryItemID, "player", 18)
	if not okI or not item or Secret(item) then
		return
	end
	local api = _G.C_Item
	local info = api and api.GetItemInfoInstant or _G.GetItemInfoInstant
	if not info then
		return
	end
	local ok, _, _, _, _, _, classID, subclassID = pcall(info, item)
	local enum = _G.Enum
	local wand = enum and enum.ItemWeaponSubclass and enum.ItemWeaponSubclass.Wand or 19
	local weapon = enum and enum.ItemClass and enum.ItemClass.Weapon or 2
	S.wand = ok and not Secret(classID) and not Secret(subclassID) and classID == weapon and subclassID == wand or false
end

local function InFight()
	if S.fight then
		return true
	end
	local ok, v = pcall(UnitAffectingCombat, "player")
	return ok and not Secret(v) and v == true
end

-- whether a bar may show at all: its switch and a weapon for it
local function Allowed(kind)
	local db = M.db
	if not (On() and db) then
		return false
	end
	if kind == "shot" then
		return db.shot ~= false and not S.wand and HasRanged()
	end
	return db.melee ~= false
end

-- whether a bar shows now: allowed, and the Show rule
local function Wanted(kind)
	if not Allowed(kind) then
		return false
	end
	if M.db.show == "always" then
		return true
	end
	if kind == "shot" then
		return InFight() and S.autoShot and S.ran.shot == true
	end
	return InFight() and S.ran.melee == true
end

local function SetShown(ui, on)
	if ui.shown == on then
		return
	end
	ui.shown = on
	local Anim = MelloUI.Anim
	if on then
		ui.holder:Show()
		Anim:To(ui.holder, "alpha", 1, B.FADE_IN)
	else
		Anim:FadeOut(ui.holder, B.FADE_OUT)
	end
end

-- every bar shown as it should be now (made when it is wanted)
local function Update()
	for _, kind in ipairs(KINDS) do
		local want = Wanted(kind)
		local ui = S.bars[kind]
		if want and not ui then
			ui = Build(kind)
		end
		if ui then
			SetShown(ui, want)
			if ui.off then
				ui.off.frame:SetShown(M.db and M.db.offhand ~= false and HasOffHand() or false)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Swings, range, the game's own timers
--------------------------------------------------------------------------------

-- the track a swing type runs on, and its bar
local function TrackOf(swingType)
	if swingType == TYPE.ranged and not S.wand then
		return S.bars.shot, "shot", "main"
	end
	return S.bars.melee, "melee", swingType == TYPE.off and "off" or "main"
end

-- The shot bar's two stages (the user's video and second log, 2026-10-02):
-- the reload, cream, counted down by the engine (moving is fine); at its end
-- the aim, red, counted up from the middle over B.AIM while the player
-- stands still, or waiting ("Moving") while the player moves. The reload's
-- end comes from one C_Timer.After a shot (the function shared, no closure:
-- a later shot's reload moves aimAt, and an earlier call finds it not due).

-- the shot bar in its stage: the fill's colour (cream reloading, the aim's
-- red; the game's own fill in its own white in its look) and the text in the
-- seconds' place (the seconds, "Hold", "Moving")
function Shot.Paint(ui)
	local stage = S.shotStage or "reload"
	local t = ui.main
	local c = MelloUI.Meaning.swingAim
	if stage == "reload" then
		c = t.game and MelloUI.Look.Palette("castbar").text or t.colour
	end
	t.fill:SetStatusBarColor(c[1], c[2], c[3])
	local text = ui.textOn and true or false
	ui.time:SetShown(text and ui.timed and stage == "reload" or false)
	if ui.state then
		ui.state:SetText(stage == "wait" and TEXT.moving or TEXT.hold)
		ui.state:SetShown(text and stage ~= "reload")
	end
end

-- the aim: run now, or wait while the player moves
function Shot.Aim()
	local ui = S.bars.shot
	if not ui then
		return
	end
	if S.moving then
		S.shotStage = "wait"
		MelloUI.Anim:StopTimer(ui.main.fill)
	else
		S.shotStage = "aim"
		MelloUI.Anim:Timer(ui.main.fill, B.AIM, true)
	end
	Shot.Paint(ui)
end

-- the reload's end (C_Timer.After): the aim, unless a later shot moved it
Shot.Due = Shared("the shot bar: its reload done", function()
	if S.shotStage == "reload" and GetTime() + 0.01 >= S.aimAt then
		Shot.Aim()
	end
end)

-- a shot fired: the reload from full
function Shot.Start(ui, duration)
	local reload = duration - B.AIM
	S.shotStage = "reload"
	S.aimAt = GetTime() + math.max(reload, 0)
	Shot.Paint(ui)
	if reload > 0 then
		MelloUI.Anim:Timer(ui.main.fill, reload)
		C_Timer.After(reload, Shot.Due)
	else
		Shot.Aim()
	end
end

-- no shot on its way (Auto Shot stopped, the module off): the bar at rest
function Shot.Stop()
	S.shotStage = nil
	local ui = S.bars.shot
	if ui then
		MelloUI.Anim:StopTimer(ui.main.fill)
		Shot.Paint(ui)
	end
end

-- the player started or stopped moving: the aim waits, or runs again
function Shot.Moving(moving)
	S.moving = moving
	if (moving and S.shotStage == "aim") or (not moving and S.shotStage == "wait") then
		Shot.Aim()
	end
end

local function Swing(duration, swingType)
	duration = Num(duration)
	if Secret(swingType) or not duration or duration <= 0 then
		return
	end
	local _, kind = TrackOf(swingType)
	S.ran[kind] = true
	if kind == "shot" then
		S.autoShot = true   -- (a shot fired: Auto Shot is on, also when it was started before a /reload)
		S.hasRanged = true   -- (and a ranged weapon there, whatever a secret read said)
	elseif swingType == TYPE.off then
		S.hasOff = true
	end
	Update()
	-- (the first swing or shot comes BEFORE PLAYER_REGEN_DISABLED -- the
	-- user's second log -- so with Show: In Combat it is not wanted yet: the
	-- bar made now all the same and its timer started, shown when the fight's
	-- event comes a moment later -- the user's video 2026-10-02, the first
	-- shot after a /reload an empty bar)
	if not S.bars[kind] and Allowed(kind) then
		Build(kind)
	end
	local ui, _, part = TrackOf(swingType)
	if not ui then
		return   -- (switched off, or no weapon for it: nothing made)
	end
	if part == "main" and kind == "melee" then
		ui.label:SetText(swingType == TYPE.ranged and TEXT.wand or TEXT.main)
	end
	if kind == "shot" then
		Shot.Start(ui, duration)
		return
	end
	local track = ui[part]
	if track then
		MelloUI.Anim:Timer(track.fill, duration)
	end
end

local function Range(swingType, out)
	S.out[swingType] = out and true or false
	local ui, _, part = TrackOf(swingType)
	local track = ui and ui[part]
	if track then
		track.frame:SetAlpha(out and B.OUT or 1)
	end
end

local function RangeChecks(on)
	local api = _G.C_SwingTimer
	if not (api and api.EnableRangeCheck) then
		return
	end
	for _, t in pairs(TYPE) do
		pcall(api.EnableRangeCheck, t, on and true or false)
	end
end

-- the target changed: each type's range asked again
local function TargetRange()
	local api = _G.C_SwingTimer
	if not (api and api.IsTargetWithinSwingRange) then
		return
	end
	for _, t in pairs(TYPE) do
		local ok, inRange = pcall(api.IsTargetWithinSwingRange, t)
		Range(t, ok and not Secret(inRange) and inRange == false)
	end
end

-- the game's own swing timers off while this is on (out of combat), the
-- player's setting back when off; the range checks asked for again after
-- the game's timers let theirs go
local function Switches()
	if MelloUI.InCombat() then
		S.cvarDue = true
		return
	end
	S.cvarDue = false
	MelloUI:HoldCVar(M.db, CVAR, "savedSwing", On(), "0")
	if On() then
		C_Timer.After(0.5, function()
			if On() then
				RangeChecks(true)
			end
		end)
	end
end

local OnEvent = Shared("OnEvent of the swing timers", function(_, event, a1, a2, a3)
	if event == "PLAYER_SWING" then
		Swing(a1, a2)
	elseif event == "PLAYER_SWING_RANGE_UPDATE" then
		-- (swingType, isInRange, checksRange)
		if not Secret(a1) and not Secret(a2) and not Secret(a3) then
			Range(a1, a3 and not a2)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		TargetRange()
	elseif event == "START_AUTOREPEAT_SPELL" then
		S.autoShot = true
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		S.autoShot = false
		S.ran.shot = false
		Shot.Stop()
		Update()
	elseif event == "PLAYER_STARTED_MOVING" then
		Shot.Moving(true)
	elseif event == "PLAYER_STOPPED_MOVING" then
		Shot.Moving(false)
	elseif event == "CVAR_UPDATE" then
		-- the game's own swing timers switched on again (its settings) while
		-- these stand in for them (the user, 2026-10-02: players had both):
		-- off again (out of combat; in a fight at its end, Switches), the
		-- player's newest choice kept for when these are switched off
		if a1 == CVAR and On() then
			local now = MelloUI:CVarText(CVAR)
			if now ~= nil and now ~= "0" then
				if M.db then
					M.db.savedSwing = now
				end
				Switches()
			end
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		S.fight = true
		Update()
	elseif event == "PLAYER_REGEN_ENABLED" then
		S.fight = false
		S.ran.shot, S.ran.melee = false, false
		ReadWeapons()   -- (plain again out of the fight)
		if S.cvarDue then
			Switches()
		end
		if not On() then
			S.frame:UnregisterAllEvents()   -- (switched off in the fight: the game's timers were waiting for its end)
			return
		end
		Update()
	elseif event == "WEAPON_SLOT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		ReadWand()
		ReadWeapons()
		if event == "PLAYER_ENTERING_WORLD" then
			RangeChecks(true)
		end
		Update()
	end
end)

local EVENTS = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_TARGET_CHANGED", "START_AUTOREPEAT_SPELL",
	"STOP_AUTOREPEAT_SPELL", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "WEAPON_SLOT_CHANGED",
	"PLAYER_ENTERING_WORLD", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "CVAR_UPDATE" }

local function Events(on)
	if not S.frame then
		if not on then
			return
		end
		S.frame = CreateFrame("Frame")
		Perf.SetScript(S.frame, "OnEvent", OnEvent)
	end
	if on then
		for _, e in ipairs(EVENTS) do
			pcall(S.frame.RegisterEvent, S.frame, e)
		end
	else
		S.frame:UnregisterAllEvents()
	end
end

--------------------------------------------------------------------------------
-- The module
--------------------------------------------------------------------------------

-- Edit Layout's plates: both bars made when it opens (their movers with
-- them), never at login
local function MoverSource()
	if On() then
		for _, kind in ipairs(KINDS) do
			Build(kind)
		end
	end
end

function M:OnInit(db)
	self.db = db
	MelloUI:AddMoverSource(MoverSource)
end

-- (the saved variables arriving after the login: the table they hold)
function M:OnAddonLoaded(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db or self.db
	Events(true)
	if not S.looking then
		S.looking = true
		MelloUI:On("look:castbar", LookAll, "Swing timers")
		-- the cast bars' Bar Texture set or switched (W.BarFill "castbars",
		-- 0.19.4: the swing timers wear the cast bar bracket, so the Cast Bars
		-- area's fill too): the fill again
		W.OnBarTexture("castbars", LookAll, "Swing timers")
	end
	ReadWand()
	ReadWeapons()
	S.fight = MelloUI.InCombat()
	local okM, moving = pcall(_G.IsPlayerMoving)
	S.moving = okM and not Secret(moving) and moving == true or false
	Switches()
	Update()
end

function M:OnDisable()
	Events(false)
	S.fight, S.autoShot, S.ran.shot, S.ran.melee = false, false, false, false
	Shot.Stop()
	for _, ui in pairs(S.bars) do
		MelloUI.Anim:StopTimer(ui.main.fill)
		if ui.off then
			MelloUI.Anim:StopTimer(ui.off.fill)
		end
		ui.shown = false
		MelloUI.Anim:Stop(ui.holder, "alpha")
		ui.holder:SetAlpha(0)
		ui.holder:Hide()
	end
	RangeChecks(false)
	-- the game's own timers back (in a fight: at its end, from the one
	-- listener left for it)
	if MelloUI.InCombat() then
		if S.frame then
			S.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		end
		S.cvarDue = true
	else
		Switches()
	end
end

function M:OnSettingChanged(key, _, db)
	self.db = db or self.db
	if key == "width" or key == "height" then
		for _, ui in pairs(S.bars) do
			Lay(ui)
		end
	elseif key == "look" or key == "text" then
		LookAll()
	end
	Update()
end

-- for the tests and /mello swing: the state and the bars
M.S = S

--------------------------------------------------------------------------------
-- /mello swing log
--------------------------------------------------------------------------------

local LOG_TIME = 20
local TYPES = { [0] = "MainHand", [1] = "OffHand", [2] = "Ranged" }
local LOG_EVENTS = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
	"PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local LOG_UNIT_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_ATTACK_SPEED" }
local log = { frame = nil, t0 = 0, untilAt = 0, last = {}, on = false }

local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h
	end
	return nil
end

-- a number for the log: two decimals, "secret" or "-"
local function N(v)
	if Secret(v) then
		return "secret"
	end
	v = Num(v)
	return v and string.format("%.2f", v) or "-"
end

local function Say(text, ...)
	MelloUI:Print("swing %6.2f  " .. text, GetTime() - log.t0, ...)
end

local function SpellName(id)
	if Secret(id) then
		return "secret"
	end
	local api = _G.C_Spell
	local name = api and Text((Ask(api.GetSpellName, id)))
	return string.format("%s %s", tostring(id), name or "?")
end

local function LogStop()
	if not log.on then
		return
	end
	log.on = false
	log.frame:UnregisterAllEvents()
	Say("log over")
end

local OnLogEvent = Shared("OnEvent on the swing log", function(_, event, a1, a2, a3)
	if not log.on then
		return
	end
	if GetTime() > log.untilAt then
		LogStop()
		return
	end
	if event == "PLAYER_SWING" then
		local kind = not Secret(a2) and TYPES[a2] or tostring(a2)
		local since = ""
		local last = log.last[kind]
		if last then
			since = string.format("  (%.2f since the last %s)", GetTime() - last, kind)
		end
		log.last[kind] = GetTime()
		Say("PLAYER_SWING %s duration %s%s", kind, N(a1), since)
	elseif event == "PLAYER_SWING_RANGE_UPDATE" then
		Say("PLAYER_SWING_RANGE_UPDATE %s in range %s checks %s", not Secret(a1) and TYPES[a1] or "?", tostring(a2),
			tostring(a3))
	elseif event == "UNIT_ATTACK_SPEED" then
		local main, off = Ask(_G.UnitAttackSpeed, "player")
		Say("UNIT_ATTACK_SPEED main %s off %s", N(main), N(off))
	elseif event:find("^UNIT_SPELLCAST_") then
		-- (unit, castGUID, spellID)
		Say("%s %s", event, SpellName(a3))
	else
		Say("%s", event)
	end
end)

-- /mello swing log
function M.Log()
	if not log.frame then
		log.frame = CreateFrame("Frame")
		Perf.SetScript(log.frame, "OnEvent", OnLogEvent)
	end
	log.t0, log.untilAt, log.on = GetTime(), GetTime() + LOG_TIME, true
	for k in pairs(log.last) do
		log.last[k] = nil
	end
	for _, e in ipairs(LOG_EVENTS) do
		pcall(log.frame.RegisterEvent, log.frame, e)
	end
	for _, e in ipairs(LOG_UNIT_EVENTS) do
		pcall(log.frame.RegisterUnitEvent, log.frame, e, "player")
	end
	-- the ranged range check on, as the game's own timer asks for it
	local st = _G.C_SwingTimer
	if st and st.EnableRangeCheck then
		pcall(st.EnableRangeCheck, 2, true)
	end
	local main, off = Ask(_G.UnitAttackSpeed, "player")
	local ranged = Ask(_G.UnitRangedDamage, "player")
	local item = Ask(_G.GetInventoryItemID, "player", 18)
	local kind = ""
	if item and not Secret(item) and _G.C_Item and _G.C_Item.GetItemInfoInstant then
		local _, _, _, _, _, classID, subclassID = Ask(_G.C_Item.GetItemInfoInstant, item)
		kind = string.format(" (item class %s, subclass %s)", tostring(classID), tostring(subclassID))
	end
	local cvar = MelloUI:CVarText(CVAR)
	MelloUI:Print("Swing log for %d seconds: fire a few shots standing still, then a few while stepping (a melee or wand "
		.. "fight works too). Copy it from /mellolog.", LOG_TIME)
	Say("speeds: main %s off %s ranged %s; ranged slot %s%s; showSwingTimer %s", N(main), N(off), N(ranged),
		tostring(item), kind, tostring(cvar))
	C_Timer.After(LOG_TIME + 0.1, LogStop)
end

M.SlashWords = { log = M.Log }
