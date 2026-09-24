--------------------------------------------------------------------------------
-- MelloUI - Custom Sounds
--
-- The game's interface sounds replaced by the custom library in
-- Media/Sounds/SFX (user, 2026-09-22: "replace the Default UI Sounds with
-- those", the first variant of each; Tools/import_sfx.py brings them in).
-- Off by default.
--
-- How a sound is replaced. The game plays a sound kit; a kit is one or more
-- sound FILES. This client has MuteSoundFile(fileDataID): the kit's file is
-- muted, so the game's own play of it is silent, and the addon plays the
-- replacement itself, from two places:
--   * PlaySound(kit) from the game's Lua (buttons, tabs, checkboxes, window
--     open/close, the whisper and invite alerts, the ready check): a post
--     hook on PlaySound sees the kit and plays the mapped file (KITS below;
--     an unnamed kit is placed by the file it uses, FILES).
--   * sounds the ENGINE plays on its own side (an item picked up or put
--     down, looted, sold, equipped, a quest turned in): no Lua sees them,
--     so the replacement rides on the event that goes with them
--     (CURSOR_CHANGED, CHAT_MSG_LOOT, PLAYER_EQUIPMENT_CHANGED, QUEST_TURNED_IN,
--     the merchant functions).
-- A muted file with no replacement would be a hole, so every file muted
-- here has a FILES default. The file ids and the kit -> file table come from
-- the client's SoundKitEntry (wago.tools, classic era 1.15.9; the vanilla
-- kits 80..1279 have carried the same files since 2004).
--
-- Hover ticks and the scroll wheel are ADDITIONS (the game has neither);
-- the library's scroll loop is unused. Sounds the library has no
-- counterpart for stay the game's.
--
-- /sfx shows the state, /sfx log prints every kit the game plays and what
-- was done with it (the verification), /sfx play <name> auditions a file,
-- /sfxdump lists the last events as copyable text.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local SOUND_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Sounds\\SFX\\"

local defaults = {
	channel = "SFX",
	clicks = true,       -- buttons, checkboxes, tabs, scroll arrows, cancel/quit
	windows = true,      -- windows opening and closing, page turns, the bags
	inventory = true,    -- items picked up, moved, put down, looted (rare items apart)
	equipment = true,    -- armour, weapons and jewellery equipped or taken off
	vendor = true,       -- buying and selling
	social = true,       -- whispers and group invites
	groupFinder = true,  -- queue entered, queue left, group ready / ready check
	crafting = true,     -- an item crafted
	quests = true,       -- a quest turned in
	errors = true,       -- "you can't do that" messages
	targets = true,      -- a target selected or lost
	levelUp = true,      -- the level up
	loot = true,         -- coins looted
	spells = true,       -- a spell, macro or ability dragged and placed
	map = true,          -- the minimap ping
	scrollWheel = true,  -- a ratchet notch per mouse-wheel step on any list (the game has none)
	hover = false,       -- a tick when the mouse reaches a button (the game has none)
}

local options = {
	{ type = "header", name = "Sounds" },
	{ type = "toggle", key = "clicks", name = "Clicks",
	  desc = "Buttons, checkboxes, tabs and scroll arrows: light clicks, a heavy one for Okay/Accept, a latch releasing for Cancel, Quit and abandoning a quest." },
	{ type = "toggle", key = "windows", name = "Windows",
	  desc = "A page turn when the character sheet, spell book, quest log or main menu opens, a latch when they close; the spell book's page turns; the bags as a leather pouch opening and closing." },
	{ type = "toggle", key = "inventory", name = "Inventory",
	  desc = "An item picked up, moved between slots, put down or looted; a rare or better item has its own sound. Silences the game's own pick-up and put-down sounds (the Equipment and Vendor sounds rely on that)." },
	{ type = "toggle", key = "equipment", parent = "inventory", name = "Equipment",
	  desc = "Buckles and plate for armour, a steel slide for weapons, jewellery ticks for rings, necks and trinkets; straps loosening when something is taken off." },
	{ type = "toggle", key = "vendor", parent = "inventory", name = "Vendor",
	  desc = "Coins on the counter when buying, coins into the pouch when selling (the automatic grey sale too)." },
	{ type = "toggle", key = "social", name = "Social",
	  desc = "A note under the door for a whisper, two knocks for a group invite." },
	{ type = "toggle", key = "groupFinder", name = "Group Finder",
	  desc = "The ledger for entering a queue or applying to a listing, a strike-through for leaving it, the bell for a group that is ready and for a ready check." },
	{ type = "toggle", key = "crafting", name = "Crafting",
	  desc = "The workbench when an item is crafted." },
	{ type = "toggle", key = "quests", name = "Quests",
	  desc = "The mechanism engaging when a quest is turned in." },
	{ type = "toggle", key = "errors", name = "Errors",
	  desc = "A muted knock for the game's red error messages (\"You can't do that yet\"), at most one every half second." },
	{ type = "toggle", key = "targets", name = "Targets",
	  desc = "An iron sight catching when a target is selected, a latch releasing when it is lost." },
	{ type = "toggle", key = "levelUp", name = "Level Up",
	  desc = "A seal struck into the record when you level." },
	{ type = "toggle", key = "loot", name = "Loot Coins",
	  desc = "Coins into the pouch when money is looted." },
	{ type = "toggle", key = "spells", name = "Spell Icons",
	  desc = "A page lifting when a spell, macro or ability is dragged, the slot latching when it is placed." },
	{ type = "toggle", key = "map", name = "Map Ping",
	  desc = "An iron pin into the parchment for a minimap ping." },
	{ type = "toggle", key = "scrollWheel", name = "Scroll Wheel",
	  desc = "One cog notch per mouse-wheel step on any list, window or the chat. The game has no wheel sound; this is an addition." },
	{ type = "toggle", key = "hover", name = "Hover Ticks",
	  desc = "A tiny tick when the mouse reaches a button. The game has no hover sound; this is an addition." },
	{ type = "header", name = "Output" },
	{ type = "dropdown", key = "channel", name = "Sound Channel", values = {
		{ value = "SFX", label = "Sound Effects" },
		{ value = "Master", label = "Master" },
		{ value = "Dialog", label = "Dialog" },
	}, desc = "The game volume slider the sounds follow." },
	{ type = "subheader", name = "/sfx shows the state, /sfx log prints what the game plays and what replaces it" },
	{ type = "header", name = "Preview" },
}

