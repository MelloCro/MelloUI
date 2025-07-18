local addonName, ns = ...
local MelloChat = {}
ns:RegisterModule("MelloChat", MelloChat)

-- Cache for player class colors
local playerClassCache = {}

-- Module variables
local melloChatFrame = nil
local eventFrame = nil
local isEnabled = false

-- Get class color for a player
local function GetClassColoredName(name, guid)
    if not name or name == "" then return "" end
    
    -- Extract the actual name without server
    local nameWithoutServer = string.match(name, "([^%-]+)") or name
    local coloredName = nameWithoutServer  -- Use name without realm
    local class = nil
    
    -- Try to get class from GUID first
    if guid and guid ~= "" then
        local localizedClass, englishClass, localizedRace, englishRace, sex, name, realm = GetPlayerInfoByGUID(guid)
        class = englishClass
    end
    
    -- Check cache if we don't have class info
    if not class and playerClassCache[name] then
        class = playerClassCache[name]
    end
    
    -- Try other methods to get class
    if not class then
        -- Check if it's the player (compare without server)
        local playerName = UnitName("player")
        if nameWithoutServer == playerName then
            _, class = UnitClass("player")
            playerClassCache[name] = class
        -- Check if the unit exists directly
        elseif UnitExists(nameWithoutServer) then
            _, class = UnitClass(nameWithoutServer)
            playerClassCache[name] = class
        -- Check party members
        elseif GetNumGroupMembers() > 0 then
            local prefix = IsInRaid() and "raid" or "party"
            local limit = IsInRaid() and GetNumGroupMembers() or GetNumGroupMembers() - 1
            
            for i = 1, limit do
                local unit = prefix .. i
                local unitName = UnitName(unit)
                if unitName and unitName == nameWithoutServer then
                    _, class = UnitClass(unit)
                    playerClassCache[name] = class
                    break
                end
            end
        end
    end
    
    -- Apply class color if found
    if class and RAID_CLASS_COLORS[class] then
        local classColor = RAID_CLASS_COLORS[class]
        coloredName = string.format("|c%s%s|r", classColor.colorStr, nameWithoutServer)
    end
    
    return GetPlayerLink(nameWithoutServer, string.format("[%s]", coloredName))
end

