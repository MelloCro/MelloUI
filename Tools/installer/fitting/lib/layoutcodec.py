#!/usr/bin/env python3
"""Edit Mode layout share-string codec for the Camelot/"Forever" client
(wow_classic_beta 1.60.1.69977, the build whose UI source was read from the
local install).

    decode(string) -> dict   (JSON-ready: named systems, settings with meaning)
    encode(dict)   -> string (byte-identical to the game's own export for any
                              string decode() accepted)

Grammar of the share string (Edit Mode > Share > Export / C_EditMode.
ConvertLayoutInfoToString), tokens separated by ONE space, no trailing space:

    layout  := VERSION SP COUNT (SP system){COUNT}
    VERSION := "3"                      (format version)
    COUNT   := decimal, number of system records
    system  := SYS SP IDX SP DEF SP P SP RP SP REL SP X SP Y SP A2 SP SETTINGS
      SYS      Enum.EditModeSystem value (decimal)
      IDX      systemIndex - 1  (systemIndex is a luaIndex: 1-based; a system
               without indices, systemIndex = nil, is written -1)
      DEF      isInDefaultPosition, 0/1
      P, RP    anchorInfo.point, anchorInfo.relativePoint as FramePoint numbers:
               0 TOPLEFT 1 TOP 2 TOPRIGHT 3 LEFT 4 CENTER 5 RIGHT
               6 BOTTOMLEFT 7 BOTTOM 8 BOTTOMRIGHT
      REL      anchorInfo.relativeTo, a global frame name (no spaces)
      X, Y     anchorInfo.offsetX/Y, printf "%.1f" (so "-0.0" can occur).
               Stored "as if at scale 1.0": UIParent-space units; the game
               applies offset/frameScale (EditModeSystemMixin:ApplySystemAnchor)
      A2       anchorInfo2 marker: "-1" = no second anchor (every sample).
               A present anchorInfo2 was never observed; this codec parses it
               as "P RP REL X Y" by analogy and flags it (unverified).
      SETTINGS one token of printable chars, 2 chars per stored digit:
               chr(35 + settingId) chr(35 + digit). A value is written in base
               90, least significant digit first, one (id, digit) pair per
               digit: v < 90 -> 1 pair; 90 <= v < 8100 -> 2 pairs with the same
               id; ... Settings appear in ascending id order. A system with no
               settings writes the single char "#" (EncounterBar, ExtraAbilities,
               TalkingHeadFrame, VehicleLeaveButton, LootFrame, HudTooltip,
               RaidWarning, TotemActionBar in every sample).
    The account cache file (WTF/Account/<acct>/edit-mode-cache-account.txt)
    uses the same system records:  "3 <nAcct> <acct values...> {<nameLen>
    <name> <COUNT> <systems>}* \\0"  (decode_account_cache / encode_account_cache).
"""
import json
import sys

