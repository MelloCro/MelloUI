-- MelloUI Module Loader System
local addonName, ns = ...
ns.modules = {}
ns.moduleOrder = {}

-- Module registration function
function ns:RegisterModule(name, module)
    ns.modules[name] = module
    table.insert(ns.moduleOrder, name)
end

-- Module initialization
function ns:InitializeModules()
    -- Load saved variables
    MelloUISavedVars = MelloUISavedVars or {}
    MelloUISavedVars.enabledModules = MelloUISavedVars.enabledModules or {
        ["Core"] = true, -- Core is always enabled
        ["AutoGraphicsSettings"] = false,
        ["DPSMeter"] = false,
        ["Nameplates"] = false,
        ["Tooltip"] = false,
        ["EnhancedBags"] = false,
        ["EnhancedCharacterFrame"] = false,
        ["DungeonTeleporter"] = false,
        ["MelloChat"] = false
    }
    
    -- Initialize all modules first
    for _, moduleName in ipairs(ns.moduleOrder) do
        local module = ns.modules[moduleName]
        if module then
            if module.OnInitialize then
                module:OnInitialize()
            end
        end
    end
    
    -- Then enable modules that should be enabled
    for _, moduleName in ipairs(ns.moduleOrder) do
        local module = ns.modules[moduleName]
        if module and MelloUISavedVars.enabledModules[moduleName] then
            if module.OnEnable then
                module:OnEnable()
            end
        end
    end
end

-- Enable module
function ns:EnableModule(name)
    if ns.modules[name] then
        MelloUISavedVars.enabledModules[name] = true
        local module = ns.modules[name]
        if module.OnEnable then
            module:OnEnable()
        end
    end
end

-- Disable module
function ns:DisableModule(name)
    if ns.modules[name] and name ~= "Core" then -- Cannot disable Core
        MelloUISavedVars.enabledModules[name] = false
        local module = ns.modules[name]
        if module.OnDisable then
            module:OnDisable()
        end
    end
end

-- Check if module is enabled
function ns:IsModuleEnabled(name)
    return MelloUISavedVars.enabledModules[name] or false
end

-- Get list of all modules
function ns:GetModules()
    return ns.modules
end