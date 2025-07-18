-- MelloUI Dungeon Teleporter Module
local addonName, ns = ...
local DungeonTeleporter = {}

-- Spell IDs for teleport buttons (matching icon spell IDs)
local TELEPORT_SPELLS = {
    354467,   -- Button 1: Theater of Pain (matching icon)
    445444,   -- Button 2: Priory of the Sacred Flame (matching icon)
    445440,   -- Button 3: Cinderbrew Meadery (matching icon)
    445443,   -- Button 4: The Rookery (matching icon)
    373274,   -- Button 5: Operation: Mechagon - Workshop (matching icon)
    467555,   -- Button 6: The MOTHERLODE!! (matching icon)
    1216786,  -- Button 7: Operation: Floodgate (matching icon)
    445441,   -- Button 8: Darkflame Cleft (matching icon)
}

-- Current Mythic+ dungeon icons (matching in-game order)
local DUNGEON_ICONS = {
    3759934,  -- Button 1: Theater of Pain (correct)
    5926521,  -- Button 2: Priory of the Sacred Flame (TWW dungeon icon)
    5926522,  -- Button 3: Cinderbrew Meadery
    5926520,  -- Button 4: The Rookery
    2915720,  -- Button 5: Operation: Mechagon - Workshop
    2065640,  -- Button 6: The MOTHERLODE!!
    5926519,  -- Button 7: Operation: Floodgate
    5926518,  -- Button 8: Darkflame Cleft
}

-- Dungeon abbreviations
local DUNGEON_ABBREVIATIONS = {
    "ToT",   -- Theater of Pain
    "PSF",   -- Priory of the Sacred Flame
    "CM",    -- Cinderbrew Meadery
    "Rook",  -- The Rookery
    "OMW",   -- Operation: Mechagon - Workshop
    "ML",    -- The MOTHERLODE!!
    "OF",    -- Operation: Floodgate
    "DFC",   -- Darkflame Cleft
}

-- Module variables
local iconContainer = nil
local teleportButtons = {}
local hooksApplied = false
local updateTimerHandle = nil

-- Create the round icon container
local function CreateIconContainer()
    if iconContainer then return iconContainer end
    
    -- Create container frame
    iconContainer = CreateFrame("Frame", "MelloUIDungeonTeleporterIcon", UIParent)
    iconContainer:SetSize(64, 64)
    iconContainer:SetFrameStrata("HIGH")
    iconContainer:SetFrameLevel(100)
    
    -- Create round black background (scaled down by 20%)
    local blackBg = iconContainer:CreateTexture(nil, "BACKGROUND")
    blackBg:SetSize(51.2, 51.2) -- 64 * 0.8 = 51.2
    blackBg:SetPoint("CENTER", 0, 0)
    blackBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    blackBg:SetVertexColor(0, 0, 0, 0.5) -- Black with 50% transparency
    
    -- Create a mask to make the black background round
    local blackMask = iconContainer:CreateMaskTexture()
    blackMask:SetAllPoints(blackBg)
    blackMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    blackBg:AddMaskTexture(blackMask)
    
    -- Add "TP" text
    local tpText = iconContainer:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tpText:SetPoint("CENTER", 3, 0)
    tpText:SetText("TP")
    tpText:SetFont(tpText:GetFont(), 15, "OUTLINE")
    tpText:SetTextColor(1, 1, 0, 1) -- Yellow text
    
    -- Add border
    local border = iconContainer:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetTexCoord(0.0, 0.6, 0.0, 0.6)
    
    -- Tooltip
    iconContainer:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mythic+ Teleports", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    iconContainer:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    return iconContainer
end