_SCHEMA = json.loads(r'''{"displayInfo":{"ActionBar":[{"label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_ORIENTATION","options":[[0,"HORIZONTAL"],[1,"VERTICAL"]],"setting":0,"type":"Dropdown"},{"altLabel":"HUD_EDIT_MODE_SETTING_ACTION_BAR_NUM_COLUMNS","convert":"raw","label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_NUM_ROWS","maxValue":4,"minValue":1,"percent":false,"setting":1,"type":"Slider"},{"convert":"raw","label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_NUM_ICONS","maxValue":12,"minValue":6,"percent":false,"setting":2,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_ICON_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":3,"stepSize":10,"type":"Slider"},{"convert":"raw","label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_ICON_PADDING","maxValue":10,"minValue":2,"percent":false,"setting":4,"stepSize":1,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING","options":[[0,"ALWAYS"],[1,"IN_COMBAT"],[2,"OUT_OF_COMBAT"],[3,"HIDDEN"]],"setting":5,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_ALWAYS_SHOW_BUTTONS","setting":9,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_HIDE_BAR_ART","setting":6,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_ACTION_BAR_HIDE_BAR_SCROLLING","setting":8,"type":"Checkbox"}],"ArchaeologyBar":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_ARCHAEOLOGY_BAR_SIZE","maxValue":200,"minValue":100,"percent":true,"setting":0,"stepSize":5,"type":"Slider"}],"AuraFrame":[{"label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_ORIENTATION","options":[[0,"HORIZONTAL"],[1,"VERTICAL"]],"setting":0,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_WRAP","options":[[0,"DOWN"],[1,"UP"]],"setting":1,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION","options":[[0,"LEFT"],[1,"RIGHT"]],"setting":2,"type":"Dropdown"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":5,"stepSize":10,"type":"Slider"},{"convert":"raw","label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_PADDING","maxValue":15,"minValue":5,"percent":false,"setting":6,"stepSize":1,"type":"Slider"},{"convert":"raw","label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_LIMIT","maxValue":32,"minValue":2,"percent":false,"setting":3,"stepSize":1,"type":"Slider"},{"convert":"raw","label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_LIMIT","maxValue":16,"minValue":1,"percent":false,"setting":4,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_OPACITY","maxValue":100,"minValue":50,"percent":true,"setting":9,"stepSize":1,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_VISIBLE_SETTING","options":[[0,"ALWAYS"],[1,"IN_COMBAT"],[2,"HIDDEN"]],"setting":8,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_AURA_FRAME_SHOW_DISPEL_TYPE","setting":10,"type":"Checkbox"}],"Bags":[{"label":"HUD_EDIT_MODE_SETTING_BAGS_ORIENTATION","options":[[0,"HORIZONTAL"],[1,"VERTICAL"]],"setting":0,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_BAGS_DIRECTION","options":[[0,"LEFT"],[1,"RIGHT"]],"setting":1,"type":"Dropdown"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_BAGS_SIZE","maxValue":200,"minValue":75,"percent":true,"setting":2,"stepSize":5,"type":"Slider"},{"convert":"raw","label":"HUD_EDIT_MODE_SETTING_BAGS_BAG_SLOT_PADDING","maxValue":10,"minValue":2,"percent":false,"setting":3,"stepSize":1,"type":"Slider"}],"CastBar":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_CAST_BAR_SIZE","maxValue":150,"minValue":100,"percent":true,"setting":0,"stepSize":10,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_CAST_BAR_LOCK_TO_PLAYER_FRAME","setting":1,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_CAST_BAR_SHOW_CAST_TIME","setting":2,"type":"Checkbox"}],"ChatFrame":[{"compositeHundreds":0,"compositeTensAndOnes":1,"convert":"composite","label":"HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH","maxValue":800,"minValue":250,"percent":false,"setting":4,"stepSize":1,"type":"Slider"},{"compositeHundreds":2,"compositeTensAndOnes":3,"convert":"composite","label":"HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT","maxValue":800,"minValue":120,"percent":false,"setting":5,"stepSize":1,"type":"Slider"}],"CooldownViewer":[{"label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_ORIENTATION","options":[[0,"HORIZONTAL"],[1,"VERTICAL"]],"setting":0,"type":"Dropdown"},{"altLabel":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_ICON_LIMIT_ALT","convert":"raw","label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_ICON_LIMIT","maxValue":20,"minValue":1,"percent":false,"setting":1,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_ICON_DIRECTION","options":[[0,"LEFT"],[1,"RIGHT"]],"setting":2,"type":"Dropdown"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_ICON_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":3,"stepSize":10,"type":"Slider"},{"convert":"raw","label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_ICON_PADDING","maxValue":14,"minValue":0,"percent":false,"setting":4,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_BUFFBAR_WIDTH_SCALE","maxValue":200,"minValue":50,"percent":true,"setting":11,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_OPACITY","maxValue":100,"minValue":50,"percent":true,"setting":5,"stepSize":1,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_VISIBLE_SETTING","options":[[0,"ALWAYS"],[1,"IN_COMBAT"],[2,"HIDDEN"]],"setting":6,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_BAR_CONTENT","options":[[0,"TYPE_ICON_AND_NAME"],[1,"TYPE_ICON_ONLY"],[2,"TYPE_NAME_ONLY"]],"setting":7,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_HIDE_WHEN_INACTIVE","setting":8,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_SHOW_TIMER","setting":9,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_SHOW_TOOLTIPS","setting":10,"type":"Checkbox"}],"DamageMeter":[{"label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_STYLE","options":[[0,"DEFAULT"],[2,"BORDERED"],[1,"THIN"]],"setting":1,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_NUMBERS","options":[[0,"MINIMAL"],[1,"COMPACT"],[2,"COMPLETE"]],"setting":2,"type":"Dropdown"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_FRAME_WIDTH","maxValue":600,"minValue":200,"percent":false,"setting":3,"stepSize":1,"type":"Slider"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_FRAME_HEIGHT","maxValue":400,"minValue":120,"percent":false,"setting":4,"stepSize":1,"type":"Slider"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_BAR_HEIGHT","maxValue":40,"minValue":15,"percent":false,"setting":10,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_PADDING","maxValue":10,"minValue":2,"percent":false,"setting":5,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_TRANSPARENCY","maxValue":100,"minValue":50,"percent":true,"setting":6,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_BACKGROUND","maxValue":100,"minValue":0,"percent":true,"setting":12,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_TEXT_SIZE","maxValue":150,"minValue":50,"percent":true,"setting":11,"stepSize":10,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_VISIBILITY","options":[[0,"ALWAYS"],[1,"IN_COMBAT"],[2,"HIDDEN"],[3,"IN_GROUP"]],"setting":0,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_SHOW_SPEC_ICON","setting":8,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_DAMAGE_METER_SHOW_CLASS_COLOR","setting":9,"type":"Checkbox"}],"DurabilityFrame":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_DURABILITY_FRAME_SIZE","maxValue":200,"minValue":75,"percent":true,"setting":0,"stepSize":5,"type":"Slider"}],"EncounterBar":[],"EncounterEvents":[{"label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_TYPE","options":[[0,"TIMELINE"],[1,"BARS"]],"setting":10,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_ORIENTATION","options":[[0,"HORIZONTAL"],[1,"VERTICAL"]],"setting":0,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_ICON_DIRECTION","options":[[0,"LEFT"],[1,"RIGHT"]],"setting":1,"type":"Dropdown"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_ICON_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":3,"stepSize":10,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_OVERALL_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":4,"stepSize":10,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_PADDING","maxValue":20,"minValue":0,"percent":false,"setting":13,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_BAR_WIDTH","maxValue":200,"minValue":50,"percent":true,"setting":12,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_BACKGROUND","maxValue":100,"minValue":0,"percent":true,"setting":5,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_TRANSPARENCY","maxValue":100,"minValue":50,"percent":true,"setting":6,"stepSize":1,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_VISIBILITY","options":[[0,"ALWAYS"],[1,"IN_ENCOUNTER"]],"setting":7,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_TOOLTIPS","options":[[0,"NONE"],[1,"HUD"],[2,"CURSOR"]],"setting":8,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_FLIP_HORIZONTAL","setting":11,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_SHOW_SPELL_NAME","setting":2,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_SHOW_TIMER","setting":9,"type":"Checkbox"}],"ExtraAbilities":[],"GroupFinder":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_GROUP_FINDER_SIZE","maxValue":150,"minValue":50,"percent":true,"setting":0,"stepSize":5,"type":"Slider"}],"HudTooltip":[],"LootFrame":[],"LossOfControl":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_LOSS_OF_CONTROL_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":0,"stepSize":10,"type":"Slider"}],"MainActionBarEndCap":[{"label":"HUD_EDIT_MODE_SETTING_END_CAP_HIDDEN","setting":0,"type":"Checkbox"}],"MicroMenu":[{"label":"HUD_EDIT_MODE_SETTING_MICRO_MENU_ORIENTATION","options":[[0,"HORIZONTAL"],[1,"VERTICAL"]],"setting":0,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_MICRO_MENU_ORDER","options":[[0,"DEFAULT"],[1,"REVERSE"]],"setting":1,"type":"Dropdown"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_MICRO_MENU_SIZE","maxValue":200,"minValue":70,"percent":true,"setting":2,"stepSize":5,"type":"Slider"}],"Minimap":[{"label":"HUD_EDIT_MODE_SETTING_MINIMAP_HEADER_UNDERNEATH","setting":0,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_MINIMAP_ROTATE_MINIMAP","setting":1,"type":"Checkbox"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_MINIMAP_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":2,"stepSize":10,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_MINIMAP_ICON_SCALE","maxValue":200,"minValue":50,"percent":true,"setting":3,"stepSize":10,"type":"Slider"}],"ObjectiveTracker":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_HEIGHT","maxValue":1000,"minValue":400,"percent":false,"setting":0,"stepSize":10,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_OPACITY","maxValue":100,"minValue":0,"percent":true,"setting":1,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_OBJECTIVE_TRACKER_TEXT_SIZE","maxValue":20,"minValue":12,"percent":false,"setting":2,"stepSize":1,"type":"Slider"}],"PersonalResourceDisplay":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_SIZE","maxValue":150,"minValue":70,"percent":true,"setting":9,"stepSize":10,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_BAR_WIDTH","maxValue":150,"minValue":50,"percent":false,"setting":12,"stepSize":10,"type":"Slider"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_HEALTH_BAR_HEIGHT","maxValue":30,"minValue":10,"percent":false,"setting":4,"stepSize":1,"type":"Slider"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_POWER_BAR_HEIGHT","maxValue":30,"minValue":10,"percent":false,"setting":5,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_PADDING","maxValue":10,"minValue":0,"percent":false,"setting":6,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_OPACITY","maxValue":100,"minValue":50,"percent":true,"setting":7,"stepSize":1,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_VISIBLE_SETTING","options":[[0,"ALWAYS"],[1,"IN_COMBAT"],[2,"HIDDEN"]],"setting":8,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_HIDE_HEALTH_BAR","setting":0,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_HIDE_POWER_BAR","setting":2,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_HIDE_ALT_POWER_BAR","setting":14,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_HIDE_CLASS_INFO","setting":3,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_HIDE_CLASS_INFO_ON_PLAYER_FRAME","setting":10,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_SHOW_CLASS_COLOR","setting":11,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_PERSONAL_RESOURCE_DISPLAY_SHOW_BAR_TEXT","setting":13,"type":"Checkbox"}],"RaidWarning":[],"StatusTrackingBar":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_STATUS_TACKING_BAR_SIZE","maxValue":130,"minValue":50,"percent":true,"setting":3,"stepSize":5,"type":"Slider"}],"SwingTimer":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_SWING_TIMER_SCALE","maxValue":200,"minValue":50,"percent":true,"setting":0,"stepSize":10,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_SWING_TIMER_OPACITY","maxValue":100,"minValue":50,"percent":true,"setting":1,"stepSize":1,"type":"Slider"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_SWING_TIMER_WIDTH","maxValue":852,"minValue":213,"percent":false,"setting":3,"stepSize":10,"type":"Slider"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_SWING_TIMER_HEIGHT","maxValue":60,"minValue":15,"percent":false,"setting":4,"stepSize":1,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_SWING_TIMER_SHOW_BAR_TITLE","setting":5,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_SWING_TIMER_SHOW_TIME","setting":6,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_SWING_TIMER_VISIBLE_SETTING","options":[[0,"ALWAYS"],[1,"IN_COMBAT"],[2,"HIDDEN"]],"setting":2,"type":"Dropdown"}],"TalkingHeadFrame":[],"TimerBars":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_TIMER_BARS_SIZE","maxValue":150,"minValue":100,"percent":true,"setting":0,"stepSize":10,"type":"Slider"}],"TotemActionBar":[],"UnitFrame":[{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_CAST_BAR_UNDERNEATH","setting":1,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_USE_LARGER_FRAME","setting":3,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_BUFFS_ON_TOP","setting":2,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES","setting":4,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_SHOW_PARTY_FRAME_BACKGROUND","setting":5,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_CAST_BAR_ON_SIDE","setting":7,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_SIZE","options":[[0,"10"],[1,"25"],[2,"40"]],"setting":9,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_VIEW_ARENA_SIZE","options":[[0,"TWO"],[1,"THREE"]],"setting":17,"type":"Dropdown"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_WIDTH","maxValue":144,"minValue":72,"percent":false,"setting":10,"stepSize":2,"type":"Slider"},{"convert":"diffFromMin","label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_HEIGHT","maxValue":72,"minValue":36,"percent":false,"setting":11,"stepSize":2,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_GROUPS","options":[[0,"SEPARATE_GROUPS_VERTICAL"],[1,"SEPARATE_GROUPS_HORIZONTAL"],[2,"COMBINE_GROUPS_VERTICAL"],[3,"COMBINE_GROUPS_HORIZONTAL"]],"setting":13,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_SORT_BY","options":[[0,"SETTING_ROLE"],[1,"SETTING_GROUP"],[2,"SETTING_ALPHABETICAL"]],"setting":14,"type":"Dropdown"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_USE_HORIZONTAL_GROUPS","setting":6,"type":"Checkbox"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_DISPLAY_BORDER","setting":12,"type":"Checkbox"},{"altLabel":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_COLUMN_SIZE","convert":"raw","label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_ROW_SIZE","maxValue":10,"minValue":2,"percent":false,"setting":15,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_FRAME_SIZE","maxValue":200,"minValue":100,"percent":true,"setting":16,"stepSize":5,"type":"Slider"},{"label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_AURA_ORGANIZATION","options":[[0,"LEGACY"],[1,"BUFFS_TOP"],[2,"BUFFS_RIGHT"]],"setting":18,"type":"Dropdown"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_CONTAINER_OPACITY","maxValue":100,"minValue":50,"percent":true,"setting":20,"stepSize":1,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_BIGDEFENSIVE_AURA_ICON_SIZE","maxValue":100,"minValue":50,"percent":true,"setting":21,"stepSize":5,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_BUFF_AURA_ICON_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":22,"stepSize":10,"type":"Slider"},{"convert":"default","label":"HUD_EDIT_MODE_SETTING_UNIT_FRAME_AURA_ICON_SIZE","maxValue":200,"minValue":50,"percent":true,"setting":19,"stepSize":10,"type":"Slider"}],"VehicleLeaveButton":[],"VehicleSeatIndicator":[{"convert":"default","label":"HUD_EDIT_MODE_SETTING_VEHICLE_SEAT_INDICATOR_SIZE","maxValue":100,"minValue":50,"percent":true,"setting":0,"stepSize":5,"type":"Slider"}]},"enums":{"ActionBarOrientation":{"Horizontal":0,"Vertical":1},"ActionBarVisibleSetting":{"Always":0,"Hidden":3,"InCombat":1,"OutOfCombat":2},"AuraFrameIconDirection":{"Down":0,"Left":0,"Right":1,"Up":1},"AuraFrameIconWrap":{"Down":0,"Left":0,"Right":1,"Up":1},"AuraFrameOrientation":{"Horizontal":0,"Vertical":1},"AuraFrameVisibleSetting":{"Always":0,"Hidden":2,"InCombat":1},"BagsDirection":{"Down":1,"Left":0,"Right":1,"Up":0},"BagsOrientation":{"Horizontal":0,"Vertical":1},"CooldownViewerBarContent":{"IconAndName":0,"IconOnly":1,"NameOnly":2},"CooldownViewerIconDirection":{"Left":0,"Right":1},"CooldownViewerOrientation":{"Horizontal":0,"Vertical":1},"CooldownViewerVisibleSetting":{"Always":0,"Hidden":2,"InCombat":1},"DamageMeterNumbers":{"Compact":1,"Complete":2,"Minimal":0},"DamageMeterStyle":{"Bordered":2,"Default":0,"FullBackground":3,"Thin":1},"DamageMeterVisibility":{"Always":0,"Hidden":2,"InCombat":1,"InGroup":3},"EditModeAccountSetting":{"DeprecatedShowDebuffFrame":11,"EnableAdvancedOptions":23,"EnableSnap":22,"GridSpacing":1,"SettingsExpanded":2,"ShowArchaeologyBar":27,"ShowArenaFrames":17,"ShowBossFrames":16,"ShowBuffsAndDebuffs":10,"ShowCastBar":7,"ShowCooldownViewer":28,"ShowDamageMeter":31,"ShowDurabilityFrame":21,"ShowEncounterBar":8,"ShowEncounterEvents":30,"ShowExternalDefensives":32,"ShowExtraAbilities":9,"ShowGrid":0,"ShowGroupFinder":35,"ShowHudTooltip":19,"ShowLootFrame":18,"ShowLossOfControl":36,"ShowPartyFrames":12,"ShowPersonalResourceDisplay":29,"ShowPetActionBar":5,"ShowPetFrame":24,"ShowPossessActionBar":6,"ShowRaidFrames":13,"ShowRaidWarning":33,"ShowStanceBar":4,"ShowStatusTrackingBar2":20,"ShowSwingTimer":37,"ShowTalkingHeadFrame":14,"ShowTargetAndFocus":3,"ShowTimerBars":25,"ShowTotemActionBar":34,"ShowVehicleLeaveButton":15,"ShowVehicleSeatIndicator":26},"EditModeActionBarSetting":{"AlwaysShowButtons":9,"DeprecatedSnapToSide":7,"HideBarArt":6,"HideBarScrolling":8,"IconPadding":4,"IconSize":3,"NumIcons":2,"NumRows":1,"Orientation":0,"VisibleSetting":5},"EditModeActionBarSystemIndices":{"Bar2":2,"Bar3":3,"ExtraBar1":6,"ExtraBar2":7,"ExtraBar3":8,"MainBar":1,"PetActionBar":12,"PossessActionBar":13,"RightBar1":4,"RightBar2":5,"StanceBar":11},"EditModeArchaeologyBarSetting":{"Size":0},"EditModeAuraFrameSetting":{"DeprecatedShowFull":7,"IconDirection":2,"IconLimitBuffFrame":3,"IconLimitDebuffFrame":4,"IconPadding":6,"IconSize":5,"IconWrap":1,"Opacity":9,"Orientation":0,"ShowDispelType":10,"VisibleSetting":8},"EditModeAuraFrameSystemIndices":{"BuffFrame":1,"DebuffFrame":2,"ExternalDefensivesFrame":3},"EditModeBagsSetting":{"BagSlotPadding":3,"Direction":1,"Orientation":0,"Size":2},"EditModeCastBarSetting":{"BarSize":0,"LockToPlayerFrame":1,"ShowCastTime":2},"EditModeChatFrameSetting":{"HeightHundreds":2,"HeightTensAndOnes":3,"WidthHundreds":0,"WidthTensAndOnes":1},"EditModeCooldownViewerSetting":{"BarContent":7,"BarWidthScale":11,"HideWhenInactive":8,"IconDirection":2,"IconLimit":1,"IconPadding":4,"IconSize":3,"Opacity":5,"Orientation":0,"ShowTimer":9,"ShowTooltips":10,"VisibleSetting":6},"EditModeCooldownViewerSystemIndices":{"BuffBar":4,"BuffIcon":3,"Essential":1,"Utility":2},"EditModeDamageMeterSetting":{"BackgroundTransparency":12,"BarHeight":10,"FrameHeight":4,"FrameWidth":3,"Numbers":2,"ObsoleteReuse1":7,"Padding":5,"ShowClassColor":9,"ShowSpecIcon":8,"Style":1,"TextSize":11,"Transparency":6,"Visibility":0},"EditModeDurabilityFrameSetting":{"Size":0},"EditModeEncounterEventsSetting":{"BackgroundTransparency":5,"BarWidth":12,"FlipHorizontally":11,"IconDirection":1,"IconSize":3,"Orientation":0,"OverallSize":4,"Padding":13,"ShowSpellName":2,"ShowTimer":9,"TooltipAnchor":8,"Transparency":6,"ViewType":10,"Visibility":7},"EditModeEncounterEventsSystemIndices":{"CriticalWarnings":2,"MediumWarnings":3,"NormalWarnings":4,"Timeline":1},"EditModeGroupFinderSetting":{"Size":0},"EditModeLayoutType":{"Account":1,"Character":2,"Override":3,"Preset":0},"EditModeLossOfControlSetting":{"Size":0},"EditModeMainActionBarEndCapSetting":{"Hidden":0},"EditModeMainActionBarEndCapSystemIndices":{"EndCapLeft":1,"EndCapRight":2},"EditModeMicroMenuSetting":{"DeprecatedEyeSize":3,"Order":1,"Orientation":0,"Size":2},"EditModeMinimapSetting":{"HeaderUnderneath":0,"IconScale":3,"RotateMinimap":1,"Size":2},"EditModeObjectiveTrackerSetting":{"Height":0,"Opacity":1,"TextSize":2},"EditModePersonalResourceDisplaySetting":{"BarWidth":12,"DeprecatedOnlyShowInCombat":1,"HealthBarHeight":4,"HideAltPower":14,"HideClassInfo":3,"HideClassInfoOnPlayerFrame":10,"HideHealth":0,"HidePower":2,"Opacity":7,"Padding":6,"PowerBarHeight":5,"ShowBarText":13,"ShowClassColor":11,"Size":9,"VisibleSetting":8},"EditModePresetLayouts":{"Classic":1,"Gamepad":2,"Modern":0},"EditModeRaidWarningSetting":{"None":0},"EditModeSettingDisplayType":{"Checkbox":1,"Dropdown":0,"Slider":2},"EditModeStatusTrackingBarSetting":{"Height":0,"Size":3,"TextSize":2,"Width":1},"EditModeStatusTrackingBarSystemIndices":{"StatusTrackingBar1":1,"StatusTrackingBar2":2},"EditModeSwingTimerSetting":{"Height":4,"Opacity":1,"Scale":0,"ShowBarTitle":5,"ShowTime":6,"Visibility":2,"Width":3},"EditModeSwingTimerSystemIndices":{"MainHand":1,"OffHand":2,"Ranged":3},"EditModeSwingTimerVisibility":{"Always":0,"Hidden":2,"InCombat":1},"EditModeSystem":{"ActionBar":0,"ArchaeologyBar":19,"AuraFrame":6,"Bags":14,"CastBar":1,"ChatFrame":8,"CooldownViewer":20,"DamageMeter":23,"DurabilityFrame":16,"EncounterBar":4,"EncounterEvents":22,"ExtraAbilities":5,"GroupFinder":27,"HudTooltip":11,"LootFrame":10,"LossOfControl":28,"MainActionBarEndCap":26,"MicroMenu":13,"Minimap":2,"ObjectiveTracker":12,"PersonalResourceDisplay":21,"RaidWarning":24,"StatusTrackingBar":15,"SwingTimer":29,"TalkingHeadFrame":7,"TimerBars":17,"TotemActionBar":25,"UnitFrame":3,"VehicleLeaveButton":9,"VehicleSeatIndicator":18},"EditModeTimerBarsSetting":{"Size":0},"EditModeUnitFrameSetting":{"AuraOrganizationType":18,"BigDefensiveIconSize":21,"BuffIconSize":22,"BuffsOnTop":2,"CastBarOnSide":7,"CastBarUnderneath":1,"DebuffIconSize":19,"DisplayBorder":12,"FrameHeight":11,"FrameSize":16,"FrameWidth":10,"HidePortrait":0,"Opacity":20,"RaidGroupDisplayType":13,"RowSize":15,"ShowCastTime":8,"ShowPartyFrameBackground":5,"SortPlayersBy":14,"UseHorizontalGroups":6,"UseLargerFrame":3,"UseRaidStylePartyFrames":4,"ViewArenaSize":17,"ViewRaidSize":9},"EditModeUnitFrameSystemIndices":{"Arena":7,"Boss":6,"Focus":3,"Party":4,"Pet":8,"Player":1,"Raid":5,"Target":2},"EditModeVehicleSeatIndicatorSetting":{"Size":0},"EncounterEventsIconDirection":{"Bottom":1,"Left":0,"Right":1,"Top":0},"EncounterEventsOrientation":{"Horizontal":0,"Vertical":1},"EncounterEventsTooltipAnchor":{"Cursor":2,"Default":1,"Hidden":0},"EncounterEventsViewType":{"Bars":1,"Timeline":0},"EncounterEventsVisibility":{"Always":0,"DeprecatedHidden":2,"InEncounter":1},"MicroMenuOrder":{"Default":0,"Reverse":1},"MicroMenuOrientation":{"Horizontal":0,"Vertical":1},"PersonalResourceDisplayVisibleSetting":{"Always":0,"Hidden":2,"InCombat":1},"RaidAuraOrganizationType":{"BuffsRightDebuffsLeft":2,"BuffsTopDebuffsBottom":1,"Legacy":0},"RaidGroupDisplayType":{"CombineGroupsHorizontal":3,"CombineGroupsVertical":2,"SeparateGroupsHorizontal":1,"SeparateGroupsVertical":0},"SortPlayersBy":{"Alphabetical":2,"Group":1,"Role":0},"ViewArenaSize":{"Three":1,"Two":0},"ViewRaidSize":{"Forty":2,"Ten":0,"TwentyFive":1}}}''')
ENUMS = _SCHEMA["enums"]
DISPLAY = _SCHEMA["displayInfo"]

