--------------------------------------------------------------------------------
-- MelloUI - Skin (1.2.4; docs/plans/default-skin.md)
--
-- The user, 2026-10-26: "if you use the default skin, then everything has the default game look ... the quest
-- tracker, bags, chat, minimap etc also have a blizzard default look, modern uses the modern skin and oldschool the
-- old school"; on the first sketch: "i dont want you to reorganize it, i want you to keep the same modern look, just a
-- reskin using default assets"; and "Make sure that every texture and border you use are sharp and highres".
--
-- ONE switch for the look of MelloUI's own parts: UI Modifications' Skin, "modern" (MelloUI's own art, the default)
-- or "default" (the game's own art -- WoW Forever's atlases and files by name, its fonts and colours -- in exactly the
-- places Modern has its own: nothing moves, nothing is added or taken away). Oldschool's painted look is its reskin
-- on top (Kit.Areas): while it dresses, the skin reads Modern (folded into this setting with the installer's skin
-- step, wave D). The shared systems ask here and lay their own pieces: the palette (MelloUI.Look.Palette), the
-- controls (Widgets), the rims (MelloUI.Rims), the icons (MelloUI.Icons), the fonts (the widgets' own font objects,
-- the Fonts module), MelloUI Frames. Every game piece at its own size or smaller.
--
--   Skin.Name() -> "default" | "modern"   (the setting as saved; any other value reads "modern")
--   Skin.IsDefault() -> true while the Default skin shows (the setting "default", and Oldschool's reskin off)
--   Skin.Follow(obj, apply)   apply(obj, isDefault) now, and again at every switch (weak: obj is its owner's)
--   Skin.Border(frame, kind[, first[, last]]) -> border   the game's border round `first` (frame) to `last`
--       (first), a child frame of `frame`: kind "tooltip" (the tooltip's edge on the rect), "window" (the dialog's
--       diamond metal, its inner edge on the rect) or "bubble" (the chat bubble's); no picture in its middle (a fill
--       is the caller's). Skin.LayBorder(border, first[, last]) lays it again round another rect
--   Skin.LayHair(tex, alpha)   a hairline (W.Hairline's) in the game's own line: the Settings divider's colour, one
--       texel of it drawn at any length (MelloUI.Painter's, for a hairline under the Default skin)
--   Skin.Icon(name) -> spec | nil   the game's picture for an icon of MelloUI's set (a name, or its path in the
--       set's folder): { atlas = } or { file = } (a game icon, its border cut: `crop`), `letter` (a channel key: the
--       game's chat button with the letter on it), `disc` (a picture with a clear ground: a round button lays a dark
--       disc under it), `round` (a square icon cut round, as the set's), `coords` (its part of a sheet: a class
--       medallion's path -> the game's class circle), `flip` (an atlas pointing the other way from the set's icon:
--       turned over top to bottom); nil while the Default skin is off or the icon has no game twin (MelloUI's own then)
--   Skin.LayIcon(tex, spec)   the game's picture on tex (Icons.Set's: its size the caller's);
--       Skin.ClearIcon(tex) takes a channel key's letter away again
-- The bus: 'skin' (isDefault) goes out at a switch, then each look area's 'look:<area>' with its own answer
-- (Kit:IsOn), so every piece that follows an area is laid again; the followers last. Read when asked: nothing at
-- login, nothing polls.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Skin")

local Skin = { followers = setmetatable({}, { __mode = "k" }) }
MelloUI.Skin = Skin

local SWITCHES = "UIModifications"   -- the module whose settings hold the skin (read raw: its switch on or off)

function Skin.Name()
	local db = MelloUI.db
	local s = db and db.modules and db.modules[SWITCHES]
	return (type(s) == "table" and s.skin == "default") and "default" or "modern"
end

-- Oldschool's painted reskin on (the 'copy' area answers it alone: the reskin's, no showcase)
local function Reskinned()
	local Kit = MelloUI.Kit
	return type(Kit) == "table" and type(Kit.IsOn) == "function" and Kit:IsOn("copy") == true
end

-- the answer the pieces were laid in: taken down at the first ask (every piece asks as it lays itself), told anew at
-- a switch
local told = nil

function Skin.IsDefault()
	local now = Skin.Name() == "default" and not Reskinned()
	if told == nil and MelloUI.db then   -- (before the settings are read, an ask takes nothing down)
		told = now
	end
	return now
end

function Skin.Follow(obj, apply)
	Skin.followers[obj] = apply
	apply(obj, Skin.IsDefault())
end

--------------------------------------------------------------------------------
-- The switch: told when the answer changes (a setting of UI Modifications', a profile loaded, a module switched),
-- looked at on the next frame so the kit's own pass has run
--------------------------------------------------------------------------------

local function Tell()
	local was = told
	local now = Skin.IsDefault()
	if was == nil or now == was then
		return   -- (nothing laid yet, or no change)
	end
	told = now
	MelloUI:Fire("skin", now)
	local Kit = MelloUI.Kit
	if type(Kit) == "table" and type(Kit.Areas) == "table" and type(Kit.IsOn) == "function" then
		for name, area in pairs(Kit.Areas) do
			MelloUI:Fire(area.topic or ("look:" .. name), Kit:IsOn(name))
		end
	end
	for obj, apply in pairs(Skin.followers) do
		local ok, err = pcall(apply, obj, now)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local function Later()
	if told == nil then
		return   -- (nothing laid yet: the first piece takes the answer down)
	end
	local S = MelloUI.Schedule
	if type(S) == "table" and S.NextFrame then
		S:NextFrame(Skin, Tell)
	else
		Tell()
	end
end

MelloUI:On("setting", Perf.Shared("'setting' on the bus: the skin", function(name)
	if name == SWITCHES then
		Later()
	end
end), Skin)
MelloUI:On("restart", Perf.Shared("'restart' on the bus: the skin", Later), Skin)
MelloUI:On("module", Perf.Shared("'module' on the bus: the skin", Later), Skin)

--------------------------------------------------------------------------------
-- The game's pieces the shared systems lay under the Default skin, by name in this one place (each drawn at its own
-- size or smaller: the sizes in the comments are the pieces' own, measured on the client's art)
--------------------------------------------------------------------------------
Skin.ART = {
	ring = "communities-ring-gold",                 -- (95 px) a round button's rim
	roundLight = "common-roundhighlight",           -- (114 px) a round button's light under the pointer
	divider = "Options_HorizontalDivider",          -- (630 x 1) a heading's line
	tab = "Options_Tab_", tabOn = "Options_Tab_Active_",   -- (7 px ends, a 1 px middle; 23 / 26 high) + Left / Middle / Right
	ddHolder = "common-dropdown-textholder",        -- (54 x 41, its ends kept) a dropdown's box
	ddArrow = "common-dropdown-a-button", ddArrowLit = "common-dropdown-a-button-hover",
	ddArrowOff = "common-dropdown-a-button-disabled",   -- (27 px) its arrow button
	chatButton = "chatframe-button-up",             -- (27 x 26) a chat button's plate
	-- (2x art: 16 x 40 px ends, drawn 8 x 20 as InputBoxTemplate draws them) a text field's box
	inputLeft = "common-search-border-left", inputMiddle = "common-search-border-middle",
	inputRight = "common-search-border-right",
	knob = "Minimal_SliderBar_Button",              -- (20 x 19) a slider's knob
	-- the red panel button (UIPanelButtonTemplate's own files: the art the top 22 of 32 rows)
	button = "Interface\\Buttons\\UI-Panel-Button-Up", buttonOff = "Interface\\Buttons\\UI-Panel-Button-Disabled",
	buttonLit = "Interface\\Buttons\\UI-Panel-Button-Highlight",
	-- (wave C) the game's compact raid frame (CompactUnitFrameTemplate's art): a Group Frames cell's health fill and
	-- dark ground (32 px, both tile both ways), its resource fill (16 x 6, tiles along), its separators (128 x 8 and
	-- 8 x 128: the line the outer 2 texels, tiled along its length)
	raidFill = "RaidFrame-Hp-Fill", raidGround = "RaidFrame-Hp-Bg", raidPower = "_RaidFrame-Resource-Fill",
	raidSepH = "Interface\\RaidFrame\\Raid-HSeparator", raidSepV = "Interface\\RaidFrame\\Raid-VSeparator",
}

--------------------------------------------------------------------------------
-- The game's borders (NineSliceUtil's own layouts): the rims of MelloUI's windows and panels, the whisper bubbles
--------------------------------------------------------------------------------

local LAYOUT = { tooltip = "TooltipDefaultLayout", window = "Dialog", bubble = "ChatBubble" }
-- how far the border lies outside its rect: the dialog's diamond metal outside the window's edge, its inner edge on it
-- (the metal band is rows 16-49 of the 128 px pieces, so it ends 24.5 into the 64-unit piece)
local OUT = { tooltip = 0, window = 24, bubble = 3 }

function Skin.LayBorder(border, first, last)
	local out = OUT[border.kind] or 0
	last = last or first
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", first, "TOPLEFT", -out, out)
	border:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", out, -out)
end

-- (the user's retail test, 2026-10-27: "the backpack border is messed up") the dialog's diamond metal is Forever's own
-- art (a band 24 units deep, OUT); the retail client's is a thin rule at its pieces' outer edge with a see-through
-- shadow inside it -- laid 24 out it showed the world between its rule and the window. There a window wears the
-- tooltip's border on its edge (the client: MelloUI.Retail, Core.lua)
Skin.FOREVER_ART = not MelloUI.Retail

function Skin.Border(frame, kind, first, last)
	kind = LAYOUT[kind] and kind or "tooltip"
	if kind == "window" and not Skin.FOREVER_ART then
		kind = "tooltip"
	end
	local border = CreateFrame("Frame", nil, frame)
	border.kind = kind
	border:EnableMouse(false)
	local Util = _G.NineSliceUtil
	if type(Util) == "table" and Util.ApplyLayoutByName then
		Util.ApplyLayoutByName(border, LAYOUT[kind])
	end
	-- (no picture in its middle: never a stretched one; a fill under it is its owner's -- NineSliceUtil's Center piece)
	local centre = border.Center
	if centre and centre.Hide then
		centre:Hide()
	end
	Skin.LayBorder(border, first or frame, last)
	return border
end

-- a hairline: the Settings divider's strongest texel (150 of its 630, where it is darkest before it fades), so a
-- line of any length or way is the game's own line colour, flat (one texel drawn big is a flat fill, never a stretched
-- picture); read once. Laid as the game's NineSlice crops an atlas: its sheet's file, then the sheet's coordinates
-- (never coordinates after SetAtlas, whose space the client and the simulator read differently)
local HAIR_TEXEL, hairUV = 150, nil

function Skin.LayHair(tex, alpha)
	local name = Skin.ART.divider
	if hairUV == nil then
		hairUV = false
		local Num = MelloUI.Safe.Number
		local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
		local file = info and (info.file or info.filename)
		local l = info and Num(info.leftTexCoord)
		local r, t, b, w = info and Num(info.rightTexCoord), info and Num(info.topTexCoord),
			info and Num(info.bottomTexCoord), info and Num(info.width)
		if file and l and r and t and b and w and w > HAIR_TEXEL then
			local step = (r - l) / w
			hairUV = { l + step * HAIR_TEXEL, l + step * (HAIR_TEXEL + 1), t, b, file = file }
		end
	end
	if hairUV then
		tex:SetTexture(hairUV.file)
		tex:SetTexCoord(hairUV[1], hairUV[2], hairUV[3], hairUV[4])
	else
		tex:SetAtlas(name)   -- (no sheet to read: the divider whole)
	end
	tex:SetVertexColor(1, 1, 1, alpha or 1)
end

-- (1.2.4, the whisper window's bubbles: BuildData/output/chat_room_sketch) a chat bubble's ground: the game's bubble
-- middle (ChatBubble-NineSlice-Center: the piece NineSliceUtil lays between the bubble's edges) as its middle texel,
-- flat, so a bubble of any size is the game's own dark, never its picture stretched; read once, as the hairline
local bubbleUV = nil

function Skin.LayBubbleGround(tex)
	local name = "ChatBubble-NineSlice-Center"
	if bubbleUV == nil then
		bubbleUV = false
		local Num = MelloUI.Safe.Number
		local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
		local file = info and (info.file or info.filename)
		local l, r = info and Num(info.leftTexCoord), info and Num(info.rightTexCoord)
		local t, b = info and Num(info.topTexCoord), info and Num(info.bottomTexCoord)
		local w, h = info and Num(info.width), info and Num(info.height)
		if file and l and r and t and b and w and h and w > 1 and h > 1 then
			local u, v = l + (r - l) * (math.floor(w / 2) / w), t + (b - t) * (math.floor(h / 2) / h)
			bubbleUV = { u, u + (r - l) / w, v, v + (b - t) / h, file = file }
		end
	end
	if bubbleUV then
		tex:SetTexture(bubbleUV.file)
		tex:SetTexCoord(bubbleUV[1], bubbleUV[2], bubbleUV[3], bubbleUV[4])
	else
		tex:SetAtlas(name)   -- (no sheet to read: the middle whole)
	end
	tex:SetVertexColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- The game's pictures for MelloUI's icon set (by name): the same things the game itself draws -- its map's service
-- icons for the Services, its quest marks, chat and friends icons, its spell and item icons for the configurator's
-- pages. An icon with no game twin keeps MelloUI's own
--------------------------------------------------------------------------------

local I = "Interface\\Icons\\"
local ICON = {
	-- the Services: the game's own map icons for the same services
	svc_flight = { atlas = "FlightMaster", disc = true }, svc_repair = { atlas = "Repair", disc = true },
	svc_auction = { atlas = "Auctioneer", disc = true }, svc_barber = { atlas = "Barbershop-32x32", disc = true },
	svc_classtrainer = { atlas = "Class", disc = true }, svc_errands = { atlas = "Mailbox", disc = true },
	svc_bank = { atlas = "Banker", disc = true }, svc_inn = { atlas = "Innkeeper", disc = true },
	svc_mail = { atlas = "Mailbox", disc = true }, svc_proftrainer = { atlas = "Profession", disc = true },
	svc_vendor = { atlas = "Food", disc = true }, svc_addons = { atlas = "mechagon-projects", disc = true },
	-- quest marks and the tracker's
	track_todo = { atlas = "QuestNormal" }, track_handin = { atlas = "QuestTurnin" }, quest_mark = { atlas = "QuestNormal" },
	turnin_mark = { atlas = "QuestTurnin" }, ql_notyet = { atlas = "TrivialQuests" },
	-- (the set's gold tick: done -- a quest done, a dungeon's quest done, the installer's Review rows; 2026-10-27: the
	-- game's checkmark, the turn-in "?" it had read as a quest still to hand in)
	ql_completed = { atlas = "common-icon-checkmark" },
	ql_chest = { atlas = "VignetteLoot" }, goal_pin = { atlas = "Waypoint-MapPin-Tracked" },
	btn_way = { atlas = "Navigation-Tracked-Arrow" }, btn_list = { atlas = "dressingroom-button-appearancelist-up" },
	kill = { atlas = "DungeonSkull" }, kill_elite = { atlas = "VignetteKillElite" }, kill_rare = { atlas = "VignetteKill" },
	pin_dungeon = { atlas = "Dungeon" }, pin_raid = { atlas = "Raid" }, pin_portal = { atlas = "PortalBlue" },
	-- the controls (the game's own, at their sizes or smaller)
	ctl_check_off = { atlas = "checkbox-minimal" }, ctl_check_on = { atlas = "checkmark-minimal", box = "checkbox-minimal" },
	-- (the dropdown's arrow button at rest -- "-up" is its state, the arrow points down; the plain arrow points up, as
	-- the set's, which its callers turn)
	ctl_dropdown = { atlas = "auctionhouse-ui-dropdown-arrow-up" }, btn_arrow = { atlas = "editmode-up-arrow" },
	ctl_knob = { atlas = Skin.ART.knob },
	btn_collapse = { atlas = "UI-QuestTrackerButton-Collapse-All" }, btn_expand = { atlas = "UI-QuestTrackerButton-Expand-All" },
	btn_accept = { atlas = "common-icon-checkmark" }, btn_decline = { atlas = "RedButton-Exit" },
	btn_friend = { atlas = "friends-icon-addFriend" }, btn_invite = { atlas = "friends-icon-friendsInGroup" },
	btn_ignore = { atlas = "communities-icon-redx" }, btn_report = { file = I .. "INV_Misc_Note_02", crop = 0.07 },
	btn_reply = { atlas = "communities-icon-chat" }, btn_sort = { atlas = "bags-button-autosort-up" },
	btn_discard = { atlas = "bags-junkcoin" },
	-- the chat: its rail's channels, its buttons' pictures, its channel keys (the game's chat button, the letter on it)
	chat_general = { atlas = "communities-icon-chat" }, chat_combat = { atlas = "combat_swords-icon" },
	chat_whispers = { file = "Interface\\ChatFrame\\UI-ChatConversationIcon" },
	chat_channels = { atlas = "chatframe-button-icon-voicechat", plate = "chatframe-button-up" },
	chat_friends = { atlas = "socialqueuing-icon-group", plate = "chatframe-button-up" },
	chat_settings = { atlas = "common-dropdown-a-button-settings-shadowless" },   -- (the game's own settings button: its cog on its plate)
	chat_history = { file = I .. "INV_Misc_Book_09", crop = 0.07, plate = "chatframe-button-up" },
	chat_loot = { atlas = "bags-icon-tradegoods" },
	chan_say = { atlas = "chatframe-button-up", letter = "S" }, chan_party = { atlas = "chatframe-button-up", letter = "P" },
	chan_raid = { atlas = "chatframe-button-up", letter = "R" }, chan_instance = { atlas = "chatframe-button-up", letter = "I" },
	chan_guild = { atlas = "chatframe-button-up", letter = "G" }, chan_yell = { atlas = "chatframe-button-up", letter = "Y" },
	chan_whisper = { atlas = "chatframe-button-up", letter = "W" }, chan_emote = { atlas = "chatframe-button-up", letter = "E" },
	-- rings and badges
	ring_gold = { atlas = "communities-ring-gold" }, uf_badge = { atlas = "UI-HUD-UnitFrame-SmallCircle" },
	bag_backpack = { file = I .. "INV_Misc_Bag_08", crop = 0.07 },
	-- (wave C, the user's picks, 2026-10-27: "A everywhere") Route's and the map's marks: the minimap's own pieces
	arrow_player = { atlas = "MinimapArrow" },
	edge_arrow = { atlas = "MiniMap-QuestArrow", flip = true },   -- (the game's points up, the set's V down: turned over)
	goal_cream = { atlas = "Waypoint-MapPin-Untracked" }, goal_red = { atlas = "Waypoint-MapPin-Tracked" },
	route_bead = { atlas = "PartyMember" },
	-- (every map dot is drawn tinted in its meaning colour -- a quest's, a whisperer's state -- so the game's white blip,
	-- as the game tints its own; the blue party dot would turn muddy under a tint)
	map_dot = { atlas = "PlayerPartyBlip" },
	pin_boat = { atlas = "FlightMasterFerry" }, pin_zeppelin = { atlas = "Vehicle-Air-Unoccupied" },
	pin_tram = { atlas = "Vehicle-SilvershardMines-MineCart" },
	-- the quests' objective kinds, loot, reagents
	pin_collect = { atlas = "VignetteLoot" }, obj_explore = { atlas = "XMarksTheSpot" },
	obj_use = { atlas = "UpgradeItem-32x32" }, loot = { atlas = "VignetteLoot" }, bag_reagent = { atlas = "bags-icon-reagents" },
	-- the media buttons (the dropdowns' small gold set, the credits' pause beside it) and the locks
	btn_play = { atlas = "common-dropdown-icon-play" }, btn_pause = { atlas = "CreditsScreen-Assets-Buttons-Pause" },
	btn_stop = { atlas = "common-dropdown-icon-stop" }, btn_next = { atlas = "common-dropdown-icon-next" },
	btn_locked = { file = "Interface\\Buttons\\LockButton-Locked-Up" },
	btn_unlocked = { file = "Interface\\Buttons\\LockButton-Unlocked-Up" },
	-- Voice Over's
	voice_greeting = { atlas = "ChatBallon" }, voice_progress = { atlas = "ChatBallon" },
	voice_page = { atlas = "common-dropdown-icon-sound-on" },
}
-- the configurator's pages and categories, the meter's: the game's own spell and item icons (their borders cut)
for name, icon in pairs({
	page_look = "INV_Misc_Gem_Sapphire_01", page_windows = "INV_Misc_Book_09", page_fader = "Spell_Magic_LesserInvisibilty",
	page_frames = "INV_Misc_GroupNeedMore", page_nameplates = "Ability_Spy", page_bars = "Ability_Warrior_BattleShout",
	page_minimap = "INV_Misc_Map_01", page_meter = "INV_Misc_PocketWatch_01", page_chat = "INV_Letter_15",
	page_tooltip = "INV_Misc_Note_01", page_screentext = "INV_Scroll_03", page_tracker = "Achievement_Quests_Completed_06",
	page_questlist = "INV_Misc_Book_07", page_route = "Ability_Tracking", page_reminders = "INV_Misc_Bell_01",
	page_automation = "INV_Misc_Wrench_01", page_sounds = "INV_Misc_Horn_01", page_profiles = "INV_Misc_Book_11",
	page_oldschool = "INV_Misc_Rune_01", page_voice = "INV_Misc_Horn_03",
	cat_look = "INV_Misc_Gem_Sapphire_01", cat_frames = "INV_Misc_GroupNeedMore", cat_chat = "INV_Letter_15",
	cat_quests = "Achievement_Quests_Completed_06", cat_sound = "INV_Misc_Horn_01",
	btn_dungeon = "INV_Misc_Head_Dragon_Black", btn_meter = "INV_Misc_PocketWatch_01",
	meter_damage = "Ability_MeleeDamage", meter_heal = "Spell_Holy_FlashHeal", meter_time = "INV_Misc_PocketWatch_02",
}) do
	ICON[name] = { file = I .. icon, crop = 0.07, round = true }
end
Skin.ICON = ICON

-- an icon's name in the set: a name, or its path in the set's folder (Icons.DIR) or in a look's own set's (1.2.4:
-- Oldschool's, kept by a picture set while that look was on), its extension left off
local function NameOf(icon)
	if type(icon) ~= "string" then
		return nil
	end
	local Icons = MelloUI.Icons
	if Icons and Icons.NameOf then
		return Icons.NameOf(icon)
	end
	local dir = Icons and Icons.DIR
	if dir and icon:sub(1, #dir) == dir then
		icon = icon:sub(#dir + 1)
	elseif icon:find("\\", 1, true) then
		return nil
	end
	return (icon:gsub("%.[TtBb][GgLl][AaPp]$", ""))
end

-- a class's medallion (Class Icons' MelloUI:ClassIconPath, any of its copies): the game's own round class icon, its
-- circle on the game's sheet (the game's CLASS_ICON_TCOORDS; 64 px each)
local CLASS_DIR = "Interface\\AddOns\\MelloUI\\Media\\Icons\\Class\\"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local classSpecs = {}

local function ClassSpec(icon)
	local class = icon:sub(#CLASS_DIR + 1):match("^(%u+)")
	local spec = class and classSpecs[class]
	if spec == nil and class then
		local all = _G.CLASS_ICON_TCOORDS
		local c = type(all) == "table" and all[class]
		spec = type(c) == "table" and { file = CLASS_CIRCLES, coords = { c[1], c[2], c[3], c[4] } } or false
		classSpecs[class] = spec
	end
	return spec or nil
end

function Skin.Icon(icon)
	if not Skin.IsDefault() then
		return nil
	end
	if type(icon) == "string" and icon:sub(1, #CLASS_DIR) == CLASS_DIR then
		return ClassSpec(icon)
	end
	local name = NameOf(icon)
	return name and ICON[name] or nil
end

local letters = setmetatable({}, { __mode = "k" })   -- [tex] = its letter (a channel key's)
local boxes = setmetatable({}, { __mode = "k" })     -- [tex] = the box under a ticked check box's mark
local cuts = setmetatable({}, { __mode = "k" })      -- [tex] = the round cut for a square icon (`round`; false: none)
local cutOn = setmetatable({}, { __mode = "k" })     -- [tex] = true while it is cut
local ROUND_CUT = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- (a square icon of the game's in the place of one of the set's round ones: cut round, as the set's is; never a
-- picture its owner masks already; the cut made once, kept for the next switch)
local function Cut(tex, on)
	if on and not cutOn[tex] then
		local m = cuts[tex]
		if m == nil then
			local okN, n = pcall(tex.GetNumMaskTextures, tex)
			m = false
			if not (okN and type(n) == "number" and not MelloUI.Safe.IsSecret(n) and n > 0) then
				m = tex:GetParent():CreateMaskTexture()
				m:SetTexture(ROUND_CUT, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				m:SetAllPoints(tex)
			end
			cuts[tex] = m
		end
		if m then
			tex:AddMaskTexture(m)
			cutOn[tex] = true
		end
	elseif not on and cutOn[tex] then
		tex:RemoveMaskTexture(cuts[tex])
		cutOn[tex] = nil
	end
end

function Skin.ClearIcon(tex)
	local fs = letters[tex]
	if fs then
		fs:Hide()
	end
	if boxes[tex] then
		boxes[tex]:Hide()
	end
	Cut(tex, false)
end

-- (a picture pointing the other way from the set's: turned over top to bottom, so the set's callers turn it as they
-- turn the set's -- its sheet and its part of it, as the game's NineSlice crops an atlas: the file, then the sheet's
-- coordinates)
local function Flip(tex, atlas)
	local Num = MelloUI.Safe.Number
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local file = info and (info.file or info.filename)
	local l, r = info and Num(info.leftTexCoord), info and Num(info.rightTexCoord)
	local t, b = info and Num(info.topTexCoord), info and Num(info.bottomTexCoord)
	if file and l and r and t and b then
		tex:SetTexture(file)
		tex:SetTexCoord(l, r, b, t)
	end
end

function Skin.LayIcon(tex, spec)
	if spec.atlas then
		tex:SetAtlas(spec.atlas)
		if spec.flip then
			Flip(tex, spec.atlas)
		end
	else
		tex:SetTexture(spec.file)
		local q = spec.coords
		if q then
			tex:SetTexCoord(q[1], q[2], q[3], q[4])
		else
			local c = spec.crop or 0
			tex:SetTexCoord(c, 1 - c, c, 1 - c)
		end
	end
	-- (the game's check box is a box with the mark over it: the box under a ticked one, on its rect)
	local box = boxes[tex]
	if spec.box then
		if not box then
			local layer, sub = tex:GetDrawLayer()
			box = tex:GetParent():CreateTexture(nil, layer, nil, math.max(-8, (sub or 0) - 1))
			box:SetAllPoints(tex)
			boxes[tex] = box
		end
		box:SetAtlas(spec.box)
		box:SetAlpha(tex:GetAlpha())
		box:Show()
	elseif box then
		box:Hide()
	end
	local fs = letters[tex]
	if spec.letter then
		if not fs then
			local parent = tex:GetParent()
			fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			fs:SetPoint("CENTER", tex, "CENTER", 0, 1)
			letters[tex] = fs
		end
		fs:SetText(spec.letter)
		fs:Show()
	elseif fs then
		fs:Hide()
	end
	Cut(tex, spec.round or false)
end
