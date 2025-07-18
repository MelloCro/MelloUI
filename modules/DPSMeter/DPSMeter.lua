-- MelloUI DPS Meter Module
local addonName, ns = ...
local DPSMeter = {}
ns:RegisterModule("DPSMeter", DPSMeter)

-- Module-specific variables
local isEnabled = false
local frame = CreateFrame("Frame")
local combatData = {}
local healingData = {}
local overallData = {}
local currentEncounter = nil
local updateInterval = 1.0
local timeSinceLastUpdate = 0
local inCombat = false
local instanceStartTime = nil
local totalCombatTime = 0
local combatStartTime = nil
local testPlayerClasses = {}
local testPlayerUnits = {}

-- Memory management settings
local MAX_PLAYERS_TRACKED = 50
local MAX_SPELLS_PER_PLAYER = 20
local DATA_CLEANUP_INTERVAL = 300
local INACTIVE_PLAYER_TIMEOUT = 300
local lastCleanupTime = 0

-- Caches to reduce allocations
local stringCache = {}
local petOwnerCache = {}
local spellIconCache = setmetatable({}, {__mode = "v"})

-- Frame pools for detail windows
local framePool = {}
local activeFrames = {}

-- Default settings
local defaults = {
    texture = "Interface\\BUTTONS\\WHITE8X8",
    font = "Fonts\\FRIZQT__.TTF",
    fontSize = 11,
    fontColor = { r = 1, g = 1, b = 1 },
    opacity = 1.0,
    borderOpacity = 1.0,
    buttonOpacity = 0.0,
    useClassColors = true,
    barHeight = 20,
    barSpacing = 1,
    showButtons = true,
    windowLocked = true,
    updateInterval = 0.50,
    windowPosition = nil,
    -- Removed glow settings for cleaner appearance
}

-- Available textures
local textures = {
    ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Smooth"] = "Interface\\Buttons\\WHITE8X8",
    ["Minimalist"] = "Interface\\BUTTONS\\WHITE8X8",
    ["Solid"] = "Interface\\BUTTONS\\WHITE8X8",
    ["Frost"] = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    ["Graphite"] = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
}

-- Available fonts
local fonts = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial"] = "Fonts\\ARIALN.TTF",
    ["Skurri"] = "Fonts\\SKURRI.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF"
}

-- Glow textures removed for cleaner appearance

-- Function to get a frame from the pool
local function GetPooledFrame(parent)
    local frame = table.remove(framePool)
    if not frame then
        frame = CreateFrame("Frame", nil, parent)
        frame:SetHeight(40)
        
        -- Background
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        frame.bg = bg
        
        -- Progress bar background removed
        
        -- Progress bar
        local progressBar = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        progressBar:SetPoint("TOPLEFT", progressBg, "TOPLEFT", 0, 0)
        progressBar:SetPoint("BOTTOM", progressBg, "BOTTOM", 0, 0)
        progressBar:SetWidth(1)
        frame.progressBar = progressBar
        
        -- Spell icon
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(32, 32)
        icon:SetPoint("LEFT", frame, "LEFT", 5, 0)
        icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        frame.icon = icon
        
        -- Spell name
        local spellName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        spellName:SetPoint("LEFT", icon, "RIGHT", 5, 8)
        spellName:SetJustifyH("LEFT")
        frame.spellName = spellName
        
        -- Damage amount
        local damageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        damageText:SetPoint("RIGHT", frame, "RIGHT", -10, 8)
        damageText:SetJustifyH("RIGHT")
        frame.damageText = damageText
        
        -- Hit count
        local hitText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hitText:SetPoint("LEFT", icon, "RIGHT", 5, -8)
        hitText:SetJustifyH("LEFT")
        hitText:SetTextColor(0.7, 0.7, 0.7)
        frame.hitText = hitText
        
        -- Average damage
        local avgText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        avgText:SetPoint("RIGHT", frame, "RIGHT", -10, -8)
        avgText:SetJustifyH("RIGHT")
        avgText:SetTextColor(0.7, 0.7, 0.7)
        frame.avgText = avgText
    end
    
    frame:SetParent(parent)
    frame:Show()
    table.insert(activeFrames, frame)
    return frame
end

-- Function to release frames back to the pool
local function ReleasePooledFrames()
    for _, frame in ipairs(activeFrames) do
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetParent(nil)
        table.insert(framePool, frame)
    end
    wipe(activeFrames)
end

