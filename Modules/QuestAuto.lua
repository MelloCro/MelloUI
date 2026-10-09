--------------------------------------------------------------------------------
-- MelloUI - Quest Auto: auto accept and hand-in (0.19.8; the user,
-- 2026-10-06, the addon study's item 6, "all as recommended": off by
-- default, a held key skips it, never a repeatable quest, a choice of
-- rewards waits unless Take The Upgrade is on, a giver's only quest picked
-- from its gossip).
--
-- Every rule reads the game's own answers at that moment -- the gossip's and
-- the greeting's quest info (repeatable, daily or weekly, grey, ignored), the
-- quest log's repeatable flag, the quest frame's money asked, its choices and
-- whether each can be used -- never a list of quests.
--   QUEST_DETAIL    accept (AcceptQuest); a grey or repeatable quest waits
--   QUEST_PROGRESS  hand the items in (CompleteQuest) when it can be
--   QUEST_COMPLETE  take the reward: none or one (GetQuestReward); a choice
--                   waits, or Take The Upgrade picks one; money asked, or a
--                   repeatable quest (the turn-ins for reputation): waits
--   GOSSIP_SHOW     a finished quest of the NPC's handed in first (Auto Hand
--                   In), else its only quest opened when it is not grey,
--                   repeatable or ignored (Auto Accept)
--   QUEST_GREETING  the same on the old greeting panel
-- An escort's or a shared quest's question (QUEST_ACCEPT_CONFIRM) is always
-- yours. With the Skip Key held as a window opens, nothing is done there.
-- Each step waits a moment (ACT_DELAY) so the dialog is still open for
-- what reads it first -- Voice Over's narration (the next frame), the Quest
-- List's learning -- and is only taken if the same quest still shows.
-- Its events are on only while one of its switches is: nothing at login
-- otherwise. Every value the client hands over is read secret-safe.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestAuto")
local C_Timer = Perf.C_Timer

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Plain = MelloUI.Safe.Value

local M = MelloUI:RegisterModule("QuestAuto", {
	title = "Auto Accept & Hand In",
	desc = "Accepts quests and hands them in as you talk to their givers, off until you switch it on.",
	icon = "Interface\\GossipFrame\\AvailableQuestIcon",
	flavour = "Talk, and the quest is yours. Hold Shift to read it first.",
	role = "adds",
	-- (not on the installer's Features step: its switches are on Quest List > List, off by default)
	installer = false,
	enabledByDefault = true,
	defaults = {
		accept = false,
		handIn = false,
		takeUpgrade = false,
		skipKey = "shift",
	},
	options = {
		{ type = "toggle", key = "accept", name = "Auto Accept Quests",
		  desc = "Accept a quest as soon as its giver shows it, and open a giver's only quest from its list. Grey, "
			.. "repeatable, daily and ignored quests are left to you, and so is an escort's or a shared quest's question." },
		{ type = "toggle", key = "handIn", name = "Auto Hand In",
		  desc = "Hand a finished quest in as soon as you talk to whoever takes it, and pick it from their list first. "
			.. "A choice of rewards waits for you (unless Take The Upgrade is on), and so do a hand-in that costs money "
			.. "and repeatable turn-ins." },
		{ type = "toggle", key = "takeUpgrade", name = "Take The Upgrade", parent = "handIn",
		  desc = "With a choice of rewards: take the one with the highest item level over what you wear in its slot, "
			.. "among those you can use; when none is better, the one that sells for the most." },
		{ type = "dropdown", key = "skipKey", name = "Skip Key",
		  values = { { value = "shift", label = "Shift" }, { value = "ctrl", label = "Ctrl" }, { value = "alt", label = "Alt" } },
		  desc = "Hold it as you talk to a giver to see its dialog as usual: nothing is accepted or handed in there." },
	},
})

local ACT_DELAY = 0.2   -- s: the dialog stays open this long for what reads it first (Voice Over: the next frame)

--------------------------------------------------------------------------------
-- Reads (every answer secret-safe: a secret answer counts as "leave it to you")
--------------------------------------------------------------------------------

-- every value the call answered (GetItemInfo's eleven), nothing when it raised
local function Answer(ok, ...)
	if not ok then
		return nil
	end
	return ...
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	return Answer(pcall(fn, ...))
end

local function Yes(v)
	return Plain(v) == true
end

local function SkipHeld()
	local key = M.db and M.db.skipKey or "shift"
	local fn = (key == "ctrl" and IsControlKeyDown) or (key == "alt" and IsAltKeyDown) or IsShiftKeyDown
	return Yes(Call(fn)) or Plain(Call(fn)) == 1
end

local function QuestID()
	return Num(Call(GetQuestID))
end

local function Repeatable(id)
	local log = C_QuestLog
	return id ~= nil and log ~= nil and Yes(Call(log.IsRepeatableQuest, id))
end

local function Grey(id)
	local log = C_QuestLog
	return id ~= nil and log ~= nil and Yes(Call(log.IsQuestTrivial, id))
end

-- a gossip / greeting quest no rule lets through: grey, repeatable, daily or
-- weekly, ignored, or read secret
local function Plainly(info)
	if type(info) ~= "table" or Secret(info.questID) then
		return false
	end
	local freq = Plain(info.frequency)
	return not (Yes(info.isTrivial) or Yes(info.repeatable) or Yes(info.isIgnored) or (freq ~= nil and freq ~= 0)
		or Secret(info.isTrivial) or Secret(info.repeatable))
end

--------------------------------------------------------------------------------
-- Take The Upgrade: among the choices you can use, the largest item level
-- over what you wear in the slot (the lower of a pair: rings, trinkets, a
-- one-hand weapon); none better: the one that sells for the most. Nil while
-- an item's details are not in the cache yet (asked for, and tried again
-- when they come) or none can be read.
--------------------------------------------------------------------------------
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_THROWN = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 },
}

