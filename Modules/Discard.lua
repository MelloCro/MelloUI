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
--   (2.1.50; Nixxen, 2026-11-12: "an 'ok to throw away consumables', but keep a whitelist of items we want to keep",
--   the user's picks of BuildData/output/restock_discard_sketch)
--   consumables  with Consumables Too on (off by default): food, drink, potions and the other consumables may go
--                too, grey or white, still never what a Restock line keeps (its item; of a family -- drink, food,
--                ammunition -- the best level in the bags, the older ones may go; a pet's diet)
--   kept         never what this character keeps: a right-click on the button keeps the item it would take (its
--                tooltip says so, then names the next one); the Restock List's Never Discard page lets one go
--   auction      (2.1.50; Nixxen: "AHLedger") with AHledger installed and on (the Addons page's switch), an item
--                is worth its auction median when that is more than the vendor's price: the cheapest goes first by
--                that worth, and Never Throw Away Items Worth counts it; at a vendor Sell skips what the auction
--                pays clearly more for (SELL_MARGIN, after the house's cut). Its prices show in the tooltip only,
--                with the credit AHledger asks for (and "the copy it ships with" while it has no synced prices)
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
	-- (no group: its rows sit on the Windows page, the bag and loot windows' Behaviour)
	enabledByDefault = true,
	defaults = { bagButton = true, lootButton = true, keepWorth = 100, consumables = false },
	options = {
		{ type = "toggle", key = "bagButton", name = "Discard Button",
		  desc = "A button on the bag window that throws away your cheapest junk item (sells it at a vendor). Never consumables, materials, quest items or your Restock list. A white item asks first." },
		{ type = "toggle", key = "consumables", name = "Consumables Too", new = "2.1.50",
		  desc = "Food, drink, potions and other consumables can be thrown away too, the cheapest first. Never what your Restock list keeps (of its drink, food or ammo the best you carry) or what you keep with a right-click on the Discard button." },
		{ type = "toggle", key = "lootButton", name = "Discard Button On Loot",
		  desc = "The same button on the loot window. It only throws something away for loot worth more." },
		{ type = "slider", key = "keepWorth", name = "Never Throw Away Items Worth", min = 1, max = 1000, step = 1,
		  desc = "Stacks worth this many silver or more are never thrown away (they can still be sold)." },
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
local MISC, JUNK = 15, 0                  -- a white miscellaneous item: its junk only
local CONSUMABLE = 0                      -- (2.1.50) the class Consumables Too lets go

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

-- (2.1.50) AHledger's auction median of one (copper), nil without it (not installed, its switch off on the Addons
-- page, no price on this market). Its API (AHledgerAPI, from its 0.9.8) never raises; guarded all the same
local AUCTION_CUT = 0.95   -- the auction house keeps 5% of a sale
local SELL_MARGIN = 1.5    -- at a vendor, kept when the auction (after its cut) pays at least this much more
local function Auction(itemID)
	local I = MelloUI.Integrations
	if I and I.Use and not I.Use("AHledger") then
		return nil
	end
	local api = rawget(_G, "AHledgerAPI")
	if type(api) ~= "table" or type(api.GetMedian) ~= "function" then
		return nil
	end
	local median = Num((Ask(api.GetMedian, itemID)))
	return median and median > 0 and median or nil
end

-- the credit line AHledger asks for wherever its prices show; while it runs on the prices it ships with (no sync), it
-- says so, as AHledger does
local function Credit(itemID)
	local api = rawget(_G, "AHledgerAPI")
	local text = type(api) == "table" and type(api.CREDIT) == "string" and api.CREDIT or "Prices from AHledger (ahledger.com)"
	local p = type(api) == "table" and Ask(api.GetPrice, itemID)
	if type(p) == "table" and p.snapshot == true then
		text = text .. ", the copy it ships with"
	end
	return text
end

-- an item line of the Restock list (its families -- food, drink, ammunition,
-- reagents -- are kept by their class already)
local function OnRestockList(itemID)
	local restock = MelloUI:GetModule("Restock")
	if not (restock and restock.isEnabled and restock.Entries and restock.Entry) then
		return false
	end
	-- (2.1.50) a line that counts it: its own, or its family's (a drink while the list keeps drink)
	if restock.Counts then
		local ok, counts = pcall(restock.Counts, restock, itemID)
		if ok and counts then
			return true
		end
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
function M.KindAllowed(quality, classID, subclassID, consumables)
	if quality ~= 0 and quality ~= 1 then
		return false
	end
	-- (2.1.50) Consumables Too: a consumable, grey or white
	if consumables and classID == CONSUMABLE then
		return true
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

-- (2.1.50) what this character keeps: never thrown away nor sold. Kept as text, the item ids (the setting
-- "keep_<guid>"); the Restock List's Never Discard page shows them
local keep = { text = false, ids = {}, guid = false, key = nil }

local function KeepKey()
	local guid = MelloUI.Safe.Text((Ask(UnitGUID, "player")))
	if not guid then
		return nil
	end
	if keep.guid ~= guid then
		keep.guid, keep.key = guid, "keep_" .. guid:gsub("[^%w]", "")
	end
	return keep.key
end

function M.Kept(itemID)
	local key = KeepKey()
	local text = key and M.db and MelloUI.Safe.Text(M.db[key]) or ""
	if text ~= keep.text then
		keep.text = text
		for k in pairs(keep.ids) do
			keep.ids[k] = nil
		end
		for w in text:gmatch("%d+") do
			keep.ids[tonumber(w)] = true
		end
	end
	return itemID ~= nil and keep.ids[itemID] == true
end

-- the kept items, into out (by id)
function M.KeepList(out)
	M.Kept(nil)
	for k in pairs(keep.ids) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

function M.Keep(itemID, on)
	local key = KeepKey()
	if not (key and M.db and itemID) then
		return
	end
	M.Kept(itemID)
	keep.ids[itemID] = on and true or nil
	local parts = {}
	for k in pairs(keep.ids) do
		parts[#parts + 1] = k
	end
	table.sort(parts)
	local text = table.concat(parts, " ")
	keep.text = text
	MelloUI:NotifySettingChanged("Discard", key, text)
	local restock = MelloUI:GetModule("Restock")
	if restock and restock.KeepChanged then
		restock:KeepChanged()
	end
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
	if not (price and price > 0) or not M.KindAllowed(quality, classID, subclassID, M.db and M.db.consumables) then
		return nil
	end
	if M.Kept(itemID) then
		return nil
	end
	local quest = Ask(C.GetContainerItemQuestInfo, bag, slot)
	if type(quest) == "table" and (Value(quest.isQuestItem) == true or Num(quest.questID)) then
		return nil
	end
	if OnRestockList(itemID) then
		return nil
	end
	-- (2.1.50) its worth: the auction's median when that is more (AHledger), else the vendor's; vendor: what a sale pays
	local auction = Auction(itemID)
	local unit = (auction and auction > price) and auction or price
	return { bag = bag, slot = slot, itemID = itemID, count = count, quality = quality, price = price, auction = auction,
		value = unit * count, vendor = price * count, link = Value(info.hyperlink), icon = Num(info.iconFileID) }
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
-- their value, for the message; (2.1.50) selling: the cheapest of those
-- held back for the auction's price and how many (AHledger)
function M.Cheapest(selling)
	local limit = ((Num(M.db and M.db.keepWorth) or 100) * 100)
	local best, valuable, held, nheld = nil, 0, nil, 0
	EachSlot(function(bag, slot)
		local c = M.Candidate(bag, slot)
		if c then
			if selling and c.auction and c.auction * AUCTION_CUT >= SELL_MARGIN * c.price then
				nheld = nheld + 1
				if not held or Better(c, held) then
					held = c
				end
			elseif not selling and c.value >= limit then
				valuable = valuable + 1
			elseif not best or Better(c, best) then
				best = c
			end
		end
	end)
	return best, valuable, held, nheld
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
		Say("Sold %s%s for %s.", name, c.count > 1 and (" x" .. c.count) or "", Money(c.vendor or c.value))
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
	Say("Threw away %s%s (worth %s).", name, c.count > 1 and (" x" .. c.count) or "", Money(c.vendor or c.value))
	return true
end

-- the button's click: from the bags ("bags") or the loot window ("loot")
function M.Click(source)
	local selling = AtVendor()
	local c, valuable, _, nheld = M.Cheapest(selling)
	if not c then
		if selling and nheld > 0 then
			Say("Discard: nothing to sell -- what is left sells for more at the auction house (AHledger's prices).")
		elseif valuable > 0 then
			Say("Discard: nothing cheap enough to throw away -- your junk is worth %s or more a stack (Never Throw Away Items Worth).",
				Money((Num(M.db and M.db.keepWorth) or 100) * 100))
		elseif M.db and M.db.consumables then
			-- (2.1.50) with Consumables Too on, food and potions may go: the line no longer says they never do
			Say("Discard: nothing to throw away (grey and white junk and consumables go, never materials, quest items or what you keep).")
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
				Money(c.vendor or c.value)),
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
-- pick A of BuildData/output/discard_sketch, 2026-10-03; onelook stage E):
-- the bin glyph on the controls' icon plate (W.PlateButton: W.FlatOver's
-- 'button'), whatever the window wears. The places: on the bag window left
-- of Sort, the search box shorter by the button's room while it shows
-- (pick 1); on the loot window under the loot list, at its bottom right.
--------------------------------------------------------------------------------

local buttons = {}   -- [source] = the button
local SIZE_W, SIZE_H = 28, 26     -- the Sort button's own size (ContainerFrame.xml)
local GLYPH = 15
local GAP = 2                     -- between the button and Sort
local SHORTER = SIZE_W + GAP      -- the search box's room given up (30)
local MIN_SEARCH = 40             -- the search box never narrower
local AREA = { bags = "backpack", loot = "loot", kinds = "backpack" }

-- (2.1.50) an item's name out of its link
local function NameOf(c)
	return c.link and c.link:match("%[(.-)%]") or ("item " .. c.itemID)
end

-- (2.1.50, the user's picks T1-T3 of restock_discard_sketch) the tooltip: the item and its worth (with AHledger, its
-- auction worth and the vendor's beside it), what Sell holds back for the auction, the right-click, the credit
local function Tip(self)
	local selling = AtVendor()
	local c, _, held, nheld = M.Cheapest(selling)
	local P = MelloUI.Palette.text
	local tr, tg, tb = P[1], P[2], P[3]
	local credit = nil
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(selling and "Sell Cheapest Junk" or "Discard Cheapest Junk", 1, 1, 1)
	if c then
		local count = c.count > 1 and (" x" .. c.count) or ""
		if not selling and c.auction and c.auction > c.price then
			GameTooltip:AddLine(string.format("%s%s, %s at auction (vendor %s)", c.link or "?", count, Money(c.value),
				Money(c.vendor)), 1, 1, 1)
			credit = c
		else
			GameTooltip:AddLine(string.format("%s%s, %s", c.link or "?", count, Money(c.vendor or c.value)), 1, 1, 1)
		end
	else
		GameTooltip:AddLine("Nothing to throw away.", 0.7, 0.7, 0.7)
	end
	if held then
		local more = nheld > 1 and string.format(" and %d more", nheld - 1) or ""
		GameTooltip:AddLine(string.format("Kept, worth more at auction: %s%s (%s)%s", NameOf(held),
			held.count > 1 and (" x" .. held.count) or "", Money(held.auction * held.count), more), tr, tg, tb, true)
		credit = credit or held
	end
	if c then
		-- (2.1.50) the right-click: in the game's green of a use line
		local g = rawget(_G, "GREEN_FONT_COLOR")
		GameTooltip:AddLine("Right-click: always keep " .. NameOf(c), g and g.r or 0, g and g.g or 1, g and g.b or 0)
	end
	if credit then
		GameTooltip:AddLine(Credit(credit.itemID), tr, tg, tb)
	end
	if self.source == "loot" and not selling then
		GameTooltip:AddLine("Only when the loot is worth more.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end

-- (2.1.50) the right-click: the item the button would take kept from now on; its tooltip names the next one
function M.KeepClick(self)
	local c = M.Cheapest(AtVendor())
	if not c then
		return
	end
	M.Keep(c.itemID, true)
	MelloUI:PlayUISound("check_on")
	Say("Discard: %s is kept now (the Restock List's Never Discard page lets it go).", c.link or ("item " .. c.itemID))
	if self and GameTooltip:IsOwned(self) then
		Tip(self)
	end
end

-- (the scripts handed in first: a SetScript after the plate's hooks would drop them)
local BUTTON_SCRIPTS = {
	OnClick = function(self, button)
		if button == "RightButton" then
			M.KeepClick(self)
			return
		end
		M.Click(self.source)
	end,
	OnEnter = Tip,
	OnLeave = function()
		GameTooltip:Hide()
	end,
}

local function MakeButton(source, parent)
	local W = MelloUI.Widgets
	-- the controls' icon plate under the bin, whatever the window wears
	-- (W.PlateButton: the bag window's Settings is the same button)
	local b, glyph = W.PlateButton(parent, SIZE_W, SIZE_H, GLYPH, AREA[source], BUTTON_SCRIPTS, "bin")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")   -- (2.1.50: the right-click keeps)
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