-- Create action bar style button
local function CreateTeleportButton(index, spellID, parent)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetSize(40, 40) -- Standard action button size
    
    -- Position below the icon
    if index == 1 then
        button:SetPoint("TOP", parent, "BOTTOM", 0, -5)
    else
        button:SetPoint("TOP", teleportButtons[index-1], "BOTTOM", 0, -3)
    end
    
    -- IMPORTANT: Set up secure attributes FIRST before any other code
    -- Special handling for button 6 (MOTHERLODE/Azerite Refinery)
    if index == 6 then
        -- Try using the spell name instead of ID for this specific spell
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", "Path of the Azerite Refinery")
    else
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/cast [@player] " .. spellID)
        
        -- Also try direct spell casting as backup
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", spellID)
    end
    
    -- Enable mouse interaction
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp", "AnyDown")
    
    -- Check spell validity silently
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    
    -- Create icon texture
    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    
    -- Use custom dungeon icon
    local iconTexture = DUNGEON_ICONS[index]
    
    -- Special cases for specific buttons using spell icons
    if index == 2 then
        local priorySpellInfo = C_Spell.GetSpellInfo(445444)
        if priorySpellInfo then
            button.icon:SetTexture(priorySpellInfo.iconID)
            button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    elseif index == 3 then
        local cinderbrewSpellInfo = C_Spell.GetSpellInfo(445440)
        if cinderbrewSpellInfo then
            button.icon:SetTexture(cinderbrewSpellInfo.iconID)
            button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    elseif index == 4 then
        local rookerySpellInfo = C_Spell.GetSpellInfo(445443)
        if rookerySpellInfo then
            button.icon:SetTexture(rookerySpellInfo.iconID)
            button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    elseif index == 5 then
        local mechagonSpellInfo = C_Spell.GetSpellInfo(373274)
        if mechagonSpellInfo then
            button.icon:SetTexture(mechagonSpellInfo.iconID)
            button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    elseif index == 6 then
        local motherlodeSpellInfo = C_Spell.GetSpellInfo(467555)
        if motherlodeSpellInfo then
            button.icon:SetTexture(motherlodeSpellInfo.iconID)
            button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    elseif index == 7 then
        local floodgateSpellInfo = C_Spell.GetSpellInfo(1216786)
        if floodgateSpellInfo then
            button.icon:SetTexture(floodgateSpellInfo.iconID)
            button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    elseif index == 8 then
        local darkflameSpellInfo = C_Spell.GetSpellInfo(445441)
        if darkflameSpellInfo then
            button.icon:SetTexture(darkflameSpellInfo.iconID)
            button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    elseif iconTexture then
        button.icon:SetTexture(iconTexture)
        button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    else
        -- Fallback to spell icon if no custom icon
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then
            button.icon:SetTexture(spellInfo.iconID)
            button.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        end
    end
    
    -- Create border texture
    local border = button:CreateTexture(nil, "ARTWORK")
    border:SetPoint("TOPLEFT", -13, 11)
    border:SetPoint("BOTTOMRIGHT", 15, -13)
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    
    -- Create highlight texture
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.3)
    
    -- Create pushed texture
    local pushed = button:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    pushed:Hide()
    
    -- Show/hide pushed texture on click
    button:SetScript("OnMouseDown", function(self) pushed:Show() end)
    button:SetScript("OnMouseUp", function(self) pushed:Hide() end)
    
    -- Add dungeon abbreviation text
    local textBg = button:CreateTexture(nil, "ARTWORK")
    textBg:SetColorTexture(0, 0, 0, 0.5) -- Black 50% transparent
    textBg:SetHeight(12)
    textBg:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    textBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    
    local dungeonText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dungeonText:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
    dungeonText:SetText(DUNGEON_ABBREVIATIONS[index])
    dungeonText:SetFont(dungeonText:GetFont(), 10, "OUTLINE")
    dungeonText:SetTextColor(1, 1, 1, 1) -- White text
    
    -- Check if spell is usable (account-wide teleports)
    -- Initial check may fail on first login, will be updated later
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local isKnown = spellInfo and C_Spell.IsSpellUsable(spellID)
    
    -- Create lock overlay (hidden by default)
    local lock = button:CreateTexture(nil, "OVERLAY")
    lock:SetSize(20, 20)
    lock:SetPoint("CENTER", 3, -1)
    lock:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
    lock:Hide()
    button.lockIcon = lock
    
    -- Store spell ID first
    button.spellID = spellID
    
    -- Function to update button state
    button.UpdateSpellState = function(self)
        local spellInfo = C_Spell.GetSpellInfo(self.spellID)
        local isUsable = spellInfo and C_Spell.IsSpellUsable(self.spellID)
        self.isKnown = isUsable
        
        if isUsable then
            -- Spell is known
            self.icon:SetDesaturated(false)
            self.icon:SetVertexColor(1, 1, 1)
            if self.lockIcon then
                self.lockIcon:Hide()
            end
            if self.cooldownText then
                self.cooldownText:Show()
            end
        else
            -- Spell is not known
            self.icon:SetDesaturated(true)
            self.icon:SetVertexColor(0.5, 0.5, 0.5)
            if self.lockIcon then
                self.lockIcon:Show()
            end
            if self.cooldownText then
                self.cooldownText:Hide()
            end
        end
    end
    
    -- Initial state update
    button:UpdateSpellState()
    
    -- Tooltip and cooldown update
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.isKnown then
            GameTooltip:SetSpellByID(self.spellID)
        else
            GameTooltip:SetText("Teleport Locked", 1, 0.5, 0)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("This teleport is not yet unlocked.", 1, 1, 1)
            GameTooltip:AddLine("Complete the dungeon on Mythic +10 difficulty to unlock.", 0, 1, 0)
        end
        GameTooltip:Show()
    end)
    
    button:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Create cooldown timer text
    local cooldownText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cooldownText:SetPoint("TOP", button, "TOP", 0, -8)
    cooldownText:SetFont(cooldownText:GetFont(), 15, "OUTLINE")
    cooldownText:SetTextColor(1, 1, 0, 1) -- Yellow text
    button.cooldownText = cooldownText
    
    -- isKnown is already set by UpdateSpellState()
    
    return button
