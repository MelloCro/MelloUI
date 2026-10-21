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

function Icons.Path(icon)
	if type(icon) == "string" and not icon:find("\\", 1, true) then
		return DIR .. icon
	end
	return icon
end

-- the path's key in Media/IconSizes.lua's files (under Media, no extension), or nil: a file with no copies -- or the
-- list not loaded yet (it loads after this file: asked again then, nothing remembered)
local relOf = {}   -- [path under Media] = its key, or false
local function Rel(path)
	if type(path) ~= "string" or path:sub(1, #MEDIA) ~= MEDIA then
		return nil
	end
	local data = MelloUI.IconSizes
	if not (type(data) == "table" and type(data.files) == "table") then
		return nil
	end
	local rel = relOf[path]
	if rel == nil then
		rel = path:sub(#MEDIA + 1):gsub("%.[TtBb][GgLl][AaPp]$", "")
		if not data.files[rel] then
			rel = false
		end
		relOf[path] = rel
	end
	return rel or nil
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
	local rel = Rel(path)
	px = Finite(px)
	if not (rel and px and px > 0) then
		return nil
	end
	local data = MelloUI.IconSizes
	local sheet = data.sheets[data.files[rel]]
	for i = 1, #sheet do
		local c = sheet[i]
		if c[1] >= px * SLACK then
			return SIZES .. rel, c[2], c[3], c[1], floor(c[1] * (sheet.r or 1) + 0.5), sheet.w, sheet.h
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

-- tex drawn from the copy for its size; force: its file and part set even when they are the ones it had (a refit
-- that picks the same copy writes nothing). False while its size is unknown (the full file shown meanwhile)
local laying = false
local function Lay(tex, st, force)
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

function Icons.Set(tex, icon, units, l, r, t, b)
	local path = Icons.Path(icon)
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
	st.path, st.units = path, units
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
