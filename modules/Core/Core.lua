-- MelloUI Core Module
local addonName, ns = ...
local Core = {}

-- Initialize SavedVariables
if not MelloUISavedVars then
    MelloUISavedVars = {}
end

local function ColorFrameTexture(frame)
    if frame and frame.FrameTexture then
        frame.FrameTexture:SetVertexColor(0, 0, 0, 1)
    end
end

local function ColorAllFrames()
    -- Player Frame
    if PlayerFrame and PlayerFrame.PlayerFrameContainer then
        ColorFrameTexture(PlayerFrame.PlayerFrameContainer)
    end
    
    -- Hide Player Status Texture
    if PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.StatusTexture then
        PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.StatusTexture:Hide()
    end
    
    -- Hide Player Name/Level Background
    if PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual then
        if PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon then
            PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon:Hide()
        end
        if PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PrestigePortraitIcon then
            PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PrestigePortraitIcon:Hide()
        end
        if PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PrestigeBadge then
            PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PrestigeBadge:Hide()
        end
    end
    
    -- Also hide the name background texture if it exists
    if PlayerFrame and PlayerFrame.name then
        local parent = PlayerFrame.name:GetParent()
        if parent then
            for i = 1, parent:GetNumRegions() do
                local region = select(i, parent:GetRegions())
                if region and region:GetObjectType() == "Texture" and region ~= PlayerFrame.PlayerFrameContainer.FrameTexture then
                    local texture = region:GetTexture()
                    if texture and (string.find(texture, "UI-HUD-UnitFrame-Player-PortraitOn") or string.find(texture, "NameBackground")) then
                        region:Hide()
                    end
                end
            end
        end
    end
    
    -- Hide Health Bar Mask
    if PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarMask then
        PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarMask:Hide()
    end
    
    -- Hide PlayerFrame Scrolling Damage/Healing Text
    if PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerHitIndicator then
        PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerHitIndicator:Hide()
        PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerHitIndicator:SetAlpha(0)
    end
    
    -- Paladin Power Bar Frame
    if PaladinPowerBarFrame and PaladinPowerBarFrame.ActiveTexture then
        PaladinPowerBarFrame.ActiveTexture:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Color Minimap Compass Texture Black
    if MinimapCompassTexture then
        MinimapCompassTexture:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Hide MicroMenuContainer
    if MicroMenuContainer then
        MicroMenuContainer:Hide()
    end
    
    -- Hide BagsBar
    if BagsBar then
        BagsBar:Hide()
    end
    
    -- Color Status Tracking Bars Black
    if StatusTrackingBarManager then
        -- Main Status Tracking Bar
        if StatusTrackingBarManager.MainStatusTrackingBarContainer and StatusTrackingBarManager.MainStatusTrackingBarContainer.BarFrameTexture then
            StatusTrackingBarManager.MainStatusTrackingBarContainer.BarFrameTexture:SetVertexColor(0, 0, 0, 1)
        end
        -- Secondary Status Tracking Bar
        if StatusTrackingBarManager.SecondaryStatusTrackingBarContainer and StatusTrackingBarManager.SecondaryStatusTrackingBarContainer.BarFrameTexture then
            StatusTrackingBarManager.SecondaryStatusTrackingBarContainer.BarFrameTexture:SetVertexColor(0, 0, 0, 1)
        end
    end
    
    -- Also check if SecondaryStatusTrackingBarContainer exists as a global
    if SecondaryStatusTrackingBarContainer and SecondaryStatusTrackingBarContainer.BarFrameTexture then
        SecondaryStatusTrackingBarContainer.BarFrameTexture:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Color Quest Objective Tracker textures black
    if ObjectiveTrackerFrame then
        local function ColorObjectiveTrackerTextures(frame)
            if not frame then return end
            
            -- Check if this frame has a NormalTexture
            if frame.NormalTexture then
                frame.NormalTexture:SetVertexColor(0, 0, 0, 1)
            end
            
            -- Check for specific border textures
            local borderTextures = {"BarFrame", "BarFrame2", "BarFrame3", "BarBorder", "Border", "BorderLeft", "BorderRight", "BorderTop", "BorderBottom"}
            for _, textureName in ipairs(borderTextures) do
                local texture = frame[textureName]
                if texture and texture:GetObjectType() == "Texture" then
                    texture:SetVertexColor(0, 0, 0, 1)
                end
            end
            
            -- Check for textures in common patterns
            local textures = {frame:GetRegions()}
            for _, region in ipairs(textures) do
                if region and region:GetObjectType() == "Texture" then
                    local name = region:GetDebugName()
                    -- Look for border/frame textures
                    if name then
                        local isBorderTexture = string.find(name, "NormalTexture") or 
                                              string.find(name, "Border") or 
                                              string.find(name, "BarFrame") or
                                              string.find(name, "BarBorder")
                        
                        -- Don't color the actual progress bar fill
                        local isBarFill = string.find(name, "BarFill") or 
                                        (string.find(name, "Bar") and not string.find(name, "BarFrame") and not string.find(name, "BarBorder"))
                        
                        if isBorderTexture and not isBarFill then
                            region:SetVertexColor(0, 0, 0, 1)
                        end
                    end
                end
            end
            
            -- Recursively check children
            local children = {frame:GetChildren()}
            for _, child in ipairs(children) do
                ColorObjectiveTrackerTextures(child)
            end
        end
        
        -- Color existing textures
        ColorObjectiveTrackerTextures(ObjectiveTrackerFrame)
        
        -- Also check QuestObjectiveTracker specifically
        if QuestObjectiveTracker then
            ColorObjectiveTrackerTextures(QuestObjectiveTracker)
            if QuestObjectiveTracker.ContentsFrame then
                ColorObjectiveTrackerTextures(QuestObjectiveTracker.ContentsFrame)
            end
        end
        
        -- Check BonusObjectiveTracker specifically
        if BonusObjectiveTracker then
            ColorObjectiveTrackerTextures(BonusObjectiveTracker)
            if BonusObjectiveTracker.ContentsFrame then
                ColorObjectiveTrackerTextures(BonusObjectiveTracker.ContentsFrame)
            end
        end
    end
    
    -- Target Frame
    if TargetFrame and TargetFrame.TargetFrameContainer then
        ColorFrameTexture(TargetFrame.TargetFrameContainer)
    end
    
    -- Target of Target Frame
    if TargetFrameToT and TargetFrameToT.FrameTexture then
        TargetFrameToT.FrameTexture:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Pet Frame
    if PetFrame and PetFrame.FrameTexture then
        PetFrame.FrameTexture:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Focus Frame
    if FocusFrame and FocusFrame.TargetFrameContainer then
        ColorFrameTexture(FocusFrame.TargetFrameContainer)
    end
    
    -- Boss Frames
    for i = 1, 5 do
        local bossFrame = _G["Boss" .. i .. "TargetFrame"]
        if bossFrame and bossFrame.TargetFrameContainer then
            ColorFrameTexture(bossFrame.TargetFrameContainer)
        end
    end
    
    -- Arena Frames
    for i = 1, 5 do
        local arenaFrame = _G["ArenaEnemyMatchFrame" .. i]
        if arenaFrame and arenaFrame.TargetFrameContainer then
            ColorFrameTexture(arenaFrame.TargetFrameContainer)
        end
    end
    
    -- Color BuffBarCooldownViewer borders black
    if BuffBarCooldownViewer then
        -- Style the main frame border if it exists
        if BuffBarCooldownViewer.Border then
            BuffBarCooldownViewer.Border:SetVertexColor(0, 0, 0, 1)
        end
        
        -- Recursively style all child borders
        local function StyleBuffBarBorders(frame)
            if not frame then return end
            
            -- Check for Border
            if frame.Border then
                frame.Border:SetVertexColor(0, 0, 0, 1)
            end
            
            -- Check for Icon.Border
            if frame.Icon and frame.Icon.Border then
                frame.Icon.Border:SetVertexColor(0, 0, 0, 1)
            end
            
            -- Check all children
            for _, child in pairs({frame:GetChildren()}) do
                StyleBuffBarBorders(child)
            end
        end
        
        StyleBuffBarBorders(BuffBarCooldownViewer)
    end
