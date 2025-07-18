-- MelloUI Enhanced Bags Module
local addonName, ns = ...
local EnhancedBags = {}

-- Create a hidden tooltip for scanning
local scanTooltip = CreateFrame("GameTooltip", "MelloUIEnhancedBagsScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local defaultSettings = {
    showItemLevel = true,
    showVendorPrice = false,
    highlightQuality = false,
    autoVendorJunk = true,
    autoLoot = true,
    debugMode = false,
}

local function GetItemQualityColor(quality)
    if quality == 0 then return 0.62, 0.62, 0.62 end  -- Gray (Poor)
    if quality == 1 then return 1, 1, 1 end           -- White (Common)
    if quality == 2 then return 0.12, 1, 0 end        -- Green (Uncommon)
    if quality == 3 then return 0, 0.44, 0.87 end     -- Blue (Rare)
    if quality == 4 then return 0.64, 0.21, 0.93 end  -- Purple (Epic)
    if quality == 5 then return 1, 0.5, 0 end         -- Orange (Legendary)
    if quality == 6 then return 0.9, 0.8, 0.5 end     -- Light Gold (Artifact)
    if quality == 7 then return 0, 0.8, 1 end         -- Light Blue (Heirloom)
    return 1, 1, 1
end

-- Function to get the real item level from an item in a bag
local function GetRealItemLevel(bag, slot)
    local itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
    
    if not itemLocation or not itemLocation:IsValid() then
        return nil
    end
    
    -- Method 1: Try the direct API
    local itemLevel = C_Item.GetCurrentItemLevel(itemLocation)
    if itemLevel and itemLevel > 0 then
        return itemLevel
    end
    
    -- Method 2: Get from item link
    local itemLink = C_Item.GetItemLink(itemLocation)
    if itemLink then
        -- GetDetailedItemLevelInfo should return the actual item level including upgrades
        itemLevel = GetDetailedItemLevelInfo(itemLink)
        if itemLevel and itemLevel > 0 then
            return itemLevel
        end
    end
    
    -- Method 3: Fallback to basic item info
    local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
    if itemInfo and itemInfo.hyperlink then
        local _, _, _, baseLevel = C_Item.GetItemInfo(itemInfo.hyperlink)
        return baseLevel
    end
    
    return nil
end

-- Alternative method using item stats
local function GetItemLevelFromStats(itemLink)
    if not itemLink then return nil end
    
    local stats = C_Item.GetItemStats(itemLink)
    if stats and stats["ITEM_LEVEL"] then
        return stats["ITEM_LEVEL"]
    end
    
    return nil
end

local function GetContainerItemInfo(bag, slot)
    local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
    if not itemInfo then return nil end
    
    local itemID = itemInfo.itemID
    if not itemID then return nil end
    
    -- Use the hyperlink to get item info
    local itemLink = itemInfo.hyperlink
    if not itemLink then return nil end
    
    local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType, _, _, _, vendorPrice, classID, subClassID = C_Item.GetItemInfo(itemLink)
    
    return {
        texture = itemInfo.iconFileID,
        count = itemInfo.stackCount,
        locked = itemInfo.isLocked,
        quality = itemInfo.quality or itemQuality or 1,
        itemLink = itemLink,
        itemName = itemName,
        itemLevel = itemLevel,
        vendorPrice = vendorPrice,
        classID = classID,
        subClassID = subClassID,
        itemType = itemType,
        itemSubType = itemSubType,
        itemID = itemID,
        bagID = bag,
        slotID = slot
    }
end

