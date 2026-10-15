--------------------------------------------------------------------------------
-- MelloUI - Tweaks
--
-- Small quality of life switches:
--   * hide the micro menu (character / spellbook / ... buttons)
--   * hide the bag bar (the bag slots then dock under the open bag window,
--     with or without Combine Bags, so bags can still be equipped and removed)
--   * the bag bar's fold: the game's arrow beside the backpack folds the bag
--     slots away and brings them back (the game's own expandBagBar setting)
--   * world text scale (floating combat text / damage numbers)
--   * (0.22.0) the split box: the mouse wheel moves its amount, a ½ button halves the stack
--   * (one look, D3) Quality Gems and Grey Out Junk on every bag, bank and guild
--     bank slot, dressed or not (MelloUI.ItemGems, below)
--
-- Hidden frames are re-parented to an invisible frame instead of calling Hide(),
-- so Blizzard code that calls Show() on them cannot bring them back. While Edit
-- Mode is active they are shown again so their layout can still be changed.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Tweaks")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Num = MelloUI.Safe.Number
local W = MelloUI.Widgets

-- (0.19.9) the bars' and the buffs' layouts (below, after the module): the
-- options' get / missing / set ask it (the registration names nothing else
-- of the file's: its choices are written in it)
local Layout = {}

local M = MelloUI:RegisterModule("Tweaks", {
	title = "Tweaks",
	desc = "Hide the micro menu and bag bar, and scale the floating combat text.",
	icon = "Interface\\Icons\\INV_Misc_Wrench_01",
	flavour = "Small knobs with a big effect. Hide what you never click, scale what you never see.",
	role = "adds",
	tweak = { label = "Tweaks", desc = "", order = 15, always = true },
	keep = { "savedWorldTextScale", "menuTipShown" },   -- the player's own text scale to give back, a one-time tip: never in a profile
	defaults = {
		hideMicroMenu = false,
		hideBagBar = false,
		bagSlotsOnBags = true,
		bagBarFold = true,
		hideMinimapCoords = true,
		worldTextScale = 1,
		chatNotices = true,
		-- the on-screen notice's (Core/Notice.lua reads them, Tweaks on or off)
		noticeOnScreen = true,
		noticeToChat = false,
		noticeOutline = false,
		noticeSounds = true,
		-- (0.16.0: one Text Shade for the zone text, the centre texts and the
		-- Route's arrow and marker; Core/Notice.lua, Core/CentreText.lua and
		-- Modules/Route.lua read it as saved)
		textShade = true,
		menuTipShown = false,
		-- (0.19.9: the bar the Bar Layout rows set; their values and the Buff
		-- Layout rows' are the game's or Buffs & Debuffs', never kept here)
		barLayoutBar = 1,
		-- (0.22.0) the split box's mouse wheel and ½ button
		splitWheel = true,
		splitHalf = true,
		-- (one look, D3: Backpack Kit's until then; Core.lua's MergeSettings
		-- carries a saved off) the item slots' quality gems and junk grey
		qualityGems = true,
		greyJunk = true,
	},
	options = {
		{ type = "header", name = "Hide Frames" },
		{ type = "toggle", key = "hideMicroMenu", name = "Hide Micro Menu",
		  desc = "Hide the row of menu buttons (character, spellbook, talents, ...). Still shown while Edit Mode is open." },
		{ type = "toggle", key = "hideBagBar", name = "Hide Bag Bar",
		  desc = "Hide the backpack and bag slot buttons. Still shown while Edit Mode is open. Bags can still be opened with their keybinds." },
		{ type = "toggle", key = "hideMinimapCoords", name = "Hide Minimap Coordinates",
		  desc = "Hide the player coordinates the client writes under the minimap." },
		{ type = "toggle", key = "bagSlotsOnBags", parent = "hideBagBar", name = "Bag Slots On Bag Window",
		  desc = "While the bag bar is hidden, show the bag slots under the open bag window so bags can still be equipped and removed. Works with and without the Combine Bags option." },
		{ type = "toggle", key = "bagBarFold", name = "Collapse Arrow",
		  desc = "An arrow beside the backpack folds the bag slots away so only the backpack shows; click it again to bring them back. While you hold an item they come out by themselves, so a new bag can be dropped into a slot. The game remembers which way you left it." },
		{ type = "header", name = "Chat" },
		{ type = "toggle", key = "chatNotices", name = "Chat Notices",
		  desc = "Lines MelloUI writes to chat on its own: a learned dungeon entrance, settings restored from the backup, hints. Replies to slash commands, and the notices you send to the chat (Send To Chat Instead), always show." },
		{ type = "header", name = "Notices" },
		{ type = "toggle", key = "noticeOnScreen", name = "On-screen Notices",
		  desc = "One short line in the upper third of the screen when MelloUI has news for you: a route set or finished, a service remembered, a dungeon's quests listed. It fades after a few seconds. Move it in Edit Layout." },
		{ type = "toggle", key = "noticeToChat", parent = "noticeOnScreen", name = "Send To Chat Instead",
		  desc = "Write these lines in the chat instead of showing them on the screen. They show there even while Chat Notices is off." },
		{ type = "toggle", key = "noticeSounds", parent = "noticeOnScreen", name = "Notice Sounds",
		  desc = "A short chime with each notice: the map's tracking sound for a new destination (left out while the World Marker's own sound plays for it), a softer one when you arrive." },
		{ type = "toggle", key = "textShade", name = "Text Shade",
		  desc = "A soft dark shade behind the text MelloUI shows on the world, so it reads on bright ground: the zone name when you enter a new area (with its subzone and PvP lines), the game's messages in the middle of the screen (red errors, yellow quest progress, raid warnings and boss emotes) and the Route's World Marker. No outline on the first two (Outlined Text adds it back); the game's colours stay. Off: the game's own look, and no shade behind the marker." },
		-- (not under On-screen Notices: it sets the zone text's and the
		-- centre texts' outline too, which show with the notices off)
		{ type = "toggle", key = "noticeOutline", name = "Outlined Text",
		  desc = "Draw the text MelloUI shows on the world with an outline: the on-screen notice's lines, Combat Text's lines and the Gains lines, and, while Text Shade is on, the zone text and the game's messages in the middle of the screen. Off: soft text on a dark shade." },
		{ type = "header", name = "Combat Text" },
		{ type = "slider", key = "worldTextScale", name = "Numbers Over Enemies", min = 0.5, max = 3, step = 0.1,
		  format = function(v) return string.format("%.1fx", v) end, search = "world text scale",
		  desc = "The size of the numbers over the enemies and the ones you heal: the game's own, and Your Damage's when MelloUI draws them (one or the other shows). 1.0 is the game's size." },
		-- (0.19.9, L1 of keybind_layout_sketch: Action Bars > Bars > Layout)
		{ type = "header", name = "Bar Layout" },
		{ type = "dropdown", key = "barLayoutBar", name = "Which Bar", values = {
			{ value = 1, label = "Action Bar 1" }, { value = 2, label = "Action Bar 2" },
			{ value = 3, label = "Action Bar 3" }, { value = 4, label = "Action Bar 4" },
			{ value = 5, label = "Action Bar 5" }, { value = 6, label = "Action Bar 6" },
			{ value = 7, label = "Action Bar 7" }, { value = 8, label = "Action Bar 8" },
			{ value = 11, label = "Stance Bar" }, { value = 12, label = "Pet Bar" } },
		  desc = "The bar the rows below set: its rows, icons, icon size and padding, saved into your active Edit Mode layout as Edit Mode saves them, once you let a slider go (out of combat). The game shows them after a reload: type /reload (MelloUI says so once). One of the game's preset layouts is copied first: you are asked once." },
		{ type = "slider", key = "barRows", name = "Rows", min = 1, max = 4, step = 1,
		  get = function(db) return Layout.BarGet(db, "barRows") end, missing = function() return Layout.BarMissing("barRows") end,
		  search = "bar rows columns",
		  desc = "How many rows the bar's buttons stand in (columns, on a bar stood upright in Edit Mode)." },
		{ type = "slider", key = "barIcons", name = "Icons", min = 6, max = 12, step = 1,
		  get = function(db) return Layout.BarGet(db, "barIcons") end, missing = function() return Layout.BarMissing("barIcons") end,
		  search = "bar buttons count",
		  desc = "How many of the bar's buttons show." },
		{ type = "slider", key = "barIconSize", name = "Icon Size", min = 50, max = 200, step = 10,
		  format = function(v) return string.format("%d%%", v) end,
		  get = function(db) return Layout.BarGet(db, "barIconSize") end, missing = function() return Layout.BarMissing("barIconSize") end,
		  search = "bar button size scale",
		  desc = "The size of the bar's buttons. 100% is the game's own size." },
		{ type = "slider", key = "barPadding", name = "Padding", min = 2, max = 10, step = 1,
		  get = function(db) return Layout.BarGet(db, "barPadding") end, missing = function() return Layout.BarMissing("barPadding") end,
		  search = "bar button spacing gap",
		  desc = "The room between the bar's buttons." },
		{ type = "shape", key = "barShape", name = "The Bar's Shape",
		  get = function(db) return Layout.BarShape(db) end, missing = function() return Layout.BarMissing() end,
		  desc = "The bar as the rows above lay it out. Saved into your Edit Mode layout when you let a slider go (in a fight, when it ends); the bar itself changes after a reload." },
		-- (0.19.9: Unit Frames > Buffs & Debuffs > Layout, the player's: MelloUI's
		-- own buff rows while they show, else the game's buff and debuff bars
		-- in the Edit Mode layout -- one set of rows for both)
		{ type = "header", name = "Buff Layout" },
		{ type = "slider", key = "buffSize", name = "Icon Size", min = 15, max = 60, step = 1,
		  get = function(db) return Layout.BuffGet("buffSize") end, missing = function() return Layout.BuffMissing("buffSize") end,
		  search = "buffs debuffs aura size",
		  desc = "The size of your buff and debuff icons, in pixels: MelloUI's own rows while Your Buffs And Debuffs shows them, else the game's buff and debuff bars (saved into your Edit Mode layout in its own steps of 3 pixels, shown after a reload; 30 is the game's size)." },
		{ type = "slider", key = "buffSpacing", name = "Spacing", min = 5, max = 15, step = 1,
		  get = function(db) return Layout.BuffGet("buffSpacing") end, missing = function() return Layout.BuffMissing("buffSpacing") end,
		  search = "buffs debuffs aura padding gap",
		  desc = "The room between your buff and debuff icons." },
		{ type = "slider", key = "buffPerRow", name = "Per Row", min = 2, max = 32, step = 1,
		  get = function(db) return Layout.BuffGet("buffPerRow") end, missing = function() return Layout.BuffMissing("buffPerRow") end,
		  search = "buffs debuffs icons per row limit",
		  desc = "How many buffs stand in a row before the next row starts. Your debuffs start a row of their own (the game's debuff bar takes at most 16 in a row)." },
		{ type = "dropdown", key = "buffGrow", name = "Grow", values = { { value = "left", label = "Left" }, { value = "right", label = "Right" } },
		  get = function(db) return Layout.BuffGet("buffGrow") end, missing = function() return Layout.BuffMissing("buffGrow") end,
		  search = "buffs debuffs direction left right",
		  desc = "Which way a row of buffs grows from the first one." },
		{ type = "dropdown", key = "buffNewRows", name = "New Rows", values = { { value = "down", label = "Down" }, { value = "up", label = "Up" } },
		  get = function(db) return Layout.BuffGet("buffNewRows") end, missing = function() return Layout.BuffMissing("buffNewRows") end,
		  search = "buffs debuffs wrap down up",
		  desc = "Where the next row of buffs goes: under the first, or over it." },
		-- (0.22.0, a player's request "QoL: Split Stack"; Windows > Split stack > Behaviour)
		{ type = "header", name = "Split Stack" },
		{ type = "toggle", key = "splitWheel", name = "Mouse Wheel Amount",
		  search = "split stack amount scroll wheel shift",
		  desc = "In the box that splits a stack (Shift-click a stack), the mouse wheel changes the amount: up adds one, down takes one, ten at a time while you hold Shift." },
		{ type = "toggle", key = "splitHalf", name = "Half Button",
		  search = "split stack half halve",
		  desc = "A ½ button at the left end of the split box's amount: click it and the amount is half the stack (191 makes 95). Buying in bundles at a merchant, it rounds down to whole bundles." },
		-- (one look, D3: moved from Backpack Kit, the same rows on Windows >
		-- Bags / Bank / Guild Bank > Look; MelloUI.ItemGems below)
		{ type = "header", name = "Item Slots" },
		{ type = "toggle", key = "qualityGems", name = "Quality Gems",
		  desc = "A small gem in the top-left corner of every item in your bags, the bank and the guild bank, in the colour of the item's quality: grey for junk, white for common, then green, blue, purple and orange. Junk and better items stand out at a glance. While the game shows its own mark in that corner (the junk coin at a merchant, the upgrade arrow, the exclamation mark on an item that starts a quest, the quality badge on a crafting reagent), the gem moves to the top-right corner. One switch for all three windows." },
		{ type = "toggle", key = "greyJunk", name = "Grey Out Junk",
		  desc = "Junk (grey quality) items show grey in your bags, the bank and the guild bank, so they stand apart from what you keep. One switch for all three windows." },
	},
})

--------------------------------------------------------------------------------
-- Frame hiding
--------------------------------------------------------------------------------

local hiddenParent = CreateFrame("Frame", "MelloUIHiddenFrame", UIParent)
hiddenParent:Hide()

local HIDE_TARGETS = {
	hideMicroMenu = function() return MicroMenuContainer end,
	hideBagBar = function() return BagsBar end,
	hideMinimapCoords = function()
		return (Minimap and Minimap.PlayerCoords)
			or (MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords)
			or (MinimapCluster and MinimapCluster.PlayerCoords)
	end,
}

local originalParents = setmetatable({}, { __mode = "k" })
local editModeActive = false
local UpdateBagSlots = nil   -- defined in the bag slots section
local Fold = {}             -- the bag bar's fold (its section below)

local function SetFrameHidden(frame, hidden)
	if not frame or not frame.SetParent then
		return
	end
	if hidden then
		if frame:GetParent() ~= hiddenParent then
			originalParents[frame] = frame:GetParent() or UIParent
			frame:SetParent(hiddenParent)
		end
	else
		if frame:GetParent() == hiddenParent then
			frame:SetParent(originalParents[frame] or UIParent)
		end
	end
end

local function UpdateHiddenFrames()
	local db = M.db
	for key, getter in pairs(HIDE_TARGETS) do
		local frame = getter()
		local shouldHide = M.isEnabled and db and db[key] and not editModeActive
		SetFrameHidden(frame, shouldHide)
	end
	if UpdateBagSlots then
		UpdateBagSlots()
	end
	if Fold.Apply then
		Fold.Apply()
	end
end

local callbacksRegistered = false

-- (through the kit's one Edit Mode registration, the bus's 'editmode';
-- audit, 2026-09-24)
local function RegisterEditModeCallbacks()
	if callbacksRegistered then
		return
	end
	callbacksRegistered = true
	MelloUI:On("editmode", function(entering)
		editModeActive = entering
		UpdateHiddenFrames()
	end, M)
end

--------------------------------------------------------------------------------
-- Bag slots on the bag window
--
-- With the bag bar hidden the four bag slot buttons (and the reagent bag and
-- key ring when this client has them) are re-parented to a small holder that
-- sits under the first open bag window: the combined bags frame, or the
-- backpack when bags are separate. Both stack upwards from the bottom right of
-- the screen, so the strip below them, where the bag bar was, is always free.
-- Blizzard's BagsBar:Layout() re-anchors the buttons whenever the cursor picks
-- something up; a hook puts them back.
--------------------------------------------------------------------------------

local BAG_SLOT_NAMES = { "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot" }
local SLOT_GAP = 2
local SLOT_SCALE = 0.8

local holder = nil
local slotsAttached = false
local slotParents = setmetatable({}, { __mode = "k" })
local bagHooksDone = false

local function SlotButtons()
	local list = {}
	for _, name in ipairs(BAG_SLOT_NAMES) do
		if _G[name] then
			list[#list + 1] = _G[name]
		end
	end
	local reagentSlots = Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumReagentBagSlots
	if CharacterReagentBag0Slot and reagentSlots and reagentSlots > 0 then
		list[#list + 1] = CharacterReagentBag0Slot
	end
	if KeyRingButton and KeyRingButton:IsShown() then
		list[#list + 1] = KeyRingButton
	end
	return list
end

-- Another module may take the bag slots over while a window of its own shows
-- them (the Backpack panel's painted bag bar): ns.BagSlotOverride returns
-- true when it has placed them itself.
local function LayoutBagSlots()
	if not (slotsAttached and holder) then
		return
	end
	if ns.BagSlotOverride and ns.BagSlotOverride(SlotButtons(), holder) then
		return
	end
	local previous, width = nil, 0
	for _, button in ipairs(SlotButtons()) do
		button:ClearAllPoints()
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", -SLOT_GAP, 0)
			width = width + SLOT_GAP
		else
			button:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
		end
		width = width + button:GetWidth()
		previous = button
	end
	holder:SetWidth(math.max(width, 1))
end

-- The bag window the slots hang from: the first one shown, which is the one
-- in the bottom right corner. The bag window by kind (Modules/BagWindow.lua)
-- first, while it shows: the game's own bag window is then never seen.
local function FirstBagFrame()
	local own = ns.BagWindowShown and ns.BagWindowShown()
	if own then
		return own
	end
	if ContainerFrameSettingsManager and ContainerFrameSettingsManager.GetBagsShown then
		local ok, shown = pcall(ContainerFrameSettingsManager.GetBagsShown, ContainerFrameSettingsManager)
		if ok and type(shown) == "table" and shown[1] and shown[1]:IsShown() then
			return shown[1]
		end
	end
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		return ContainerFrameCombinedBags
	end
	if ContainerFrame1 and ContainerFrame1:IsShown() then
		return ContainerFrame1
	end
	return nil
end

local function PositionBagSlots()
	if not holder then
		return
	end
	if slotsAttached and ns.BagSlotOverride and ns.BagSlotOverride(SlotButtons(), holder) then
		holder:Show()
		return
	end
	local anchor = slotsAttached and FirstBagFrame()
	if not anchor then
		holder:Hide()
		return
	end
	holder:ClearAllPoints()
	holder:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", -4 / SLOT_SCALE, -4 / SLOT_SCALE)
	holder:Show()
end

local function ScheduleBagSlotUpdate()
	if slotsAttached then
		C_Timer.After(0, PositionBagSlots)
	end
end

local function HookBagFrames()
	if bagHooksDone then
		return
	end
	bagHooksDone = true
	if type(UpdateContainerFrameAnchors) == "function" then
		hooksecurefunc("UpdateContainerFrameAnchors", ScheduleBagSlotUpdate)
	end
	-- the bag window by kind shown, laid out or hidden
	MelloUI:On("bagwindow", ScheduleBagSlotUpdate, "Tweaks bag slots")
	local frames = { ContainerFrameCombinedBags }
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		frames[#frames + 1] = _G["ContainerFrame" .. i]
	end
	for _, frame in ipairs(frames) do
		if frame and frame.HookScript then
			Perf.HookScript(frame, "OnShow", ScheduleBagSlotUpdate)
			Perf.HookScript(frame, "OnHide", ScheduleBagSlotUpdate)
		end
	end
	if BagsBar and BagsBar.Layout then
		hooksecurefunc(BagsBar, "Layout", function()
			if slotsAttached then
				LayoutBagSlots()
			end
		end)
	end
	-- Picking something up expands the bag bar, which runs BagsBar:Layout()
	-- through a callback registered with the original function at load time,
	-- so the hook above never sees it. Re-anchor a frame later instead.
	local function Relayout()
		if slotsAttached then
			C_Timer.After(0, LayoutBagSlots)
		end
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("MainMenuBarManager.OnExpandChanged", Relayout, M)
	end
	local cursorFrame = CreateFrame("Frame")
	cursorFrame:RegisterEvent("CURSOR_CHANGED")
	cursorFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	Perf.SetScript(cursorFrame, "OnEvent", Relayout)
end

local function AttachBagSlots()
	if slotsAttached then
		return
	end
	if not holder then
		holder = CreateFrame("Frame", "MelloUIBagSlots", UIParent)
		holder:SetSize(1, 45)
		holder:SetScale(SLOT_SCALE)
		holder:SetFrameStrata("MEDIUM")
		holder:SetFrameLevel(20)
		holder:Hide()
	end
	for _, button in ipairs(SlotButtons()) do
		slotParents[button] = button:GetParent()
		button:SetParent(holder)
	end
	slotsAttached = true
	HookBagFrames()
	LayoutBagSlots()
	PositionBagSlots()
end

local function DetachBagSlots()
	if not slotsAttached then
		return
	end
	slotsAttached = false
	for button, parent in pairs(slotParents) do
		if button:GetParent() == holder then
			button:SetParent(parent)
		end
	end
	if holder then
		holder:Hide()
	end
	-- the game's own anchors again, laid by hand (its Layout is never run)
	Fold.Chain()
end

function UpdateBagSlots()
	local db = M.db
	local want = M.isEnabled and db and db.hideBagBar and db.bagSlotsOnBags and not editModeActive and BagsBar ~= nil
	if want then
		-- (the fold's hidden slots out first: the dock takes the ones shown)
		if Fold.Release then
			Fold.Release()
		end
		AttachBagSlots()
	else
		DetachBagSlots()
	end
end

--------------------------------------------------------------------------------
-- The bag bar's fold (0.19.1; the user, 2026-10-04: "make the bag button to be
-- able to collapse itself into a 1 bag but also expendable"; picked: the arrow
-- between the backpack and the bags, and the bags out by themselves while an
-- item is on the cursor). The game has the whole of it -- BagBarExpandToggle,
-- the expandBagBar CVar its click sets and the game keeps, and
-- MainMenuBarBagManager's state (that CVar, or an item on the cursor) -- and
-- this client turns it off (BagsBar.hideExpandToggle). Here the arrow is shown
-- and laid, its click left the game's own; the bag slots and the key ring are
-- hidden while the bar is folded. Never a key on the game's frames and never
-- its layout run: after each of its passes the slots are chained from the
-- arrow with the game's own anchors (BagsBarMixin:Layout's). The bar keeps
-- its size (the game centres the bottom row on it, so a fold moves nothing
-- else); should the arrow not fit in the bar's own room, the backpack steps
-- out on its side by the rest. The game's frame art round the bar follows
-- what shows. The arrow's look: the game's art, or the kit's flat arrow
-- (ActionBarPanel). Told on the bus: 'bagbar' (the backdrops).
--------------------------------------------------------------------------------

Fold.CVAR = "expandBagBar"
Fold.SLOTS = { "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
	"CharacterReagentBag0Slot", "KeyRingButton" }
Fold.POOLS = { "HorizontalDividersPool", "VerticalDividersPool" }
Fold.ART = { -6, 6, 5, -5 }   -- the frame art round the bar (BagsBar.BorderArt's own offsets)
Fold.hid = setmetatable({}, { __mode = "k" })   -- [slot] = true: hidden by the fold (shown again by it alone)
Fold.list = {}
Fold.on = false

-- a frame's length along the bar (its width on a row, its height in a column)
function Fold.Len(frame, horizontal)
	local ok, w, h = pcall(frame.GetSize, frame)
	if not ok then
		return 0
	end
	return Num(horizontal and w or h) or 0
end

-- the bag buttons in the game's order (the backpack first)
function Fold.Buttons()
	local list = Fold.list
	wipe(list)
	local mgr = MainMenuBarBagManager
	if mgr and mgr.EnumerateBagButtons then
		for _, button in mgr:EnumerateBagButtons() do
			list[#list + 1] = button
		end
	end
	return list
end

function Fold.Active()
	local db = M.db
	if not (M.isEnabled and db and db.bagBarFold and not db.hideBagBar and not slotsAttached) then
		return false
	end
	if not (BagsBar and BagBarExpandToggle and MainMenuBarBackpackButton and MainMenuBarBagManager) then
		return false
	end
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local ok, value = pcall(get, Fold.CVAR)
	return ok and value ~= nil
end

-- the game's state: the player's (the CVar) or an item on the cursor
function Fold.Open()
	local mgr = MainMenuBarBagManager
	local ok, open = pcall(mgr.ShouldBarExpand, mgr)
	if not ok then
		return true
	end
	return open and true or false
end

function Fold.Turn(texture, angle)
	if texture and texture.SetRotation then
		texture:SetRotation(angle)
	end
end

function Fold.HideDividers(bar)
	for _, key in ipairs(Fold.POOLS) do
		local pool = rawget(bar, key)
		if pool and pool.EnumerateActive then
			for divider in pool:EnumerateActive() do
				divider:Hide()
			end
		end
	end
end

-- The frame art round what shows: from the backpack's corners, out along the
-- bar by `beyond` on the bags' side
function Fold.FitArt(bar, pack, point, beyond)
	local art = rawget(bar, "BorderArt")
	if not (art and art.SetPoint) then
		return
	end
	if not Fold.artPoints then
		local saved = {}
		for i = 1, art:GetNumPoints() do
			saved[i] = { art:GetPoint(i) }
		end
		Fold.artPoints = saved
	end
	local A = Fold.ART
	local l, t, r, b = A[1], A[2], A[3], A[4]
	if point == "RIGHT" then
		l = l - beyond
	elseif point == "LEFT" then
		r = r + beyond
	elseif point == "BOTTOM" then
		t = t + beyond
	else
		b = b - beyond
	end
	art:ClearAllPoints()
	art:SetPoint("TOPLEFT", pack, "TOPLEFT", l, t)
	art:SetPoint("BOTTOMRIGHT", pack, "BOTTOMRIGHT", r, b)
end

function Fold.Lay(open)
	local bar, toggle, pack = BagsBar, BagBarExpandToggle, MainMenuBarBackpackButton
	for _, name in ipairs(Fold.SLOTS) do
		local slot = _G[name]
		if slot then
			if open then
				if Fold.hid[slot] then
					Fold.hid[slot] = nil
					slot:Show()
				end
			elseif slot:IsShown() then
				Fold.hid[slot] = true
				slot:Hide()
			end
		end
	end
	local ok, point, relativePoint, x, y = pcall(bar.GetBagButtonAnchorPoints, bar)
	local okH, horizontal = pcall(bar.IsHorizontal, bar)
	if not (ok and okH and point) then
		return
	end
	-- the arrow at the game's size (its long side across the bar), beside the
	-- backpack toward the bags, as BagsBarMixin:Layout lays it
	toggle:SetSize(horizontal and Fold.w or Fold.h, horizontal and Fold.h or Fold.w)
	toggle:ClearAllPoints()
	toggle:SetPoint(point, pack, relativePoint)
	toggle:Show()
	-- which way it points (BagBarExpandToggleMixin:GetRotation's: its art
	-- points left unturned; open, toward the backpack)
	local angle
	if horizontal then
		angle = (open == (bar:IsDirectionLeft() and true or false)) and math.pi or 0
	else
		angle = (open == (bar:IsDirectionUp() and true or false)) and (math.pi / 2) or (3 * math.pi / 2)
	end
	Fold.Turn(toggle:GetNormalTexture(), angle)
	Fold.Turn(toggle:GetPushedTexture(), angle)
	Fold.Turn(toggle:GetHighlightTexture(), angle)
	-- the slots that show, chained from the arrow
	local beyond, anchor, gap = Fold.Len(toggle, horizontal), toggle, math.abs((horizontal and x or y) or 0)
	for _, button in ipairs(Fold.Buttons()) do
		if button ~= pack and button:IsShown() then
			button:ClearAllPoints()
			button:SetPoint(point, anchor, relativePoint, x, y)
			anchor = button
			beyond = beyond + gap + Fold.Len(button, horizontal)
		end
	end
	-- the backpack in its place, stepped out by what the bar has no room for
	local over = Fold.Len(pack, horizontal) + beyond - Fold.Len(bar, horizontal)
	over = over > 0.5 and over or 0
	local dx, dy = 0, 0
	if point == "RIGHT" then
		dx = over
	elseif point == "LEFT" then
		dx = -over
	elseif point == "BOTTOM" then
		dy = -over
	else
		dy = over
	end
	pack:ClearAllPoints()
	pack:SetPoint(point, bar, point, dx, dy)
	-- folded: no divider between buttons that are not there
	if not open then
		Fold.HideDividers(bar)
	end
	Fold.FitArt(bar, pack, point, beyond)
end

-- The game's own chain (BagsBarMixin:Layout's anchors) laid by hand, its
-- pass never run: the backpack at the bar's end, the arrow beside it while
-- it shows, the slots that show chained on from there. For the fold gone and
-- for the slots back from the bag window (Hide Bag Bar or Bag Slots on Bag
-- Window off, Edit Mode opened).
function Fold.Chain()
	local bar, toggle, pack = BagsBar, BagBarExpandToggle, MainMenuBarBackpackButton
	if not (bar and pack and bar.GetBagButtonAnchorPoints) then
		return
	end
	local ok, point, relativePoint, x, y = pcall(bar.GetBagButtonAnchorPoints, bar)
	if not (ok and point) then
		return
	end
	pack:ClearAllPoints()
	pack:SetPoint(point, bar, point)
	local anchor = pack
	if toggle and toggle:IsShown() then
		toggle:ClearAllPoints()
		toggle:SetPoint(point, pack, relativePoint)
		anchor = toggle
	end
	for _, button in ipairs(Fold.Buttons()) do
		if button ~= pack and button:IsShown() then
			button:ClearAllPoints()
			button:SetPoint(point, anchor, relativePoint, x, y)
			anchor = button
		end
	end
end

-- the fold gone (the option off, the bar hidden, its slots docked): the
-- slots back, the arrow hidden, the game's own chain from the backpack laid
-- again (its pass not run), the frame art on its own anchors
function Fold.Release()
	if not Fold.on then
		return
	end
	Fold.on = false
	for slot in pairs(Fold.hid) do
		slot:Show()
	end
	wipe(Fold.hid)
	local bar = BagsBar
	BagBarExpandToggle:Hide()
	Fold.Chain()
	local art = rawget(bar, "BorderArt")
	if art and Fold.artPoints then
		art:ClearAllPoints()
		for _, p in ipairs(Fold.artPoints) do
			art:SetPoint(unpack(p))
		end
	end
	Fold.told = nil
	MelloUI:Fire("bagbar")
end

function Fold.Apply()
	if not Fold.Active() then
		Fold.Release()
		return
	end
	if not Fold.w then
		-- the arrow's own size (10 x 16 on a row)
		local ok, w, h = pcall(BagBarExpandToggle.GetSize, BagBarExpandToggle)
		w, h = ok and Num(w), ok and Num(h)
		Fold.w, Fold.h = (w and w > 0) and w or 10, (h and h > 0) and h or 16
	end
	Fold.Hook()
	Fold.on = true
	local open = Fold.Open()
	Fold.Lay(open)
	-- (told only when it changed: the backdrops re-lay on the bar's own
	-- passes as well)
	if Fold.told ~= open then
		Fold.told = open
		MelloUI:Fire("bagbar")
	end
end

-- After the game's pass (its Layout run directly, or through the expand
-- callback it took at load, which a hook never sees): laid again now and
-- once more a frame later, whichever came first
local function FoldNext()
	Fold.pending = false
	Fold.Apply()
end

Fold.Changed = Perf.Shared("the bag bar's layout and expand state (the fold)", function()
	if not Fold.on then
		return
	end
	Fold.Apply()
	if not Fold.pending then
		Fold.pending = true
		C_Timer.After(0, FoldNext)
	end
end, "hook")

-- The arrow clicked: the slots shown or hidden BEFORE the game's own click
-- handler sets the CVar and its pass runs, so its dividers come out right
Fold.PreClick = Perf.Shared("PreClick on the bag bar's arrow", function()
	if not Fold.on then
		return
	end
	local mgr = MainMenuBarBagManager
	local okU, user = pcall(mgr.IsBarUserExpanded, mgr)
	Fold.Lay((okU and not user) or rawget(mgr, "expandBarAuto") == true)
end, "script")

function Fold.Hook()
	if Fold.hooked then
		return
	end
	Fold.hooked = true
	if BagsBar.Layout then
		hooksecurefunc(BagsBar, "Layout", Fold.Changed)
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("MainMenuBarManager.OnExpandChanged", Fold.Changed, Fold)
	end
	Perf.HookScript(BagBarExpandToggle, "PreClick", Fold.PreClick)
end

--------------------------------------------------------------------------------
-- The split box (0.22.0; a player's request, 2026-10-14, "QoL: Split Stack": "change quantity of the split stack size
-- with the mouse wheel (default step size 1; shift scroll - step size 10)" and "a button to halve the stack (e.g. stack
-- size is 191 -> set split stack size to 95)"; the user's pick A of MelloUI-BuildData/output/split_half_sketch: the ½
-- inside the field, at its empty left end). The game's StackSplitFrame keeps its amount, its typing and its OK: the
-- wheel and the ½ move the amount only by the game's own arrows (StackSplitLeftButton_OnClick /
-- StackSplitRightButton_OnClick: one step of the box's minSplit each, within its bounds); nothing is written on the
-- box. Made on the box's first show: a frame of our own over it that takes the wheel and no click, and the ½ (the
-- shared W.Button) -- the kit's dress of the box (StackSplitPanel) on or off.
--------------------------------------------------------------------------------

local Split = {
	SHIFT = 10,        -- steps a wheel turn makes while Shift is held
	HALF_W = 18, HALF_H = 16, HALF_X = 4,   -- the ½: its size, its gap from the left arrow (inside the field)
	MULTI_DY = 12,     -- (the amount's line above the arrows' while splitting into stacks: the game's 30 against 18)
	TEXT = { half = "Half The Stack", halfTip = "The amount set to half the stack: %d of %d.",
		halfBundles = "The amount set to half of what you can buy, in whole bundles: %d of %d." },
}

function Split.Box()
	local f = rawget(_G, "StackSplitFrame")
	return type(f) == "table" and f.GetChildren and f or nil
end

-- the box's amount, step and maximum (the game's own fields, read)
function Split.Read(f)
	if not f then
		return nil, 1, nil
	end
	return Num(f.split), Num(f.minSplit) or 1, Num(f.maxStack)
end

-- the amount moved n steps (up: more) by the game's own arrows, never past its bounds
function Split.Step(n)
	local fn = rawget(_G, n > 0 and "StackSplitRightButton_OnClick" or "StackSplitLeftButton_OnClick")
	if type(fn) ~= "function" then
		return
	end
	for _ = 1, math.abs(n) do
		local split, step, max = Split.Read(Split.Box())
		if not split or (n > 0 and (not max or split >= max)) or (n < 0 and split <= step) then
			return
		end
		fn()
	end
end

-- half the stack, in whole steps (a merchant's bundles), at least one step
function Split.Target()
	local split, step, max = Split.Read(Split.Box())
	if not (split and max) then
		return nil
	end
	return math.max(step, math.floor(max / 2 / step) * step), max, step
end

Split.Wheel = Perf.Shared("OnMouseWheel over the split box", function(_, delta)
	if M.db and M.db.splitWheel == false then
		return
	end
	local n = IsShiftKeyDown() and Split.SHIFT or 1
	Split.Step((Num(delta) or 0) > 0 and n or -n)
end, "script")

Split.HalfClick = Perf.Shared("OnClick on the split box's ½", function()
	local target, _, step = Split.Target()
	local split = Split.Read(Split.Box())
	if target and split then
		Split.Step(math.floor((target - split) / step + 0.5))
	end
end, "script")

Split.HalfEnter = Perf.Shared("OnEnter on the split box's ½", function(b)
	local target, max, step = Split.Target()
	if target then
		W.ShowTooltip(b, Split.TEXT.half, (step > 1 and Split.TEXT.halfBundles or Split.TEXT.halfTip):format(target, max))
	end
end, "script")

-- a region's centre height, secret-safe
function Split.CenterY(obj)
	local ok, _, y = pcall(obj.GetCenter, obj)
	return ok and Num(y) or nil
end

-- the ½ and the wheel as the options and the box are: the ½ on the amount's line (the arrows' for one item, above
-- them for stacks), only while there is something to halve
function Split.Lay()
	local f, half = Split.Box(), Split.half
	if not (f and half) then
		return
	end
	local db = M.db
	Split.catcher:EnableMouseWheel((db and db.splitWheel ~= false) and true or false)
	local _, step, max = Split.Read(f)
	local on = db and db.splitHalf ~= false and max and max >= 2 * step and f.LeftButton
	half:SetShown(on and true or false)
	if on then
		local ay, ty = Split.CenterY(f.LeftButton), f.StackSplitText and Split.CenterY(f.StackSplitText)
		local dy = (ay and ty) and (ty - ay) or (f.isMultiStack == true and Split.MULTI_DY or 0)
		half:ClearAllPoints()
		half:SetPoint("LEFT", f.LeftButton, "RIGHT", Split.HALF_X, dy)
	end
end

-- made the first time the box shows (nothing at login)
function Split.Make(f)
	if Split.half then
		return
	end
	local catcher = MelloUI.Safe.CreateFrame("Frame", nil, f)
	catcher:SetAllPoints(f)
	catcher:EnableMouse(false)   -- (the arrows, the amount's typing and OK / Cancel stay the box's)
	Perf.SetScript(catcher, "OnMouseWheel", Split.Wheel)
	Split.catcher = catcher
	local half = W.Button(f, "½", Split.HALF_W, nil, { height = Split.HALF_H, onClick = Split.HalfClick })
	Perf.HookScript(half, "OnEnter", Split.HalfEnter)
	Perf.HookScript(half, "OnLeave", W.TipLeave)
	Split.half = half
end

Split.Shown = Perf.Shared("OnShow on the split box (the wheel, the ½)", function(f)
	Split.Make(f)
	Split.Lay()
end, "script")

-- (the box's own show, and its re-layout for one item or for stacks and a new maximum while it shows)
function Split.Hook()
	local f = Split.Box()
	if Split.hooked or not f then
		return
	end
	Split.hooked = true
	Perf.HookScript(f, "OnShow", Split.Shown)
	for _, method in ipairs({ "ChooseFrameType", "UpdateStackSplitFrame" }) do
		if type(f[method]) == "function" then
			hooksecurefunc(f, method, Split.Lay)
		end
	end
end
M.Split = Split   -- (the tests')

--------------------------------------------------------------------------------
-- World text scale
--------------------------------------------------------------------------------

local WORLD_TEXT_CVAR = "WorldTextScale"
local worldTextWarned = false

-- The player's own WorldTextScale is kept in the saved settings
-- (db.savedWorldTextScale, as Chat keeps the class colour cvar), taken ONCE,
-- just before this module first writes the cvar, and never taken again
-- while it is kept: a reload or the next login find MelloUI's own value in
-- the cvar and must not keep that as the player's (the 2026-09-24 review:
-- the original was read once per session, so after a /reload switching the
-- module off gave back MelloUI's value). The slider is written only once
-- the player has moved it -- a value other than the default, or the
-- original already kept -- so a scale set in the game's options is not
-- overwritten with 1.0 at every login. Written back and forgotten when the
-- module goes off. This session's copy of it (`keptWorldTextScale`) is the
-- one written back when both are there. (Loading a profile once cleared the
-- saved one too; it is a personal key now, kept by Core's ApplySettingsText,
-- and the session copy stays as a second guard.)
local keptWorldTextScale = nil

local function ReadWorldTextScale()
	if not (C_CVar and C_CVar.GetCVar) then
		return nil
	end
	local ok, current = pcall(C_CVar.GetCVar, WORLD_TEXT_CVAR)
	if not ok or type(current) ~= "string" or (issecretvalue and issecretvalue(current)) then
		return nil
	end
	return current
end

-- The client accepts a cvar it knows and ignores the rest without a word
-- (user, 2026-09-22: the slider did nothing, Config.wtf never got the
-- entry): a name this build does not have is reported once.
local function ApplyWorldTextScale(value)
	if not C_CVar or not C_CVar.SetCVar then
		return
	end
	local current = ReadWorldTextScale()
	if current == nil then
		-- (0.20.1: no cvar, no slider -- Core/ConfigLayout.lua lays it only where the client has one; nothing said)
		return
	end
	value = tonumber(value) or 1
	local db = M.db
	if db and db.savedWorldTextScale == nil then
		db.savedWorldTextScale = keptWorldTextScale or current   -- the player's own, before the first write
	end
	keptWorldTextScale = db and db.savedWorldTextScale or keptWorldTextScale
	if math.abs((tonumber(current) or -1) - value) < 0.001 then
		return   -- already so
	end
	local okS, done = pcall(C_CVar.SetCVar, WORLD_TEXT_CVAR, string.format("%.2f", value))
	if not (okS and done) and not worldTextWarned then
		worldTextWarned = true
		MelloUI:Print("Tweaks: the client refused '%s'; the World Text Scale slider cannot work on it.", WORLD_TEXT_CVAR)
	end
end

-- At login: the slider's value only once the player has moved it
local function WorldTextScaleWanted(db)
	if db.savedWorldTextScale ~= nil then
		return true
	end
	return math.abs((tonumber(db.worldTextScale) or 1) - 1) > 0.001
end

-- The player's own value back (the module off)
local function RestoreWorldTextScale()
	local db = M.db
	local saved = keptWorldTextScale or (db and db.savedWorldTextScale)
	keptWorldTextScale = nil
	if db then
		db.savedWorldTextScale = nil
	end
	if saved ~= nil and C_CVar and C_CVar.SetCVar then
		pcall(C_CVar.SetCVar, WORLD_TEXT_CVAR, saved)
	end
end

--------------------------------------------------------------------------------
-- Layouts (0.19.9, keybind_layout_sketch L1 and its buffs; docs/plans/
-- keybind-bar-layout.md). The game keeps a bar's rows, icons, icon size and
-- padding, and its buff and debuff bars' size, padding, icons per row,
-- direction and wrap, in the active Edit Mode layout: the Bar Layout rows,
-- and the Buff Layout rows while the game's buff bars show, read them from
-- there and write them back through MelloUI:EditModeSettingsSoon
-- (Core/EditModeLayout.lua: held while a slider moves, written once it is let
-- go, out of combat, a preset copied after asking). While MelloUI's own buff
-- rows show (Buffs & Debuffs on, Your Buffs And Debuffs on) the Buff Layout
-- rows are theirs, kept in Buffs & Debuffs' settings (playerSize in pixels,
-- playerSpacing, playerPerRow, playerGrow, playerNewRows). Nothing of either
-- is kept here: a profile carries Buffs & Debuffs' own, never the game's.
--------------------------------------------------------------------------------

Layout.barSetting = { barRows = "NumRows", barIcons = "NumIcons", barIconSize = "IconSize", barPadding = "IconPadding" }
Layout.buffOwn = { buffSize = "playerSize", buffSpacing = "playerSpacing", buffPerRow = "playerPerRow",
	buffGrow = "playerGrow", buffNewRows = "playerNewRows" }
Layout.BUFF_PX = 30   -- a buff icon at 100 % (the game's aura button): the game keeps the size as (% - 50) / 10
Layout.shape = {}     -- the preview's numbers (one table)
Layout.TEXT = {
	noLayout = "Your Edit Mode layout could not be read.",
	noSetting = "The game has no such setting for this bar.",
	column = "Your buffs grow away from the minimap column while they are attached to it (Buffs & Debuffs).",
}

-- an enum's value (nil on a client without it)
local function EnumOf(group, name)
	local e = Enum and Enum[group]
	return e and name and e[name]
end

local function Clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- the chosen bar's values (the held ones over them), or nil and why
function Layout.Bar(db)
	local system = EnumOf("EditModeSystem", "ActionBar")
	if not (system and MelloUI.EditModeSystemSettings) then
		return nil, Layout.TEXT.noLayout
	end
	local values = MelloUI:EditModeSystemSettings(system, (db or M.db).barLayoutBar or 1)
	if not values then
		return nil, Layout.TEXT.noLayout
	end
	return values
end

-- a Bar Layout slider's value (the icon size as a share: the game keeps
-- (size - 50) / 10)
function Layout.BarGet(db, key)
	local values = Layout.Bar(db)
	local setting = EnumOf("EditModeActionBarSetting", Layout.barSetting[key])
	local raw = values and setting and values[setting]
	if type(raw) ~= "number" then
		return nil
	end
	return key == "barIconSize" and raw * 10 + 50 or raw
end

-- why a Bar Layout row sleeps: the layout unread, or the bar without that
-- setting (the stance and pet bars keep their own icon count); nil: live
function Layout.BarMissing(key)
	local values, why = Layout.Bar()
	if not values then
		return why
	end
	if key then
		local setting = EnumOf("EditModeActionBarSetting", Layout.barSetting[key])
		if not (setting and values[setting] ~= nil) then
			return Layout.TEXT.noSetting
		end
	end
	return nil
end

-- the preview's numbers (W.ShapeRow)
function Layout.BarShape(db)
	local values = Layout.Bar(db)
	local S = Enum and Enum.EditModeActionBarSetting
	if not (values and S) then
		return nil
	end
	local bar, shape = (db or M.db).barLayoutBar or 1, Layout.shape
	shape.rows = values[S.NumRows] or 1
	shape.icons = values[S.NumIcons] or (bar >= 11 and 10 or 12)
	shape.size = values[S.IconSize] and values[S.IconSize] * 10 + 50 or 100
	shape.padding = values[S.IconPadding] or 2
	shape.vertical = values[S.Orientation] ~= nil and values[S.Orientation] == EnumOf("ActionBarOrientation", "Vertical")
	return shape
end

function Layout.BarSet(db, key, value)
	local system = EnumOf("EditModeSystem", "ActionBar")
	local setting = EnumOf("EditModeActionBarSetting", Layout.barSetting[key])
	if not (system and setting and MelloUI.EditModeSettingsSoon) or type(value) ~= "number" then
		return
	end
	local raw = key == "barIconSize" and math.floor((value - 50) / 10 + 0.5) or math.floor(value + 0.5)
	MelloUI:EditModeSettingsSoon(system, db.barLayoutBar or 1, { [setting] = raw })
end

-- Buffs & Debuffs' settings (its own table once it ran, else the saved one)
local function AurasDB()
	local A = MelloUI.modules.Auras
	return A and (A.db or MelloUI:GetModuleDB("Auras"))
end

-- MelloUI's own buff rows show: the Buff Layout rows are theirs
function Layout.Mine()
	local A, db = MelloUI.modules.Auras, AurasDB()
	return (A and A.isEnabled and db and db.player) and true or false
end

-- the game's buff bar's values (BuffFrame's: the debuff bar is written the
-- same), or nil
local function GameBuffs()
	local system = EnumOf("EditModeSystem", "AuraFrame")
	local index = EnumOf("EditModeAuraFrameSystemIndices", "BuffFrame")
	if not (system and index and MelloUI.EditModeSystemSettings) then
		return nil
	end
	return (MelloUI:EditModeSystemSettings(system, index))
end

function Layout.BuffGet(key)
	if Layout.Mine() then
		return AurasDB()[Layout.buffOwn[key]]
	end
	local values = GameBuffs()
	local S = Enum and Enum.EditModeAuraFrameSetting
	if not (values and S) then
		return nil
	end
	if key == "buffSize" then
		local raw = values[S.IconSize]
		return raw and math.floor(Layout.BUFF_PX * (raw * 10 + 50) / 100 + 0.5)
	elseif key == "buffSpacing" then
		return values[S.IconPadding]
	elseif key == "buffPerRow" then
		return values[S.IconLimitBuffFrame]
	elseif key == "buffGrow" then
		local v = values[S.IconDirection]
		return v ~= nil and (v == EnumOf("AuraFrameIconDirection", "Right") and "right" or "left") or nil
	elseif key == "buffNewRows" then
		local v = values[S.IconWrap]
		return v ~= nil and (v == EnumOf("AuraFrameIconDirection", "Up") and "up" or "down") or nil
	end
	return nil
end

function Layout.BuffMissing(key)
	if Layout.Mine() then
		local A = MelloUI.modules.Auras
		if key == "buffGrow" and A.Attached and A.Attached() then
			return Layout.TEXT.column
		end
		return nil
	end
	if not GameBuffs() then
		return Layout.TEXT.noLayout
	end
	return nil
end

-- a Buff Layout row set: into Buffs & Debuffs' own settings while its rows
-- show, else into the game's buff and debuff bars
function Layout.BuffSet(key, value)
	if Layout.Mine() then
		MelloUI:NotifySettingChanged("Auras", Layout.buffOwn[key], value)
		return
	end
	local system = EnumOf("EditModeSystem", "AuraFrame")
	local S = Enum and Enum.EditModeAuraFrameSetting
	if not (system and S and MelloUI.EditModeSettingsSoon) then
		return
	end
	for _, bar in ipairs({ "BuffFrame", "DebuffFrame" }) do
		local index = EnumOf("EditModeAuraFrameSystemIndices", bar)
		local t = {}
		if key == "buffSize" and type(value) == "number" then
			t[S.IconSize] = Clamp(math.floor((value * 100 / Layout.BUFF_PX - 50) / 10 + 0.5), 0, 15)
		elseif key == "buffSpacing" and type(value) == "number" then
			t[S.IconPadding] = Clamp(math.floor(value + 0.5), 5, 15)
		elseif key == "buffPerRow" and type(value) == "number" then
			if bar == "DebuffFrame" then
				t[S.IconLimitDebuffFrame] = Clamp(math.floor(value + 0.5), 1, 16)
			else
				t[S.IconLimitBuffFrame] = Clamp(math.floor(value + 0.5), 2, 32)
			end
		elseif key == "buffGrow" then
			t[S.IconDirection] = EnumOf("AuraFrameIconDirection", value == "right" and "Right" or "Left")
		elseif key == "buffNewRows" then
			t[S.IconWrap] = EnumOf("AuraFrameIconDirection", value == "up" and "Up" or "Down")
		end
		if index and next(t) then
			MelloUI:EditModeSettingsSoon(system, index, t)
		end
	end
end
M.Layout = Layout   -- (the tests')

--------------------------------------------------------------------------------
-- Quality Gems and Grey Out Junk (one look, stage D3: moved here from
-- Modules/Kit.lua, where they showed only on a slot the painted kit had
-- dressed; the user, 2026-10-15: look A of MelloUI-BuildData/output/
-- onelook_gems_sketch, the corner gem, on EVERY item -- the game's bags, bank
-- and guild bank and MelloUI's bag window -- and both on for everyone, while
-- Everything Off keeps them off). MelloUI.ItemGems.
--
-- Quality Gems (user, 2026-09-26: "can we also add those tooltip gems onto
-- the items in the backpack themselves, to easy as a glance separate normal
-- items from Junk Items etc"; option A of the bag gems mockup). Every item in
-- a slot of the bag windows, the bank, the guild bank and the bag window by
-- kind shows a small gem in its quality's TRUE colour, the game's own
-- (ITEM_QUALITY_COLORS: junk grey, common white, uncommon green, rare blue,
-- epic purple, legendary orange, artifact and heirloom in theirs): the
-- tooltip's gem, MelloUI.QuestInk's QI.Gem (one gem for the interface). An
-- empty slot, and a quality the game hands over secret, not at all or one
-- ITEM_QUALITY_COLORS has no colour for, shows none.
--   where       the slot's top-left corner, 2 px in from the icon's corner
--               (the icon in the rim's opening on a dressed slot), about 37 %
--               of the button's size (14 px on the 37 px slot; the mockup's
--               15 on 40); a child of the button, so it scales with it
--   layering    over the button's own art (the icon, the quality border, the
--               stack count's layer) and over its cooldown child, two levels
--               up: a level of its own (WINDOW-RULES: never tie with the
--               game's frame; between the button and its cooldown, one level
--               apart, there is none) -- and so over a dressed slot's kit
--               frames (its rim and border are regions of the button, its
--               stone's opening one level up). The diamond keeps to its
--               corner: the count stays in the bottom-right one, the
--               cooldown's time in the middle
--   the corner  the game's own marks there: the merchant's junk coin
--               (JunkIcon), the upgrade arrow (UpgradeIcon), a quest
--               starter's "!" (IconQuestTexture set to TEXTURE_ITEM_QUEST_BANG,
--               its "!" down the icon's left side) and a crafting reagent's
--               quality badge (ProfessionQualityOverlay: the game makes it
--               the first time the slot holds one, TOPLEFT -3, 2, its atlas
--               33 x 28; crafted gear wears it only while the Professions
--               window is open). While one shows, the gem steps over to the
--               top-right corner, and back when it goes: both stay readable
--               (the badge's box reaches past the middle of a 37 px slot, so
--               no corner is clear of the box itself; the top-right one is
--               the furthest from its picture, which hangs off the top-left)
--   dimmed      a slot the game dims (the search box, or an item that does
--               not fit what an open window wants: its ItemContextOverlay
--               in the game's dim mode, ItemButtonConstants.ContextMatch
--               .Standard; an older client's searchOverlay) dims its gem as
--               well. The same overlay as the runeforge glow round an item
--               the game highlights is not a dim: the gem stays bright
--   finding     a slot is found at the game's own first update of it: one
--               post-hook on the game's global SetItemButtonQuality (the
--               bags, the bank grid, the guild bank and the bag window by
--               kind all call it with the quality, poor and common too),
--               put in at Tweaks' enable, takes a slot whose parent is a
--               host -- the game's bag windows by name (ContainerFrame1..N,
--               the combined one only while it IS visible: the bag window by
--               kind holds it under a hidden holder), the bank's BankPanel,
--               a guild bank column, or a holder of the bag window by kind
--               (Gems.AddHost). Any other caller (a merchant, the loot, a
--               quest reward, a tooltip's item, the bank's bag slots) costs
--               a cached look-up and is never written on
--   when        then from the game's own updates of the slot, post-hooked on
--               the button when it is found: SetItemButtonQuality,
--               UpdateItemContextOverlay (the search's shade; each window's
--               update of a slot ends with it, the junk coin, the quest mark
--               and the reagent's badge set by then), the quest texture's
--               SetTexture (the "!" or the plain border; the bank sets it
--               before the quality: its first "!" read from the game's
--               record of the slot, questItemInfo), and the reagent badge's
--               SetShown (hooked when the gem first meets it: the
--               Professions window shows and hides crafted gear's badge on
--               its own). A gem is made the first time its slot has an item
--               to show with the switch on (nothing at login, none for an
--               empty slot), kept with the pooled button and recoloured on
--               those updates; no OnUpdate, no timer
--   the switch  one for the three windows: Tweaks' Quality Gems (on; its rows
--               on Windows > Bags / Bank / Guild Bank > Look), and Tweaks on
--               (it is while UI Modifications is: Everything Off shows none).
--               Off: every gem hidden at once, none made; a slot is found
--               only while one of the two switches is on
-- Grey Out Junk (0.16.0, user 2026-09-30: "the junk items should be
-- desaturated in the inventory"; one look D3, the user: a cover, never a
-- write on the game's picture -- the game sets its own grey on every update
-- of a slot, a picked-up item's): a slot holding a poor item (quality 0)
-- shows a grey copy of its picture just over the game's own -- a texture of
-- the button's own, in the icon's draw layer one sublevel up (under the
-- count, the borders and the overlays), on the icon's rect, desaturated --
-- made the first time the slot holds junk, following the icon: its picture,
-- its crop, its tint and its alpha copied at each update of the slot, and
-- again from post-hooks on the icon's SetTexture / SetVertexColor / SetShown
-- (a cooldown's tint comes after the quality). Shown while Grey Out Junk
-- (Tweaks' greyJunk, on) and Tweaks are on, hidden as the item goes or the
-- switch does; the game's own picture and its grey are left alone.
--   Gems.Install()  the global post-hook, once (Tweaks' enable)
--   Gems.Sync()     every slot found again (the switches, Tweaks on or off)
--   Gems.AddHost(frame)  a parent whose item buttons are slots (BagWindow)
--   Gems.Adopt(button, quality, kind)  a slot taken now (the tests')
--   Gems.Counts() -> slots found, gems made, gems shown, covers made, covers shown
--------------------------------------------------------------------------------

local Gems = {}
MelloUI.ItemGems = Gems

do
	local SIZE, INSET, DIM = 0.37, 2, 0.25   -- (look A) of the button's width; px in from the icon's corner; a dimmed slot's gem
	local GEMS_KEY, JUNK_KEY = "qualityGems", "greyJunk"
	local Secret, Finite, Text, SafeCall = MelloUI.Safe.IsSecret, MelloUI.Safe.Finite, MelloUI.Safe.Text, MelloUI.Safe.Call
	local Shared = Perf.Shared
	local slots = {}                                      -- every slot found, in the order found
	local gemOf = setmetatable({}, { __mode = "k" })      -- [button] = its slot's state
	local gemOfArt = setmetatable({}, { __mode = "k" })   -- [quest texture] = its slot's state
	local gemOfBadge = setmetatable({}, { __mode = "k" }) -- [reagent quality badge] = its slot's state
	local coverOf = setmetatable({}, { __mode = "k" })    -- [the game's icon] = its slot's state (its cover made)
	local hostOf = setmetatable({}, { __mode = "k" })     -- [a slot's parent] = "bags" | "bank" | "guild" | "own" | false
	local installed = false
	local made, covers = 0, 0

	-- a switch of Tweaks' as it is now (Tweaks off: none); read on each use,
	-- no copy kept (a profile load hands Tweaks a new table)
	local function Setting(key)
		if M.isEnabled ~= true then
			return false
		end
		local db = M.db
		return type(db) == "table" and db[key] ~= false
	end

	local function Wanted()
		return Setting(GEMS_KEY)
	end

	local function JunkWanted()
		return Setting(JUNK_KEY)
	end

	-- the game's own colour of an item quality (`q` a plain number); nil when
	-- it has none plainly. ITEM_QUALITY_COLORS is the game's (its colour
	-- manager fills it for every quality there is, 0 .. NumValues - 1): a
	-- quality it lacks is unknown, no gem. Only a client without that table
	-- asks C_Item, for a quality in range (it answers a colour for any number)
	local function Colour(q)
		local list = ITEM_QUALITY_COLORS
		local r, g, b
		if type(list) == "table" then
			local c = list[q]
			if type(c) ~= "table" then
				return nil
			end
			r, g, b = c.r, c.g, c.b
		else
			local meta = Enum and Enum.ItemQualityMeta
			local count = meta and Num(meta.NumValues) or 9
			if not (C_Item and C_Item.GetItemQualityColor) or q < 0 or q >= count or q ~= math.floor(q) then
				return nil
			end
			local ok
			ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
			if not ok then
				return nil
			end
		end
		r, g, b = Num(r), Num(g), Num(b)
		if r and g and b then
			return r, g, b
		end
		return nil
	end

	-- a region of the game's shown (a secret reads as not shown)
	local function Shown(region)
		if not region then
			return false
		end
		local ok, shown = pcall(region.IsShown, region)
		return ok and not Secret(shown) and shown == true
	end

	-- one of the game's own marks in the top-left corner (the reagent's
	-- badge read from the button each time: the game makes it late)
	local function CornerTaken(st)
		local b = st.button
		return Shown(b.JunkIcon) or Shown(b.UpgradeIcon) or (st.bang and Shown(b.IconQuestTexture))
			or Shown(b.ProfessionQualityOverlay) or false
	end

	-- a slot the game dims: its context overlay shown in the dim mode (the
	-- search box, an item that does not fit the open window), not as the
	-- glow round an item it highlights (runeforging); the game's own reader
	-- of the mode, where there is one. An older client's searchOverlay
	local function Dimmed(button)
		if Shown(button.ItemContextOverlay) then
			local read = button.GetItemContextOverlayMode
			local match = _G.ItemButtonConstants and _G.ItemButtonConstants.ContextMatch
			local standard = match and match.Standard
			if type(read) ~= "function" or standard == nil then
				return true   -- (no mode on this client: the overlay is the dim)
			end
			local ok, mode = pcall(read, button)
			return ok and not Secret(mode) and mode == standard
		end
		return Shown(button.searchOverlay)
	end

	-- its size (of the button's) and level (over the button's children):
	-- when made and when the switch comes on (the button keeps both for the
	-- session: not read again on every update)
	local function Fit(st, gem)
		local b = st.button
		local okW, w = pcall(b.GetWidth, b)
		w = okW and Finite(w) or nil
		gem:SetGemSize(w and w > 0 and math.floor(w * SIZE + 0.5) or 14)
		local okL, level = pcall(b.GetFrameLevel, b)
		level = okL and Num(level) or nil
		if level and level + 2 ~= st.level then
			st.level = level + 2
			gem:SetFrameLevel(level + 2)
		end
	end

	-- the reagent badge's own shows and hides (the Professions window's, for
	-- crafted gear): a gem shown moved (below, with the other hooks)
	local Gem_OnBadge

	-- its corner (the top-right one while the game's own mark takes the
	-- top-left) and its alpha (a slot the game dims)
	local function Marks(st, gem)
		local button = st.button
		-- the reagent's badge, heard from the first time the gem meets it
		local badge = button.ProfessionQualityOverlay
		if badge and not gemOfBadge[badge] and badge.SetShown then
			gemOfBadge[badge] = st
			hooksecurefunc(badge, "SetShown", Gem_OnBadge)
		end
		local aside = CornerTaken(st)
		if aside ~= st.aside then
			st.aside = aside
			local icon = st.icon or button
			gem:ClearAllPoints()
			if aside then
				gem:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -INSET, -INSET)
			else
				gem:SetPoint("TOPLEFT", icon, "TOPLEFT", INSET, -INSET)
			end
		end
		local dim = Dimmed(button)
		if dim ~= st.dim then
			st.dim = dim
			gem:SetAlpha(dim and DIM or 1)
		end
	end

	-- the slot's gem as the game's slot now is: shown in its quality's colour
	-- (made the first time), or hidden; `refit`: its size and level again
	local function Sync(st, refit)
		local q = st.q
		local r, g, b = nil, nil, nil
		if q and Wanted() then
			r, g, b = Colour(q)
		end
		local gem = st.gem
		if not r then
			if gem then
				gem:Hide()
			end
			return
		end
		if not gem then
			local QI = MelloUI.QuestInk
			if not (QI and QI.Gem) then
				return
			end
			gem = QI.Gem(st.button)
			st.gem = gem
			made = made + 1
			refit = true
		end
		if refit then
			Fit(st, gem)
		end
		Marks(st, gem)
		gem:SetColour(r, g, b)
	end

	-- Grey Out Junk's cover: the icon's look copied onto it (its picture,
	-- its crop, its tint, its alpha), each written only when it changed;
	-- false when the picture cannot be read or set (no cover shown then)
	local function Copy(st, cover)
		local icon = st.icon
		local ok, art = pcall(icon.GetTexture, icon)
		if not ok then
			return false
		end
		if Secret(art) then
			-- (handed on as it is, never compared; a client that refuses it: no cover)
			if not pcall(cover.SetTexture, cover, art) then
				return false
			end
			st.art = nil
		elseif art == nil then
			return false
		elseif art ~= st.art then
			st.art = art
			cover:SetTexture(art)
		end
		local okC, ulx, uly, llx, lly, urx, ury, lrx, lry = pcall(icon.GetTexCoord, icon)
		if okC and Num(ulx) and Num(uly) and Num(llx) and Num(lly) and Num(urx) and Num(ury) and Num(lrx) and Num(lry) then
			local tc = st.tc
			if tc[1] ~= ulx or tc[2] ~= uly or tc[3] ~= llx or tc[4] ~= lly or tc[5] ~= urx or tc[6] ~= ury
				or tc[7] ~= lrx or tc[8] ~= lry then
				tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8] = ulx, uly, llx, lly, urx, ury, lrx, lry
				cover:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
			end
		end
		local okV, r, g, b = pcall(icon.GetVertexColor, icon)
		r, g, b = okV and Num(r), okV and Num(g), okV and Num(b)
		if r and g and b and (r ~= st.r or g ~= st.g or b ~= st.b) then
			st.r, st.g, st.b = r, g, b
			cover:SetVertexColor(r, g, b)
		end
		local okA, alpha = pcall(icon.GetAlpha, icon)
		alpha = okA and Finite(alpha) or 1
		if alpha ~= st.alpha then
			st.alpha = alpha
			cover:SetAlpha(alpha)
		end
		return true
	end

	-- the slot's junk grey as the game's slot now is: its cover shown over a
	-- poor item's picture (made the first time) and following it, or hidden
	local Cover_OnIcon
	local function Junk(st)
		local icon = st.icon
		if not icon then
			return
		end
		local cover = st.cover
		if st.q == 0 and JunkWanted() and Shown(icon) then
			if not cover then
				local layer, sub = "BORDER", 0
				local ok, l, s = pcall(icon.GetDrawLayer, icon)
				if ok and Text(l) then
					layer, sub = l, Num(s) or 0
				end
				cover = st.button:CreateTexture(nil, layer, nil, math.min(sub + 1, 7))
				cover:SetAllPoints(icon)
				cover:SetDesaturated(true)
				cover:Hide()
				st.cover, st.tc = cover, {}
				covers = covers + 1
				coverOf[icon] = st
				hooksecurefunc(icon, "SetTexture", Cover_OnIcon)
				hooksecurefunc(icon, "SetVertexColor", Cover_OnIcon)
				hooksecurefunc(icon, "SetShown", Cover_OnIcon)
			end
			if Copy(st, cover) then
				if not st.grey then
					st.grey = true
					cover:Show()
				end
				return
			end
		end
		if st.grey then
			st.grey = false
			cover:Hide()
		end
	end

	-- the game's own updates of a slot (one handler each for every slot, no
	-- closure of their own)
	local Gem_OnQuality = Shared("SetItemButtonQuality on a bag, bank or guild bank slot (Quality Gems)", function(button, quality)
		local st = gemOf[button]
		if st then
			st.q = Num(quality)
			Sync(st)
			Junk(st)
		end
	end)
	-- the picture of a slot that held junk changed (its art, its tint, its
	-- show): the cover follows
	Cover_OnIcon = Shared("SetTexture / SetVertexColor / SetShown on a bag, bank or guild bank slot's picture (Grey Out Junk's cover)", function(icon)
		local st = coverOf[icon]
		if st then
			Junk(st)
		end
	end)
	-- the corner's marks and the search's shade: a gem shown moved or dimmed
	-- (none shown: nothing to do; the next quality update places it)
	local Gem_OnMarks = Shared("the corner and search marks on a bag, bank or guild bank slot (Quality Gems)", function(button)
		local st = gemOf[button]
		local gem = st and st.gem
		if gem and gem:IsShown() then
			Marks(st, gem)
		end
	end)
	Gem_OnBadge = Shared("SetShown on a bag, bank or guild bank slot's reagent quality badge (Quality Gems)", function(region)
		local st = gemOfBadge[region]
		local gem = st and st.gem
		if gem and gem:IsShown() then
			Marks(st, gem)
		end
	end)
	local Gem_OnQuestArt = Shared("SetTexture on a bag, bank or guild bank slot's quest mark (Quality Gems)", function(region, art)
		local st = gemOfArt[region]
		if st then
			local bang = _G.TEXTURE_ITEM_QUEST_BANG
			st.bang = bang ~= nil and Text(art) == bang
		end
	end)

	-- a bank slot's quest starter: the game's own record of the slot
	-- (questItemInfo, read only), whose "!" it set before the quality
	local function BankBang(button)
		local quest = button.questItemInfo
		if type(quest) ~= "table" then
			return false
		end
		local id = Num(quest.questID)
		local going = quest.isActive
		if Secret(going) then
			going = true   -- (unknown: not taken for a quest starter)
		end
		return id ~= nil and not going
	end

	-- what a slot's parent is: one of the game's bag windows (by name: the
	-- bag window by kind takes ContainerFrame frames elsewhere), the bank's
	-- grid, a guild bank column, a holder of the bag window by kind, or none
	-- (cached: a frame stays what it is). Reads only
	local function HostKind(parent)
		local kind = hostOf[parent]
		if kind ~= nil then
			return kind
		end
		kind = false
		if parent == rawget(_G, "ContainerFrameCombinedBags") then
			kind = "bags"
		else
			for i = 1, Num(rawget(_G, "NUM_CONTAINER_FRAMES")) or 13 do
				if parent == rawget(_G, "ContainerFrame" .. i) then
					kind = "bags"
					break
				end
			end
		end
		if not kind then
			local frame = rawget(_G, "BankFrame")
			local bank = (type(frame) == "table" and frame.BankPanel) or rawget(_G, "BankPanel")
			if bank ~= nil and parent == bank then
				kind = "bank"
			end
		end
		if not kind then
			local guild = rawget(_G, "GuildBankFrame")
			local columns = type(guild) == "table" and guild.Columns
			if type(columns) == "table" then
				for i = 1, #columns do
					if columns[i] == parent then
						kind = "guild"
						break
					end
				end
			end
		end
		hostOf[parent] = kind
		return kind
	end

	function Gems.AddHost(frame)
		if type(frame) == "table" then
			hostOf[frame] = "own"
		end
	end

	-- a slot taken: the game's updates of it heard from now on, and its gem
	-- and junk grey as the game just gave it (`kind`: its host's, "bank" to
	-- read the bank's "!")
	function Gems.Adopt(button, quality, kind)
		if type(button) ~= "table" or gemOf[button] or type(button.SetItemButtonQuality) ~= "function" then
			return
		end
		local st = { button = button, icon = button.icon }
		gemOf[button] = st
		slots[#slots + 1] = st
		hooksecurefunc(button, "SetItemButtonQuality", Gem_OnQuality)
		-- (the search's shade, called last in each window's update of a slot:
		-- the corner's marks are set by then)
		local dim = (button.UpdateItemContextOverlay and "UpdateItemContextOverlay") or (button.SetMatchesSearch and "SetMatchesSearch")
		if dim then
			hooksecurefunc(button, dim, Gem_OnMarks)
		end
		local quest = button.IconQuestTexture
		if quest and quest.SetTexture then
			gemOfArt[quest] = st
			hooksecurefunc(quest, "SetTexture", Gem_OnQuestArt)
		end
		st.q = Num(quality)
		if kind == "bank" then
			st.bang = BankBang(button)
		end
		Sync(st, true)
		Junk(st)
	end

	-- the game's first update of a slot: taken when its parent is a host and
	-- one of the switches is on. Anything else passes with a cached look-up,
	-- nothing written (every item button of the game calls this)
	local OnAnyQuality = Shared("SetItemButtonQuality: a bag, bank or guild bank slot's first update (Quality Gems)", function(button, quality)
		if type(button) ~= "table" or gemOf[button] or not (Wanted() or JunkWanted()) then
			return
		end
		local parent = SafeCall(button, "GetParent")
		local kind = parent and HostKind(parent)
		if not kind then
			return
		end
		if kind == "bags" and SafeCall(parent, "IsVisible") ~= true then
			return   -- (the combined bags under the bag window's hidden holder: not cached, taken once shown again)
		end
		Gems.Adopt(button, quality, kind)
	end)

	function Gems.Install()
		if installed or type(rawget(_G, "SetItemButtonQuality")) ~= "function" then
			return
		end
		installed = true
		hooksecurefunc("SetItemButtonQuality", OnAnyQuality)
	end

	-- the switches read again (Quality Gems or Grey Out Junk changed, Tweaks
	-- on or off, a profile load): every slot found, nothing made while off
	function Gems.Sync()
		for i = 1, #slots do
			local st = slots[i]
			Sync(st, true)
			Junk(st)
		end
	end

	function Gems.Counts()
		local shown, grey = 0, 0
		for i = 1, #slots do
			local st = slots[i]
			if st.gem and st.gem:IsShown() then
				shown = shown + 1
			end
			if st.cover and st.cover:IsShown() then
				grey = grey + 1
			end
		end
		return #slots, made, shown, covers, grey
	end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	-- (first: an error further down never leaves the item slots behind)
	Gems.Install()
	Gems.Sync()
	RegisterEditModeCallbacks()
	if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
		editModeActive = EditModeManagerFrame:IsEditModeActive()
	end
	UpdateHiddenFrames()
	if WorldTextScaleWanted(db) then
		ApplyWorldTextScale(db.worldTextScale)
	end
	Split.Hook()
end

function M:OnDisable()
	-- (a profile load's restart runs this with Tweaks still on: its enable
	-- follows and syncs again)
	Gems.Sync()
	UpdateHiddenFrames()
	RestoreWorldTextScale()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if HIDE_TARGETS[key] or key == "bagSlotsOnBags" or key == "bagBarFold" then
		UpdateHiddenFrames()
	elseif key == "worldTextScale" then
		ApplyWorldTextScale(value)
	elseif key == "splitWheel" or key == "splitHalf" then
		Split.Lay()
	elseif key == "qualityGems" or key == "greyJunk" then
		Gems.Install()   -- (once: a retry, should the game's function not have been there at the enable)
		Gems.Sync()
	elseif Layout.barSetting[key] then
		-- (0.19.9) the game's value: read back from the layout, never kept here
		db[key] = nil
		Layout.BarSet(db, key, value)
	elseif Layout.buffOwn[key] then
		db[key] = nil
		Layout.BuffSet(key, value)
	end
end
