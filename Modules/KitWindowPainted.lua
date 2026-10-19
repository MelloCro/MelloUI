--------------------------------------------------------------------------------
-- MelloUI - Kit window, the painted reskin's part (one look, stage I: cut from
-- Modules/KitWindow.lua, which loads before it)
--
-- The painted dressing of an own window -- the page stone and the outer rail,
-- the ring (or the game's corner), the title plate -- handed to the shell as
-- Kit.__.ShellDress (Kit:OwnWindow runs it through shell:Kit: now while the
-- kit dresses the window, else at the first switch on); Kit:ChoicePicture, a
-- look choice's picture for the picture rows (W.PictureRow / W.PictureMenu);
-- and the nudges the painted skins move the game's controls with (Kit:Nudge,
-- Kit:ClearRails, Kit:AlignBeside, Kit:TitleWords, Kit:Shrink).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Kit = MelloUI.Kit
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceNameOf = MelloUI.Kept.pieceNameOf
local pieceOf = MelloUI.Kept.pieceOf
local Num = MelloUI.Safe.Number
local Secret = MelloUI.Safe.IsSecret

local PLATE_FIT, ROUND_MASK = Kit.__.ShellPlateFit, Kit.__.RoundMask   -- (KitWindow.lua's)
-- the game's portrait corner (ring.game: a window standing in for a game window, the bag window), one frame level
-- over its portrait (KitWindow.lua's LEVEL_GAME_PORTRAIT, 9)
local LEVEL_GAME_CORNER = 10
local GAME_CORNER_ATLAS = "UI-Frame-PortraitMetal-CornerTopLeft"
local GAME_CORNER_X, GAME_CORNER_Y = -13, 16   -- NineSliceLayouts' PortraitFrameTemplate TopLeftCorner

-- the short plate's title on its painted box, in the title face (2c), and
-- back on the plain plate (the rep's onEnable / onDisable)
local function Plate_OnEnable(rep)
	local fs = rep.melloTitle
	if fs and rep.strip then
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", rep.strip, "CENTER", 0, Kit:StripTextOffset(rep.strip))
		Kit:TitleFont(fs, true)
	end
end

local function Plate_OnDisable(rep)
	local fs = rep.melloTitle
	if fs then
		Kit:TitleFont(fs, false)
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", rep.melloPlate, "CENTER", 0, 0)
	end
end

--------------------------------------------------------------------------------
-- The kit's dressing (through shell:Kit: now, or at the first switch on)
--------------------------------------------------------------------------------

-- the page stone in the rock's place, the outer double rail (its
-- shell registration: the rail Edit Layout lights while the window is
-- dragged, Kit.shells[frame].outer, and its shade)
local function DressFrame(K, shell)
	local frame = shell.frame
	shell.page = shell:Replace(shell.bg, { as = "UI-Background-Rock", parent = frame, rect = frame, inset = K:OuterRailInset(), alsoFade = { shell.tint } })
	-- (the window's own choice in the stone's place, opts.background)
	shell:SetBackground()
	-- (body = false: the page stone above is the window's one background)
	local ok, rail = pcall(shell.Replace, shell, shell:Anchor(frame, "BORDER"), { as = "NineSlicePanelTemplate", parent = frame, rect = frame,
		body = false, skip = shell.ringAt == "tl" and "tl" or nil })
	if not ok then
		error(rail, 0)
	end
	if rail then
		shell.rail = rail
		shell.bounds[#shell.bounds + 1] = rail.object
	end
end

-- the ring in place of the plain emblem, its disc in the palette's inner
-- panel, the emblem on the disc (sized by the kit: no size of its own)
local function DressRing(K, shell)
	if shell.gameCorner then
		-- (ring.game: the game's own corner art where the game puts it, shown with the painted look; the emblem is
		-- the crest's own, the game's portrait: shell.plainEmblem)
		local holder = CreateFrame("Frame", nil, shell.frame)
		holder:SetFrameLevel(shell.frame:GetFrameLevel() + LEVEL_GAME_CORNER)
		holder:EnableMouse(false)
		holder:SetAllPoints(shell.frame)
		local corner = holder:CreateTexture(nil, "OVERLAY")
		if pcall(corner.SetAtlas, corner, GAME_CORNER_ATLAS, true) then
			corner:SetPoint("TOPLEFT", shell.frame, "TOPLEFT", GAME_CORNER_X, GAME_CORNER_Y)
			-- (its rail stubs cut as on the game's windows, and the kit's rail cut at the ring: Kit:CutGameCorner)
			if holder.CreateMaskTexture and corner.AddMaskTexture then
				corner:AddMaskTexture(K:CornerCutMask(holder, corner))
			end
			if shell.rail and rawget(shell.rail, "outerCut") == nil then
				K:CutRailAtRing(shell.rail, corner)
			end
			shell.gameCornerTex = corner   -- (the plate behind it: DressPlate)
		else
			corner:Hide()
		end
		shell.gameCornerArt = holder
		shell:OnKit(function(sh, on)
			sh.gameCornerArt:SetShown(on)
		end)
		holder:SetShown(shell.kit)
		return
	end
	-- (`own`: an own window's corner ring; a game window's corner stays the game's, Kit:Replace)
	local rep = shell:Replace(shell.plainEmblem, { as = shell.ringAt == "top" and "MelloUI-Crest" or "UI-Frame-PortraitMetal-CornerTopLeft",
		rect = shell.crest, own = true })
	if not rep then
		return
	end
	shell.ring = rep
	local holder = rep.object
	local disc = K:RingDisc(rep, "innerPanel", holder, 6)
	local emblem = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	pieceOf[emblem] = true
	emblem:SetTexture(shell.emblemTexture)
	emblem:SetAllPoints(disc or rep.tex)
	local mask = holder:CreateMaskTexture()
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(emblem)
	emblem:AddMaskTexture(mask)
	shell.emblem, shell.disc = emblem, disc
end

-- the plate: the short one under the crest, or the standard one on the rail
-- (its title carried by the rule, 2c)
local function DressPlate(K, shell)
	local plate = shell.plate
	local rep
	if shell.plateKind == "rail" then
		plate.TitleText = shell.title
		rep = shell:Replace(shell.plateFill, { as = "TitleBar", parent = plate, rect = plate, fitHeight = PLATE_FIT, alsoFade = shell.plateEdges })
		if rep and rep.object then
			shell.bounds[#shell.bounds + 1] = rep.object
		end
		-- (0.20.1, a stand-in for a game window: the bag window) the plate behind the game's corner, as a game
		-- window's (Kit:RegisterShell's)
		if rep and shell.gameCornerTex then
			K:TitleBehindGameCorner(rep, shell.gameCornerTex, shell.rail, true)
		end
	else
		rep = shell:Replace(shell.plateFill, { as = "MelloUI-TitlePlate", parent = plate, rect = plate, fitHeight = PLATE_FIT, alsoFade = shell.plateEdges })
		if rep then
			rep.melloTitle, rep.melloPlate = shell.title, plate
			rep.onEnable, rep.onDisable = Plate_OnEnable, Plate_OnDisable
			if shell.kit then
				Plate_OnEnable(rep)
			end
		end
	end
	shell.plateRep = rep
end

-- (Kit:OwnWindow runs them through shell:Kit when it builds a window)
Kit.__.ShellDress = { Frame = DressFrame, Ring = DressRing, Plate = DressPlate }

--------------------------------------------------------------------------------
-- Kit:ChoicePicture: a look choice's picture (0.15.0; the Dynamic UI picker's
-- previews, moved here with its window gone): what the choice looks like
-- where it goes, on a small tile -- a picture row's box and its flyout's
-- tiles (W.PictureRow / W.PictureMenu, Core/Widgets.lua). The kinds, as the
-- choices' owners name them (Kit.borderKinds' `preview`, a panel's
-- PickerGroups section `kind`):
--   rim    the rim round a spell icon on the stone, as on the bar (a choice
--          with no rim piece: the icon on the stone, its plain edge)
--   bar    a progress bar in that bracket, a sample fill two thirds along
--   frame  the border piece round the stone (a rail family: a small
--          nine-slice of it); none: the stone darkened, "None"
--   tile   a swatch of the background; Dark: the palette's inner panel;
--          none: "None"
--   Kit:ChoicePicture(tile, kind, choice)
--     tile    the caller's: tile.pic (the picture's square frame), tile.none
--             (a FontString reading "None"), tile.layers (a table, its
--             slots filled here, LAYER_* below), tile.size (the picture's
--             side; TILE when nil)
--     choice  nil: the tile shows nothing
-- A tile's parts are made once and kept: drawn again with another choice (a
-- pooled tile, a row's box after a pick) it makes nothing but a bar strip or
-- a rail family's nine-slice the first time one is shown on it.
--------------------------------------------------------------------------------

local TILE = 52            -- a picture's side when the tile names none (the flyout's tiles)
local NONE_DIM = 0.45      -- the "None" frame's stone, darkened to this much of its light
local SAMPLE_ICON = "Interface\\Icons\\INV_Sword_04"

-- A tile's textures by what they wear. A texture that once wore a kit piece
-- stays the kit's (Dark Mode's brightness follows its every tint), so the
-- slots that wear kit pieces never wear anything else, and what is not the
-- kit's -- the sample icon, the bar's gold fill, the Dark swatch -- has a
-- slot of its own that never wears a piece.
local LAYER_BACK = 1       -- the stone, or a background's swatch (kit pieces)
local LAYER_PIECE = 2      -- a frame's border piece
local LAYER_RIM = 3        -- a rim's piece
local LAYER_OWN = 4        -- the icon, the fill or the Dark swatch (never a kit piece)

