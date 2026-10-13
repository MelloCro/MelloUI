--------------------------------------------------------------------------------
-- MelloUI - Bag Window: the bags by kind (0.19.0)
--
-- The user, 2026-10-04 (after the bag addon study): "sketch first", then A of
-- MelloUI-BuildData/output/bag_view_sketch/bag_view_looks.jpg. One bag window
-- of MelloUI's own in place of the game's: a heading over each kind of item,
-- small kinds side by side in a row, the empty slots folded into one. The
-- plan and every decision: docs/plans/bag-window.md.
--
-- Kinds (0.20.4: the game's item types, bag_kinds_sketch): an item goes to the
-- first that takes it (KindOf): Recent (the game's new-item mark; kept in
-- Recent until the window closes, so a hovered item does not jump away under
-- the mouse), Junk (poor quality), Quest, Hearthstone, then its type --
-- Consumable, Weapon, Armour, Reagent, Trade Goods, Recipe, Projectile, Bag,
-- Quiver, Key, Miscellaneous -- else Other; an item the player placed (dropped
-- on a kind's + slot, shown while an item is held) goes there first. Shown in the
-- player's order (Windows > Bags > Kinds: lines between them, groups with a
-- fold arrow), Empty
-- (0.21.1, bag_own_kinds_sketch, the user's picks) the player's own kinds:
-- each takes what is dropped on its + slot and what its rule matches (an
-- item type and subtype, a word in the name, a quality), before the game's
-- kinds, the higher on the list first; any kind renamed, any kind split by
-- item type (a heading per type in its place -- 0.19.0's Split Trade Goods
-- is Trade Goods' own); each kind's settings open under its row on the list.
-- The bank by kind (0.21.1, the user's pick: inside the game's bank window):
-- the same engine lays the bank's items in the same kinds where the game's
-- bank grid stood (a view each: BAGS, BANK); the bank window stays the game's
-- the first free slot's own button with the number of free slots on it (an item
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

-- (0.20.4) the Kinds list's row: its heading, 22 rows, its buttons (W.OrderList; longer lists scroll)
local KINDS_H = 46 + 22 * 26 + 8 + 40 + 10

local M   -- (the Kinds row's build reads it)
M = MelloUI:RegisterModule("BagWindow", {
	title = "Bags by Kind",
	slash = "bags",   -- (0.21.3: /mello bags loot, /mello bags coins)
	desc = "Your bags in one window of MelloUI's own, sorted by kind: what you picked up lately, gear, quest items, consumables, junk, trade goods and the rest, each under its own heading. The empty slots fold into one slot with their count.",
	icon = "Interface\\Icons\\INV_Misc_Bag_08",
	flavour = "A place for everything, and everything under its heading.",
	role = "feature",
	-- (no group: its rows sit on the Windows page, the bag window's)
	installer = false,
	enabledByDefault = true,
	defaults = { recentFor = "close", columns = 10, itemSize = 37, foldEmpty = true, sortBy = "quality", bank = true,
		lootFlight = true },
	options = {
		-- (0.20.4; the user, 2026-10-11: "the categories have a priority, whats shown on top ... most people have their
		-- hearthstone on top", look A of bag_kinds_sketch: the kinds in the player's order, lines and groups among them,
		-- a tick each -- the Recent / Gear / Quest / Consumables / Junk / Trade Goods Kind switches folded in)
		{ type = "canvas", key = "kinds", name = "Kinds", height = KINDS_H,
		  search = "kinds order categories priority hearthstone groups lines separator equipment crafting recent junk own custom new add rename subcategories split type subtype rule",
		  desc = "Your bag window's kinds in the order they show, the top first: drag a row to move it. A line draws a line across the window between the kinds over and under it; a group puts the kinds under it, to the next line, under one heading you can fold. Untick a kind and its items go to their own type, or to Other. Add kind makes one of your own: it takes the items you drop on its + slot and the ones its rule matches (an item type, a word in the name, a quality), before the game's kinds. Double-click a name to rename it; a kind's cog opens its settings: its name, Split By Type (a heading for each item type, in its place) and an own kind's rule.",
		  build = function(canvas, width)
			M.BuildKindList(canvas, width)
		  end },
		-- (0.20.4, stage 2 of bag_kinds_sketch; the user: "picking up an item does not show that i can manually place
		-- that item into a group") the + slots while an item is held; the placed items forgotten here
		{ type = "button", name = "Items You Placed", text = "Forget",
		  search = "place drop plus slot item kind assign",
		  desc = "While you hold an item, every kind in your bag window shows a + slot: drop the item there and it always goes under that kind (drop it on its own kind's + to put it back). Forget puts every item you placed back under its own kind.",
		  onClick = function()
			MelloUI:NotifySettingChanged("BagWindow", "placed", nil)
		  end },
		-- (0.21.1; the user, 2026-10-13: "modification to bank aswell" -- the kinds inside the game's bank window)
		{ type = "toggle", key = "bank", name = "Bank by Kind",
		  search = "bank kinds sorted categories banker",
		  desc = "Your bank in the same kinds as your bags, inside the game's bank window: its items under their headings, the lines and groups of the Kinds list, the empty slots folded into one, a + slot in every kind while you hold an item. Deposit and take out as always (right-click, drag). Off: the game's own grid." },
		{ type = "dropdown", key = "recentFor", name = "Recent Lasts", values = RECENT_FOR,
		  desc = "How long an item stays under Recent: until you close your bags, only until you point at it (it moves to its own kind as the pointer leaves it), or for 5 minutes after you got it." },
		{ type = "slider", key = "columns", name = "Columns", min = 8, max = 16, step = 1,
		  desc = "How many slots across the bag window is: more makes it wider and shorter." },
		{ type = "slider", key = "itemSize", name = "Item Size", min = 30, max = 46, step = 1,
		  desc = "How big the item slots are (37 is the game's own size)." },
		{ type = "toggle", key = "foldEmpty", name = "Fold Empty Slots",
		  desc = "All your empty slots as one slot with their count (drop an item on it to put it in a free slot). Off: every empty slot shows." },
		{ type = "dropdown", key = "sortBy", name = "Sort Items By", values = SORT_BY,
		  desc = "The order inside each kind: better quality first, by name, the ones you picked up last first, or the highest item level first." },
		-- (0.21.3; the user, 2026-10-13: "Yes to all" to the animation previews, and "more impactfull animations
		-- depending on the rarity of the item")
		{ type = "toggle", key = "lootFlight", name = "Loot Flight", new = "0.21.3",
		  search = "loot animation fly flight rarity quality legendary epic",
		  desc = "An item you loot flies from where you picked it up into its slot in your bag window (with the bags closed, onto the bag button) and lands with a light across it. The rarer it is, the more it does: green leaves a streak, blue bursts into rays and lands in a ring, purple throws sparks and a shockwave, and a legendary rises in a pillar of light, flashes your bag window's border and says its name on the screen. Turning in a quest, its reward item flies the same way, and its money flies as coins into the bag window's money, which counts up as they land. Only loot and quest rewards, never what you buy, craft or take from the mail. Not with Reduce Motion." },
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
	SEARCH_X = 70,   -- the search box's left, past the ring
	-- (0.20.1, the window pass: the search field on its buttons' line, as tall as their plates -- the user's pick E,
	-- THE text field)
	ROW_Y = -32,     -- the search row's top below the window's top (the sort / bin / settings buttons and the box)
	ROW_H = 26,      -- its height: the buttons' (the game's sort button's) and the search field's
	PANEL_PAD = 6,   -- the dark panel round the items
	PANEL_ALPHA = 0.9,
	FOOT = 38,       -- the money row under the content (and its dark panel)
	-- (0.20.1, the user: the items' panel "needs to be readjusted to fit inside the thick borders") with the kit look
	-- on, the side inset and the foot from the window rail's own depth (Insets): the panel EDGE_GAP clear of the rails
	EDGE_GAP = 4,
	MONEY_Y = 12,    -- the money's bottom above the window's bottom (the plain look's; past the bottom rail in the kit's)
	MONEY_H = 14,    -- the money row's height
	HEAD = 17,       -- a kind's heading above its items
	ROW_GAP = 8,     -- between rows of kinds
	KIND_GAP = 15,   -- between kinds side by side
	GROUP_H = 23,    -- (0.20.4) a group's heading over its kinds
	LINE_GAP = 10,   -- (0.20.4) a line, and the room under it
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
	G.INSET, G.FOOT_NOW, G.MONEY_Y_NOW = G.INSET or G.SIDE, G.FOOT_NOW or G.FOOT, G.MONEY_Y_NOW or G.MONEY_Y
	G.WIDTH = G.CONTENT_W + 2 * G.INSET
end
Grid()
M.G = G   -- (the tests)

local TEXT = {
	title = "Bags",
	fold = "Click to fold this kind into one slot.",
	unfold = "Click to show every item of this kind.",
	sell = "Sell Junk",
	worth = "Sells for %s",
	free = "%d free |4slot:slots;",
	sort = "Clean Up Bags",
	settings = "Bag Settings",
	settingsTip = "Bags by Kind's options: its kinds and its layout (Windows > Bags).",
	-- (0.20.4) the groups, and the Kinds list on Windows > Bags
	foldGroup = "Click to fold this group: only its heading shows.",
	unfoldGroup = "Click to show the kinds of this group.",
	kindsTitle = "Kinds",
	kindsHelp = "Drag a row to order it. Double-click a name to rename it. The cog: a kind's settings.",
	addLine = "Add line",
	addGroup = "Add group",
	resetOrder = "Reset order",
	newGroup = "New group",
	-- (0.21.1) own kinds and a kind's settings (opened under its row)
	addKind = "Add kind",
	newKind = "New kind",
	ownNote = "your own",
	splitNote = "split by type",
	name = "Name",
	split = "Split By Type",
	splitTip = "a heading for each item type",
	takes = "Takes",
	takesTip = "what matches all of these (none set: only what you drop on it)",
	itemType = "Item Type",
	subtype = "Subtype",
	nameHas = "Name Contains",
	quality = "Quality",
	any = "Any",
	orBetter = "%s or better",
	dropped = "Items you dropped here: %d",
	forget = "Forget Them",
	remove = "Remove Kind",
	removeAsk = "Remove the kind %s? Its items go back to their own kinds.",
	removeAccept = "Remove",
	-- (0.20.4) the + slots while an item is held
	placeTip = "Drop the item here: it always goes under %s.",
	placeBack = "Drop it here: it goes back under its own kind.",
}

-- The kinds (0.20.4; the user, 2026-10-11: "the categories have a priority, whats shown on top ... most people have
-- their hearthstone on top" -- bag_kinds_sketch): the game's item types. `note`: a line beside it on the Kinds list;
-- `always`: no tick (Other takes what the others pass on, Empty is the free slots)
local KINDS = {
	{ key = "recent", name = "Recent", note = "while you have new items" },
	{ key = "hearth", name = "Hearthstone" },
	{ key = "consumable", name = "Consumable" },
	{ key = "quest", name = "Quest" },
	{ key = "weapon", name = "Weapon" },
	{ key = "armour", name = "Armour" },
	{ key = "reagent", name = "Reagent" },
	{ key = "tradegoods", name = "Trade Goods" },
	{ key = "recipe", name = "Recipe" },
	{ key = "projectile", name = "Projectile" },
	{ key = "bag", name = "Bag" },
	{ key = "quiver", name = "Quiver" },
	{ key = "key", name = "Key" },
	{ key = "misc", name = "Miscellaneous" },
	{ key = "other", name = "Other", always = true },
	{ key = "junk", name = "Junk" },
	{ key = "empty", name = "Empty", always = true, note = "folded into one slot" },
}
local KIND = {}
for _, k in ipairs(KINDS) do
	KIND[k.key] = k
end
M.KINDS = KINDS

-- the order a player starts with (and Reset order's): "-" a line, "group:<name>" a group, its kinds the ones after it
-- up to the next line or group (the sketch's)
local DEFAULT_ORDER = { "recent", "-", "hearth", "consumable", "quest", "-", "group:Equipment", "weapon", "armour", "-",
	"group:Crafting", "reagent", "tradegoods", "recipe", "-", "projectile", "bag", "quiver", "key", "misc", "other", "-",
	"junk", "empty" }

-- an item's class (Enum.ItemClass numbers: this client's) to its kind
local CLASS_KIND = {
	[0] = "consumable",                  -- food, drink, potions, elixirs, scrolls, bandages
	[1] = "bag",
	[2] = "weapon", [4] = "armour",
	[3] = "tradegoods", [7] = "tradegoods",   -- gems, trade goods
	[5] = "reagent",
	[6] = "projectile",
	[9] = "recipe",
	[11] = "quiver",
	[12] = "quest",
	[13] = "key",
	[15] = "misc",
}
local HEARTH = { [6948] = true }   -- the Hearthstone

-- (0.21.1; the user, 2026-10-13: "people ask for a option to add and rename subcategories" -- bag_own_kinds_sketch,
-- the picks: own kinds by drag + rules, Split By Type per kind, every kind renamed) the player's own kinds:
-- db.ownKinds[key] = { name, class, subclass, nameHas, quality } (keys "own:<n>", db.ownN the last n); a game kind's
-- name of the player's: db.kindNames[key]; Split By Type: db.kindSplit[key]
local function IsOwn(key)
	return type(key) == "string" and key:sub(1, 4) == "own:"
end
local function Own(key)
	local own = M.db and type(M.db.ownKinds) == "table" and M.db.ownKinds
	local o = own and IsOwn(key) and own[key]
	return type(o) == "table" and o or nil
end
local function KnownKind(key)
	return KIND[key] ~= nil or Own(key) ~= nil
end
local function KindName(key)
	local o = Own(key)
	if o then
		return type(o.name) == "string" and o.name ~= "" and o.name or TEXT.newKind
	end
	local names = M.db and type(M.db.kindNames) == "table" and M.db.kindNames
	local n = names and names[key]
	if type(n) == "string" and n ~= "" then
		return n
	end
	return KIND[key] and KIND[key].name or tostring(key)
end
local function Split(key)
	local t = M.db and type(M.db.kindSplit) == "table" and M.db.kindSplit
	return t and t[key] == true or false
end
M.KindName, M.IsOwn = KindName, IsOwn   -- (the tests)

-- an own kind's rule against an item: every condition set must hold (a quality of 10 + q: q or better)
local function Matches(r, quality, classID, subclassID, name)
	if r.class and r.class ~= classID then
		return false
	elseif r.subclass and r.subclass ~= subclassID then
		return false
	elseif r.nameHas and not (type(name) == "string" and name:lower():find(r.nameHas, 1, true)) then
		return false
	elseif r.quality then
		if r.quality >= 10 then
			return (quality or 1) >= r.quality - 10
		end
		return quality == r.quality
	end
	return true
end
local POOR = 0   -- Enum.ItemQuality.Poor
local TRADE_GOODS = 7   -- the trade goods' class (split by its subclasses: Cloth, Leather ...)
local ALL_ON = {}

-- Which kind an item is: the first that takes it, of the kinds switched on
-- (`on`: [kind] = false for a kind unticked, OnTable; a kind off passes its items on: Recent's to their own kind,
-- Junk's, Quest's and Hearthstone's to their type's, the types' to Other). `placed` (0.20.4): [itemID] = the kind the
-- player dropped it on (its + slot), taken after Recent while that kind is on; `rules` (0.21.1): the own kinds' rules
-- in the list's order (Rules), taken next -- before the game's kinds -- by the item's subclass and name too
function M.KindOf(quality, classID, isQuestItem, recent, on, itemID, placed, subclassID, name, rules)
	on = on or ALL_ON
	local mine = placed and itemID and placed[itemID]
	if recent and on.recent ~= false then
		return "recent"
	elseif mine and KnownKind(mine) and mine ~= "recent" and mine ~= "empty" and on[mine] ~= false then
		return mine
	end
	for i = 1, rules and #rules or 0 do
		local r = rules[i]
		if on[r.key] ~= false and Matches(r, quality, classID, subclassID, name) then
			return r.key
		end
	end
	if quality == POOR and on.junk ~= false then
		return "junk"
	elseif (isQuestItem or classID == 12) and on.quest ~= false then
		return "quest"
	elseif itemID and HEARTH[itemID] and on.hearth ~= false then
		return "hearth"
	end
	local kind = CLASS_KIND[classID]
	if kind and kind ~= "quest" and on[kind] ~= false then
		return kind
	end
	return "other"
end

-- the kinds on (the Kinds list's ticks: db.kindOff), as KindOf reads them (one table, reused)
local onNow = {}
local function OnTable()
	local off = M.db and type(M.db.kindOff) == "table" and M.db.kindOff or nil
	wipe(onNow)
	for _, k in ipairs(KINDS) do
		onNow[k.key] = not (off and off[k.key]) and true or false
	end
	for key in pairs(M.db and type(M.db.ownKinds) == "table" and M.db.ownKinds or ALL_ON) do
		onNow[key] = not (off and off[key]) and true or false
	end
	return onNow
end
local function On(key)
	local off = M.db and type(M.db.kindOff) == "table" and M.db.kindOff or nil
	return not (off and off[key])
end

-- (0.20.4) the kinds' old switches -- Recent, Gear, Quest, Consumables, Junk and Trade Goods Kind -- into the Kinds
-- list's ticks: a switch that was off unticks its kinds; the old keys go (at each enable: a profile may bring them)
local OLD_SWITCHES = { recent = { "recent" }, gear = { "weapon", "armour" }, quest = { "quest" },
	consumables = { "consumable" }, junk = { "junk" }, trade = { "reagent", "tradegoods", "recipe" } }
local function Migrate(db)
	-- (0.21.1) Split Trade Goods: Trade Goods' own Split By Type
	if db.splitTrade ~= nil then
		if db.splitTrade == true then
			local t = type(db.kindSplit) == "table" and db.kindSplit or {}
			db.kindSplit = t
			t.tradegoods = true
		end
		db.splitTrade = nil
	end
	for old, kinds in pairs(OLD_SWITCHES) do
		if db[old] ~= nil then
			if db[old] == false then
				local off = type(db.kindOff) == "table" and db.kindOff or {}
				db.kindOff = off
				for _, k in ipairs(kinds) do
					off[k] = true
				end
			end
			db[old] = nil
		end
	end
end
M.Migrate = Migrate   -- (the tests)

-- The player's order (Kinds: db.kindOrder; DEFAULT_ORDER until they change it), read into one table (reused): every
-- known kind once, the lines ("-"), the groups ("group:<name>"); a kind the saved order lacks (one an update added)
-- goes in before Empty
local ord, ordSeen = {}, {}
local function IsGroup(v)
	return type(v) == "string" and v:sub(1, 6) == "group:"
end
local function ReadOrder()
	local saved = M.db and M.db.kindOrder
	local src = (type(saved) == "table" and #saved > 0) and saved or DEFAULT_ORDER
	wipe(ord)
	wipe(ordSeen)
	for _, v in ipairs(src) do
		if v == "-" or IsGroup(v) then
			ord[#ord + 1] = v
		elseif KnownKind(v) and not ordSeen[v] then
			ordSeen[v] = true
			ord[#ord + 1] = v
		end
	end
	local function Missing(key)
		if not ordSeen[key] then
			local at = #ord + 1
			for i, v in ipairs(ord) do
				if v == "empty" then
					at = i
					break
				end
			end
			table.insert(ord, at, key)
			ordSeen[key] = true
		end
	end
	for _, k in ipairs(KINDS) do
		Missing(k.key)
	end
	-- (0.21.1: an own kind the order lacks -- a profile's -- before Empty too)
	for key in pairs(M.db and type(M.db.ownKinds) == "table" and M.db.ownKinds or ALL_ON) do
		if IsOwn(key) then
			Missing(key)
		end
	end
	return ord
end
M.ReadOrder = ReadOrder   -- (the tests)

-- (0.21.1) the own kinds with a rule, in the list's order (one table, reused): what KindOf asks
local rules = {}
local function Rules()
	local n = 0
	for _, v in ipairs(ReadOrder()) do
		local o = Own(v)
		local has = o and type(o.nameHas) == "string" and o.nameHas:match("%S") and o.nameHas:lower() or nil
		if o and (Num(o.class) or Num(o.subclass) or has or Num(o.quality)) then
			n = n + 1
			local r = rules[n] or {}
			rules[n] = r
			r.key, r.class, r.subclass, r.quality, r.nameHas = v, Num(o.class), Num(o.subclass), Num(o.quality), has
		end
	end
	for i = #rules, n + 1, -1 do
		rules[i] = nil
	end
	return rules
end
M.Rules = Rules   -- (the tests)

-- Split By Type (0.21.1, any kind; 0.19.0's Split Trade Goods is Trade Goods'): an item's own part of a split kind
-- (its key and its heading: the client's own name of its subtype, else of its type) -- Trade Goods' as Split Trade
-- Goods had them (a trade good by its subtype, a reagent, recipe or gem by its type)
local partNames = {}   -- [key] = the heading, read once
local function SplitKind(parent, classID, subclassID)
	local key
	if parent == "tradegoods" then
		key = classID == TRADE_GOODS and ("trade:7:" .. subclassID) or ("trade:" .. classID)
	else
		key = "split:" .. parent .. ":" .. classID .. ":" .. subclassID
	end
	if not partNames[key] then
		local C = C_Item
		local name
		if (parent ~= "tradegoods" or (classID == TRADE_GOODS and subclassID ~= 0)) and C and C.GetItemSubClassInfo then
			name = C.GetItemSubClassInfo(classID, subclassID)
		end
		if not (type(name) == "string" and name ~= "") and (parent ~= "tradegoods" or classID ~= TRADE_GOODS)
			and C and C.GetItemClassInfo then
			name = C.GetItemClassInfo(classID)
		end
		partNames[key] = type(name) == "string" and name ~= "" and name or KindName(parent)
	end
	return key
end

--------------------------------------------------------------------------------
-- The bags read: every slot of the held bags, each item's kind
--------------------------------------------------------------------------------

local win = {}          -- the window's parts (made on the first open)
local heldID = {}       -- [bag * 1000 + slot] = itemID: Recent (until the bags close, or for some minutes)
local heldAt = {}       -- [bag * 1000 + slot] = when it was first seen new (For 5 Minutes)
local RECENT_MINUTES = 5

-- (0.21.1) A view: one place the kinds are laid -- the bag window's, the bank window's grid (the user, 2026-10-13:
-- the bank by kind "inside the bank window") -- with its own containers read, buttons, headings, lines and + slots;
-- S the view being read or laid (one engine, the bags' and the bank's alike)
--   containers()   the containers it shows (reused list)
--   recent         Recent and Newest First's records (the bags only: the game marks new items there)
--   content        the frame its kinds are laid on
--   holders [bag] the frame a container's buttons sit in (its ID: the container); slots [bag] = { [slot] = button };
--   made, undressed  every button made, in order, and how many since the last dressing; entries, nEntries the items
--   read; byKind [kind] = its entries; empties, nEmpties the free slots shown; junkWorth (copper; nil while an item's
--   price is not known yet); parts [split kind] = its parts this layout; headings, folds [kind]; groupHeads [group];
--   lines, pluses (made as many as a layout lays); stamp (a layout's); holding (an item held at its last layout)
local function NewView(name, containers, recent)
	local v = { name = name, containers = containers, recent = recent, holders = {}, slots = {}, made = {},
		undressed = 0, entries = {}, nEntries = 0, byKind = {}, empties = {}, nEmpties = 0, junkWorth = 0, parts = {},
		headings = {}, folds = {}, groupHeads = {}, lines = {}, pluses = {}, dressedPitch = nil, stamp = 0, holding = false }
	for _, k in ipairs(KINDS) do
		v.byKind[k.key] = {}
	end
	return v
end

-- the held bags: the backpack and its bag slots
local heldBags = {}
local function HeldBags()
	local inv = Constants and Constants.InventoryConstants
	local last = inv and Num(inv.NumBagSlots) or 4
	for bag = 0, last do
		heldBags[bag + 1] = bag
	end
	for i = #heldBags, last + 2, -1 do
		heldBags[i] = nil
	end
	return heldBags
end
local BAGS = NewView("bags", HeldBags, true)
local S = BAGS

-- the bank's containers: the bank tabs the active bank type has bought (the game's bank window's own reads)
local bankTabs = {}
local function BankContainers()
	wipe(bankTabs)
	local bf = rawget(_G, "BankFrame")
	local panel = bf and bf.BankPanel
	local ok, bankType = pcall(function()
		return panel:GetActiveBankType()
	end)
	if not (ok and bankType ~= nil) then
		bankType = Enum and Enum.BankType and Enum.BankType.Character or 0
	end
	local CB = rawget(_G, "C_Bank")
	local okData, data = pcall(CB and CB.FetchPurchasedBankTabData, bankType)
	if okData and type(data) == "table" then
		for _, tab in ipairs(data) do
			local id = type(tab) == "table" and Num(tab.ID)
			if id then
				bankTabs[#bankTabs + 1] = id
			end
		end
	end
	return bankTabs
end
local BANK = NewView("bank", BankContainers, false)
local BankShown   -- (the bank's section: is the bank by kind showing)

local function Entry(i)
	local e = S.entries[i]
	if not e then
		e = {}
		S.entries[i] = e
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
	S.nEmpties = S.nEmpties + 1
	local e = S.empties[S.nEmpties]
	if not e then
		e = {}
		S.empties[S.nEmpties] = e
	end
	e.bag, e.slot, e.free = bag, slot, free
end

local function ByPartName(a, b)
	return partNames[a] < partNames[b]
end

local function ReadBags()
	local C = C_Container
	local db = M.db or ALL_ON
	for _, list in pairs(S.byKind) do
		wipe(list)
	end
	S.nEntries, S.nEmpties, S.junkWorth, recentEnds = 0, 0, 0, nil
	for _, list in pairs(S.parts) do
		wipe(list)
	end
	readStamp = readStamp + 1
	local normalFree, normalBag, normalSlot = 0, nil, nil
	wipe(familyFree)
	wipe(familyBag)
	wipe(familySlot)
	local isNew = C_NewItems and C_NewItems.IsNewItem
	local recentMode = db.recentFor or "close"
	local sortBy = SORTS[db.sortBy] and db.sortBy or "quality"
	local fold = db.foldEmpty ~= false
	local on = OnTable()
	local placed = type(db.placed) == "table" and db.placed or nil
	local ownRules = Rules()
	local now = GetTime()
	for _, bag in ipairs(S.containers()) do
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
				S.nEntries = S.nEntries + 1
				local e = Entry(S.nEntries)
				e.bag, e.slot, e.itemID, e.info = bag, slot, itemID, info
				e.quality = Num(info.quality) or 1
				e.count = Num(info.stackCount) or 1
				local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
				e.classID = Num(classID) or 15
				e.subclassID = Num(subclassID) or 0
				e.isQuest, e.questID, e.questActive = Quest(bag, slot)
				local key = bag * 1000 + slot
				local isNewNow = S.recent and isNew and isNew(bag, slot) and true or false
				local recent = S.recent and Recent(recentMode, key, itemID, isNewNow, now)
				if recent and recentMode == "minutes" then
					local ends = heldAt[key] + RECENT_MINUTES * 60
					recentEnds = recentEnds and math.min(recentEnds, ends) or ends
				end
				-- (the name: Sort Items By's Name, and an own kind's Name Contains)
				e.name = type(info.hyperlink) == "string" and info.hyperlink:match("%[(.-)%]") or ""
				local kind = M.KindOf(e.quality, e.classID, e.isQuest, recent, on, itemID, placed, e.subclassID, e.name,
					ownRules)
				if kind ~= "recent" and Split(kind) then
					local part = SplitKind(kind, e.classID, e.subclassID)
					local list = S.byKind[part]
					if not list then
						list = {}
						S.byKind[part] = list
					end
					if #list == 0 then
						local of = S.parts[kind]
						if not of then
							of = {}
							S.parts[kind] = of
						end
						of[#of + 1] = part
					end
					kind = part
				end
				e.kind = kind
				local list = S.byKind[kind]
				if not list then
					list = {}   -- (an own kind's, the first time it takes an item)
					S.byKind[kind] = list
				end
				list[#list + 1] = e
				if sortBy == "level" then
					e.level = ItemLevel(info, itemID)
				end
				if M.db and S.recent then
					Seen(M.db, itemID, key, isNewNow)   -- (the numbers read after the pass: every stack of a type alike)
				end
				if e.quality == POOR and S.junkWorth and not info.hasNoValue then
					local price = SellPrice(itemID)
					S.junkWorth = price and S.junkWorth + price * e.count or nil
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
	for i = 1, S.nEntries do
		local e = S.entries[i]
		e.seen = seen and Num(seen[e.itemID]) or 0
	end
	local order = SORTS[sortBy]
	for _, list in pairs(S.byKind) do
		if #list > 1 then
			table.sort(list, order)
		end
	end
	for _, of in pairs(S.parts) do
		if #of > 1 then
			table.sort(of, ByPartName)
		end
	end
	if M.db and S.recent then
		PruneSeen(M.db)
	end
	-- the free slots folded: the normal bags' first, then each bag type's
	if normalBag then
		AddEmpty(normalBag, normalSlot, normalFree)
	end
	for family, bag in pairs(familyBag) do
		AddEmpty(bag, familySlot[family], familyFree[family])
	end
	return S.nEntries
end
M.byKind, M.empties = BAGS.byKind, BAGS.empties   -- (the tests: the bags')

--------------------------------------------------------------------------------
-- The item buttons: the game's own template, one holder per bag
--------------------------------------------------------------------------------

local LayoutSoon   -- (the events' one, below)

-- Recent Lasts Until Hovered: was this slot's item laid under Recent, and is
-- the game's new-item mark off it now?
local function LeftRecent(bag, slot)
	local list = S.byKind.recent
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
	local h = S.holders[bag]
	if not h then
		h = CreateFrame("Frame", nil, S.content)
		h:SetID(bag)
		h:SetAllPoints(S.content)
		S.holders[bag] = h
	end
	return h
end

local function SlotButton(bag, slot)
	local list = S.slots[bag]
	if not list then
		list = {}
		S.slots[bag] = list
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
		S.made[#S.made + 1] = b
		S.undressed = S.undressed + 1
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
local function Dress()
	-- (the pitch in the buttons' own units: they are scaled to Item Size)
	local pitch = G.PITCH / G.SCALE
	if pitch ~= S.dressedPitch then
		S.undressed = #S.made   -- (a new Item Size: every rim laid on the new pitch)
	end
	if S.undressed == 0 then
		return
	end
	local panel = MelloUI:GetModule("BackpackPanel")
	if panel and panel.DressSlots and panel:DressSlots(S.made, #S.made, { pitch, pitch }) then
		S.undressed, S.dressedPitch = 0, pitch
	end
end

--------------------------------------------------------------------------------
-- The headings: one per kind, made with the window
--------------------------------------------------------------------------------


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
	M.LayAll()
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
	if self.key == "junk" and S.junkWorth and S.junkWorth > 0 then
		body = TEXT.worth:format(GetMoneyString(S.junkWorth, true)) .. "\n" .. body
	end
	W.ShowTooltip(self, self.name, body)
end, "script")

-- a kind's heading, made the first time that kind shows (a trade good's type
-- with Split Trade Goods: one per type ever, kept)
local function Heading(key, name)
	local h = S.headings[key]
	if h then
		if h.name ~= name then
			h.name = name   -- (0.21.1: renamed)
			h.text:SetText(name)
		end
		return h
	end
	h = CreateFrame("Button", nil, S.content)
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
	S.headings[key] = h
	local fold = S.content:CreateFontString(nil, "OVERLAY")
	Look.Text(fold, "number", 12, { area = AREA })
	S.folds[key] = fold
	return h
end

local function LayHeading(h, folded)
	h.text:ClearAllPoints()
	h.text:SetPoint("LEFT", h, "LEFT", folded and 14 or 1, 0)
	h.plus:SetShown(folded)
end

-- (0.20.4) a group's heading over its kinds: its name with the kit's gold caret (down while open, right while folded:
-- its kinds hidden, their count beside it), made the first time that group shows; and the lines between kinds (a
-- light line over a dark one, as in the user's shot), made as many as a layout lays

local function GroupFolded(name)
	local f = M.db and M.db.foldedGroups
	return type(f) == "table" and f[name] == true
end

local GroupClick = Shared("OnClick on a bag window group heading", function(self)
	local f = M.db.foldedGroups
	if type(f) ~= "table" then
		f = {}
		M.db.foldedGroups = f
	end
	f[self.name] = not f[self.name] or nil
	MelloUI:PlayUISound(f[self.name] and "check_off" or "check_on")
	M.LayAll()
	if self:IsMouseOver() then
		self:GetScript("OnEnter")(self)
	end
end, "script")

local GroupEnter = Shared("OnEnter on a bag window group heading", function(self)
	W.Caret(self.caret, 12, GroupFolded(self.name) and "right" or "down", true)
	W.ShowTooltip(self, self.name, GroupFolded(self.name) and TEXT.unfoldGroup or TEXT.foldGroup)
end, "script")

local GroupLeave = Shared("OnLeave on a bag window group heading", function(self)
	W.Caret(self.caret, 12, GroupFolded(self.name) and "right" or "down")
	W.TipLeave(self)
end, "script")

local function GroupHead(name)
	local h = S.groupHeads[name]
	if h then
		return h
	end
	h = CreateFrame("Button", nil, S.content)
	h:SetHeight(G.GROUP_H)
	h.name = name
	h.caret = h:CreateTexture(nil, "OVERLAY")
	h.caret:SetSize(12, 12)
	h.caret:SetPoint("LEFT", h, "LEFT", 1, 0)
	h.text = h:CreateFontString(nil, "OVERLAY")
	Look.Text(h.text, "gold", 14, { area = AREA })
	h.text:SetPoint("LEFT", h.caret, "RIGHT", 6, 0)
	h.text:SetText(name)
	h.count = h:CreateFontString(nil, "OVERLAY")
	Look.Text(h.count, "text", 11, { area = AREA })
	h.count:SetPoint("LEFT", h.text, "RIGHT", 8, 0)
	Perf.SetScript(h, "OnClick", GroupClick)
	Perf.SetScript(h, "OnEnter", GroupEnter)
	Perf.SetScript(h, "OnLeave", GroupLeave)
	S.groupHeads[name] = h
	return h
end

local function LayGroupHead(h, folded, count)
	W.Caret(h.caret, 12, folded and "right" or "down")
	h.count:SetText(folded and count or "")
	h:SetWidth((Num(h.text:GetStringWidth()) or 0) + 18 + (folded and 40 or 0))
end

-- (0.20.4, stage 2 of bag_kinds_sketch; the user, 2026-10-11: "picking up an item does not show that i can manually
-- place that item into a group") While the cursor holds an item every kind on shows a + slot after its items (a
-- kind with none shows its heading and the slot; a folded group opens): the item dropped there (or clicked onto it)
-- always goes under that kind -- db.placed[itemID], forgotten when it is dropped on its own kind's -- and goes back
-- to its slot. Made as many as a layout lays.

-- the item the cursor holds (its ID), else nil
local function CursorItem()
	local ok, what, id = pcall(GetCursorInfo)
	if ok and what == "item" then
		return Num(id)
	end
	return nil
end

-- the kind a + slot places in (a part of a kind split by type: that kind)
local function PlaceKind(key)
	if type(key) ~= "string" then
		return key
	elseif key:sub(1, 6) == "trade:" then
		return "tradegoods"
	end
	return key:match("^split:(.-):%-?%d+:%-?%d+$") or key
end

local function TakesPlus(key)
	return key ~= "recent" and key ~= "empty" and On(PlaceKind(key))
end

-- the kind an item goes to by itself (no placing, not Recent): its read entry's, else its type's
local function NaturalKind(id)
	for i = 1, S.nEntries do
		local e = S.entries[i]
		if e.itemID == id then
			return M.KindOf(e.quality, e.classID, e.isQuest, false, OnTable(), id, nil, e.subclassID, e.name, Rules())
		end
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
	local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	local ok, name, _, quality = pcall(GetInfo, id)
	return M.KindOf(ok and Num(quality) or 1, Num(classID) or 15, false, false, OnTable(), id, nil, Num(subclassID) or 0,
		ok and type(name) == "string" and name or nil, Rules())
end

local function PlusLook(b, lit)
	W.PlusMark(b.mark, b.markSize, lit)
	for _, e in ipairs(b.edges) do
		W.Paint(e, lit and "selectedTrim" or "border", "fill", 1)
	end
end

local PlusDrop = Shared("OnReceiveDrag / OnClick on a bag window + slot", function(self)
	local id = CursorItem()
	if not id then
		return
	end
	local kind = PlaceKind(self.placeKind)
	local placed = {}
	for k, v in pairs(type(M.db.placed) == "table" and M.db.placed or {}) do
		placed[k] = v
	end
	placed[id] = (kind ~= NaturalKind(id)) and kind or nil
	ClearCursor()
	MelloUI:PlayUISound("check_on")
	MelloUI:NotifySettingChanged(M.name, "placed", placed)
end, "script")

local PlusEnter = Shared("OnEnter on a bag window + slot", function(self)
	PlusLook(self, true)
	local kind = PlaceKind(self.placeKind)
	local id = CursorItem()
	local name = KindName(kind)
	W.ShowTooltip(self, name, (id and NaturalKind(id) == kind) and TEXT.placeBack or TEXT.placeTip:format(name))
end, "script")

local PlusLeave = Shared("OnLeave on a bag window + slot", function(self)
	PlusLook(self, false)
	W.TipLeave(self)
end, "script")

local function LayPlus(i, key, x, y)
	local b = S.pluses[i]
	if not b then
		b = CreateFrame("Button", nil, S.content)
		b:RegisterForClicks("LeftButtonUp")
		b.fill = W.Solid(b, "BACKGROUND", "innerPanel", 0.9)
		b.fill:SetAllPoints(b)
		b.edges = W.Edges(b, "border", "BORDER")
		b.mark = b:CreateTexture(nil, "ARTWORK")
		b.mark:SetPoint("CENTER", b, "CENTER", 0, 0)
		Perf.SetScript(b, "OnClick", PlusDrop)
		Perf.SetScript(b, "OnReceiveDrag", PlusDrop)
		Perf.SetScript(b, "OnEnter", PlusEnter)
		Perf.SetScript(b, "OnLeave", PlusLeave)
		S.pluses[i] = b
	end
	b.placeKind = key
	b:SetSize(G.SLOT, G.SLOT)
	b.markSize = math.floor(G.SLOT * 0.55 + 0.5)
	b.mark:SetSize(b.markSize, b.markSize)
	PlusLook(b, false)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", S.content, "TOPLEFT", x, -y)
	b:Show()
end

local function LayLine(i, y)
	local l = S.lines[i]
	if not l then
		l = {}
		l.light = W.Solid(S.content, "ARTWORK", "trim", 0.55)
		l.dark = W.Solid(S.content, "ARTWORK", "innerPanel", 1)
		l.light:SetHeight(1)
		l.dark:SetHeight(1)
		S.lines[i] = l
	end
	l.light:ClearAllPoints()
	l.light:SetPoint("TOPLEFT", S.content, "TOPLEFT", 0, -y)
	l.light:SetPoint("RIGHT", S.content, "RIGHT", 0, 0)
	l.dark:ClearAllPoints()
	l.dark:SetPoint("TOPLEFT", l.light, "BOTTOMLEFT", 0, 0)
	l.dark:SetPoint("RIGHT", l.light, "RIGHT", 0, 0)
	l.light:Show()
	l.dark:Show()
end

--------------------------------------------------------------------------------
-- The layout: the kinds packed in rows, each kind's items under its heading
--------------------------------------------------------------------------------

local used = setmetatable({}, { __mode = "k" })   -- [button] = the stamp of the layout that placed it

-- a slot at x, y of the content: the button at the game's own size, scaled to
-- Item Size (its points then in its own scale's units)
local function Place(b, x, y)
	local k = G.SCALE
	if b:GetScale() ~= k then
		b:SetScale(k)
	end
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", S.content, "TOPLEFT", x / k, -y / k)
	b:Show()
	used[b] = S.stamp
end

-- what this layout lays, in the player's order: the kinds (a kind split by type: its parts in its place, by name),
-- the lines and the groups -- orderType "kind", "line" or "group" (a group's name in orderName)
local order, orderName, orderType = {}, {}, {}
local function Order()
	local n = 0
	for _, v in ipairs(ReadOrder()) do
		if v == "-" then
			n = n + 1
			order[n], orderName[n], orderType[n] = v, nil, "line"
		elseif IsGroup(v) then
			n = n + 1
			order[n], orderName[n], orderType[n] = v, v:sub(7), "group"
		elseif v ~= "recent" and Split(v) then
			for _, part in ipairs(S.parts[v] or ALL_ON) do
				n = n + 1
				order[n], orderName[n], orderType[n] = part, partNames[part], "kind"
			end
		else
			n = n + 1
			order[n], orderName[n], orderType[n] = v, KindName(v), "kind"
		end
	end
	for i = #order, n + 1, -1 do
		order[i], orderName[i], orderType[i] = nil, nil, nil
	end
	return n
end

-- the items under a group's kinds (the order's entries after it, to the next line or group); `holding`: their + slots
-- too
local function GroupCount(i, n, holding)
	local count = 0
	for j = i + 1, n do
		if orderType[j] ~= "kind" then
			break
		end
		local key = order[j]
		count = count + (key == "empty" and S.nEmpties or (S.byKind[key] and #S.byKind[key] or 0))
		if holding and TakesPlus(key) then
			count = count + 1
		end
	end
	return count
end

-- the layout's place (one table: no closure per layout) -- x, y, the row's height, whether anything is laid yet,
-- whether a line is asked for before the next thing laid, the lines laid, the + slots laid
local at = { x = 0, y = 0, rowH = 0, laid = false, lineDue = false, nLines = 0, nPlus = 0 }

-- a new row under what is laid
local function NewRow()
	if at.x > 0 or at.rowH > 0 then
		at.y = at.y + at.rowH + G.ROW_GAP
	end
	at.x, at.rowH = 0, 0
end

-- the line asked for, before the next thing laid: never at the top, never two at once
local function DueLine()
	if at.lineDue and at.laid then
		NewRow()
		at.nLines = at.nLines + 1
		LayLine(at.nLines, at.y + 1)
		at.y = at.y + G.LINE_GAP
	end
	at.lineDue = false
end

local function AtVendor()
	local mf = rawget(_G, "MerchantFrame")
	return mf and mf:IsShown() and true or false
end

local function SellShown()
	return AtVendor() and S.junkWorth ~= 0 and #S.byKind.junk > 0
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
		win.search:SetPoint("TOPLEFT", win.frame, "TOPLEFT", G.SEARCH_X, G.ROW_Y)
		win.search:SetPoint("RIGHT", win.settings, "LEFT", -8, 0)
	end
end

-- The window's own parts past the rails (0.20.1, the user: the items' panel "needs to be readjusted to fit inside the
-- thick borders"; their pick "Move them inward"): with the kit look on, the content's side inset and the foot under it
-- from the window rail's own depth (Kit:OuterRailInset) -- the dark panel round the items EDGE_GAP clear of the rails,
-- the search row's buttons (the row hangs from the sort button) at the same inset, the money between the panel and
-- the bottom rail; the fixed G.SIDE / G.FOOT where those are larger (the plain look, a thin rail)
local function Insets()
	local side, foot, moneyY = G.SIDE, G.FOOT, G.MONEY_Y
	if win.shell and win.shell.kit and Kit.OuterRailInset then
		local ins = Kit:OuterRailInset()
		side = math.max(side, math.max(ins[1], ins[2]) + G.PANEL_PAD + G.EDGE_GAP)
		moneyY = math.max(moneyY, ins[4] + G.EDGE_GAP)
		foot = math.max(foot, moneyY + G.MONEY_H + G.EDGE_GAP + G.PANEL_PAD)
	end
	G.INSET, G.FOOT_NOW, G.MONEY_Y_NOW = side, foot, moneyY
	G.WIDTH = G.CONTENT_W + 2 * side
	local f = win.frame
	if win.content then
		win.content:ClearAllPoints()
		win.content:SetPoint("TOPLEFT", f, "TOPLEFT", side, -G.TOP)
	end
	if win.sort then
		win.sort:ClearAllPoints()
		win.sort:SetPoint("TOPRIGHT", f, "TOPRIGHT", -side, G.ROW_Y)
	end
	if win.money then
		win.money:ClearAllPoints()
		win.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -side + 4, moneyY)
	end
end

-- (0.21.1) the kinds laid in the view S, on its content, on G's grid (set for it): the height they take
local function LayKinds()
	S.content:SetWidth(G.CONTENT_W)
	ReadBags()
	S.stamp = S.stamp + 1
	at.x, at.y, at.rowH, at.laid, at.lineDue, at.nLines, at.nPlus = 0, 0, 0, false, false, 0, 0
	local holding = CursorItem() ~= nil   -- (an item held: a + slot in every kind on, the groups open)
	S.holding = holding
	-- (the headings of kinds and groups not shown this time are hidden after: a kind
	-- emptied or switched off, a trade type gone, the split off, a group emptied)
	for _, h in pairs(S.headings) do
		h.laid = false
	end
	for _, h in pairs(S.groupHeads) do
		h.laid = false
	end
	local skipping = false   -- (the kinds of a folded group: passed by)
	local nOrder = Order()
	for i = 1, nOrder do
		local t, key = orderType[i], order[i]
		if t == "line" then
			at.lineDue, skipping = true, false
		elseif t == "group" then
			skipping = false
			local count = GroupCount(i, nOrder, holding)
			if count > 0 then
				DueLine()
				NewRow()
				local gh = GroupHead(orderName[i])
				local folded = GroupFolded(orderName[i]) and not holding
				LayGroupHead(gh, folded, count)
				gh:ClearAllPoints()
				gh:SetPoint("TOPLEFT", S.content, "TOPLEFT", 0, -at.y)
				gh:Show()
				gh.laid = true
				at.y = at.y + G.GROUP_H
				at.laid = true
				skipping = folded
			end
		elseif not skipping then
			local list = S.byKind[key]
			local n = key == "empty" and S.nEmpties or (list and #list or 0)
			local plus = holding and TakesPlus(key)
			local h = (n > 0 or plus) and Heading(key, orderName[i]) or S.headings[key]
			local fold = S.folds[key]
			if n > 0 or plus then
				DueLine()
				h.laid = true
				local folded = key ~= "empty" and Folded(key) and n > 1
				if key == "junk" then
					h.worth:SetText(S.junkWorth and S.junkWorth > 0 and GetMoneyString(S.junkWorth, true) or "")
					h.worth:SetShown(not SellShown())
				end
				LayHeading(h, folded)
				local shown = folded and 1 or n
				local items = shown + (plus and 1 or 0)
				local hw = HeadingWidth(h, key)
				local cols = math.min(items, G.COLS)
				local w = math.min(math.max(cols * G.PITCH - G.GAP, hw), G.CONTENT_W)
				if at.x > 0 and at.x + G.KIND_GAP + w > G.CONTENT_W then
					-- (0.20.4, bag_kinds_sketch: a big kind wraps in the room its row has left -- Hearthstone and
					-- Consumable share a row -- while that makes it at most one line taller than a row of its own)
					local room = G.CONTENT_W - at.x - G.KIND_GAP
					local fit = math.floor((room + G.GAP) / G.PITCH)
					if fit >= 2 and hw <= room and math.ceil(items / fit) <= math.ceil(items / G.COLS) + 1 then
						cols = math.min(items, fit)
						w = math.max(cols * G.PITCH - G.GAP, hw)
						at.x = at.x + G.KIND_GAP
					else
						NewRow()
					end
				elseif at.x > 0 then
					at.x = at.x + G.KIND_GAP
				end
				local x, y = at.x, at.y
				local nLines = math.ceil(items / cols)
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", S.content, "TOPLEFT", x, -y)
				h:SetWidth(w)
				h:Show()
				if key == "empty" then
					h.free = 0
					for j = 1, n do
						local e = S.empties[j]
						local b = SlotButton(e.bag, e.slot)
						FillEmpty(b, e.free)
						Place(b, x + ((j - 1) % cols) * G.PITCH, y + G.HEAD + math.floor((j - 1) / cols) * G.PITCH)
						h.free = h.free + (e.free or 1)
					end
				else
					for j = 1, shown do
						local e = list[j]
						local b = SlotButton(e.bag, e.slot)
						Fill(b, e)
						Place(b, x + ((j - 1) % cols) * G.PITCH, y + G.HEAD + math.floor((j - 1) / cols) * G.PITCH)
					end
					if plus then
						at.nPlus = at.nPlus + 1
						LayPlus(at.nPlus, key, x + (shown % cols) * G.PITCH, y + G.HEAD + math.floor(shown / cols) * G.PITCH)
					end
				end
				if folded then
					fold:SetText(n)
					fold:ClearAllPoints()
					fold:SetPoint("BOTTOMLEFT", S.content, "TOPLEFT", x + G.SLOT + 3, -(y + G.HEAD + G.SLOT))
					fold:Show()
				else
					fold:Hide()
				end
				at.rowH = math.max(at.rowH, G.HEAD + nLines * G.PITCH - G.GAP)
				at.x = x + w
				at.laid = true
			end
		end
	end
	local y, rowH = at.y, at.rowH
	for _, gh in pairs(S.groupHeads) do
		if not gh.laid and gh:IsShown() then
			gh:Hide()
		end
	end
	for i = at.nLines + 1, #S.lines do
		S.lines[i].light:Hide()
		S.lines[i].dark:Hide()
	end
	for i = at.nPlus + 1, #S.pluses do
		S.pluses[i]:Hide()
	end
	-- the headings and buttons this layout did not lay: hidden
	for key, h in pairs(S.headings) do
		if not h.laid and h:IsShown() then
			h:Hide()
			S.folds[key]:Hide()
		end
	end
	for _, b in ipairs(S.made) do
		if used[b] ~= S.stamp and b:IsShown() then
			b:Hide()
		end
	end
	local height = y + rowH
	S.content:SetHeight(math.max(height, 1))
	Dress()
	return height
end

-- the bag window laid: its grid, its kinds, its height, the Sell Junk button
function M:Layout()
	if not win.frame then
		return
	end
	S = BAGS
	FitSearch()
	Grid()
	Insets()
	win.frame:SetWidth(G.WIDTH)
	local height = LayKinds()
	-- For 5 Minutes: laid out again as the first item leaves Recent (one
	-- timer at a time, unless an earlier end comes)
	if recentEnds and not (win.expiryAt and win.expiryAt <= recentEnds) then
		win.expiryAt = recentEnds
		C_Timer.After(math.max(recentEnds - GetTime(), 0) + 0.2, RecentEnded)
	end
	win.frame:SetHeight(G.TOP + math.max(height, G.SLOT) + G.FOOT_NOW)
	-- the Sell Junk button on Junk's heading, at a vendor
	local sell = win.sell
	if SellShown() and S.headings.junk.laid then
		sell:ClearAllPoints()
		sell:SetPoint("RIGHT", S.headings.junk, "RIGHT", 0, 0)
		sell:Show()
	else
		sell:Hide()
	end
	MelloUI:Fire("bagwindow", true)
end

-- every view that shows laid again (a heading or group folded, a setting changed, the bags or the bank changed)
local function LayAll()
	if win.frame and win.frame:IsShown() then
		M:Layout()
	end
	if BankShown() then
		M:BankLayout()
	end
end

-- the items' marks only (the lock while one is moved, the search, the cooldowns): no new layout -- in every view
-- that shows
local function RefreshView(v)
	local C = C_Container
	for _, b in ipairs(v.made) do
		if b:IsShown() then
			local info = C.GetContainerItemInfo(b:GetBagID(), b:GetID())
			SetItemButtonDesaturated(b, info and info.isLocked)
			b:SetMatchesSearch(not (info and info.isFiltered))
			b:UpdateCooldown(info and info.iconFileID)
		end
	end
end
local function Refresh()
	if win.frame and win.frame:IsShown() then
		RefreshView(BAGS)
	end
	if BankShown() then
		RefreshView(BANK)
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
		for _, e in ipairs(S.byKind.junk) do
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
	-- the game's own backpack corner (the user, 2026-10-10: the game windows' top-left portrait and its border stay
	-- the game's; "you did not make that change on the backpack"): the shell's ring.game -- the game's corner art,
	-- the backpack icon round at the game's portrait size and place, in both looks
	win.shell = Kit:OwnWindow(f, {
		area = AREA, plate = "rail",
		ring = { at = "tl", texture = "Interface\\Buttons\\Button-Backpack-Up", game = true, bag = 0 },   -- (the backpack's portrait)
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
	BAGS.content = content
	-- the search row: the game's own bag search (its text kept with the
	-- game's other search boxes; what does not match is dimmed)
	local sort = CreateFrame("Button", nil, f)
	sort:SetSize(28, G.ROW_H)
	sort:SetNormalAtlas("bags-button-autosort-up")
	sort:SetPushedAtlas("bags-button-autosort-down")
	W.HoverLight(sort, "square")   -- (the game's sort button's light: the shared one)
	sort:SetPoint("TOPRIGHT", f, "TOPRIGHT", -G.SIDE, G.ROW_Y)
	Perf.SetScript(sort, "OnClick", SortClick)
	Perf.SetScript(sort, "OnEnter", SortEnter)
	Perf.SetScript(sort, "OnLeave", W.TipLeave)
	win.sort = sort
	local search = CreateFrame("EditBox", nil, f, "BagSearchBoxTemplate")
	search:SetHeight(G.ROW_H)
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
	-- Windows > Bags; 0.19.9 (the user, 2026-10-09: "why arent the cogwheel ... changed"): the NewUI2 cog plate, the
	-- gear in the game's look only
	local settings, gear = W.PlateButton(f, 28, G.ROW_H, 16, AREA, SETTINGS_SCRIPTS, "cog")
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
	win.sell:SetFrameLevel(S.headings.junk:GetFrameLevel() + 2)
	win.sell:Hide()
	W.Dress(f, win.shell)
	-- the look switched: the slots dressed as the game's bag slots, or left in the game's look; the money's ink with
	-- the page (the Window Background is the kit look's)
	win.shell:OnKit(function(_, on)
		if on then
			S = BAGS
			S.undressed = #S.made
			Dress()
		end
		InkMoney()
		-- (the insets follow the look: laid out again)
		if win.content and win.frame:IsShown() then
			M:Layout()
		end
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
	"MERCHANT_SHOW", "MERCHANT_CLOSED", "GET_ITEM_INFO_RECEIVED", "CURSOR_CHANGED",
	"PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED" }   -- (0.21.1: the bank's; registered only where the client has them)
local MARK_EVENTS = { "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "INVENTORY_SEARCH_UPDATE" }

local relay = false
function LayoutSoon()
	if relay then
		return
	end
	relay = true
	C_Timer.After(0, function()
		relay = false
		LayAll()
	end)
end

local OnEvent = Shared("OnEvent of the bag window", function(_, event, arg1)
	if event == "PLAYER_REGEN_ENABLED" then
		if M.pending then
			M.pending = nil
			M:Apply()
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if S.junkWorth == nil then
			LayoutSoon()
		end
	elseif event == "UNIT_QUEST_LOG_CHANGED" then
		if arg1 == "player" then
			LayoutSoon()
		end
	elseif event == "CURSOR_CHANGED" then
		-- (0.20.4) an item picked up or put down: the + slots shown or gone (0.21.1: in the bags or the bank)
		local held = CursorItem() ~= nil
		if (win.frame and win.frame:IsShown() and held ~= (BAGS.holding or false))
			or (BankShown() and held ~= (BANK.holding or false)) then
			LayoutSoon()
		end
	elseif event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_COOLDOWN" or event == "INVENTORY_SEARCH_UPDATE" then
		Refresh()
	else
		LayoutSoon()
	end
end, "event")

-- (0.21.1) while the bag window or the bank by kind shows (`on` ignored: both asked)
function Listen()
	if not events then
		events = CreateFrame("Frame")
		Perf.SetScript(events, "OnEvent", OnEvent)
	end
	local on = (win.frame and win.frame:IsShown()) or BankShown()
	for _, list in ipairs({ LAYOUT_EVENTS, MARK_EVENTS }) do
		for _, ev in ipairs(list) do
			if on then
				pcall(events.RegisterEvent, events, ev)
			else
				pcall(events.UnregisterEvent, events, ev)
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
	M.BankSwitched()
end

--------------------------------------------------------------------------------
-- The bank by kind (0.21.1; the user, 2026-10-13: "modification to bank aswell", then the kinds "inside the bank
-- window"): the bank window stays the game's -- the banker, a right-click deposit from the bags (its bank type), a
-- tab bought, its close, the Bank Kit's dress -- and its item grid is taken by the kinds: as the game lays its grid
-- (post-hooks) its own item buttons are hidden and the BANK view lays the kinds where they stood, by the bags' engine
-- (the game's ContainerFrameItemButtonTemplate on the bank tabs' containers, as the bags'), the window as tall as they
-- need. A bank type's side tab stays only where the game shows more than one bank type (an account bank: none on
-- Forever, the user's /bankdump of 2026-10-13), the first page's; the other pages' go (the kinds show every page).
--------------------------------------------------------------------------------

local BANK_X, BANK_Y = 40, -60   -- the kinds' top left in the bank panel (the game's first slot: 47, -63)
local BANK_FOOT = 118            -- the window under its grid (the game's: 460 for six rows of 47 from -63)
local BANK_MIN = 460             -- the game's own height for its smallest grid

local function BankOn()
	return M.isEnabled and M.db and M.db.bank ~= false and true or false
end

local function BankParts()
	local bf = rawget(_G, "BankFrame")
	return bf, bf and bf.BankPanel
end

function BankShown()
	local c = BANK.content
	return BankOn() and c ~= nil and c:IsVisible() and true or false
end

-- the game's own grid hidden (shown again: `back`), its pages' tabs but each bank type's first while it shows two
local function GameGrid(back)
	local bf, panel = BankParts()
	local pool = panel and panel.itemButtonPool
	if pool and pool.EnumerateActive then
		for b in pool:EnumerateActive() do
			if back then
				b:Show()
			else
				b:Hide()
			end
		end
	end
	local tabs = bf and bf.bankPageTabPool
	if tabs and tabs.EnumerateActive then
		local types, n = {}, 0
		for t in tabs:EnumerateActive() do
			if t.bankType ~= nil and not types[t.bankType] then
				types[t.bankType] = true
				n = n + 1
			end
		end
		for t in tabs:EnumerateActive() do
			t:SetShown(back or (n > 1 and t.pageNumber == 1))
		end
	end
end

-- the bank laid by kind: the game's grid hidden, the kinds where it stood, the window as tall as they need
function M:BankLayout()
	local bf, panel = BankParts()
	if not (BankOn() and panel and bf:IsShown()) then
		return
	end
	if not BANK.content then
		local c = CreateFrame("Frame", nil, panel)
		c:SetPoint("TOPLEFT", panel, "TOPLEFT", BANK_X, BANK_Y)
		c:SetFrameLevel(panel:GetFrameLevel() + 5)
		BANK.content = c
	end
	BANK.content:Show()
	GameGrid(false)
	S = BANK
	Grid()
	local w = (Num(panel:GetWidth()) or 480) - 2 * BANK_X
	G.COLS = math.max(4, math.floor((w + G.GAP) / G.PITCH))
	G.CONTENT_W = G.COLS * G.PITCH - G.GAP
	local height = LayKinds()
	S = BAGS
	Grid()   -- (the bags' grid back)
	local h = math.max(BANK_MIN, -BANK_Y + height + BANK_FOOT)
	if math.abs((Num(bf:GetHeight()) or 0) - h) > 0.5 then
		MelloUI.Perf.WriteBack("bank by kind: the bank window's height")
		bf:SetHeight(h)
		panel:SetHeight(h)
	end
	Listen()
end

-- the game laid its grid or its pages' tabs: ours again (while on)
local BankGrid = Shared("the bank grid's post-hook (the bank by kind)", function()
	if BankOn() then
		M:BankLayout()
	end
end, "hook")
local BankTabs = Shared("the bank page tabs' post-hook (the bank by kind)", function()
	if BankShown() then
		GameGrid(false)
	end
end, "hook")
local BankClosed = Shared("OnHide on the game's bank window (the bank by kind)", function()
	if BANK.content then
		BANK.content:Hide()
	end
	Listen()
end, "script")

local bankHooked = false
local function HookBank()
	local bf, panel = BankParts()
	if bankHooked or not (panel and type(panel.GenerateItemSlotsForSelectedTab) == "function") then
		return
	end
	bankHooked = true
	hooksecurefunc(panel, "GenerateItemSlotsForSelectedTab", BankGrid)
	if type(bf.RefreshPageTabs) == "function" then
		hooksecurefunc(bf, "RefreshPageTabs", BankTabs)
	end
	Perf.HookScript(bf, "OnHide", BankClosed)
end

-- Bank by Kind switched (or the module): on, the kinds at once if the bank shows; off, the game's grid back (its
-- height the game's again at its next lay)
function M.BankSwitched()
	if BankOn() then
		HookBank()
		local bf = BankParts()
		if bf and bf:IsShown() then
			M:BankLayout()
		end
	elseif BANK.content and BANK.content:IsShown() then
		BANK.content:Hide()
		GameGrid(true)
		Listen()
	end
end
M.LayAll, M.BANK = LayAll, BANK   -- (the headings' clicks; the tests)

-- (the bag slots' dock and others ask whether the window shows)
function ns.BagWindowShown()
	local f = win.frame
	return (M.isEnabled and captured and f and f:IsShown()) and f or nil
end

--------------------------------------------------------------------------------
-- Kinds on Windows > Bags (0.20.4, the user's pick A of bag_kinds_sketch: W.OrderList): the order, its lines and
-- groups, a tick each; every change saved as the module's kindOrder / kindOff (the bus's 'setting': laid out again)
--------------------------------------------------------------------------------

-- the order as it stands, a copy to change and save
local function OrderCopy()
	local out = {}
	for i, v in ipairs(ReadOrder()) do
		out[i] = v
	end
	return out
end

local function SaveOrder(list)
	MelloUI:NotifySettingChanged(M.name, "kindOrder", list)
end

-- (0.21.1) a kind's note on its row: your own, split by type (else the game's kind's own note)
local function KindNote(v)
	local note = IsOwn(v) and TEXT.ownNote or (KIND[v] and KIND[v].note) or nil
	if Split(v) and v ~= "recent" and v ~= "empty" then
		note = note and (note .. ", " .. TEXT.splitNote) or TEXT.splitNote
	end
	return note
end

local function KindRows()
	local rows, inGroup = {}, false
	local off = M.db and type(M.db.kindOff) == "table" and M.db.kindOff or nil
	for i, v in ipairs(ReadOrder()) do
		if v == "-" then
			inGroup = false
			rows[i] = { kind = "line", removable = true }
		elseif IsGroup(v) then
			inGroup = true
			rows[i] = { kind = "group", label = v:sub(7), removable = true, renamable = true }
		else
			local k = KIND[v]
			local ticked = nil
			if not (k and k.always) then
				ticked = not (off and off[v])
			end
			rows[i] = { kind = "item", id = v, label = KindName(v), note = KindNote(v), indent = inGroup and 1 or 0,
				ticked = ticked, renamable = true, settings = true }
		end
	end
	return rows
end

-- a group moves with its kinds
local function KindBlock(i)
	local o = ReadOrder()
	if not IsGroup(o[i]) then
		return 1
	end
	local n = 1
	for j = i + 1, #o do
		if o[j] == "-" or IsGroup(o[j]) then
			break
		end
		n = n + 1
	end
	return n
end

local function KindMove(from, count, to)
	local o = OrderCopy()
	local moved = {}
	for j = 1, count do
		moved[j] = table.remove(o, from)
	end
	if to > from then
		to = to - count
	end
	for j = count, 1, -1 do
		table.insert(o, to, moved[j])
	end
	SaveOrder(o)
end

local function KindTick(i, on)
	local v = ReadOrder()[i]
	if not (KnownKind(v) and not (KIND[v] and KIND[v].always)) then
		return
	end
	local off = {}
	for k, flag in pairs(type(M.db.kindOff) == "table" and M.db.kindOff or {}) do
		off[k] = flag
	end
	off[v] = (not on) or nil
	MelloUI:NotifySettingChanged(M.name, "kindOff", off)
end

local function KindRemove(i)
	local o = OrderCopy()
	if o[i] == "-" or IsGroup(o[i]) then
		table.remove(o, i)
		SaveOrder(o)
	end
end

-- (0.21.1) a kind's settings saved: a copy of the table changed, handed to the settings bus (laid out again)
local function Copy(t)
	local out = {}
	for k, v in pairs(type(t) == "table" and t or ALL_ON) do
		out[k] = v
	end
	return out
end

local function Save(key, value)
	if type(value) == "table" and next(value) == nil then
		value = nil   -- (an emptied table: none kept)
	end
	MelloUI:NotifySettingChanged(M.name, key, value)
end

-- an own kind's field (or two) set
local function SetOwn(key, field, value, field2, value2)
	local own = Copy(M.db.ownKinds)
	local e = Copy(own[key])
	e[field] = value
	if field2 then
		e[field2] = value2
	end
	own[key] = e
	Save("ownKinds", own)
end

-- a kind renamed: an own kind's name; a game kind's own name (its game name again: none kept)
local function SetName(key, text)
	text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if text == "" then
		return
	elseif IsOwn(key) then
		SetOwn(key, "name", text)
		return
	end
	local names = Copy(M.db.kindNames)
	names[key] = (KIND[key] and text ~= KIND[key].name) and text or nil
	Save("kindNames", names)
end

local function SetSplit(key, on)
	local t = Copy(M.db.kindSplit)
	t[key] = on and true or nil
	Save("kindSplit", t)
end

-- the items dropped on a kind: how many, forgotten
local function PlacedOn(key)
	local n = 0
	for _, v in pairs(type(M.db.placed) == "table" and M.db.placed or ALL_ON) do
		if v == key then
			n = n + 1
		end
	end
	return n
end

local function Forget(key)
	local placed = Copy(M.db.placed)
	for id, v in pairs(placed) do
		if v == key then
			placed[id] = nil
		end
	end
	Save("placed", placed)
end

local kindList   -- the Kinds list (W.OrderList), once built

local function RefreshKinds()
	if kindList then
		kindList:Refresh()
	end
end

-- an own kind removed (asked first): its entry, its place, its tick, split and fold, the items dropped on it
local function RemoveKind(key)
	MelloUI:Confirm({
		text = TEXT.removeAsk:format(KindName(key)),
		accept = TEXT.removeAccept,
		onAccept = function()
			local own = Copy(M.db.ownKinds)
			own[key] = nil
			local o = {}
			for _, v in ipairs(ReadOrder()) do
				if v ~= key then
					o[#o + 1] = v
				end
			end
			for _, t in ipairs({ "kindOff", "kindSplit", "folded" }) do
				if type(M.db[t]) == "table" and M.db[t][key] ~= nil then
					local c = Copy(M.db[t])
					c[key] = nil
					Save(t, c)
				end
			end
			Forget(key)
			Save("ownKinds", own)
			SaveOrder(o)
			if kindList then
				kindList:Open(nil)
			end
		end,
	})
end

-- a new own kind on top of the list, its settings open
local function AddKind()
	local n = (Num(M.db.ownN) or 0) + 1
	M.db.ownN = n
	local key = "own:" .. n
	local own = Copy(M.db.ownKinds)
	own[key] = { name = TEXT.newKind }
	Save("ownKinds", own)
	local o = OrderCopy()
	table.insert(o, 1, key)
	SaveOrder(o)
	if kindList then
		kindList:Open(key)
	end
	return key
end
M.AddKind, M.SetName, M.SetSplit, M.SetOwn = AddKind, SetName, SetSplit, SetOwn   -- (the tests)

local function KindRename(i, text)
	local o = OrderCopy()
	if IsGroup(o[i]) then
		o[i] = "group:" .. text
		SaveOrder(o)
	elseif KnownKind(o[i]) then
		SetName(o[i], text)
	end
end

-- (0.21.1, the user's pick 2A of bag_own_kinds_sketch) a kind's settings, opened under its row: its name; Split By
-- Type; an own kind's rule (an item type and subtype, a word in the name, a quality: all set must hold); the items
-- dropped on it, forgotten; an own kind removed. The controls made once on the list's holder, filled for the kind open
local D = { LABEL_X = 12, FIELD_X = 150, ROW = 32, FIELD_W = 220 }   -- (one table: the file's locals)
D.CLASSES = { 0, 1, 2, 4, 3, 5, 6, 7, 9, 11, 12, 13, 15 }   -- the item types an own kind may take (Enum.ItemClass)
D.subValues = {}   -- [classID] = its subtypes' values, read on first need

-- the item types / one type's subtypes / the qualities, as dropdown values (read from the client on first need)
function D.Types()
	if not D.types then
		local C = C_Item
		D.types = { { value = -1, label = TEXT.any } }
		for _, id in ipairs(D.CLASSES) do
			local name = C and C.GetItemClassInfo and C.GetItemClassInfo(id)
			name = type(name) == "string" and name ~= "" and name or (KIND[CLASS_KIND[id]] and KIND[CLASS_KIND[id]].name)
			if name then
				D.types[#D.types + 1] = { value = id, label = name }
			end
		end
	end
	return D.types
end

function D.Subtypes(classID)
	classID = Num(classID)
	if not classID then
		return { { value = -1, label = TEXT.any } }
	end
	local list = D.subValues[classID]
	if not list then
		list = { { value = -1, label = TEXT.any } }
		local C = C_Item
		for sub = 0, 30 do
			local name = C and C.GetItemSubClassInfo and C.GetItemSubClassInfo(classID, sub)
			if type(name) == "string" and name ~= "" then
				list[#list + 1] = { value = sub, label = name }
			end
		end
		D.subValues[classID] = list
	end
	return list
end

function D.Qualities()
	if not D.qualities then
		local names = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
		D.qualities = { { value = -1, label = TEXT.any } }
		for q = 0, 5 do
			local name = rawget(_G, "ITEM_QUALITY" .. q .. "_DESC")
			names[q] = type(name) == "string" and name ~= "" and name or names[q]
			D.qualities[#D.qualities + 1] = { value = q, label = names[q] }
		end
		for q = 2, 4 do
			D.qualities[#D.qualities + 1] = { value = 10 + q, label = TEXT.orBetter:format(names[q]) }
		end
	end
	return D.qualities
end

-- an edit box of the settings (a name, a word): saved on Enter and as it loses focus, Escape puts it back
D.BoxSave = Shared("OnEnterPressed / OnEditFocusLost in a bag kind's settings box", function(box)
	local key = box.holder.key
	if box.saving or not key then
		return
	end
	box.saving = true
	local text = box:GetText()
	if box.field == "name" then
		SetName(key, text)
	elseif Own(key) then
		text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
		SetOwn(key, "nameHas", text ~= "" and text or nil)
	end
	box:ClearFocus()
	box.saving = false
	RefreshKinds()
end, "script")
D.BoxEscape = Shared("OnEscapePressed in a bag kind's settings box", function(box)
	box.saving = true
	box:ClearFocus()
	box.saving = false
	RefreshKinds()
end, "script")

function D.Box(holder, field)
	local box = CreateFrame("EditBox", nil, holder)
	box:SetAutoFocus(false)
	box:SetSize(D.FIELD_W, 22)
	box:SetFontObject("GameFontHighlight")
	box:SetTextInsets(6, 6, 0, 0)
	box:SetMaxLetters(32)
	box.field, box.holder = field, holder
	W.Field(box)
	Perf.SetScript(box, "OnEnterPressed", D.BoxSave)
	Perf.SetScript(box, "OnEditFocusLost", D.BoxSave)
	Perf.SetScript(box, "OnEscapePressed", D.BoxEscape)
	return box
end

function D.Label(holder, text, font, key)
	return W.Text(holder, font or "GameFontHighlight", text, key or "text")
end

-- an own kind's rule field read (nil: not set)
function D.Rule(key, field)
	local o = Own(key)
	return o and Num(o[field]) or nil
end

function D.Make(holder)
	local c = {}
	local fill = W.Solid(holder, "BACKGROUND", "mainWindow", 1)
	fill:SetAllPoints(holder)
	W.Edges(holder, "trim", "BORDER")
	c.nameLabel = D.Label(holder, TEXT.name)
	c.name = D.Box(holder, "name")
	c.split = W.Switch(holder, function()
		return Split(holder.key)
	end, function(on)
		SetSplit(holder.key, on)
		RefreshKinds()
	end)
	c.splitLabel = D.Label(holder, TEXT.split)
	c.splitTip = D.Label(holder, TEXT.splitTip, "GameFontHighlightSmall")
	c.takes = D.Label(holder, TEXT.takes, "GameFontNormal", "selectedTrim")
	c.takesTip = D.Label(holder, TEXT.takesTip, "GameFontHighlightSmall")
	c.typeLabel = D.Label(holder, TEXT.itemType)
	c.type = W.Dropdown(holder, D.FIELD_W, function()
		return D.Rule(holder.key, "class") or -1
	end, function(v)
		v = Num(v)
		SetOwn(holder.key, "class", (v and v >= 0) and v or nil, "subclass", nil)
		RefreshKinds()
	end, D.Types())
	c.subLabel = D.Label(holder, TEXT.subtype)
	c.sub = W.Dropdown(holder, D.FIELD_W, function()
		return D.Rule(holder.key, "subclass") or -1
	end, function(v)
		v = Num(v)
		SetOwn(holder.key, "subclass", (v and v >= 0) and v or nil)
		RefreshKinds()
	end, D.Subtypes(nil))
	c.hasLabel = D.Label(holder, TEXT.nameHas)
	c.has = D.Box(holder, "nameHas")
	c.qualityLabel = D.Label(holder, TEXT.quality)
	c.quality = W.Dropdown(holder, 160, function()
		return D.Rule(holder.key, "quality") or -1
	end, function(v)
		v = Num(v)
		SetOwn(holder.key, "quality", (v and v >= 0) and v or nil)
		RefreshKinds()
	end, D.Qualities())
	c.dropped = D.Label(holder, "")
	c.forget = W.Button(holder, TEXT.forget, 110, nil, { onClick = function()
		MelloUI:PlayUISound("check_off")
		Forget(holder.key)
		RefreshKinds()
	end })
	c.remove = W.Button(holder, TEXT.remove, 110, nil, { onClick = function()
		RemoveKind(holder.key)
	end })
	return c
end

-- a control on its row of the settings (the label at the left, the field at FIELD_X), y px below the top
local function At(region, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", region:GetParent(), "TOPLEFT", x, -y)
	region:Show()
end

-- what a kind's settings hold: the name, Split By Type (not Recent's, not Empty's), an own kind's rule (5 rows), the
-- items dropped on it (a kind that takes them) -- in rows of D.ROW
function D.Parts(key)
	local split = key ~= "recent" and key ~= "empty"
	local own = Own(key) ~= nil
	local drops = key ~= "recent" and key ~= "empty"
	return split, own, drops
end

function D.Rows(r)
	local split, own, drops = D.Parts(r.id)
	local px = 12 + D.ROW * (1 + (split and 1 or 0) + (own and 5 or 0) + (drops and 1 or 0))
	return math.ceil((px + 6) / 26)
end

function D.Fill(holder, r)
	local key = r.id
	local c = holder.kindParts
	if not c then
		c = D.Make(holder)
		holder.kindParts = c
	end
	holder.key = key
	local split, own, drops = D.Parts(key)
	local y = 10
	At(c.nameLabel, D.LABEL_X, y + 4)
	At(c.name, D.FIELD_X, y)
	if not c.name:HasFocus() then
		c.name:SetText(KindName(key))
	end
	y = y + D.ROW
	c.split:SetShown(split)
	c.splitLabel:SetShown(split)
	c.splitTip:SetShown(split)
	if split then
		At(c.split, D.LABEL_X - 4, y - 3)
		c.split:Refresh()
		At(c.splitLabel, D.LABEL_X + 26, y + 4)
		At(c.splitTip, D.FIELD_X, y + 6)
		y = y + D.ROW
	end
	for _, part in ipairs({ c.takes, c.takesTip, c.typeLabel, c.type, c.subLabel, c.sub, c.hasLabel, c.has,
		c.qualityLabel, c.quality, c.remove }) do
		part:SetShown(own)
	end
	if own then
		At(c.takes, D.LABEL_X, y + 4)
		At(c.takesTip, D.LABEL_X + 60, y + 6)
		y = y + D.ROW - 6
		At(c.typeLabel, D.LABEL_X, y + 4)
		At(c.type, D.FIELD_X, y)
		c.type:Refresh()
		y = y + D.ROW
		At(c.subLabel, D.LABEL_X, y + 4)
		At(c.sub, D.FIELD_X, y)
		c.sub:SetValues(D.Subtypes(D.Rule(key, "class")))
		c.sub:Refresh()
		y = y + D.ROW
		At(c.hasLabel, D.LABEL_X, y + 4)
		At(c.has, D.FIELD_X, y)
		if not c.has:HasFocus() then
			local o = Own(key)
			c.has:SetText(o and type(o.nameHas) == "string" and o.nameHas or "")
		end
		y = y + D.ROW
		At(c.qualityLabel, D.LABEL_X, y + 4)
		At(c.quality, D.FIELD_X, y)
		c.quality:Refresh()
		y = y + D.ROW + 6
	end
	c.dropped:SetShown(drops)
	c.forget:SetShown(drops)
	if drops then
		local n = PlacedOn(key)
		c.dropped:SetText(TEXT.dropped:format(n))
		At(c.dropped, D.LABEL_X, y + 5)
		At(c.forget, D.FIELD_X + 80, y)
		c.forget:SetEnabled(n > 0)
		if own then
			At(c.remove, D.FIELD_X + 200, y)
		end
	elseif own then
		At(c.remove, D.FIELD_X, y)
	end
end
M.KindDetail = D   -- (the tests)

local KIND_LIST = {
	title = TEXT.kindsTitle, help = TEXT.kindsHelp,
	rows = KindRows, block = KindBlock, move = KindMove, tick = KindTick, remove = KindRemove, rename = KindRename,
	detail = D.Fill, detailRows = D.Rows,
	buttons = {
		{ TEXT.addKind, AddKind },
		{ TEXT.addLine, function()
			local o = OrderCopy()
			table.insert(o, 1, "-")
			SaveOrder(o)
		end },
		{ TEXT.addGroup, function()
			local o = OrderCopy()
			table.insert(o, 1, "group:" .. TEXT.newGroup)
			SaveOrder(o)
		end },
		{ TEXT.resetOrder, function()
			MelloUI:NotifySettingChanged(M.name, "kindOrder", nil)
		end },
	},
}

local function RefreshKindList(canvas)
	if canvas.list then
		canvas.list:Refresh()
	end
end

function M.BuildKindList(canvas, width)
	local list = W.OrderList(canvas, math.min((Num(width) or 600) - 28, 560), KINDS_H - 12, KIND_LIST)
	list.frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 14, -6)
	canvas.list = list
	canvas.Refresh = RefreshKindList
	kindList = list
end

--------------------------------------------------------------------------------
-- Loot Flight (0.21.3; the user, 2026-10-13: "Yes to all" to BuildData/output/
-- animation_previews, 4. Loot into the bags, and "more impactfull animations
-- depending on the rarity of the item"): an item looted flies from where it
-- was picked up -- the pointer as it came (on the corpse, or on the loot
-- window's row) -- into its slot in this window (laid out first, in its
-- kind), or with the bags closed onto the bag button; the rarer the more
-- (MelloUI.FrameFX's loot look). A legendary flashes this window's border as
-- it lands and says its name (MelloUI:Announce). Only loot and a quest's
-- reward: from the loot window's or the reward window's opening (auto loot
-- too) to LINGER seconds after it closes -- never a purchase, the mail or a
-- craft. A quest turned in (Animations 6, "Turning in a quest") also sends
-- its money as COINS coins (FX.Loot's coin) from the pointer into this
-- window's money, which counts up as each lands (Fly.Coins; MoneyFrame_Update
-- on the window's own money frame, the real sum at the end), or with the bags
-- closed onto the bag button. The pushes (ITEM_PUSH: the bag and
-- the icon) are matched to their slots once the bags are updated (the game's
-- new-item mark first); up to MAX at once, STAGGER apart. Its events only
-- while the option is on; its records reused; the engine's layers made at
-- its first flight. Not under Reduce Motion (FX.Loot's own door)
--------------------------------------------------------------------------------

local Fly = { AFTER = 0.05, FALLBACK = 0.4, STAGGER = 0.08, LINGER = 1.5, MAX = 8, SPILL = 3, COINS = 6, COIN_GAP = 0.08,
	COIN_ICONS = { "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" },
	coin = { sum = 0, from = 0, landed = 0 },
	open = false, closedAt = -100, n = 0, pushes = {}, queue = {}, q = 0, due = false, tints = {}, spill = {},
	taken = {} }

function Fly.On()
	return M.isEnabled and M.db ~= nil and M.db.lootFlight ~= false
end

-- the quality's tier: 0 poor and common .. 4 legendary and up
function Fly.Tier(quality)
	quality = Num(quality) or 1
	return quality <= 1 and 0 or math.min(4, quality - 1)
end

-- the quality's colour, the game's (a meaning colour): { r, g, b, hex = "#rrggbb" }, read once
function Fly.Tint(quality)
	quality = Num(quality) or 1
	local t = Fly.tints[quality]
	if t then
		return t
	end
	local r, g, b
	if C_Item and C_Item.GetItemQualityColor then
		local ok, r1, g1, b1 = pcall(C_Item.GetItemQualityColor, quality)
		if ok then
			r, g, b = Num(r1), Num(g1), Num(b1)
		end
	end
	if not (r and g and b) then
		local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[quality]   -- look-ok: the game's quality colours
		r, g, b = c and Num(c.r), c and Num(c.g), c and Num(c.b)
	end
	if not (r and g and b) then
		return nil
	end
	t = { r, g, b, hex = string.format("#%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)) }
	Fly.tints[quality] = t
	return t
end

-- the pointer in UIParent's units (nil when it cannot be read)
function Fly.Pointer()
	local x, y = GetCursorPosition()
	x, y = Num(x), Num(y)
	local k = Num(UIParent:GetEffectiveScale())
	if not (x and y and k and k > 0) then
		return nil
	end
	return x / k, y / k
end

-- the slot an icon came into: one the game marks new first, else the first
-- holding it, not taken by another push of this pass (`used`)
function Fly.Find(icon, taken)
	local fb, fs, finfo
	for _, bag in ipairs(HeldBags()) do
		local okN, count = pcall(C_Container.GetContainerNumSlots, bag)
		for slot = 1, (okN and Num(count)) or 0 do
			if not taken[bag * 1000 + slot] then
				local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
				if ok and type(info) == "table" and Num(info.iconFileID) == icon then
					local okNew, new = pcall(C_NewItems.IsNewItem, bag, slot)
					if okNew and new == true then
						return bag, slot, info
					end
					if not fb then
						fb, fs, finfo = bag, slot, info
					end
				end
			end
		end
	end
	return fb, fs, finfo
end

-- the pushes of a loot matched to their slots and queued (reused records)
function Fly.Go()
	Fly.due = false
	if Fly.n == 0 or not Fly.On() then
		Fly.n = 0
		return
	end
	local taken = Fly.taken
	wipe(taken)
	for i = 1, Fly.n do
		local p = Fly.pushes[i]
		local bag, slot, info = Fly.Find(p.icon, taken)
		if bag and Fly.q < Fly.MAX then
			taken[bag * 1000 + slot] = true
			Fly.q = Fly.q + 1
			local r = Fly.queue[Fly.q] or {}
			Fly.queue[Fly.q] = r
			r.x, r.y, r.bag, r.slot, r.icon = p.x, p.y, bag, slot, p.icon
			r.quality = Num(info.quality) or 1
			local name = info.itemName
			if not (type(name) == "string" and not Secret(name)) and C_Item and C_Item.GetItemNameByID then
				local okName, n = pcall(C_Item.GetItemNameByID, Num(info.itemID))
				name = okName and type(n) == "string" and not Secret(n) and n or nil
			end
			r.name = type(name) == "string" and not Secret(name) and name or nil
		end
	end
	Fly.n = 0
	Fly.Next()
end

-- the next queued item away (then the one after it, STAGGER later)
function Fly.Next()
	if Fly.q == 0 then
		return
	end
	local r = table.remove(Fly.queue, 1)
	Fly.q = Fly.q - 1
	Fly.queue[#Fly.queue + 1] = r   -- (kept for the next push, past the queue's end)
	Fly.Launch(r)
	if Fly.q > 0 then
		C_Timer.After(Fly.STAGGER, Fly.Next)
	end
end

function Fly.Launch(r)
	local FX = MelloUI.FrameFX
	if not (FX and FX.Loot and Fly.On()) then
		return
	end
	local frame, target = win.frame, nil
	if frame and frame:IsShown() then
		local list = BAGS.slots[r.bag]
		local b = list and list[r.slot]
		if b and b:IsVisible() then
			target = b
		end
	else
		local bb = _G.MainMenuBarBackpackButton
		if bb and bb:IsVisible() then
			target = bb
		end
	end
	if not target then
		return
	end
	local tier, tint = Fly.Tier(r.quality), Fly.Tint(r.quality)
	local reach = G.SLOT * Fly.SPILL
	Fly.spill[1], Fly.spill[2] = reach, reach
	local layer = FX.Loot(r.x, r.y, target, tier, r.icon, tint, Fly.spill)
	if layer and tier == 4 then
		-- a legendary: its name on the screen, in its colour; the window's
		-- border flashing as it lands
		if r.name and tint then
			MelloUI:Announce("Legendary: |cff" .. tint.hex:sub(2) .. r.name .. "|r")
		end
		local st = FX.state[layer]
		if frame and frame:IsShown() and st and st.loot then
			Fly.flashTint = tint
			C_Timer.After(st.loot.total, Fly.Flash)
		end
	end
end

function Fly.Flash()
	local FX = MelloUI.FrameFX
	if FX and FX.ShowOn and win.frame and win.frame:IsShown() then
		FX.ShowOn(win.frame, "loot", "frame", nil, Fly.flashTint)
	end
end

-- a quest's money as coins (COINS of them, COIN_GAP apart) from where the
-- pointer is to the window's money (counting up as each lands), or with the
-- bags closed to the bag button. One job (Fly.coin) drives the count; the
-- money frame shows the real sum at its end
function Fly.Coins(money)
	money = Num(money)
	local FX = MelloUI.FrameFX
	if not (money and money > 0 and FX and FX.Loot and Fly.On()) then
		return
	end
	local frame = win.frame
	local target = frame and frame:IsShown() and win.money or nil
	if not target then
		local bb = _G.MainMenuBarBackpackButton
		target = bb and bb:IsVisible() and bb or nil
	end
	local x, y = Fly.Pointer()
	if not (target and x) then
		return
	end
	local tint = Fly.Tint(1)
	local job = Fly.coin
	job.x, job.y, job.target, job.tint = x, y, target, tint
	job.sum, job.landed, job.sent = money, 0, 0
	local okM, now = pcall(GetMoney)
	now = okM and Num(now) or nil
	job.counting = target == win.money and now ~= nil and type(_G.MoneyFrame_Update) == "function"
	job.from = job.counting and math.max(0, now - money) or 0
	local L = FX.LOOT
	local total = (Fly.COINS - 1) * Fly.COIN_GAP + L.COIN_FLIGHT
	MelloUI.Anim:Drive(job, Fly.CoinStep, total, "linear", Fly.CoinsLanded)
end

-- the coins sent COIN_GAP apart, and the money counted up as each lands
function Fly.CoinStep(job, u)
	local FX = MelloUI.FrameFX
	local L = FX.LOOT
	local total = (Fly.COINS - 1) * Fly.COIN_GAP + L.COIN_FLIGHT
	local t = u * total
	while job.sent < Fly.COINS and t >= job.sent * Fly.COIN_GAP do
		job.sent = job.sent + 1
		FX.Loot(job.x, job.y, job.target, 0, Fly.COIN_ICONS[job.sent % 2 + 1], job.tint, nil, true)
	end
	local landed = 0
	for i = 1, Fly.COINS do
		if t >= (i - 1) * Fly.COIN_GAP + L.COIN_FLIGHT then
			landed = i
		end
	end
	if landed ~= job.landed then
		job.landed = landed
		if job.counting and win.money then
			pcall(_G.MoneyFrame_Update, win.money, job.from + math.floor(job.sum * landed / Fly.COINS + 0.5))
		end
	end
end

function Fly.CoinsLanded(job)
	if job.counting and win.money and type(MoneyFrame_UpdateMoney) == "function" then
		pcall(MoneyFrame_UpdateMoney, win.money)
	end
end

-- (the reward's money, a moment after the turn-in: the bags' sum is the new one then)
function Fly.TurnedIn()
	Fly.Coins(Fly.reward)
	Fly.reward = nil
end

Fly.OnEvent = Shared("OnEvent of the bag window's loot flight", function(_, event, arg1, arg2, arg3)
	if event == "LOOT_OPENED" or event == "LOOT_READY" or event == "QUEST_COMPLETE" then
		Fly.open = true
	elseif event == "LOOT_CLOSED" or event == "QUEST_FINISHED" then
		Fly.open, Fly.closedAt = false, GetTime()
	elseif event == "QUEST_TURNED_IN" then
		-- (questID, xp, money): the coins a moment later, the bags' sum the new one then
		local money = Num(arg3)
		if money and money > 0 then
			Fly.reward = money
			C_Timer.After(Fly.AFTER, Fly.TurnedIn)
		end
	elseif event == "ITEM_PUSH" then
		local icon = Num(arg2)
		if icon and Fly.n < Fly.MAX and (Fly.open or GetTime() - Fly.closedAt <= Fly.LINGER) then
			local x, y = Fly.Pointer()
			if x then
				Fly.n = Fly.n + 1
				local p = Fly.pushes[Fly.n] or {}
				Fly.pushes[Fly.n] = p
				p.icon, p.x, p.y = icon, x, y
				if not Fly.due then
					-- (the bags' update normally sends it sooner: BAG_UPDATE_DELAYED)
					Fly.due = true
					C_Timer.After(Fly.FALLBACK, Fly.Go)
				end
			end
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		if Fly.n > 0 then
			C_Timer.After(Fly.AFTER, Fly.Go)
		end
	end
end, "event")

-- its events while the option is on (and the module)
function Fly.Listen()
	local on = Fly.On()
	if not (on or Fly.frame) then
		return
	end
	if not Fly.frame then
		Fly.frame = CreateFrame("Frame")
		Perf.SetScript(Fly.frame, "OnEvent", Fly.OnEvent)
	end
	for _, ev in ipairs({ "LOOT_OPENED", "LOOT_READY", "LOOT_CLOSED", "ITEM_PUSH", "BAG_UPDATE_DELAYED", "QUEST_COMPLETE",
		"QUEST_FINISHED", "QUEST_TURNED_IN" }) do
		if on then
			pcall(Fly.frame.RegisterEvent, Fly.frame, ev)
		else
			pcall(Fly.frame.UnregisterEvent, Fly.frame, ev)
		end
	end
	if not on then
		Fly.n, Fly.open = 0, false
	end
end
M.Fly = Fly   -- (the tests)

-- (0.21.3) Loot Flight played to see it: /mello bags loot [poor | common |
-- uncommon | rare | epic | legendary | all] -- an item of that quality from
-- the pointer into the first slot shown in the bag window (its own picture
-- and name), or with the bags closed onto the bag button; all: every
-- quality, one after another. /mello bags coins: quest money flying in
Fly.SAMPLE = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5, MONEY = 1234,
	ICON = "Interface\\Icons\\INV_Misc_QuestionMark", NAME = "a made-up item", GAP = 1.4, GAP_BIG = 2.2,
	off = "Bags by Kind: Loot Flight is off (Windows > Bags), or Reduce Motion is on.",
	none = "Bags by Kind: no item is shown in the bag window to fly into." }

function Fly.Sample(quality)
	local anim = MelloUI.Anim
	if not Fly.On() or (anim and anim.reduceMotion) then
		MelloUI:Print(Fly.SAMPLE.off)
		return
	end
	local x, y = Fly.Pointer()
	if not x then
		return
	end
	local r = Fly.sample or {}
	Fly.sample = r
	r.x, r.y, r.quality, r.bag, r.slot, r.icon, r.name = x, y, quality, nil, nil, Fly.SAMPLE.ICON, nil
	if win.frame and win.frame:IsShown() then
		for _, bag in ipairs(HeldBags()) do
			for slot, b in pairs(BAGS.slots[bag] or {}) do
				if not r.bag and b:IsVisible() then
					local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
					local icon = ok and type(info) == "table" and Num(info.iconFileID)
					if icon then
						r.bag, r.slot, r.icon = bag, slot, icon
						r.name = type(info.itemName) == "string" and not Secret(info.itemName) and info.itemName or nil
					end
				end
			end
		end
		if not r.bag then
			MelloUI:Print(Fly.SAMPLE.none)
			return
		end
	end
	r.name = r.name or Fly.SAMPLE.NAME
	Fly.Launch(r)
end

-- every quality, poor to legendary, one after another
function Fly.SampleNext()
	local q = Fly.sampleQ or 0
	Fly.Sample(q)
	if q < 5 then
		Fly.sampleQ = q + 1
		C_Timer.After(q >= 3 and Fly.SAMPLE.GAP_BIG or Fly.SAMPLE.GAP, Fly.SampleNext)
	else
		Fly.sampleQ = nil
	end
end

-- (the words made in a function of their own: this file's main chunk is at Lua's limit of locals)
function Fly.Words()
	local words = {
		loot = function() Fly.Sample(Fly.SAMPLE.epic) end,
		["loot all"] = function()
			Fly.sampleQ = 0
			Fly.SampleNext()
		end,
		coins = function()
			local anim = MelloUI.Anim
			if not Fly.On() or (anim and anim.reduceMotion) then
				MelloUI:Print(Fly.SAMPLE.off)
				return
			end
			Fly.Coins(Fly.SAMPLE.MONEY)
		end,
	}
	for _, word in ipairs({ "poor", "common", "uncommon", "rare", "epic", "legendary" }) do
		words["loot " .. word] = function() Fly.Sample(Fly.SAMPLE[word]) end
	end
	return words
end
M.SlashWords = Fly.Words()

function M:OnEnable(db)
	self.db = db
	Migrate(db)
	self:Apply()
	Fly.Listen()
end

function M:OnDisable()
	self:Apply()
	Fly.Listen()
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
	if key == "bank" then
		M.BankSwitched()
	end
	if key == "lootFlight" then
		Fly.Listen()
		return
	end
	LayAll()
end

-- (the tests)
M.win = win
M.lines, M.groupHeads, M.pluses = BAGS.lines, BAGS.groupHeads, BAGS.pluses   -- (0.20.4; the bags')