-- Clean up old data
local function CleanupOldData()
    local currentTime = GetTime()
    
    -- Clean up combat data
    for guid, data in pairs(combatData) do
        if currentTime - data.lastUpdate > INACTIVE_PLAYER_TIMEOUT then
            combatData[guid] = nil
        else
            -- Limit spells per player
            if data.spells then
                local sortedSpells = {}
                for spellId, spellData in pairs(data.spells) do
                    table.insert(sortedSpells, {id = spellId, damage = spellData.damage, data = spellData})
                end
                table.sort(sortedSpells, function(a, b) return a.damage > b.damage end)
                
                -- Keep only top spells
                if #sortedSpells > MAX_SPELLS_PER_PLAYER then
                    for i = MAX_SPELLS_PER_PLAYER + 1, #sortedSpells do
                        data.spells[sortedSpells[i].id] = nil
                    end
                end
            end
        end
    end
    
    -- Clean up healing data
    for guid, data in pairs(healingData) do
        if currentTime - data.lastUpdate > INACTIVE_PLAYER_TIMEOUT then
            healingData[guid] = nil
        else
            -- Limit spells per player
            if data.spells then
                local sortedSpells = {}
                for spellId, spellData in pairs(data.spells) do
                    table.insert(sortedSpells, {id = spellId, healing = spellData.healing, data = spellData})
                end
                table.sort(sortedSpells, function(a, b) return a.healing > b.healing end)
                
                if #sortedSpells > MAX_SPELLS_PER_PLAYER then
                    for i = MAX_SPELLS_PER_PLAYER + 1, #sortedSpells do
                        data.spells[sortedSpells[i].id] = nil
                    end
                end
            end
        end
    end
    
    -- Clean up overall data
    for guid, data in pairs(overallData) do
        if currentTime - data.lastUpdate > INACTIVE_PLAYER_TIMEOUT * 2 then
            overallData[guid] = nil
        else
            -- Limit spells per player
            if data.spells then
                local sortedSpells = {}
                for spellId, spellData in pairs(data.spells) do
                    table.insert(sortedSpells, {id = spellId, damage = spellData.damage, data = spellData})
                end
                table.sort(sortedSpells, function(a, b) return a.damage > b.damage end)
                
                if #sortedSpells > MAX_SPELLS_PER_PLAYER then
                    for i = MAX_SPELLS_PER_PLAYER + 1, #sortedSpells do
                        data.spells[sortedSpells[i].id] = nil
                    end
                end
            end
        end
    end
    
    -- Limit total players tracked
    local function limitPlayers(dataTable)
        local playerCount = 0
        for _ in pairs(dataTable) do
            playerCount = playerCount + 1
        end
        
        if playerCount > MAX_PLAYERS_TRACKED then
            local sortedPlayers = {}
            for guid, data in pairs(dataTable) do
                table.insert(sortedPlayers, {guid = guid, lastUpdate = data.lastUpdate})
            end
            table.sort(sortedPlayers, function(a, b) return a.lastUpdate < b.lastUpdate end)
            
            -- Remove oldest players
            for i = 1, playerCount - MAX_PLAYERS_TRACKED do
                dataTable[sortedPlayers[i].guid] = nil
            end
        end
    end
    
    limitPlayers(combatData)
    limitPlayers(healingData)
    limitPlayers(overallData)
    
    -- Clear string cache periodically
    if next(stringCache) and currentTime % 60 < 1 then
        wipe(stringCache)
    end
    
    -- Clear pet owner cache for non-existent pets
    for petGUID, ownerInfo in pairs(petOwnerCache) do
        if currentTime - ownerInfo.time > 300 then
            petOwnerCache[petGUID] = nil
        end
    end
end

local function ResetCombatData()
    wipe(combatData)
    wipe(healingData)
    currentEncounter = nil  -- Set to nil instead of creating new encounter
    
    -- Clear test player classes when resetting combat data (except when generating test data)
    if not DPSMeter.generatingTestData then
        wipe(testPlayerClasses)
        wipe(testPlayerUnits)
    end
    
    -- Clear pet cache on combat reset
    wipe(petOwnerCache)
    
    -- Update display if DPSMeter exists
    if DPSMeter and DPSMeter.UpdateDisplay then
        DPSMeter:UpdateDisplay()
    end
end

local function ResetOverallData()
    wipe(overallData)
    instanceStartTime = GetTime()
    totalCombatTime = 0
    combatStartTime = nil
end

local function GetUnitName(guid)
    local name = select(6, strsplit("-", guid))
    return name or "Unknown"
end

