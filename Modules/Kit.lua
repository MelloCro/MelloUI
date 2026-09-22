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
function Kit:Apply(tex, name)
	local p = PIECES[name]
	if not p then
		tex:SetTexture(nil)
		tex.kitPiece, tex.kitName = nil, nil
		return false
	end
	if p.tile then
		tex:SetTexture(ROOT .. p.file, "REPEAT", "REPEAT")
	else
		tex:SetTexture(ROOT .. p.file)
	end
	tex:SetTexCoord(p.uv[1], p.uv[2], p.uv[3], p.uv[4])
	tex.kitPiece, tex.kitName = p, name
	self:RegisterTexture(tex)
	if p.tile then
		self:Retile(tex)
	end
	return true
end

-- Texture coordinates of a repeatable piece for its current size, so the art
-- repeats at its native scale instead of stretching.
function Kit:Retile(tex)
	local p = tex.kitPiece
	if not p or not p.tile then
		return
	end
	local scale = tex.kitScale
	if not scale or scale <= 0 then
		scale = self.scale
	end
	local ok, w, h = pcall(tex.GetSize, tex)
	if not ok or (issecretvalue and (issecretvalue(w) or issecretvalue(h))) then
		-- a region under a unit frame answers with secret sizes: `kitTileSize`
		-- (set by whoever sized it) stands in, else the art stays as applied
		w, h = tex.kitTileW or 0, tex.kitTileH or 0
	end
	local u1, u2, v1, v2 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
	if p.tile:find("x") and w > 0 then
		u2 = u1 + (u2 - u1) * (w / (p.w * scale))
	end
	if p.tile:find("y") and h > 0 then
		v2 = v1 + (v2 - v1) * (h / (p.h * scale))
	end
	tex:SetTexCoord(u1, u2, v1, v2)
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

function StripMixin:GetState()
	return self.state
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

