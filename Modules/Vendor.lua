--------------------------------------------------------------------------------
-- MelloUI - Vendor
--
-- Automatically repairs all gear and sells grey (junk) items whenever a
-- merchant window is opened.
--
-- What other modules use of it (Restock's shop panel, 0.14.0):
--   M:IsSelling()         true while the junk sale runs (money still changes)
--   M:AfterSelling(fn)    fn() now when no sale runs, else once it is over
--                         (the same fn asked twice runs once)
--   M:Report(fmt, ...)    a line in chat when Report In Chat is on
--   M.CoinText(copper)    the gold / silver / copper text with coin icons
-- Every value the client hands over is read secret-safe (MelloUI.Safe: the
-- secret test first): a secret cost, money or item quality is never compared.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Vendor")
local C_Timer = Perf.C_Timer
local IsSecret = MelloUI.Safe.IsSecret
local Plain = MelloUI.Safe.Value
local Num = MelloUI.Safe.Number

local M = MelloUI:RegisterModule("Vendor", {
	title = "Vendor",
	desc = "Automatically repair your gear and sell junk items when visiting a merchant.",
	icon = "Interface\\Icons\\INV_Misc_Coin_02",
	flavour = "Sell the grey, mend the steel. Every merchant visit handled before the window opens.",
	role = "adds",
	tweak = { label = "Vendor Automation", desc = "Repair your gear and sell junk automatically at a merchant.", order = 13 },
	defaults = {
		autoRepair = true,
		guildRepair = false,
		autoSell = true,
		report = true,
	},
	options = {
		{ type = "header", name = "Repair" },
		{ type = "toggle", key = "autoRepair", name = "Auto Repair",
		  desc = "Repair all equipped and carried items when a merchant that can repair is opened." },
		{ type = "toggle", key = "guildRepair", parent = "autoRepair", name = "Use Guild Funds",
		  desc = "Pay repairs from the guild bank when allowed. Falls back to your own gold if the guild cannot cover the cost." },
		{ type = "header", name = "Selling" },
		{ type = "toggle", key = "autoSell", name = "Auto Sell Junk",
		  desc = "Sell all grey quality items in your bags when a merchant is opened." },
		{ type = "header", name = "Chat" },
		{ type = "toggle", key = "report", name = "Report In Chat",
		  desc = "Print the repair cost, the gold gained from selling junk and what Restock bought for you." },
	},
})

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function CoinText(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper)
	elseif GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	return tostring(copper) .. "c"
end

local function Report(msg, ...)
	if M.db and M.db.report then
		MelloUI:Print(msg, ...)
	end
end

-- (for Restock's line: "Restocked: 20 Melon Juice ... for 1g 20s")
function M:Report(msg, ...)
	Report(msg, ...)
end
M.CoinText = CoinText

-- The player's money, or nil when the client hands it over secret
local function Money()
	local ok, money = pcall(GetMoney)
	return ok and Num(money) or nil
end

-- fn() guarded: its first result, or nil when it is missing, raised or
-- answered secret
local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Plain(v)
end

local POOR_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

-- the last bag the junk sale and the gear check look in
local function LastBag()
	return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

--------------------------------------------------------------------------------
-- Repair
--------------------------------------------------------------------------------

-- The own gold's repair: only when the money covers the cost (the money
-- unreadable: nothing is spent on a guess); `done` the line said after it
local function RepairOwn(cost, done)
	local money = Money()
	if not money then
		return
	end
	if money >= cost then
		RepairAllItems(false)
		Report(done, CoinText(cost))
	else
		Report("|cffff4040Not enough gold to repair|r (%s needed).", CoinText(cost))
	end
end

-- One piece's durability as pcall hands it over: "worn" (below its full
-- durability), "whole" (full, or none at all: an empty slot, a ring), or nil
-- when it cannot be read (raised, secret)
local function PieceState(ok, cur, max)
	if not ok or IsSecret(cur) or IsSecret(max) then
		return nil
	end
	cur, max = Num(cur), Num(max)
	if cur and max and cur < max then
		return "worn"
	end
	return "whole"
end