-- Static unit list to avoid recreating
local unitList = {}
local function BuildUnitList()
    wipe(unitList)
    unitList[1] = "player"
    
    -- Add party members
    for i = 1, 4 do
        unitList[#unitList + 1] = "party" .. i
    end
    
    -- Add raid members
    for i = 1, 40 do
        unitList[#unitList + 1] = "raid" .. i
    end
end

-- Check if a GUID belongs to a group member
local function IsGroupMember(guid)
    -- Always include the player
    if guid == UnitGUID("player") then
        return true
    end
    
    -- Check if we're in a raid
    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then
                return true
            end
        end
    -- Check if we're in a party
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then
                return true
            end
        end
    end
    
    return false
end

-- Get owner information for pets with caching
local function GetPetOwner(petGUID, petFlags)
    -- Check cache first
    local cachedOwner = petOwnerCache[petGUID]
    if cachedOwner then
        return cachedOwner.ownerGUID, cachedOwner.ownerName
    end
    
    -- Check if this is a pet or guardian
    local isPet = bit.band(petFlags, COMBATLOG_OBJECT_TYPE_PET) > 0
    local isGuardian = bit.band(petFlags, COMBATLOG_OBJECT_TYPE_GUARDIAN) > 0
    
    if not (isPet or isGuardian) then
        return nil
    end
    
    -- Build unit list if needed
    if #unitList == 0 then
        BuildUnitList()
    end
    
    -- Check each unit's pet
    for _, unit in ipairs(unitList) do
        if UnitExists(unit) then
            local petUnit = unit .. "pet"
            if UnitExists(petUnit) and UnitGUID(petUnit) == petGUID then
                local ownerGUID = UnitGUID(unit)
                local ownerName = UnitName(unit)
                
                -- Cache the result
                petOwnerCache[petGUID] = {
                    ownerGUID = ownerGUID,
                    ownerName = ownerName,
                    time = GetTime()
                }
                
                return ownerGUID, ownerName
            end
        end
    end
    
    return nil
end

local function FormatDPS(dps)
    -- Handle nil or invalid values
    if not dps or type(dps) ~= "number" then
        return "0"
    end
    
    -- Check cache first
    local cacheKey = math.floor(dps)
    local cached = stringCache[cacheKey]
    if cached then
        return cached
    end
    
    local result
    if dps < 1000 then
        -- Under 1k, show exact number
        result = string.format("%.0f", dps)
    elseif dps < 1000000 then
        -- 1k to 999k, show as Xk
        result = string.format("%.0fk", dps / 1000)
    else
        -- 1m and above, show as X.Xm
        result = string.format("%.1fm", dps / 1000000)
    end
    
    -- Cache the result
    stringCache[cacheKey] = result
    return result
end

local function FormatTime(seconds)
    if seconds < 60 then
        return string.format("0:%02d", seconds)
    else
        local minutes = math.floor(seconds / 60)
        local secs = seconds % 60
        return string.format("%d:%02d", minutes, secs)
    end
end

-- Helper function to get spell icon texture with caching
local function GetSpellIcon(spellId)
    -- Check cache first
    local cached = spellIconCache[spellId]
    if cached then
        return cached
    end
    
    local icon
    
    -- Try C_Spell API first (most modern)
    if C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(spellId)
    end
    
    -- Fallback to GetSpellTexture
    if not icon and GetSpellTexture then
        icon = GetSpellTexture(spellId)
    end
    
    -- Fallback to GetSpellInfo for older versions
    if not icon and GetSpellInfo then
        local _, _, spellIcon = GetSpellInfo(spellId)
        icon = spellIcon
    end
    
    -- If still no icon, check for special spell IDs
    if not icon then
        -- Special handling for auto attacks and environmental damage
        local specialIcons = {
            [6603] = "Interface\\Icons\\INV_Sword_04", -- Auto Attack/Melee
            [75] = "Interface\\Icons\\INV_Weapon_Bow_07", -- Auto Shot
            [1] = "Interface\\Icons\\INV_Misc_QuestionMark", -- Environmental damage
        }
        icon = specialIcons[spellId]
    end
    
    -- Final fallback
    if not icon then
        icon = "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    
    -- Cache the result
    spellIconCache[spellId] = icon
    return icon
end

local function GetClassIcon(playerName)
    -- Try to get class info from unit
    local classIcons = {
        ["WARRIOR"] = "Interface\\Icons\\ClassIcon_Warrior",
        ["PALADIN"] = "Interface\\Icons\\ClassIcon_Paladin", 
        ["HUNTER"] = "Interface\\Icons\\ClassIcon_Hunter",
        ["ROGUE"] = "Interface\\Icons\\ClassIcon_Rogue",
        ["PRIEST"] = "Interface\\Icons\\ClassIcon_Priest",
        ["DEATHKNIGHT"] = "Interface\\Icons\\ClassIcon_DeathKnight",
        ["SHAMAN"] = "Interface\\Icons\\ClassIcon_Shaman",
        ["MAGE"] = "Interface\\Icons\\ClassIcon_Mage",
        ["WARLOCK"] = "Interface\\Icons\\ClassIcon_Warlock",
        ["MONK"] = "Interface\\Icons\\ClassIcon_Monk",
        ["DRUID"] = "Interface\\Icons\\ClassIcon_Druid",
        ["DEMONHUNTER"] = "Interface\\Icons\\ClassIcon_DemonHunter",
        ["EVOKER"] = "Interface\\Icons\\ClassIcon_Evoker"
    }
    
    -- Check if this is a test player first
    if testPlayerClasses[playerName] then
        return classIcons[testPlayerClasses[playerName]] or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    
    -- Check if player is the current player
    if playerName == UnitName("player") then
        local _, class = UnitClass("player")
        return classIcons[class] or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    
    -- Check raid/party
    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitName(unit) == playerName then
                local _, class = UnitClass(unit)
                return classIcons[class] or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitName(unit) == playerName then
                local _, class = UnitClass(unit)
                return classIcons[class] or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
        end
    end
    
    -- Check test units
    for unit, name in pairs(testPlayerUnits) do
        if name == playerName and UnitExists(unit) then
            local _, class = UnitClass(unit)
            return classIcons[class] or "Interface\\Icons\\INV_Misc_QuestionMark"
        end
    end
    
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function FormatNumber(number)
    if number >= 1000000000 then
        return string.format("%.2fb", number / 1000000000)
    elseif number >= 1000000 then
        return string.format("%.2fm", number / 1000000)
    elseif number >= 1000 then
        return string.format("%.1fk", number / 1000)
    else
        return tostring(number)
    end
end

local function GetClassColor(class)
    local classColors = {
        ["WARRIOR"] = {r = 0.78, g = 0.61, b = 0.43},
        ["PALADIN"] = {r = 0.96, g = 0.55, b = 0.73},
        ["HUNTER"] = {r = 0.67, g = 0.83, b = 0.45},
        ["ROGUE"] = {r = 1.00, g = 0.96, b = 0.41},
        ["PRIEST"] = {r = 1.00, g = 1.00, b = 1.00},
        ["DEATHKNIGHT"] = {r = 0.77, g = 0.12, b = 0.23},
        ["SHAMAN"] = {r = 0.00, g = 0.44, b = 0.87},
        ["MAGE"] = {r = 0.25, g = 0.78, b = 0.92},
        ["WARLOCK"] = {r = 0.53, g = 0.53, b = 0.93},
        ["MONK"] = {r = 0.00, g = 1.00, b = 0.59},
        ["DRUID"] = {r = 1.00, g = 0.49, b = 0.04},
        ["DEMONHUNTER"] = {r = 0.64, g = 0.19, b = 0.79},
        ["EVOKER"] = {r = 0.20, g = 0.58, b = 0.50}
    }
    
    return classColors[class] or {r = 0.5, g = 0.5, b = 0.5}
end

-- Combat log event handler
local function OnCombatLogEvent(...)
    local timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = ...
    
    -- Check if source is a player, pet, or guardian
    local isPlayer = bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
    local isPet = bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) > 0
    local isGuardian = bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_GUARDIAN) > 0
    
    if not (isPlayer or isPet or isGuardian) then
        return
    end
    
    -- Only track group members
    if not IsGroupMember(sourceGUID) then
        -- If it's a pet, check if the owner is a group member
        if isPet or isGuardian then
            local ownerGUID = GetPetOwner(sourceGUID, sourceFlags)
            if not ownerGUID or not IsGroupMember(ownerGUID) then
                return
            end
        else
            return
        end
    end
    
    -- Handle pet attribution
    local actualSourceGUID = sourceGUID
    local actualSourceName = sourceName
    
    if isPet or isGuardian then
        local ownerGUID, ownerName = GetPetOwner(sourceGUID, sourceFlags)
        if ownerGUID then
            actualSourceGUID = ownerGUID
            actualSourceName = ownerName
        end
    end
    
    -- Track damage events
    local amount = 0
    local spellId = nil
    local spellName = nil
    local isDamage = false
    local isHealing = false
    
    if subevent == "SWING_DAMAGE" then
        amount = select(12, ...)
        spellId = 6603  -- Melee swing
        spellName = "Melee"
        isDamage = true
    elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "RANGE_DAMAGE" then
        spellId, spellName = select(12, ...), select(13, ...)
        amount = select(15, ...)
        isDamage = true
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        spellId, spellName = select(12, ...), select(13, ...)
        amount = select(15, ...)
        local overheal = select(16, ...)
        amount = amount - overheal  -- Only count effective healing
        isHealing = true
        
        -- Don't count healing on enemies
        if bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0 then
            isHealing = false
        end
    elseif subevent == "DAMAGE_SHIELD" then
        spellId, spellName = select(12, ...), select(13, ...)
        amount = select(15, ...)
        isDamage = true
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
        local environmentalType = select(12, ...)
        amount = select(13, ...)
        spellId = 1
        spellName = _G["ACTION_ENVIRONMENTAL_DAMAGE_"..environmentalType] or "Environmental"
        isDamage = true
    end
    
    -- Update damage data
    if isDamage and amount > 0 then
        -- Initialize player data if needed
        if not combatData[actualSourceGUID] then
            combatData[actualSourceGUID] = {
                name = actualSourceName,
                damage = 0,
                dps = 0,
                spells = {},
                lastUpdate = GetTime()
            }
        end
        
        -- Update damage totals
        combatData[actualSourceGUID].damage = combatData[actualSourceGUID].damage + amount
        combatData[actualSourceGUID].lastUpdate = GetTime()
        
        -- Update spell data
        if spellId then
            if not combatData[actualSourceGUID].spells[spellId] then
                combatData[actualSourceGUID].spells[spellId] = {
                    name = spellName or "Unknown",
                    damage = 0,
                    hits = 0
                }
            end
            combatData[actualSourceGUID].spells[spellId].damage = combatData[actualSourceGUID].spells[spellId].damage + amount
            combatData[actualSourceGUID].spells[spellId].hits = combatData[actualSourceGUID].spells[spellId].hits + 1
        end
        
        -- Update overall data
        if not overallData[actualSourceGUID] then
            overallData[actualSourceGUID] = {
                name = actualSourceName,
                damage = 0,
                dps = 0,
                spells = {},
                lastUpdate = GetTime()
            }
        end
        
        overallData[actualSourceGUID].damage = overallData[actualSourceGUID].damage + amount
        overallData[actualSourceGUID].lastUpdate = GetTime()
        
        -- Update overall spell data
        if spellId then
            if not overallData[actualSourceGUID].spells[spellId] then
                overallData[actualSourceGUID].spells[spellId] = {
                    name = spellName or "Unknown",
                    damage = 0,
                    hits = 0
                }
            end
            overallData[actualSourceGUID].spells[spellId].damage = overallData[actualSourceGUID].spells[spellId].damage + amount
            overallData[actualSourceGUID].spells[spellId].hits = overallData[actualSourceGUID].spells[spellId].hits + 1
        end
    end
    
    -- Update healing data
    if isHealing and amount > 0 then
        -- Initialize healer data if needed
        if not healingData[actualSourceGUID] then
            healingData[actualSourceGUID] = {
                name = actualSourceName,
                healing = 0,
                hps = 0,
                spells = {},
                lastUpdate = GetTime()
            }
        end
        
        -- Update healing totals
        healingData[actualSourceGUID].healing = healingData[actualSourceGUID].healing + amount
        healingData[actualSourceGUID].lastUpdate = GetTime()
        
        -- Update spell data
        if spellId then
            if not healingData[actualSourceGUID].spells[spellId] then
                healingData[actualSourceGUID].spells[spellId] = {
                    name = spellName or "Unknown",
                    healing = 0,
                    hits = 0
                }
            end
            healingData[actualSourceGUID].spells[spellId].healing = healingData[actualSourceGUID].spells[spellId].healing + amount
            healingData[actualSourceGUID].spells[spellId].hits = healingData[actualSourceGUID].spells[spellId].hits + 1
        end
    end