-- The Preview tab: a Play button per sound (user, 2026-09-22), in the
-- library's order, each with where the game uses it. Plays whether or not
-- the module or its family is on.
local PREVIEW = {
	{ "UI_Click_Light", "Click, light", "checkboxes, tabs, list rows, minimap zoom" },
	{ "UI_Click_Heavy", "Click, heavy", "Okay, Accept, the panel buttons, the main menu opening" },
	{ "UI_Hover", "Hover tick", "the mouse reaching a button (Hover Ticks)" },
	{ "UI_Cancel", "Cancel", "Cancel, Quit, a quest abandoned, a window closing, a target lost" },
	{ "UI_Error", "Error", "the red error messages" },
	{ "UI_Success", "Success", "a quest turned in, the group finder's rewards" },
	{ "UI_TargetSelect", "Target select", "a target selected" },
	{ "Scroll_Parchment", "Scroll, parchment", "the scroll arrows" },
	{ "Scroll_Wheel", "Scroll, wheel", "a mouse-wheel step (Scroll Wheel)" },
	{ "Page_Turn", "Page turn", "the character sheet, spell book and quest log opening; the spell book's pages" },
	{ "Inventory_Pickup", "Inventory, pick up", "an item onto the cursor; the bags opening" },
	{ "Inventory_Move", "Inventory, move", "an item swapped with another" },
	{ "Inventory_Drop", "Inventory, drop", "an item put down or looted; the bags closing" },
	{ "Rare_Item_Interaction", "Rare item", "a rare or better item picked up or looted" },
	{ "Loot_Coins", "Loot coins", "money looted" },
	{ "Equip_Armor", "Equip armour", "armour equipped" },
	{ "Unequip_Armor", "Unequip", "anything taken off" },
	{ "Equip_Weapon", "Equip weapon", "a weapon equipped" },
	{ "Equip_Accessory", "Equip accessory", "a ring, neck or trinket equipped" },
	{ "SpellIcon_Drag", "Spell icon, drag", "a spell, macro or ability onto the cursor" },
	{ "SpellIcon_Place", "Spell icon, place", "... placed on a bar" },
	{ "Craft_Item", "Craft", "an item crafted" },
	{ "Vendor_Buy", "Vendor, buy", "an item bought" },
	{ "Vendor_Sell", "Vendor, sell", "an item sold" },
	{ "Social_Whisper", "Whisper", "a whisper received" },
	{ "Social_GroupInvite", "Group invite", "a group invite received" },
	{ "DungeonFinder_Queue", "Queue entered", "a queue joined, a listing applied to, a role check" },
	{ "DungeonFinder_QueueDropped", "Queue left", "a queue left or declined" },
	{ "DungeonFinder_Ready", "Group ready", "the group ready, a ready check" },
	{ "Character_LevelUp", "Level up", "a level gained" },
	{ "Map_Ping", "Map ping", "a minimap ping" },
}

for _, entry in ipairs(PREVIEW) do
	local name = entry[1]
	options[#options + 1] = { type = "button", name = entry[2], hint = entry[3], text = "Play",
		desc = name .. ".ogg: " .. entry[3],
		onClick = function(module) module:Preview(name) end }
end

local M = MelloUI:RegisterModule("CustomSounds", {
	title = "Custom Sounds",
	desc = "The interface's sounds replaced by the custom library: iron, leather, parchment and stone for clicks, windows, bags, gear, vendors, whispers and the group finder.",
	enabledByDefault = false,
	defaults = defaults,
	options = options,
})

--------------------------------------------------------------------------------
-- The library: name -> the least gap between two plays (seconds)
--------------------------------------------------------------------------------

local SOUNDS = {
	UI_Click_Light = 0.03, UI_Click_Heavy = 0.05, UI_Hover = 0.06, UI_Cancel = 0.05, UI_Error = 0.5, UI_Success = 0.5,
	Scroll_Parchment = 0.03, Page_Turn = 0.1,
	Inventory_Pickup = 0.05, Inventory_Move = 0.05, Inventory_Drop = 0.05, Rare_Item_Interaction = 0.3,
	Equip_Armor = 0.1, Unequip_Armor = 0.1, Equip_Weapon = 0.1, Equip_Accessory = 0.1,
	Craft_Item = 0.2, Vendor_Buy = 0.1, Vendor_Sell = 0.12,
	Social_GroupInvite = 0.5, Social_Whisper = 0.5,
	DungeonFinder_Queue = 0.5, DungeonFinder_QueueDropped = 0.5, DungeonFinder_Ready = 0.5,
	UI_TargetSelect = 0.05, Character_LevelUp = 2.5, Loot_Coins = 0.15, SpellIcon_Drag = 0.05, SpellIcon_Place = 0.05,
	Map_Ping = 0.2, Scroll_Wheel = 0.03,
}

--------------------------------------------------------------------------------
-- The game's sound kits: kit -> { replacement, group }. The file each kit
-- plays is listed under FILES, with the default for the kits that are not
-- named here but play that file (the kit ids on each line).
--------------------------------------------------------------------------------

