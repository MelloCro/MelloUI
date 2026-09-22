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
	"SLASH_MELLOSERVICES1", "SLASH_MELLOMINIDUMP1", "SLASH_MELLOTRDUMP1", "SLASH_MELLOBPDUMP1", "SLASH_MELLOSBDUMP1", "SLASH_MELLOPROFDUMP1", "SLASH_MELLOLEGDUMP1", "SLASH_MELLOTALDUMP1", "SLASH_MELLOMAPDUMP1", "SLASH_MELLOGFDUMP1", "SLASH_MELLOVOICEOVER1", "SLASH_MELLOVOICEOVER2", "SLASH_MELLOICONDUMP1",
	"SLASH_MELLOABDUMP1", "SLASH_MELLOBAGDUMP1", "SLASH_MELLOMMDUMP1", "SLASH_MELLOUFDUMP1", "SLASH_MELLOUFTEST1", "SLASH_MELLORFDUMP1", "SLASH_MELLOABDUMP1", "SLASH_MELLOCBDUMP1", "SLASH_MELLOHUDDUMP1", "SLASH_MELLOAPDUMP1",
	"SLASH_MELLOSOCDUMP1", "SLASH_MELLOTTDUMP1", "SLASH_MELLONPDUMP1", "SLASH_MELLOHUDSHOW1", "SLASH_MELLOHUDCHECK1",
	"SLASH_MELLOTBDUMP1", "SLASH_MELLODMDUMP1", "SLASH_MELLOCHDUMP1", "SLASH_MELLOKITDEMO1", "SLASH_MELLOKITWHAT1", "SLASH_MELLOPMDUMP1", "SLASH_MELLOSFX1", "SLASH_MELLOSFXDUMP1", "SLASH_MELLOCPDUMP1", "SLASH_MELLOLOG1", "SLASH_MELLOQLDUMP1", "SLASH_MELLOGDUMP1", "SLASH_MELLOCOLDUMP1", "SLASH_MELLOUFDUMP1",
	"ChatFrameUtil", "StaticPopupDialogs",
}

