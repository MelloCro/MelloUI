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
--                      has that value; `line` is the hint while it has not.
--                      { key, notValue, line } (0.17.0): live while it has
--                      any other value.
--                      { any = { parts }, line } (0.19.4): live while ANY
--                      part holds; { all = { parts }, line }: while every
--                      part does. A part is { key, value } or { key,
--                      notValue }, or itself an any / all (its own line
--                      unused)
--          whenFor     { [id] = when } (0.19.4): on a row with a key per
--                      pick, a `when` for that key alone (it wins over
--                      `when`)
--          also        { [id] = text }: frames with no pick that key reaches
--                      too (the shared hint's tail)
-- Link(page, tab, section, target, label[, extra]): a row naming a setting
-- whose one place is another page (its value and a button to it), at the end
-- of its section; target an id, or { [pick] = id } on a picker page. The
-- button's page, tab and pick are those of the target's own R line. extra
-- (0.19.4): { when = ... }, as a row's: the link sleeps with that line while
-- it does not hold.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local L = {}
MelloUI.ConfigLayout = L

-- (Text-to-Speech: Voice Over's text-to-speech voices, speed and volume, the
-- user 2026-09-29; the other pages have no row there, so they never show it)
L.SECTIONS = { "General", "Look", "Text", "Layout", "Behaviour", "Sound", "Text-to-Speech", "Advanced" }

L.groups = {
	{ entries = { "Home" } },
	{ title = "The look", entries = { "Look", "Windows", "Fader" } },
	{ title = "Frames and bars", entries = { "UnitFrames", "Nameplates", "ActionBars", "Minimap", "BarsMeters",
		"SwingTimers" } },
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
		switchDesc = "The painted reskin AND every feature of UI Modifications: Vendor, Error Messages, Cooldown Timers, Nameplate Tweaks, Chat, Tooltip, Fonts, Dark Mode, Bar Textures, Buffs & Debuffs, Unit Frame Tweaks, FPS / Latency, Class Icons, Bar Values, the game windows' skins, hiding the micro menu, the bag bar and the minimap coordinates, and the world text scale. Off: all of them are off, Edit Layout lets go of the game's windows (they go back to the game's own places), Windows Fade In stops, names are shown in full and Class Coloured Names stops. The palette, the UI Shade, Reduce Motion and MelloUI's notices keep working.",
		tabs = { "General", "Borders", "Fonts", "Dark Mode", "Bar Texture", "Parchment" } },
	Windows = { title = "Windows", icon = "module:CharacterPanel",
		flavour = "The game's windows in the painted look, one at a time: pick a window.",
		tabs = { "Windows" },
		picker = { label = "Window", noun = "window", from = "windows" } },
	-- (0.17.0) which parts fade away, and when they come back (its header
	-- switch: the Fader module's, off by default)
	Fader = { title = "Fader", icon = "module:Fader", module = "Fader",
		tabs = { "Fader", "Frames", "Bars", "Chat & Map" } },
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
		tabs = { "Bars", "Backdrops", "Cooldown Timers" },
		picker = { label = "Bar", noun = "bar", picks = { { "bars", "Action Bars" }, { "micro", "Micro Menu" }, { "bag", "Bag Bar" } } } },
	Minimap = { title = "Minimap", icon = "module:MinimapPanel",
		flavour = "The minimap, its shape, size and border, and the Services bar under it.",
		tabs = { "Minimap", "Services Bar" } },
	-- (0.17.1) the shot bar and the melee bar (its header switch: the Swing
	-- Timers module's, off by default)
	SwingTimers = { title = "Swing Timers", icon = "module:SwingTimers", module = "SwingTimers",
		tabs = { "Swing Timers" } },
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
		tabs = { "Reminders", "Restock", "Vendor", "Widgets" } },
	Gains = { title = "Gains", icon = "module:Gains", module = "Gains",
		tabs = { "Gains" } },
	VoiceOver = { title = "Voice Over", icon = "module:VoiceOver", module = "VoiceOver",
		tabs = { "Reading", "Voices", "Sound Packs", "Widget" } },
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
	fade = { "Fader" },
	mouseover = { "Fader" },
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
	backdrops = { "ActionBars", "Backdrops" },
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
	widgets = { "Reminders", "Widgets" },
	wand = { "SwingTimers" },
	autoshot = { "SwingTimers" },
}

-- (0.16.0: the chat windows' and the tooltips' painted skins and the chat's
-- Dark Mode are set through each page's one Background dropdown, which reads
-- and writes them: no row of their own. Their parchment has its switch on
-- Look > Parchment since 0.19.1, the dropdown showing it all the same)
L.unplaced = {
	["UIModifications.ChatPanel"] = "Chat > Chat Frame > Background",
	["UIModifications.TooltipPanel"] = "Tooltip > Background",
	["DarkMode.chat"] = "Chat > Chat Frame > Background",
}

