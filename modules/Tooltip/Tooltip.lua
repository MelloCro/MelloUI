-- MelloUI Tooltip Module
local addonName, ns = ...
local Tooltip = {}

-- Create saved variables table if it doesn't exist
mTooltipDB = mTooltipDB or {}

-- Class icon texture coordinates
local CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {
    ["WARRIOR"] = {0, 0.25, 0, 0.25},
    ["MAGE"] = {0.25, 0.49609375, 0, 0.25},
    ["ROGUE"] = {0.49609375, 0.7421875, 0, 0.25},
    ["DRUID"] = {0.7421875, 0.98828125, 0, 0.25},
    ["HUNTER"] = {0, 0.25, 0.25, 0.5},
    ["SHAMAN"] = {0.25, 0.49609375, 0.25, 0.5},
    ["PRIEST"] = {0.49609375, 0.7421875, 0.25, 0.5},
    ["WARLOCK"] = {0.7421875, 0.98828125, 0.25, 0.5},
    ["PALADIN"] = {0, 0.25, 0.5, 0.75},
    ["DEATHKNIGHT"] = {0.25, 0.49609375, 0.5, 0.75},
    ["MONK"] = {0.49609375, 0.7421875, 0.5, 0.75},
    ["DEMONHUNTER"] = {0.7421875, 0.98828125, 0.5, 0.75},
    ["EVOKER"] = {0, 0.25, 0.75, 1},
}

-- Function to get level difference color based on Blizzard's logic
local function GetLevelDifferenceColor(targetLevel)
    local playerLevel = UnitLevel("player")
    local levelDiff = targetLevel - playerLevel
    
    if levelDiff >= 5 then
        return 1, 0, 0 -- Red for 5+ levels higher
    elseif levelDiff >= 3 then
        return 1, 0.5, 0 -- Orange for 3-4 levels higher
    elseif levelDiff >= -2 then
        return 1, 1, 0 -- Yellow for -2 to +2 levels
    elseif levelDiff >= -7 then
        return 0, 1, 0 -- Green for slightly lower (up to 7 levels)
    else
        return 0.5, 0.5, 0.5 -- Gray for much lower
    end
end

-- Function to get item level color based on Blizzard's logic
local function GetItemLevelColor(ilvl)
    if not ilvl or ilvl == 0 then
        return 0.5, 0.5, 0.5 -- Gray for no ilvl
    end
    
    -- These are approximate breakpoints for current content
    if ilvl >= 450 then
        return 1, 0.5, 0 -- Orange/Legendary for very high ilvl
    elseif ilvl >= 415 then
        return 0.64, 0.21, 0.93 -- Purple/Epic for high ilvl
    elseif ilvl >= 385 then
        return 0, 0.44, 0.87 -- Blue/Rare for mid-high ilvl
    elseif ilvl >= 350 then
        return 0.12, 1, 0 -- Green/Uncommon for mid ilvl
    else
        return 1, 1, 1 -- White/Common for low ilvl
    end
end

-- Function to get M+ rating color based on Blizzard's formula
local function GetMythicPlusRatingColor(rating)
    if not rating or rating == 0 then
        return 0.5, 0.5, 0.5 -- Gray for no rating
    end
    
    -- Blizzard's M+ color breakpoints
    if rating < 500 then
        -- Gray to Green transition
        local progress = rating / 500
        return 0.5 * (1 - progress), 0.5 + (0.5 * progress), 0.5 * (1 - progress)
    elseif rating < 1000 then
        -- Green to Blue transition
        local progress = (rating - 500) / 500
        return 0, 1 - (0.5 * progress), progress
    elseif rating < 1500 then
        -- Blue to Purple transition
        local progress = (rating - 1000) / 500
        return 0.5 * progress, 0.5 * (1 - progress), 1
    elseif rating < 2000 then
        -- Purple to Orange transition
        local progress = (rating - 1500) / 500
        return 0.5 + (0.5 * progress), 0.5 * progress, 1 - progress
    else
        -- Orange to Red for 2000+
        local progress = math.min((rating - 2000) / 500, 1)
        return 1, 0.5 * (1 - progress), 0
    end
end

