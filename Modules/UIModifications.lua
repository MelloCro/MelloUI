--------------------------------------------------------------------------------
-- MelloUI - UI Modifications
--
-- One module for everything that changes how the interface looks and behaves
-- per area (user, 2026-09-21): the painted-kit RESKIN (the first, important
-- option: on or off as a whole, then one switch per area) and the per-area
-- quality-of-life tweaks (nameplates, tooltips, chat, unit frames), which
-- work whether the reskin is on or off. The only thing that matters is that
-- this module is enabled: off, every reskin panel and every folded tweak goes
-- with it (its switch sits in the Configurator's Look page header, labelled
-- "UI Modifications").
--
-- The kit panels (Modules/*Panel.lua) and the folded tweak modules stay
-- separate modules in the code, each with its own /xxdump; they are HIDDEN
-- from the Configurator's side list and switched from here.
--
-- Folded in as well (user, 2026-09-21/22/24): Tweaks, Vendor, FPS / Latency,
-- Fonts, Bar Textures, Bar Text, Class Icons, Cooldown Timers, Dark Mode,
-- Buffs & Debuffs and Error Messages. Only the feature modules (Quest List,
-- Route, Services, Party Markers, Custom Sounds, Voice Over, Quest Tracker)
-- keep switches of their own.
--
-- Its options (0.15.0, the Configurator rebuild) are DEFINITIONS only: each
-- setting's type, name, description and range. Where each one sits is
-- Core/ConfigLayout.lua's: the global look on the Look page, an area's switch
-- on its element's page (a panel's as its "Painted Skin"), a folded
-- feature's switch on the page of what it changes. The look (the palette,
-- the Kit Colours, the borders, the parchment sheets, the UI shade and its
-- areas) is defined here as well: it is chosen on those pages now, with
-- pictures where it has them.
--
-- It also keeps the LIST of the game's elements Edit Layout moves (0.15.0:
-- its windows, the undocked chat windows, and the minimap, the chat, the
-- objective tracker and the damage meter that Edit Mode places too) and
-- registers them with Core's one mover registry, which keeps their places
-- (the one store, this module's `positions` setting) and puts them back
-- after the game lays them out. The moving itself is Edit Layout's
-- (Core/EditLayout.lua and its files); the old Unlock the Windows mode, its
-- grab strips and its provider of Core's mover are gone.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("UIModifications")
-- the kit (Modules/Kit.lua, loaded before this file: see the TOC)
local Kit = MelloUI.Kit

-- The reskin's switches (the kit panels) and the folded features come from
-- the module registry (audit, 2026-09-24, rank 4: they were hand lists here,
-- beside PLAIN_WINDOWS below and the configurator's icons, and had drifted
-- from the modules). Each kit panel gives its row as `window` in its
-- RegisterModule, each folded feature as `tweak` (Core's header):
--   window  { label, desc, tab = "Windows" | "HUD", order, switch, frames,
--             plainGrab, addon, firstOpen, include }
--   tweak   { label, desc, order, off, always }
--   order   rows with one lead their list (their tab), lowest first; the
--           rest follow in the TOC's order
--   switch  the row is not a kit module's but the look switch of one of
--           MelloUI's own windows: that setting of this module, which
--           Kit:IsOn reads (the Quest Tracker's questTrackerKit; audit,
--           2026-09-24, rank 1)
--   include (not read here since 0.15.0: Core/ConfigLayout.lua places every
--           option of a panel, on its element's page)
-- Made into the lists the code below reads, in the registry's order:
--   PANELS  { module name (or the switch), label, description, tab =,
--           setting = true for a switch: no module goes by that name, and
--           the module paths below pass it by }
--   TWEAKS  { module name, label, description, off =, always = }, each
--           switched by `qol_<name>` here (`off`: off until switched on, as
--           the module was before it moved here; `always`: no switch, its
--           rows each switch one thing)
--   AREA_OF [switch key] = { name = the module it switches (nil for a
--           setting switch), tweak = its TWEAKS row (a feature's) }: every
--           area's and feature's switch (M:SetAreas writes only these)
-- This file loads before those modules (see the TOC), so the lists, the
-- switches' defaults and their definitions are made once every module is
-- in: at the addon's own ADDON_LOADED, before the saved settings are read
-- (Lists, by the plain windows' sweep below).
local PANELS, TWEAKS, AREA_OF = {}, {}, {}

-- Flags without option rows: welcomeAsked, the first login was handled (the
-- installer's login check, Core/Installer.lua); seenVersion, the version
-- whose one What's new line was given; layoutApplied, the Edit Mode layout
-- was put in place once when the reskin came on (ReskinOn below) or the
-- installer answered for it; layoutFitFor, layoutFitRev and
-- layoutAsked_<character>, the installer's own facts. The switching
-- functions are defined further down, next to the rest of the switching;
-- declared here so the button's definition can reach them.
local Apply, RestoreAreas, NothingWanted, TweakWanted

-- The look's own state (below): the Kit Colours set inside a Batch applied
-- at its end (Tint.KitColours), the preloaded art held for the look now
-- drawn (Tint.preloaded, Tint.preloadedColours, Tint.LookMoved,
-- Tint.PreloadAgain)
local Tint = {}

-- A bulk switch of painted skins refused in combat (M:SetAreas): the line
-- its callers print
local AREAS_REFUSED = "Not in combat: this would switch painted skins."

local defaults, options = { reskin = true, preloadArt = true, fadeWindows = true, reduceMotion = false,
	parchment_tracker = false, parchment_questTracker = false, parchment_chat = false,
	parchment_whisper = false, parchment_meter = false, parchment_character = false, parchment_tooltip = false, parchment_dialog = false,
	autoSnap = true, positions = {}, welcomeAsked = false, layoutApplied = false, nameFormat = "both", classNames = true,
	-- the palette (0.14.0): an id of MelloUI.Palettes, applied by Core
	-- (MelloUI:SetPalette; this module on or off); a choice, not personal
	palette = "ember" }, {}
-- Edit Layout's (0.15.0): `positions` is Core's one store of places, and
-- `autoSnap` its bar's Snap switch; `snapTargets` ({ [key] = "screen" |
-- "grid" | "off" | another element's key }, nil: the nearest element) is
-- no default (read as {}): profiles carry it, the installer never sets it
for _, k in ipairs(MelloUI.Kit and MelloUI.Kit.borderKinds or {}) do
	defaults[k.key] = k.default
end
-- the UI shade (0.14.0, Modules/KitShade.lua, which loads before this file
-- and switches it from the bus's 'setting'): on at 70 %, every area on
-- (user, 2026-09-26)
do
	local shade, areas = Kit and Kit.shadeSettings, Kit and Kit.shadeAreas
	if type(shade) == "table" and type(areas) == "table" and type(shade.master) == "string" then
		defaults[shade.master], defaults[shade.strength] = true, shade.default
		for _, a in ipairs(areas) do
			if type(a.key) ~= "string" then
				break
			end
			if not a.noSwitch then
				defaults[a.key] = true
			end
		end
	end
end
-- (each area's and feature's switch is added to these by Lists, below)

--------------------------------------------------------------------------------
-- The option definitions (0.15.0): the module's own settings, the look's and,
-- made by Lists once every module is in, each area's and feature's switch.
-- No headers, no includes: Core/ConfigLayout.lua lays each one out. Beyond
-- the schema's usual fields (type, key, name, desc, values, range, parent,
-- requires, new):
--   free    true: applied with this module on or off (OnSettingChanged and
--           the bus's 'setting' below), so a page never dims it for the
--           module being off: the palette, the UI shade and its areas,
--           Reduce Motion
--   get     fn(db) -> the value shown, read another way (the Kit Colours:
--           the choice the kit draws)
--   relist  a bus topic on which the choices are made again (the Kit
--           Colours' are the palette in use's, Kit.colourLooks refilled)
--------------------------------------------------------------------------------

local function Add(opt)
	options[#options + 1] = opt
	return opt
end

Add({ type = "toggle", key = "reskin", name = "Painted kit reskin", important = true,
	desc = "The whole interface dressed in the painted kit. Off: every area shows the game's own art; every feature keeps working." })
Add({ type = "toggle", key = "preloadArt", name = "Preload Artwork", requires = "reskin",
	desc = "Load all of the reskin's artwork during the loading screen, so a window opened for the first time after a reload shows its art at once instead of a moment later. Keeps about 13 MB of artwork in memory for the whole session, including for windows you never open. Off: each piece loads the first time a window needs it." })
Add({ type = "button", name = "Switch every area on", hint = "when nothing is reskinned any more",
	text = "Switch on", requires = "reskin",
	desc = "Every window and HUD area of the reskin back on, and every feature of UI Modifications that is on by default.",
	onClick = function(_, db)
		local ok, count = RestoreAreas(db)
		if not ok then
			MelloUI:Print(AREAS_REFUSED)
			return
		end
		if count == 0 then
			MelloUI:Print("Every area is on already.")
			return
		end
		MelloUI:Print("%d area%s switched back on.", count, count == 1 and "" or "s")
		if MelloUI.RefreshConfig then
			MelloUI:RefreshConfig()
		end
	end })

-- The palette (0.14.0): Core applies it (MelloUI:SetPalette), this module on
-- or off; its choices are the widget set's one list, every palette by its
-- name (W.PaletteValues)
do
	-- (no widget set: a file an update added, loaded only after a restart;
	-- the Configurator stands down until then)
	local W = MelloUI.Widgets
	Add({ type = "dropdown", key = "palette", name = "Palette", free = true,
		values = type(W) == "table" and type(W.PaletteValues) == "function" and W.PaletteValues() or {},
		desc = "The colours of MelloUI's own windows and, with the painted kit reskin, of all its art. Your choice applies at once, with the reskin on or off." })
end

-- The borders, one choice per kind for every window, and the Kit Colours
-- (Kit.borderKinds; the kit applies a choice: OnSettingChanged below). The
-- Kit Colours' choices are the palette in use's (Kit.colourLooks, the same
-- table filled again on a switch), and the one shown is the one the kit
-- draws: a Bronze kept from Ember shows, under another palette, as that
-- palette's own kit (Kit:ColourLookShown, the kit's one answer)
local function ColoursShown(db)
	local K = MelloUI.Kit   -- (looked up now: the kit a world has when it is asked)
	local look = K and K.ColourLookShown and K:ColourLookShown()
	if look then
		return look.value
	end
	return db and db.kitColours
end
for _, k in ipairs(MelloUI.Kit and MelloUI.Kit.borderKinds or {}) do
	local opt = Add({ type = "dropdown", key = k.key, name = k.name, values = k.values, desc = k.desc,
		requires = "reskin", new = k.new })
	if k.kind == "colours" then
		opt.get, opt.relist = ColoursShown, "palette"
	end
end

-- The UI shade (0.14.0, Modules/KitShade.lua): its switch, its strength and a
-- switch per area (Kit.shadeAreas' order), each area's live while the shade
-- is on. Applied from the bus's 'setting' (KitShade), this module on or off
do
	local shade = Kit and Kit.shadeSettings
	if type(shade) == "table" and type(shade.master) == "string" and type(shade.strength) == "string" then
		Add({ type = "toggle", key = shade.master, name = "UI Shade", free = true,
			desc = "A soft dark shade round the kit's outlines, so windows, bars and frames stand out from the world. Each area has its own switch under it." })
		Add({ type = "slider", key = shade.strength, name = "Shade Strength", parent = shade.master, free = true,
			min = shade.min, max = shade.max, step = shade.step, percent = true,
			desc = "How dark the shade round the kit's outlines is, the nameplates' shade too." })
		-- (the nameplates' area has no switch here: Nameplates > Name Shade's
		-- Whole plate is it, 0.16.0)
		for _, a in ipairs(type(Kit.shadeAreas) == "table" and Kit.shadeAreas or {}) do
			if type(a.key) ~= "string" then
				break
			end
			if not a.noSwitch then
				Add({ type = "toggle", key = a.key, name = "Shade: " .. a.label, requires = shade.master, free = true, new = a.new,
					desc = "The UI Shade round the " .. a.label:lower() .. ". Off: no shade there; the other areas keep theirs." })
			end
		end
	end
end

-- The parchment sheets (the kit's, Kit:SetParchment; the text on them in
-- dark ink): one switch per area, live with the reskin. The list is the
-- installer's too (its Fresh start lists the same areas, one list: read
-- only)
local PARCHMENTS = {
	{ "parchment_tracker", "Objective Tracker" },
	{ "parchment_questTracker", "Quest Tracker" },
	{ "parchment_chat", "Chat" },
	{ "parchment_whisper", "Whisper Popup" },
	{ "parchment_meter", "Damage Meter" },
	{ "parchment_character", "Character Window" },
	{ "parchment_tooltip", "Tooltips" },
	{ "parchment_dialog", "Dialogs" },     -- (user, 2026-09-24: the popup dialogs, "add a parchment to it")
}
MelloUI.ParchmentAreas = PARCHMENTS
local PARCHMENT_DESC = {
	parchment_tracker = "The game's objective tracker on a parchment sheet, its text in dark ink.",
	parchment_questTracker = "MelloUI's Quest Tracker on a parchment sheet, its text in dark ink.",
	parchment_chat = "The chat windows on a parchment sheet, their text in dark ink.",
	parchment_whisper = "The whisper popup on a parchment sheet, its text in dark ink.",
	parchment_meter = "The damage meter on a parchment sheet, its text in dark ink.",
	parchment_character = "The character window on a parchment sheet, its text in dark ink.",
	parchment_tooltip = "The tooltips on a parchment sheet, their text in dark ink.",
	parchment_dialog = "The popup dialogs, the colour picker, ready checks and split stack on a parchment sheet, their text in dark ink.",
}
for _, entry in ipairs(PARCHMENTS) do
	Add({ type = "toggle", key = entry[1], name = "Parchment: " .. entry[2], requires = "reskin", new = entry.new,
		desc = PARCHMENT_DESC[entry[1]] })
end

Add({ type = "toggle", key = "fadeWindows", name = "Windows Fade In",
	desc = "Every window fades in over a fifth of a second when it opens, instead of appearing at once: the character window, talents and spells, professions, the bags, social, guild, group finder, collections, the map, the game menu and the rest. Works with the reskin on or off." })
Add({ type = "toggle", key = "reduceMotion", name = "Reduce Motion", free = true,
	desc = "Every MelloUI animation ends at once: windows open without fading, the whisper popup appears in place, the quest tracker's lines do not flash, the configurator jumps instead of gliding. For anyone who finds moving interface parts distracting. Works with UI Modifications switched off as well." })
-- Names (user, 2026-09-22: "make that option global for all of the 3
-- things at the same time"): one dropdown for the unit frames, the
-- nameplates and the name over your own head. Characters here have a first
-- name and a surname. The unit frames and nameplates are re-set by their
-- modules (their `nameFormat`, driven from here); the name the engine draws
-- over heads has ONE setting, the client's `UnitSurnameOwn` cvar ("show
-- player surname over head", the binary's only surname cvar): your own
-- name follows, other players' overhead names are the engine's and have
-- no setting (nameplates on shows them in the chosen form).
-- (0.16.0: Chat's Names In Chat merged in: one form for the frames, the
-- nameplates and the chat; its old value carried, MelloUI:MergeSettings)
Add({ type = "dropdown", key = "nameFormat", name = "Show Names As", values = {
	{ value = "both", label = "Full name (Professor Skillybones)" },
	{ value = "initial", label = "Initial and surname (P. Skillybones)" },
	{ value = "firstinitial", label = "Name and initial (Professor S.)" },
	{ value = "first", label = "First name (Professor)" },
	{ value = "last", label = "Surname (Skillybones)" },
}, desc = "How a character's name is written, everywhere at once: the player, target, focus, pet, party and raid frames, the nameplates, the chat and whisper windows, and the name over your own head (the game's own setting for it: only First name leaves out the surname there). A character with no surname shows the name it has; in the chat the name is still a link to the player. Names over other players' heads without a nameplate are the engine's and have no setting." })
-- (0.16.0: chat's and the tooltip's Class Coloured Names merged: one
-- switch, read by both as saved, UI Modifications on or off)
Add({ type = "toggle", key = "classNames", name = "Class Coloured Names", free = true,
	desc = "Players' names in their class colour: in every chat type (the game's own setting for it) and in the tooltip. On the parchment sheet a chat name is in dark ink with a gem in its class colour before it instead." })

local M = MelloUI:RegisterModule("UIModifications", {
	title = "UI Modifications",
	desc = "The painted kit reskin, area by area, and the interface's features: buffs and debuffs, error messages, cooldowns, unit frames, chat, tooltips, fonts, dark mode and more. The look is chosen on the Look page and on each element's own page.",
	enabledByDefault = true,
	important = true,
	-- it drives every reskin panel and folded tweak, so its OFF state has to
	-- be applied at start-up too, not only when the switch is thrown
	applyWhenDisabled = true,
	-- a borrowed game setting, one-time steps, and the installer's facts
	-- about this machine and character (the version it last showed, the
	-- layout questions asked, the screen the layout was fitted for): never
	-- in a profile; and Dark Mode's switch, the player's own preference
	-- (user, 2026-09-26: no profile carries it)
	keep = { "savedSurnameOwn", "layoutApplied", "welcomeAsked", "bordersMigrated", "featuresFolded", "questTrackerKitMigrated",
		"seenVersion", "^layoutAsked_", "layoutFitFor", "layoutFitRev", "qol_DarkMode" },
	defaults = defaults,
	options = options,
	icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_02",
	flavour = "The painted reskin, area by area, and the quality-of-life tweaks on nameplates, tooltips, chat and unit frames. Start here.",
	group = "The look", navOrder = 1,
	role = "core",
})

-- the line a caller of M:SetAreas prints when it is refused in combat
M.areasRefused = AREAS_REFUSED

--------------------------------------------------------------------------------
-- The game's elements Edit Layout moves (0.15.0: Edit Layout, Core/
-- EditLayout.lua, is the one place to move things; it replaced Unlock the
-- Windows, its grab strips, its snapping and its provider of Core's mover).
-- This module keeps only the LIST of them, its candidates, and registers
-- them through Core's one registry (MelloUI:RegisterMover); Core keeps their
-- places in its one store, puts them back after the game lays them out
-- (`follow`) and holds an Edit Layout session's pending changes. Each is
-- live (`when`) only while this module is on:
--   windows   every frame a module's `window` names with `plainGrab`, and
--             every game window the kit dressed (Kit.shells; MelloUI's own
--             windows register themselves; an Edit Mode system is the
--             game's, Edit Layout's bridge): key = the frame's name, group
--             "window", its module's label and page (else a name made from
--             the frame's and this module's page), no default (a Reset
--             closes an open one and the game lays it out afresh); the world
--             map keeps the Quest List beside it on the screen (`with`,
--             looked up when needed)
--   chat      every chat window NOT docked with ChatFrame1 (the game's
--             temporary whisper windows too): "Chat: <its tab>", its
--             standard place the game's own saved one
--   the four  MinimapCluster, ChatFrame1 (the dock), ObjectiveTrackerFrame
--             and DamageMeter (Core/LayoutFit.lua's EDIT_MODE_FRAMES): Edit
--             Mode systems, moved only by their plain <Method>Base methods
--             (Core's); MelloUI's place wins while it has one, and a Reset
--             hands the element back to Edit Mode's place (group "hud")
-- When they register (the first-open rule, WINDOW-RULES 2f: no frame is
-- made for any of them): at login only the ones with a stored place (the
-- four and the chat windows at OnEnable, shown at once; the rest after
-- MelloUI:AfterLogin), a window loaded on demand with a stored place at its
-- addon's ADDON_LOADED, a window the kit dresses on its first show with a
-- stored place as it is dressed (the bus's 'shell'), the whole store
-- replaced (a profile, the installer) on the next frame; every other one
-- when Edit Layout opens (this module's mover source).
--------------------------------------------------------------------------------

-- The windows a module's `window` names with `plainGrab` (MelloUI's own
-- windows are not among them: they register with Core themselves). Made by
-- Lists, as PLAIN[name] = true too; WINDOW_OF[frame name] = { label, page }
-- for every frame a `window` names (its plate's name and its page).
local PLAIN_WINDOWS, PLAIN, WINDOW_OF = {}, {}, {}

-- The lists made from the registry (PANELS, TWEAKS and AREA_OF: see the
-- top; PLAIN_WINDOWS, PLAIN and WINDOW_OF: above), the switches' defaults
-- and their definitions, once: at the addon's own ADDON_LOADED, when every
-- module is in (the sweep's event, below), so the defaults are complete
-- before Core reads the saved settings against them at login; OnInit makes
-- sure of it. The registry does not change after.
local listed = false
local TAB_RANK = { Windows = 1, HUD = 2 }

local function InOrder(entries, into)
	table.sort(entries, function(a, b)
		if a.tab ~= b.tab then
			return a.tab < b.tab
		elseif a.order ~= b.order then
			return a.order < b.order
		end
		return a.at < b.at
	end)
	for i, entry in ipairs(entries) do
		into[i] = entry.row
	end
end

local function Lists()
	if listed then
		return
	end
	listed = true
	local panels, tweaks = {}, {}
	for at, module in ipairs(MelloUI:ModulesInOrder()) do
		local w, t = module.window, module.tweak
		if w and w.label then
			panels[#panels + 1] = { at = at, tab = TAB_RANK[w.tab] or 3, order = type(w.order) == "number" and w.order or math.huge,
				row = { w.switch or module.name, w.label, w.desc or "", tab = w.tab, setting = w.switch and true or nil } }
		end
		if w and type(w.frames) == "table" then
			for _, name in ipairs(w.frames) do
				if w.plainGrab and not PLAIN[name] then
					PLAIN_WINDOWS[#PLAIN_WINDOWS + 1] = name
					PLAIN[name] = true
				end
				if type(name) == "string" and not WINDOW_OF[name] then
					WINDOW_OF[name] = { label = type(w.label) == "string" and w.label or name, page = module.name }
				end
			end
		end
		if t and t.label then
			tweaks[#tweaks + 1] = { at = at, tab = 0, order = type(t.order) == "number" and t.order or math.huge,
				row = { module.name, t.label, t.desc or "", off = t.off and true or nil, always = t.always and true or nil } }
		end
	end
	InOrder(panels, PANELS)
	InOrder(tweaks, TWEAKS)
	for _, area in ipairs(PANELS) do
		defaults[area[1]] = true
	end
	-- (an `always` tweak has no switch, so no default either: Everything
	-- Off (Core's FreshProfileText) would write its qol_ key as false, and
	-- the one-time fold in OnEnable would take that for a switched-off
	-- Tweaks and reset its rows)
	for _, tweak in ipairs(TWEAKS) do
		if not (tweak.off or tweak.always) then
			defaults["qol_" .. tweak[1]] = true
		end
	end
	-- each area's and feature's switch, defined after the module's own (the
	-- same table the configurator was given): a panel's needs the reskin, a
	-- feature's works with it on or off
	for _, area in ipairs(PANELS) do
		AREA_OF[area[1]] = { name = not area.setting and area[1] or nil }
		Add({ type = "toggle", key = area[1], name = area[2], desc = area[3], requires = "reskin" })
	end
	for _, tweak in ipairs(TWEAKS) do
		if not tweak.always then
			AREA_OF["qol_" .. tweak[1]] = { name = tweak[1], tweak = tweak }
			Add({ type = "toggle", key = "qol_" .. tweak[1], name = tweak[2], desc = tweak[3] })
		end
	end
end

-- The four Edit Mode systems MelloUI keeps a place for too (Core/LayoutFit.lua's
-- EDIT_MODE_FRAMES, one list: the installer's fitter reads it the same way),
-- each with its plate's name, its settings' page and its system's name in
-- Enum.EditModeSystem (read when the frame names none of its own)
local SHARED = {
	MinimapCluster = { label = "Minimap", page = "MinimapPanel", system = "Minimap" },
	ChatFrame1 = { label = "Chat", page = "Chat", system = "ChatFrame" },
	-- (its options are the Objective Tracker panel's: the Quest Tracker page's
	-- Objective Tracker tab, not MelloUI's own tracker's first one)
	ObjectiveTrackerFrame = { label = "Objective tracker", page = "TrackerPanel", system = "ObjectiveTracker" },
	DamageMeter = { label = "Damage meter", page = "DamageMeterPanel", system = "DamageMeter" },
}
local function SharedNames()
	local fit = MelloUI.LayoutFit
	local names = type(fit) == "table" and fit.EDIT_MODE_FRAMES
	return type(names) == "table" and names or { "MinimapCluster", "DamageMeter", "ChatFrame1", "ObjectiveTrackerFrame" }
end

local EDIT_TEXT = {
	sharedNote = "Edit Mode can move this too. While it has a place here, that place wins.",
	sharedReset = "Back to Edit Mode's place",
	editModeLater = "%s returns to Edit Mode's place after a reload.",
	gameLater = "%s returns to the game's place after a reload.",
	chat = "Chat: %s",
	chatWindow = "Chat window %d",   -- (a chat window whose tab name does not read plainly)
	bag = "Bag %d",                  -- (a separate bag window, ContainerFrameN)
}

local Secret, Num, Finite = MelloUI.Safe.IsSecret, MelloUI.Safe.Number, MelloUI.Safe.Finite

-- the entries registered here (weak: Core keeps them)
local mine = setmetatable({}, { __mode = "k" })

-- a candidate's `when`: this module on (one function for all)
local function ModuleOn()
	return M.isEnabled and true or false
end

local function SharedNote()
	return EDIT_TEXT.sharedNote
end

-- the world map carries the Quest List beside it (made on the map's first
-- show: looked up when needed)
local function QuestListBeside()
	return _G.MelloUIQuestListPanel
end
local WITH = { WorldMapFrame = QuestListBeside }

-- The game's bag windows: the combined one and each bag's own
local BAG_WINDOWS = { "ContainerFrameCombinedBags" }
for i = 1, 13 do
	BAG_WINDOWS[#BAG_WINDOWS + 1] = "ContainerFrame" .. i
end

-- A bag window carries the bag windows the game stacks on it (0.17.0; a
-- player's bags went off the screen): on every open the game hangs each
-- shown bag on the one before it, up a column and then in columns to its
-- left, so a bag moved up or aside took the rest past the screen's edge.
-- Its `with` is that stack, the shown bags whose anchors lead to it, so its
-- place is kept on the screen together with them (Core's FitOffsets; Edit
-- Layout's drag the same). The bag frames looked up on first need.
local bagSet, bagList
local bagStack = {}   -- (BagStack's answer, reused: read at once)

local function BagStack(entry)
	local root = entry and entry.frame
	if not bagList then
		bagSet, bagList = {}, {}
		for _, name in ipairs(BAG_WINDOWS) do
			local f = _G[name]
			if type(f) == "table" and f.GetPoint then
				bagSet[f] = true
				bagList[#bagList + 1] = f
			end
		end
	end
	wipe(bagStack)
	for _, bag in ipairs(bagList) do
		local okV, shown = pcall(bag.IsShown, bag)
		if bag ~= root and okV and not Secret(shown) and shown then
			-- up its chain of anchors, bag on bag, to this one
			local f = bag
			for _ = 1, #bagList do
				local ok, _, rel = pcall(f.GetPoint, f, 1)
				if not ok or Secret(rel) or not bagSet[rel] then
					break
				end
				if rel == root then
					bagStack[#bagStack + 1] = bag
					break
				end
				f = rel
			end
		end
	end
	return bagStack
end
for _, name in ipairs(BAG_WINDOWS) do
	WITH[name] = BagStack
end

-- a chat window's id, and whether it hangs in the dock (the game's own
-- setting for it, or the frame's own mark), read plainly
local function ChatId(frame)
	local ok, id = pcall(frame.GetID, frame)
	id = ok and Num(id)
	return (id and id > 0) and id or nil
end

local function ChatInfo(id)
	local info = _G.GetChatWindowInfo
	if not id or type(info) ~= "function" then
		return nil
	end
	local ok, name, _, _, _, _, _, _, _, docked = pcall(info, id)
	if not ok then
		return nil
	end
	return MelloUI.Safe.Text(name), (not Secret(docked) and docked) and true or false
end

local function Docked(frame)
	local mark = frame.isDocked
	if not Secret(mark) and mark then
		return true
	end
	local _, docked = ChatInfo(ChatId(frame))
	return docked and true or false
end

-- an undocked chat window's `when`: this module on and the window out of the dock
local function ChatLive(entry)
	return M.isEnabled and not Docked(entry.frame) and true or false
end

-- the chat dock's plate shows while ChatFrame1 or the dock's selected tab does
local function DockShown(entry)
	local frame = entry.frame
	local ok, shown = pcall(frame.IsShown, frame)
	if ok and not Secret(shown) and shown then
		return true
	end
	local dock = GENERAL_CHAT_DOCK
	local selected = type(dock) == "table" and dock.selected
	if Secret(selected) or type(selected) ~= "table" or type(selected.IsShown) ~= "function" then
		return false
	end
	local okS, on = pcall(selected.IsShown, selected)
	return (okS and not Secret(on) and on) and true or false
end

-- The four's standard place: Edit Mode's, from the active saved layout
-- (MelloUI:EditModeSystemAnchor, read only), laid with their plain methods
-- (Core's PlaceEntryAt). A preset layout, a secret, or a system at its
-- default place inside a container the game lays out (the tracker) gives
-- none: it stays where it is, and the line says when it goes back.
local function EditModeHome(frame)
	local entry = MelloUI:MoverEntry(frame)
	if not entry then
		return false
	end
	local info = SHARED[entry.key]
	local system, index = frame.system, frame.systemIndex
	system = Num(system)
	if not system and info and Enum and Enum.EditModeSystem then
		system = Num(Enum.EditModeSystem[info.system])
	end
	index = Num(index)
	if system and MelloUI.EditModeSystemAnchor then
		local p, to, rp, x, y, inDefault = MelloUI:EditModeSystemAnchor(system, index)
		local managed = frame.isManagedFrame
		if p and not (inDefault and not Secret(managed) and managed) then
			local rel = _G[to]
			if type(rel) ~= "table" then
				rel = UIParent
			end
			if MelloUI:PlaceEntryAt(entry, p, rel, rp, x, y) then
				return true
			end
		end
	end
	return false, EDIT_TEXT.editModeLater:format(entry.label or entry.key)
end

-- An undocked chat window's standard place: the game's own saved one (its
-- point and the offsets as shares of the screen, read plainly), as the game
-- lays it at login
local function ChatHome(frame)
	local entry = MelloUI:MoverEntry(frame)
	if not entry then
		return false
	end
	local saved, id = _G.GetChatWindowSavedPosition, ChatId(frame)
	if id and type(saved) == "function" then
		local ok, point, x, y = pcall(saved, id)
		if ok and not Secret(point) and type(point) == "string" and Finite(x) and Finite(y) then
			local okS, w, h = pcall(UIParent.GetSize, UIParent)
			w, h = okS and Finite(w), okS and Finite(h)
			if w and h and MelloUI:PlaceEntryAt(entry, point, UIParent, point, x * w, y * h) then
				return true
			end
		end
	end
	return false, EDIT_TEXT.gameLater:format(entry.label or entry.key)
end

-- ChatFrame2 and every one after it: its number, else nil. The game's
-- temporary windows (a whisper in a tab of its own) come after the last
-- standing one (ChatFrame11 ...): chat windows too, live only out of the dock
local function ChatNumber(name)
	local n = tonumber(name:match("^ChatFrame(%d+)$"))
	return (n and n >= 2) and n or nil
end

-- a chat window's plate name: "Chat: <its tab>" (a standing window's name as
-- the game saves it, else the window's own -- a temporary one's is its
-- whisper partner's, set by the game when it made the tab); a name that
-- does not read plainly gives its number
local function ChatLabel(frame, n)
	local tab = n <= (NUM_CHAT_WINDOWS or 10) and ChatInfo(ChatId(frame)) or nil
	if not tab or tab == "" then
		tab = MelloUI.Safe.Text(frame.name)
	end
	return (tab and tab ~= "") and EDIT_TEXT.chat:format(tab) or EDIT_TEXT.chatWindow:format(n)
end

-- a game window the kit dressed that no module's `window` names: its plate's
-- name made from its frame's ("AuctionHouseFrame": "Auction House", a
-- separate bag's ContainerFrame3: "Bag 3"), never the raw code name
local function Readable(name)
	local bag = name:match("^ContainerFrame(%d+)$")
	if bag then
		return EDIT_TEXT.bag:format(tonumber(bag))
	end
	local s = name:gsub("Frame(%d*)$", "%1")
	s = s:gsub("(%l)(%u)", "%1 %2")
	s = s:gsub("(%u)(%u%l)", "%1 %2")
	s = s:gsub("(%a)(%d)", "%1 %2")
	s = s:gsub("_", " ")
	s = s:match("^%s*(.-)%s*$")
	return s ~= "" and s or name
end

-- one of Edit Mode's systems (the loot window, the talking head ...): the
-- game's to place, Edit Layout's bridge hands it to Edit Mode; only the
-- four above are MelloUI's as well. Read plainly: its system's number, and
-- the plain SetPoint Edit Mode keeps aside on each system it takes in
local function IsEditModeSystem(frame)
	local system = frame.system
	return not Secret(system) and type(system) == "number" and type(frame.SetPointBase) == "function"
end

-- the registration of a candidate, or nil for a frame that is none (its
-- module's own window, a forbidden frame, a frame of another addon, an Edit
-- Mode system but the four)
local function CandidateOpts(frame, name)
	if type(frame) ~= "table" or type(name) ~= "string" or type(frame.GetObjectType) ~= "function" then
		return nil
	end
	if frame.IsForbidden then
		local ok, forbidden = pcall(frame.IsForbidden, frame)
		if not ok or Secret(forbidden) or forbidden then
			return nil
		end
	end
	local shared = SHARED[name]
	if shared then
		return { key = name, follow = true, when = ModuleOn, group = "hud", label = shared.label, page = shared.page,
			default = EditModeHome, resetLabel = EDIT_TEXT.sharedReset, note = SharedNote,
			visible = name == "ChatFrame1" and DockShown or nil }
	end
	local n = ChatNumber(name)
	if n then
		return { key = name, follow = true, when = ChatLive, group = "window", label = ChatLabel(frame, n),
			page = "Chat", default = ChatHome }
	end
	if IsEditModeSystem(frame) then
		return nil
	end
	local shells = Kit and Kit.shells
	if not (PLAIN[name] or (type(shells) == "table" and shells[frame] and not name:find("^MelloUI"))) then
		return nil
	end
	local window = WINDOW_OF[name]
	return { key = name, follow = true, when = ModuleOn, group = "window", label = window and window.label or Readable(name),
		page = window and window.page or M.name, with = WITH[name] }
end

-- a candidate by its name (and its frame, when known) registered, once
local function RegisterNamed(name, frame)
	frame = frame or _G[name]
	if type(frame) ~= "table" or MelloUI:MoverEntry(frame) then
		return
	end
	local opts = CandidateOpts(frame, name)
	if opts then
		local entry = MelloUI:RegisterMover(frame, frame, opts)
		if entry then
			mine[entry] = true
		end
	end
end

-- The candidates that have a place in the store (which = "shown": only the
-- ones the game shows at once -- the four and the chat windows, docked ones
-- too: their `when` keeps a docked one where the dock lays it), registered:
-- Core places each as it registers. (The lists are made by then: at the
-- addon's ADDON_LOADED and OnInit, before any OnEnable)
local function RegisterStored(which)
	if not M.isEnabled then
		return
	end
	local db = MelloUI:GetModuleDB(M.name)
	local store = type(db) == "table" and db.positions
	if type(store) ~= "table" then
		return
	end
	for key in pairs(store) do
		if type(key) == "string" and (which ~= "shown" or SHARED[key] or ChatNumber(key)) then
			RegisterNamed(key)
		end
	end
end
local function RegisterAllStored()
	RegisterStored()
end

-- the registered candidates put where the store says (a profile's, a new
-- store's); shown: only the ones that show (the rest on their next show)
local function PlaceRegistered(shown)
	for entry in pairs(mine) do
		if entry.key ~= nil and MelloUI:GetPosition(entry.key) and (not shown or MelloUI:EntryShown(entry)) then
			MelloUI:RestorePosition(entry.key, entry.frame)
		end
	end
end

-- the whole store replaced (a profile, the installer): its candidates
-- registered on the next frame, the shown ones placed from it.
-- registeredFrom: the store they were last registered from
local registeredFrom = nil
local function NewStore()
	RegisterStored()
	PlaceRegistered(true)
end

-- The mover source (Core's MelloUI:AddMoverSource): Edit Layout runs it at
-- each open and resume, and every candidate not registered yet registers
-- then -- a player's action, never the login. The four first, then the
-- windows, the undocked chat windows and the kit's dressed windows.
local function Candidates()
	if not M.isEnabled then
		return
	end
	Lists()
	for _, name in ipairs(SharedNames()) do
		RegisterNamed(name)
	end
	for _, name in ipairs(PLAIN_WINDOWS) do
		RegisterNamed(name)
	end
	for i = 2, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if type(frame) == "table" and not Docked(frame) then
			RegisterNamed("ChatFrame" .. i, frame)
		end
	end
	local shells = Kit and Kit.shells
	if type(shells) == "table" then
		for frame in pairs(shells) do
			if type(frame) == "table" and frame.GetName then
				local ok, name = pcall(frame.GetName, frame)
				name = ok and MelloUI.Safe.Text(name) or nil
				if name then
					RegisterNamed(name, frame)
				end
			end
		end
	end
end
if MelloUI.AddMoverSource then
	MelloUI:AddMoverSource(Candidates)
end

-- The addon's own ADDON_LOADED makes the lists (every module is in by then);
-- another's (a window loaded on demand) registers the candidates that have
-- a stored place (at login the AfterLogin walk does it)
local sweepFrame = CreateFrame("Frame")
sweepFrame:RegisterEvent("ADDON_LOADED")
Perf.SetScript(sweepFrame, "OnEvent", function(_, _, addon)
	if addon == MelloUI.name then
		Lists()   -- every file of the addon has run: every module is in
	elseif M.isEnabled and not MelloUI:LoggingIn() then
		RegisterStored()
	end
end)

-- A game window the kit dresses on its first show (the first-open rule:
-- most panels) is no candidate before that (Kit.shells), so neither walk
-- above finds it: one with a stored place registers as the kit dresses it
-- (the bus's 'shell', a player's action), and Core places it then and after
-- every layout of the game's -- its old place applies from its first show.
-- No frame is made. During the login the AfterLogin walk takes the ones
-- dressed by then.
MelloUI:On("shell", Perf.Shared("'shell' on the bus: a dressed window's stored place", function(frame)
	if not M.isEnabled or MelloUI:LoggingIn() or type(frame) ~= "table" or type(frame.GetName) ~= "function"
		or MelloUI:MoverEntry(frame) then
		return
	end
	local ok, name = pcall(frame.GetName, frame)
	name = ok and MelloUI.Safe.Text(name) or nil
	local db = name and MelloUI:GetModuleDB(M.name)
	local store = type(db) == "table" and db.positions
	if type(store) == "table" and store[name] ~= nil then
		RegisterNamed(name, frame)
	end
end), M)

-- Windows Fade In (user, 2026-09-23: "can we do that effect with all of the
-- UI elements that open, the character tab, backpack, talents, professions
-- tab etc?"): every window the game opens as a panel -- the ones it lists in
-- UIPanelWindows: character, talents and spells, professions, social, guild,
-- group finder, collections, map, game menu ... -- and every bag window fades
-- in when it opens, reskin on or off (Core/Anim.lua). Windows of addons the
-- game loads on demand join that list when they load, so the sweep runs again
-- on every ADDON_LOADED, before such a window's first show. Only the window's
-- alpha is touched, which the game allows on any window, in combat too; the
-- hooks are post-hooks and nothing is written onto the windows.
local fadeHooked = setmetatable({}, { __mode = "k" })
local EXTRA_WINDOWS = { "BankFrame", "SettingsPanel", "AddonList" }
for _, name in ipairs(BAG_WINDOWS) do
	EXTRA_WINDOWS[#EXTRA_WINDOWS + 1] = name
end

local function FadeOnShow(self)
	if M.isEnabled and M.db and M.db.fadeWindows and MelloUI.Anim
		and not (self.IsForbidden and self:IsForbidden()) then
		MelloUI.Anim:FadeIn(self, 0.2)
	end
end

local function HookFade(frame)
	if type(frame) ~= "table" or fadeHooked[frame] or not frame.HookScript then
		return
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end
	fadeHooked[frame] = true
	Perf.HookScript(frame, "OnShow", FadeOnShow)
end

local function SweepFade()
	if type(UIPanelWindows) == "table" then
		for name in pairs(UIPanelWindows) do
			if type(name) == "string" then
				HookFade(_G[name])
			end
		end
	end
	for _, name in ipairs(EXTRA_WINDOWS) do
		HookFade(_G[name])
	end
end

local fadeWatcher = CreateFrame("Frame")
fadeWatcher:RegisterEvent("PLAYER_LOGIN")
fadeWatcher:RegisterEvent("ADDON_LOADED")
Perf.SetScript(fadeWatcher, "OnEvent", SweepFade)

local function PanelWanted(db, name)
	return db.reskin ~= false and db[name] ~= false
end

-- During Core's start-up pass the driven modules must come up in TOC order
-- (Bar Textures before the unit frame panel, and so on): only their flags
-- are set then, and Core enables each in its turn; afterwards (a switch on
-- the page) they are switched at once.
local function Want(name, wanted)
	if MelloUI.initializingModules then
		MelloUI.db.enabled[name] = wanted and true or false
	else
		MelloUI:SetModuleEnabled(name, wanted)
	end
end

-- A folded feature's switch: on unless switched off (`off`: off unless
-- switched on; `always`: no switch)
function TweakWanted(db, tweak)
	if tweak.always then
		return true
	end
	local v = db["qol_" .. tweak[1]]
	if tweak.off then
		return v == true
	end
	return v ~= false
end

-- Is there anything at all for the umbrella to do? Every area and every
-- tweak switched off is a real choice (the window mover and the name format
-- work without the reskin), so it is never undone behind your back -- but it
-- is worth saying, because the switch then looks like it does nothing.
function NothingWanted(db)
	for _, area in ipairs(PANELS) do
		if db[area[1]] ~= false then
			return false
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		if not tweak.always and TweakWanted(db, tweak) then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Many areas at once (0.15.0): the Configurator's bulk writes (Copy from,
-- Apply to all, Reset this page) and Switch every area on. One page action
-- could switch up to 43 painted skins, each an art load and a skin, in one
-- frame. M:SetAreas(values), values = { [switch key] = true | false } over
-- the areas' and features' switches (AREA_OF: a panel's, the Quest Tracker's
-- own look switch, a feature's qol_ key; any other key is not its to write
-- and is passed by):
--   nothing would change: true, 0 (nothing written)
--   in combat, when a painted skin would switch (a panel's switch, the
--     Quest Tracker's own look): false, and NOTHING is written (the caller
--     prints M.areasRefused): the skins' apply paths were never checked
--     there, and nothing half-done is left waiting behind the player's back.
--     Features only (qol_ keys): as out of combat; their own rows switch
--     them in a fight as well
--   else: true, the number changed. The changed keys are written through
--     NotifySettingChanged in ONE Batch (the bus's 'setting' once per key,
--     at its end; one backup), their switching held back meanwhile
--     (OnSettingChanged); then the modules they drive are switched
--     AREAS_PER_FRAME a frame in the TOC's order (Bar Textures before the
--     unit frame panel, as Apply), each to what its switches want by then,
--     on a Kit:NextFrame chain. In a fight (one starting half-way) the
--     features at the front go on being switched; the first painted skin
--     and everything behind it (the TOC's order kept) wait for its end
--     (Kit:WhenOutOfCombat). With this module off nothing is switched
--     (Apply switched them all off with it).
-- Nothing runs while nothing waits: no frame, no ticker.
--------------------------------------------------------------------------------

local AREAS_PER_FRAME = 3
local AREAS_KEY = "UIModifications: areas"   -- (Kit:NextFrame's and Kit:WhenOutOfCombat's key)
-- holding: inside SetAreas' Batch (OnSettingChanged switches nothing);
-- pending: the module names still to switch, in order; queued[name] = true
-- while one waits there
local Areas = { holding = false, pending = {}, queued = {} }

-- a driven module that is a folded feature (switched in a fight as its own
-- row does), not a painted skin
local function IsFeature(name)
	local area = AREA_OF["qol_" .. name]
	return area ~= nil and area.tweak ~= nil
end

-- a switch as its module reads it (a feature's `off`: off until switched on)
local function AreaOn(db, key)
	local tweak = AREA_OF[key].tweak
	if tweak then
		return TweakWanted(db, tweak)
	end
	return db[key] ~= false
end

-- what a driven module is to be by now: off with this module off
local function AreaWanted(db, name)
	if not M.isEnabled then
		return false
	end
	if IsFeature(name) then
		return TweakWanted(db, AREA_OF["qol_" .. name].tweak)
	end
	return PanelWanted(db, name)
end

-- a few of the waiting modules switched (Kit:NextFrame's fn, handed its key;
-- Kit:WhenOutOfCombat's after a fight); the rest on the next frame. In a
-- fight only the features at the front: a painted skin, and all behind it,
-- waits for its end
function Areas.Step()
	local pending = Areas.pending
	if #pending == 0 then
		return
	end
	local fight = InCombatLockdown and InCombatLockdown()
	local db = MelloUI:GetModuleDB(M.name)
	for _ = 1, AREAS_PER_FRAME do
		local name = pending[1]
		if not name or (fight and not IsFeature(name)) then
			break
		end
		table.remove(pending, 1)
		Areas.queued[name] = nil
		MelloUI:SetModuleEnabled(name, AreaWanted(db, name))
	end
	if #pending == 0 then
		return
	elseif fight and not IsFeature(pending[1]) then
		Kit:WhenOutOfCombat(Areas.Step, AREAS_KEY)
	else
		Kit:NextFrame(AREAS_KEY, Areas.Step)
	end
end

-- the changed keys written, in one Batch (MelloUI:Batch's fn)
local function WriteAreas(keys, values)
	for i = 1, #keys do
		MelloUI:NotifySettingChanged(M.name, keys[i], values[keys[i]])
	end
end

function M:SetAreas(values)
	if type(values) ~= "table" then
		return true, 0
	end
	Lists()
	local db = MelloUI:GetModuleDB(M.name)
	-- the keys that change, in the registry's order; skin: one of them
	-- switches a painted skin (not a feature's qol_ key)
	local keys, wanted, drives, skin = {}, {}, {}, false
	local function Take(key)
		local v = values[key]
		if v ~= nil and AreaOn(db, key) ~= (v and true or false) then
			keys[#keys + 1] = key
			wanted[key] = v and true or false
			skin = skin or AREA_OF[key].tweak == nil
			local name = AREA_OF[key].name
			if name and MelloUI:GetModule(name) then
				drives[name] = true
			end
		end
	end
	for _, area in ipairs(PANELS) do
		Take(area[1])
	end
	for _, tweak in ipairs(TWEAKS) do
		if not tweak.always then
			Take("qol_" .. tweak[1])
		end
	end
	if #keys == 0 then
		return true, 0
	end
	if skin and InCombatLockdown and InCombatLockdown() then
		return false
	end
	Areas.holding = true
	local ok, err = pcall(MelloUI.Batch, MelloUI, WriteAreas, keys, wanted)
	Areas.holding = false
	if not ok then
		geterrorhandler()(err)
	end
	if M.isEnabled then
		local pending, queued = Areas.pending, Areas.queued
		for name in MelloUI:IterateModules() do
			if drives[name] and not queued[name] then
				queued[name] = true
				pending[#pending + 1] = name
			end
		end
		if #pending > 0 then
			Kit:NextFrame(AREAS_KEY, Areas.Step)
		end
	end
	return true, #keys
end

-- Every area and feature back on that is off (a feature off until switched
-- on stays as it is), for the Switch every area on button: through
-- M:SetAreas. Returns its answer: false in combat while a painted skin is
-- off, else true and how many were off.
function RestoreAreas(db)
	local values = {}
	for _, area in ipairs(PANELS) do
		if db[area[1]] == false then
			values[area[1]] = true
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		if not (tweak.off or tweak.always) and db["qol_" .. tweak[1]] == false then
			values["qol_" .. tweak[1]] = true
		end
	end
	return M:SetAreas(values)
end

function Apply(db, on)
	local wanted = {}
	for _, area in ipairs(PANELS) do
		local name = area[1]
		if MelloUI:GetModule(name) then
			wanted[name] = on and PanelWanted(db, name) or false
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		local name = tweak[1]
		if MelloUI:GetModule(name) then
			wanted[name] = on and TweakWanted(db, tweak) or false
		end
	end
	-- in TOC order on every path (Bar Textures before the unit frame panel
	-- when the umbrella is switched on from its tile as well, not only in
	-- Core's start-up pass; audit, 2026-09-22)
	for name in MelloUI:IterateModules() do
		if wanted[name] ~= nil then
			Want(name, wanted[name])
		end
	end
end

-- qol_Tweaks has no default any more (Tweaks has no switch, see Lists): a
-- saved one is dead data (the old default put `true` in every player's
-- settings) and, with no default to compare with, would travel in every
-- profile, share string, backup and bake. Only a false the fold (OnEnable)
-- has not read yet means something. Dropped at login (OnInit) and after a
-- profile load or the late settings (the bus's 'restart', below), with the
-- module on or off.
local function DropTweaksSwitch(db)
	if type(db) == "table" and (db.featuresFolded or db.qol_Tweaks ~= false) then
		db.qol_Tweaks = nil
	end
end

-- `unlock`, the old Unlock the Windows mode's switch (gone with Edit Layout,
-- 0.15.0), is dead data a profile, share string or backup from before may
-- still bring: never read, dropped at login (OnInit) and after a profile
-- load (the bus's 'restart', below), the module on or off, as qol_Tweaks.
-- The installer's NEVER list keeps a setup from writing it back.
local function DropUnlock(db)
	if type(db) == "table" then
		db.unlock = nil
	end
end

-- Dark Mode is off until switched on since 0.13.7 (a personal preference,
-- user, 2026-09-26); it was on unless switched off before. A player from
-- then (the fold below done) whose switch was never touched had it running:
-- theirs is written in as on, so nothing changes for them. A new player's
-- switch is written by the fold (off), so it is never nil after it.
local function KeepDarkMode(db)
	if type(db) == "table" and db.featuresFolded and db.qol_DarkMode == nil then
		db.qol_DarkMode = true
	end
end

-- The driven modules are hidden from the configurator; done once every
-- module is registered (this file loads before them, see the TOC).
function M:OnInit(db)
	Lists()   -- (made at the addon's ADDON_LOADED already)
	DropTweaksSwitch(db)   -- (before any profile is saved)
	DropUnlock(db)
	KeepDarkMode(db)
	for _, area in ipairs(PANELS) do
		local module = MelloUI:GetModule(area[1])
		if module then
			module.hidden = true
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		local module = MelloUI:GetModule(tweak[1])
		if module then
			module.hidden = true
		end
	end
end

-- The name form to the two modules and the engine's own-name cvar.
local SURNAME_CVAR = "UnitSurnameOwn"

local function HasCVar(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then
		return false
	end
	local ok, value = pcall(C_CVar.GetCVarInfo, name)
	return ok and value ~= nil
end

local function ApplyNameFormat(db, on)
	local mode = on and (db.nameFormat or "both") or "both"
	for _, name in ipairs({ "UnitFrames", "Nameplates" }) do
		local module = MelloUI:GetModule(name)
		if module then
			MelloUI:NotifySettingChanged(name, "nameFormat", mode)
		end
	end
	if HasCVar(SURNAME_CVAR) then
		if on then
			if db.savedSurnameOwn == nil then
				local ok, current = pcall(C_CVar.GetCVar, SURNAME_CVAR)
				db.savedSurnameOwn = (ok and current) and tostring(current) or "1"
			end
			pcall(C_CVar.SetCVar, SURNAME_CVAR, mode == "first" and "0" or "1")
		elseif db.savedSurnameOwn ~= nil then
			pcall(C_CVar.SetCVar, SURNAME_CVAR, db.savedSurnameOwn)
			db.savedSurnameOwn = nil
		end
	end
end

-- Preload Artwork (Kit:Preload): the kit's files while the reskin is on, the
-- class medallions with them; all let go when either is off or the module is.
local function ApplyPreload(db, on)
	if not (Kit and Kit.Preload) then
		return
	end
	local files = {}
	-- (the look held: the palette and the Kit Colours it was preloaded for)
	Tint.preloaded, Tint.preloadedColours = nil, nil
	if on and db.preloadArt ~= false and db.reskin ~= false then
		Tint.preloaded = MelloUI:PaletteId()
		Tint.preloadedColours = Kit.BorderValue and Kit:BorderValue("colours")
		files = Kit:KitFiles()
		local function Walk(t)
			for _, v in pairs(t) do
				if type(v) == "string" then
					files[#files + 1] = v
				elseif type(v) == "table" then
					Walk(v)
				end
			end
		end
		if type(MelloUI_ClassIcons) == "table" then
			Walk(MelloUI_ClassIcons)
		end
	end
	Kit:Preload(files)
end

-- The reskin's Edit Mode layout, answered (ApplyEditModeLayout's done, on a
-- later frame: the layout is fitted to this screen first, Core/LayoutFit.lua,
-- like the installer's). Put in: remembered. A FAIL is never put in -- a
-- screen too small for Mello's layout until the game's UI-scale fix, or
-- one whose settings do not fit it -- and Core/EditModeLayout.lua has said
-- so ("Your screen is too small for Mello's layout ..."): answered too, so
-- the next switch does not say it again (the installer and /mello layout
-- apply stay for later). Anything else (a fit dropped, no room in Edit
-- Mode, a save refused) is tried again on the next switch.
local function ReskinLayoutDone(ok, _, report)
	local db = MelloUI:GetModuleDB("UIModifications")
	if not db or db.layoutApplied then
		return
	end
	local failed = type(report) == "table" and report.pass == false and (report.cause == "size" or report.cause == "settings")
	if ok or failed then
		MelloUI:NotifySettingChanged(M.name, "layoutApplied", true)
	end
end

-- The reskin switched on by the user (the umbrella from its tile or the
-- reskin toggle; not Core's start-up pass): Custom Sounds comes on with it,
-- and the Edit Mode layout the reskin is drawn for is put in place once,
-- fitted to this screen (user, 2026-09-22: "if people enable the reskin, it
-- should only auto enable the full reskin and the custom sounds, but it
-- needs to load my current UI layout"; user, 2026-09-25: kept,
-- through the fitter, so a 16:9 screen never gets the raw 21:9 string).
-- Never while the installer applies a setup: it sets every switch, Custom
-- Sounds included, and puts its own fitted layout in. Never in a profile
-- load or a restart either (Core's restartingModules: the module comes on
-- again there with the reskin already on; a profile with Custom Sounds off
-- keeps it off, and no layout goes in).
local function ReskinOn(db)
	if MelloUI.initializingModules or MelloUI.restartingModules or not MelloUI.initialized or not db.reskin then
		return
	end
	local installer = MelloUI.Installer
	if type(installer) == "table" and installer.applying then
		return
	end
	if MelloUI:GetModule("CustomSounds") and not MelloUI:IsModuleEnabled("CustomSounds") then
		MelloUI:SetModuleEnabled("CustomSounds", true)
		MelloUI:Print("Custom Sounds switched on with the reskin.")
	end
	if not db.layoutApplied and MelloUI.ApplyEditModeLayout then
		-- (true at once while it is being fitted; the answer comes to
		-- ReskinLayoutDone. Refused now -- combat, Edit Mode open -- it is
		-- put in when that ends, and answered then)
		local ok, why = MelloUI:ApplyEditModeLayout(false, nil, ReskinLayoutDone)
		if not ok and type(why) == "string" and not why:find("no layout is baked", 1, true) then
			MelloUI:Print("Edit Mode layout: %s", why)
		end
	end
	if MelloUI.RefreshConfig then
		MelloUI:RefreshConfig()
	end
end

-- Reduce Motion: the animation engine finishes every tween and group at once.
-- An accessibility switch for the whole addon, not part of the reskin: it
-- follows the saved setting with this module on or off (Chat's smooth scroll
-- reads it, and the Fresh start profile turns this module off; audit,
-- 2026-09-24). Read at start-up (OnEnable, or OnDisable for a module that is
-- off), on a change and after a profile load; its switch is on the Look page.
local function ApplyMotion(db)
	if MelloUI.Anim and db then
		MelloUI.Anim:SetReduceMotion(db.reduceMotion)
	end
end

-- a change reaches OnSettingChanged, and a profile load OnEnable, only while
-- the module is on: the bus's 'setting' and 'restart' (fired at the end of
-- NotifySettingChanged and RestartModules, where the hooks on them ran;
-- audit, 2026-09-24, rank 5) reach it with the module off as well
MelloUI:On("setting", Perf.Shared("'setting' on the bus", function(name, key, value)
	if name ~= "UIModifications" then
		return
	elseif key == "reduceMotion" then
		ApplyMotion(MelloUI:GetModuleDB("UIModifications"))
	elseif key == "positions" then
		-- the whole store replaced (a profile, the installer: a new table;
		-- a place saved into it is the same table): its candidates on the
		-- next frame
		if M.isEnabled and value ~= registeredFrom then
			registeredFrom = value
			if Kit and Kit.NextFrame then
				Kit:NextFrame("UIModifications stored places", NewStore)
			else
				NewStore()
			end
		end
	elseif key == "palette" then
		-- (Core swaps the palette, the kit's art follows: 'border', then
		-- the one 'palette')
		MelloUI:SetPalette(value)
	elseif key == "kitColours" and M.isEnabled then
		Tint.KitColours()
	end
end), M)
-- The Kit Colours set inside a Batch (the installer's Install or Revert)
-- are applied here, once its held 'setting' goes out (OnSettingChanged
-- leaves them while it runs): with a palette held in the same Batch the
-- one switch takes both (MelloUI:SetPalette: one walk over the kit's
-- textures, one 'palette'), whichever of the two was set first. Outside a
-- Batch OnSettingChanged has applied them already: nothing is left here.
function Tint.KitColours()
	if not (Kit and Kit.ApplyBorder and Kit.BorderValue) then
		return
	end
	local stored = MelloUI:KnownPalette(M.db and M.db.palette)
	if stored ~= MelloUI:PaletteId() then
		MelloUI:SetPalette(stored)   -- (its walk reads the new Kit Colours as well)
		return
	end
	local applied = type(Kit.borderApplied) == "table" and Kit.borderApplied.colours or nil
	if applied ~= Kit:BorderValue("colours") then
		Kit:ApplyBorder("colours")
	end
end
-- The palette switched (or the Kit Colours): the preloaded art held for the
-- look now drawn (0.14.0: the last look's files stayed held, and the new
-- look's first draw came in late) -- only while the preload is on and the
-- look is another one than the one preloaded.
-- (a frame after the switch: the kit's own walk over its textures has the
-- switch's frame; asked again then, as a restart in between -- a profile
-- load's, whose OnEnable preloads -- may have made it for this look)
function Tint.LookMoved()
	if not (M.isEnabled and M.db and Tint.preloaded and Kit and Kit.BorderValue) then
		return false
	end
	return MelloUI:PaletteId() ~= Tint.preloaded or Kit:BorderValue("colours") ~= Tint.preloadedColours
end
function Tint.PreloadAgain()
	if Tint.LookMoved() then
		ApplyPreload(M.db, true)
	end
end
MelloUI:On("palette", Perf.Shared("'palette' on the bus", function()
	if Tint.LookMoved() then
		Kit:NextFrame("UIModifications preload", Tint.PreloadAgain)
	end
end), M)
MelloUI:On("restart", Perf.Shared("'restart' on the bus", function()
	local db = MelloUI:GetModuleDB("UIModifications")
	ApplyMotion(db)
	DropTweaksSwitch(db)
	DropUnlock(db)
end), M)

function M:OnEnable(db)
	self.db = db
	-- the borders moved here from the panels (one choice per kind for every
	-- window, 2026-09-23): the action bars' Button Border and the character
	-- window's progress bar look carry over, once
	if not db.bordersMigrated then
		local ab = MelloUI:GetModuleDB("ActionBarPanel")
		if ab and ab.buttonBorder then
			db.buttonBorder = ab.buttonBorder
		end
		local cp = MelloUI:GetModuleDB("CharacterPanel")
		if cp and cp.repBarBorder then
			db.barBorder = cp.repBarBorder
		end
		db.bordersMigrated = true
	end
	-- Buffs & Debuffs and Error Messages moved here from pages of their own,
	-- and Tweaks lost its switch (its rows each switch one thing; user,
	-- 2026-09-24): each keeps the state it had, once
	KeepDarkMode(db)   -- (before: a fold done now writes a new player's)
	if not db.featuresFolded then
		for _, tweak in ipairs(TWEAKS) do
			local key = "qol_" .. tweak[1]
			if tweak.off and db[key] == nil then
				db[key] = MelloUI.db.enabled[tweak[1]] == true
			end
		end
		if db.qol_Tweaks == false then
			local tw = MelloUI:GetModuleDB("Tweaks")
			if tw then
				tw.hideMicroMenu, tw.hideBagBar, tw.hideMinimapCoords, tw.chatNotices = false, false, false, false
				tw.worldTextScale = 1
			end
		end
		db.qol_Tweaks = nil
		db.featuresFolded = true
	end
	-- MelloUI's Quest Tracker has a kit switch of its own now (audit,
	-- 2026-09-24, rank 1); it wore the kit with the Objective tracker's until
	-- then, so it starts as that one is set, once, and no look changes. The
	-- flag is this player's own one-time step (in `keep`): profiles, share
	-- strings and the installer's setups never carry it, and loading one
	-- leaves it as it is (the macro backup keeps it). A profile saved since
	-- carries questTrackerKit itself when it is off; loading one saved
	-- before, which has no such key, leaves the switch at its default (on).
	if not db.questTrackerKitMigrated then
		db.questTrackerKit = db.TrackerPanel ~= false
		db.questTrackerKitMigrated = true
	end
	ApplyMotion(db)
	if db.reskin ~= false and NothingWanted(db) then
		MelloUI:Notice("UI Modifications is on, but every area of the reskin is switched off, so the game's own art is what you see. The Configurator's Look page has a \"Switch every area on\" button.")
	end
	Apply(db, true)
	-- the game's elements Edit Layout moves: the ones registered before put
	-- where the store now says (a profile's), then the ones with a stored
	-- place registered (Core places each): the four and the chat windows now,
	-- shown at once (no jump when the login is over), the rest once the
	-- login is over (at once after it)
	PlaceRegistered()
	RegisterStored("shown")
	MelloUI:AfterLogin(RegisterAllStored)
	registeredFrom = db.positions   -- (registered from it: its 'setting' at a Batch's end registers nothing again)
	ApplyNameFormat(db, true)
	ApplyPreload(db, true)
	ReskinOn(db)
end

function M:OnDisable(db)
	db = db or self.db or {}
	ApplyMotion(db)   -- kept: Reduce Motion is not the module's
	Apply(db, false)
	-- its game elements are not live any more (their `when`): an Edit
	-- Layout session lets go of each it holds, put back from its snapshot
	local session = MelloUI.LayoutSession
	if type(session) == "table" and session.Holds and session.Drop then
		for entry in pairs(mine) do
			if session.Holds(entry) then
				session.Drop(entry)
			end
		end
	end
	ApplyNameFormat(db, false)
	ApplyPreload(db, false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if Areas.holding and AREA_OF[key] then
		return   -- (M:SetAreas: switched a few a frame once its Batch is over)
	elseif key == "reduceMotion" then
		return   -- applied from the bus's 'setting', module on or off
	elseif key == "questTrackerKit" or key == "questTrackerKitMigrated" then
		-- read live by Kit:IsOn("questTracker"), which looks again on the
		-- bus's 'setting' of this module (and tells 'look:questTracker')
		return
	elseif key == "palette" then
		return   -- applied from the bus's 'setting', module on or off (MelloUI:SetPalette)
	elseif key == "uiShade" or key == "uiShadeStrength" or key:sub(1, 6) == "shade_" then
		return   -- the UI shade: applied from the bus's 'setting', module on or off (Modules/KitShade.lua)
	elseif key:sub(1, 10) == "parchment_" then
		if MelloUI.Kit and MelloUI.Kit.SetParchment then
			MelloUI.Kit:SetParchment(key:sub(11), value and true or false)
		end
		return
	elseif MelloUI.Kit and MelloUI.Kit.borderKinds then
		for _, k in ipairs(MelloUI.Kit.borderKinds) do
			if key == k.key then
				-- (the Kit Colours in a Batch: at its end, with a palette
				-- set in it, Tint.KitColours)
				if not (k.kind == "colours" and MelloUI.InBatch and MelloUI:InBatch()) then
					MelloUI.Kit:ApplyBorder(k.kind)
				end
				return
			end
		end
	end
	-- (autoSnap and snapTargets: Edit Layout's, read when it snaps;
	-- positions: Core's store, the bus's 'setting' above)
	if key == "autoSnap" or key == "snapTargets" or key == "positions" or key == "layoutApplied" or key == "welcomeAsked"
		or key == "savedSurnameOwn" or key == "featuresFolded" then
		return
	elseif key == "nameFormat" then
		ApplyNameFormat(db, true)
		return
	elseif key == "preloadArt" then
		ApplyPreload(db, true)
		return
	elseif key == "reskin" then
		Apply(db, true)
		ApplyPreload(db, true)
		if value then
			ReskinOn(db)
		end
	elseif key:sub(1, 4) == "qol_" then
		local name = key:sub(5)
		if MelloUI:GetModule(name) then
			MelloUI:SetModuleEnabled(name, value and true or false)
		end
	elseif MelloUI:GetModule(key) then
		MelloUI:SetModuleEnabled(key, PanelWanted(db, key))
	end
end
