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
	"SLASH_MELLOSERVICES1", "SLASH_MELLOTRDUMP1", "SLASH_MELLOSBDUMP1", "SLASH_MELLOPROFDUMP1", "SLASH_MELLOLEGDUMP1", "SLASH_MELLOGFDUMP1", "SLASH_MELLOVOICEOVER1", "SLASH_MELLOVOICEOVER2", "SLASH_MELLOICONDUMP1",
	"SLASH_MELLOABDUMP1", "SLASH_MELLOINKWHY1", "SLASH_MELLOBAGDUMP1", "SLASH_MELLOMMDUMP1", "SLASH_MELLOUFDUMP1", "SLASH_MELLOUFTEST1", "SLASH_MELLORFDUMP1", "SLASH_MELLOABDUMP1", "SLASH_MELLOCBDUMP1",
	"SLASH_MELLOSOCDUMP1", "SLASH_MELLOTTDUMP1", "SLASH_MELLONPDUMP1",
	"SLASH_MELLODMDUMP1", "SLASH_MELLOCHDUMP1", "SLASH_MELLOKITDEMO1", "SLASH_MELLOKITWHAT1", "SLASH_MELLOPMDUMP1", "SLASH_MELLOSFX1", "SLASH_MELLOSFXDUMP1", "SLASH_MELLOCPDUMP1", "SLASH_MELLOLOG1", "SLASH_MELLOQLDUMP1", "SLASH_MELLOGDUMP1", "SLASH_MELLOCOLDUMP1", "SLASH_MELLOUFDUMP1", "SLASH_MELLOBTDUMP1",
	"ChatFrameUtil", "StaticPopupDialogs",
}