local KITS = {
	-- light clicks: checkboxes, tabs, list rows, the character rotate, minimap zoom
	[856] = { "UI_Click_Light", "clicks" },   -- IG_MAINMENU_OPTION_CHECKBOX_ON
	[857] = { "UI_Click_Light", "clicks" },   -- IG_MAINMENU_OPTION_CHECKBOX_OFF
	[858] = { "UI_Click_Light", "clicks" },   -- IG_MAINMENU_OPTION_FAER_TAB
	[841] = { "UI_Click_Light", "clicks" },   -- IG_CHARACTER_INFO_TAB
	[681] = { "UI_Click_Light", "clicks" },
	[861] = { "UI_Click_Light", "clicks" },   -- IG_INVENTORY_ROTATE_CHARACTER
	[825] = { "UI_Click_Light", "clicks" },   -- IG_CHAT_EMOTE_BUTTON
	[823] = { "UI_Click_Light", "clicks" },   -- IG_MINIMAP_ZOOM_IN
	[824] = { "UI_Click_Light", "clicks" },   -- IG_MINIMAP_ZOOM_OUT
	[877] = { "UI_Click_Light", "clicks" },   -- IG_QUEST_LIST_SELECT
	[864] = { "UI_Click_Light", "clicks" },   -- IG_BACKPACK_COIN_SELECT
	[891] = { "UI_Click_Light", "clicks" },   -- MONEY_FRAME_OPEN
	[821] = { "UI_Click_Light", "clicks" },   -- IG_MINIMAP_OPEN
	[822] = { "UI_Click_Light", "clicks" },   -- IG_MINIMAP_CLOSE
	-- scroll arrows
	[1115] = { "Scroll_Parchment", "clicks" },   -- U_CHAT_SCROLL_BUTTON
	[826] = { "Scroll_Parchment", "clicks" },    -- IG_CHAT_SCROLL_UP
	[827] = { "Scroll_Parchment", "clicks" },    -- IG_CHAT_SCROLL_DOWN
	[828] = { "Scroll_Parchment", "clicks" },    -- IG_CHAT_BOTTOM
	-- the heavy click: Okay, Accept, Continue, the panel buttons
	[852] = { "UI_Click_Heavy", "clicks" },   -- IG_MAINMENU_OPTION
	[855] = { "UI_Click_Heavy", "clicks" },   -- IG_MAINMENU_CONTINUE
	[798] = { "UI_Click_Heavy", "clicks" },   -- GS_TITLE_OPTION_OK
	[805] = { "UI_Click_Heavy", "clicks" },   -- GS_LOGIN_CHANGE_REALM_OK
	[865] = { "UI_Click_Heavy", "clicks" },   -- IG_BACKPACK_COIN_OK
	-- cancel: Quit, Logout, Cancel, a quest abandoned or declined
	[854] = { "UI_Cancel", "clicks" },   -- IG_MAINMENU_QUIT
	[853] = { "UI_Cancel", "clicks" },   -- IG_MAINMENU_LOGOUT
	[799] = { "UI_Cancel", "clicks" },   -- GS_TITLE_OPTION_EXIT
	[807] = { "UI_Cancel", "clicks" },   -- GS_LOGIN_CHANGE_REALM_CANCEL
	[39514] = { "UI_Cancel", "clicks" }, -- UI_IG_STORE_CANCEL_BUTTON
	[866] = { "UI_Cancel", "clicks" },   -- IG_BACKPACK_COIN_CANCEL
	[879] = { "UI_Cancel", "clicks" },   -- IG_QUEST_CANCEL
	[846] = { "UI_Cancel", "clicks" },   -- IG_QUEST_LOG_ABANDON_QUEST
	[847] = { "UI_Cancel", "clicks" },
	[892] = { "UI_Cancel", "clicks" },   -- MONEY_FRAME_CLOSE
	-- windows: a page turn to open, a latch to close
	[839] = { "Page_Turn", "windows" },   -- IG_CHARACTER_INFO_OPEN
	[679] = { "Page_Turn", "windows" },
	[840] = { "UI_Cancel", "windows" },   -- IG_CHARACTER_INFO_CLOSE
	[680] = { "UI_Cancel", "windows" },
	[844] = { "Page_Turn", "windows" },   -- IG_QUEST_LOG_OPEN
	[875] = { "Page_Turn", "windows" },   -- IG_QUEST_LIST_OPEN
	[620] = { "Page_Turn", "windows" },
	[845] = { "UI_Cancel", "windows" },   -- IG_QUEST_LOG_CLOSE
	[876] = { "UI_Cancel", "windows" },   -- IG_QUEST_LIST_CLOSE
	[621] = { "UI_Cancel", "windows" },
	[829] = { "Page_Turn", "windows" },   -- IG_SPELLBOOK_OPEN
	[834] = { "Page_Turn", "windows" },   -- IG_ABILITY_OPEN
	[603] = { "Page_Turn", "windows" },
	[830] = { "UI_Cancel", "windows" },   -- IG_SPELLBOOK_CLOSE
	[835] = { "UI_Cancel", "windows" },   -- IG_ABILITY_CLOSE
	[604] = { "UI_Cancel", "windows" },
	[836] = { "Page_Turn", "windows" },   -- IG_ABILITY_PAGE_TURN
	[831] = { "Page_Turn", "windows" },
	[605] = { "Page_Turn", "windows" },
	[850] = { "UI_Click_Heavy", "windows" },   -- IG_MAINMENU_OPEN
	[882] = { "UI_Click_Heavy", "windows" },
	[851] = { "UI_Cancel", "windows" },        -- IG_MAINMENU_CLOSE
	-- the bags: a leather pouch
	[862] = { "Inventory_Pickup", "windows" },   -- IG_BACKPACK_OPEN
	[859] = { "Inventory_Pickup", "windows" },
	[863] = { "Inventory_Drop", "windows" },     -- IG_BACKPACK_CLOSE
	[860] = { "Inventory_Drop", "windows" },
	[8938] = { "Inventory_Pickup", "windows" },  -- KEY_RING_OPEN
	[8939] = { "Inventory_Drop", "windows" },    -- KEY_RING_CLOSE
	-- alerts
	[880] = { "Social_GroupInvite", "social" },   -- IG_PLAYER_INVITE
	[881] = { "Social_GroupInvite", "social" },
	[3081] = { "Social_Whisper", "social" },      -- TELL_MESSAGE
	[8960] = { "DungeonFinder_Ready", "groupFinder" },   -- READY_CHECK
	[139828] = { "DungeonFinder_Ready", "groupFinder" },  -- QUEST_SESSION_READY_CHECK
	[17318] = { "DungeonFinder_Ready", "groupFinder" },   -- the dungeon-ready pop (engine)
	[17317] = { "DungeonFinder_Queue", "groupFinder" },   -- LFG_ROLE_CHECK
	[17341] = { "DungeonFinder_QueueDropped", "groupFinder" },   -- LFG_DENIED
	[17316] = { "UI_Success", "groupFinder" },            -- LFG_REWARDS
	[47615] = { "DungeonFinder_Queue", "groupFinder" },   -- UI_GROUP_FINDER_RECEIVE_APPLICATION
	[8458] = { "DungeonFinder_Queue", "groupFinder" },    -- PVP_ENTER_QUEUE
	[8462] = { "DungeonFinder_Queue", "groupFinder" },
	[8459] = { "DungeonFinder_Ready", "groupFinder" },    -- PVP_THROUGH_QUEUE
	[8463] = { "DungeonFinder_Ready", "groupFinder" },
	[878] = { "UI_Success", "quests" },   -- IG_QUEST_LIST_COMPLETE
	[619] = { "UI_Success", "quests" },
	-- targets (TargetFrame plays these on PLAYER_TARGET_CHANGED)
	[867] = { "UI_TargetSelect", "targets" },   -- IG_CHARACTER_NPC_SELECT
	[871] = { "UI_TargetSelect", "targets" },   -- IG_CREATURE_NEUTRAL_SELECT
	[873] = { "UI_TargetSelect", "targets" },   -- IG_CREATURE_AGGRO_SELECT
	[684] = { "UI_Cancel", "targets" },         -- INTERFACE_SOUND_LOST_TARGET_UNIT
	-- the minimap ping, coins, the spell icon drag
	[3175] = { "Map_Ping", "map" },             -- MAP_PING
	[120] = { "Loot_Coins", "loot" },           -- LOOT_WINDOW_COIN_SOUND
	[838] = { "SpellIcon_Place", "spells" },    -- IG_ABILITY_ICON_DROP
	[689] = { "SpellIcon_Place", "spells" },    -- UI_CURSOR_DROP_OBJECT
	[688] = { "SpellIcon_Drag", "spells" },     -- UI_CURSOR_PICKUP_OBJECT
}

