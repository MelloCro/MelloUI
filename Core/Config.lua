--------------------------------------------------------------------------------
-- MelloUI - Config
--
-- The configuration window, opened from its own MelloUI button at the game
-- menu (Escape; not while the game's Gamepad UI is on) or with /mello.
-- Nothing is registered with the Blizzard Settings panel, so there is no
-- entry under Options > AddOns.
--
-- Layout (the approved sketch of 2026-09-24; the rebuild of 0.15.0, the
-- user's decisions of 2026-09-27/28):
--   the shell           Kit:OwnWindow (Modules/KitWindow.lua): the emblem as a
--                       crest on the top rail, the short "MelloUI" plate under
--                       it, the drag strip, the fit, Escape, the sounds, the
--                       look switch (the kit or the plain palette look), and
--                       the calm ground (one flat mainWindow ground inside a
--                       band of the stone)
--   top bar             Install..., Edit Layout (while it is there) and
--                       close, on the right (Edit Layout, Core/EditLayout.lua,
--                       took the old Layout group's place in 0.15.0: the one
--                       place to move things)
--   side list           the pages in groups that fold (W.NavRail), from
--                       Core/ConfigLayout.lua's `groups`; the search box on it
--   page                header (icon, title, flavour, the page's switch,
--                       Reset this page; a picker page: its picker, Copy
--                       from, a live preview; Reset and Copy ask first),
--                       its tabs, and on each tab the
--                       sections in their fixed order (General, Look, Text,
--                       Layout, Behaviour, Sound, Advanced) as a striped
--                       ledger: label left, control right
--   Home                What's new and Your setup side by side, Help under them
--
-- Where every option lives is Core/ConfigLayout.lua's data (MelloUI.
-- ConfigLayout): one R line places a module's setting on a page, a tab and a
-- section, once; a Link line names it on another page (its value and a
-- button to its one place). The modules keep their option schemas as the
-- definitions, e.g.
--     { type = "toggle", key = "unitframes", name = "Unit Frames", desc = "..." },
--     { type = "slider", key = "shade", name = "Brightness", min = 0, max = 1, step = 0.05, percent = true },
--     { type = "dropdown", key = "style", name = "Style", values = { {value="a", label="A"}, ... } },
--     { type = "button", name = "Click, light", hint = "checkboxes, tabs", text = "Play", onClick = function(module, db) ... end },
-- with `parent` / `requires` (a switch of the same module the row hangs on),
-- `new` (the update it came with: its New tag), `free` (applied with UI
-- Modifications off), `get` (a value read another way), `missing` (0.17.0:
-- function() -> a line while this client lacks the setting, its row dimmed
-- with it), `search` (0.17.0: words the search finds the row by but no text
-- shows, e.g. its name before a rename) and `relist` (a bus topic its choices
-- are made again on). A page's side-list entry and header
-- show the `icon` and `flavour` of its layout entry, or of the module it
-- names ("module:<Name>", the registry's), else a question mark.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Config")
local hooksecurefunc = Perf.hooksecurefunc

local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local LOGO = TEXTURE_PATH .. "LogoIcon.tga"   -- the round emblem of the logo (user, 2026-09-24: new logo, "round_inner")
local LOGO_FULL = TEXTURE_PATH .. "LogoFull.tga"   -- the whole logo, for the home page's header
local ICON = "Interface\\Icons\\"
-- The widgets (switches, dropdowns, sliders, icon boxes, rows and their
-- hover, the colours by palette key): MelloUI.Widgets, Core/Widgets.lua, one
-- set for every own window (audit item 11). It loads right before this file.
-- The sounds ("page", "tab", the switches' clicks, the window's open and
-- close) go through MelloUI:PlayUISound, in Core.lua.
local W = MelloUI.Widgets
local Num = MelloUI.Safe.Number   -- (Core.lua's secret-safe reads, one set for the addon)

-- Core/Widgets.lua is a file an update added, and this client loads the
-- files an update adds only after a full restart (a /reload runs the new
-- code without them): until then the configurator stands down with one
-- line, /mello says it again, and its callers find stand-ins.
if not W then
	local LINE = "MelloUI was updated: restart the game once to finish (/reload does not load the new files)."
	MelloUI:Print(LINE)
	function MelloUI:RefreshConfig() end
	function MelloUI:OpenConfig()
		MelloUI:Print(LINE)
	end
	SLASH_MELLOUI1, SLASH_MELLOUI2 = "/mello", "/melloui"
	SlashCmdList.MELLOUI = function()
		MelloUI:Print(LINE)
	end
	return
end

-- (one size: the 1080 wide window UI Modifications' eight tabs needed went
-- with them in 0.15.0; a page's tab row wraps onto a second row, LayTabs)
local WINDOW_WIDTH, WINDOW_HEIGHT = 1000, 760
-- the parts, in UI units from the window's edges (the approved sketch)
local EDGE = 16                    -- the top bar's and the side list's margin
local BAR_TOP, BAR_HEIGHT = -70, 34   -- the top bar, under the drag strip (the shell's grab ends at BAR_TOP)
local BODY_TOP = -112              -- the side list and the page area
local NAV_WIDTH = 206              -- the side list's box
local PAGE_LEFT, PAGE_RIGHT = 234, -30   -- the page area; the classic scroll bar in the 30 px on its right
local CREST_SCALE = 1.25           -- the crest: 1.25 x the kit's portrait ring (user, 2026-09-25)
local PAD = 22
local ROW_HEIGHT = W.ROW_HEIGHT                 -- the widgets' typed rows (34)
local SLIDER_ROW_HEIGHT = W.SLIDER_ROW_HEIGHT   -- (40)

-- Palette
-- The configurator's colours, all from the palette (Core.lua, the user's
-- rule of 2026-09-23), by role: each role names a MelloUI.Palette KEY, looked
-- up when it is painted (W.Paint; "Palette-ready", user 2026-09-25: a
-- palette switch puts a new table there, so no colour is held
-- from load). Small reading text (hints, tooltips, flavour) is in `text`,
-- told apart from the labels by its size; muted text only marks what is
-- switched off (the palette's muted is 3.2:1, too faint for small text).
local C = {
	bg      = "mainWindow",
	band    = "innerPanel",
	panel   = "raisedPanel",
	stripe  = "mainWindow",   -- on the sections' dark inner panel (user, 2026-09-24: "everything is just too brown")
	line    = "border",
	hover   = "hover",
	accent  = "selectedTrim",
	accent2 = "trim",
	text    = "text",
	sub     = "text",
	dim     = "mutedText",
	on      = "selectedTrim",
	off     = "mutedText",
	knob    = "text",
}

local HOME_FLAVOUR = "Module based interface tweaks for World of Warcraft: Forever."
local PROFILES_META = { icon = ICON .. "INV_Scroll_06", title = "Profiles",
	flavour = "Your whole setup under one name. Save it, load it, or make it the default for a fresh install." }
local DEFAULT_ICON = ICON .. "INV_Misc_QuestionMark"

-- Shown on the Home page under "What's new". A short list in a player's
-- words; CHANGELOG.md has the whole release. Kept to about eleven short
-- lines: Home shows the newest version in a card one column wide, beside
-- Your setup and above Help.
local CHANGELOG = {
	{ version = "0.16.0", lines = {
		"Voice Over is a small widget: the speaker's face, the line and a gold ring that fills as it plays. Point at it for Pause, Skip, Lines and the padlock.",
		"New widgets in one column: loot rolls with Need, Greed and Pass, the way back to your corpse, a timed quest's clock, summons and resurrect offers, ready checks.",
		"More widgets: whispers with Reply, a pet that is not happy with Feed Pet, the auction house, your crafting batch, a profession cooldown ready again.",
		"Each widget has its switch on the Widgets tab. Move the column in Edit Layout or drag a widget; Lock The Widgets keeps it put. At most four show, Voice Over at the bottom.",
		"Threat without a meter: in group fights a line under enemy nameplates and a Threat widget that speaks up only when it matters.",
		"Reminders by your portrait for bags almost full, talent points to spend and Well Fed running out; they stay up in towns too.",
		"Whisper windows: Add Friend, Invite To Group, Ignore and Report buttons on the header.",
		"Gamepad UI: the Quest List's map marks are back. Point the cursor at one for its tooltip and press A to use it.",
		"Fewer settings that meant the same: one Show Names As for frames, nameplates and chat, one Class Coloured Names and one Text Shade, all on Look.",
		"Tooltip and Chat: one Background choice each (Painted, Parchment, Dark, Game). Name Shade takes Whole plate and follows the UI Shade's strength.",
		"The Quest Tracker's and the Route arrow's size is Edit Layout's wheel; Route's notices follow On-screen Notices; Restock's reminder is part of Restock. Your settings carry over.",
		"New files: restart the game once after updating.",
	} },
	{ version = "0.15.0", lines = {
		"Gamepad UI: no more freezes on Escape, Options or the world map, and no \"blocked\" popup. If that popup turned MelloUI off, tick it again in the AddOns list.",
		"An objective that needs an item first now leads you to where the item comes from, with the arrow, the World Marker and a \"First: ...\" line in the Quest Tracker.",
		"World Marker: a beacon with the distance when far away, a pin on the spot within 100 yards, out of the way inside a quest's area. The first route says Loading navigation.",
		"Active look: whatever is on, checked or selected (your stance or form, auto attack, an open bag, the selected tab) wears one thick gold ring with a soft glow.",
		"Nameplates show the level on a dark disc. Elites, rares and bosses wear metal marks on nameplates and on the target and focus frames: gold crown, silver star, red-bronze skull.",
		"Minimap: its normal size again, with Width and Height sliders; the Quest Tracker hangs right under the map, as wide as it. Mello's layout from before? Press Fit to this screen once.",
		"This window is rebuilt in a calmer look: groups in the side list, every option in one place, flat buttons, sliders you can type a number into, and search that lights the row.",
		"Edit Layout (/mello edit): drag anything, the wheel resizes, right-click for exact numbers, and it snaps to its neighbours. Nothing sticks until you Save; action bars go to Edit Mode.",
		"The Quest Log and the Quest List match: the same rows, fonts, round bullets and Classic or Forever stamps, in dark ink on parchment.",
		"A new voice pack, MelloUI_VoicePack, voices every quest, greeting and book, one voice per NPC. It is a separate download that replaces the old pack.",
		"Books, letters and plaques are read aloud to the last page, even as you walk on (Read Books And Letters Aloud). The Quest List has the 19 quests with Test back.",
		"/mello on its own opens this window again. New files: restart the game once after updating.",
	} },
	{ version = "0.14.0", lines = {
		"Six new palettes, each with its own painted kit: Obsidian, Royal Azure and Fel Ember, each with a Vibrant version. Pick one on Your setup here or in Dynamic UI Modification.",
		"A soft shade round the painted kit (UI Shade, UI Modifications). Centre Text Shade: red errors, quest lines, raid warnings and boss emotes on the zone text's shade (Tweaks).",
		"Reminders: one round button beside your portrait for supplies, mail, worn gear and training; right-click for Not now. In an inn or a city they stay until done.",
		"Restock: a list per character of drink, food, ammunition and reagents. At a shop it shows what to buy; nothing is bought until you click Buy.",
		"The Services bar has a sixth group, Errands, and says when it can't place you. Zephras Isle: routes, the Services bar and the Quest List work there now.",
		"The Quest Tracker puts the nearest quest first, with a distance on each. Tooltips say Turn in here or Quest ends here on the NPCs who take your quests back.",
		"Flights: the flight map shows where your route flies and how long it takes; while you fly, the arrow counts down to the landing.",
		"Quality Gems: every item in your bags, bank and guild bank wears a gem in its quality colour; parchment tooltips put one before item and player names.",
		"Gains: skill ups, new items and what you buy float beside your character on a soft shade, then fade (Quests and travel).",
		"Fade Out Of Combat (Unit Frames, off at first): your player and pet frames fade away until a fight, a target or a scratch brings them back.",
		"Search: type in the box above the side list to go straight to any option. Long lists like the fonts scroll now. New files: restart the game once.",
		"Macro Backup is a switch on the Profiles page, off at first; a copy comes back only when you ask. Using Mello's layout from before? Press Fit to this screen once.",
	} },
	{ version = "0.13.7", lines = {
		"Two folders now: Route's road data lives in MelloUI_Companion, loaded only when you route somewhere. Copy both folders into AddOns and restart the game once.",
		"An installer sets MelloUI up fitted to your screen: Install… at the top or /mello install. Fresh start asks Round or Square minimap and which features you want, each with Mello's settings.",
		"A new settings window: the modules in a side list by group, a Home with your setup, and Dynamic UI Modification as the one place for the look.",
		"Less memory, quicker loading: the textures take about 30 MB instead of 96 MB, and this window, parchment windows and flight masters open without a stall.",
		"One on-screen notice for all of MelloUI, and soft shades so text reads on bright ground: nameplate names (fitted to each name), Route's arrow and World Marker, the zone name as you enter.",
		"Route shows travel time (how long the rest of the way takes, flights and boats included, from how fast you really move) and routes overseas by boat or zeppelin.",
		"By the minimap: a bigger minimap in Mello's layout, your buffs beside it, the Services bar in groups under a rail, the Quest Tracker as wide, never behind it or on the Services row.",
		"MelloUI's own windows, this one too, change look the moment you flip the reskin and move with Unlock the Windows; more game windows have the painted look (UI Modifications, Windows).",
		"Easier on the eyes: text-heavy areas lie on a dark panel, titles sit on their plates, text on parchment no longer flickers white, and Kit Colours: Warm iron, Bronze, Original.",
		"Dark Mode is yours: no profile or setup changes it. Loading a profile keeps your flight points and no longer turns Custom Sounds back on; Mello's Edit Mode layout is the new Immersive one.",
		"Also new: a logo, smooth chat scrolling, one background opacity for every chat window (profiles carry it), parchment tooltips, eleven fonts, six Font Styles and Names In Chat.",
	} },
	{ version = "0.13.6", lines = {
		"New modules, off until you switch them on: Quest Tracker (a scrolling tracker), Error Messages and Buffs & Debuffs.",
		"Route: World Marker and Light Beam over the destination, routes to a quest's objectives themselves, roads across zone borders, only flight points you know.",
		"Quests: the Classic or Forever logo on every quest, 5,882 quests, item and object starters with their own map icons, and filters by what a quest starts from.",
		"Whisper Popup Window, Windows Fade In, Reduce Motion, Preload Artwork, and parchment sheets as a choice.",
		"Profiles can be shared as a short string; Bar Textures gained By health colours and an Execute Range.",
		"Painted brush-stroke edges on the parchment and stone pages; combat fixes for the damage meter and moved windows.",
	} },
	{ version = "0.13.5", lines = {
		"A Discord for MelloUI: help, bug reports and every new release (the link is in the release notes).",
		"Unlock the Windows leaves the chat and the damage meter clickable, shows every drag area as a gold band and puts a plate on screen while unlocked.",
		"Settings changed in the first moments of a session are no longer lost; UI Modifications says when every area is off.",
	} },
	{ version = "0.13.4", lines = {
		"The painted kit reskin: every window and the whole HUD dressed in the painted art, one switch and one toggle per area under UI Modifications.",
		"Unlock the Windows: drag any window, the minimap, the tracker, the meter and the chat; the wheel scales; positions stay.",
		"A guided tour of this window (the Tutorial button, /mello tutorial), offered on the first login; a fresh install starts with everything off (the built-in Everything Off profile).",
		"Voice Over reads the right quest once the panel has settled, plays old recordings for renumbered quests, and lists the vanilla lines the pack never had.",
		"Bar Textures: the game's own textures as a choice and a health colour that overrides threat; Fonts: one font per role; Dark Mode darkens the reskin.",
		"Settings: a larger macro backup, window positions kept, profile names as typed; dozens of fixes from a full audit.",
		"Custom Sounds, a new module (off until you turn it on): the interface's clicks, pages, pouches, buckles, coins, whispers and the group finder bell re-recorded in iron, leather, parchment and stone.",
	} },
	{ version = "0.13.3", lines = {
		"Chat notices can be turned off under Tweaks; replies to slash commands always show.",
		"Report a problem link on this page; the addon list shows the MelloUI icon.",
		"Lighter minimap stand texture; the Quest List code is in three files.",
	} },
	{ version = "0.13", lines = {
		"Configuration window with its own button in the game menu.",
		"Bag slots dock under the bag window while the bag bar is hidden.",
		"Dungeon and raid doors are learned on the way in and on the way out.",
		"Services bar under the minimap: nearest repair, mailbox, innkeeper, bank and more.",
		"Route arrow, tracking notices and objective routing for the tracked quest.",
		"Profiles, with a bundled default applied on a fresh install.",
		"Voice Over: quest log read-aloud, paged subtitles, lock button on the overlay.",
	} },
}
local LINKS = {
	{ "GitHub", "https://github.com/MelloCro/MelloUI" },
	{ "Report a problem", "https://github.com/MelloCro/MelloUI/issues" },
	{ "CurseForge", "https://www.curseforge.com/wow/addons/melloui" },
	{ "Voice pack", "https://github.com/MelloCro/MelloUI/releases" },
}
-- The commands a player uses. The dump and diagnostic commands for tuning
-- the addon stay out of this list (/mello help prints a few of them below it).
local COMMANDS = {
	{ "/mello", "open or close this window" },
	{ "/mello <page>", "open a page by its name (a module's name works too)" },
	{ "/mello list", "modules and their state" },
	{ "/mello enable <module>", "turn a module on" },
	{ "/mello disable <module>", "turn a module off" },
	{ "/mello profile ...", "save, load, share or delete profiles, set the default" },
	{ "/mello status", "where your settings came from, and their backup" },
	{ "/mello backup ...", "Macro Backup: on, off, restore or delete the copy" },
	{ "/mello install", "set MelloUI up: a setup, your screen, keep or go back" },
	{ "/mello edit", "Edit Layout: move and resize the interface" },
	{ "/mello preview solo", "a fight, alone or (party) in a group, played to see" },
	{ "/mello preview <part>", "one part alone: fader, widgets, meter, gains ..." },
	{ "/mello swing log", "20 s of your swings and shots, to copy (/mellolog)" },
	{ "/mello layout apply", "Mello's Edit Mode layout, fitted to your screen" },
	{ "/mello tutorial", "the guided tour of this window" },
	{ "/melloperf", "what MelloUI costs: its time per frame, its slowest frames" },
	{ "/melloperf record", "measure while you play (30 s, or /melloperf record 60)" },
	{ "/melloperf report", "the last recording's report again, to copy" },
	{ "/melloperf load", "how long each part took to load, and its memory" },
	{ "/mellolog", "MelloUI's recent messages in a window to copy" },
	{ "/sfx", "Custom Sounds: its state and the slowest sounds" },
	{ "/sfx play <name>", "hear one custom sound (/sfx list names them)" },
	{ "/vo stop | pause | skip", "stop, pause or skip the voice that is reading" },
	{ "/vo read", "read the quest selected in the quest log aloud" },
	{ "/vo test", "a test line in the targeted NPC's voice" },
	{ "/vo packs", "which voice packs are installed" },
	{ "/vo reset", "the Voice Over window back to its place" },
	{ "/route status", "the route, its road data and your flight points" },
	{ "/route clear", "stop the route" },
	{ "/route arrow reset", "the direction arrow back to the top of the screen" },
	{ "/services", "the list of the nearest services" },
	{ "/services <service>", "route to the nearest one, e.g. /services repair" },
	{ "/restock", "your Restock List: what to keep in your bags" },
}

local function Meta(module)
	return module.icon or DEFAULT_ICON, module.flavour or module.desc or ""
end

local window
local shell   -- the window's shell (Kit:OwnWindow): its look, crest, plate, mover, fit, Escape, sounds
-- The built pages of each look ([true] the kit's, [false] the plain one):
-- a look switch shows the other set, made on its first show in that look and
-- kept after (at most two sets a session; switching back reuses the first)
local pagesBy = { [true] = {}, [false] = {} }
local pages = pagesBy[false]   -- the set of the look in use
local currentPage = nil

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------

-- Text(parent, font, text, key), Solid(parent, layer, key, alpha): the
-- widgets' (colours by key)
local Text, Solid = W.Text, W.Solid

local function WrappedHeight(fs, fallback)
	local ok, h = pcall(fs.GetStringHeight, fs)
	if ok and type(h) == "number" and h > 0 then
		return h
	end
	return fallback or 14
end

local function ModuleByName(name)
	if not name then
		return nil
	end
	local module = MelloUI.modules[name]
	if module then
		return module
	end
	local wanted = name:lower()
	for key, m in MelloUI:IterateModules() do
		if key:lower() == wanted or m.title:lower() == wanted or (type(m.slash) == "string" and m.slash == wanted) then
			return m
		end
	end
	return nil
end

-- The handlers the pages share (user, 2026-09-24: a page of two hundred rows
-- made a dozen functions per row, each wrapped and named by the profiler as
-- it was set): one function each, wrapped once (Perf.Shared), reading what
-- it shows from the frame it runs on. The rows' and controls' own are the
-- widgets'.
local Shared = Perf.Shared or function(_, fn) return fn end

--------------------------------------------------------------------------------
-- The painted kit on the configurator itself (user, 2026-09-21; picks CT2 SI1
-- from kit_raw/config_catalog.png): its look switch is Kit:IsOn('config')
-- (the UI Modifications reskin). The window is one own window on
-- Kit:OwnWindow (Modules/KitWindow.lua, audit item 8): the shell reads the
-- look at every show and switches it live on 'look:config' (a change showed
-- only after /reload before the audit, 2026-09-24, rank 1). The shell, the
-- top bar and the side list switch with it; the pages are made for one look
-- (a plain page never queues kit dressing), so each look keeps its own set
-- of pages (pagesBy), made on its first show in that look. Every piece goes
-- through Kit:Replace with the fixed looks' keys: the crest and its short
-- plate, the outer double rail, the page stone, R1 rims on the icons, TB6
-- tabs, L1 boxes around the sections and the side list, plate rows with a
-- hover, the kit's check boxes, red buttons, D1 dropdowns, the kit slider,
-- the kit's title face on the titles.
--------------------------------------------------------------------------------

-- The pages' look: the Kit (KIT) and the shell (SKIN, what the widgets ask
-- of a shell: skin:Replace, skin:Anchor, skin:Kit, skin.replace, skin.skin)
-- while the shell's look is the kit's, nil in the plain look. Set when the
-- window is made and at every look switch (Config_OnKit). The shell's own
-- parts, the top bar and the side list are made with the shell itself, so
-- they switch with it.
local KIT = nil
local SKIN = nil

-- A framed icon (the widgets' IconBox): the client's action button bevel
-- around a rounded icon, grey at rest, gold when selected, the text colour
-- while hovered; with the kit, the rim every window's buttons wear (user,
-- 2026-09-24: the icons follow the look's settings) -- the Button Border
-- (Look > Borders), swapped live with it, in the Kit Colours look -- showing the box's states: gold (checked) for the current page,
-- pressed while held, hover. box:SetGlow(on): a pulsing gold glow over the
-- rim for an important module (Anim:Pulse; a still glow under Reduce Motion).
local function IconBox(parent, size, texture)
	return W.IconBox(parent, size, texture, SKIN)
end

--------------------------------------------------------------------------------
-- Widgets: the switches, dropdowns and sliders, the rows and their hover are
-- MelloUI.Widgets' (lifted from here, taking get / set). What the
-- configurator hands them:
--------------------------------------------------------------------------------

-- a switch's options: the window's look (one table, filled per switch)
local SWITCH = {}
local function SwitchOpts()
	SWITCH.skin = SKIN
	return SWITCH
end

-- the hover of the rows the configurator lays itself (the Profiles page's
-- rows): the palette's wash at half strength with its gold edge, in both
-- looks
local ROW_HOVER = { look = "palette", strength = 0.5 }

--------------------------------------------------------------------------------
-- Sections and rows
--
-- A page owns sections; a section is a frame holding rows, one per tab when
-- there is more than one. On an element page a tab's section lays its rows
-- under headings (W.Header), one per section of the fixed order (the
-- layout's SECTIONS: General, Look, Text, ...), 8 px apart.
--------------------------------------------------------------------------------

local SelectPage, NavFollow  -- forward declarations

local SEC_INSET = 10   -- the rows' margin inside a section's panel
local INDENT = 22      -- a sub-option's label, per level, right of its parent's
local PANEL_ON = { on = true }   -- (W.Panel's options: the section is its own panel)

-- The section's panel (0.15.0, the cleaner look the user picked: W.Panel, a
-- flat inner panel in a 1 px edge on the calm ground, in both looks; the
-- kit's L1 list box before). Made with the section's first rows (a tab not
-- open yet costs nothing until its rows are made: user, 2026-09-24), or at
-- once for a section made whole
local function SectionPanel(sec)
	if sec.needsPanel then
		sec.needsPanel = nil
		W.Panel(sec, PANEL_ON)
	end
end

local function NewSection(page, name)
	local sec = CreateFrame("Frame", nil, page)
	sec.name = name
	sec.page = page
	sec.y = SEC_INSET
	sec.rows = 0
	sec.refreshers = {}
	sec:SetWidth(page.width - PAD * 2)
	sec:SetHeight(10)
	sec:Hide()
	sec.needsPanel = true   -- (SectionPanel)
	function sec:Refresh()
		for _, fn in ipairs(self.refreshers) do
			fn()
		end
	end
	-- (as tall as its rows will be while some are still to be made, when
	-- their heights are known: the scroll bar does not jump as they come)
	function sec:Finish()
		local y = (self.jobs and self.plannedY) or self.y
		self:SetHeight(math.max(y + SEC_INSET, 10))
	end
	page.sections[#page.sections + 1] = sec
	return sec
end

--------------------------------------------------------------------------------
-- A page made a little at a time (user, 2026-09-24: "clean up the spikes";
-- the first click on a module tile built its page in 170 ms in one frame):
-- a section's rows are jobs, made in order. The rows in view come first:
-- a page or a tab opened, or a scroll that reaches rows not made yet, makes
-- the open tab's rows in view there and then (only those in view when the
-- rows above them are not made either); the rest follow a few milliseconds
-- a frame, the open tab first, then the other tabs in their order. All of
-- it keeps to one budget of rows a frame, whoever makes them: what the
-- budget leaves of a view is the first work of the frames after it, before
-- any row out of view. A section is as tall as its rows will be from the
-- start. Built pages are kept, as before. The frames that make them belong
-- to the window, so nothing is made while it is closed.
--------------------------------------------------------------------------------

local BUILD_BUDGET = 2.5   -- ms of rows a frame after the first (and the one row under way past it)
-- ms of rows in the frame that opens a page or a tab, or scrolls to rows
-- not made yet (the row under way finished, as above): the rest from the
-- worker while the page fades in, so that frame keeps within 5 ms with the
-- page's own parts (configurator build, 2026-09-25: it made every row in
-- view at once)
local FIRST_BUDGET = 3
-- One budget of rows a frame, whoever makes them: the widget set's
-- (W.RowBudget), which the installer's pages share. None begin inside rows
-- under way (a scroll set while a row is made has its view made after them,
-- MakeRowsInView, or first thing in the worker's next frame, OwedView).
-- The deadline for up to `ms` of rows now, less those this frame has made;
-- nil when none are left or rows are under way. EndRows counts them.
local BeginRows, EndRows = W.RowBudget.Begin, W.RowBudget.End

-- pages with rows still to make, in the order they were opened: a list per
-- look, as the pages (pagesBy), so the set not on show is not worked on
local buildingBy = { [true] = {}, [false] = {} }
local building = buildingBy[false]
local worker          -- the window's frame whose OnUpdate makes them

-- A page's height from its open tab, set through the pager (its canvas, the
-- scroll child, follows only the page on show): the one way the three
-- places that lay a page's height set it (a tab made whole, a tab opened,
-- the Profiles list)
local function PageHeight(page, sec)
	page.pager:SetPageHeight(page, page.headerHeight + sec:GetHeight() + PAD)
end

-- A job for the section: `run(sec, job)` makes it; `height`, when given,
-- is the row's height (one row; 0: none), added to the section's planned
-- height, and where the row goes is kept with the job: a section whose jobs
-- all have one can make the rows in view before those above them
local function Queue(sec, job, run, height)
	local jobs = sec.jobs
	if not jobs then
		jobs = {}
		sec.jobs, sec.nextJob = jobs, 1
		sec.jobY, sec.jobRow, sec.plannedRows, sec.unsized = {}, {}, sec.rows, nil
	end
	local n = #jobs + 1
	jobs[n] = job
	sec.runJob = run
	if height then
		local y = sec.plannedY or sec.y
		sec.jobY[n], sec.jobRow[n] = y, sec.plannedRows
		sec.plannedY = y + height
		if height > 0 then
			sec.plannedRows = sec.plannedRows + 1
		end
	else
		sec.unsized = true
	end
end

-- The rows in view made out of turn (user, 2026-09-24: a tab opened, or the
-- scroll bar dragged, far down the page before the worker came to it made
-- every row above the view as well -- 24 ms in one click): the jobs whose
-- rows reach into [minY, maxY), each at its own place and zebra band, until
-- `deadline` (the row under way finished; the rest of the view is the
-- worker's first work, OwedView); those above are left to the worker, which
-- steps over the rows made here
local function RunInView(sec, minY, maxY, deadline)
	local jobs, ys, rowsAt = sec.jobs, sec.jobY, sec.jobRow
	for n = sec.nextJob, #jobs do
		local top = ys[n]
		if top >= maxY then
			break
		end
		local job = jobs[n]
		if job and (ys[n + 1] or sec.plannedY) > minY then
			jobs[n] = false
			sec.y, sec.rows = top, rowsAt[n]
			sec.runJob(sec, job)
			if deadline and debugprofilestop() >= deadline then
				break
			end
		end
	end
end
local function MakeRowsInView(sec, minY, maxY, deadline)
	-- (the section's cursor put back whatever happens: the worker goes on
	-- from it; a scroll set while these rows are made leaves its view in
	-- `viewMin` / `viewMax`, made after them while the deadline allows)
	local cursorY, cursorRows = sec.y, sec.rows
	sec.outOfTurn = true
	local ok, err
	repeat
		sec.viewMin, sec.viewMax = nil, nil
		ok, err = pcall(RunInView, sec, minY, maxY, deadline)
		minY, maxY = sec.viewMin, sec.viewMax
	until not (ok and minY) or (deadline and debugprofilestop() >= deadline)
	sec.y, sec.rows = cursorY, cursorRows
	sec.outOfTurn, sec.viewMin, sec.viewMax = nil, nil, nil
	if not ok then
		error(err, 0)
	end
end

-- Make the section's rows, in order: all of them, those above `maxY` (in
-- the section's own units), or as many as fit before `deadline` (a
-- debugprofilestop time; the row under way is finished). With `minY` (the
-- top of the view) and the rows above it not made yet, only the rows in
-- view are made (MakeRowsInView, within the same deadline). True once the
-- section is complete.
local function MakeRows(sec, maxY, deadline, minY)
	local jobs = sec.jobs
	if not jobs then
		return true
	end
	if sec.outOfTurn then
		-- (a scroll set while the rows in view are made: its view is made
		-- after them, MakeRowsInView)
		if minY and maxY then
			sec.viewMin, sec.viewMax = minY, maxY
		end
		return false
	end
	SectionPanel(sec)
	local page = sec.page
	local refreshers = sec.refreshers
	local first = #refreshers + 1
	local count = #jobs
	if minY and maxY and not sec.unsized and sec.y < minY then
		MakeRowsInView(sec, minY, maxY, deadline)
		maxY = sec.y   -- (only the made rows at the cursor stepped over below)
	end
	-- (the cursor is the section's own, read again for every row: a scroll
	-- set while a row is made -- the game's scroll bar answering a new
	-- range -- may make rows itself, or even finish the section)
	while sec.jobs == jobs and sec.nextJob <= count do
		local n = sec.nextJob
		local job = jobs[n]
		if not job then
			-- made out of turn: the cursor steps over its place
			sec.nextJob = n + 1
			sec.y = sec.jobY[n + 1] or sec.plannedY or sec.y
			sec.rows = sec.jobRow[n + 1] or sec.plannedRows or sec.rows
		elseif maxY and sec.y >= maxY then
			break
		else
			jobs[n] = false
			sec.nextJob = n + 1
			sec.runJob(sec, job)
			if deadline and debugprofilestop() >= deadline then
				break
			end
		end
	end
	-- rows made on the open tab take their values before they are drawn
	-- (a tab's own refresh does the rest when it opens)
	if page.current == sec then
		for i = first, #refreshers do
			refreshers[i]()
		end
	end
	if sec.jobs ~= jobs then
		return true
	end
	if sec.nextJob <= count then
		return false
	end
	sec.jobs, sec.nextJob, sec.runJob, sec.jobY, sec.jobRow = nil, nil, nil, nil, nil
	sec:Finish()
	if page.current == sec then
		PageHeight(page, sec)
	end
	if page.onSectionDone then
		page.onSectionDone(sec)
	end
	return true
end

-- The top and the bottom of the view in a tab's section units: the rows it
-- needs before it is drawn (plus one above and one below), at the scroll it
-- will show at (the game's scroll bar brings the offset down to the end of
-- a tab shorter than the one before). A page not on show yet (one being
-- made) shows from its top; the page on show sits at the canvas's top, so
-- the scroll's offset is its own.
local function ViewRange(page, sec)
	local pager = page.pager
	local scroll = pager.scroll
	local height = scroll:GetHeight()
	if not (type(height) == "number" and height > 0) then
		height = WINDOW_HEIGHT
	end
	local offset = 0
	if pager:Current() == page then
		offset = scroll:GetVerticalScroll() or 0
		local most = page.headerHeight + sec:GetHeight() + PAD - height
		if offset > most then
			offset = math.max(0, most)
		end
	end
	local top = offset - page.headerHeight
	return top - ROW_HEIGHT, top + height + ROW_HEIGHT
end

-- Rows scrolled into view before the worker came to them (the wheel, the
-- scroll bar dragged, a jump), made now, before they are drawn, within the
-- frame's one budget of rows: those in view only when the rows above them
-- are not made either (MakeRowsInView). What the budget leaves (the worker
-- or a click had it this frame) is the worker's first work in the next
-- (OwedView). One function for every window's page scroll, hooked on our
-- own scroll frame.
local RowsInView = Shared("SetVerticalScroll on the configurator's pages", function(scroll)
	if not (window and scroll == window.scroll) then
		return
	end
	local page = currentPage and pages[currentPage]
	local sec = page and page.current
	if not (sec and sec.jobs and page.pager:Current() == page) then
		return
	end
	local top, bottom = ViewRange(page, sec)
	if sec.outOfTurn then
		-- (a scroll set while the rows in view are made out of turn: MakeRows
		-- keeps its view, made after them within their deadline)
		MakeRows(sec, bottom, nil, top)
	elseif sec.y < bottom then   -- (the cursor below the view: every row in it made)
		local deadline = BeginRows(FIRST_BUDGET)
		if deadline then
			MakeRows(sec, bottom, deadline, top)
			EndRows()
		end
	end
end, "hook")

-- The next section to make rows for: the open page's open tab, its other
-- tabs in their order, then the pages opened before it
local function NextSection()
	local page = currentPage and pages[currentPage]
	if page then
		if page.current and page.current.jobs then
			return page.current
		end
		for _, sec in ipairs(page.sections) do
			if sec.jobs then
				return sec
			end
		end
	end
	for _, p in ipairs(building) do
		for _, sec in ipairs(p.sections) do
			if sec.jobs then
				return sec
			end
		end
	end
	return nil
end

-- The view the worker owes rows first: that of the open tab of the page on
-- show, when rows in it are still to make below rows not made either (a
-- view reached out of turn and left at its budget). Its top and bottom;
-- nil when the worker's next row is the view's own, or none is owed.
local function OwedView(sec)
	local page = sec.page
	if sec.unsized or page.current ~= sec or page.pager:Current() ~= page then
		return nil
	end
	local top, bottom = ViewRange(page, sec)
	if sec.y >= top then
		return nil
	end
	local jobs, ys = sec.jobs, sec.jobY
	for n = sec.nextJob, #jobs do
		if ys[n] >= bottom then
			return nil
		end
		if jobs[n] and (ys[n + 1] or sec.plannedY) > top then
			return top, bottom
		end
	end
	return nil
end

local function Work(self)
	local deadline = BeginRows(BUILD_BUDGET)
	if not deadline then
		return   -- (this frame's rows are made: a click's or a scroll's)
	end
	repeat
		local sec = NextSection()
		if not sec then
			EndRows()
			for i = #building, 1, -1 do
				building[i] = nil
			end
			self:Hide()
			return
		end
		local top, bottom = OwedView(sec)
		MakeRows(sec, bottom, deadline, top)
	until debugprofilestop() >= deadline
	EndRows()
end

-- rows still to make: the worker on (it stops by itself when all are made)
local function Kick()
	if worker and not worker:IsShown() and NextSection() then
		worker:Show()
	end
end

-- A ledger row (W.Row and the typed rows): stripe, label, optional hint,
-- tooltip with the description; with the kit a faint band on every other row
-- (CR4, user 2026-09-21) and the plate's hover look on the row under the
-- mouse only, plain the palette's hover wash and a line under it. The label
-- and the hint end 10 px left of the row's control, cut there, the full text
-- in the tooltip (no text under a control). A row that sleeps until a switch
-- is on (`sec.gate` while it is made, W.Gate) is dimmed, and its hint slot
-- says which switch wakes it, so it keeps its height. The section keeps
-- where the next row goes (`y`) and how many it holds (`rows`).
local ROW = {}   -- the rows' options (one table, filled per row)
-- `new`: the update the row's option came with (its New tag, W.Row's
-- opts.new): the schema's `opt.new`, or a hand-built row's (a named table's
-- `new`, as the Profiles page's BACKUP_TAG.new)
local function RowOpts(sec, new)
	ROW.skin = SKIN
	ROW.new = new
	ROW.inset = SEC_INSET
	ROW.indent = (sec.indent or 0) * INDENT
	ROW.zebra = (KIT and sec.rows % 2 == 0) and true or false
	ROW.line = not KIT
	ROW.look = KIT and "plate" or "palette"
	ROW.gate, ROW.onCover = sec.gate, nil
	ROW.labelKey, ROW.hintKey = nil, nil
	return ROW
end

-- after a row: the section's place for the next one
local function Placed(sec, row, height)
	sec.y = sec.y + height
	sec.rows = sec.rows + 1
	return row
end

-- A row with a button on the right (user, 2026-09-22: "a preview button on
-- each sound effect"): the label, a grey hint, and a flat button with
-- `opt.text`; `opt.onClick(module, db)` on the click.
local RowButtonClick = Shared("OnClick on the configurator's row buttons", function(self)
	local opt = self.melloOpt
	if opt.onClick then
		opt.onClick(self.melloModule, MelloUI:GetModuleDB(self.melloModule.name))
	end
end, "script")

--------------------------------------------------------------------------------
-- Pages
--
-- The page area is MelloUI.Widgets' Pager (configurator build, 2026-09-25):
-- one scroll frame whose child is a canvas holding every built page. A
-- switch puts the new page at the top and fades it in, sliding 12 px in
-- from the side of the list it lies on, while a shield over the page area
-- takes the mouse until it is in; instant under Reduce Motion, when the
-- window has just been opened, and for the tour. Two safe fallbacks are on
-- until an in-game check of the clipping and of the slide's cost says
-- otherwise, one switch each:
--   PAGER.outInstant   true: the page going hides at once and only the new
--                      one fades and slides; false: it fades out where it
--                      is on screen, pinned at its scroll
--   ALPHA_ONLY_ROWS    a page whose largest tab holds more rows only fades,
--                      it never slides; nil: every page slides
-- (at run time: MelloUI:ConfigTour().pager.cf.outInstant, and
-- pager:AlphaOnly(page, on) for one page)
--------------------------------------------------------------------------------

local PAGER = { step = 80, slide = 12, outTime = 0.10, inTime = 0.15, outInstant = true,
	template = "UIPanelScrollFrameTemplate" }   -- (`name` per window: CreateWindow)
local ALPHA_ONLY_ROWS = 40

local HEADER_ICON = 58   -- the page header's framed icon (the approved sketch)

-- a page header's height from its parts as they are now (the title, the
-- flavour as it wraps, the icon, an element page's live preview), down to
-- where the tabs or the first section start; a picker page's picker line
-- under them (its place: page.pickerY)
local function HeaderHeight(page)
	local y = PAD + math.max(HEADER_ICON, 26 + 6 + WrappedHeight(page.flavour, 14), page.previewH or 0)
	if page.pickerLineH then
		page.pickerY = y + 8
		y = page.pickerY + page.pickerLineH
	end
	return y + 18
end

-- a page's tab: its section's page opens it
local TabClick = Shared("OnClick on the configurator's tabs", function(self)
	MelloUI:PlayUISound("tab")
	local page = self.section.page
	local changed = page.current ~= self.section
	page:Select(self.section, true)
	-- (an open picture flyout closes with the tab it belongs to)
	if changed then
		W.ClosePictureMenu(window)
	end
end, "script")

-- A tab switch (configurator build, 2026-09-25): the tab going fades out
-- as the one coming fades in, alpha only (instant under Reduce Motion). One
-- table for every switch; `instant` and `outInstant` are set per call.
local TAB_CF = { slide = 0, outTime = 0.10, inTime = 0.12, instant = false, outInstant = false }

-- Whether the page's scroll comes down when the tab `sec` lays its height:
-- a tab too short for the scroll (the game's scroll bar brings the offset
-- down to its end, and the tab going would jump under its fade)
local function ScrollDrops(page, sec)
	local pager = page.pager
	if pager:Current() ~= page then
		return false
	end
	local scroll = pager.scroll
	local offset = scroll:GetVerticalScroll() or 0
	local height = scroll:GetHeight()
	if not (type(height) == "number" and height > 0) then
		height = WINDOW_HEIGHT
	end
	return offset > 0 and offset > page.headerHeight + sec:GetHeight() + PAD - height
end

-- A page: a frame of the pager's canvas (MelloUI.Widgets' Pager, held by
-- one TOPLEFT point), put on show by SelectPage. It is shown while it is
-- made, as it was when it hung from the scroll frame itself (its parts come
-- in without an OnShow each); the pager shows it in the same frame.
local function NewPage(name, width)
	local pager = window.pager
	local page = pager:NewPage()
	page:Show()
	page.pager = pager
	page.name = name
	page.width = width
	page.sections = {}
	page.refreshers = {}
	page.headerHeight = 0
	page.current = nil
	page:SetSize(width, 10)
	building[#building + 1] = page   -- its rows still to make, if any (the worker drops it when none are)

	function page:Refresh()
		self.stale = nil
		for _, fn in ipairs(self.refreshers) do
			fn()
		end
		if self.current then
			self.current:Refresh()
		end
	end

	-- A tab opened: its rows down to the bottom of the view made before it
	-- shows, within the frame's FIRST_BUDGET ms of rows (the rest follow
	-- a few a frame, the rows in view first); then the tabs cross-fade
	-- (`animate`: a tab clicked) or change at once (a page's first tab, as
	-- the page is made). The tab going hides at once when the scroll comes
	-- down to the end of a shorter one.
	function page:Select(sec, animate)
		local prev = self.current
		if self.tabsStale then
			self:LayTabs()   -- (a font change since the tabs were laid)
		end
		if sec.jobs then
			local deadline = BeginRows(FIRST_BUDGET)
			if deadline then
				local top, bottom = ViewRange(self, sec)
				MakeRows(sec, bottom, deadline, top)
				EndRows()
			end
		end
		self.current = sec
		local Anim = MelloUI.Anim
		for _, other in ipairs(self.sections) do
			-- (a tab still fading out from the switch before ends its fade)
			if other ~= sec and other ~= prev and other:IsShown() and not Anim:IsRunning(other, "alpha") then
				other:Hide()
			end
		end
		TAB_CF.instant = not animate
		TAB_CF.outInstant = prev ~= nil and prev ~= sec and ScrollDrops(self, sec)
		Anim:CrossFade(prev, sec, TAB_CF)
		if self.tabs then
			for _, tab in ipairs(self.tabs) do
				tab:SetSelected(tab.section == sec)
			end
		end
		sec:Refresh()
		PageHeight(self, sec)
		Kick()
	end

	-- A deep link (a search result, a link row, a sleeping row's switch): the
	-- tab `sec` opened, then the page scrolled so the row at `y` (the tab's
	-- own units) sits just under the top of the view -- a glide, or at once
	-- (`instant`). The rows in view there come through the scroll hook within
	-- the frame's one budget (RowsInView; what it leaves, the worker's first
	-- work). `animate`: the tab cross-fades (the page was on show already).
	function page:RevealAt(sec, y, instant, animate)
		if self.current ~= sec then
			self:Select(sec, animate)
		end
		self.pager:ScrollTo(math.max(0, self.headerHeight + y - 8), instant)
	end

	-- A picker page's picker line under the header's texts, the tab row
	-- (wrapped onto a second row where the tabs do not fit the section's
	-- width) and the sections under it, each by one TOPLEFT point.
	-- At Finish (`measured`: the tabs were just sized), and again after a
	-- font change: the 'fonts' topic marks the built pages (tabsStale), laid
	-- again on their next show or tab click, the page on show at once. The
	-- header's height is taken again from its flavour (it wraps deeper at a
	-- larger Font Style).
	function page:LayTabs(measured)
		self.tabsStale = nil
		if not measured and self.flavour then
			self.baseHeight = HeaderHeight(self)
		end
		local y = self.baseHeight
		local line = self.pickerLine
		if line and self.pickerY then
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", self, "TOPLEFT", PAD + HEADER_ICON + 14, -self.pickerY)
			line:SetPoint("RIGHT", self, "RIGHT", -PAD, 0)
		end
		local tabs = self.tabs
		if tabs then
			local x, rowY = 0, y
			local artHeight = 24
			for _, tab in ipairs(tabs) do
				if not measured then
					PanelTemplates_TabResize(tab, 8)
				end
				if tab.MiddleActive then
					artHeight = math.floor(tab.MiddleActive:GetHeight() + 0.5)
				end
				local w = tab:GetWidth()
				if x + w > self.width - PAD * 2 and x > 0 then
					x = 0
					rowY = rowY + artHeight + 2
				end
				tab:ClearAllPoints()
				tab:SetPoint("TOPLEFT", PAD + x, -rowY)
				x = x + w - 6
			end
			y = rowY + artHeight - 1
			if self.tabLine then
				self.tabLine:SetPoint("TOPLEFT", PAD, -y)
			end
			y = y + 12
		end
		self.headerHeight = y
		for _, sec in ipairs(self.sections) do
			sec:ClearAllPoints()
			sec:SetPoint("TOPLEFT", PAD, -y)
		end
		-- (a page whose own texts wrap: Home's What's new and Help)
		if not measured and self.relay then
			self:relay()
		end
	end

	-- Make the tab row (if more than one section), lay it and the sections
	-- out, and open the first tab.
	function page:Finish()
		self.baseHeight = self.headerHeight
		if #self.sections > 1 then
			self.tabs = {}
			for _, sec in ipairs(self.sections) do
				local tab = CreateFrame("Button", nil, self, "PanelTopTabButtonTemplate")
				tab:SetText(sec.name)
				PanelTemplates_TabResize(tab, 8)
				tab.section = sec
				-- (flat in both looks, 0.15.0; the selected one wears the
				-- kit's active look in the kit's: tab:SetSelected)
				W.FlatTab(tab, SKIN)
				Perf.SetScript(tab, "OnClick", TabClick)
				-- a tab holding an option new in the running update: its New
				-- tag on the tab's top edge (W.Badge)
				tab.newTag = sec.hasNew and W.Badge(tab, true) or nil
				self.tabs[#self.tabs + 1] = tab
			end
			-- (the flat tabs' line, in both looks)
			local line = Solid(self, "ARTWORK", C.accent2, 1)
			line:SetHeight(1)
			line:SetPoint("RIGHT", self, "RIGHT", -PAD, 0)
			self.tabLine = line
		end
		self:LayTabs(true)
		local most = 0   -- (the rows of its largest tab)
		for _, sec in ipairs(self.sections) do
			sec:SetWidth(self.width - PAD * 2)
			sec:Finish()
			if not sec.jobs then
				SectionPanel(sec)   -- (a tab with no rows to make)
			end
			local rows = sec.jobs and sec.plannedRows or sec.rows
			if rows > most then
				most = rows
			end
		end
		-- a page of many rows only fades in: a slide lays every one of them
		-- out again each frame (ALPHA_ONLY_ROWS, the safe fallback above)
		self.pager:AlphaOnly(self, ALPHA_ONLY_ROWS ~= nil and most > ALPHA_ONLY_ROWS)
		self:Select(self.sections[1])
	end
	return page
end

-- Page header: framed icon (58, the approved sketch), title in the title face,
-- the flavour line under it. `new`: the update a brand-new page came with (its
-- New tag after the title); `right`: the width kept free on the right (an
-- element page's switch and Reset this page, 200; a live preview's; Home's
-- Tutorial button). The header lies on the calm ground (0.15.0: the flat
-- mainWindow reads at 8:1, so no dark panel is laid under it any more).
local function BuildPageHeader(page, icon, title, flavour, new, right)
	local box = IconBox(page, HEADER_ICON, icon)
	box:SetPoint("TOPLEFT", PAD, -PAD)
	page.headerBox = box   -- (an important module's pulses while its page is open: SelectPage)

	local titleFS = Text(page, "GameFontNormalHuge", title, C.accent)
	titleFS:SetPoint("TOPLEFT", box, "TOPRIGHT", 14, 0)
	if KIT and KIT.TitleFont then
		KIT:TitleFont(titleFS, true)
	end
	page.titleText = titleFS
	-- a brand-new page's module (its registry `new`): its New tag after the title
	page.titleTag = new and W.NewTag(page, titleFS, new) or nil

	local flavourFS = Text(page, "GameFontHighlightSmall", nil, C.sub)
	flavourFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 2, -6)
	flavourFS:SetWidth(page.width - PAD * 2 - (HEADER_ICON + 14) - (right or 0))
	flavourFS:SetWordWrap(true)
	flavourFS:SetText(flavour)
	page.flavour = flavourFS
	page.headerHeight = HeaderHeight(page)
end

-- an option by its key, in a module's options
local function OptionOf(owner, key)
	for _, o in ipairs(owner.options) do
		if o.key == key then
			return o
		end
	end
	return nil
end

local EMPTY = {}

--------------------------------------------------------------------------------
-- The layout (0.15.0, the configurator rebuild; the user, 2026-09-27/28:
-- every option in exactly ONE place): Core/ConfigLayout.lua's data
-- (MelloUI.ConfigLayout, loaded after this file) resolved against the
-- modules' option schemas once, when first needed -- the window's first
-- open, a /mello word -- never at load or login. L.Define runs with R and
-- Link recorders; each id is matched to what it names ("Module.key" the
-- module's schema option, "Module.#Name" its button of that name,
-- "Module.!enabled" the module's own switch; headers, subheaders and
-- includes are the old pages' structure, never options), and each page is
-- laid out as its tabs, each of the fixed sections (L.SECTIONS) holding its
-- rows in their order, then its link rows. A line naming an unknown page,
-- tab, section, pick or option, a per-pick row whose keys differ in type, and
-- a link whose target is not placed are reported once through the error
-- handler and left out (the page still builds). A schema option no line
-- places (and not in L.unplaced) is laid at the end of its module's home
-- page, in Advanced, so a new option is never lost.
--   Lay.Get() -> the layout:
--     pages[key]   { key, def (L.pages'), tabs = { { name, index, new,
--                  sections = { { name, rows, links } } } }, picks = { { key,
--                  label, desc } } and pickLabel[key] on a picker page, new }
--     order        the page keys in the side list's order
--     place[id]    where a setting's row is: { r, picks (the picks it is
--                  live on, per-pick and `only` rows), pickSet }
--     switchOf[module name]   its switch: { r = its switch row } or
--                  { header = the page whose header has it }
--   A row r: page (key), tab, section, name, type ("toggle", "slider",
--   "dropdown", "button", "picture"), and b (its one binding) or keys
--   ([pick] = binding) with distinct (the bindings in pick order) and
--   picksOf ([binding] = its picks); only (a set) / onlyList, wide,
--   picture, swatch, free, gate (a binding), when ({ b, value, line }),
--   also, new (the update its newest setting came with, while it runs).
--   A link lk: page, tab, section, name, and target (a binding) or targets
--   ([pick] = binding).
--   A binding: { id, mod (the module whose setting it is), opt (its schema
--   option; none for a module switch), key, kind = "option" | "button" |
--   "module" }
--   Lay.Word(text) -> page key, tab name, pick   (/mello words, below)
--------------------------------------------------------------------------------

local Lay = {}
do
	local resolved = nil   -- Lay.Get's answer, made once
	local bindings = {}    -- [id] = its binding, or false: nothing by that id
	local words = nil      -- the /mello words (Lay.Word), made at the first

	local function IsOption(o)
		return type(o) == "table" and o.type ~= nil and o.type ~= "header" and o.type ~= "subheader"
			and o.type ~= "include" and not o.slot
	end

	-- what an id names (made once per id, the same table after)
	local function Bind(id)
		local b = bindings[id]
		if b ~= nil then
			return b or nil
		end
		b = false
		local name, rest = tostring(id):match("^([^.]+)%.(.+)$")
		local m = name and MelloUI.modules[name]
		if m and rest == "!enabled" then
			b = { id = id, mod = m, kind = "module" }
		elseif m and type(m.options) == "table" then
			local button = rest:sub(1, 1) == "#" and rest:sub(2) or nil
			for _, o in ipairs(m.options) do
				if IsOption(o) and ((button and o.type == "button" and o.key == nil and o.name == button)
					or (not button and o.key == rest)) then
					b = { id = id, mod = (o.module and MelloUI.modules[o.module]) or m, opt = o, key = o.key,
						kind = o.type == "button" and "button" or "option" }
					break
				end
			end
		end
		bindings[id] = b
		return b or nil
	end
	Lay.Bind = Bind

	local function KindOf(b, picture)
		if picture then
			return "picture"
		end
		return b.kind == "module" and "toggle" or b.opt.type
	end

	local function ByLabel(a, b)
		return a.label:lower() < b.label:lower()
	end

	-- the module a page stands for: its header switch's, else the one its
	-- icon names ("module:<Name>"); nil for none
	function Lay.ModuleOf(def)
		local name = def.module or (type(def.icon) == "string" and def.icon:match("^module:(.+)$"))
		return name and MelloUI.modules[name] or nil
	end

	-- the Windows page's picks: the registry's kit panels on its Windows tab,
	-- not the look switch of one of MelloUI's own windows (the Quest
	-- Tracker's), by label; a pick's key is the panel module's name
	local function WindowPicks()
		local out = {}
		for _, m in ipairs(MelloUI:ModulesInOrder()) do
			local w = m.window
			if type(w) == "table" and type(w.label) == "string" and w.tab == "Windows" and not w.switch then
				out[#out + 1] = { key = m.name, label = w.label, desc = w.desc }
			end
		end
		table.sort(out, ByLabel)
		return out
	end

	-- the update a setting came with while it runs (its New tag), else nil
	local function NewOf(b)
		local new = b.opt and b.opt.new
		if new ~= nil and MelloUI:IsNew(new) then
			return new
		end
		return nil
	end

	function Lay.Get()
		if resolved then
			return resolved
		end
		local out = { pages = {}, order = {}, place = {}, switchOf = {} }
		resolved = out
		local L = MelloUI.ConfigLayout
		if type(L) ~= "table" or type(L.pages) ~= "table" then
			-- (a file an update added, which this client loads only after a
			-- full restart: Home and Profiles until then, and the line once)
			MelloUI:Print("MelloUI was updated: restart the game once to finish (/reload does not load the new files).")
			return out
		end
		local problems = {}
		local function Problem(...)
			problems[#problems + 1] = string.format(...)
		end
		-- the pages, their tabs and each tab's sections
		for key, def in pairs(L.pages) do
			local p = { key = key, def = def, tabs = {}, tabOf = {} }
			for i, name in ipairs(def.tabs or EMPTY) do
				local t = { name = name, index = i, sections = {}, secOf = {} }
				for j, sname in ipairs(L.SECTIONS) do
					local s = { name = sname, rows = {}, links = {} }
					t.sections[j], t.secOf[sname] = s, s
				end
				p.tabs[i], p.tabOf[name] = t, t
			end
			local picker = def.picker
			if type(picker) == "table" then
				p.picks, p.pickLabel = {}, {}
				if picker.from == "windows" then
					p.picks = WindowPicks()
				else
					for i, pk in ipairs(picker.picks or EMPTY) do
						p.picks[i] = { key = pk[1], label = pk[2] }
					end
				end
				for _, pk in ipairs(p.picks) do
					p.pickLabel[pk.key] = pk.label
				end
			end
			if def.module then
				out.switchOf[def.module] = { header = key }
			end
			out.pages[key] = p
		end
		for _, g in ipairs(L.groups or EMPTY) do
			for _, key in ipairs(g.entries) do
				out.order[#out.order + 1] = key
			end
		end
		local place, switchOf = out.place, out.switchOf
		local function Place(id, r, picks)
			if not place[id] then
				local set = nil
				if picks then
					set = {}
					for _, k in ipairs(picks) do
						set[k] = true
					end
				end
				place[id] = { r = r, picks = picks, pickSet = set }
			end
		end
		local function AddRow(p, t, s, what, extra)
			local r = { page = p.key, tab = t, section = s }
			local first
			if type(what) == "string" then
				first = Bind(what)
				if not first then
					Problem("%s > %s: no option '%s'", p.key, t.name, what)
					return
				end
				r.b = first
			elseif not p.picks then
				Problem("%s > %s: a row per pick on a page with no picker", p.key, t.name)
				return
			else
				local map = what
				if what.from == "windows" then
					map = {}
					for _, pk in ipairs(p.picks) do
						map[pk.key] = "UIModifications." .. pk.key
					end
				end
				for k in pairs(map) do
					if k ~= "*" and not p.pickLabel[k] then
						Problem("%s > %s: no pick '%s'", p.key, t.name, tostring(k))
					end
				end
				r.keys, r.distinct, r.picksOf = {}, {}, {}
				for _, pk in ipairs(p.picks) do
					local id = map[pk.key] or map["*"]
					local b = id and Bind(id)
					if id and not b then
						Problem("%s > %s: no option '%s'", p.key, t.name, id)
					elseif b then
						r.keys[pk.key] = b
						local list = r.picksOf[b]
						if not list then
							list = {}
							r.picksOf[b] = list
							r.distinct[#r.distinct + 1] = b
						end
						list[#list + 1] = pk.key
					end
				end
				first = r.distinct[1]
				if not first then
					return
				end
			end
			r.type = KindOf(first, extra.picture)
			for _, b in ipairs(r.distinct or EMPTY) do
				if KindOf(b, extra.picture) ~= r.type then
					Problem("%s > %s: '%s' is a %s, '%s' a %s", p.key, t.name, first.id, r.type, b.id, KindOf(b))
					return nil
				end
			end
			r.name = extra.name or (first.kind == "module" and first.mod.title) or first.opt.name or first.id
			if extra.only then
				r.only, r.onlyList = {}, extra.only
				for _, k in ipairs(extra.only) do
					r.only[k] = true
				end
			end
			r.wide, r.picture, r.swatch, r.also = extra.wide, extra.picture, extra.swatch, extra.also
			r.free = (extra.free or (first.opt and first.opt.free)) and true or nil
			if extra.gate then
				r.gate = Bind(extra.gate)
				if not r.gate then
					Problem("%s > %s: no switch '%s'", p.key, t.name, extra.gate)
				end
			end
			local when = extra.when
			if when then
				local b = Bind(when.key)
				if b then
					r.when = { b = b, value = when.value, notValue = when.notValue, line = when.line }
				else
					Problem("%s > %s: no setting '%s'", p.key, t.name, tostring(when.key))
				end
			end
			for _, b in ipairs(r.distinct or { first }) do
				r.new = r.new or NewOf(b)
				Place(b.id, r, r.picksOf and r.picksOf[b] or r.onlyList)
				if b.kind == "module" then
					switchOf[b.mod.name] = { r = r }
				end
			end
			s.rows[#s.rows + 1] = r
			return r
		end
		local function Section(pageKey, tab, section)
			local p = out.pages[pageKey]
			local t = p and p.tabOf[tab]
			local s = t and t.secOf[section]
			if not s then
				Problem("no page / tab / section %s > %s > %s", tostring(pageKey), tostring(tab), tostring(section))
			end
			return p, t, s
		end
		local links = {}
		local function R(pageKey, tab, section, what, extra)
			local p, t, s = Section(pageKey, tab, section)
			if not s then
				return
			end
			extra = extra or EMPTY
			if type(what) == "table" and what.prefix then
				-- every button of that module, in its order
				local name = tostring(what.prefix):match("^([^.]+)%.#$")
				local m = name and MelloUI.modules[name]
				for _, o in ipairs(m and m.options or EMPTY) do
					if IsOption(o) and o.type == "button" and o.key == nil and type(o.name) == "string" then
						AddRow(p, t, s, name .. ".#" .. o.name, extra)
					end
				end
				return
			end
			AddRow(p, t, s, what, extra)
		end
		local function Link(pageKey, tab, section, target, label)
			local p, t, s = Section(pageKey, tab, section)
			if s then
				links[#links + 1] = { page = pageKey, p = p, tab = t, section = s, target = target, name = label }
			end
		end
		local ok, err = pcall(L.Define, R, Link)
		if not ok then
			Problem("its rows stopped: %s", tostring(err))
		end
		-- the links, now that every setting has its place
		for _, lk in ipairs(links) do
			local target = lk.target
			local good = true
			if type(target) == "table" then
				lk.targets = {}
				local map = target
				for _, pk in ipairs(lk.p.picks or EMPTY) do
					local id = map[pk.key] or map["*"]
					local b = id and Bind(id)
					if b and place[b.id] then
						lk.targets[pk.key] = b
					elseif id then
						good = false
						Problem("%s > %s: the link '%s' names '%s', which has no place", lk.page, lk.tab.name, lk.name, id)
					end
				end
				lk.target = nil
			else
				local b = Bind(target)
				if b and place[b.id] then
					lk.target = b
				else
					good = false
					Problem("%s > %s: the link '%s' names '%s', which has no place", lk.page, lk.tab.name, lk.name, tostring(target))
				end
			end
			lk.p = nil
			if good then
				lk.isLink = true
				local list = lk.section.links
				list[#list + 1] = lk
			end
		end
		-- a schema option no line places (and not left out on purpose): at the
		-- end of its module's home page, in Advanced
		local unplaced = L.unplaced or EMPTY
		for _, name in ipairs(MelloUI.moduleOrder) do
			local m = MelloUI.modules[name]
			for _, o in ipairs(type(m.options) == "table" and m.options or EMPTY) do
				if IsOption(o) then
					local id = o.key ~= nil and (name .. "." .. tostring(o.key)) or (name .. ".#" .. tostring(o.name))
					if not place[id] and not unplaced[id] then
						local key, tab = Lay.HomeOf(out, name)
						local p = key and out.pages[key]
						local t = p and (p.tabOf[tab] or p.tabs[1])
						local r = t and AddRow(p, t, t.secOf.Advanced, id, EMPTY)
						if r then
							r.fallback = true   -- (the checks look for these: every option has its R line)
						end
					end
				end
			end
		end
		-- the New tags: a tab holding a row new in the running update, a page
		-- with one or whose module is new itself (its header's, else the one
		-- its icon names: Reminders)
		for _, p in pairs(out.pages) do
			local m = Lay.ModuleOf(p.def)
			p.new = m ~= nil and MelloUI:IsNew(m.new) or nil
			for _, t in ipairs(p.tabs) do
				for _, s in ipairs(t.sections) do
					for _, r in ipairs(s.rows) do
						if r.new then
							t.new, p.new = true, true
						end
					end
					if not t.firstSection and (#s.rows > 0 or #s.links > 0) then
						t.firstSection = s
					end
				end
			end
		end
		if #problems > 0 then
			geterrorhandler()("MelloUI: the Configurator's layout (Core/ConfigLayout.lua): " .. table.concat(problems, "; "))
		end
		return out
	end

	-- A module's home page: the page holding most of its rows (a panel's
	-- Painted Skin and a feature's switch count as its own), and the tab of its
	-- first row there; a window panel's is the Windows page on its pick
	local counts = nil   -- [module name] = { [page key] = rows }, first[name][page] = its first row
	local function Count(lay)
		if counts then
			return counts
		end
		counts = { n = {}, first = {} }
		local function Add(name, r)
			local n = counts.n[name]
			if not n then
				n = {}
				counts.n[name], counts.first[name] = n, {}
			end
			n[r.page] = (n[r.page] or 0) + 1
			counts.first[name][r.page] = counts.first[name][r.page] or r
		end
		for _, key in ipairs(lay.order) do
			local p = lay.pages[key]
			for _, t in ipairs(p and p.tabs or EMPTY) do
				for _, s in ipairs(t.sections) do
					for _, r in ipairs(s.rows) do
						for _, b in ipairs(r.distinct or { r.b }) do
							Add(b.mod.name, r)
							local key2 = b.mod.name == "UIModifications" and type(b.key) == "string" and b.key
							local driven = key2 and (key2:match("^qol_(.+)$") or key2)
							if driven and MelloUI.modules[driven] then
								Add(driven, r)
							end
						end
					end
				end
			end
		end
		return counts
	end

	function Lay.HomeOf(lay, name)
		local m = MelloUI.modules[name]
		local w = m and m.window
		if type(w) == "table" and w.tab == "Windows" and not w.switch and lay.pages.Windows then
			return "Windows", nil, name
		end
		local c = Count(lay)
		local n = c.n[name]
		if not n then
			return nil
		end
		local best, most = nil, 0
		for _, key in ipairs(lay.order) do
			if (n[key] or 0) > most then
				best, most = key, n[key]
			end
		end
		if not best then
			return nil
		end
		local r = c.first[name][best]
		return best, r.tab.name, nil
	end

	-- a page word: lower case, spaces out ("screen text" -> "screentext");
	-- and with only its letters and digits ("bars & meters" -> "barsmeters")
	local function Norm(s)
		return (tostring(s or ""):lower():gsub("%s+", ""))
	end
	local function Alnum(s)
		return (tostring(s or ""):lower():gsub("[^%w]", ""))
	end
	Lay.Norm = Norm

	local function Words()
		if words then
			return words
		end
		local lay = Lay.Get()
		words = { pages = {}, extra = {}, modules = {} }
		for key, p in pairs(lay.pages) do
			words.pages[Norm(key)] = key
			words.pages[Norm(p.def.title)] = key
			words.pages[Alnum(p.def.title)] = key
		end
		local L = MelloUI.ConfigLayout
		for w, t in pairs(L and L.words or EMPTY) do
			words.extra[Norm(w)] = t
		end
		for _, name in ipairs(MelloUI.moduleOrder) do
			local key, tab, pick = Lay.HomeOf(lay, name)
			if key then
				local t = { key, tab, pick = pick }
				words.modules[Norm(name)] = t
				local title = Norm(MelloUI.modules[name].title)
				words.modules[title] = words.modules[title] or t
			end
		end
		return words
	end

	-- /mello <words> (7.2): the whole text, lower case, spaces out -- a page's
	-- key or title, home, then the layout's own words, then a module's name or
	-- title through its home page (a window panel's pick). Nil: no page.
	function Lay.Word(text)
		local w = Norm(text)
		if w == "" then
			return nil
		end
		local all = Words()
		local key = all.pages[w] or all.pages[Alnum(text)]
		if key then
			return key
		end
		if w == "home" then
			return "Home"
		end
		local t = all.extra[w] or all.modules[w]
		if t and t[1] and resolved.pages[t[1]] then
			return t[1], t[2], t.pick
		end
		return nil
	end
end

-- A page's title, icon and flavour: its layout entry's, else those of the
-- module it names (its registry `icon` and `flavour`: "module:<Name>", or
-- the page's own module)
local function PageTitle(key)
	local L = MelloUI.ConfigLayout
	local def = L and L.pages and L.pages[key]
	return def and def.title or key
end
local function PageMeta(key)
	if key == "Home" then
		return LOGO, HOME_FLAVOUR
	elseif key == "Profiles" then
		return PROFILES_META.icon, PROFILES_META.flavour
	end
	local L = MelloUI.ConfigLayout
	local def = L and L.pages and L.pages[key]
	if not def then
		return DEFAULT_ICON, ""
	end
	local icon, flavour = def.icon, def.flavour
	local named = type(icon) == "string" and icon:match("^module:(.+)$")
	local m = (named and MelloUI.modules[named]) or nil
	local own = def.module and MelloUI.modules[def.module]
	if named or not icon then
		icon = m and (Meta(m)) or DEFAULT_ICON
	end
	if not flavour then
		local from = own or m
		flavour = from and select(2, Meta(from)) or ""
	end
	return icon, flavour
end

--------------------------------------------------------------------------------
-- Element pages (0.15.0, the rebuild; SPEC sections 1.2, 5): a page of the
-- layout -- its header (the page's switch on a page one module owns, Reset
-- this page; on a picker page the picker, Copy from and, on Unit Frames, the
-- live preview), its tabs, and on each tab the sections in their fixed
-- order, each a heading (W.Header) over its rows and then its link rows.
-- Every row is made from a job, a few a frame (MakeRows), in both looks.
--   A row's setting on a picker page is the CURRENT pick's (`page.pick`,
--   kept for the session per page): a row per pick reads and writes the
--   pick's key, takes that key's range, values and pictures, and is dimmed
--   ("Not for Pet") on a pick that has none; a row one key serves on several
--   picks says "shared" (its tooltip names them); a row that is one key for
--   every pick shows its `wide` hint. Apply to all ("All", left of a row per
--   pick with several keys) shows while those keys differ.
--   A row sleeps (W.Gate: dimmed, its hint slot saying what wakes it, a
--   click on it jumping there) on the first of: 1 the pick, 2 UI
--   Modifications off (a row it drives, unless `free`), 3 its module's own
--   switch off (a feature with a switch of its own), 4 its area off (a folded
--   feature's qol_ switch; a kit panel's Painted Skin -- on the Windows page
--   the CURRENT pick's, so a window wearing another panel's keys stays live
--   on its own switch -- and the reskin), 5 its schema's parent / requires,
--   6 the layout's extra gate / when.
--   Every bulk write (Copy from, All, Reset this page) is one MelloUI:Batch;
--   the painted skins' and features' switches in it go through UI
--   Modifications' SetAreas, which refuses a painted skin in combat: then
--   nothing is written and one line says why. Copy from and Reset this page
--   ask first (the user, 2026-09-29: MelloUI:Confirm, Modules/KitWindow.lua),
--   naming the picks and how many settings change; nothing is asked when
--   nothing would change (the line says so at once), and the answer writes
--   the picks the question named, whatever is picked by then.
--   The page on show is refreshed once a frame however many settings change
--   (the bus's 'setting' and 'module' mark it stale and ask the kit's next
--   frame; a hidden page is refreshed on its next show).
--------------------------------------------------------------------------------

-- (what the rest of the file uses of the block)
local BuildElementPage, JumpTo, ShowPage, RevealRow, AskPageRefresh, RelistPages, EntryLive
local pickOf = {}   -- [page key] = its pick, kept for the session (both looks' pages share it)
do
local ROW_H = { toggle = ROW_HEIGHT, slider = SLIDER_ROW_HEIGHT, dropdown = ROW_HEIGHT, button = ROW_HEIGHT,
	picture = ROW_HEIGHT }
-- where a typed row's control starts, from the row's right edge (W.ClipRow's
-- span: the texts end 10 px left of it)
local SPAN = { toggle = 12 + 26, slider = 14 + 256, dropdown = 14 + 200, picture = 14 + 200 }
local SECTION_GAP = 8       -- between a tab's sections
local ALL_W, ALL_GAP = 44, 8   -- Apply to all's button, and its room left of the control
local SWATCH_SPEC = { width = 50, height = 14 }
local SWATCH_GAP = 8
local PICKER_W, COPY_W, PICKER_LINE = 180, 150, 26
local RESET_W = 120
local PREVIEW_W, PREVIEW_H = 220, 96   -- the live preview (Core/ConfigPreview.lua)
local SWITCH_ROOM = 200     -- the header's right for a page's switch and Reset this page

-- the texts (in-game words: no tool or other addon named)
local TEXT = {
	enabled = "Enabled",
	reset = "Reset this page",
	resetTip = "Every setting on this page back to its default: every tab, and on a page with a picker the one picked "
		.. "(and what every pick shares). Switches of whole modules and what belongs to your character stay as they are. "
		.. "It asks first.",
	resetDone = "%s: %s reset to default.",
	resetNone = "%s: every setting on this page is at its default already.",
	resetAsk = "Reset every setting on the %s page to its default? It changes %s.",
	resetAskPick = "Reset every setting on the %s page for %s to its default? It changes %s.",
	resetShared = "%s (%d shared with other %ss)",
	resetAccept = "Reset",
	copy = "Copy from…",
	copyTip = "Every setting this page keeps per %s, copied from the %s you choose to the one shown. What they share is one setting already. It asks first.",
	copied = "%s: %s copied from %s to %s.",
	copiedNone = "%s: %s has the settings of %s already.",
	copyAsk = "Copy the %s settings to %s? It changes %s.",
	copyAccept = "Copy",
	cancel = "Cancel",
	all = "All",
	allTip = "Set this for every %s that has it: %s.",
	allDone = "%s: %s set for every %s.",
	shared = "shared",
	sharedTip = "One setting for %s%s.",
	also = " (%s too)",
	notFor = "Not for %s",
	switchOn = "Switch on \"%s\" first.",
	switchOnAt = "Switch on \"%s\" first (%s).",
	tabWhere = "%s tab",
	uim = "UI Modifications",
	pickTip = "The %s this page's settings are for. Rows it has no setting for are dimmed.",
	nothing = "Nothing to set here yet.",
}
local AREAS_REFUSED = "Not in combat: this would switch painted skins."   -- (UI Modifications' own line, areasRefused)

local function Settings(n)
	return n == 1 and "1 setting" or string.format("%d settings", n)
end

-- "A", "A and B", "A, B and C"
local function Join(list)
	local n = #list
	if n <= 1 then
		return list[1] or ""
	end
	return table.concat(list, ", ", 1, n - 1) .. " and " .. list[n]
end

local function LabelsOf(p, picks)
	local out = {}
	for i, k in ipairs(picks) do
		out[i] = p.pickLabel[k] or k
	end
	return out
end

-- a module driven by UI Modifications: UI Modifications itself, a kit
-- panel (its registry `window`, not the look switch of an own window) or a
-- folded feature (its `tweak`)
local drivenOf = {}
local function Driven(m)
	local d = drivenOf[m]
	if d == nil then
		local w = m.window
		d = m.name == "UIModifications" or (type(w) == "table" and not w.switch) or type(m.tweak) == "table"
		drivenOf[m] = d
	end
	return d
end

-- a setting as it is now: read as stored (the module's defaults not laid on
-- again for every read: GetModuleDB walks them all), its default when unset
local function Setting(m, key)
	local all = MelloUI.db and MelloUI.db.modules
	local db = all and all[m.name]
	local v = db and db[key]
	if v == nil then
		v = m.defaults[key]
	end
	return v
end

-- a binding's value: a module's switch, a setting read another way
-- (`opt.get`: the Kit Colours the kit draws), or the setting
local function ValueOf(b)
	if not b then
		return nil
	end
	if b.kind == "module" then
		return MelloUI:IsModuleEnabled(b.mod.name)
	end
	local opt = b.opt
	if opt.get then
		return opt.get(MelloUI:GetModuleDB(b.mod.name))
	end
	return Setting(b.mod, b.key)
end

local function Write(b, value)
	if b.kind == "module" then
		MelloUI:SetModuleEnabled(b.mod.name, value)
		MelloUI:RefreshConfig()
		return
	end
	MelloUI:NotifySettingChanged(b.mod.name, b.key, value)
end

-- the setting a row reaches on the page's pick (or on `pick`: a question's,
-- asked on another): the pick's key (nil: none for it), its one key (nil
-- while the pick is not one of `only`)
local function Current(page, r, pick)
	pick = pick or page.pick
	local keys = r.keys
	if keys then
		return keys[pick]
	end
	if r.only and pick and not r.only[pick] then
		return nil
	end
	return r.b
end
-- the setting whose schema a row's controls are made from: the pick's, else
-- its first
local function Shape(page, r)
	return Current(page, r) or r.b or r.distinct[1]
end

-- a row that has a setting on this pick
function EntryLive(page, r, pick)
	if r.keys then
		return r.keys[pick] ~= nil
	end
	return not (r.only and pick and not r.only[pick])
end

-- The choices of a picture row's setting: a border kind's (Kit.borderKinds,
-- by key) or the section of its module's PickerGroups with that key (a panel
-- that is off still answers: its groups are static tables); kept on the
-- binding
local function Choices(b)
	if b.choices == nil then
		b.choices = false
		local K = MelloUI.Kit
		if b.mod.name == "UIModifications" and K and type(K.borderKinds) == "table" then
			for _, k in ipairs(K.borderKinds) do
				if k.key == b.key then
					b.choices, b.pictureKind = k.values, k.preview or "rim"
				end
			end
		end
		if not b.choices and type(b.mod.PickerGroups) == "function" then
			local ok, groups = pcall(b.mod.PickerGroups, b.mod)
			for _, g in ipairs(ok and type(groups) == "table" and groups or EMPTY) do
				for _, s in ipairs(g.sections or EMPTY) do
					if s.key == b.key then
						b.choices, b.pictureKind = s.choices, s.kind
					end
				end
			end
		end
	end
	return b.choices or EMPTY, b.pictureKind
end

-- a value as another key of the same row takes it: a switch's as it is, a
-- slider's kept in its range and on its step, a dropdown's or a picture's
-- only when that key offers it (nil: not taken)
local function Fit(b, v)
	if v == nil or b.kind ~= "option" then
		return nil
	end
	local opt = b.opt
	local t = opt.type
	if t == "toggle" then
		return v and true or false
	elseif t == "slider" then
		if type(v) ~= "number" then
			return nil
		end
		v = W.Round(v, opt.step)
		return math.max(opt.min or v, math.min(opt.max or v, v))
	end
	local values = t == "dropdown" and opt.values or (Choices(b))
	for _, entry in ipairs(type(values) == "table" and values or EMPTY) do
		if entry.value == v then
			return v
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The gates (5.3): the first that fails, as W.Gate wants it -- live, why,
-- line -- and where a click on the sleeping row jumps (an id, or
-- "!page:<key>" for a page's header switch, with the pick it needs)
--------------------------------------------------------------------------------

local lines = {}   -- [why][where or ""] = the line (made once each)
local function SwitchLine(why, where)
	local byWhere = lines[why]
	if not byWhere then
		byWhere = {}
		lines[why] = byWhere
	end
	local w = where or ""
	local line = byWhere[w]
	if not line then
		line = where and string.format(TEXT.switchOnAt, why, where) or string.format(TEXT.switchOn, why)
		byWhere[w] = line
	end
	return line
end
local notFor = {}   -- [pick label] = "Not for <pick>"
local function NotFor(label)
	local line = notFor[label]
	if not line then
		line = string.format(TEXT.notFor, label)
		notFor[label] = line
	end
	return line
end

-- where a place is seen from this page: nil here (its tab), else the other
-- page's title with the pick it is on when it is not on every pick there
-- ("Action Bars > Bag Bar": a row per pick is named by its shared label),
-- the pick it needs here (its label, and its key for the jump), or the
-- other tab it is on ("Minimap tab")
local farWhere, tabWhere = {}, {}   -- [place] / [tab name] = the text (made once each)
local function WhereOf(page, place, row)
	local r = place.r
	local pick = place.pickSet and place.picks[1]
	if r.page ~= page.name then
		local where = farWhere[place]
		if not where then
			local other = pick and Lay.Get().pages[r.page]
			local label = other and other.picks and #place.picks < #other.picks and other.pickLabel[pick]
			where = label and (PageTitle(r.page) .. " > " .. label) or PageTitle(r.page)
			farWhere[place] = where
		end
		return where, nil
	end
	if pick and page.pick and not place.pickSet[page.pick] then
		return page.lay.pickLabel[pick] or pick, pick
	end
	if r.tab ~= row.tab then
		local name = r.tab.name
		local where = tabWhere[name]
		if not where then
			where = string.format(TEXT.tabWhere, name)
			tabWhere[name] = where
		end
		return where, nil
	end
	return nil, nil
end

-- a switch that is off, by its id: its row's label where it is placed
local function Off(page, row, id, fallback)
	local place = Lay.Get().place[id]
	if not place then
		return false, fallback, SwitchLine(fallback), nil
	end
	local why = place.r.name
	local where, pick = WhereOf(page, place, row)
	return false, why, SwitchLine(why, where), id, pick
end

-- the module whose own look switch a UI Modifications setting is (its
-- registry `window.switch`: the Quest Tracker's questTrackerKit), else nil
local lookOwner = nil   -- [UI Modifications key] = that module (made once)
local function LookOwner(b)
	if b.mod.name ~= "UIModifications" or b.key == nil then
		return nil
	end
	if not lookOwner then
		lookOwner = {}
		for _, m in ipairs(MelloUI:ModulesInOrder()) do
			local w = m.window
			if type(w) == "table" and type(w.switch) == "string" then
				lookOwner[w.switch] = m
			end
		end
	end
	return lookOwner[b.key]
end

local function Gate(page, r)
	-- 1: the pick
	local b = Current(page, r)
	if not b then
		local label = page.lay.pickLabel[page.pick] or tostring(page.pick)
		return false, nil, NotFor(label)
	end
	local m = b.mod
	local driven = Driven(m)
	-- 2: UI Modifications (its switch is the Look page's header's)
	if driven and not r.free and not MelloUI:IsModuleEnabled("UIModifications") then
		return false, TEXT.uim, SwitchLine(TEXT.uim, PageTitle("Look")), "!page:Look"
	end
	-- 3: the module's own switch (a feature with one); a look switch UI
	-- Modifications keeps for one module (the Quest Tracker's Painted Skin)
	-- on that module's, as the module's other rows
	local own = (not driven and b.kind ~= "module" and m) or LookOwner(b)
	if own and not MelloUI:IsModuleEnabled(own.name) then
		local sw = Lay.Get().switchOf[own.name]
		if sw and sw.r then
			return Off(page, r, sw.r.b.id, own.title)
		end
		local at = sw and sw.header
		return false, own.title, SwitchLine(own.title, at and at ~= page.name and PageTitle(at) or nil), at and ("!page:" .. at)
	end
	-- 4: its area: a kit panel's Painted Skin (the Windows page: the pick's)
	-- and the reskin; a folded feature's switch
	local w, tweak = m.window, m.tweak
	if type(w) == "table" and not w.switch then
		local um = MelloUI.modules.UIModifications
		local panel = page.fromWindows and page.pick or m.name
		if um and Setting(um, "reskin") == false then
			return Off(page, r, "UIModifications.reskin", "Painted kit reskin")
		elseif um and Setting(um, panel) == false then
			return Off(page, r, "UIModifications." .. panel, panel)
		end
	elseif type(tweak) == "table" and not tweak.always then
		local um = MelloUI.modules.UIModifications
		local v = um and Setting(um, "qol_" .. m.name)
		if (tweak.off and v ~= true) or (not tweak.off and v == false) then
			return Off(page, r, "UIModifications.qol_" .. m.name, tweak.label or m.title)
		end
	end
	-- 5: the schema's own parent / requires (the same module's switches)
	local opt = b.opt
	if opt then
		local key = opt.parent
		for i = 1, 2 do
			if key and not Setting(m, key) then
				local o = OptionOf(m, key)
				return Off(page, r, m.name .. "." .. key, o and o.name or key)
			end
			key = i == 1 and opt.requires or nil
		end
	end
	-- 6: the layout's own: a switch elsewhere, another setting's value
	if r.gate and not ValueOf(r.gate) then
		return Off(page, r, r.gate.id, r.gate.opt and r.gate.opt.name or r.gate.id)
	end
	local when = r.when
	if when then
		local v = ValueOf(when.b)
		if (when.notValue ~= nil and v == when.notValue) or (when.notValue == nil and v ~= when.value) then
			return false, nil, when.line
		end
	end
	-- 7: (0.17.0) a setting this client may lack (Combat Text's over-enemy
	-- switches, the engine's own CVars): its schema's `missing` says why
	if opt and type(opt.missing) == "function" then
		local ok, line = pcall(opt.missing)
		if ok and type(line) == "string" then
			return false, nil, line
		end
	end
	return true
end

-- a click on a sleeping row: to the switch that wakes it (W.Gate's onCover)
local function CoverJump(row)
	local e = row.melloEntry
	if not e then
		return
	end
	local _, _, _, id, pick = Gate(e.page, e.r)
	if id then
		MelloUI:PlayUISound("page")
		JumpTo(id, pick)
	end
end

--------------------------------------------------------------------------------
-- A row's hint and tooltip for its pick
--------------------------------------------------------------------------------

-- the hint: a row one key for every pick its `wide` text, a row one key serves
-- on several picks "shared", else the schema's (the important switch's
-- IMPORTANT)
local function Hint(page, r, b)
	if r.wide then
		return r.wide
	end
	local picks = (r.keys and b and r.picksOf[b]) or (not r.keys and r.onlyList)
	if picks and #picks >= 2 then
		return TEXT.shared
	end
	local opt = (b or Shape(page, r)).opt
	if opt then
		return opt.important and "IMPORTANT" or opt.hint
	end
	return nil
end

-- the tooltip's body: the setting's description, and for a shared one the
-- picks it is one setting for (made once per row and setting)
local function Tip(page, r, b)
	local tips = r.tips
	if not tips then
		tips = {}
		r.tips = tips
	end
	local tip = tips[b]
	if tip then
		return tip
	end
	tip = (b.kind == "module" and b.mod.desc) or (b.opt and b.opt.desc) or ""
	local picks = (r.keys and r.picksOf[b]) or (not r.keys and r.onlyList)
	if picks and #picks >= 2 then
		local also = r.also and r.also[b.id]
		local line = string.format(TEXT.sharedTip, Join(LabelsOf(page.lay, picks)), also and string.format(TEXT.also, also) or "")
		tip = tip ~= "" and (tip .. "\n\n" .. line) or line
	end
	tips[b] = tip
	return tip
end

-- a sub-option's depth under its parents (the schema's `parent`, a switch of
-- the same module): one indent per level
local function Depth(m, opt)
	local depth, seen = 0, {}
	local p = opt and opt.parent and OptionOf(m, opt.parent)
	while p and not seen[p] and depth < 4 do
		seen[p] = true
		depth = depth + 1
		p = p.parent and OptionOf(m, p.parent)
	end
	return depth
end

-- the gate's cover of a row (W.Gate's, found once: its hint follows the pick)
local function CoverAmong(row, ...)
	for i = 1, select("#", ...) do
		local kid = select(i, ...)
		if kid.gateRow == row then
			return kid
		end
	end
	return nil
end
local function CoverOf(row)
	return CoverAmong(row, row:GetChildren())
end

-- the keys of a row per pick hold different values (Apply to all is offered)
local function Differ(r)
	local d = r.distinct
	local first = ValueOf(d[1])
	for i = 2, #d do
		if ValueOf(d[i]) ~= first then
			return true
		end
	end
	return false
end

local function RefreshEntry(e)
	e.row:Refresh()
	local all = e.all
	if all then
		-- (none on a pick with no setting: the row sleeps "Not for <pick>";
		-- its room is kept all the same)
		all:SetShown(Current(e.page, e.r) ~= nil and Differ(e.r))
	end
end

-- A row per pick takes the pick's setting: its range, values or pictures,
-- its tooltip and hint (nothing made again)
local function Rebind(e)
	local page, r = e.page, e.r
	if e.link then
		local lk = e.link
		if lk.targets then
			local b = lk.targets[page.pick]
			e.row:SetTarget(b and PageTitle(Lay.Get().place[b.id].r.page) or nil, nil)
		end
		return
	end
	if not r.keys then
		return
	end
	local b = Current(page, r)
	local shape = b or r.distinct[1]
	local control = e.control
	if shape ~= e.shape then
		e.shape = shape
		local opt = shape.opt
		if r.type == "slider" and opt then
			control:SetRange(opt.min, opt.max, opt.step, opt.percent and true or false, opt.format or false)
		elseif r.type == "dropdown" and opt then
			control:SetValues(opt.values)
		elseif r.type == "picture" then
			control:SetChoices(Choices(shape))
		end
		local tip = Tip(page, r, shape)
		e.row.tipBody, control.tipBody = tip, tip
	end
	if e.cover then
		e.cover.hintText = Hint(page, r, b)
	end
end

--------------------------------------------------------------------------------
-- The bulk writes (5.2): ONE MelloUI:Batch (the bus's 'setting' held to its
-- end, one backup); the painted skins' and features' switches of UI
-- Modifications through its SetAreas (a few a frame; refused in combat when a
-- painted skin would switch: then nothing at all is written and one line
-- says why). `writes`: a list of { binding, value }, in order.
--------------------------------------------------------------------------------

-- [UI Modifications key] = "skin" (a painted skin's switch: a panel's, the
-- Quest Tracker's own look) or "feature" (a folded feature's qol_ switch);
-- IsArea(key) -> that, or nil
local areaKeys = nil
local function IsArea(key)
	if not areaKeys then
		areaKeys = {}
		for _, m in ipairs(MelloUI:ModulesInOrder()) do
			local w, t = m.window, m.tweak
			if type(w) == "table" and w.label then
				areaKeys[w.switch or m.name] = "skin"
			end
			if type(t) == "table" and not t.always then
				areaKeys["qol_" .. m.name] = "feature"
			end
		end
	end
	return areaKeys[key]
end

-- the one line a refused bulk write prints (UI Modifications' own)
local function SayRefused()
	local um = MelloUI.modules.UIModifications
	MelloUI:Print((um and um.areasRefused) or AREAS_REFUSED)
end

local writeList, areaValues = {}, {}
local function WriteAll()
	for i = 1, #writeList, 2 do
		local b = writeList[i]
		if not (b.mod.name == "UIModifications" and IsArea(b.key)) then
			Write(b, writeList[i + 1])
		end
	end
end
local function Bulk()
	for k in pairs(areaValues) do
		areaValues[k] = nil
	end
	local areas, reskin = false, false
	for i = 1, #writeList, 2 do
		local b = writeList[i]
		if b.mod.name == "UIModifications" and IsArea(b.key) then
			areaValues[b.key] = writeList[i + 1] and true or false
			areas = true
		elseif b.mod.name == "UIModifications" and b.key == "reskin" then
			reskin = (Setting(b.mod, "reskin") ~= false) ~= (writeList[i + 1] and true or false)
		end
	end
	local um = MelloUI.modules.UIModifications
	-- (the painted reskin itself switched: every painted skin at once, in
	-- one frame -- refused in combat as SetAreas refuses one skin: D16)
	if reskin and InCombatLockdown() then
		SayRefused()
		return false
	end
	local refused = false
	MelloUI:Batch(function()
		if areas and um and um.SetAreas then
			if not um:SetAreas(areaValues) then
				refused = true
				return
			end
		end
		WriteAll()
	end)
	if refused then
		SayRefused()
		return false
	end
	return true
end
-- Bulk's refusal known before a question is asked: in a fight, a painted
-- skin's switch or the painted reskin itself among the writes (the pending
-- writes change each, so SetAreas would refuse them): the line at once, and
-- no question the answer could only refuse. The answer still goes through
-- Bulk (a fight that starts while it asks)
local function FightRefuses()
	if not InCombatLockdown() then
		return false
	end
	for i = 1, #writeList, 2 do
		local b = writeList[i]
		if b.mod.name == "UIModifications" and (IsArea(b.key) == "skin" or b.key == "reskin") then
			SayRefused()
			return true
		end
	end
	return false
end
local function Want(b, v)
	writeList[#writeList + 1] = b
	writeList[#writeList + 1] = v
end
local function Clear()
	for i = #writeList, 1, -1 do
		writeList[i] = nil
	end
end

-- every row of a page (every tab), with the setting it reaches on the pick
local function EachRow(page, fn, arg)
	for _, t in ipairs(page.lay.tabs) do
		for _, s in ipairs(t.sections) do
			for _, r in ipairs(s.rows) do
				fn(page, r, arg)
			end
		end
	end
end

local function DefaultOf(b)
	local v = b.mod.defaults[b.key]
	if type(v) == "table" then
		-- a copy: the live table must not BE the defaults table
		local copy = {}
		for k, x in pairs(v) do
			copy[k] = x
		end
		v = copy
	end
	return v
end

-- Reset this page: every setting of the page's rows on the pick (a row one
-- key for every pick too) back to its default. Left alone: a module's own
-- switch (its `!enabled` row, and a folded feature's `qol_` switch, which
-- is that feature's module switch: D7), and what belongs to the player
-- (MelloUI:IsPersonalKey), Dark Mode's settings too on every page its rows
-- sit on (the player's own preference: no profile carries them either).
-- `pick`: the pick the question named (nil: the page's own)
local resetShared = 0   -- of a reset's writes, the ones other picks share (ResetWants)
local function ResetRow(page, r, pick)
	local b = Current(page, r, pick)
	if not (b and b.kind == "option" and b.opt.type ~= "button" and b.mod.defaults[b.key] ~= nil) then
		return
	end
	if MelloUI:IsPersonalKey(b.mod.name, b.key) or (b.mod.name == "UIModifications" and IsArea(b.key) == "feature") then
		return
	end
	local v = DefaultOf(b)
	if type(v) == "table" or Setting(b.mod, b.key) ~= v then
		Want(b, v)
		-- (one setting for other picks too, as the row's "shared" hint says,
		-- or for the whole page: the question counts it)
		local picks = (r.keys and r.picksOf[b]) or (not r.keys and r.onlyList)
		if pick and not (picks and #picks < 2) then
			resetShared = resetShared + 1
		end
	end
end
-- the writes a reset of the page on `pick` would make (writeList), counted;
-- and how many of them other picks share
local function ResetWants(page, pick)
	Clear()
	resetShared = 0
	EachRow(page, ResetRow, pick)
	return #writeList / 2, resetShared
end
local function ResetPage(page, pick)
	local n = ResetWants(page, pick)
	local title = page.lay.def.title
	if n == 0 then
		MelloUI:Print(TEXT.resetNone, title)
	elseif Bulk() then
		MelloUI:Print(TEXT.resetDone, title, Settings(n))
	end
	Clear()
	MelloUI:RefreshConfig()
end
-- Reset this page asks first (MelloUI's one dialog), naming the page (the
-- dialog stays while the side list moves on) and on a picker page the pick
-- shown now, reset on the answer, and how many of the writes other picks
-- share; nothing to reset, or a fight that would refuse it: the line at
-- once, no question
local function AskResetPage(page)
	local pick = page.pick
	local n, shared = ResetWants(page, pick)
	local refused = n > 0 and FightRefuses()
	Clear()
	local lay = page.lay
	if n == 0 then
		MelloUI:Print(TEXT.resetNone, lay.def.title)
		return
	elseif refused then
		return
	end
	local label = pick and lay.pickLabel and lay.pickLabel[pick]
	local count = Settings(n)
	if label and shared > 0 then
		count = string.format(TEXT.resetShared, count, shared, lay.def.picker.noun or "pick")
	end
	local text = label and string.format(TEXT.resetAskPick, lay.def.title, label, count)
		or string.format(TEXT.resetAsk, lay.def.title, count)
	MelloUI:Confirm({
		text = text,
		accept = TEXT.resetAccept,
		cancel = TEXT.cancel,
		onAccept = function()
			ResetPage(page, pick)
		end,
	})
end

-- Copy from: every row per pick whose keys differ between the two picks
-- takes the source pick's value (fitted to the key); shared and page-wide
-- rows are one setting already. `pair`: { source, target }
local function CopyRow(_, r, pair)
	local keys = r.keys
	local from, to = keys and keys[pair[1]], keys and keys[pair[2]]
	if from and to and from ~= to then
		local v = Fit(to, ValueOf(from))
		if v ~= nil and v ~= ValueOf(to) then
			Want(to, v)
		end
	end
end
-- the writes a copy from `source` to `target` would make (writeList),
-- counted; nil when the two are not two picks of the page
local function CopyWants(page, source, target)
	local lay = page.lay
	if not (lay.pickLabel[source] and lay.pickLabel[target] and source ~= target) then
		return nil
	end
	Clear()
	EachRow(page, CopyRow, { source, target })
	return #writeList / 2
end
local function CopyFrom(page, source, target)
	local n = CopyWants(page, source, target)
	if not n then
		return
	end
	local lay = page.lay
	local title, from, to = lay.def.title, lay.pickLabel[source], lay.pickLabel[target]
	if n == 0 then
		MelloUI:Print(TEXT.copiedNone, title, to, from)
	elseif Bulk() then
		MelloUI:Print(TEXT.copied, title, Settings(n), from, to)
	end
	Clear()
	MelloUI:RefreshConfig()
end
-- a pick as the owner of the settings in Copy from's question: the
-- picker's noun after its name unless the name ends in a picker's noun
-- already ("the Target frame's", "the Social window's", "the Bag Bar's"),
-- and a plural's possessive "'" ("the Raid Frames'", "the Loot windows'")
local nouns = nil   -- [noun] = true: every picker's (made at the first question)
local function Owner(label, noun)
	if not nouns then
		nouns = {}
		local L = MelloUI.ConfigLayout
		for _, def in pairs(type(L) == "table" and L.pages or EMPTY) do
			if type(def.picker) == "table" and def.picker.noun then
				nouns[def.picker.noun] = true
			end
		end
	end
	local last = (label:match("(%a+)$") or ""):lower()
	if noun and not (nouns[last] or nouns[last:match("^(.-)s$") or ""]) then
		label = label .. " " .. noun
	end
	return label:find("s$") and (label .. "'") or (label .. "'s")
end

-- Copy from asks first (MelloUI's one dialog), naming both picks: the pick
-- shown now takes the source's settings on the answer, even if another is
-- picked by then; nothing to copy, or a fight that would refuse it: the
-- line at once, no question
local function AskCopyFrom(page, source)
	local target = page.pick
	local n = CopyWants(page, source, target)
	local refused = n and n > 0 and FightRefuses()
	Clear()
	if not n then
		return
	end
	local lay = page.lay
	local from, to = lay.pickLabel[source], lay.pickLabel[target]
	if n == 0 then
		MelloUI:Print(TEXT.copiedNone, lay.def.title, to, from)
		return
	elseif refused then
		return
	end
	MelloUI:Confirm({
		text = string.format(TEXT.copyAsk, Owner(from, lay.def.picker.noun), to, Settings(n)),
		accept = TEXT.copyAccept,
		cancel = TEXT.cancel,
		onAccept = function()
			CopyFrom(page, source, target)
		end,
	})
end

-- Apply to all: the pick's value into every other key of the row
local function ApplyToAll(page, r)
	local cur = Current(page, r)
	if not cur then
		return
	end
	local v = ValueOf(cur)
	Clear()
	for _, b in ipairs(r.distinct) do
		if b ~= cur then
			local fit = Fit(b, v)
			if fit ~= nil and fit ~= ValueOf(b) then
				Want(b, fit)
			end
		end
	end
	if #writeList > 0 and Bulk() then
		MelloUI:Print(TEXT.allDone, page.lay.def.title, r.name, page.lay.def.picker.noun or "one")
	end
	Clear()
	page:Refresh()
end

-- The shared handlers of the page's own controls (reading what they need
-- from the control they run on)
local ResetPageClick = Shared("OnClick on the configurator's Reset this page", function(self)
	MelloUI:PlayUISound("tab")
	AskResetPage(self.melloPage)
end, "script")
local AllClick = Shared("OnClick on the configurator's Apply to all", function(self)
	local e = self.melloEntry
	MelloUI:PlayUISound("tab")
	ApplyToAll(e.page, e.r)
end, "script")
local TipEnter = Shared("OnEnter on the configurator's page controls", function(self)
	W.ShowTooltip(self, self.melloTipTitle or "", self.melloTipBody)
end, "script")
local function PageTip(control, title, body)
	control.melloTipTitle, control.melloTipBody = title, body
	Perf.HookScript(control, "OnEnter", TipEnter)
	Perf.HookScript(control, "OnLeave", W.TipLeave)
end
local function NoValue()
	return nil
end

--------------------------------------------------------------------------------
-- The rows (a job each)
--------------------------------------------------------------------------------

-- the picks a row per pick has a key for, in their order
local function PicksWithKeys(lay, r)
	local out = {}
	for _, pk in ipairs(lay.picks) do
		if r.keys[pk.key] then
			out[#out + 1] = pk.key
		end
	end
	return out
end

local SLIDER_KEYS = { "min", "max", "step", "percent", "format" }

local function MakeRow(sec, r)
	local page = sec.page
	local b = Current(page, r)
	local shape = b or r.b or r.distinct[1]
	local opt = shape.opt
	local e = { page = page, r = r, shape = shape }
	local o = RowOpts(sec, r.new)
	if opt and opt.important then
		o.labelKey, o.hintKey = C.accent, C.accent
	end
	o.indent = Depth(shape.mod, opt) * INDENT
	o.gate = function()
		return Gate(page, r)
	end
	o.onCover = CoverJump
	local get = function()
		return ValueOf(Current(page, r))
	end
	local set = function(value)
		local now = Current(page, r)
		if now then
			Write(now, value)
		end
	end
	local hint, desc = Hint(page, r, b), Tip(page, r, shape)
	local t = r.type
	local row, control
	if t == "toggle" then
		row, control = W.ToggleRow(sec, sec.y, r.name, hint, desc, get, set, o)
	elseif t == "slider" then
		for _, k in ipairs(SLIDER_KEYS) do
			o[k] = opt[k]
		end
		row, control = W.SliderRow(sec, sec.y, r.name, hint, desc, get, set, o)
		for _, k in ipairs(SLIDER_KEYS) do
			o[k] = nil
		end
	elseif t == "dropdown" then
		row, control = W.DropdownRow(sec, sec.y, r.name, hint, desc, get, set, opt.values, o)
		if opt.relist then
			page.relist[#page.relist + 1] = control
		end
	elseif t == "picture" then
		local choices, kind = Choices(shape)
		o.host = window
		row, control = W.PictureRow(sec, sec.y, r.name, hint, desc, get, set, choices, kind, o)
		o.host = nil
	else
		o.width = opt.width
		row, control = W.ButtonRow(sec, sec.y, r.name, hint, desc, opt.text or "Run", RowButtonClick, o)
		o.width = nil
		control.melloOpt, control.melloModule = opt, shape.mod
	end
	o.gate, o.onCover, o.indent = nil, nil, 0
	e.row, e.control = row, control
	row.melloEntry = e
	local span = SPAN[t] or (12 + (opt and opt.width or 70))
	if r.keys then
		e.cover = CoverOf(row)
		-- Apply to all (a row with several keys): its room always kept, so the
		-- label never moves when it shows
		if #r.distinct >= 2 then
			local all = W.Button(row, TEXT.all, ALL_W, SKIN, { onClick = AllClick })
			all:SetPoint("RIGHT", control, "LEFT", -ALL_GAP, 0)
			all.melloEntry = e
			if not r.allTip then
				local noun = page.lay.def.picker.noun or "one"
				r.allTip = string.format(TEXT.allTip, noun, Join(LabelsOf(page.lay, PicksWithKeys(page.lay, r))))
			end
			PageTip(all, TEXT.all, r.allTip)
			W.RowPlateChild(row, all)
			W.ClipRow(row, all, span + ALL_W + ALL_GAP)
			all:Hide()
			e.all = all
		end
	end
	if r.swatch == "palette" then
		local swatch = W.PaletteSwatch(row, SWATCH_SPEC)
		swatch:SetPoint("RIGHT", control, "LEFT", -SWATCH_GAP, 0)
		W.ClipRow(row, swatch, span + SWATCH_SPEC.width + SWATCH_GAP)
	end
	sec.refreshers[#sec.refreshers + 1] = function()
		RefreshEntry(e)
	end
	page.entries[#page.entries + 1] = e
	page.built[r] = e
	Placed(sec, row, ROW_H[t] or ROW_HEIGHT)
end

-- a link's value as text: a switch On / Off (W.LinkRow's), a choice by its
-- label, a slider's number as its box shows it
local function Shown(b, v)
	local opt = b.opt
	if not opt or v == nil or type(v) == "boolean" then
		return v
	end
	if opt.type == "slider" then
		if opt.format then
			local ok, text = pcall(opt.format, v)
			return ok and text or v
		elseif opt.percent then
			return string.format("%d%%", math.floor(v * 100 + 0.5))
		end
		return v
	end
	local values = opt.type == "dropdown" and opt.values or (Choices(b))
	for _, entry in ipairs(type(values) == "table" and values or EMPTY) do
		if entry.value == v then
			return entry.label or tostring(v)
		end
	end
	return v
end
local function LinkTarget(page, lk)
	if lk.targets then
		return lk.targets[page.pick]
	end
	return lk.target
end
local function LinkValue(e)
	local b = LinkTarget(e.page, e.link)
	if not b then
		return ""
	end
	local v = ValueOf(b)
	if v ~= e.lastValue or b ~= e.lastTarget then
		e.lastValue, e.lastTarget, e.lastText = v, b, Shown(b, v)
	end
	return e.lastText
end
local function LinkGate(page, lk)
	if lk.targets and not lk.targets[page.pick] then
		return false, nil, NotFor(page.lay.pickLabel[page.pick] or tostring(page.pick))
	end
	return true
end
local LinkClick = Shared("OnClick on the configurator's link rows (to the setting's page)", function(row)
	local e = row.melloEntry
	local b = e and LinkTarget(e.page, e.link)
	if b then
		MelloUI:PlayUISound("page")
		JumpTo(b.id)
	end
end)

local function MakeLink(sec, lk)
	local page = sec.page
	local e = { page = page, link = lk }
	local b = LinkTarget(page, lk) or (lk.targets and select(2, next(lk.targets)))
	local o = RowOpts(sec)
	o.target = b and PageTitle(Lay.Get().place[b.id].r.page) or ""
	o.desc = b and ((b.opt and b.opt.desc) or b.mod.desc) or nil
	if lk.targets then
		o.gate = function()
			return LinkGate(page, lk)
		end
	end
	local row = W.LinkRow(sec, sec.y, lk.name, function()
		return LinkValue(e)
	end, LinkClick, o)
	o.target, o.desc, o.gate = nil, nil, nil
	e.row = row
	row.melloEntry = e
	sec.refreshers[#sec.refreshers + 1] = function()
		e.row:Refresh()
	end
	page.entries[#page.entries + 1] = e
	Placed(sec, row, ROW_HEIGHT)
end

-- a section's heading (8 px under the section before it)
local function MakeHeading(sec, s)
	local gap = s.gap
	W.Header(sec, sec.y + gap, s.name, { inset = SEC_INSET })
	Placed(sec, nil, gap + W.HEADER_HEIGHT)
end

-- a job of a tab's section: a heading, a row or a link
local function ElementJob(sec, job)
	if job.isLink then
		MakeLink(sec, job)
	elseif job.rows then
		MakeHeading(sec, job)
	else
		MakeRow(sec, job)
	end
end

--------------------------------------------------------------------------------
-- The header's own controls
--------------------------------------------------------------------------------

-- the picks as a dropdown's values, and the other picks as Copy from's (made
-- once per page and pick, kept on the layout: both looks share them)
local function PickValues(lay)
	if not lay.pickValues then
		lay.pickValues = {}
		for i, pk in ipairs(lay.picks) do
			lay.pickValues[i] = { value = pk.key, label = pk.label }
		end
	end
	return lay.pickValues
end
local function CopyValues(lay, pick)
	lay.copyValues = lay.copyValues or {}
	local list = lay.copyValues[pick]
	if not list then
		list = {}
		for _, pk in ipairs(lay.picks) do
			if pk.key ~= pick then
				list[#list + 1] = { value = pk.key, label = pk.label }
			end
		end
		lay.copyValues[pick] = list
	end
	return list
end

-- A pick chosen: every row made takes its setting (no row is made again),
-- the page and the preview follow; an open picture flyout closes
local function SetPick(page, pick)
	local lay = page.lay
	if not (lay.pickLabel and lay.pickLabel[pick]) or pick == page.pick then
		return
	end
	page.pick = pick
	pickOf[page.name] = pick
	if window then
		W.ClosePictureMenu(window)
	end
	for _, e in ipairs(page.entries) do
		Rebind(e)
	end
	if page.copyBox then
		page.copyBox:SetValues(CopyValues(lay, pick))
	end
	if page.preview and page.preview.SetPick then
		pcall(page.preview.SetPick, page.preview, pick)
	end
	page:Refresh()
end

local function Header(page, pl)
	local def = pl.def
	local module = def.module and MelloUI.modules[def.module]
	local P = def.preview and pl.picks and MelloUI.ConfigPreview
	local preview = type(P) == "table" and type(P.Make) == "function"
	local icon, flavour = PageMeta(page.name)
	local right = module and SWITCH_ROOM or (preview and PREVIEW_W + 10) or RESET_W + 10
	page.previewH = preview and PREVIEW_H or nil
	page.pickerLineH = pl.picks and PICKER_LINE or nil
	local own = Lay.ModuleOf(def)
	BuildPageHeader(page, icon, def.title, flavour, own and own.new, right)
	page.important = module and module.important and true or false
	local reset = W.Button(page, TEXT.reset, RESET_W, SKIN, { onClick = ResetPageClick })
	reset.melloPage = page
	PageTip(reset, TEXT.reset, TEXT.resetTip)
	page.resetButton = reset
	if module then
		-- the page's switch: its module's (Look's is UI Modifications', labelled
		-- so, its tooltip saying all it takes with it)
		local name = def.switchLabel or TEXT.enabled
		local lbl = Text(page, "GameFontNormal", name, C.text)
		local switch = W.Switch(page, function()
			return MelloUI:IsModuleEnabled(module.name)
		end, function(value)
			MelloUI:SetModuleEnabled(module.name, value)
			MelloUI:RefreshConfig()
		end, SwitchOpts())
		switch:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -PAD)
		lbl:SetPoint("RIGHT", switch, "LEFT", -4, 0)
		PageTip(switch, name, def.switchDesc or module.desc)
		page.switch, page.switchLabel = switch, lbl
		page.refreshers[#page.refreshers + 1] = function()
			switch:Refresh()
		end
		reset:SetPoint("TOPRIGHT", switch, "BOTTOMRIGHT", 0, -10)
	elseif not preview then
		reset:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -PAD)
	end
	if pl.picks then
		-- the picker line: the pick, Copy from (placed by LayTabs, under the
		-- header's texts)
		local noun = def.picker.noun or "one"
		local line = CreateFrame("Frame", nil, page)
		line:SetHeight(PICKER_LINE)
		local lbl = Text(line, "GameFontNormal", (def.picker.label or "") .. ":", C.text)
		lbl:SetPoint("LEFT", line, "LEFT", 0, 0)
		local dd = W.Dropdown(line, PICKER_W, function()
			return page.pick
		end, function(value)
			MelloUI:PlayUISound("tab")
			SetPick(page, value)
		end, PickValues(pl), { default = def.picker.label, tooltip = string.format(TEXT.pickTip, noun) })
		dd:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
		local copy = W.Dropdown(line, COPY_W, NoValue, function(value)
			AskCopyFrom(page, value)
			page.copyBox:Refresh()
		end, CopyValues(pl, page.pick), { default = TEXT.copy, tooltip = string.format(TEXT.copyTip, noun, noun) })
		copy:SetPoint("LEFT", dd, "RIGHT", 12, 0)
		page.pickerLine, page.picker, page.copyBox = line, dd, copy
		page.refreshers[#page.refreshers + 1] = function()
			dd:Refresh()
		end
		if preview then
			-- (the preview takes the header's right: Reset this page at the
			-- picker line's right end)
			reset:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, -2)
		end
	end
	if preview then
		-- the live preview (Core/ConfigPreview.lua): made with the page, never
		-- at login; it follows the settings itself
		local ok, made = pcall(P.Make, page, def.preview, SKIN)
		if ok and type(made) == "table" then
			made:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -PAD)
			if made.SetPick then
				pcall(made.SetPick, made, page.pick)
			end
			page.preview = made
		elseif not ok then
			geterrorhandler()(made)
		end
	end
	page.headerHeight = HeaderHeight(page)
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function BuildElementPage(key, width)
	local pl = Lay.Get().pages[key]
	if not pl or pl.def.own then
		return nil
	end
	local page = NewPage(key, width)
	page.lay = pl
	page.entries, page.built, page.rowSec, page.rowY, page.relist = {}, {}, {}, {}, {}
	page.fromWindows = pl.def.picker and pl.def.picker.from == "windows" or nil
	if pl.picks then
		local pick = pickOf[key]
		page.pick = (pick and pl.pickLabel[pick]) and pick or (pl.picks[1] and pl.picks[1].key)
		pickOf[key] = page.pick
		page.SetPick = SetPick
	end
	Header(page, pl)
	-- the header's controls dressed now (the dropdowns); the tabs dress
	-- themselves and every row is dressed as it is made
	W.Dress(page, SKIN)
	for _, t in ipairs(pl.tabs) do
		local sec = NewSection(page, t.name)
		sec.hasNew = t.new
		for _, s in ipairs(t.sections) do
			if #s.rows > 0 or #s.links > 0 then
				s.gap = s == t.firstSection and 0 or SECTION_GAP
				Queue(sec, s, ElementJob, s.gap + W.HEADER_HEIGHT)
				for _, r in ipairs(s.rows) do
					page.rowSec[r], page.rowY[r] = sec, sec.plannedY or sec.y
					Queue(sec, r, ElementJob, ROW_H[r.type] or ROW_HEIGHT)
				end
				for _, lk in ipairs(s.links) do
					Queue(sec, lk, ElementJob, ROW_HEIGHT)
				end
			end
		end
		if not sec.jobs then
			-- (a tab with nothing on it: its line, as a module with no options had)
			local fs = Text(sec, "GameFontDisable", TEXT.nothing)
			fs:SetPoint("TOPLEFT", 14, -(SEC_INSET + 8))
			sec.y = SEC_INSET + 30
		end
	end
	if #page.sections == 0 then
		local sec = NewSection(page, pl.def.title)
		local fs = Text(sec, "GameFontDisable", TEXT.nothing)
		fs:SetPoint("TOPLEFT", 14, -(SEC_INSET + 8))
		sec.y = SEC_INSET + 30
	end
	page:Finish()
	return page
end

-- The page named, on show: the page on show already (true), or put on show
-- (made on its first open) as its side-list entry does
function ShowPage(name)
	local page = pages[name]
	if page and window.pager:Current() == page then
		return page, true
	end
	SelectPage(name)
	return pages[name], false
end

-- A row brought into view: its tab opened, the page scrolled so the row sits
-- under the top of the view (a glide on a page already on show, else at
-- once: the page's own fade is the motion), the row made when the page has
-- not made it yet (that one row, out of the pages' turn), and lit
function RevealRow(page, r, onShow)
	local sec, y = page.rowSec and page.rowSec[r], page.rowY and page.rowY[r]
	if not sec then
		return
	end
	page:RevealAt(sec, y, not onShow, onShow)
	if sec.jobs and not page.built[r] then
		MakeRows(sec, y + 1, nil, y)
	end
	local e = page.built[r]
	W.Flash(e and e.row)
end

-- A jump to a setting's one place (a link row's button, a sleeping row's
-- cover, Home's Change…, a search result): its page, the pick it needs
-- (`pick`, else the one shown when it has it there, else its first), its tab,
-- the row lit. "!page:<key>": that page's header switch.
function JumpTo(id, pick)
	if type(id) ~= "string" or not window then
		return
	end
	local header = id:match("^!page:(.+)$")
	if header then
		local page, onShow = ShowPage(header)
		if page then
			page.pager:ScrollTo(0, not onShow)
			W.Flash(page.switch)
		end
		NavFollow(true)
		return
	end
	local place = Lay.Get().place[id]
	if not place then
		return
	end
	local page, onShow = ShowPage(place.r.page)
	if not page then
		return
	end
	if page.SetPick then
		local want = pick or (place.pickSet and not place.pickSet[page.pick] and place.picks[1]) or nil
		if want then
			page:SetPick(want)
		end
	end
	RevealRow(page, place.r, onShow)
	NavFollow(true)
end

-- The page on show brought in line once a frame however many settings
-- changed in it (a slider dragged through 30 steps, a Batch of 40 keys);
-- every built page is stale until its next refresh (a hidden one: its next
-- show's). Nothing runs while nothing changes.
local asked = false
local PageRefresh = Shared("the configurator's page refresh (once a frame)", function()
	asked = false
	local page = window and currentPage and pages[currentPage]
	if page and page.stale and window:IsShown() and window.pager:Current() == page then
		page:Refresh()
	end
end)
function AskPageRefresh()
	for _, set in pairs(pagesBy) do
		for _, page in pairs(set) do
			page.stale = true
		end
	end
	if asked or not (window and window:IsShown()) then
		return
	end
	local K = MelloUI.Kit
	if K and K.NextFrame then
		asked = true
		K:NextFrame("Config page refresh", PageRefresh)
	else
		PageRefresh()
	end
end

-- 'palette': the lists made again that a palette renames in place (the Kit
-- Colours: the row's `relist`), on every built page
function RelistPages()
	for _, set in pairs(pagesBy) do
		for _, page in pairs(set) do
			for _, dd in ipairs(page.relist or EMPTY) do
				dd:Refresh(true)
			end
		end
	end
end
end   -- (the element pages block)

--------------------------------------------------------------------------------
-- Home page (the approved sketch of 2026-09-24): the header with the whole
-- logo and the Tutorial button; one section in two columns -- What's new on
-- the left (this version's changes, the older ones behind Earlier versions),
-- Your setup on the right (the profile, the palette, Kit Colours, the
-- screen, MelloUI's state, the installer) -- and Help under both, full
-- width. The palette and the Kit Colours show as values with Change…, a jump
-- to their one place on the Look page (0.15.0: every option in one place).
-- The header and both cards are made in the click frame; Help is one job
-- for the worker from the next frame on, its height planned so the page does
-- not jump.
--------------------------------------------------------------------------------

-- (what the rest of the file uses of it; the block keeps its helpers to
-- itself: the file is near Lua's limit of 200 locals in one function)
local BuildHomePage, ConfirmLoadProfile, FillProfileNames, InstallClick, HomeNew, HomeSearch, HomePart
do
local HOME_GAP = 10       -- between the two cards, and above Help
local CARD_PAD = 12       -- a card's texts inside its box
local CARD_ROW = 30       -- a Your setup row
local SETUP_VALUE = 100   -- where a Your setup row's value starts
local CHANGE_W = 70       -- Your setup's Change… (its text and the plate's sides)
local CARD_HEAD = SEC_INSET + ROW_HEIGHT - 6 + 8   -- a card's texts start under its heading
local TUTORIAL_W = 110
local HELP_NOTE_H = 28    -- Help's note, planned (two lines) until it is made
-- Earlier versions: true (the safe path) makes the older versions through
-- the worker, a version a job within its 2.5 ms a frame, the button saying
-- "Loading…" until the page's height is laid once after the last; false
-- makes them all in the click frame (the first choice once an in-game
-- measure shows that frame keeps within 5 ms)
local EARLIER_BY_WORKER = true

-- the texts Home's controls say (in-game words: no tool or other addon named)
local HOME_TIPS = {
	tutorial = "A short tour of this window: where every feature lives, step by step, on the game's help tips. Also /mello tutorial.",
	profile = "Choose a profile to load it: every setting of every module. It asks first. The Profiles page saves, shares and deletes them.",
	palette = "The colours of MelloUI's own windows and, with the painted kit reskin, of all its art. Chosen on the Look page: Change… takes you there.",
	change = "The colours of the painted art: frames, headers, rows, buttons, slots and bars. Chosen on the Look page: Change… takes you there.",
	fit = "Mello's Edit Mode layout was fitted to another screen size or UI scale, or by an older MelloUI. The installer fits it to this one, and you can go back right after.",
	install = "The installer: a setup for the whole interface in a few steps, fitted to this screen. Closes this window while it runs.",
	revert = "Back to how MelloUI was before the installer ran (the 'Before install' profile): your settings, and Edit Mode's layouts if the installer changed them. Asks first.",
}
local HELP_NOTE = "The game keeps your settings. Macro Backup on the Profiles page can also keep a copy in account macros, brought back only when you ask; /mello status shows both. The voice pack, MelloUI_VoicePack, replaces the old pack: a separate download in two parts from the 0.15.0 release (the Voice pack link above). Unzip both into the AddOns folder, where they make one MelloUI_VoicePack folder."

-- This frame's rows counted as spent: a page's first open whose own parts
-- are this frame's work (Home's header and cards), so the worker starts on
-- its jobs the next frame, never in the click frame
local function RowsDoneThisFrame()
	W.RowBudget.Spent(BUILD_BUDGET)
end

-- Your setup's voice pack row: MelloUI_VoicePack, else an old pack it
-- replaces (still played while it is the only one), else none
local function VoicePackText()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		for i, name in ipairs({ "MelloUI_VoicePack", "MelloUI_VoiceOverData", "AI_VoiceOverData_Forever", "AI_VoiceOverData_Vanilla" }) do
			local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
			if ok and loaded then
				return i == 1 and "installed" or "old pack: the new one is under Help"
			end
		end
	end
	return "not installed (the link is under Help)"
end

-- how many of the modules with a page of their own are on
local function ModulesOn()
	local on, total = 0, 0
	for name, module in MelloUI:IterateModules() do
		if not module.hidden then
			total = total + 1
			if MelloUI:IsModuleEnabled(name) then
				on = on + 1
			end
		end
	end
	return on, total
end

-- the Kit Colours look in use, by its label (the Look page's choice)
local function KitColoursLabel()
	local K = MelloUI.Kit
	if not (K and K.BorderValue and type(K.colourLooks) == "table") then
		return "-"
	end
	local value = K:BorderValue("colours")
	-- (the choice the kit draws: a Bronze kept from Ember is, under another
	-- palette, that palette's own kit)
	local look = K.ColourLookShown and K:ColourLookShown()
	if not look then
		for _, l in ipairs(K.colourLooks) do
			if l.value == value then
				look = l
				break
			end
		end
	end
	return look and (look.label or tostring(look.value)) or tostring(value)
end

-- "3440 × 1440 (21:9)": Core's one formatter (MelloUI:ScreenText, shared
-- with the installer; made again only when the size changes), "-" while the
-- client does not say
local function ScreenText()
	return (MelloUI:ScreenText()) or "-"
end

-- Fit to this screen is offered when Mello's layout went in fitted to a size
-- (UI units, UIModifications.layoutFitFor, written by the installer) the
-- screen no longer has: another resolution or UI scale; or fitted by an
-- older model (layoutFitRev short of LayoutFit.FIT_REV: 0.14.0's shorter
-- Services row)
local function FitDue()
	local db = MelloUI:GetModuleDB("UIModifications")
	local fitFor = db and db.layoutFitFor
	if type(fitFor) ~= "string" then
		return false
	end
	local rev = MelloUI.LayoutFit and MelloUI.LayoutFit.FIT_REV
	if rev and db.layoutFitRev ~= rev then
		return true
	end
	local ok, w, h = pcall(UIParent.GetSize, UIParent)
	w, h = ok and Num(w) or nil, ok and Num(h) or nil
	if not (w and h) then
		return false
	end
	return string.format("%.1fx%.1f", w, h) ~= fitFor
end

-- the installer's restore point ('Before install') and the answer it is
-- still owed, if any
local function InstallerState()
	local db = MelloUI.db
	local rp = db and db.installer
	if type(rp) ~= "table" or type(rp.before) ~= "table" then
		return nil, nil
	end
	return rp, type(rp.pending) == "table" and rp.pending or nil
end

-- Loading a profile by a click asks first (user, 2026-09-25): ONE confirmation
-- for Home's Profile dropdown and the Profiles page's Load button, in
-- MelloUI's own dialog (MelloUI:Confirm, Modules/KitWindow.lua; the game's
-- popups run the game's popup and gamepad code in MelloUI's execution, the
-- Gamepad UI freeze of 0.15.0). Accepted, it does what Load always did. The
-- typed /mello profile load stays without a question.
local function LoadAccepted(name)
	if MelloUI:LoadProfile(name) then
		MelloUI:Print("Profile '%s' loaded.", name)
	end
	MelloUI:RefreshConfig()
end
function ConfirmLoadProfile(name)
	if type(name) ~= "string" or name == "" then
		return
	end
	MelloUI:Confirm({
		text = ("Load the profile '%s'? Your current settings are replaced; save them as a profile first to keep them."):format(name),
		accept = "Load",
		cancel = "Cancel",
		onAccept = function()
			LoadAccepted(name)
		end,
	})
end

-- Your setup's Revert: back to the installer's restore point. An answer the
-- installer is still owed (its countdown, or an install it could not finish)
-- is the installer's own: its window opens on the Keep page. Otherwise the
-- revert runs AS an owed answer, so the installer's own guard covers it:
-- should nothing put the settings back, the answer stays owed and failed
-- (Keep and a new Install refused, Revert only), and a half state never
-- becomes the next install's restore point. A refusal before anything was
-- touched (combat, Edit Mode open) leaves no answer owed.
local function OpenInstallerFor(from)
	if MelloUI.OpenInstaller then
		MelloUI:OpenInstaller(from)
	end
end
local function RevertAccepted()
	local I = MelloUI.Installer
	local rp, pending = InstallerState()
	if not (rp and type(I) == "table" and type(I.Revert) == "function") then
		return
	end
	if pending then
		OpenInstallerFor("revert")
		return
	end
	-- (whether the game has read the installed start-up values since, as the
	-- engine keeps it: a /reload or a restart after the install, so a revert
	-- that changes them owes a reload; an install and revert in one session
	-- owe none)
	local reloadedSince = (rp.reloadedSince or not I.BeforeSession or I:BeforeSession(rp)) and true or false
	local owed = { option = rp.option, needsReload = false, reloadedSince = reloadedSince }
	rp.pending = owed
	local ok, reverted, why, reloadOwed = pcall(I.Revert, I, "button")
	if ok and reverted then
		if reloadOwed then
			-- (the installer window's own line; its Reload button is not on
			-- this path, so the line says it)
			local IW = MelloUI.InstallerWindow
			local line = IW and IW.TEXT and IW.TEXT.revertedReload
			MelloUI:Print((type(line) == "string" and line or "Reload to finish: the names above characters still use the installed font.") .. " (/reload)")
		end
		MelloUI:RefreshConfig()
		return
	end
	local failed = I.TEXT and I.TEXT.revertFailed
	if ok and why ~= failed and not owed.failed then
		-- refused before anything was put back (in a fight: this button's
		-- own line, not the countdown's pause)
		if rp.pending == owed then
			rp.pending = nil
		end
		if I.TEXT and why == I.TEXT.pausedCombat then
			why = I.TEXT.revertCombat or why
		end
		if type(why) == "string" then
			MelloUI:Print(why)
		end
		MelloUI:RefreshConfig()
		return
	end
	if not ok then
		geterrorhandler()(reverted)
	end
	owed.failed, owed.revertFailed = true, true
	MelloUI:RefreshConfig()
	OpenInstallerFor("revert")
end
local function ConfirmRevert()
	local rp, pending = InstallerState()
	if not rp then
		return
	end
	if pending then
		OpenInstallerFor("revert")
		return
	end
	MelloUI:Confirm({
		text = "Go back to how MelloUI was before the installer ran ('Before install')? Your settings return to what they were then, and Edit Mode's layouts too if the installer changed them.",
		accept = "Go back",
		cancel = "Cancel",
		onAccept = RevertAccepted,
	})
end

-- the profiles' names, sorted, into `out` (emptied first)
function FillProfileNames(out)
	for i = #out, 1, -1 do
		out[i] = nil
	end
	for name in pairs(MelloUI:Profiles()) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

-- The handlers Home shares: one function each, reading what they need from
-- the control they run on (`melloTipTitle`, `melloTipBody`, `melloPage`)
local HomeTipEnter = Shared("OnEnter on the configurator's Home controls", function(self)
	W.ShowTooltip(self, self.melloTipTitle or "", self.melloTipBody)
end, "script")
local function HomeTip(control, title, body)
	control.melloTipTitle, control.melloTipBody = title, body
	Perf.HookScript(control, "OnEnter", HomeTipEnter)
	Perf.HookScript(control, "OnLeave", W.TipLeave)
end
local TutorialClick = Shared("OnClick on the configurator's Tutorial", function()
	MelloUI:PlayUISound("page")
	if MelloUI.Tutorial then
		MelloUI.Tutorial:Start()
	end
end, "script")
-- Your setup's Change… by the palette and the Kit Colours: to their one
-- place, Look > General (the row lit; 0.15.0, the button's `melloJump`)
local ChangeClick = Shared("OnClick on the configurator's Change…", function(self)
	MelloUI:PlayUISound("page")
	JumpTo(self.melloJump)
end, "script")
-- Install... and Install again: the installer (Core/InstallerWindow.lua),
-- which closes this window
InstallClick = Shared("OnClick on the configurator's Install", function()
	OpenInstallerFor("configurator")
end, "script")
-- Fit to this screen: the installer, whose Screen step fits Mello's layout
-- to this screen through its engine (the store's places too), with its keep
-- or go back
local FitClick = Shared("OnClick on the configurator's Fit to this screen", function()
	OpenInstallerFor("fit")
end, "script")
local RevertClick = Shared("OnClick on the configurator's Revert", function()
	ConfirmRevert()
end, "script")
local function ProfileGet()
	return MelloUI.db and MelloUI.db.activeProfile or nil
end
local function ProfileSet(name)
	ConfirmLoadProfile(name)
end
local PROFILE_DD = { default = "None loaded", tooltip = HOME_TIPS.profile }
-- Home's own options (Your setup's controls), each with the update it came
-- with in `new`: the side list's Home entry is tagged New while one of them
-- is new (HomeNew; a new control of Home's goes in this list)
local HOME_OPTIONS = { PROFILE_DD }
function HomeNew()
	for _, o in ipairs(HOME_OPTIONS) do
		if o.new ~= nil and MelloUI:IsNew(o.new) then
			return true
		end
	end
	return false
end
-- What's new's first line while New tags show: the tag itself, and where to
-- look for it (in-game words)
local NEW_LINE = "Look for this tag on the side list, the tabs and the options: it marks everything this update added."

-- a Home card: the widgets' content panel (W.Panel, 0.15.0: a flat inner
-- panel in a 1 px edge on the calm ground, in both looks)
local function HomeCard(sec, width)
	local card = W.Panel(sec)
	card:SetWidth(width)
	card.w = width
	return card
end

-- a card's heading: the section heading of the own windows (W.Header: the
-- title in gold and a hairline, in both looks)
local CARD_HEADER = { inset = SEC_INSET, x = 2 }
local function CardHeading(card, text)
	local head = W.Header(card, SEC_INSET, text, CARD_HEADER)
	card.heading = head
	return head
end

-- one version's changes in the What's new card from `y` down, at the card's
-- own width: its number, then a line per change; the y under it. Each text
-- is kept in order in `card.items` (a line with its dot, `melloDot`; the
-- New tags' line with its tag, `melloTag`), so a font change can place them
-- again (NewsLay). `card.lead`: a first line after the tag (W.Tag), the
-- running update's while its options show New tags (taken once).
local function AddVersion(card, entry, y)
	local lead = card.lead
	card.lead = nil
	local items = card.items
	local head = Text(card, "GameFontNormal", "Version " .. entry.version, C.accent)
	head:SetPoint("TOPLEFT", CARD_PAD, -y)
	items[#items + 1] = head
	y = y + 22
	if lead then
		local tag = W.Tag(card, W.NEW)
		tag:SetPoint("TOPLEFT", CARD_PAD + W.TAG_PAD, -(y + 1))
		local indent = (Num(tag:GetStringWidth()) or 24) + W.TAG_PAD * 2 + 8
		local fs = Text(card, "GameFontHighlight", lead, C.text)
		fs:SetPoint("TOPLEFT", CARD_PAD + indent, -y)
		fs:SetWidth(card.w - CARD_PAD * 2 - indent)
		fs:SetWordWrap(true)
		fs.melloTag, fs.melloIndent = tag, indent
		items[#items + 1] = fs
		y = y + WrappedHeight(fs, 14) + 6
	end
	local textWidth = card.w - CARD_PAD * 2 - 16
	for _, line in ipairs(entry.lines) do
		local dot = Solid(card, "ARTWORK", C.accent2, 1)
		dot:SetSize(5, 5)
		dot:SetPoint("TOPLEFT", CARD_PAD + 4, -(y + 5))
		local fs = Text(card, "GameFontHighlight", line, C.text)
		fs:SetPoint("TOPLEFT", CARD_PAD + 16, -y)
		fs:SetWidth(textWidth)
		fs:SetWordWrap(true)
		fs.melloDot = dot
		items[#items + 1] = fs
		y = y + WrappedHeight(fs, 14) + 6
	end
	return y + 6
end

-- What's new's height from where its texts end: Earlier versions under them
-- while older versions are still to show
local function NewsHeight(card)
	local more = card.more
	if more and card.shownVersions < #CHANGELOG then
		more:SetPoint("TOPLEFT", CARD_PAD, -card.textY)
		card.h = card.textY + 26 + CARD_PAD
	else
		if more then
			more:Hide()
		end
		card.h = card.textY + CARD_PAD
	end
	card:SetHeight(card.h)
end

-- What's new's texts placed again from their wrapped heights now (after a
-- font change: the lines wrap deeper or shallower), as AddVersion laid them
local function NewsLay(card)
	local y, items = CARD_HEAD, card.items
	for i = 1, #items do
		local fs = items[i]
		local dot = fs.melloDot
		if dot then
			dot:SetPoint("TOPLEFT", CARD_PAD + 4, -(y + 5))
			fs:SetPoint("TOPLEFT", CARD_PAD + 16, -y)
			y = y + WrappedHeight(fs, 14) + 6
		elseif fs.melloTag then
			fs.melloTag:SetPoint("TOPLEFT", CARD_PAD + W.TAG_PAD, -(y + 1))
			fs:SetPoint("TOPLEFT", CARD_PAD + fs.melloIndent, -y)
			y = y + WrappedHeight(fs, 14) + 6
		else
			if i > 1 then
				y = y + 6   -- (under the version before)
			end
			fs:SetPoint("TOPLEFT", CARD_PAD, -y)
			y = y + 22
		end
	end
	card.textY = y + 6
	NewsHeight(card)
end

-- Help's height as RunHelp lays it, its note `note` tall
local function HelpHeight(note)
	return CARD_HEAD + 22 + #COMMANDS * 20 + 8 + 22 + #LINKS * 28 + 8 + note + CARD_PAD
end

-- Home's section from its cards: Help under the taller one (its planned
-- height until it is made, so the page does not jump when it comes); with
-- `height`, the section's and the page's height laid too
local function LayHome(page, height)
	local sec, help = page.homeSection, page.helpSection
	local top = math.max(page.news.h, page.setup.h) + HOME_GAP
	if help then
		help:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -top)
		sec.y = top + help.h
	else
		sec.y = top + HelpHeight(HELP_NOTE_H)
	end
	if height then
		sec:Finish()
		if page.current == sec then
			PageHeight(page, sec)
		end
	end
end

-- Home's jobs (the worker's, on its one section): { fn, arg }
local function HomeJob(sec, job)
	job[1](sec, job[2])
end

-- the links: their text stays as it is (select it and copy it)
local LinkChanged = Shared("OnTextChanged on the configurator's links", function(self, user)
	if user then
		self:SetText(self.melloLink)
	end
end, "script")
local LinkEscape = Shared("OnEscapePressed on the configurator's links", function(self)
	self:ClearFocus()
end, "script")
local LinkFocus = Shared("OnEditFocusGained on the configurator's links", function(self)
	self:HighlightText()
end, "script")

-- Help (a job): the commands a player uses, the links, and where the
-- settings are kept, full width under the two cards
local function RunHelp(sec)
	local page = sec.page
	local width = page.width - PAD * 2
	local card = HomeCard(sec, width)
	CardHeading(card, "Help")
	local y = CARD_HEAD
	local head = Text(card, "GameFontNormal", "Slash commands", C.accent)
	head:SetPoint("TOPLEFT", CARD_PAD, -y)
	y = y + 22
	for _, cmd in ipairs(COMMANDS) do
		local c = Text(card, "GameFontHighlight", cmd[1], C.text)
		c:SetPoint("TOPLEFT", CARD_PAD + 6, -y)
		local what = Text(card, "GameFontHighlight", cmd[2], C.text)
		what:SetPoint("TOPLEFT", 230, -y)
		y = y + 20
	end
	y = y + 8
	local head2 = Text(card, "GameFontNormal", "Links (select the text and copy it)", C.accent)
	head2:SetPoint("TOPLEFT", CARD_PAD, -y)
	y = y + 22
	for _, link in ipairs(LINKS) do
		local lbl = Text(card, "GameFontHighlight", link[1], C.text)
		lbl:SetPoint("TOPLEFT", CARD_PAD + 6, -(y + 5))
		local box = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
		box:SetSize(420, 22)
		box:SetPoint("TOPLEFT", 136, -y)
		box:SetAutoFocus(false)
		box.melloLink = link[2]
		box:SetText(link[2])
		box:SetCursorPosition(0)
		Perf.SetScript(box, "OnTextChanged", LinkChanged)
		Perf.SetScript(box, "OnEscapePressed", LinkEscape)
		Perf.SetScript(box, "OnEditFocusGained", LinkFocus)
		-- (flat in both looks, 0.15.0, as the search box: after its scripts,
		-- its focus look hooked on them)
		W.Paint(box, C.text, "text")
		W.FlatField(box)
		y = y + 28
	end
	y = y + 8
	local note = Text(card, "GameFontHighlight", HELP_NOTE, C.text)
	note:SetPoint("TOPLEFT", CARD_PAD, -y)
	note:SetWidth(width - CARD_PAD * 2)
	note:SetWordWrap(true)
	card.note = note
	card.h = HelpHeight(WrappedHeight(note, 14))
	card:SetHeight(card.h)
	page.helpSection = card
	LayHome(page)
end

-- After a font change (page:LayTabs, from the 'fonts' topic: the page on
-- show at once, another on its next show): What's new's lines placed again
-- from their wrapped heights, Help's height from its note's, and the page
-- laid with them (Help under the taller card, the page's height)
local function RelayHome(page)
	local help = page.helpSection
	if page.news then
		NewsLay(page.news)
	end
	if help and help.note then
		help.h = HelpHeight(WrappedHeight(help.note, 14))
		help:SetHeight(help.h)
	end
	LayHome(page, true)
end

-- an older version (a job, or in the click frame): made under the ones
-- before it, the button moved under it; after the last the button goes
local function RunVersion(sec, entry)
	local page = sec.page
	local card = page.news
	card.textY = AddVersion(card, entry, card.textY)
	card.shownVersions = card.shownVersions + 1
	NewsHeight(card)
	LayHome(page)
end

-- Earlier versions: the older versions under this one's (see
-- EARLIER_BY_WORKER); the page's height laid once, after the last
local EarlierClick = Shared("OnClick on the configurator's Earlier versions", function(self)
	local page = self.melloPage
	local card = page and page.news
	if not card or card.loading then
		return
	end
	card.loading = true
	MelloUI:PlayUISound("tab")
	local sec = page.homeSection
	if EARLIER_BY_WORKER then
		self:SetText("Loading…")
		self:SetEnabled(false)
		for i = card.shownVersions + 1, #CHANGELOG do
			Queue(sec, { RunVersion, CHANGELOG[i] }, HomeJob)
		end
		Kick()
	else
		for i = card.shownVersions + 1, #CHANGELOG do
			RunVersion(sec, CHANGELOG[i])
		end
		LayHome(page, true)
	end
end, "script")

-- What's new (left): this version's changes, made at the card's width in
-- the click frame; Earlier versions under them
local function BuildNews(page, sec, width)
	local card = HomeCard(sec, width)
	card:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, 0)
	CardHeading(card, "What's new")
	card.items = {}
	-- (the line about the New tags: while this version's options show them)
	local latest = CHANGELOG[1]
	card.lead = window.anyNew and MelloUI:IsNew(latest.version) and NEW_LINE or nil
	card.textY = AddVersion(card, latest, CARD_HEAD)
	card.shownVersions = 1
	if #CHANGELOG > 1 then
		local more = W.Button(card, "Earlier versions", 150, SKIN, { onClick = EarlierClick })
		more.melloPage = page
		card.more = more
	end
	NewsHeight(card)
	page.news = card   -- (the tour points at it)
end

-- Your setup (right): a row each, shown in this order (a row not wanted
-- now -- Fit to this screen while the layout fits, the installer's row
-- without the installer -- leaves no gap)
local SETUP_ROWS = { "profile", "palette", "colours", "screen", "fit", "mello", "voice", "installer" }
local SETUP_LABELS = { profile = "Profile", palette = "Palette", colours = "Kit Colours", screen = "Screen", mello = "MelloUI",
	voice = "Voice pack", installer = "Installer" }
local SETUP_VALUES = { "palette", "colours", "screen", "mello", "voice" }

-- the rows laid top down, those wanted only; the card's height (true when
-- it changed)
local function LaySetup(card)
	local y = CARD_HEAD
	for _, row in ipairs(card.order) do
		if row.wanted then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -y)
			row:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -y)
			row:Show()
			y = y + CARD_ROW
		else
			row:Hide()
		end
	end
	local h = y + CARD_PAD - 4
	if h == card.h then
		return false
	end
	card.h = h
	card:SetHeight(h)
	return true
end

local function BuildSetup(page, sec, width, x)
	local card = HomeCard(sec, width)
	card:SetPoint("TOPLEFT", sec, "TOPLEFT", x, 0)
	CardHeading(card, "Your setup")
	card.rows, card.order, card.profileValues = {}, {}, {}
	local rows = card.rows
	for i, key in ipairs(SETUP_ROWS) do
		local row = CreateFrame("Frame", nil, card)
		row:SetHeight(CARD_ROW)
		row.wanted = key ~= "fit"
		local label = SETUP_LABELS[key]
		if label then
			row.label = Text(row, "GameFontHighlight", label, C.text)
			row.label:SetPoint("LEFT", CARD_PAD, 0)
		end
		rows[key], card.order[i] = row, row
	end
	for _, key in ipairs(SETUP_VALUES) do
		local value = Text(rows[key], "GameFontHighlight", nil, C.accent)
		value:SetPoint("LEFT", SETUP_VALUE, 0)
		value:SetPoint("RIGHT", -CARD_PAD, 0)
		value:SetWordWrap(false)
		rows[key].value = value
	end
	-- the profile in use; choosing one asks first (ConfirmLoadProfile)
	local dd = W.Dropdown(rows.profile, 180, ProfileGet, ProfileSet, card.profileValues, PROFILE_DD)
	dd:SetPoint("RIGHT", -CARD_PAD, 0)
	dd.melloTipTitle = "Profile"
	card.profile = dd
	-- the palette in use and the Kit Colours by name, each with Change… to
	-- its one place (0.15.0: Look > General, the row lit). The name has the
	-- room from the value's start to Change…: 151 of a 341 card, the longest
	-- ("Royal Azure Vibrant") needs about 116 (no swatch beside it: with
	-- one it was cut); Change…'s tooltip names it too
	local changePalette = W.Button(rows.palette, "Change…", CHANGE_W, SKIN, { onClick = ChangeClick })
	changePalette:SetPoint("RIGHT", -CARD_PAD, 0)
	changePalette.melloJump = "UIModifications.palette"
	rows.palette.value:SetPoint("RIGHT", changePalette, "LEFT", -8, 0)
	HomeTip(changePalette, "Palette", HOME_TIPS.palette)
	card.changePalette = changePalette
	local change = W.Button(rows.colours, "Change…", CHANGE_W, SKIN, { onClick = ChangeClick })
	change:SetPoint("RIGHT", -CARD_PAD, 0)
	change.melloJump = "UIModifications.kitColours"
	rows.colours.value:SetPoint("RIGHT", change, "LEFT", -8, 0)
	HomeTip(change, "Kit Colours", HOME_TIPS.change)
	card.change = change
	-- the screen, and Fit to this screen when the layout was fitted to another
	-- (or by an older model: FitDue)
	local fit = W.Button(rows.fit, "Fit to this screen", 150, SKIN, { onClick = FitClick })
	fit:SetPoint("LEFT", SETUP_VALUE, 0)
	HomeTip(fit, "Fit to this screen", HOME_TIPS.fit)
	card.fit = fit
	-- the installer again, and Revert while its restore point is kept
	local install = W.Button(rows.installer, "Install again", 120, SKIN, { gold = true, onClick = InstallClick })
	install:SetPoint("RIGHT", -CARD_PAD, 0)
	HomeTip(install, "Install again", HOME_TIPS.install)
	local revert = W.Button(rows.installer, "Revert…", 90, SKIN, { onClick = RevertClick })
	revert:SetPoint("RIGHT", install, "LEFT", -8, 0)
	HomeTip(revert, "Revert", HOME_TIPS.revert)
	card.install, card.revert = install, revert
	W.Dress(card, SKIN)   -- (the dropdown in the kit's look)
	LaySetup(card)
	page.setup = card   -- (the tour points at it)
end

-- Your setup as things are now: the profiles' list refilled in place (new
-- entries only when the names changed: the dropdown makes its menu again
-- only then), the palette's name, the Kit Colours' label, the screen, the
-- modules on, the voice pack, the installer's buttons. True when the card's
-- height changed (a row came or went).
local profileNames = {}
local function RefreshSetup(page)
	local card = page.setup
	local rows = card.rows
	local names, values = FillProfileNames(profileNames), card.profileValues
	local same = #values == #names
	for i = 1, same and #names or 0 do
		if values[i].value ~= names[i] then
			same = false
			break
		end
	end
	if not same then
		for i = #values, 1, -1 do
			values[i] = nil
		end
		for i, name in ipairs(names) do
			values[i] = { value = name, label = name }
		end
	end
	card.profile:Refresh()
	local palette = W.PaletteName(MelloUI:PaletteId())
	rows.palette.value:SetText(palette)
	if card.paletteShown ~= palette then
		-- (the tooltip's title names it: made again only when it changed)
		card.paletteShown = palette
		card.changePalette.melloTipTitle = string.format("Palette: %s", palette)
	end
	rows.colours.value:SetText(KitColoursLabel())
	rows.screen.value:SetText(ScreenText())
	local on, total = ModulesOn()
	rows.mello.value:SetText(string.format("%s, %d of %d modules on", tostring(MelloUI.version), on, total))
	rows.voice.value:SetText(VoicePackText())
	local installer = type(MelloUI.OpenInstaller) == "function"
	local I = MelloUI.Installer
	local canRevert = InstallerState() ~= nil and type(I) == "table" and type(I.Revert) == "function"
	card.install:SetShown(installer)
	card.revert:SetShown(canRevert)
	local fit, row = installer and FitDue() or false, installer or canRevert
	if rows.fit.wanted == fit and rows.installer.wanted == row then
		return false
	end
	rows.fit.wanted, rows.installer.wanted = fit, row
	return LaySetup(card)
end

function BuildHomePage(width)
	local page = NewPage("Home", width)
	BuildPageHeader(page, LOGO_FULL, "MelloUI", HOME_FLAVOUR, nil, TUTORIAL_W + 10)
	-- the guided tour (Core/Tutorial.lua), where a module page has its switch
	local tour = W.Button(page, "Tutorial", TUTORIAL_W, SKIN, { onClick = TutorialClick })
	tour:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -PAD)
	HomeTip(tour, "Tutorial", HOME_TIPS.tutorial)
	page.tutorialButton = tour
	-- one section, no tabs: What's new and Your setup side by side (two
	-- columns of 341 at the 736 page), Help under them
	local sec = NewSection(page, "Home")
	sec.needsPanel = nil   -- (each card is a panel of its own)
	page.homeSection = sec
	local column = (width - PAD * 2 - HOME_GAP) / 2
	BuildNews(page, sec, column)
	BuildSetup(page, sec, column, column + HOME_GAP)
	RefreshSetup(page)
	LayHome(page)
	page.refreshers[#page.refreshers + 1] = function()
		if RefreshSetup(page) then
			LayHome(page, true)
		end
	end
	page.relay = RelayHome   -- (page:LayTabs after a font change)
	page:Finish()
	-- Help: one job for the worker, from the next frame on (this frame's
	-- work is the header and the two cards)
	Queue(sec, { RunHelp }, HomeJob)
	RowsDoneThisFrame()
	return page
end

-- Home for the configurator's search (below): Your setup's rows by their
-- labels (the installer's by its two buttons; the palette is found on the
-- Look page, its one place) and the two cards, each with
-- what its tooltip says; `add(part, name, tip, new, when)`. A row Your setup
-- shows only at times (Fit to this screen; the installer's buttons) is found
-- only then (`when(turn)`, asked of a match once a search, not per
-- keystroke: the search keeps its answer until the box is emptied).
local SEARCH_TIPS = {
	news = "This update's changes, and the ones before it under Earlier versions.",
	help = "The slash commands, the links, and where your settings are kept.",
	screen = "Your screen's size and shape, as the installer fits MelloUI's layout to it.",
	mello = "The version running and how many of its modules are on.",
	voice = "Whether the voice pack for Voice Over, MelloUI_VoicePack, is installed.",
}
local function FitWanted()
	return type(MelloUI.OpenInstaller) == "function" and FitDue() and true or false
end
local function InstallWanted()
	return type(MelloUI.OpenInstaller) == "function"
end
local function RevertWanted()
	local I = MelloUI.Installer
	return InstallerState() ~= nil and type(I) == "table" and type(I.Revert) == "function"
end
function HomeSearch(add)
	add("news", "What's new", SEARCH_TIPS.news)
	add("profile", SETUP_LABELS.profile, HOME_TIPS.profile, PROFILE_DD.new)
	add("screen", SETUP_LABELS.screen, SEARCH_TIPS.screen)
	add("fit", "Fit to this screen", HOME_TIPS.fit, nil, FitWanted)
	add("mello", SETUP_LABELS.mello, SEARCH_TIPS.mello)
	add("voice", SETUP_LABELS.voice, SEARCH_TIPS.voice)
	add("installer", "Install again", HOME_TIPS.install, nil, InstallWanted)
	add("installer", "Revert", HOME_TIPS.revert, nil, RevertWanted)
	add("help", "Help", SEARCH_TIPS.help)
end
-- the frame a search's jump lights on Home: a Your setup row on show, or a
-- card (Help made now when the worker has not come to it)
function HomePart(page, key)
	if key == "news" then
		return page.news
	end
	if key == "help" then
		local sec = page.homeSection
		if not page.helpSection and sec and sec.jobs then
			MakeRows(sec)
		end
		return page.helpSection
	end
	local row = page.setup and page.setup.rows[key]
	return row and row.wanted and row or nil
end
end   -- (the Home block)

--------------------------------------------------------------------------------
-- Macro Backup (0.14.0): the configurator's side of the backup engine
-- (Core/Backup.lua: MacroBackupOn, SetMacroBackup, RestoreMacroBackup,
-- DeleteMacroBackup, GetBackupStatus). The copy in account macros is a
-- player's choice, off unless switched on, and it is only ever brought back
-- when asked: Restore asks first. The Profiles page shows the switch, the
-- copy's state and, while there is a copy, Restore and Delete; /mello backup
-- and /mello status say the same in chat. The replies are said here, once
-- (the engine answers with what it did, or why not).
--------------------------------------------------------------------------------

local BackupUI = {}
do
local B = BackupUI
-- the texts (in-game words: short and plain, no tool or other addon named)
local TEXT = {
	heading = "Macro Backup",
	switch = "Keep a copy in account macros",
	switchHint = "off unless you turn it on",
	switchDesc = "A copy of your settings in account macros, which the game keeps for your whole account. It is written a few seconds after a change and brought back only when you ask: Restore, or /mello backup restore. Turned off, the copy is removed and its macro slots are free again.",
	restore = "Bring back the copy",
	restoreHint = "replaces your current settings",
	restoreDesc = "Your settings as the copy in account macros has them. Asks first; save your settings as a profile first to keep them.",
	restoreButton = "Restore…",
	delete = "Remove the copy",
	deleteHint = "frees its macro slots",
	deleteDesc = "Removes the copy from your account macros, which the game keeps for your whole account: it is gone on every computer. Asks first.",
	deleteButton = "Delete",
	-- the copy's state, on the page (full sentences)
	unavailable = "Account macros are not available here, so no copy can be kept.",
	onCopy = "On. The copy fills %s (%d of %d characters)",
	onSync = ", the same as your settings.",
	onSoon = ", updated in a few seconds.",
	onCombat = ", updated when the fight ends.",
	onDiffers = ", not the same as your settings yet.",
	onEmpty = "On. The copy is written a few seconds after a change.",
	onFailed = " The last write failed: %s.",
	offFound = "Off. A copy of earlier settings was found in %s: Restore brings it back, Delete removes it. The switch stays off until one of them is done.",
	offArmed = "Off. Your old copy in %s is removed at your next login, now that the game keeps your settings.",
	offOld = "Off. An old copy is still in %s.",
	offFreed = "Off. The old copy was removed: %s free again.",
	offFreedSome = "Off. The old copy was removed and its macro slots are free again.",
	offCombat = "Off. The copy is removed from your account macros when the fight ends.",
	offNone = "Off. MelloUI uses no account macros: the game keeps your settings, and profiles are copies of your own.",
	restoredNote = " Brought back by you this session (%s).",
	-- the replies
	missing = "Macro Backup is not available.",
	loading = "Your account macros are still loading: try again in a moment.",
	nowOn = "Macro Backup is on: a copy of your settings is kept in account macros, written a few seconds after a change.",
	nowOnCombat = "Macro Backup is on: a copy of your settings is written to account macros when the fight ends.",
	nowOnFailed = "Macro Backup is on, but the copy could not be written: %s. It is tried again after your next change.",
	nowOff = "Macro Backup is off: its account macros are removed.",
	nowOffCombat = "Macro Backup is off: its account macros are removed when the fight ends.",
	nowOffNone = "Macro Backup is off: MelloUI uses no account macros.",
	alreadyOn = "Macro Backup is already on.",
	alreadyOff = "Macro Backup is already off.",
	found = "Macro Backup stays off while a copy of earlier settings is in your account macros: /mello backup restore brings it back, /mello backup delete removes it.",
	noCopy = "There is no copy of your settings in your account macros.",
	combat = "Not during a fight: try again when it ends.",
	installer = "Not while the installer is open or waiting for Keep or Revert.",
	notNow = "That is not possible right now.",
	restored = "Settings brought back from the copy in your account macros (%s). /reload brings back the fonts over names and damage numbers as well.",
	deleted = "The copy was removed from your account macros: %s free again.",
	deletedOff = "Macro Backup is off and its copy was removed from your account macros: %s free again.",
	deletedCombat = "The copy is removed from your account macros when the fight ends.",
	deletedOffCombat = "Macro Backup is off and its copy is removed from your account macros when the fight ends.",
	deletedNone = "No copy was left in your account macros to remove.",
	deletedOffNone = "Macro Backup is off; no copy was left in your account macros to remove.",
	usage = "/mello backup on | off | restore | delete",
	askRestore = "Bring back your settings from the copy in your account macros? Your current settings are replaced; save them as a profile first to keep them.",
	askDelete = "Remove the copy of your settings from your account macros? The game keeps those for your whole account, so it is gone on every computer.",
	-- the chat lines (/mello status, /mello backup)
	lineHead = "   Macro Backup: ",
	lineUnavailable = "account macros not available",
	lineOn = "on|r, %s, %d of %d characters, %s",
	lineSync = "in sync with your settings",
	lineDiffers = "not in sync with your settings yet",
	lineWrite = "   Last write: %s%s%s",
	lineError = "   Last error: %s",
	lineFound = "off|r; a copy of earlier settings is in %s: /mello backup restore brings it back, /mello backup delete removes it",
	lineArmed = "off|r; the old copy in %s is removed at your next login",
	lineOld = "off|r; an old copy is in %s (/mello backup delete removes it)",
	lineFreed = "off|r; the old copy was removed (%s free again)",
	lineFreedSome = "off|r; the old copy was removed",
	lineCombat = "off|r; the copy is removed when the fight ends",
	lineNone = "off|r, no account macros used",
}
B.TEXT = TEXT

-- a refusal's words: the engine's reason by its name, or its own sentence
local REFUSED = { combat = TEXT.combat, installer = TEXT.installer, busy = TEXT.installer, pending = TEXT.installer,
	found = TEXT.found, none = TEXT.noCopy, empty = TEXT.noCopy, nocopy = TEXT.noCopy, unavailable = TEXT.unavailable }
local function Refusal(why, fallback)
	if type(why) == "string" and why ~= "" then
		if why == "unavailable" and type(MelloUI.GetBackupStatus) == "function" then
			-- (the macro API is there: the account's macros have not come in yet,
			-- a moment after the login)
			local s = MelloUI:GetBackupStatus()
			if type(s) == "table" and s.available then
				return TEXT.loading
			end
		end
		return REFUSED[why] or why
	end
	return fallback or TEXT.notNow
end

-- the engine is there whole (Core/Backup.lua)
function B.Ready()
	return type(MelloUI.GetBackupStatus) == "function" and type(MelloUI.SetMacroBackup) == "function"
		and type(MelloUI.MacroBackupOn) == "function"
end

-- the copy's facts, or nil
function B.Status()
	if not B.Ready() then
		return nil
	end
	local s = MelloUI:GetBackupStatus()
	return type(s) == "table" and s or nil
end

-- how many MelloUI macros there are, and how many characters the copy holds
local function Count(s)
	return s and (tonumber(s.macros) or tonumber(s.chunks)) or 0
end
local function Length(s)
	return s and tonumber(s.length) or 0
end
local function Available(s)
	return s ~= nil and s.available ~= false
end
local function Macros(n)
	return n == 1 and "1 account macro" or string.format("%d account macros", n)
end
local function Slots(n)
	return n == 1 and "1 macro slot" or string.format("%d macro slots", n)
end
function B.Settings(n)
	return n == 1 and "1 setting" or string.format("%d settings", n)
end
-- the old macros freed on this PC: how many (a number over 0), true, or nil
local function Freed(s)
	local freed = s and s.freed
	if freed == true then
		return true
	end
	freed = tonumber(freed)
	return freed and freed > 0 and freed or nil
end

-- Restore is offered while the copy holds settings other than the ones in
-- use, not while the copy is about to catch up with them (on, a write due in
-- a few seconds and the last one fine) nor while a write or a delete waits
-- for a fight to end; Delete while the switch is off and MelloUI macros are
-- there (the switch turned off removes them itself), not while a delete
-- waits for a fight to end
function B.CanRestore(s)
	return Available(s) and Length(s) > 0 and not s.inSync and not s.deferredForCombat
		and not (s.on and s.pending and not s.lastError)
end
function B.CanDelete(s)
	return Available(s) and not s.on and Count(s) > 0 and not s.deferredForCombat
end

-- the copy's state as a sentence (the Profiles page)
function B.StateText(s)
	local text
	if not Available(s) then
		return TEXT.unavailable
	elseif s.on then
		if Length(s) > 0 then
			local tail = TEXT.onDiffers
			if s.inSync then
				tail = TEXT.onSync
			elseif s.deferredForCombat then
				tail = TEXT.onCombat
			elseif s.pending then
				tail = TEXT.onSoon
			end
			text = string.format(TEXT.onCopy, Macros(Count(s)), Length(s), tonumber(s.capacity) or 0) .. tail
		else
			text = TEXT.onEmpty
		end
		if s.lastError then
			text = text .. string.format(TEXT.onFailed, tostring(s.lastError))
		end
	elseif s.deferredForCombat and Count(s) > 0 then
		text = TEXT.offCombat
	elseif s.found and Count(s) > 0 then
		text = string.format(TEXT.offFound, Macros(Count(s)))
	elseif s.armed and Count(s) > 0 then
		text = string.format(TEXT.offArmed, Macros(Count(s)))
	elseif Count(s) > 0 then
		text = string.format(TEXT.offOld, Macros(Count(s)))
	elseif Freed(s) then
		local n = Freed(s)
		text = n ~= true and string.format(TEXT.offFreed, Slots(n)) or TEXT.offFreedSome
	else
		text = TEXT.offNone
	end
	if MelloUI.restoredFromBackup then
		text = text .. string.format(TEXT.restoredNote, B.Settings(tonumber(MelloUI.backupRestoredCount) or 0))
	end
	return text
end

-- the chat lines: the state, and while on its last write and error
function B.PrintLines(s)
	local gold, muted = MelloUI:PaletteCode("selectedTrim"), MelloUI:PaletteCode("mutedText")
	if not Available(s) then
		print(TEXT.lineHead .. muted .. TEXT.lineUnavailable .. "|r")
		return
	end
	local n = Count(s)
	if s.on then
		print(TEXT.lineHead .. gold .. string.format(TEXT.lineOn, Macros(n), Length(s), tonumber(s.capacity) or 0,
			s.inSync and TEXT.lineSync or TEXT.lineDiffers))
		local when = s.lastWrite and date("%H:%M:%S", s.lastWrite) or "not yet this session"
		print(string.format(TEXT.lineWrite, when, s.lastReason and (" (" .. tostring(s.lastReason) .. ")") or "",
			s.pending and ", write scheduled" or (s.deferredForCombat and ", waiting for the fight to end" or "")))
		if s.lastError then
			print(string.format(TEXT.lineError, tostring(s.lastError)))
		end
		return
	end
	local line
	if s.deferredForCombat and n > 0 then
		line = TEXT.lineCombat
	elseif s.found and n > 0 then
		line = string.format(TEXT.lineFound, Macros(n))
	elseif s.armed and n > 0 then
		line = string.format(TEXT.lineArmed, Macros(n))
	elseif n > 0 then
		line = string.format(TEXT.lineOld, Macros(n))
	elseif Freed(s) then
		local freed = Freed(s)
		line = freed ~= true and string.format(TEXT.lineFreed, Slots(freed)) or TEXT.lineFreedSome
	else
		line = TEXT.lineNone
	end
	print(TEXT.lineHead .. muted .. line)
end

-- /mello backup with no word: the state and the words it takes
function B.PrintStatus()
	if not B.Ready() then
		MelloUI:Print(TEXT.missing)
		return
	end
	MelloUI:Print(TEXT.heading .. ":")
	B.PrintLines(B.Status())
	print("   " .. TEXT.usage)
end

-- The switch (the Profiles page's row, /mello backup on | off): the reply
-- from what the switch is after the call; refused, the engine's reason
function B.Switch(on)
	on = on and true or false
	if not B.Ready() then
		MelloUI:Print(TEXT.missing)
		return false
	end
	if (MelloUI:MacroBackupOn() and true or false) == on then
		MelloUI:Print(on and TEXT.alreadyOn or TEXT.alreadyOff)
		MelloUI:RefreshConfig()
		return true
	end
	local before = Count(B.Status())
	local _, why = MelloUI:SetMacroBackup(on)
	local now = MelloUI:MacroBackupOn() and true or false
	if now ~= on then
		local s = on and B.Status()
		MelloUI:Print(Refusal(why, s and s.found and TEXT.found or nil))
	elseif on and MelloUI.InCombat() then
		MelloUI:Print(TEXT.nowOnCombat)
	elseif on then
		-- (the switch writes the copy at once: said as it went)
		local s = B.Status()
		if s and s.lastError then
			MelloUI:Print(TEXT.nowOnFailed, tostring(s.lastError))
		else
			MelloUI:Print(TEXT.nowOn)
		end
	elseif before == 0 then
		MelloUI:Print(TEXT.nowOffNone)
	else
		MelloUI:Print(MelloUI.InCombat() and TEXT.nowOffCombat or TEXT.nowOff)
	end
	MelloUI:RefreshConfig()
	return now == on
end

-- Restore, asked first (the Profiles page's Restore…, /mello backup
-- restore): the question only when there is something to bring back
local function RestoreAccepted()
	if not B.Ready() then
		return
	end
	local ok, why = MelloUI:RestoreMacroBackup()
	if ok then
		MelloUI:Print(TEXT.restored, B.Settings(type(why) == "number" and why or tonumber(MelloUI.backupRestoredCount) or 0))
	else
		MelloUI:Print(Refusal(why))
	end
	MelloUI:RefreshConfig()
end
function B.AskRestore()
	local s = B.Status()
	if not s then
		MelloUI:Print(TEXT.missing)
		return
	end
	if not (Available(s) and Length(s) > 0) then
		MelloUI:Print(TEXT.noCopy)
		return
	end
	if MelloUI.InCombat() then
		MelloUI:Print(TEXT.combat)
		return
	end
	MelloUI:Confirm({ text = TEXT.askRestore, accept = "Restore", cancel = "Cancel", onAccept = RestoreAccepted })
end

-- Delete: the typed /mello backup delete at once, the page's Delete asked
-- first (the page offers it while the switch is off; typed while it is on,
-- the engine turns the switch off with it). In a fight the engine holds the
-- delete for the fight's end ("combat").
function B.Delete(reason)
	local s = B.Status()
	if not s then
		MelloUI:Print(TEXT.missing)
		return false
	end
	local n = Count(s)
	if n == 0 then
		MelloUI:Print(TEXT.noCopy)
		return false
	end
	local removed, why = MelloUI:DeleteMacroBackup(reason or "command")
	if removed == false and why == "combat" then
		MelloUI:Print(s.on and TEXT.deletedOffCombat or TEXT.deletedCombat)
	elseif removed == false then
		MelloUI:Print(Refusal(why))
	elseif type(removed) == "number" and removed <= 0 then
		MelloUI:Print(s.on and TEXT.deletedOffNone or TEXT.deletedNone)
	else
		-- (the engine's count; one that gives none, the macros looked at)
		n = type(removed) == "number" and removed or n
		MelloUI:Print(s.on and TEXT.deletedOff or TEXT.deleted, Slots(n))
	end
	MelloUI:RefreshConfig()
	return removed ~= false
end
local function DeleteAccepted()
	B.Delete("button")
end
function B.AskDelete()
	MelloUI:Confirm({ text = TEXT.askDelete, accept = "Delete", cancel = "Cancel", onAccept = DeleteAccepted })
end
end   -- (the Macro Backup block)

--------------------------------------------------------------------------------
-- Profiles page
--------------------------------------------------------------------------------

-- the profiles' names, sorted, in a list of their own (the slash command's)
local function ProfileNames()
	return FillProfileNames({})
end

-- (what the rest of the file uses of the Profiles block)
local RefreshProfilesPage, BuildProfilesPage, ProfilesNew, ProfilesSearch, ProfilesPart
do
-- The four buttons of a profile's row: one shared handler each, reading the
-- row's `profileName` (set as the list is filled), so a refresh makes no
-- function. Load asks first (ConfirmLoadProfile, the same question as Home's
-- Profile dropdown).
local function RowProfile(button)
	local row = button:GetParent()
	return row and row.profileName or nil
end
local ProfileLoadClick = Shared("OnClick on the configurator's profile Load", function(self)
	ConfirmLoadProfile(RowProfile(self))
end, "script")
local ProfileDefaultClick = Shared("OnClick on the configurator's profile Set default", function(self)
	local name = RowProfile(self)
	if not name then
		return
	end
	MelloUI:SetDefaultProfile(MelloUI.db.defaultProfile ~= name and name or nil)
	if MelloUI.ScheduleBackup then
		MelloUI:ScheduleBackup("profile default")
	end
	RefreshProfilesPage()
end, "script")
local ProfileDeleteClick = Shared("OnClick on the configurator's profile Delete", function(self)
	local name = RowProfile(self)
	if name then
		MelloUI:DeleteProfile(name)
	end
	RefreshProfilesPage()
end, "script")
local ProfileShareClick = Shared("OnClick on the configurator's profile Share", function(self)
	local name = RowProfile(self)
	if not name then
		return
	end
	local str, err = MelloUI:ExportProfile(name)
	if str then
		MelloUI:ShowText(string.format("share string of '%s' (%d characters)", name, #str), str)
	else
		MelloUI:Print("Could not share '%s': %s.", name, err)
	end
end, "script")

-- a profile's row: a frame, four game buttons in the flat look (W.FlatButton,
-- 0.15.0), two texts (made once, kept)
local function ProfileRowFrame(sec, i)
	local row = CreateFrame("Frame", nil, sec)
	row:SetHeight(30)
	row:SetPoint("TOPLEFT", sec.list, "TOPLEFT", 0, -(i - 1) * 32)
	row:SetPoint("RIGHT", sec.list, "RIGHT")
	local line = Solid(row, "BORDER", C.line, 0.6)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	row:EnableMouse(true)
	row.hoverGlow = W.RowPlate(row, ROW_HOVER)
	row.name = Text(row, "GameFontHighlight", nil, C.text)
	row.name:SetPoint("LEFT", 14, 0)
	row.name:SetWidth(200)
	row.name:SetWordWrap(false)
	row.load = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.load:SetSize(60, 22)
	row.load:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.load:SetText("Load")
	W.FlatButton(row.load)
	row.default = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.default:SetSize(100, 22)
	row.default:SetPoint("LEFT", row.load, "RIGHT", 4, 0)
	W.FlatButton(row.default)
	row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.delete:SetSize(60, 22)
	row.delete:SetPoint("LEFT", row.default, "RIGHT", 4, 0)
	row.delete:SetText("Delete")
	W.FlatButton(row.delete)
	row.share = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.share:SetSize(60, 22)
	row.share:SetPoint("LEFT", row.delete, "RIGHT", 4, 0)
	row.share:SetText("Share")
	W.FlatButton(row.share)
	row.baked = Text(row, "GameFontHighlightSmall", nil, C.sub)
	row.baked:SetPoint("LEFT", row.share, "RIGHT", 10, 0)
	row.baked:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.baked:SetWordWrap(false)
	Perf.SetScript(row.load, "OnClick", ProfileLoadClick)
	Perf.SetScript(row.default, "OnClick", ProfileDefaultClick)
	Perf.SetScript(row.delete, "OnClick", ProfileDeleteClick)
	Perf.SetScript(row.share, "OnClick", ProfileShareClick)
	-- (the wash stays lit while the pointer is on the row's buttons)
	W.RowPlateChild(row, row.load)
	W.RowPlateChild(row, row.default)
	W.RowPlateChild(row, row.delete)
	W.RowPlateChild(row, row.share)
	sec.rowFrames[i] = row
	return row
end

-- the rows the budget left, on the next frame while the page shows (a page
-- hidden meanwhile gets them from its next refresh)
local function MoreProfileRows()
	local page = pages.Profiles
	local sec = page and page.section
	if sec and window and window:IsShown() and sec:IsVisible() then
		RefreshProfilesPage()
	end
end

-- Macro Backup's part of the page, under the list (BackupUI): its heading,
-- the switch, the copy's state in full-size text, and the rows that bring
-- the copy back or remove it, shown only while there is one. Made when the
-- engine is there, on the frame after the page's first show (that frame's
-- work is the page's own: MakeBackupPart); laid by RefreshProfilesPage
-- under the list, which it follows as the list grows or shrinks, and brought
-- in line again when the engine writes or removes the copy by itself (the
-- 'backup' topic, BackupFollow).
local function BackupGet()
	return MelloUI:MacroBackupOn() and true or false
end
local function BackupSet(value)
	BackupUI.Switch(value)
end
local BackupRestoreClick = Shared("OnClick on the configurator's Macro Backup Restore", function()
	BackupUI.AskRestore()
end, "script")
local BackupDeleteClick = Shared("OnClick on the configurator's Macro Backup Delete", function()
	BackupUI.AskDelete()
end, "script")
local BACKUP_HEAD = { name = BackupUI.TEXT.heading }
-- the update Macro Backup's rows came with (their New tags; the side list's
-- Profiles entry is tagged while they are new: ProfilesNew)
local BACKUP_TAG = { }
function ProfilesNew()
	return BackupUI.Ready() and MelloUI:IsNew(BACKUP_TAG.new) or false
end

-- a row of the part at `y` (under the copy's state, which wraps)
local function PlaceBackupRow(blk, row, y)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", blk.inset, -y)
	row:SetPoint("RIGHT", blk, "RIGHT", -blk.inset, 0)
end

local function BuildBackup(sec, width)
	if not BackupUI.Ready() then
		return
	end
	local T = BackupUI.TEXT
	local blk = CreateFrame("Frame", nil, sec)
	blk:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -sec.y)
	blk:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
	blk:SetHeight(10)
	blk.y, blk.rows = 0, 0
	blk.inset = SEC_INSET
	-- (its heading: the own windows' section heading, W.Header)
	Placed(blk, W.Header(blk, blk.y, BACKUP_HEAD.name, { inset = blk.inset }), W.HEADER_HEIGHT)
	local o = RowOpts(blk, BACKUP_TAG.new)
	local row = W.ToggleRow(blk, blk.y, T.switch, T.switchHint, T.switchDesc, BackupGet, BackupSet, o)
	blk.switchRow = Placed(blk, row, ROW_HEIGHT)
	blk.stateTop = blk.y + 8
	blk.state = Text(blk, "GameFontHighlight", nil, C.text)
	blk.state:SetPoint("TOPLEFT", blk.inset + 14, -blk.stateTop)
	blk.state:SetWidth(width - PAD * 2 - (blk.inset + 14) * 2)
	blk.state:SetWordWrap(true)
	o = RowOpts(blk, BACKUP_TAG.new)
	o.width = 90
	blk.restoreRow = W.ButtonRow(blk, 0, T.restore, T.restoreHint, T.restoreDesc, T.restoreButton, BackupRestoreClick, o)
	blk.rows = blk.rows + 1
	o = RowOpts(blk, BACKUP_TAG.new)
	o.width = 90
	blk.deleteRow = W.ButtonRow(blk, 0, T.delete, T.deleteHint, T.deleteDesc, T.deleteButton, BackupDeleteClick, o)
	o.width = nil
	blk.restoreRow:Hide()
	blk.deleteRow:Hide()
	sec.backup = blk
end

-- the part brought in line with the copy's facts; its height
local function RefreshBackup(blk)
	local s = BackupUI.Status()
	blk.switchRow:Refresh()
	blk.state:SetText(BackupUI.StateText(s))
	local y = blk.stateTop + WrappedHeight(blk.state, 14) + 10
	local restore, delete = BackupUI.CanRestore(s), BackupUI.CanDelete(s)
	if restore then
		PlaceBackupRow(blk, blk.restoreRow, y)
		y = y + ROW_HEIGHT
	end
	if delete then
		PlaceBackupRow(blk, blk.deleteRow, y)
		y = y + ROW_HEIGHT
	end
	blk.restoreRow:SetShown(restore)
	blk.deleteRow:SetShown(delete)
	blk:SetHeight(y)
	return y
end

-- the part made within the frame's one budget of rows, while the page shows
-- (a page hidden meanwhile: its next show's refresh asks again), then laid
local function MakeBackupPart()
	local page = pages.Profiles
	local sec = page and page.section
	if not (sec and sec.backupWidth and not sec.backup and window and window:IsShown() and sec:IsVisible()) then
		return
	end
	local deadline = BeginRows(FIRST_BUDGET)
	if deadline then
		BuildBackup(sec, sec.backupWidth)
		if not sec.backup then
			sec.backupWidth = nil   -- (no engine after all: no part, never asked again)
		end
	end
	EndRows()
	if sec.backup then
		RefreshProfilesPage()
	elseif sec.backupWidth then
		MelloUI.Kit:NextFrame("Config backup part", MakeBackupPart)   -- (this frame's rows are made)
	end
end

-- (the Profiles page of the look in use: each look has its own, pagesBy)
local pageNames = {}   -- (the list's names, filled again in place)
function RefreshProfilesPage()
	local page = pages.Profiles
	local sec = page and page.section
	if not sec then
		return
	end
	local db = MelloUI.db
	-- (the names first: MelloUI:Profiles() gives a default never set its
	-- built-in one, and the status must name the default the rows mark)
	local names = FillProfileNames(pageNames)
	local gold, muted = MelloUI:PaletteCode("selectedTrim"), MelloUI:PaletteCode("mutedText")
	local active = db.activeProfile and (gold .. db.activeProfile .. "|r") or (muted .. "none|r")
	local default = db.defaultProfile and (gold .. db.defaultProfile .. "|r") or (muted .. "none|r")
	sec.status:SetText(string.format("Active: %s      Default on a fresh install: %s", active, default))
	-- new row frames within the frame's one budget of rows (the one row
	-- under way finished), the rest on the next frame: a long list's first
	-- show never makes them all in one frame. Their room is kept (sec.y).
	local Kit = MelloUI.Kit
	local later = Kit and Kit.NextFrame and true or false
	local deadline, begun, laid = nil, false, 0
	for i, name in ipairs(names) do
		local row = sec.rowFrames[i]
		if not row then
			if not begun then
				begun = true
				if later then
					deadline = BeginRows(FIRST_BUDGET)   -- (nil: this frame's rows are made)
				else
					deadline = math.huge   -- (no next frame to wait for: all of them now)
				end
			end
			if not (deadline and debugprofilestop() < deadline) then
				break
			end
			row = ProfileRowFrame(sec, i)
		end
		laid = i
		row.profileName = name
		row.name:SetText(name)
		local isDefault = db.defaultProfile == name
		row.default:SetText(isDefault and ("Default  " .. MelloUI:PaletteCode("selectedTrim") .. "*|r") or "Set default")
		local builtIn = name == MelloUI.FRESH_PROFILE
		-- one shipped in the addon's files, or one of the player's own
		row.baked:SetText(builtIn and "built in" or (MelloUI:IsProfileBaked(name) and "comes with MelloUI" or "yours"))
		row.delete:SetEnabled(not builtIn)
		row:Show()
	end
	if later and deadline then
		EndRows()
	end
	if laid < #names then
		Kit:NextFrame(sec, MoreProfileRows)
	end
	for i = laid + 1, #sec.rowFrames do
		sec.rowFrames[i].profileName = nil
		sec.rowFrames[i]:Hide()
	end
	sec.empty:SetShown(#names == 0)
	sec.y = sec.listTop + math.max(#names, 1) * 32 + 10
	-- Macro Backup's part under the list (not made yet: on the next frame)
	local blk = sec.backup
	if not blk and sec.backupWidth then
		if later then
			Kit:NextFrame("Config backup part", MakeBackupPart)
		else
			BuildBackup(sec, sec.backupWidth)
			blk = sec.backup
		end
	end
	if blk then
		blk:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -sec.y)
		sec.y = sec.y + RefreshBackup(blk)
	end
	sec:Finish()
	if page.current == sec then
		PageHeight(page, sec)
	end
end

function BuildProfilesPage(width)
	local page = NewPage("Profiles", width)
	BuildPageHeader(page, PROFILES_META.icon, PROFILES_META.title, PROFILES_META.flavour, nil)
	local sec = NewSection(page, "Profiles")
	SectionPanel(sec)
	page.section = sec
	sec.rowFrames = {}

	-- (full-size text: a paragraph on the page, the no-eye-strain rule)
	local desc = Text(sec, "GameFontHighlight", nil, C.sub)
	desc:SetPoint("TOPLEFT", 4, -4)
	desc:SetWidth(width - PAD * 2 - 8)
	desc:SetWordWrap(true)
	-- what is true for a player: profiles are kept with the settings; the
	-- ones shipped in the addon's files are always there
	desc:SetText("A profile is a copy of every setting of every module. It leaves out your Dark Mode and what belongs to your characters: the flight points they know, game settings MelloUI borrowed, and steps done once; loading a profile never touches those. The one marked default is applied when MelloUI starts with no settings at all, such as on a fresh install. Load asks before it replaces your settings. Profiles you save here are kept with your settings; Share gives a string to pass one on, and Import as brings one in. The profiles that come with MelloUI are always here.")
	local y = 4 + WrappedHeight(desc, 16) + 16

	sec.nameBox = CreateFrame("EditBox", nil, sec, "InputBoxTemplate")
	sec.nameBox:SetSize(220, 22)
	sec.nameBox:SetPoint("TOPLEFT", 12, -y)
	sec.nameBox:SetAutoFocus(false)
	sec.nameBox:SetMaxLetters(40)
	W.Paint(sec.nameBox, C.text, "text")
	W.FlatField(sec.nameBox)   -- (flat in both looks, 0.15.0, as the search box)
	sec.save = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
	sec.save:SetSize(150, 22)
	sec.save:SetPoint("LEFT", sec.nameBox, "RIGHT", 8, 0)
	sec.save:SetText("Save current as")
	W.FlatButton(sec.save)
	local function Save()
		local name = sec.nameBox:GetText()
		local ok, err = MelloUI:SaveProfile(name)
		if ok then
			MelloUI:Print("Profile '%s' saved.", (name:gsub("^%s+", ""):gsub("%s+$", "")))
			sec.nameBox:SetText("")
			sec.nameBox:ClearFocus()
		else
			MelloUI:Print(err)
		end
		RefreshProfilesPage()
	end
	Perf.SetScript(sec.save, "OnClick", Save)
	page.saveButton = sec.save
	-- a share string from someone else, stored under the name typed
	sec.import = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
	sec.import:SetSize(150, 22)
	sec.import:SetPoint("LEFT", sec.save, "RIGHT", 6, 0)
	sec.import:SetText("Import as")
	W.FlatButton(sec.import)
	Perf.SetScript(sec.import, "OnClick", function()
		local name = sec.nameBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then
			MelloUI:Print("Type a name for the imported profile first, then click Import as.")
			sec.nameBox:SetFocus()
			return
		end
		MelloUI:ShowPaste(string.format("paste a MelloUI profile string for '%s'", name), function(text)
			local ok, known, total = MelloUI:ImportProfile(name, text)
			if not ok then
				MelloUI:Print("Not imported: %s.", known)
				return false
			end
			MelloUI:Print("Profile '%s' imported (%d settings). Load it from the list to use it.", name, total)
			sec.nameBox:SetText("")
			sec.nameBox:ClearFocus()
			RefreshProfilesPage()
			return true
		end)
	end)
	Perf.SetScript(sec.nameBox, "OnEnterPressed", Save)
	Perf.SetScript(sec.nameBox, "OnEscapePressed", function(self) self:ClearFocus() end)
	y = y + 22 + 14

	sec.status = Text(sec, "GameFontHighlight", nil, C.text)
	sec.status:SetPoint("TOPLEFT", 4, -y)
	y = y + 16 + 12

	sec.list = CreateFrame("Frame", nil, sec)
	sec.list:SetPoint("TOPLEFT", 0, -y)
	sec.list:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
	sec.list:SetHeight(1)
	sec.listTop = y

	sec.empty = Text(sec, "GameFontDisable", "No profiles yet. Type a name above and save the current settings.")
	sec.empty:SetPoint("TOPLEFT", sec.list, "TOPLEFT", 14, -8)

	sec.refreshers[#sec.refreshers + 1] = RefreshProfilesPage
	sec.y = y + 42
	-- Macro Backup under the list (made the frame after this one, then
	-- filled and laid with the list by the refresh every show runs; after a
	-- font change too, its state line wrapping anew: page:LayTabs)
	if BackupUI.Ready() then
		sec.backupWidth = width
		page.relay = RefreshProfilesPage
	end
	page:Finish()
	return page
end

-- the Profiles page for the configurator's search: Macro Backup's rows, the
-- two that show only while there is a copy found only then (`add` as
-- HomeSearch's, with the section's heading last). Their gates read the
-- copy's facts (every macro of it, the settings written out to compare) ONCE
-- a search, shared by the two: `turn` is the search's own count (review of
-- the search box, 2026-09-26: read per keystroke it made 2.7-36 KB each)
local gateTurn, gateStatus
local function StatusFor(turn)
	if gateTurn ~= turn then
		gateTurn, gateStatus = turn, BackupUI.Status()
	end
	return gateStatus
end
local function CanRestoreNow(turn)
	return BackupUI.CanRestore(StatusFor(turn)) and true or false
end
local function CanDeleteNow(turn)
	return BackupUI.CanDelete(StatusFor(turn)) and true or false
end
function ProfilesSearch(add)
	if not BackupUI.Ready() then
		return
	end
	local T = BackupUI.TEXT
	add("backup", T.switch, T.switchDesc, BACKUP_TAG.new, nil, T.heading)
	add("restore", T.restore, T.restoreDesc, BACKUP_TAG.new, CanRestoreNow, T.heading)
	add("delete", T.delete, T.deleteDesc, BACKUP_TAG.new, CanDeleteNow, T.heading)
end
-- the row a search's jump lights: Macro Backup's part made now when the
-- page's next frame has not made it yet, then laid with the list
function ProfilesPart(page, key)
	local sec = page and page.section
	if not sec then
		return nil
	end
	if not sec.backup and sec.backupWidth then
		BuildBackup(sec, sec.backupWidth)
		if not sec.backup then
			sec.backupWidth = nil
		end
		RefreshProfilesPage()
	end
	local blk = sec.backup
	local row = blk and ((key == "backup" and blk.switchRow) or (key == "restore" and blk.restoreRow)
		or (key == "delete" and blk.deleteRow))
	return row and row:IsShown() and row or nil
end
end   -- (the Profiles block)

--------------------------------------------------------------------------------
-- Window: the shell, the top bar, the side list, the page area (the approved
-- sketch of 2026-09-24)
--------------------------------------------------------------------------------

-- The shell (Kit:OwnWindow, Modules/KitWindow.lua): the round emblem as a
-- crest on the top rail with the short "MelloUI" plate under it, the drag
-- strip down to the top bar, one mover whose place is kept (user,
-- 2026-09-25: it opens where it was dropped), scaled down to fit the screen with its crest,
-- Escape, the open and close sounds, the look switch, and the calm ground
-- (0.15.0, Background A: the stone only as a band round one flat ground)
-- (its mover is a "tool" of Edit Layout's: never a plate there, never in its
-- Reset all; dragged by its strip at any time, its place kept at once)
local SHELL_OPTS = { area = "config", ring = { at = "top", texture = LOGO, scale = CREST_SCALE }, plate = "crest",
	title = "MelloUI", plateWidth = 200, escape = true, grabBottom = BAR_TOP, fit = true, sounds = true, calm = true,
	mover = { key = "MelloUIConfigFrame", plainDrag = "always", group = "tool" } }

-- The side list's groups (0.15.0: Core/ConfigLayout.lua's `groups`, the
-- grouped rail the user picked; made once, at the first open): a header per
-- group that has a title (they fold), an entry per page. An entry is tagged
-- New while its page holds a row new in the running update or its module is
-- new itself (the user's rule, 2026-09-26: "for people to easily navigate to
-- that option"); Home and Profiles by their own rows (HomeNew, ProfilesNew).
-- A page one module owns shows that module off on its icon.
local function RailGroups()
	local L = MelloUI.ConfigLayout
	local lay = Lay.Get()
	local homeNew, profilesNew = HomeNew(), ProfilesNew()
	local groups, anyNew = {}, homeNew or profilesNew
	for gi, g in ipairs(L and L.groups or { { entries = { "Home" } }, { entries = { "Profiles" } } }) do
		local entries = {}
		for _, key in ipairs(g.entries) do
			local p = lay.pages[key]
			if p or key == "Home" or key == "Profiles" then
				local icon, tip = PageMeta(key)
				local new
				if key == "Home" then
					new = homeNew
				elseif key == "Profiles" then
					new = profilesNew
				else
					new = p.new
				end
				anyNew = anyNew or new
				entries[#entries + 1] = { key = key, text = PageTitle(key), icon = icon, tip = tip, new = new or nil,
					module = p and p.def.module or nil }
			end
		end
		if #entries > 0 then
			groups[#groups + 1] = { key = g.title or entries[1].key or gi, title = g.title,
				collapsible = g.title ~= nil or nil, entries = entries }
		end
	end
	return groups, anyNew and true or false
end

-- the side list's icon: the widgets' framed icon, with the kit the rim every
-- window's buttons wear (the Button Border, as the old icon strip's)
local function NavIcon(row, size, skin)
	return W.IconBox(row, size, nil, skin)
end

-- The side list's states: a page whose module is off shows it on its icon
local function RefreshNav()
	local rail = window.rail
	for key, entry in pairs(window.navEntries) do
		if entry.module then
			rail:SetState(key, not MelloUI:IsModuleEnabled(entry.module) and "off" or nil)
		end
	end
	window.navStale = nil
end

-- The side list's marker on the page on show (`instant`: at once)
function NavFollow(_, instant)
	if not window then
		return
	end
	local key = currentPage
	local rail = window.rail
	rail:Select(key and rail.rows[key] and key or nil, instant)
end

-- a side-list entry clicked (the rail's onSelect)
local function NavClick(_, key)
	if currentPage ~= key then
		MelloUI:PlayUISound("page")
	end
	SelectPage(key)
end
--------------------------------------------------------------------------------
-- Search (0.14.0; user, 2026-09-26: "search box in the next build"): the box
-- at the top of the side list, flat (0.15.0: W.FlatSearch, the own windows'
-- field look). From two letters on, the
-- side list gives its place to what matches (W.NavRail's results): one a
-- row, its breadcrumb over its name (0.15.0: "Unit Frames > Buffs & Debuffs >
-- Layout"; a page of one tab: "Tooltip > Look"), found by its name, its
-- description and hint, where it lies (any case, colour codes left out),
-- the best first -- a name that is the word, then a name that starts with
-- it, then a name with a word that starts with it, then a name holding it,
-- then where it lies, then its description; within each, pages before tabs
-- and picks, those before rows (the likeliest place first) -- the New ones
-- with their tag. A click, or Enter on the one selected (the first; Up and
-- Down move), opens its page, its tab and the pick it needs (the one shown
-- when the row has a setting there, else the pick whose own setting matched
-- the words, else its first), makes its row when the page has not made it
-- yet (a page makes its rows a few a frame), scrolls it under the top of the
-- view and lights it a moment (W.Flash). Escape or an empty box gives the
-- side list back. A fight that starts while the box has the keyboard gives
-- the keyboard back to the game (the text and the results stay).
--
-- What it finds, its index: the layout (0.15.0) -- each page of the side
-- list in its order, its tabs (two or more), its picks ("Windows > Bank",
-- found by the window's own description too), and every row (a row per
-- pick is ONE result, found by each of its settings' names and
-- descriptions: "Target Frame" finds "Buffs & Debuffs On This Frame"; link
-- rows are not results: their target is) -- then Home's Your setup rows and
-- cards and the Profiles page's Macro Backup rows (their blocks name them:
-- HomeSearch, ProfilesSearch), and the top bar's controls. Made on the
-- first search (nothing at login, nothing at the window's first open but
-- the box), kept, and made again at the next search after a module was
-- switched on or off, a profile load's switches too (the 'module' topic,
-- Config_OnModule; results on show stay as they are, the one selected and
-- the list's scroll too; the index's time is counted in the frame's one
-- budget of rows, W.RowBudget, which the new result rows keep to). A row
-- found only at times (`when`) is asked once a search (`turn`), not per
-- keystroke. Once the rail's result rows are made (at most 30, reused by
-- every search after) a keystroke makes no frame and no table (the matches go
-- in one list, sorted in place); nothing runs while nobody types.
--------------------------------------------------------------------------------

local Search = {}
do
-- the box's update (its New tag, W.Badge on its top edge)
local SEARCH_TAG = { }
local HEAD, TOP, HEIGHT = 32, 4, 22   -- the box's strip over the side list (the rail's head), the box in it
-- (its New tag's plate kept clear of the template's clear button: 17 wide,
-- 3 in from the box's right, and a gap)
local CLEAR_ROOM = 24
local PROMPT = "Search options"
local MIN_LETTERS = 2    -- the side list turns into results from this many letters
local MAX_SHOWN = 30     -- results shown (the rest counted in the quiet line)
local JUMP_MARGIN = 8    -- a jump's row under the top of the view (page:RevealAt's)
local TEXT = {
	none = "Nothing found. Try another word.",
	more = "%d more. Type more letters to narrow it down.",
	bar = "Top bar",
	-- Edit Layout found by the words of the mode it replaced in 0.15.0 too
	-- (search words, never shown: no text names the old mode)
	editWords = "unlock windows snap snapping auto position positions reset",
	previewWords = "preview simulate simulation test demo try fight combat behave behaviour",
}
-- within a tier: what a result opens, the likeliest target first (a page;
-- then a tab or a pick; then a row)
local RANK = { page = 0, tab = 1, pick = 1 }
local ROW_RANK = 2
local Secret = MelloUI.Safe.IsSecret
local find, lower, byte = string.find, string.lower, string.byte

local index          -- the entries (Build), nil until the first search and after a change
local found = {}     -- a search's matches, best first (filled in place)
local nFound = 0
local words = {}     -- the query's words, when it has more than one
local moreLines = {} -- [n] = the quiet line for n more, made once per n
local turn = 0       -- a search's own count: a `when` is asked once in it
local query = nil    -- the last search's text, lower case (a jump's pick: the one whose setting it names)

-- a text as a player reads it: colour codes, textures and line breaks out
-- (most texts have none: returned as they are)
local function Bare(s)
	if type(s) ~= "string" or Secret(s) then
		return nil
	end
	if not find(s, "|", 1, true) then
		return s
	end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|n", " ")
	return s
end

-- One entry of the index: what the result row shows (`name`, `path`: the
-- rail keeps its end when the row is too narrow for it), its tooltip
-- (`full`, `section`, `tip`), what a search looks in (`lname`; `lplace`: its
-- path and section; `ldesc`: its description and hint), what it opens
-- (`rank`, RANK), its place in the index (`order`, ties keep the side list's
-- order), and a search's `tier` and `score`; `when` (a row found only at
-- times) with the answer of its search (`gateTurn`, `gateOk`)
local function Entry(e, name, path, tip, place, hint)
	name = Bare(name) or ""
	tip = Bare(tip)
	place = Bare(place)
	e.name, e.path, e.tip, e.section = name, path, tip, place
	e.full = path and (path .. " > " .. name) or name
	e.lname = lower(name)
	e.lplace = lower((path or "") .. " " .. (place or ""))
	e.ldesc = lower((tip or "") .. " " .. (Bare(hint) or ""))
	e.rank = RANK[e.kind] or ROW_RANK
	e.tier, e.score = 0, 0
	local n = #index + 1
	e.order = n
	index[n] = e
end

-- the words a row is found by beyond its name and description: its hint, and
-- for a row per pick every setting's own name and description
local parts = {}
local function RowWords(r)
	local n = 0
	for _, b in ipairs(r.distinct or EMPTY) do
		local opt = b.opt
		if opt then
			parts[n + 1], parts[n + 2] = opt.name or "", opt.desc or ""
			n = n + 2
		end
	end
	local b = r.b or r.distinct[1]
	if b.opt and type(b.opt.hint) == "string" then
		n = n + 1
		parts[n] = b.opt.hint
	end
	if b.opt and type(b.opt.search) == "string" then
		n = n + 1
		parts[n] = b.opt.search
	end
	local text = table.concat(parts, " ", 1, n)
	for i = 1, n do
		parts[i] = nil
	end
	return text
end

-- a page of the layout: the page, its tabs (two or more), its picks, then
-- every row under its breadcrumb
local function AddLayoutPage(key, nav, group)
	local p = Lay.Get().pages[key]
	if not p then
		return
	end
	local title = p.def.title
	Entry({ kind = "page", key = key, new = nav.new and true or nil }, title, group, nav.tip)
	local many = #p.tabs > 1
	if many then
		for i, t in ipairs(p.tabs) do
			Entry({ kind = "tab", key = key, tab = i, new = t.new or nil }, t.name, title)
		end
	end
	for _, pk in ipairs(p.picks or EMPTY) do
		Entry({ kind = "pick", key = key, pick = pk.key }, pk.label, title, pk.desc)
	end
	for _, t in ipairs(p.tabs) do
		local path = many and (title .. " > " .. t.name) or title
		for _, s in ipairs(t.sections) do
			local crumb = path .. " > " .. s.name
			for _, r in ipairs(s.rows) do
				local b = r.b or r.distinct[1]
				local tip = (b.kind == "module" and b.mod.desc) or (b.opt and b.opt.desc) or nil
				-- (a renamed row's old name: found as well as by its own, `search`)
				local old = b.opt and type(b.opt.search) == "string" and lower(b.opt.search) or nil
				Entry({ kind = "option", key = key, row = r, new = r.new and true or nil, lsearch = old }, r.name, crumb,
					tip, nil, RowWords(r))
			end
		end
	end
end

-- Home's and the Profiles page's own rows (their blocks' HomeSearch and
-- ProfilesSearch hand them over)
local function AddHome(part, name, tip, new, when)
	Entry({ kind = "part", key = "Home", part = part, when = when, new = new ~= nil and MelloUI:IsNew(new) or nil },
		name, "Home", tip)
end
local function AddProfiles(part, name, tip, new, when, section)
	Entry({ kind = "part", key = "Profiles", part = part, when = when, new = new ~= nil and MelloUI:IsNew(new) or nil },
		name, "Profiles", tip, section)
end

-- (the top bar's Edit Layout: a result while its button is there)
local function EditLayoutThere()
	return type(MelloUI.StartEditLayout) == "function"
end

local function Build()
	index = {}
	for _, g in ipairs(window.navGroups) do
		for _, nav in ipairs(g.entries) do
			local new = nav.new and true or nil
			if nav.key == "Home" then
				Entry({ kind = "page", key = "Home", new = new }, nav.text, nil, nav.tip)
				HomeSearch(AddHome)
			elseif nav.key == "Profiles" then
				Entry({ kind = "page", key = "Profiles", new = new }, nav.text, nil, nav.tip)
				ProfilesSearch(AddProfiles)
			else
				AddLayoutPage(nav.key, nav, g.title)
			end
		end
	end
	-- the top bar: Edit Layout (its tooltip's texts, and the old mode's words)
	local edit = window.parts.edit
	Entry({ kind = "bar", part = "edit", when = EditLayoutThere, new = window.editNew or nil }, edit.melloTipTitle,
		TEXT.bar, edit.melloTipBody, nil, TEXT.editWords)
	-- the top bar: Preview (0.17.0)
	local preview = window.parts.preview
	Entry({ kind = "bar", part = "preview", new = MelloUI:IsNew(preview.melloNew) or nil }, preview.melloTipTitle, TEXT.bar,
		preview.melloTipBody, nil, TEXT.previewWords)
end

-- 1: `s` starts with `q`; 2: a word in it does; 3: it holds `q` (lower case)
local function NameTier(s, q)
	local at = find(s, q, 1, true)
	if not at then
		return nil
	end
	if at == 1 then
		return 1
	end
	repeat
		local b = byte(s, at - 1)
		if not ((b >= 48 and b <= 57) or (b >= 97 and b <= 122)) then
			return 2
		end
		at = find(s, q, at + 1, true)
	until not at
	return 3
end

-- An entry's tier for the query (lower is better), nil when it does not
-- match: its name is the query (0), else its name (NameTier), where it lies
-- (4), its description (5). A query of more words: the whole of it in the
-- name first, else every word somewhere (the worst place any of them is
-- found)
local function Tier(e, q, nWords)
	if e.lname == q then
		return 0
	end
	local t = NameTier(e.lname, q)
	if t then
		return t
	end
	if e.lsearch and find(e.lsearch, q, 1, true) then
		return 3   -- (its old name holds the whole query: as a name of many words)
	end
	if nWords <= 1 then
		if find(e.lplace, q, 1, true) then
			return 4
		end
		return find(e.ldesc, q, 1, true) and 5 or nil
	end
	t = 3
	for i = 1, nWords do
		local w = words[i]
		if not find(e.lname, w, 1, true) then
			if find(e.lplace, w, 1, true) then
				if t < 4 then
					t = 4
				end
			elseif find(e.ldesc, w, 1, true) then
				t = 5
			else
				return nil
			end
		end
	end
	return t
end

local function ByScore(a, b)
	return a.score < b.score
end

-- a row found only at times: asked once a search (`turn`), its answer kept
-- for the search's other keystrokes
local function Gate(e)
	local when = e.when
	if when == nil then
		return true
	end
	if e.gateTurn ~= turn then
		e.gateTurn, e.gateOk = turn, when(turn) and true or false
	end
	return e.gateOk
end

-- The matches, best first, into `found` (in place); how many. The score: the
-- tier, then what it opens (RANK), then the index's order (fewer than 10000
-- entries)
local function Match(q, nWords)
	local n = 0
	for i = 1, #index do
		local e = index[i]
		local t = Tier(e, q, nWords)
		if t and Gate(e) then
			e.tier = t
			e.score = (t * 4 + e.rank) * 10000 + e.order
			n = n + 1
			found[n] = e
		end
	end
	for i = n + 1, nFound do
		found[i] = nil
	end
	nFound = n
	if n > 1 then
		table.sort(found, ByScore)
	end
	return n
end

-- the query: the box's text in lower case, trimmed, and its words when it
-- has more than one; nil under MIN_LETTERS
local function Query(text)
	if Secret(text) or type(text) ~= "string" then
		return nil, 0
	end
	local q = lower(text):match("^%s*(.-)%s*$")
	if #q < MIN_LETTERS then
		return nil, 0
	end
	local n = 0
	if find(q, " ", 1, true) then
		for w in q:gmatch("%S+") do
			n = n + 1
			words[n] = w
		end
	end
	for i = n + 1, #words do
		words[i] = nil
	end
	return q, n
end

-- the result rows the frame's budget left, on the next frames
local function MoreRows(rail)
	if rail:MoreResults() then
		MelloUI.Kit:NextFrame(rail, MoreRows)
	end
end

-- the quiet line under the results: nothing found, or how many more
local function NoteFor(n)
	if n == 0 then
		return TEXT.none
	end
	if n <= MAX_SHOWN then
		return nil
	end
	local more = n - MAX_SHOWN
	local line = moreLines[more]
	if not line then
		line = string.format(TEXT.more, more)
		moreLines[more] = line
	end
	return line
end

function Search.Run(text)
	local rail = window and window.rail
	if not rail then
		return
	end
	local q, nWords = Query(text)
	if not q then
		if rail.resultsShown then
			rail:HideResults()
		end
		return
	end
	query = q
	if not rail.resultsShown then
		turn = turn + 1   -- (a new search: its gates asked again)
	end
	if not index then
		-- (the index is this frame's work too: the new result rows get what
		-- it leaves of the frame's one budget of rows)
		local t = debugprofilestop()
		Build()
		W.RowBudget.Spent(debugprofilestop() - t)
	end
	local n = Match(q, nWords)
	if rail:ShowResults(found, math.min(n, MAX_SHOWN), NoteFor(n)) then
		MelloUI.Kit:NextFrame(rail, MoreRows)
	end
end

-- the index made again at the next search (a module switched on or off, by
-- hand or by a profile load); results on show stay as they are, the one
-- selected and the list's scroll too (review of the search box, 2026-09-26:
-- searched again, a switch flipped from a result sent the marker back to the
-- first), their entries still good for a click
function Search.Stale()
	index = nil
	turn = turn + 1
end
-- the gates asked again at the next keystroke ('backup': the copy written,
-- removed or brought back)
function Search.Recheck()
	turn = turn + 1
end

-- the box emptied and the side list back at once (the window shown again,
-- the tour)
function Search.Clear()
	local box = window and window.search
	if not box then
		return
	end
	box:ClearFocus()
	if window.rail.resultsShown then
		window.rail:HideResults(true)
	end
	local text = box:GetText()
	if Secret(text) or (text ~= nil and text ~= "") then
		box:SetText("")
	end
end

-- where a frame of the page lies under the page's top, from its anchors (each
-- a top point on its parent's top: Home's cards and rows, the Profiles
-- page's parts), nil when they do not say
local function TopIn(page, f)
	local y = 0
	for _ = 1, 12 do
		if f == page then
			return y
		end
		local point, rel, relPoint, _, oy = f:GetPoint(1)
		oy = Num(oy)
		if not (oy and rel and rel == f:GetParent() and type(point) == "string" and type(relPoint) == "string"
			and point:find("^TOP") and relPoint:find("^TOP")) then
			return nil
		end
		y = y - oy
		f = rel
	end
	return nil
end

-- the pick a row's result opens: the one shown when the row has a setting
-- there, else the pick whose own setting the words name, else the first
-- that has one
local function PickFor(page, r)
	if EntryLive(page, r, page.pick) then
		return page.pick
	end
	local first = nil
	for _, pk in ipairs(page.lay.picks) do
		if EntryLive(page, r, pk.key) then
			first = first or pk.key
			local b = r.keys and r.keys[pk.key]
			local opt = b and b.opt
			if query and opt and (find(lower(opt.name or ""), query, 1, true) or find(lower(opt.desc or ""), query, 1, true)) then
				return pk.key
			end
		end
	end
	return first
end

-- a result chosen: the page (or tab, pick or row) opened and brought into view
local function Jump(e)
	local kind = e.kind
	MelloUI:PlayUISound("page")
	if kind == "bar" then
		local part = window.parts[e.part]
		if part then
			W.Flash(part)
		end
		return
	end
	local page, onShow = ShowPage(e.key)
	if not page then
		return
	end
	if kind == "tab" then
		local sec = page.sections[e.tab]
		if sec and page.current ~= sec then
			page:Select(sec, onShow)
		end
		page.pager:ScrollTo(0, not onShow)
	elseif kind == "pick" then
		page:SetPick(e.pick)
		page.pager:ScrollTo(0, not onShow)
	elseif kind == "option" then
		if page.SetPick then
			page:SetPick(PickFor(page, e.row))
		end
		RevealRow(page, e.row, onShow)
	elseif kind == "part" then
		local part = (e.key == "Home" and HomePart or ProfilesPart)(page, e.part)
		if part then
			local y = TopIn(page, part)
			if y then
				page.pager:ScrollTo(math.max(0, y - JUMP_MARGIN), not onShow)
			end
			W.Flash(part)
		end
	elseif onShow then
		page.pager:ScrollTo(0, false)
	end
	NavFollow(true)
end

-- the box's and the results' handlers (one function each)
Search.Changed = Shared("OnTextChanged on the configurator's search box", function(self)
	Search.Run(self:GetText())
end, "script")
Search.Enter = Shared("OnEnterPressed on the configurator's search box", function(self)
	self:ClearFocus()
	local e = window.rail:Result()
	if e then
		Jump(e)
	end
end, "script")
Search.Escape = Shared("OnEscapePressed on the configurator's search box", function(self)
	self:ClearFocus()
	local text = self:GetText()
	if Secret(text) or (text ~= nil and text ~= "") then
		self:SetText("")   -- (its OnTextChanged gives the side list back)
	end
end, "script")
Search.Arrow = Shared("OnArrowPressed on the configurator's search box", function(_, key)
	if key == "UP" then
		window.rail:MoveResult(-1)
	elseif key == "DOWN" then
		window.rail:MoveResult(1)
	end
end, "script")
-- A fight that starts while the box has the keyboard: the keyboard given back
-- to the game at once (moving, casting), the text and the results left as
-- they are. The box takes the event only while it has the keyboard (its
-- focus scripts): nothing waits on it otherwise (review of the search box,
-- 2026-09-26)
Search.Focus = Shared("OnEditFocusGained on the configurator's search box", function(self)
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
end, "script")
Search.Unfocus = Shared("OnEditFocusLost on the configurator's search box", function(self)
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
end, "script")
Search.Fight = Shared("OnEvent on the configurator's search box (a fight starts)", function(self)
	self:ClearFocus()
end, "script")
-- a result clicked (the rail's onResult)
function Search.Pick(_, e)
	if window.search then
		window.search:ClearFocus()
	end
	Jump(e)
end
-- (tests: the index as it stands, nil before the first search)
function Search.Index()
	return index
end

-- The box, made with the side list (CreateWindow: the rail's head strip,
-- Search.HEAD tall): the game's search box, flat in both looks (W.FlatSearch,
-- 0.15.0), its New tag on its top edge, clear of its clear button. Nothing
-- else of the search is made then: the index at the first search, the result
-- rows with the first results.
Search.HEAD = HEAD
function Search.MakeBox(rail, skin)
	local search = CreateFrame("EditBox", nil, rail.head, "SearchBoxTemplate")
	search:SetPoint("TOPLEFT", rail.head, "TOPLEFT", 6, -TOP)
	search:SetPoint("TOPRIGHT", rail.head, "TOPRIGHT", -2, -TOP)
	search:SetHeight(HEIGHT)
	search:SetAutoFocus(false)
	search:SetMaxLetters(40)
	W.Paint(search, C.text, "text")   -- (what is typed, in the palette's text colour)
	if search.Instructions then
		search.Instructions:SetText(PROMPT)
	end
	Perf.HookScript(search, "OnTextChanged", Search.Changed)
	Perf.SetScript(search, "OnEnterPressed", Search.Enter)
	Perf.SetScript(search, "OnEscapePressed", Search.Escape)
	Perf.SetScript(search, "OnArrowPressed", Search.Arrow)
	-- (the template's own focus scripts kept: hooked)
	Perf.HookScript(search, "OnEditFocusGained", Search.Focus)
	Perf.HookScript(search, "OnEditFocusLost", Search.Unfocus)
	Perf.SetScript(search, "OnEvent", Search.Fight)
	search.newTag = W.Badge(search, SEARCH_TAG.new, CLEAR_ROOM)
	W.FlatSearch(search)
	window.search = search
	return search
end
end   -- (the Search block)

-- the top bar's tooltips (one handler; its texts read from the control:
-- `melloTipTitle`, `melloTipBody`), painted by the widgets' one tooltip
-- (W.ShowTooltip)
local BarEnter = Shared("OnEnter on the configurator's top bar", function(self)
	-- (under the control, over the page: the bar runs along the window's top)
	W.ShowTooltip(self, self.melloTipTitle or "", self.melloTipBody, nil, "ANCHOR_BOTTOM")
end, "script")
local function BarTip(control, title, body)
	control.melloTipTitle, control.melloTipBody = title, body
	Perf.HookScript(control, "OnEnter", BarEnter)
	Perf.HookScript(control, "OnLeave", W.TipLeave)
end

-- Edit Layout (0.15.0, the top bar's button where the look's old window
-- opened): the interface moved and sized on the screen itself
-- (Core/EditLayout.lua; the one place to move things, it replaced the old
-- Layout group of Unlock the Windows, Auto Snapping and Reset positions).
-- The button shows only while MelloUI.StartEditLayout is there (a file an
-- update adds: loaded after a full restart); Install… closes up to the
-- close button otherwise. Its tooltip is Edit Layout's own text
-- (MelloUI.EditLayout.TEXT.desc) when it gives one. /mello edit is its
-- slash command (below).
local EDIT_LAYOUT = { name = "Edit Layout",
	desc = "Move and size MelloUI's windows and bars on the screen itself. Closes the configurator while you edit." }
local EditLayoutClick = Shared("OnClick on the configurator's Edit Layout", function()
	if type(MelloUI.StartEditLayout) == "function" then
		MelloUI:StartEditLayout("configurator")
	end
end, "script")
local function RefreshBar()
	local parts = window.parts
	local edit, install = parts.edit, parts.install
	local there = type(MelloUI.StartEditLayout) == "function"
	edit:SetShown(there)
	local E = MelloUI.EditLayout
	local text = type(E) == "table" and type(E.TEXT) == "table" and E.TEXT.desc
	edit.melloTipBody = type(text) == "string" and text or EDIT_LAYOUT.desc
	install:ClearAllPoints()
	install:SetPoint("RIGHT", there and edit or parts.close, "LEFT", -8, 0)
	install:SetShown(type(MelloUI.OpenInstaller) == "function")
end

-- Preview (0.17.0; the user, 2026-10-01: "preview opens the preview menu
-- and i can click different stuff to check it out individually"): its list
-- (Core/Preview.lua) -- a fight alone or in a group, or one part at a time,
-- played as a short scene. The configurator steps aside while it plays and
-- comes back after.
local PREVIEW = { name = "Preview",
	desc = "See how your interface behaves in a fight, with made-up numbers: resting, the fight, after it. "
		.. "A fight alone or in a group, or one part at a time (the fades, the reminders, the widget column, "
		.. "party frames, the meter, Combat Text, Gains). Out of combat only; Stop ends it." }
local PreviewClick = Shared("OnClick on the configurator's Preview", function(button)
	if MelloUI.Preview then
		MelloUI.Preview:ToggleMenu(button, shell)
	end
end, "script")

local CloseClick = Shared("OnClick on the configurator's close button", function()
	window:Hide()
end, "script")

-- On every show: the side list's states (marked stale while it was closed)
-- and the top bar's buttons as what is there; the page on show is brought
-- in line by SelectPage, which every open calls. (Its own script, set before
-- the shell's hooks: the shell's look check, fit and sound come after it.)
local Window_OnShow = Shared("OnShow on the configurator", function()
	-- (a search left in the box when it closed: the side list back, at once)
	Search.Clear()
	if window.navStale then
		RefreshNav()
	end
	RefreshBar()
	MelloUI:Fire("configurator", true)
end, "script")

local Window_OnHide = Shared("OnHide on the configurator", function()
	MelloUI:Fire("configurator", false)
end, "script")

-- set while OpenConfig shows the window: a look switch at that show leaves
-- the page to OpenConfig's own SelectPage (one page made, not two)
local opening = false

-- The page on show when the look switches with the window open and the other
-- look's set has no such page yet: made on the frame after the switch, never
-- in it (review of the configurator build, 2026-09-25: the switch's frame
-- already holds the shell's reps, its dressing made at the kit's first switch
-- on and the other windows' look switches; the page, the largest one when the
-- reskin is switched on its own page, is then a first open in a frame of its
-- own). Meanwhile the old look's page is hidden (nothing drawn in the wrong
-- look); the new one fades in. false: made in the switch's frame, at once.
local LOOK_PAGE_LATER = true
local function LookPage()
	if window:IsShown() and currentPage and window.pager:Current() ~= pages[currentPage] then
		SelectPage(currentPage)
	end
end

-- The look switched (the shell's OnKit, after its own parts): the pages'
-- look, the top bar's dark panel, and the other look's set of pages, the
-- page on show taken up in it (at once when that set has it, else LookPage)
local function Config_OnKit(s, on)
	KIT = on and MelloUI.Kit or nil
	SKIN = on and s or nil
	if window.barDim then
		window.barDim:SetShown(on)
	end
	pages, building = pagesBy[on], buildingBy[on]
	if window.glowing then
		window.glowing:SetGlow(false)
		window.glowing = nil
	end
	W.ClosePictureMenu(window)
	if not currentPage or opening then
		return
	end
	local K = MelloUI.Kit
	if pages[currentPage] or not (LOOK_PAGE_LATER and K and K.NextFrame) then
		SelectPage(currentPage, true)
		return
	end
	local old = window.pager:Current()
	if old then
		old:Hide()   -- (the pager shows it again when it is chosen again)
	end
	K:NextFrame("Config look page", LookPage)
end

-- the top bar's dark panel with the kit (the eye-strain panel, WINDOW-RULES
-- 2e): a region of the WINDOW, so it never ties with the bar's controls
-- (frames above it) and the outer rail stays in front (made at the kit
-- look's first switch on)
local function DressBar(K, bar)
	window.barDim = K:StoneDim(window, { rect = bar, layer = "BORDER", sublevel = 1 })
end

-- the bus, taken at the first open (owner "Config"): each returns at once
-- while the window is closed, after marking what its next show brings in
-- line. A setting changed anywhere (a row, a slider dragged, a profile, the
-- game's own chat Background slider, a bulk write) marks the pages stale and
-- refreshes the page on show once, on the next frame (AskPageRefresh)
local function Config_OnSetting()
	AskPageRefresh()
end
-- 'backup' (the engine wrote, removed or brought back the copy by itself: a
-- write a few seconds after a change, one held for a fight's end): the
-- Profiles page on show brought in line on the next frame, once however
-- many came; hidden, its next show does it
local BackupFollow = Shared("the configurator's Macro Backup part following the engine", function()
	local page = pages.Profiles
	if window:IsShown() and page and page.section and page.section.backup and window.pager:Current() == page then
		RefreshProfilesPage()
	end
end)
local function Config_OnBackup()
	Search.Recheck()   -- (Restore and Delete are found only while there is a copy)
	if window:IsShown() and currentPage == "Profiles" then
		local K = MelloUI.Kit
		if K and K.NextFrame then
			K:NextFrame("Config backup", BackupFollow)
		else
			BackupFollow()
		end
	end
end
local function Config_OnModule(name, enabled)
	Search.Stale()   -- (the search's index made again at its next search)
	if not window:IsShown() then
		window.navStale = true
		AskPageRefresh()
		return
	end
	for key, entry in pairs(window.navEntries) do
		if entry.module == name then
			window.rail:SetState(key, not enabled and "off" or nil)
		end
	end
	-- (rows wake or sleep with a module: the page on show on the next frame)
	AskPageRefresh()
end
-- 'palette' (the palette or the Kit Colours changed; unlike the painted
-- regions' own listener, a same-table Fire counts too: a Kit Colours change
-- writes Your setup's label again, and the Profiles page's colour codes are
-- text, not painted regions): the lists a palette renames in place made again
-- (the Kit Colours), the page on show refreshed while the window is shown; a
-- closed window's next show refreshes its page anyway
local function Config_OnPalette()
	RelistPages()
	if window:IsShown() then
		MelloUI:RefreshConfig()
	end
end
-- 'fonts' (a Font Style or a font size changed): every built page's header
-- and tab row are laid again (Home's What's new and Help too: page.relay),
-- on its next show or tab click; the page on show at once
local function Config_OnFonts()
	for _, set in pairs(pagesBy) do
		for _, page in pairs(set) do
			page.tabsStale = true
		end
	end
	local page = currentPage and pages[currentPage]
	if page and window:IsShown() and window.pager:Current() == page then
		page:LayTabs()
		if page.current then
			PageHeight(page, page.current)
		end
	end
end

-- The window's parts for the guided tour (Core/Tutorial.lua): one table,
-- made with the window (MelloUI:ConfigTour). A name that is not a page is
-- taken as a /mello word (a module's name: the page it lives on)
local function TourKey(name)
	if pages[name] or name == "Home" or name == "Profiles" or Lay.Get().pages[name] then
		return name
	end
	return Lay.Word(name) or name
end
local function TourSelect(name)
	SelectPage(TourKey(name), true)
	-- (the tour shows the side list, never a search's results: every step
	-- comes through here, the side list's own step too)
	Search.Clear()
end
local function TourPage(name)
	return pages[TourKey(name)]
end
local function TourPart(name)
	return window.parts[name]
end
local function TourNav(key)
	Search.Clear()   -- (the side list, not a search's results)
	return window.rail:Reveal(TourKey(key))
end
-- a part of the page on show brought into view: the page JUMPS so the part
-- sits 60 below its top (a tip never anchors to a moving part); a part
-- outside the page on show moves nothing
local function TourScrollTo(target)
	local pager = window.pager
	local page = pager:Current()
	if not (page and type(target) == "table" and target.GetTop and pager:Contains(target)) then
		return
	end
	local pageTop, top = Num(page:GetTop()), Num(target:GetTop())
	if not (pageTop and top) then
		return
	end
	pager:ScrollTo(math.max(0, pageTop - top - 60), true)
end

-- The top bar (under the drag strip): Install…, Edit Layout and close on
-- the right. (0.15.0, the user's decision of 2026-09-27/28: Edit Layout is
-- the one place to move things, so the Layout group that stood on the left
-- -- Unlock the Windows, Auto Snapping, Reset positions -- is gone; its
-- snapping is the Snap switch on Edit Layout's own bar, its reset that
-- bar's Reset all.)
local function TopBar()
	local bar = CreateFrame("Frame", nil, window)
	bar:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE, BAR_TOP)
	bar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -EDGE, BAR_TOP)
	bar:SetHeight(BAR_HEIGHT)
	local barFill = shell:Plain(Solid(bar, "BACKGROUND", C.band, 1))
	barFill:SetAllPoints(bar)
	local barLine = shell:Plain(Solid(bar, "BORDER", C.line, 1))
	barLine:SetHeight(1)
	barLine:SetPoint("BOTTOMLEFT")
	barLine:SetPoint("BOTTOMRIGHT")
	shell:Kit(DressBar, bar)

	local close = W.CloseButton(bar, shell)
	close:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
	Perf.SetScript(close, "OnClick", CloseClick)
	-- (the main action: its edge and label in gold; there while the installer
	-- is, left of Edit Layout while that is there: RefreshBar)
	local install = W.Button(bar, "Install…", 110, shell, { gold = true, onClick = InstallClick })
	BarTip(install, "Install…", "The installer: a setup for the whole interface in a few steps, fitted to this screen. "
		.. "Closes the configurator while it runs.")
	local edit = W.Button(bar, EDIT_LAYOUT.name, 120, shell, { onClick = EditLayoutClick })
	edit:SetPoint("RIGHT", close, "LEFT", -8, 0)
	-- (its New tag inside it, at its right, while its update runs: the button
	-- grows by the tag's room, its label keeps its own)
	edit.newTag = W.ButtonTag(edit, EDIT_LAYOUT.new)
	BarTip(edit, EDIT_LAYOUT.name, EDIT_LAYOUT.desc)
	-- Preview: at the bar's left end, its list under it
	local preview = W.Button(bar, PREVIEW.name, 110, shell, { onClick = PreviewClick })
	preview:SetPoint("LEFT", bar, "LEFT", 8, 0)
	preview.newTag, preview.melloNew = W.ButtonTag(preview, PREVIEW.new), PREVIEW.new
	BarTip(preview, PREVIEW.name, PREVIEW.desc)
	return { topBar = bar, install = install, edit = edit, close = close, preview = preview }
end

local function CreateWindow()
	if window then
		return
	end
	local Kit = MelloUI.Kit   -- (looked up now: this file loads before Kit.lua and KitWindow.lua)
	window = CreateFrame("Frame", "MelloUIConfigFrame", UIParent)
	window:Hide()
	window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window.navStale = true
	-- (its own show before the shell's hooks: SetScript drops hooks)
	Perf.SetScript(window, "OnShow", Window_OnShow)
	Perf.HookScript(window, "OnHide", Window_OnHide)
	shell = Kit:OwnWindow(window, SHELL_OPTS)
	window.shell = shell
	KIT, SKIN = shell.kit and Kit or nil, shell.kit and shell or nil
	pages, building = pagesBy[shell.kit], buildingBy[shell.kit]

	-- the layout, resolved once (its time counted in this frame's rows)
	local t0 = debugprofilestop()
	Lay.Get()
	W.RowBudget.Spent(debugprofilestop() - t0)

	window.parts = TopBar()
	window.parts.title, window.parts.plate, window.parts.crest = shell.title, shell.plate, shell.crest

	-- The side list (W.NavRail, from the layout's groups): the pages in their
	-- groups, the page on show marked, the search box over them (the rail's
	-- head strip; its results take the list's place). Its rows count against
	-- the frame's one budget of rows: the page's rows in view made in the
	-- same frame get what it leaves (BeginRows / EndRows). Rows 24 high and
	-- headers 20: the 19 entries and 5 headers stand 579 tall in the 580 the
	-- list keeps under the box with every group open, so no scroll is needed
	local rail = W.NavRail(window, { width = NAV_WIDTH, rowHeight = 24, headerHeight = 20, iconMaker = NavIcon,
		onSelect = NavClick, skin = shell, head = Search.HEAD, onResult = Search.Pick })
	rail.box:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE, BODY_TOP)
	rail.box:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", EDGE, EDGE)
	window.rail = rail
	window.parts.nav = rail.box
	-- the search box on its strip (nothing else of the search now)
	Search.MakeBox(rail, shell)
	local groups, anyNew = RailGroups()
	-- (What's new's line about the New tags: while any shows; Edit Layout's
	-- button counts while it is there)
	window.editNew = type(MelloUI.StartEditLayout) == "function" and MelloUI:IsNew(EDIT_LAYOUT.new) or nil
	window.anyNew = anyNew or window.editNew or MelloUI:IsNew(PREVIEW.new) or false
	-- (the search's index walks the list as it stands)
	window.navGroups = groups
	-- (each page's place in the list: the side a page slides in from)
	window.navEntries, window.pageOrder = {}, {}
	local n = 0
	for _, g in ipairs(groups) do
		for _, e in ipairs(g.entries) do
			n = n + 1
			window.navEntries[e.key] = e
			window.pageOrder[e.key] = n
		end
	end
	BeginRows(FIRST_BUDGET)
	rail:SetGroups(groups)
	EndRows()

	-- The page area: the pager (see Pages above), its scroll frame with the
	-- classic scroll bar in the gutter on its right
	PAGER.name = "MelloUIConfigScroll"
	local pager = W.Pager(window, PAGER)
	window.pager = pager
	window.scroll = pager.scroll
	window.scroll:SetPoint("TOPLEFT", window, "TOPLEFT", PAGE_LEFT, BODY_TOP)
	window.scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", PAGE_RIGHT, EDGE)
	if window.scroll.ScrollBar then
		window.scroll.ScrollBar:ClearAllPoints()
		window.scroll.ScrollBar:SetPoint("TOPLEFT", window.scroll, "TOPRIGHT", 2, -16)
		window.scroll.ScrollBar:SetPoint("BOTTOMLEFT", window.scroll, "BOTTOMRIGHT", 2, 16)
	end
	window.pageWidth = WINDOW_WIDTH - PAGE_LEFT + PAGE_RIGHT

	-- the pages' rows still to make, a few a frame while the window is open
	worker = CreateFrame("Frame", nil, window)
	worker:Hide()
	Perf.SetScript(worker, "OnUpdate", Work)

	-- Smooth scrolling (user, 2026-09-23): the wheel moves a target and the
	-- page glides to it, quick at first and easing in (each notch adds to
	-- the target, so a fast spin runs on smoothly); a scroll set any other
	-- way (the scroll bar dragged, a page opened, a jump) stops the glide
	-- where it is. Reduce Motion (UI Modifications) jumps as before. The
	-- one glide of the addon runs it (Anim:Glide, audit rank 9, made by the
	-- pager at 80 UI px a notch): no frame or OnUpdate of the window's own,
	-- nothing made per notch.
	window.pageGlide = pager.glide
	hooksecurefunc(window.scroll, "SetVerticalScroll", RowsInView)

	-- the tour's one table
	window.tour = { window = window, pager = pager, select = TourSelect, page = TourPage, part = TourPart, navEntry = TourNav,
		scrollTo = TourScrollTo, search = Search }

	-- the look switched with the window open (the shell's 'look:config')
	shell:OnKit(Config_OnKit)
	-- the bus: the pages follow every setting and module switch (once a frame,
	-- AskPageRefresh); the side list's states and the search's index follow
	-- the modules; the palette's colour codes and the Kit Colours' label
	-- follow the palette; the tab rows follow the fonts; the Profiles page's
	-- Macro Backup part follows the engine's own writes and removals
	MelloUI:On("setting", Config_OnSetting, "Config")
	MelloUI:On("module", Config_OnModule, "Config")
	MelloUI:On("palette", Config_OnPalette, "Config")
	MelloUI:On("fonts", Config_OnFonts, "Config")
	MelloUI:On("backup", Config_OnBackup, "Config")
end

local function GetPage(name)
	local page = pages[name]
	if page then
		return page
	end
	if name == "Home" then
		page = BuildHomePage(window.pageWidth)
	elseif name == "Profiles" then
		page = BuildProfilesPage(window.pageWidth)
	else
		page = BuildElementPage(name, window.pageWidth)
		if not page then
			return nil
		end
	end
	pages[name] = page
	return page
end

-- the side a page comes in from: +1 (from the right) for a page further
-- along the list, -1 for one before it, 0 for a page with no place in it
local function PageDir(from, to)
	local order = window.pageOrder
	local a, b = from and order[from], order[to]
	if not (a and b) or a == b then
		return 0
	end
	return a < b and 1 or -1
end

-- an important module's header icon pulses while its page is open (the old
-- icon strip's did; the side list itself does not glow)
local function Glow(page)
	local box = page.important and page.headerBox or nil
	local was = window.glowing
	if was == box then
		return
	end
	if was then
		was:SetGlow(false)
	end
	if box then
		box:SetGlow(true)
	end
	window.glowing = box
end

-- A page put on show (configurator build, 2026-09-25): made on its first
-- open (its rows in view within the frame's FIRST_BUDGET ms, the rest from
-- the worker while it fades in), then switched to by the pager. `instant`:
-- no fade or slide (the window just opened, the tour); the pager is instant
-- under Reduce Motion too. The page on show again (its side-list entry,
-- /mello) goes back to its top at once, as it always did. (The pager's jump
-- to the top reaches the scroll hook: it makes no row a click has had the
-- budget for.) An open picture flyout closes with the page it belongs to.
function SelectPage(name, instant)
	if not window then
		return
	end
	local fresh = not pages[name]
	local page = GetPage(name)
	if not page then
		name = "Home"
		fresh = not pages.Home
		page = GetPage("Home")
	end
	if currentPage ~= name then
		W.ClosePictureMenu(window)
	end
	local pager = page.pager
	local from = currentPage
	currentPage = name
	page:SetWidth(window.pageWidth)
	pager:Show(page, PageDir(from, name), instant)
	if page.tabsStale then
		-- (a font change since its tabs were laid: laid again, its height too)
		page:LayTabs()
		if page.current then
			PageHeight(page, page.current)
		end
	end
	if from == name then
		pager:ScrollTo(0, true)
	end
	-- a page opened before whose rows in view the worker has not come to
	-- (it was busy with another page): made now, within the same budget
	-- (a page made just now had its own in page:Select)
	local sec = page.current
	if not fresh and sec and sec.jobs then
		local deadline = BeginRows(FIRST_BUDGET)
		if deadline then
			local top, bottom = ViewRange(page, sec)
			MakeRows(sec, bottom, deadline, top)
			EndRows()
		end
	end
	-- (the other look's page may have changed the pick since this one was on
	-- show: both looks' pages share it, pickOf; SetPick refreshes the page)
	local pick = page.SetPick and pickOf[name]
	if pick and pick ~= page.pick and page.lay.pickLabel[pick] then
		page:SetPick(pick)
	else
		page:Refresh()
	end
	Glow(page)
	NavFollow(false, instant)
	Kick()
end

-- Bring every visible value in line with the settings (after a profile load,
-- a slash command, or a switch flipped elsewhere). While the window is
-- closed it only notes it: its next show and SelectPage bring it in line.
function MelloUI:RefreshConfig()
	if not window then
		return
	end
	if not window:IsShown() then
		window.navStale = true
		return
	end
	RefreshNav()
	local page = currentPage and pages[currentPage]
	if page then
		page:Refresh()
	end
end

function MelloUI:BuildConfig()
	-- Nothing to register up front; the window is built on first use.
end

-- A page by a word (0.15.0, /mello <words>, SPEC 7.2): page, tab, pick. The
-- whole text, lower case, spaces out: a page's key or title ("look",
-- "screen text", "bars & meters"), "home", then the layout's own words
-- ("fonts" is Look > Fonts, "services" Minimap > Services Bar), then a
-- module's name or title, which opens the page holding most of its rows (a
-- window panel's: Windows on its pick). Nil for none. Made on its first ask
-- (the layout's tables only; never at login).
function MelloUI:ConfigWord(word)
	if type(word) ~= "string" then
		return nil
	end
	return Lay.Word(word)
end

-- /mello [words]: the page the words name (MelloUI:ConfigWord: its tab and
-- pick too), else the page shown last (Home the first time); with the
-- window open and no page named it closes. A module's name works too (Edit
-- Layout's "All options >" hands one).
function MelloUI:OpenConfig(word)
	CreateWindow()
	local target, tab, pick
	if word ~= nil then
		target, tab, pick = self:ConfigWord(word)
	end
	local wasShown = window:IsShown()
	if wasShown and not target then
		window:Hide()
		return
	end
	if target and pick then
		pickOf[target] = pick   -- (a page made now is made on it)
	end
	opening = true
	window:Show()
	opening = false
	-- (a window just opened shows its page at once: no switch to see)
	SelectPage(target or currentPage or "Home", not wasShown)
	local page = target and pages[target]
	if not page then
		return
	end
	if pick and page.SetPick then
		page:SetPick(pick)
	end
	if tab then
		for i, t in ipairs(page.lay and page.lay.tabs or EMPTY) do
			local sec = page.sections[i]
			if t.name == tab and sec and page.current ~= sec then
				page:Select(sec, wasShown)
				page.pager:ScrollTo(0, not wasShown)
			end
		end
	end
end

-- The window's parts for the guided tour (Core/Tutorial.lua), one table made
-- with the window:
--   c.window, c.pager (its `cf` the switch's timings)
--   c.select(name)    SelectPage at once (a tip never anchors to a page still
--                     sliding in); a name that is no page is taken as a
--                     /mello word (a module's name: its page)
--   c.page(name)      the built page of the look in use, or nil
--   c.part(name)      "title" (the plate's FontString), "plate", "crest",
--                     "topBar", "install", "edit" (Edit Layout, shown while
--                     it is there), "close", "nav" (0.15.0: "layout",
--                     "unlock", "snap" and "reset" went with the Layout group)
--   c.navEntry(key)   the side-list row of a page: its group unfolded, the
--                     list jumped to it
--   c.scrollTo(part)  the page on show jumped so the part sits 60 below its
--                     top; a part outside it moves nothing
--   c.search          the search box's side: Run(text) (what typing does),
--                     Clear() (the box emptied, the side list back), Index()
--                     (its entries, nil before the first search)
function MelloUI:ConfigTour()
	CreateWindow()
	return window.tour
end

--------------------------------------------------------------------------------
-- Game menu button (Escape > MelloUI): MelloUI's own button, under the menu.
--------------------------------------------------------------------------------

-- The Gamepad UI freeze (0.15.0; the taint log of 2026-09-28): the entry the
-- menu's own AddButton made here, and the layout fields written on the
-- menu's buttons to put it above Log Out, left MelloUI's taint in the menu's
-- button list and layout, which the game reads again as the menu opens and
-- closes. With the Gamepad UI on, the close then ran the game's gamepad
-- bindings in MelloUI's execution: blocked ("MelloUI has been blocked from an
-- action only available to the Blizzard UI"), its popup looping until the
-- game froze. So the entry is MelloUI's own button:
--   * a child of UIParent at the menu's strata, a few levels over it; nothing
--     is written on the menu, its button pool or its buttons (the menu's
--     OnShow / OnHide and SetAlpha are post-hooks)
--   * made at the menu's first show with the mouse UI, never at login; never
--     made or shown while the game's Gamepad UI is on (there: /mello)
--   * centred under the menu; the Game Menu Panel lays it on its MelloUI
--     plate (Modules/GameMenuPanel.lua, Buttons), as it did the menu's own,
--     and there, inside the menu, puts it one strata up: a raise of the
--     (toplevel) menu while it shows does not carry the button along
--   * at the menu's alpha, which Windows Fade In eases in as it opens
-- The menu's OnShow hook is put on here, at load: before the Game Menu
-- Panel's (its OnEnable), so the button is there when the panel lays it.
local menuButton

-- the click: the menu closed through the game's panel manager (its gamepad
-- side would run in MelloUI's execution, so with the mouse UI only), then
-- the configurator
local function MenuButtonClick()
	MelloUI:PlayUISound("menu_button")
	if not MelloUI.Safe.GamepadUI() then
		HideUIPanel(GameMenuFrame)
	end
	MelloUI:OpenConfig()
end

-- the menu's alpha, on the button (a secret one is left)
local function FollowAlpha(_, alpha)
	alpha = MelloUI.Safe.Number(alpha)
	if alpha and menuButton then
		menuButton:SetAlpha(alpha)
	end
end

local function MakeMenuButton(menu)
	-- (the template of the menu's own entries, MainMenuFrameTemplates.xml:
	-- their look)
	menuButton = CreateFrame("Button", "MelloUIGameMenuButton", UIParent, "MainMenuFrameButtonTemplate")
	menuButton:SetText("MelloUI")
	menuButton:SetFrameStrata(menu:GetFrameStrata())
	menuButton:SetPoint("TOP", menu, "BOTTOM", 0, -4)
	Perf.SetScript(menuButton, "OnClick", MenuButtonClick)
	hooksecurefunc(menu, "SetAlpha", FollowAlpha)
end

local function MenuShown(menu)
	if MelloUI.Safe.GamepadUI() then
		if menuButton then
			menuButton:Hide()
		end
		return
	end
	if not menuButton then
		MakeMenuButton(menu)
	end
	-- (over the menu: a level read again each show, the menu is toplevel and
	-- rises as it shows; a raise while it shows can pass it, which under
	-- the menu's edge covers nothing)
	local level = MelloUI.Safe.Number(menu:GetFrameLevel())
	if level then
		menuButton:SetFrameLevel(math.min(level + 5, 10000))
	end
	FollowAlpha(menu, menu:GetAlpha())
	menuButton:Show()
end

local function MenuHidden()
	if menuButton then
		menuButton:Hide()
	end
end

if GameMenuFrame then
	Perf.HookScript(GameMenuFrame, "OnShow", MenuShown)
	Perf.HookScript(GameMenuFrame, "OnHide", MenuHidden)
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- /mello secrets: what this client offers for SECRET values (user, 2026-09-23:
-- "test the secret value tools on the client first"). Part 1, at once: which
-- of the secret-value APIs and widget methods exist. Part 2, armed until a
-- secret shows up (fight something with a target): what the client allows
-- with one -- concatenation, format, compare, arithmetic, SetText, SetAlpha,
-- a status bar. Every test runs in pcall on MelloUI's own throwaway widgets;
-- a secret is never printed, only "ok" / the error / whether the result is
-- itself secret.
--------------------------------------------------------------------------------

local probe

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local IsSecret = MelloUI.Safe.IsSecret

local function Lookup(path)
	local v = _G
	for part in path:gmatch("[^%.]+") do
		if type(v) ~= "table" then
			return nil
		end
		v = v[part]
	end
	return v
end

-- "ok" (and whether the result is secret), or the error, first line only
local function Try(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		local text = tostring(result):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*") or "?"
		return "|cffff6060error|r " .. text:sub(1, 110)
	end
	if IsSecret(result) then
		return "|cff60ff60ok|r, result SECRET"
	end
	if result == nil then
		return "|cff60ff60ok|r (nil)"
	end
	return "|cff60ff60ok|r, result plain"
end

local API = {
	"issecretvalue", "canaccessvalue", "hasanysecretvalues", "issecrettable",
	"C_Secrets.HasSecretRestrictions", "C_Secrets.ShouldAurasBeSecret", "C_Secrets.ShouldUnitIdentityBeSecret",
	"C_Secrets.ShouldCooldownsBeSecret", "C_Secrets.GetSpellAuraSecrecy", "C_Secrets.CanCompareUnitTokens",
	"C_RestrictedActions.IsAddOnRestrictionActive", "C_RestrictedActions.GetAddOnRestrictionState",
	"C_CurveUtil.CreateCurve", "C_CurveUtil.CreateColorCurve", "C_CurveUtil.EvaluateColorValueFromBoolean",
	"CurveConstants.ScaleTo100", "Enum.LuaCurveType",
	"UnitHealthPercent", "UnitHealthMissing", "UnitGetDetailedHealPrediction", "CreateUnitHealPredictionCalculator",
	"UnitCastingDuration", "UnitChannelDuration", "C_UnitAuras.GetAuraDuration", "C_UnitAuras.GetAuraDispelTypeColor",
	"AbbreviateNumbers", "CreateAbbreviateConfig",
	"C_StringUtil.TruncateWhenZero", "C_StringUtil.RoundToNearestString", "C_StringUtil.CreateNumericRuleFormatter",
	"C_DurationUtil.CreateDurationTextBinding", "Enum.StatusBarInterpolation",
	"C_EncodingUtil.SerializeCBOR", "C_EncodingUtil.CompressString", "C_EncodingUtil.EncodeBase64",
	"C_Navigation.GetFrame", "C_Navigation.GetDistance", "C_SuperTrack.SetSuperTrackedUserWaypoint",
}

local function ProbeAPIs()
	MelloUI:Print("Secret-value tools on this client (part 1 of 2):")
	local have, missing = {}, {}
	for _, path in ipairs(API) do
		if Lookup(path) ~= nil then
			have[#have + 1] = path
		else
			missing[#missing + 1] = path
		end
	end
	MelloUI:Print("  present (%d): %s", #have, table.concat(have, ", "))
	MelloUI:Print("  MISSING (%d): %s", #missing, #missing > 0 and table.concat(missing, ", ") or "none")

	-- widget methods, on throwaway widgets of our own
	local f = CreateFrame("Frame")
	local sb = CreateFrame("StatusBar", nil, f)
	local tex = f:CreateTexture()
	local methods = {
		{ "StatusBar:SetTimerDuration", sb.SetTimerDuration },
		{ "Region:SetAlphaFromBoolean", tex.SetAlphaFromBoolean },
		{ "Texture:SetVertexColorFromBoolean", tex.SetVertexColorFromBoolean },
		{ "Region:SetShownFromBoolean", tex.SetShownFromBoolean },
	}
	for _, m in ipairs(methods) do
		MelloUI:Print("  %s: %s", m[1], m[2] and "present" or "MISSING")
	end
	MelloUI:Print("  StatusBar:SetValue with smoothing: %s", Try(function()
		sb:SetMinMaxValues(0, 10)
		sb:SetValue(5, Enum.StatusBarInterpolation.ExponentialEaseOut)
		return true
	end))
	MelloUI:Print("  AuraContainer frame type: %s",
		Try(function() return CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate") end))
	if C_EventUtils and C_EventUtils.IsEventValid then
		MelloUI:Print("  event ADDON_RESTRICTION_STATE_CHANGED: %s",
			C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED") and "present" or "MISSING")
	end
	if C_Secrets and C_Secrets.HasSecretRestrictions then
		local ok, on = pcall(C_Secrets.HasSecretRestrictions)
		MelloUI:Print("  secret restrictions active on this client: %s", ok and not IsSecret(on) and tostring(on) or "?")
	end
	-- a colour curve on the player's own health (the player's is never secret)
	if C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent then
		MelloUI:Print("  colour curve through UnitHealthPercent: %s", Try(function()
			local curve = C_CurveUtil.CreateColorCurve()
			if Enum.LuaCurveType then
				curve:SetType(Enum.LuaCurveType.Step)
			end
			-- (two palette colours, one each side of half health: any two
			-- tell whether the curve answers)
			local low, high = MelloUI.Palette.selectedTab, MelloUI.Palette.text
			curve:AddPoint(0, CreateColor(low[1], low[2], low[3], 1))
			curve:AddPoint(0.5, CreateColor(high[1], high[2], high[3], 1))
			local color = UnitHealthPercent("player", true, curve)
			return color and color.GetRGB and select(2, color:GetRGB())
		end))
	end
	f:Hide()
end

-- the first secret the game hands us: a health / power number of a unit in
-- reach, or a name
local UNITS = { "target", "focus", "mouseover", "nameplate1", "nameplate2", "nameplate3", "boss1", "party1" }
local function FindSecret()
	for _, unit in ipairs(UNITS) do
		for _, fn in ipairs({ UnitHealth, UnitHealthMax, UnitPower }) do
			local ok, v = pcall(fn, unit)
			if ok and IsSecret(v) then
				return v, unit, "number"
			end
		end
	end
	for _, unit in ipairs(UNITS) do
		local ok, v = pcall(UnitName, unit)
		if ok and IsSecret(v) then
			return v, unit, "name"
		end
	end
end

local function ProbeSecret(v, unit, kind)
	MelloUI:Print("Secret found (part 2 of 2): a %s of %s. What this client allows with it:", kind, unit)
	local f = CreateFrame("Frame")
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local tex = f:CreateTexture()
	local sb = CreateFrame("StatusBar", nil, f)
	local tests = {
		{ "concatenate  \"x\" .. v", function() return "x" .. v end },
		{ "string.format(\"%s\", v)", function() return string.format("%s", v) end },
		{ "tostring(v)", function() return tostring(v) end },
		{ "compare  v == v", function() return v == v end },
		{ "boolean test  if v then", function() if v then return true end return false end },
		{ "table key  t[v]", function() return rawset({}, v, 1) ~= nil end },
		{ "fs:SetText(v)", function() fs:SetText(v); return fs:GetText() end },
		{ "fs:SetText(\"x\" .. v)", function() fs:SetText("x" .. v); return fs:GetText() end },
		{ "fs:SetFormattedText(\"%s\", v)", function() fs:SetFormattedText("%s", v); return fs:GetText() end },
	}
	if kind == "number" then
		local numeric = {
			{ "compare  v > 0", function() return v > 0 end },
			{ "arithmetic  v + 1", function() return v + 1 end },
			{ "string.format(\"%d\", v)", function() return string.format("%d", v) end },
			{ "AbbreviateNumbers(v)", function() return AbbreviateNumbers(v) end },
			{ "C_StringUtil.TruncateWhenZero(v)", function() return C_StringUtil.TruncateWhenZero(v) end },
			{ "tex:SetAlpha(v)", function() tex:SetAlpha(v); return tex:GetAlpha() end },
			{ "StatusBar SetMinMaxValues / SetValue", function() sb:SetMinMaxValues(0, UnitHealthMax(unit)); sb:SetValue(v); return true end },
			{ "UnitHealthPercent(unit, true, ScaleTo100)", function() return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) end },
		}
		for _, t in ipairs(numeric) do
			tests[#tests + 1] = t
		end
	end
	for _, t in ipairs(tests) do
		MelloUI:Print("  %-42s %s", t[1], Try(t[2]))
	end
	f:Hide()
	MelloUI:ShowLog("mello secrets")
end

local function ArmProbe()
	if not probe then
		probe = CreateFrame("Frame")
		Perf.SetScript(probe, "OnEvent", function(self)
			local v, unit, kind = FindSecret()
			if IsSecret(v) then
				self:UnregisterAllEvents()
				ProbeSecret(v, unit, kind)
			end
		end)
	end
	probe:RegisterEvent("PLAYER_TARGET_CHANGED")
	probe:RegisterEvent("PLAYER_REGEN_DISABLED")
	probe:RegisterEvent("UNIT_HEALTH")
	probe:RegisterEvent("NAME_PLATE_UNIT_ADDED")
end

function MelloUI:SecretProbe()
	self:ClearLog()
	ProbeAPIs()
	local v, unit, kind = FindSecret()
	if IsSecret(v) then
		ProbeSecret(v, unit, kind)
		return
	end
	ArmProbe()
	self:Print("No secret value in reach right now. Part 2 runs by itself as soon as the game hands one out: target an enemy and fight it. /mello secrets again re-runs part 1.")
	self:ShowLog("mello secrets")
end

--------------------------------------------------------------------------------
-- /mello auras: what this client's aura container offers (user, 2026-09-23:
-- MelloUI's own buff / debuff rows on the target frame, enemy nameplates and
-- the player's buffs, drawn by the game's AuraContainer so no aura data is
-- ever read). The retail 12.1 API is the guide; this lists what Forever
-- really has, and what the game's own aura frames are made of, before any
-- of it is used.
--------------------------------------------------------------------------------

local AURA_CONTAINER_METHODS = {
	"SetUnit", "GetUnit", "SetEnabled", "IsEnabled", "UpdateAllAuras",
	"AddAuraGroup", "AddAuraSlot", "GetAuraGroupFrame", "GetAuraGroupFrameCount", "HasAuraGroup",
	"SetAuraGroupFilterString", "SetAuraGroupLayout", "SetAuraGroupMaxFrameCount", "SetAuraGroupSortMethod",
	"SetAuraGroupCandidateFilters", "SetAuraGroupEnabled", "AddItemEnchantment",
	"SetFlowLayoutAnchorPoint", "SetFlowLayoutAxis", "SetFlowLayoutGrowthDirection",
	"SetFlowLayoutMaximumLineSize", "SetFlowLayoutPadding", "ResetFlowLayoutOptions",
	"SetAuraProcessingPolicy", "SetEditModePreviewEnabled",
}
local AURA_BUTTON_METHODS = {
	"SetIcon", "SetDurationCooldown", "SetDurationText", "SetApplicationCount", "SetApplicationBar",
	"AddDispelTypeTexture", "SetAuraBorder", "SetAuraSymbol", "SetCancelAuraButtons",
	"SetTooltipAnchorPoint", "SetHideTooltipInCombat", "SetRadialPandemicIndicator",
}
local AURA_GLOBALS = {
	"AuraContainerSortMethod", "AuraContainerSortDirection", "CustomAuraContainerAuraProcessingPolicy",
	"Enum.CustomAuraButtonDispelTypeTextureStyle", "Enum.CustomAuraButtonDispelTypeStealableFilter",
	"AnchorUtil.FlowLayoutAxis", "C_AuraContainerUtil", "GenerateClosure",
}

local function Keys(t, match)
	local out = {}
	if type(t) == "table" then
		for k in pairs(t) do
			if type(k) == "string" and (not match or k:lower():find(match, 1, true)) then
				out[#out + 1] = k
			end
		end
	end
	table.sort(out)
	return table.concat(out, ", ")
end

function MelloUI:AuraProbe()
	self:ClearLog()
	local P = function(...) self:Print(...) end
	local okC, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	if not (okC and c) then
		P("AuraContainer: cannot be created here (%s). Nothing else to probe.", tostring(c))
		self:ShowLog("mello auras")
		return
	end
	c:Hide()
	local have, miss = {}, {}
	for _, m in ipairs(AURA_CONTAINER_METHODS) do
		if type(c[m]) == "function" then have[#have + 1] = m else miss[#miss + 1] = m end
	end
	P("Container methods present (%d): %s", #have, table.concat(have, ", "))
	P("Container methods MISSING (%d): %s", #miss, #miss > 0 and table.concat(miss, ", ") or "none")
	for _, g in ipairs(AURA_GLOBALS) do
		local v = Lookup(g)
		P("  %s: %s%s", g, type(v), type(v) == "table" and (" { " .. Keys(v) .. " }") or "")
	end
	-- a group on the player's auras: every button it makes is looked at
	local buttons, initErr = {}, nil
	local okG, errG = pcall(function()
		c:SetSize(200, 40)
		c:SetPoint("CENTER")
		c:SetUnit("player")
		c:AddAuraGroup("melloProbe", "HELPFUL", {
			maxFrameCount = 4,
			initializeFrame = function(button)
				buttons[#buttons + 1] = button
				local ok, e = pcall(function()
					button:SetSize(24, 24)
					local icon = button:CreateTexture(nil, "BORDER")
					icon:SetAllPoints()
					button:SetIcon(icon)
				end)
				if not ok then initErr = e end
			end,
		})
		c:Show()
		c:UpdateAllAuras()
	end)
	P("AddAuraGroup on your buffs: %s%s", okG and "ok" or "FAILED", okG and "" or (": " .. tostring(errG)))
	local okN, n = pcall(c.GetAuraGroupFrameCount, c, "melloProbe")
	P("  buttons in the group: %s (you have to have a buff for any)", tostring(okN and n or n))
	if initErr then
		P("  a button's set-up failed: %s", tostring(initErr))
	end
	local b = buttons[1]
	if b then
		P("  a button is a %s", tostring(b.GetObjectType and b:GetObjectType()))
		local bh, bm = {}, {}
		for _, m in ipairs(AURA_BUTTON_METHODS) do
			if type(b[m]) == "function" then bh[#bh + 1] = m else bm[#bm + 1] = m end
		end
		P("Button methods present (%d): %s", #bh, table.concat(bh, ", "))
		P("Button methods MISSING (%d): %s", #bm, #bm > 0 and table.concat(bm, ", ") or "none")
	else
		P("  no button was made: buff yourself (or have any buff) and run /mello auras again for the button methods.")
	end
	pcall(c.SetEnabled, c, false)
	c:Hide()
	-- the game's own aura frames: what they are made of on this client
	local function Kind(f)
		return f and f.GetObjectType and f:GetObjectType() or type(f)
	end
	P("Game's buff frame: BuffFrame %s, DebuffFrame %s; aura keys: %s", Kind(BuffFrame), Kind(DebuffFrame), Keys(BuffFrame, "aura"))
	P("  BuffFrame.AuraContainer: %s", Kind(BuffFrame and BuffFrame.AuraContainer))
	P("Game's target frame: aura keys %s", Keys(TargetFrame, "aura"))
	P("  TargetFrame.auraPools: %s, TargetFrame.AurasContainer: %s", Kind(TargetFrame and TargetFrame.auraPools), Kind(TargetFrame and TargetFrame.AurasContainer))
	local okP, plates = pcall(C_NamePlate.GetNamePlates)
	local uf = okP and type(plates) == "table" and plates[1] and plates[1].UnitFrame
	if uf then
		P("A nameplate's unit frame: aura keys %s", Keys(uf, "aura"))
		P("  UnitFrame.AurasFrame: %s; its keys: %s", Kind(uf.AurasFrame), Keys(uf.AurasFrame))
	else
		P("No nameplate on screen: stand near an enemy for the nameplate part.")
	end
	self:ShowLog("mello auras")
end

-- /mello's own command words (0.15.0, SPEC 7.2): these first words keep their
-- commands; anything else is a page word, the WHOLE text (/mello screen text
-- opens Screen Text), resolved by MelloUI:ConfigWord. `auras` stays the aura
-- probe: the Buffs & Debuffs page is /mello buffs. One list, which the
-- handler and its test read.
local RESERVED = {}
for _, word in ipairs({ "list", "enable", "disable", "profile", "profiles", "install", "layout", "edit", "perf", "cpu",
	"secrets", "auras", "preload", "dump", "backup", "status", "tutorial", "tour", "help", "preview" }) do
	RESERVED[word] = true
end

-- /mello edit [dump] (0.15.0): Edit Layout's slash command, through its one
-- entry point MelloUI:StartEditLayout("slash") (a second /mello edit while
-- it shows is a leave, as Escape), and its dump (every element, plate and
-- layer into the log to copy). Core/EditLayout.lua is a file the update
-- added, loaded only after a full restart: until then one line says so.
-- Other words after it are a page's words as before ("/mello edit mode kit").
local EDIT_RESTART = "Edit Layout needs a full restart of the game after this update."
local EDIT_USAGE = "/mello edit (move and resize the interface) | /mello edit dump (every element it knows, to copy)"
local function EditCommand(rest, msg)
	if rest ~= "" and rest ~= "dump" then
		if MelloUI:ConfigWord(msg) then
			MelloUI:OpenConfig(msg)
		else
			MelloUI:Print(EDIT_USAGE)
		end
		return
	end
	local E = MelloUI.EditLayout
	if type(MelloUI.StartEditLayout) ~= "function" or type(E) ~= "table" then
		MelloUI:Print(EDIT_RESTART)
	elseif rest == "dump" then
		if type(E.Dump) == "function" then
			E:Dump()
		else
			MelloUI:Print(EDIT_RESTART)
		end
	else
		MelloUI:StartEditLayout("slash")
	end
end

SLASH_MELLOUI1 = "/mello"
SLASH_MELLOUI2 = "/melloui"
SlashCmdList.MELLOUI = function(msg)
	local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	msg = raw:lower()
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")
	-- a bare /mello matches nothing: no command opens the Configurator
	cmd, rest = cmd or "", rest or ""
	-- profile names keep their case (a name saved from the window is
	-- stored as typed; lowercasing here found none of them)
	local rawRest = raw:match("^%S+%s*(.-)$") or ""

	if cmd ~= "" and not RESERVED[cmd] then
		-- (0.17.0) "<module> test": a module's own sample, its SlashTest
		-- (/mello combattext test: Combat Text's burst)
		if rest == "test" then
			local module = ModuleByName(cmd)
			if module and type(module.SlashTest) == "function" then
				module:SlashTest()
				return
			end
		end
		-- "<module> <word>": a module's own word (module.SlashWords[word]:
		-- /mello combattext order, Combat Text's event order log)
		if rest ~= "" then
			local module = ModuleByName(cmd)
			local words = module and module.SlashWords
			local fn = type(words) == "table" and words[rest]
			if type(fn) == "function" then
				fn()
				return
			end
		end
		-- a page word: the whole text
		if MelloUI:ConfigWord(msg) then
			MelloUI:OpenConfig(msg)
		else
			MelloUI:Print("Unknown command or page '%s'. /mello help lists the commands, /mello list the modules.", raw)
		end
		return
	end
	if cmd == "list" then
		MelloUI:Print("Modules:")
		for name, module in MelloUI:IterateModules() do
			local state = MelloUI:IsModuleEnabled(name) and "|cff40ff40on|r" or "|cffff4040off|r"
			print(string.format("   %s  -  %s (%s)", state, module.title, name))
		end
	elseif cmd == "enable" or cmd == "disable" then
		local module = ModuleByName(rest)
		if module then
			MelloUI:SetModuleEnabled(module.name, cmd == "enable")
			MelloUI:RefreshConfig()
			MelloUI:Print("%s %s", module.title, cmd == "enable" and "enabled" or "disabled")
		else
			MelloUI:Print("Unknown module '%s'. Use /mello list.", rest)
		end
	elseif cmd == "profile" or cmd == "profiles" then
		local sub, name = rest:match("^(%S+)%s*(.-)$")
		if sub then
			name = rawRest:match("^%S+%s*(.-)$") or name
		end
		if sub == "save" and name ~= "" then
			local ok, err = MelloUI:SaveProfile(name)
			MelloUI:Print(ok and ("Profile '" .. name .. "' saved.") or err)
		elseif sub == "load" and name ~= "" then
			MelloUI:Print(MelloUI:LoadProfile(name) and ("Profile '" .. name .. "' loaded.") or ("No profile '" .. name .. "'."))
		elseif sub == "delete" and name ~= "" then
			MelloUI:Print(MelloUI:DeleteProfile(name) and ("Profile '" .. name .. "' deleted.") or ("No profile '" .. name .. "'."))
		elseif sub == "default" then
			if name == "" or name == "none" then
				MelloUI:SetDefaultProfile(nil)
				MelloUI:Print("No default profile.")
			else
				MelloUI:Print(MelloUI:SetDefaultProfile(name) and ("'" .. name .. "' is applied on a fresh install.") or ("No profile '" .. name .. "'."))
			end
		elseif sub == "export" and name ~= "" then
			local str, err = MelloUI:ExportProfile(name)
			if str then
				MelloUI:ShowText(string.format("share string of '%s' (%d characters)", name, #str), str)
			else
				MelloUI:Print("Could not share '%s': %s.", name, err)
			end
		elseif sub == "import" and name ~= "" then
			MelloUI:ShowPaste(string.format("paste a MelloUI profile string for '%s'", name), function(text)
				local ok, known, total = MelloUI:ImportProfile(name, text)
				if not ok then
					MelloUI:Print("Not imported: %s.", known)
					return false
				end
				MelloUI:Print("Profile '%s' imported (%d settings). /mello profile load %s to use it.", name, total, name)
				MelloUI:RefreshConfig()
				return true
			end)
		elseif sub == "list" or sub == nil then
			local names = ProfileNames()
			MelloUI:Print("Profiles (%d). Active: %s, default: %s.", #names, tostring(MelloUI.db.activeProfile or "none"), tostring(MelloUI.db.defaultProfile or "none"))
			for _, n in ipairs(names) do
				print("   " .. n .. (MelloUI:IsProfileBaked(n) and "  (comes with MelloUI)" or ""))
			end
		else
			MelloUI:Print("/mello profile save <name> | load <name> | delete <name> | default <name|none> | export <name> | import <name> | list")
		end
		MelloUI:RefreshConfig()
	elseif cmd == "install" then
		-- the installer (Core/InstallerWindow.lua; its own refusals: the
		-- settings still loading, combat, Edit Mode open)
		if MelloUI.OpenInstaller then
			MelloUI:OpenInstaller("command")
		else
			MelloUI:Print("The installer is not available.")
		end
	elseif cmd == "layout" then
		if rest == "export" then
			local text, name = MelloUI:ExportEditModeLayout()
			if text then
				MelloUI:ClearLog()
				MelloUI:Print("Edit Mode layout '%s' (%d chars), the game's share string, ready to copy:", tostring(name), #text)
				MelloUI:Print("%s", text)
				MelloUI:ShowLog("Edit Mode layout")
			else
				MelloUI:Print("Edit Mode layout: %s", tostring(name))
			end
		elseif rest == "apply" then
			local ok, why = MelloUI:ApplyEditModeLayout()
			if not ok then
				MelloUI:Print("Edit Mode layout: %s", tostring(why))
			end
		else
			MelloUI:Print("Edit Mode layout: %s", MelloUI:EditModeLayoutStatus())
			MelloUI:Print("/mello layout export (the active layout's share string, to copy) | apply (Mello's layout, fitted to your screen, into Edit Mode and made active)")
		end
	elseif cmd == "edit" then
		EditCommand(rest, msg)
	elseif cmd == "preview" then
		if MelloUI.Preview then
			MelloUI.Preview.Slash(rest)
		end
	elseif cmd == "perf" then
		SlashCmdList.MELLOPERF(rest or "")
	elseif cmd == "cpu" then
		if not (GetCVar and GetCVar("scriptProfile") == "1") then
			MelloUI:Print("CPU profiling is off. Run  /console scriptProfile 1  then /reload, and /mello cpu again. Turn it off afterwards with  /console scriptProfile 0  (profiling itself costs a little performance).")
			return
		end
		if rest == "reset" then
			ResetCPUUsage()
			MelloUI:Print("CPU counters reset. Play a while, then /mello cpu.")
			return
		end
		UpdateAddOnCPUUsage()
		local total = GetAddOnCPUUsage(ADDON_NAME) or 0
		local rows = {}
		for _, entry in ipairs(MelloUI.profiled) do
			local ms, calls
			if type(entry.target) == "function" then
				ms, calls = GetFunctionCPUUsage(entry.target, true)
			elseif type(entry.target) == "table" then
				ms, calls = GetFrameCPUUsage(entry.target, true)
			end
			if ms and ms > 0 then
				rows[#rows + 1] = { module = entry.module, label = entry.label, ms = ms, calls = calls or 0 }
			end
		end
		table.sort(rows, function(a, b) return a.ms > b.ms end)
		MelloUI:Print("CPU since login or the last reset: %.0f ms in MelloUI in total.", total)
		for i, row in ipairs(rows) do
			if i > 25 or row.ms < 0.5 then
				break
			end
			print(string.format("   %8.1f ms  %6d calls  %s: %s", row.ms, row.calls, row.module, row.label))
		end
		print("   Hooks and handlers not listed used less than half a millisecond. /mello cpu reset clears the counters.")
	elseif cmd == "secrets" then
		MelloUI:SecretProbe()
	elseif cmd == "widgets" then
		-- the widget column as it stands (0.16.0), into the copy window
		MelloUI.Reminders:DumpColumn()
	elseif cmd == "auras" then
		MelloUI:AuraProbe()
	elseif cmd == "preload" then
		-- Preload Artwork (UI Modifications): how many files are held, and how
		-- many the client says are in memory already
		local Kit = MelloUI.Kit
		local held, loaded = 0, nil
		if Kit and Kit.PreloadStatus then
			held, loaded = Kit:PreloadStatus()
		end
		if held == 0 then
			MelloUI:Print("Preload Artwork: nothing held (the option, the reskin or UI Modifications is off).")
		elseif loaded then
			MelloUI:Print("Preload Artwork: %d files held, %d of them loaded.", held, loaded)
		else
			MelloUI:Print("Preload Artwork: %d files held (this client does not report which are loaded).", held)
		end
	elseif cmd == "dump" then
		-- printed through MelloUI:Print (kept for the copy window), nested
		-- tables written out one level deep (the window positions), and the
		-- copy window opened at the end (user, 2026-09-21)
		MelloUI:ClearLog()
		local function Value(v)
			if type(v) == "table" then
				local parts, keys = {}, {}
				for k in pairs(v) do keys[#keys + 1] = tostring(k) end
				table.sort(keys)
				for _, k in ipairs(keys) do
					local inner = v[k]
					if type(inner) == "table" then
						local fields = {}
						for ik, iv in pairs(inner) do fields[#fields + 1] = tostring(ik) .. "=" .. tostring(iv) end
						table.sort(fields)
						inner = "{ " .. table.concat(fields, ", ") .. " }"
					end
					parts[#parts + 1] = k .. " = " .. tostring(inner)
				end
				return #parts > 0 and ("{ " .. table.concat(parts, "; ") .. " }") or "{}"
			end
			return tostring(v)
		end
		local function DumpModule(name, module)
			local db = MelloUI:GetModuleDB(name)
			local state = MelloUI:IsModuleEnabled(name) and "on" or "off"
			MelloUI:Print("%s (%s)", module.title, state)
			local keys = {}
			for k in pairs(db) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			for _, k in ipairs(keys) do
				MelloUI:Print("   %s = %s", k, Value(db[k]))
			end
		end
		local target = ModuleByName(rest)
		if target then
			DumpModule(target.name, target)
		else
			for name, module in MelloUI:IterateModules() do
				DumpModule(name, module)
			end
		end
		MelloUI:ShowLog("dump " .. tostring(rest or ""))
	elseif cmd == "backup" then
		-- Macro Backup (BackupUI): the switch, Restore (asks first, as the
		-- Profiles page's), Delete (typed: at once), else its state
		local word = rest:match("^(%S+)")
		if word == "on" or word == "off" then
			BackupUI.Switch(word == "on")
		elseif word == "restore" then
			BackupUI.AskRestore()
		elseif word == "delete" then
			BackupUI.Delete("command")
		else
			BackupUI.PrintStatus()
		end
	elseif cmd == "status" then
		-- (the palette's colours: gold for what is in place, muted for what
		-- is not)
		local gold, muted = MelloUI:PaletteCode("selectedTrim"), MelloUI:PaletteCode("mutedText")
		MelloUI:Print("Status (v%s):", tostring(MelloUI.version))
		-- (the client's late load is looked for a minute after login: a
		-- fresh start only once that look is over)
		local none = MelloUI.savedVariablesNone or (MelloUI.initialized and not MelloUI.adoptTicker)
		if not MelloUI.dbIsTemporary then
			print(string.format("   Saved variables: %sloaded by the client|r (at %s)", gold, tostring(MelloUI.savedVariablesStage or "?")))
		elseif none then
			print(string.format("   Saved variables: %snone found|r (a fresh start)", muted))
		else
			print(string.format("   Saved variables: %snot loaded yet|r (still looking)", muted))
		end
		local source
		if MelloUI.restoredFromBackup then
			local stage = MelloUI.backupRestoredStage
			source = string.format("%sthe macro copy|r (%s, %s)", gold, BackupUI.Settings(tonumber(MelloUI.backupRestoredCount) or 0),
				(stage == nil or stage == "by you") and "brought back by you" or ("at " .. tostring(stage)))
		elseif not MelloUI.dbIsTemporary then
			source = gold .. "saved variables|r"
		elseif none then
			source = muted .. "defaults|r (a fresh start)"
		else
			source = muted .. "defaults|r (for now, while the saved settings are looked for)"
		end
		print("   Settings in use come from: " .. source)
		if BackupUI.Ready() then
			BackupUI.PrintLines(BackupUI.Status())
		end
	elseif cmd == "tutorial" or cmd == "tour" then
		if MelloUI.Tutorial then
			MelloUI.Tutorial:Start()
		end
	elseif cmd == "help" then
		MelloUI:Print("Commands:")
		for _, c in ipairs(COMMANDS) do
			print(string.format("   %-26s %s", c[1], c[2]))
		end
		-- /melloperf is in COMMANDS now; these are the tuning ones
		print("   /mello dump [m]            print the stored settings of all modules or one module")
		print("   /mello edit dump           every element Edit Layout knows, and why one has no plate")
		print("   /mello cpu                 CPU time per handler (old; needs scriptProfile)")
		print("   /mello preload             how much of the artwork is preloaded")
		print("   /mello secrets             which secret-value tools this client has, and what a secret allows")
		print("   /mello auras               what this client's aura container offers (for MelloUI's own aura rows)")
		print("   /mello widgets             the widget column as it stands: each widget, what shows, the rows")
	else
		-- (a bare /mello: the page shown last, or the window closed)
		MelloUI:OpenConfig(nil)
	end
end