-- WoW API, Blizzard frames and the addon's own data files and named frames.
read_globals = {
	"HelpTip", "StaticPopup_Show",
	"BagItemAutoSortButton", "BagItemSearchBox", "MainMenuBarBackpackButton",
	"ADDONS", "EXIT_GAME", "GAMEMENU_ADDONS", "GAMEMENU_EDIT_MODE", "GAMEMENU_HELP", "GAMEMENU_OPTIONS", "GAMEMENU_SUPPORT", "HELP_LABEL", "HUD_EDIT_MODE_MENU", "LOGOUT", "MACROS", "OPTIONS", "QUIT", "RETURN_TO_GAME",
	"EnumerateFrames",
	"LFGListingCategorySelection_UpdateCategoryButtons", "LFGListingFrame",
	"MelloUI_StoneParts",
	"MAINMENU_BUTTON",
	"PaperDollFrame_UpdateSidebarTabLayout",
	"PaperDollFrame_UpdateStats",
	"PaperDollFrame_SetSidebar",
	"PaperDollFrame",
	"PaperDollSidebarTab3",
	"PaperDollSidebarTab2",
	"PaperDollSidebarTab1",
	"STAT_CATEGORY_PRIMARY_ATTRIBUTES",
	"PAPERDOLL_STATCATEGORIES",
	"BreakUpLargeNumbers", "CHARACTER", "CLASS_ICON_TCOORDS", "CLOSE", "CharacterAmmoSlot", "CharacterFrame", "CharacterModelScene", "CharacterStatFrameMixin", "CharacterStatsPane", "CharacterStatsPanePetScrollBox", "CharacterStatsPaneScrollBox", "HEALTH", "MANA", "PAPERDOLL_STATINFO", "POWER", "PaperDollLevelInfo", "PaperDollSidebarTabs", "SetPortraitTexture", "SetUIPanelAttribute", "UnitHealthMax", "UnitPVPName", "UnitPowerMax", "UnitPowerType", "characterFrameDisplayInfo",
	"bit", "AddonCompartmentFrame", "BagsBar", "BuffBarCooldownViewer", "BuffFrame",
	"ButtonFrameTemplate_HidePortrait", "CHAT_FRAME_TEXTURES", "C_AddOns", "C_AreaPoiInfo", "C_CVar",
	"C_Container", "C_CurrencyInfo", "C_EncounterJournal", "C_GossipInfo", "C_Map", "C_MerchantFrame",
	"C_NamePlate", "C_QuestLog", "C_SuperTrack", "C_TaxiMap", "C_Texture", "C_Timer", "C_TooltipInfo",
	"C_VoiceChat", "CanGuildBankRepair", "CanMerchantRepair", "CastingBarType",
	"CharacterReagentBag0Slot", "CompactPartyFrame", "CompactRaidFrameContainer", "Constants",
	"ContainerFrame1", "ContainerFrameCombinedBags", "ContainerFrameSettingsManager",
	"CreateDataProvider", "CreateFont", "CreateColor", "CreateFrame", "CreateFromMixins", "CreateMacro",
	"CreateScrollBoxListLinearView", "CreateVector2D", "DeadlyDebuffFrame", "DebuffFrame",
	"EditMacro", "EditModeManagerFrame", "Enum", "EventRegistry", "ExpansionLandingPageMinimapButton",
	"ExtraActionButton1", "FACTION_BAR_COLORS", "FCFTab_UpdateAlpha", "FCF_GetCurrentChatFrame", "FCF_SetChatWindowFontSize",
	"FocusFrame", "PetFrame", "Game15Font_Shadow", "GameFontHighlightOutline", "GameFontHighlightSmall",
	"GameFontNormal", "ChatFontNormal", "PagedContentFrameBaseMixin", "LegacyChallengeObjectives", "QuestScrollFrame", "GameMenuFrame", "GameTimeFrame", "GameTooltip", "GameTooltipStatusBar",
	"GameTooltip_AddNormalLine", "GameTooltip_SetDefaultAnchor", "GameTooltip_SetTitle",
	"GameTooltip_UnitColor", "GeneralDockManager", "GetAddOnCPUUsage", "GetAddOnMemoryUsage",
	"GetBuildInfo", "GetCVar", "GetCoinTextureString", "GetCursorPosition", "GetFrameCPUUsage", "GetPhysicalScreenSize",
	"GetFramerate", "GetFunctionCPUUsage", "GetGossipText", "GetGreetingText",
	"GetGuildBankWithdrawMoney", "GetInstanceInfo", "GetMacroIndexByName", "GetMacroInfo",
	"GetMinimapShape", "GetMouseFoci", "GetMouseFocus", "GetMoney", "GetNetStats", "GetNumMacros", "GetNumRoutes", "GetObjectiveText",
	"GetPlayerFacing", "GetProfessionInfo", "GetProfessions", "GetProgressText",
	"GetQuestDifficultyColor", "GetQuestID", "GetQuestLogQuestText", "GetQuestText",
	"GetRepairAllCost", "GetRewardText", "GetServerTime", "GetSubZoneText", "GetSuperTrackedQuestID",
	"GetTaxiMapID", "GetTime", "GetTitleText", "HideUIPanel", "ShowUIPanel", "InCombatLockdown", "IsInInstance",
	"IsMouseButtonDown", "IsShiftKeyDown", "KeyRingButton", "LOG_OUT", "LibStub", "MainActionBar",
	"MainMenuBar", "MultiBarBottomLeft", "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "MapQuestInfoRewardsFrame",
	"MelloUIBackpackSkin", "MelloUIHiddenFrame", "MelloUIMinimapStand", "MelloUIServicesBar", "MelloUI_CustomFonts",
	"MelloUI_CustomTextures", "MelloUI_NPCVoiceData", "MelloUI_NPCVoiceOverrides", "MelloUI_Profiles",
	"MelloUI_QuestListData", "MelloUI_RouteData", "MelloUI_RoadData", "MelloUI_ClassIcons", "MelloUI_HudLayout", "MelloUI_ChatLayout", "MelloUI_BackpackLayout", "MelloUI_KitLayout", "MenuUtil", "MerchantFrame", "MicroMenu",
	"InputUtil", "IsAccountSecured", "GetScreenWidth", "GetScreenHeight",
	"MicroMenuContainer", "MinimalSliderWithSteppersMixin", "Minimap", "MinimapCluster",
	"MinimapCompassTexture", "MinimapCompassTextureUnderlay", "MinimapBackdrop", "MinimapZoneText",
	"TimeManagerClockButton", "TimeManagerClockTicker", "POIButtonUtil",
	"Mixin", "NUM_BAG_SLOTS",
	"NUM_CHAT_WINDOWS", "UpdateUIPanelPositions", "NamePlateDriverFrame", "NamePlateSetupOptions", "NamePlateConstants", "WorldFrame", "UnitInParty", "UnitInRaid", "UnitIsFriend", "UnitGroupRolesAssigned",
	"C_EditMode", "EditModePresetLayoutManager", "NameUtil", "UnitFrame_Update", "CompactUnitFrame_UpdateName", "NamePlateEnemyFrameOptions", "NamePlateFriendlyFrameOptions", "NamePlatePlayerFrameOptions", "TargetFrameToT", "FocusFrameToT", "MelloUI_EditModeLayout", "MuteSoundFile", "UnmuteSoundFile", "GetCursorInfo", "C_Item", "GetItemInfo", "GetLFGMode", "BuyMerchantItem", "BuybackItem", "SellCursorItem", "FCF_MinimizeFrame", "FCF_SetWindowAlpha", "ChatFrame1", "NUM_CONTAINER_FRAMES", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NineSliceUtil",
	"NumberFontNormal", "ObjectiveTrackerFrame", "PanelTemplates_DeselectTab",
	"PanelTemplates_SelectTab", "PanelTemplates_TabResize", "PartyFrame",
	"PersonalResourceDisplayFrame", "PetAttackModeTexture", "PetCastingBarFrame", "OverlayPlayerCastingBarFrame", "TotemFrame", "RaidInfoFrame", "RaidFrame", "FriendsListFrame", "FriendsFrameIcon", "FriendsFrame", "MainActionBar", "MicroMenu", "BagsBar", "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "ActionButton1", "ActionButton2", "CompactRaidGroup_UpdateBorder", "CompactPartyFrameMember1", "CompactRaidGroup1Member1", "CompactRaidFrame1", "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup", "PetFrameFlash",
	"PetFrameHealthBar", "PetFrameManaBar", "PetFrameTexture", "PlaySound", "PlaySoundFile",
	"PlayerCastingBarFrame", "PlayerFrame", "PlayerFrame_UpdatePlayerNameTextAnchor", "PlayerName", "PlayerLevelText",
	"PlayerFrame_ShowPvPIcon", "PlayerFrame_GetPlayerFrameContentContextual", "PortraitFrameMixin", "UnitFramePortrait_Update",
	"PlayerSpellsFrame", "LegacySystemFrame", "ProfessionsFrame", "PowerBarColor", "QuestInfoFrame", "QuestInfoObjectivesFrame",
	"QuestInfoRequiredMoneyFrame", "QuestInfoRewardsFrame", "QuestInfoSpecialObjectivesFrame",
	"QuestInfoTimerFrame", "QuestMapFrame", "QuestLogQuests_Update", "QuestMapFrame_ShowQuestDetails", "CommunitiesFrame", "WaypointLocationPinMixin", "LFGParentFrame", "LFGListingCategorySelection_UpdateCategoryButtons", "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame", "CollectionsJournal", "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame", "CollectionsJournal_UpdateSelectedTab", "QuestLogCount", "NavBar_AddButton", "RAID_CLASS_COLORS", "RepairAllItems", "ResetCPUUsage",
	"SOUNDKIT", "ScrollBoxConstants", "ScrollUtil", "SetCVar", "SharedTooltip_SetBackdropStyle",
	"StatusTrackingBarManager", "STATUS_BAR_NUM_SEGMENTS", "StopSound",
	"C_DamageMeter", "DamageMeter", "DamageMeterEntryMixin", "MinimapCluster", "MelloUIServicesMenu", "GetPhysicalScreenSize",
	"ObjectiveTrackerFrame", "GetCVar", "MelloUITrackerPanel", "DAMAGE_METER_DEFAULT_BAR_HEIGHT", "DAMAGE_METER_DEFAULT_BAR_SPACING", "SystemFont_Shadow_Small",
	"TOOLTIP_DEFAULT_BACKGROUND_COLOR", "TargetFrame", "TaxiGetDestX", "TaxiGetDestY",
	"TextStatusBarText", "ToggleAllBags", "ToggleBackpack", "TooltipDataProcessor", "UIParent", "UISpecialFrames", "UiMapPoint",
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
		"MelloUI_NPCVoiceOverrides", "MelloUI_Profiles", "MelloUI_QuestListData", "MelloUI_RouteData", "MelloUI_RoadData", "MelloUI_StoneParts", "MelloUI_ClassIcons", "MelloUI_HudLayout", "MelloUI_ChatLayout", "MelloUI_BackpackLayout", "MelloUI_KitLayout", "MelloUI_EditModeLayout",
	},
}