end

-- Cooldown update function
local function UpdateCooldowns()
    local hasActiveCooldown = false
    
    -- Update all buttons
    for i = 1, 8 do
        local button = teleportButtons[i]
        if button and button.isKnown and button.spellID then
            local spellCooldownInfo = C_Spell.GetSpellCooldown(button.spellID)
            if spellCooldownInfo and spellCooldownInfo.duration > 0 then
                -- Calculate remaining time
                local remaining = spellCooldownInfo.startTime + spellCooldownInfo.duration - GetTime()
                if remaining > 0 then
                    hasActiveCooldown = true
                    -- Desaturate icon during cooldown
                    button.icon:SetDesaturated(true)
                    
                    -- Format and show cooldown time
                    local timeText
                    if remaining >= 60 then
                        timeText = string.format("%dm", math.ceil(remaining / 60))
                    else
                        timeText = string.format("%d", math.ceil(remaining))
                    end
                    button.cooldownText:SetText(timeText)
                    button.cooldownText:Show()
                else
                    -- Cooldown finished
                    button.icon:SetDesaturated(false)
                    button.cooldownText:Hide()
                end
            else
                -- No cooldown
                button.icon:SetDesaturated(false)
                button.cooldownText:Hide()
            end
        end
    end
    
    return hasActiveCooldown
end

-- Start/stop cooldown timer based on need
local function StartCooldownTimer()
    if updateTimerHandle then return end -- Already running
    
    local function TimerCallback()
        if not iconContainer or not iconContainer:IsShown() then
            StopCooldownTimer()
            return
        end
        
        local hasActiveCooldown = UpdateCooldowns()
        if hasActiveCooldown then
            updateTimerHandle = C_Timer.NewTimer(0.5, TimerCallback)
        else
            updateTimerHandle = nil
        end
    end
    
    -- Initial update
    local hasActiveCooldown = UpdateCooldowns()
    if hasActiveCooldown then
        updateTimerHandle = C_Timer.NewTimer(0.5, TimerCallback)
    end
end

local function StopCooldownTimer()
    if updateTimerHandle then
        updateTimerHandle:Cancel()
        updateTimerHandle = nil
    end
end

