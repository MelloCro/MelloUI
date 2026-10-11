--------------------------------------------------------------------------------
-- MelloUI - Discard
--
-- A button on the bag window and on the loot window that frees a bag slot:
-- it throws away the bag item worth least (a player's request, 2026-10-03,
-- with the user's rules). At a vendor it sells that item instead (nothing
-- lost: the buyback has it).
--
-- What may go (every rule must hold):
--   quality      poor (grey) or common (white) only
--   gear         weapons and armour only when grey (white gear is kept:
--                worn, in a set, an upgrade, a profession's tool -- the
--                mining pick, the skinning knife, the fishing pole)
--   never        consumables (food, drink, potions, elixirs, scrolls,
--                bandages, conjured food and gems), bags, gems, reagents,
--                ammunition, trade goods (crafting materials), recipes,
--                quivers, quest items, keys, profession items; a white
--                miscellaneous item unless it is junk (mounts, pets,
--                holiday items and other odds kept); an item that starts or
--                is part of a quest; a lockbox or anything holding loot; a
--                locked item; anything the vendor gives nothing for (the
--                hearthstone, quest starters, special items); an item line
--                on the Restock list
--   valuable     never thrown away (user: "throwing away a valuable item
--                should never be the case"): a stack worth more than Never
--                Throw Away Items Worth (1 gold by default) is kept --
--                selling it at a vendor is fine (nothing is lost)
-- Which one: the stack worth least (the vendor's price times the stack);
-- a tie: grey before white, then the first in the bags.
-- Asking first: a white item is named with its value and only goes on
-- Discard (MelloUI:Confirm); a grey one goes on the click.
-- The loot window's button (always there): it frees a slot only when
-- something on the loot is worth more than what it would throw away (a
-- quest item or one the vendor gives nothing for counts as worth more);
-- else it says so and keeps the bags as they are.
-- Deleting needs a click: the game deletes an item only from a hardware
-- event (DeleteCursorItem: HasRestrictions), so it happens in the button's
-- own click or the question's Discard click. The item is checked again
-- right before (still in its slot, the same stack); a cursor already
-- holding something stops it; an item the game would not let go is put back.
-- Nothing at login: the buttons are made with their window's first show.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Discard")

local Num = MelloUI.Safe.Number
local Value = MelloUI.Safe.Value

local M = MelloUI:RegisterModule("Discard", {
	title = "Discard",
	desc = "A button on the bag and loot windows that throws away your cheapest grey or white junk to free a slot (sells it at a vendor).",
	icon = "Interface\\Icons\\INV_Misc_Bag_10",
	flavour = "Full bags? The cheapest junk makes room, never anything worth keeping.",
	role = "feature",
	-- (no group: its rows sit on the Windows page, the bag and loot windows' Behaviour)
	-- (not on the installer's Features step: its two columns are full, as for
	-- the Swing Timers; on by default, its switches on the Windows page)
	installer = false,
	enabledByDefault = true,
	defaults = { bagButton = true, lootButton = true, keepWorth = 100 },
	options = {
		{ type = "toggle", key = "bagButton", name = "Discard Button",
		  desc = "A button on the bag window that frees a slot: it throws away the grey or white junk item worth least (at a vendor it sells it). Never food, drink, potions, scrolls, conjured items, crafting materials, quest items, reagents, ammunition, keys, white gear or anything on your Restock list. A white item asks first." },
		{ type = "toggle", key = "lootButton", name = "Discard Button on Loot",
		  desc = "The same button on the loot window. It frees a slot only when something you are looting is worth more than what it would throw away." },
		{ type = "slider", key = "keepWorth", name = "Never Throw Away Items Worth", min = 1, max = 1000, step = 1,
		  desc = "In silver: a stack worth this or more is never thrown away (selling it at a vendor still is). 100 silver = 1 gold." },
	},
})

-- the item classes that never go (Enum.ItemClass numbers: this client's)
local KEEP_CLASS = {
	[0] = true,    -- consumables: food, drink, potions, elixirs, scrolls, bandages, conjured items
	[1] = true,    -- containers (bags)
	[3] = true,    -- gems
	[5] = true,    -- reagents
	[6] = true,    -- projectiles (ammunition)
	[7] = true,    -- trade goods (crafting materials)
	[9] = true,    -- recipes
	[11] = true,   -- quivers
	[12] = true,   -- quest items
	[13] = true,   -- keys
	[19] = true,   -- profession items
}
local GEAR = { [2] = true, [4] = true }   -- weapons, armour: grey only
local MISC, JUNK = 15, 0                  -- a white miscellaneous item: its junk only

M.KEEP_CLASS, M.GEAR = KEEP_CLASS, GEAR   -- (the tests)

--------------------------------------------------------------------------------
-- Reads (each guarded: a secret or refused answer is nil)
--------------------------------------------------------------------------------

local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h, i, j, k, l, n = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h, i, j, k, l, n
	end
end

-- the vendor's price of one, the class and subclass
local function ItemFacts(itemID)
	local C = C_Item
	local _, _, _, _, _, _, _, _, _, _, price, classID, subclassID = Ask(C and C.GetItemInfo or GetItemInfo, itemID)
	return Num(price), Num(classID), Num(subclassID)
end

-- an item line of the Restock list (its families -- food, drink, ammunition,
-- reagents -- are kept by their class already)
local function OnRestockList(itemID)
	local restock = MelloUI:GetModule("Restock")
	if not (restock and restock.isEnabled and restock.Entries and restock.Entry) then
		return false
	end
	local ok, n = pcall(restock.Entries, restock)
	for i = 1, (ok and Num(n)) or 0 do
		local okE, key = pcall(restock.Entry, restock, i)
		if okE and Num(key) == itemID then
			return true
		end
	end
	return false
end

-- whether the rules let this kind of item go: quality, class, subclass
function M.KindAllowed(quality, classID, subclassID)
	if quality ~= 0 and quality ~= 1 then
		return false
	end
	if classID == nil or KEEP_CLASS[classID] then
		return false
	end
	if quality == 1 then
		-- white: only miscellaneous junk (white gear, mounts, pets, holiday
		-- items and every other white kind kept)
		return classID == MISC and subclassID == JUNK
	end
	return true
end

-- one bag slot as a candidate, or nil when it must stay
function M.Candidate(bag, slot)
	local C = C_Container
	if not C then
		return nil
	end
	local info = Ask(C.GetContainerItemInfo, bag, slot)
	if type(info) ~= "table" then
		return nil
	end
	local itemID, count, quality = Num(info.itemID), Num(info.stackCount), Num(info.quality)
	if not (itemID and count and quality) then
		return nil
	end
	if Value(info.isLocked) == true or Value(info.hasLoot) == true or Value(info.hasNoValue) == true then
		return nil
	end
	local price, classID, subclassID = ItemFacts(itemID)
	if not (price and price > 0) or not M.KindAllowed(quality, classID, subclassID) then
		return nil
	end
	local quest = Ask(C.GetContainerItemQuestInfo, bag, slot)
	if type(quest) == "table" and (Value(quest.isQuestItem) == true or Num(quest.questID)) then
		return nil
	end
	if OnRestockList(itemID) then
		return nil
	end
	return { bag = bag, slot = slot, itemID = itemID, count = count, quality = quality, price = price,
		value = price * count, link = Value(info.hyperlink), icon = Num(info.iconFileID) }
end

-- the bags' slots: the backpack and the four bags
local function EachSlot(fn)
	local C = C_Container
	local last = Num(rawget(_G, "NUM_BAG_SLOTS")) or 4
	for bag = 0, last do
		local n = Num(Ask(C and C.GetContainerNumSlots, bag)) or 0
		for slot = 1, n do
			fn(bag, slot)
		end
	end
end

local function Better(a, b)
	if a.value ~= b.value then
		return a.value < b.value
	end
	if a.quality ~= b.quality then
		return a.quality < b.quality
	end
	if a.bag ~= b.bag then
		return a.bag < b.bag
	end
	return a.slot < b.slot
end

-- the cheapest candidate; selling: whatever its value, else under the limit
-- (a valuable stack is never thrown away). Also how many were kept for
-- their value, for the message.
function M.Cheapest(selling)
	local limit = ((Num(M.db and M.db.keepWorth) or 100) * 100)
	local best, valuable = nil, 0
	EachSlot(function(bag, slot)
		local c = M.Candidate(bag, slot)
		if c then
			if not selling and c.value >= limit then
				valuable = valuable + 1
			elseif not best or Better(c, best) then
				best = c
			end
		end
	end)
	return best, valuable
end

-- what the loot window holds worth most: an item's vendor value times its
-- count; a quest item or one the vendor gives nothing for counts as worth
-- more than anything (math.huge). nil: no item on the window (money only)
function M.BestLoot()
	local n = Num(Ask(GetNumLootItems)) or 0
	local best = nil
	for i = 1, n do
		local kind = Num(Ask(GetLootSlotType, i))
		local slotItem = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1
		if kind == slotItem then
			local _, _, quantity, _, _, _, isQuestItem = Ask(GetLootSlotInfo, i)
			local link = Value((Ask(GetLootSlotLink, i)))
			local worth
			if Value(isQuestItem) == true then
				worth = math.huge
			else
				local price = link and ItemFacts(link)
				worth = (price and price > 0) and price * (Num(quantity) or 1) or math.huge
			end
			if not best or worth > best then
				best = worth
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- The act
--------------------------------------------------------------------------------

local function Money(copper)
	local f = rawget(_G, "GetMoneyString") or rawget(_G, "GetCoinTextureString")
	local ok, s = pcall(f, copper)
	return ok and s or tostring(copper)
end

local function Say(fmt, ...)
	MelloUI:Print(fmt, ...)
end

local function AtVendor()
	local f = rawget(_G, "MerchantFrame")
	return f and Value(f:IsShown()) == true or false
end

-- the slot still holds this candidate (the same item, the same stack)
local function Still(c)
	local now = M.Candidate(c.bag, c.slot)
	return now and now.itemID == c.itemID and now.count == c.count
end

-- sells or throws away the candidate; from a click (hardware event) only
function M.Act(c, selling)
	if not Still(c) then
		Say("Discard: your bags changed; nothing was thrown away.")
		return false
	end
	local name = c.link or ("item " .. c.itemID)
	local C = C_Container
	if selling then
		Ask(C.UseContainerItem, c.bag, c.slot)
		Say("Sold %s%s for %s.", name, c.count > 1 and (" x" .. c.count) or "", Money(c.value))
		return true
	end
	if Ask(GetCursorInfo) ~= nil then
		Say("Discard: you are holding something on the cursor; put it down first.")
		return false
	end
	Ask(C.PickupContainerItem, c.bag, c.slot)
	local kind, id = Ask(GetCursorInfo)
	if kind ~= "item" or Num(id) ~= c.itemID then
		Ask(ClearCursor)
		Say("Discard: the item could not be picked up; nothing was thrown away.")
		return false
	end
	Ask(DeleteCursorItem)
	if Ask(GetCursorInfo) ~= nil then
		-- (the game would not let it go: back to its slot)
		Ask(ClearCursor)
		Say("Discard: the game did not let MelloUI throw %s away; it is back in your bags.", name)
		return false
	end
	Say("Threw away %s%s (worth %s).", name, c.count > 1 and (" x" .. c.count) or "", Money(c.value))
	return true
end

-- the button's click: from the bags ("bags") or the loot window ("loot")
function M.Click(source)
	local selling = AtVendor()
	local c, valuable = M.Cheapest(selling)
	if not c then
		if valuable > 0 then
			Say("Discard: nothing cheap enough to throw away -- your junk is worth %s or more a stack (Never Throw Away Items Worth).",
				Money((Num(M.db and M.db.keepWorth) or 100) * 100))
		else
			Say("Discard: nothing to throw away (only grey and white junk goes, never food, potions, materials or quest items).")
		end
		return
	end
	if source == "loot" and not selling then
		local best = M.BestLoot()
		if not best then
			Say("Discard: nothing on the loot window needs the room.")
			return
		end
		if best <= c.value then
			Say("Discard: the loot is worth less than your cheapest junk, %s (%s); your bags are kept as they are.",
				c.link or "?", Money(c.value))
			return
		end
	end
	if c.quality >= 1 and not selling then
		MelloUI:Confirm({
			text = string.format("Throw away %s%s (worth %s)?", c.link or "this item", c.count > 1 and (" x" .. c.count) or "",
				Money(c.value)),
			accept = "Discard",
			onAccept = function()
				M.Act(c, false)
			end,
		})
		return
	end
	M.Act(c, selling)
end

--------------------------------------------------------------------------------
-- The buttons (made with their window's first show). The look (the user's
-- pick A of BuildData/output/discard_sketch, 2026-10-03): the bin glyph on
-- the Sort button's plate -- the kit's cog plate while the window wears the
-- kit (the area "backpack" / "loot"), the game's own round column button
-- (chatframe-button-up) without it (Look.ColumnButton). The places: on the
-- bag window left of Sort, the search box shorter by the button's room
-- while it shows (pick 1); on the loot window under the loot list, at its
-- bottom right.
--------------------------------------------------------------------------------

local buttons = {}   -- [source] = the button
local SIZE_W, SIZE_H = 28, 26     -- the Sort button's own size (ContainerFrame.xml)
local GLYPH = 15
local GAP = 2                     -- between the button and Sort
local SHORTER = SIZE_W + GAP      -- the search box's room given up (30)
local MIN_SEARCH = 40             -- the search box never narrower
local AREA = { bags = "backpack", loot = "loot", kinds = "backpack" }

local function Tip(self)
	local selling = AtVendor()
	local c = M.Cheapest(selling)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(selling and "Sell Cheapest Junk" or "Discard Cheapest Junk", 1, 1, 1)
	if c then
		GameTooltip:AddLine(string.format("%s%s, %s", c.link or "?", c.count > 1 and (" x" .. c.count) or "", Money(c.value)), 1, 1, 1)
	else
		GameTooltip:AddLine("Nothing to throw away.", 0.7, 0.7, 0.7)
	end
	if self.source == "loot" and not selling then
		GameTooltip:AddLine("Only when the loot is worth more.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end

-- (the scripts handed in first: a SetScript after the plate's hooks would drop them)
local BUTTON_SCRIPTS = {
	OnClick = function(self)
		M.Click(self.source)
	end,
	OnEnter = Tip,
	OnLeave = function()
		GameTooltip:Hide()
	end,
}

local function MakeButton(source, parent)
	local W = MelloUI.Widgets
	-- the kit's cog plate, as the Sort button's, its opening black under the
	-- bin (W.PlateButton: the bag window's Settings is the same button)
	local b, glyph = W.PlateButton(parent, SIZE_W, SIZE_H, GLYPH, AREA[source], BUTTON_SCRIPTS)
	b.source = source
	W.Glyph(glyph, "bin")
	buttons[source] = b
	return b
end

-- the bag window: a child of the Sort button (it goes where Sort goes: the
-- backpack's or the combined bags' window; hidden with it in gamepad mode)
local function BagButton()
	local sort = rawget(_G, "BagItemAutoSortButton")
	if buttons.bags or not sort then
		return buttons.bags
	end
	local b = MakeButton("bags", sort)
	b:SetPoint("RIGHT", sort, "LEFT", -GAP, 0)
	return b
end

-- the loot window: under the loot list, at the window's bottom right -- laid on every show: with the double rail laid
-- round the window (0.20.1, Kit:SkinWindowShell's `outward`, Kit.outwardOf) as far out and down as the rail goes
local function LootButton()
	local loot = rawget(_G, "LootFrame")
	if not loot then
		return buttons.loot
	end
	local b = buttons.loot or MakeButton("loot", loot)
	local Kit = MelloUI.Kit
	local ow = Kit and Kit.outwardOf and Kit.outwardOf[loot]
	b:ClearAllPoints()
	b:SetPoint("TOPRIGHT", loot, "BOTTOMRIGHT", -6 + (ow and ow.r or 0), -2 - (ow and ow.b or 0))
	return b
end

-- The search box: the game sets its width with its place for the window
-- (SetSearchBoxPoint, on each UpdateSearchBox: 96 on the backpack, 330 on
-- the combined bags); kept here, and the box shorter by the button's room
-- while the button shows. Nothing is written onto the game's frames.
local search = { width = nil }

local function FitSearch()
	local box = rawget(_G, "BagItemSearchBox")
	local w = search.width
	if not (box and w) then
		return
	end
	local on = buttons.bags and buttons.bags:IsShown()
	box:SetWidth(on and math.max(w - SHORTER, MIN_SEARCH) or w)
end
M.FitSearch = FitSearch   -- (the tests)

local function OnSearchPoint(_, box)
	local w = Num(box and box.GetWidth and box:GetWidth())
	if w and w > 0 then
		search.width = w
	end
	FitSearch()
end

local function Sync()
	local on = M.isEnabled and M.db
	if buttons.bags then
		buttons.bags:SetShown(on and M.db.bagButton and true or false)
	end
	if buttons.kinds then
		buttons.kinds:SetShown(on and M.db.bagButton and true or false)
	end
	if buttons.loot then
		buttons.loot:SetShown(on and M.db.lootButton and true or false)
	end
	FitSearch()
end

-- The bag window by kind (Modules/BagWindow.lua, 0.19.0) asks for the same
-- button for its search row (that window places it); shown by the same
-- switch as the bag window's
function M:KindWindowButton(parent)
	if not buttons.kinds then
		MakeButton("kinds", parent)
	end
	Sync()
	return buttons.kinds
end

local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	local function OnBags()
		if M.isEnabled and M.db.bagButton then
			BagButton()
			Sync()
		end
	end
	for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
		local f = rawget(_G, name)
		if f and f.HookScript then
			Perf.HookScript(f, "OnShow", OnBags)
		end
		if f and type(f.SetSearchBoxPoint) == "function" then
			Perf.hooksecurefunc(f, "SetSearchBoxPoint", OnSearchPoint)
		end
	end
	local loot = rawget(_G, "LootFrame")
	if loot and loot.HookScript then
		Perf.HookScript(loot, "OnShow", function()
			if M.isEnabled and M.db.lootButton then
				LootButton()
				Sync()
				-- (once more a frame later: the loot window's look may be dressed after this, on the same show)
				Perf.C_Timer.After(0, LootButton)
			end
		end)
	end
end

function M:OnEnable(db)
	self.db = db
	Hook()
	Sync()
end

function M:OnDisable()
	Sync()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "bagButton" and value then
		BagButton()
	elseif key == "lootButton" and value then
		LootButton()
	end
	Sync()
end
