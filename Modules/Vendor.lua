--------------------------------------------------------------------------------
-- MelloUI - Vendor
--
-- Automatically repairs all gear and sells grey (junk) items whenever a
-- merchant window is opened.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("Vendor", {
	title = "Vendor",
	desc = "Automatically repair your gear and sell junk items when visiting a merchant.",
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
		  desc = "Print the repair cost and the gold gained from selling junk." },
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

local POOR_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

--------------------------------------------------------------------------------
-- Repair
--------------------------------------------------------------------------------

local function Repair()
	if not CanMerchantRepair or not CanMerchantRepair() then
		return
	end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then
		return
	end

	if M.db.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
		local guildFunds = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or -1
		if guildFunds == -1 or guildFunds >= cost then
			RepairAllItems(true)
			Report("Repaired for %s (guild funds).", CoinText(cost))
			return
		end
	end

	if GetMoney() >= cost then
		RepairAllItems(false)
		Report("Repaired for %s.", CoinText(cost))
	else
		Report("|cffff4040Not enough gold to repair|r (%s needed).", CoinText(cost))
	end
end

--------------------------------------------------------------------------------
-- Junk selling
--------------------------------------------------------------------------------

local selling = false
local sellQueue = {}
local moneyBefore = 0
local itemsSold = 0

local function FinishSelling()
	selling = false
	sellQueue = {}
	local gained = GetMoney() - moneyBefore
	if itemsSold > 0 then
		if gained > 0 then
			Report("Sold %d junk item%s for %s.", itemsSold, itemsSold == 1 and "" or "s", CoinText(gained))
		else
			Report("Sold %d junk item%s.", itemsSold, itemsSold == 1 and "" or "s")
		end
	end
	itemsSold = 0
end

local SELL_BATCH = 6
local SELL_DELAY = 0.25

local function SellNextBatch()
	if not selling then
		return
	end
	if not MerchantFrame or not MerchantFrame:IsShown() then
		FinishSelling()
		return
	end
	local count = 0
	while #sellQueue > 0 and count < SELL_BATCH do
		local entry = table.remove(sellQueue, 1)
		local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
		if info and info.quality == POOR_QUALITY and not info.hasNoValue and not info.isLocked then
			C_Container.UseContainerItem(entry.bag, entry.slot)
			itemsSold = itemsSold + 1
			count = count + 1
		end
	end
	if #sellQueue > 0 then
		C_Timer.After(SELL_DELAY, SellNextBatch)
	else
		-- Give the server a moment to deliver the gold before reporting.
		C_Timer.After(0.5, FinishSelling)
	end
end

local function CollectJunk()
	local queue = {}
	local lastBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
	for bag = 0, lastBag do
		local numSlots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == POOR_QUALITY and not info.hasNoValue and not info.isLocked then
				queue[#queue + 1] = { bag = bag, slot = slot }
			end
		end
	end
	return queue
end

local function SellJunk()
	if selling then
		return
	end
	moneyBefore = GetMoney()
	itemsSold = 0

	-- Preferred: Blizzard's own bulk sell, which handles everything server side.
	if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems and C_MerchantFrame.IsSellAllJunkEnabled
	   and C_MerchantFrame.IsSellAllJunkEnabled() then
		local numJunk = C_MerchantFrame.GetNumJunkItems and C_MerchantFrame.GetNumJunkItems() or #CollectJunk()
		if numJunk > 0 then
			selling = true
			itemsSold = numJunk
			C_MerchantFrame.SellAllJunkItems()
			C_Timer.After(1.0, FinishSelling)
		end
		return
	end

	-- Fallback: sell item by item in small batches.
	sellQueue = CollectJunk()
	if #sellQueue == 0 then
		return
	end
	selling = true
	SellNextBatch()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
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