end

-- Update DPS calculations
local function UpdateDPS()
    local currentTime = GetTime()
    if not currentEncounter or not currentEncounter.startTime then return end
    
    local combatDuration = currentTime - currentEncounter.startTime
    if combatDuration <= 0 then return end
    
    -- Update DPS for combat data
    for guid, data in pairs(combatData) do
        data.dps = data.damage / combatDuration
    end
    
    -- Update HPS for healing data
    for guid, data in pairs(healingData) do
        data.hps = data.healing / combatDuration
    end
    
    -- Update overall DPS
    if instanceStartTime then
        local overallDuration = totalCombatTime
        if inCombat then
            overallDuration = overallDuration + combatDuration
        end
        
        if overallDuration > 0 then
            for guid, data in pairs(overallData) do
                data.dps = data.damage / overallDuration
            end
        end
    end
end

function DPSMeter:OnInitialize()
    -- Initialize SavedVariables
    MelloUISavedVars.DPSMeter = MelloUISavedVars.DPSMeter or {}
    local db = MelloUISavedVars.DPSMeter
    
    -- Apply defaults
    for k, v in pairs(defaults) do
        if db[k] == nil then
            db[k] = v
        end
    end
    
    -- Store reference
    self.db = db
end

function DPSMeter:OnEnable()
    if isEnabled then return end
    isEnabled = true
    
    -- Register events
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("CHALLENGE_MODE_START")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLogEvent(CombatLogGetCurrentEventInfo())
        elseif event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            -- Only reset if we don't have an active encounter
            if not currentEncounter then
                ResetCombatData()
                -- Create new encounter after reset
                currentEncounter = {
                    startTime = GetTime(),
                    endTime = nil,
                    duration = 0
                }
            end
            combatStartTime = GetTime()
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            if currentEncounter and currentEncounter.startTime then
                currentEncounter.endTime = GetTime()
                currentEncounter.duration = currentEncounter.endTime - currentEncounter.startTime
                if currentEncounter.duration > 0 then
                    totalCombatTime = totalCombatTime + currentEncounter.duration
                end
            end
            UpdateDPS()
            DPSMeter:UpdateDisplay()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Delay reset to avoid initialization issues
            C_Timer.After(0.1, function()
                ResetCombatData()
                local _, instanceType = IsInInstance()
                if instanceType ~= "none" then
                    ResetOverallData()
                end
            end)
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            local _, instanceType = IsInInstance()
            if instanceType ~= "none" then
                if not instanceStartTime then
                    ResetOverallData()
                end
            else
                instanceStartTime = nil
            end
        elseif event == "CHALLENGE_MODE_START" or event == "ENCOUNTER_START" then
            ResetCombatData()
            if not instanceStartTime then
                ResetOverallData()
            end
            -- Create new encounter for these events
            currentEncounter = {
                startTime = GetTime(),
                endTime = nil,
                duration = 0
            }
        elseif event == "ENCOUNTER_END" then
            if currentEncounter and currentEncounter.startTime and not currentEncounter.endTime then
                currentEncounter.endTime = GetTime()
                currentEncounter.duration = currentEncounter.endTime - currentEncounter.startTime
                if currentEncounter.duration > 0 then
                    totalCombatTime = totalCombatTime + currentEncounter.duration
                end
            end
            UpdateDPS()
            DPSMeter:UpdateDisplay()
        end
    end)
    
    -- Set up update handler
    frame:SetScript("OnUpdate", function(self, elapsed)
        timeSinceLastUpdate = timeSinceLastUpdate + elapsed
        
        if timeSinceLastUpdate >= (DPSMeter.db.updateInterval or defaults.updateInterval) then
            timeSinceLastUpdate = 0
            
            if inCombat or (currentEncounter and GetTime() - currentEncounter.startTime < 5) then
                UpdateDPS()
                DPSMeter:UpdateDisplay()
            end
            
            -- Periodic cleanup
            local currentTime = GetTime()
            if currentTime - lastCleanupTime > DATA_CLEANUP_INTERVAL then
                lastCleanupTime = currentTime
                CleanupOldData()
            end
        end
    end)
    
    -- Create main window
    self:CreateMainWindow()
    
    -- Show window
    if self.mainFrame then
        self.mainFrame:Show()
    end
    
    -- Reset data
    ResetCombatData()
    ResetOverallData()
