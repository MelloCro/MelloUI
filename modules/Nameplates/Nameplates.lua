-- MelloUI Nameplates Module
local addonName, ns = ...
local Nameplates = {}

-- Store references for cleanup
local mainTicker = nil
local fontUpdateTimer = nil
local pendingFontUpdates = {}

-- These defaults represent the current preferred settings for mNameplates
local defaults = {
    width = 120,
    height = 12,
    texture = "Interface\\Buttons\\WHITE8X8", -- Solid
    castbarTexture = "Interface\\Buttons\\WHITE8X8", -- Solid
    backgroundTexture = "Interface\\Buttons\\WHITE8X8", -- Solid
    showCastbar = true,
    castbarHeight = 10,
    hideTargetHighlight = true,
    enableCastbarColors = true,
    interruptibleColor = {r = 1.0, g = 0.7, b = 0.0}, -- Yellow/Orange
    nonInterruptibleColor = {r = 0.7, g = 0.7, b = 0.7}, -- Gray
    castbarNameFontSize = 7,
    enableTankThreatColors = true,
    tankHasThreatColor = {r = 0.0, g = 1.0, b = 0.0}, -- Green
    tankNoThreatColor = {r = 1.0, g = 0.0, b = 0.0}, -- Red
    alwaysShowNameplates = true,
    hideFriendlyNameplates = true,
    nameplateMaxDistance = 51,
    nameplateOverlapH = 0.7,
    nameplateOverlapV = 0.7
}

