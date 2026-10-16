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
--          owner       "Module": while the key's own module is off, the row
--                      sleeps with THAT module's switches instead (any-of:
--                      a setting a core module reads from a kit panel's key
--                      until the key moves; one-look D6)
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
	{ title = "The look", entries = { "Look", "Windows", "Fader", "Oldschool" } },
	{ title = "Frames and bars", entries = { "UnitGroupFrames", "Nameplates", "ActionBars", "Minimap",
		"BarsMeters", "SwingTimers" } },
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
	-- (0.17.0) which parts fade away, and when they come back (one look: no
	-- header switch -- the Fader runs while any element fades)
	Fader = { title = "Fader", icon = "module:Fader",
		tabs = { "Fader", "Frames", "Bars", "Chat & Map" } },
	-- (one look C8, the user 2026-10-15: one designer per family) the player, target, focus, pet, your buffs, the
	-- party and raid frames (MelloUI's own) and the Personal Display: pick a frame, then a part of it; its own
	-- options under the part's (docs/plans/onelook-designer/c7-lite.md, ugf-audit.md)
	UnitGroupFrames = { title = "Unit & Group Frames", icon = "module:UnitFrames", designer = true, new = "0.25.0",
		flavour = "You, your target and your group: pick a frame, click a part of it, change it.",
		elements = {
			{ key = "player", label = "Player", line = "Your own frame", parts = { { key = "name", label = "Name" },
				{ key = "health", label = "Health bar" }, { key = "values", label = "Values" }, { key = "pvp", label = "PvP badge" },
				{ key = "status", label = "Status glow" }, { key = "combat", label = "Combat glow" },
				{ key = "portrait", label = "Portrait" } } },
			{ key = "target", label = "Target", line = "Your target's frame (and its target's)", parts = {
				{ key = "name", label = "Name" }, { key = "health", label = "Health bar" }, { key = "values", label = "Values" },
				{ key = "auras", label = "Buffs & Debuffs" }, { key = "pvp", label = "PvP badge" },
				{ key = "combat", label = "Combat glow" }, { key = "portrait", label = "Portrait" } } },
			{ key = "focus", label = "Focus", line = "Your focus's frame", parts = { { key = "name", label = "Name" },
				{ key = "health", label = "Health bar" }, { key = "values", label = "Values" }, { key = "pvp", label = "PvP badge" },
				{ key = "combat", label = "Combat glow" }, { key = "portrait", label = "Portrait" } } },
			{ key = "pet", label = "Pet", line = "Your pet's frame", parts = { { key = "status", label = "Status glow" },
				{ key = "combat", label = "Combat glow" } } },
			{ key = "buffs", label = "Buffs", line = "Your buffs and debuffs" },
			{ key = "party", label = "Party", module = "GroupFrames", line = "Your party: MelloUI's Group Frames or the game's",
				parts = { { key = "name", label = "Name" }, { key = "healthtext", label = "Health text" },
				{ key = "status", label = "Status text" }, { key = "health", label = "Health bar" },
				{ key = "power", label = "Power bar" }, { key = "background", label = "Background" } } },
			{ key = "raid", label = "Raid", module = "GroupFrames", line = "MelloUI's raid frames", parts = {
				{ key = "name", label = "Name" }, { key = "healthtext", label = "Health text" },
				{ key = "status", label = "Status text" }, { key = "health", label = "Health bar" },
				{ key = "power", label = "Power bar" }, { key = "background", label = "Background" },
				{ key = "indicators", label = "Indicators" } } },
			{ key = "personal", label = "Personal", module = "PersonalDisplay", line = "The bars under your character",
				parts = { { key = "shield", label = "Shield column" }, { key = "cast", label = "Cast" },
				{ key = "swing", label = "Swing rails" }, { key = "text", label = "Text" },
				{ key = "cooldowns", label = "Big cooldowns" } } },
		},
		family = { key = "all", label = "All frames", line = "Every frame: the heal light, the big moments, the debuff glow" } },
	-- (one look C8) the painted reskin's own rows, kept working here until the painted look becomes its own addon
	Oldschool = { title = "Oldschool", icon = "module:UIModifications",
		flavour = "The painted reskin's own settings, kept here until the painted look becomes its own addon.",
		tabs = { "Painted Skins", "Frame Art" } },
	-- (0.20.0) MelloUI_GroupFrames: MelloUI's own party and raid frames (their
	-- frames, bars, texts; the Designer is one canvas row, W.CanvasRow)
	-- (0.20.0) the effects on the frames, one page (the user, 2026-10-09: "why are
	-- these 2 not 1 category"; one addon, MelloUI_FrameEffects): Heals, Heal
	-- Flight's (your heals' light from the cast bar to the frame), and Cooldowns,
	-- Frame Effects' (your group's big moments); each tab's first row its
	-- module's switch
	Nameplates = { title = "Nameplates", icon = "module:Nameplates",
		flavour = "The nameplates over every unit, their icons and auras, the markers over your party, and the sparkles on what you can loot.",
		tabs = { "Plates", "Auras & Icons", "Party Markers", "Sparkles" } },
	ActionBars = { title = "Action Bars", icon = "module:ActionBarPanel",
		flavour = "The action bars, the micro menu and the bag bar: pick a bar.",
		tabs = { "Bars", "Backdrops", "Cooldown Timers" },
		picker = { label = "Bar", noun = "bar", picks = { { "bars", "Action Bars" }, { "micro", "Micro Menu" }, { "bag", "Bag Bar" } } },
		-- (0.19.9) beside the picker: MelloUI's own Keybind Mode (its button: Core/Config.lua KEYBIND_MODE)
		action = "keybind" },
	-- (onelook D7) its header switch: MelloUI's minimap (MinimapPanel, for everyone since the one-look build; its
	-- painted half, MinimapKit, is the Painted Skin row); `new`: the switch's New tag (Core/Config.lua's Header)
	Minimap = { title = "Minimap", icon = "module:MinimapPanel", module = "MinimapPanel",
		flavour = "The minimap, its shape, size and border, and the Services bar under it.",
		switchLabel = "MelloUI Minimap",
		switchDesc = "MelloUI's minimap: its Width and Height, the square shape in the Chat panel, the Services bar merged under it, and the column under it that the Quest Tracker follows. Off: the game's own minimap, Edit Mode's Size sizes it again, and the Painted Skin is off with it.",
		new = "0.25.0",
		tabs = { "Minimap", "Services Bar" } },
	-- (0.17.1) the shot bar and the melee bar (its header switch: the Swing
	-- Timers module's, off by default)
	SwingTimers = { title = "Swing Timers", icon = "module:SwingTimers", module = "SwingTimers",
		tabs = { "Swing Timers" } },
	-- (0.21.0) health, power and the cast bar under the character, the shield column beside it (its header switch:
	-- the Personal Display module's, off by default; MelloUI_PersonalDisplay)
	BarsMeters = { title = "Bars & Meters", icon = "module:Stats",
		flavour = "The experience and reputation bars, the cooldown manager, the damage meter, event widgets and the FPS / latency readout.",
		-- (one look C8: "Cast Bar" interim, until the Bars designer -- the user's pick)
		tabs = { "XP & Reputation", "Cast Bar", "Cooldown Manager", "Damage Meter", "Event Widgets", "FPS / Latency" } },
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
	groupframes = { "UnitGroupFrames", "raid:element" },
	partyframes = { "UnitGroupFrames", "party:element" },
	raidframes = { "UnitGroupFrames", "raid:element" },
	indicators = { "UnitGroupFrames", "raid:indicators" },
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
	buffs = { "UnitGroupFrames", "buffs:element" },
	debuffs = { "UnitGroupFrames", "buffs:element" },
	classicons = { "UnitGroupFrames", "player:portrait" },
	unitframepanel = { "Oldschool", "Frame Art" },
	bartext = { "UnitGroupFrames", "player:values" },
	castbarpanel = { "Oldschool", "Painted Skins" },
	raidframepanel = { "Oldschool", "Painted Skins" },
	nameplatepanel = { "Nameplates", "Plates" },
	partymarkers = { "Nameplates", "Party Markers" },
	sparkles = { "Nameplates", "Sparkles" },
	lootsparkles = { "Nameplates", "Sparkles" },
	actionbarpanel = { "ActionBars", "Bars" },
	cooldowntext = { "ActionBars", "Cooldown Timers" },
	backdrops = { "ActionBars", "Backdrops" },
	minimappanel = { "Minimap", "Minimap" },
	minimapkit = { "Minimap", "Minimap" },   -- (onelook D7: the painted minimap, its Painted Skin row)
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
-- Look > Parchment since 0.19.1, the dropdown showing it all the same. One
-- look, 2026-10-15: the chat's painted skin is a Painted Skin row on the Chat
-- page and its parchment a Parchment row there -- the Background no longer
-- sets either)
L.unplaced = {
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
	-- (one look, 2026-10-15) the painted chat covers the game's chat windows: the reskin and its Painted Skin both on
	local CHAT_PAINTED = { all = { { key = "UIModifications.reskin", value = true },
		{ key = "UIModifications.ChatPanel", value = true } } }
	-- the chat's paper: the Minimal Chat View's and its whisper window's sheet, the reskin on or off (the Chat
	-- module's: asleep with it off, as the page's other rows), or the painted chat's on the game's windows (its own
	-- sheet, the Chat module on or off: a paper on there can always be switched off)
	local CHAT_PAPER = { any = { { all = { { key = "Chat.!enabled", value = true }, { key = "Chat.view", value = "minimal" } } },
		CHAT_PAINTED },
		line = "Only with the Minimal Chat View (Chat Tweaks on) or the painted chat (its Painted Skin, the reskin on)" }
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
	-- (0.20.1: the windows' frame and title, the user's examples 3 and 4 in our own art)
	R("Look", "Borders", "Look", "UIModifications.windowBorder")
	R("Look", "Borders", "Look", "UIModifications.windowTitle")
	R("Look", "Borders", "Look", "UIModifications.buttonBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.sideTabBorder", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.barBorder", { picture = true })
	-- (0.19.8, the border library's stage 2: the unit frames' bars a border of their own, worn under their skin)
	R("Look", "Borders", "Look", "UIModifications.unitFrameBorder", { picture = true,
		when = { key = "UIModifications.UnitFramePanel", value = true, line = "Only with the unit frames' Painted Skin" } })
	-- (0.19.1, the user 2026-10-04: "all border customization into Borders tab": the borders each element's page
	-- had, here with the kit's; each of those pages links its own)
	R("Look", "Borders", "Look", "UIModifications.nameplateBorder", { picture = true })
	-- (0.19.8: the cast bar's and the personal resource display's, the border library's)
	R("Look", "Borders", "Look", "UIModifications.castBarBorder", { picture = true,
		when = { key = "UIModifications.CastBarPanel", value = true, line = "Only with the cast bars' Painted Skin" } })
	-- (0.21.0: the Personal Display's bars, a module of its own -- no skin gate)
	R("Look", "Borders", "Look", "UIModifications.personalBarBorder", { picture = true })
	-- (0.20.1: the swing timers' frame, a choice of its own)
	R("Look", "Borders", "Look", "UIModifications.swingTimerBorder", { picture = true,
		when = { key = "UIModifications.CastBarPanel", value = true, line = "Only with the cast bars' Painted Skin" } })
	R("Look", "Borders", "Look", "UIModifications.roundBorder", { picture = true })
	-- (0.19.8, the border library's stage 4: the unit frames' portrait ring a choice of its own, decision 8)
	R("Look", "Borders", "Look", "UIModifications.portraitRing", { picture = true,
		when = { key = "UIModifications.UnitFramePanel", value = true, line = "Only with the unit frames' Painted Skin" } })
	-- (0.20.1: the level orb's look, the RPG pack's stone badge a choice -- Modules/KitBorders.lua)
	R("Look", "Borders", "Look", "UIModifications.levelOrb", { picture = true })
	R("Look", "Borders", "Look", "UIModifications.auraBorder", { picture = true })
	-- (0.19.8, the border library's first own row: Modules/KitBorders.lua; worn under the raid frames' skin)
	R("Look", "Borders", "Look", "UIModifications.raidFrameBorder", { picture = true,
		when = { key = "UIModifications.RaidFramePanel", value = true, line = "Only with the raid frames' Painted Skin" } })
	-- (0.19.8, stage 3: where it goes -- on each frame, round the group, both)
	R("Look", "Borders", "Look", "UIModifications.raidBorderPlace",
		{ when = { key = "UIModifications.RaidFramePanel", value = true, line = "Only with the raid frames' Painted Skin" } })
	-- (0.19.8: the game's Cooldown Manager's icons, Cooldown Tweaks)
	R("Look", "Borders", "Look", "UIModifications.cooldownBorder", { picture = true })
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
	-- (0.20.1) Numbers Over Enemies only where the client has the cvar it writes (the user, 2026-10-10: this
	-- client has none, the slider moved nothing and Combat Text reads the same cvar): else left out on purpose
	local okWorld, worldText = pcall(function() return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("WorldTextScale") end)
	local hasWorldText = okWorld and type(worldText) == "string"
	if hasWorldText then
		R("Look", "Fonts", "Text", "Tweaks.worldTextScale", { name = "Combat Text: Numbers Over Enemies" })
	else
		L.unplaced["Tweaks.worldTextScale"] = "this client has no WorldTextScale cvar: the slider would move nothing"
	end
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
	R("Look", "Parchment", "Look", "UIModifications.parchmentStyle")   -- (0.20.3: the look of every sheet and page)
	R("Look", "Parchment", "Look", "UIModifications.parchment_tracker", { when = GAME_TRACKER })
	-- (the Quest Tracker's paper and the chat's: their rows on their own pages since the one look, links here -- the
	-- Link rows below)
	-- (0.19.1, the user 2026-10-04: "any Parchment Enable/Disable into the Parchment tab": the whisper popups' and the
	-- tooltips', live while their painted skin is on -- the tooltips' Background dropdown shows it too)
	R("Look", "Parchment", "Look", "UIModifications.parchment_whisper", { gate = "UIModifications.ChatPanel" })
	R("Look", "Parchment", "Look", "UIModifications.parchment_meter")
	R("Look", "Parchment", "Look", "UIModifications.parchment_character")
	R("Look", "Parchment", "Look", "UIModifications.parchment_tooltip", { gate = "UIModifications.TooltipPanel" })
	R("Look", "Parchment", "Look", "UIModifications.parchment_dialog")

	-- Windows (the picker: the registry's windows). A kit panel's row here is
	-- live on the CURRENT pick's Painted Skin, not on the panel owning the
	-- key: the Bank wears the Bags' keys. Quality Gems and Grey Out Junk are
	-- Tweaks' (one look, D3): live on every pick, the painted skin on or off
	-- (asleep only with UI Modifications off, as Tweaks and the gems are)
	-- (0.19.0) the bag window by kind, MelloUI's own (either look; works with UI Modifications off)
	R("Windows", "Windows", "General", { BackpackPanel = "BagWindow.!enabled" }, { name = "Bags by Kind", free = true })
	-- (its kinds, the user's picks of 2026-10-04 -- since 0.20.4 one list, Kinds, their order, lines and groups; since
	-- 0.21.1 own kinds and each kind's settings in it, Split Trade Goods Trade Goods' own Split By Type there; its
	-- layout's below, after Bag Slots On Bag Window)
	for _, key in ipairs({ "kinds", "#Items You Placed", "recentFor" }) do
		R("Windows", "Windows", "General", { BackpackPanel = "BagWindow." .. key }, { free = true })
	end
	-- (0.21.1, the user: "modification to bank aswell" -- the bank by kind, inside the game's bank window: its switch on
	-- the Bank pick, beside the bank's look; the kinds are the bags' Kinds list)
	R("Windows", "Windows", "General", { BankPanel = "BagWindow.bank" }, { free = true })
	R("Windows", "Windows", "Look", { from = "windows" }, { name = "Painted Skin" })
	-- (0.19.4, the options audit: under the whole window's parchment the character window's body is its own stone)
	R("Windows", "Windows", "Look", { CharacterPanel = "CharacterPanel.windowBackground", BackpackPanel = "BackpackPanel.windowBackground", BankPanel = "BackpackPanel.windowBackground" }, { name = "Window Background", picture = true,
		whenFor = { ["CharacterPanel.windowBackground"] = { key = "UIModifications.parchment_character", notValue = "window", line = "Not with the whole window on parchment" } } })
	R("Windows", "Windows", "Look", { BackpackPanel = "BackpackPanel.itemBackground", BankPanel = "BackpackPanel.itemBackground", GuildBankPanel = "BackpackPanel.itemBackground" }, { name = "Item Slot Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.bookBackground" }, { name = "Book Page Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.pageBackground" }, { name = "Crafting Page Background", picture = true })
	R("Windows", "Windows", "Look", { ProfessionsPanel = "ProfessionsPanel.listBackground" }, { name = "Recipe List Background", picture = true })
	R("Windows", "Windows", "Look", { BackpackPanel = "Tweaks.qualityGems", BankPanel = "Tweaks.qualityGems", GuildBankPanel = "Tweaks.qualityGems" }, { name = "Quality Gems" })
	R("Windows", "Windows", "Look", { BackpackPanel = "Tweaks.greyJunk", BankPanel = "Tweaks.greyJunk", GuildBankPanel = "Tweaks.greyJunk" }, { name = "Grey Out Junk" })
	R("Windows", "Windows", "Layout", { BackpackPanel = "Tweaks.bagSlotsOnBags" }, { name = "Bag Slots On Bag Window" })
	for _, key in ipairs({ "columns", "itemSize", "foldEmpty", "sortBy" }) do
		R("Windows", "Windows", "Layout", { BackpackPanel = "BagWindow." .. key }, { free = true })
	end
	-- (0.21.3, the animations: an item looted flies into its slot, the rarer the more)
	R("Windows", "Windows", "Behaviour", { BackpackPanel = "BagWindow.lootFlight" }, { free = true })
	-- (0.22.1, the animations: items glide to their new slots, the money rolls, the bags full shake their Empty slot)
	for _, key in ipairs({ "itemsGlide", "moneyRoll", "fullWarning" }) do
		R("Windows", "Windows", "Behaviour", { BackpackPanel = "BagWindow." .. key }, { free = true })
	end
	R("Windows", "Windows", "Behaviour", { BackpackPanel = "Discard.bagButton", LootPanel = "Discard.lootButton" }, { name = "Discard Button" })
	R("Windows", "Windows", "Behaviour", { BackpackPanel = "Discard.keepWorth", LootPanel = "Discard.keepWorth" }, { name = "Never Throw Away Items Worth" })
	-- (0.22.0, a player's request: the split box's mouse wheel and ½, Tweaks' -- either look)
	R("Windows", "Windows", "Behaviour", { StackSplitPanel = "Tweaks.splitWheel" })
	R("Windows", "Windows", "Behaviour", { StackSplitPanel = "Tweaks.splitHalf" })
	-- (0.19.4, the options audit: UI Modifications' own, working without the
	-- Fader, so here, not under the Fader's switch; the Fader links it)
	R("Windows", "Windows", "Behaviour", "UIModifications.fadeWindows", { wide = "every window" })

	-- Unit Frames (the picker: Player ... Personal Display)
	-- (one look C8) a row on several frames' tabs: one row each, the first its home, the others marked
	-- Shared ("also ..."); `plus`, a frame with no tab here yet, named on that line only (the game's party
	-- frames: the Party chip's Portraits style comes with C9 / C10)
	local UGF_LABEL = { player = "Player", target = "Target", focus = "Focus", pet = "Pet", buffs = "Buffs", party = "Party",
		raid = "Raid", personal = "Personal" }
	local function UGF(tabs, section, id, extra)
		for i, tab in ipairs(tabs) do
			local e = {}
			for k, v in pairs(extra or {}) do
				e[k] = v
			end
			e.plus = nil
			if #tabs > 1 or (extra and extra.plus) then
				local others = {}
				for j, other in ipairs(tabs) do
					if j ~= i then
						others[#others + 1] = UGF_LABEL[other:match("^(%w+)")]
					end
				end
				others[#others + 1] = extra and extra.plus
				e.shared = "also " .. table.concat(others, ", ")
			end
			R("UnitGroupFrames", tab, section, id, e)
		end
	end
	local GAME4 = { "player:element", "target:element", "focus:element", "pet:element" }
	UGF(GAME4, "General", "UIModifications.qol_UnitFrames", { plus = "Party portraits" })
	UGF({ "player:portrait", "target:portrait", "focus:portrait" }, "General", "UIModifications.qol_ClassIcons",
		{ plus = "Party portraits" })
	R("Oldschool", "Painted Skins", "Look", "UIModifications.UnitFramePanel", { name = "Unit Frames" })
	R("Oldschool", "Painted Skins", "Look", "UIModifications.RaidFramePanel", { name = "Raid Frames" })
	R("Oldschool", "Painted Skins", "Look", "UIModifications.CastBarPanel", { name = "Cast Bars" })
	UGF(GAME4, "Look", "DarkMode.unitframes", { name = "Dark Mode", also = { ["DarkMode.unitframes"] = "boss and target of target" },
		when = Uncovered("UnitFramePanel", "unit frames"), plus = "Party portraits" })
	R("BarsMeters", "Cast Bar", "Look", "DarkMode.castbar", { name = "Dark Mode", when = Uncovered("CastBarPanel", "cast bars") })
	R("UnitGroupFrames", "personal:element", "Look", "DarkMode.personal", { name = "Dark Mode" })
	-- (0.19.4, the options audit: the unit frame skin fades or replaces the
	-- same art and puts the writes back)
	local UF = Uncovered("UnitFramePanel", "unit frames")
	UGF(GAME4, "Look", "UnitFrames.frameAlpha", { when = UF, plus = "Party portraits" })
	UGF({ "target:name", "focus:name" }, "Look", "UnitFrames.hideReputationColor", { when = UF })
	UGF({ "player:combat", "target:combat", "focus:combat", "pet:combat" }, "Look", "UnitFrames.hideCombatGlow", { when = UF, plus = "Party portraits" })
	UGF({ "player:status", "pet:status" }, "Look", "UnitFrames.hideStatusGlow", { when = UF })
	UGF({ "player:pvp", "target:pvp", "focus:pvp" }, "Look", "UnitFrames.hidePvPBadge", { when = UF })
	UGF({ "player:portrait", "target:portrait", "focus:portrait" }, "Look", "ClassIcons.portraits", { plus = "Party portraits" })
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.marks")
	-- (0.19.8, the border library's stage 3: a backdrop round the frame, the kit's one backdrop system)
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.backdrop")
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.backdropBackground",
		{ when = { key = "UnitFramePanel.backdrop", notValue = "none", line = "Only with a Frame Backdrop" } })
	-- (0.21.3, the animations: the level badge turning over, the XP bar's light, the notice;
	-- one-look D5: the Unit Frames module's, Unit Frame Tweaks')
	R("BarsMeters", "XP & Reputation", "Look", "UnitFrames.levelUp")
	UGF({ "player:name", "target:name", "focus:name" }, "Text", "UnitFrames.centerNames", { when = UF })
	UGF({ "player:values", "target:values", "focus:values" }, "General", "UIModifications.qol_BarText")
	-- (0.19.0) incoming heals and the debuff glow: one setting each for every frame (HealerFrames)
	-- (0.19.4: incoming heals on MelloUI's three frames only, the bar
	-- background on the unit frames the skin draws -- not the raid frames,
	-- cast bars or personal resource)
	UGF({ "player:health", "target:health", "focus:health" }, "General", "HealerFrames.incomingHeals",
		{ also = { ["HealerFrames.incomingHeals"] = "their targets" } })
	UGF(GAME4, "Look", "BarTextures.unitframesTexture", { name = "Bar Texture", plus = "Party portraits",
		also = { ["BarTextures.unitframesTexture"] = "boss and target of target" } })
	UGF({ "raid:element", "party:element" }, "Look", "BarTextures.raidframesTexture", { name = "Bar Texture" })
	R("BarsMeters", "Cast Bar", "Look", "BarTextures.castbarsTexture", { name = "Bar Texture" })
	R("UnitGroupFrames", "personal:element", "Look", "BarTextures.personalTexture", { name = "Bar Texture" })
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.barBackground",
		{ also = { ["UnitFramePanel.barBackground"] = "target of target" } })
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.barBackgroundAlpha",
		{ also = { ["UnitFramePanel.barBackgroundAlpha"] = "target of target" },
		when = { key = "UnitFramePanel.barBackground", notValue = "none", line = "Not with the None background" } })
	R("UnitGroupFrames", "player:values", "Text", "BarText.player", { name = "Values On This Frame" })
	R("UnitGroupFrames", "target:values", "Text", "BarText.target", { name = "Values On This Frame" })
	R("UnitGroupFrames", "focus:values", "Text", "BarText.focus", { name = "Values On This Frame" })
	UGF({ "player:values", "target:values", "focus:values" }, "Text", "BarText.health")
	UGF({ "player:values", "target:values", "focus:values" }, "Text", "BarText.power")
	UGF({ "player:values", "target:values", "focus:values" }, "Text", "BarText.format")
	UGF({ "player:values", "target:values", "focus:values" }, "Text", "BarText.showMax")
	UGF({ "player:values", "target:values", "focus:values" }, "Layout", "BarText.position")
	UGF({ "player:values", "target:values", "focus:values" }, "Layout", "BarText.offsetX")
	UGF({ "player:values", "target:values", "focus:values" }, "Layout", "BarText.offsetY")
	UGF({ "buffs:element", "target:auras" }, "General", "UIModifications.qol_Auras")
	R("UnitGroupFrames", "buffs:element", "General", "Auras.player", { name = "Buffs & Debuffs On This Frame" })
	R("UnitGroupFrames", "target:auras", "General", "Auras.target", { name = "Buffs & Debuffs On This Frame" })
	R("UnitGroupFrames", "all", "General", "HealerFrames.debuffGlow")
	-- (0.19.4: Dark Mode reaches the game's own icons of yours, never the
	-- target's; with MelloUI's rows in their place it has nothing to darken.
	-- Keep Dispel Colours also serves the Cooldown Manager's icons)
	R("UnitGroupFrames", "buffs:element", "Look", "DarkMode.auras",
		{ when = { any = GAME_AURAS.any, line = "Only on the game's own icons (Buffs & Debuffs or Your Buffs And Debuffs off)" } })
	R("UnitGroupFrames", "buffs:element", "Look", "DarkMode.keepDispelColor",
		{ when = { any = { GAME_AURAS, { key = "DarkMode.cooldowns", value = true } },
			line = "Only on the game's own icons (Buffs & Debuffs or Your Buffs And Debuffs off) or the Cooldown Manager's" } })
	-- (0.19.9: one set of rows for your buffs -- MelloUI's own rows while
	-- they show, else the game's buff and debuff bars in the Edit Mode
	-- layout: Tweaks' Buff Layout; the size in pixels on both picks)
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffSize", { name = "Icon Size" })
	R("UnitGroupFrames", "target:auras", "Layout", "Auras.targetSize", { name = "Icon Size" })
	-- (0.20.1) the rows' own layout sleeps while they hang under the player frame (the target rows' look there)
	local NOT_FRAMED = { any = { GAME_AURAS.any[1], GAME_AURAS.any[2], { key = "Auras.playerFrame", value = false } },
		line = "Not with Attach To The Player Frame" }
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffSpacing", { when = NOT_FRAMED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffPerRow", { when = NOT_FRAMED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffGrow", { when = NOT_FRAMED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffNewRows", { when = NOT_FRAMED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Auras.playerColumn", { when = NOT_FRAMED })
	-- (0.20.1, the user: "an option under UnitFrames -> Player to attach their own buffs and debuffs to their unitframe")
	R("UnitGroupFrames", "buffs:element", "Layout", "Auras.playerFrame")
	R("UnitGroupFrames", "buffs:element", "Layout", "Auras.playerFrameGrow")
	R("UnitGroupFrames", "buffs:element", "Layout", "Auras.playerFrameSize")
	R("UnitGroupFrames", "target:auras", "Behaviour", "Auras.targetOnlyMine")
	R("UnitGroupFrames", "all", "Behaviour", "HealerFrames.debuffGlowShows")

	-- Nameplates (tabs: the parts differ)
	R("Nameplates", "Plates", "General", "Nameplates.threatLine")
	R("Nameplates", "Plates", "General", "Nameplates.comboPoints")
	R("Nameplates", "Plates", "General", "Nameplates.comboSize")   -- (under its switch: the user, 2026-10-04)
	R("Nameplates", "Plates", "Look", "UIModifications.NameplatePanel", { name = "Painted Skin" })
	R("Nameplates", "Plates", "Look", "DarkMode.nameplates", { name = "Dark Mode", when = Uncovered("NameplatePanel", "nameplates") })
	R("Nameplates", "Plates", "Look", "BarTextures.nameplatesTexture", { name = "Bar Texture" })
	R("Nameplates", "Plates", "Look", "NameplatePanel.marks")
	-- (one-look D6: the name band is the Nameplates module's, its key still the kit's: live with either)
	R("Nameplates", "Plates", "Text", "NameplatePanel.nameShade", { owner = "Nameplates" })
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
	-- (0.20.1, the user: a quality of life addition) the quest items' sparkle and the gathering glints: the glints
	-- hang on the game's nameplate of the object you walk up to (Modules/Sparkles.lua)
	R("Nameplates", "Sparkles", "General", "Sparkles.!enabled", { name = "Loot Sparkles" })
	R("Nameplates", "Sparkles", "General", "Sparkles.questItems")
	R("Nameplates", "Sparkles", "General", "Sparkles.ore")
	R("Nameplates", "Sparkles", "General", "Sparkles.herbs")
	R("Nameplates", "Sparkles", "General", "Sparkles.questObjects")

	-- Action Bars (the picker: Action Bars, Micro Menu, Bag Bar)
	R("ActionBars", "Bars", "General", { micro = "Tweaks.hideMicroMenu", bag = "Tweaks.hideBagBar" }, { name = "Hide This Bar" })
	R("ActionBars", "Bars", "General", "ActionBars.hidePageArrows", { only = { "bars" } })
	R("ActionBars", "Bars", "General", "ActionBars.hideBarArt", { only = { "bars" } })
	R("ActionBars", "Bars", "Look", "UIModifications.ActionBarPanel", { name = "Painted Skin", wide = "every bar" })
	R("ActionBars", "Bars", "Look", { bars = "ActionBarPanel.barBackdrop", micro = "ActionBarPanel.microBackdrop", bag = "ActionBarPanel.bagBackdrop" }, { name = "Backdrop", picture = true })
	R("ActionBars", "Bars", "Look", { bars = "ActionBarPanel.barBackground", micro = "ActionBarPanel.microBackground", bag = "ActionBarPanel.bagBackground" }, { name = "Backdrop Background", picture = true })
	R("ActionBars", "Bars", "Look", { bars = "ActionBarPanel.buttonBackground", micro = "ActionBarPanel.microButtonBackground", bag = "ActionBarPanel.bagButtonBackground" }, { name = "Button Background", picture = true })
	-- (the action bar skin covers the bars, the micro menu, the bag bar and
	-- the XP bars: ActionBarPanel)
	R("ActionBars", "Bars", "Look", { bars = "DarkMode.actionbars", micro = "DarkMode.micromenu", bag = "DarkMode.micromenu" }, { name = "Dark Mode",
		when = Uncovered("ActionBarPanel", "action bars") })
	R("ActionBars", "Bars", "Look", "DarkMode.gryphons", { only = { "bars" }, when = Uncovered("ActionBarPanel", "action bars") })
	-- (0.19.8, the user's picks of button_press_sketch: the key held, range and resources; skin on or off)
	R("ActionBars", "Bars", "Look", "ActionButtons.pressLight", { only = { "bars" } })
	R("ActionBars", "Bars", "Look", "ActionButtons.rangeColours", { only = { "bars" } })
	-- (0.19.9, L1: one bar's layout, written into the Edit Mode layout:
	-- Tweaks' Bar Layout; its shape drawn under the sliders)
	R("ActionBars", "Bars", "Layout", "Tweaks.barLayoutBar", { only = { "bars" } })
	R("ActionBars", "Bars", "Layout", "Tweaks.barRows", { only = { "bars" } })
	R("ActionBars", "Bars", "Layout", "Tweaks.barIcons", { only = { "bars" } })
	R("ActionBars", "Bars", "Layout", "Tweaks.barIconSize", { only = { "bars" } })
	R("ActionBars", "Bars", "Layout", "Tweaks.barPadding", { only = { "bars" } })
	R("ActionBars", "Bars", "Layout", "Tweaks.barShape", { only = { "bars" } })
	R("ActionBars", "Bars", "Behaviour", "Tweaks.bagBarFold", { only = { "bag" },
		when = { key = "Tweaks.hideBagBar", value = false, line = "Only while the bag bar shows" } })
	-- (0.18.5) each element's backdrop, one list whatever the pick (the user,
	-- 2026-10-04: "a list on Action Bars"); the looks stay on Bars > Look
	-- (onelook stage D4: the core's, Modules/ActionBars.lua, whatever the look)
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBar1")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBar2")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBar3")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBar4")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBar5")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBar6")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBar7")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBar8")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropStance")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropPet")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropPossess")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropTotem")   -- (0.20.2: the shaman's totem bar)
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropMicro")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropBags")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropXP")
	R("ActionBars", "Backdrops", "General", "ActionBars.backdropXP2")
	R("ActionBars", "Cooldown Timers", "General", "UIModifications.qol_CooldownText", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "General", "CooldownText.actionBars", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Text", "CooldownText.tenths", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Text", "CooldownText.colorByTime", { only = { "bars" } })
	R("ActionBars", "Cooldown Timers", "Behaviour", "CooldownText.minDuration", { only = { "bars" } })

	-- Minimap (its header switch: MelloUI's minimap, MinimapPanel; its Services bar a tab: Services has no header
	-- switch here). (onelook D7) Painted Skin: the painted half's own switch (MinimapKit), with MelloUI's minimap on
	R("Minimap", "Minimap", "General", "Tweaks.hideMinimapCoords")
	R("Minimap", "Minimap", "Look", "UIModifications.MinimapKit", { name = "Painted Skin",
		when = { key = "MinimapPanel.!enabled", value = true, line = "Only with MelloUI's minimap on" } })
	R("Minimap", "Minimap", "Look", "MinimapPanel.shape", { picture = true })
	R("Minimap", "Minimap", "Look", "DarkMode.minimap", { name = "Dark Mode", when = Uncovered("MinimapKit", "minimap") })
	R("Minimap", "Minimap", "Layout", "MinimapPanel.width")
	R("Minimap", "Minimap", "Layout", "MinimapPanel.height", { when = { key = "MinimapPanel.shape", value = "square", line = "Only for the square map (the round map takes Width)" } })
	R("Minimap", "Services Bar", "General", "Services.!enabled", { name = "Services Bar" })
	R("Minimap", "Services Bar", "General", "Services.showBar")
	R("Minimap", "Services Bar", "General", "Services.showButton")
	-- (0.22.0, a player's request: the addons' minimap buttons gathered into the row's AddOns group)
	R("Minimap", "Services Bar", "General", "Services.addonButtons")
	R("Minimap", "Services Bar", "Look", "Services.roundIcons")
	R("Minimap", "Services Bar", "Look", "Services.trayDrawer")   -- (0.22.1, the animations: the trays slide out)
	R("Minimap", "Services Bar", "Layout", "Services.buttonLayout")
	R("Minimap", "Services Bar", "Layout", "Services.barOffset")
	R("Minimap", "Services Bar", "Layout", "MinimapPanel.servicesMerge",
		{ when = { key = "MinimapPanel.shape", value = "square", line = "Only for the square map" } })

	-- Bars & Meters
	R("BarsMeters", "XP & Reputation", "Look", "BarTextures.statusbarsTexture", { name = "Bar Texture" })
	R("BarsMeters", "XP & Reputation", "Look", "DarkMode.statusbars", { name = "Dark Mode", when = Uncovered("ActionBarPanel", "action bars") })
	-- (0.22.1, the animations: the stretch of the XP bar just gained lit; Level Up's neighbour in the unit frames' file)
	R("BarsMeters", "XP & Reputation", "Look", "UnitFrames.xpGain")
	R("BarsMeters", "Cooldown Manager", "Look", "BarTextures.cooldownsTexture", { name = "Bar Texture" })
	R("BarsMeters", "Cooldown Manager", "Look", "DarkMode.cooldowns", { name = "Dark Mode" })
	-- (0.19.8, Cooldown Tweaks: Modules/CooldownTweaks.lua -- the addon study's item 7)
	R("BarsMeters", "Cooldown Manager", "Look", "CooldownTweaks.keybinds")
	R("BarsMeters", "Cooldown Manager", "Look", "CooldownTweaks.pressLight")
	R("BarsMeters", "Cooldown Manager", "Text", "CooldownTweaks.countSize")
	R("BarsMeters", "Cooldown Manager", "Layout", "CooldownTweaks.centreRows")
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
	R("BarsMeters", "Damage Meter", "Layout", "Meter.railHeight")   -- (onelook B: Race Bar Thickness, Height's place)
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
	R("Chat", "Chat Frame", "Look", "Chat.view")
	-- (one look, 2026-10-15: the painted chat -- Oldschool's -- a switch of its own, as every painted skin's; the
	-- Background set it until then)
	R("Chat", "Chat Frame", "Look", "UIModifications.ChatPanel", { name = "Painted Skin" })
	-- (one look; the user, 2026-10-15: "for those 2, chat and objective tracker, i want them to have the option for
	-- either normal look, and parchment even with the reskin off": the chat's paper its own switch, as the Quest
	-- Tracker's (Kit.ownParchments); the Background's Parchment until then; Look > Parchment links to it)
	R("Chat", "Chat Frame", "Look", "UIModifications.parchment_chat", { name = "Parchment", free = true, when = CHAT_PAPER })
	-- (the game's windows' ground, asleep under the painted chat, which lays its own; the Minimal Chat View's panel)
	R("Chat", "Chat Frame", "Look", "Chat.background", { when = { any = { { key = "UIModifications.reskin", value = false },
		{ key = "UIModifications.ChatPanel", value = false }, { key = "Chat.view", value = "minimal" } },
		line = "Only without the painted chat, or with the Minimal Chat View" } })
	-- (the opacity is the painted chat's stone's too: live under it whatever the Background reads)
	local NOT_NONE = { any = { { key = "Chat.background", notValue = "none" }, CHAT_PAINTED },
		line = "Not with the None background" }
	R("Chat", "Chat Frame", "Look", "Chat.windowAlphaOn", { when = NOT_NONE })
	R("Chat", "Chat Frame", "Look", "Chat.windowAlpha", { when = NOT_NONE })
	-- (0.19.4: the painted chat holds the input box and the tabs itself)
	R("Chat", "Chat Frame", "Look", "Chat.hideEditBox", { when = Uncovered("ChatPanel", "chat") })
	R("Chat", "Chat Frame", "Look", "Chat.hideTabs", { when = Uncovered("ChatPanel", "chat") })
	-- (0.23.0: the Minimal Chat View has its own row of buttons and places the line you type in itself)
	local NOT_MINIMAL = { key = "Chat.view", notValue = "minimal", line = "Not with the Minimal Chat View" }
	R("Chat", "Chat Frame", "Look", "Chat.chatButtons", { when = NOT_MINIMAL })
	R("Chat", "Chat Frame", "Layout", "Chat.editBoxTop", { when = NOT_MINIMAL })
	R("Chat", "Chat Frame", "Behaviour", "Chat.editBoxWhileTyping")   -- (0.20.4: the game's Classic chat style)
	R("Chat", "Chat Frame", "Behaviour", "Chat.smoothScroll")
	R("Chat", "Messages", "Text", "Chat.shortChannels")
	R("Chat", "Messages", "Text", "Chat.hideBrackets")
	R("Chat", "Messages", "Text", "Chat.nameShade")
	-- (free: read by MelloUI:Notice with Tweaks, and UI Modifications, off)
	R("Chat", "Messages", "Behaviour", "Tweaks.chatNotices", { free = true })
	-- (0.23.0: the Minimal Chat View's whisper window takes the whispers while it is on)
	R("Chat", "Whispers", "General", "Chat.whisperPopup", { when = { key = "Chat.view", notValue = "minimal",
		line = "Not with the Minimal Chat View: its whisper window takes the whispers" } })

	-- Tooltip
	R("Tooltip", "Tooltip", "General", "UIModifications.qol_Tooltip")
	R("Tooltip", "Tooltip", "Look", "Tooltip.background")
	R("Tooltip", "Tooltip", "Look", "Tooltip.backdropAlpha", { when = { key = "Tooltip.background", value = "dark", line = "Only for the Dark background" } })
	-- (0.19.4: Hide Health Bar, on by default, leaves nothing to dress)
	local HEALTH_BAR = { key = "Tooltip.hideHealthBar", value = false, line = "Only while the health bar shows (Hide Health Bar off)" }
	R("Tooltip", "Tooltip", "Look", "BarTextures.tooltipTexture", { name = "Bar Texture", when = HEALTH_BAR })
	R("Tooltip", "Tooltip", "Look", "Tooltip.classHealth", { when = HEALTH_BAR })
	R("Tooltip", "Tooltip", "Look", "Tooltip.hideHealthBar")
	R("Tooltip", "Tooltip", "Look", "Tooltip.hideIssueLine")
	R("Tooltip", "Tooltip", "Layout", "Tooltip.anchor")
	R("Tooltip", "Tooltip", "Layout", "Tooltip.scale")
	R("Tooltip", "Tooltip", "Behaviour", "Tooltip.hideInCombat")
	R("Tooltip", "Tooltip", "Behaviour", "Tooltip.fadeDelay")
	R("Tooltip", "Tooltip", "Behaviour", "QuestList.tipQuestItems")
	R("Tooltip", "Tooltip", "Behaviour", "QuestList.tipTurnIn")
	R("Tooltip", "Tooltip", "Behaviour", "QuestList.tipCharacters")

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
	-- (0.21.0, the settings audit: a row for a module's own part dimmed while that module is off, as the Objective
	-- Tracker's is while MelloUI's Quest Tracker stands in for it)
	local OWNED = {
		petToo = { when = { key = "Fader.show_player", notValue = "always", line = "Only while the Player Frame fades" } },
		personal = { when = { key = "PersonalDisplay.!enabled", value = true, line = "Only with the Personal Display on" } },
		tracker = { when = { key = "QuestTracker.!enabled", value = true, line = "Only with MelloUI's Quest Tracker on" } },
		objectives = { when = GAME_TRACKER },
		widgets = { when = { key = "Widgets.!enabled", value = true, line = "Only with the Widgets on" } },
		route = { when = { key = "Route.!enabled", value = true, line = "Only with Route on" } },
	}
	for _, key in ipairs({ "player", "petToo", "target", "party", "raid", "buffs", "reminders", "personal" }) do
		R("Fader", "Frames", "General", key == "petToo" and "Fader.petToo" or ("Fader.show_" .. key), OWNED[key])
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
		R("Fader", "Chat & Map", "General", "Fader.show_" .. key, OWNED[key])
	end

	-- (0.20.0) the Group Frames (header: its module's switch): the
	-- Designer is one canvas; the indicators' and your solo frame's switches
	do
		local function When(key, value, line)
			return { when = { key = "GroupFrames." .. key, value = value, line = line } }
		end
		local MINE = "Only with My Colour"
		-- the frames: what shows, their size and layout, the range
		UGF({ "raid:element", "party:element" }, "General", "GroupFrames.!enabled", { name = "Group Frames" })
		R("UnitGroupFrames", "party:element", "General", "GroupFrames.partyStyle")
		R("UnitGroupFrames", "party:element", "General", "GroupFrames.showPlayer")
		R("UnitGroupFrames", "party:element", "General", "GroupFrames.solo")
		UGF({ "raid:element", "party:element" }, "Layout", "GroupFrames.width")
		UGF({ "raid:element", "party:element" }, "Layout", "GroupFrames.height")
		-- (one look Q4: Edit Layout's Size of the party and the raid, the same value)
		R("UnitGroupFrames", "party:element", "Layout", "GroupFrames.@scale:GroupFramesParty", { name = "Scale" })
		R("UnitGroupFrames", "raid:element", "Layout", "GroupFrames.@scale:GroupFramesRaid", { name = "Scale" })
		R("UnitGroupFrames", "party:element", "Layout", "GroupFrames.spacing")
		R("UnitGroupFrames", "party:element", "Layout", "GroupFrames.partyGrowth")
		R("UnitGroupFrames", "party:element", "Layout", "GroupFrames.partySort")
		R("UnitGroupFrames", "raid:element", "Layout", "GroupFrames.raidGroupBy")
		R("UnitGroupFrames", "raid:element", "Layout", "GroupFrames.raidFlow")
		R("UnitGroupFrames", "raid:element", "Layout", "GroupFrames.raidPerLine")
		R("UnitGroupFrames", "raid:element", "Layout", "GroupFrames.raidSpacing")
		R("UnitGroupFrames", "raid:element", "Layout", "GroupFrames.raidGap")
		UGF({ "raid:element", "party:element" }, "Behaviour", "GroupFrames.rangeFade")
		UGF({ "raid:element", "party:element" }, "Behaviour", "GroupFrames.rangeAlpha")
		-- the bars: health, background, missing health, power
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.healthColour")
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.healthCustom", When("healthColour", "custom", MINE))
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.healthHigh", When("healthColour", "health", "Only with By Health"))
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.healthMid", When("healthColour", "health", "Only with By Health"))
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.healthLow", When("healthColour", "health", "Only with By Health"))
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.healthAlpha")
		UGF({ "raid:background", "party:background" }, "Look", "GroupFrames.backgroundTexture")
		UGF({ "raid:background", "party:background" }, "Look", "GroupFrames.background", When("backgroundTexture", "flat", "Only with Flat colour"))
		UGF({ "raid:background", "party:background" }, "Look", "GroupFrames.backgroundCustom", When("background", "custom", MINE))
		UGF({ "raid:background", "party:background" }, "Look", "GroupFrames.backgroundAlpha")
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.missing")
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.missingCustom", When("missing", "custom", MINE))
		UGF({ "raid:health", "party:health" }, "Look", "GroupFrames.missingAlpha", { when = { key = "GroupFrames.missing", notValue = "off", line = "Only with Missing Health on" } })
		UGF({ "raid:health", "party:health" }, "Layout", "GroupFrames.fillDirection")
		UGF({ "raid:power", "party:power" }, "Layout", "GroupFrames.power")
		UGF({ "raid:power", "party:power" }, "Layout", "GroupFrames.powerSolo")
		UGF({ "raid:power", "party:power" }, "Layout", "GroupFrames.powerHeight")
		UGF({ "raid:power", "party:power" }, "Layout", "GroupFrames.powerColour")
		UGF({ "raid:power", "party:power" }, "Layout", "GroupFrames.powerCustom", When("powerColour", "custom", MINE))
		UGF({ "raid:health", "party:health" }, "Behaviour", "GroupFrames.smooth")
		-- the texts (their places and sizes: the Designer's frame parts)
		UGF({ "raid:name", "party:name" }, "Text", "GroupFrames.nameColour")
		UGF({ "raid:name", "party:name" }, "Text", "GroupFrames.nameCustom", When("nameColour", "custom", MINE))
		UGF({ "raid:name", "party:name" }, "Text", "GroupFrames.nameLength")
		UGF({ "raid:healthtext", "party:healthtext" }, "Text", "GroupFrames.healthText")
		UGF({ "raid:status", "party:status" }, "Text", "GroupFrames.statusText")
		-- the Designer: the indicators and the frame's parts on one canvas
		R("UnitGroupFrames", "raid:indicators", "General", "GroupFrames.indicators")
		R("UnitGroupFrames", "raid:indicators", "General", "GroupFrames.designer")
	end

	-- (0.20.0) Frame Effects, Heals: Heal Flight's switch, the look, the landing
	-- in a raid, a made-up heal and every kind's landing to compare them
	R("UnitGroupFrames", "all", "General", "HealFlight.!enabled", { name = "Heal Effects" })
	R("UnitGroupFrames", "all", "General", "HealFlight.#Preview")
	R("UnitGroupFrames", "all", "General", "HealFlight.#Every Kind")
	R("UnitGroupFrames", "all", "General", "HealFlight.flight")
	R("UnitGroupFrames", "all", "General", "HealFlight.hotTicks")
	R("UnitGroupFrames", "all", "Look", "HealFlight.look")
	R("UnitGroupFrames", "all", "Look", "HealFlight.raidLanding")

	-- (0.20.0) Frame Effects, Cooldowns: its switch, whose, and every kind to see
	R("UnitGroupFrames", "all", "General", "FrameEffects.!enabled", { name = "Cooldown Effects" })
	R("UnitGroupFrames", "all", "General", "FrameEffects.#Every Effect")
	R("UnitGroupFrames", "all", "General", "FrameEffects.mine")
	R("UnitGroupFrames", "all", "General", "FrameEffects.group")

	-- (0.17.1) Swing Timers (header: its module's switch): which bars, their
	-- look, their size, when they show
	R("SwingTimers", "Swing Timers", "General", "SwingTimers.shot")
	R("SwingTimers", "Swing Timers", "General", "SwingTimers.melee")
	R("SwingTimers", "Swing Timers", "General", "SwingTimers.offhand")
	R("SwingTimers", "Swing Timers", "Look", "SwingTimers.look")
	-- (one look, 2026-10-15: the seconds in the Round rim, the one look: no gate on the Look)
	R("SwingTimers", "Swing Timers", "Text", "SwingTimers.text")
	R("SwingTimers", "Swing Timers", "Layout", "SwingTimers.width")
	R("SwingTimers", "Swing Timers", "Layout", "SwingTimers.height")
	R("SwingTimers", "Swing Timers", "Behaviour", "SwingTimers.show")

	-- (0.21.0) Personal Display (header: its module's switch): the shield column, the texts, the width, the hop, the preview
	R("UnitGroupFrames", "personal:element", "General", "PersonalDisplay.!enabled", { name = "Personal Display" })
	R("UnitGroupFrames", "personal:shield", "General", "PersonalDisplay.shield")
	R("UnitGroupFrames", "personal:element", "General", "PersonalDisplay.#Preview")
	R("UnitGroupFrames", "personal:cast", "General", "PersonalDisplay.hideCastBar")
	R("UnitGroupFrames", "personal:swing", "General", "PersonalDisplay.swing")
	R("UnitGroupFrames", "personal:cooldowns", "General", "PersonalDisplay.cooldowns")
	-- (the audit, 2026-10-12: gated as Route's minimap drawing is -- it does nothing without Heal Flight)
	R("UnitGroupFrames", "personal:cast", "Behaviour", "PersonalDisplay.healFrom", { when = { key = "HealFlight.!enabled", value = true, line = "Only with Heal Flight on" } })
	R("UnitGroupFrames", "personal:text", "Text", "PersonalDisplay.text")
	R("UnitGroupFrames", "personal:element", "Layout", "PersonalDisplay.width")
	R("UnitGroupFrames", "personal:element", "Layout", "PersonalDisplay.height")
	-- (one look Q4: Edit Layout's Size of the bars and of the shield column, the same value)
	R("UnitGroupFrames", "personal:element", "Layout", "PersonalDisplay.@scale:personalbars", { name = "Scale" })
	R("UnitGroupFrames", "personal:shield", "Layout", "PersonalDisplay.@scale:personalshield", { name = "Scale" })
	R("UnitGroupFrames", "personal:cooldowns", "Layout", "PersonalDisplay.cdSize", { when = { key = "PersonalDisplay.cooldowns", notValue = false, line = "Only with Big Cooldowns on" } })
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.hop")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.zoom")
	-- (0.21.0: its border on Look > Borders, its fade on the Fader's page)

	-- Quest Tracker (header: its module's switch; one look, stage E, the user 2026-10-15: its Painted Skin row is
	-- removed -- the tracker always wears MelloUI's look)
	-- (one look; the user, 2026-10-15: "the quest tracker the same as the chat does, needs to have the option to
	-- enable or disable parchment and not be depending on the reskin on/off": its own row here, as the chat's
	-- Parchment on the Chat page, live whatever the reskin -- Kit.ownParchments; asleep with the tracker off, as
	-- the page's other rows)
	R("QuestTracker", "Quest Tracker", "Look", "UIModifications.parchment_questTracker", { name = "Parchment", free = true,
		when = { key = "QuestTracker.!enabled", value = true, line = "Only with MelloUI's Quest Tracker on" } })
	R("QuestTracker", "Quest Tracker", "Look", "QuestTracker.progressMotion")
	-- (0.19.4: Match Minimap needs MelloUI's minimap -- onelook D7: the core
	-- module MinimapPanel, painted or not; Width is live while it is off)
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.matchMinimap",
		{ when = { key = "MinimapPanel.!enabled", value = true, line = "Only with MelloUI's minimap on" } })
	R("QuestTracker", "Quest Tracker", "Layout", "QuestTracker.width", { when = { any = {
		{ key = "QuestTracker.matchMinimap", value = false }, { key = "MinimapPanel.!enabled", value = false } },
		line = "Only while the tracker does not match the minimap (Match Minimap or MelloUI's minimap off)" } })
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
	R("QuestList", "List", "General", "QuestList.showHidden")
	R("QuestList", "List", "General", "QuestList.startGiver")
	R("QuestList", "List", "General", "QuestList.startDrop")
	R("QuestList", "List", "General", "QuestList.startPickup")
	R("QuestList", "List", "General", "QuestList.startUnknown")
	R("QuestList", "List", "General", "QuestList.otherFaction")
	R("QuestList", "List", "General", "QuestList.otherClass")
	R("QuestList", "List", "General", "QuestList.levelAbove")
	R("QuestList", "List", "Behaviour", "QuestList.dungeonSummary")
	-- (0.19.8: Auto Accept & Hand In, Modules/QuestAuto.lua -- the addon study's item 6, off by default)
	R("QuestList", "List", "Behaviour", "QuestAuto.accept")
	R("QuestList", "List", "Behaviour", "QuestAuto.handIn")
	R("QuestList", "List", "Behaviour", "QuestAuto.takeUpgrade", { when = { key = "QuestAuto.handIn", value = true,
		line = "Only with Auto Hand In" } })
	R("QuestList", "List", "Behaviour", "QuestAuto.skipKey", { when = { any = { { key = "QuestAuto.accept", value = true },
		{ key = "QuestAuto.handIn", value = true } }, line = "Only with Auto Accept or Auto Hand In" } })
	R("QuestList", "Map", "General", "QuestList.mapPins")
	R("QuestList", "Map", "General", "QuestList.pinCompleted")
	R("QuestList", "Map", "General", "QuestList.hideGrey")
	R("QuestList", "Map", "General", "QuestList.zoneBadges")
	R("QuestList", "Map", "General", "QuestList.zoneProgress")
	R("QuestList", "Map", "General", "QuestList.entrancePins")
	R("QuestList", "Map", "General", "QuestList.transportPins")
	R("QuestList", "Map", "General", "QuestList.objectiveMarks")
	R("QuestList", "Map", "General", "QuestList.objectiveTrackedOnly")
	R("QuestList", "Map", "General", "QuestList.hideGameObjectives")
	R("QuestList", "Map", "General", "QuestList.objectiveMinimap",
		{ when = { key = "Route.!enabled", value = true, line = "Only with Route on (its minimap drawing)" } })

	-- Route (header: its module's switch)
	R("Route", "Route", "General", "Route.trackQuests")
	R("Route", "Route", "General", "Route.trackFirstWatched")
	R("Route", "Route", "General", "Route.worldMap")
	R("Route", "Route", "General", "Route.minimap")
	R("Route", "Route", "General", "Route.distanceText")
	R("Route", "Route", "General", "Route.travelTime")
	R("Route", "Route", "Look", "Route.trailLook")
	R("Route", "Route", "Look", "Route.lineWidth")
	R("Route", "Route", "Look", "Route.drawIn")
	R("Route", "Route", "Behaviour", "Route.arrive")
	R("Route", "Route", "Behaviour", "Route.learn")
	R("Route", "Arrow & Marker", "General", "Route.worldMarker")
	R("Route", "Arrow & Marker", "General", "Route.routeBeam")
	R("Route", "Arrow & Marker", "General", "Route.markerWisp")
	R("Route", "Arrow & Marker", "General", "Route.arriveLight")
	R("Route", "Arrow & Marker", "Sound", "Route.markerSound")
	R("Route", "Flights", "General", "Route.flightHint")

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
		-- (0.19.4: the whisper row is raised by Chat's popup alone; 0.23.0: or the Minimal Chat View's whisper window)
		R("Reminders", "Widgets", "General", "Widgets." .. key, key == "whisper"
			and { when = { any = { { key = "Chat.whisperPopup", value = true }, { key = "Chat.view", value = "minimal" } },
				line = "Needs Chat's Whisper Popup Window or the Minimal Chat View" } } or nil)
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
	Link("Windows", "Windows", "Look", "UIModifications.buttonBorder", "Button Border")
	Link("Windows", "Windows", "Look", "UIModifications.sideTabBorder", "Side Tab Border")
	Link("Windows", "Windows", "Look", "UIModifications.roundBorder", "Round Border")
	-- (0.21.0, the settings audit, the user's picks: the windows' own frame and title too)
	Link("Windows", "Windows", "Look", "UIModifications.windowBorder", "Window Border")
	Link("Windows", "Windows", "Look", "UIModifications.windowTitle", "Window Title")
	Link("VoiceOver", "Widget", "Layout", "Reminders.widgetLock", "Lock The Widgets")
	Link("Reminders", "Widgets", "General", "Meter.summary", "Fight Summary")
	-- (0.17.0: the fades moved to the Fader)
	Link("Fader", "Fader", "Behaviour", "UIModifications.fadeWindows", "Windows Fade In")
	Link("Chat", "Chat Frame", "Behaviour", "Chat.tabsOnMouseover", "Tabs Only On Mouseover",
		{ when = Uncovered("ChatPanel", "chat") })
	-- (0.16.0: the merged settings, from where their members were)
	Link("Chat", "Messages", "Text", "UIModifications.nameFormat", "Names")
	Link("Chat", "Messages", "Text", "UIModifications.classNames", "Class Coloured Names")
	Link("Tooltip", "Tooltip", "Text", "UIModifications.classNames", "Class Coloured Names")
	Link("ScreenText", "Notices", "Text", "Tweaks.textShade", "Text Shade")
	Link("Route", "Arrow & Marker", "Text", "Tweaks.textShade", "Text Shade")
	Link("Route", "Route", "General", "Tweaks.noticeOnScreen", "On-screen Notices")
	Link("Route", "Route", "Sound", "Tweaks.noticeSounds", "Notice Sounds")
	-- (0.19.4, the options audit: the name band keeps its own strength; the UI Shade reaches the plates on Whole plate only)
	-- (one-look D6: Whole plate is the Nameplate Kit's, so these two links need the kit too)
	Link("Nameplates", "Plates", "Look", "UIModifications.uiShadeStrength", "Shade Strength", { when = { all = {
		{ key = "NameplatePanel.nameShade", value = "plate" }, { key = "UIModifications.uiShade", value = true },
		{ key = "UIModifications.reskin", notValue = false }, { key = "UIModifications.NameplatePanel", notValue = false } },
		line = "Only with Name Shade: Whole plate on the Nameplate Kit and the UI Shade on (the name band keeps its own)" } })
	-- (0.19.8, rule 9: the unit frames, the cast bars and the personal display have borders of their own now)
	-- (0.21.0, the user's picks: the level orb beside the portrait ring; the Personal Display's hold on the cast bar
	-- where the cast bar is set)
	-- (the Group Frames wear the Raid Frames pick's skin, border and bar texture)
	-- (Swing On The Rails makes the Swing Timers step aside)
	Link("SwingTimers", "Swing Timers", "General", "PersonalDisplay.swing", "Swing On The Rails (Personal Display)",
		{ when = { key = "PersonalDisplay.!enabled", value = true, line = "Only with the Personal Display on" } })
	-- (0.19.4: the aura border is worn by MelloUI's own rows only)
	Link("Nameplates", "Plates", "Look", "UIModifications.uiShade", "UI Shade", { when = { all = {
		{ key = "NameplatePanel.nameShade", value = "plate" },
		{ key = "UIModifications.reskin", notValue = false }, { key = "UIModifications.NameplatePanel", notValue = false } },
		line = "Only with Name Shade: Whole plate on the Nameplate Kit (the name band keeps its own)" } })
	Link("Nameplates", "Plates", "Look", "BarTextures.healthColor", "Health Bar Colour")
	Link("Nameplates", "Plates", "Text", "UIModifications.nameFormat", "Names")
	Link("Nameplates", "Auras & Icons", "Look", "UIModifications.auraBorder", "Aura Border", { when = { all = {
		{ key = "UIModifications.qol_Auras", value = true }, { key = "Auras.nameplates", value = true } },
		line = "Only on MelloUI's own debuff rows (Buffs & Debuffs and Enemy Nameplates on)" } })
	Link("ActionBars", "Bars", "Look", "UIModifications.shade_actionbars", "UI Shade")
	Link("ActionBars", "Bars", "Look", "UIModifications.buttonBorder", "Button Border")
	Link("Minimap", "Minimap", "Look", "UIModifications.shade_minimap", "UI Shade")
	Link("BarsMeters", "XP & Reputation", "Look", "UIModifications.barBorder", "Progress Bar Border")
	Link("BarsMeters", "Cooldown Manager", "Look", "DarkMode.keepDispelColor", "Keep Dispel Colours")
	Link("BarsMeters", "Cooldown Manager", "Look", "UIModifications.cooldownBorder", "Icon Border")
	Link("BarsMeters", "Damage Meter", "Look", "UIModifications.parchment_meter", "Parchment")
	Link("BarsMeters", "Event Widgets", "Look", "UIModifications.shade_widgets", "UI Shade")
	Link("Chat", "Chat Frame", "Look", "UIModifications.shade_chat", "UI Shade")
	Link("Chat", "Chat Frame", "Text", "Fonts.scaleChat", "Chat Size")
	Link("Chat", "Whispers", "Look", "UIModifications.parchment_whisper", "Parchment",
		{ when = { key = "Chat.whisperPopup", value = true, line = "Only with the Whisper Popup Window" } })
	Link("Tooltip", "Tooltip", "Look", "BarTextures.texture", "Bar Texture (Look)", { when = HEALTH_BAR })
	Link("Tooltip", "Tooltip", "Look", "UIModifications.barBorder", "Progress Bar Border", { when = HEALTH_BAR })
	Link("ScreenText", "Combat Text", "Text", "Fonts.style", "Font")
	-- (one look: the Quest Tracker's paper on its own page; the Parchment tab keeps it in its list, the user's
	-- 0.19.1 "any Parchment Enable/Disable into the Parchment tab")
	Link("Look", "Parchment", "Look", "UIModifications.parchment_questTracker", "Parchment: Quest Tracker")
	-- (one look, 2026-10-15: the chat's paper on the Chat page the same way)
	Link("Look", "Parchment", "Look", "UIModifications.parchment_chat", "Parchment: Chat", { when = CHAT_PAPER })
	Link("QuestTracker", "Quest Tracker", "Look", "UIModifications.shade_tracker", "UI Shade")
	Link("QuestTracker", "Quest Tracker", "Text", "Fonts.style", "Font")
	Link("QuestTracker", "Quest Tracker", "Layout", "MinimapPanel.width", "Map Width")
	Link("QuestTracker", "Objective Tracker", "Look", "UIModifications.parchment_tracker", "Parchment", { when = GAME_TRACKER })
	Link("QuestTracker", "Objective Tracker", "Look", "UIModifications.shade_tracker", "UI Shade")
	Link("QuestList", "List", "Look", "UIModifications.QuestLogPanel", "Painted Skin (Quest Log)")
	-- (0.19.1, the user 2026-10-04: the borders on Look > Borders, the text sizes and fonts on Look > Fonts, named
	-- where they were)
	Link("Nameplates", "Plates", "Look", "UIModifications.nameplateBorder", "Nameplate Border")
	Link("Minimap", "Minimap", "Look", "MinimapPanel.squareBorder", "Square Border")
	Link("Tooltip", "Tooltip", "Look", "Tooltip.classBorder", "Class / Reaction Border", { when = Uncovered("TooltipPanel", "tooltip") })
	Link("Chat", "Chat Frame", "Look", "Chat.borderAlpha", "Border Opacity")
	Link("Chat", "Chat Frame", "Text", "Fonts.fontChatText", "Chat Font")
	Link("Chat", "Chat Frame", "Text", "Fonts.scaleChatParchment", "Chat On Parchment Size")
	Link("ActionBars", "Cooldown Timers", "Text", { bars = "CooldownText.fontRatio" }, "Text Size")
	-- (one look, 2026-10-15: no Swing Timer Border link here -- the swing timers' Round rim wears no painted frame,
	-- the user's decision 8; the row on Look > Borders stays until stage E's option table)
	Link("BarsMeters", "FPS / Latency", "Text", "Stats.fontSize", "Text Size")
	Link("QuestTracker", "Quest Tracker", "Text", "QuestTracker.textSize", "Text Size")
	Link("QuestTracker", "Quest Tracker", "Text", "QuestTracker.headerSize", "Header Size")
	Link("ScreenText", "Notices", "Text", "Tweaks.noticeOutline", "Outlined Text")
	Link("ScreenText", "Combat Text", "Text", "CombatText.size", "Text Around You Size")
	Link("ScreenText", "Combat Text", "Text", "CombatText.titleNotices", "Notices In Title Font")
	if hasWorldText then
		Link("ScreenText", "Combat Text", "Text", "Tweaks.worldTextScale", "Numbers Over Enemies Size")
	end
	Link("ScreenText", "Combat Text", "Text", "Fonts.fontDamage", "Game Numbers Font")
end
