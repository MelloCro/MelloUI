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
-- The LIST of the game's elements Edit Layout moves (its windows, the
-- undocked chat windows, and the minimap, the chat, the objective tracker
-- and the damage meter that Edit Mode places too) and their registration
-- with Core's one mover registry are Core/EditLayoutWindows.lua's (onelook
-- D2: in the core, so they move with every kit panel off). This module keeps
-- the one store (`positions`: Core's, unchanged key), Edit Layout's snap
-- settings, and the switch that makes them live (this module on: onelook
-- D6), and hands its OnEnable, its OnDisable and another addon's
-- ADDON_LOADED to that file. The moving itself is Edit Layout's
-- (Core/EditLayout.lua and its files); the old Unlock the Windows mode, its
-- grab strips and its provider of Core's mover are gone.
--
-- (onelook D9) The settings in two parts of the one module, every saved key
-- and option id ("UIModifications.<key>") as it was, so profiles, share
-- strings, the macro backup and the installer read them as before:
--   the core: the palette, the UI shade and its areas, the parchment of
--     MelloUI's own parts (the Quest Tracker, the chat, the whisper popup,
--     the damage meter), Windows Fade In, Reduce Motion, Show Names As,
--     Class Coloured Names, Edit Layout's snap and the store of places, the
--     core border kinds (Cooldown Manager Border), the one switching engine
--     of the areas and features (Lists, M:SetAreas, Apply), and the contract
--     a part extends a core module's settings by (MelloUI.ModuleParts,
--     M:AddPart: Dark Mode's Reskin Brightness takes the same)
--   the painted reskin's part, the OLDSCHOOL block at the end of this file
--     (MelloUI_Oldschool at stage I): its switch and Preload Artwork, Switch
--     every area on, the Kit Colours and the other border kinds, Raid Border
--     Placement, the game windows' parchment sheets and Parchment Style; the
--     panel switches' gate (PanelsOff) and their rows' `requires`, the
--     preload, the layout put in with the reskin, and its one-time steps.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("UIModifications")
-- the kit (Modules/Kit.lua, loaded before this file: see the TOC)
local Kit = MelloUI.Kit
-- ONELOOK HEADER END (an OLDSCHOOL block below may use only the locals above and public tables)
-- the game's elements Edit Layout moves (Core/EditLayoutWindows.lua, loaded
-- before this file; onelook D2): each use nil-guarded
local GW = MelloUI.EditLayoutWindows