-- Whether the gear still wants mending, read from the pieces themselves (no
-- merchant needed, unlike the repair price): true when a worn or carried
-- piece is below its full durability, false when every piece reads whole,
-- nil when a piece cannot be read or the calls are missing
local function GearWorn()
	local wornGet = _G.GetInventoryItemDurability
	local carriedGet = C_Container and C_Container.GetContainerItemDurability
	if type(wornGet) ~= "function" or type(carriedGet) ~= "function" then
		return nil
	end
	local unread = false
	for slot = 1, 19 do   -- the worn gear's slots (1 head .. 19 tabard)
		local state = PieceState(pcall(wornGet, slot))
		if state == "worn" then
			return true
		end
		unread = unread or state == nil
	end
	for bag = 0, LastBag() do
		for slot = 1, Num(Ask(C_Container.GetContainerNumSlots, bag)) or 0 do
			local state = PieceState(pcall(carriedGet, bag, slot))
			if state == "worn" then
				return true
			end
			unread = unread or state == nil
		end
	end
	if unread then
		return nil
	end
	return false
end

-- A repair the guild bank was asked to pay is looked at again a moment
-- later, once the server's answer (the gear's durability) is in: only the
-- player's withdraw limit can be read at a merchant, not the bank's balance,
-- so gear that still wants mending means the bank could not pay -- the own
-- gold then, as the option promises (audit, 0.15.0: nothing was mended and
-- chat still said "guild funds"). The repair price is the merchant's (its
-- reputation discount) and reads 0 once the merchant is closed, so with the
-- merchant gone the pieces themselves decide, and gear that cannot be read
-- claims nothing (review, 0.15.0: a merchant closed within the second said
-- "guild funds" for gear the bank never paid for). A check left from an
-- earlier open finds a later one waiting and does nothing (one timer
-- function, no closure).
local GUILD_CHECK = 1.0              -- the wait for the answer (s), as the junk sale's report
local guildCost, guildPending = nil, 0   -- what the guild was asked to pay; the checks waiting

local function GuildCheck()
	guildPending = guildPending - 1
	if guildPending > 0 then
		return
	end
	guildPending = 0
	local asked = guildCost
	guildCost = nil
	if not asked then
		return
	end
	if Ask(CanMerchantRepair) then
		local okCost, cost = pcall(GetRepairAllCost)
		cost = okCost and Num(cost) or nil
		if not cost then
			return   -- (the cost unreadable: nothing said, nothing spent)
		end
		if cost <= 0 then
			Report("Repaired for %s (guild funds).", CoinText(asked))
		else
			RepairOwn(cost, "The guild bank could not pay: repaired for %s from your own gold.")
		end
		return
	end
	local worn = GearWorn()
	if worn then
		Report("The guild bank could not pay for the repair (%s needed).", CoinText(asked))
	elseif worn == false then
		Report("Repaired for %s (guild funds).", CoinText(asked))
	end
end

local function Repair()
	if not Ask(CanMerchantRepair) then
		return
	end
	local okCost, cost, canRepair = pcall(GetRepairAllCost)
	if not okCost then
		return
	end
	cost = Num(cost)
	if not (cost and cost > 0) or IsSecret(canRepair) or not canRepair then
		return
	end

	if M.db.guildRepair and Ask(CanGuildBankRepair) then
		-- -1: the guild pays whatever it costs (also when the client does not
		-- say how much may be taken)
		local guildFunds = -1
		if GetGuildBankWithdrawMoney then
			guildFunds = Num(Ask(GetGuildBankWithdrawMoney))
		end
		if guildFunds and (guildFunds == -1 or guildFunds >= cost) then
			RepairAllItems(true)
			-- (said once the answer is in: GuildCheck)
			guildCost, guildPending = cost, guildPending + 1
			C_Timer.After(GUILD_CHECK, GuildCheck)
			return
		end
	end

	RepairOwn(cost, "Repaired for %s.")
end

--------------------------------------------------------------------------------
-- Junk selling
--------------------------------------------------------------------------------

local selling = false
-- the junk found, by position: its bag and slot (two lists kept and filled
-- again, no table per slot), gone through from queuePos on
local queueBag, queueSlot = {}, {}
local queueLen, queuePos = 0, 0
local moneyBefore = nil
local itemsSold = 0
local afterSelling = {}   -- fns run once the sale is over (M:AfterSelling)

-- a grey item that sells: every field read secret-safe (the secret test
-- first); one that cannot be read is left alone
local function IsJunk(bag, slot)
	local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
	if not ok or type(info) ~= "table" then
		return false
	end
	local noValue, locked = info.hasNoValue, info.isLocked
	if IsSecret(noValue) or IsSecret(locked) then
		return false
	end
	return Num(info.quality) == POOR_QUALITY and not noValue and not locked
end

