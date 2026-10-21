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

-- (2026-10-20, the user: "go all the way with the new icons") a group's `icon` and a page's `set`: their pictures
-- in MelloUI's icon set (Media/Textures/Icons), shown bare (pick A); a page's `icon` still names its module for
-- its flavour line
L.groups = {
	{ entries = { "Home" } },
	{ title = "The look", icon = "cat_look", entries = { "Look", "Windows", "Fader", "Oldschool" } },
	{ title = "Frames and bars", icon = "cat_frames", entries = { "UnitGroupFrames", "Nameplates", "ActionBars", "Minimap",
		"BarsMeters" } },
	{ title = "Chat and text", icon = "cat_chat", entries = { "Chat", "Tooltip", "ScreenText" } },
	{ title = "Quests and travel", icon = "cat_quests", entries = { "QuestTracker", "QuestList", "Route", "Map", "Reminders", "Automation" } },
	{ title = "Sound", icon = "cat_sound", entries = { "VoiceOver", "CustomSounds" } },
	{ entries = { "Profiles" } },
}

L.pages = {
	Home = { title = "Home", own = true },
	-- the global look: every element's page links here (its header switch
	-- is UI Modifications', which takes the reskin and every folded feature
	-- with it)
	Look = { title = "Look", icon = "module:UIModifications", set = "page_look", module = "UIModifications",
		flavour = "The look of the whole interface: the soft shade, fonts, icons, Dark Mode, the bar texture and fading. The painted reskin and its palettes are on the Oldschool page.",
		switchLabel = "UI Modifications",
		switchDesc = "The painted reskin AND every feature of UI Modifications: Vendor, Error Messages, Cooldown Timers, Nameplate Tweaks, Chat, Tooltip, Fonts, Dark Mode, Bar Textures, Buffs & Debuffs, Unit Frame Tweaks, FPS / Latency, Class Icons, Bar Values, the game windows' skins, hiding the micro menu, the bag bar and the minimap coordinates, and the world text scale. Off: all of them are off, Edit Layout lets go of the game's windows (they go back to the game's own places), Windows Fade In stops, names are shown in full and Class Coloured Names stops. The palette, the UI Shade, Reduce Motion and MelloUI's notices keep working.",
		tabs = { "General", "Fonts", "Icons", "Dark Mode", "Bar Texture", "Fading" } },
	-- (1.0, the user, 2026-10-20: "once you disable MelloUI_OldSchool, the "Window" category disappears from the
	-- Configurator, but that means that people cant configure their Bag anymore") made with or without
	-- MelloUI_Oldschool: its picker's `own` windows are the ones MelloUI's own settings belong to (the bag window and
	-- the bank by kind, Discard, the split box), always there; the painted skins of the game's windows join them with
	-- Oldschool loaded (the registry's windows, these four among them, the same keys and labels)
	Windows = { title = "Windows", icon = "module:CharacterPanel", set = "page_windows",
		flavour = "The bag window and the game's windows, one at a time: pick a window.",
		tabs = { "Windows" },
		picker = { label = "Window", noun = "window", from = "windows", own = {
			{ "BackpackPanel", "Bags", "MelloUI's bag window: your items by kind, its layout and behaviour." },
			{ "BankPanel", "Bank", "The bank by kind, inside the game's bank window." },
			{ "LootPanel", "Loot windows", "The loot window's Discard button." },
			{ "StackSplitPanel", "Split stack", "The split box's mouse wheel and half button." } } } },
	-- (0.17.0) which parts fade away, and when they come back (one look: no
	-- header switch -- the Fader runs while any element fades)
	Fader = { title = "Fader", icon = "module:Fader", set = "page_fader",
		-- (one look, Q5: each frame's and bar's Fade is its own element's last Behaviour row now -- the designers'
		-- and the Reminders page's; the chat's and the map's here until stage H)
		tabs = { "Chat & Map" } },
	-- (one look C8, the user 2026-10-15: one designer per family) the player, target, focus, pet, your buffs, the
	-- party and raid frames (MelloUI's own) and the Personal Display: pick a frame, then a part of it; its own
	-- options under the part's (docs/plans/onelook-designer/c7-lite.md, ugf-audit.md)
	UnitGroupFrames = { title = "Unit & Group Frames", icon = "module:UnitFrames", set = "page_frames", designer = true,
		flavour = "You, your target and your group: pick a frame, click a part of it, change it.",
		-- (2026-10-20, the user: "i also want user to be able to click and move stuff around, for example draging
		-- the name, the hp text etc") the frames' stage: Config Preview's 'unitframes' kind, the real frame's copy
		-- with its name and values dragged, sized and hidden there (their places Unit Frames' `parts`, the real
		-- frames' too); the `sample` slot (the corner sample, 1.5x) until then
		elements = {
			{ key = "player", label = "Player", line = "Your own frame", stage = { kind = "unitframes", pick = "player" },
				parts = { { key = "name", label = "Name", stage = "name" },
				{ key = "health", label = "Health bar" }, { key = "values", label = "Values", stage = "health" },
				{ key = "powervalue", label = "Power value", stage = "power" }, { key = "pvp", label = "PvP badge" },
				{ key = "status", label = "Status glow" }, { key = "combat", label = "Combat glow" },
				{ key = "portrait", label = "Portrait" } } },
			{ key = "target", label = "Target", line = "Your target's frame (and its target's)",
				stage = { kind = "unitframes", pick = "target" }, parts = {
				{ key = "name", label = "Name", stage = "name" }, { key = "health", label = "Health bar" },
				{ key = "values", label = "Values", stage = "health" }, { key = "powervalue", label = "Power value", stage = "power" },
				{ key = "auras", label = "Buffs & Debuffs" }, { key = "pvp", label = "PvP badge" },
				{ key = "combat", label = "Combat glow" }, { key = "portrait", label = "Portrait" } } },
			{ key = "focus", label = "Focus", line = "Your focus's frame", stage = { kind = "unitframes", pick = "focus" },
				parts = { { key = "name", label = "Name", stage = "name" },
				{ key = "health", label = "Health bar" }, { key = "values", label = "Values", stage = "health" },
				{ key = "powervalue", label = "Power value", stage = "power" }, { key = "pvp", label = "PvP badge" },
				{ key = "combat", label = "Combat glow" }, { key = "portrait", label = "Portrait" } } },
			{ key = "pet", label = "Pet", line = "Your pet's frame", stage = { kind = "unitframes", pick = "pet" },
				parts = { { key = "name", label = "Name", stage = "name" }, { key = "status", label = "Status glow" },
				{ key = "combat", label = "Combat glow" } } },
			{ key = "buffs", label = "Buffs", line = "Your buffs and debuffs" },
			-- (one look C10) `stage`: the designer stage over the chips (MelloUI_GroupFrames' 'raidframe' kind, its
			-- pick; `also`: its other picks of this frame); a part's `stage`: its part's key there ("ind:" any
			-- indicator) -- picked on the stage, its tab opens; its tab opened, picked on the stage
			{ key = "party", label = "Party", module = "GroupFrames", line = "Your party: MelloUI's Group Frames or the game's",
				stage = { kind = "raidframe", pick = "groupParty", also = { "portrait" } },
				parts = { { key = "name", label = "Name", stage = "name" },
				{ key = "healthtext", label = "Health text", stage = "health" },
				{ key = "status", label = "Status text", stage = "health", state = "down" },
				{ key = "health", label = "Health bar", stage = "bar.health" },
				{ key = "power", label = "Power bar", stage = "bar.power" },
				{ key = "background", label = "Background", stage = "bar.background" },
				{ key = "indicators", label = "Indicators", stage = "ind:" } } },
			{ key = "raid", label = "Raid", module = "GroupFrames", line = "MelloUI's raid frames",
				stage = { kind = "raidframe", pick = "raid" }, parts = {
				{ key = "name", label = "Name", stage = "name" },
				{ key = "healthtext", label = "Health text", stage = "health" },
				{ key = "status", label = "Status text", stage = "health", state = "down" },
				{ key = "health", label = "Health bar", stage = "bar.health" },
				{ key = "power", label = "Power bar", stage = "bar.power" },
				{ key = "background", label = "Background", stage = "bar.background" },
				{ key = "indicators", label = "Indicators", stage = "ind:" } } },
			{ key = "personal", label = "Personal", module = "PersonalDisplay", line = "The bars under your character",
				parts = { { key = "shield", label = "Shield column" }, { key = "cast", label = "Cast" },
				{ key = "swing", label = "Swing rails" }, { key = "text", label = "Text" },
				{ key = "cooldowns", label = "Big cooldowns" } } },
		},
		family = { key = "all", label = "All frames", line = "Every frame: the heal light, the big moments, the debuff glow" } },
	-- (one look C8) the painted reskin's own rows, kept working here until the painted look becomes its own addon
	Oldschool = { title = "Oldschool", icon = "module:UIModifications", set = "page_oldschool", oldschool = true,
		flavour = "The painted reskin's own settings, kept here until the painted look becomes its own addon.",
		tabs = { "General", "Painted Skins", "Borders", "Parchment", "Frame Art" } },
	-- (0.20.0) MelloUI_GroupFrames: MelloUI's own party and raid frames (their
	-- frames, bars, texts; the Designer is one canvas row, W.CanvasRow)
	-- (0.20.0) the effects on the frames, one page (the user, 2026-10-09: "why are
	-- these 2 not 1 category"; one addon, MelloUI_FrameEffects): Heals, Heal
	-- Flight's (your heals' light from the cast bar to the frame), and Cooldowns,
	-- Frame Effects' (your group's big moments); each tab's first row its
	-- module's switch
	-- (one look stage G, the user's yes of 2026-10-16 to docs/plans/onelook-designer/np-audit.md) the designer: the
	-- enemies' plates (every part MelloUI puts on the game's plate), the friendly players' (Party Markers' class
	-- medallion), the objects' (Loot Sparkles); no family block. The painted Nameplate Kit's rows are Oldschool's
	Nameplates = { title = "Nameplates", icon = "module:Nameplates", set = "page_nameplates", designer = true,
		flavour = "The game's nameplates: pick a kind, click a part of it, change it.",
		elements = {
			-- (`stage`: the enemy plate's sample, Modules/Nameplates.lua's 'nameplate' kind -- its parts picked,
			-- never moved; `showIn`: a part your target's plate shows, listed in every state, the stage put in it
			-- when its tab opens)
			{ key = "enemies", label = "Enemies", line = "Enemies' and NPCs' plates",
				stage = { kind = "nameplate", pick = "enemy" }, parts = {
				{ key = "name", label = "Name", stage = "name" }, { key = "health", label = "Health bar", stage = "health" },
				{ key = "threat", label = "Threat line", stage = "threat", showIn = "target" },
				{ key = "combo", label = "Combo points", stage = "combo", showIn = "target" },
				{ key = "cc", label = "CC icon", stage = "cc" }, { key = "quest", label = "Quest icon", stage = "quest" },
				{ key = "debuffs", label = "Your debuffs", stage = "debuffs" }, { key = "auras", label = "The game's auras" } } },
			-- (`sample`: Party Markers' own medallion sample in the slot -- Modules/PartyMarkers.lua's corner kind)
			{ key = "friendly", label = "Friendly players", line = "A class medallion over friendly players' names, in the open world",
				sample = { kind = "partymarker", pick = "marker" },
				parts = { { key = "medallion", label = "Medallion" }, { key = "role", label = "Role ring" } } },
			{ key = "objects", label = "Objects", line = "The sparkle on quest items and the glints over veins, herbs and quest objects" },
		} },
	-- (one look stage G, the user's yes of 2026-10-16 to docs/plans/onelook-designer/bars-audit.md: one designer
	-- for the bars -- RECOMMENDED.md section 3) the action bars, the micro menu and the bag bar, your cast bar, the
	-- swing timers, the XP and reputation bars and the game's Cooldown Manager; the painted action bar skin's rows
	-- are Oldschool's. `locked`: a part with nothing to set yet (listed, not opened: Q11)
	ActionBars = { title = "Bars", icon = "module:ActionBarPanel", set = "page_bars", designer = true,
		flavour = "Your bars: pick one, click a part of it, change it.",
		-- (0.19.9) MelloUI's own Keybind Mode in the header (its button: Core/Config.lua KEYBIND_MODE)
		action = "keybind",
		elements = {
			-- (`stage`: the bars' strips and the picked bar large, Modules/ActionButtons.lua's 'actionbar' kind --
			-- the user's A; a strip is Which Bar, the bar the Layout rows set)
			{ key = "actionbars", label = "Action Bars", line = "Bars 1-8, stance, pet, possess, totem",
				stage = { kind = "actionbar", pick = "bars" },
				parts = { { key = "button", label = "Button", stage = "button" },
				{ key = "cooldown", label = "Cooldown timer", stage = "cooldown", showIn = "cooldown" },
				{ key = "caps", label = "End caps", stage = "caps" }, { key = "arrows", label = "Page arrows", stage = "arrows" },
				{ key = "keybind", label = "Keybind text", stage = "keybind", locked = "Nothing to set yet: the game's text" } } },
			{ key = "menubags", label = "Menu & Bags", line = "The micro menu and the bag bar",
				parts = { { key = "micro", label = "Micro menu" }, { key = "bags", label = "Bag bar" } } },
			{ key = "castbar", label = "Cast Bar", line = "Your cast bar (size and place: Edit Mode)",
				parts = { { key = "bar", label = "Bar", locked = "Nothing to set yet" },
				{ key = "icon", label = "Icon", locked = "Nothing to set yet" },
				{ key = "spell", label = "Spell text", locked = "Nothing to set yet (its size: Interface Text, Look > Fonts)" },
				{ key = "timer", label = "Timer", locked = "Nothing to set yet" } } },
			{ key = "swing", label = "Swing Timers", module = "SwingTimers", line = "Your shot, melee and off-hand swings",
				parts = { { key = "shot", label = "Shot bar" }, { key = "melee", label = "Melee bar" },
				{ key = "offhand", label = "Off-hand bar" }, { key = "seconds", label = "Seconds" } } },
			{ key = "xprep", label = "XP & Rep", line = "The experience and reputation bars",
				parts = { { key = "xp", label = "XP bar" }, { key = "rep", label = "Reputation bar" } } },
			{ key = "cooldowns", label = "Cooldowns", line = "The game's Cooldown Manager",
				parts = { { key = "icon", label = "Icon" }, { key = "keybind", label = "Keybind" },
				{ key = "count", label = "Count" } } },
		} },
	-- (onelook D7) its header switch: MelloUI's minimap (MinimapPanel, for everyone since the one-look build; its
	-- painted half, MinimapKit, is the Painted Skin row); `new`: the switch's New tag (Core/Config.lua's Header)
	-- (one look stage G, the user's answers to docs/plans/onelook-designer/minimap-audit.md: a designer, chips Minimap
	-- and Services; no sample; the modern map square only -- Round with its header is the painted skin's, Oldschool's;
	-- Route trail and Objective marks locked parts that say where their settings are)
	Minimap = { title = "Minimap", icon = "module:MinimapPanel", set = "page_minimap", module = "MinimapPanel", designer = true,
		flavour = "The minimap and the Services bar under it: pick one, click a part, change it.",
		switchLabel = "MelloUI Minimap",
		switchDesc = "MelloUI's minimap: its Width and Height, the square shape in the Chat panel, the Services bar merged under it, and the column under it that the Quest Tracker follows. Off: the game's own minimap, Edit Mode's Size sizes it again, and the Painted Skin is off with it.",
		elements = {
			{ key = "minimap", label = "Minimap", line = "The map, its size and its border",
				parts = { { key = "coords", label = "Coordinates" }, { key = "border", label = "Border" },
				{ key = "route", label = "Route trail", locked = "Its settings: Route (Quests and travel)" },
				{ key = "marks", label = "Objective marks", locked = "Its settings: the World Map page" } } },
			{ key = "services", label = "Services", module = "Services", line = "The Services bar under the map",
				parts = { { key = "button", label = "Services button" }, { key = "tray", label = "Tray" } } },
		} },
	-- (0.21.0) health, power and the cast bar under the character, the shield column beside it (its header switch:
	-- the Personal Display module's, off by default; MelloUI_PersonalDisplay)
	-- (the Bars audit's point 5: the damage meter and the FPS / latency readout until stage H gives them homes;
	-- the bars went to Bars, the Event Widgets tab with its one painted link)
	BarsMeters = { title = "Damage Meter", icon = "module:Meter", set = "page_meter",
		flavour = "The damage meter.",
		tabs = { "Damage Meter" } },
	Chat = { title = "Chat", icon = "module:Chat", set = "page_chat",
		flavour = "The chat windows, the lines in them and the whisper popup.",
		tabs = { "Chat Frame", "Messages", "Whispers" } },
	Tooltip = { title = "Tooltip", icon = "module:Tooltip", set = "page_tooltip",
		flavour = "The tooltips: their backdrop, the unit lines, where they sit, and the quest lines on them.",
		tabs = { "Tooltip" } },
	ScreenText = { title = "Screen Text", icon = "module:ErrorFilter", set = "page_screentext",
		flavour = "The text in the middle of the screen: MelloUI's notices, the zone text, the red error messages and the floating combat numbers.",
		tabs = { "Notices", "Combat Text", "Gains", "Error Messages" } },
	QuestTracker = { title = "Quest Tracker", icon = "module:QuestTracker", set = "page_tracker", module = "QuestTracker",
		tabs = { "Quest Tracker", "Objective Tracker" } },
	QuestList = { title = "Quest List", icon = "module:QuestList", set = "page_questlist", module = "QuestList",
		tabs = { "List", "Map" } },
	Route = { title = "Route", icon = "module:Route", set = "page_route", module = "Route",
		tabs = { "Route", "Arrow & Marker", "Flights" } },
	-- (the seamless map, MelloUI_Map: docs/plans/seamless-map.md, stage M0)
	Map = { title = "Map", icon = "module:Map", module = "Map",
		tabs = { "Map" } },
	-- no header switch: three modules share the page, and each tab's first
	-- row is its module's switch (Reminders, Restock, Vendor Automation)
	Reminders = { title = "Reminders & Widgets", icon = "module:Reminders", set = "page_reminders",
		flavour = "Supplies, mail, repairs and training: a gentle nudge beside your portrait, never a nag. With the widgets for loot rolls, summons and the rest, and the FPS / latency readout.",
		tabs = { "Reminders", "Widgets", "FPS / Latency" } },
	-- (one look stage H, the plain pages' audit: the restock list, the vendor's repairs and sales and the quests'
	-- automatic accept and hand-in, one page; each tab's first row its module's switch)
	Automation = { title = "Automation", icon = "module:Vendor", set = "page_automation",
		flavour = "The things MelloUI does for you: repairs and junk sales at the vendor, the restock list, accepting and handing in quests.",
		tabs = { "Vendor", "Restock", "Quests" } },
	VoiceOver = { title = "Voice Over", icon = "module:VoiceOver", set = "page_voice", module = "VoiceOver",
		tabs = { "Reading", "Voices", "Sound Packs", "Widget" } },
	CustomSounds = { title = "Custom Sounds", icon = "module:CustomSounds", set = "page_sounds", module = "CustomSounds",
		tabs = { "Sounds", "Preview" } },
	Profiles = { title = "Profiles", own = true },
}

-- The page words beyond a page's key or title and the words each module
-- gives by itself (the page holding most of its rows, the tab of its first
-- row, a window panel's pick): the Look's tabs, the modules whose rows are
-- spread over several pages, and the panels with no row of their own. The
-- Auras module's name is /mello's aura probe: its page is buffs / debuffs.
L.words = {
	fade = { "Look", "Fading" },
	groupframes = { "UnitGroupFrames", "raid:element" },
	partyframes = { "UnitGroupFrames", "party:element" },
	raidframes = { "UnitGroupFrames", "raid:element" },
	indicators = { "UnitGroupFrames", "raid:indicators" },
	mouseover = { "Look", "Fading" },
	uimodifications = { "Look" },
	palette = { "Oldschool", "General" },   -- (0.25.0: the reskin's palettes; the modern look has Gilded Slate alone)
	uishade = { "Look", "General" },
	borders = { "Oldschool", "Borders" },
	fonts = { "Look", "Fonts" },
	darkmode = { "Look", "Dark Mode" },
	bartextures = { "Look", "Bar Texture" },
	parchment = { "Oldschool", "Parchment" },
	fading = { "Look", "Fading" },
	characterpanel = { "Windows", pick = "CharacterPanel" },
	buffs = { "UnitGroupFrames", "buffs:element" },
	debuffs = { "UnitGroupFrames", "buffs:element" },
	classicons = { "UnitGroupFrames", "player:portrait" },
	unitframepanel = { "Oldschool", "Frame Art" },
	bartext = { "UnitGroupFrames", "player:values" },
	castbarpanel = { "Oldschool", "Painted Skins" },
	raidframepanel = { "Oldschool", "Painted Skins" },
	nameplatepanel = { "Oldschool", "Painted Skins" },   -- (one look stage G: the painted Nameplate Kit is Oldschool's)
	partymarkers = { "Nameplates", "friendly:element" },
	sparkles = { "Nameplates", "objects:element" },
	lootsparkles = { "Nameplates", "objects:element" },
	actionbarpanel = { "Oldschool", "Painted Skins" },   -- (the Bars audit: the painted action bar skin)
	cooldowntext = { "ActionBars", "actionbars:cooldown" },
	backdrops = { "ActionBars", "actionbars:element" },
	minimappanel = { "Minimap", "minimap:element" },
	minimapkit = { "Oldschool", "Painted Skins" },   -- (onelook D7: the painted minimap; one look stage G: Oldschool's)
	services = { "Minimap", "services:element" },
	stats = { "Reminders", "FPS / Latency" },
	fps = { "Reminders", "FPS / Latency" },
	gains = { "ScreenText", "Gains" },
	damagemeterpanel = { "BarsMeters", "Damage Meter" },
	chatpanel = { "Chat", "Chat Frame" },
	tooltippanel = { "Tooltip" },
	tweaks = { "ScreenText", "Notices" },
	errorfilter = { "ScreenText", "Error Messages" },
	trackerpanel = { "QuestTracker", "Objective Tracker" },
	restock = { "Automation", "Restock" },
	vendor = { "Automation", "Vendor" },
	questauto = { "Automation", "Quests" },
	widgets = { "Reminders", "Widgets" },
	wand = { "ActionBars", "swing:element" },
	autoshot = { "ActionBars", "swing:element" },
}

-- (0.16.0: the chat windows' and the tooltips' painted skins and the chat's
-- Dark Mode are set through each page's one Background dropdown, which reads
-- and writes them: no row of their own. Their parchment has its switch on
-- Oldschool > Parchment since 0.19.1, the dropdown showing it all the same. One
-- look, 2026-10-15: the chat's painted skin is a Painted Skin row on the Chat
-- page and its parchment a Parchment row there -- the Background no longer
-- sets either)
L.unplaced = {
	["UIModifications.TooltipPanel"] = "Tooltip > Background",
	["DarkMode.chat"] = "Chat > Chat Frame > Background",
	-- (one look stage G, the Bars designer: Which Bar is the Action Bars stage's strips)
	["Tweaks.barLayoutBar"] = "Bars > Action Bars: the strips pick the bar",
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
	-- (one look Q9: no Buffs & Debuffs master -- Your Buffs And Debuffs alone)
	local GAME_AURAS = { any = { { key = "Auras.player", value = false } } }
	-- (2026-10-20, the configurator pass: a folded feature's rows sleep while none of its switches is on -- they
	-- set nothing then; one look Q9 made the frames' switches the features' only switches, off for a new player)
	local BAR_VALUES = { any = { { key = "BarText.player", value = true }, { key = "BarText.target", value = true },
		{ key = "BarText.focus", value = true } }, line = "Only with values shown" }
	local OWN_PLAYER = { key = "Auras.player", value = true, line = "Only with MelloUI's icons here" }
	local OWN_TARGET = { key = "Auras.target", value = true, line = "Only with MelloUI's icons here" }
	local OWN_ATTACHED = { all = { OWN_PLAYER, { key = "Auras.playerFrame", value = true } },
		line = "Only when attached to the frame" }
	local OWN_ANY = { any = { OWN_PLAYER, OWN_TARGET, { key = "Auras.nameplates", value = true } },
		line = "Only with MelloUI's icons on" }
	local TIMERS = { any = { { key = "CooldownText.actionBars", value = true }, { key = "CooldownText.nameplates", value = true } },
		line = "Only with Cooldown Timers on" }
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
	R("Oldschool", "General", "General", "UIModifications.reskin")
	R("Oldschool", "General", "General", "UIModifications.preloadArt")
	R("Oldschool", "General", "General", "UIModifications.#Switch every area on")
	-- (free: applied with UI Modifications on or off, its OnSettingChanged; 0.25.0: the painted reskin's palettes, so its
	-- page -- the modern look's one palette, Gilded Slate, is no choice)
	R("Oldschool", "General", "Look", "UIModifications.palette", { swatch = "palette", free = true })
	R("Oldschool", "General", "Look", "UIModifications.kitColours")
	R("Look", "General", "Look", "UIModifications.uiShade", { free = true })
	R("Look", "General", "Look", "UIModifications.uiShadeStrength", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_windows", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_chat", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_bags", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_minimap", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_icons", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_tracker", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_buffs", { free = true })
	R("Look", "General", "Look", "UIModifications.shade_widgets", { free = true })
	R("Look", "General", "Text", "UIModifications.nameFormat")
	R("Look", "General", "Text", "UIModifications.classNames", { free = true })
	R("Look", "General", "Text", "Tweaks.textShade", { free = true })
	R("Look", "General", "Behaviour", "UIModifications.reduceMotion", { free = true })
	R("Look", "General", "Behaviour", "UIModifications.fadeWindows")
	-- (0.20.1: the windows' frame and title, the user's examples 3 and 4 in our own art)
	R("Oldschool", "Borders", "Look", "UIModifications.windowBorder")
	R("Oldschool", "Borders", "Look", "UIModifications.windowTitle")
	R("Oldschool", "Borders", "Look", "UIModifications.buttonBorder", { picture = true })
	R("Oldschool", "Borders", "Look", "UIModifications.sideTabBorder", { picture = true })
	R("Oldschool", "Borders", "Look", "UIModifications.barBorder", { picture = true })
	-- (0.19.8, the border library's stage 2: the unit frames' bars a border of their own, worn under their skin)
	R("Oldschool", "Borders", "Look", "UIModifications.unitFrameBorder", { picture = true,
		when = { key = "UIModifications.UnitFramePanel", value = true, line = "Only with the unit frames' Painted Skin" } })
	-- (0.19.1, the user 2026-10-04: "all border customization into Borders tab": the borders each element's page
	-- had, here with the kit's; each of those pages links its own)
	R("Oldschool", "Borders", "Look", "UIModifications.nameplateBorder", { picture = true })
	-- (0.19.8: the cast bar's and the personal resource display's, the border library's)
	R("Oldschool", "Borders", "Look", "UIModifications.castBarBorder", { picture = true,
		when = { key = "UIModifications.CastBarPanel", value = true, line = "Only with the cast bars' Painted Skin" } })
	-- (0.21.0: the Personal Display's bars, a module of its own -- no skin gate)
	R("Oldschool", "Borders", "Look", "UIModifications.personalBarBorder", { picture = true })
	-- (0.20.1: the swing timers' frame, a choice of its own)
	R("Oldschool", "Borders", "Look", "UIModifications.swingTimerBorder", { picture = true,
		when = { key = "UIModifications.CastBarPanel", value = true, line = "Only with the cast bars' Painted Skin" } })
	R("Oldschool", "Borders", "Look", "UIModifications.roundBorder", { picture = true })
	-- (0.19.8, the border library's stage 4: the unit frames' portrait ring a choice of its own, decision 8)
	R("Oldschool", "Borders", "Look", "UIModifications.portraitRing", { picture = true,
		when = { key = "UIModifications.UnitFramePanel", value = true, line = "Only with the unit frames' Painted Skin" } })
	-- (0.20.1: the level orb's look, the RPG pack's stone badge a choice -- Modules/KitBorders.lua)
	R("Oldschool", "Borders", "Look", "UIModifications.levelOrb", { picture = true })
	R("Oldschool", "Borders", "Look", "UIModifications.auraBorder", { picture = true })
	-- (0.19.8, the border library's first own row: Modules/KitBorders.lua; worn under the raid frames' skin)
	R("Oldschool", "Borders", "Look", "UIModifications.raidFrameBorder", { picture = true,
		when = { key = "UIModifications.RaidFramePanel", value = true, line = "Only with the raid frames' Painted Skin" } })
	-- (0.19.8, stage 3: where it goes -- on each frame, round the group, both)
	R("Oldschool", "Borders", "Look", "UIModifications.raidBorderPlace",
		{ when = { key = "UIModifications.RaidFramePanel", value = true, line = "Only with the raid frames' Painted Skin" } })
	-- (0.19.8: the game's Cooldown Manager's icons, Cooldown Tweaks)
	R("Oldschool", "Borders", "Look", "UIModifications.cooldownBorder", { picture = true })
	R("Tooltip", "Tooltip", "Look", "Tooltip.classBorder", {
		when = Uncovered("TooltipPanel", "tooltip") })
	R("Chat", "Chat Frame", "Look", "Chat.borderAlpha", { name = "Border Opacity" })
	R("Look", "Fonts", "General", "UIModifications.qol_Fonts")
	R("Look", "Fonts", "Text", "Fonts.style")
	R("Look", "Fonts", "Text", "Fonts.sizeText")
	R("Look", "Fonts", "Text", "Fonts.scaleChat")
	R("Look", "Fonts", "Text", "Fonts.sizeTitle")
	R("Look", "Fonts", "Text", "Fonts.outline")
	-- (0.19.1, the user 2026-10-04: "all font sizes, font types and anything thats changing the font somewhere into
	-- this tab": each element's text size and font, named by its element; each of those pages links its own)
	R("Oldschool", "Parchment", "Text", "Fonts.scaleChatParchment", { gate = "UIModifications.parchment_chat" })
	R("Look", "Fonts", "Text", "BarText.fontSize", { name = "Unit Frame Bars: Font Size", when = BAR_VALUES })
	-- (the Bars audit's point 2: the cooldown timers' style, shared by the action bars and the nameplates)
	R("Look", "Icons", "Text", "CooldownText.fontRatio", { name = "Timer Text Size", when = TIMERS })
	R("Look", "Icons", "Text", "CooldownText.tenths", { when = TIMERS })
	R("Look", "Icons", "Text", "CooldownText.colorByTime", { when = TIMERS })
	R("Look", "Icons", "Behaviour", "CooldownText.minDuration", { when = TIMERS })
	R("Look", "Fonts", "Text", "QuestTracker.textSize", { name = "Quest Tracker: Text Size" })
	R("Look", "Fonts", "Text", "QuestTracker.headerSize", { name = "Quest Tracker: Header Text Size" })
	-- (the configurator audit, 2026-10-01: one size per thing on screen --
	-- MelloUI's combat text around you and the numbers over the enemies, the
	-- game's or Your Damage's; the game sizes its own text around you itself:
	-- Scale Damage gone in 0.19.4)
	-- (0.20.1) Numbers Over Enemies only where the client has the cvar it writes (the user, 2026-10-10: this
	-- client has none, the slider moved nothing and Combat Text reads the same cvar): else left out on purpose
	local okWorld, worldText = pcall(function() return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("WorldTextScale") end)
	local hasWorldText = okWorld and type(worldText) == "string"
	if hasWorldText then
		R("ScreenText", "Combat Text", "Text", "Tweaks.worldTextScale")
	else
		L.unplaced["Tweaks.worldTextScale"] = "this client has no WorldTextScale cvar: the slider would move nothing"
	end
	R("Look", "Fonts", "Advanced", "Fonts.fontText")
	R("Look", "Fonts", "Advanced", "Fonts.fontChat")
	R("Look", "Fonts", "Advanced", "Fonts.fontTitle")
	R("Look", "Fonts", "Advanced", "Fonts.fontChatText")
	R("Oldschool", "Parchment", "Advanced", "Fonts.fontChatParchment", { gate = "UIModifications.parchment_chat" })
	R("Look", "Fonts", "Advanced", "Fonts.fontDamage")
	R("Look", "Dark Mode", "General", "UIModifications.qol_DarkMode")
	R("Look", "Dark Mode", "Look", "DarkMode.shade")
	R("Oldschool", "General", "Look", "DarkMode.kitShade")
	R("Look", "Dark Mode", "Look", "DarkMode.desaturate")
	R("Look", "Bar Texture", "General", "UIModifications.qol_BarTextures")
	R("Look", "Bar Texture", "Look", "BarTextures.texture")
	-- the health bars' colour reaches the unit frames AND the nameplates
	-- (their descs; RecolorHealthBar): global
	-- (one look Q7: ONE Health Colour, every frame's -- the party and raid
	-- frames' too, so live while Bar Textures or Group Frames is on; its
	-- colours with it, Group Frames' until then; a link on each frame's
	-- Health bar in Unit & Group Frames)
	R("Look", "Bar Texture", "Look", "BarTextures.healthColor", { owner = "GroupFrames" })
	R("Look", "Bar Texture", "Look", "BarTextures.healthCustom", { owner = "GroupFrames",
		when = { key = "BarTextures.healthColor", value = "custom", line = "Only with My Colour" } })
	for _, key in ipairs({ "healthHigh", "healthMid", "healthLow" }) do
		R("Look", "Bar Texture", "Look", "BarTextures." .. key, { owner = "GroupFrames",
			when = { key = "BarTextures.healthColor", value = "health", line = "Only with By health" } })
	end
	R("Look", "Bar Texture", "Look", "BarTextures.overrideThreat",
		{ when = { key = "BarTextures.healthColor", notValue = "green", line = "Not with the Green (Blizzard) colour" } })
	R("Look", "Bar Texture", "Look", "BarTextures.executeRange")
	R("Look", "Bar Texture", "Look", "BarTextures.executeBelow")
	R("Oldschool", "Parchment", "Look", "UIModifications.parchmentStyle")   -- (0.20.3: the look of every sheet and page)
	R("Oldschool", "Parchment", "Look", "UIModifications.parchment_tracker", { when = GAME_TRACKER })
	-- (the Quest Tracker's paper and the chat's: their rows on their own pages since the one look, links here -- the
	-- Link rows below)
	-- (0.19.1, the user 2026-10-04: "any Parchment Enable/Disable into the Parchment tab": the whisper popups' and the
	-- tooltips', live while their painted skin is on -- the tooltips' Background dropdown shows it too)
	R("Oldschool", "Parchment", "Look", "UIModifications.parchment_whisper", { gate = "UIModifications.ChatPanel" })
	R("Oldschool", "Parchment", "Look", "UIModifications.parchment_meter")
	R("Oldschool", "Parchment", "Look", "UIModifications.parchment_character")
	R("Oldschool", "Parchment", "Look", "UIModifications.parchment_tooltip", { gate = "UIModifications.TooltipPanel" })
	R("Oldschool", "Parchment", "Look", "UIModifications.parchment_dialog")

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
				e.sharedWith = others   -- (the languages: Config writes "also ..." in the language in use)
			end
			R("UnitGroupFrames", tab, section, id, e)
		end
	end
	local GAME4 = { "player:element", "target:element", "focus:element", "pet:element" }
	UGF(GAME4, "General", "UIModifications.qol_UnitFrames", { plus = "Party portraits" })
	-- (one look Q9: Class Icons' master folded -- Player Portraits is its switch, first in General)
	UGF({ "player:portrait", "target:portrait", "focus:portrait" }, "General", "ClassIcons.portraits", { plus = "Party portraits" })
	R("Oldschool", "Painted Skins", "Look", "UIModifications.UnitFramePanel", { name = "Unit Frames" })
	R("Oldschool", "Painted Skins", "Look", "UIModifications.RaidFramePanel", { name = "Raid Frames" })
	R("Oldschool", "Painted Skins", "Look", "UIModifications.CastBarPanel", { name = "Cast Bars" })
	UGF(GAME4, "Look", "DarkMode.unitframes", { name = "Dark Mode", also = { ["DarkMode.unitframes"] = "boss and target of target" },
		when = Uncovered("UnitFramePanel", "unit frames"), plus = "Party portraits" })
	R("UnitGroupFrames", "personal:element", "Look", "DarkMode.personal", { name = "Dark Mode" })
	-- (0.19.4, the options audit: the unit frame skin fades or replaces the
	-- same art and puts the writes back)
	local UF = Uncovered("UnitFramePanel", "unit frames")
	-- (2026-10-20, the user's sheet: the frames as laid out, in the set's style; the party's too: "you always forget
	-- the Party Frames")
	UGF({ "player:element", "target:element", "focus:element", "party:element" }, "Look", "UnitFrames.frames", { when = UF })
	UGF({ "player:combat", "target:combat", "focus:combat", "pet:combat" }, "Look", "UnitFrames.hideCombatGlow", { when = UF, plus = "Party portraits" })
	UGF({ "player:status", "pet:status" }, "Look", "UnitFrames.hideStatusGlow", { when = UF })
	UGF({ "player:pvp", "target:pvp", "focus:pvp" }, "Look", "UnitFrames.hidePvPBadge", { when = UF })
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.marks")
	-- (0.19.8, the border library's stage 3: a backdrop round the frame, the kit's one backdrop system)
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.backdrop")
	-- (one look C13e, the user's yes to the audit's correction: UI Shade's Unit Frames area is the painted unit
	-- frames' -- KitShade.lua's OLDSCHOOL block, UnitFramePanel's SHADE_AREA -- so its switch is Oldschool's)
	R("Oldschool", "Frame Art", "Look", "UIModifications.shade_unitframes", { free = true, name = "UI Shade" })
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.backdropBackground",
		{ when = { key = "UnitFramePanel.backdrop", notValue = "none", line = "Only with a Frame Backdrop" } })
	-- (0.21.3, the animations: the level badge turning over, the XP bar's light, the notice;
	-- one-look D5: the Unit Frames module's, Unit Frame Tweaks')
	-- (one look C11, Q2: each text part its own face -- MelloUI.FontFaces, "Shared" today's)
	UGF({ "player:name", "target:name", "focus:name" }, "Text", "UnitFrames.nameFont", { name = "Font",
		plus = "Pet, their targets, Party portraits" })
	-- (0.19.0) incoming heals and the debuff glow: one setting each for every frame (HealerFrames)
	-- (0.19.4: incoming heals on MelloUI's three frames only, the bar
	-- background on the unit frames the skin draws -- not the raid frames,
	-- cast bars or personal resource)
	UGF({ "player:health", "target:health", "focus:health" }, "General", "HealerFrames.incomingHeals",
		{ also = { ["HealerFrames.incomingHeals"] = "their targets" } })
	UGF(GAME4, "Look", "BarTextures.unitframesTexture", { name = "Bar Texture", plus = "Party portraits",
		also = { ["BarTextures.unitframesTexture"] = "boss and target of target" } })
	UGF({ "raid:element", "party:element" }, "Look", "BarTextures.raidframesTexture", { name = "Bar Texture" })
	R("UnitGroupFrames", "personal:element", "Look", "BarTextures.personalTexture", { name = "Bar Texture" })
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.barBackground",
		{ also = { ["UnitFramePanel.barBackground"] = "target of target" } })
	R("Oldschool", "Frame Art", "Look", "UnitFramePanel.barBackgroundAlpha",
		{ also = { ["UnitFramePanel.barBackgroundAlpha"] = "target of target" },
		when = { key = "UnitFramePanel.barBackground", notValue = "none", line = "Not with the None background" } })
	R("UnitGroupFrames", "player:values", "Text", "BarText.player", { name = "Values On This Frame" })
	R("UnitGroupFrames", "target:values", "Text", "BarText.target", { name = "Values On This Frame" })
	R("UnitGroupFrames", "focus:values", "Text", "BarText.focus", { name = "Values On This Frame" })
	UGF({ "player:values", "target:values", "focus:values" }, "Text", "BarText.health", { when = BAR_VALUES })
	UGF({ "player:values", "target:values", "focus:values" }, "Text", "BarText.power", { when = BAR_VALUES })
	UGF({ "player:values", "target:values", "focus:values" }, "Text", "BarText.format", { when = BAR_VALUES })
	UGF({ "player:values", "target:values", "focus:values" }, "Text", "BarText.valueFont", { name = "Font", when = BAR_VALUES })
	UGF({ "player:values", "target:values", "focus:values" }, "Layout", "BarText.position", { when = BAR_VALUES })
	UGF({ "player:values", "target:values", "focus:values" }, "Layout", "BarText.offsetX", { when = BAR_VALUES })
	UGF({ "player:values", "target:values", "focus:values" }, "Layout", "BarText.offsetY", { when = BAR_VALUES })
	R("UnitGroupFrames", "buffs:element", "General", "Auras.player", { name = "Buffs & Debuffs On This Frame" })
	R("UnitGroupFrames", "target:auras", "General", "Auras.target", { name = "Buffs & Debuffs On This Frame" })
	UGF({ "buffs:element", "target:auras" }, "Text", "Auras.textFont", { name = "Numbers Font", plus = "the nameplates' debuffs",
		when = OWN_ANY })
	R("UnitGroupFrames", "all", "General", "HealerFrames.debuffGlow")
	-- (0.19.4: Dark Mode reaches the game's own icons of yours, never the
	-- target's; with MelloUI's rows in their place it has nothing to darken.
	-- Keep Dispel Colours also serves the Cooldown Manager's icons)
	R("UnitGroupFrames", "buffs:element", "Look", "DarkMode.auras",
		{ when = { any = GAME_AURAS.any, line = "Only on the game's own icons (Your Buffs And Debuffs off)" } })
	R("UnitGroupFrames", "buffs:element", "Look", "DarkMode.keepDispelColor",
		{ when = { any = { GAME_AURAS, { key = "DarkMode.cooldowns", value = true } },
			line = "Only on the game's own icons (Your Buffs And Debuffs off) or the Cooldown Manager's" } })
	-- (0.19.9: one set of rows for your buffs -- MelloUI's own rows while
	-- they show, else the game's buff and debuff bars in the Edit Mode
	-- layout: Tweaks' Buff Layout; the size in pixels on both picks)
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffSize", { name = "Icon Size" })
	R("UnitGroupFrames", "target:auras", "Layout", "Auras.targetSize", { name = "Icon Size", when = OWN_TARGET })
	-- (0.20.1) the rows' own layout sleeps while they hang under the player frame (the target rows' look there)
	local NOT_FRAMED = { any = { GAME_AURAS.any[1], { key = "Auras.playerFrame", value = false } },
		line = "Not with Attach To The Player Frame" }
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffSpacing", { when = NOT_FRAMED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffPerRow", { when = NOT_FRAMED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffGrow", { when = NOT_FRAMED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Tweaks.buffNewRows", { when = NOT_FRAMED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Auras.playerColumn", { when = NOT_FRAMED })
	-- (0.20.1, the user: "an option under UnitFrames -> Player to attach their own buffs and debuffs to their unitframe")
	R("UnitGroupFrames", "buffs:element", "Layout", "Auras.playerFrame", { when = OWN_PLAYER })
	R("UnitGroupFrames", "buffs:element", "Layout", "Auras.playerFrameGrow", { when = OWN_ATTACHED })
	R("UnitGroupFrames", "buffs:element", "Layout", "Auras.playerFrameSize", { when = OWN_ATTACHED })
	R("UnitGroupFrames", "target:auras", "Behaviour", "Auras.targetOnlyMine", { when = OWN_TARGET })
	R("UnitGroupFrames", "all", "Behaviour", "HealerFrames.debuffGlowShows")

	-- Nameplates (one look stage G: the designer; np-audit.md's table)
	-- Enemies: Nameplate Tweaks (the Nameplates module's switch) first, Dark Mode; each part's own rows
	R("Nameplates", "enemies:element", "General", "UIModifications.qol_Nameplates")
	R("Nameplates", "enemies:element", "Look", "DarkMode.nameplates", { name = "Dark Mode", when = Uncovered("NameplatePanel", "nameplates") })
	-- (0.25.0, the user's "yes build it" to the Nameplate Impact page: the target's plate answers the fight)
	R("Nameplates", "enemies:element", "General", "PlateImpact.!enabled", { name = "Impact Effects" })
	R("Nameplates", "enemies:element", "Behaviour", "PlateImpact.flash")
	R("Nameplates", "enemies:element", "Behaviour", "PlateImpact.chunk")
	R("Nameplates", "enemies:element", "Behaviour", "PlateImpact.crit")
	R("Nameplates", "enemies:element", "Behaviour", "PlateImpact.kill")
	R("Nameplates", "enemies:element", "Behaviour", "PlateImpact.evade")
	R("Nameplates", "enemies:element", "Behaviour", "PlateImpact.cast")
	R("Nameplates", "enemies:health", "Look", "BarTextures.nameplatesTexture", { name = "Bar Texture" })
	R("Nameplates", "enemies:threat", "General", "Nameplates.threatLine")
	R("Nameplates", "enemies:combo", "General", "Nameplates.comboPoints")
	R("Nameplates", "enemies:combo", "Layout", "Nameplates.comboSize")   -- (under its switch: the user, 2026-10-04)
	R("Nameplates", "enemies:cc", "General", "Nameplates.bigCC", { name = "Above The Name" })
	R("Nameplates", "enemies:cc", "Layout", "Nameplates.ccSize", { name = "Size" })
	R("Nameplates", "enemies:cc", "Layout", "Nameplates.ccGap")
	R("Nameplates", "enemies:quest", "General", "Nameplates.questIcon")
	R("Nameplates", "enemies:quest", "Layout", "Nameplates.questIconSize", { name = "Size" })
	R("Nameplates", "enemies:debuffs", "General", "Auras.nameplates")
	R("Nameplates", "enemies:debuffs", "Layout", "Auras.nameplateSize",
		{ when = { key = "Auras.nameplates", value = true, line = "Only with Your Debuffs on" } })
	R("Nameplates", "enemies:auras", "General", "CooldownText.nameplates")   -- (the Bars audit: Cooldown Timers' switch here)
	-- Friendly players: Party Markers' switch first
	R("Nameplates", "friendly:element", "General", "PartyMarkers.!enabled", { name = "Party Markers" })
	R("Nameplates", "friendly:element", "General", "PartyMarkers.who")
	R("Nameplates", "friendly:medallion", "Layout", "PartyMarkers.size", { name = "Size" })
	R("Nameplates", "friendly:medallion", "Layout", "PartyMarkers.offset")
	R("Nameplates", "friendly:role", "General", "PartyMarkers.roleRing")
	-- Objects (0.20.1, the user: a quality of life addition) the quest items' sparkle and the gathering glints: the
	-- glints hang on the game's nameplate of the object you walk up to (Modules/Sparkles.lua)
	R("Nameplates", "objects:element", "General", "Sparkles.!enabled", { name = "Loot Sparkles" })
	R("Nameplates", "objects:element", "General", "Sparkles.questItems")
	R("Nameplates", "objects:element", "General", "Sparkles.ore")
	R("Nameplates", "objects:element", "General", "Sparkles.herbs")
	R("Nameplates", "objects:element", "General", "Sparkles.questObjects")
	-- (one look stage G: the painted Nameplate Kit's own rows, Oldschool's)
	R("Oldschool", "Painted Skins", "Look", "UIModifications.NameplatePanel", { name = "Nameplates" })
	R("Oldschool", "Frame Art", "Look", "NameplatePanel.marks")
	-- (stage G, Q12: Name Shade's Whole plate, the kit's own switch; it needs the UI Shade)
	R("Oldschool", "Frame Art", "Look", "NameplatePanel.plateShade", { when = { key = "UIModifications.uiShade", value = true,
		line = "Only with the UI Shade on (Look)" } })

	-- Bars (one look stage G, bars-audit.md, the user's yes): each element's rows, its parts' rows
	-- Action Bars: every bar's (Dark Mode, the backdrops, the layout of the bar picked on the stage's strips --
	-- Which Bar), the parts shared by every bar
	R("ActionBars", "actionbars:element", "Look", "DarkMode.actionbars", { name = "Dark Mode",
		when = Uncovered("ActionBarPanel", "action bars") })
	-- (0.18.5) each bar's backdrop (onelook stage D4: the core's, Modules/ActionBars.lua, whatever the look)
	for _, key in ipairs({ "Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8", "Stance", "Pet", "Possess", "Totem" }) do
		R("ActionBars", "actionbars:element", "Look", "ActionBars.backdrop" .. key)
	end
	-- (0.19.9, L1: one bar's layout, written into the Edit Mode layout: Tweaks' Bar Layout; its shape drawn under
	-- the sliders)
	R("ActionBars", "actionbars:element", "Layout", "Tweaks.barRows")
	R("ActionBars", "actionbars:element", "Layout", "Tweaks.barIcons")
	R("ActionBars", "actionbars:element", "Layout", "Tweaks.barIconSize")
	R("ActionBars", "actionbars:element", "Layout", "Tweaks.barPadding")
	R("ActionBars", "actionbars:element", "Layout", "Tweaks.barShape")
	-- (2026-10-20, the user's sheet: MelloUI's frame on every button, the painted skin's bars aside)
	R("ActionBars", "actionbars:button", "Look", "ActionButtons.frames")
	R("ActionBars", "actionbars:button", "Look", "ActionButtons.readyFlash")
	-- (0.19.8, the user's picks of button_press_sketch: the key held, range and resources; skin on or off)
	R("ActionBars", "actionbars:button", "Look", "ActionButtons.pressLight")
	R("ActionBars", "actionbars:button", "Look", "ActionButtons.rangeColours")
	-- (the Bars audit's point 1: On Action Bars is Cooldown Timers' switch here)
	R("ActionBars", "actionbars:cooldown", "General", "CooldownText.actionBars", { name = "Cooldown Timers" })
	R("ActionBars", "actionbars:caps", "General", "ActionBars.hideBarArt")
	R("ActionBars", "actionbars:caps", "Look", "DarkMode.gryphons", { name = "Dark Mode",
		when = Uncovered("ActionBarPanel", "action bars") })
	R("ActionBars", "actionbars:arrows", "General", "ActionBars.hidePageArrows")
	-- Menu & Bags: each bar a part (Hide This Bar, its backdrop; the bag bar's fold), Dark Mode for both
	R("ActionBars", "menubags:element", "Look", "DarkMode.micromenu", { name = "Dark Mode",
		when = Uncovered("ActionBarPanel", "action bars") })
	R("ActionBars", "menubags:micro", "General", "Tweaks.hideMicroMenu", { name = "Hide This Bar" })
	R("ActionBars", "menubags:micro", "Look", "ActionBars.backdropMicro", { name = "Backdrop" })
	R("ActionBars", "menubags:bags", "General", "Tweaks.hideBagBar", { name = "Hide This Bar" })
	R("ActionBars", "menubags:bags", "Look", "ActionBars.backdropBags", { name = "Backdrop" })
	R("ActionBars", "menubags:bags", "Behaviour", "Tweaks.bagBarFold",
		{ when = { key = "Tweaks.hideBagBar", value = false, line = "Only while the bag bar shows" } })
	-- Cast Bar: its look (its parts the game's: nothing to set yet)
	R("ActionBars", "castbar:element", "Look", "BarTextures.castbarsTexture", { name = "Bar Texture" })
	R("ActionBars", "castbar:element", "Look", "DarkMode.castbar", { name = "Dark Mode", when = Uncovered("CastBarPanel", "cast bars") })
	-- (0.17.1) Swing Timers: its switch (the module's, off by default), each bar's, the seconds, the size, when
	R("ActionBars", "swing:element", "General", "SwingTimers.!enabled", { name = "Swing Timers" })
	R("ActionBars", "swing:element", "Layout", "SwingTimers.width")
	R("ActionBars", "swing:element", "Layout", "SwingTimers.height")
	R("ActionBars", "swing:element", "Behaviour", "SwingTimers.show")
	R("ActionBars", "swing:shot", "General", "SwingTimers.shot")
	R("ActionBars", "swing:melee", "General", "SwingTimers.melee")
	R("ActionBars", "swing:offhand", "General", "SwingTimers.offhand")
	R("ActionBars", "swing:seconds", "General", "SwingTimers.text")
	-- XP & Rep: the bars' look; the XP bar's light and Level Up (one look C13b: Tweaks'), each bar's backdrop
	-- (2026-10-20, the user's sheet: MelloUI's frame, track, notches and light on the bars, first)
	R("ActionBars", "xprep:element", "Look", "ActionBars.statusFrame")
	R("ActionBars", "xprep:element", "Look", "BarTextures.statusbarsTexture", { name = "Bar Texture" })
	R("ActionBars", "xprep:element", "Look", "DarkMode.statusbars", { name = "Dark Mode", when = Uncovered("ActionBarPanel", "action bars") })
	-- (0.22.1, the animations: the stretch of the XP bar just gained lit)
	R("ActionBars", "xprep:xp", "Look", "Tweaks.xpGain")
	R("ActionBars", "xprep:xp", "Look", "Tweaks.levelUp")
	R("ActionBars", "xprep:xp", "Look", "ActionBars.backdropXP", { name = "Backdrop" })
	R("ActionBars", "xprep:rep", "Look", "ActionBars.backdropXP2", { name = "Backdrop" })
	-- Cooldowns (0.19.8, Cooldown Tweaks: Modules/CooldownTweaks.lua -- the addon study's item 7)
	R("ActionBars", "cooldowns:element", "Look", "BarTextures.cooldownsTexture", { name = "Bar Texture" })
	R("ActionBars", "cooldowns:element", "Look", "DarkMode.cooldowns", { name = "Dark Mode" })
	R("ActionBars", "cooldowns:element", "Layout", "CooldownTweaks.centreRows")
	R("ActionBars", "cooldowns:icon", "Look", "CooldownTweaks.pressLight")
	R("ActionBars", "cooldowns:keybind", "General", "CooldownTweaks.keybinds")
	R("ActionBars", "cooldowns:count", "Text", "CooldownTweaks.countSize")
	-- the painted action bar skin (Oldschool: the switch, each bar's pictures)
	R("Oldschool", "Painted Skins", "Look", "UIModifications.ActionBarPanel", { name = "Action Bars" })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.barBackdrop", { name = "Action Bars: Backdrop", picture = true })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.barBackground", { name = "Action Bars: Backdrop Background", picture = true })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.buttonBackground", { name = "Action Bars: Button Background", picture = true })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.microBackdrop", { name = "Micro Menu: Backdrop", picture = true })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.microBackground", { name = "Micro Menu: Backdrop Background", picture = true })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.microButtonBackground", { name = "Micro Menu: Button Background", picture = true })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.bagBackdrop", { name = "Bag Bar: Backdrop", picture = true })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.bagBackground", { name = "Bag Bar: Backdrop Background", picture = true })
	R("Oldschool", "Frame Art", "Look", "ActionBarPanel.bagButtonBackground", { name = "Bag Bar: Button Background", picture = true })
	-- (the painted skins' rim shades: ActionBarPanel's and CastBarPanel's UI Shade areas)
	R("Oldschool", "Frame Art", "Look", "UIModifications.shade_actionbars", { free = true, name = "UI Shade: Action Bars" })
	R("Oldschool", "Frame Art", "Look", "UIModifications.shade_castbars", { free = true, name = "UI Shade: Cast Bars" })

	-- Minimap (its header switch: MelloUI's minimap, MinimapPanel; its Services bar an element: Services has no
	-- header switch here). (onelook D7) Painted Skin: the painted half's own switch (MinimapKit), with MelloUI's
	-- minimap on. (one look stage G: the modern map is square; the round one -- the painted skin's ring and header --
	-- is Oldschool's, so are the Shape and the Painted Skin. A square map: its shape Square, or the painted skin off;
	-- the cover jumps to the first switch, the painted Minimap's beside its Shape, never the whole reskin)
	local SQUARE = { any = { { key = "MinimapPanel.shape", value = "square" }, { key = "UIModifications.MinimapKit", value = false },
		{ key = "UIModifications.reskin", value = false } }, line = "Only for the square map (Oldschool's painted Minimap is set to Round)" }
	R("Minimap", "minimap:coords", "General", "Tweaks.hideMinimapCoords")
	R("Minimap", "minimap:element", "Look", "DarkMode.minimap", { name = "Dark Mode", when = Uncovered("MinimapKit", "minimap") })
	R("Minimap", "minimap:element", "Layout", "MinimapPanel.width")
	R("Minimap", "minimap:element", "Layout", "MinimapPanel.height", { when = SQUARE })
	-- (the frame round the square map: only the minimap wears it -- a link on Oldschool > Borders)
	R("Minimap", "minimap:border", "Look", "MinimapPanel.squareBorder", { picture = true, when = SQUARE })
	R("Minimap", "services:element", "General", "Services.!enabled", { name = "Services Bar" })
	R("Minimap", "services:element", "General", "Services.showBar")
	R("Minimap", "services:element", "Layout", "Services.buttonLayout")
	R("Minimap", "services:element", "Layout", "Services.barOffset")
	R("Minimap", "services:element", "Layout", "MinimapPanel.servicesMerge", { when = SQUARE })
	R("Minimap", "services:button", "General", "Services.showButton")
	R("Minimap", "services:button", "Look", "Services.roundIcons")
	-- (0.22.0, a player's request: the addons' minimap buttons gathered into the row's AddOns group)
	R("Minimap", "services:tray", "General", "Services.addonButtons")
	R("Minimap", "services:tray", "Look", "Services.trayDrawer")   -- (0.22.1, the animations: the trays slide out)
	-- the painted minimap (Oldschool: its switch -- with MelloUI's minimap on -- and its Shape, Round or Square)
	R("Oldschool", "Painted Skins", "Look", "UIModifications.MinimapKit", { name = "Minimap",
		when = { key = "MinimapPanel.!enabled", value = true, line = "Only with MelloUI's minimap on" } })
	R("Oldschool", "Frame Art", "Look", "MinimapPanel.shape", { name = "Minimap Shape", picture = true,
		when = { key = "UIModifications.MinimapKit", value = true, line = "Only with the painted Minimap skin" } })

	-- Bars & Meters
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
	R("Reminders", "FPS / Latency", "General", "UIModifications.qol_Stats")
	R("Reminders", "FPS / Latency", "General", "Stats.showFps")
	R("Reminders", "FPS / Latency", "General", "Stats.showLatency")
	R("Reminders", "FPS / Latency", "General", "Stats.worldLatency")
	R("Reminders", "FPS / Latency", "Text", "Stats.fontSize")
	R("Reminders", "FPS / Latency", "Layout", "Stats.offsetX")
	R("Reminders", "FPS / Latency", "Layout", "Stats.offsetY")
	R("Reminders", "FPS / Latency", "Behaviour", "Stats.interval")

	-- Chat
	R("Chat", "Chat Frame", "General", "UIModifications.qol_Chat")
	R("Chat", "Chat Frame", "Look", "Chat.view")
	-- (one look, 2026-10-15: the painted chat -- Oldschool's -- a switch of its own, as every painted skin's; the
	-- Background set it until then)
	R("Chat", "Chat Frame", "Look", "UIModifications.ChatPanel", { name = "Painted Skin" })
	-- (one look; the user, 2026-10-15: "for those 2, chat and objective tracker, i want them to have the option for
	-- either normal look, and parchment even with the reskin off": the chat's paper its own switch, as the Quest
	-- Tracker's (Kit.ownParchments); the Background's Parchment until then; Oldschool > Parchment links to it)
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
	-- (free: read by MelloUI:Notice with Tweaks, and UI Modifications, off)
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
	R("Tooltip", "Tooltip", "Look", "Tooltip.colourLines")
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
	R("ScreenText", "Notices", "Text", "Tweaks.noticeOutline", { free = true })
	R("ScreenText", "Notices", "Behaviour", "Tweaks.chatNotices", { free = true })
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
	R("ScreenText", "Combat Text", "Text", "CombatText.dealtScale",
		{ when = { key = "CombatText.dealt", notValue = "game", line = "Only while MelloUI draws Your Damage" } })
	R("ScreenText", "Combat Text", "General", "CombatText.#Preview")
	R("ScreenText", "Combat Text", "Look", "CombatText.shadeSize")
	-- (its text sizes and fonts: Look > Fonts since 0.19.1, linked below)
	R("ScreenText", "Combat Text", "Text", "CombatText.size", { when = { key = "CombatText.style", notValue = "game", line = "Only for the Lanes, Feed and Classic styles" } })
	R("ScreenText", "Combat Text", "Text", "CombatText.titleNotices", { when = { key = "CombatText.style", notValue = "game", line = "Only for the Lanes, Feed and Classic styles" } })
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
	R("Look", "Fading", "General", "Fader.#Fade Everything")
	R("Look", "Fading", "General", "Fader.#Fade Nothing")
	R("Look", "Fading", "Look", "Fader.alpha")
	R("Look", "Fading", "Behaviour", "Fader.after")
	R("Look", "Fading", "Behaviour", "Fader.speed")
	R("Look", "Fading", "Behaviour", "Fader.target")
	R("Look", "Fading", "Behaviour", "Fader.mouse")
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
	-- (the frames' and the bars' Fade rows: each element's last Behaviour row, at the end of the rows -- one look Q5)
	R("Fader", "Chat & Map", "General", "Fader.show_chat")
	R("Fader", "Chat & Map", "General", "Chat.tabsOnMouseover", { when = Uncovered("ChatPanel", "chat") })
	for _, key in ipairs({ "tracker", "objectives", "route" }) do   -- (the minimap's: its own page, Q5)
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
		UGF({ "raid:element", "party:element" }, "Behaviour", "GroupFrames.rangeAlpha")
		-- the bars: health, background, missing health, power
		-- (one look Q7: the health bar's colour is the one Health Colour, Look > Bar Texture: a link below)
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
		UGF({ "raid:name", "party:name" }, "Text", "GroupFrames.nameFont", { name = "Font" })
		UGF({ "raid:healthtext", "party:healthtext" }, "Text", "GroupFrames.healthFont", { name = "Font" })
		UGF({ "raid:indicators", "party:indicators" }, "Text", "GroupFrames.indicatorFont", { name = "Numbers Font" })
		-- the Designer: the indicators and the frame's parts on one canvas
		-- (one look C9b / C10: party and raid each their own list -- one switch, the canvas on both)
		UGF({ "raid:indicators", "party:indicators" }, "General", "GroupFrames.indicators")
		UGF({ "raid:indicators", "party:indicators" }, "General", "GroupFrames.designer")
	end

	-- (0.20.0) Frame Effects, Heals: Heal Flight's switch, the look, the landing
	-- in a raid, a made-up heal and every kind's landing to compare them
	R("UnitGroupFrames", "all", "General", "HealFlight.!enabled", { name = "Heal Effects" })
	R("UnitGroupFrames", "all", "General", "HealFlight.#Preview")
	R("UnitGroupFrames", "all", "General", "HealFlight.#Every Kind")
	R("UnitGroupFrames", "all", "General", "HealFlight.flight")
	R("UnitGroupFrames", "all", "General", "HealFlight.hotTicks")
	R("UnitGroupFrames", "all", "Look", "HealFlight.look")

	-- (0.20.0) Frame Effects, Cooldowns: its switch, whose, and every kind to see
	R("UnitGroupFrames", "all", "General", "FrameEffects.!enabled", { name = "Cooldown Effects" })
	R("UnitGroupFrames", "all", "General", "FrameEffects.#Every Effect")
	R("UnitGroupFrames", "all", "General", "FrameEffects.whose")   -- (one look C13d: Your Own + Your Group's)

	-- (0.21.0) Personal Display (header: its module's switch): the shield column, the texts, the width, the hop, the preview
	R("UnitGroupFrames", "personal:element", "General", "PersonalDisplay.!enabled", { name = "Personal Display" })
	R("UnitGroupFrames", "personal:shield", "General", "PersonalDisplay.shield")
	R("UnitGroupFrames", "personal:element", "General", "PersonalDisplay.#Preview")
	R("UnitGroupFrames", "personal:cast", "General", "PersonalDisplay.hideCastBar")
	R("UnitGroupFrames", "personal:swing", "General", "PersonalDisplay.swing")
	R("UnitGroupFrames", "personal:cooldowns", "General", "PersonalDisplay.cooldowns")
	R("UnitGroupFrames", "personal:element", "Look", "PersonalDisplay.classColour")
	-- (the audit, 2026-10-12: gated as Route's minimap drawing is -- it does nothing without Heal Flight)
	R("UnitGroupFrames", "personal:cast", "Behaviour", "PersonalDisplay.healFrom", { when = { key = "HealFlight.!enabled", value = true, line = "Only with Heal Flight on" } })
	R("UnitGroupFrames", "personal:text", "Text", "PersonalDisplay.text")
	R("UnitGroupFrames", "personal:text", "Text", "PersonalDisplay.textFont", { name = "Font" })
	R("UnitGroupFrames", "personal:element", "Layout", "PersonalDisplay.width")
	R("UnitGroupFrames", "personal:element", "Layout", "PersonalDisplay.height")
	-- (one look Q4: Edit Layout's Size of the bars and of the shield column, the same value)
	R("UnitGroupFrames", "personal:element", "Layout", "PersonalDisplay.@scale:personalbars", { name = "Scale" })
	R("UnitGroupFrames", "personal:shield", "Layout", "PersonalDisplay.@scale:personalshield", { name = "Scale" })
	R("UnitGroupFrames", "personal:cooldowns", "Layout", "PersonalDisplay.cdSize", { when = { key = "PersonalDisplay.cooldowns", notValue = false, line = "Only with Big Cooldowns on" } })
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.zoom")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.chunk")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.lead")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.heavy")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.spend")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.gain")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.avoid")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.lowHealth")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.stun")
	R("UnitGroupFrames", "personal:element", "Behaviour", "PersonalDisplay.settle")
	-- (0.21.0: its border on Oldschool > Borders, its fade on the Fader's page)

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
	R("Automation", "Quests", "Behaviour", "QuestAuto.accept")
	R("Automation", "Quests", "Behaviour", "QuestAuto.handIn")
	R("Automation", "Quests", "Behaviour", "QuestAuto.takeUpgrade", { when = { key = "QuestAuto.handIn", value = true,
		line = "Only with Auto Hand In" } })
	R("Automation", "Quests", "Behaviour", "QuestAuto.skipKey", { when = { any = { { key = "QuestAuto.accept", value = true },
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
	R("Map", "Map", "General", "Map.#Open The Map")

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
	R("Automation", "Restock", "General", "Restock.!enabled", { name = "Restock List And Shop" })
	R("Automation", "Restock", "General", "Restock.below")
	R("Automation", "Restock", "General", "Restock.shopPanel")
	R("Automation", "Restock", "General", "Restock.#Restock List")
	R("Automation", "Vendor", "General", "UIModifications.qol_Vendor")
	R("Automation", "Vendor", "Behaviour", "Vendor.autoRepair")
	R("Automation", "Vendor", "Behaviour", "Vendor.guildRepair")
	R("Automation", "Vendor", "Behaviour", "Vendor.autoSell")
	R("Automation", "Vendor", "Behaviour", "Vendor.report")
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
	R("ScreenText", "Gains", "General", "Gains.!enabled", { name = "Gains" })
	R("ScreenText", "Gains", "General", "Gains.skills")
	R("ScreenText", "Gains", "General", "Gains.values")
	R("ScreenText", "Gains", "General", "Gains.items")
	R("ScreenText", "Gains", "General", "Gains.bought")
	R("ScreenText", "Gains", "General", "Gains.junk")
	-- (0.17.0) money, the other currencies and the names' quality colour
	R("ScreenText", "Gains", "General", "Gains.money")
	R("ScreenText", "Gains", "General", "Gains.currencies")
	R("ScreenText", "Gains", "Look", "Gains.qualityNames")
	R("ScreenText", "Gains", "Behaviour", "Gains.hold")

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
	-- (stage H, the plain pages' audit: Record Dialog Lines, the voice work's recorder, is no player choice)
	L.unplaced["VoiceOver.collectLines"] = "the voice work's recorder, off for players: not a setting to offer"
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

	-- (one look, Q5 -- ugf-audit.md section 14, bars-audit.md: the user's yes) each frame's and bar's Fade (the
	-- Fader's Show: Always / In Combat / Mouseover ...) is its own element's last Behaviour row, here at the end so it
	-- is the last; the Fader page keeps how it fades and the chat's and the map's rows (stage H's)
	R("UnitGroupFrames", "player:element", "Behaviour", "Fader.show_player", { name = "Fade" })
	R("UnitGroupFrames", "target:element", "Behaviour", "Fader.show_target", { name = "Fade" })
	R("UnitGroupFrames", "pet:element", "Behaviour", "Fader.petToo", { name = "Fades With The Player", when = OWNED.petToo.when })
	R("UnitGroupFrames", "buffs:element", "Behaviour", "Fader.show_buffs", { name = "Fade" })
	R("UnitGroupFrames", "party:element", "Behaviour", "Fader.show_party", { name = "Fade" })
	R("UnitGroupFrames", "raid:element", "Behaviour", "Fader.show_raid", { name = "Fade" })
	R("UnitGroupFrames", "personal:element", "Behaviour", "Fader.show_personal", { name = "Fade", when = OWNED.personal.when })
	-- (each bar's own Fade in the Action Bars' list until the stage's strip picks it: bars-audit "This bar")
	R("ActionBars", "actionbars:element", "Behaviour", "Fader.show_bar1", { name = "Fade: Main Action Bar" })
	for n = 2, 8 do
		R("ActionBars", "actionbars:element", "Behaviour", "Fader.show_bar" .. n, { name = "Fade: Action Bar " .. n })
	end
	R("ActionBars", "actionbars:element", "Behaviour", "Fader.show_stance", { name = "Fade: Stance & Pet Bar" })
	-- (0.19.4: a bar Hide This Bar parks has nothing to fade)
	R("ActionBars", "menubags:micro", "Behaviour", "Fader.show_micro", { name = "Fade",
		when = { key = "Tweaks.hideMicroMenu", value = false, line = "Hidden (Hide This Bar)" } })
	R("ActionBars", "menubags:bags", "Behaviour", "Fader.show_bags", { name = "Fade",
		when = { key = "Tweaks.hideBagBar", value = false, line = "Hidden (Hide This Bar)" } })
	R("ActionBars", "xprep:element", "Behaviour", "Fader.show_xp", { name = "Fade" })
	R("Reminders", "Reminders", "Behaviour", "Fader.show_reminders", { name = "Fade" })
	R("Reminders", "Widgets", "Behaviour", "Fader.show_widgets", { name = "Fade", when = { key = "Widgets.!enabled", value = true, line = "Only with the Widgets on" } })
	R("Minimap", "minimap:element", "Behaviour", "Fader.show_minimap", { name = "Fade" })

	-- the link rows: a setting whose one place is another page (the global
	-- look on Look; the map's width on Minimap; the quest log's skin on
	-- Windows), named on each page it reaches
	Link("Windows", "Windows", "Look", { ["*"] = "UIModifications.shade_windows", BackpackPanel = "UIModifications.shade_bags" }, "UI Shade")
	Link("Windows", "Windows", "Look", { CharacterPanel = "UIModifications.parchment_character", DialogPanel = "UIModifications.parchment_dialog", ColorPickerPanel = "UIModifications.parchment_dialog", ReadyPanel = "UIModifications.parchment_dialog", StackSplitPanel = "UIModifications.parchment_dialog" }, "Parchment")
	Link("Windows", "Windows", "Look", "UIModifications.buttonBorder", "Button Border")
	-- (one look Q7: the one Health Colour on every frame's Health bar)
	for _, tab in ipairs({ "player:health", "target:health", "focus:health", "party:health", "raid:health" }) do
		Link("UnitGroupFrames", tab, "Look", "BarTextures.healthColor", "Health Bar Colour")
	end
	Link("Windows", "Windows", "Look", "UIModifications.sideTabBorder", "Side Tab Border")
	Link("Windows", "Windows", "Look", "UIModifications.roundBorder", "Round Border")
	-- (0.21.0, the settings audit, the user's picks: the windows' own frame and title too)
	Link("Windows", "Windows", "Look", "UIModifications.windowBorder", "Window Border")
	Link("Windows", "Windows", "Look", "UIModifications.windowTitle", "Window Title")
	Link("VoiceOver", "Widget", "Layout", "Reminders.widgetLock", "Lock The Widgets")
	Link("Reminders", "Widgets", "General", "Meter.summary", "Fight Summary")
	-- (0.17.0: the fades moved to the Fader)
	Link("Chat", "Chat Frame", "Behaviour", "Chat.tabsOnMouseover", "Tabs Only On Mouseover",
		{ when = Uncovered("ChatPanel", "chat") })
	-- (0.16.0: the merged settings, from where their members were)
	Link("Chat", "Messages", "Text", "UIModifications.nameFormat", "Names")
	Link("Chat", "Messages", "Text", "UIModifications.classNames", "Class Coloured Names")
	Link("Tooltip", "Tooltip", "Text", "UIModifications.classNames", "Class Coloured Names")
	Link("ScreenText", "Notices", "Text", "Tweaks.textShade", "Text Shade")
	Link("Route", "Arrow & Marker", "Text", "Tweaks.textShade", "Text Shade")
	-- (the user, 2026-10-16: Text Shade the one switch of every shade behind text -- the nameplates' Name Shade and
	-- the chat's Shade Behind Tags and Links went into it; the unit frames' name bands follow it)
	Link("Nameplates", "enemies:name", "Look", "Tweaks.textShade", "Text Shade")
	Link("Chat", "Messages", "Text", "Tweaks.textShade", "Text Shade")
	Link("UnitGroupFrames", "player:name", "Text", "Tweaks.textShade", "Text Shade")
	Link("Route", "Route", "General", "Tweaks.noticeOnScreen", "On-screen Notices")
	Link("Route", "Route", "Sound", "Tweaks.noticeSounds", "Notice Sounds")
	-- (0.19.4, the options audit: the name band keeps its own strength; the UI Shade reaches the plates on Whole plate only)
	-- (one-look D6: Whole plate is the Nameplate Kit's, so these two links need the kit too)
	-- (0.19.8, rule 9: the unit frames, the cast bars and the personal display have borders of their own now)
	-- (0.21.0, the user's picks: the level orb beside the portrait ring; the Personal Display's hold on the cast bar
	-- where the cast bar is set)
	-- (the Group Frames wear the Raid Frames pick's skin, border and bar texture)
	-- (Swing On The Rails makes the Swing Timers step aside)
	Link("ActionBars", "swing:element", "General", "PersonalDisplay.swing", "Swing On The Rails (Personal Display)",
		{ when = { key = "PersonalDisplay.!enabled", value = true, line = "Only with the Personal Display on" } })
	-- (0.19.4: the aura border is worn by MelloUI's own rows only)
	Link("Nameplates", "enemies:health", "Look", "BarTextures.healthColor", "Health Bar Colour")
	Link("Nameplates", "enemies:name", "Text", "UIModifications.nameFormat", "Names")
	Link("Nameplates", "enemies:debuffs", "Text", "Auras.textFont", "Numbers Font")
	Link("Minimap", "minimap:element", "Look", "UIModifications.shade_minimap", "UI Shade")
	Link("ActionBars", "cooldowns:element", "Look", "DarkMode.keepDispelColor", "Keep Dispel Colours")
	-- (the swing bars wear the cast bar's Bar Texture)
	Link("ActionBars", "swing:element", "Look", "BarTextures.castbarsTexture", "Bar Texture (Cast Bar)")
	Link("BarsMeters", "Damage Meter", "Look", "UIModifications.parchment_meter", "Parchment")
	Link("Chat", "Chat Frame", "Look", "UIModifications.shade_chat", "UI Shade")
	Link("Chat", "Chat Frame", "Text", "Fonts.scaleChat", "Chat Size")
	Link("Chat", "Whispers", "Look", "UIModifications.parchment_whisper", "Parchment",
		{ when = { key = "Chat.whisperPopup", value = true, line = "Only with the Whisper Popup Window" } })
	Link("Tooltip", "Tooltip", "Look", "BarTextures.texture", "Bar Texture (Look)", { when = HEALTH_BAR })
	Link("Tooltip", "Tooltip", "Look", "UIModifications.barBorder", "Progress Bar Border", { when = HEALTH_BAR })
	Link("ScreenText", "Combat Text", "Text", "Fonts.style", "Font")
	-- (one look: the Quest Tracker's paper on its own page; the Parchment tab keeps it in its list, the user's
	-- 0.19.1 "any Parchment Enable/Disable into the Parchment tab")
	Link("Oldschool", "Parchment", "Look", "UIModifications.parchment_questTracker", "Parchment: Quest Tracker")
	-- (one look, 2026-10-15: the chat's paper on the Chat page the same way)
	Link("Oldschool", "Parchment", "Look", "UIModifications.parchment_chat", "Parchment: Chat", { when = CHAT_PAPER })
	Link("QuestTracker", "Quest Tracker", "Look", "UIModifications.shade_tracker", "UI Shade")
	Link("QuestTracker", "Quest Tracker", "Text", "Fonts.style", "Font")
	Link("QuestTracker", "Quest Tracker", "Layout", "MinimapPanel.width", "Map Width")
	Link("QuestTracker", "Objective Tracker", "Look", "UIModifications.parchment_tracker", "Parchment", { when = GAME_TRACKER })
	Link("QuestTracker", "Objective Tracker", "Look", "UIModifications.shade_tracker", "UI Shade")
	Link("QuestList", "List", "Look", "UIModifications.QuestLogPanel", "Painted Skin (Quest Log)")
	-- (0.19.1, the user 2026-10-04: the borders on Oldschool > Borders, the text sizes and fonts on Look > Fonts, named
	-- where they were)
	Link("Oldschool", "Borders", "Look", "MinimapPanel.squareBorder", "Minimap Square Border")
	Link("Chat", "Chat Frame", "Text", "Fonts.fontChatText", "Chat Font")
	Link("Chat", "Chat Frame", "Text", "Fonts.scaleChatParchment", "Chat On Parchment Size")
	-- (the Bars audit's point 2: the timers' style on Look > Icons, linked from both of its places)
	Link("ActionBars", "actionbars:cooldown", "Text", "CooldownText.fontRatio", "Timer Text Size")
	Link("Nameplates", "enemies:auras", "Text", "CooldownText.fontRatio", "Timer Text Size")
	-- (one look, 2026-10-15: no Swing Timer Border link here -- the swing timers' Round rim wears no painted frame,
	-- the user's decision 8; the row on Oldschool > Borders stays until stage E's option table)
	Link("QuestTracker", "Quest Tracker", "Text", "QuestTracker.textSize", "Text Size")
	Link("QuestTracker", "Quest Tracker", "Text", "QuestTracker.headerSize", "Header Size")
	Link("ScreenText", "Combat Text", "Text", "Fonts.fontDamage", "Game Numbers Font")
end
