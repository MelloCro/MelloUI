--------------------------------------------------------------------------------
-- MelloUI - Icons: every icon drawn from a copy made for its size (2026-10-21)
--
-- The user, 2026-10-21: "all icons and its borders should always stay
-- smooth" -- "i want this rule to be for all the icons in the UI". The client
-- draws an icon's file with its plain bilinear filter and no mipmaps (it mips
-- one only when asked for TRILINEAR, and that made thin lines a soft, dim ring
-- in game: docs/plans/chat-redesign.md, stage 0): a 64 px icon shrunk to 14
-- screen px reads one texel in five -- jagged edges, a gold ring sampled into
-- dots or lost. So each icon file of the families Tools/make_icon_sizes.py
-- builds (MelloUI's icon set, the class and faction medallions) ships a sheet
-- of copies besides, each made for its size, 12 to 96 px (its border at least
-- a pixel wide, scaled once with a good filter: Tools/icon_sizes.py; their
-- list in Media/IconSizes.lua). This draws the copy for the icon's size on
-- screen -- the smallest copy as big as the icon's screen pixels, so the game
-- never shrinks one by more than a step of the ladder (about 1.33x), which its
-- filter draws whole -- and picks again when the UI's scale, the screen, a
-- setting or a frame's place and scale (Edit Layout) changes.
-- One system for every icon (CLAUDE.md rule 5): W.Icon, W.IconMarkup,
-- W.RoundIcon, W.FrameArt's neighbours, the maps' pins, the World Marker ...
-- all come here: no code sets a file of a family on a texture itself (the
-- suite's v101/smoothicons checks it), and no code but this sets the texture
-- coordinates of a texture it holds (a crop goes through Icons.Set). Other
-- art put on a held texture (SetTexture, SetAtlas, SetColorTexture: a pooled
-- texture reused) lets it go, so no later fit paints over it.
--
--   Icons.DIR                       the icon set's folder (Media\Textures\Icons\)
--   Icons.Path(icon) -> path        an icon's full-size file: a name of the
--                                   set, or a path as it is
--   Icons.Pick(icon, px) -> path, left, right, top, bottom, copy
--                                   the file and the part of it to draw icon
--                                   px screen px wide: a copy on its sheet
--                                   (copy its size), or the full file
--                                   (0, 1, 0, 1; copy nil) past the copies,
--                                   for a file with none, or px unknown
--   Icons.Set(tex, icon[, units[, l, r, t, b]]) -> tex
--                                   tex shows icon from the copy for its size:
--                                   units its width in UI units (default:
--                                   tex's own, read now, else on the next
--                                   frame), l r t b the part of the icon shown
--                                   (0..1: a crop; the whole by default). Its
--                                   tint, alpha, blend and rotation are the
--                                   caller's. Fitted again on the changes above.
--                                   Any picture: one with no copies (a game
--                                   icon, a file id) is set as it is
--   Icons.Has(icon) -> true when the picture has copies
--   Icons.Fit(tex[, units])         tex's copy picked again now: its size or
--                                   its scale changed (a growing frame, the
--                                   World Marker's distance); units as Set's
--   Icons.Release(tex)              tex no longer an icon (a pooled texture
--                                   given other art)
--   Icons.Markup(icon, size[, region]) -> inline text markup, size x size of
--                                   the line's units, from the copy for that
--                                   size at region's scale (UIParent's)
--   Icons.PixelsPerUnit(region) -> the screen px a UI unit is at region's
--                                   scale (UIParent's for nil)
--   Icons.FloorScale(parent, units, px) -> the least scale a frame of `units`
--                                   inside `parent` may take and still be px
--                                   screen px: a shrinking icon's floor
-- Nothing at login: textures are fitted as they are set, the next frame's
-- pass asked of MelloUI.Schedule:NextFrame; the bus tells the changes.
--
-- A look's own set (1.2.4; the user's pick B of MelloUI-BuildData/output/
-- oldschool_icons_sketch, 2026-10-28: "B: painted"): Default shows the game's
-- pictures (MelloUI.Skin), Modern this set, Oldschool its own painted set while
-- its painted reskin is on -- one place (Icons.Path), no option: the look the
-- player picked picks the icons, as Custom Sounds' set picks the sounds. A set
-- registers itself as its addon loads (MelloUI_Oldschool's
-- Media/IconSizes.lua, written by Tools/make_icon_sizes.py --set oldschool);
-- a picture it has not drawn stays this set's.
--   Icons.AddSet(key, set)          set: root (its addon's Media folder, ending
--                                   in a backslash), area (a Kit area: shown
--                                   while Kit:IsOn(area)), square (its buttons
--                                   wear their own square frame: W.RoundIcon's
--                                   square mode), sheets and files (as
--                                   Media/IconSizes.lua's: its pictures under
--                                   root .. "Icons\\", their copies under
--                                   root .. "IconSizes\\"), halos ([name] =
--                                   true: its lifts, under its Icons\Halo\)
--   Icons.NameOf(icon) -> name      a picture's name in the sets (a name, or a
--                                   path in any set's folder), or nil
--   Icons.Showing(icon) -> set, name   the set showing that picture now (nil:
--                                   this one's)
--   Icons.Square(icon) -> true when the set showing it frames its buttons square
--   Icons.HaloPath(name) -> the lift's file for the picture as it shows now
-- The area switched ('look:<area>' on the bus): every held icon set again by
-- its name, then 'icons' fired (the round buttons, the lifts follow it).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Finite = MelloUI.Safe.Finite
local type, pairs, pcall, next = type, pairs, pcall, next
local floor = math.floor

local Icons = {}
MelloUI.Icons = Icons

local MEDIA = "Interface\\AddOns\\MelloUI\\Media\\"
local SIZES = MEDIA .. "IconSizes\\"
Icons.DIR = MEDIA .. "Textures\\Icons\\"
local DIR = Icons.DIR
-- a copy this much smaller than the icon's pixels is still taken (16.2 px: the 16 px copy, not the 20)
local SLACK = 0.98

-- the looks' own sets, in the order they registered (Icons.AddSet)
local sets = {}
Icons.sets = sets
local SET_ICONS = "Icons\\"   -- (a set's pictures, under its root; its files' keys begin so)
local EXT = "%.[TtBb][GgLl][AaPp]$"

function Icons.NameOf(icon)
	if type(icon) ~= "string" then
		return nil
	end
	if not icon:find("\\", 1, true) then
		return (icon:gsub(EXT, ""))
	end
	if icon:sub(1, #DIR) == DIR then
		return (icon:sub(#DIR + 1):gsub(EXT, ""))
	end
	for i = 1, #sets do
		local dir = sets[i].dir
		if icon:sub(1, #dir) == dir then
			return (icon:sub(#dir + 1):gsub(EXT, ""))
		end
	end
	return nil
end

-- the set's area on now (Kit:IsOn: read live, so a picture set before the first look pass is right too)
local function Shows(set)
	local Kit = rawget(MelloUI, "Kit")
	return type(Kit) == "table" and type(Kit.IsOn) == "function" and Kit:IsOn(set.area) == true
end

function Icons.Showing(icon)
	if sets[1] == nil then
		return nil
	end
	local name = Icons.NameOf(icon)
	if not name then
		return nil
	end
	for i = 1, #sets do
		local set = sets[i]
		if set.files[SET_ICONS .. name] and Shows(set) then
			return set, name
		end
	end
	return nil
end

function Icons.Path(icon)
	if type(icon) ~= "string" then
		return icon
	end
	local set, name = Icons.Showing(icon)
	if set then
		return set.dir .. name
	end
	if not icon:find("\\", 1, true) then
		return DIR .. icon
	end
	-- (a set's own path while the set is off: this set's picture again)
	if sets[1] ~= nil and icon:sub(1, #DIR) ~= DIR then
		name = Icons.NameOf(icon)
		if name then
			return DIR .. name
		end
	end
	return icon
end

function Icons.Square(icon)
	local set = Icons.Showing(icon)
	return set ~= nil and set.square == true
end

local HALO = DIR .. "Halo\\"
function Icons.HaloPath(name)
	local set, own = Icons.Showing(name)
	if set and set.halos[own] then
		return set.dir .. "Halo\\" .. own
	end
	return HALO .. (Icons.NameOf(name) or tostring(name))
end

-- the path's place in a list of copies: its key there (under its root, no extension), the list and its sheets'
-- folder -- MelloUI's (Media/IconSizes.lua, MelloUI.IconSizes) or a set's -- or nil: a file with no copies, or the
-- list not loaded yet (MelloUI's loads after this file: asked again then, nothing remembered)
local relOf = {}   -- [path] = { key, list, folder }, or false
local function Rel(path)
	if type(path) ~= "string" then
		return nil
	end
	local got = relOf[path]
	if got ~= nil then
		return got and got[1] or nil, got and got[2], got and got[3]
	end
	local root, data, folder
	if path:sub(1, #MEDIA) == MEDIA then
		root, data, folder = MEDIA, MelloUI.IconSizes, SIZES
		if not (type(data) == "table" and type(data.files) == "table") then
			return nil
		end
	else
		for i = 1, #sets do
			local set = sets[i]
			if path:sub(1, #set.root) == set.root then
				root, data, folder = set.root, set, set.root .. "IconSizes\\"
				break
			end
		end
		if not root then
			return nil
		end
	end
	local rel = path:sub(#root + 1):gsub(EXT, "")
	got = data.files[rel] and { rel, data, folder } or false
	relOf[path] = got
	return got and rel or nil, got and data, got and folder
end

-- a region's effective scale, or nil (none to read, or secret: a nameplate's)
local function ScaleOf(region)
	if region and region.GetEffectiveScale then
		local ok, v = pcall(region.GetEffectiveScale, region)
		v = ok and Finite(v) or nil
		if v and v > 0 then
			return v
		end
	end
	return nil
end

function Icons.PixelsPerUnit(region)
	local s = ScaleOf(region) or ScaleOf(UIParent) or 1
	local h = GetPhysicalScreenSize and Finite((select(2, GetPhysicalScreenSize()))) or nil
	return s * ((h and h > 0) and h or 768) / 768
end

-- the copy for px across: its sheet's path, its rect in sheet px (x, y, width, height: an oblong file's copies keep
-- its shape, the sheet's r) and the sheet's (w, h); nil when none fits
local function Copy(path, px)
	local rel, data, folder = Rel(path)
	px = Finite(px)
	if not (rel and px and px > 0) then
		return nil
	end
	local sheet = data.sheets[data.files[rel]]
	for i = 1, #sheet do
		local c = sheet[i]
		if c[1] >= px * SLACK then
			return folder .. rel, c[2], c[3], c[1], floor(c[1] * (sheet.r or 1) + 0.5), sheet.w, sheet.h
		end
	end
	return nil
end

function Icons.Pick(icon, px)
	local path = Icons.Path(icon)
	local file, x, y, cw, ch, w, h = Copy(path, px)
	if not file then
		return path, 0, 1, 0, 1, nil
	end
	return file, x / w, (x + cw) / w, y / h, (y + ch) / h, cw
end

-- the icons set: [tex] = { path, units (the caller's, or nil), l, r, t, b (the crop), file, copy }
local held = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })   -- set before their size could be read: fitted next frame
local everything = false                              -- every held one fitted next frame (a scale changed)

-- tex's width in UI units: the caller's, else its own (nil while unknown: no size yet, or secret)
local function Width(tex, units)
	units = Finite(units)
	if units and units > 0 then
		return units
	end
	local ok, w = pcall(tex.GetWidth, tex)
	w = ok and Finite(w) or nil
	return (w and w > 0) and w or nil
end

-- (1.2.4, the Default skin) a game picture never bigger than its own size ("every texture sharp"): a texture sized
-- on its own (one point, or none yet: sized before it is placed) is drawn at most at its atlas's size, in its shape,
-- about that point; the caller's size kept for the other look (st.size; a caller's new size taken as it comes)
local function Cap(tex, st, game)
	if not game.atlas then
		return
	end
	local okN, n = pcall(tex.GetNumPoints, tex)
	local okS, w, h = pcall(tex.GetSize, tex)
	w, h = okS and Finite(w), okS and Finite(h)
	if not (okN and n <= 1 and w and h and w > 0 and h > 0) then
		return
	end
	if not (st.capW == w and st.capH == h) then
		st.size = { w, h }   -- (the caller's: a size of its own since the last cap)
	end
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(game.atlas)
	local aw, ah = info and Finite(info.width), info and Finite(info.height)
	local cw, ch = st.size[1], st.size[2]
	if aw and ah and aw > 0 and ah > 0 then
		local s = math.min(1, cw / aw, ch / ah)
		cw, ch = aw * s, ah * s
	end
	st.capW, st.capH = cw, ch
	if cw ~= w or ch ~= h then
		tex:SetSize(cw, ch)
	end
end

-- (leaving the game's picture) the caller's size again
local function Uncap(tex, st)
	if st.size then
		tex:SetSize(st.size[1], st.size[2])
	end
	st.size, st.capW, st.capH = nil, nil, nil
end

-- tex drawn from the copy for its size; force: its file and part set even when they are the ones it had (a refit
-- that picks the same copy writes nothing). False while its size is unknown (the full file shown meanwhile)
local laying = false
local function Lay(tex, st, force)
	if st.game then
		Cap(tex, st, st.game)
		return true   -- (the Default skin's game picture: no copies to pick, MelloUI.Skin laid it)
	end
	local units = Width(tex, st.units)
	local file, l, r, t, b, copy = Icons.Pick(st.path, units and units * Icons.PixelsPerUnit(tex))
	if not force and st.file == file and st.copy == copy then
		return units ~= nil
	end
	if force or st.file ~= file then
		laying = true
		tex:SetTexture(file)
		laying = false
		st.file = file
	end
	st.copy = copy
	local w, h = r - l, b - t
	tex:SetTexCoord(l + st.l * w, l + st.r * w, t + st.t * h, t + st.b * h)
	return units ~= nil
end

-- other art put on a held texture by anything but this (a pooled texture reused, a painted look's plate): it is no
-- icon any more, so no fit paints over it (hooked once per texture, the first time it is set)
local hooked = setmetatable({}, { __mode = "k" })
local function Foreign(tex)
	if not laying then
		held[tex], pending[tex] = nil, nil
	end
end
local function Watch(tex)
	if not hooked[tex] then
		hooked[tex] = true
		hooksecurefunc(tex, "SetTexture", Foreign)
		hooksecurefunc(tex, "SetAtlas", Foreign)
		hooksecurefunc(tex, "SetColorTexture", Foreign)
	end
end

local function FitPending()
	if everything then
		everything = false
		for tex, st in pairs(held) do
			pending[tex] = nil
			Lay(tex, st, false)
		end
	end
	local tex = next(pending)
	while tex do
		pending[tex] = nil
		local st = held[tex]
		if st then
			Lay(tex, st, false)   -- (still unknown: the full file stays until the next change or Fit)
		end
		tex = next(pending)
	end
end

-- the next frame's pass: the shared scheduler's (Core/Schedule.lua: one timer a frame however often asked); a world
-- without it fits at once
local function Wake()
	local S = MelloUI.Schedule
	if type(S) == "table" and S.NextFrame then
		S:NextFrame(Icons, FitPending)
	else
		FitPending()
	end
end

-- (1.2.4, the Default skin: MelloUI.Skin) an icon of the set with a game picture for it shows that picture while the
-- Default skin is on -- kept here with its name, so a switch lays the other look again (the bus's 'skin')
local function SetGame(tex, icon, units, l, r, t, b, game)
	local st = held[tex]
	if not st then
		st = {}
		held[tex] = st
		Watch(tex)
	end
	st.icon, st.units, st.game, st.file, st.copy = icon, units, game, nil, nil
	st.l, st.r, st.t, st.b = l or 0, r or 1, t or 0, b or 1
	pending[tex] = nil
	laying = true
	MelloUI.Skin.LayIcon(tex, game)
	laying = false
	Cap(tex, st, game)
	return tex
end

function Icons.Set(tex, icon, units, l, r, t, b)
	local Skin = rawget(MelloUI, "Skin")
	local game = Skin and Skin.Icon(icon)
	if game then
		return SetGame(tex, icon, units, l, r, t, b, game)
	end
	local path = Icons.Path(icon)
	local was = held[tex]
	if was and was.game then
		was.game = nil
		Skin.ClearIcon(tex)
		Uncap(tex, was)
	end
	if not Rel(path) then
		-- (a picture with no copies: a game icon, a file id, a file of another folder -- as it is; Foreign lets go of a
		-- held texture)
		tex:SetTexture(path)
		tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
		return tex
	end
	local st = held[tex]
	if not st then
		st = {}
		held[tex] = st
		Watch(tex)
	end
	st.path, st.units, st.icon = path, units, icon
	st.l, st.r, st.t, st.b = l or 0, r or 1, t or 0, b or 1
	if not Lay(tex, st, true) then
		pending[tex] = true
		Wake()
	end
	return tex
end

-- whether the picture has copies (a file of a family: the set, the medallions)
function Icons.Has(icon)
	return Rel(Icons.Path(icon)) ~= nil
end

function Icons.Fit(tex, units)
	local st = held[tex]
	if st then
		if units ~= nil then
			st.units = units
		end
		Lay(tex, st, false)
	end
end

function Icons.Release(tex)
	held[tex], pending[tex] = nil, nil
end

function Icons.Markup(icon, size, region)
	size = floor((Finite(size) or 14) + 0.5)
	local Skin = rawget(MelloUI, "Skin")
	local game = Skin and Skin.Icon(icon)
	if game and game.atlas then
		return "|A:" .. game.atlas .. ":" .. size .. ":" .. size .. "|a"
	elseif game then
		return "|T" .. game.file .. ":" .. size .. ":" .. size .. ":0:0:64:64:4:60:4:60|t"
	end
	local path = Icons.Path(icon)
	local file, x, y, cw, ch, w, h = Copy(path, size * Icons.PixelsPerUnit(region))
	if not file then
		return "|T" .. path .. ":" .. size .. ":" .. size .. "|t"
	end
	return "|T" .. file .. ":" .. size .. ":" .. size .. ":0:0:" .. w .. ":" .. h .. ":" .. x .. ":" .. (x + cw) .. ":"
		.. y .. ":" .. (y + ch) .. "|t"
end

function Icons.FloorScale(parent, units, px)
	units = Finite(units)
	if not units or units <= 0 then
		return 0
	end
	return (Finite(px) or 0) / (units * Icons.PixelsPerUnit(parent))
end

-- every icon fitted again on the next frame: the UI's scale or the screen (the bus's 'scale', Core/Schedule.lua's one
-- watcher), a setting (a module's scale) or a frame's place and scale (Edit Layout) changed
local function FitAll()
	if next(held) then
		everything = true
		Wake()
	end
end
MelloUI:On("scale", FitAll, Icons)
MelloUI:On("setting", FitAll, Icons)
MelloUI:On("mover", FitAll, Icons)

-- every held icon set again by its name, in the look on show now
local function SetAgain()
	local list = {}
	for tex, st in pairs(held) do
		if st.icon ~= nil then
			list[#list + 1] = tex
		end
	end
	for i = 1, #list do
		local tex = list[i]
		local st = held[tex]
		if st then
			Icons.Set(tex, st.icon, st.units, st.l, st.r, st.t, st.b)
		end
	end
end

-- (1.2.4) the skin switched (MelloUI.Skin): in the skin's look now
MelloUI:On("skin", SetAgain, Icons)

-- (1.2.4) a set's area switched (its look on or off, the modules restarted: a profile loaded): its pictures or this
-- set's, then the round buttons and the lifts told ('icons')
local function Switched()
	SetAgain()
	MelloUI:Fire("icons")
end

local listening = {}   -- [area] = true once its topic is heard
function Icons.AddSet(key, set)
	if type(key) ~= "string" or type(set) ~= "table" or type(set.root) ~= "string" or type(set.area) ~= "string"
		or type(set.files) ~= "table" or type(set.sheets) ~= "table" then
		error("Icons.AddSet: a key and { root, area, sheets, files } wanted", 2)
	end
	set.key, set.dir = key, set.root .. SET_ICONS
	set.halos = type(set.halos) == "table" and set.halos or {}
	for i = 1, #sets do
		if sets[i].key == key then
			sets[i] = set
			relOf = {}
			return set
		end
	end
	sets[#sets + 1] = set
	relOf = {}   -- (a path under its root may have been asked before: no copies then)
	if not listening[set.area] then
		listening[set.area] = true
		MelloUI:On("look:" .. set.area, Switched, Icons)
		if not listening.restart then
			listening.restart = true
			MelloUI:On("restart", Switched, Icons)
		end
	end
	return set
end
