local addonName, ns = ...

-- Initialize the module system
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize SavedVariables
        MelloUISavedVars = MelloUISavedVars or {}
        
        -- Initialize modules
        ns:InitializeModules()
        
        -- Check if this is first login
        if not MelloUISavedVars.firstLoginDone then
            -- Show the installer
            if MelloUIProfileInstaller and MelloUIProfileInstaller.ShowInstaller then
                MelloUIProfileInstaller:ShowInstaller()
            end
            MelloUISavedVars.firstLoginDone = true
        end
    elseif event == "PLAYER_LOGIN" then
        -- Any additional setup after player login
    end
end)