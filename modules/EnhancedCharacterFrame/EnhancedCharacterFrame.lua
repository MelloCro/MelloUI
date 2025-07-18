-- MelloUI Enhanced Character Frame Module
local addonName, ns = ...
local EnhancedCharacterFrame = {}

local SLOT_NAMES = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "MainHandSlot", "SecondaryHandSlot"
}

local ITEM_QUALITY_COLORS = {
    [0] = {0.5, 0.5, 0.5},    -- Poor (gray)
    [1] = {1, 1, 1},          -- Common (white)
    [2] = {0.12, 1, 0},       -- Uncommon (green)
    [3] = {0, 0.44, 0.87},    -- Rare (blue)
    [4] = {0.64, 0.21, 0.93}, -- Epic (purple)
    [5] = {1, 0.5, 0},        -- Legendary (orange)
    [6] = {0.9, 0.8, 0.5},    -- Artifact (light gold)
    [7] = {0, 0.8, 1},        -- Heirloom (light blue)
    [8] = {0, 0.8, 1},        -- WoW Token (light blue)
}

local function CreateItemLevelDisplay()
    if not CharacterFrame then return end
    
    for _, slotName in ipairs(SLOT_NAMES) do
        local slot = _G["Character"..slotName]
        if slot then
            if not slot.itemLevelText then
                slot.itemLevelText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                slot.itemLevelText:SetPoint("BOTTOM", slot, "BOTTOM", 0, 2)
                slot.itemLevelText:SetJustifyH("CENTER")
                
                slot.itemLevelBG = slot:CreateTexture(nil, "ARTWORK")
                slot.itemLevelBG:SetColorTexture(0, 0, 0, 0.75)
                slot.itemLevelBG:SetHeight(16)
                slot.itemLevelBG:SetWidth(32)
                slot.itemLevelBG:SetPoint("CENTER", slot.itemLevelText, "CENTER", 0, 0)
                slot.itemLevelBG:Hide()
            end
        end
    end
end

local function UpdateItemLevels()
    local playerLevel = UnitLevel("player")
    local totalItemLevel = 0
    local itemCount = 0
    
    for _, slotName in ipairs(SLOT_NAMES) do
        local slot = _G["Character"..slotName]
        if slot then
            local slotId = GetInventorySlotInfo(slotName)
            local itemLink = GetInventoryItemLink("player", slotId)
            
            if itemLink then
                local itemLevel = GetDetailedItemLevelInfo(itemLink)
                if itemLevel and itemLevel > 0 then
                    totalItemLevel = totalItemLevel + itemLevel
                    itemCount = itemCount + 1
                    
                    if slot.itemLevelText then
                        slot.itemLevelText:SetText(itemLevel)
                        
                        -- Get item quality for color
                        local _, _, itemQuality = GetItemInfo(itemLink)
                        local r, g, b = 0.5, 0.5, 0.5
                        if itemQuality and ITEM_QUALITY_COLORS[itemQuality] then
                            r, g, b = unpack(ITEM_QUALITY_COLORS[itemQuality])
                        end
                        
                        slot.itemLevelText:SetTextColor(r, g, b)
                        slot.itemLevelText:Show()
                        
                        if slot.itemLevelBG then
                            slot.itemLevelBG:Show()
                        end
                    end
                end
            else
                if slot.itemLevelText then
                    slot.itemLevelText:Hide()
                end
                if slot.itemLevelBG then
                    slot.itemLevelBG:Hide()
                end
            end
        end
    end
    
    return itemCount > 0 and math.floor(totalItemLevel / itemCount) or 0
end

local function GetMythicPlusRatingColor(rating)
    if not rating or rating == 0 then
        return 0.5, 0.5, 0.5
    elseif rating < 1000 then
        return 0.6, 0.6, 0.6
    elseif rating < 1500 then
        return 0.1, 1, 0
    elseif rating < 2000 then
        return 0, 0.5, 1
    elseif rating < 2500 then
        return 0.5, 0, 1
    elseif rating < 3000 then
        return 1, 0.5, 0
    else
        return 1, 0.84, 0
    end
end

local function CreateMythicPlusDisplay()
    if not CharacterFrame then return end
    
    local mpDisplay = CreateFrame("Frame", "ECFMythicPlusDisplay", CharacterFrame)
    mpDisplay:SetSize(140, 21)
    mpDisplay:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", -5, 8)
    mpDisplay:SetFrameStrata("HIGH")
    
    mpDisplay.text = mpDisplay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mpDisplay.text:SetPoint("CENTER", mpDisplay, "CENTER", 0, 0)
    
    return mpDisplay
end

local function UpdateMythicPlusDisplay()
    if not EnhancedCharacterFrame.mpDisplay then return end
    
    local rating = 0
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        rating = C_ChallengeMode.GetOverallDungeonScore() or 0
    end
    
    if rating and rating > 0 then
        local r, g, b = GetMythicPlusRatingColor(rating)
        EnhancedCharacterFrame.mpDisplay.text:SetText(string.format("M+ Rating: |cff%02x%02x%02x%d|r", r*255, g*255, b*255, rating))
    else
        EnhancedCharacterFrame.mpDisplay.text:SetText("M+ Rating: |cff808080None|r")
    end
    
    -- Only show if we're on the character tab
    if PaperDollFrame and PaperDollFrame:IsShown() then
        EnhancedCharacterFrame.mpDisplay:Show()
    else
        EnhancedCharacterFrame.mpDisplay:Hide()
    end
end

local function SetupTabHooks()
    if not CharacterFrame then return end
    
    -- Hook the character tab
    if CharacterFrameTab1 then
        CharacterFrameTab1:HookScript("OnClick", function()
            if EnhancedCharacterFrame.mpDisplay then
                EnhancedCharacterFrame.mpDisplay:Show()
            end
        end)
    end
    
    -- Hook the other tabs to hide the display
    for i = 2, 5 do
        local tab = _G["CharacterFrameTab"..i]
        if tab then
            tab:HookScript("OnClick", function()
                if EnhancedCharacterFrame.mpDisplay then
                    EnhancedCharacterFrame.mpDisplay:Hide()
                end
            end)
        end
    end
end

function EnhancedCharacterFrame:SetupCharacterFrame()
    if not CharacterFrame then return end
    
    CreateItemLevelDisplay()
    self.mpDisplay = CreateMythicPlusDisplay()
    SetupTabHooks()
    
    CharacterFrame:HookScript("OnShow", function()
        UpdateItemLevels()
        UpdateMythicPlusDisplay()
    end)
    
    if CharacterFrame:IsShown() then
        UpdateItemLevels()
        UpdateMythicPlusDisplay()
    end
end

function EnhancedCharacterFrame:OnInitialize()
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    
    self.eventFrame:SetScript("OnEvent", function(frame, event, arg1)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_CharacterUI" then
            EnhancedCharacterFrame:SetupCharacterFrame()
        elseif event == "PLAYER_ENTERING_WORLD" then
            if not EnhancedCharacterFrame.initialized and CharacterFrame then
                EnhancedCharacterFrame:SetupCharacterFrame()
                EnhancedCharacterFrame.initialized = true
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            if CharacterFrame and CharacterFrame:IsShown() then
                UpdateItemLevels()
            end
        end
    end)
end

function EnhancedCharacterFrame:OnEnable()
    -- Module enabled
end

function EnhancedCharacterFrame:OnDisable()
    -- Module disabled
    if self.mpDisplay then
        self.mpDisplay:Hide()
    end
end

-- Register the module
ns:RegisterModule("EnhancedCharacterFrame", EnhancedCharacterFrame)