BASE = 90
CHAR0 = 35  # '#'

FRAME_POINTS = ["TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"]

SYSTEM_NAMES = {v: k for k, v in ENUMS["EditModeSystem"].items()}

# system -> (indices enum, settings enum)
SYSTEM_ENUMS = {
    "ActionBar": ("EditModeActionBarSystemIndices", "EditModeActionBarSetting"),
    "CastBar": (None, "EditModeCastBarSetting"),
    "Minimap": (None, "EditModeMinimapSetting"),
    "UnitFrame": ("EditModeUnitFrameSystemIndices", "EditModeUnitFrameSetting"),
    "EncounterBar": (None, None),
    "ExtraAbilities": (None, None),
    "AuraFrame": ("EditModeAuraFrameSystemIndices", "EditModeAuraFrameSetting"),
    "TalkingHeadFrame": (None, None),
    "ChatFrame": (None, "EditModeChatFrameSetting"),
    "VehicleLeaveButton": (None, None),
    "LootFrame": (None, None),
    "HudTooltip": (None, None),
    "ObjectiveTracker": (None, "EditModeObjectiveTrackerSetting"),
    "MicroMenu": (None, "EditModeMicroMenuSetting"),
    "Bags": (None, "EditModeBagsSetting"),
    "StatusTrackingBar": ("EditModeStatusTrackingBarSystemIndices", "EditModeStatusTrackingBarSetting"),
    "DurabilityFrame": (None, "EditModeDurabilityFrameSetting"),
    "TimerBars": (None, "EditModeTimerBarsSetting"),
    "VehicleSeatIndicator": (None, "EditModeVehicleSeatIndicatorSetting"),
    "ArchaeologyBar": (None, "EditModeArchaeologyBarSetting"),
    "CooldownViewer": ("EditModeCooldownViewerSystemIndices", "EditModeCooldownViewerSetting"),
    "PersonalResourceDisplay": (None, "EditModePersonalResourceDisplaySetting"),
    "EncounterEvents": ("EditModeEncounterEventsSystemIndices", "EditModeEncounterEventsSetting"),
    "DamageMeter": (None, "EditModeDamageMeterSetting"),
    "RaidWarning": (None, "EditModeRaidWarningSetting"),
    "TotemActionBar": (None, None),
    "MainActionBarEndCap": ("EditModeMainActionBarEndCapSystemIndices", "EditModeMainActionBarEndCapSetting"),
    "GroupFinder": (None, "EditModeGroupFinderSetting"),
    "LossOfControl": (None, "EditModeLossOfControlSetting"),
    "SwingTimer": ("EditModeSwingTimerSystemIndices", "EditModeSwingTimerSetting"),
}

