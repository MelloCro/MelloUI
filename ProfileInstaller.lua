local addonName, ns = ...
MelloUIProfileInstaller = {}
local ProfileInstaller = MelloUIProfileInstaller

local moduleList = {
    {
        name = "Core",
        displayName = "MelloUI - Interface Reskin",
        description = "Applies a black color theme to various UI elements",
        required = true
    },
    {
        name = "AutoGraphicsSettings",
        displayName = "Auto Graphics Settings",
        description = "Automatically sets optimal graphics settings on login"
    },
    {
        name = "EnhancedBags",
        displayName = "Enhanced Bags",
        description = "Enhances the default backpack with item levels and vendor prices"
    },
    {
        name = "EnhancedCharacterFrame",
        displayName = "Enhanced Character Frame",
        description = "Adds item levels and M+ rating to the character window"
    },
    {
        name = "DPSMeter",
        displayName = "DPS Meter - WIP",
        description = "Lightweight damage meter (Work in Progress - Currently disabled)",
        disabled = true
    },
    {
        name = "Nameplates",
        displayName = "Custom Nameplates",
        description = "Customize nameplate width, height, and texture"
    },
    {
        name = "Tooltip",
        displayName = "Enhanced Tooltips",
        description = "Modifies game tooltips with class colors and M+ ratings"
    },
    {
        name = "DungeonTeleporter",
        displayName = "Dungeon Teleporter",
        description = "Adds teleport buttons to the Mythic+ interface"
    },
    {
        name = "MelloChat",
        displayName = "MelloChat",
        description = "Replaces the default chat window with a customizable tabbed interface"
    }
}

-- Function to get the actual enabled state of a module
local function GetModuleEnabledState(moduleName)
    return ns:IsModuleEnabled(moduleName)
end

local function CreateCheckbox(parent, index, moduleData)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", 20, -60 - (index - 1) * 70)
    
    -- Get the actual enabled state of the module
    local isEnabled = GetModuleEnabledState(moduleData.name)
    checkbox:SetChecked(isEnabled)
    
    if moduleData.required then
        checkbox:Disable()
        checkbox:SetChecked(true)
    elseif moduleData.disabled then
        checkbox:Disable()
        checkbox:SetChecked(false)
    end
    
    checkbox.Text:SetText(moduleData.displayName)
    if moduleData.disabled then
        checkbox.Text:SetTextColor(0.5, 0.5, 0.5)
    else
        checkbox.Text:SetTextColor(1, 1, 1)
    end
    checkbox.Text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    
    local description = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    description:SetPoint("TOPLEFT", checkbox.Text, "BOTTOMLEFT", 0, -5)
    description:SetText(moduleData.description)
    if moduleData.disabled then
        description:SetTextColor(0.4, 0.4, 0.4)
    else
        description:SetTextColor(0.8, 0.8, 0.8)
    end
    description:SetWidth(400)
    description:SetJustifyH("LEFT")
    
    checkbox.moduleName = moduleData.name
    checkbox.moduleData = moduleData
    
    return checkbox
end

local function CreateProfileInstallerFrame()
    local frame = CreateFrame("Frame", "MelloUIProfileInstallerFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 100 + #moduleList * 70)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    
    frame.TitleText:SetText("MelloUI Module Manager")
    
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", frame.TitleText, "BOTTOM", 0, -10)
    subtitle:SetText("Select which modules you want to enable:")
    
    frame.checkboxes = {}
    
    for i, moduleData in ipairs(moduleList) do
        local checkbox = CreateCheckbox(frame, i, moduleData)
        table.insert(frame.checkboxes, checkbox)
    end
    
    local applyButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    applyButton:SetSize(120, 30)
    applyButton:SetPoint("BOTTOMRIGHT", -20, 20)
    applyButton:SetText("Apply & Reload")
    applyButton:SetScript("OnClick", function()
        ProfileInstaller:ApplyProfile(frame)
    end)
    
    local cancelButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    cancelButton:SetSize(80, 30)
    cancelButton:SetPoint("RIGHT", applyButton, "LEFT", -10, 0)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    local selectAllButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    selectAllButton:SetSize(80, 30)
    selectAllButton:SetPoint("BOTTOMLEFT", 20, 20)
    selectAllButton:SetText("Select All")
    selectAllButton:SetScript("OnClick", function()
        for _, checkbox in ipairs(frame.checkboxes) do
            if not checkbox.moduleData.required and not checkbox.moduleData.disabled then
                checkbox:SetChecked(true)
            end
        end
    end)
    
    local selectNoneButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    selectNoneButton:SetSize(100, 30)
    selectNoneButton:SetPoint("LEFT", selectAllButton, "RIGHT", 10, 0)
    selectNoneButton:SetText("Select None")
    selectNoneButton:SetScript("OnClick", function()
        for _, checkbox in ipairs(frame.checkboxes) do
            if not checkbox.moduleData.required and not checkbox.moduleData.disabled then
                checkbox:SetChecked(false)
            end
        end
    end)
    
    return frame
end

function ProfileInstaller:ApplyProfile(frame)
    local selections = {}
    
    for _, checkbox in ipairs(frame.checkboxes) do
        local moduleName = checkbox.moduleName
        local isChecked = checkbox:GetChecked()
        
        -- Skip disabled modules
        if checkbox.moduleData.disabled then
            selections[moduleName] = false
            ns:DisableModule(moduleName)
        else
            selections[moduleName] = isChecked
            
            -- Enable or disable the module
            if isChecked then
                ns:EnableModule(moduleName)
            else
                ns:DisableModule(moduleName)
            end
        end
    end
    
    MelloUISavedVars.moduleSelections = selections
    
    ReloadUI()
end

function ProfileInstaller:CheckFirstTimeSetup()
    if not MelloUISavedVars then
        MelloUISavedVars = {}
    end
    
    if not MelloUISavedVars.firstLoginDone then
        return true
    end
    
    return false
end

function ProfileInstaller:Initialize()
    if self:CheckFirstTimeSetup() then
        local frame = CreateProfileInstallerFrame()
        frame:Show()
    end
end

function ProfileInstaller:GetModuleList()
    return moduleList
end

function ProfileInstaller:ShowInstaller()
    local frame = CreateProfileInstallerFrame()
    frame:Show()
end

-- Register slash commands
SLASH_MELLOUIPROFILE1 = "/melloui"
SLASH_MELLOUIPROFILE2 = "/mellouiprofile"
SLASH_MELLOUIPROFILE3 = "/mellouisetup"

SlashCmdList["MELLOUIPROFILE"] = function(msg)
    ProfileInstaller:ShowInstaller()
end