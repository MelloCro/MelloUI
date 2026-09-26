--------------------------------------------------------------------------------
-- MelloUI - Core
--
-- Module registry, saved variables and lifecycle.
--
-- A module is a plain table registered through MelloUI:RegisterModule(name, tbl).
-- Supported fields:
--   title            display name shown in the config panel
--   desc             tooltip / description text
--   defaults         table of default settings for the module
--   enabledByDefault boolean (default true)
--   options          declarative list used by Core/Config.lua to build controls
--   OnAddonLoaded(db) called at ADDON_LOADED (only if the module is enabled)
--   OnInit(db)       called once after saved variables are available
--   OnEnable(db)     called when the module is switched on (and at login if enabled)
--   OnDisable(db)    called when the module is switched off
--   applyWhenDisabled  true: OnDisable is called at start-up too when the
--                    module is off, for a module that drives others
--   OnSettingChanged(key, value, db)  called when one of its options changes
--   hidden           true: not listed in the configurator (driven by another
--                    module: the kit panels by Painted UI); /mello list shows it
--   important        true: the configurator's tile keeps a gold border, a glowing
--                    icon and an IMPORTANT badge (the UI Modifications entry)
--   keep             the settings that are this player's own, not choices
--                    (learned flight points, a borrowed game setting, a
--                    one-time flag): exact keys, or Lua patterns starting
--                    with ^. Profiles and share strings leave them out and
--                    loading one never touches them (IsPersonalKey below)
--   options entries may carry `module = "<name>"` (the option belongs to that
--   module: built against its settings) or be `{ type = "include", module = }`
--   (that module's whole option list laid out in place); a toggle with
--   `important = true` is drawn gold with an IMPORTANT hint
-- The registry's own fields (audit, 2026-09-24, rank 4: one place that says
-- what a module is, for the configurator, the installer and UI
-- Modifications). All optional, kept on the module as given. UI
-- Modifications builds its rows, the plain grabs and the switches' defaults
-- from `window` and `tweak` (UIModifications.lua's header); the
-- configurator reads `icon` and `flavour` (its tiles) and `group` and
-- `navOrder` (its side list); the installer reads `role`; `area` and the
-- window's `addon` and `firstOpen` are facts nothing reads yet:
--   icon             texture path (or file id) of its tile
--   flavour          one line under its title
--   group            the side-list group its entry sits in: "The look",
--                    "Quests and travel", "Chat and sound" or "Frames and
--                    bars" (Home and Profiles are the configurator's own
--                    pages). A module shown in the configurator is a page
--                    entry; a hidden one a shortcut to its qol_ switch on UI
--                    Modifications' tabs. No group: no entry (a folded
--                    feature is found on UI Modifications' tabs only)
--   navOrder         a number: its place in that group, 1 first; entries
--                    without one come after, in the order they registered
--   window           a window (or HUD part) the reskin dresses: { label, desc,
--                    tab = "Windows" | "HUD", order = n (rows with one lead
--                    their tab, lowest first), switch = "<UI Modifications
--                    setting>" (the row is that setting, not a module switch:
--                    the Quest Tracker's questTrackerKit), frames = { frame
--                    names }, addon = "Blizzard_..." (loaded on demand),
--                    plainGrab = true (a plain grab while the windows are
--                    unlocked), firstOpen = true (dressed on its first show),
--                    include = true | { keys } (its own options laid out
--                    under its row, indented and live only while it is on;
--                    { keys }: only those, in that order) }
--   tweak            a feature folded under UI Modifications: { label, desc,
--                    order = n (as window's), off = true (off until switched
--                    on), always = true (no switch: its rows each switch one
--                    thing) }
--   area             an own window's look switch: { key = "questTracker",
--                    follows = nil | "<module whose switch it follows>" }
--   role             what the installer's setups do with it: "core" (UI
--                    Modifications, the switchboard), "look" (restyles the
--                    game's art, fonts or sounds), "feature" (MelloUI's own
--                    tools), "adds" (adds information or automation to the
--                    game's UI without restyling it), "replaces" (replaces or
--                    restyles a game part). A hidden kit panel (it carries
--                    `window`) needs none: it is look.
-- One of the wrong type (or a role not in that list) goes to the error
-- handler and is left off the module; the module itself still registers.
-- MelloUI:ModulesInOrder() lists the modules in the order they registered.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local MelloUI = CreateFrame("Frame")
ns.MelloUI = MelloUI
_G.MelloUI = MelloUI

MelloUI.name = ADDON_NAME
MelloUI.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
MelloUI.modules = {}