local function CreateMelloChatFrame()
    local frame = CreateFrame("Frame", "MelloChatFrame", UIParent, "BackdropTemplate")
    frame:SetSize(493, 412)
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 7.5, 7.5)
    
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    
    frame:EnableMouse(true)
    frame:SetMovable(false)  -- Default to locked
    frame:SetResizable(false)  -- Default to locked
    frame:SetResizeBounds(200, 100, 800, 600)
    frame:SetClampedToScreen(true)
    frame.isLocked = true  -- Default to locked
    
    local titleBar = CreateFrame("Button", nil, frame)
    titleBar:SetHeight(20)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -10)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() 
        if not frame.isLocked then
            frame:StartMoving() 
        end
    end)
    titleBar:SetScript("OnDragStop", function() 
        if not frame.isLocked then
            frame:StopMovingOrSizing()
            C_Timer.After(0.1, function() 
                if MelloChat.SaveSettings then MelloChat:SaveSettings() end
            end)  -- Save after moving
        end
    end)
    
    
    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetScript("OnMouseDown", function() 
        if not frame.isLocked then
            frame:StartSizing("BOTTOMRIGHT") 
        end
    end)
    resizeButton:SetScript("OnMouseUp", function() 
        if not frame.isLocked then
            frame:StopMovingOrSizing()
            C_Timer.After(0.1, function()
                if MelloChat.SaveSettings then MelloChat:SaveSettings() end
            end)  -- Save after resizing
        end
    end)
    frame.resizeButton = resizeButton  -- Store reference for lock functionality
    resizeButton:Hide()  -- Hide by default since we're locked
    
    -- Create a message frame that supports hyperlinks
    local chatDisplay = CreateFrame("ScrollingMessageFrame", "MelloChatDisplay", frame)
    chatDisplay:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -35)
    chatDisplay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)
    frame.chatDisplay = chatDisplay  -- Store reference for settings
    
    -- Set a consistent font for all messages
    local fontPath, fontSize, fontFlags = "Fonts\\ARIALN.TTF", 11, ""
    frame.currentFont = fontPath  -- Store current font
    frame.currentFontSize = fontSize  -- Store current font size
    chatDisplay:SetFont(fontPath, fontSize, fontFlags)
    chatDisplay:SetJustifyH("LEFT")
    chatDisplay:SetMaxLines(500)
    chatDisplay:SetFading(false)
    chatDisplay:SetHyperlinksEnabled(true)
    chatDisplay:SetIndentedWordWrap(true)
    chatDisplay:SetTextCopyable(true)
    chatDisplay:SetSpacing(2) -- Consistent line spacing
    
    -- Handle link clicks with full functionality
    chatDisplay:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local linkType = string.match(link, "^([^:]+)")
        if linkType == "player" then
            local name = string.match(link, "player:([^:]+)")
            if name and button == "LeftButton" and not IsModifiedClick() then
                -- Open whisper to player
                if frame.inputBox then
                    local nameWithoutRealm = string.match(name, "([^%-]+)") or name
                    frame.inputBox.chatType = "WHISPER"
                    frame.inputBox.chatTarget = name  -- Keep full name for whisper functionality
                    frame.channelLabel:SetText("[To " .. nameWithoutRealm .. "]")
                    frame.channelLabel:SetTextColor(1, 0.5, 1)
                    local labelWidth = frame.channelLabel:GetStringWidth() + 12
                    frame.inputBox:SetTextInsets(labelWidth, 5, 3, 3)
                    frame.inputBox:SetFocus()
                end
                return
            end
        end
        SetItemRef(link, text, button)
    end)
    
    chatDisplay:SetScript("OnHyperlinkEnter", function(self, link, text)
        local linkType = string.match(link, "^([^:]+)")
        if linkType == "item" or linkType == "spell" or linkType == "achievement" or linkType == "talent" or linkType == "quest" or linkType == "enchant" or linkType == "trade" or linkType == "instancelock" then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        elseif linkType == "player" then
            local name = string.match(link, "player:([^:]+)")
            if name then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText(name)
                GameTooltip:AddLine("Left-click to whisper", 1, 1, 1)
                GameTooltip:AddLine("Right-click for more options", 1, 1, 1)
                GameTooltip:Show()
            end
        end
    end)
    
    chatDisplay:SetScript("OnHyperlinkLeave", function(self, link, text)
        GameTooltip:Hide()
    end)
    
    -- Enable mouse wheel scrolling
    chatDisplay:EnableMouseWheel(true)
    chatDisplay:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            -- Scroll up
            if IsShiftKeyDown() then
                self:ScrollToTop()
            else
                self:ScrollUp()
            end
        else
            -- Scroll down
            if IsShiftKeyDown() then
                self:ScrollToBottom()
            else
                self:ScrollDown()
            end
        end
    end)
    
    -- Create tab container
    local tabContainer = CreateFrame("Frame", nil, frame)
    tabContainer:SetHeight(20)
    tabContainer:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    tabContainer:SetWidth(600) -- Set a fixed width for the tab container
    
    -- Store tabs and their filters
    frame.tabs = {}
    frame.activeTab = nil
    frame.messageHistory = {}  -- Store messages for each tab
    
    -- Create tabs
    local function CreateTab(name, filter)
        local tab = CreateFrame("Button", nil, tabContainer, "BackdropTemplate")
        tab:SetHeight(22)
        tab:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 3, right = 3, top = 1, bottom = 5 }
        })
        tab:SetBackdropColor(0, 0, 0, (frame.bgOpacity or 0.8) * 0.625)
        tab:SetBackdropBorderColor(0.5, 0.5, 0.5, frame.borderOpacity or 1)
        
        local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", 0, 1)
        text:SetText(name)
        tab.text = text
        
        -- Auto-size based on text
        local textWidth = text:GetStringWidth()
        tab:SetWidth(textWidth + 20)
        
        tab.name = name
        tab.filter = filter
        tab.messages = {}
        
        tab:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                frame:SetActiveTab(self)
            elseif button == "RightButton" then
                frame:ShowTabMenu(self)
            end
        end)
        
        tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        tab:SetScript("OnEnter", function(self)
            if self ~= frame.activeTab then
                self:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            end
        end)
        
        tab:SetScript("OnLeave", function(self)
            if self ~= frame.activeTab then
                self:SetBackdropColor(0, 0, 0, (frame.bgOpacity or 0.8) * 0.625)
            end
        end)
        
        return tab
    end
    
    -- Create settings button (cogwheel)
    local settingsButton = CreateFrame("Button", nil, tabContainer, "BackdropTemplate")
    settingsButton:SetHeight(22)
    settingsButton:SetWidth(22)
    settingsButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    settingsButton:SetBackdropColor(0, 0, 0, (frame.bgOpacity or 0.8) * 0.625)
    settingsButton:SetBackdropBorderColor(0.5, 0.5, 0.5, frame.borderOpacity or 1)
    
    -- Create cogwheel texture
    local cogTexture = settingsButton:CreateTexture(nil, "ARTWORK")
    cogTexture:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cogTexture:SetPoint("CENTER")
    cogTexture:SetSize(16, 16)
    
    settingsButton:SetPoint("LEFT", tabContainer, "LEFT", 5, 0)
    
    settingsButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Chat Settings")
        GameTooltip:Show()
    end)
    
    settingsButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0.5)
        GameTooltip:Hide()
    end)
    
    settingsButton:SetScript("OnClick", function(self)
        frame:ShowSettingsMenu(self)
    end)
    
    frame.settingsButton = settingsButton
    
    -- Create default tabs
    local generalTab = CreateTab("General", {
        ["CHAT_MSG_SAY"] = true,
        ["CHAT_MSG_YELL"] = true,
        ["CHAT_MSG_SYSTEM"] = true,
        ["CHAT_MSG_PARTY"] = true,
        ["CHAT_MSG_PARTY_LEADER"] = true,
        ["CHAT_MSG_RAID"] = true,
        ["CHAT_MSG_RAID_LEADER"] = true,
        ["CHAT_MSG_RAID_WARNING"] = true,
        ["CHAT_MSG_INSTANCE_CHAT"] = true,
        ["CHAT_MSG_INSTANCE_CHAT_LEADER"] = true,
        ["CHAT_MSG_EMOTE"] = true,
        ["CHAT_MSG_TEXT_EMOTE"] = true,
        ["CHAT_MSG_MONSTER_SAY"] = true,
        ["CHAT_MSG_MONSTER_YELL"] = true,
        ["CHAT_MSG_MONSTER_EMOTE"] = true,
        ["CHAT_MSG_MONSTER_WHISPER"] = true,
        ["CHAT_MSG_RAID_BOSS_EMOTE"] = true,
        ["CHAT_MSG_RAID_BOSS_WHISPER"] = true,
        ["CHAT_MSG_LOOT"] = true,
        ["CHAT_MSG_MONEY"] = true,
        ["CHAT_MSG_CURRENCY"] = true,
        ["CHAT_MSG_TRADESKILLS"] = true,
        ["CHAT_MSG_OPENING"] = true,
        ["CHAT_MSG_PET_INFO"] = true,
        ["CHAT_MSG_SKILL"] = true,
        ["CHAT_MSG_ACHIEVEMENT"] = true,
        ["CHAT_MSG_GUILD_ACHIEVEMENT"] = true,
        ["CHAT_MSG_BG_SYSTEM_NEUTRAL"] = true,
        ["CHAT_MSG_BG_SYSTEM_ALLIANCE"] = true,
        ["CHAT_MSG_BG_SYSTEM_HORDE"] = true,
        ["CHAT_MSG_COMBAT_XP_GAIN"] = true,
        ["CHAT_MSG_COMBAT_HONOR_GAIN"] = true,
        ["CHAT_MSG_COMBAT_FACTION_CHANGE"] = true,
    })
    generalTab:SetPoint("LEFT", settingsButton, "RIGHT", 5, 0)
    table.insert(frame.tabs, generalTab)
    
    local tradeTab = CreateTab("Trade", {
        ["CHAT_MSG_CHANNEL"] = true,  -- This will include all channels including Trade
    })
    tradeTab:SetPoint("LEFT", generalTab, "RIGHT", 2, 0)
    table.insert(frame.tabs, tradeTab)
    
    local whisperTab = CreateTab("Whispers", {
        ["CHAT_MSG_WHISPER"] = true,
        ["CHAT_MSG_WHISPER_INFORM"] = true,
        ["CHAT_MSG_BN_WHISPER"] = true,
        ["CHAT_MSG_BN_WHISPER_INFORM"] = true,
        ["CHAT_MSG_AFK"] = true,
        ["CHAT_MSG_DND"] = true,
        ["CHAT_MSG_IGNORED"] = true,
    })
    whisperTab:SetPoint("LEFT", tradeTab, "RIGHT", 2, 0)
    table.insert(frame.tabs, whisperTab)
    frame.whisperTab = whisperTab  -- Store reference for glow effect
    
    local guildTab = CreateTab("Guild", {
        ["CHAT_MSG_GUILD"] = true,
        ["CHAT_MSG_OFFICER"] = true,
        ["CHAT_MSG_GUILD_ACHIEVEMENT"] = true,
    })
    guildTab:SetPoint("LEFT", whisperTab, "RIGHT", 2, 0)
    table.insert(frame.tabs, guildTab)
    
    -- Create "Add Tab" button
    local addTabButton = CreateFrame("Button", nil, tabContainer, "BackdropTemplate")
    addTabButton:SetHeight(22)
    addTabButton:SetWidth(30)
    addTabButton:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 1, bottom = 5 }
    })
    addTabButton:SetBackdropColor(0, 0, 0, (frame.bgOpacity or 0.8) * 0.625)
    addTabButton:SetBackdropBorderColor(0.5, 0.5, 0.5, frame.borderOpacity or 1)
    
    local addText = addTabButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addText:SetPoint("CENTER", 0, 1)
    addText:SetText("+")
    addText:SetTextColor(0.7, 0.7, 0.7)
    
    addTabButton:SetScript("OnClick", function()
        frame:ShowAddTabDialog()
    end)
    
    addTabButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
        addText:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Add New Tab")
        GameTooltip:Show()
    end)
    
    addTabButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0.5)
        addText:SetTextColor(0.7, 0.7, 0.7)
        GameTooltip:Hide()
    end)
    
    frame.addTabButton = addTabButton
    
    -- Function to update tab positions
    function frame:UpdateTabPositions()
        local xOffset = 5 + self.settingsButton:GetWidth() + 5  -- Account for settings button
        for i, tab in ipairs(self.tabs) do
            tab:ClearAllPoints()
            tab:SetPoint("LEFT", tabContainer, "LEFT", xOffset, 0)
            xOffset = xOffset + tab:GetWidth() + 2
        end
        -- Position add button after last tab
        self.addTabButton:ClearAllPoints()
        self.addTabButton:SetPoint("LEFT", tabContainer, "LEFT", xOffset, 0)
    end
    
    -- Function to show tab menu
    function frame:ShowTabMenu(tab)
        if not frame.dropdownMenu then
            frame.dropdownMenu = CreateFrame("Frame", "MelloChatDropdown", UIParent, "UIDropDownMenuTemplate")
        end
        
        local menuList = {}
        
        -- Tab name header
        tinsert(menuList, {
            text = tab.name,
            isTitle = true,
            notCheckable = true,
        })
        
        -- Rename option
        tinsert(menuList, {
            text = "Rename Tab",
            notCheckable = true,
            func = function()
                CloseDropDownMenus()
                self:ShowRenameTabDialog(tab)
            end,
        })
        
        -- Configure Filters submenu
        tinsert(menuList, {
            text = "Configure Filters",
            notCheckable = true,
            hasArrow = true,
        })
        
        -- Delete option
        tinsert(menuList, {
            text = "Delete Tab",
            notCheckable = true,
            disabled = #self.tabs <= 1,
            func = function()
                CloseDropDownMenus()
                self:DeleteTab(tab)
            end,
        })
        
        -- Separator
        tinsert(menuList, {
            text = "",
            disabled = true,
            notCheckable = true,
        })
        
        -- Cancel
        tinsert(menuList, {
            text = "Cancel",
            notCheckable = true,
            func = function() CloseDropDownMenus() end,
        })
        
        -- Store the menu data on the dropdown frame
        frame.dropdownMenu.menuData = menuList
        frame.dropdownMenu.filterBuilder = function() return self:BuildFilterMenu(tab) end
        
        UIDropDownMenu_Initialize(frame.dropdownMenu, function(dropdown, level, menuList)
            level = level or 1
            
            if level == 1 then
                -- Main menu
                for _, item in ipairs(dropdown.menuData) do
                    if item.hasArrow and item.text == "Configure Filters" then
                        -- Set the value for the submenu
                        item.value = "FILTERS"
                    end
                    UIDropDownMenu_AddButton(item, level)
                end
            elseif level == 2 then
                -- Submenu
                if UIDROPDOWNMENU_MENU_VALUE == "FILTERS" then
                    local filterMenu = dropdown.filterBuilder()
                    for _, item in ipairs(filterMenu) do
                        UIDropDownMenu_AddButton(item, level)
                    end
                end
            end
        end, "MENU")
        
        ToggleDropDownMenu(1, nil, frame.dropdownMenu, "cursor", 0, 0)
    end
    
    -- Build filter submenu
    function frame:BuildFilterMenu(tab)
        local filterMenu = {}
        
        -- Helper function to create filter item
        local function createFilterItem(text, event)
            return {
                text = text,
                checkable = true,
                checked = function() return tab.filter[event] end,
                func = function() 
                    tab.filter[event] = not tab.filter[event]
                    if MelloChat.SaveSettings then MelloChat:SaveSettings() end  -- Save filter change
                end,
                keepShownOnClick = true,
            }
        end
        
        -- General Chat
        tinsert(filterMenu, {text = "General Chat", isTitle = true, notCheckable = true})
        tinsert(filterMenu, createFilterItem("Say", "CHAT_MSG_SAY"))
        tinsert(filterMenu, createFilterItem("Yell", "CHAT_MSG_YELL"))
        tinsert(filterMenu, createFilterItem("Emote", "CHAT_MSG_EMOTE"))
        tinsert(filterMenu, createFilterItem("Text Emote", "CHAT_MSG_TEXT_EMOTE"))
        
        -- Separator
        tinsert(filterMenu, {text = "", disabled = true, notCheckable = true})
        
        -- Group & Guild
        tinsert(filterMenu, {text = "Group & Guild", isTitle = true, notCheckable = true})
        tinsert(filterMenu, createFilterItem("Party", "CHAT_MSG_PARTY"))
        tinsert(filterMenu, createFilterItem("Party Leader", "CHAT_MSG_PARTY_LEADER"))
        tinsert(filterMenu, createFilterItem("Raid", "CHAT_MSG_RAID"))
        tinsert(filterMenu, createFilterItem("Raid Leader", "CHAT_MSG_RAID_LEADER"))
        tinsert(filterMenu, createFilterItem("Raid Warning", "CHAT_MSG_RAID_WARNING"))
        tinsert(filterMenu, createFilterItem("Instance", "CHAT_MSG_INSTANCE_CHAT"))
        tinsert(filterMenu, createFilterItem("Instance Leader", "CHAT_MSG_INSTANCE_CHAT_LEADER"))
        tinsert(filterMenu, createFilterItem("Guild", "CHAT_MSG_GUILD"))
        tinsert(filterMenu, createFilterItem("Officer", "CHAT_MSG_OFFICER"))
        
        -- Separator
        tinsert(filterMenu, {text = "", disabled = true, notCheckable = true})
        
        -- Whispers & Channels
        tinsert(filterMenu, {text = "Whispers & Channels", isTitle = true, notCheckable = true})
        tinsert(filterMenu, createFilterItem("Whisper", "CHAT_MSG_WHISPER"))
        tinsert(filterMenu, createFilterItem("Whisper Inform", "CHAT_MSG_WHISPER_INFORM"))
        tinsert(filterMenu, createFilterItem("BN Whisper", "CHAT_MSG_BN_WHISPER"))
        tinsert(filterMenu, createFilterItem("BN Whisper Inform", "CHAT_MSG_BN_WHISPER_INFORM"))
        tinsert(filterMenu, createFilterItem("Channel", "CHAT_MSG_CHANNEL"))
        
        -- Separator
        tinsert(filterMenu, {text = "", disabled = true, notCheckable = true})
        
        -- System Messages
        tinsert(filterMenu, {text = "System Messages", isTitle = true, notCheckable = true})
        tinsert(filterMenu, createFilterItem("System", "CHAT_MSG_SYSTEM"))
        tinsert(filterMenu, createFilterItem("Achievement", "CHAT_MSG_ACHIEVEMENT"))
        tinsert(filterMenu, createFilterItem("Guild Achievement", "CHAT_MSG_GUILD_ACHIEVEMENT"))
        tinsert(filterMenu, createFilterItem("Loot", "CHAT_MSG_LOOT"))
        tinsert(filterMenu, createFilterItem("Money", "CHAT_MSG_MONEY"))
        tinsert(filterMenu, createFilterItem("Currency", "CHAT_MSG_CURRENCY"))
        tinsert(filterMenu, createFilterItem("Tradeskills", "CHAT_MSG_TRADESKILLS"))
        tinsert(filterMenu, createFilterItem("Opening", "CHAT_MSG_OPENING"))
        tinsert(filterMenu, createFilterItem("Pet Info", "CHAT_MSG_PET_INFO"))
        
        -- Separator
        tinsert(filterMenu, {text = "", disabled = true, notCheckable = true})
        
        -- Combat Messages
        tinsert(filterMenu, {text = "Combat Messages", isTitle = true, notCheckable = true})
        tinsert(filterMenu, createFilterItem("Combat XP Gain", "CHAT_MSG_COMBAT_XP_GAIN"))
        tinsert(filterMenu, createFilterItem("Combat Honor Gain", "CHAT_MSG_COMBAT_HONOR_GAIN"))
        tinsert(filterMenu, createFilterItem("Combat Faction Change", "CHAT_MSG_COMBAT_FACTION_CHANGE"))
        tinsert(filterMenu, createFilterItem("Skill", "CHAT_MSG_SKILL"))
        
        -- Separator
        tinsert(filterMenu, {text = "", disabled = true, notCheckable = true})
        
        -- Creature Messages
        tinsert(filterMenu, {text = "Creature Messages", isTitle = true, notCheckable = true})
        tinsert(filterMenu, createFilterItem("Monster Say", "CHAT_MSG_MONSTER_SAY"))
        tinsert(filterMenu, createFilterItem("Monster Yell", "CHAT_MSG_MONSTER_YELL"))
        tinsert(filterMenu, createFilterItem("Monster Emote", "CHAT_MSG_MONSTER_EMOTE"))
        tinsert(filterMenu, createFilterItem("Monster Whisper", "CHAT_MSG_MONSTER_WHISPER"))
        tinsert(filterMenu, createFilterItem("Boss Emote", "CHAT_MSG_RAID_BOSS_EMOTE"))
        tinsert(filterMenu, createFilterItem("Boss Whisper", "CHAT_MSG_RAID_BOSS_WHISPER"))
        
        -- Separator
        tinsert(filterMenu, {text = "", disabled = true, notCheckable = true})
        
        -- Other Messages
        tinsert(filterMenu, {text = "Other Messages", isTitle = true, notCheckable = true})
        tinsert(filterMenu, createFilterItem("BG System Neutral", "CHAT_MSG_BG_SYSTEM_NEUTRAL"))
        tinsert(filterMenu, createFilterItem("BG System Alliance", "CHAT_MSG_BG_SYSTEM_ALLIANCE"))
        tinsert(filterMenu, createFilterItem("BG System Horde", "CHAT_MSG_BG_SYSTEM_HORDE"))
        tinsert(filterMenu, createFilterItem("Ignored", "CHAT_MSG_IGNORED"))
        tinsert(filterMenu, createFilterItem("AFK", "CHAT_MSG_AFK"))
        tinsert(filterMenu, createFilterItem("DND", "CHAT_MSG_DND"))
        tinsert(filterMenu, createFilterItem("Combat Misc Info", "CHAT_MSG_COMBAT_MISC_INFO"))
        
        return filterMenu
    end
    
    -- Function to delete a tab
    function frame:DeleteTab(tab)
        if #self.tabs <= 1 then return end
        
        -- Find and remove the tab
        for i, t in ipairs(self.tabs) do
            if t == tab then
                table.remove(self.tabs, i)
                tab:Hide()
                break
            end
        end
        
        -- If we deleted the active tab, activate another one
        if self.activeTab == tab then
            self:SetActiveTab(self.tabs[1])
        end
        
        self:UpdateTabPositions()
        if MelloChat.SaveSettings then MelloChat:SaveSettings() end  -- Save after deleting tab
    end
    
    -- Function to show settings menu
    function frame:ShowSettingsMenu(button)
        if not frame.settingsDropdown then
            frame.settingsDropdown = CreateFrame("Frame", "MelloChatSettingsDropdown", UIParent, "UIDropDownMenuTemplate")
        end
        
        local fontList = {
            "Fonts\\FRIZQT__.TTF",
            "Fonts\\ARIALN.TTF",
            "Fonts\\skurri.TTF",
            "Fonts\\MORPHEUS.TTF",
        }
        
        local fontSizes = {8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24}
        
        UIDropDownMenu_Initialize(frame.settingsDropdown, function(dropdown, level)
            level = level or 1
            
            if level == 1 then
                -- Font submenu
                local fontInfo = UIDropDownMenu_CreateInfo()
                fontInfo.text = "Font"
                fontInfo.hasArrow = true
                fontInfo.value = "FONT"
                fontInfo.notCheckable = true
                UIDropDownMenu_AddButton(fontInfo, level)
                
                -- Font Size submenu
                local sizeInfo = UIDropDownMenu_CreateInfo()
                sizeInfo.text = "Font Size"
                sizeInfo.hasArrow = true
                sizeInfo.value = "FONTSIZE"
                sizeInfo.notCheckable = true
                UIDropDownMenu_AddButton(sizeInfo, level)
                
                -- Separator
                local sep = UIDropDownMenu_CreateInfo()
                sep.text = ""
                sep.isTitle = true
                sep.notCheckable = true
                UIDropDownMenu_AddButton(sep, level)
                
                -- Lock position
                local lockInfo = UIDropDownMenu_CreateInfo()
                lockInfo.text = "Lock Position & Size"
                lockInfo.checked = frame.isLocked or false
                lockInfo.func = function()
                    frame.isLocked = not frame.isLocked
                    if frame.isLocked then
                        frame:SetMovable(false)
                        frame:SetResizable(false)
                        if frame.resizeButton then
                            frame.resizeButton:Hide()
                        end
                    else
                        frame:SetMovable(true)
                        frame:SetResizable(true)
                        if frame.resizeButton then
                            frame.resizeButton:Show()
                        end
                    end
                    if MelloChat.SaveSettings then MelloChat:SaveSettings() end  -- Save lock state change
                end
                lockInfo.keepShownOnClick = true
                UIDropDownMenu_AddButton(lockInfo, level)
                
                -- Background Opacity submenu
                local bgOpacityInfo = UIDropDownMenu_CreateInfo()
                bgOpacityInfo.text = "Background Opacity"
                bgOpacityInfo.hasArrow = true
                bgOpacityInfo.value = "BGOPACITY"
                bgOpacityInfo.notCheckable = true
                UIDropDownMenu_AddButton(bgOpacityInfo, level)
                
                -- Border Opacity submenu
                local borderOpacityInfo = UIDropDownMenu_CreateInfo()
                borderOpacityInfo.text = "Border Opacity"
                borderOpacityInfo.hasArrow = true
                borderOpacityInfo.value = "BORDEROPACITY"
                borderOpacityInfo.notCheckable = true
                UIDropDownMenu_AddButton(borderOpacityInfo, level)
                
            elseif level == 2 then
                if UIDROPDOWNMENU_MENU_VALUE == "BGOPACITY" then
                    -- Background opacity options (0% to 100% in 10% increments)
                    for i = 0, 100, 10 do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = i .. "%"
                        info.checked = math.abs((frame.bgOpacity or 0.8) * 100 - i) < 5
                        info.func = function()
                            frame.bgOpacity = i / 100
                            local r, g, b, _ = frame:GetBackdropColor()
                            frame:SetBackdropColor(r, g, b, frame.bgOpacity)
                            -- Update settings button background
                            if frame.settingsButton then
                                frame.settingsButton:SetBackdropColor(0, 0, 0, frame.bgOpacity * 0.625)
                            end
                            -- Update input box
                            if frame.inputBox then
                                frame.inputBox:SetBackdropColor(0, 0, 0, frame.bgOpacity * 0.625)
                            end
                            -- Update tabs
                            for _, tab in ipairs(frame.tabs) do
                                if frame.activeTab == tab then
                                    tab:SetBackdropColor(0.2, 0.2, 0.2, frame.bgOpacity)
                                else
                                    tab:SetBackdropColor(0, 0, 0, frame.bgOpacity * 0.625)
                                end
                            end
                            -- Update add tab button
                            if frame.addTabButton then
                                frame.addTabButton:SetBackdropColor(0, 0, 0, frame.bgOpacity * 0.625)
                            end
                            if MelloChat.SaveSettings then MelloChat:SaveSettings() end
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                elseif UIDROPDOWNMENU_MENU_VALUE == "BORDEROPACITY" then
                    -- Border opacity options (0% to 100% in 10% increments)
                    for i = 0, 100, 10 do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = i .. "%"
                        info.checked = math.abs((frame.borderOpacity or 1.0) * 100 - i) < 5
                        info.func = function()
                            frame.borderOpacity = i / 100
                            frame:SetBackdropBorderColor(1, 1, 1, frame.borderOpacity)
                            -- Update settings button border
                            if frame.settingsButton then
                                frame.settingsButton:SetBackdropBorderColor(0.5, 0.5, 0.5, frame.borderOpacity)
                            end
                            -- Update all tabs
                            for _, tab in ipairs(frame.tabs) do
                                if tab.SetBackdropBorderColor then
                                    tab:SetBackdropBorderColor(0.5, 0.5, 0.5, frame.borderOpacity)
                                end
                            end
                            -- Update add tab button
                            if frame.addTabButton then
                                frame.addTabButton:SetBackdropBorderColor(0.5, 0.5, 0.5, frame.borderOpacity)
                            end
                            -- Update input box
                            if frame.inputBox then
                                frame.inputBox:SetBackdropBorderColor(0.5, 0.5, 0.5, frame.borderOpacity)
                            end
                            if MelloChat.SaveSettings then MelloChat:SaveSettings() end
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                elseif UIDROPDOWNMENU_MENU_VALUE == "FONT" then
                    for i, fontPath in ipairs(fontList) do
                        local info = UIDropDownMenu_CreateInfo()
                        local fontName = fontPath:match("([^\\]+)%.ttf$") or fontPath:match("([^\\]+)%.TTF$") or ("Font " .. i)
                        info.text = fontName
                        info.checked = frame.currentFont == fontPath
                        info.func = function()
                            frame.currentFont = fontPath
                            if frame.chatDisplay then
                                frame.chatDisplay:SetFont(fontPath, frame.currentFontSize or 11, "")
                            end
                            if MelloChat.SaveSettings then MelloChat:SaveSettings() end  -- Save font change
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                elseif UIDROPDOWNMENU_MENU_VALUE == "FONTSIZE" then
                    for _, size in ipairs(fontSizes) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = tostring(size)
                        info.checked = frame.currentFontSize == size
                        info.func = function()
                            frame.currentFontSize = size
                            if frame.chatDisplay then
                                frame.chatDisplay:SetFont(frame.currentFont or "Fonts\\ARIALN.TTF", size, "")
                            end
                            if MelloChat.SaveSettings then MelloChat:SaveSettings() end  -- Save font size change
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end
        end, "MENU")
        
        ToggleDropDownMenu(1, nil, frame.settingsDropdown, button, 0, 0)
    end
    
    -- Update initial positions
    frame:UpdateTabPositions()
    
    -- Function to set active tab
    function frame:SetActiveTab(tab)
        -- Update visual state
        for _, t in ipairs(self.tabs) do
            if t == tab then
                t:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
                t.text:SetTextColor(1, 0.82, 0)  -- Gold color for active tab
                t:SetHeight(24)  -- Slightly taller when active
                -- Stop glow if this is the whisper tab
                if t == self.whisperTab then
                    self:StopTabGlow(t)
                end
            else
                t:SetBackdropColor(0, 0, 0, 0.5)
                t.text:SetTextColor(0.7, 0.7, 0.7)
                t:SetHeight(22)
            end
        end
        
        self.activeTab = tab
        
        -- Clear and repopulate chat display
        chatDisplay:Clear()
        
        -- Apply custom font settings
        local fontPath = self.currentFont or "Fonts\\ARIALN.TTF"
        local fontSize = self.currentFontSize or 11
        chatDisplay:SetFont(fontPath, fontSize, "")
        
        for _, msg in ipairs(tab.messages) do
            chatDisplay:AddMessage(msg.text, msg.r, msg.g, msg.b)
        end
        
        -- Scroll to bottom
        C_Timer.After(0.01, function()
            chatDisplay:ScrollToBottom()
        end)
    end
    
    -- Function to start tab glow animation
    function frame:StartTabGlow(tab)
        if not tab.glowFrame then
            -- Create glow frame
            tab.glowFrame = CreateFrame("Frame", nil, tab)
            tab.glowFrame:SetAllPoints(tab)
            tab.glowFrame:SetFrameLevel(tab:GetFrameLevel() - 1)
            
            -- Create glow texture
            tab.glowTexture = tab.glowFrame:CreateTexture(nil, "BACKGROUND")
            tab.glowTexture:SetAllPoints(tab.glowFrame)
            tab.glowTexture:SetColorTexture(1, 0.82, 0, 0.5)  -- Gold glow
            
            -- Create animation group
            tab.glowAnim = tab.glowFrame:CreateAnimationGroup()
            tab.glowAnim:SetLooping("REPEAT")
            
            -- Create alpha animation
            local fadeIn = tab.glowAnim:CreateAnimation("Alpha")
            fadeIn:SetFromAlpha(0.2)
            fadeIn:SetToAlpha(0.8)
            fadeIn:SetDuration(0.5)
            fadeIn:SetOrder(1)
            
            local fadeOut = tab.glowAnim:CreateAnimation("Alpha")
            fadeOut:SetFromAlpha(0.8)
            fadeOut:SetToAlpha(0.2)
            fadeOut:SetDuration(0.5)
            fadeOut:SetOrder(2)
        end
        
        tab.glowFrame:Show()
        tab.glowAnim:Play()
        tab.isGlowing = true
    end
    
    -- Function to stop tab glow animation
    function frame:StopTabGlow(tab)
        if tab.glowFrame and tab.isGlowing then
            tab.glowAnim:Stop()
            tab.glowFrame:Hide()
            tab.isGlowing = false
        end
    end
    
    function frame:AddMessage(text, r, g, b, event)
        -- Add timestamp if enabled
        local timestamp = ""
        if GetCVar("showTimestamps") ~= "none" then
            timestamp = BetterDate(CHAT_TIMESTAMP_FORMAT, time()) .. " "
        end
        
        local fullText = timestamp .. text
        
        -- Store message in appropriate tabs
        local messageData = {
            text = fullText,
            r = r or 1,
            g = g or 1,
            b = b or 1,
            event = event
        }
        
        -- Add to tabs that match this event
        local addedToActiveTab = false
        for _, tab in ipairs(self.tabs) do
            if not event or tab.filter[event] then
                table.insert(tab.messages, messageData)
                -- Keep only last 500 messages per tab
                if #tab.messages > 500 then
                    table.remove(tab.messages, 1)
                end
                
                if tab == self.activeTab then
                    addedToActiveTab = true
                end
            end
        end
        
        -- If message should show in active tab, display it
        if addedToActiveTab then
            -- Use custom font settings if available, otherwise use defaults
            local fontPath = self.currentFont or "Fonts\\ARIALN.TTF"
            local fontSize = self.currentFontSize or 11
            chatDisplay:SetFont(fontPath, fontSize, "")
            
            chatDisplay:AddMessage(fullText, r or 1, g or 1, b or 1)
            
            -- Auto-scroll to bottom
            C_Timer.After(0.01, function()
                chatDisplay:ScrollToBottom()
            end)
        end
    end
    
    local inputBox = CreateFrame("EditBox", "MelloChatInputBox", frame, "BackdropTemplate")
    inputBox:SetHeight(20)
    inputBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 10, 35)
    inputBox:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -10, 35)
    inputBox:SetFontObject(ChatFontNormal)
    inputBox:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    inputBox:SetBackdropColor(0, 0, 0, (frame.bgOpacity or 0.8) * 0.625)
    inputBox:SetBackdropBorderColor(0.5, 0.5, 0.5, frame.borderOpacity or 1)
    inputBox:SetAutoFocus(false)
    
    -- Create channel label inside the input box
    local channelLabel = inputBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelLabel:SetPoint("LEFT", inputBox, "LEFT", 8, 0)
    channelLabel:SetText("[Say]")
    channelLabel:SetTextColor(1, 1, 1)
    
    -- Adjust text insets to make room for the channel label
    inputBox:SetTextInsets(55, 5, 3, 3)
    
    -- Default chat type
    inputBox.chatType = "SAY"
    inputBox.chatTarget = nil
    
    inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    inputBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text ~= "" then
            -- Check if it's a slash command (but not a chat command)
            if text:match("^/") and not text:match("^/[sgpyraow]%s") and not text:match("^/[12345]%s") and 
               not text:match("^/say%s") and not text:match("^/guild%s") and not text:match("^/party%s") and 
               not text:match("^/yell%s") and not text:match("^/raid%s") and not text:match("^/officer%s") and 
               not text:match("^/whisper%s") and not text:match("^/services%s") then
                -- Execute the slash command
                ChatEdit_ParseText(_G["ChatFrame1EditBox"], 0)
                _G["ChatFrame1EditBox"]:SetText(text)
                ChatEdit_SendText(_G["ChatFrame1EditBox"], 0)
                _G["ChatFrame1EditBox"]:SetText("")
            else
                -- Send regular chat message
                if self.chatType == "WHISPER" and self.chatTarget then
                    SendChatMessage(text, self.chatType, nil, self.chatTarget)
                elseif self.chatType == "CHANNEL" and self.chatTarget then
                    SendChatMessage(text, self.chatType, nil, self.chatTarget)
                else
                    SendChatMessage(text, self.chatType)
                end
            end
            self:SetText("")
        end
        self:ClearFocus()
    end)
    
    -- Function to update text insets based on label width
    local function UpdateTextInsets()
        local labelWidth = channelLabel:GetStringWidth() + 12
        inputBox:SetTextInsets(labelWidth, 5, 3, 3)
    end
    
    -- Handle chat type commands
    inputBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text:match("^/s ") or text:match("^/say ") then
            self.chatType = "SAY"
            channelLabel:SetText("[Say]")
            channelLabel:SetTextColor(1, 1, 1)
            UpdateTextInsets()
            self:SetText(text:gsub("^/s%s*", ""):gsub("^/say%s*", ""))
        elseif text:match("^/y ") or text:match("^/yell ") then
            self.chatType = "YELL"
            channelLabel:SetText("[Yell]")
            channelLabel:SetTextColor(1, 0.25, 0.25)
            UpdateTextInsets()
            self:SetText(text:gsub("^/y%s*", ""):gsub("^/yell%s*", ""))
        elseif text:match("^/p ") or text:match("^/party ") then
            self.chatType = "PARTY"
            channelLabel:SetText("[Party]")
            channelLabel:SetTextColor(0.67, 0.67, 1)
            UpdateTextInsets()
            self:SetText(text:gsub("^/p%s*", ""):gsub("^/party%s*", ""))
        elseif text:match("^/g ") or text:match("^/guild ") then
            self.chatType = "GUILD"
            channelLabel:SetText("[Guild]")
            channelLabel:SetTextColor(0.25, 1, 0.25)
            UpdateTextInsets()
            self:SetText(text:gsub("^/g%s*", ""):gsub("^/guild%s*", ""))
        elseif text:match("^/ra ") or text:match("^/raid ") then
            self.chatType = "RAID"
            channelLabel:SetText("[Raid]")
            channelLabel:SetTextColor(1, 0.5, 0)
            UpdateTextInsets()
            self:SetText(text:gsub("^/ra%s*", ""):gsub("^/raid%s*", ""))
        elseif text:match("^/o ") or text:match("^/officer ") then
            self.chatType = "OFFICER"
            channelLabel:SetText("[Officer]")
            channelLabel:SetTextColor(0.25, 0.75, 0.25)
            UpdateTextInsets()
            self:SetText(text:gsub("^/o%s*", ""):gsub("^/officer%s*", ""))
        elseif text:match("^/w ") or text:match("^/whisper ") then
            local _, _, target, msg = text:find("^/w%s+(%S+)%s*(.*)")
            if not target then
                _, _, target, msg = text:find("^/whisper%s+(%S+)%s*(.*)")
            end
            if target then
                self.chatType = "WHISPER"
                self.chatTarget = target
                local targetWithoutRealm = string.match(target, "([^%-]+)") or target
                channelLabel:SetText("[To " .. targetWithoutRealm .. "]")
                channelLabel:SetTextColor(1, 0.5, 1)
                UpdateTextInsets()
                self:SetText(msg or "")
            end
        elseif text:match("^/1 ") then
            self.chatType = "CHANNEL"
            self.chatTarget = 1
            channelLabel:SetText("[1. General]")
            channelLabel:SetTextColor(1, 0.75, 0.75)
            UpdateTextInsets()
            self:SetText(text:gsub("^/1%s*", ""))
        elseif text:match("^/2 ") then
            self.chatType = "CHANNEL"
            self.chatTarget = 2
            channelLabel:SetText("[2. Trade]")
            channelLabel:SetTextColor(1, 0.75, 0.75)
            UpdateTextInsets()
            self:SetText(text:gsub("^/2%s*", ""))
        elseif text:match("^/3 ") then
            self.chatType = "CHANNEL"
            self.chatTarget = 3
            channelLabel:SetText("[3. LocalDefense]")
            channelLabel:SetTextColor(1, 0.75, 0.75)
            UpdateTextInsets()
            self:SetText(text:gsub("^/3%s*", ""))
        elseif text:match("^/4 ") then
            self.chatType = "CHANNEL"
            self.chatTarget = 4
            channelLabel:SetText("[4. LookingForGroup]")
            channelLabel:SetTextColor(1, 0.75, 0.75)
            UpdateTextInsets()
            self:SetText(text:gsub("^/4%s*", ""))
        elseif text:match("^/5 ") or text:match("^/services ") then
            self.chatType = "CHANNEL"
            self.chatTarget = 5
            channelLabel:SetText("[5. Services]")
            channelLabel:SetTextColor(1, 0.5, 0.5)
            UpdateTextInsets()
            self:SetText(text:gsub("^/5%s*", ""):gsub("^/services%s*", ""))
        end
    end)
    
    -- Store references
    frame.inputBox = inputBox
    frame.channelLabel = channelLabel
    
    -- Dialog for adding new tab
    function frame:ShowAddTabDialog()
        StaticPopupDialogs["MELLOCHAT_ADD_TAB"] = {
            text = "Enter name for new tab:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local text = self.editBox:GetText()
                if text and text ~= "" then
                    frame:CreateNewTab(text)
                end
            end,
            EditBoxOnEnterPressed = function(self)
                local text = self:GetText()
                if text and text ~= "" then
                    frame:CreateNewTab(text)
                    self:GetParent():Hide()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("MELLOCHAT_ADD_TAB")
    end
    
    -- Dialog for renaming tab
    function frame:ShowRenameTabDialog(tab)
        StaticPopupDialogs["MELLOCHAT_RENAME_TAB"] = {
            text = "Enter new name for tab:",
            button1 = "Rename",
            button2 = "Cancel",
            hasEditBox = true,
            OnShow = function(self)
                self.editBox:SetText(tab.name)
                self.editBox:HighlightText()
            end,
            OnAccept = function(self)
                local text = self.editBox:GetText()
                if text and text ~= "" then
                    frame:RenameTab(tab, text)
                end
            end,
            EditBoxOnEnterPressed = function(self)
                local text = self:GetText()
                if text and text ~= "" then
                    frame:RenameTab(tab, text)
                    self:GetParent():Hide()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("MELLOCHAT_RENAME_TAB")
    end
    
    -- Function to create new tab
    function frame:CreateNewTab(name)
        -- Create empty filter (shows all messages)
        local filter = {}
        
        local newTab = CreateTab(name, filter)
        table.insert(self.tabs, newTab)
        self:UpdateTabPositions()
        self:SetActiveTab(newTab)
        if MelloChat.SaveSettings then
            MelloChat:SaveSettings()  -- Save after adding new tab
        end
    end
    
    -- Function to rename tab
    function frame:RenameTab(tab, newName)
        tab.name = newName
        tab.text:SetText(newName)
        
        -- Resize tab based on new text
        local textWidth = tab.text:GetStringWidth()
        tab:SetWidth(textWidth + 20)
        
        self:UpdateTabPositions()
        if MelloChat.SaveSettings then MelloChat:SaveSettings() end  -- Save after renaming tab
    end
    
    -- Set initial active tab
    frame:SetActiveTab(generalTab)
    
    return frame
end

local function HideDefaultChatFrame()
    -- Hide all chat frames more safely
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame"..i]
        if chatFrame then
            -- Don't unregister all events - just hide visually
            chatFrame:EnableMouse(false)
            chatFrame:EnableMouseWheel(false)
            chatFrame:SetAlpha(0)
            
            -- Move off screen but keep accessible
            if i == 1 then
                chatFrame:ClearAllPoints()
                chatFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -1000, 1000)
            else
                chatFrame:Hide()
            end
        end
        
        local tab = _G["ChatFrame"..i.."Tab"]
        if tab then
            tab:SetAlpha(0)
            tab:EnableMouse(false)
        end
        
        local editBox = _G["ChatFrame"..i.."EditBox"]
        if editBox then
            editBox:SetAlpha(0)
            editBox:EnableMouse(false)
        end
        
        local buttonFrame = _G["ChatFrame"..i.."ButtonFrame"]
        if buttonFrame then
            buttonFrame:SetAlpha(0)
        end
        
        local background = _G["ChatFrame"..i.."Background"]
        if background then
            background:SetAlpha(0)
        end
    end
    
    -- Hide chat UI elements but keep dock manager functional
    local elementsToHide = {
        "ChatFrameMenuButton",
        "ChatFrameChannelButton", 
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
        "QuickJoinToastButton",
        "ChatFrame1Background"
    }
    
    for _, elementName in ipairs(elementsToHide) do
        local element = _G[elementName]
        if element then
            element:SetAlpha(0)
            element:EnableMouse(false)
        end
    end
    
    -- Keep GeneralDockManager but make it invisible
    if GeneralDockManager then
        GeneralDockManager:SetAlpha(0)
        GeneralDockManager:EnableMouse(false)
    end
    
    -- Ensure ChatFrame1 stays hidden visually
    ChatFrame1:HookScript("OnShow", function(self)
        self:SetAlpha(0)
    end)
end

-- Module functions
function MelloChat:OnInitialize()
    -- Module is registered but not yet enabled
end

function MelloChat:OnEnable()
    if isEnabled then return end
    isEnabled = true
    
    -- Create event frame for chat events
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    eventFrame:RegisterEvent("CHAT_MSG_SAY")
    eventFrame:RegisterEvent("CHAT_MSG_YELL")
    eventFrame:RegisterEvent("CHAT_MSG_PARTY")
    eventFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
    eventFrame:RegisterEvent("CHAT_MSG_RAID")
    eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
    eventFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
    eventFrame:RegisterEvent("CHAT_MSG_GUILD")
    eventFrame:RegisterEvent("CHAT_MSG_OFFICER")
    eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
    eventFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    eventFrame:RegisterEvent("CHAT_MSG_SKILL")
    eventFrame:RegisterEvent("CHAT_MSG_EMOTE")
    eventFrame:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
    eventFrame:RegisterEvent("CHAT_MSG_MONSTER_SAY")
    eventFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
    eventFrame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
    eventFrame:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
    eventFrame:RegisterEvent("CHAT_MSG_ACHIEVEMENT")
    eventFrame:RegisterEvent("CHAT_MSG_GUILD_ACHIEVEMENT")
    eventFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
    eventFrame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
    eventFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
    eventFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_JOIN")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")
    eventFrame:RegisterEvent("CHAT_MSG_CURRENCY")
    eventFrame:RegisterEvent("CHAT_MSG_TRADESKILLS")
    eventFrame:RegisterEvent("CHAT_MSG_OPENING")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
    eventFrame:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
    eventFrame:RegisterEvent("CHAT_MSG_RAID_BOSS_WHISPER")
    eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
    eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
    eventFrame:RegisterEvent("CHAT_MSG_PET_INFO")
    eventFrame:RegisterEvent("CHAT_MSG_AFK")
    eventFrame:RegisterEvent("CHAT_MSG_DND")
    eventFrame:RegisterEvent("CHAT_MSG_IGNORED")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_MISC_INFO")
    
    -- Hide default chat frame
    HideDefaultChatFrame()
    
    -- Create MelloChat frame
    melloChatFrame = CreateMelloChatFrame()
    
    -- Load saved settings
    C_Timer.After(0.5, function()
        if MelloUISavedVars and MelloUISavedVars.MelloChatDB then
            self:LoadSettings()
        end
    end)
    
    -- Keep default chat hidden
    C_Timer.NewTicker(0.1, function()
        if not isEnabled then return end
        for i = 1, NUM_CHAT_WINDOWS do
            local chatFrame = _G["ChatFrame"..i]
            if chatFrame and chatFrame:GetAlpha() > 0 then
                chatFrame:SetAlpha(0)
            end
            
            local tab = _G["ChatFrame"..i.."Tab"]
            if tab and tab:GetAlpha() > 0 then
                tab:SetAlpha(0)
            end
        end
    end)
    
    -- Override functions
    if ChatFrame_ConfigEventHandler then
        local oldHandler = ChatFrame_ConfigEventHandler
        ChatFrame_ConfigEventHandler = function(self, event, ...)
            if event ~= "CHAT_MSG_WHISPER" and event ~= "CHAT_MSG_BN_WHISPER" then
                return oldHandler(self, event, ...)
            end
        end
    end
    
    SetCVar("whisperMode", "inline")
    SetCVar("chatStyle", "classic")
    
    -- Hook into the default chat opening
    hooksecurefunc("ChatFrame_OpenChat", function(text, chatFrame)
        if not isEnabled then return end
        -- Clear the default chat frame
        for i = 1, NUM_CHAT_WINDOWS do
            local editBox = _G["ChatFrame"..i.."EditBox"]
            if editBox and editBox:IsShown() then
                editBox:Hide()
                editBox:ClearFocus()
            end
        end
        
        -- Open our custom chat
        if melloChatFrame and melloChatFrame.inputBox then
            melloChatFrame.inputBox:SetText(text or "")
            melloChatFrame.inputBox:SetFocus()
        end
    end)
    
    -- Set up event handler
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if not isEnabled or not melloChatFrame then return end
        
        local message, sender, language, channelString, target, flags, _, channelNumber, channelName, _, lineID, guid = ...
        local formattedMessage = ""
        local r, g, b = 1, 1, 1
        
        -- Fix for channel events
        if event == "CHAT_MSG_CHANNEL" then
            if type(channelName) == "number" then
                channelNumber, channelName = channelName, channelNumber
            end
        end
        
        -- Create player link with class color
        local playerLink = GetClassColoredName(sender, guid)
        
        -- Format messages based on event type
        if event == "CHAT_MSG_SAY" then
            formattedMessage = string.format("%s: %s", playerLink, message)
            r, g, b = 1, 1, 1
        elseif event == "CHAT_MSG_YELL" then
            formattedMessage = string.format("%s yells: %s", playerLink, message)
            r, g, b = 1, 0.25, 0.25
        elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
            formattedMessage = string.format("[P] %s: %s", playerLink, message)
            r, g, b = 0.67, 0.67, 1
        elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
            formattedMessage = string.format("[R] %s: %s", playerLink, message)
            r, g, b = 1, 0.5, 0
        elseif event == "CHAT_MSG_GUILD" then
            formattedMessage = string.format("[G] %s: %s", playerLink, message)
            r, g, b = 0.25, 1, 0.25
        elseif event == "CHAT_MSG_OFFICER" then
            formattedMessage = string.format("[O] %s: %s", playerLink, message)
            r, g, b = 0.25, 0.75, 0.25
        elseif event == "CHAT_MSG_WHISPER" then
            formattedMessage = string.format("%s whispers: %s", playerLink, message)
            r, g, b = 1, 0.5, 1
            PlaySound(SOUNDKIT.TELL_MESSAGE)
            HideDefaultChatFrame()
            if melloChatFrame and melloChatFrame.whisperTab and melloChatFrame.activeTab ~= melloChatFrame.whisperTab then
                melloChatFrame:StartTabGlow(melloChatFrame.whisperTab)
            end
        elseif event == "CHAT_MSG_WHISPER_INFORM" then
            formattedMessage = string.format("To %s: %s", playerLink, message)
            r, g, b = 1, 0.5, 1
        elseif event == "CHAT_MSG_CHANNEL" then
            local channelNameLower = channelName and type(channelName) == "string" and channelName:lower() or ""
            if string.find(channelNameLower, "services") or string.find(channelNameLower, "trade") then
                formattedMessage = string.format("[%d] %s: %s", channelNumber or 0, playerLink, message)
                r, g, b = 1, 0.5, 0.5
            else
                formattedMessage = string.format("[%d] %s: %s", channelNumber or 0, playerLink, message)
                r, g, b = 1, 0.75, 0.75
            end
        elseif event == "CHAT_MSG_SYSTEM" then
            formattedMessage = message
            r, g, b = 1, 1, 0
        elseif event == "CHAT_MSG_RAID_WARNING" then
            formattedMessage = string.format("[RW] %s: %s", playerLink, message)
            r, g, b = 1, 0.28, 0
        elseif event == "CHAT_MSG_LOOT" then
            formattedMessage = message
            r, g, b = 0, 0.67, 0
        elseif event == "CHAT_MSG_MONEY" then
            formattedMessage = message
            r, g, b = 1, 1, 0
        elseif event == "CHAT_MSG_SKILL" then
            formattedMessage = message
            r, g, b = 0.33, 0.33, 1
        elseif event == "CHAT_MSG_EMOTE" then
            formattedMessage = string.format("%s %s", playerLink, message)
            r, g, b = 1, 0.5, 0.25
        elseif event == "CHAT_MSG_TEXT_EMOTE" then
            formattedMessage = message
            r, g, b = 1, 0.5, 0.25
        elseif event == "CHAT_MSG_MONSTER_SAY" then
            formattedMessage = string.format("%s says: %s", sender, message)
            r, g, b = 1, 1, 0.63
        elseif event == "CHAT_MSG_MONSTER_YELL" then
            formattedMessage = string.format("%s yells: %s", sender, message)
            r, g, b = 1, 0.25, 0.25
        elseif event == "CHAT_MSG_MONSTER_EMOTE" then
            formattedMessage = string.format("%s %s", sender, message)
            r, g, b = 1, 0.5, 0.25
        elseif event == "CHAT_MSG_MONSTER_WHISPER" then
            formattedMessage = string.format("%s whispers: %s", sender, message)
            r, g, b = 1, 0.71, 0.92
        elseif event == "CHAT_MSG_ACHIEVEMENT" then
            formattedMessage = message
            r, g, b = 1, 1, 0
        elseif event == "CHAT_MSG_GUILD_ACHIEVEMENT" then
            formattedMessage = message
            r, g, b = 0.25, 1, 0.25
        elseif event == "CHAT_MSG_BN_WHISPER" then
            formattedMessage = string.format("%s whispers: %s", sender, message)
            r, g, b = 0, 1, 0.96
            PlaySound(SOUNDKIT.TELL_MESSAGE)
            HideDefaultChatFrame()
            if melloChatFrame and melloChatFrame.whisperTab and melloChatFrame.activeTab ~= melloChatFrame.whisperTab then
                melloChatFrame:StartTabGlow(melloChatFrame.whisperTab)
            end
        elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
            formattedMessage = string.format("To %s: %s", sender, message)
            r, g, b = 0, 1, 0.96
        elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
            formattedMessage = string.format("[I] %s: %s", playerLink, message)
            r, g, b = 1, 0.5, 0
        end
        
        if formattedMessage ~= "" then
            melloChatFrame:AddMessage(formattedMessage, r, g, b, event)
        end
    end)
    
    -- Override FCF functions
    if FCF_StartAlertFlash then
        FCF_StartAlertFlash = function() end
    end
    
    if FCF_StopAlertFlash then
        FCF_StopAlertFlash = function() end
    end
    
    if FCF_FlashTab then
        FCF_FlashTab = function() end
    end
    
    if FCF_OpenTemporaryWindow then
        FCF_OpenTemporaryWindow = function() return nil end
    end
    
    if FCF_SetTemporaryWindowType then
        FCF_SetTemporaryWindowType = function() end
    end
    
    -- Disable chat alert frame
    if ChatAlertFrame then
        ChatAlertFrame:UnregisterAllEvents()
        ChatAlertFrame:Hide()
        ChatAlertFrame.Show = function() end
    end
    
    -- Hook SetShown to prevent chat frames from being shown
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame"..i]
        if chatFrame then
            hooksecurefunc(chatFrame, "SetShown", function(self, shown)
                if shown and isEnabled then
                    self:SetAlpha(0)
                end
            end)
        end
    end
    
    -- Disable chat frame fading
    CHAT_FRAME_FADE_TIME = 0
    CHAT_FRAME_FADE_OUT_TIME = 0
    CHAT_TAB_SHOW_DELAY = 0
    CHAT_TAB_HIDE_DELAY = 0
    CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA = 0
    CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0
    CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA = 0
    CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0
    
    -- Bind Enter key to open our chat
    local function OpenMelloChat()
        if melloChatFrame and melloChatFrame.inputBox then
            melloChatFrame.inputBox:SetFocus()
        end
    end
    
    SetOverrideBindingClick(melloChatFrame, true, "ENTER", "MelloChatButton")
    local button = CreateFrame("Button", "MelloChatButton", UIParent)
    button:SetScript("OnClick", OpenMelloChat)
    
    -- Bind R key for reply
    SetOverrideBindingClick(melloChatFrame, true, "R", "MelloChatReplyButton")
    local replyButton = CreateFrame("Button", "MelloChatReplyButton", UIParent)
    replyButton:SetScript("OnClick", function()
        local lastTell = ChatEdit_GetLastTellTarget()
        if lastTell and lastTell ~= "" then
            if melloChatFrame and melloChatFrame.inputBox then
                melloChatFrame.inputBox.chatType = "WHISPER"
                melloChatFrame.inputBox.chatTarget = lastTell
                local lastTellWithoutRealm = string.match(lastTell, "([^%-]+)") or lastTell
                melloChatFrame.channelLabel:SetText("[To " .. lastTellWithoutRealm .. "]")
                melloChatFrame.channelLabel:SetTextColor(1, 0.5, 1)
                local labelWidth = melloChatFrame.channelLabel:GetStringWidth() + 12
                melloChatFrame.inputBox:SetTextInsets(labelWidth, 5, 3, 3)
                melloChatFrame.inputBox:SetFocus()
            end
        end
    end)