local function RunAfterSelling()
	for i = 1, #afterSelling do
		local fn = afterSelling[i]
		afterSelling[i] = nil
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local function FinishSelling()
	selling = false
	queueLen, queuePos = 0, 0
	local now = Money()
	local gained = (now and moneyBefore) and (now - moneyBefore) or 0
	if itemsSold > 0 then
		if gained > 0 then
			Report("Sold %d junk item%s for %s.", itemsSold, itemsSold == 1 and "" or "s", CoinText(gained))
		else
			Report("Sold %d junk item%s.", itemsSold, itemsSold == 1 and "" or "s")
		end
	end
	itemsSold = 0
	RunAfterSelling()
end

function M:IsSelling()
	return selling
end

function M:AfterSelling(fn)
	if type(fn) ~= "function" then
		return
	end
	if not selling then
		fn()
		return
	end
	for i = 1, #afterSelling do
		if afterSelling[i] == fn then
			return
		end
	end
	afterSelling[#afterSelling + 1] = fn
end

local SELL_BATCH = 6
local SELL_DELAY = 0.25

-- The sale's timers, one shared function each (no closure per sale), with
-- how many of each are still waiting: a timer left from a sale that ended
-- early (the shop closed and opened again within the second) finds a later
-- one asked after it and does nothing, so it never ends the next sale early
-- nor runs a second batch alongside it
local finishPending, batchPending = 0, 0
local bulkSale = false   -- the sale under way is the game's own bulk sale (no batches)
local SellNextBatch

local function FinishTimer()
	finishPending = finishPending - 1
	if finishPending <= 0 then
		finishPending = 0
		if selling then
			FinishSelling()
		end
	end
end

local function BatchTimer()
	batchPending = batchPending - 1
	if batchPending <= 0 then
		batchPending = 0
		SellNextBatch()
	end
end

local function FinishLater(delay)
	finishPending = finishPending + 1
	C_Timer.After(delay, FinishTimer)
end

SellNextBatch = function()
	if not selling or bulkSale then
		return
	end
	if not MerchantFrame or not MerchantFrame:IsShown() then
		FinishSelling()
		return
	end
	local count = 0
	while queuePos < queueLen and count < SELL_BATCH do
		queuePos = queuePos + 1
		local bag, slot = queueBag[queuePos], queueSlot[queuePos]
		if IsJunk(bag, slot) then
			C_Container.UseContainerItem(bag, slot)
			itemsSold = itemsSold + 1
			count = count + 1
		end
	end
	if queuePos < queueLen then
		batchPending = batchPending + 1
		C_Timer.After(SELL_DELAY, BatchTimer)
	else
		-- Give the server a moment to deliver the gold before reporting.
		FinishLater(0.5)
	end
end

-- the junk in the bags into the queue; how many
local function CollectJunk()
	queueLen, queuePos = 0, 0
	for bag = 0, LastBag() do
		local numSlots = Num(Ask(C_Container.GetContainerNumSlots, bag)) or 0
		for slot = 1, numSlots do
			if IsJunk(bag, slot) then
				queueLen = queueLen + 1
				queueBag[queueLen], queueSlot[queueLen] = bag, slot
			end
		end
	end
	return queueLen
end

local function SellJunk()
	if selling then
		return
	end
	moneyBefore = Money()
	itemsSold = 0

	-- Preferred: Blizzard's own bulk sell, which handles everything server side.
	if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems and Ask(C_MerchantFrame.IsSellAllJunkEnabled) then
		local numJunk
		if C_MerchantFrame.GetNumJunkItems then
			numJunk = Num(Ask(C_MerchantFrame.GetNumJunkItems)) or 0
		else
			numJunk = CollectJunk()
		end
		if numJunk > 0 then
			selling, bulkSale = true, true
			itemsSold = numJunk
			C_MerchantFrame.SellAllJunkItems()
			FinishLater(1.0)
		end
		return
	end

	-- Fallback: sell item by item in small batches.
	if CollectJunk() == 0 then
		return
	end
	selling, bulkSale = true, false
	SellNextBatch()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, event)
	if event == "MERCHANT_SHOW" then
		if M.db.autoRepair then
			Repair()
		end
		if M.db.autoSell then
			SellJunk()
		end
	elseif event == "MERCHANT_CLOSED" then
		if selling then
			FinishSelling()
		end
	end
end)

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	eventFrame:RegisterEvent("MERCHANT_SHOW")
	eventFrame:RegisterEvent("MERCHANT_CLOSED")
end

function M:OnDisable()
	eventFrame:UnregisterEvent("MERCHANT_SHOW")
	eventFrame:UnregisterEvent("MERCHANT_CLOSED")
	if selling then
		FinishSelling()
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
end

MelloUI:Profile("Vendor", "merchant events", eventFrame)
