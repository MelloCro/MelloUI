--------------------------------------------------------------------------------
-- MelloUI - Config
--
-- The configuration window, opened from its own MelloUI button in the game
-- menu (Escape) or with /mello. Nothing is registered with the Blizzard
-- Settings panel, so there is no entry under Options > AddOns.
--
-- Layout (the approved sketch of 2026-09-24; the configurator build):
--   the shell           Kit:OwnWindow (Modules/KitWindow.lua): the emblem as a
--                       crest on the top rail, the short "MelloUI" plate under
--                       it, the drag strip, the fit, Escape, the sounds, the
--                       look switch (the kit or the plain palette look)
--   top bar             Layout (Unlock the Windows, Auto Snapping, Reset
--                       positions) on the left; Install..., Dynamic UI
--                       Modification and close on the right
--   side list           the pages and shortcuts by group (W.NavRail), made
--                       from the registry's `group` and `navOrder`
--   page                header (icon, title, flavour, Enabled switch, Defaults)
--                       tabs built from the module's option headers
--                       a striped ledger of options: label left, control right
--   Home                What's new and Your setup side by side, Help under them
--
-- Module options are declared as a list, e.g.
--   options = {
--     { type = "header", name = "Components" },          -- becomes a tab
--     { type = "toggle", key = "unitframes", name = "Unit Frames", desc = "..." },
--     { type = "slider", key = "shade", name = "Brightness", min = 0, max = 1, step = 0.05, percent = true },
--     { type = "dropdown", key = "style", name = "Style", values = { {value="a", label="A"}, ... } },
--     { type = "button", name = "Click, light", hint = "checkboxes, tabs", text = "Play", onClick = function(module, db) ... end },
--   }
-- A module's side-list entry and page header show the `icon` (texture path)
-- and `flavour` (one line) it gives RegisterModule (the registry: audit,
-- 2026-09-24, rank 4 -- they were a hand list here), else a question mark and
-- its description.
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

local WINDOW_WIDTH, WINDOW_HEIGHT = 1000, 760
-- The width when UI Modifications' tabs would not fit one row at the Font
-- Style in use (user, 2026-09-25): measured at the first open, the
-- page area gains the 80 (TabRowFits)
local WIDE_WIDTH = 1080
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
	{ "/mello <module>", "open a module's page" },
	{ "/mello list", "modules and their state" },
	{ "/mello enable <module>", "turn a module on" },
	{ "/mello disable <module>", "turn a module off" },
	{ "/mello profile ...", "save, load, share or delete profiles, set the default" },
	{ "/mello status", "where your settings came from, and their backup" },
	{ "/mello install", "set MelloUI up: a setup, your screen, keep or go back" },
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

-- (a text's colour by its role's palette key)
local function Colour(fs, key)
	W.Paint(fs, key, "text")
end

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
		if key:lower() == wanted or m.title:lower() == wanted then
			return m
		end
	end
	return nil
end

-- a tooltip: the title in gold, the body in the text colour (the palette
-- looked up when shown)
local ShowTooltip = W.ShowTooltip

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
-- 2026-09-24: the icons follow the Dynamic UI Modification settings) -- UI
-- Modifications' Button Border, swapped live with it, in the Kit Colours
-- look -- showing the box's states: gold (checked) for the current page,
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
-- A page owns sections; a section is a frame holding rows. Sections map to
-- tabs when there is more than one.
--------------------------------------------------------------------------------

local SelectPage, NavFollow  -- forward declarations

local SEC_INSET = 10   -- the rows' margin inside a section's L1 box (kit)
local INDENT = 22      -- a sub-option's label, per level, right of its parent's