# the global frame each system record drives (from the client XML: frames that
# inherit the EditMode*SystemTemplate and their systemIndex keyValues)
FRAMES = {
    ("ActionBar", 1): "MainActionBar", ("ActionBar", 2): "MultiBarBottomLeft",
    ("ActionBar", 3): "MultiBarBottomRight", ("ActionBar", 4): "MultiBarRight",
    ("ActionBar", 5): "MultiBarLeft", ("ActionBar", 6): "MultiBar5",
    ("ActionBar", 7): "MultiBar6", ("ActionBar", 8): "MultiBar7",
    ("ActionBar", 11): "StanceBar", ("ActionBar", 12): "PetActionBar",
    ("ActionBar", 13): "PossessActionBar",
    ("CastBar", None): "PlayerCastingBarFrame",
    ("Minimap", None): "MinimapCluster",
    ("UnitFrame", 1): "PlayerFrame", ("UnitFrame", 2): "TargetFrame",
    ("UnitFrame", 3): "FocusFrame", ("UnitFrame", 4): "PartyFrame",
    ("UnitFrame", 5): "CompactRaidFrameContainer", ("UnitFrame", 6): "BossTargetFrameContainer",
    ("UnitFrame", 7): "CompactArenaFrame", ("UnitFrame", 8): "PetFrame",
    ("EncounterBar", None): "EncounterBar",
    ("ExtraAbilities", None): "ExtraAbilityContainer",
    ("AuraFrame", 1): "BuffFrame", ("AuraFrame", 2): "DebuffFrame",
    ("AuraFrame", 3): "ExternalDefensivesFrame",
    ("TalkingHeadFrame", None): "TalkingHeadFrame",
    ("ChatFrame", None): "ChatFrame1",
    ("VehicleLeaveButton", None): "MainMenuBarVehicleLeaveButton",
    ("LootFrame", None): "LootFrame",
    ("HudTooltip", None): "GameTooltipDefaultContainer",
    ("ObjectiveTracker", None): "ObjectiveTrackerFrame",
    ("MicroMenu", None): "MicroMenuContainer",
    ("Bags", None): "BagsBar",
    ("StatusTrackingBar", 1): "MainStatusTrackingBarContainer",
    ("StatusTrackingBar", 2): "SecondaryStatusTrackingBarContainer",
    ("DurabilityFrame", None): "DurabilityFrame",
    ("TimerBars", None): "MirrorTimerContainer",
    ("VehicleSeatIndicator", None): "VehicleSeatIndicator",
    ("ArchaeologyBar", None): "ArcheologyDigsiteProgressBar",
    ("CooldownViewer", 1): "EssentialCooldownViewer", ("CooldownViewer", 2): "UtilityCooldownViewer",
    ("CooldownViewer", 3): "BuffIconCooldownViewer", ("CooldownViewer", 4): "BuffBarCooldownViewer",
    ("PersonalResourceDisplay", None): "PersonalResourceDisplayFrame",
    ("EncounterEvents", 1): "EncounterTimeline", ("EncounterEvents", 2): "CriticalEncounterWarnings",
    ("EncounterEvents", 3): "MediumEncounterWarnings", ("EncounterEvents", 4): "MinorEncounterWarnings",
    ("DamageMeter", None): "DamageMeter",
    ("RaidWarning", None): "RaidWarningFrame",
    ("TotemActionBar", None): "MultiCastActionBarFrame",
    ("MainActionBarEndCap", 1): "MainActionBar.EndCaps.LeftEndCap",
    ("MainActionBarEndCap", 2): "MainActionBar.EndCaps.RightEndCap",
    ("GroupFinder", None): "QueueStatusButton",
    ("LossOfControl", None): "LossOfControlFrame",
    ("SwingTimer", 1): "SwingTimerMainHandFrame", ("SwingTimer", 2): "SwingTimerOffHandFrame",
    ("SwingTimer", 3): "SwingTimerRangedFrame",
}


