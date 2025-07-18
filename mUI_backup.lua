local addonName, addon = ...

-- Initialize SavedVariables
if not mUISavedVars then
    mUISavedVars = {}
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
    
    -- Hide Scrolling Combat Text from Player Frame
    if PlayerFrame then
        -- Hide PlayerHitIndicator (damage/heal text on player frame)
        if PlayerHitIndicator then
            PlayerHitIndicator:Hide()
            PlayerHitIndicator:SetScript("OnShow", function(self) self:Hide() end)
        end
        
        -- Also check for combat feedback text
        if PlayerFrame.feedbackText then
            PlayerFrame.feedbackText:Hide()
            PlayerFrame.feedbackText:SetScript("OnShow", function(self) self:Hide() end)
        end
        
        -- Check for PlayerFloatingCombatTextFrame
        if PlayerFloatingCombatTextFrame then
            PlayerFloatingCombatTextFrame:Hide()
            PlayerFloatingCombatTextFrame:SetScript("OnShow", function(self) self:Hide() end)
        end
    end
    
    -- Color Paladin Power Bar Frame Black
    if PaladinPowerBarFrame and PaladinPowerBarFrame.ActiveTexture then
        PaladinPowerBarFrame.ActiveTexture:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Color Minimap Compass Texture Black
    if MinimapCompassTexture then
        MinimapCompassTexture:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Hide Micro Menu
    if MicroMenuContainer then
        MicroMenuContainer:Hide()
    end
    
    -- Hide Bags Bar
    if BagsBar then
        BagsBar:Hide()
    end
    
end

-- Separate function for coloring container frames
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
        if not ContainerFrameCombinedBags._mUIHooked then
            ContainerFrameCombinedBags._mUIHooked = true
            
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

-- Rest of ColorAllFrames function continues here
local function ColorAllFrames_Part2()
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
end

-- Update the main ColorAllFrames to include both parts
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
    
    -- Hide MicroMenuContainer
    if MicroMenuContainer then
        MicroMenuContainer:Hide()
    end
    
    -- Hide BagsBar
    if BagsBar then
        BagsBar:Hide()
    end
    
    -- Call the second part
    ColorAllFrames_Part2()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
frame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
frame:RegisterEvent("ARENA_OPPONENT_UPDATE")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:SetScript("OnEvent", function(self, event, ...)
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

-- Style Tooltips
local function StyleTooltip(tooltip)
    if not tooltip then return end
    
    -- Modern tooltips use NineSlice system
    if tooltip.NineSlice then
        tooltip.NineSlice:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Color any overlay textures
    if tooltip.TopOverlay then
        tooltip.TopOverlay:SetVertexColor(0, 0, 0, 1)
    end
    if tooltip.BottomOverlay then
        tooltip.BottomOverlay:SetVertexColor(0, 0, 0, 1)
    end
    
    -- For tooltips that still use backdrop
    if tooltip.SetBackdropColor then
        tooltip:SetBackdropColor(0, 0, 0, 1)
    end
    if tooltip.SetBackdropBorderColor then
        tooltip:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

-- Hook all tooltips
local tooltips = {
    GameTooltip,
    ItemRefTooltip,
    ItemRefShoppingTooltip1,
    ItemRefShoppingTooltip2,
    ShoppingTooltip1,
    ShoppingTooltip2,
    AutoCompleteBox,
    FriendsTooltip,
    WorldMapTooltip,
    WorldMapCompareTooltip1,
    WorldMapCompareTooltip2,
}

for _, tooltip in pairs(tooltips) do
    if tooltip then
        hooksecurefunc(tooltip, "Show", function(self)
            StyleTooltip(self)
        end)
    end
end

-- Also hook GameTooltip OnTooltipSetItem to ensure it stays black
hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
    StyleTooltip(tooltip)
end)

-- Style Action Buttons
local function StyleActionButton(button)
    if button and button.NormalTexture then
        button.NormalTexture:SetVertexColor(0, 0, 0, 1)
    end
end

-- Style all action bars
local function StyleAllActionBars()
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
    
    -- Right Action Bar 2
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
    
    -- Check Icon.Border
    if frame.Icon and frame.Icon.Border then
        frame.Icon.Border:SetVertexColor(0, 0, 0, 1)
    end
    
    -- Recursively check children
    local children = {frame:GetChildren()}
    for _, child in ipairs(children) do
        StyleAllAuras(child)
    end
