--------------------------------------------------------------------------------
-- MelloUI - Kit
--
-- The painted UI kit (Media/Kit, described by Media/KitLayout.lua, naming per
-- docs/UI-KIT.md) as building blocks for the panel modules: a nine-slice
-- window, cap/mid/cap strips with states, bars with a trough and a fill area,
-- icon slots whose rim sits over the icon, and the replacement library
-- (Kit.Replacements + Kit:Replace) that maps the game's art to those blocks
-- so a panel never chooses a piece itself. A replacement takes the game
-- art's rectangle, size, visibility AND place in the draw order (strata,
-- frame level, layer): check all of them before mapping. Not a module with settings; other
-- modules use MelloUI.Kit. `/kitdemo [scale]` shows every block in one window.
--
-- Files are 2x art; Kit.scale is how many UI units one file pixel covers
-- (0.375 = the "1x is 0.75 UI units" rule the painted bars use).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local LAYOUT = MelloUI_KitLayout
local PIECES = LAYOUT and LAYOUT.pieces or {}
local ROOT = LAYOUT and LAYOUT.root or "Interface\\AddOns\\MelloUI\\Media\\Kit\\"

local Kit = { scale = 0.375 }
MelloUI.Kit = Kit

-- The kit's colours (user, 2026-09-23: "We can make A and B and let the users
-- select when in game"): the pieces as painted (Media\Kit) or recoloured to
-- the palette by Tools/kit_palette.py, one folder per look holding the same
-- files, so the layout is shared. Pictures and the tiles already warm are not
-- recoloured: every look reads them from Media\Kit (kit_palette's SKIP).
Kit.colourLooks = {
	{ value = "warm", label = "Warm iron", folder = "KitWarm" },
	{ value = "bronze", label = "Bronze", folder = "KitBronze" },
	{ value = "painted", label = "Original (painted)" },
}
local LOOK_ROOT = {}
for _, look in ipairs(Kit.colourLooks) do
	LOOK_ROOT[look.value] = look.folder and (ROOT:gsub("Kit\\$", look.folder .. "\\")) or ROOT
end
local UNCOLOURED = { "^backdrops/", "^cards/", "^icons/", "^tiles/vellum", "^tiles/parchment", "^tiles/leather", "^tiles/quilt_", "^tiles/crackle" }
local lookRoot = nil   -- the chosen look's folder, once the settings are there

-- The folder a piece is read from in the chosen look
local function PieceRoot(name)
	if not lookRoot then
		local um = MelloUI:GetModule("UIModifications")
		if not (um and um.db and Kit.BorderValue) then
			return LOOK_ROOT.warm   -- the default look, until the settings are loaded
		end
		lookRoot = LOOK_ROOT[Kit:BorderValue("colours")] or ROOT
	end
	if lookRoot == ROOT then
		return ROOT
	end
	for _, pattern in ipairs(UNCOLOURED) do
		if name:find(pattern) then
			return ROOT
		end
	end
	return lookRoot
end

local STATES = { "normal", "hover", "pressed", "checked", "disabled", "plain", "open", "closed", "selected", "focused", "off", "on", "title" }

-- this client hands out secret numbers under unit frames: never compare one
local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

--------------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------------

function Kit:Piece(name)
	return PIECES[name]
end

--------------------------------------------------------------------------------
-- Preload (user, 2026-09-23: "for a split it waits for the artwork to load in
-- ... can we make it so that it load everything at the loading screen?").
-- The client loads a texture file the first time something asks for it and
-- draws nothing until it is in, so a window's first open after a reload (the
-- professions' cards and parchment, above all) showed its art popping in. One
-- holder texture per file, set during the loading screen and kept, has every
-- file in memory before any window asks. The holder is shown but fully
-- transparent and 1 px: nothing to see, nothing to click.
--------------------------------------------------------------------------------

local preload

--------------------------------------------------------------------------------
-- Painted edges (user, 2026-09-23: pick B "dry brush" of
-- kit_raw/edge_mask_catalog.png, on the spell book's parchment pages). Two
-- masks on one texture: the corner mask, rough along its left and top sides,
-- at the texture's top-left, and its 180-degree twin at the bottom-right, so
-- all four sides of the texture end in bristle strokes. Each mask is at least
-- 512 UI units square (the file's size, the strokes 18 units deep) and grows
-- with a larger texture. Made by Tools/make_edge_mask.py.
--------------------------------------------------------------------------------

local EDGE_ROOT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Masks\\"
local EDGE_SIZE = 512
Kit.edgeMasks = { EDGE_ROOT .. "edge_brush_tl", EDGE_ROOT .. "edge_brush_br" }
-- the same strokes a third as deep, for a wide panel whose text runs close to
-- its edge (the chat windows)
Kit.edgeMasksFine = { EDGE_ROOT .. "edge_brush_fine_tl", EDGE_ROOT .. "edge_brush_fine_br" }
-- deep strokes on the left and right, shallow ones top and bottom (a chat
-- window's grown backdrop)
Kit.edgeMasksWide = { EDGE_ROOT .. "edge_brush_wide_tl", EDGE_ROOT .. "edge_brush_wide_br" }

local EdgeMixin = {}

-- Size and place the two masks for a texture of w x h on `anchor`.
function EdgeMixin:Fit(w, h)
	local sizeX, sizeY = EDGE_SIZE, EDGE_SIZE
	if w and h and not Secret(w) and not Secret(h) then
		if self.tight then
			-- `tight`: the masks at the texture's own size, so a small panel
			-- gets shorter strokes in proportion (a 340-wide popup: about 12)
			sizeX = math.max(w, h)
			sizeY = sizeX
		else
			-- each way at least the texture's own length: a tall panel (the
			-- objective tracker) stretches the masks up and down only, so its
			-- side strokes keep their depth
			sizeX, sizeY = math.max(EDGE_SIZE, w), math.max(EDGE_SIZE, h)
		end
	end
	local tl, br = self.masks[1], self.masks[2]
	tl:ClearAllPoints()
	br:ClearAllPoints()
	if self.mirror then
		-- flipped left-right: rough on the top and right, then bottom and left
		tl:SetPoint("TOPRIGHT", self.anchor, "TOPRIGHT")
		br:SetPoint("BOTTOMLEFT", self.anchor, "BOTTOMLEFT")
	else
		tl:SetPoint("TOPLEFT", self.anchor, "TOPLEFT")
		br:SetPoint("BOTTOMRIGHT", self.anchor, "BOTTOMRIGHT")
	end
	tl:SetSize(sizeX, sizeY)
	br:SetSize(sizeX, sizeY)
end

-- Rough painted edges on `tex` (a texture filling `anchor`); `mirror` flips
-- the strokes left-right (a left page, so it is not the right page's twin);
-- `tight` scales the strokes with a panel smaller than the masks' 512 units;
-- `fine` uses the shallow strokes (Kit.edgeMasksFine), or "wide" the deep-
-- sided, shallow-topped ones (Kit.edgeMasksWide).
-- Returns the edge (edge:Fit(w, h) once the size is known), or nil where the
-- client has no masks.
function Kit:PaintedEdge(tex, anchor, mirror, tight, fine)
	local owner = tex and tex:GetParent()
	if not (owner and owner.CreateMaskTexture and tex.AddMaskTexture) then
		return nil
	end
	local edge = Mixin({ tex = tex, anchor = anchor or tex, mirror = mirror, tight = tight, masks = {} }, EdgeMixin)
	local set = (fine == "wide" and self.edgeMasksWide) or (fine and self.edgeMasksFine) or self.edgeMasks
	for i, path in ipairs(set) do
		local m = owner:CreateMaskTexture()
		m:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		if mirror then
			pcall(m.SetTexCoord, m, 1, 0, 0, 1)
		end
		edge.masks[i] = m
		tex:AddMaskTexture(m)
	end
	edge:Fit()
	return edge
end

-- A parchment sheet laid on a railed panel's stone (a Kit:NineSlice skin),
-- inside its rails, ending in the painted edge (user, 2026-09-23: the
-- objective tracker, the whisper popup, the chat windows and the damage meter:
-- "leave the background how it was and the borders, but add the parchment
-- layer on top of that and mask it"). It lies in the skin's own layer stack
-- between the stone (BACKGROUND 0) and the rails, a little stone showing
-- between the rails and its strokes; darkened as aged paper, so white and
-- yellow text stays readable on it; the picture cropped to the sheet's shape,
-- never stretched, again whenever `watch` (the frame whose size the skin
-- follows) changes size.
--   opts: margin (6; less than 0 reaches out under the rails), tint
--         { r, g, b }, tight / fine / wide (see PaintedEdge), layer
--         ("BACKGROUND") and sublevel (3); rect: lay it on this instead of
--         inside the skin's rails (a chat window, whose rails stand outside
--         its body), `margin` in from each side; piece (Kit.parchmentPiece)
-- ONE tone for every parchment in the kit (user, 2026-09-23: "a lot of
-- inconsistencies in the brightness of the parchment background" -- the added
-- sheets were tinted to 60 % as aged paper, the pages kept the picture's own
-- light, 112 against 191; pick B of kit_raw/parchment_tone_catalog.png, about
-- 146: white chat and tracker text reads with its shadow, dark ink too).
Kit.parchmentTint = { 0.80, 0.74, 0.64 }
-- the parchment as a tile cut from the page's middle (tiles/vellum, as
-- bright on average as the whole page was): a sheet of any size shows it at
-- the UI's one background resolution, never a stretched picture
Kit.parchmentPiece = "tiles/vellum"

-- Each area's sheets on a switch of its own (user, 2026-09-23: "some people
-- like it, some dont, off by default"): UI Modifications' parchment_<area>
-- settings. opts.area names the area; opts.alive, when given, says whether
-- the sheet's own frame is dressed at all (a sheet that is the chat window's
-- region, not the skin's, shows only while the chat reskin is on).
Kit.parchmentSheets = {}   -- [area] = { { sheet, alive }, ... }

function Kit:ParchmentOn(area)
	if not area then
		return true
	end
	local um = MelloUI:GetModule("UIModifications")
	local db = um and um.db
	return (db and db["parchment_" .. area] == true) and true or false
end

function Kit:SetParchment(area, on)
	for _, entry in ipairs(self.parchmentSheets[area] or {}) do
		entry.sheet:SetShown((on and (not entry.alive or entry.alive())) and true or false)
	end
end

function Kit:ParchmentSheet(skin, watch, opts)
	opts = opts or {}
	if not (skin and skin.CreateTexture) then
		return nil
	end
	local margin = opts.margin or 6
	local sheet = skin:CreateTexture(nil, opts.layer or "BACKGROUND", nil, opts.sublevel or 3)
	if opts.rect then
		sheet:SetPoint("TOPLEFT", opts.rect, "TOPLEFT", margin, -margin)
		sheet:SetPoint("BOTTOMRIGHT", opts.rect, "BOTTOMRIGHT", -margin, margin)
	else
		local pre = self.framePrefix
		sheet:SetPoint("TOPLEFT", skin, "TOPLEFT", self:RailInset(pre .. "_l", "l") + margin, -(self:RailInset(pre .. "_t", "t") + margin))
		sheet:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -(self:RailInset(pre .. "_r", "r") + margin), self:RailInset(pre .. "_b", "b") + margin)
	end
	-- opts.piece: another parchment tile than the kit's (the character
	-- window's Window Background Parchment keeps the tile it was chosen as;
	-- user, 2026-09-24)
	if not self:Apply(sheet, opts.piece or self.parchmentPiece) then
		sheet:Hide()
		return nil
	end
	sheet.kitAlign = "center"
	local tint = opts.tint or self.parchmentTint
	sheet:SetVertexColor(tint[1], tint[2], tint[3])
	local edge = self:PaintedEdge(sheet, sheet, opts.mirror, opts.tight, opts.wide and "wide" or opts.fine)
	local function Fit()
		local ok, w, h = pcall(sheet.GetSize, sheet)
		if not (ok and w and h) or Secret(w) or Secret(h) or w <= 0 or h <= 0 then
			return
		end
		self:Retile(sheet)
		if edge then
			edge:Fit(w, h)
		end
	end
	watch = watch or skin
	if watch.HookScript then
		watch:HookScript("OnSizeChanged", Fit)
		watch:HookScript("OnShow", Fit)
	end
	Fit()
	if opts.area then
		local list = self.parchmentSheets[opts.area] or {}
		self.parchmentSheets[opts.area] = list
		list[#list + 1] = { sheet = sheet, alive = opts.alive }
		sheet:SetShown((self:ParchmentOn(opts.area) and (not opts.alive or opts.alive())) and true or false)
	end
	return sheet, edge
end

-- Every file the kit draws from, as full paths, each once (the painted-edge
-- masks with them).
function Kit:KitFiles()
	local files, seen = {}, {}
	for _, list in ipairs({ self.edgeMasks, self.edgeMasksFine, self.edgeMasksWide }) do
		for _, path in ipairs(list) do
			files[#files + 1] = path
		end
	end
	for name, p in pairs(PIECES) do
		local file = p.file and PieceRoot(name) .. p.file
		if file and not seen[file] then
			seen[file] = true
			files[#files + 1] = file
		end
	end
	table.sort(files)
	return files
end

-- Hold these files (full paths) in memory; nil or an empty list lets every
-- one go again. Returns how many are held.
function Kit:Preload(files)
	files = files or {}
	if #files == 0 and not preload then
		return 0
	end
	if not preload then
		preload = CreateFrame("Frame", nil, UIParent)
		preload:SetSize(1, 1)
		preload:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		preload:SetAlpha(0)
		preload:EnableMouse(false)
		preload.textures = {}
	end
	for i, path in ipairs(files) do
		local tex = preload.textures[i]
		if not tex then
			tex = preload:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints(preload)
			preload.textures[i] = tex
		end
		tex:SetTexture(path)
	end
	for i = #files + 1, #preload.textures do
		preload.textures[i]:SetTexture(nil)
	end
	preload.count = #files
	preload:SetShown(#files > 0)
	return #files
end

-- How many files are held, and how many the client reports as loaded (nil
-- when this client cannot say).
function Kit:PreloadStatus()
	if not (preload and preload.count and preload.count > 0) then
		return 0, nil
	end
	local loaded
	for i = 1, preload.count do
		local tex = preload.textures[i]
		if tex.IsObjectLoaded then
			local ok, yes = pcall(tex.IsObjectLoaded, tex)
			if ok and not Secret(yes) then
				loaded = (loaded or 0) + (yes and 1 or 0)
			end
		end
	end
	return preload.count, loaded
end

-- Size of a piece on screen, in UI units.
function Kit:Size(name, scale)
	local p = PIECES[name]
	if not p then
		return 0, 0
	end
	scale = scale or self.scale
	return p.w * scale, p.h * scale
end

-- The transparent interior of a hollow piece as insets from its edges
-- (left, right, top, bottom) in UI units; nil when the piece has none.
function Kit:Insets(name, scale)
	local p = PIECES[name]
	if not p or not p.open then
		return nil
	end
	scale = scale or self.scale
	local o = p.open
	return o[1] * scale, (p.w - o[3]) * scale, o[2] * scale, (p.h - o[4]) * scale
end

-- The kit's title face (user, 2026-09-21: "Enchanted Land", titles and
-- headers ONLY — window title plates, the tracker's and the damage meter's
-- headers, the minimap's zone band; body text, names, numbers and chat stay
-- the game's). `Kit:TitleFont(fs, true)` puts it on a FontString at the
-- string's own size and flags (remembered, restored with `false`); a string
-- whose font reads secret is left alone. The face itself is the Fonts
-- module's "Titles & headers" choice (user, 2026-09-22: it was hard-coded
-- here and the setting changed nothing on the plates): `Kit:SetTitleFace`
-- takes a path, `false` for the game's own face on the plates ("Keep the
-- game's"), or nil for the default, Enchanted Land.
Kit.defaultTitleFont = "Interface\\AddOns\\MelloUI\\Media\\Fonts\\EnchantedLand.ttf"
Kit.titleFont = Kit.defaultTitleFont
Kit.titleFontScale = 1.5   -- user, 2026-09-21: the face at 1.5 x the string's size (a custom face only; the game's own keeps its size)
Kit.titleSizeFactor = 1    -- the Fonts module's "Titles & headers size" slider (user, 2026-09-22: it did nothing on the plates)
local titleStrings = setmetatable({}, { __mode = "k" })   -- every string in the title face, for a re-size

-- The slider's factor; every title string re-set at the new size.
function Kit:SetTitleSizeFactor(factor)
	factor = tonumber(factor) or 1
	if math.abs(factor - (self.titleSizeFactor or 1)) < 0.001 then
		return
	end
	self.titleSizeFactor = factor
	for fs in pairs(titleStrings) do
		if fs.melloFontSaved then
			self:TitleFont(fs, true)
		end
	end
end

-- The face on every title string: a path, false (the game's own), nil
-- (the default). Every string in the title face is re-set.
function Kit:SetTitleFace(face)
	if face == nil then
		face = self.defaultTitleFont
	end
	if face == self.titleFont then
		return
	end
	self.titleFont = face
	for fs in pairs(titleStrings) do
		if fs.melloFontSaved then
			fs.melloFontTries = nil
			self:TitleFont(fs, true)
		end
	end
end

function Kit:TitleFont(fs, on)
	if not (fs and fs.GetFont and fs.SetFont) then
		return
	end
	if on then
		if not fs.melloFontSaved then
			local ok, path, size, flags = pcall(fs.GetFont, fs)
			if not ok or Secret(path) or Secret(size) or not (size and size > 0) then
				return
			end
			fs.melloFontSaved = { path, size, flags or "" }
		end
		local saved = fs.melloFontSaved
		titleStrings[fs] = true
		-- SetFont answers false when the face cannot be used yet (the file
		-- is read on first use; a string fonted during loading lost its text
		-- — the tracker's "All Objectives" came up blank, 2026-09-21): then
		-- the game's font goes back at once and the face is tried again a
		-- moment later, a few times
		local face = self.titleFont or saved[1]
		local scale = self.titleFont and (self.titleFontScale or 1) or 1
		local okSet, applied = pcall(fs.SetFont, fs, face, saved[2] * scale * (self.titleSizeFactor or 1), saved[3])
		if not (okSet and applied) then
			pcall(fs.SetFont, fs, saved[1], saved[2], saved[3])
			fs.melloFontTries = (fs.melloFontTries or 0) + 1
			if fs.melloFontTries <= 8 and C_Timer and C_Timer.After then
				C_Timer.After(1, function()
					if fs.melloFontSaved then
						Kit:TitleFont(fs, true)
					end
				end)
			end
		else
			fs.melloFontTries = nil
		end
	elseif fs.melloFontSaved then
		local saved = fs.melloFontSaved
		fs.melloFontSaved = nil
		fs.melloFontTries = nil
		titleStrings[fs] = nil
		fs:SetFont(saved[1], saved[2], saved[3])
	end
end

-- Every kit texture is registered here, so Dark Mode can darken the painted
-- interface as one (user, 2026-09-21: Dark Mode darkens the modified UI
-- while it is on, the default art while it is off). `Kit:SetShade(s)` puts
-- s x the texture's own tint on each piece; tints set later by the modules
-- (a lit tab, the target's gold bracket, a hover) go through the same
-- multiplier: a SetVertexColor post-hook remembers the tint as the BASE and
-- re-applies it shaded. Only the brightness is touched, never the hue: the
-- red gems stay red.
Kit.shade = 1
local SHADED = setmetatable({}, { __mode = "k" })

local function ShadeTexture(tex)
	local base = tex.kitBase
	local r, g, b = 1, 1, 1
	if base then
		r, g, b = base[1], base[2], base[3]
	end
	local k = Kit.shade
	tex.kitShading = true
	tex:SetVertexColor(r * k, g * k, b * k)
	tex.kitShading = nil
end

function Kit:RegisterTexture(tex)
	if SHADED[tex] then
		return
	end
	SHADED[tex] = true
	hooksecurefunc(tex, "SetVertexColor", function(t, r, g, b)
		if t.kitShading then
			return
		end
		t.kitBase = { r or 1, g or 1, b or 1 }
		if Kit.shade < 1 then
			ShadeTexture(t)
		end
	end)
	if self.shade < 1 then
		ShadeTexture(tex)
	end
end

function Kit:SetShade(shade)
	shade = tonumber(shade) or 1
	if shade < 0 then
		shade = 0
	elseif shade > 1 then
		shade = 1
	end
	if math.abs(shade - self.shade) < 0.001 then
		return
	end
	self.shade = shade
	for tex in pairs(SHADED) do
		ShadeTexture(tex)
	end
end

-- Put a piece on an existing texture. Repeatable pieces get the REPEAT wrap
-- mode; call Kit:Retile(tex) whenever their size changes.
-- BACKGROUNDS keep one resolution across the whole UI (user, 2026-09-23:
-- "Scaling something should not stretch the Background artwork, it should
-- dynamically expand it and the background resolution should stay
-- persistant across the whole UI"): a background piece (a tile, a window's
-- stone body) repeats at Kit.scale UI units per piece px of the SCREEN
-- (UIParent's scale), whatever the scale of the frame it is on and whatever
-- scale its caller asked for. A bigger or scaled-up frame shows more of it,
-- never a bigger copy. The page pictures were replaced by tiles cut from
-- their middles (tiles/concrete, tiles/vellum) for this: a picture can only
-- be fitted by stretching. `tex.kitOwnScale`: a texture that keeps its
-- caller's scale (the picker's small previews).
local BACKGROUNDS = setmetatable({}, { __mode = "k" })   -- every background texture, to lay again when scales change

local function IsBackground(name)
	return name:find("^tiles/") ~= nil or name:find("_body$") ~= nil
end

function Kit:Apply(tex, name)
	local p = PIECES[name]
	if not p then
		tex:SetTexture(nil)
		tex.kitPiece, tex.kitName = nil, nil
		return false
	end
	if p.tile then
		tex:SetTexture(PieceRoot(name) .. p.file, "REPEAT", "REPEAT")
	else
		tex:SetTexture(PieceRoot(name) .. p.file)
	end
	tex:SetTexCoord(p.uv[1], p.uv[2], p.uv[3], p.uv[4])
	tex.kitPiece, tex.kitName = p, name
	tex.kitBackground = (p.tile and IsBackground(name)) or nil
	if tex.kitBackground then
		BACKGROUNDS[tex] = true
	end
	self:RegisterTexture(tex)
	if p.tile then
		self:Retile(tex)
	end
	return true
end

-- Kit Colours changed: every kit texture shown again from the chosen look's
-- folder, where it is (its texture coordinates -- a strip's tiling, a mirror,
-- a crop -- kept as they are)
function Kit:SetKitColours(value)
	lookRoot = LOOK_ROOT[value] or ROOT
	for tex in pairs(SHADED) do
		local p, name = tex.kitPiece, tex.kitName
		if p and name and p.file then
			local coords = { tex:GetTexCoord() }
			if p.tile then
				tex:SetTexture(PieceRoot(name) .. p.file, "REPEAT", "REPEAT")
			else
				tex:SetTexture(PieceRoot(name) .. p.file)
			end
			if #coords == 8 then
				tex:SetTexCoord(unpack(coords))
			end
		end
	end
end

-- A background's scale in its own UI units per piece px: Kit.scale on the
-- screen, whatever its frame's effective scale
function Kit:BackgroundScale(tex)
	local ok, s = pcall(tex.GetEffectiveScale, tex)
	local us = UIParent and UIParent:GetEffectiveScale()
	if not (ok and s and us) or Secret(s) or s <= 0 then
		return self.scale
	end
	return self.scale * us / s
end

-- Texture coordinates of a repeatable piece for its current size, so the art
-- repeats at its native scale instead of stretching. A background's phase
-- (`tex.kitAlign`): from its top-left corner (nil), centred ("center"),
-- centred across and from the top or bottom ("top" / "bottom"), or from the
-- screen's origin ("screen": backdrops that meet show one surface).
function Kit:Retile(tex)
	local p = tex.kitPiece
	if type(p) ~= "table" or not p.tile then
		return
	end
	local background = tex.kitBackground and not tex.kitOwnScale
	local scale = background and self:BackgroundScale(tex) or tex.kitScale
	if not scale or scale <= 0 then
		scale = self.scale
	end
	local ok, w, h = pcall(tex.GetSize, tex)
	if not ok or (issecretvalue and (issecretvalue(w) or issecretvalue(h))) then
		-- a region under a unit frame answers with secret sizes: `kitTileSize`
		-- (set by whoever sized it) stands in, else the art stays as applied
		w, h = tex.kitTileW or 0, tex.kitTileH or 0
	end
	local align = background and tex.kitAlign or nil
	local left, top
	if align == "screen" then
		local okP, l, t = pcall(function() return tex:GetLeft(), tex:GetTop() end)
		if okP and l and t and not Secret(l) and not Secret(t) then
			left, top = l, t
		else
			align = nil
		end
	end
	-- the share of one repeat the texture spans on an axis, and where it starts
	local function Span(size, repeatSize, from, centred, far)
		local f = size / repeatSize
		if align == "screen" then
			return f, (from % repeatSize) / repeatSize
		elseif centred then
			return f, (1 - f) / 2
		elseif far then
			return f, 1 - f
		end
		return f, 0
	end
	local u1, u2, v1, v2 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
	local du, dv = u2 - u1, v2 - v1
	if p.tile:find("x") and w > 0 then
		local f, o = Span(w, p.w * scale, left, align == "center" or align == "top" or align == "bottom")
		u1 = u1 + du * o
		u2 = u1 + du * f
	end
	if p.tile:find("y") and h > 0 then
		local f, o = Span(h, p.h * scale, top and -top, align == "center", align == "bottom")
		v1 = v1 + dv * o
		v2 = v1 + dv * f
	end
	tex:SetTexCoord(u1, u2, v1, v2)
end

-- Every background laid again (a frame scaled, the UI scale changed, Edit
-- Mode closed): their repeat stays the same size on the screen. A texture
-- whose size reads secret (under a unit frame, in combat) and that has no
-- `kitTileW` standing in is left as it was last laid: Retile would otherwise
-- fall back to one whole copy of the piece, the stretched look this rule
-- exists to prevent. Returns how many were laid and how many left.
function Kit:RetileBackgrounds()
	local laid, left = 0, 0
	for tex in pairs(BACKGROUNDS) do
		if tex.kitBackground then
			local ok, w, h = pcall(tex.GetSize, tex)
			if (ok and w and h and not Secret(w) and not Secret(h)) or tex.kitTileW then
				self:Retile(tex)
				laid = laid + 1
			else
				left = left + 1
			end
		end
	end
	return laid, left
end

--------------------------------------------------------------------------------
-- The UI scale watcher (user, 2026-09-24: "UI Scaling Break the UI"). One
-- place that answers a change of the game's UI Scale (the uiScale /
-- useUiScale settings), of the window's resolution, and of an Edit Mode
-- setting (a system's Size): every background laid again at the screen's
-- one density, then every panel that measured something on the screen told
-- through Kit:OnUIScaleChanged(fn), fn(reason) with reason "uiscale" (the UI
-- Scale or the resolution) or "editmode" (a setting in Edit Mode).
-- The work waits a moment and runs once for a burst of changes: when the
-- event comes the game has not yet re-laid everything for the new scale
-- (Edit Mode re-scales and re-places the right-hand action bars and the
-- panel manager moves its windows in their own handlers of the same events),
-- and the settings' slider sends several changes in a row. What a listener
-- does to a protected frame it puts through Kit:WhenOutOfCombat itself.
-- Bars, rails, caps and pieces in general need nothing: they are sized in
-- their frame's own units and follow any scale with it; only the
-- backgrounds (measured on the screen) and what a panel laid out from
-- screen positions (the action bar backdrops, the saved window places, the
-- picker's catchers, the drag grid) go stale.
--------------------------------------------------------------------------------
Kit.scaleListeners = {}
Kit.lastScaleRefit = nil   -- what the last refit did, for /uiscaledump

function Kit:OnUIScaleChanged(fn)
	if type(fn) == "function" then
		self.scaleListeners[#self.scaleListeners + 1] = fn
	end
end

-- The refit itself, at once (the watcher calls it a moment after a change;
-- /uiscaledump refit calls it by hand)
function Kit:RefitForScale(reason)
	reason = reason or "uiscale"
	local laid, left = self:RetileBackgrounds()
	local told, failed, firstError = 0, 0, nil
	for _, fn in ipairs(self.scaleListeners) do
		local ok, err = pcall(fn, reason)
		if ok then
			told = told + 1
		else
			failed = failed + 1
			firstError = firstError or tostring(err)
		end
	end
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	self.lastScaleRefit = {
		reason = reason, when = GetTime and GetTime() or 0,
		backgrounds = laid, skipped = left, listeners = told, failed = failed, error = firstError,
		effectiveScale = (okU and not Secret(us)) and us or nil,
	}
	return laid, told
end

do
	local pending, pendingReason = nil, nil
	local function Run()
		pending = nil
		local reason = pendingReason
		pendingReason = nil
		Kit:RefitForScale(reason)
	end
	-- a change of the UI Scale outranks an Edit Mode one: its listeners do more
	local function Schedule(reason)
		if pendingReason ~= "uiscale" then
			pendingReason = reason
		end
		if pending then
			pending:Cancel()
		end
		pending = C_Timer.NewTimer(0.15, Run)
	end
	Kit.ScheduleScaleRefit = function(_, reason)
		Schedule(reason or "uiscale")
	end
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("UI_SCALE_CHANGED")
	ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
	ev:SetScript("OnEvent", function()
		Schedule("uiscale")
	end)
	-- the settings themselves, for a client that changes the scale without
	-- the event (it costs nothing twice: the timer runs once)
	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
		for _, cvar in ipairs({ "uiScale", "useUiScale" }) do
			CVarCallbackRegistry:RegisterCallback(cvar, function() Schedule("uiscale") end, Kit)
		end
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Exit", function() Schedule("editmode") end, Kit)
	end
	-- a system's Size (or any setting) changed in Edit Mode: laid again while
	-- the window is still open, not only when it closes (a post-hook: Edit
	-- Mode's own code runs untouched)
	local manager = EditModeManagerFrame
	if manager and type(manager.OnSystemSettingChange) == "function" then
		hooksecurefunc(manager, "OnSystemSettingChange", function()
			Schedule("editmode")
		end)
	end
end

-- /uiscaledump [refit]: the UI scale as the game and the kit see it, and what
-- the last refit did (user, 2026-09-24: to check the UI Scale fix in game).
-- "refit" runs a refit now first. Opens the copy window.
SLASH_MELLOUISCALEDUMP1 = "/uiscaledump"
SlashCmdList.MELLOUISCALEDUMP = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "refit" then
		Kit:RefitForScale("uiscale")
	end
	MelloUI:ClearLog()
	local function Num(v, fmt)
		if type(v) ~= "number" or Secret(v) then
			return tostring(v)
		end
		return string.format(fmt or "%.4f", v)
	end
	local GetCVarFn = (C_CVar and C_CVar.GetCVar) or GetCVar
	local okC, uiScale = pcall(GetCVarFn, "uiScale")
	local okU, useUiScale = pcall(GetCVarFn, "useUiScale")
	MelloUI:Print("cvar uiScale = %s, useUiScale = %s", okC and tostring(uiScale) or "?", okU and tostring(useUiScale) or "?")
	local okS, s = pcall(UIParent.GetScale, UIParent)
	local okE, es = pcall(UIParent.GetEffectiveScale, UIParent)
	local okW, w, h = pcall(UIParent.GetSize, UIParent)
	MelloUI:Print("UIParent scale = %s, effective = %s, size = %s x %s UI units", okS and Num(s) or "?", okE and Num(es) or "?",
		okW and Num(w, "%.1f") or "?", okW and Num(h, "%.1f") or "?")
	if GetPhysicalScreenSize then
		local okP, pw, ph = pcall(GetPhysicalScreenSize)
		if okP and type(ph) == "number" and not Secret(ph) and ph > 0 then
			MelloUI:Print("physical screen = %s x %s px; a pixel-exact UI scale here would be %s", Num(pw, "%d"), Num(ph, "%d"), Num(768 / ph))
			if okE and type(es) == "number" and not Secret(es) and es > 0 then
				MelloUI:Print("one UI unit = %s screen px", Num(es * ph / 768, "%.3f"))
			end
		end
	end
	local backgrounds = 0
	for tex in pairs(BACKGROUNDS) do
		if tex.kitBackground then
			backgrounds = backgrounds + 1
		end
	end
	MelloUI:Print("Kit.scale = %s UI units per piece px; backgrounds registered = %d; scale listeners = %d", Num(Kit.scale, "%.3f"),
		backgrounds, #Kit.scaleListeners)
	local last = Kit.lastScaleRefit
	if last then
		local ago = GetTime and (GetTime() - (last.when or 0)) or 0
		MelloUI:Print("last refit (%s, %.0f s ago, UIParent effective %s): %d backgrounds laid again, %d left (size unreadable), %d listeners told, %d failed",
			tostring(last.reason), ago, Num(last.effectiveScale), last.backgrounds or 0, last.skipped or 0, last.listeners or 0, last.failed or 0)
		if last.error then
			MelloUI:Print("first listener error: %s", last.error)
		end
		if last.effectiveScale and okE and type(es) == "number" and not Secret(es) and math.abs(last.effectiveScale - es) > 0.0001 then
			MelloUI:Print("the UI scale changed since the last refit and none ran: /uiscaledump refit")
		end
	else
		MelloUI:Print("no refit since the last reload (the UI scale has not changed); /uiscaledump refit runs one")
	end
	MelloUI:ShowLog("uiscaledump")
end

-- A new texture showing a piece at its natural size.
function Kit:Texture(parent, name, layer, sublevel, scale)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
	tex.kitScale = scale
	self:Apply(tex, name)
	tex:SetSize(self:Size(name, scale))
	return tex
end

-- A painted part stood in for by another of the same family (the user's
-- pick for that state): the title plate's red middle is the open tab's
-- brighter red (H3, user 2026-09-21: the painted title middle did not fit
-- its rune caps).
local STRIP_ALIAS = {
	["tabs/top_mid_title"] = "tabs/top_mid_open",
}

-- "buttons/textbtn", "cap_l", "hover" -> "buttons/textbtn_cap_l_hover"
local function StripName(base, part, state)
	local name = base .. "_" .. part
	if state and PIECES[name .. "_" .. state] then
		return STRIP_ALIAS[name .. "_" .. state] or name .. "_" .. state
	end
	return name
end

-- The piece a strip part is drawn with (aliases resolved), for code that
-- measures the painted pieces.
function Kit:StripPieceName(base, part, state)
	return StripName(base, part, state)
end

-- First state a strip part exists in ("normal", "plain", ...), nil when stateless.
function Kit:FirstState(base, part)
	return self:FirstStateOf(base .. "_" .. part)
end

-- First state a piece exists in: "buttons/cog" -> "normal", "buttons/checkbox" -> "off".
function Kit:FirstStateOf(base)
	for _, s in ipairs(STATES) do
		if PIECES[base .. "_" .. s] then
			return s
		end
	end
	return nil
end

-- The state name a piece should show for a button's condition, among the
-- states it was painted in (a checkbox has off/on/hover, a slot has
-- normal/hover/pressed/checked, a text button also disabled).
local FALLBACK = {
	disabled = { "disabled" },
	pressed = { "pressed", "hover" },
	checked = { "checked", "on", "open", "selected" },
	hover = { "hover" },
}
local REST = { "normal", "off", "plain", "closed" }

function Kit:ResolveState(base, hover, pressed, checked, disabled)
	-- in priority order, each condition only if a piece for it exists: a
	-- family without a disabled piece shows a disabled AND checked button
	-- as checked (the game disables the selected category tab; the slot
	-- rim then lost its gold on a reload — user, 2026-09-22)
	-- (`or false`: a nil flag would leave a hole in the list and ipairs
	-- would stop there — every checked box showed as off, user 2026-09-22)
	for _, want in ipairs({ disabled and "disabled" or false, pressed and "pressed" or false, checked and "checked" or false, hover and "hover" or false }) do
		if want then
			for _, s in ipairs(FALLBACK[want]) do
				if PIECES[base .. "_" .. s] then
					return s
				end
			end
		end
	end
	for _, s in ipairs(REST) do
		if PIECES[base .. "_" .. s] then
			return s
		end
	end
	return self:FirstStateOf(base)
end

--------------------------------------------------------------------------------
-- Nine-slice window: body tiled under everything, edges tiled, corners on top,
-- optional gems on the crossings and the ornament over the top-left.
--   Kit:NineSlice(parent, { prefix = "window/frame", scale = , level = ,
--                           gems = true, ornament = true, body = true,
--                           corners = "gem", skip = "tl",
--                           open = "l" })  -- sides left open: "l", "r", "t", "b"
-- An open side has no edge and no corners: the bracket shape of an attached
-- tab or a bar cap. corners = "gem" draws the painted gem corners
-- (<prefix>_gem_tl..br, oversized, over the edges; their `overhang` puts the
-- gem past the frame's corner) instead of the mitred ones; `skip` names
-- corners to leave mitred (e.g. "tl" where a portrait ring is the corner).
-- The skin fills `parent`; keep content inside Kit:NineSliceInset(skin).
-- skin:SetTint(r, g, b) colours the edges.
--------------------------------------------------------------------------------

local function Tiled(skin, name, layer, sublevel, scale)
	local tex = skin:CreateTexture(nil, layer, nil, sublevel)
	tex.kitScale = scale
	Kit:Apply(tex, name)
	return tex
end

local function NineSlice_Retile(self)
	for _, tex in ipairs(self.tiled) do
		Kit:Retile(tex)
	end
end

function Kit:NineSlice(parent, opts)
	opts = opts or {}
	local prefix = opts.prefix or "window/frame"
	local scale = opts.scale or self.scale
	local skin = CreateFrame("Frame", nil, parent)
	skin:SetFrameStrata(parent:GetFrameStrata())
	skin:SetFrameLevel(math.max(parent:GetFrameLevel() + (opts.level or 0), 0))
	skin:EnableMouse(false)
	skin:SetAllPoints(parent)
	skin.melloSkin = true
	skin.kitScale = scale
	-- `owner`: the textures are REGIONS of that frame (drawn in ITS layer
	-- stack: `bodyLayer` / `bodySub`, `edgeLayer` / `edgeSub`), the skin frame
	-- only laying them out — a compact raid frame's rail above its fill and
	-- under its icons. Show / Hide then toggle the regions.
	local host = opts.owner or skin
	local bodyLayer, bodySub = opts.bodyLayer or "BACKGROUND", opts.bodySub or 0
	local edgeLayer, edgeSub = opts.edgeLayer or "BORDER", opts.edgeSub or 0
	if opts.owner then
		local show, hide = skin.Show, skin.Hide
		skin.Show = function(self)
			show(self)
			for _, tex in ipairs(self.all) do tex:Show() end
		end
		skin.Hide = function(self)
			hide(self)
			for _, tex in ipairs(self.all) do tex:Hide() end
		end
		skin.SetShown = function(self, shown) if shown then self:Show() else self:Hide() end end
	end
	skin.all = {}

	local T = self:Size(prefix .. "_tl", scale)   -- corner = edge thickness
	skin.thickness = T
	skin.tiled = {}
	skin.art = {}
	local open = opts.open or ""
	local oL, oR, oT, oB = open:find("l") ~= nil, open:find("r") ~= nil, open:find("t") ~= nil, open:find("b") ~= nil

	local gemCorners = opts.corners == "gem" and PIECES[prefix .. "_gem_tl"] ~= nil
	local skip = opts.skip or ""
	if opts.body ~= false then
		-- the body reaches under the whole edge when gem corners sit on it:
		-- the interior shows inside their rounded elbows
		local inset = gemCorners and 0 or T / 2
		-- the family's own stone, or another tile (`body` = its name, `bodyScale` its scale)
		local bodyName = type(opts.body) == "string" and opts.body or (prefix .. "_body")
		local body = Tiled(host, bodyName, bodyLayer, bodySub, opts.bodyScale or scale)
		body:SetPoint("TOPLEFT", skin, "TOPLEFT", oL and 0 or inset, oT and 0 or -inset)
		body:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", oR and 0 or -inset, oB and 0 or inset)
		skin.body = body
		table.insert(skin.tiled, body)
		table.insert(skin.all, body)
	end

	-- edges run to the rect's edge on an open side (no corner there)
	local edges = {
		t = { "TOPLEFT", oL and 0 or T, 0, "TOPRIGHT", oR and 0 or -T, 0, skip = oT },
		b = { "BOTTOMLEFT", oL and 0 or T, 0, "BOTTOMRIGHT", oR and 0 or -T, 0, skip = oB },
		l = { "TOPLEFT", 0, oT and 0 or -T, "BOTTOMLEFT", 0, oB and 0 or T, skip = oL },
		r = { "TOPRIGHT", 0, oT and 0 or -T, "BOTTOMRIGHT", 0, oB and 0 or T, skip = oR },
	}
	for e, a in pairs(edges) do
		if not a.skip then
			local tex = Tiled(host, prefix .. "_" .. e, edgeLayer, edgeSub, scale)
			tex:SetPoint(a[1], skin, a[1], a[2], a[3])
			tex:SetPoint(a[4], skin, a[4], a[5], a[6])
			if e == "t" or e == "b" then
				tex:SetHeight(T)
			else
				tex:SetWidth(T)
			end
			skin[e] = tex
			table.insert(skin.tiled, tex)
			table.insert(skin.art, tex)
			table.insert(skin.all, tex)
		end
	end

	local corners = { tl = { "TOPLEFT", oT or oL }, tr = { "TOPRIGHT", oT or oR }, bl = { "BOTTOMLEFT", oB or oL }, br = { "BOTTOMRIGHT", oB or oR } }
	for c, a in pairs(corners) do
		if not a[2] then
			local gem = gemCorners and not skip:find(c, 1, true)
			if not gem then
				local tex = self:Texture(host, prefix .. "_" .. c, edgeLayer, edgeSub + 1, scale)
				tex:SetPoint(a[1], skin, a[1])
				skin[c] = tex
				table.insert(skin.art, tex)
				table.insert(skin.all, tex)
			else
				-- the painted corner, anchored past the frame's corner by its overhang
				local name = prefix .. "_gem_" .. c
				local o = (PIECES[name].overhang or 0) * scale
				local tex = self:Texture(skin, name, "ARTWORK", 1, scale)
				local sx = (c == "tl" or c == "bl") and -1 or 1
				local sy = (c == "tl" or c == "tr") and 1 or -1
				tex:SetPoint(a[1], skin, a[1], sx * o, sy * o)
				skin[c] = tex
				table.insert(skin.art, tex)
				skin.gemCorner = skin.gemCorner or {}
				skin.gemCorner[c] = { tex = tex, point = a[1] }
			end
		end
	end

	-- The top gem corners give way to a title plate riding the top rail (its
	-- caps' own gems sit there): plain corners in their place, made when first
	-- needed. `on` false: plain; true: the gems again.
	skin.SetTopGems = function(me, on)
		for _, c in ipairs({ "tl", "tr" }) do
			local gem = me.gemCorner and me.gemCorner[c]
			if gem then
				local plain = me.plainCorner and me.plainCorner[c]
				if not on and not plain then
					plain = self:Texture(host, prefix .. "_" .. c, edgeLayer, edgeSub + 1, scale)
					plain:SetPoint(gem.point, me, gem.point)
					me.plainCorner = me.plainCorner or {}
					me.plainCorner[c] = plain
					table.insert(me.art, plain)
				end
				gem.tex:SetShown(on and true or false)
				if plain then
					plain:SetShown(not on)
				end
			end
		end
	end

	-- a colour on the iron (the selected state of an attached tab)
	skin.SetTint = function(self, r, g, b)
		for _, tex in ipairs(self.art) do
			tex:SetVertexColor(r or 1, g or 1, b or 1)
		end
	end

	if opts.gems ~= false and PIECES["deco/gem_large"] then
		skin.gems = {}
		for c, point in pairs(corners) do
			local gem = self:Texture(skin, c == "tl" and "deco/gem_large" or "deco/gem_small", "ARTWORK", 1, scale)
			local sx = (c == "tl" or c == "bl") and 1 or -1
			local sy = (c == "tl" or c == "tr") and -1 or 1
			gem:SetPoint("CENTER", skin, point, sx * T / 2, sy * T / 2)
			skin.gems[c] = gem
		end
	end
	local ornName = (prefix:gsub("frame$", "corner_ornament_tl"))
	if opts.ornament and PIECES[ornName] then
		local orn = self:Texture(skin, ornName, "ARTWORK", 2, scale)
		orn:SetPoint("TOPLEFT", -4 * scale, 4 * scale)
		skin.ornament = orn
	end

	skin:SetScript("OnSizeChanged", NineSlice_Retile)
	-- a skin sized while hidden gets no OnSizeChanged on this client (the
	-- configurator's sections behind the first tab: one tile stretched over
	-- the box, "blurred" — user, 2026-09-22): tiled again when it shows
	skin:HookScript("OnShow", NineSlice_Retile)
	NineSlice_Retile(skin)
	return skin
end

function Kit:NineSliceInset(skin)
	return skin.thickness
end

--------------------------------------------------------------------------------
-- Strip: cap_l + tiled mid + cap_r, all the same height, top-aligned.
--   Kit:Strip(parent, "buttons/textbtn", { state = "normal", width = 200, scale = })
-- strip:SetState("hover"); strip:SetWidth(w); strip.height
--------------------------------------------------------------------------------

local StripMixin = {}

function StripMixin:SetState(state)
	if state == self.state and self.applied then
		return
	end
	self.state, self.applied = state, true
	Kit:Apply(self.capL, StripName(self.base, self.endL and "end_l" or "cap_l", state))
	Kit:Apply(self.mid, StripName(self.base, "mid", state))
	Kit:Apply(self.capR, StripName(self.base, self.endR and "end_r" or "cap_r", state))
end

-- Another family of pieces for the strip (a bar's Bar Border), in its state
-- where the family has it: the caps and the mid re-applied and re-sized
function StripMixin:SetBase(base)
	if base == self.base then
		return
	end
	self.base = base
	local state = self.state
	self.state, self.applied = nil, nil
	self.capless, self.noL, self.noR, self.endL, self.endR = nil, nil, nil, nil, nil
	self:SetState(state)
	local scale = self.scale
	self.scale = 0          -- sized afresh for the new pieces
	self:Rescale(scale)
end

-- Change the strip's scale (e.g. once the game element it replaces has its
-- real height): caps resize, the mid retiles, the frame keeps its anchors.
function StripMixin:Rescale(scale)
	if not scale or scale <= 0 or math.abs(scale - self.scale) < 0.001 then
		return
	end
	self.scale = scale
	self.kitScale = scale
	self.capL.kitScale, self.mid.kitScale, self.capR.kitScale = scale, scale, scale
	local wl, h = Kit:Size(StripName(self.base, self.endL and "end_l" or "cap_l", self.state), scale)
	local wr = Kit:Size(StripName(self.base, self.endR and "end_r" or "cap_r", self.state), scale)
	self.height = h
	self.wl, self.wr = wl, wr
	self.capL:SetSize(wl, h)
	self.capR:SetSize(wr, h)
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", self, "TOPLEFT", (self.capless or (self.noL and not self.endL)) and 0 or wl, 0)
	self.mid:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", (self.capless or (self.noR and not self.endR)) and 0 or -wr, 0)
	Kit:Retile(self.mid)
end

-- Scale so the strip's natural height equals `height` (0 or nil: no change).
function StripMixin:FitHeight(height)
	if not height or height <= 0 then
		return
	end
	local natural = select(2, Kit:Size(StripName(self.base, "cap_l", self.state), 1))
	if natural > 0 then
		self:Rescale(height / natural)
	end
end

-- Scale so the OPAQUE part of the mid (its box) is `height` tall, and return
-- the vertical offset that puts that box on the centre line of whatever the
-- strip is anchored to (the art is not always centred in its canvas).
function StripMixin:FitBox(height)
	if not height or height <= 0 then
		return 0
	end
	local p = PIECES[StripName(self.base, "mid", self.state)]
	if not (p and p.box) then
		self:FitHeight(height)
		return 0
	end
	local boxH = p.box[4] - p.box[2]
	if boxH <= 0 then
		self:FitHeight(height)
		return 0
	end
	self:Rescale(height / boxH)
	local boxCentre = (p.box[2] + p.box[4]) / 2
	return (boxCentre - p.h / 2) * self.scale
end

-- The scale at which the WHOLE strip, its caps included, is `height` tall,
-- and the height its box (the opening) has at that scale. Both come from the
-- art alone, never from the current layout, so a panel can size what sits in
-- the opening before the strip has been refitted. For a bracket that must fit
-- a row rather than hug its bar (the damage meter's rows, user 2026-09-23:
-- "scale down the artwork ... to fit").
function StripMixin:FitWhole(height)
	if not height or height <= 0 then
		return nil
	end
	local natural = select(2, Kit:Size(StripName(self.base, self.endL and "end_l" or "cap_l", self.state), 1))
	local p = PIECES[StripName(self.base, "mid", self.state)]
	if not (natural and natural > 0 and p and p.box) then
		return nil
	end
	local scale = height / natural
	return scale, (p.box[4] - p.box[2]) * scale
end

-- A rect narrower than the two caps shows the mid alone (the caps would
-- overlap): the caps are hidden and the mid spans the whole strip.
function StripMixin:FitCaps(width)
	-- the caps' widths as computed (never read back: a region under a unit
	-- frame answers with a secret number on this client)
	local wl, wr = self.wl or 0, self.wr or 0
	local capless = self.forceCapless or (width and width > 0 and width < wl + wr + 4)
	-- `dropCap`: one cap left out ("l" / "r"), the mid running to that edge
	local noL = capless or self.dropCap == "l"
	local noR = capless or self.dropCap == "r"
	if capless == self.capless and noL == self.noL and noR == self.noR then
		if width and width > 0 then
			self.mid.kitTileW = width - ((noL and not self.endL) and 0 or wl) - ((noR and not self.endR) and 0 or wr)
			self.mid.kitTileH = self.height
			Kit:Retile(self.mid)
		end
		return
	end
	self.capless, self.noL, self.noR = capless, noL, noR
	-- a dropped cap closes with the family's gemless end piece
	-- (<base>_end_l/r_<state>, made by Tools/make_plain_plate.py) when it has one
	local endL = noL and not capless and PIECES[StripName(self.base, "end_l", self.state)]
	local endR = noR and not capless and PIECES[StripName(self.base, "end_r", self.state)]
	if endL then
		Kit:Apply(self.capL, StripName(self.base, "end_l", self.state))
		wl = select(1, Kit:Size(StripName(self.base, "end_l", self.state), self.scale))
		self.capL:SetWidth(wl)
		self.wl = wl
	end
	if endR then
		Kit:Apply(self.capR, StripName(self.base, "end_r", self.state))
		wr = select(1, Kit:Size(StripName(self.base, "end_r", self.state), self.scale))
		self.capR:SetWidth(wr)
		self.wr = wr
	end
	self.endL, self.endR = endL and true or nil, endR and true or nil
	self.capL:SetShown(not noL or endL)
	self.capR:SetShown(not noR or endR)
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", self, "TOPLEFT", (noL and not endL) and 0 or wl, 0)
	self.mid:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", (noR and not endR) and 0 or -wr, 0)
	-- the mid's size as laid out, for a Retile that cannot read it back
	if width and width > 0 then
		self.mid.kitTileW = width - ((noL and not endL) and 0 or wl) - ((noR and not endR) and 0 or wr)
		self.mid.kitTileH = self.height
	end
	Kit:Retile(self.mid)
end

-- Insets of the mid's opening (left cap, right cap, top, bottom), for content.
function StripMixin:GetInsets()
	local _, _, top, bottom = Kit:Insets(StripName(self.base, "mid", self.state), self.scale)
	return self.wl or 0, self.wr or 0, top or 0, bottom or 0
end

function Kit:Strip(parent, base, opts)
	opts = opts or {}
	local scale = opts.scale
	if not scale or scale <= 0 then
		scale = self.scale
	end
	local state = opts.state or self:FirstState(base, "mid")
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	Mixin(f, StripMixin)
	f.base, f.scale, f.kitScale = base, scale, scale

	local layer, sub = opts.layer or "ARTWORK", opts.sublevel or 0
	-- `owner`: the textures are regions of that frame (drawn in ITS layer
	-- stack, between its own regions); the strip frame only lays them out
	local host = opts.owner or f
	f.capL = host:CreateTexture(nil, layer, nil, sub)
	f.mid = host:CreateTexture(nil, layer, nil, sub - 1)
	f.capR = host:CreateTexture(nil, layer, nil, sub)
	f.capL.kitScale, f.mid.kitScale, f.capR.kitScale = scale, scale, scale
	if opts.owner then
		local show, hide = f.Show, f.Hide
		f.Show = function(self) show(self); self.capL:SetShown(not self.noL or self.endL); self.mid:Show(); self.capR:SetShown(not self.noR or self.endR) end
		f.Hide = function(self) hide(self); self.capL:Hide(); self.mid:Hide(); self.capR:Hide() end
		f.SetShown = function(self, shown) if shown then self:Show() else self:Hide() end end
	end

	local wl, h = self:Size(StripName(base, "cap_l", state), scale)
	local wr = self:Size(StripName(base, "cap_r", state), scale)
	f.height = h
	f.wl, f.wr = wl, wr
	f:SetSize(opts.width or (wl + wr + 4 * self:Size(StripName(base, "mid", state), scale)), h)

	f.capL:SetPoint("TOPLEFT", f, "TOPLEFT")
	f.capL:SetSize(wl, h)
	f.capR:SetPoint("TOPRIGHT", f, "TOPRIGHT")
	f.capR:SetSize(wr, h)
	f.mid:SetPoint("TOPLEFT", f, "TOPLEFT", wl, 0)
	f.mid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -wr, 0)
	f:SetScript("OnSizeChanged", function(self)
		Kit:Retile(self.mid)
	end)
	f:SetState(state)
	Kit:Retile(f.mid)
	return f
end

--------------------------------------------------------------------------------
-- VStrip: an upright strip, cap_t + tiled mid + cap_b, all the same width,
-- for a scroll thumb. The caps shrink when the strip is shorter than both.
--   Kit:VStrip(parent, "lists/scrollthumb", { state = "normal", scale = })
-- strip:SetState("hover"); strip:FitWidth(w) scales it to that width.
--------------------------------------------------------------------------------

local VStripMixin = {}

function VStripMixin:SetState(state)
	if state == self.state and self.applied then
		return
	end
	self.state, self.applied = state, true
	Kit:Apply(self.capT, StripName(self.base, "cap_t", state))
	Kit:Apply(self.mid, StripName(self.base, "mid", state))
	Kit:Apply(self.capB, StripName(self.base, "cap_b", state))
end

function VStripMixin:Layout()
	local w, h = self:GetSize()
	local capH = self.capH
	if h > 0 and capH * 2 > h then
		capH = h / 2                          -- a thumb shorter than its two gems
	end
	self.capT:SetSize(w, capH)
	self.capB:SetSize(w, capH)
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", 0, -capH)
	self.mid:SetPoint("BOTTOMRIGHT", 0, capH)
	Kit:Retile(self.mid)
end

-- Scale so the piece's natural width equals `width` (0 or nil: no change).
function VStripMixin:FitWidth(width)
	if not width or width <= 0 then
		return
	end
	local natural, capH = Kit:Size(StripName(self.base, "cap_t", self.state), 1)
	if natural <= 0 then
		return
	end
	local scale = width / natural
	self.scale, self.kitScale = scale, scale
	self.capT.kitScale, self.mid.kitScale, self.capB.kitScale = scale, scale, scale
	self.capH = capH * scale
	self:SetWidth(width)
	self:Layout()
end

function Kit:VStrip(parent, base, opts)
	opts = opts or {}
	local scale = opts.scale
	if not scale or scale <= 0 then
		scale = self.scale
	end
	local state = opts.state or self:FirstState(base, "mid")
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	Mixin(f, VStripMixin)
	f.base, f.scale, f.kitScale = base, scale, scale
	local layer, sub = opts.layer or "ARTWORK", opts.sublevel or 0
	f.capT = f:CreateTexture(nil, layer, nil, sub)
	f.mid = f:CreateTexture(nil, layer, nil, sub - 1)
	f.capB = f:CreateTexture(nil, layer, nil, sub)
	f.capT.kitScale, f.mid.kitScale, f.capB.kitScale = scale, scale, scale
	local w, capH = self:Size(StripName(base, "cap_t", state), scale)
	f.capH = capH
	f:SetSize(w, 3 * capH)
	f.capT:SetPoint("TOPLEFT")
	f.capB:SetPoint("BOTTOMLEFT")
	f:SetScript("OnSizeChanged", function(self)
		self:Layout()
	end)
	f:SetState(state)
	f:Layout()
	return f
end

--------------------------------------------------------------------------------
-- Bar: trough tiled under the frame strip, the frame over it, and `fill`, a
-- frame covering the opening, for a StatusBar (or any fill texture).
--   Kit:Bar(parent, { kind = "frame" | "castbar", width = , scale = })
--------------------------------------------------------------------------------

function Kit:Bar(parent, opts)
	opts = opts or {}
	local kind = opts.kind or "frame"
	local scale = opts.scale or self.scale
	local base = "bars/" .. kind
	local strip = self:Strip(parent, base, { width = opts.width, scale = scale, layer = "ARTWORK", sublevel = 2 })

	-- the opening runs from inside the left cap's hollow arm to inside the right one
	local _, _, top, bottom = strip:GetInsets()
	local capL, capR = PIECES[base .. "_cap_l"], PIECES[base .. "_cap_r"]
	local left = capL and capL.open and capL.open[1] * scale or strip.wl
	local right = capR and capR.open and (capR.w - capR.open[3]) * scale or strip.wr
	-- frame art two levels above the fill, so a StatusBar parented to `fill`
	-- (one level above it) still draws under the rim
	local base_level = parent:GetFrameLevel()
	strip:SetFrameLevel(base_level + 3)
	local fill = CreateFrame("Frame", nil, strip)
	fill:SetFrameLevel(base_level + 1)
	fill:SetPoint("TOPLEFT", left, -top)
	fill:SetPoint("BOTTOMRIGHT", -right, bottom)
	strip.fill = fill

	local trough = fill:CreateTexture(nil, "BACKGROUND", nil, 0)
	trough.kitScale = scale
	self:Apply(trough, "bars/trough")
	trough:SetPoint("TOPLEFT", -2 * scale, 0)
	trough:SetPoint("BOTTOMRIGHT", 2 * scale, 0)
	strip.trough = trough
	fill:SetScript("OnSizeChanged", function()
		Kit:Retile(trough)
	end)
	Kit:Retile(trough)
	return strip
end

--------------------------------------------------------------------------------
-- Slot: the painted rim over a button's icon; hover / pressed / checked follow
-- the button. The button's own art should be faded by the caller.
--   Kit:Slot(button, { kind = "slot" | "roundslot", icon = texture, scale = , checked = function })
-- The icon is anchored into the opening when given.
--------------------------------------------------------------------------------

local function Slot_Update(rim)
	local b = rim.button
	-- secret-safe, as the sweep below: this runs from the button's own
	-- OnEnter / OnMouseDown / SetChecked hooks, and an action button can
	-- answer IsEnabled / GetChecked with a secret in combat; a secret keeps
	-- the rim's last known value instead of being tested (user, 2026-09-23)
	local disabled = rim.lastDisabled or false
	if b.IsEnabled then
		local okE, enabled = pcall(b.IsEnabled, b)
		if okE and not Secret(enabled) then
			disabled = enabled == false
		end
	end
	local checked = rim.lastChecked
	local okC, c
	if rim.isChecked then
		okC, c = pcall(rim.isChecked)
	elseif b.GetChecked then
		okC, c = pcall(b.GetChecked, b)
	else
		okC, c = true, nil
	end
	if okC and not Secret(c) then
		checked = c
	end
	rim.lastDisabled = disabled
	local state
	if rim.restState then
		-- a fixed look (the game's tab art is the same on every tab); the
		-- states are shown by the glow the replacement adds over it
		state = rim.restState
	else
		state = Kit:ResolveState(rim.base, rim.hover, rim.pressed, checked, disabled)
	end
	rim.lastChecked = checked and true or false   -- for the sweep below
	if rim.glow then
		local a = checked and 0.7 or rim.hover and 0.35 or 0
		rim.glow:SetAlpha(a)
		rim.glow:SetShown(a > 0)
	end
	if state and state ~= rim.state then
		rim.state = state
		Kit:Apply(rim, rim.base .. "_" .. state)
	end
end

-- A press latched by OnMouseDown ends on ANY mouse release, and when the
-- cursor leaves the button: a button gets no OnMouseUp when the cursor
-- left it before the release or a drag began, and its rim stayed pressed
-- until the next click (user, 2026-09-22: action buttons stuck pressed).
local pressedLatches = setmetatable({}, { __mode = "k" })   -- [rim or rep] = its Update
local SweepRims   -- below
local releaseFrame = CreateFrame("Frame")
releaseFrame:RegisterEvent("GLOBAL_MOUSE_UP")
releaseFrame:SetScript("OnEvent", function()
	for latch, update in pairs(pressedLatches) do
		pressedLatches[latch] = nil
		if latch.pressed then
			latch.pressed = nil
			update(latch)
		end
	end
	-- and every rim re-read right after the release (the click's C-side
	-- toggle of a check button is in by now)
	if SweepRims then
		C_Timer.After(0, SweepRims)
	end
end)

-- ... and every rim is re-read from its button's live state once a second
-- (mouse over it, the widget's own pushed state): whatever an event missed,
-- the look is right again within a second (user, 2026-09-22: rims stuck).
local allRims = setmetatable({}, { __mode = "k" })
SweepRims = function()
	for rim in pairs(allRims) do
		local b = rim.button
		-- EVERY read below can come back SECRET on this client (an action
		-- button's mouse-over in combat: "attempt to perform boolean test on
		-- local 'over' (a secret boolean value)", user 2026-09-23). A secret
		-- answer means "cannot know right now": the rim keeps what it had and
		-- is read again on the next sweep; nothing is tested or compared.
		local okV, shown = false, nil
		if b and b.IsShown then
			okV, shown = pcall(b.IsShown, b)
		end
		if okV and not Secret(shown) and shown and not rim.restState then
			local okO, over = pcall(b.IsMouseOver, b)
			local okS, state = pcall(b.GetButtonState, b)
			local hover = rim.hover
			if okO and not Secret(over) then
				hover = over and true or nil
			end
			local pressed = rim.pressed
			if okS and not Secret(state) then
				pressed = (state == "PUSHED") and true or nil
			end
			if b.GetButtonState == nil then
				pressed = rim.pressed   -- no widget state to read: the latch stands
			end
			-- the checked flag as well: a check button flips it on the C side
			-- when clicked, past the SetChecked hook (the action bars' rims
			-- stayed "checked" with the button long unchecked, user 2026-09-22)
			local okC, c
			if rim.isChecked then
				okC, c = pcall(rim.isChecked)
			else
				okC, c = pcall(b.GetChecked, b)
			end
			local checked = rim.lastChecked or false
			if okC and not Secret(c) then
				checked = c and true or false
			end
			if rim.hover ~= hover or rim.pressed ~= pressed or (rim.lastChecked or false) ~= checked then
				rim.hover, rim.pressed = hover, pressed
				pcall(Slot_Update, rim)
			end
		end
	end
end
C_Timer.NewTicker(1, SweepRims)

local function FollowButton(tex, button)
	allRims[tex] = true
	button:HookScript("OnEnter", function() tex.hover = true; Slot_Update(tex) end)
	button:HookScript("OnLeave", function() tex.hover = nil; tex.pressed = nil; Slot_Update(tex) end)
	button:HookScript("OnMouseDown", function() tex.pressed = true; pressedLatches[tex] = Slot_Update; Slot_Update(tex) end)
	button:HookScript("OnMouseUp", function() tex.pressed = nil; Slot_Update(tex) end)
	if button.SetChecked then
		hooksecurefunc(button, "SetChecked", function() Slot_Update(tex) end)
	end
	if button.SetEnabled then
		hooksecurefunc(button, "SetEnabled", function() Slot_Update(tex) end)
	end
	-- a keybind presses an action button through SetButtonState, not the
	-- mouse: the pressed look follows that too
	if button.SetButtonState then
		hooksecurefunc(button, "SetButtonState", function(b, state)
			tex.pressed = (state == "PUSHED") or nil
			Slot_Update(tex)
		end)
	end
	tex.Update = Slot_Update
end

function Kit:Slot(button, opts)
	opts = opts or {}
	local scale = opts.scale or self.scale
	local base = "buttons/" .. (opts.kind or "slot")
	local owner = button
	if opts.under then
		-- the rim under the button's own art (icon, quality border), as the
		-- game's slot picture is: a frame one level below the button
		owner = CreateFrame("Frame", nil, button)
		owner:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		owner:EnableMouse(false)
		owner:SetAllPoints(button)
	end
	local rim = owner:CreateTexture(nil, opts.layer or (opts.under and "ARTWORK" or "OVERLAY"), nil, opts.sublevel or 3)
	rim.owner = owner
	rim.kitScale = scale
	-- a round rim wears every window's Round Border (Kit.borderKinds)
	if base == "buttons/roundslot" and self.roundRims then
		self.roundRims[rim] = true
		local look = self:BorderValue("round")
		if look and PIECES["buttons/" .. look .. "_normal"] then
			base = "buttons/" .. look
		end
	end
	rim.button, rim.base = button, base
	rim.isChecked = opts.checked           -- function(): true when the piece should show its checked state
	rim:SetAllPoints(button)
	rim.state = nil

	rim.icon = opts.icon
	if opts.icon then
		self:SlotPlaceIcon(rim)
	end

	FollowButton(rim, button)
	Slot_Update(rim)
	return rim
end

-- Anchor the rim's icon into the rim's opening (insets as fractions of the
-- rim, so any button size works). Callers restore the icon's own points to undo.
function Kit:SlotPlaceIcon(rim)
	if rim.placingIcon then
		return
	end
	local name = rim.base .. "_" .. (self:FirstStateOf(rim.base) or "normal")
	local p = PIECES[name]
	local icon = rim.icon
	-- the icon fills the rim's opening: measured on the RIM's own rect (the
	-- rim may be a square on a rectangular button, or larger than the button)
	local rw, rh = rim:GetSize()
	local l, r, t, b = self:Insets(name, 1)
	if p and l and icon and rw > 0 and rh > 0 then
		local il, ir, it, ib = rw * l / p.w, rw * r / p.w, rh * t / p.h, rh * b / p.h
		-- rim.iconGrow: the icon that share larger than the opening, reaching
		-- under the rim's inner bevel (the action bars' thin rims: the icons
		-- looked smaller than their frames, user 2026-09-23)
		local grow = rim.iconGrow
		if grow and grow ~= 0 then
			local gw, gh = (rw - il - ir) * grow / 2, (rh - it - ib) * grow / 2
			il, ir, it, ib = il - gw, ir - gw, it - gh, ib - gh
		end
		-- rim.iconBleed: UI px the icon reaches under the rim's inner edge on
		-- every side (the side tabs: "about 2px bigger than the inner border",
		-- user 2026-09-23)
		local bleed = rim.iconBleed
		if bleed and bleed ~= 0 then
			il, ir, it, ib = il - bleed, ir - bleed, it - bleed, ib - bleed
		end
		rim.placingIcon = true
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", rim, "TOPLEFT", il, -it)
		icon:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -ir, ib)
		rim.placingIcon = nil
	end
end

-- Swap a slot rim's art family live (Action Bars Kit's Button Border, the
-- Dynamic UI Modification picker): the same states from another base, the
-- icon fitted into the new opening, and whoever follows the rim told
-- (rim.onBaseChanged: the empty slot's stone).
function Kit:SetSlotBase(rim, base)
	if not rim or rim.base == base or not PIECES[base .. "_normal"] then
		return
	end
	rim.base, rim.state = base, nil
	Slot_Update(rim)
	if rim.icon then
		self:SlotPlaceIcon(rim)
	end
	if rim.onBaseChanged then
		rim.onBaseChanged()
	end
end

-- Same idea for the small painted buttons (cog, arrows, checkbox, plus, minus,
-- orb, close): one texture that follows the button's state.
function Kit:StateTexture(button, base, opts)
	opts = opts or {}
	local tex = button:CreateTexture(nil, opts.layer or "ARTWORK", nil, opts.sublevel or 0)
	tex.kitScale = opts.scale or self.scale
	tex.button, tex.base = button, base
	tex.isChecked = opts.checked
	tex:SetAllPoints(button)
	FollowButton(tex, button)
	Slot_Update(tex)
	return tex
end

--------------------------------------------------------------------------------
-- Replacement library: which kit piece stands in for which game art.
--
-- Keyed by the game's atlas name (or a texture file's base name, or a name
-- of ours for art that has no atlas, like "TitleBar"). A panel module never
-- picks a piece itself: it hands Kit:Replace the game region and the library
-- looks the piece up here, builds it on the region's own rectangle as a child
-- of the region's frame, and fades the original. docs/KIT-MAPPING.md is the
-- human-readable copy of this table; keep both in step.
--
-- kind:
--   frame   an inner nine-slice (edges + stone body) on the rect; `scale` is
--           a multiplier on Kit.scale, `prefix` another edge family
--           ("window/single": one rail instead of the window's double rail),
--           `body = false` for edges only, `open`
--           the sides without edge (an attached tab: "l"), `checkedTint`
--           the colour of the iron when opts.checked() is true, `corners = "gem"`
--           the painted gem corners over the edges (opts.skip leaves some out)
--           `outset` grows the frame outward from the rect by that many piece px
--           `hover` / `pressed` / `disabled`: tint factors for the button's states
--   strip   ... `capOverhang`: the caps may reach that fraction of their width past the rect
--   edge    one edge tile on the rect (`piece`), for divider lines
--   strip   a cap/mid/cap strip (`base`, `state`) fitted to the rect's height;
--           `owner` draws it as regions of the replaced texture's frame (its
--           layer one sublevel up, or `layer` / `sublevel`) instead of a child frame;
--           `natural` keeps the kit size instead (a thin line inside a large
--           glow atlas) and `widthFrac` spans that fraction of the rect, centred;
--           `heightScale` multiplies the fitted height (the width stays the rect's)
--   slot    the slot rim on a button (`slot` = "slot" | "roundslot"); `under`
--           puts it below the button's icon and quality border, as the game's
--           slot picture is (equipment); without it the rim is over the icon (tabs);
--           `rest` fixes the rim's look (e.g. "checked" = the gold rim on every
--           tab, as the game's tab art is) and `glow` adds the same rim
--           additively for the selected (0.7) and hovered (0.35) button,
--           standing in for the game's SelectedTexture / TabGlow / Highlight
--   state   a state texture on a button (`base`), e.g. the close button;
--           `natural` keeps the kit size centred on the rect, `layer` its
--           draw layer (OVERLAY unless the game's icon must stay on top)
--   vstrip  an upright cap_t / mid / cap_b strip on the rect (a scroll thumb),
--           `widthScale` x the rect's width, its state from the button
--   bar     a hollow bar bracket (`bar` = "frame" | "castbar") fitted to the
--           rect's height with the trough in its opening, both regions of the
--           rect's frame (bracket in BORDER over the game's fill, under its
--           text); `thicken` makes it that many px taller than the rect,
--           `into` how far the fill goes into the rails (1 = all the way),
--           `artScale` (rule or opts) the border art at that fraction of its
--           fitted scale, in every look (the opening shrinks with it);
--           rep:GetOpening() gives the fill area's insets from the rect
--   texture one piece (`piece`) sized to the rect (`square`: to its shorter side,
--           `natural`: the kit size, centred on the rect or opts.center)
--   tile    a repeatable tile (`piece`) filling the rect at its native scale
--   solid   a flat colour (`color` = { r, g, b, a }) on the rect
--   fade    nothing: the region is only faded (decoration with no kit equivalent)
--   picture a painted picture (`piece`, its greyscale twin `grey`) cropped to
--           the rect's aspect (`crop` = "bottom" | "top" | "middle"), or with
--           `fit = "right"` shown whole at the rect's height against its right
--           edge, its own left columns mirrored across the rest (a banner whose
--           subject sits at the right on plain stone); the single-rail edges
--           over it when `frame`
--------------------------------------------------------------------------------

-- RULES (user, 2026-09-21): borders are SINGLE-LINE and ONE WEIGHT unless
-- stated otherwise for an element. Every `frame` / `edge` rule uses the
-- single-rail family (window/single_*) at Kit.frameScale unless it names its
-- own prefix or scale; the window's double rail (window/frame_*) is only used
-- where the user asks for it. The family's edge is 11 px at 2x; 1.6 is the
-- user's pick (B1, ~7 px on screen at the kit scale).
Kit.framePrefix = "window/single"
Kit.frameScale = 1.6

Kit.Replacements = {
	-- window frames and their parts
	-- the OUTER border of every window (user, 2026-09-21): the window sheet as
	-- painted, double rail at 1.0 with the painted gem corners on top; the
	-- one place the single-rail rule does not apply
	-- (user: the wider border expands OUTSIDE the window, not into it: outset
	-- = the rail band's 48 px less its 6 px inner bevel, which stays on the edge)
	["NineSlicePanelTemplate"]                = { kind = "frame", level = 0, prefix = "window/frame", scale = 1.0, corners = "gem", outset = 42 },
	["TitleBar"]                              = { kind = "strip", base = "tabs/top", state = "open", heightScale = 1.5, onRail = true },   -- rune caps, red plate (the user's pick H), red matched to buttons/redbtn (F); 1.5 x the bar's height, same width; `onRail`: riding the OUTER rail across the whole window width, its caps' red gems on the rail's top corners in place of the frame's own gems (Kit:TitleOnRail), the title text with it (user, 2026-09-23: "combining B1 and having H3 as a header", layout C; was standing on the rail with the title caps, H1)
	["_UI-Frame-TopTileStreaks"]              = { kind = "fade" },   -- the streak band under the title: a stone band there read as a second, different backdrop (user, 2026-09-21); the page shows through
	["UI-Frame-PortraitMetal-CornerTopLeft"]  = { kind = "texture", piece = "window/portrait_ring", square = true, level = 1 },
	["RedButton-Exit"]                        = { kind = "state", base = "window/close", rect = "normal" },
	-- inset frames and backdrops
	["common-insideframe"]                    = { kind = "frame" },
	["common-insideframe-2x"]                 = { kind = "frame" },
	-- ONE stone per surface (user, 2026-09-23, the skills tab: "background 1
	-- and 2 are basically the same, they are loading 2 times for no reason"):
	-- a pane or backdrop picture that would look like the window's own stone
	-- is faded, not replaced with a second stone on top (tiles/stone over
	-- window/frame_body, each tiled from its own corner, showed its edge).
	-- The window's body runs on under it as one surface. A second surface is
	-- drawn only where it is meant to read as different (the darker list-box
	-- stone of an inset, a page picture, the parchment).
	-- The two pane backdrops: faded; the seam between the panes is drawn by
	-- common-framedivider alone, as in the default. The right pane's holder
	-- still carries its parchment sheet.
	["UI-Character-Info-General-BG"]          = { kind = "fade" },
	["UI-Character-Info-Stat-BG"]             = { kind = "fade" },
	["UI-Character-Info-Stat-StoneBG"]        = { kind = "frame" },
	["UI-Character-Info-Stat-StoneBG2"]       = { kind = "frame" },
	["common-framedivider"]                   = { kind = "edge", piece = "window/single_l" },
	-- lines, plates and list rows
	["UI-Character-Info-ScrollLine"]          = { kind = "strip", base = "window/divider" },
	["UI-Character-Info-ScrollLine-Long"]     = { kind = "strip", base = "window/divider" },
	-- a thin line inside a big soft-glow atlas: the atlas box says nothing about
	-- the line, so the divider keeps its natural kit size and spans half the box
	["UI-Character-Info-Honor-LevelBG"]       = { kind = "strip", base = "window/divider", natural = true, widthFrac = 0.5 },
	["UI-Character-Info-Title"]               = { kind = "strip", base = "lists/header" },
	["UI-Character-Info-ItemLevel-Bounce"]    = { kind = "strip", base = "lists/header" },
	["UI-Character-Info-Line-Bounce"]         = { kind = "strip", base = "lists/plate", state = "plain" },   -- a plain line in the game: the gemless plate
	["UI-Character-Info-Line-Bounce2"]        = { kind = "strip", base = "lists/plate", state = "plain" },
	["common-button-list-collapseExpand"]     = { kind = "strip", base = "lists/catplate", state = "closed" },   -- the plain category plate: one texture, no chevron (the game's +/- glyph stays)
	["charactercreate-customize-dropdown-linemouseover-middle"] = { kind = "strip", base = "lists/plate", state = "plain" },   -- the gemless plate: the gemmed row's gems overshoot a list row
	-- backdrop pictures with no frame of their own
	["ModelSceneBackground"]                  = { kind = "fade" },   -- the race landscape behind the character: faded, the window's stone runs on behind the model (one stone per surface)
	-- the ONE addition the default window does not have (the user's decision, catalogue pick B1):
	-- a single-rail iron frame around the character viewport, over its backdrop
	["ViewportFrame"]                         = { kind = "frame", body = false, level = 1, open = "r" },   -- open where it meets the pane divider
	-- slots and tabs
	-- gemSpan: the gems' centre-to-centre span as a fraction of the piece; with
	-- opts.pitch (the distance between neighbouring slots) the rim is sized so
	-- neighbours share a gem, as the game's slot pictures share their diamonds
	["UI-Character-Info-GearSlot"]            = { kind = "fade" },   -- a gear slot's frame art (its BorderFrame's picture): faded, the slot wears the action bars' thin rim on the button itself (CharacterPanel, Item Border; user 2026-09-23: "onto the Character Pane next"). Was the gemmed slot sized so neighbours shared a gem
	["common-sidetab"]                        = { kind = "slot", slot = "slot", rest = "checked", glow = true, sideTab = true, iconBleed = 2, keepIcon = true },   -- gold rim on every tab (the user's pick, I), additive glow when selected; `sideTab`: every window's at the Character window's size, in the one Side Tab Border (Kit:RegisterSideTab)
	-- small controls
	["checkbox-minimal"]                      = { kind = "state", base = "buttons/checkbox" },
	-- scroll bars (user, 2026-09-21: T2 / H1 / S1 is THE scroll bar, the only
	-- look for every MinimalScrollBar): the dark trough as the track, the gem
	-- slab thumb stretching with the content, the kit arrow buttons as steppers
	["minimal-scrollbar-track-middle"]        = { kind = "edge", piece = "bars/trough_v", scale = 1.0, level = -1 },   -- on the whole Track (Begin / End faded with it)
	["minimal-scrollbar-small-thumb-middle"]  = { kind = "vstrip", base = "lists/scrollthumb", widthScale = 1.25, level = 0 },   -- on the Thumb (Begin / End faded with it)
	["minimal-scrollbar-arrow-top"]           = { kind = "state", base = "buttons/arrow_up", natural = true },
	["minimal-scrollbar-arrow-bottom"]        = { kind = "state", base = "buttons/arrow_down", natural = true },
	-- progress bars (user, 2026-09-21: P1): the hollow bar bracket with the
	-- trough in its opening, under the game's tinted fill and its text
	["common-stat-bar-BG"]                    = { kind = "bar", bar = "frame", heightScale = 0.85 },   -- the character pane's skill / reputation bars: P1 at 0.85 of the bar's height (user, 2026-09-21: the borders 15 % smaller), the fill fitted into the smaller opening by the panel
	-- list glyphs (user, 2026-09-21: consistency — every check box, expand /
	-- collapse control and toggle in a window is the kit's): the +/- plates
	-- on the glyph's rect, the plus for a collapsed header, the minus for an open one
	["common-button-list-plus"]               = { kind = "state", base = "buttons/plus", natural = true },
	["common-button-list-minus"]              = { kind = "state", base = "buttons/minus", natural = true },
	["campaign_headericon_closed"]            = { kind = "state", base = "buttons/plus", natural = true, rect = "normal" },   -- a sub-header's toggle, collapsed
	["campaign_headericon_open"]              = { kind = "state", base = "buttons/minus", natural = true, rect = "normal" },  -- ... open
	-- the character window's equipment manager
	["UI-Character-Info-OutfitCard"]          = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 0 },   -- an outfit card: the gemless plate ...
	["UI-Character-Info-OutfitCard-Hover"]    = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- ... its hover (shown / hidden by the game)
	["UI-Character-Info-OutfitCard-Selected"] = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... its selected bar (likewise)
	["common-button-tertiary-normal"]         = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8, capOverhang = 0.35 },   -- New Set (a tertiary button re-atlased with its state): the red plate (B1), the game's + icon and text on top
	-- the spell book (user's picks, 2026-09-21: P1 C1 H3 K1 T1); the talents
	-- page stays the game's until the user's per-class art arrives
	-- The PAGES (user, 2026-09-23: backgrounds keep one resolution, never
	-- stretched): the painted page pictures are gone from them; the stone
	-- pages repeat tiles/concrete (the page stone's own middle), the paper
	-- pages tiles/vellum (the parchment page's middle), from the rect's
	-- middle or top (`crop`), their painted edges as before.
	["spellbook-Page-Right-C60"]              = { kind = "picture", piece = "tiles/vellum", crop = "middle", level = -1, edge = "brush" },   -- the book page: the user's parchment page painting (parchmentnew, 2026-09-21; painted at the page's 1.15 aspect), one UNDER the SpellBookFrame (level 100: well above the window's skin, below every control on the page)
	["spellbook-Page-Left-C60"]               = { kind = "picture", piece = "tiles/vellum", crop = "middle", level = -1, edge = "brush", edgeMirror = true },   -- the left page's strokes flipped, so the two pages are not twins
	["spellbook-Tab-Frame-C60"]               = { kind = "slot", slot = "slot" },   -- a category tab (C1): the slot rim over the icon, gold (checked) while the tab is selected
	["spellbook-list-backplate"]              = { kind = "fade" },   -- the list header's backplate (H3: the text on the page)
	["spellbook-divider"]                     = { kind = "strip", base = "window/divider" },   -- the line under the header (H3)
	["spellbook-item-backplate"]              = { kind = "fade" },   -- a spell card: no plate (user re-picked K4 from K1 on sight), the rim and text on the page
	["spellbook-item-iconframe"]              = { kind = "slot", slot = "slot" },   -- an active spell's icon frame: the square rim
	["spellbook-item-iconframe-inactive"]     = { kind = "slot", slot = "slot" },
	["spellbook-item-iconframe-passive"]      = { kind = "slot", slot = "roundslot" },   -- a passive's: the round rim (the icon is round)
	["spellbook-item-iconframe-passive-inactive"] = { kind = "slot", slot = "roundslot" },
	["talents-node-circle-gray"]              = { kind = "slot", slot = "roundslot" },   -- what this client puts on a passive spell's icon
	["uiframe-tab-left"]                      = { kind = "frame", level = 0, hover = 1.15 },   -- a window's bottom / top tab (TB6, user 2026-09-21; was T1, the tabs/top plate): the single rail with the stone card on the tab's rect, a holder at the tab's own level (its stone and rails under the tab's OVERLAY text, above the window's rail), brighter on hover
	["uiframe-activetab-left"]                = { kind = "frame", level = 0, lit = { 1.45, 1.3, 0.85 } },   -- ... the open tab: the same card with its iron lit gold (as a selected R3 row); each on the tab's rect, the one the game shows
	["common-dropdown-a-button"]              = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the small round dropdown arrow: the cog plate under the game's arrow (K2)
	["common-dropdown-a-button-shadowless"]   = { kind = "state", base = "buttons/arrow_down", natural = true },   -- the same template with hasShadow false (WowStyle1ArrowDropdownTemplate; the damage meter's type dropdown, keyed by hand): the kit's down arrow in the arrow's place (user, 2026-09-23: A of kit_raw/meter_arrow_catalog.png) -- not K2, whose cog would stand beside the header's settings cog
	["RedButton-Expand"]                      = { kind = "state", base = "buttons/arrow_up", natural = true, rect = "normal" },   -- the window's maximize / minimize
	["RedButton-Condense"]                    = { kind = "state", base = "buttons/arrow_down", natural = true, rect = "normal" },
	-- the professions window (user's picks, 2026-09-21: A, F crop 1, K1)
	-- the book page's backdrop: the user's own page painting (the kit's soft
	-- stones, tiles/crackle and a plain grey were all tried before it)
	["Profession-Background-Overview"]        = { kind = "picture", piece = "tiles/concrete", crop = "middle", level = 1, edge = "brush" },   -- one ABOVE the window (the window's own skin is at its level: a tie there draws in an order the client may change between loads)   -- the user's grey stone page with gothic pilasters (2026-09-21), painted at the page's own aspect
	["Profession-overview-Card"]              = { kind = "frame" },   -- a primary card with no profession in it (A): single rail, stone body
	-- a primary card with a profession: the game re-atlases its Background to
	-- -<Profession> in FormatProfession; each gets its painted banner (the
	-- still-life at the right on stone, user's sheets 2026-09-21), whole at the
	-- card's height against its right edge (nothing of the still-life cut
	-- off), the stone mirrored across the rest, the single rail over it
	["Profession-overview-Card-Alchemy"]       = { kind = "picture", piece = "cards/alchemy", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Alchemy"]     = { kind = "picture", piece = "backdrops/profession_alchemy", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Blacksmithing"] = { kind = "picture", piece = "cards/blacksmithing", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Blacksmithing"]= { kind = "picture", piece = "backdrops/profession_blacksmithing", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Enchanting"]    = { kind = "picture", piece = "cards/enchanting", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Enchanting"]  = { kind = "picture", piece = "backdrops/profession_enchanting", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Engineering"]   = { kind = "picture", piece = "cards/engineering", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Engineering"] = { kind = "picture", piece = "backdrops/profession_engineering", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Herbalism"]     = { kind = "picture", piece = "cards/herbalism", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Herbalism"]   = { kind = "picture", piece = "backdrops/profession_herbalism", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Leatherworking"]= { kind = "picture", piece = "cards/leatherworking", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Leatherworking"]= { kind = "picture", piece = "backdrops/profession_leatherworking", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Mining"]        = { kind = "picture", piece = "cards/mining", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Mining"]      = { kind = "picture", piece = "backdrops/profession_mining", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Skinning"]      = { kind = "picture", piece = "cards/skinning", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Skinning"]    = { kind = "picture", piece = "backdrops/profession_skinning", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Tailoring"]     = { kind = "picture", piece = "cards/tailoring", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Tailoring"]   = { kind = "picture", piece = "backdrops/profession_tailoring", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	-- the secondary professions' schematics: their own tall panels (user's sheet 3d259005, 2026-09-21), cut at the schematic's aspect on the band with the still-life
	["Profession-background-card-Cooking"]    = { kind = "picture", piece = "backdrops/schematic_cooking", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },
	["Profession-background-card-Fishing"]    = { kind = "picture", piece = "backdrops/schematic_fishing", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },
	["Profession-background-card-FirstAid"]   = { kind = "picture", piece = "backdrops/schematic_firstaid", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },
	["Profession-overview-card-generic-Cooking"]  = { kind = "picture", piece = "backdrops/profession_cooking", grey = "backdrops/profession_cooking_grey", crop = "bottom", frame = true, desaturate = 0.9 },   -- a secondary card (F, crop 1): the still-life, grey while not learned, single rail over it
	["Profession-overview-card-generic-Fishing"]  = { kind = "picture", piece = "backdrops/profession_fishing", grey = "backdrops/profession_fishing_grey", crop = "bottom", frame = true, desaturate = 0.9 },
	["Profession-overview-card-generic-FirstAid"] = { kind = "picture", piece = "backdrops/profession_firstaid", grey = "backdrops/profession_firstaid_grey", crop = "bottom", frame = true, desaturate = 0.9 },
	["Profession-square-frame"]               = { kind = "slot", slot = "slot" },   -- the frame over a profession spell's icon: the rim over the icon, as the game's is
	-- the crafting page (user's picks, 2026-09-21: S1 D1 B1 N1 R1 O1 K2 L1 T1)
	["Profession-Background-Template2"]       = { kind = "picture", piece = "tiles/concrete", crop = "middle", level = -2, edge = "brush" },   -- the crafting page's backdrop: the same page stone as the book's; TWO under the page, so the list box and the schematic picture (one under their frames, which may sit at the page's level) never tie with it
	["Professions-background-summarylist"]    = { kind = "frame" },   -- the recipe list box (L1): single rail, stone body
	["common-search-border-middle"]           = { kind = "strip", base = "inputs/edit", state = "normal", owner = true },
	["common-dropdown-b-button"]              = { kind = "frame", level = -1, hover = 1.25, pressed = 0.75, disabled = 0.6 },   -- the filter dropdown (B6, user 2026-09-21): the single-rail band with stone, its states by tint
	["_128-RedButton-Center"]                 = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8, capOverhang = 0.35 },   -- B1: the plate at the button's height, its gem caps reaching past the button's ends (the game's Left / Right pieces sit outside its Center too)
	["_128-RedButton-Center-Disabled"]        = { kind = "strip", base = "buttons/redbtn", state = "disabled", owner = true, heightScale = 0.8, capOverhang = 0.35 },
	["UI-SpellbookIcon-PrevPage-Up"]          = { kind = "state", base = "buttons/arrow_left", natural = true, fit = "height" },   -- the spinner's - / + (N1), as tall as their buttons, flush to the plate; also the character window's pane toggle (PrevPage = open, NextPage = collapsed)
	["UI-SpellbookIcon-NextPage-Up"]          = { kind = "state", base = "buttons/arrow_right", natural = true, fit = "height" },
	["Professions-Slot-Frame"]                = { kind = "slot", slot = "slot" },   -- a reagent slot's frame over its icon (R1)
	["auctionhouse-itemicon-border-white"]    = { kind = "slot", slot = "roundslot" },   -- the output icon's quality-coloured border (O2, user 2026-09-21): the round rim, tinted like the border
	["common-button-tertiary-square-normal"]  = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the link button's plate (K2), under the game's chain-link icon
	["Professions_Recipe_Hover"]              = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a region of the row under its text (the game's translucent hover is HIGHLIGHT over it)
	["Professions_Recipe_Active"]             = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },
	["Professions-skillbar-bg"]               = { kind = "bar", bar = "frame", layer = "ARTWORK", sublevel = 4 },   -- the crafting page's rank bar: the same P1 as the book's
	["Profession-ProgressBar-BG"]             = { kind = "bar", bar = "frame", layer = "ARTWORK", sublevel = 4 },   -- the rank bars (P1): the masked fill is ARTWORK 2, so the bracket's caps go to 4 and its middle (one below the caps) to 3, both over the fill
	-- shared controls met in the legacy / quest log / guild windows (2026-09-21)
	["UI-Panel-Button-Up"]                    = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8, capOverhang = 0.35 },   -- UIPanelButtonTemplate (Left / Middle / Right file pieces; keyed by hand, file textures read back as ids): the red plate (B1), as the 128-RedButton
	["UI-CheckBox-Up"]                        = { kind = "state", base = "buttons/checkbox" },   -- the classic check box (file art; keyed by hand): the kit's, as checkbox-minimal
	["questlog-icon-ticksquare"]              = { kind = "state", base = "buttons/checkbox" },   -- the quest log's tracking tick box (a Frame with a CheckMark the game shows / hides)
	["ui-journeys-delve-arrow-small-left"]    = { kind = "state", base = "buttons/arrow_left", natural = true, rect = "normal" },   -- a reward track's scroll arrows
	["ui-journeys-delve-arrow-small-right"]   = { kind = "state", base = "buttons/arrow_right", natural = true, rect = "normal" },
	["128-redbutton-plus"]                    = { kind = "state", base = "buttons/plus", natural = true },    -- a card's expand glyph (the legacy challenge cards)
	["128-redbutton-minus"]                   = { kind = "state", base = "buttons/minus", natural = true },
	-- the legacy window (Blizzard_LegacySystem: the reward track, challenges
	-- and tree pages; the tree's nodes are talent buttons and stay the game's,
	-- as the talents page does). Picks pending the user's catalogue choice
	-- for the cards (kit_raw/legacy_catalog.png); the rest are the fixed looks.
	["Legacy-Rewards-Tracker-background"]     = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true, edge = "brush" },   -- a page's backdrop: the page stone as a REGION of the page in the backdrop's own layer (the pages sit at level 100 with children at 800: no holder, no tie), fitted to the WINDOW's rect so all three pages show the same picture in the same place
	["Legacy-Challenge-BG"]                   = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true, edge = "brush" },
	["Legacy-Tree-Frame-background"]          = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true, edge = "brush" },
	["Legacy-Tree-Frame-divider-Vertical"]    = { kind = "edge", piece = "window/single_l" },   -- the pane divider (12 x 503): the single rail, as common-framedivider
	["Legacy-Progressbar-Frame"]              = { kind = "bar", bar = "frame", layer = "ARTWORK", sublevel = 2 },   -- LegacyProgressBarTemplate (a StatusBar: the fill at ARTWORK 0, the bracket in OVERLAY, the text over it): P1, the bracket's caps at ARTWORK 2 and its middle at 1 over the fill, the StatusBar moved into the opening (Kit:SkinStatusBar)
	["Legacy-Challenge-Left-Sub-Tab"]         = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a category list leaf (the button's normal texture, re-atlased with the selection): the plain plate ...
	["Legacy-Challenge-Left-Sub-Tab-selected"] = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... and the selected one (one rep per atlas seen, the current shown)
	["Legacy-Challenge-Cards-Bar"]            = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a criteria row's bar (180 x 30) under its text: the plain plate
	["Legacy-Tree-Frame-Points-Bar"]          = { kind = "strip", base = "lists/header" },   -- the "Available points" plate: the header plate
	["Legacy-Tree-Frame-icon-frame"]          = { kind = "slot", slot = "roundslot" },   -- a challenge's icon frame (the icon is masked round by UI-Frame-IconMask): the round rim (O2)
	["Legacy-Tree-Frame-Ring-big"]            = { kind = "slot", slot = "roundslot" },   -- the selected tree's big ring (130 on a 110 icon)
	["Legacy-Tree-Frame-Card-Ring"]           = { kind = "slot", slot = "roundslot", glow = true },   -- a tree card's ring (70 on a 67 icon); LT4 (user, 2026-09-21): the rim only, lit (the rim's hover look, additive) while the card is checked
	["Legacy-Tree-Frame-Card"]                = { kind = "fade" },   -- LT4: no card behind the ring ...
	["Legacy-Tree-Frame-Card-Glow"]           = { kind = "fade" },   -- ... and the game's selection glow is the rim's own glow now
	["Legacy-Tree-Frame-level-circle"]        = { kind = "texture", piece = "deco/gem_large", square = true, owner = true },   -- the spent-points circle (LS1): the large gem, the frame's own text over it
	["Legacy-Challenge-Cards"]                = { kind = "frame" },   -- a challenge card's body (LC1): single rail + stone on the card's rect, whatever the game atlases its Background to (complete / incomplete, collapsed / the expanded tiled trio)
	["Legacy-Challenge-Cards-Disable"]        = { kind = "frame" },
	["Legacy-Challenge-Cards-Ribbon-Brown"]   = { kind = "strip", base = "lists/header", owner = true },   -- the card's title ribbon (LC1): the header plate as a region under the Label, one rep per atlas seen (brown / blue = account-wide, each with a -Disable)
	["Legacy-Challenge-Cards-Ribbon-Blue"]    = { kind = "strip", base = "lists/header", owner = true },
	["Legacy-Challenge-Cards-Ribbon-Brown-Disable"] = { kind = "strip", base = "lists/header", owner = true },
	["Legacy-Challenge-Cards-Ribbon-Blue-Disable"]  = { kind = "strip", base = "lists/header", owner = true },
	["Legacy-Rewards-Tracker-Cards"]          = { kind = "frame" },   -- a reward card's body (LR1): single rail + stone on the card's rect (re-atlased -Green / -Disable by the game)
	["Legacy-Rewards-Tracker-Cards-Green"]    = { kind = "frame" },
	["Legacy-Rewards-Tracker-Cards-Disable"]  = { kind = "frame" },
	["Legacy-Rewards-Tracker-Diamond"]        = { kind = "texture", piece = "deco/gem_large", square = true, owner = true },   -- the card's level diamond (LD2): the large gem on its rect, the Level text over it; one rep per atlas
	["Legacy-Rewards-Tracker-Diamond-Disable"] = { kind = "texture", piece = "deco/gem_large", square = true, owner = true },
	["Legacy-Rewards-Tracker-Icons-Frame"]    = { kind = "slot", slot = "slot" },   -- a reward card's icon border (80 on a 64 square icon; re-atlased -Disable while unearned): the square rim (R1), one rep per atlas
	["Legacy-Rewards-Tracker-Icons-Frame-Disable"] = { kind = "slot", slot = "slot" },
	-- the quest log (QuestMapFrame in the world map window; 2026-09-21)
	["QuestLog-main-background"]              = { kind = "picture", piece = "tiles/vellum", crop = "middle", owner = true, edge = "brush", edgeBacking = "window/single_body" },   -- the list's page (QP2, user 2026-09-21): the parchment page painting, as the spell book's; also MelloUI's own quest list window
	["QuestDetailsBackgrounds"]               = { kind = "picture", piece = "tiles/vellum", crop = "top", owner = true, edge = "brush", edgeBacking = "window/single_body" },   -- a quest's details page: the same parchment
	["MapTitleBand"]                          = { kind = "picture", piece = "tiles/concrete", crop = "top", level = 0 },   -- an agreed addition (user, 2026-09-21): a body-off window's title band (the map for its canvas; the collections and LFG pages, whose rock starts below the title) filled with the page stone, inside the outer rail, so it is not bare once the title plate stands on the rail
	["questlog-frame"]                        = { kind = "frame", body = false },   -- the border around the list / details (QuestLogBorderFrameTemplate): the single rail, edges only
	["QuestLog-frame-devider"]                = { kind = "strip", base = "window/divider" },   -- the line under a header
	["questlog-icon-setting"]                 = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the list's settings button (a 15 x 16 gear glyph): the cog plate (K2), as the dropdown arrows
	["questlog-quest-glow-yellow"]            = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a quest title's highlight (the game shows it on hover / selection): the plate's hover look
	["QuestListFilter"]                       = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- MelloUI's Quests panel filter buttons (F7, user 2026-09-21): the plain plate (hover from the button) ...
	["QuestListFilter-Selected"]              = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... the selected plate on the active filter (from the panel's db.filter)
	-- the guild and communities window (CommunitiesFrame; file art keyed by hand; 2026-09-21)
	["UI-Background-Rock"]                    = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true },   -- ButtonFrameTemplate's rock background: the page stone as a region of the frame
	["bluemenu-main"]                         = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a communities list entry's background (the sheet's blue plate): the plain plate
	["bluemenu-main-selected"]                = { kind = "fade" },   -- ... its selection bar: faded, the card's iron lights instead
	["CommunitiesListEntry"]                  = { kind = "frame", hover = 1.15, pressed = 0.9, checkedTint = { 1.45, 1.3, 0.85 } },   -- a communities list entry (68 px tall: a TALL row, R3 — the plate's rails got fat): the single-rail card with stone, its iron lit gold while the game shows its Selection
	["communities-ring-gold"]                 = { kind = "slot", slot = "roundslot" },   -- the entry's icon ring: the round rim
	["CommunitiesListBody"]                   = { kind = "tile", piece = "window/single_body", owner = true },   -- the communities list's box (L1), in two parts: the stone body as a REGION of the list under its rows (the list's blue Bg, filigrees faded) ...
	["CommunitiesListBox"]                    = { kind = "frame", body = false },   -- ... and the single rail on the list's InsetFrame rect at that frame's own level (200: over the rows), the gold border faded
	["common-dropdown-textholder"]            = { kind = "strip", base = "inputs/dropdown", state = "normal", owner = true },   -- a text dropdown (WowStyle1DropdownTemplate): the dropdown plate (D1), its painted cap in place of the game's arrow, hover from the button
	["UI-Background-Marble"]                  = { kind = "fade" },   -- the marble strip under a list's scroll bar: nothing stands in (the trough is the bar's)
	["UI-ChatInputBorder-Mid2"]               = { kind = "strip", base = "inputs/edit", state = "normal", owner = true },   -- the chat edit box (Left / Mid / Right file pieces): the edit plate (S1)
	["UI-ClassTrainer-HorizontalBar"]         = { kind = "fade" },   -- the guild info page's horizontal bars over its headers: faded — a gem-capped divider stacked on a gem-capped header plate read as clutter (user, 2026-09-21); the plate alone marks the section
	["GuildFrame-Header"]                     = { kind = "strip", base = "lists/header", owner = true },   -- a guild page header (GH1, user 2026-09-21; a region of the GuildFrame sheet, keyed by hand): the header plate as a region under the page's text
	["ColumnDisplayButton"]                   = { kind = "strip", base = "lists/header", owner = true },   -- a roster column header (GC1, user 2026-09-21; WhoFrame-ColumnTabs file pieces, keyed by hand): the header plate per column, hover from the button
	["GuildNewsRow"]                          = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a guild news row (GP1, user 2026-09-21): the plain plate under the row's text, hover from the button; the blue highlight faded
	["GuildFrame-Bar"]                        = { kind = "bar", bar = "frame" },   -- the guild reputation bar (CommunitiesGuildProgressBarTemplate): P1
	["GuildFrame-Sheet"]                      = { kind = "fade" },   -- the guild info / news pages' sheet backgrounds (GuildFrame file pieces, keyed by hand): faded, the page stone shows
	["UI-Frame-InnerBorderPiece"]             = { kind = "fade" },   -- loose inset-border textures (the roster's column band, the info page's two columns): faded — the inset rail and the pane divider stand in
	["UIDropDownMenu"]                        = { kind = "strip", base = "inputs/dropdown", state = "normal", owner = true },   -- an old-style dropdown (Left / Middle / Right file art 64 px tall with the box in its middle; keyed by hand): D1 fitted to the box's 24 px, the arrow button faded
	-- the dungeon finder (PVEFrame) and the collections (CollectionsJournal), 2026-09-21 first pass
	["bluemenu-Ring"]                         = { kind = "slot", slot = "roundslot" },   -- a group button's ring on its masked icon (the dungeon finder's left column): the round rim
	["bluemenu-shadowcovers"]                 = { kind = "fade" },   -- the shadow strips beside the left column: nothing stands in
	["UI-LFG-BlueBG"]                         = { kind = "fade" },   -- the listing page's blue role band (file art, keyed by hand): faded — the window's one page picture runs under it; only the INSIDE of the inset rail is the darker stone (user, 2026-09-21)
	["UI-LFG-BACKGROUND-QUESTPAPER"]          = { kind = "picture", piece = "tiles/vellum", crop = "middle", owner = true },   -- the queue frame's paper (file art, keyed by hand): the parchment page, as the quest lists
	["PetList-ButtonBackground"]              = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a mount / pet list row: the plain plate (hover from the button) ...
	["PetList-ButtonSelect"]                  = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... and the selected plate, shown / hidden by the game
	["WhiteIconFrame"]                        = { kind = "slot", slot = "slot" },   -- a list row's icon border (file art, keyed by hand): the square rim (R1) on the icon
	["collections-background-tile"]           = { kind = "tile", piece = "window/single_body", owner = true },   -- an icon grid's tiled backdrop (the wardrobe's items, toys, heirlooms): the list box's stone (L1) as a region under the slots, set off from the window's page stone (user, 2026-09-21), the single rail around it
	["collections-background-shadow-large"]   = { kind = "fade" },   -- the grid's shadowed edges and corners: nothing stands in (the inset rail is the edge)
	["collections-background-shadow-small"]   = { kind = "fade" },
	["collections-background-corner"]         = { kind = "fade" },
	-- the vanilla-style group finder (LFGParentFrame; 2026-09-21)
	["groupfinder-background"]                = { kind = "tile", piece = "window/single_body", owner = true },   -- the pages' INSET backdrop (the listing's category area, the browse list): the darker list-box stone as a region (user, 2026-09-21: the page stone there was too light)
	["WhoListBody"]                           = { kind = "tile", piece = "window/single_body", owner = true },   -- the who list's box: the darker list-box stone as a region under its rows (the page has no inset picture of its own there; user, 2026-09-21)
	["groupfinder-background-page"]           = { kind = "fade" },   -- the browse page's page-level painting (over its inset): faded — the window's page stone is under it already, and the inset's darker stone must show
	["groupfinder-button-cover"]              = { kind = "frame", body = false, level = 0 },   -- a category button's cover (the border over its painted banner; user, 2026-09-21): the single rail, edges only, at the button's own level so it sits over the painting (a region of the button); the painting, selection and hover stay the game's
	["groupfinder-Stat-StoneBG"]              = { kind = "fade" },   -- the who list's header band: faded — the window's one page picture runs under it (a second stone met it with a seam)
	["glues-characterSelect-searchbar"]       = { kind = "fade" },   -- the who search box's own backdrop (the S1 plate stands in)
	["UI-SquareButton-Up"]                    = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- a square icon button's plate (the browse refresh; file art keyed by hand): K2, the game's icon on top
	["shop-list-rule"]                        = { kind = "strip", base = "window/divider" },   -- the activity list's rule line
	["LFGBrowse-Result"]                      = { kind = "frame", hover = 1.15, pressed = 0.9, checkedTint = { 1.45, 1.3, 0.85 } },   -- a TALL list row (R3, user 2026-09-21; the plate's rails got fat stretched to 50-60 px): a single-rail card with stone under the row, its iron lit gold while the game marks it selected, brighter on hover
	["LFGBrowse-Grouping"]                    = { kind = "strip", base = "lists/catplate", state = "closed", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a browse grouping header: the category plate
	["groupfinder-highlightbar-yellow"]       = { kind = "fade" },   -- the selected result's bar: faded, the card's iron lights instead (R3)
	["QuestLog-icon-Expand"]                  = { kind = "state", base = "buttons/plus", natural = true },    -- a grouping header's glyphs (two textures the game shows / hides)
	["QuestLog-icon-shrink"]                  = { kind = "state", base = "buttons/minus", natural = true },
	["common-button-list-large"]              = { kind = "frame", hover = 1.15, pressed = 0.9, checkedTint = { 1.45, 1.3, 0.85 } },   -- a who list row (the large list plate, 58 px tall): R3, as the browse rows
	["common-button-list-large-selected"]     = { kind = "fade" },   -- its selected bar: faded, the card's iron lights instead
	-- junctions of rails (T and +): the game has no art there, so this is an
	-- agreed addition (user, 2026-09-21: pick K, the slider thumb's gem, on
	-- every junction), placed by Kit:Joint at the kit's natural size
	["RailJoint"]                             = { kind = "texture", piece = "inputs/slider_thumb_normal", natural = true, level = 1 },

	-- The HUD's unit frames (UnitFramePanel; user's picks B3 R1 L1 N3 from
	-- kit_raw/unitframe_catalog.png, 2026-09-21). The game's frame picture
	-- (ring + name band + both bar rims in ONE texture) is faded and pieces
	-- stand on the frame's own sub-rects:
	["UI-HUD-UnitFrame-Player-PortraitOn"]    = { kind = "fade" },   -- the composite picture (player; the vehicle / class-resource / rare / minus variants are the same region re-atlased)
	["UI-HUD-UnitFrame-Target-PortraitOn"]    = { kind = "fade" },   -- ... target / focus
	["UI-HUD-UnitFrame-TargetofTarget-PortraitOn"] = { kind = "fade" },   -- ... target of target / pet
	["UI-HUD-UnitFrame-Player-PortraitOn-Vehicle"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Player-PortraitOn-ClassResource"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Player-PortraitOn-InCombat"] = { kind = "fade" },   -- the combat / threat flashes and status rings: faded (decoration)
	["UI-HUD-UnitFrame-Target-PortraitOn-InCombat"] = { kind = "fade" },
	["UI-HUD-UnitFrame-TargetofTarget-PortraitOn-InCombat"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Player-PortraitOn-Status"] = { kind = "fade" },
	["UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Status"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment"] = { kind = "fade" },   -- the corner flourish on the player ring
	["UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold"] = { kind = "fade" },   -- the elite / rare / boss rings: faded, the kit ring tinted gold / silver instead
	["UnitFramePortraitRing"]                 = { kind = "texture", piece = "window/portrait_ring", opening = true, owner = true },   -- R1: the ring's OPENING on the game's portrait rect, as a region in the faded picture's layer
	["UnitFrameBar"]                          = { kind = "bar", bar = "frame", dropCap = "l", capOut = true, troughSub = -1 },   -- B3: the P1 bracket on the bar, ring side capless, the far cap grown outward; the trough under the BACKGROUND-0 fill
	["UnitFrameBarMirrored"]                  = { kind = "bar", bar = "frame", dropCap = "r", capOut = true, troughSub = -1 },   -- ... the target's (ring on the right)
	["UnitFrameHealthBar"]                    = { kind = "bar", bar = "frame", dropCap = "l", capOut = true, troughSub = -1, state = "red" },   -- a health bar: the same B3, its end gem kept red (user, 2026-09-23, painted on the player frame) where every other bracket's is iron
	["UnitFrameHealthBarMirrored"]            = { kind = "bar", bar = "frame", dropCap = "r", capOut = true, troughSub = -1, state = "red" },
	["UI-HUD-UnitFrame-SmallCircle"]          = { kind = "texture", piece = "buttons/orb_normal", square = true, owner = true },   -- L1: the level circle (and the PvP badge's circle): the orb plate under the frame's own text / faction icon
	["UI-HUD-UnitFrame-Target-PortraitOn-Type"] = { kind = "fade" },   -- the target's reaction strip (the name band): faded, the plate below stands on its rect

	-- ... the party frames (UnitFramePanel too, the same picks; the member frame's picture is ARTWORK 0 with the
	-- name after it in ARTWORK, so the ring and the band go to BACKGROUND above the portrait, under the name)
	["UI-HUD-UnitFrame-Party-PortraitOn"]     = { kind = "fade" },   -- a party member's picture (and the pet's, `ui-hud-unitframe-party-portraiton` at half scale)
	["UI-HUD-UnitFrame-Party-PortraitOn-Vehicle"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Party-PortraitOn-InCombat"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Party-PortraitOn-Status"] = { kind = "fade" },
	["UnitFramePortraitRingParty"]            = { kind = "texture", piece = "window/portrait_ring", opening = true, owner = true, layer = "BACKGROUND", sublevel = 2 },   -- R1 on a party member / pet portrait
	["PartyFrameBackground"]                  = { kind = "frame" },   -- Edit Mode's optional party backdrop (a BackdropTemplate frame): L1, the single rail with the stone body, as its child

	-- The HUD's compact raid frames (RaidFramePanel; user's picks F1 G1 from kit_raw/raidframe_catalog.png, 2026-09-21)
	["raidframe-hp-bg-white"]                 = { kind = "frame", scale = 0.8, owner = true, bodyLayer = "BACKGROUND", bodySub = 1, edgeLayer = "ARTWORK", edgeSub = -1 },   -- F1: a compact frame's dark backing → the single rail at a small scale with the stone under the fills, as REGIONS of the frame: the stone above the faded backing, the rails above the BORDER fills and under the ARTWORK icons / name
	["options_frame_child"]                   = { kind = "frame", body = false },   -- G1: a raid group's border (`borderFrame`, shown by Edit Mode's 'display border'): the single rail 1.6, following the game's show / hide
	["UI-HUD-UnitFrame-TotemFrame"]           = { kind = "texture", piece = "buttons/roundslot_normal", square = true, owner = true },   -- a totem's round border (30 px OVERLAY over its 22 px masked icon): the round rim (O2) on its rect

	-- The HUD's action bars, micro menu, bag bar and status bars (ActionBarPanel; user's picks X2 M1 from
	-- kit_raw/actionbar_catalog.png, 2026-09-21; the buttons R1 by the rule book, the bar art faded as it lies under the rims)
	["ActionButtonRim"]                       = { kind = "slot", slot = "rim", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },   -- an action / stance / pet button on the action bars: the THIN rim on the button's own rect, no gems (user, 2026-09-23: the gems moved to one backdrop round the bar, ActionBarPanel); its states hover / pressed / checked as the slot's. Button Border "Thin iron"; the four below are its other looks (Tools/build_kit.py THIN_RIMS)
	["ActionButtonRimHairline"]               = { kind = "slot", slot = "rimhair", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },
	["ActionButtonRimRounded"]                = { kind = "slot", slot = "rimround", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },
	["ActionButtonRimGold"]                   = { kind = "slot", slot = "rimgold", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },
	["ActionButtonRimSunk"]                   = { kind = "slot", slot = "rimsunk", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },
	["UI-HUD-ActionBar-IconFrame"]            = { kind = "slot", slot = "slot", gemSpan = { 97 / 135, 92 / 130 }, layer = "ARTWORK", sublevel = 2 },   -- an action / stance / pet / bag button's rim (its NormalTexture): R1 — the slot rim sized to the bar's pitch so neighbours share a gem, at the NormalTexture's ARTWORK under the OVERLAY name, count, keybind and highlights; the icon fitted into its opening (Kit:SkinActionButton)
	["UI-HUD-ActionBar-IconFrame-Background"] = { kind = "tile", piece = "tiles/stone", owner = true, sublevel = -1 },   -- an empty slot's backing: the stone in the rim's opening, UNDER the icon (BACKGROUND -1), shown as the game shows the backing (empty slots only)
	["ui-hud-actionbar-iconframe-slot"]       = { kind = "fade" },   -- the empty slot's ornament
	["UI-HUD-ActionBar-IconFrame-Border"]     = { kind = "fade" },   -- the equipped-item border: faded, the rim tinted green while the game shows it
	["UI-HUD-ActionBar-Frame"]                = { kind = "fade" },   -- a bar's frame art (main bar, micro menu, bag bar): it lies under the pitch-sized rims
	["MicroMenuBackgroundArt"]                = { kind = "fade" },   -- the micro menu's backing (an IconFrame-Background region, keyed by hand)
	["ui-hud-actionbar-gryphon-left"]         = { kind = "texture", piece = "deco/rail_cap_l", fit = "height", anchor = "BOTTOMRIGHT" },   -- X2: the left end cap → the rail's orb cap, the gryphon's height, standing at the bar's end — on a holder at the BAR's level, under its buttons (user, 2026-09-21: the caps behind the bar)
	["ui-hud-actionbar-gryphon-right"]        = { kind = "texture", piece = "deco/rail_cap_r", fit = "height", anchor = "BOTTOMLEFT" },
	["ui-hud-actionbar-pageuparrow-up"]       = { kind = "state", base = "buttons/arrow_up", natural = true },   -- the page arrows: the kit's arrows at their size
	["ui-hud-actionbar-pagedownarrow-up"]     = { kind = "state", base = "buttons/arrow_down", natural = true },
	["MicroButtonRim"]                        = { kind = "slot", slot = "rim", pitchSize = 1, layer = "OVERLAY", sublevel = 1 },   -- a micro button's plate -> the THIN rim, a square of the size ActionBarPanel gives it (SetPitch): the bag bar's slot size, the buttons spaced as the bag slots are (user, 2026-09-23: "make the microbar buttons match the bag button slots in size and have the same distance to borders"); the game's glyph fitted inside
	["UI-HUD-MicroMenu-ButtonBG-Up"]          = { kind = "slot", slot = "slot", gemSpan = { 97 / 135, 92 / 130 }, layer = "OVERLAY", sublevel = 1 },   -- a micro button's plate → the R1 slot rim sized to the button's pitch (neighbours share a gem), the game's glyph inside it, nothing painted behind (user, 2026-09-22: the cog plates M1 were not wanted, the rim is)
	["UI-HUD-MicroMenu-ButtonBG-Down"]        = { kind = "fade" },
	["UI-HUD-ExperienceBar-Frame"]            = { kind = "bar", bar = "frame", capOut = true },   -- the XP / reputation / honour bar's frame: P1, the caps outside the bar so the fill keeps its width
	["UI-HUD-ExperienceBar-Background"]       = { kind = "fade" },   -- its trough art: the bracket's trough
	["UI-HUD-ExperienceBar-Divider"]          = { kind = "texture", piece = "bars/tick", natural = true, owner = true },   -- the status bar's 20 segment dividers (pooled StatusBarDividerTemplate frames): the kit's tick at its size on each
	["UI-HUD-ActionBar-Frame-Divider-ThreeSlice-EdgeTop"] = { kind = "fade" },   -- the main bar's dividers between its buttons (pooled three-slice frames): under the rims
	["UI-HUD-ActionBar-Frame-Divider-ThreeSlice-EdgeBottom"] = { kind = "fade" },
	["!UI-HUD-ActionBar-Frame-Divider-ThreeSlice-Center"] = { kind = "fade" },
	["!UI-HUD-ActionBar-Frame-Divider-ThreeSlice-EdgeLeft"] = { kind = "fade" },
	["!UI-HUD-ActionBar-Frame-Divider-ThreeSlice-EdgeRight"] = { kind = "fade" },

	-- The backpack and bag windows (BackpackPanel, 2026-09-21): the flat portrait window shell + R1 item rims
	["uiframebackground-nineslice-cornerbottomleft"] = { kind = "fade" },   -- PortraitFrameFlatTemplate's Bg pieces: faded, the page stone stands in (SkinWindowShell bg)
	["BagSlotBackground"]                     = { kind = "fade" },   -- the combined bags' slot-cell picture (UI-Bag-Components, keyed by hand): faded, the rims and stone stand in
	["UI-Bag-1Slot"]                          = { kind = "fade" },   -- a one-slot bag's picture
	["UI-Quickslot2"]                         = { kind = "slot", slot = "slot", gemSpan = { 97 / 135, 92 / 130 }, layer = "ARTWORK", sublevel = 2 },   -- a bag slot's NormalTexture (the classic quickslot rim): R1 as the action buttons
	["bags-button-autosort-up"]               = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND", fit = "width" },   -- the sort button: K2, the cog plate UNDER the game's round button (its glyph is its plate: not faded)
	["common-coinbox-center"]                 = { kind = "strip", base = "lists/header" },   -- the money strip (Left / Middle / Right, keyed on the middle): B2 (user, 2026-09-21), the header plate on its rect, the coins on it

	-- The minimap cluster (MinimapPanel; user's picks R1 Z2 from kit_raw/minimap_catalog.png, 2026-09-21)
	["UI-HUD-Minimap-Frame"]                  = { kind = "texture", piece = "window/portrait_ring", opening = true, openingScale = 0.75 },   -- R1 at 0.75 (user, 2026-09-21): the round frame (MinimapCompassTexture, also its -Pointer / -Circle rotated variants) → the portrait ring sized from the 198 px map's opening x 0.75, its rim over the map's edge, on a holder one level above the map; the band and buttons raised above it
	["UI-HUD-Minimap-Frame-Circle"]           = { kind = "fade" },   -- the rotated mode's underlay
	["MinimapZoneBand"]                       = { kind = "strip", base = "tabs/top", state = "title", owner = true, heightScale = 1.4, widthScale = 1.4 },   -- Z2: the zone band (BorderTop, a nine-slice of textures keyed by hand) → the title plate as regions of the band, 1.4 x the band's height and width (user, 2026-09-21), standing on the ring's top rim as a window title on its rail; the zone text centred on it
	["ui-hud-minimap-button"]                 = { kind = "texture", piece = "buttons/roundslot_normal", square = true, owner = true },   -- the tracking button's round plate: the round rim under the game's glyph
	["ui-hud-minimap-zoom-in"]                = { kind = "state", base = "buttons/plus", natural = true },   -- the zoom buttons: the kit's plus / minus
	["ui-hud-minimap-zoom-out"]               = { kind = "state", base = "buttons/minus", natural = true },

	-- The objective tracker (TrackerPanel; user's pick T2 from the same catalogue)
	["ui-questtracker-primary-objective-header"] = { kind = "strip", base = "tabs/top", state = "title", owner = true },   -- T2: the tracker's header band → the title plate
	["UI-QuestTracker-Secondary-Objective-Header"] = { kind = "strip", base = "lists/header", owner = true },   -- a module's header band → the header plate
	["ui-questtrackerbutton-collapse-all"]    = { kind = "state", base = "buttons/minus", natural = true },   -- the collapse / expand glyphs, switched with the atlas the game puts there
	["ui-questtrackerbutton-expand-all"]      = { kind = "state", base = "buttons/plus", natural = true },
	["ui-questtrackerbutton-secondary-collapse"] = { kind = "state", base = "buttons/minus", natural = true },
	["ui-questtrackerbutton-secondary-expand"] = { kind = "state", base = "buttons/plus", natural = true },
	["ui-questtrackerbutton-filter"]          = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the filter button: the cog plate under the game's glyph
	["ObjectiveTrackerBackground"]            = { kind = "frame" },   -- Edit Mode's tracker backdrop (a NineSlicePanelTemplate child): L1, the single rail with stone, its child (follows the opacity); TrackerPanel lays the parchment sheet with the painted edge on its stone
	["UI-Character-Skills-BarBorder"]         = { kind = "bar", bar = "frame" },   -- a tracker progress bar's border pieces (file art, keyed by hand): P1

	-- MelloUI's own configurator (Core/Config.lua, 2026-09-21; user's picks CT2 SI1 from kit_raw/config_catalog.png): its
	-- sliders are MinimalSliderWithSteppersTemplate; everything else goes through the fixed looks' existing keys
	["_Minimal_SliderBar_Middle"]             = { kind = "strip", base = "inputs/slider", owner = true },   -- a minimal slider's track (Left / Middle / Right, keyed on the middle): the kit slider's track as the slider's regions
	["Minimal_SliderBar_Button"]              = { kind = "state", base = "inputs/slider_thumb", natural = true },   -- its thumb: the gem thumb
	["Minimal_SliderBar_Button_Left"]         = { kind = "state", base = "buttons/arrow_left", natural = true },   -- its steppers: the kit arrows
	["Minimal_SliderBar_Button_Right"]        = { kind = "state", base = "buttons/arrow_right", natural = true },

	-- Tooltips (TooltipPanel, 2026-09-21; user's pick TT1 from kit_raw/tooltip_catalog.png)
	["Tooltip-NineSlice-CornerTopLeft"]       = { kind = "frame", owner = true, bodyLayer = "BACKGROUND", edgeLayer = "BORDER" },   -- TT1: a tooltip's NineSlice (the TooltipDefaultLayout pieces, keyed on the top-left corner; the other eight faded) -> the single rail with the list-box stone as REGIONS of the NineSlice in its own layers (under the tooltip's texts as the game's pieces are)
	["TooltipStatusBar"]                      = { kind = "bar", bar = "frame", capOut = true },   -- the unit tooltip's health bar (a StatusBar with no border art; an agreed addition, as the catalogue showed it): P1 with the caps outside, the bar set in by the arms
	-- Nameplates (NameplatePanel, 2026-09-21; user's picks NP1 = P1, NC2 from kit_raw/nameplate_catalog.png)
	["NamePlateHealthBarBG"]                  = { kind = "bar", bar = "frame", capOut = true, borderGroup = "nameplate" },   -- NP1: the health bar's backing (UI-HUD-CoolDownManager-Bar-BG, keyed by hand) -> P1 as the bar's regions above the fill, the caps outside, the bar set in by the arms after the game's UpdateAnchors; the trough under the fill
	["NamePlateCastBarBackground"]            = { kind = "frame", scale = 0.8, owner = true, bodyLayer = "BACKGROUND", edgeLayer = "ARTWORK", edgeSub = 1, outset = 2 },   -- outset 2: the single rail's 2 px outer pad, so the painted line's outer edge is ON the bar's edge and the fill (which reaches that edge, a StatusBar's fill cannot be set in) ends under the line (user, 2026-09-22: "spilling on the bottom")   -- NC2: the cast bar's background (ui-castingbar-background on a nameplate, keyed by hand; its Border faded) -> the single rail at 0.8 with the stone body as the bar's regions: the stone under the ARTWORK fill, the rails one sublevel above it, under the OVERLAY text
	["UI-HUD-Nameplates-Selected"]            = { kind = "fade" },   -- the target / focus outline around the health bar: faded; the bracket's iron shines gold while the game shows it (NameplatePanel)
	["ui-hud-nameplates-levelindicator"]      = { kind = "texture", piece = "buttons/orb_normal", square = true, owner = true },
	["ui-hud-nameplates-levelindicator-selected"] = { kind = "fade" },   -- the target ring around the level circle: faded (the bar's gold iron is the highlight)   -- the level indicator's circle: the orb, as the unit frames' level circle (the -selected ring and the skull stay the game's)

	-- The chat windows (ChatPanel, 2026-09-21; user's picks CH1 CT2 from kit_raw/chat_catalog.png)
	["ChatFrameBorder"]                       = { kind = "frame", body = false, owner = true, edgeLayer = "BORDER", outset = 8 },   -- CH1: a FloatingBorderedFrame's eight border pieces (UI-ChatFrame-BorderCorner / -BorderTop / -BorderLeft file art, keyed by hand on the top-left corner) -> the single rail as regions of the chat frame in the pieces' BORDER layer, centred on the Background's edge (the pieces reach 4 px past it); the Background stays the game's, the rail's alpha follows it
	["ChatFrameBody"]                         = { kind = "tile", piece = "window/single_body", owner = true },   -- the window's Background (ChatFrameBackground file art, the translucent black at the alpha slider; keyed by hand): the list-box stone as a region in its place, at the slider's alpha (user, 2026-09-21: the dark cracked stone, not a flat colour)
	["ChatIconButton"]                        = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the menu / channel / voice / minimize / maximize icon buttons (UI-ChatIcon-* file art, keyed by hand): K2, the cog plate under the game's glyph
	["chatframe-button-up"]                   = { kind = "state", base = "buttons/cog" },   -- the channel / voice buttons' own round plate (27 x 26, the glyph on their Icon): K2, the cog plate on its rect
	["minimal-scrollbar-arrow-returntobottom"] = { kind = "state", base = "buttons/arrow_down" },   -- scroll-to-bottom: the kit's down arrow on the button's rect (its new-messages flash stays, an FX)
	-- the chat tabs (ChatTabTemplate Left / ActiveLeft, keyed by hand) reuse the TB6 tab rules `uiframe-tab-left` / `uiframe-activetab-left`; the edit box reuses `UI-ChatInputBorder-Mid2`

	-- The damage meter (DamageMeterPanel, 2026-09-21; user's pick D1 = P1 from kit_raw/dpsmeter_catalog.png)
	["ui-damagemeters-bar-shadowbg"]          = { kind = "bar", bar = "frame", capOut = true },   -- an entry's shadow band under its status bar (+ BackgroundEdge, faded): P1, the bracket as the bar's regions above the fill, the trough under it; the caps OUTSIDE the bar's rect (a StatusBar's fill cannot be re-anchored, so the bar is set in by the arms and the fill ends under the gems — user, 2026-09-21: the fill overflowed the caps)
	["ui-damagemeters-header-bar"]            = { kind = "strip", base = "lists/header", owner = true },   -- a session window's header band: the header plate as its regions, the game's timer / dropdowns / buttons on it
	["damagemeters-background"]               = { kind = "frame" },   -- a session window's body (MinimizeContainer.Background, alpha = the transparency setting): L1 as the container's child at its level, its alpha following the setting
	["DamageMeterSourceBackground"]           = { kind = "frame" },   -- the source / spell breakdown window's Background (common-dropdown-bg, keyed by hand): L1 the same
	["DamageMeterSettingsIcon"]               = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the settings dropdown button's glyph (an Icon set in Lua, keyed by hand): K2, the kit's cog in the glyph's place (the glyph faded since 2026-09-23: laid under it, the two gears read as one stacked on the other)

	-- The social window (SocialPanel, 2026-09-21): fixed looks; the raid pane's group box per the user's G pick
	["FriendsRowHighlight"]                   = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a friend / ignore / raid-info row's highlight (UI-QuestLogTitleHighlight file art, keyed by hand): the plate's hover look, shown on hover only
	["FriendsPendingHeader"]                  = { kind = "strip", base = "lists/catplate", state = "closed", owner = true },   -- a pending-invite header (UI-Background-Rock BG + arrows, keyed by hand): the category plate, the game's arrows on it
	["UI-FriendsFrame-OnlineDivider"]         = { kind = "strip", base = "window/divider" },   -- the online / offline divider line
	["battlenet-friends-main"]                = { kind = "strip", base = "lists/header", owner = true },   -- the Battle.net tag band under the tabs: the header plate
	["friendslist-invitebutton-default-normal"] = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the invite icon button: K2, the cog plate under the game's glyph
	["UI-RaidFrame-GroupOutline"]             = { kind = "frame", scale = 0.8 },   -- a raid group box's outline (162 x 80 file picture): G3 (user, 2026-09-21), the single rail at the raid frames' small weight with the stone body
	["UI-RaidInfo-Header"]                    = { kind = "fade" },   -- the raid info popup's header / footer bands: faded (the dialog's own border stands)

	-- The HUD's cast bars (CastBarPanel; user's picks C1 T1 from kit_raw/castbar_catalog.png, 2026-09-21)
	["ui-castingbar-frame"]                   = { kind = "bar", bar = "castbar", capOut = true },   -- C1: the cast bar bracket (gem-cluster caps) with the game's bar as its opening: the caps stand outside the bar, which the panel narrows by their arms so the whole reads the game's width
	["ui-castingbar-background"]              = { kind = "fade" },   -- the trough art: the bracket's trough stands in
	["ui-castingbar-textbox"]                 = { kind = "strip", base = "lists/header", owner = true },   -- T1: the header plate on the 12 px under the bar (the box's lower part), the spell name on it
	["ui-castingbar-full-glow-standard"]      = { kind = "fade" },   -- the completion flash
	["castbar_shadow_embedded"]               = { kind = "fade" },   -- the overlay look's drop shadow
	["CastBarFX"]                             = { kind = "fade" },   -- the glows, flakes, wisps, sparkles and shine (keyed by hand: their animations drive alpha, the panel stops those)
	["UnitFrameNameBand"]                     = { kind = "strip", base = "tabs/top", state = "title", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- N3: the title plate on the name band's rect (the target's strip; the player's the same rect mirrored), a region in the faded picture's layer so the ring draws over its end
}

--------------------------------------------------------------------------------
-- Covers: which HUD groups a kit module currently dresses (user rule,
-- 2026-09-21: Dark Mode and the Chat module's art hiding act on a group ONLY
-- while no kit module covers it). A kit module calls Kit:Cover(group) in
-- OnEnable and Kit:Uncover(group) in OnDisable; the tweak modules ask
-- Kit:IsCovered(group) before every sweep and re-run it from Kit:OnCover.
-- Groups: unitframes, castbar, partyframes, raidframes, actionbars, micromenu,
-- bagbar, statusbars, backpack, minimap, tracker, social, chat, damagemeter.
--------------------------------------------------------------------------------
Kit.covers = {}

-- Every window dressed by Kit:SkinWindowShell: [frame] = { outer = rep,
-- title = rep }, and the watchers told of each new one (the window mover
-- in UI Modifications hangs its drag handle on the title plate).
Kit.shells = {}
Kit.shellWatchers = {}

function Kit:OnShell(fn)
	self.shellWatchers[#self.shellWatchers + 1] = fn
	for frame, shell in pairs(self.shells) do
		fn(frame, shell)
	end
end

local RegisterShell

-- A panel registers a window (or a HUD element: the minimap cluster, the
-- tracker, the damage meter, a chat frame) with its drag handle — a title /
-- header plate's rep, or a plain frame — and the outer frame rep whose iron
-- lights while it moves (user, 2026-09-21: the HUD's elements too).
function Kit:RegisterShell(frame, shell)
	RegisterShell(frame, shell)
end

RegisterShell = function(frame, shell)
	local known = Kit.shells[frame] or {}
	known.outer = shell.outer or known.outer
	known.title = shell.title or known.title
	known.ring = shell.ring or known.ring
	Kit.shells[frame] = known
	-- the title plate rides the outer rail: its caps' gems take the corners,
	-- and it runs behind the portrait ring
	local onRail = known.title and known.title.rule and known.title.rule.onRail
	local skin = known.outer and known.outer.skin
	if onRail and skin and skin.SetTopGems then
		skin:SetTopGems(false)
	end
	if onRail and known.ring then
		Kit:TitleBehindRing(known.title, known.ring, known.outer)
	end
	for _, fn in ipairs(Kit.shellWatchers) do
		fn(frame, known)
	end
end
Kit.coverWatchers = {}

function Kit:IsCovered(group)
	return self.covers[group] == true
end

local function NotifyCover(group, covered)
	for _, fn in ipairs(Kit.coverWatchers) do
		fn(group, covered)
	end
end

function Kit:Cover(group)
	if not self.covers[group] then
		self.covers[group] = true
		NotifyCover(group, true)
	end
end

function Kit:Uncover(group)
	if self.covers[group] then
		self.covers[group] = nil
		NotifyCover(group, false)
	end
end

function Kit:OnCover(fn)
	self.coverWatchers[#self.coverWatchers + 1] = fn
end

--------------------------------------------------------------------------------
-- Combat: geometry on a protected frame's children is refused while the
-- player is in combat; the HUD modules queue it here and it runs at
-- PLAYER_REGEN_ENABLED (at once when out of combat). A refit hook on the
-- game's own layout method goes through the same queue.
--------------------------------------------------------------------------------
local combatQueue = {}
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
	local queue = combatQueue
	combatQueue = {}
	for _, fn in ipairs(queue) do
		fn()
	end
end)

function Kit:WhenOutOfCombat(fn)
	if InCombatLockdown() then
		combatQueue[#combatQueue + 1] = fn
	else
		fn()
	end
end

-- An action-style button (ActionButtonTemplate and its small kin: action,
-- stance, pet, possess and bag slot buttons): the R1 rim on its NormalTexture
-- sized to the bar's pitch { x, y } so neighbours share a gem, the icon fitted
-- into the rim's opening (its rounded mask taken off while the rim is on),
-- the empty-slot backing on stone, the pushed / highlight / checked textures
-- faded (the rim carries the states), the equipped border faded and the rim
-- tinted green while the game shows it. `replace` is the panel's Replace.
-- Returns the rim rep; rep:SetPitch(x, y) re-sizes it after a re-layout.
function Kit:SkinActionButton(button, replace, pitch, opts)
	opts = opts or {}
	-- the rim texture: the template's key, else the widget's own (a bag
	-- button has no NormalTexture key; one is never written onto it -- the
	-- game reads that key, 2026-09-23 audit)
	local normal = button and (button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture()))
	if not (button and normal and button.icon) or button.melloRep ~= nil then
		return button and button.melloRep or nil
	end
	local extra = { button.PushedTexture, button.HighlightTexture, button.CheckedTexture }
	if button.GetPushedTexture then
		extra[#extra + 1] = button:GetPushedTexture()
	end
	if button.GetHighlightTexture then
		extra[#extra + 1] = button:GetHighlightTexture()
	end
	if button.GetCheckedTexture then
		extra[#extra + 1] = button:GetCheckedTexture()
	end
	-- opts.as: another slot rule (the action bars' thin rim, "ActionButtonRim")
	local rep = replace(normal, { as = opts.as or "UI-HUD-ActionBar-IconFrame", button = button, rect = button, pitch = pitch,
		icon = button.icon, alsoFade = extra })
	button.melloRep = rep or false
	if not rep then
		return nil
	end
	-- a thin rim follows the one Button Border of every window
	for _, rule in pairs(self.buttonLooks.rimRule) do
		if opts.as == rule then
			self:RegisterButtonRim(button)
			break
		end
	end
	-- the icon's rounded mask off while the rim is on (its square opening)
	local mask = button.IconMask or button.SquareMask
	local icon = button.icon
	local onEnable, onDisable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if onEnable then
			onEnable(...)
		end
		if mask and icon.RemoveMaskTexture then
			pcall(icon.RemoveMaskTexture, icon, mask)
		end
	end
	rep.onDisable = function(...)
		if onDisable then
			onDisable(...)
		end
		if mask and icon.AddMaskTexture then
			pcall(icon.AddMaskTexture, icon, mask)
		end
	end
	-- the empty slot's backing: stone in the rim's opening; its ornament faded
	-- (a bag slot has no backing region: `opts.emptyStone` puts the stone
	-- on the button itself, replacing its NormalTexture's empty look)
	if button.SlotBackground or opts.emptyStone then
		local rim = rep.object
		local opening = CreateFrame("Frame", nil, button)
		opening:EnableMouse(false)
		local function Fit()
			local name = (rim.base or "buttons/slot") .. "_normal"   -- the opening of the rim it is in (its art can change live)
			local piece = PIECES[name]
			local l, r, t, b = Kit:Insets(name, 1)
			local okS, rw, rh = pcall(rim.GetSize, rim)
			if piece and l and okS and rw and rh and not Secret(rw) and rw > 0 then
				opening:ClearAllPoints()
				opening:SetPoint("TOPLEFT", rim, "TOPLEFT", rw * l / piece.w, -rh * t / piece.h)
				opening:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -rw * r / piece.w, rh * b / piece.h)
			else
				opening:SetAllPoints(button)
			end
		end
		Fit()
		rim.onBaseChanged = Fit
		local stone = replace(button.SlotBackground or normal, { as = "UI-HUD-ActionBar-IconFrame-Background", rect = opening,
			noFade = not button.SlotBackground })
		button.melloSlotStone = stone or nil   -- its texture (stone.tex) can be swapped: Action Bars Kit's Button Background
		if stone then
			-- the stone shows while the slot is EMPTY: the game hides the icon
			-- then (its own backing shows only on a bar whose art is hidden —
			-- on the main bar the faded frame art was the empty slot's look).
			-- An ITEM button (a bag window's slot, a bag bar slot) keeps its
			-- icon shown when empty, painted with its empty-slot picture
			-- (`emptyBackgroundAtlas` / `emptyBackgroundTexture`, put there by
			-- SetItemButtonTexture(nil)): the Item Background never showed
			-- (user, 2026-09-23). Its emptiness is read from that call; while
			-- empty the icon (the game's picture) is see-through.
			local itemButton = (button.emptyBackgroundAtlas or button.emptyBackgroundTexture) and button.SetItemButtonTexture
			local function IsEmpty()
				if not icon:IsShown() then
					return true
				end
				if not itemButton then
					return false
				end
				if button.melloEmpty ~= nil then
					return button.melloEmpty
				end
				local ok, atlas = pcall(function() return icon.GetAtlas and icon:GetAtlas() end)
				return ok and atlas ~= nil and atlas == button.emptyBackgroundAtlas
			end
			local function Sync()
				if rep.object:IsShown() then
					local empty = IsEmpty()
					stone:SetShown(empty)
					if itemButton then
						icon:SetAlpha(empty and 0 or 1)
					end
				end
			end
			if itemButton then
				hooksecurefunc(button, "SetItemButtonTexture", function(_, texture)
					button.melloEmpty = texture == nil
					Sync()
				end)
				local disable = rep.onDisable
				rep.onDisable = function(...)
					if disable then
						disable(...)
					end
					icon:SetAlpha(1)
				end
			end
			hooksecurefunc(icon, "Show", Sync)
			hooksecurefunc(icon, "Hide", Sync)
			hooksecurefunc(icon, "SetShown", Sync)
			local enable = stone.Enable
			stone.Enable = function(self)
				enable(self)
				Sync()
			end
			Sync()
		end
		local setPitch = rep.SetPitch
		rep.SetPitch = function(self, px, py)
			if setPitch then
				setPitch(self, px, py)
			end
			Fit()
		end
	end
	if button.SlotArt then
		replace(button.SlotArt, { as = "ui-hud-actionbar-iconframe-slot" })
	end
	-- a quality border (a bag slot's WhiteIconFrame, tinted by the game): the
	-- game's, kept over the icon — anchored to the icon so it follows the
	-- icon into the rim's opening (user, 2026-09-21: the rim itself is not
	-- recoloured by the quality); the game's anchors put back on disable
	local quality = opts.qualityBorder
	if quality then
		local saved = {}
		for i = 1, quality:GetNumPoints() do
			saved[i] = { quality:GetPoint(i) }
		end
		local enable2, disable2 = rep.onEnable, rep.onDisable
		rep.onEnable = function(...)
			if enable2 then
				enable2(...)
			end
			quality:ClearAllPoints()
			quality:SetAllPoints(icon)
		end
		rep.onDisable = function(...)
			if disable2 then
				disable2(...)
			end
			quality:ClearAllPoints()
			for _, pt in ipairs(saved) do
				quality:SetPoint(unpack(pt))
			end
		end
	end
	-- the equipped border: faded, the rim green while the game shows it
	if button.Border then
		replace(button.Border, { as = "UI-HUD-ActionBar-IconFrame-Border" })
		local border, rim = button.Border, rep.object
		local function Tint()
			if rep.object:IsShown() then
				if border:IsShown() then
					rim:SetVertexColor(0.5, 1, 0.5)
				else
					rim:SetVertexColor(1, 1, 1)
				end
			end
		end
		hooksecurefunc(border, "Show", Tint)
		hooksecurefunc(border, "Hide", Tint)
		hooksecurefunc(border, "SetShown", Tint)
		Tint()
	end
	-- a button skinned while the panel is already on was enabled by `replace`
	-- before the hooks above existed: run them now
	if rep.object:IsShown() and rep.onEnable then
		rep.onEnable(rep)
	end
	return rep
end

--------------------------------------------------------------------------------
-- The looks a button can take, shared by every panel that offers them (the
-- action bars, micro menu and bag bar in Action Bars Kit, the bag windows'
-- slots in Backpack Kit) and by the Dynamic UI picker's previews.
--   borders:      Button Border (a dropdown's values; `piece` the preview)
--   backgrounds:  Button / Backdrop Background ("dark" a flat fill, "none" nothing)
--   rimRule / rimKind: a border's slot rule and its rim piece family
--------------------------------------------------------------------------------

Kit.buttonLooks = {
	borders = {
		{ value = "thin", label = "Thin iron", piece = "buttons/rim_normal" },
		{ value = "hairline", label = "Hairline", piece = "buttons/rimhair_normal" },
		{ value = "rounded", label = "Rounded corners", piece = "buttons/rimround_normal" },
		{ value = "gold", label = "Iron with gold line", piece = "buttons/rimgold_normal" },
		{ value = "sunk", label = "Sunk", piece = "buttons/rimsunk_normal" },
	},
	backgrounds = {
		{ value = "stone", label = "Stone", piece = "tiles/stone" },
		{ value = "concrete", label = "Cracked concrete", piece = "tiles/concrete" },
		{ value = "ironplate", label = "Iron plate", piece = "tiles/ironplate" },
		{ value = "parchment", label = "Parchment", piece = "tiles/parchment" },
		{ value = "leather", label = "Leather", piece = "tiles/quilt_brown" },
		{ value = "dark", label = "Dark" },
		{ value = "none", label = "None" },
	},
	-- a progress bar's bracket (a bar replacement's `bar`): the ornate P1,
	-- the cast bar's, or the thin rims made into bars (Tools/build_kit.py
	-- thin_bar); `piece` the preview's middle
	barBorders = {
		{ value = "frame", label = "Ornate", bar = "frame" },
		{ value = "castbar", label = "Cast bar", bar = "castbar" },
		{ value = "rim", label = "Thin iron", bar = "rim" },
		{ value = "rimhair", label = "Hairline", bar = "rimhair" },
		{ value = "rimround", label = "Rounded", bar = "rimround" },
		{ value = "rimgold", label = "Iron with gold line", bar = "rimgold" },
		{ value = "rimsunk", label = "Sunk", bar = "rimsunk" },
	},
	rimRule = { thin = "ActionButtonRim", hairline = "ActionButtonRimHairline", rounded = "ActionButtonRimRounded",
		gold = "ActionButtonRimGold", sunk = "ActionButtonRimSunk" },
	rimKind = { thin = "rim", hairline = "rimhair", rounded = "rimround", gold = "rimgold", sunk = "rimsunk" },
	borderDesc = "The rim on each button: a thin iron rim, a hairline, rounded corners, iron with a gold line round the icon, "
		.. "or sunk (a soft shadow inside the rim). Each lights up under the mouse and turns gold when checked.",
}
Kit.buttonLooks.backgroundPiece = {}
for _, v in ipairs(Kit.buttonLooks.backgrounds) do
	Kit.buttonLooks.backgroundPiece[v.value] = v.piece
end

-- A Button Border's slot rule (for Kit:SkinActionButton's `as`); without a
-- style, the one every window's buttons wear (UI Modifications' Button Border)
function Kit:ButtonRimRule(style)
	local looks = self.buttonLooks
	style = style or (self.BorderValue and self:BorderValue("button"))
	return looks.rimRule[style] or looks.rimRule.thin
end

-- A new Button Border on a skinned button (its rim's art swapped live)
function Kit:SetButtonBorder(button, style)
	local kind = self.buttonLooks.rimKind[style]
	local rep = button and button.melloRep
	if kind and rep and rep.object and rep.object.base then
		self:SetSlotBase(rep.object, "buttons/" .. kind)
	end
end

-- A button's background: the texture in its opening where it shows no icon
-- (an action / bag / item slot's empty backing, melloSlotStone; a micro
-- button's stone under its glyph, melloStone)
function Kit:SetButtonBackground(button, value)
	local tex = button and ((button.melloSlotStone and button.melloSlotStone.tex) or button.melloStone)
	if not tex then
		return
	end
	local piece = self.buttonLooks.backgroundPiece[value]
	if piece then
		if tex.kitName ~= piece then
			self:Apply(tex, piece)
		end
		self:Retile(tex)
		tex:SetAlpha(1)
	elseif value == "dark" then
		tex:SetColorTexture(0.05, 0.045, 0.04, 0.88)
		-- still ours: a plain mark, no piece (as the solid kind's fill)
		tex.kitPiece, tex.kitName = true, nil
		tex:SetAlpha(1)
	else
		tex:SetAlpha(0)   -- none: the game shows it with the empty slot; it stays see-through
	end
end

-- The layer above a status bar's fill for its bracket, and the one below it
-- for the trough (a unit frame's health fill draws at BACKGROUND, its power
-- bar and a cast bar at ARTWORK — no drawLayer in their XML — their texts at
-- OVERLAY 1). Secret-safe.
-- `strict`: nil when the fill's layer cannot be read (a secret string on the
-- target side's bars), for a caller that would rather leave things as they
-- are than guess (the relayer).
function Kit:BracketLayers(bar, strict)
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local ok, layer = pcall(function() return tex and tex:GetDrawLayer() end)
	if not ok or type(layer) ~= "string" or Secret(layer) then
		if strict then
			return nil
		end
		layer = "BACKGROUND"
	end
	if layer == "ARTWORK" then
		return "OVERLAY", 0, "BORDER", 0
	elseif layer == "BORDER" then
		return "ARTWORK", 1, "BACKGROUND", 7
	elseif layer == "OVERLAY" then
		return "OVERLAY", 7, "ARTWORK", 7
	end
	return "BORDER", 1, "BACKGROUND", -1
end

-- Alpha 0 that survives the game's own SetAlpha / Show calls (shared by the
-- panel modules so one registry knows what is faded).
Kit.faded = {}

function Kit:Fade(obj)
	if not obj or self.faded[obj] then
		return
	end
	self.faded[obj] = true
	obj:SetAlpha(0)
	if not obj.kitFadeHook then
		obj.kitFadeHook = true
		local faded = self.faded
		hooksecurefunc(obj, "SetAlpha", function(o, a)
			if faded[o] and a ~= 0 then
				o:SetAlpha(0)
			end
		end)
		-- a vertex colour with an alpha (UnitSelectionColor's fourth value on
		-- a reaction band) resets the region's alpha on this client
		if obj.SetVertexColor then
			hooksecurefunc(obj, "SetVertexColor", function(o)
				if faded[o] then
					o:SetAlpha(0)
				end
			end)
		end
	end
end

function Kit:Unfade(obj)
	if obj and self.faded[obj] then
		self.faded[obj] = nil
		obj:SetAlpha(1)
	end
end

-- The name the library keys on: the region's atlas, else its texture file's
-- base name. Secret values (this client) read as unknown.
function Kit:ArtKey(region)
	if not region or not region.GetAtlas then
		return nil
	end
	local ok, atlas = pcall(region.GetAtlas, region)
	if ok and atlas and not (issecretvalue and issecretvalue(atlas)) and atlas ~= "" then
		return atlas
	end
	local okT, tex = pcall(region.GetTexture, region)
	if okT and tex and not (issecretvalue and issecretvalue(tex)) and type(tex) == "string" then
		return tex:match("([^\\/]+)$")
	end
	return nil
end

local ReplacementMixin = {}

-- Fade the game art, show ours.
function ReplacementMixin:Enable()
	if not self.noFade then
		Kit:Fade(self.region)
	end
	for _, extra in ipairs(self.alsoFade) do
		Kit:Fade(extra)
	end
	self.object:Show()
	if self.backing then
		self.backing:Show()
	end
	self:Refit()
	if self.checked then
		self:SetState()
	end
	if self.onEnable then
		self.onEnable(self)
	end
end

-- Show the game art again, hide ours.
function ReplacementMixin:Disable()
	if not self.noFade then
		Kit:Unfade(self.region)
	end
	for _, extra in ipairs(self.alsoFade) do
		Kit:Unfade(extra)
	end
	self.object:Hide()
	if self.backing then
		self.backing:Hide()
	end
	if self.object.glow then
		self.object.glow:Hide()
	end
	if self.onDisable then
		self.onDisable(self)
	end
end

-- The rect's height / width, or nil when unreadable (secret). With the editing
-- tools' proxy in front of the element, measured from the ELEMENT plus the
-- proxy's padding: a proxy made this frame reads 0 x 0 until the next layout
-- pass, so a bar bracket and the fill fitted into its opening were sized from
-- two different heights and the fill spilled past the rails (user, 2026-09-23:
-- the skill / reputation bars, only while the editor addon was installed).
function ReplacementMixin:RectSize(method)
	local target, pad = self.rect, 0
	if self.proxy and self.proxyOf then
		target = self.proxyOf
		local tune = self.tune
		if tune then
			if method == "GetHeight" then
				pad = (tune.padT or 0) + (tune.padB or 0)
			else
				pad = (tune.padL or 0) + (tune.padR or 0)
			end
		end
	end
	local ok, v = pcall(target[method], target)
	if not ok or Secret(v) or v == nil then
		return nil
	end
	return v + pad
end

-- Re-fit to the rectangle (rows get their height after layout), or to the
-- fit height when one is set: the strip spans the rect's width and its
-- opaque part is exactly that tall, centred on the rect's centre line.
function ReplacementMixin:Refit()
	if not (self.strip and self.rect) then
		return
	end
	if self.rule.natural then
		-- the kit size, centred on the rect, spanning widthFrac of its width
		local mid = PIECES[StripName(self.strip.base, "mid", self.strip.state)]
		local boxH = mid and mid.box and (mid.box[4] - mid.box[2]) or (mid and mid.h) or 0
		local yoff = self.strip:FitBox(boxH * Kit.scale)
		local w = (self:RectSize("GetWidth") or 0) * (self.rule.widthFrac or 1)
		self.strip:ClearAllPoints()
		self.strip:SetPoint("CENTER", self.rect, "CENTER", 0, yoff)
		self.strip:SetSize(math.max(w, 1), self.strip.height)
		return
	end
	local h = self.fitHeight
	if not (h and h > 0) then
		h = self:RectSize("GetHeight")
		if not h then
			return
		end
	end
	if not (h and h > 0) then
		return
	end
	h = h * (self.rule.heightScale or 1)
	local yoff = self.strip:FitBox(h)
	self.strip:ClearAllPoints()
	-- `capOverhang`: the caps may reach that fraction of their width past
	-- the rect's edges (a gemmed button plate on a short button: the gems
	-- stand outside, as the game's own Left / Right button pieces do)
	local over = 0
	if self.rule.capOverhang then
		over = (self.strip.wl or 0) * self.rule.capOverhang
	end
	-- `widthScale`: the plate wider than its rect by that factor, centred
	-- (the minimap's zone band at 1.4 — user, 2026-09-21)
	if self.rule.widthScale then
		local w0 = self:RectSize("GetWidth")
		if w0 and w0 > 0 then
			over = over + w0 * (self.rule.widthScale - 1) / 2
		end
	end
	local overL = self.strip.dropCap == "l" and 0 or over
	local overR = self.strip.dropCap == "r" and 0 or over
	self.strip:SetPoint("LEFT", self.rect, "LEFT", -overL, yoff)
	self.strip:SetPoint("RIGHT", self.rect, "RIGHT", overR, yoff)
	self.strip:SetHeight(self.strip.height)
	local w = self:RectSize("GetWidth")
	if not (w and w > 0) then
		w = self.fitWidth or 0
	end
	self.strip:FitCaps(w + overL + overR)
end

function ReplacementMixin:SetFitHeight(h)
	if h and h > 0 and h ~= self.fitHeight then
		self.fitHeight = h
		self:Refit()
	end
end

function ReplacementMixin:SetState(state)
	if self.kind == "picture" then
		self:Refit()
	elseif self.vstrip then
		local b = self.button
		if not state and b then
			-- ButtonStateBehaviorMixin keeps `over` / `down` on the button
			state = Kit:ResolveState(self.vstrip.base .. "_mid", b.over, b.down, nil, b.IsEnabled and not b:IsEnabled())
		end
		self.vstrip:SetState(state or Kit:FirstState(self.vstrip.base, "mid"))
	elseif self.strip then
		self.strip:SetState(state)
	elseif self.skin and self.Update then
		self.Update()
	elseif self.skin and self.checked then
		local tint = self.rule.checkedTint
		if tint and self.checked() then
			self.skin:SetTint(tint[1], tint[2], tint[3])
		else
			self.skin:SetTint(1, 1, 1)
		end
	elseif self.object.Update then
		self.object:Update()
	end
end

function ReplacementMixin:SetShown(shown)
	self.object:SetShown(shown)
end

-- Replace one game region (or frame) with the kit piece the library maps it
-- to. opts:
--   as        rule key when the region's art can't be read (or is a frame)
--   parent    the frame to parent to (default: the region's own frame; pass
--             another when that frame is faded, since alpha inherits)
--   rect      the rectangle to cover (default: the region)
--   button    the button for slot / state kinds
--   pitch     { x, y } distance between neighbouring slots: a slot rim with a
--             gemSpan rule is sized so neighbours share a corner gem
--   fitHeight a strip's height, when it should be the distance between
--             neighbouring rows (the rows' pitch) rather than the art's rect;
--             rep:SetFitHeight(h) changes it later
--   checked   function() -> true for the checked / selected state
--   state     the strip's first state
--   center    for `square` / `natural` pieces: the region to centre on;
--             centerPoint the point of it (default "CENTER")
--   alsoFade  other regions the piece stands in for (a row's side pieces)
--   noFade    the piece stands in for nothing (an agreed addition): the
--             region is only the rect / parent, it is not faded
--   level     frame level relative to the parent (overrides the rule)
--   skip      frame kind: gem corners to leave out ("tl" under a portrait ring)
--   grey      picture kind: function() -> true while the greyscale twin shows
--   button    strip kind: the plate follows this button's hover / pressed / disabled
--   edit      strip kind: the plate shows its focused look while this edit box has focus
--   capless   strip kind: the middle alone, never the caps
--   dropCap   strip kind: one cap left out ("l" / "r"), the middle to that edge
--   icon      slot kind: the button's icon texture, fitted into the rim's opening
-- Returns the replacement, or nil and the key that had no rule.
-- The rule for an art key. The client hands atlas names back in their
-- canonical case ("UI-QuestTrackerButton-Collapse-All" for the XML's
-- "ui-questtrackerbutton-collapse-all"), so a miss is retried ignoring case
-- (an index built once from the table).
local LOWER_RULES = nil
local function BaseRule(key)
	local rule = Kit.Replacements[key]
	if rule then
		return rule
	end
	if not LOWER_RULES then
		LOWER_RULES = {}
		for k, v in pairs(Kit.Replacements) do
			LOWER_RULES[k:lower()] = v
		end
	end
	return LOWER_RULES[key:lower()]
end

-- The rule an element key is drawn by, with the editing tools' overrides
-- (Core\KitTuning.lua) merged on top. A tuned rule is built once per tuning
-- change and cached; an untuned key hands back the library's own table.
local tunedRules = { serial = -1 }

function Kit:RuleFor(key)
	if not key then
		return nil
	end
	local base = BaseRule(key)
	local KT = MelloUI.KitTuning
	if not KT then
		return base
	end
	if tunedRules.serial ~= KT.serial then
		tunedRules = { serial = KT.serial }
	end
	local cached = tunedRules[key]
	if cached ~= nil then
		return cached or base
	end
	local over = KT:Rule(key)
	if not over or not next(over) then
		tunedRules[key] = false
		return base
	end
	local merged = base and KT:Copy(base) or {}
	KT:Merge(merged, over)
	-- an override may INVENT a rule for an element the library never mapped,
	-- but it has to say what kind of piece to draw
	if not merged.kind then
		tunedRules[key] = false
		return base
	end
	merged.tuned = true
	tunedRules[key] = merged
	return merged
end

--------------------------------------------------------------------------------
-- Tuning (the editing tools' overrides; see Core\KitTuning.lua)
--
-- Nothing here runs unless a tuning table carries something: with an empty
-- one every function below is a no-op and the kit behaves as it always has.
--------------------------------------------------------------------------------

-- `liveEdit` is switched on by the companion editor addon while it is
-- installed: every replacement then gets a proxy rectangle the editor can
-- drag, instead of only those that already carry an offset.
Kit.liveEdit = false

local GONE = {}                 -- "this field did not exist before the override"
local pieceBackup = {}          -- [piece name] = { field = original value }

-- Globals and painted-piece geometry, applied to the kit itself. Called by
-- MelloUI.KitTuning whenever the tuning changes.
function Kit:ApplyTuning(KT)
	local g = KT:Globals()
	self.baseScale = self.baseScale or self.scale
	self.baseFrameScale = self.baseFrameScale or self.frameScale
	self.baseFramePrefix = self.baseFramePrefix or self.framePrefix
	self.scale = tonumber(g.scale) or self.baseScale
	self.frameScale = tonumber(g.frameScale) or self.baseFrameScale
	self.framePrefix = g.framePrefix or self.baseFramePrefix

	-- pieces that are not tuned any more go back to what build_kit.py wrote
	for name, backup in pairs(pieceBackup) do
		if not KT:Piece(name) then
			local p = PIECES[name]
			if p then
				for field, value in pairs(backup) do
					p[field] = value ~= GONE and value or nil
				end
			end
			pieceBackup[name] = nil
		end
	end
	for name, over in pairs(KT:Section("pieces")) do
		local p = PIECES[name]
		if not p then
			p = { file = name:gsub("/", "\\") }
			PIECES[name] = p
		end
		local backup = pieceBackup[name]
		if not backup then
			backup = {}
			pieceBackup[name] = backup
		end
		for field, value in pairs(over) do
			if backup[field] == nil then
				backup[field] = p[field] == nil and GONE or p[field]
			end
			p[field] = value ~= KT.NIL and value or nil
		end
	end

	LOWER_RULES = nil
	tunedRules = { serial = -1 }
	self:RefreshTuning()
end

-- Every painted texture inside a replacement, whatever kind it is.
function Kit:Textures(rep)
	local out, seen = {}, {}
	local function add(tex)
		if tex and not seen[tex] and tex.SetVertexColor then
			seen[tex] = true
			out[#out + 1] = tex
		end
	end
	add(rep.tex)
	if rep.skin then
		for _, tex in ipairs(rep.skin.art or {}) do
			add(tex)
		end
		add(rep.skin.body)
	end
	for _, strip in ipairs({ rep.strip, rep.vstrip }) do
		if strip then
			add(strip.capL)
			add(strip.mid)
			add(strip.capR)
		end
	end
	local obj = rep.object
	if obj and obj.GetRegions and obj.GetObjectType and obj:GetObjectType() ~= "Texture" then
		local ok, regions = pcall(function() return { obj:GetRegions() } end)
		if ok then
			for _, region in ipairs(regions) do
				if region.GetObjectType and region:GetObjectType() == "Texture" then
					add(region)
				end
			end
		end
	end
	return out
end

-- One texture's look. Only what `tune` actually names is touched; a field
-- that was tuned and is not any more goes back to what the piece (or the
-- module that tinted it) said, so clearing a box in the editor undoes it
-- without a reload and without flattening a module's own colours.
function Kit:TuneTexture(tex, tune)
	tune = tune or {}
	local had = tex.melloTuned or nil
	local now = nil
	local function mark(field)
		now = now or {}
		now[field] = true
	end
	local piece = tex.kitPiece

	if tune.texture then
		if tex.melloArt == nil then
			tex.melloArt = (tex.GetTexture and tex:GetTexture()) or false
		end
		pcall(tex.SetTexture, tex, tune.texture)
		mark("texture")
	elseif tex.melloArt ~= nil then
		if piece and tex.kitName then
			self:Apply(tex, tex.kitName)
		elseif tex.melloArt then
			pcall(tex.SetTexture, tex, tex.melloArt)
		end
		tex.melloArt = nil
	end

	local t = tune.tint
	if t then
		pcall(tex.SetVertexColor, tex, t[1] or 1, t[2] or 1, t[3] or 1, t[4])
		mark("tint")
	elseif had and had.tint then
		-- back to the tint whoever owns this texture last asked for
		local base = tex.kitBase
		pcall(tex.SetVertexColor, tex, base and base[1] or 1, base and base[2] or 1, base and base[3] or 1)
	end

	if tune.desat ~= nil then
		if tex.SetDesaturated then
			pcall(tex.SetDesaturated, tex, tune.desat and true or false)
		end
		mark("desat")
	elseif had and had.desat and tex.SetDesaturated then
		pcall(tex.SetDesaturated, tex, false)
	end

	if tune.blend then
		pcall(tex.SetBlendMode, tex, tune.blend)
		mark("blend")
	elseif had and had.blend then
		pcall(tex.SetBlendMode, tex, "BLEND")
	end

	if tune.layer then
		pcall(tex.SetDrawLayer, tex, tune.layer, tune.sublevel or 0)
		mark("layer")
	end

	if tune.texAlpha then
		pcall(tex.SetAlpha, tex, tune.texAlpha)
		mark("texAlpha")
	elseif had and had.texAlpha then
		pcall(tex.SetAlpha, tex, 1)
	end

	-- cropping and mirroring work on the piece's own uv window; a repeatable
	-- piece re-computes its uv from its size, so it is left alone
	if not (piece and piece.tile) then
		local cropping = tune.coord or tune.flipH or tune.flipV
		if cropping then
			local u1, u2, v1, v2 = 0, 1, 0, 1
			if piece and piece.uv then
				u1, u2, v1, v2 = piece.uv[1], piece.uv[2], piece.uv[3], piece.uv[4]
			end
			local c = tune.coord
			if c then
				local du, dv = u2 - u1, v2 - v1
				u1, u2 = u1 + du * (c[1] or 0), u1 + du * (c[2] or 1)
				v1, v2 = v1 + dv * (c[3] or 0), v1 + dv * (c[4] or 1)
			end
			if tune.flipH then
				u1, u2 = u2, u1
			end
			if tune.flipV then
				v1, v2 = v2, v1
			end
			pcall(tex.SetTexCoord, tex, u1, u2, v1, v2)
			mark("coord")
		elseif had and had.coord then
			if piece and piece.uv then
				pcall(tex.SetTexCoord, tex, piece.uv[1], piece.uv[2], piece.uv[3], piece.uv[4])
			else
				pcall(tex.SetTexCoord, tex, 0, 1, 0, 1)
			end
		end
	end

	tex.melloTuned = now
end

-- The whole replacement: its rectangle (through the proxy made in Replace),
-- its alpha and every texture in it.
function Kit:TuneObject(rep, tune)
	local obj = rep.object
	if not obj then
		return
	end
	rep.tune = tune
	if rep.proxy and rep.proxyOf then
		local x, y = tune and tune.x or 0, tune and tune.y or 0
		rep.proxy:ClearAllPoints()
		rep.proxy:SetPoint("TOPLEFT", rep.proxyOf, "TOPLEFT", x - (tune and tune.padL or 0), y + (tune and tune.padT or 0))
		rep.proxy:SetPoint("BOTTOMRIGHT", rep.proxyOf, "BOTTOMRIGHT", x + (tune and tune.padR or 0), y - (tune and tune.padB or 0))
	end
	if obj.SetAlpha then
		pcall(obj.SetAlpha, obj, (tune and tune.alpha) or 1)
	end
	for _, tex in ipairs(self:Textures(rep)) do
		self:TuneTexture(tex, tune)
	end
	if rep.Refit then
		pcall(rep.Refit, rep)
	end
end

-- Re-apply (or undo) the tuning of every replacement already on screen, so
-- the editor's handles and sliders move the art immediately. Structural
-- changes -- a different kind or a different painted piece -- still need
-- the panels rebuilt, which the editor asks for with a reload.
function Kit:RefreshTuning()
	local KT = MelloUI.KitTuning
	if not KT then
		return
	end
	for _, rep in ipairs(self.repList) do
		local tune = KT:Tune(rep.key)
		if tune or rep.tune then
			self:TuneObject(rep, tune)
		end
	end
end

-- Every replacement built this session, so the editor can list what is
-- actually on screen instead of guessing from the library.
Kit.repList = {}
Kit.repByKey = {}

function Kit:RegisterReplacement(rep)
	if not rep or rep.registered then
		return
	end
	rep.registered = true
	self.repList[#self.repList + 1] = rep
	local key = rep.key
	if key then
		local list = self.repByKey[key]
		if not list then
			list = {}
			self.repByKey[key] = list
		end
		list[#list + 1] = rep
	end
end

-- How the editor names one region of a frame: its global name, the key it
-- sits under in the frame table, or the art it shows.
function Kit:RegionKey(frame, region)
	local ok, name = pcall(region.GetName, region)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	for key, value in pairs(frame) do
		if rawequal(value, region) and type(key) == "string" then
			return key
		end
	end
	return self:ArtKey(region)
end

-- Per-region tuning of a window the kit does not otherwise touch (the
-- `regions` table of an element; MelloUI's own windows use this).
function Kit:TuneRegions(frame, regions)
	if not (frame and frame.GetRegions and regions) then
		return
	end
	local ok, list = pcall(function() return { frame:GetRegions() } end)
	if not ok then
		return
	end
	for index, region in ipairs(list) do
		if region.GetObjectType and region:GetObjectType() == "Texture" then
			-- a texture with no name and no key is addressed by its position,
			-- the same way the editor wrote it down
			local key = self:RegionKey(frame, region)
			local tune = (key and regions[key]) or regions["#" .. index]
			if tune then
				if tune.hidden then
					region.melloHidden = true
					pcall(region.Hide, region)
				else
					if region.melloHidden then
						region.melloHidden = nil
						pcall(region.Show, region)
					end
					self:TuneTexture(region, tune)
				end
			elseif region.melloTuned or region.melloHidden then
				-- it was changed and is not listed any more: put it back.
				-- Only ever a texture we touched, so the game's own tints and
				-- hidden states are left alone.
				if region.melloHidden then
					region.melloHidden = nil
					pcall(region.Show, region)
				end
				self:TuneTexture(region, nil)
			end
		end
	end
end

function Kit:Replace(region, opts)
	opts = opts or {}
	local key = opts.as or self:ArtKey(region)
	local rule = self:RuleFor(key)
	if not rule then
		return nil, key
	end
	local isFrame = region.GetObjectType and region:GetObjectType() ~= "Texture" and region.CreateTexture
	local parent = opts.parent or (isFrame and region:GetParent()) or region:GetParent()
	local rect = opts.rect or region
	-- the editing tools' tuning for this element (Core\KitTuning.lua)
	local KT = MelloUI.KitTuning
	local tune = KT and KT:Tune(key) or nil
	if tune and tune.hidden then
		-- "leave this one alone": the game's own art stays, as if the library
		-- had no rule for it
		return nil, key
	end
	-- a proxy rectangle stands between the game's element and our piece so
	-- the editor can move and resize the piece without touching the game's
	-- layout; it is made whenever there is something to offset, and always
	-- while the editor addon is installed (so a drag has something to move)
	local proxy
	if tune or self.liveEdit then
		proxy = CreateFrame("Frame", nil, parent)
		proxy.ignoreInLayout = true   -- never part of a layout frame's size (see Holder)
		proxy:EnableMouse(false)
		local x, y = tune and tune.x or 0, tune and tune.y or 0
		proxy:SetPoint("TOPLEFT", rect, "TOPLEFT", x - (tune and tune.padL or 0), y + (tune and tune.padT or 0))
		proxy:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", x + (tune and tune.padR or 0), y - (tune and tune.padB or 0))
		proxy.melloProxyOf = rect
		rect = proxy
	end
	local level = (tune and tune.level) or opts.level or rule.level or -1
	-- fitHeight / fitWidth: the element's size as the template states it, used
	-- where its rect reads SECRET (the target's spell bar) or is not laid out yet
	local rep = Mixin({ kind = rule.kind, key = key, rule = rule, region = region, rect = rect, alsoFade = opts.alsoFade or {}, fitHeight = opts.fitHeight, fitWidth = opts.fitWidth, noFade = opts.noFade }, ReplacementMixin)
	rep.proxy, rep.proxyOf, rep.tune = proxy, proxy and proxy.melloProxyOf or nil, tune

	local function Holder(lvl)
		local f = CreateFrame("Frame", nil, parent)
		-- never part of the parent's size: a layout frame (an action bar, a
		-- ResizeLayoutFrame) grows round its shown children, and a holder on
		-- a rect past its content would make it grow (user, 2026-09-23: Action
		-- Bar 1 swelling in Edit Mode with the backdrop)
		f.ignoreInLayout = true
		-- opts.strata: a holder below everything at the parent's strata (the
		-- main bar's end caps under every bar and the status bars)
		if opts.strata then
			f:SetFrameStrata(opts.strata)
			-- kept there when its parent is raised (the game lifts the action
			-- bars to TOOLTIP while a spell is dragged: a holder that followed
			-- would come over the buttons)
			if f.SetFixedFrameStrata then
				f:SetFixedFrameStrata(true)
			end
		end
		f:SetFrameLevel(math.max(parent:GetFrameLevel() + lvl, 0))
		f:EnableMouse(false)
		f:SetAllPoints(rect)
		return f
	end

	if rule.kind == "frame" then
		local f = Holder(level)
		local fscale = self.scale * (rule.scale or self.frameScale)
		if rule.outset then
			-- the frame grows OUTWARD from the rect by `outset` piece px: the
			-- rails lie outside the window, their inner bevel on its edge
			local o = rule.outset * fscale
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", rect, "TOPLEFT", -o, o)
			f:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", o, -o)
		end
		-- opts.body overrides the rule's (false: edges only, for a window whose
		-- middle must stay open — the world map's canvas)
		local body = rule.body == nil and true or rule.body
		if opts.body ~= nil then
			body = opts.body
		end
		-- rule.owner: the rails and body as regions of the replaced texture's
		-- frame in the rule's layers (edgeLayer / edgeSub, bodyLayer / bodySub)
		local owner = (rule.owner and not isFrame) and region:GetParent() or nil
		rep.skin = self:NineSlice(f, { scale = fscale, gems = false, body = body, bodyScale = rule.bodyScale and self.scale * rule.bodyScale,
			open = opts.open or rule.open, prefix = rule.prefix or self.framePrefix, corners = rule.corners, skip = opts.skip,
			owner = owner, bodyLayer = rule.bodyLayer, bodySub = rule.bodySub, edgeLayer = rule.edgeLayer, edgeSub = rule.edgeSub })
		rep.checked = opts.checked
		rep.object = owner and rep.skin or f
		if rule.lit then
			rep.skin:SetTint(rule.lit[1], rule.lit[2], rule.lit[3])
		end
		local button = opts.button
		if button and (rule.hover or rule.pressed or rule.disabled) then
			-- a frame under a button: its states are a tint of the whole
			-- skin (edges and body), hover lighter, pressed / disabled darker
			-- the iron takes the rule's checkedTint while opts.checked() (a
			-- selected row); the state factor multiplies both iron and body
			local function Tint(k)
				local t = (rep.checked and rep.checked() and rule.checkedTint) or { 1, 1, 1 }
				for _, tex in ipairs(rep.skin.art) do
					tex:SetVertexColor(math.min(t[1] * k, 1), math.min(t[2] * k, 1), math.min(t[3] * k, 1))
				end
				if rep.skin.body then
					rep.skin.body:SetVertexColor(math.min(k, 1), math.min(k, 1), math.min(k, 1))
				end
			end
			local function Update()
				-- secret-safe (Slot_Update's rule): a secret IsEnabled keeps the last answer
				local disabled = rep.lastDisabled or false
				if button.IsEnabled then
					local okE, enabled = pcall(button.IsEnabled, button)
					if okE and not Secret(enabled) then
						disabled = enabled == false
					end
				end
				rep.lastDisabled = disabled
				Tint(disabled and (rule.disabled or 1) or rep.pressed and (rule.pressed or 1) or rep.hover and (rule.hover or 1) or 1)
			end
			rep.Update = Update
			button:HookScript("OnEnter", function() rep.hover = true; Update() end)
			button:HookScript("OnLeave", function() rep.hover = nil; rep.pressed = nil; Update() end)
			button:HookScript("OnMouseDown", function() rep.pressed = true; pressedLatches[rep] = Update; Update() end)
			button:HookScript("OnMouseUp", function() rep.pressed = nil; Update() end)
			if button.SetEnabled then
				hooksecurefunc(button, "SetEnabled", Update)
			end
			Update()
		end
	elseif rule.kind == "edge" then
		local f = Holder(level)
		local tex = f:CreateTexture(nil, "OVERLAY")
		tex.kitScale = self.scale * (rule.scale or self.frameScale)
		self:Apply(tex, rule.piece)
		tex:SetAllPoints(f)
		f:SetScript("OnSizeChanged", function() Kit:Retile(tex) end)
		f:HookScript("OnShow", function() Kit:Retile(tex) end)
		self:Retile(tex)
		rep.object, rep.tex = f, tex
	elseif rule.kind == "strip" then
		local state = opts.state or rule.state
		-- `owner`: the strip's textures are REGIONS of the replaced texture's
		-- frame, in its layer one sublevel up (a button's plate under its
		-- text, whatever frame level the button has); else a child frame
		local owner, layer, sub = nil, "BACKGROUND", 1
		if rule.owner and not isFrame then
			owner = region:GetParent()
			local l, sl = region:GetDrawLayer()
			layer, sub = rule.layer or l or "BACKGROUND", rule.sublevel or ((sl or 0) + 1)
		end
		local strip = self:Strip(parent, rule.base, { state = state, scale = self.scale, layer = layer, sublevel = sub, owner = owner })
		strip:SetFrameLevel(math.max(parent:GetFrameLevel() + level, 0))
		strip:SetAllPoints(rect)
		strip.forceCapless = opts.capless      -- the middle alone (a plate whose caps carry an icon, on a box that has none)
		strip.dropCap = opts.dropCap           -- one cap left out ("l" / "r"): a button that butts against another control on that side
		rep.object, rep.strip = strip, strip
		rep:Refit()
		-- the cap decision (capless when the rect is narrower than two caps)
		-- is made from the rect's width at fit time: a box fitted before its
		-- window laid it out (the backpack's search box, 0 px wide while the
		-- bag was closed at load) kept its caps hidden for good (user,
		-- 2026-09-21). A frame rect refits itself whenever its size changes.
		if rect.HookScript and rect.GetObjectType and rect:GetObjectType() ~= "Texture" then
			local function Refit()
				if rep.object and rep.object:IsShown() then
					rep:Refit()
				end
			end
			rect:HookScript("OnSizeChanged", Refit)
			rect:HookScript("OnShow", Refit)   -- sized while hidden: no OnSizeChanged came
		end
		local button = opts.button
		if button then
			-- a plate under a button: hover / pressed / disabled from the
			-- button's scripts and SetEnabled, like a slot rim
			local function Update()
				local disabled = button.IsEnabled and button:IsEnabled() == false
				-- a strip's states are painted on its parts: resolve on the mid
				rep:SetState(Kit:ResolveState(rule.base .. "_mid", rep.hover, rep.pressed, nil, disabled))
			end
			button:HookScript("OnEnter", function() rep.hover = true; Update() end)
			button:HookScript("OnLeave", function() rep.hover = nil; rep.pressed = nil; Update() end)
			button:HookScript("OnMouseDown", function() rep.pressed = true; pressedLatches[rep] = Update; Update() end)
			button:HookScript("OnMouseUp", function() rep.pressed = nil; Update() end)
			if button.SetEnabled then
				hooksecurefunc(button, "SetEnabled", Update)
			end
			if button.Enable then
				hooksecurefunc(button, "Enable", Update)
			end
			if button.Disable then
				hooksecurefunc(button, "Disable", Update)
			end
			rep.button = button
			rep.Update = Update
			Update()
		end
		if rule.onRail then
			-- the plate is lifted from the title container onto the outer
			-- rail: its BOTTOM on the band's top edge, above the window's
			-- top edge; the container's TitleText goes with it, centred on
			-- the plate, and is put back on disable
			local window = parent:GetParent()
			local text = parent.TitleText
			local refit = rep.Refit
			rep.Refit = function(self)
				refit(self)
				if not window then
					return
				end
				-- the plate rides the OUTER rail across its whole width (user,
				-- 2026-09-23, layout C): centred on the rail's middle line, its
				-- caps' gems on the rail's top corners, where the frame's own
				-- gems were (they give way: RegisterShell); anchored to the
				-- window's top corners, so no layout is needed
				local lift, reach = Kit:TitleOnRail(self.strip)
				local out = Kit:OuterRailOutset() + reach
				-- with a portrait ring on the corner the plate starts at the
				-- ring's centre, its left cap left out: nothing of it shows
				-- left of the ring, the rest runs into the ring's hole (user,
				-- 2026-09-23: the cap past the ring "mask completely")
				local left = -out
				local ringX = self.behindRing and Kit:RingCentreX(self.behindRing, window)
				self.strip.dropCap = ringX and "l" or nil
				if ringX then
					left = ringX
				end
				-- the title stays over the window's middle, not the shorter plate's
				self.strip.textShift = -(left + out) / 2
				self.strip:ClearAllPoints()
				self.strip:SetPoint("LEFT", window, "TOPLEFT", left, lift)
				self.strip:SetPoint("RIGHT", window, "TOPRIGHT", out, lift)
				self.strip:SetHeight(self.strip.height)
				local w = window:GetWidth()
				if w and w > 0 and not (issecretvalue and issecretvalue(w)) then
					self.strip:FitCaps(w + out - left)
				end
			end
			if text then
				local saved = {}
				for i = 1, text:GetNumPoints() do
					saved[i] = { text:GetPoint(i) }
				end
				-- centred on the plate's PAINTED box, not its canvas (the box
				-- sits lower in the canvas: the text read as riding high —
				-- user, 2026-09-21)
				local function Centre(self)
					local mid = PIECES[StripName(self.strip.base, "mid", self.strip.state)]
					local dy = 0
					if mid and mid.box then
						dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (self.strip.scale or Kit.scale)
					end
					text:ClearAllPoints()
					text:SetPoint("CENTER", self.strip, "CENTER", self.strip.textShift or 0, dy)
					Kit:TitleFont(text, true)
				end
				rep.onEnable = Centre
				local refit2 = rep.Refit
				rep.Refit = function(self)
					refit2(self)
					if self.object:IsShown() then
						Centre(self)
					end
				end
				rep.onDisable = function()
					Kit:TitleFont(text, false)
					text:ClearAllPoints()
					for _, pt in ipairs(saved) do
						text:SetPoint(unpack(pt))
					end
				end
			end
			-- the window may be laid out only when shown: fit again then
			strip:SetScript("OnShow", function() rep:Refit() end)
		end
		local edit = opts.edit
		if edit then
			-- a plate under an edit box: its focused look while it has focus
			edit:HookScript("OnEditFocusGained", function() rep:SetState("focused") end)
			edit:HookScript("OnEditFocusLost", function() rep:SetState(rule.state or Kit:FirstState(rule.base, "mid")) end)
		end
	elseif rule.kind == "slot" then
		local button = opts.button or parent
		local rim = self:Slot(button, { kind = rule.slot or "slot", scale = self.scale, checked = opts.checked, under = rule.under,
			layer = rule.layer, sublevel = rule.sublevel })
		rim.iconGrow = rule.iconGrow
		rim.iconBleed = rule.iconBleed
		rim:ClearAllPoints()
		rim:SetAllPoints(rect)
		if opts.icon then
			-- the game's icon fitted into the rim's opening (a side tab's
			-- icon is drawn off-centre and clipped by the game's own mask,
			-- which is faded with the tab art); the game's anchors are
			-- restored on disable
			local icon = opts.icon
			local saved = { w = icon:GetWidth(), h = icon:GetHeight() }
			for i = 1, icon:GetNumPoints() do
				saved[i] = { icon:GetPoint(i) }
			end
			rim.icon = icon
			rep.onEnable = function()
				self:SlotPlaceIcon(rim)
			end
			rep.onDisable = function()
				icon:ClearAllPoints()
				for i = 1, #saved do
					icon:SetPoint(unpack(saved[i]))
				end
				icon:SetSize(saved.w, saved.h)
			end
			-- the game re-anchors the icon on press / release and on its own
			-- layout: fit it again after each
			for _, m in ipairs({ "InitializeIconAnchoring", "UpdateIconInterior", "OnMouseDown", "OnMouseUp" }) do
				if button[m] then
					hooksecurefunc(button, m, function()
						if rep.object:IsShown() then
							self:SlotPlaceIcon(rim)
						end
					end)
				end
			end
			-- `keepIcon`: whoever anchors the icon afterwards (a side tab
			-- centres it with an offset on press, release and selection, and
			-- sizes it to its atlas: it spilled over the rim -- user,
			-- 2026-09-23), it goes straight back into the opening
			if rule.keepIcon then
				hooksecurefunc(icon, "SetPoint", function()
					if rep.object:IsShown() and not rim.placingIcon then
						self:SlotPlaceIcon(rim)
					end
				end)
			end
		end
		-- the rim's size from the pitch: gemSpan (neighbours share a gem: the
		-- rim larger than the pitch), or pitchSize (a thin rim a little inside
		-- the pitch: the micro buttons, taller than they are apart)
		local function PitchSize(px, py)
			if rule.gemSpan then
				return px / rule.gemSpan[1], py / rule.gemSpan[2]
			elseif rule.pitchSize then
				return px * rule.pitchSize, py * rule.pitchSize
			end
		end
		local pw, ph
		if opts.pitch and opts.pitch[1] > 0 and opts.pitch[2] > 0 then
			pw, ph = PitchSize(opts.pitch[1], opts.pitch[2])
		end
		if pw then
			rim:ClearAllPoints()
			rim:SetPoint("CENTER", rect, "CENTER")
			rim:SetSize(pw, ph)
		end
		-- SetPitch(x, y): re-size the rim to a new pitch (a bar re-laid by
		-- Edit Mode) and fit the icon again
		rep.SetPitch = function(self, px, py)
			local w, h
			if px and py and px > 0 and py > 0 then
				w, h = PitchSize(px, py)
			end
			if w then
				rim:ClearAllPoints()
				rim:SetPoint("CENTER", rect, "CENTER")
				rim:SetSize(w, h)
				if rim.icon then
					Kit:SlotPlaceIcon(rim)
				end
			end
		end
		if rule.rest then
			rim.restState = rule.rest
		end
		if rule.glow then
			local glow = rim.owner:CreateTexture(nil, rule.under and "ARTWORK" or "OVERLAY", nil, 4)
			glow.kitScale = self.scale
			-- the glow is the rim's checked look, or its hover look for a rim
			-- painted without one (the round slot)
			local look = rule.rest or (PIECES[rim.base .. "_checked"] and "checked") or (PIECES[rim.base .. "_hover"] and "hover") or self:FirstStateOf(rim.base)
			self:Apply(glow, rim.base .. "_" .. look)
			glow:SetBlendMode("ADD")
			glow:SetAllPoints(rim)
			glow:Hide()
			rim.glow = glow
		end
		rim:Update()
		rep.object = rim
		if rule.sideTab then
			self:RegisterSideTab(rep, button)
		end
	elseif rule.kind == "state" then
		local button = opts.button or parent
		local tex = self:StateTexture(button, rule.base, { scale = self.scale, layer = rule.layer or "OVERLAY", checked = opts.checked })
		if rule.rect == "normal" and button.GetNormalTexture and button:GetNormalTexture() then
			rect = button:GetNormalTexture()
		end
		tex:ClearAllPoints()
		if rule.natural then
			-- the kit size, its OPAQUE part centred on the rect (a 17 x 11
			-- stepper under a 16 x 15 arrow; an arrow painted off-centre in
			-- its canvas is placed by its box, not its canvas); `fit =
			-- "height"` sizes it to the rect's height instead, aspect kept
			local name = rule.base .. "_" .. (self:FirstStateOf(rule.base) or "normal")
			local p = PIECES[name]
			local w, h = self:Size(name, self.scale)
			if rule.fit == "height" and p and rect:GetHeight() > 0 then
				h = rect:GetHeight()
				w = h * p.w / p.h
			elseif rule.fit == "width" and p and rect:GetWidth() > 0 then
				w = rect:GetWidth()
				h = w * p.h / p.w
			end
			tex:SetSize(w, h)
			local dx, dy = 0, 0
			if p and p.box then
				local k = w / p.w
				dx = (p.w / 2 - (p.box[1] + p.box[3]) / 2) * k
				dy = ((p.box[2] + p.box[4]) / 2 - p.h / 2) * k
			end
			tex:SetPoint("CENTER", rect, "CENTER", dx, dy)
		else
			tex:SetAllPoints(rect)
		end
		rep.object, rep.rect = tex, rect
	elseif rule.kind == "vstrip" then
		-- an upright strip on the rect's height, `widthScale` x the rect's
		-- width, centred; its state follows the button's over / down flags
		local button = opts.button or parent
		local strip = self:VStrip(parent, rule.base, { scale = self.scale, layer = "ARTWORK", sublevel = 1 })
		strip:SetFrameLevel(math.max(parent:GetFrameLevel() + level, 0))
		strip:SetPoint("TOP", rect, "TOP")
		strip:SetPoint("BOTTOM", rect, "BOTTOM")
		rep.object, rep.vstrip, rep.button = strip, strip, button
		rep.Refit = function(self)
			local w = self.rect:GetWidth()
			if w and w > 0 then
				self.vstrip:FitWidth(w * (rule.widthScale or 1))
			end
		end
		rep:Refit()
		if button and button.OnButtonStateChanged then
			hooksecurefunc(button, "OnButtonStateChanged", function() rep:SetState() end)
		elseif button and button.HookScript then
			-- no state mixin: the over / down flags from the button's scripts
			-- (FollowButton drives a slot rim, not a strip)
			for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp" }) do
				button:HookScript(script, function() rep:SetState() end)
			end
		end
		rep:SetState()
	elseif rule.kind == "bar" then
		-- a hollow bar bracket fitted to the rect's height, the trough in its
		-- opening, both as REGIONS of the rect's own frame: the trough in the
		-- replaced background's layer, the bracket in BORDER above the game's
		-- fill and below its ARTWORK text, so the rails cover the fill's edges
		-- `opts.bar`: another bracket than the rule's (a panel's Bar Border
		-- choice: "frame" the ornate P1, "castbar", or a thin rim look
		-- "rim" / "rimhair" / "rimround" / "rimgold" / "rimsunk");
		-- rep:SetBar(bar) swaps it live
		-- a progress bar's bracket follows its group's border (every window's
		-- Progress Bar Border; the nameplates' their own); a cast bar keeps its
		local group = rule.bar ~= "castbar" and (rule.borderGroup or "bar") or nil
		local base = "bars/" .. (opts.bar or (group and self:BorderValue(group)) or rule.bar or "frame")
		if not PIECES[StripName(base, "mid")] then
			base = "bars/" .. (rule.bar or "frame")
		end
		rep.base = base
		if group then
			self:RegisterBorderBar(group, rep)
		end
		-- the bracket goes in the layer just above the game's fill (`layer` /
		-- `sublevel` on the rule: the caps at that sublevel, the middle ONE
		-- BELOW it, so the sublevel must be at least the fill's + 2: BORDER 1
		-- over a BORDER 0 fill, ARTWORK 4 over a rank bar's ARTWORK 2 fill),
		-- the trough in BACKGROUND under it
		-- opts.layer / sublevel / troughLayer / troughSub override the rule's
		-- for a fill drawn elsewhere (a unit frame's power bar at ARTWORK: the
		-- bracket at OVERLAY 0, the trough at BORDER)
		-- `state`: a variant of the caps ("red": the red end gems a health bar
		-- keeps, while every other bracket's are iron -- Tools/kit_gems.py)
		local strip = self:Strip(parent, base, { scale = self.scale, owner = parent, layer = opts.layer or rule.layer or "BORDER", sublevel = opts.sublevel or rule.sublevel or 1,
			state = opts.state or rule.state })
		strip:SetPoint("LEFT", rect, "LEFT")
		strip:SetPoint("RIGHT", rect, "RIGHT")
		-- `dropCap` ("l" / "r"): that end is capless, the rails running to the
		-- rect's edge (a unit frame's bar butting into the portrait ring);
		-- `capOut`: the kept cap(s) grow OUTWARD past the rect by their solid
		-- arm, so the opening starts at the rect's edge and the fill keeps its
		-- whole width (B3, user 2026-09-21); the trough's sublevel from
		-- `troughSub` (-1 under a fill drawn at BACKGROUND 0)
		strip.dropCap = opts.dropCap or rule.dropCap
		rep.capOut = opts.capOut or rule.capOut
		-- opts.troughParent: another frame for the trough (one below a fill
		-- that lives on a LOWER strata than the bracket's frame)
		local trough = (opts.troughParent or parent):CreateTexture(nil, opts.troughLayer or rule.troughLayer or "BACKGROUND", nil, opts.troughSub or rule.troughSub or 1)
		trough.kitScale = self.scale
		self:Apply(trough, "bars/trough")
		rep.object, rep.strip, rep.trough = strip, strip, trough
		-- a StatusBar's fill can change layer after the bracket was placed
		-- (Bar Textures sets its own fill texture, which comes up at ARTWORK
		-- where the game's was at BACKGROUND): the bracket and trough follow
		-- the fill's layer on every SetStatusBarTexture (user, 2026-09-21:
		-- the unit frame fills came up over their brackets)
		if opts.layer and parent.SetStatusBarTexture and parent.GetStatusBarTexture then
			rep.Relayer = function(self)
				local layer, sub, tl, ts = Kit:BracketLayers(parent, true)
				if not layer then
					return   -- unreadable (secret) on this bar: the bracket stays where it was placed
				end
				self.strip.capL:SetDrawLayer(layer, sub)
				self.strip.capR:SetDrawLayer(layer, sub)
				self.strip.mid:SetDrawLayer(layer, sub - 1)
				if not opts.troughParent then
					self.trough:SetDrawLayer(tl, ts)
				end
			end
			hooksecurefunc(parent, "SetStatusBarTexture", function()
				if rep.object:IsShown() then
					rep:Relayer()
				end
			end)
		end
		-- the caps' solid arms (from the piece's edge to its opening) in UI px
		rep.GetArms = function(self)
			local sc = self.strip.scale
			local capL, capR = PIECES[StripName(self.base, "cap_l")], PIECES[StripName(self.base, "cap_r")]
			local l = capL and capL.open and capL.open[1] * sc or self.strip.wl or 0
			local r = capR and capR.open and (capR.w - capR.open[3]) * sc or self.strip.wr or 0
			return l, r
		end
		-- the bracket's fill area as insets from the rect: sideways from the
		-- caps' hollow arms (past the gems) a little under the gems' bezels,
		-- top / bottom most of the way into the rails, so the rails cover the edges
		rep.GetOpening = function(self)
			local sc = self.strip.scale
			local mid = PIECES[StripName(self.base, "mid")]
			local under = (rule.underGem or 3) * sc
			local armL, armR = self:GetArms()
			-- a dropped or outward cap leaves the rect's whole width to the fill
			local dropL = self.strip.dropCap == "l" or self.strip.capless
			local dropR = self.strip.dropCap == "r" or self.strip.capless
			local l = (dropL or self.capOut) and 0 or armL - under
			local r = (dropR or self.capOut) and 0 or armR - under
			-- the fill's rows in the mid's canvas: `into` of the way through
			-- each rail (1: the bracket's whole height, the rails over fill)
			local into = rule.into or 1
			local rowT, rowB = 0, mid and mid.h or 0
			if mid and mid.open and mid.box then
				rowT = mid.open[2] - (mid.open[2] - mid.box[2]) * into
				rowB = mid.open[4] + (mid.box[4] - mid.open[4]) * into
			end
			-- the strip's canvas is centred on the rect's centre line, shifted
			-- by yoff (FitBox), and is canvasH tall: a canvas row's distance
			-- from the rect's top / bottom edge
			local rectH = self:RectSize("GetHeight")
			if not (rectH and rectH > 0) then
				rectH = self.fitHeight or 0
			end
			local canvasH = (mid and mid.h or 0) * sc
			local yoff = self.stripOffset or 0
			local top = rectH / 2 - yoff - canvasH / 2 + rowT * sc
			local bottom = rectH / 2 + yoff + canvasH / 2 - rowB * sc
			return l, r, top, bottom
		end
		rep.Refit = function(self)
			local h = self:RectSize("GetHeight")
			if not (h and h > 0) then
				h = self.fitHeight
			end
			if not (h and h > 0) then
				return
			end
			-- `thicken`: the bracket is that many UI px taller than the rect,
			-- centred on it (it overhangs the rect top and bottom)
			-- `heightScale`: the bracket that fraction of the rect's height,
			-- centred on it (the character pane's bars at 0.85 — user, 2026-09-21)
			-- `artScale` (opts or rule): the border ART drawn at that fraction
			-- of the scale the fit gives, in every Progress Bar Border look
			-- (thinner rails, smaller caps and gems, the opening with them), for
			-- one set of bars without touching the rule every window shares
			-- (user, 2026-09-24: the Reputation and Skills tabs' bars at 0.85).
			-- Every size below (arms, opening, caps) is read from the strip's
			-- scale, so the fill and the trough follow; kept in `opts`, so a
			-- live look swap (SetBar -> Refit) keeps it too
			local artScale = opts.artScale or rule.artScale or 1
			local yoff = self.strip:FitBox((h + (opts.thicken or rule.thicken or 0)) * (rule.heightScale or 1) * artScale)
			self.stripOffset = yoff
			local w = self:RectSize("GetWidth")
			if not (w and w > 0) then
				w = self.fitWidth or 0
			end
			-- the caps: one dropped (the mid to that edge), the kept ones inside
			-- the rect or, with capOut, outside it by their solid arm
			local outL, outR = 0, 0
			if self.capOut then
				local armL, armR = self:GetArms()
				outL = self.strip.dropCap ~= "l" and armL or 0
				outR = self.strip.dropCap ~= "r" and armR or 0
			end
			self.strip:ClearAllPoints()
			self.strip:SetPoint("LEFT", self.rect, "LEFT", -outL, yoff)
			self.strip:SetPoint("RIGHT", self.rect, "RIGHT", outR, yoff)
			self.strip:SetHeight(self.strip.height)
			-- the cap test (capless when narrower than two caps) only for a
			-- bracket that drops or grows a cap: a window's P1 bars are meant
			-- to keep both caps even when they overlap (the 160 px stat bars)
			if self.strip.dropCap or self.capOut then
				self.strip:FitCaps(w + outL + outR)
			end
			local l, r, t, b = self:GetOpening()
			self.trough:ClearAllPoints()
			self.trough:SetPoint("TOPLEFT", self.rect, "TOPLEFT", l, -t)
			self.trough:SetPoint("BOTTOMRIGHT", self.rect, "BOTTOMRIGHT", -r, b)
			Kit:Retile(self.trough)
		end
		rep.SetBar = function(self, bar)
			local b = "bars/" .. (bar or "frame")
			if b == self.base or not PIECES[StripName(b, "mid")] then
				return
			end
			self.base = b
			self.strip:SetBase(b)
			self:Refit()
		end
		rep:Refit()
		local show, hide = strip.Show, strip.Hide
		strip.Show = function(f) show(f); trough:Show() end
		strip.Hide = function(f) hide(f); trough:Hide() end
	elseif rule.kind == "picture" then
		-- a painted picture on the rect, cropped to the rect's aspect (never
		-- stretched): `crop` says which part stays when the rect is wider
		-- than the picture ("bottom" / "top" / "middle"; columns are always
		-- centred). `grey` names the greyscale twin, shown while opts.grey()
		-- is true. `frame` lays the single-rail edges over it.
		-- `owner`: the picture is a REGION of the replaced texture's frame in
		-- that texture's layer and sublevel (a page's backdrop under the page's
		-- own children, whatever their levels: no holder, so no level tie);
		-- else a holder frame at `level`
		local f, tex, inner
		if rule.owner and not isFrame then
			local l, sl = region:GetDrawLayer()
			f = region:GetParent()
			tex = f:CreateTexture(nil, l or "BACKGROUND", nil, sl or 0)
			inner = CreateFrame("Frame", nil, f)
			inner:EnableMouse(false)
			-- opts.inset = { l, r, t, b } UI px: the picture stops short of the
			-- rect (inside the window's outer rail, so the rail stays in front)
			local ins = opts.inset or { 0, 0, 0, 0 }
			inner:SetPoint("TOPLEFT", rect, "TOPLEFT", ins[1], -ins[3])
			inner:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", -ins[2], ins[4])
		else
			f = Holder(level)
			-- the picture stops at the rails' centre lines when a frame is over it
			-- (the rails cover its edges; past them it would show outside the
			-- frame): `inner` is the rect inset by each rail's centre
			inner = CreateFrame("Frame", nil, f)
			inner:EnableMouse(false)
			if rule.frame then
				local pre = self.framePrefix
				inner:SetPoint("TOPLEFT", f, "TOPLEFT", self:RailInset(pre .. "_l", "l"), -self:RailInset(pre .. "_t", "t"))
				inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -self:RailInset(pre .. "_r", "r"), self:RailInset(pre .. "_b", "b"))
			elseif opts.inset then
				-- opts.inset = { l, r, t, b }: inside the window's outer rail
				local ins = opts.inset
				inner:SetPoint("TOPLEFT", f, "TOPLEFT", ins[1], -ins[3])
				inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ins[2], ins[4])
			else
				inner:SetAllPoints(f)
			end
			tex = f:CreateTexture(nil, "BACKGROUND")
		end
		tex.kitScale = self.scale
		tex:SetAllPoints(inner)
		rep.object, rep.tex, rep.inner, rep.grey = (rule.owner and not isFrame) and tex or f, tex, inner, opts.grey
		-- `desaturate` (0..1): the picture's colour taken down that much (the
		-- secondary professions' cards at 10 % saturation: 0.9; user,
		-- 2026-09-24: "reduce the saturation of this Artwork to 10%")
		if rule.desaturate and tex.SetDesaturation then
			pcall(tex.SetDesaturation, tex, rule.desaturate)
		end
		-- `dim` (0..1): the picture darkened, a backdrop behind text (the
		-- crafting page's schematics: the recipe's name and reagents read
		-- over it -- user, 2026-09-24: "this is a bit hard to read")
		if rule.dim then
			tex:SetVertexColor(rule.dim, rule.dim, rule.dim)
		end
		-- `edge` = "brush": the picture ends in painted strokes on every side
		-- (Kit:PaintedEdge); `edgeMirror` flips them for a left-hand page
		if rule.edge then
			rep.edge = self:PaintedEdge(tex, inner, rule.edgeMirror)
		end
		-- `edgeBacking`: a tiled piece right under the picture, on the same
		-- rect, so the gaps between the strokes show stone and not whatever
		-- lies behind the window (user, 2026-09-23: the quest log over the
		-- world map, MelloUI's quest list: "add the dark cracked concrete
		-- behind")
		if rule.edgeBacking then
			local layer, sub = tex:GetDrawLayer()
			sub = sub or 0
			if sub <= -8 then
				-- no sublevel left under the picture: the picture steps up one
				sub = -7
				tex:SetDrawLayer(layer, sub)
			end
			local backing = tex:GetParent():CreateTexture(nil, layer, nil, sub - 1)
			backing:SetAllPoints(inner)
			backing.kitScale = self.scale * self.frameScale
			if self:Apply(backing, rule.edgeBacking) then
				rep.backing = backing
			else
				backing:Hide()
			end
		end
		rep.Refit = function(self)
			-- rep:SetPiece(value): a panel's background choice in place of
			-- the rule's piece ("dark": a flat fill)
			if self.pieceOverride == "dark" then
				self.tex:SetColorTexture(0.05, 0.045, 0.04, 0.95)
				self.tex.kitPiece, self.tex.kitName = true, nil
				return
			end
			local name = self.pieceOverride or ((self.grey and rule.grey and self.grey()) and rule.grey or rule.piece)
			if self.tex.kitName ~= name then
				Kit:Apply(self.tex, name)
				-- the parchment in the kit's one parchment tone
				if name == Kit.parchmentPiece then
					local t = Kit.parchmentTint
					self.tex:SetVertexColor(t[1], t[2], t[3])
				elseif rule.dim then
					self.tex:SetVertexColor(rule.dim, rule.dim, rule.dim)
				end
			end
			local p = PIECES[name]
			local w, h = self.inner:GetSize()
			if not (p and w and h and w > 0 and h > 0) then
				return
			end
			if self.edge then
				self.edge:Fit(w, h)
			end
			if self.backing then
				Kit:Retile(self.backing)
			end
			if p.tile then
				-- a background: repeated at the UI's one background
				-- resolution, never fitted by stretching; `crop` says where
				-- it starts (the middle, the top or the bottom of the rect)
				self.tex.kitAlign = (rule.crop == "top" and "top") or (rule.crop == "bottom" and "bottom") or "center"
				Kit:Retile(self.tex)
				return
			end
			local u1, u2, v1, v2 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
			local pa, ra = p.w / p.h, w / h
			if rule.fit == "right" then
				-- the whole picture at the rect's height, against its right
				-- edge (its subject is there); the rest of the rect, to the
				-- left, is the picture's own left columns mirrored, so the
				-- stone continues without a seam and nothing is cut off
				local picW = h * pa
				self.tex:ClearAllPoints()
				if picW >= w then
					self.tex:SetAllPoints(self.inner)
					self.tex:SetTexCoord(u2 - (u2 - u1) * (w / picW), u2, v1, v2)
					if self.filler then
						self.filler:Hide()
					end
					return
				end
				self.tex:SetPoint("TOPRIGHT", self.inner, "TOPRIGHT")
				self.tex:SetPoint("BOTTOMRIGHT", self.inner, "BOTTOMRIGHT")
				self.tex:SetWidth(picW)
				self.tex:SetTexCoord(u1, u2, v1, v2)
				if not self.filler then
					self.filler = self.object:CreateTexture(nil, "BACKGROUND")
					self.filler.kitScale = self.tex.kitScale
				end
				if self.filler.kitName ~= name then
					Kit:Apply(self.filler, name)
				end
				self.filler:ClearAllPoints()
				self.filler:SetPoint("TOPLEFT", self.inner, "TOPLEFT")
				self.filler:SetPoint("BOTTOMRIGHT", self.tex, "BOTTOMLEFT")
				self.filler:SetTexCoord(u1 + (u2 - u1) * ((w - picW) / picW), u1, v1, v2)
				self.filler:Show()
				return
			end
			if ra > pa + 0.001 then
				local frac = pa / ra                 -- the visible share of the picture's height
				if rule.crop == "top" then
					v2 = v1 + (v2 - v1) * frac
				elseif rule.crop == "middle" then
					local c, half = (v1 + v2) / 2, (v2 - v1) * frac / 2
					v1, v2 = c - half, c + half
				else
					v1 = v2 - (v2 - v1) * frac
				end
			elseif ra < pa - 0.001 then
				local c, half = (u1 + u2) / 2, (u2 - u1) * (ra / pa) / 2
				u1, u2 = c - half, c + half
			end
			self.tex:SetTexCoord(u1, u2, v1, v2)
		end
		rep.SetPiece = function(self, value)
			local piece = value and (Kit.buttonLooks.backgroundPiece[value] or (PIECES[value] and value))
			self.pieceOverride = (value == "dark" and "dark") or piece or nil
			if not self.pieceOverride then
				local k = rule.dim or 1
				self.tex:SetVertexColor(k, k, k, 1)
			end
			self:Refit()
		end
		inner:SetScript("OnSizeChanged", function() rep:Refit() end)
		-- a page hidden while the skin is built has no size to fit to (the
		-- whole painting would stay stretched on it): fit again when it shows
		inner:SetScript("OnShow", function() rep:Refit() end)
		if rule.frame and rep.object == f then
			rep.skin = self:NineSlice(f, { scale = self.scale * self.frameScale, gems = false, body = false, prefix = self.framePrefix })
		end
		rep:Refit()
	elseif rule.kind == "fade" then
		-- nothing stands in: the region is faded while the skin is on
		local f = Holder(level)
		rep.object = f
	elseif rule.kind == "solid" then
		-- a flat colour on the rect (`color` = { r, g, b, a })
		local f = Holder(level)
		local tex = f:CreateTexture(nil, "BACKGROUND")
		local c = rule.color or { 0.18, 0.18, 0.19, 1 }
		tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		tex.kitPiece = true            -- ours: never faded by GameArt
		tex:SetAllPoints(f)
		rep.object, rep.tex = f, tex
	elseif rule.kind == "tile" then
		-- `owner`: the tile is a REGION of the replaced texture's frame in its
		-- layer (a list's body under the list's own children); else a holder
		local f, tex
		if rule.owner and not isFrame then
			-- rule.layer / sublevel: a place in the owner's stack other than the
			-- replaced region's (an empty slot's stone UNDER the icon)
			local l, sl = region:GetDrawLayer()
			f = region:GetParent()
			tex = f:CreateTexture(nil, rule.layer or l or "BACKGROUND", nil, rule.sublevel or sl or 0)
			tex:SetAllPoints(rect)
		else
			f = Holder(level)
			tex = f:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints(f)
			f:SetScript("OnSizeChanged", function() Kit:Retile(tex) end)
			f:HookScript("OnShow", function() Kit:Retile(tex) end)
		end
		tex.kitScale = self.scale * (rule.scale or 1)
		self:Apply(tex, rule.piece)
		self:Retile(tex)
		rep.object, rep.tex = (rule.owner and not isFrame) and tex or f, tex
		-- `edge` = "brush": the tiled panel ends in painted strokes on every
		-- side (Kit:PaintedEdge), fitted again whenever its size changes
		local edge = rule.edge and self:PaintedEdge(tex, tex, rule.edgeMirror, rule.edgeTight) or nil
		rep.edge = edge
		local function Refit()
			Kit:Retile(tex)
			if edge then
				local okS, w, h = pcall(tex.GetSize, tex)
				if okS then
					edge:Fit(w, h)
				end
			end
		end
		if rep.object == tex then
			-- a region has no OnSizeChanged: re-tile on the rect's
			local sizer = CreateFrame("Frame", nil, f)
			sizer:EnableMouse(false)
			sizer:SetAllPoints(rect)
			sizer:SetScript("OnSizeChanged", Refit)
			sizer:HookScript("OnShow", Refit)
		elseif edge then
			f:SetScript("OnSizeChanged", Refit)
			f:HookScript("OnShow", Refit)
		end
		Refit()
	elseif rule.kind == "texture" then
		-- `owner`: the piece is a REGION of the replaced texture's frame in its
		-- layer and sublevel (a level plate under the frame's own text); else
		-- on a holder frame
		local f, tex
		if rule.owner and not isFrame then
			-- rule.layer / sublevel: a place in the owner's stack other than
			-- the replaced region's (a party frame's ring under its name)
			local l, sl = region:GetDrawLayer()
			f = region:GetParent()
			tex = f:CreateTexture(nil, rule.layer or l or "ARTWORK", nil, rule.sublevel or sl or 0)
			tex.kitScale = self.scale
			self:Apply(tex, rule.piece)
		else
			f = Holder(level)
			tex = self:Texture(f, rule.piece, "OVERLAY", 1, self.scale)
		end
		if rule.natural then
			tex:SetSize(self:Size(rule.piece, self.scale * (rule.scale or 1)))
			tex:SetPoint("CENTER", opts.center or rect, opts.centerPoint or "CENTER")
		elseif rule.fit == "height" then
			-- the rect's height, the piece's aspect, on the rect's `anchor`
			-- corner (a wide rail cap standing on a tall gryphon rect)
			local piece = PIECES[rule.piece]
			local okS, _, h = pcall(rect.GetSize, rect)
			if not okS or Secret(h) or not (h and h > 0) then
				h = 1
			end
			tex:SetSize(piece and h * piece.w / piece.h or h, h)
			tex:SetPoint(rule.anchor or "CENTER", rect, rule.anchor or "CENTER")
			if f ~= rect and f.SetScript then
				f:SetScript("OnSizeChanged", function(_, _, nh)
					if nh and not Secret(nh) and nh > 0 then
						tex:SetSize(piece and nh * piece.w / piece.h or nh, nh)
					end
				end)
			end
		elseif rule.square or rule.opening then
			local okS, w, h = pcall(rect.GetSize, rect)
			if not okS or Secret(w) or Secret(h) then
				w, h = 0, 0
			end
			local size = math.min(w > 0 and w or h, h > 0 and h or w)
			local piece = PIECES[rule.piece]
			if rule.opening and piece and piece.open then
				-- the rect is the OPENING: the canvas grows around it by the
				-- piece's ratio (a ring around the game's own portrait);
				-- `openingScale` shrinks that (the minimap's ring at 0.75, its
				-- rim over the map's edge — user, 2026-09-21)
				size = size * piece.w / (piece.open[3] - piece.open[1]) * (rule.openingScale or 1)
			end
			tex:SetSize(size, size)
			tex:SetPoint("CENTER", opts.center or rect, "CENTER")
		else
			tex:SetAllPoints(rule.owner and rect or f)
		end
		rep.object, rep.tex = (rule.owner and not isFrame) and tex or f, tex
	end
	rep.object:Hide()
	-- every window's outer rail and title plate are known to the window
	-- mover (UI Modifications), whichever panel dressed the window: the
	-- older panels replace these two by hand, not through SkinWindowShell
	-- ... the WINDOW being the top frame under UIParent (a title container
	-- may sit in a page inside the window: the group finder's tabs stayed
	-- behind when only the page moved — user, 2026-09-21)
	local function Window(frame)
		local depth = 0
		while frame and frame ~= UIParent and depth < 6 do
			local up = frame.GetParent and frame:GetParent()
			if not up or up == UIParent then
				return frame
			end
			frame = up
			depth = depth + 1
		end
		return frame
	end
	if key == "TitleBar" and parent and parent.GetParent then
		local window = Window(parent:GetParent())
		if window and window ~= UIParent then
			RegisterShell(window, { title = rep })
		end
	elseif key == "NineSlicePanelTemplate" and parent then
		local window = Window(parent)
		if window and window ~= UIParent then
			RegisterShell(window, { outer = rep })
		end
	elseif key == "UI-Frame-PortraitMetal-CornerTopLeft" and parent then
		local window = Window(parent)
		if window and window ~= UIParent then
			RegisterShell(window, { ring = rep })
		end
	end
	rep.window = Window(parent)
	self:RegisterReplacement(rep)
	if tune then
		self:TuneObject(rep, tune)
	end
	return rep
end

-- A MinimalScrollBar (Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml):
-- Track with Begin / Middle / End textures and the Thumb button (its own
-- Begin / Middle / End, re-atlased on hover / press), Back and Forward
-- stepper buttons with one Texture each. The game shows and hides the bar,
-- the track and the thumb itself; the pieces are children of theirs.
-- `replace` is the panel's registering Replace. Returns the reps (or nil).
function Kit:SkinScrollBar(bar, replace)
	if bar.melloRep ~= nil then
		return bar.melloRep or nil
	end
	local track, thumb = bar.Track, bar.Track and bar.Track.Thumb
	if not (track and thumb and track.Middle and thumb.Middle) then
		bar.melloRep = false
		return nil
	end
	local reps = {}
	reps[#reps + 1] = replace(track.Middle, { as = "minimal-scrollbar-track-middle", rect = track, alsoFade = { track.Begin, track.End } })
	reps[#reps + 1] = replace(thumb.Middle, { as = "minimal-scrollbar-small-thumb-middle", rect = thumb, button = thumb, alsoFade = { thumb.Begin, thumb.End } })
	if bar.Back and bar.Back.Texture then
		reps[#reps + 1] = replace(bar.Back.Texture, { as = "minimal-scrollbar-arrow-top", button = bar.Back })
	end
	if bar.Forward and bar.Forward.Texture then
		reps[#reps + 1] = replace(bar.Forward.Texture, { as = "minimal-scrollbar-arrow-bottom", button = bar.Forward })
	end
	-- the thumb's height follows the content: refit when it changes
	thumb:HookScript("OnSizeChanged", function()
		for _, rep in ipairs(reps) do
			if rep.vstrip and rep.object:IsShown() then
				rep:Refit()
			end
		end
	end)
	bar.melloRep = reps
	return reps
end

-- Every MinimalScrollBar under `root` (a frame with Track / Thumb / Back /
-- Forward), skinned with `replace`; `skip` is a frame never walked into.
function Kit:SkinScrollBarsIn(root, replace, skip, depth)
	depth = depth or 0
	if depth > 7 or root == skip then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if child.Track and child.Track.Thumb and child.Back and child.Forward then
			self:SkinScrollBar(child, replace)     -- `replace` enables the reps itself when the skin is active
		else
			self:SkinScrollBarsIn(child, replace, skip, depth + 1)
		end
	end
end

-- A glyph the game re-atlases with a state (a header's +/-, a toggle's
-- open/closed): one replacement per atlas it has shown, kept on `owner`
-- (owner.melloIcons), the one for its current atlas shown. `replace` is the
-- panel's registering Replace; `extra` other regions to fade with it.
function Kit:StateIconReps(owner, icon, button, replace, extra)
	if not (owner and icon) then
		return
	end
	owner.melloIcons = owner.melloIcons or {}
	local key = self:ArtKey(icon)
	if key and self:RuleFor(key) and owner.melloIcons[key] == nil then
		local rep = replace(icon, { as = key, button = button or owner, rect = icon, alsoFade = extra }) or false
		owner.melloIcons[key] = rep
		if rep then
			local enable = rep.onEnable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				Kit:StateIconReps(owner, icon, button, replace, extra)
			end
		end
	end
	for k, rep in pairs(owner.melloIcons) do
		if rep then
			rep:SetShown(k == key)
		end
	end
end

-- Distance from a rail piece's outer edge to the centre line of its rail, in
-- UI units at `scale` (the edges carry a transparent pad on the outside).
-- `side` is the piece's outer side: "t", "b", "l" or "r".
function Kit:RailInset(name, side, scale)
	local p = PIECES[name]
	if not (p and p.box) then
		return 0
	end
	scale = scale or (self.scale * self.frameScale)
	if side == "t" then
		return (p.box[2] + p.box[4]) / 2 * scale
	elseif side == "b" then
		return (p.h - (p.box[2] + p.box[4]) / 2) * scale
	elseif side == "l" then
		return (p.box[1] + p.box[3]) / 2 * scale
	end
	return (p.w - (p.box[1] + p.box[3]) / 2) * scale
end

-- A cover on a junction of rails (the RailJoint rule): the piece centred where
-- the vertical rail of `x` (an `edge` replacement) crosses the horizontal
-- line `dy` UI units above the bottom edge of `y` (a frame or region), or
-- its top when opts.yPoint is "TOP", or its centre line ("CENTER", e.g. a
-- rail texture). A point in WoW carries both
-- coordinates, so a helper frame spans from the rail's bottom to that line
-- and the piece sits on the helper's top-left corner: the line must lie above
-- the rail's bottom, and y's right edge right of the rail.
--   Kit:Joint(parent, { x = rep, y = frame, yPoint = , dy = , level = })
function Kit:Joint(parent, opts)
	local rail, rect = opts.x, opts.x.rect
	local w = rect:GetWidth()
	local p = PIECES[rail.rule.piece]
	-- the edge is stretched across its rect: the rail's centre in that width
	local dx = (p and p.box and p.w > 0) and ((p.box[1] + p.box[3]) / 2 / p.w) * w or w / 2
	local helper = CreateFrame("Frame", nil, parent)
	helper:EnableMouse(false)
	helper:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", dx, 0)
	local yp = opts.yPoint == "TOP" and "TOPRIGHT" or opts.yPoint == "CENTER" and "RIGHT" or "BOTTOMRIGHT"
	helper:SetPoint("TOPRIGHT", opts.y, yp, 0, opts.dy or 0)
	return self:Replace(helper, { as = "RailJoint", parent = parent, rect = helper, noFade = true, level = opts.level, centerPoint = "TOPLEFT" })
end

--------------------------------------------------------------------------------
-- Shared window parts (2026-09-21, for the legacy, quest log and guild
-- windows): the same code the character / professions / spell book panels
-- carry inline, once. Every helper takes the panel's registering `replace`
-- (so the reps land in that panel's skin) and returns what it made.
--------------------------------------------------------------------------------

-- The first game texture of a frame (skipping ours).
function Kit:FirstTexture(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			return region
		end
	end
end

-- Every game texture of a button but `keep` (to fade with its normal art).
function Kit:OtherTextures(button, keep)
	local extra = {}
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= keep and not region.kitPiece then
			extra[#extra + 1] = region
		end
	end
	return extra
end

-- How far the window's OUTER rail (the NineSlicePanelTemplate rule, grown
-- outward by `outset`) reaches INTO the window on each side, in UI px:
-- { l, r, t, b }. A page picture inset by this stops at the rail's inner
-- bevel, so the rail is in front of it (user, 2026-09-21).
function Kit:OuterRailInset()
	local rule = self.Replacements["NineSlicePanelTemplate"]
	local prefix = rule and rule.prefix or "window/frame"
	local sc = self.scale * (rule and rule.scale or self.frameScale)
	local outset = rule and rule.outset or 0
	local function side(name, inner)
		local p = PIECES[name]
		if not (p and p.box) then
			return 0
		end
		local depth = inner == "r" and p.box[3] or inner == "l" and (p.w - p.box[1]) or inner == "b" and p.box[4] or (p.h - p.box[2])
		return math.max((depth - outset) * sc, 0)
	end
	return { side(prefix .. "_l", "r"), side(prefix .. "_r", "l"), side(prefix .. "_t", "b"), side(prefix .. "_b", "t") }
end

-- The class medallion's size in the character window's ring: the size every
-- portrait icon and ring disc is brought to (WINDOW-RULES 2b).
local MEDALLION_TO_RING = 0.759
-- the class medallion's painted disc spans this much of its texture (the
-- plain variant's opaque width: 243 of 256 px)
local MEDALLION_DISC = 0.95

-- A dark disc in a portrait ring's opening, under the portrait (an agreed
-- addition, user 2026-09-21: the Legacy shield does not fill the ring, the
-- page showed through). A region of the ring holder's parent (the game's
-- PortraitContainer, level 400: its portrait is OVERLAY, the disc goes in
-- BACKGROUND under it), masked round with the game's own circle mask, the
-- class medallion's size on the ring's centre; shown / hidden with the
-- ring's replacement. `color` = { r, g, b }.
-- `parent` / `sublevel` override the frame and BACKGROUND sublevel the disc is
-- a region of, for a window whose portrait lives elsewhere (the guild window's
-- PortraitOverlay at level 300, its portrait BACKGROUND 1: the disc at 0).
function Kit:RingDisc(ring, color, parent, sublevel)
	if not (ring and ring.tex and ring.object) then
		return nil
	end
	parent = parent or ring.object:GetParent()
	local disc = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel or 7)
	disc.kitPiece = true
	local c = color or { 0.16, 0.16, 0.17 }
	disc:SetColorTexture(c[1], c[2], c[3], 1)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(disc)
	disc:AddMaskTexture(mask)
	-- the disc is the class medallion's size (0.759 x the ring, user
	-- 2026-09-21), the same as a portrait fitted by Kit:FitPortrait
	local function Fit()
		local size = ring.tex:GetWidth() * MEDALLION_TO_RING
		disc:SetSize(size, size)
		disc:ClearAllPoints()
		disc:SetPoint("CENTER", ring.tex, "CENTER")
	end
	Fit()
	ring.disc = disc
	local onEnable, onDisable = ring.onEnable, ring.onDisable
	ring.onEnable = function(r)
		if onEnable then onEnable(r) end
		Fit()
		disc:Show()
	end
	ring.onDisable = function(r)
		if onDisable then onDisable(r) end
		disc:Hide()
	end
	disc:SetShown(ring.object:IsShown())
	return disc
end

-- The OUTER rail's top band: its outer (top) edge, in UI px ABOVE the
-- window's top edge (the band is grown outward by `outset`, its box top
-- measured from the piece's top). The title plate stands on it: its bottom
-- on this line (the TitleBar rule; user, 2026-09-21).
function Kit:OuterRailTop()
	local rule = self.Replacements["NineSlicePanelTemplate"]
	local prefix = rule and rule.prefix or "window/frame"
	local sc = self.scale * (rule and rule.scale or self.frameScale)
	local p = PIECES[prefix .. "_t"]
	local boxTop = (p and p.box) and p.box[2] or 0
	return ((rule and rule.outset or 0) - boxTop) * sc
end

-- The title plate riding the outer rail (the TitleBar rule's `onRail`):
-- the lift of the plate's centre above the window's top edge and how far each
-- end reaches past the rail's outer edge, so that its caps' gems sit where the
-- rail's own corner gems were, their centres on the rail's middle line.
local RAIL_GEM_IN = 20            -- the corner gems' centres, piece px in from the rail's outer corner (window/frame_gem_tl / _tr)
local CAP_GEM = { x = 48, y = 50 } -- the gem's centre in a tabs/top cap's canvas, from its outer end and its top
function Kit:TitleOnRail(strip)
	local rule = self.Replacements["NineSlicePanelTemplate"]
	local prefix = rule and rule.prefix or "window/frame"
	local sc = self.scale * (rule and rule.scale or self.frameScale)
	local rail = PIECES[prefix .. "_t"]
	local top, bottom = 0, 0
	if rail and rail.box then
		top, bottom = rail.box[2], rail.box[4]
	end
	-- the rail's middle line, above the window's top edge (the band is grown
	-- outward by `outset`, its box measured from the piece's top)
	local middle = ((rule and rule.outset or 0) - (top + bottom) / 2) * sc
	local ss = strip.scale or self.scale
	local cap = PIECES[StripName(strip.base, "cap_l", strip.state)]
	local capH = cap and cap.h or 0
	-- the gem sits below the canvas's centre: the plate's centre goes that much higher
	local lift = middle + (CAP_GEM.y - capH / 2) * ss
	local reach = CAP_GEM.x * ss - RAIL_GEM_IN * sc
	return lift, reach
end

-- The title plate and the outer rail run behind the portrait ring (user,
-- 2026-09-23: "mask the overlapping header ... the header is actually going
-- behind the Round border and icon and disappearing", then the rail's corner
-- past the ring too): Masks/ring_corner hides a round hole under the ring, a
-- little inside its body so its rim covers the cut, and the whole quarter
-- above and left of its centre (CLAMP: its top row and left column repeat
-- outward, so that quarter reaches on and all else stays shown). The ring is
-- drawn above the plate, its top gem over it, and stands as the corner.
local RING_HOLE = EDGE_ROOT .. "ring_corner"
local RING_HOLE_FILL = 62 / 64   -- the hole's radius in the mask, as a share of its half-size (Tools/make_ring_corner_mask.py)
local RING_HOLE_IN = 6           -- piece px: the cut this far inside the ring's body radius, under its rim

function Kit:FitRingHole(title, ring)
	local strip, tex = title.strip, ring.tex
	local mask = strip and strip.ringHole
	if not (mask and tex) then
		return
	end
	local ok, w = pcall(tex.GetWidth, tex)
	if not ok or Secret(w) or not (w and w > 0) then
		return
	end
	local piece = PIECES[tex.kitName or "window/portrait_ring"]
	local radius = ((piece and piece.radius) or 84) - RING_HOLE_IN
	local hole = w * radius / ((piece and piece.w) or 197)
	local size = 2 * hole / RING_HOLE_FILL
	for _, m in ipairs({ mask, title.outerCut }) do
		m:ClearAllPoints()
		m:SetPoint("CENTER", tex, "CENTER")
		m:SetSize(size, size)
	end
	-- the ring over the plate
	local holder = ring.object
	if holder and holder.SetFrameLevel and holder ~= tex then
		local level = strip:GetFrameLevel()
		if holder:GetFrameLevel() <= level then
			holder:SetFrameLevel(level + 2)
		end
	end
end

-- The portrait ring's centre, in UI px right of the window's left edge (nil
-- until both are laid out)
function Kit:RingCentreX(ring, window)
	local tex = ring and ring.tex
	if not (tex and window) then
		return nil
	end
	local okC, cx = pcall(tex.GetCenter, tex)
	local okL, left = pcall(window.GetLeft, window)
	if not (okC and okL and cx and left) or Secret(cx) or Secret(left) then
		return nil
	end
	local k = tex:GetEffectiveScale() / window:GetEffectiveScale()
	return cx * k - left
end

-- One cut of the ring's corner on a frame's textures (its own mask: a mask
-- only works on textures of the frame that made it)
local function RingCut(owner, textures)
	local mask = owner:CreateMaskTexture()
	mask:SetTexture(RING_HOLE, "CLAMP", "CLAMP")
	local seen = {}
	for _, t in ipairs(textures) do
		if t and not seen[t] and t.AddMaskTexture and t:GetParent() == owner then
			seen[t] = true
			t:AddMaskTexture(mask)
		end
	end
	return mask
end

function Kit:TitleBehindRing(title, ring, outer)
	local strip = title and title.strip
	if not (strip and ring and ring.tex and strip.CreateMaskTexture) then
		return
	end
	-- the outer rail's corner past the ring (its top and left rails, the
	-- corner, the stone under them)
	local skin = outer and outer.skin
	if skin and not title.outerCut and skin.CreateMaskTexture then
		local list = {}
		for _, t in ipairs(skin.all or {}) do
			list[#list + 1] = t
		end
		for _, t in ipairs(skin.art or {}) do
			list[#list + 1] = t
		end
		title.outerCut = RingCut(skin, list)
	end
	if not strip.ringHole then
		local mask = strip:CreateMaskTexture()
		mask:SetTexture(RING_HOLE, "CLAMP", "CLAMP")
		for _, k in ipairs({ "capL", "mid", "capR", "endL", "endR" }) do
			local t = strip[k]
			if t and t.AddMaskTexture then
				t:AddMaskTexture(mask)
			end
		end
		strip.ringHole = mask
		-- fitted again with the plate
		local refit = title.Refit
		title.Refit = function(me, ...)
			refit(me, ...)
			Kit:FitRingHole(me, ring)
		end
		-- the plate starts at the ring from now on (its Refit reads this)
		title.behindRing = ring
		if title.object and title.object:IsShown() then
			title:Refit()
			return
		end
	end
	self:FitRingHole(title, ring)
end

-- How far the window's OUTER rail grows outward past the window's edge, in
-- UI px (the NineSlicePanelTemplate rule's `outset` at its scale): two
-- windows side by side need twice this between them, or their rails overlap.
function Kit:OuterRailOutset()
	local rule = self.Replacements["NineSlicePanelTemplate"]
	if not (rule and rule.outset) then
		return 0
	end
	return rule.outset * self.scale * (rule.scale or self.frameScale)
end

-- A square rect for a slot rim whose OPENING is `iconSize` (a rim on an
-- icon that is not the button's whole rect: a 67 px ring icon, a 50 px
-- masked challenge icon): a child of `parent` centred on `center`, sized from
-- the piece's opening (rim = icon x canvas / opening), so the icon fills the
-- rim's hollow and is never squashed. `kind` is "slot" or "roundslot".
-- `into` (0..1) lets the icon run under the bezel: 0 = the icon fills the
-- hollow only, 1 = it reaches the rim's outer edge; 0.5 (the default for a
-- round icon the game rings thinly) puts the icon's edge under the middle
-- of the bezel, so the rim is smaller than icon x canvas / opening (a 67 px
-- tree icon gets an 84 px rim instead of 110, which overlapped its neighbours).
function Kit:RimRect(parent, kind, iconSize, center, into)
	local name = "buttons/" .. (kind or "slot") .. "_normal"
	local piece = PIECES[name]
	local l, r = self:Insets(name, 1)
	into = into or 0.5
	local size = iconSize * 1.35
	if piece and l then
		local opening = piece.w - l - r
		size = iconSize * piece.w / (opening + (piece.w - opening) * into)
	end
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	f:SetSize(size, size)
	f:SetPoint("CENTER", center or parent, "CENTER")
	return f
end

-- A PortraitFrameTemplate / ButtonFrameTemplate window's shell: the outer
-- rail with gem corners, the streak band, the ring on the portrait corner,
-- the title plate, the close button and the maximize / minimize pair.
--   Kit:SkinWindowShell(frame, replace, skin, { portrait = , noRing = , streaks = })
-- Returns the ring rep (skin.ring) when made.
function Kit:SkinWindowShell(frame, replace, skin, opts)
	opts = opts or {}
	if frame.NineSlice then
		-- a window whose Bg becomes the page stone (opts.bg) gets the rail
		-- WITHOUT its body: the rail's own stone tile filled the rect in a
		-- holder at the window's level, tied with the window's own stone
		-- region, and which of the two drew on top changed between loads
		-- (user, 2026-09-22: backgrounds "randomly changing between the
		-- dark and the light cracked stone"). One background per window.
		local body = opts.body
		if body == nil and opts.bg then
			body = false
		end
		replace(frame.NineSlice, { as = "NineSlicePanelTemplate", parent = frame, rect = opts.rect or frame, skip = (not opts.noRing) and "tl" or nil, body = body })
	end
	if frame.TopTileStreaks then
		replace(frame.TopTileStreaks, { as = "_UI-Frame-TopTileStreaks", parent = frame })
	end
	if frame.Bg and opts.bg then
		-- ONE picture for the whole window, inside the outer rail (the game's
		-- rock starts below the title area; a second picture for that strip
		-- met the first with a seam — user, 2026-09-21), as the Legacy pages
		replace(frame.Bg, { as = opts.bg, parent = frame, rect = frame, inset = self:OuterRailInset() })
	end
	local portrait = opts.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
	local corner = frame.NineSlice and frame.NineSlice.TopLeftCorner
	if portrait and corner and not opts.noRing then
		skin.ring = replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = frame.PortraitContainer or frame, center = portrait })
	end
	local tc = frame.TitleContainer
	if tc then
		local bg = self:FirstTexture(tc)
		if bg then
			replace(bg, { as = "TitleBar", parent = tc, rect = tc })
		else
			replace(tc, { as = "TitleBar", parent = tc, rect = tc, noFade = true })
		end
	end
	-- (the shell is registered by Kit:Replace itself, on the TOP window under
	-- UIParent: a page inside a window — the group finder's — must move its
	-- parent, which owns the close button and the side tabs; a second entry
	-- for the page here overrode that mover — user, 2026-09-21)
	local close = frame.CloseButton
	if close and close.GetNormalTexture and close:GetNormalTexture() then
		replace(close:GetNormalTexture(), { as = "RedButton-Exit", button = close, alsoFade = self:OtherTextures(close, close:GetNormalTexture()) })
	end
	-- maximize / minimize: two buttons, the game shows one at a time
	local mm = frame.MaximizeMinimizeFrame or frame.MaximizeMinimizeButton
	for _, entry in ipairs({ { mm and mm.MaximizeButton, "RedButton-Expand" }, { mm and mm.MinimizeButton, "RedButton-Condense" } }) do
		local b, key = entry[1], entry[2]
		if b and b.GetNormalTexture and b:GetNormalTexture() then
			local rep = replace(b:GetNormalTexture(), { as = key, button = b, alsoFade = self:OtherTextures(b, b:GetNormalTexture()) })
			if rep and skin.followers then
				skin.followers[#skin.followers + 1] = { rep = rep, region = b }
			end
		end
	end
	return skin.ring
end

-- The portrait fitted into the ring's opening like the class medallion
-- (0.759 x the ring, its aspect kept, on the portrait's own centre); the
-- game's size and anchors are kept on the portrait and put back by
-- Kit:UnfitPortrait. `ring` is the ring rep (skin.ring).

function Kit:FitPortrait(portrait, ring, mode)
	if not (portrait and ring and ring.tex) then
		return
	end
	if not portrait.melloSaved then
		local points = {}
		for i = 1, portrait:GetNumPoints() do
			points[i] = { portrait:GetPoint(i) }
		end
		local cx, cy = portrait:GetCenter()
		local px, py = portrait:GetParent():GetLeft(), portrait:GetParent():GetTop()
		if not (cx and px) then
			return             -- not laid out yet (the window hidden): try again on the next refresh
		end
		portrait.melloSaved = { points = points, w = portrait:GetWidth(), h = portrait:GetHeight(),
			cx = cx - px, cy = cy - py }
	end
	local saved = portrait.melloSaved
	local size = ring.tex:GetWidth() * MEDALLION_TO_RING
	if type(mode) == "number" then
		-- a factor on the medallion size. No window uses it: a window's
		-- portrait stays at the medallion size, on the disc when it does not
		-- cover the opening (WINDOW-RULES 2b; the social window's 1.3 x
		-- outgrew its ring — user, 2026-09-24)
		size = size * mode
	elseif mode == "opening" then
		-- the HUD's unit frames (user, 2026-09-21): the visible disc exactly
		-- the ring's opening — a class medallion's painted disc, else the
		-- whole (round-masked) portrait
		local piece = PIECES[ring.tex.kitName or "window/portrait_ring"]
		local openFrac = piece and piece.open and (piece.open[3] - piece.open[1]) / piece.w or 0.61
		local okT, file = pcall(portrait.GetTexture, portrait)
		local medallion = okT and type(file) == "string" and file:find("MelloUI", 1, true) ~= nil
		size = ring.tex:GetWidth() * openFrac / (medallion and MEDALLION_DISC or 1)
	end
	local w, h = saved.w, saved.h
	if size > 0 and saved.cx and w > 0 and h > 0 then
		local k = size / math.max(w, h)
		portrait:ClearAllPoints()
		portrait:SetPoint("CENTER", portrait:GetParent(), "TOPLEFT", saved.cx, saved.cy)
		portrait:SetSize(w * k, h * k)
	end
end

function Kit:UnfitPortrait(portrait)
	local saved = portrait and portrait.melloSaved
	if saved then
		portrait:ClearAllPoints()
		for _, pt in ipairs(saved.points) do
			portrait:SetPoint(unpack(pt))
		end
		portrait:SetSize(saved.w, saved.h)
		portrait.melloSaved = nil
	end
end

--------------------------------------------------------------------------------
-- Side tabs (user, 2026-09-23: "all Category Side Tab Buttons should be
-- mimicing the same size and appearence as the ones on the Character Pane and
-- Vice Versa, setting the Character Pane as the Default"): every
-- common-sidetab replacement is registered here. A tab of another window is
-- given the Character window's tab size (the button itself, so it grows the
-- way the game anchors it and its neighbours follow; the rim on it, the icon
-- fitted again); every tab wears one Side Tab Border (UI Modifications'
-- `sideTabBorder`: "slot" the Character window's gem slot, else a thin rim
-- look), changed on all of them at once.
--------------------------------------------------------------------------------

Kit.sideTabLooks = {
	{ value = "slot", label = "Gem slot", piece = "buttons/slot_checked" },
	{ value = "rim", label = "Thin iron", piece = "buttons/rim_checked" },
	{ value = "rimhair", label = "Hairline", piece = "buttons/rimhair_checked" },
	{ value = "rimround", label = "Rounded corners", piece = "buttons/rimround_checked" },
	{ value = "rimgold", label = "Iron with gold line", piece = "buttons/rimgold_checked" },
	{ value = "rimsunk", label = "Sunk", piece = "buttons/rimsunk_checked" },
}
local SIDE_TAB_FALLBACK = 48       -- UI px, until the Character window's tab can be measured
local SIDE_TAB_SCALE = 0.8         -- the rims 20 % smaller than the Character window's tab (user, 2026-09-23: "scale down their border by 20%"), the icons filling them
local sideTabs = {}                -- { tab, rep, reference, saved = { w, h } }

-- The Character window's side tab: its size is every side tab's
local function IsReferenceTab(tab)
	local name = tab and tab.GetName and tab:GetName()
	return name and name:find("^CharacterFrameModeTab%d") ~= nil
end

function Kit:SideTabSize()
	-- the size of the rim it shows: its Background's (the rim's rect there)
	local tab = _G.CharacterFrameModeTab1
	local ref = tab and (tab.Background or tab)
	if ref then
		local ok, w, h = pcall(ref.GetSize, ref)
		if ok and w and h and not Secret(w) and not Secret(h) and w > 1 and h > 1 then
			return w, h
		end
	end
	return SIDE_TAB_FALLBACK, SIDE_TAB_FALLBACK
end

local function SideTabBase()
	local um = MelloUI:GetModule("UIModifications")
	local value = um and um.db and um.db.sideTabBorder or "slot"
	for _, look in ipairs(Kit.sideTabLooks) do
		if look.value == value then
			return "buttons/" .. value
		end
	end
	return "buttons/slot"
end

-- The look on one tab's rim (its glow is its checked look, drawn additively)
local function SideTabLook(entry)
	local rim = entry.rep and entry.rep.object
	if not (rim and rim.base) then
		return
	end
	local base = SideTabBase()
	Kit:SetSlotBase(rim, base)
	if rim.glow and PIECES[base .. "_checked"] then
		Kit:Apply(rim.glow, base .. "_checked")
	end
end

-- The side of its window a tab hangs on ("right" / "left")
local function TabSide(tab)
	local window = tab
	while window:GetParent() and window:GetParent() ~= UIParent do
		window = window:GetParent()
	end
	local ok, tx, wx = pcall(function() return (tab:GetCenter()), (window:GetCenter()) end)
	if ok and tx and wx and not Secret(tx) and not Secret(wx) then
		return tx >= wx and "right" or "left"
	end
	return "right"
end

-- A tab at the Character window's size (another window's button set to it,
-- put back on disable), its rim SIDE_TAB_SCALE x that size, growing away
-- from the window: its window-side edge on the tab's, centred up and down
local function SideTabSize(entry, on)
	local tab, rim = entry.tab, entry.rep and entry.rep.object
	if not (tab and tab.SetSize and rim) then
		return
	end
	local w, h = Kit:SideTabSize()
	local anchor = entry.reference and (tab.Background or tab) or tab
	if on then
		if not entry.reference then
			if not entry.saved then
				local ok, sw, sh = pcall(tab.GetSize, tab)
				if not (ok and sw and sh) or Secret(sw) or Secret(sh) then
					return
				end
				entry.saved = { sw, sh }
			end
			tab:SetSize(w, h)
		end
		local side = TabSide(tab)
		rim:ClearAllPoints()
		if side == "right" then
			rim:SetPoint("LEFT", anchor, "LEFT", 0, 0)
		else
			rim:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
		end
		rim:SetSize(w * SIDE_TAB_SCALE, h * SIDE_TAB_SCALE)
	elseif entry.saved then
		tab:SetSize(entry.saved[1], entry.saved[2])
	end
	if rim.icon then
		Kit:SlotPlaceIcon(rim)
	end
end

-- The Character window's painted side-tab icons (INV_SideTab_*_c60, tabs 2
-- on) are drawn for the game's tab shape: a clipped corner and a transparent
-- strip down their right side, which the game hides by nudging them left. In
-- the square rim that strip showed the world through the opening (user,
-- 2026-09-23, painted blue on a screenshot): cropped away, the art keeping
-- its aspect (the top and bottom trimmed by the same share); measured on the
-- reputation tab's icon, the art ends at 0.89 of its width, so the icon
-- fills the rim to its inner edge (no backing behind it: user, 2026-09-23,
-- "dont add a background, resize the buttons to fit the borders"). The
-- game's own coordinates (UpdateIconInterior) come back on disable.
local SIDE_TAB_ICON_CROP = { 0.03125, 0.866, 0.0828, 0.9172 }
local SIDE_TAB_ICON_GAME = { 0.03125, 0.96875, 0.03125, 0.96875 }

local function SideTabIcon(entry, on)
	local rim = entry.rep and entry.rep.object
	local icon = rim and rim.icon
	if not icon then
		return
	end
	if not entry.crop then
		return
	end
	if not entry.cropHooked then
		entry.cropHooked = true
		hooksecurefunc(icon, "SetTexCoord", function(self)
			if entry.cropping or not (entry.rep.object and entry.rep.object:IsShown()) then
				return
			end
			entry.cropping = true
			self:SetTexCoord(unpack(SIDE_TAB_ICON_CROP))
			entry.cropping = nil
		end)
	end
	entry.cropping = true
	icon:SetTexCoord(unpack(on and SIDE_TAB_ICON_CROP or SIDE_TAB_ICON_GAME))
	entry.cropping = nil
end

function Kit:RegisterSideTab(rep, tab)
	if not (rep and tab) then
		return
	end
	local entry = { tab = tab, rep = rep, reference = IsReferenceTab(tab) }
	entry.crop = entry.reference and tab.GetID and tab:GetID() ~= 1   -- tab 1 is the character's portrait
	sideTabs[#sideTabs + 1] = entry
	local enable, disable = rep.Enable, rep.Disable
	rep.Enable = function(self, ...)
		enable(self, ...)
		SideTabLook(entry)
		SideTabSize(entry, true)
		SideTabIcon(entry, true)
	end
	rep.Disable = function(self, ...)
		disable(self, ...)
		SideTabSize(entry, false)
		SideTabIcon(entry, false)
	end
	SideTabLook(entry)
	if rep.object and rep.object:IsShown() then
		SideTabSize(entry, true)
		SideTabIcon(entry, true)
	end
end

-- Side Tab Border changed: every registered tab at once
function Kit:SetSideTabBorder()
	for _, entry in ipairs(sideTabs) do
		SideTabLook(entry)
	end
end

--------------------------------------------------------------------------------
-- Borders for every window, one choice per kind (user, 2026-09-23: "Progress
-- bar Borders, Nameplate Borders, ... should all be selectable from 1
-- Dropdown menu and reflect on the connected action bars like the Character
-- Side Panel Tab Borders"; one dropdown per kind). UI Modifications keeps
-- the settings; every element of a kind is registered as it is skinned and
-- takes the kind's look, and a new choice goes to all of them at once
-- (Kit:ApplyBorder). Panels that fit something round a border (a bar's
-- fill, the spell book's rims) listen with Kit:OnBorderChanged.
--   button     the square rims of the action bars, micro menu, bag bar, bags,
--              gear slots and spells (the thin looks)
--   sidetab    every window's side tabs and the spell book's category tabs
--   bar        every progress bar's bracket (character, professions, legacy,
--              guild, experience, tracker, tooltip, damage meter, unit frames)
--   nameplate  the nameplates' health bar bracket
--------------------------------------------------------------------------------

-- the round rims' looks (Tools/build_kit.py thin_ring; no rounded-corners
-- ring: a ring is round already) and the auras' (the plain black edge they
-- had, or a thin rim)
Kit.roundLooks = {
	{ value = "roundslot", label = "Gem ring", piece = "buttons/roundslot_normal" },
	{ value = "roundrim", label = "Thin iron", piece = "buttons/roundrim_normal" },
	{ value = "roundrimhair", label = "Hairline", piece = "buttons/roundrimhair_normal" },
	{ value = "roundrimgold", label = "Iron with gold line", piece = "buttons/roundrimgold_normal" },
	{ value = "roundrimsunk", label = "Sunk", piece = "buttons/roundrimsunk_normal" },
}
Kit.auraLooks = { { value = "black", label = "Plain black edge" } }
for _, v in ipairs(Kit.buttonLooks.borders) do
	Kit.auraLooks[#Kit.auraLooks + 1] = v
end

Kit.borderKinds = {
	{ kind = "button", key = "buttonBorder", default = "thin", name = "Button Border", values = Kit.buttonLooks.borders, preview = "rim",
	  desc = "The rim on every square button: the action bars, the micro menu, the bag bar, your bags, the equipment slots and the spell book's spells." },
	{ kind = "sidetab", key = "sideTabBorder", default = "slot", name = "Side Tab Border", values = Kit.sideTabLooks, preview = "rim",
	  desc = "The rim on every window's side tabs and the spell book's category tabs, all at the character window's size." },
	{ kind = "bar", key = "barBorder", default = "frame", name = "Progress Bar Border", values = Kit.buttonLooks.barBorders, preview = "bar",
	  desc = "The frame round every progress bar: reputation and skills, the professions' ranks, legacy, guild, experience, the tracker's, the tooltip's, the damage meter's and the unit frames' bars." },
	{ kind = "nameplate", key = "nameplateBorder", default = "frame", name = "Nameplate Border", values = Kit.buttonLooks.barBorders, preview = "bar",
	  desc = "The frame round the nameplates' health bars." },
	{ kind = "round", key = "roundBorder", default = "roundslot", name = "Round Border", values = Kit.roundLooks, preview = "rim",
	  desc = "The rim round every round icon: passive spells, the legacy, guild and group finder windows' rings, the auction house's item, the Services bar's round buttons." },
	{ kind = "aura", key = "auraBorder", default = "thin", name = "Aura Border", values = Kit.auraLooks, preview = "rim",
	  desc = "The rim round your buffs and debuffs, the target's and the nameplates' (Buffs & Debuffs): a plain black edge or one of the thin rims the buttons wear. The debuff colour stays round the icon." },
	{ kind = "colours", key = "kitColours", default = "warm", name = "Kit Colours", values = Kit.colourLooks,
	  desc = "The colours of all the painted art (frames, headers, rows, buttons, slots, bars) in the interface's palette: Warm iron (the metal in warm browns), Bronze (warm browns with gold bevels), or the Original painted grey iron and bright red. Pictures keep their own colours." },
}
local BORDER_KIND = {}
for _, k in ipairs(Kit.borderKinds) do
	BORDER_KIND[k.kind] = k
end

function Kit:BorderValue(kind)
	local k = BORDER_KIND[kind]
	if not k then
		return nil
	end
	local um = MelloUI:GetModule("UIModifications")
	local v = um and um.db and um.db[k.key]
	return v or k.default
end

local buttonRims = setmetatable({}, { __mode = "k" })   -- [button] = true: a skinned button whose rim is a thin look
local borderBars = { bar = setmetatable({}, { __mode = "k" }), nameplate = setmetatable({}, { __mode = "k" }) }
local borderListeners = {}                                -- [kind] = { fn, ... }

function Kit:RegisterButtonRim(button)
	if button then
		buttonRims[button] = true
		self:SetButtonBorder(button, self:BorderValue("button"))
	end
end

function Kit:RegisterBorderBar(group, rep)
	if borderBars[group] and rep then
		borderBars[group][rep] = true
	end
end

function Kit:OnBorderChanged(kind, fn)
	borderListeners[kind] = borderListeners[kind] or {}
	table.insert(borderListeners[kind], fn)
end

-- every round rim (Kit:Slot with kind "roundslot"), for Round Border
Kit.roundRims = setmetatable({}, { __mode = "k" })

-- A round rim in a look (its glow, the lit look, too)
local function RoundLook(rim, value)
	local base = "buttons/" .. value
	if not PIECES[base .. "_normal"] then
		return
	end
	Kit:SetSlotBase(rim, base)
	if rim.glow then
		local look = rim.restState or (PIECES[base .. "_checked"] and "checked") or "hover"
		Kit:Apply(rim.glow, base .. "_" .. look)
	end
end

-- A kind's choice to every element of it
function Kit:ApplyBorder(kind)
	local value = self:BorderValue(kind)
	if kind == "colours" then
		self:SetKitColours(value)
	elseif kind == "round" then
		for rim in pairs(self.roundRims) do
			RoundLook(rim, value)
		end
	elseif kind == "button" then
		for button in pairs(buttonRims) do
			self:SetButtonBorder(button, value)
		end
	elseif kind == "sidetab" then
		self:SetSideTabBorder()
	elseif borderBars[kind] then
		for rep in pairs(borderBars[kind]) do
			if rep.SetBar then
				rep:SetBar(value)
				if rep.onBarChanged then
					pcall(rep.onBarChanged, rep)
				end
			end
		end
	end
	for _, fn in ipairs(borderListeners[kind] or {}) do
		pcall(fn, value)
	end
end

-- A large side tab (SidePanelTabButtonMixin: Background common-sidetab, Icon,
-- SelectedTexture / TabGlow / HighlightTexture): the gold rim with the icon
-- fitted in, the glow while `checked()` (default: the game's SelectedTexture shown).
function Kit:SkinSideTab(tab, replace, checked)
	if not (tab and tab.Background) or tab.melloRep ~= nil then
		return tab and tab.melloRep or nil
	end
	tab.melloRep = replace(tab.Background, { as = "common-sidetab", button = tab, parent = tab, icon = tab.Icon,
		checked = checked or function() return tab.SelectedTexture and tab.SelectedTexture:IsShown() end,
		alsoFade = { tab.SelectedTexture, tab.TabGlow, tab.HighlightTexture } }) or false
	return tab.melloRep or nil
end

-- A list header's collapse button (CollapseButtonTemplate: an Icon the game
-- re-atlases with the state, an additive highlight copy): the +/- plate on
-- the glyph's rect, one per atlas seen. Call again after the game's
-- UpdateCollapsedState (or post-hook it).
function Kit:SkinCollapseButton(button, replace)
	if not (button and button.Icon) then
		return
	end
	local extra = {}
	for _, region in ipairs({ button:GetRegions() }) do
		if region ~= button.Icon and region:GetObjectType() == "Texture" and not region.kitPiece then
			extra[#extra + 1] = region
		end
	end
	self:StateIconReps(button, button.Icon, button, replace, extra)
end

-- A search box (SearchBoxTemplate): the edit plate with its glass cap in
-- place of the game's icon; the text and instructions start past the cap.
function Kit:SkinSearchBox(search, replace)
	if not (search and search.Middle) or search.melloRep ~= nil then
		return search and search.melloRep or nil
	end
	local rep = replace(search.Middle, { as = "common-search-border-middle", rect = search, edit = search,
		alsoFade = { search.Left, search.Right, search.searchIcon } })
	search.melloRep = rep or false
	if not rep then
		return nil
	end
	local l, r, t, b = search:GetTextInsets()
	local instr = search.Instructions
	local points = {}
	if instr then
		for i = 1, instr:GetNumPoints() do
			points[i] = { instr:GetPoint(i) }
		end
	end
	rep.onEnable = function()
		local capW = (rep.strip.wl or 0) * 0.45
		search:SetTextInsets(capW, r, t, b)
		if instr then
			instr:ClearAllPoints()
			instr:SetPoint("TOPLEFT", search, "TOPLEFT", capW, 0)
			instr:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", -20, 0)
		end
	end
	rep.onDisable = function()
		search:SetTextInsets(l, r, t, b)
		if instr then
			instr:ClearAllPoints()
			for _, pt in ipairs(points) do
				instr:SetPoint(unpack(pt))
			end
		end
	end
	return rep
end

-- A text button on the red plate (B1): a UIPanelButtonTemplate (Left /
-- Middle / Right file pieces) or a 128-RedButton three-slice (Center).
function Kit:SkinRedButton(button, replace, opts)
	if not button or button.melloRep ~= nil then
		return button and button.melloRep or nil
	end
	opts = opts or {}
	local anchor, key, extra
	if button.Center then
		anchor, key = button.Center, "_128-RedButton-Center"
		extra = { button.Left, button.Right }
	elseif button.Middle then
		anchor, key = button.Middle, "UI-Panel-Button-Up"
		extra = { button.Left, button.Right }
	end
	if not anchor then
		button.melloRep = false
		return nil
	end
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= anchor and region ~= button.Left and region ~= button.Right
			and not region.kitPiece and region:GetDrawLayer() == "HIGHLIGHT" then
			extra[#extra + 1] = region
		end
	end
	button.melloRep = replace(anchor, { as = key, rect = button, button = button, alsoFade = extra, dropCap = opts.dropCap, capless = opts.capless }) or false
	return button.melloRep or nil
end

-- A check button (CheckButton with the minimal or the classic check box
-- art): the kit's check box off / on / hover on its normal texture's rect.
function Kit:SkinCheckButton(cb, replace, key)
	if not (cb and cb.GetNormalTexture and cb:GetNormalTexture()) or cb.melloRep ~= nil then
		return cb and cb.melloRep or nil
	end
	local normal = cb:GetNormalTexture()
	cb.melloRep = replace(normal, { as = key or "checkbox-minimal", button = cb, rect = normal,
		alsoFade = { cb:GetPushedTexture(), cb:GetCheckedTexture(), cb:GetHighlightTexture(), cb:GetDisabledTexture() } }) or false
	return cb.melloRep or nil
end

-- P1 on a StatusBar whose bracket art is one of its own textures (`frame`,
-- e.g. LegacyProgressBarTemplate's ProgressBarFrame) and whose background
-- (`bg`) is a texture of the parent the bar is anchored to: the bracket and
-- trough become regions of the bar's frame on the background's rect, the
-- background and the game's bracket are faded, and the StatusBar itself is
-- moved into the opening (its fill spans the bracket's whole height, behind
-- the rails), put back on disable. `key` is the mapping (the bracket's atlas).
function Kit:SkinStatusBar(bar, frame, bg, replace, key)
	if not (bar and frame and bg) or bar.melloRep ~= nil then
		return bar and bar.melloRep or nil
	end
	local rep = replace(frame, { as = key or self:ArtKey(frame), rect = bg, parent = bar, alsoFade = { bg } })
	bar.melloRep = rep or false
	if not rep then
		return nil
	end
	local saved = {}
	for i = 1, bar:GetNumPoints() do
		saved[i] = { bar:GetPoint(i) }
	end
	rep.onEnable = function()
		rep:Refit()
		local l, r, t, b = rep:GetOpening()
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", bg, "TOPLEFT", l, -t)
		bar:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -r, b)
	end
	rep.onDisable = function()
		bar:ClearAllPoints()
		for _, pt in ipairs(saved) do
			bar:SetPoint(unpack(pt))
		end
	end
	return rep
end

-- A PanelTabButtonTemplate / TabSystem tab (Left / Middle / Right plain,
-- LeftActive / MiddleActive / RightActive open; the game shows one set):
-- T1, one plate per set on the tab's rect, following the game's Show / Hide.
function Kit:SkinPanelTab(tab, replace, skin)
	if not (tab and tab.Left and tab.LeftActive) or tab.melloRep ~= nil then
		return
	end
	tab.melloRep = false
	local plain = replace(tab.Left, { as = "uiframe-tab-left", rect = tab, button = tab, alsoFade = { tab.Middle, tab.Right, tab.LeftHighlight, tab.MiddleHighlight, tab.RightHighlight } })
	local open = replace(tab.LeftActive, { as = "uiframe-activetab-left", rect = tab, alsoFade = { tab.MiddleActive, tab.RightActive } })
	tab.melloRep = plain or open or false
	if skin and skin.followers then
		if plain then
			skin.followers[#skin.followers + 1] = { rep = plain, region = tab.Left }
		end
		if open then
			skin.followers[#skin.followers + 1] = { rep = open, region = tab.LeftActive }
		end
	end
	-- the game hides the plain set and shows the active one on select
	for _, region in ipairs({ tab.Left, tab.LeftActive }) do
		hooksecurefunc(region, "Show", function()
			if plain then plain:SetShown(tab.Left:IsShown()) end
			if open then open:SetShown(tab.LeftActive:IsShown()) end
		end)
		hooksecurefunc(region, "Hide", function()
			if plain then plain:SetShown(tab.Left:IsShown()) end
			if open then open:SetShown(tab.LeftActive:IsShown()) end
		end)
	end
	if plain then plain:SetShown(tab.Left:IsShown()) end
	if open then open:SetShown(tab.LeftActive:IsShown()) end
	-- the game bobs the tab's text on select / deselect (a few px up and
	-- down, to sit on its own tab art); on the kit's plate it stays put,
	-- centred on the plate's painted box (user, 2026-09-21). Re-applied
	-- after each of the game's SetPoint calls on the text, only while a
	-- plate is on.
	local text = tab.Text
	local rep = plain or open
	if text and rep then
		local function Steady()
			if tab.melloSteadying or not (rep.object:IsShown() or (open and open.object:IsShown())) then
				return
			end
			tab.melloSteadying = true
			local dy = 0
			if rep.strip then
				local mid = PIECES[StripName(rep.strip.base, "mid", rep.strip.state)]
				if mid and mid.box then
					dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (rep.strip.scale or Kit.scale)
				end
			end
			local okP, _, _, _, x = pcall(text.GetPoint, text, 1)
			text:SetPoint("CENTER", tab, "CENTER", (okP and x) or 0, dy)
			tab.melloSteadying = nil
		end
		hooksecurefunc(text, "SetPoint", Steady)
		Steady()
	end
end

-- An InsetFrameTemplate (a marble Bg, a NineSlice at the frame's own level):
-- the single rail, edges only, on a holder at the inset's own level under
-- `parent` (over any list rows the inset frames), the inset faded.
-- `withBody`: the inset filled with the list-box stone (the palette's Inner
-- Panel, a panel sunk into the window) instead of showing the page through it:
-- a list whose text must read (user, 2026-09-23: the social window's lists on
-- the page's cracked stone were "not readable")
function Kit:SkinInset(inset, replace, parent, withBody)
	if not inset or inset.melloRep ~= nil then
		return
	end
	parent = parent or inset:GetParent()
	local ok, a, b = pcall(function() return inset:GetFrameLevel(), parent:GetFrameLevel() end)
	local level = (ok and a and b) and math.max(a - b, 1) or 1
	-- only the inset's ART is faded (its nine-slice pieces and marble), never
	-- the frame: an inset may hold content (the wardrobe's slots and models)
	local extra = { inset.Bg }
	if inset.NineSlice then
		for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
			if region:GetObjectType() == "Texture" then
				extra[#extra + 1] = region
			end
		end
	end
	inset.melloRep = replace(inset, { as = "common-insideframe", parent = parent, rect = inset, level = level, body = withBody and true or false, noFade = true, alsoFade = extra }) or false
end

-- The controls every window has, found by what they ARE under `root` (a
-- window, a page): search boxes, red buttons, check boxes, dropdowns, panel
-- tabs, insets, scroll bars — each to its fixed look. `skip` frames are not
-- walked into (a map canvas). The game's own icons and pictures are left.
function Kit:SweepControls(root, replace, skin, skip, depth)
	depth = depth or 0
	if not root or depth > 8 or root == skip or root == skin then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		local kind = child:GetObjectType()
		if child.Track and child.Track.Thumb and child.Back and child.Forward then
			self:SkinScrollBar(child, replace)
		elseif kind == "EditBox" and child.Middle and child.searchIcon then
			self:SkinSearchBox(child, replace)
		elseif child.Left and child.LeftActive and child.Middle then
			self:SkinPanelTab(child, replace, skin)
		elseif kind == "Button" and (child.Center or (child.Left and child.Middle and child.Right)) and child:GetFontString() and child:GetFontString():GetText()
			and not child.Icon and not child.Background and not child.CollapsedIcon and not (root.LayoutColumns) then
			-- (a column display's header buttons have the same Left / Middle /
			-- Right shape but are the window's to map: GC1, not B1)
			self:SkinRedButton(child, replace)
		elseif kind == "CheckButton" and child.GetCheckedTexture and child:GetCheckedTexture() and child:GetCheckedTexture():GetTexture()
			and not child.Icon and not child.Ring and (child:GetWidth() <= 40 or child:GetWidth() == 0) and child.melloRep == nil then
			local normal = child.GetNormalTexture and child:GetNormalTexture()
			local key = normal and self:ArtKey(normal)
			self:SkinCheckButton(child, replace, (key and self:RuleFor(key)) and key or "UI-CheckBox-Up")
		elseif child.Background and child.Arrow and child.Text and child.melloRep == nil then
			child.melloRep = replace(child.Background, { as = "common-dropdown-textholder", rect = child, button = child, alsoFade = { child.Arrow } }) or false
		elseif child.Background and child.Text and self:ArtKey(child.Background) == "common-dropdown-b-button" and child.melloRep == nil then
			child.melloRep = replace(child.Background, { as = "common-dropdown-b-button", rect = child, button = child, parent = child }) or false
		elseif child.NineSlice and child.Bg and (child.layoutType == "InsetFrameTemplate" or child.NineSlice.layoutType == "InsetFrameTemplate"
			or (child.NineSlice.TopLeftCorner and tostring(self:ArtKey(child.NineSlice.TopLeftCorner)):find("^UI%-Frame%-Inner"))) then
			self:SkinInset(child, replace, root)
		end
		if not (child.Track and child.Track.Thumb) then
			self:SweepControls(child, replace, skin, skip, depth + 1)
		end
	end
end

-- A list's rows as they are acquired by a WowScrollBoxList (and the ones it
-- already holds): `rowSkin(frame)` once per row, guarded by the panel.
-- `initialized`: call `rowSkin` after the row's own Init instead (a pool
-- whose frames serve as header AND row: the look is known only then).
function Kit:HookScrollBoxRows(scrollBox, rowSkin, isActive, initialized)
	if not (scrollBox and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) or scrollBox.melloKitHooked then
		return
	end
	scrollBox.melloKitHooked = true
	local add = (initialized and ScrollUtil.AddInitializedFrameCallback) or ScrollUtil.AddAcquiredFrameCallback
	add(scrollBox, function(_, frame)
		if isActive() then
			rowSkin(frame)
		end
	end, scrollBox, false)
	if scrollBox.ForEachFrame then
		scrollBox:ForEachFrame(function(frame)
			if isActive() then
				rowSkin(frame)
			end
		end)
	end
end

-- The dump every window module offers (/xxdump): the visible game textures
-- under `root` (art name, rect, layer), "frames" (the tree with strata and
-- levels), "reps" (ours), or `extra(msg)` for the module's own modes.
function Kit:DumpWindow(root, skin, msg, extra)
	local function Rect(label, f, more)
		local ok, l, b, w, h = pcall(function() return f:GetRect() end)
		if ok and l and not Secret(l) then
			MelloUI:Print("%-44s x=%.0f y=%.0f w=%.0f h=%.0f %s", label, l, b, w, h, more or "")
		else
			MelloUI:Print("%-44s (no rect) %s", label, more or "")
		end
	end
	-- a pooled entry's name can read secret on this client (the damage
	-- meter's rows): printed as such, never handed to format
	local function Name(obj)
		local ok, n = pcall(obj.GetName, obj)
		if ok and n and not Secret(n) then
			return n
		end
		local okD, d = pcall(obj.GetDebugName, obj)
		if okD and d and not Secret(d) then
			return d
		end
		return "[secret name]"
	end
	if extra and extra(msg, Rect, Name) then
		return
	end
	if msg == "frames" then
		local function walk(frame, depth)
			if depth > 6 or frame == skin then
				return
			end
			MelloUI:Print("%s%s  %s L%d%s", string.rep("  ", depth), Name(frame), frame:GetFrameStrata(), frame:GetFrameLevel(), frame:IsShown() and "" or " (hidden)")
			for _, child in ipairs({ frame:GetChildren() }) do
				walk(child, depth + 1)
			end
		end
		walk(root, 0)
		return
	end
	if msg == "reps" then
		if not skin then
			MelloUI:Print("No skin built.")
			return
		end
		for i, rep in ipairs(skin.reps) do
			local more = rep.object:IsShown() and "shown" or "hidden"
			if rep.kind == "picture" and rep.tex then
				local okV, vis = pcall(rep.tex.IsVisible, rep.tex)
				local ok, u1, _, _, _, _, _, u2, v2 = pcall(rep.tex.GetTexCoord, rep.tex)
				local okS, w, h = pcall(rep.inner.GetSize, rep.inner)
				more = string.format("%s visible=%s inner=%sx%s uv=%s..%s,%s piece=%s", more, okV and tostring(vis) or "?",
					okS and string.format("%.0f", w) or "?", okS and string.format("%.0f", h) or "?",
					ok and string.format("%.2f", u1) or "?", ok and string.format("%.2f", u2) or "?", ok and string.format("%.2f", v2) or "?", tostring(rep.tex.kitName))
			end
			if rep.strip then
				-- a strip's fit: its scale, the caps' widths as laid out and
				-- the cap decisions (a plate that lost its caps shows why)
				local st = rep.strip
				more = string.format("%s scale=%.3f wl=%.1f wr=%.1f%s%s%s%s", more, st.scale or 0, st.wl or 0, st.wr or 0,
					st.capless and " CAPLESS" or "", st.dropCap and (" drop=" .. tostring(st.dropCap)) or "",
					st.endL and " endL" or "", st.endR and " endR" or "")
			end
			Rect(string.format("%d %s (%s)", i, rep.key, rep.kind), rep.rect, more)
			local piece = rep.tex or (rep.strip and rep.strip.mid) or nil
			if piece and piece ~= rep.rect then
				Rect("     piece", piece)
			end
			if rep.strip then
				Rect("     cap_l", rep.strip.capL, rep.strip.capL:IsShown() and "shown" or "hidden")
				Rect("     cap_r", rep.strip.capR, rep.strip.capR:IsShown() and "shown" or "hidden")
			end
		end
		return
	end
	local n = 0
	local function walk(frame, depth)
		if depth > 9 or frame == skin then
			return
		end
		for _, region in ipairs({ frame:GetRegions() }) do
			-- shown / alpha / layer can all read secret on a nameplate's
			-- regions (the cast bar's target indicator, user 2026-09-22)
			local okV, visible = pcall(region.IsVisible, region)
			if region:GetObjectType() == "Texture" and not region.kitPiece and okV and not Secret(visible) and visible then
				local ok, alpha = pcall(region.GetAlpha, region)
				if ok and alpha and not Secret(alpha) and alpha > 0 then
					n = n + 1
					local okL, layer, sub = pcall(region.GetDrawLayer, region)
					if not okL or Secret(layer) or Secret(sub) then
						layer, sub = "?", "?"
					end
					Rect(string.format("%d %s/%s", n, Name(frame), region:GetName() or region.kitName or region:GetDebugName()), region,
						string.format("%s/%s art=%s", tostring(layer), tostring(sub), tostring(self:ArtKey(region))))
				end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			walk(child, depth + 1)
		end
	end
	walk(root, 0)
	MelloUI:Print("%d visible game textures", n)
end

--------------------------------------------------------------------------------
-- /kitdemo [scale]: one window with every block, to check the art in the client.
--------------------------------------------------------------------------------

local demo

local function BuildDemo(scale)
	scale = scale or Kit.scale
	local f = CreateFrame("Frame", "MelloUIKitDemo", UIParent)
	f:SetSize(640, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)

	local skin = Kit:NineSlice(f, { scale = scale, gems = true, ornament = true })
	local T = Kit:NineSliceInset(skin)

	-- everything else lives above the skin
	local c = CreateFrame("Frame", nil, f)
	c:SetAllPoints(f)
	c:SetFrameLevel(f:GetFrameLevel() + 4)

	-- title plate hanging on the top edge, close button in the corner
	local title = Kit:Strip(c, "window/title", { width = 260, scale = scale })
	title:SetPoint("TOP", f, "TOP", 0, T * 0.6)
	local titleText = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleText:SetPoint("CENTER", title, "CENTER", 0, 0)
	titleText:SetText("MelloUI kit  " .. string.format("%.3f", scale))

	local close = CreateFrame("Button", nil, c)
	close:SetSize(Kit:Size("window/close_normal", scale))
	close:SetPoint("TOPRIGHT", -T * 0.4, -T * 0.4)
	Kit:StateTexture(close, "window/close", { scale = scale })
	close:SetScript("OnClick", function() f:Hide() end)

	local ring = Kit:Texture(c, "window/portrait_ring", "ARTWORK", 3, scale)
	ring:SetPoint("TOPLEFT", -T * 0.2, T * 0.2)

	local y = -(T + 30)
	local x = T + 20

	-- text buttons
	local btn = Kit:Strip(c, "buttons/textbtn", { width = 180, scale = scale, state = "normal" })
	btn:SetPoint("TOPLEFT", x, y)
	local red = Kit:Strip(c, "buttons/redbtn", { width = 140, scale = scale, state = "hover" })
	red:SetPoint("LEFT", btn, "RIGHT", 12, 0)
	local dis = Kit:Strip(c, "buttons/textbtn", { width = 120, scale = scale, state = "disabled" })
	dis:SetPoint("LEFT", red, "RIGHT", 12, 0)
	y = y - btn.height - 12

	-- bars with a StatusBar in the opening
	for i, kind in ipairs({ "frame", "castbar" }) do
		local bar = Kit:Bar(c, { kind = kind, width = 420, scale = scale })
		bar:SetPoint("TOPLEFT", x, y)
		local sb = CreateFrame("StatusBar", nil, bar.fill)
		sb:SetAllPoints()
		sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		sb:SetStatusBarColor(i == 1 and 0.75 or 0.85, i == 1 and 0.12 or 0.65, 0.12)
		sb:SetMinMaxValues(0, 1)
		sb:SetValue(i == 1 and 0.62 or 0.4)
		y = y - bar.height - 8
	end

	-- list rows and tabs
	for _, state in ipairs({ "plain", "hover", "selected" }) do
		local row = Kit:Strip(c, "lists/row", { width = 300, scale = scale, state = state })
		row:SetPoint("TOPLEFT", x, y)
		local txt = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		txt:SetPoint("LEFT", row, "LEFT", row:GetInsets() + 4, 0)
		txt:SetText("list row " .. state)
		y = y - row.height + 2 * scale
	end
	y = y - 10
	local tabPlain = Kit:Strip(c, "tabs/top", { width = 110, scale = scale, state = "plain" })
	tabPlain:SetPoint("TOPLEFT", x, y)
	local tabOpen = Kit:Strip(c, "tabs/top", { width = 110, scale = scale, state = "open" })
	tabOpen:SetPoint("LEFT", tabPlain, "RIGHT", 6, 0)
	local edit = Kit:Strip(c, "inputs/edit", { width = 160, scale = scale, state = "focused" })
	edit:SetPoint("LEFT", tabOpen, "RIGHT", 12, 0)

	-- icon slots on the right, with a spell icon under the rim
	local sx = 640 - T - 20
	local sy = -(T + 30)
	local size = Kit:Size("buttons/slot_normal", scale)
	for i, kind in ipairs({ "slot", "slot", "roundslot" }) do
		local b = CreateFrame(i == 2 and "CheckButton" or "Button", nil, c)
		b:SetSize(size, size)
		b:SetPoint("TOPRIGHT", sx, sy)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		if kind == "roundslot" then
			icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		end
		Kit:Slot(b, { kind = kind, icon = icon, scale = scale })
		if i == 2 then
			b:SetChecked(true)
		end
		sy = sy - size - 8
	end

	-- small buttons
	local small = { "buttons/cog", "buttons/arrow_up", "buttons/arrow_down", "buttons/checkbox", "buttons/plus", "buttons/minus", "buttons/orb" }
	local px = sx
	for _, base in ipairs(small) do
		local first = Kit:FirstStateOf(base) and (base .. "_" .. Kit:FirstStateOf(base)) or nil
		if first then
			local b = CreateFrame(base == "buttons/checkbox" and "CheckButton" or "Button", nil, c)
			b:SetSize(Kit:Size(first, scale))
			b:SetPoint("TOPRIGHT", px, sy)
			Kit:StateTexture(b, base, { scale = scale })
			px = px - b:GetWidth() - 6
		end
	end
	sy = sy - 60

	-- a tile panel
	local tile = c:CreateTexture(nil, "ARTWORK", nil, 1)
	tile.kitScale = scale
	Kit:Apply(tile, "tiles/quilt_blue")
	tile:SetSize(150, 90)
	tile:SetPoint("TOPRIGHT", sx, sy)
	Kit:Retile(tile)
	local rail = Kit:Strip(c, "deco/rail", { width = 300, scale = scale })
	rail:SetPoint("BOTTOMLEFT", x, T + 6)

	return f
end

-- /kitwhat: every kit texture under the mouse cursor, back to front: the
-- piece, its rect, its texture coordinates (the crop), its tint and
-- alpha, the frame it is on. For a background that is not the one
-- expected (user, 2026-09-22: stone that changed shade, stretched
-- pictures): the answer is in which piece draws there and how it is cut.
SLASH_MELLOKITWHAT1 = "/kitwhat"
SlashCmdList.MELLOKITWHAT = function()
	local okC, cx, cy = pcall(GetCursorPosition)
	if not (okC and cx and cy) then
		return
	end
	local rows = {}
	for tex in pairs(SHADED) do
		local ok, visible = pcall(tex.IsVisible, tex)
		if ok and visible then
			local okR, l, b, w, h = pcall(tex.GetRect, tex)
			local okS, es = pcall(tex.GetEffectiveScale, tex)
			if okR and l and w and okS and es and es > 0 and not (issecretvalue and (issecretvalue(l) or issecretvalue(w))) then
				local x, y = cx / es, cy / es
				if x >= l and x <= l + w and y >= b and y <= b + h then
					local parent = tex:GetParent()
					-- GetTexCoord: UL x y, LL x y, UR x y, LR x y
					local okT, u1, v1, _, _, _, _, u2, v2 = pcall(tex.GetTexCoord, tex)
					local okV, r, g, bl = pcall(tex.GetVertexColor, tex)
					local okL, layer, sub = pcall(tex.GetDrawLayer, tex)
					local _, file = pcall(tex.GetTexture, tex)
					local strata = parent and parent.GetFrameStrata and parent:GetFrameStrata() or "?"
					local level = parent and parent.GetFrameLevel and parent:GetFrameLevel() or 0
					local order = ({ BACKGROUND = 0, LOW = 1, MEDIUM = 2, HIGH = 3, DIALOG = 4, FULLSCREEN = 5, FULLSCREEN_DIALOG = 6, TOOLTIP = 7 })[strata] or 0
					local layerOrder = ({ BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 })[okL and layer or ""] or 0
					local kp = type(tex.kitPiece) == "table" and tex.kitPiece or nil   -- (true: a flat colour of ours)
					local pieceW, pieceH = kp and kp.w or 0, kp and kp.h or 0
					local rimInfo = ""
					if tex.button then
						local bt = tex.button
						local okCk, ck = pcall(function() return bt.GetChecked and bt:GetChecked() end)
						local okSt, st = pcall(function() return bt.GetButtonState and bt:GetButtonState() end)
						rimInfo = string.format("  RIM state=%s hover=%s pressed=%s lastChecked=%s isChecked=%s | button checked=%s state=%s enabled=%s",
							tostring(tex.state), tostring(tex.hover), tostring(tex.pressed), tostring(tex.lastChecked),
							tex.isChecked and tostring(select(2, pcall(tex.isChecked))) or "-",
							okCk and tostring(ck) or "err", okSt and tostring(st) or "err", tostring(bt.IsEnabled and bt:IsEnabled()))
					end
					local shownW = (okT and u2 and u1) and (u2 - u1) or 0
					rows[#rows + 1] = {
						key = order * 1e6 + level * 1e3 + layerOrder * 10 + (okL and sub or 0),
						text = string.format("%-34s %4dx%-4d  uv %.3f..%.3f x %.3f..%.3f  (%s: %dx%d px shown on %dx%d)  tint %.2f %.2f %.2f a=%.2f  %s/%s  %s L%d %s  file=%s",
							tostring(tex.kitName), w, h, u1 or 0, u2 or 0, v1 or 0, v2 or 0,
							kp and kp.tile and "tile" or "picture", math.floor(pieceW * shownW + 0.5), math.floor(pieceH * ((v2 or 0) - (v1 or 0)) + 0.5), w, h,
							okV and r or 1, okV and g or 1, okV and bl or 1, tex:GetAlpha() or 1,
							tostring(okL and layer or "?"), tostring(okL and sub or "?"), tostring(parent and parent:GetName() or (parent and parent:GetDebugName()) or "?"), level, strata,
							tostring(file)) .. rimInfo,
					}
				end
			end
		end
	end
	table.sort(rows, function(a, b) return a.key < b.key end)
	MelloUI:ClearLog()
	MelloUI:Print("Kit textures under the cursor, back to front (%d):", #rows)
	for _, row in ipairs(rows) do
		MelloUI:Print("%s", row.text)
	end
	MelloUI:ShowLog("kitwhat")
end

SLASH_MELLOKITDEMO1 = "/kitdemo"
SlashCmdList.MELLOKITDEMO = function(msg)
	local scale = tonumber(msg)
	if demo and (scale or demo:IsShown()) then
		demo:Hide()
		demo:SetParent(nil)
		demo = nil
		if not scale then
			return
		end
	end
	if not LAYOUT then
		MelloUI:Print("Kit layout missing (Media/KitLayout.lua).")
		return
	end
	demo = BuildDemo(scale)
	demo:Show()
end