# dropdown settings -> the enum their stored value is a member of
DROPDOWN_ENUMS = {
    ("ActionBar", 0): "ActionBarOrientation", ("ActionBar", 5): "ActionBarVisibleSetting",
    ("UnitFrame", 9): "ViewRaidSize", ("UnitFrame", 13): "RaidGroupDisplayType", ("UnitFrame", 14): "SortPlayersBy",
    ("UnitFrame", 17): "ViewArenaSize", ("UnitFrame", 18): "RaidAuraOrganizationType",
    ("AuraFrame", 0): "AuraFrameOrientation", ("AuraFrame", 8): "AuraFrameVisibleSetting",
    ("MicroMenu", 0): "MicroMenuOrientation", ("MicroMenu", 1): "MicroMenuOrder", ("Bags", 0): "BagsOrientation",
    ("CooldownViewer", 0): "CooldownViewerOrientation", ("CooldownViewer", 2): "CooldownViewerIconDirection",
    ("CooldownViewer", 6): "CooldownViewerVisibleSetting", ("CooldownViewer", 7): "CooldownViewerBarContent",
    ("PersonalResourceDisplay", 8): "PersonalResourceDisplayVisibleSetting",
    ("EncounterEvents", 0): "EncounterEventsOrientation", ("EncounterEvents", 7): "EncounterEventsVisibility",
    ("EncounterEvents", 8): "EncounterEventsTooltipAnchor", ("EncounterEvents", 10): "EncounterEventsViewType",
    ("DamageMeter", 0): "DamageMeterVisibility", ("DamageMeter", 1): "DamageMeterStyle", ("DamageMeter", 2): "DamageMeterNumbers",
    ("SwingTimer", 2): "EditModeSwingTimerVisibility",
}
# dropdowns whose labels follow the system's orientation (UpdateDisplayInfoOptions)
ORIENTED = {
    ("AuraFrame", 1): (0, ["Down", "Up"], ["Left", "Right"]),        # IconWrap
    ("AuraFrame", 2): (0, ["Left", "Right"], ["Down", "Up"]),        # IconDirection
    ("Bags", 1): (0, ["Left", "Right"], ["Up", "Down"]),             # Direction
    ("EncounterEvents", 1): (0, ["Left", "Right"], ["Top", "Bottom"]),
}