-- the tile's texture `i` over the whole picture (made the first time, kept;
-- what it wore for another choice let go -- a palette fill, a kit piece --
-- so a new palette or Kit Colours leaves what it wears now)
local function Layer(tile, i, level)
	local t = tile.layers[i]
	if not t then
		t = tile.pic:CreateTexture(nil, "ARTWORK", nil, level or 0)
		tile.layers[i] = t
	else
		Kit:Unpaint(t)
		if pieceNameOf[t] then
			Kit:Apply(t, nil)
		end
	end
	t:SetDrawLayer("ARTWORK", level or 0)
	t:ClearAllPoints()
	t:SetAllPoints(tile.pic)
	t:SetTexCoord(0, 1, 0, 1)
	t:SetVertexColor(1, 1, 1, 1)
	t:Show()
	return t
end

-- the stone a rim, a bar or a frame lies on
local function Stone(tile)
	local back = Layer(tile, LAYER_BACK, 0)
	back.kitScale, back.kitOwnScale = Kit.scale, true
	Kit:Apply(back, "tiles/stone")
	Kit:Retile(back)
	return back
end

-- the icon a rim is shown round: the first action button's, as on the bar
-- (a secret answer, or none: a sample sword)
local function SampleIcon()
	local icon = GetActionTexture and GetActionTexture(1)
	if Secret(icon) then
		return SAMPLE_ICON
	end
	return icon or SAMPLE_ICON