end

-- Function to color container frames
local function ColorContainerFrames()
    -- Color Container Frame Combined Bags Normal Texture and Borders Black
    if ContainerFrameCombinedBags then
        if ContainerFrameCombinedBags.NormalTexture then
            ContainerFrameCombinedBags.NormalTexture:SetVertexColor(0, 0, 0, 1)
        end
        
        -- Recursively style all borders with protection against infinite recursion
        local processedFrames = {}
        local function StyleContainerBorders(frame)
            if not frame then return end
            
            -- Prevent infinite recursion
            if processedFrames[frame] then return end
            processedFrames[frame] = true
            
            -- Check for Border (could be texture or frame)
            if frame.Border then
                if frame.Border.SetVertexColor then
                    frame.Border:SetVertexColor(0, 0, 0, 1)
                elseif frame.Border:GetObjectType() == "Frame" then
                    -- Border is a frame, check its textures
                    for _, region in pairs({frame.Border:GetRegions()}) do
                        if region:GetObjectType() == "Texture" and region.SetVertexColor then
                            region:SetVertexColor(0, 0, 0, 1)
                        end
                    end
                end
            end
            
            -- Check for NormalTexture
            if frame.NormalTexture and frame.NormalTexture.SetVertexColor then
                frame.NormalTexture:SetVertexColor(0, 0, 0, 1)
            end
            
            -- Check all children
            for _, child in pairs({frame:GetChildren()}) do
                StyleContainerBorders(child)
            end
        end
        
        StyleContainerBorders(ContainerFrameCombinedBags)
        
        -- Store hook state to prevent multiple hooks
        if not ContainerFrameCombinedBags._MelloUIHooked then
            ContainerFrameCombinedBags._MelloUIHooked = true
            
            -- Hook to maintain black color on updates
            if ContainerFrameCombinedBags.Update then
                hooksecurefunc(ContainerFrameCombinedBags, "Update", function()
                    C_Timer.After(0, function()
                        local processed = {}
                        local function restyle(frame)
                            if not frame or processed[frame] then return end
                            processed[frame] = true
                            
                            if frame.Border and frame.Border.SetVertexColor then
                                frame.Border:SetVertexColor(0, 0, 0, 1)
                            end
                            if frame.NormalTexture and frame.NormalTexture.SetVertexColor then
                                frame.NormalTexture:SetVertexColor(0, 0, 0, 1)
                            end
                        end
                        restyle(ContainerFrameCombinedBags)
                    end)
                end)
            end
        end
    end