end

function MelloChat:OnDisable()
    if not isEnabled then return end
    isEnabled = false
    
    -- Unregister events
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    
    -- Clear bindings
    if melloChatFrame then
        ClearOverrideBindings(melloChatFrame)
        melloChatFrame:Hide()
    end
    
    -- Restore default chat (basic restoration)
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame"..i]
        if chatFrame then
            chatFrame.Show = nil
            chatFrame.SetAlpha = nil
            if i == 1 then
                chatFrame:Show()
                chatFrame:SetAlpha(1)
            end
        end
    end
    
    print("|cFFFFFF00MelloChat disabled. /reload to fully restore default chat.|r")
end

-- Save settings function
function MelloChat:SaveSettings()
    if not melloChatFrame then return end
    
    MelloUISavedVars = MelloUISavedVars or {}
    MelloUISavedVars.MelloChatDB = MelloUISavedVars.MelloChatDB or {}
    local db = MelloUISavedVars.MelloChatDB
    
    -- Save window position and size
    local point, _, relativePoint, xOfs, yOfs = melloChatFrame:GetPoint()
    db.windowPosition = {
        point = point,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs,
        width = melloChatFrame:GetWidth(),
        height = melloChatFrame:GetHeight()
    }
    
    -- Save font settings
    db.font = melloChatFrame.currentFont
    db.fontSize = melloChatFrame.currentFontSize
    
    -- Save opacity settings
    db.bgOpacity = melloChatFrame.bgOpacity or 0.8
    db.borderOpacity = melloChatFrame.borderOpacity or 1.0
    
    -- Save lock state
    db.isLocked = melloChatFrame.isLocked
    
    -- Save tabs
    if melloChatFrame.tabs and #melloChatFrame.tabs > 0 then
        db.tabs = {}
        for i, tab in ipairs(melloChatFrame.tabs) do
            local tabData = {
                name = tab.name,
                filter = {}
            }
            for event, enabled in pairs(tab.filter) do
                tabData.filter[event] = enabled
            end
            table.insert(db.tabs, tabData)
        end
    end
    
    -- Save active tab index
    for i, tab in ipairs(melloChatFrame.tabs) do
        if tab == melloChatFrame.activeTab then
            db.activeTabIndex = i
            break
        end
    end