-- an item's level, its slot kind and its sell price; nil while not cached
local function ItemOf(link)
	if type(link) ~= "string" then
		return nil
	end
	local name, _, _, level, _, _, _, _, equipLoc, _, price = Call((C_Item and C_Item.GetItemInfo) or GetItemInfo, link)
	if Plain(name) == nil then
		return nil
	end
	return Num(level) or 0, Plain(equipLoc), Num(price) or 0
end

local function WornLevel(slot)
	local link = Plain(Call(GetInventoryItemLink, "player", slot))
	if not link then
		return 0   -- (an empty slot: anything is better)
	end
	local level = ItemOf(link)
	return level or 0
end

local waiting = false   -- a choice whose items were not cached yet: tried again as they come

local function BestChoice(n)
	local best, gain, richest, price = nil, 0, nil, -1
	for i = 1, n do
		local link = Plain(Call(GetQuestItemLink, "choice", i))
		local level, equipLoc, sell = ItemOf(link)
		if not level then
			waiting = true
			return nil
		end
		local _, _, _, _, usable = Call(GetQuestItemInfo, "choice", i)
		local slots = equipLoc and SLOTS[equipLoc]
		if slots and Yes(usable) then
			local worn = WornLevel(slots[1])
			if slots[2] then
				worn = math.min(worn, WornLevel(slots[2]))
			end
			if level - worn > gain then
				best, gain = i, level - worn
			end
		end
		if sell > price then
			richest, price = i, sell
		end
	end
	return best or richest
end

--------------------------------------------------------------------------------
-- The steps (one pending at a time: made once, nothing per event)
--------------------------------------------------------------------------------

local frame                           -- its event frame, made when a switch is first on (Sync)
local pending, pendingID = nil, nil   -- the step to take after ACT_DELAY, the quest it was for
local handedGossip = {}               -- [questID] = true: selected from this gossip (never twice: GOSSIP_CLOSED clears)

local function Accept()
	if QuestID() == pendingID and M.db.accept then
		Call(AcceptQuest)
	end
end

local function Progress()
	if QuestID() == pendingID and M.db.handIn and Yes(Call(IsQuestCompletable)) then
		Call(CompleteQuest)
	end
end

local function Reward()
	if QuestID() ~= pendingID or not M.db.handIn then
		return
	end
	local money = Num(Call(GetQuestMoneyToGet))
	local n = Num(Call(GetNumQuestChoices))
	if money == nil or money > 0 or n == nil then
		return
	end
	if n == 0 then
		Call(GetQuestReward, 0)
	elseif n == 1 then
		Call(GetQuestReward, 1)
	elseif M.db.takeUpgrade then
		local i = BestChoice(n)
		if i then
			Call(GetQuestReward, i)
		elseif waiting and frame then
			frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")   -- (tried again as the items come into the cache)
		end
	end