local function EnhanceBagSlot(button, bag, slot)
    if not button then return end
    
    local itemInfo = GetContainerItemInfo(bag, slot)
    if not itemInfo then
        if button.ebItemLevel then button.ebItemLevel:Hide() end
        if button.ebItemLevelBG then button.ebItemLevelBG:Hide() end
        if button.ebVendorPrice then button.ebVendorPrice:Hide() end
        if button.ebQualityBorder then button.ebQualityBorder:Hide() end
        if button.ebGoldIcon then button.ebGoldIcon:Hide() end
        local iconTexture = button.icon or button.Icon or _G[button:GetName().."IconTexture"]
        if iconTexture then iconTexture:SetDesaturated(false) end
        return
    end
    
    -- Handle junk items (quality 0 = gray/poor quality)
    if itemInfo.quality == 0 then
        -- Find the icon texture - it might be button.icon or button.Icon
        local iconTexture = button.icon or button.Icon or _G[button:GetName().."IconTexture"]
        
        if iconTexture then
            iconTexture:SetDesaturated(true)
        end
        
        -- Add gold coin icon in top-left corner
        if not button.ebGoldIcon then
            button.ebGoldIcon = button:CreateTexture(nil, "OVERLAY")
            button.ebGoldIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
            button.ebGoldIcon:SetSize(16, 16)
            button.ebGoldIcon:SetPoint("TOPLEFT", 2, -2)
            button.ebGoldIcon:SetDrawLayer("OVERLAY", 7)
        end
        button.ebGoldIcon:Show()
    else
        -- Find the icon texture
        local iconTexture = button.icon or button.Icon or _G[button:GetName().."IconTexture"]
        if iconTexture then
            iconTexture:SetDesaturated(false)
        end
        if button.ebGoldIcon then
            button.ebGoldIcon:Hide()
        end
    end
    
    -- Show item level only for equipment items (armor, weapons, accessories)
    if mmEnhancedBagsDB.showItemLevel and itemInfo.itemLink then
        -- Check if item is equipment (classID 2 = Armor, 4 = Jewelry/Accessories)
        -- Also check for weapons which have various subclass IDs
        local isEquipment = false
        
        if itemInfo.classID == 2 then
            -- Armor (includes all armor types)
            isEquipment = true
        elseif itemInfo.classID == 4 then
            -- Armor subcategory (includes backs, necklaces, rings, trinkets)
            isEquipment = true
        elseif itemInfo.itemType then
            -- Check for weapon types by name
            local itemType = itemInfo.itemType:lower()
            if itemType:find("weapon") or itemType:find("shield") or itemType:find("offhand") then
                isEquipment = true
            end
        end
        
        if isEquipment then
            -- Use GetDetailedItemLevelInfo like EnhancedCharacterFrame does
            local actualItemLevel = nil
            if itemInfo.itemLink then
                actualItemLevel = GetDetailedItemLevelInfo(itemInfo.itemLink)
            end
            
            -- Fallback to our other methods if needed
            if not actualItemLevel or actualItemLevel == 0 then
                actualItemLevel = GetRealItemLevel(bag, slot)
            end
            
            -- Try stats-based method as second fallback
            if not actualItemLevel or actualItemLevel == 0 then
                actualItemLevel = GetItemLevelFromStats(itemInfo.itemLink)
            end
            
            if actualItemLevel and actualItemLevel > 1 then
                if not button.ebItemLevel then
                    button.ebItemLevel = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    button.ebItemLevel:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
                    button.ebItemLevel:SetJustifyH("CENTER")
                    
                    -- Create background like EnhancedCharacterFrame
                    button.ebItemLevelBG = button:CreateTexture(nil, "ARTWORK")
                    button.ebItemLevelBG:SetColorTexture(0, 0, 0, 0.75)
                    button.ebItemLevelBG:SetHeight(16)
                    button.ebItemLevelBG:SetWidth(32)
                    button.ebItemLevelBG:SetPoint("CENTER", button.ebItemLevel, "CENTER", 0, 0)
                end
                button.ebItemLevel:SetText(actualItemLevel)
                
                -- Color based on item quality
                local itemQuality = itemInfo.quality or 1
                local r, g, b = GetItemQualityColor(itemQuality)
                button.ebItemLevel:SetTextColor(r, g, b)
                
                button.ebItemLevel:Show()
                button.ebItemLevelBG:Show()
            elseif button.ebItemLevel then
                button.ebItemLevel:Hide()
                if button.ebItemLevelBG then
                    button.ebItemLevelBG:Hide()
                end
            end
        elseif button.ebItemLevel then
            button.ebItemLevel:Hide()
            if button.ebItemLevelBG then
                button.ebItemLevelBG:Hide()
            end
        end
    elseif button.ebItemLevel then
        button.ebItemLevel:Hide()
        if button.ebItemLevelBG then
            button.ebItemLevelBG:Hide()
        end
    end
    
    -- Hide vendor price display
    if button.ebVendorPrice then
        button.ebVendorPrice:Hide()
    end
    
    -- Hide quality border glow
    if button.ebQualityBorder then
        button.ebQualityBorder:Hide()
    end
end

local function UpdateBags()
    -- Check for combined bags frame
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        -- Update combined bags items
        for _, itemButton in ContainerFrameCombinedBags:EnumerateItems() do
            if itemButton then
                local bag = itemButton:GetBagID()
                local slot = itemButton:GetID()
                if bag and slot then
                    EnhanceBagSlot(itemButton, bag, slot)
                end
            end
        end
    end
    
    -- Check individual bag frames
    for i = 1, 12 do
        local frameName = "ContainerFrame" .. i
        local frame = _G[frameName]
        if frame and frame:IsShown() then
            local id = frame:GetID()
            local size = C_Container.GetContainerNumSlots(id)
            
            for j = 1, size do
                local button = _G[frameName .. "Item" .. j]
                if button then
                    EnhanceBagSlot(button, id, j)
                end
            end
        end
    end
end

local function AutoVendorJunk()
    if not mmEnhancedBagsDB.autoVendorJunk then return end
    
    local totalValue = 0
    local itemsSold = 0
    
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo and itemInfo.quality == 0 and not itemInfo.isLocked then
                local itemLink = itemInfo.hyperlink
                local vendorPrice = select(11, C_Item.GetItemInfo(itemInfo.itemID))
                
                if vendorPrice and vendorPrice > 0 then
                    C_Container.UseContainerItem(bag, slot)
                    totalValue = totalValue + (vendorPrice * itemInfo.stackCount)
                    itemsSold = itemsSold + 1
                end
            end
        end
    end
    
    if itemsSold > 0 then
        local gold = floor(totalValue / 10000)
        local silver = floor((totalValue % 10000) / 100)
        local copper = totalValue % 100
        
        local moneyString = ""
        if gold > 0 then moneyString = gold .. "g " end
        if silver > 0 then moneyString = moneyString .. silver .. "s " end
        if copper > 0 then moneyString = moneyString .. copper .. "c" end
        
        print(string.format("|cff00ff00MelloUI Enhanced Bags:|r Sold %d junk items for %s", itemsSold, moneyString))
    end
