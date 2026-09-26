--------------------------------------------------------------------------------
-- MelloUI - Layout fit
--
-- The approved Edit Mode layout (Media/EditModeLayout.lua `layout`, the 21:9
-- Immersive) is drawn for a screen of 2866.67 x 1200 UI units. This file fits
-- it to the player's screen. Every fit starts from the approved layout, keeps
-- every anchor, and changes a piece only when a check fails, with the smallest
-- change that clears it (the rules F0-F12, ported one to one from the
-- prototype, Tools/installer/fitting/fit.py, whose functions have the same
-- names). The one change every fit makes is the minimap column of layout E
-- (F5m, the refit, user 2026-09-25 "yes, flip it"): the minimap's Edit Mode Size makes the map about as wide as the
-- Quest Tracker's design width, and the tracker hangs right under the column.
-- So the design screen gets the approved layout back with only that and what
-- it forces (the boss frames and the external defensives make room); a 32:9
-- screen gets it in a centred 21:9 zone; a screen with no
-- room for it (inside 1400 x 800 UI units, or one where the design's own
-- settings fail too) gets a "too small" result, and the installer then
-- suggests No reskin. A FAIL that only the player's settings make is said
-- as such (cause "settings"): No reskin would not help there.
--
-- The UI scale is only read (UIParent's size), never changed: the game's own
-- scale is bugged on this client (user, 2026-09-25).
--
-- Pure: every size comes from the layout's own settings plus the kit's
-- constant footprints and the window sizes below. No live frame is measured
-- (they are sized for the player's current layout, not the fitted one), no
-- frame is made and nothing runs at login. A fit reads only the layout info
-- it is given and MelloUI's settings; it never calls Edit Mode itself (the
-- caller applies the result through C_EditMode, out of combat).
--
--   LayoutFit:Fit(info, W, H, inputs, opts) -> fitted, places, report
--       tests and tools only: in game use Run (a whole fit is 2-16 ms in one
--       go, twice that on a FAIL, over the frame's budget)
--       info    the game's layout info (C_EditMode.ConvertStringToLayoutInfo)
--               of the approved layout; not changed (the fit works on a copy)
--       W, H    the screen in UI units (LayoutFit:ScreenSize())
--       inputs  MelloUI's own settings the fit reads (LayoutFit:Inputs()):
--               positions (UI Modifications' store: the window places; none
--               when nil), tracker { pos, width, maxHeight, scale } (a width
--               or maxHeight of 0: the game's tracker's, as QuestTracker
--               reads it), questlist { width }, hideBagBar, statsOn,
--               actionSlots ([slot] = true: the hidden bars that hold an
--               action are shown), column { kit, shape, border, merge, bar,
--               groups, barOffset, roundIcons, match } (the minimap column
--               of layout E: the Minimap Kit on, its shape, square border
--               and Merge With Services; the Services bar shown, its Groups
--               layout, distance and round icons; the Quest Tracker's Match
--               The Minimap's Width) and auras { rows, attached, size,
--               perRow, fitRows } (your buff rows, by the minimap column;
--               fitRows: true only from a caller that writes places.auras;
--               without it the layout is still laid for the Icons Per Row
--               and Icon Size the rows need, but nothing is written: an eye
--               line asks the player to set them; Inputs leaves it out);
--               a missing or secret column or auras field is the design's
--               (Full's)
--       opts    screenW / screenH (the physical size, for the layout's name;
--               read from the game when not given), baseName ("MelloUI")
--     fitted   the fitted layout info: anchorInfo points (strings) and
--              offsets, isInDefaultPosition, settings[j].value; layoutName
--              is one name per screen ("MelloUI 1920x1080"; plain "MelloUI"
--              on the design screen)
--     places   what the installer writes into MelloUI's settings:
--                remove        UIModifications.positions keys to delete (the
--                              four frames Edit Mode places)
--                windows       [frame] = place, UIModifications.positions
--                questTracker  { clearPos = true, maxHeight, width }
--                              (QuestTracker.pos = nil: it hangs on 12:-1;
--                              a 0 the fit did not have to change stays 0)
--                questList     { width }
--                auras         { playerPerRow, playerSize } while your buff
--                              rows stand by the minimap column and the
--                              inputs' auras.fitRows is on (Auras' Icons
--                              Per Row and Icon Size as fitted), else nil
--                layoutFitFor  "WxH" (UIModifications.layoutFitFor)
--     report   verdict ("PASS" | "PASS, needs the user's eye" | "FAIL (...)"),
--              pass; on a FAIL, cause "size" (tooSmall = true, suggest =
--              "noReskin") or "settings" (the screen fits the design's
--              settings, not the player's), and why = the words to show
--              (a layout or size that cannot be read: nil, nil and cause
--              "input"); eye (what the player should look at), flags (unsolved),
--              notes, checks, log (every change and why), layoutName, and
--              the pieces' rects for the preview picture (palette keys)
--
--   LayoutFit:Run(info, W, H, inputs, done, opts) -> job
--       the same fit as a coroutine stepped by Kit:NextFrame, about 2 ms of
--       solving a frame (opts.budget; opts.clock, debugprofilestop), then
--       done(fitted, places, report). The last result is kept by its inputs:
--       an unchanged screen and settings answer from it (LayoutFit:ClearCache()
--       forgets it). LayoutFit:Cancel(job) stops one.
--   LayoutFit:ScreenSize() -> W, H          UIParent's size (secret-safe)
--   LayoutFit:Inputs(read) -> inputs        read(module, key); the live
--                                           settings when nil
--   LayoutFit:ActionSlots(hasAction)        the hidden bars' slots holding
--                                           an action (shown: the user's choice), as data
--   LayoutFit:LayoutName(W, H, sw, sh, base) nil when W / H cannot be read
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
MelloUI.Perf:Scope("LayoutFit")   -- this file's load time (/melloperf load); it sets no script or timer

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number

local LayoutFit = {}
MelloUI.LayoutFit = LayoutFit

local floor, ceil, abs, min, max, sqrt, huge = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.huge
local format, byte, find, concat = string.format, string.byte, string.find, table.concat
local sort = table.sort
local pairs, ipairs, type, tostring, pcall = pairs, ipairs, type, tostring, pcall
local create, resume, status, running, yield = coroutine.create, coroutine.resume, coroutine.status, coroutine.running, coroutine.yield

local GAP = 8          -- the smallest gap the fitter leaves between two pieces
local EPS = 0.05
local GRID = 8         -- F9g's search grid
-- the screen the layout was drawn on: 3440 x 1440 at the scale this client
-- picks (0.64), 2866.67 x 1200 units -- the prototype's own arithmetic, so the
-- numbers are the same to the last bit
local DESIGN_H = 768 / 0.64
local DESIGN_W = DESIGN_H * 3440 / 1440
local DESIGN_ASPECT = DESIGN_W / DESIGN_H
LayoutFit.DESIGN_W, LayoutFit.DESIGN_H = DESIGN_W, DESIGN_H
LayoutFit.TOO_SMALL = "Your screen is too small for Mello's layout at your UI scale; your own Edit Mode layout stays."
LayoutFit.SETTINGS_FAIL = "Mello's layout fits your screen, but not with some of your settings; your own Edit Mode layout stays."
-- a screen inside this (UI units) is too small whatever fails; a FAIL on a
-- larger one is 'too small' only when the design's own settings fail there too
local SMALL_W, SMALL_H = 1400, 800

local EMPTY = {}

--------------------------------------------------------------------------------
-- Data: the Edit Mode systems, the settings the fit reads, the pieces
--------------------------------------------------------------------------------

-- the screen point's place on a frame, from the left and from the top
local AXX = { TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, LEFT = 0, CENTER = 0.5, RIGHT = 1, BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1 }
local AXY = { TOPLEFT = 0, TOP = 0, TOPRIGHT = 0, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
local CORNER = { TT = "TOPLEFT", TF = "TOPRIGHT", BT = "BOTTOMLEFT", BF = "BOTTOMRIGHT" }

-- Enum.EditModeSystem
local SYSTEM_NAME = {
	[0] = "ActionBar", [1] = "CastBar", [2] = "Minimap", [3] = "UnitFrame", [4] = "EncounterBar", [5] = "ExtraAbilities",
	[6] = "AuraFrame", [7] = "TalkingHeadFrame", [8] = "ChatFrame", [9] = "VehicleLeaveButton", [10] = "LootFrame",
	[11] = "HudTooltip", [12] = "ObjectiveTracker", [13] = "MicroMenu", [14] = "Bags", [15] = "StatusTrackingBar",
	[16] = "DurabilityFrame", [17] = "TimerBars", [18] = "VehicleSeatIndicator", [19] = "ArchaeologyBar",
	[20] = "CooldownViewer", [21] = "PersonalResourceDisplay", [22] = "EncounterEvents", [23] = "DamageMeter",
	[24] = "RaidWarning", [25] = "TotemActionBar", [26] = "MainActionBarEndCap", [27] = "GroupFinder",
	[28] = "LossOfControl", [29] = "SwingTimer",
}
-- the systems with indices: [systemIndex] = its name (for the log)
local INDEX_NAME = {
	ActionBar = { "MainBar", "Bar2", "Bar3", "RightBar1", "RightBar2", "ExtraBar1", "ExtraBar2", "ExtraBar3", [11] = "StanceBar", [12] = "PetActionBar", [13] = "PossessActionBar" },
	UnitFrame = { "Player", "Target", "Focus", "Party", "Raid", "Boss", "Arena", "Pet" },
	AuraFrame = { "BuffFrame", "DebuffFrame", "ExternalDefensivesFrame" },
	StatusTrackingBar = { "StatusTrackingBar1", "StatusTrackingBar2" },
	CooldownViewer = { "Essential", "Utility", "BuffIcon", "BuffBar" },
	EncounterEvents = { "Timeline", "CriticalWarnings", "MediumWarnings", "NormalWarnings" },
	MainActionBarEndCap = { "EndCapLeft", "EndCapRight" },
	SwingTimer = { "MainHand", "OffHand", "Ranged" },
}
-- the global frame each record drives ([0] = a system without indices);
-- chained records anchor to these names
local FRAME = {
	ActionBar = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", [11] = "StanceBar", [12] = "PetActionBar", [13] = "PossessActionBar" },
	CastBar = { [0] = "PlayerCastingBarFrame" }, Minimap = { [0] = "MinimapCluster" },
	UnitFrame = { "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame", "CompactRaidFrameContainer", "BossTargetFrameContainer", "CompactArenaFrame", "PetFrame" },
	EncounterBar = { [0] = "EncounterBar" }, ExtraAbilities = { [0] = "ExtraAbilityContainer" },
	AuraFrame = { "BuffFrame", "DebuffFrame", "ExternalDefensivesFrame" },
	TalkingHeadFrame = { [0] = "TalkingHeadFrame" }, ChatFrame = { [0] = "ChatFrame1" },
	VehicleLeaveButton = { [0] = "MainMenuBarVehicleLeaveButton" }, LootFrame = { [0] = "LootFrame" },
	HudTooltip = { [0] = "GameTooltipDefaultContainer" }, ObjectiveTracker = { [0] = "ObjectiveTrackerFrame" },
	MicroMenu = { [0] = "MicroMenuContainer" }, Bags = { [0] = "BagsBar" },
	StatusTrackingBar = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
	DurabilityFrame = { [0] = "DurabilityFrame" }, TimerBars = { [0] = "MirrorTimerContainer" },
	VehicleSeatIndicator = { [0] = "VehicleSeatIndicator" }, ArchaeologyBar = { [0] = "ArcheologyDigsiteProgressBar" },
	CooldownViewer = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" },
	PersonalResourceDisplay = { [0] = "PersonalResourceDisplayFrame" },
	EncounterEvents = { "EncounterTimeline", "CriticalEncounterWarnings", "MediumEncounterWarnings", "MinorEncounterWarnings" },
	DamageMeter = { [0] = "DamageMeter" }, RaidWarning = { [0] = "RaidWarningFrame" }, TotemActionBar = { [0] = "MultiCastActionBarFrame" },
	MainActionBarEndCap = { "MainActionBar.EndCaps.LeftEndCap", "MainActionBar.EndCaps.RightEndCap" },
	GroupFinder = { [0] = "QueueStatusButton" }, LossOfControl = { [0] = "LossOfControlFrame" },
	SwingTimer = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" },
}
-- in their default position the game's managed containers place these, not
-- their anchor ([true] = every index of the system)
local MANAGED = {
	ActionBar = { [11] = true, [12] = true, [13] = true }, UnitFrame = { [6] = true, [7] = true, [8] = true },
	StatusTrackingBar = { [1] = true, [2] = true },
	CastBar = true, EncounterBar = true, ExtraAbilities = true, TalkingHeadFrame = true, VehicleLeaveButton = true,
	ArchaeologyBar = true, SwingTimer = true, ObjectiveTracker = true, DurabilityFrame = true, VehicleSeatIndicator = true,
}

-- The settings the fit reads or writes: the id, and the dialog's stored ->
-- shown rule (settings_table.md): "raw" as stored, "pct" lo + raw x step,
-- "diff" lo + raw, "list" a dropdown's option name, "check" a checkbox.
-- Shown values are clamped to lo..hi like the game's.
local function Slider(id, conv, lo, hi, step)
	return { id = id, conv = conv, lo = lo, hi = hi, step = step }
end
local function List(id, options)
	return { id = id, conv = "list", options = options }
end
local function Check(id)
	return { id = id, conv = "check" }
end
local ORIENTATION = { [0] = "HORIZONTAL", "VERTICAL" }
local SETTINGS = {
	ActionBar = { Orientation = List(0, ORIENTATION), NumRows = Slider(1, "raw", 1, 4), NumIcons = Slider(2, "raw", 6, 12),
		IconSize = Slider(3, "pct", 50, 200, 10), IconPadding = Slider(4, "raw", 2, 10),
		VisibleSetting = List(5, { [0] = "ALWAYS", "IN_COMBAT", "OUT_OF_COMBAT", "HIDDEN" }) },
	CastBar = { BarSize = Slider(0, "pct", 100, 150, 10) },
	Minimap = { Size = Slider(2, "pct", 50, 200, 10) },
	UnitFrame = { UseLargerFrame = Check(3), FrameWidth = Slider(10, "diff", 72, 144), FrameHeight = Slider(11, "diff", 36, 72),
		FrameSize = Slider(16, "pct", 100, 200, 5) },
	AuraFrame = { IconLimitBuffFrame = Slider(3, "raw", 2, 32), IconLimitDebuffFrame = Slider(4, "raw", 1, 16),
		IconSize = Slider(5, "pct", 50, 200, 10), IconPadding = Slider(6, "raw", 5, 15) },
	-- composite: width = Hundreds x 100 + TensAndOnes (never a whole number in one)
	ChatFrame = { WidthHundreds = Slider(0, "raw", 0, 8), WidthTensAndOnes = Slider(1, "raw", 0, 99),
		HeightHundreds = Slider(2, "raw", 0, 8), HeightTensAndOnes = Slider(3, "raw", 0, 99) },
	DamageMeter = { Visibility = List(0, { [0] = "ALWAYS", "IN_COMBAT", "HIDDEN", "IN_GROUP" }),
		FrameWidth = Slider(3, "diff", 200, 600), FrameHeight = Slider(4, "diff", 120, 400) },
	ObjectiveTracker = { Height = Slider(0, "pct", 400, 1000, 10) },
	MicroMenu = { Orientation = List(0, ORIENTATION), Size = Slider(2, "pct", 70, 200, 5) },
	Bags = { Orientation = List(0, ORIENTATION), Size = Slider(2, "pct", 75, 200, 5) },
	StatusTrackingBar = { Size = Slider(3, "pct", 50, 130, 5) },
	DurabilityFrame = { Size = Slider(0, "pct", 75, 200, 5) },
	TimerBars = { Size = Slider(0, "pct", 100, 150, 10) },
	VehicleSeatIndicator = { Size = Slider(0, "pct", 50, 100, 5) },
	ArchaeologyBar = { Size = Slider(0, "pct", 100, 200, 5) },
	GroupFinder = { Size = Slider(0, "pct", 50, 150, 5) },
	LossOfControl = { Size = Slider(0, "pct", 50, 200, 10) },
	SwingTimer = { Scale = Slider(0, "pct", 50, 200, 10), Visibility = List(2, { [0] = "ALWAYS", "IN_COMBAT", "HIDDEN" }),
		Width = Slider(3, "diff", 213, 852), Height = Slider(4, "diff", 15, 60) },
	MainActionBarEndCap = { Hidden = Check(0) },
}

-- the records the rules read directly: a layout without them is not the approved one
local REQUIRED = { "0:0", "1:-1", "2:-1", "3:0", "3:1", "3:2", "3:4", "3:5", "5:-1", "6:0", "6:1", "6:2", "8:-1",
	"11:-1", "12:-1", "13:-1", "16:-1", "23:-1", "24:-1", "26:0", "26:1" }

-- The pieces' categories: A always, T with a target, O out of combat, C in
-- combat, K while casting, M on mouseover (these overlap the play for real);
-- S situational, V on a taxi, L while looting, P pet / totem class only;
-- Q the test client's own button (reported, never counted)
local PERSISTENT = { A = true, T = true, O = true, C = true, K = true, M = true }
-- the preview's outline for each (MelloUI.Palette keys only)
local OUTLINE = { A = "selectedTrim", T = "selectedTrim", K = "selectedTrim", M = "selectedTrim", O = "trim", C = "trim",
	S = "mutedText", V = "mutedText", L = "mutedText", P = "mutedText", Q = "border" }

-- When a piece is on the screen: two pieces 'show together' when their
-- situations meet, and such an overlap counts as hard even when one of them
-- shows only now and then (the boss frames always come with a target)
local SITUATIONS = { "boss", "combat", "gfight", "group", "idle", "taxi" }   -- (alphabetical: the report's order)
local ALL_SIT = { idle = true, combat = true, group = true, gfight = true, boss = true, taxi = true }
local FIGHT = { combat = true, gfight = true, boss = true }
local GROUPED = { group = true, gfight = true, boss = true }
local SIT_BY_CAT = {
	A = ALL_SIT, M = ALL_SIT, P = ALL_SIT,
	T = { idle = true, combat = true, group = true, gfight = true, boss = true },
	K = { idle = true, combat = true, group = true, gfight = true, boss = true },
	O = { idle = true, group = true, taxi = true },
	C = FIGHT,
}
local SIT_BY_NAME = {
	["Boss frames"] = { boss = true },
	["Extra ability"] = { combat = true, boss = true },
	["Focus frame"] = { gfight = true, boss = true },
	["Debuffs"] = FIGHT, ["External defensives"] = FIGHT,
	["Party frames"] = GROUPED, ["Raid frames (8 groups of 5)"] = GROUPED,
	["Durability doll"] = ALL_SIT, ["Second tracked bar"] = ALL_SIT, ["Queue eye"] = ALL_SIT,
	["Possess bar"] = { combat = true, boss = true },
	["Vehicle / taxi exit"] = { taxi = true },
	-- shows for a moment while the cursor rests on something (MelloUI puts
	-- tooltips at the cursor): never counted as showing together
	["Tooltip fallback corner"] = {},
}

-- pairs allowed by design: nested pieces, and pieces that never show together
local NEST = {
	{ "Bar panel backdrop", "Action Bar 1" }, { "Bar panel backdrop", "Action Bar 2" }, { "Bar panel backdrop", "Action Bar 3" },
	{ "Bar panel backdrop", "Action Bar 4" }, { "Bar panel backdrop", "Stance tab (kit plate)" },
	{ "Bar panel backdrop", "End cap left (painted)" }, { "Bar panel backdrop", "End cap right (painted)" },
	{ "Bar panel backdrop", "Pet bar tab" }, { "Bar panel backdrop", "Totem bar tab (Wrath-style shaman)" },
	{ "Minimap (kit frame + zone plate)", "Queue eye" }, { "Target frame", "Target auras (MelloUI row)" },
	{ "Minimap (kit frame + zone plate)", "Services panel (MelloUI)" },   -- one column (a bar offset may lay the bar on the frame's rim)
	{ "Player frame", "Pet frame" }, { "XP bar", "Second tracked bar" }, { "Chat panel", "Chat tabs" },
	{ "Micro menu (kit row)", "Bag bar" },   -- joined backdrops by design
}
local EXCL = {
	{ "Cast bar + kit text", "Vehicle / taxi exit" }, { "Possess bar", "Vehicle / taxi exit" },
	{ "Pet bar tab", "Stance tab (kit plate)" }, { "Pet bar tab", "Totem bar tab (Wrath-style shaman)" },
	{ "Possess bar", "Pet bar tab" }, { "Possess bar", "Stance tab (kit plate)" },
	{ "Party frames", "Raid frames (8 groups of 5)" },
	{ "Totem bar tab (Wrath-style shaman)", "Stance tab (kit plate)" },   -- shamans have no stance bar in Classic
	{ "Totem bar tab (Wrath-style shaman)", "Possess bar" },              -- only priests possess
}
local RULES   -- [name][name] = "nest" | "excl", made on the first fit

local BARS = { { "0:0", "Action Bar 1" }, { "0:1", "Action Bar 2" }, { "0:2", "Action Bar 3" }, { "0:3", "Action Bar 4" },
	{ "0:4", "Action Bar 5 (utility tray)" }, { "0:5", "Action Bar 6" }, { "0:6", "Action Bar 7" }, { "0:7", "Action Bar 8" } }
local PANEL_BARS = { "0:1", "0:2", "0:3" }   -- chained on Bar 1 inside the painted panel
local PANEL_KEYS = { "0:0", "0:1", "0:2", "0:3" }
local SWINGS = { { "29:0", "Swing timer main hand" }, { "29:1", "Swing timer off hand" }, { "29:2", "Swing timer ranged" } }

-- the Immersive hides Action Bars 3, 4, 6, 7 and 8; their action slots (page
-- p holds slots (p - 1) x 12 + 1 .. p x 12)
local BAR_SLOTS = {
	{ "0:2", 49, 60, "Action Bar 3 (MultiBarBottomRight, page 5)" },
	{ "0:3", 25, 36, "Action Bar 4 (MultiBarRight, page 3)" },
	{ "0:5", 145, 156, "Action Bar 6 (MultiBar5, page 13)" },
	{ "0:6", 157, 168, "Action Bar 7 (MultiBar6, page 14)" },
	{ "0:7", 169, 180, "Action Bar 8 (MultiBar7, page 15)" },
}

-- F11: smaller Edit Mode sizes, cumulative, tried when the bottom band does not fit
local COMPACT = {
	{ "unit frames 100%", { { "3:0", "FrameSize", 0 }, { "3:1", "FrameSize", 0 } } },
	{ "micro menu 70% and bag bar 75%", { { "13:-1", "Size", 0 }, { "14:-1", "Size", 0 } } },
	{ "action bars 90%", { { "0:0", "IconSize", 4 }, { "0:1", "IconSize", 4 }, { "0:2", "IconSize", 4 }, { "0:3", "IconSize", 4 } } },
	{ "action bars 80%", { { "0:0", "IconSize", 3 }, { "0:1", "IconSize", 3 }, { "0:2", "IconSize", 3 }, { "0:3", "IconSize", 3 } } },
	{ "action bars 70%", { { "0:0", "IconSize", 2 }, { "0:1", "IconSize", 2 }, { "0:2", "IconSize", 2 }, { "0:3", "IconSize", 2 } } },
}
local AURA_SIZES = { { 5, "100%" }, { 4, "90%" }, { 3, "80%" } }   -- AuraFrame IconSize raw
local AURA_NAMES = { "Buffs", "Debuffs", "External defensives" }
local AURA_KEYS = { "6:0", "6:1", "6:2" }
local GROUP_UNITS = { "party", "raid" }

local CHAT_MIN_W = 300       -- beside the bars: never narrower than the damage meter
local CHAT_GAME_MIN_W = 250  -- lifted, out of the centre third: the game's own minimum
local CHAT_MIN_H = 120       -- the game's own minimum
local TRACKER_MIN = 200      -- never shorter
local TRACKER_KEEP = 300     -- shortened for the bottom centre only down to this; below it the centre slides

-- the pieces that show now and then, placed biggest first; each avoids the
-- ones placed before it, the ones after it make room (LATER)
local PIECE = {
	boss = { "Boss frames", "3:5" }, party = { "Party frames", "3:3" }, raid = { "Raid frames (8 groups of 5)", "3:4" },
	focus = { "Focus frame", "3:2" }, extra = { "Extra ability", "5:-1" }, doll = { "Durability doll", "16:-1" },
	tooltip = { "Tooltip fallback corner", "11:-1" },
}
local LATER = {
	boss = { party = true, raid = true, focus = true, extra = true, doll = true, tooltip = true },
	party = { raid = true, focus = true, extra = true, doll = true, tooltip = true },
	raid = { focus = true, extra = true, doll = true, tooltip = true },
	focus = { extra = true, doll = true, tooltip = true },
	extra = { doll = true, tooltip = true },
	doll = { tooltip = true },
	tooltip = {},
}

-- Frames Edit Mode places that UI Modifications' movers can also keep a place for
local EDIT_MODE_FRAMES = { "MinimapCluster", "DamageMeter", "ChatFrame1", "ObjectiveTrackerFrame" }
LayoutFit.EDIT_MODE_FRAMES = EDIT_MODE_FRAMES   -- (read only: the installer keeps the player's own places of these)

-- The windows the fit places (those with a place in the user's snapshot;
-- any other store entry is left as it is): size in UI units from the
-- client source; checkFit = the game's panel manager scales the window down
-- to fit (with this extra room), fit = MelloUI's own FitToScreen; [5] how
-- far windows that open one after the other from the stored place reach
-- right and down past the first; `dress` = { left, right, top, bottom }, how
-- far a window's own dressing reaches past its frame, in its units (counted
-- by its fit and in its rect). The two store places wave 3 moved into the
-- one store and Full ships (with the minimap column's refit): the voice
-- overlay (Modules/VoiceOver.lua FRAME_W, FRAME_H at its default Overlay
-- Scale) and the whisper popups (Modules/Chat.lua POPUP_W, POPUP_H; six
-- places, each 24 right and 24 down of the one before). The configurator
-- (Core/Config.lua): its wide width (WIDE_WIDTH, when UI Modifications' tabs
-- need it), fitted by its shell (Modules/KitWindow.lua Shell:Fit, 16 of room)
-- with the kit's dressing: the outer rail (Kit:OuterRailOutset, 42 x 0.375)
-- on every side and the crest over the top (Kit:RailMiddle 6.375 + half the
-- ring, 197 x 0.375 x 1.25 / 2)
local WINDOWS = {
	CharacterFrame = { 631, 484 }, FriendsFrame = { 385, 424 }, MacroFrame = { 338, 424 },
	ProfessionsFrame = { 673, 594, 20, 20 }, LFGParentFrame = { 458, 535 }, CommunitiesFrame = { 814, 426 },
	PlayerSpellsFrame = { 1618, 883, 200, 140 }, CollectionsJournal = { 703, 606 }, LegacySystemFrame = { 920, 575 },
	ContainerFrameCombinedBags = { 430, 440 },
	MelloUIConfigFrame = { 1080, 760, 16, 16, dress = { 15.75, 15.75, 52.546875, 15.75 } },
	voiceOverlay = { 600, 200 }, whisper = { 340, 210, nil, nil, 5 * 24 },
}
-- The design's own MelloUI settings (the approved snapshot's, the tracker
-- hung on 12:-1 as every fit leaves it). What the approved layout already
-- overlaps at its screen with these is 'inherited'; a FAIL that these pass
-- on the same screen is the player's settings, not the screen's size. (The
-- window places are the player's own: Full's come from its baked profile.)
local DESIGN_INPUTS = { tracker = { width = 300, maxHeight = 440, scale = 1 }, questlist = { width = 380 } }

--------------------------------------------------------------------------------
-- The minimap column of layout E (the refit: since the flip
-- the map's size is Edit Mode's alone -- Minimap, Size -- and the Quest
-- Tracker and the Services row follow the map's width). One table: this file
-- is at Lua's limit of top-level locals. Its functions are below the rects.
--   the minimap cluster (Blizzard_Minimap/Mainline/Minimap.xml): a
--   ResizeLayoutFrame (Blizzard_SharedXML/LayoutFrame.lua, widthPadding 20)
--   sized round its shown children -- the map's container (the frame art,
--   215 x 226, Camelot/Skin.lua) scaled by the Size, its TOP 10 right and 30
--   down of the cluster's top middle in the cluster's own units at any Size
--   (SetHeaderUnderneath lays it at offset / scale); the zone band (175 x 16,
--   15 right, 4 down) with the tracking button (17 + 2) left of it and the
--   calendar (1 + 19) right of it -- and the map (198) in the container's
--   middle. MelloUI's column under it (Modules/MinimapPanel.lua's contract;
--   top to bottom as M:ColumnOrder has it by default: the zone band, the
--   map, Route's distance line, the Services row, the tracker): the painted
--   frame and the Services bar live in the map's container, so their
--   measures are map units, times the Size on the screen.
--------------------------------------------------------------------------------

local Column = {
	-- the painted frame's rims round the map (left, top, right, bottom), as
	-- MinimapPanel's LaySquare lays them (a rail's opaque depth at Kit.scale
	-- x the border's scale, less the 1 px it lies over the map): the kit's
	-- square borders; the kit's round ring (window/portrait_ring from the map
	-- x 0.75 of its opening: its opaque box past the map); the game's own
	-- frame art (the container) when the Minimap Kit is off
	RAILS = { window = { 17, 17.375, 16.625, 17.375 }, single = { 5.6, 5.6, 5.6, 5.6 }, red = { 9.875, 11.75, 9.875, 11.75 },
		iron = { 9.875, 11.75, 9.875, 11.75 }, none = { 0, 0, 0, 0 } },
	RING = { 20.65, 20.65, 20.65, 20.65 },
	GAME = { 8.5, 14, 8.5, 14 },
	-- the window frame's bottom gem corners paint below its bottom rail
	-- (MinimapPanel GemReach: window/frame_gem_bl's overhang 12 less the 7
	-- clear rows under its box, x Kit.scale 0.375): the column's bottom,
	-- so the tracker hangs clear of them (user, 2026-09-26)
	GEM_B = { window = 1.875 },
	-- the Services bar (Modules/Services.lua LayoutBar): width, height, the
	-- stone above it merged (the divider rail's band, MinimapPanel's
	-- M:DividerHeight(), 26 with either Button Layout; Groups: one row of 5
	-- cells min(38, (198 - 6 x 4) / 5) with 5 above and under; All Buttons:
	-- two rows -- merged as wide as the map, loose 26 px icons in the kit's
	-- rim, the round rim or none)
	ROW_GROUPS = { 198, 44.8, 26 }, ROW_ALL_MERGED = { 198, 81.6, 26 },
	ROW_ALL_KIT = { 244, 100.6 }, ROW_ALL_ROUND = { 222, 91.8 }, ROW_ALL_PLAIN = { 160, 67 },
	LINE_GAP = 2, LINE_H = 12,   -- Route's distance line (MinimapPanel LINE_GAP, LINE_H)
	AURA_GAP = 13,               -- Modules/Auras.lua ATTACH_GAP
	-- the minimap's Size for layout E (raw: 50 + 10 x raw %): 150 %, the map
	-- 198 x 1.5 = 297 wide, about the Quest Tracker's design width, 300 (160 %
	-- would be 317); smaller steps, down to the approved layout's own size,
	-- only where the tracker or your buff rows have no room
	SIZE_DESIGN = 10, TRACKER_DESIGN_W = 300,
	ROWS_LEAST = 6,              -- Auras' Icons Per Row slider's least
	BOSS_GAP = 20,               -- the design's gap between the boss frames and the tracker (-325.8 against -5.8 - 300)
	-- the design's MelloUI settings for the column and your buff rows (Full's:
	-- the square map in the window frame merged with the Services groups, the
	-- tracker matching the minimap's width, your buff rows by the column)
	DESIGN = { kit = true, shape = "square", border = "window", merge = true, bar = true, groups = true, barOffset = -26,
		roundIcons = true, match = true },
	DESIGN_AURAS = { rows = true, attached = true, size = 38, perRow = 12 },
	ROW_NAMES = { "Buffs", "Debuffs" },
}
DESIGN_INPUTS.column, DESIGN_INPUTS.auras = Column.DESIGN, Column.DESIGN_AURAS
-- MelloUI's settings as the approved layout was drawn with them (the
-- 2026-09-24 snapshot, before layout E's options): the Services bar's two
-- rows, the Quest Tracker at its own width, your buff rows on the game's buff
-- bar's place. What that layout overlaps at its own screen with these is
-- 'inherited' (Inherit, below).
Column.APPROVED_INPUTS = { tracker = DESIGN_INPUTS.tracker, questlist = DESIGN_INPUTS.questlist,
	column = { kit = true, shape = "square", border = "window", merge = true, bar = true, groups = false, barOffset = -26,
		roundIcons = true, match = false },
	auras = { rows = true, attached = false, size = 38, perRow = 12 } }

-- unit groups the rules test
local U_CORE_FRAMES = { core = true, frames = true }
local U_RIGHT = { br = true, tracker = true, auras = true, minimap = true }
local U_LEFT = { chat = true, meter = true }
local U_BR = { br = true }
local U_BR_CENTRE = { br = true, core = true, frames = true }
local U_CHAT = { chat = true }
local U_MAIN = { core = true, frames = true, chat = true, br = true, tracker = true, minimap = true, meter = true }
local U_COLUMN = { auras = true, minimap = true }

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- Python's round(v, 1): the nearest tenth, a tie (x.x5 exactly) to even
-- through the C formatter, a small negative to -0.0; the prototype rounds
-- every offset and every system rect this way
local function Round1(v)
	local x = v * 10
	local frac = x - floor(x)
	if abs(frac - 0.5) < 1e-6 then
		return tonumber(format("%.1f", v))
	end
	local r = floor(x + 0.5)
	if r == 0 and v < 0 then
		return v * 0   -- (-0.0, as the prototype keeps it)
	end
	return r / 10
end

-- the integer part, for a %d of a number that may carry a fraction
local function Int(v)
	if v >= 0 then
		return floor(v)
	end
	return ceil(v)
end

local function On(v)
	return v ~= nil and v ~= false and v ~= 0
end

-- byte order, whatever the client's collation
local function ByteLess(a, b)
	local la, lb = #a, #b
	for i = 1, min(la, lb) do
		local ca, cb = byte(a, i), byte(b, i)
		if ca ~= cb then
			return ca < cb
		end
	end
	return la < lb
end

local function AnchorRect(rl, rt, rr, rb, point, relPoint, ox, oy, w, h)
	local px = rl + (rr - rl) * AXX[relPoint] + ox
	local py = rt + (rb - rt) * AXY[relPoint] - oy
	local L = px - AXX[point] * w
	local T = py - AXY[point] * h
	return L, T, L + w, T + h
end

-- vertical / horizontal overlap of two spans (more than -g apart)
local function Yov(at, ab, bt, bb, g)
	return min(ab, bb) - max(at, bt) > -g + EPS
end
local function Xov(al, ar, bl, br, g)
	return min(ar, br) - max(al, bl) > -g + EPS
end

local function Off(l, t, r, b, W, H)
	return l < -EPS or t < -EPS or r > W + EPS or b > H + EPS
end

local function Tables()
	if RULES then
		return
	end
	RULES = {}
	local function Put(list, rule)
		for _, pair in ipairs(list) do
			local a, b = pair[1], pair[2]
			RULES[a] = RULES[a] or {}
			RULES[b] = RULES[b] or {}
			RULES[a][b] = RULES[a][b] or rule
			RULES[b][a] = RULES[b][a] or rule
		end
	end
	Put(NEST, "nest")
	Put(EXCL, "excl")
end

local function CopyPlace(p)
	local c = {}
	for k, v in pairs(p) do
		c[k] = v
	end
	return c
end

local function PlaceText(p)
	return format("{point=%s, relPoint=%s, x=%s, y=%s}", tostring(p.point), tostring(p.relPoint), tostring(p.x), tostring(p.y))
end

--------------------------------------------------------------------------------
-- The working state: a copy of the layout, its settings by id, the pieces
--------------------------------------------------------------------------------

local function Bump(f)
	f.version = f.version + 1
end

-- The coroutine's hand-over point: its frame's share used up, the rest waits
-- for the next frame. `longest` (the longest stretch between two of these,
-- at most half the budget; never taken below a quarter of it, so a longer
-- stretch than any seen yet still ends inside the budget) keeps a frame's
-- solving under its budget.
local function JobStep(job)
	if not job then
		return
	end
	local now = job.clock()
	local seg = now - job.mark
	if seg > job.longest then
		job.longest = min(seg, job.budget / 2)
	end
	job.mark = now
	if now + max(job.longest, job.budget / 4) >= job.deadline and running() == job.co then
		yield()
	end
end

local function Step(f)
	JobStep(f.job)
end

local function Setting(f, s, name)
	local def = SETTINGS[f.meta[s].name]
	def = def and def[name]
	local e = def and f.sv[s][def.id]
	return e and e.value
end

-- the value the settings dialog shows
local function Disp(f, s, name)
	local def = SETTINGS[f.meta[s].name]
	def = def and def[name]
	local e = def and f.sv[s][def.id]
	if not e then
		return nil
	end
	local raw, conv = e.value, def.conv
	if conv == "list" then
		return def.options[raw]
	elseif conv == "check" then
		return min(max(raw, 0), 1) ~= 0
	end
	local v = raw
	if conv == "pct" then
		v = raw * def.step + def.lo
	elseif conv == "diff" then
		v = raw + def.lo
	end
	return min(max(v, def.lo), def.hi)
end

local function SetRaw(f, s, name, raw)
	local def = SETTINGS[f.meta[s].name][name]
	local e = def and f.sv[s][def.id]
	if not e then
		error(format("%s has no setting %s", f.meta[s].key, name), 0)
	end
	e.value = raw
	Bump(f)
end

local function Log(f, rule, key, what, why)
	local log = f.log
	log[#log + 1] = { rule = rule, key = key, what = what, why = why }
end
local function Eye(f, text)
	f.eye[#f.eye + 1] = text
end
local function Note(f, text)
	f.notes[#f.notes + 1] = text
end
local function Flag(f, text)
	f.flags[#f.flags + 1] = text
end

local function Set(f, key, name, raw, rule, why)
	local s = f.rec[key]
	local old = Setting(f, s, name)
	if old == raw then
		return
	end
	SetRaw(f, s, name, raw)
	Log(f, rule, key, format("%s %s %s -> %s", f.meta[s].name, name, tostring(old), tostring(raw)), why)
end

local function SystemLabel(m)
	local names = INDEX_NAME[m.name]
	local idxName = names and m.idx and names[m.idx]
	return idxName and (m.name .. "." .. idxName) or m.name
end

local function Move(f, key, rule, why, point, relPoint, x, y)
	local s = f.rec[key]
	local a = s.anchorInfo
	local bp, brp, bx, by = a.point, a.relativePoint, a.offsetX, a.offsetY
	if point then
		a.point = point
	end
	if relPoint then
		a.relativePoint = relPoint
	end
	if x ~= nil then
		a.offsetX = Round1(x) + 0.0   -- (+0.0: never a -0.0 the prototype would not write)
	end
	if y ~= nil then
		a.offsetY = Round1(y) + 0.0
	end
	Bump(f)
	if a.point ~= bp or a.relativePoint ~= brp or a.offsetX ~= bx or a.offsetY ~= by then
		s.isInDefaultPosition = false
		Log(f, rule, key, format("%s %s->%s %s (%.1f, %.1f) [was %s->%s %s (%.1f, %.1f)]", SystemLabel(f.meta[s]),
			a.point, a.relativePoint, tostring(a.relativeTo), a.offsetX, a.offsetY, bp, brp, tostring(a.relativeTo), bx, by), why)
	end
end

local function Shift(f, key, rule, why, dx, dy)
	local a = f.rec[key].anchorInfo
	Move(f, key, rule, why, nil, nil, a.offsetX + dx, a.offsetY + dy)
end

-- the layout's changeable values into `buf` and back: a candidate is tried
-- and taken back without copying the layout (the prototype deep-copied it)
local function SaveLayout(f, buf)
	local n = 0
	local systems = f.systems
	for i = 1, #systems do
		local s = systems[i]
		local a = s.anchorInfo
		buf[n + 1], buf[n + 2], buf[n + 3], buf[n + 4], buf[n + 5], buf[n + 6] = a.point, a.relativePoint, a.relativeTo, a.offsetX, a.offsetY, s.isInDefaultPosition
		n = n + 6
		local list = s.settings
		for j = 1, #list do
			n = n + 1
			buf[n] = list[j].value
		end
	end
	return n
end

local function RestoreLayout(f, buf)
	local n = 0
	local systems = f.systems
	for i = 1, #systems do
		local s = systems[i]
		local a = s.anchorInfo
		a.point, a.relativePoint, a.relativeTo, a.offsetX, a.offsetY, s.isInDefaultPosition = buf[n + 1], buf[n + 2], buf[n + 3], buf[n + 4], buf[n + 5], buf[n + 6]
		n = n + 6
		local list = s.settings
		for j = 1, #list do
			n = n + 1
			list[j].value = buf[n]
		end
	end
	Bump(f)
	return n
end

local function Truncate(list, n)
	for i = #list, n + 1, -1 do
		list[i] = nil
	end
end

-- the whole trial state: the layout, the tracker's and Quest List's sizes,
-- your buff rows' icon size and length, and the lengths of the lists a trial
-- appends to
local function Save(f, buf)
	local n = SaveLayout(f, buf)
	local t, a = f.mello.tracker, f.mello.auras
	buf[n + 1], buf[n + 2], buf[n + 3] = t.width, t.maxHeight, f.mello.questlist.width
	buf[n + 4], buf[n + 5], buf[n + 6], buf[n + 7] = #f.log, #f.eye, #f.notes, #f.flags
	buf[n + 8], buf[n + 9] = a.size, a.perRow
	return buf
end

local function Restore(f, buf)
	local n = RestoreLayout(f, buf)
	local t, a = f.mello.tracker, f.mello.auras
	t.width, t.maxHeight, f.mello.questlist.width = buf[n + 1], buf[n + 2], buf[n + 3]
	a.size, a.perRow = buf[n + 8], buf[n + 9]
	Truncate(f.log, buf[n + 4])
	Truncate(f.eye, buf[n + 5])
	Truncate(f.notes, buf[n + 6])
	Truncate(f.flags, buf[n + 7])
end

local function CopyInfo(v)
	if type(v) ~= "table" then
		return v
	end
	local c = {}
	for k, x in pairs(v) do
		c[k] = CopyInfo(x)
	end
	return c
end

-- the layout info checked and copied, with each record's name, key, frame
-- and settings by id; nil and why when it is not a layout this fit knows
local function NewState(info, job)
	if type(info) ~= "table" or type(info.systems) ~= "table" then
		return nil, "no layout"
	end
	-- the copy the fit works on (a record at a time: the runner may hand over between them)
	local copy = { systems = {} }
	for k, v in pairs(info) do
		if k ~= "systems" then
			copy[k] = CopyInfo(v)
		end
	end
	for i = 1, #info.systems do
		if i % 16 == 0 then
			JobStep(job)
		end
		copy.systems[i] = CopyInfo(info.systems[i])
	end
	local f = { info = copy, job = job, meta = {}, rec = {}, sv = {}, byFrame = {}, version = 1, solved = 0, built = 0,
		R = {}, rPool = {}, FR = {}, frPool = { UIParent = {} }, order = {}, nOrder = 0, inPend = {}, stamp = 0, pendA = {}, pendB = {},
		E = {}, nE = 0, N = {}, pool = {}, inh = {}, log = {}, eye = {}, notes = {}, flags = {},
		snapA = {}, snapP = {}, bestScore = {}, curScore = {} }
	f.systems = f.info.systems
	Step(f)
	for i = 1, #f.systems do
		if i % 16 == 0 then
			Step(f)
		end
		local s = f.systems[i]
		local a = type(s) == "table" and s.anchorInfo
		-- (every value the fit keys a table with or counts with: secret tested first)
		local name = type(s) == "table" and not Secret(s.system) and SYSTEM_NAME[s.system]
		if not (type(a) == "table" and name and type(s.settings) == "table") or Secret(s.systemIndex) or Secret(s.isInDefaultPosition) then
			return nil, "layout record " .. i .. " is not readable"
		end
		local x, y = a.offsetX, a.offsetY
		if Secret(x) or Secret(y) or Secret(a.point) or Secret(a.relativePoint) or Secret(a.relativeTo)
			or type(x) ~= "number" or type(y) ~= "number" or not AXX[a.point] or not AXX[a.relativePoint] then
			return nil, "layout record " .. i .. " has no readable anchor"
		end
		local idx = s.systemIndex
		if idx ~= nil and type(idx) ~= "number" then
			return nil, "layout record " .. i .. " is not readable"
		end
		local key = s.system .. ":" .. (idx and (idx - 1) or -1)
		local frames = FRAME[name]
		local m = { name = name, idx = idx, key = key, frame = frames and frames[idx or 0] }
		f.meta[s] = m
		f.rec[key] = s
		if m.frame then
			f.byFrame[m.frame] = s
		end
		local byId = {}
		for j = 1, #s.settings do
			local e = s.settings[j]
			if type(e) ~= "table" or Secret(e.setting) or Secret(e.value) or type(e.value) ~= "number" then
				return nil, "layout record " .. i .. " has an unreadable setting"
			end
			byId[e.setting] = e
		end
		f.sv[s] = byId
	end
	for _, key in ipairs(REQUIRED) do
		if not f.rec[key] then
			return nil, "the layout has no record " .. key
		end
	end
	f.base = {}
	SaveLayout(f, f.base)
	f.srcRaidWidth = Setting(f, f.rec["3:4"], "FrameWidth")
	return f
end

local function BarsFor(inputs)
	local bars = {}
	local slots = inputs.actionSlots
	if type(slots) == "table" then
		for _, bar in ipairs(BAR_SLOTS) do
			for slot = bar[2], bar[3] do
				if slots[slot] then
					bars[#bars + 1] = bar[1]
					break
				end
			end
		end
	elseif type(inputs.barsWithActions) == "table" then
		for i, key in ipairs(inputs.barsWithActions) do
			bars[i] = key
		end
	end
	return bars
end

-- MelloUI's own settings, as the fit works on them (a fresh copy per try).
-- A tracker width or height of 0 (or less) is the game's tracker's, as
-- QuestTracker reads it (FrameWidth, SetOrGameHeight): gameW / gameH, sized
-- from 12:-1 by Reset; nil is the design's own.
local function MelloFrom(inputs)
	local positions = {}
	for name, p in pairs(type(inputs.positions) == "table" and inputs.positions or EMPTY) do
		if type(p) == "table" then
			positions[name] = CopyPlace(p)
		end
	end
	local t = type(inputs.tracker) == "table" and inputs.tracker or EMPTY
	local pos = t.pos
	local width, height, scale = Num(t.width), Num(t.maxHeight), Num(t.scale)
	local ql = type(inputs.questlist) == "table" and Num(inputs.questlist.width)
	-- the minimap column and your buff rows: a missing field, or one that
	-- cannot be read plainly (secret: tested first), is the design's
	local c = type(inputs.column) == "table" and inputs.column or EMPTY
	local a = type(inputs.auras) == "table" and inputs.auras or EMPTY
	local D, DA = Column.DESIGN, Column.DESIGN_AURAS
	local function Bool(v, def)
		if Secret(v) or v == nil then
			return def
		end
		return v and true or false
	end
	local function Str(v, def)
		if Secret(v) or type(v) ~= "string" then
			return def
		end
		return v
	end
	local border = Str(c.border, D.border)
	local size, perRow = Num(a.size), Num(a.perRow)
	perRow = perRow and floor(perRow)
	return {
		column = { kit = Bool(c.kit, D.kit), shape = Str(c.shape, D.shape), border = Column.RAILS[border] and border or D.border,
			merge = Bool(c.merge, D.merge), bar = Bool(c.bar, D.bar), groups = Bool(c.groups, D.groups), barOffset = Num(c.barOffset) or D.barOffset,
			roundIcons = Bool(c.roundIcons, D.roundIcons), match = Bool(c.match, D.match) },
		-- (fit: the caller writes places.auras, so the fit may change your
		-- rows' Icons Per Row and Icon Size; else they stay as they are)
		auras = { rows = Bool(a.rows, DA.rows), attached = Bool(a.attached, DA.attached),
			size = (size and size > 0) and size or DA.size, perRow = (perRow and perRow > 0) and perRow or DA.perRow,
			fit = Bool(a.fitRows, false) },
		positions = positions,
		tracker = { pos = type(pos) == "table" and { x = pos.x, y = pos.y } or nil, width = width or 300, maxHeight = height or 440,
			gameW = width ~= nil and width <= 0, gameH = height ~= nil and height <= 0, scale = (scale and scale > 0) and scale or 1 },
		questlist = { width = (ql and ql > 0) and ql or 380 },
		hideBagBar = inputs.hideBagBar and true or false,
		statsOn = inputs.statsOn and true or false,
		bars = BarsFor(inputs),
	}
end

--------------------------------------------------------------------------------
-- Sizes and rects (UIParent units, origin top-left, y down)
--------------------------------------------------------------------------------

local function Managed(m)
	local v = MANAGED[m.name]
	return v == true or (v and v[m.idx]) or false
end

-- A record's size from its own settings (the client's default frame sizes),
-- or nil when it has none this model knows (group, raid, boss, cooldown,
-- encounter content)
local function SizeOf(f, s, m)
	local name, idx = m.name, m.idx
	if name == "ActionBar" then
		local btn, n
		if idx == 11 or idx == 12 or idx == 13 then
			btn, n = 30, (idx == 12) and 10 or 2
		else
			btn, n = 45, Setting(f, s, "NumIcons") or 12
		end
		local rows = Disp(f, s, "NumRows") or 1
		local scale = (Disp(f, s, "IconSize") or 100) / 100
		local pad = max(2, Disp(f, s, "IconPadding") or 2)
		local stride = ceil(n / rows)
		local a = stride * btn * scale + (stride - 1) * pad
		local b = rows * btn * scale + (rows - 1) * pad
		if (Setting(f, s, "Orientation") or 0) == 0 then
			return a, b
		end
		return b, a
	elseif name == "CastBar" then
		local k = (Disp(f, s, "BarSize") or 100) / 100
		return 208 * k, 11 * k
	elseif name == "Minimap" then
		-- the cluster round its children at the Size (Column, above)
		local k = (Disp(f, s, "Size") or 100) / 100
		local lo = min(10 - 215 / 2 * k, -91.5)
		local hi = max(10 + 215 / 2 * k, 122.5)
		return hi - lo + 20, 30 + 226 * k - 4
	elseif name == "UnitFrame" then
		local k = Setting(f, s, "FrameSize") ~= nil and Disp(f, s, "FrameSize") / 100 or 1
		if idx == 1 or idx == 2 then
			return 232 * k, 100 * k
		elseif idx == 3 then
			local small = On(Setting(f, s, "UseLargerFrame")) and 1 or 0.75
			return 232 * k * small, 100 * k * small
		elseif idx == 4 then
			return 120 * k, 4 * 53 * k
		elseif idx == 8 then
			return 120 * k, 49 * k
		end
		return nil
	elseif name == "AuraFrame" then
		local k = (Disp(f, s, "IconSize") or 100) / 100
		local pad = Disp(f, s, "IconPadding") or 5
		if idx == 1 then
			return (30 + pad) * (Disp(f, s, "IconLimitBuffFrame") or 11) * k, (40 + pad) * k
		elseif idx == 2 then
			return (30 + pad) * (Disp(f, s, "IconLimitDebuffFrame") or 8) * k, (40 + pad) * k
		end
		return 5 * (30 + pad) * k, (40 + pad) * k
	elseif name == "ChatFrame" then
		return (Setting(f, s, "WidthHundreds") or 4) * 100 + (Setting(f, s, "WidthTensAndOnes") or 0),
			(Setting(f, s, "HeightHundreds") or 1) * 100 + (Setting(f, s, "HeightTensAndOnes") or 0)
	elseif name == "DamageMeter" then
		return Disp(f, s, "FrameWidth") or 300, Disp(f, s, "FrameHeight") or 186
	elseif name == "ObjectiveTracker" then
		return 260, Disp(f, s, "Height") or 400
	elseif name == "MicroMenu" then
		local k = (Disp(f, s, "Size") or 100) / 100
		return (32 + 11 * 27) * k, 40 * k
	elseif name == "Bags" then
		local k = (Disp(f, s, "Size") or 100) / 100
		if Setting(f, s, "Orientation") == 1 then
			return 45 * k, 268 * k
		end
		return 268 * k, 45 * k
	elseif name == "StatusTrackingBar" then
		local k = (Disp(f, s, "Size") or 100) / 100
		return 1192 * k, 17
	elseif name == "MainActionBarEndCap" then
		return 154, 95
	elseif name == "DurabilityFrame" then
		local k = (Disp(f, s, "Size") or 100) / 100
		return 60 * k, 75 * k
	elseif name == "LootFrame" then
		return 220, 290
	elseif name == "HudTooltip" then
		return 250, 150
	elseif name == "VehicleLeaveButton" then
		return 32, 32
	elseif name == "EncounterBar" then
		return 250, 30
	elseif name == "ExtraAbilities" then
		return 256, 128
	elseif name == "SwingTimer" then
		local k = (Disp(f, s, "Scale") or 100) / 100
		return (Disp(f, s, "Width") or 313) * k, (Disp(f, s, "Height") or 18) * k
	elseif name == "GroupFinder" then
		local k = (Disp(f, s, "Size") or 100) / 100
		return 45 * k, 45 * k
	elseif name == "LossOfControl" then
		local k = (Disp(f, s, "Size") or 100) / 100
		return 256 * k, 58 * k
	elseif name == "TimerBars" then
		local k = (Disp(f, s, "Size") or 100) / 100
		return 206 * k, 32 * k
	elseif name == "TalkingHeadFrame" then
		return 570, 155
	elseif name == "VehicleSeatIndicator" then
		local k = (Disp(f, s, "Size") or 100) / 100
		return 128 * k, 128 * k
	elseif name == "ArchaeologyBar" then
		local k = (Disp(f, s, "Size") or 100) / 100
		return 200 * k, 30 * k
	elseif name == "PersonalResourceDisplay" then
		return 200, 75
	elseif name == "TotemActionBar" then
		return 230, 38
	end
	return nil
end

-- The state at the approved layout for a screen and a set of MelloUI's
-- settings. A tracker sized by the game's tracker takes its size from 12:-1
-- (startW / startH: what the places keep as 0 when the fit leaves it).
local function Reset(f, W, H, inputs)
	RestoreLayout(f, f.base)
	f.mello = MelloFrom(inputs)
	Truncate(f.log, 0)
	Truncate(f.eye, 0)
	Truncate(f.notes, 0)
	Truncate(f.flags, 0)
	f.W, f.H = W, H
	f.inset, f.framesD, f.chatLifted, f.bandWhy, f.bandNote = 0, 0, false, nil, nil
	local t = f.mello.tracker
	if t.gameW or t.gameH then
		local s = f.rec["12:-1"]
		local gw, gh = SizeOf(f, s, f.meta[s])
		t.width = t.gameW and gw or t.width
		t.maxHeight = t.gameH and gh or t.maxHeight
	end
	t.startW, t.startH = t.width, t.maxHeight
	Bump(f)
end

-- Every record's rect, the game's anchor maths (offsets are UIParent
-- units), chained records after the frame they hang on (up to 6 passes).
-- R[key] is rounded to a tenth like the prototype's; the chain uses the exact
-- rects. Rect tables are kept per key and refilled: no garbage per solve.
local function Solve(f)
	if f.solved == f.version then
		return
	end
	Step(f)
	local W, H = f.W, f.H
	local FR, R, frPool, rPool, order = f.FR, f.R, f.frPool, f.rPool, f.order
	for k in pairs(FR) do
		FR[k] = nil
	end
	for k in pairs(R) do
		R[k] = nil
	end
	local ui = frPool.UIParent
	ui[1], ui[2], ui[3], ui[4] = 0, 0, W, H
	FR.UIParent = ui
	local nOrder = 0
	local systems, meta, byFrame, inPend = f.systems, f.meta, f.byFrame, f.inPend
	local pending, left = f.pendA, f.pendB
	local nPending = #systems
	for i = 1, nPending do
		pending[i] = systems[i]
	end
	for pass = 1, 6 do
		if pass > 1 then
			Step(f)
		end
		local stamp = f.stamp + 1
		f.stamp = stamp
		for i = 1, nPending do
			inPend[pending[i]] = stamp
		end
		local nLeft = 0
		for i = 1, nPending do
			local s = pending[i]
			local m = meta[s]
			local w, h = SizeOf(f, s, m)
			if w and not (s.isInDefaultPosition and Managed(m)) then
				local a = s.anchorInfo
				local rel = FR[a.relativeTo]
				if not rel and byFrame[a.relativeTo] ~= nil then
					-- its frame is placed later in this pass or the next (or
					-- never: it then waits with it, as in the prototype)
					nLeft = nLeft + 1
					left[nLeft] = s
				elseif rel then
					local L, T, Rr, B = AnchorRect(rel[1], rel[2], rel[3], rel[4], a.point, a.relativePoint, a.offsetX, a.offsetY, w, h)
					local fr = m.frame
					if fr then
						local t = frPool[fr]
						if not t then
							t = {}
							frPool[fr] = t
						end
						t[1], t[2], t[3], t[4] = L, T, Rr, B
						FR[fr] = t
						if fr == "MinimapCluster" then
							-- the map inside the cluster (the queue eye hangs on it)
							local mm = frPool.Minimap
							if not mm then
								mm = {}
								frPool.Minimap = mm
							end
							mm[1], mm[2], mm[3], mm[4] = Column.MapRect(L, T, Rr, (Disp(f, s, "Size") or 100) / 100)
							FR.Minimap = mm
						end
					end
					local key = m.key
					local r = rPool[key]
					if not r then
						r = {}
						rPool[key] = r
					end
					r[1], r[2], r[3], r[4] = Round1(L), Round1(T), Round1(Rr), Round1(B)
					R[key] = r
					nOrder = nOrder + 1
					order[nOrder] = key
				end
			end
		end
		pending, left = left, pending
		nPending = nLeft
		if nPending == 0 then
			break
		end
	end
	f.nOrder = nOrder
	f.solved = f.version
end

local function Visible(f, s)
	local name = f.meta[s].name
	local v
	if name == "ActionBar" then
		v = Disp(f, s, "VisibleSetting")
	elseif name == "SwingTimer" then
		v = Disp(f, s, "Visibility")
	end
	return v ~= "HIDDEN"
end

local function BarCat(f, s)
	local v = Disp(f, s, "VisibleSetting")
	if v == "IN_COMBAT" then
		return "C"
	elseif v == "OUT_OF_COMBAT" then
		return "O"
	end
	return "A"
end

--------------------------------------------------------------------------------
-- The minimap column (the Column table's functions; its data is above)
--------------------------------------------------------------------------------

-- the map (198 x 198 at the Size k) in the cluster's rect
function Column.MapRect(l, t, r, k)
	local cx = l + (r - l) / 2 + 10
	local cy = t + 30 + 226 * k / 2
	local half = 198 / 2 * k
	return cx - half, cy - half, cx + half, cy + half
end

function Column.Put(into, l, t, r, b)
	into[1], into[2], into[3], into[4] = l, t, r, b
	return into
end

-- The column at the layout's minimap Size, from the cluster's rect (R, a
-- tenth like the prototype's): the map; the painted frame round it (merged:
-- round the Services bar too); the pieces the player sees (`piece`, the frame
-- with the zone band or plate; `bar`, the Services row, nil without it); the
-- column's `left` and `right` as M:ColumnPart("frame") has them (the painted
-- frame: the kit's round ring or square border, else the map; never a loose
-- bar) for your buff rows (Modules/Auras.lua); its `bottom` (the frame and
-- its bottom gems' paint, a loose bar, Route's line) for the tracker, as
-- M:ColumnRect has it; `ref`, the frame the Quest
-- Tracker matches and lines up with (M:ColumnWidth's line: the kit's square
-- border or merged frame where it shows, else the map -- the round ring is
-- not in it). Kept per version in f.col (no garbage).
function Column.Model(f)
	local col = f.col
	if col and col.built == f.version then
		return col
	end
	Solve(f)
	if not col then
		col = { map = {}, frame = {}, piece = {}, barRect = {}, loose = {} }
		f.col = col
	end
	local c = f.mello.column
	local k = (Disp(f, f.rec["2:-1"], "Size") or 100) / 100
	local mc = f.R["2:-1"]
	local mL, mT, mR, mB = Column.MapRect(mc[1], mc[2], mc[3], k)
	local kit, square, border = c.kit, c.shape == "square", c.border
	local rim = (kit and square) and Column.RAILS[border] or kit and Column.RING or Column.GAME
	local merged = kit and square and (border == "window" or border == "single") and c.merge and c.bar or false
	local row
	if c.bar then
		if c.groups then
			row = Column.ROW_GROUPS
		elseif merged then
			row = Column.ROW_ALL_MERGED
		elseif kit then
			row = Column.ROW_ALL_KIT
		elseif c.roundIcons then
			row = Column.ROW_ALL_ROUND
		else
			row = Column.ROW_ALL_PLAIN
		end
	end
	local map, frame, piece = Column.Put(col.map, mL, mT, mR, mB), col.frame, col.piece
	local loose, bar = nil, nil
	if merged then
		local bt = mB + row[3] * k
		local bb = bt + row[2] * k
		Column.Put(frame, mL - rim[1] * k, mT - rim[2] * k, mR + rim[3] * k, bb + rim[4] * k)
		-- the zone plate on the frame's top rail
		Column.Put(piece, frame[1], frame[2] - 2 * k, frame[3], bt)
		bar = Column.Put(col.barRect, frame[1], bt, frame[3], frame[4])
	else
		Column.Put(frame, mL - rim[1] * k, mT - rim[2] * k, mR + rim[3] * k, mB + rim[4] * k)
		-- the zone band at home (175 x 16, 15 right of the cluster's middle,
		-- 4 down; the kit's plate 1.4 x it), its buttons at its ends
		local cc = (mc[1] + mc[3]) / 2
		local bl, bt0, br
		if kit then
			bl, bt0, br = cc - 107.5, mc[2] + 0.8, cc + 137.5
		else
			bl, bt0, br = cc - 91.5, mc[2] + 4, cc + 122.5
		end
		Column.Put(piece, min(frame[1], bl), min(frame[2], bt0), max(frame[3], br), frame[4])
		if row then
			local cx = (mL + mR) / 2
			local bt = mB - c.barOffset * k
			loose = Column.Put(col.loose, cx - row[1] / 2 * k, bt, cx + row[1] / 2 * k, bt + row[2] * k)
			bar = loose
		end
	end
	-- Route's distance line: 2 under the map, under a loose bar that leaves
	-- it no room (M:ColumnSlot("route"))
	local lt = mB + Column.LINE_GAP * k
	local lb = lt + Column.LINE_H * k
	if loose and lb > loose[2] and lt < loose[4] then
		lt = loose[4] + Column.LINE_GAP * k
		lb = lt + Column.LINE_H * k
	end
	local bottom = max(frame[4] + ((kit and square) and Column.GEM_B[border] or 0) * k, lb)
	if loose then
		bottom = max(bottom, loose[4])
	end
	local block = (kit and square and border ~= "none") and frame or map
	col.ref = block
	-- (your buff rows stand beside the painted frame: with the Minimap Kit,
	-- its round ring's or square border's outer edges, else the map's)
	local side = kit and frame or map
	col.left, col.right = side[1], side[3]
	col.k, col.bar, col.bottom, col.kit, col.match, col.merged = k, bar, bottom, kit, (kit and c.match) and true or false, merged
	col.built = f.version
	return col
end

-- the tracker's width on the screen while it matches the minimap's: the
-- column's frame, within the grip's bounds (QuestTracker FOLLOW_MIN,
-- FOLLOW_MAX: 180..700 of its own units)
function Column.TrackerWidth(col, s)
	return min(700, max(180, (col.ref[3] - col.ref[1]) / s)) * s
end

-- your buff rows stand by the column (Auras' Attach To The Minimap Column,
-- with the Minimap Kit on)
function Column.Attached(f)
	local a = f.mello.auras
	return (a.rows and a.attached and Column.Model(f).kit) and true or false
end

-- The room for your buff rows between the column and the centre third (x0,
-- x1), on the side Rows puts them
function Column.RowsRoom(col, W, x0, x1)
	if col.left + col.right < W then
		return x0 - (col.right + Column.AURA_GAP)
	end
	return col.left - Column.AURA_GAP - x1
end

-- Your buff rows by the column (Modules/Auras.lua): their top corner
-- AURA_GAP beside M:ColumnPart("frame")'s edge, level with the map's top; left of it
-- growing leftwards, or right of it growing rightwards when the column
-- stands in the screen's left half. Each line (size + 6) x perRow wide,
-- size + 16 apart (the time under each icon); the buffs (32 at worst), then
-- the debuffs (16) on the lines under them. -> the buffs' l, t, r, b and the
-- debuffs' bottom (the debuffs are l, buffs' b, r, that)
function Column.Rows(f)
	local col, a = Column.Model(f), f.mello.auras
	local size, per = a.size, a.perRow
	local line = (size + 6) * per
	local pitch = size + 16
	local nb, nd = ceil(32 / per), ceil(16 / per)
	local top = col.map[2]
	local l, r
	if col.left + col.right < f.W then
		l = col.right + Column.AURA_GAP
		r = l + line
	else
		r = col.left - Column.AURA_GAP
		l = r - line
	end
	return l, top, r, top + nb * pitch, top + (nb + nd) * pitch
end

-- pct % of an icon size, whole, not below Auras' Icon Size slider's least (20)
function Column.RowIcon(size, pct)
	return max(20, floor(size * pct / 100 + 0.5))
end

-- The icon sizes F6 tries for your buff rows: yours, then 90, 80, 70 and 60 %
-- of it, then the slider's least, each only when smaller than yours (F5m
-- sizes the minimap for the 80 % icons: the smaller ones only where the
-- minimap is at its least already). Into `out`.
function Column.RowSizes(size, out)
	Truncate(out, 0)
	out[1] = size
	for _, pct in ipairs(Column.PCTS) do
		local s = Column.RowIcon(size, pct)
		local seen = s >= size
		for i = 1, #out do
			if out[i] == s then
				seen = true
			end
		end
		if not seen then
			out[#out + 1] = s
		end
	end
	return out
end
Column.PCTS = { 90, 80, 70, 60, 0 }

-- MelloUI's Quest Tracker: with no place of its own its right edge hangs on
-- the game's tracker's TOPRIGHT, which Edit Mode places (12:-1); matching the
-- minimap's width (QuestTracker, the flip) as wide on the screen as the
-- column's frame, whatever its own width and scale
local function TrackerRect(f)
	Solve(f)
	local t = f.mello.tracker
	local s = t.scale
	local w, h = t.width * s, t.maxHeight * s
	local col = Column.Model(f)
	if col.match then
		w = Column.TrackerWidth(col, s)
	end
	local pos = t.pos
	if pos == nil then
		local r = f.R["12:-1"]
		return r[3] - w, r[2], r[3], r[2] + h
	end
	local x, y = pos.x * s, pos.y * s
	return f.W + x - w, -y, f.W + x, -y + h
end

local function Add(f, name, cat, unit, key, l, t, r, b)
	if l == nil then
		return
	end
	local e = f.pool[name]
	if not e then
		e = { name = name, key = key }
		f.pool[name] = e
	end
	e.cat, e.unit, e.l, e.t, e.r, e.b = cat, unit, l, t, r, b
	local n = f.nE + 1
	f.nE = n
	f.E[n] = e
	f.N[name] = e
end

local function AddR(f, name, cat, unit, key, rc)
	if rc then
		Add(f, name, cat, unit, key, rc[1], rc[2], rc[3], rc[4])
	end
end

-- What the player sees: the game's systems plus MelloUI's kit footprints
-- (measured on the 21:9 screenshot) and its own pieces, in the prototype's
-- order. The piece tables are kept per name and refilled.
local function Elements(f)
	if f.built == f.version then
		return
	end
	Step(f)
	Solve(f)
	local R, W, H = f.R, f.W, f.H
	local rec, mello, N = f.rec, f.mello, f.N
	for name in pairs(N) do
		N[name] = nil
	end
	f.nE = 0
	-- top left: damage meter, party, raid
	local vis = Disp(f, rec["23:-1"], "Visibility")
	AddR(f, "Damage meter", (vis == "ALWAYS" or vis == nil) and "A" or "S", "meter", "23:-1", R["23:-1"])
	AddR(f, "Party frames", "S", "party", "3:3", R["3:3"])
	local raid = rec["3:4"]
	local ra = raid.anchorInfo
	if ra.relativeTo == "UIParent" then
		local fw, fh = Disp(f, raid, "FrameWidth") or 98, Disp(f, raid, "FrameHeight") or 44
		Add(f, "Raid frames (8 groups of 5)", "S", "raid", "3:4", AnchorRect(0, 0, W, H, ra.point, ra.relativePoint, ra.offsetX, ra.offsetY, 8 * fw, 5 * fh + 14))
	end
	-- the chat: MelloUI's kit box and the edit box below, the tabs above
	local cf = R["8:-1"]
	Add(f, "Chat panel", "A", "chat", "8:-1", cf[1] - 26, cf[2] - 8, cf[3] + 40, cf[4] + 29)
	Add(f, "Chat tabs", "M", "chat", "8:-1", cf[1], cf[2] - 28, cf[1] + 218, cf[2] - 10)
	-- the bottom centre
	local b1 = R["0:0"]
	local top = b1
	for i = 1, #PANEL_BARS do
		local k = PANEL_BARS[i]
		local s = rec[k]
		if R[k] and Visible(f, s) and s.anchorInfo.relativeTo ~= "UIParent" then
			top = R[k]
		end
	end
	Add(f, "Bar panel backdrop", "A", "core", "0:0", b1[1] - 13, top[2] - 16, b1[3] + 13, b1[4] + 8)
	for i = 1, #BARS do
		local k, nm = BARS[i][1], BARS[i][2]
		local s = rec[k]
		if R[k] and Visible(f, s) then
			local rel = s.anchorInfo.relativeTo
			local unit = (rel ~= "UIParent" or k == "0:0") and "core" or (k == "0:4" and "br" or "bars")
			if (k == "0:5" or k == "0:6" or k == "0:7") and (rel == "MultiBarLeft" or rel == "MultiBar5" or rel == "MultiBar6") then
				local rp = rec["0:4"] and rec["0:4"].anchorInfo.relativePoint or ""
				unit = rp:sub(-5) == "RIGHT" and "br" or "bars"
			end
			AddR(f, nm, BarCat(f, s), unit, k, R[k])
		end
	end
	local c = R["26:0"]
	if c and not On(Setting(f, rec["26:0"], "Hidden")) then
		Add(f, "End cap left (painted)", "A", "core", "26:0", c[1] + 13.4, c[2] + 9, c[3] - 11.6, c[4] - 10)
	end
	c = R["26:1"]
	if c and not On(Setting(f, rec["26:1"], "Hidden")) then
		Add(f, "End cap right (painted)", "A", "core", "26:1", c[1] + 11.6, c[2] + 9, c[3] - 13.4, c[4] - 10)
	end
	AddR(f, "XP bar", "A", "core", "15:0", R["15:0"])
	AddR(f, "Second tracked bar", "S", "core", "15:1", R["15:1"])
	c = R["0:10"]
	if c then
		Add(f, "Stance tab (kit plate)", "A", "core", "0:10", c[1] - 15, c[2] - 16, c[3] + 12, c[4])
	end
	AddR(f, "Pet bar tab", "P", "core", "0:11", R["0:11"])
	AddR(f, "Possess bar", "S", "core", "0:12", R["0:12"])
	AddR(f, "Totem bar tab (Wrath-style shaman)", "P", "core", "25:-1", R["25:-1"])
	local cb = R["1:-1"]
	Add(f, "Cast bar + kit text", "K", "core", "1:-1", cb[1], cb[2], cb[3], cb[4] + 18)
	for i = 1, #SWINGS do
		local k = SWINGS[i][1]
		if R[k] and Visible(f, rec[k]) then
			AddR(f, SWINGS[i][2], "C", "core", k, R[k])
		end
	end
	AddR(f, "Vehicle / taxi exit", "V", "core", "9:-1", R["9:-1"])
	Step(f)   -- (half way: the pieces are a long stretch on a slow PC)
	local pl, tg = R["3:0"], R["3:1"]
	AddR(f, "Player frame", "A", "frames", "3:0", pl)
	AddR(f, "Target frame", "T", "frames", "3:1", tg)
	local kt = (tg[3] - tg[1]) / 232
	Add(f, "Target auras (MelloUI row)", "T", "frames", "3:1", tg[1] + 142 * kt, tg[4] - 20 * kt, tg[1] + 236 * kt, tg[4] - 6 * kt)
	local kp = (pl[3] - pl[1]) / 232
	local pcx, ptop = (pl[1] + pl[3]) / 2 + 30 * kp, pl[4] - 25 * kp
	Add(f, "Pet frame", "P", "frames", "3:7", pcx - 60 * kp, ptop, pcx + 60 * kp, ptop + 49 * kp)
	AddR(f, "Focus frame", "S", "focus", "3:2", R["3:2"])
	AddR(f, "Extra ability", "S", "extra", "5:-1", R["5:-1"])
	-- top right: the minimap column (layout E), auras, tracker, boss
	local col = Column.Model(f)
	local cp, cr = col.piece, col.bar
	Add(f, "Minimap (kit frame + zone plate)", "A", "minimap", "2:-1", cp[1], cp[2], cp[3], cp[4])
	if cr then
		Add(f, "Services panel (MelloUI)", "A", "minimap", "2:-1", cr[1], cr[2], cr[3], cr[4])
	end
	AddR(f, "Queue eye", "S", "minimap", "27:-1", R["27:-1"])
	-- the aura blocks at their worst case (32 buffs, 16 debuffs), so a full
	-- row never runs into anything: the game's buff and debuff bars, or your
	-- buff rows by the minimap column (the game's bars hidden then); the
	-- external defensives hang on the game's debuffs by their own offsets
	-- (the design's 0, -4; F6 may lower them under your buff rows)
	local bs = rec["6:0"]
	local per = Setting(f, bs, "IconLimitBuffFrame") or 11
	local k = (Disp(f, bs, "IconSize") or 100) / 100
	local pad = Disp(f, bs, "IconPadding") or 5
	local br = R["6:0"]
	local bR, bT = br[3], br[2]
	local bB = bT + ceil(32 / per) * (40 + pad) * k
	local perd = Setting(f, rec["6:1"], "IconLimitDebuffFrame") or 8
	local dR, dT = bR - 15, bB + 4
	local dB = dT + ceil(16 / perd) * (40 + pad) * k
	local ea = rec["6:2"].anchorInfo
	local eR, eT = dR + ea.offsetX, dB - ea.offsetY
	if Column.Attached(f) then
		local rl, rt, rr, rb, rd = Column.Rows(f)
		Add(f, "Buffs", "A", "auras", "6:0", rl, rt, rr, rb)
		Add(f, "Debuffs", "S", "auras", "6:1", rl, rb, rr, rd)
	else
		Add(f, "Buffs", "A", "auras", "6:0", bR - per * (30 + pad) * k - 15, bT, bR, bB)
		Add(f, "Debuffs", "S", "auras", "6:1", dR - perd * (30 + pad) * k, dT, dR, dB)
	end
	Add(f, "External defensives", "S", "auras", "6:2", eR - 5 * (30 + pad) * k, eT, eR, eT + (40 + pad) * k)
	Add(f, "Quest Tracker (MelloUI)", "A", "tracker", "12:-1", TrackerRect(f))
	local ba = rec["3:5"].anchorInfo
	if ba.relativeTo == "UIParent" then
		Add(f, "Boss frames", "S", "boss", "3:5", AnchorRect(0, 0, W, H, ba.point, ba.relativePoint, ba.offsetX, ba.offsetY, 232, 300))
	end
	-- bottom right: micro menu, bags, tray, doll, tooltip corner
	local mm, mr = R["13:-1"], rec["13:-1"]
	local km = (Disp(f, mr, "Size") or 100) / 100
	if Setting(f, mr, "Orientation") == 0 then
		local ml = mm[3] - 11 * 27 * km - 5 * km
		Add(f, "Micro menu (kit row)", "A", "br", "13:-1", ml - 14, mm[2] - 14, mm[3] + 14, mm[4] + 14)
	else
		Add(f, "Micro menu (kit column)", "A", "br", "13:-1", mm[1] - 14, mm[2] - 14, mm[3] + 14, mm[4] + 14)
	end
	if not mello.hideBagBar then
		AddR(f, "Bag bar", "A", "br", "14:-1", R["14:-1"])
	end
	AddR(f, "Durability doll", "S", "doll", "16:-1", R["16:-1"])
	AddR(f, "Tooltip fallback corner", "S", "tooltip", "11:-1", R["11:-1"])
	-- the pop-ups the game centres
	AddR(f, "Loot window", "L", "popup", "10:-1", R["10:-1"])
	AddR(f, "Loss of control alert", "S", "popup", "28:-1", R["28:-1"])
	AddR(f, "Encounter bar", "S", "popup", "4:-1", R["4:-1"])
	AddR(f, "Mirror timers", "S", "popup", "17:-1", R["17:-1"])
	local rw = rec["24:-1"].anchorInfo
	Add(f, "Raid warning text", "S", "popup", "24:-1", AnchorRect(0, 0, W, H, rw.point, rw.relativePoint, rw.offsetX, rw.offsetY, 800, 100))
	if mello.statsOn then
		Add(f, "FPS / latency text", "A", "br", nil, W - 18 - 90, H - 120 - 13, W - 18, H - 120)
	end
	Add(f, "Issue Reporter (test client)", "Q", "client", nil, W - 580.67, H - 103, W - 508.67, H - 3)
	Truncate(f.E, f.nE)
	f.built = f.version
end

--------------------------------------------------------------------------------
-- Pair rules and conflicts
--------------------------------------------------------------------------------

local function PairRule(a, b)
	local r = RULES[a.name]
	r = r and r[b.name]
	if r then
		return r
	end
	local ca, cb = a.cat, b.cat
	if (ca == "V" and (cb == "C" or cb == "K")) or (cb == "V" and (ca == "C" or ca == "K")) then
		return "excl"
	end
	return nil
end

local function Situations(e)
	return SIT_BY_NAME[e.name] or SIT_BY_CAT[e.cat] or EMPTY
end

local function Together(a, b)
	local sa, sb = Situations(a), Situations(b)
	for i = 1, #SITUATIONS do
		local s = SITUATIONS[i]
		if sa[s] and sb[s] then
			return true
		end
	end
	return false
end

local function TogetherText(a, b)
	local sa, sb = Situations(a), Situations(b)
	local out = {}
	for i = 1, #SITUATIONS do
		local s = SITUATIONS[i]
		if sa[s] and sb[s] then
			out[#out + 1] = s
		end
	end
	return concat(out, ", ")
end

-- hard: both always on, or they show together; soft: one always on, the
-- other never with it; rare: both now and then, never together
local function Kind(a, b)
	if a.cat == "Q" or b.cat == "Q" then
		return "info"
	end
	local n = (PERSISTENT[a.cat] and 1 or 0) + (PERSISTENT[b.cat] and 1 or 0)
	if n == 2 or Together(a, b) then
		return "hard"
	end
	return n == 1 and "soft" or "rare"
end

local function Inherited(f, a, b)
	local t = f.inh[a.name]
	return t ~= nil and t[b.name] == true
end

-- Overlapping pairs no rule allows, in the prototype's order. `unit`: only
-- pairs with a piece of that unit; pieces of the `later` units are left out
-- (they make room later); the game's pop-ups only with `popups`. With
-- `counting`, the pairs a unit is scored by (not the test client's, not the
-- inherited ones) are only counted -- hard, soft, rare -- and no list is
-- made (a candidate's trial)
local function Conflicts(f, unit, later, popups, counting)
	Elements(f)
	local out = not counting and {} or nil
	local hard, soft, rare = 0, 0, 0
	-- (work: the pairs tested since the last hand-over point; the first
	-- comes before the first row, after the pieces were built)
	local E, n, work = f.E, f.nE, 160
	for i = 1, n do
		local a = E[i]
		if not (later and later[a.unit]) and (unit == nil or a.unit == unit) then
			-- a hand-over point about every 160 pairs tested (a whole scan's
			-- first rows are the longest: every piece after them)
			if work >= 160 then
				Step(f)
				work = 0
			end
			work = work + ((unit == nil) and (n - i) or n)
			for j = (unit == nil) and (i + 1) or 1, n do
				local b = E[j]
				if j ~= i and not (later and later[b.unit]) and not (unit ~= nil and b.unit == unit and j < i)
					and not PairRule(a, b) and (popups or (a.unit ~= "popup" and b.unit ~= "popup")) then
					local ox = min(a.r, b.r) - max(a.l, b.l)
					local oy = min(a.b, b.b) - max(a.t, b.t)
					if ox > EPS and oy > EPS then
						local kind = Kind(a, b)
						if not counting then
							out[#out + 1] = { kind = kind, a = a, b = b, ox = ox, oy = oy }
						elseif kind ~= "info" and not Inherited(f, a, b) then
							if kind == "hard" then
								hard = hard + 1
							elseif kind == "soft" then
								soft = soft + 1
							else
								rare = rare + 1
							end
						end
					end
				end
			end
		end
	end
	if counting then
		return hard, soft, rare
	end
	return out
end

-- a unit's conflicts, leaving out the test client's and the pairs the
-- approved layout already has at its own screen (the fitter keeps the
-- design, it does not redesign it)
local function UnitConflicts(f, unit, later)
	local out = {}
	for _, c in ipairs(Conflicts(f, unit, later, false)) do
		if c.kind ~= "info" and not Inherited(f, c.a, c.b) then
			out[#out + 1] = c
		end
	end
	return out
end

-- the top of the bottom centre (unit frames, cast bar, swing timers)
local function CentreTop(f, later)
	Elements(f)
	local top = huge
	for i = 1, f.nE do
		local e = f.E[i]
		if U_CORE_FRAMES[e.unit] and PERSISTENT[e.cat] and not (later and later[e.unit]) then
			top = min(top, e.t)
		end
	end
	return top
end

-- the centre third (of the 21:9 zone on a wider screen)
local function Third(f)
	local zone = f.W - 2 * f.inset
	return f.inset + zone / 3, f.inset + 2 * zone / 3
end

local function Union(a, b)
	return min(a.l, b.l), min(a.t, b.t), max(a.r, b.r), max(a.b, b.b)
end

-- every record held to the screen's bottom centre (they slide together)
local function CentreGroup(f)
	local out = {}
	for i = 1, #f.systems do
		local s = f.systems[i]
		local a = s.anchorInfo
		if a.relativeTo == "UIParent" and a.relativePoint == "BOTTOM" and not s.isInDefaultPosition then
			out[#out + 1] = f.meta[s].key
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- The rules (the prototype's functions of the same names, Tools/installer/fitting/fit.py)
--------------------------------------------------------------------------------

-- F0. One store per place: Edit Mode places the minimap, the damage meter,
-- the chat and the game's tracker, so MelloUI's store keeps no place for them
-- (PutBack would move them again), and the Quest Tracker has no place of its
-- own. Runs first: the tracker's place below is read from 12:-1.
local function F0Store(f)
	local P = f.mello.positions
	for _, key in ipairs(EDIT_MODE_FRAMES) do
		local old = P[key]
		if old ~= nil then
			P[key] = nil
			Log(f, "F0 store", "positions." .. key, "removed (was " .. PlaceText(old) .. ")",
				"Edit Mode places this frame; one store per place (Reset positions then returns to the fitted place)")
		end
	end
	local t = f.mello.tracker
	if t.pos ~= nil then
		Log(f, "F0 store", "QuestTracker.pos", "removed (was " .. PlaceText(t.pos) .. ")",
			"the tracker hangs on the game's tracker, placed by Edit Mode 12:-1 (QuestTracker.lua:302-310)")
		t.pos = nil
		Bump(f)
	end
end

-- F1. Wider than 21:9: the HUD keeps the 21:9 width, centred; every piece
-- held to the left / right edge is held to the zone's edge instead
local function F1Zone(f)
	local zone = min(f.W, DESIGN_ASPECT * f.H)
	local inset = (f.W - zone) / 2
	f.inset = inset >= 0.05 and inset or 0
	if f.inset == 0 then
		return
	end
	for i = 1, #f.systems do
		local s = f.systems[i]
		local a = s.anchorInfo
		if a.relativeTo == "UIParent" and not s.isInDefaultPosition then
			local edge = AXX[a.relativePoint]
			if edge == 0 then
				Shift(f, f.meta[s].key, "F1 zone", format("held to the 21:9 zone's left edge, %.1f in from the screen's", inset), inset, 0)
			elseif edge == 1 then
				Shift(f, f.meta[s].key, "F1 zone", format("held to the 21:9 zone's right edge, %.1f in from the screen's", inset), -inset, 0)
			end
		end
	end
	Eye(f, format("32:9 zone: the HUD sits in a centred 21:9 zone, %.0f units in from each side (the outer %.0f%% of the screen stays world)",
		inset, 100 * 2 * inset / f.W))
end

local function PanelTop(f)
	local top = huge
	for _, k in ipairs(PANEL_KEYS) do
		local r = f.R[k]
		if r and Visible(f, f.rec[k]) then
			top = min(top, r[2])
		end
	end
	return top
end

-- F0b (the user's choice). A hidden bar that holds actions is shown. Bars 3 and 4
-- add rows on top of the panel: the pieces above it are lifted by the rows'
-- height and the unit frames step out. Bars 6-8 stand in 2 rows of 6 on the
-- tray. The tracker, doll and tooltip corner make room by their own rules.
local function F0bBars(f)
	local want = {}
	for _, key in ipairs(f.mello.bars) do
		if f.rec[key] and not Visible(f, f.rec[key]) then
			want[#want + 1] = key
		end
	end
	if #want == 0 then
		return
	end
	Solve(f)
	local before = {}
	for key, r in pairs(f.R) do
		before[key] = { r[1], r[2], r[3], r[4] }
	end
	local b1 = before["0:0"]
	local oldTop = PanelTop(f)
	local names = {}
	for _, key in ipairs(want) do
		local label
		for _, bar in ipairs(BAR_SLOTS) do
			if bar[1] == key then
				label = bar[4]
			end
		end
		names[#names + 1] = label
		Set(f, key, "VisibleSetting", 0, "F0b bars", format("%s holds actions: shown", label))
		if key == "0:5" or key == "0:6" or key == "0:7" then
			Set(f, key, "NumRows", 2, "F0b bars", format("%s in 2 rows of 6, the tray's width", label))
		end
	end
	Solve(f)
	local lift = Round1(oldTop - PanelTop(f))
	if lift > EPS then
		for i = 1, #f.systems do
			local s = f.systems[i]
			local a = s.anchorInfo
			local key = f.meta[s].key
			local rc = before[key]
			if a.relativeTo == "UIParent" and a.relativePoint == "BOTTOM" and not s.isInDefaultPosition and rc
				and key ~= "0:0" and key ~= "0:1" and key ~= "0:2" and key ~= "0:3"
				and rc[4] <= oldTop + EPS and rc[1] < b1[3] and rc[3] > b1[1] then
				Shift(f, key, "F0b bars", format("lifted %.1f above the panel's new bar rows", lift), 0, lift)
			end
		end
		-- the taller panel now reaches the unit frames beside it: the pair
		-- steps out, GAP clear of the panel's backdrop
		Elements(f)
		local back, pl = f.N["Bar panel backdrop"], f.N["Player frame"]
		if Yov(back.t, back.b, pl.t, pl.b, 0) and pl.r > back.l - GAP then
			local d = ceil((pl.r - (back.l - GAP)) * 10) / 10
			local why = format("the unit frames step %.1f out, clear of the taller panel", d)
			Shift(f, "3:0", "F0b bars", why, -d, 0)
			Shift(f, "3:2", "F0b bars", why, -d, 0)
			Shift(f, "3:1", "F0b bars", why, d, 0)
			Shift(f, "5:-1", "F0b bars", why, d, 0)
		end
	end
	Eye(f, format("shown because they hold actions: %s%s", concat(names, ", "),
		lift > EPS and format(" (the panel grows %.0f taller)", lift) or ""))
end

-- F11. Smaller Edit Mode sizes up to `level`, tried only when the bottom band
-- cannot be solved at the approved sizes. The painted panel keeps its shape.
local function ApplyCompact(f, level)
	if level == 0 then
		return
	end
	Solve(f)
	local R = f.R
	local b = R["0:0"]
	local half0 = (b[3] - b[1]) / 2
	local pl, tg = R["3:0"], R["3:1"]
	local innerGap = b[1] - pl[3]                           -- 3 at the design
	local capOut = f.rec["26:1"].anchorInfo.offsetX - half0  -- 92.2 at the design
	local focusGap = pl[1] - R["3:2"][3]
	local extraGap = R["5:-1"][1] - tg[3]
	local steps = {}
	for i = 1, level do
		local name, changes = COMPACT[i][1], COMPACT[i][2]
		for _, c in ipairs(changes) do
			Set(f, c[1], c[2], c[3], "F11 compact", format("compact step %d: %s", i, name))
		end
		steps[i] = name
	end
	Eye(f, "compact sizes: " .. concat(steps, ", "))
	Solve(f)
	local bL = R["0:0"][1]
	local half = (R["0:0"][3] - bL) / 2
	Move(f, "26:0", "F11 compact", format("end cap stays %.1f outside the bars", capOut), nil, nil, -(half + capOut))
	Move(f, "26:1", "F11 compact", format("end cap stays %.1f outside the bars", capOut), nil, nil, half + capOut)
	-- the totem tab (a fixed 230 wide) stays inside the narrower bars' left edge
	Solve(f)
	local tt = R["25:-1"]
	if tt and tt[1] < bL - EPS then
		Shift(f, "25:-1", "F11 compact", "totem tab stays inside the bars' left edge", ceil((bL - tt[1]) * 10) / 10, 0)
	end
	Solve(f)
	local pw = R["3:0"][3] - R["3:0"][1]
	local fw = R["3:2"][3] - R["3:2"][1]
	local ew = R["5:-1"][3] - R["5:-1"][1]
	local off = half + innerGap + pw / 2
	Move(f, "3:0", "F11 compact", format("inner edge %.0f outside the bars, as designed", innerGap), nil, nil, -off)
	Move(f, "3:1", "F11 compact", "mirror of the player frame", nil, nil, off)
	Move(f, "3:2", "F11 compact", format("keeps its %.0f gap to the player frame", focusGap), nil, nil, -(off + pw / 2 + focusGap + fw / 2))
	Move(f, "5:-1", "F11 compact", format("keeps its %.0f gap to the target frame", extraGap), nil, nil, off + pw / 2 + extraGap + ew / 2)
end

-- the persistent bottom-centre pieces, the frames at their tightest
local function BottomObstacles(f, dmax)
	local out = {}
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] and U_CORE_FRAMES[e.unit] then
			local l, r = e.l, e.r
			if e.unit == "frames" then
				local sgn = (l + r) / 2 < f.W / 2 and 1 or -1
				l, r = l + sgn * dmax, r + sgn * dmax
			end
			out[#out + 1] = { l, e.t, r, e.b }
		end
	end
	return out
end

-- How far the player / target frames can come in: until the nearest
-- persistent centre piece beside them is GAP away, and the pet frame that
-- hangs under the player frame touches the bar panel
local function FramesDmax(f)
	local N = f.N
	local pl, tg, pet = N["Player frame"], N["Target frame"], N["Pet frame"]
	local dl, dr = 1e9, 1e9
	for i = 1, f.nE do
		local e = f.E[i]
		if e.unit == "core" and (PERSISTENT[e.cat] or e.cat == "P") then
			local g = PERSISTENT[e.cat] and GAP or 0   -- class-only tabs may touch
			if Yov(e.t, e.b, pl.t, pl.b, 0) and e.l >= pl.r - EPS then
				dl = min(dl, e.l - pl.r - g)
			end
			if Yov(e.t, e.b, tg.t, tg.b, 0) and e.r <= tg.l + EPS then
				dr = min(dr, tg.l - e.r - g)
			end
			if Yov(e.t, e.b, pet.t, pet.b, 0) and e.l >= pet.r - EPS then
				dl = min(dl, e.l - pet.r)
			end
		end
	end
	return max(0, min(dl, dr))
end

-- how far the bottom centre can slide right: GAP before the persistent
-- pieces on its right that share its height, and before the screen's edge
local function RightRoom(f)
	local E, n = f.E, f.nE
	local cmax = -huge
	for i = 1, n do
		local c = E[i]
		if PERSISTENT[c.cat] and U_CORE_FRAMES[c.unit] then
			cmax = max(cmax, c.r)
		end
	end
	local room = f.W - GAP - cmax
	for i = 1, n do
		local c = E[i]
		if PERSISTENT[c.cat] and U_CORE_FRAMES[c.unit] then
			for j = 1, n do
				local b = E[j]
				if PERSISTENT[b.cat] and U_RIGHT[b.unit] and Yov(c.t, c.b, b.t, b.b, GAP) and b.l >= c.r - EPS then
					room = min(room, b.l - GAP - c.r)
				end
			end
		end
	end
	return max(0, room)
end

local function ChatSize(f)
	local s = f.rec["8:-1"]
	return Setting(f, s, "WidthHundreds") * 100 + Setting(f, s, "WidthTensAndOnes"),
		Setting(f, s, "HeightHundreds") * 100 + Setting(f, s, "HeightTensAndOnes")
end

local function SetChat(f, w, h, why)
	if w then
		Set(f, "8:-1", "WidthHundreds", floor(w / 100), "F2 chat", why)
		Set(f, "8:-1", "WidthTensAndOnes", w % 100, "F2 chat", format("%s (%d wide)", why, w))
	end
	if h then
		Set(f, "8:-1", "HeightHundreds", floor(h / 100), "F2 chat", why)
		Set(f, "8:-1", "HeightTensAndOnes", h % 100, "F2 chat", format("%s (%d tall)", why, h))
	end
end

-- F2. The chat keeps its place when it clears the bottom centre; else it
-- gets narrower, down to 300; else the bottom centre slides right (when the
-- right side has the room, at most 12 %); else the chat is lifted above the
-- bottom centre, narrowed to stay out of the centre third and shortened to
-- fit under the damage meter.
local function F2Chat(f)
	Elements(f)
	local N = f.N
	local bl, bt, br, bb = Union(N["Chat panel"], N["Chat tabs"])
	local cf = f.R["8:-1"]
	local cfL = cf[1]
	local kitR, kitB, tabs = br - cf[3], bb - cf[4], cf[2] - bt   -- 40, 29, 28
	local curW, curH = ChatSize(f)
	local function WidthBeside(dmax)
		local hit
		for _, o in ipairs(BottomObstacles(f, dmax)) do
			if Yov(o[2], o[4], bt, bb, GAP) and o[1] < br + GAP then
				hit = min(hit or huge, o[1])
			end
		end
		return hit and floor(hit - GAP - kitR - cfL)
	end
	local needW = WidthBeside(0)
	if needW == nil then
		return
	end
	local dmax = FramesDmax(f)
	if needW < CHAT_MIN_W and dmax > EPS then
		needW = WidthBeside(dmax)   -- F3 then brings the frames in by what the chat needs
		if needW == nil then
			return
		end
	end
	local obst = BottomObstacles(f, dmax)
	if needW >= CHAT_MIN_W then
		local w = min(curW, needW)
		SetChat(f, w, nil, "narrower to clear the bar panel and frames")
		Eye(f, format("chat %d wide (from %d) to sit beside the bar panel", w, curW))
		return
	end
	-- the bottom centre slides right to make the missing room, when the
	-- right side has it
	local lack = CHAT_MIN_W - needW
	local room = RightRoom(f)
	if lack <= min(room, 0.12 * f.W) + EPS then
		local slide = ceil(lack * 10) / 10
		for _, key in ipairs(CentreGroup(f)) do
			Shift(f, key, "F2 chat", format("the bottom centre slides %.1f right so the chat keeps its corner at %d wide", slide, CHAT_MIN_W), slide, 0)
		end
		SetChat(f, CHAT_MIN_W, nil, "narrower to clear the bar panel and frames")
		Eye(f, format("chat %d wide (from %d) in its corner; bar panel and frames %.0f units right of the centre (%.1f%% of the width)",
			CHAT_MIN_W, curW, slide, 100 * slide / f.W))
		return
	end
	local top = huge
	for _, o in ipairs(obst) do
		if Xov(o[1], o[3], bl, br, GAP) then
			top = min(top, o[2])
		end
	end
	local yOff = f.H - (top - GAP - kitB)
	local x0 = Third(f)
	local w = min(curW, floor(x0 - GAP - kitR - cfL))
	if w < CHAT_GAME_MIN_W then
		Flag(f, format("chat: only %d units left of the centre third (the game's minimum width is %d)", w, CHAT_GAME_MIN_W))
		w = CHAT_GAME_MIN_W
	end
	local h = min(curH, floor((f.H - yOff) - tabs - (N["Damage meter"].b + GAP)))
	if h < CHAT_MIN_H then
		Flag(f, format("chat: only %d units of height between the damage meter and the bottom centre (the game's minimum is %d)", h, CHAT_MIN_H))
		h = CHAT_MIN_H
	end
	Move(f, "8:-1", "F2 chat", "lifted above the bottom centre: the screen is too narrow for the chat beside the bar panel", nil, nil, nil, yOff)
	SetChat(f, w ~= curW and w or nil, h ~= curH and h or nil, "lifted chat: out of the centre third, under the damage meter")
	Eye(f, format("chat lifted off the bottom edge (its bottom %.0f units up), %d x %d (from %d x %d)", yOff, w, h, curW, curH))
	f.chatLifted = true
end

-- F3. The player / target frames come in as a mirrored pair, just enough to
-- clear the chat and the bottom-right corner, never past their room; focus
-- and extra ability move with them.
local function F3Frames(f)
	Elements(f)
	local dmax = FramesDmax(f)
	local pl, tg = f.N["Player frame"], f.N["Target frame"]
	local need = 0
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] then
			if e.unit == "chat" and Yov(e.t, e.b, pl.t, pl.b, GAP) then
				need = max(need, e.r + GAP - pl.l)
			end
			if e.unit == "br" and Yov(e.t, e.b, tg.t, tg.b, GAP) then
				need = max(need, tg.r + GAP - e.l)
			end
		end
	end
	f.framesD = 0
	if need <= EPS then
		return
	end
	local d = ceil(min(need, dmax) * 10) / 10
	if d <= EPS then
		return
	end
	local why = format("frames %.1f closer to the centre (their room: %.1f, up to the bar panel's pieces beside them)", d, dmax)
	Shift(f, "3:0", "F3 frames", why, d, 0)
	Shift(f, "3:2", "F3 frames", why, d, 0)
	Shift(f, "3:1", "F3 frames", why, -d, 0)
	Shift(f, "5:-1", "F3 frames", why, -d, 0)
	f.framesD = d
end

-- F4. The bottom centre still runs into the right side: the whole bottom
-- centre slides left, at most 12 % of the width and never into the chat or
-- off the screen. False when it cannot.
local function F4Slide(f)
	Elements(f)
	local E, n = f.E, f.nE
	local delta = 0
	local room = huge
	for i = 1, n do
		local c = E[i]
		if PERSISTENT[c.cat] and U_CORE_FRAMES[c.unit] then
			room = min(room, c.l)
			for j = 1, n do
				local b = E[j]
				if PERSISTENT[b.cat] and U_RIGHT[b.unit] and Yov(c.t, c.b, b.t, b.b, GAP) and c.r + GAP > b.l then
					delta = max(delta, c.r + GAP - b.l)
				end
			end
		end
	end
	if delta <= EPS then
		return true
	end
	room = room - GAP
	for i = 1, n do
		local c = E[i]
		if PERSISTENT[c.cat] and U_CORE_FRAMES[c.unit] then
			for j = 1, n do
				local l = E[j]
				if PERSISTENT[l.cat] and U_LEFT[l.unit] and Yov(c.t, c.b, l.t, l.b, 0) then
					room = min(room, c.l - l.r - GAP)
				end
			end
		end
	end
	delta = ceil(delta * 10) / 10
	if delta > 0.12 * f.W or delta > room + EPS then
		f.bandNote = format("the bottom centre needs %.0f to the left (room %.0f, limit %.0f)", delta, room, 0.12 * f.W)
		return false
	end
	for _, key in ipairs(CentreGroup(f)) do
		Shift(f, key, "F4 slide", format("the bottom centre slides %.1f left, clear of the right side", delta), -delta, 0)
	end
	Eye(f, format("bar panel and frames %.0f units left of the screen's centre (%.1f%% of the width)", delta, 100 * delta / f.W))
	return true
end

-- F5m. The minimap column of layout E: the minimap at the Size that makes
-- the map about as wide as the Quest Tracker's design width, a step smaller
-- (down to the approved layout's size) while the tracker would get less than
-- TRACKER_KEEP under the column (the corner's pieces under it and the
-- screen's bottom, as F5) or your buff rows by the column no room for 6 a
-- row of icons at 80 % (what F6 sets, or tells the player to set); where no
-- step leaves room for both, the least, with an eye line that says which is
-- short; the game's tracker (12:-1, which MelloUI's hangs on)
-- right under the column, its right edge on the column's frame's, so the
-- tracker, as wide as that frame, lines up with it.
function Column.F5m(f)
	local s = f.rec["2:-1"]
	local start = Setting(f, s, "Size")
	Elements(f)
	-- the corner's always-on pieces (they do not move with the Size): l, r, t
	local br, n = f.brBuf or {}, 0
	f.brBuf = br
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] and U_BR[e.unit] then
			br[n + 1], br[n + 2], br[n + 3] = e.l, e.r, e.t
			n = n + 3
		end
	end
	local t, a = f.mello.tracker, f.mello.auras
	local need = min(TRACKER_KEEP, t.maxHeight)
	local rows = Column.Attached(f)
	-- the room your rows need beside it: 6 a row (fewer when yours are
	-- fewer) of icons at 80 % -- what F6 sets, or tells the player to set
	local narrow = (min(a.size, Column.RowIcon(a.size, 80)) + 6) * min(a.perRow, Column.ROWS_LEAST)
	local x0, x1 = Third(f)
	local chosen, trackerOk, rowsOk = nil, true, true
	for raw = Column.SIZE_DESIGN, start, -1 do
		Step(f)
		SetRaw(f, s, "Size", raw)   -- a trial, logged once below
		local col = Column.Model(f)
		local ref = col.ref
		local tw = col.match and Column.TrackerWidth(col, t.scale) or t.width * t.scale
		local tt = Round1(col.bottom + GAP)
		local trL, trR = ref[3] - tw, ref[3]
		local floorY = f.H - GAP
		for i = 1, n, 3 do
			if Xov(br[i], br[i + 1], trL, trR, 0) and br[i + 2] > tt then
				floorY = min(floorY, br[i + 2] - GAP)
			end
		end
		trackerOk = floor((floorY - tt) / 20) * 20 >= need
		rowsOk = not rows or Column.RowsRoom(col, f.W, x0, x1) >= narrow
		if trackerOk and rowsOk then
			chosen = raw
			break
		end
	end
	-- no step with room for both: the least, the most room for both, and
	-- the eye line says which has less than it wants there
	local short
	if not chosen then
		chosen = start
		short = (not trackerOk and not rowsOk) and "the quest tracker and your buff rows get" or not trackerOk and "the quest tracker gets"
			or "your buff rows get"
	end
	SetRaw(f, s, "Size", start)
	local pct, pct0 = 50 + 10 * chosen, 50 + 10 * Column.SIZE_DESIGN
	local why
	if chosen == Column.SIZE_DESIGN then
		why = format("layout E: the map about as wide as the Quest Tracker (%d of its %d units)", floor(198 * pct / 100 + 0.5),
			Column.TRACKER_DESIGN_W)
	elseif short then
		why = format("the smallest size (the approved layout's): even there %s less room than wanted", short)
	else
		why = format("the largest size that leaves the quest tracker %d units under the minimap%s", need, rows and ", and your buff rows room beside it" or "")
	end
	Set(f, "2:-1", "Size", chosen, "F5m column", why)
	if short then
		Eye(f, format("minimap at %d%% (from %d%%), its smallest: even so %s less room than wanted", pct, pct0, short))
	elseif chosen ~= Column.SIZE_DESIGN then
		Eye(f, format("minimap at %d%% (from %d%%): room for the quest tracker under it%s", pct, pct0, rows and " and your buff rows beside it" or ""))
	end
	local col = Column.Model(f)
	Move(f, "12:-1", "F5m column", "the quest tracker right under the minimap column, its right edge on the column's frame's",
		"TOPRIGHT", "TOPRIGHT", col.ref[3] - f.W, -(col.bottom + GAP))
end

-- F5. MelloUI's Quest Tracker keeps its top (under the minimap) and is as
-- tall as the approved 440, but stops GAP above the persistent pieces under
-- it and above the screen's bottom. Never below 200.
local function F5Tracker(f, withCentre, keep)
	Elements(f)
	local tl, tt, tr = TrackerRect(f)
	local floorY = f.H - GAP
	local units = withCentre and U_BR_CENTRE or U_BR
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] and units[e.unit] and Xov(e.l, e.r, tl, tr, 0) and e.t > tt then
			floorY = min(floorY, e.t - GAP)
		end
	end
	local t = f.mello.tracker
	local cur = t.maxHeight
	local h = min(cur, floor((floorY - tt) / 20) * 20)   -- the Height slider's step
	if withCentre and keep > TRACKER_MIN and h < keep then
		return   -- left to F4's slide
	end
	if h < TRACKER_MIN then
		Flag(f, format("quest tracker: only %d units under the minimap (the fitter's minimum is %d)", h, TRACKER_MIN))
		h = TRACKER_MIN
	end
	if h ~= cur then
		t.maxHeight = h
		Bump(f)
		-- (from the game's tracker's height: the fitted one is written as a
		-- number, as 12:-1's Height cannot go below 400)
		Log(f, "F5 tracker", "QuestTracker.maxHeight", format((t.gameH and cur == t.startH) and "maxHeight 0 (the game's tracker's, %d) -> %d" or "maxHeight %d -> %d", cur, h),
			format("stops %d above the pieces under it", GAP))
		Set(f, "12:-1", "Height", floor((max(400, min(1000, h)) - 400) / 10), "F5 tracker",
			"the game's own (hidden) tracker: its Height in the dialog's 400..1000")
	end
end

-- the bottom band and the right column solved at this compact level
local function BandOk(f)
	local why = {}
	for _, x in ipairs(f.flags) do
		if find(x, "chat:", 1, true) == 1 or find(x, "quest tracker:", 1, true) == 1 then
			why[#why + 1] = x
		end
	end
	for _, c in ipairs(Conflicts(f, nil, nil, false)) do
		local a, b = c.a, c.b
		if c.kind == "hard" and a.unit ~= b.unit and U_MAIN[a.unit] and U_MAIN[b.unit] and not Inherited(f, a, b) then
			why[#why + 1] = a.name .. " x " .. b.name
		end
	end
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] and Off(e.l, e.t, e.r, e.b, f.W, f.H) then
			why[#why + 1] = e.name .. " off the screen"
		end
	end
	local top = CentreTop(f)
	local x0 = Third(f)
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] and U_CHAT[e.unit] and e.t < top and e.r > x0 + EPS then
			why[#why + 1] = "chat in the centre third"
		end
	end
	f.bandWhy = why
	return #why == 0
end

-- what the aura blocks run into: the buffs into anything always on; the
-- debuffs and external defensives into what shows with them in a fight
local function AuraHits(f)
	Elements(f)
	local hits = {}
	for _, nm in ipairs(AURA_NAMES) do
		local a = f.N[nm]
		for i = 1, f.nE do
			local e = f.E[i]
			if not U_COLUMN[e.unit] and PERSISTENT[e.cat] and not PairRule(a, e) and not Inherited(f, a, e) then
				local ox = min(a.r, e.r) - max(a.l, e.l)
				local oy = min(a.b, e.b) - max(a.t, e.t)
				if ox > EPS and oy > EPS and Kind(a, e) == "hard" then
					hits[#hits + 1] = nm .. " x " .. e.name
				end
			end
		end
		if Off(a.l, a.t, a.r, a.b, f.W, f.H) then
			hits[#hits + 1] = nm .. " off the screen"
		end
	end
	return hits
end

-- the always-on pieces a full buff block would run into
local function BuffHits(f, names)
	local b = f.N.Buffs
	local any = false
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] and not U_COLUMN[e.unit] and min(b.r, e.r) - max(b.l, e.l) > EPS and min(b.b, e.b) - max(b.t, e.t) > EPS then
			any = true
			if names then
				names[#names + 1] = e.name
			end
		end
	end
	return any
end

-- F6b. A taller aura column runs past the quest tracker's top: the tracker
-- gets narrower, not below 270, so the column runs down beside it; if that is
-- not enough the debuff rows step left of it.
local function F6bColumn(f)
	Elements(f)
	local tl, tt, tr, tb = TrackerRect(f)
	local N = f.N
	local most
	for _, nm in ipairs(AURA_NAMES) do
		local c = N[nm]
		if Yov(c.t, c.b, tt, tb, 0) and Xov(c.l, c.r, tl, tr, GAP) then
			local v = c.r + GAP - tl
			most = most and max(most, v) or v
		end
	end
	if not most then
		return
	end
	local t = f.mello.tracker
	local cut = ceil(most / 10) * 10   -- the Width slider's step
	-- (a tracker matching the minimap's width keeps it)
	if not Column.Model(f).match and t.width - cut >= 270 then
		Log(f, "F6 auras", "QuestTracker.width", format("width %d -> %d", t.width, t.width - cut), "the aura column (32 buffs, 16 debuffs) runs down beside the tracker")
		Eye(f, format("quest tracker %d wide (from %d) beside the taller aura column", t.width - cut, t.width))
		t.width = t.width - cut
		Bump(f)
		return
	end
	local d, x = N.Debuffs, N["External defensives"]
	if Yov(d.t, d.b, tt, tb, 0) or Yov(x.t, x.b, tt, tb, 0) then
		Shift(f, "6:1", "F6 auras", "debuff rows step left of the quest tracker", -ceil((d.r + GAP - tl) * 10) / 10, 0)
	end
end

-- F6a. Buffs are always on: their block (all 32) stays right of the centre
-- third and clear of the persistent pieces -- fewer icons a row, more rows.
-- Debuffs a row: at most buffs - 1.
local function F6Try(f, sizeRaw, sizeLabel)
	for _, key in ipairs(AURA_KEYS) do
		Set(f, key, "IconSize", sizeRaw, "F6 auras", format("aura icons at %s: the column fits beside the tracker and above the bottom centre", sizeLabel))
	end
	if sizeRaw ~= AURA_SIZES[1][1] then
		Eye(f, format("aura icons at %s (from 100%%)", sizeLabel))
	end
	local _, x1 = Third(f)
	local s = f.rec["6:0"]
	local start = Setting(f, s, "IconLimitBuffFrame")
	local bestThird, chosen
	for per = start, 2, -1 do
		SetRaw(f, s, "IconLimitBuffFrame", per)   -- a trial, logged once below
		Elements(f)
		local inThird = f.N.Buffs.l < x1 - EPS
		if not inThird and bestThird == nil then
			bestThird = per
		end
		if not inThird and not BuffHits(f) then
			chosen = per
			break
		end
	end
	if chosen == nil then
		chosen = bestThird or 2
		if bestThird == nil then
			Flag(f, "buffs: even 2 a row reach into the centre third")
		end
	end
	SetRaw(f, s, "IconLimitBuffFrame", start)
	Set(f, "6:0", "IconLimitBuffFrame", chosen, "F6 auras", format("buffs %d a row: the block (32 buffs) stays right of the centre third", chosen))
	if chosen < start then
		Eye(f, format("buffs wrap at %d a row (from %d)", chosen, start))
	end
	if Setting(f, f.rec["6:1"], "IconLimitDebuffFrame") > chosen - 1 then
		Set(f, "6:1", "IconLimitDebuffFrame", max(4, chosen - 1), "F6 auras", "debuffs a row no wider than the buffs above them")
	end
	F6bColumn(f)
	Elements(f)
	local names = {}
	if BuffHits(f, names) then
		Note(f, format("buffs %d a row: a full 32 buffs would reach %s", chosen, concat(names, ", ")))
	end
end

-- F6 for your buff rows by the minimap column (Auras, Attach To The Minimap
-- Column): the game's buff and debuff bars are hidden then, so their Edit
-- Mode settings are left as they are. The rows (all 32 buffs) stay out of the
-- centre third and clear of the always-on pieces: fewer icons a row (Auras'
-- Icons Per Row, down to its least, 6), then smaller icons (RowSizes); when
-- nothing clears everything, the first that clears the centre third is kept
-- and the rest reported. The caller writes them (places.auras) only with
-- auras.fitRows; without it nothing would, so the eye line asks the player
-- to set them, never "wrap at" as if done. The game's external defensives
-- hang on its hidden debuff bar: when the rows run over them, they step
-- down under the rows.
function Column.F6Rows(f)
	local a = f.mello.auras
	local x0, x1 = Third(f)
	local size0, start = a.size, a.perRow
	local sizes = Column.RowSizes(size0, f.rowSizes or {})
	f.rowSizes = sizes
	-- (yours below the slider's least, from an older profile: yours only)
	local least = min(start, Column.ROWS_LEAST)
	local bestS, bestP, chS, chP, ownIn
	for i = 1, #sizes do
		for per = start, least, -1 do
			a.size, a.perRow = sizes[i], per   -- a trial, logged once below
			Bump(f)
			Elements(f)
			local b = f.N.Buffs
			local inThird = b.l < x1 - EPS and b.r > x0 + EPS
			if ownIn == nil then
				ownIn = inThird   -- (the first trial is your own rows)
			end
			if not inThird and bestS == nil then
				bestS, bestP = sizes[i], per
			end
			if not inThird and not BuffHits(f) then
				chS, chP = sizes[i], per
				break
			end
		end
		if chS then
			break
		end
	end
	if not chS then
		chS, chP = bestS or sizes[#sizes], bestP or least
	end
	a.size, a.perRow = size0, start
	if bestS == nil then
		Flag(f, format("your buff rows: even %d a row at icon size %d reach into the centre third", chP, chS))
	end
	if not a.fit then
		-- nothing writes your rows' settings (no places.auras): the fit is
		-- laid for the rows it found, and the player is asked to set them
		-- (the rest of the layout then fits them as they will be)
		if chS ~= size0 or chP ~= start then
			Eye(f, format("your buff rows %s: set Buffs & Debuffs to %d a row, icon size %d (now %d, %d)",
				ownIn and "reach into the centre third" or "run into other pieces", chP, chS, start, size0))
		end
	else
		if chS ~= size0 then
			Log(f, "F6 auras", "Auras.playerSize", format("playerSize %d -> %d", size0, chS), "your buff rows by the minimap: smaller icons keep them out of the centre third")
			Eye(f, format("your buff icons at %d (from %d)", chS, size0))
		end
		if chP ~= start then
			Log(f, "F6 auras", "Auras.playerPerRow", format("playerPerRow %d -> %d", start, chP),
				format("your buff rows by the minimap: %d a row keep all 32 buffs out of the centre third", chP))
			Eye(f, format("your buff rows wrap at %d a row (from %d)", chP, start))
		end
	end
	a.size, a.perRow = chS, chP
	Bump(f)
	Elements(f)
	local N = f.N
	local x, rb = N["External defensives"], N.Debuffs
	local over = false
	for _, nm in ipairs(Column.ROW_NAMES) do
		local p = N[nm]
		if not Inherited(f, p, x) and min(p.r, x.r) - max(p.l, x.l) > EPS and min(p.b, x.b) - max(p.t, x.t) > EPS then
			over = true
		end
	end
	if over then
		Shift(f, "6:2", "F6 auras", "external defensives step down under your buff rows (the game's debuff bar they hang on is hidden)",
			0, -ceil((rb.b + 4 - x.t) * 10) / 10)
	end
	local hits = AuraHits(f)
	if #hits > 0 then
		Note(f, format("your buff rows at %d a row: %s", chP, concat(hits, "; ")))
	end
end

-- F6. The aura column; when the debuffs or external defensives still run
-- into what shows with them in a fight, the icons get smaller (100 -> 90 ->
-- 80 %), then the least bad size is kept (the checks report what remains).
-- Your buff rows by the minimap column instead: Column.F6Rows.
local function F6Auras(f)
	if Column.Attached(f) then
		Column.F6Rows(f)
		return
	end
	-- the game's buff bar hangs on the minimap cluster's top left: a bigger
	-- minimap's painted frame (the round ring, a square border) reaches past
	-- the cluster's left edge into it, so the bar steps left, GAP clear
	Elements(f)
	local b, m = f.N.Buffs, f.N["Minimap (kit frame + zone plate)"]
	if Yov(b.t, b.b, m.t, m.b, 0) and b.l < m.l and b.r > m.l - GAP + EPS then
		Shift(f, "6:0", "F6 auras", format("the buff bar steps left, %d clear of the bigger minimap's frame", GAP), -ceil((b.r - (m.l - GAP)) * 10) / 10, 0)
	end
	local tried = {}
	for _, size in ipairs(AURA_SIZES) do
		local snap = Save(f, f.snapA)
		F6Try(f, size[1], size[2])
		local hits = AuraHits(f)
		if #hits == 0 then
			return
		end
		tried[#tried + 1] = { n = #hits, raw = size[1], label = size[2], hits = hits }
		Restore(f, snap)
	end
	local best = tried[1]
	for i = 2, #tried do
		local t = tried[i]
		if t.n < best.n or (t.n == best.n and t.raw > best.raw) then
			best = t
		end
	end
	F6Try(f, best.raw, best.label)
	Note(f, format("aura column at %s: %s", best.label, concat(best.hits, "; ")))
end

-- F9g. The free spot nearest the piece's designed place when none of its
-- listed places is free: a GRID-unit search over the screen, never in the
-- centre third above the bottom centre, at least GAP from every piece placed
-- before it -- first from all of them, then only from the pieces it shows
-- together with. The piece is then held to the screen corner nearest it.
local function GridSpot(f, unit, later, prep)
	if prep then
		prep()
	end
	local name, key = PIECE[unit][1], PIECE[unit][2]
	Elements(f)
	local me = f.N[name]
	if not me or later[me.unit] then
		return
	end
	local l0, t0, r0, b0 = me.l, me.t, me.r, me.b
	local w, h = r0 - l0, b0 - t0
	local cx0, cy0 = (l0 + r0) / 2, (t0 + b0) / 2
	local x0, x1 = Third(f)
	local ctop = CentreTop(f, later)
	local W, H = f.W, f.H
	local found, foundX, foundY
	local obst, band = {}, {}
	for pass = 1, 2 do
		local strict = pass == 1
		local no = 0
		for i = 1, f.nE do
			local o = f.E[i]
			if not later[o.unit] and o.unit ~= unit and o.unit ~= "popup" and o.cat ~= "Q" and not PairRule(me, o)
				and not Inherited(f, me, o) and (strict or Kind(me, o) == "hard") then
				obst[no + 1], obst[no + 2], obst[no + 3], obst[no + 4] = o.l - GAP, o.t - GAP, o.r + GAP, o.b + GAP
				no = no + 4
			end
		end
		local y = GAP
		while y + h <= H - GAP + EPS do
			Step(f)
			local nb = 0
			for i = 1, no, 4 do
				if obst[i + 1] < y + h and obst[i + 3] > y then
					band[nb + 1], band[nb + 2] = obst[i], obst[i + 2]
					nb = nb + 2
				end
			end
			local x = GAP
			while x + w <= W - GAP + EPS do
				if not (x < x1 and x + w > x0 and y < ctop) then
					local hitR
					for i = 1, nb, 2 do
						if band[i] < x + w and band[i + 1] > x then
							hitR = band[i + 1]
							break
						end
					end
					if hitR == nil then
						local dx, dy = x + w / 2 - cx0, y + h / 2 - cy0
						local d = sqrt(dx * dx + dy * dy)
						if found == nil or d < found then
							found, foundX, foundY = d, x, y
						end
					else
						x = max(x, floor((hitR - x) / GRID) * GRID + x)   -- jump past the piece in the way
					end
				end
				x = x + GRID
			end
			y = y + GRID
		end
		if found then
			break
		end
	end
	if not found then
		return
	end
	local right = foundX + w / 2 > W / 2
	local bottom = foundY + h / 2 > H / 2
	local point = CORNER[(bottom and "B" or "T") .. (right and "F" or "T")]
	Move(f, key, "F9g grid", "", point, point, right and -(W - (foundX + w)) or foundX, bottom and (H - (foundY + h)) or -foundY)
end

local function Less(a, b)
	for i = 1, 6 do
		if a[i] ~= b[i] then
			return a[i] < b[i]
		end
	end
	return false
end

local function Zero(s, n)
	for i = 1, n do
		if s[i] ~= 0 then
			return false
		end
	end
	return true
end

local function SmallRaid(f)
	Set(f, "3:4", "FrameWidth", 0, "F9 raid", "raid frames at the game's smallest size")
	Set(f, "3:4", "FrameHeight", 0, "F9 raid", "raid frames at the game's smallest size")
end

-- F7-F9. The first candidate with no overlap at all and out of the centre
-- third above the bottom centre; else the least bad one (off the screen,
-- then hard overlaps, then the centre third, then soft, rare overlaps, then
-- the candidate order). When no listed place is free of hard overlaps and of
-- the centre third, F9g's nearest free spot is one more candidate.
local function Pick(f, unit, cands, rule)
	local later = LATER[unit]
	local best
	local bestScore, cur = f.bestScore, f.curScore
	local gridAdded = false
	local i = 0
	while i < #cands do
		i = i + 1
		Step(f)
		local snap = Save(f, f.snapP)
		cands[i][2]()
		local hard, soft, rare = Conflicts(f, unit, later, false, true)
		local x0, x1 = Third(f)
		local ctop = CentreTop(f, later)
		local on, mid = true, false
		for j = 1, f.nE do
			local e = f.E[j]
			if e.unit == unit then
				if Off(e.l, e.t, e.r, e.b, f.W, f.H) then
					on = false
				end
				if e.l < x1 - EPS and e.r > x0 + EPS and e.t < ctop - EPS then
					mid = true
				end
			end
		end
		cur[1], cur[2], cur[3], cur[4], cur[5], cur[6] = on and 0 or 1, hard, mid and 1 or 0, soft, rare, i
		Restore(f, snap)
		if best == nil or Less(cur, bestScore) then
			best = i
			for k = 1, 6 do
				bestScore[k] = cur[k]
			end
		end
		if Zero(cur, 5) then
			break
		end
		if i == #cands and not gridAdded and not Zero(bestScore, 3) then
			gridAdded = true
			cands[#cands + 1] = { "the free spot nearest its designed place (grid search)", function() GridSpot(f, unit, later) end }
			if unit == "raid" then
				cands[#cands + 1] = { "the free spot nearest its designed place (grid search), 72 x 36 frames",
					function() GridSpot(f, unit, later, function() SmallRaid(f) end) end }
			end
		end
	end
	local desc = cands[best][1]
	cands[best][2]()
	for _, x in ipairs(f.log) do
		if (x.rule == rule or x.rule == "F9g grid") and x.why == "" then
			x.why = desc
		end
	end
	if not Zero(bestScore, 5) then
		local parts = {}
		for _, c in ipairs(UnitConflicts(f, unit, later)) do
			parts[#parts + 1] = format("%s x %s (%s)", c.a.name, c.b.name, c.kind)
		end
		local txt = #parts > 0 and concat(parts, "; ") or (bestScore[3] ~= 0 and "in the centre third" or "off the screen")
		local line = format("%s ('%s'): %s", unit, desc, txt)
		if bestScore[1] ~= 0 or bestScore[2] ~= 0 then
			Flag(f, line)
		else
			Note(f, line)
		end
	end
	return best
end

local function Nop()
end

-- F9 boss (the biggest of the pieces that show now and then, placed first)
local function F9Boss(f)
	local W = f.W
	Elements(f)
	local N = f.N
	local tl, tt, _, tb = TrackerRect(f)
	local doll = N["Durability doll"]
	local left = min(tl, (Yov(doll.t, doll.b, tt, tb, 0) and doll.r <= tl + EPS) and doll.l or tl)
	local bu, de, ex = N.Buffs, N.Debuffs, N["External defensives"]
	local colL = min(bu.l, de.l, ex.l)
	local colB = max(bu.b, de.b, ex.b)
	local ctop = CentreTop(f)
	local boss = N["Boss frames"]
	local bh = boss.b - boss.t
	local mL, mB = N["Damage meter"].l, N["Damage meter"].b
	local _, chatT, chatR = Union(N["Chat panel"], N["Chat tabs"])
	-- (left of the quest tracker as designed: the boss frames' right edge
	-- BOSS_GAP left of the tracker's left edge, wherever the tracker now is --
	-- under the minimap column since the refit)
	local bx = -(W - tl + Column.BOSS_GAP)
	Pick(f, "boss", {
		{ "left of the quest tracker", function() Move(f, "3:5", "F9 boss", "", nil, nil, bx) end },
		{ "left of the quest tracker, under the aura column", function() Move(f, "3:5", "F9 boss", "", nil, nil, bx, -(colB + GAP)) end },
		{ "left of the aura column, level with the tracker's top", function() Move(f, "3:5", "F9 boss", "", nil, nil, -(W - colL + GAP), -tt) end },
		{ "left of the quest tracker, its bottom on the bottom centre's top", function() Move(f, "3:5", "F9 boss", "", nil, nil, bx, -(ctop - GAP - bh)) end },
		{ "right of the chat, level with its top", function() Move(f, "3:5", "F9 boss", "", "TOPLEFT", "TOPLEFT", chatR + GAP, -chatT) end },
		{ "right of the chat, its bottom on the bottom centre's top", function() Move(f, "3:5", "F9 boss", "", "TOPLEFT", "TOPLEFT", chatR + GAP, -(ctop - GAP - bh)) end },
		{ "under the damage meter", function() Move(f, "3:5", "F9 boss", "", "TOPLEFT", "TOPLEFT", mL, -(mB + GAP)) end },
		{ "left of the doll beside the tracker", function() Move(f, "3:5", "F9 boss", "", nil, nil, -(W - left + 20)) end },
	}, "F9 boss")
end

-- F9. Party / raid frames: as designed, under the damage meter, right of
-- it, right of the chat; then the same places with the raid's smallest
-- frames (a 40-man raid out of the centre third)
local function F9Groups(f)
	Elements(f)
	local N = f.N
	local mt, mr, mb = N["Damage meter"].t, N["Damage meter"].r, N["Damage meter"].b
	local _, chatT, chatR = Union(N["Chat panel"], N["Chat tabs"])
	for _, unit in ipairs(GROUP_UNITS) do
		local key = PIECE[unit][2]
		local rule = "F9 " .. unit
		local c = {}
		for size = 1, (unit == "raid") and 2 or 1 do
			local tag = size == 2 and ", 72 x 36 frames (the game's smallest)" or ""
			local function Sized()
				if size == 2 then
					Set(f, key, "FrameWidth", 0, rule, "raid frames at the game's smallest size")
					Set(f, key, "FrameHeight", 0, rule, "raid frames at the game's smallest size")
				end
			end
			c[#c + 1] = { "where the design has it" .. tag, Sized }
			c[#c + 1] = { "under the damage meter" .. tag, function()
				Sized()
				Move(f, key, rule, "", "TOPLEFT", "TOPLEFT", f.rec[key].anchorInfo.offsetX, -(mb + GAP))
			end }
			c[#c + 1] = { "right of the damage meter" .. tag, function()
				Sized()
				Move(f, key, rule, "", "TOPLEFT", "TOPLEFT", mr + GAP, -mt)
			end }
			c[#c + 1] = { "right of the chat, level with its top" .. tag, function()
				Sized()
				Move(f, key, rule, "", "TOPLEFT", "TOPLEFT", chatR + GAP, -chatT)
			end }
		end
		Pick(f, unit, c, rule)
		if unit == "raid" and Setting(f, f.rec["3:4"], "FrameWidth") ~= f.srcRaidWidth then
			Eye(f, format("raid frames at the game's smallest size, 72 x 36 (from 98 x 44): 8 groups are %d wide instead of %d", 8 * 72, 8 * 98))
		end
	end
end

local function OntoScreenDx(f, e)
	return (e.l < 0 and -e.l + GAP or 0) - (e.r > f.W and e.r - f.W + GAP or 0)
end

-- F7. Focus frame and extra ability follow the frames; when they meet
-- something: pulled onto the screen, lifted above the chat / bottom-right
-- corner, stacked on their frame, or put beside the tracker / meter
local function F7FocusExtra(f)
	Elements(f)
	local N = f.N
	local W, H = f.W, f.H
	local _, chatT, chatR, chatB = Union(N["Chat panel"], N["Chat tabs"])
	local plT, tgT = N["Player frame"].t, N["Target frame"].t
	local axFo, axEx = f.rec["3:2"].anchorInfo.offsetX, f.rec["5:-1"].anchorInfo.offsetX
	local aPl, aTg = f.rec["3:0"].anchorInfo.offsetX, f.rec["3:1"].anchorInfo.offsetX
	local brTop = huge
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] and U_BR[e.unit] then
			brTop = min(brTop, e.t)
		end
	end
	local mL, mB = N["Damage meter"].l, N["Damage meter"].b
	local trL, _, _, trB = TrackerRect(f)
	local dfo, dex = OntoScreenDx(f, N["Focus frame"]), OntoScreenDx(f, N["Extra ability"])
	local ctop = CentreTop(f)
	local groupX = f.rec["0:0"].anchorInfo.offsetX   -- the bottom centre's slide (F2 / F4)
	Pick(f, "focus", {
		{ "beside the player frame", Nop },
		{ "pulled onto the screen", function() Move(f, "3:2", "F7 focus", "", nil, nil, axFo + dfo) end },
		{ "lifted above the chat", function() Move(f, "3:2", "F7 focus", "", nil, nil, axFo + dfo, H - (chatT - GAP)) end },
		{ "on top of the player frame", function() Move(f, "3:2", "F7 focus", "", nil, nil, aPl, H - (plT - GAP)) end },
		{ "under the damage meter", function() Move(f, "3:2", "F7 focus", "", "TOPLEFT", "TOPLEFT", mL, -(mB + GAP)) end },
		{ "right of the chat, level with its bottom", function() Move(f, "3:2", "F7 focus", "", "BOTTOMLEFT", "BOTTOMLEFT", chatR + GAP, H - chatB) end },
	}, "F7 focus")
	Pick(f, "extra", {
		{ "beside the target frame", Nop },
		{ "pulled onto the screen", function() Move(f, "5:-1", "F7 extra", "", nil, nil, axEx + dex) end },
		{ "lifted above the bottom-right corner", function() Move(f, "5:-1", "F7 extra", "", nil, nil, axEx + dex, H - (brTop - GAP)) end },
		{ "on top of the target frame", function() Move(f, "5:-1", "F7 extra", "", nil, nil, aTg, H - (tgT - GAP)) end },
		{ "left of the quest tracker's bottom", function() Move(f, "5:-1", "F7 extra", "", "BOTTOMRIGHT", "BOTTOMRIGHT", -(W - trL + GAP), H - trB) end },
		-- the game's own default: centred above the bars (it shows only in a
		-- fight or a quest, so the always-on rule for the centre third does
		-- not apply)
		{ "above the bottom centre, the game's own place", function() Move(f, "5:-1", "F7 extra", "", "BOTTOM", "BOTTOM", groupX, H - (ctop - GAP)) end },
	}, "F7 extra")
end

-- F8. Durability doll and the tooltip fallback corner (MelloUI puts the
-- tooltips at the cursor, so the corner is a fallback)
local function F8Corner(f)
	Elements(f)
	local W, H = f.W, f.H
	local trL, trT, _, trB = TrackerRect(f)
	local bL, bT, bB = huge, huge, -huge
	for i = 1, f.nE do
		local e = f.E[i]
		if PERSISTENT[e.cat] and U_BR[e.unit] then
			bL, bT, bB = min(bL, e.l), min(bT, e.t), max(bB, e.b)
		end
	end
	Pick(f, "doll", {
		{ "above the tray", Nop },
		{ "left of the quest tracker, level with its top", function() Move(f, "16:-1", "F8 doll", "", "TOPRIGHT", "TOPRIGHT", -(W - trL + GAP), -trT) end },
		{ "left of the micro menu row", function() Move(f, "16:-1", "F8 doll", "", nil, nil, -(W - bL + GAP), H - bB) end },
	}, "F8 doll")
	Pick(f, "tooltip", {
		{ "above the doll", Nop },
		{ "left of the quest tracker's bottom", function() Move(f, "11:-1", "F8 tooltip", "", nil, nil, -(W - trL + GAP), H - trB) end },
		{ "above the bottom-right corner", function() Move(f, "11:-1", "F8 tooltip", "", nil, nil, -18, H - (bT - GAP)) end },
	}, "F8 tooltip")
end

-- F10. The pop-ups the game centres stay where they are; one is pulled back
-- only when it would leave the screen
local function F10Popups(f)
	Elements(f)
	local W, H = f.W, f.H
	for i = 1, f.nE do
		local e = f.E[i]
		if e.unit == "popup" and e.key then
			local dx = (e.l < 0 and -e.l or 0) - (e.r > W and e.r - W or 0)
			local down = (e.t < 0 and -e.t or 0) - (e.b > H and e.b - H or 0)   -- (the screen's y grows downward)
			if (abs(dx) > EPS or abs(down) > EPS) and not f.rec[e.key].isInDefaultPosition then
				Shift(f, e.key, "F10 pop-up", e.name .. " pulled onto the screen", dx, -down)
			end
		end
	end
end

-- The store entry's own scale (the mover's size) when it has one: PlaceSaved
-- sets it and places the window in its own units, and a later SetScale by
-- the panel manager's fit puts it back (UIModifications' SetScale hook), so
-- it replaces the game's fit. Else the game's fit (checkFit) or 1.
local function WindowScale(win, W, H, p)
	local own = p and Num(p.scale)
	if own and own > 0 then
		return own, true
	end
	if not (win and win[3]) then
		return 1, false
	end
	local d = win.dress or EMPTY
	return min(1, (W - win[3]) / (win[1] + (d[1] or 0) + (d[2] or 0)), (H - win[4]) / (win[2] + (d[3] or 0) + (d[4] or 0))), false
end

-- a window at its stored place: the store's compact form (point nil =
-- BOTTOMLEFT, relPoint nil = CENTER), offsets and size times its scale, its
-- dressing round it (the screen's y grows downward)
local function WindowRect(name, p, W, H)
	local win = WINDOWS[name]
	local s, own = WindowScale(win, W, H, p)
	local l, t, r, b = AnchorRect(0, 0, W, H, p.point or "BOTTOMLEFT", p.relPoint or "CENTER", (p.x or 0) * s, (p.y or 0) * s, win[1] * s, win[2] * s)
	local c = win[5]
	if c then
		r, b = r + c * s, b + c * s
	end
	local d = win.dress
	if d then
		l, t, r, b = l - d[1] * s, t - d[3] * s, r + d[2] * s, b + d[4] * s
	end
	return l, t, r, b, s, own
end

-- the world map (702 x 534, 1035 wide with its quest log, times its store
-- scale) and the Quest List docked on its right (+2), as one rect; nil when
-- the store has no place for the map (the game places it then)
local function MapRect(f, withLog)
	local p = f.mello.positions.WorldMapFrame
	if not p then
		return nil
	end
	local s = WindowScale(nil, f.W, f.H, p)
	local l, t, r, b = AnchorRect(0, 0, f.W, f.H, p.point or "BOTTOMLEFT", p.relPoint or "CENTER", (p.x or 0) * s, (p.y or 0) * s,
		(702 + (withLog and 333 or 0)) * s, 534 * s)
	local qr = r + 2 + f.mello.questlist.width
	return min(l, r + 2), t, max(r, qr), b, s
end

local function SortedWindows(P)
	local names = {}
	for name in pairs(P) do
		if WINDOWS[name] then
			names[#names + 1] = name
		end
	end
	sort(names, ByteLess)
	return names
end

-- F12. The window places: W1, on a screen wider than 21:9 a window held to
-- the left / right edge is held to the 21:9 zone's edge instead; W2, a window
-- that would leave the screen at its size (times its scale: its store entry's
-- own, else the game's checkFit) is pulled back by what is missing plus GAP,
-- keeping its anchor. Then the world map + Quest List pair stays on the
-- screen, the Quest List narrower (not below its 260) when the pair is wider
-- than the screen. A map with no place in the store is the game's to place:
-- only the Quest List's width is fitted then (no place is made for the map).
local function F12Windows(f)
	local P = f.mello.positions
	local W, H = f.W, f.H
	for _, name in ipairs(SortedWindows(P)) do
		local p = P[name]
		local before = CopyPlace(p)
		local edge = AXX[p.relPoint or "CENTER"]
		local win = WINDOWS[name]
		local s, own = WindowScale(win, W, H, p)
		local zoned = f.inset ~= 0 and (edge == 0 or edge == 1)
		if zoned then
			p.x = Round1((p.x or 0) + (edge == 0 and f.inset or -f.inset) / s)
		end
		local l, t, r, b = WindowRect(name, p, W, H)
		local dx = (l < 0 and GAP - l or 0) - (r > W and r - W + GAP or 0)
		local down = (t < 0 and GAP - t or 0) - (b > H and b - H + GAP or 0)
		if r - l > W - 2 * GAP then
			dx = (W - (r - l)) / 2 - l
			Flag(f, format("%s is wider than the screen (%.0f of %.0f)", name, r - l, W))
		end
		if b - t > H - 2 * GAP then
			down = (H - (b - t)) / 2 - t
			Flag(f, format("%s is taller than the screen (%.0f of %.0f)", name, b - t, H))
		end
		local pulled = abs(dx) > EPS or abs(down) > EPS
		if pulled then
			p.x = Round1((p.x or 0) + dx / s)
			p.y = Round1((p.y or 0) - down / s)
		end
		if p.x ~= before.x or p.y ~= before.y then
			local why = {}
			if zoned then
				why[#why + 1] = format("W1: held to the 21:9 zone's %s edge", edge == 0 and "left" or "right")
			end
			if pulled then
				local scaled = ""
				if own and abs(s - 1) > 0.001 then
					scaled = format(", at its own scale %.2f", s)
				elseif s < 0.999 then
					scaled = format(", scaled %.2f by the game", s)
				end
				-- (0 - down: an unmoved axis reads 0.0, never -0.0)
				why[#why + 1] = format("W2: pulled onto the screen by %.1f, %.1f (%s is %.0f x %.0f%s)", dx, 0 - down, name, win[1] * s, win[2] * s, scaled)
			end
			Log(f, "F12 windows", "positions." .. name, PlaceText(before) .. " -> " .. PlaceText(p), concat(why, "; "))
		end
	end
	local ql = f.mello.questlist
	local mp = P.WorldMapFrame
	local ms = mp and WindowScale(nil, W, H, mp) or 1
	local function Pull(withLog)
		if not mp then
			return
		end
		local l, t, r, b = MapRect(f, withLog)
		local dx = (l < 0 and -l or 0) - (r > W and r - W or 0)
		local down = (t < 0 and -t or 0) - (b > H and b - H or 0)
		if abs(dx) > EPS or abs(down) > EPS then
			mp.x = Round1((mp.x or 0) + dx / ms)
			mp.y = Round1((mp.y or 0) - down / ms)
			Log(f, "F12 map", "positions.WorldMapFrame", format("moved %.1f, %.1f", dx, 0 - down),
				format("the map%s and the Quest List stay on the screen together", withLog and " with its quest log" or ""))
		end
	end
	for pass = 1, 2 do
		local withLog = pass == 1
		local w, h
		if mp then
			local l, t, r, b = MapRect(f, withLog)
			w, h = r - l, b - t
		else
			w, h = 702 + (withLog and 333 or 0) + 2 + ql.width, 534
		end
		if w <= W and h <= H then
			Pull(withLog)
			if not withLog then
				Note(f, format("world map with its quest log open (1035) + Quest List (%d) are wider than %d units: fits with the log closed", ql.width, Int(W)))
			end
			return
		end
	end
	local room = floor((W - 702 * ms - 2) / 10) * 10
	if room >= 260 then
		local old = ql.width
		ql.width = min(old, room)
		Log(f, "F12 map", "QuestList.width", format("%d -> %d", old, ql.width), "map + Quest List fit the width")
		Eye(f, format("Quest List %d wide (from %d)", ql.width, old))
		Pull(false)
		Note(f, format("world map with its quest log open (1035 wide, the game's own panel) + the Quest List do not fit %d units", Int(W)))
	else
		Flag(f, format("world map + Quest List cannot fit %d units", Int(W)))
	end
end

--------------------------------------------------------------------------------
-- The checks, the verdict, the places
--------------------------------------------------------------------------------

local function CheckAll(f)
	Elements(f)
	local W, H = f.W, f.H
	local rep = { off = {}, hard = {}, soft = {}, rare = {}, info = {}, inherited = {}, centre = {}, centreNowAndThen = {}, stores = {}, windows = {} }
	for i = 1, f.nOrder do
		local key = f.order[i]
		local r = f.R[key]
		if Off(r[1], r[2], r[3], r[4], W, H) then
			rep.off[#rep.off + 1] = format("system %s L%.1f T%.1f R%.1f B%.1f", key, r[1], r[2], r[3], r[4])
		end
	end
	for i = 1, f.nE do
		local e = f.E[i]
		if Off(e.l, e.t, e.r, e.b, W, H) then
			rep.off[#rep.off + 1] = format("%s [%s] L%.1f T%.1f R%.1f B%.1f", e.name, e.cat, e.l, e.t, e.r, e.b)
		end
	end
	local together = {}
	for _, c in ipairs(Conflicts(f, nil, nil, false)) do
		local a, b = c.a, c.b
		local txt = format("%s [%s] x %s [%s] (%.1f x %.1f)", a.name, a.cat, b.name, b.cat, c.ox, c.oy)
		if c.kind == "hard" and not (PERSISTENT[a.cat] and PERSISTENT[b.cat]) then
			txt = txt .. " shows together: " .. TogetherText(a, b)
		end
		local list
		if Inherited(f, a, b) then
			list = rep.inherited
		else
			list = rep[c.kind]
			if c.kind == "hard" then
				together[a.name], together[b.name] = true, true
			end
		end
		list[#list + 1] = txt
	end
	local unitTop = CentreTop(f)
	local zone = W - 2 * f.inset
	local x0, x1 = f.inset + zone / 3, f.inset + 2 * zone / 3
	for i = 1, f.nE do
		local e = f.E[i]
		if e.t < unitTop - EPS and e.r > x0 + EPS and e.l < x1 - EPS and e.unit ~= "frames" then
			if PERSISTENT[e.cat] then
				rep.centre[#rep.centre + 1] = format("%s [%s]", e.name, e.cat)
			elseif e.unit ~= "popup" and e.unit ~= "client" and e.cat ~= "Q" then
				rep.centreNowAndThen[#rep.centreNowAndThen + 1] = format("%s [%s]", e.name, e.cat)
			end
		end
	end
	-- one store per place: no Edit Mode system in MelloUI's own store, no
	-- place of the Quest Tracker's own
	local P = f.mello.positions
	for _, key in ipairs(EDIT_MODE_FRAMES) do
		if P[key] ~= nil then
			rep.stores[#rep.stores + 1] = format("UI Modifications' store holds a place for %s, an Edit Mode system", key)
		end
	end
	if f.mello.tracker.pos ~= nil then
		rep.stores[#rep.stores + 1] = "QuestTracker.pos is set: the tracker would not follow Edit Mode 12:-1"
	end
	-- the windows: only 'on the screen' matters (they open over the HUD by
	-- design); a map with no place of its own is the game's
	for pass = 1, 2 do
		local withLog = pass == 2
		local l, t, r, b = MapRect(f, withLog)
		if l and Off(l, t, r, b, W, H) then
			rep.windows[#rep.windows + 1] = format("world map%s + Quest List %d L%.0f R%.0f (screen %.0f)", withLog and " with its quest log" or "",
				f.mello.questlist.width, l, r, W)
		end
	end
	for _, name in ipairs(SortedWindows(P)) do
		local l, t, r, b = WindowRect(name, P[name], W, H)
		if Off(l, t, r, b, W, H) then
			rep.windows[#rep.windows + 1] = format("%s L%.0f T%.0f R%.0f B%.0f (screen %.0f x %.0f)", name, l, t, r, b, W, H)
		end
	end
	rep.unitTop, rep.third = unitTop, { x0, x1 }
	return rep, together
end

-- every offset a tenth, every setting a whole number the share string holds
local function LayoutOk(f)
	for i = 1, #f.systems do
		local s = f.systems[i]
		local a = s.anchorInfo
		for k = 1, 2 do
			local v = k == 1 and a.offsetX or a.offsetY
			if v ~= v or v == huge or v == -huge or abs(v * 10 - floor(v * 10 + 0.5)) > 1e-6 then
				return false
			end
		end
		for j = 1, #s.settings do
			local v = s.settings[j].value
			if v < 0 or v ~= floor(v) then
				return false
			end
		end
	end
	return true
end

local function Verdict(f, rep)
	local bad = {}
	if #rep.off > 0 then
		bad[#bad + 1] = "off screen"
	end
	if #rep.hard > 0 then
		bad[#bad + 1] = "pieces that show together overlap"
	end
	if #rep.centre > 0 then
		bad[#bad + 1] = "centre third"
	end
	if #rep.stores > 0 then
		bad[#bad + 1] = "store holds an Edit Mode system"
	end
	for _, w in ipairs(rep.windows) do
		if find(w, "world map with its quest log", 1, true) ~= 1 then
			bad[#bad + 1] = "window off the screen"
			break
		end
	end
	if not LayoutOk(f) then
		bad[#bad + 1] = "codec"
	end
	if #f.flags > 0 then
		bad[#bad + 1] = "unsolved"
	end
	if #bad > 0 then
		return "FAIL (" .. concat(bad, ", ") .. ")", false
	end
	return #f.eye > 0 and "PASS, needs the user's eye" or "PASS", true
end

-- One layout name per screen, so two machines sharing the account's layouts
-- keep a fit each: plain `base` on the design screen, else "base WxH" with
-- the physical size when known (the UI units otherwise)
function LayoutFit:LayoutName(W, H, screenW, screenH, base)
	base = base or "MelloUI"
	W, H = Num(W), Num(H)
	if not (W and H) then
		return nil   -- (no size to name it by: never the design screen's name by default)
	end
	if abs(W - DESIGN_W) < 0.5 and abs(H - DESIGN_H) < 0.5 then
		return base
	end
	local w, h = Num(screenW), Num(screenH)
	if not (w and h and w > 0 and h > 0) then
		w, h = W, H
	end
	return format("%s %dx%d", base, floor(w + 0.5), floor(h + 0.5))
end

local function FailReport(why)
	return { verdict = "FAIL (" .. why .. ")", pass = false, cause = "input", tooSmall = false, eye = {}, flags = { why }, notes = {}, log = {}, pieces = {}, checks = {} }
end

--------------------------------------------------------------------------------
-- The whole fit
--------------------------------------------------------------------------------

-- What the approved layout already overlaps at its own screen, with the
-- settings it was drawn with (never the player's: an overlap their settings
-- make is the fit's to solve or report; nor layout E's, new since: the fit
-- makes room for those): kept as designed, not the fitter's to change
local function Inherit(f)
	Reset(f, DESIGN_W, DESIGN_H, Column.APPROVED_INPUTS)
	Step(f)
	for _, c in ipairs(Conflicts(f, nil, nil, false)) do
		local a, b = c.a.name, c.b.name
		f.inh[a] = f.inh[a] or {}
		f.inh[b] = f.inh[b] or {}
		f.inh[a][b], f.inh[b][a] = true, true
	end
end

-- The rules in the built order at W x H with `inputs`, then the checks and
-- the verdict
local function Rules(f, W, H, inputs)
	-- the bottom band at the approved sizes, then smaller ones (F11)
	local tried = {}
	local solved = false
	for level = 0, #COMPACT do
		Reset(f, W, H, inputs)
		Step(f)
		f.level = level
		F0Store(f)
		Step(f)
		F1Zone(f)
		Step(f)
		ApplyCompact(f, level)
		Step(f)
		F0bBars(f)
		Column.F5m(f)
		F5Tracker(f, false, TRACKER_MIN)
		F2Chat(f)
		F3Frames(f)
		F5Tracker(f, true, TRACKER_KEEP)
		local slid = F4Slide(f)
		F5Tracker(f, true, TRACKER_MIN)
		local ok = BandOk(f)
		if slid and ok then
			solved = true
			break
		end
		tried[#tried + 1] = format("level %d: %s", level, #f.bandWhy > 0 and concat(f.bandWhy, "; ") or (f.bandNote or ""))
	end
	if not solved then
		Flag(f, "bottom band not solved even at the smallest compact sizes: " .. ((f.bandNote and f.bandNote ~= "") and f.bandNote or concat(f.bandWhy, "; ")))
	end
	F6Auras(f)
	F9Boss(f)
	F9Groups(f)
	F7FocusExtra(f)
	F8Corner(f)
	F10Popups(f)
	F12Windows(f)
	local rep, together = CheckAll(f)
	for _, t in ipairs(rep.soft) do
		Eye(f, "now and then (never at the same time as the piece under it): " .. t)
	end
	for _, t in ipairs(rep.centreNowAndThen) do
		Eye(f, "in the centre third when it shows: " .. t)
	end
	local verdict, pass = Verdict(f, rep)
	return rep, together, verdict, pass, tried
end

-- Why a fit failed: "size" when the screen is inside SMALL_W x SMALL_H, or
-- when the design's own settings fail on it too (a second fit, on a fresh
-- copy: only on a FAIL); "settings" when they pass (the player's settings
-- are what does not fit, and No reskin would not help)
local function FailCause(info, W, H, inh, job)
	if W < SMALL_W and H < SMALL_H then
		return "size"
	end
	local g = NewState(info, job)
	if not g then
		return "size"
	end
	g.inh = inh
	local _, _, _, pass = Rules(g, W, H, DESIGN_INPUTS)
	return pass and "settings" or "size"
end

local function Core(info, W, H, inputs, opts, job)
	W, H = Num(W), Num(H)
	if not (W and H and W > 0 and H > 0) then
		return nil, nil, FailReport("no screen size")
	end
	inputs = type(inputs) == "table" and inputs or EMPTY
	opts = type(opts) == "table" and opts or EMPTY
	Tables()
	local f, err = NewState(info, job)
	if not f then
		return nil, nil, FailReport(err)
	end
	Inherit(f)
	local rep, together, verdict, pass, tried = Rules(f, W, H, inputs)
	local fitted = f.info
	local name = LayoutFit:LayoutName(W, H, opts.screenW, opts.screenH, opts.baseName)
	fitted.layoutName = name
	-- what the installer writes into MelloUI's own settings for this screen
	-- (a tracker sized by the game's tracker keeps its 0 unless the fit
	-- had to set a size)
	local windows = {}
	for key, p in pairs(f.mello.positions) do
		windows[key] = CopyPlace(p)
	end
	local t = f.mello.tracker
	local places = {
		remove = { EDIT_MODE_FRAMES[1], EDIT_MODE_FRAMES[2], EDIT_MODE_FRAMES[3], EDIT_MODE_FRAMES[4] },
		windows = windows,
		questTracker = { clearPos = true, maxHeight = (t.gameH and t.maxHeight == t.startH) and 0 or t.maxHeight,
			width = (t.gameW and t.width == t.startW) and 0 or t.width },
		questList = { width = f.mello.questlist.width },
		-- your buff rows by the column: Icons Per Row and Icon Size as fitted
		-- (only for a caller that writes them: auras.fitRows)
		auras = (Column.Attached(f) and f.mello.auras.fit) and { playerPerRow = f.mello.auras.perRow, playerSize = f.mello.auras.size } or nil,
		layoutFitFor = format("%.1fx%.1f", W, H),
	}
	-- the preview's pieces, from the same model (palette keys only)
	local moved = {}
	for _, x in ipairs(f.log) do
		moved[x.key] = true
	end
	local pieces = {}
	for i = 1, f.nE do
		local e = f.E[i]
		pieces[i] = { name = e.name, cat = e.cat, unit = e.unit, l = e.l, t = e.t, r = e.r, b = e.b, outline = OUTLINE[e.cat] or "text",
			moved = (e.key and moved[e.key]) and true or false, together = together[e.name] or false }
	end
	local cause = not pass and FailCause(info, W, H, f.inh, job) or nil
	local report = {
		verdict = verdict, pass = pass, cause = cause, tooSmall = cause == "size", suggest = cause == "size" and "noReskin" or nil,
		why = cause == "size" and LayoutFit.TOO_SMALL or cause == "settings" and LayoutFit.SETTINGS_FAIL or nil,
		eye = f.eye, flags = f.flags, notes = f.notes, log = f.log, levelsTried = tried, level = f.level,
		checks = rep, layoutName = name, W = W, H = H, inset = f.inset, third = rep.third, unitTop = rep.unitTop, pieces = pieces,
		legend = { screen = "innerPanel", centreThird = "raisedPanel", centreThirdLines = "border", moved = "hover", together = "selectedTab", zoneEdge = "trim" },
	}
	return fitted, places, report
end

-- opts with the physical screen size filled in (for the layout's name), a copy
local function WithScreen(opts)
	local o = {}
	for k, v in pairs(type(opts) == "table" and opts or EMPTY) do
		o[k] = v
	end
	if o.screenW == nil and o.screenH == nil then
		o.screenW, o.screenH = LayoutFit:PhysicalSize()
	end
	return o
end

-- The whole fit in one go: for tests and tools only. In game use Run: a fit
-- is 2-16 ms of solving (twice that on a FAIL), over the 5 ms frame, so the
-- installer, /mello layout apply and the combat waiter all go through Run.
function LayoutFit:Fit(info, W, H, inputs, opts)
	local ok, fitted, places, report = pcall(Core, info, W, H, inputs, WithScreen(opts), nil)
	if not ok then
		return nil, nil, FailReport("the layout could not be fitted: " .. tostring(fitted))
	end
	return fitted, places, report
end

--------------------------------------------------------------------------------
-- The runner: the fit a frame's share at a time, on Kit:NextFrame
--------------------------------------------------------------------------------

local cache = {}   -- the last fit: key, fitted, places, report

-- a value in the key (a secret one is never turned into text)
local function K(v)
	if Secret(v) then
		return "?"
	end
	return tostring(v)
end

-- the fit's inputs as one string: the layout, the screen, MelloUI's settings
local function KeyOf(info, W, H, inputs, opts, job)
	local parts = { format("%.3f", W), format("%.3f", H), K(opts.screenW), K(opts.screenH), K(opts.baseName) }
	local systems = type(info) == "table" and type(info.systems) == "table" and info.systems or EMPTY
	for i = 1, #systems do
		if i % 16 == 0 then
			JobStep(job)
		end
		local s = systems[i]
		if type(s) == "table" then
			local a = type(s.anchorInfo) == "table" and s.anchorInfo or EMPTY
			parts[#parts + 1] = format("%s|%s|%s|%s|%s|%s|%s|%s", K(s.system), K(s.systemIndex), K(s.isInDefaultPosition),
				K(a.point), K(a.relativePoint), K(a.relativeTo), K(a.offsetX), K(a.offsetY))
			for _, e in ipairs(type(s.settings) == "table" and s.settings or EMPTY) do
				parts[#parts + 1] = K(e.setting) .. "=" .. K(e.value)
			end
		end
	end
	local m = MelloFrom(inputs)
	local t = m.tracker
	parts[#parts + 1] = format("%s|%s|%s|%s|%s|%s|%s|%s", tostring(t.width), tostring(t.maxHeight), tostring(t.scale),
		tostring(t.pos and t.pos.x), tostring(t.pos and t.pos.y), tostring(m.questlist.width), tostring(m.hideBagBar), tostring(m.statsOn))
	parts[#parts + 1] = concat(m.bars, ",")
	local c, a = m.column, m.auras
	parts[#parts + 1] = format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s", tostring(c.kit), c.shape, c.border, tostring(c.merge), tostring(c.bar),
		tostring(c.groups), tostring(c.barOffset), tostring(c.roundIcons), tostring(c.match), tostring(a.rows), tostring(a.attached),
		tostring(a.size), tostring(a.perRow), tostring(a.fit))
	local names = {}
	for name in pairs(m.positions) do
		names[#names + 1] = name
	end
	sort(names, ByteLess)
	for _, name in ipairs(names) do
		local p = m.positions[name]
		parts[#parts + 1] = format("%s:%s:%s:%s:%s:%s", name, tostring(p.point), tostring(p.relPoint), tostring(p.x), tostring(p.y), tostring(p.scale))
	end
	return concat(parts, ";")
end

local function Finish(job)
	job.finished = true
	local done = job.done
	if done then
		local ok, err = pcall(done, job.fitted, job.places, job.report)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local Tick

local function Later(job)
	local Kit = MelloUI.Kit
	if Kit and Kit.NextFrame then
		Kit:NextFrame(job, Tick)
	else
		C_Timer.After(0, function() Tick(job) end)
	end
end

-- the fit, in the job's coroutine: an unchanged screen and unchanged inputs
-- answer from the last fit (the key is made here, in a budgeted frame)
local function Body(job)
	job.key = KeyOf(job.info, Num(job.W) or 0, Num(job.H) or 0, job.inputs, job.opts, job)
	if cache.key ~= nil and cache.key == job.key then
		job.cached = true
		job.fitted, job.places, job.report = CopyInfo(cache.fitted), cache.places, cache.report
		return
	end
	JobStep(job)
	job.fitted, job.places, job.report = Core(job.info, job.W, job.H, job.inputs, job.opts, job)
	if job.fitted then
		JobStep(job)
		cache.key, cache.fitted, cache.places, cache.report = job.key, CopyInfo(job.fitted), job.places, job.report
	end
end

-- this frame's share of the fit
Tick = function(job)
	if job.cancelled or job.finished then
		return
	end
	local now = job.clock()
	-- (a twentieth of the budget is kept for the hand-over itself: the
	-- resume's return and the ask for the next frame)
	job.deadline, job.mark = now + job.budget * 0.95, now
	job.frames = job.frames + 1
	local ok, err = resume(job.co, job)
	if ok and status(job.co) ~= "dead" then
		Later(job)
		return
	end
	if not ok then
		job.fitted, job.places, job.report = nil, nil, FailReport("the layout could not be fitted: " .. tostring(err))
	end
	job.co = nil
	Finish(job)
end

-- The fit in a coroutine, about `opts.budget` ms (2) of solving a frame;
-- done(fitted, places, report) on a later frame. An unchanged screen and
-- unchanged inputs answer from the last fit (places and report are shared:
-- read them, do not change them).
function LayoutFit:Run(info, W, H, inputs, done, opts)
	inputs = type(inputs) == "table" and inputs or EMPTY
	opts = WithScreen(opts)
	local job = { info = info, W = W, H = H, inputs = inputs, opts = opts, done = done, frames = 0, longest = 0, mark = 0, deadline = 0,
		budget = tonumber(opts.budget) or 2, clock = opts.clock or debugprofilestop }
	job.co = create(Body)
	Later(job)
	return job
end

function LayoutFit:Cancel(job)
	if type(job) == "table" then
		job.cancelled = true
		job.co = nil
	end
end

-- a size change (the 'scale' topic) or a new layout: the next fit solves again
function LayoutFit:ClearCache()
	cache.key, cache.fitted, cache.places, cache.report = nil, nil, nil, nil
end

--------------------------------------------------------------------------------
-- What the fit reads from the game and from MelloUI's settings
--------------------------------------------------------------------------------

-- UIParent's size in UI units (the scale is read here, never set)
function LayoutFit:ScreenSize()
	if not UIParent then
		return nil
	end
	local ok, w, h = pcall(UIParent.GetSize, UIParent)
	if not ok then
		return nil
	end
	w, h = Num(w), Num(h)
	if not (w and h and w > 0 and h > 0) then
		return nil
	end
	return w, h
end

-- the physical screen (for the layout's name only)
function LayoutFit:PhysicalSize()
	if not GetPhysicalScreenSize then
		return nil
	end
	local ok, w, h = pcall(GetPhysicalScreenSize)
	if not ok then
		return nil
	end
	return Num(w), Num(h)
end

-- The slots of the hidden bars (3, 4, 6, 7, 8) that hold an action, as data:
-- [slot] = true. `hasAction` is the game's HasAction unless given.
function LayoutFit:ActionSlots(hasAction)
	hasAction = hasAction or _G.HasAction
	local slots = {}
	if type(hasAction) ~= "function" then
		return slots
	end
	for _, bar in ipairs(BAR_SLOTS) do
		for slot = bar[2], bar[3] do
			local ok, v = pcall(hasAction, slot)
			if ok and not Secret(v) and v then
				slots[slot] = true
			end
		end
	end
	return slots
end

local function LiveRead(module, key)
	if key == nil then
		return MelloUI:IsModuleEnabled(module)
	end
	local db = MelloUI:GetModuleDB(module)
	return db and db[key]
end

-- What the fit reads besides the layout: read(module, key) -> value, and
-- read(module) -> whether it is on. The live settings when nil; the
-- installer passes its target's reader (Fresh start changes some of these
-- after the fit, so they are also the result's key).
function LayoutFit:Inputs(read)
	read = read or LiveRead
	local positions
	local store = read("UIModifications", "positions")
	if type(store) == "table" then
		positions = {}
		for name, p in pairs(store) do
			if type(p) == "table" then
				positions[name] = CopyPlace(p)
			end
		end
	end
	local pos = read("QuestTracker", "pos")
	return {
		positions = positions,
		-- the minimap column (layout E) and your buff rows by it; a missing
		-- key reads as the module's default through the live settings
		-- (auras.fitRows is the caller's own: set it where places.auras is
		-- written)
		column = { kit = read("MinimapPanel") and true or false, shape = read("MinimapPanel", "shape"), border = read("MinimapPanel", "squareBorder"),
			merge = read("MinimapPanel", "servicesMerge") ~= false, bar = (read("Services") and read("Services", "showBar") ~= false) and true or false,
			groups = read("Services", "buttonLayout") ~= "all", barOffset = tonumber(read("Services", "barOffset")),
			roundIcons = read("Services", "roundIcons") ~= false,
			match = (read("QuestTracker") and read("QuestTracker", "matchMinimap") ~= false) and true or false },
		auras = { rows = (read("Auras") and read("Auras", "player") ~= false) and true or false, attached = read("Auras", "playerColumn") ~= false,
			size = tonumber(read("Auras", "playerSize")), perRow = tonumber(read("Auras", "playerPerRow")) },
		tracker = { pos = type(pos) == "table" and { x = pos.x, y = pos.y } or nil, width = tonumber(read("QuestTracker", "width")),
			maxHeight = tonumber(read("QuestTracker", "maxHeight")), scale = tonumber(read("QuestTracker", "scale")) },
		questlist = { width = tonumber(read("QuestList", "width")) },
		hideBagBar = (read("Tweaks") and read("Tweaks", "hideBagBar")) and true or false,
		statsOn = read("Stats") and true or false,
		actionSlots = self:ActionSlots(),
	}
end
