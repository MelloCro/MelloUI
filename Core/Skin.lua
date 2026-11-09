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
-- on top (Kit.Areas): while it dresses, the skin reads Modern. The three are picked in one place, the skin whole
-- (Skin.SETS, Skin.Pick: the installer's Skin step and Look > General's Skin row, el-13). The shared systems ask
-- here and lay their own pieces: the palette (MelloUI.Look.Palette), the
-- controls (Widgets), the rims (MelloUI.Rims), the icons (MelloUI.Icons), the fonts (the widgets' own font objects,
-- the Fonts module), MelloUI Frames. Every game piece at its own size or smaller.
--
--   Skin.Name() -> "default" | "modern"   (the setting as saved; any other value reads "modern")
--   Skin.IsDefault() -> true while the Default skin shows (the setting "default", and Oldschool's reskin off)
--   Skin.SETS[skin] -> { ["Module.key"] = value, ["!Module"] = true }   each skin's settings and the switches it needs
--   Skin.Offered(skin), Skin.Current() -> "default" | "modern" | "oldschool"   pickable; the skin in use
--   Skin.Pick(skin) -> laid   a player's pick: the set written, what it needs turned on (never a module off)
--   Skin.Follow(obj, apply)   apply(obj, isDefault) now, and again at every switch (weak: obj is its owner's)
--   Skin.Border(frame, kind[, first[, last]]) -> border   the game's border round `first` (frame) to `last`
--       (first), a child frame of `frame`: kind "tooltip" (the tooltip's edge on the rect), "window" (the dialog's
--       diamond metal, its inner edge on the rect) or "bubble" (the chat bubble's); no picture in its middle (a fill
--       is the caller's). Skin.LayBorder(border, first[, last]) lays it again round another rect
--   Skin.Window(frame[, opts]) -> win   (lk-12) the game's portrait window frame round an own window (the shell, the
--       whisper window, the minimap panel); Skin.WindowTitle / Skin.WindowClose lay its owner's title and close;
--       Skin.CoinBox(parent) the game's coin box (the bag window's money); Skin.ChatTab(button) the game's chat tab
--       (Chat View's channels under Default), Skin.ChatAlpha([id]) its see-through chat box's alpha (Chat View's box, the
--       damage meter's list); Skin.ListGround / Skin.ListRow / Skin.Inset the game's Communities
--       pieces (the whisper window). Their own blocks below
--   Skin.LayHair(tex, alpha)   a hairline (W.Hairline's) in the game's own line: the Settings divider's colour, one
--       texel of it drawn at any length (MelloUI.Painter's, for a hairline under the Default skin)
--   Skin.Icon(name) -> spec | nil   the game's picture for an icon of MelloUI's set (a name, or its path in the
--       set's folder): { atlas = } or { file = } (a game icon, its border cut: `crop`), `letter` (a channel key: the
--       game's chat button with the letter on it), `disc` (a picture with a clear ground: a round button lays a dark
--       disc under it), `round` (a square icon cut round, as the set's), `coords` (its part of a sheet: a class
--       medallion's path -> the game's class circle), `flip` (an atlas pointing the other way from the set's icon:
--       turned over top to bottom), `rgb` (the picture tinted so: a class pin's blip; laid after the caller's colour,
--       taken away again by Skin.ClearIcon), `grow` and `inset` (a picture with a wide clear margin: a map pin draws it
--       this much bigger than the set's icon, with `inset` of each side cut off -- Skin.InsetPicture, MelloUI_Map's MapPins);
--       nil while the Default skin is off or the icon has no game twin (MelloUI's own then)
--   Skin.InsetPicture(tex, spec)   (qu-04) spec's atlas on tex without its clear margin (spec.inset of each side): the file
--       and its part of the sheet, as Flip lays one
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
-- (1.2.4, el-13) The skins, each picked whole, the same wherever it is picked (the installer's Skin step, Look >
-- General's Skin): its settings and the module switches it needs to show. Default and Modern are UI Modifications'
-- Skin, applied with the module on or off; Oldschool is MelloUI_Oldschool's painted reskin over Modern's parts, drawn
-- only while UI Modifications runs (Kit's Reskin), so that pick turns it on. A pick never turns a module off, and only
-- a pick lays a skin: a switch the player throws afterwards stays theirs. The user, 2026-10-30, on the Skin row: "One
-- row for all skins".
--------------------------------------------------------------------------------

Skin.SETS = {
	default = { [SWITCHES .. ".skin"] = "default", [SWITCHES .. ".reskin"] = false },
	modern = { [SWITCHES .. ".skin"] = "modern", [SWITCHES .. ".reskin"] = false },
	oldschool = { [SWITCHES .. ".skin"] = "modern", [SWITCHES .. ".reskin"] = true, ["!" .. SWITCHES] = true },
}

-- a skin that can be picked: Oldschool only while MelloUI_Oldschool is loaded and of this release
function Skin.Offered(name)
	if Skin.SETS[name] == nil then
		return false
	end
	return name ~= "oldschool" or MelloUI:OldschoolShipped() ~= nil
end

-- the skin in use: Oldschool while its painted reskin dresses, else the setting
function Skin.Current()
	return Reskinned() and "oldschool" or Skin.Name()
end

-- A player's pick: the set's settings that differ written in one Batch (a module that is off has its settings
-- written for its OnEnable to read), then the switches it needs turned on. Refused in a fight when it would switch
-- the painted reskin or a module (every painted skin at once: UI Modifications' SetAreas refuses that too). Returns
-- whether the skin was laid
function Skin.Pick(name)
	if not Skin.Offered(name) then
		return false
	end
	local set, writes, switches = Skin.SETS[name], {}, {}
	for spec, value in pairs(set) do
		local flag = spec:match("^!(.+)$")
		if flag then
			if value and not MelloUI:IsModuleEnabled(flag) then
				switches[#switches + 1] = flag
			end
		else
			local module, key = spec:match("^([^.]+)%.(.+)$")
			local db = MelloUI:GetModuleDB(module)
			if db and db[key] ~= value then
				writes[#writes + 1] = { module, key, value }
			end
		end
	end
	local refused = false
	if InCombatLockdown() then
		refused = #switches > 0
		for _, w in ipairs(writes) do
			refused = refused or (w[1] == SWITCHES and w[2] == "reskin")
		end
	end
	if refused then
		local um = MelloUI.modules[SWITCHES]
		MelloUI:Print(um and um.areasRefused or "Not in combat.")
		return false
	end
	MelloUI:Batch(function()
		for _, w in ipairs(writes) do
			MelloUI:NotifySettingChanged(w[1], w[2], w[3])
		end
	end)
	for _, flag in ipairs(switches) do
		MelloUI:SetModuleEnabled(flag, true)
	end
	return true
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
	-- (lk-12, stage 4) the game's tracker headers (Blizzard_ObjectiveTracker): the container's bar behind the title
	-- row (300 x 40) and a module's behind a section's heading (300 x 30), each drawn at its own size
	trackerHead = "UI-QuestTracker-Primary-Objective-Header",
	trackerSection = "UI-QuestTracker-Secondary-Objective-Header",
}

--------------------------------------------------------------------------------
-- The game's borders (NineSliceUtil's own layouts): the rims of MelloUI's windows and panels, the whisper bubbles
--------------------------------------------------------------------------------

local LAYOUT = { tooltip = "TooltipDefaultLayout", window = "Dialog", bubble = "ChatBubble" }
-- (NineSliceUtil's pieces by their keys on the border)
local BORDER_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
	"BottomEdge", "LeftEdge", "RightEdge" }
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
	-- (1.2.4, lk-11) its pieces under Dark Mode as MelloUI's own frame art: the kit's shade (Kit:RegisterTexture)
	local Kit = MelloUI.Kit
	if type(Kit) == "table" and Kit.RegisterTexture then
		for _, key in ipairs(BORDER_PIECES) do
			local piece = rawget(border, key)
			if type(piece) == "table" and piece.SetVertexColor then
				Kit:RegisterTexture(piece)
			end
		end
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
	-- (1.2.4, lk-11: at its Dark Mode brightness, as the palette's lines; laid again with the palette)
	local k = Skin.Dim(tex)
	tex:SetVertexColor(k, k, k, alpha or 1)
end

-- (lk-11) a piece's brightness under Dark Mode: its area's (Dark Mode's LevelOf, Modules/DarkMode.lua), 1 without it
function Skin.Dim(region)
	local modules = MelloUI.modules
	local dark = type(modules) == "table" and modules.DarkMode
	return type(dark) == "table" and dark.LevelOf and dark.LevelOf(region) or 1
end

--------------------------------------------------------------------------------
-- The game's window frame (lk-12, 2026-10-29; the user: "all of the custom windows that we made, the bags, chat,
-- quest tracker, whisper window etc needs to have its default look but retain the functionality"; their pick 6A of
-- default_windows_sketch): the game's portrait window, PortraitFrameBaseTemplate's NineSlice by its layout's name (the
-- bronze metal, the portrait's ring at the top left, the title bar along the top) and its round portrait under the
-- ring's edge, masked where the template masks it. ONE function for every own window that wears it: the own-window
-- shell (Kit:OwnWindow), the whisper window, the minimap panel. The owner keeps its own ground, title and close and
-- lays them where the template has its own (Skin.WindowTitle, Skin.WindowClose): never the game's UIPanelCloseButton,
-- which hides its parent through the game's panel system.
--   Skin.Window(frame[, opts]) -> win   a child frame of `frame` over its parts; opts.portrait false: the game's window
--       without a portrait (ButtonFrameTemplateNoPortrait); opts.level: its level over `frame`'s (Skin.WINDOW.level:
--       over the window's parts). win.portrait: the texture in the ring (nil without one)
--   Skin.WindowTitle(fs, frame)   a title on the bar, centred as the template's TitleText
--   Skin.WindowClose(button, frame)   a close button on the template's close's middle
--   Skin.WINDOW   the template's numbers, in UI units from the window's top left
--   Skin.CoinBox(parent) -> box   the game's coin box (the bag window's money frame), Skin.COIN its numbers
--------------------------------------------------------------------------------
Skin.WINDOW = {
	level = 60,                -- the border over the window's parts (the rims' level, MelloUI.Rims.T); the portrait one under
	bar = 26,                  -- the title bar's foot under the window's top (the top edge's dark band ends there)
	title = { 58, -24, -12 },  -- the title's left and right (TitleContainer, 58 / -24) and its middle under the top
	close = { -11, -12 },      -- the close's middle from the top right (UIPanelCloseButtonDefaultAnchors: 24 square at 1, 0)
	portrait = { size = 62, x = -5, y = 7, maskIn = 2, maskUp = 4 },   -- (PortraitContainer's portrait and CircleMask)
	clear = 59,                -- the portrait's foot under the window's top and a little room: content below it is clear
	out = { 13, 2, 16, 8 },    -- how far the corners reach past the window: left, right, top, bottom (the client's offsets)
}
local WINDOW_LAYOUT = { portrait = "PortraitFrameTemplate", plain = "ButtonFrameTemplateNoPortrait" }
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function Skin.Window(frame, opts)
	local T = Skin.WINDOW
	local portrait = not (opts and opts.portrait == false)
	local win = CreateFrame("Frame", nil, frame)
	win:SetAllPoints(frame)
	win:SetFrameLevel(frame:GetFrameLevel() + (opts and tonumber(opts.level) or T.level))
	win:EnableMouse(false)
	local Util = _G.NineSliceUtil
	if type(Util) == "table" and Util.ApplyLayoutByName then
		Util.ApplyLayoutByName(win, WINDOW_LAYOUT[portrait and "portrait" or "plain"])
	end
	-- (its pieces under Dark Mode as MelloUI's own frame art, as Skin.Border's)
	local Kit = MelloUI.Kit
	if type(Kit) == "table" and Kit.RegisterTexture then
		for _, key in ipairs(BORDER_PIECES) do
			local piece = rawget(win, key)
			if type(piece) == "table" and piece.SetVertexColor then
				Kit:RegisterTexture(piece)
			end
		end
	end
	if portrait then
		-- (under the ring's edge: a layer under the NineSlice's OVERLAY pieces, as the template's PortraitContainer
		-- under its NineSlice)
		-- (by its middle, so a game picture drawn smaller than the portrait -- never bigger than its own size,
		-- MelloUI.Icons -- stays in the ring's middle; the mask on the portrait's own rect)
		local p = T.portrait
		local tex = win:CreateTexture(nil, "ARTWORK")
		tex:SetSize(p.size, p.size)
		tex:SetPoint("CENTER", frame, "TOPLEFT", p.x + p.size / 2, p.y - p.size / 2)
		local mask = win:CreateMaskTexture()
		mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetPoint("TOPLEFT", frame, "TOPLEFT", p.x + p.maskIn, p.y)
		mask:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", p.x + p.size - p.maskIn, p.y - p.size + p.maskUp)
		tex:AddMaskTexture(mask)
		win.portrait = tex
	end
	return win
end

function Skin.WindowTitle(fs, frame)
	local t = Skin.WINDOW.title
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", frame, "TOPLEFT", t[1], t[3])
	fs:SetPoint("RIGHT", frame, "TOPRIGHT", t[2], t[3])
	fs:SetJustifyH("CENTER")
end

function Skin.WindowClose(button, frame)
	local c = Skin.WINDOW.close
	button:ClearAllPoints()
	button:SetPoint("CENTER", frame, "TOPRIGHT", c[1], c[2])
end

-- (lk-12, stage 2: the user's pick 1A, the bag window) the game's coin box: the bag window's money frame border
-- (ContainerFrameCurrencyBorderTemplate: its two ends 8 x 17, the middle between them, each laid as the game lays
-- them -- SetAtlas, no texel snapping bias -- the 2x art drawn at half). A child frame of `parent` the owner places;
-- Skin.COIN its height and where the game puts it on its window (8 in from the sides and the bottom)
Skin.COIN = { height = 17, cap = 8, inset = 8 }
local COIN_ART = { Left = "common-coinbox-left", Right = "common-coinbox-right", Middle = "_common-coinbox-center" }

function Skin.CoinBox(parent)
	local T = Skin.COIN
	local box = CreateFrame("Frame", nil, parent)
	box:SetHeight(T.height)
	box:EnableMouse(false)
	for key, atlas in pairs(COIN_ART) do
		local piece = box:CreateTexture(nil, "BACKGROUND")
		if piece.SetTexelSnappingBias then
			piece:SetTexelSnappingBias(0)
		end
		piece:SetAtlas(atlas)
		box[key] = piece
	end
	box.Left:SetSize(T.cap, T.height)
	box.Left:SetPoint("LEFT")
	box.Right:SetSize(T.cap, T.height)
	box.Right:SetPoint("RIGHT")
	box.Middle:SetPoint("TOPLEFT", box.Left, "TOPRIGHT")
	box.Middle:SetPoint("BOTTOMRIGHT", box.Right, "BOTTOMLEFT")
	return box
end

-- (lk-12, stage 5: the user's pick 2A, Chat View's channels as the game's chat tabs) the game's chat tab
-- (ChatTabArtTemplate, by its files): its two ends 16 x 32 and the middle between them tiled along, at the button's
-- foot as the template lays them; the selected three over them (ADD) while it is the open one; the highlight three in
-- the button's own HIGHLIGHT layer; the new-message glow along its foot (hidden: the owner flashes it). The art at the
-- game's own alphas: a selected tab's and another's under the pointer (CHAT_FRAME_TAB_*_MOUSEOVER_ALPHA)
--   Skin.ChatTab(button) -> art   on a Button of the owner's (its size the owner's, CHAT_TAB.height high);
--       art.Select(on), art.glow (the new-message glow texture), art.ground / art.on / art.lit (each its three pieces:
--       the owner hides them while its button is something else)
Skin.CHAT_TAB = { height = 32, cap = 16, glowIn = 8, labelY = -5 }

-- (lk-12, stages 5 and 6A's meter) the game's see-through chat box: its ground's alpha as the game draws its chat --
-- the player's own General window's (GetChatWindowInfo), else the game's default; nil where the client tells neither.
-- Chat View's box and the damage meter's list wear it under the Default skin. (ch-02) `id` another chat window's
-- (Chat View's open tab: each window its own, as the game's dock shows them); General's (1) when none is given
function Skin.ChatAlpha(id)
	local get = rawget(_G, "FCF_GetChatWindowInfo") or rawget(_G, "GetChatWindowInfo")
	local Num = MelloUI.Safe.Number
	local alpha
	if type(get) == "function" then
		local ok, _, _, _, _, _, a = pcall(get, id or 1)
		alpha = ok and Num(a) or nil
	end
	return alpha or Num(rawget(_G, "DEFAULT_CHATFRAME_ALPHA"))
end
local CHAT_TAB_FILE = "Interface\\ChatFrame\\ChatFrameTab-"

local function ChatTabThree(button, layer, kind, blend)
	local T = Skin.CHAT_TAB
	local l, m, r = button:CreateTexture(nil, layer), button:CreateTexture(nil, layer), button:CreateTexture(nil, layer)
	l:SetTexture(CHAT_TAB_FILE .. kind .. "Left")
	r:SetTexture(CHAT_TAB_FILE .. kind .. "Right")
	m:SetTexture(CHAT_TAB_FILE .. kind .. "Mid", "REPEAT", "CLAMP")
	m:SetHorizTile(true)
	l:SetSize(T.cap, T.height)
	r:SetSize(T.cap, T.height)
	m:SetHeight(T.height)
	l:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -2, 0)
	r:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, 0)
	m:SetPoint("LEFT", l, "RIGHT")
	m:SetPoint("RIGHT", r, "LEFT")
	if blend then
		l:SetBlendMode(blend)
		m:SetBlendMode(blend)
		r:SetBlendMode(blend)
	end
	return { l, m, r }
end

function Skin.ChatTab(button)
	local T = Skin.CHAT_TAB
	local art = { ground = ChatTabThree(button, "BACKGROUND", "BG") }
	art.on = ChatTabThree(button, "BORDER", "Selected", "ADD")
	art.lit = ChatTabThree(button, "HIGHLIGHT", "Highlight", "ADD")
	local glow = button:CreateTexture(nil, "BORDER")
	glow:SetTexture(CHAT_TAB_FILE .. "NewMessage")
	glow:SetBlendMode("ADD")
	glow:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", T.glowIn, 0)
	glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -T.glowIn, 0)
	glow:Hide()
	art.glow = glow
	local onAlpha = tonumber(rawget(_G, "CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA")) or 1
	local offAlpha = tonumber(rawget(_G, "CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA")) or onAlpha
	function art.Select(on)
		for _, piece in ipairs(art.on) do
			piece:SetShown(on and true or false)
		end
		for _, piece in ipairs(art.ground) do
			piece:SetAlpha(on and onAlpha or offAlpha)
		end
	end
	art.Select(false)
	return art
end

-- (lk-12, stage 6: the user's pick 3A, "A: Communities") the game's Guild & Communities pieces for the whisper window,
-- by name: the list column's ground (CommunitiesListFrameTemplate's Bg, its part of Interface\Common\bluemenu-main,
-- drawn into the column -- never bigger than its part -- and its foot's filigree at the column's width, its own
-- shape kept), a chosen row (the game's green nav button, pressed: CommunitiesListEntryMixin's Selection) and the
-- talk's inset (InsetFrameTemplate: the marble tiled at its own size, the inner border by its layout's name)
--   Skin.ListGround(frame, left, right) -> ground   textures on `frame` (BACKGROUND, over a fill at -8) between the
--       regions `left` (its top left) and `right` (its bottom right): ground.bg, ground.foot
--   Skin.ListRow(row) -> tex   the chosen row's picture on `row`, its own shape kept across the row's width
--   Skin.Inset(frame) -> inset   a child frame of `frame` (the owner places it) with the inner border; inset.marble
--       the marble on `frame` across it (shown and hidden by the owner with the inset)
Skin.LIST = {
	file = "Interface\\Common\\bluemenu-main",
	ground = { 0.00390625, 0.82421875, 0.18554688, 0.58984375 },   -- (211 x 414 px)
	foot = { 0.26171875, 0.984375, 0.06542969, 0.11914063 }, footW = 155, footH = 55, footIn = 14,
	row = "communities-nav-button-green-pressed", rowW = 224, rowH = 80,
	marble = "Interface\\FrameGeneral\\UI-Background-Marble",
}

function Skin.ListGround(frame, left, right)
	local T = Skin.LIST
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetTexture(T.file)
	bg:SetTexCoord(T.ground[1], T.ground[2], T.ground[3], T.ground[4])
	bg:SetPoint("TOPLEFT", left, "TOPLEFT")
	bg:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
	local foot = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	foot:SetTexture(T.file)
	foot:SetTexCoord(T.foot[1], T.foot[2], T.foot[3], T.foot[4])
	foot:SetPoint("BOTTOM", bg, "BOTTOM", 0, 1)
	-- (its shape kept, at the column's width or its own, whichever is less)
	function foot.Fit(width)
		local w = math.min(T.footW, math.max(1, (tonumber(width) or T.footW) - 2 * T.footIn))
		foot:SetSize(w, w * T.footH / T.footW)
	end
	foot.Fit()
	return { bg = bg, foot = foot }
end

function Skin.ListRow(row)
	local T = Skin.LIST
	local tex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	tex:SetAtlas(T.row)
	tex:SetPoint("LEFT", row, "LEFT")
	tex:SetPoint("RIGHT", row, "RIGHT")
	function tex.Fit(width)
		tex:SetHeight(math.min(T.rowH, (tonumber(width) or T.rowW) * T.rowH / T.rowW))
	end
	tex.Fit()
	tex:Hide()
	return tex
end

function Skin.Inset(frame)
	local inset = CreateFrame("Frame", nil, frame)
	inset:EnableMouse(false)
	-- (the marble on `frame` itself, over its fill and under all its children; the border on the inset's own frame)
	local marble = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	marble:SetTexture(Skin.LIST.marble, "REPEAT", "REPEAT")
	marble:SetHorizTile(true)
	marble:SetVertTile(true)
	marble:SetAllPoints(inset)
	inset.marble = marble
	local Util = _G.NineSliceUtil
	if type(Util) == "table" and Util.ApplyLayoutByName then
		Util.ApplyLayoutByName(inset, "InsetFrameTemplate")
	end
	return inset
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
	-- (2.1.0, qu-04; the user's yes: Default's doors "a little bigger") the game's door pictures fill half their frame
	-- (the solid swirl 0.54 of its 50 px; on screen the ring 6.7 px at 16, wowsim): a map pin draws them without their
	-- clear margin (`inset` of each side, Skin.InsetPicture) and a quarter bigger (`grow`): the ring about 13 px, as the other
	-- pins' pictures read, in a 20 px box that keeps clear of its neighbours (a 32 px box pushed the capitals aside)
	pin_dungeon = { atlas = "Dungeon", grow = 1.25, inset = 0.18 }, pin_raid = { atlas = "Raid", grow = 1.25, inset = 0.18 },
	pin_portal = { atlas = "PortalBlue" },
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
	-- (2.1.0, qu-04) the map's towns and merged pins' count: the client's own map pictures (its town icon, its quest
	-- map's number disc), where MelloUI's look lays palette pieces (MelloUI_Map's seal and badge). Not the capitals: the
	-- user, 2026-10-31, their emblems "all on the map with the ring around it" -- under Default too each capital wears
	-- its city's emblem in the gold seal, never the game's city tower
	map_town = { atlas = "poi-town" },
	map_count = { atlas = "UI-QuestPoi-QuestNumber" },
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
	-- (2.1.30; the user, 2026-11-09: "now we need icons to match them, for all 3 themes" -- "Default A")
	page_animations = "Spell_Holy_SurgeOfLight", page_buffs = "Spell_Holy_WordFortitude", page_map = "INV_Misc_Map02",
	page_supporters = "INV_Misc_Coin_01",
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

-- (2.1.0, qu-04) a party member's class pin (the set's class_<CLASS>, its colour baked in): the game's map draws a
-- member as its white blip in the class colour, so that, tinted (`rgb`, from the game's own class colours)
local classBlips = {}
MelloUI:On("colours", function()   -- (2.1.9: a colour picked on Look > Colours)
	wipe(classBlips)
end, "Skin: the class blips")

local function ClassBlip(class)
	local spec = classBlips[class]
	if spec == nil then
		local r, g, b = MelloUI.Colours.Class(class)
		spec = type(r) == "number" and { atlas = ICON.map_dot.atlas, rgb = { r, g, b } } or false
		classBlips[class] = spec
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
	local class = name and name:match("^class_(%u+)$")
	if class then
		return ClassBlip(class)
	end
	return name and ICON[name] or nil
end

local letters = setmetatable({}, { __mode = "k" })   -- [tex] = its letter (a channel key's)
local boxes = setmetatable({}, { __mode = "k" })     -- [tex] = the box under a ticked check box's mark
local cuts = setmetatable({}, { __mode = "k" })      -- [tex] = the round cut for a square icon (`round`; false: none)
local cutOn = setmetatable({}, { __mode = "k" })     -- [tex] = true while it is cut
local tinted = setmetatable({}, { __mode = "k" })    -- [tex] = true while a picture's own `rgb` colours it
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
	if tinted[tex] then
		tinted[tex] = nil
		tex:SetVertexColor(1, 1, 1)
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

-- (2.1.13: named Skin.Inset until now, which overwrote the whisper window's Skin.Inset(frame) above: under the Default skin
-- every open of that window raised an error, since 2.1.0)
function Skin.InsetPicture(tex, spec)
	local Num = MelloUI.Safe.Finite
	local k = Num(spec.inset)
	local info = spec.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(spec.atlas)
	local file = info and (info.file or info.filename)
	local l, r = info and Num(info.leftTexCoord), info and Num(info.rightTexCoord)
	local t, b = info and Num(info.topTexCoord), info and Num(info.bottomTexCoord)
	if k and file and l and r and t and b then
		local w, h = r - l, b - t
		tex:SetTexture(file)
		tex:SetTexCoord(l + w * k, r - w * k, t + h * k, b - h * k)
	end
end

function Skin.LayIcon(tex, spec)
	if spec.atlas then
		-- (the configurator walk, 2026-11-04: the Default skin's tick showed only its long stroke, shifted) a crop left on
		-- the texture by the other look (its picture's copy on a sheet) stays through SetAtlas: the whole of it first
		tex:SetTexCoord(0, 1, 0, 1)
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
	-- (its own colour over the caller's; a picture without one leaves the caller's as it is)
	local c = spec.rgb
	if c then
		tex:SetVertexColor(c[1], c[2], c[3])
	end
	tinted[tex] = c and true or nil
	Cut(tex, spec.round or false)
end
