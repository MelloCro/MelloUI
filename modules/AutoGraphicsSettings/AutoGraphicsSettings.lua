-- MelloUI AutoGraphicsSettings Module
local addonName, ns = ...
local AutoGraphicsSettings = {}

local graphicsSettings = {
    {"Sound_MasterVolume", "0.2"},
    {"graphicsDepthEffects", "0"},
    {"lodObjectCullSize", "35"},
    {"graphicsQuality", "0"},
    {"graphicsProjectedTextures", "1"},
    {"horizonStart", "4000"},
    {"raidGraphicsSpellDensity", "4"},
    {"lodObjectFadeScale", "50"},
    {"projectedTextures", "1"},
    {"graphicsGroundClutter", "0"},
    {"farclip", "10000"},
    {"graphicsLiquidDetail", "0"},
    {"doodadLodScale", "50"},
    {"graphicsShadowQuality", "0"},
    {"vsync", "0"},
    {"maxFPSBk", "60"},
    {"GxApi", "D3D12"},
    {"graphicsComputeEffects", "0"},
    {"volumeFogLevel", "0"},
    {"spellClutter", "100"},
    {"particleDensity", "80"},
    {"horizonClip", "10000"},
    {"graphicsViewDistance", "9"},
    {"LowLatencyMode", "3"},
    {"groundEffectDist", "40"},
    {"ffxAntiAliasingMode", "4"},
    {"terrainLodDist", "650"},
    {"reflectionMode", "0"},
    {"Gamma", "1.2000000476837"},
    {"graphicsTextureResolution", "2"},
    {"graphicsSpellDensity", "0"},
    {"graphicsEnvironmentDetail", "0"},
    {"raidGraphicsSSAO", "3"},
    {"ResampleSharpness", "0"},
    {"MSAAQuality", "3"},
    {"graphicsParticleDensity", "4"},
    {"rippleDetail", "0"},
    {"weatherDensity", "3"},
    {"GxMaximize", "1"},
    {"graphicsSSAO", "0"},
    {"nameplateShowEnemies", "1"},
    {"nameplateMaxDistance", "50"},
    {"nameplateOverlapH", "0.7"},
    {"nameplateOverlapV", "0.7"},
}

local function ApplyGraphicsSettings()
    for _, setting in ipairs(graphicsSettings) do
        local cvar = setting[1]
        local value = setting[2]
        
        local success = SetCVar(cvar, value)
    end
end

function AutoGraphicsSettings:OnInitialize()
    -- Apply settings 2 seconds after login
    C_Timer.After(2, ApplyGraphicsSettings)
    
    -- Register slash commands
    SLASH_MELLOUIAUTOGRAPHICS1 = "/ags"
    SLASH_MELLOUIAUTOGRAPHICS2 = "/autographics"
    SlashCmdList["MELLOUIAUTOGRAPHICS"] = function(msg)
        if msg == "apply" then
            ApplyGraphicsSettings()
        end
    end
end

function AutoGraphicsSettings:OnEnable()
    -- Module enabled
end

function AutoGraphicsSettings:OnDisable()
    -- Module disabled
end

-- Register the module
ns:RegisterModule("AutoGraphicsSettings", AutoGraphicsSettings)