class LayoutError(ValueError):
    pass


def _rev(enum_name):
    if not enum_name:
        return {}
    return {v: k for k, v in ENUMS[enum_name].items()}


def _display_map(system_name):
    return {e["setting"]: e for e in DISPLAY.get(system_name, [])}


def setting_range(system_name, setting_id):
    """(rawMin, rawMax, text) for a stored value, from the settings dialog info."""
    di = _display_map(system_name).get(setting_id)
    if di is None:
        return None
    t = di["type"]
    if t == "Checkbox":
        return 0, 1, "checkbox 0/1"
    if t == "Dropdown":
        vals = [o[0] for o in di["options"]]
        en = DROPDOWN_ENUMS.get((system_name, setting_id))
        if en:
            lab = {v: k for k, v in ENUMS[en].items()}
            txt = ", ".join("%d=%s" % (v, lab.get(v, n)) for v, n in sorted(di["options"]))
        elif (system_name, setting_id) in ORIENTED:
            oid, hz, vt = ORIENTED[(system_name, setting_id)]
            txt = "0=%s/%s, 1=%s/%s (horizontal/vertical orientation)" % (hz[0], vt[0], hz[1], vt[1])
        else:
            txt = ", ".join("%d=%s" % (v, n) for v, n in sorted(di["options"]))
        return min(vals), max(vals), "dropdown " + txt
    mn, mx = di["minValue"], di["maxValue"]
    st = di.get("stepSize") or 1
    conv = di.get("convert")
    unit = "%" if di.get("percent") else ""
    if conv == "default":
        rmax = int(round((mx - mn) / st))
        return 0, rmax, "slider %g..%g%s step %g; stored = (value-%g)/%g, raw 0..%d" % (mn, mx, unit, st, mn, st, rmax)
    if conv == "diffFromMin":
        return 0, int(mx - mn), "slider %g..%g%s (step %g in the dialog); stored = value-%g, raw 0..%d" % (mn, mx, unit, st, mn, mx - mn)
    if conv == "raw":
        return int(mn), int(mx), "slider %g..%g%s step %g; stored = value" % (mn, mx, unit, st)
    return None