-- file id -> { default replacement, group, the kits playing it }
local FILES = {
	[567407] = { "UI_Click_Light", "clicks", { 80, 83, 111, 687, 792, 793, 794, 795, 796, 797, 798, 799, 805, 806, 807, 808, 811, 814, 815, 816, 817, 826, 827, 828, 842, 843, 856, 857, 858, 861, 905, 906, 1115, 39511, 303824, 306217 } },   -- uchatscrollbutton
	[567481] = { "UI_Click_Heavy", "clicks", { 624, 825, 852, 853, 854, 855, 39514 } },   -- iuiinterfacebuttona
	[567422] = { "UI_Click_Light", "clicks", { 681, 841 } },   -- ucharactersheettab
	[567467] = { "UI_Click_Light", "clicks", { 113, 114, 823, 824 } },   -- uminimapzoom
	[567529] = { "UI_Click_Light", "clicks", { 115, 821 } },   -- uminimapopen
	[567515] = { "UI_Click_Light", "clicks", { 116, 822 } },   -- uminimapclose
	[567459] = { "UI_Cancel", "clicks", { 846, 847 } },   -- igquestfailed
	[567483] = { "UI_Click_Light", "clicks", { 677, 864, 891, 247487, 249509 } },   -- imoneydialogopen
	[567501] = { "UI_Cancel", "clicks", { 678, 865, 866, 892, 249512 } },   -- imoneydialogclose
	[567507] = { "Page_Turn", "windows", { 679, 839 } },   -- ucharactersheetopen
	[567433] = { "UI_Cancel", "windows", { 680, 840 } },   -- ucharactersheetclose
	[567490] = { "UI_Click_Heavy", "windows", { 88, 682, 850, 882, 180332 } },   -- uescapescreenopen
	[567464] = { "UI_Cancel", "windows", { 89, 683, 851 } },   -- uescapescreenclose
	[567504] = { "Page_Turn", "windows", { 620, 844, 875 } },   -- iquestlogopena
	[567508] = { "UI_Cancel", "windows", { 621, 845, 876, 877, 879 } },   -- iquestlogclosea
	[567440] = { "Page_Turn", "windows", { 603, 754, 829, 834, 3190, 3371, 4734 } },   -- iabilitiesopena
	[567496] = { "UI_Cancel", "windows", { 604, 830, 835, 3191, 3372, 4735 } },   -- iabilitiesclosea
	[567472] = { "Page_Turn", "windows", { 605, 831, 836 } },   -- iabilitiesturnpagea
	[567502] = { "Page_Turn", "windows", { 836 } },   -- iabilitiesturnpageb
	[567457] = { "Page_Turn", "windows", { 836 } },   -- iabilitiesturnpagec
	[567461] = { "Inventory_Pickup", "windows", { 117, 616, 685, 859, 862 } },   -- iequipmentcontaineropena
	[567512] = { "Inventory_Drop", "windows", { 617, 686, 860, 863 } },   -- iequipmentcontainerclosea
	[567462] = { "Inventory_Pickup", "windows", { 8938, 281045 } },   -- keyringopen
	[567523] = { "Inventory_Drop", "windows", { 8939 } },   -- keyringclose
	[567451] = { "Social_GroupInvite", "social", { 880, 881 } },   -- iplayerinvitea
	[567421] = { "Social_Whisper", "social", { 3081 } },   -- itellmessage
	[567409] = { "DungeonFinder_Ready", "groupFinder", { 8960 } },   -- readycheck (the classic kit)
	[567478] = { "DungeonFinder_Ready", "groupFinder", { 8960, 139828 } },   -- levelup2: READY_CHECK's file on the modern data (level up itself is levelup.ogg, kit 1440)
	[567465] = { "DungeonFinder_Ready", "groupFinder", { 17318, 293714 } },   -- lfg_dungeonready (engine, on the proposal)
	[567513] = { "DungeonFinder_Queue", "groupFinder", { 17317 } },   -- lfg_rolecheck
	[567420] = { "DungeonFinder_QueueDropped", "groupFinder", { 17341, 137909 } },   -- lfg_denied
	[567514] = { "UI_Success", "groupFinder", { 17316 } },   -- lfg_rewards
	[568587] = { "DungeonFinder_Queue", "groupFinder", { 8458, 8462 } },   -- pvp enter queue
	[568011] = { "DungeonFinder_Ready", "groupFinder", { 8459, 8463, 36609 } },   -- pvp through queue
	[1067667] = { "DungeonFinder_Queue", "groupFinder", { 47615 } },   -- ui_groupfinderreceiveapplication_01
	[567439] = { "UI_Success", "quests", { 619, 878 } },   -- iquestcomplete
	[567415] = { "UI_Error", "errors", {} },   -- error (engine)
	[567453] = { "UI_TargetSelect", "targets", { 101, 867, 869, 871, 873, 206593 } },   -- iselecttarget
	[567520] = { "UI_Cancel", "targets", { 684, 868, 870, 872, 874, 900, 206823 } },   -- ideselecttarget
	[567416] = { "Map_Ping", "map", { 3175 } },   -- mapping
	[567428] = { "Loot_Coins", "loot", { 120, 895, 247487, 249509 } },   -- lootcoinsmall
	[567413] = { "Loot_Coins", "loot", { 287276 } },   -- lootcoinlarge
	[567489] = { "SpellIcon_Drag", "spells", { 688, 832, 837, 902 } },   -- uspelliconpickup (engine, on the drag)
	[567524] = { "SpellIcon_Place", "spells", { 689, 833, 838, 903 } },   -- uspellicondrop
	[569593] = { "Character_LevelUp", "levelUp", { 888, 1440 } },   -- sound/spells/levelup (engine, on the level)
	[567431] = { "Character_LevelUp", "levelUp", {} },   -- interface levelup
	-- the engine's item pick-up and put-down sounds (sound/interface/pickup/*),
	-- one file per material, and the loot pick-up; replaced on the cursor,
	-- loot, equipment and merchant events, never seen by PlaySound
	[567517] = { "Inventory_Drop", "inventory", { 1279 } },   -- uilootpickupitem
	[567542] = { "Inventory_Pickup", "inventory", { 1193 } },
	[567543] = { "Inventory_Pickup", "inventory", { 1183 } },
	[567544] = { "Inventory_Pickup", "inventory", { 1196 } },
	[567545] = { "Inventory_Pickup", "inventory", { 1184 } },
	[567546] = { "Inventory_Pickup", "inventory", { 1186 } },
	[567547] = { "Inventory_Drop", "inventory", { 1208, 2984 } },
	[567548] = { "Inventory_Drop", "inventory", { 1201, 281250 } },
	[567549] = { "Inventory_Drop", "inventory", { 1214 } },
	[567550] = { "Inventory_Pickup", "inventory", { 1188 } },
	[567551] = { "Inventory_Drop", "inventory", { 1210 } },
	[567552] = { "Inventory_Pickup", "inventory", { 1187 } },
	[567553] = { "Inventory_Drop", "inventory", { 1205 } },
	[567554] = { "Inventory_Pickup", "inventory", { 1190 } },
	[567555] = { "Inventory_Pickup", "inventory", { 1197, 281465 } },
	[567556] = { "Inventory_Drop", "inventory", { 1209, 281258, 287934 } },
	[567557] = { "Inventory_Drop", "inventory", { 1215, 3083 } },
	[567558] = { "Inventory_Pickup", "inventory", { 1199 } },
	[567559] = { "Inventory_Drop", "inventory", { 1200 } },
	[567560] = { "Inventory_Pickup", "inventory", { 1191 } },
	[567561] = { "Inventory_Pickup", "inventory", { 1195 } },
	[567562] = { "Inventory_Pickup", "inventory", { 1192 } },
	[567563] = { "Inventory_Drop", "inventory", { 1213 } },
	[567564] = { "Inventory_Pickup", "inventory", { 1194 } },
	[567565] = { "Inventory_Pickup", "inventory", { 1185, 5437 } },
	[567566] = { "Inventory_Drop", "inventory", { 1217 } },
	[567567] = { "Inventory_Drop", "inventory", { 1216 } },
	[567568] = { "Inventory_Pickup", "inventory", { 1221, 287859, 287860, 287861, 287863, 287864, 287866 } },
	[567569] = { "Inventory_Drop", "inventory", { 1207 } },
	[567570] = { "Inventory_Drop", "inventory", { 1203 } },
	[567571] = { "Inventory_Drop", "inventory", { 1202, 5438 } },
	[567572] = { "Inventory_Drop", "inventory", { 1206 } },
	[567573] = { "Inventory_Pickup", "inventory", { 1189 } },
	[567574] = { "Inventory_Drop", "inventory", { 1204, 3084, 287250 } },
	[567575] = { "Inventory_Drop", "inventory", { 1211 } },
	[567576] = { "Inventory_Pickup", "inventory", { 1198 } },
	[567577] = { "Inventory_Drop", "inventory", { 1212 } },
}