end

-- Function to color mirror timers
local function ColorMirrorTimers()
    -- Color Mirror Timer Container Border Black
    if MirrorTimerContainer then
        -- Check all children of MirrorTimerContainer for borders
        for _, child in pairs({MirrorTimerContainer:GetChildren()}) do
            if child.Border then
                child.Border:SetVertexColor(0, 0, 0, 1)
            end
            -- Also check nested children
            for _, subchild in pairs({child:GetChildren()}) do
                if subchild.Border then
                    subchild.Border:SetVertexColor(0, 0, 0, 1)
                end
            end
        end
        
        -- Individual mirror timers
        for i = 1, 3 do
            local timer = _G["MirrorTimer"..i]
            if timer and timer.Border then
                timer.Border:SetVertexColor(0, 0, 0, 1)
            end
        end
    end
end

-- Function to color casting bars
local function ColorCastingBars()
    -- Color Player Casting Bar Border Black
    if PlayerCastingBarFrame and PlayerCastingBarFrame.Border then
        PlayerCastingBarFrame.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Color Target Casting Bar Border Black
    if TargetFrameSpellBar and TargetFrameSpellBar.Border then
        TargetFrameSpellBar.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Color Focus Casting Bar Border Black
    if FocusFrameSpellBar and FocusFrameSpellBar.Border then
        FocusFrameSpellBar.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Color Pet Casting Bar Border Black
    if PetCastingBarFrame and PetCastingBarFrame.Border then
        PetCastingBarFrame.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Color Boss Casting Bar Borders Black
    for i = 1, 5 do
        local bossBar = _G["Boss"..i.."TargetFrameSpellBar"]
        if bossBar and bossBar.Border then
            bossBar.Border:SetVertexColor(0, 0, 0, 1)
        end
    end
    
    -- Color Arena Casting Bar Borders Black
    for i = 1, 5 do
        local arenaBar = _G["ArenaEnemyMatchFrame"..i.."CastingBar"]
        if arenaBar and arenaBar.Border then
            arenaBar.Border:SetVertexColor(0, 0, 0, 1)
        end
    end
    
    -- Color Target of Target Casting Bar Border Black
    if TargetFrameToT and TargetFrameToT.spellbar and TargetFrameToT.spellbar.Border then
        TargetFrameToT.spellbar.Border:SetVertexColor(0, 0, 0, 1)
    end
end

-- Function to style action bars
local function StyleActionBars()
    -- Function to style individual action buttons
    local function StyleActionButton(button)
        if not button then return end
        
        -- Style the border
        if button.Border then
            button.Border:SetVertexColor(0, 0, 0, 1)
        end
        
        -- Style the NormalTexture (default border)
        if button.NormalTexture then
            button.NormalTexture:SetVertexColor(0, 0, 0, 1)
        end
        
        -- Hook to maintain the color
        if button.SetNormalTexture then
            hooksecurefunc(button, "SetNormalTexture", function(self)
                if self.NormalTexture then
                    self.NormalTexture:SetVertexColor(0, 0, 0, 1)
                end
            end)
        end
    end
    
    -- Main Action Bar
    for i = 1, 12 do
        StyleActionButton(_G["ActionButton" .. i])
    end
    
    -- Bottom Left Action Bar
    for i = 1, 12 do
        StyleActionButton(_G["MultiBarBottomLeftButton" .. i])
    end
    
    -- Bottom Right Action Bar
    for i = 1, 12 do
        StyleActionButton(_G["MultiBarBottomRightButton" .. i])
    end
    
    -- Right Action Bar
    for i = 1, 12 do
        StyleActionButton(_G["MultiBarRightButton" .. i])
    end
    
    -- Left Action Bar
    for i = 1, 12 do
        StyleActionButton(_G["MultiBarLeftButton" .. i])
    end
    
    -- Pet Action Bar
    for i = 1, 10 do
        StyleActionButton(_G["PetActionButton" .. i])
    end
    
    -- Stance Bar
    for i = 1, 10 do
        StyleActionButton(_G["StanceButton" .. i])
    end
    
    -- Possess Bar
    for i = 1, 10 do
        StyleActionButton(_G["PossessButton" .. i])
    end
    
    -- Extra Action Button
    StyleActionButton(ExtraActionButton1)
    
    -- Zone Ability Frame
    if ZoneAbilityFrame then
        for button in ZoneAbilityFrame.SpellButtonContainer:EnumerateActive() do
            StyleActionButton(button)
        end
    end
end

