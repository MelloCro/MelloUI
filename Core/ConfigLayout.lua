--------------------------------------------------------------------------------
-- MelloUI - ConfigLayout
--
-- Where every option of the Configurator lives (0.15.0, the rebuild; the
-- user, 2026-09-27/28: a grouped side list, one page per element with its
-- tabs on top and the same sections in the same order on every tab, a picker
-- where an element has parts with the same rows, and every option in exactly
-- ONE place). This file is data only: the modules keep their option schemas
-- (type, key, name, desc, values, range, parent / requires, new) as the
-- DEFINITIONS, and Core/Config.lua builds the side list, the pages, the
-- search and the /mello words from what is here. Moving an option is moving
-- its one R line (and, for a global setting, its Link lines).
--
--   L.SECTIONS  the sections of a tab, in their fixed order; one with no
--               rows is left out
--   L.groups    the side list: { title = header or nil, entries = { page
--               keys } }, in order
--   L.pages     [page key] = { title, icon, flavour, tabs, module,
--               switchLabel, switchDesc, picker, preview, own }
--       icon        "module:<Name>" (that module's registry icon) or a path
--       flavour     the header's line; nil: the page module's own (registry)
--       tabs        the tab names, in order (one tab: no tab row)
--       module      the module whose switch sits in the page header (a page
--                   several modules share has none: each such module's
--                   switch is the first row of its tab)
--       switchLabel / switchDesc  that switch's label and tooltip when not
--                   the plain "Enabled" (Look's: it is UI Modifications')
--       picker      { label, noun, picks = { { key, label }, ... } } or
--                   { label, noun, from = "windows" }: the registry's kit
--                   panels whose `window.tab` is "Windows" and that have no
--                   `switch` (not the Quest Tracker's), by label; a pick's
--                   key is the panel module's name
--       preview     the live preview the header shows ("unitframe")
--       own         Home and Profiles: the Configurator's own pages
--   L.words     /mello words the page list does not give by itself (lower
--               case, spaces removed): word = { page[, tab][, pick = key] };
--               never one of /mello's own command words
--   L.unplaced  ["Module.key"] = why: a schema option that has no R line on
--               purpose (the checks fail on any other without one)
--   L.Define(R, Link)  lays every row, in order; run once when first needed
--               (the Configurator's first open, a /mello word), never at load
--
-- R(page, tab, section, what[, extra]): one row, at the end of its section.
--   what   "Module.key"          a setting of that module (its schema option)
--          "Module.#Name"        the module's button option of that name
--          "Module.!enabled"     the module's own switch (IsModuleEnabled)
--          { [pick] = id, ["*"] = id }  a row whose setting is another key
--                                per pick ("*": every pick not named); a
--                                pick with none shows the row dimmed
--          { from = "windows" }  UIModifications.<Panel>, one per window pick
--          { prefix = "Module.#" }  every such button, in the module's order
--   extra  name        the row's label (else the schema's name)
--          only        { picks }: live on those picks, dimmed on the others
--          wide        the hint of a row that is one key for every pick
--          picture     true: a picture row (its choices from Kit.borderKinds
--                      by key, else the key owner's PickerGroups section)
--          swatch      "palette": the palette's swatch left of the control
--          free        true: works with UI Modifications off, so the row is
--                      never dimmed for it being off. UI Modifications'
--                      own such keys say so in their definitions too (the
--                      definition's `free`); Tweaks' notice keys are read
--                      by Core itself with Tweaks off (Core/Notice.lua,
--                      Core/CentreText.lua, MelloUI:Notice)
--          gate        "Module.key": live only while that switch is on
--          when        { key, value, line }: live only while that setting
--                      has that value; `line` is the hint while it has not
--          also        { [id] = text }: frames with no pick that key reaches
--                      too (the shared hint's tail)
-- Link(page, tab, section, target, label): a row naming a setting whose one
-- place is another page (its value and a button to it), at the end of its
-- section; target an id, or { [pick] = id } on a picker page. The button's
-- page, tab and pick are those of the target's own R line.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local L = {}
MelloUI.ConfigLayout = L

L.SECTIONS = { "General", "Look", "Text", "Layout", "Behaviour", "Sound", "Advanced" }

L.groups = {
	{ entries = { "Home" } },
	{ title = "The look", entries = { "Look", "Windows" } },
	{ title = "Frames and bars", entries = { "UnitFrames", "Nameplates", "ActionBars", "Minimap", "BarsMeters" } },
	{ title = "Chat and text", entries = { "Chat", "Tooltip", "ScreenText" } },
	{ title = "Quests and travel", entries = { "QuestTracker", "QuestList", "Route", "Reminders", "Gains" } },
	{ title = "Sound", entries = { "VoiceOver", "CustomSounds" } },
	{ entries = { "Profiles" } },
}

L.pages = {
	Home = { title = "Home", own = true },
	-- the global look: every element's page links here (its header switch
	-- is UI Modifications', which takes the reskin and every folded feature
	-- with it)
	Look = { title = "Look", icon = "module:UIModifications", module = "UIModifications",
		flavour = "The look of the whole interface: the painted reskin, the palette, the soft shade, borders, fonts, Dark Mode, the bar texture and the parchment sheets. Every element's own page links here.",
		switchLabel = "UI Modifications",
		switchDesc = "The painted reskin AND every feature of UI Modifications: Vendor, Error Messages, Cooldown Timers, Nameplate Icons, Chat, Tooltip, Fonts, Dark Mode, Bar Textures, Buffs & Debuffs, Unit Frame Tweaks, FPS / Latency, Class Icons, Bar Values, the game windows' skins, hiding the micro menu, the bag bar and the minimap coordinates, and the world text scale. Off: all of them are off. The palette, the UI Shade, Reduce Motion and MelloUI's notices keep working.",
		tabs = { "General", "Borders", "Fonts", "Dark Mode", "Bar Texture", "Parchment" } },
	Windows = { title = "Windows", icon = "module:CharacterPanel",
		flavour = "The game's windows in the painted look, one at a time: pick a window.",
		tabs = { "Windows" },
		picker = { label = "Window", noun = "window", from = "windows" } },
	UnitFrames = { title = "Unit Frames", icon = "module:UnitFrames",
		flavour = "The player, target, focus, pet, party and raid frames, the cast bars and the personal resource display: pick a frame.",
		tabs = { "Frame", "Bars", "Buffs & Debuffs" }, preview = "unitframe",
		-- boss frames and target of target have no pick: the keys that reach
		-- them say so in their row's hint (`also`)
		picker = { label = "Frame", noun = "frame", picks = { { "player", "Player" }, { "target", "Target" },
			{ "focus", "Focus" }, { "pet", "Pet" }, { "party", "Party" }, { "raid", "Raid Frames" },
			{ "castbars", "Cast Bars" }, { "personal", "Personal Resource" } } } },
	Nameplates = { title = "Nameplates", icon = "module:Nameplates",
		flavour = "The nameplates over every unit, their icons and auras, and the markers over your party.",
		tabs = { "Plates", "Auras & Icons", "Party Markers" } },
	ActionBars = { title = "Action Bars", icon = "module:ActionBarPanel",
		flavour = "The action bars, the micro menu and the bag bar: pick a bar.",
		tabs = { "Bars", "Cooldown Timers" },
		picker = { label = "Bar", noun = "bar", picks = { { "bars", "Action Bars" }, { "micro", "Micro Menu" }, { "bag", "Bag Bar" } } } },
	Minimap = { title = "Minimap", icon = "module:MinimapPanel",
		flavour = "The minimap, its shape, size and border, and the Services bar under it.",
		tabs = { "Minimap", "Services Bar" } },
	BarsMeters = { title = "Bars & Meters", icon = "module:Stats",
		flavour = "The experience and reputation bars, the cooldown manager, the damage meter, event widgets and the FPS / latency readout.",
		tabs = { "XP & Reputation", "Cooldown Manager", "Damage Meter", "Event Widgets", "FPS / Latency" } },
	Chat = { title = "Chat", icon = "module:Chat",
		flavour = "The chat windows, the lines in them and the whisper popup.",
		tabs = { "Chat Frame", "Messages", "Whispers" } },
	Tooltip = { title = "Tooltip", icon = "module:Tooltip",
		flavour = "The tooltips: their backdrop, the unit lines, where they sit, and the quest lines on them.",
		tabs = { "Tooltip" } },
	ScreenText = { title = "Screen Text", icon = "module:ErrorFilter",
		flavour = "The text in the middle of the screen: MelloUI's notices, the zone text, the red error messages and the floating combat numbers.",
		tabs = { "Notices", "Error Messages", "Combat Text" } },
	QuestTracker = { title = "Quest Tracker", icon = "module:QuestTracker", module = "QuestTracker",
		tabs = { "Quest Tracker", "Objective Tracker" } },
	QuestList = { title = "Quest List", icon = "module:QuestList", module = "QuestList",
		tabs = { "List", "Map" } },
	Route = { title = "Route", icon = "module:Route", module = "Route",
		tabs = { "Route", "Arrow & Marker", "Flights" } },
	-- no header switch: three modules share the page, and each tab's first
	-- row is its module's switch (Reminders, Restock, Vendor Automation)
	Reminders = { title = "Reminders", icon = "module:Reminders",
		flavour = "Supplies, mail, repairs and training: a gentle nudge beside your portrait, never a nag. With the restock list and its shopping list, and the vendor's automatic repairs and junk sales.",
		tabs = { "Reminders", "Restock", "Vendor" } },
	Gains = { title = "Gains", icon = "module:Gains", module = "Gains",
		tabs = { "Gains" } },
	VoiceOver = { title = "Voice Over", icon = "module:VoiceOver", module = "VoiceOver",
		tabs = { "Reading", "Voices", "Sound Packs", "Overlay" } },
	CustomSounds = { title = "Custom Sounds", icon = "module:CustomSounds", module = "CustomSounds",
		tabs = { "Sounds", "Preview" } },
	Profiles = { title = "Profiles", own = true },
}

-- The page words beyond a page's key or title and the words each module
-- gives by itself (the page holding most of its rows, the tab of its first
-- row, a window panel's pick): the Look's tabs, the modules whose rows are
-- spread over several pages, and the panels with no row of their own. The
-- Auras module's name is /mello's aura probe: its page is buffs / debuffs.
L.words = {
	uimodifications = { "Look" },
	palette = { "Look", "General" },
	uishade = { "Look", "General" },
	borders = { "Look", "Borders" },
	fonts = { "Look", "Fonts" },
	darkmode = { "Look", "Dark Mode" },
	bartextures = { "Look", "Bar Texture" },
	parchment = { "Look", "Parchment" },
	characterpanel = { "Windows", pick = "CharacterPanel" },
	buffs = { "UnitFrames", "Buffs & Debuffs" },
	debuffs = { "UnitFrames", "Buffs & Debuffs" },
	classicons = { "UnitFrames", "Frame" },
	unitframepanel = { "UnitFrames", "Frame" },
	bartext = { "UnitFrames", "Bars" },
	castbarpanel = { "UnitFrames", "Frame", pick = "castbars" },
	raidframepanel = { "UnitFrames", "Frame", pick = "raid" },
	nameplatepanel = { "Nameplates", "Plates" },
	partymarkers = { "Nameplates", "Party Markers" },
	actionbarpanel = { "ActionBars", "Bars" },
	cooldowntext = { "ActionBars", "Cooldown Timers" },
	minimappanel = { "Minimap", "Minimap" },
	services = { "Minimap", "Services Bar" },
	stats = { "BarsMeters", "FPS / Latency" },
	damagemeterpanel = { "BarsMeters", "Damage Meter" },
	chatpanel = { "Chat", "Chat Frame" },
	tooltippanel = { "Tooltip" },
	tweaks = { "ScreenText", "Notices" },
	errorfilter = { "ScreenText", "Error Messages" },
	trackerpanel = { "QuestTracker", "Objective Tracker" },
	restock = { "Reminders", "Restock" },
	vendor = { "Reminders", "Vendor" },
}

-- (none: every schema option has its R line)
L.unplaced = {}

function L.Define(R, Link)
	-- Look: the global look, only here (every element's page links to it)
	R("Look", "General", "General", "UIModifications.reskin")
	R("Look", "General", "General", "UIModifications.preloadArt")
	R("Look", "General", "General", "UIModifications.#Switch every area on")
	-- (free: applied with UI Modifications on or off, its OnSettingChanged)
	R("Look", "General", "Look", "UIModifications.palette", { swatch = "palette", free = true })
	R("Look", "General", "Look", "UIModifications.kitColours")
	R("Look", "General", "Look", "UIModifications.uiShade", { free = true })
	R("Look", "General", "Look", "UIModifications.uiShadeStrength", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_windows", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_actionbars", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_castbars", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_unitframes", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_chat", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_bags", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_minimap", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_tracker", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_buffs", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_widgets", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_nameplates", { free = true })
	R("Look", "General", "Text", "UIModifications.nameFormat")
	R("Look", "General", "Behaviour", "UIModifications.reduceMotion", { free = true })
	R("Look", "Borders", "Look", "UIModifications.buttonBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.sideTabBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.barBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.roundBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.auraBorder", { picture = true })
	R("Look", "Fonts", "General", "UIModifications.qol_Fonts")
	R("Look", "Fonts", "Text", "Fonts.style")
	R("Look", "Fonts", "Text", "Fonts.scaleText")
	R("Look", "Fonts", "Text", "Fonts.scaleChat")
	R("Look", "Fonts", "Text", "Fonts.scaleTitle")
	R("Look", "Fonts", "Text", "Fonts.outline")
	R("Look", "Fonts", "Advanced", "Fonts.fontText")
	R("Look", "Fonts", "Advanced", "Fonts.fontChat")
	R("Look", "Fonts", "Advanced", "Fonts.fontTitle")
	R("Look", "Dark Mode", "General", "UIModifications.qol_DarkMode")
	R("Look", "Dark Mode", "Look", "DarkMode.shade")
	R("Look", "Dark Mode", "Look", "DarkMode.kitShade")
	R("Look", "Dark Mode", "Look", "DarkMode.desaturate")
	R("Look", "Bar Texture", "General", "UIModifications.qol_BarTextures")
	R("Look", "Bar Texture", "Look", "BarTextures.texture")
	-- the health bars' colour reaches the unit frames AND the nameplates
	-- (their descs; RecolorHealthBar): global
	R("Look", "Bar Texture", "Look", "BarTextures.healthColor")
	R("Look", "Bar Texture", "Look", "BarTextures.overrideThreat")
	R("Look", "Bar Texture", "Look", "BarTextures.executeRange")
	R("Look", "Bar Texture", "Look", "BarTextures.executeBelow")
	R("Look", "Parchment", "Look", "UIModifications.parchment_tracker")
	R("Look", "Parchment", "Look", "UIModifications.parchment_questTracker")
	R("Look", "Parchment", "Look", "UIModifications.parchment_chat")
	R("Look", "Parchment", "Look", "UIModifications.parchment_whisper")
	R("Look", "Parchment", "Look", "UIModifications.parchment_meter")
	R("Look", "Parchment", "Look", "UIModifications.parchment_character")
	R("Look", "Parchment", "Look", "UIModifications.parchment_tooltip")
	R("Look", "Parchment", "Look", "UIModifications.parchment_dialog")

	-- Windows (the picker: the registry's windows). A kit panel's row here is
	-- live on the CURRENT pick's Painted Skin, not on the panel owning the
	-- key: the Bank wears the Bags' keys, and Quality Gems stays live on the
	-- Bank with the Bags' skin off
	R("Windows", "Windows", "Look", { from = "windows" }, { name = "Painted Skin" })
	R("Windows", "Windows", "Look", { CharacterPanel = "CharacterPanel.windowBackground", BackpackPanel = "BackpackPanel.windowBackground", BankPanel = "BackpackPanel.windowBackground" }, { name = "Window Background", picture = true })
	R("Windows", "Windows", "Look", { BackpackPanel = "BackpackPanel.itemBackground", BankPanel = "BackpackPanel.itemBackground", GuildBankPanel = "BackpackPanel.itemBackground" }, { name = "Item Slot Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.bookBackground" }, { name = "Book Page Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.pageBackground" }, { name = "Crafting Page Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.listBackground" }, { name = "Recipe List Background", picture = true })
	R("Windows", "Windows", "Look", { BackpackPanel = "BackpackPanel.qualityGems", BankPanel = "BackpackPanel.qualityGems", GuildBankPanel = "BackpackPanel.qualityGems" }, { name = "Quality Gems" })
	R("Windows", "Windows", "Layout", { BackpackPanel = "Tweaks.bagSlotsOnBags" }, { name = "Bag Slots on Bag Window" })
	R("Windows", "Windows", "Behaviour", "UIModifications.fadeWindows", { wide = "every window" })

	-- Unit Frames (the picker: Player ... Personal Resource)
	R("UnitFrames", "Frame", "General", "UIModifications.qol_UnitFrames", { only = { "player", "target", "focus", "pet", "party" } })
	R("UnitFrames", "Frame", "General", "UIModifications.qol_ClassIcons", { only = { "player", "target", "focus", "party" } })
	R("UnitFrames", "Frame", "Look", { player = "UIModifications.UnitFramePanel", target = "UIModifications.UnitFramePanel", focus = "UIModifications.UnitFramePanel", pet = "UIModifications.UnitFramePanel", party = "UIModifications.UnitFramePanel", raid = "UIModifications.RaidFramePanel", castbars = "UIModifications.CastBarPanel" }, { name = "Painted Skin" })
	R("UnitFrames", "Frame", "Look", { player = "DarkMode.unitframes", target = "DarkMode.unitframes", focus = "DarkMode.unitframes", pet = "DarkMode.unitframes", party = "DarkMode.unitframes", castbars = "DarkMode.castbar", personal = "DarkMode.personal" }, { name = "Dark Mode", also = { ["DarkMode.unitframes"] = "boss and target of target" } })
	R("UnitFrames", "Frame", "Look", "UnitFrames.frameAlpha", { only = { "player", "target", "focus", "pet" } })
	R("UnitFrames", "Frame", "Look", "UnitFrames.hideReputationColor", { only = { "target", "focus" } })
	R("UnitFrames", "Frame", "Look", "UnitFrames.hideCombatGlow", { only = { "player", "target", "focus", "pet", "party" } })
	R("UnitFrames", "Frame", "Look", "UnitFrames.hideStatusGlow", { only = { "player" } })
	R("UnitFrames", "Frame", "Look", "ClassIcons.portraits", { only = { "player", "target", "focus", "party" } })
	R("UnitFrames", "Frame", "Look", "ClassIcons.pvpFlag", { only = { "player" } })
	R("UnitFrames", "Frame", "Look", "UnitFramePanel.marks", { only = { "target", "focus" } })
	R("UnitFrames", "Frame", "Text", "UnitFrames.centerNames", { only = { "player", "target", "focus", "pet" } })
	R("UnitFrames", "Frame", "Behaviour", "UnitFrames.fadeOutOfCombat", { only = { "player" } })
	-- Pet Frame Too: a sub-switch of the Player's Fade Out Of Combat (its
	-- schema's parent), not the pet's own fade
	R("UnitFrames", "Frame", "Behaviour", "UnitFrames.fadePet", { only = { "pet" } })
	R("UnitFrames", "Frame", "Behaviour", "UnitFrames.fadeAlpha", { only = { "player", "pet" } })
	R("UnitFrames", "Bars", "General", "UIModifications.qol_BarText", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Look", { player = "BarTextures.unitframes", target = "BarTextures.unitframes", focus = "BarTextures.unitframes", pet = "BarTextures.unitframes", party = "BarTextures.unitframes", raid = "BarTextures.raidframes", castbars = "BarTextures.castbars", personal = "BarTextures.personal" }, { name = "Bar Texture", also = { ["BarTextures.unitframes"] = "boss and target of target" } })
	R("UnitFrames", "Bars", "Text", { player = "BarText.player", target = "BarText.target", focus = "BarText.focus" }, { name = "Values On This Frame" })
	R("UnitFrames", "Bars", "Text", "BarText.health", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Text", "BarText.power", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Text", "BarText.format", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Text", "BarText.showMax", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Text", "BarText.fontSize", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Layout", "BarText.position", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Layout", "BarText.offsetX", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Layout", "BarText.offsetY", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Buffs & Debuffs", "General", "UIModifications.qol_Auras", { only = { "player", "target" } })
	R("UnitFrames", "Buffs & Debuffs", "General", { player = "Auras.player", target = "Auras.target" }, { name = "Buffs & Debuffs On This Frame" })
	R("UnitFrames", "Buffs & Debuffs", "Look", "DarkMode.auras", { only = { "player", "target" } })
	R("UnitFrames", "Buffs & Debuffs", "Look", "DarkMode.auraIconBorder", { only = { "player", "target" } })
	R("UnitFrames", "Buffs & Debuffs", "Look", "DarkMode.keepDispelColor", { only = { "player", "target" } })
	R("UnitFrames", "Buffs & Debuffs", "Layout", { player = "Auras.playerSize", target = "Auras.targetSize" }, { name = "Icon Size" })
	R("UnitFrames", "Buffs & Debuffs", "Layout", "Auras.playerPerRow", { only = { "player" } })
	R("UnitFrames", "Buffs & Debuffs", "Layout", "Auras.playerColumn", { only = { "player" } })
	R("UnitFrames", "Buffs & Debuffs", "Behaviour", "Auras.targetOnlyMine", { only = { "target" } })

	-- Nameplates (tabs: the parts differ)
	R("Nameplates", "Plates", "Look", "UIModifications.NameplatePanel", { name = "Painted Skin" })
	R("Nameplates", "Plates", "Look", "UIModifications.nameplateBorder", { picture = true })
	R("Nameplates", "Plates", "Look", "DarkMode.nameplates", { name = "Dark Mode" })
	R("Nameplates", "Plates", "Look", "BarTextures.nameplates", { name = "Bar Texture" })
	R("Nameplates", "Plates", "Look", "NameplatePanel.marks")
	R("Nameplates", "Plates", "Text", "NameplatePanel.nameShade")
	R("Nameplates", "Plates", "Text", "NameplatePanel.shadeStrength")
	R("Nameplates", "Auras & Icons", "General", "UIModifications.qol_Nameplates")
	R("Nameplates", "Auras & Icons", "General", "Nameplates.bigCC")
	R("Nameplates", "Auras & Icons", "General", "Nameplates.questIcon")
	R("Nameplates", "Auras & Icons", "General", "Auras.nameplates")
	R("Nameplates", "Auras & Icons", "Layout", "Nameplates.ccSize")
	R("Nameplates", "Auras & Icons", "Layout", "Nameplates.ccGap")
	R("Nameplates", "Auras & Icons", "Layout", "Nameplates.questIconSize")
	R("Nameplates", "Auras & Icons", "Layout", "Auras.nameplateSize")
	R("Nameplates", "Auras & Icons", "Behaviour", "CooldownText.nameplates")
	R("Nameplates", "Party Markers", "General", "PartyMarkers.!enabled", { name = "Party Markers" })
	R("Nameplates", "Party Markers", "General", "PartyMarkers.who")
	R("Nameplates", "Party Markers", "Look", "PartyMarkers.roleRing")
	R("Nameplates", "Party Markers", "Layout", "PartyMarkers.size")
	R("Nameplates", "Party Markers", "Layout", "PartyMarkers.offset")

	-- Action Bars (the picker: Action Bars, Micro Menu, Bag Bar)
	R("ActionBars", "Bars", "General", { micro = "Tweaks.hideMicroMenu", bag = "Tweaks.hideBagBar" }, { name = "Hide This Bar" })
	R("ActionBars", "Bars", "General", "ActionBarPanel.hidePageArrows", { only = { "bars" } })
	R("ActionBars", "Bars", "Look", "UIModifications.ActionBarPanel", { name = "Painted Skin", wide = "every bar" })
	R("ActionBars", "Bars", "Look", { bars = "ActionBarPanel.barBackdrop", micro = "ActionBarPanel.microBackdrop", bag = "ActionBarPanel.bagBackdrop" }, { name = "Backdrop", picture = true })
	R("ActionBars", "Bars", "Look", { bars = "ActionBarPanel.barBackground", micro = "ActionBarPanel.microBackground", bag = "ActionBarPanel.bagBackground" }, { name = "Backdrop Background", picture = true })
	R("ActionBars", "Bars", "Look", { bars = "ActionBarPanel.buttonBackground", micro = "ActionBarPanel.microButtonBackground", bag = "ActionBarPanel.bagButtonBackground" }, { name = "Button Background", picture = true })
	R("ActionBars", "Bars", "Look", { bars = "DarkMode.actionbars", micro = "DarkMode.micromenu", bag = "DarkMode.micromenu" }, { name = "Dark Mode" })
	R("ActionBars", "Bars", "Look", "DarkMode.gryphons", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "General", "UIModifications.qol_CooldownText", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "General", "CooldownText.actionBars", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Text", "CooldownText.fontRatio", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Text", "CooldownText.tenths", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Text", "CooldownText.colorByTime", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Behaviour", "CooldownText.minDuration", { only = { "bars" } })

	-- Minimap (its Services bar a tab: Services has no header switch here)
	R("Minimap", "Minimap", "General", "Tweaks.hideMinimapCoords")
	R("Minimap", "Minimap", "Look", "UIModifications.MinimapPanel", { name = "Painted Skin" })
	R("Minimap", "Minimap", "Look", "MinimapPanel.shape", { picture = true })
	R("Minimap", "Minimap", "Look", "MinimapPanel.squareBorder", { picture = true, when = { key = "MinimapPanel.shape", value = "square", line = "Only for the square map" } })
	R("Minimap", "Minimap", "Look", "DarkMode.minimap", { name = "Dark Mode" })
	R("Minimap", "Minimap", "Layout", "MinimapPanel.width")
	R("Minimap", "Minimap", "Layout", "MinimapPanel.height", { when = { key = "MinimapPanel.shape", value = "square", line = "Only for the square map (the round map takes Width)" } })
	R("Minimap", "Services Bar", "General", "Services.!enabled", { name = "Services Bar" })
	R("Minimap", "Services Bar", "General", "Services.showBar")
	R("Minimap", "Services Bar", "General", "Services.showButton")
	R("Minimap", "Services Bar", "Look", "Services.roundIcons")
	R("Minimap", "Services Bar", "Layout", "Services.buttonLayout")
	R("Minimap", "Services Bar", "Layout", "Services.barOffset")
	R("Minimap", "Services Bar", "Layout", "MinimapPanel.servicesMerge")

	-- Bars & Meters
	R("BarsMeters", "XP & Reputation", "Look", "BarTextures.statusbars", { name = "Bar Texture" })
	R("BarsMeters", "XP & Reputation", "Look", "DarkMode.statusbars", { name = "Dark Mode" })
	R("BarsMeters", "Cooldown Manager", "Look", "BarTextures.cooldowns", { name = "Bar Texture" })
	R("BarsMeters", "Cooldown Manager", "Look", "DarkMode.cooldowns", { name = "Dark Mode" })
	R("BarsMeters", "Damage Meter", "Look", "UIModifications.DamageMeterPanel", { name = "Painted Skin" })
	R("BarsMeters", "FPS / Latency", "General", "UIModifications.qol_Stats")
	R("BarsMeters", "FPS / Latency", "General", "Stats.showFps")
	R("BarsMeters", "FPS / Latency", "General", "Stats.showLatency")
	R("BarsMeters", "FPS / Latency", "General", "Stats.worldLatency")
	R("BarsMeters", "FPS / Latency", "Text", "Stats.fontSize")
	R("BarsMeters", "FPS / Latency", "Layout", "Stats.offsetX")
	R("BarsMeters", "FPS / Latency", "Layout", "Stats.offsetY")
	R("BarsMeters", "FPS / Latency", "Behaviour", "Stats.interval")

	-- Chat
	R("Chat", "Chat Frame", "General", "UIModifications.qol_Chat")
	R("Chat", "Chat Frame", "Look", "UIModifications.ChatPanel", { name = "Painted Skin" })
	R("Chat", "Chat Frame", "Look", "DarkMode.chat", { name = "Dark Mode" })
	R("Chat", "Chat Frame", "Look", "Chat.hideBackground")
	R("Chat", "Chat Frame", "Look", "Chat.windowAlphaOn")
	R("Chat", "Chat Frame", "Look", "Chat.windowAlpha")
	R("Chat", "Chat Frame", "Look", "Chat.hideEditBox")
	R("Chat", "Chat Frame", "Look", "Chat.hideTabs")
	R("Chat", "Chat Frame", "Look", "Chat.hideButtons")
	R("Chat", "Chat Frame", "Text", "Fonts.fontChatText")
	R("Chat", "Chat Frame", "Text", "Fonts.fontChatParchment")
	R("Chat", "Chat Frame", "Text", "Fonts.scaleChatParchment")
	R("Chat", "Chat Frame", "Layout", "Chat.editBoxTop")
	R("Chat", "Chat Frame", "Behaviour", "Chat.tabsOnMouseover")
	R("Chat", "Chat Frame", "Behaviour", "Chat.smoothScroll")
	R("Chat", "Messages", "Text", "Chat.shortChannels")
	R("Chat", "Messages", "Text", "Chat.hideBrackets")
	R("Chat", "Messages", "Text", "Chat.classColors")
	R("Chat", "Messages", "Text", "Chat.nameStyle")
	R("Chat", "Messages", "Text", "Chat.nameShade")
	-- (free: read by MelloUI:Notice with Tweaks, and UI Modifications, off)
	R("Chat", "Messages", "Behaviour", "Tweaks.chatNotices", { free = true })
	R("Chat", "Whispers", "General", "Chat.whisperPopup")

	-- Tooltip
	R("Tooltip", "Tooltip", "General", "UIModifications.qol_Tooltip")
	R("Tooltip", "Tooltip", "Look", "UIModifications.TooltipPanel", { name = "Painted Skin" })
	R("Tooltip", "Tooltip", "Look", "Tooltip.darkBackdrop")
	R("Tooltip", "Tooltip", "Look", "Tooltip.backdropAlpha")
	R("Tooltip", "Tooltip", "Look", "Tooltip.darkBorder")
	R("Tooltip", "Tooltip", "Look", "Tooltip.classBorder")
	R("Tooltip", "Tooltip", "Look", "Tooltip.barTexture")
	R("Tooltip", "Tooltip", "Look", "Tooltip.classHealth")
	R("Tooltip", "Tooltip", "Look", "Tooltip.hideHealthBar")
	R("Tooltip", "Tooltip", "Text", "Tooltip.classNames")
	R("Tooltip", "Tooltip", "Layout", "Tooltip.anchor")
	R("Tooltip", "Tooltip", "Layout", "Tooltip.scale")
	R("Tooltip", "Tooltip", "Behaviour", "Tooltip.hideInCombat")
	R("Tooltip", "Tooltip", "Behaviour", "QuestList.tipQuestItems")
	R("Tooltip", "Tooltip", "Behaviour", "QuestList.tipTurnIn")

	-- Screen Text (the notices' rows free: Core reads them, Core/Notice.lua
	-- and Core/CentreText.lua, with Tweaks and UI Modifications off)
	R("ScreenText", "Notices", "General", "Tweaks.noticeOnScreen", { free = true })
	R("ScreenText", "Notices", "General", "Tweaks.noticeToChat", { free = true })
	R("ScreenText", "Notices", "Text", "Tweaks.zoneTextShade", { free = true })
	R("ScreenText", "Notices", "Text", "Tweaks.centreTextShade", { free = true })
	R("ScreenText", "Notices", "Text", "Tweaks.noticeOutline", { free = true })
	R("ScreenText", "Notices", "Sound", "Tweaks.noticeSounds", { free = true })
	R("ScreenText", "Error Messages", "General", "UIModifications.qol_ErrorFilter")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.resources")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.cooldowns")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.range")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.targeting")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.busy")
	R("ScreenText", "Combat Text", "Text", "Fonts.fontDamage")
	R("ScreenText", "Combat Text", "Text", "Fonts.scaleDamage")
	R("ScreenText", "Combat Text", "Layout", "Tweaks.worldTextScale")

	-- Quest Tracker (header: its module's switch)
	R("QuestTracker", "Quest Tracker", "Look", "UIModifications.questTrackerKit", { name = "Painted Skin" })
	R("QuestTracker", "Quest Tracker", "Text", "QuestTracker.textSize")
	R("QuestTracker", "Quest Tracker", "Text", "QuestTracker.headerSize")
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.matchMinimap")
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.width")
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.maxHeight")
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.scale")
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.#Reset Position")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.itemButtons")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.nearestFirst")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.showDistance")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.turnInLine")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.scrollStep")
	R("QuestTracker", "Objective Tracker", "Look", "UIModifications.TrackerPanel", { name = "Painted Skin" })

	-- Quest List (header: its module's switch)
	R("QuestList", "List", "General", "QuestList.filter")
	R("QuestList", "List", "General", "QuestList.hideCompleted")
	R("QuestList", "List", "General", "QuestList.startGiver")
	R("QuestList", "List", "General", "QuestList.startDrop")
	R("QuestList", "List", "General", "QuestList.startPickup")
	R("QuestList", "List", "General", "QuestList.startUnknown")
	R("QuestList", "List", "General", "QuestList.otherFaction")
	R("QuestList", "List", "General", "QuestList.otherClass")
	R("QuestList", "List", "General", "QuestList.levelAbove")
	R("QuestList", "List", "Layout", "QuestList.width")
	R("QuestList", "List", "Behaviour", "QuestList.dungeonSummary")
	R("QuestList", "Map", "General", "QuestList.mapPins")
	R("QuestList", "Map", "General", "QuestList.pinCompleted")
	R("QuestList", "Map", "General", "QuestList.zoneBadges")
	R("QuestList", "Map", "General", "QuestList.entrancePins")
	R("QuestList", "Map", "General", "QuestList.transportPins")

	-- Route (header: its module's switch)
	R("Route", "Route", "General", "Route.trackQuests")
	R("Route", "Route", "General", "Route.trackFirstWatched")
	R("Route", "Route", "General", "Route.worldMap")
	R("Route", "Route", "General", "Route.minimap")
	R("Route", "Route", "General", "Route.distanceText")
	R("Route", "Route", "General", "Route.travelTime")
	R("Route", "Route", "General", "Route.notice")
	R("Route", "Route", "Look", "Route.lineWidth")
	R("Route", "Route", "Behaviour", "Route.arrive")
	R("Route", "Route", "Behaviour", "Route.learn")
	R("Route", "Route", "Sound", "Route.noticeSound")
	R("Route", "Arrow & Marker", "General", "Route.arrow")
	R("Route", "Arrow & Marker", "General", "Route.worldMarker")
	R("Route", "Arrow & Marker", "General", "Route.routeBeam")
	R("Route", "Arrow & Marker", "Text", "Route.textShade")
	R("Route", "Arrow & Marker", "Layout", "Route.arrowScale")
	R("Route", "Flights", "General", "Route.flightHint")
	R("Route", "Flights", "General", "Route.flightCountdown")

	-- Reminders (each tab's first row its module's switch)
	R("Reminders", "Reminders", "General", "Reminders.!enabled", { name = "Reminders" })
	R("Reminders", "Reminders", "General", "Reminders.remind_mail")
	R("Reminders", "Reminders", "General", "Reminders.remind_repair")
	R("Reminders", "Reminders", "General", "Reminders.repairAt")
	R("Reminders", "Reminders", "General", "Reminders.remind_trainer")
	R("Reminders", "Reminders", "General", "Reminders.trainerClass")
	R("Reminders", "Reminders", "General", "Reminders.trainerProfession")
	R("Reminders", "Reminders", "Look", "Reminders.glow")
	R("Reminders", "Reminders", "Layout", "Reminders.place")
	R("Reminders", "Reminders", "Behaviour", "Reminders.stayResting")
	R("Reminders", "Reminders", "Behaviour", "Reminders.hold")
	R("Reminders", "Restock", "General", "Restock.!enabled", { name = "Restock List And Shop" })
	R("Reminders", "Restock", "General", "Reminders.remind_restock", { name = "Restock Reminder" })
	-- (live only while the reminder is on, as its rows hung on it before)
	R("Reminders", "Restock", "General", "Restock.below", { gate = "Reminders.remind_restock" })
	R("Reminders", "Restock", "General", "Restock.shopPanel")
	R("Reminders", "Restock", "General", "Restock.#Restock List")
	R("Reminders", "Vendor", "General", "UIModifications.qol_Vendor")
	R("Reminders", "Vendor", "Behaviour", "Vendor.autoRepair")
	R("Reminders", "Vendor", "Behaviour", "Vendor.guildRepair")
	R("Reminders", "Vendor", "Behaviour", "Vendor.autoSell")
	R("Reminders", "Vendor", "Behaviour", "Vendor.report")

	-- Gains (header: its module's switch)
	R("Gains", "Gains", "General", "Gains.skills")
	R("Gains", "Gains", "General", "Gains.values")
	R("Gains", "Gains", "General", "Gains.items")
	R("Gains", "Gains", "General", "Gains.bought")
	R("Gains", "Gains", "General", "Gains.junk")
	R("Gains", "Gains", "Behaviour", "Gains.hold")

	-- Voice Over (header: its module's switch)
	R("VoiceOver", "Reading", "General", "VoiceOver.gossip")
	R("VoiceOver", "Reading", "General", "VoiceOver.questDetail")
	-- (one switch for the objectives after an offer and after the Read
	-- button, only the voice pack's recorded line: 0.15.0, 2026-09-29)
	R("VoiceOver", "Reading", "General", "VoiceOver.recordedObjectives")
	R("VoiceOver", "Reading", "General", "VoiceOver.questProgress")
	R("VoiceOver", "Reading", "General", "VoiceOver.questComplete")
	R("VoiceOver", "Reading", "General", "VoiceOver.questLog")
	-- (the item text window's pages: books, letters, plaques; 0.15.0)
	R("VoiceOver", "Reading", "General", "VoiceOver.readBooks")
	R("VoiceOver", "Reading", "Behaviour", "VoiceOver.queueLines")
	R("VoiceOver", "Reading", "Behaviour", "VoiceOver.stopOnClose")
	R("VoiceOver", "Reading", "Behaviour", "VoiceOver.stopOnMove")
	R("VoiceOver", "Voices", "Sound", "VoiceOver.maleVoice")
	R("VoiceOver", "Voices", "Sound", "VoiceOver.femaleVoice")
	R("VoiceOver", "Voices", "Sound", "VoiceOver.rate")
	R("VoiceOver", "Voices", "Sound", "VoiceOver.volume")
	R("VoiceOver", "Voices", "Sound", "VoiceOver.raceProfiles")
	R("VoiceOver", "Voices", "Sound", "VoiceOver.profileStrength")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_human")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_elf")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_dwarf")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_gnome")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_orc")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_troll")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_tauren")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_undead")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_goblin")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_ogre")
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_monster")
	R("VoiceOver", "Sound Packs", "General", "VoiceOver.soundPacks")
	R("VoiceOver", "Sound Packs", "General", "VoiceOver.speakUnrecorded")
	R("VoiceOver", "Sound Packs", "General", "VoiceOver.preferRecordings")
	R("VoiceOver", "Sound Packs", "General", "VoiceOver.collectLines")
	R("VoiceOver", "Sound Packs", "Sound", "VoiceOver.soundChannel")
	R("VoiceOver", "Overlay", "General", "VoiceOver.overlay")
	R("VoiceOver", "Overlay", "General", "VoiceOver.overlayPortrait")
	R("VoiceOver", "Overlay", "General", "VoiceOver.overlaySubtitles")
	R("VoiceOver", "Overlay", "Layout", "VoiceOver.overlayLock")
	R("VoiceOver", "Overlay", "Layout", "VoiceOver.overlayScale")

	-- Custom Sounds (header: its module's switch)
	R("CustomSounds", "Sounds", "General", "CustomSounds.clicks")
	R("CustomSounds", "Sounds", "General", "CustomSounds.windows")
	R("CustomSounds", "Sounds", "General", "CustomSounds.inventory")
	R("CustomSounds", "Sounds", "General", "CustomSounds.equipment")
	R("CustomSounds", "Sounds", "General", "CustomSounds.vendor")
	R("CustomSounds", "Sounds", "General", "CustomSounds.social")
	R("CustomSounds", "Sounds", "General", "CustomSounds.groupFinder")
	R("CustomSounds", "Sounds", "General", "CustomSounds.crafting")
	R("CustomSounds", "Sounds", "General", "CustomSounds.quests")
	R("CustomSounds", "Sounds", "General", "CustomSounds.errors")
	R("CustomSounds", "Sounds", "General", "CustomSounds.targets")
	R("CustomSounds", "Sounds", "General", "CustomSounds.levelUp")
	R("CustomSounds", "Sounds", "General", "CustomSounds.loot")
	R("CustomSounds", "Sounds", "General", "CustomSounds.spells")
	R("CustomSounds", "Sounds", "General", "CustomSounds.map")
	R("CustomSounds", "Sounds", "General", "CustomSounds.scrollWheel")
	R("CustomSounds", "Sounds", "General", "CustomSounds.hover")
	R("CustomSounds", "Sounds", "Sound", "CustomSounds.channel")
	R("CustomSounds", "Preview", "Sound", { prefix = "CustomSounds.#" })   -- (the Play buttons, in the module's order)

	-- the link rows: a setting whose one place is another page (the global
	-- look on Look; the map's width on Minimap; the quest log's skin on
	-- Windows), named on each page it reaches
	Link("Windows", "Windows", "Look", { ["*"] = "UIModifications.shade_windows", BackpackPanel = "UIModifications.shade_bags" }, "UI Shade")
	Link("Windows", "Windows", "Look", { CharacterPanel = "UIModifications.parchment_character", DialogPanel = "UIModifications.parchment_dialog", ColorPickerPanel = "UIModifications.parchment_dialog", ReadyPanel = "UIModifications.parchment_dialog", StackSplitPanel = "UIModifications.parchment_dialog" }, "Parchment")
	Link("Windows", "Windows", "Look", "UIModifications.buttonBorder", "Button, side tab and round borders")
	Link("UnitFrames", "Frame", "Look", { player = "UIModifications.shade_unitframes", target = "UIModifications.shade_unitframes", focus = "UIModifications.shade_unitframes", pet = "UIModifications.shade_unitframes", party = "UIModifications.shade_unitframes", castbars = "UIModifications.shade_castbars" }, "UI Shade")
	Link("UnitFrames", "Frame", "Text", "UIModifications.nameFormat", "Names")
	Link("UnitFrames", "Bars", "Look", "BarTextures.texture", "Bar texture")
	Link("UnitFrames", "Bars", "Look", "BarTextures.healthColor", "Health bar colour")
	Link("UnitFrames", "Bars", "Look", "UIModifications.barBorder", "Bar border")
	Link("UnitFrames", "Buffs & Debuffs", "Look", { player = "UIModifications.shade_buffs" }, "UI Shade")
	Link("UnitFrames", "Buffs & Debuffs", "Look", "UIModifications.auraBorder", "Aura border")
	Link("Nameplates", "Plates", "Look", "UIModifications.shade_nameplates", "UI Shade")
	Link("Nameplates", "Plates", "Look", "BarTextures.healthColor", "Health bar colour")
	Link("Nameplates", "Plates", "Text", "UIModifications.nameFormat", "Names")
	Link("Nameplates", "Auras & Icons", "Look", "UIModifications.auraBorder", "Aura border")
	Link("ActionBars", "Bars", "Look", "UIModifications.shade_actionbars", "UI Shade")
	Link("ActionBars", "Bars", "Look", "UIModifications.buttonBorder", "Button border")
	Link("Minimap", "Minimap", "Look", "UIModifications.shade_minimap", "UI Shade")
	Link("BarsMeters", "XP & Reputation", "Look", "UIModifications.barBorder", "Bar border")
	Link("BarsMeters", "Damage Meter", "Look", "UIModifications.parchment_meter", "Parchment")
	Link("BarsMeters", "Event Widgets", "Look", "UIModifications.shade_widgets", "UI Shade")
	Link("Chat", "Chat Frame", "Look", "UIModifications.parchment_chat", "Parchment")
	Link("Chat", "Chat Frame", "Look", "UIModifications.shade_chat", "UI Shade")
	Link("Chat", "Chat Frame", "Text", "Fonts.scaleChat", "Chat font and size")
	Link("Chat", "Whispers", "Look", "UIModifications.parchment_whisper", "Parchment")
	Link("Tooltip", "Tooltip", "Look", "UIModifications.parchment_tooltip", "Parchment")
	Link("Tooltip", "Tooltip", "Look", "BarTextures.texture", "Bar texture")
	Link("Tooltip", "Tooltip", "Look", "UIModifications.barBorder", "Bar border")
	Link("ScreenText", "Combat Text", "Text", "Fonts.style", "Font")
	Link("QuestTracker", "Quest Tracker", "Look", "UIModifications.parchment_questTracker", "Parchment")
	Link("QuestTracker", "Quest Tracker", "Look", "UIModifications.shade_tracker", "UI Shade")
	Link("QuestTracker", "Quest Tracker", "Text", "Fonts.style", "Font")
	Link("QuestTracker", "Quest Tracker", "Layout", "MinimapPanel.width", "Map width")
	Link("QuestTracker", "Objective Tracker", "Look", "UIModifications.parchment_tracker", "Parchment")
	Link("QuestTracker", "Objective Tracker", "Look", "UIModifications.shade_tracker", "UI Shade")
	Link("QuestList", "List", "Look", "UIModifications.QuestLogPanel", "Painted Skin (Quest log)")
end