local textures = {
    ["Blizzard Default"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Solid"] = "Interface\\Buttons\\WHITE8X8",
    ["Aluminium"] = "Interface\\AddOns\\MelloUI\\modules\\Nameplates\\Textures\\Aluminium",
    ["BantoBar"] = "Interface\\AddOns\\MelloUI\\modules\\Nameplates\\Textures\\BantoBar",
    ["Smooth"] = "Interface\\AddOns\\MelloUI\\modules\\Nameplates\\Textures\\Smooth",
    ["Perl"] = "Interface\\AddOns\\MelloUI\\modules\\Nameplates\\Textures\\Perl",
    ["Gloss"] = "Interface\\AddOns\\MelloUI\\modules\\Nameplates\\Textures\\Gloss",
    ["Charcoal"] = "Interface\\AddOns\\MelloUI\\modules\\Nameplates\\Textures\\Charcoal",
    ["Minimalist"] = "Interface\\AddOns\\MelloUI\\modules\\Nameplates\\Textures\\Minimalist",
}

-- Function to check if player is tank spec
local function IsPlayerTank()
    local spec = GetSpecialization()
    if not spec then return false end
    
    local role = GetSpecializationRole(spec)
    return role == "TANK"
end

-- Batch update function for castbar fonts
local function UpdatePendingFontChanges()
    for castBar in pairs(pendingFontUpdates) do
        if castBar and castBar:IsVisible() then
            -- Find all font strings on the castbar
            local regions = {castBar:GetRegions()}
            for _, region in ipairs(regions) do
                if region:GetObjectType() == "FontString" then
                    local font, size, flags = region:GetFont()
                    if font then
                        -- Check if this is the spell name or time display
                        local text = region:GetText()
                        if text and text:len() > 0 then
                            region:SetFont(font, mNameplatesDB.castbarNameFontSize, flags)
                        end
                    end
                end
            end
        end
        pendingFontUpdates[castBar] = nil
    end
    fontUpdateTimer = nil
end

-- Function to set nameplate CVars based on our width/height
local function UpdateNameplateCVars()
    -- Calculate scale based on width (default is ~110-120)
    local widthScale = mNameplatesDB.width / 110
    
    -- Handle always show nameplates setting
    if mNameplatesDB.alwaysShowNameplates then
        SetCVar("nameplateShowEnemies", 1)
        SetCVar("nameplateShowEnemyMinions", 1)
        SetCVar("nameplateShowEnemyMinus", 1)
        SetCVar("nameplateShowAll", 1)
    end
    
    -- Handle hide friendly nameplates setting
    if mNameplatesDB.hideFriendlyNameplates then
        SetCVar("nameplateShowFriends", 0)
    else
        SetCVar("nameplateShowFriends", 1)
    end
    
    -- These CVars affect nameplate sizing
    SetCVar("nameplateGlobalScale", widthScale)
    SetCVar("nameplateSelectedScale", widthScale)
    SetCVar("nameplateLargerScale", widthScale)
    SetCVar("nameplateMinScale", 0.8)
    SetCVar("nameplateMaxScale", 1.0)
    
    -- Set nameplate height through vertical scale
    local heightScale = mNameplatesDB.height / 12
    SetCVar("nameplateOtherTopInset", -0.1)
    SetCVar("nameplateOtherBottomInset", -0.1)
    SetCVar("nameplateLargeTopInset", -0.1)
    SetCVar("nameplateLargeBottomInset", -0.1)
    
    -- Force nameplate updates
    SetCVar("nameplateMotion", GetCVar("nameplateMotion"))
    
    -- Set distance and overlap CVars
    SetCVar("nameplateMaxDistance", mNameplatesDB.nameplateMaxDistance)
    SetCVar("nameplateOverlapH", mNameplatesDB.nameplateOverlapH)
    SetCVar("nameplateOverlapV", mNameplatesDB.nameplateOverlapV)
end

local function UpdateNameplateThreatColor(unitFrame, unit)
    if not unitFrame or not unitFrame.healthBar or not unit then return end
    
    -- Skip player nameplates (both enemy and friendly)
    if UnitIsPlayer(unit) then
        if unitFrame.healthBar then
            unitFrame.healthBar.customThreatColor = false
        end
        return
    end
    
    -- Only apply tank threat colors if enabled and player is a tank
    if mNameplatesDB.enableTankThreatColors and IsPlayerTank() then
        local isTanking = UnitIsUnit(unit.."target", "player")
        
        -- Mark that we're using custom colors to prevent flickering
        unitFrame.healthBar.customThreatColor = true
        
        if isTanking then
            -- Tank has threat - use green color
            unitFrame.healthBar:SetStatusBarColor(
                mNameplatesDB.tankHasThreatColor.r,
                mNameplatesDB.tankHasThreatColor.g,
                mNameplatesDB.tankHasThreatColor.b
            )
        else
            -- Tank doesn't have threat - use red color
            unitFrame.healthBar:SetStatusBarColor(
                mNameplatesDB.tankNoThreatColor.r,
                mNameplatesDB.tankNoThreatColor.g,
                mNameplatesDB.tankNoThreatColor.b
            )
        end
    else
        -- Clear the custom color flag when threat colors are disabled
        if unitFrame.healthBar then
            unitFrame.healthBar.customThreatColor = false
        end
    end
end

local function ApplyTextureToNameplate(nameplate)
    if not nameplate or not nameplate.UnitFrame then return end
    
    local unitFrame = nameplate.UnitFrame
    
    -- Apply texture to health bar
    if unitFrame.healthBar then
        unitFrame.healthBar:SetStatusBarTexture(mNameplatesDB.texture)
        
        if unitFrame.healthBar.background then
            unitFrame.healthBar.background:SetTexture(mNameplatesDB.backgroundTexture)
            unitFrame.healthBar.background:SetVertexColor(0.1, 0.1, 0.1, 0.8)
        end
    end
    
    -- Apply texture to cast bar
    if unitFrame.castBar then
        -- Always apply textures, but don't force show/hide
        unitFrame.castBar:SetStatusBarTexture(mNameplatesDB.castbarTexture)
        
        -- Set castbar height
        unitFrame.castBar:SetHeight(mNameplatesDB.castbarHeight)
        
        -- Apply background texture to castbar
        if unitFrame.castBar.Background then
            unitFrame.castBar.Background:SetTexture(mNameplatesDB.backgroundTexture)
            unitFrame.castBar.Background:SetVertexColor(0.1, 0.1, 0.1, 0.8)
        end
        
        -- Apply to cast bar border/background
        if unitFrame.castBar.Border then
            unitFrame.castBar.Border:SetAlpha(1)
        end
        
        -- Mark castbar for font update instead of creating timer immediately
        if unitFrame.castBar then
            pendingFontUpdates[unitFrame.castBar] = true
            if not fontUpdateTimer then
                fontUpdateTimer = C_Timer.After(0.01, UpdatePendingFontChanges)
            end
        end
    end
    
    -- Apply texture to power bar if exists
    if unitFrame.PowerBar then
        unitFrame.PowerBar:SetStatusBarTexture(mNameplatesDB.texture)
        
        if unitFrame.PowerBar.Background then
            unitFrame.PowerBar.Background:SetTexture(mNameplatesDB.backgroundTexture)
            unitFrame.PowerBar.Background:SetVertexColor(0.1, 0.1, 0.1, 0.8)
        end
    end
    
    -- Hide target highlight if enabled
    if mNameplatesDB.hideTargetHighlight then
        if unitFrame.selectionHighlight then
            unitFrame.selectionHighlight:SetAlpha(0)
        end
        if unitFrame.aggroHighlight then
            unitFrame.aggroHighlight:SetAlpha(0)
        end
    else
        if unitFrame.selectionHighlight then
            unitFrame.selectionHighlight:SetAlpha(1)
        end
        if unitFrame.aggroHighlight then
            unitFrame.aggroHighlight:SetAlpha(1)
        end
    end
end

local function OnNamePlateAdded(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate then
        ApplyTextureToNameplate(nameplate)
        -- Apply threat colors immediately if enabled
        if mNameplatesDB.enableTankThreatColors and IsPlayerTank() then
            UpdateNameplateThreatColor(nameplate.UnitFrame, unit)
        end
    end
end

local function RefreshAllNameplates()
    -- Update CVars first
    UpdateNameplateCVars()
    
    -- Then update textures and threat colors
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        ApplyTextureToNameplate(nameplate)
        -- Apply threat colors if enabled
        if nameplate.UnitFrame and nameplate.UnitFrame.unit and mNameplatesDB.enableTankThreatColors and IsPlayerTank() then
            UpdateNameplateThreatColor(nameplate.UnitFrame, nameplate.UnitFrame.unit)
        end
    end
    
    -- Force a nameplate refresh by toggling them
    local nameplateShowAll = GetCVar("nameplateShowAll")
    SetCVar("nameplateShowAll", nameplateShowAll == "1" and "0" or "1")
    C_Timer.After(0.1, function()
        SetCVar("nameplateShowAll", nameplateShowAll)
    end)
end

function Nameplates:SetupHooks()
    -- Hook nameplate texture updates
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        if frame.healthBar and frame:IsForbidden() == false then
            -- Apply texture immediately
            frame.healthBar:SetStatusBarTexture(mNameplatesDB.texture)
            
            -- Update threat colors if enabled (do this immediately to prevent flickering)
            if frame.unit and mNameplatesDB.enableTankThreatColors and IsPlayerTank() then
                UpdateNameplateThreatColor(frame, frame.unit)
            end
        end
    end)
    
    -- Hook the nameplate visibility functions to override them
    if mNameplatesDB.alwaysShowNameplates then
        hooksecurefunc("SetCVar", function(cvar, value)
            if mNameplatesDB.alwaysShowNameplates and not InCombatLockdown() then
                if cvar == "nameplateShowEnemies" and value ~= "1" then
                    C_Timer.After(0.1, function() 
                        if not InCombatLockdown() then
                            SetCVar("nameplateShowEnemies", 1) 
                        end
                    end)
                elseif cvar == "nameplateShowEnemyMinions" and value ~= "1" then
                    C_Timer.After(0.1, function() 
                        if not InCombatLockdown() then
                            SetCVar("nameplateShowEnemyMinions", 1) 
                        end
                    end)
                elseif cvar == "nameplateShowEnemyMinus" and value ~= "1" then
                    C_Timer.After(0.1, function() 
                        if not InCombatLockdown() then
                            SetCVar("nameplateShowEnemyMinus", 1) 
                        end
                    end)
                elseif cvar == "nameplateShowAll" and value ~= "1" then
                    C_Timer.After(0.1, function() 
                        if not InCombatLockdown() then
                            SetCVar("nameplateShowAll", 1) 
                        end
                    end)
                end
            end
        end)
    end
    
    -- Additional hook to maintain our custom colors
    hooksecurefunc("CompactUnitFrame_UpdateHealth", function(frame)
        if frame.healthBar and frame.healthBar.customThreatColor and frame.unit and mNameplatesDB.enableTankThreatColors and IsPlayerTank() then
            -- Reapply threat color to prevent it being overwritten
            UpdateNameplateThreatColor(frame, frame.unit)
        end
    end)
    
    -- Hook nameplate creation to setup castbar hooks
    hooksecurefunc("DefaultCompactNamePlateFrameSetup", function(frame)
        if frame and frame.castBar and not InCombatLockdown() then
            -- Check if we've already hooked this castbar
            if not frame.castBar.mNameplatesHooked then
                frame.castBar.mNameplatesHooked = true
                
                -- Hook the Show function instead of overriding it
                hooksecurefunc(frame.castBar, "Show", function(self)
                    if mNameplatesDB.showCastbar then
                        -- Apply our customizations after shown
                        C_Timer.After(0, function()
                            if not InCombatLockdown() then
                                self:SetStatusBarTexture(mNameplatesDB.castbarTexture)
                                self:SetHeight(mNameplatesDB.castbarHeight)
                                if self.Background then
                                    self.Background:SetTexture(mNameplatesDB.backgroundTexture)
                                    self.Background:SetVertexColor(0.1, 0.1, 0.1, 0.8)
                                end
                            end
                        end)
                        
                        -- Apply font sizes with delay to ensure text is created
                        C_Timer.After(0.01, function()
                            if self.Text then
                                local font, _, flags = self.Text:GetFont()
                                if font then
                                    self.Text:SetFont(font, mNameplatesDB.castbarNameFontSize, flags)
                                end
                            end
                            
                            -- Try different possible names for cast time text
                            local timeText = self.CastTimeText or self.castTime or self.Time
                            if timeText then
                                local font, _, flags = timeText:GetFont()
                                if font then
                                    timeText:SetFont(font, mNameplatesDB.castbarNameFontSize, flags)
                                end
                            end
                        end)
                        
                        -- Apply cast colors if enabled
                        if mNameplatesDB.enableCastbarColors then
                            C_Timer.After(0.01, function()
                                if self.notInterruptible then
                                    self:SetStatusBarColor(
                                        mNameplatesDB.nonInterruptibleColor.r,
                                        mNameplatesDB.nonInterruptibleColor.g,
                                        mNameplatesDB.nonInterruptibleColor.b
                                    )
                                else
                                    self:SetStatusBarColor(
                                        mNameplatesDB.interruptibleColor.r,
                                        mNameplatesDB.interruptibleColor.g,
                                        mNameplatesDB.interruptibleColor.b
                                    )
                                end
                            end)
                        end
                    elseif not mNameplatesDB.showCastbar then
                        -- Hide castbar if our setting is disabled
                        C_Timer.After(0, function()
                            if self and self:IsShown() then
                                self:Hide()
                            end
                        end)
                    end
                end)
            end
        end
    end)
end

function Nameplates:OnInitialize()
    if not mNameplatesDB then
        mNameplatesDB = {}
    end
    
    for key, value in pairs(defaults) do
        if mNameplatesDB[key] == nil then
            mNameplatesDB[key] = value
        end
    end
    
    -- Apply initial settings
    UpdateNameplateCVars()
    
    -- Set up a timer to maintain nameplate visibility if enabled
    -- Cancel existing ticker if it exists to prevent duplicates
    if mainTicker then
        mainTicker:Cancel()
    end
    
    mainTicker = C_Timer.NewTicker(1, function()
        if mNameplatesDB.alwaysShowNameplates and not InCombatLockdown() then
            if GetCVar("nameplateShowEnemies") ~= "1" then
                SetCVar("nameplateShowEnemies", 1)
            end
            if GetCVar("nameplateShowEnemyMinions") ~= "1" then
                SetCVar("nameplateShowEnemyMinions", 1)
            end
            if GetCVar("nameplateShowEnemyMinus") ~= "1" then
                SetCVar("nameplateShowEnemyMinus", 1)
            end
            if GetCVar("nameplateShowAll") ~= "1" then
                SetCVar("nameplateShowAll", 1)
            end
        end
    end)
    
    -- Set up hooks
    self:SetupHooks()
    
    -- Event frame
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("UNIT_TARGET")
    self.eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self.eventFrame:RegisterEvent("CVAR_UPDATE")
    
    self.eventFrame:SetScript("OnEvent", function(frame, event, ...)
        if event == "NAME_PLATE_UNIT_ADDED" then
            local unit = ...
            OnNamePlateAdded(unit)
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.1, RefreshAllNameplates)
        elseif event == "UNIT_TARGET" or event == "UNIT_THREAT_SITUATION_UPDATE" then
            -- Update threat colors for all nameplates when threat changes
            if mNameplatesDB.enableTankThreatColors and IsPlayerTank() then
                for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
                    if nameplate.UnitFrame and nameplate.UnitFrame.unit then
                        UpdateNameplateThreatColor(nameplate.UnitFrame, nameplate.UnitFrame.unit)
                    end
                end
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Refresh nameplates when player changes spec (might change tank status)
            C_Timer.After(0.1, RefreshAllNameplates)
        elseif event == "CVAR_UPDATE" then
            local cvar = ...
            -- Force nameplate visibility if our setting is enabled
            if mNameplatesDB.alwaysShowNameplates and not InCombatLockdown() then
                if (cvar == "nameplateShowEnemies" or cvar == "nameplateShowEnemyMinions" or 
                    cvar == "nameplateShowEnemyMinus" or cvar == "nameplateShowAll") then
                    C_Timer.After(0.1, function()
                        if not InCombatLockdown() then
                            UpdateNameplateCVars()
                        end
                    end)
                end
            end
        end
    end)
    
    -- Initial refresh
    C_Timer.After(0.5, RefreshAllNameplates)
    
    -- Slash commands
    SLASH_MELLOUINAMEPLATES1 = "/mnameplates"
    SLASH_MELLOUINAMEPLATES2 = "/mnp"
    SlashCmdList["MELLOUINAMEPLATES"] = function(msg)
        if msg == "reset" then
            mNameplatesDB = {}
            for key, value in pairs(defaults) do
                mNameplatesDB[key] = value
            end
            RefreshAllNameplates()
            print("|cff00ff00MelloUI Nameplates:|r Settings reset to defaults")
        else
            RefreshAllNameplates()
            print("|cff00ff00MelloUI Nameplates:|r Nameplates refreshed")
        end
    end
end

function Nameplates:OnEnable()
    -- Ensure DB is initialized (in case module is enabled after initial load)
    if not mNameplatesDB then
        mNameplatesDB = {}
    end
    
    for key, value in pairs(defaults) do
        if mNameplatesDB[key] == nil then
            mNameplatesDB[key] = value
        end
    end
    
    -- Module enabled
    if self.eventFrame then
        self.eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:RegisterEvent("UNIT_TARGET")
        self.eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        self.eventFrame:RegisterEvent("CVAR_UPDATE")
    end
    RefreshAllNameplates()
end

function Nameplates:OnDisable()
    -- Module disabled - clean up
    if mainTicker then
        mainTicker:Cancel()
        mainTicker = nil
    end
    if fontUpdateTimer then
        fontUpdateTimer:Cancel()
        fontUpdateTimer = nil
    end
    pendingFontUpdates = {}
    
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
end

-- Register the module
ns:RegisterModule("Nameplates", Nameplates)