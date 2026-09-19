-- luacheck configuration (https://luacheck.readthedocs.io). Run locally with
-- `luacheck Core Modules Media`; the Lint workflow runs the same on every push.
std = "lua51"
max_line_length = false
ignore = {
	"212", -- unused argument (handlers keep the signature of the event)
	"43/self", -- OnEnter/OnLeave closures shadowing a method's self
}

-- Written by the addon: saved variables, slash command registration, the pin mixin the XML expects.
globals = {
	"MelloUIDB", "MelloUIRoutes", "MelloUIVoiceLines", "MelloUI_QuestPinMixin",
	"SlashCmdList", "SLASH_MELLOUI1", "SLASH_MELLOUI2", "SLASH_MELLOQUESTMAP1", "SLASH_MELLOROUTE1",
	"SLASH_MELLOSERVICES1", "SLASH_MELLOVOICEOVER1", "SLASH_MELLOVOICEOVER2",
	"ChatFrameUtil",
}

-- WoW API, Blizzard frames and the addon's own data files and named frames.
read_globals = {
	"bit", "AddonCompartmentFrame", "BagsBar", "BuffBarCooldownViewer", "BuffFrame",
	"ButtonFrameTemplate_HidePortrait", "CHAT_FRAME_TEXTURES", "C_AddOns", "C_AreaPoiInfo", "C_CVar",
	"C_Container", "C_CurrencyInfo", "C_EncounterJournal", "C_GossipInfo", "C_Map", "C_MerchantFrame",
	"C_NamePlate", "C_QuestLog", "C_SuperTrack", "C_TaxiMap", "C_Texture", "C_Timer", "C_TooltipInfo",
	"C_VoiceChat", "CanGuildBankRepair", "CanMerchantRepair", "CastingBarType",
	"CharacterReagentBag0Slot", "CompactPartyFrame", "CompactRaidFrameContainer", "Constants",
	"ContainerFrame1", "ContainerFrameCombinedBags", "ContainerFrameSettingsManager",
	"CreateDataProvider", "CreateFont", "CreateFrame", "CreateFromMixins", "CreateMacro",
	"CreateScrollBoxListLinearView", "CreateVector2D", "DeadlyDebuffFrame", "DebuffFrame",
	"EditMacro", "EditModeManagerFrame", "Enum", "EventRegistry", "ExpansionLandingPageMinimapButton",
	"ExtraActionButton1", "FACTION_BAR_COLORS", "FCFTab_UpdateAlpha", "FCF_SetChatWindowFontSize",
	"FocusFrame", "Game15Font_Shadow", "GameFontHighlightOutline", "GameFontHighlightSmall",
	"GameFontNormal", "GameMenuFrame", "GameTimeFrame", "GameTooltip", "GameTooltipStatusBar",
	"GameTooltip_AddNormalLine", "GameTooltip_SetDefaultAnchor", "GameTooltip_SetTitle",
	"GameTooltip_UnitColor", "GeneralDockManager", "GetAddOnCPUUsage", "GetAddOnMemoryUsage",
	"GetBuildInfo", "GetCVar", "GetCoinTextureString", "GetCursorPosition", "GetFrameCPUUsage",
	"GetFramerate", "GetFunctionCPUUsage", "GetGossipText", "GetGreetingText",
	"GetGuildBankWithdrawMoney", "GetInstanceInfo", "GetMacroIndexByName", "GetMacroInfo",
	"GetMinimapShape", "GetMoney", "GetNetStats", "GetNumMacros", "GetNumRoutes", "GetObjectiveText",
	"GetPlayerFacing", "GetProfessionInfo", "GetProfessions", "GetProgressText",
	"GetQuestDifficultyColor", "GetQuestID", "GetQuestLogQuestText", "GetQuestText",
	"GetRepairAllCost", "GetRewardText", "GetServerTime", "GetSubZoneText", "GetSuperTrackedQuestID",
	"GetTaxiMapID", "GetTime", "GetTitleText", "HideUIPanel", "InCombatLockdown", "IsInInstance",
	"IsMouseButtonDown", "IsShiftKeyDown", "KeyRingButton", "LOG_OUT", "LibStub", "MainActionBar",
	"MainMenuBar", "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "MapQuestInfoRewardsFrame",
	"MelloUIHiddenFrame", "MelloUIMinimapStand", "MelloUIServicesBar", "MelloUI_CustomFonts",
	"MelloUI_CustomTextures", "MelloUI_NPCVoiceData", "MelloUI_NPCVoiceOverrides", "MelloUI_Profiles",
	"MelloUI_QuestListData", "MelloUI_RouteData", "MenuUtil", "MerchantFrame", "MicroMenu",
	"MicroMenuContainer", "MinimalSliderWithSteppersMixin", "Minimap", "MinimapCluster",
	"MinimapCompassTexture", "MinimapCompassTextureUnderlay", "Mixin", "NUM_BAG_SLOTS",
	"NUM_CHAT_WINDOWS", "NUM_CONTAINER_FRAMES", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NineSliceUtil",
	"NumberFontNormal", "ObjectiveTrackerFrame", "PanelTemplates_DeselectTab",
	"PanelTemplates_SelectTab", "PanelTemplates_TabResize", "PartyFrame",
	"PersonalResourceDisplayFrame", "PetAttackModeTexture", "PetCastingBarFrame", "PetFrameFlash",
	"PetFrameHealthBar", "PetFrameManaBar", "PetFrameTexture", "PlaySound", "PlaySoundFile",
	"PlayerCastingBarFrame", "PlayerFrame", "PlayerFrame_UpdatePlayerNameTextAnchor", "PlayerName",
	"PlayerSpellsFrame", "PowerBarColor", "QuestInfoFrame", "QuestInfoObjectivesFrame",
	"QuestInfoRequiredMoneyFrame", "QuestInfoRewardsFrame", "QuestInfoSpecialObjectivesFrame",
	"QuestInfoTimerFrame", "QuestMapFrame", "RAID_CLASS_COLORS", "RepairAllItems", "ResetCPUUsage",
	"SOUNDKIT", "ScrollBoxConstants", "ScrollUtil", "SetCVar", "SharedTooltip_SetBackdropStyle",
	"StatusTrackingBarManager", "StopSound", "SystemFont_Shadow_Small",
	"TOOLTIP_DEFAULT_BACKGROUND_COLOR", "TargetFrame", "TaxiGetDestX", "TaxiGetDestY",
	"TextStatusBarText", "TooltipDataProcessor", "UIParent", "UISpecialFrames", "UiMapPoint",
	"UnitCanAttack", "UnitClass", "UnitCreatureType", "UnitExists", "UnitFactionGroup",
	"UnitFrameHealthBar_Update", "UnitFrameManaBar_UpdateType", "UnitFrameManaBar_UpdateTypeOld",
	"UnitGUID", "UnitIsPlayer", "UnitLevel", "UnitName", "UnitOnTaxi", "UnitRace", "UnitReaction",
	"UnitSex", "UnitTokenFromGUID", "UpdateAddOnCPUUsage", "UpdateAddOnMemoryUsage",
	"UpdateContainerFrameAnchors", "WorldMapFrame", "date", "hooksecurefunc", "issecretvalue", "time",
	"tinsert", "wipe",
}

-- The generated data files only define their table.
files["Media"] = {
	globals = {
		"MelloUI_CustomFonts", "MelloUI_CustomTextures", "MelloUI_NPCVoiceData",
		"MelloUI_NPCVoiceOverrides", "MelloUI_Profiles", "MelloUI_QuestListData", "MelloUI_RouteData",
	},
}