-- Style Buff and Debuff Frames
local function StyleAura(aura)
    if not aura then return end
    
    -- Style the border
    if aura.Border then
        aura.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- For buffs/debuffs that use Icon.Border
    if aura.Icon and aura.Icon.Border then
        aura.Icon.Border:SetVertexColor(0, 0, 0, 1)
    end
end

-- Style all borders in BuffFrame.AuraContainer
local function StyleAuraContainer()
    -- Modern BuffFrame with AuraContainer
    if BuffFrame and BuffFrame.AuraContainer then
        -- Get all children of AuraContainer
        for _, child in pairs({BuffFrame.AuraContainer:GetChildren()}) do
            if child.Border then
                child.Border:SetVertexColor(0, 0, 0, 1)
            end
            -- Check if it's an aura button
            if child.Icon then
                StyleAura(child)
            end
        end
    end
    
    -- Also check DebuffFrame if it has AuraContainer
    if DebuffFrame and DebuffFrame.AuraContainer then
        for _, child in pairs({DebuffFrame.AuraContainer:GetChildren()}) do
            if child.Border then
                child.Border:SetVertexColor(0, 0, 0, 1)
            end
            if child.Icon then
                StyleAura(child)
            end
        end
    end
end

-- Hook to style auras when they're created or updated
local function HookAuraFrames()
    -- Hook BuffFrame aura updates
    if BuffFrame then
        hooksecurefunc(BuffFrame, "Update", function()
            C_Timer.After(0, StyleAuraContainer)
        end)
    end
    
    -- Hook into EditModeManagerFrame if it exists (modern UI)
    if EditModeManagerFrame and EditModeManagerFrame.AccountSettings then
        local settings = EditModeManagerFrame.AccountSettings
        if settings.RefreshAuraFrame then
            hooksecurefunc(settings, "RefreshAuraFrame", function()
                C_Timer.After(0, StyleAuraContainer)
            end)
        end
    end
end

-- Function to recursively find and style all aura borders
local function StyleAllAuras(frame)
    if not frame then return end
    
    -- Check if this frame has a border
    if frame.Border then
        frame.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Check for Icon.Border
    if frame.Icon and frame.Icon.Border then
        frame.Icon.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Check all children
    for _, child in pairs({frame:GetChildren()}) do
        StyleAllAuras(child)
    end
end

-- Function to style buffs and debuffs
local function StyleBuffsAndDebuffs()
    -- Buffs
    if BuffFrame then
        StyleAllAuras(BuffFrame)
        for i = 1, BUFF_MAX_DISPLAY do
            local buff = _G["BuffButton"..i]
            if buff then
                StyleAura(buff)
            end
        end
    end
    
    -- Debuffs
    if DebuffFrame then
        StyleAllAuras(DebuffFrame)
        for i = 1, DEBUFF_MAX_DISPLAY do
            local debuff = _G["DebuffButton"..i]
            if debuff then
                StyleAura(debuff)
            end
        end
    end
    
    -- Temp Enchants
    for i = 1, 3 do
        local tempEnchant = _G["TempEnchant"..i]
        if tempEnchant then
            StyleAura(tempEnchant)
        end
    end
    
    -- Style AuraContainer
    StyleAuraContainer()
end

-- Style tooltips with modern NineSlice system
local function StyleTooltip(tooltip)
    if not tooltip then return end
    
    -- Modern tooltips use NineSlice system
    if tooltip.NineSlice then
        tooltip.NineSlice:SetBorderColor(0, 0, 0, 1)
    end
    
    -- Legacy border support
    if tooltip.Border then
        tooltip.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Some tooltips have BackdropFrame
    if tooltip.BackdropFrame then
        if tooltip.BackdropFrame.NineSlice then
            tooltip.BackdropFrame.NineSlice:SetBorderColor(0, 0, 0, 1)
        end
        if tooltip.BackdropFrame.Border then
            tooltip.BackdropFrame.Border:SetVertexColor(0, 0, 0, 1)
        end
    end
end

-- Hook all tooltips
hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
    if tooltip then
        C_Timer.After(0, function() StyleTooltip(tooltip) end)
    end
end)

-- Style specific tooltips
local tooltips = {
    GameTooltip,
    ItemRefTooltip,
    ItemRefShoppingTooltip1,
    ItemRefShoppingTooltip2,
    ShoppingTooltip1,
    ShoppingTooltip2,
    AutoCompleteBox,
    FriendsTooltip,
    ConsolidatedBuffsTooltip,
    WorldMapTooltip,
    WorldMapCompareTooltip1,
    WorldMapCompareTooltip2,
    DropDownList1MenuBackdrop,
    DropDownList2MenuBackdrop,
    BattlePetTooltip,
    PetBattlePrimaryAbilityTooltip,
    PetBattlePrimaryUnitTooltip,
    FloatingBattlePetTooltip,
    FloatingPetBattleAbilityTooltip,
    FloatingGarrisonFollowerTooltip,
    GarrisonFollowerTooltip,
    GarrisonFollowerAbilityTooltip,
    GarrisonMissionMechanicTooltip,
    GarrisonMissionMechanicFollowerCounterTooltip,
    ReputationParagonTooltip,
    QueueStatusFrame,
    FloatingGarrisonFollowerAbilityTooltip,
    GarrisonFollowerMissionAbilityWithoutCountersTooltip,
    GarrisonFollowerAbilityWithoutCountersTooltip,
}

