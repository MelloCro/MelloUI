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
	},
	options = {
		{ type = "header", name = "Hide Frames" },
		{ type = "toggle", key = "hideMicroMenu", name = "Hide Micro Menu",
		  desc = "Hide the row of menu buttons (character, spellbook, talents, ...). Still shown while Edit Mode is open." },
		{ type = "toggle", key = "hideBagBar", name = "Hide Bag Bar",
		  desc = "Hide the backpack and bag slot buttons. Still shown while Edit Mode is open. Bags can still be opened with their keybinds." },
		{ type = "toggle", key = "hideMinimapCoords", name = "Hide Minimap Coordinates",
		  desc = "Hide the player coordinates the client writes under the minimap." },
		{ type = "toggle", key = "bagSlotsOnBags", parent = "hideBagBar", name = "Bag Slots on Bag Window",
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
		  desc = "A soft dark shade behind the text MelloUI shows on the world, so it reads on bright ground: the zone name when you enter a new area (with its subzone and PvP lines), the game's messages in the middle of the screen (red errors, yellow quest progress, raid warnings and boss emotes) and the Route's Direction Arrow and World Marker. No outline on the first two (Outlined Text adds it back); the game's colours stay. Off: the game's own look, and no shade behind the arrow and the marker." },
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
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	RegisterEditModeCallbacks()
	if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
		editModeActive = EditModeManagerFrame:IsEditModeActive()
	end
	UpdateHiddenFrames()
	if WorldTextScaleWanted(db) then
		ApplyWorldTextScale(db.worldTextScale)
	end
end

function M:OnDisable()
	UpdateHiddenFrames()
	RestoreWorldTextScale()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if HIDE_TARGETS[key] or key == "bagSlotsOnBags" or key == "bagBarFold" then
		UpdateHiddenFrames()
	elseif key == "worldTextScale" then
		ApplyWorldTextScale(value)
	elseif Layout.barSetting[key] then
		-- (0.19.9) the game's value: read back from the layout, never kept here
		db[key] = nil
		Layout.BarSet(db, key, value)
	elseif Layout.buffOwn[key] then
		db[key] = nil
		Layout.BuffSet(key, value)
	end
end
