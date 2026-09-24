--------------------------------------------------------------------------------
-- MelloUI - UI Modifications
--
-- One entry in the configurator for everything that changes how the
-- interface looks and behaves per area (user, 2026-09-21): the painted-kit
-- RESKIN (the first, important option: on or off as a whole, then one
-- toggle per area) and the per-area quality-of-life tweaks (nameplates,
-- tooltips, chat, unit frames), which work whether the reskin is on or
-- off. The only thing that matters is that this module is enabled: off,
-- every reskin panel and every folded tweak goes with it.
--
-- The kit panels (Modules/*Panel.lua) and the folded tweak modules stay
-- separate modules in the code, each with its own /xxdump; they are HIDDEN
-- from the configurator and switched from here. A tweak module's own
-- options are shown on this page under its area (`include`), routed to that
-- module's settings by the configurator.
--
-- Folded in as well (user, 2026-09-21/22/24): Tweaks, Vendor, FPS / Latency,
-- Fonts, Bar Textures, Bar Text, Class Icons, Cooldown Timers, Dark Mode,
-- Buffs & Debuffs and Error Messages. Only the feature modules (Quest List,
-- Route, Services, Party Markers, Custom Sounds, Voice Over, Quest Tracker)
-- keep tiles of their own.
--
-- The page (2026-09-24) is switches and sliders on eight tabs: General,
-- Windows, HUD, Combat, Unit Frames & Bars, Chat & Tooltips, Text, Dark
-- Mode / Other. The look is chosen in Dynamic UI Modification only.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("UIModifications")
local hooksecurefunc = Perf.hooksecurefunc

-- The reskin panels: { module name, toggle label, description, tab }. The
-- look of each (backgrounds, backdrops, the minimap's shape) is chosen in
-- Dynamic UI Modification; here only whether the area is reskinned.
local PANELS = {
	{ "CharacterPanel",   "Character window",       "Equipment, stats, reputation and skills in the kit.", tab = "Windows" },
	{ "SpellBookPanel",   "Spell book",             "The spell book and its tabs in the kit.", tab = "Windows" },
	{ "ProfessionsPanel", "Professions",            "The profession book and crafting window in the kit.", tab = "Windows" },
	{ "LegacyPanel",      "Legacy window",          "Rewards, challenges and the tree in the kit.", tab = "Windows" },
	{ "QuestLogPanel",    "Quest log",              "The quest log in the world map window and MelloUI's quest list in the kit.", tab = "Windows" },
	{ "GuildPanel",       "Guild & communities",    "Chat, roster, info and settings in the kit.", tab = "Windows" },
	{ "GroupFinderPanel", "Looking for group",      "Listing, browse and who in the kit.", tab = "Windows" },
	{ "CollectionsPanel", "Appearances",            "The wardrobe in the kit.", tab = "Windows" },
	{ "SocialPanel",      "Social window",          "Contacts, raid and quick join in the kit.", tab = "Windows" },
	{ "BackpackPanel",    "Bags",                   "The backpack and bag windows in the kit.", tab = "Windows" },
	{ "GameMenuPanel",    "Game menu",              "The Escape menu on its painted plates.", tab = "Windows" },
	{ "DialogPanel",      "Popup dialogs",          "The game's popup dialogs (confirmations, the world refresh notice, Release spirit ...) on the kit's stone and rail, with red plate buttons.", tab = "Windows" },
	{ "MacroPanel",     "Macros",                "The macro window (general and character macros, the icon picker) in the kit.", tab = "Windows" },
	{ "EditModePanel",  "Edit Mode window",      "Edit Mode's settings window and the layout dialogs in the kit.", tab = "Windows" },
	{ "AddonListPanel",  "AddOn list",            "The AddOn list in the kit.", tab = "Windows" },
	{ "OptionsPanel",   "Game options",          "The game's Options window (every settings page) in the kit.", tab = "Windows" },
	{ "QuestDialogPanel", "Quest dialogs", "The quest giver's dialogs (offer, progress, reward) and the gossip window in the kit.", tab = "Windows" },
	{ "MerchantPanel", "Merchants", "The merchant window (items, buyback, repair) in the kit.", tab = "Windows" },
	{ "AuctionHousePanel", "Auction house", "The auction house (buy, sell, your auctions) in the kit.", tab = "Windows" },
	{ "TrainerPanel", "Trainers", "The class and profession trainers' window in the kit.", tab = "Windows" },
	{ "TabardPanel", "Guild tabard vendor", "The guild tabard designer in the kit.", tab = "Windows" },
	{ "TaxiPanel", "Flight map", "The flight map window in the kit.", tab = "Windows" },
	{ "MailPanel", "Mailbox", "The mailbox (inbox, reading a letter, send mail) in the kit.", tab = "Windows" },
	{ "BankPanel", "Bank", "The bank window (the bank's slots, bag slots, purchase) in the kit, in the bags' looks.", tab = "Windows" },
	{ "GuildBankPanel", "Guild bank", "The guild bank (its tabs, slots, logs and money) in the kit.", tab = "Windows" },
	{ "TradePanel", "Trade", "The trade window in the kit.", tab = "Windows" },
	{ "LootPanel", "Loot windows", "The loot window and the group loot rolls in the kit.", tab = "Windows" },
	{ "ItemTextPanel", "Books and letters", "Books, plaques and letters you read (the item text window) in the kit, on parchment.", tab = "Windows" },
	{ "CharterPanel", "Guild charter", "The guild charter (petition) and the guild registrar in the kit.", tab = "Windows" },
	{ "InspectPanel", "Inspect", "The inspect window (another player's gear) in the kit.", tab = "Windows" },
	{ "DressUpPanel", "Dressing room", "The dressing room in the kit.", tab = "Windows" },
	{ "BarberShopPanel", "Barber shop", "The barber shop in the kit.", tab = "Windows" },
	{ "SocketingPanel", "Gem socketing", "The item socketing window in the kit.", tab = "Windows" },
	{ "StablePanel", "Pet stable", "The hunter's pet stable in the kit.", tab = "Windows" },
	{ "PvPPanel", "PvP windows", "The battleground and arena windows and the scoreboard in the kit.", tab = "Windows" },
	{ "BattlefieldMapPanel", "Battlefield map", "The battlefield minimap's frame in the kit (the map itself untouched).", tab = "Windows" },
	{ "ReadyPanel", "Ready checks", "The ready check and the dungeon / battleground ready popups in the kit.", tab = "Windows" },
	{ "StackSplitPanel", "Split stack", "The split-stack box in the kit.", tab = "Windows" },
	{ "ColorPickerPanel", "Colour picker", "The colour picker in the kit.", tab = "Windows" },
	{ "CalendarPanel", "Calendar", "The calendar and its event windows in the kit.", tab = "Windows" },
	{ "ClockPanel", "Clock and stopwatch", "The clock settings and the stopwatch in the kit.", tab = "Windows" },
	{ "ChannelPanel", "Chat channels", "The chat channels window in the kit.", tab = "Windows" },
	{ "HelpPanel", "Help window", "The help / customer support window in the kit.", tab = "Windows" },
	{ "UnitFramePanel",   "Unit frames",            "Player, target, focus, pet and party frames in the kit.", tab = "HUD" },
	{ "CastBarPanel",     "Cast bars",              "Player, pet, target and focus cast bars in the kit.", tab = "HUD" },
	{ "RaidFramePanel",   "Raid frames",            "Compact raid frames, group borders and totems in the kit.", tab = "HUD" },
	{ "ActionBarPanel",   "Action bars",            "Action bars, stance and pet bars, micro menu, bag bar, experience and reputation bars in the kit.", tab = "HUD" },
	{ "MinimapPanel",     "Minimap",                "The minimap ring (or a square map in a border of your choosing), zone band and buttons in the kit.", tab = "HUD" },
	{ "TrackerPanel",     "Objective tracker",      "The tracker's headers and backdrop in the kit.", tab = "HUD" },
	{ "ChatPanel",        "Chat windows",           "Chat frames, tabs, edit box and buttons in the kit (no fade).", tab = "HUD" },
	{ "DamageMeterPanel", "Damage meter",           "The damage meter and its breakdown window in the kit.", tab = "HUD" },
	{ "TooltipPanel",     "Tooltips",               "Tooltips on the stone box with the single rail.", tab = "HUD" },
	{ "NameplatePanel",   "Nameplates",             "Nameplate health and cast bars in the kit.", tab = "HUD" },
}

-- The folded feature modules: { module name, switch label, description },
-- each switched by `qol_<name>` here (`off`: off until switched on, as the
-- module was before it moved here; `always`: no switch, its rows each switch
-- one thing and are spread over the tabs). Their rows are laid out below.
local TWEAKS = {
	{ "Auras",        "Buffs & Debuffs",       "MelloUI's own rows of buffs and debuffs: yours in place of the game's buff bar, the target's under its frame, your debuffs on enemy nameplates.", off = true },
	{ "ErrorFilter",  "Error Messages",        "Hides the red error messages you choose (not enough energy, not ready yet, out of range...) from the middle of the screen.", off = true },
	{ "CooldownText", "Cooldown Timers",       "Countdown numbers on action bar cooldowns and nameplate auras, coloured by the time left." },
	{ "Nameplates",   "Nameplate Icons",       "A large crowd-control icon above the name and a quest marker on enemies you still need. Works with or without the reskin." },
	{ "UnitFrames",   "Unit Frame Tweaks",     "Name and glow tweaks on the unit frames (they step aside where the reskin covers them)." },
	{ "BarText",      "Bar Values",            "Health and power values always shown on the player, target and focus frames." },
	{ "BarTextures",  "Bar Textures",          "The finish of health and mana bars (flat, smooth, glossy, minimalist) and their colours; the fill under the kit's brackets." },
	{ "ClassIcons",   "Class Icons",           "The painted class medallions in place of the game's class icons and on player portraits." },
	{ "Chat",         "Chat Tweaks",           "Short channel names, class-coloured names and the art-hiding switches (which only apply while the chat reskin is off)." },
	{ "Tooltip",      "Tooltip Tweaks",        "Class and reaction colours, the health bar and placement of tooltips. The dark backdrop only applies while the tooltip reskin is off." },
	{ "Fonts",        "Custom Fonts",          "The fonts and sizes used by the whole interface. Off: the game's own fonts." },
	{ "DarkMode",     "Dark Mode",             "Darkens the painted reskin (its brightness below) and, where the reskin is off, the game's own art of unit frames, bars, nameplates, auras and menus." },
	{ "Vendor",       "Vendor Automation",     "Repair your gear and sell junk automatically at a merchant." },
	{ "Stats",        "FPS / Latency",         "A small coloured FPS and latency readout in the bottom right corner." },
	{ "Tweaks",       "Tweaks",                "", always = true },
}

-- welcomeAsked: the first-login question (take the tour) was asked
-- (Core/Tutorial.lua); layoutApplied: the Edit Mode layout was put in place
-- when the reskin came on (ReskinOn below); flags without option rows
-- defined further down, next to the rest of the switching; declared here so
-- the button on the page can reach them
local Apply, RestoreAreas, NothingWanted, TweakWanted

-- The page (user, 2026-09-24: "the Dynamic UI Modification is going to be
-- the Main Tool people are going to use when configuring the Look of the UI
-- ... the UI Modification Section is going to be mostly sliders checkboxes
-- etc, we need to reconstruct it a bit and simplify the approach"): eight
-- tabs of switches and sliders. The look (borders, Kit Colours, every
-- background and backdrop, parchment, the minimap's shape) is only in
-- Dynamic UI Modification; its keys stay in these settings. A feature's
-- rows sit under its switch, dimmed while it is off; a sub-option under
-- the switch it needs (`parent` in the modules' options).
local defaults, options = { reskin = true, preloadArt = true, fadeWindows = true, reduceMotion = false,
	parchment_tracker = false, parchment_questTracker = false, parchment_chat = false,
	parchment_whisper = false, parchment_meter = false, parchment_character = false, parchment_tooltip = false, parchment_dialog = false,
	unlock = false, autoSnap = true, positions = {}, welcomeAsked = false, layoutApplied = false, nameFormat = "both" }, {}
for _, k in ipairs(MelloUI.Kit and MelloUI.Kit.borderKinds or {}) do
	defaults[k.key] = k.default
end
for _, area in ipairs(PANELS) do
	defaults[area[1]] = true
end
for _, tweak in ipairs(TWEAKS) do
	if not tweak.off then
		defaults["qol_" .. tweak[1]] = true
	end
end

local function Add(opt)
	options[#options + 1] = opt
end
local function Tab(name)
	Add({ type = "header", name = name })
end
local function Sub(name)
	Add({ type = "subheader", name = name })
end
-- a feature: its heading, its switch, then its rows (`keys`: which, in
-- order; nil: all of them) under the switch
local function Feature(name, keys, heading)
	local tweak
	for _, t in ipairs(TWEAKS) do
		if t[1] == name then
			tweak = t
		end
	end
	if heading ~= false then
		Sub(heading or tweak[2])
	end
	local area = nil
	if not tweak.always then
		area = "qol_" .. name
		Add({ type = "toggle", key = area, name = tweak[2], desc = tweak[3] })
	end
	Add({ type = "include", module = name, area = area, keys = keys, flat = true })
end
local function Panels(tab)
	for _, area in ipairs(PANELS) do
		if area.tab == tab then
			Add({ type = "toggle", key = area[1], name = area[2], desc = area[3], requires = "reskin" })
		end
	end
end

-- General
Tab("General")
Add({ type = "toggle", key = "reskin", name = "Painted kit reskin", important = true,
	desc = "The whole interface dressed in the painted kit. Off: every area shows the game's own art; the other tabs' features keep working." })
Add({ type = "button", name = "Dynamic UI Modification", hint = "borders, colours, backgrounds, parchment",
	text = "Open", width = 90, requires = "reskin",
	desc = "Choose the look of the reskin on the interface itself: the borders of every window, the Kit Colours, the backgrounds and backdrops of the bars and windows, the parchment sheets and the minimap's shape, with previews.",
	onClick = function()
		if MelloUI.StartDynamicUI then
			MelloUI:StartDynamicUI()
		end
	end })
Add({ type = "toggle", key = "fadeWindows", name = "Windows Fade In",
	desc = "Every window fades in over a fifth of a second when it opens, instead of appearing at once: the character window, talents and spells, professions, the bags, social, guild, group finder, collections, the map, the game menu and the rest. Works with the reskin on or off." })
Add({ type = "toggle", key = "reduceMotion", name = "Reduce Motion",
	desc = "Every MelloUI animation ends at once: windows open without fading, the whisper popup appears in place, the quest tracker's lines do not flash, the configurator jumps instead of gliding. For anyone who finds moving interface parts distracting." })
Add({ type = "toggle", key = "preloadArt", name = "Preload Artwork", requires = "reskin",
	desc = "Load all of the reskin's artwork during the loading screen, so a window opened for the first time after a reload shows its art at once instead of a moment later. Keeps about 13 MB of artwork in memory for the whole session, including for windows you never open. Off: each piece loads the first time a window needs it." })
-- Names (user, 2026-09-22: "make that option global for all of the 3
-- things at the same time"): one dropdown for the unit frames, the
-- nameplates and the name over your own head. Characters here have a first
-- name and a surname. The unit frames and nameplates are re-set by their
-- modules (their `nameFormat`, driven from here); the name the engine draws
-- over heads has ONE setting, the client's `UnitSurnameOwn` cvar ("show
-- player surname over head", the binary's only surname cvar): your own
-- name follows, other players' overhead names are the engine's and have
-- no setting (nameplates on shows them in the chosen form).
Add({ type = "dropdown", key = "nameFormat", name = "Show Names As", values = {
	{ value = "first", label = "First name" },
	{ value = "last", label = "Last name" },
	{ value = "both", label = "First and last name" },
}, desc = "Which part of a character's name is shown, everywhere at once: the player, target, focus, pet, party and raid frames, the nameplates, and the name over your own head (the game's own setting for it; Last name shows both there). A character with no surname shows the name it has. Names over other players' heads without a nameplate are the engine's and have no setting." })
Add({ type = "button", name = "Switch every area on", hint = "when nothing is reskinned any more",
	text = "Switch on", requires = "reskin",
	desc = "Every window and HUD area of the reskin back on, and every feature on these tabs that is on by default.",
	onClick = function(_, db)
		local count = RestoreAreas(db)
		if count == 0 then
			MelloUI:Print("Every area is on already.")
			return
		end
		Apply(db, true)
		MelloUI:Print("%d area%s switched back on.", count, count == 1 and "" or "s")
		if MelloUI.RefreshConfig then
			MelloUI:RefreshConfig()
		end
	end })

-- Windows: which windows the reskin dresses
Tab("Windows")
Panels("Windows")

-- HUD: which parts of the HUD, and what to hide
Tab("HUD")
Panels("HUD")
Sub("Hide")
Feature("Tweaks", { "hideMicroMenu", "hideBagBar", "bagSlotsOnBags", "hideMinimapCoords" }, false)

-- Combat
Tab("Combat")
Feature("Auras")
Feature("ErrorFilter")
Feature("CooldownText")
Feature("Nameplates")
Sub("Combat Text")
Feature("Tweaks", { "worldTextScale" }, false)

-- Unit frames and bars
Tab("Unit Frames & Bars")
Feature("UnitFrames")
Feature("BarText")
Feature("BarTextures")
Feature("ClassIcons")

-- Chat and tooltips
Tab("Chat & Tooltips")
Feature("Chat")
Feature("Tweaks", { "chatNotices" }, false)
Feature("Tooltip")

-- Text: the style and sizes first, the single faces under Advanced
Tab("Text")
Feature("Fonts", { "style", "scaleText", "scaleChat", "scaleTitle", "scaleDamage", "outline",
	{ type = "subheader", name = "Chat on parchment" }, "fontChatParchment", "scaleChatParchment",
	{ type = "subheader", name = "Advanced: one face per role" },
	"fontText", "fontChat", "fontChatText", "fontTitle", "fontDamage" }, false)

-- Dark Mode and the rest
Tab("Dark Mode / Other")
Feature("DarkMode")
Feature("Vendor")
Feature("Stats")

local M = MelloUI:RegisterModule("UIModifications", {
	title = "UI Modifications",
	desc = "The painted kit reskin, area by area, and the interface's features: buffs and debuffs, error messages, cooldowns, unit frames, chat, tooltips, fonts, dark mode and more. The look itself is chosen in Dynamic UI Modification.",
	enabledByDefault = true,
	important = true,
	-- it drives every reskin panel and folded tweak, so its OFF state has to
	-- be applied at start-up too, not only when the switch is thrown
	applyWhenDisabled = true,
	keep = { "savedSurnameOwn", "layoutApplied", "welcomeAsked", "bordersMigrated", "featuresFolded" },   -- a borrowed game setting and one-time steps: never in a profile
	defaults = defaults,
	options = options,
})

-- Unlock the Windows, Auto Snapping and Reset positions sit in the
-- configurator's top bar (user, 2026-09-23: "should be placed along with as
-- the main options on top of that window"): their texts, for its tooltips
M.placementTexts = {
	unlock = { name = "Unlock the Windows",
		desc = "Every window can be dragged by its title strip (the kit's title plate when the reskin is on), the minimap by its zone band, the trackers by their headers, the damage meter by grabbing it and a chat window by a strip along its top edge (so its links and buttons keep working); the border lights up while it moves, the screen darkens with a grid on it, and the mouse wheel while dragging scales it. Every drag area shows as a gold band while this is on, brighter under the mouse. Positions and scales stay, reloads included, and win over Edit Mode's for those elements. Works with the reskin off as well." },
	autoSnap = { name = "Auto Snapping",
		desc = "While a window is dragged, the grid lines near its bottom-left corner light up, and on release the corner snaps onto them. Off: the window stays exactly where it is dropped." },
	reset = { name = "Reset positions",
		desc = "Forget every saved window position and scale: each window returns to the game's own place and size the next time it opens (open ones are closed now)." },
}

--------------------------------------------------------------------------------
-- The window mover (user, 2026-09-21): while `unlock` is on, a kit window's
-- title plate is a drag handle; the outer rail is lit while it moves; the
-- position is saved and put back on every show and after the game's own
-- panel layout (UpdateUIPanelPositions), so it survives reloads.
--------------------------------------------------------------------------------

local movers = {}   -- [frame] = mover

-- Edit Mode replaces SetPoint / ClearAllPoints / SetScale (and Hide / Show /
-- SetShown) on its system frames -- the damage meter, the minimap cluster, the
-- objective tracker, the chat -- with Lua overrides that keep its own
-- bookkeeping: frame snapping (self.snappedToFrame), OnEditModeSystemAnchorChanged,
-- ManageFramePositions(), the tracker's Update(). Called from MelloUI they run
-- tainted and leave tainted state behind, and Blizzard code reading it later
-- runs tainted too: the damage meter's fight timer then failed on its secret
-- combat duration on every refresh ("attempt to compare local 'durationSeconds'
-- (a secret number value, while execution tainted by 'MelloUI')", user
-- 2026-09-23). The mover's positions are MelloUI's own, not Edit Mode's, so it
-- calls the plain methods Edit Mode kept aside as <Method>Base and leaves Edit
-- Mode's state alone. A frame without the overrides answers with its own.
local function Raw(frame, method)
	return frame[method .. "Base"] or frame[method]
end

local function SavedPosition(frame)
	local name = frame.GetName and frame:GetName()
	local db = M.db
	return name and db and db.positions and db.positions[name] or nil, name
end

-- A protected window in combat cannot be moved or scaled by an addon: the
-- game refuses the call and says "ADDON BLOCKED" (player report, 2026-09-23:
-- the talents window opened in combat laid the panels out again, and the
-- mover put the chat window and the talents window back where they had been
-- saved -- ChatFrame1:ClearAllPointsBase(), PlayerSpellsFrame:ClearAllPoints()
-- and :SetScale(), all blocked). Such a put-back waits for the end of the
-- fight; a drag or a wheel turn is simply refused until then.
local function Locked(frame)
	if not (InCombatLockdown and InCombatLockdown()) then
		return false
	end
	local ok, protected = pcall(frame.IsProtected, frame)
	return ok and protected and true or false
end

local afterCombat = {}          -- [frame] = true: put back once the fight is over
local afterCombatFrame = CreateFrame("Frame")
local PutBack
Perf.SetScript(afterCombatFrame, "OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for frame in pairs(afterCombat) do
		afterCombat[frame] = nil
		if frame:IsShown() then
			PutBack(frame)
		end
	end
end)

local combatNoticeShown = false
local function RefuseInCombat(frame)
	if not Locked(frame) then
		return false
	end
	if not combatNoticeShown then
		combatNoticeShown = true
		MelloUI:Print("This window cannot be moved during combat; it can be again once the fight is over.")
	end
	return true
end

-- A saved place kept on the screen (user, 2026-09-24: "UI Scaling Break the
-- UI"). The offsets are in the window's own units from the screen's centre,
-- so they grow with the UI scale while the screen, in those units, shrinks:
-- a window saved near an edge at a small UI scale landed partly or wholly off
-- the screen at a larger one (or after a change to a smaller resolution).
-- The offsets are pulled in just enough for the window to fit, its top-left
-- corner kept on the screen when it is larger than the screen; the saved
-- entry itself is not changed, so the old place comes back with the old
-- scale. Only the mover's own anchor (BOTTOMLEFT to the screen's CENTER);
-- a frame whose size or scale cannot be read yet is left as saved.
local function OnScreen(frame, x, y)
	local okS, fs = pcall(frame.GetEffectiveScale, frame)
	local okW, w, h = pcall(frame.GetSize, frame)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	local okP, sw, sh = pcall(UIParent.GetSize, UIParent)
	if not (okS and okW and okU and okP) then
		return x, y
	end
	for _, v in ipairs({ fs, w, h, us, sw, sh }) do
		if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) or v <= 0 then
			return x, y
		end
	end
	-- half the screen in the window's own units
	local k = us / fs
	local halfW, halfH = sw / 2 * k, sh / 2 * k
	if x + w > halfW then
		x = halfW - w
	end
	if x < -halfW then
		x = -halfW
	end
	if y < -halfH then
		y = -halfH
	end
	if y + h > halfH then
		y = halfH - h
	end
	return x, y
end

PutBack = function(frame)
	local pos = SavedPosition(frame)
	if not pos or not M.isEnabled then
		return
	end
	if Locked(frame) then
		afterCombat[frame] = true
		afterCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local mover = movers[frame]
	local was = mover and mover.placing
	if mover then
		mover.placing = true
	end
	local ok = pcall(function()
		if pos.scale and pos.scale > 0 and frame.SetScale then
			mover = mover or movers[frame]
			if mover then
				mover.scaling = true
			end
			Raw(frame, "SetScale")(frame, pos.scale)
			if mover then
				mover.scaling = nil
			end
			MelloUI.Kit:RetileBackgrounds()
		end
		-- the mover anchors BOTTOMLEFT to the screen's CENTRE; an entry
		-- carries the anchor only when it differs (measured before the
		-- anchors go: a window sized by them reads 0 wide after)
		local x, y = pos.x or 0, pos.y or 0
		if not pos.point and not pos.relPoint then
			x, y = OnScreen(frame, x, y)
		end
		Raw(frame, "ClearAllPoints")(frame)
		Raw(frame, "SetPoint")(frame, pos.point or "BOTTOMLEFT", UIParent, pos.relPoint or "CENTER", x, y)
	end)
	if mover then
		mover.placing = was
	end
	if not ok then
		MelloUI:Notice("UI Modifications: could not place %s.", tostring(frame:GetName()))
	end
end

-- The lit rail: a tint can only darken painted iron, so the rails are
-- drawn ADDITIVELY while the window moves (the art adds its own light
-- to what is under it: a real glow, gold) — user, 2026-09-21: "500 %"
-- ... and an outer glow around the window while it moves (user,
-- 2026-09-21): four additive gold bands outside the window's edges, each
-- fading out away from it. Made once per window, shown only while dragging.
local GLOW = 28
local SNAP = 16   -- px: the light snap to the nearest grid line on release (each axis on its own)
local SCALE_STEP, SCALE_MIN, SCALE_MAX = 0.05, 0.5, 2   -- the wheel while dragging
-- The grab areas SHOW while the windows are unlocked (user, 2026-09-22):
-- nothing said where a window could be taken hold of, least of all now that
-- a grab is a strip and not the whole window. Each one is a gold wash with a
-- thin edge, brighter under the mouse. (The wash was hidden on 2026-09-21,
-- when a grab covered a whole window and the wash covered it with it.)
local WASH, WASH_LIT = 0.12, 0.25
local EDGE, EDGE_LIT = 0.45, 0.9
local STRIP = 22   -- px: the height of a grab that is only a strip along a window's top edge

local function OuterGlow(frame, mover)
	if mover.glow then
		return mover.glow
	end
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetFrameStrata(frame:GetFrameStrata())
	glow:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
	glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -GLOW, GLOW)
	glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", GLOW, -GLOW)
	glow:EnableMouse(false)
	local inner = CreateColor(1, 0.8, 0.3, 0.7)
	local outer = CreateColor(1, 0.8, 0.3, 0)
	local function Band(point1, point2, orientation, fromInner)
		local tex = glow:CreateTexture(nil, "BACKGROUND")
		tex:SetColorTexture(1, 1, 1, 1)
		tex:SetBlendMode("ADD")
		tex:SetPoint(point1[1], frame, point1[2], point1[3], point1[4])
		tex:SetPoint(point2[1], frame, point2[2], point2[3], point2[4])
		if fromInner then
			tex:SetGradient(orientation, inner, outer)
		else
			tex:SetGradient(orientation, outer, inner)
		end
		return tex
	end
	-- top: from the window's top edge upward (VERTICAL runs bottom -> top)
	Band({ "BOTTOMLEFT", "TOPLEFT", 0, 0 }, { "TOPRIGHT", "TOPRIGHT", 0, GLOW }, "VERTICAL", true)
	-- bottom: downward
	Band({ "TOPLEFT", "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, -GLOW }, "VERTICAL", false)
	-- left: leftward (HORIZONTAL runs left -> right)
	Band({ "TOPRIGHT", "TOPLEFT", 0, 0 }, { "BOTTOMLEFT", "BOTTOMLEFT", -GLOW, 0 }, "HORIZONTAL", false)
	-- right: rightward
	Band({ "TOPLEFT", "TOPRIGHT", 0, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", GLOW, 0 }, "HORIZONTAL", true)
	glow:Hide()
	mover.glow = glow
	return glow
end

-- The rest of the screen darkens while a window moves, so the eye stays on
-- it (user, 2026-09-21): one black veil at the window's strata, at level 0
-- under everything drawn there — it dims the world and every lower strata.
local veil = nil

-- ... with a grid on it: a line every GRID px out from the screen's
-- centre, the two centre lines gold and brighter (user, 2026-09-21: "where
-- the middle of the screen is").
local GRID = 50

-- The lines are pooled on the veil and the grid drawn again whenever the
-- screen's size in UI units is no longer the one it was drawn for (user,
-- 2026-09-24: "UI Scaling Break the UI" -- drawn once, the grid kept the
-- old UI scale's screen: its centre lines off the centre, lines missing or
-- running past the edge, and the lit snap lines too short).
local function DrawGrid(parent)
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if not (w and h) or w <= 0 or h <= 0 then
		return
	end
	parent.gridLines = parent.gridLines or {}
	local pool, used = parent.gridLines, 0
	parent.gridW, parent.gridH = w, h
	local cx, cy = w / 2, h / 2
	local function Line(vertical, offset, centre)
		used = used + 1
		local tex = pool[used]
		if not tex then
			tex = parent:CreateTexture(nil, "BORDER")
			pool[used] = tex
		end
		tex:ClearAllPoints()
		tex:Show()
		if centre then
			tex:SetColorTexture(1, 0.82, 0, 0.55)
		else
			tex:SetColorTexture(1, 1, 1, 0.08)
		end
		if vertical then
			tex:SetSize(centre and 2 or 1, h)
			tex:SetPoint("TOP", parent, "TOPLEFT", cx + offset, 0)
		else
			tex:SetSize(w, centre and 2 or 1)
			tex:SetPoint("LEFT", parent, "BOTTOMLEFT", 0, cy + offset)
		end
	end
	local n = 1
	while n * GRID < cx do
		Line(true, n * GRID, false)
		Line(true, -n * GRID, false)
		n = n + 1
	end
	n = 1
	while n * GRID < cy do
		Line(false, n * GRID, false)
		Line(false, -n * GRID, false)
		n = n + 1
	end
	Line(true, 0, true)
	Line(false, 0, true)
	for i = used + 1, #pool do
		pool[i]:Hide()
	end
end

-- The window's centre relative to the screen's centre, in UIParent units
-- (a panel the manager scaled has its own scale: GetCenter answers in
-- that, the grid is in UIParent's — the first snap landed off-centre, user
-- 2026-09-21), and the factor that turns a UIParent offset into the
-- frame's own anchor units.
-- The window's BOTTOM-LEFT corner (user, 2026-09-21: the corner is what
-- snaps) relative to the screen's centre, in UIParent units ...
local function CornerOffset(frame)
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	local fs, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if not (left and bottom and fs and us and sw and sh) or fs <= 0 or us <= 0 then
		return nil
	end
	local dx = (left * fs - sw / 2 * us) / us
	local dy = (bottom * fs - sh / 2 * us) / us
	return dx, dy, us / fs
end

-- The grid line an offset would snap to (nil: none within SNAP)
local function SnapTarget(offset)
	local nearest = math.floor(offset / GRID + 0.5) * GRID
	if math.abs(offset - nearest) <= SNAP then
		return nearest
	end
	return nil
end

local function Veil(frame, on)
	if on then
		if not veil then
			veil = CreateFrame("Frame", nil, UIParent)
			veil:SetAllPoints(UIParent)
			veil:EnableMouse(false)
			local tex = veil:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints()
			tex:SetColorTexture(0, 0, 0, 0.6)
			pcall(DrawGrid, veil)
			-- the lines the window would snap to, lit while it is near them
			veil.hlX = veil:CreateTexture(nil, "ARTWORK")
			veil.hlX:SetColorTexture(1, 0.9, 0.4, 0.9)
			veil.hlX:SetSize(3, UIParent:GetHeight())
			veil.hlY = veil:CreateTexture(nil, "ARTWORK")
			veil.hlY:SetColorTexture(1, 0.9, 0.4, 0.9)
			veil.hlY:SetSize(UIParent:GetWidth(), 3)
		end
		-- the screen is another size in UI units since the grid was drawn
		-- (the UI scale or the resolution changed): drawn again for it
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		if screenW and screenH and (math.abs(screenW - (veil.gridW or 0)) > 0.5 or math.abs(screenH - (veil.gridH or 0)) > 0.5) then
			pcall(DrawGrid, veil)
			veil.hlX:SetSize(3, screenH)
			veil.hlY:SetSize(screenW, 3)
		end
		veil:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
		veil:SetFrameLevel(0)
		veil.hlX:Hide()
		veil.hlY:Hide()
		-- the wheel is caught on the veil as well: a window scaled down
		-- slides out from under the cursor, which then no longer sits on
		-- the plate (user, 2026-09-21: could not scale back up)
		-- ... and the veil takes the mouse for the drag's duration: a wheel
		-- turn that reaches nothing zooms the camera (user, 2026-09-21); the
		-- button is held anyway, so no click is lost
		veil:EnableMouse(true)
		veil:EnableMouseWheel(true)
		Perf.SetScript(veil, "OnMouseWheel", function(_, delta)
			if veil.onWheel then
				veil.onWheel(delta)
			end
		end)
		Perf.SetScript(veil, "OnUpdate", function(self)
			local dx, dy = CornerOffset(frame)
			if not dx or not (M.db and M.db.autoSnap ~= false) then
				self.hlX:Hide()
				self.hlY:Hide()
				return
			end
			local tx, ty = SnapTarget(dx), SnapTarget(dy)
			local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
			if tx then
				self.hlX:ClearAllPoints()
				self.hlX:SetPoint("TOP", self, "TOPLEFT", sw / 2 + tx, 0)
				self.hlX:Show()
			else
				self.hlX:Hide()
			end
			if ty then
				self.hlY:ClearAllPoints()
				self.hlY:SetPoint("LEFT", self, "BOTTOMLEFT", 0, sh / 2 + ty)
				self.hlY:Show()
			else
				self.hlY:Hide()
			end
		end)
		veil:Show()
	elseif veil then
		Perf.SetScript(veil, "OnUpdate", nil)
		veil:EnableMouseWheel(false)
		veil:EnableMouse(false)
		veil.onWheel = nil
		veil:Hide()
	end
end

local function Light(shell, on, frame, mover)
	if frame then
		pcall(Veil, frame, on)
	end
	local outer = shell.outer
	if outer and outer.skin and outer.skin.art then
		for _, tex in ipairs(outer.skin.art) do
			if on then
				tex:SetBlendMode("ADD")
				tex:SetVertexColor(1, 0.85, 0.35)
			else
				tex:SetBlendMode("BLEND")
				tex:SetVertexColor(1, 1, 1)
			end
		end
	end
	if frame and mover then
		local ok, glow = pcall(OuterGlow, frame, mover)
		if ok and glow then
			glow:SetShown(on and true or false)
		end
	end
end

-- The size readout (user, 2026-09-24: "when i mouse scroll to resize it, it
-- should show me at which % of the standard UI scale that window currently
-- is, so that i know how to bring it back to normal"). While a window is
-- dragged, a small plate above it says how big it is against its STANDARD
-- size and how to get back there; it stays a moment after the release and
-- then fades (just goes, with Reduce Motion). Hovering a grab while the
-- windows are unlocked shows it as well, for a window that is not at 100 %.
-- 100 % is the size the window has without a scale of MelloUI's: its own
-- scale (GetScale, so the game's UI Scale does not count) divided by the scale
-- the game gives it -- 1 for most, Edit Mode's Size for the HUD, the panel
-- manager's fit on a small screen -- which the mover notes when it is made
-- and whenever something other than the mover scales the window (mover.base).
-- A window that keeps its own place (the quest tracker) is at 100 % at scale
-- 1, or at its custom.base. The plate is anchored to the screen, never to
-- the window: a frame anchored to a protected window becomes protected
-- itself and could no longer be hidden in combat.
local SizeTip = {}
do
	local HOLD, FADE = 1.2, 0.4   -- s: shown after the release, then the fade
	local DETENT = 0.3            -- s: the wheel holds at 100 % for this long
	local tip, owner, hold

	local function Plain(v)
		return type(v) == "number" and not (issecretvalue and issecretvalue(v))
	end

	-- the scale that is 100 % for this mover's window
	function SizeTip.Base(mover)
		local custom = mover.custom
		local base = custom and custom.base or mover.base
		return (Plain(base) and base > 0) and base or 1
	end

	-- the window's own scale, nil when it cannot be read
	function SizeTip.Scale(frame)
		local ok, scale = pcall(frame.GetScale, frame)
		return (ok and Plain(scale) and scale > 0) and scale or nil
	end

	-- the next size for a wheel notch, in whole percent of the standard size:
	-- always a multiple of the step (so 100 % is never stepped over), and a
	-- wheel still spinning right after it landed on 100 % is held there a
	-- moment (a detent), so a quick turn back stops on the standard size.
	-- nil: the notch was held.
	function SizeTip.Step(mover, percent, delta, step)
		local now = GetTime and GetTime() or 0
		if mover.detent and now < mover.detent and (delta > 0) == mover.detentUp then
			return nil
		end
		local p = math.floor(percent + 0.5)
		local nextP
		if delta > 0 then
			nextP = math.floor(p / step) * step + step
		else
			nextP = math.ceil(p / step) * step - step
		end
		mover.detent, mover.landed = nil, nil
		if nextP == 100 and p ~= 100 then
			mover.detent, mover.detentUp, mover.landed = now + DETENT, delta > 0, true
		end
		return nextP
	end

	local function Percent(mover)
		local scale = SizeTip.Scale(mover.frame)
		return scale and math.floor(scale / SizeTip.Base(mover) * 100 + 0.5) or nil
	end

	-- above the window, centred; below it where there is no room above, and
	-- over its top when it fills the screen (the plate is clamped to the screen)
	local function Place()
		local f = owner and owner.frame
		if not f then
			return
		end
		local ok, left, bottom, w, h = pcall(f.GetRect, f)
		local okS, fs = pcall(f.GetEffectiveScale, f)
		local us, sh, th = UIParent:GetEffectiveScale(), UIParent:GetHeight(), tip:GetHeight()
		if not (ok and okS) then
			return
		end
		for _, v in ipairs({ left, bottom, w, h, fs, us, sh, th }) do
			if not Plain(v) then
				return
			end
		end
		if us <= 0 then
			return
		end
		local k = fs / us
		local cx, top, low = (left + w / 2) * k, (bottom + h) * k, bottom * k
		tip:ClearAllPoints()
		if top + 8 + th <= sh then
			tip:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, top + 8)
		elseif low - 8 - th >= 0 then
			tip:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, low - 8)
		else
			tip:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, top - 30)
		end
	end

	-- a plate in the palette: the window's ground, a trim edge (the selected
	-- trim at exactly 100 %), the size in the kit's title face and gold, the
	-- hint in body text; at the tooltip strata, over the darkened grid
	local function Build()
		local P = MelloUI.Palette
		tip = CreateFrame("Frame", nil, UIParent)
		tip:SetFrameStrata("TOOLTIP")
		tip:SetClampedToScreen(true)
		tip:EnableMouse(false)
		tip:Hide()
		local fill = tip:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(P.mainWindow[1], P.mainWindow[2], P.mainWindow[3], 0.94)
		tip.edges = {}
		for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
			{ "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
			local t = tip:CreateTexture(nil, "BORDER")
			t:SetPoint(e[1], tip, e[1])
			t:SetPoint(e[2], tip, e[2])
			if e[3] then
				t:SetWidth(e[3])
			end
			if e[4] then
				t:SetHeight(e[4])
			end
			tip.edges[#tip.edges + 1] = t
		end
		tip.value = tip:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		tip.value:SetPoint("TOP", tip, "TOP", 0, -7)
		tip.value:SetTextColor(P.selectedTrim[1], P.selectedTrim[2], P.selectedTrim[3])
		if MelloUI.Kit and MelloUI.Kit.TitleFont then
			pcall(MelloUI.Kit.TitleFont, MelloUI.Kit, tip.value, true)
		end
		tip.hint = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tip.hint:SetPoint("TOP", tip.value, "BOTTOM", 0, -4)
		tip.hint:SetTextColor(P.text[1], P.text[2], P.text[3])
		-- a line of its own, so each is measured on its own for the width
		tip.note = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tip.note:SetPoint("TOP", tip.hint, "BOTTOM", 0, -2)
		tip.note:SetTextColor(P.text[1], P.text[2], P.text[3])
		Perf.SetScript(tip, "OnUpdate", function(self, elapsed)
			Place()
			if hold then
				hold = hold - elapsed
				if hold <= 0 then
					hold = nil
					if MelloUI.Anim then
						MelloUI.Anim:FadeOut(self, FADE)
					else
						self:Hide()
					end
				end
			end
		end)
	end

	local function Fill(mover, percent)
		local P = MelloUI.Palette
		local standard = percent == 100
		tip.value:SetFormattedText("Size %d%%", percent)
		local note = nil
		if standard then
			tip.hint:SetText("The standard size")
		elseif mover.moving then
			tip.hint:SetText("Wheel back to 100% for the standard size")
			note = "Reset positions puts every window back"
		else
			tip.hint:SetText("Drag it and wheel back to 100% for the standard size")
		end
		tip.note:SetText(note or "")
		tip.note:SetShown(note ~= nil)
		local edge = standard and P.selectedTrim or P.trim
		for _, t in ipairs(tip.edges) do
			t:SetColorTexture(edge[1], edge[2], edge[3], 1)
		end
		local w = math.max(tip.value:GetStringWidth() or 0, tip.hint:GetStringWidth() or 0, note and tip.note:GetStringWidth() or 0)
		local h = (tip.value:GetStringHeight() or 16) + (tip.hint:GetStringHeight() or 10) + (note and (tip.note:GetStringHeight() or 10) + 2 or 0)
		tip:SetSize(math.ceil(w) + 24, math.ceil(h) + 18)
	end

	-- shows (or refreshes) the readout for this mover's window; `hover`: only
	-- for a window that is not at its standard size
	function SizeTip.Show(mover, hover)
		local percent = Percent(mover)
		if not percent or (hover and percent == 100) then
			return
		end
		if not tip then
			Build()
		end
		owner, hold = mover, nil
		if MelloUI.Anim then
			MelloUI.Anim:Stop(tip, "alpha")
		end
		tip:SetAlpha(1)
		Fill(mover, percent)
		Place()
		tip:Show()
	end

	-- lets it go after `delay` s (then the fade); a drag in progress keeps it
	function SizeTip.Release(mover, delay)
		if tip and owner == mover and not mover.moving and tip:IsShown() and not hold then
			hold = delay or HOLD
		end
	end
end

local AddHandle   -- below

local function MakeMover(frame, shell)
	local handle = shell.title and (shell.title.object or shell.title)
	local existing = movers[frame]
	if existing then
		-- a second registration for the window: the kit's shell for a
		-- window that already has its plain grab (its lit rail comes
		-- along), or the plain grab for a kit window — one mover, another
		-- handle (user, 2026-09-22: the mover works with the reskin off)
		existing.shell.outer = shell.outer or existing.shell.outer
		existing.custom = existing.custom or shell.custom   -- a window keeping its own place, whichever came first
		AddHandle(existing, handle)
		return
	end
	local usable = handle and handle.EnableMouse and handle.SetScript
	if not usable and not shell.outer then
		return
	end
	-- a shell may bring only its lit rail (`outer`) and leave the handle to
	-- the plain grab that the sweep makes: the mover is still built, and
	-- AddHandle below does nothing until there is one (user, 2026-09-22: the
	-- damage meter is dragged by its header, which only the sweep knows)
	local mover = { shell = shell, handles = {}, washes = {}, frame = frame, custom = shell.custom }
	movers[frame] = mover
	-- the game's own scale for the window, before a saved one is put on it
	-- (PutBack at the end): the size readout's 100 % (user, 2026-09-24)
	mover.base = SizeTip.Scale(frame)
	-- the mouse wheel while dragging: the window's scale, 5 % a notch,
	-- 50 % .. 200 % (user, 2026-09-21), saved with the position
	local function Wheel(delta)
		-- a fight that starts in the middle of a drag: no scaling until it ends
		if not mover.moving or not frame.SetScale or Locked(frame) then
			return
		end
		local current = SizeTip.Scale(frame)
		if not current then
			return
		end
		-- (user, 2026-09-24: the size readout) a notch goes to the next
		-- round percentage of the window's STANDARD size, not the raw scale
		-- plus 5 %, so every step reads round and 100 % is always landed on
		-- (with a short hold there); the range is 50 .. 200 % of the standard
		-- size, or a custom window's own absolute range
		local custom = mover.custom
		local base = SizeTip.Base(mover)
		local percent = SizeTip.Step(mover, current / base * 100, delta, SCALE_STEP * 100)
		if not percent then
			return
		end
		local scale = math.max(custom and custom.min or SCALE_MIN * base, math.min(custom and custom.max or SCALE_MAX * base, base * percent / 100))
		if math.abs(scale - current) < 0.001 then
			mover.landed = nil
			return
		end
		-- the window stays glued to the cursor (user, 2026-09-21): the
		-- point under the cursor is kept under it — the drag is paused,
		-- the frame scaled, re-anchored so that point is back under the
		-- cursor, and the drag resumed (the button is still held)
		local okC, cx, cy = pcall(GetCursorPosition)
		local okR, left, bottom, w, h = pcall(frame.GetRect, frame)
		local fs = frame:GetEffectiveScale()
		mover.scaling = true
		if okC and okR and cx and left and w and h and w > 0 and h > 0 and fs and fs > 0 then
			local fx, fy = (cx / fs - left) / w, (cy / fs - bottom) / h
			frame:StopMovingOrSizing()
			Raw(frame, "SetScale")(frame, scale)
			local fs2 = frame:GetEffectiveScale()
			if fs2 and fs2 > 0 then
				Raw(frame, "ClearAllPoints")(frame)
				Raw(frame, "SetPoint")(frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / fs2 - fx * w, cy / fs2 - fy * h)
			end
			frame:StartMoving()
		else
			Raw(frame, "SetScale")(frame, scale)
		end
		mover.scaling = nil
		mover.scaled = scale
		-- its backgrounds keep the UI's one resolution: more of them shows
		MelloUI.Kit:RetileBackgrounds()
		-- the readout follows the new size; landing on the standard size
		-- gives a soft tick (the chat's scroll click)
		SizeTip.Show(mover)
		if mover.landed and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then
			PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
		end
		mover.landed = nil
	end
	mover.Wheel = Wheel
	mover.DragStart = function()
		if not (M.isEnabled and M.db and M.db.unlock) or RefuseInCombat(frame) then
			return
		end
		frame:SetMovable(true)
		frame:SetClampedToScreen(true)
		frame:StartMoving()
		mover.moving = true
		Light(shell, true, frame, mover)
		if veil then
			veil.onWheel = Wheel
		end
		SizeTip.Show(mover)
	end
	mover.DragStop = function()
		if not mover.moving then
			return
		end
		frame:StopMovingOrSizing()
		Light(shell, false, frame, mover)
		-- still "moving" through the snap and the save: the SetPoint hook
		-- below would otherwise put the window back to its PREVIOUS saved
		-- place the moment the snap anchors it (user, 2026-09-21: "does not
		-- snap on that spot")
		-- light snapping: a window released with its centre within SNAP px
		-- of a screen centre line is put on that line (each axis on its own)
		pcall(function()
			local dx, dy, k = CornerOffset(frame)
			if not dx or not (M.db and M.db.autoSnap ~= false) then
				return
			end
			local tx, ty = SnapTarget(dx), SnapTarget(dy)
			if tx or ty then
				-- the corner onto the lit lines: anchored from the screen's
				-- centre by the snapped offsets, in the window's own units
				Raw(frame, "ClearAllPoints")(frame)
				Raw(frame, "SetPoint")(frame, "BOTTOMLEFT", UIParent, "CENTER", (tx or dx) * k, (ty or dy) * k)
			end
		end)
		-- a window that keeps its own place (MelloUI's quest tracker): it
		-- saves where it was dropped and at what scale, its own way
		if mover.custom then
			if mover.custom.save then
				local ok, err = pcall(mover.custom.save, frame)
				if not ok then
					MelloUI:Notice("UI Modifications: %s", tostring(err))
				end
			end
			mover.moving = nil
			SizeTip.Release(mover)
			return
		end
		local _, name = SavedPosition(frame)
		if name and M.db then
			M.db.positions = M.db.positions or {}
			local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
			if ok and point and x and y then
				local okS, scale = pcall(frame.GetScale, frame)
				-- compact: the backup holds a few thousand characters for
				-- everything and a raw float took a third of a window's entry.
				-- A tenth of a pixel, the scale to a hundredth, the anchor
				-- only when it is not the mover's own BOTTOMLEFT to CENTER.
				-- No scale is kept for a window at its standard size (user,
				-- 2026-09-24: the size readout's 100 %, the game's own scale
				-- for it -- not always 1), so the game's scale stays its own
				M.db.positions[name] = { point = point ~= "BOTTOMLEFT" and point or nil,
					relPoint = relPoint ~= "CENTER" and relPoint or nil,
					x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10,
					scale = (okS and type(scale) == "number" and math.abs(scale - SizeTip.Base(mover)) > 0.001) and (math.floor(scale * 100 + 0.5) / 100) or nil }
				-- the entries saved before this rounding, once
				for _, pos in pairs(M.db.positions) do
					if type(pos) == "table" then
						if type(pos.x) == "number" then pos.x = math.floor(pos.x * 10 + 0.5) / 10 end
						if type(pos.y) == "number" then pos.y = math.floor(pos.y * 10 + 0.5) / 10 end
						if type(pos.scale) == "number" then pos.scale = math.floor(pos.scale * 100 + 0.5) / 100 end
						if pos.point == "BOTTOMLEFT" then pos.point = nil end
						if pos.relPoint == "CENTER" then pos.relPoint = nil end
					end
				end
				-- through the setting path, so the backup this client's saved
				-- variables rely on is written (a plain write was lost on
				-- reload — user, 2026-09-21)
				MelloUI:NotifySettingChanged(M.name, "positions", M.db.positions)
			end
		end
		mover.moving = nil
		SizeTip.Release(mover)
	end
	Perf.HookScript(frame, "OnShow", function()
		PutBack(frame)
	end)
	-- whoever re-anchors the window (the panel manager on show, the bag
	-- layout, a page's own code), it goes back where it was put — right
	-- after that SetPoint, never during a drag or our own placing
	hooksecurefunc(frame, "SetPoint", function()
		if mover.moving or mover.placing then
			return
		end
		if SavedPosition(frame) then
			mover.placing = true
			PutBack(frame)
			mover.placing = nil
		end
	end)
	if frame.SetScale then
		hooksecurefunc(frame, "SetScale", function()
			if mover.moving or mover.placing or mover.scaling then
				return
			end
			-- someone else scaled it (Edit Mode's Size, the panel manager's
			-- fit): that is the game's scale for it, the size readout's 100 %
			if not mover.custom then
				mover.base = SizeTip.Scale(frame) or mover.base
			end
			local pos = SavedPosition(frame)
			if pos and pos.scale then
				mover.placing = true
				PutBack(frame)
				mover.placing = nil
			end
		end)
	end
	mover.SetUnlocked = function(on)
		mover.unlocked = on and true or false
		for h in pairs(mover.handles) do
			h:EnableMouse(mover.unlocked)
			h:EnableMouseWheel(mover.unlocked)
		end
		for _, wash in ipairs(mover.washes) do
			wash:SetShown(mover.unlocked)
		end
		if not mover.unlocked then
			SizeTip.Release(mover, 0)
		end
	end
	AddHandle(mover, handle)
	mover.SetUnlocked(M.isEnabled and M.db and M.db.unlock)
	PutBack(frame)
end

-- What a grab area looks like while the windows are unlocked: a gold wash
-- inside a thin gold edge, both brighter while the mouse is on it. The
-- textures are made once and shown with the unlocked state.
local function HandleWash(mover, handle)
	local fill = handle:CreateTexture(nil, "OVERLAY", nil, 7)
	fill:SetAllPoints(handle)
	fill:SetColorTexture(1, 0.82, 0, WASH)
	local edges = {}
	local function Edge(a, b, w, h)
		local t = handle:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(1, 0.82, 0, EDGE)
		t:SetPoint(a, handle, a)
		t:SetPoint(b, handle, b)
		if w then
			t:SetWidth(w)
		end
		if h then
			t:SetHeight(h)
		end
		edges[#edges + 1] = t
	end
	Edge("TOPLEFT", "TOPRIGHT", nil, 1)
	Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
	local function Lit(on)
		fill:SetColorTexture(1, 0.82, 0, on and WASH_LIT or WASH)
		for _, edge in ipairs(edges) do
			edge:SetColorTexture(1, 0.82, 0, on and EDGE_LIT or EDGE)
		end
	end
	-- hooked, not set: a handle that is a kit plate has its own scripts
	-- ... and the size readout while the mouse is on it, for a window that
	-- is not at its standard size (user, 2026-09-24)
	pcall(handle.HookScript, handle, "OnEnter", function()
		Lit(mover.unlocked)
		if mover.unlocked and not mover.moving then
			SizeTip.Show(mover, true)
		end
	end)
	pcall(handle.HookScript, handle, "OnLeave", function()
		SizeTip.Release(mover, 0)
		Lit(false)
	end)
	fill:Hide()
	mover.washes[#mover.washes + 1] = fill
	for _, edge in ipairs(edges) do
		edge:Hide()
		mover.washes[#mover.washes + 1] = edge
	end
end

-- A drag handle of a mover: the drag and wheel scripts on it, the mouse
-- only while unlocked.
AddHandle = function(mover, handle)
	if not (handle and handle.EnableMouse and handle.SetScript) or mover.handles[handle] then
		return
	end
	mover.handles[handle] = true
	handle:RegisterForDrag("LeftButton")
	Perf.SetScript(handle, "OnMouseWheel", function(_, delta)
		if mover.moving then
			mover.Wheel(delta)
			return
		end
		-- not dragging: the wheel is the window's (a chat frame scrolls on
		-- it — user, 2026-09-22: could not scroll the chat while unlocked)
		local target = mover.frame
		local script = target and target.GetScript and target:GetScript("OnMouseWheel")
		if script then
			pcall(script, target, delta)
		end
	end)
	Perf.SetScript(handle, "OnDragStart", mover.DragStart)
	Perf.SetScript(handle, "OnDragStop", mover.DragStop)
	HandleWash(mover, handle)
	handle:EnableMouse(mover.unlocked and true or false)
	handle:EnableMouseWheel(mover.unlocked and true or false)
	for _, wash in ipairs(mover.washes) do
		wash:SetShown(mover.unlocked and true or false)
	end
end

--------------------------------------------------------------------------------
-- Plain windows (user, 2026-09-22): the mover works with the reskin off.
-- Every window the kit dresses, the interaction windows and the HUD elements
-- get a grab area of their own whether or not a kit panel is on: an
-- invisible frame over the game's title strip (the HUD's band / header /
-- body), mouse-enabled only while unlocked. A kit shell registered for the
-- same window adds its lit rail and its plate as a second handle. Windows
-- loaded on demand are picked up when the game lays its panels out.
--------------------------------------------------------------------------------

local PLAIN_WINDOWS = {
	"CharacterFrame", "PlayerSpellsFrame", "ProfessionsFrame", "ProfessionsBookFrame", "CollectionsJournal",
	"PVEFrame", "CommunitiesFrame", "FriendsFrame", "WorldMapFrame", "LegacySystemFrame", "ContainerFrameCombinedBags",
	"MerchantFrame", "GossipFrame", "QuestFrame", "MailFrame", "BankFrame", "TradeFrame", "MacroFrame", "TaxiFrame",
	-- these got their mover only from the kit's shell, which is now built on
	-- the window's first show (user, 2026-09-24: "dress rarely used windows
	-- on first open"), so their grab is plain from login like the others
	"OpenMailFrame", "DressUpFrame", "ItemTextFrame", "PetitionFrame", "GuildRegistrarFrame", "TabardFrame",
	"PetStableFrame", "StableFrame",
	"MelloUIConfigFrame",
}
-- HUD elements: the frame, the region its grab covers, a control to stop
-- short of, and how the grab sits on the region ("strip" = the top edge only)
local PLAIN_HUD = {
	{ "MinimapCluster", function(f) return f.BorderTop or f end },
	{ "ObjectiveTrackerFrame", function(f) return f.Header or f end, function(f) return f.Header and f.Header.MinimizeButton end },
	-- the damage meter is dragged by its HEADER, not by its list (user,
	-- 2026-09-22: "the damage meter should be dragable by the windows
	-- header, not the Bar"). The header's controls sit at both ends of the
	-- band -- the timer and the type dropdown on the left, the session
	-- dropdown, the cog and the minimize button on the right -- so the grab
	-- is the span BETWEEN them, over the title, and every control keeps its
	-- clicks (2026-09-21).
	{ "DamageMeter", function(f)
		local win = f.GetPrimarySessionWindow and f:GetPrimarySessionWindow()
		return win and win.Header or nil
	end, function(f)
		local win = f.GetPrimarySessionWindow and f:GetPrimarySessionWindow()
		if not win then
			return nil
		end
		return { left = win.DamageMeterTypeDropdown or win.SessionTimer,
			right = win.SessionDropdown or win.SettingsDropdown or win.MinimizeButton }
	end, "between" },
}
local plainGrabs = {}   -- [frame] = grab

local function PlainGrab(frame, region, avoid, avoidSide)
	local grab = CreateFrame("Frame", nil, frame)
	if avoidSide == "between" and type(avoid) == "table" then
		-- the span between two controls, over the region's full height: a
		-- header band whose ends are buttons is grabbed in the middle
		local band = region or frame
		grab:SetPoint("TOP", band, "TOP")
		grab:SetPoint("BOTTOM", band, "BOTTOM")
		grab:SetPoint("LEFT", avoid.left or band, avoid.left and "RIGHT" or "LEFT", avoid.left and 2 or 0, 0)
		grab:SetPoint("RIGHT", avoid.right or band, avoid.right and "LEFT" or "RIGHT", avoid.right and -2 or 0, 0)
	elseif avoidSide == "strip" then
		-- a strip along the top edge and nothing more: a grab over a whole
		-- window body takes every click and wheel turn under it while the
		-- windows are unlocked, and a chat window's links, scroll buttons and
		-- wheel die with it (user, 2026-09-22; the wheel alone was forwarded
		-- once before, the clicks could not be)
		grab:SetPoint("TOPLEFT", region or frame, "TOPLEFT")
		grab:SetPoint("TOPRIGHT", region or frame, "TOPRIGHT")
		grab:SetHeight(STRIP)
	elseif region and region ~= frame or (region == frame and avoid) then
		grab:SetAllPoints(region)
		if avoid then
			-- a button on the region keeps its clicks while unlocked: the
			-- grab stops short of it — at its left edge (the tracker's
			-- minimize, at the header's right end) or above its top (the
			-- chat's scroll arrow, in the bottom-right corner: the bottom
			-- strip is left out) — user, 2026-09-22
			grab:ClearAllPoints()
			if avoidSide == "bottom" then
				grab:SetPoint("TOPLEFT", region, "TOPLEFT")
				grab:SetPoint("BOTTOMRIGHT", avoid, "TOPRIGHT", 0, 2)   -- no edge set twice
			else
				grab:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
				grab:SetPoint("TOPRIGHT", avoid, "TOPLEFT", -2, 0)
			end
		end
	elseif frame.TitleContainer then
		grab:SetAllPoints(frame.TitleContainer)   -- the game's title strip, short of the close button
	elseif region == frame then
		grab:SetAllPoints(frame)
	else
		grab:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, 0)
		grab:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -28, -24)
	end
	grab:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
	grab:EnableMouse(false)
	plainGrabs[frame] = grab
	return grab
end

-- (the sweep runs on every panel shown or hidden: user, 2026-09-24 -- the
-- functions and names it made on each run are made once here)
local function AttachPlain(frame, region, avoid, avoidSide)
	if type(frame) == "table" and type(frame.GetObjectType) == "function" and not plainGrabs[frame]
		and not (frame.IsForbidden and frame:IsForbidden()) then
		local ok, grab = pcall(PlainGrab, frame, region, avoid, avoidSide)
		if ok and grab then
			MakeMover(frame, { title = grab })
		end
	end
end
local function NoAvoid()
	return nil
end
local CHAT_FRAMES = {}
for i = 1, (NUM_CHAT_WINDOWS or 10) do
	CHAT_FRAMES[i] = "ChatFrame" .. i
end

local function SweepPlain()
	if not M.isEnabled then
		return
	end
	for _, name in ipairs(PLAIN_WINDOWS) do
		AttachPlain(_G[name], nil)
	end
	for _, entry in ipairs(PLAIN_HUD) do
		local frame = _G[entry[1]]
		if frame and not plainGrabs[frame] then   -- (its region and controls looked up only until it has its grab)
			local ok, region = pcall(entry[2], frame)
			local okA, avoid = pcall(entry[3] or NoAvoid, frame)
			if ok and region then
				AttachPlain(frame, region, okA and avoid or nil, entry[4])
			end
		end
	end
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		if frame then
			AttachPlain(frame, frame, nil, "strip")   -- a chat window is grabbed by a strip along its top edge; the messages under it keep their links, buttons and wheel
		end
	end
end

local sweepFrame = CreateFrame("Frame")
sweepFrame:RegisterEvent("ADDON_LOADED")
sweepFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
Perf.SetScript(sweepFrame, "OnEvent", function()
	SweepPlain()
end)

--------------------------------------------------------------------------------
-- The unlocked state has to say so (user, 2026-09-22): it is kept across
-- sessions, nothing on screen showed it, and the grab areas take the mouse
-- while it is on -- a UI that quietly stops answering the mouse in places.
-- A plate at the top of the screen names the state and locks again when it
-- is clicked.
--------------------------------------------------------------------------------

local ApplyUnlock   -- below
local banner

local function UnlockBanner(on)
	if not on then
		if banner then
			banner:Hide()
		end
		return
	end
	if not banner then
		banner = CreateFrame("Button", "MelloUIUnlockedNotice", UIParent)
		banner:SetSize(420, 32)
		banner:SetPoint("TOP", UIParent, "TOP", 0, -150)
		banner:SetFrameStrata("DIALOG")
		banner:SetClampedToScreen(true)
		local back = banner:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints(banner)
		back:SetColorTexture(0, 0, 0, 0.75)
		-- drawn from plain textures, never a backdrop: this sits over the HUD
		local function Line(a, b, w, h)
			local t = banner:CreateTexture(nil, "BORDER")
			t:SetColorTexture(1, 0.82, 0, 0.5)
			t:SetPoint(a, banner, a)
			t:SetPoint(b, banner, b)
			if w then
				t:SetWidth(w)
			end
			if h then
				t:SetHeight(h)
			end
		end
		Line("TOPLEFT", "TOPRIGHT", nil, 1)
		Line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
		Line("TOPLEFT", "BOTTOMLEFT", 1, nil)
		Line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
		local text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("CENTER", banner, "CENTER", 0, 0)
		text:SetText("Windows unlocked: drag a gold band, wheel to scale.  |cffffd200Click here to lock them|r")
		Perf.SetScript(banner, "OnClick", function()
			-- the setting itself is changed, so the configurator's toggle and
			-- the grabs follow through OnSettingChanged
			MelloUI:NotifySettingChanged(M.name, "unlock", false)
			if MelloUI.RefreshConfig then
				MelloUI:RefreshConfig()
			end
			MelloUI:Print("Windows locked.")
		end)
	end
	banner:Show()
end

ApplyUnlock = function(on)
	for _, mover in pairs(movers) do
		mover.SetUnlocked(on)
	end
	UnlockBanner(on and M.isEnabled and true or false)
end

-- Reset positions (the header button): the saved places and scales are
-- forgotten, every moved window goes back to its standard scale (the game's
-- own for it, the size readout's 100 % -- 1 for most; user, 2026-09-24) and,
-- if open, is closed so the game lays it out afresh on its next show.
local function ResetPositions()
	if not M.db then
		return
	end
	local positions = M.db.positions or {}
	for frame, mover in pairs(movers) do
		local name = frame.GetName and frame:GetName()
		if name and positions[name] then
			mover.placing = true
			pcall(function()
				if frame.SetScale then
					mover.scaling = true
					Raw(frame, "SetScale")(frame, SizeTip.Base(mover))
					mover.scaling = nil
				end
				if frame:IsShown() then
					Raw(frame, "Hide")(frame)
				end
			end)
			mover.placing = nil
		end
	end
	for _, mover in pairs(movers) do
		if mover.custom and mover.custom.reset then
			pcall(mover.custom.reset)
		end
	end
	M.db.positions = {}
	MelloUI:NotifySettingChanged(M.name, "positions", M.db.positions)
	MelloUI:Print("UI Modifications: window positions and scales reset.")
end
M.ResetPositions = ResetPositions

-- A window MelloUI draws itself, moved by the same mover (the darkened
-- screen, the grid, the lit border, the snap and the wheel), which keeps its
-- own place (user, 2026-09-23: the All Objectives tracker "does not have
-- the same darkening ... also the mousewheel does not increase its scale").
-- custom = { save = function(frame) (on release), reset = function() (Reset
-- positions), min / max = its scale range for the wheel, base = its scale
-- at 100 % in the size readout (1 when not given) }.
function MelloUI:RegisterMover(frame, handle, custom)
	if not (frame and handle) then
		return
	end
	local ok = pcall(MakeMover, frame, { title = handle, custom = custom or {} })
	if ok and movers[frame] then
		movers[frame].SetUnlocked(M.isEnabled and M.db and M.db.unlock)
	end
end

local Kit = MelloUI.Kit
if Kit and Kit.OnShell then
	Kit:OnShell(function(frame, shell)
		MakeMover(frame, shell)
	end)
end

-- The UI Scale or the resolution changed (user, 2026-09-24: "UI Scaling
-- Break the UI"): every open window with a saved place is put back, so it is
-- kept on the new screen (PutBack's OnScreen); a protected one in combat
-- waits for the fight's end as always. A closed window is put back when it
-- next opens. The drag grid redraws itself on the next drag.
if Kit and Kit.OnUIScaleChanged then
	Kit:OnUIScaleChanged(function(reason)
		if reason ~= "uiscale" or not M.isEnabled then
			return
		end
		for frame, mover in pairs(movers) do
			local ok, shown = pcall(frame.IsShown, frame)
			if ok and shown and not mover.moving and not mover.custom and SavedPosition(frame) then
				PutBack(frame)
			end
		end
	end)
end

-- Windows Fade In (user, 2026-09-23: "can we do that effect with all of the
-- UI elements that open, the character tab, backpack, talents, professions
-- tab etc?"): every window the game opens as a panel -- the ones it lists in
-- UIPanelWindows: character, talents and spells, professions, social, guild,
-- group finder, collections, map, game menu ... -- and every bag window fades
-- in when it opens, reskin on or off (Core/Anim.lua). Windows of addons the
-- game loads on demand join that list when they load, so the sweep runs again
-- on every ADDON_LOADED, before such a window's first show. Only the window's
-- alpha is touched, which the game allows on any window, in combat too; the
-- hooks are post-hooks and nothing is written onto the windows.
local fadeHooked = setmetatable({}, { __mode = "k" })
local EXTRA_WINDOWS = { "ContainerFrameCombinedBags", "BankFrame", "SettingsPanel", "AddonList" }
for i = 1, 13 do
	EXTRA_WINDOWS[#EXTRA_WINDOWS + 1] = "ContainerFrame" .. i
end

local function FadeOnShow(self)
	if M.isEnabled and M.db and M.db.fadeWindows and MelloUI.Anim
		and not (self.IsForbidden and self:IsForbidden()) then
		MelloUI.Anim:FadeIn(self, 0.2)
	end
end

local function HookFade(frame)
	if type(frame) ~= "table" or fadeHooked[frame] or not frame.HookScript then
		return
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end
	fadeHooked[frame] = true
	Perf.HookScript(frame, "OnShow", FadeOnShow)
end

local function SweepFade()
	if type(UIPanelWindows) == "table" then
		for name in pairs(UIPanelWindows) do
			if type(name) == "string" then
				HookFade(_G[name])
			end
		end
	end
	for _, name in ipairs(EXTRA_WINDOWS) do
		HookFade(_G[name])
	end
end

local fadeWatcher = CreateFrame("Frame")
fadeWatcher:RegisterEvent("PLAYER_LOGIN")
fadeWatcher:RegisterEvent("ADDON_LOADED")
Perf.SetScript(fadeWatcher, "OnEvent", SweepFade)

-- the plain grabs first, so the kit's plate is the second handle and the
-- plain one stays when the kit goes off
-- the game lays its panels out again on every show / hide of one, and the
-- bags on every open (UpdateContainerFrameAnchors — the backpack went back
-- to its default place after a reload, user 2026-09-21): ours go back where
-- they were put after each of those
local function PutBackShown()
	SweepPlain()   -- a window loaded on demand gets its grab here
	for frame in pairs(movers) do
		if frame:IsShown() then
			PutBack(frame)
		end
	end
end
for _, fn in ipairs({ "UpdateUIPanelPositions", "UpdateContainerFrameAnchors" }) do
	if type(_G[fn]) == "function" then
		hooksecurefunc(fn, PutBackShown)
	end
end

local function PanelWanted(db, name)
	return db.reskin ~= false and db[name] ~= false
end

-- During Core's start-up pass the driven modules must come up in TOC order
-- (Bar Textures before the unit frame panel, and so on): only their flags
-- are set then, and Core enables each in its turn; afterwards (a switch on
-- the page) they are switched at once.
local function Want(name, wanted)
	if MelloUI.initializingModules then
		MelloUI.db.enabled[name] = wanted and true or false
	else
		MelloUI:SetModuleEnabled(name, wanted)
	end
end

-- A folded feature's switch: on unless switched off (`off`: off unless
-- switched on; `always`: no switch)
function TweakWanted(db, tweak)
	if tweak.always then
		return true
	end
	local v = db["qol_" .. tweak[1]]
	if tweak.off then
		return v == true
	end
	return v ~= false
end

-- Is there anything at all for the umbrella to do? Every area and every
-- tweak switched off is a real choice (the window mover and the name format
-- work without the reskin), so it is never undone behind your back -- but it
-- is worth saying, because the switch then looks like it does nothing.
function NothingWanted(db)
	for _, area in ipairs(PANELS) do
		if db[area[1]] ~= false then
			return false
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		if not tweak.always and TweakWanted(db, tweak) then
			return false
		end
	end
	return true
end

-- Put every area and tweak back on, for the button on the page. Returns how
-- many were off.
function RestoreAreas(db)
	local count = 0
	local function put(key)
		if db[key] == false then
			db[key] = true
			count = count + 1
			MelloUI:NotifySettingChanged(M.name, key, true)
		end
	end
	for _, area in ipairs(PANELS) do
		put(area[1])
	end
	for _, tweak in ipairs(TWEAKS) do
		if not (tweak.off or tweak.always) then
			put("qol_" .. tweak[1])
		end
	end
	return count
end

function Apply(db, on)
	local wanted = {}
	for _, area in ipairs(PANELS) do
		local name = area[1]
		if MelloUI:GetModule(name) then
			wanted[name] = on and PanelWanted(db, name) or false
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		local name = tweak[1]
		if MelloUI:GetModule(name) then
			wanted[name] = on and TweakWanted(db, tweak) or false
		end
	end
	-- in TOC order on every path (Bar Textures before the unit frame panel
	-- when the umbrella is switched on from its tile as well, not only in
	-- Core's start-up pass; audit, 2026-09-22)
	for name in MelloUI:IterateModules() do
		if wanted[name] ~= nil then
			Want(name, wanted[name])
		end
	end
end

-- The driven modules are hidden from the configurator; done once every
-- module is registered (this file loads before them, see the TOC).
function M:OnInit()
	for _, area in ipairs(PANELS) do
		local module = MelloUI:GetModule(area[1])
		if module then
			module.hidden = true
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		local module = MelloUI:GetModule(tweak[1])
		if module then
			module.hidden = true
		end
	end
end

-- The name form to the two modules and the engine's own-name cvar.
local SURNAME_CVAR = "UnitSurnameOwn"

local function HasCVar(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then
		return false
	end
	local ok, value = pcall(C_CVar.GetCVarInfo, name)
	return ok and value ~= nil
end

local function ApplyNameFormat(db, on)
	local mode = on and (db.nameFormat or "both") or "both"
	for _, name in ipairs({ "UnitFrames", "Nameplates" }) do
		local module = MelloUI:GetModule(name)
		if module then
			MelloUI:NotifySettingChanged(name, "nameFormat", mode)
		end
	end
	if HasCVar(SURNAME_CVAR) then
		if on then
			if db.savedSurnameOwn == nil then
				local ok, current = pcall(C_CVar.GetCVar, SURNAME_CVAR)
				db.savedSurnameOwn = (ok and current) and tostring(current) or "1"
			end
			pcall(C_CVar.SetCVar, SURNAME_CVAR, mode == "first" and "0" or "1")
		elseif db.savedSurnameOwn ~= nil then
			pcall(C_CVar.SetCVar, SURNAME_CVAR, db.savedSurnameOwn)
			db.savedSurnameOwn = nil
		end
	end
end

-- Preload Artwork (Kit:Preload): the kit's files while the reskin is on, the
-- class medallions with them; all let go when either is off or the module is.
local function ApplyPreload(db, on)
	if not (Kit and Kit.Preload) then
		return
	end
	local files = {}
	if on and db.preloadArt ~= false and db.reskin ~= false then
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

-- The reskin switched on by the user (the umbrella from its tile or the
-- reskin toggle; not Core's start-up pass): Custom Sounds comes on with it,
-- and the Edit Mode layout the reskin is drawn for is put in place once
-- (user, 2026-09-22: "if people enable the reskin, it should only auto
-- enable the full reskin and the custom sounds, but it needs to load my
-- current UI layout").
local function ReskinOn(db)
	if MelloUI.initializingModules or not MelloUI.initialized or not db.reskin then
		return
	end
	if MelloUI:GetModule("CustomSounds") and not MelloUI:IsModuleEnabled("CustomSounds") then
		MelloUI:SetModuleEnabled("CustomSounds", true)
		MelloUI:Print("Custom Sounds switched on with the reskin.")
	end
	if not db.layoutApplied and MelloUI.ApplyEditModeLayout then
		local ok, why = MelloUI:ApplyEditModeLayout()
		if ok then
			db.layoutApplied = true
			MelloUI:NotifySettingChanged(M.name, "layoutApplied", true)
		elseif why and not why:find("no layout is baked", 1, true) then
			MelloUI:Print("Edit Mode layout: %s", why)
		end
	end
	if MelloUI.RefreshConfig then
		MelloUI:RefreshConfig()
	end
end

-- Reduce Motion: the animation engine finishes every tween at once
local function ApplyMotion(db)
	if MelloUI.Anim then
		MelloUI.Anim.reduceMotion = (M.isEnabled and db and db.reduceMotion) and true or false
	end
end

function M:OnEnable(db)
	self.db = db
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
	-- Buffs & Debuffs and Error Messages moved here from pages of their own,
	-- and Tweaks lost its switch (its rows each switch one thing; user,
	-- 2026-09-24): each keeps the state it had, once
	if not db.featuresFolded then
		for _, tweak in ipairs(TWEAKS) do
			local key = "qol_" .. tweak[1]
			if tweak.off and db[key] == nil then
				db[key] = MelloUI.db.enabled[tweak[1]] == true
			end
		end
		if db.qol_Tweaks == false then
			local tw = MelloUI:GetModuleDB("Tweaks")
			if tw then
				tw.hideMicroMenu, tw.hideBagBar, tw.hideMinimapCoords, tw.chatNotices = false, false, false, false
				tw.worldTextScale = 1
			end
		end
		db.qol_Tweaks = nil
		db.featuresFolded = true
	end
	ApplyMotion(db)
	if db.reskin ~= false and NothingWanted(db) then
		MelloUI:Notice("UI Modifications is on, but every area of the reskin is switched off, so the game's own art is what you see. Its page has a \"Switch every area on\" button.")
	end
	Apply(db, true)
	SweepPlain()
	ApplyUnlock(db.unlock)
	for frame in pairs(movers) do
		PutBack(frame)
	end
	ApplyNameFormat(db, true)
	ApplyPreload(db, true)
	ReskinOn(db)
end

function M:OnDisable(db)
	db = db or self.db or {}
	ApplyMotion(nil)
	Apply(db, false)
	ApplyUnlock(false)
	ApplyNameFormat(db, false)
	ApplyPreload(db, false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "unlock" then
		ApplyUnlock(value)
		return
	elseif key == "reduceMotion" then
		ApplyMotion(db)
		return
	elseif key:sub(1, 10) == "parchment_" then
		if MelloUI.Kit and MelloUI.Kit.SetParchment then
			MelloUI.Kit:SetParchment(key:sub(11), value and true or false)
		end
		return
	elseif MelloUI.Kit and MelloUI.Kit.borderKinds then
		for _, k in ipairs(MelloUI.Kit.borderKinds) do
			if key == k.key then
				MelloUI.Kit:ApplyBorder(k.kind)
				return
			end
		end
	end
	if key == "autoSnap" or key == "positions" or key == "layoutApplied" or key == "welcomeAsked" or key == "savedSurnameOwn" or key == "featuresFolded" then
		return
	elseif key == "nameFormat" then
		ApplyNameFormat(db, true)
		return
	elseif key == "preloadArt" then
		ApplyPreload(db, true)
		return
	elseif key == "reskin" then
		Apply(db, true)
		ApplyPreload(db, true)
		if value then
			ReskinOn(db)
		end
	elseif key:sub(1, 4) == "qol_" then
		local name = key:sub(5)
		if MelloUI:GetModule(name) then
			MelloUI:SetModuleEnabled(name, value and true or false)
		end
	elseif MelloUI:GetModule(key) then
		MelloUI:SetModuleEnabled(key, PanelWanted(db, key))
	end
end