def raw_to_display(system_name, setting_id, raw):
    """What the settings dialog shows for a stored value (clamped like the game)."""
    di = _display_map(system_name).get(setting_id)
    if di is None:
        return None
    t = di["type"]
    if t == "Checkbox":
        return bool(min(max(raw, 0), 1))
    if t == "Dropdown":
        for v, n in di["options"]:
            if v == raw:
                return n
        return None
    mn, mx = di["minValue"], di["maxValue"]
    st = di.get("stepSize") or 1
    conv = di.get("convert")
    if conv == "default":
        v = raw * st + mn
    elif conv == "diffFromMin":
        v = raw + mn
    else:
        v = raw
    v = min(max(v, mn), mx)
    return v


def display_to_raw(system_name, setting_id, value):
    di = _display_map(system_name).get(setting_id)
    if di is None:
        raise LayoutError("no display info for %s setting %d" % (system_name, setting_id))
    if di["type"] != "Slider":
        return int(value)
    mn = di["minValue"]
    st = di.get("stepSize") or 1
    conv = di.get("convert")
    if conv == "default":
        return int(round((value - mn) / st))
    if conv == "diffFromMin":
        return int(round(value - mn))
    return int(round(value))


def _meaning(system_name, setting_name, setting_id, raw, others=None):
    di = _display_map(system_name).get(setting_id)
    if (system_name, setting_id) in ORIENTED and others is not None:
        oid, horiz, vert = ORIENTED[(system_name, setting_id)]
        labels = vert if others.get(oid, 0) == 1 else horiz
        return labels[raw] if 0 <= raw < len(labels) else "?%d" % raw
    en = DROPDOWN_ENUMS.get((system_name, setting_id))
    if en:
        names = [k for k, v in ENUMS[en].items() if v == raw]
        if names:
            return names[0]
    if system_name == "ChatFrame":
        return {"WidthHundreds": "width hundreds digit", "WidthTensAndOnes": "width tens+ones",
                "HeightHundreds": "height hundreds digit", "HeightTensAndOnes": "height tens+ones"}.get(setting_name, "")
    if di is None:
        return "not shown in the Edit Mode dialog (deprecated/hidden setting); stored %d" % raw
    d = raw_to_display(system_name, setting_id, raw)
    if di["type"] == "Slider":
        unit = "%" if di.get("percent") else ""
        return "%g%s" % (d, unit)
    if di["type"] == "Checkbox":
        return "on" if d else "off"
    return str(d)


# ---------------------------------------------------------------- settings

def decode_settings(token):
    if token == "#":
        return []
    if len(token) % 2:
        raise LayoutError("settings token has odd length: %r" % token)
    pairs = []
    for i in range(0, len(token), 2):
        sid = ord(token[i]) - CHAR0
        dig = ord(token[i + 1]) - CHAR0
        if not (0 <= sid < BASE and 0 <= dig < BASE):
            raise LayoutError("bad settings chars %r" % token[i:i + 2])
        pairs.append((sid, dig))
    out = []  # [(id, value, ndigits)]
    for sid, dig in pairs:
        if out and out[-1][0] == sid:
            s, v, n = out[-1]
            out[-1] = (s, v + dig * BASE ** n, n + 1)
        else:
            out.append((sid, dig, 1))
    # the game writes the minimal digit count; anything else could not round-trip
    for sid, v, n in out:
        if _ndigits(v) != n:
            raise LayoutError("non-minimal value encoding for setting %d" % sid)
    return [(sid, v) for sid, v, n in out]


def _ndigits(v):
    n = 1
    while v >= BASE:
        v //= BASE
        n += 1
    return n


def encode_settings(settings):
    if not settings:
        return "#"
    parts = []
    for sid, v in settings:
        if not (0 <= sid < BASE):
            raise LayoutError("setting id out of range: %r" % sid)
        v = int(v)
        if v < 0:
            raise LayoutError("negative setting value: %r" % v)
        while True:
            parts.append(chr(CHAR0 + sid) + chr(CHAR0 + v % BASE))
            v //= BASE
            if v == 0:
                break
    return "".join(parts)


# ---------------------------------------------------------------- floats

def _fmt(x):
    return "%.1f" % float(x)


def _parse_float(tok):
    v = float(tok)
    if _fmt(v) != tok:
        raise LayoutError("offset %r is not in %%.1f form" % tok)
    return v


def _point_name(n):
    if not (0 <= n < len(FRAME_POINTS)):
        raise LayoutError("bad FramePoint %r" % n)
    return FRAME_POINTS[n]


def _point_num(p):
    if isinstance(p, int):
        return p
    return FRAME_POINTS.index(p)


# ---------------------------------------------------------------- systems

def _decode_system(tok, i):
    try:
        sysid = int(tok[i]); widx = int(tok[i + 1]); dflt = int(tok[i + 2])
        p = int(tok[i + 3]); rp = int(tok[i + 4]); rel = tok[i + 5]
        x = _parse_float(tok[i + 6]); y = _parse_float(tok[i + 7])
    except (IndexError, ValueError) as e:
        raise LayoutError("bad system record at token %d: %s" % (i, e))
    for t in tok[i:i + 3] + tok[i + 3:i + 5]:
        if str(int(t)) != t:
            raise LayoutError("non-canonical integer %r" % t)
    i += 8
    a2 = None
    if tok[i] == "-1":
        i += 1
    else:  # unverified: never seen in any sample
        a2 = {"point": _point_name(int(tok[i])), "relativePoint": _point_name(int(tok[i + 1])),
              "relativeTo": tok[i + 2], "offsetX": _parse_float(tok[i + 3]), "offsetY": _parse_float(tok[i + 4]),
              "_unverified": True}
        i += 5
    settings_tok = tok[i]
    i += 1
    sname = SYSTEM_NAMES.get(sysid, "System%d" % sysid)
    idx_enum, set_enum = SYSTEM_ENUMS.get(sname, (None, None))
    lua_idx = None if widx == -1 else widx + 1
    idx_names = _rev(idx_enum)
    set_names = _rev(set_enum)
    settings = []
    pairs = decode_settings(settings_tok)
    others = dict(pairs)
    for sid, v in pairs:
        name = set_names.get(sid, "Setting%d" % sid)
        rng = setting_range(sname, sid)
        entry = {"id": sid, "name": name, "value": v, "meaning": _meaning(sname, name, sid, v, others)}
        if rng:
            entry["range"] = rng[2]
        settings.append(entry)
    if sname == "ChatFrame":
        vals = {e["name"]: e["value"] for e in settings}
        if "WidthHundreds" in vals and "WidthTensAndOnes" in vals:
            w = vals["WidthHundreds"] * 100 + vals["WidthTensAndOnes"]
            for e in settings:
                if e["name"].startswith("Width"):
                    e["meaning"] += " -> width %d (dialog 250..800, step 1)" % w
        if "HeightHundreds" in vals and "HeightTensAndOnes" in vals:
            h = vals["HeightHundreds"] * 100 + vals["HeightTensAndOnes"]
            for e in settings:
                if e["name"].startswith("Height"):
                    e["meaning"] += " -> height %d (dialog 120..800, step 1)" % h
    rec = {
        "key": "%d:%d" % (sysid, widx),
        "system": sysid,
        "systemName": sname,
        "systemIndex": lua_idx,
        "systemIndexName": idx_names.get(lua_idx) if lua_idx is not None else None,
        "frame": FRAMES.get((sname, lua_idx)),
        "isInDefaultPosition": bool(dflt),
        "anchor": {"point": _point_name(p), "relativePoint": _point_name(rp), "relativeTo": rel,
                   "offsetX": x, "offsetY": y},
        "anchor2": a2,
        "settings": settings,
    }
    if dflt not in (0, 1):
        raise LayoutError("isInDefaultPosition not 0/1")
    return rec, i