-- The reskin's switches (the kit panels) and the folded features come from
-- the module registry (audit, 2026-09-24, rank 4: they were hand lists here,
-- beside the configurator's icons, and had drifted from the modules). Each
-- kit panel gives its row as `window` in its RegisterModule, each folded
-- feature as `tweak` (Core's header):
--   window  { label, desc, tab = "Windows" | "HUD", order, addon,
--             firstOpen, include } (its frames that move in Edit Layout:
--             Core/EditLayoutWindows.lua's list since onelook D2)
--   tweak   { label, desc, order, off, always }
--   order   rows with one lead their list (their tab), lowest first; the
--           rest follow in the TOC's order
--   include (not read here since 0.15.0: Core/ConfigLayout.lua places every
--           option of a panel, on its element's page)
-- (one look, stage E, the user 2026-10-15: a window row's `switch` -- the
-- look switch of one of MelloUI's own windows, the Quest Tracker's
-- questTrackerKit alone -- went with that switch)
-- Made into the lists the code below reads, in the registry's order:
--   PANELS  { module name, label, description, tab = }
--   TWEAKS  { module name, label, description, off =, always = }, each
--           switched by `qol_<name>` here (`off`: off until switched on, as
--           the module was before it moved here; `always`: no switch, its
--           rows each switch one thing)
--   AREA_OF [switch key] = { name = the module it switches, tweak = its
--           TWEAKS row (a feature's) }: every area's and feature's switch
--           (M:SetAreas writes only these)
-- This file loads before those modules (see the TOC), so the lists, the
-- switches' defaults and their definitions are made once every module is
-- in: at the addon's own ADDON_LOADED, before the saved settings are read
-- (Lists, by the sweep below).
local PANELS, TWEAKS, AREA_OF = {}, {}, {}

-- Flags without option rows: welcomeAsked, the first login was handled (the
-- installer's login check, Core/Installer.lua); seenVersion, the version
-- whose one What's new line was given; layoutApplied, the Edit Mode layout
-- was put in place once when the reskin came on (ReskinOn below) or the
-- installer answered for it; layoutFitFor, layoutFitRev and
-- layoutAsked_<character>, the installer's own facts. The switching
-- functions are defined further down, next to the rest of the switching;
-- declared here so the code above them can reach them.
local Apply, TweakWanted

-- A bulk switch of painted skins refused in combat (M:SetAreas): the line
-- its callers print
local AREAS_REFUSED = "Not in combat: this would switch painted skins."

local defaults, options = { fadeWindows = true, reduceMotion = false,
	parchment_questTracker = false, parchment_chat = false, parchment_whisper = false, parchment_meter = false,
	autoSnap = true, snapGap = 0, positions = {}, welcomeAsked = false, layoutApplied = false, nameFormat = "both", classNames = true,
	-- the palette (0.14.0): an id of MelloUI.Palettes, applied by Core
	-- (MelloUI:SetPalette; this module on or off); a choice, not personal
	palette = "ember" }, {}
-- Edit Layout's (0.15.0): `positions` is Core's one store of places, and
-- `autoSnap` its bar's Snap switch, `snapGap` (0.19.9) its Gap (the pixels
-- kept between elements snapped side by side, 0 - 10); `snapTargets` ({ [key] = "screen" |
-- "grid" | "off" | another element's key }, nil: the nearest element) is
-- no default (read as {}): profiles carry it, the installer never sets it
-- (the core border kinds, `core`: the Cooldown Manager Border; the painted
-- reskin's part brings the others' defaults)
for _, k in ipairs(MelloUI.Kit and MelloUI.Kit.borderKinds or {}) do
	if k.core then
		defaults[k.key] = k.default
	end
end
-- the UI shade (0.14.0, Modules/KitShade.lua, which loads before this file
-- and switches it from the bus's 'setting'): on at 70 %, every area on
-- (user, 2026-09-26; each area's default with its switch, ShadeRow below)
do
	local shade = Kit and Kit.shadeSettings
	if type(shade) == "table" and type(shade.master) == "string" then
		defaults[shade.master], defaults[shade.strength] = true, shade.default
	end
end
-- (each area's and feature's switch is added to these by Lists, below)

--------------------------------------------------------------------------------
-- Parts (onelook D9): the one way a part of MelloUI that is not a module of
-- its own -- the painted reskin's settings, MelloUI_Oldschool from stage I --
-- extends a core module's settings: the same module, its saved keys and its
-- option ids ("<Module>.<key>"), so profiles, share strings, the backup and
-- the installer read them as before. One contract for every core module that
-- takes one (UI Modifications, Dark Mode):
--   module:AddPart(part) -> part   (= MelloUI.ModuleParts.Add(module, part))
--       part.defaults copied into the module's defaults; part.options put
--       into its options: an option with `after` / `before` (another
--       option's key) right after / before it, the ones after it following
--       on; with neither, at the end (the fields are taken off the option).
--       The part is kept, in order, on module.parts
--   MelloUI.ModuleParts.Run(module, hook, ...) -> true when a part's
--       part[hook](...) answered true (the rest not asked), else false
-- The hooks are the module's to ask (its OnEnable, OnSettingChanged ...); a
-- part's bus listeners have an owner of their own (the part), never the
-- module: Core's MelloUI:On replaces a listener of the same owner and topic.
--------------------------------------------------------------------------------
local Parts = {}
MelloUI.ModuleParts = Parts

function Parts.Add(module, part)
	if type(module) ~= "table" or type(part) ~= "table" then
		return nil
	end
	local list = rawget(module, "parts")
	if not list then
		list = {}
		module.parts = list
	end
	list[#list + 1] = part
	local into, opts = module.defaults, module.options
	for k, v in pairs(type(part.defaults) == "table" and part.defaults or {}) do
		into[k] = v
	end
	local at = nil
	for _, opt in ipairs(type(part.options) == "table" and part.options or {}) do
		local after, before = opt.after, opt.before
		opt.after, opt.before = nil, nil
		if after ~= nil or before ~= nil then
			at = nil
			for i, o in ipairs(opts) do
				if o.key ~= nil and o.key == (after or before) then
					at = after ~= nil and i + 1 or i
					break
				end
			end
		end
		at = at or #opts + 1
		table.insert(opts, at, opt)
		at = at + 1
	end
	return part
end

function Parts.Run(module, hook, ...)
	local list = type(module) == "table" and rawget(module, "parts")
	for i = 1, list and #list or 0 do
		local fn = list[i][hook]
		if type(fn) == "function" and fn(...) then
			return true
		end
	end
	return false
end

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

-- (the painted reskin's switch, Preload Artwork and Switch every area on
-- lead the list: its part puts them before the palette)

-- The palette (0.14.0): Core applies it (MelloUI:SetPalette), this module on
-- or off; its choices are the widget set's one list, every palette by its
-- name (W.PaletteValues)
do
	-- (no widget set: a file an update added, loaded only after a restart;
	-- the Configurator stands down until then)
	local W = MelloUI.Widgets
	Add({ type = "dropdown", key = "palette", name = "Palette", free = true,
		values = type(W) == "table" and type(W.PaletteValues) == "function" and W.PaletteValues() or {},
		desc = "The colours of MelloUI's look: its own windows and parts and all of the reskin's art. Your choice applies at once." })
end

-- The borders, one choice per kind for every window (Kit.borderKinds; the
-- kit applies a choice: OnSettingChanged below): the core kinds' (`core`,
-- the Cooldown Manager Border) here; the Kit Colours and the painted
-- reskin's other kinds are its part's, put in where each kind stands
-- (stages C / E / H: the core rows' `requires = "reskin"` goes)
for _, k in ipairs(MelloUI.Kit and MelloUI.Kit.borderKinds or {}) do
	if k.core then
		Add({ type = "dropdown", key = k.key, name = k.name, values = k.values, desc = k.desc,
			requires = "reskin", new = k.new })
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
			desc = "How dark the UI Shade round the kit's outlines is, the nameplates' Whole plate shade too. The bands behind unit frame and nameplate names keep their own." })
	end
end
-- An area's default (on) and its switch, once per area (Kit:AddShadeArea,
-- onelook D11: an area the painted reskin, or a later file, registers after
-- this file loaded gets its row at the next listing, Lists below). The
-- nameplates' area has no switch here: Nameplates > Name Shade's Whole plate
-- is it (0.16.0)
local shadeRowOf = {}   -- [area key] = true: its default and switch made
local function ShadeRow(a)
	local shade = Kit and Kit.shadeSettings
	if type(a) ~= "table" or type(a.key) ~= "string" or shadeRowOf[a.key] or type(shade) ~= "table"
		or type(shade.master) ~= "string" then
		return
	end
	shadeRowOf[a.key] = true
	if a.noSwitch then
		return
	end
	defaults[a.key] = true
	if type(shade.strength) == "string" then
		Add({ type = "toggle", key = a.key, name = "Shade: " .. a.label, requires = shade.master, free = true, new = a.new,
			desc = "The UI Shade round the " .. a.label:lower() .. ". Off: no shade there; the other areas keep theirs." })
	end
end
local function ShadeRows()
	for _, a in ipairs(Kit and type(Kit.shadeAreas) == "table" and Kit.shadeAreas or {}) do
		ShadeRow(a)
	end
end
ShadeRows()

-- The parchment sheets (the kit's, Kit:SetParchment; the text on them in
-- dark ink): one switch per area. The list is the installer's too (its
-- Fresh start lists the same areas, one list: read only). An area with
-- `values` is a choice instead, its "off" the switch's off (Kit:ParchmentOn
-- reads either), `on` the choice an older switch's true stands for. The
-- core's are the sheets of MelloUI's own parts; the painted reskin's part
-- puts the game windows' in (the objective tracker first, the character
-- window, the tooltips and the dialogs after these), so the list keeps its
-- order.
local PARCHMENTS = {
	{ "parchment_questTracker", "Quest Tracker" },
	{ "parchment_chat", "Chat" },
	{ "parchment_whisper", "Whisper Popup" },
	{ "parchment_meter", "Damage Meter" },
}
MelloUI.ParchmentAreas = PARCHMENTS
local PARCHMENT_DESC = {
	parchment_questTracker = "MelloUI's Quest Tracker on a parchment sheet, its text in dark ink. Works with the reskin on or off.",
	parchment_chat = "The chat on a parchment sheet, its text in dark ink: the Minimal Chat View and its whisper window with the reskin on or off; the game's chat windows with the painted chat (its Painted Skin, the reskin on).",
	parchment_whisper = "The whisper popup on a parchment sheet, its text in dark ink.",
	parchment_meter = "The damage meter on a parchment sheet, its text in dark ink.",
}
for _, entry in ipairs(PARCHMENTS) do
	-- (one look, Kit.ownParchments: the paper of a part of MelloUI's own -- the Quest Tracker's, the chat's -- is live
	-- whatever the reskin, and with this module off: `free`, applied from the bus's 'setting' below)
	local own = Kit and type(Kit.ownParchments) == "table" and Kit.ownParchments[entry[1]:sub(11)] or nil
	Add({ type = entry.values and "dropdown" or "toggle", key = entry[1], name = "Parchment: " .. entry[2], values = entry.values,
		requires = not own and "reskin" or nil, free = own, new = entry.new, desc = PARCHMENT_DESC[entry[1]] })
end

Add({ type = "toggle", key = "fadeWindows", name = "Windows Fade In",
	desc = "Every window fades in over a fifth of a second when it opens, instead of appearing at once: the character window, talents and spells, professions, the bags, social, guild, group finder, collections, the map, the game menu and the rest. Works with the reskin on or off. Reduce Motion: at once." })
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
-- switch, read by both as saved; it acts only while Chat Tweaks and Tooltip
-- Tweaks run, so not with UI Modifications off: options audit, 2026-10-05)
Add({ type = "toggle", key = "classNames", name = "Class Coloured Names", free = true,
	desc = "Players' names in their class colour: in every chat type (the game's own setting for it) and in the tooltip. On the parchment sheet a chat name is in dark ink with a gem in its class colour before it instead. It works through Chat Tweaks and Tooltip Tweaks: with UI Modifications off (or one of the two), the names there keep the game's own colours." })

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
	-- (user, 2026-09-26: no profile carries it). (questTrackerKitMigrated:
	-- the removed Painted Skin's one-time flag, one look stage E 2026-10-15 --
	-- old saves, snapshots and share strings carry it: it must never travel)
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
-- (onelook D9) the parts extending these settings (Parts above: the painted
-- reskin's, the OLDSCHOOL block at the end of this file)
M.AddPart = Parts.Add

-- the panel rows' requirement: the first part's that names one (the painted
-- reskin's switch); none without a part
local function PanelRequires()
	for _, part in ipairs(rawget(M, "parts") or {}) do
		if part.panelRequires ~= nil then
			return part.panelRequires
		end
	end
	return nil
end

-- The lists made from the registry (PANELS, TWEAKS and AREA_OF: see the
-- top), the switches' defaults and their definitions: at the addon's own
-- ADDON_LOADED, when every module of MelloUI's is in (the sweep's event,
-- below), so the defaults are
-- complete before Core reads the saved settings against them at login;
-- OnInit makes sure of it. (0.19.9, split-addons) A module registered after
-- that -- a feature of its own addon (Chat, MelloUI_Chat), whose files the
-- game runs after MelloUI's ADDON_LOADED -- joins at its addon's
-- ADDON_LOADED (the sweep), at the latest at OnInit: each call lists the
-- modules not listed yet and sorts PANELS and TWEAKS again with them (the
-- user's in-game error, 2026-10-09: "no option 'UIModifications.qol_Chat'").
local listedModule = {}                    -- [module] = true: in the lists
local panelEntries, tweakEntries = {}, {}  -- the lists' entries, kept for that sort
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
	ShadeRows()   -- (an area registered since: its default and its switch)
	local new = nil   -- [row] = true: the rows of modules listed in this call
	for at, module in ipairs(MelloUI:ModulesInOrder()) do
		if not listedModule[module] then
			listedModule[module] = true
			local w, t = module.window, module.tweak
			if w and w.label then
				local e = { at = at, tab = TAB_RANK[w.tab] or 3, order = type(w.order) == "number" and w.order or math.huge,
					row = { module.name, w.label, w.desc or "", tab = w.tab } }
				panelEntries[#panelEntries + 1] = e
				new = new or {}
				new[e.row] = true
			end
			if t and t.label then
				local e = { at = at, tab = 0, order = type(t.order) == "number" and t.order or math.huge,
					row = { module.name, t.label, t.desc or "", off = t.off and true or nil, always = t.always and true or nil } }
				tweakEntries[#tweakEntries + 1] = e
				new = new or {}
				new[e.row] = true
			end
		end
	end
	if not new then
		return
	end
	InOrder(panelEntries, PANELS)
	InOrder(tweakEntries, TWEAKS)
	for _, area in ipairs(PANELS) do
		if new[area] then
			defaults[area[1]] = true
		end
	end
	-- (an `always` tweak has no switch, so no default either: Everything
	-- Off (Core's FreshProfileText) would write its qol_ key as false, and
	-- the one-time fold in OnEnable would take that for a switched-off
	-- Tweaks and reset its rows)
	for _, tweak in ipairs(TWEAKS) do
		if new[tweak] and not (tweak.off or tweak.always) then
			defaults["qol_" .. tweak[1]] = true
		end
	end
	-- each area's and feature's switch, defined after the module's own (the
	-- same table the configurator was given): a panel's needs the reskin (its
	-- part's switch, PanelRequires), a feature's works with it on or off
	for _, area in ipairs(PANELS) do
		if new[area] then
			AREA_OF[area[1]] = { name = area[1] }
			Add({ type = "toggle", key = area[1], name = area[2], desc = area[3], requires = PanelRequires() })
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		if new[tweak] and not tweak.always then
			AREA_OF["qol_" .. tweak[1]] = { name = tweak[1], tweak = tweak }
			Add({ type = "toggle", key = "qol_" .. tweak[1], name = tweak[2], desc = tweak[3] })
		end
	end
end

-- The addon's own ADDON_LOADED makes the lists (every module of MelloUI's is
-- in by then), a feature addon's adds its modules to them (0.19.9, Lists);
-- another's (a window loaded on demand) is handed to
-- Core/EditLayoutWindows.lua, which registers its candidates that have a
-- stored place (at login the AfterLogin walk does it). No frame of its own:
-- the sweep's frame stays the one event frame.
local function FeatureAddon(addon)
	for _, f in pairs(MelloUI.Features or {}) do
		if f.addon == addon then
			return true
		end
	end
	return false
end

local sweepFrame = CreateFrame("Frame")
sweepFrame:RegisterEvent("ADDON_LOADED")
Perf.SetScript(sweepFrame, "OnEvent", function(_, _, addon)
	if addon == MelloUI.name or FeatureAddon(addon) then
		Lists()   -- every file of the addon has run: its modules are in
	elseif GW and GW.AddonLoaded then
		GW.AddonLoaded()   -- (this module on and the login over: checked there)
	end
end)

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
-- (the game's bag windows: Core/EditLayoutWindows.lua's one list of them)
for _, name in ipairs(GW and GW.BAG_WINDOWS or {}) do
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

-- a panel (a painted skin) wanted: its switch on, and no part holding the
-- panels off (the painted reskin's part: its switch off)
local function PanelWanted(db, name)
	return not Parts.Run(M, "PanelsOff", db) and db[name] ~= false
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
-- is worth saying, because the switch then looks like it does nothing (the
-- painted reskin's part says it as the module comes on).
function M.NothingWanted(db)
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
-- the areas' and features' switches (AREA_OF: a panel's, a feature's qol_
-- key; any other key is not its to write and is passed by):
--   nothing would change: true, 0 (nothing written)
--   in combat, when a painted skin would switch (a panel's switch): false,
--     and NOTHING is written (the caller
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
-- off, else true and how many were off. (the button is the painted reskin's
-- part's)
function M.RestoreAreas(db)
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
-- (the painted reskin's part switches every area again as its switch moves)
M.ApplyAreas = Apply

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
	elseif key == "palette" then
		-- (Core swaps the palette, the kit's art follows: 'border', then
		-- the one 'palette')
		MelloUI:SetPalette(value)
	elseif key:sub(1, 10) == "parchment_" and not M.isEnabled then
		-- (one look) the paper of a part of MelloUI's own (Kit.ownParchments: the Quest Tracker's, the chat's), live
		-- with this module off too; OnSettingChanged switches every area while it is on
		local area = key:sub(11)
		if Kit and type(Kit.ownParchments) == "table" and Kit.ownParchments[area] and Kit.SetParchment then
			Kit:SetParchment(area, Kit.ParchmentValueOn(value))
		end
	end
end), M)
MelloUI:On("restart", Perf.Shared("'restart' on the bus", function()
	local db = MelloUI:GetModuleDB("UIModifications")
	ApplyMotion(db)
	DropTweaksSwitch(db)
	DropUnlock(db)
end), M)

-- (0.21.3; the user, 2026-10-13: "dont we have the option to "Preload" the UI
-- assets on the loading screen?") the files asked for in the login's own
-- frame, while the loading screen is up -- since the start-up pass (0.19.8)
-- this module comes on after it; OnEnable asks again for the same files (the
-- painted reskin's part's preload: its LoginFrame)
function M:OnLoginFrame(db)
	self.db = db   -- (Kit:BorderValue reads it, and keeps its first answer)
	Parts.Run(M, "LoginFrame", db)
end

-- (onelook D9) the parts asked as the module comes on: Migrate first (their
-- one-time steps), Enabled last (the painted reskin's: the 'every area is
-- off' notice, its preload, the layout put in with it); Disabled as it goes
function M:OnEnable(db)
	self.db = db
	Parts.Run(M, "Migrate", db)
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
	ApplyMotion(db)
	Apply(db, true)
	-- the game's elements Edit Layout moves (Core/EditLayoutWindows.lua): the
	-- registered ones placed from the store, the stored ones registered (the
	-- four and the chat windows now, the rest after the login)
	if GW and GW.OnEnable then
		GW.OnEnable(db)
	end
	ApplyNameFormat(db, true)
	Parts.Run(M, "Enabled", db)
end

function M:OnDisable(db)
	db = db or self.db or {}
	ApplyMotion(db)   -- kept: Reduce Motion is not the module's
	Apply(db, false)
	-- the game's elements Edit Layout moves are not live any more (their
	-- `when`): an Edit Layout session lets go of each it holds
	-- (Core/EditLayoutWindows.lua)
	if GW and GW.OnDisable then
		GW.OnDisable()
	end
	ApplyNameFormat(db, false)
	Parts.Run(M, "Disabled", db)
end

-- (onelook D9) a part's settings first (its Setting answers true for a key it
-- applied: the painted reskin's switch, Preload Artwork, the Kit Colours and
-- its border kinds, Raid Border Placement, Parchment Style, the Quest
-- Tracker's old look switch); the core's below
function M:OnSettingChanged(key, value, db)
	self.db = db
	if Areas.holding and AREA_OF[key] then
		return   -- (M:SetAreas: switched a few a frame once its Batch is over)
	elseif Parts.Run(M, "Setting", key, value, db) then
		return
	elseif key == "reduceMotion" then
		return   -- applied from the bus's 'setting', module on or off
	elseif key == "palette" then
		return   -- applied from the bus's 'setting', module on or off (MelloUI:SetPalette)
	elseif key == "uiShade" or key == "uiShadeStrength" or key:sub(1, 6) == "shade_" then
		return   -- the UI shade: applied from the bus's 'setting', module on or off (Modules/KitShade.lua)
	elseif key:sub(1, 10) == "parchment_" then
		-- (a switch, or a choice whose "off" is off: the character window's,
		-- 0.19.4, read by Kit.ParchmentValueOn)
		local kit = MelloUI.Kit
		if kit and kit.SetParchment then
			kit:SetParchment(key:sub(11), kit.ParchmentValueOn and kit.ParchmentValueOn(value) or value == true)
		end
		return
	elseif MelloUI.Kit and MelloUI.Kit.borderKinds then
		-- (the core kinds: the Cooldown Manager Border)
		for _, k in ipairs(MelloUI.Kit.borderKinds) do
			if key == k.key and k.core then
				MelloUI.Kit:ApplyBorder(k.kind)
				return
			end
		end
	end
	-- (autoSnap, snapGap and snapTargets: Edit Layout's, read when it snaps;
	-- positions: Core's store, the bus's 'setting' in Core/EditLayoutWindows.lua)
	if key == "autoSnap" or key == "snapGap" or key == "snapTargets" or key == "positions" or key == "layoutApplied" or key == "welcomeAsked"
		or key == "savedSurnameOwn" or key == "featuresFolded" then
		return
	elseif key == "nameFormat" then
		ApplyNameFormat(db, true)
		return
	elseif key:sub(1, 4) == "qol_" then
		local name = key:sub(5)
		if MelloUI:GetModule(name) then
			MelloUI:SetModuleEnabled(name, value and true or false)
		end
	elseif MelloUI:GetModule(key) then
		MelloUI:SetModuleEnabled(key, PanelWanted(db, key))
	end
end

-- OLDSCHOOL BEGIN: the painted reskin's settings -- its switch, Preload Artwork, Switch every area on, the Kit Colours
-- and its border kinds, Raid Border Placement, the game windows' parchment sheets and Parchment Style -- a part of UI
-- Modifications' (M:AddPart: the same module, keys and option ids). Moves to MelloUI_Oldschool at stage I; it uses only
-- the header's locals and public tables.
do
local UM = MelloUI:GetModule("UIModifications")
-- the part (filled below), and the owner of its bus listeners: never the
-- module, whose own 'setting' listener a second one of the same owner would
-- replace (Core's MelloUI:On: Reduce Motion and the palette would be lost)
local part = {}

-- The look's own state (below): the Kit Colours set inside a Batch applied
-- at its end (Tint.KitColours), the preloaded art held for the look now
-- drawn (Tint.preloaded, Tint.preloadedColours, Tint.LookMoved,
-- Tint.PreloadAgain)
local Tint = {}

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
		MelloUI:NotifySettingChanged(UM.name, "layoutApplied", true)
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

-- The Kit Colours set inside a Batch (the installer's Install or Revert)
-- are applied here, once its held 'setting' goes out (the part's Setting
-- leaves them while it runs): with a palette held in the same Batch the
-- one switch takes both (MelloUI:SetPalette: one walk over the kit's
-- textures, one 'palette'), whichever of the two was set first. Outside a
-- Batch the part's Setting has applied them already: nothing is left here.
function Tint.KitColours()
	if not (Kit and Kit.ApplyBorder and Kit.BorderValue) then
		return
	end
	local stored = MelloUI:KnownPalette(UM.db and UM.db.palette)
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
	if not (UM.isEnabled and UM.db and Tint.preloaded and Kit and Kit.BorderValue) then
		return false
	end
	return MelloUI:PaletteId() ~= Tint.preloaded or Kit:BorderValue("colours") ~= Tint.preloadedColours
end
function Tint.PreloadAgain()
	if Tint.LookMoved() then
		ApplyPreload(UM.db, true)
	end
end

-- The Kit Colours' shown choice: the Kit Colours' choices are the palette in
-- use's (Kit.colourLooks, the same table filled again on a switch), and the
-- one shown is the one the kit draws: a Bronze kept from Ember shows, under
-- another palette, as that palette's own kit (Kit:ColourLookShown, the kit's
-- one answer)
local function ColoursShown(db)
	local K = MelloUI.Kit   -- (looked up now: the kit a world has when it is asked)
	local look = K and K.ColourLookShown and K:ColourLookShown()
	if look then
		return look.value
	end
	return db and db.kitColours
end

-- The game windows' parchment sheets (the list's other half: the core's are
-- MelloUI's own parts'). The character window's (0.19.4, the options audit:
-- Window Background's Parchment folded in, one control) is a choice, its
-- right pane's sheet or the whole window's (Modules/CharacterPanel.lua; an
-- older save carried by MelloUI:MergeSettings), `on` the choice an older
-- switch's true stands for
local CHARACTER_PARCHMENT = {
	{ value = "off", label = "Off" },
	{ value = "pane", label = "Right pane" },
	{ value = "window", label = "Whole window" },
}
local SHEET_FIRST = { "parchment_tracker", "Objective Tracker" }
local SHEETS_AFTER = {
	{ "parchment_character", "Character Window", values = CHARACTER_PARCHMENT, on = "pane" },
	{ "parchment_tooltip", "Tooltips" },
	{ "parchment_dialog", "Dialogs" },     -- (user, 2026-09-24: the popup dialogs, "add a parchment to it")
}
local SHEET_DESC = {
	parchment_tracker = "The game's objective tracker on a parchment sheet, its text in dark ink.",
	parchment_character = "The character window on a parchment sheet, its text in dark ink: Right pane lays it under the right pane (the stats, reputation, skills and the other lists); Whole window over the whole window inside its frame, the window's own stone round its edge. Off: no parchment; the window shows its Window Background (Windows > Character window).",
	parchment_tooltip = "The tooltips on a parchment sheet, their text in dark ink.",
	parchment_dialog = "The popup dialogs, the colour picker, ready checks and split stack on a parchment sheet, their text in dark ink.",
}
do
	local list = MelloUI.ParchmentAreas
	if type(list) == "table" then
		table.insert(list, 1, SHEET_FIRST)
		for _, entry in ipairs(SHEETS_AFTER) do
			list[#list + 1] = entry
		end
	end
end
local function SheetOption(entry, where)
	local opt = { type = entry.values and "dropdown" or "toggle", key = entry[1], name = "Parchment: " .. entry[2],
		values = entry.values, requires = "reskin", new = entry.new, desc = SHEET_DESC[entry[1]] }
	for k, v in pairs(where or {}) do
		opt[k] = v
	end
	return opt
end

-- The settings: the defaults, and the options where each stood in the list
-- (`after` / `before`: M:AddPart's anchors)
part.defaults = { reskin = true, preloadArt = true, raidBorderPlace = "both", parchment_tracker = false,
	parchment_character = "off", parchment_tooltip = false, parchment_dialog = false, parchmentStyle = "paper" }
local opts = {}
opts[#opts + 1] = { type = "toggle", key = "reskin", name = "Painted Kit Reskin", important = true, before = "palette",
	desc = "The game's windows and HUD dressed in the painted kit, and the frame of MelloUI's own windows. Off: the game's windows and HUD keep the game's own art; MelloUI's own parts (the Quest Tracker, the widget column, the reminders, the race bar ...) keep MelloUI's look either way, and every feature keeps working. Switching it on also switches Custom Sounds on, and the first time puts in the Edit Mode layout the reskin is drawn for, fitted to your screen. Switching it off leaves Custom Sounds on." }
opts[#opts + 1] = { type = "toggle", key = "preloadArt", name = "Preload Artwork", requires = "reskin",
	desc = "Load all of the reskin's artwork during the loading screen, so a window opened for the first time after a reload shows its art at once instead of a moment later. Keeps about 13 MB of artwork in memory for the whole session, including for windows you never open. Off: each piece loads the first time a window needs it." }
opts[#opts + 1] = { type = "button", name = "Switch every area on", hint = "when nothing is reskinned any more",
	text = "Switch on", requires = "reskin",
	desc = "Every window and HUD area of the reskin back on, and every feature of UI Modifications that is on by default.",
	onClick = function(_, db)
		local ok, count = UM.RestoreAreas(db)
		if not ok then
			MelloUI:Print(UM.areasRefused)
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
	end }
-- the borders, one choice per kind for every window, and the Kit Colours
-- (Kit.borderKinds, the core kinds' rows the core's): each where its kind
-- stands, after the kind before it (the first after the palette)
do
	local prev = "palette"
	for _, k in ipairs(MelloUI.Kit and MelloUI.Kit.borderKinds or {}) do
		if not k.core then
			part.defaults[k.key] = k.default
			local opt = { type = "dropdown", key = k.key, name = k.name, values = k.values, desc = k.desc,
				requires = "reskin", new = k.new, after = prev }
			if k.kind == "colours" then
				opt.get, opt.relist = ColoursShown, "palette"
			end
			opts[#opts + 1] = opt
		end
		prev = k.key
	end
end
-- (0.19.8, the border library's stage 3, the plan's decision 7: one Raid
-- Frame Border, laid on each frame, round each group, or both;
-- Modules/KitBorders.lua)
opts[#opts + 1] = { type = "dropdown", key = "raidBorderPlace", name = "Raid Border Placement", requires = "reskin",
	values = { { value = "both", label = "On each frame and round the group" }, { value = "frame", label = "On each frame" },
		{ value = "group", label = "Round the group" } },
	desc = "Where Raid Frame Border goes: on each raid frame, round each raid group, or both. A group's border shows while Edit Mode's Display Border is on for the raid frames." }
-- the game windows' sheets round the core's own
opts[#opts + 1] = SheetOption(SHEET_FIRST, { before = "parchment_questTracker" })
for i, entry in ipairs(SHEETS_AFTER) do
	opts[#opts + 1] = SheetOption(entry, i == 1 and { after = "parchment_meter" } or nil)
end
-- The parchment's look (0.20.3; the user, 2026-10-11: "the new one is the default but some people liked how the old
-- one looked aswell"): every sheet and page, live (Kit:SetParchmentStyle)
opts[#opts + 1] = { type = "dropdown", key = "parchmentStyle", name = "Parchment Style", requires = "reskin",
	values = { { value = "paper", label = "Burnt paper" }, { value = "classic", label = "Classic vellum" } },
	desc = "How the parchment looks wherever it shows: the sheets switched on below, and the quest log, quest and spell book pages. Burnt paper: warm paper with burnt edges, big pages with curled corners. Classic vellum: the vellum with painted brush-stroke edges from before 0.20.1." }
part.options = opts

-- the panel switches: their rows need the reskin, and with it off no panel
-- comes on (UI Modifications' PanelWanted)
part.panelRequires = "reskin"
function part.PanelsOff(db)
	return db.reskin == false
end

-- the login's own frame (UI Modifications' OnLoginFrame): the preload
function part.LoginFrame(db)
	ApplyPreload(db, true)
end

-- the one-time steps, first in OnEnable
function part.Migrate(db)
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
	-- (one look, stage E, the user 2026-10-15: the Quest Tracker's Painted
	-- Skin, questTrackerKit, is removed with its one-time step; a saved key is
	-- dropped at the login by Core's MERGES, the flag stays in `keep`)
end

-- last in OnEnable, the areas switched: every area off is a real choice,
-- never undone behind the player's back, but said (the switch then looks
-- like it does nothing); the preload; the layout put in with the reskin
function part.Enabled(db)
	if db.reskin ~= false and UM.NothingWanted(db) then
		MelloUI:Notice("UI Modifications is on, but every area of the reskin is switched off, so the game's own art is what you see. The Configurator's Look page has a \"Switch every area on\" button.")
	end
	ApplyPreload(db, true)
	ReskinOn(db)
end

function part.Disabled(db)
	ApplyPreload(db, false)
end

-- a setting of the part's (true: applied here, UI Modifications' own branches
-- are passed by)
function part.Setting(key, value, db)
	if key == "parchmentStyle" then
		if MelloUI.Kit and MelloUI.Kit.SetParchmentStyle then
			MelloUI.Kit:SetParchmentStyle()
		end
		return true
	elseif key == "raidBorderPlace" then
		if MelloUI.Kit and MelloUI.Kit.ApplyBorder then
			MelloUI.Kit:ApplyBorder("raid")   -- (0.19.8: where Raid Frame Border goes)
		end
		return true
	elseif key == "preloadArt" then
		ApplyPreload(db, true)
		return true
	elseif key == "reskin" then
		UM.ApplyAreas(db, true)
		ApplyPreload(db, true)
		if value then
			ReskinOn(db)
		end
		return true
	end
	for _, k in ipairs(MelloUI.Kit and MelloUI.Kit.borderKinds or {}) do
		if key == k.key and not k.core then
			-- (the Kit Colours in a Batch: at its end, with a palette
			-- set in it, Tint.KitColours)
			if not (k.kind == "colours" and MelloUI.InBatch and MelloUI:InBatch()) then
				MelloUI.Kit:ApplyBorder(k.kind)
			end
			return true
		end
	end
	return false
end

-- the Kit Colours set in a Batch, at its end (Tint.KitColours above); and
-- the preload again for a look moved (Tint.LookMoved)
MelloUI:On("setting", Perf.Shared("'setting' on the bus: the Kit Colours", function(name, key)
	if name == "UIModifications" and key == "kitColours" and UM.isEnabled then
		Tint.KitColours()
	end
end), part)   -- (its own owner: the core 'setting' listener stays)
MelloUI:On("palette", Perf.Shared("'palette' on the bus", function()
	if Tint.LookMoved() then
		Kit:NextFrame("UIModifications preload", Tint.PreloadAgain)
	end
end), part)

UM:AddPart(part)
end
-- OLDSCHOOL END
