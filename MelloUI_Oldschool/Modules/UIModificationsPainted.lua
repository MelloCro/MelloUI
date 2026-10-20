--------------------------------------------------------------------------------
-- MelloUI - UI Modifications, the painted reskin's part (one look, stage I:
-- UIModifications.lua's OLDSCHOOL block)
--
-- The painted reskin's settings -- its switch, Preload Artwork, Switch every
-- area on, the Kit Colours, the painted border kinds, the per-window choices
-- -- added to UI Modifications as one of its parts (MelloUI.ModuleParts: the
-- same module, its saved keys and option ids), so profiles, share strings and
-- the installer read them as before. It loads after the painted engine, whose
-- border kinds it lists (Kit.borderKinds).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("UIModificationsPainted")
local Kit = MelloUI.Kit

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
-- (one look stage I: MelloUI_Oldschool from another MelloUI version dresses
-- nothing -- Oldschool.lua's guard)
local function Refused()
	local oldschool = rawget(MelloUI, "Oldschool")
	return type(oldschool) == "table" and oldschool.refused ~= nil
end
function part.PanelsOff(db)
	return db.reskin == false or Refused()
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
	if Refused() then
		MelloUI:Notice("%s: its painted look stays off. Update both from the same release, then /reload.",
			MelloUI.Oldschool.refused)
		return
	end
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