-- kit -> file, from FILES
local KIT_FILE = {}
for file, entry in pairs(FILES) do
	for _, kit in ipairs(entry[3]) do
		KIT_FILE[kit] = file
	end
end

--------------------------------------------------------------------------------
-- Playing, logging
--------------------------------------------------------------------------------

local lastPlayed = {}
local events = {}       -- the last sound events, for /sfxdump
local EVENTS_MAX = 60
local live = false      -- /sfx log: print each event as it happens

local kitNames
local function KitName(kit)
	if not kitNames then
		kitNames = {}
		for name, id in pairs(SOUNDKIT or {}) do
			kitNames[id] = name
		end
	end
	return kitNames[kit] or "?"
end

local function Note(fmt, ...)
	local ok, line = pcall(string.format, fmt, ...)
	if not ok then
		line = fmt
	end
	line = string.format("%.1f %s", GetTime() % 1000, line)
	events[#events + 1] = line
	if #events > EVENTS_MAX then
		table.remove(events, 1)
	end
	if live then
		MelloUI:Print("SFX %s", line)
	end
end

local function GroupOn(group)
	return M.isEnabled and M.db and M.db[group] and true or false
end

-- The named file, once per its gap; returns whether it started.
local function Play(name, why)
	local gap = SOUNDS[name]
	if not gap then
		return false
	end
	local now = GetTime()
	if lastPlayed[name] and now - lastPlayed[name] < gap then
		Note("%s skipped (%.2fs after the last) %s", name, now - lastPlayed[name], why or "")
		return false
	end
	local ok, willPlay = pcall(PlaySoundFile, SOUND_PATH .. name .. ".ogg", (M.db and M.db.channel) or "SFX")
	if ok and willPlay then
		lastPlayed[name] = now
		Note("%s played %s", name, why or "")
		return true
	end
	Note("%s FAILED to play (%s) %s", name, ok and "file missing?" or tostring(willPlay), why or "")
	return false
end

-- The Preview tab's Play: the file as is, whatever is on or off.
function M:Preview(name)
	local ok, willPlay = pcall(PlaySoundFile, SOUND_PATH .. name .. ".ogg", (self.db and self.db.channel) or "SFX")
	if not (ok and willPlay) then
		MelloUI:Print("%s did not play (a new sound file needs a full client restart).", name)
	end
end

--------------------------------------------------------------------------------
-- Muting the game's files
--------------------------------------------------------------------------------

local muted = {}   -- file id -> true while muted by this module

local function CanMute()
	return type(MuteSoundFile) == "function" and type(UnmuteSoundFile) == "function"
end

local function ApplyMutes()
	if not CanMute() then
		return
	end
	for file, entry in pairs(FILES) do
		local want = GroupOn(entry[2])
		if want and not muted[file] then
			if pcall(MuteSoundFile, file) then
				muted[file] = true
			end
		elseif not want and muted[file] then
			pcall(UnmuteSoundFile, file)
			muted[file] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- PlaySound from the game's Lua
--------------------------------------------------------------------------------

local hooked = false

local function OnPlaySound(kit)
	if type(kit) ~= "number" then
		return
	end
	local entry = KITS[kit]
	local file = KIT_FILE[kit]
	if not entry and file then
		entry = FILES[file]
	end
	if not entry then
		if live then
			Note("kit %d %s: not ours, the game's sound", kit, KitName(kit))
		end
		return
	end
	if not GroupOn(entry[2]) then
		Note("kit %d %s: group %s off, the game's sound", kit, KitName(kit), entry[2])
		return
	end
	if file and not muted[file] then
		Note("kit %d %s: file %d not muted (MuteSoundFile missing?), the game's sound", kit, KitName(kit), file)
		return
	end
	Play(entry[1], string.format("for kit %d %s", kit, KitName(kit)))
end

local function HookPlaySound()
	if hooked then
		return
	end
	hooked = true
	hooksecurefunc("PlaySound", OnPlaySound)
end

--------------------------------------------------------------------------------
-- The engine's sounds: the events they go with
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

local CURSOR_ITEM = Enum and Enum.UICursorType and Enum.UICursorType.Item or 1
-- cursor types that are not a spell-like drag (an item, money, a merchant or
-- guild bank item)
local CURSOR_PLAIN = {}
do
	local types = Enum and Enum.UICursorType or {}
	for _, key in ipairs({ "Default", "Item", "Money", "Merchant", "GuildBank" }) do
		if types[key] then
			CURSOR_PLAIN[types[key]] = true
		end
	end
	CURSOR_PLAIN[0] = true
end
local holdingItem = false
local holdingSpell = false
local pickedFromPaperDoll = 0   -- GetTime of a pick-up from an equipment slot
local enteredWorld = 0

local function ItemQuality(link, itemID)
	local quality
	if C_Item and C_Item.GetItemQualityByID and itemID then
		local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
		if ok and type(q) == "number" then
			quality = q
		end
	end
	if not quality and link then
		local info = C_Item and C_Item.GetItemInfo or GetItemInfo
		if info then
			local ok, _, _, q = pcall(info, link)
			if ok and type(q) == "number" then
				quality = q
			end
		end
	end
	return quality or 0
end

-- The frame under the mouse, or nil (a forbidden one counts as none).
local function MouseFrame()
	local f
	if GetMouseFoci then
		local ok, list = pcall(GetMouseFoci)
		f = ok and type(list) == "table" and list[1] or nil
	elseif GetMouseFocus then
		local ok, focus = pcall(GetMouseFocus)
		f = ok and focus or nil
	end
	if f and f.IsForbidden and f:IsForbidden() then
		return nil
	end
	return f
end

local function FrameName(f)
	if not f or not f.GetName then
		return nil
	end
	local ok, name = pcall(f.GetName, f)
	return ok and type(name) == "string" and name or nil
end

local function OnEquipmentSlot(f)
	local name = FrameName(f)
	return name and name:match("^Character%a+Slot$") and true or false
end

local function OnMerchant(f)
	while f do
		if f == MerchantFrame then
			return true
		end
		local ok, parent = pcall(f.GetParent, f)
		f = ok and parent or nil
	end
	return false
end

local function CursorChanged(isDefault, newType, oldType)
	local wasItem = holdingItem
	local isItem = newType == CURSOR_ITEM
	holdingItem = isItem
	-- a spell, macro, ability, pet action, mount... on the cursor
	local wasSpell = holdingSpell
	local isSpell = not isDefault and newType ~= nil and not CURSOR_PLAIN[newType] and true or false
	holdingSpell = isSpell
	if GroupOn("spells") then
		if isSpell and not wasSpell then
			Play("SpellIcon_Drag", "cursor type " .. tostring(newType))
		elseif wasSpell and not isSpell then
			Play("SpellIcon_Place", "cursor cleared")
		end
	end
	if not GroupOn("inventory") then
		return
	end
	if isItem and not wasItem then
		local from = MouseFrame()
		if OnEquipmentSlot(from) then
			pickedFromPaperDoll = GetTime()
		end
		local itemID, link
		if GetCursorInfo then
			local ok, kind, id, lnk = pcall(GetCursorInfo)
			if ok and kind == "item" then
				itemID, link = id, lnk
			end
		end
		if ItemQuality(link, itemID) >= 3 then
			Play("Rare_Item_Interaction", "cursor picked up a rare item")
		else
			Play("Inventory_Pickup", "cursor picked up an item")
		end
	elseif isItem and wasItem then
		Play("Inventory_Move", "cursor swapped items")
	elseif wasItem and not isItem then
		local onto = MouseFrame()
		if OnEquipmentSlot(onto) then
			Note("Inventory_Drop skipped: dropped on an equipment slot (Equipment plays)")
		elseif OnMerchant(onto) then
			Note("Inventory_Drop skipped: dropped on the merchant (Vendor plays)")
		else
			Play("Inventory_Drop", "cursor put an item down")
		end
	end
end

local lootPatterns
local function LootPatterns()
	if lootPatterns then
		return lootPatterns
	end
	lootPatterns = {}
	for _, global in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
		local text = _G[global]
		if type(text) == "string" then
			local pattern = "^" .. text:gsub("%%", "%%%%"):gsub("%%%%s", "(.-)"):gsub("%%%%d", "%%d+") .. "$"
			lootPatterns[#lootPatterns + 1] = pattern
		end
	end
	return lootPatterns
end

local function Looted(message)
	if type(message) ~= "string" or not GroupOn("inventory") then
		return
	end
	local link
	for _, pattern in ipairs(LootPatterns()) do
		link = message:match(pattern)
		if link then
			break
		end
	end
	if not link then
		return
	end
	local itemID = tonumber(link:match("item:(%d+)"))
	if ItemQuality(link, itemID) >= 3 then
		Play("Rare_Item_Interaction", "looted a rare item")
	else
		Play("Inventory_Drop", "looted an item")
	end
end

local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }
local ACCESSORY_SLOTS = { [2] = true, [11] = true, [12] = true, [13] = true, [14] = true }

local function EquipmentChanged(slot, hasCurrent)
	if not GroupOn("equipment") or GetTime() - enteredWorld < 3 then
		return
	end
	if hasCurrent then
		if WEAPON_SLOTS[slot] then
			Play("Equip_Weapon", "slot " .. tostring(slot))
		elseif ACCESSORY_SLOTS[slot] then
			Play("Equip_Accessory", "slot " .. tostring(slot))
		else
			Play("Equip_Armor", "slot " .. tostring(slot))
		end
	elseif GetTime() - pickedFromPaperDoll < 1 then
		Note("Unequip_Armor skipped: the item was dragged off (Inventory played)")
	else
		Play("Unequip_Armor", "slot " .. tostring(slot))
	end
end

local lastQueued = false
local LFG_CATEGORIES = 6

local function Queued()
	if not GetLFGMode then
		return false
	end
	for category = 1, LFG_CATEGORIES do
		local ok, mode = pcall(GetLFGMode, category)
		if ok and (mode == "queued" or mode == "proposal" or mode == "rolecheck" or mode == "suspended") then
			return true
		end
	end
	return false
end

local function QueueChanged()
	if not GroupOn("groupFinder") then
		return
	end
	local queued = Queued()
	if queued and not lastQueued then
		Play("DungeonFinder_Queue", "queue entered")
	elseif lastQueued and not queued then
		Play("DungeonFinder_QueueDropped", "queue left")
	end
	lastQueued = queued
end

local function ApplicationChanged(_, newStatus)
	if not GroupOn("groupFinder") then
		return
	end
	if newStatus == "applied" then
		Play("DungeonFinder_Queue", "applied to a listing")
	elseif newStatus == "invited" then
		Play("DungeonFinder_Ready", "invited from a listing")
	elseif newStatus == "declined" or newStatus == "cancelled" or newStatus == "timedout" or newStatus == "failed" or newStatus == "declined_full" or newStatus == "declined_delisted" then
		Play("DungeonFinder_QueueDropped", "application " .. tostring(newStatus))
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "CURSOR_CHANGED" then
		CursorChanged(...)
	elseif event == "CHAT_MSG_LOOT" then
		Looted((...))
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		EquipmentChanged(...)
	elseif event == "QUEST_TURNED_IN" then
		if GroupOn("quests") then
			Play("UI_Success", "quest turned in")
		end
	elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
		if GroupOn("crafting") then
			Play("Craft_Item", "item crafted")
		end
	elseif event == "UI_ERROR_MESSAGE" then
		if GroupOn("errors") then
			Play("UI_Error", "error message")
		end
	elseif event == "CHAT_MSG_MONEY" then
		if GroupOn("loot") then
			Play("Loot_Coins", "money looted")
		end
	elseif event == "PLAYER_LEVEL_UP" then
		if GroupOn("levelUp") then
			Play("Character_LevelUp", "level up")
		end
	elseif event == "LFG_PROPOSAL_SHOW" then
		if GroupOn("groupFinder") then
			Play("DungeonFinder_Ready", "group ready")
		end
		lastQueued = true
	elseif event == "LFG_PROPOSAL_FAILED" then
		if GroupOn("groupFinder") then
			Play("DungeonFinder_QueueDropped", "the proposal failed")
		end
	elseif event == "LFG_UPDATE" or event == "LFG_QUEUE_STATUS_UPDATE" then
		QueueChanged()
	elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
		ApplicationChanged(...)
	elseif event == "PLAYER_ENTERING_WORLD" then
		enteredWorld = GetTime()
		lastQueued = Queued()
	end
end)