end

function DPSMeter:OnDisable()
    if not isEnabled then return end
    isEnabled = false
    
    -- Unregister events
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    frame:SetScript("OnUpdate", nil)
    
    -- Hide windows
    if self.mainFrame then self.mainFrame:Hide() end
    if self.healingFrame then self.healingFrame:Hide() end
    if self.overallFrame then self.overallFrame:Hide() end
    if self.detailFrame then self.detailFrame:Hide() end
    if self.healingDetailFrame then self.healingDetailFrame:Hide() end
    if self.overallDetailFrame then self.overallDetailFrame:Hide() end
    if self.settingsFrame then self.settingsFrame:Hide() end
end

function DPSMeter:CreateMainWindow()
    if self.mainFrame then return end
    
    local mainFrame = CreateFrame("Frame", "MelloUIDPSMeterFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(250, 200)
    
    -- Restore saved position or use default
    if self.db.windowPosition then
        local pos = self.db.windowPosition
        mainFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    mainFrame:SetBackdropColor(0, 0, 0, self.db.opacity or 0.8)
    mainFrame:SetBackdropBorderColor(1, 1, 1, self.db.borderOpacity or 1.0)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if not DPSMeter.db.windowLocked then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, relativePoint, x, y = self:GetPoint()
        DPSMeter.db.windowPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
    end)
    
    -- Create a clickable title frame
    local titleFrame = CreateFrame("Button", nil, mainFrame)
    titleFrame:SetSize(100, 20)
    titleFrame:SetPoint("TOP", mainFrame, "TOP", 0, -10)
    titleFrame:RegisterForClicks("RightButtonUp")
    titleFrame:EnableMouse(true)
    
    local title = titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetAllPoints()
    title:SetText("DPS Meter")
    
    titleFrame:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            DPSMeter:ShowMenu()
        end
    end)
    
    -- Timer text
    local timerText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerText:SetPoint("TOP", title, "BOTTOM", 0, -2)
    timerText:SetTextColor(0.7, 0.7, 0.7)
    mainFrame.timerText = timerText
    
    local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -2, -2)
    closeButton:SetSize(24, 24)
    
    -- Create scroll frame without visible scrollbar
    local scrollFrame = CreateFrame("ScrollFrame", nil, mainFrame)
    scrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 10)
    scrollFrame:EnableMouse(true)
    
    -- Create content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(230)  -- Width accounts for potential scrollbar
    content:SetHeight(1)  -- Will be set dynamically
    scrollFrame:SetScrollChild(content)
    scrollFrame.content = content
    
    -- Store references
    mainFrame.scrollFrame = scrollFrame
    mainFrame.content = content
    mainFrame.bars = {}
    
    self.mainFrame = mainFrame
    
    -- Enable mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self.maxScroll or 0
        
        if delta > 0 then
            self:SetVerticalScroll(math.max(0, current - 30))
        else
            self:SetVerticalScroll(math.min(maxScroll, current + 30))
        end
    end)