--------------------------------------------------------------------------------
-- The palette (user, 2026-09-23: "a Color Palette that i would like us to hold
-- as a rule in this UI"; the hex of each is the colour of its swatch -- "match
-- the hex code with the actual color" -- not the label written under it).
-- Every colour MelloUI draws itself -- fills, lines, text, selection, hover --
-- comes from here; the painted kit art is tuned to sit with it. { r, g, b } in
-- 0..1. Contrast on mainWindow: text 8.0:1, selectedTrim 5.1:1, mutedText
-- 3.2:1 (large or bold labels only, never small body text).
--   mainWindow    #1F1B16  a window's ground
--   innerPanel    #11100D  a panel sunk into the window (lists, insets)
--   raisedPanel   #2E1F14  a panel standing out of it (cards, plates)
--   border        #3D342A  rules and plain borders
--   trim          #8D642F  ornamental trim
--   text          #C6AF85  body text
--   mutedText     #7F6846  secondary text: labels, hints
--   selectedTab   #4E1812  the selected tab or row
--   selectedTrim  #AE8546  the selected tab's trim, gold highlights, headings
--   hover         #5A3C24  what the pointer is over
--------------------------------------------------------------------------------
local function Hex(hex)
	return { tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255, hex = hex:sub(2) }
end
MelloUI.Palette = {
	mainWindow   = Hex("#1F1B16"),
	innerPanel   = Hex("#11100D"),
	raisedPanel  = Hex("#2E1F14"),
	border       = Hex("#3D342A"),
	trim         = Hex("#8D642F"),
	text         = Hex("#C6AF85"),
	mutedText    = Hex("#7F6846"),
	selectedTab  = Hex("#4E1812"),
	selectedTrim = Hex("#AE8546"),
	hover        = Hex("#5A3C24"),
}

-- A palette colour as a chat / font-string colour code: "|cffAE8546"
function MelloUI:PaletteCode(role)
	local c = self.Palette[role]
	return "|cff" .. (c and c.hex or "FFFFFF")
end
MelloUI.moduleOrder = {}

local DB_VERSION = 1

local DB_DEFAULTS = {
	version = DB_VERSION,
	enabled = {},   -- [moduleName] = boolean
	modules = {},   -- [moduleName] = { settings }
	profiles = {},  -- [name] = serialised settings (see Profiles below)
}

--------------------------------------------------------------------------------
-- Secret-safe reads: one set for the whole addon (audit, 2026-09-24: 59 files
-- carried their own Secret / IsSecret, in 4 bodies, and 11 their own Plain,
-- with 6 meanings). This client hands some values over SECRET
-- (issecretvalue): comparing one -- even with nil --, joining it into text or
-- doing arithmetic on it is refused, so each helper asks issecretvalue FIRST,
-- before any other test of the value. None of them makes a table.
-- A file binds the ones it needs once, at load, as upvalues (a call costs
-- what its own copy did):
--   local Secret = MelloUI.Safe.IsSecret
-- Core is first in the TOC, so Safe is always there; a test world that loads
-- a file without Core runs this block itself (wave 3, 2026-09-25: the
-- `MelloUI.Safe and ... or <stand-in>` bindings went with that).
--------------------------------------------------------------------------------

local Safe = {}
MelloUI.Safe = Safe

-- true when v is secret; always a boolean (false on a client without secrets)
function Safe.IsSecret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- v, or nil when v is secret (or nil)
function Safe.Value(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

-- v when it is a plain number, else nil (secret, nil or not a number)
function Safe.Number(v)
	if (issecretvalue and issecretvalue(v)) or type(v) ~= "number" then
		return nil
	end
	return v
end

-- v when it is a plain string, else nil (secret, nil or not a string)
function Safe.Text(v)
	if (issecretvalue and issecretvalue(v)) or type(v) ~= "string" then
		return nil
	end
	return v
end

-- a pcall's results, or nil when it raised or its first result is secret
local function Checked(ok, first, ...)
	if not ok or (issecretvalue and issecretvalue(first)) then
		return nil
	end
	return first, ...
end

-- obj:method(...) guarded: its results, or nil when obj has no such method,
-- the call raised or the first result is secret. Only the first is tested;
-- any further results are the caller's to test.
function Safe.Call(obj, method, ...)
	local fn = type(obj) == "table" and obj[method]
	if type(fn) ~= "function" then
		return nil
	end
	return Checked(pcall(fn, obj, ...))
end

-- The screen as a player names it: its size in pixels and its aspect ratio
-- ("32:9", "21:9", "16:9", "16:10", "3:2", "4:3", "5:4": the nearest one,
-- and no label when none is within 4 %, as a triple screen or a 32:10), from
-- GetPhysicalScreenSize read through Safe.Number. One helper for the
-- configurator's Your setup and the installer's Screen step. Returns width,
-- height, label (nil when none is close); nothing while the client does not
-- say. Makes no table.
function MelloUI:ScreenInfo()
	if not GetPhysicalScreenSize then
		return nil
	end
	local ok, w, h = pcall(GetPhysicalScreenSize)
	if not ok then
		return nil
	end
	w, h = Safe.Number(w), Safe.Number(h)
	if not (w and h and w > 0 and h > 0) then
		return nil
	end
	-- (the nearest ratio: each bound is half way between two neighbours;
	-- "21:9" as the screens sold under it measure, 2560 x 1080 and 3440 x
	-- 1440, about 2.37)
	local ratio = w / h
	local label, target
	if ratio >= 2.96 then
		label, target = "32:9", 32 / 9
	elseif ratio >= 2.07 then
		label, target = "21:9", 2.37
	elseif ratio >= 1.689 then
		label, target = "16:9", 16 / 9
	elseif ratio >= 1.55 then
		label, target = "16:10", 1.6
	elseif ratio >= 1.417 then
		label, target = "3:2", 1.5
	elseif ratio >= 1.29 then
		label, target = "4:3", 4 / 3
	else
		label, target = "5:4", 1.25
	end
	local off = ratio / target - 1
	if off > 0.04 or off < -0.04 then
		label = nil   -- (nothing close: no label rather than a wrong one)
	end
	return w, h, label
end

-- The screen as the texts show it: "3440 × 1440 (21:9)" (no label: the size
-- alone), and the aspect as a word ("21:9", else "2.39:1"); nil while
-- ScreenInfo says nothing. Made again only when the size changes: the one
-- formatter for the configurator's Your setup and the installer's lines.
do
	local memo = { w = false, h = false, text = nil, ratio = nil }
	function MelloUI:ScreenText()
		local w, h, label = self:ScreenInfo()
		if not w then
			return nil
		end
		if memo.w ~= w or memo.h ~= h then
			memo.w, memo.h = w, h
			local size = string.format("%d \195\151 %d", math.floor(w + 0.5), math.floor(h + 0.5))
			memo.text = label and (size .. " (" .. label .. ")") or size
			memo.ratio = label or string.format("%.2f:1", w / h)
		end
		return memo.text, memo.ratio
	end
end

-- Two reads MelloUI's own engines share (the installer, its window, the Edit
-- Mode layout; one reader each, plain functions a file binds once):
--   MelloUI.InCombat()      in combat (the game's lockdown)
--   MelloUI.EditModeOpen()  Edit Mode open, read only: its manager shown, or
--                           still active while a game panel hides it for a
--                           moment (its own flag: it leaves Edit Mode, and
--                           tells so, only on a real exit)
function MelloUI.InCombat()
	return InCombatLockdown and InCombatLockdown() and true or false
end

function MelloUI.EditModeOpen()
	local manager = EditModeManagerFrame
	if type(manager) ~= "table" or type(manager.IsShown) ~= "function" then
		return false
	end
	local active = manager.editModeActive
	if not Safe.IsSecret(active) and active == true then
		return true
	end
	local ok, shown = pcall(manager.IsShown, manager)
	if not ok or Safe.IsSecret(shown) then
		return false
	end
	return shown and true or false
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local PREFIX = "|cff9b8cffMello|rUI: "

-- Everything printed is also kept (the last LOG_MAX lines, colour codes
-- stripped) for the copy window: /mellolog shows it in a text box that can
-- be selected and copied, so a dump travels as text instead of screenshots.
local LOG_MAX = 2000
local log = {}

-- MelloUI.printHold: while this counter is above 0, printed lines go to the
-- log only (/mellolog), not to the chat. The installer holds them while it
-- applies a setup, so a new player's chat gets its one summary line instead
-- of each module's own ("Font Style: ...", "Custom Sounds switched on ...").
-- Whoever raises it lowers it again, also on an error.
MelloUI.printHold = 0

-- A secret value (this client) prints as "[secret]": a format with one
-- secret argument would make the whole message secret and unindexable.
local function Printable(v)
	if Safe.IsSecret(v) then
		return "[secret]"
	end
	return v
end

function MelloUI:Print(msg, ...)
	local n = select("#", ...)
	if n > 0 then
		local args = { ... }
		for i = 1, n do
			args[i] = Printable(args[i])
		end
		local ok, formatted = pcall(string.format, Printable(msg), unpack(args, 1, n))
		if ok then
			msg = formatted
		else
			-- a "[secret]" where a number was expected: the pieces, joined
			local parts = { tostring(Printable(msg)) }
			for i = 1, n do
				parts[#parts + 1] = tostring(args[i])
			end
			msg = table.concat(parts, " ")
		end
	end
	msg = tostring(Printable(msg))
	local hold = MelloUI.printHold
	if not (type(hold) == "number" and hold > 0) then
		print(PREFIX .. msg)
	end
	log[#log + 1] = (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	if #log > LOG_MAX then
		table.remove(log, 1)
	end
end

function MelloUI:ClearLog()
	wipe(log)
end

-- an error in a listener or a callback: to the game's error handler, and on
local function Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if type(handler) == "function" then
		handler(err)
	end
end

--------------------------------------------------------------------------------
-- The settings bus (audit, 2026-09-24, rank 5): one path for "this changed",
-- where files hooked MelloUI's own functions (NotifySettingChanged,
-- SetModuleEnabled, Kit.SetParchment: a hook runs for every setting of every
-- module and can never be taken off) or kept a listener list per subject.
--
--   MelloUI:On(topic, fn, owner)  fn(...) is called with what the topic is
--                                 fired with (not the topic). One listener per
--                                 owner and topic: On again with the same
--                                 owner replaces its fn where it stands.
--                                 owner defaults to fn. Listeners run in the
--                                 order they came.
--   MelloUI:Off(owner[, topic])   that owner's listeners, of one topic or all
--   MelloUI:Fire(topic, ...)      every listener of the topic, each in its own
--                                 pcall: one that raises goes to the error
--                                 handler and the others still run. No table
--                                 is made per Fire. One added during a Fire
--                                 first runs on the next; one taken off
--                                 during it is not called any more.
--   MelloUI:Batch(fn, ...)        fn(...), with the 'setting' Fires raised
--                                 meanwhile held and fired after it, one per
--                                 module and key (its last value), in the
--                                 order first raised; the settings backup is
--                                 scheduled once at the end, not per setting
--                                 (the installer's apply engine). Batches
--                                 nest. fn's results are returned; an error
--                                 in fn is raised again once the held Fires
--                                 went out.
-- Topics, with what they carry:
--   "setting"      moduleName, key, value  end of NotifySettingChanged
--   "module"       moduleName, enabled     end of SetModuleEnabled (not before
--                                          login's start-up: the flag only)
--   "restart"      -                       end of RestartModules
--   "look:<area>"  on                      an area's kit look switched
--   "cover"        area, on                Kit:Cover
--   "parchment"    area, on                Kit:SetParchment
--   "border"       kind                    a Button / window Border changed
--   "fonts"        -                       the Font Style or a face changed
--   "scale"        reason                  "uiscale" | "editmode" (Kit's watcher)
--   "editmode"     entering                Edit Mode entered (true) / left
--   "shell"        window                  a kit window shell was built
--   "palette"      -                       MelloUI.Palette or the Kit Colours changed
--                                          (fired after both are in place; a new
--                                          palette is a new table)
--   "column"       -                       the column under the minimap re-laid
--   "installer"    what, ...               the installer (Core/Installer.lua):
--                    "installed", setupKey, needsReload   a setup went in
--                    "countdown", seconds, paused, why    the Keep countdown
--                    "kept", needsReload                  Keep pressed
--                    "reverted", reason, reloadOwed       back to 'Before
--                                          install' (reason "button",
--                                          "timeout" or "error")
--                    "revertFailed", reason, why          it could not be
--                                          put back (the restore point stays)
--------------------------------------------------------------------------------

-- the settings backup through the bus's Batch: held there, scheduled once at
-- its end (set below)
local Backup

do
	local topics = {}   -- [topic] = { fn = {}, owner = {}, n = 0, depth = 0, dirty = false }
	local batch = 0     -- Batch depth
	local backupWanted = false

	-- the slots taken off during a Fire are false until it ends: then the
	-- list closes up, in order
	local function Compact(t)
		local fns, owners, j = t.fn, t.owner, 0
		for i = 1, t.n do
			local fn = fns[i]
			if fn then
				j = j + 1
				fns[j], owners[j] = fn, owners[i]
			end
		end
		for i = j + 1, t.n do
			fns[i], owners[i] = nil, nil
		end
		t.n, t.dirty = j, false
	end

	function MelloUI:On(topic, fn, owner)
		assert(topic ~= nil and type(fn) == "function", "MelloUI:On(topic, fn, owner) needs a topic and a function")
		if owner == nil then
			owner = fn
		end
		local t = topics[topic]
		if not t then
			t = { fn = {}, owner = {}, n = 0, depth = 0, dirty = false }
			topics[topic] = t
		end
		local fns, owners = t.fn, t.owner
		for i = 1, t.n do
			if fns[i] and owners[i] == owner then
				fns[i] = fn
				return
			end
		end
		local n = t.n + 1
		t.n = n
		fns[n], owners[n] = fn, owner
	end

	local function OffIn(t, owner)
		local fns, owners = t.fn, t.owner
		for i = 1, t.n do
			if fns[i] and owners[i] == owner then
				fns[i], owners[i] = false, false
				t.dirty = true
			end
		end
		if t.dirty and t.depth == 0 then
			Compact(t)
		end
	end

	function MelloUI:Off(owner, topic)
		if owner == nil then
			return
		end
		if topic ~= nil then
			local t = topics[topic]
			if t then
				OffIn(t, owner)
			end
			return
		end
		for _, t in pairs(topics) do
			OffIn(t, owner)
		end
	end

	-- a Batch's held 'setting' Fires: parallel lists, and at[module][key] =
	-- its slot. Two kept (one filling while the other goes out), their
	-- tables reused from batch to batch.
	local function NewHold()
		return { n = 0, mod = {}, key = {}, val = {}, at = {} }
	end
	local held, spare = NewHold(), nil

	local function Hold(module, key, value)
		local h = held
		local byKey
		if module ~= nil and key ~= nil then
			byKey = h.at[module]
			if not byKey then
				byKey = {}
				h.at[module] = byKey
			end
			local i = byKey[key]
			if i then
				h.val[i] = value
				return
			end
		end
		local i = h.n + 1
		h.n = i
		h.mod[i], h.key[i], h.val[i] = module, key, value
		if byKey then
			byKey[key] = i
		end
	end

	function MelloUI:Fire(topic, ...)
		if batch > 0 and topic == "setting" then
			Hold(...)
			return
		end
		local t = topics[topic]
		if not t or t.n == 0 then
			return
		end
		t.depth = t.depth + 1
		local fns = t.fn
		for i = 1, t.n do   -- (the count as it was when the Fire began)
			local fn = fns[i]
			if fn then
				local ok, err = pcall(fn, ...)
				if not ok then
					Report(err)
				end
			end
		end
		t.depth = t.depth - 1
		if t.dirty and t.depth == 0 then
			Compact(t)
		end
	end

	local function Flush()
		local h = held
		if h.n == 0 then
			return
		end
		-- a listener may start a Batch of its own: it fills the other list
		held = spare or NewHold()
		spare = nil
		for i = 1, h.n do
			local module, key, value = h.mod[i], h.key[i], h.val[i]
			h.mod[i], h.key[i], h.val[i] = nil, nil, nil
			MelloUI:Fire("setting", module, key, value)
		end
		h.n = 0
		for _, byKey in pairs(h.at) do
			wipe(byKey)
		end
		spare = h
	end

	local function EndBatch(ok, ...)
		batch = batch - 1
		if batch == 0 then
			Flush()
			if backupWanted then
				backupWanted = false
				if MelloUI.ScheduleBackup then
					MelloUI:ScheduleBackup("batch")
				end
			end
		end
		if not ok then
			error((...), 0)
		end
		return ...
	end

	function MelloUI:Batch(fn, ...)
		batch = batch + 1
		return EndBatch(pcall(fn, ...))
	end

	-- NotifySettingChanged, SetModuleEnabled and the profile loads ask for
	-- the backup here: "setting <key>" as before, or once for a whole Batch
	Backup = function(self, reason, detail)
		if batch > 0 then
			backupWanted = true
			return
		end
		if self.ScheduleBackup then
			self:ScheduleBackup(detail ~= nil and (reason .. tostring(detail)) or reason)
		end
	end
end

--------------------------------------------------------------------------------
-- UI sounds (moved from the configurator, audit 2026-09-24: its sounds are
-- for every MelloUI window, and the configurator is being rebuilt). The soft
-- clicks made by Tools\make_ui_sounds.py; the game's own sounds if a file is
-- missing; the Custom Sounds module's own click when it is on.
--   MelloUI:PlayUISound(kind)
--     the soft clicks:  "page", "tab", "check_on", "check_off"
--     the game's own:   "option_on", "option_off" (its checkbox clicks),
--                       "menu_open", "menu_close", "menu_button" (the game
--                       menu's), "window_open", "window_close", "tick" (the
--                       chat's scroll button), "waypoint_set", "waypoint_clear"
--     the notice's:     "notice_track", "notice_arrive", "notice_learn",
--                       "notice_fail" (MelloUI:Announce, on the Master channel)
-- Every MelloUI window plays its UI sounds through here, never PlaySound
-- itself (audit, 2026-09-24: Dynamic UI, Voice Over, the Quest List and the
-- mover each called it directly; Tools/lint/check_panels.py holds it).
--------------------------------------------------------------------------------

do
	local SOUND_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Sounds\\"
	-- file: MelloUI's own click, played first. kit: the SOUNDKIT name (alt:
	-- the one for a client without it), looked up when played -- played when
	-- there is no file or the file is missing. A kit-only kind is the game's
	-- sound the window played before, id for id; Custom Sounds' PlaySound hook
	-- swaps it as it does any game click.
	local SOUNDS = {
		check_on  = { file = "check_on.ogg",  kit = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
		check_off = { file = "check_off.ogg", kit = "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
		tab       = { file = "tab.ogg",       kit = "IG_CHARACTER_INFO_TAB" },
		page      = { file = "page.ogg",      kit = "IG_MAINMENU_OPTION" },
		option_on      = { kit = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
		option_off     = { kit = "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
		menu_open      = { kit = "IG_MAINMENU_OPEN" },
		menu_close     = { kit = "IG_MAINMENU_CLOSE" },
		menu_button    = { kit = "IG_MAINMENU_OPTION" },
		window_open    = { kit = "IG_CHARACTER_INFO_OPEN" },
		window_close   = { kit = "IG_CHARACTER_INFO_CLOSE" },
		tick           = { kit = "U_CHAT_SCROLL_BUTTON" },
		waypoint_set   = { kit = "UI_MAP_WAYPOINT_CLICK_TO_PLACE", alt = "IG_MAINMENU_OPTION_CHECKBOX_ON" },
		waypoint_clear = { kit = "UI_MAP_WAYPOINT_REMOVE", alt = "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
		-- the on-screen notice's chimes (Core/Notice.lua): Route's own from
		-- before, on the Master channel as they were
		notice_track   = { kit = "UI_MAP_WAYPOINT_SUPER_TRACK_ON", alt = "UI_MAP_WAYPOINT_CLICK_TO_PLACE", channel = "Master" },
		notice_arrive  = { kit = "UI_MAP_WAYPOINT_SUPER_TRACK_OFF", alt = "IG_QUEST_LIST_COMPLETE", channel = "Master" },
		notice_learn   = { kit = "UI_MAP_WAYPOINT_CLICK_TO_PLACE", alt = "IG_MAINMENU_OPTION_CHECKBOX_ON", channel = "Master" },
		notice_fail    = { kit = "UI_MAP_WAYPOINT_REMOVE", alt = "IG_QUEST_LOG_ABANDON_QUEST", channel = "Master" },
	}
	for _, sound in pairs(SOUNDS) do
		if sound.file then
			sound.path = SOUND_PATH .. sound.file
		end
	end

	function MelloUI:PlayUISound(kind)
		local sound = SOUNDS[kind]
		if not sound then
			return
		end
		-- the Custom Sounds module, when it is on, plays its own click instead
		if self.PlayCustomUISound and self:PlayCustomUISound(kind) then
			return
		end
		if sound.path then
			local ok, played = pcall(PlaySoundFile, sound.path, "SFX")
			if ok and played then
				return
			end
		end
		local kit = SOUNDKIT and (SOUNDKIT[sound.kit] or (sound.alt and SOUNDKIT[sound.alt]))
		if kit and sound.channel then
			PlaySound(kit, sound.channel)
		elseif kit then
			PlaySound(kit)
		end
	end
end

--------------------------------------------------------------------------------
-- Window places: one store, one mover registry and one keep-on-screen for
-- every MelloUI window (audit, 2026-09-24, rank 6: the whisper popups, the
-- Route arrow, the Voice Over overlay and the copy window each dragged
-- themselves and kept their place their own way, and Unlock the Windows,
-- Reset positions and the UI-scale put-back never reached them). Core keeps
-- the registration and the store, so they work with UI Modifications off;
-- UI Modifications brings the unlocked behaviour (the darkened screen, the
-- grid, the snap, the wheel's scale) as the mover's provider.
--
--   MelloUI:RegisterMover(frame, handle, opts) -> entry
--       handle (default: the frame) is what is dragged. opts, all optional:
--         key        its place in the store (default: the frame's name; no
--                    key, no saved place)
--         anchor     the frame's point that is saved, held to the same point
--                    of the screen ("TOPRIGHT": it grows down and left from
--                    there); nil: BOTTOMLEFT to the screen's CENTER, the
--                    mover's own
--         default    function(frame): lays its default place (Reset)
--         save       function(frame): a window that keeps its own place (the
--                    Quest Tracker): called on release, the store untouched
--         reset      function(): Reset positions, for such a window
--         min, max   the wheel's scale range; base: its 100 %
--         with       a frame, or a list of frames, kept on the screen with it
--                    (they move with it: the world map and the Quest List)
--         plainDrag  "always": dragged at any time, unlocked or not;
--                    "unlocked": only while the windows are unlocked;
--                    false (default): only through the provider
--       The entry is { frame, handle, key, anchor, default, save, reset, min,
--       max, base, with, plainDrag, moving }. A frame registered again gets
--       its first entry back. A saved place is put back at once and on every
--       show (not for a `save` window), and on a UI Scale change for the
--       shown ones ("scale" topic, reason "uiscale").
--   MelloUI:SavePosition(key, frame[, scale]) -> saved
--       the frame's place under key, by its entry's anchor; scale: a number
--       is kept with it (to a hundredth), false drops it, nil leaves it
--   MelloUI:RestorePosition(key, frame) -> placed[, "combat"]
--       the saved scale, then the place, kept on the screen; false when
--       nothing is saved, or for a protected frame in combat
--   MelloUI:ForgetPosition(key)
--   MelloUI:GetPosition(key) -> { point, relPoint, x, y, scale } or nil
--       point nil = BOTTOMLEFT, relPoint nil = CENTER; x, y in the frame's
--       own units. Read only: change it through Save / Forget.
--   MelloUI:ResetMover(entryOrFrame)   forgets its place, calls its reset,
--                                      then its default
--   MelloUI:MoverEntries()             the entries, in registration order
--   MelloUI:WindowsUnlocked()          true while the windows are unlocked
--                                      (the provider says so; none: false)
--   MelloUI:SetMoverProvider(provider)
--       provider:Attach(entry) is called for every entry, now and later. At
--       a drag start on a handle, provider:DragStart(entry) is asked first:
--       true takes that drag (provider:DragStop(entry) ends it, and the
--       provider saves, through SavePosition or entry.save); otherwise the
--       plain drag runs when entry.plainDrag allows it. The handle's
--       OnDragStart / OnDragStop are Core's: a provider hooks them, never sets
--       them, and leaves the mouse on for "always" handles. A window hidden
--       mid-drag (no OnDragStop) ends its drag from Core's OnHide hook
--       (DragStop for a provider's drag); the frame's own OnShow / OnHide
--       are hooked too, so set them BEFORE registering (SetScript drops hooks).
--       provider:IsUnlocked() says whether the windows are unlocked.
--   MelloUI:FitOnScreen(frame, extraRects) -> moved, dx, dy
--       a laid-out frame moved (its points shifted) just enough to be on
--       the screen, together with extraRects (a frame or a list of frames
--       that move with it; hidden ones do not count); one larger than the
--       screen keeps its top-left corner on it. dx, dy in its own units.
-- The store is UI Modifications' `positions` setting, which is in its
-- settings whether the module is on or off, so profiles, share strings and
-- the macro backup carry every place. Nothing is made or hooked until a
-- window registers (the 'scale' listener aside: one entry on the bus).
--------------------------------------------------------------------------------

local RegisterEntry   -- the registration itself (MelloUI:RegisterMover); the copy window's

do
	local Num = Safe.Number
	local Secret = Safe.IsSecret
	local POSITIONS_MODULE = "UIModifications"

	-- where a point sits on its frame: 0 left / bottom .. 1 right / top
	local POINT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5,
		TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
	local POINT_Y = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
		BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }

	local entries = {}                 -- in registration order
	local byFrame, byKey, byHandle = {}, {}, {}
	local provider

	-- the one table of places, looked up each time (a profile load or Reset
	-- positions puts a new one there); create: made when missing
	local function Positions(create)
		local db = MelloUI.db
		local modules = db and db.modules
		if type(modules) ~= "table" then
			return nil
		end
		local um = modules[POSITIONS_MODULE]
		if type(um) ~= "table" then
			if not create then
				return nil
			end
			if MelloUI.modules[POSITIONS_MODULE] then
				um = MelloUI:GetModuleDB(POSITIONS_MODULE)
			else
				um = {}
				modules[POSITIONS_MODULE] = um
			end
		end
		local positions = um.positions
		if type(positions) ~= "table" then
			if not create then
				return nil
			end
			positions = {}
			um.positions = positions
		end
		return positions
	end

	-- written through the setting path, so the backup this client's saved
	-- variables rely on is written (as the mover always did)
	local function Stored(positions)
		MelloUI:NotifySettingChanged(POSITIONS_MODULE, "positions", positions)
	end

	-- Edit Mode's own SetPoint / ClearAllPoints / SetScale on its systems
	-- leave tainted state behind when called from here; the plain methods it
	-- kept aside (<Method>Base) are used where a frame has them (the mover's
	-- rule, UIModifications.lua)
	local function Raw(frame, method)
		return frame[method .. "Base"] or frame[method]
	end

	-- a protected frame in combat cannot be moved or scaled by an addon
	local function Locked(frame)
		if not (InCombatLockdown and InCombatLockdown()) then
			return false
		end
		local ok, protected = pcall(frame.IsProtected, frame)
		return ok and not Secret(protected) and protected and true or false
	end

	-- left, bottom, width, height in the frame's own units; nil when any
	-- reads secret or is missing
	local function Rect(frame)
		local ok, l, b, w, h = pcall(frame.GetRect, frame)
		if not ok then
			return nil
		end
		l, b, w, h = Num(l), Num(b), Num(w), Num(h)
		if not (l and b and w and h) then
			return nil
		end
		return l, b, w, h
	end

	local function Size(frame)
		local ok, w, h = pcall(frame.GetSize, frame)
		if not ok then
			return nil
		end
		return Num(w), Num(h)
	end

	-- the frame's effective scale, and the screen's scale and size (in its
	-- units); nil when any cannot be read plainly
	local function Screen(frame)
		local okS, fs = pcall(frame.GetEffectiveScale, frame)
		local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
		local okP, sw, sh = pcall(UIParent.GetSize, UIParent)
		fs, us = okS and Num(fs), okU and Num(us)
		sw, sh = okP and Num(sw), okP and Num(sh)
		if not (fs and us and sw and sh) or fs <= 0 or us <= 0 or sw <= 0 or sh <= 0 then
			return nil
		end
		return fs, us, sw, sh
	end

	-- How far a box (in pixels) must move to be on a screen of sw x sh
	-- pixels (UI Modifications' OnScreen, user 2026-09-24: "UI Scaling Break
	-- the UI"): past the right or the bottom it comes in; one larger than
	-- the screen keeps its left and top edges on it.
	local function Pull(left, bottom, right, top, sw, sh)
		local dx, dy = 0, 0
		if right > sw then
			dx = sw - right
		end
		if left + dx < 0 then
			dx = -left
		end
		if bottom < 0 then
			dy = -bottom
		end
		if top + dy > sh then
			dy = sh - top
		end
		return dx, dy
	end

	-- a box (pixels) grown by a shown frame's rect
	local function Grow(extra, left, bottom, right, top)
		if type(extra) ~= "table" or not extra.GetRect then
			return left, bottom, right, top
		end
		local okV, shown = pcall(extra.IsShown, extra)
		if not okV or Secret(shown) or not shown then
			return left, bottom, right, top
		end
		local okS, es = pcall(extra.GetEffectiveScale, extra)
		es = okS and Num(es)
		local l, b, w, h = Rect(extra)
		if not (es and l) or es <= 0 or w <= 0 or h <= 0 then
			return left, bottom, right, top
		end
		l, b = l * es, b * es
		return math.min(left, l), math.min(bottom, b), math.max(right, l + w * es), math.max(top, b + h * es)
	end

	-- extras: a frame, or a list of frames
	local function Union(extras, left, bottom, right, top)
		if type(extras) ~= "table" then
			return left, bottom, right, top
		end
		if extras.GetRect then
			return Grow(extras, left, bottom, right, top)
		end
		for i = 1, #extras do
			left, bottom, right, top = Grow(extras[i], left, bottom, right, top)
		end
		return left, bottom, right, top
	end

	-- The offsets that keep a frame of w x h (its own units) on the screen
	-- when it is hung by `point` from the screen's `relPoint` at x, y. Its
	-- extras are measured where they are now, against the frame where it is
	-- now (they move with it), before its anchors go.
	local function FitOffsets(frame, point, relPoint, x, y, w, h, extras)
		local fs, us, sw, sh = Screen(frame)
		if not fs or not w or not h or w <= 0 or h <= 0 then
			return x, y
		end
		local SW, SH = sw * us, sh * us
		local left = POINT_X[relPoint] * SW + (x - POINT_X[point] * w) * fs
		local bottom = POINT_Y[relPoint] * SH + (y - POINT_Y[point] * h) * fs
		local right, top = left + w * fs, bottom + h * fs
		if extras ~= nil then
			local l, b, cw, ch = Rect(frame)
			if l and cw > 0 and ch > 0 then
				local cl, cb = l * fs, b * fs
				local cr, ct = cl + cw * fs, cb + ch * fs
				local ul, ub, ur, ut = Union(extras, cl, cb, cr, ct)
				left, bottom, right, top = left + (ul - cl), bottom + (ub - cb), right + (ur - cr), top + (ut - ct)
			end
		end
		local dx, dy = Pull(left, bottom, right, top, SW, SH)
		return x + dx / fs, y + dy / fs
	end

	-- every point of a frame moved by dx, dy (its own units), its anchoring
	-- kept; the points read into these lists, emptied after
	local sP, sRel, sRP, sX, sY = {}, {}, {}, {}, {}
	local function Shift(frame, dx, dy)
		local okN, n = pcall(frame.GetNumPoints, frame)
		n = okN and Num(n)
		if not n or n < 1 then
			return false
		end
		local plain = true
		for i = 1, n do
			local ok, p, rel, rp, x, y = pcall(frame.GetPoint, frame, i)
			if not ok or Secret(p) or Secret(rel) or Secret(rp) or Secret(x) or Secret(y) then
				plain = false
			else
				sP[i], sRel[i], sRP[i], sX[i], sY[i] = p, rel, rp, Num(x) or 0, Num(y) or 0
			end
		end
		local ok = false
		if plain then
			ok = pcall(Raw(frame, "ClearAllPoints"), frame)
			if ok then
				local set = Raw(frame, "SetPoint")
				for i = 1, n do
					pcall(set, frame, sP[i], sRel[i], sRP[i], sX[i] + dx, sY[i] + dy)
				end
			end
		end
		for i = 1, n do
			sP[i], sRel[i], sRP[i], sX[i], sY[i] = nil, nil, nil, nil, nil
		end
		return ok
	end

	function MelloUI:FitOnScreen(frame, extraRects)
		if type(frame) ~= "table" or not frame.GetRect then
			return false
		end
		local fs, us, sw, sh = Screen(frame)
		local l, b, w, h = Rect(frame)
		if not (fs and l) or w <= 0 or h <= 0 then
			return false
		end
		local left, bottom = l * fs, b * fs
		local right, top
		left, bottom, right, top = Union(extraRects, left, bottom, left + w * fs, bottom + h * fs)
		local dx, dy = Pull(left, bottom, right, top, sw * us, sh * us)
		if (dx == 0 and dy == 0) or Locked(frame) then
			return false
		end
		dx, dy = dx / fs, dy / fs
		return Shift(frame, dx, dy), dx, dy
	end

	local function Round(v, step)
		return math.floor(v * step + 0.5) / step
	end

	function MelloUI:GetPosition(key)
		local positions = key ~= nil and Positions(false)
		local pos = positions and positions[key]
		return type(pos) == "table" and pos or nil
	end

	function MelloUI:SavePosition(key, frame, scale)
		if key == nil or type(frame) ~= "table" then
			return false
		end
		local entry = byKey[key]
		local anchor = entry and entry.anchor
		local point, relPoint = anchor or "BOTTOMLEFT", anchor or "CENTER"
		local fs, us, sw, sh = Screen(frame)
		local l, b, w, h = Rect(frame)
		if not (fs and l) then
			return false
		end
		-- the screen in the frame's own units
		local k = us / fs
		local x = l + POINT_X[point] * w - POINT_X[relPoint] * sw * k
		local y = b + POINT_Y[point] * h - POINT_Y[relPoint] * sh * k
		local positions = Positions(true)
		if not positions then
			return false
		end
		local pos = positions[key]
		if type(pos) ~= "table" then
			pos = {}
			positions[key] = pos
		end
		-- compact, as the mover's: a tenth of a unit, the scale to a
		-- hundredth, the points only when not the mover's own
		pos.point = point ~= "BOTTOMLEFT" and point or nil
		pos.relPoint = relPoint ~= "CENTER" and relPoint or nil
		pos.x, pos.y = Round(x, 10), Round(y, 10)
		if scale == false then
			pos.scale = nil
		elseif Num(scale) and scale > 0 then
			pos.scale = Round(scale, 100)
		end
		Stored(positions)
		return true
	end

	function MelloUI:ForgetPosition(key)
		local positions = key ~= nil and Positions(false)
		if positions and positions[key] ~= nil then
			positions[key] = nil
			Stored(positions)
		end
	end

	function MelloUI:RestorePosition(key, frame)
		local pos = self:GetPosition(key)
		if not pos or type(frame) ~= "table" then
			return false
		end
		local point, relPoint = pos.point or "BOTTOMLEFT", pos.relPoint or "CENTER"
		if not (POINT_X[point] and POINT_X[relPoint]) then
			return false
		end
		if Locked(frame) then
			return false, "combat"
		end
		local entry = byFrame[frame]
		-- the scale first, while it still hangs where it was; its
		-- backgrounds laid again only when its scale really changed
		local scale = tonumber(pos.scale)
		if scale and scale > 0 then
			local Kit = self.Kit
			if Kit and Kit.SetFrameScale then
				Kit:SetFrameScale(frame, scale, Raw(frame, "SetScale"))
			else
				Raw(frame, "SetScale")(frame, scale)
			end
		end
		-- measured before the anchors go: a window sized by them reads 0
		-- wide after
		local w, h = Size(frame)
		local x, y = FitOffsets(frame, point, relPoint, tonumber(pos.x) or 0, tonumber(pos.y) or 0, w, h,
			entry and entry.with)
		Raw(frame, "ClearAllPoints")(frame)
		Raw(frame, "SetPoint")(frame, point, UIParent, relPoint, x, y)
		return true
	end

	-- Core's handlers go through a /melloperf scope of their own, one handler
	-- for every handle (Shared). Core loads before Perf.lua, so its scope is
	-- opened by Anim.lua while the files load (MelloUI.CorePerf): one asked
	-- for here after login would open a file load that never closes
	-- (review, 2026-09-25). Without it, plain hooks.
	local wrapped = {}
	local function Hook(frame, script, label, fn)
		local scope = MelloUI.CorePerf
		if scope and scope.Shared and scope.HookScript then
			local w = wrapped[fn]
			if not w then
				w = scope.Shared(label, fn, "script")
				wrapped[fn] = w
			end
			return scope.HookScript(frame, script, w)
		end
		return frame:HookScript(script, fn)
	end

	local function Unlocked()
		if not (provider and provider.IsUnlocked) then
			return false
		end
		local ok, on = pcall(provider.IsUnlocked, provider)
		return ok and on and true or false
	end

	-- a plain drag let go: saved in the store (or by the window itself) and
	-- hung by its own anchor again, kept on the screen
	local function SaveEntry(entry)
		local frame = entry.frame
		if entry.save then
			local ok, err = pcall(entry.save, frame)
			if not ok then
				Report(err)
			end
		elseif entry.key ~= nil and MelloUI:SavePosition(entry.key, frame) then
			MelloUI:RestorePosition(entry.key, frame)
		end
	end

	-- a drag over: the plain one let go (saved, hung by its anchor again;
	-- stale: a drag left over from before a hide, only stopped), the
	-- provider's handed back to it to end
	local function EndDrag(entry, stale)
		local how = entry.moving
		entry.moving = nil
		if how == "provider" then
			if provider and provider.DragStop then
				local ok, err = pcall(provider.DragStop, provider, entry)
				if not ok then
					Report(err)
				end
			end
		elseif how == "plain" then
			entry.frame:StopMovingOrSizing()
			if not stale then
				SaveEntry(entry)
			end
		end
	end

	local function DragStart(handle)
		local entry = byHandle[handle]
		if not entry then
			return
		end
		-- a drag that never saw its OnDragStop (its window hidden while it
		-- was held): ended first, or the window could never be dragged or
		-- put back again (review, 2026-09-25); this drag saves its place
		if entry.moving then
			EndDrag(entry, true)
		end
		if provider and provider.DragStart then
			local ok, took = pcall(provider.DragStart, provider, entry)
			if not ok then
				Report(took)
			elseif took then
				entry.moving = "provider"
				return
			end
		end
		local mode = entry.plainDrag
		if not (mode == "always" or (mode == "unlocked" and Unlocked())) then
			return
		end
		local frame = entry.frame
		if Locked(frame) then
			return
		end
		frame:SetMovable(true)
		frame:StartMoving()
		entry.moving = "plain"
	end

	local function DragStop(handle)
		local entry = byHandle[handle]
		if entry and entry.moving then
			EndDrag(entry)
		end
	end

	-- a window hidden while it is dragged (Esc, its close key) gets no
	-- OnDragStop: its drag ends here, where it was let go
	local function OnHide(frame)
		local entry = byFrame[frame]
		if entry and entry.moving then
			EndDrag(entry)
		end
	end

	-- a saved place put back on every show (the window may have been laid
	-- elsewhere, or the screen changed, while it was hidden); a drag still
	-- marked from before it was hidden is over, its place not taken
	local function OnShow(frame)
		local entry = byFrame[frame]
		if not entry then
			return
		end
		if entry.moving then
			EndDrag(entry, true)
		end
		if not entry.save then
			MelloUI:RestorePosition(entry.key, frame)
		end
	end

	local function Attach(entry)
		local ok, err = pcall(provider.Attach, provider, entry)
		if not ok then
			Report(err)
		end
	end

	RegisterEntry = function(frame, handle, opts)
		if type(frame) ~= "table" then
			return nil
		end
		local entry = byFrame[frame]
		if entry then
			return entry
		end
		if type(opts) ~= "table" then
			opts = {}
		end
		handle = type(handle) == "table" and handle or frame
		local key = opts.key
		if key == nil and frame.GetName then
			local ok, name = pcall(frame.GetName, frame)
			key = ok and Safe.Text(name) or nil
		end
		local anchor = opts.anchor
		entry = {
			frame = frame, handle = handle, key = key,
			anchor = POINT_X[anchor] and anchor or nil,
			default = opts.default, save = opts.save, reset = opts.reset,
			min = opts.min, max = opts.max, base = opts.base, with = opts.with,
			plainDrag = (opts.plainDrag == "always" or opts.plainDrag == "unlocked") and opts.plainDrag or false,
		}
		entries[#entries + 1] = entry
		byFrame[frame] = entry
		if key ~= nil and byKey[key] == nil then
			byKey[key] = entry
		end
		-- the handle's drag is Core's: the plain drag, or the provider's
		if not byHandle[handle] then
			byHandle[handle] = entry
			if handle.RegisterForDrag and entry.plainDrag then
				handle:RegisterForDrag("LeftButton")
			end
			if entry.plainDrag == "always" and handle.EnableMouse then
				handle:EnableMouse(true)
			end
			Hook(handle, "OnDragStart", "mover: drag start", DragStart)
			Hook(handle, "OnDragStop", "mover: drag stop", DragStop)
		end
		Hook(frame, "OnHide", "mover: drag ended by a hide", OnHide)
		if not entry.save and key ~= nil then
			Hook(frame, "OnShow", "mover: saved place on show", OnShow)
			MelloUI:RestorePosition(key, frame)
		end
		if provider and provider.Attach then
			Attach(entry)
		end
		return entry
	end

	function MelloUI:RegisterMover(frame, handle, opts)
		return RegisterEntry(frame, handle, opts)
	end

	function MelloUI:MoverEntries()
		return entries
	end

	function MelloUI:WindowsUnlocked()
		return Unlocked()
	end

	function MelloUI:ResetMover(target)
		-- a registered frame, or its entry
		local entry = byFrame[target]
		if not entry and type(target) == "table" and target.frame ~= nil and byFrame[target.frame] == target then
			entry = target
		end
		if not entry then
			return
		end
		if entry.key ~= nil and not entry.save then
			self:ForgetPosition(entry.key)
		end
		if entry.reset then
			local ok, err = pcall(entry.reset)
			if not ok then
				Report(err)
			end
		end
		if entry.default then
			local ok, err = pcall(entry.default, entry.frame)
			if not ok then
				Report(err)
			end
		end
	end

	function MelloUI:SetMoverProvider(p)
		provider = p
		if p and p.Attach then
			for i = 1, #entries do
				Attach(entries[i])
			end
		end
	end

	-- a new UI Scale or resolution: the shown windows with a saved place put
	-- back, so they stay on the new screen (the hidden ones on their next
	-- show)
	MelloUI:On("scale", function(reason)
		if reason ~= "uiscale" then
			return
		end
		for i = 1, #entries do
			local entry = entries[i]
			if not entry.save and not entry.moving and entry.key ~= nil then
				local ok, shown = pcall(entry.frame.IsShown, entry.frame)
				if ok and not Secret(shown) and shown then
					MelloUI:RestorePosition(entry.key, entry.frame)
				end
			end
		end
	end, "Core mover")
end

local copyFrame

-- The copy window: a large text box to select and copy from. In PASTE mode
-- (MelloUI:ShowPaste) the box takes typing and an Import button hands the
-- text on; otherwise whatever is typed is put back at once.
local function CopyFrame()
	if copyFrame then
		return copyFrame
	end
	local f = CreateFrame("Frame", "MelloUICopyFrame", UIParent, "BackdropTemplate")
	f:SetSize(760, 480)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f:SetBackdropColor(0.06, 0.06, 0.07, 0.97)
	f:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 12, -10)
	f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.hint:SetPoint("TOPRIGHT", -40, -12)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	local scroll = CreateFrame("ScrollFrame", "MelloUICopyScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	f.scroll = scroll
	local edit = CreateFrame("EditBox", "MelloUICopyEdit", scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(700)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)
	edit:SetScript("OnEditFocusGained", function(self)
		if not f.onAccept then
			self:HighlightText()
		end
	end)
	-- typing must not change the text: put it back (not while pasting)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and not f.onAccept then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	f.edit = edit
	f.accept = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.accept:SetSize(120, 24)
	f.accept:SetPoint("BOTTOMRIGHT", -34, 10)
	f.accept:SetText("Import")
	f.accept:SetScript("OnClick", function()
		local fn = f.onAccept
		if fn and fn(f.edit:GetText()) then
			f:Hide()
		end
	end)
	f:SetScript("OnHide", function() f.onAccept = nil end)
	-- dragged by the one mover (audit, 2026-09-24): at any time, as before,
	-- and now kept where it was dropped (the store's 'copy'), back in the
	-- middle with Reset positions. Registered after its own OnHide is set:
	-- SetScript would drop the mover's hook (review, 2026-09-25)
	RegisterEntry(f, f, { key = "copy", plainDrag = "always", default = function(self)
		self:ClearAllPoints()
		self:SetPoint("CENTER")
	end })
	tinsert(UISpecialFrames, "MelloUICopyFrame")
	copyFrame = f
	return f
end

-- Show `text` to be selected and copied.
function MelloUI:ShowText(title, text)
	local f = CopyFrame()
	f.onAccept = nil
	f.accept:Hide()
	f.scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	f.hint:SetText("Ctrl+A, Ctrl+C to copy  -  Esc closes")
	f.title:SetText(PREFIX .. (title or ""))
	f.text = text or ""
	f.edit:SetText(f.text)
	f:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
end

-- An empty box to paste into; Import calls onAccept(text), and the window
-- closes when it returns true.
function MelloUI:ShowPaste(title, onAccept)
	local f = CopyFrame()
	f.onAccept = onAccept
	f.accept:Show()
	f.scroll:SetPoint("BOTTOMRIGHT", -32, 42)
	f.hint:SetText("Ctrl+V to paste  -  Esc closes")
	f.title:SetText(PREFIX .. (title or ""))
	f.text = ""
	f.edit:SetText("")
	f:Show()
	f.edit:SetFocus()
end

function MelloUI:ShowLog(title)
	self:ShowText((title or "log") .. string.format("  (%d lines)", #log), table.concat(log, "\n"))
end

SLASH_MELLOLOG1 = "/mellolog"
SlashCmdList.MELLOLOG = function(msg)
	if msg == "clear" then
		MelloUI:ClearLog()
		MelloUI:Print("Log cleared.")
		return
	end
	MelloUI:ShowLog("log")
end

-- Chat lines nobody asked for: something learned, settings restored late, a
-- hint. Replies to slash commands use Print and always show; these can be
-- turned off with Tweaks > Chat Notices.
function MelloUI:Notice(msg, ...)
	local tweaks = self.db and self.db.modules and self.db.modules.Tweaks
	if tweaks and tweaks.chatNotices == false then
		return
	end
	self:Print(msg, ...)
end

-- One-time hint after the update that moved the settings out of Options > AddOns.
-- The flag lives in the Tweaks settings so the macro backup keeps it. It
-- yields to the installer (its window shows, its countdown runs, or its
-- first-login check has not decided yet): the installer marks the tip shown
-- when it opens, and its Done page says where the settings live.
function MelloUI:ShowMenuButtonTip()
	local tweaks = self.db and self.db.modules and self.db.modules.Tweaks
	if not tweaks or tweaks.menuTipShown then
		return
	end
	local installer = self.Installer
	if type(installer) == "table" and type(installer.Busy) == "function" and installer:Busy() then
		return
	end
	tweaks.menuTipShown = true
	Backup(self, "menu tip")
	self:Notice("The settings have their own window now: the MelloUI button in the game menu (Escape), or /mello.")
end

-- Fill missing keys of tbl from defaults (shallow, one nested level for tables).
local function ApplyDefaults(tbl, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(tbl[k]) ~= "table" then
				tbl[k] = {}
			end
			ApplyDefaults(tbl[k], v)
		elseif tbl[k] == nil then
			tbl[k] = v
		end
	end
	return tbl
end
MelloUI.ApplyDefaults = ApplyDefaults

-- Safe call wrapper so one broken module cannot take the whole addon down.
local function SafeCall(module, method, ...)
	local fn = module[method]
	if type(fn) ~= "function" then
		return true
	end
	local perf = MelloUI.Perf
	local t0, m0 = perf and debugprofilestop(), perf and collectgarbage("count")
	local ok, err = pcall(fn, module, ...)
	if perf then
		perf:ModuleCall(module.name, method, debugprofilestop() - t0, collectgarbage("count") - m0)
	end
	if not ok then
		MelloUI:Print("|cffff4040Error|r in module '%s' (%s): %s", module.name, method, tostring(err))
	end
	return ok
end

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

-- the modules as registered (MelloUI:ModulesInOrder), and the types of the
-- registry's own fields (see the header): checked, kept as given
MelloUI.moduleList = {}
local REGISTRY_FIELDS = { flavour = "string", group = "string", window = "table", tweak = "table", area = "table",
	role = "string", navOrder = "number" }
local ROLES = { core = true, look = true, feature = true, adds = true, replaces = true }

function MelloUI:RegisterModule(name, module)
	assert(type(name) == "string" and name ~= "", "MelloUI:RegisterModule requires a name")
	assert(not self.modules[name], "MelloUI module '" .. name .. "' is already registered")

	module = module or {}
	module.name = name
	module.title = module.title or name
	module.desc = module.desc or ""
	module.defaults = module.defaults or {}
	module.options = module.options or {}
	assert(module.keep == nil or type(module.keep) == "table", "MelloUI module '" .. name .. "': keep must be a list of keys")
	-- a registry field of the wrong type: reported and left off, so only the
	-- tile or row that would read it goes without; an error here would take
	-- the whole module (and the rest of its file) out (review, 2026-09-25)
	local icon = module.icon
	if icon ~= nil and type(icon) ~= "string" and type(icon) ~= "number" then
		Report("MelloUI module '" .. name .. "': icon must be a texture path or a file id")
		module.icon = nil
	end
	for field, kind in pairs(REGISTRY_FIELDS) do
		if module[field] ~= nil and type(module[field]) ~= kind then
			Report("MelloUI module '" .. name .. "': " .. field .. " must be a " .. kind)
			module[field] = nil
		end
	end
	if module.role ~= nil and not ROLES[module.role] then
		Report("MelloUI module '" .. name .. "': role must be core, look, feature, adds or replaces")
		module.role = nil
	end
	if module.enabledByDefault == nil then
		module.enabledByDefault = true
	end
	module.isEnabled = false

	self.modules[name] = module
	table.insert(self.moduleOrder, name)
	self.moduleList[#self.moduleList + 1] = module

	-- Late registration (after login) still gets initialised.
	if self.initialized then
		self:InitModule(module)
	end

	return module
end

function MelloUI:GetModule(name)
	return self.modules[name]
end

function MelloUI:IterateModules()
	local i = 0
	return function()
		i = i + 1
		local name = self.moduleOrder[i]
		if name then
			return name, self.modules[name]
		end
	end
end

-- The modules in the order they registered (the TOC's): the list kept as
-- they come, not a copy, so read it and do not change it (for the lists
-- the configurator and the installer make from the registry's fields).
function MelloUI:ModulesInOrder()
	return self.moduleList
end

--------------------------------------------------------------------------------
-- CPU profiling (/mello cpu, needs the scriptProfile CVar)
--------------------------------------------------------------------------------

MelloUI.profiled = {}

-- Register a frame (its script handlers) or a function so that /mello cpu can
-- report how much CPU it used. Costs nothing while profiling is off.
function MelloUI:Profile(moduleName, label, target)
	if target ~= nil then
		self.profiled[#self.profiled + 1] = { module = moduleName, label = label, target = target }
	end
	return target
end

function MelloUI:GetModuleDB(name)
	local module = self.modules[name]
	if not module then
		return nil
	end
	self.db.modules[name] = self.db.modules[name] or {}
	return ApplyDefaults(self.db.modules[name], module.defaults)
end

function MelloUI:IsModuleEnabled(name)
	local module = self.modules[name]
	if not module then
		return false
	end
	local flag = self.db.enabled[name]
	if flag == nil then
		return module.enabledByDefault
	end
	return flag
end

function MelloUI:SetModuleEnabled(name, enabled)
	local module = self.modules[name]
	if not module then
		return
	end
	enabled = not not enabled
	self.db.enabled[name] = enabled

	if not self.initialized then
		return
	end
	Backup(self, "module ", name)

	if enabled and not module.isEnabled then
		module.isEnabled = true
		SafeCall(module, "OnEnable", self:GetModuleDB(name))
	elseif not enabled and module.isEnabled then
		module.isEnabled = false
		SafeCall(module, "OnDisable", self:GetModuleDB(name))
	end
	self:Fire("module", name, enabled)
end

-- Called by the config panel when a module setting changes.
function MelloUI:NotifySettingChanged(name, key, value)
	local module = self.modules[name]
	if not module then
		return
	end
	local db = self:GetModuleDB(name)
	db[key] = value
	if module.isEnabled then
		SafeCall(module, "OnSettingChanged", key, value, db)
	end
	Backup(self, "setting ", key)
	-- last, after everything above (held until the end of a Batch)
	self:Fire("setting", name, key, value)
end

function MelloUI:InitModule(module)
	if module.initialized then
		return
	end
	module.initialized = true
	local db = self:GetModuleDB(module.name)
	SafeCall(module, "OnInit", db)
	if self:IsModuleEnabled(module.name) then
		module.isEnabled = true
		SafeCall(module, "OnEnable", db)
	elseif module.applyWhenDisabled then
		-- A module that DRIVES other modules has to be obeyed while it is off
		-- as well. OnDisable otherwise only runs on the switch being thrown,
		-- never at login, so what it drives came up from its own saved flags
		-- and the screen disagreed with the switch (UI Modifications off with
		-- the whole reskin still on screen, 2026-09-22).
		SafeCall(module, "OnDisable", db)
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function MelloUI:InitDB()
	if type(MelloUIDB) == "table" then
		self.db = MelloUIDB
		self.dbIsTemporary = false
		self.savedVariablesStage = "ADDON_LOADED"
	else
		-- Saved variables are not in place yet. Forever loads them late and
		-- will NOT overwrite a global that already exists, so the global must
		-- stay untouched until the real data shows up. Work on a private
		-- table meanwhile and adopt the real one as soon as it appears.
		self.db = {}
		self.dbIsTemporary = true
	end
	ApplyDefaults(self.db, DB_DEFAULTS)
	self.db.version = DB_VERSION
end

-- Called at every later lifecycle point. If the client replaced the global
-- with the loaded saved variables after we initialised, switch to that table.
-- If it replaced it with something else, keep ours and make sure ours is what
-- gets saved.
function MelloUI:AdoptSavedVariables(stage)
	if self.dbIsTemporary then
		if type(MelloUIDB) ~= "table" then
			return false -- still not loaded; keep waiting
		end
		local temp = self.db
		ApplyDefaults(MelloUIDB, DB_DEFAULTS)
		MelloUIDB.version = DB_VERSION
		self.db = MelloUIDB
		self.dbIsTemporary = false
		self.savedVariablesStage = stage or "late"
		-- Carry over anything changed while the temporary table was in use
		-- (this includes values restored from the macro backup).
		for name, values in pairs(temp.modules or {}) do
			local module = self.modules[name]
			if module then
				local real = self:GetModuleDB(name)
				for k, v in pairs(values) do
					if module.defaults[k] ~= v and real[k] == module.defaults[k] then
						real[k] = v
					end
				end
			end
		end
		for name, flag in pairs(temp.enabled or {}) do
			if self.db.enabled[name] == nil then
				self.db.enabled[name] = flag
			end
		end
		self.db.profiles = self.db.profiles or {}
		for name, text in pairs(temp.profiles or {}) do
			if self.db.profiles[name] == nil then
				self.db.profiles[name] = text
			end
		end
		-- (a baked copy carried over stays known as one: it follows a newer
		-- baked text, see Profiles)
		if type(temp.profilesShipped) == "table" then
			local record = type(self.db.profilesShipped) == "table" and self.db.profilesShipped or {}
			for name, text in pairs(temp.profilesShipped) do
				if self.db.profiles[name] == text and record[name] == nil then
					record[name] = text
				end
			end
			if next(record) ~= nil then
				self.db.profilesShipped = record
			end
		end
		if self.db.defaultProfile == nil then
			self.db.defaultProfile = temp.defaultProfile
		end
		if self.db.activeProfile == nil then
			self.db.activeProfile = temp.activeProfile
		end
		-- The kit editor writes straight into the db rather than through a
		-- module, so it was not on this list and every edit made before the
		-- client got round to loading its saved variables was thrown away
		-- here (they load late on this client). What was edited THIS session
		-- is the newer of the two, so it wins.
		local function Graft(into, from)
			for key, value in pairs(from) do
				if type(value) ~= "table" then
					into[key] = value
				elseif value[1] ~= nil or type(into[key]) ~= "table" then
					-- an array (a tint, a crop) is replaced whole, never
					-- merged index by index
					into[key] = value
				else
					Graft(into[key], value)
				end
			end
		end
		for _, key in ipairs({ "kitTuning", "kitEditor" }) do
			if type(temp[key]) == "table" then
				if type(self.db[key]) ~= "table" then
					self.db[key] = temp[key]
				else
					Graft(self.db[key], temp[key])
				end
			end
		end
		if self.KitTuning then
			self.KitTuning:Reload()
		end
		-- Modules that acted on the temporary table get a second pass.
		for _, module in self:IterateModules() do
			module.db = nil
			if self:IsModuleEnabled(module.name) and type(module.OnAddonLoaded) == "function" then
				SafeCall(module, "OnAddonLoaded", self:GetModuleDB(module.name))
			end
		end
		return true
	end
	if type(MelloUIDB) == "table" and not rawequal(MelloUIDB, self.db) then
		MelloUIDB = self.db
	end
	return false
end

-- Runs fn(self) with restartingModules set, and puts the outer value back
-- even when fn raises (the error goes on after it): a flag left set would
-- keep the reskin's own reactions out for the rest of the session.
local function WhileRestarting(self, fn)
	local outer = self.restartingModules
	self.restartingModules = true
	local ok, err = pcall(fn, self)
	self.restartingModules = outer
	if not ok then
		error(err, 0)
	end
end

local function RestartEach(self)
	for _, module in self:IterateModules() do
		if module.isEnabled then
			local db = self:GetModuleDB(module.name)
			SafeCall(module, "OnDisable", db)
			SafeCall(module, "OnEnable", db)
		end
	end
end

-- After a (late) adoption, modules that are already running must re-read
-- their settings.
-- (restartingModules while it runs: a module's own reaction to a switch --
-- UI Modifications' reskin bringing Custom Sounds and the Edit Mode layout --
-- is the player's switch only, never a restart's or a profile load's)
function MelloUI:RestartModules()
	WhileRestarting(self, RestartEach)
	if self.RefreshConfig then
		self:RefreshConfig()
	end
	self:Fire("restart")
end

--------------------------------------------------------------------------------
-- Unit names on this client have a first name and a surname (user,
-- 2026-09-22: "only show the character's first name, last name or both").
-- The game's NameUtil (C side) gives the display name with or without the
-- surname and the first name alone; the surname is the rest of the full
-- name. A unit token or a name can be a secret value here (nameplates): a
-- secret first or full name is still handed back (SetText takes it), only
-- the surname needs string work and is nil when it cannot be done.
-- mode: "first", "last", "both". nil when nothing could be read.
-- A pcall's first result, secret or not; nil when it raised. The value is
-- never compared: a secret refuses even the nil test (audit, 2026-09-24).
local function PlainOrSecret(ok, value)
	if not ok then
		return nil
	end
	return value
end

function MelloUI:UnitNameAs(unit, mode)
	if not unit then
		return nil
	end
	local util = NameUtil
	local full, first
	if type(util) == "table" and util.FormatUnitNameForDisplay then
		full = PlainOrSecret(pcall(util.FormatUnitNameForDisplay, unit, true))
		if util.GetUnitFirstName then
			first = PlainOrSecret(pcall(util.GetUnitFirstName, unit))
		end
	end
	-- (each name asked for secret before its nil test)
	if not Safe.IsSecret(full) and full == nil then
		full = PlainOrSecret(pcall(UnitName, unit))
	end
	local secretFull = Safe.IsSecret(full)
	if not secretFull and full == nil then
		return nil
	end
	local secretFirst = Safe.IsSecret(first)
	if not (secretFull or secretFirst) and first == nil then
		first = full:match("^(%S+)") or full
	end
	if mode == "both" then
		return full
	elseif mode == "first" then
		return first
	elseif mode == "last" then
		if secretFull or secretFirst or first == nil then
			return nil
		end
		local rest = full:sub(#first + 1):gsub("^%s+", "")
		if rest == "" then
			return full   -- no surname: the name as it is
		end
		return rest
	end
	return nil
end

-- Profiles
--
-- A profile is the settings serialised the way the macro backup does it
-- (only values that differ from the defaults). Profiles live in
-- MelloUIDB.profiles; Tools\bake_routes.py bakes them into Media\Profiles.lua
-- (MelloUI_Profiles) so they ship with the addon,
-- and the one marked default is applied on a fresh install, that is when no
-- setting differs from the defaults after login.
--------------------------------------------------------------------------------

-- The built-in profile with every module off (user, 2026-09-22: "when the
-- addon is installed for the first time, everything should be off"): the
-- default for a fresh install, made from the module list at every login so
-- a module added later is off in it too. Not baked, not deletable, not
-- overwritable.
MelloUI.FRESH_PROFILE = "Everything Off"

function MelloUI:FreshProfileText()
	local parts = {}
	for name, module in self:IterateModules() do
		if module.enabledByDefault and not module.hidden then
			parts[#parts + 1] = "!" .. name .. "=b0"
		end
		-- the tweak modules folded under UI Modifications follow its qol_
		-- switches: those off too, so switching the umbrella on brings the
		-- reskin alone (user, 2026-09-22: "it should only auto enable the
		-- full reskin and the custom sounds")
		local keys = {}
		for key, value in pairs(module.defaults) do
			if type(key) == "string" and key:sub(1, 4) == "qol_" and value == true then
				keys[#keys + 1] = key
			end
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			parts[#parts + 1] = name .. "." .. key .. "=b0"
		end
	end
	return table.concat(parts, ";")
end

-- the baked text copied into the player's list, recorded (db.profilesShipped)
local function RecordShipped(db, name, text)
	if type(db.profilesShipped) ~= "table" then
		db.profilesShipped = {}
	end
	db.profilesShipped[name] = text
end

-- The player's profiles, the baked ones (MelloUI_Profiles) copied in while
-- the name is free. db.profilesShipped[name] records the baked text copied,
-- so a copy the player never changed follows a newer baked text (a release's
-- new "MelloUI"); a copy they saved over, or an older copy that was never
-- recorded, stays theirs.
function MelloUI:Profiles()
	local db = self.db
	db.profiles = db.profiles or {}
	local profiles = db.profiles
	local baked = type(MelloUI_Profiles) == "table" and MelloUI_Profiles.profiles
	if type(baked) == "table" then
		for name, text in pairs(baked) do
			if type(text) == "string" and name ~= self.FRESH_PROFILE then
				local have = profiles[name]
				local copied = type(db.profilesShipped) == "table" and db.profilesShipped[name] or nil
				if have == nil or (copied ~= nil and have == copied and have ~= text) then
					profiles[name] = text
					RecordShipped(db, name, text)
				elseif have == text and copied ~= text then
					RecordShipped(db, name, text)   -- (a copy equal to the baked text follows it from now on)
				end
			end
		end
	end
	profiles[self.FRESH_PROFILE] = self:FreshProfileText()
	if self.db.defaultProfile == nil then
		self.db.defaultProfile = self.FRESH_PROFILE
	end
	return self.db.profiles
end

function MelloUI:IsProfileBaked(name)
	if name == self.FRESH_PROFILE then
		return true
	end
	return type(MelloUI_Profiles) == "table" and type(MelloUI_Profiles.profiles) == "table"
		and MelloUI_Profiles.profiles[name] == self:Profiles()[name]
end

-- Personal keys (audit, 2026-09-24). Some settings are no choice at all but
-- this player's own: the flight points a character has learned (Route's
-- flights_<character>), a game setting MelloUI borrowed and must give back
-- (Chat's savedWhisperMode), a one-time step that was done (UI
-- Modifications' layoutApplied). A module names them in `keep` when it
-- registers. A profile or a share string never carries them: a posted
-- string held the sharer's character IDs, and a layoutApplied in it kept
-- the importer's reskin from ever placing its layout. Loading a profile
-- leaves them as they are: it used to wipe every character's flight points.
-- The macro backup still writes them: it brings them back, with the rest,
-- should the saved variables ever be missing.
function MelloUI:IsPersonalKey(moduleName, key)
	local module = self.modules[moduleName]
	local keep = module and module.keep
	if not keep or type(key) ~= "string" then
		return false
	end
	for i = 1, #keep do
		local entry = keep[i]
		if entry == key or (entry:sub(1, 1) == "^" and key:find(entry)) then
			return true
		end
	end
	return false
end

-- Serialised settings without their personal entries ("Module.key=value",
-- parsed as DeserializeSettings does); the text itself when it holds none.
local function StripPersonal(self, text)
	if type(text) ~= "string" or text == "" then
		return text
	end
	local parts, dropped = {}, false
	for entry in text:gmatch("[^;]+") do
		local moduleName, key = entry:match("^([^=.]+)%.([^=]+)=")
		if moduleName and self:IsPersonalKey(moduleName, key) then
			dropped = true
		else
			parts[#parts + 1] = entry
		end
	end
	return dropped and table.concat(parts, ";") or text
end

function MelloUI:SaveProfile(name)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		return false, "a profile needs a name"
	end
	if name == self.FRESH_PROFILE then
		return false, "'" .. name .. "' is built in"
	end
	self:Profiles()[name] = StripPersonal(self, self:SerializeSettings())
	self.db.activeProfile = name
	return true
end

function MelloUI:DeleteProfile(name)
	local profiles = self:Profiles()
	if profiles[name] == nil or name == self.FRESH_PROFILE then
		return false
	end
	profiles[name] = nil
	if self.db.defaultProfile == name then
		self.db.defaultProfile = nil
	end
	if self.db.activeProfile == name then
		self.db.activeProfile = nil
	end
	return true
end

function MelloUI:SetDefaultProfile(name)
	if name ~= nil and self:Profiles()[name] == nil then
		return false
	end
	-- false, not nil: "none" chosen, as against never set (Profiles() makes
	-- the built-in profile the default when nothing was chosen)
	self.db.defaultProfile = name or false
	return true
end

-- Replace every setting with the serialised ones: defaults first, then the
-- profile, then the running modules pick the new values up. The personal
-- keys stay as they are, whatever the text holds (IsPersonalKey). The
-- tables are emptied in place: a module holding its db (Route's cached
-- flight points read from it) keeps reading the same one.
-- The modules UI Modifications drives (hidden) are its to switch, never the
-- profile's flags: their flags were cleared with the rest (so each would
-- read as its enabledByDefault), and an old text may carry one ("!DarkMode"
-- lands in the flags, Dark Mode's switch being off until switched on). The
-- umbrella switched on or off by the load drives them from its OnEnable /
-- OnDisable; one off before and after is obeyed as at login (InitModule's
-- applyWhenDisabled), so what it drives stays off (a load with UI
-- Modifications off left Dark Mode and every panel running, 2026-09-26).
local function SwitchForProfile(self)
	for name, module in self:IterateModules() do
		if not module.hidden then
			local want = self:IsModuleEnabled(name)
			if want ~= (module.isEnabled or false) then
				self:SetModuleEnabled(name, want)
			elseif not want and module.applyWhenDisabled then
				SafeCall(module, "OnDisable", self:GetModuleDB(name))
			end
		end
	end
	self:RestartModules()
end

function MelloUI:ApplySettingsText(text)
	for name, module in self:IterateModules() do
		local db = self:GetModuleDB(name)
		for k in pairs(db) do
			if not (module.keep and self:IsPersonalKey(name, k)) then
				db[k] = nil
			end
		end
		ApplyDefaults(db, module.defaults)
	end
	for name in pairs(self.db.enabled) do
		self.db.enabled[name] = nil
	end
	local applied = self:DeserializeSettings(StripPersonal(self, text))
	if self.initialized then
		-- (a module's switch here is the profile's, not the player's: the
		-- reskin's own reactions stay out, as in RestartModules)
		WhileRestarting(self, SwitchForProfile)
		if self.RefreshConfig then
			self:RefreshConfig()
		end
		Backup(self, "profile")
	end
	return applied
end

--------------------------------------------------------------------------------
-- Share strings (user, 2026-09-23: "Profile share strings with the game's own
-- encoders"). A profile is already its settings' differences from the
-- defaults, as text; to share it, that text is compressed and turned into
-- plain letters by the game's own encoders (C_EncodingUtil: Deflate, then
-- Base64) behind a tag naming the format:
--
--   !MelloUI1!<base64 of the deflated profile text>
--
-- An import is decoded back and checked -- every entry "key=value", at least
-- one for a module this addon has -- before it becomes a profile. It is only
-- stored under the name given: nothing changes until it is loaded.
--------------------------------------------------------------------------------

local SHARE_TAG = "!MelloUI1!"

local function Deflate()
	return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
end

function MelloUI:ExportProfile(name)
	local text = self:Profiles()[name]
	if type(text) ~= "string" then
		return nil, "no profile '" .. tostring(name) .. "'"
	end
	-- a profile saved before they were left out may still hold personal keys
	text = StripPersonal(self, text)
	local enc = C_EncodingUtil
	if not (enc and enc.CompressString and enc.EncodeBase64) then
		return nil, "this client cannot make share strings"
	end
	local method = Deflate()
	local okC, packed
	if method then
		okC, packed = pcall(enc.CompressString, text, method)
	else
		okC, packed = pcall(enc.CompressString, text)
	end
	if not (okC and type(packed) == "string") then
		return nil, "the profile could not be compressed"
	end
	local okB, letters = pcall(enc.EncodeBase64, packed)
	if not (okB and type(letters) == "string") then
		return nil, "the profile could not be encoded"
	end
	return SHARE_TAG .. letters
end

-- The profile text inside a share string, and how many of its entries are for
-- modules this addon has; nil and the reason when it is not one.
function MelloUI:DecodeProfileString(str)
	if type(str) ~= "string" then
		return nil, "nothing to import"
	end
	-- copied from a chat or a web page it may have gained spaces or line breaks
	str = str:gsub("%s+", "")
	if str:sub(1, #SHARE_TAG) ~= SHARE_TAG then
		return nil, "not a MelloUI profile string (it starts with " .. SHARE_TAG .. ")"
	end
	local enc = C_EncodingUtil
	if not (enc and enc.DecodeBase64 and enc.DecompressString) then
		return nil, "this client cannot read share strings"
	end
	local okB, packed = pcall(enc.DecodeBase64, str:sub(#SHARE_TAG + 1))
	if not (okB and type(packed) == "string" and packed ~= "") then
		return nil, "the string is damaged (cut short while copying?)"
	end
	local method = Deflate()
	local okD, text
	if method then
		okD, text = pcall(enc.DecompressString, packed, method)
	else
		okD, text = pcall(enc.DecompressString, packed)
	end
	if not (okD and type(text) == "string") then
		return nil, "the string is damaged (cut short while copying?)"
	end
	-- never taken in: another player's personal keys (their characters' flight
	-- points, a game setting of theirs to give back, their one-time flags),
	-- which strings posted before profiles left them out still carry
	local stripped = StripPersonal(self, text)
	if stripped == "" and text ~= "" then
		return nil, "it holds no settings, only one player's own data, which profiles never carry"
	end
	text = stripped
	local total, known = 0, 0
	for entry in text:gmatch("[^;]+") do
		total = total + 1
		local key = entry:match("^([^=]+)=.")
		if not key then
			return nil, "the string holds something that is not a MelloUI setting"
		end
		local module = key:match("^!?([^.]+)")
		if module and self.modules[module] then
			known = known + 1
		end
	end
	if text ~= "" and known == 0 then
		return nil, "none of its settings belong to a MelloUI module"
	end
	return text, known, total
end

-- Store a share string as the profile `name` (replacing one of that name).
function MelloUI:ImportProfile(name, str)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		return false, "type a name for the profile first"
	end
	if name == self.FRESH_PROFILE then
		return false, "'" .. name .. "' is built in"
	end
	local text, known, total = self:DecodeProfileString(str)
	if not text then
		return false, known
	end
	self:Profiles()[name] = text
	Backup(self, "profile import")
	return true, known, total
end

function MelloUI:LoadProfile(name)
	local text = self:Profiles()[name]
	if type(text) ~= "string" then
		return false
	end
	self:ApplySettingsText(text)
	self.db.activeProfile = name
	return true
end

-- Nothing configured at all (a fresh install, or the saved variables missing
-- and the macro backup empty): apply the default profile.
function MelloUI:ApplyDefaultProfileIfFresh()
	if self:SerializeSettings() ~= "" then
		return false
	end
	local profiles = self:Profiles()
	local name = self.db.defaultProfile
	if not name or type(profiles[name]) ~= "string" then
		return false
	end
	-- as a loaded one: its personal keys never land (a profile saved before
	-- they were left out could carry one that would stand in for the player's own)
	self:DeserializeSettings(StripPersonal(self, profiles[name]))
	self.db.activeProfile = name
	self.profileAppliedAtLogin = name
	return true
end

MelloUI:RegisterEvent("ADDON_LOADED")
MelloUI:RegisterEvent("VARIABLES_LOADED")
MelloUI:RegisterEvent("PLAYER_LOGIN")
MelloUI:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		self:UnregisterEvent("ADDON_LOADED")
		self:InitDB()
		self:RegisterEvent("PLAYER_LOGOUT")
		-- Early hook for modules that must act before PLAYER_LOGIN (e.g. world fonts).
		for _, module in self:IterateModules() do
			if self:IsModuleEnabled(module.name) and type(module.OnAddonLoaded) == "function" then
				SafeCall(module, "OnAddonLoaded", self:GetModuleDB(module.name))
			end
		end
	elseif event == "VARIABLES_LOADED" then
		self:UnregisterEvent("VARIABLES_LOADED")
		if not self.db then
			self:InitDB()
		end
		self:AdoptSavedVariables("VARIABLES_LOADED")
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		if not self.db then
			self:InitDB()
		end
		self:AdoptSavedVariables("PLAYER_LOGIN")
		if self.dbIsTemporary and self.RestoreFromBackup and self:RestoreFromBackup("PLAYER_LOGIN") then
			-- the early hook ran on the defaults at ADDON_LOADED: once more
			-- on the restored settings (the world fonts)
			for _, module in self:IterateModules() do
				module.db = nil
				if self:IsModuleEnabled(module.name) and type(module.OnAddonLoaded) == "function" then
					SafeCall(module, "OnAddonLoaded", self:GetModuleDB(module.name))
				end
			end
		end
		-- (no line for it: a new player gets the installer a few seconds in,
		-- Core/Installer.lua's one login check)
		self:ApplyDefaultProfileIfFresh()
		self.initialized = true
		-- the modules come up in TOC order; a module that drives others
		-- (UI Modifications) must not pull them forward out of that order
		-- during this pass (the unit frame panel read the bars' layers
		-- before Bar Textures had set them, 2026-09-21): it sets their
		-- flags and lets this loop enable them in their turn
		self.initializingModules = true
		for _, module in self:IterateModules() do
			self:InitModule(module)
		end
		self.initializingModules = nil
		if self.BuildConfig then
			self:BuildConfig()
		end
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
	elseif event == "PLAYER_LOGOUT" then
		-- Whatever table we have been editing is the one that must be saved.
		self:AdoptSavedVariables("PLAYER_LOGOUT")
		MelloUIDB = self.db
		if self.WriteBackup then
			self:WriteBackup("logout")
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if self:AdoptSavedVariables("PLAYER_ENTERING_WORLD") then
			self:RestartModules()
		end
		if not self.menuTipTimer then
			-- a few seconds in, after the login spam and a possible late settings load
			self.menuTipTimer = C_Timer.NewTimer(8, function() self:ShowMenuButtonTip() end)
		end
		-- Saved variables may still be on their way: keep checking for a while.
		if self.dbIsTemporary and not self.adoptTicker then
			local ticks = 0
			self.adoptTicker = C_Timer.NewTicker(1, function(ticker)
				ticks = ticks + 1
				if not self.dbIsTemporary then
					ticker:Cancel()
					self.adoptTicker = nil
					return
				end
				if self:AdoptSavedVariables("late poll " .. ticks .. "s") then
					self:RestartModules()
					self:Notice("Settings loaded late by the client and applied.")
					ticker:Cancel()
					self.adoptTicker = nil
				elseif ticks >= 60 then
					ticker:Cancel()
					self.adoptTicker = nil
				end
			end)
		end
	end
end)