local EVENTS = {
	"CURSOR_CHANGED", "CHAT_MSG_LOOT", "PLAYER_EQUIPMENT_CHANGED", "QUEST_TURNED_IN",
	"TRADE_SKILL_ITEM_CRAFTED_RESULT", "UI_ERROR_MESSAGE", "CHAT_MSG_MONEY", "PLAYER_LEVEL_UP",
	"LFG_PROPOSAL_SHOW", "LFG_PROPOSAL_FAILED", "LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "LFG_LIST_APPLICATION_STATUS_UPDATED",
	"PLAYER_ENTERING_WORLD",
}

-- The merchant: buying and selling are engine sounds (the item's pick-up
-- and put-down files, muted with Inventory); the functions are hooked once.
local merchantHooked = false

local function HookMerchant()
	if merchantHooked then
		return
	end
	merchantHooked = true
	local function Bought()
		if GroupOn("vendor") then
			Play("Vendor_Buy", "bought")
		end
	end
	local function Sold()
		if GroupOn("vendor") then
			Play("Vendor_Sell", "sold")
		end
	end
	if type(BuyMerchantItem) == "function" then
		hooksecurefunc("BuyMerchantItem", Bought)
	end
	if type(BuybackItem) == "function" then
		hooksecurefunc("BuybackItem", Bought)
	end
	if type(SellCursorItem) == "function" then
		hooksecurefunc("SellCursorItem", Sold)
	end
	if C_Container and type(C_Container.UseContainerItem) == "function" then
		hooksecurefunc(C_Container, "UseContainerItem", function()
			-- with the merchant open a bag item used is a bag item sold
			if MerchantFrame and MerchantFrame:IsShown() then
				Sold()
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- The scroll wheel: a notch per step. The game has no wheel sound, so there
-- is nothing to mute and no kit to hook: every frame with an OnMouseWheel
-- script gets a post-hook (EnumerateFrames, once at enable and every ten
-- seconds for frames made since; a hook is a one-time thing per frame).
--------------------------------------------------------------------------------

local wheelSeen = setmetatable({}, { __mode = "k" })
local wheelTicker = nil
local wheelHooks = 0

local function OnWheel()
	if GroupOn("scrollWheel") then
		Play("Scroll_Wheel", "wheel")
	end
end

local function HookWheels()
	local f = EnumerateFrames()
	while f do
		if not wheelSeen[f] then
			wheelSeen[f] = true
			local forbidden = f.IsForbidden and f:IsForbidden()
			if not forbidden then
				local ok, script = pcall(f.GetScript, f, "OnMouseWheel")
				if ok and script and pcall(f.HookScript, f, "OnMouseWheel", OnWheel) then
					wheelHooks = wheelHooks + 1
				end
			end
		end
		f = EnumerateFrames(f)
	end
end

local function ApplyWheel()
	if GroupOn("scrollWheel") then
		HookWheels()
		if not wheelTicker then
			wheelTicker = C_Timer.NewTicker(10, HookWheels)
		end
	elseif wheelTicker then
		wheelTicker:Cancel()
		wheelTicker = nil
	end
end

--------------------------------------------------------------------------------
-- Hover ticks: the frame under the mouse, polled
--------------------------------------------------------------------------------

local hoverFrame = CreateFrame("Frame")
local hoverLast = nil
local hoverElapsed = 0

local function HoverTick(_, elapsed)
	hoverElapsed = hoverElapsed + elapsed
	if hoverElapsed < 0.05 then
		return
	end
	hoverElapsed = 0
	local f = MouseFrame()
	if f == hoverLast then
		return
	end
	hoverLast = f
	if not f or f == WorldFrame or f == UIParent then
		return
	end
	local ok, isButton = pcall(f.IsObjectType, f, "Button")
	if not (ok and isButton) then
		return
	end
	local okE, enabled = pcall(f.IsEnabled, f)
	if okE and enabled == false then
		return
	end
	if IsMouseButtonDown and IsMouseButtonDown() then
		return
	end
	Play("UI_Hover", FrameName(f) or "a button")
end

local function ApplyHover()
	if GroupOn("hover") then
		hoverFrame:SetScript("OnUpdate", HoverTick)
	else
		hoverFrame:SetScript("OnUpdate", nil)
		hoverLast = nil
	end
end

--------------------------------------------------------------------------------
-- The configurator's own clicks (Core/Config.lua asks here first)
--------------------------------------------------------------------------------

local CONFIG_SOUNDS = { check_on = "UI_Click_Light", check_off = "UI_Click_Light", tab = "UI_Click_Light", page = "Page_Turn" }

function MelloUI:PlayCustomUISound(kind)
	if not GroupOn("clicks") then
		return false
	end
	local name = CONFIG_SOUNDS[kind]
	return name and Play(name, "configurator " .. kind) or false
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	HookPlaySound()
	HookMerchant()
	for _, event in ipairs(EVENTS) do
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	enteredWorld = GetTime()
	lastQueued = Queued()
	ApplyMutes()
	ApplyHover()
	ApplyWheel()
	if not CanMute() then
		MelloUI:Print("Custom Sounds: this client has no MuteSoundFile, the game's own sounds cannot be silenced; the custom ones play on top of them.")
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	ApplyMutes()
	ApplyHover()
	ApplyWheel()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyMutes()
	ApplyHover()
	ApplyWheel()
end

--------------------------------------------------------------------------------
-- /sfx, /sfxdump
--------------------------------------------------------------------------------

local function Status()
	local count = 0
	for _ in pairs(muted) do
		count = count + 1
	end
	MelloUI:Print("Custom Sounds: module %s, MuteSoundFile %s, %d files muted, channel %s, hook %s, %d wheel hooks, live log %s",
		M.isEnabled and "on" or "off", CanMute() and "present" or "MISSING", count, (M.db and M.db.channel) or "SFX",
		hooked and "installed" or "not installed", wheelHooks, live and "on" or "off")
	local groups = {}
	for _, opt in ipairs(options) do
		if opt.type == "toggle" then
			groups[#groups + 1] = string.format("%s=%s", opt.key, GroupOn(opt.key) and "on" or "off")
		end
	end
	MelloUI:Print("Groups: %s", table.concat(groups, " "))
end

SLASH_MELLOSFX1 = "/sfx"
SlashCmdList.MELLOSFX = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local word, rest = msg:match("^(%S+)%s*(.*)$")
	if word == "play" and rest ~= "" then
		local name = rest
		if not SOUNDS[name] then
			for known in pairs(SOUNDS) do
				if known:lower() == name:lower() then
					name = known
				end
			end
		end
		if SOUNDS[name] then
			lastPlayed[name] = nil
			local ok, willPlay = pcall(PlaySoundFile, SOUND_PATH .. name .. ".ogg", (M.db and M.db.channel) or "SFX")
			MelloUI:Print("%s: %s", name, (ok and willPlay) and "playing" or "did not play (a new file needs a full client restart)")
		else
			MelloUI:Print("No sound '%s'. /sfx list names them.", rest)
		end
	elseif word == "list" then
		local names = {}
		for name in pairs(SOUNDS) do
			names[#names + 1] = name
		end
		table.sort(names)
		MelloUI:Print("Sounds: %s", table.concat(names, ", "))
	elseif word == "log" then
		live = not live
		MelloUI:Print("Custom Sounds live log %s%s", live and "on" or "off", live and ": every kit the game plays is printed with what was done" or "")
	elseif word == "kit" and tonumber(rest) then
		local kit = tonumber(rest)
		local entry = KITS[kit] or (KIT_FILE[kit] and FILES[KIT_FILE[kit]])
		MelloUI:Print("kit %d %s: file %s, replacement %s (group %s)", kit, KitName(kit), tostring(KIT_FILE[kit]),
			entry and entry[1] or "none", entry and entry[2] or "-")
	else
		Status()
		MelloUI:Print("/sfx play <name>, /sfx list, /sfx log (print each sound the game plays and what replaced it), /sfx kit <id>, /sfxdump")
	end
end

SLASH_MELLOSFXDUMP1 = "/sfxdump"
SlashCmdList.MELLOSFXDUMP = function()
	MelloUI:ClearLog()
	Status()
	MelloUI:Print("Last %d sound events (time within the hour, newest last):", #events)
	for _, line in ipairs(events) do
		MelloUI:Print("  %s", line)
	end
	MelloUI:ShowLog("sfxdump")
end
