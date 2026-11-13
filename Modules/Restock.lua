--------------------------------------------------------------------------------
-- MelloUI - Restock
--
-- (user, 2026-09-26: the fourth user of the reminder widget, "the Restock
-- should be shown the whole time until the player either restocks or leaves
-- the safe area", and the picks made with it)
--
-- Keeps what a character lives on in its bags: drink, food, arrows or
-- bullets and class reagents.
--   The list     per character (the setting list_<GUID>, a keep key: never
--                in a profile, never wiped by one), "d:20 f:20 a:1000
--                17031:10": a family (d drink, f food, a arrows, b bullets,
--                r class reagents) or an item id, and how many to keep. A
--                character that never changed it has its class's suggestion
--                (Suggested: drink for the classes with mana, food for all,
--                a hunter's ammunition by its ranged weapon, the class
--                reagents with the levels they are used at). Edited in the
--                small Restock List window (its own window, opened from the
--                Reminders page, the shop's list and /restock), where an
--                item dropped from the bags or a shop is added.
--   Counting     what is in the bags, on BAG_UPDATE_DELAYED (registered only
--                while the list has a line), on the next frame, never in
--                combat. A family counts every one of its items the
--                character can use: older, lower stock too (Ice Cold Milk
--                counts toward the water).
--   Low          a line below Remind Below (half, the user's pick) of its
--                amount. The reminder (MelloUI.Reminders, Core/Reminders.lua)
--                says which; in a rest area it stays until restocked or the
--                rest area is left (while the Reminders page's Stay Up In Rest
--                Areas is on: the one switch of all four reminders, the
--                widget's Rem:StayUp), and Not now hides it until a rest area
--                is entered again. Its click routes to the nearest shop that
--                sells what is low (Services:GoTo "vendor": the shipped
--                vendor rows, the shops seen here, the innkeeper when none is
--                known for drink or food).
--   The shop     at a merchant who sells something that is low, a list beside
--                the shop window: each item to buy back up to the FULL amount,
--                how many and its price, the total, and Buy / Not now.
--                Nothing is bought until Buy is clicked; then the purchases
--                go out one every 0.2 s and stop when the shop closes or the
--                game refuses one (no gold, bags full). Goods are chosen from
--                what the merchant lists (C_MerchantFrame.GetItemInfo), the
--                best the character can use.
--   Learning     every shop opened is remembered with what it sells of the
--                families and of the list (Services' learned places, kind
--                "vendor", written through Services:Learn): a shop seen
--                overrides the shipped row of the same name.
-- The reminder's switch is this module's own (0.16.0: the Reminders page's
-- Restock tab, "Restock List And Shop"; the old remind_restock is gone): the
-- spec is taken back while the module is off. The Reminders switch is over
-- it too: off, no reminder of Restock's either (RemActive).
-- Nothing at login but the event frame (two merchant events) and the
-- reminder's spec, a table handed to the widget at OnEnable (registered
-- later, the widget's login moment would wait 8 s more); the first count and
-- the bag events come 8 s into the world. The panel and the list window are
-- built on first use; a shop's first look is spread over frames (the plan,
-- then the panel, then the shop remembered). Colours by palette key
-- (W.Paint), text in Font Style (MelloUI:StyleFont), sounds through
-- MelloUI:PlayUISound. Every game value is tested for a secret first.
--
-- For the others (Services' Errands group, the reminder, tests):
--   MelloUI.Restock = M
--   M:GoTo() -> true | false, why          route to the nearest shop for it
--   M:LowCount() -> n
--   M:OpenList()                           the Restock List window
--   M:Entries() -> n; M:Entry(i) -> key, amount, have, low, active
--   M:Add(key[, amount]), M:Remove(i), M:SetAmount(i, amount), M:Reset()
--   M.buyingQuiet                          true from a Buy's second purchase
--                                          to its end (a buy sound: once)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Restock")
local C_Timer = Perf.C_Timer
local Shared = Perf.Shared
local IsSecret = MelloUI.Safe.IsSecret
local Plain = MelloUI.Safe.Value
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local W = MelloUI.Widgets

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local type, pcall, tonumber, tostring = type, pcall, tonumber, tostring

local M = MelloUI:RegisterModule("Restock", {
	title = "Restock",
	desc = "Keeps food, drink, ammo and reagents stocked: a reminder when low, and a shopping list at merchants.",
	icon = "Interface\\Icons\\INV_Drink_07",
	flavour = "Water, bread and arrows, topped up before they run out.",
	-- (no group: its rows sit on the Reminders page, Modules/Reminders.lua)
	keep = { "^list_", "listH" },   -- each character's own list (ListKey): never in a profile, never wiped by one;
	-- (2.1.37) the list window's height, the screen's
	enabledByDefault = true,
	defaults = {
		below = 0.5,
		shopPanel = true,
		listH = false,   -- (2.1.37) the list window's own height (its grip); false: the standard
	},
	-- (no header and no switch of its own for the reminder: the Reminders page
	-- lays these rows on its Restock tab, under this module's switch, which is
	-- the reminder's too)
	options = {
		{ type = "slider", key = "below", name = "Remind Below", min = 0.25, max = 0.75, step = 0.05, percent = true,
		  desc = "Reminds you when an item drops below this share of its amount." },
		{ type = "toggle", key = "shopPanel", name = "Shopping List At The Shop",
		  desc = "At a merchant, a shopping list of what you are low on. Nothing is bought until you click Buy." },
		{ type = "button", name = "Restock List", text = "Edit",
		  desc = "What to keep in your bags, and how many. Each character has its own list. /restock opens it too.",
		  onClick = function(module) module:OpenList() end },
	},
})
MelloUI.Restock = M
M.buyingQuiet = false   -- (read only: set by the purchases, below)

local REM_KEY = "restock"
local ICON = MelloUI.Widgets.IconPath("svc_vendor")   -- (0.25.0: the set's food vendor; the 1x tracking icon until then)
local URGENCY = 50        -- the widget's order (higher first): broken gear 100, Repair 40, Mail 20, Trainer 10
local READY_DELAY = 8     -- s into the world before the first count and the reminder (nothing in the login frames)
local MAX_ENTRIES = 40    -- lines on a list (2.1.18: 12 until the catalogue; each item its own line now)
local SHOP_ROWS = 16      -- purchases a shop visit plans (the shop panel's rows): the rest at the next one
local MAX_AMOUNT = 5000
local BUY_SPACING = 0.2   -- s between two purchases
local LOW_DEFAULT = 0.5   -- Remind Below: half (the user's pick)

-- the families: their names, the amount a new line keeps, and the list
-- window's slider (step, top)
local FAMILY = {
	d = { name = "Drink", word = "drink", amount = 20, step = 5, top = 100, range = "stack" },
	f = { name = "Food", word = "food", amount = 20, step = 5, top = 100, range = "stack" },
	a = { name = "Arrows", word = "arrows", amount = 1000, step = 200, top = 2000, range = "ammo" },
	b = { name = "Bullets", word = "bullets", amount = 1000, step = 200, top = 2000, range = "ammo" },
	r = { name = "Class reagents", word = "reagents", amount = 10, step = 1, top = 100, range = "item" },
}
-- (2.1.18; the user, 2026-11-08: "especially the hunters because their pets have diets", the pick "per diet") a pet's
-- diets as the data numbers them (item_template's FoodType): the family lines p1 .. p6, each counting every food of
-- its diet, raw meat and fish too, whatever pet is out
local DIETS = { "Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit" }
local DIET_KEY = {}   -- [diet] = its line's key, made once (a count makes no strings)
for i, name in ipairs(DIETS) do
	DIET_KEY[i] = "p" .. i
	FAMILY[DIET_KEY[i]] = { name = name, word = name:lower() .. " for your pet", amount = 20, step = 5, top = 100,
		range = "stack", diet = i }
end
-- the data's kinds: the families, p potions and bandages, e elixirs and flasks, o poisons, s scrolls (their own kind:
-- the user, 2026-11-08, "You have categorized Scrolls under Elixirs?")
local KIND_LETTERS = "dfabrpeos"

-- The class suggestions. Drink for the classes with mana, food for every
-- class, a hunter's ammunition (by the ranged weapon: a gun shoots bullets).
-- Class reagents: { item, the level it is first used at, the last level it
-- is used at (nil: from then on), how many }. A reagent line counts only in
-- its levels (Active): a druid's Maple Seed is Rebirth's until level 29.
-- Reagents that need a book learned first (Arcane Powder, the candles) are
-- left out; the list window adds them by a drop.
local DRINKERS = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true, SHAMAN = true, WARLOCK = true }
local REAGENTS = {
	MAGE = { { 17031, 20, nil, 10 }, { 17032, 40, nil, 10 } },                 -- Rune of Teleportation, Rune of Portals
	PALADIN = { { 17033, 30, nil, 5 }, { 21177, 52, nil, 100 } },              -- Symbol of Divinity, Symbol of Kings
	DRUID = { { 17034, 20, 29, 5 }, { 17035, 30, 39, 5 }, { 17036, 40, 49, 5 }, -- the Rebirth seeds, rank by rank
		{ 17037, 50, 59, 5 }, { 17038, 60, nil, 5 }, { 17021, 50, 59, 20 }, { 17026, 60, nil, 20 } },   -- Gift of the Wild
	SHAMAN = { { 17030, 30, nil, 5 } },                                         -- Ankh
	ROGUE = { { 5140, 22, nil, 10 } },                                          -- Flash Powder
	WARLOCK = { { 5565, 50, nil, 3 }, { 16583, 60, nil, 3 } },                  -- Infernal Stone, Demonic Figurine
}
local WINDOW = {}   -- [item] = { from, to }: a reagent's levels (built with the families)

--------------------------------------------------------------------------------
-- Reads (secret-safe: a secret or missing answer is nil)
--------------------------------------------------------------------------------

-- f(...)'s first two results, or nil when f is missing or raised
local function Ask(f, ...)
	if type(f) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(f, ...)
	if not ok then
		return nil
	end
	return a, b
end

local function PlayerLevel()
	return Num((Ask(UnitLevel, "player")))
end

-- the level to count and plan with: the last plain answer (a secret one
-- must not make older stock look unusable)
local lastLevel = { value = nil }
local function Level()
	local level = PlayerLevel()
	if level then
		lastLevel.value = level
	end
	return lastLevel.value or 1
end

local function PlayerClass()
	local _, token = Ask(UnitClass, "player")
	return Text(token)
end

local function Money()
	return Num((Ask(GetMoney)))
end

local function InCombat()
	return MelloUI.InCombat()
end

-- how many of an item are in the bags
local function ItemCount(id)
	local C = C_Item
	local n
	if C and C.GetItemCount then
		n = Ask(C.GetItemCount, id)
	else
		n = Ask(GetItemCount, id)
	end
	return Num(n) or 0
end

local names = {}   -- [item] = its name, once the client has it
local function ItemName(id)
	local name = names[id]
	if name then
		return name
	end
	local C = C_Item
	if C and C.GetItemNameByID then
		name = Text((Ask(C.GetItemNameByID, id)))
	end
	if not name and GetItemInfo then
		name = Text((Ask(GetItemInfo, id)))
	end
	if name then
		names[id] = name
	elseif C and C.RequestLoadItemDataByID then
		Ask(C.RequestLoadItemDataByID, id)   -- (asked for: named the next time)
	end
	return name
end

local function ItemIcon(id)
	local C = C_Item
	if C and C.GetItemIconByID then
		local icon = Plain((Ask(C.GetItemIconByID, id)))
		if icon then
			return icon
		end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function LastBag()
	return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

-- MelloUI's text look: Font Style's face for a string of ours
local function Style(fs, role, object, size)
	if MelloUI.StyleFont then
		MelloUI:StyleFont(fs, role, object, size)
	end
	return fs
end

local function CoinText(copper)
	local vendor = MelloUI:GetModule("Vendor")
	if vendor and vendor.CoinText then
		return vendor.CoinText(copper)
	end
	return tostring(copper) .. "c"
end

--------------------------------------------------------------------------------
-- The families (MelloUI_QuestListData.restockItems), built on first use:
-- item -> family letter, required level, stack size, class mask
--------------------------------------------------------------------------------

local fam = nil
local function Families()
	if fam then
		return fam
	end
	-- (2.1.18) rows: [letter] = the kind's items by level (the catalogue's order); diet / ilevel: a pet food's diet and
	-- item level (an item may be a food and a pet food both)
	fam = { of = {}, level = {}, stack = {}, classes = {}, classBit = false, shipped = nil, rows = {}, diet = {},
		ilevel = {}, firstOfDiet = {} }
	local data = rawget(_G, "MelloUI_QuestListData")
	local items = type(data) == "table" and data.restockItems
	if type(items) == "table" then
		for i = 1, #KIND_LETTERS do
			local letter = KIND_LETTERS:sub(i, i)
			local rows = items[letter]
			local ids = {}
			fam.rows[letter] = ids
			if type(rows) == "table" then
				for _, row in ipairs(rows) do
					local id = row[1]
					if type(id) == "number" and not fam.of[id] then
						fam.of[id], fam.level[id], fam.stack[id], fam.classes[id] = letter, row[2] or 0, row[3] or 20, row[5] or 0
						ids[#ids + 1] = id
					end
				end
			end
		end
		if type(items.diet) == "table" then
			for _, row in ipairs(items.diet) do
				local id, diet = row[1], row[2]
				if type(id) == "number" and FAMILY["p" .. tostring(diet)] then
					fam.diet[id], fam.ilevel[id] = diet, row[3] or 0
					fam.stack[id] = fam.stack[id] or row[4] or 20
					fam.firstOfDiet[diet] = fam.firstOfDiet[diet] or id
				end
			end
		end
	end
	-- the player's class as the data's mask (classes = { [bit] = "TOKEN" })
	local token = PlayerClass()
	local classes = type(data) == "table" and data.classes
	if token and type(classes) == "table" then
		for b, t in pairs(classes) do
			if t == token then
				fam.classBit = b
			end
		end
	end
	for _, reagents in pairs(REAGENTS) do
		for _, r in ipairs(reagents) do
			WINDOW[r[1]] = { r[2], r[3] }
		end
	end
	return fam
end

local function ClassOk(mask, mine)
	if not mask or mask == 0 or not mine then
		return true
	end
	return bit.band(mask, mine) ~= 0
end

-- a line counts at this level (a reagent only in its levels; 2.1.18: an item of the kinds from the level it is used
-- at -- the catalogue lists the next ones up)
local function Active(key, level)
	local w = type(key) == "number" and WINDOW[key]
	if not w then
		local need = type(key) == "number" and Families().level[key]
		return not (need and need > level)
	end
	return level >= w[1] and (w[2] == nil or level <= w[2])
end

-- the names of the shipped vendor rows (a shop seen with one of them
-- overrides it: kept then even when it sells none of the goods)
local function ShippedName(name)
	local F = Families()
	if not F.shipped then
		F.shipped = {}
		local data = rawget(_G, "MelloUI_QuestListData")
		local rows = type(data) == "table" and data.services
		if type(rows) == "table" then
			for _, row in ipairs(rows) do
				if row[1] == "vendor" and type(row[2]) == "string" then
					F.shipped[row[2]] = true
				end
			end
		end
	end
	return F.shipped[name] == true
end

--------------------------------------------------------------------------------
-- The list (per character)
--------------------------------------------------------------------------------

local list = {
	n = 0, key = {}, amount = {},   -- the lines
	text = false,                   -- the text they were read from
	items = {},                     -- [item] = true: the item lines
	families = false,               -- a family line is there (the bags are walked)
	version = 0,                    -- one up at every change
}
local keyCache = { guid = false, key = nil }
local suggest = { text = nil }

-- the setting that keeps this character's list
local function ListKey()
	local guid = Text((Ask(UnitGUID, "player")))
	if not guid then
		return nil
	end
	if keyCache.guid ~= guid then
		keyCache.guid, keyCache.key = guid, "list_" .. guid:gsub("[^%w]", "")
	end
	return keyCache.key
end

-- a hunter's ammunition: bullets for a gun in the ranged slot, else arrows
local function HunterAmmo()
	local id = Num((Ask(_G.GetInventoryItemID, "player", 18)))
	local C = C_Item
	if id and C and C.GetItemInfoInstant then
		local ok, _, _, _, _, _, classID, subclassID = pcall(C.GetItemInfoInstant, id)
		if ok and Num(classID) == 2 and Num(subclassID) == 3 then
			return "b"
		end
	end
	return "a"
end

-- the class's suggestion as list text (made again after a level up or a new
-- ranged weapon)
local function Suggested()
	if suggest.text then
		return suggest.text
	end
	local class = PlayerClass() or ""
	local level = Level()
	local parts = {}
	-- no food, drink or ammo before level 5 (user, 2026-09-26): a new
	-- character has no gold yet, so it would only be nagged in its first inn
	if (tonumber(level) or 0) >= 5 then
		if DRINKERS[class] then
			parts[#parts + 1] = "d:" .. FAMILY.d.amount
		end
		parts[#parts + 1] = "f:" .. FAMILY.f.amount
		if class == "HUNTER" then
			local ammo = HunterAmmo()
			parts[#parts + 1] = ammo .. ":" .. FAMILY[ammo].amount
		end
	end
	for _, r in ipairs(REAGENTS[class] or {}) do
		if r[3] == nil or level <= r[3] then
			parts[#parts + 1] = r[1] .. ":" .. r[4]
		end
	end
	suggest.text = table.concat(parts, " ")
	return suggest.text
end

local function Stored()
	local key = ListKey()
	if not (key and M.db) then
		return nil
	end
	return Text(M.db[key])
end

local function Has(key)
	for i = 1, list.n do
		if list.key[i] == key then
			return i
		end
	end
	return nil
end

-- the lines from list text
local function Parse(text)
	list.n = 0
	wipe(list.items)
	list.families = false
	for word in text:gmatch("[^%s,;]+") do
		local k, a = word:match("^(%w+):(%d+)$")
		local amount = tonumber(a)
		local key = nil
		if k and FAMILY[k] then
			key = k
		elseif k and k:match("^%d+$") then
			key = tonumber(k)
		end
		if key and amount and list.n < MAX_ENTRIES and not Has(key) then
			list.n = list.n + 1
			list.key[list.n], list.amount[list.n] = key, min(amount, MAX_AMOUNT)
			if type(key) == "number" then
				list.items[key] = true
			else
				list.families = true
			end
		end
	end
	for i = list.n + 1, #list.key do
		list.key[i], list.amount[i] = nil, nil
	end
end

local state = {
	ready = false, waiting = false, registered = false, frame = nil,
	dirty = true,     -- the bags changed since the last count
	pass = 0, seen = {},
	famHave = { d = 0, f = 0, a = 0, b = 0, r = 0 },
	famBest = {},     -- (2.1.50) [letter] = the highest level of that family's items in the bags
	have = {}, low = {}, active = {},
	lowCount = 0, lowMask = -1, version = -1,
	told = nil, toldActive = nil,
	text = "Restock", textMask = -1, textVersion = -1,
}

-- the list as it stands (read again only when its text changed)
local function EnsureList()
	local text = Stored() or Suggested()
	if text ~= list.text then
		list.text = text
		Parse(text)
		list.version = list.version + 1
		state.dirty = true
	end
end

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

local function Below()
	local b = M.db and Num(M.db.below)
	if not b or b <= 0 or b >= 1 then
		return LOW_DEFAULT
	end
	return b
end

-- the family counts from the bags: each item the character can use, once
-- (2.1.18) and the diets': every food of a diet in the bags, whatever its level (a pet's, not the character's)
local function CountFamilies(level)
	local F = Families()
	local famHave, famBest, seen = state.famHave, state.famBest, state.seen
	for k in pairs(famHave) do
		famHave[k] = 0
	end
	for k in pairs(famBest) do
		famBest[k] = nil
	end
	if not list.families or not C_Container then
		return
	end
	state.pass = state.pass + 1
	local pass = state.pass
	local getID, getSlots = C_Container.GetContainerItemID, C_Container.GetContainerNumSlots
	for bag = 0, LastBag() do
		local slots = Num((Ask(getSlots, bag))) or 0
		for slot = 1, slots do
			local id = Num((Ask(getID, bag, slot)))
			if id and seen[id] ~= pass then
				local letter, diet = F.of[id], F.diet[id]
				local family = letter and FAMILY[letter] and letter
				if family or diet then
					seen[id] = pass
					local n = ItemCount(id)
					if family and F.level[id] <= level and ClassOk(F.classes[id], F.classBit) then
						famHave[family] = (famHave[family] or 0) + n
						if n > 0 and F.level[id] > (famBest[family] or -1) then
							famBest[family] = F.level[id]
						end
					end
					if diet then
						local key = DIET_KEY[diet]
						famHave[key] = (famHave[key] or 0) + n
					end
				end
			end
		end
	end
end

local Changed, ShopCounted, ListCounted, ReachOpts   -- (below)

local function Count()
	state.dirty = false
	EnsureList()
	local level = Level()
	CountFamilies(level)
	local below = Below()
	local lowCount, lowMask = 0, 0
	for i = 1, list.n do
		local key, amount = list.key[i], list.amount[i]
		local have
		if type(key) == "number" then
			have = ItemCount(key)
		else
			have = state.famHave[key] or 0
		end
		local active = Active(key, level)
		local low = active and amount > 0 and have < amount * below
		state.have[i], state.active[i], state.low[i] = have, active, low
		if low then
			lowCount = lowCount + 1
			lowMask = lowMask + 2 ^ (i - 1)
		end
	end
	state.lowCount = lowCount
	if lowMask ~= state.lowMask or list.version ~= state.version then
		state.lowMask, state.version = lowMask, list.version
		Changed()
	end
	ShopCounted()
	ListCounted()
end

-- the count, now when it is out of date (never in combat: the last one then;
-- PLAYER_REGEN_ENABLED counts once the fight is over)
local function Counted()
	if InCombat() then
		return
	end
	if state.dirty or list.text ~= (Stored() or Suggested()) then
		Count()
	end
end

local function CountSoon()
	if InCombat() then
		return   -- (counted when the fight ends: PLAYER_REGEN_ENABLED)
	end
	Count()
end

-- the bags changed: counted on the next frame, once for all that came
local function Dirty()
	state.dirty = true
	if state.ready and not InCombat() then
		MelloUI.Kit:NextFrame("Restock count", CountSoon)
	end
end

--------------------------------------------------------------------------------
-- The list's lines as the texts say them
--------------------------------------------------------------------------------

local function EntryName(key, lower)
	if type(key) == "number" then
		local name = ItemName(key)
		if name then
			return name
		end
		state.nameMissing = true   -- (the client has not named it yet: RemText)
		return "Item " .. key
	end
	local f = FAMILY[key]
	return lower and f.word or f.name
end

-- "drink", "drink and food", "drink, food and arrows", "drink, food and 2 more"
local function Words(keys, n)
	if n == 0 then
		return ""
	elseif n == 1 then
		return EntryName(keys[1], true)
	elseif n == 2 then
		return EntryName(keys[1], true) .. " and " .. EntryName(keys[2], true)
	elseif n == 3 then
		return EntryName(keys[1], true) .. ", " .. EntryName(keys[2], true) .. " and " .. EntryName(keys[3], true)
	end
	return EntryName(keys[1], true) .. ", " .. EntryName(keys[2], true) .. " and " .. (n - 2) .. " more"
end

local lowKeys = {}   -- the low lines' keys, in list order (filled again)
local function LowKeys()
	local n = 0
	for i = 1, list.n do
		if state.low[i] then
			n = n + 1
			lowKeys[n] = list.key[i]
		end
	end
	for i = n + 1, #lowKeys do
		lowKeys[i] = nil
	end
	return lowKeys, n
end

--------------------------------------------------------------------------------
-- The reminder (MelloUI.Reminders, Core/Reminders.lua)
--------------------------------------------------------------------------------

local function Reminders()
	local rem = MelloUI.Reminders
	if type(rem) == "table" then
		return rem
	end
	return nil
end

-- the Reminders page's own switch: off, no reminder at all
local function RemindersOn()
	if not MelloUI:GetModule("Reminders") then
		return true
	end
	return MelloUI:IsModuleEnabled("Reminders") and true or false
end

-- (the reminder's own switch is this module's: its spec is with the widget
-- only while the module is on, enabled = true; the Reminders page's module
-- switch off, none of its reminders is wanted)
local function RemActive()
	if not (M.isEnabled and M.db and RemindersOn()) then
		return false
	end
	-- (the widget asks from its login moment on, 8 s into the world: counted
	-- then when the bags changed since)
	if state.dirty then
		Counted()
	end
	return state.lowCount > 0
end

-- the names the client sends later: while a low line's item is still
-- "Item 17031" in the text, the text is told again once one arrives
local function WaitForNames(on)
	local f = state.frame
	if f and on ~= state.namesWanted then
		state.namesWanted = on
		if on then
			f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		else
			f:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		end
	end
end

-- "Restock: drink and food" (made again only when the low lines changed, or
-- while an item's name has not come yet)
local function RemText()
	if state.textMask ~= state.lowMask or state.textVersion ~= list.version then
		state.textMask, state.textVersion = state.lowMask, list.version
		state.nameMissing = false
		local keys, n = LowKeys()
		state.text = n > 0 and ("Restock: " .. Words(keys, n)) or "Restock"
		if state.nameMissing then
			state.textMask = -1   -- (made again at the next ask)
		end
		WaitForNames(state.nameMissing)
	end
	return state.text
end

-- up the whole time in a rest area (the user's rule), until restocked or
-- the rest area is left: while low and the widget's StayUp() (Stay Up In
-- Rest Areas, the Reminders page's one switch of all four, and the player
-- resting)
local function RemPersistent()
	local rem = Reminders()
	return RemActive() and rem ~= nil and type(rem.StayUp) == "function" and rem:StayUp() or false
end

local function RemClick()
	return M:GoTo()
end

-- the tooltip's lines (built on hover only): each line of the list with
-- what the bags hold, the low ones in the palette's gold
local function RemTooltip(_, tip)
	if type(tip) ~= "table" or type(tip.AddDoubleLine) ~= "function" then
		return
	end
	local P = MelloUI.Look.TipPalette()
	local text, gold = P.text, P.selectedTrim
	for i = 1, list.n do
		if state.active[i] and list.amount[i] > 0 then
			local have = state.have[i] or 0
			local c = state.low[i] and gold or text
			tip:AddDoubleLine(EntryName(list.key[i]), have .. " / " .. list.amount[i], text[1], text[2], text[3], c[1], c[2], c[3])
		end
	end
end

-- (one table: the widget keeps it, its fields change in place). The widget's
-- contract (Core/Reminders.lua): the reach is measured by it through
-- Services:Nearest("vendor", { letters, skip, extra }), which follow the low
-- lines as the click's route does (ReachOpts). enabled: on (0.16.0: the
-- Restock switch is its reminder's too; registered only while it is on)
local SPEC = {
	key = REM_KEY, label = "Restock", icon = ICON, text = RemText, urgency = URGENCY, check = RemActive, enabled = true,
	when = {},   -- (Core's moments: login, a rest area, a zone; this module tells it of every change of its own)
	onClick = RemClick, persistent = RemPersistent, tooltip = RemTooltip,
	dismiss = "rest",   -- Not now: until a rest area is entered again (the user's pick)
	hint = "Click: the way to the nearest shop that sells it",
	kind = "vendor", letters = nil, skip = nil, extra = nil,
}

-- the widget told when what check() or text() says changed
Changed = function()
	local active, text = RemActive(), RemText()
	if state.toldActive == active and state.told == text then
		return
	end
	state.toldActive, state.told = active, text
	ReachOpts(active)
	local rem = Reminders()
	if state.registered and rem and type(rem.Refresh) == "function" then
		rem:Refresh(REM_KEY)
	end
end

-- the spec to the widget while the module is on, taken back while it is off
-- (the widget keeps its Not now over a new registration)
local function Register(on)
	local rem = Reminders()
	if not rem or on == state.registered then
		return
	end
	if on then
		if type(rem.Register) ~= "function" then
			return
		end
		state.registered = true
		rem:Register(SPEC)
	else
		state.registered = false
		if type(rem.Unregister) == "function" then
			rem:Unregister(REM_KEY)
		end
	end
	state.told, state.toldActive = nil, nil
end

--------------------------------------------------------------------------------
-- The shops seen: Services' learned places (kind "vendor"), read through
-- Services:LearnedPlaces() and written through Services:Learn (one store,
-- one writer); Restock keeps two fields on its entries: sells (the families)
-- and items (the list's items it sells)
--------------------------------------------------------------------------------

local function ServiceStore()
	local services = MelloUI:GetModule("Services")
	if not (services and type(services.LearnedPlaces) == "function") then
		return nil
	end
	local ok, store = pcall(services.LearnedPlaces, services)
	return ok and type(store) == "table" and store or nil
end

-- what the open merchant lists: every item id by its index (filled again at
-- each look), and for the goods, what it asks
local merchant = {
	n = 0, idx = {}, id = {},
	ok = {}, name = {}, icon = {}, price = {}, bundle = {}, avail = {}, maxStack = {},
}

-- one merchant item's offer: name, icon, price (a purchase), items a
-- purchase, how many purchases are left (-1 any), whether it is for sale
-- here for gold (no tokens, no currency)
local function Offer(index)
	local C = C_MerchantFrame
	if C and C.GetItemInfo then
		local info = Ask(C.GetItemInfo, index)
		if type(info) ~= "table" then
			return nil
		end
		local extended, currency, purchasable, usable = info.hasExtendedCost, info.currencyID, info.isPurchasable, info.isUsable
		if IsSecret(extended) or IsSecret(currency) or IsSecret(purchasable) or IsSecret(usable) then
			return nil
		end
		local ok = not extended and currency == nil and purchasable ~= false and usable ~= false
		return Text(info.name), Plain(info.texture), Num(info.price), Num(info.stackCount), Num(info.numAvailable), ok
	end
	if _G.GetMerchantItemInfo then
		local okCall, name, texture, price, quantity, available, purchasable, usable, extended = pcall(_G.GetMerchantItemInfo, index)
		if not okCall or IsSecret(extended) or IsSecret(purchasable) or IsSecret(usable) then
			return nil
		end
		local ok = not extended and purchasable ~= false and usable ~= false
		return Text(name), Plain(texture), Num(price), Num(quantity), Num(available), ok
	end
	return nil
end

-- the merchant's list: the goods' offers read (the family items and the
-- list's items), then what it sells remembered
local function ScanMerchant()
	local F = Families()
	local n = Num((Ask(_G.GetMerchantNumItems))) or 0
	local m = merchant
	m.n = 0
	for index = 1, n do
		local id = Num((Ask(_G.GetMerchantItemID, index)))
		if id then
			local j = m.n + 1
			m.n = j
			m.idx[j], m.id[j], m.ok[j] = index, id, false
			if F.of[id] or F.diet[id] or list.items[id] then
				local name, icon, price, bundle, avail, ok = Offer(index)
				if ok and price and price >= 0 then
					m.ok[j] = true
					m.name[j], m.icon[j], m.price[j] = name or ItemName(id) or ("Item " .. id), icon or ItemIcon(id), price
					m.bundle[j] = (bundle and bundle >= 1) and bundle or 1
					m.avail[j] = avail or -1
					local most = Num((Ask(_G.GetMerchantItemMaxStack, index)))
					m.maxStack[j] = (most and most >= m.bundle[j]) and most or m.bundle[j]
				end
			end
		end
	end
end

local sellsScratch = { d = false, f = false, a = false, b = false, r = false }
local dietScratch = {}   -- [diet] = true: a shop sells food of it (LearnShop, filled again)

-- the open shop, remembered with what it sells (written only when that
-- changed): a shop that sells none of it is kept only to override a shipped
-- row of the same name. Services:Learn(kind, name, sub, create) -> the
-- entry of the NPC whose window is open (name nil) on the player's map, and
-- that NPC's name; create false: only one kept before
local function LearnShop()
	local services = MelloUI:GetModule("Services")
	if not (services and type(services.Learn) == "function") then
		return
	end
	local okKept, e, name = pcall(services.Learn, services, "vendor", nil, "", false)
	if not okKept or type(name) ~= "string" then
		return
	end
	local F = Families()
	local s = sellsScratch
	s.d, s.f, s.a, s.b, s.r = false, false, false, false, false
	local items = nil
	-- (2.1.18) the diets it sells: kept as their digits after the families' letters
	local diets = dietScratch
	for d = 1, #DIETS do
		diets[d] = false
	end
	for j = 1, merchant.n do
		local id = merchant.id[j]
		local letter = F.of[id]
		if letter and FAMILY[letter] then
			s[letter] = true
		end
		local diet = F.diet[id]
		if diet then
			diets[diet] = true
		end
		if list.items[id] then
			items = items and (items .. "," .. id) or tostring(id)
		end
	end
	local sells = (s.d and "d" or "") .. (s.f and "f" or "") .. (s.a and "a" or "") .. (s.b and "b" or "") .. (s.r and "r" or "")
	for d = 1, #DIETS do
		if diets[d] then
			sells = sells .. d
		end
	end
	items = items or ""
	if type(e) ~= "table" then
		if sells == "" and items == "" and not ShippedName(name) then
			return
		end
		local okNew, made = pcall(services.Learn, services, "vendor", name, "")
		if not okNew or type(made) ~= "table" then
			return   -- (no place on this map: an instance, a map the client does not place)
		end
		e = made
	elseif e.sells == sells and e.items == items then
		return
	end
	e.sells, e.items = sells, items
end

--------------------------------------------------------------------------------
-- The route to a shop (Services:GoTo "vendor"; the reminder's click and the
-- Errands group's Restock)
--------------------------------------------------------------------------------

local route = { letters = "", skip = {}, extra = {}, what = "", label = "Restock", fallback = nil }
local wantKeys = {}

-- what to shop for: the low lines, or every line when none is low (a trip
-- to top up)
local function Wants()
	local keys, n = LowKeys()
	if n > 0 then
		return keys, n
	end
	for i = 1, list.n do
		if state.active[i] ~= false and list.amount[i] > 0 then
			n = n + 1
			wantKeys[n] = list.key[i]
		end
	end
	for i = n + 1, #wantKeys do
		wantKeys[i] = nil
	end
	return wantKeys, n
end

-- Services:GoTo's options for these lines: the families (a reagent item as
-- "r"), the shops seen by name (they override the shipped rows), the shops
-- seen that sell a line's own item, the innkeeper for drink and food
local function RouteOpts(keys, n)
	local F = Families()
	local s = sellsScratch
	s.d, s.f, s.a, s.b, s.r = false, false, false, false, false
	local items = false
	local diets = nil   -- (2.1.18) the diets wanted, as their digits: the shops seen that sell one of them
	for i = 1, n do
		local key = keys[i]
		local family = FAMILY[key]
		if type(key) == "number" then
			local letter = F.of[key]
			if letter and FAMILY[letter] then
				s[letter] = true
			end
			items = true
		elseif family and family.diet then
			diets = (diets or "") .. family.diet
		elseif family then
			s[key] = true
		end
	end
	route.letters = (s.d and "d" or "") .. (s.f and "f" or "") .. (s.a and "a" or "") .. (s.b and "b" or "") .. (s.r and "r" or "")
	route.fallback = (s.d or s.f) and "innkeeper" or nil
	route.what = "vendor with " .. Words(keys, n)
	wipe(route.skip)
	wipe(route.extra)
	local store = ServiceStore()
	if store then
		for _, e in pairs(store) do
			if type(e) == "table" and e.kind == "vendor" and type(e.name) == "string" then
				route.skip[e.name] = true
				-- a shop seen with one of the lines' own items (the families
				-- are Services' own filter, by `sells`; an item of the kinds
				-- that are no family -- potions, elixirs, poisons -- by its id)
				local hit = false
				if items and type(e.items) == "string" and e.items ~= "" then
					for i = 1, n do
						local key = keys[i]
						local letter = type(key) == "number" and F.of[key]
						if type(key) == "number" and not (letter and FAMILY[letter])
							and ("," .. e.items .. ","):find("," .. key .. ",", 1, true) then
							hit = true
							break
						end
					end
				end
				-- (2.1.18) a shop seen selling food of a diet wanted
				if not hit and diets and type(e.sells) == "string" and e.sells:find("[" .. diets .. "]") then
					hit = true
				end
				if hit then
					route.extra[#route.extra + 1] = { name = e.name, sub = e.sub or "", mapID = e.mapID, x = e.x, y = e.y }
				end
			end
		end
	end
	return route
end

-- The widget's reach as the click's route goes (the widget measures it with
-- the spec's letters, skip and extra): the low lines' families, the shops
-- seen passed over by name, the shops seen that sell a line's own item --
-- letters "" when no family is low, so no shop of other goods counts.
-- Nothing while none is low. Made at Changed()'s edges and when a shop is
-- recorded, never per check (the route's tables, filled in place)
ReachOpts = function(active)
	if not active then
		SPEC.letters, SPEC.skip, SPEC.extra = nil, nil, nil
		return
	end
	local opts = RouteOpts(LowKeys())
	SPEC.letters, SPEC.skip, SPEC.extra = opts.letters, opts.skip, opts.extra
end

-- (lines no family covers: letters "", which Services reads as no shipped
-- row at all, so only the shops seen that sell one of them, `extra`)
function M:GoTo()
	Counted()
	local keys, n = Wants()
	if n == 0 then
		MelloUI:Announce("Your restock list is empty. Add to it with /restock.", "fail")
		return false, "empty"
	end
	local opts = RouteOpts(keys, n)
	if opts.letters == "" and #opts.extra == 0 then
		MelloUI:Announce("No " .. opts.what .. " known yet. Open a shop that sells it once and it is remembered.", "fail")
		return false, "none"
	end
	local services = MelloUI:GetModule("Services")
	if not (services and type(services.GoTo) == "function") then
		MelloUI:Announce("Switch on Services to route there.", "fail")
		return false, "off"
	end
	return services:GoTo("vendor", opts)
end

function M:LowCount()
	return state.lowCount
end

--------------------------------------------------------------------------------
-- The shop: what to buy (planned from the merchant's list) and the panel
--------------------------------------------------------------------------------

local plan = {
	n = 0, merch = {}, entry = {}, count = {}, cost = {},   -- the rows: merchant slot, list line, items, copper
	total = 0, money = nil, short = nil, anyLow = false,
	-- (2.1.50) skip[r]: the row's item unticked (shown dimmed, not bought, not in the total); ticked: the rows Buy buys
	skip = {}, ticked = 0,
	-- (2.1.50) the lines' items not offered: of a family the bags hold better of (names, the lines' keys)
	notN = 0, notName = {}, notKey = {}, notText = "",
}
local shop = { open = false, snoozed = false, done = false, frame = nil, rows = {} }
-- (lastRow, lastN, lastCost: the purchase sent last, taken off the count
-- when the game refuses it)
local buy = { on = false, waiting = false, row = 1, left = {}, bought = {}, spent = 0, lastRow = nil, lastN = 0, lastCost = 0 }

local function MerchantOpen()
	local f = MerchantFrame
	if not (shop.open and f and f.IsShown) then
		return false
	end
	local shown = f:IsShown()
	return not IsSecret(shown) and shown and true or false
end

-- the free bag slots: general, quiver, ammo pouch
local function FreeSlots()
	local general, quiver, pouch = 0, 0, 0
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then
		return general, quiver, pouch
	end
	for bag = 0, LastBag() do
		local free, family = Ask(C_Container.GetContainerNumFreeSlots, bag)
		free, family = Num(free), Num(family)
		if free then
			if not family or family == 0 then
				general = general + free
			elseif bit.band(family, 1) ~= 0 then
				quiver = quiver + free
			elseif bit.band(family, 2) ~= 0 then
				pouch = pouch + free
			end
		end
	end
	return general, quiver, pouch
end

local function StackSize(id)
	local F = Families()
	local s = F.stack[id]
	if not s and C_Item and C_Item.GetItemMaxStackSizeByID then
		s = Num((Ask(C_Item.GetItemMaxStackSizeByID, id)))
	end
	return (s and s >= 1) and s or 20
end

-- the merchant's best for a line: its own item, or of a family the
-- character can use, the highest level first (then the dearer per item)
-- (2.1.18: a diet's, its food of the highest item level up to the character's -- the pet is never above it)
local function BestFor(key, level)
	local F, m = Families(), merchant
	local best, bestLevel, bestUnit = nil, -1, -1
	local diet = type(key) == "string" and FAMILY[key] and FAMILY[key].diet
	for j = 1, m.n do
		local id = m.id[j]
		if m.ok[j] then
			if type(key) == "number" then
				if id == key then
					return j
				end
			elseif diet then
				local lv = F.ilevel[id] or 0
				if F.diet[id] == diet and lv <= level then
					local unit = m.price[j] / m.bundle[j]
					if lv > bestLevel or (lv == bestLevel and unit > bestUnit) then
						best, bestLevel, bestUnit = j, lv, unit
					end
				end
			elseif F.of[id] == key and F.level[id] <= level and ClassOk(F.classes[id], F.classBit) then
				local lv, unit = F.level[id], m.price[j] / m.bundle[j]
				if lv > bestLevel or (lv == bestLevel and unit > bestUnit) then
					best, bestLevel, bestUnit = j, lv, unit
				end
			end
		end
	end
	return best
end

-- (2.1.50; Nixxen, 2026-11-12: "Would love a way to unselect items we do not want to buy in the restock popup", the
-- user's pick A of BuildData/output/restock_discard_sketch) the shop's items this character unticked: never bought, at
-- any shop, until ticked again. Kept as text, the item ids (the setting "skip_<guid>", beside the list's)
-- (one table: the file is near Lua's 200 locals)
local Pick = { text = false, ids = {}, notKeys = {}, NONE = {} }

function Pick.Key()
	local key = ListKey()
	return key and ("skip_" .. key:sub(6)) or nil
end

function Pick.Skipped(id)
	local key = Pick.Key()
	local text = key and M.db and Text(M.db[key]) or ""
	if text ~= Pick.text then
		Pick.text = text
		for k in pairs(Pick.ids) do
			Pick.ids[k] = nil
		end
		for w in text:gmatch("%d+") do
			Pick.ids[tonumber(w)] = true
		end
	end
	return Pick.ids[id] == true
end

function Pick.Set(id, on)
	local key = Pick.Key()
	if not (key and M.db and id) then
		return
	end
	Pick.Skipped(id)
	Pick.ids[id] = on and true or nil
	local parts = {}
	for k in pairs(Pick.ids) do
		parts[#parts + 1] = k
	end
	table.sort(parts)
	local text = table.concat(parts, " ")
	Pick.text = text
	MelloUI:NotifySettingChanged("Restock", key, text)
end

-- (2.1.50; Nixxen: "perhaps a level filter on the restock items", the user's pick N1) a drink, food or ammunition line
-- never offers an item of a lower level than the best of its family already in the bags: left out, and named
Pick.NO_DOWNGRADE = { d = true, f = true, a = true, b = true }

function Pick.Downgrade(key, j)
	local best = Pick.NO_DOWNGRADE[key] and state.famBest[key]
	return best ~= nil and (Families().level[merchant.id[j]] or 0) < best
end

local function Planned(j)
	for r = 1, plan.n do
		if plan.merch[r] == j then
			return true
		end
	end
	return false
end

-- what to buy here: each line below its full amount that the merchant sells,
-- back up to the amount in whole purchases, as far as the stock, the bags
-- and the gold go
local function Plan()
	plan.n, plan.total, plan.short, plan.anyLow, plan.ticked, plan.notN = 0, 0, nil, false, 0, 0
	local money = Money()
	plan.money = money
	local level = Level()
	local general, quiver, pouch = FreeSlots()
	local F, m = Families(), merchant
	for e = 1, list.n do
		local key, amount, have = list.key[e], list.amount[e], state.have[e] or 0
		local j = state.active[e] and amount > have and plan.n < SHOP_ROWS and BestFor(key, level) or nil
		if j and Pick.Downgrade(key, j) then
			if not Planned(j) and plan.notN < SHOP_ROWS then
				plan.notN = plan.notN + 1
				plan.notName[plan.notN], plan.notKey[plan.notN] = m.name[j], key
			end
			j = nil
		end
		if j and not Planned(j) then
			local id, bundle, price = m.id[j], m.bundle[j], m.price[j]
			local skipped = Pick.Skipped(id)
			local buys = ceil((amount - have) / bundle)
			local avail = m.avail[j]
			if avail and avail >= 0 and buys > avail then
				buys = avail
			end
			-- the bags: what fits on this item's stacks and in the free slots
			-- it may take (ammunition: its quiver or pouch first); an unticked
			-- row takes neither room nor gold
			local stack = StackSize(id)
			local own = ItemCount(id) % stack
			local room = own > 0 and (stack - own) or 0
			local letter = F.of[id]
			local special = letter == "a" and quiver or letter == "b" and pouch or 0
			local fits = room + (general + special) * stack
			if not skipped and buys * bundle > fits then
				buys = floor(fits / bundle)
				plan.short = "bags"
			end
			if not skipped and money and price > 0 then
				local afford = floor((money - plan.total) / price)
				if buys > afford then
					buys = max(0, afford)
					plan.short = plan.short or "gold"
				end
			end
			if buys > 0 then
				local items = buys * bundle
				if not skipped then
					local slots = ceil(max(0, items - room) / stack)
					local fromSpecial = min(special, slots)
					if letter == "a" then
						quiver = quiver - fromSpecial
					elseif letter == "b" then
						pouch = pouch - fromSpecial
					else
						fromSpecial = 0
					end
					general = general - (slots - fromSpecial)
					plan.total = plan.total + buys * price
					plan.ticked = plan.ticked + 1
				end
				local r = plan.n + 1
				plan.n = r
				plan.merch[r], plan.entry[r], plan.count[r], plan.cost[r] = j, e, items, buys * price
				plan.skip[r] = skipped
				if state.low[e] then
					plan.anyLow = true
				end
			end
		end
	end
end

-- the panel ---------------------------------------------------------------

-- (a row for every purchase a visit plans: every item Buy buys is shown with
-- its amount and price; 36 + 16 x 26 + 74 = 526 -- 2.1.18: the list holds 40
-- lines now, a visit plans SHOP_ROWS of them)
local PANEL_W, PAD, HEAD, ROW_H, FOOT, MAX_ROWS = 320, 12, 36, 26, 74, SHOP_ROWS
-- (2.1.50, the pick A) a tick box at each row's start: the panel wider by its column, the rest as it was; an unticked
-- row dimmed; a note a line (the bags or the gold, the ticks', what was not offered), the panel taller by each past one
Pick.COL, Pick.SIZE, Pick.DIM, Pick.NOTE_H, Pick.NOTE_PX = 24, 23, 0.38, 16, 10
PANEL_W = PANEL_W + Pick.COL
local PANEL_AREA = "config"   -- the panel's look: the reskin's, as MelloUI's own windows (Kit.Areas)

local RowEnter = Shared("OnEnter on the Restock shop rows", function(row)
	local r = row.planRow
	local j = r and plan.merch[r]
	if not j then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if not pcall(GameTooltip.SetMerchantItem, GameTooltip, merchant.idx[j]) then
		GameTooltip:SetText(merchant.name[j] or "")
	end
	GameTooltip:Show()
end, "script")

local ShopRefresh, BuyStart, NotNow   -- (below)

local BuyClick = Shared("OnClick on the Restock shop's Buy", function()
	BuyStart()
end, "script")

local NotNowClick = Shared("OnClick on the Restock shop's Not now", function()
	NotNow()
end, "script")

local EditClick = Shared("OnClick on the Restock shop's Edit list", function()
	M:OpenList()
end, "script")

-- a row's tick: its item bought or skipped, here and at every shop (the plan again: the total, Buy)
function Pick.TickGet(tick)
	local r = tick.row.planRow
	return r ~= nil and not plan.skip[r]
end

function Pick.TickSet(tick, on)
	local r = tick.row.planRow
	local j = r and plan.merch[r]
	if j and not buy.on then
		Pick.Set(merchant.id[j], not on)
		ShopRefresh()
	end
end

local function ShopRow(f, i)
	local row = CreateFrame("Frame", nil, f)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(HEAD + (i - 1) * ROW_H))
	row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	if i % 2 == 1 then
		-- a neutral stripe under every other row (WINDOW-RULES 2e; MelloUI.Look)
		row.band = MelloUI.Look.Solid(row, "BACKGROUND", "mainWindow", 0.85)
		row.band:SetAllPoints(row)
	end
	local tick = nil
	tick = W.Switch(row, function() return Pick.TickGet(tick) end, function(on) Pick.TickSet(tick, on) end)
	tick.row = row
	tick:SetScale(Pick.SIZE / tick:GetWidth())
	tick:SetPoint("LEFT", row, "LEFT", 1 / tick:GetScale(), 0)
	row.tick = tick
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", row, "LEFT", 4 + Pick.COL, 0)
	row.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	row.price = Style(W.Text(row, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	row.price:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.price:SetJustifyH("RIGHT")
	row.price:SetJustifyV("MIDDLE")
	row.amount = Style(W.Text(row, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	row.amount:SetPoint("RIGHT", row.price, "LEFT", -10, 0)
	row.amount:SetJustifyV("MIDDLE")
	row.name = Style(W.Text(row, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.amount, "LEFT", -8, 0)
	row.name:SetJustifyV("MIDDLE")
	row.name:SetWordWrap(false)
	row:EnableMouse(true)
	Perf.SetScript(row, "OnEnter", RowEnter)
	Perf.SetScript(row, "OnLeave", W.TipLeave)
	row:Hide()
	return row
end

-- the panel's box in the look of the moment: the kit's list box (its shade
-- with it, the windows' area: made once, the first time the kit's box shows)
-- or the plain one
local function PanelLook(f)
	local Kit = MelloUI.Kit
	local on = Kit and Kit.IsOn and Kit:IsOn(PANEL_AREA) and true or false
	-- (W.TrayBox's SetKit is handed the kit while its look is on)
	if f:SetKit(on and Kit or false) and not f.shaded then
		f.shaded = true
		local rep = f.kitBox
		if rep and rep.skin and Kit.ShadeElement then
			local ok, el = pcall(Kit.ShadeElement, Kit, f, "windows", { host = rep.skin })
			if ok and type(el) == "table" and type(el.Add) == "function" then
				el:Add(rep)
			end
		end
	end
end

-- the panel, made on the first shop that needs it: the tray box beside a
-- window (W.TrayBox: the palette's inner panel under the text, the eye
-- strain rule)
local function BuildPanel()
	local f = W.TrayBox(UIParent, { name = "MelloUIRestockPanel", strata = "HIGH" })
	f:SetClampedToScreen(true)
	f:SetWidth(PANEL_W)
	f:EnableMouse(true)
	f:Hide()
	PanelLook(f)
	MelloUI:On("look:" .. PANEL_AREA, function()
		PanelLook(f)
	end, "Restock panel")
	f.title = Style(W.Text(f, "GameFontNormal", "Restock", "selectedTrim"), "fontTitle", _G.GameFontNormal, 15)
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -12)
	f.hint = Style(W.Text(f, "GameFontHighlight", "Back up to your list's amounts", "text"), "fontText", _G.GameFontHighlight)
	f.hint:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	f.hint:SetWordWrap(false)
	for i = 1, MAX_ROWS do
		shop.rows[i] = ShopRow(f, i)
	end
	f.total = Style(W.Text(f, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	f.total:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 50)
	f.total:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	f.total:SetWordWrap(false)
	-- (2.1.50) the notes: a line each, the first just over the buttons (f.note), the total over them all; smaller than
	-- the rows, as the sketch drew them (in the text colour: muted text is never small body text)
	f.notes = {}
	for i = 1, 3 do
		local note = Style(W.Text(f, "GameFontHighlightSmall", nil, "text"), "fontText", _G.GameFontHighlightSmall, Pick.NOTE_PX)
		note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 34 + (i - 1) * Pick.NOTE_H)
		note:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
		note:SetWordWrap(false)
		f.notes[i] = note
	end
	f.note = f.notes[1]
	f.buy = W.Button(f, "Buy", 90, nil, { onClick = BuyClick, gold = true })
	f.buy:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 10)
	f.notNow = W.Button(f, "Not now", 90, nil, { onClick = NotNowClick })
	f.notNow:SetPoint("RIGHT", f.buy, "LEFT", -8, 0)
	f.edit = W.Button(f, "Edit list", 80, nil, { onClick = EditClick })
	f.edit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 10)
	shop.frame = f
	return f
end

local function HidePanel()
	local f = shop.frame
	if f and f:IsShown() then
		f:Hide()
	end
end

local function Place(f)
	local mf = MerchantFrame
	f:ClearAllPoints()
	if mf then
		f:SetPoint("TOPLEFT", mf, "TOPRIGHT", 12, 0)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

-- "Not offered: Refreshing Spring Water. You carry better drink." (made again only when what was left out changed)
function Pick.NotOffered()
	local notKeys = Pick.notKeys
	local said = plan.notName[1]
	local n = 0
	for i = 1, plan.notN do
		if i > 1 then
			said = said .. ", " .. plan.notName[i]
		end
		local key, seen = plan.notKey[i], false
		for x = 1, n do
			if notKeys[x] == key then
				seen = true
			end
		end
		if not seen then
			n = n + 1
			notKeys[n] = key
		end
	end
	local text = "Not offered: " .. (said or "") .. ". You carry better " .. Words(notKeys, n) .. "."
	plan.notText = text
	return text
end

-- the plan onto the panel (made again only where a text changed)
local function Fill(f)
	local shown = min(plan.n, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local row = shop.rows[i]
		if i <= shown then
			local j, e = plan.merch[i], plan.entry[i]
			row.planRow = i
			row.icon:SetTexture(merchant.icon[j])
			if row.nameText ~= merchant.name[j] then
				row.nameText = merchant.name[j]
				row.name:SetText(merchant.name[j])
			end
			local count, have = plan.count[i], state.have[e] or 0
			if row.countWas ~= count or row.haveWas ~= have then
				row.countWas, row.haveWas = count, have
				row.amount:SetText(MelloUI.Lang.F("+%d (have %d)", count, have))
			end
			if row.costWas ~= plan.cost[i] then
				row.costWas = plan.cost[i]
				row.price:SetText(CoinText(plan.cost[i]))
			end
			local a = plan.skip[i] and Pick.DIM or 1
			if row.alphaWas ~= a then
				row.alphaWas = a
				row.icon:SetAlpha(a)
				row.name:SetAlpha(a)
				row.amount:SetAlpha(a)
				row.price:SetAlpha(a)
			end
			row.tick:Refresh()
			row.tick:SetEnabled(not buy.on)
			row:Show()
		else
			row.planRow = nil
			row:Hide()
		end
	end
	-- the notes: the bags or the gold; the ticks' (a row unticked); what was not offered (N1)
	local notes, k = f.notes, 0
	local short = plan.short == "bags" and "Not all of it fits in your bags."
		or plan.short == "gold" and "Not enough gold for all of it." or nil
	local unticked = false
	for i = 1, shown do
		if plan.skip[i] then
			unticked = true
		end
	end
	local lines = f.lines or {}
	f.lines = lines
	lines[1], lines[2], lines[3] = nil, nil, nil
	if short then
		k = k + 1
		lines[k] = W.Tr(short)   -- (woofix's PR #10: the notes through the translations)
	end
	if unticked then
		k = k + 1
		lines[k] = W.Tr("Untick to skip it here and at every shop, until you tick it again.")
	end
	if plan.notN > 0 then
		k = k + 1
		lines[k] = Pick.NotOffered()
	end
	local n = max(1, k)
	for i = 1, 3 do
		-- (read top down: the last line just over the buttons)
		local text = i <= k and lines[k - i + 1] or ""
		local note = notes[i]
		if note.textWas ~= text then
			note.textWas = text
			note:SetText(text)
		end
	end
	if f.notesWas ~= n then
		f.notesWas = n
		f.total:ClearAllPoints()
		f.total:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 50 + (n - 1) * Pick.NOTE_H)
		f.total:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	end
	f:SetHeight(HEAD + shown * ROW_H + FOOT + (n - 1) * Pick.NOTE_H)
	if f.totalWas ~= plan.total or f.moneyWas ~= plan.money then
		f.totalWas, f.moneyWas = plan.total, plan.money
		local text = W.Tr("Total:") .. " " .. CoinText(plan.total)
		if plan.money then
			text = text .. "   " .. W.Tr("Left after:") .. " " .. CoinText(max(0, plan.money - plan.total))
		end
		f.total:SetText(text)
	end
	if not buy.on then
		f.buy:SetText(W.Tr("Buy"))
		f.buy:SetEnabled(plan.ticked > 0)
	end
end

local function ShowPanel()
	local f = shop.frame or BuildPanel()
	Fill(f)
	if not f:IsShown() then
		Place(f)
		if MelloUI.Anim then
			MelloUI.Anim:FadeIn(f, 0.12)
		else
			f:Show()
		end
	end
end

-- the panel's events: the merchant's list and the money, while a shop is open
local function ShopEvents(on)
	local f = state.frame
	if not f then
		return
	end
	if on then
		f:RegisterEvent("MERCHANT_UPDATE")
		f:RegisterEvent("PLAYER_MONEY")
	else
		f:UnregisterEvent("MERCHANT_UPDATE")
		f:UnregisterEvent("PLAYER_MONEY")
	end
end

-- the panel may show: the shop open, its list on, not put off this visit,
-- not in a fight, and the plan has something low in it
local function PanelWanted()
	return MerchantOpen() and not buy.on and M.isEnabled and M.db ~= nil and M.db.shopPanel == true
		and not shop.snoozed and not shop.done and not InCombat() and plan.n > 0 and plan.anyLow
end

-- the shop remembered (Services' store), on a frame of its own after the
-- first look: once a visit, its list does not change what it sells
local function LearnLater()
	if shop.open and not shop.learned then
		shop.learned = true
		LearnShop()
		ReachOpts(state.toldActive)   -- (the reminder's reach as the route now goes)
	end
end

-- the panel's first build, on the frame after the plan that asked for it
-- (the first visit's work spread over three frames: the plan, the panel,
-- the shop remembered)
local function BuildLater()
	if PanelWanted() then
		ShowPanel()
	end
	if shop.open and not shop.learned then
		MelloUI.Kit:NextFrame("Restock learn", LearnLater)
	end
end

-- the shop looked at again: its list read, the plan made, the panel shown
-- when something there is low
local function ShopLook()
	if not MerchantOpen() then
		return
	end
	if buy.on then
		return   -- (planned again once the purchases are done)
	end
	ScanMerchant()
	local building = false
	if not (M.isEnabled and M.db and M.db.shopPanel) or shop.snoozed or shop.done or InCombat() then
		HidePanel()
	else
		Counted()
		Plan()
		if not (plan.n > 0 and plan.anyLow) then
			HidePanel()
		elseif shop.frame then
			ShowPanel()
		else
			building = true
			MelloUI.Kit:NextFrame("Restock panel", BuildLater)
		end
	end
	if not shop.learned and not building then
		MelloUI.Kit:NextFrame("Restock learn", LearnLater)
	end
end

-- after the junk sale (Vendor's: the money changes with it)
local function ShopSoon()
	local vendor = MelloUI:GetModule("Vendor")
	if vendor and vendor.AfterSelling then
		vendor:AfterSelling(ShopLook)
	else
		ShopLook()
	end
end

ShopRefresh = function()
	if shop.open then
		MelloUI.Kit:NextFrame("Restock shop", ShopSoon)
	end
end

-- a count while a shop is open: its plan again
ShopCounted = function()
	if shop.open and not buy.on then
		ShopRefresh()
	end
end

-- buying ------------------------------------------------------------------

local BuyStep   -- (below)

local function BuyTimer()
	buy.waiting = false
	BuyStep()
end

local function BuyEnd(completed)
	local was = buy.on
	buy.on = false
	M.buyingQuiet = false
	local f = state.frame
	if f then
		f:UnregisterEvent("UI_ERROR_MESSAGE")
	end
	if not was then
		return
	end
	-- "Restocked: 20 Melon Juice, 1000 Razor Arrow for 1g 20s." (Vendor's
	-- Report In Chat while Vendor Automation is on; off, always)
	local parts = nil
	for r = 1, plan.n do
		local n = buy.bought[r] or 0
		if n > 0 then
			local item = n .. " " .. (merchant.name[plan.merch[r]] or "")
			parts = parts and (parts .. ", " .. item) or item
		end
	end
	local vendor = MelloUI:GetModule("Vendor")
	if parts and vendor and vendor.Report then
		vendor:Report("Restocked: %s for %s.", parts, CoinText(floor(buy.spent + 0.5)))
	end
	if completed then
		shop.done = true
		HidePanel()
	else
		ShopRefresh()
	end
	Dirty()
end

-- one purchase, then the next 0.2 s later; stops when the shop closed or its
-- list changed under the plan
BuyStep = function()
	if not buy.on then
		return
	end
	if not MerchantOpen() then
		BuyEnd(false)
		return
	end
	local r = buy.row
	while r <= plan.n and (buy.left[r] or 0) <= 0 do
		r = r + 1
	end
	buy.row = r
	if r > plan.n then
		BuyEnd(true)
		return
	end
	local j = plan.merch[r]
	local index, bundle = merchant.idx[j], merchant.bundle[j]
	if Num((Ask(_G.GetMerchantItemID, index))) ~= merchant.id[j] then
		BuyEnd(false)   -- (the merchant's list changed: nothing bought on a guess)
		return
	end
	-- items per call: at most the merchant's most, in whole purchases
	local n = min(buy.left[r], merchant.maxStack[j])
	n = n - n % bundle
	if n < bundle then
		n = bundle
	end
	BuyMerchantItem(index, n)
	-- (the purchases after a batch's first: a buy sound hooked on
	-- BuyMerchantItem may stay quiet for them, one sound a Buy click)
	M.buyingQuiet = true
	local cost = (n / bundle) * merchant.price[j]
	buy.left[r] = buy.left[r] - n
	buy.bought[r] = (buy.bought[r] or 0) + n
	buy.spent = buy.spent + cost
	buy.lastRow, buy.lastN, buy.lastCost = r, n, cost
	buy.waiting = true
	C_Timer.After(BUY_SPACING, BuyTimer)
end

-- the Buy button's click: the only way anything is bought
BuyStart = function()
	if buy.on or buy.waiting or plan.ticked == 0 or not MerchantOpen() then
		return
	end
	buy.on, buy.row, buy.spent, buy.lastRow = true, 1, 0, nil
	for r = 1, plan.n do
		buy.left[r], buy.bought[r] = (not plan.skip[r]) and plan.count[r] or 0, 0
	end
	local f = shop.frame
	if f then
		f.buy:SetText(W.Tr("Buying…"))
		f.buy:SetEnabled(false)
	end
	if state.frame then
		state.frame:RegisterEvent("UI_ERROR_MESSAGE")
	end
	BuyStep()
end

-- Not now: the panel hidden for this visit, and the reminder until a rest
-- area is entered again (the user's pick)
NotNow = function()
	shop.snoozed = true
	HidePanel()
	local rem = Reminders()
	if rem and type(rem.Dismiss) == "function" then
		rem:Dismiss(REM_KEY, "rest")
	end
end

--------------------------------------------------------------------------------
-- The Restock List window (its own window, built on its first open): the
-- catalogue by kind (2.1.18; the user, 2026-11-08: "pick and choose each
-- consumable, ammo, food etc", the pick B of restock_catalogue_sketch: the
-- kinds in a rail on the left). A rail entry per kind this character has use
-- for; its page lists the kind's items the character can use near its level
-- (NEAR_BELOW under it to NEAR_ABOVE over), and whatever is on the list or in
-- the bags, a family's "any" line first (Any drink counts them all). A row: a
-- tick (on the list or not), the item's icon, its name, what the bags hold
-- (or the level it is first used at), and while it is on the list how many to
-- keep. Pet Food (hunters): the six diets, the ones the pet out eats marked
-- (C_PetInfo.CanPetEatItem on an item of each). Items on the list that no
-- page lists (one dropped from the bags): Other. An item dropped on the window
-- is added, as before. (2.1.50, the user's pick K1 of restock_discard_sketch)
-- Never Discard: what Discard keeps for this character (its right-click), a
-- tick each to let one go; the rail shows it while something is kept.
--------------------------------------------------------------------------------

local LIST_W, LIST_H, RAIL_W, LIST_TOP, INTRO_H, LIST_FOOT = 680, 560, 168, 66, 76, 56
local SEARCH_H, HEAD_STEP = 30, 28    -- the search box's room over the line; a group's heading and its rule
local BAR = 6                         -- the thin scroll bar's width (and the room each side of it)
local LIST_EDGE = 14   -- the panel's margin in the painted look (the modern shell's: its one inset, shell:Inset)
local ROW_STEP = W.SLIDER_ROW_HEIGHT or 40
local NEAR_BELOW, NEAR_ABOVE = 20, 10   -- the levels a page lists around the character's
local ROW_INDENT = 64                   -- the name's room left of it: the tick and the icon
local win = { frame = nil, body = nil, rail = nil, pager = nil, page = nil, rows = {}, pools = { stack = {}, ammo = {},
	item = {}, keep = {} }, kind = nil, shell = nil, lines = {}, scratch = {}, seenKeys = {}, onKeys = {}, offKeys = {},
	query = nil, queryText = nil, keepLeft = {} }
local ListLayout   -- (below)

-- the kinds, in the rail's order: `any` the family lines first, `letters` the data's kinds listed, `diets` the six
-- diet lines, `classes` the classes it is for (nil: every class; its page shows too while the list holds a line of
-- it), `icon` an item of it whose icon the rail shows
local KINDS = {
	{ key = "drink", text = "Drink", any = { "d" }, letters = "d", icon = 159 },
	{ key = "food", text = "Food", any = { "f" }, letters = "f", icon = 4540 },
	{ key = "pet", text = "Pet Food", diets = true, icon = 2287, classes = { HUNTER = true } },
	{ key = "ammo", text = "Ammo", any = { "a", "b" }, letters = "ab", icon = 2512,
	  classes = { HUNTER = true, WARRIOR = true, ROGUE = true } },
	{ key = "potions", text = "Potions", letters = "p", icon = 118 },
	{ key = "elixirs", text = "Elixirs", letters = "e", icon = 2454 },
	{ key = "scrolls", text = "Scrolls", letters = "s", icon = 954 },
	{ key = "poisons", text = "Poisons", letters = "o", icon = 6947, classes = { ROGUE = true } },
	{ key = "reagents", text = "Reagents", letters = "r", icon = 17020 },
	{ key = "other", text = "Other", other = true, icon = "Interface\\Icons\\INV_Misc_Bag_08" },
	{ key = "keep", text = "Never Discard", keep = true, icon = W.IconPath("btn_discard") },
}
local KIND_OF = {}
for _, k in ipairs(KINDS) do
	KIND_OF[k.key] = k
end
local INTRO = {
	-- (the user, 2026-11-08: "make it clear somewhere in the restock list that the restock only show items which are
	-- level appropriate")
	any = "Tick what to keep and how many. Each kind shows only the items for your level, and what you carry or have "
		.. "ticked; search to find any other.",
	pet = "A diet counts every food of it in your bags, whichever pet is out.",
	other = "Items you dropped on the list. Drop any item from your bags on this window to add it.",
	search = "Results for \"%s\" in every kind. Clear the box to go back.",
	keep = "Discard never throws these away. Right-click the Discard button to keep what it would throw away; "
		.. "untick to let one go.",
	kept = "Kept", keepNote = "Also never thrown away: everything on your Restock list.",
	onList = "On your list", offList = "More for your level", offSearch = "Not on your list",
	none = "Nothing of this kind for your level yet.",
	found = "Nothing found.", prompt = "Search every kind",
}
-- a family's or a diet's tooltip (an item's is the game's own)
local FAMILY_TIP = {
	d = "Counts every drink this character can use, the older ones too, and buys the best a shop has.",
	f = "Counts every food this character can use, the older ones too, and buys the best a shop has.",
	a = "Counts every arrow this character can use, and buys the best a shop has.",
	b = "Counts every bullet this character can use, and buys the best a shop has.",
	diet = "Counts every %s in your bags, raw too, whatever its level, and buys the best a shop has for your level.",
}

local function Save()
	local key = ListKey()
	if not (key and M.db) then
		return
	end
	local parts = {}
	for i = 1, list.n do
		parts[#parts + 1] = list.key[i] .. ":" .. list.amount[i]
	end
	local text = table.concat(parts, " ")
	list.text = text
	Parse(text)
	list.version = list.version + 1
	MelloUI:NotifySettingChanged("Restock", key, text)
	Dirty()
end

-- the default amount a new line keeps
local function DefaultAmount(key)
	if FAMILY[key] then
		return FAMILY[key].amount
	end
	for _, reagents in pairs(REAGENTS) do
		for _, r in ipairs(reagents) do
			if r[1] == key then
				return r[4]
			end
		end
	end
	return min(StackSize(key), 20)
end

function M:Entries()
	EnsureList()
	return list.n
end

function M:Entry(i)
	Counted()
	return list.key[i], list.amount[i], state.have[i] or 0, state.low[i] and true or false, state.active[i] ~= false
end

-- a line added: a family letter or an item id (the list holds MAX_ENTRIES)
function M:Add(key, amount)
	EnsureList()
	if type(key) == "string" and key:match("^%d+$") then
		key = tonumber(key)
	end
	if not (FAMILY[key] or (type(key) == "number" and key > 0)) then
		return false
	end
	if Has(key) then
		return false
	end
	if list.n >= MAX_ENTRIES then
		MelloUI:Print("The restock list holds %d lines at most.", MAX_ENTRIES)
		return false
	end
	list.n = list.n + 1
	list.key[list.n], list.amount[list.n] = key, min(floor(amount or DefaultAmount(key)), MAX_AMOUNT)
	Save()
	if win.frame and win.frame:IsShown() then
		ListLayout()
	end
	return true
end

function M:Remove(i)
	EnsureList()
	if not list.key[i] then
		return false
	end
	table.remove(list.key, i)
	table.remove(list.amount, i)
	list.n = list.n - 1
	Save()
	if win.frame and win.frame:IsShown() then
		ListLayout()
	end
	return true
end

function M:SetAmount(i, amount)
	EnsureList()
	amount = Num(amount)
	if not (list.key[i] and amount) then
		return false
	end
	amount = max(0, min(floor(amount + 0.5), MAX_AMOUNT))
	if list.amount[i] == amount then
		return true
	end
	list.amount[i] = amount
	Save()
	return true
end

-- back to the class's suggestion
function M:Reset()
	local key = ListKey()
	if key and M.db and M.db[key] ~= nil then
		MelloUI:NotifySettingChanged("Restock", key, nil)
	end
	suggest.text = nil
	EnsureList()
	Dirty()
	if win.frame and win.frame:IsShown() then
		ListLayout()
	end
end

-- a line's count as its row says it: what the bags hold, or the level it waits for
local function HaveText(i)
	local key = list.key[i]
	if state.active[i] == false then
		local w = WINDOW[key]
		if w and Level() < w[1] then
			return "from level " .. w[1]
		end
		local need = type(key) == "number" and Families().level[key]
		if need and need > Level() then
			return "from level " .. need
		end
		return "not at your level"
	end
	return "in bags " .. (state.have[i] or 0)
end

-- the diets the pet out eats (C_PetInfo.CanPetEatItem on the first item of each), into out; true when it eats any
local function PetEats(out)
	wipe(out)
	local okE, exists = pcall(UnitExists, "pet")
	local pets = rawget(_G, "C_PetInfo")
	local can = type(pets) == "table" and pets.CanPetEatItem
	if not (okE and Plain(exists) and type(can) == "function") then
		return false
	end
	local F, any = Families(), false
	for d = 1, #DIETS do
		local id = F.firstOfDiet[d]
		local ok, eats = false, nil
		if id then
			ok, eats = pcall(can, id)
		end
		if ok and Plain(eats) == true then
			out[d] = true
			any = true
		end
	end
	return any
end

-- a row's line under its name: on the list, its count (or the level it waits for); else what the bags hold or the
-- level it is first used at; a diet the pet eats says so
local function RowHint(key)
	local i = Has(key)
	local text
	if i then
		text = HaveText(i)
	else
		local need = type(key) == "number" and Families().level[key]
		local n = type(key) == "number" and ItemCount(key) or (state.famHave[key] or 0)
		if need and need > Level() then
			text = "level " .. need
		elseif n > 0 then
			text = "in bags " .. n
		else
			text = ""
		end
	end
	local diet = FAMILY[key] and FAMILY[key].diet
	if diet and win.eats and win.eats[diet] then
		text = text ~= "" and (text .. ", your pet eats this") or "your pet eats this"
	end
	return text
end

local function RowName(key)
	if key == "d" then
		return "Any drink"
	elseif key == "f" then
		return "Any food"
	elseif key == "a" then
		return "Any arrows"
	elseif key == "b" then
		return "Any bullets"
	end
	return EntryName(key)
end

local function RowIcon(key)
	if type(key) == "number" then
		return ItemIcon(key)
	end
	local F = Families()
	local family = FAMILY[key]
	local id = family and family.diet and F.firstOfDiet[family.diet] or (F.rows[key] and F.rows[key][#F.rows[key]])
	return id and ItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- the keys a kind's page lists, into out: its family lines, its diets, its items near the character's level (an
-- item of a skill's -- potions, elixirs, poisons -- with no level always; `all`, a search's: every one the class can
-- use), and whatever of it is on the list or in the bags; Other: the list's items no kind knows
local SKILL_KIND = { p = true, e = true, o = true }
local function KindLines(k, out, all)
	wipe(out)
	if k.keep then
		local discard = MelloUI:GetModule("Discard")
		if discard and discard.isEnabled and discard.KeepList then
			discard.KeepList(out)
			for id in pairs(win.keepLeft) do
				if not discard.Kept(id) then
					out[#out + 1] = id
				end
			end
		end
		return out
	end
	local F, level = Families(), Level()
	for _, f in ipairs(k.any or {}) do
		out[#out + 1] = f
	end
	if k.diets then
		for d = 1, #DIETS do
			out[#out + 1] = "p" .. d
		end
	end
	for c = 1, #(k.letters or "") do
		local letter = k.letters:sub(c, c)
		for _, id in ipairs(F.rows[letter] or {}) do
			local lv = F.level[id] or 0
			local near = ClassOk(F.classes[id], F.classBit)
				and (all or (lv == 0 and SKILL_KIND[letter]) or (lv <= level + NEAR_ABOVE and lv >= level - NEAR_BELOW))
			if near or Has(id) or ItemCount(id) > 0 then
				out[#out + 1] = id
			end
		end
	end
	if k.other then
		for i = 1, list.n do
			local key = list.key[i]
			if type(key) == "number" and not F.of[key] then
				out[#out + 1] = key
			end
		end
	end
	return out
end

-- the kinds this character's rail shows: its classes' (or any kind the list holds a line of), with something to list
local function KindShown(k, class, lines)
	if #lines == 0 then
		return false
	end
	if not k.classes or k.classes[class] then
		return true
	end
	for _, key in ipairs(lines) do
		if Has(key) then
			return true
		end
	end
	return false
end

-- a row ticked: the line added with its default amount, or taken off
local function RowTicked(row, on)
	local key = row.key
	if key == nil then
		return
	end
	local i = Has(key)
	if on and not i then
		M:Add(key)
	elseif not on and i then
		M:Remove(i)
	end
end

local RANGES = {
	stack = { min = 0, max = 100, step = 5 },
	ammo = { min = 0, max = 2000, step = 200 },
	item = { min = 0, max = 100, step = 1 },
	keep = { min = 0, max = 100, step = 1 },   -- (2.1.50: Never Discard's rows, their slider hidden)
}

local function RangeOf(key)
	if FAMILY[key] then
		return FAMILY[key].range
	end
	return "item"
end

local ListDrop   -- (below)

-- a row under the mouse: an item's own tooltip (the game's), a family's or a diet's what it counts
local CatRowEnter = Shared("OnEnter on the Restock List's rows", function(row)
	local key = row.key
	if key == nil then
		return
	end
	if type(key) == "number" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		if not pcall(GameTooltip.SetItemByID, GameTooltip, key) then
			pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. key)
		end
		GameTooltip:Show()
		return
	end
	local family = FAMILY[key]
	local body = family and family.diet and string.format(FAMILY_TIP.diet, family.name:lower()) or FAMILY_TIP[key]
	W.ShowTooltip(row, RowName(key), body)
end, "script")

-- a row of the catalogue: a slider row of its range (one pool a range: a row is used again only for a key of the
-- same range), the tick and the icon left of the name
local function NewListRow(range)
	local row = nil
	-- (the slider asks its value while it is made: row is nil then)
	row = W.SliderRow(win.page, 0, "", " ", nil,
		function()
			local i = row and row.key ~= nil and Has(row.key)
			return i and list.amount[i] or 0
		end,
		function(v)
			local i = row and row.key ~= nil and Has(row.key)
			if i then
				M:SetAmount(i, v)
			end
		end,
		{ min = RANGES[range].min, max = RANGES[range].max, step = RANGES[range].step, width = 150, skin = win.shell,
		  zebra = true, indent = ROW_INDENT })
	row.tick = W.Switch(row, function()
		if row.keep then
			local discard = MelloUI:GetModule("Discard")
			return row.key ~= nil and discard and discard.Kept and discard.Kept(row.key) or false
		end
		return row.key ~= nil and Has(row.key) ~= nil
	end, function(on)
		if row.keep then
			local discard = MelloUI:GetModule("Discard")
			if row.key ~= nil and discard and discard.Keep then
				win.keepLeft[row.key] = (not on) or nil
				discard.Keep(row.key, on)
			end
			return
		end
		RowTicked(row, on)
	end)
	row.tick:SetPoint("LEFT", row, "LEFT", 12, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT", row, "LEFT", 42, 0)
	row.range = range
	-- (a row covers the page's width: an item dropped on it is added too)
	Perf.HookScript(row, "OnReceiveDrag", ListDrop)
	Perf.HookScript(row, "OnMouseUp", ListDrop)
	Perf.HookScript(row, "OnEnter", CatRowEnter)
	Perf.HookScript(row, "OnLeave", W.TipLeave)
	if row.label then
		Style(row.label, "fontText", _G.GameFontHighlight)
	end
	if row.hint then
		Style(row.hint, "fontText", _G.GameFontHighlight)
	end
	return row
end

-- the rail's entries for this character (made again at each layout; the rail pools its rows)
local function RailGroups(class)
	local entries, firstShown = {}, nil
	for _, k in ipairs(KINDS) do
		local lines = KindLines(k, {})
		if KindShown(k, class, lines) then
			entries[#entries + 1] = { key = k.key, text = k.text, icon = RowIcon(type(k.icon) == "number" and k.icon or 0) }
			if type(k.icon) == "string" then
				entries[#entries].icon = k.icon
			end
			firstShown = firstShown or k.key
		end
	end
	return { { key = "kinds", entries = entries } }, firstShown, entries
end

-- the scroll bar to the list: its range the page's height past the view, its thumb the share in view; hidden while
-- the page fits (Dungeon Info's SyncBar, the one way MelloUI's lists pair the bar with a pager)
local function SyncBar()
	local bar, pager = win.bar, win.pager
	if not bar then
		return
	end
	local Finite = MelloUI.Safe.Finite
	local view = Finite(pager.scroll:GetHeight()) or 0
	local range = max(0, (Finite(pager.canvas:GetHeight()) or 0) - view)
	-- (not laid out yet: no height to measure -- its OnSizeChanged syncs it once it has one)
	if view <= 1 or range <= 0.5 then
		bar:Hide()
		return
	end
	bar.laying = true
	bar:SetMinMaxValues(0, range)
	bar:SetValue(min(range, Finite(pager.scroll:GetVerticalScroll()) or 0))
	bar.laying = false
	bar.thumb:SetHeight(max(16, (Finite(bar:GetHeight()) or view) * view / (view + range)))
	bar:Show()
end
local BarSync = Shared("SetVerticalScroll / OnSizeChanged on the Restock List's scroll", function()
	SyncBar()
end, "script")
local BarDragged = Shared("OnValueChanged on the Restock List's scroll bar", function(bar, value)
	if not bar.laying then
		win.pager:ScrollTo(MelloUI.Safe.Finite(value) or 0, true)
	end
end, "script")

-- two keys by their rows' names (the ticked ones' order), then by key
local function ByName(a, b)
	local na, nb = RowName(a):lower(), RowName(b):lower()
	if na ~= nb then
		return na < nb
	end
	return tostring(a) < tostring(b)
end

-- the page of the kind on show onto its rows (the counts in their hints), the rail with it; a search's matches
-- instead while the search box holds a text
ListLayout = function()
	local f = win.frame
	if not f then
		return
	end
	Counted()
	local class = PlayerClass() or ""
	local groups, first, entries = RailGroups(class)
	win.shownKinds = entries
	local shown = false
	for _, e in ipairs(entries) do
		if e.key == win.kind then
			shown = true
		end
	end
	if not shown then
		win.kind = first
	end
	win.rail:SetGroups(groups)
	if win.kind then
		win.rail:Select(win.kind, true)
	end
	local k = KIND_OF[win.kind or ""]
	local query = win.query
	win.eats = win.eats or {}
	local eats = (query or (k and k.diets)) and PetEats(win.eats)
	if not eats then
		wipe(win.eats)
	end
	-- the keys: the kind's page, or a search's matches in every kind the rail shows (each once)
	local lines = win.lines
	if query then
		wipe(lines)
		local seen = win.seenKeys
		wipe(seen)
		for _, e in ipairs(entries) do
			for _, key in ipairs(e.key == "keep" and Pick.NONE or KindLines(KIND_OF[e.key], win.scratch, true)) do
				if not seen[key] and RowName(key):lower():find(query, 1, true) then
					seen[key] = true
					lines[#lines + 1] = key
				end
			end
		end
	else
		KindLines(k or KINDS[1], lines)
	end
	-- split: the ticked on top by name, the rest below in the kind's order
	local on, off = win.onKeys, win.offKeys
	wipe(on)
	wipe(off)
	local keepPage = not query and k and k.keep and true or false
	for _, key in ipairs(lines) do
		if keepPage or Has(key) then
			on[#on + 1] = key
		else
			off[#off + 1] = key
		end
	end
	table.sort(on, ByName)
	local used = { stack = 0, ammo = 0, item = 0, keep = 0 }
	for _, row in ipairs(win.rows) do
		row.key = nil
		row:Hide()
	end
	wipe(win.rows)
	local y = 0
	local function Lay(key)
		local range = keepPage and "keep" or RangeOf(key)
		local pool = win.pools[range]
		used[range] = used[range] + 1
		local row = pool[used[range]]
		if not row then
			row = NewListRow(range)
			row.keep = range == "keep"
			pool[used[range]] = row
		end
		row.key = key
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", win.page, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", win.page, "RIGHT", 0, 0)
		row.label:SetText(RowName(key))
		if row.hint then
			row.hint:SetText(RowHint(key))
		end
		MelloUI.Icons.Set(row.icon, RowIcon(key), 24)
		local n = #win.rows + 1
		if row.band then
			row.band:SetShown(n % 2 == 1)   -- (a neutral stripe under every other row)
		end
		local ticked = Has(key) ~= nil
		if keepPage then
			local discard = MelloUI:GetModule("Discard")
			ticked = discard and discard.Kept and discard.Kept(key) or false
		end
		row.tick:SetValue(ticked, true)
		local slider = W.ControlOf(row)
		if slider then
			slider:SetShown(ticked and not keepPage)
			if ticked and slider.Refresh then
				slider:Refresh()
			end
		end
		row:Show()
		win.rows[n] = row
		y = y + ROW_STEP
	end
	local function Heading(fs, rule)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", win.page, "TOPLEFT", 12, -(y + 8))
		fs:Show()
		if rule then
			rule:ClearAllPoints()
			rule:SetPoint("TOPLEFT", win.page, "TOPLEFT", 8, -(y + 2))
			rule:SetPoint("RIGHT", win.page, "RIGHT", -8, 0)
			rule:Show()
		end
		y = y + HEAD_STEP
	end
	win.headOn:Hide()
	win.headOff:Hide()
	win.rule:Hide()
	win.headOn:SetText(keepPage and INTRO.kept or INTRO.onList)
	if #on > 0 then
		Heading(win.headOn)
		for _, key in ipairs(on) do
			Lay(key)
		end
	end
	if #off > 0 then
		if #on > 0 then
			win.headOff:SetText(query and INTRO.offSearch or INTRO.offList)   -- (a search's are of any level)
			Heading(win.headOff, win.rule)
		end
		for _, key in ipairs(off) do
			Lay(key)
		end
	end
	-- the page's line over its rows: what a tick does (the pet's diets: what it eats; a search: what it looked for)
	local intro = INTRO.any
	if query then
		intro = string.format(INTRO.search, win.queryText or query)
	elseif k and k.diets then
		local eaten = nil
		for d = 1, #DIETS do
			if win.eats[d] then
				eaten = eaten and (eaten .. ", " .. DIETS[d]) or DIETS[d]
			end
		end
		intro = (eaten and ("Your pet eats: " .. eaten .. ". ") or "Call your pet to see what it eats. ") .. INTRO.pet
	elseif k and k.other then
		intro = INTRO.other
	elseif keepPage then
		intro = INTRO.keep
	end
	win.intro:SetText(intro)
	-- (2.1.50) the kept page's last line: the Restock list is kept too; its footer the kept count
	if keepPage and not win.keepNote then
		win.keepNote = Style(W.Text(win.page, "GameFontHighlight", INTRO.keepNote, "text"), "fontText", _G.GameFontHighlight)
	end
	if win.keepNote then
		win.keepNote:SetShown(keepPage)
		if keepPage then
			win.keepNote:ClearAllPoints()
			win.keepNote:SetPoint("TOPLEFT", win.page, "TOPLEFT", 12, -(y + 12))
			y = y + 12 + 20
		end
	end
	win.reset:SetShown(not keepPage)
	win.empty:SetText(query and INTRO.found or INTRO.none)
	win.empty:SetShown(#win.rows == 0)
	win.pager:SetPageHeight(win.page, max(ROW_STEP, y) + 8)
	SyncBar()
	local below = floor(Below() * 100 + 0.5)
	if keepPage then
		local n = 0
		local discard = MelloUI:GetModule("Discard")
		for _, key in ipairs(on) do
			if discard and discard.Kept(key) then
				n = n + 1
			end
		end
		win.foot:SetText(n == 1 and "1 item never thrown away." or string.format("%d items never thrown away.", n))
	else
		win.foot:SetText(string.format("%d of %d lines on the list. Reminded below %d%%.", list.n, MAX_ENTRIES, below))
	end
end

-- a count while the window is open: the hints
ListCounted = function()
	if not (win.frame and win.frame:IsShown()) then
		return
	end
	for _, row in ipairs(win.rows) do
		if row.key ~= nil and row.hint then
			row.hint:SetText(RowHint(row.key))
		end
	end
end

-- an item dropped on the window (from the bags, or a shop's item picked up)
ListDrop = Shared("OnReceiveDrag / OnMouseUp on the Restock List", function()
	local kind, a = Ask(GetCursorInfo)
	if IsSecret(kind) or IsSecret(a) then
		return
	end
	local id = nil
	if kind == "item" then
		id = Num(a)
	elseif kind == "merchant" then
		id = Num((Ask(_G.GetMerchantItemID, Num(a))))
	end
	if id then
		Ask(_G.ClearCursor)
		if M:Add(id) then
			MelloUI:PlayUISound("check_on")
		end
	end
end, "script")

local ListShown = Shared("OnShow on the Restock List", function()
	ListLayout()
end, "script")


-- names the client had not loaded yet arrive while a search runs: the matches again on the next frame
local function Renamed()
	if win.query and win.frame and win.frame:IsShown() then
		ListLayout()
	end
end
local NamesArrived = Shared("OnEvent on the Restock List's search (item names)", function()
	MelloUI.Kit:NextFrame("Restock List search names", Renamed)
end, "script")

local function Listening(on)
	local f = win.names
	if not f then
		return
	end
	if on then
		f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	else
		f:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
end

-- the search box's text: a search in every kind (lower case, trimmed), none when empty
local SearchChanged = Shared("OnTextChanged on the Restock List's search", function(box)
	local t = Text(box:GetText()) or ""
	t = t:match("^%s*(.-)%s*$") or ""
	local query = t ~= "" and t:lower() or nil
	if query == win.query then
		return
	end
	win.query, win.queryText = query, t
	Listening(query ~= nil and win.frame and win.frame:IsShown())
	win.pager:ScrollTo(0, true)
	ListLayout()
end, "script")
local SearchEscape = Shared("OnEscapePressed on the Restock List's search", function(box)
	box:SetText("")
	box:ClearFocus()
end, "script")
local SearchEnter = Shared("OnEnterPressed on the Restock List's search", function(box)
	box:ClearFocus()
end, "script")
local ListHidden = Shared("OnHide on the Restock List", function()
	Listening(false)
	wipe(win.keepLeft)   -- (2.1.50: the rows let go on Never Discard gone at the next open)
end, "script")

-- a kind picked in the rail: its page, at its top (a search let go)
local RailPicked = Shared("onSelect of the Restock List's kinds", function(_, key)
	local searching = win.query ~= nil
	if key ~= win.kind or searching then
		wipe(win.keepLeft)
		win.kind = key
		win.pager:ScrollTo(0, true)
		if searching then
			-- (the search let go here: the box's OnTextChanged then finds nothing changed)
			win.query, win.queryText = nil, nil
			Listening(false)
			win.search:SetText("")
		end
		ListLayout()
	end
end)

-- Suggested replaces the list, once the player says so in MelloUI's own
-- dialog (MelloUI:Confirm, Modules/KitWindow.lua: never the game's popup,
-- which blocks the game's own calls with the Gamepad UI on)
local function ResetAccepted()
	MelloUI:PlayUISound("page")
	M:Reset()
end
local RESET_ASK = { text = "Replace your restock list with the suggestions for your class?", accept = "Replace",
	cancel = "Cancel", onAccept = ResetAccepted }
local ResetClick = Shared("OnClick on the Restock List's Suggested", function()
	MelloUI:Confirm(RESET_ASK)
end, "script")

-- (2.1.37; the user, 2026-11-10, after the map's grip: "what can we do for other windows then?") the list window made
-- taller by its grip, from the standard height up as far as the screen has room (its width is its page's)
local Taller = {}

function Taller.Start()
	return Num(win.frame:GetHeight()) or LIST_H
end

function Taller.Drag(from, _, gy)
	win.frame:SetHeight(max(LIST_H, floor((from or LIST_H) + gy)))
	if win.frame:IsShown() then
		ListLayout()
	end
end

function Taller.Stop()
	if M.db then
		local h = floor(win.frame:GetHeight() + 0.5)
		M.db.listH = h > LIST_H and h or false
	end
end

function Taller.Reset()
	if M.db then
		M.db.listH = false
	end
	win.frame:SetHeight(LIST_H)
	if win.frame:IsShown() then
		ListLayout()
	end
end

local function BuildList()
	local f = CreateFrame("Frame", "MelloUIRestockList", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(LIST_W, max(LIST_H, Num(M.db and M.db.listH) or 0))
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	-- (its own scripts before the shell's hooks: SetScript drops hooks)
	Perf.SetScript(f, "OnShow", ListShown)
	Perf.SetScript(f, "OnReceiveDrag", ListDrop)
	Perf.SetScript(f, "OnMouseUp", ListDrop)
	win.frame = f
	win.shell = MelloUI.Kit:OwnWindow(f, {
		area = "config", ring = { at = "tl" }, plate = "rail", title = "Restock List",
		close = true, escape = true, fit = true, sounds = true,
		mover = { key = "MelloUIRestockList", label = "Restock list", page = "Restock", plainDrag = "always" },
	})
	-- the kinds: the configurator's own side list (W.NavRail), in its box
	win.rail = W.NavRail(f, { width = RAIL_W, rowHeight = 34, iconSize = 22, scroll = false, box = true,
		skin = win.shell, onSelect = RailPicked })
	-- the text sits on the dark inner panel (the eye strain rule), placed by
	-- the look (Lay, below)
	local body = CreateFrame("Frame", nil, f)
	local fill = W.Solid(body, "BACKGROUND", "innerPanel", 0.85)
	fill:SetAllPoints(body)
	body:EnableMouse(true)
	Perf.SetScript(body, "OnReceiveDrag", ListDrop)
	Perf.SetScript(body, "OnMouseUp", ListDrop)
	win.body = body
	-- the search box over the line (the configurator's own: SearchBoxTemplate made flat, W.FlatSearch)
	local search = CreateFrame("EditBox", nil, body, "SearchBoxTemplate")
	search:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -6)
	search:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -6)
	search:SetHeight(22)
	search:SetAutoFocus(false)
	search:SetMaxLetters(40)
	W.Paint(search, "text", "text")   -- (what is typed, in the palette's text colour)
	if search.Instructions then
		search.Instructions:SetText(INTRO.prompt)
	end
	Perf.HookScript(search, "OnTextChanged", SearchChanged)
	Perf.SetScript(search, "OnEscapePressed", SearchEscape)
	Perf.SetScript(search, "OnEnterPressed", SearchEnter)
	W.FlatSearch(search)
	win.search = search
	win.names = CreateFrame("Frame")
	Perf.SetScript(win.names, "OnEvent", NamesArrived)
	Perf.HookScript(f, "OnHide", ListHidden)
	local intro = Style(W.Text(body, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	intro:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -(SEARCH_H + 6))
	intro:SetPoint("RIGHT", body, "RIGHT", -12, 0)
	intro:SetJustifyH("LEFT")
	win.intro = intro
	-- the rows on one page of a pager: its wheel glides
	win.pager = W.Pager(body)
	win.pager.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -INTRO_H)
	win.pager.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -(4 + 2 * BAR), 4)
	-- MelloUI's thin scroll bar beside it (W.ThinScrollBar), in step with the scroll
	local bar = W.ThinScrollBar(body, BAR)
	bar:SetPoint("TOPLEFT", win.pager.scroll, "TOPRIGHT", BAR / 2, 0)
	bar:SetPoint("BOTTOMLEFT", win.pager.scroll, "BOTTOMRIGHT", BAR / 2, 0)
	bar:Hide()
	Perf.SetScript(bar, "OnValueChanged", BarDragged)
	win.bar = bar
	Perf.hooksecurefunc(win.pager.scroll, "SetVerticalScroll", BarSync)
	Perf.SetScript(win.pager.scroll, "OnSizeChanged", BarSync)
	win.page = win.pager:NewPage()
	-- the two groups' headings and the rule between them (ListLayout places them)
	win.headOn = Style(W.Text(win.page, "GameFontNormal", INTRO.onList, "selectedTrim"), "fontText", _G.GameFontNormal)
	win.headOff = Style(W.Text(win.page, "GameFontNormal", INTRO.offList, "selectedTrim"), "fontText", _G.GameFontNormal)
	win.rule = W.Solid(win.page, "ARTWORK", "border", 0.8)
	win.rule:SetHeight(1)
	win.empty = Style(W.Text(body, "GameFontHighlight", INTRO.none, "text"),
		"fontText", _G.GameFontHighlight)
	win.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 22, -(INTRO_H + 12))
	win.foot = Style(W.Text(f, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	win.reset = W.Button(f, "Suggested", 100, win.shell, { onClick = ResetClick })
	-- the rail, the panel and the controls under them on the look's inset (onelook, the modern shell: under its strip
	-- on the one inset; the painted one: under the corner ring), at every look switch
	local function Lay(sh)
		local edge, top = sh:Inset(LIST_EDGE, -LIST_TOP)
		win.rail.box:ClearAllPoints()
		win.rail.box:SetPoint("TOPLEFT", f, "TOPLEFT", edge, top)
		win.rail.box:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", edge, LIST_FOOT)
		body:SetPoint("TOPLEFT", f, "TOPLEFT", edge + RAIL_W + 8, top)
		body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -edge, LIST_FOOT)
		win.foot:ClearAllPoints()
		win.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", edge + 4, 24)
		win.reset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(edge + 4), 18)
		-- (the page a width of its own, as the configurator's and the installer's: the pager's canvas takes the page's
		-- width when it shows it, and a page held by one point has none -- the rows were laid in a canvas 0 wide, unseen;
		-- the user's shot, 2026-11-08: the Drink page empty) the body's width less the scroll frame's 4 on each side
		local pageW = LIST_W - 2 * edge - RAIL_W - 8 - 8 - 2 * BAR   -- (2.1.18: and the scroll bar's room)
		win.page:SetWidth(pageW)
		win.pager.canvas:SetWidth(pageW)
		if f:IsShown() then
			ListLayout()
		end
	end
	Lay(win.shell)
	win.pager:Show(win.page, 0, true)
	win.shell:OnKit(Lay)
	W.Dress(f, win.shell)
	-- (2.1.37) the size grip (W.SizeGrip's drag): taller, more of the list in view
	win.grip = W.SizeGrip(f, { corner = "auto", level = 30, tip = "Drag to make the list taller",
		body = "Right-click: the standard size.",
		size = { start = Taller.Start, drag = Taller.Drag, stop = Taller.Stop, reset = Taller.Reset } })
	return f
end

-- (2.1.50, Discard's Consumables Too: never what the list keeps) whether a line of this character's list keeps the
-- item: its own line; its family's (drink, food, ammunition, reagents) for the best level of that family in the bags --
-- what the line tops up; the older ones may go, as the shop never offers them again (no downgrades, N1) -- or its
-- diet's (a pet's food, any level)
function M:Counts(id)
	if type(id) ~= "number" then
		return false
	end
	Counted()
	EnsureList()
	if list.items[id] then
		return true
	end
	local F = Families()
	local letter = F.of[id]
	if letter and FAMILY[letter] and Has(letter) and F.level[id] <= Level() and ClassOk(F.classes[id], F.classBit)
		and F.level[id] >= (state.famBest[letter] or 0) then
		return true
	end
	local diet = F.diet[id]
	return diet ~= nil and Has(DIET_KEY[diet]) ~= nil
end

-- (2.1.50) Discard's kept items changed (its right-click, a tick here): the window again while it is open
function M:KeepChanged()
	if win.frame and win.frame:IsShown() then
		ListLayout()
	end
end

function M:OpenList()
	local f = win.frame or BuildList()
	if f:IsShown() then
		ListLayout()
		return
	end
	f:Show()
end
M.listWindow = win   -- (read by the tests: the kind on show, the kinds shown, the rows)

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- the bags are listened to only while the list has a line
local function Listen()
	local f = state.frame
	if not f then
		return
	end
	if not (M.isEnabled and state.ready) then
		f:UnregisterEvent("BAG_UPDATE_DELAYED")
		f:UnregisterEvent("PLAYER_LEVEL_UP")
		f:UnregisterEvent("PLAYER_REGEN_ENABLED")
		f:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
		return
	end
	EnsureList()
	if list.n > 0 then
		f:RegisterEvent("BAG_UPDATE_DELAYED")
	else
		f:UnregisterEvent("BAG_UPDATE_DELAYED")
	end
	f:RegisterEvent("PLAYER_LEVEL_UP")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- (a hunter's suggestion follows the ranged weapon until the list is edited)
	if PlayerClass() == "HUNTER" and not Stored() then
		f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	else
		f:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	end
end

local function OnEvent(_, event, arg1)
	if event == "BAG_UPDATE_DELAYED" then
		Dirty()
	elseif event == "MERCHANT_SHOW" then
		shop.open, shop.snoozed, shop.done, shop.learned = true, false, false, false
		ShopEvents(true)
		-- the frame after (Vendor's repair and junk sale go first)
		MelloUI.Kit:NextFrame("Restock shop", ShopSoon)
	elseif event == "MERCHANT_CLOSED" then
		shop.open = false
		ShopEvents(false)
		HidePanel()
		BuyEnd(false)
	elseif event == "MERCHANT_UPDATE" or event == "PLAYER_MONEY" then
		if not buy.on then
			ShopRefresh()
		end
	elseif event == "UI_ERROR_MESSAGE" then
		-- the game refused a purchase (no gold, bags full): the last one sent
		-- is not counted, and it stops there
		if buy.on then
			local r = buy.lastRow
			if r then
				buy.lastRow = nil
				buy.bought[r] = max(0, (buy.bought[r] or 0) - buy.lastN)
				buy.spent = max(0, buy.spent - buy.lastCost)
			end
			BuyEnd(false)
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- a name the reminder's text waited for (one of the list's items)
		if list.items[Num(arg1) or 0] then
			WaitForNames(false)
			Changed()
		end
	elseif event == "PLAYER_LEVEL_UP" then
		suggest.text = nil
		Dirty()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		if Num(arg1) == 18 then
			suggest.text = nil
			Dirty()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if state.dirty then
			Dirty()
		end
	end
end

local function Ready()
	state.waiting = false
	if state.ready or not M.isEnabled then
		return
	end
	state.ready = true
	Listen()
	state.told, state.toldActive = nil, nil
	if InCombat() then
		return   -- (a login into a fight: counted once it is over, PLAYER_REGEN_ENABLED)
	end
	Count()
	Changed()
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	if not state.frame then
		state.frame = CreateFrame("Frame")
		Perf.SetScript(state.frame, "OnEvent", OnEvent)
		MelloUI:Profile("Restock", "bag and merchant events", state.frame)
	end
	state.frame:RegisterEvent("MERCHANT_SHOW")
	state.frame:RegisterEvent("MERCHANT_CLOSED")
	-- the spec to the widget now, in the login pass (a table: the widget
	-- builds nothing before its login moment, 8 s after entering the world;
	-- registered later, that moment would wait 8 s more)
	Register(true)
	-- the Reminders page's switch, and a profile or late settings load
	MelloUI:On("module", function(name)
		if name == "Reminders" then
			Changed()
		end
	end, "Restock")
	MelloUI:On("restart", function()
		suggest.text = nil
		Dirty()
		Changed()
	end, "Restock")
	if state.ready then
		Listen()
		Dirty()
		Changed()
	elseif not state.waiting then
		-- the first count and the reminder, 8 s into the world: nothing in the
		-- login frames
		state.waiting = true
		C_Timer.After(READY_DELAY, Ready)
	end
end

-- Off: the events, the shop and the spec taken back. A restart (a profile
-- load or the settings adopted late: OnDisable then OnEnable, the module
-- still on) keeps the shop as it is and the spec registered, so the reminder
-- is not raised again and its Not now stays (as Modules/Reminders.lua); a
-- profile that switches Restock off is a real off (isEnabled false then)
function M:OnDisable()
	if MelloUI.restartingModules and M.isEnabled then
		Listen()
		return
	end
	local f = state.frame
	if f then
		f:UnregisterEvent("MERCHANT_SHOW")
		f:UnregisterEvent("MERCHANT_CLOSED")
		ShopEvents(false)
	end
	Listen()
	WaitForNames(false)
	shop.open = false
	HidePanel()
	BuyEnd(false)
	MelloUI:Off("Restock")
	-- the spec taken back: the Errands row routes on its own, and no stale
	-- line is left there
	Register(false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "shopPanel" then
		if not value then
			HidePanel()
		else
			ShopRefresh()
		end
	elseif key == "below" then
		Dirty()
		if state.ready then
			Count()
		end
		-- (the open Restock List's intro says the share: laid again)
		if win.frame and win.frame:IsShown() then
			ListLayout()
		end
	elseif key == ListKey() then
		EnsureList()
		Listen()
		Dirty()
	end
end

_G.SLASH_MELLORESTOCK1 = "/restock"
SlashCmdList.MELLORESTOCK = function()
	M:OpenList()
end