end

-- Load settings function
function MelloChat:LoadSettings()
    if not MelloUISavedVars or not MelloUISavedVars.MelloChatDB or not melloChatFrame then return end
    local db = MelloUISavedVars.MelloChatDB
    
    -- Load window position and size
    if db.windowPosition then
        local pos = db.windowPosition
        melloChatFrame:ClearAllPoints()
        melloChatFrame:SetPoint(pos.point or "BOTTOMLEFT", UIParent, pos.relativePoint or "BOTTOMLEFT", pos.xOfs or 7.5, pos.yOfs or 7.5)
        melloChatFrame:SetSize(pos.width or 493, pos.height or 412)
    end
    
    -- Load font settings
    if db.font then
        melloChatFrame.currentFont = db.font
    end
    if db.fontSize then
        melloChatFrame.currentFontSize = db.fontSize
        if melloChatFrame.chatDisplay then
            melloChatFrame.chatDisplay:SetFont(melloChatFrame.currentFont or "Fonts\\ARIALN.TTF", melloChatFrame.currentFontSize or 11, "")
        end
    end
    
    -- Load opacity settings
    if db.bgOpacity then
        melloChatFrame.bgOpacity = db.bgOpacity
        melloChatFrame:SetBackdropColor(0, 0, 0, melloChatFrame.bgOpacity)
        -- Update all child frames with appropriate opacity
        if melloChatFrame.settingsButton then
            melloChatFrame.settingsButton:SetBackdropColor(0, 0, 0, melloChatFrame.bgOpacity * 0.625)
        end
        if melloChatFrame.inputBox then
            melloChatFrame.inputBox:SetBackdropColor(0, 0, 0, melloChatFrame.bgOpacity * 0.625)
        end
        -- Update tabs
        for _, tab in ipairs(melloChatFrame.tabs) do
            if melloChatFrame.activeTab == tab then
                tab:SetBackdropColor(0.2, 0.2, 0.2, melloChatFrame.bgOpacity)
            else
                tab:SetBackdropColor(0, 0, 0, melloChatFrame.bgOpacity * 0.625)
            end
        end
        if melloChatFrame.addTabButton then
            melloChatFrame.addTabButton:SetBackdropColor(0, 0, 0, melloChatFrame.bgOpacity * 0.625)
        end
    end
    
    if db.borderOpacity then
        melloChatFrame.borderOpacity = db.borderOpacity
        melloChatFrame:SetBackdropBorderColor(1, 1, 1, melloChatFrame.borderOpacity)
        -- Update all child frames with border opacity
        if melloChatFrame.settingsButton then
            melloChatFrame.settingsButton:SetBackdropBorderColor(0.5, 0.5, 0.5, melloChatFrame.borderOpacity)
        end
        if melloChatFrame.inputBox then
            melloChatFrame.inputBox:SetBackdropBorderColor(0.5, 0.5, 0.5, melloChatFrame.borderOpacity)
        end
        -- Update tabs
        for _, tab in ipairs(melloChatFrame.tabs) do
            tab:SetBackdropBorderColor(0.5, 0.5, 0.5, melloChatFrame.borderOpacity)
        end
        if melloChatFrame.addTabButton then
            melloChatFrame.addTabButton:SetBackdropBorderColor(0.5, 0.5, 0.5, melloChatFrame.borderOpacity)
        end
    end
    
    -- Load lock state
    if db.isLocked ~= nil then
        melloChatFrame.isLocked = db.isLocked
        if melloChatFrame.isLocked then
            melloChatFrame:SetMovable(false)
            melloChatFrame:SetResizable(false)
            if melloChatFrame.resizeButton then
                melloChatFrame.resizeButton:Hide()
            end
        else
            melloChatFrame:SetMovable(true)
            melloChatFrame:SetResizable(true)
            if melloChatFrame.resizeButton then
                melloChatFrame.resizeButton:Show()
            end
        end
    end
    
    -- Load tabs
    if db.tabs and type(db.tabs) == "table" and #db.tabs > 0 then
        local hasValidTabs = false
        for _, tabData in ipairs(db.tabs) do
            if tabData.name and type(tabData.name) == "string" and tabData.name ~= "" then
                hasValidTabs = true
                break
            end
        end
        
        if hasValidTabs then
            -- Clear all default tabs
            for _, tab in ipairs(melloChatFrame.tabs) do
                tab:Hide()
            end
            melloChatFrame.tabs = {}
            
            -- Recreate tabs from saved data
            for i, tabData in ipairs(db.tabs) do
                if tabData.name and tabData.name ~= "" then
                    melloChatFrame:CreateNewTab(tabData.name)
                    local newTab = melloChatFrame.tabs[#melloChatFrame.tabs]
                    -- Update filter
                    newTab.filter = {}
                    if tabData.filter then
                        for event, enabled in pairs(tabData.filter) do
                            newTab.filter[event] = enabled
                        end
                    end
                end
            end
            
            -- Update tab positions
            melloChatFrame:UpdateTabPositions()
            
            -- Set active tab
            if db.activeTabIndex and melloChatFrame.tabs[db.activeTabIndex] then
                melloChatFrame:SetActiveTab(melloChatFrame.tabs[db.activeTabIndex])
            elseif #melloChatFrame.tabs > 0 then
                melloChatFrame:SetActiveTab(melloChatFrame.tabs[1])
            end
        end
    end
end

-- Slash command
SLASH_MELLOCHAT1 = "/mellochat"
SlashCmdList["MELLOCHAT"] = function(msg)
    if melloChatFrame then
        if melloChatFrame:IsShown() then
            melloChatFrame:Hide()
        else
            melloChatFrame:Show()
        end
    end
end