end

function DPSMeter:CreateBarFrame(parent, index)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(self.db.barHeight or defaults.barHeight)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ((self.db.barHeight or defaults.barHeight) + (self.db.barSpacing or defaults.barSpacing)))
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * ((self.db.barHeight or defaults.barHeight) + (self.db.barSpacing or defaults.barSpacing)))
    
    -- No glow effect
    
    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    bar.bg = bg
    
    -- Status bar
    local statusBar = bar:CreateTexture(nil, "ARTWORK")
    statusBar:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    statusBar:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    statusBar:SetTexture(self.db.texture or defaults.texture)
    statusBar:SetHeight(bar:GetHeight() - 2)
    bar.statusBar = statusBar
    
    -- Icon
    local icon = bar:CreateTexture(nil, "OVERLAY")
    icon:SetSize((self.db.barHeight or defaults.barHeight) - 4, (self.db.barHeight or defaults.barHeight) - 4)
    icon:SetPoint("LEFT", bar, "LEFT", 2, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.icon = icon
    
    -- Name text
    local name = bar:CreateFontString(nil, "OVERLAY")
    name:SetFont(self.db.font or defaults.font, self.db.fontSize or defaults.fontSize, "OUTLINE")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetWidth(80)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetTextColor(1, 1, 1, 1)
    bar.name = name
    
    -- DPS text
    local dps = bar:CreateFontString(nil, "OVERLAY")
    dps:SetFont(self.db.font or defaults.font, self.db.fontSize or defaults.fontSize, "OUTLINE")
    dps:SetPoint("RIGHT", bar, "RIGHT", -40, 0)
    dps:SetJustifyH("RIGHT")
    dps:SetWidth(60)
    dps:SetTextColor(1, 1, 1, 1)
    bar.dps = dps
    
    -- Percentage text
    local percent = bar:CreateFontString(nil, "OVERLAY")
    percent:SetFont(self.db.font or defaults.font, (self.db.fontSize or defaults.fontSize) - 1, "OUTLINE")
    percent:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    percent:SetJustifyH("RIGHT")
    percent:SetWidth(35)
    percent:SetTextColor(0.9, 0.9, 0.9, 1)
    bar.percent = percent
    
    -- Click handler for details
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and bar.guid then
            DPSMeter:ShowDetailWindow(bar.guid, bar.playerName)
        end
    end)
    
    -- Highlight on hover
    bar:SetScript("OnEnter", function(self)
        bar.bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    end)
    
    bar:SetScript("OnLeave", function(self)
        bar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    end)
    
    return bar
end