-- Position the container relative to PVE Frame
local function PositionContainer()
    if not iconContainer or not PVEFrame then return end
    
    -- Clear any existing points
    iconContainer:ClearAllPoints()
    
    -- Anchor to the top-right of PVE Frame, outside the window
    iconContainer:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", 10, -5)
end

-- Hook into the PVE Frame (Dungeon Finder)
local function HookPVEFrame()
    if hooksApplied then return end -- Prevent duplicate hooks
    
    -- Hook the toggle function that opens/closes the dungeon finder
    hooksecurefunc("ToggleLFDParentFrame", function()
        C_Timer.After(0.1, function()
            if PVEFrame and PVEFrame:IsShown() and iconContainer then
                PositionContainer()
                iconContainer:Show()
                StartCooldownTimer()
            elseif iconContainer then
                iconContainer:Hide()
                StopCooldownTimer()
            end
        end)
    end)
    
    -- Also hook the PVE frame if it exists
    if PVEFrame then
        -- Show when PVE Frame is shown
        hooksecurefunc(PVEFrame, "Show", function()
            if iconContainer then
                PositionContainer()
                iconContainer:Show()
                StartCooldownTimer()
            end
        end)
        
        -- Hide when PVE Frame is hidden
        hooksecurefunc(PVEFrame, "Hide", function()
            if iconContainer then
                iconContainer:Hide()
                StopCooldownTimer()
            end
        end)
        
        -- Check if PVE Frame is already open
        if PVEFrame:IsShown() and iconContainer then
            PositionContainer()
            iconContainer:Show()
            StartCooldownTimer()
        end
    end
    
    hooksApplied = true
end

-- Update all button states (called after spells are loaded)
local function UpdateAllButtonStates()
    for i = 1, 8 do
        local button = teleportButtons[i]
        if button and button.UpdateSpellState then
            button:UpdateSpellState()
        end
    end
end

-- Cleanup function
local function CleanupAddon()
    StopCooldownTimer()
    if iconContainer then
        iconContainer:Hide()
    end
end

function DungeonTeleporter:OnInitialize()
    -- Create the icon container
    local container = CreateIconContainer()
    
    -- Create 8 teleport buttons
    for i = 1, 8 do
        teleportButtons[i] = CreateTeleportButton(i, TELEPORT_SPELLS[i], container)
    end
    
    -- Hide initially (will show when PVE frame opens)
    container:Hide()
    
    -- Try to hook immediately
    HookPVEFrame()
    
    -- Single delayed attempt if UI isn't loaded yet
    if not PVEFrame then
        C_Timer.After(2, function()
            if not hooksApplied then
                HookPVEFrame()
            end
        end)
    end
    
    -- Register for events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:RegisterEvent("SPELLS_CHANGED")
    self.eventFrame:SetScript("OnEvent", function(frame, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 == "Blizzard_LookingForGroupUI" or arg1 == "Blizzard_PVPUI" then
                if not hooksApplied then
                    HookPVEFrame()
                end
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Update button states after entering world (with delay for spell system)
            C_Timer.After(1, UpdateAllButtonStates)
        elseif event == "SPELLS_CHANGED" then
            -- Update button states when spells change
            UpdateAllButtonStates()
        end
    end)
    
    -- Slash commands
    SLASH_MDUNGEONTELEPORTER1 = "/mdt"
    SLASH_MDUNGEONTELEPORTER2 = "/mph"
    SlashCmdList["MDUNGEONTELEPORTER"] = function(msg)
        if msg == "reset" then
            if iconContainer and PVEFrame then
                PositionContainer()
            end
        elseif msg == "toggle" then
            -- Force toggle visibility (for debugging)
            if iconContainer then
                if iconContainer:IsShown() then
                    iconContainer:Hide()
                else
                    iconContainer:Show()
                end
            end
        elseif msg == "cleanup" then
            -- Manual cleanup command
            CleanupAddon()
        end
    end
end

function DungeonTeleporter:OnEnable()
    -- Module enabled
end

function DungeonTeleporter:OnDisable()
    -- Module disabled
    CleanupAddon()
end

-- Register the module
ns:RegisterModule("DungeonTeleporter", DungeonTeleporter)