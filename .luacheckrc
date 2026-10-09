-- luacheck configuration (https://luacheck.readthedocs.io). Run locally with
-- `luacheck Core Modules Media MelloUI_Companion`; the Lint workflow runs the
-- same on every push.
std = "lua51"
max_line_length = false
ignore = {
	"212", -- unused argument (handlers keep the signature of the event)
	"43/self", -- OnEnter/OnLeave closures shadowing a method's self
}

-- Written by the addon: saved variables, slash command registration, the pin mixin the XML expects.
globals = {
	"MelloUIDB", "MelloUIRoutes", "MelloUIVoiceLines", "MelloUIRoadRecords", "MelloUIRouteSaved",
	"SlashCmdList", "SLASH_MELLOUI1", "SLASH_MELLOUI2", "SLASH_MELLOPERF1", "SLASH_MELLOBUG1", "SLASH_MELLOAURA1", "SLASH_MELLOHEAL1", "SLASH_MELLOFX1", "SLASH_MELLOQUESTMAP1", "SLASH_MELLOROUTE1",
	"SLASH_MELLOSERVICES1", "SLASH_MELLOTRDUMP1", "SLASH_MELLOSBDUMP1", "SLASH_MELLOPROFDUMP1", "SLASH_MELLOLEGDUMP1", "SLASH_MELLOGFDUMP1", "SLASH_MELLOVOICEOVER1", "SLASH_MELLOVOICEOVER2", "SLASH_MELLOICONDUMP1",
	"SLASH_MELLOABDUMP1", "SLASH_MELLOINKWHY1", "SLASH_MELLODIALOGDUMP1", "SLASH_MELLOUISCALEDUMP1", "SLASH_MELLOCHATINK1", "SLASH_MELLOCHATSCROLL1", "SLASH_MELLOBAGDUMP1", "SLASH_MELLOMMDUMP1", "SLASH_MELLOUFDUMP1", "SLASH_MELLOUFTEST1", "SLASH_MELLORFDUMP1", "SLASH_MELLOABDUMP1", "SLASH_MELLOCBDUMP1",
	"SLASH_MELLOSOCDUMP1", "SLASH_MELLOTTDUMP1", "SLASH_MELLONPDUMP1", "SLASH_MELLOADDONLISTDUMP1",
	"SLASH_MELLODMDUMP1", "SLASH_MELLOCHDUMP1", "SLASH_MELLOKITDEMO1", "SLASH_MELLOKITWHAT1", "SLASH_MELLOPMDUMP1", "SLASH_MELLOSFX1", "SLASH_MELLOSFXDUMP1", "SLASH_MELLOCPDUMP1", "SLASH_MELLOLOG1", "SLASH_MELLOQLDUMP1", "SLASH_MELLOGDUMP1", "SLASH_MELLOCOLDUMP1", "SLASH_MELLOUFDUMP1", "SLASH_MELLOBTDUMP1",
	"SLASH_MELLOMACRODUMP1", "SLASH_MELLOEDITMODEDUMP1",
	"SLASH_MELLOOPTIONSDUMP1",
	"SLASH_MELLOAUCTIONDUMP1",
	"SLASH_MELLOTRAINERDUMP1",
	"SLASH_MELLOQUESTDIALOGDUMP1",
	"SLASH_MELLOMERCHANTDUMP1",
	"SLASH_MELLOMAILDUMP1",
	"SLASH_MELLOTAXIDUMP1",
	"SLASH_MELLOPVPDUMP1", "SLASH_MELLOBFMAPDUMP1",
	"SLASH_MELLOTABARDDUMP1",
	"SLASH_MELLOTRADEDUMP1", "SLASH_MELLOLOOTDUMP1",
	"SLASH_MELLOITEMTEXTDUMP1", "SLASH_MELLOCHARTERDUMP1",
	"SLASH_MELLOBANKDUMP1",
	"SLASH_MELLOGUILDBANKDUMP1",
	"SLASH_MELLOINSPECTDUMP1", "SLASH_MELLODRESSUPDUMP1",
	"SLASH_MELLOBARBERDUMP1", "SLASH_MELLOSOCKETDUMP1", "SLASH_MELLOSTABLEDUMP1",
	"SLASH_MELLOREADYDUMP1", "SLASH_MELLOSPLITDUMP1", "SLASH_MELLOCOLORPICKERDUMP1",
	"SLASH_MELLOCALENDARDUMP1", "SLASH_MELLOCLOCKDUMP1",
	"SLASH_MELLOCHANNELDUMP1", "SLASH_MELLOHELPDUMP1",
	"ChatFrameUtil", "StaticPopupDialogs",
}

-- WoW API, Blizzard frames and the addon's own data files and named frames.
read_globals = {
	"HelpTip", "StaticPopup_Show", "GetActionTexture", "OpenAllBags", "CloseAllBags", "CVarCallbackRegistry",
	"BagItemAutoSortButton", "BagItemSearchBox", "MainMenuBarBackpackButton", "BagBarExpandToggle", "MainMenuBarBagManager",
	"ADDONS", "EXIT_GAME", "GAMEMENU_ADDONS", "GAMEMENU_EDIT_MODE", "GAMEMENU_HELP", "GAMEMENU_OPTIONS", "GAMEMENU_SUPPORT", "HELP_LABEL", "HUD_EDIT_MODE_MENU", "LOGOUT", "MACROS", "OPTIONS", "QUIT", "RETURN_TO_GAME",
	"EnumerateFrames",
	"LFGListingCategorySelection_UpdateCategoryButtons", "LFGListingFrame",
	"PaperDollFrame_UpdateStats",
	"PaperDollFrame",
	"CharacterAmmoSlot", "CharacterFrame", "CharacterModelScene", "CharacterStatsPane", "CharacterStatsPanePetScrollBox", "CharacterStatsPaneScrollBox", "SetPortraitTexture",
	"bit", "AddonCompartmentFrame", "BagsBar", "BuffBarCooldownViewer", "BuffFrame",
	"ButtonFrameTemplate_HidePortrait", "CHAT_FRAME_TEXTURES", "C_AddOns", "C_AreaPoiInfo", "C_CVar",
	"C_Container", "C_CurrencyInfo", "C_EncounterJournal", "C_GossipInfo", "C_Map", "C_MerchantFrame",
	"C_NamePlate", "C_PlayerInfo", "ITEM_QUALITY_COLORS", "C_QuestLog", "C_Reputation", "C_SkillInfo", "GetFactionInfoByID", "GetNumAvailableQuests", "GetAvailableQuestInfo", "C_SuperTrack", "C_TaxiMap", "C_Texture", "C_Timer", "C_TooltipInfo",
	"C_VoiceChat", "CanGuildBankRepair", "CanMerchantRepair", "CastingBarType",
	"CharacterReagentBag0Slot", "CompactPartyFrame", "CompactRaidFrameContainer", "Constants",
	"ContainerFrame1", "ContainerFrameCombinedBags", "ContainerFrameSettingsManager",
	"CreateDataProvider", "CreateFont", "CreateFontFamily", "CreateColor", "CreateFrame", "CreateFromMixins", "CreateMacro",
	"CreateScrollBoxListLinearView", "CreateVector2D", "DeadlyDebuffFrame", "DebuffFrame",
	"EditMacro", "EditModeManagerFrame", "Enum", "EventRegistry", "ExpansionLandingPageMinimapButton",
	"ExtraActionButton1", "ActionButton_UpdateRangeIndicator", "C_ActionBar",
	-- (0.19.6, Quest Auto: the quest frame's and the greeting's own calls)
	"AcceptQuest", "CompleteQuest", "GetActiveQuestID", "GetActiveTitle", "GetInventoryItemLink", "GetNumActiveQuests",
	"GetNumQuestChoices", "GetQuestItemInfo", "GetQuestItemLink", "GetQuestMoneyToGet", "GetQuestReward",
	"IsQuestCompletable", "SelectActiveQuest", "SelectAvailableQuest",
	-- (0.19.6, Cooldown Tweaks: an action's spell, the out-of-range dot the hot key shows)
	"GetActionInfo", "GetMacroSpell", "RANGE_INDICATOR", "FACTION_BAR_COLORS", "FCF_SetChatWindowFontSize",
	"FocusFrame", "PetFrame", "Game15Font_Shadow", "GameFontHighlightOutline", "GameFontHighlightSmall",
	"GameFontNormal", "ChatFontNormal", "PagedContentFrameBaseMixin", "LegacyChallengeObjectives", "QuestScrollFrame", "GameMenuFrame", "GameTimeFrame", "GameTooltip", "GameTooltipStatusBar",
	"GameTooltip_AddNormalLine", "GameTooltip_SetDefaultAnchor", "GameTooltip_SetTitle",
	"GameTooltip_UnitColor", "GeneralDockManager", "GetAddOnCPUUsage", "GetAddOnMemoryUsage",
	"GetBuildInfo", "GetCVar", "GetPhysicalScreenSize", "GetCoinTextureString", "GetCursorPosition", "IsControlKeyDown", "IsAltKeyDown", "GetCurrentKeyBoardFocus", "IsKeyDown", "Menu", "GetFrameCPUUsage",
	"GetFramerate", "GetFunctionCPUUsage", "GetGossipText", "GetGreetingText",
	"GetGuildBankWithdrawMoney", "GetInstanceInfo", "GetMacroIndexByName", "GetMacroInfo",
	"GetMinimapShape", "GetMouseFoci", "GetMouseFocus", "GetMoney", "GetNetStats", "GetNumMacros", "GetNumRoutes", "GetObjectiveText",
	"GetPlayerFacing", "GetProfessionInfo", "GetProfessions", "GetProgressText",
	"GetQuestDifficultyColor", "GetQuestID", "GetQuestLogQuestText", "GetQuestText",
	"GetRepairAllCost", "GetRewardText", "GetServerTime", "GetSubZoneText", "GetRealZoneText", "GetSuperTrackedQuestID",
	"GetTaxiMapID", "GetTime", "GetTitleText", "HideUIPanel", "ShowUIPanel", "InCombatLockdown", "IsInInstance",
	"IsMouseButtonDown", "IsShiftKeyDown", "KeyRingButton", "LOG_OUT", "LibStub", "MainActionBar",
	-- (0.19.9) Keybind Mode: the game's binding API and its listener's pure helpers
	"C_KeyBindings", "GetBindingKey", "GetBindingText", "GetBindingAction", "GetBindingFromClick", "SetBinding",
	"SaveBindings", "LoadBindings", "GetCurrentBindingSet", "GetConvertedKeyOrButton", "IsKeyPressIgnoredForBinding",
	"CreateKeyChordStringUsingMetaKeyState",
	"MainMenuBar", "MultiBarBottomLeft", "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "MapQuestInfoRewardsFrame",
	"MelloUIHiddenFrame", "MelloUIMinimapStand", "MelloUIServicesBar", "MelloUI_CustomFonts",
	"MelloUI_CustomTextures", "MelloUI_NPCVoiceData", "MelloUI_NPCVoiceOverrides", "MelloUI_Profiles",
	"MelloUI_QuestListData", "MelloUI_PlaceData", "MelloUI_QuestObjectiveData", "MelloUI_QuestNeededItems", "MelloUI_QuestMadeItems", "MelloUI_QuestObjectiveSources", "MelloUI_RouteData", "MelloUI_RoadData", "MelloUI_ClassIcons", "MelloUI_KitLayout", "MelloUI_KitTuning", "MenuUtil", "MerchantFrame", "MicroMenu",
	"MicroMenuContainer", "MinimalSliderWithSteppersMixin", "Minimap", "MinimapCluster",
	"MinimapCompassTexture", "MinimapCompassTextureUnderlay", "MinimapBackdrop", "MinimapZoneText",
	"Mixin", "NUM_BAG_SLOTS",
	"NUM_CHAT_WINDOWS", "UpdateUIPanelPositions", "NamePlateDriverFrame", "NamePlateSetupOptions", "NamePlateConstants", "WorldFrame", "UnitInParty", "UnitInRaid", "UnitIsFriend", "UnitGroupRolesAssigned",
	"C_EditMode", "EditModePresetLayoutManager", "NameUtil", "UnitFrame_Update", "CompactUnitFrame_UpdateName", "NamePlateEnemyFrameOptions", "NamePlateFriendlyFrameOptions", "NamePlatePlayerFrameOptions", "TargetFrameToT", "FocusFrameToT", "MelloUI_EditModeLayout", "MuteSoundFile", "UnmuteSoundFile", "GetCursorInfo", "ClearCursor", "DeleteCursorItem", "GetNumLootItems", "GetLootSlotType", "GetLootSlotInfo", "GetLootSlotLink", "C_Item", "GetItemInfo", "GetLFGMode", "BuyMerchantItem", "BuybackItem", "SellCursorItem", "FCF_MinimizeFrame", "FCF_SetWindowAlpha", "ChatFrame1", "NUM_CONTAINER_FRAMES", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NineSliceUtil",
	"NumberFontNormal", "ObjectiveTrackerFrame", "PanelTemplates_DeselectTab",
	"PanelTemplates_SelectTab", "PanelTemplates_TabResize", "PartyFrame",
	"PersonalResourceDisplayFrame", "PetAttackModeTexture", "PetCastingBarFrame", "OverlayPlayerCastingBarFrame", "TotemFrame", "RaidInfoFrame", "RaidFrame", "FriendsListFrame", "FriendsFrameIcon", "FriendsFrame", "MainActionBar", "MicroMenu", "BagsBar", "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "ActionButton1", "ActionButton2", "CompactRaidGroup_UpdateBorder", "CompactPartyFrameMember1", "CompactRaidGroup1Member1", "CompactRaidFrame1", "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup", "PetFrameFlash",
	"PetFrameHealthBar", "PetFrameManaBar", "PetFrameTexture", "PlaySound", "PlaySoundFile",
	"PlayerCastingBarFrame", "PlayerFrame", "PlayerFrame_UpdatePlayerNameTextAnchor", "PlayerName",
	"PortraitFrameMixin", "UnitFramePortrait_Update",
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
	"FCFDock_GetSelectedWindow", "FCF_OpenTemporaryWindow", "FCFTab_UpdateColors", "UnitEffectiveLevel", "UnitQuestTrivialLevelRange", "GENERAL_CHAT_DOCK", "ChatTypeInfo",
	"Ambiguate", "C_BattleNet", "C_ChatInfo", "SetItemRef", "YOU",
	-- a community channel line's author (the chat's class gems on parchment, 0.14.0)
	"C_Club",
	"C_ClassColor", "C_FriendList", "GetGuildRosterInfo", "GetNumGuildMembers", "GetPlayerInfoByGUID",
	"IsInGuild", "LOCALIZED_CLASS_NAMES_FEMALE", "LOCALIZED_CLASS_NAMES_MALE",
	-- the whisper window's header buttons (0.16.0): the invite, the Battle.net
	-- friend's game, the chat frame's link handler that Report's link runs
	"C_PartyInfo", "BNET_CLIENT_WOW", "WOW_PROJECT_ID", "ChatFrameMixin",
	-- /mello secrets: the secret-value tools it probes for (2026-09-23)
	"C_EventUtils", "C_Secrets", "C_CurveUtil", "C_StringUtil", "CurveConstants", "UnitHealthPercent",
	"UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "AbbreviateNumbers", "UnitIsDeadOrGhost", "UnitIsGhost",
	"UnitIsConnected", "IsInGroup", "UnitHealthMissing", "GetRaidTargetIndex", "GetReadyCheckStatus", "UnitInRange",
	-- Bar Text's secret-value formatting
	"BreakUpLargeNumbers", "UnitPowerPercent",
	-- /melloheal (the heal probe)
	"IsInRaid", "GetNumGroupMembers", "UnitCastingInfo",
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
	"UnitCanAttack", "UnitClass", "UnitClassification", "UnitCreatureType", "UnitExists", "UnitFactionGroup", "UnitIsBossMob", "UnitIsUnit",
	-- (0.16.0: the threat line and the Threat widget, Core/Threat.lua)
	"UnitAffectingCombat",
	-- (0.17.0: the language you speak on the chat's edit box, Modules/Chat.lua)
	"DEFAULT_CHAT_FRAME", "GetNumLanguages",
	-- (0.17.0: Combat Text, Modules/CombatText.lua)
	"C_CombatText", "UnitPowerType", "UnitIsTapDenied", "UnitPlayerControlled",
	"UnitFrameHealthBar_Update", "UnitFrameManaBar_UpdateType", "UnitFrameManaBar_UpdateTypeOld",
	"UnitGUID", "UnitIsPlayer", "UnitLevel", "UnitName", "GetRealmName", "UnitOnTaxi", "UnitPosition", "GetCameraZoom", "GetComboPoints", "GetShapeshiftFormID", "UnitIsDead", "UnitRace", "UnitReaction",
	"UnitSex", "UnitTokenFromGUID", "UpdateAddOnCPUUsage", "UpdateAddOnMemoryUsage", "debugprofilestop", "C_AddOnProfiler", "strtrim",
	"UpdateContainerFrameAnchors", "WorldMapFrame", "date", "hooksecurefunc", "issecretvalue", "time",
	-- (0.19.0: the bag window by kind, Modules/BagWindow.lua)
	"C_NewItems", "ClearItemButtonOverlay", "SetItemButtonQuality", "SetItemButtonCount", "SetItemButtonDesaturated",
	"GetMoneyString", "GetCVarBool", "MoneyFrame_UpdateMoney",
	-- (0.19.0: incoming heals and the debuff glow, Modules/HealerFrames.lua)
	"CreateUnitHealPredictionCalculator", "UnitGetDetailedHealPrediction", "C_UnitAuras", "DebuffTypeColor", "UnitCanAssist", "issecrettable",
	"CompactUnitFrame_SetUnit",
	"tinsert", "wipe",
	-- the game's gamepad navigation, read by Core's MelloUI.Safe.CreateFrame (0.14.0)
	"InputUtil", "SmartNavigation",
}

-- The generated data files only define their table.
files["Media"] = {
	globals = {
		"MelloUI_CustomFonts", "MelloUI_CustomTextures", "MelloUI_NPCVoiceData",
		"MelloUI_NPCVoiceOverrides", "MelloUI_Profiles", "MelloUI_QuestListData", "MelloUI_PlaceData", "MelloUI_RouteData", "MelloUI_ClassIcons", "MelloUI_KitLayout", "MelloUI_KitTuning", "MelloUI_EditModeLayout",
	},
}

-- Voice Over's NPC data (0.19.9: MelloUI_VoiceOver's, data files like Media's)
files["MelloUI_VoiceOver/NPCVoiceData.lua"] = {
	globals = { "MelloUI_NPCVoiceData" },
}
files["MelloUI_VoiceOver/NPCVoiceOverrides.lua"] = {
	globals = { "MelloUI_NPCVoiceOverrides" },
}

-- Route's baked roads (0.19.9: MelloUI_Route's, a generated data file like Media's)
files["MelloUI_Route/RouteData.lua"] = {
	globals = { "MelloUI_RouteData" },
}

-- The route data companion (MelloUI_Companion, loaded on demand): its data
-- files only define their table too; Route reads them (read_globals above).
files["MelloUI_Companion"] = {
	globals = {
		"MelloUI_RoadData", "MelloUI_QuestObjectiveData", "MelloUI_QuestNeededItems", "MelloUI_QuestMadeItems", "MelloUI_QuestUseItems",
		"MelloUI_QuestObjectiveSources",
	},
}