-- L1: the single rail with the list-box stone around a section. Made with
-- the section's first rows (a tab not open yet costs nothing until its rows
-- are made: user, 2026-09-24), or at once for a section made whole
local function SectionBox(sec)
	if sec.needsBox then
		sec.needsBox = nil
		SKIN:Replace(SKIN:Anchor(sec), { as = "Professions-background-summarylist", rect = sec, parent = sec, level = -1 })
		-- depth (user, 2026-09-24: "everything is just too brown ... add the
		-- checkbox section a darker tone from our color palette"): the L1
		-- box lays the palette's inner panel over its stone itself (its
		-- rule's `dim`, WINDOW-RULES 2e), the rows on that darker ground
	end
end

local function NewSection(page, name)
	local sec = CreateFrame("Frame", nil, page)
	sec.name = name
	sec.page = page
	sec.y = KIT and SEC_INSET or 0
	sec.rows = 0
	sec.refreshers = {}
	sec:SetWidth(page.width - PAD * 2)
	sec:SetHeight(10)
	sec:Hide()
	sec.needsBox = KIT and true or nil   -- (SectionBox)
	function sec:Refresh()
		for _, fn in ipairs(self.refreshers) do
			fn()
		end
	end
	-- (as tall as its rows will be while some are still to be made, when
	-- their heights are known: the scroll bar does not jump as they come)
	function sec:Finish()
		local y = (self.jobs and self.plannedY) or self.y
		self:SetHeight(math.max(y + (KIT and SEC_INSET or 0), 10))
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

-- a row's height by its option type (the builders below make them so)
local ROW_HEIGHTS = { toggle = ROW_HEIGHT, slider = SLIDER_ROW_HEIGHT, dropdown = ROW_HEIGHT, button = ROW_HEIGHT, subheader = ROW_HEIGHT - 6 }

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
	SectionBox(sec)
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

-- A ledger row (W.Row): stripe, label, optional hint, tooltip with the
-- description; with the kit a faint band on every other row (CR4, user
-- 2026-09-21) and the plate's hover look on the row under the mouse only,
-- plain the palette's hover wash and a line under it. The label and the hint
-- end 10 px left of the row's control, cut there, the full text in the
-- tooltip (no text under a control). A row that sleeps until a switch is on
-- (`sec.gate` while it is made, W.Gate) is dimmed, and its hint slot says
-- which switch wakes it, so it keeps its height. The section keeps where the
-- next row goes (`y`) and how many it holds (`rows`).
local ROW = {}   -- the rows' options (one table, filled per row)
local function RowOpts(sec)
	ROW.skin = SKIN
	ROW.inset = KIT and SEC_INSET or 0
	ROW.indent = (sec.indent or 0) * INDENT
	ROW.zebra = (KIT and sec.rows % 2 == 0) and true or false
	ROW.line = not KIT
	ROW.look = KIT and "plate" or "palette"
	ROW.gate = sec.gate
	ROW.labelKey, ROW.hintKey = nil, nil
	return ROW
end

-- after a row: the section's place for the next one
local function Placed(sec, row, height)
	sec.y = sec.y + height
	sec.rows = sec.rows + 1
	return row
end

local function Row(sec, height, label, hint, desc)
	return Placed(sec, W.Row(sec, sec.y, height, label, hint, desc, RowOpts(sec)), height)
end

-- a row's refresh kept on the section: its control's value (get again) and,
-- for a row that sleeps until a switch is on, its gate (row:Refresh)
local function Refreshes(sec, row)
	sec.refreshers[#sec.refreshers + 1] = function() row:Refresh() end
end

-- the typed rows (W.ToggleRow and the others: the row, its control on the
-- right taking get / set, the row's controls dressed by the kit's sweep)
-- on a module's settings. The important switch (the reskin) has its label
-- and its IMPORTANT hint in the palette's gold.
local function AddToggle(sec, module, db, opt)
	local key = opt.key
	local o = RowOpts(sec)
	if opt.important then
		o.labelKey, o.hintKey = C.accent, C.accent
	end
	local row = W.ToggleRow(sec, sec.y, opt.name, opt.important and "IMPORTANT" or opt.hint, opt.desc,
		function() return db[key] end,
		function(value)
			MelloUI:NotifySettingChanged(module.name, key, value)
			-- the rows that hang on this switch wake or grey at once
			sec:Refresh()
		end,
		o)
	o.labelKey, o.hintKey = nil, nil
	Refreshes(sec, row)
	return Placed(sec, row, ROW_HEIGHT)
end

local function AddSlider(sec, module, db, opt)
	local key = opt.key
	local o = RowOpts(sec)
	o.min, o.max, o.step, o.percent, o.format = opt.min, opt.max, opt.step, opt.percent, opt.format
	local row = W.SliderRow(sec, sec.y, opt.name, opt.hint, opt.desc,
		function() return db[key] end,
		function(value) MelloUI:NotifySettingChanged(module.name, key, value) end,
		o)
	o.min, o.max, o.step, o.percent, o.format = nil, nil, nil, nil, nil
	Refreshes(sec, row)
	return Placed(sec, row, SLIDER_ROW_HEIGHT)
end

local function AddDropdown(sec, module, db, opt)
	local key = opt.key
	local row = W.DropdownRow(sec, sec.y, opt.name, opt.hint, opt.desc,
		function() return db[key] end,
		function(value) MelloUI:NotifySettingChanged(module.name, key, value) end,
		opt.values, RowOpts(sec))
	Refreshes(sec, row)
	return Placed(sec, row, ROW_HEIGHT)
end

-- A row with a button on the right (user, 2026-09-22: "a preview button on
-- each sound effect"): the label, a grey hint, and the kit's red plate
-- button with `opt.text`; `opt.onClick(module, db)` on the click.
local RowButtonClick = Shared("OnClick on the configurator's row buttons", function(self)
	local opt = self.melloOpt
	if opt.onClick then
		opt.onClick(self.melloModule, self.melloDb)
	end
end, "script")

local function AddButton(sec, module, db, opt)
	local o = RowOpts(sec)
	o.width = opt.width
	local row, button = W.ButtonRow(sec, sec.y, opt.name, opt.hint, opt.desc, opt.text or "Run", RowButtonClick, o)
	o.width = nil
	button.melloOpt, button.melloModule, button.melloDb = opt, module, db
	if sec.gate then
		Refreshes(sec, row)   -- (its gate: a button has no value of its own to take again)
	end
	return Placed(sec, row, ROW_HEIGHT)
end

-- A heading inside a tab (a `header` opens a new tab; the reskin's
-- "Windows" / "HUD" groups and a folded module's own headers stay inside
-- their area's tab — user, 2026-09-21)
local function AddSubheader(sec, module, db, opt)
	local row = Row(sec, ROW_HEIGHT - 6, opt.name, nil, nil)
	Colour(row.label, C.accent)
	if KIT then
		-- SH3 (user, 2026-09-21): the header plate, the text past its gem cap
		-- (no band, no hover plate on a heading)
		row:EnableMouse(false)
		if row.band then
			row.band:Hide()
		end
		row.hover = nil
		SKIN:Replace(SKIN:Anchor(row), { as = "GuildFrame-Header", rect = row })
		row.label:SetPoint("LEFT", 34, 0)
		return
	end
	row.label:SetPoint("LEFT", 8, -4)
	local line = Solid(row, "ARTWORK", C.line, 1)
	line:SetPoint("BOTTOMLEFT", 8, 0)
	line:SetPoint("BOTTOMRIGHT", -8, 0)
end

local builders = {
	toggle = AddToggle,
	slider = AddSlider,
	dropdown = AddDropdown,
	subheader = AddSubheader,
	button = AddButton,
}

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
-- flavour as it wraps, the icon), down to where the tabs or the first
-- section start
local function HeaderHeight(page)
	return PAD + math.max(HEADER_ICON, 26 + 6 + WrappedHeight(page.flavour, 14)) + 18
end

-- a page's tab: its section's page opens it
local function TabSetSelected(self, selected)
	if selected then
		PanelTemplates_SelectTab(self)
	else
		PanelTemplates_DeselectTab(self)
	end
end
local TabClick = Shared("OnClick on the configurator's tabs", function(self)
	MelloUI:PlayUISound("tab")
	local page = self.section.page
	local changed = page.current ~= self.section
	page:Select(self.section, true)
	-- (a tab changed by hand: the side list's marker leaves the shortcut that
	-- opened the page for the page's own entry)
	if changed then
		NavFollow(true)
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

	-- A deep link (a side-list shortcut, /mello fonts): the tab holding the
	-- option `key` opened, then the page scrolled so its row sits just under
	-- the top of the view -- a glide, or at once (`instant`). The rows in
	-- view there come through the scroll hook within the frame's one budget
	-- (RowsInView; what it leaves, the worker's first work). `animate`: the
	-- tab cross-fades (the page was on show already). False when the page
	-- has no such option.
	function page:Reveal(key, instant, animate)
		local at = self.anchors and self.anchors[key]
		if not at then
			return false
		end
		if self.current ~= at.sec then
			self:Select(at.sec, animate)
		end
		self.pager:ScrollTo(math.max(0, self.headerHeight + at.y - 8), instant)
		return true
	end

	-- The header's panel down to just above the tabs / the first section, the
	-- tab row (wrapped onto a second row where the tabs do not fit the
	-- section's width) and the sections under it, each by one TOPLEFT point.
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
		if self.headerShade then
			self.headerShade:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", -(PAD - 10), -(y - 8))
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
				if KIT and KIT.SkinPanelTab then
					KIT:SkinPanelTab(tab, SKIN.replace, SKIN.skin)
				end
				tab.SetSelected = TabSetSelected
				Perf.SetScript(tab, "OnClick", TabClick)
				self.tabs[#self.tabs + 1] = tab
			end
			if not KIT then
				local line = Solid(self, "ARTWORK", C.accent2, 1)
				line:SetHeight(1)
				line:SetPoint("RIGHT", self, "RIGHT", -PAD, 0)
				self.tabLine = line
			end
		end
		self:LayTabs(true)
		local most = 0   -- (the rows of its largest tab)
		for _, sec in ipairs(self.sections) do
			sec:SetWidth(self.width - PAD * 2)
			sec:Finish()
			if not sec.jobs then
				SectionBox(sec)   -- (a tab with no rows to make)
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
-- flavour line and, for modules, the Enabled switch and the Defaults button.
-- `right`: the width kept free on the right (the module's switch and
-- Defaults, 200; Home's Tutorial button).
local function BuildPageHeader(page, icon, title, flavour, module, right)
	local box = IconBox(page, HEADER_ICON, icon)
	box:SetPoint("TOPLEFT", PAD, -PAD)
	page.headerBox = box   -- (an important module's pulses while its page is open: SelectPage)

	local titleFS = Text(page, "GameFontNormalHuge", title, C.accent)
	titleFS:SetPoint("TOPLEFT", box, "TOPRIGHT", 14, 0)
	if KIT and KIT.TitleFont then
		KIT:TitleFont(titleFS, true)
	end
	page.titleText = titleFS

	local rightWidth = right or (module and 200 or 0)
	local flavourFS = Text(page, "GameFontHighlightSmall", nil, C.sub)
	if KIT then
		-- on the page stone the dim grey drowned (user, 2026-09-21): light
		-- text with a thin outline
		flavourFS:SetFontObject("GameFontHighlightSmallOutline")
		Colour(flavourFS, C.text)
	end
	flavourFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 2, -6)
	flavourFS:SetWidth(page.width - PAD * 2 - (HEADER_ICON + 14) - rightWidth)
	flavourFS:SetWordWrap(true)
	flavourFS:SetText(flavour)
	page.flavour = flavourFS
	if KIT then
		-- the header on the palette's inner panel (user, 2026-09-24: "apply
		-- the eye strain rule to all existing windows"; WINDOW-RULES 2e): the
		-- title, the flavour, the status line AND the switches' labels on the
		-- right ("Enabled", "Unlock the Windows") lay on the plain brown --
		-- the black backing that faded out to the right (2026-09-22) left the
		-- right-hand labels on the stone. A page region under everything
		-- else, across the header's whole width; its bottom follows the
		-- header's final height (page:Finish)
		local shade = page:CreateTexture(nil, "BACKGROUND", nil, 1)
		W.Paint(shade, C.band, "fill", 0.8)
		shade:SetPoint("TOPLEFT", page, "TOPLEFT", PAD - 10, -(PAD - 10))
		page.headerShade = shade
	end

	if module then
		local lbl = Text(page, "GameFontNormal", "Enabled", C.text)
		local switch = W.Switch(page, function() return MelloUI:IsModuleEnabled(module.name) end, function(value)
			MelloUI:SetModuleEnabled(module.name, value)
			MelloUI:RefreshConfig()
		end, SwitchOpts())
		switch:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, -PAD)
		lbl:SetPoint("RIGHT", switch, "LEFT", -4, 0)
		page.switch = switch
		local defaults = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		defaults:SetSize(90, 22)
		defaults:SetPoint("TOPRIGHT", switch, "BOTTOMRIGHT", 0, -10)
		defaults:SetText("Defaults")
		Perf.SetScript(defaults, "OnClick", function()
			-- (a module whose keep list is every key, "^." (Dark Mode), keeps
			-- the player's own preferences, not data: Defaults puts them back)
			local keep = module.keep
			local preferences = type(keep) == "table" and #keep == 1 and keep[1] == "^."
			for key, value in pairs(module.defaults) do
				-- a character's own data and one-time steps stay (the module's
				-- keep list: flight points, borrowed game settings, "layout
				-- already applied"); Defaults puts back settings only
				if preferences or not MelloUI:IsPersonalKey(module.name, key) then
					if type(value) == "table" then
						-- a copy: the live table must not BE the defaults table
						-- (the window positions were written into it)
						local copy = {}
						for k, v in pairs(value) do
							copy[k] = v
						end
						value = copy
					end
					MelloUI:NotifySettingChanged(module.name, key, value)
				end
			end
			MelloUI:Print("%s: settings back to their defaults.", module.title)
			MelloUI:RefreshConfig()
		end)
		Perf.SetScript(defaults, "OnEnter", function(self) ShowTooltip(self, "Defaults", "Put every option of this module back to its default value. The module stays on or off as it is.") end)
		Perf.SetScript(defaults, "OnLeave", function() GameTooltip:Hide() end)
		page.refreshers[#page.refreshers + 1] = function()
			switch:Refresh()
		end
	end

	page.headerHeight = HeaderHeight(page)
end

local function BuildModulePage(module, width)
	local page = NewPage(module.name, width)
	page.important = module.important and true or false
	-- where each option's row will lie: its section and its planned y (a
	-- deep link's target, page:Reveal)
	page.anchors = {}
	local icon, flavour = Meta(module)
	BuildPageHeader(page, icon, module.title, flavour, module)
	-- the header's controls dressed now (Defaults and the like, red plates);
	-- the tabs dress themselves and every row is dressed as it is made, so
	-- the page is not walked whole afterwards
	W.Dress(page, SKIN)
	local db = MelloUI:GetModuleDB(module.name)
	local sec = nil
	-- an option's row by its key, in a module's options
	local function OptionOf(owner, key)
		for _, o in ipairs(owner.options) do
			if o.key == key then
				return o
			end
		end
		return nil
	end
	-- how deep an option hangs under its parents (`opt.parent`, a switch of
	-- the same module): one indent per level
	local function Depth(owner, opt)
		local depth, seen = 0, {}
		local p = opt.parent and OptionOf(owner, opt.parent)
		while p and not seen[p] and depth < 4 do
			seen[p] = true
			depth = depth + 1
			p = p.parent and OptionOf(owner, p.parent)
		end
		return depth
	end
	-- the switches a row hangs on, as one gate: `opt.parent` (indented under
	-- it) and `opt.requires` (not indented), keys of the same module's
	-- settings, and `area`: { db, key, name } of the tab's area switch
	local function GateOf(owner, ownerDb, opt, area)
		local needs = {}
		for _, key in ipairs({ opt.parent, opt.requires }) do
			if key then
				local o = OptionOf(owner, key)
				needs[#needs + 1] = { db = ownerDb, key = key, name = o and o.name or key }
			end
		end
		if area then
			table.insert(needs, 1, area)
		end
		if #needs == 0 then
			return nil
		end
		return function()
			for _, n in ipairs(needs) do
				if not n.db[n.key] then
					return false, n.name
				end
			end
			return true
		end
	end
	-- an option's row, made from its job: the builder, its indent, its gate
	-- (made with the row, so the hint slot that says which switch wakes it
	-- is laid before the texts are cut at the control; the typed row dresses
	-- its controls itself: dropdowns, red plate buttons, through the kit's
	-- sweep of the row)
	local function MakeOption(s, job)
		local owner, ownerDb, opt, area = job[1], job[2], job[3], job[4]
		local builder = builders[opt.type]
		if not builder then
			MelloUI:Print("Unknown option type '%s' in module %s", tostring(opt.type), owner.name)
			return
		end
		local sub = opt.type == "subheader"
		s.indent = not sub and ((area and 1 or 0) + Depth(owner, opt)) or 0
		s.gate = not sub and GateOf(owner, ownerDb, opt, area) or nil
		builder(s, owner, ownerDb, opt)
		s.indent, s.gate = 0, nil
	end
	-- an option may belong to ANOTHER module (`opt.module`), built against
	-- that module and its settings; `include` lays out another module's
	-- options in place (all of them, its headers as subheaders, or only
	-- `keys`, in their order, with inline rows between), under the tab's
	-- area switch (`area`, a key of this page's module: the rows indented
	-- one step and live only while it is on). Here the option's setting is
	-- filled in and its row queued on the tab; MakeRows makes it.
	local function Build(owner, ownerDb, opt, area)
		if not sec then
			sec = NewSection(page, "General")
		end
		if builders[opt.type] and opt.key and ownerDb[opt.key] == nil then
			ownerDb[opt.key] = owner.defaults[opt.key]
		end
		if opt.key and owner == module and not page.anchors[opt.key] then
			page.anchors[opt.key] = { sec = sec, y = sec.plannedY or sec.y }
		end
		Queue(sec, { owner, ownerDb, opt, area }, MakeOption, ROW_HEIGHTS[opt.type] or 0)
	end
	for _, opt in ipairs(module.options) do
		if opt.type == "header" then
			sec = NewSection(page, opt.name)
		elseif opt.type == "include" then
			local inc = MelloUI:GetModule(opt.module)
			if inc then
				local incDb = MelloUI:GetModuleDB(inc.name)
				local area = nil
				if opt.area then
					local o = OptionOf(module, opt.area)
					area = { db = db, key = opt.area, name = o and o.name or opt.area }
				end
				if opt.keys then
					for _, entry in ipairs(opt.keys) do
						local sub = type(entry) == "table" and entry or OptionOf(inc, entry)
						if sub then
							Build(inc, incDb, sub, sub.type ~= "subheader" and area or nil)
						end
					end
				else
					for _, sub in ipairs(inc.options) do
						if sub.type == "header" then
							if not opt.flat then
								Build(inc, incDb, { type = "subheader", name = sub.name })
							end
						else
							Build(inc, incDb, sub, area)
						end
					end
				end
			end
		elseif opt.module then
			local owner = MelloUI:GetModule(opt.module)
			if owner then
				Build(owner, MelloUI:GetModuleDB(owner.name), opt)
			end
		else
			Build(module, db, opt)
		end
	end
	if #page.sections == 0 then
		sec = NewSection(page, "Options")
		SectionBox(sec)
		local fs = Text(sec, "GameFontDisable", "This module has no options. The switch above is all there is to it.")
		fs:SetPoint("TOPLEFT", 14, -8)
		sec.y = 30
	end
	-- the tabs, and the first tab's rows down to the bottom of the view
	-- (page:Select)
	page:Finish()
	return page
end

--------------------------------------------------------------------------------
-- Home page (the approved sketch of 2026-09-24): the header with the whole
-- logo and the Tutorial button; one section in two columns -- What's new on
-- the left (this version's changes, the older ones behind Earlier versions),
-- Your setup on the right (the profile, Kit Colours, the screen, MelloUI's
-- state, the installer) -- and Help under both, full width. The header and
-- both cards are made in the click frame; Help is one job for the worker
-- from the next frame on, its height planned so the page does not jump.
--------------------------------------------------------------------------------

-- (what the rest of the file uses of it; the block keeps its helpers to
-- itself: the file is near Lua's limit of 200 locals in one function)
local BuildHomePage, ConfirmLoadProfile, FillProfileNames, DynamicClick, InstallClick
do
local HOME_GAP = 10       -- between the two cards, and above Help
local CARD_PAD = 12       -- a card's texts inside its box
local CARD_ROW = 30       -- a Your setup row
local SETUP_VALUE = 100   -- where a Your setup row's value starts
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
	change = "Dynamic UI Modification: the Kit Colours and the rest of the reskin's look, chosen on the interface itself. Closes this window while you pick.",
	changeOff = "Switch on the painted kit reskin first (UI Modifications, General): the Kit Colours are the reskin's.",
	fit = "Mello's Edit Mode layout was fitted to another screen size or UI scale. The installer fits it to this one, and you can go back right after.",
	install = "The installer: a setup for the whole interface in a few steps, fitted to this screen. Closes this window while it runs.",
	revert = "Back to how MelloUI was before the installer ran (the 'Before install' profile): your settings, and Edit Mode's layouts if the installer changed them. Asks first.",
}
local HELP_NOTE = "A copy of your settings is kept in hidden account macros and brings them back if the saved settings ever go missing; /mello status shows both. The voice pack (MelloUI_VoiceOverData) is a separate download from the releases page and goes next to the MelloUI folder."

-- This frame's rows counted as spent: a page's first open whose own parts
-- are this frame's work (Home's header and cards), so the worker starts on
-- its jobs the next frame, never in the click frame
local function RowsDoneThisFrame()
	W.RowBudget.Spent(BUILD_BUDGET)
end

local function VoicePackInstalled()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		for _, name in ipairs({ "MelloUI_VoiceOverData", "AI_VoiceOverData_Forever", "AI_VoiceOverData_Vanilla" }) do
			local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
			if ok and loaded then
				return true
			end
		end
	end
	return false
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

-- the Kit Colours look in use, by its label (Dynamic UI Modification's)
local function KitColoursLabel()
	local K = MelloUI.Kit
	if not (K and K.BorderValue and type(K.colourLooks) == "table") then
		return "-"
	end
	local value = K:BorderValue("colours")
	for _, look in ipairs(K.colourLooks) do
		if look.value == value then
			return look.label or tostring(value)
		end
	end
	return tostring(value)
end

-- "3440 × 1440 (21:9)": Core's one formatter (MelloUI:ScreenText, shared
-- with the installer; made again only when the size changes), "-" while the
-- client does not say
local function ScreenText()
	return (MelloUI:ScreenText()) or "-"
end

-- Fit to this screen is offered when Mello's layout went in fitted to a size
-- (UI units, UIModifications.layoutFitFor, written by the installer) the
-- screen no longer has: another resolution or UI scale
local function FitDue()
	local db = MelloUI:GetModuleDB("UIModifications")
	local fitFor = db and db.layoutFitFor
	if type(fitFor) ~= "string" then
		return false
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
-- for Home's Profile dropdown and the Profiles page's Load button, defined
-- the first time it is asked (not at load). Accepted, it does what Load
-- always did. The typed /mello profile load stays without a question.
local function LoadAccepted(_, name)
	if type(name) ~= "string" then
		return
	end
	if MelloUI:LoadProfile(name) then
		MelloUI:Print("Profile '%s' loaded.", name)
	end
	MelloUI:RefreshConfig()
end
function ConfirmLoadProfile(name)
	if type(name) ~= "string" or name == "" or type(StaticPopupDialogs) ~= "table" then
		return
	end
	if not StaticPopupDialogs.MELLOUI_LOAD_PROFILE then
		StaticPopupDialogs.MELLOUI_LOAD_PROFILE = {
			text = "Load the profile '%s'? Your current settings are replaced; save them as a profile first to keep them.",
			button1 = "Load",
			button2 = "Cancel",
			OnAccept = LoadAccepted,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
	end
	StaticPopup_Show("MELLOUI_LOAD_PROFILE", name, nil, name)
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
	if type(StaticPopupDialogs) ~= "table" then
		return
	end
	if not StaticPopupDialogs.MELLOUI_REVERT_SETUP then
		StaticPopupDialogs.MELLOUI_REVERT_SETUP = {
			text = "Go back to how MelloUI was before the installer ran ('Before install')? Your settings return to what they were then, and Edit Mode's layouts too if the installer changed them.",
			button1 = "Go back",
			button2 = "Cancel",
			OnAccept = RevertAccepted,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
	end
	StaticPopup_Show("MELLOUI_REVERT_SETUP")
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
-- Dynamic UI Modification (user, 2026-09-23/24): the look of the whole
-- reskin, the one place it is chosen -- borders, Kit Colours, parchment,
-- every background and backdrop, picked on the interface itself with
-- previews (Modules/DynamicUI.lua); it closes this window. The top bar's
-- button, and Your setup's Change... by the Kit Colours (user, 2026-09-25:
-- Home shows them, Dynamic UI stays the one place to change them).
DynamicClick = Shared("OnClick on the configurator's Dynamic UI Modification", function()
	if MelloUI.StartDynamicUI then
		MelloUI:StartDynamicUI()
	end
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

-- a Home card: the L1 box with the kit (CT2: single rail and list-box stone,
-- its rule laying the palette's inner panel over the stone, 2e), a palette
-- box without it (the inner panel inside a border line)
local function HomeCard(sec, width)
	local card
	if KIT then
		card = CreateFrame("Frame", nil, sec)
		-- (one level under the card, so its own texts stay above the stone)
		SKIN:Replace(SKIN:Anchor(card), { as = "Professions-background-summarylist", rect = card, parent = card, level = -1 })
	else
		card = W.Box(sec, C.band, C.line, 1)
	end
	card:SetWidth(width)
	card.w = width
	return card
end

-- a card's heading: SH3 (the header plate, the text past its gem cap) with
-- the kit, gold text over a line without it
local function CardHeading(card, text)
	local head = CreateFrame("Frame", nil, card)
	head:SetHeight(ROW_HEIGHT - 6)
	head:SetPoint("TOPLEFT", card, "TOPLEFT", SEC_INSET, -SEC_INSET)
	head:SetPoint("TOPRIGHT", card, "TOPRIGHT", -SEC_INSET, -SEC_INSET)
	head.label = Text(head, "GameFontNormal", text, C.accent)
	if KIT then
		SKIN:Replace(SKIN:Anchor(head), { as = "GuildFrame-Header", rect = head })
		head.label:SetPoint("LEFT", 34, 0)
	else
		head.label:SetPoint("LEFT", 2, -3)
		local line = Solid(head, "ARTWORK", C.line, 1)
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT", 0, 0)
		line:SetPoint("BOTTOMRIGHT", 0, 0)
	end
	card.heading = head
	return head
end

-- one version's changes in the What's new card from `y` down, at the card's
-- own width: its number, then a line per change; the y under it. Each text
-- is kept in order in `card.items` (a line with its dot, `melloDot`), so a
-- font change can place them again (NewsLay).
local function AddVersion(card, entry, y)
	local items = card.items
	local head = Text(card, "GameFontNormal", "Version " .. entry.version, C.accent)
	head:SetPoint("TOPLEFT", CARD_PAD, -y)
	items[#items + 1] = head
	y = y + 22
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
	card.textY = AddVersion(card, CHANGELOG[1], CARD_HEAD)
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
local SETUP_ROWS = { "profile", "colours", "screen", "fit", "mello", "voice", "installer" }
local SETUP_LABELS = { profile = "Profile", colours = "Kit Colours", screen = "Screen", mello = "MelloUI",
	voice = "Voice pack", installer = "Installer" }
local SETUP_VALUES = { "colours", "screen", "mello", "voice" }

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
	-- the Kit Colours, read only, and Change... to Dynamic UI (the one place to change them)
	local change = W.Button(rows.colours, "Change…", 90, SKIN, { onClick = DynamicClick })
	change:SetPoint("RIGHT", -CARD_PAD, 0)
	rows.colours.value:SetPoint("RIGHT", change, "LEFT", -8, 0)
	HomeTip(change, "Kit Colours", HOME_TIPS.change)
	card.change = change
	-- the screen, and Fit to this screen when the layout was fitted to another
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
-- only then), the Kit Colours' label and whether Dynamic UI can open, the
-- screen, the modules on, the voice pack, the installer's buttons. True
-- when the card's height changed (a row came or went).
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
	rows.colours.value:SetText(KitColoursLabel())
	local K = MelloUI.Kit
	local canChange = (K and K.IsOn and K:IsOn("dynamicui")) and true or false
	card.change:SetEnabled(canChange)
	card.change.melloTipBody = canChange and HOME_TIPS.change or HOME_TIPS.changeOff
	rows.screen.value:SetText(ScreenText())
	local on, total = ModulesOn()
	rows.mello.value:SetText(string.format("%s, %d of %d modules on", tostring(MelloUI.version), on, total))
	rows.voice.value:SetText(VoicePackInstalled() and "installed" or "not installed (the link is under Help)")
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
	sec.needsBox = nil   -- (each card has its own box)
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
end   -- (the Home block)

--------------------------------------------------------------------------------
-- Profiles page
--------------------------------------------------------------------------------

-- the profiles' names, sorted, in a list of their own (the slash command's)
local function ProfileNames()
	return FillProfileNames({})
end

-- (what the rest of the file uses of the Profiles block)
local RefreshProfilesPage, BuildProfilesPage
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

-- a profile's row: a frame, four game buttons, two texts (made once, kept)
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
	row.default = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.default:SetSize(100, 22)
	row.default:SetPoint("LEFT", row.load, "RIGHT", 4, 0)
	row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.delete:SetSize(60, 22)
	row.delete:SetPoint("LEFT", row.default, "RIGHT", 4, 0)
	row.delete:SetText("Delete")
	row.share = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.share:SetSize(60, 22)
	row.share:SetPoint("LEFT", row.delete, "RIGHT", 4, 0)
	row.share:SetText("Share")
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
	sec:Finish()
	if page.current == sec then
		PageHeight(page, sec)
	end
end

function BuildProfilesPage(width)
	local page = NewPage("Profiles", width)
	BuildPageHeader(page, PROFILES_META.icon, PROFILES_META.title, PROFILES_META.flavour, nil)
	local sec = NewSection(page, "Profiles")
	SectionBox(sec)
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
	sec.save = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
	sec.save:SetSize(150, 22)
	sec.save:SetPoint("LEFT", sec.nameBox, "RIGHT", 8, 0)
	sec.save:SetText("Save current as")
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
	page:Finish()
	return page
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
-- Escape, the open and close sounds, the look switch
local SHELL_OPTS = { area = "config", ring = { at = "top", texture = LOGO, scale = CREST_SCALE }, plate = "crest",
	title = "MelloUI", plateWidth = 200, escape = true, grabBottom = BAR_TOP, fit = true, sounds = true,
	mover = { key = "MelloUIConfigFrame", plainDrag = "always" } }

-- The side list's groups, in order (the approved sketch's names: a design
-- constant, user 2026-09-25). Home and Profiles, the configurator's own pages,
-- stand first and last with no header. Every module whose registry `group`
-- names one of these gets an entry there, by its `navOrder`, then its place
-- in the registry: a module shown here is a page; a hidden one a shortcut
-- into UI Modifications when that has a qol_<Name> switch for it (the other
-- folded features stay on UI Modifications' tabs only).
local NAV_GROUPS = { "The look", "Quests and travel", "Chat and sound", "Frames and bars" }

-- Unlock the Windows, Auto Snapping and Reset positions while UI
-- Modifications is off (its mover provider rests then): dimmed and
-- disabled, their tooltips saying so (the gated-row rule of the rows)
local GATE_NOTE = "Switch on UI Modifications first."
local LAYOUT_DIM = 0.4

-- The wide window (user, 2026-09-25): UI Modifications' tabs, measured at the first
-- open at the Font Style in use as page:Finish lays them (a tab's width
-- less the 6 px the next one overlaps). One row of a section on the 1000
-- wide window holds them while the sum is this or less (its width less the
-- last tab's overlap); over it the window is WIDE_WIDTH wide, the page
-- area taking the 80. One tab made for the measure, kept hidden.
local TAB_ROW_ROOM = WINDOW_WIDTH - PAGE_LEFT + PAGE_RIGHT - PAD * 2 - 6
local function TabRowFits(parent)
	local um = MelloUI.modules.UIModifications
	if not (um and type(um.options) == "table") then
		return true
	end
	local tab = CreateFrame("Button", nil, parent, "PanelTopTabButtonTemplate")
	tab:Hide()
	local sum = 0
	for _, opt in ipairs(um.options) do
		if opt.type == "header" then
			tab:SetText(opt.name)
			PanelTemplates_TabResize(tab, 8)
			sum = sum + (Num(tab:GetWidth()) or 0) - 6
		end
	end
	parent.tabRowWidth = sum
	return sum <= TAB_ROW_ROOM
end

-- the side list's entries of a group: by navOrder, then the registry's order
local function NavOrder(a, b)
	if a.order ~= b.order then
		return a.order < b.order
	end
	return a.at < b.at
end

-- The side list's groups from the registry (made once, at the first open)
local function NavGroups()
	local switches = {}
	local um = MelloUI.modules.UIModifications
	if um and type(um.options) == "table" then
		for _, opt in ipairs(um.options) do
			if opt.key and not opt.module then
				switches[opt.key] = true
			end
		end
	end
	local byGroup = {}
	for i, module in ipairs(MelloUI:ModulesInOrder()) do
		local group = module.group
		local shortcut = module.hidden and switches["qol_" .. module.name] and ("qol_" .. module.name) or nil
		if group and (shortcut or not module.hidden) then
			local icon, flavour = Meta(module)
			local list = byGroup[group] or {}
			byGroup[group] = list
			list[#list + 1] = { key = module.name, text = module.title, icon = icon, tip = flavour, module = true,
				shortcut = shortcut, order = tonumber(module.navOrder) or math.huge, at = i }
		end
	end
	local groups = { { key = "Home", entries = { { key = "Home", text = "Home", icon = LOGO, tip = HOME_FLAVOUR } } } }
	for _, name in ipairs(NAV_GROUPS) do
		local list = byGroup[name]
		if list then
			table.sort(list, NavOrder)
			groups[#groups + 1] = { key = name, title = name, collapsible = true, entries = list }
		end
	end
	groups[#groups + 1] = { key = "Profiles", entries = { { key = "Profiles", text = "Profiles", icon = PROFILES_META.icon,
		tip = PROFILES_META.flavour } } }
	return groups
end

-- the side list's icon: the widgets' framed icon, with the kit the rim every
-- window's buttons wear (the Button Border, as the old icon strip's)
local function NavIcon(row, size, skin)
	return W.IconBox(row, size, nil, skin)
end

-- The side list's states: a module that is off shows it on its icon
local function RefreshNav()
	local rail = window.rail
	for key, entry in pairs(window.navEntries) do
		if entry.module then
			rail:SetState(key, not MelloUI:IsModuleEnabled(key) and "off" or nil)
		end
	end
	window.navStale = nil
end

-- The Layout group as UI Modifications is: its switches' values, and dimmed
-- and disabled while the module is off
local function RefreshLayout()
	local on = MelloUI:IsModuleEnabled("UIModifications") and true or false
	local parts = window.parts
	window.layoutGated = not on
	parts.layout:SetAlpha(on and 1 or LAYOUT_DIM)
	parts.unlock:SetEnabled(on)
	parts.snap:SetEnabled(on)
	parts.reset:SetEnabled(on)
	parts.unlock:Refresh()
	parts.snap:Refresh()
end

-- The side list's marker on what is shown: the page's own entry; on UI
-- Modifications the shortcut clicked last while its tab is the one open (a
-- tab changed by hand, `byHand`, moves it to UI Modifications' own entry);
-- none for a page with no entry (/mello characterpanel)
function NavFollow(byHand, instant)
	if not window then
		return
	end
	if byHand then
		window.shortcut = nil
	end
	local key = currentPage
	local sc = window.shortcut
	if sc and key == "UIModifications" then
		local page = pages.UIModifications
		local entry = window.navEntries[sc]
		local at = page and entry and page.anchors and page.anchors[entry.shortcut]
		if at and page.current == at.sec then
			key = sc
		end
	end
	local rail = window.rail
	rail:Select(key and rail.rows[key] and key or nil, instant)
end

-- A shortcut (Dark Mode, Fonts, Chat ...: a feature folded into UI
-- Modifications): UI Modifications on the tab holding its switch, scrolled
-- to it (page:Reveal). From another page, the page comes in already there
-- (one motion: its own fade); on show already, the tab cross-fades and the
-- page glides there. (On show means the open window's pager shows this
-- look's page: a window just opened, `instant`, always goes through
-- SelectPage, for the page's Refresh and the set of the look in use.)
local function OpenShortcut(key, instant)
	local entry = window.navEntries[key]
	if not (entry and entry.shortcut) then
		return
	end
	window.shortcut = key
	local ui = pages.UIModifications
	local onShow = not instant and ui ~= nil and window.pager:Current() == ui
	if not onShow then
		SelectPage("UIModifications", instant)
	end
	local page = pages.UIModifications
	if page and page:Reveal(entry.shortcut, not onShow, onShow) then
		NavFollow(false, instant)
	end
end

-- a side-list entry clicked (the rail's onSelect)
local function NavClick(_, key, entry)
	if entry.shortcut then
		if not (currentPage == "UIModifications" and window.shortcut == key) then
			MelloUI:PlayUISound("page")
		end
		OpenShortcut(key)
		return
	end
	if currentPage ~= key or window.shortcut then
		MelloUI:PlayUISound("page")
	end
	window.shortcut = nil
	SelectPage(key)
end

-- the top bar's tooltips (one handler; its texts read from the control:
-- `melloTipTitle`, `melloTipBody`, and `melloGated` for the Layout group,
-- whose tooltip says what wakes it while it sleeps), painted by the widgets'
-- one tooltip (W.ShowTooltip)
local BarEnter = Shared("OnEnter on the configurator's top bar", function(self)
	local body = self.melloTipBody
	if self.melloGated and window.layoutGated then
		body = GATE_NOTE
	end
	-- (under the control, over the page: the bar runs along the window's top)
	W.ShowTooltip(self, self.melloTipTitle or "", body, nil, "ANCHOR_BOTTOM")
end, "script")
local function BarTip(control, title, body, gated)
	control.melloTipTitle, control.melloTipBody, control.melloGated = title, body, gated
	Perf.HookScript(control, "OnEnter", BarEnter)
	Perf.HookScript(control, "OnLeave", W.TipLeave)
end

-- Reset positions: UI Modifications' one reset (every mover entry, the
-- store, the plain-window drags, the UI-scale put-back; open windows closed)
local ResetClick = Shared("OnClick on the configurator's Reset positions", function()
	local um = MelloUI:GetModule("UIModifications")
	if um and um.ResetPositions then
		um.ResetPositions()
	end
	MelloUI:RefreshConfig()
end, "script")

-- (Dynamic UI Modification and Install... share Home's handlers:
-- DynamicClick, InstallClick)

local CloseClick = Shared("OnClick on the configurator's close button", function()
	window:Hide()
end, "script")

-- On every show: the side list's states (marked stale while it was closed)
-- and the Layout group as the settings are now; the page on show is brought
-- in line by SelectPage, which every open calls. (Its own script, set before
-- the shell's hooks: the shell's look check, fit and sound come after it.)
local Window_OnShow = Shared("OnShow on the configurator", function()
	if window.navStale then
		RefreshNav()
	end
	RefreshLayout()
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

-- the top bar's dark panel with the kit (the eye-strain panel over the page
-- stone, WINDOW-RULES 2e): a region of the WINDOW over its stone, so it never
-- ties with the bar's controls (frames above it) and the outer rail stays in
-- front (made at the kit look's first switch on)
local function DressBar(K, bar)
	window.barDim = K:StoneDim(window, { rect = bar, layer = "BORDER", sublevel = 1 })
end

-- the bus, taken at the first open (owner "Config"): each returns at once
-- while the window is closed, after marking what its next show brings in line
local function Config_OnSetting(module, key)
	if module == "UIModifications" and (key == "unlock" or key == "autoSnap") and window:IsShown() then
		RefreshLayout()
	end
end
local function Config_OnModule(name, enabled)
	if not window:IsShown() then
		window.navStale = true
		return
	end
	if window.navEntries[name] then
		window.rail:SetState(name, not enabled and "off" or nil)
	end
	if name == "UIModifications" then
		RefreshLayout()
	end
end
-- 'palette' (the palette or the Kit Colours changed; unlike the painted
-- regions' own listener, a same-table Fire counts too: a Kit Colours change
-- writes Your setup's label again, and the Profiles page's colour codes are
-- text, not painted regions): the page on show refreshed while the window
-- is shown; a closed window's next show refreshes its page anyway
local function Config_OnPalette()
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
-- made with the window (MelloUI:ConfigTour)
local function TourSelect(name)
	SelectPage(name, true)
end
local function TourPage(name)
	return pages[name]
end
local function TourPart(name)
	return window.parts[name]
end
local function TourNav(key)
	return window.rail:Reveal(key)
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

local function CreateWindow()
	if window then
		return
	end
	local Kit = MelloUI.Kit   -- (looked up now: this file loads before Kit.lua and KitWindow.lua)
	window = CreateFrame("Frame", "MelloUIConfigFrame", UIParent)
	window:Hide()
	local width = TabRowFits(window) and WINDOW_WIDTH or WIDE_WIDTH
	window:SetSize(width, WINDOW_HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window.navStale = true
	-- (its own show before the shell's hooks: SetScript drops hooks)
	Perf.SetScript(window, "OnShow", Window_OnShow)
	shell = Kit:OwnWindow(window, SHELL_OPTS)
	window.shell = shell
	KIT, SKIN = shell.kit and Kit or nil, shell.kit and shell or nil
	pages, building = pagesBy[shell.kit], buildingBy[shell.kit]
	local barOpts = { skin = shell }   -- (the shell's parts switch with it)

	-- The top bar, under the drag strip
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

	-- Layout (user, 2026-09-23: "Unlock the Window, Reset Position and Turn
	-- off Auto Snapping should be placed along with as the main options on
	-- top of that window"): UI Modifications' settings, on the left
	local texts = (MelloUI:GetModule("UIModifications") or {}).placementTexts or {}
	local layout = CreateFrame("Frame", nil, bar)
	local head = Text(layout, "GameFontNormal", "Layout", C.accent)
	head:SetPoint("LEFT", bar, "LEFT", 12, 0)
	local function LayoutSwitch(key, fallback, anchor, gap)
		local t = texts[key]
		local sw = W.Switch(layout, function()
			local db = MelloUI:GetModuleDB("UIModifications")
			if key == "autoSnap" then
				return not (db and db.autoSnap == false)
			end
			return db and db[key]
		end, function(value)
			MelloUI:NotifySettingChanged("UIModifications", key, value)
			MelloUI:RefreshConfig()
		end, barOpts)
		sw:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
		local label = Text(layout, "GameFontHighlight", (t and t.name) or fallback, C.text)
		label:SetPoint("LEFT", sw, "RIGHT", 2, 0)
		BarTip(sw, (t and t.name) or fallback, t and t.desc, true)
		return sw, label
	end
	local unlock, unlockText = LayoutSwitch("unlock", "Unlock the Windows", head, 12)
	local snap, snapText = LayoutSwitch("autoSnap", "Auto Snapping", unlockText, 14)
	local resetName = (texts.reset and texts.reset.name) or "Reset positions"
	local reset = W.Button(layout, resetName, 120, shell, { onClick = ResetClick })
	reset:SetPoint("LEFT", snapText, "RIGHT", 14, 0)
	BarTip(reset, resetName, texts.reset and texts.reset.desc, true)
	layout:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	layout:SetPoint("BOTTOMRIGHT", reset, "BOTTOMRIGHT", 8, -6)

	-- Install..., Dynamic UI Modification and close, on the right
	local close = W.CloseButton(bar, shell)
	close:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
	Perf.SetScript(close, "OnClick", CloseClick)
	local dynamic = W.Button(bar, "Dynamic UI Modification", 190, shell, { onClick = DynamicClick })
	dynamic:SetPoint("RIGHT", close, "LEFT", -8, 0)
	BarTip(dynamic, "Dynamic UI Modification", "The look of the reskin, all in one place: the borders and Kit Colours of every "
		.. "window, the parchment sheets, and the backgrounds of the action bars, micro menu, bag bar, bags, character window, "
		.. "minimap and professions, chosen on the interface itself with a picture of each choice. Closes the configurator "
		.. "while you pick.")
	-- (the red plate with a gold label and a thin gold outline: the approved
	-- "gold trim"; there while the installer is)
	local install = W.Button(bar, "Install…", 110, shell, { gold = true, onClick = InstallClick })
	install:SetPoint("RIGHT", dynamic, "LEFT", -8, 0)
	install:SetShown(type(MelloUI.OpenInstaller) == "function")
	BarTip(install, "Install…", "The installer: a setup for the whole interface in a few steps, fitted to this screen. "
		.. "Closes the configurator while it runs.")

	-- The side list (W.NavRail, from the registry): the pages and the
	-- shortcuts by group, the page on show marked. Its rows count against
	-- the frame's one budget of rows: the page's rows in view made in the
	-- same frame get what it leaves (BeginRows / EndRows)
	local rail = W.NavRail(window, { width = NAV_WIDTH, iconMaker = NavIcon, onSelect = NavClick, skin = shell })
	rail.box:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE, BODY_TOP)
	rail.box:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", EDGE, EDGE)
	window.rail = rail
	local groups = NavGroups()
	-- (each page's place in the list: the side a page slides in from)
	window.navEntries, window.pageOrder = {}, {}
	local n = 0
	for _, g in ipairs(groups) do
		for _, e in ipairs(g.entries) do
			window.navEntries[e.key] = e
			if not e.shortcut then
				n = n + 1
				window.pageOrder[e.key] = n
			end
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
	window.pageWidth = width - PAGE_LEFT + PAGE_RIGHT

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

	-- the parts the tour points at, and the tour's one table
	window.parts = { title = shell.title, plate = shell.plate, crest = shell.crest, topBar = bar, layout = layout,
		unlock = unlock, snap = snap, reset = reset, install = install, dynamic = dynamic, close = close, nav = rail.box }
	window.tour = { window = window, pager = pager, select = TourSelect, page = TourPage, part = TourPart, navEntry = TourNav,
		scrollTo = TourScrollTo }

	-- the look switched with the window open (the shell's 'look:config')
	shell:OnKit(Config_OnKit)
	-- the bus: the Layout group's switches follow their settings however
	-- they change (the unlock banner's "click here to lock them" too); the
	-- side list's states and the Layout group's gate follow the modules; the
	-- palette's colour codes and the Kit Colours' label follow the palette;
	-- the tab rows follow the fonts
	MelloUI:On("setting", Config_OnSetting, "Config")
	MelloUI:On("module", Config_OnModule, "Config")
	MelloUI:On("palette", Config_OnPalette, "Config")
	MelloUI:On("fonts", Config_OnFonts, "Config")
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
		local module = MelloUI.modules[name]
		if not module then
			return nil
		end
		page = BuildModulePage(module, window.pageWidth)
	end
	pages[name] = page
	return page
end

-- the side a page comes in from: +1 (from the right) for a page further
-- along the list, -1 for one before it, 0 for a page with no place in it (a
-- hidden module's own page, /mello characterpanel)
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
-- budget for.)
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
	page:Refresh()
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
	RefreshLayout()
	local page = currentPage and pages[currentPage]
	if page then
		page:Refresh()
	end
end

function MelloUI:BuildConfig()
	-- Nothing to register up front; the window is built on first use.
end

-- /mello [page]: a module's page (a hidden module with a side-list entry:
-- its shortcut, /mello fonts), Profiles, else the page shown last (Home the
-- first time); /mello with the window open closes it
function MelloUI:OpenConfig(moduleName)
	CreateWindow()
	local module = ModuleByName(moduleName)
	local target = module and module.name or (moduleName and moduleName:lower() == "profiles" and "Profiles") or nil
	local wasShown = window:IsShown()
	if wasShown and not target then
		window:Hide()
		return
	end
	opening = true
	window:Show()
	opening = false
	-- (a window just opened shows its page at once: no switch to see)
	local entry = target and window.navEntries[target]
	if entry and entry.shortcut then
		OpenShortcut(target, not wasShown)
		return
	end
	if target then
		window.shortcut = nil
	end
	SelectPage(target or currentPage or "Home", not wasShown)
end

-- The window's parts for the guided tour (Core/Tutorial.lua), one table made
-- with the window:
--   c.window, c.pager (its `cf` the switch's timings)
--   c.select(name)    SelectPage at once (a tip never anchors to a page still
--                     sliding in)
--   c.page(name)      the built page of the look in use, or nil
--   c.part(name)      "title" (the plate's FontString), "plate", "crest",
--                     "topBar", "layout", "unlock", "snap", "reset", "install",
--                     "dynamic", "close", "nav"
--   c.navEntry(key)   the side-list row: its group unfolded, the list jumped
--                     to it
--   c.scrollTo(part)  the page on show jumped so the part sits 60 below its
--                     top; a part outside it moves nothing
function MelloUI:ConfigTour()
	CreateWindow()
	return window.tour
end

--------------------------------------------------------------------------------
-- Game menu button (Escape > MelloUI), in its own section above Logout.
--------------------------------------------------------------------------------

local gameMenuHooked = false

local function AddGameMenuButton(menu)
	local button = menu:AddButton("MelloUI", function()
		MelloUI:PlayUISound("menu_button")
		HideUIPanel(menu)
		MelloUI:OpenConfig()
	end)
	local logoutText = LOG_OUT
	if menu.GetLogoutText then
		local ok, text = pcall(menu.GetLogoutText, menu)
		if ok and text then
			logoutText = text
		end
	end
	local logoutIndex
	for _, other in ipairs(menu.buttons or {}) do
		if other ~= button and other:GetText() == logoutText then
			logoutIndex = other.layoutIndex
			break
		end
	end
	if logoutIndex then
		for _, other in ipairs(menu.buttons) do
			if other ~= button and other.layoutIndex and other.layoutIndex >= logoutIndex then
				other.layoutIndex = other.layoutIndex + 1
			end
		end
		button.layoutIndex = logoutIndex
		button.topPadding = 20
	end
	if menu.MarkDirty then
		menu:MarkDirty()
	end
end

local function HookGameMenu()
	if gameMenuHooked or not GameMenuFrame then
		return
	end
	if GameMenuFrame.InitButtons then
		gameMenuHooked = true
		hooksecurefunc(GameMenuFrame, "InitButtons", AddGameMenuButton)
	end
end

HookGameMenu()
if not gameMenuHooked then
	local waiter = CreateFrame("Frame")
	waiter:RegisterEvent("PLAYER_LOGIN")
	Perf.SetScript(waiter, "OnEvent", function(self)
		HookGameMenu()
		self:UnregisterAllEvents()
	end)
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

SLASH_MELLOUI1 = "/mello"
SLASH_MELLOUI2 = "/melloui"
SlashCmdList.MELLOUI = function(msg)
	local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	msg = raw:lower()
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")
	-- profile names keep their case (a name saved from the window is
	-- stored as typed; lowercasing here found none of them)
	local rawRest = raw:match("^%S+%s*(.-)$") or ""

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
	elseif cmd == "status" then
		local green, red, yellow = "|cff40ff40", "|cffff4040", "|cffffff00"
		MelloUI:Print("Status (v%s):", tostring(MelloUI.version))
		if not MelloUI.dbIsTemporary then
			print(string.format("   Saved variables: %sloaded by the client|r (at %s)", green, tostring(MelloUI.savedVariablesStage or "?")))
		else
			print(string.format("   Saved variables: %snot loaded yet|r (still waiting)", red))
		end
		local source
		if MelloUI.restoredFromBackup then
			source = string.format("%smacro backup|r (%d values restored at %s)", yellow,
				tonumber(MelloUI.backupRestoredCount) or 0, tostring(MelloUI.backupRestoredStage or "?"))
		elseif not MelloUI.dbIsTemporary then
			source = green .. "saved variables|r"
		else
			source = red .. "defaults|r (nothing to restore from)"
		end
		print("   Settings in use come from: " .. source)
		if type(MelloUI.GetBackupStatus) == "function" then
			local b = MelloUI:GetBackupStatus()
			if b.paused then
				print("   Macro backup: " .. yellow .. "PAUSED in Core/Backup.lua (nothing read or written)|r")
			elseif not b.available then
				print("   Macro backup: " .. red .. "macro API not available|r")
			else
				local when = b.lastWrite and date("%H:%M:%S", b.lastWrite) or "not yet this session"
				print(string.format("   Macro backup: %d macro(s), %d of %d characters, %s", b.chunks, b.length, b.capacity or 0,
					b.inSync and (green .. "in sync with current settings|r") or (yellow .. "differs from current settings|r")))
				print(string.format("   Last write: %s%s%s", when,
					b.lastReason and (" (" .. tostring(b.lastReason) .. ")") or "",
					b.pending and ", write scheduled" or (b.deferredForCombat and ", waiting for combat to end" or "")))
				if b.lastError then
					print("   Last error: " .. red .. tostring(b.lastError) .. "|r")
				end
			end
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
		print("   /mello cpu                 CPU time per handler (old; needs scriptProfile)")
		print("   /mello preload             how much of the artwork is preloaded")
		print("   /mello secrets             which secret-value tools this client has, and what a secret allows")
		print("   /mello auras               what this client's aura container offers (for MelloUI's own aura rows)")
	elseif cmd ~= "" and not ModuleByName(cmd) and cmd ~= "profiles" then
		MelloUI:Print("Unknown command or module '%s'. /mello help lists the commands, /mello list the modules.", cmd)
	else
		MelloUI:OpenConfig(cmd ~= "" and cmd or nil)
	end
end