end

-- a rail family's small nine-slice on the tile, one per family made and kept
-- (a pooled tile shows other families after)
local function Nine(tile, choice, size)
	local nines = rawget(tile, "melloNines")   -- (fields of our own, never a method)
	if not nines then
		nines = {}
		rawset(tile, "melloNines", nines)
	end
	local key = choice.prefix .. (choice.gem and "|gem|" or "|") .. tostring(choice.scale or 1)
	local skin = nines[key]
	if not skin then
		skin = Kit:NineSlice(tile.pic, { prefix = choice.prefix, scale = Kit.scale * (choice.scale or 1) * 0.5 * size / TILE,
			gems = false, body = false, corners = choice.gem and "gem" or nil })
		nines[key] = skin
	end
	skin:Show()
end

function Kit:ChoicePicture(tile, kind, choice)
	local pic = tile.pic
	if not tile.layers then
		tile.layers = {}
	end
	local layers = tile.layers
	for i = LAYER_BACK, LAYER_OWN do
		local t = layers[i]   -- (a slot is made when first worn: they may have gaps)
		if t then
			t:Hide()
		end
	end
	local nines = rawget(tile, "melloNines")
	if nines then
		for _, skin in pairs(nines) do
			skin:Hide()
		end
	end
	local strip = rawget(tile, "melloStrip")
	if strip then
		strip:Hide()
	end
	tile.none:Hide()
	if self.BorderPictureOff then
		self:BorderPictureOff(tile)   -- (a border of the library's, drawn by the choice shown before)
		self:BorderBarPictureOff(tile)
	end
	if not choice then
		return
	end
	local size = tonumber(tile.size) or TILE
	if kind == "rim" and choice.style and self.BorderPicture then
		-- (0.19.8) a style of the border library's (Modules/KitBorders.lua):
		-- drawn by it round the sample icon, at a button's weight
		Stone(tile)
		local icon = Layer(tile, LAYER_OWN, 1)
		icon:SetTexture(SampleIcon())
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		self:BorderPicture(tile, choice, icon)
	elseif kind == "rim" then
		-- the rim round a spell icon on stone, as on the bar
		Stone(tile)
		local icon = Layer(tile, LAYER_OWN, 1)
		icon:SetTexture(SampleIcon())
		local p = choice.piece and self:Piece(choice.piece)
		if p and p.open then
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", pic, "TOPLEFT", size * p.open[1] / p.w, -size * p.open[2] / p.h)
			icon:SetPoint("BOTTOMRIGHT", pic, "BOTTOMRIGHT", -size * (p.w - p.open[3]) / p.w, size * (p.h - p.open[4]) / p.h)
		elseif not choice.piece then
			-- no rim of the kit's (the auras' plain edge): the stone's edge
			-- round the icon
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", pic, "TOPLEFT", 2, -2)
			icon:SetPoint("BOTTOMRIGHT", pic, "BOTTOMRIGHT", -2, 2)
		end
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		if choice.piece then
			self:Apply(Layer(tile, LAYER_RIM, 2), choice.piece)
		end
	elseif kind == "bar" and choice.style and self.BorderBarPicture then
		-- (0.19.8) a style of the border library's round a sample fill
		Stone(tile)
		local fill = Layer(tile, LAYER_OWN, 1)
		self:Paint(fill, "selectedTrim", "fill", 1)
		self:BorderBarPicture(tile, choice, fill, size)
	elseif kind == "bar" and not (choice.bar or choice.style) then
		-- (0.21.0, the Personal Resource Border's None) no frame: the stone darkened, as a frame row's None
		local back = Stone(tile)
		back:SetVertexColor(NONE_DIM, NONE_DIM, NONE_DIM)
		tile.none:Show()
	elseif kind == "bar" and self.Strip then
		-- a progress bar in that bracket: a fill two thirds along, on stone
		Stone(tile)
		local base = "bars/" .. (choice.bar or "frame")
		if not strip then
			strip = self:Strip(pic, base, { scale = self.scale, layer = "ARTWORK", sublevel = 2 })
			rawset(tile, "melloStrip", strip)
		elseif strip.SetBase then
			strip:SetBase(base)
		end
		local yoff = strip:FitBox(size * 0.36)
		strip:ClearAllPoints()
		strip:SetPoint("LEFT", pic, "LEFT", 2, yoff)
		strip:SetPoint("RIGHT", pic, "RIGHT", -2, yoff)
		strip:SetHeight(strip.height)
		strip:FitCaps(size - 4)
		strip:Show()
		-- (the fill in the palette's gold: a sample, not a bar's meaning)
		local fill = Layer(tile, LAYER_OWN, 1)
		fill:ClearAllPoints()
		fill:SetPoint("LEFT", pic, "LEFT", 4, 0)
		fill:SetSize((size - 8) * 0.66, size * 0.36 * 0.5)
		self:Paint(fill, "selectedTrim", "fill", 1)
	elseif kind == "frame" and choice.style and self.BorderPicture then
		-- (0.19.8) a style of the border library's round the stone (its studs on)
		Stone(tile)
		self:BorderPicture(tile, choice, nil)
	elseif kind == "frame" then
		-- the border piece itself: its corner gems and rim round the stone
		local back = Stone(tile)
		if choice.prefix and self.NineSlice then
			-- a rail family (the minimap's square borders): a small nine-slice
			-- of it round the stone, as it is laid on the real frame
			Nine(tile, choice, size)
		elseif choice.piece then
			self:Apply(Layer(tile, LAYER_PIECE, 2), choice.piece)
		else
			-- no border: the stone darkened (a dim of the art's light, as the
			-- kit's `dim`; the recoloured stone keeps its palette's hue)
			back:SetVertexColor(NONE_DIM, NONE_DIM, NONE_DIM)
			tile.none:Show()
		end
	else
		-- a swatch of the background
		if choice.piece then
			local back = Layer(tile, LAYER_BACK, 0)
			back.kitScale, back.kitOwnScale = self.scale * 0.5, true   -- a swatch: more of the tile than the UI's resolution would show
			self:Apply(back, choice.piece)
			self:Retile(back)
		elseif choice.value == "dark" then
			-- the Dark background: the palette's inner panel
			self:Paint(Layer(tile, LAYER_OWN, 0), "innerPanel", "fill", 0.88)
		else
			tile.none:Show()
		end
	end
end

--------------------------------------------------------------------------------
-- Nudges (0.20.1; the user's picks 2026-10-10: a control the game parks at its window's edge, under the double rail
-- that lies over the content, "Move them inward"; a search field and the filter button beside it on one centre and
-- one height). A game region moved off its own anchors by offsets the kit sets, one per reason (`key`), summed; its
-- anchors as the game left them kept here -- never on its frame -- and put back when its last nudge goes. A game
-- function that anchors it again: Kit:NudgeTaken(region) takes its new anchors as the game's (the caller lays its
-- nudges again after).
--   Kit:Nudge(region, key, dx, dy, point)   the offset for `key` (0, 0: gone); `point`: that one anchor alone (the
--                                           region's edge on that side moves: it grows or shrinks)
--   Kit:NudgeTaken(region)
--   Kit:ClearRails(windowRep, region, move, axis, point, key)
--                                           `region` measured against the window's rails (a railOver look's: the
--                                           rails over the content), `move` (region; or the root of its anchor chain)
--                                           nudged in by its overlap and RAIL_GAP; returns the nudge (dx, dy).
--                                           `axis`: "x" sideways only, "y" up only (nil: both); `point`: that one
--                                           anchor of `move` alone (a region hung by two corners, "y": its bottom edge
--                                           up off the bottom rail, the region shorter, its top kept); `key`: the
--                                           nudge's own key ("rails" by default) -- a second call on one region with
--                                           another key adds to the first (a scroll bar moved in sideways, then
--                                           shortened off the bottom rail)
--   Kit:RailEdges(windowRep)                the rails' inner edges in screen units -- the left rail's right, the right
--                                           rail's left, the bottom rail's top (nil each without it; all nil when the
--                                           rails do not lie over the content or are not shown): ClearRails' measure,
--                                           for a panel whose content has a margin of its own; RAIL_GAP as Kit.RAIL_GAP
--   Kit:AlignBeside(region, beside, move)   `region`'s centre line onto `beside`'s, by nudging `move` (region; or
--                                           the root of its anchor chain)
--   Kit:Shrink(region, key, dw, dh)         a region the game sizes itself (one anchor and its own size) `dw` / `dh`
--                                           narrower / shorter for `key` (0, 0: gone); its size as the game set it
--                                           kept here and put back when its last shrink goes
--   Kit:ShrinkTaken(region, side)           a game function sized it again: its new size taken as the game's
--                                           (`side` "w" / "h": the game set that side alone -- the professions'
--                                           schematic, its width per recipe -- the other kept as the game's)
--------------------------------------------------------------------------------
local nudges = setmetatable({}, { __mode = "k" })   -- [region] = { points = the game's anchors, offs = { [key] = { dx, dy, point } } }
local shrinks = setmetatable({}, { __mode = "k" })  -- [region] = { w, h = the game's size, offs = { [key] = { dw, dh } } }
local RAIL_GAP = 4
Kit.RAIL_GAP = RAIL_GAP

local function PointsOf(region)
	local points = {}
	for i = 1, region:GetNumPoints() do
		local p = { region:GetPoint(i) }
		if Secret(p[4]) or Secret(p[5]) then
			return nil
		end
		points[i] = p
	end
	return points
end

local function NudgeLay(region, n)
	region:ClearAllPoints()
	for _, p in ipairs(n.points) do
		local dx, dy = 0, 0
		for _, o in pairs(n.offs) do
			if not o[3] or o[3] == p[1] then
				dx, dy = dx + o[1], dy + o[2]
			end
		end
		region:SetPoint(p[1], p[2], p[3], (p[4] or 0) + dx, (p[5] or 0) + dy)
	end
end

function Kit:Nudge(region, key, dx, dy, point)
	dx, dy = dx or 0, dy or 0
	local n = nudges[region]
	if not n then
		if dx == 0 and dy == 0 then
			return
		end
		local points = PointsOf(region)
		if not points then
			return
		end
		n = { points = points, offs = {} }
		nudges[region] = n
	end
	n.offs[key] = (dx ~= 0 or dy ~= 0) and { dx, dy, point } or nil
	NudgeLay(region, n)
	if not next(n.offs) then
		nudges[region] = nil
	end
end

function Kit:NudgeTaken(region)
	local n = nudges[region]
	local points = n and PointsOf(region)
	if points then
		n.points = points
		NudgeLay(region, n)
	end
end

-- (a region's edges in screen units: left, bottom, right, top; nil where unreadable)
local ScreenRect = MelloUI.Safe.ScreenRect

function Kit:RailEdges(rep)
	local parts = rep and rep.rule and rep.rule.railOver and rep.skin
	local r, b, l = parts and rawget(parts, "r"), parts and rawget(parts, "b"), parts and rawget(parts, "l")
	if not (r and r:IsVisible()) then
		return nil
	end
	local _, _, lr = ScreenRect(l or r)
	local rl = ScreenRect(r)
	local _, _, _, bt = ScreenRect(b or r)
	return l and lr or nil, rl, b and bt or nil
end

function Kit:ClearRails(rep, region, move, axis, point, key)
	move, key = move or region, key or "rails"
	self:Nudge(move, key, 0, 0)   -- (measured where the game puts it)
	local lr, rl, bt = self:RailEdges(rep)
	if not ((lr or rl or bt) and region:IsVisible()) then
		return 0, 0
	end
	local L, B, R = ScreenRect(region)
	if not L then
		return 0, 0
	end
	local dx, dy = 0, 0
	if axis ~= "y" then
		if rl and R > rl - RAIL_GAP then
			dx = (rl - RAIL_GAP) - R
		elseif lr and L < lr + RAIL_GAP then
			dx = (lr + RAIL_GAP) - L
		end
	end
	if axis ~= "x" and bt and B < bt + RAIL_GAP then
		dy = (bt + RAIL_GAP) - B
	end
	local s = Num(move:GetEffectiveScale()) or 1
	self:Nudge(move, key, dx / s, dy / s, point)
	return dx / s, dy / s
end

function Kit:AlignBeside(region, beside, move)
	move = move or region
	self:Nudge(move, "beside", 0, 0)
	local _, b1, _, t1 = ScreenRect(region)
	local _, b2, _, t2 = ScreenRect(beside)
	if not (t1 and t2) then
		return
	end
	local s = Num(move:GetEffectiveScale()) or 1
	self:Nudge(move, "beside", 0, ((t2 + b2) / 2 - (t1 + b1) / 2) / s)
end

-- One title on the plate (0.20.1; the user's screenshots, 2026-10-11: the macro window's and the tabard designer's
-- plates empty). A window that writes its title into a string of its own (the macro window's unnamed "Create Macros",
-- the tabard designer's TabardFrameNameText: the vendor's name), not the title container's TitleText, had that string
-- moved onto the plate -- but it stays a region of the window, under the plate that rides the rail. The words go into
-- the container's TitleText instead, the string every window's plate shows in the title face (its own text kept and
-- put back off; read again on every call: a vendor's name changes), and the strays give way. The caller refits the
-- plate after.
--   Kit:TitleWords(window, strays, on, fallback)   strays: the window's other title strings (the container's own left
--                                        out); `fallback`: words for a window that writes none anywhere (this client's
--                                        stable: the stable master's name, as the merchant's and the trainer's windows)
Kit.titleSavedOf = setmetatable({}, { __mode = "k" })    -- [container TitleText] = { text = its own } while written
Kit.titleStraysOf = setmetatable({}, { __mode = "k" })   -- [window] = { [string] = true } faded while on

function Kit:TitleWords(window, strays, on, fallback)
	local tc = window and window.TitleContainer
	local own = tc and tc.TitleText
	if not on then
		for fs in pairs(Kit.titleStraysOf[window] or {}) do
			Kit:Unfade(fs)
		end
		Kit.titleStraysOf[window] = nil
		local saved = own and Kit.titleSavedOf[own]
		if saved then
			own:SetText(saved.text or "")
			Kit.titleSavedOf[own] = nil
		end
		return
	end
	if not own then
		return
	end
	local function TextOf(fs)
		local ok, text = pcall(fs.GetText, fs)
		if ok and not Secret(text) and type(text) == "string" and text ~= "" then
			return text
		end
	end
	-- the container's own words stand unless they are ours (written before: taken again from the strays)
	if Kit.titleSavedOf[own] or not TextOf(own) then
		local words
		for _, fs in ipairs(strays or {}) do
			words = words or TextOf(fs)
		end
		if not words and type(fallback) == "string" and not Secret(fallback) and fallback ~= "" then
			words = fallback
		end
		if words then
			if not Kit.titleSavedOf[own] then
				local ok, text = pcall(own.GetText, own)
				Kit.titleSavedOf[own] = { text = (ok and not Secret(text)) and text or nil }
			end
			own:SetText(words)
		end
	end
	local faded = Kit.titleStraysOf[window] or {}
	Kit.titleStraysOf[window] = faded
	for _, fs in ipairs(strays or {}) do
		if fs ~= own and not faded[fs] then
			faded[fs] = true
			Kit:Fade(fs)
		end
	end
end

local function ShrinkLay(region, n)
	local sw, sh = 0, 0
	for _, o in pairs(n.offs) do
		sw, sh = sw + o[1], sh + o[2]
	end
	region:SetSize(math.max(1, n.w - sw), math.max(1, n.h - sh))
end

function Kit:Shrink(region, key, dw, dh)
	dw, dh = dw or 0, dh or 0
	local n = shrinks[region]
	if not n then
		if dw == 0 and dh == 0 then
			return
		end
		local okW, w = pcall(region.GetWidth, region)
		local okH, h = pcall(region.GetHeight, region)
		if not (okW and okH) or Secret(w) or Secret(h) or not (w and h) then
			return
		end
		n = { w = w, h = h, offs = {} }
		shrinks[region] = n
	end
	n.offs[key] = (dw ~= 0 or dh ~= 0) and { dw, dh } or nil
	ShrinkLay(region, n)
	if not next(n.offs) then
		shrinks[region] = nil
	end
end

function Kit:ShrinkTaken(region, side)
	local n = shrinks[region]
	if not n then
		return
	end
	local okW, w = pcall(region.GetWidth, region)
	local okH, h = pcall(region.GetHeight, region)
	if okW and okH and not Secret(w) and not Secret(h) and w and h then
		-- (`side`: the game set that one alone; the other is still ours, its game size kept)
		if side ~= "h" then
			n.w = w
		end
		if side ~= "w" then
			n.h = h
		end
		ShrinkLay(region, n)
	end
end

