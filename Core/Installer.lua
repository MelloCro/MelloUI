--------------------------------------------------------------------------------
-- MelloUI - Installer: the engine and its data
--
-- The first-login installer is a front end over systems MelloUI already has,
-- not a second settings system:
--   - the profiles: the setup starts from the shipped profile ("MelloUI",
--     Media/Profiles.lua; 1.2.4: one for every skin), read from the
--     shipped table, never a saved copy;
--   - the settings path (NotifySettingChanged / SetModuleEnabled) inside ONE
--     MelloUI:Batch: one backup, at most one 'setting' Fire per key;
--   - Core/EditModeLayout.lua for the Edit Mode layout and MelloUI.LayoutFit
--     for the screen (every screen fitted from the 21:9 Immersive);
--   - the one position store (UI Modifications' `positions`) and Core's
--     mover registry for the window places.
-- This file is the engine and its data; the window is InstallerWindow.lua.
--
-- The UI scale is never changed here: the game's own scale is bugged on
-- this client (user, 2026-09-25), so it is only read, never set.
-- At login nothing is built but the one hidden event frame of the first-
-- login check (the end of this file): the rest is data and functions. The
-- countdown's event frame is made the first time a countdown starts.
--
-- A state is a whole set of settings:
--   { modules = { [module] = { key = value } }, enabled = { [module] = flag },
--     activeProfile = name }
-- A setup's TARGET is such a state, made from the player's current one and
-- the picked skin's shipped text with the picks over it, then applied in one
-- Batch and taken back exactly (the restore point, db.installer).
--
--   I.OPTIONS, I:Option(key)            the setup ("setup", 1.2.4: every
--                                       player picks the skin and the features
--                                       step by step; the four setups of
--                                       0.13.0 went) and the hidden refit,
--                                       "fit" (Fit to this screen: the layout
--                                       and the window places fitted again,
--                                       every other setting the player's own)
--   I.SETUP, I.SKINS                    the setup's steps after the skin and
--                                       the layout, and what each choice sets
--   I.SkinOf(draft), I:Offered(choice), I:DefaultPicks(), I:SetupDraft(picks)
--                                       the picks and the draft made of them
--   I.Kind(module), I.SwitchKey(module) what switches a module, and its key
--   I:FullText() -> text                the shipped setup (one for every skin)
--   I:Capture() -> state                every module's settings, exactly
--   I:TargetFromText(text[, cur])       defaults + text; the player's own
--                                       (personal) and NEVER keys = cur's
--   I:Draft(state, draft) -> state      a draft laid on (a Font Style first)
--   I:PaletteOf(option, draft) -> id    the palette the setup puts in (the
--                                       Review step names it)
--   I:TargetFor(option, draft, fit[, cur]) -> state
--   I:EffectiveOn(state, module)        its running state under that state
--   I:LayoutOn(option, draft, fit)      the fitted Edit Mode layout goes in
--   I:PlacesToTarget(target, fit, option, draft[, cur])
--   I:StartFit(option, draft, done) -> fit; I:CancelFit(fit)
--       the fitter (LayoutFit:Run: a frame's share at a time) on the setup's
--       own target, from the next frame on; done(fit) on a later frame,
--       fit = { option, W, H, done, fitted, places, report }
--   I:Apply(target, exact) -> changed
--   I:PlaceWindows() -> placed
--   I:LayoutRoom(fit[, fresh]) -> room, most   Edit Mode keeps one more
--                                       layout for the fitted one (one of its
--                                       name is replaced: no room needed);
--                                       kept on the fit (fit.room, fit.most)
--                                       until `fresh` or the window forgets it
--   I:InstallBlocked(option, draft, fit[, fresh]) -> why | nil   (the footer's line;
--                                       with the layout going in and no room
--                                       for it, TEXT.noRoom: before anything
--                                       is written)
--   I:Install(option, draft, fit) -> ok, why, changed   (a fault half way:
--                                       reported, reverted at once, why =
--                                       TEXT.failed; not put back: pending
--                                       stays with failed = true, why =
--                                       TEXT.revertFailed or failedStuck; a
--                                       fault while the target is made:
--                                       nothing written, TEXT.failedNothing)
--   I:Revert(reason) -> ok, why, reloadOwed   (reason "button", "timeout",
--                                       "error"; the exact apply, tried again
--                                       on a fault, then the 'Before install'
--                                       text through the profile load; why =
--                                       TEXT.revertFailed when nothing worked:
--                                       the pending answer then failed too,
--                                       revertFailed = true)
--   I:Keep() -> kept[, why]             (1.2.4: the window's Keep then
--                                       reloads the UI; false with no answer
--                                       owed; refused for a failed pending:
--                                       false, TEXT.keepFailed, or
--                                       TEXT.keepHalf after a failed revert)
--   I:StartCountdown([seconds]); I:Countdown() -> running, seconds, paused, why
--   I:ResumePending() -> waiting        an answer still owed from before a
--                                       /reload or a restart (the saved
--                                       settings keep it): the countdown
--                                       again with its full 15 s
--   I.cost = { install = ms, revert = ms }   the one long frame of each
--                                       (allowed and measured: user,
--                                       2026-09-25)
--   I.SESSION_AT, I:BeforeSession(rp)   when this session's Lua began (a
--                                       /reload starts a new one), and
--                                       whether a restore point was made
--                                       before it: the game has read the
--                                       installed start-up values since
--   I:Open([page]) -> shown; I:Busy() -> busy   the entry every caller
--                                       shares, and the first-login check
--                                       (the end of this file)
--   I.TEXT.installed / I.TEXT.refitted  the chat line after Install (Fit to
--                                       this screen: the layout was fitted,
--                                       nothing "installed")
-- The bus topic "installer" tells the window what happened:
--   ("installed", optionKey, notIn)         ("countdown", seconds, paused, why)
--   (notIn, 2.1.0: the line when Mello's Edit Mode layout was wanted and did not go in)
--   ("kept")                                ("reverted", reason, reloadOwed)
--   ("revertFailed", reason, why)
-- A draft is { ["Module.key"] = value, ["!Module"] = on, layout = on,
-- skin = name }: nothing is written until Install. A personal key a draft
-- sets goes in as set, and a revert takes it back (target.explicit, copied
-- onto the restore point).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Installer")
local C_Timer = Perf.C_Timer

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number

local pairs, ipairs, type, tostring, tonumber, pcall, next = pairs, ipairs, type, tostring, tonumber, pcall, next
local sort, ceil, floor, abs = table.sort, math.ceil, math.floor, math.abs

local I = { applying = false }
MelloUI.Installer = I

local UMB = "UIModifications"          -- the umbrella: its keys switch the kit panels and the folded features
local BEFORE_PROFILE = "Before install" -- the restore point on the Profiles page
local KEEP_SECONDS = 15
local EMPTY = {}
-- the modules holding a copy of Show Names As (UIModifications' ApplyNameFormat pushes it)
local NAME_COPIES = { "UnitFrames", "Nameplates" }

I.BEFORE_PROFILE, I.KEEP_SECONDS = BEFORE_PROFILE, KEEP_SECONDS   -- (the tests')
-- (compared with a restore point's `at`, time() when it was made)
I.SESSION_AT = tonumber(time and time()) or 0

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

-- keys no setup ever sets: the player's accessibility choice, and two
-- dropped keys a profile or share string from before may still bring:
-- `unlock` (the old Unlock the Windows mode, gone with Edit Layout, 0.15.0)
-- and the switch Tweaks lost (its one-time fold resets rows reading false);
-- and the player's own Group Frames work (one look, the user's answer to
-- F-v3's needs_user 8: Install leaves the indicator lists -- sets, started --
-- and the frames' part places -- parts, partyParts -- alone, Revert too)
-- (one look C13a: the folded masters' marks, <name>.qolFolded -- in a
-- profile's text so an older text is folded, never set by a setup)
local NEVER = { [UMB] = { reduceMotion = true, unlock = true, qol_Tweaks = true },
	GroupFrames = { sets = true, started = true, parts = true, partyParts = true }, Auras = { qolFolded = true },
	BarText = { qolFolded = true }, ClassIcons = { qolFolded = true }, CooldownText = { qolFolded = true } }

-- the installer's own facts about this machine and character, and a
-- one-time flag: the player's own like the keep lists' keys (never carried
-- by a setup, never taken back by one). Exact keys, or patterns with ^.
local OWN = { [UMB] = { seenVersion = true, layoutFitFor = true, layoutFitRev = true, layoutApplied = true, questTrackerKitMigrated = true,
	"^layoutAsked_" } }
-- of those, what an install that puts the layout in writes, and a revert puts back
local LAYOUT_OWN = { "layoutFitFor", "layoutFitRev", "layoutApplied" }

-- parchment areas whose sheet and dark ink belong to different modules: the
-- paper never shows while its ink's module is off (the parchment ink rule)
local INK = { chat = { sheet = "ChatPanel", ink = "Chat" } }
I.INK, I.NEVER = INK, NEVER   -- (read only: the tests read them)

-- keys a module's OnSettingChanged expands into others: written first
-- (written after the faces, the Font Style would flip to "custom")
local LEADERS = { Fonts = { "style" } }
-- values the game reads once at start-up: a change there owes a reload
-- (the names over heads and the combat text)
local STARTUP = { Fonts = { fontText = true, fontDamage = true } }
-- modules whose OnSettingChanged walks everything once per key: with 2 or
-- more keys to change they go off first and on last, so the walk runs once
local BUNDLE = { Fonts = true }

-- The setups: the one setup (1.2.4: the four of 0.13.0 -- Full experience, No reskin, Reskin only, Fresh start --
-- went with the installer's rebuild) and the refit. base "setup": the picked skin's shipped setup with the picks over
-- it (I:SetupDraft); refit: the player's own state as it is; layout: the fitted Edit Mode layout ("draft": the
-- picks', in when the fit passes); places: the fitter's window places; hidden: not offered as a setup (the refit has
-- its own entry: the configurator's Fit to this screen, when Mello's layout went in fitted to another screen size or
-- UI scale).
I.OPTIONS = {
	-- (1.2.4, the user, 2026-10-26: "the installer should also have the user go trough every step and picking and
	-- choosing the look, i would start with the look"; "everybody always goes trough the picking process, no more 1
	-- button full settings"; docs/plans/installer-steps.md) THE setup: the skin first, then the features, each step's
	-- answer in the draft; the picked skin's shipped setup with the picks laid over it (base "setup", I:SetupDraft)
	{ key = "setup", title = "MelloUI setup", base = "setup", layout = "draft", places = true,
	  steps = { "skin", "layout", "party", "quests", "combat", "chat", "minimap", "bags", "sound", "review", "keep" } },
	{ key = "fit", title = "Fit to this screen", hidden = true, refit = true,
	  desc = "Mello's layout and the window places fitted to this screen. Your other settings stay.",
	  layout = true, places = true, steps = { "fit", "review", "keep" } },
}
local OPTION = {}
for _, option in ipairs(I.OPTIONS) do
	OPTION[option.key] = option
end

function I:Option(key)
	if type(key) == "table" then
		return key
	end
	return OPTION[key]
end

-- (1.2.4) The setup's steps after the skin and the layout (the window draws its pages from these): a step's choices,
-- each one what it writes into the draft. kind "one": a card of several, its `set` laid into the draft; kind "many": a
-- switch each, its `modules` switched on or off (I.SwitchKey: a module's own flag or its folded switch). `extras`: the
-- switches under a "one" step's cards (`set`: one setting on or off, `modules` as a "many" step's, `only`: shown with
-- that card picked). `on`: a switch's first answer; `pick`: the step's first card (the recommended one). A choice
-- whose modules are not there (a feature addon switched off) is not offered. Every key is one of its own across the
-- steps (the window names each by it).
I.SETUP = {
	{ key = "party", kind = "one", pick = "group", choices = {
		{ key = "group", set = { ["GroupFrames.partyStyle"] = "group" }, modules = { "GroupFrames" } },
		{ key = "portraits", set = { ["GroupFrames.partyStyle"] = "party" }, modules = { "GroupFrames" } } },
	  extras = {
		{ key = "yourself", on = true, set = "GroupFrames.showPlayer", modules = { "GroupFrames" } },
		{ key = "flip", on = false, set = "UnitFrames.partyFlip", only = "portraits", modules = { "UnitFrames" } },
		{ key = "markers", on = false, modules = { "PartyMarkers" } } } },
	{ key = "quests", kind = "many", choices = {
		{ key = "tracker", modules = { "QuestTracker" } }, { key = "questlist", modules = { "QuestList" } },
		{ key = "route", modules = { "Route" } }, { key = "map", modules = { "Map" } },
		{ key = "voice", modules = { "VoiceOver" } }, { key = "services", modules = { "Services" } },
		{ key = "dungeon", modules = { "DungeonInfo" } } } },
	{ key = "combat", kind = "many", choices = {
		{ key = "nameplates", modules = { "Nameplates" } }, { key = "combattext", modules = { "CombatText" } },
		{ key = "meter", modules = { "Meter" } }, { key = "effects", modules = { "FrameEffects", "HealFlight" } },
		{ key = "prd", modules = { "PersonalDisplay" } } } },
	{ key = "chat", kind = "one", pick = "view", choices = {
		{ key = "view", set = { ["Chat.view"] = "minimal" }, modules = { "Chat" } },
		{ key = "plainchat", set = { ["Chat.view"] = "game" }, modules = { "Chat" } } } },
	{ key = "minimap", kind = "many", choices = {
		{ key = "column", modules = { "MinimapPanel" } }, { key = "reminders", modules = { "Reminders" } },
		{ key = "widgets", modules = { "Widgets" } } } },
	{ key = "bags", kind = "one", pick = "kinds", choices = {
		{ key = "kinds", set = { ["!BagWindow"] = true }, modules = { "BagWindow" } },
		{ key = "separate", set = { ["!BagWindow"] = false }, modules = { "BagWindow" } } },
	  -- (needs: { step, choice } the window ticks too when this one is ticked: Restock's reminder is the Reminders
	  -- widget's; its shop list works without it, so Reminders off leaves Restock be)
	  extras = { { key = "gains", on = true, modules = { "Gains" } },
		{ key = "restock", on = true, modules = { "Restock" }, needs = { "minimap", "reminders" } },
		{ key = "discard", on = true, modules = { "Discard" } } } },
	-- (1.2.4, the user, 2026-10-28: "The Default Profile should use games own sounds so nothing changes there": the
	-- recommended card follows the skin, `pickFor`; Custom Sounds plays nothing under the Default skin either way)
	{ key = "sound", kind = "one", pick = "melloSound", pickFor = { default = "gameSound" }, choices = {
		{ key = "melloSound", set = { ["!CustomSounds"] = true }, modules = { "CustomSounds" } },
		{ key = "gameSound", set = { ["!CustomSounds"] = false }, modules = { "CustomSounds" } } } },
}
I.SKINS = { "default", "modern", "oldschool" }

-- the lines the window shows (its footer, the Keep page)
I.TEXT = {
	loading = "MelloUI's settings are still loading; try again in a moment.",
	combat = "Install waits until you are out of combat.",
	editMode = "Close Edit Mode first.",
	fitting = "Your screen is still being fitted.",
	refit = "Your screen changed; it is being fitted again.",
	noRoom = "Edit Mode already keeps %d account layouts, the most it can. Delete one in Edit Mode, or keep your own layout.",
	pending = "Keep or revert the setup you just installed first.",
	nothing = "There is no setup to go back to.",
	pausedCombat = "Paused while you are in combat.",
	revertCombat = "Revert waits until you are out of combat; try again then.",   -- (the configurator's Revert...)
	pausedEditMode = "Paused while Edit Mode is open.",
	installed = "%s installed. Keep it, or MelloUI goes back to 'Before install' when the timer runs out.",
	-- (Fit to this screen: nothing is installed, the layout is fitted)
	refitted = "Your layout was fitted to this screen. Keep it, or MelloUI goes back to 'Before install' when the timer runs out.",
	-- (2.1.0, el-15) Mello's Edit Mode layout wanted, but the game did not take it: said, never silent
	layoutNotIn = "MelloUI's Edit Mode layout did not go in (%s). Your own layout stays; /mello layout check shows why.",
	noFit = "the screen was not fitted",   -- (the layout's reason when no fit answered)
	reverted = "Back to 'Before install'.",
	failed = "Something went wrong while installing, so MelloUI went back to 'Before install'.",
	failedStuck = "Something went wrong while installing. Use Revert to go back to 'Before install'.",
	failedNothing = "Something went wrong while preparing the setup. Nothing was changed.",
	revertFailed = "MelloUI could not go all the way back to 'Before install'. Type /reload to try again.",
	keepFailed = "This setup did not install fully, so it cannot be kept. Revert goes back to 'Before install'.",
	keepHalf = "MelloUI was only partly put back, so this setup cannot be kept. Revert tries again to go back to 'Before install'.",
	cost ="%s: %.1f ms in one frame.",   -- (the log only: /mellolog)
	-- the entries and the first login (chat lines, the alt's question)
	openCombat = "The installer opens when combat ends.",
	openEditMode = "Close Edit Mode first, then open the installer again.",
	whatsNew = "Version %s. /mello shows what's new; Install... there sets MelloUI up again.",
	altQuestion = "Use MelloUI's Edit Mode layout on this character too?\n\nYour own layouts stay in Edit Mode's list. Later: /mello layout apply.",
	altYes = "Use it",
	altNo = "Not now",
	-- (the Gamepad UI on: the question waits for a login with the mouse UI;
	-- never /mello layout apply here, which fits and saves the account's
	-- shared layout again, where Use it only makes it active)
	altGamepad = "MelloUI's Edit Mode layout is not active on this character: pick it in Edit Mode's layout list, or log in without the Gamepad UI to be asked.",
}
local TEXT = I.TEXT

--------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------

-- Settings are plain values and shallow tables. A table met twice (a
-- module that kept a table pointing at itself) is copied once, so a copy
-- never runs away; a comparison deeper than any setting compares identity.
local function Copy(v, done)
	if type(v) ~= "table" then
		return v
	end
	local t = done[v]
	if t then
		return t
	end
	t = {}
	done[v] = t
	for k, x in pairs(v) do
		t[k] = Copy(x, done)
	end
	return t
end

local function DeepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	return Copy(v, {})
end
I.DeepCopy = DeepCopy

local MAX_DEPTH = 16

local function Same(a, b, depth)
	if type(a) ~= "table" or type(b) ~= "table" or a == b then
		return a == b
	end
	if depth > MAX_DEPTH then
		return false
	end
	for k, x in pairs(a) do
		if not Same(x, b[k], depth + 1) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function Equal(a, b)
	return Same(a, b, 0)
end
I.Equal = Equal

-- the string keys of a and b, once each, sorted (an apply writes in a fixed order)
local function SortedUnion(a, b)
	local keys, seen = {}, {}
	for k in pairs(a or EMPTY) do
		if type(k) == "string" and not seen[k] then
			seen[k] = true
			keys[#keys + 1] = k
		end
	end
	for k in pairs(b or EMPTY) do
		if type(k) == "string" and not seen[k] then
			seen[k] = true
			keys[#keys + 1] = k
		end
	end
	sort(keys)
	return keys
end

--------------------------------------------------------------------------------
-- What a module is (read from the registry at call time)
--------------------------------------------------------------------------------

-- "panel": a kit panel, switched by UI Modifications' key of its name;
-- "tweak": a folded feature, qol_<name>, on unless false; "tweakOff": the
-- same, off unless true; "always": folded, no switch; "rows": folded, its
-- rows its switches (`switches`: Buffs & Debuffs' three -- one look, the
-- user's A: one switch here writes them together); "module": its own flag
local function Kind(m)
	local tweak = m and m.tweak
	if type(tweak) == "table" then
		if tweak.always then
			return type(m.switches) == "table" and "rows" or "always"
		end
		return (tweak.off and "tweakOff") or "tweak"
	elseif m and m.hidden and type(m.window) == "table" then
		return "panel"
	end
	return "module"
end
I.Kind = Kind

-- the draft key that switches a module: its own flag, or UI Modifications'
-- qol_<name> for a folded feature, or <name>.@on for one whose rows are its
-- switches (Overlay writes them all) (nil: a kit panel, or one with no
-- switch)
local function SwitchKey(m)
	local kind = m and Kind(m)
	if kind == "module" then
		return "!" .. m.name
	elseif kind == "tweak" or kind == "tweakOff" then
		return UMB .. ".qol_" .. m.name
	elseif kind == "rows" then
		return m.name .. ".@on"
	end
	return nil
end
I.SwitchKey = SwitchKey

local function Module(name)
	return MelloUI.modules[name]
end

-- the installer's own keys (OWN): exact, or a pattern
local function Own(name, key)
	local own = OWN[name]
	if not own or type(key) ~= "string" then
		return false
	end
	if own[key] then
		return true
	end
	for i = 1, #own do
		if key:find(own[i]) then
			return true
		end
	end
	return false
end

-- a key no setup changes: the player's own (the keep lists, and the
-- installer's own facts) and the NEVER keys
local function Kept(name, key)
	if MelloUI:IsPersonalKey(name, key) or Own(name, key) then
		return true
	end
	local never = NEVER[name]
	return never and never[key] or false
end
I.Kept = Kept

-- a module's own flag in a state (nil: its enabledByDefault)
local function Flag(state, name)
	local f = state.enabled[name]
	if f == nil then
		local m = Module(name)
		return m and m.enabledByDefault and true or false
	end
	return f and true or false
end

-- a module's running state as a state's settings give it
function I:EffectiveOn(state, name)
	local m = Module(name)
	if not m then
		return false
	end
	local kind = Kind(m)
	if kind == "module" then
		return Flag(state, name)
	end
	if not Flag(state, UMB) then
		return false
	end
	local um = state.modules[UMB] or EMPTY
	if kind == "panel" then
		return um.reskin ~= false and um[name] ~= false
	elseif kind == "always" or kind == "rows" then
		-- (one whose rows are its switches runs with UI Modifications: with
		-- them all off it makes nothing -- I:FeatureOn reads the rows)
		return true
	elseif kind == "tweakOff" then
		return um["qol_" .. name] == true
	end
	return um["qol_" .. name] ~= false
end

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

-- the shipped setup: never db.profiles.MelloUI (a player's own save of that
-- name, or an older shipped copy, could stand in for it). (1.2.4, the user
-- 2026-10-28: "make sure that all 3 Themes follow the same Profiles, no more
-- separate profiles depending on the Theme") One for every skin, Oldschool's
-- painted reskin's settings in it: the Skin step only sets the skin over it
-- (I:SetupDraft)
function I:FullText()
	local shipped = MelloUI:ShippedProfiles()[MelloUI:FullProfileName()]
	return type(shipped) == "string" and shipped or ""
end

function I:Capture()
	local db = MelloUI.db
	local s = { modules = {}, enabled = DeepCopy(db.enabled), activeProfile = db.activeProfile }
	for name in MelloUI:IterateModules() do
		s.modules[name] = DeepCopy(MelloUI:GetModuleDB(name))
	end
	return s
end

-- the player's own and NEVER keys: always the current ones (nil stays nil)
local function KeepUntouched(t, cur)
	for name in MelloUI:IterateModules() do
		local tm, cm = t.modules[name], cur.modules[name] or EMPTY
		if not tm then
			tm = {}
			t.modules[name] = tm
		end
		for key in pairs(tm) do
			if Kept(name, key) then
				tm[key] = DeepCopy(cm[key])   -- (nil when the player has none: a key's value set, never a new key)
			end
		end
		for key, v in pairs(cm) do
			if tm[key] == nil and Kept(name, key) then
				tm[key] = DeepCopy(v)
			end
		end
	end
	return t
end

-- The text read into a state of its own (every module's defaults, then the
-- text, by the same reader as a profile load: DeserializeSettings with its
-- `into`, so the live settings are never touched)
function I:TargetFromText(text, cur)
	cur = cur or self:Capture()
	local state = { modules = {}, enabled = {} }
	for name, m in MelloUI:IterateModules() do
		state.modules[name] = MelloUI.ApplyDefaults({}, m.defaults)
	end
	if type(text) == "string" and text ~= "" then
		MelloUI:DeserializeSettings(text, state)
	end
	return KeepUntouched(state, cur)
end

-- { ["Module.key"] = v, ["!Module"] = on } laid over a copy of a state
local function Overlay(state, set)
	local s = DeepCopy(state)
	for spec, value in pairs(set or EMPTY) do
		if type(spec) == "string" then
			local flag = spec:match("^!(.+)$")
			if flag then
				s.enabled[flag] = value and true or false
			else
				local name, key = spec:match("^([^.]+)%.(.+)$")
				local m = key == "@on" and Module(name)
				if m and type(m.switches) == "table" then
					-- (a module whose rows are its switches: all of them)
					s.modules[name] = s.modules[name] or {}
					for _, row in ipairs(m.switches) do
						s.modules[name][row] = value and true or false
					end
				elseif name then
					s.modules[name] = s.modules[name] or {}
					s.modules[name][key] = DeepCopy(value)
				end
			end
		end
	end
	return s
end
I.Overlay = Overlay

-- A draft on a state: a leader the draft sets is expanded first (a Font
-- Style fills in its faces and sizes only inside Fonts' OnSettingChanged,
-- and only while Fonts is on), then the draft's own keys go over it
function I:Draft(state, draft)
	local s = DeepCopy(state)
	local style = draft and draft["Fonts.style"]
	local expand = MelloUI.FontStyleSettings
	if style ~= nil and type(expand) == "function" then
		local ok, set = pcall(expand, style)
		if ok and type(set) == "table" then
			s.modules.Fonts = s.modules.Fonts or {}
			for k, v in pairs(set) do
				s.modules.Fonts[k] = DeepCopy(v)
			end
		end
	end
	return Overlay(s, draft)
end

-- (1.2.4) The setup's picks and its draft. Picks are the window's answers: { skin = "default" | "modern" | "oldschool",
-- layout = "mello" | "own", [a "one" step] = its card's key, [a "many" step] = { [choice] = on }, x = { [extra] = on } }.
--   I.SkinOf(draft) -> skin        the draft's skin: Oldschool only while MelloUI_Oldschool is there, Modern otherwise
--   I:Offered(choice) -> on        a choice's modules are all there (a feature addon off: not offered)
--   I:DefaultPicks() -> picks      every step at its first answer: Modern, Mello's layout, every feature on
--   I:RecommendedPick(st, skin) -> key   a "one" step's recommended card under a skin (the sound step: the game's
--                                  own under Default); I:SkinPicked(picks, was) moves the answers that follow it
--   I:SetupDraft(picks) -> draft   the picks as the setup's draft (draft.skin, draft.layout and the settings)
function I.SkinOf(draft)
	local skin = type(draft) == "table" and draft.skin or "modern"
	return MelloUI.Skin.Offered(skin) and skin or "modern"
end

function I:Offered(choice)
	for _, name in ipairs(choice.modules or EMPTY) do
		if not (Module(name) and SwitchKey(Module(name))) then
			return false
		end
	end
	return true
end

-- a "one" step's recommended card under a skin: its `pickFor` for that skin, else its `pick`
function I:RecommendedPick(st, skin)
	return st.pickFor and st.pickFor[skin] or st.pick
end

-- the skin picked (`was`: the skin before): each step whose recommendation follows the skin moves its answer along,
-- unless the player had picked another card (an answer that is not the old recommendation stays)
function I:SkinPicked(picks, was)
	local skin = self.SkinOf(picks)
	for _, st in ipairs(self.SETUP) do
		if st.pickFor and picks[st.key] == self:RecommendedPick(st, was) then
			picks[st.key] = self:RecommendedPick(st, skin)
		end
	end
end

function I:DefaultPicks()
	local picks = { skin = "modern", layout = "mello", x = {} }
	for _, st in ipairs(self.SETUP) do
		if st.kind == "many" then
			picks[st.key] = {}
			for _, c in ipairs(st.choices) do
				picks[st.key][c.key] = true
			end
		else
			picks[st.key] = st.pick
		end
		for _, x in ipairs(st.extras or EMPTY) do
			picks.x[x.key] = x.on and true or false
		end
	end
	return picks
end

-- the modules' switches on or off into a draft
local function SwitchInto(d, modules, on)
	for _, name in ipairs(modules or EMPTY) do
		local key = SwitchKey(Module(name))
		if key then
			d[key] = on and true or false
		end
	end
end

function I:SetupDraft(picks)
	picks = type(picks) == "table" and picks or self:DefaultPicks()
	-- (Mello's layout: in when the fit passes, I:LayoutOn; Keep my layout: never -- 2.1.29: false set apart, as
	-- 1.2.4's `and false or nil` gave nil and Keep my layout put Mello's in all the same)
	local d = { skin = picks.skin }
	if picks.layout == "own" then
		d.layout = false
	end
	local skin = self.SkinOf(d)
	d.skin = skin
	-- the skin, whole: its settings and the switches it needs (MelloUI.Skin.SETS, the same as Look > General's Skin)
	for spec, v in pairs(MelloUI.Skin.SETS[skin]) do
		d[spec] = v
	end
	local x = type(picks.x) == "table" and picks.x or EMPTY
	for _, st in ipairs(self.SETUP) do
		local answer = picks[st.key]
		for _, c in ipairs(st.choices) do
			if self:Offered(c) then
				if st.kind == "many" then
					SwitchInto(d, c.modules, type(answer) == "table" and answer[c.key])
				elseif answer == c.key then
					for spec, v in pairs(c.set or EMPTY) do
						d[spec] = v
					end
				end
			end
		end
		for _, e in ipairs(st.extras or EMPTY) do
			if self:Offered(e) and not (e.only and answer ~= e.only) then
				if type(e.set) == "string" then
					d[e.set] = x[e.key] and true or false
				else
					SwitchInto(d, e.modules, x[e.key])
				end
			end
		end
	end
	return d
end

-- The palette a setup puts in (the Review step names it): the modern look's
-- Gilded Slate for the Default and Modern skins (the painted reskin off),
-- the shipped setup's for the Oldschool skin, else the one in use (the refit keeps
-- the player's). An id of MelloUI.Palettes (an unknown one is Ember, as Core
-- reads it). The shipped one is read from its text once: the shipped text
-- never changes in a session.
do
	local NO_STATE = { modules = {}, enabled = {} }   -- (Full's alone: no player's keys laid over it)
	local fullPalette = nil
	local function FullPalette(self)
		if fullPalette == nil then
			local ok, t = pcall(self.TargetFromText, self, self:FullText(), NO_STATE)
			local um = ok and type(t) == "table" and t.modules[UMB]
			fullPalette = type(um) == "table" and um.palette or false
		end
		return fullPalette or nil
	end

	function I:PaletteOf(option, draft)
		option = self:Option(option)
		-- (0.25.0) the painted reskin's palettes only with MelloUI_Oldschool there and the reskin the setup leaves on
		-- (MelloUI:PaintedPalettes once it is in): else the modern look's Gilded Slate
		local oldschool = rawget(MelloUI, "Oldschool")
		local reskinOff = type(draft) == "table" and draft[UMB .. ".reskin"] == false
		if type(oldschool) ~= "table" or oldschool.refused or reskinOff then
			return "gildedSlate"
		end
		if not option then
			return "ember"
		elseif option.base == "setup" then
			return MelloUI:KnownPalette(FullPalette(self))
		end
		return MelloUI:PaletteId()
	end
end

-- a draft's personal keys ("Module.key" the module keeps as the player's
-- own, not the installer's facts nor a NEVER key): { [module] = { [key] =
-- true } }, or nil when it sets none
local function ExplicitOf(draft)
	local explicit
	for spec in pairs(draft or EMPTY) do
		local name, key
		if type(spec) == "string" then
			name, key = spec:match("^([^.!]+)%.(.+)$")
		end
		if name and MelloUI:IsPersonalKey(name, key) and not Own(name, key) and not (NEVER[name] and NEVER[name][key]) then
			explicit = explicit or {}
			explicit[name] = explicit[name] or {}
			explicit[name][key] = true
		end
	end
	return explicit
end

-- whether a target sets this kept key itself (a personal key its draft sets)
local function Explicit(target, name, key)
	local explicit = type(target) == "table" and target.explicit
	local keys = type(explicit) == "table" and explicit[name]
	return (type(keys) == "table" and keys[key]) and true or false
end

-- a parchment area whose sheet shows while its ink's module is off: the
-- paper goes (the parchment ink rule)
local function InkGuard(self, t)
	local um = t.modules[UMB]
	if not um then
		return t
	end
	for area, who in pairs(INK) do
		local key = "parchment_" .. area
		if um[key] == true and self:EffectiveOn(t, who.sheet) and not self:EffectiveOn(t, who.ink) then
			um[key] = false
		end
	end
	return t
end

-- Chat's background opacity: the chat reskin applies it with Chat Tweaks off
-- too (user, 2026-09-26: a new character's painted chat stone was nearly
-- see-through), so a setup with the chat reskin on and Chat Tweaks off
-- carries the shipped setup's two rows as its text has them (a row the
-- draft sets stays the draft's).
local RESKIN_ALPHA_ROWS = { "windowAlphaOn", "windowAlpha" }
local function ReskinAlpha(self, t, full, cur, draft)
	if not self:EffectiveOn(t, "ChatPanel") or self:EffectiveOn(t, "Chat") then
		return
	end
	full = full or self:TargetFromText(self:FullText(), cur)
	local from = full.modules.Chat or EMPTY
	t.modules.Chat = t.modules.Chat or {}
	for _, key in ipairs(RESKIN_ALPHA_ROWS) do
		if draft == nil or draft["Chat." .. key] == nil then
			t.modules.Chat[key] = DeepCopy(from[key])
		end
	end
end

-- the setup's whole target. fit: the Screen step's result (nil: no fit, so
-- no layout); cur: the current state when already captured. forFit (the
-- fitter's own read, BeginFit): the target as the fitted layout would have
-- it, without the fitter's places and without the player's own Edit Mode
-- frame places (the fit models the layout going in)
local function Target(self, option, draft, fit, cur, forFit)
	option = self:Option(option)
	assert(option, "MelloUI.Installer:TargetFor needs a setup")
	cur = cur or self:Capture()
	local t
	if option.refit then
		t = DeepCopy(cur)
	else
		-- (1.2.4) the shipped setup (Mello's settings for everything, one for every skin), the picks over it: the skin,
		-- a feature switched off, the party's frames, the chat's view (I:SetupDraft)
		local full = self:TargetFromText(self:FullText(), cur)
		t = self:Draft(full, draft or EMPTY)
		t.explicit = ExplicitOf(draft)
		ReskinAlpha(self, t, full, cur, draft)
	end
	t.activeProfile = nil
	if not forFit then
		self:PlacesToTarget(t, fit, option, draft, cur)
	end
	InkGuard(self, t)
	KeepUntouched(t, cur)
	-- the personal keys the draft sets itself (the player choosing their own
	-- preference) go in as set
	for name, keys in pairs(t.explicit or EMPTY) do
		for key in pairs(keys) do
			t.modules[name] = t.modules[name] or {}
			t.modules[name][key] = DeepCopy(draft[name .. "." .. key])
		end
	end
	-- the name form's two copies follow Show Names As (user, 2026-09-30:
	-- after a fresh install the frames kept the setup's "last" while Show
	-- Names As said the draft's pick): a draft sets only Show Names As,
	-- and the apply's reconcile would put an older copy back over its push
	local form = (t.modules[UMB] or EMPTY).nameFormat
	for _, name in ipairs(NAME_COPIES) do
		local copy = t.modules[name]
		if form ~= nil and type(copy) == "table" then
			copy.nameFormat = form
		end
	end
	return t
end

function I:TargetFor(option, draft, fit, cur)
	return Target(self, option, draft, fit, cur, false)
end

--------------------------------------------------------------------------------
-- The screen: the fitter's result into the target
--------------------------------------------------------------------------------

-- whether the setup puts the fitted Edit Mode layout in: the Screen step's
-- switch (draft.layout) when set, else on after a pass and off after a FAIL
function I:LayoutOn(option, draft, fit)
	option = self:Option(option)
	if not (option and option.layout) or type(fit) ~= "table" or type(fit.fitted) ~= "table" then
		return false
	end
	local wanted = draft and draft.layout
	if wanted ~= nil then
		return wanted and true or false
	end
	-- (2.1.0, el-15) in even on a FAIL: on the screen the layout is drawn for (report.drawn), and on any other the fit's
	-- closest try (report.adapted: scaled to the screen where that came closer) -- its overlaps said on the Layout step;
	-- the player is never left on the game's own layout (the user, 2026-11-01). Out only for a layout the fit could not
	-- read or the player's own pick
	local report = fit.report
	return type(report) == "table" and (report.pass or ((report.drawn or report.adapted) and type(fit.fitted) == "table"))
		and true or false
end

-- whether Install must wait for the fit: the window places, or the layout
local function NeedsFit(option, draft)
	if option.places then
		return true
	end
	return option.layout and not (draft and draft.layout == false) and true or false
end

-- a store place of what Edit Mode's layout places: the four frames (the
-- fitter's own list, LayoutFit.EDIT_MODE_FRAMES: one list, never a copy
-- here) and Edit Layout's EditMode.<system>.<index> copies
local function EditModePlace(key)
	if type(key) ~= "string" then
		return false
	end
	if key:find("^EditMode%.%-?%d+%.%-?%d+$") then
		return true
	end
	-- (fr-18) the places of MelloUI's own status bars and bag bar: kept with the player's own layout; a profile that
	-- brings none leaves ours to take its layout's places for the game's frames at the next login (MelloUI.OwnBars)
	local own = MelloUI.OwnBars
	if own and own.IsKey(key) then
		return true
	end
	local LayoutFit = MelloUI.LayoutFit
	for _, name in ipairs(type(LayoutFit) == "table" and type(LayoutFit.EDIT_MODE_FRAMES) == "table"
		and LayoutFit.EDIT_MODE_FRAMES or EMPTY) do
		if name == key then
			return true
		end
	end
	return false
end

-- (2.1.0, el-15; the user, 2026-11-01, of pr-04's question: "Yes, keep them too (Recommended)") a place of MelloUI's
-- own elements in Core's store: no Edit Mode place (EditModePlace, the own bars with them) and none of the game's
-- windows or Edit Mode frames (LayoutFit.IsGameKey) -- Gains, the notice, the widget column, Combat Text, the meter,
-- the Personal Display, the group frames, the unit frames' own places
local function OwnElementPlace(key)
	if type(key) ~= "string" or EditModePlace(key) then
		return false
	end
	local LayoutFit = MelloUI.LayoutFit
	return not (type(LayoutFit) == "table" and type(LayoutFit.IsGameKey) == "function" and LayoutFit.IsGameKey(key))
end

-- Edit Mode keeps the player's own layout: its frames' store places, Edit
-- Layout's copies and the tracker's own place as the player has them (the
-- shipped text's are for the shipped layout; its whole store would go in);
-- (2.1.0) and every place the player gave MelloUI's own elements (OwnElementPlace: none given, the profile's).
-- Returns the keys kept (keys[key] = true), which the window places then leave alone
local function KeepOwnLayoutPlaces(target, cur)
	local um = target.modules[UMB]
	local have = (cur.modules[UMB] or EMPTY).positions
	have = type(have) == "table" and have or EMPTY
	local LayoutFit = MelloUI.LayoutFit
	local keys = {}   -- (the keys in order, each also as keys[key] = true)
	for _, key in ipairs(type(LayoutFit) == "table" and type(LayoutFit.EDIT_MODE_FRAMES) == "table"
		and LayoutFit.EDIT_MODE_FRAMES or EMPTY) do
		keys[#keys + 1], keys[key] = key, true
	end
	for key in pairs(type(um.positions) == "table" and um.positions or EMPTY) do
		if EditModePlace(key) and not keys[key] then
			keys[#keys + 1], keys[key] = key, true
		end
	end
	-- (fr-18) the player's own places of MelloUI's own status bars and bag bar, whether the profile names them or not
	local own = MelloUI.OwnBars
	for key in pairs(own and have or EMPTY) do
		if own.IsKey(key) and not keys[key] then
			keys[#keys + 1], keys[key] = key, true
		end
	end
	for key, p in pairs(have) do
		if p ~= nil and OwnElementPlace(key) and not keys[key] then
			keys[#keys + 1], keys[key] = key, true
		end
	end
	for _, key in ipairs(keys) do
		local p = have[key]
		if p ~= nil or type(um.positions) == "table" then
			if type(um.positions) ~= "table" then
				um.positions = {}
			end
			um.positions[key] = DeepCopy(p)
		end
	end
	local pos = (cur.modules.QuestTracker or EMPTY).pos
	if target.modules.QuestTracker or pos ~= nil then
		target.modules.QuestTracker = target.modules.QuestTracker or {}
		target.modules.QuestTracker.pos = DeepCopy(pos)
	end
	return keys
end

-- The fitter's places into the target (inside the one Batch like every
-- other setting). With the layout: the four Edit Mode frames' store places
-- removed, the tracker's own place cleared and its sizes (1.2.4: MelloUI's
-- places win, LayoutFit's ownPlaces -- the fit removes none of them and keeps
-- the tracker's own place, fitted to this screen; PlaceWindows puts them over
-- the layout once it is in), the window
-- places, the buff rows by the minimap's column (Icons
-- Per Row, Icon Size) as the fit wrapped them. Without it (the player's own layout kept, a FAIL,
-- no fit): only the window places; Edit Mode
-- still holds the player's own layout, so its four frames' store places and
-- the tracker's own place stay as the player has them (cur: the current
-- state; without it the target's are left). (layoutFitFor is the machine's
-- own fact: Install writes it.)
function I:PlacesToTarget(target, fit, option, draft, cur)
	option = self:Option(option)
	local um = target.modules[UMB]
	if not (option and um) then
		return target
	end
	local places = type(fit) == "table" and type(fit.places) == "table" and fit.places or nil
	local layoutOn = self:LayoutOn(option, draft, fit)
	local kept
	if not layoutOn and type(cur) == "table" then
		kept = KeepOwnLayoutPlaces(target, cur)
	end
	if not (places and (option.places or layoutOn)) then
		return target
	end
	local store = type(um.positions) == "table" and um.positions or {}
	um.positions = store
	-- (el-11) the places are this screen's now: the profile's screen of origin goes (a later refit reads layoutFitFor)
	um.placesFor = nil
	if option.places then
		for key, p in pairs(type(places.windows) == "table" and places.windows or EMPTY) do
			if not (kept and kept[key]) then   -- (2.1.0: a place the player's own layout keeps)
				store[key] = DeepCopy(p)
			end
		end
	end
	if layoutOn then
		for _, key in ipairs(type(places.remove) == "table" and places.remove or EMPTY) do
			store[key] = nil
		end
		-- (1.2.4: MelloUI's places of what the layout places, as the fit kept them on this screen: they win over it)
		for key, p in pairs(type(places.own) == "table" and places.own or EMPTY) do
			store[key] = DeepCopy(p)
		end
		local qt, t = places.questTracker, target.modules.QuestTracker
		if type(qt) == "table" and t then
			if qt.clearPos then
				t.pos = nil
			elseif type(qt.pos) == "table" then
				t.pos = DeepCopy(qt.pos)   -- (1.2.4: its own place wins, as the fit kept it on this screen)
			end
			if qt.maxHeight ~= nil then
				t.maxHeight = qt.maxHeight
			end
			if qt.width ~= nil then
				t.width = qt.width
			end
		end
		-- the buff rows by the minimap's column as the fit wrapped them (the
		-- fit asked for them: BeginFit's auras.fitRows); the layout was
		-- fitted for these rows, so they go in only with it
		local rows, a = places.auras, target.modules.Auras
		if type(rows) == "table" and a then
			if rows.playerPerRow ~= nil then
				a.playerPerRow = rows.playerPerRow
			end
			if rows.playerSize ~= nil then
				a.playerSize = rows.playerSize
			end
		end
		-- the Minimap Kit's Width and Height a step smaller where the fit
		-- made room so (BeginFit's column.fitMap), with the layout alone
		local map, mp = places.minimap, target.modules.MinimapPanel
		if type(map) == "table" and mp and map.width ~= nil and map.height ~= nil then
			mp.width, mp.height = map.width, map.height
		end
	end
	return target
end

-- read(module, key) over a state for the fitter's inputs; read(module):
-- whether it runs
local function Reader(self, state)
	return function(name, key)
		if key == nil then
			return self:EffectiveOn(state, name)
		end
		local m = state.modules[name]
		return m and m[key]
	end
end

-- the approved layout's info (Core/EditModeLayout.lua; the baked string
-- converted here while that file has no EditModeLayoutInfo). (1.2.4) One for
-- every skin, as the shipped profile is: its places were fitted for it.
local function LayoutInfo()
	if MelloUI.EditModeLayoutInfo then
		local ok, info = pcall(MelloUI.EditModeLayoutInfo, MelloUI)
		return ok and type(info) == "table" and info or nil
	end
	local data = MelloUI:ShippedEditMode()
	if type(data) ~= "table" or type(data.layout) ~= "string" or not (C_EditMode and C_EditMode.ConvertStringToLayoutInfo) then
		return nil
	end
	local ok, info = pcall(C_EditMode.ConvertStringToLayoutInfo, data.layout)
	if not (ok and type(info) == "table") then
		return nil
	end
	info.layoutName = data.name
	return info
end

local function ScreenSize()
	local LayoutFit = MelloUI.LayoutFit
	if LayoutFit and LayoutFit.ScreenSize then
		return LayoutFit:ScreenSize()
	end
	return nil
end

-- the fitter's answer on the fit (and the caller's done)
local function Fitted(fit, fitted, places, report)
	fit.fitted, fit.places, fit.report, fit.done, fit.job = fitted, places, report, true, nil
	local done = fit.onDone
	fit.onDone = nil
	if done then
		local ok, err = pcall(done, fit)
		if not ok then
			local handler = geterrorhandler and geterrorhandler()
			if type(handler) == "function" then
				handler(err)
			end
		end
	end
end

-- (el-11) the own sizes of the registered frames the places name, [key] =
-- { w, h }: the fitter keeps each place as far from its side of the screen
-- (LayoutFit's F0s), which needs the frame's middle; one it cannot read
-- plainly is left out (it then counts as its anchor point)
local function PlaceSizes(positions)
	local sizes = {}
	if type(positions) ~= "table" or not MelloUI.MoverEntries then
		return sizes
	end
	for _, entry in ipairs(MelloUI:MoverEntries() or EMPTY) do
		local frame = entry.key ~= nil and positions[entry.key] ~= nil and entry.frame
		if frame and frame.GetSize then
			local ok, w, h = pcall(frame.GetSize, frame)
			w, h = ok and Num(w) or nil, ok and Num(h) or nil
			if w and h and w > 0 and h > 0 then
				sizes[entry.key] = { w, h }
			end
		end
	end
	return sizes
end

-- the frame after StartFit: the setup's target read into the fitter's inputs
-- (1-2 ms, kept out of the click's frame), then the fitter's own frames.
-- (el-11) Places made on another screen follow this one's shape: the shipped
-- profile's say where they were made (UIModifications.placesFor, read by
-- LayoutFit:Inputs); the refit's are the player's own, fitted for the screen
-- their layout went in for (layoutFitFor)
local function BeginFit(fit)
	if fit.cancelled then
		return
	end
	local LayoutFit = MelloUI.LayoutFit
	local read = Reader(I, Target(I, fit.option, fit.draft, nil, nil, true))
	local inputs = LayoutFit:Inputs(read)
	if type(inputs) == "table" then
		local option = I:Option(fit.option)
		if inputs.placesFor == nil and option and option.refit then
			inputs.placesFor = read(UMB, "layoutFitFor")
		end
		inputs.sizes = PlaceSizes(inputs.positions)
	end
	-- (the installer writes the buff rows the fit wraps and the minimap's
	-- Width and Height it steps down: I:PlacesToTarget)
	if type(inputs) == "table" and type(inputs.auras) == "table" then
		inputs.auras.fitRows = true
	end
	if type(inputs) == "table" and type(inputs.column) == "table" then
		inputs.column.fitMap = true
	end
	fit.W, fit.H = ScreenSize()
	fit.job = LayoutFit:Run(LayoutInfo(), fit.W, fit.H, inputs, function(fitted, places, report)
		Fitted(fit, fitted, places, report)
	end)
end

-- The fit for a setup: the fitter reads the setup's own target (Full's
-- window places and the tracker as the setup leaves them;
-- the draft as it is on the next frame), as a coroutine on Kit:NextFrame,
-- about 2 ms a frame. done(fit) runs once, on a later frame. The fitter
-- keeps its last result by its inputs, so an unchanged screen answers
-- from it. I:CancelFit(fit) stops one (done is not called then).
function I:StartFit(option, draft, done)
	option = self:Option(option)
	local LayoutFit, Kit = MelloUI.LayoutFit, MelloUI.Kit
	local fit = { option = option and option.key, draft = draft, done = false, onDone = done }
	if not (option and LayoutFit and LayoutFit.Run) then
		Fitted(fit, nil, nil, { verdict = "FAIL (no fitter)", pass = false, cause = "input", tooSmall = false })
		return fit
	end
	if type(Kit) == "table" and Kit.NextFrame then
		Kit:NextFrame(fit, BeginFit)
	else
		BeginFit(fit)
	end
	return fit
end

function I:CancelFit(fit)
	if type(fit) == "table" and not fit.done then
		fit.cancelled, fit.onDone = true, nil
		if fit.job and MelloUI.LayoutFit then
			MelloUI.LayoutFit:Cancel(fit.job)
		end
		fit.job = nil
	end
end

--------------------------------------------------------------------------------
-- Apply: one Batch, five phases
--------------------------------------------------------------------------------

local function WantOn(target, name, module)
	local flag = target.enabled[name]
	if flag == nil then
		return module.enabledByDefault and true or false
	end
	return flag and true or false
end

-- UI Modifications' switching keys: the reskin, a kit panel's name, qol_<name>
local function IsSwitch(key)
	return key == "reskin" or key:sub(1, 4) == "qol_" or Module(key) ~= nil
end

-- a UI Modifications key whose kit state is cached: how it is refreshed
local function LookKind(key)
	if type(key) ~= "string" then
		return nil
	end
	if key:sub(1, 10) == "parchment_" then
		return "parchment", key:sub(11)
	end
	local Kit = MelloUI.Kit
	local kinds = type(Kit) == "table" and type(Kit.borderKinds) == "table" and Kit.borderKinds or EMPTY
	for i = 1, #kinds do
		if kinds[i].key == key then
			return "border", kinds[i].kind
		end
	end
	return nil
end

local function Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if type(handler) == "function" then
		handler(err)
	end
end

-- The kit's cached looks for UI Modifications keys written while it was off
-- (its OnSettingChanged, the only caller of ApplyBorder / SetParchment, did
-- not run): one call each, only when the value really changed. The Kit
-- reads the umbrella's bound settings (its db, set in its OnEnable), which
-- a new player's never had: bound for the refresh only. The palette (0.14.0)
-- written while it was off is switched here first, the settings bound
-- (MelloUI:SetPalette: one walk over the kit's textures that reads the new
-- Kit Colours too, 'border' then one 'palette'), so the Kit Colours are not
-- walked again, the kit's own check when UI Modifications comes on finds
-- its art in place, and the held 'setting' finds the palette there: one
-- walk, one 'palette' for the whole apply. (With it on, the palette goes
-- in from that 'setting' as the Batch ends, the Kit Colours with it.)
local function PaletteMoves(umNow)
	return MelloUI:KnownPalette(umNow.palette) ~= MelloUI:PaletteId()
end

local function LookRefresh(pending, umStart, log)
	if next(pending) == nil then
		return
	end
	local Kit = MelloUI.Kit
	local um = Module(UMB)
	local umNow = MelloUI:GetModuleDB(UMB)
	local bound = um and um.db
	if um and bound == nil then
		um.db = umNow
	end
	local palette = pending.palette and PaletteMoves(umNow)
	pending.palette = nil
	if palette then
		local ok, err = pcall(MelloUI.SetPalette, MelloUI, umNow.palette)
		if not ok then
			Report(err)
		end
		log[#log + 1] = "palette"
	end
	for _, key in ipairs(SortedUnion(pending)) do
		pending[key] = nil
		if not Equal(umNow[key], umStart[key]) and type(Kit) == "table" then
			local how, what = LookKind(key)
			local ok, err = true, nil
			if how == "border" and what == "colours" and palette then
				how = nil   -- (the palette's switch walked them)
			end
			if how == "border" and Kit.ApplyBorder then
				ok, err = pcall(Kit.ApplyBorder, Kit, what)
			elseif how == "parchment" and Kit.SetParchment then
				-- (an area with a choice, the character window's since
				-- 0.19.4: "off" is off, "pane" / "window" on)
				local on = Kit.ParchmentValueOn and Kit.ParchmentValueOn(umNow[key]) or umNow[key] == true
				ok, err = pcall(Kit.SetParchment, Kit, what, on)
			end
			if not ok then
				Report(err)
			end
			log[#log + 1] = key
		end
	end
	if um and bound == nil then
		um.db = nil
	end
end

-- the start-up-read values now (compared after the Batch: a leader such as
-- the Font Style changes them without being set)
local function StartupValues()
	local t = {}
	for name, keys in pairs(STARTUP) do
		local db = Module(name) and MelloUI:GetModuleDB(name)
		if db then
			local v = { on = MelloUI:IsModuleEnabled(name) and true or false }
			for key in pairs(keys) do
				v[key] = DeepCopy(db[key])
			end
			t[name] = v
		end
	end
	return t
end

local function NeedsReload(was)
	for name, keys in pairs(STARTUP) do
		local before = was[name]
		if before then
			local on = MelloUI:IsModuleEnabled(name) and true or false
			if on ~= before.on then
				return true
			elseif on then
				local db = MelloUI:GetModuleDB(name)
				for key in pairs(keys) do
					if not Equal(db[key], before[key]) then
						return true
					end
				end
			end
		end
	end
	return false
end

-- the settings that differ between a module's db and its target (the
-- player's own and NEVER keys aside)
local function Differing(name, tgt)
	local cur, n = MelloUI:GetModuleDB(name), 0
	for _, key in ipairs(SortedUnion(cur, tgt)) do
		if not Kept(name, key) and not Equal(cur[key], tgt[key]) then
			n = n + 1
		end
	end
	return n
end

-- The target applied: what turns off, each module's settings, UI
-- Modifications' own keys, the kit's cached looks, what turns on, then a
-- reconcile of whatever the modules' own reactions changed. exact (a
-- revert): the flags and the profile name as the target has them, raw.
local function DoApply(self, target, exact, out)
	local umStart = DeepCopy(MelloUI:GetModuleDB(UMB))
	local lookPending, bundled = {}, {}
	local umModule = Module(UMB)
	local function Set(name, key, value)
		out.changed = out.changed + 1
		if name == UMB and not (umModule and umModule.isEnabled) and (LookKind(key) or key == "palette") then
			lookPending[key] = true
		end
		MelloUI:NotifySettingChanged(name, key, DeepCopy(value))
	end
	-- a key the apply leaves alone: the player's own and NEVER keys, unless
	-- the target sets it itself (target.explicit: a personal key the draft sets)
	local function Skip(name, key)
		return Kept(name, key) and not Explicit(target, name, key)
	end
	-- the reskin's one-time Edit Mode layout (UI Modifications' ReskinOn)
	-- stays out of an apply: the installer puts the fitted layout in itself
	local umdb = MelloUI:GetModuleDB(UMB)
	local layoutApplied = umdb.layoutApplied
	umdb.layoutApplied = true
	local ok, err = pcall(MelloUI.Batch, MelloUI, function()
		local umb = MelloUI:GetModuleDB(UMB)
		local umbT = target.modules[UMB] or EMPTY
		-- phase 0: what turns off; the bundled modules; the umbrella's switches going off
		for name, module in MelloUI:IterateModules() do
			if not module.hidden and MelloUI:IsModuleEnabled(name) and not WantOn(target, name, module) then
				out.changed = out.changed + 1
				MelloUI:SetModuleEnabled(name, false)
			end
		end
		for name in pairs(BUNDLE) do
			local module = Module(name)
			local tgt = target.modules[name]
			if module and tgt and module.isEnabled and self:EffectiveOn(target, name) and Differing(name, tgt) >= 2 then
				bundled[name] = { raw = MelloUI.db.enabled[name] }
				MelloUI:SetModuleEnabled(name, false)
			end
		end
		for _, key in ipairs(SortedUnion(umb, umbT)) do
			if IsSwitch(key) and umbT[key] == false and umb[key] ~= false and not Skip(UMB, key) then
				Set(UMB, key, false)
			end
		end
		-- phase 1: each module's settings, leaders first (a module that is
		-- off only has its db written: its OnEnable reads the final values)
		for name in MelloUI:IterateModules() do
			local tgt = target.modules[name]
			if name ~= UMB and tgt then
				local cur = MelloUI:GetModuleDB(name)
				for _, key in ipairs(LEADERS[name] or EMPTY) do
					if not Equal(cur[key], tgt[key]) then
						Set(name, key, tgt[key])
					end
				end
				cur = MelloUI:GetModuleDB(name)
				for _, key in ipairs(SortedUnion(cur, tgt)) do
					if not Skip(name, key) and not Equal(cur[key], tgt[key]) then
						Set(name, key, tgt[key])
					end
				end
			end
		end
		-- phase 2: UI Modifications' own keys, the reskin first; then the
		-- kit's cached looks, before the panels come on (every piece built
		-- in phase 3 reads the new value; the walk meets only what was there)
		umb = MelloUI:GetModuleDB(UMB)
		if umbT.reskin ~= nil and not Equal(umb.reskin, umbT.reskin) then
			Set(UMB, "reskin", umbT.reskin)
		end
		for _, key in ipairs(SortedUnion(umb, umbT)) do
			if key ~= "reskin" and not Skip(UMB, key) and not Equal(umb[key], umbT[key]) then
				Set(UMB, key, umbT[key])
			end
		end
		LookRefresh(lookPending, umStart, out.lookRefresh)
		-- phase 3: what turns on; the bundled modules back on (their walk
		-- runs once, every key already final), their raw flags as they were
		for name, module in MelloUI:IterateModules() do
			if not module.hidden and not MelloUI:IsModuleEnabled(name) and WantOn(target, name, module) then
				out.changed = out.changed + 1
				MelloUI:SetModuleEnabled(name, true)
			end
		end
		for name, b in pairs(bundled) do
			if not Module(name).isEnabled and self:EffectiveOn(target, name) then
				MelloUI:SetModuleEnabled(name, true)
			end
			MelloUI.db.enabled[name] = b.raw
			bundled[name] = nil   -- (back: a fault after this leaves it alone)
		end
		-- phase 4: reconcile, at most twice. A module's own reaction may
		-- have changed another setting or switch (the reskin brings Custom
		-- Sounds on; the name form is copied into two modules): whatever
		-- still differs is set again (the Batch keeps one Fire per key)
		for _ = 1, 2 do
			local again = 0
			for name, module in MelloUI:IterateModules() do
				local tgt = target.modules[name]
				if tgt then
					local cur = MelloUI:GetModuleDB(name)
					for _, key in ipairs(SortedUnion(cur, tgt)) do
						if not Skip(name, key) and not Equal(cur[key], tgt[key]) then
							again = again + 1
							Set(name, key, tgt[key])
						end
					end
				end
				if not module.hidden and (MelloUI:IsModuleEnabled(name) and true or false) ~= WantOn(target, name, module) then
					again = again + 1
					MelloUI:SetModuleEnabled(name, WantOn(target, name, module))
				end
			end
			out.reconcile = again
			if again == 0 then
				break
			end
		end
	end)
	umdb = MelloUI:GetModuleDB(UMB)
	umdb.layoutApplied = layoutApplied
	if not ok then
		-- a fault half way: a bundled module still off goes back on, raw
		-- flag and all (it is driven: nothing else would switch it back)
		for name, b in pairs(bundled) do
			local on, onErr = pcall(MelloUI.SetModuleEnabled, MelloUI, name, true)
			if not on then
				Report(onErr)
			end
			MelloUI.db.enabled[name] = b.raw
		end
		-- and the kit's cached looks for the look keys already written: a
		-- retry, or the profile load after it, starts from a kit that
		-- matches the settings (it compares with them)
		local looked, lookErr = pcall(LookRefresh, lookPending, umStart, out.lookRefresh)
		if not looked then
			Report(lookErr)
		end
		error(err, 0)
	end
	-- (a look key the reconcile wrote while UI Modifications stayed off)
	LookRefresh(lookPending, umStart, out.lookRefresh)
	if exact then
		-- the flags as they were, nil included (nil is the module's
		-- enabledByDefault: the running state is the same), and the
		-- profile name the Profiles page showed
		local enabled = MelloUI.db.enabled
		for name in pairs(enabled) do
			if target.enabled[name] == nil then
				enabled[name] = nil
			end
		end
		for name, flag in pairs(target.enabled) do
			enabled[name] = flag
		end
		-- a module left running against its flag by a fault half way through
		-- an earlier apply: switched to its flag, the raw flag kept (after a
		-- clean install and revert there is none)
		for name, module in MelloUI:IterateModules() do
			local want = MelloUI:IsModuleEnabled(name) and true or false
			if (module.isEnabled and true or false) ~= want then
				local raw = enabled[name]
				out.changed = out.changed + 1
				MelloUI:SetModuleEnabled(name, want)
				enabled[name] = raw
			end
		end
		MelloUI.db.activeProfile = target.activeProfile
	end
end

-- Returns how many settings and switches were written (1.2.4: no reload
-- answer -- Keep reloads the UI; Revert reads its own, I:Revert). Quiet
-- while it runs: `applying` for the modules that ask, and the chat lines
-- held for the log (MelloUI.printHold).
function I:Apply(target, exact)
	assert(type(target) == "table" and type(target.modules) == "table" and type(target.enabled) == "table",
		"MelloUI.Installer:Apply needs a state")
	local out = { changed = 0, reconcile = 0, lookRefresh = {} }
	self.applying = true
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 0) + 1
	local ok, err = pcall(DoApply, self, target, exact, out)
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 1) - 1
	self.applying = false
	if not ok then
		error(err, 0)
	end
	self.lastApply = out
	return out.changed
end

-- An Edit Layout session (Core's MelloUI.LayoutSession) ended with nothing
-- put back from it: the setup's store is the truth (Install, Fit to this
-- screen and Revert, before their first write)
local function AbandonLayout()
	local session = MelloUI.LayoutSession
	if type(session) == "table" and type(session.Abandon) == "function" then
		session.Abandon("installer")
	end
end

-- Every registered window put where the store now says. A window that
-- keeps its own place (entry.save: the Quest Tracker) moved on its own
-- 'setting' Fire and is left alone: never its entry.reset here, which
-- would wipe the place just applied and write settings outside the Batch. A hidden window gets its place on its next show (Core's OnShow).
-- An element that is not live (a module's that is off: UI Modifications'
-- game windows) is the game's to place; a game window the game lays out
-- (`follow`) with no place in the store keeps the game's, never its
-- default (that is Edit Layout's Reset preview: Edit Mode's place).
function I:PlaceWindows()
	local placed = { restored = 0, defaulted = 0, skipped = 0 }
	for _, entry in ipairs(MelloUI:MoverEntries()) do
		if entry.save or (MelloUI.EntryLive and not MelloUI:EntryLive(entry)) then
			placed.skipped = placed.skipped + 1
		elseif entry.key ~= nil and MelloUI:GetPosition(entry.key) then
			MelloUI:RestorePosition(entry.key, entry.frame)
			placed.restored = placed.restored + 1
		elseif entry.default and not entry.follow then
			local ok, err = pcall(entry.default, entry.frame)
			if ok then
				placed.defaulted = placed.defaulted + 1
			else
				Report(err)
			end
		end
	end
	return placed
end

--------------------------------------------------------------------------------
-- The Keep countdown: the seconds from the clock (a deadline), never from
-- counting ticks, and at most one timer out at any time (a pause and resume
-- inside a second, or Keep and a new install inside a second, reuse the one
-- that is out). One shared Tick on C_Timer.After, landing where the shown
-- number changes: no ticker, no OnUpdate, no closure per tick. Paused in
-- combat and while Edit Mode is open (its events taken only while it runs).
--------------------------------------------------------------------------------

local CD = { running = false, paused = false, deadline = 0, left = 0, outstanding = false, why = nil, editMode = false }
local CD_OWNER = "Installer countdown"
local cdFrame
local Tick

-- (Core's readers, one each: the fight, Edit Mode open)
local InCombat, EditModeOpen = MelloUI.InCombat, MelloUI.EditModeOpen

local function Left()
	if CD.paused then
		return CD.left
	end
	local left = CD.deadline - (Num(GetTime()) or CD.deadline)
	return left > 0 and left or 0
end

local function Draw()
	local seconds = ceil(Left() - 1e-6)
	MelloUI:Fire("installer", "countdown", seconds > 0 and seconds or 0, CD.paused, CD.why)
end

-- the next tick where the shown number changes (a whole second of what is left)
local function Arm()
	if CD.outstanding then
		return   -- the timer already out serves this run too
	end
	CD.outstanding = true
	local left = Left()
	local d = left - floor(left - 1e-6)
	C_Timer.After(d > 1e-6 and d or 1, Tick)
end

local function Pause(why)
	if not CD.running then
		return
	end
	local reason = why or (InCombat() and "combat") or (CD.editMode and "editmode") or nil
	if not reason then
		return
	end
	if not CD.paused then
		CD.left = Left()
		CD.paused = true
	end
	CD.why = reason
	Draw()
end

local function Resume()
	if not (CD.running and CD.paused) then
		return
	end
	local still = (InCombat() and "combat") or (CD.editMode and "editmode") or nil
	if still then
		if still ~= CD.why then
			CD.why = still
			Draw()
		end
		return
	end
	CD.paused, CD.why = false, nil
	CD.deadline = (Num(GetTime()) or 0) + CD.left
	Draw()
	Arm()
end

local function OnCountdownEvent(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		Pause("combat")
	elseif event == "PLAYER_REGEN_ENABLED" then
		Resume()
	end
end

local function OnEditMode(entering)
	CD.editMode = entering and true or false
	if CD.editMode then
		Pause("editmode")
	else
		Resume()
	end
end

-- the two combat events and the 'editmode' topic, only while a countdown runs
local function Listen(on)
	if on then
		if not cdFrame then
			cdFrame = CreateFrame("Frame")
			Perf.SetScript(cdFrame, "OnEvent", OnCountdownEvent)
		end
		cdFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
		cdFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		MelloUI:On("editmode", OnEditMode, CD_OWNER)
	else
		if cdFrame then
			cdFrame:UnregisterAllEvents()
		end
		MelloUI:Off(CD_OWNER, "editmode")
	end
end

local function Stop()
	if CD.running then
		CD.running, CD.paused, CD.why = false, false, nil
		Listen(false)
	end
end

Tick = function()
	CD.outstanding = false
	if not CD.running or CD.paused then
		return
	end
	if InCombat() then
		Pause("combat")   -- (the fight began this frame: a timeout never falls in combat)
		return
	end
	if Left() <= 1e-6 then
		-- (the revert ends the countdown; refused this frame, it is tried
		-- again a second later, the number standing at 0)
		local ok, why = I:Revert("timeout")
		if not ok and CD.running then
			if why == TEXT.nothing then
				Stop()   -- (no restore point: nothing to wait for)
			else
				Draw()
				Arm()
			end
		end
		return
	end
	Draw()
	Arm()
end

-- after Install, or after a /reload or a restart while an install waits for
-- its answer (I:ResumePending)
function I:StartCountdown(seconds)
	CD.running, CD.paused, CD.why = true, false, nil
	CD.deadline = (Num(GetTime()) or 0) + (tonumber(seconds) or KEEP_SECONDS)
	CD.editMode = EditModeOpen()
	Listen(true)
	Pause(nil)   -- (in combat or with Edit Mode open it starts paused)
	if not CD.paused then
		Draw()
	end
	Arm()
end

function I:Countdown()
	if not CD.running then
		return false, 0, false, nil
	end
	local seconds = ceil(Left() - 1e-6)
	return true, seconds > 0 and seconds or 0, CD.paused, CD.why
end

-- An answer still owed: the install was made before a /reload or a restart
-- (the saved settings keep the restore point and `pending`, as any
-- setting), or in this session (a revert from the configurator's Home that
-- could not put everything back). Made before this session began, the game
-- has read the installed start-up values since (the fonts over heads), so a
-- revert then owes a reload and Keep owes none; one made in this session
-- keeps its own mark. The countdown runs again with its full time. Returns
-- whether an answer is owed; one countdown already running is left as it is.
function I:ResumePending()
	local rp = MelloUI.db and MelloUI.db.installer
	local pending = type(rp) == "table" and rp.pending
	if type(pending) ~= "table" then
		return false
	end
	if not CD.running then
		pending.reloadedSince = (pending.reloadedSince or self:BeforeSession(rp)) and true or false
		self:StartCountdown(KEEP_SECONDS)
	end
	return true
end

-- whether a restore point was made before this session began (its `at`
-- not after the second this file loaded: no install is clicked in that
-- second; none: taken as before)
function I:BeforeSession(rp)
	local at = type(rp) == "table" and tonumber(rp.at) or nil
	return (not at or at <= I.SESSION_AT) and true or false
end

--------------------------------------------------------------------------------
-- Install, Revert, Keep
--------------------------------------------------------------------------------

-- the real saved settings are in place (Backup.lua): until then an existing
-- player could look new, and an install would run on settings still to come
local function Settled()
	return (MelloUI.initialized and MelloUI.db and MelloUI:SettingsSettled()) and true or false
end

-- The one long frame (allowed and measured: user, 2026-09-25): what Install took, and what Revert took (the
-- exact mirror of Install's work: the same modules switched back, the same
-- keys, in one Batch). I.cost = { install = ms, revert = ms } for a check
-- in game; the line goes to the log only (/mellolog), never to the chat.
I.cost = {}

local function Clock()
	return Num(debugprofilestop and debugprofilestop()) or 0
end

local function NoteCost(what, label, t0)
	local ms = Clock() - t0
	I.cost[what] = ms
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 0) + 1
	pcall(MelloUI.Print, MelloUI, TEXT.cost, label, ms)
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 1) - 1
end

-- whether a state leaves the reskin on (UI Modifications on, its reskin not off)
local function ReskinStaysOn(state)
	return Flag(state, UMB) and (state.modules[UMB] or EMPTY).reskin ~= false
end

-- one of the installer's own facts written through the setting path
local function SetOwn(key, value)
	local db = MelloUI:GetModuleDB(UMB)
	if db and not Equal(db[key], value) then
		MelloUI:NotifySettingChanged(UMB, key, DeepCopy(value))
	end
end

-- The fitted Edit Mode layout in (Core/EditModeLayout.lua; the version that
-- takes a fitted layout has EditModeLayoutInfo). Returns ok, why, and
-- whether it was handed to Edit Mode at all (then a revert restores the
-- Edit Mode state).
local function PutLayout(fit)
	if not (MelloUI.EditModeLayoutInfo and MelloUI.ApplyEditModeLayout) then
		return false, "the fitted layout cannot be applied by this version", false
	end
	local ok, applied, why = pcall(MelloUI.ApplyEditModeLayout, MelloUI, true, fit.fitted)
	if not ok then
		Report(applied)
		return false, tostring(applied), true
	end
	return applied and true or false, why, true
end

-- Whether Edit Mode keeps one more layout for the fitted one, read before
-- anything is written (a list with more than Edit Mode keeps would not save
-- at all, and Core/EditModeLayout.lua refuses it only once the settings
-- went in): a layout of the fitted one's name is replaced, no room needed;
-- else the account layouts are counted against
-- Constants.EditModeConsts.EditModeMaxLayoutsPerType, as that file counts
-- them. Read only; what cannot be read is room. Returns room, the most.
-- The answer is kept on a finished fit (fit.room, fit.most: the footer and
-- the Screen step ask on every refresh, and the layouts' list is a whole
-- tree of tables): `fresh` reads it again (Install's own check), and the
-- window forgets it when it shows and when Edit Mode opens or closes (where
-- a layout can be deleted).
local function ReadRoom(fit)
	local consts = type(Constants) == "table" and Constants.EditModeConsts
	local most = type(consts) == "table" and consts.EditModeMaxLayoutsPerType
	if Secret(most) or type(most) ~= "number" or not (C_EditMode and C_EditMode.GetLayouts) then
		return true, most
	end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not (ok and type(info) == "table" and type(info.layouts) == "table") then
		return true, most
	end
	local name = type(fit) == "table" and type(fit.fitted) == "table" and fit.fitted.layoutName or nil
	local kinds = Enum and Enum.EditModeLayoutType
	local account = kinds and kinds.Account
	local n = 0
	for _, layout in ipairs(info.layouts) do
		local lname, kind = type(layout) == "table" and layout.layoutName, type(layout) == "table" and layout.layoutType
		if not (Secret(lname) or Secret(kind)) then
			if name ~= nil and lname == name then
				return true, most   -- (replaced where it stands)
			end
			if kind == account then
				n = n + 1
			end
		end
	end
	return n < most, most
end

function I:LayoutRoom(fit, fresh)
	local keep = type(fit) == "table" and fit.done
	if keep and not fresh and fit.room ~= nil then
		return fit.room, fit.most
	end
	local room, most = ReadRoom(fit)
	if keep then
		fit.room, fit.most = room and true or false, most
	end
	return room, most
end

-- why Install cannot run now (the footer's line), or nil; fresh: the Edit
-- Mode layouts counted again (Install's own check)
function I:InstallBlocked(option, draft, fit, fresh)
	option = self:Option(option)
	if not option then
		return TEXT.nothing
	elseif not Settled() then
		return TEXT.loading
	elseif InCombat() then
		return TEXT.combat
	elseif EditModeOpen() then
		return TEXT.editMode
	elseif CD.running or (type(MelloUI.db.installer) == "table" and MelloUI.db.installer.pending) then
		return TEXT.pending
	end
	if NeedsFit(option, draft) then
		if type(fit) ~= "table" or not fit.done or fit.option ~= option.key then
			return TEXT.fitting
		end
		local W, H = ScreenSize()
		if W and fit.W and fit.H and (abs(W - fit.W) > 0.5 or abs(H - fit.H) > 0.5) then
			return TEXT.refit
		end
	end
	if self:LayoutOn(option, draft, fit) then
		local room, most = self:LayoutRoom(fit, fresh)
		if not room then
			return MelloUI.Lang.F(TEXT.noRoom, most)
		end
	end
	return nil
end

-- The setup, its layout and its facts, in one Batch (one backup), then the
-- windows re-placed. The layout facts: layoutFitFor (and the model's
-- layoutFitRev) only when the fitted layout really went in; layoutApplied
-- whenever the layout went in, the setup leaves the reskin on, or the setup's
-- Layout step was answered (1.2.4: every setup) -- the installer answered the
-- layout question: a later hand switch of the reskin never puts the raw
-- layout over the player's "my own layout stays". All
-- noted on the restore point before they are written, so a revert, or a
-- fault half way, puts them back.
local function DoInstall(self, rp, option, target, fit, layoutOn, out)
	-- the restore point on the Profiles page (it sets the active profile:
	-- after the capture, and the revert puts the old name back); its text is
	-- kept on the restore point too, for a revert whose exact apply fails
	MelloUI:SaveProfile(BEFORE_PROFILE, true)   -- (2.1.0: plain -- the settings as they were, no places measured)
	rp.text = MelloUI:Profiles()[BEFORE_PROFILE]
	MelloUI:Batch(function()
		out.changed = self:Apply(target)
		SetOwn("seenVersion", MelloUI.version)
		if layoutOn then
			-- (layoutWritten: handed to Edit Mode, so a revert puts its state
			-- back, even when Edit Mode refused it or a later step failed)
			rp.layoutPut, rp.layoutWhy, rp.layoutWritten = PutLayout(fit)
		end
		-- (1.2.4: the setup's Layout step answers the layout question whatever the skin: Mello's layout or the player's)
		if rp.layoutPut or ReskinStaysOn(target) or option.base == "setup" then
			rp.layoutFlags = true
			if rp.layoutPut then
				SetOwn("layoutFitFor", fit.places and fit.places.layoutFitFor or nil)
				-- (the model's revision: an older one's fit is offered the refit)
				local LF = MelloUI.LayoutFit
				SetOwn("layoutFitRev", type(LF) == "table" and LF.FIT_REV or nil)
			end
			SetOwn("layoutApplied", true)
		end
		-- (1.2.4, the user's pick B of BuildData/output/chat_room_sketch: the chat's text 14 for the chat MelloUI's
		-- layout makes -- the game's own setting, Fonts' SetChatTextSize; its sizes before kept: Revert puts them back)
		local fonts = option.base == "setup" and MelloUI:GetModule("Fonts")
		if fonts and fonts.SetChatTextSize then
			rp.chatSizes = fonts:SetChatTextSize(14)
		end
	end)
	-- (the refit changes only what no profile carries -- the layout, the
	-- places -- so the profile in use stays named)
	MelloUI.db.activeProfile = option.refit and rp.before.activeProfile or nil
	-- the registered windows where the store now says
	self:PlaceWindows()
end

-- the current state and the setup's target made from it (nothing written)
local function Prepare(self, option, draft, fit)
	local before = self:Capture()
	return before, self:TargetFor(option, draft, fit, before), self:LayoutOn(option, draft, fit)
end

-- In the click frame: the restore point first, then the setup and the
-- fitted places in one Batch with the Edit Mode layout, the windows
-- re-placed, then the Keep countdown. One long frame (measured: I.cost),
-- every frame after it inside the budget. A fault half way (an engine
-- error; a module's own errors are caught by SafeCall) is reported and put
-- back at once (Revert "error"): the player is never left with half a setup
-- and no countdown. Should that revert not get through, the answer stays
-- pending (failed): nothing overwrites the restore point, and the Keep
-- page offers Revert only. A fault while the target is made changes nothing.
function I:Install(option, draft, fit)
	option = self:Option(option)
	local why = self:InstallBlocked(option, draft, fit, true)
	if why then
		return false, why
	end
	local t0 = Clock()
	draft = draft or {}
	local db = MelloUI.db
	-- 1. the current state and the setup's target made from it (nothing
	-- written yet: a fault here leaves everything as it was)
	local prepared, before, target, layoutOn = pcall(Prepare, self, option, draft, fit)
	if not prepared then
		Report(before)
		return false, TEXT.failedNothing
	end
	-- the personal keys the setup sets itself: the revert puts them back too
	before.explicit = DeepCopy(target.explicit)
	-- (read by the fitted layout itself, so the state names exactly the
	-- layout the install writes)
	local layoutBefore
	if MelloUI.EditModeState then
		local ok, state = pcall(MelloUI.EditModeState, MelloUI, type(fit) == "table" and fit.fitted or nil)
		layoutBefore = ok and state or nil
	end
	-- an Edit Layout session ends before the first write, nothing of it put
	-- back over the setup (its places come from the store this writes:
	-- PlaceWindows below)
	AbandonLayout()
	-- 2. the restore point (in the db this session runs on: never the
	-- global, which may not be there yet on this client)
	local rp = { before = before, layout = layoutBefore, option = option.key, at = time() }
	-- (2.1.0, el-15; the user's /mello layout check said "not wanted", and nothing told why) what the player picked on
	-- the Layout step, and the fit's verdict when Mello's layout was picked but the fit did not pass (I:LayoutOn then
	-- answers false and the layout was skipped without a word): kept for the check and said below
	rp.layoutWanted = option.layout and not (type(draft) == "table" and draft.layout == false) and true or false
	if rp.layoutWanted and not layoutOn then
		local report = type(fit) == "table" and type(fit.report) == "table" and fit.report or nil
		rp.layoutWhy = report and tostring(report.why or report.verdict) or TEXT.noFit
	end
	-- (el-15, the user's real client, 2026-11-01: "too small" on the very screen the layout is drawn for, which the sim
	-- never gave) the fit's own answer kept with it, small and plain, for /mello layout check: the screen it measured,
	-- its verdict and cause, and the first of what it could not solve
	local report = type(fit) == "table" and type(fit.report) == "table" and fit.report or nil
	if report then
		local function Few(list)
			local out = {}
			for i = 1, math.min(4, type(list) == "table" and #list or 0) do
				out[i] = tostring(list[i])
			end
			return out
		end
		local checks = type(report.checks) == "table" and report.checks or EMPTY
		rp.layoutFit = { W = fit.W, H = fit.H, verdict = tostring(report.verdict), cause = report.cause and tostring(report.cause),
			drawn = report.drawn and true or nil, adapted = report.adapted and true or nil, scaled = report.scaled,
			flags = Few(report.flags), hard = Few(checks.hard), off = Few(checks.off),
			centre = Few(checks.centre), stores = Few(checks.stores) }
	end
	db.installer = rp
	-- 3-6. the setup, the layout, the windows
	local out = {}
	local ok, err = pcall(DoInstall, self, rp, option, target, fit, layoutOn, out)
	if not ok then
		Report(err)
		-- pending before the revert (failed: half a setup, never kept). A
		-- revert that works clears it; one that does not leaves the restore
		-- point guarded: Install and Keep refused, the Keep page and its
		-- Revert after a /reload (a second install would take the half
		-- state as its restore point)
		rp.pending = { option = option.key, reloadedSince = false, failed = true }
		local rok, reverted, rwhy = pcall(self.Revert, self, "error")
		if not rok then
			Report(reverted)
		elseif reverted then
			return false, TEXT.failed
		elseif rwhy == TEXT.revertFailed then
			return false, TEXT.revertFailed   -- (the line Revert printed)
		end
		return false, TEXT.failedStuck
	end
	local changed = out.changed
	-- 7. the answer the countdown waits for
	rp.pending = { option = option.key, reloadedSince = false }
	if option.refit then
		MelloUI:Print(TEXT.refitted)
	else
		MelloUI:Print(TEXT.installed, option.title)
	end
	-- (2.1.0, el-15: players' "the Edit Mode layout does not apply") the layout wanted but refused (a full list, a save
	-- the game turned down ...): said in the chat and on the Keep page -- it was kept on the restore point only, and
	-- the player reloaded into their old layout without a word
	local notIn
	if rp.layoutWanted and not rp.layoutPut then
		notIn = MelloUI.Lang.F(TEXT.layoutNotIn, tostring(rp.layoutWhy or "?"))
		MelloUI:Print("%s", notIn)
	end
	self:StartCountdown(KEEP_SECONDS)
	MelloUI:Fire("installer", "installed", option.key, notIn)
	NoteCost("install", "Install", t0)   -- (the window's Keep page drawn on the Fire included)
	return true, nil, changed
end

-- the installer's own layout facts as the restore point has them
local function PutLayoutFacts(rp)
	if rp.layoutFlags or rp.layoutWritten then
		local um = rp.before.modules[UMB] or EMPTY
		for _, key in ipairs(LAYOUT_OWN) do
			SetOwn(key, um[key])
		end
	end
end

-- the restore point's settings back, in one Batch: the exact apply (the
-- settings, the switches, the kit's cached looks, the raw flags and the
-- profile name), then the layout facts
local function PutBackExact(self, rp)
	self:Apply(rp.before, true)
	PutLayoutFacts(rp)
end

-- The fallback when the exact apply keeps failing: the same settings as
-- text ("Before install", saved from them) through Core's own profile load,
-- the kit's cached looks, the running state and the raw flags as the
-- restore point has them, the profile name, the layout facts. Quiet like
-- an apply.
local function PutBackLoaded(self, rp)
	local umStart = DeepCopy(MelloUI:GetModuleDB(UMB))
	MelloUI:ApplySettingsText(rp.text)
	-- (a profile never holds a personal key: the ones the setup set itself
	-- are put back from the restore point)
	for name, keys in pairs(type(rp.before.explicit) == "table" and rp.before.explicit or EMPTY) do
		local was = rp.before.modules[name] or EMPTY
		local db = Module(name) and MelloUI:GetModuleDB(name)
		for key in pairs(db and keys or EMPTY) do
			if not Equal(db[key], was[key]) then
				MelloUI:NotifySettingChanged(name, key, DeepCopy(was[key]))
			end
		end
	end
	-- the profile load writes the settings without UI Modifications'
	-- OnSettingChanged (the only caller of ApplyBorder / SetParchment), on
	-- or off: each look key whose value changed refreshed once, before the
	-- running state below switches a panel on
	local looks = {}
	for _, key in ipairs(SortedUnion(umStart, MelloUI:GetModuleDB(UMB))) do
		if LookKind(key) then
			looks[key] = true
		end
	end
	LookRefresh(looks, umStart, {})
	local enabled, flags = MelloUI.db.enabled, rp.before.enabled
	for name, module in MelloUI:IterateModules() do
		local want = flags[name]
		if want == nil then
			want = module.enabledByDefault
		end
		if (module.isEnabled and true or false) ~= (want and true or false) then
			MelloUI:SetModuleEnabled(name, want)
		end
	end
	for name in pairs(enabled) do
		if flags[name] == nil then
			enabled[name] = nil
		end
	end
	for name, flag in pairs(flags) do
		enabled[name] = flag
	end
	MelloUI.db.activeProfile = rp.before.activeProfile
	PutLayoutFacts(rp)
end

local function PutBackByText(self, rp)
	if type(rp.text) ~= "string" then
		error("the restore point has no 'Before install' text", 0)
	end
	self.applying = true
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 0) + 1
	local ok, err = pcall(MelloUI.Batch, MelloUI, PutBackLoaded, self, rp)
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 1) - 1
	self.applying = false
	if not ok then
		error(err, 0)
	end
end

-- the settings put back: the exact apply; should it fault half way (an
-- engine error), once more from where it stopped (the apply sets whatever
-- still differs), then the profile load of the same settings
local function PutBack(self, rp)
	local ok, err = pcall(MelloUI.Batch, MelloUI, PutBackExact, self, rp)
	if ok then
		return true
	end
	Report(err)
	ok, err = pcall(MelloUI.Batch, MelloUI, PutBackExact, self, rp)
	if ok then
		return true
	end
	Report(err)
	ok, err = pcall(PutBackByText, self, rp)
	if not ok then
		Report(err)
	end
	return ok
end

-- Back to the restore point: the settings, the switches, the kit's cached
-- looks, the flags and the profile name exactly; the Edit Mode layouts as
-- they were; the windows re-placed. The restore point stays, like the
-- 'Before install' profile, in the saved settings (Revert stays possible
-- until the next install). reloadOwed: the game read the installed start-up
-- values (a /reload or a restart since the install) and the revert changes
-- them back.
-- One long frame, like Install's and measured the same way (I.cost.revert),
-- for the button and the countdown's timeout alike: it undoes exactly the
-- Install frame's work, and its biggest step (UI Modifications switching
-- its panels in its own OnEnable / OnDisable) cannot be split; spread over
-- frames it would show a half-reverted UI, could be caught by combat half
-- way (the panels cannot switch then) and would lose the one Batch that
-- makes it exact (one backup, one Fire per key, the settings text
-- byte-identical).
-- Should nothing put the settings back (every way faulted): nothing else is
-- done, the restore point and the pending answer stay, and the line says to
-- /reload (the Keep page comes back and its countdown tries again). The
-- answer is then failed too (revertFailed: half put back): Keep refused,
-- Revert only, now and after the /reload.
function I:Revert(reason)
	local db = MelloUI.db
	local rp = db and db.installer
	if type(rp) ~= "table" or type(rp.before) ~= "table" then
		return false, TEXT.nothing
	elseif InCombat() then
		return false, TEXT.pausedCombat
	elseif (CD.running and CD.editMode) or EditModeOpen() then
		return false, TEXT.editMode   -- (never SaveLayouts behind Edit Mode's own edit)
	end
	-- (as Install's: an Edit Layout session ends before anything is put back)
	AbandonLayout()
	Stop()
	local t0 = Clock()
	local pending = rp.pending
	local was = StartupValues()
	if not PutBack(self, rp) then
		-- (an install that faulted keeps its own failed mark and line)
		if type(pending) == "table" and not pending.failed then
			pending.failed, pending.revertFailed = true, true
		end
		MelloUI:Print(TEXT.revertFailed)
		MelloUI:Fire("installer", "revertFailed", reason, TEXT.revertFailed)
		NoteCost("revert", "Revert (" .. tostring(reason) .. ", failed)", t0)
		return false, TEXT.revertFailed
	end
	local needsReload = NeedsReload(was)
	if rp.layoutWritten and rp.layout and MelloUI.RestoreEditModeState then
		local ok, err = pcall(MelloUI.RestoreEditModeState, MelloUI, rp.layout)
		if not ok then
			Report(err)
		end
	end
	-- (1.2.4) the chat's text sizes as they were
	local fonts = type(rp.chatSizes) == "table" and next(rp.chatSizes) ~= nil and MelloUI:GetModule("Fonts")
	if fonts and fonts.SetChatTextSize then
		local okS, errS = pcall(fonts.SetChatTextSize, fonts, rp.chatSizes)
		if not okS then
			Report(errS)
		end
	end
	local placed, err = pcall(self.PlaceWindows, self)
	if not placed then
		Report(err)
	end
	rp.pending = nil
	rp.layoutWritten, rp.layoutPut, rp.layoutFlags, rp.chatSizes = nil, nil, nil, nil
	rp.reverted = tostring(reason or "?")   -- (2.1.0, el-15: /mello layout check tells a revert from a layout never wanted)
	local reloaded = rp.reloadedSince or (pending and pending.reloadedSince)
	local reloadOwed = (needsReload and reloaded) and true or false
	MelloUI:Print(TEXT.reverted)
	MelloUI:Fire("installer", "reverted", reason, reloadOwed)
	NoteCost("revert", "Revert (" .. tostring(reason) .. ")", t0)
	return true, nil, reloadOwed
end

-- The setup kept: the countdown ends, true (1.2.4: the window's Keep then
-- reloads the UI, so nothing is owed). An install that faulted half
-- way and could not be put back, or one a Revert only partly put back, is
-- never kept (Revert only): refused, the countdown left running.
function I:Keep()
	local rp = MelloUI.db and MelloUI.db.installer
	local pending = type(rp) == "table" and rp.pending
	if pending and pending.failed then
		return false, pending.revertFailed and TEXT.keepHalf or TEXT.keepFailed
	end
	Stop()
	if not pending then
		return false
	end
	rp.pending = nil
	rp.reloadedSince = rp.reloadedSince or pending.reloadedSince
	MelloUI:Fire("installer", "kept")
	return true
end

--------------------------------------------------------------------------------
-- The entry, and the first login: the installer owns it (the tour's old
-- welcome popup is gone)
--
-- At login nothing is built but one hidden event frame, made as this file
-- loads (it replaces the one the tour's old welcome popup had: the count
-- stays the same). It takes PLAYER_ENTERING_WORLD once; 3 s later, one
-- check:
--   - the settings not settled (Backup.lua: settled once the saved
--     variables are in or the world was entered, so by the check they are;
--     not: the player is not known to be new, nothing this session);
--   - an answer owed (an install made before a /reload or a restart, a
--     failed one too: the saved settings keep it): the Keep page, its
--     countdown again with its 15 s (IW:Open, I:ResumePending);
--   - a new player (UI Modifications' welcomeAsked not set, and the
--     settings are the built-in "Everything Off"): welcomeAsked and
--     seenVersion set first (the next login gives no What's new line), then
--     the installer on its first step, a frame later (the check and the
--     window's build never share a frame). A late settings load while it
--     waits, or while it is open before an install, drops or closes it: the
--     player was not new;
--   - an existing player on a new version: one chat line (What's new), and
--     seenVersion (and welcomeAsked) set;
--   - an existing player whose account took Mello's Edit Mode layout for
--     this screen (the installer put it in, or the reskin is on: AltCheck),
--     on a character that does not use it (the
--     game keeps the active layout per character; MelloUI's settings are
--     the account's): one question, once per character, remembered in
--     UI Modifications' layoutAsked_<character> (the player's own), in
--     MelloUI's own dialog (MelloUI:Confirm). With the Gamepad UI on: one
--     chat line instead, and the question waits for the mouse UI.
-- Whatever opens waits for the end of a fight (PLAYER_REGEN_ENABLED) or for
-- Edit Mode to close ('editmode'), each taken only then. Nothing polls.
-- The player's own open (I:Open) comes first: once they opened the
-- installer, or asked for it in a fight, the window is theirs -- the check
-- opens nothing of its own, asks no alt question, and no late load closes it.
--
--   I:Open([page]) -> shown   the entry every caller shares (/mello install,
--                             the configurator's Install... and Install
--                             again: MelloUI:OpenInstaller). Refused with a
--                             chat line while the settings are still
--                             loading or Edit Mode is open; in combat it
--                             says so and opens when the fight ends; on the
--                             Keep page while an answer is owed. Marks the
--                             game menu button's one-time tip shown.
--   I:Busy() -> busy          the window shows, a countdown runs, or the
--                             first-login check (or an open it owes) has
--                             not finished: the menu button's tip yields
--------------------------------------------------------------------------------

local LOGIN_OWNER = "Installer login"   -- the bus owner while a login open waits
local CHECK_DELAY = 3

-- started: PLAYER_ENTERING_WORLD came; done: the check decided (or gave
-- up); armed: the check's timer is out; owed: what opens next frame, or once the fight or
-- Edit Mode ends ("choose", "keep", "open", "alt"); fresh: the open owed is
-- a new player's; waited: it waited for a fight or Edit Mode (the settings
-- are read again before it opens); user: the player opened the installer
-- (or asked for it) this session; altKey: the character's layoutAsked_ key
-- for the question
local login = { started = false, done = false, armed = false, owed = nil, fresh = false,
	waited = false, user = false, altKey = nil }
local loginFrame
local Check, ShowOwed

-- the window (Core/InstallerWindow.lua loads after this file)
local function Window()
	local IW = MelloUI.InstallerWindow
	return (type(IW) == "table" and type(IW.Open) == "function") and IW or nil
end

-- the settings' entries as a set, the player's own and the NEVER keys left
-- out (one-time flags the first login writes, as profiles leave them out)
local function Entries(text)
	local set, n = {}, 0
	for entry in text:gmatch("[^;]+") do
		local name, key = entry:match("^([^=.]+)%.([^=]+)=")
		if not (name and Kept(name, key)) then
			set[entry], n = true, n + 1
		end
	end
	return set, n
end

-- a new player's settings: none, or the built-in "Everything Off" (the
-- default profile a fresh install gets at login: Core's
-- ApplyDefaultProfileIfFresh), in any order
local function FreshSettings()
	local ok, text = pcall(MelloUI.SerializeSettings, MelloUI)
	if not (ok and type(text) == "string") then
		return false
	end
	local have, n = Entries(text)
	if n == 0 then
		return true
	end
	local okF, fresh = pcall(MelloUI.FreshProfileText, MelloUI)
	if not (okF and type(fresh) == "string") then
		return false
	end
	local want, m = Entries(fresh)
	if n ~= m then
		return false
	end
	for entry in pairs(have) do
		if not want[entry] then
			return false
		end
	end
	return true
end
I.FreshSettings = FreshSettings   -- (read only: the tests)

-- the game menu button's one-time tip (Core's ShowMenuButtonTip): the
-- installer took its place
local function TipShown()
	local tweaks = Module("Tweaks") and MelloUI:GetModuleDB("Tweaks")
	if type(tweaks) == "table" and tweaks.menuTipShown ~= true then
		MelloUI:NotifySettingChanged("Tweaks", "menuTipShown", true)
	end
end

-- A late settings load (or a profile load) while the new player's open
-- still waits (the frame after the check, a fight, Edit Mode), or while the
-- installer it opened is still before an install: the player was not new,
-- so the open is dropped or the window closes. Taken from the check's
-- decision on; the player's own open (I:Open) takes it away, since the
-- window is theirs then (the only other way the window shows). Never for
-- the installer's own work: a revert's last way back loads 'Before
-- install' as a profile, and that says 'restart' too.
local function OnRestart()
	if I.applying then
		return
	end
	MelloUI:Off(LOGIN_OWNER, "restart")
	if login.fresh then
		login.owed, login.fresh, login.waited = nil, false, false
		return
	end
	local IW = Window()
	if not (IW and IW:IsShown()) then
		return
	end
	local st = IW.state
	local rp = MelloUI.db and MelloUI.db.installer
	if (type(rp) == "table" and rp.pending) or (type(st) == "table" and (st.phase ~= "choose" or st.installed)) then
		return
	end
	IW:Close()
end

-- the window shown now (the caller checked the fight and Edit Mode)
local function OpenNow(page)
	local IW = Window()
	if not IW then
		return false
	end
	local ok, err = pcall(IW.Open, IW, page)
	if not ok then
		Report(err)
		return false
	end
	TipShown()
	return true
end

-- The question for a character that does not use Mello's layout (asked
-- once per character: user, 2026-09-25): remembered before it is asked, so
-- it is asked once, in MelloUI's own dialog (MelloUI:Confirm,
-- Modules/KitWindow.lua). With the Gamepad UI on nothing is asked: the
-- D-pad cannot reach that dialog, and the game's own popup would block the
-- game's protected calls. One chat line says where to pick the layout
-- instead (TEXT.altGamepad), and the question stays unasked (its key unset)
-- for a login with the mouse UI.
-- Use it makes the account's layout for this screen active on this
-- character (Core/EditModeLayout.lua; after the fight when there is one):
-- nothing is fitted or saved, so the layout another character installed
-- stays exactly as it is. Only when that layout is gone is one put in,
-- fitted to this screen.
local function AltAccept()
	local name
	if MelloUI.EditModeState then
		local ok, state = pcall(MelloUI.EditModeState, MelloUI)
		name = ok and type(state) == "table" and state.name or nil
	end
	if name and MelloUI.ActivateEditModeLayout then
		local _, _, gone = MelloUI:ActivateEditModeLayout(name)
		if not gone then
			return
		end
	end
	if MelloUI.ApplyEditModeLayout then
		MelloUI:ApplyEditModeLayout(false)
	end
end

local ALT_ASK = { text = TEXT.altQuestion, accept = TEXT.altYes, cancel = TEXT.altNo, onAccept = AltAccept }

local function AskAlt()
	local key = login.altKey
	login.altKey = nil
	if not key or type(MelloUI.Confirm) ~= "function" then
		return
	end
	if MelloUI.Safe.GamepadUI() then
		MelloUI:Notice(TEXT.altGamepad)
		return
	end
	SetOwn(key, true)
	MelloUI:Confirm(ALT_ASK)
end

local function OnLoginEditMode(entering)
	if entering == false then
		MelloUI:Off(LOGIN_OWNER, "editmode")
		C_Timer.After(0, ShowOwed)   -- (a frame later: the manager has hidden by then)
	end
end

ShowOwed = function()
	local what = login.owed
	if not what then
		return
	elseif InCombat() then
		login.waited = true
		loginFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	elseif EditModeOpen() then
		login.waited = true
		MelloUI:On("editmode", OnLoginEditMode, LOGIN_OWNER)
		return
	end
	if login.fresh and login.waited then
		-- (read again only after a wait -- the check has just read them
		-- otherwise -- and the window then built a frame later)
		login.waited = false
		if FreshSettings() then
			C_Timer.After(0, ShowOwed)
		else
			-- (settings of their own came in while it waited, a fight say:
			-- the player was not new)
			login.owed, login.fresh = nil, false
			MelloUI:Off(LOGIN_OWNER, "restart")
		end
		return
	end
	local first = login.fresh   -- (a new player's: the installer's first run)
	login.owed, login.fresh, login.waited = nil, false, false
	if what == "alt" then
		AskAlt()
	else
		local IW = Window()
		if IW and IW:IsShown() then
			MelloUI:Off(LOGIN_OWNER, "restart")
			return   -- (open already: the player's own)
		end
		if first and MelloUI.Kit and MelloUI.Kit.Showcase then
			MelloUI.Kit:Showcase(true)   -- (its first run in the kit's look, whatever the reskin)
		end
		OpenNow(what ~= "open" and what or nil)
	end
end

-- what the check owes the player, shown a frame later: the check (its
-- settings read, its Batch) and the window's build never share a frame. A
-- new player's open takes the late-load 'restart' from here on.
local function Owe(what, fresh)
	login.owed, login.fresh, login.waited = what, fresh and true or false, false
	if fresh then
		MelloUI:On("restart", OnRestart, LOGIN_OWNER)
	end
	C_Timer.After(0, ShowOwed)
end

-- the character's own key for the question: its GUID's letters and
-- digits (as Route keeps a character's flight points)
local function AltKey()
	local ok, guid = pcall(UnitGUID, "player")
	if not ok or Secret(guid) or type(guid) ~= "string" or guid == "" then
		return nil
	end
	return "layoutAsked_" .. (guid:gsub("[^%w]", ""))
end

-- The alt question: this screen's Mello layout is in the account's list,
-- the account took it, and this character's active layout is another one: ask, once. A
-- character already on it is remembered as asked (a later switch of its
-- own is its own choice). Read only until then (EditModeState).
-- (2.1.0, el-15: players' "the Edit Mode layout does not apply") The account
-- took Mello's layout: the installer put it in (layoutFitFor, written only
-- when the fitted layout went in), or the painted reskin is on (its own
-- one-time layout). Since 1.2.4 the Default and Modern skins leave the reskin
-- off, and the question was asked behind it alone: no other character was
-- ever asked, and the game kept each one on its own layout.
local function TookLayout(um)
	return type(um.layoutFitFor) == "string" or (MelloUI:IsModuleEnabled(UMB) and um.reskin ~= false)
end
I.AltKey, I.TookLayout = AltKey, TookLayout   -- (read by /mello layout check: Core/EditModeLayout.lua)

local function AltCheck()
	local key = AltKey()
	local um = MelloUI:GetModuleDB(UMB)
	if not key or um[key] ~= nil or not TookLayout(um) or not MelloUI.EditModeState then
		return
	end
	-- (2.1.46) the character's profile carries its Edit Mode layout and puts it in at the login (Core.lua's
	-- ApplyProfileEditMode): nothing to ask
	if type(um.emKind) == "string" then
		SetOwn(key, true)
		return
	end
	local ok, state = pcall(MelloUI.EditModeState, MelloUI)
	if not (ok and type(state) == "table" and state.hadMello and state.activeName ~= nil and state.name ~= nil) then
		return
	end
	if state.activeName == state.name then
		SetOwn(key, true)
		return
	end
	login.altKey = key
	Owe("alt")
end

local function Seen(version)
	SetOwn("welcomeAsked", true)
	SetOwn("seenVersion", version)
end

-- what the settled settings say (the check's second half). theirs: the
-- player opened the installer (or asked for it in a fight) before this
-- check; the check then opens nothing of its own (their window is on the
-- Keep page anyway while an answer is owed), prints no What's new line and
-- asks no alt question (asked at a later login) -- the flags are still set
local function Decide()
	local um = MelloUI:GetModuleDB(UMB)
	if type(um) ~= "table" then
		return
	end
	local theirs = login.user
	local rp = MelloUI.db.installer
	if type(rp) == "table" and type(rp.pending) == "table" then
		if not theirs then
			Owe("keep")
		end
		return
	end
	local version = MelloUI.version
	if not um.welcomeAsked and FreshSettings() then
		-- (remembered before it opens, as the old welcome was: a session that
		-- ends before an answer does not open it again and again)
		MelloUI:Batch(Seen, version)
		if not theirs then
			Owe("choose", true)
		end
		return
	end
	if um.seenVersion ~= version then
		if not theirs then
			MelloUI:Notice(TEXT.whatsNew, tostring(version))
		end
		MelloUI:Batch(Seen, version)
	end
	if not theirs then
		AltCheck()
	end
end

-- the check's one timer
local function Due()
	login.armed = false
	Check()
end

local function ArmCheck(seconds)
	if not login.armed then
		login.armed = true
		C_Timer.After(seconds, Due)
	end
end

Check = function()
	if login.done then
		return
	end
	login.done = true
	if not Settled() then
		return   -- (not known to be new: nothing this session)
	end
	local ok, err = pcall(Decide)
	if not ok then
		Report(err)
	end
end

local function OnLoginEvent(frame, event)
	if event == "PLAYER_ENTERING_WORLD" then
		frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
		if not login.started then
			login.started = true
			ArmCheck(CHECK_DELAY)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		ShowOwed()
	end
end

do
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	Perf.SetScript(frame, "OnEvent", OnLoginEvent)
	loginFrame = frame
end

-- The player's own open (it opens, or waits for the fight's end): the
-- window is theirs from now on. The first login's late-load close leaves
-- it, an open the login still owes is this one (an alt question waiting is
-- asked at a later login: never on top of the installer), and the check,
-- should it still be to come, opens nothing of its own.
local function Theirs()
	MelloUI:Off(LOGIN_OWNER)
	login.user, login.owed, login.fresh, login.waited, login.altKey = true, nil, false, false, nil
end

function I:Open(page)
	local IW = Window()
	if not IW then
		return false
	elseif IW:IsShown() then
		Theirs()
		return OpenNow(page)
	elseif not Settled() then
		MelloUI:Print(TEXT.loading)
		return false
	elseif InCombat() then
		MelloUI:Print(TEXT.openCombat)
		Theirs()
		login.owed = page or "open"
		ShowOwed()   -- (takes PLAYER_REGEN_ENABLED now)
		return false
	elseif EditModeOpen() then
		MelloUI:Print(TEXT.openEditMode)
		return false
	end
	Theirs()
	return OpenNow(page)
end

function I:Busy()
	if (login.started and not login.done) or login.owed then
		return true
	end
	local IW = Window()
	return (IW and IW:IsShown()) or CD.running or false
end