end

-- Call the hook setup after a delay to ensure frames are loaded
C_Timer.After(1, HookAuraFrames)

-- Initial styling
C_Timer.After(0.1, StyleAllActionBars)

-- Also style on events
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_BINDINGS")
frame:RegisterEvent("PET_BAR_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
local oldHandler = frame:GetScript("OnEvent")
frame:SetScript("OnEvent", function(self, event, ...)
    oldHandler(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_BINDINGS" or event == "PET_BAR_UPDATE" then
        StyleAllActionBars()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            -- Style all auras recursively
            if BuffFrame then
                StyleAllAuras(BuffFrame)
            end
            if DebuffFrame then
                StyleAllAuras(DebuffFrame)
            end
            
            -- Also use the traditional approach
            for i = 1, BUFF_MAX_DISPLAY do
                local buff = _G["BuffButton"..i]
                if buff and buff:IsShown() then
                    StyleAura(buff)
                end
            end
            for i = 1, DEBUFF_MAX_DISPLAY do
                local debuff = _G["DebuffButton"..i]
                if debuff and debuff:IsShown() then
                    StyleAura(debuff)
                end
            end
            
            -- Style AuraContainer
            StyleAuraContainer()
        end
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_COOLDOWN" then
        -- Re-style container bags on bag updates
        if ContainerFrameCombinedBags then
            local function StyleContainerBorders(frame)
                if not frame then return end
                
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
        end
    end
end)

-- Function to format health numbers
local function FormatHealth(value)
    if value >= 1000000000 then
        return string.format("%.1fb", value / 1000000000)
    elseif value >= 1000000 then
        return string.format("%.1fm", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fk", value / 1000)
    else
        return tostring(value)
    end
end

-- Update health text for a specific unit frame
local function UpdateHealthText(frame, unit)
    if not frame or not unit or not UnitExists(unit) then return end
    
    local healthBar = frame.healthbar or frame.HealthBar
    if healthBar and healthBar.TextString then
        local current = UnitHealth(unit)
        healthBar.TextString:SetText(FormatHealth(current))
    end
end

-- Update mana text for a specific unit frame
local function UpdateManaText(frame, unit)
    if not frame or not unit or not UnitExists(unit) then return end
    
    local manaBar = frame.manabar or frame.ManaBar
    if manaBar and manaBar.TextString then
        local current = UnitPower(unit)
        manaBar.TextString:SetText(FormatHealth(current))
    end
end

-- Hook to update health text
local healthUpdateFrame = CreateFrame("Frame")
healthUpdateFrame:RegisterEvent("UNIT_HEALTH")
healthUpdateFrame:RegisterEvent("UNIT_MAXHEALTH")
healthUpdateFrame:RegisterEvent("UNIT_POWER_UPDATE")
healthUpdateFrame:RegisterEvent("UNIT_MAXPOWER")
healthUpdateFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
healthUpdateFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
healthUpdateFrame:RegisterEvent("UNIT_PET")
healthUpdateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
healthUpdateFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
healthUpdateFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")

healthUpdateFrame:SetScript("OnEvent", function(self, event, arg1)
    -- Player
    UpdateHealthText(PlayerFrame, "player")
    UpdateManaText(PlayerFrame, "player")
    
    -- Target
    if UnitExists("target") then
        UpdateHealthText(TargetFrame, "target")
        UpdateManaText(TargetFrame, "target")
    end
    
    -- Focus
    if UnitExists("focus") then
        UpdateHealthText(FocusFrame, "focus")
        UpdateManaText(FocusFrame, "focus")
    end
    
    -- Pet
    if UnitExists("pet") then
        UpdateHealthText(PetFrame, "pet")
        UpdateManaText(PetFrame, "pet")
    end
    
    -- Target of Target
    if UnitExists("targettarget") then
        UpdateHealthText(TargetFrameToT, "targettarget")
        UpdateManaText(TargetFrameToT, "targettarget")
    end
    
    -- Boss frames
    for i = 1, 5 do
        local unit = "boss"..i
        if UnitExists(unit) then
            UpdateHealthText(_G["Boss"..i.."TargetFrame"], unit)
            UpdateManaText(_G["Boss"..i.."TargetFrame"], unit)
        end
    end
    
    -- Arena frames
    for i = 1, 5 do
        local unit = "arena"..i
        if UnitExists(unit) then
            UpdateHealthText(_G["ArenaEnemyMatchFrame"..i], unit)
            UpdateManaText(_G["ArenaEnemyMatchFrame"..i], unit)
        end
    end
end)

-- Hook individual frame updates with a more targeted approach
local function SetupHealthTextHooks()
    -- Helper function to override text on a healthbar
    local function OverrideHealthText(healthBar, unit)
        if healthBar and healthBar.TextString and unit then
            -- Store the original SetText function
            local originalSetText = healthBar.TextString.SetText
            
            -- Override SetText to format our way
            healthBar.TextString.SetText = function(self, text)
                if UnitExists(unit) then
                    local current = UnitHealth(unit)
                    originalSetText(self, FormatHealth(current))
                else
                    originalSetText(self, text)
                end
            end
            
            -- Update immediately
            if UnitExists(unit) then
                local current = UnitHealth(unit)
                healthBar.TextString:SetText(FormatHealth(current))
            end
        end
    end
    
    -- Helper function to override text on a manabar
    local function OverrideManaText(manaBar, unit)
        if manaBar and manaBar.TextString and unit then
            -- Store the original SetText function
            local originalSetText = manaBar.TextString.SetText
            
            -- Override SetText to format our way
            manaBar.TextString.SetText = function(self, text)
                if UnitExists(unit) then
                    local current = UnitPower(unit)
                    originalSetText(self, FormatHealth(current)) -- Using same format function
                else
                    originalSetText(self, text)
                end
            end
            
            -- Update immediately
            if UnitExists(unit) then
                local current = UnitPower(unit)
                manaBar.TextString:SetText(FormatHealth(current))
            end
        end
    end
    
    -- Set up overrides for each frame type
    C_Timer.After(0.5, function()
        -- Player
        if PlayerFrame then
            if PlayerFrame.healthbar then
                OverrideHealthText(PlayerFrame.healthbar, "player")
            end
            if PlayerFrame.manabar then
                OverrideManaText(PlayerFrame.manabar, "player")
            end
        end
        
        -- Target
        if TargetFrame then
            if TargetFrame.healthbar then
                OverrideHealthText(TargetFrame.healthbar, "target")
            end
            if TargetFrame.manabar then
                OverrideManaText(TargetFrame.manabar, "target")
            end
        end
        
        -- Focus
        if FocusFrame then
            if FocusFrame.healthbar then
                OverrideHealthText(FocusFrame.healthbar, "focus")
            end
            if FocusFrame.manabar then
                OverrideManaText(FocusFrame.manabar, "focus")
            end
        end
        
        -- Pet
        if PetFrame then
            if PetFrame.healthbar then
                OverrideHealthText(PetFrame.healthbar, "pet")
            end
            if PetFrame.manabar then
                OverrideManaText(PetFrame.manabar, "pet")
            end
        end
        
        -- Boss Frames
        for i = 1, 5 do
            local frame = _G["Boss"..i.."TargetFrame"]
            if frame then
                if frame.healthbar then
                    OverrideHealthText(frame.healthbar, "boss"..i)
                end
                if frame.manabar then
                    OverrideManaText(frame.manabar, "boss"..i)
                end
            end
        end
        
        -- Arena Frames
        for i = 1, 5 do
            local frame = _G["ArenaEnemyMatchFrame"..i]
            if frame then
                if frame.healthbar then
                    OverrideHealthText(frame.healthbar, "arena"..i)
                end
                if frame.manabar then
                    OverrideManaText(frame.manabar, "arena"..i)
                end
            end
        end
    end)
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

-- Call the setup function
SetupHealthTextHooks()

-- Setup event frame for initialization
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Initialize Profile Installer
        if addon.ProfileInstaller then
            addon.ProfileInstaller:Initialize()
        end
        
        -- Continue with normal mUI initialization
        C_Timer.After(0.1, function()
            ColorAllFrames()
            ColorMirrorTimers()
            ColorCastingBars()
            StyleBuffsAndDebuffs()
            HookAuraFrames()
            ColorContainerFrames()
            StyleActionBars()
        end)
    end
end)