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
-- The reminder's switch is the Reminders page's "Restock" (remind_restock,
-- as remind_<key> is every reminder's); the spec is taken back while the
-- module is off.
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
	desc = "Keeps drink, food, ammunition and reagents in your bags: a reminder when one runs low (with Reminders on), and at a shop a list of what to buy, bought only when you click Buy.",
	icon = "Interface\\Icons\\INV_Drink_07",
	flavour = "Water, bread and arrows, topped up before they run out.",
	role = "feature",
	-- (no group: its rows sit on the Reminders page, Modules/Reminders.lua)
	keep = { "^list_" },   -- each character's own list (ListKey): never in a profile, never wiped by one
	enabledByDefault = true,
	defaults = {
		below = 0.5,
		shopPanel = true,
	},
	-- (no header and no switch of its own for the reminder: the Reminders page
	-- lays these rows under its "Restock" switch, remind_restock)
	options = {
		{ type = "slider", key = "below", name = "Remind Below", new = "0.14.0", min = 0.25, max = 0.75, step = 0.05, percent = true,
		  desc = "You are reminded when a line drops below this share of its amount: at 50 %, a line of 20 water reminds you at 9. At a shop it is bought back up to the full amount." },
		{ type = "toggle", key = "shopPanel", name = "Shopping List At The Shop", new = "0.14.0",
		  desc = "At a merchant who sells what you are low on, a small list beside the shop window: each item, how many and the price, and the total. Nothing is bought until you click Buy." },
		{ type = "button", name = "Restock List", text = "Edit", new = "0.14.0",
		  desc = "What to keep in your bags and how many. Each character has its own list; a new one starts with suggestions for its class. Also /restock.",
		  onClick = function(module) module:OpenList() end },
	},
})
MelloUI.Restock = M
M.buyingQuiet = false   -- (read only: set by the purchases, below)