-- Function to modify unit tooltips
local function OnTooltipSetUnit(tooltip, data)
    if tooltip ~= GameTooltip then return end
    
    -- Get the unit from the tooltip
    local _, unit = tooltip:GetUnit()
    if not unit then return end
    
    if UnitIsPlayer(unit) then
        -- Get player info
        local _, class = UnitClass(unit)
        local guildName, guildRankName = GetGuildInfo(unit)
        
        -- Process first line (name) - remove realm and apply class color
        local nameLine = _G["GameTooltipTextLeft1"]
        if nameLine then
            local nameText = nameLine:GetText()
            if nameText then
                -- Get the unit name without title or realm
                local unitName = GetUnitName(unit, false) -- false = no realm
                
                -- Apply class color and add icon
                if class then
                    -- Create the name with class icon
                    local iconSize = 14  -- Adjust this value to scale the icon
                    local coords = CLASS_ICON_TCOORDS[class]
                    
                    if coords then
                        -- Format: name + space + icon using the standard class icon texture
                        local iconString = string.format("|TInterface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t",
                            iconSize, iconSize,  -- width, height
                            coords[1] * 256, coords[2] * 256,  -- left, right
                            coords[3] * 256, coords[4] * 256)  -- top, bottom
                        
                        local nameWithIcon = unitName .. " " .. iconString
                        nameLine:SetText(nameWithIcon)
                    else
                        -- No icon coords, just set name
                        nameLine:SetText(unitName)
                    end
                    
                    -- Apply class color
                    if RAID_CLASS_COLORS[class] then
                        local classColor = RAID_CLASS_COLORS[class]
                        nameLine:SetTextColor(classColor.r, classColor.g, classColor.b)
                    end
                else
                    -- No class info, just set name
                    nameLine:SetText(unitName)
                end
            end
        end
        
        -- Process other lines
        local linesToRemove = {}
        local targetLevel = UnitLevel(unit)
        
        for i = 2, tooltip:NumLines() do
            local line = _G["GameTooltipTextLeft"..i]
            if line then
                local text = line:GetText()
                if text then
                    -- Check for guild (with or without brackets, possibly with realm)
                    local guildMatch = text:match("^<(.+)>$")
                    
                    if guildMatch then
                        -- Remove realm name from guild if present
                        local guildWithoutRealm = guildMatch:match("^([^-]+)") or guildMatch
                        -- Add rank if available
                        local newText = "<" .. guildWithoutRealm .. ">"
                        if guildRankName and guildRankName ~= "" then
                            newText = newText .. " - " .. guildRankName
                        end
                        line:SetText(newText)
                        -- Color guild name green
                        line:SetTextColor(0, 1, 0)
                    elseif guildName and text:find(guildName, 1, true) then
                        -- Handle guild without brackets - add them
                        local guildWithoutRealm = text:match("^([^-]+)") or text
                        -- Add rank if available
                        local newText = "<" .. guildWithoutRealm .. ">"
                        if guildRankName and guildRankName ~= "" then
                            newText = newText .. " - " .. guildRankName
                        end
                        line:SetText(newText)
                        line:SetTextColor(0, 1, 0)
                    -- Check if this line contains level/spec/class info
                    elseif text:match("Level %d+") then
                        -- Apply level difference coloring
                        if targetLevel and targetLevel > 0 then
                            local r, g, b = GetLevelDifferenceColor(targetLevel)
                            line:SetTextColor(r, g, b)
                        end
                    -- Color faction lines
                    elseif text == "Alliance" or text == FACTION_ALLIANCE then
                        line:SetTextColor(0, 0.6, 1) -- Alliance blue
                    elseif text == "Horde" or text == FACTION_HORDE then
                        line:SetTextColor(1, 0, 0) -- Horde red
                    end
                end
            end
        end
        
        -- Hide the lines we want to remove
        for _, lineNum in ipairs(linesToRemove) do
            local leftLine = _G["GameTooltipTextLeft"..lineNum]
            local rightLine = _G["GameTooltipTextRight"..lineNum]
            if leftLine then leftLine:SetText("") end
            if rightLine then rightLine:SetText("") end
        end
        
        -- Add M+ Rating
        local rating = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
        local score = 0
        
        -- Get the actual score if it exists
        if rating and rating.currentSeasonScore then
            score = rating.currentSeasonScore
        end
        
        -- Add a blank line first for spacing
        tooltip:AddLine(" ")
        
        -- Get the color for the rating
        local r, g, b = GetMythicPlusRatingColor(score)
        
        -- Format the score text with color
        local scoreText = string.format("M+ Score: |cff%02x%02x%02x%d|r", 
            r * 255, g * 255, b * 255, 
            math.floor(score))
        
        -- Add the M+ score line as a single line
        tooltip:AddLine(scoreText)
        
        -- Add Item Level
        local avgItemLevelEquipped = 0
        
        -- Get item level - only works reliably for self
        if unit == "player" then
            local avgItemLevel, equipped = GetAverageItemLevel()
            avgItemLevelEquipped = equipped or 0
        else
            -- For other players, we can try to get it from inspect data if available
            -- This requires the player to have been inspected
            local guid = UnitGUID(unit)
            if guid and CanInspect(unit, false) then
                -- Try to get cached inspect data
                avgItemLevelEquipped = select(2, GetAverageItemLevel()) or 0
            end
        end
        
        -- Only show if we have a valid item level
        if avgItemLevelEquipped and avgItemLevelEquipped > 0 then
            -- Get the color for the item level
            local ilvlR, ilvlG, ilvlB = GetItemLevelColor(avgItemLevelEquipped)
            
            -- Format the item level text with color
            local ilvlText = string.format("Item Level: |cff%02x%02x%02x%d|r", 
                ilvlR * 255, ilvlG * 255, ilvlB * 255, 
                math.floor(avgItemLevelEquipped))
            
            -- Add the item level line
            tooltip:AddLine(ilvlText)
        else
            -- Show "Item Level: ---" for players we can't inspect
            tooltip:AddLine("Item Level: |cff808080---|r")
        end
    end
end

-- Function to modify item tooltips
local function OnTooltipSetItem(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    
    -- Get item info from the tooltip
    local _, itemLink = tooltip:GetItem()
    if itemLink then
        -- This is where custom modifications will be added
        -- For now, just a placeholder
    end
end

-- Function to modify spell tooltips
local function OnTooltipSetSpell(tooltip, data)
    if tooltip ~= GameTooltip then return end
    
    -- Get spell info from the tooltip
    local spellId = select(2, tooltip:GetSpell())
    if spellId then
        -- This is where custom modifications will be added
        -- For now, just a placeholder
    end
end

function Tooltip:OnInitialize()
    -- Register tooltip data handlers using the new API
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnTooltipSetSpell)
    
    -- Hide the health bar
    GameTooltipStatusBar:SetAlpha(0)
    GameTooltipStatusBar:Hide()
    
    -- Hook to keep it hidden
    GameTooltipStatusBar:SetScript("OnShow", function(self)
        self:Hide()
    end)
end

function Tooltip:OnEnable()
    -- Module enabled
end

function Tooltip:OnDisable()
    -- Module disabled
end

-- Register the module
ns:RegisterModule("Tooltip", Tooltip)