for _, tooltip in pairs(tooltips) do
    if tooltip then
        StyleTooltip(tooltip)
        
        -- Hook OnShow to maintain style
        if tooltip:HasScript("OnShow") then
            tooltip:HookScript("OnShow", function(self)
                C_Timer.After(0, function() StyleTooltip(self) end)
            end)
        end
    end
end

-- Override health text formatting
local function FormatHealth(value)
    if value >= 1e9 then
        return string.format("%.1fb", value / 1e9)
    elseif value >= 1e6 then
        return string.format("%.1fm", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.1fk", value / 1e3)
    else
        return tostring(value)
    end
end

-- Override mana text formatting
local function FormatMana(value)
    if value >= 1e9 then
        return string.format("%.1fb", value / 1e9)
    elseif value >= 1e6 then
        return string.format("%.1fm", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.1fk", value / 1e3)
    else
        return tostring(value)
    end
end

-- Hook into health text updates
local function OverrideHealthText(statusBar, unit)
    if not statusBar or not unit then return end
    
    local textString = statusBar.TextString
    if not textString then
        -- Try to find the text string
        for _, region in pairs({statusBar:GetRegions()}) do
            if region:GetObjectType() == "FontString" then
                textString = region
                break
            end
        end
    end
    
    if textString then
        local health = UnitHealth(unit)
        local maxHealth = UnitHealthMax(unit)
        
        if health and maxHealth and maxHealth > 0 then
            local healthPercent = (health / maxHealth) * 100
            textString:SetText(FormatHealth(health) .. " (" .. string.format("%.0f", healthPercent) .. "%)")
        end
    end
end

-- Hook into mana text updates
local function OverrideManaText(statusBar, unit)
    if not statusBar or not unit then return end
    
    local textString = statusBar.TextString
    if not textString then
        -- Try to find the text string
        for _, region in pairs({statusBar:GetRegions()}) do
            if region:GetObjectType() == "FontString" then
                textString = region
                break
            end
        end
    end
    
    if textString then
        local mana = UnitPower(unit)
        local maxMana = UnitPowerMax(unit)
        
        if mana and maxMana and maxMana > 0 then
            local manaPercent = (mana / maxMana) * 100
            textString:SetText(FormatMana(mana) .. " (" .. string.format("%.0f", manaPercent) .. "%)")
        end
    end
end

-- Setup hooks for health and mana text
local function SetupHealthTextHooks()
    -- Try the older hook first
    if TextStatusBar_UpdateTextStringWithValues then
        hooksecurefunc("TextStatusBar_UpdateTextStringWithValues", function(statusBar, textString, value, valueMin, valueMax)
            if statusBar:GetName() then
                local name = statusBar:GetName()
                
                -- Player Health
                if name == "PlayerFrameHealthBar" or (statusBar:GetParent() and statusBar:GetParent():GetName() == "PlayerFrame" and statusBar.unit == "player") then
                    OverrideHealthText(statusBar, "player")
                -- Player Mana
                elseif name == "PlayerFrameManaBar" then
                    OverrideManaText(statusBar, "player")
                -- Target Health
                elseif name == "TargetFrameHealthBar" then
                    OverrideHealthText(statusBar, "target")
                -- Target Mana
                elseif name == "TargetFrameManaBar" then
                    OverrideManaText(statusBar, "target")
                -- Focus Health
                elseif name == "FocusFrameHealthBar" then
                    OverrideHealthText(statusBar, "focus")
                -- Focus Mana
                elseif name == "FocusFrameManaBar" then
                    OverrideManaText(statusBar, "focus")
                -- Pet Health
                elseif name == "PetFrameHealthBar" then
                    OverrideHealthText(statusBar, "pet")
                -- Pet Mana
                elseif name == "PetFrameManaBar" then
                    OverrideManaText(statusBar, "pet")
                end
            end
        end)
    end
    
    -- Alternative approach using TextStatusBar_UpdateTextString
    if TextStatusBar_UpdateTextString then
        hooksecurefunc("TextStatusBar_UpdateTextString", function(statusBar)
            if statusBar:GetName() then
                local name = statusBar:GetName()
                
                -- Player Health
                if name == "PlayerFrameHealthBar" then
                    OverrideHealthText(statusBar, "player")
                -- Player Mana
                elseif name == "PlayerFrameManaBar" then
                    OverrideManaText(statusBar, "player")
                -- Target Health
                elseif name == "TargetFrameHealthBar" then
                    OverrideHealthText(statusBar, "target")
                -- Target Mana
                elseif name == "TargetFrameManaBar" then
                    OverrideManaText(statusBar, "target")
                -- Focus Health
                elseif name == "FocusFrameHealthBar" then
                    OverrideHealthText(statusBar, "focus")
                -- Focus Mana
                elseif name == "FocusFrameManaBar" then
                    OverrideManaText(statusBar, "focus")
                -- Pet Health
                elseif name == "PetFrameHealthBar" then
                    OverrideHealthText(statusBar, "pet")
                -- Pet Mana
                elseif name == "PetFrameManaBar" then
                    OverrideManaText(statusBar, "pet")
                end
            end
        end)
    end
    
    -- Boss and Arena frames
    if UnitFrameHealthBar_Update then
        hooksecurefunc("UnitFrameHealthBar_Update", function(statusBar, unit)
            if unit then
                -- Boss Frames
                for i = 1, 5 do
                    if unit == "boss"..i then
                        OverrideHealthText(statusBar, unit)
                        break
                    end
                end
                
                -- Arena Frames
                for i = 1, 5 do
                    if unit == "arena"..i then
                        OverrideHealthText(statusBar, unit)
                        break
                    end
                end
            end
        end)
    end
    
    if UnitFrameManaBar_Update then
        hooksecurefunc("UnitFrameManaBar_Update", function(statusBar, unit)
            if unit then
                -- Boss Frames
                for i = 1, 5 do
                    if unit == "boss"..i then
                        OverrideManaText(statusBar, unit)
                        break
                    end
                end
                
                -- Arena Frames
                for i = 1, 5 do
                    if unit == "arena"..i then
                        OverrideManaText(statusBar, unit)
                        break
                    end
                end
            end
        end)
    end
    
    -- Additional hook for boss/arena frames
    if TextStatusBar_UpdateTextString then
        hooksecurefunc("TextStatusBar_UpdateTextString", function(statusBar)
            -- Boss Frames
            for i = 1, 5 do
                local frame = _G["Boss"..i.."TargetFrame"]
                if frame then
                    if frame.healthbar == statusBar then
                        OverrideHealthText(frame.healthbar, "boss"..i)
                    elseif frame.manabar == statusBar then
                        OverrideManaText(frame.manabar, "boss"..i)
                    end
                end
            end
            
            -- Arena Frames
            for i = 1, 5 do
                local frame = _G["ArenaEnemyMatchFrame"..i]
                if frame then
                    if frame.healthbar == statusBar then
                        OverrideHealthText(frame.healthbar, "arena"..i)
                    elseif frame.manabar == statusBar then
                        OverrideManaText(frame.manabar, "arena"..i)
                    end
                end
            end
        end)
    end
end

-- Function to add MelloUI button to Game Menu
local gameMenuButtonAdded = false
local originalButtonPositions = {}

local function AddGameMenuButton()
    -- Create our button only once
    if not GameMenuButtonMelloUI then
        local menuButton = CreateFrame("Button", "GameMenuButtonMelloUI", GameMenuFrame, "GameMenuButtonTemplate")
        menuButton:SetText("MelloUI")
        menuButton:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
            HideUIPanel(GameMenuFrame)
            if MelloUIProfileInstaller then
                MelloUIProfileInstaller:ShowInstaller()
            end
        end)
        
        -- Add a glow border
        local glow = menuButton:CreateTexture(nil, "BACKGROUND")
        glow:SetPoint("TOPLEFT", menuButton, "TOPLEFT", -3, 3)
        glow:SetPoint("BOTTOMRIGHT", menuButton, "BOTTOMRIGHT", 3, -3)
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetVertexColor(1, 0.82, 0) -- Golden color
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0.3)
        menuButton.glow = glow
        
        -- Make the glow pulse
        local animGroup = menuButton:CreateAnimationGroup()
        local fadeIn = animGroup:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.3)
        fadeIn:SetToAlpha(0.6)
        fadeIn:SetDuration(1)
        fadeIn:SetOrder(1)
        
        local fadeOut = animGroup:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(0.6)
        fadeOut:SetToAlpha(0.3)
        fadeOut:SetDuration(1)
        fadeOut:SetOrder(2)
        
        animGroup:SetLooping("REPEAT")
        animGroup:Play()
        
        -- Apply the animation to the glow
        fadeIn:SetTarget(glow)
        fadeOut:SetTarget(glow)
    end
    
    local menuButton = GameMenuButtonMelloUI
    
    -- Only reposition buttons on first setup
    if not gameMenuButtonAdded then
        -- Store original button positions
        local buttons = {}
        for _, child in ipairs({GameMenuFrame:GetChildren()}) do
            if child:IsObjectType("Button") and child:GetText() and child ~= menuButton then
                table.insert(buttons, child)
                -- Store original position
                if not originalButtonPositions[child] then
                    originalButtonPositions[child] = {child:GetPoint()}
                end
            end
        end
        
        -- Find the header
        local header = GameMenuFrameHeader or GameMenuFrame.Header
        local startY = -16
        
        if header then
            startY = -(header:GetHeight() + 8)
        end
        
        -- Position MelloUI button at the top (moved up by 100 pixels total)
        menuButton:ClearAllPoints()
        menuButton:SetPoint("TOP", GameMenuFrame, "TOP", 0, startY + 100)
        
        -- Move all other buttons down
        local previousButton = menuButton
        for i, button in ipairs(buttons) do
            button:ClearAllPoints()
            button:SetPoint("TOP", previousButton, "BOTTOM", 0, -1)
            previousButton = button
        end
        
        -- Calculate and set frame height
        local numButtons = #buttons + 1
        local buttonHeight = menuButton:GetHeight() or 20
        local spacing = 1
        local headerSpace = math.abs(startY) + 8
        local buttonsHeight = (numButtons * buttonHeight) + ((numButtons - 1) * spacing)
        local bottomPadding = 20
        local totalHeight = headerSpace + buttonsHeight + bottomPadding
        
        -- Store original height
        if not GameMenuFrame.originalHeight then
            GameMenuFrame.originalHeight = GameMenuFrame:GetHeight()
        end
        
        GameMenuFrame:SetHeight(totalHeight)
        gameMenuButtonAdded = true
    end
    
    -- Always ensure our button is shown
    menuButton:Show()