-- Switch to another strip family (lists/row <-> lists/header): the caps'
-- sizes follow the new pieces, the frame keeps its width.
function StripMixin:SetBase(base, state)
	state = state or Kit:FirstState(base, "mid")
	if base == self.base and state == self.state then
		return
	end
	self.base = base
	self.state, self.applied = nil, nil
	local wl, h = Kit:Size(StripName(base, "cap_l", state), self.scale)
	local wr = Kit:Size(StripName(base, "cap_r", state), self.scale)
	self.height = h
	self.wl, self.wr = wl, wr
	self.capL:SetSize(wl, h)
	self.capR:SetSize(wr, h)
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", self, "TOPLEFT", wl, 0)
	self.mid:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -wr, 0)
	self:SetState(state)
	Kit:Retile(self.mid)
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
	local disabled = b.IsEnabled and b:IsEnabled() == false
	local checked
	if rim.isChecked then
		checked = rim.isChecked()
	else
		checked = b.GetChecked and b:GetChecked()
	end
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
		if b and b.IsShown and b:IsShown() and not rim.restState then
			local okO, over = pcall(b.IsMouseOver, b)
			local okS, state = pcall(b.GetButtonState, b)
			local hover = (okO and over) and true or nil
			local pressed = (okS and state == "PUSHED") and true or nil
			if b.GetButtonState == nil then
				pressed = rim.pressed   -- no widget state to read: the latch stands
			end
			-- the checked flag as well: a check button flips it on the C side
			-- when clicked, past the SetChecked hook (the action bars' rims
			-- stayed "checked" with the button long unchecked, user 2026-09-22)
			local checked
			if rim.isChecked then
				local okC, c = pcall(rim.isChecked)
				checked = (okC and c) and true or false
			else
				local okC, c = pcall(b.GetChecked, b)
				checked = (okC and c) and true or false
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
	local name = rim.base .. "_" .. (self:FirstStateOf(rim.base) or "normal")
	local p = PIECES[name]
	local icon = rim.icon
	-- the icon fills the rim's opening: measured on the RIM's own rect (the
	-- rim may be a square on a rectangular button, or larger than the button)
	local rw, rh = rim:GetSize()
	local l, r, t, b = self:Insets(name, 1)
	if p and l and icon and rw > 0 and rh > 0 then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", rim, "TOPLEFT", rw * l / p.w, -rh * t / p.h)
		icon:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -rw * r / p.w, rh * b / p.h)
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
--           `into` how far the fill goes into the rails (1 = all the way);
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
	["TitleBar"]                              = { kind = "strip", base = "tabs/top", state = "title", heightScale = 1.5, onRail = true },   -- rune caps, red plate (the user's pick H), red matched to buttons/redbtn (F); 1.5 x the bar's height, same width; `onRail`: standing on the OUTER rail across the whole window width, its bottom on the band's top edge, the title text with it (user, 2026-09-21: the header sits on top of the thick border of every window)
	["_UI-Frame-TopTileStreaks"]              = { kind = "fade" },   -- the streak band under the title: a stone band there read as a second, different backdrop (user, 2026-09-21); the page shows through
	["UI-Frame-PortraitMetal-CornerTopLeft"]  = { kind = "texture", piece = "window/portrait_ring", square = true, level = 1 },
	["RedButton-Exit"]                        = { kind = "state", base = "window/close", rect = "normal" },
	-- inset frames and backdrops
	["common-insideframe"]                    = { kind = "frame" },
	["common-insideframe-2x"]                 = { kind = "frame" },
	-- the two pane backdrops are plain pictures: stone only; the seam between
	-- the panes is drawn by common-framedivider alone, as in the default
	["UI-Character-Info-General-BG"]          = { kind = "tile", piece = "tiles/stone" },
	["UI-Character-Info-Stat-BG"]             = { kind = "tile", piece = "tiles/stone" },
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
	["ModelSceneBackground"]                  = { kind = "tile", piece = "tiles/stone" },   -- the race landscape behind the character
	-- the ONE addition the default window does not have (the user's decision, catalogue pick B1):
	-- a single-rail iron frame around the character viewport, over its backdrop
	["ViewportFrame"]                         = { kind = "frame", body = false, level = 1, open = "r" },   -- open where it meets the pane divider
	-- slots and tabs
	-- gemSpan: the gems' centre-to-centre span as a fraction of the piece; with
	-- opts.pitch (the distance between neighbouring slots) the rim is sized so
	-- neighbours share a gem, as the game's slot pictures share their diamonds
	["UI-Character-Info-GearSlot"]            = { kind = "slot", slot = "slot", under = true, gemSpan = { 97 / 135, 92 / 130 } },
	["common-sidetab"]                        = { kind = "slot", slot = "slot", rest = "checked", glow = true },   -- gold rim on every tab (the user's pick, I), additive glow when selected
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
	["spellbook-Page-Right-C60"]              = { kind = "picture", piece = "backdrops/page_parchment", crop = "middle", level = -1 },   -- the book page: the user's parchment page painting (parchmentnew, 2026-09-21; painted at the page's 1.15 aspect), one UNDER the SpellBookFrame (level 100: well above the window's skin, below every control on the page)
	["spellbook-Page-Left-C60"]               = { kind = "picture", piece = "backdrops/page_parchment", crop = "middle", level = -1 },
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
	["RedButton-Expand"]                      = { kind = "state", base = "buttons/arrow_up", natural = true, rect = "normal" },   -- the window's maximize / minimize
	["RedButton-Condense"]                    = { kind = "state", base = "buttons/arrow_down", natural = true, rect = "normal" },
	-- the professions window (user's picks, 2026-09-21: A, F crop 1, K1)
	-- the book page's backdrop: the user's own page painting (the kit's soft
	-- stones, tiles/crackle and a plain grey were all tried before it)
	["Profession-Background-Overview"]        = { kind = "picture", piece = "backdrops/page_stone", crop = "middle", level = 1 },   -- one ABOVE the window (the window's own skin is at its level: a tie there draws in an order the client may change between loads)   -- the user's grey stone page with gothic pilasters (2026-09-21), painted at the page's own aspect
	["Profession-overview-Card"]              = { kind = "frame" },   -- a primary card with no profession in it (A): single rail, stone body
	-- a primary card with a profession: the game re-atlases its Background to
	-- -<Profession> in FormatProfession; each gets its painted banner (the
	-- still-life at the right on stone, user's sheets 2026-09-21), whole at the
	-- card's height against its right edge (nothing of the still-life cut
	-- off), the stone mirrored across the rest, the single rail over it
	["Profession-overview-Card-Alchemy"]       = { kind = "picture", piece = "cards/alchemy", fit = "right", frame = true },
	["Profession-background-card-Alchemy"]     = { kind = "picture", piece = "backdrops/profession_alchemy", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Blacksmithing"] = { kind = "picture", piece = "cards/blacksmithing", fit = "right", frame = true },
	["Profession-background-card-Blacksmithing"]= { kind = "picture", piece = "backdrops/profession_blacksmithing", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Enchanting"]    = { kind = "picture", piece = "cards/enchanting", fit = "right", frame = true },
	["Profession-background-card-Enchanting"]  = { kind = "picture", piece = "backdrops/profession_enchanting", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Engineering"]   = { kind = "picture", piece = "cards/engineering", fit = "right", frame = true },
	["Profession-background-card-Engineering"] = { kind = "picture", piece = "backdrops/profession_engineering", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Herbalism"]     = { kind = "picture", piece = "cards/herbalism", fit = "right", frame = true },
	["Profession-background-card-Herbalism"]   = { kind = "picture", piece = "backdrops/profession_herbalism", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Leatherworking"]= { kind = "picture", piece = "cards/leatherworking", fit = "right", frame = true },
	["Profession-background-card-Leatherworking"]= { kind = "picture", piece = "backdrops/profession_leatherworking", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Mining"]        = { kind = "picture", piece = "cards/mining", fit = "right", frame = true },
	["Profession-background-card-Mining"]      = { kind = "picture", piece = "backdrops/profession_mining", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Skinning"]      = { kind = "picture", piece = "cards/skinning", fit = "right", frame = true },
	["Profession-background-card-Skinning"]    = { kind = "picture", piece = "backdrops/profession_skinning", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Tailoring"]     = { kind = "picture", piece = "cards/tailoring", fit = "right", frame = true },
	["Profession-background-card-Tailoring"]   = { kind = "picture", piece = "backdrops/profession_tailoring", crop = "bottom", frame = true },   -- the schematic backdrop (T1): the tall colour panel with the inset rail on the same holder (the form's own inset texture is faded with it)
	-- the secondary professions' schematics: their own tall panels (user's sheet 3d259005, 2026-09-21), cut at the schematic's aspect on the band with the still-life
	["Profession-background-card-Cooking"]    = { kind = "picture", piece = "backdrops/schematic_cooking", crop = "bottom", frame = true },
	["Profession-background-card-Fishing"]    = { kind = "picture", piece = "backdrops/schematic_fishing", crop = "bottom", frame = true },
	["Profession-background-card-FirstAid"]   = { kind = "picture", piece = "backdrops/schematic_firstaid", crop = "bottom", frame = true },
	["Profession-overview-card-generic-Cooking"]  = { kind = "picture", piece = "backdrops/profession_cooking", grey = "backdrops/profession_cooking_grey", crop = "bottom", frame = true },   -- a secondary card (F, crop 1): the still-life, grey while not learned, single rail over it
	["Profession-overview-card-generic-Fishing"]  = { kind = "picture", piece = "backdrops/profession_fishing", grey = "backdrops/profession_fishing_grey", crop = "bottom", frame = true },
	["Profession-overview-card-generic-FirstAid"] = { kind = "picture", piece = "backdrops/profession_firstaid", grey = "backdrops/profession_firstaid_grey", crop = "bottom", frame = true },
	["Profession-square-frame"]               = { kind = "slot", slot = "slot" },   -- the frame over a profession spell's icon: the rim over the icon, as the game's is
	-- the crafting page (user's picks, 2026-09-21: S1 D1 B1 N1 R1 O1 K2 L1 T1)
	["Profession-Background-Template2"]       = { kind = "picture", piece = "backdrops/page_stone", crop = "middle", level = -2 },   -- the crafting page's backdrop: the same page stone as the book's; TWO under the page, so the list box and the schematic picture (one under their frames, which may sit at the page's level) never tie with it
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
	["Legacy-Rewards-Tracker-background"]     = { kind = "picture", piece = "backdrops/page_stone", crop = "middle", owner = true },   -- a page's backdrop: the page stone as a REGION of the page in the backdrop's own layer (the pages sit at level 100 with children at 800: no holder, no tie), fitted to the WINDOW's rect so all three pages show the same picture in the same place
	["Legacy-Challenge-BG"]                   = { kind = "picture", piece = "backdrops/page_stone", crop = "middle", owner = true },
	["Legacy-Tree-Frame-background"]          = { kind = "picture", piece = "backdrops/page_stone", crop = "middle", owner = true },
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
	["QuestLog-main-background"]              = { kind = "picture", piece = "backdrops/page_parchment", crop = "middle", owner = true },   -- the list's page (QP2, user 2026-09-21): the parchment page painting, as the spell book's; also MelloUI's own quest list window
	["QuestDetailsBackgrounds"]               = { kind = "picture", piece = "backdrops/page_parchment", crop = "top", owner = true },   -- a quest's details page: the same parchment
	["MapTitleBand"]                          = { kind = "picture", piece = "backdrops/page_stone", crop = "top", level = 0 },   -- an agreed addition (user, 2026-09-21): a body-off window's title band (the map for its canvas; the collections and LFG pages, whose rock starts below the title) filled with the page stone, inside the outer rail, so it is not bare once the title plate stands on the rail
	["questlog-frame"]                        = { kind = "frame", body = false },   -- the border around the list / details (QuestLogBorderFrameTemplate): the single rail, edges only
	["QuestLog-frame-devider"]                = { kind = "strip", base = "window/divider" },   -- the line under a header
	["questlog-icon-setting"]                 = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the list's settings button (a 15 x 16 gear glyph): the cog plate (K2), as the dropdown arrows
	["questlog-quest-glow-yellow"]            = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a quest title's highlight (the game shows it on hover / selection): the plate's hover look
	["QuestListFilter"]                       = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- MelloUI's Quests panel filter buttons (F7, user 2026-09-21): the plain plate (hover from the button) ...
	["QuestListFilter-Selected"]              = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... the selected plate on the active filter (from the panel's db.filter)
	-- the guild and communities window (CommunitiesFrame; file art keyed by hand; 2026-09-21)
	["UI-Background-Rock"]                    = { kind = "picture", piece = "backdrops/page_stone", crop = "middle", owner = true },   -- ButtonFrameTemplate's rock background: the page stone as a region of the frame
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
	["UI-LFG-BACKGROUND-QUESTPAPER"]          = { kind = "picture", piece = "backdrops/page_parchment", crop = "middle", owner = true },   -- the queue frame's paper (file art, keyed by hand): the parchment page, as the quest lists
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
	["ObjectiveTrackerBackground"]            = { kind = "frame" },   -- Edit Mode's tracker backdrop (a NineSlicePanelTemplate child): L1, the single rail with stone, its child (follows the opacity)
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
	["NamePlateHealthBarBG"]                  = { kind = "bar", bar = "frame", capOut = true },   -- NP1: the health bar's backing (UI-HUD-CoolDownManager-Bar-BG, keyed by hand) -> P1 as the bar's regions above the fill, the caps outside, the bar set in by the arms after the game's UpdateAnchors; the trough under the fill
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
	["DamageMeterSettingsIcon"]               = { kind = "state", base = "buttons/cog", natural = true, layer = "BACKGROUND" },   -- the settings dropdown button's glyph (an Icon set in Lua, keyed by hand): K2, the cog plate under it

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
	Kit.shells[frame] = known
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

-- After the game re-lays `frame` (its `method`, a post-hook on the instance),
-- run `fn` out of combat; also on the frame's size changes when `onSize`.
function Kit:RefitOnLayout(frame, method, fn, onSize)
	if method and type(frame[method]) == "function" then
		hooksecurefunc(frame, method, function()
			Kit:WhenOutOfCombat(fn)
		end)
	end
	if onSize then
		frame:HookScript("OnSizeChanged", function()
			Kit:WhenOutOfCombat(fn)
		end)
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
	if not (button and button.NormalTexture and button.icon) or button.melloRep ~= nil then
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
	local rep = replace(button.NormalTexture, { as = "UI-HUD-ActionBar-IconFrame", button = button, rect = button, pitch = pitch,
		icon = button.icon, alsoFade = extra })
	button.melloRep = rep or false
	if not rep then
		return nil
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
		local name = "buttons/slot_normal"
		local piece = PIECES[name]
		local opening = CreateFrame("Frame", nil, button)
		opening:EnableMouse(false)
		local function Fit()
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
		local stone = replace(button.SlotBackground or button.NormalTexture, { as = "UI-HUD-ActionBar-IconFrame-Background", rect = opening,
			noFade = not button.SlotBackground })
		if stone then
			-- the stone shows while the slot is EMPTY: the game hides the icon
			-- then (its own backing shows only on a bar whose art is hidden —
			-- on the main bar the faded frame art was the empty slot's look)
			local function Sync()
				if rep.object:IsShown() then
					stone:SetShown(not icon:IsShown())
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
	if self.object.glow then
		self.object.glow:Hide()
	end
	if self.onDisable then
		self.onDisable(self)
	end
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
		local w = self.rect:GetWidth() * (self.rule.widthFrac or 1)
		self.strip:ClearAllPoints()
		self.strip:SetPoint("CENTER", self.rect, "CENTER", 0, yoff)
		self.strip:SetSize(math.max(w, 1), self.strip.height)
		return
	end
	local h = self.fitHeight
	if not (h and h > 0) then
		local ok
		ok, h = pcall(self.rect.GetHeight, self.rect)
		if not ok or Secret(h) then
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
		local okW0, w0 = pcall(self.rect.GetWidth, self.rect)
		if okW0 and w0 and not Secret(w0) and w0 > 0 then
			over = over + w0 * (self.rule.widthScale - 1) / 2
		end
	end
	local overL = self.strip.dropCap == "l" and 0 or over
	local overR = self.strip.dropCap == "r" and 0 or over
	self.strip:SetPoint("LEFT", self.rect, "LEFT", -overL, yoff)
	self.strip:SetPoint("RIGHT", self.rect, "RIGHT", overR, yoff)
	self.strip:SetHeight(self.strip.height)
	local okW, w = pcall(self.rect.GetWidth, self.rect)
	if not okW or Secret(w) or not (w and w > 0) then
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
function Kit:RuleFor(key)
	if not key then
		return nil
	end
	local rule = self.Replacements[key]
	if rule then
		return rule
	end
	if not LOWER_RULES then
		LOWER_RULES = {}
		for k, v in pairs(self.Replacements) do
			LOWER_RULES[k:lower()] = v
		end
	end
	return LOWER_RULES[key:lower()]
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
	local level = opts.level or rule.level or -1
	-- fitHeight / fitWidth: the element's size as the template states it, used
	-- where its rect reads SECRET (the target's spell bar) or is not laid out yet
	local rep = Mixin({ kind = rule.kind, key = key, rule = rule, region = region, rect = rect, alsoFade = opts.alsoFade or {}, fitHeight = opts.fitHeight, fitWidth = opts.fitWidth, noFade = opts.noFade }, ReplacementMixin)

	local function Holder(lvl)
		local f = CreateFrame("Frame", nil, parent)
		-- opts.strata: a holder below everything at the parent's strata (the
		-- main bar's end caps under every bar and the status bars)
		if opts.strata then
			f:SetFrameStrata(opts.strata)
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
				local disabled = button.IsEnabled and button:IsEnabled() == false
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
				-- the plate spans the outer rail's WHOLE width (user, 2026-09-21),
				-- its bottom on the rail's top edge: anchored to the window's
				-- top corners, so no layout is needed
				-- ... the whole width of the OUTER rail, which is grown outward
				-- past the window's edges by the outset
				local lift = Kit:OuterRailTop() + self.strip.height / 2
				local out = Kit:OuterRailOutset()
				self.strip:ClearAllPoints()
				self.strip:SetPoint("LEFT", window, "TOPLEFT", -out, lift)
				self.strip:SetPoint("RIGHT", window, "TOPRIGHT", out, lift)
				self.strip:SetHeight(self.strip.height)
				local w = window:GetWidth()
				if w and w > 0 and not (issecretvalue and issecretvalue(w)) then
					self.strip:FitCaps(w + 2 * out)
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
					text:SetPoint("CENTER", self.strip, "CENTER", 0, dy)
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
		end
		if rule.gemSpan and opts.pitch and opts.pitch[1] > 0 and opts.pitch[2] > 0 then
			rim:ClearAllPoints()
			rim:SetPoint("CENTER", rect, "CENTER")
			rim:SetSize(opts.pitch[1] / rule.gemSpan[1], opts.pitch[2] / rule.gemSpan[2])
		end
		-- SetPitch(x, y): re-size the rim to a new pitch (a bar re-laid by
		-- Edit Mode) and fit the icon again
		rep.SetPitch = function(self, px, py)
			if rule.gemSpan and px and py and px > 0 and py > 0 then
				rim:ClearAllPoints()
				rim:SetPoint("CENTER", rect, "CENTER")
				rim:SetSize(px / rule.gemSpan[1], py / rule.gemSpan[2])
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
		local base = "bars/" .. (rule.bar or "frame")
		-- the bracket goes in the layer just above the game's fill (`layer` /
		-- `sublevel` on the rule: the caps at that sublevel, the middle ONE
		-- BELOW it, so the sublevel must be at least the fill's + 2: BORDER 1
		-- over a BORDER 0 fill, ARTWORK 4 over a rank bar's ARTWORK 2 fill),
		-- the trough in BACKGROUND under it
		-- opts.layer / sublevel / troughLayer / troughSub override the rule's
		-- for a fill drawn elsewhere (a unit frame's power bar at ARTWORK: the
		-- bracket at OVERLAY 0, the trough at BORDER)
		local strip = self:Strip(parent, base, { scale = self.scale, owner = parent, layer = opts.layer or rule.layer or "BORDER", sublevel = opts.sublevel or rule.sublevel or 1 })
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
			local capL, capR = PIECES[StripName(base, "cap_l")], PIECES[StripName(base, "cap_r")]
			local l = capL and capL.open and capL.open[1] * sc or self.strip.wl or 0
			local r = capR and capR.open and (capR.w - capR.open[3]) * sc or self.strip.wr or 0
			return l, r
		end
		-- the bracket's fill area as insets from the rect: sideways from the
		-- caps' hollow arms (past the gems) a little under the gems' bezels,
		-- top / bottom most of the way into the rails, so the rails cover the edges
		rep.GetOpening = function(self)
			local sc = self.strip.scale
			local mid = PIECES[StripName(base, "mid")]
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
			local okH, rectH = pcall(self.rect.GetHeight, self.rect)
			if not okH or Secret(rectH) or not rectH then
				rectH = self.fitHeight or 0
			end
			local canvasH = (mid and mid.h or 0) * sc
			local yoff = self.stripOffset or 0
			local top = rectH / 2 - yoff - canvasH / 2 + rowT * sc
			local bottom = rectH / 2 + yoff + canvasH / 2 - rowB * sc
			return l, r, top, bottom
		end
		rep.Refit = function(self)
			local okH, h = pcall(self.rect.GetHeight, self.rect)
			if not okH or Secret(h) or not (h and h > 0) then
				h = self.fitHeight
			end
			if not (h and h > 0) then
				return
			end
			-- `thicken`: the bracket is that many UI px taller than the rect,
			-- centred on it (it overhangs the rect top and bottom)
			-- `heightScale`: the bracket that fraction of the rect's height,
			-- centred on it (the character pane's bars at 0.85 — user, 2026-09-21)
			local yoff = self.strip:FitBox((h + (opts.thicken or rule.thicken or 0)) * (rule.heightScale or 1))
			self.stripOffset = yoff
			local okW, w = pcall(self.rect.GetWidth, self.rect)
			if not okW or Secret(w) or not (w and w > 0) then
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
		rep.Refit = function(self)
			local name = (self.grey and rule.grey and self.grey()) and rule.grey or rule.piece
			if self.tex.kitName ~= name then
				Kit:Apply(self.tex, name)
			end
			local p = PIECES[name]
			local w, h = self.inner:GetSize()
			if not (p and w and h and w > 0 and h > 0) then
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
		if rep.object == tex then
			-- a region has no OnSizeChanged: re-tile on the rect's
			local sizer = CreateFrame("Frame", nil, f)
			sizer:EnableMouse(false)
			sizer:SetAllPoints(rect)
			sizer:SetScript("OnSizeChanged", function() Kit:Retile(tex) end)
			sizer:HookScript("OnShow", function() Kit:Retile(tex) end)
		end
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

-- A game texture of `frame` by its art key (atlas / file base name).
function Kit:TextureByArt(frame, key)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece and self:ArtKey(region) == key then
			return region
		end
	end
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
-- A black shade under a list's text: darkest down the middle, fading
-- out to both sides (user, 2026-09-22: the quest text on the stone and
-- the parchment). Two gradient halves on a holder at the parent's level
-- (over the parent's own picture, under its children), inset by `inset`
-- px from the rect. Returns the holder: show / hide it with the skin.
--   Kit:CentreShade(parent, rect, { strength = 0.6, inset = 4 })
function Kit:CentreShade(parent, rect, opts)
	opts = opts or {}
	local strength, inset = opts.strength or 0.6, opts.inset or 4
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetFrameLevel(parent:GetFrameLevel())
	holder:EnableMouse(false)
	holder:SetPoint("TOPLEFT", rect, "TOPLEFT", inset, -inset)
	holder:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", -inset, inset)
	local left = holder:CreateTexture(nil, "BACKGROUND", nil, 2)
	left:SetColorTexture(1, 1, 1, 1)
	left:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, strength))
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", holder, "BOTTOM")
	local right = holder:CreateTexture(nil, "BACKGROUND", nil, 2)
	right:SetColorTexture(1, 1, 1, 1)
	right:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, strength), CreateColor(0, 0, 0, 0))
	right:SetPoint("TOPLEFT", holder, "TOP")
	right:SetPoint("BOTTOMRIGHT")
	holder.left, holder.right = left, right
	return holder
end

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
		-- a factor on the medallion size: an icon painted with a wide
		-- transparent margin (the social window's) reads small at 1
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
function Kit:SkinInset(inset, replace, parent)
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
	inset.melloRep = replace(inset, { as = "common-insideframe", parent = parent, rect = inset, level = level, body = false, noFade = true, alsoFade = extra }) or false
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
					local pieceW, pieceH = tex.kitPiece and tex.kitPiece.w or 0, tex.kitPiece and tex.kitPiece.h or 0
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
							tex.kitPiece and tex.kitPiece.tile and "tile" or "picture", math.floor(pieceW * shownW + 0.5), math.floor(pieceH * ((v2 or 0) - (v1 or 0)) + 0.5), w, h,
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