-- WoW API, Blizzard frames and the addon's own data files and named frames.
read_globals = {
	"HelpTip", "StaticPopup_Show", "GetActionTexture", "OpenAllBags", "CloseAllBags", "CVarCallbackRegistry",
	"BagItemAutoSortButton", "BagItemSearchBox", "MainMenuBarBackpackButton",
	"ADDONS", "EXIT_GAME", "GAMEMENU_ADDONS", "GAMEMENU_EDIT_MODE", "GAMEMENU_HELP", "GAMEMENU_OPTIONS", "GAMEMENU_SUPPORT", "HELP_LABEL", "HUD_EDIT_MODE_MENU", "LOGOUT", "MACROS", "OPTIONS", "QUIT", "RETURN_TO_GAME",
	"EnumerateFrames",
	"LFGListingCategorySelection_UpdateCategoryButtons", "LFGListingFrame",
	"PaperDollFrame_UpdateStats",
	"PaperDollFrame",
	"CharacterAmmoSlot", "CharacterFrame", "CharacterModelScene", "CharacterStatsPane", "CharacterStatsPanePetScrollBox", "CharacterStatsPaneScrollBox", "SetPortraitTexture",
	"bit", "AddonCompartmentFrame", "BagsBar", "BuffBarCooldownViewer", "BuffFrame",
	"ButtonFrameTemplate_HidePortrait", "CHAT_FRAME_TEXTURES", "C_AddOns", "C_AreaPoiInfo", "C_CVar",
	"C_Container", "C_CurrencyInfo", "C_EncounterJournal", "C_GossipInfo", "C_Map", "C_MerchantFrame",
	"C_NamePlate", "C_PlayerInfo", "C_QuestLog", "C_SuperTrack", "C_TaxiMap", "C_Texture", "C_Timer", "C_TooltipInfo",
	"C_VoiceChat", "CanGuildBankRepair", "CanMerchantRepair", "CastingBarType",
	"CharacterReagentBag0Slot", "CompactPartyFrame", "CompactRaidFrameContainer", "Constants",
	"ContainerFrame1", "ContainerFrameCombinedBags", "ContainerFrameSettingsManager",
	"CreateDataProvider", "CreateFont", "CreateColor", "CreateFrame", "CreateFromMixins", "CreateMacro",
	"CreateScrollBoxListLinearView", "CreateVector2D", "DeadlyDebuffFrame", "DebuffFrame",
	"EditMacro", "EditModeManagerFrame", "Enum", "EventRegistry", "ExpansionLandingPageMinimapButton",
	"ExtraActionButton1", "FACTION_BAR_COLORS", "FCF_SetChatWindowFontSize",
	"FocusFrame", "PetFrame", "Game15Font_Shadow", "GameFontHighlightOutline", "GameFontHighlightSmall",
	"GameFontNormal", "ChatFontNormal", "PagedContentFrameBaseMixin", "LegacyChallengeObjectives", "QuestScrollFrame", "GameMenuFrame", "GameTimeFrame", "GameTooltip", "GameTooltipStatusBar",
	"GameTooltip_AddNormalLine", "GameTooltip_SetDefaultAnchor", "GameTooltip_SetTitle",
	"GameTooltip_UnitColor", "GeneralDockManager", "GetAddOnCPUUsage", "GetAddOnMemoryUsage",
	"GetBuildInfo", "GetCVar", "GetCoinTextureString", "GetCursorPosition", "GetFrameCPUUsage",
	"GetFramerate", "GetFunctionCPUUsage", "GetGossipText", "GetGreetingText",
	"GetGuildBankWithdrawMoney", "GetInstanceInfo", "GetMacroIndexByName", "GetMacroInfo",
	"GetMinimapShape", "GetMouseFoci", "GetMouseFocus", "GetMoney", "GetNetStats", "GetNumMacros", "GetNumRoutes", "GetObjectiveText",
	"GetPlayerFacing", "GetProfessionInfo", "GetProfessions", "GetProgressText",
	"GetQuestDifficultyColor", "GetQuestID", "GetQuestLogQuestText", "GetQuestText",
	"GetRepairAllCost", "GetRewardText", "GetServerTime", "GetSubZoneText", "GetSuperTrackedQuestID",
	"GetTaxiMapID", "GetTime", "GetTitleText", "HideUIPanel", "ShowUIPanel", "InCombatLockdown", "IsInInstance",
	"IsMouseButtonDown", "IsShiftKeyDown", "KeyRingButton", "LOG_OUT", "LibStub", "MainActionBar",
	"MainMenuBar", "MultiBarBottomLeft", "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "MapQuestInfoRewardsFrame",
	"MelloUIHiddenFrame", "MelloUIMinimapStand", "MelloUIServicesBar", "MelloUI_CustomFonts",
	"MelloUI_CustomTextures", "MelloUI_NPCVoiceData", "MelloUI_NPCVoiceOverrides", "MelloUI_Profiles",
	"MelloUI_QuestListData", "MelloUI_QuestObjectiveData", "MelloUI_RouteData", "MelloUI_RoadData", "MelloUI_ClassIcons", "MelloUI_KitLayout", "MelloUI_KitTuning", "MenuUtil", "MerchantFrame", "MicroMenu",
	"MicroMenuContainer", "MinimalSliderWithSteppersMixin", "Minimap", "MinimapCluster",
	"MinimapCompassTexture", "MinimapCompassTextureUnderlay", "MinimapBackdrop", "MinimapZoneText",
	"Mixin", "NUM_BAG_SLOTS",
	"NUM_CHAT_WINDOWS", "UpdateUIPanelPositions", "NamePlateDriverFrame", "NamePlateSetupOptions", "NamePlateConstants", "WorldFrame", "UnitInParty", "UnitInRaid", "UnitIsFriend", "UnitGroupRolesAssigned",
	"C_EditMode", "EditModePresetLayoutManager", "NameUtil", "UnitFrame_Update", "CompactUnitFrame_UpdateName", "NamePlateEnemyFrameOptions", "NamePlateFriendlyFrameOptions", "NamePlatePlayerFrameOptions", "TargetFrameToT", "FocusFrameToT", "MelloUI_EditModeLayout", "MuteSoundFile", "UnmuteSoundFile", "GetCursorInfo", "C_Item", "GetItemInfo", "GetLFGMode", "BuyMerchantItem", "BuybackItem", "SellCursorItem", "FCF_MinimizeFrame", "FCF_SetWindowAlpha", "ChatFrame1", "NUM_CONTAINER_FRAMES", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NineSliceUtil",
	"NumberFontNormal", "ObjectiveTrackerFrame", "PanelTemplates_DeselectTab",
	"PanelTemplates_SelectTab", "PanelTemplates_TabResize", "PartyFrame",
	"PersonalResourceDisplayFrame", "PetAttackModeTexture", "PetCastingBarFrame", "OverlayPlayerCastingBarFrame", "TotemFrame", "RaidInfoFrame", "RaidFrame", "FriendsListFrame", "FriendsFrameIcon", "FriendsFrame", "MainActionBar", "MicroMenu", "BagsBar", "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "ActionButton1", "ActionButton2", "CompactRaidGroup_UpdateBorder", "CompactPartyFrameMember1", "CompactRaidGroup1Member1", "CompactRaidFrame1", "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup", "PetFrameFlash",
	"PetFrameHealthBar", "PetFrameManaBar", "PetFrameTexture", "PlaySound", "PlaySoundFile",
	"PlayerCastingBarFrame", "PlayerFrame", "PlayerFrame_UpdatePlayerNameTextAnchor", "PlayerName",
	"PlayerFrame_ShowPvPIcon", "PlayerFrame_GetPlayerFrameContentContextual", "PortraitFrameMixin", "UnitFramePortrait_Update",
	"PlayerSpellsFrame", "LegacySystemFrame", "ProfessionsFrame", "PowerBarColor", "QuestInfoFrame", "QuestInfoObjectivesFrame",
	"QuestInfoRequiredMoneyFrame", "QuestInfoRewardsFrame", "QuestInfoSpecialObjectivesFrame",
	"QuestInfoTimerFrame", "QuestMapFrame", "QuestLogQuests_Update", "QuestMapFrame_ShowQuestDetails", "CommunitiesFrame", "WaypointLocationPinMixin", "LFGParentFrame", "LFGListingCategorySelection_UpdateCategoryButtons", "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame", "CollectionsJournal", "MountJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame", "CollectionsJournal_UpdateSelectedTab", "RAID_CLASS_COLORS", "RepairAllItems", "ResetCPUUsage",
	"SOUNDKIT", "ScrollBoxConstants", "ScrollUtil", "SetCVar", "SharedTooltip_SetBackdropStyle",
	"StatusTrackingBarManager", "StopSound",
	"DamageMeter", "MinimapCluster", "MelloUIServicesMenu",
	"ObjectiveTrackerFrame", "GetCVar", "SystemFont_Shadow_Small",
	"TOOLTIP_DEFAULT_BACKGROUND_COLOR", "TargetFrame", "TaxiGetDestX", "TaxiGetDestY",
	"TextStatusBarText", "TooltipDataProcessor", "UIParent", "UISpecialFrames", "UiMapPoint",
	-- chat: every window incl. whisper windows, tab alphas (read only), the whisper popup (2026-09-23)
	"CHAT_FRAMES", "CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA", "CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA",
	"FCFDock_GetSelectedWindow", "FCF_OpenTemporaryWindow", "GENERAL_CHAT_DOCK", "ChatTypeInfo",
	"Ambiguate", "C_BattleNet", "C_ChatInfo", "SetItemRef", "YOU",
	"C_ClassColor", "C_FriendList", "GetGuildRosterInfo", "GetNumGuildMembers", "GetPlayerInfoByGUID",
	"IsInGuild", "LOCALIZED_CLASS_NAMES_FEMALE", "LOCALIZED_CLASS_NAMES_MALE",
	-- /mello secrets: the secret-value tools it probes for (2026-09-23)
	"C_EventUtils", "C_Secrets", "C_CurveUtil", "C_StringUtil", "CurveConstants", "UnitHealthPercent",
	"UnitHealth", "UnitHealthMax", "UnitPower", "AbbreviateNumbers",
	-- Bar Text's secret-value formatting
	"BreakUpLargeNumbers", "UnitPowerPercent",
	-- Route's world marker
	"C_Navigation", "SuperTrackedFrame",
	-- Core/Anim.lua
	"geterrorhandler",
	-- Windows Fade In reads which frames are panel windows
	"UIPanelWindows",
	-- profile share strings
	"C_EncodingUtil",
	-- the Quest Tracker
	"RegisterStateDriver", "UnregisterStateDriver", "QuestMapFrame_OpenToQuestDetails", "securecallfunction",
	"GetQuestLogSpecialItemInfo", "GetQuestLogSpecialItemCooldown", "GetQuestLogCompletionText", "QUESTS_LABEL",
	"C_TradeSkillUI", "GetItemCount", "TRADE_SKILLS", "TRACKER_ALL_OBJECTIVES",
	"POIButtonUtil", "UIErrorsFrame",
	"AnchorUtil", "AuraContainerSortMethod", "AuraContainerSortDirection", "AuraContainerItemEnchantmentSlot",
	"QuestInfo_Display", "QuestInfoTitleHeader", "QuestInfoFrame", "GetQuestID",
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
		"MelloUI_NPCVoiceOverrides", "MelloUI_Profiles", "MelloUI_QuestListData", "MelloUI_QuestObjectiveData", "MelloUI_RouteData", "MelloUI_RoadData", "MelloUI_ClassIcons", "MelloUI_KitLayout", "MelloUI_KitTuning", "MelloUI_EditModeLayout",
	},
}