end

-- Hook to add button when game menu is first shown
local gameMenuHookSetup = false
local function SetupGameMenuHook()
    if gameMenuHookSetup then return end
    
    local function SetupHook()
        if GameMenuFrame and not gameMenuHookSetup then
            gameMenuHookSetup = true
            GameMenuFrame:HookScript("OnShow", function()
                AddGameMenuButton()
            end)
            -- Run once immediately if menu is already open
            if GameMenuFrame:IsShown() then
                AddGameMenuButton()
            end
        end
    end
    
    -- Try to set up immediately
    SetupHook()
    
    -- If GameMenuFrame doesn't exist yet, wait for it
    if not gameMenuHookSetup then
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("ADDON_LOADED")
        watcher:SetScript("OnEvent", function(self, event, addonName)
            if addonName == "Blizzard_GameMenu" or GameMenuFrame then
                SetupHook()
                if gameMenuHookSetup then
                    self:UnregisterEvent("ADDON_LOADED")
                end
            end
        end)
    end
end

function Core:OnInitialize()
    -- Call setup hooks
    SetupHealthTextHooks()
    
    -- Setup Game Menu button hook
    SetupGameMenuHook()
    
    -- Continue with normal MelloUI initialization
    C_Timer.After(0.1, function()
        ColorAllFrames()
        ColorMirrorTimers()
        ColorCastingBars()
        StyleBuffsAndDebuffs()
        HookAuraFrames()
        ColorContainerFrames()
        StyleActionBars()
    end)
    
    -- Setup event frame for maintaining styles
    local maintenanceFrame = CreateFrame("Frame")
    maintenanceFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    maintenanceFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    maintenanceFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    maintenanceFrame:RegisterEvent("UNIT_PET")
    maintenanceFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    maintenanceFrame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
    maintenanceFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
    maintenanceFrame:RegisterEvent("UNIT_POWER_UPDATE")
    maintenanceFrame:SetScript("OnEvent", function(self, event, ...)
        ColorAllFrames()
    end)
    
    -- Hook the Paladin Power Bar to maintain black color
    if PaladinPowerBarFrame then
        hooksecurefunc(PaladinPowerBarFrame, "UpdatePower", function()
            if PaladinPowerBarFrame.ActiveTexture then
                PaladinPowerBarFrame.ActiveTexture:SetVertexColor(0, 0, 0, 1)
            end
        end)
        
        -- Also hook SetVertexColor to override any attempts to change the color
        if PaladinPowerBarFrame.ActiveTexture then
            hooksecurefunc(PaladinPowerBarFrame.ActiveTexture, "SetVertexColor", function(self)
                if self:GetVertexColor() ~= 0 then
                    self:SetVertexColor(0, 0, 0, 1)
                end
            end)
        end
    end
    
    -- Hook Status Tracking Bar updates to maintain black color
    if StatusTrackingBarManager then
        -- Hook the Show method to color bars when they appear
        if StatusTrackingBarManager.SecondaryStatusTrackingBarContainer then
            hooksecurefunc(StatusTrackingBarManager.SecondaryStatusTrackingBarContainer, "Show", function()
                if StatusTrackingBarManager.SecondaryStatusTrackingBarContainer.BarFrameTexture then
                    StatusTrackingBarManager.SecondaryStatusTrackingBarContainer.BarFrameTexture:SetVertexColor(0, 0, 0, 1)
                end
            end)
        end
        
        if StatusTrackingBarManager.MainStatusTrackingBarContainer then
            hooksecurefunc(StatusTrackingBarManager.MainStatusTrackingBarContainer, "Show", function()
                if StatusTrackingBarManager.MainStatusTrackingBarContainer.BarFrameTexture then
                    StatusTrackingBarManager.MainStatusTrackingBarContainer.BarFrameTexture:SetVertexColor(0, 0, 0, 1)
                end
            end)
        end
    end
    
    -- Also hook if SecondaryStatusTrackingBarContainer exists as global
    if SecondaryStatusTrackingBarContainer then
        hooksecurefunc(SecondaryStatusTrackingBarContainer, "Show", function()
            if SecondaryStatusTrackingBarContainer.BarFrameTexture then
                SecondaryStatusTrackingBarContainer.BarFrameTexture:SetVertexColor(0, 0, 0, 1)
            end
        end)
        
        -- Hook SetVertexColor to prevent color changes
        if SecondaryStatusTrackingBarContainer.BarFrameTexture then
            hooksecurefunc(SecondaryStatusTrackingBarContainer.BarFrameTexture, "SetVertexColor", function(self)
                local r, g, b = self:GetVertexColor()
                if r ~= 0 or g ~= 0 or b ~= 0 then
                    self:SetVertexColor(0, 0, 0, 1)
                end
            end)
        end
    end
    
    -- Hook Objective Tracker updates
    if ObjectiveTrackerFrame then
        -- Function to color objective tracker textures
        local function ColorObjectiveTrackerTextures(frame)
            if not frame then return end
            
            -- Check if this frame has a NormalTexture
            if frame.NormalTexture then
                frame.NormalTexture:SetVertexColor(0, 0, 0, 1)
            end
            
            -- Check for specific border textures
            local borderTextures = {"BarFrame", "BarFrame2", "BarFrame3", "BarBorder", "Border", "BorderLeft", "BorderRight", "BorderTop", "BorderBottom"}
            for _, textureName in ipairs(borderTextures) do
                local texture = frame[textureName]
                if texture and texture:GetObjectType() == "Texture" then
                    texture:SetVertexColor(0, 0, 0, 1)
                end
            end
            
            -- Check for textures in common patterns
            local textures = {frame:GetRegions()}
            for _, region in ipairs(textures) do
                if region and region:GetObjectType() == "Texture" then
                    local name = region:GetDebugName()
                    -- Look for border/frame textures
                    if name then
                        local isBorderTexture = string.find(name, "NormalTexture") or 
                                              string.find(name, "Border") or 
                                              string.find(name, "BarFrame") or
                                              string.find(name, "BarBorder")
                        
                        -- Don't color the actual progress bar fill
                        local isBarFill = string.find(name, "BarFill") or 
                                        (string.find(name, "Bar") and not string.find(name, "BarFrame") and not string.find(name, "BarBorder"))
                        
                        if isBorderTexture and not isBarFill then
                            region:SetVertexColor(0, 0, 0, 1)
                        end
                    end
                end
            end
            
            -- Recursively check children
            local children = {frame:GetChildren()}
            for _, child in ipairs(children) do
                ColorObjectiveTrackerTextures(child)
            end
        end
        
        -- Hook the Update function
        if ObjectiveTrackerFrame.Update then
            hooksecurefunc(ObjectiveTrackerFrame, "Update", function()
                C_Timer.After(0.1, function()
                    ColorObjectiveTrackerTextures(ObjectiveTrackerFrame)
                    if QuestObjectiveTracker then
                        ColorObjectiveTrackerTextures(QuestObjectiveTracker)
                        if QuestObjectiveTracker.ContentsFrame then
                            ColorObjectiveTrackerTextures(QuestObjectiveTracker.ContentsFrame)
                        end
                    end
                end)
            end)
        end
        
        -- Hook module updates for quest objectives
        local function HookTrackerModule(module)
            if module and module.Update then
                hooksecurefunc(module, "Update", function()
                    C_Timer.After(0.1, function()
                        if module.ContentsFrame then
                            ColorObjectiveTrackerTextures(module.ContentsFrame)
                        end
                        -- Also color the module itself
                        ColorObjectiveTrackerTextures(module)
                    end)
                end)
            end
            
            -- Hook specific functions for BonusObjectiveTracker
            if module == BonusObjectiveTracker then
                if module.ShowLine then
                    hooksecurefunc(module, "ShowLine", function()
                        C_Timer.After(0.1, function()
                            ColorObjectiveTrackerTextures(module)
                            if module.ContentsFrame then
                                ColorObjectiveTrackerTextures(module.ContentsFrame)
                            end
                        end)
                    end)
                end
                
                if module.AddProgressBar then
                    hooksecurefunc(module, "AddProgressBar", function()
                        C_Timer.After(0.1, function()
                            ColorObjectiveTrackerTextures(module)
                            if module.ContentsFrame then
                                ColorObjectiveTrackerTextures(module.ContentsFrame)
                            end
                        end)
                    end)
                end
            end
        end
        
        -- Hook known tracker modules
        C_Timer.After(1, function()
            if QuestObjectiveTracker then HookTrackerModule(QuestObjectiveTracker) end
            if AchievementObjectiveTracker then HookTrackerModule(AchievementObjectiveTracker) end
            if ScenarioObjectiveTracker then HookTrackerModule(ScenarioObjectiveTracker) end
            if CampaignQuestObjectiveTracker then HookTrackerModule(CampaignQuestObjectiveTracker) end
            if BonusObjectiveTracker then HookTrackerModule(BonusObjectiveTracker) end
            if WorldQuestObjectiveTracker then HookTrackerModule(WorldQuestObjectiveTracker) end
        end)
    end
end

-- Register the module
ns:RegisterModule("Core", Core)