end

local Run = Perf.Shared("Quest Auto's step after its moment", function()
	local fn = pending
	pending = nil
	if fn then
		fn()
	end
end)

local function Soon(fn, id)
	pending, pendingID = fn, id
	C_Timer.After(ACT_DELAY, Run)
end

local function OnDetail()
	local id = QuestID()
	if M.db.accept and id and not Repeatable(id) and not Grey(id) then
		Soon(Accept, id)
	end
end

local function OnProgress()
	local id = QuestID()
	if M.db.handIn and id and not Repeatable(id) then
		Soon(Progress, id)
	end
end

local function OnComplete()
	local id = QuestID()
	if M.db.handIn and id and not Repeatable(id) then
		Soon(Reward, id)
	end
end

-- the gossip: a finished quest handed in first, else the only quest opened
local function OnGossip()
	local G = C_GossipInfo
	if not G then
		return
	end
	if M.db.handIn then
		for _, q in ipairs(Call(G.GetActiveQuests) or {}) do
			local id = Plain(q.questID)
			if Yes(q.isComplete) and id and not handedGossip[id] and not Yes(q.repeatable) and not Secret(q.repeatable) then
				handedGossip[id] = true
				Call(G.SelectActiveQuest, id)
				return
			end
		end
	end
	if M.db.accept then
		local available = Call(G.GetAvailableQuests) or {}
		local only = #available == 1 and available[1]
		if only and Plainly(only) then
			Call(G.SelectAvailableQuest, only.questID)
		end
	end
end

-- the old greeting panel (a giver with several quests and no gossip)
local function OnGreeting()
	if M.db.handIn then
		for i = 1, Num(Call(GetNumActiveQuests)) or 0 do
			local _, done = Call(GetActiveTitle, i)
			local id = Num(Call(GetActiveQuestID, i))
			if Yes(done) and not Repeatable(id) and not (id and handedGossip[id]) then
				if id then
					handedGossip[id] = true
				end
				Call(SelectActiveQuest, i)
				return
			end
		end
	end
	if M.db.accept and Num(Call(GetNumAvailableQuests)) == 1 then
		local trivial, frequency, repeatable, _, id = Call(GetAvailableQuestInfo, 1)
		if Plainly({ questID = id, isTrivial = trivial, frequency = frequency, repeatable = repeatable }) then
			Call(SelectAvailableQuest, 1)
		end
	end
end

local HANDLERS = {
	QUEST_DETAIL = OnDetail,
	QUEST_PROGRESS = OnProgress,
	QUEST_COMPLETE = OnComplete,
	GOSSIP_SHOW = OnGossip,
	QUEST_GREETING = OnGreeting,
}

local OnEvent = Perf.Shared("Quest Auto's events", function(_, event)
	if event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
		if event == "GOSSIP_CLOSED" then
			wipe(handedGossip)
		end
		if waiting then
			waiting = false
			frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		end
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" then
		-- (Take The Upgrade's choices came into the cache: the reward panel again)
		if waiting then
			waiting = false
			frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
			OnComplete()
		end
		return
	end
	if SkipHeld() then
		return
	end
	local fn = HANDLERS[event]
	if fn then
		fn()
	end
end, "script")

-- its events on while one of its switches is
local function Sync()
	local on = M.isEnabled and M.db and (M.db.accept or M.db.handIn) and true or false
	if on and not frame then
		frame = CreateFrame("Frame")
		Perf.SetScript(frame, "OnEvent", OnEvent)
	end
	if not frame then
		return
	end
	for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING",
		"GOSSIP_CLOSED", "QUEST_FINISHED" }) do
		if on then
			frame:RegisterEvent(event)
		else
			frame:UnregisterEvent(event)
		end
	end
	if not on then
		frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		waiting, pending = false, nil
	end
end

function M:OnEnable(db)
	self.db = db
	Sync()
end

function M:OnDisable()
	Sync()
end

function M:OnSettingChanged(key)
	if key == "accept" or key == "handIn" then
		Sync()
	end
end

-- (for its test: the reads and the steps, and its event frame -- nil until a switch is first on)
M.BestChoice, M.Plainly, M.SkipHeld = BestChoice, Plainly, SkipHeld
function M:EventFrame()
	return frame
end