function DPSMeter:UpdateDisplay()
    if not self.mainFrame or not self.mainFrame:IsShown() then return end
    
    -- Update timer
    if currentEncounter and currentEncounter.startTime then
        local duration = GetTime() - currentEncounter.startTime
        self.mainFrame.timerText:SetText(FormatTime(math.floor(duration)))
    else
        self.mainFrame.timerText:SetText("0:00")
    end
    
    -- Get sorted player list
    local players = {}
    local totalDamage = 0
    
    for guid, data in pairs(combatData) do
        if data.damage > 0 then
            table.insert(players, {
                guid = guid,
                name = data.name,
                damage = data.damage,
                dps = data.dps or 0
            })
            totalDamage = totalDamage + data.damage
        end
    end
    
    table.sort(players, function(a, b) return a.damage > b.damage end)
    
    -- Update or create bars
    local contentHeight = 0
    local barHeight = self.db.barHeight or defaults.barHeight
    local barSpacing = self.db.barSpacing or defaults.barSpacing
    
    for i = 1, #players do
        local bar = self.mainFrame.bars[i]
        if not bar then
            bar = self:CreateBarFrame(self.mainFrame.content, i)
            self.mainFrame.bars[i] = bar
        end
        
        local player = players[i]
        local percentage = totalDamage > 0 and (player.damage / totalDamage * 100) or 0
        local maxDamage = players[1] and players[1].damage or 1
        local barPercent = (player.damage / maxDamage) * 100
        
        -- Update bar position
        bar:SetPoint("TOPLEFT", self.mainFrame.content, "TOPLEFT", 0, -(i - 1) * (barHeight + barSpacing))
        bar:SetPoint("TOPRIGHT", self.mainFrame.content, "TOPRIGHT", 0, -(i - 1) * (barHeight + barSpacing))
        
        -- Update bar data
        bar.guid = player.guid
        bar.playerName = player.name
        
        -- Update visuals
        bar.statusBar:SetWidth((bar:GetWidth() - 2) * (barPercent / 100))
        bar.icon:SetTexture(GetClassIcon(player.name))
        bar.name:SetText(player.name)
        bar.dps:SetText(FormatDPS(player.dps))
        bar.percent:SetText(string.format("%.0f%%", percentage))
        
        -- Set bar color
        if self.db.useClassColors then
            -- Try to get class for color
            local class = nil
            if player.name == UnitName("player") then
                _, class = UnitClass("player")
            elseif IsInRaid() then
                for j = 1, 40 do
                    local unit = "raid" .. j
                    if UnitExists(unit) and UnitName(unit) == player.name then
                        _, class = UnitClass(unit)
                        break
                    end
                end
            elseif IsInGroup() then
                for j = 1, 4 do
                    local unit = "party" .. j
                    if UnitExists(unit) and UnitName(unit) == player.name then
                        _, class = UnitClass(unit)
                        break
                    end
                end
            end
            
            -- Check test player classes first
            if testPlayerClasses[player.name] then
                class = testPlayerClasses[player.name]
            end
            
            if class then
                local color = GetClassColor(class)
                bar.statusBar:SetVertexColor(color.r, color.g, color.b, 0.8)
            else
                bar.statusBar:SetVertexColor(0.5, 0.5, 0.5, 0.8)
            end
        else
            bar.statusBar:SetStatusBarColor(self.db.fontColor.r, self.db.fontColor.g, self.db.fontColor.b)
        end
        
        bar:Show()
        contentHeight = contentHeight + barHeight + barSpacing
    end
    
    -- Hide unused bars
    for i = #players + 1, #self.mainFrame.bars do
        self.mainFrame.bars[i]:Hide()
    end
    
    -- Update content height and scrollbar
    self.mainFrame.content:SetHeight(math.max(contentHeight - barSpacing, 1))
    
    -- Store max scroll for mouse wheel
    local maxScroll = math.max(0, contentHeight - barSpacing - self.mainFrame.scrollFrame:GetHeight())
    self.mainFrame.scrollFrame.maxScroll = maxScroll
end

