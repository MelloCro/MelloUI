--------------------------------------------------------------------------------
-- MelloUI - Installer: the engine and its data
--
-- The first-login installer is a front end over systems MelloUI already has,
-- not a second settings system:
--   - the profiles: "Full experience" IS the shipped profile "MelloUI"
--     (Media/Profiles.lua), read from the shipped table, never a saved copy;
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
-- A setup's TARGET is such a state, made from the player's current one,
-- Full's text and the modules' roles (RoleOf), then applied in one Batch and
-- taken back exactly (the restore point, db.installer).
--
--   I.OPTIONS, I:Option(key)            the four setups (Full experience, No
--                                       reskin, Reskin only, Fresh start)
--                                       and the hidden refit, "fit" (Fit to
--                                       this screen: the layout and the
--                                       window places fitted again, every
--                                       other setting the player's own)
--   I.RoleOf(module), I.Kind(module)    what a module is, what switches it
--   I:FullText() -> text                the shipped Full
--   I:Capture() -> state                every module's settings, exactly
--   I:TargetFromText(text[, cur])       defaults + text; the player's own
--                                       (personal) and NEVER keys = cur's
--   I:Draft(state, draft) -> state      a Fresh start draft laid on
--   I:DefaultDraft([full]) -> draft     the wizard's controls at Full's values
--   I:TargetFor(option, draft, fit[, cur]) -> state
--   I:EffectiveOn(state, module)        its running state under that state
--   I:LayoutOn(option, draft, fit)      the fitted Edit Mode layout goes in
--   I:PlacesToTarget(target, fit, option, draft[, cur])
--   I:StartFit(option, draft, done) -> fit; I:CancelFit(fit)
--       the fitter (LayoutFit:Run: a frame's share at a time) on the setup's
--       own target, from the next frame on; done(fit) on a later frame,
--       fit = { option, W, H, done, fitted, places, report }
--   I:Apply(target, exact) -> changed, needsReload
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
--   I:Keep() -> needsReload[, why]      (refused for a failed pending:
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
-- The bus topic "installer" tells the window what happened:
--   ("installed", optionKey, needsReload)   ("countdown", seconds, paused, why)
--   ("kept", needsReload)                   ("reverted", reason, reloadOwed)
--   ("revertFailed", reason, why)
-- A draft (Fresh start's wizard) is { ["Module.key"] = value,
-- ["!Module"] = on, layout = on }: nothing is written until Install. A
-- feature switched on there (I.SwitchKey(module) true) takes Full's settings
-- for that module, the draft's own keys over them; a personal key the draft
-- sets (Dark Mode: the player's own preference) goes in as set, and a revert
-- takes it back (target.explicit, copied onto the restore point).
--   I.FEATURE_GROUPS, I.SwitchKey(module), I:FeaturesOn(draft) -> names
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
local FULL_PROFILE = "MelloUI"          -- the shipped Full experience
local BEFORE_PROFILE = "Before install" -- the restore point on the Profiles page
local KEEP_SECONDS = 15
local EMPTY = {}

I.FULL_PROFILE, I.BEFORE_PROFILE, I.KEEP_SECONDS = FULL_PROFILE, BEFORE_PROFILE, KEEP_SECONDS
-- (compared with a restore point's `at`, time() when it was made)
I.SESSION_AT = tonumber(time and time()) or 0

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

-- A module's role (what a setup does with it). A module's own `role`
-- (RegisterModule) wins; a hidden kit panel (it carries `window`) is look;
-- these are the roles of the modules that do not declare one yet:
--   core      UI Modifications, the switchboard
--   look      restyles the game's art, fonts or sounds
--   feature   MelloUI's own tools
--   adds      adds information or automation without restyling
--   replaces  replaces or restyles a game part
local ROLE = {
	UIModifications = "core",
	DarkMode = "look", Fonts = "look", ClassIcons = "look", BarTextures = "look", CustomSounds = "look",
	QuestList = "feature", Route = "feature", Services = "feature", PartyMarkers = "feature", VoiceOver = "feature",
	BarText = "adds", CooldownText = "adds", Tweaks = "adds", Stats = "adds", Vendor = "adds", Chat = "adds",
	Nameplates = "adds", ErrorFilter = "adds",
	QuestTracker = "replaces", Auras = "replaces", Tooltip = "replaces", UnitFrames = "replaces",
}

-- UI Modifications' own keys by role: its look keys (the kit panels' keys
-- and the border kinds' keys are found at call time: the registry and
-- Kit.borderKinds), and the one preference Full and Fresh start carry.
-- qol_<Module> follows that module's role; the rest is never set by a role.
local U_LOOK = { reskin = true, questTrackerKit = true, preloadArt = true, fadeWindows = true, positions = true, autoSnap = true }
local U_PREFERENCE = { nameFormat = true }

-- keys no setup ever sets: the player's accessibility choice, a passing
-- mode, the switch Tweaks lost (its one-time fold resets rows reading false)
local NEVER = { [UMB] = { reduceMotion = true, unlock = true, qol_Tweaks = true } }

-- the installer's own facts about this machine and character, and a
-- one-time flag: the player's own like the keep lists' keys (never carried
-- by a setup, never taken back by one). Exact keys, or patterns with ^.
local OWN = { [UMB] = { seenVersion = true, layoutFitFor = true, layoutApplied = true, questTrackerKitMigrated = true, "^layoutAsked_" } }
-- of those, what an install that puts the layout in writes, and a revert puts back
local LAYOUT_OWN = { "layoutFitFor", "layoutApplied" }

-- "No reskin": Chat's and Tweaks' art-hiding rows act while the reskin is
-- off, so they are neutral there (the chat buttons and background stay, and
-- the chat windows keep the game's own background opacity)
local NO_RESKIN_ROWS = {
	["Chat.hideButtons"] = false, ["Chat.hideBackground"] = false, ["Chat.hideEditBox"] = false,
	["Chat.hideTabs"] = false, ["Chat.tabsOnMouseover"] = false, ["Chat.editBoxTop"] = false,
	["Chat.windowAlphaOn"] = false,
	["Tweaks.hideMinimapCoords"] = false, ["Tweaks.hideMicroMenu"] = false, ["Tweaks.hideBagBar"] = false,
}

-- parchment areas whose sheet and dark ink belong to different modules: the
-- paper never shows while its ink's module is off (the parchment ink rule)
local INK = { chat = { sheet = "ChatPanel", ink = "Chat" } }
I.INK, I.NEVER, I.NO_RESKIN_ROWS = INK, NEVER, NO_RESKIN_ROWS   -- (read only: the tests and the window read them)

-- keys a module's OnSettingChanged expands into others: written first
-- (written after the faces, the Font Style would flip to "custom")
local LEADERS = { Fonts = { "style" } }
-- values the game reads once at start-up: a change there owes a reload
-- (the names over heads and the combat text)
local STARTUP = { Fonts = { fontText = true, fontDamage = true } }
-- modules whose OnSettingChanged walks everything once per key: with 2 or
-- more keys to change they go off first and on last, so the walk runs once
local BUNDLE = { Fonts = true }

local function Merge(a, b)
	local t = {}
	for k, v in pairs(a) do
		t[k] = v
	end
	for k, v in pairs(b) do
		t[k] = v
	end
	return t
end

-- The four setups, and the refit. whole: Full's state as it is; roles: what
-- each role takes ("full": Full's settings and switch, "off": switched off,
-- nil: the player's own); set: laid over last; base "fresh": Everything Off
-- and the wizard's draft (each feature switched on there with Full's
-- settings); refit: the player's own state as it is; layout:
-- the fitted Edit Mode layout ("draft": the Screen step's switch); places:
-- the fitter's window places; hidden: no card on the Setup step (the refit
-- has its own entry: the configurator's Fit to this screen, when Mello's
-- layout went in fitted to another screen size or UI scale).
I.OPTIONS = {
	{ key = "full", title = "Full experience", tag = "Recommended",
	  desc = "Mello's layout, looks and features, set up for your screen.",
	  whole = true, layout = true, places = true, steps = { "choose", "fit", "review", "keep" } },
	{ key = "noReskin", title = "No reskin, features on",
	  desc = "Your UI and bars stay. MelloUI's features switch on.",
	  roles = { feature = "full", adds = "full" },
	  set = Merge(NO_RESKIN_ROWS, { ["UIModifications.reskin"] = false, ["!UIModifications"] = true }),
	  layout = false, places = false, steps = { "choose", "review", "keep" } },
	{ key = "reskinOnly", title = "Reskin only",
	  desc = "The painted look and layout. Features stay off.",
	  roles = { look = "full", feature = "off", adds = "off", replaces = "off" },
	  set = { ["!UIModifications"] = true },
	  layout = true, places = true, steps = { "choose", "fit", "review", "keep" } },
	{ key = "fresh", title = "Fresh start",
	  desc = "Everything off. Set it up step by step.",
	  base = "fresh", layout = "draft", places = false,
	  -- (the Minimap and Features steps before the Screen step: the fitter
	  -- reads the map's shape, the merge, the Services bar, the tracker, the
	  -- buff rows and the FPS text)
	  steps = { "choose", "look", "map", "parchment", "fonts", "features", "fit", "chat", "windows", "review", "keep" } },
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

-- The Fresh start wizard's Windows step: the kit panels in six groups (the
-- 43 of the Windows tab and the 10 of the HUD)
I.WINDOW_GROUPS = {
	{ key = "character", label = "Your character", members = { "CharacterPanel", "SpellBookPanel", "ProfessionsPanel",
		"LegacyPanel", "CollectionsPanel", "BackpackPanel", "QuestLogPanel", "InspectPanel", "DressUpPanel", "SocketingPanel",
		"BarberShopPanel" } },
	{ key = "shops", label = "Shops, mail, bank, trainers", members = { "MerchantPanel", "AuctionHousePanel", "TrainerPanel",
		"TabardPanel", "TaxiPanel", "MailPanel", "BankPanel", "GuildBankPanel", "TradePanel", "LootPanel", "StablePanel",
		"QuestDialogPanel", "ItemTextPanel", "CharterPanel" } },
	{ key = "social", label = "Social, guild, group finder", members = { "SocialPanel", "GuildPanel", "GroupFinderPanel",
		"PvPPanel", "BattlefieldMapPanel", "ReadyPanel" } },
	{ key = "options", label = "Options, macros, Edit Mode, AddOn list", members = { "GameMenuPanel", "OptionsPanel",
		"MacroPanel", "EditModePanel", "AddonListPanel", "DialogPanel", "StackSplitPanel", "ColorPickerPanel" } },
	{ key = "calendar", label = "Calendar, clock, help, channels", members = { "CalendarPanel", "ClockPanel", "HelpPanel",
		"ChannelPanel" } },
	{ key = "hud", label = "The HUD", members = { "UnitFramePanel", "CastBarPanel", "RaidFramePanel", "ActionBarPanel",
		"MinimapPanel", "TrackerPanel", "ChatPanel", "DamageMeterPanel", "TooltipPanel", "NameplatePanel" } },
}

-- The Fresh start wizard's Features step: every feature, adds and replaces
-- module with a switch of its own, in two columns (Chat has its own step;
-- Tweaks has no switch). Each starts off; one switched on takes Full's
-- settings for that module.
I.FEATURE_GROUPS = {
	{ key = "quests", label = "Quests, travel and your group", members = { "QuestList", "QuestTracker", "Route", "Services",
		"PartyMarkers", "VoiceOver", "Vendor" } },
	{ key = "combat", label = "Combat, frames and tooltips", members = { "Auras", "CooldownText", "ErrorFilter", "Nameplates",
		"UnitFrames", "BarText", "Tooltip", "Stats" } },
}

-- the lines the window shows (its footer, the Keep page)
I.TEXT = {
	loading = "MelloUI's settings are still loading; try again in a moment.",
	combat = "Install waits until you are out of combat.",
	editMode = "Close Edit Mode first.",
	fitting = "Your screen is still being fitted.",
	refit = "Your screen changed; it is being fitted again.",
	noRoom = "Edit Mode already keeps %d account layouts, the most it can. Delete one in Edit Mode, or switch the layout off on the Screen step.",
	pending = "Keep or revert the setup you just installed first.",
	nothing = "There is no setup to go back to.",
	pausedCombat = "Paused while you are in combat.",
	revertCombat = "Revert waits until you are out of combat; try again then.",   -- (the configurator's Revert...)
	pausedEditMode = "Paused while Edit Mode is open.",
	installed = "%s installed. Keep it, or MelloUI goes back to 'Before install' when the timer runs out.",
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
-- same, off unless true; "always": folded, no switch; "module": its own flag
local function Kind(m)
	local tweak = m and m.tweak
	if type(tweak) == "table" then
		return tweak.always and "always" or (tweak.off and "tweakOff") or "tweak"
	elseif m and m.hidden and type(m.window) == "table" then
		return "panel"
	end
	return "module"
end
I.Kind = Kind

local function RoleOf(m)
	if not m then
		return nil
	end
	return m.role or (m.hidden and type(m.window) == "table" and "look") or ROLE[m.name] or nil
end
I.RoleOf = RoleOf

-- the roles a feature switch in the wizard takes Full's settings for
local FEATURE_ROLES = { feature = true, adds = true, replaces = true }

-- the draft key that switches a module: its own flag, or UI Modifications'
-- qol_<name> for a folded feature (nil: a kit panel, or one with no switch)
local function SwitchKey(m)
	local kind = m and Kind(m)
	if kind == "module" then
		return "!" .. m.name
	elseif kind == "tweak" or kind == "tweakOff" then
		return UMB .. ".qol_" .. m.name
	end
	return nil
end
I.SwitchKey = SwitchKey

-- the Features step's members the draft switches on, in the step's order
function I:FeaturesOn(draft)
	local on = {}
	if type(draft) ~= "table" then
		return on
	end
	for _, group in ipairs(self.FEATURE_GROUPS) do
		for _, name in ipairs(group.members) do
			local key = SwitchKey(MelloUI.modules[name])
			if key and draft[key] == true then
				on[#on + 1] = name
			end
		end
	end
	return on
end

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

-- UI Modifications' own key's role (nil: never set by a role rule)
local function UKeyRole(key)
	if type(key) ~= "string" then
		return nil
	end
	if U_LOOK[key] or key:sub(1, 10) == "parchment_" then
		return "look"
	elseif U_PREFERENCE[key] then
		return "preference"
	end
	local Kit = MelloUI.Kit
	local kinds = type(Kit) == "table" and type(Kit.borderKinds) == "table" and Kit.borderKinds or EMPTY
	for i = 1, #kinds do
		if kinds[i].key == key then
			return "look"
		end
	end
	local m = Module(key)
	if m and Kind(m) == "panel" then
		return "look"
	end
	return nil
end
I.UKeyRole = UKeyRole

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
	elseif kind == "always" then
		return true
	elseif kind == "tweakOff" then
		return um["qol_" .. name] == true
	end
	return um["qol_" .. name] ~= false
end

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

-- the shipped Full experience: never db.profiles.MelloUI (a player's own
-- save of that name, or an older shipped copy, could stand in for it)
function I:FullText()
	local shipped = type(MelloUI_Profiles) == "table" and type(MelloUI_Profiles.profiles) == "table"
		and MelloUI_Profiles.profiles[FULL_PROFILE]
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
				if name then
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

-- what pressing Continue through every wizard step gives: each control at
-- Full's value (the look, minimap, parchment, fonts, chat and windows
-- steps), every feature off (the Features step), and Dark Mode as the
-- player has it now (their own preference: no profile carries it; off for a
-- new player)
local DRAFT_UM = { reskin = true, kitColours = true, buttonBorder = true, qol_ClassIcons = true,
	qol_Fonts = true, qol_Chat = true }
local DRAFT_MAP = { "shape", "squareBorder", "servicesMerge" }
function I:DefaultDraft(full)
	full = full or self:TargetFromText(self:FullText())
	local d = { ["!UIModifications"] = true }
	for key, v in pairs(full.modules[UMB] or EMPTY) do
		if type(key) == "string" and not Kept(UMB, key) and (DRAFT_UM[key] or key:sub(1, 10) == "parchment_"
			or (Module(key) and Kind(Module(key)) == "panel")) then
			d["UIModifications." .. key] = DeepCopy(v)
		end
	end
	for k, v in pairs(full.modules.Fonts or EMPTY) do
		if type(k) == "string" and not Kept("Fonts", k) then
			d["Fonts." .. k] = DeepCopy(v)
		end
	end
	local icons, chat = full.modules.ClassIcons or EMPTY, full.modules.Chat or EMPTY
	d["ClassIcons.portraits"] = icons.portraits
	d["Chat.nameStyle"], d["Chat.nameShade"] = chat.nameStyle, chat.nameShade
	local map = full.modules.MinimapPanel or EMPTY
	for _, k in ipairs(DRAFT_MAP) do
		d["MinimapPanel." .. k] = DeepCopy(map[k])
	end
	for _, group in ipairs(self.FEATURE_GROUPS) do
		for _, name in ipairs(group.members) do
			local key = SwitchKey(Module(name))
			if key then
				d[key] = false
			end
		end
	end
	-- Dark Mode: its switch as the player has set it (on only when switched
	-- on: off until then), and its brightness as set
	local dark = Module("DarkMode")
	if dark then
		local v = MelloUI:GetModuleDB(UMB).qol_DarkMode
		d[UMB .. ".qol_DarkMode"] = (Kind(dark) == "tweakOff" and v == true or Kind(dark) ~= "tweakOff" and v ~= false) and true or false
		d["DarkMode.shade"] = DeepCopy(MelloUI:GetModuleDB("DarkMode").shade)
	end
	return d
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

-- a module's switch as another state has it
local function CopySwitch(t, from, m)
	local kind, name = Kind(m), m.name
	local um, fum = t.modules[UMB], from.modules[UMB] or EMPTY
	if kind == "panel" then
		um[name] = DeepCopy(fum[name])
	elseif kind == "tweak" or kind == "tweakOff" then
		um["qol_" .. name] = DeepCopy(fum["qol_" .. name])
	elseif kind == "module" then
		t.enabled[name] = from.enabled[name]
	end   -- always: no switch
end

local function SwitchOff(t, m)
	local kind, name = Kind(m), m.name
	if kind == "tweak" or kind == "tweakOff" then
		t.modules[UMB]["qol_" .. name] = false
	elseif kind == "module" then
		t.enabled[name] = false
	end   -- panel: through the reskin (the setup's own set); always: untouched
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
-- (Reskin only; Fresh start with its Chat step off) carries Full's two rows
-- as Full's text has them (a row the wizard's draft sets stays the draft's).
-- With the reskin off they stay as the setup has them (NO_RESKIN_ROWS).
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
	if option.whole then
		t = self:TargetFromText(self:FullText(), cur)
	elseif option.refit then
		t = DeepCopy(cur)
	elseif option.base == "fresh" then
		-- Everything Off; each feature the draft switches on (the Features
		-- step, Chat's own step) with Full's settings for that module; then the
		-- draft's own keys over them (Chat's name form, say)
		local base, full = self:TargetFromText(MelloUI:FreshProfileText(), cur), nil
		-- (with the reskin switched off, a table taken from Full keeps the
		-- rows No reskin keeps neutral: the chat's buttons, background and
		-- opacity stay the game's)
		local plain = draft and draft[UMB .. ".reskin"] == false
		for name, m in MelloUI:IterateModules() do
			local key = FEATURE_ROLES[RoleOf(m)] and SwitchKey(m)
			if key and draft and draft[key] == true then
				full = full or self:TargetFromText(self:FullText(), cur)
				local taken = DeepCopy(full.modules[name])
				if plain and type(taken) == "table" then
					for spec, v in pairs(NO_RESKIN_ROWS) do
						local row = spec:sub(1, #name + 1) == name .. "." and spec:sub(#name + 2)
						if row then
							taken[row] = v
						end
					end
				end
				base.modules[name] = taken
			end
		end
		t = self:Draft(base, draft or EMPTY)
		t.explicit = ExplicitOf(draft)
		ReskinAlpha(self, t, full, cur, draft)
	else
		local full = self:TargetFromText(self:FullText(), cur)
		t = DeepCopy(cur)
		t.modules[UMB] = t.modules[UMB] or {}
		local roles = option.roles or EMPTY
		for name, m in MelloUI:IterateModules() do
			if name ~= UMB then
				local how = roles[RoleOf(m)]
				if how == "full" then
					t.modules[name] = DeepCopy(full.modules[name])
					CopySwitch(t, full, m)
				elseif how == "off" then
					SwitchOff(t, m)
				end
			end
		end
		local um, fum = t.modules[UMB], full.modules[UMB] or EMPTY
		for _, key in ipairs(SortedUnion(um, fum)) do
			local role = UKeyRole(key)
			if role and roles[role] == "full" then
				um[key] = DeepCopy(fum[key])
			end
		end
		t = Overlay(t, option.set)
		ReskinAlpha(self, t, full, cur)
	end
	t.activeProfile = nil
	if not forFit then
		self:PlacesToTarget(t, fit, option, draft, cur)
	end
	InkGuard(self, t)
	KeepUntouched(t, cur)
	-- the personal keys the draft sets itself (the wizard's Dark Mode: the
	-- player choosing their own preference) go in as set
	for name, keys in pairs(t.explicit or EMPTY) do
		for key in pairs(keys) do
			t.modules[name] = t.modules[name] or {}
			t.modules[name][key] = DeepCopy(draft[name .. "." .. key])
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
	return type(fit.report) == "table" and fit.report.pass and true or false
end

-- whether Install must wait for the fit: the window places, or the layout
local function NeedsFit(option, draft)
	if option.places then
		return true
	end
	return option.layout and not (draft and draft.layout == false) and true or false
end

-- the four frames Edit Mode places: the fit's places.remove, or, when no
-- fit was given (No reskin, a Fresh start without the layout), the fitter's
-- own list (LayoutFit.EDIT_MODE_FRAMES: one list, never a copy here)
local function EditModeFrames(remove)
	if type(remove) == "table" then
		return remove
	end
	local LayoutFit = MelloUI.LayoutFit
	local list = type(LayoutFit) == "table" and LayoutFit.EDIT_MODE_FRAMES
	return type(list) == "table" and list or EMPTY
end

-- Edit Mode keeps the player's own layout: its frames' store places and the
-- tracker's own place as the player has them (Full's text has none of them,
-- and Reskin only takes Full's whole store)
local function KeepOwnLayoutPlaces(target, cur, remove)
	local um = target.modules[UMB]
	local have = (cur.modules[UMB] or EMPTY).positions
	have = type(have) == "table" and have or EMPTY
	for _, key in ipairs(EditModeFrames(remove)) do
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
end

-- The fitter's places into the target (inside the one Batch like every
-- other setting). With the layout: the four Edit Mode frames' store places
-- removed, the tracker's own place cleared and its sizes, the Quest List's
-- width, the window places, the buff rows by the minimap's column (Icons
-- Per Row, Icon Size) as the fit wrapped them. Without it (the switch off, a FAIL, No reskin,
-- no fit): only the window places and the Quest List's width; Edit Mode
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
	if not layoutOn and type(cur) == "table" then
		KeepOwnLayoutPlaces(target, cur, places and places.remove)
	end
	if not (places and (option.places or layoutOn)) then
		return target
	end
	local store = type(um.positions) == "table" and um.positions or {}
	um.positions = store
	if option.places then
		for key, p in pairs(type(places.windows) == "table" and places.windows or EMPTY) do
			store[key] = DeepCopy(p)
		end
	end
	local ql = places.questList
	if type(ql) == "table" and ql.width ~= nil and target.modules.QuestList then
		target.modules.QuestList.width = ql.width
	end
	if layoutOn then
		for _, key in ipairs(type(places.remove) == "table" and places.remove or EMPTY) do
			store[key] = nil
		end
		local qt, t = places.questTracker, target.modules.QuestTracker
		if type(qt) == "table" and t then
			if qt.clearPos then
				t.pos = nil
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
-- converted here while that file has no EditModeLayoutInfo)
local function LayoutInfo()
	if MelloUI.EditModeLayoutInfo then
		local ok, info = pcall(MelloUI.EditModeLayoutInfo, MelloUI)
		return ok and type(info) == "table" and info or nil
	end
	local data = MelloUI_EditModeLayout
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

-- the frame after StartFit: the setup's target read into the fitter's inputs
-- (1-2 ms, kept out of the click's frame), then the fitter's own frames
local function BeginFit(fit)
	if fit.cancelled then
		return
	end
	local LayoutFit = MelloUI.LayoutFit
	local inputs = LayoutFit:Inputs(Reader(I, Target(I, fit.option, fit.draft, nil, nil, true)))
	-- (the installer writes the buff rows the fit wraps: I:PlacesToTarget)
	if type(inputs) == "table" and type(inputs.auras) == "table" then
		inputs.auras.fitRows = true
	end
	fit.W, fit.H = ScreenSize()
	fit.job = LayoutFit:Run(LayoutInfo(), fit.W, fit.H, inputs, function(fitted, places, report)
		Fitted(fit, fitted, places, report)
	end)
end

-- The fit for a setup: the fitter reads the setup's own target (Full's
-- window places, the tracker and the Quest List as the setup leaves them;
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
-- a new player's never had: bound for the refresh only.
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
	for _, key in ipairs(SortedUnion(pending)) do
		pending[key] = nil
		if not Equal(umNow[key], umStart[key]) and type(Kit) == "table" then
			local how, what = LookKind(key)
			local ok, err = true, nil
			if how == "border" and Kit.ApplyBorder then
				ok, err = pcall(Kit.ApplyBorder, Kit, what)
			elseif how == "parchment" and Kit.SetParchment then
				ok, err = pcall(Kit.SetParchment, Kit, what, umNow[key] == true)
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
		if name == UMB and not (umModule and umModule.isEnabled) and LookKind(key) then
			lookPending[key] = true
		end
		MelloUI:NotifySettingChanged(name, key, DeepCopy(value))
	end
	-- a key the apply leaves alone: the player's own and NEVER keys, unless
	-- the target sets it itself (target.explicit: the wizard's Dark Mode)
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

-- Returns how many settings and switches were written, and whether a
-- value the game reads at start-up changed (a reload is owed then). Quiet
-- while it runs: `applying` for the modules that ask, and the chat lines
-- held for the log (MelloUI.printHold).
function I:Apply(target, exact)
	assert(type(target) == "table" and type(target.modules) == "table" and type(target.enabled) == "table",
		"MelloUI.Installer:Apply needs a state")
	local out = { changed = 0, reconcile = 0, lookRefresh = {} }
	local was = StartupValues()
	self.applying = true
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 0) + 1
	local ok, err = pcall(DoApply, self, target, exact, out)
	MelloUI.printHold = (tonumber(MelloUI.printHold) or 1) - 1
	self.applying = false
	if not ok then
		error(err, 0)
	end
	self.lastApply = out
	return out.changed, NeedsReload(was)
end

-- Every registered window put where the store now says. A window that
-- keeps its own place (entry.save: the Quest Tracker) moved on its own
-- 'setting' Fire and is left alone: never ResetMover or entry.reset here,
-- which would wipe the place just applied and write settings outside the
-- Batch. A hidden window gets its place on its next show (Core's OnShow).
function I:PlaceWindows()
	local placed = { restored = 0, defaulted = 0, skipped = 0 }
	for _, entry in ipairs(MelloUI:MoverEntries()) do
		if entry.save then
			placed.skipped = placed.skipped + 1
		elseif entry.key ~= nil and MelloUI:GetPosition(entry.key) then
			MelloUI:RestorePosition(entry.key, entry.frame)
			placed.restored = placed.restored + 1
		elseif entry.default then
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
			return TEXT.noRoom:format(most)
		end
	end
	return nil
end

-- The setup, its layout and its facts, in one Batch (one backup), then the
-- windows re-placed. The layout facts: layoutFitFor only when the fitted
-- layout really went in; layoutApplied whenever the layout went in or the
-- setup leaves the reskin on (the installer answered the layout question:
-- a later hand switch of the reskin never puts the raw layout over the
-- player's "my own layout stays"). Both noted on the restore point before
-- they are written, so a revert, or a fault half way, puts them back.
local function DoInstall(self, rp, option, target, fit, layoutOn, out)
	-- the restore point on the Profiles page (it sets the active profile:
	-- after the capture, and the revert puts the old name back); its text is
	-- kept on the restore point too, for a revert whose exact apply fails
	MelloUI:SaveProfile(BEFORE_PROFILE)
	rp.text = MelloUI:Profiles()[BEFORE_PROFILE]
	MelloUI:Batch(function()
		out.changed, out.needsReload = self:Apply(target)
		SetOwn("seenVersion", MelloUI.version)
		if layoutOn then
			-- (layoutWritten: handed to Edit Mode, so a revert puts its state
			-- back, even when Edit Mode refused it or a later step failed)
			rp.layoutPut, rp.layoutWhy, rp.layoutWritten = PutLayout(fit)
		end
		if rp.layoutPut or ReskinStaysOn(target) then
			rp.layoutFlags = true
			if rp.layoutPut then
				SetOwn("layoutFitFor", fit.places and fit.places.layoutFitFor or nil)
			end
			SetOwn("layoutApplied", true)
		end
	end)
	-- (the refit changes only what no profile carries -- the layout, the
	-- places -- so the profile in use stays named)
	MelloUI.db.activeProfile = option.whole and FULL_PROFILE or (option.refit and rp.before.activeProfile) or nil
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
	-- 2. the restore point (in the db this session runs on: never the
	-- global, which may not be there yet on this client)
	local rp = { before = before, layout = layoutBefore, option = option.key, at = time() }
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
		rp.pending = { option = option.key, needsReload = false, reloadedSince = false, failed = true }
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
	local changed, needsReload = out.changed, out.needsReload
	-- 7. the answer the countdown waits for
	rp.pending = { option = option.key, needsReload = needsReload and true or false, reloadedSince = false }
	MelloUI:Print(TEXT.installed, option.title)
	self:StartCountdown(KEEP_SECONDS)
	MelloUI:Fire("installer", "installed", option.key, rp.pending.needsReload)
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
	local placed, err = pcall(self.PlaceWindows, self)
	if not placed then
		Report(err)
	end
	rp.pending = nil
	rp.layoutWritten, rp.layoutPut, rp.layoutFlags = nil, nil, nil
	local reloaded = rp.reloadedSince or (pending and pending.reloadedSince)
	local reloadOwed = (needsReload and reloaded) and true or false
	MelloUI:Print(TEXT.reverted)
	MelloUI:Fire("installer", "reverted", reason, reloadOwed)
	NoteCost("revert", "Revert (" .. tostring(reason) .. ")", t0)
	return true, nil, reloadOwed
end

-- The setup kept: the countdown ends; whether a reload is owed (the names
-- over heads read their font at start-up; none once the game has read the
-- installed fonts: a /reload or a restart since the install). An install that faulted half
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
	local needsReload = (pending.needsReload and not pending.reloadedSince) and true or false
	MelloUI:Fire("installer", "kept", needsReload)
	return needsReload
end

--------------------------------------------------------------------------------
-- The entry, and the first login: the installer owns it (the tour's old
-- welcome popup is gone)
--
-- At login nothing is built but one hidden event frame, made as this file
-- loads (it replaces the one the tour's old welcome popup had: the count
-- stays the same). It takes PLAYER_ENTERING_WORLD once; 3 s later, one
-- check:
--   - the settings not settled yet (Backup.lua: a player whose settings
--     have not appeared is not known to be new): checked again on
--     UPDATE_MACROS (taken only then) or 3 s later, at most 6 more times,
--     never past 20 s after the first check; then nothing this session;
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
--   - an existing player with the reskin on whose account has Mello's Edit
--     Mode layout for this screen, on a character that does not use it (the
--     game keeps the active layout per character; MelloUI's settings are
--     the account's): one question, once per character, remembered in
--     UI Modifications' layoutAsked_<character> (the player's own).
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
--                             game menu button's one-time tip shown (the
--                             Done page says where the settings live).
--   I:Busy() -> busy          the window shows, a countdown runs, or the
--                             first-login check (or an open it owes) has
--                             not finished: the menu button's tip yields
--------------------------------------------------------------------------------

local LOGIN_OWNER = "Installer login"   -- the bus owner while a login open waits
local CHECK_DELAY, CHECK_AGAIN, CHECK_MORE, CHECK_GIVE_UP = 3, 3, 6, 20
local ALT_POPUP = "MELLOUI_LAYOUT_ALT"

-- started: PLAYER_ENTERING_WORLD came; done: the check decided (or gave
-- up); first: its first run's time; more: the checks run again; armed: a
-- check's timer is out; owed: what opens next frame, or once the fight or
-- Edit Mode ends ("choose", "keep", "open", "alt"); fresh: the open owed is
-- a new player's; waited: it waited for a fight or Edit Mode (the settings
-- are read again before it opens); user: the player opened the installer
-- (or asked for it) this session; altKey: the character's layoutAsked_ key
-- for the question
local login = { started = false, done = false, first = nil, more = 0, armed = false, owed = nil, fresh = false,
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
-- it is asked once. The game's own popup, its dialog registered only now.
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

local ALT_DIALOG = { text = TEXT.altQuestion, button1 = TEXT.altYes, button2 = TEXT.altNo, OnAccept = AltAccept,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }

local function AskAlt()
	local key = login.altKey
	login.altKey = nil
	if not key or type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
		return
	end
	SetOwn(key, true)
	StaticPopupDialogs[ALT_POPUP] = ALT_DIALOG
	StaticPopup_Show(ALT_POPUP)
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
	login.owed, login.fresh, login.waited = nil, false, false
	if what == "alt" then
		AskAlt()
	else
		local IW = Window()
		if IW and IW:IsShown() then
			MelloUI:Off(LOGIN_OWNER, "restart")
			return   -- (open already: the player's own)
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
-- the reskin is on, and this character's active layout is another one: ask, once. A
-- character already on it is remembered as asked (a later switch of its
-- own is its own choice). Read only until then (EditModeState).
local function AltCheck()
	local key = AltKey()
	local um = MelloUI:GetModuleDB(UMB)
	if not key or um[key] ~= nil or not (MelloUI:IsModuleEnabled(UMB) and um.reskin ~= false) or not MelloUI.EditModeState then
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

local function Finish()
	login.done = true
	loginFrame:UnregisterEvent("UPDATE_MACROS")
end

-- the check's one timer (never two out: an early check on UPDATE_MACROS
-- leaves the one that is out, which then finds the check done)
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

-- early: the check UPDATE_MACROS brought forward (it counts as none of the
-- 6; the timer that is out stays)
Check = function(early)
	if login.done then
		return
	end
	local now = Num(GetTime()) or 0
	login.first = login.first or now
	if Settled() then
		Finish()
		local ok, err = pcall(Decide)
		if not ok then
			Report(err)
		end
		return
	end
	if early ~= true then
		if login.more >= CHECK_MORE or now - login.first >= CHECK_GIVE_UP then
			Finish()   -- (not known to be new: nothing this session)
			return
		end
		login.more = login.more + 1
		ArmCheck(CHECK_AGAIN)
	end
	loginFrame:RegisterEvent("UPDATE_MACROS")
end

local function Early()
	Check(true)
end

local function OnLoginEvent(frame, event)
	if event == "PLAYER_ENTERING_WORLD" then
		frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
		if not login.started then
			login.started = true
			ArmCheck(CHECK_DELAY)
		end
	elseif event == "UPDATE_MACROS" then
		frame:UnregisterEvent("UPDATE_MACROS")
		-- (a frame later: Backup.lua's own handler, which restores and
		-- settles, has run by then)
		C_Timer.After(0, Early)
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