function L.Define(R, Link)
	-- (0.19.4, the options audit) a kit panel covers its area while the
	-- reskin and its Painted Skin are both on (Kit:IsCovered): what the skin
	-- steps over (Dark Mode, the chat's and the tooltip's tweaks, the unit
	-- frame tweaks) is live while either is off
	local function Uncovered(panel, what)
		return { any = { { key = "UIModifications.reskin", value = false },
			{ key = "UIModifications." .. panel, value = false } },
			line = "Only without the painted " .. what }
	end
	-- the game's own buff and debuff icons: shown unless MelloUI's rows
	-- (Buffs & Debuffs with Your Buffs And Debuffs) stand in their place
	local GAME_AURAS = { any = { { key = "UIModifications.qol_Auras", notValue = true },
		{ key = "Auras.player", value = false } } }
	-- the game's objective tracker: hidden while MelloUI's Quest Tracker is on
	local GAME_TRACKER = { key = "QuestTracker.!enabled", value = false,
		line = "Only for the game's tracker (MelloUI's Quest Tracker off)" }
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
	R("Look", "General", "Text", "UIModifications.nameFormat")
	R("Look", "General", "Text", "UIModifications.classNames", { free = true })
	R("Look", "General", "Text", "Tweaks.textShade", { free = true })
	R("Look", "General", "Behaviour", "UIModifications.reduceMotion", { free = true })
	R("Look", "Borders", "Look", "UIModifications.buttonBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.sideTabBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.barBorder", { picture = true })
	-- (0.19.1, the user 2026-10-04: "all border customization into Borders tab": the borders each element's page
	-- had, here with the kit's; each of those pages links its own)
	R("Look", "Borders", "Look", "UIModifications.nameplateBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.roundBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.auraBorder", { picture = true })
	R("Look", "Borders", "Look", "MinimapPanel.squareBorder", { picture = true, name = "Minimap Square Border",
		when = { key = "MinimapPanel.shape", value = "square", line = "Only for the square map" } })
	R("Look", "Borders", "Look", "Tooltip.classBorder", { name = "Tooltip Class / Reaction Border",
		when = Uncovered("TooltipPanel", "tooltip") })
	R("Look", "Borders", "Look", "Chat.borderAlpha", { name = "Chat Border Opacity" })
	R("Look", "Fonts", "General", "UIModifications.qol_Fonts")
	R("Look", "Fonts", "Text", "Fonts.style")
	R("Look", "Fonts", "Text", "Fonts.sizeText")
	R("Look", "Fonts", "Text", "Fonts.scaleChat")
	R("Look", "Fonts", "Text", "Fonts.sizeTitle")
	R("Look", "Fonts", "Text", "Fonts.outline")
	-- (0.19.1, the user 2026-10-04: "all font sizes, font types and anything thats changing the font somewhere into
	-- this tab": each element's text size and font, named by its element; each of those pages links its own)
	R("Look", "Fonts", "Text", "Fonts.scaleChatParchment", { gate = "UIModifications.parchment_chat" })
	R("Look", "Fonts", "Text", "BarText.fontSize", { name = "Unit Frame Bars: Font Size" })
	R("Look", "Fonts", "Text", "CooldownText.fontRatio", { name = "Cooldown Timers: Text Size" })
	R("Look", "Fonts", "Text", "Stats.fontSize", { name = "FPS / Latency: Font Size" })
	R("Look", "Fonts", "Text", "QuestTracker.textSize", { name = "Quest Tracker: Text Size" })
	R("Look", "Fonts", "Text", "QuestTracker.headerSize", { name = "Quest Tracker: Header Text Size" })
	R("Look", "Fonts", "Text", "Tweaks.noticeOutline", { name = "Notices: Outlined Text", free = true })
	-- (the configurator audit, 2026-10-01: one size per thing on screen --
	-- MelloUI's combat text around you and the numbers over the enemies, the
	-- game's or Your Damage's; the game sizes its own text around you itself:
	-- Scale Damage gone in 0.19.4)
	R("Look", "Fonts", "Text", "CombatText.size", { name = "Combat Text: Text Around You", when = { key = "CombatText.style", notValue = "game", line = "Only for the Lanes, Feed and Classic styles" } })
	R("Look", "Fonts", "Text", "Tweaks.worldTextScale", { name = "Combat Text: Numbers Over Enemies" })
	R("Look", "Fonts", "Text", "CombatText.titleNotices", { name = "Combat Text: Notices In Title Font", when = { key = "CombatText.style", notValue = "game", line = "Only for the Lanes, Feed and Classic styles" } })
	R("Look", "Fonts", "Advanced", "Fonts.fontText")
	R("Look", "Fonts", "Advanced", "Fonts.fontChat")
	R("Look", "Fonts", "Advanced", "Fonts.fontTitle")
	R("Look", "Fonts", "Advanced", "Fonts.fontChatText")
	R("Look", "Fonts", "Advanced", "Fonts.fontChatParchment", { gate = "UIModifications.parchment_chat" })
	R("Look", "Fonts", "Advanced", "Fonts.fontDamage")
	R("Look", "Dark Mode", "General", "UIModifications.qol_DarkMode")
	R("Look", "Dark Mode", "Look", "DarkMode.shade")
	R("Look", "Dark Mode", "Look", "DarkMode.kitShade")
	R("Look", "Dark Mode", "Look", "DarkMode.desaturate")
	R("Look", "Bar Texture", "General", "UIModifications.qol_BarTextures")
	R("Look", "Bar Texture", "Look", "BarTextures.texture")
	-- the health bars' colour reaches the unit frames AND the nameplates
	-- (their descs; RecolorHealthBar): global
	R("Look", "Bar Texture", "Look", "BarTextures.healthColor")
	R("Look", "Bar Texture", "Look", "BarTextures.overrideThreat",
		{ when = { key = "BarTextures.healthColor", notValue = "green", line = "Not with the Green (Blizzard) colour" } })
	R("Look", "Bar Texture", "Look", "BarTextures.executeRange")
	R("Look", "Bar Texture", "Look", "BarTextures.executeBelow")
	R("Look", "Parchment", "Look", "UIModifications.parchment_tracker", { when = GAME_TRACKER })
	R("Look", "Parchment", "Look", "UIModifications.parchment_questTracker")
	-- (0.19.1, the user 2026-10-04: "any Parchment Enable/Disable into the Parchment tab": the chat's and the
	-- tooltips', live while their painted skin is on -- their Background dropdowns show it too)
	R("Look", "Parchment", "Look", "UIModifications.parchment_chat", { gate = "UIModifications.ChatPanel" })
	R("Look", "Parchment", "Look", "UIModifications.parchment_whisper", { gate = "UIModifications.ChatPanel" })
	R("Look", "Parchment", "Look", "UIModifications.parchment_meter")
	R("Look", "Parchment", "Look", "UIModifications.parchment_character")
	R("Look", "Parchment", "Look", "UIModifications.parchment_tooltip", { gate = "UIModifications.TooltipPanel" })
	R("Look", "Parchment", "Look", "UIModifications.parchment_dialog")

	-- Windows (the picker: the registry's windows). A kit panel's row here is
	-- live on the CURRENT pick's Painted Skin, not on the panel owning the
	-- key: the Bank wears the Bags' keys, and Quality Gems stays live on the
	-- Bank with the Bags' skin off
	-- (0.19.0) the bag window by kind, MelloUI's own (either look; works with UI Modifications off)
	R("Windows", "Windows", "General", { BackpackPanel = "BagWindow.!enabled" }, { name = "Bags by Kind", free = true })
	-- (its kinds, the user's picks of 2026-10-04; its layout's below, after Bag Slots on Bag Window)
	for _, key in ipairs({ "recent", "recentFor", "gear", "quest", "consumables", "junk", "trade", "splitTrade" }) do
		R("Windows", "Windows", "General", { BackpackPanel = "BagWindow." .. key }, { free = true })
	end
	R("Windows", "Windows", "Look", { from = "windows" }, { name = "Painted Skin" })
	-- (0.19.4, the options audit: under the whole window's parchment the character window's body is its own stone)
	R("Windows", "Windows", "Look", { CharacterPanel = "CharacterPanel.windowBackground", BackpackPanel = "BackpackPanel.windowBackground", BankPanel = "BackpackPanel.windowBackground" }, { name = "Window Background", picture = true,
		whenFor = { ["CharacterPanel.windowBackground"] = { key = "UIModifications.parchment_character", notValue = "window", line = "Not with the whole window on parchment" } } })
	R("Windows", "Windows", "Look", { BackpackPanel = "BackpackPanel.itemBackground", BankPanel = "BackpackPanel.itemBackground", GuildBankPanel = "BackpackPanel.itemBackground" }, { name = "Item Slot Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.bookBackground" }, { name = "Book Page Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.pageBackground" }, { name = "Crafting Page Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.listBackground" }, { name = "Recipe List Background", picture = true })
	R("Windows", "Windows", "Look", { BackpackPanel = "BackpackPanel.qualityGems", BankPanel = "BackpackPanel.qualityGems", GuildBankPanel = "BackpackPanel.qualityGems" }, { name = "Quality Gems" })
	R("Windows", "Windows", "Look", { BackpackPanel = "BackpackPanel.greyJunk", BankPanel = "BackpackPanel.greyJunk", GuildBankPanel = "BackpackPanel.greyJunk" }, { name = "Grey Out Junk" })
	R("Windows", "Windows", "Layout", { BackpackPanel = "Tweaks.bagSlotsOnBags" }, { name = "Bag Slots on Bag Window" })
	for _, key in ipairs({ "columns", "itemSize", "foldEmpty", "sortBy" }) do
		R("Windows", "Windows", "Layout", { BackpackPanel = "BagWindow." .. key }, { free = true })
	end
	R("Windows", "Windows", "Behaviour", { BackpackPanel = "Discard.bagButton", LootPanel = "Discard.lootButton" }, { name = "Discard Button" })
	R("Windows", "Windows", "Behaviour", { BackpackPanel = "Discard.keepWorth", LootPanel = "Discard.keepWorth" }, { name = "Never Throw Away Items Worth" })
	-- (0.19.4, the options audit: UI Modifications' own, working without the
	-- Fader, so here, not under the Fader's switch; the Fader links it)
	R("Windows", "Windows", "Behaviour", "UIModifications.fadeWindows", { wide = "every window" })

	-- Unit Frames (the picker: Player ... Personal Resource)
	R("UnitFrames", "Frame", "General", "UIModifications.qol_UnitFrames", { only = { "player", "target", "focus", "pet", "party" } })
	R("UnitFrames", "Frame", "General", "UIModifications.qol_ClassIcons", { only = { "player", "target", "focus", "party" } })
	R("UnitFrames", "Frame", "Look", { player = "UIModifications.UnitFramePanel", target = "UIModifications.UnitFramePanel", focus = "UIModifications.UnitFramePanel", pet = "UIModifications.UnitFramePanel", party = "UIModifications.UnitFramePanel", raid = "UIModifications.RaidFramePanel", castbars = "UIModifications.CastBarPanel" }, { name = "Painted Skin" })
	R("UnitFrames", "Frame", "Look", { player = "DarkMode.unitframes", target = "DarkMode.unitframes", focus = "DarkMode.unitframes", pet = "DarkMode.unitframes", party = "DarkMode.unitframes", castbars = "DarkMode.castbar", personal = "DarkMode.personal" }, { name = "Dark Mode", also = { ["DarkMode.unitframes"] = "boss and target of target" },
		whenFor = { ["DarkMode.unitframes"] = Uncovered("UnitFramePanel", "unit frames"), ["DarkMode.castbar"] = Uncovered("CastBarPanel", "cast bars") } })
	-- (0.19.4, the options audit: the unit frame skin fades or replaces the
	-- same art and puts the writes back)
	local UF = Uncovered("UnitFramePanel", "unit frames")
	R("UnitFrames", "Frame", "Look", "UnitFrames.frameAlpha", { only = { "player", "target", "focus", "pet", "party" }, when = UF })
	R("UnitFrames", "Frame", "Look", "UnitFrames.hideReputationColor", { only = { "target", "focus" }, when = UF })
	R("UnitFrames", "Frame", "Look", "UnitFrames.hideCombatGlow", { only = { "player", "target", "focus", "pet", "party" }, when = UF })
	R("UnitFrames", "Frame", "Look", "UnitFrames.hideStatusGlow", { only = { "player", "pet" }, when = UF })
	R("UnitFrames", "Frame", "Look", "ClassIcons.portraits", { only = { "player", "target", "focus", "party" } })
	R("UnitFrames", "Frame", "Look", "UnitFramePanel.marks", { only = { "target", "focus" } })
	R("UnitFrames", "Frame", "Text", "UnitFrames.centerNames", { only = { "player", "target", "focus" }, when = UF })
	R("UnitFrames", "Bars", "General", "UIModifications.qol_BarText", { only = { "player", "target", "focus" } })
	-- (0.19.0) incoming heals and the debuff glow: one setting each for every frame (HealerFrames)
	-- (0.19.4: incoming heals on MelloUI's three frames only, the bar
	-- background on the unit frames the skin draws -- not the raid frames,
	-- cast bars or personal resource)
	R("UnitFrames", "Bars", "General", "HealerFrames.incomingHeals", { only = { "player", "target", "focus" },
		also = { ["HealerFrames.incomingHeals"] = "their targets" } })
	R("UnitFrames", "Bars", "Look", { player = "BarTextures.unitframes", target = "BarTextures.unitframes", focus = "BarTextures.unitframes", pet = "BarTextures.unitframes", party = "BarTextures.unitframes", raid = "BarTextures.raidframes", castbars = "BarTextures.castbars", personal = "BarTextures.personal" }, { name = "Bar Texture", also = { ["BarTextures.unitframes"] = "boss and target of target" } })
	R("UnitFrames", "Bars", "Look", "UnitFramePanel.barBackground", { only = { "player", "target", "focus", "pet", "party" },
		also = { ["UnitFramePanel.barBackground"] = "target of target" } })
	R("UnitFrames", "Bars", "Look", "UnitFramePanel.barBackgroundAlpha", { only = { "player", "target", "focus", "pet", "party" },
		also = { ["UnitFramePanel.barBackgroundAlpha"] = "target of target" },
		when = { key = "UnitFramePanel.barBackground", notValue = "none", line = "Not with the None background" } })
	R("UnitFrames", "Bars", "Text", { player = "BarText.player", target = "BarText.target", focus = "BarText.focus" }, { name = "Values On This Frame" })
	R("UnitFrames", "Bars", "Text", "BarText.health", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Text", "BarText.power", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Text", "BarText.format", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Text", "BarText.showMax", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Layout", "BarText.position", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Layout", "BarText.offsetX", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Bars", "Layout", "BarText.offsetY", { only = { "player", "target", "focus" } })
	R("UnitFrames", "Buffs & Debuffs", "General", "UIModifications.qol_Auras", { only = { "player", "target" } })
	R("UnitFrames", "Buffs & Debuffs", "General", { player = "Auras.player", target = "Auras.target" }, { name = "Buffs & Debuffs On This Frame" })
	R("UnitFrames", "Buffs & Debuffs", "General", "HealerFrames.debuffGlow", { wide = "every frame" })
	-- (0.19.4: Dark Mode reaches the game's own icons of yours, never the
	-- target's; with MelloUI's rows in their place it has nothing to darken.
	-- Keep Dispel Colours also serves the Cooldown Manager's icons)
	R("UnitFrames", "Buffs & Debuffs", "Look", "DarkMode.auras", { only = { "player" },
		when = { any = GAME_AURAS.any, line = "Only on the game's own icons (Buffs & Debuffs or Your Buffs And Debuffs off)" } })
	R("UnitFrames", "Buffs & Debuffs", "Look", "DarkMode.keepDispelColor", { only = { "player" },
		when = { any = { GAME_AURAS, { key = "DarkMode.cooldowns", value = true } },
			line = "Only on the game's own icons (Buffs & Debuffs or Your Buffs And Debuffs off) or the Cooldown Manager's" } })
	R("UnitFrames", "Buffs & Debuffs", "Layout", { player = "Auras.playerSize", target = "Auras.targetSize" }, { name = "Icon Size" })
	R("UnitFrames", "Buffs & Debuffs", "Layout", "Auras.playerPerRow", { only = { "player" } })
	R("UnitFrames", "Buffs & Debuffs", "Layout", "Auras.playerColumn", { only = { "player" } })
	R("UnitFrames", "Buffs & Debuffs", "Behaviour", "Auras.targetOnlyMine", { only = { "target" } })
	R("UnitFrames", "Buffs & Debuffs", "Behaviour", "HealerFrames.debuffGlowShows", { wide = "every frame" })

	-- Nameplates (tabs: the parts differ)
	R("Nameplates", "Plates", "General", "Nameplates.threatLine")
	R("Nameplates", "Plates", "General", "Nameplates.comboPoints")
	R("Nameplates", "Plates", "General", "Nameplates.comboSize")   -- (under its switch: the user, 2026-10-04)
	R("Nameplates", "Plates", "Look", "UIModifications.NameplatePanel", { name = "Painted Skin" })
	R("Nameplates", "Plates", "Look", "DarkMode.nameplates", { name = "Dark Mode", when = Uncovered("NameplatePanel", "nameplates") })
	R("Nameplates", "Plates", "Look", "BarTextures.nameplates", { name = "Bar Texture" })
	R("Nameplates", "Plates", "Look", "NameplatePanel.marks")
	R("Nameplates", "Plates", "Text", "NameplatePanel.nameShade")
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
	-- (the action bar skin covers the bars, the micro menu, the bag bar and
	-- the XP bars: ActionBarPanel)
	R("ActionBars", "Bars", "Look", { bars = "DarkMode.actionbars", micro = "DarkMode.micromenu", bag = "DarkMode.micromenu" }, { name = "Dark Mode",
		when = Uncovered("ActionBarPanel", "action bars") })
	R("ActionBars", "Bars", "Look", "DarkMode.gryphons", { only = { "bars" }, when = Uncovered("ActionBarPanel", "action bars") })
	R("ActionBars", "Bars", "Behaviour", "Tweaks.bagBarFold", { only = { "bag" },
		when = { key = "Tweaks.hideBagBar", value = false, line = "Only while the bag bar shows" } })
	-- (0.18.5) each element's backdrop, one list whatever the pick (the user,
	-- 2026-10-04: "a list on Action Bars"); the looks stay on Bars > Look
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBar1")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBar2")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBar3")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBar4")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBar5")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBar6")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBar7")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBar8")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropStance")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropPet")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropPossess")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropMicro")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropBags")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropXP")
	R("ActionBars", "Backdrops", "General", "ActionBarPanel.backdropXP2")
	R("ActionBars", "Cooldown Timers", "General", "UIModifications.qol_CooldownText", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "General", "CooldownText.actionBars", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Text", "CooldownText.tenths", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Text", "CooldownText.colorByTime", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Behaviour", "CooldownText.minDuration", { only = { "bars" } })

	-- Minimap (its Services bar a tab: Services has no header switch here)
	R("Minimap", "Minimap", "General", "Tweaks.hideMinimapCoords")
	R("Minimap", "Minimap", "Look", "UIModifications.MinimapPanel", { name = "Painted Skin" })
	R("Minimap", "Minimap", "Look", "MinimapPanel.shape", { picture = true })
	R("Minimap", "Minimap", "Look", "DarkMode.minimap", { name = "Dark Mode", when = Uncovered("MinimapPanel", "minimap") })
	R("Minimap", "Minimap", "Layout", "MinimapPanel.width")
	R("Minimap", "Minimap", "Layout", "MinimapPanel.height", { when = { key = "MinimapPanel.shape", value = "square", line = "Only for the square map (the round map takes Width)" } })
	R("Minimap", "Services Bar", "General", "Services.!enabled", { name = "Services Bar" })
	R("Minimap", "Services Bar", "General", "Services.showBar")
	R("Minimap", "Services Bar", "General", "Services.showButton")
	R("Minimap", "Services Bar", "Look", "Services.roundIcons")
	R("Minimap", "Services Bar", "Layout", "Services.buttonLayout")
	R("Minimap", "Services Bar", "Layout", "Services.barOffset")
	R("Minimap", "Services Bar", "Layout", "MinimapPanel.servicesMerge",
		{ when = { key = "MinimapPanel.shape", value = "square", line = "Only for the square map" } })

	-- Bars & Meters
	R("BarsMeters", "XP & Reputation", "Look", "BarTextures.statusbars", { name = "Bar Texture" })
	R("BarsMeters", "XP & Reputation", "Look", "DarkMode.statusbars", { name = "Dark Mode", when = Uncovered("ActionBarPanel", "action bars") })
	R("BarsMeters", "Cooldown Manager", "Look", "BarTextures.cooldowns", { name = "Bar Texture" })
	R("BarsMeters", "Cooldown Manager", "Look", "DarkMode.cooldowns", { name = "Dark Mode" })
	-- (0.17.0: MelloUI's meter replaces the game's; its switch heads the tab)
	R("BarsMeters", "Damage Meter", "General", "Meter.!enabled", { name = "Use MelloUI's Damage Meter (replaces the game's)" })
	R("BarsMeters", "Damage Meter", "General", "Meter.values")
	R("BarsMeters", "Damage Meter", "General", "Meter.party")
	R("BarsMeters", "Damage Meter", "General", "Meter.raid")
	R("BarsMeters", "Damage Meter", "General", "Meter.bar")
	R("BarsMeters", "Damage Meter", "General", "Meter.summary")
	R("BarsMeters", "Damage Meter", "General", "Meter.history")
	-- (the game's meter windows: never shown while MelloUI's meter is on)
	R("BarsMeters", "Damage Meter", "Look", "UIModifications.DamageMeterPanel", { name = "Painted Skin",
		when = { key = "Meter.!enabled", value = false, line = "Only for the game's meter (MelloUI's meter off)" } })
	R("BarsMeters", "Damage Meter", "Layout", "Meter.pins")
	R("BarsMeters", "Damage Meter", "Layout", "Meter.barWidth")
	R("BarsMeters", "Damage Meter", "Layout", "Meter.barHeight")
	R("BarsMeters", "Damage Meter", "Behaviour", "Meter.metric")
	R("BarsMeters", "Damage Meter", "Behaviour", "Meter.historySize")
	R("BarsMeters", "FPS / Latency", "General", "UIModifications.qol_Stats")
	R("BarsMeters", "FPS / Latency", "General", "Stats.showFps")
	R("BarsMeters", "FPS / Latency", "General", "Stats.showLatency")
	R("BarsMeters", "FPS / Latency", "General", "Stats.worldLatency")
	R("BarsMeters", "FPS / Latency", "Layout", "Stats.offsetX")
	R("BarsMeters", "FPS / Latency", "Layout", "Stats.offsetY")
	R("BarsMeters", "FPS / Latency", "Behaviour", "Stats.interval")

	-- Chat
	R("Chat", "Chat Frame", "General", "UIModifications.qol_Chat")
	R("Chat", "Chat Frame", "Look", "Chat.background")
	local NOT_NONE = { key = "Chat.background", notValue = "none", line = "Not with the None background" }
	R("Chat", "Chat Frame", "Look", "Chat.windowAlphaOn", { when = NOT_NONE })
	R("Chat", "Chat Frame", "Look", "Chat.windowAlpha", { when = NOT_NONE })
	-- (0.19.4: the painted chat holds the input box and the tabs itself)
	R("Chat", "Chat Frame", "Look", "Chat.hideEditBox", { when = Uncovered("ChatPanel", "chat") })
	R("Chat", "Chat Frame", "Look", "Chat.hideTabs", { when = Uncovered("ChatPanel", "chat") })
	R("Chat", "Chat Frame", "Look", "Chat.chatButtons")
	R("Chat", "Chat Frame", "Layout", "Chat.editBoxTop")
	R("Chat", "Chat Frame", "Behaviour", "Chat.smoothScroll")
	R("Chat", "Messages", "Text", "Chat.shortChannels")
	R("Chat", "Messages", "Text", "Chat.hideBrackets")
	R("Chat", "Messages", "Text", "Chat.nameShade")
	-- (free: read by MelloUI:Notice with Tweaks, and UI Modifications, off)
	R("Chat", "Messages", "Behaviour", "Tweaks.chatNotices", { free = true })
	R("Chat", "Whispers", "General", "Chat.whisperPopup")

	-- Tooltip
	R("Tooltip", "Tooltip", "General", "UIModifications.qol_Tooltip")
	R("Tooltip", "Tooltip", "Look", "Tooltip.background")
	R("Tooltip", "Tooltip", "Look", "Tooltip.backdropAlpha", { when = { key = "Tooltip.background", value = "dark", line = "Only for the Dark background" } })
	-- (0.19.4: Hide Health Bar, on by default, leaves nothing to dress)
	local HEALTH_BAR = { key = "Tooltip.hideHealthBar", value = false, line = "Only while the health bar shows (Hide Health Bar off)" }
	R("Tooltip", "Tooltip", "Look", "BarTextures.tooltip", { name = "Bar Texture", when = HEALTH_BAR })
	R("Tooltip", "Tooltip", "Look", "Tooltip.classHealth", { when = HEALTH_BAR })
	R("Tooltip", "Tooltip", "Look", "Tooltip.hideHealthBar")
	R("Tooltip", "Tooltip", "Layout", "Tooltip.anchor")
	R("Tooltip", "Tooltip", "Layout", "Tooltip.scale")
	R("Tooltip", "Tooltip", "Behaviour", "Tooltip.hideInCombat")
	R("Tooltip", "Tooltip", "Behaviour", "Tooltip.fadeDelay")
	R("Tooltip", "Tooltip", "Behaviour", "QuestList.tipQuestItems")
	R("Tooltip", "Tooltip", "Behaviour", "QuestList.tipTurnIn")

	-- Screen Text (the notices' rows free: Core reads them, Core/Notice.lua
	-- and Core/CentreText.lua, with Tweaks and UI Modifications off)
	R("ScreenText", "Notices", "General", "Tweaks.noticeOnScreen", { free = true })
	R("ScreenText", "Notices", "General", "Tweaks.noticeToChat", { free = true })
	R("ScreenText", "Notices", "Sound", "Tweaks.noticeSounds", { free = true })
	R("ScreenText", "Error Messages", "General", "UIModifications.qol_ErrorFilter")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.resources")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.cooldowns")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.range")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.targeting")
	R("ScreenText", "Error Messages", "Behaviour", "ErrorFilter.busy")
	-- (0.17.0) Combat Text: MelloUI's text over your character (its module's
	-- switch the tab's first row), then the engine's numbers over the enemies
	-- (their font and size, and the game's own switches for them)
	R("ScreenText", "Combat Text", "General", "CombatText.!enabled", { name = "MelloUI Combat Text" })
	R("ScreenText", "Combat Text", "General", "CombatText.style")
	R("ScreenText", "Combat Text", "General", "CombatText.dealt")
	R("ScreenText", "Combat Text", "General", "CombatText.#Preview")
	R("ScreenText", "Combat Text", "Look", "CombatText.shadeSize")
	-- (its text sizes and fonts: Look > Fonts since 0.19.1, linked below)
	R("ScreenText", "Combat Text", "Layout", "CombatText.spread",
		{ when = { key = "CombatText.style", value = "lanes", line = "Only for the Lanes style" } })
	R("ScreenText", "Combat Text", "Layout", "CombatText.lines",
		{ when = { key = "CombatText.style", notValue = "game", line = "Only for the Lanes, Feed and Classic styles" } })
	-- (MelloUI's kinds sleep on Game, as Most Lines; the game's four switches
	-- for the numbers over the enemies never)
	local MELLO_STYLES = { key = "CombatText.style", notValue = "game", line = "Only for the Lanes, Feed and Classic styles" }
	for _, key in ipairs({ "taken", "heals", "notices", "avoid", "resource", "combat", "reputation",
		"enemyDamage", "enemyPeriodic", "enemyPet", "enemyHealing" }) do
		R("ScreenText", "Combat Text", "Behaviour", "CombatText." .. key,
			key:sub(1, 5) ~= "enemy" and { when = MELLO_STYLES } or nil)
	end

	-- (0.17.0) The Fader (header: its module's switch): how it fades, then
	-- the elements, each one Show choice; Unit Frames' Fade Out Of Combat
	-- (carried over: Core.lua's MergeSettings) and the chat's Tabs Only On
	-- Mouseover moved here, a Link row where it was (Windows Fade In went
	-- back to Windows in 0.19.4: it works without the Fader; linked here)
	R("Fader", "Fader", "General", "Fader.#Fade Everything")
	R("Fader", "Fader", "General", "Fader.#Fade Nothing")
	R("Fader", "Fader", "Look", "Fader.alpha")
	R("Fader", "Fader", "Behaviour", "Fader.after")
	R("Fader", "Fader", "Behaviour", "Fader.speed")
	R("Fader", "Fader", "Behaviour", "Fader.target")
	R("Fader", "Fader", "Behaviour", "Fader.mouse")
	for _, key in ipairs({ "player", "petToo", "target", "party", "raid", "buffs", "reminders" }) do
		R("Fader", "Frames", "General", key == "petToo" and "Fader.petToo" or ("Fader.show_" .. key),
			key == "petToo" and { when = { key = "Fader.show_player", notValue = "always",
				line = "Only while the Player Frame fades" } } or nil)
	end
	-- (0.19.4: a bar Hide This Bar parks has nothing to fade)
	local PARKED = {
		micro = { when = { key = "Tweaks.hideMicroMenu", value = false, line = "Hidden on Action Bars (Hide This Bar)" } },
		bags = { when = { key = "Tweaks.hideBagBar", value = false, line = "Hidden on Action Bars (Hide This Bar)" } },
	}
	for _, key in ipairs({ "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "stance", "micro", "bags", "xp" }) do
		R("Fader", "Bars", "General", "Fader.show_" .. key, PARKED[key])
	end
	R("Fader", "Chat & Map", "General", "Fader.show_chat")
	R("Fader", "Chat & Map", "General", "Chat.tabsOnMouseover", { when = Uncovered("ChatPanel", "chat") })
	for _, key in ipairs({ "minimap", "tracker", "objectives", "widgets", "route" }) do
		R("Fader", "Chat & Map", "General", "Fader.show_" .. key, key == "objectives" and { when = GAME_TRACKER } or nil)
	end

	-- (0.17.1) Swing Timers (header: its module's switch): which bars, their
	-- look, their size, when they show
	R("SwingTimers", "Swing Timers", "General", "SwingTimers.shot")
	R("SwingTimers", "Swing Timers", "General", "SwingTimers.melee")
	R("SwingTimers", "Swing Timers", "General", "SwingTimers.offhand")
	R("SwingTimers", "Swing Timers", "Look", "SwingTimers.look")
	R("SwingTimers", "Swing Timers", "Text", "SwingTimers.text",
		{ when = { key = "SwingTimers.look", value = "castbar", line = "Only for the Cast Bar look" } })
	R("SwingTimers", "Swing Timers", "Layout", "SwingTimers.width")
	R("SwingTimers", "Swing Timers", "Layout", "SwingTimers.height")
	R("SwingTimers", "Swing Timers", "Behaviour", "SwingTimers.show")

	-- Quest Tracker (header: its module's switch)
	R("QuestTracker", "Quest Tracker", "Look", "UIModifications.questTrackerKit", { name = "Painted Skin" })
	-- (0.19.4: Match Minimap needs the Minimap Kit -- UI Modifications, the
	-- reskin and the minimap's Painted Skin; Width is live while either is off)
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.matchMinimap", { when = { all = {
		{ key = "UIModifications.!enabled", value = true }, { key = "UIModifications.reskin", value = true },
		{ key = "UIModifications.MinimapPanel", value = true } }, line = "Only with the painted minimap (the Minimap Kit)" } })
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.width", { when = { any = {
		{ key = "QuestTracker.matchMinimap", value = false }, { key = "UIModifications.!enabled", value = false },
		{ key = "UIModifications.reskin", value = false }, { key = "UIModifications.MinimapPanel", value = false } },
		line = "Only while the tracker does not match the minimap (Match Minimap or the Minimap Kit off)" } })
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.maxHeight")
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.#Reset Position")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.itemButtons")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.nearestFirst")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.showDistance")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.turnInLine")
	R("QuestTracker", "Quest Tracker", "Behaviour", "QuestTracker.scrollStep")
	R("QuestTracker", "Objective Tracker", "Look", "UIModifications.TrackerPanel", { name = "Painted Skin", when = GAME_TRACKER })

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
	R("Route", "Route", "Look", "Route.lineWidth")
	R("Route", "Route", "Behaviour", "Route.arrive")
	R("Route", "Route", "Behaviour", "Route.learn")
	R("Route", "Arrow & Marker", "General", "Route.arrow")
	R("Route", "Arrow & Marker", "General", "Route.worldMarker")
	R("Route", "Arrow & Marker", "General", "Route.routeBeam")
	R("Route", "Arrow & Marker", "Sound", "Route.markerSound")
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
	R("Reminders", "Restock", "General", "Restock.below")
	R("Reminders", "Restock", "General", "Restock.shopPanel")
	R("Reminders", "Restock", "General", "Restock.#Restock List")
	R("Reminders", "Vendor", "General", "UIModifications.qol_Vendor")
	R("Reminders", "Vendor", "Behaviour", "Vendor.autoRepair")
	R("Reminders", "Vendor", "Behaviour", "Vendor.guildRepair")
	R("Reminders", "Vendor", "Behaviour", "Vendor.autoSell")
	R("Reminders", "Vendor", "Behaviour", "Vendor.report")
	-- (0.16.0: the widget column's users and three more portrait reminders,
	-- Modules/Widgets.lua; the column's lock is the Reminders module's)
	R("Reminders", "Widgets", "General", "Widgets.!enabled", { name = "Widgets" })
	for _, key in ipairs({ "loot", "corpse", "timed", "summon", "resurrect", "ready", "threat", "whisper", "pet", "auction",
		"craft", "cooldown", "questItem", "healer", "rare", "rareSound",
		"bags", "bagsAt", "talents", "wellfed", "weapon", "buffs", "groupBuffs" }) do
		-- (0.19.4: the whisper row is raised by Chat's popup alone)
		R("Reminders", "Widgets", "General", "Widgets." .. key, key == "whisper"
			and { when = { key = "Chat.whisperPopup", value = true, line = "Needs Chat's Whisper Popup Window" } } or nil)
	end
	R("Reminders", "Widgets", "Layout", "Reminders.widgetLock")
	R("Reminders", "Widgets", "Layout", "Reminders.widgetMax")

	-- Gains (header: its module's switch)
	R("Gains", "Gains", "General", "Gains.skills")
	R("Gains", "Gains", "General", "Gains.values")
	R("Gains", "Gains", "General", "Gains.items")
	R("Gains", "Gains", "General", "Gains.bought")
	R("Gains", "Gains", "General", "Gains.junk")
	-- (0.17.0) money, the other currencies and the names' quality colour
	R("Gains", "Gains", "General", "Gains.money")
	R("Gains", "Gains", "General", "Gains.currencies")
	R("Gains", "Gains", "Look", "Gains.qualityNames")
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
	-- (text-to-speech only: a recorded line keeps its own voice, pace and
	-- volume, so these sleep while no line is read by text-to-speech: Read
	-- Unvoiced Lines off with Use Voice Packs on (0.19.4: with the packs off
	-- every line is text-to-speech); the race pitch and speed profiles are
	-- gone, user 2026-09-29)
	local TTS = { when = { any = { { key = "VoiceOver.speakUnrecorded", value = true },
		{ key = "VoiceOver.soundPacks", value = false } },
		line = "Only for text-to-speech (Read Unvoiced Lines on, or Use Voice Packs off)" } }
	R("VoiceOver", "Voices", "Text-to-Speech", "VoiceOver.maleVoice", TTS)
	R("VoiceOver", "Voices", "Text-to-Speech", "VoiceOver.femaleVoice", TTS)
	R("VoiceOver", "Voices", "Text-to-Speech", "VoiceOver.rate", TTS)
	R("VoiceOver", "Voices", "Text-to-Speech", "VoiceOver.volume", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_human", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_elf", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_dwarf", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_gnome", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_orc", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_troll", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_tauren", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_undead", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_goblin", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_ogre", TTS)
	R("VoiceOver", "Voices", "Advanced", "VoiceOver.voice_monster", TTS)
	R("VoiceOver", "Sound Packs", "General", "VoiceOver.soundPacks")
	R("VoiceOver", "Sound Packs", "General", "VoiceOver.speakUnrecorded")
	R("VoiceOver", "Sound Packs", "General", "VoiceOver.preferRecordings")
	R("VoiceOver", "Sound Packs", "General", "VoiceOver.collectLines")
	R("VoiceOver", "Sound Packs", "Sound", "VoiceOver.soundChannel")
	-- (0.16.0: the widget in MelloUI's widget column; its lock is the
	-- column's, a link row, and its size is Edit Layout's wheel)
	R("VoiceOver", "Widget", "General", "VoiceOver.overlay")
	R("VoiceOver", "Widget", "General", "VoiceOver.overlayPortrait")
	R("VoiceOver", "Widget", "General", "VoiceOver.overlaySubtitles")
	R("VoiceOver", "Widget", "General", "VoiceOver.overlayCompact")

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
	Link("Windows", "Windows", "Look", "UIModifications.buttonBorder", "Button border")
	Link("Windows", "Windows", "Look", "UIModifications.sideTabBorder", "Side tab border")
	Link("Windows", "Windows", "Look", "UIModifications.roundBorder", "Round border")
	Link("VoiceOver", "Widget", "Layout", "Reminders.widgetLock", "Lock the widgets")
	Link("Reminders", "Widgets", "General", "Meter.summary", "Fight summary")
	-- (0.17.0: the fades moved to the Fader)
	Link("UnitFrames", "Frame", "Behaviour", { player = "Fader.show_player", pet = "Fader.petToo",
		target = "Fader.show_target", party = "Fader.show_party", raid = "Fader.show_raid" }, "Fade (Fader)")
	Link("Fader", "Fader", "Behaviour", "UIModifications.fadeWindows", "Windows fade in")
	Link("Chat", "Chat Frame", "Behaviour", "Chat.tabsOnMouseover", "Tabs only on mouseover",
		{ when = Uncovered("ChatPanel", "chat") })
	-- (0.16.0: the merged settings, from where their members were)
	Link("Chat", "Messages", "Text", "UIModifications.nameFormat", "Names")
	Link("Chat", "Messages", "Text", "UIModifications.classNames", "Class coloured names")
	Link("Tooltip", "Tooltip", "Text", "UIModifications.classNames", "Class coloured names")
	Link("ScreenText", "Notices", "Text", "Tweaks.textShade", "Text shade")
	Link("Route", "Arrow & Marker", "Text", "Tweaks.textShade", "Text shade")
	Link("Route", "Route", "General", "Tweaks.noticeOnScreen", "On-screen notices")
	Link("Route", "Route", "Sound", "Tweaks.noticeSounds", "Notice sounds")
	-- (0.19.4, the options audit: the name band keeps its own strength; the UI Shade reaches the plates on Whole plate only)
	Link("Nameplates", "Plates", "Look", "UIModifications.uiShadeStrength", "Shade strength", { when = { all = {
		{ key = "NameplatePanel.nameShade", value = "plate" }, { key = "UIModifications.uiShade", value = true } },
		line = "Only with Name Shade: Whole plate and the UI Shade on (the name band keeps its own)" } })
	Link("UnitFrames", "Frame", "Look", { player = "UIModifications.shade_unitframes", target = "UIModifications.shade_unitframes", focus = "UIModifications.shade_unitframes", pet = "UIModifications.shade_unitframes", party = "UIModifications.shade_unitframes", castbars = "UIModifications.shade_castbars" }, "UI Shade")
	Link("UnitFrames", "Frame", "Text", "UIModifications.nameFormat", "Names")
	Link("UnitFrames", "Bars", "Look", "BarTextures.texture", "Bar texture")
	Link("UnitFrames", "Bars", "Look", "BarTextures.healthColor", "Health bar colour")
	Link("UnitFrames", "Bars", "Look", "UIModifications.barBorder", "Bar border")
	Link("UnitFrames", "Buffs & Debuffs", "Look", { player = "UIModifications.shade_buffs" }, "UI Shade")
	-- (0.19.4: the aura border is worn by MelloUI's own rows only)
	Link("UnitFrames", "Buffs & Debuffs", "Look", "UIModifications.auraBorder", "Aura border", { when = { all = {
		{ key = "UIModifications.qol_Auras", value = true },
		{ any = { { key = "Auras.player", value = true }, { key = "Auras.target", value = true } } } },
		line = "Only on MelloUI's own buff rows (Buffs & Debuffs on)" } })
	Link("Nameplates", "Plates", "Look", "UIModifications.uiShade", "UI Shade", { when = { key = "NameplatePanel.nameShade", value = "plate",
		line = "Only with Name Shade: Whole plate (the name band keeps its own)" } })
	Link("Nameplates", "Plates", "Look", "BarTextures.healthColor", "Health bar colour")
	Link("Nameplates", "Plates", "Text", "UIModifications.nameFormat", "Names")
	Link("Nameplates", "Auras & Icons", "Look", "UIModifications.auraBorder", "Aura border", { when = { all = {
		{ key = "UIModifications.qol_Auras", value = true }, { key = "Auras.nameplates", value = true } },
		line = "Only on MelloUI's own debuff rows (Buffs & Debuffs and Enemy Nameplates on)" } })
	Link("ActionBars", "Bars", "Look", "UIModifications.shade_actionbars", "UI Shade")
	Link("ActionBars", "Bars", "Look", "UIModifications.buttonBorder", "Button border")
	Link("Minimap", "Minimap", "Look", "UIModifications.shade_minimap", "UI Shade")
	Link("BarsMeters", "XP & Reputation", "Look", "UIModifications.barBorder", "Bar border")
	Link("BarsMeters", "Cooldown Manager", "Look", "DarkMode.keepDispelColor", "Keep dispel colours")
	Link("BarsMeters", "Damage Meter", "Look", "UIModifications.parchment_meter", "Parchment")
	Link("BarsMeters", "Event Widgets", "Look", "UIModifications.shade_widgets", "UI Shade")
	Link("Chat", "Chat Frame", "Look", "UIModifications.shade_chat", "UI Shade")
	Link("Chat", "Chat Frame", "Text", "Fonts.scaleChat", "Chat font and size")
	Link("Chat", "Whispers", "Look", "UIModifications.parchment_whisper", "Parchment",
		{ when = { key = "Chat.whisperPopup", value = true, line = "Only with the Whisper Popup Window" } })
	Link("Tooltip", "Tooltip", "Look", "BarTextures.texture", "Bar texture", { when = HEALTH_BAR })
	Link("Tooltip", "Tooltip", "Look", "UIModifications.barBorder", "Bar border", { when = HEALTH_BAR })
	Link("ScreenText", "Combat Text", "Text", "Fonts.style", "Font")
	Link("QuestTracker", "Quest Tracker", "Look", "UIModifications.parchment_questTracker", "Parchment")
	Link("QuestTracker", "Quest Tracker", "Look", "UIModifications.shade_tracker", "UI Shade")
	Link("QuestTracker", "Quest Tracker", "Text", "Fonts.style", "Font")
	Link("QuestTracker", "Quest Tracker", "Layout", "MinimapPanel.width", "Map width")
	Link("QuestTracker", "Objective Tracker", "Look", "UIModifications.parchment_tracker", "Parchment", { when = GAME_TRACKER })
	Link("QuestTracker", "Objective Tracker", "Look", "UIModifications.shade_tracker", "UI Shade")
	Link("QuestList", "List", "Look", "UIModifications.QuestLogPanel", "Painted Skin (Quest log)")
	-- (0.19.1, the user 2026-10-04: the borders on Look > Borders, the text sizes and fonts on Look > Fonts, named
	-- where they were)
	Link("Nameplates", "Plates", "Look", "UIModifications.nameplateBorder", "Nameplate border")
	Link("Minimap", "Minimap", "Look", "MinimapPanel.squareBorder", "Square border")
	Link("Tooltip", "Tooltip", "Look", "Tooltip.classBorder", "Class / reaction border", { when = Uncovered("TooltipPanel", "tooltip") })
	Link("Chat", "Chat Frame", "Look", "Chat.borderAlpha", "Border opacity")
	Link("Chat", "Chat Frame", "Text", "Fonts.fontChatText", "Chat font")
	Link("Chat", "Chat Frame", "Text", "Fonts.scaleChatParchment", "Chat on parchment size")
	Link("UnitFrames", "Bars", "Text", { player = "BarText.fontSize", target = "BarText.fontSize", focus = "BarText.fontSize" }, "Text size")
	Link("ActionBars", "Cooldown Timers", "Text", { bars = "CooldownText.fontRatio" }, "Text size")
	Link("BarsMeters", "FPS / Latency", "Text", "Stats.fontSize", "Text size")
	Link("QuestTracker", "Quest Tracker", "Text", "QuestTracker.textSize", "Text size")
	Link("QuestTracker", "Quest Tracker", "Text", "QuestTracker.headerSize", "Header size")
	Link("ScreenText", "Notices", "Text", "Tweaks.noticeOutline", "Outlined text")
	Link("ScreenText", "Combat Text", "Text", "CombatText.size", "Combat text size")
	Link("ScreenText", "Combat Text", "Text", "Tweaks.worldTextScale", "Numbers over enemies size")
	Link("ScreenText", "Combat Text", "Text", "Fonts.fontDamage", "Game numbers font")
end