function DPSMeter:ShowMenu()
    if not self.dropdownMenu then
        self.dropdownMenu = CreateFrame("Frame", "MelloUIDPSMeterDropdown", UIParent, "UIDropDownMenuTemplate")
    end
    
    UIDropDownMenu_Initialize(self.dropdownMenu, function(frame, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        
        -- Title
        info.text = "MelloUI DPS Meter"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
        
        -- Settings
        info = UIDropDownMenu_CreateInfo()
        info.text = "Settings"
        info.notCheckable = true
        info.func = function() 
            CloseDropDownMenus()
            DPSMeter:ShowSettings() 
        end
        UIDropDownMenu_AddButton(info)
        
        -- Reset Current Fight
        info = UIDropDownMenu_CreateInfo()
        info.text = "Reset Current Fight"
        info.notCheckable = true
        info.func = function() 
            CloseDropDownMenus()
            ResetCombatData()
            -- Force immediate display update
            C_Timer.After(0.1, function()
                DPSMeter:UpdateDisplay()
            end)
        end
        UIDropDownMenu_AddButton(info)
        
        -- Reset All Data
        info = UIDropDownMenu_CreateInfo()
        info.text = "Reset All Data"
        info.notCheckable = true
        info.func = function() 
            CloseDropDownMenus()
            ResetCombatData()
            ResetOverallData()
            -- Force immediate display update
            C_Timer.After(0.1, function()
                DPSMeter:UpdateDisplay()
            end)
        end
        UIDropDownMenu_AddButton(info)
        
        -- Lock Window
        info = UIDropDownMenu_CreateInfo()
        info.text = "Lock Window"
        info.checked = DPSMeter.db.windowLocked
        info.keepShownOnClick = true
        info.func = function()
            DPSMeter.db.windowLocked = not DPSMeter.db.windowLocked
        end
        UIDropDownMenu_AddButton(info)
        
        -- Separator
        info = UIDropDownMenu_CreateInfo()
        info.text = ""
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
        
        -- Show Healing Meter
        info = UIDropDownMenu_CreateInfo()
        info.text = "Show Healing Meter"
        info.checked = DPSMeter.healingFrame and DPSMeter.healingFrame:IsShown()
        info.keepShownOnClick = true
        info.func = function()
            if not DPSMeter.healingFrame then
                DPSMeter:CreateHealingWindow()
            end
            if DPSMeter.healingFrame:IsShown() then
                DPSMeter.healingFrame:Hide()
            else
                DPSMeter.healingFrame:Show()
                DPSMeter:UpdateHealingDisplay()
            end
        end
        UIDropDownMenu_AddButton(info)
        
        -- Show Overall Damage
        info = UIDropDownMenu_CreateInfo()
        info.text = "Show Overall Damage"
        info.checked = DPSMeter.overallFrame and DPSMeter.overallFrame:IsShown()
        info.keepShownOnClick = true
        info.func = function()
            if not DPSMeter.overallFrame then
                DPSMeter:CreateOverallWindow()
            end
            if DPSMeter.overallFrame:IsShown() then
                DPSMeter.overallFrame:Hide()
            else
                DPSMeter.overallFrame:Show()
                DPSMeter:UpdateOverallDisplay()
            end
        end
        UIDropDownMenu_AddButton(info)
        
        -- Separator
        info = UIDropDownMenu_CreateInfo()
        info.text = ""
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
        
        -- Test Mode
        info = UIDropDownMenu_CreateInfo()
        info.text = "Test Mode"
        info.notCheckable = true
        info.func = function() 
            CloseDropDownMenus()
            DPSMeter:GenerateTestData() 
        end
        UIDropDownMenu_AddButton(info)
        
        -- Close
        info = UIDropDownMenu_CreateInfo()
        info.text = "Close"
        info.notCheckable = true
        info.func = function() 
            CloseDropDownMenus() 
        end
        UIDropDownMenu_AddButton(info)
    end, "MENU")
    
    ToggleDropDownMenu(1, nil, self.dropdownMenu, "cursor", 0, 0)
end

function DPSMeter:GenerateTestData()
    self.generatingTestData = true
    ResetCombatData()
    
    -- Create a new encounter for test data
    currentEncounter = {
        startTime = GetTime() - 30,
        endTime = nil,
        duration = 0
    }
    
    local testNames = {"Warrior", "Paladin", "Hunter", "Rogue", "Priest", "DeathKnight", "Shaman", "Mage", "Warlock", "Monk", "Druid", "DemonHunter", "Evoker"}
    local testClasses = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"}
    
    currentEncounter = {
        startTime = GetTime() - 30,
        endTime = nil,
        duration = 0
    }
    
    for i = 1, math.min(10, #testNames) do
        local guid = "Test-0-0-0-0-" .. i
        local name = testNames[i]
        local class = testClasses[i]
        local damage = math.random(500000, 2000000)
        
        testPlayerClasses[name] = class
        
        combatData[guid] = {
            name = name,
            damage = damage,
            dps = damage / 30,
            spells = {},
            lastUpdate = GetTime()
        }
        
        -- Add some spell data
        local spellCount = math.random(3, 8)
        for j = 1, spellCount do
            local spellId = 100000 + j
            local spellDamage = damage * (0.4 / spellCount) + math.random(damage * 0.1)
            combatData[guid].spells[spellId] = {
                name = "Test Spell " .. j,
                damage = spellDamage,
                hits = math.random(10, 50)
            }
        end
    end
    
    -- Add some healing data
    for i = 1, 5 do
        local guid = "Test-0-0-0-0-" .. i
        local name = testNames[i]
        local healing = math.random(300000, 1500000)
        
        healingData[guid] = {
            name = name,
            healing = healing,
            hps = healing / 30,
            spells = {},
            lastUpdate = GetTime()
        }
    end
    
    self.generatingTestData = false
    self:UpdateDisplay()
end

function DPSMeter:ShowSettings()
    -- Implement settings window
    print("Settings window not yet implemented")
end

function DPSMeter:ShowDetailWindow(guid, playerName)
    -- Implement detail window for spell breakdown
    print("Detail window not yet implemented for", playerName)
end

function DPSMeter:CreateHealingWindow()
    -- Implement healing meter window
end

function DPSMeter:UpdateHealingDisplay()
    -- Implement healing display update
end

function DPSMeter:CreateOverallWindow()
    -- Implement overall damage window
end

function DPSMeter:UpdateOverallDisplay()
    -- Implement overall display update
end

function DPSMeter:ApplySettings()
    -- Apply settings to all windows
    if self.mainFrame then
        -- Update bar appearance
        for _, bar in ipairs(self.mainFrame.bars) do
            if bar then
                bar.statusBar:SetTexture(self.db.texture or defaults.texture)
                bar.name:SetFont(self.db.font or defaults.font, self.db.fontSize or defaults.fontSize, "OUTLINE")
                bar.dps:SetFont(self.db.font or defaults.font, self.db.fontSize or defaults.fontSize, "OUTLINE")
                bar.percent:SetFont(self.db.font or defaults.font, (self.db.fontSize or defaults.fontSize) - 1, "OUTLINE")
                -- No glow settings
            end
        end
        
        -- Update window opacity
        self.mainFrame:SetBackdropColor(0, 0, 0, self.db.opacity or 0.8)
        self.mainFrame:SetBackdropBorderColor(1, 1, 1, self.db.borderOpacity or 1.0)
    end
end

-- Slash commands
SLASH_MELLOUIDPS1 = "/muidps"
SLASH_MELLOUIDPS2 = "/mdps"
SlashCmdList["MELLOUIDPS"] = function(msg)
    if msg == "test" then
        DPSMeter:GenerateTestData()
    elseif msg == "reset" then
        ResetCombatData()
        ResetOverallData()
        -- Force immediate display update
        C_Timer.After(0.1, function()
            DPSMeter:UpdateDisplay()
        end)
    elseif msg == "show" then
        if DPSMeter.mainFrame then
            DPSMeter.mainFrame:Show()
        end
    elseif msg == "hide" then
        if DPSMeter.mainFrame then
            DPSMeter.mainFrame:Hide()
        end
    elseif msg == "config" or msg == "settings" then
        DPSMeter:ShowSettings()
    else
        print("MelloUI DPS Meter commands:")
        print("/muidps test - Generate test data")
        print("/muidps reset - Reset all data")
        print("/muidps show - Show the meter")
        print("/muidps hide - Hide the meter")
        print("/muidps config - Open settings")
    end
end