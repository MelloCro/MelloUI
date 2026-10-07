--------------------------------------------------------------------------------
-- MelloUI - Bag Window: the bags by kind (0.19.0)
--
-- The user, 2026-10-04 (after the bag addon study): "sketch first", then A of
-- MelloUI-BuildData/output/bag_view_sketch/bag_view_looks.jpg. One bag window
-- of MelloUI's own in place of the game's: a heading over each kind of item,
-- small kinds side by side in a row, the empty slots folded into one. The
-- plan and every decision: docs/plans/bag-window.md.
--
-- Kinds: an item goes to the first that takes it (KindOf): Recent (the game's
-- new-item mark; kept in Recent until the window closes, so a hovered item
-- does not jump away under the mouse), Junk (poor quality), Quest, Gear,
-- Consumables, Trade Goods, Other. Shown in KINDS' order, Empty last: the
-- first free slot's own button with the number of free slots on it (an item
-- dropped there goes into that slot), one more for each special bag type
-- with room (its rim in the bag type's colour, as every slot of such a bag).
-- A heading clicked folds its kind into one slot (its first item, the kind's
-- count beside it), kept per character. Junk's heading shows what it sells
-- for, and at a vendor a Sell Junk button (the game's own sell-all-junk).
--
-- How it stays out of the game's way:
--   * the game keeps deciding when the bags are open. Combined Bags is held
--     on (its CVar, put back when this goes off), so the held bags are all
--     in the game's one combined window, and that window is re-parented to a
--     hidden holder: the game's IsBagOpen and its toggles read IsShown, which
--     the holder leaves alone, so every open and close the game does (the
--     bag key, the backpack button, a vendor, the bank, mail, trade, the
--     auction house, Escape) still happens -- and nothing of the game's
--     window is drawn or can be clicked (its OnShow, its layout, never run).
--     Post-hooks on the game's bag functions show or hide this window from
--     it; this window's close button and Escape hide the game's with :Hide(),
--     as the game's own backpack toggle does. The bank's bags keep their own
--     windows. No global replaced, no key written on a game frame.
--   * the item buttons are the game's ContainerFrameItemButtonTemplate (use,
--     sell, deposit at the bank, split, drag, the tooltip, the cooldown: the
--     game's own code), each in a holder frame per bag whose ID is the bag
--     (the button's GetBagID reads its parent's ID, its own ID is the slot):
--     no Initialize, no attribute, nothing the game's code reads is written.
--     They are dressed by the game's bag slots' own dressing
--     (BackpackPanel:DressSlots) while the kit is on.
-- Nothing at login: the window and its buttons are made on the first open.
-- While it is hidden it listens to nothing; it is laid out again on each open.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("BagWindow")
local Shared, hooksecurefunc, C_Timer = Perf.Shared, Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit
local W = MelloUI.Widgets
local Look = MelloUI.Look
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number

-- (the user, 2026-10-04: "what kind of customization options can we give the players?" -- the kinds and the layout
-- picked; their own kinds, saved searches, come with a sketch first)
local RECENT_FOR = {
	{ value = "close", label = "Until The Bags Close" },
	{ value = "hover", label = "Until Hovered" },
	{ value = "minutes", label = "For 5 Minutes" },
}
local SORT_BY = {
	{ value = "quality", label = "Quality" },
	{ value = "name", label = "Name" },
	{ value = "newest", label = "Newest First" },
	{ value = "level", label = "Item Level" },
}

local M = MelloUI:RegisterModule("BagWindow", {
	title = "Bags by Kind",
	desc = "Your bags in one window of MelloUI's own, sorted by kind: what you picked up lately, gear, quest items, consumables, junk, trade goods and the rest, each under its own heading. The empty slots fold into one slot with their count.",
	icon = "Interface\\Icons\\INV_Misc_Bag_08",
	flavour = "A place for everything, and everything under its heading.",
	role = "feature",
	-- (no group: its rows sit on the Windows page, the bag window's)
	installer = false,
	enabledByDefault = true,
	defaults = { recent = true, recentFor = "close", gear = true, quest = true, consumables = true, junk = true,
		trade = true, splitTrade = false, columns = 10, itemSize = 37, foldEmpty = true, sortBy = "quality" },
	options = {
		{ type = "toggle", key = "recent", name = "Recent Kind",
		  desc = "What you picked up lately, under its own heading first. Off: it goes straight to its own kind." },
		{ type = "dropdown", key = "recentFor", parent = "recent", name = "Recent Lasts", values = RECENT_FOR,
		  desc = "How long an item stays under Recent: until you close your bags, only until you point at it (it moves to its own kind as the pointer leaves it), or for 5 minutes after you got it." },
		{ type = "toggle", key = "gear", name = "Gear Kind",
		  desc = "Weapons and armour under their own heading. Off: they go to Other." },
		{ type = "toggle", key = "quest", name = "Quest Kind",
		  desc = "Quest items, and items that start a quest, under their own heading. Off: they go to their own kind." },
		{ type = "toggle", key = "consumables", name = "Consumables Kind",
		  desc = "Food, drink, potions, scrolls and bandages under their own heading. Off: they go to Other." },
		{ type = "toggle", key = "junk", name = "Junk Kind",
		  desc = "Grey junk under its own heading, with what it sells for (and Sell Junk at a vendor). Off: it goes to its own kind." },
		{ type = "toggle", key = "trade", name = "Trade Goods Kind",
		  desc = "Crafting materials, reagents, recipes and gems under their own heading. Off: they go to Other." },
		{ type = "toggle", key = "splitTrade", parent = "trade", name = "Split Trade Goods",
		  desc = "Trade goods split by type, each under its own heading: Cloth, Leather, Metal & Stone, Herbs, Meat, Reagents, Recipes and so on." },
		{ type = "slider", key = "columns", name = "Columns", min = 8, max = 16, step = 1,
		  desc = "How many slots across the bag window is: more makes it wider and shorter." },
		{ type = "slider", key = "itemSize", name = "Item Size", min = 30, max = 46, step = 1,
		  desc = "How big the item slots are (37 is the game's own size)." },
		{ type = "toggle", key = "foldEmpty", name = "Fold Empty Slots",
		  desc = "All your empty slots as one slot with their count (drop an item on it to put it in a free slot). Off: every empty slot shows." },
		{ type = "dropdown", key = "sortBy", name = "Sort Items By", values = SORT_BY,
		  desc = "The order inside each kind: better quality first, by name, the ones you picked up last first, or the highest item level first." },
	},
})

local AREA = "backpack"   -- the bag windows' look (Kit.Areas)

-- the window's grid, in UI units (the game's combined bags: 37 px slots, 5 apart, ten across); SLOT and COLS are
-- the player's (Item Size, Columns: Grid)
local G = {
	BASE = 37,       -- the game's slot (the template's size): a slot of another size is the button scaled
	SLOT = 37, GAP = 5, COLS = 10,
	SIDE = 12,       -- the content's inset from the window's sides
	TOP = 74,        -- the content's top below the window's top (the title rail, the search row, the ring's foot)
	RING = 84,       -- the corner ring: the game's corner piece's size (PortraitFrameTemplate's TopLeftCorner)
	RING_X = 24, RING_Y = -17,   -- its centre (the kit look): its gems over the rail's and the plate's cut ends
	SEARCH_X = 70,   -- the search box's left, past the ring
	PANEL_PAD = 6,   -- the dark panel round the items
	PANEL_ALPHA = 0.9,
	FOOT = 38,       -- the money row under the content (and its dark panel)
	HEAD = 17,       -- a kind's heading above its items
	ROW_GAP = 8,     -- between rows of kinds
	KIND_GAP = 15,   -- between kinds side by side
}
-- the grid from the player's Columns and Item Size
local function Clamp(v, lo, hi, default)
	v = Num(v) or default
	return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

local function Grid()
	local db = M.db or {}
	G.COLS = Clamp(db.columns, 8, 16, 10)
	G.SLOT = Clamp(db.itemSize, 30, 46, G.BASE)
	G.SCALE = G.SLOT / G.BASE
	G.PITCH = G.SLOT + G.GAP
	G.CONTENT_W = G.COLS * G.PITCH - G.GAP
	G.WIDTH = G.CONTENT_W + 2 * G.SIDE
end
Grid()
M.G, M.Grid = G, Grid   -- (the tests)

local TEXT = {
	title = "Bags",
	fold = "Click to fold this kind into one slot.",
	unfold = "Click to show every item of this kind.",
	sell = "Sell Junk",
	sellTip = "Sell every junk item to this vendor.",
	worth = "Sells for %s",
	free = "%d free |4slot:slots;",
	sort = "Clean Up Bags",
	settings = "Bag Settings",
	settingsTip = "Bags by Kind's options: its kinds and its layout (Windows > Bags).",
}

-- The kinds, in the order they are shown (the sketch's)
local KINDS = {
	{ key = "recent", name = "Recent" },
	{ key = "gear", name = "Gear" },
	{ key = "quest", name = "Quest" },
	{ key = "other", name = "Other" },
	{ key = "consumables", name = "Consumables" },
	{ key = "junk", name = "Junk" },
	{ key = "trade", name = "Trade Goods" },
	{ key = "empty", name = "Empty" },
}
M.KINDS = KINDS

-- an item's class (Enum.ItemClass numbers: this client's) to its kind
local CLASS_KIND = {
	[0] = "consumables",                 -- food, drink, potions, elixirs, scrolls, bandages
	[2] = "gear", [4] = "gear",          -- weapons, armour
	[3] = "trade", [5] = "trade", [7] = "trade", [9] = "trade",   -- gems, reagents, trade goods, recipes
	[12] = "quest",
}
local POOR = 0   -- Enum.ItemQuality.Poor
local TRADE_GOODS = 7   -- the trade goods' class (split by its subclasses: Cloth, Leather ...)
local ALL_ON = { recent = true, gear = true, quest = true, consumables = true, junk = true, trade = true }

-- Which kind an item is: the first that takes it, of the kinds switched on
-- (`on`: the module's settings; a kind off passes its items on: Recent's to
-- their own kind, Junk's and Quest's to their class's, the classes' to Other)
function M.KindOf(quality, classID, isQuestItem, recent, on)
	on = on or ALL_ON
	-- (a switch not saved yet reads as on: every kind is on by default)
	if recent and on.recent ~= false then
		return "recent"
	elseif quality == POOR and on.junk ~= false then
		return "junk"
	elseif (isQuestItem or classID == 12) and on.quest ~= false then
		return "quest"
	end
	local kind = CLASS_KIND[classID]
	if kind and kind ~= "quest" and on[kind] ~= false then
		return kind
	end
	return "other"
end

-- Split Trade Goods: a trade good's own kind (its key and its heading: the
-- client's own name of its type, a reagent's, recipe's or gem's class name)
local tradeNames = {}   -- [key] = the heading, read once
local function TradeKind(classID, subclassID)
	local key = classID == TRADE_GOODS and ("trade:7:" .. subclassID) or ("trade:" .. classID)
	if not tradeNames[key] then
		local C = C_Item
		local name
		if classID == TRADE_GOODS and subclassID ~= 0 and C and C.GetItemSubClassInfo then
			name = C.GetItemSubClassInfo(classID, subclassID)
		elseif classID ~= TRADE_GOODS and C and C.GetItemClassInfo then
			name = C.GetItemClassInfo(classID)
		end
		tradeNames[key] = type(name) == "string" and name ~= "" and name or "Trade Goods"
	end
	return key, tradeNames[key]
end
M.TradeKind = TradeKind

--------------------------------------------------------------------------------
-- The bags read: every slot of the held bags, each item's kind
--------------------------------------------------------------------------------

local win = {}          -- the window's parts (made on the first open)
local holders = {}      -- [bag] = the frame the bag's buttons sit in (its ID: the bag)
local slots = {}        -- [bag] = { [slot] = button }
local made = {}         -- every button made, in order (handed to the dressing)
local undressed = 0     -- the buttons made since the last dressing
local entries = {}      -- the items read, reused ({ bag, slot, kind, ... })
local nEntries = 0
local byKind = {}       -- [kind key] = { entries } (lists reused)
local empties = {}      -- the free slots shown: { bag, slot, free } (reused), normal bags first
local nEmpties = 0
local heldID = {}       -- [bag * 1000 + slot] = itemID: Recent (until the bags close, or for some minutes)
local heldAt = {}       -- [bag * 1000 + slot] = when it was first seen new (For 5 Minutes)
local RECENT_MINUTES = 5
local junkWorth = 0     -- copper; nil while an item's price is not known yet
local trades = {}       -- the trade goods' kinds this layout (Split Trade Goods), by name
local nTrades = 0
for _, k in ipairs(KINDS) do
	byKind[k.key] = {}
end

local function HeldBags()
	local inv = Constants and Constants.InventoryConstants
	return 0, inv and Num(inv.NumBagSlots) or 4
end

local function Entry(i)
	local e = entries[i]
	if not e then
		e = {}
		entries[i] = e
	end
	return e
end

local function Quest(bag, slot)
	local C = C_Container
	local q = C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(bag, slot)
	if type(q) ~= "table" then
		return false, nil, nil
	end
	local active = q.isActive
	if Secret(active) then
		active = true
	end
	return (q.isQuestItem or q.questID ~= nil) and true or false, q.questID, active
end

local function SellPrice(itemID)
	local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	if not GetInfo then
		return nil
	end
	local ok, name, _, _, _, _, _, _, _, _, _, price = pcall(GetInfo, itemID)
	if not ok or not name then
		return nil
	end
	return Num(price) or 0
end

-- The order inside a kind (Sort Items By): better quality first, then by
-- class and item, bigger stacks first, then where they lie; Name, Newest
-- First (the order they were picked up in, as far as this window saw them
-- arrive: db.seen) and Item Level first by theirs
local function ByQuality(a, b)
	if a.quality ~= b.quality then
		return a.quality > b.quality
	elseif a.classID ~= b.classID then
		return a.classID < b.classID
	elseif a.itemID ~= b.itemID then
		return a.itemID < b.itemID
	elseif a.count ~= b.count then
		return a.count > b.count
	elseif a.bag ~= b.bag then
		return a.bag < b.bag
	end
	return a.slot < b.slot
end
local SORTS = {
	quality = ByQuality,
	name = function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return ByQuality(a, b)
	end,
	newest = function(a, b)
		if a.seen ~= b.seen then
			return a.seen > b.seen
		end
		return ByQuality(a, b)
	end,
	level = function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		return ByQuality(a, b)
	end,
}

local function ItemLevel(info, itemID)
	local C = C_Item
	local link = info.hyperlink
	if C and C.GetDetailedItemLevelInfo and type(link) == "string" then
		local ok, level = pcall(C.GetDetailedItemLevelInfo, link)
		level = ok and Num(level)
		if level then
			return level
		end
	end
	local GetInfo = C and C.GetItemInfo or GetItemInfo
	local ok, _, _, _, level = pcall(GetInfo, itemID)
	return ok and Num(level) or 0
end

-- Newest First: the order items were seen arrive (the game's new-item mark),
-- kept per character between sessions; an item no longer in the bags is
-- forgotten at the next layout
local seenSlot = {}   -- [bag * 1000 + slot] = the itemID last numbered there (this session)
local present = {}    -- [itemID] = the layout's stamp (the pruning's)
local readStamp = 0
local function Seen(db, itemID, key, isNewNow)
	local seen = db.seen
	if type(seen) ~= "table" then
		seen = {}
		db.seen, db.seenN = seen, 0
	end
	if isNewNow and seenSlot[key] ~= itemID then
		seenSlot[key] = itemID
		db.seenN = (Num(db.seenN) or 0) + 1
		seen[itemID] = db.seenN
	end
	present[itemID] = readStamp
end

local function PruneSeen(db)
	local seen = db.seen
	if type(seen) ~= "table" then
		return
	end
	for itemID in pairs(seen) do
		if present[itemID] ~= readStamp then
			seen[itemID] = nil
		end
	end
end

-- Recent (Recent Lasts): new now, or held -- until the bags close (wiped at
-- the close), or for some minutes from when it was first seen new; Until
-- Hovered: only while the game's own new mark is on it
local function Recent(mode, key, itemID, isNewNow, now)
	if mode == "hover" then
		return isNewNow
	end
	if isNewNow and heldID[key] ~= itemID then
		heldID[key], heldAt[key] = itemID, now
	elseif heldID[key] ~= itemID then
		return false
	end
	if not heldAt[key] then
		heldAt[key] = now   -- (never without a clock: one without stayed for ever)
	end
	return mode ~= "minutes" or now - heldAt[key] < RECENT_MINUTES * 60
end

-- the free slots read (reused: one layout's)
local familyFree, familyBag, familySlot = {}, {}, {}
local recentEnds = nil   -- For 5 Minutes: when the first item shown under Recent leaves it

local function AddEmpty(bag, slot, free)
	nEmpties = nEmpties + 1
	local e = empties[nEmpties]
	if not e then
		e = {}
		empties[nEmpties] = e
	end
	e.bag, e.slot, e.free = bag, slot, free
end

local function ByTradeName(a, b)
	return tradeNames[a] < tradeNames[b]
end

local function ReadBags()
	local C = C_Container
	local db = M.db or ALL_ON
	for _, list in pairs(byKind) do
		wipe(list)
	end
	nEntries, nEmpties, nTrades, junkWorth, recentEnds = 0, 0, 0, 0, nil
	readStamp = readStamp + 1
	local normalFree, normalBag, normalSlot = 0, nil, nil
	wipe(familyFree)
	wipe(familyBag)
	wipe(familySlot)
	local first, last = HeldBags()
	local isNew = C_NewItems and C_NewItems.IsNewItem
	local recentMode = db.recentFor or "close"
	local sortBy = SORTS[db.sortBy] and db.sortBy or "quality"
	local split = db.splitTrade and db.trade ~= false
	local fold = db.foldEmpty ~= false
	local now = GetTime()
	for bag = first, last do
		local n = Num(C.GetContainerNumSlots(bag)) or 0
		local family = 0
		if bag > 0 and n > 0 and C.GetContainerNumFreeSlots then
			local ok, _, fam = pcall(C.GetContainerNumFreeSlots, bag)
			family = ok and Num(fam) or 0
		end
		for slot = 1, n do
			local info = C.GetContainerItemInfo(bag, slot)
			local itemID = info and Num(info.itemID)
			if itemID then
				nEntries = nEntries + 1
				local e = Entry(nEntries)
				e.bag, e.slot, e.itemID, e.info = bag, slot, itemID, info
				e.quality = Num(info.quality) or 1
				e.count = Num(info.stackCount) or 1
				local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
				e.classID = Num(classID) or 15
				e.subclassID = Num(subclassID) or 0
				e.isQuest, e.questID, e.questActive = Quest(bag, slot)
				local key = bag * 1000 + slot
				local isNewNow = isNew and isNew(bag, slot) and true or false
				local recent = Recent(recentMode, key, itemID, isNewNow, now)
				if recent and recentMode == "minutes" then
					local ends = heldAt[key] + RECENT_MINUTES * 60
					recentEnds = recentEnds and math.min(recentEnds, ends) or ends
				end
				local kind = M.KindOf(e.quality, e.classID, e.isQuest, recent, db)
				if kind == "trade" and split then
					kind = TradeKind(e.classID, e.subclassID)
					local list = byKind[kind]
					if not list then
						list = {}
						byKind[kind] = list
					end
					if #list == 0 then
						nTrades = nTrades + 1
						trades[nTrades] = kind
					end
				end
				e.kind = kind
				local list = byKind[kind]
				list[#list + 1] = e
				if sortBy == "name" then
					e.name = type(info.hyperlink) == "string" and info.hyperlink:match("%[(.-)%]") or ""
				elseif sortBy == "level" then
					e.level = ItemLevel(info, itemID)
				end
				if M.db then
					Seen(M.db, itemID, key, isNewNow)   -- (the numbers read after the pass: every stack of a type alike)
				end
				if e.quality == POOR and junkWorth and not info.hasNoValue then
					local price = SellPrice(itemID)
					junkWorth = price and junkWorth + price * e.count or nil
				end
			elseif not fold then
				AddEmpty(bag, slot, nil)   -- (Fold Empty Slots off: every free slot)
			elseif family == 0 then
				normalFree = normalFree + 1
				if not normalBag then
					normalBag, normalSlot = bag, slot
				end
			else
				familyFree[family] = (familyFree[family] or 0) + 1
				if not familyBag[family] then
					familyBag[family], familySlot[family] = bag, slot
				end
			end
		end
	end
	local seen = M.db and type(M.db.seen) == "table" and M.db.seen or nil
	for i = 1, nEntries do
		local e = entries[i]
		e.seen = seen and Num(seen[e.itemID]) or 0
	end
	local order = SORTS[sortBy]
	for _, list in pairs(byKind) do
		if #list > 1 then
			table.sort(list, order)
		end
	end
	for i = #trades, nTrades + 1, -1 do
		trades[i] = nil
	end
	if nTrades > 1 then
		table.sort(trades, ByTradeName)
	end
	if M.db then
		PruneSeen(M.db)
	end
	-- the free slots folded: the normal bags' first, then each bag type's
	if normalBag then
		AddEmpty(normalBag, normalSlot, normalFree)
	end
	for family, bag in pairs(familyBag) do
		AddEmpty(bag, familySlot[family], familyFree[family])
	end
	return nEntries
end
M.ReadBags = ReadBags   -- (the tests)
M.byKind, M.empties = byKind, empties

--------------------------------------------------------------------------------
-- The item buttons: the game's own template, one holder per bag
--------------------------------------------------------------------------------

local LayoutSoon   -- (the events' one, below)

-- Recent Lasts Until Hovered: was this slot's item laid under Recent, and is
-- the game's new-item mark off it now?
local function LeftRecent(bag, slot)
	local list = byKind.recent
	if not (list and M.db and M.db.recentFor == "hover") then
		return false
	end
	if C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) then
		return false
	end
	for i = 1, #list do
		if list[i].bag == bag and list[i].slot == slot then
			return true
		end
	end
	return false
end

local SlotLeft = Shared("OnLeave on a bag window slot", function(self)
	-- the game cleared its new-item mark on the hover: the glow follows
	local bag, slot = self:GetBagID(), self:GetID()
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info and self.UpdateNewItem then
		self:UpdateNewItem(info.quality)
	end
	-- Until Hovered: the item leaves Recent as the pointer leaves it (laid
	-- again on the next frame, never while it is under the mouse; options
	-- audit, 2026-10-05: it stayed until the next relayout)
	if LeftRecent(bag, slot) then
		LayoutSoon()
	end
end, "script")

local function Holder(bag)
	local h = holders[bag]
	if not h then
		h = CreateFrame("Frame", nil, win.content)
		h:SetID(bag)
		h:SetAllPoints(win.content)
		holders[bag] = h
	end
	return h
end

local function SlotButton(bag, slot)
	local list = slots[bag]
	if not list then
		list = {}
		slots[bag] = list
	end
	local b = list[slot]
	if not b then
		b = CreateFrame("ItemButton", nil, Holder(bag), "ContainerFrameItemButtonTemplate")
		b:SetID(slot)
		b:SetSize(G.BASE, G.BASE)   -- (Item Size scales it: Place)
		-- an empty slot's own picture: the one the game's combined bags give
		-- their buttons (its Initialize, which is not called here)
		b.ItemSlotBackground = b:CreateTexture(nil, "BACKGROUND", "ItemSlotBackgroundCombinedBagsTemplate", -6)
		b.ItemSlotBackground:SetAllPoints(b)
		Perf.HookScript(b, "OnLeave", SlotLeft)
		list[slot] = b
		made[#made + 1] = b
		undressed = undressed + 1
	end
	return b
end

-- The slot as the game's bag window fills it (ContainerFrameMixin:UpdateItems)
local function Fill(b, e)
	local info = e and e.info
	local texture = info and info.iconFileID
	ClearItemButtonOverlay(b)
	b:SetHasItem(texture)
	b:SetItemButtonTexture(texture)
	SetItemButtonQuality(b, info and info.quality, info and info.hyperlink, false, info and info.isBound)
	SetItemButtonCount(b, info and info.stackCount)
	SetItemButtonDesaturated(b, info and info.isLocked)
	b:UpdateQuestItem(e and e.isQuest or false, e and e.questID, e and e.questActive)
	b:UpdateNewItem(info and info.quality)
	b:UpdateJunkItem(info and info.quality, info and info.hasNoValue)
	b:UpdateItemContextMatching()
	b:UpdateCooldown(texture)
	b:SetReadable(info and info.isReadable)
	b:SetMatchesSearch(not (info and info.isFiltered))
end

-- the free slots' button: empty, the number of free slots on it
local function FillEmpty(b, free)
	Fill(b, nil)
	if free then
		b.Count:SetText(free)
		b.Count:Show()
	end
end

-- every button made since the last time dressed as the game's bag slots
-- (while the kit is on; the game's look stays on them otherwise)
local dressedPitch = nil
local function Dress()
	-- (the pitch in the buttons' own units: they are scaled to Item Size)
	local pitch = G.PITCH / G.SCALE
	if pitch ~= dressedPitch then
		undressed = #made   -- (a new Item Size: every rim laid on the new pitch)
	end
	if undressed == 0 then
		return
	end
	local panel = MelloUI:GetModule("BackpackPanel")
	if panel and panel.DressSlots and panel:DressSlots(made, #made, { pitch, pitch }) then
		undressed, dressedPitch = 0, pitch
	end
end

--------------------------------------------------------------------------------
-- The headings: one per kind, made with the window
--------------------------------------------------------------------------------

local headings = {}   -- [kind key] = the heading button
local folds = {}      -- [kind key] = the count beside a folded kind's slot

local function Folded(key)
	local f = M.db and M.db.folded
	return type(f) == "table" and f[key] == true
end

local function HeadingWidth(h, key)
	local w = Num(h.text:GetStringWidth()) or 0
	if Folded(key) then
		w = w + 14
	end
	if key == "junk" then
		w = w + 10 + (Num(h.worth:GetStringWidth()) or 0)
	end
	return w + 4
end

local HeadingClick = Shared("OnClick on a bag window heading", function(self)
	local key = self.key
	if key == "empty" then
		return
	end
	local f = M.db.folded
	if type(f) ~= "table" then
		f = {}
		M.db.folded = f
	end
	f[key] = not f[key] or nil
	MelloUI:PlayUISound(f[key] and "check_off" or "check_on")
	M:Layout()
	if self:IsMouseOver() then
		self:GetScript("OnEnter")(self)
	end
end, "script")

local HeadingEnter = Shared("OnEnter on a bag window heading", function(self)
	if self.key == "empty" then
		W.ShowTooltip(self, self.name, TEXT.free:format(self.free or 0))
		return
	end
	local body = Folded(self.key) and TEXT.unfold or TEXT.fold
	if self.key == "junk" and junkWorth and junkWorth > 0 then
		body = TEXT.worth:format(GetMoneyString(junkWorth, true)) .. "\n" .. body
	end
	W.ShowTooltip(self, self.name, body)
end, "script")

-- a kind's heading, made the first time that kind shows (a trade good's type
-- with Split Trade Goods: one per type ever, kept)
local function Heading(key, name)
	local h = headings[key]
	if h then
		return h
	end
	h = CreateFrame("Button", nil, win.content)
	h:SetHeight(G.HEAD)
	h.key, h.name = key, name
	h.text = h:CreateFontString(nil, "OVERLAY")
	Look.Text(h.text, "gold", 12, { area = AREA })
	h.text:SetText(name)
	h.plus = h:CreateTexture(nil, "OVERLAY")
	h.plus:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	h.plus:SetSize(12, 12)
	h.plus:SetPoint("LEFT", h, "LEFT", 0, 0)
	if key == "junk" then
		h.worth = h:CreateFontString(nil, "OVERLAY")
		Look.Text(h.worth, "text", 11, { area = AREA })
		h.worth:SetPoint("RIGHT", h, "RIGHT", -1, 0)
	end
	Perf.SetScript(h, "OnClick", HeadingClick)
	Perf.SetScript(h, "OnEnter", HeadingEnter)
	Perf.SetScript(h, "OnLeave", W.TipLeave)
	headings[key] = h
	local fold = win.content:CreateFontString(nil, "OVERLAY")
	Look.Text(fold, "number", 12, { area = AREA })
	folds[key] = fold
	return h
end

local function LayHeading(h, folded)
	h.text:ClearAllPoints()
	h.text:SetPoint("LEFT", h, "LEFT", folded and 14 or 1, 0)
	h.plus:SetShown(folded)
end

--------------------------------------------------------------------------------
-- The layout: the kinds packed in rows, each kind's items under its heading
--------------------------------------------------------------------------------

local shownStamp = 0
local used = setmetatable({}, { __mode = "k" })   -- [button] = the stamp of the layout that placed it

-- a slot at x, y of the content: the button at the game's own size, scaled to
-- Item Size (its points then in its own scale's units)
local function Place(b, x, y)
	local k = G.SCALE
	if b:GetScale() ~= k then
		b:SetScale(k)
	end
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", win.content, "TOPLEFT", x / k, -y / k)
	b:Show()
	used[b] = shownStamp
end

-- the kinds this layout shows, in order: Trade Goods' place taken by its
-- types (Split Trade Goods), by name
local order, orderName = {}, {}
local function Order()
	local n = 0
	local split = M.db and M.db.splitTrade and M.db.trade ~= false
	for _, kind in ipairs(KINDS) do
		if kind.key == "trade" and split then
			for i = 1, nTrades do
				n = n + 1
				order[n], orderName[n] = trades[i], tradeNames[trades[i]]
			end
		else
			n = n + 1
			order[n], orderName[n] = kind.key, kind.name
		end
	end
	for i = #order, n + 1, -1 do
		order[i], orderName[i] = nil, nil
	end
	return n
end

local function AtVendor()
	local mf = rawget(_G, "MerchantFrame")
	return mf and mf:IsShown() and true or false
end

local function SellShown()
	return AtVendor() and junkWorth ~= 0 and #byKind.junk > 0
end

local function RecentEnded()
	win.expiryAt = nil
	if win.frame and win.frame:IsShown() then
		M:Layout()
	end
end

-- the row's buttons from the right: Sort, Discard while it shows, Settings;
-- the search box up to the last of them
local function FitSearch()
	local d = win.discard
	local to = (d and d:IsShown()) and d or win.sort
	if win.searchTo ~= to then
		win.searchTo = to
		win.settings:ClearAllPoints()
		win.settings:SetPoint("RIGHT", to, "LEFT", -2, 0)
		win.search:ClearAllPoints()
		win.search:SetPoint("TOPLEFT", win.frame, "TOPLEFT", G.SEARCH_X, -35)
		win.search:SetPoint("RIGHT", win.settings, "LEFT", -8, 0)
	end
end

function M:Layout()
	if not win.frame then
		return
	end
	FitSearch()
	Grid()
	win.frame:SetWidth(G.WIDTH)
	win.content:SetWidth(G.CONTENT_W)
	ReadBags()
	shownStamp = shownStamp + 1
	local x, y, rowH = 0, 0, 0
	-- (the headings of kinds not shown this time are hidden after: a kind
	-- emptied or switched off, a trade type gone, the split off)
	for _, h in pairs(headings) do
		h.laid = false
	end
	for i = 1, Order() do
		local key = order[i]
		local list = byKind[key]
		local n = key == "empty" and nEmpties or (list and #list or 0)
		local h = n > 0 and Heading(key, orderName[i]) or headings[key]
		local fold = folds[key]
		if n > 0 then
			h.laid = true
			local folded = key ~= "empty" and Folded(key) and n > 1
			if key == "junk" then
				h.worth:SetText(junkWorth and junkWorth > 0 and GetMoneyString(junkWorth, true) or "")
				h.worth:SetShown(not SellShown())
			end
			LayHeading(h, folded)
			local items = folded and 1 or n
			local cols = math.min(items, G.COLS)
			local lines = math.ceil(items / G.COLS)
			local w = math.max(cols * G.PITCH - G.GAP, HeadingWidth(h, key))
			w = math.min(w, G.CONTENT_W)
			if x > 0 and x + G.KIND_GAP + w > G.CONTENT_W then
				y = y + rowH + G.ROW_GAP
				x, rowH = 0, 0
			elseif x > 0 then
				x = x + G.KIND_GAP
			end
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", win.content, "TOPLEFT", x, -y)
			h:SetWidth(w)
			h:Show()
			if key == "empty" then
				h.free = 0
				for j = 1, n do
					local e = empties[j]
					local b = SlotButton(e.bag, e.slot)
					FillEmpty(b, e.free)
					Place(b, x + ((j - 1) % G.COLS) * G.PITCH, y + G.HEAD + math.floor((j - 1) / G.COLS) * G.PITCH)
					h.free = h.free + (e.free or 1)
				end
			else
				for j = 1, items do
					local e = list[j]
					local b = SlotButton(e.bag, e.slot)
					Fill(b, e)
					Place(b, x + ((j - 1) % G.COLS) * G.PITCH, y + G.HEAD + math.floor((j - 1) / G.COLS) * G.PITCH)
				end
			end
			if folded then
				fold:SetText(n)
				fold:ClearAllPoints()
				fold:SetPoint("BOTTOMLEFT", win.content, "TOPLEFT", x + G.SLOT + 3, -(y + G.HEAD + G.SLOT))
				fold:Show()
			else
				fold:Hide()
			end
			rowH = math.max(rowH, G.HEAD + lines * G.PITCH - G.GAP)
			x = x + w
		end
	end
	-- the headings and buttons this layout did not lay: hidden
	for key, h in pairs(headings) do
		if not h.laid and h:IsShown() then
			h:Hide()
			folds[key]:Hide()
		end
	end
	for _, b in ipairs(made) do
		if used[b] ~= shownStamp and b:IsShown() then
			b:Hide()
		end
	end
	-- For 5 Minutes: laid out again as the first item leaves Recent (one
	-- timer at a time, unless an earlier end comes)
	if recentEnds and not (win.expiryAt and win.expiryAt <= recentEnds) then
		win.expiryAt = recentEnds
		C_Timer.After(math.max(recentEnds - GetTime(), 0) + 0.2, RecentEnded)
	end
	local height = y + rowH
	win.content:SetHeight(math.max(height, 1))
	win.frame:SetHeight(G.TOP + math.max(height, G.SLOT) + G.FOOT)
	-- the Sell Junk button on Junk's heading, at a vendor
	local sell = win.sell
	if SellShown() and headings.junk.laid then
		sell:ClearAllPoints()
		sell:SetPoint("RIGHT", headings.junk, "RIGHT", 0, 0)
		sell:Show()
	else
		sell:Hide()
	end
	Dress()
	MelloUI:Fire("bagwindow", true)
end

-- the items' marks only (the lock while one is moved, the search, the cooldowns): no new layout
local function Refresh()
	if not (win.frame and win.frame:IsShown()) then
		return
	end
	local C = C_Container
	for _, b in ipairs(made) do
		if b:IsShown() then
			local info = C.GetContainerItemInfo(b:GetBagID(), b:GetID())
			SetItemButtonDesaturated(b, info and info.isLocked)
			b:SetMatchesSearch(not (info and info.isFiltered))
			b:UpdateCooldown(info and info.iconFileID)
		end
	end
end

--------------------------------------------------------------------------------
-- The game's bag window: kept in step, never shown
--------------------------------------------------------------------------------

local hidden = nil       -- the holder the game's combined window is parented to while this is on
local gameParent = nil   -- its own parent, given back
local captured = false

local function Game()
	return rawget(_G, "ContainerFrameCombinedBags")
end

local function GameOpen()
	local g = Game()
	return g and g:IsShown() and true or false
end

local Capture   -- (below)

local function Sync()
	if M.isEnabled and not captured and M.pending and not InCombatLockdown() then
		Capture()   -- (switched on while the bags were open: now they are closed)
	end
	if not (M.isEnabled and captured) then
		return
	end
	local open = GameOpen()
	local f = win.frame
	if open and not (f and f:IsShown()) then
		M:Open()
	elseif not open and f and f:IsShown() then
		f:Hide()
	end
end
M.Sync = Sync

local SyncHook = Shared("the bag window's step with the game's bags", function()
	Sync()
end, "hook")

local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	for _, name in ipairs({ "OpenAllBags", "CloseAllBags", "ToggleAllBags", "ToggleBackpack", "OpenBackpack",
		"CloseBackpack", "ToggleBag", "OpenBag", "CloseBag" }) do
		if type(rawget(_G, name)) == "function" then
			hooksecurefunc(name, SyncHook)
		end
	end
end

-- Combined Bags held on while this is on (the game's own setting: a CVar),
-- put back as it was when this goes off
local function HoldCombined(on)
	local db = M.db
	if on then
		if not GetCVarBool("combinedBags") then
			db.combinedWas = false
			SetCVar("combinedBags", 1)
		end
	elseif db and db.combinedWas == false then
		db.combinedWas = nil
		SetCVar("combinedBags", 0)
	end
end

-- The game's window is moved under the holder only while it is closed (at
-- login, or at its next close when this is switched on with the bags open):
-- moved while it shows, its OnHide would run from this code (tainted), and
-- the game's own bag records with it. Out of combat too.
function Capture()
	local g = Game()
	if captured or not g then
		return
	end
	if InCombatLockdown() or g:IsShown() then
		M.pending = true
		return
	end
	M.pending = nil
	hidden = hidden or CreateFrame("Frame", nil, UIParent)
	hidden:Hide()
	HoldCombined(true)
	gameParent = g:GetParent()
	g:SetParent(hidden)
	captured = true
end

-- Given back closed: while it is under the holder its Hide runs no script
-- (it is not visible), and given back hidden its OnShow does not run either;
-- the game's own next open lays it out
local function Release()
	if not captured then
		M.pending = nil
		return
	end
	if InCombatLockdown() then
		M.pending = true
		return
	end
	M.pending = nil
	captured = false
	local g = Game()
	if g and g:IsShown() then
		g:Hide()
	end
	if win.frame and win.frame:IsShown() then
		win.closing = true
		win.frame:Hide()
		win.closing = false
	end
	if g then
		g:SetParent(gameParent or UIParent)
	end
	HoldCombined(false)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local Listen   -- (below: the events while shown)

-- The bags' Window Background (0.19.4, the options audit: Backpack Kit's, as the game's bag windows and the bank wear
-- it) on this window's page: the shell's page stone takes it (opts.background), with the kit look, as theirs do
local function WindowBackground()
	local panel = MelloUI:GetModule("BackpackPanel")
	return panel and panel.WindowBackground and panel:WindowBackground() or nil
end

-- The money lies on the page: in dark ink while the page is parchment (the parchment ink rule, QuestInk.lua), in its
-- own colours otherwise (the texts of this window's own money frame, the game's template)
local MONEY_TEXTS = { "GoldButton", "SilverButton", "CopperButton" }
local function InkMoney()
	local QI, money = MelloUI.QuestInk, win.money
	if not (QI and QI.InkText and QI.PlainText and money) then
		return
	end
	local paper = Kit:IsOn(AREA) and Kit:BackgroundIsPaper(WindowBackground())   -- (the aged parchment too, 0.19.8)
	for _, key in ipairs(MONEY_TEXTS) do
		local button = money[key]
		local fs = button and button.Text
		if fs then
			if paper then
				QI.InkText(fs)
			else
				QI.PlainText(fs)
			end
		end
	end
end

-- the bags' Window Background changed (Backpack Kit's option or the picker, on the bus whether that module is on or
-- off): the page and the money's ink at once (taken with the window, at its first open)
local BackgroundChanged = Shared("'setting' on the bus (the bag window's background)", function(name, key)
	if name == "BackpackPanel" and key == "windowBackground" and win.shell then
		win.shell:SetBackground()
		InkMoney()
	end
end)

local Shown = Shared("OnShow on the bag window", function()
	MelloUI:PlayUISound("bags_open")
	Listen(true)
	if win.money then
		MoneyFrame_UpdateMoney(win.money)
	end
	InkMoney()
	M:Layout()
end, "script")

local Hidden = Shared("OnHide on the bag window", function()
	Listen(false)
	-- Recent Lasts Until The Bags Close: let go now (For 5 Minutes keeps its clock)
	if not (M.db and M.db.recentFor == "minutes") then
		wipe(heldID)
		wipe(heldAt)
	end
	-- closed here (its close button, Escape): the game's bags closed too
	if not win.closing and captured and GameOpen() then
		Game():Hide()
	end
	MelloUI:PlayUISound("bags_close")
	MelloUI:Fire("bagwindow", false)
end, "script")

local SortClick = Shared("OnClick on the bag window's sort button", function()
	MelloUI:PlayUISound("menu_button")
	C_Container.SortBags()
end, "script")

local SortEnter = Shared("OnEnter on the bag window's sort button", function(self)
	W.ShowTooltip(self, TEXT.sort)
end, "script")

-- Settings: the settings window on Windows, the Bags pick (the bag window's
-- panel module's word: its page and pick)
local SETTINGS_SCRIPTS = {
	OnClick = Shared("OnClick on the bag window's Settings", function()
		MelloUI:OpenConfig("BackpackPanel")
	end, "script"),
	OnEnter = Shared("OnEnter on the bag window's Settings", function(self)
		W.ShowTooltip(self, TEXT.settings, TEXT.settingsTip)
	end, "script"),
	OnLeave = W.TipLeave,
}

local SellClick = Shared("OnClick on the bag window's Sell Junk", function()
	if not AtVendor() then
		return
	end
	local CM = C_MerchantFrame
	if CM and CM.SellAllJunkItems and (not CM.IsSellAllJunkEnabled or CM.IsSellAllJunkEnabled()) then
		CM.SellAllJunkItems()
	else
		for _, e in ipairs(byKind.junk) do
			C_Container.UseContainerItem(e.bag, e.slot)
		end
	end
end, "script")

local function Build()
	local f = CreateFrame("Frame", "MelloUIBagWindow", UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetSize(G.WIDTH, G.TOP + G.SLOT + G.FOOT)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	-- (its own scripts before the shell's hooks: SetScript drops hooks)
	Perf.SetScript(f, "OnShow", Shown)
	Perf.SetScript(f, "OnHide", Hidden)
	win.frame = f
	-- the corner ring as big as on the game's bag window and set higher (user, 2026-10-04: "the texture on the top
	-- left corner is off", then the talents window's corner: "this is how they should connect"): the rail and the
	-- title plate are cut along the ring's middle lines (Kit:TitleBehindRing), and the shell's ring left the cut
	-- ends showing beside its gems
	local ringW = Kit:Size("window/portrait_ring")
	win.shell = Kit:OwnWindow(f, {
		area = AREA, plate = "rail",
		ring = { at = "tl", texture = "Interface\\Buttons\\Button-Backpack-Up", scale = ringW > 0 and G.RING / ringW or 1,
			x = G.RING_X, y = G.RING_Y },
		title = TEXT.title, close = true, escape = true, fit = true, background = WindowBackground,
		mover = { key = "MelloUIBagWindow", label = TEXT.title, page = "Windows", default = M.Home },
	})
	MelloUI:On("setting", BackgroundChanged, "Bag window background")
	-- the items, on the own windows' dark panel (user, 2026-10-04: "this part should have a darker background for
	-- clarity and less eye strain, that part should scale with the inventory size"; WINDOW-RULES 2e): W.Panel, the
	-- game's inset in its look, held round the items by its corners so it grows and shrinks with them
	local panel = W.Panel(f, { alpha = G.PANEL_ALPHA })
	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", f, "TOPLEFT", G.SIDE, -G.TOP)
	content:SetWidth(G.CONTENT_W)
	content:SetHeight(G.SLOT)
	content:SetFrameLevel(panel:GetFrameLevel() + 1)
	panel:SetPoint("TOPLEFT", content, "TOPLEFT", -G.PANEL_PAD, G.PANEL_PAD)
	panel:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", G.PANEL_PAD, -G.PANEL_PAD)
	win.content, win.panel = content, panel
	-- the search row: the game's own bag search (its text kept with the
	-- game's other search boxes; what does not match is dimmed)
	local sort = CreateFrame("Button", nil, f)
	sort:SetSize(28, 26)
	sort:SetNormalAtlas("bags-button-autosort-up")
	sort:SetPushedAtlas("bags-button-autosort-down")
	W.HoverLight(sort, "square")   -- (the game's sort button's light: the shared one)
	sort:SetPoint("TOPRIGHT", f, "TOPRIGHT", -G.SIDE, -32)
	Perf.SetScript(sort, "OnClick", SortClick)
	Perf.SetScript(sort, "OnEnter", SortEnter)
	Perf.SetScript(sort, "OnLeave", W.TipLeave)
	win.sort = sort
	local search = CreateFrame("EditBox", nil, f, "BagSearchBoxTemplate")
	search:SetHeight(20)
	W.FlatSearch(search)   -- (the Configurator's search box, as every own window's)
	win.search = search
	win.shell:Kit(function(K)
		if sort:GetNormalTexture() then
			win.shell:Replace(sort:GetNormalTexture(), { as = "bags-button-autosort-up", button = sort, noFade = true })
		end
	end)
	-- the Discard button (its own module's: the same button as on the game's bag window)
	local discard = MelloUI:GetModule("Discard")
	if discard and discard.KindWindowButton then
		win.discard = discard:KindWindowButton(f)
		if win.discard then
			win.discard:SetPoint("RIGHT", sort, "LEFT", -2, 0)
		end
	end
	-- the Settings button (user, 2026-10-04: "a button in the backpack like a shortcut to that window"; pick A of
	-- bag_view_sketch/bag_settings_looks.jpg): Discard's button with the game's options gear, the settings opened on
	-- Windows > Bags
	local settings, gear = W.PlateButton(f, 28, 26, 16, AREA, SETTINGS_SCRIPTS)
	gear:SetAtlas((select(2, Look.Art("optionsGear"))))
	gear:SetDesaturated(true)   -- (in the text colour, as Discard's bin)
	win.settings = settings
	-- the money
	local money = CreateFrame("Frame", "MelloUIBagWindowMoney", f, "SmallMoneyFrameTemplate")
	money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -G.SIDE + 4, 12)
	win.money = money
	-- the headings (a trade good type's with its first show)
	for _, kind in ipairs(KINDS) do
		Heading(kind.key, kind.name)
	end
	win.sell = W.Button(content, TEXT.sell, 74, win.shell, { height = 17, onClick = SellClick })
	win.sell:SetFrameLevel(headings.junk:GetFrameLevel() + 2)
	win.sell:Hide()
	W.Dress(f, win.shell)
	-- the look switched: the slots dressed as the game's bag slots, or left in the game's look; the money's ink with
	-- the page (the Window Background is the kit look's)
	win.shell:OnKit(function(_, on)
		if on then
			undressed = #made
			Dress()
		end
		InkMoney()
	end)
	return f
end

-- the window's place: the game's bags' own corner (bottom right, over the action bars)
function M.Home(frame)
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 120)
end

function M:Open()
	local f = win.frame or Build()
	if f:IsShown() then
		self:Layout()
		return
	end
	f:Show()
end

--------------------------------------------------------------------------------
-- Events: only while the window shows
--------------------------------------------------------------------------------

local events = nil
local LAYOUT_EVENTS = { "BAG_UPDATE_DELAYED", "BAG_NEW_ITEMS_UPDATED", "QUEST_ACCEPTED", "UNIT_QUEST_LOG_CHANGED",
	"MERCHANT_SHOW", "MERCHANT_CLOSED", "GET_ITEM_INFO_RECEIVED" }
local MARK_EVENTS = { "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "INVENTORY_SEARCH_UPDATE" }

local relay = false
function LayoutSoon()
	if relay then
		return
	end
	relay = true
	C_Timer.After(0, function()
		relay = false
		if win.frame and win.frame:IsShown() then
			M:Layout()
		end
	end)
end

local OnEvent = Shared("OnEvent of the bag window", function(_, event, arg1)
	if event == "PLAYER_REGEN_ENABLED" then
		if M.pending then
			M.pending = nil
			M:Apply()
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if junkWorth == nil then
			LayoutSoon()
		end
	elseif event == "UNIT_QUEST_LOG_CHANGED" then
		if arg1 == "player" then
			LayoutSoon()
		end
	elseif event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_COOLDOWN" or event == "INVENTORY_SEARCH_UPDATE" then
		Refresh()
	else
		LayoutSoon()
	end
end, "event")

function Listen(on)
	if not events then
		events = CreateFrame("Frame")
		Perf.SetScript(events, "OnEvent", OnEvent)
	end
	for _, list in ipairs({ LAYOUT_EVENTS, MARK_EVENTS }) do
		for _, ev in ipairs(list) do
			if on then
				events:RegisterEvent(ev)
			else
				events:UnregisterEvent(ev)
			end
		end
	end
end

-- on or off as the module is (a change in combat waits for the combat's end)
function M:Apply()
	if not events then
		events = CreateFrame("Frame")
		Perf.SetScript(events, "OnEvent", OnEvent)
	end
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	if self.isEnabled then
		Hook()
		Capture()
	else
		Release()
	end
end

-- (the bag slots' dock and others ask whether the window shows)
function ns.BagWindowShown()
	local f = win.frame
	return (M.isEnabled and captured and f and f:IsShown()) and f or nil
end

function M:OnEnable(db)
	self.db = db
	self:Apply()
end

function M:OnDisable()
	self:Apply()
end

-- a setting changed: laid out again while the window shows (else at its next open)
function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "recentFor" then
		-- (Recent starts afresh: an item held under the old setting had no
		-- clock of For 5 Minutes, and stayed for ever)
		wipe(heldID)
		wipe(heldAt)
	end
	if win.frame and win.frame:IsShown() then
		self:Layout()
	end
end

-- (the tests)
M.win = win
M.Capture, M.Release, M.GameOpen = Capture, Release, GameOpen
M.trades = trades
