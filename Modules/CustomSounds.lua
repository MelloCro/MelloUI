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
local Perf = MelloUI.Perf:Scope("CustomSounds")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Secret = MelloUI.Safe.IsSecret

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
	  desc = "A page turn when the character sheet, spell book, quest log or main menu opens, a latch when they close; the spell book's page turns; a quest giver's list and Decline; the bags as a leather pouch opening and closing." },
	{ type = "toggle", key = "inventory", name = "Inventory",
	  desc = "An item picked up, moved between slots, put down or looted; a rare or better item has its own sound. Silences the game's own pick-up and put-down sounds (the Equipment and Vendor sounds rely on that, and play only while this is on)." },
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
	  desc = "A muted knock for the game's red error messages (\"You can't do that yet\"), at most one every half second; none for a message Error Messages hides." },
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
-- its family is on; while the module is off the buttons sleep, as every row
-- of a switched-off module (Core/Config.lua).
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
	icon = "Interface\\Icons\\INV_Misc_Bell_01",
	flavour = "Iron, leather, parchment and stone. Every click, page, pouch and buckle of the interface, re-recorded.",
	group = "Chat and sound", navOrder = 3,
	role = "look",   -- the sound reskin: it comes on with the reskin (UI Modifications' ReskinOn)
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
	-- (a kit takes its file's group, whose switch mutes that file: the quest
	-- giver's list row and Decline play the quest log's close, Windows')
	[877] = { "UI_Click_Light", "windows" },   -- IG_QUEST_LIST_SELECT
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
	[879] = { "UI_Cancel", "windows" },  -- IG_QUEST_CANCEL (its file's group, as 877)
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
	-- (kits 247487 and 249509 play this file too, or the money dialog's,
	-- 567483: listed there only, so one group owns each kit)
	[567428] = { "Loot_Coins", "loot", { 120, 895 } },   -- lootcoinsmall
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
--
-- Nothing on a sound's way makes garbage (user, 2026-09-24: "clean up the
-- spikes"). Each file's path is made once. The log keeps its last events as
-- they came, the format and its values in slots used round and round, and
-- writes them out as lines only when someone reads them (/sfxdump, /sfx log):
-- before, every sound wrote two or three strings for a log hardly ever read,
-- and the first kit the game played turned the whole SOUNDKIT list round into
-- a table of names (a few thousand entries at once) for one of those lines.
-- The kit names are now looked up only when a line is written.
--------------------------------------------------------------------------------

-- each file's path, made once, and when it last played (false: not yet)
local PATHS = {}
local lastPlayed = {}
-- How long the game's own PlaySoundFile took, per file: its first call, its
-- slowest and how many (/sfx). The one-off 8-58 ms calls of the 2026-09-24
-- /melloperf recording (money looted, the first error, two kits) were the
-- first play of a file each, as far as can be told outside the game: the Lua
-- around it takes microseconds, the files are 5-31 KB and decode in under
-- 3 ms. This shows the game's own share.
local calls, firstMs, slowestMs = {}, {}, {}
for name in pairs(SOUNDS) do
	PATHS[name] = SOUND_PATH .. name .. ".ogg"
	lastPlayed[name] = false
	calls[name], firstMs[name], slowestMs[name] = 0, 0, 0
end

local EVENTS_MAX = 60
-- the last sound events, for /sfxdump: { time, format, how many values, up
-- to five values }, each slot made once and then reused
local notes = {}
local noteNext = 1      -- the slot the next event goes into
local noteCount = 0
local live = false      -- /sfx log: print each event as it happens

-- stands among an event's values for the name of the kit just before it
local KIT_NAME = {}

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

-- An event as the line it always was: its values into its format, the time
-- in front.
local lineValues = {}
local function NoteLine(slot)
	local n = math.min(slot[3], 5)
	for i = 1, n do
		local v = slot[i + 3]
		if v == KIT_NAME then
			v = KitName(slot[i + 2])
		elseif type(v) ~= "string" and type(v) ~= "number" then
			v = tostring(v)
		end
		lineValues[i] = v
	end
	local ok, line = pcall(string.format, slot[2], unpack(lineValues, 1, n))
	if not ok then
		line = slot[2]
	end
	return string.format("%.1f %s", slot[1] % 1000, line)
end

local function Note(fmt, ...)
	local slot = notes[noteNext]
	if not slot then
		slot = { 0, "", 0, false, false, false, false, false }
		notes[noteNext] = slot
	end
	slot[1], slot[2], slot[3] = GetTime(), fmt, select("#", ...)
	slot[4], slot[5], slot[6], slot[7], slot[8] = ...
	noteNext = noteNext % EVENTS_MAX + 1
	if noteCount < EVENTS_MAX then
		noteCount = noteCount + 1
	end
	if live then
		MelloUI:Print("SFX %s", NoteLine(slot))
	end
end

local function GroupOn(group)
	return M.isEnabled and M.db and M.db[group] and true or false
end

-- an event's format with the reason joined on, made once for each pair
local joined = {}
local function Joined(head, why)
	local byWhy = joined[head]
	if not byWhy then
		byWhy = {}
		joined[head] = byWhy
	end
	local fmt = byWhy[why]
	if not fmt then
		fmt = head .. why
		byWhy[why] = fmt
	end
	return fmt
end

-- The game's PlaySoundFile for the named file, timed.
local function PlayFile(name, channel)
	local t0 = debugprofilestop()
	local ok, willPlay = pcall(PlaySoundFile, PATHS[name] or (SOUND_PATH .. name .. ".ogg"), channel)
	local ms = debugprofilestop() - t0
	local n = calls[name]
	if n then
		if n == 0 then
			firstMs[name] = ms
		end
		calls[name] = n + 1
		if ms > slowestMs[name] then
			slowestMs[name] = ms
		end
	end
	return ok, willPlay
end

local PLAYED, SKIPPED, FAILED = "%s played ", "%s skipped (%.2fs after the last) ", "%s FAILED to play (%s) "

-- The named file, once per its gap; returns whether it started. `why` says
-- what set it off: a format for `a` and `b`, filled in only when the log is
-- read.
local function Play(name, why, a, b)
	local gap = SOUNDS[name]
	if not gap then
		return false
	end
	why = why or ""
	local now = GetTime()
	local last = lastPlayed[name]
	if last and now - last < gap then
		Note(Joined(SKIPPED, why), name, now - last, a, b)
		return false
	end
	local ok, willPlay = PlayFile(name, (M.db and M.db.channel) or "SFX")
	if ok and willPlay then
		lastPlayed[name] = now
		Note(Joined(PLAYED, why), name, a, b)
		return true
	end
	Note(Joined(FAILED, why), name, ok and "file missing?" or tostring(willPlay), a, b)
	return false
end

-- The Preview tab's Play: the file as is, whichever families are on or off
-- (the module itself is on: its buttons sleep while it is off).
function M:Preview(name)
	local ok, willPlay = PlayFile(name, (self.db and self.db.channel) or "SFX")
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
			Note("kit %d %s: not ours, the game's sound", kit, KIT_NAME)
		end
		return
	end
	if not GroupOn(entry[2]) then
		Note("kit %d %s: group %s off, the game's sound", kit, KIT_NAME, entry[2])
		return
	end
	if file and not muted[file] then
		Note("kit %d %s: file %d not muted (MuteSoundFile missing?), the game's sound", kit, KIT_NAME, file)
		return
	end
	Play(entry[1], "for kit %d %s", kit, KIT_NAME)
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
local putDownAt = 0             -- GetTime an item last left the cursor
local enteredWorld = 0

-- Equipment and Vendor sit under Inventory (their rows grey with it): each
-- plays only while Inventory is on too, whose mutes they rely on
local function ChildOn(group)
	return GroupOn("inventory") and GroupOn(group)
end

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
	if wasItem and not isItem then
		putDownAt = GetTime()
	end
	-- a spell, macro, ability, pet action, mount... on the cursor
	local wasSpell = holdingSpell
	local isSpell = not isDefault and newType ~= nil and not CURSOR_PLAIN[newType] and true or false
	holdingSpell = isSpell
	if GroupOn("spells") then
		if isSpell and not wasSpell then
			Play("SpellIcon_Drag", "cursor type %s", newType)
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
		-- (the drop is left to Equipment or Vendor only while that one is on;
		-- off, the plain drop plays, as anywhere else)
		local onto = MouseFrame()
		if GroupOn("equipment") and OnEquipmentSlot(onto) then
			Note("Inventory_Drop skipped: dropped on an equipment slot (Equipment plays)")
		elseif GroupOn("vendor") and OnMerchant(onto) then
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
	if not ChildOn("equipment") or GetTime() - enteredWorld < 3 then
		return
	end
	if hasCurrent then
		if WEAPON_SLOTS[slot] then
			Play("Equip_Weapon", "slot %s", slot)
		elseif ACCESSORY_SLOTS[slot] then
			Play("Equip_Accessory", "slot %s", slot)
		else
			Play("Equip_Armor", "slot %s", slot)
		end
	elseif GetTime() - pickedFromPaperDoll < 1 then
		Note("Unequip_Armor skipped: the item was dragged off (Inventory played)")
	else
		Play("Unequip_Armor", "slot %s", slot)
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
		Play("DungeonFinder_QueueDropped", "application %s", newStatus)
	end
end

-- An error Error Messages hides never reaches the screen: no knock for it
-- (its own test: a secret text is never hidden there, so it knocks)
local function ErrorHidden(messageType, message)
	local filter = MelloUI:GetModule("ErrorFilter")
	return type(filter) == "table" and type(filter.Hides) == "function" and filter:Hides(messageType, message) or false
end

Perf.SetScript(eventFrame, "OnEvent", function(_, event, ...)
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
		if GroupOn("errors") and not ErrorHidden(...) then
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
-- A drag-sell (an item dropped on the merchant's window, or on one of its
-- goods) goes through PickupMerchantItem with the item on the cursor: a sale
-- when the cursor held an item as it was called (still held, should the
-- cursor's event come after the call, or put down in this same frame, should
-- it come during it); with an empty cursor it picks a good up to buy.
local merchantHooked = false

local function HookMerchant()
	if merchantHooked then
		return
	end
	merchantHooked = true
	local function Bought()
		-- (Restock's Buy sends several purchases: one buy sound for all of it)
		local restock = MelloUI.Restock
		if restock and restock.buyingQuiet then
			return
		end
		if ChildOn("vendor") then
			Play("Vendor_Buy", "bought")
		end
	end
	local function Sold()
		if ChildOn("vendor") then
			Play("Vendor_Sell", "sold")
		end
	end
	if type(_G.PickupMerchantItem) == "function" then
		hooksecurefunc("PickupMerchantItem", function()
			if holdingItem or putDownAt == GetTime() then
				Sold()
			end
		end)
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
-- is nothing to mute and no kit to hook: a frame with an OnMouseWheel script
-- gets a post-hook (a hook is a one-time thing per frame). Nothing at login
-- and no poller (0.19.4; before, a walk over every frame of the interface at
-- enable and another look every ten seconds, against the login rule): the
-- frames are found where the mouse goes, at the moments the game tells --
--   * the mouse leaving the world for the interface (the world frame's
--     OnLeave, the hook the hover ticks use too), looked at on the next frame;
--   * a click on the interface (GLOBAL_MOUSE_DOWN; over the world nothing is
--     asked);
--   * each new frame the hover ticks find under the mouse, while they run.
-- A look hooks the frame under the mouse and its parents, then walks the
-- window they belong to (the frame just under UIParent), every frame in it,
-- so its other lists and panes sound too before the mouse reaches them; a
-- window is walked again only WALK_AGAIN seconds after its last walk (pages
-- made since). A walk is spread over frames, a millisecond at a time (far
-- from the client's 1000 ms per-addon burst), on a stack used again and
-- again, the children handed over as values (no list made per frame). Only
-- the frames given the hook and the windows walked are remembered, both
-- weakly (user, 2026-09-24: "clean up the spikes").
--------------------------------------------------------------------------------

local wheelHooked = setmetatable({}, { __mode = "k" })   -- the frames given the hook
local wheelWalked = setmetatable({}, { __mode = "k" })   -- window -> GetTime of its last walk
local wheelHooks = 0
local WALK_BUDGET = 1       -- ms a walk may take per frame
local WALK_CHECK = 32       -- frames looked at between two looks at the clock
local WALK_AGAIN = 10       -- seconds before a window is walked again
local WHEEL_UP = 40         -- parents looked at above the frame under the mouse, at most
local walkStack = {}        -- the frames still to look at, the last on top
local walkTop = 0
local wheelWalking = false
local wheelLookQueued = false
local wheelWalker = CreateFrame("Frame")

local function OnWheel()
	if GroupOn("scrollWheel") then
		Play("Scroll_Wheel", "wheel")
	end
end

local function HookWheel(f)
	local forbidden = f.IsForbidden and f:IsForbidden()
	if not forbidden then
		local ok, script = pcall(f.GetScript, f, "OnMouseWheel")
		if ok and script and pcall(f.HookScript, f, "OnMouseWheel", OnWheel) then
			wheelHooked[f] = true
			wheelHooks = wheelHooks + 1
		end
	end
end

-- a frame's children onto the stack
local function PushChildren(...)
	for i = 1, select("#", ...) do
		walkTop = walkTop + 1
		walkStack[walkTop] = (select(i, ...))
	end
end

-- One stretch of the walk, up to the budget; true once the stack is empty.
local function WalkStep()
	local stop = debugprofilestop() + WALK_BUDGET
	local count = 0
	while walkTop > 0 do
		local f = walkStack[walkTop]
		walkStack[walkTop] = nil
		walkTop = walkTop - 1
		if not (f.IsForbidden and f:IsForbidden()) then
			if not wheelHooked[f] then
				HookWheel(f)
			end
			PushChildren(f:GetChildren())
		end
		count = count + 1
		if count >= WALK_CHECK then
			count = 0
			if debugprofilestop() > stop then
				return false
			end
		end
	end
	return true
end

-- the walk under way given up (a frame that refused, or the wheel off); its
-- window is walked again at a later look
local function DropWalk()
	for i = walkTop, 1, -1 do
		walkStack[i] = nil
	end
	walkTop = 0
	if wheelWalking then
		wheelWalking = false
		Perf.SetScript(wheelWalker, "OnUpdate", nil)
	end
end

local function Walking()
	local ok, done = pcall(WalkStep)
	if not ok then
		DropWalk()
	elseif done then
		wheelWalking = false
		Perf.SetScript(wheelWalker, "OnUpdate", nil)
	end
end

-- a window onto the stack; the walk starts now (one under way takes it on)
local function WalkWindow(window)
	walkTop = walkTop + 1
	walkStack[walkTop] = window
	if wheelWalking then
		return
	end
	wheelWalking = true
	Walking()
	if wheelWalking then
		Perf.SetScript(wheelWalker, "OnUpdate", Walking)
	end
end

-- f (the frame under the mouse) and its parents hooked, and their window
-- walked unless it was lately; a frame on the world's side (a nameplate's)
-- has no window
local function WheelLookAt(f)
	if not (f and GroupOn("scrollWheel")) then
		return
	end
	local window
	for _ = 1, WHEEL_UP do
		if f == UIParent or f == WorldFrame then
			break
		end
		if not wheelHooked[f] then
			HookWheel(f)
		end
		window = f
		local ok, parent = pcall(f.GetParent, f)
		if not ok or Secret(parent) then
			parent = nil
		end
		f = parent
		if not f then
			break
		end
	end
	if not window or f == WorldFrame then
		return
	end
	local now = GetTime()
	local last = wheelWalked[window]
	if not last or now - last >= WALK_AGAIN then
		wheelWalked[window] = now
		WalkWindow(window)
	end
end

local function WheelLook()
	wheelLookQueued = false
	WheelLookAt(MouseFrame())
end

-- a look on the next frame (as the world frame's OnLeave runs, the mouse
-- may not have its new frame yet); one waiting at a time
local function QueueWheelLook()
	if not wheelLookQueued and GroupOn("scrollWheel") then
		wheelLookQueued = true
		C_Timer.After(0, WheelLook)
	end
end

-- the mouse over the world (its frame says so without a list): a click
-- there has no list to look at
local function OverWorld()
	local w = WorldFrame
	if not (w and w.IsMouseMotionFocus) then
		return false
	end
	local ok, focus = pcall(w.IsMouseMotionFocus, w)
	return ok and not Secret(focus) and focus == true
end

Perf.SetScript(wheelWalker, "OnEvent", function(_, event)
	if event == "GLOBAL_MOUSE_DOWN" and not OverWorld() then
		WheelLookAt(MouseFrame())
	end
end)

--------------------------------------------------------------------------------
-- Hover ticks: the frame under the mouse, polled twenty times a second (a
-- timer, not a script on every frame). GetMouseFoci makes a new list on
-- every call, so it is asked only when the frame found last has lost the
-- mouse (the game says so without a list): the moment another frame comes
-- under the cursor, moved or not (a list scrolled under a still cursor),
-- and at every fourth look besides (a frame on top can pass the mouse on to
-- the one below, which then keeps it too). Over the world nothing is asked
-- until the mouse leaves it. While the cursor rests, that fourth-look ask,
-- and the ask on every look where nothing usable was found last (a forbidden
-- frame, an empty list), come once a second only (user, 2026-09-24: "clean up
-- the spikes"): a still cursor asked five times a second on a button and
-- twenty over a forbidden frame, a new list each time, for the same answer.
-- A frame that comes under a resting cursor and passes the mouse on is then
-- found within a second instead of a fifth; the moment the cursor moves, or
-- the frame found last loses the mouse, it is asked as before.
-- Over the world the looks stop altogether (user, 2026-09-24: no idle work):
-- the world has no button, and the game tells the world frame when the mouse
-- comes and goes (post-hooks on its OnEnter / OnLeave), so the looks start
-- again the moment the mouse leaves it for the interface. That is trusted
-- only once both have been seen: on a client where they never come, the looks
-- go on over the world as before. The mouse crosses between the world and
-- the interface all the time, so stopping and starting must cost nothing:
-- one step made once, each look queueing the next (a one-shot timer, which
-- makes nothing new), rather than a new ticker at every crossing.
--------------------------------------------------------------------------------

local HOVER_EVERY = 0.05    -- seconds between two looks
local HOVER_KEPT = 4        -- looks between two asks while the frame found last keeps the mouse
local HOVER_STILL = 20      -- looks between two asks while the cursor rests (a second)
local hoverOn = false       -- the looks run
local hoverQueued = false   -- the next look is waiting on its timer (never two at once)
local hoverLast = nil
local hoverLooks = 0        -- looks since the last ask
local hoverX, hoverY = nil, nil   -- the cursor at the last ask (nil: unknown)
local worldHooked = false         -- the world frame's hooks are in (once, when the ticks are first on)
local worldEntered, worldLeft = false, false   -- the game has told the world frame each at least once

-- the cursor, or nil where the game cannot say
local function CursorAt()
	if not GetCursorPosition then
		return nil, nil
	end
	local x, y = GetCursorPosition()
	if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then
		return nil, nil
	end
	return x, y
end

-- the frame still has the mouse (false where the game cannot say)
local function KeepsMouse(f)
	if not (f and f.IsMouseMotionFocus) then
		return false
	end
	local ok, focus = pcall(f.IsMouseMotionFocus, f)
	if not ok or (issecretvalue and issecretvalue(focus)) then
		return false
	end
	return focus == true
end

-- The mouse is over the world: the looks stop while the world frame's leave
-- can be trusted to start them again.
local function RestOverWorld()
	if worldEntered and worldLeft then
		hoverOn = false
	end
end

local function HoverTick()
	hoverLooks = hoverLooks + 1
	local kept = hoverLast and KeepsMouse(hoverLast)
	if kept and (hoverLast == WorldFrame or hoverLooks < HOVER_KEPT) then
		if hoverLast == WorldFrame then
			RestOverWorld()
		end
		return
	end
	-- a resting cursor waits a second between two asks; a frame found last
	-- that lost the mouse is asked about at once, rested or not
	local x, y = CursorAt()
	if (kept or not hoverLast) and hoverLooks < HOVER_STILL and x and x == hoverX and y == hoverY then
		return
	end
	hoverLooks = 0
	hoverX, hoverY = x, y
	local f = MouseFrame()
	if f and f == WorldFrame then
		RestOverWorld()
	end
	if f == hoverLast then
		return
	end
	hoverLast = f
	if not f or f == WorldFrame or f == UIParent then
		return
	end
	-- (a new frame under the mouse: the wheel's look too, while it is on)
	WheelLookAt(f)
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
	Play("UI_Hover", "%s", FrameName(f) or "a button")
end

-- one look, the next queued first (as a ticker would: a look that fails
-- does not end them); stopped, the look waiting finds that and queues nothing
local function HoverStep()
	hoverQueued = false
	if not hoverOn then
		return
	end
	hoverQueued = true
	C_Timer.After(HOVER_EVERY, HoverStep)
	HoverTick()
end

local function StartLooks()
	hoverOn = true
	if not hoverQueued then
		hoverQueued = true
		C_Timer.After(HOVER_EVERY, HoverStep)
	end
end

-- the world frame's hooks: the mouse came (noted; the next look finds the
-- world and rests) or went (the looks start again, the first a twentieth of
-- a second later, as it would have come had they run on; and the wheel's
-- look at what the mouse went to, on the next frame)
local function WorldEntered()
	worldEntered = true
end

local function WorldLeft()
	worldLeft = true
	if GroupOn("hover") then
		StartLooks()
	end
	QueueWheelLook()
end

local function HookWorld()
	if worldHooked or not WorldFrame then
		return
	end
	worldHooked = true
	if WorldFrame.HookScript then
		pcall(Perf.HookScript, WorldFrame, "OnEnter", WorldEntered)
		pcall(Perf.HookScript, WorldFrame, "OnLeave", WorldLeft)
	end
end

local function ApplyHover()
	if GroupOn("hover") then
		HookWorld()
		StartLooks()
	else
		hoverOn = false
		hoverLast = nil
		hoverLooks = 0
		hoverX, hoverY = nil, nil
	end
end

-- The wheel's moments while Scroll Wheel is on: the world frame's hooks
-- (the hover ticks' too) and the clicks. Nothing is looked at here: the
-- first look comes with the mouse (at login, nothing is walked).
local function ApplyWheel()
	if GroupOn("scrollWheel") then
		HookWorld()
		pcall(wheelWalker.RegisterEvent, wheelWalker, "GLOBAL_MOUSE_DOWN")
	else
		pcall(wheelWalker.UnregisterEvent, wheelWalker, "GLOBAL_MOUSE_DOWN")
		DropWalk()
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
	return name and Play(name, "configurator %s", kind) or false
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
	-- (switched on in the configurator: the window under the mouse, the
	-- configurator itself, looked at now rather than at the next click)
	if key == "scrollWheel" and value then
		QueueWheelLook()
	end
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
	-- the game's own time to start each file, slowest first
	local played = {}
	for name, n in pairs(calls) do
		if n > 0 then
			played[#played + 1] = name
		end
	end
	table.sort(played, function(a, b) return slowestMs[a] > slowestMs[b] end)
	local parts = {}
	for i = 1, math.min(#played, 6) do
		local name = played[i]
		parts[i] = string.format("%s %.1f ms (first %.1f ms, %d x)", name, slowestMs[name], firstMs[name], calls[name])
	end
	MelloUI:Print("PlaySoundFile, slowest: %s", #parts > 0 and table.concat(parts, ", ") or "nothing played yet")
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
			lastPlayed[name] = false
			local ok, willPlay = PlayFile(name, (M.db and M.db.channel) or "SFX")
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
	MelloUI:Print("Last %d sound events (time within the hour, newest last):", noteCount)
	-- oldest first: the slot the next event would take, once the ring is full
	local first = noteCount < EVENTS_MAX and 1 or noteNext
	for i = 0, noteCount - 1 do
		MelloUI:Print("  %s", NoteLine(notes[(first - 1 + i) % EVENTS_MAX + 1]))
	end
	MelloUI:ShowLog("sfxdump")
end
