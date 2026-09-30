--------------------------------------------------------------------------------
-- MelloUI - Widgets (0.16.0)
--
-- The widget column's users besides Voice Over, and three more reminders by
-- the portrait (the user, 2026-09-29: "all 12 look awesome", each in the
-- picked look; docs/plans/next-update-refs/widget_ideas.jpg). Every one is
-- ONE spec on the widget (Core/Reminders.lua, MelloUI.Reminders:Register):
-- no window, frame or look of its own. In the column (column = true):
--   Loot Rolls      a roll waiting (START_LOOT_ROLL): the item in its quality
--                   colour, the ring the roll's time, Need / Greed / Pass
--                   (RollOnLoot), the count the rolls waiting. The game's own
--                   roll windows stay (a faded one would still take clicks)
--   Corpse Run      a ghost: how far the body is and which way, the ring the
--                   corpse recovery delay; a click shows the way (Route)
--   Timed Quests    a quest with a time limit (C_QuestLog.GetQuestTimers): the
--                   ring its whole time (GetTimeAllowed)
--   Summons         Accept / Decline (C_SummonInfo), the ring its time left
--   Resurrect       an offer: Accept / Decline, the ring the game dialog's
--                   own time (the recovery delay + 60 s)
--   Ready Checks    the leader's check and its ring; the answer is the game's
--                   box (ConfirmReadyCheck is not ours to call)
--   Whispers        the Chat module's whisper popups tell it (its bus event
--                   'whisper': no second listener): the sender in their class
--                   colour, the last line when it is plain, the unread count,
--                   Reply opens their popup
--   Hunter Pet      a pet that is not happy: its face, the ring its
--                   happiness, Feed Pet (a secure button, out of combat)
--   Auction House   outbid, sold and won (the system messages): the list in a
--                   tray, a click the way to the nearest mailbox
--   Crafting        a batch (C_TradeSkillUI.CraftRecipe, post-hooked):
--                   "Crafting 12 of 20", the ring each item's cast, Stop
--   Profession      a cooldown ready again (Transmute, Mooncloth, the Salt
--   Cooldowns       Shaker): read while the profession is open, the ready
--                   time kept per character, told once it has passed
-- By the portrait (the reminders as they are):
--   Bags Almost Full    free slots at or under Free Slots; a click: the way
--                       to the nearest vendor
--   Talent Points       points to spend
--   Well Fed Ending     the buff's last two minutes (read out of combat)
-- The column's order and fold (user, 2026-09-30; Core/Reminders.lua's
-- `priority` and `combat`): "now" -- loot rolls, summons, resurrect offers,
-- ready checks -- always show, right above Voice Over; the others ongoing,
-- but whispers, the auction house and profession cooldowns "wait" (the first
-- to fold past Most Widgets Shown) and, with Feed Pet and Crafting, fold
-- while in combat and come back after it.
-- Each has its switch on the Reminders page's Widgets tab. Nothing is made
-- or read at login: one event frame with the first OnEnable, only the
-- switched-on uses' events, and the widget builds nothing before a row or a
-- reminder comes up. Secret-safe: a secret value leaves the state as it was.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Widgets")
local C_Timer = Perf.C_Timer

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local pcall, type, floor = pcall, type, math.floor
-- (the game's namespaces this file asks, looked up once)
local C_Spell, C_Loot, C_DeathInfo, C_SummonInfo, C_UnitAuras = _G.C_Spell, _G.C_Loot, _G.C_DeathInfo,
	_G.C_SummonInfo, _G.C_UnitAuras

local NEW = "0.16.0"

local M = MelloUI:RegisterModule("Widgets", {
	title = "Widgets",
	desc = "Small live widgets in one column: loot rolls, the way back to your corpse, timed quests, summons, resurrect offers, ready checks, whispers, your pet, the auction house, crafting batches and profession cooldowns. And three more reminders by your portrait.",
	icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	flavour = "What needs you now, in one small column.",
	role = "feature",
	-- (no group: its rows sit on the Reminders page's Widgets tab, Core/ConfigLayout.lua)
	keep = { "^cd_" },   -- each character's profession cooldowns (cd_<GUID>): never in a profile
	enabledByDefault = true,
	defaults = {
		loot = true, corpse = true, timed = true, summon = true, resurrect = true, ready = true, threat = true, whisper = true,
		pet = true, auction = true, craft = true, cooldown = true,
		bags = true, bagsAt = 2, talents = true, wellfed = true,
	},
	options = {
		{ type = "header", name = "In The Column" },
		{ type = "toggle", key = "loot", name = "Loot Rolls", new = NEW,
		  desc = "A roll in a group: the item in its quality colour, a ring for the time left, and Need, Greed and Pass on hover. The count is the rolls waiting. The game's own roll window stays out of sight meanwhile (with the Gamepad UI it stays)." },
		{ type = "toggle", key = "corpse", name = "Corpse Run", new = NEW,
		  desc = "As a ghost: how far your body is and which way, and a ring until you can come back. Click it for the way there; at your body, Resurrect. The game's own Resurrect popup is see-through and click-through meanwhile." },
		{ type = "toggle", key = "timed", name = "Timed Quests", new = NEW,
		  desc = "A quest with a time limit: a ring for its whole time and the time left." },
		{ type = "toggle", key = "summon", name = "Summons", new = NEW,
		  desc = "Someone summons you: where to, the time left, and Accept or Decline on hover. The game's own popup is see-through and click-through meanwhile." },
		{ type = "toggle", key = "resurrect", name = "Resurrect Offers", new = NEW,
		  desc = "Someone offers to resurrect you: the time left, and Accept or Decline on hover. The game's own popup is see-through and click-through meanwhile." },
		{ type = "toggle", key = "ready", name = "Ready Checks", new = NEW,
		  desc = "The leader's ready check and its time, with Ready and Not Ready on hover (a click on it: Ready). The game's own box stays away meanwhile (with the Gamepad UI it stays)." },
		{ type = "toggle", key = "threat", name = "Threat", new = NEW,
		  desc = "In a group fight, only when it matters: close to pulling your target (\"Ease off\") or with it on you (\"Aggro\"), and for a tank the mobs not on you. The ring is your threat against the pull; point at it for the group's threat on your target." },
		{ type = "toggle", key = "whisper", name = "Whispers", new = NEW,
		  desc = "A new whisper: the sender in their class colour, the last line and how many are unread. Reply opens their whisper window. Needs Chat's Whisper Popup Window." },
		{ type = "toggle", key = "pet", name = "Hunter Pet", new = NEW,
		  desc = "Your pet is not happy: its face, a ring for its happiness, and Feed Pet on hover (out of combat)." },
		{ type = "toggle", key = "auction", name = "Auction House", new = NEW,
		  desc = "Outbid, sold, won and expired at the auction house, in one list. Click it for the way to the nearest mailbox." },
		{ type = "toggle", key = "craft", name = "Crafting", new = NEW,
		  desc = "A batch you craft: which one of how many, a ring for each item, and Stop on hover." },
		{ type = "toggle", key = "cooldown", name = "Profession Cooldowns", new = NEW,
		  desc = "A profession cooldown ready again (a transmute, mooncloth, the salt shaker). MelloUI learns it when you open that profession." },
		{ type = "header", name = "By The Portrait" },
		{ type = "toggle", key = "bags", name = "Bags Almost Full", new = NEW,
		  desc = "Remind you when your bags are almost full; it stays, in a fight too, until you make room. Click it for the way to the nearest vendor." },
		{ type = "slider", key = "bagsAt", parent = "bags", name = "Free Slots", min = 0, max = 10, step = 1, new = NEW,
		  desc = "Remind you once this many free bag slots or fewer are left." },
		{ type = "toggle", key = "talents", name = "Talent Points", new = NEW,
		  desc = "Remind you when you have talent points to spend." },
		{ type = "toggle", key = "wellfed", name = "Well Fed Ending", new = NEW,
		  desc = "Remind you when Well Fed has two minutes left." },
	},
})

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- f(...)'s first four results, or nil when f is not a function or raised
local function Ask(f, ...)
	if type(f) ~= "function" then
		return nil
	end
	local ok, a, b, c, d = pcall(f, ...)
	if not ok then
		return nil
	end
	return a, b, c, d
end

local function On(key)
	return M.isEnabled and M.db ~= nil and M.db[key] == true
end

local function Rem()
	local r = MelloUI.Reminders
	return type(r) == "table" and type(r.Register) == "function" and r or nil
end

local state = { registered = false, frame = nil }

-- a use's row or reminder looked at again on the next frame; raise: a new
-- moment of it (a Not now until then is over)
local function Refresh(key, raise)
	local r = Rem()
	if r and state.registered then
		r:Refresh(key, raise)
	end
end

local function Clock(secs)
	local r = Rem()
	return r and r.Clock and r.Clock(secs) or tostring(floor(secs + 0.5))
end

local function Services()
	local s = MelloUI:GetModule("Services")
	return (type(s) == "table" and type(s.GoTo) == "function") and s or nil
end

local function Route()
	local r = MelloUI.Route
	return type(r) == "table" and r or nil
end

-- "ffRRGGBB" (a class colour's hex) -> r, g, b
local function HexColour(hex)
	if type(hex) ~= "string" or Secret(hex) then
		return nil
	end
	local r, g, b = hex:match("^%x%x(%x%x)(%x%x)(%x%x)$")
	if not r then
		return nil
	end
	return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function Spell(id, fallback)
	local name
	if C_Spell and C_Spell.GetSpellName then
		name = Text(Ask(C_Spell.GetSpellName, id))
	end
	if not name and _G.GetSpellInfo then
		name = Text((Ask(_G.GetSpellInfo, id)))
	end
	return name or fallback
end

local function SpellIcon(id)
	if C_Spell and C_Spell.GetSpellTexture then
		local t = Ask(C_Spell.GetSpellTexture, id)
		if not Secret(t) and t then
			return t
		end
	end
	return nil
end

local TEXT = {
	loot = "Loot Rolls", lootLine = "Roll before the ring runs out", need = "Need", needDesc = "Roll for it as Need.",
	greed = "Greed", greedDesc = "Roll for it as Greed.", pass = "Pass", passDesc = "Pass on it.",
	corpse = "Your corpse", corpseLabel = "Corpse Run", corpseFar = "%s, to the %s", corpseNear = "Your body is near",
	corpseLine = "Go back to your body", way = "Show the way", wayCorpse = "The arrow points at your corpse.",
	corpseRes = "Resurrect", corpseResDesc = "Come back to life here.", corpseReady = "Resurrect now",
	corpseUnknown = "Your body's place is not known here yet.", corpseNoWay = "No way to your body from here.",
	ready_ = "Ready", timedLabel = "Timed Quests", timedLine = "Timed quest",
	summonLabel = "Summons", summons = "%s summons you", summonLine = "to %s", someone = "Someone",
	accept = "Accept", decline = "Decline", summonAccept = "Go to %s.", summonDecline = "Stay where you are.",
	resLabel = "Resurrect Offers", resurrects = "%s resurrects you", resLine = "Accept to come back here",
	resAccept = "Come back where you died.", resDecline = "Stay dead for now.",
	readyLabel = "Ready Checks", readyTitle = "Ready check", readyLine = "from %s", readyHint = "Click: Ready. Point at it for Not Ready.",
	readyYes = "Ready", readyYesDesc = "Tell the group you are ready.", readyNo = "Not Ready",
	readyNoDesc = "Tell the group you are not ready yet.",
	threatLabel = "Threat", threatHint = "Point at it: the group's threat on your target", threatOf = "%d%% of %s's threat",
	threatPct = "%d%% of the pull", threatClose = "Close to pulling", threatOnYou = "It is attacking you",
	threatEase = "Ease off", threatAggro = "Aggro", threatLoose = "%d mobs not on you", threatLooseOne = "1 mob not on you",
	threatOn = "%s \226\134\146 %s", threatList = "Threat", threatListDesc = "The group's threat on your target.",
	threatTank = "%s (tank)", threatYou = "You", threatFoot = "On %s", threatNone = "Nobody on its list yet",
	whisperLabel = "Whispers", whisperNew = "New whisper", reply = "Reply", replyDesc = "Opens their whisper window.",
	petLabel = "Hunter Pet", petTitle = "%s, your pet", petContent = "Content: feed it soon", petUnhappy = "Unhappy: feed it now",
	feed = "Feed Pet", feedDesc = "Then click a food in your bags that your pet eats.",
	auctionLabel = "Auction House", outbid = "Outbid: %s", sold = "Sold: %s", won = "Won: %s", expired = "Expired: %s",
	anItem = "an item", auctionFoot = "Click one: the way to a mailbox",
	auctionHint = "Click: the way to the nearest mailbox",
	craftLabel = "Crafting", crafting = "Crafting %d of %d", stop = "Stop", stopDesc = "Stops after this one.",
	cdLabel = "Profession Cooldowns", cdReady = "%s ready", cdLine = "%s: the cooldown is over", cdLineItem = "The cooldown is over",
	bagsLabel = "Bags Almost Full", bags = "Bags: %d free slots", bagsOne = "Bags: 1 free slot", bagsFull = "Bags: full",
	bagsHint = "Click: the way to the nearest vendor",
	talentsLabel = "Talent Points", talents = "Talent points: %d to spend", talentsHint = "Open your talents to spend them.",
	wellfedLabel = "Well Fed", wellfed = "Well Fed ends in %s", wellfedHint = "Eat something to keep it.",
	DIRS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" },
}
M.TEXT = TEXT

--------------------------------------------------------------------------------
-- Loot rolls
--------------------------------------------------------------------------------

local loot = { rolls = {}, n = 0 }   -- rolls[1..n] = { id, startAt, total }, the soonest to end first

local function LootFind(id)
	for i = 1, loot.n do
		if loot.rolls[i].id == id then
			return i
		end
	end
	return nil
end

local function LootDrop(id)
	local i = LootFind(id)
	if not i then
		return
	end
	table.remove(loot.rolls, i)
	loot.n = loot.n - 1
end

local function SoonerRoll(a, b)
	return a.startAt + a.total < b.startAt + b.total
end

-- a roll added (its whole time from the event, what is left asked)
local function LootAdd(id, rollTime)
	id = Num(id)
	if not id or LootFind(id) then
		return
	end
	local total = Num(rollTime)
	total = total and total / 1000 or nil
	local left = Num((Ask(_G.GetLootRollTimeLeft, id)))
	left = left and left / 1000 or total
	if not total and C_Loot and C_Loot.GetLootRollDuration then
		total = Num((Ask(C_Loot.GetLootRollDuration, id)))
		total = total and total / 1000 or nil
	end
	total = total or left or 60
	left = left or total
	loot.n = loot.n + 1
	loot.rolls[loot.n] = { id = id, startAt = GetTime() - (total - left), total = total }
	table.sort(loot.rolls, SoonerRoll)
end

-- the rolls the game has now (a login or a reload in a group)
local function LootRead()
	loot.n = 0
	wipe(loot.rolls)
	local ids = Ask(_G.GetActiveLootRollIDs)
	if type(ids) ~= "table" then
		return
	end
	for i = 1, #ids do
		LootAdd(ids[i], nil)
	end
end

local function LootInfo()
	local r = loot.rolls[1]
	if not r then
		return nil
	end
	-- (all seven results: Ask keeps four)
	local fn = _G.GetLootRollItemInfo
	if type(fn) ~= "function" then
		return r
	end
	local ok, texture, name, count, quality, _, canNeed, canGreed = pcall(fn, r.id)
	if not ok then
		return r
	end
	return r, texture, name, count, quality, canNeed, canGreed
end

local function Roll(kind)
	local r = loot.rolls[1]
	if not r then
		return
	end
	local ok = pcall(_G.RollOnLoot, r.id, kind)
	if ok then
		LootDrop(r.id)
		Refresh("loot")
	end
end

local LOOT = {
	key = "loot", column = true, label = TEXT.loot, priority = "now",
	check = function()
		return loot.n > 0
	end,
	title = function()
		local _, _, name, count, quality = LootInfo()
		name = Text(name)
		if not name then
			return TEXT.loot
		end
		if Num(count) and count > 1 then
			name = name .. " x" .. count
		end
		quality = Num(quality)
		local fn = C_Item and C_Item.GetItemQualityColor or _G.GetItemQualityColor
		if quality and fn then
			local r, g, b = Ask(fn, quality)
			if Num(r) and Num(g) and Num(b) then
				return name, r, g, b
			end
		end
		return name
	end,
	text = TEXT.lootLine,
	icon = function()
		local _, texture = LootInfo()
		return (not Secret(texture) and texture) or "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
	end,
	count = function()
		return loot.n > 1 and loot.n or nil
	end,
	progress = function()
		local r = loot.rolls[1]
		if r then
			return r.startAt, r.total
		end
	end,
	tooltip = function(_, tip)
		local r = loot.rolls[1]
		if r and tip.SetLootRollItem then
			pcall(tip.SetLootRollItem, tip, r.id)
		end
	end,
	actions = {
		{ icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", tip = TEXT.need, desc = TEXT.needDesc,
		  shown = function() local _, _, _, _, _, canNeed = LootInfo() return canNeed == true end,
		  fn = function() Roll(1) end },
		{ icon = "Interface\\Buttons\\UI-GroupLoot-Coin-Up", tip = TEXT.greed, desc = TEXT.greedDesc,
		  shown = function() local _, _, _, _, _, _, canGreed = LootInfo() return canGreed ~= false end,
		  fn = function() Roll(2) end },
		{ icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", tip = TEXT.pass, desc = TEXT.passDesc,
		  fn = function() Roll(0) end },
	},
}

--------------------------------------------------------------------------------
-- Corpse run
--------------------------------------------------------------------------------

local corpse = { ghost = false, until_ = nil, total = nil, mapID = nil, x = nil, y = nil, near = false }

local function IsGhost()
	local g = Ask(_G.UnitIsGhost, "player")
	if Secret(g) then
		return corpse.ghost
	end
	return g == true
end

-- where the body lies: on the player's map, else on the first map above it
-- that holds it (a body in another part of the zone, or across the zone's
-- edge: the zone's or the continent's map); nil when not known here. Read
-- again while it is missing (user, 2026-09-30: the release reads it as the
-- player is moved to the graveyard, when the game may have no place yet,
-- and "clicking on the waypoint doesn't do anything")
local CORPSE_MAPS_UP = 4

local function CorpseOn(mapID)
	local pos = Ask(C_DeathInfo.GetCorpseMapPosition, mapID)
	if type(pos) ~= "table" or Secret(pos) then
		return nil
	end
	local x, y = Ask(pos.GetXY, pos)
	x, y = Num(x), Num(y)
	if x and y and (x > 0 or y > 0) then
		return x, y
	end
	return nil
end

local function CorpseRead()
	corpse.mapID, corpse.x, corpse.y = nil, nil, nil
	local mapID = C_Map and Num((Ask(C_Map.GetBestMapForUnit, "player")))
	if not (mapID and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then
		return
	end
	for _ = 1, CORPSE_MAPS_UP do
		local x, y = CorpseOn(mapID)
		if x then
			corpse.mapID, corpse.x, corpse.y = mapID, x, y
			return
		end
		local info = C_Map.GetMapInfo and Ask(C_Map.GetMapInfo, mapID)
		local parent = type(info) == "table" and Num(info.parentMapID) or nil
		if not parent or parent == 0 then
			return
		end
		mapID = parent
	end
end

local function CorpseDelay()
	local d = Num((Ask(_G.GetCorpseRecoveryDelay)))
	if d and d > 0 then
		corpse.until_, corpse.total = GetTime() + d, d
	else
		corpse.until_, corpse.total = nil, nil
	end
end

local CANDIDATE = {}   -- (Route's candidate for the body, one table)

local function CorpseCandidate()
	if not corpse.mapID and corpse.ghost then
		CorpseRead()
	end
	if not corpse.mapID then
		return nil
	end
	CANDIDATE.mapID, CANDIDATE.x, CANDIDATE.y = corpse.mapID, corpse.x, corpse.y
	return CANDIDATE
end

-- the way to the body (a click, the way button): its place read again
-- first (the player may be on another map now); a place not known, or one
-- Route cannot lay a way to, said on the centre line instead of nothing
local function CorpseWay()
	if corpse.ghost then
		CorpseRead()
	end
	local R, c = Route(), CorpseCandidate()
	if not c then
		MelloUI:Announce(TEXT.corpseUnknown, "fail")
		return
	end
	if not (R and type(R.SetDestinationTo) == "function") then
		MelloUI:Announce(TEXT.corpseNoWay, "fail")
		return
	end
	local ok, placed = pcall(R.SetDestinationTo, R, c, TEXT.corpse, true)
	if not ok then
		geterrorhandler()(placed)
	elseif placed == false then
		MelloUI:Announce(TEXT.corpseNoWay, "fail")
	end
end

-- which way the body is from the player (map north up; map y grows south)
local function Bearing()
	local c = corpse
	if not (c.mapID and C_Map and C_Map.GetPlayerMapPosition) then
		return nil
	end
	local pos = Ask(C_Map.GetPlayerMapPosition, c.mapID, "player")
	if type(pos) ~= "table" or Secret(pos) then
		return nil
	end
	local px, py = Ask(pos.GetXY, pos)
	px, py = Num(px), Num(py)
	if not (px and py) then
		return nil
	end
	local dx, dy = c.x - px, py - c.y
	if dx == 0 and dy == 0 then
		return nil
	end
	local angle = math.deg(math.atan2(dx, dy)) % 360   -- 0 = north, clockwise
	return TEXT.DIRS[floor((angle + 22.5) / 45) % 8 + 1]
end

-- the game's own Resurrect at the body (RetrieveCorpse: no restriction)
local function CorpseRes()
	local fn = _G.RetrieveCorpse
	if type(fn) == "function" then
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local CORPSE = {
	key = "corpse", column = true, label = TEXT.corpseLabel,
	check = function()
		return corpse.ghost
	end,
	title = TEXT.corpse,
	text = function()
		if corpse.near then
			return TEXT.corpseReady
		end
		local R, c = Route(), CorpseCandidate()
		if R and c and type(R.DistanceTo) == "function" then
			local ok, d = pcall(R.DistanceTo, R, c, true)
			d = ok and Num(d) or nil
			if d then
				if d < 25 then
					return TEXT.corpseNear
				end
				local yards = type(R.YardsText) == "function" and R:YardsText(d) or (floor(d) .. " yd")
				local dir = Bearing()
				return dir and TEXT.corpseFar:format(yards, dir) or yards
			end
		end
		return TEXT.corpseLine
	end,
	icon = "Interface\\Icons\\Ability_Vanish",
	progress = function()
		if corpse.until_ and corpse.until_ > GetTime() then
			return corpse.until_ - corpse.total, corpse.total
		end
	end,
	time = function(_, left)
		if left and left > 0 then
			return Clock(left)
		end
		return nil
	end,
	-- (at the body, CORPSE_IN_RANGE: Resurrect on it, as the game's popup has
	-- it; that popup is made invisible while this widget shows, user
	-- 2026-09-30; the ring is the recovery delay, a click before it ends
	-- gets the game's own "not yet")
	onClick = function()
		if corpse.near then
			CorpseRes()
		else
			CorpseWay()
		end
	end,
	hint = TEXT.way,
	actions = {
		{ glyph = "check", tip = TEXT.corpseRes, desc = TEXT.corpseResDesc, fn = function() CorpseRes() end,
		  shown = function() return corpse.near end },
		{ glyph = "way", tip = TEXT.way, desc = TEXT.wayCorpse, fn = function() CorpseWay() end,
		  shown = function() return not corpse.near end },
	},
}

-- Route's 'where' (every few seconds while the player travels): the
-- distance again, only while a ghost
local function CorpseWhere()
	if corpse.ghost then
		Refresh("corpse")
	end
end

local function CorpseState()
	local was = corpse.ghost
	corpse.ghost = On("corpse") and IsGhost() or false
	if corpse.ghost then
		CorpseRead()
		if not was then
			CorpseDelay()
		end
	else
		corpse.until_, corpse.total, corpse.near = nil, nil, false
	end
	local R = Route()
	if R and type(R.WantWhere) == "function" and was ~= corpse.ghost then
		pcall(R.WantWhere, R, "Widgets", corpse.ghost)
	end
	Refresh("corpse", corpse.ghost and not was)
end

--------------------------------------------------------------------------------
-- Timed quests
--------------------------------------------------------------------------------

local timed = { n = 0, id = nil, startAt = nil, total = nil }

local function TimedRead()
	timed.n, timed.id, timed.startAt, timed.total = 0, nil, nil, nil
	local list = C_QuestLog and Ask(C_QuestLog.GetQuestTimers)
	if type(list) ~= "table" then
		return
	end
	local best
	for i = 1, #list do
		local info = list[i]
		local id = type(info) == "table" and Num(info.questID)
		local left = type(info) == "table" and Num(info.questTimer)
		if id and left and left > 0 then
			timed.n = timed.n + 1
			if not best or left < best then
				best, timed.id = left, id
			end
		end
	end
	if not timed.id then
		return
	end
	local total, elapsed = Ask(C_QuestLog.GetTimeAllowed, timed.id)
	total, elapsed = Num(total), Num(elapsed)
	local now = GetTime()
	if total and elapsed and total > 0 then
		timed.startAt, timed.total = now - elapsed, total
	else
		timed.startAt, timed.total = now, best
	end
end

local TIMED = {
	key = "timed", column = true, label = TEXT.timedLabel,
	check = function(_, why)
		TimedRead()
		return timed.id ~= nil
	end,
	title = function()
		local title = timed.id and C_QuestLog and Text((Ask(C_QuestLog.GetTitleForQuestID, timed.id)))
		return title or TEXT.timedLabel
	end,
	text = function()
		local objectives = timed.id and C_QuestLog and Ask(C_QuestLog.GetQuestObjectives, timed.id)
		local first = type(objectives) == "table" and objectives[1]
		local line = type(first) == "table" and Text(first.text)
		return line or TEXT.timedLine
	end,
	icon = "Interface\\Icons\\INV_Misc_PocketWatch_02",
	count = function()
		return timed.n > 1 and timed.n or nil
	end,
	progress = function()
		if timed.startAt then
			return timed.startAt, timed.total
		end
	end,
	time = function(_, left)
		return left and Clock(left) or nil
	end,
}

--------------------------------------------------------------------------------
-- Summons, resurrect offers, ready checks
--------------------------------------------------------------------------------

local summon = { at = nil, total = nil, who = nil, where = nil }
local res = { at = nil, total = nil, who = nil }
local ready = { at = nil, total = nil, who = nil }

local function SummonRead()
	local S = C_SummonInfo
	summon.at, summon.total, summon.who, summon.where = nil, nil, nil, nil
	if not S then
		return
	end
	local left = Num((Ask(S.GetSummonConfirmTimeLeft)))
	if not (left and left > 0) then
		return
	end
	summon.at, summon.total = GetTime(), left
	summon.who = Text((Ask(S.GetSummonConfirmSummoner)))
	summon.where = Text((Ask(S.GetSummonConfirmAreaName)))
end

local function Live(t)
	return t.at ~= nil and (not t.total or GetTime() < t.at + t.total)
end

local SUMMON = {
	key = "summon", column = true, label = TEXT.summonLabel, priority = "now",
	check = function()
		return Live(summon)
	end,
	title = function()
		return TEXT.summons:format(summon.who or TEXT.someone)
	end,
	text = function()
		return summon.where and TEXT.summonLine:format(summon.where) or ""
	end,
	icon = "Interface\\Icons\\Spell_Shadow_Twilight",
	progress = function()
		if summon.at and summon.total then
			return summon.at, summon.total
		end
	end,
	actions = {
		{ glyph = "check", tip = TEXT.accept, desc = function() return TEXT.summonAccept:format(summon.where or "") end,
		  fn = function()
			if C_SummonInfo and pcall(C_SummonInfo.ConfirmSummon) then
				summon.at = nil
				Refresh("summon")
			end
		  end },
		{ glyph = "cross", tip = TEXT.decline, desc = TEXT.summonDecline,
		  fn = function()
			if C_SummonInfo and pcall(C_SummonInfo.CancelSummon) then
				summon.at = nil
				Refresh("summon")
			end
		  end },
	},
}

local RESURRECT = {
	key = "resurrect", column = true, label = TEXT.resLabel, priority = "now",
	check = function()
		return Live(res)
	end,
	title = function()
		return TEXT.resurrects:format(res.who or TEXT.someone)
	end,
	text = TEXT.resLine,
	icon = "Interface\\Icons\\Spell_Holy_Resurrection",
	progress = function()
		if res.at and res.total then
			return res.at, res.total
		end
	end,
	actions = {
		{ glyph = "check", tip = TEXT.accept, desc = TEXT.resAccept,
		  fn = function()
			if pcall(_G.AcceptResurrect) then
				res.at = nil
				Refresh("resurrect")
			end
		  end },
		{ glyph = "cross", tip = TEXT.decline, desc = TEXT.resDecline,
		  fn = function()
			if pcall(_G.DeclineResurrect) then
				res.at = nil
				Refresh("resurrect")
			end
		  end },
	},
}

-- the player's answer, as the game's own box gives it
local function ReadyAnswer(yes)
	local P = C_PartyInfo
	local fn = type(P) == "table" and P.ConfirmReadyCheck or nil
	if type(fn) == "function" then
		local ok, err = pcall(fn, yes and true or false)
		if not ok then
			geterrorhandler()(err)
		end
	end
	ready.at = nil
	Refresh("ready")
end

local READY = {
	key = "ready", column = true, label = TEXT.readyLabel, hint = TEXT.readyHint, priority = "now",
	check = function()
		return Live(ready)
	end,
	title = TEXT.readyTitle,
	text = function()
		return ready.who and TEXT.readyLine:format(ready.who) or ""
	end,
	icon = "Interface\\RaidFrame\\ReadyCheck-Waiting",
	progress = function()
		if ready.at and ready.total then
			return ready.at, ready.total
		end
	end,
	-- (user, 2026-09-30: the widget answers, the game's box stays away;
	-- C_PartyInfo.ConfirmReadyCheck wants a click behind it: these are)
	onClick = function()
		ReadyAnswer(true)
	end,
	actions = {
		{ glyph = "check", tip = TEXT.readyYes, desc = TEXT.readyYesDesc, fn = function() ReadyAnswer(true) end },
		{ glyph = "cross", tip = TEXT.readyNo, desc = TEXT.readyNoDesc, fn = function() ReadyAnswer(false) end },
	},
}

--------------------------------------------------------------------------------
-- Threat (0.16.0; user, 2026-09-30: threat_sketch, the widget "as sketched",
-- pulled into 0.16.0): in a group fight only when it matters -- a damage
-- dealer or healer close to pulling their target ("Ease off") or with it on
-- them ("Aggro"), a tank with mobs not on them. The one reader is
-- MelloUI.Threat (Core/Threat.lua; the nameplates' threat line reads it
-- too). Once up for being close it stays until the threat falls under
-- STAY_UNDER of the pull (no flicker at the edge). Where the numbers are
-- secret (a boss) the warning only: no ring, no percentages. A "now" widget:
-- it never folds, in a fight least of all. Its tray: the group's threat on
-- the player's target, highest first.
--------------------------------------------------------------------------------

local Threat = MelloUI.Threat
local STAY_UNDER = 0.7
local PLATE_UNITS, PLATE_TARGETS = {}, {}
for i = 1, 40 do
	PLATE_UNITS[i], PLATE_TARGETS[i] = "nameplate" .. i, "nameplate" .. i .. "target"
end
local PARTY_UNITS, RAID_UNITS = { "player", "party1", "party2", "party3", "party4" }, {}
for i = 1, 40 do
	RAID_UNITS[i] = "raid" .. i
end
local threat = { state = nil, fraction = nil, tank = false, name = nil, holder = nil, loose = 0, looseName = nil,
	looseOn = nil, up = false, list = {} }

local function Yes(v)
	return not Secret(v) and v == true
end

-- the fight as it stands, into `threat` (nothing made)
local function ThreatRead()
	local wasUp = threat.up
	threat.state, threat.fraction, threat.loose, threat.looseName, threat.looseOn, threat.up = nil, nil, 0, nil, nil, false
	if not (On("threat") and Threat.Grouped() and Yes(Ask(UnitAffectingCombat, "player"))) then
		return
	end
	local tank = Threat.IsTank()
	threat.tank = tank
	if tank then
		-- the mobs in the fight not on the tank, on the plates in sight
		for i = 1, #PLATE_UNITS do
			local unit = PLATE_UNITS[i]
			if Yes(Ask(UnitExists, unit)) and Yes(Ask(UnitCanAttack, "player", unit)) and Yes(Ask(UnitAffectingCombat, unit)) then
				local status, fraction = Threat.Read("player", unit)
				if type(status) == "number" and status < 2 then
					threat.loose = threat.loose + 1
					if not threat.looseName then
						threat.looseName = Text((Ask(UnitName, unit)))
						threat.looseOn = Text((Ask(UnitName, PLATE_TARGETS[i])))
						threat.fraction = fraction
					end
				end
			end
		end
		if threat.loose > 0 then
			threat.state, threat.up = "aggro", true
		end
		return
	end
	if not Yes(Ask(UnitCanAttack, "player", "target")) then
		return
	end
	local status, fraction, tanking = Threat.Read("player", "target")
	local now = Threat.State(status, fraction, false)
	if now == "safe" and wasUp and fraction and fraction >= STAY_UNDER then
		now = "close"
	end
	if now == "close" or now == "aggro" then
		threat.state, threat.fraction, threat.up = now, fraction, true
		threat.name = Text((Ask(UnitName, "target")))
		threat.holder = not tanking and Text((Ask(UnitName, "targettarget"))) or nil
	end
end

local function Percent(fraction)
	return floor(fraction * 100 + 0.5)
end

local function Coloured(kind, text)
	local c = kind == "aggro" and MelloUI.Meaning.threatAggro or MelloUI.Meaning.threatClose
	return "|cff" .. c.hex .. text .. "|r"
end

-- the tray: the group's threat on the player's target, highest first
local function ThreatTray(_, rows)
	local list, n = threat.list, 0
	local grouped = Yes(Ask(_G.IsInRaid))
	local units = grouped and RAID_UNITS or PARTY_UNITS
	for i = 1, #units do
		local unit = units[i]
		if Yes(Ask(UnitExists, unit)) then
			local status, fraction, tanking = Threat.Read(unit, "target")
			if type(status) == "number" and fraction then
				n = n + 1
				local e = list[n] or {}
				list[n] = e
				e.fraction, e.tanking = fraction, tanking
				e.name = Yes(Ask(UnitIsUnit, unit, "player")) and TEXT.threatYou or (Text((Ask(UnitName, unit))) or TEXT.someone)
			end
		end
	end
	for i = n + 1, #list do
		list[i] = nil
	end
	table.sort(list, function(a, b) return a.fraction > b.fraction end)
	for i = 1, n do
		local e = list[i]
		local r = rows[i] or {}
		rows[i] = r
		r.glyph, r.icon, r.onClick = nil, nil, nil
		r.text = e.tanking and TEXT.threatTank:format(e.name) or e.name
		r.right = Percent(e.fraction) .. "%"
	end
	rows.n = n
	if n == 0 then
		return TEXT.threatNone
	end
	return TEXT.threatFoot:format(threat.name or (Text((Ask(UnitName, "target"))) or TEXT.someone))
end

local THREAT = {
	key = "threat", column = true, label = TEXT.threatLabel, hint = TEXT.threatHint, priority = "now",
	check = function()
		ThreatRead()
		return threat.state ~= nil
	end,
	title = function()
		if threat.tank then
			return threat.loose == 1 and TEXT.threatLooseOne or TEXT.threatLoose:format(threat.loose)
		end
		return threat.name or TEXT.threatLabel
	end,
	text = function()
		if threat.tank then
			if threat.looseName and threat.looseOn then
				return TEXT.threatOn:format(threat.looseName, threat.looseOn)
			end
			return threat.looseName or ""
		end
		if threat.state == "aggro" then
			return TEXT.threatOnYou
		elseif threat.fraction and threat.holder then
			return TEXT.threatOf:format(Percent(threat.fraction), threat.holder)
		elseif threat.fraction then
			return TEXT.threatPct:format(Percent(threat.fraction))
		end
		return TEXT.threatClose
	end,
	portrait = function()
		return not threat.tank and "target" or nil
	end,
	icon = "Interface\\Icons\\Ability_Warrior_Challange",
	fraction = function()
		return threat.fraction and math.min(threat.fraction, 1) or nil
	end,
	time = function()
		if threat.tank then
			return threat.fraction and Coloured("aggro", Percent(threat.fraction) .. "%") or ""
		end
		return Coloured(threat.state, threat.state == "aggro" and TEXT.threatAggro or TEXT.threatEase)
	end,
	count = function()
		return threat.tank and threat.loose > 1 and threat.loose or nil
	end,
	onClick = function()
		Rem():Tray("threat")
	end,
	tray = ThreatTray,
	actions = {
		{ glyph = "list", tip = TEXT.threatList, desc = TEXT.threatListDesc, tray = true },
	},
}

--------------------------------------------------------------------------------
-- Whispers (the Chat module's popups tell it: bus 'whisper')
--------------------------------------------------------------------------------

local whisper = { key = nil, title = nil, hex = nil, last = nil, unread = 0, byKey = {} }

local function OnWhisper(key, title, classHex, text, incoming, open)
	if not On("whisper") or type(key) ~= "string" then
		return
	end
	local c = whisper.byKey[key]
	if not c then
		c = { unread = 0 }
		whisper.byKey[key] = c
	end
	-- (a line to a window that is open: read there, no widget for it)
	if incoming and not open then
		c.unread = c.unread + 1
		c.title = Text(title) or c.title
		c.hex = (type(classHex) == "string" and not Secret(classHex)) and classHex or c.hex
		c.last = Text(text)
		whisper.key = key
	else
		c.unread = 0   -- (answered)
	end
	local total = 0
	for _, conv in pairs(whisper.byKey) do
		total = total + conv.unread
	end
	whisper.unread = total
	Refresh("whisper", incoming and not open)
end

local function Reply()
	local key = whisper.key
	local chat = MelloUI:GetModule("Chat")
	if key and chat and type(chat.OpenWhisper) == "function" then
		pcall(chat.OpenWhisper, chat, key)
	end
	for _, conv in pairs(whisper.byKey) do
		conv.unread = 0
	end
	whisper.unread = 0
	Refresh("whisper")
end

local WHISPER = {
	key = "whisper", column = true, label = TEXT.whisperLabel, onClick = function() Reply() end, hint = TEXT.replyDesc,
	priority = "wait", combat = false,
	check = function()
		return whisper.unread > 0 and whisper.key ~= nil
	end,
	title = function()
		local c = whisper.key and whisper.byKey[whisper.key]
		if not c then
			return TEXT.whisperLabel
		end
		local r, g, b = HexColour(c.hex)
		return c.title or TEXT.someone, r, g, b
	end,
	text = function()
		local c = whisper.key and whisper.byKey[whisper.key]
		return (c and c.last) and ('"' .. c.last .. '"') or TEXT.whisperNew
	end,
	icon = "Interface\\Icons\\INV_Letter_18",
	count = function()
		return whisper.unread > 1 and whisper.unread or nil
	end,
	actions = {
		{ glyph = "reply", tip = TEXT.reply, desc = TEXT.replyDesc, fn = function() Reply() end },
	},
}

--------------------------------------------------------------------------------
-- Hunter pet
--------------------------------------------------------------------------------

local FEED_PET = 6991
local pet = { happiness = nil, name = nil, hunter = nil }

local function PetRead()
	pet.happiness, pet.name = nil, nil
	if pet.hunter == nil then
		local _, token = Ask(UnitClass, "player")
		pet.hunter = Text(token) == "HUNTER"
	end
	if not pet.hunter then
		return
	end
	local exists = Ask(UnitExists, "pet")
	if Secret(exists) or not exists then
		return
	end
	pet.happiness = Num((Ask(_G.GetPetHappiness)))
	pet.name = Text((Ask(UnitName, "pet")))
end

local PET = {
	key = "pet", column = true, label = TEXT.petLabel, combat = false,
	check = function()
		PetRead()
		return pet.happiness ~= nil and pet.happiness < 3
	end,
	title = function()
		return TEXT.petTitle:format(pet.name or TEXT.petLabel)
	end,
	text = function()
		return pet.happiness == 1 and TEXT.petUnhappy or TEXT.petContent
	end,
	portrait = "pet",
	icon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
	fraction = function()
		return pet.happiness and pet.happiness / 3 or nil
	end,
	actions = {
		{ icon = function() return SpellIcon(FEED_PET) or "Interface\\Icons\\Ability_Hunter_BeastTraining" end,
		  tip = function() return Spell(FEED_PET, TEXT.feed) end, desc = TEXT.feedDesc,
		  secure = function() return "/cast " .. Spell(FEED_PET, TEXT.feed) end },
	},
}

--------------------------------------------------------------------------------
-- Auction house (the system messages, matched against the game's own
-- strings: built once, the first time one is needed)
--------------------------------------------------------------------------------

local auction = { list = {}, patterns = nil }
local AUCTION_MAX = 12

local function Pattern(s)
	if type(s) ~= "string" or Secret(s) then
		return nil
	end
	s = s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	return "^" .. s:gsub("%%%%s", "(.+)") .. "$"
end

local function AuctionPatterns()
	local p = auction.patterns
	if not p then
		p = {
			{ kind = "outbid", pat = Pattern(_G.ERR_AUCTION_OUTBID_S) },
			{ kind = "sold", pat = Pattern(_G.ERR_AUCTION_SOLD_S) },
			{ kind = "won", pat = Pattern(_G.ERR_AUCTION_WON_S) },
		}
		auction.patterns = p
	end
	return p
end

-- one on the list (the same one heard twice in a moment: once)
local function AuctionAdd(kind, item)
	local list, now = auction.list, GetTime()
	local top = list[1]
	if top and top.kind == kind and top.item == item and now - top.at < 2 then
		return
	end
	table.insert(list, 1, { kind = kind, item = item, at = now })
	if #list > AUCTION_MAX then
		table.remove(list)
	end
	Refresh("auction", true)
end

local function OnSystem(text)
	if type(text) ~= "string" or Secret(text) then
		return
	end
	for _, p in ipairs(AuctionPatterns()) do
		local item = p.pat and text:match(p.pat)
		if item then
			AuctionAdd(p.kind, item)
			return
		end
	end
end

-- The auction house's own notices (user, 2026-09-30: a sale showed no
-- widget): this client sends them as AUCTION_HOUSE_SHOW_NOTIFICATION and
-- ..._FORMATTED_NOTIFICATION, whose chat line the game writes itself, with
-- no CHAT_MSG_SYSTEM. Enum.AuctionHouseNotification: 2 won, 3 outbid, 4
-- sold, 5 expired; the item its format argument.
local AUCTION_NOTICE = { [2] = "won", [3] = "outbid", [4] = "sold", [5] = "expired" }

local function OnAuctionNotice(notice, item)
	local kind = AUCTION_NOTICE[Num(notice) or -1]
	if kind then
		AuctionAdd(kind, Text(item) or TEXT.anItem)
	end
end

local function Mailbox()
	local s = Services()
	if s then
		pcall(s.GoTo, s, "mailbox")
	end
end

local AUCTION_WORD = { outbid = TEXT.outbid, sold = TEXT.sold, won = TEXT.won, expired = TEXT.expired }

local AUCTION = {
	key = "auction", column = true, label = TEXT.auctionLabel, hint = TEXT.auctionHint, priority = "wait", combat = false,
	check = function()
		return #auction.list > 0
	end,
	title = TEXT.auctionLabel,
	text = function()
		local e = auction.list[1]
		return e and AUCTION_WORD[e.kind]:format(e.item) or ""
	end,
	icon = "Interface\\Icons\\INV_Misc_Coin_02",
	count = function()
		return #auction.list > 1 and #auction.list or nil
	end,
	onClick = function()
		Rem():Tray("auction")
	end,
	tray = function(_, rows)
		for i, e in ipairs(auction.list) do
			local r = rows[i] or {}
			rows[i] = r
			r.glyph, r.icon, r.right = nil, nil, ""
			r.text = AUCTION_WORD[e.kind]:format(e.item)
			r.onClick = Mailbox
		end
		rows.n = #auction.list
		return TEXT.auctionFoot
	end,
	actions = {
		{ glyph = "list", tip = TEXT.auctionLabel, tray = true },
		{ glyph = "way", tip = TEXT.way, desc = TEXT.auctionHint, fn = Mailbox },
	},
}

--------------------------------------------------------------------------------
-- Crafting (a batch: C_TradeSkillUI.CraftRecipe post-hooked, the casts
-- counted by their events)
--------------------------------------------------------------------------------

local craft = { recipe = nil, total = 0, done = 0, name = nil, icon = nil, castAt = nil, castFor = nil }

local function CraftEnd()
	if craft.recipe then
		craft.recipe = nil
		Refresh("craft")
	end
end

local function OnCraftRecipe(recipeID, numCasts)
	if not On("craft") then
		return
	end
	recipeID, numCasts = Num(recipeID), Num(numCasts) or 1
	if not recipeID or numCasts < 2 then
		CraftEnd()
		return
	end
	craft.recipe, craft.total, craft.done, craft.castAt, craft.castFor = recipeID, numCasts, 0, nil, nil
	local info = C_TradeSkillUI and Ask(C_TradeSkillUI.GetRecipeInfo, recipeID)
	craft.name = type(info) == "table" and Text(info.name) or nil
	craft.icon = type(info) == "table" and not Secret(info.icon) and info.icon or nil
	Refresh("craft", true)
end

-- a cast of the batch's recipe (a secret spell id: counted as ours while a batch runs)
local function OurCast(spellID)
	return craft.recipe ~= nil and (Secret(spellID) or Num(spellID) == craft.recipe)
end

local function CraftCastStart(spellID)
	if not OurCast(spellID) then
		return
	end
	local startMS, endMS
	if type(_G.UnitCastingInfo) == "function" then
		local ok, _, _, _, s, e = pcall(_G.UnitCastingInfo, "player")
		if ok then
			startMS, endMS = Num(s), Num(e)
		end
	end
	craft.castAt = GetTime()
	craft.castFor = (startMS and endMS and endMS > startMS) and (endMS - startMS) / 1000 or nil
	Refresh("craft")
end

local CRAFT = {
	key = "craft", column = true, label = TEXT.craftLabel, combat = false,
	check = function()
		return craft.recipe ~= nil and craft.done < craft.total
	end,
	title = function()
		return craft.name or TEXT.craftLabel
	end,
	text = function()
		return TEXT.crafting:format(math.min(craft.done + 1, craft.total), craft.total)
	end,
	icon = function()
		return craft.icon or "Interface\\Icons\\Trade_BlackSmithing"
	end,
	count = function()
		local left = craft.total - craft.done
		return left > 1 and left or nil
	end,
	progress = function()
		if craft.castAt and craft.castFor then
			return craft.castAt, craft.castFor
		end
	end,
	actions = {
		{ glyph = "stop", tip = TEXT.stop, desc = TEXT.stopDesc, secure = function() return "/stopcasting" end },
	},
}

--------------------------------------------------------------------------------
-- Profession cooldowns (read while a profession is open; the ready time
-- kept per character as a server time, so it holds over a logout)
--------------------------------------------------------------------------------

local SALT_SHAKER = 15846
local cd = { key = nil, next = nil, serial = 0, scanAt = 0 }

local function CdStore()
	if not M.db then
		return nil
	end
	if not cd.key then
		local guid = Text((Ask(UnitGUID, "player")))
		if not guid then
			return nil
		end
		cd.key = "cd_" .. guid:gsub("[^%w]", "")
	end
	local s = M.db[cd.key]
	if type(s) ~= "table" then
		s = {}
		M.db[cd.key] = s
	end
	return s
end

-- the first one ready and not told yet
local function CdReady()
	local s = CdStore()
	if not s then
		return nil
	end
	local now = time()
	local best
	for id, e in pairs(s) do
		if type(e) == "table" and e.ready and e.ready <= now and not e.told then
			if not best or e.ready < s[best].ready then
				best = id
			end
		end
	end
	return best and s[best], best
end

local CdTimer   -- (below)

-- one timer for the next one due (a newer ask makes the older one do nothing)
local function CdSchedule()
	local s = CdStore()
	if not s then
		return
	end
	local now, soon = time(), nil
	for _, e in pairs(s) do
		if type(e) == "table" and e.ready and e.ready > now and (not soon or e.ready < soon) then
			soon = e.ready
		end
	end
	if soon then
		cd.serial = cd.serial + 1
		local serial = cd.serial
		C_Timer.After(soon - now + 1, function()
			if serial == cd.serial then
				CdTimer()
			end
		end)
	end
end

CdTimer = function()
	Refresh("cooldown", true)
	CdSchedule()
end

local function CdSet(id, name, icon, secs, profession)
	local s = CdStore()
	if not s then
		return
	end
	local e = s[id]
	if secs and secs > 0 then
		local readyAt = time() + floor(secs + 0.5)
		if not e or not e.ready or math.abs(e.ready - readyAt) > 60 then
			s[id] = { name = name, icon = icon, ready = readyAt, prof = profession }
		end
	end
end

local function CdScan()
	local T = C_TradeSkillUI
	if not (T and T.GetAllRecipeIDs and T.GetRecipeCooldown) or not On("cooldown") then
		return
	end
	local now = GetTime()
	if now - cd.scanAt < 2 then
		return   -- (the list's updates come in bursts)
	end
	cd.scanAt = now
	local ids = Ask(T.GetAllRecipeIDs)
	if type(ids) ~= "table" then
		return
	end
	local prof
	local info = T.GetBaseProfessionInfo and Ask(T.GetBaseProfessionInfo)
	if type(info) == "table" then
		prof = Text(info.professionName)
	end
	for i = 1, #ids do
		local id = Num(ids[i])
		local secs = id and Num((Ask(T.GetRecipeCooldown, id)))
		if secs and secs > 0 then
			local r = Ask(T.GetRecipeInfo, id)
			local name = type(r) == "table" and Text(r.name) or nil
			local icon = type(r) == "table" and not Secret(r.icon) and r.icon or nil
			CdSet(id, name, icon, secs, prof)
		end
	end
	CdSchedule()
	Refresh("cooldown")
end

-- the Salt Shaker: an item's cooldown (while it is in the bags)
local function CdSalt()
	if not On("cooldown") then
		return
	end
	local count = C_Item and Num((Ask(C_Item.GetItemCount, SALT_SHAKER)))
	if not (count and count > 0) then
		return
	end
	local fn = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
	local start, duration = Ask(fn, SALT_SHAKER)
	start, duration = Num(start), Num(duration)
	if start and duration and duration > 60 then
		local name = C_Item and Text((Ask(C_Item.GetItemNameByID, SALT_SHAKER)))
		local icon = C_Item and Ask(C_Item.GetItemIconByID, SALT_SHAKER)
		CdSet("item" .. SALT_SHAKER, name, (not Secret(icon)) and icon or nil, start + duration - GetTime())
		CdSchedule()
	end
end

local COOLDOWN = {
	key = "cooldown", column = true, label = TEXT.cdLabel, dismiss = "session", priority = "wait", combat = false,
	check = function()
		return CdReady() ~= nil
	end,
	title = function()
		local e = CdReady()
		return TEXT.cdReady:format(e and e.name or TEXT.cdLabel)
	end,
	text = function()
		local e = CdReady()
		return (e and e.prof) and TEXT.cdLine:format(e.prof) or TEXT.cdLineItem
	end,
	icon = function()
		local e = CdReady()
		return e and e.icon or "Interface\\Icons\\INV_Misc_PocketWatch_01"
	end,
	-- (a click: told, the next one ready shows, if any)
	onClick = function()
		local e = CdReady()
		if e then
			e.told = true
		end
		Refresh("cooldown", true)
	end,
	actions = {
		{ glyph = "check", tip = TEXT.ready_, desc = TEXT.cdLineItem,
		  fn = function()
			local e = CdReady()
			if e then
				e.told = true
			end
			Refresh("cooldown", true)
		  end },
	},
}

--------------------------------------------------------------------------------
-- By the portrait: bags, talents, Well Fed
--------------------------------------------------------------------------------

local portrait = { free = nil, points = nil, fedLeft = nil, fedSerial = 0 }
local NUM_BAGS = Num(_G.NUM_BAG_SLOTS) or 4

local function FreeSlots()
	local fn = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
	if type(fn) ~= "function" then
		return nil
	end
	local free = 0
	for bag = 0, NUM_BAGS do
		local n, family = Ask(fn, bag)
		n, family = Num(n), Num(family)
		if n and (family == nil or family == 0) then
			free = free + n
		end
	end
	return free
end

local function StayUp(key)
	local r = Rem()
	return r and r.StayUp and r:StayUp() and true or false
end

local BAGS = {
	key = "bags", label = TEXT.bagsLabel, urgency = 30, kind = "vendor", hint = TEXT.bagsHint,
	enabled = function() return On("bags") end,
	check = function()
		portrait.free = FreeSlots()
		local at = Num(M.db and M.db.bagsAt) or 2
		return portrait.free ~= nil and portrait.free <= at
	end,
	text = function()
		local f = portrait.free or 0
		return f == 0 and TEXT.bagsFull or (f == 1 and TEXT.bagsOne or TEXT.bags:format(f))
	end,
	icon = "Interface\\Icons\\INV_Misc_Bag_08",
	-- (user, 2026-09-30: it stays the whole time the bags are at or under
	-- Free Slots, "even in combat until the space is freed")
	persistent = function()
		local at = Num(M.db and M.db.bagsAt) or 2
		return portrait.free ~= nil and portrait.free <= at
	end,
	fight = function()
		local at = Num(M.db and M.db.bagsAt) or 2
		return portrait.free ~= nil and portrait.free <= at
	end,
	onClick = function()
		local s = Services()
		if s then
			pcall(s.GoTo, s, "vendor")
		end
	end,
}

local TALENTS = {
	key = "talents", label = TEXT.talentsLabel, urgency = 15, hint = TEXT.talentsHint,
	enabled = function() return On("talents") end,
	check = function()
		portrait.points = Num((Ask(_G.GetUnspentTalentPoints)))
		return portrait.points ~= nil and portrait.points > 0
	end,
	text = function()
		return TEXT.talents:format(portrait.points or 0)
	end,
	icon = "Interface\\Icons\\Ability_Marksmanship",
	persistent = function(key)
		return (portrait.points or 0) > 0 and StayUp(key)
	end,
}

local WELL_FED_SPELL = 19705
local FED_WARN = 120   -- s: the last two minutes

local function FedLeft()
	local name = Spell(WELL_FED_SPELL, "Well Fed")
	local U = C_UnitAuras
	if not (U and U.GetAuraDataBySpellName) then
		return nil
	end
	local aura = Ask(U.GetAuraDataBySpellName, "player", name, "HELPFUL")
	if type(aura) ~= "table" or Secret(aura) then
		return nil
	end
	local expires = Num(aura.expirationTime)
	if not (expires and expires > 0) then
		return nil
	end
	return expires - GetTime()
end

-- raised again when the last two minutes begin (one timer per change of the
-- buff; a newer ask makes the older one do nothing)
local function FedSchedule(left)
	portrait.fedSerial = portrait.fedSerial + 1
	if left and left > FED_WARN then
		local serial = portrait.fedSerial
		C_Timer.After(left - FED_WARN + 0.5, function()
			if serial == portrait.fedSerial then
				Refresh("wellfed", true)
			end
		end)
	end
end

local WELLFED = {
	key = "wellfed", label = TEXT.wellfedLabel, urgency = 5, hint = TEXT.wellfedHint,
	enabled = function() return On("wellfed") end,
	check = function()
		local left = FedLeft()
		local was = portrait.fedLeft
		portrait.fedLeft = left
		if left and (not was or math.abs((was or 0) - left) > 5) then
			FedSchedule(left)
		end
		return left ~= nil and left > 0 and left <= FED_WARN
	end,
	text = function()
		return TEXT.wellfed:format(Clock(math.max(0, portrait.fedLeft or 0)))
	end,
	icon = "Interface\\Icons\\Spell_Misc_Food",
}

--------------------------------------------------------------------------------
-- The specs, the events
--------------------------------------------------------------------------------

local ORDER = { "loot", "corpse", "timed", "summon", "resurrect", "ready", "threat", "whisper", "pet", "auction", "craft",
	"cooldown", "bags", "talents", "wellfed" }
local SPECS = { loot = LOOT, corpse = CORPSE, timed = TIMED, summon = SUMMON, resurrect = RESURRECT, ready = READY,
	threat = THREAT,
	whisper = WHISPER, pet = PET, auction = AUCTION, craft = CRAFT, cooldown = COOLDOWN, bags = BAGS, talents = TALENTS,
	wellfed = WELLFED }
for _, key in ipairs(ORDER) do
	local spec = SPECS[key]
	if spec.column then
		spec.enabled = function()
			return On(key)
		end
	end
end
M.SPECS = SPECS   -- (read only: the tests, a dump)

local EVENTS = {
	loot = { "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS" },
	corpse = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA", "CORPSE_IN_RANGE", "CORPSE_OUT_OF_RANGE" },
	timed = { "QUEST_LOG_UPDATE" },
	summon = { "CONFIRM_SUMMON", "CANCEL_SUMMON" },
	resurrect = { "RESURRECT_REQUEST", "PLAYER_ALIVE", "PLAYER_UNGHOST" },
	ready = { "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED" },
	threat = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED",
		"PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" },
	whisper = {},   -- (the Chat module's bus event 'whisper': no game event of its own)
	pet ={ "UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE" },
	auction = { "CHAT_MSG_SYSTEM", "AUCTION_HOUSE_SHOW_NOTIFICATION", "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", "MAIL_SHOW" },
	craft = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
		"UPDATE_TRADESKILL_CAST_STOPPED" },
	cooldown = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "BAG_UPDATE_COOLDOWN" },
	bags = { "BAG_UPDATE_DELAYED" },
	talents = { "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" },
	wellfed = { "UNIT_AURA" },
}

local function OnEvent(_, event, a1, a2, a3)
	if event == "START_LOOT_ROLL" then
		LootAdd(a1, a2)
		Refresh("loot", true)
	elseif event == "CANCEL_LOOT_ROLL" then
		local id = Num(a1)
		if id then
			LootDrop(id)
			Refresh("loot")
		end
	elseif event == "CANCEL_ALL_LOOT_ROLLS" then
		loot.n = 0
		wipe(loot.rolls)
		Refresh("loot")
	elseif event == "CORPSE_IN_RANGE" or event == "CORPSE_OUT_OF_RANGE" then
		corpse.near = event == "CORPSE_IN_RANGE" and corpse.ghost
		Refresh("corpse", corpse.near)
	elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_TARGET_CHANGED"
		or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
		if On("threat") then
			Refresh("threat")
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- (a new fight: a Not now from the last one is over)
		if On("threat") then
			Refresh("threat", true)
		end
	elseif event == "QUEST_LOG_UPDATE" then
		Refresh("timed")
	elseif event == "CONFIRM_SUMMON" then
		SummonRead()
		Refresh("summon", true)
	elseif event == "CANCEL_SUMMON" then
		summon.at = nil
		Refresh("summon")
	elseif event == "RESURRECT_REQUEST" then
		res.who = Text(a1)
		res.at = GetTime()
		local timer = Ask(_G.ResurrectHasTimer)
		local delay = Num((Ask(_G.GetCorpseRecoveryDelay))) or 0
		res.total = (Secret(timer) or timer ~= false) and (delay + 60) or nil
		Refresh("resurrect", true)
	elseif event == "READY_CHECK" then
		-- (the player's own check: nothing to answer, as in the game's box)
		if Ask(UnitIsUnit, a1, "player") == true then
			ready.at = nil
			Refresh("ready")
			return
		end
		ready.who, ready.at, ready.total = Text(a1), GetTime(), Num(a2)
		Refresh("ready", true)
	elseif event == "READY_CHECK_CONFIRM" then
		local isPlayer = not Secret(a1) and type(a1) == "string" and Ask(UnitIsUnit, a1, "player")
		if isPlayer == true then
			ready.at = nil   -- (answered)
			Refresh("ready")
		end
	elseif event == "READY_CHECK_FINISHED" then
		ready.at = nil
		Refresh("ready")
	elseif event == "CHAT_MSG_SYSTEM" then
		if On("auction") then
			OnSystem(a1)
		end
	elseif event == "AUCTION_HOUSE_SHOW_NOTIFICATION" or event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
		if On("auction") then
			OnAuctionNotice(a1, a2)
		end
	elseif event == "MAIL_SHOW" then
		if #auction.list > 0 then
			wipe(auction.list)
			Refresh("auction")
		end
	elseif event == "UNIT_SPELLCAST_START" then
		if a1 == "player" then
			CraftCastStart(a3)
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if a1 == "player" and OurCast(a3) then
			craft.done = craft.done + 1
			craft.castAt = nil
			if craft.done >= craft.total then
				CraftEnd()
			else
				Refresh("craft")
			end
		end
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		if a1 == "player" and OurCast(a3) then
			CraftEnd()
		end
	elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" then
		CraftEnd()
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
		CdScan()
	elseif event == "BAG_UPDATE_COOLDOWN" then
		CdSalt()
	elseif event == "BAG_UPDATE_DELAYED" then
		Refresh("bags")
	elseif event == "UNIT_PET" or event == "PET_UI_UPDATE" then
		if event == "PET_UI_UPDATE" or a1 == "player" then
			Refresh("pet", true)
		end
	elseif event == "UNIT_HAPPINESS" then
		Refresh("pet", true)
	elseif event == "PLAYER_LEVEL_UP" or event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
		Refresh("talents", true)
	elseif event == "UNIT_AURA" then
		if a1 == "player" and not InCombatLockdown() then
			Refresh("wellfed")
		end
	end
	-- (the corpse run and the resurrect offer both hear these)
	if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST"
		or (event == "ZONE_CHANGED_NEW_AREA" and corpse.ghost) then
		if On("corpse") then
			CorpseState()
		end
		if event ~= "PLAYER_DEAD" and event ~= "ZONE_CHANGED_NEW_AREA" and res.at then
			res.at = nil
			Refresh("resurrect")
		end
	end
end

-- the switched-on uses' events (one this client does not have is refused,
-- not an error)
local function Listen()
	local f = state.frame
	if not f then
		return
	end
	f:UnregisterAllEvents()
	if not (M.isEnabled and M.db) then
		return
	end
	for _, key in ipairs(ORDER) do
		if M.db[key] == true then
			for _, event in ipairs(EVENTS[key]) do
				pcall(f.RegisterEvent, f, event)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The game's own windows the widgets stand in for (user, 2026-09-30: "i only
-- want people to see the widget one"). While a use is on, its game window
-- stays out of sight, put back when it goes off. Only C calls on the game's
-- frames, no key written on them and none of their layout run from here:
--   the ready check's box stops listening for READY_CHECK;
--   the four loot roll frames still open and close as the game has them,
--   but draw nothing and take no clicks (hiding them from here would lay out
--   the screen's bottom frames as MelloUI's code: blocked in a fight).
--   the game's popups for a summon, a resurrect offer and the corpse (user,
--   2026-09-30, "Invisible popup") still open, time out and answer as the
--   game has them, but draw nothing and take no clicks; put back as they
--   close. Never hidden or shown from here: hiding one from an addon froze
--   Escape in 0.15.0, and the popup system's own "do not show" hook would
--   decline the summon. Told by the popup system's own callbacks
--   (PopupEventManager's PopupOpened / PopupClosed, each run through
--   securecallfunction: nothing of ours in the game's own calls). They
--   take a popup's place still: the next popup shows below them. None of
--   the three closes on Escape.
-- The Gamepad UI keeps the game's boxes (its D-pad does not reach a widget).
--------------------------------------------------------------------------------

local taken = { ready = false, loot = false, mouse = {} }   -- mouse: [frame] = true, its mouse taken off here

local function Mouse(frame, off, depth)
	if off then
		local ok, enabled = pcall(frame.IsMouseEnabled, frame)
		if ok and enabled == true then
			taken.mouse[frame] = true
			frame:EnableMouse(false)
		end
	elseif taken.mouse[frame] then
		taken.mouse[frame] = nil
		frame:EnableMouse(true)
	end
	if depth > 0 then
		for i = 1, select("#", frame:GetChildren()) do
			Mouse((select(i, frame:GetChildren())), off, depth - 1)
		end
	end
end

local function LootFrames(off)
	for i = 1, 4 do
		local f = _G["GroupLootFrame" .. i]
		if type(f) == "table" and f.SetAlpha and f.GetChildren then
			f:SetAlpha(off and 0 or 1)
			Mouse(f, off, 2)
		end
	end
end

local function ReadyBox(off)
	local f = _G.ReadyCheckFrame
	if type(f) == "table" and f.UnregisterEvent then
		if off then
			f:UnregisterEvent("READY_CHECK")
		else
			f:RegisterEvent("READY_CHECK")
		end
	end
end

local VEIL = { CONFIRM_SUMMON = "summon", RESURRECT = "resurrect", RESURRECT_NO_SICKNESS = "resurrect",
	RESURRECT_NO_TIMER = "resurrect", RECOVER_CORPSE = "corpse" }
local veiled = {}   -- [dialog] = true: made invisible here

local function Veil(dialog, on)
	veiled[dialog] = on or nil
	dialog:SetAlpha(on and 0 or 1)
	Mouse(dialog, on, 3)
end

local function PopupOpened(_, dialog)
	if type(dialog) ~= "table" or not dialog.SetAlpha then
		return
	end
	local which = dialog.which
	local use = type(which) == "string" and VEIL[which]
	if use and On(use) and Rem() ~= nil and not MelloUI.Safe.GamepadUI() then
		Veil(dialog, true)
	elseif veiled[dialog] then
		Veil(dialog, false)
	end
end

local function PopupClosed(_, dialog)
	if veiled[dialog] then
		Veil(dialog, false)
	end
end

local function TakeOver()
	local can = Rem() ~= nil and not MelloUI.Safe.GamepadUI()
	local takeReady, takeLoot = can and On("ready"), can and On("loot")
	if takeReady ~= taken.ready then
		taken.ready = takeReady
		ReadyBox(takeReady)
	end
	if takeLoot ~= taken.loot then
		taken.loot = takeLoot
		LootFrames(takeLoot)
	end
	-- the popups' two callbacks, once, from the first use that wants them
	-- (each looks at the switch itself); a popup shown now put back when
	-- its use went off
	local P = _G.PopupEventManager
	if not taken.popups and can and (On("summon") or On("resurrect") or On("corpse"))
		and type(P) == "table" and type(P.RegisterCallback) == "function" then
		taken.popups = true
		P:RegisterCallback("PopupOpened", PopupOpened, M)
		P:RegisterCallback("PopupClosed", PopupClosed, M)
	end
	for dialog in pairs(veiled) do
		local use = VEIL[dialog.which]
		if not (can and use and On(use)) then
			Veil(dialog, false)
		end
	end
end

-- (the Chat module: a new whisper's window waits for the widget's Reply
-- while the Whispers widget is on)
function M:Takes(use)
	return use == "whisper" and On("whisper") and Rem() ~= nil or false
end

-- the crafting batch: one post-hook for good, made with the first OnEnable
-- (it runs after the game's call, and only counts)
local hooked = false
local function HookCraft()
	if hooked or not (C_TradeSkillUI and type(C_TradeSkillUI.CraftRecipe) == "function") then
		return
	end
	hooked = true
	hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(recipeID, numCasts)
		if M.isEnabled then
			OnCraftRecipe(recipeID, numCasts)
		end
	end)
end

local function Register(on)
	local r = Rem()
	if not r or state.registered == on then
		return
	end
	state.registered = on
	for _, key in ipairs(ORDER) do
		if on then
			r:Register(SPECS[key])
		else
			r:Unregister(key)
		end
	end
end

-- a use's state read afresh (switched on, or the module on)
local function Read(key)
	if key == "loot" then
		LootRead()
	elseif key == "corpse" then
		CorpseState()
	elseif key == "pet" then
		pet.hunter = nil
	end
	Refresh(key)
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
	MelloUI:On("whisper", OnWhisper, "Widgets: whispers")
	MelloUI:On("where", CorpseWhere, "Widgets: corpse")
end

function M:OnEnable(db)
	self.db = db
	if not state.frame then
		state.frame = CreateFrame("Frame")
		Perf.SetScript(state.frame, "OnEvent", OnEvent)
	end
	HookCraft()
	Listen()
	Register(true)
	TakeOver()
	for _, key in ipairs(ORDER) do
		if db[key] == true then
			Read(key)
		end
	end
end

function M:OnDisable()
	Listen()
	TakeOver()
	if not (MelloUI.restartingModules and M.isEnabled) then
		Register(false)
	end
	local R = Route()
	if corpse.ghost and R and type(R.WantWhere) == "function" then
		pcall(R.WantWhere, R, "Widgets", false)
	end
	corpse.ghost = false
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if SPECS[key] then
		Listen()
		TakeOver()
		if value then
			Read(key)
		else
			if key == "corpse" then
				CorpseState()
			end
			Refresh(key)
		end
	elseif key == "bagsAt" then
		Refresh("bags", true)
	end
end
