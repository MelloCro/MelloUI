--------------------------------------------------------------------------------
-- MelloUI - Edit Layout's game windows
--
-- (onelook D2, out of Modules/UIModifications.lua) The ONE list of the
-- game's elements Edit Layout moves, registered with Core's one mover
-- registry (MelloUI:RegisterMover, MelloUI:AddMoverSource), which keeps their
-- places in its one store (UI Modifications' `positions` setting: Core.lua's
-- POSITIONS_MODULE; each kept under its frame's name), puts them back after
-- the game lays them out (`follow`) and holds an Edit Layout session's
-- pending changes. The moving itself is Edit Layout's (Core/EditLayout.lua
-- and its files). Each is live (`when`) only while UI Modifications is on
-- (onelook D6, until D9 splits that module):
--   windows   every frame a row of WINDOWS below names: the game's windows,
--             in the core, so they move with every *Panel module off and
--             without the kit (the rows the panels' `window = { frames,
--             plainGrab = true }` gave until onelook D2, and the windows that
--             moved only while the kit dressed them); and every other game
--             window the kit dressed (Kit.shells, looked up when needed:
--             Dressed below, Oldschool's seam; MelloUI's own windows register
--             themselves; an Edit Mode system is the game's, Edit Layout's
--             bridge): key = the frame's name, group "window", its row's
--             label and page (the page, Edit Layout's "All options >", only
--             while that module exists), else a name made from the frame's
--             and UI Modifications' page; no default (a Reset closes an open
--             one and the game lays it out afresh); a bag window keeps the
--             bags the game stacks on it on the screen with it (`with`)
--   chat      every chat window NOT docked with ChatFrame1 (the game's
--             temporary whisper windows too): "Chat: <its tab>", its
--             standard place the game's own saved one
--   the four  MinimapCluster, ChatFrame1 (the dock), ObjectiveTrackerFrame
--             and DamageMeter (Core/LayoutFit.lua's EDIT_MODE_FRAMES): Edit
--             Mode systems, moved only by their plain <Method>Base methods
--             (Core's); MelloUI's place wins while it has one, and a Reset
--             hands the element back to Edit Mode's place (group "hud")
-- When they register (the first-open rule, WINDOW-RULES 2f: no frame is
-- made for any of them): at login only the ones with a stored place (the
-- four and the chat windows at UI Modifications' OnEnable, shown at once; the
-- rest after MelloUI:AfterLogin), a window loaded on demand with a stored
-- place at its addon's ADDON_LOADED (UI Modifications' sweep hands it here),
-- a window the kit dresses on its first show with a stored place as it is
-- dressed (the bus's 'shell'), the whole store replaced (a profile, the
-- installer) on the next frame; every other one when Edit Layout opens (the
-- mover source below). UI Modifications hands its OnEnable, its OnDisable
-- and another addon's ADDON_LOADED to GW.OnEnable, GW.OnDisable and
-- GW.AddonLoaded: the three stay with whichever half of it keeps the core
-- settings when it is split (onelook D9).
-- At load: tables, two bus listeners ('shell', 'setting') and one mover
-- source; no frame, no hook. MelloUI.Kit is read when needed, never at load:
-- Modules/Kit.lua loads after this file (see the TOC).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("EditLayoutWindows")
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Finite = MelloUI.Safe.Finite

-- the store's module (Core.lua's POSITIONS_MODULE) and the switch they live by
local UIMOD = "UIModifications"
local GW = {}

--------------------------------------------------------------------------------
-- The list of the game's windows
--
-- In the TOC's order of the panels that dress them (page = that module: its
-- "All options >"; label = the plate's name). The rows the panels' `window =
-- { frames, plainGrab = true }` gave until onelook D2 (22 rows, 28 frames),
-- and (onelook D2: no function lost without Oldschool) the windows that
-- moved only while the kit dressed them (Kit.shells): the auction house,
-- the trainer, the guild bank, inspect, gem socketing, the PvP scoreboard and
-- results, the battlefield map, the calendar, the clock, the chat channels,
-- the help window, the AddOn list and the game's options. A frame this
-- client does not have is passed by (looked up by its name when needed).
--------------------------------------------------------------------------------

local WINDOWS = {
	{ page = "CharacterPanel", label = "Character window", frames = { "CharacterFrame" } },
	{ page = "MacroPanel", label = "Macros", frames = { "MacroFrame" } },
	{ page = "AddonListPanel", label = "AddOn list", frames = { "AddonList" } },
	{ page = "OptionsPanel", label = "Game options", frames = { "SettingsPanel" } },
	{ page = "QuestDialogPanel", label = "Quest dialogs", frames = { "GossipFrame", "QuestFrame" } },
	{ page = "MerchantPanel", label = "Merchants", frames = { "MerchantFrame" } },
	{ page = "AuctionHousePanel", label = "Auction house", frames = { "AuctionHouseFrame" } },
	{ page = "TrainerPanel", label = "Trainers", frames = { "ClassTrainerFrame" } },
	{ page = "TabardPanel", label = "Guild tabard vendor", frames = { "TabardFrame" } },
	{ page = "TaxiPanel", label = "Flight map", frames = { "TaxiFrame" } },
	{ page = "MailPanel", label = "Mailbox", frames = { "MailFrame", "OpenMailFrame" } },
	{ page = "BankPanel", label = "Bank", frames = { "BankFrame" } },
	{ page = "GuildBankPanel", label = "Guild bank", frames = { "GuildBankFrame" } },
	{ page = "TradePanel", label = "Trade", frames = { "TradeFrame" } },
	{ page = "ItemTextPanel", label = "Books and letters", frames = { "ItemTextFrame" } },
	{ page = "CharterPanel", label = "Guild charter", frames = { "PetitionFrame", "GuildRegistrarFrame" } },
	{ page = "InspectPanel", label = "Inspect", frames = { "InspectFrame" } },
	{ page = "DressUpPanel", label = "Dressing room", frames = { "DressUpFrame" } },
	{ page = "SocketingPanel", label = "Gem socketing", frames = { "ItemSocketingFrame" } },
	{ page = "StablePanel", label = "Pet stable", frames = { "PetStableFrame", "StableFrame" } },
	{ page = "PvPPanel", label = "PvP scoreboard", frames = { "PVPMatchScoreboard" } },
	{ page = "PvPPanel", label = "PvP results", frames = { "PVPMatchResults" } },
	-- (not the battlefield map, BattlefieldMapFrame: the game anchors it to its tab and moves it by the tab's drag
	-- (Blizzard_BattlefieldMap.xml:59, BattlefieldMapOptions.position); a place of ours would leave the tab behind.
	-- A kit-dressed one still joins through the 'shell' listener below, under its old key, as before onelook D2)
	{ page = "CalendarPanel", label = "Calendar", frames = { "CalendarFrame" } },
	{ page = "ClockPanel", label = "Clock", frames = { "TimeManagerFrame" } },
	{ page = "ChannelPanel", label = "Chat channels", frames = { "ChannelFrame" } },
	{ page = "HelpPanel", label = "Help window", frames = { "HelpFrame" } },
	{ page = "ProfessionsPanel", label = "Professions", frames = { "ProfessionsFrame", "ProfessionsBookFrame" } },
	{ page = "SpellBookPanel", label = "Spell book", frames = { "PlayerSpellsFrame" } },
	{ page = "LegacyPanel", label = "Legacy window", frames = { "LegacySystemFrame" } },
	{ page = "QuestLogPanel", label = "Quest log", frames = { "WorldMapFrame" } },
	{ page = "GuildPanel", label = "Guild & communities", frames = { "CommunitiesFrame" } },
	{ page = "GroupFinderPanel", label = "Looking for group", frames = { "PVEFrame" } },
	{ page = "CollectionsPanel", label = "Appearances", frames = { "CollectionsJournal" } },
	{ page = "BackpackPanel", label = "Bags", frames = { "ContainerFrameCombinedBags" } },
	{ page = "SocialPanel", label = "Social window", frames = { "FriendsFrame", "SocialUIFrame" } },
}

-- Made from it once, here: PLAIN_WINDOWS (the frames' names in order),
-- PLAIN[name] = true and WINDOW_OF[name] = { label, page } (its plate's name
-- and its page)
local PLAIN_WINDOWS, PLAIN, WINDOW_OF = {}, {}, {}
for _, row in ipairs(WINDOWS) do
	for _, name in ipairs(row.frames) do
		if not PLAIN[name] then
			PLAIN_WINDOWS[#PLAIN_WINDOWS + 1] = name
			PLAIN[name] = true
			WINDOW_OF[name] = { label = row.label, page = row.page }
		end
	end
end

-- a candidate's `when`: UI Modifications on (one function for all; read when
-- asked: that module registers after this file)
local function Live()
	local m = MelloUI.modules[UIMOD]
	return m ~= nil and m.isEnabled and true or false
end

-- the game windows the kit dressed (Modules/Kit.lua's Kit.shells: read when
-- asked, the kit loads after this file): the one seam for them, which
-- Oldschool fills
local function Dressed()
	local K = MelloUI.Kit
	local s = K and K.shells
	return type(s) == "table" and s or nil
end

-- a row's page, Edit Layout's "All options >": only while that module exists
-- (onelook D2: without it the word opens no page; stage I decides what a
-- *Panel page becomes without Oldschool)
local function PageLink(page)
	return (type(page) == "string" and MelloUI:GetModule(page) ~= nil) and page or nil
end

--------------------------------------------------------------------------------
-- The four Edit Mode systems MelloUI keeps a place for too
--------------------------------------------------------------------------------

-- The four Edit Mode systems MelloUI keeps a place for too (Core/LayoutFit.lua's
-- EDIT_MODE_FRAMES, one list: the installer's fitter reads it the same way),
-- each with its plate's name, its settings' page and its system's name in
-- Enum.EditModeSystem (read when the frame names none of its own)
-- (0.20.3) `box`: the rect the element draws, its plate's (Core's mover `box`): the cluster is laid round the
-- game's own parts too, the map MelloUI draws inside it (MinimapPanel:DrawnRect)
local function MinimapBox()
	local mp = MelloUI:GetModule("MinimapPanel")
	if mp and mp.isEnabled and mp.DrawnRect then
		return mp:DrawnRect()
	end
	return nil
end
-- (1.2.0) the chat dock: the minimal chat's view laid round ChatFrame1, its rail and its row of buttons
-- (MelloUI_Chat's View.DrawnRect; nil while the view is off)
local function ChatBox()
	local view = MelloUI.ChatView
	if type(view) == "table" and view.DrawnRect then
		return view.DrawnRect()
	end
	return nil
end
local SHARED = {
	MinimapCluster = { label = "Minimap", page = "MinimapPanel", system = "Minimap", box = MinimapBox },
	ChatFrame1 = { label = "Chat", page = "Chat", system = "ChatFrame", box = ChatBox },
	-- (its options are the Objective Tracker panel's: the Quest Tracker page's
	-- Objective Tracker tab, not MelloUI's own tracker's first one)
	ObjectiveTrackerFrame = { label = "Objective tracker", page = "TrackerPanel", system = "ObjectiveTracker" },
	DamageMeter = { label = "Damage meter", page = "DamageMeterPanel", system = "DamageMeter" },
}
local function SharedNames()
	local fit = MelloUI.LayoutFit
	local names = type(fit) == "table" and fit.EDIT_MODE_FRAMES
	return type(names) == "table" and names or { "MinimapCluster", "DamageMeter", "ChatFrame1", "ObjectiveTrackerFrame" }
end

local EDIT_TEXT = {
	sharedNote = "Edit Mode can move this too. While it has a place here, that place wins.",
	sharedReset = "Back to Edit Mode's place",
	editModeLater = "%s returns to Edit Mode's place after a reload.",
	gameLater = "%s returns to the game's place after a reload.",
	chat = "Chat: %s",
	chatWindow = "Chat window %d",   -- (a chat window whose tab name does not read plainly)
	bag = "Bag %d",                  -- (a separate bag window, ContainerFrameN)
}

-- the entries registered here (weak: Core keeps them)
local mine = setmetatable({}, { __mode = "k" })

local function SharedNote()
	return EDIT_TEXT.sharedNote
end

-- the frames a window carries, kept on the screen with it (the bag stacks,
-- below; the Quest List is a page inside the world map's own rect since
-- 0.18.0's side window went)
local WITH = {}

-- The game's bag windows: the combined one and each bag's own
local BAG_WINDOWS = { "ContainerFrameCombinedBags" }
for i = 1, 13 do
	BAG_WINDOWS[#BAG_WINDOWS + 1] = "ContainerFrame" .. i
end

-- A bag window carries the bag windows the game stacks on it (0.17.0; a
-- player's bags went off the screen): on every open the game hangs each
-- shown bag on the one before it, up a column and then in columns to its
-- left, so a bag moved up or aside took the rest past the screen's edge.
-- Its `with` is that stack, the shown bags whose anchors lead to it, so its
-- place is kept on the screen together with them (Core's FitOffsets; Edit
-- Layout's drag the same). The bag frames looked up on first need.
local bagSet, bagList
local bagStack = {}   -- (BagStack's answer, reused: read at once)

local function BagStack(entry)
	local root = entry and entry.frame
	if not bagList then
		bagSet, bagList = {}, {}
		for _, name in ipairs(BAG_WINDOWS) do
			local f = _G[name]
			if type(f) == "table" and f.GetPoint then
				bagSet[f] = true
				bagList[#bagList + 1] = f
			end
		end
	end
	wipe(bagStack)
	for _, bag in ipairs(bagList) do
		local okV, shown = pcall(bag.IsShown, bag)
		if bag ~= root and okV and not Secret(shown) and shown then
			-- up its chain of anchors, bag on bag, to this one
			local f = bag
			for _ = 1, #bagList do
				local ok, _, rel = pcall(f.GetPoint, f, 1)
				if not ok or Secret(rel) or not bagSet[rel] then
					break
				end
				if rel == root then
					bagStack[#bagStack + 1] = bag
					break
				end
				f = rel
			end
		end
	end
	return bagStack
end
for _, name in ipairs(BAG_WINDOWS) do
	WITH[name] = BagStack
end

--------------------------------------------------------------------------------
-- The chat windows
--------------------------------------------------------------------------------

-- a chat window's id, and whether it hangs in the dock (the game's own
-- setting for it, or the frame's own mark), read plainly
local function ChatId(frame)
	local ok, id = pcall(frame.GetID, frame)
	id = ok and Num(id)
	return (id and id > 0) and id or nil
end

local function ChatInfo(id)
	local info = _G.GetChatWindowInfo
	if not id or type(info) ~= "function" then
		return nil
	end
	local ok, name, _, _, _, _, _, _, _, docked = pcall(info, id)
	if not ok then
		return nil
	end
	return MelloUI.Safe.Text(name), (not Secret(docked) and docked) and true or false
end

local function Docked(frame)
	local mark = frame.isDocked
	if not Secret(mark) and mark then
		return true
	end
	local _, docked = ChatInfo(ChatId(frame))
	return docked and true or false
end

-- an undocked chat window's `when`: UI Modifications on and the window out of the dock
local function ChatLive(entry)
	return Live() and not Docked(entry.frame) and true or false
end

-- the chat dock's plate shows while ChatFrame1 or the dock's selected tab does
local function DockShown(entry)
	local frame = entry.frame
	local ok, shown = pcall(frame.IsShown, frame)
	if ok and not Secret(shown) and shown then
		return true
	end
	local dock = GENERAL_CHAT_DOCK
	local selected = type(dock) == "table" and dock.selected
	if Secret(selected) or type(selected) ~= "table" or type(selected.IsShown) ~= "function" then
		return false
	end
	local okS, on = pcall(selected.IsShown, selected)
	return (okS and not Secret(on) and on) and true or false
end

-- The four's standard place: Edit Mode's, from the active saved layout
-- (MelloUI:EditModeSystemAnchor, read only), laid with their plain methods
-- (Core's PlaceEntryAt). A preset layout, a secret, or a system at its
-- default place inside a container the game lays out (the tracker) gives
-- none: it stays where it is, and the line says when it goes back.
local function EditModeHome(frame)
	local entry = MelloUI:MoverEntry(frame)
	if not entry then
		return false
	end
	local info = SHARED[entry.key]
	local system, index = frame.system, frame.systemIndex
	system = Num(system)
	if not system and info and Enum and Enum.EditModeSystem then
		system = Num(Enum.EditModeSystem[info.system])
	end
	index = Num(index)
	if system and MelloUI.EditModeSystemAnchor then
		local p, to, rp, x, y, inDefault = MelloUI:EditModeSystemAnchor(system, index)
		local managed = frame.isManagedFrame
		if p and not (inDefault and not Secret(managed) and managed) then
			local rel = _G[to]
			if type(rel) ~= "table" then
				rel = UIParent
			end
			if MelloUI:PlaceEntryAt(entry, p, rel, rp, x, y) then
				return true
			end
		end
	end
	return false, EDIT_TEXT.editModeLater:format(entry.label or entry.key)
end

-- An undocked chat window's standard place: the game's own saved one (its
-- point and the offsets as shares of the screen, read plainly), as the game
-- lays it at login
local function ChatHome(frame)
	local entry = MelloUI:MoverEntry(frame)
	if not entry then
		return false
	end
	local saved, id = _G.GetChatWindowSavedPosition, ChatId(frame)
	if id and type(saved) == "function" then
		local ok, point, x, y = pcall(saved, id)
		if ok and not Secret(point) and type(point) == "string" and Finite(x) and Finite(y) then
			local okS, w, h = pcall(UIParent.GetSize, UIParent)
			w, h = okS and Finite(w), okS and Finite(h)
			if w and h and MelloUI:PlaceEntryAt(entry, point, UIParent, point, x * w, y * h) then
				return true
			end
		end
	end
	return false, EDIT_TEXT.gameLater:format(entry.label or entry.key)
end

-- ChatFrame2 and every one after it: its number, else nil. The game's
-- temporary windows (a whisper in a tab of its own) come after the last
-- standing one (ChatFrame11 ...): chat windows too, live only out of the dock
local function ChatNumber(name)
	local n = tonumber(name:match("^ChatFrame(%d+)$"))
	return (n and n >= 2) and n or nil
end

-- a chat window's plate name: "Chat: <its tab>" (a standing window's name as
-- the game saves it, else the window's own -- a temporary one's is its
-- whisper partner's, set by the game when it made the tab); a name that
-- does not read plainly gives its number
local function ChatLabel(frame, n)
	local tab = n <= (NUM_CHAT_WINDOWS or 10) and ChatInfo(ChatId(frame)) or nil
	if not tab or tab == "" then
		tab = MelloUI.Safe.Text(frame.name)
	end
	return (tab and tab ~= "") and EDIT_TEXT.chat:format(tab) or EDIT_TEXT.chatWindow:format(n)
end

--------------------------------------------------------------------------------
-- The candidates
--------------------------------------------------------------------------------

-- a game window the kit dressed that no row names: its plate's name made
-- from its frame's ("ItemUpgradeFrame": "Item Upgrade", a separate bag's
-- ContainerFrame3: "Bag 3"), never the raw code name
local function Readable(name)
	local bag = name:match("^ContainerFrame(%d+)$")
	if bag then
		return EDIT_TEXT.bag:format(tonumber(bag))
	end
	local s = name:gsub("Frame(%d*)$", "%1")
	s = s:gsub("(%l)(%u)", "%1 %2")
	s = s:gsub("(%u)(%u%l)", "%1 %2")
	s = s:gsub("(%a)(%d)", "%1 %2")
	s = s:gsub("_", " ")
	s = s:match("^%s*(.-)%s*$")
	return s ~= "" and s or name
end

-- one of Edit Mode's systems (the loot window, the talking head ...): the
-- game's to place, Edit Layout's bridge hands it to Edit Mode; only the
-- four above are MelloUI's as well. Read plainly: its system's number, and
-- the plain SetPoint Edit Mode keeps aside on each system it takes in
local function IsEditModeSystem(frame)
	local system = frame.system
	return not Secret(system) and type(system) == "number" and type(frame.SetPointBase) == "function"
end

-- a frame laid over the whole screen (within 2 units of UIParent's size): a
-- holder of windows, never one (CandidateOpts)
local function CoversScreen(frame)
	local okW, w = pcall(frame.GetWidth, frame)
	local okH, h = pcall(frame.GetHeight, frame)
	w, h = okW and Num(w) or nil, okH and Num(h) or nil
	local sw, sh = Num(UIParent:GetWidth()), Num(UIParent:GetHeight())
	return w ~= nil and h ~= nil and sw ~= nil and sh ~= nil and w >= sw - 2 and h >= sh - 2
end

-- the registration of a candidate, or nil for a frame that is none (its
-- module's own window, a forbidden frame, a frame of another addon, an Edit
-- Mode system but the four, a holder laid over the whole screen)
local function CandidateOpts(frame, name)
	if type(frame) ~= "table" or type(name) ~= "string" or type(frame.GetObjectType) ~= "function" then
		return nil
	end
	if frame.IsForbidden then
		local ok, forbidden = pcall(frame.IsForbidden, frame)
		if not ok or Secret(forbidden) or forbidden then
			return nil
		end
	end
	-- (2026-10-04, the user: "the whole 'Container Frame Container' is
	-- selectable, which is the whole background") a frame laid over the whole
	-- screen is a holder, no window: the game's ContainerFrameContainer, every
	-- bag's parent, is the window the kit finds for a bag (Kit's WindowOf: the
	-- top frame under UIParent). Nothing to move, and its plate would cover
	-- the screen
	if CoversScreen(frame) then
		return nil
	end
	local shared = SHARED[name]
	if shared then
		return { key = name, follow = true, when = Live, group = "hud", label = shared.label, page = shared.page,
			default = EditModeHome, resetLabel = EDIT_TEXT.sharedReset, note = SharedNote,
			visible = name == "ChatFrame1" and DockShown or nil, box = shared.box }
	end
	local n = ChatNumber(name)
	if n then
		return { key = name, follow = true, when = ChatLive, group = "window", label = ChatLabel(frame, n),
			page = "Chat", default = ChatHome }
	end
	if IsEditModeSystem(frame) then
		return nil
	end
	local shells = Dressed()
	if not (PLAIN[name] or (shells and shells[frame] and not name:find("^MelloUI"))) then
		return nil
	end
	local window = WINDOW_OF[name]
	local page = UIMOD
	if window then
		page = PageLink(window.page)
	end
	return { key = name, follow = true, when = Live, group = "window", label = window and window.label or Readable(name),
		page = page, with = WITH[name] }
end

--------------------------------------------------------------------------------
-- Registering
--------------------------------------------------------------------------------

-- (0.20.3) an entry with a `box` (the minimap's cluster): what it draws changed size round it (the bus's 'column':
-- the map's size, the merge, a login's first lay; 1.2.0 'drawn': the chat's own view put on or taken off) ->
-- clamped by it again (Core's ClampEntry), and its place laid again kept on the screen by it (a place fitted while
-- the map was not drawn yet held the cluster's whole rect)
local boxed = setmetatable({}, { __mode = "k" })   -- [entry] = true
local function BoxedRelay()
	for entry in pairs(boxed) do
		if MelloUI:ClampEntry(entry) and not entry.moving and MelloUI:EntryLive(entry) then
			MelloUI:RestorePosition(entry.key, entry.frame)
		end
	end
end

-- a candidate by its name (and its frame, when known) registered, once
local function RegisterNamed(name, frame)
	frame = frame or _G[name]
	if type(frame) ~= "table" or MelloUI:MoverEntry(frame) then
		return
	end
	local opts = CandidateOpts(frame, name)
	if opts then
		local entry = MelloUI:RegisterMover(frame, frame, opts)
		if entry then
			mine[entry] = true
			if entry.box and not boxed[entry] then
				if next(boxed) == nil then
					MelloUI:On("column", BoxedRelay, "UI Modifications: boxed entries")
					MelloUI:On("drawn", BoxedRelay, "UI Modifications: boxed entries")
				end
				boxed[entry] = true
			end
		end
	end
end

-- The candidates that have a place in the store (which = "shown": only the
-- ones the game shows at once -- the four and the chat windows, docked ones
-- too: their `when` keeps a docked one where the dock lays it), registered:
-- Core places each as it registers
local function RegisterStored(which)
	if not Live() then
		return
	end
	local db = MelloUI:GetModuleDB(UIMOD)
	local store = type(db) == "table" and db.positions
	if type(store) ~= "table" then
		return
	end
	for key in pairs(store) do
		if type(key) == "string" and (which ~= "shown" or SHARED[key] or ChatNumber(key)) then
			RegisterNamed(key)
		end
	end
end
local function RegisterAllStored()
	RegisterStored()
end

-- the registered candidates put where the store says (a profile's, a new
-- store's); shown: only the ones that show (the rest on their next show)
local function PlaceRegistered(shown)
	for entry in pairs(mine) do
		if entry.key ~= nil and MelloUI:GetPosition(entry.key) and (not shown or MelloUI:EntryShown(entry)) then
			MelloUI:RestorePosition(entry.key, entry.frame)
		end
	end
end

-- the whole store replaced (a profile, the installer): its candidates
-- registered on the next frame, the shown ones placed from it.
-- registeredFrom: the store they were last registered from
local registeredFrom = nil
local function NewStore()
	RegisterStored()
	PlaceRegistered(true)
end

-- The mover source (Core's MelloUI:AddMoverSource): Edit Layout runs it at
-- each open and resume, and every candidate not registered yet registers
-- then -- a player's action, never the login. The four first, then the
-- windows, the undocked chat windows and the kit's dressed windows.
local function Candidates()
	if not Live() then
		return
	end
	for _, name in ipairs(SharedNames()) do
		RegisterNamed(name)
	end
	for _, name in ipairs(PLAIN_WINDOWS) do
		RegisterNamed(name)
	end
	for i = 2, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if type(frame) == "table" and not Docked(frame) then
			RegisterNamed("ChatFrame" .. i, frame)
		end
	end
	local shells = Dressed()
	if shells then
		for frame in pairs(shells) do
			if type(frame) == "table" and frame.GetName then
				local ok, name = pcall(frame.GetName, frame)
				name = ok and MelloUI.Safe.Text(name) or nil
				if name then
					RegisterNamed(name, frame)
				end
			end
		end
	end
end
if MelloUI.AddMoverSource then
	MelloUI:AddMoverSource(Candidates)
end

--------------------------------------------------------------------------------
-- The bus and the hand-offs
--------------------------------------------------------------------------------

-- A game window the kit dresses on its first show (the first-open rule:
-- most panels) and no row names is no candidate before that (Kit.shells), so
-- neither walk above finds it: one with a stored place registers as the kit
-- dresses it (the bus's 'shell', a player's action), and Core places it then
-- and after every layout of the game's -- its old place applies from its
-- first show. No frame is made. During the login the AfterLogin walk takes
-- the ones dressed by then.
MelloUI:On("shell", Perf.Shared("'shell' on the bus: a dressed window's stored place", function(frame)
	if not Live() or MelloUI:LoggingIn() or type(frame) ~= "table" or type(frame.GetName) ~= "function"
		or MelloUI:MoverEntry(frame) then
		return
	end
	local ok, name = pcall(frame.GetName, frame)
	name = ok and MelloUI.Safe.Text(name) or nil
	local db = name and MelloUI:GetModuleDB(UIMOD)
	local store = type(db) == "table" and db.positions
	if type(store) == "table" and store[name] ~= nil then
		RegisterNamed(name, frame)
	end
end), GW)

-- the whole store replaced (a profile, the installer: a new table; a place
-- saved into it is the same table): its candidates on the next frame. The
-- bus's 'setting' reaches here with UI Modifications on or off.
MelloUI:On("setting", Perf.Shared("'setting' on the bus: a replaced store of places", function(name, key, value)
	if name ~= UIMOD or key ~= "positions" then
		return
	end
	if Live() and value ~= registeredFrom then
		registeredFrom = value
		local K = MelloUI.Kit
		if K and K.NextFrame then
			K:NextFrame("UIModifications stored places", NewStore)
		else
			NewStore()
		end
	end
end), GW)

-- UI Modifications' OnEnable: the ones registered before put where the
-- store now says (a profile's), then the ones with a stored place registered
-- (Core places each): the four and the chat windows now, shown at once (no
-- jump when the login is over), the rest once the login is over (at once
-- after it)
function GW.OnEnable(db)
	PlaceRegistered()
	RegisterStored("shown")
	MelloUI:AfterLogin(RegisterAllStored)
	registeredFrom = type(db) == "table" and db.positions or nil   -- (registered from it: its 'setting' at a Batch's end registers nothing again)
end

-- UI Modifications' OnDisable: its game elements are not live any more
-- (their `when`): an Edit Layout session lets go of each it holds, put back
-- from its snapshot
function GW.OnDisable()
	local session = MelloUI.LayoutSession
	if type(session) == "table" and session.Holds and session.Drop then
		for entry in pairs(mine) do
			if session.Holds(entry) then
				session.Drop(entry)
			end
		end
	end
end

-- another addon's ADDON_LOADED (a window loaded on demand; UI
-- Modifications' sweep hands it here): the candidates with a stored place
-- registered (at login the AfterLogin walk does it)
function GW.AddonLoaded()
	if Live() and not MelloUI:LoggingIn() then
		RegisterStored()
	end
end

GW.WINDOWS = WINDOWS
GW.BAG_WINDOWS = BAG_WINDOWS
-- published last: a file that raised on its way here leaves none half made
MelloUI.EditLayoutWindows = GW

-- the media data files load next (MelloUI.toc): their time is counted from
-- here, under one name (/melloperf load; none of them opens a scope of its own)
MelloUI.Perf:Scope("Media data files")