def _encode_system(s):
    sysid = s["system"] if "system" in s else ENUMS["EditModeSystem"][s["systemName"]]
    li = s.get("systemIndex")
    widx = -1 if li is None else int(li) - 1
    a = s["anchor"]
    parts = [str(int(sysid)), str(widx), "1" if s.get("isInDefaultPosition") else "0",
             str(_point_num(a["point"])), str(_point_num(a["relativePoint"])), a["relativeTo"],
             _fmt(a["offsetX"]), _fmt(a["offsetY"])]
    a2 = s.get("anchor2")
    if a2 is None:
        parts.append("-1")
    else:
        parts += [str(_point_num(a2["point"])), str(_point_num(a2["relativePoint"])), a2["relativeTo"],
                  _fmt(a2["offsetX"]), _fmt(a2["offsetY"])]
    parts.append(encode_settings([(int(e["id"]), int(e["value"])) for e in s.get("settings", [])]))
    return " ".join(parts)


def _decode_systems(tok, i, count):
    systems = []
    for _ in range(count):
        rec, i = _decode_system(tok, i)
        systems.append(rec)
    return systems, i


# ---------------------------------------------------------------- public API

def decode(text):
    """Share string -> dict. A trailing newline/whitespace (as in a saved .txt)
    is kept in 'trailer' so encode() reproduces the file byte for byte."""
    body = text.rstrip("\r\n\t ")
    trailer = text[len(body):]
    tok = body.split(" ")
    if "" in tok:
        raise LayoutError("empty token (double space?)")
    version = int(tok[0])
    # version 4 (client 1.60.1.70009, 2026-09-25): the input style follows
    # the version -- 0 mouse and keyboard, 1 gamepad (Enum.InputDeviceInterfaceType)
    style = None
    start = 1
    if version >= 4:
        style = int(tok[1])
        start = 2
    count = int(tok[start])
    systems, i = _decode_systems(tok, start + 1, count)
    if i != len(tok):
        raise LayoutError("%d tokens left over" % (len(tok) - i))
    out = {"format": "EditModeLayoutShareString", "version": version, "systemCount": count, "systems": systems}
    if style is not None:
        out["interfaceStyle"] = style
    if trailer:
        out["trailer"] = trailer
    return out


def encode(layout):
    """dict -> share string. Version 4 unless the dict says otherwise (a v3
    string is misread by the patched client: its count becomes the style)."""
    systems = layout["systems"]
    version = int(layout.get("version", 4))
    parts = [str(version)]
    if version >= 4:
        style = int(layout.get("interfaceStyle", 0))
        if style not in (0, 1):
            raise LayoutError("interfaceStyle must be 0 (mouse and keyboard) or 1 (gamepad), not %r" % style)
        parts.append(str(style))
    parts.append(str(len(systems)))
    parts += [_encode_system(s) for s in systems]
    return " ".join(parts) + layout.get("trailer", "")


def decode_account_cache(text):
    """edit-mode-cache-account.txt -> dict (same system records)."""
    body = text
    trailer = ""
    while body and body[-1] in "\0\r\n":
        trailer = body[-1] + trailer
        body = body[:-1]
    # layout names may contain spaces: walk the string with a cursor
    pos = 0

    def take():
        nonlocal pos
        j = body.find(" ", pos)
        if j < 0:
            j = len(body)
        t = body[pos:j]
        pos = j + 1
        return t

    version = int(take())
    nacct = int(take())
    acct = [int(take()) for _ in range(nacct)]
    layouts = []
    while pos < len(body):
        nlen = int(take())
        name = body[pos:pos + nlen]
        pos += nlen + 1
        count = int(take())
        # decode count systems from the remaining tokens
        rest = body[pos:].split(" ")
        systems, used = _decode_systems(rest, 0, count)
        consumed = len(" ".join(rest[:used]))
        pos += consumed + 1
        layouts.append({"name": name, "systemCount": count, "systems": systems})
    names = _rev("EditModeAccountSetting")
    return {"format": "EditModeAccountCache", "version": version,
            "accountSettings": [{"id": k, "name": names.get(k, "Setting%d" % k), "value": v} for k, v in enumerate(acct)],
            "layouts": layouts, "trailer": trailer}


def encode_account_cache(obj):
    parts = [str(obj["version"]), str(len(obj["accountSettings"]))]
    parts += [str(int(e["value"])) for e in obj["accountSettings"]]
    for lay in obj["layouts"]:
        parts += [str(len(lay["name"])), lay["name"], str(len(lay["systems"]))]
        parts += [_encode_system(s) for s in lay["systems"]]
    return " ".join(parts) + obj.get("trailer", "")


def validate(layout):
    """Warnings for values outside what the Edit Mode dialog can produce."""
    warn = []
    for s in layout["systems"]:
        for e in s.get("settings", []):
            r = setting_range(s["systemName"], e["id"])
            if r and not (r[0] <= e["value"] <= r[1]):
                warn.append("%s %s=%d outside raw %d..%d" % (s["key"], e["name"], e["value"], r[0], r[1]))
    return warn


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("mode", choices=["decode", "encode", "roundtrip"])
    ap.add_argument("path")
    a = ap.parse_args()
    raw = open(a.path, "rb").read().decode("latin-1")
    if a.mode == "decode":
        print(json.dumps(decode(raw), indent=1))
    elif a.mode == "encode":
        sys.stdout.buffer.write(encode(json.loads(raw)).encode("latin-1"))
    else:
        out = encode(decode(raw))
        print("byte-identical" if out == raw else "DIFFERENT")