local REM_KEY = "restock"
local ICON = "Interface\\Minimap\\Tracking\\Food"
local URGENCY = 50        -- the widget's order (higher first): broken gear 100, Repair 40, Mail 20, Trainer 10
local READY_DELAY = 8     -- s into the world before the first count and the reminder (nothing in the login frames)
local MAX_ENTRIES = 12    -- lines on a list
local MAX_AMOUNT = 5000
local BUY_SPACING = 0.2   -- s between two purchases
local LOW_DEFAULT = 0.5   -- Remind Below: half (the user's pick)
local ORDER = "dfabr"     -- the families, in the data's order

-- the families: their names, the amount a new line keeps, and the list
-- window's slider (step, top)
local FAMILY = {
	d = { name = "Drink", word = "drink", amount = 20, step = 5, top = 100, range = "stack" },
	f = { name = "Food", word = "food", amount = 20, step = 5, top = 100, range = "stack" },
	a = { name = "Arrows", word = "arrows", amount = 1000, step = 200, top = 2000, range = "ammo" },
	b = { name = "Bullets", word = "bullets", amount = 1000, step = 200, top = 2000, range = "ammo" },
	r = { name = "Class reagents", word = "reagents", amount = 10, step = 1, top = 100, range = "item" },
}

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
	fam = { of = {}, level = {}, stack = {}, classes = {}, classBit = false, shipped = nil }
	local data = rawget(_G, "MelloUI_QuestListData")
	local items = type(data) == "table" and data.restockItems
	if type(items) == "table" then
		for i = 1, #ORDER do
			local letter = ORDER:sub(i, i)
			local rows = items[letter]
			if type(rows) == "table" then
				for _, row in ipairs(rows) do
					local id = row[1]
					if type(id) == "number" and not fam.of[id] then
						fam.of[id], fam.level[id], fam.stack[id], fam.classes[id] = letter, row[2] or 0, row[3] or 20, row[5] or 0
					end
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

-- a line counts at this level (a reagent only in its levels)
local function Active(key, level)
	local w = type(key) == "number" and WINDOW[key]
	if not w then
		return true
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
local function CountFamilies(level)
	local F = Families()
	local famHave, seen = state.famHave, state.seen
	famHave.d, famHave.f, famHave.a, famHave.b, famHave.r = 0, 0, 0, 0, 0
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
			local letter = id and F.of[id]
			if letter and seen[id] ~= pass then
				seen[id] = pass
				if F.level[id] <= level and ClassOk(F.classes[id], F.classBit) then
					famHave[letter] = famHave[letter] + ItemCount(id)
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

-- (the reminder's own switch is the core's: the Reminders setting
-- remind_restock, read by the widget before it asks this; the Reminders
-- page's module switch off, none of its reminders is wanted)
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
	local P = MelloUI.Palette
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
-- lines as the click's route does (ReachOpts). No `enabled`: the widget's
-- own remind_restock is the switch
local SPEC = {
	key = REM_KEY, label = "Restock", icon = ICON, text = RemText, urgency = URGENCY, check = RemActive,
	when = {},   -- (Core's moments: login, a rest area, a zone; this module tells it of every change of its own)
	onClick = RemClick, persistent = RemPersistent, tooltip = RemTooltip,
	dismiss = "rest",   -- Not now: until a rest area is entered again (the user's pick)
	hint = "Click: the way to the nearest shop that sells it",
	kind = "vendor", letters = nil, skip = nil, extra = nil,
}
M.SPEC = SPEC   -- (read only: the tests, a dump)

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
			if F.of[id] or list.items[id] then
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
	for j = 1, merchant.n do
		local id = merchant.id[j]
		local letter = F.of[id]
		if letter then
			s[letter] = true
		end
		if list.items[id] then
			items = items and (items .. "," .. id) or tostring(id)
		end
	end
	local sells = (s.d and "d" or "") .. (s.f and "f" or "") .. (s.a and "a" or "") .. (s.b and "b" or "") .. (s.r and "r" or "")
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
	for i = 1, n do
		local key = keys[i]
		if type(key) == "number" then
			if F.of[key] then
				s[F.of[key]] = true
			end
			items = true
		else
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
				-- are Services' own filter, by `sells`)
				if items and type(e.items) == "string" and e.items ~= "" then
					for i = 1, n do
						local key = keys[i]
						if type(key) == "number" and not F.of[key] and ("," .. e.items .. ","):find("," .. key .. ",", 1, true) then
							route.extra[#route.extra + 1] = { name = e.name, sub = e.sub or "", mapID = e.mapID, x = e.x, y = e.y }
							break
						end
					end
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
local function BestFor(key, level)
	local F, m = Families(), merchant
	local best, bestLevel, bestUnit = nil, -1, -1
	for j = 1, m.n do
		local id = m.id[j]
		if m.ok[j] then
			if type(key) == "number" then
				if id == key then
					return j
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
	plan.n, plan.total, plan.short, plan.anyLow = 0, 0, nil, false
	local money = Money()
	plan.money = money
	local level = Level()
	local general, quiver, pouch = FreeSlots()
	local F, m = Families(), merchant
	for e = 1, list.n do
		local key, amount, have = list.key[e], list.amount[e], state.have[e] or 0
		local j = state.active[e] and amount > have and BestFor(key, level) or nil
		if j and not Planned(j) then
			local id, bundle, price = m.id[j], m.bundle[j], m.price[j]
			local buys = ceil((amount - have) / bundle)
			local avail = m.avail[j]
			if avail and avail >= 0 and buys > avail then
				buys = avail
			end
			-- the bags: what fits on this item's stacks and in the free slots
			-- it may take (ammunition: its quiver or pouch first)
			local stack = StackSize(id)
			local own = ItemCount(id) % stack
			local room = own > 0 and (stack - own) or 0
			local letter = F.of[id]
			local special = letter == "a" and quiver or letter == "b" and pouch or 0
			local fits = room + (general + special) * stack
			if buys * bundle > fits then
				buys = floor(fits / bundle)
				plan.short = "bags"
			end
			if money and price > 0 then
				local afford = floor((money - plan.total) / price)
				if buys > afford then
					buys = max(0, afford)
					plan.short = plan.short or "gold"
				end
			end
			if buys > 0 then
				local items = buys * bundle
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
				local r = plan.n + 1
				plan.n = r
				plan.merch[r], plan.entry[r], plan.count[r], plan.cost[r] = j, e, items, buys * price
				plan.total = plan.total + buys * price
				if state.low[e] then
					plan.anyLow = true
				end
			end
		end
	end
end

-- the panel ---------------------------------------------------------------

-- (a row for every line a list may hold: every item Buy buys is shown with
-- its amount and price; 36 + 12 x 26 + 74 = 422, beside the 444 of the shop)
local PANEL_W, PAD, HEAD, ROW_H, FOOT, MAX_ROWS = 320, 12, 36, 26, 74, MAX_ENTRIES
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

local function ShopRow(f, i)
	local row = CreateFrame("Frame", nil, f)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(HEAD + (i - 1) * ROW_H))
	row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	if i % 2 == 1 then
		-- a neutral stripe under every other row (WINDOW-RULES 2e)
		row.band = W.Solid(row, "BACKGROUND", "mainWindow", 0.85)
		row.band:SetAllPoints(row)
	end
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
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
	f.note = Style(W.Text(f, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	f.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 34)
	f.note:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	f.note:SetWordWrap(false)
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
				row.amount:SetText("+" .. count .. " (have " .. have .. ")")
			end
			if row.costWas ~= plan.cost[i] then
				row.costWas = plan.cost[i]
				row.price:SetText(CoinText(plan.cost[i]))
			end
			row:Show()
		else
			row.planRow = nil
			row:Hide()
		end
	end
	f:SetHeight(HEAD + shown * ROW_H + FOOT)
	if f.totalWas ~= plan.total or f.moneyWas ~= plan.money then
		f.totalWas, f.moneyWas = plan.total, plan.money
		local text = "Total: " .. CoinText(plan.total)
		if plan.money then
			text = text .. "   Left after: " .. CoinText(max(0, plan.money - plan.total))
		end
		f.total:SetText(text)
	end
	local note = plan.short == "bags" and "Not all of it fits in your bags."
		or plan.short == "gold" and "Not enough gold for all of it." or ""
	if f.noteWas ~= note then
		f.noteWas = note
		f.note:SetText(note)
	end
	if not buy.on then
		f.buy:SetText("Buy")
		f.buy:SetEnabled(plan.n > 0)
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
	-- Report In Chat)
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
	if buy.on or buy.waiting or plan.n == 0 or not MerchantOpen() then
		return
	end
	buy.on, buy.row, buy.spent, buy.lastRow = true, 1, 0, nil
	for r = 1, plan.n do
		buy.left[r], buy.bought[r] = plan.count[r], 0
	end
	local f = shop.frame
	if f then
		f.buy:SetText("Buying…")
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
-- The Restock List window (its own window, built on its first open)
--------------------------------------------------------------------------------

local LIST_W, LIST_TOP, INTRO_H, LIST_FOOT = 480, 66, 44, 56
local ROW_STEP = W.SLIDER_ROW_HEIGHT or 40
local win = { frame = nil, body = nil, rows = {}, pools = { stack = {}, ammo = {}, item = {} }, addValues = {}, shell = nil }
local ListLayout   -- (below)

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

local function HaveText(i)
	local key = list.key[i]
	if state.active[i] == false then
		local w = WINDOW[key]
		if w and Level() < w[1] then
			return "from level " .. w[1]
		end
		return "not at your level"
	end
	return "have " .. (state.have[i] or 0)
end

-- a line's row in the window: a slider row of the line's range (one pool a
-- range: a row is used again only for a line of the same range) and a
-- Remove button
local RemoveClick = Shared("OnClick on the Restock List's Remove", function(button)
	local row = button.restockRow
	if row and row.line then
		MelloUI:PlayUISound("check_off")
		M:Remove(row.line)
	end
end, "script")

local function RangeOf(key)
	if FAMILY[key] then
		return FAMILY[key].range
	end
	return "item"
end

local RANGES = {
	stack = { min = 0, max = 100, step = 5 },
	ammo = { min = 0, max = 2000, step = 200 },
	item = { min = 0, max = 100, step = 1 },
}

local ListDrop   -- (below)

local function NewListRow(range)
	local row = nil
	-- (the slider asks its value while it is made: row is nil then)
	row = W.SliderRow(win.body, 0, "", "have 0", nil,
		function() return row and row.line and list.amount[row.line] or 0 end,
		function(v) if row and row.line then M:SetAmount(row.line, v) end end,
		{ min = RANGES[range].min, max = RANGES[range].max, step = RANGES[range].step, width = 150, skin = win.shell,
		  zebra = true })
	local slider = W.ControlOf(row)
	if slider then
		slider:ClearAllPoints()
		slider:SetPoint("RIGHT", row, "RIGHT", -108, 0)
	end
	local remove = W.Button(row, "Remove", 70, win.shell, { onClick = RemoveClick })
	remove:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	remove.restockRow = row
	row.remove = remove
	row.range = range
	-- (a line covers the body's width: an item dropped on it is added too)
	Perf.HookScript(row, "OnReceiveDrag", ListDrop)
	Perf.HookScript(row, "OnMouseUp", ListDrop)
	if row.label then
		Style(row.label, "fontText", _G.GameFontHighlight)
	end
	if row.hint then
		Style(row.hint, "fontText", _G.GameFontHighlightSmall)
	end
	return row
end

-- the lines onto the rows (the counts in their hints)
ListLayout = function()
	local f = win.frame
	if not f then
		return
	end
	Counted()
	local used = { stack = 0, ammo = 0, item = 0 }
	for _, row in ipairs(win.rows) do
		row.line = nil
		row:Hide()
	end
	wipe(win.rows)
	for i = 1, list.n do
		local key = list.key[i]
		local range = RangeOf(key)
		local pool = win.pools[range]
		used[range] = used[range] + 1
		local row = pool[used[range]]
		if not row then
			row = NewListRow(range)
			pool[used[range]] = row
		end
		row.line = i
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", win.body, "TOPLEFT", 8, -(INTRO_H + (i - 1) * ROW_STEP))
		row:SetPoint("RIGHT", win.body, "RIGHT", -8, 0)
		row.label:SetText(EntryName(key))
		if row.hint then
			row.hint:SetText(HaveText(i))
		end
		if row.band then
			row.band:SetShown(i % 2 == 1)   -- (a neutral stripe under every other line)
		end
		local slider = W.ControlOf(row)
		if slider and slider.Refresh then
			slider:Refresh()
		end
		row:Show()
		win.rows[#win.rows + 1] = row
	end
	win.empty:SetShown(list.n == 0)
	local below = floor(Below() * 100 + 0.5)
	if win.introBelow ~= below then
		win.introBelow = below
		win.intro:SetText("What to keep in your bags. You are reminded when a line runs below " .. below
			.. "%, and at a shop it is bought back up to the full amount. Drop an item here to add it.")
	end
	-- the Add list: the families not on it, then the class's suggestions
	local values = win.addValues
	wipe(values)
	for k = 1, #ORDER do
		local letter = ORDER:sub(k, k)
		if letter ~= "r" and not Has(letter) then
			values[#values + 1] = { value = letter, label = FAMILY[letter].name }
		end
	end
	for _, r in ipairs(REAGENTS[PlayerClass() or ""] or {}) do
		if not Has(r[1]) then
			values[#values + 1] = { value = r[1], label = ItemName(r[1]) or ("Item " .. r[1]) }
		end
	end
	if win.add and win.add.Refresh then
		win.add:Refresh()
	end
	f:SetHeight(LIST_TOP + INTRO_H + max(1, list.n) * ROW_STEP + LIST_FOOT + 16)
end

-- a count while the window is open: the hints
ListCounted = function()
	if not (win.frame and win.frame:IsShown()) then
		return
	end
	for _, row in ipairs(win.rows) do
		if row.line and row.hint then
			row.hint:SetText(HaveText(row.line))
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

local AddGet = function()
	return nil
end
local AddSet = function(value)
	if M:Add(value) then
		MelloUI:PlayUISound("check_on")
	end
end

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

local function BuildList()
	local f = CreateFrame("Frame", "MelloUIRestockList", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(LIST_W, 360)
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
		mover = { key = "MelloUIRestockList" },
	})
	-- the text sits on the dark inner panel (the eye strain rule)
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -LIST_TOP)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, LIST_FOOT)
	local fill = W.Solid(body, "BACKGROUND", "innerPanel", 0.85)
	fill:SetAllPoints(body)
	body:EnableMouse(true)
	Perf.SetScript(body, "OnReceiveDrag", ListDrop)
	Perf.SetScript(body, "OnMouseUp", ListDrop)
	win.body = body
	local intro = Style(W.Text(body, "GameFontHighlight", nil, "text"), "fontText", _G.GameFontHighlight)
	intro:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -8)
	intro:SetPoint("RIGHT", body, "RIGHT", -12, 0)
	win.intro = intro
	win.empty = Style(W.Text(body, "GameFontHighlight", "Nothing on the list. Add a line below, or drop an item here.", "text"),
		"fontText", _G.GameFontHighlight)
	win.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 22, -(INTRO_H + 12))
	win.add = W.Dropdown(f, 200, AddGet, AddSet, win.addValues, { default = "Add a line", tooltip = "Drink, food, ammunition or your class's reagents." })
	win.add:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 18)
	win.reset = W.Button(f, "Suggested", 100, win.shell, { onClick = ResetClick })
	win.reset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
	W.Dress(f, win.shell)
	return f
end

function M:OpenList()
	local f = win.frame or BuildList()
	if f:IsShown() then
		ListLayout()
		return
	end
	f:Show()
end

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
		if not state.ready then
			return
		end
		Count()
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