end

function EnhancedBags:SetupHooks()
    -- Hook the combined bags if it exists
    if ContainerFrameCombinedBags then
        hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", function(self)
            C_Timer.After(0.1, function()
                UpdateBags()
            end)
        end)
    end
    
    -- Hook individual bag frames when they're shown
    for i = 1, 13 do
        local frameName = "ContainerFrame" .. i
        local frame = _G[frameName]
        if frame then
            frame:HookScript("OnShow", function(self)
                C_Timer.After(0.1, function()
                    UpdateBags()
                end)
            end)
            
            -- Try to hook UpdateItems if it exists
            if frame.UpdateItems then
                hooksecurefunc(frame, "UpdateItems", function(self)
                    C_Timer.After(0.1, function()
                        UpdateBags()
                    end)
                end)
            end
        end
    end
    
    -- Use a ticker for periodic updates
    self.updateTicker = C_Timer.NewTicker(0.5, function()
        if not InCombatLockdown() then
            UpdateBags()
        end
    end)
end

function EnhancedBags:OnInitialize()
    mmEnhancedBagsDB = mmEnhancedBagsDB or {}
    for k, v in pairs(defaultSettings) do
        if mmEnhancedBagsDB[k] == nil then
            mmEnhancedBagsDB[k] = v
        end
    end
    
    -- Apply auto loot setting
    if mmEnhancedBagsDB.autoLoot ~= nil then
        SetCVar("autoLootDefault", mmEnhancedBagsDB.autoLoot and "1" or "0")
    end
    
    -- Set up hooks
    self:SetupHooks()
    
    -- Event frame
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("BAG_UPDATE")
    self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    self.eventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
    self.eventFrame:RegisterEvent("MERCHANT_SHOW")
    self.eventFrame:RegisterEvent("BAG_OPEN")
    self.eventFrame:RegisterEvent("BAG_CLOSED")
    self.eventFrame:RegisterEvent("BAG_CONTAINER_UPDATE")
    
    self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
        if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
            C_Timer.After(0.1, function()
                UpdateBags()
            end)
        elseif event == "ITEM_LOCK_CHANGED" then
            UpdateBags()
        elseif event == "BAG_OPEN" or event == "BAG_CLOSED" or event == "BAG_CONTAINER_UPDATE" then
            C_Timer.After(0.1, function()
                UpdateBags()
            end)
        elseif event == "MERCHANT_SHOW" then
            C_Timer.After(0.1, function()
                AutoVendorJunk()
            end)
        end
    end)
    
    -- Slash commands
    SLASH_MELLOUIENHANCEDBAGS1 = "/meb"
    SLASH_MELLOUIENHANCEDBAGS2 = "/menhancedbags"
    SlashCmdList["MELLOUIENHANCEDBAGS"] = function(msg)
        if msg == "debug" then
            mmEnhancedBagsDB.debugMode = not mmEnhancedBagsDB.debugMode
            print("|cff00ff00MelloUI Enhanced Bags:|r Debug mode", mmEnhancedBagsDB.debugMode and "enabled" or "disabled")
        elseif msg == "refresh" then
            print("|cff00ff00MelloUI Enhanced Bags:|r Manually refreshing bags...")
            UpdateBags()
        else
            print("|cff00ff00MelloUI Enhanced Bags:|r Commands:")
            print("  /meb debug - Toggle debug mode")
            print("  /meb refresh - Manually refresh bags")
        end
    end
end

function EnhancedBags:OnEnable()
    -- Ensure DB is initialized (in case module is enabled after initial load)
    mmEnhancedBagsDB = mmEnhancedBagsDB or {}
    for k, v in pairs(defaultSettings) do
        if mmEnhancedBagsDB[k] == nil then
            mmEnhancedBagsDB[k] = v
        end
    end
    
    -- Module enabled
    if self.eventFrame then
        self.eventFrame:RegisterEvent("BAG_UPDATE")
        self.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        self.eventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
        self.eventFrame:RegisterEvent("MERCHANT_SHOW")
        self.eventFrame:RegisterEvent("BAG_OPEN")
        self.eventFrame:RegisterEvent("BAG_CLOSED")
        self.eventFrame:RegisterEvent("BAG_CONTAINER_UPDATE")
    end
    UpdateBags()
end

function EnhancedBags:OnDisable()
    -- Module disabled
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    if self.updateTicker then
        self.updateTicker:Cancel()
        self.updateTicker = nil
    end
end

-- Register the module
ns:RegisterModule("EnhancedBags", EnhancedBags)