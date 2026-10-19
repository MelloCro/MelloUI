--------------------------------------------------------------------------------
-- MelloUI - Kit, the painted engine (one look, stage I: cut from
-- Modules/Kit.lua, the core look kit, which loads before it and makes
-- MelloUI.Kit)
--
-- The painted UI kit as building blocks for the panel modules: cap/mid/cap
-- strips with states, bars with a trough and a fill area, and the replacement
-- library (Kit.Replacements + Kit:Replace) that maps the game's art to those
-- blocks so a panel never chooses a piece itself. A replacement takes the
-- game art's rectangle, size, visibility AND place in the draw order (strata,
-- frame level, layer): check all of them before mapping. Also the slot
-- stones, the button looks, the tuning (Core/KitTuning.lua's overrides), the
-- shared window parts, the side tabs, the painted border kinds, the skin
-- helpers and the debug commands (`/kitdemo [scale]` shows every block in one
-- window). It only adds fields to MelloUI.Kit; the core's locals it uses come
-- from the core's private table Kit.__.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("KitPainted")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Secret = MelloUI.Safe.IsSecret

local Kit = MelloUI.Kit
-- the core's locals (Modules/Kit.lua's Kit.__)
local K = Kit.__
-- one handler for every object it is hooked on, wrapped once (user,
-- 2026-09-24: the shared handlers, low-risk steps only): this file's scope's,
-- or the core's where a scope has none (a test's world)
local Shared = Perf.Shared or K.Shared
local LAYOUT, PIECES, Kept, LOOK, EDGE_ROOT, SHADED, Slices, resolved, pressedLatches =
	K.LAYOUT, K.PIECES, K.Kept, K.LOOK, K.EDGE_ROOT, K.SHADED, K.Slices, K.resolved, K.pressedLatches
local PieceRoot, StripName, Slot_Update, FollowButton, RegisterShell, Tiled, NineSlice_Lay =
	K.PieceRoot, K.StripName, K.Slot_Update, K.FollowButton, K.RegisterShell, K.Tiled, K.NineSlice_Lay
local SliceUnit, SliceData, SliceFamily, SliceCut =
	K.SliceUnit, K.SliceData, K.SliceFamily, K.SliceCut

--------------------------------------------------------------------------------
-- Strip: cap_l + tiled mid + cap_r, all the same height, top-aligned.
--   Kit:Strip(parent, "buttons/textbtn", { state = "normal", width = 200, scale = })
-- strip:SetState("hover"); strip:SetWidth(w); strip.height
--------------------------------------------------------------------------------

local StripMixin = {}

-- Strip families drawn flat in the palette's colours instead of their pieces (0.20.1; the user's pick E of
-- MelloUI-BuildData/output/header_sketch, 2026-10-10: "E for everything" -- the header plate's gem caps "everywhere we use
-- it does not fit"): over the plate's painted box rows, the strip's whole width, `fill` at `alpha`, a 1 px `top` line
-- and a `footH` px `foot` line (Kit:Paint, painted again with the palette). The strip keeps its pieces' sizes -- every
-- place that fits, insets or centres text on it lays out as before -- and applies none of their art: no caps, no shade
-- partner (the shade follows art).
Kit.flatStrips = {
	["lists/header"] = { fill = "raisedPanel", alpha = 0.92, top = "border", foot = "selectedTrim", footH = 1.5 },
}

function StripMixin:SetState(state)
	if state == self.state and self.applied then
		return
	end
	self.state, self.applied = state, true
	if self.flatLook then
		self:FlatLay()
	else
		Kit:Apply(self.capL, StripName(self.base, self.endL and "end_l" or "cap_l", state))
		Kit:Apply(self.mid, StripName(self.base, "mid", state))
		Kit:Apply(self.capR, StripName(self.base, self.endR and "end_r" or "cap_r", state))
	end
	self:SyncActive()
end

-- A flat strip's band (Kit.flatStrips), made on its first lay as regions where the pieces would be (the owner's, in
-- the mid's layer), laid on the painted box at the strip's scale; shown as the strip is (an owner's: by its Show / Hide)
function StripMixin:FlatLay()
	local look = self.flatLook
	local parts = rawget(self, "flatParts")
	if not look then
		if parts then
			for i = 1, #parts do
				parts[i]:Hide()
			end
		end
		return
	end
	if not parts then
		local host = self.kitOwner or self
		local layer, sub = self.mid:GetDrawLayer()
		sub = sub or 0
		parts = { host:CreateTexture(nil, layer, nil, sub), host:CreateTexture(nil, layer, nil, math.min(sub + 1, 7)),
			host:CreateTexture(nil, layer, nil, math.min(sub + 1, 7)) }
		Kit:Paint(parts[1], look.fill, "fill", look.alpha or 1)
		Kit:Paint(parts[2], look.top, "fill", 1)
		Kit:Paint(parts[3], look.foot, "fill", 1)
		self.flatParts = parts
	end
	local sc = self.scale or Kit.scale
	local mid = PIECES[StripName(self.base, "mid", self.state)]
	local t = (mid and mid.box) and mid.box[2] * sc or 0
	local b = (mid and mid.box) and (mid.h - mid.box[4]) * sc or 0
	local fill, top, foot = parts[1], parts[2], parts[3]
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -t)
	fill:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, b)
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", fill, "TOPLEFT")
	top:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, -1)
	foot:ClearAllPoints()
	foot:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, look.footH or 1)
	foot:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	local on = not self.capsOff and (not self.kitOwner or self:IsShown())
	for i = 1, #parts do
		parts[i]:SetShown(on)
	end
end

-- A list's selected plate (a strip in its "selected" state) wears the active
-- look (Kit:SetActive, 0.15.0) round the strip: regions of the strip frame,
-- shown and hidden with it, or with an `owner` of the frame its pieces are
-- regions of (a row: over its plate), then following the strip's own Show /
-- Hide. Only a strip that was selected turns it off (a row's plain and hover
-- plates share its owner with the selected one)
function StripMixin:SyncActive()
	local on = self.state == "selected"
	if not (on or self.activeWas) then
		return
	end
	local owner = self.kitOwner
	if owner then
		on = on and self:IsShown()
	end
	self.activeWas = on or nil
	-- (0.20.1: round the strip's painted box, not its canvas -- the user, in the character window's reputations: the
	-- ring stood off the selected plate by the canvas's clear rows)
	Kit:SetActive(owner or self, on, self:PaintedBox(), "rect")
end

-- (0.20.1) The strip's PAINTED box -- the mid's box rows, the kept caps' outer box columns -- as an empty region of
-- the strip frame's own, made once and laid again at each ask: what the active look lies round
function StripMixin:PaintedBox()
	local box = rawget(self, "paintedBox")
	if not box then
		box = self:CreateTexture()
		self.paintedBox = box
	end
	local sc = self.scale or Kit.scale
	local mid = PIECES[StripName(self.base, "mid", self.state)]
	local capL = not self.noL and PIECES[StripName(self.base, self.endL and "end_l" or "cap_l", self.state)]
	local capR = not self.noR and PIECES[StripName(self.base, self.endR and "end_r" or "cap_r", self.state)]
	local t = (mid and mid.box) and mid.box[2] * sc or 0
	local b = (mid and mid.box) and (mid.h - mid.box[4]) * sc or 0
	local l = (capL and capL.box) and capL.box[1] * sc or 0
	local r = (capR and capR.box) and (capR.w - capR.box[3]) * sc or 0
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", self, "TOPLEFT", l, -t)
	box:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -r, b)
	return box
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
	-- (to or from a flat family: its band laid or put away; a piece family's art applied by SetState)
	self.flatLook = Kit.flatStrips[base]
	if not self.flatLook then
		self:FlatLay()
	end
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
	if self.flatLook then
		self:FlatLay()   -- (its band on the painted box at the new scale)
	end
	-- the parts' shadow partners reach as far at the new scale (Kit:Shadow)
	if self.capL.kitShadow or self.mid.kitShadow or self.capR.kitShadow then
		Kit:ShadowFit(self.capL)
		Kit:ShadowFit(self.mid)
		Kit:ShadowFit(self.capR)
	end
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
	-- (the caps' shadow partners follow their Show / Hide; the mid's, made
	-- with opts.ends, takes a soft end where it now runs to the strip's end,
	-- below)
	self.capless, self.noL, self.noR = capless, noL, noR
	-- a dropped cap closes with the family's gemless end piece
	-- (<base>_end_l/r_<state>, made by Tools/make_plain_plate.py) when it has one
	local endL = noL and not capless and not self.flatLook and PIECES[StripName(self.base, "end_l", self.state)]
	local endR = noR and not capless and not self.flatLook and PIECES[StripName(self.base, "end_r", self.state)]
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
	self.capL:SetShown(not self.capsOff and (not noL or endL))   -- (0.20.1: capsOff, see Kit:Strip's Show)
	self.capR:SetShown(not self.capsOff and (not noR or endR))
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", self, "TOPLEFT", (noL and not endL) and 0 or wl, 0)
	self.mid:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", (noR and not endR) and 0 or -wr, 0)
	-- the mid's size as laid out, for a Retile that cannot read it back
	if width and width > 0 then
		self.mid.kitTileW = width - ((noL and not endL) and 0 or wl) - ((noR and not endR) and 0 or wr)
		self.mid.kitTileH = self.height
	end
	Kit:Retile(self.mid)
	-- the mid's ends with no cap and no end piece: its shadow partner (one
	-- made with opts.ends) fades out softly there instead of stopping square
	-- (Kit:Shadow)
	self.mid.kitOpenL = (noL and not endL) and true or false
	self.mid.kitOpenR = (noR and not endR) and true or false
	if self.mid.kitShadow then
		Kit:ShadowFit(self.mid)
	end
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
	f.flatLook = self.flatStrips[base]   -- (drawn flat: Kit.flatStrips)

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
		f.kitOwner = opts.owner   -- (its active look is the owner's regions: StripMixin:SyncActive)
		-- (0.20.1: `capsOff` -- a library border standing in for the bracket, KitBorders' BarLibraryBorder -- keeps the
		-- three pieces off through every Show)
		f.Show = function(self)
			show(self)
			local on = not self.capsOff
			self.capL:SetShown(on and (not self.noL or self.endL))
			self.mid:SetShown(on)
			self.capR:SetShown(on and (not self.noR or self.endR))
			if self.flatLook then
				self:FlatLay()
			end
			self:SyncActive()
		end
		f.Hide = function(self)
			hide(self); self.capL:Hide(); self.mid:Hide(); self.capR:Hide()
			local parts = rawget(self, "flatParts")
			if parts then
				for i = 1, #parts do
					parts[i]:Hide()
				end
			end
			self:SyncActive()
		end
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
	Perf.SetScript(f, "OnSizeChanged", function(self)
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
	-- the parts' shadow partners reach as far at the new scale (as a Strip's)
	if self.capT.kitShadow or self.mid.kitShadow or self.capB.kitShadow then
		Kit:ShadowFit(self.capT)
		Kit:ShadowFit(self.mid)
		Kit:ShadowFit(self.capB)
	end
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
	Perf.SetScript(f, "OnSizeChanged", function(self)
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
--   bar:SetBarScale(scale)   (0.21.0, the Personal Display's Height) the whole
--       bar at another scale in place: the strip, its height, the opening,
--       the trough (no frame made again)
--   bar:SetBarLook(kind)     (0.21.0, the Personal Display's Personal Resource
--       Border) another bracket look in place (bars/<kind>_*: StripMixin:SetBase),
--       the opening and the trough laid again at its scale
--------------------------------------------------------------------------------

-- (in a block of its own: Kit.lua is at Lua 5.1's 200 top-level locals)
do
-- the opening from inside the left cap's hollow arm to inside the right one, at the strip's scale; the trough under it
local function BarLay(strip)
	local scale = strip.scale
	local _, _, top, bottom = strip:GetInsets()
	local capL, capR = PIECES[strip.base .. "_cap_l"], PIECES[strip.base .. "_cap_r"]
	local left = capL and capL.open and capL.open[1] * scale or strip.wl
	local right = capR and capR.open and (capR.w - capR.open[3]) * scale or strip.wr
	local fill, trough = strip.fill, strip.trough
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", left, -top)
	fill:SetPoint("BOTTOMRIGHT", -right, bottom)
	trough.kitScale = scale
	trough:ClearAllPoints()
	trough:SetPoint("TOPLEFT", -2 * scale, 0)
	trough:SetPoint("BOTTOMRIGHT", 2 * scale, 0)
	Kit:Retile(trough)
end

local function BarSetScale(strip, scale)
	if not scale or scale <= 0 then
		return
	end
	strip:Rescale(scale)
	strip:SetHeight(strip.height)
	BarLay(strip)
end

local function BarSetLook(strip, kind)
	strip:SetBase("bars/" .. kind)
	strip:SetHeight(strip.height)
	BarLay(strip)
end

function Kit:Bar(parent, opts)
	opts = opts or {}
	local kind = opts.kind or "frame"
	local scale = opts.scale or self.scale
	local base = "bars/" .. kind
	local strip = self:Strip(parent, base, { width = opts.width, scale = scale, layer = "ARTWORK", sublevel = 2 })

	-- frame art two levels above the fill, so a StatusBar parented to `fill`
	-- (one level above it) still draws under the rim
	local base_level = parent:GetFrameLevel()
	strip:SetFrameLevel(base_level + 3)
	local fill = CreateFrame("Frame", nil, strip)
	fill:SetFrameLevel(base_level + 1)
	strip.fill = fill

	local trough = fill:CreateTexture(nil, "BACKGROUND", nil, 0)
	trough.kitScale = scale
	self:Apply(trough, "bars/trough")
	strip.trough = trough
	strip.SetBarScale = BarSetScale
	strip.SetBarLook = BarSetLook
	BarLay(strip)
	Perf.SetScript(fill, "OnSizeChanged", function()
		Kit:Retile(trough)
	end)
	return strip
end
end

--------------------------------------------------------------------------------
-- VBar (0.21.0, the Personal Display's shield column; docs/plans/personal-display.md): Kit:Bar stood upright -- the
-- bracket's upright pieces (bars/<kind>v_cap_t / _mid / _cap_b: Tools/make_upright_bars.py turns the horizontal ones a
-- quarter left, the right cap on top) as a VStrip, the trough stood up under the opening (bars/trough_v) and `fill`, a
-- frame on the opening for an upright StatusBar. The opening is read from the horizontal pieces they were turned from
-- (an upright middle reads open end to end): across, the middle's open rows; down, the right cap's solid arm on top
-- and the left cap's at the bottom. The strip is meant at least two caps tall (a VStrip shrinks its caps below that).
--   Kit:VBar(parent, { kind = "frame", width = (UI px across the bracket), scale = })
--   bar:SetBarLook(kind, width)   (0.21.0, the Personal Resource Border) another bracket look in place, `width`
--       across (the last one given when nil; its upright pieces bars/<kind>v_*; false when the look has none)
--------------------------------------------------------------------------------

-- (in a block of its own, as Kit:Bar's: Kit.lua is at Lua 5.1's 200 top-level locals)
do
-- the opening read from the horizontal pieces of `kind`, at the strip's scale; the trough under it
local function VBarLay(strip, kind)
	local scale = strip.scale
	local mid, capL, capR = PIECES["bars/" .. kind .. "_mid"], PIECES["bars/" .. kind .. "_cap_l"], PIECES["bars/" .. kind .. "_cap_r"]
	local left = mid and mid.open and mid.open[2] * scale or 0
	local right = mid and mid.open and (mid.h - mid.open[4]) * scale or 0
	local top = capR and capR.open and (capR.w - capR.open[3]) * scale or 0
	local bottom = capL and capL.open and capL.open[1] * scale or 0
	local fill, trough = strip.fill, strip.trough
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", left, -top)
	fill:SetPoint("BOTTOMRIGHT", -right, bottom)
	strip.insets = { left, right, top, bottom }
	trough.kitScale = scale
	trough:ClearAllPoints()
	trough:SetPoint("TOPLEFT", 0, 2 * scale)
	trough:SetPoint("BOTTOMRIGHT", 0, -2 * scale)
	Kit:Retile(trough)
end

local function VBarSetLook(strip, kind, width)
	if not PIECES["bars/" .. kind .. "v_cap_t"] then
		return false
	end
	strip.across = width or strip.across
	if strip.kind ~= kind then
		strip.kind = kind
		strip.base = "bars/" .. kind .. "v"
		strip.applied = nil
		strip:SetState(strip.state)
	end
	if strip.across then
		strip:FitWidth(strip.across)
	end
	VBarLay(strip, kind)
	return true
end

function Kit:VBar(parent, opts)
	opts = opts or {}
	local kind = opts.kind or "frame"
	local strip = self:VStrip(parent, "bars/" .. kind .. "v", { scale = opts.scale, layer = "ARTWORK", sublevel = 2 })
	strip.kind, strip.across = kind, opts.width
	if opts.width then
		strip:FitWidth(opts.width)
	end
	-- (as Kit:Bar: the frame art two levels above the fill, a StatusBar on `fill` under the rim)
	local baseLevel = parent:GetFrameLevel()
	strip:SetFrameLevel(baseLevel + 3)
	local fill = CreateFrame("Frame", nil, strip)
	fill:SetFrameLevel(baseLevel + 1)
	strip.fill = fill
	local trough = fill:CreateTexture(nil, "BACKGROUND", nil, 0)
	self:Apply(trough, "bars/trough_v")
	strip.trough = trough
	strip.SetBarLook = VBarSetLook
	VBarLay(strip, kind)
	Perf.SetScript(fill, "OnSizeChanged", function()
		Kit:Retile(trough)
	end)
	return strip
end
end

-- A flat control's opening (rep:GetOpening, as a bar's): its face is the whole rect
local function FlatOpening()
	return 0, 0, 0, 0
end

-- A flat control's button greyed out (FLAT_OFF) as it is: its Enable /
-- Disable read again (the rims follow SetEnabled alone; a panel button
-- turned off with Disable kept its lit plate -- one handler for all)
local flatButtons = setmetatable({}, { __mode = "k" })   -- [button] = { its flat reps' drivers }
local FlatButton_Enabled = Shared("Enable / Disable on a kit flat control's button", function(button)
	local list = flatButtons[button]
	if list then
		for i = 1, #list do
			Slot_Update(list[i])
		end
	end
end, "hook")

-- A flat arrow over art the game turns (a rule's `rotates`: the bag bar's
-- arrow): SetRotation's angle, a quarter turn counter-clockwise at a time
-- from the art's own way (the rule's `dir`), lays the arrow's lines again
local FLAT_TURNS = { "left", "down", "right", "up" }   -- each a quarter turn counter-clockwise from the one before
local FLAT_TURN_OF = { left = 0, down = 1, right = 2, up = 3 }
local flatTurns = setmetatable({}, { __mode = "k" })   -- [the game's art] = the flat arrow's parts
local FlatArrow_Turn = Shared("SetRotation on a kit flat arrow's art", function(region, angle)
	local parts = flatTurns[region]
	if not parts or type(angle) ~= "number" or Secret(angle) then
		return
	end
	local q = (math.floor(angle / (math.pi / 2) + 0.5) + (parts.turnFrom or 0)) % 4
	MelloUI.Widgets.FlatDir(parts, FLAT_TURNS[q + 1])
end, "hook")

-- A flat edit box's field (the "flat" kind): its edge in `trim` while it has
-- the keyboard, as the Configurator's search box's (one handler for all)
local flatFields = setmetatable({}, { __mode = "k" })   -- [edit box] = its flat rep's driver
local FlatField_Focus = Shared("OnEditFocusGained / Lost on a kit flat field", function(edit)
	local driver = flatFields[edit]
	if driver then
		local ok, focus = pcall(edit.HasFocus, edit)
		driver.flatFocus = (ok and not Secret(focus) and focus) and true or nil
		Slot_Update(driver)
	end
end, "script")

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
--           `natural` keeps the kit's own weight instead (Kit:StripWeight: every
--           divider line, one thickness in every window), across the rect, or
--           with `widthFrac` that fraction of it, centred (a thin line inside a
--           large glow atlas);
--           `heightScale` multiplies the fitted height (the width stays the rect's)
--   slot    the slot rim on a button (`slot` = "slot" | "roundslot"); `under`
--           puts it below the button's icon and quality border, as the game's
--           slot picture is (equipment); without it the rim is over the icon (tabs);
--           `rest` fixes the rim's look (e.g. "checked" = the gold rim on every
--           tab, as the game's tab art is) and `glow` adds the same rim
--           additively for the hovered (0.35) button, standing in for the
--           game's TabGlow / Highlight; the selected one wears the active
--           look (Kit:SetActive) for the game's SelectedTexture
--   state   a state texture on a button (`base`), e.g. the close button;
--           `natural` keeps the kit size centred on the rect, `layer` its
--           draw layer (OVERLAY unless the game's icon must stay on top)
--   flat    (0.19.1) a control in the Configurator's flat look (`flat` =
--           button / check / dropdown / edit / close / arrow (`dir`) / plus /
--           minus / cog / tab / tabActive / track / thumb / slider / knob; the
--           check, close, arrows, + / -, cog and an icon button's plate the
--           kit's NewUI2 pieces, 0.19.9:
--           W.FlatOver's parts on a holder on the rect, painted by its state
--           as the rims are; `rect = "normal"` the button's normal texture's
--           rect); opts.left an edit box's fill reaching left over its glass,
--           opts.body = false the edge alone, opts.fitHeight a centred height;
--           `glyph` (0.20.1) a + / - / arrow always its bare glyph, never on
--           its plate (the Legacy cards' +, the user's pick)
--   active  the active look alone (Kit:SetActive) on a check button the kit
--           does not dress, while it is checked; `active = true` on a rule
--           of another kind puts the active look round its piece whenever
--           the piece shows (the open tab's card)
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
--           `natural`: the kit size, centred on the rect or opts.center; `body`
--           with `square`: the piece sized so its round body is that piece's
--           on the rect -- a ring with wings reaches past it)
--   tile    a repeatable tile (`piece`) filling the rect at its native scale
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
	["UI-Frame-PortraitMetal-CornerTopLeft"]  = { kind = "texture", piece = "rings/r5", square = true, body = "window/portrait_ring", level = 1 },   -- (0.19.9, the user's pick 4c 2026-10-08) the NewUI2 winged border (Tools/make_newui2_glyphs.py), its ring body the gem ring's on the rect, its wings past it; the minimap, the crest and the unit frames keep window/portrait_ring
	-- the configurator's crest and the short plate under it (approved sketch,
	-- 2026-09-24; Kit:OwnWindow, Modules/KitWindow.lua): the portrait ring
	-- centred on the top rail's middle line with the emblem on its disc, and
	-- the title plate without `onRail`. Keys of their own, so neither is taken
	-- for a window's corner ring or title plate (Kit.shells keeps them as
	-- crest / plate, for their shade only: never a drag handle, nothing cut
	-- by TitleBehindRing)
	["MelloUI-Crest"]                         = { kind = "texture", piece = "window/portrait_ring", square = true, level = 1 },
	["MelloUI-TitlePlate"]                    = { kind = "strip", base = "tabs/top", state = "open", heightScale = 1.5 },
	["RedButton-Exit"]                        = { kind = "flat", flat = "close", rect = "normal" },   -- (0.19.1) flat: the close button (was the red cross)
	-- inset frames and backdrops
	["common-insideframe"]                    = { kind = "frame", dim = 0.8 },   -- an inset: single rail + stone, the stone under the palette's inner panel (no eye strain, WINDOW-RULES 2e)
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
	-- (0.20.1) every divider line at the kit's own weight (`natural`), whatever its atlas's height
	["UI-Character-Info-ScrollLine"]          = { kind = "strip", base = "window/divider", natural = true },
	["UI-Character-Info-ScrollLine-Long"]     = { kind = "strip", base = "window/divider", natural = true },
	-- a thin line inside a big soft-glow atlas: the atlas box says nothing about
	-- the line, so the divider keeps its natural kit size and spans half the box
	-- (0.20.1, the user: "on the PVP tab where it stands above "Civilian" its missing its middle") two levels up, over
	-- the honor ring's frame: that frame's big soft glow (275 x 295, from the ring up past the line) hid the middle
	["UI-Character-Info-Honor-LevelBG"]       = { kind = "strip", base = "window/divider", natural = true, widthFrac = 0.5, level = 2 },
	["UI-Character-Info-Title"]               = { kind = "strip", base = "lists/header" },
	["UI-Character-Info-ItemLevel-Bounce"]    = { kind = "strip", base = "lists/header" },
	["UI-Character-Info-Line-Bounce"]         = { kind = "strip", base = "lists/plate", state = "plain" },   -- a plain line in the game: the gemless plate
	["UI-Character-Info-Line-Bounce2"]        = { kind = "strip", base = "lists/plate", state = "plain" },
	["common-button-list-collapseExpand"]     = { kind = "strip", base = "lists/catplate", state = "closed" },   -- the plain category plate: one texture, no chevron (the game's +/- glyph stays)
	["QuestHeadingChat"]                      = { kind = "fade" },   -- (0.24.0, the chat's look: the user's pick 2A / 2B, 2026-10-15) a quest header's plate in the quest log and the Quests panel (as = this; the atlas common-button-list-collapseExpand): faded, the chat's heading drawn by QuestLogPanel (its name in the title face, a hairline under it)
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
	["checkbox-minimal"]                      = { kind = "flat", flat = "check" },   -- (0.19.1) flat: a check box (was the kit's)
	-- scroll bars (user, 2026-09-21: T2 / H1 / S1 is THE scroll bar, the only
	-- look for every MinimalScrollBar): the dark trough as the track, the gem
	-- slab thumb stretching with the content, the kit arrow buttons as steppers
	["minimal-scrollbar-track-middle"]        = { kind = "flat", flat = "track", level = -1 },   -- (0.19.1) flat: a scroll bar's track (was T2's trough)
	["minimal-scrollbar-small-thumb-middle"]  = { kind = "flat", flat = "thumb", level = 0 },   -- (0.19.1) flat: its thumb (was H1's slab)
	["minimal-scrollbar-arrow-top"]           = { kind = "flat", flat = "arrow", dir = "up" },   -- (0.19.1) flat: a scroll bar's up stepper (was S1's arrow)
	["minimal-scrollbar-arrow-bottom"]        = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: ... its down stepper
	-- progress bars (user, 2026-09-21: P1): the hollow bar bracket with the
	-- trough in its opening, under the game's tinted fill and its text
	["common-stat-bar-BG"]                    = { kind = "bar", bar = "frame", heightScale = 0.85 },   -- the character pane's skill / reputation bars: P1 at 0.85 of the bar's height (user, 2026-09-21: the borders 15 % smaller), the fill fitted into the smaller opening by the panel
	-- list glyphs (user, 2026-09-21: consistency — every check box, expand /
	-- collapse control and toggle in a window is the kit's): the +/- plates
	-- on the glyph's rect, the plus for a collapsed header, the minus for an open one
	["common-button-list-plus"]               = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: a list's expand (was the kit's +)
	["common-button-list-minus"]              = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ... collapse (was the kit's -)
	["campaign_headericon_closed"]            = { kind = "flat", flat = "plus", rect = "normal" },   -- (0.19.1) flat: a sub-header's toggle, closed (was the kit's +)
	["campaign_headericon_open"]              = { kind = "flat", flat = "minus", rect = "normal" },   -- (0.19.1) flat: ... open
	-- the character window's equipment manager
	["UI-Character-Info-OutfitCard"]          = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 0 },   -- an outfit card: the gemless plate ...
	["UI-Character-Info-OutfitCard-Hover"]    = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- ... its hover (shown / hidden by the game)
	["UI-Character-Info-OutfitCard-Selected"] = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... its selected bar (likewise)
	["common-button-tertiary-normal"]         = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8 },   -- (0.19.1) the red plate again, gemless (B1; user, 2026-10-04: "no more diamonds on the sides"; was flat for a day): New Set, the game's + icon and text on top
	-- the spell book (user's picks, 2026-09-21: P1 C1 H3 K1 T1); the talents
	-- page stays the game's until the user's per-class art arrives
	-- The PAGES (user, 2026-09-23: backgrounds keep one resolution, never
	-- stretched): the painted page pictures are gone from them; the stone
	-- pages repeat tiles/concrete (the page stone's own middle), the paper
	-- pages tiles/vellum (the parchment page's middle), from the rect's
	-- middle or top (`crop`), their painted edges as before.
	["spellbook-Page-Right-C60"]              = { kind = "picture", piece = "tiles/vellum", crop = "middle", level = -1, parchment = "br" },   -- (0.20.1: the parchment nine, its curl at the bottom right)   -- the book page: the user's parchment page painting (parchmentnew, 2026-09-21; painted at the page's 1.15 aspect), one UNDER the SpellBookFrame (level 100: well above the window's skin, below every control on the page)
	["spellbook-Page-Left-C60"]               = { kind = "picture", piece = "tiles/vellum", crop = "middle", level = -1, parchment = "tl", edgeMirror = true },   -- (0.20.1: the parchment nine, its curl at the top left: a spread's two outer corners; 0.20.3: the Classic style's strokes mirrored)   -- the left page's strokes flipped, so the two pages are not twins
	["spellbook-Tab-Frame-C60"]               = { kind = "slot", slot = "slot" },   -- a category tab (C1): the slot rim over the icon, gold (checked) while the tab is selected
	["spellbook-list-backplate"]              = { kind = "fade" },   -- the list header's backplate (H3: the text on the page)
	["spellbook-divider"]                     = { kind = "strip", base = "window/divider", natural = true },   -- the line under the header (H3)
	["spellbook-item-backplate"]              = { kind = "fade" },   -- a spell card: no plate (user re-picked K4 from K1 on sight), the rim and text on the page
	["spellbook-item-iconframe"]              = { kind = "slot", slot = "slot" },   -- an active spell's icon frame: the square rim
	["spellbook-item-iconframe-inactive"]     = { kind = "slot", slot = "slot" },
	["spellbook-item-iconframe-passive"]      = { kind = "slot", slot = "roundslot" },   -- a passive's: the round rim (the icon is round)
	["spellbook-item-iconframe-passive-inactive"] = { kind = "slot", slot = "roundslot" },
	["talents-node-circle-gray"]              = { kind = "slot", slot = "roundslot" },   -- what this client puts on a passive spell's icon
	["uiframe-tab-left"]                      = { kind = "flat", flat = "tab", level = -1 },   -- (0.19.1) flat: a window's tab at rest (was TB6)
	["uiframe-activetab-left"]                = { kind = "flat", flat = "tabActive", level = -1, active = true },   -- (0.19.1) flat: the open tab (was TB6 lit gold); `active`: the active look round it, as the Configurator's open tab
	["common-dropdown-a-button"]              = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: the small round dropdown arrow (was K2's cog under it)
	["common-dropdown-a-button-shadowless"]   = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: ... without its shadow (was the kit's arrow)
	-- (0.20.1, the user's pick A: "Steel, like close") the title bar's buttons on one steel plate
	["RedButton-Expand"]                      = { kind = "flat", flat = "titlearrow", dir = "up", rect = "normal" },   -- (0.19.1) flat: the window's maximize (was the kit's arrow)
	["RedButton-Condense"]                    = { kind = "flat", flat = "titlearrow", dir = "down", rect = "normal" },   -- (0.19.1) flat: ... minimize
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
	["Professions-background-summarylist"]    = { kind = "frame", dim = 0.8 },   -- the recipe list box (L1): single rail, stone body under the palette's inner panel (no eye strain, WINDOW-RULES 2e)
	["common-search-border-middle"]           = { kind = "flat", flat = "edit" },   -- (0.19.1) flat: a search box / the quantity box (was S1 / N1; a search box's fill over its glass: Kit:SkinSearchBox's opts.left)
	["common-dropdown-b-button"]              = { kind = "flat", flat = "dropdown", level = -1 },   -- (0.19.1) flat: a filter dropdown (was B6)
	["_128-RedButton-Center"]                 = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8 },   -- (0.19.1) the red plate again, gemless (B1, user 2026-10-04): the plate at the button's height, its closed ends on the button's (no gem caps reaching past them now)
	["_128-RedButton-Center-Disabled"]        = { kind = "strip", base = "buttons/redbtn", state = "disabled", owner = true, heightScale = 0.8 },
	["UI-SpellbookIcon-PrevPage-Up"]          = { kind = "flat", flat = "arrow", dir = "left" },   -- (0.19.1) flat: a spinner's / pager's back arrow (was the kit's)
	["UI-SpellbookIcon-NextPage-Up"]          = { kind = "flat", flat = "arrow", dir = "right" },   -- (0.19.1) flat: ... its forward arrow
	["Professions-Slot-Frame"]                = { kind = "slot", slot = "slot" },   -- a reagent slot's frame over its icon (R1)
	["auctionhouse-itemicon-border-white"]    = { kind = "slot", slot = "roundslot" },   -- the output icon's quality-coloured border (O2, user 2026-09-21): the round rim, tinted like the border
	["AuctionHouseBackgroundTemplate"]        = { kind = "frame", owner = true, bodyLayer = "BACKGROUND", bodySub = 1, edgeLayer = "BORDER", dim = 0.8 },   -- an auction house box (a Background picture + an inset NineSlice at the box's level; keyed by hand, its atlas differs per box): L1, the single rail with the list-box stone under the inner panel (2e), as REGIONS of the box, so the stone always lies under the box's scroll box and rows (user, 2026-09-24)
	["common-button-tertiary-square-normal"]  = { kind = "flat", flat = "button" },   -- (0.19.1) flat: a square icon button's plate (was K2's cog)
	["Professions_Recipe_Hover"]              = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a region of the row under its text (the game's translucent hover is HIGHLIGHT over it)
	["Professions_Recipe_Active"]             = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },
	["Professions-skillbar-bg"]               = { kind = "bar", bar = "frame", layer = "ARTWORK", sublevel = 4 },   -- the crafting page's rank bar: the same P1 as the book's
	["Profession-ProgressBar-BG"]             = { kind = "bar", bar = "frame", layer = "ARTWORK", sublevel = 4 },   -- the rank bars (P1): the masked fill is ARTWORK 2, so the bracket's caps go to 4 and its middle (one below the caps) to 3, both over the fill
	-- shared controls met in the legacy / quest log / guild windows (2026-09-21)
	["UI-Panel-Button-Up"]                    = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8 },   -- (0.19.1) the red plate again, gemless (B1, user 2026-10-04): UIPanelButtonTemplate (Left / Middle / Right file pieces; keyed by hand, file textures read back as ids)
	["UI-CheckBox-Up"]                        = { kind = "flat", flat = "check" },   -- (0.19.1) flat: the classic check box (keyed by hand; was the kit's)
	["questlog-icon-ticksquare"]              = { kind = "flat", flat = "check" },   -- (0.19.1) flat: the quest log's tracking tick box (was the kit's)
	["ui-journeys-delve-arrow-small-left"]    = { kind = "flat", flat = "arrow", dir = "left", rect = "normal" },   -- (0.19.1) flat: a reward track's arrow (was the kit's)
	["ui-journeys-delve-arrow-small-right"]   = { kind = "flat", flat = "arrow", dir = "right", rect = "normal" },   -- (0.19.1) flat: ...
	["128-redbutton-plus"]                    = { kind = "flat", flat = "plus", glyph = true },   -- (0.19.1) flat: a card's expand glyph (was the kit's +); 0.20.1 `glyph`: always the bare gold + (the user's pick, 2026-10-10: the Legacy cards' 20 px + wore the plate on some)
	["128-redbutton-minus"]                   = { kind = "flat", flat = "minus", glyph = true },   -- (0.19.1) flat: ...
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
	["QuestLog-main-background"]              = { kind = "picture", piece = "tiles/vellum", crop = "middle", owner = true, parchment = "tl br", edgeBacking = "window/single_body" },   -- (0.20.1: the parchment nine with both curls; no stone backing: its square showed round the curls' fold -- the window behind shows there, as on the pack's page; 0.20.3: the backing the Classic style's only)   -- the list's page (QP2, user 2026-09-21): the parchment page painting, as the spell book's; also MelloUI's own quest list window
	["QuestDetailsBackgrounds"]               = { kind = "picture", piece = "tiles/vellum", crop = "top", owner = true, parchment = "tl br", edgeBacking = "window/single_body" },   -- (0.20.1: the parchment nine with both curls; no stone backing: its square showed round the curls' fold -- the window behind shows there, as on the pack's page; 0.20.3: the backing the Classic style's only)   -- a quest's details page: the same parchment
	-- the quest giver's dialogs (QuestDialogPanel; user, 2026-09-24): an item / reward / spell button's name plate (file art, keyed by hand) -> the plain gemless plate under the name, as a list row's; the greeting's horizontal break -> the scroll line at its natural weight across most of the page
	["UI-QuestItemNameFrame"]                 = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },
	["UI-HorizontalBreak"]                    = { kind = "strip", base = "window/divider", natural = true, widthFrac = 0.8 },
	["MapTitleBand"]                          = { kind = "picture", piece = "tiles/concrete", crop = "top", level = 0 },   -- an agreed addition (user, 2026-09-21): a body-off window's title band (the map for its canvas; the collections and LFG pages, whose rock starts below the title) filled with the page stone, inside the outer rail, so it is not bare once the title plate stands on the rail
	["questlog-frame"]                        = { kind = "frame", body = false },   -- the border around the list / details (QuestLogBorderFrameTemplate): the single rail, edges only
	["QuestLog-frame-devider"]                = { kind = "strip", base = "window/divider", natural = true },   -- the line under a header
	["questlog-icon-setting"]                 = { kind = "flat", flat = "cog" },   -- (0.19.9, the user's pick 0A) the NewUI2 cog plate in place of the game's gear (0.19.1: a bare flat plate; was K2)
	["questlog-quest-glow-yellow"]            = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a quest title's highlight (the game shows it on hover / selection): the plate's hover look
	["QuestListFilter"]                       = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- the Quest List's switch on the quest log's count box (the side window's filter buttons were the first, F7, user 2026-09-21), the Auction House's category rows: the plain plate (hover from the button) ...
	["QuestListFilter-Selected"]              = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... the selected plate (the Auction House's chosen category)
	-- the guild and communities window (CommunitiesFrame; file art keyed by hand; 2026-09-21)
	["UI-Background-Rock"]                    = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true },   -- ButtonFrameTemplate's rock background: the page stone as a region of the frame
	["bluemenu-main"]                         = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a communities list entry's background (the sheet's blue plate): the plain plate
	["bluemenu-main-selected"]                = { kind = "fade" },   -- ... its selection bar: faded, the card's iron lights instead
	["CommunitiesListEntry"]                  = { kind = "frame", hover = 1.15, pressed = 0.9, checkedTint = { 1.45, 1.3, 0.85 } },   -- a communities list entry (68 px tall: a TALL row, R3 — the plate's rails got fat): the single-rail card with stone, its iron lit gold while the game shows its Selection
	["communities-ring-gold"]                 = { kind = "slot", slot = "roundslot" },   -- the entry's icon ring: the round rim
	["CommunitiesListBody"]                   = { kind = "tile", piece = "window/single_body", owner = true },   -- the communities list's box (L1), in two parts: the stone body as a REGION of the list under its rows (the list's blue Bg, filigrees faded) ...
	["CommunitiesListBox"]                    = { kind = "frame", body = false },   -- ... and the single rail on the list's InsetFrame rect at that frame's own level (200: over the rows), the gold border faded
	["common-dropdown-textholder"]            = { kind = "flat", flat = "dropdown" },   -- (0.19.1) flat: a text dropdown, WowStyle1DropdownTemplate (was D1)
	["UI-Background-Marble"]                  = { kind = "fade" },   -- the marble strip under a list's scroll bar: nothing stands in (the trough is the bar's)
	["UI-ChatInputBorder-Mid2"]               = { kind = "flat", flat = "edit" },   -- (0.19.1) flat: the chat edit box (was S1)
	["UI-ClassTrainer-HorizontalBar"]         = { kind = "fade" },   -- the guild info page's horizontal bars over its headers: faded — a gem-capped divider stacked on a gem-capped header plate read as clutter (user, 2026-09-21); the plate alone marks the section
	["GuildFrame-Header"]                     = { kind = "strip", base = "lists/header", owner = true },   -- a guild page header (GH1, user 2026-09-21; a region of the GuildFrame sheet, keyed by hand): the header plate as a region under the page's text
	["ColumnDisplayButton"]                   = { kind = "strip", base = "lists/header", owner = true },   -- a roster column header (GC1, user 2026-09-21; WhoFrame-ColumnTabs file pieces, keyed by hand): the header plate per column, hover from the button
	["GuildNewsRow"]                          = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a guild news row (GP1, user 2026-09-21): the plain plate under the row's text, hover from the button; the blue highlight faded
	["GuildFrame-Bar"]                        = { kind = "bar", bar = "frame" },   -- the guild reputation bar (CommunitiesGuildProgressBarTemplate): P1
	["GuildFrame-Sheet"]                      = { kind = "fade" },   -- the guild info / news pages' sheet backgrounds (GuildFrame file pieces, keyed by hand): faded, the page stone shows
	["UI-Frame-InnerBorderPiece"]             = { kind = "fade" },   -- loose inset-border textures (the roster's column band, the info page's two columns): faded — the inset rail and the pane divider stand in
	["UIDropDownMenu"]                        = { kind = "flat", flat = "dropdown" },   -- (0.19.1) flat: an old-style dropdown (was D1)
	-- the dungeon finder (PVEFrame) and the collections (CollectionsJournal), 2026-09-21 first pass
	["bluemenu-Ring"]                         = { kind = "slot", slot = "roundslot" },   -- a group button's ring on its masked icon (the dungeon finder's left column): the round rim
	["bluemenu-shadowcovers"]                 = { kind = "fade" },   -- the shadow strips beside the left column: nothing stands in
	["UI-LFG-BlueBG"]                         = { kind = "fade" },   -- the listing page's blue role band (file art, keyed by hand): faded — the window's one page picture runs under it; only the INSIDE of the inset rail is the darker stone (user, 2026-09-21)
	["UI-LFG-BACKGROUND-QUESTPAPER"]          = { kind = "picture", piece = "tiles/vellum", crop = "middle", owner = true, parchment = true },   -- (0.20.1: the parchment nine)   -- the queue frame's paper (file art, keyed by hand): the parchment page, as the quest lists
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
	["UI-SquareButton-Up"]                    = { kind = "flat", flat = "button" },   -- (0.19.1) flat: a square icon button's plate (was K2)
	["shop-list-rule"]                        = { kind = "strip", base = "window/divider", natural = true },   -- the activity list's rule line
	["LFGBrowse-Result"]                      = { kind = "frame", hover = 1.15, pressed = 0.9, checkedTint = { 1.45, 1.3, 0.85 } },   -- a TALL list row (R3, user 2026-09-21; the plate's rails got fat stretched to 50-60 px): a single-rail card with stone under the row, its iron lit gold while the game marks it selected, brighter on hover
	["LFGBrowse-Grouping"]                    = { kind = "strip", base = "lists/catplate", state = "closed", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a browse grouping header: the category plate
	["groupfinder-highlightbar-yellow"]       = { kind = "fade" },   -- the selected result's bar: faded, the card's iron lights instead (R3)
	["QuestLog-icon-Expand"]                  = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: a grouping header's glyphs (was the kit's + / -)
	["QuestLog-icon-shrink"]                  = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ...
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
	["UnitFrameBar"]                          = { kind = "bar", bar = "frame", dropCap = "l", capOut = true, troughSub = -1, borderGroup = "unitframe" },   -- B3: the P1 bracket on the bar, ring side capless, the far cap grown outward; the trough under the BACKGROUND-0 fill
	["UnitFrameBarMirrored"]                  = { kind = "bar", bar = "frame", dropCap = "r", capOut = true, troughSub = -1, borderGroup = "unitframe" },   -- ... the target's (ring on the right)
	["UnitFrameHealthBar"]                    = { kind = "bar", bar = "frame", dropCap = "l", capOut = true, troughSub = -1, state = "red", borderGroup = "unitframe" },   -- a health bar: the same B3, its end gem kept red (user, 2026-09-23, painted on the player frame) where every other bracket's is iron
	["UnitFrameHealthBarMirrored"]            = { kind = "bar", bar = "frame", dropCap = "r", capOut = true, troughSub = -1, state = "red", borderGroup = "unitframe" },
	["UI-HUD-UnitFrame-SmallCircle"]          = { kind = "texture", piece = "buttons/orb_normal", square = true, owner = true },   -- L1: the level circle: the orb plate under the frame's own level text
	-- (0.20.2, the user: "can we remove the circle border and background from the PVP icon, and just place the icon on
	-- the top side of the Level Border?") the PvP badge's circle (the same atlas, its own key: UnitFramePanel's
	-- PvPOnLevel) faded, no orb; its faction icon rides the level orb's top
	["UnitFrame-PvpBackgroundCircle"]         = { kind = "fade" },
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
	["ActionButtonActiveLook"]                = { kind = "active" },   -- a check button of the game's own art the kit does not dress (the extra action button, the vehicle bar's; keyed by hand): the active look (Kit:SetActive, 0.15.0) while it is checked, in place of its checked art (an agreed addition where it has none)
	["UI-HUD-ActionBar-IconFrame"]            = { kind = "slot", slot = "slot", gemSpan = { 97 / 135, 92 / 130 }, layer = "ARTWORK", sublevel = 2 },   -- an action / stance / pet / bag button's rim (its NormalTexture): R1 — the slot rim sized to the bar's pitch so neighbours share a gem, at the NormalTexture's ARTWORK under the OVERLAY name, count, keybind and highlights; the icon fitted into its opening (Kit:SkinActionButton)
	["UI-HUD-ActionBar-IconFrame-Background"] = { kind = "tile", piece = "tiles/stone", owner = true, sublevel = -1 },   -- an empty slot's backing: the stone in the rim's opening, UNDER the icon (BACKGROUND -1), shown as the game shows the backing (empty slots only)
	["ui-hud-actionbar-iconframe-slot"]       = { kind = "fade" },   -- the empty slot's ornament
	["UI-HUD-ActionBar-IconFrame-Border"]     = { kind = "fade" },   -- the equipped-item border: faded, the rim tinted green while the game shows it
	["UI-HUD-ActionBar-Frame"]                = { kind = "fade" },   -- a bar's frame art (main bar, micro menu, bag bar): it lies under the pitch-sized rims
	["MicroMenuBackgroundArt"]                = { kind = "fade" },   -- the micro menu's backing (an IconFrame-Background region, keyed by hand)
	["ui-hud-actionbar-gryphon-left"]         = { kind = "texture", piece = "deco/rail_cap_l", fit = "height", anchor = "BOTTOMRIGHT" },   -- X2: the left end cap → the rail's orb cap, the gryphon's height, standing at the bar's end — on a holder at the BAR's level, under its buttons (user, 2026-09-21: the caps behind the bar)
	["ui-hud-actionbar-gryphon-right"]        = { kind = "texture", piece = "deco/rail_cap_r", fit = "height", anchor = "BOTTOMLEFT" },
	["ui-hud-actionbar-pageuparrow-up"]       = { kind = "flat", flat = "arrow", dir = "up" },   -- (0.19.1) flat: the action bar's page arrows (was the kit's)
	["ui-hud-actionbar-pagedownarrow-up"]     = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: ...
	["bag-arrow"]                             = { kind = "flat", flat = "arrow", dir = "left", rotates = true },   -- (0.19.1) flat: the bag bar's fold arrow (BagBarExpandToggle, shown by Tweaks' Collapse Arrow); its art points left unturned, the game turns it (SetRotation): the flat arrow follows
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
	["bags-button-autosort-up"]               = { kind = "flat", flat = "button" },   -- (0.19.1) flat: the bags' Clean Up button's plate (was K2)
	["common-coinbox-center"]                 = { kind = "strip", base = "lists/header" },   -- the money strip (Left / Middle / Right, keyed on the middle): B2 (user, 2026-09-21), the header plate on its rect, the coins on it

	-- The minimap cluster (MinimapPanel; user's picks R1 Z2 from kit_raw/minimap_catalog.png, 2026-09-21)
	["UI-HUD-Minimap-Frame"]                  = { kind = "texture", piece = "window/portrait_ring", opening = true, openingScale = 0.75 },   -- R1 at 0.75 (user, 2026-09-21): the round frame (MinimapCompassTexture, also its -Pointer / -Circle rotated variants) → the portrait ring sized from the 198 px map's opening x 0.75, its rim over the map's edge, on a holder one level above the map; the band and buttons raised above it
	["UI-HUD-Minimap-Frame-Circle"]           = { kind = "fade" },   -- the rotated mode's underlay
	["MinimapZoneBand"]                       = { kind = "strip", base = "tabs/top", state = "title", owner = true, heightScale = 1.4, widthScale = 1.4 },   -- Z2: the zone band (BorderTop, a nine-slice of textures keyed by hand) → the title plate as regions of the band, 1.4 x the band's height and width (user, 2026-09-21), standing on the ring's top rim as a window title on its rail; the zone text centred on it
	["ui-hud-minimap-button"]                 = { kind = "texture", piece = "buttons/roundslot_normal", square = true, owner = true },   -- the tracking button's round plate: the round rim under the game's glyph
	["ui-hud-minimap-zoom-in"]                = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: the minimap's zoom buttons (was the kit's + / -)
	["ui-hud-minimap-zoom-out"]               = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ...

	-- The objective tracker (TrackerPanel; user's pick T2 from the same catalogue)
	["ui-questtracker-primary-objective-header"] = { kind = "strip", base = "tabs/top", state = "title", owner = true },   -- T2: the tracker's header band → the title plate
	["UI-QuestTracker-Secondary-Objective-Header"] = { kind = "strip", base = "lists/header", owner = true },   -- a module's header band → the header plate
	["ui-questtrackerbutton-collapse-all"]    = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: the tracker's collapse / expand (was the kit's - / +)
	["ui-questtrackerbutton-expand-all"]      = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: ...
	["ui-questtrackerbutton-secondary-collapse"] = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ...
	["ui-questtrackerbutton-secondary-expand"] = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: ...
	["ui-questtrackerbutton-filter"]          = { kind = "flat", flat = "button" },   -- (0.19.1) flat: the tracker's filter button's plate (was K2)
	["ObjectiveTrackerBackground"]            = { kind = "frame" },   -- Edit Mode's tracker backdrop (a NineSlicePanelTemplate child): L1, the single rail with stone, its child (follows the opacity); TrackerPanel lays the parchment sheet with the painted edge on its stone
	["UI-Character-Skills-BarBorder"]         = { kind = "bar", bar = "frame" },   -- a tracker progress bar's border pieces (file art, keyed by hand): P1

	-- MelloUI's own configurator (Core/Config.lua, 2026-09-21; user's picks CT2 SI1 from kit_raw/config_catalog.png): its
	-- sliders are MinimalSliderWithSteppersTemplate; everything else goes through the fixed looks' existing keys
	["_Minimal_SliderBar_Middle"]             = { kind = "flat", flat = "slider" },   -- (0.19.1) flat: a minimal slider's track (was the kit slider, SL1)
	["Minimal_SliderBar_Button"]              = { kind = "flat", flat = "knob" },   -- (0.19.1) flat: its thumb (was the gem thumb)
	["Minimal_SliderBar_Button_Left"]         = { kind = "flat", flat = "arrow", dir = "left" },   -- (0.19.1) flat: a slider's steppers (was the kit's arrows)
	["Minimal_SliderBar_Button_Right"]        = { kind = "flat", flat = "arrow", dir = "right" },   -- (0.19.1) flat: ...

	-- Tooltips (TooltipPanel, 2026-09-21; user's pick TT1 from kit_raw/tooltip_catalog.png)
	["Tooltip-NineSlice-CornerTopLeft"]       = { kind = "frame", owner = true, bodyLayer = "BACKGROUND", bodySub = -8, edgeLayer = "BORDER" },   -- TT1: a tooltip's NineSlice (the TooltipDefaultLayout pieces, keyed on the top-left corner; the other eight faded) -> the single rail with the list-box stone as REGIONS of the NineSlice in its own layers (under the tooltip's texts as the game's pieces are); the stone at the bottom of BACKGROUND (-8): the game's line icons (AddTexture's GameTooltipTextureN, the quest objectives' check marks) lie at BACKGROUND 0 of the tooltip, on the NineSlice's level (/ttdump icons, 2026-10-03)
	["TooltipStatusBar"]                      = { kind = "bar", bar = "frame", capOut = true },   -- the unit tooltip's health bar (a StatusBar with no border art; an agreed addition, as the catalogue showed it): P1 with the caps outside, the bar set in by the arms
	-- Nameplates (NameplatePanel, 2026-09-21; user's picks NP1 = P1, NC2 from kit_raw/nameplate_catalog.png)
	["NamePlateHealthBarBG"]                  = { kind = "bar", bar = "frame", capOut = true, borderGroup = "nameplate", into = 0.5 },   -- NP1: the health bar's backing (UI-HUD-CoolDownManager-Bar-BG, keyed by hand) -> P1 as the bar's regions above the fill, the caps outside, the bar set in by the arms after the game's UpdateAnchors; the trough under the fill. into 0.5 (user, 2026-10-04: "pixel perfect"): the trough's and the fill's edges at the rails' centres, under solid metal, never on the rails' soft outer rows (NameplatePanel sets the fill in and thickens the bracket by the same)
	["NamePlateCastBarBackground"]            = { kind = "frame", scale = 0.8, owner = true, bodyLayer = "BACKGROUND", edgeLayer = "ARTWORK", edgeSub = 1, outset = 2 },   -- outset 2: the single rail's 2 px outer pad, so the painted line's outer edge is ON the bar's edge and the fill (which reaches that edge, a StatusBar's fill cannot be set in) ends under the line (user, 2026-09-22: "spilling on the bottom")   -- NC2: the cast bar's background (ui-castingbar-background on a nameplate, keyed by hand; its Border faded) -> the single rail at 0.8 with the stone body as the bar's regions: the stone under the ARTWORK fill, the rails one sublevel above it, under the OVERLAY text
	["UI-HUD-Nameplates-Selected"]            = { kind = "fade" },   -- the target / focus outline around the health bar: faded; the bracket's iron shines gold while the game shows it (NameplatePanel)
	["ui-hud-nameplates-levelindicator"]      = { kind = "texture", piece = "buttons/orb_normal", square = true, owner = true },
	["ui-hud-nameplates-levelindicator-selected"] = { kind = "fade" },   -- the target ring around the level circle: faded (the bar's gold iron is the highlight)   -- the level indicator's circle: the orb, as the unit frames' level circle (the -selected ring and the skull stay the game's)

	-- The chat windows (ChatPanel, 2026-09-21; user's picks CH1 CT2 from kit_raw/chat_catalog.png)
	["ChatFrameBorder"]                       = { kind = "frame", body = false, owner = true, edgeLayer = "BORDER", outset = 8 },   -- CH1: a FloatingBorderedFrame's eight border pieces (UI-ChatFrame-BorderCorner / -BorderTop / -BorderLeft file art, keyed by hand on the top-left corner) -> the single rail as regions of the chat frame in the pieces' BORDER layer, centred on the Background's edge (the pieces reach 4 px past it); the Background stays the game's, the rail stays at full alpha (the Background Opacity moves the stone only), and so does its shade
	["ChatFrameBody"]                         = { kind = "tile", piece = "window/single_body", owner = true },   -- the window's Background (ChatFrameBackground file art, the translucent black at the alpha slider; keyed by hand): the list-box stone as a region in its place, at the slider's alpha (user, 2026-09-21: the dark cracked stone, not a flat colour)
	["ChatIconButton"]                        = { kind = "flat", flat = "button" },   -- (0.19.1) flat: a chat menu / channel button's plate (was K2)
	["chatframe-button-up"]                   = { kind = "flat", flat = "button" },   -- (0.19.1) flat: a voice button's plate (was K2)
	["ChatColumnButton"]                      = { kind = "slot", slot = "roundslot" },   -- (0.17.0, the user's pick C of chat_menu_sketch) the chat column's three game buttons -- the chat menu (UI-ChatIcon-Chat-Up), Channels (chatframe-button-up) and Friends (quickjoin-button-friendslist-up), keyed by hand: the round rim (the Round Border) on a 22-unit rect in the column, ChatPanel's disc and glyph in its opening (the whisper header's look)
	["minimal-scrollbar-arrow-returntobottom"] = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: scroll-to-bottom (was the kit's arrow)
	-- the chat tabs (ChatTabTemplate Left / ActiveLeft, keyed by hand) reuse the TB6 tab rules `uiframe-tab-left` / `uiframe-activetab-left`; the edit box reuses `UI-ChatInputBorder-Mid2`

	-- The damage meter (DamageMeterPanel, 2026-09-21; user's pick D1 = P1 from kit_raw/dpsmeter_catalog.png)
	["ui-damagemeters-bar-shadowbg"]          = { kind = "bar", bar = "frame", capOut = true },   -- an entry's shadow band under its status bar (+ BackgroundEdge, faded): P1, the bracket as the bar's regions above the fill, the trough under it; the caps OUTSIDE the bar's rect (a StatusBar's fill cannot be re-anchored, so the bar is set in by the arms and the fill ends under the gems — user, 2026-09-21: the fill overflowed the caps)
	["ui-damagemeters-header-bar"]            = { kind = "strip", base = "lists/header", owner = true },   -- a session window's header band: the header plate as its regions, the game's timer / dropdowns / buttons on it
	["damagemeters-background"]               = { kind = "frame" },   -- a session window's body (MinimizeContainer.Background, alpha = the transparency setting): L1 as the container's child at its level, its alpha following the setting
	["DamageMeterSourceBackground"]           = { kind = "frame" },   -- the source / spell breakdown window's Background (common-dropdown-bg, keyed by hand): L1 the same
	["DamageMeterSettingsIcon"]               = { kind = "flat", flat = "cog" },   -- (0.19.9, the user's pick 0A) the NewUI2 cog plate in place of the game's gear (0.19.1: a bare flat plate; was K2)

	-- The social window (SocialPanel, 2026-09-21): fixed looks; the raid pane's group box per the user's G pick
	["FriendsRowHighlight"]                   = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a friend / ignore / raid-info row's highlight (UI-QuestLogTitleHighlight file art, keyed by hand): the plate's hover look, shown on hover only
	["FriendsPendingHeader"]                  = { kind = "strip", base = "lists/catplate", state = "closed", owner = true },   -- a pending-invite header (UI-Background-Rock BG + arrows, keyed by hand): the category plate, the game's arrows on it
	["UI-FriendsFrame-OnlineDivider"]         = { kind = "strip", base = "window/divider", natural = true },   -- the online / offline divider line
	-- (0.20.1, the user's screenshots: the social window, SocialUIFrame, the client's new one) its list cards on the
	-- list's plain plate (their hover the friend row's, FriendsRowHighlight; the selected one the active look), its
	-- section lines the divider
	["friends-card-default"]                  = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },
	["friends-card-battleNet"]                = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },
	["friends-card-disabled"]                 = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },
	["friends-card-quickJoin"]                = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },
	["perks-divider-short"]                   = { kind = "strip", base = "window/divider", natural = true },
	["battlenet-friends-main"]                = { kind = "strip", base = "lists/header", owner = true },   -- the Battle.net tag band under the tabs: the header plate
	["friendslist-invitebutton-default-normal"] = { kind = "flat", flat = "button" },   -- (0.19.1) flat: the friends list's invite button's plate (was K2)
	["UI-RaidFrame-GroupOutline"]             = { kind = "frame", scale = 0.8 },   -- a raid group box's outline (162 x 80 file picture): G3 (user, 2026-09-21), the single rail at the raid frames' small weight with the stone body
	["UI-RaidInfo-Header"]                    = { kind = "fade" },   -- the raid info popup's header / footer bands: faded (the dialog's own border stands)
	["CalendarBackground"]                    = { kind = "frame", owner = true, bodyLayer = "BACKGROUND", bodySub = 1, edgeLayer = "BORDER", edgeSub = 1, dim = 0.8 },   -- a calendar day (CalendarPanel, 2026-09-24; its NormalTexture, the CalendarBackground file keyed by hand): the single-rail card with stone under the inner panel (2e: the day's event text reads on dark), as REGIONS of the day button -- the stone and panel under its BORDER event picture, the rails one sublevel over it -- on the button's rect grown by the rail's centre inset, so neighbouring days share one rail

	-- The HUD's cast bars (CastBarPanel; user's picks C1 T1 from kit_raw/castbar_catalog.png, 2026-09-21)
	["ui-castingbar-frame"]                   = { kind = "bar", bar = "castbar", capOut = true, borderGroup = "castbar" },   -- C1: the cast bar bracket (gem-cluster caps) with the game's bar as its opening: the caps stand outside the bar, which the panel narrows by their arms so the whole reads the game's width
	["ui-castingbar-background"]              = { kind = "fade" },   -- the trough art: the bracket's trough stands in
	["ui-castingbar-textbox"]                 = { kind = "strip", base = "lists/header", owner = true },   -- T1: the header plate on the 12 px under the bar (the box's lower part), the spell name on it
	["ui-castingbar-full-glow-standard"]      = { kind = "fade" },   -- the completion flash
	["castbar_shadow_embedded"]               = { kind = "fade" },   -- the overlay look's drop shadow
	["CastBarFX"]                             = { kind = "fade" },   -- the glows, flakes, wisps, sparkles and shine (keyed by hand: their animations drive alpha, the panel stops those)
}

-- An action-style button's hooks, one handler each for every button (user,
-- 2026-09-24: the bags' first open, 16 hooks per slot, each with closures of
-- its own): the slot's state is kept by its button and its icon (slotOf), a
-- border's rim rep by the border (borderOf).
local slotOf = setmetatable({}, { __mode = "k" })     -- [button or icon] = the slot's state (Kit:SlotStone): { rep, stone, icon, button, itemButton, ... }
local borderOf = setmetatable({}, { __mode = "k" })   -- [border] = the rim rep

-- the icon's atlas (a pcall with no closure made per call)
local function IconAtlas(icon)
	return icon.GetAtlas and icon:GetAtlas()
end

-- whether the slot is empty (an item button's by its SetItemButtonTexture,
-- below in Kit:SlotStone)
local function SlotEmpty(st)
	local icon, button = st.icon, st.button
	if not icon:IsShown() then
		return true
	end
	if not st.itemButton then
		return false
	end
	if Kit.slotEmpty[button] ~= nil then
		return Kit.slotEmpty[button]
	end
	local ok, atlas = pcall(IconAtlas, icon)
	return ok and atlas ~= nil and atlas == button.emptyBackgroundAtlas
end

-- the stone shown while the slot is empty, an item button's icon see-through
local function SlotSync(st)
	if st.rep.object:IsShown() then
		local empty = SlotEmpty(st)
		st.stone:SetShown(empty)
		if st.itemButton then
			st.icon:SetAlpha(empty and 0 or 1)
		end
	end
end

local Slot_OnItemTexture = Shared("SetItemButtonTexture on a kit slot", function(button, texture)
	Kit.slotEmpty[button] = texture == nil
	SlotSync(slotOf[button])
end)
local Slot_OnIcon = Shared("Show / Hide on a kit slot's icon", function(icon)
	SlotSync(slotOf[icon])
end)

--------------------------------------------------------------------------------
-- Kit:SlotStone(rep, button, bg, opts): the stone in a slot rim's opening,
-- one for every slot that has one (audit, 2026-09-24: the pet stable kept a
-- copy of the action buttons' fit and missed its fixes; the next slot fix
-- lands here, once). The stone stands in for `bg` (the slot's own backing,
-- faded) in the opening of the rim `rep` put on `button`, fitted into that
-- opening again when the rim's art changes (rim.onBaseChanged: a Button
-- Border), when it is re-pitched (rep:SetPitch), and a frame later when the
-- rim's size was not known yet (Kit:DrawnSize 0, 0: Kit:RefitLater).
--   replace    the panel's Replace: the stone is one of its reps (required)
--   base       the rim's art family while it has none of its own
--              (default "buttons/slot", the action buttons' R1)
--   showWhen   "empty" (default): shown only while the slot is empty, an item
--              button's picture see-through then (SlotSync); "always": shown
--              whenever the kit is (the pet stable's slots)
--   tintFrom   a region whose tint the stone wears, copied on each of its
--              SetVertexColor (the stable's empty-slot picture: red for a slot
--              not bought yet)
--   noFade     `bg` left as the game's (a bag slot has no backing: the stone
--              is put on the button itself)
--   icon       the slot's icon (default the rim's, else button.icon)
-- Returns the stone rep, or nil. Made once per slot; a refit makes nothing.
-- Kit:SyncSlotStone(button) reads the game's state onto the stone again.
--------------------------------------------------------------------------------
do
	local tintOf = setmetatable({}, { __mode = "k" })   -- [tintFrom region] = the slot's state

	-- the stone's opening: the opening of the rim it is in (its art can change
	-- live), measured as drawn (not laid out yet a rim reads as its atlas sheet)
	local function SlotFit(st)
		local rim, opening = st.rim, st.opening
		local name = (rim.base or st.base) .. "_normal"
		local piece = PIECES[name]
		local l, r, t, b = Kit:Insets(name, 1)
		local rw, rh = Kit:DrawnSize(rim)
		opening:ClearAllPoints()
		if piece and l and rw > 0 and rh > 0 then
			opening:SetPoint("TOPLEFT", rim, "TOPLEFT", rw * l / piece.w, -rh * t / piece.h)
			opening:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -rw * r / piece.w, rh * b / piece.h)
		else
			opening:SetAllPoints(st.button)
			if piece and l then
				Kit:RefitLater(rim)   -- the rim's size not known yet: fitted again a frame later
			end
		end
	end

	-- the stone in the tint the game gives the region it copies (secret-safe:
	-- a secret colour leaves the stone as it is)
	local function SlotTint(st)
		local tex, from = st and st.stone and st.stone.tex, st and st.tintFrom
		if not (tex and from) then
			return
		end
		local ok, r, g, b = pcall(from.GetVertexColor, from)
		if ok and not Secret(r) and not Secret(g) and not Secret(b) and type(r) == "number" then
			tex:SetVertexColor(r, g, b)
		end
	end
	local Slot_OnTint = Shared("SetVertexColor on a kit slot stone's tint", function(region)
		SlotTint(tintOf[region])
	end)

	function Kit:SlotStone(rep, button, bg, opts)
		opts = opts or {}
		local rim = rep and rep.object
		local replace = opts.replace
		if not (rim and button and bg and replace) then
			return nil
		end
		local opening = CreateFrame("Frame", nil, button)
		opening:EnableMouse(false)
		-- (the slot's state: the shared handlers and the refit read it)
		local st = { rep = rep, rim = rim, button = button, opening = opening, base = opts.base or "buttons/slot",
			icon = opts.icon or rim.icon or button.icon }
		local function Fit()
			SlotFit(st)
		end
		Fit()
		rim.onBaseChanged = Fit
		-- (the opening is the stone's own sizer: no frame made for it per slot)
		local stone = replace(bg, { as = "UI-HUD-ActionBar-IconFrame-Background", rect = opening, noFade = opts.noFade,
			sizer = opening }) or nil
		st.stone = stone
		local icon = st.icon
		if stone then
			slotOf[button] = st
			if opts.showWhen ~= "always" and icon then
				-- the stone shows while the slot is EMPTY: the game hides the icon
				-- then (its own backing shows only on a bar whose art is hidden —
				-- on the main bar the faded frame art was the empty slot's look).
				-- An ITEM button (a bag window's slot, a bag bar slot) keeps its
				-- icon shown when empty, painted with its empty-slot picture
				-- (`emptyBackgroundAtlas` / `emptyBackgroundTexture`, put there by
				-- SetItemButtonTexture(nil)): the Item Background never showed
				-- (user, 2026-09-23). Its emptiness is read from that call; while
				-- empty the icon (the game's picture) is see-through.
				st.whileEmpty = true
				st.itemButton = ((button.emptyBackgroundAtlas or button.emptyBackgroundTexture) and button.SetItemButtonTexture) and true or false
				slotOf[icon] = st
				if st.itemButton then
					hooksecurefunc(button, "SetItemButtonTexture", Slot_OnItemTexture)
					local disable = rep.onDisable
					rep.onDisable = function(...)
						if disable then
							disable(...)
						end
						icon:SetAlpha(1)
					end
				end
				hooksecurefunc(icon, "Show", Slot_OnIcon)
				hooksecurefunc(icon, "Hide", Slot_OnIcon)
				hooksecurefunc(icon, "SetShown", Slot_OnIcon)
				local enable = stone.Enable
				stone.Enable = function(self)
					enable(self)
					SlotSync(st)
				end
				SlotSync(st)
			end
			-- tinted as the game tints the picture it stands for (one shared
			-- handler for every slot, no closure of its own: audit, 2026-09-24)
			local from = opts.tintFrom
			if from and from.SetVertexColor then
				st.tintFrom = from
				tintOf[from] = st
				hooksecurefunc(from, "SetVertexColor", Slot_OnTint)
				SlotTint(st)
			end
		end
		-- a rim re-sized to a new pitch: the opening fitted again
		local setPitch = rep.SetPitch
		rep.SetPitch = function(self, px, py)
			if setPitch then
				setPitch(self, px, py)
			end
			Fit()
		end
		return stone
	end

	-- The game's state onto a slot's stone again (a window's refresh): the tint
	-- it copies and, for a stone shown while empty, whether it shows
	function Kit:SyncSlotStone(button)
		local st = button and slotOf[button]
		if not st then
			return
		end
		if st.tintFrom then
			SlotTint(st)
		end
		if st.whileEmpty then
			SlotSync(st)
		end
	end
end

-- the rim green while the game shows the equipped border
local function BorderTint(rep, border)
	if rep.object:IsShown() then
		if border:IsShown() then
			rep.object:SetVertexColor(0.5, 1, 0.5)
		else
			rep.object:SetVertexColor(1, 1, 1)
		end
	end
end
local Slot_OnBorder = Shared("Show / Hide on a kit slot's border", function(border)
	BorderTint(borderOf[border], border)
end)

-- An action-style button (ActionButtonTemplate and its small kin: action,
-- stance, pet, possess and bag slot buttons): the R1 rim on its NormalTexture
-- sized to the bar's pitch { x, y } so neighbours share a gem, the icon fitted
-- into the rim's opening (its rounded mask taken off while the rim is on),
-- the empty-slot backing on stone, the pushed / highlight / checked textures
-- faded (the rim carries the states), the equipped border faded and the rim
-- tinted green while the game shows it. `replace` is the panel's Replace.
-- Returns the rim rep; rep:SetPitch(x, y) re-sizes it after a re-layout.
-- (An item slot's quality gem and junk grey are Tweaks', dressed or not:
-- MelloUI.ItemGems, Modules/Tweaks.lua.)
function Kit:SkinActionButton(button, replace, pitch, opts)
	opts = opts or {}
	-- the rim texture: the template's key, else the widget's own (a bag
	-- button has no NormalTexture key; one is never written onto it -- the
	-- game reads that key, 2026-09-23 audit)
	local normal = button and (button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture()))
	if not (button and normal and button.icon) or Kit.repOf[button] ~= nil then
		return button and Kit.repOf[button] or nil
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
	-- opts.alsoFade: more of the game's art the rim stands in for, and
	-- opts.checked its checked state where the button has no flag (a bag
	-- slot: an item button, its open bag shown by a highlight region)
	if opts.alsoFade then
		for _, region in ipairs(opts.alsoFade) do
			extra[#extra + 1] = region
		end
	end
	-- opts.as: another slot rule (the action bars' thin rim, "ActionButtonRim")
	local rep = replace(normal, { as = opts.as or "UI-HUD-ActionBar-IconFrame", button = button, rect = button, pitch = pitch,
		icon = button.icon, alsoFade = extra, checked = opts.checked })
	Kit.repOf[button] = rep or false
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
	-- the empty slot's backing: the kit's slot stone in the rim's opening,
	-- shown while the slot is empty (Kit:SlotStone); its ornament faded (a bag
	-- slot has no backing region: `opts.emptyStone` puts the stone on the
	-- button itself, replacing its NormalTexture's empty look)
	if button.SlotBackground or opts.emptyStone then
		local stone = self:SlotStone(rep, button, button.SlotBackground or normal, { replace = replace, base = "buttons/slot",
			showWhen = "empty", noFade = not button.SlotBackground, icon = icon })
		Kit.slotStoneOf[button] = stone   -- its texture (stone.tex) can be swapped: Action Bars Kit's Button Background
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
		local border = button.Border
		borderOf[border] = rep
		hooksecurefunc(border, "Show", Slot_OnBorder)
		hooksecurefunc(border, "Hide", Slot_OnBorder)
		hooksecurefunc(border, "SetShown", Slot_OnBorder)
		BorderTint(rep, border)
	end
	-- a button skinned while the panel is already on was enabled by `replace`
	-- before the hooks above existed: run them now
	if rep.object:IsShown() and rep.onEnable then
		rep.onEnable(rep)
	end
	return rep
end

--------------------------------------------------------------------------------
-- Quality gems on item slots, and Grey Out Junk: no longer the kit's (one
-- look, stage D3). They are Tweaks' (Modules/Tweaks.lua, MelloUI.ItemGems),
-- on every bag, bank and guild bank slot whether the kit dressed it or not;
-- a dressed slot's gem follows its icon into the rim's opening.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- The looks a button can take, shared by every panel that offers them (the
-- action bars, micro menu and bag bar in Action Bars Kit, the bag windows'
-- slots in Backpack Kit) and by the Configurator's picture rows.
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
		-- (0.19.8) the border library's own styles (Modules/KitBorders.lua),
		-- drawn by it where the rim stands: no slot rim of their own
		{ value = "single", label = "Single rail", style = "single" },
		{ value = "backdrop", label = "Backdrop", style = "backdrop", piece = "borders/backdrop" },
		-- (the NewUI2 rims the user picked: Tools/make_newui2_borders.py)
		{ value = "n4", label = "Medium iron, corner studs", style = "n4", piece = "borders/n4" },
		{ value = "n4g", label = "Thin gold, corner studs", style = "n4g", piece = "borders/n4g" },
		{ value = "n5", label = "Hairline, corner nubs", style = "n5", piece = "borders/n5" },
		{ value = "n1", label = "Heavy bevel, corner studs", style = "n1", piece = "borders/n1" },
		-- (0.20.1, the RPG pack's frame with its trough: Tools/make_rpg_frames.py)
		{ value = "rpg", label = "Stone rail", style = "rpg", piece = "borders/rpg" },
	},
	backgrounds = {
		{ value = "stone", label = "Stone", piece = "tiles/stone" },
		{ value = "concrete", label = "Cracked concrete", piece = "tiles/concrete" },
		{ value = "ironplate", label = "Iron plate", piece = "tiles/ironplate" },
		{ value = "parchment", label = "Parchment", piece = "parchment/sheet_body", paper = true },   -- (0.20.1: the RPG pack's paper, Tools/make_parchment.py)
		{ value = "leather", label = "Leather", piece = "tiles/quilt_brown" },
		-- (0.19.8, the NewUI2 textures the user picked: Tools/make_newui2_borders.py)
		{ value = "brushedmetal", label = "Brushed dark metal", piece = "tiles/brushedmetal" },
		{ value = "agedparchment", label = "Aged parchment", piece = "tiles/agedparchment", paper = true },
		{ value = "dark", label = "Dark" },
		-- (0.20.1, the user: the RPG pack's dark panel gradient, "scaleable and reusable": Tools/make_rpg_gradient.py;
		-- no tile, laid over the whole rect)
		{ value = "gradient", label = "Dark gradient", piece = "backdrops/gradient_dark" },
		{ value = "radial", label = "Dark round gradient", piece = "backdrops/gradient_radial" },   -- (0.20.1: the pack's slot boxes')
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
		-- (0.19.8, the border library's stage 2: Modules/KitBorders.lua) drawn
		-- by it round the bar, the bracket put out
		{ value = "single", label = "Single rail", style = "single" },
		{ value = "backdrop", label = "Backdrop", style = "backdrop" },
		{ value = "n4", label = "Medium iron, corner studs", style = "n4" },
		{ value = "n4g", label = "Thin gold, corner studs", style = "n4g" },
		{ value = "n5", label = "Hairline, corner nubs", style = "n5" },
		{ value = "n1", label = "Heavy bevel, corner studs", style = "n1" },
		{ value = "rpg", label = "Stone rail", style = "rpg" },   -- (0.20.1: its trough the bar's ground)
	},
	rimRule = { thin = "ActionButtonRim", hairline = "ActionButtonRimHairline", rounded = "ActionButtonRimRounded",
		gold = "ActionButtonRimGold", sunk = "ActionButtonRimSunk" },
	rimKind = { thin = "rim", hairline = "rimhair", rounded = "rimround", gold = "rimgold", sunk = "rimsunk" },
	borderDesc = "The rim on each button: a thin iron rim, a hairline, rounded corners, iron with a gold line round the icon, "
		.. "or sunk (a soft shadow inside the rim). Each lights up under the mouse and turns gold when checked.",
}
Kit.buttonLooks.backgroundPiece = {}
Kit.buttonLooks.backgroundPaper = {}
for _, v in ipairs(Kit.buttonLooks.backgrounds) do
	Kit.buttonLooks.backgroundPiece[v.value] = v.piece
	Kit.buttonLooks.backgroundPaper[v.value] = v.paper or nil
end

-- A background that is paper (0.19.8: the parchment, the aged parchment):
-- the text on it is dark ink (the parchment ink rule, QuestInk.lua), and a
-- window that has its own parchment choice does not offer it
function Kit:BackgroundIsPaper(value)
	return self.buttonLooks.backgroundPaper[value] == true
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
	-- (0.19.8) a style of the border library's: drawn by it where the rim
	-- stands, the rim put out (Modules/KitBorders.lua); another style puts
	-- such a border away and swaps the rim's art as before
	if self.ButtonLibraryBorder and self:ButtonLibraryBorder(button, style) then
		return
	end
	local kind = self.buttonLooks.rimKind[style]
	local rep = button and Kit.repOf[button]
	if kind and rep and rep.object and rep.object.base then
		self:SetSlotBase(rep.object, "buttons/" .. kind)
	end
end

-- A button's background: the texture in its opening where it shows no icon
-- (an action / bag / item slot's empty backing, Kit.slotStoneOf; a micro
-- button's stone under its glyph, Kit.glyphStoneOf)
function Kit:SetButtonBackground(button, value)
	local tex = button and ((Kit.slotStoneOf[button] and Kit.slotStoneOf[button].tex) or Kit.glyphStoneOf[button])
	if not tex then
		return
	end
	local piece = self.buttonLooks.backgroundPiece[value]
	if piece then
		if Kit.pieceNameOf[tex] ~= piece then
			self:Unpaint(tex)   -- (the dark fill's palette colour no longer on it)
			self:Apply(tex, piece)
		end
		self:Retile(tex)
		tex:SetAlpha(1)
	elseif value == "dark" then
		-- the palette's inner panel, by its key (a new palette paints it again)
		self:Paint(tex, "innerPanel", "fill", 0.88)
		-- still ours: a plain mark, no piece
		Kit.pieceOf[tex], Kit.pieceNameOf[tex] = true, nil
		tex:SetAlpha(1)
	else
		tex:SetAlpha(0)   -- none: the game shows it with the empty slot; it stays see-through
	end
end

local ReplacementMixin = {}

-- The holder frame a replacement is drawn on: on its rect, `lvl` levels over
-- its parent's, never part of a layout frame's size. `strata`: Kit:Replace's
-- opts.strata.
local function MakeHolder(parent, rect, lvl, strata)
	local f = CreateFrame("Frame", nil, parent)
	-- never part of the parent's size: a layout frame (an action bar, a
	-- ResizeLayoutFrame) grows round its shown children, and a holder on
	-- a rect past its content would make it grow (user, 2026-09-23: Action
	-- Bar 1 swelling in Edit Mode with the backdrop)
	f.ignoreInLayout = true
	-- opts.strata: a holder below everything at the parent's strata (the
	-- main bar's end caps under every bar and the status bars)
	if strata then
		f:SetFrameStrata(strata)
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

-- A 'fade' draws nothing, and its holder was an empty frame per faded
-- region (user, 2026-09-24: every bag slot's picture, every spell card's and
-- header's backplate): its rep has no frame until something asks for
-- rep.object (a panel hanging a parchment sheet on it, a dump). The holder is
-- then made as Kit:Replace made it, shown or hidden as the rep is; until
-- then the rep keeps that itself (`holderShown`).
local BareRep = {
	__index = function(rep, key)
		if key ~= "object" then
			return nil
		end
		local f = MakeHolder(rawget(rep, "holderParent"), rawget(rep, "rect"), rawget(rep, "holderLevel"), rawget(rep, "holderStrata"))
		if not rawget(rep, "holderShown") then
			f:Hide()
		end
		rawset(rep, "object", f)
		return f
	end,
}

-- A rep whose skin waits for its first show (a panel tab's open card, Kit:
-- SkinPanelTab) laid now, the editor's tune on it as on every rep
local function LayRep(rep)
	local skin = rep.skin
	if not (skin and skin.pendingArt) then
		return
	end
	local holder = rawget(rep, "object")
	if holder and holder.kitWaiting then
		holder.kitWaiting = nil
		Perf.SetScript(holder, "OnUpdate", nil)
	end
	NineSlice_Lay(skin)
	if rep.tune then
		Kit:TuneObject(rep, rep.tune)
	end
end

-- ... and a waiting card whose holder is on screen without it (shown by an
-- Enable that no sync to the game's art followed): laid in that frame's
-- update, before it is drawn, as it would have shown. A hidden holder gets
-- no OnUpdate, so the cards that wait cost nothing here.
local Waiting_OnUpdate = Shared("OnUpdate on a waiting kit card", function(f)
	LayRep(f.kitWaiting)
end, "update")

-- Fade the game art, show ours.
function ReplacementMixin:Enable()
	if not self.noFade then
		Kit:Fade(self.region)
	end
	for _, extra in ipairs(self.alsoFade) do
		Kit:Fade(extra)
	end
	-- (a fade's holder only once asked for; a waiting card laid when the
	-- art it stands for is shown)
	local object = rawget(self, "object")
	if object then
		local wait = self.layWith
		if wait and self.skin.pendingArt and wait:IsShown() then
			LayRep(self)
		end
		object:Show()
		-- a rim or state texture read again: its button's active look (its
		-- regions, not the rim's) follows it back on (Kit:SetActive); a flat
		-- control's driver likewise (the "flat" kind)
		if object.Update == Slot_Update then
			Slot_Update(object)
		end
		if self.flatDriver then
			Slot_Update(self.flatDriver)
		end
	else
		self.holderShown = true
	end
	if self.backing then
		self.backing:Show()
	end
	-- its shadow partners drawn by another frame (Kit:Shadow's rep)
	Kit:ShadowRepOn(self, true)
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
	local object = rawget(self, "object")
	if object then
		object:Hide()
	else
		self.holderShown = false
	end
	if self.backing then
		self.backing:Hide()
	end
	if object and object.glow then
		object.glow:Hide()
	end
	-- a rim's active look is regions of its button: off with the rim (one
	-- that drives it: a hover-only rim leaves a row's plate its look)
	if object and object.Update == Slot_Update and Kit:RimDrivesLook(object) then
		Kit:SetActive(object.button, false)
	end
	local driver = self.flatDriver
	if driver and Kit:RimDrivesLook(driver) then
		Kit:SetActive(driver.button, false)
	end
	Kit:ShadowRepOn(self, false)
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
	-- `natural`: the kit's own weight (Kit:StripWeight), however tall the game's art is (0.20.1, the user: "We use
	-- this separation line on muiltiple windows and sizes" -- each window's divider stood at its own atlas's height,
	-- 0.44 to 1.0 of the art); with `widthFrac`, centred on the rect over that share of its width
	local h = self.fitHeight
	if self.rule.natural then
		h = Kit:StripWeight(self.strip.base, self.strip.state)
		if self.rule.widthFrac then
			local yoff = self.strip:FitBox(h)
			local w = (self:RectSize("GetWidth") or 0) * self.rule.widthFrac
			self.strip:ClearAllPoints()
			self.strip:SetPoint("CENTER", self.rect, "CENTER", 0, yoff)
			self.strip:SetSize(math.max(w, 1), self.strip.height)
			self.strip:FitCaps(w)
			return
		end
	elseif not (h and h > 0) then
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
	elseif self.flatDriver then
		-- (a flat control reads its state from its button; a given state is
		-- the edit field's lit edge: "focused" / "normal", a binding button)
		if state then
			self.flatDriver.flatFocus = (state == "focused") or nil
		end
		Slot_Update(self.flatDriver)
	elseif self.strip then
		self.strip:SetState(state)
	elseif self.skin and self.Update then
		self.Update()
	elseif self.skin and self.checked then
		local tint = self.rule.checkedTint
		local on = self.checked() and true or false
		if tint and on then
			self.skin:SetTint(tint[1], tint[2], tint[3])
		else
			self.skin:SetTint(1, 1, 1)
		end
		-- the selected row's active look (Kit:SetActive), round its card
		Kit:SetActive(self.skin, on, self.skin, "rect")
	else
		local object = rawget(self, "object")
		if object and object.Update then
			object:Update()
		end
	end
end

function ReplacementMixin:SetShown(shown)
	-- (its shadow partners on other frames with its holder)
	Kit:ShadowRepOn(self, shown)
	local object = rawget(self, "object")
	if not object then
		self.holderShown = shown and true or false
		return
	end
	if shown and self.skin and self.skin.pendingArt then
		LayRep(self)
	end
	object:SetShown(shown)
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
	if key == "NineSlicePanelTemplate" or key == "TitleBar" then
		self:SyncWindowLookOnce()
	elseif (key == "UI-HUD-UnitFrame-SmallCircle" or key == "ui-hud-nameplates-levelindicator") and self.OrbLook then
		-- (0.20.1) the level orb in the look chosen (Level Orb, KitBorders.lua)
		self.Replacements[key].piece = self:OrbLook().piece
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
local invented = {}             -- [piece name] = true: a piece the layout lacks, made by the tuning
local WHOLE = { 0, 1, 0, 1 }    -- a whole file, as a uv

-- The shipped textures (user, 2026-09-24: "textures look good", option (d)):
-- Tools/texture_pack.py ship packs the small pieces of each look into atlas
-- sheets (Media\<look>\atlas\...) and gives some pieces a smaller file.
-- KitLayout.lua then names the sheet as such a piece's `file`, its
-- rectangle there as its `uv`, and keeps `was`: its uv in its own former
-- file (file = its name), the frame build_kit.py wrote and the kit tools
-- write a `pieces` uv or file override in. Everything that draws a piece
-- reads file + uv (Kit:Apply) and crops or mirrors inside that uv, so it
-- draws the piece's rectangle of the sheet; an override is mapped from the
-- `was` frame into that rectangle here.
local function InSheet(file)
	return type(file) == "string" and file:find("^atlas\\") ~= nil
end

-- `uv` (left, right, top, bottom in the `was` frame) into `rect` (the
-- piece's rectangle now); a value past the piece is held at its edge (in a
-- sheet the neighbouring pieces lie there)
local function MapInto(uv, was, rect)
	local out = {}
	for i = 1, 4 do
		local lo, hi = (i <= 2) and 1 or 3, (i <= 2) and 2 or 4
		local span = was[hi] - was[lo]
		local f = span > 0 and (uv[i] - was[lo]) / span or 0
		if f < 0 then
			f = 0
		elseif f > 1 then
			f = 1
		end
		out[i] = rect[lo] + f * (rect[hi] - rect[lo])
	end
	return out
end

local LAYOUT_FIELDS = { "file", "uv", "was", "tile" }

-- A piece's values as the layout has them, whatever tuning has put into
-- PIECES since: a backed-up field's original, else the live field (one no
-- override has touched is still the layout's)
local function LayoutOf(name)
	local p = PIECES[name]
	if not p then
		return nil
	end
	local backup, out = pieceBackup[name], {}
	for _, field in ipairs(LAYOUT_FIELDS) do
		local value = p[field]
		if backup and backup[field] ~= nil then
			value = backup[field]
			if value == GONE then
				value = nil
			end
		end
		out[field] = value
	end
	return out
end

-- The piece a file override names ("buttons\\cog_hover"), also written in
-- another case or with its old extension (the files it named were found so)
local lowerNames = nil   -- [lower-case name] = the piece's name, made on a miss; emptied by Kit:ApplyTuning
local function PieceNamed(file)
	local name = file:gsub("\\", "/"):gsub("%.[Tt][Gg][Aa]$", ""):gsub("%.[Bb][Ll][Pp]$", "")
	if PIECES[name] then
		return name
	end
	if not lowerNames then
		lowerNames = {}
		for n in pairs(PIECES) do
			lowerNames[n:lower()] = n
		end
	end
	return lowerNames[name:lower()]
end

-- A tuned piece's uv / file override (copied into `p`) put where its art is
-- now. `base`: the piece's layout values. Returns the fields it changed.
local function RemapTunedPiece(p, over, base, NIL)
	local changed = {}
	local file = over.file ~= NIL and type(over.file) == "string" and over.file or nil
	local uv = over.uv ~= NIL and type(over.uv) == "table" and over.uv or nil
	-- the piece whose art the override means: the one its file names, else
	-- this piece (as the layout has them)
	local target = base
	if file ~= nil then
		local named = PieceNamed(file)
		target = named and LayoutOf(named) or nil
	end
	if file ~= nil or uv ~= nil then
		if target and target.was and target.uv then
			-- the art the override means has moved: its file now, the uv
			-- mapped from its former frame into its rectangle there
			-- (a piece the tuning invents may bring no uv: the whole piece)
			p.file = target.file
			p.uv = MapInto(uv or base.was or base.uv or target.was, target.was, target.uv)
			changed.file, changed.uv = true, true
		else
			if file ~= nil and target and file ~= target.file then
				-- a piece's own file in another case or with an extension:
				-- as the layout names it (it may ship as .blp or .tga)
				p.file = target.file
				changed.file = true
			end
			if file ~= nil and uv == nil and base.was then
				-- a file that was not moved, named for a piece that was: the
				-- piece's uv in its former file is what the override meant
				p.uv = { base.was[1], base.was[2], base.was[3], base.was[4] }
				changed.uv = true
			end
		end
	end
	-- a piece left without a uv (one the tuning invents, given only a file;
	-- an override that removes the uv) is drawn whole: the target's
	-- rectangle as the layout has it, else the whole file (Kit:Apply reads a
	-- uv for every piece)
	if p.uv == nil then
		local whole = target and target.uv or WHOLE
		p.uv = { whole[1], whole[2], whole[3], whole[4] }
		changed.uv = true
	end
	-- one piece cannot repeat inside a sheet (the ship never puts a tiling
	-- piece in one)
	if p.tile and InSheet(p.file) then
		p.tile = nil
		changed.tile = true
	end
	return changed
end

-- The frame a `pieces` uv / file override is written in (above): the
-- piece's own file (its name, for a piece the ship moved into a sheet) and
-- its uv there, as the layout has them whatever tuning did since; and
-- whether the piece is drawn from a sheet now (it cannot repeat there).
-- nil for a piece the kit does not know. The kit editor shows these.
function Kit:PieceFrame(name)
	local base = LayoutOf(name)
	if not base then
		return nil
	end
	local inSheet = InSheet(PIECES[name].file)
	if base.was then
		return (name:gsub("/", "\\")), base.was, inSheet
	end
	return base.file, base.uv, inSheet
end

-- Globals and painted-piece geometry, applied to the kit itself. Called by
-- MelloUI.KitTuning whenever the tuning changes: every pass starts each
-- piece tuned so far from its layout values again (its backup) before the
-- overrides go in, so the same tuning applied twice gives the same pieces
-- (a remapped uv never feeds the next mapping) and a field an override
-- stops carrying goes back to the layout's.
function Kit:ApplyTuning(KT)
	local g = KT:Globals()
	self.baseScale = self.baseScale or self.scale
	self.baseFrameScale = self.baseFrameScale or self.frameScale
	self.baseFramePrefix = self.baseFramePrefix or self.framePrefix
	self.scale = tonumber(g.scale) or self.baseScale
	self.frameScale = tonumber(g.frameScale) or self.baseFrameScale
	self.framePrefix = g.framePrefix or self.baseFramePrefix

	-- every piece tuned before back to what the layout says; the ones not
	-- tuned any more are done with (a piece the tuning made goes with it)
	local section = KT:Section("pieces")
	lowerNames = nil
	for name, backup in pairs(pieceBackup) do
		local p = PIECES[name]
		if p then
			for field, value in pairs(backup) do
				if value == GONE then
					p[field] = nil
				else
					p[field] = value
				end
			end
		end
		if not section[name] then
			pieceBackup[name] = nil
			if invented[name] then
				PIECES[name], invented[name] = nil, nil
			end
		end
	end
	for name, over in pairs(section) do
		local p = PIECES[name]
		if not p then
			p = { file = (name:gsub("/", "\\")) }
			PIECES[name] = p
			invented[name] = true
		end
		local backup = pieceBackup[name]
		if not backup then
			backup = {}
			pieceBackup[name] = backup
		end
		local base = LayoutOf(name)
		for field, value in pairs(over) do
			if backup[field] == nil then
				backup[field] = p[field] == nil and GONE or p[field]
			end
			if value == KT.NIL then
				p[field] = nil
			else
				p[field] = value
			end
		end
		for field in pairs(RemapTunedPiece(p, over, base, KT.NIL)) do
			if backup[field] == nil then
				backup[field] = base[field] == nil and GONE or base[field]
			end
		end
	end

	LOWER_RULES = nil
	tunedRules = { serial = -1 }
	for base in pairs(resolved) do
		resolved[base] = nil
	end
	-- a tuned rail piece keeps its family's skins in pieces (checked again)
	Slices.families, Slices.cuts = {}, {}
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
-- (0.19.1) A texture of a window moved or resized by the kit editor (an element's `regions` entry: x, y, padL /
-- padR / padT / padB, Core/KitTuning.lua; user 2026-10-04, "move each individual thing on the windows"): against
-- the points it had when first tuned, taken again when its owner has laid it out anew since, so the same tuning
-- applied any number of times gives the same place. Weak tables: nothing is written on the texture.
LOOK.geomBase = setmetatable({}, { __mode = "k" })   -- [texture] = its own points { point, relative, relativePoint, x, y } (+ w, h)
LOOK.geomSet = setmetatable({}, { __mode = "k" })    -- [texture] = the points the tuning last set
LOOK.geomTune = setmetatable({}, { __mode = "k" })   -- [texture] = the tuning on it, for Kit:RefitRegion
LOOK.centeredOn = setmetatable({}, { __mode = "k" }) -- [texture] = the replacement centred on it (a portrait's ring)
function LOOK.Points(tex)
	local out = {}
	for i = 1, tex:GetNumPoints() do
		local point, relative, relativePoint, x, y = tex:GetPoint(i)
		if Secret(x) or Secret(y) then
			return nil
		end
		out[i] = { point, relative, relativePoint, x or 0, y or 0 }
	end
	return out
end
function LOOK.SamePoints(a, b)
	if not (a and b) or #a ~= #b then
		return false
	end
	for i = 1, #a do
		local p, q = a[i], b[i]
		if p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3] or math.abs(p[4] - q[4]) > 0.01 or math.abs(p[5] - q[5]) > 0.01 then
			return false
		end
	end
	return true
end
function LOOK.TuneGeometry(tex, tune)
	local cur = LOOK.Points(tex)
	if not cur or #cur == 0 then
		return false
	end
	local base = LOOK.geomBase[tex]
	if not base or not LOOK.SamePoints(cur, LOOK.geomSet[tex]) then
		base = cur
		local ok, w, h = pcall(tex.GetSize, tex)
		if ok and not Secret(w) and not Secret(h) then
			base.w, base.h = w, h
		end
		LOOK.geomBase[tex] = base
	end
	local x, y = tune.x or 0, tune.y or 0
	local L, R, T, B = tune.padL or 0, tune.padR or 0, tune.padT or 0, tune.padB or 0
	local set = {}
	tex:ClearAllPoints()
	for i, p in ipairs(base) do
		local point = p[1]
		local px, py = p[4] + x, p[5] + y
		local centreX, centreY = not (point:find("LEFT") or point:find("RIGHT")), not (point:find("TOP") or point:find("BOTTOM"))
		-- a side's point moves with its side; one point alone keeps the box's middle in step with its growth
		if point:find("LEFT") then px = px - L elseif point:find("RIGHT") then px = px + R elseif #base == 1 and centreX then px = px + (R - L) / 2 end
		if point:find("TOP") then py = py + T elseif point:find("BOTTOM") then py = py - B elseif #base == 1 and centreY then py = py + (T - B) / 2 end
		tex:SetPoint(point, p[2], p[3], px, py)
		set[i] = { point, p[2], p[3], px, py }
	end
	if #base == 1 and base.w and base.h then
		tex:SetSize(math.max(1, base.w + L + R), math.max(1, base.h + T + B))
	end
	LOOK.geomSet[tex], LOOK.geomTune[tex] = set, tune
	return true
end
function LOOK.UntuneGeometry(tex)
	local base = LOOK.geomBase[tex]
	if base and LOOK.SamePoints(LOOK.Points(tex), LOOK.geomSet[tex]) then
		-- still where the tuning put it: back to its own points
		tex:ClearAllPoints()
		for _, p in ipairs(base) do
			tex:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
		if #base == 1 and base.w and base.h then
			tex:SetSize(base.w, base.h)
		end
	end
	LOOK.geomBase[tex], LOOK.geomSet[tex], LOOK.geomTune[tex] = nil, nil, nil
end

-- A window's texture tuned (Kit:TuneRegions; the kit editor's live drag): Kit:TuneTexture, and its place and size
-- (x, y, pad*; a replacement's own textures take their move from its rectangle instead, Kit:TuneObject).
-- A ring centred on the texture keeps its own place: the portrait moves under it (user, 2026-10-04).
function Kit:TuneRegion(tex, tune)
	self:TuneTexture(tex, tune)
	if tune and (tune.x or tune.y or tune.padL or tune.padR or tune.padT or tune.padB) then
		pcall(LOOK.TuneGeometry, tex, tune)
	elseif LOOK.geomBase[tex] then
		pcall(LOOK.UntuneGeometry, tex)
	end
	local ring = LOOK.centeredOn[tex]
	if ring and ring.tex then
		pcall(LOOK.CenterTune, ring, ring.tune)
	end
end

-- A texture its owner has just laid out again (a portrait fitted to its ring on every refresh): its tuning on the
-- new place, and the ring centred on it back where it was
function Kit:RefitRegion(tex)
	if not tex then
		return
	end
	local tune = LOOK.geomTune[tex]
	if tune then
		pcall(LOOK.TuneGeometry, tex, tune)
		local ring = LOOK.centeredOn[tex]
		if ring and ring.tex then
			pcall(LOOK.CenterTune, ring, ring.tune)
		end
	end
end

function Kit:TuneTexture(tex, tune)
	tune = tune or {}
	local had = Kit.tunedAt[tex] or nil
	local now = nil
	local function mark(field)
		now = now or {}
		now[field] = true
	end
	-- (Kit.pieceOf is `true` on a flat colour of ours: no piece to read)
	local piece = type(Kit.pieceOf[tex]) == "table" and Kit.pieceOf[tex] or nil
	-- the window of the file the art is cut from: the piece's uv, or under a
	-- texture of the tuning's own the piece's uv in its own former file
	-- (`was`: its rectangle in an atlas sheet means nothing on another file)
	local window = piece and piece.uv
	if tune.texture and piece and piece.was then
		window = piece.was
	end

	if tune.texture then
		if Kit.tunedArt[tex] == nil then
			Kit.tunedArt[tex] = (tex.GetTexture and tex:GetTexture()) or false
		end
		pcall(tex.SetTexture, tex, tune.texture)
		if piece and piece.was and not piece.tile then
			pcall(tex.SetTexCoord, tex, window[1], window[2], window[3], window[4])
		end
		mark("texture")
	elseif Kit.tunedArt[tex] ~= nil then
		if piece and Kit.pieceNameOf[tex] then
			self:Apply(tex, Kit.pieceNameOf[tex])
		elseif Kit.tunedArt[tex] then
			pcall(tex.SetTexture, tex, Kit.tunedArt[tex])
		end
		Kit.tunedArt[tex] = nil
	end

	local t = tune.tint
	if t then
		pcall(tex.SetVertexColor, tex, t[1] or 1, t[2] or 1, t[3] or 1, t[4])
		mark("tint")
	elseif had and had.tint then
		-- back to the tint whoever owns this texture last asked for
		local base = Kit.tintBaseOf[tex]
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
			if window then
				u1, u2, v1, v2 = window[1], window[2], window[3], window[4]
			end
			local c = tune.coord
			if c then
				local c1, c2, c3, c4 = c[1] or 0, c[2] or 1, c[3] or 0, c[4] or 1
				-- a crop reaching past the piece (the editor allows -1..2) is
				-- held at its edge in an atlas sheet: the neighbouring pieces
				-- lie there
				if piece and not tune.texture and InSheet(piece.file) then
					c1, c2 = math.max(0, math.min(1, c1)), math.max(0, math.min(1, c2))
					c3, c4 = math.max(0, math.min(1, c3)), math.max(0, math.min(1, c4))
				end
				local du, dv = u2 - u1, v2 - v1
				u1, u2 = u1 + du * c1, u1 + du * c2
				v1, v2 = v1 + dv * c3, v1 + dv * c4
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
			if window then
				pcall(tex.SetTexCoord, tex, window[1], window[2], window[3], window[4])
			else
				pcall(tex.SetTexCoord, tex, 0, 1, 0, 1)
			end
		end
	end

	Kit.tunedAt[tex] = now
end

-- (0.19.1) The editor's proxy rectangle on its element, the tuning's offsets on it. ProxyTo lays it on another
-- rectangle (a close button's face, Replace's rect = "normal": the plate hung from the face itself and the
-- editor's drag moved nothing, user 2026-10-04); CenterTune moves a piece centred on something other than its
-- rect (a portrait's ring on the portrait) by the same offsets, its size by the pads
function LOOK.PlaceProxy(rep, tune)
	local x, y = tune and tune.x or 0, tune and tune.y or 0
	rep.proxy:ClearAllPoints()
	rep.proxy:SetPoint("TOPLEFT", rep.proxyOf, "TOPLEFT", x - (tune and tune.padL or 0), y + (tune and tune.padT or 0))
	rep.proxy:SetPoint("BOTTOMRIGHT", rep.proxyOf, "BOTTOMRIGHT", x + (tune and tune.padR or 0), y - (tune and tune.padB or 0))
end
function LOOK.ProxyTo(rep, rect)
	if not rep.proxy then
		return rect
	end
	rep.proxyOf, rep.proxy.melloProxyOf = rect, rect
	LOOK.PlaceProxy(rep, rep.tune)
	return rep.proxy
end
function LOOK.CenterTune(rep, tune)
	local tex = rep.tex
	local L, R, T, B = tune and tune.padL or 0, tune and tune.padR or 0, tune and tune.padT or 0, tune and tune.padB or 0
	if not rep.centerSize then
		local w, h = tex:GetSize()
		if Secret(w) or Secret(h) then
			return
		end
		rep.centerSize = { w, h }
	end
	-- the centre's own move (a portrait moved by the editor, Kit:TuneRegion) taken back off: the ring stays
	-- where it was and the portrait moves under it; its middle moves by x + (R - L) / 2 however it is held
	local own = LOOK.geomTune[rep.centerOn]
	local ox = own and (own.x or 0) + ((own.padR or 0) - (own.padL or 0)) / 2 or 0
	local oy = own and (own.y or 0) + ((own.padT or 0) - (own.padB or 0)) / 2 or 0
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", rep.centerOn, rep.centerPoint or "CENTER", (tune and tune.x or 0) + (R - L) / 2 - ox, (tune and tune.y or 0) + (T - B) / 2 - oy)
	-- (a square piece that waited for its rect's size is sized by its sizer, from the proxy, pads and all)
	if not rep.sizer then
		tex:SetSize(math.max(1, rep.centerSize[1] + L + R), math.max(1, rep.centerSize[2] + T + B))
	end
end

-- The whole replacement: its rectangle (through the proxy made in Replace),
-- its alpha and every texture in it.
function Kit:TuneObject(rep, tune)
	local obj = rep.object
	if not obj then
		return
	end
	-- a tune arriving for a tab's open card whose rails still wait (it was
	-- untuned when dressed, the editor off): laid now, before the tune, so the
	-- tune lands on its textures as on a card built at dressing, and a tune
	-- taken off again later leaves it as it leaves every built card (review,
	-- 2026-09-24)
	if tune and rep.skin and rep.skin.pendingArt then
		LayRep(rep)
	end
	rep.tune = tune
	if rep.proxy and rep.proxyOf then
		LOOK.PlaceProxy(rep, tune)
		if rep.centerOn and rep.tex then
			pcall(LOOK.CenterTune, rep, tune)
		end
	elseif not InCombatLockdown() and not (obj.IsProtected and obj:IsProtected()) then
		-- (0.19.1) no proxy to move it by (built before the editor was there, or
		-- laid by its window's own code: the kit editor's drag did nothing,
		-- user 2026-10-04): its own frame moved against its own points
		if tune and (tune.x or tune.y or tune.padL or tune.padR or tune.padT or tune.padB) then
			pcall(LOOK.TuneGeometry, obj, tune)
		elseif LOOK.geomBase[obj] then
			pcall(LOOK.UntuneGeometry, obj)
		end
	end
	if obj.SetAlpha then
		pcall(obj.SetAlpha, obj, (tune and tune.alpha) or 1)
	end
	for _, tex in ipairs(self:Textures(rep)) do
		self:TuneTexture(tex, tune)
	end
	-- a tuned layer is the bar relayer's to follow again on the next fill change
	rep.relayered = nil
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
					Kit.tunedHidden[region] = true
					pcall(region.Hide, region)
				else
					if Kit.tunedHidden[region] then
						Kit.tunedHidden[region] = nil
						pcall(region.Show, region)
					end
					self:TuneRegion(region, tune)
				end
			elseif Kit.tunedAt[region] or Kit.tunedHidden[region] then
				-- it was changed and is not listed any more: put it back.
				-- Only ever a texture we touched, so the game's own tints and
				-- hidden states are left alone.
				if Kit.tunedHidden[region] then
					Kit.tunedHidden[region] = nil
					pcall(region.Show, region)
				end
				self:TuneRegion(region, nil)
			end
		end
	end
end

-- The frame kind under a button (a tab's card, a list row): its hover /
-- pressed / disabled tint, one handler per script for every such button
-- (user, 2026-09-24: shared handlers), the rep kept by its button
local frameTints = setmetatable({}, { __mode = "k" })   -- [button] = the rep it tints
-- the iron as painted: the one table the tint reads while nothing is checked
-- (a new { 1, 1, 1 } on every hover, leave, press and Update before)
local NO_TINT = { 1, 1, 1 }

local function FrameTint(rep, k)
	local on = rep.checked and rep.checked() and true or false
	local t = (on and rep.rule.checkedTint) or NO_TINT
	for _, tex in ipairs(rep.skin.art) do
		tex:SetVertexColor(math.min(t[1] * k, 1), math.min(t[2] * k, 1), math.min(t[3] * k, 1))
	end
	if rep.skin.body then
		rep.skin.body:SetVertexColor(math.min(k, 1), math.min(k, 1), math.min(k, 1))
	end
	-- the selected row's active look (Kit:SetActive), round its card
	if rep.checked then
		Kit:SetActive(rep.skin, on, rep.skin, "rect")
	end
end

local FrameTint_OnEnter = Shared("OnEnter on a kit frame's button", function(b)
	local rep = frameTints[b]
	rep.hover = true
	rep.Update()
end, "script")
local FrameTint_OnLeave = Shared("OnLeave on a kit frame's button", function(b)
	local rep = frameTints[b]
	rep.hover = nil
	rep.pressed = nil
	rep.Update()
end, "script")
local FrameTint_OnMouseDown = Shared("OnMouseDown on a kit frame's button", function(b)
	local rep = frameTints[b]
	rep.pressed = true
	pressedLatches[rep] = rep.Update
	rep.Update()
end, "script")
local FrameTint_OnMouseUp = Shared("OnMouseUp on a kit frame's button", function(b)
	local rep = frameTints[b]
	rep.pressed = nil
	rep.Update()
end, "script")
local FrameTint_OnSetEnabled = Shared("SetEnabled on a kit frame's button", function(b)
	frameTints[b].Update()
end)

-- A holder tiling one texture (the edge and tile kinds: holder.kitTile), and
-- a sizer re-fitting a tile that is a region (sizer.kitRefit): one handler
-- each for all of them
local Holder_OnSize = Shared("OnSizeChanged on a kit holder", function(f)
	Kit:Retile(f.kitTile)
end, "script")
local Holder_OnShow = Shared("OnShow on a kit holder", function(f)
	Kit:Retile(f.kitTile)
end, "script")
local Sizer_OnSize = Shared("OnSizeChanged on a kit tile's rect", function(f)
	f.kitRefit()
end, "script")
local Sizer_OnShow = Shared("OnShow on a kit tile's rect", function(f)
	f.kitRefit()
end, "script")

-- A slot's icon fitted into its rim again after the game re-anchors it: one
-- handler for every button's methods (slotIcons) and every kept icon's
-- SetPoint (keptIcons)
local ICON_METHODS = { "InitializeIconAnchoring", "UpdateIconInterior", "OnMouseDown", "OnMouseUp" }
local slotIcons = setmetatable({}, { __mode = "k" })   -- [button] = its slot rep
local keptIcons = setmetatable({}, { __mode = "k" })   -- [icon] = its slot rep
local SlotIcon_Refit = Shared("icon anchoring on a kit slot's button", function(b)
	local rep = slotIcons[b]
	if rep.object:IsShown() then
		Kit:SlotPlaceIcon(rep.object)
	end
end)
local SlotIcon_Keep = Shared("SetPoint on a kit slot's kept icon", function(icon)
	local rim = keptIcons[icon].object
	if rim:IsShown() and not rim.placingIcon then
		Kit:SlotPlaceIcon(rim)
	end
end)

-- The WINDOW a replacement is in: the top frame under UIParent (a title
-- container may sit in a page inside the window: the group finder's tabs
-- stayed behind when only the page moved — user, 2026-09-21)
local function WindowOf(frame)
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

-- A game window's portrait corner stays the game's (the user, 2026-10-10: "the sizes of the icons and their
-- borders in the top left returns to default values, and to not make any custom changes to them anymore"): no
-- ring of ours over it, its portrait neither fitted nor given a disc (the panels' FitPortrait / RingDisc need
-- the ring: without it they leave the portrait alone). MelloUI's own windows keep their corner ring (`own`:
-- KitWindow's DressRing), there being no game ring to keep. (No top-level local for the name: the file is at
-- Lua 5.1's 200.)
function Kit:Replace(region, opts)
	opts = opts or {}
	local key = opts.as or self:ArtKey(region)
	if key == "UI-Frame-PortraitMetal-CornerTopLeft" and not opts.own then
		-- (no key: a refusal, not a piece missing -- the panels' Replace helpers tell a missing piece by the key, and
		-- printed "no kit piece mapped" for every game window's corner; the user, 2026-10-10)
		return nil
	end
	-- (and the game's border round such a window, skipped at that corner: its
	-- other pieces faded one by one, not the whole border -- the corner ring is
	-- one of its pieces and would fade with it; its rail stubs cut, Kit:CutGameCorner)
	local keptCorner
	if key == "NineSlicePanelTemplate" and type(opts.skip) == "string" and opts.skip:find("tl", 1, true)
		and not opts.noFade then
		local corner = rawget(region, "TopLeftCorner")
		keptCorner = corner
		if corner then
			local fade = {}
			for _, t in ipairs(opts.alsoFade or {}) do
				fade[#fade + 1] = t
			end
			for _, t in ipairs(self:OtherTextures(region, corner)) do
				fade[#fade + 1] = t
			end
			opts.noFade, opts.alsoFade = true, fade
		end
	end
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
	-- (rule.atBorder: the rails alone at the game's border frame's level, one under it -- its corner ring stays over
	-- them -- on a frame of their own, Kit:NineSlice's edgeLevel; the skin, which a window hangs its stone and its
	-- sheets on, stays at the rule's level: raised whole, it covered the window -- in game, 2026-10-10)
	local edgeLevel
	if rule.atBorder and isFrame and not (tune and tune.level) and not opts.level then
		-- (two under the game's border frame: a title plate riding the rail lies one under it, over the rails --
		-- Kit:TitleBehindGameCorner; `railOver`, 0.20.1: seven over it, over the window's content and under its title
		-- bar and close button at 510, the plate one over the rails)
		local l = region:GetFrameLevel() + (rule.railOver and 7 or -2)
		if l > parent:GetFrameLevel() + level then
			edgeLevel = l
		end
	end
	-- fitHeight / fitWidth: the element's size as the template states it, used
	-- where its rect reads SECRET (the target's spell bar) or is not laid out yet
	local rep = Mixin({ kind = rule.kind, key = key, rule = rule, region = region, rect = rect, alsoFade = opts.alsoFade or {}, fitHeight = opts.fitHeight, fitWidth = opts.fitWidth, noFade = opts.noFade }, ReplacementMixin)
	rep.proxy, rep.proxyOf, rep.tune = proxy, proxy and proxy.melloProxyOf or nil, tune
	-- (the frame it is dressed on: a bag, a page of a window, a window -- each
	-- rail's shade its own, Modules/KitShade.lua)
	rep.kitParent = parent
	if keptCorner then
		rep.keptCorner = keptCorner   -- (0.20.1: the title plate on the rail runs behind it, Kit:TitleBehindGameCorner)
		self:CutGameCorner(rep, keptCorner)
	end

	if rule.kind == "frame" then
		local f = MakeHolder(parent, rect, level, opts.strata)
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
		-- `dim` (rule or opts; user, 2026-09-24: "apply the eye strain rule to
		-- all existing windows"): a box that holds text -- a list, an inset,
		-- a section of options -- gets the palette's inner panel over its
		-- stone inside the rail at that alpha (WINDOW-RULES 2e), a region of
		-- the box's own host, shown and hidden with it
		local dim = opts.dim
		if dim == nil then
			dim = rule.dim
		end
		-- opts.layWith (Kit:SkinPanelTab's open card): the skin's textures wait
		-- until the card is first to be seen, that is while this region (the
		-- game's own open art) shows (NineSlice's `defer`). Never while the
		-- editing tools are on or the element is tuned (their handles and
		-- tints work on the textures), nor for a skin that tints itself
		local defer = opts.layWith and not (tune or self.liveEdit or owner or dim or rule.corners)
			and not (opts.button and (rule.hover or rule.pressed or rule.disabled)) or nil
		rep.skin = self:NineSlice(f, { scale = fscale, gems = false, body = body, bodyScale = rule.bodyScale and self.scale * rule.bodyScale,
			open = opts.open or rule.open, prefix = rule.prefix or self.framePrefix, corners = rule.corners, skip = opts.skip,
			owner = owner, bodyLayer = rule.bodyLayer, bodySub = rule.bodySub, edgeLayer = rule.edgeLayer, edgeSub = rule.edgeSub,
			defer = defer, edgeLevel = edgeLevel })
		if key == "NineSlicePanelTemplate" and not rep.skin.pendingArt then
			self:TitleRail(rep, region)
		end
		if rep.skin.pendingArt then
			rep.layWith = opts.layWith
			f.kitWaiting = rep
			Perf.SetScript(f, "OnUpdate", Waiting_OnUpdate)
		end
		rep.checked = opts.checked
		rep.object = owner and rep.skin or f
		if dim and body and rep.skin.body then
			-- the fill on the frame the BODY is a region of (the skin frame, or
			-- the owner): on the holder it tied with the skin frame at one level
			-- and could draw under the stone, unseen
			local host = owner or rep.skin
			local inset = (rep.skin.thickness or 0) * 0.6
			local fill = host:CreateTexture(nil, rule.bodyLayer or "BACKGROUND", nil, math.min((rule.bodySub or 0) + 1, 7))
			fill:SetPoint("TOPLEFT", rep.skin, "TOPLEFT", inset, -inset)
			fill:SetPoint("BOTTOMRIGHT", rep.skin, "BOTTOMRIGHT", -inset, inset)
			-- opts.dimColor: another palette tone (a card or row lying ON a
			-- dimmed list takes the main window's tone, a stripe lighter than
			-- the panel around it, as WINDOW-RULES 2e has rows), its key or
			-- the palette's table; painted by its key (Kit:Paint), so a new
			-- palette paints it again. A colour of no palette role stays as given.
			local c = opts.dimColor
			local tone = c == nil and "innerPanel" or self:PaletteKeyOf(c)
			if tone then
				self:Paint(fill, tone, "fill", dim)
			elseif type(c) == "table" then
				fill:SetColorTexture(c[1], c[2], c[3], dim)
			end
			rep.skin.dimFill = fill
			table.insert(rep.skin.all, fill)
		end
		if rule.lit then
			rep.skin:SetTint(rule.lit[1], rule.lit[2], rule.lit[3])
		end
		-- `active`: the piece stands for the game's active / selected art
		-- (the open tab's card): the active look round it whenever it shows,
		-- as regions of its skin (made on the skin's first show)
		if rule.active then
			self:SetActive(rep.skin, true, rep.skin, "rect")
		end
		local button = opts.button
		if button and (rule.hover or rule.pressed or rule.disabled) then
			-- a frame under a button: its states are a tint of the whole
			-- skin (edges and body), hover lighter, pressed / disabled darker
			-- the iron takes the rule's checkedTint while opts.checked() (a
			-- selected row); the state factor multiplies both iron and body
			-- (FrameTint)
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
				FrameTint(rep, disabled and (rule.disabled or 1) or rep.pressed and (rule.pressed or 1) or rep.hover and (rule.hover or 1) or 1)
			end
			rep.Update = Update
			if frameTints[button] == nil then
				-- the shared handlers (FrameTint_*), the rep kept by its button
				frameTints[button] = rep
				Perf.HookScript(button, "OnEnter", FrameTint_OnEnter)
				Perf.HookScript(button, "OnLeave", FrameTint_OnLeave)
				Perf.HookScript(button, "OnMouseDown", FrameTint_OnMouseDown)
				Perf.HookScript(button, "OnMouseUp", FrameTint_OnMouseUp)
				if type(button.SetEnabled) == "function" then
					hooksecurefunc(button, "SetEnabled", FrameTint_OnSetEnabled)
				end
			else
				-- a second tinted frame on this button: handlers of its own, so
				-- every hook runs where it did
				Perf.HookScript(button, "OnEnter", function() rep.hover = true; Update() end)
				Perf.HookScript(button, "OnLeave", function() rep.hover = nil; rep.pressed = nil; Update() end)
				Perf.HookScript(button, "OnMouseDown", function() rep.pressed = true; pressedLatches[rep] = Update; Update() end)
				Perf.HookScript(button, "OnMouseUp", function() rep.pressed = nil; Update() end)
				if type(button.SetEnabled) == "function" then
					hooksecurefunc(button, "SetEnabled", Update)
				end
			end
			Update()
		end
	elseif rule.kind == "edge" then
		local f = MakeHolder(parent, rect, level, opts.strata)
		local tex = f:CreateTexture(nil, "OVERLAY")
		tex.kitScale = self.scale * (rule.scale or self.frameScale)
		self:Apply(tex, rule.piece, true)   -- (tiled below, once it is placed)
		tex:SetAllPoints(f)
		f.kitTile = tex
		Perf.SetScript(f, "OnSizeChanged", Holder_OnSize)
		Perf.HookScript(f, "OnShow", Holder_OnShow)
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
			Perf.HookScript(rect, "OnSizeChanged", Refit)
			Perf.HookScript(rect, "OnShow", Refit)   -- sized while hidden: no OnSizeChanged came
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
			Perf.HookScript(button, "OnEnter", function() rep.hover = true; Update() end)
			Perf.HookScript(button, "OnLeave", function() rep.hover = nil; rep.pressed = nil; Update() end)
			Perf.HookScript(button, "OnMouseDown", function() rep.pressed = true; pressedLatches[rep] = Update; Update() end)
			Perf.HookScript(button, "OnMouseUp", function() rep.pressed = nil; Update() end)
			if type(button.SetEnabled) == "function" then
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
			local function RailFit(self)
				-- the plate rides the OUTER rail across its whole width (user,
				-- 2026-09-23, layout C): centred on the rail's middle line, its
				-- caps' gems on the rail's top corners, where the frame's own
				-- gems were (they give way: RegisterShell); anchored to the
				-- window's top corners, so no layout is needed
				local lift, reach = Kit:TitleOnRail(self.strip)
				local out = Kit:OuterRailOutset() + reach
				-- (0.20.1) a window whose rail is laid outward (Kit:SkinWindowShell's `outward`): its sides that much
				-- further out
				local ow = Kit.outwardOf[window]
				local outR = out + (ow and ow.r or 0)
				-- with a portrait ring on the corner the plate starts at the
				-- ring's centre, its left cap left out: nothing of it shows
				-- left of the ring, the rest runs into the ring's hole (user,
				-- 2026-09-23: the cap past the ring "mask completely")
				local left = -(out + (ow and ow.l or 0))
				local ringX = self.behindRing and Kit:RingCentreX(self.behindRing, window)
				-- (0.20.1, the user: "sometimes when i open the character pane" -- after a /reload too -- the plate's
				-- left cap showed past the ring until the window was opened again: the plate at the ring's centre, its
				-- caps never laid again for the dropped one. Behind a ring the cap is always out, and the caps follow
				-- that whether or not the window's width can be read; a fit that could not read the ring or the width
				-- is fitted again on the next frame, a few times at most)
				self.strip.dropCap = self.behindRing and "l" or nil
				if ringX then
					left = ringX
				end
				-- the title stays over the window's middle, not the shorter plate's
				self.strip.textShift = -(left + outR) / 2
				self.strip:ClearAllPoints()
				self.strip:SetPoint("LEFT", window, "TOPLEFT", left, lift)
				self.strip:SetPoint("RIGHT", window, "TOPRIGHT", outR, lift)
				self.strip:SetHeight(self.strip.height)
				-- (the window's width tested for a secret before any compare)
				local okW, w = pcall(window.GetWidth, window)
				if not okW or Secret(w) or not (w and w > 0) then
					w = nil
				end
				self.strip:FitCaps(w and (w + outR - left) or nil)
				self.fitMiss = (self.behindRing and not ringX) and "ring" or (not w and "width") or nil
				-- (0.20.1, the user's design) the game's close button inside the plate, just left of its right cap: the
				-- cap's gem stands where the button stood, at the window's top right corner; its own anchors back on
				-- disable; a protected one left alone in a fight
				-- (an own window's close: Kit.ownClose, KitWindow.lua -- never a key on its frame)
				-- (a close of another frame's -- Kit.ownClose -- taken only by a shown window's plate: the group finder's
				-- three pages share their parent's, and a hidden page dressed in an idle turn must not take it from the
				-- page on show; each page's plate fits again as it shows)
				-- (a registered close first: the settings panel's CloseButton is its text button "Close" at the bottom, its X
				-- ClosePanelButton -- the user's screenshot, 2026-10-11: the text button stood in the plate)
				local own = Kit.ownClose[window]
				local close = (own and window:IsVisible() and own) or (not own and rawget(window, "CloseButton")) or nil
				if close and close.SetPoint and self.strip.capR
					and not (InCombatLockdown() and close.IsProtected and close:IsProtected()) then
					-- (the game's anchors kept once per button, not per plate: the group finder's three pages share
					-- their parent's close, each page's plate taking it while shown)
					if not Kit.closeSavedOf[close] then
						local saved = {}
						for i = 1, close:GetNumPoints() do
							saved[i] = { close:GetPoint(i) }
						end
						Kit.closeSavedOf[close] = saved
					end
					close:ClearAllPoints()
					close:SetPoint("RIGHT", self.strip.capR, "LEFT", 0, Kit:StripTextOffset(self.strip))
				end
			end
			rep.Refit = function(self)
				refit(self)
				if not window then
					return
				end
				-- (0.20.1) a fit that failed half way left the plate half laid (a game error is silent by default):
				-- reported as any error, kept for the dumps (Kit:DumpWindow's reps), fitted again
				local ok, err = pcall(RailFit, self)
				if not ok then
					self.fitMiss, self.fitError = "error", err
					geterrorhandler()(err)
				end
				-- the plate hangs on the ring and the window, which the game lays out in the frame it opens them:
				-- fitted once more a frame later, and again while the ring or the width cannot be read or the fit
				-- failed, a few times at most (Kit.TitleRefitLater)
				if self.fitMiss then
					if (self.fitTries or 0) < 5 then
						self.fitTries = (self.fitTries or 0) + 1
						Kit:NextFrame(self, Kit.TitleRefitLater)
					end
				else
					self.fitTries = nil
					if not self.fitLate then
						Kit:NextFrame(self, Kit.TitleRefitLater)
					end
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
					text:ClearAllPoints()
					text:SetPoint("CENTER", self.strip, "CENTER", self.strip.textShift or 0, Kit:StripTextOffset(self.strip))
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
			-- (0.20.1) the close button's own anchors back with the game's look
			local disable = rep.onDisable
			rep.onDisable = function(...)
				if disable then
					disable(...)
				end
				local close = window and (Kit.ownClose[window] or rawget(window, "CloseButton"))
				local saved = close and Kit.closeSavedOf[close]
				if saved and not (InCombatLockdown() and close.IsProtected and close:IsProtected()) then
					close:ClearAllPoints()
					for _, pt in ipairs(saved) do
						close:SetPoint(unpack(pt))
					end
					Kit.closeSavedOf[close] = nil
				end
			end
			-- the window may be laid out only when shown: fit again then
			Perf.SetScript(strip, "OnShow", function() rep:Refit() end)
		elseif rule.centreTitle and parent.TitleText then
			-- (0.20.1, the window titles on the game's title bar: the ribbon, the band) the title text centred on the
			-- strip's painted box, in the title face (WINDOW-RULES 2c); its own anchors back on disable
			local text = parent.TitleText
			local saved = {}
			for i = 1, text:GetNumPoints() do
				saved[i] = { text:GetPoint(i) }
			end
			local function Centre(self)
				text:ClearAllPoints()
				text:SetPoint("CENTER", self.strip, "CENTER", 0, Kit:StripTextOffset(self.strip))
				Kit:TitleFont(text, true)
			end
			rep.onEnable = Centre
			local refit = rep.Refit
			rep.Refit = function(self)
				refit(self)
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
		local edit = opts.edit
		if edit then
			-- a plate under an edit box: its focused look while it has focus
			Perf.HookScript(edit, "OnEditFocusGained", function() rep:SetState("focused") end)
			Perf.HookScript(edit, "OnEditFocusLost", function() rep:SetState(rule.state or Kit:FirstState(rule.base, "mid")) end)
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
			-- layout: fit it again after each (SlotIcon_Refit, the rep kept by
			-- its button; a second slot on the button has handlers of its own)
			local shared = slotIcons[button] == nil
			if shared then
				slotIcons[button] = rep
			end
			for _, m in ipairs(ICON_METHODS) do
				if button[m] then
					hooksecurefunc(button, m, shared and SlotIcon_Refit or function()
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
				if keptIcons[icon] == nil then
					keptIcons[icon] = rep
					hooksecurefunc(icon, "SetPoint", SlotIcon_Keep)
				else
					hooksecurefunc(icon, "SetPoint", function()
						if rep.object:IsShown() and not rim.placingIcon then
							self:SlotPlaceIcon(rim)
						end
					end)
				end
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
			rect = LOOK.ProxyTo(rep, button:GetNormalTexture())
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
	elseif rule.kind == "flat" then
		-- (0.19.1; the user, 2026-10-04: "from now on only use the same style as
		-- we have in the Configurator") the Configurator's flat control over
		-- the game's (MelloUI.Widgets.FlatOver: its plate, caret, field, tab,
		-- track or knob; 0.19.9 the kit's NewUI2 check box, close, arrow, + / -
		-- or cog), on a holder of ours on the rect; painted by the control's
		-- state (FlatState) as a rim follows its button: an empty region of the
		-- holder is the rim FollowButton drives, Slot_Update painting the parts
		local button = opts.button or (isFrame and region) or parent
		if rule.rect == "normal" and button and button.GetNormalTexture and button:GetNormalTexture() then
			rect = LOOK.ProxyTo(rep, button:GetNormalTexture())
		end
		local f = MakeHolder(parent, rect, level, opts.strata)
		-- opts.fitHeight (an old dropdown's 24 px box in its taller frame): the
		-- plate that tall, centred on the rect
		local fit = opts.fitHeight
		if fit and fit > 0 then
			f:ClearAllPoints()
			f:SetPoint("LEFT", rect, "LEFT", 0, 0)
			f:SetPoint("RIGHT", rect, "RIGHT", 0, 0)
			f:SetHeight(fit)
		end
		-- (the call's own: an edit box's fill over its glass -- the search
		-- box's only, opts.left -- and body = false, the edge alone)
		local parts = MelloUI.Widgets.FlatOver(f, rule.flat, { dir = rule.dir, left = opts.left, body = opts.body, glyph = rule.glyph })
		local driver = f:CreateTexture(nil, "BACKGROUND")
		driver:SetAlpha(0)
		driver:SetAllPoints(f)
		Kit.pieceOf[driver] = true   -- ours: never faded as the game's art
		driver.button, driver.flatParts, driver.isChecked = button, parts, opts.checked
		-- (no flat control wears the active look: a ticked check box is its
		-- ticked plate, 0.19.9)
		driver.activeFamily = false
		if button and button.HookScript then
			FollowButton(driver, button)
			local list = flatButtons[button]
			if not list then
				list = {}
				flatButtons[button] = list
				if type(button.Enable) == "function" then
					hooksecurefunc(button, "Enable", FlatButton_Enabled)
				end
				if type(button.Disable) == "function" then
					hooksecurefunc(button, "Disable", FlatButton_Enabled)
				end
			end
			list[#list + 1] = driver
		end
		local edit = opts.edit
		if rule.flat == "edit" and edit and edit.HookScript then
			flatFields[edit] = driver
			Perf.HookScript(edit, "OnEditFocusGained", FlatField_Focus)
			Perf.HookScript(edit, "OnEditFocusLost", FlatField_Focus)
		end
		-- `rotates` (an arrow the game turns by rotating its art: the bag
		-- bar's): the flat arrow follows that rotation, a quarter at a time
		if rule.rotates and rule.flat == "arrow" and not isFrame and region.SetRotation then
			flatTurns[region] = parts
			parts.turnFrom = FLAT_TURN_OF[rule.dir or "left"] or 0
			hooksecurefunc(region, "SetRotation", FlatArrow_Turn)
			if region.GetRotation then
				FlatArrow_Turn(region, region:GetRotation())
			end
		end
		Slot_Update(driver)
		-- `active` (the open tab): the active look round the holder whenever
		-- it shows, as regions of it -- the Configurator's open tab wears it too
		if rule.active then
			self:SetActive(f, true, f, "rect")
		end
		rep.object, rep.rect, rep.flat, rep.flatDriver = f, rect, parts, driver
		-- (a panel that reads a plate's opening: a flat control's face is its whole rect)
		rep.GetOpening = FlatOpening
	elseif rule.kind == "active" then
		-- a check button of the game's own art the kit does not dress (the
		-- extra action button, the vehicle bar's): the active look in place
		-- of its checked art (the region, faded; noFade where the button has
		-- none), following its checked flag as a rim does. The object is an
		-- empty region on the button, drawing nothing, that the rims'
		-- followers read (FollowButton: its SetChecked, clicks, the bars'
		-- events, the pass after a fight)
		local button = opts.button or parent
		local mark = button:CreateTexture(nil, "OVERLAY")
		mark:SetAllPoints(button)
		mark:SetAlpha(0)
		Kit.pieceOf[mark] = true   -- ours: never faded as the game's art
		mark.button, mark.icon, mark.activeFamily = button, opts.icon, "look"
		FollowButton(mark, button)
		Slot_Update(mark)
		rep.object = mark
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
				Perf.HookScript(button, script, function() rep:SetState() end)
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
		-- Progress Bar Border; the nameplates', the unit frames' and the cast
		-- bar's their own, 0.19.8: Nameplate / Unit Frame / Cast Bar Border)
		local group = rule.borderGroup or (rule.bar ~= "castbar" and "bar") or nil
		if opts.ownBorder then
			group = nil   -- (0.20.1: a bar whose own panel lays its border, opts.bar and rep:SetBar: the swing timers')
		end
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
		rep.barParent, rep.borderGroup = parent, group   -- (the border library's: Kit:BarLibraryBorder)
		-- a StatusBar's fill can change layer after the bracket was placed
		-- (Bar Textures sets its own fill texture, which comes up at ARTWORK
		-- where the game's was at BACKGROUND): the bracket and trough follow
		-- the fill's layer on every SetStatusBarTexture (user, 2026-09-21:
		-- the unit frame fills came up over their brackets)
		if opts.layer and parent.SetStatusBarTexture and parent.GetStatusBarTexture then
			-- Some fills are re-set dozens of times a second (the target of
			-- target's, 41 a second in /melloperf 2026-09-24: the game's own
			-- updates, and Bar Textures putting its texture straight back):
			-- the layers are set only when they change. `relayered` is
			-- forgotten when the tuning touches the pieces (Kit:TuneObject).
			rep.Relayer = function(self)
				local layer, sub, tl, ts = Kit:BracketLayers(parent, true)
				if not layer then
					return   -- unreadable (secret) on this bar: the bracket stays where it was placed
				end
				if self.relayered == layer and self.relayeredSub == sub then
					return
				end
				self.relayered, self.relayeredSub = layer, sub
				self.strip.capL:SetDrawLayer(layer, sub)
				self.strip.capR:SetDrawLayer(layer, sub)
				self.strip.mid:SetDrawLayer(layer, sub - 1)
				if self.libraryBorder then
					self.libraryBorder:SetLayer(layer, sub)   -- (0.19.8: a library style in the bracket's place)
				end
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
			if self.libraryStyle then
				return 0, 0   -- (0.19.8: a library style lies round the bar: no arm takes its width)
			end
			local sc = self.strip.scale
			local capL, capR = PIECES[StripName(self.base, "cap_l")], PIECES[StripName(self.base, "cap_r")]
			local l = capL and capL.open and capL.open[1] * sc or self.strip.wl or 0
			local r = capR and capR.open and (capR.w - capR.open[3]) * sc or self.strip.wr or 0
			return l, r
		end
		-- the bracket's fill area as insets from the rect: sideways from the
		-- caps' hollow arms (past the gems) a little under the gems' bezels,
		-- top / bottom most of the way into the rails, so the rails cover the edges
		-- (0.20.1) the panel's art scale, and the share of the rect's height a library style's border lies round (the
		-- bracket's own fit: KitBorders' BarLibraryFit)
		rep.ArtScale = function()
			return opts.artScale or rule.artScale or 1
		end
		rep.LibraryShare = function(self)
			return (rule.heightScale or 1) * self:ArtScale()
		end
		-- the bar's frame, top to bottom, in UI px (a library border's band and rails, else the bracket's height):
		-- what a row's highlight fits (CharacterPanel's reputation and skill rows); nil while it reads nothing
		rep.OuterHeight = function(self)
			if self.libraryStyle and self.libBand and self.libraryBorder then
				local ok, h = pcall(self.libBand.GetHeight, self.libBand)
				if not ok or Secret(h) or not (h and h > 0) then
					return nil
				end
				local _, y = self.libraryBorder:Inset()
				return h + 2 * y
			end
			return self.strip and self.strip.height or nil
		end
		rep.GetOpening = function(self)
			if self.libraryStyle then
				-- (0.19.8: round the bar: the fill its whole width; 0.20.1: its height the band the border lies round)
				local rectH = self:RectSize("GetHeight")
				if not (rectH and rectH > 0) then
					rectH = self.fitHeight or 0
				end
				local m = rectH * (1 - self:LibraryShare()) / 2
				return 0, 0, m, m
			end
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
			-- (rep.thicken: set by the panel that sets the fill in from the rect
			-- -- the nameplates', its edges at the rails' centres: NameplatePanel)
			local thicken = self.thicken or opts.thicken or rule.thicken or 0
			local yoff = self.strip:FitBox((h + thicken) * (rule.heightScale or 1) * artScale)
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
			if self.libraryStyle and Kit.BarLibraryFit then
				Kit:BarLibraryFit(self, h)   -- (0.20.1: the library border fitted to the bar as the bracket is)
			end
		end
		rep.SetBar = function(self, bar)
			-- (0.19.8) a style of the border library's: drawn by it round the
			-- bar, the bracket put out (Modules/KitBorders.lua); another look
			-- puts such a border away first
			if Kit.BarLibraryBorder and Kit:BarLibraryBorder(self, bar) then
				return
			end
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
		strip.Show = function(f)
			show(f)
			trough:Show()
			if rep.libraryStyle then
				rep.libraryBorder:SetShown(true)
			end
		end
		strip.Hide = function(f)
			hide(f)
			trough:Hide()
			if rep.libraryBorder then
				rep.libraryBorder:SetShown(false)
			end
		end
		-- (0.19.8) the group's look a library style: laid now
		if group and self.BarLibraryBorder then
			self:BarLibraryBorder(rep, opts.bar or self:BorderValue(group))
		end
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
			f = MakeHolder(parent, rect, level, opts.strata)
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
		-- `edgeBacking`: a tiled piece right under the picture, on the same
		-- rect, so the gaps between the strokes show stone and not whatever
		-- lies behind the window (user, 2026-09-23: the quest log over the
		-- world map, MelloUI's quest list: "add the dark cracked concrete
		-- behind")
		local function Backing()
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
				return backing
			end
			backing:Hide()
			return nil
		end
		-- `parchment` (0.20.1): the page is a paper (Kit:Paper) on the picture's rect, in the Parchment Style's look
		-- (0.20.3): the parchment nine in the picture's layer (Kit:ParchmentNine; a string names its curls), the
		-- picture hidden under it; or the classic one (0.20.0's), the picture itself ending in the painted strokes
		-- with its `edgeMirror` and `edgeBacking` (below)
		if rule.parchment then
			local l, sl = tex:GetDrawLayer()
			local host = tex:GetParent()
			tex:Hide()
			rep.paper = self:Paper(host, function(p) p:SetAllPoints(inner) end, {
				paper = function(paper)
					return self:ParchmentNine(host, { layParent = paper, place = function(p) p:SetAllPoints(inner) end, layer = l,
						sublevel = sl, curls = type(rule.parchment) == "string" and rule.parchment or nil, scale = self.parchment.page })
				end,
				classic = function()
					rep.edge = self:PaintedEdge(tex, inner, rule.edgeMirror)
					rep.backing = rule.edgeBacking and Backing() or nil
					return self:ClassicLook({ tex, rep.backing }, tex, rep.edge, function()
						if rep.Refit then
							rep:Refit()
						end
					end)
				end,
			})
			if rep.object == tex then
				rep.object = rep.paper
			end
		else
			-- `edge` = "brush": the picture ends in painted strokes on every side
			-- (Kit:PaintedEdge); `edgeMirror` flips them for a left-hand page
			if rule.edge then
				rep.edge = self:PaintedEdge(tex, inner, rule.edgeMirror)
			end
			if rule.edgeBacking then
				rep.backing = Backing()
			end
		end
		rep.Refit = function(self)
			-- rep:SetPiece(value): a panel's background choice in place of
			-- the rule's piece ("dark": a flat fill)
			if self.pieceOverride == "dark" then
				-- the palette's inner panel, by its key: a new palette paints
				-- it again (Kit:Paint)
				Kit:Paint(self.tex, "innerPanel", "fill", 0.95)
				Kit.pieceOf[self.tex], Kit.pieceNameOf[self.tex] = true, nil
				return
			end
			local name = self.pieceOverride or ((self.grey and rule.grey and self.grey()) and rule.grey or rule.piece)
			if Kit.pieceNameOf[self.tex] ~= name then
				Kit:Unpaint(self.tex)   -- (a dark fill before: the piece stays when the palette changes)
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
				if Kit.pieceNameOf[self.filler] ~= name then
					Kit:Apply(self.filler, name)
				end
				self.filler:ClearAllPoints()
				self.filler:SetPoint("TOPLEFT", self.inner, "TOPLEFT")
				self.filler:SetPoint("BOTTOMRIGHT", self.tex, "BOTTOMLEFT")
				-- (in an atlas sheet never past the piece's own columns: a
				-- rect over twice the picture's width shows them stretched)
				local share = (w - picW) / picW
				if share > 1 and InSheet(p.file) then
					share = 1
				end
				self.filler:SetTexCoord(u1 + (u2 - u1) * share, u1, v1, v2)
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
		Perf.SetScript(inner, "OnSizeChanged", function() rep:Refit() end)
		-- a page hidden while the skin is built has no size to fit to (the
		-- whole painting would stay stretched on it): fit again when it shows
		Perf.SetScript(inner, "OnShow", function() rep:Refit() end)
		if rule.frame and rep.object == f then
			rep.skin = self:NineSlice(f, { scale = self.scale * self.frameScale, gems = false, body = false, prefix = self.framePrefix })
		end
		rep:Refit()
	elseif rule.kind == "fade" then
		-- nothing stands in: the region is faded while the skin is on. Its
		-- holder is made when something asks for rep.object (BareRep), or at
		-- once where the editing tools want one to move (their proxy, a tune)
		if tune or self.liveEdit then
			rep.object = MakeHolder(parent, rect, level, opts.strata)
		else
			rep.holderParent, rep.holderLevel, rep.holderStrata, rep.holderShown = parent, level, opts.strata, true
			setmetatable(rep, BareRep)
		end
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
			f = MakeHolder(parent, rect, level, opts.strata)
			tex = f:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints(f)
			f.kitTile = tex
			Perf.SetScript(f, "OnSizeChanged", Holder_OnSize)
			Perf.HookScript(f, "OnShow", Holder_OnShow)
		end
		tex.kitScale = self.scale * (rule.scale or 1)
		-- (tiled by Refit below, once the edge is on)
		self:Apply(tex, rule.piece, true)
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
			-- a region has no OnSizeChanged: re-tile on the rect's. opts.sizer:
			-- the rect itself when it is a frame of the caller's own (an action
			-- slot's opening), whose scripts serve, where a frame was made for it
			-- per slot (user, 2026-09-24: the bags' first open); not when the
			-- editing tools' proxy stands in as the rect
			local sizer = opts.sizer
			if sizer ~= rect then
				sizer = CreateFrame("Frame", nil, f)
				sizer:EnableMouse(false)
				sizer:SetAllPoints(rect)
			end
			sizer.kitRefit = Refit
			Perf.SetScript(sizer, "OnSizeChanged", Sizer_OnSize)
			Perf.HookScript(sizer, "OnShow", Sizer_OnShow)
		elseif edge then
			Perf.SetScript(f, "OnSizeChanged", Refit)
			Perf.HookScript(f, "OnShow", Refit)
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
			f = MakeHolder(parent, rect, level, opts.strata)
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
				Perf.SetScript(f, "OnSizeChanged", function(_, _, nh)
					if nh and not Secret(nh) and nh > 0 then
						tex:SetSize(piece and nh * piece.w / piece.h or nh, nh)
					end
				end)
			end
		elseif rule.square or rule.opening then
			local function SquareSize(w, h)
				if not (w and h) or Secret(w) or Secret(h) then
					return 0
				end
				-- (0.19.8: the piece it wears, a ring style's as the portrait ring: rep.ringPiece, KitBorders)
				local piece = PIECES[rep.ringPiece or rule.piece]
				local size = math.min(w > 0 and w or h, h > 0 and h or w)
				-- (0.19.9) `body`: the ring's round body where that piece's would be (the winged border on a
				-- window's corner: the gem ring's body, its wings past the rect)
				local body = rule.body and PIECES[rule.body]
				if body and piece and piece.radius and body.radius and piece.radius > 0 then
					size = size * (piece.w / piece.radius) / (body.w / body.radius)
				end
				if size > 0 and rule.opening and piece and piece.open then
					-- the rect is the OPENING: the canvas grows around it by the
					-- piece's ratio (a ring around the game's own portrait);
					-- `openingScale` shrinks that (the minimap's ring at 0.75, its
					-- rim over the map's edge — user, 2026-09-21)
					size = size * piece.w / (piece.open[3] - piece.open[1]) * (rule.openingScale or 1)
				end
				return size
			end
			local okS, w, h = pcall(rect.GetSize, rect)
			local size = okS and SquareSize(w, h) or 0
			if size <= 0 then
				-- the rect gives no size yet (a proxy made this frame, a region
				-- not laid out, a secret read): the piece at its own size
				-- meanwhile -- never none, which draws it at its FILE's size, a
				-- whole atlas sheet (1024 x 512) -- and fitted once the rect has one
				size = (self:Size(rule.piece, self.scale))
				local sizer = CreateFrame("Frame", nil, f)
				sizer:EnableMouse(false)
				sizer:SetAllPoints(rect)
				Perf.SetScript(sizer, "OnSizeChanged", function(_, nw, nh)
					local s = SquareSize(nw, nh)
					if s > 0 then
						tex:SetSize(s, s)
					end
				end)
				rep.sizer = sizer   -- (it sizes the piece from the proxy, pads and all: LOOK.CenterTune)
			end
			tex:SetSize(size, size)
			tex:SetPoint("CENTER", opts.center or rect, "CENTER")
			-- (0.19.8) sized again for the piece it wears now, coming from piece `from` (Kit:LayPortraitRing): the
			-- opening kept at its size -- never read from the rect again, which a fitted portrait is itself sized
			-- by the ring (Kit:FitPortrait: it would feed back)
			rep.Resquare = function(from)
				local a, b = PIECES[from or rule.piece], PIECES[rep.ringPiece or rule.piece]
				local okW, tw = pcall(tex.GetWidth, tex)
				if not (okW and tw and not Secret(tw) and tw > 0 and a and b and a.open and b.open) then
					return
				end
				local s = tw * ((a.open[3] - a.open[1]) / a.w) / ((b.open[3] - b.open[1]) / b.w)
				tex:SetSize(s, s)
			end
		else
			tex:SetAllPoints(rule.owner and rect or f)
		end
		-- (0.19.1) a piece centred on something other than its rect (a portrait's ring on the portrait) follows the
		-- editor's drag by its own anchor: the holder moved with the proxy and the ring stayed; and it keeps its
		-- place when that something is moved under it (Kit:TuneRegion; user, 2026-10-04)
		if opts.center and (rule.natural or rule.square or rule.opening) then
			rep.centerOn, rep.centerPoint = opts.center, rule.natural and opts.centerPoint or nil
			LOOK.centeredOn[opts.center] = rep
		end
		rep.object, rep.tex = (rule.owner and not isFrame) and tex or f, tex
	end
	local object = rawget(rep, "object")
	if object then
		object:Hide()
		-- (a rim read while it was made, shown: its active look waits for the
		-- rep's Enable too)
		if object.Update == Slot_Update and self:RimDrivesLook(object) then
			self:SetActive(object.button, false)
		end
	else
		rep.holderShown = false
	end
	-- every window's outer rail and title plate are known to the window
	-- mover (Core/EditLayoutWindows.lua), whichever panel dressed the window: the
	-- older panels replace these two by hand, not through SkinWindowShell
	-- (the window: WindowOf)
	if key == "TitleBar" and parent and parent.GetParent then
		local window = WindowOf(parent:GetParent())
		if window and window ~= UIParent then
			RegisterShell(window, { title = rep })
		end
	elseif key == "NineSlicePanelTemplate" and parent then
		local window = WindowOf(parent)
		if window and window ~= UIParent then
			RegisterShell(window, { outer = rep })
		end
	elseif key == "UI-Frame-PortraitMetal-CornerTopLeft" and parent then
		local window = WindowOf(parent)
		if window and window ~= UIParent then
			RegisterShell(window, { ring = rep })
		end
	elseif (key == "MelloUI-Crest" or key == "MelloUI-TitlePlate") and parent then
		-- an own window's crest and the short plate under it (Kit:OwnWindow:
		-- their frames the window's own children): known for their shade,
		-- never a drag handle or a ring. A crest inside a page (the
		-- installer's Keep ring) is no part of the window's outline.
		local window = WindowOf(parent)
		if window and window ~= UIParent and parent:GetParent() == window then
			RegisterShell(window, key == "MelloUI-Crest" and { crest = rep } or { plate = rep })
		end
	end
	rep.window = WindowOf(parent)
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
	if Kit.repOf[bar] ~= nil then
		return Kit.repOf[bar] or nil
	end
	local track, thumb = bar.Track, bar.Track and bar.Track.Thumb
	if not (track and thumb and track.Middle and thumb.Middle) then
		Kit.repOf[bar] = false
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
	Perf.HookScript(thumb, "OnSizeChanged", function()
		for _, rep in ipairs(reps) do
			if rep.vstrip and rep.object:IsShown() then
				rep:Refit()
			end
		end
	end)
	Kit.repOf[bar] = reps
	return reps
end

-- A frame's children without a table per frame (user, 2026-09-24: the
-- walks below built { root:GetChildren() } at every frame they visited, ~0.16
-- KB each, hundreds a walk): packed into a list kept per level of the walk
-- and used again. A list still in use (a walk started from inside another,
-- a walk an error left) is left to it, and that level gets a new one.
local walkLists = {}   -- [depth] = { busy = , [1..n] = children }

-- eight at a time: select() copies only what follows, never a table
local function Fill(list, i, n, a, b, c, d, e, f, g, h, ...)
	list[i], list[i + 1], list[i + 2], list[i + 3] = a, b, c, d
	list[i + 4], list[i + 5], list[i + 6], list[i + 7] = e, f, g, h
	if n > 8 then
		return Fill(list, i + 8, n - 8, ...)
	end
end
local function Pack(list, ...)
	local n = select("#", ...)
	if n > 0 then
		Fill(list, 1, n, ...)
	end
	return n
end

-- the list of `frame`'s children for a walk at `depth`, and how many; hand
-- it back with WalkDone when the walk is through it
local function WalkChildren(frame, depth)
	local list = walkLists[depth]
	if not list or list.busy then
		list = {}
		walkLists[depth] = list
	end
	list.busy = true
	return list, Pack(list, frame:GetChildren())
end
local function WalkDone(list)
	list.busy = false
end

-- Every MinimalScrollBar under `root` (a frame with Track / Thumb / Back /
-- Forward), skinned with `replace`; `skip` is a frame never walked into.
-- The same walk asked for again in one frame (the same root, replace and
-- skip) with no frame made anywhere since (GetNumFrames) has nothing new to
-- find and is not walked again (user, 2026-09-24: the walk asked for twice
-- and three times in the frame a window opened; the world map's and the quest
-- map's shows both ask for it -- the spell book keeps its own once a frame).
-- Only within the frame: a later show walks again, so a scroll bar moved in
-- under the root since (a reparent makes no frame) is still found.
local walked = setmetatable({}, { __mode = "k" })   -- [root] = { at, frames, replace, skip }
local GetNumFrames = _G.GetNumFrames

function Kit:SkinScrollBarsIn(root, replace, skip, depth)
	local top = depth == nil
	depth = depth or 0
	if depth > 7 or root == skip then
		return
	end
	local last = top and GetNumFrames and walked[root]
	if last and last.replace == replace and last.skip == skip and last.at == GetTime() and last.frames == GetNumFrames() then
		return
	end
	local list, n = WalkChildren(root, depth)
	for i = 1, n do
		local child = list[i]
		if child.Track and child.Track.Thumb and child.Back and child.Forward then
			self:SkinScrollBar(child, replace)     -- `replace` enables the reps itself when the skin is active
		else
			self:SkinScrollBarsIn(child, replace, skip, depth + 1)
		end
	end
	WalkDone(list)
	if top and GetNumFrames then
		last = walked[root]
		if not last then
			last = {}
			walked[root] = last
		end
		last.at, last.frames, last.replace, last.skip = GetTime(), GetNumFrames(), replace, skip
	end
end

-- A glyph the game re-atlases with a state (a header's +/-, a toggle's
-- open/closed): one replacement per atlas it has shown, kept on `owner`
-- (Kit.stateIconsOf[owner]), the one for its current atlas shown. `replace` is the
-- panel's registering Replace; `extra` other regions to fade with it.
-- `follow` (0.20.1): the game shows and hides the glyph itself (a Legacy card's
-- +/-, only on a card that can expand: the user's screenshots, its plate stood
-- over the description the game had moved into its place) -- the plate only
-- while the glyph is shown, again on each Show / Hide / SetShown of it. (Not
-- for a button's state texture: the button hides that one itself while pressed.)
function Kit:StateIconReps(owner, icon, button, replace, extra, follow)
	if not (owner and icon) then
		return
	end
	Kit.stateIconsOf[owner] = Kit.stateIconsOf[owner] or {}
	local key = self:ArtKey(icon)
	if key and self:RuleFor(key) and Kit.stateIconsOf[owner][key] == nil then
		local rep = replace(icon, { as = key, button = button or owner, rect = icon, alsoFade = extra }) or false
		Kit.stateIconsOf[owner][key] = rep
		if rep then
			local enable = rep.onEnable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				Kit:StateIconReps(owner, icon, button, replace, extra, follow)
			end
		end
	end
	if follow and not Kit.stateIconFollowOf[icon] then
		Kit.stateIconFollowOf[icon] = owner
		for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
			hooksecurefunc(icon, method, Kit.StateIcon_OnShown)
		end
	end
	local shown = not follow or icon:IsShown()
	for k, rep in pairs(Kit.stateIconsOf[owner]) do
		if rep then
			rep:SetShown(shown and k == key)
		end
	end
end

-- (a followed glyph shown or hidden by the game: its plates with it, while the skin holds it -- faded under them)
Kit.stateIconFollowOf = Kept.stateIconFollowOf   -- [glyph] = its owner (Kit:StateIconReps' `follow`)
function Kit.StateIcon_OnShown(icon)
	local owner = Kit.stateIconFollowOf[icon]
	local reps = owner and Kit.faded[icon] and Kit.stateIconsOf[owner]
	if not reps then
		return
	end
	local key, shown = Kit:ArtKey(icon), icon:IsShown()
	for k, rep in pairs(reps) do
		if rep then
			rep:SetShown(shown and k == key)
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
		if region:GetObjectType() == "Texture" and not Kit.pieceOf[region] then
			return region
		end
	end
end

-- Every game texture of a button but `keep` (to fade with its normal art).
function Kit:OtherTextures(button, keep)
	local extra = {}
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= keep and not Kit.pieceOf[region] then
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
	local rule = self:WindowFrameRule()
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

-- (0.20.5) A window's page inside its outer rail, as insets from the window ({ l, r, t, b }, UI px): the rail's depth
-- on each side, or -- its rail laid outward round it (Kit:SkinWindowShell's `outward`, Kit.outwardOf) -- the top
-- only, the page reaching the sides and bottom, where the rail's inner edge lies on the window's. Every page uses it:
-- the shell's, a window laying its own (the loot window's flat Bg; the user: its stone stopped a rail short of the
-- rail, the world showing between), a page's width (the mail window's)
function Kit:PageInset(frame)
	local inset = self:OuterRailInset()
	if frame and Kit.outwardOf[frame] then
		return { 0, 0, inset[3], 0 }
	end
	return inset
end

-- The class medallion's size in the character window's ring: the size every
-- portrait icon and ring disc is brought to (WINDOW-RULES 2b).
local MEDALLION_TO_RING = 0.759
-- the class medallion's painted disc spans this much of its texture (the
-- plain variant's opaque width: 243 of 256 px)
local MEDALLION_DISC = 0.95

-- The class medallion's size in a ring's texture (0.759 x the gem ring). A
-- ring of another share of opening to width (a ring style, 0.19.8; the
-- windows' winged border, 0.19.9) keeps the gem ring's medallion-to-opening
-- measure. Kit:FitPortrait and Kit:RingDisc size by it.
function Kit:MedallionSize(tex)
	local size = tex:GetWidth() * MEDALLION_TO_RING
	local worn, gem = PIECES[Kit.pieceNameOf[tex] or ""], PIECES["window/portrait_ring"]
	if worn and gem and worn.open and gem.open and worn.w ~= gem.w then
		size = size * ((worn.open[3] - worn.open[1]) / worn.w) / ((gem.open[3] - gem.open[1]) / gem.w)
	end
	return size
end

-- A dark disc in a portrait ring's opening, under the portrait (an agreed
-- addition, user 2026-09-21: the Legacy shield does not fill the ring, the
-- page showed through). A region of the ring holder's parent (the game's
-- PortraitContainer, level 400: its portrait is OVERLAY, the disc goes in
-- BACKGROUND under it), masked round with the game's own circle mask, the
-- class medallion's size on the ring's centre; shown / hidden with the
-- ring's replacement. `color`: a palette key, "innerPanel" when none is
-- given (painted by its key, Kit:Paint, so a new palette paints it again).
-- `parent` / `sublevel` override the frame and BACKGROUND sublevel the disc is
-- a region of, for a window whose portrait lives elsewhere (the guild window's
-- PortraitOverlay at level 300, its portrait BACKGROUND 1: the disc at 0).
function Kit:RingDisc(ring, color, parent, sublevel)
	if not (ring and ring.tex and ring.object) then
		return nil
	end
	parent = parent or ring.object:GetParent()
	local disc = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel or 7)
	Kit.pieceOf[disc] = true
	self:Paint(disc, color or "innerPanel", "fill", 1)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(disc)
	disc:AddMaskTexture(mask)
	-- the disc is the class medallion's size (0.759 x the ring, user
	-- 2026-09-21), the same as a portrait fitted by Kit:FitPortrait
	local function Fit()
		local size = Kit:MedallionSize(ring.tex)
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

-- The title plate riding the outer rail (the TitleBar rule's `onRail`):
-- the lift of the plate's centre above the window's top edge and how far each
-- end reaches past the rail's outer edge, so that its caps' gems sit where the
-- rail's own corner gems were, their centres on the rail's middle line.
local RAIL_GEM_IN = 20            -- the corner gems' centres, piece px in from the rail's outer corner (window/frame_gem_tl / _tr)
local CAP_GEM = { x = 48, y = 50 } -- the gem's centre in a tabs/top cap's canvas, from its outer end and its top

-- The OUTER rail's middle line, in UI px ABOVE the window's top edge (the band
-- is grown outward by `outset`, its box measured from the piece's top): where
-- the title plate's gems ride (Kit:TitleOnRail) and the configurator's crest
-- is centred (Kit:OwnWindow)
function Kit:RailMiddle()
	local rule = self:WindowFrameRule()
	local prefix = rule and rule.prefix or "window/frame"
	local sc = self.scale * (rule and rule.scale or self.frameScale)
	local rail = PIECES[prefix .. "_t"]
	local top, bottom = 0, 0
	if rail and rail.box then
		top, bottom = rail.box[2], rail.box[4]
	end
	return ((rule and rule.outset or 0) - (top + bottom) / 2) * sc
end

-- How far a title goes up from a strip's centre to sit on its PAINTED box,
-- not its canvas (the box sits lower in the canvas: a title centred on the
-- canvas read as riding high -- user, 2026-09-21). The rail's title plate
-- and the configurator's short plate (Kit:OwnWindow) centre theirs by it.
function Kit:StripTextOffset(strip)
	local mid = strip and PIECES[StripName(strip.base, "mid", strip.state)]
	if not (mid and mid.box) then
		return 0
	end
	return (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (strip.scale or self.scale)
end

-- (0.20.1) How far a strip's PAINTED box reaches below its centre, in the strip's own units (StripTextOffset's
-- measure): a control under a title plate placed clear of its foot (the calendar's filter)
function Kit:StripFootDepth(strip)
	local mid = strip and PIECES[StripName(strip.base, "mid", strip.state)]
	if not (mid and mid.box) then
		return nil
	end
	return (mid.box[4] - mid.h / 2) * (strip.scale or self.scale)
end

function Kit:TitleOnRail(strip)
	local rule = self:WindowFrameRule()
	local sc = self.scale * (rule and rule.scale or self.frameScale)
	local middle = self:RailMiddle()
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
	local piece = PIECES[Kit.pieceNameOf[tex] or "window/portrait_ring"]
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

-- (0.19.0) The ring's rim -- its round body, not the gems that stand out of
-- it -- as a share of its texture's width, `tuck` piece px inside the rim's
-- edge (a glow lying under the ring starts under the rim: no gap between the
-- two -- HealerFrames' debuff glow; user, 2026-10-04)
function Kit:RingRim(tex, tuck)
	local piece = PIECES[(tex and Kit.pieceNameOf[tex]) or "window/portrait_ring"]
	local radius = ((piece and piece.radius) or 84) - (tuck or 0)
	return 2 * radius / ((piece and piece.w) or 197)
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

-- (0.20.1) A title plate on the rail fitted again a frame after a fit (Kit:NextFrame's: the rep is the key) while it
-- shows: once after each fit, and while its ring or its window could not be read (the onRail Refit)
function Kit.TitleRefitLater(rep)
	local strip = rep and rep.strip
	if strip and strip:IsVisible() then
		rep.fitLate = true
		rep:Refit()
		rep.fitLate = nil
	end
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

-- (0.20.1) an own window's close button by its frame (Kit:OwnWindow's close): the title plate on the rail takes it
-- inside, left of its right cap, as a game window's CloseButton. Also a game window's close that is another frame's
-- (the group finder's pages, PortraitFrameTemplateNoCloseButton, share their parent's LFGParentFrameCloseButton:
-- GroupFinderPanel). The game's anchors of a moved close: Kit.closeSavedOf, once per button
Kit.ownClose = setmetatable({}, { __mode = "k" })
Kit.closeSavedOf = Kept.closeSavedOf   -- [close button] = its game anchors while a title plate holds it

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

-- (0.20.1, the user's design, 2026-10-10: the double rail and the red plate on it back "without having to rescale the
-- icon and its border on top ... those header borders and the thick borders would be behind the icon and its border")
-- The plate runs behind the game's own portrait corner as it ran behind the kit's ring (TitleBehindRing): a stand-in
-- region of the plate's own, no art, on the ring's centre (Kit.cornerCut, from the corner's top left) and sized so the
-- ring hole lands inside its rim (FitRingHole's measure), takes the ring's place -- the plate starts at it, its left
-- cap left out, the hole cut -- and the plate lies just under the game's border frame (the corner's own level): the
-- game's frames are never raised, the title text stays over all. The outer rail is cut at the corner already
-- (CutGameCorner).
-- `keepLevel` (0.20.1, an own window standing in for a game window: the bag window): the plate keeps its level -- the
-- shell's corner art stands over its plate and close already; raised, the plate covered its own title and close
function Kit:TitleBehindGameCorner(title, corner, rail, keepLevel)
	local strip = title and title.strip
	if not (strip and strip.CreateTexture and corner) or title.behindRing then
		return
	end
	-- (rails drawn over the window's content -- railOver -- the plate one over them, its hole at the rim's outer edge)
	local over = rail and rail.rule and rail.rule.railOver
	local c, ring = self:CornerCutOf(corner), PIECES["window/portrait_ring"]
	local hole = over and c.outer or c.hole
	local w = (ring and ring.radius and ring.w) and hole * ring.w / (ring.radius - RING_HOLE_IN) or 2 * hole
	local stand = strip:CreateTexture(nil, "BACKGROUND")
	stand:SetSize(w, w)
	stand:SetPoint("CENTER", corner, "TOPLEFT", c.x, c.y)
	local nine = corner.GetParent and corner:GetParent()
	local ok, level = false, nil
	if nine and nine.GetFrameLevel then
		ok, level = pcall(nine.GetFrameLevel, nine)
	end
	if ok and not keepLevel and not Secret(level) and type(level) == "number" then
		if over then
			strip:SetFrameLevel(level + 8)
		elseif strip:GetFrameLevel() >= level then
			strip:SetFrameLevel(math.max(level - 1, 0))
		end
	end
	self:TitleBehindRing(title, { tex = stand }, nil)
end

-- How far the window's OUTER rail grows outward past the window's edge, in
-- UI px (the NineSlicePanelTemplate rule's `outset` at its scale): two
-- windows side by side need twice this between them, or their rails overlap.
function Kit:OuterRailOutset()
	local rule = self:WindowFrameRule()
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
--   Kit:SkinWindowShell(frame, replace, skin, { portrait = , noRing = , streaks = , outward = , below = , right = })
-- Returns the ring rep (skin.ring) when made.
-- `outward` (0.20.1, the user: the game's combined bag window -- "Bags by Kind" off -- its items, laid by the game
-- edge to edge, under the double rail): a window whose content runs to its edge wears a rail that lies over the
-- content (railOver) OUTSIDE its sides and bottom by the rail's own depth (Kit:OuterRailInset), the rail's inner edge
-- on the window's: it wraps the window, the game's layout and its secure buttons untouched. The game's portrait corner
-- goes out with the left rail (Kit:Nudge, while the rail is on) and the title plate's right end with the right one
-- (Kit.outwardOf[frame]); the top stays (the plate rides it). Set when the window is dressed: a window look chosen
-- later reaches it after a /reload, as every dressed window's.
Kit.outwardOf = setmetatable({}, { __mode = "k" })   -- [window] = { l, r, b }: how far its rail lies outward
Kit.outwardWrapOf = setmetatable({}, { __mode = "k" })   -- [window] = the rect its rail is laid on

-- The two halves of `outward`, shared by every shell (SkinWindowShell's, a window's own -- the guild bank's, 0.20.1:
-- its border drawn by hand, its money under the rail):
--   Kit:OutwardWrap(frame) -> rect   the rect the rail is laid on, grown outward by the rail's depth at the sides and
--                                    the bottom (made once; Kit.outwardOf[frame] its depths), or nil when the look's
--                                    rail does not lie over the content (the thin stone rail: nothing to wrap)
--   Kit:OutwardFollow(rep, frame, { left = , portrait = , container = , below = , right = })
--                                    while `rep` (the rail) is on: `left` regions out with the left rail (the portrait
--                                    corner), the `portrait` too unless it hangs on its `container`, `below` down with
--                                    the bottom one, `right` out with the right one (each the root of its anchor chain)
function Kit:OutwardWrap(frame)
	local wrap = Kit.outwardWrapOf[frame]
	if wrap then
		return wrap
	end
	local rule = self:WindowFrameRule()
	if not (rule and rule.railOver) then
		return nil
	end
	local ins = self:OuterRailInset()
	local ow = { l = ins[1], r = ins[2], b = ins[4] }
	wrap = CreateFrame("Frame", nil, frame)
	wrap:EnableMouse(false)
	wrap:SetPoint("TOPLEFT", frame, "TOPLEFT", -ow.l, 0)
	wrap:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", ow.r, -ow.b)
	Kit.outwardOf[frame], Kit.outwardWrapOf[frame] = ow, wrap
	return wrap
end

function Kit:OutwardFollow(rep, frame, o)
	local ow = Kit.outwardOf[frame]
	if not (rep and ow) then
		return
	end
	local left, below, right = o.left or {}, o.below or {}, o.right or {}
	local portrait, container = o.portrait, o.container
	local function Out(on)
		local dx = on and -ow.l or 0
		for _, region in ipairs(left) do
			if region then
				Kit:Nudge(region, "outward", dx, 0)
			end
		end
		if portrait and not (on and container and select(2, portrait:GetPoint(1)) == container) then
			Kit:Nudge(portrait, "outward", dx, 0)
		end
		for _, region in ipairs(below) do
			if region then
				Kit:Nudge(region, "outward", 0, on and -ow.b or 0)
			end
		end
		for _, region in ipairs(right) do
			if region then
				Kit:Nudge(region, "outward", on and ow.r or 0, 0)
			end
		end
	end
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Out(true)
	end
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		Out(false)
	end
	-- (a caller that switches its replacements on as it makes them: on already)
	local object = rawget(rep, "object")
	if object and object:IsShown() then
		Out(true)
	end
end

function Kit:SkinWindowShell(frame, replace, skin, opts)
	opts = opts or {}
	local rect = opts.rect or frame
	if opts.outward and frame.NineSlice then
		rect = self:OutwardWrap(frame) or rect
	end
	local railRep
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
		railRep = replace(frame.NineSlice, { as = "NineSlicePanelTemplate", parent = frame, rect = rect, skip = (not opts.noRing) and "tl" or nil, body = body })
	end
	if frame.TopTileStreaks then
		replace(frame.TopTileStreaks, { as = "_UI-Frame-TopTileStreaks", parent = frame })
	end
	if frame.Bg and opts.bg then
		-- ONE picture for the whole window, inside the outer rail (the game's
		-- rock starts below the title area; a second picture for that strip
		-- met the first with a seam — user, 2026-09-21), as the Legacy pages
		-- (`outward`: the rail's inner edge on the window's at the sides and bottom -- the page reaches them)
		replace(frame.Bg, { as = opts.bg, parent = frame, rect = frame, inset = self:PageInset(frame) })
	end
	local portrait = opts.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
	local corner = frame.NineSlice and frame.NineSlice.TopLeftCorner
	if portrait and corner and not opts.noRing then
		skin.ring = replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = frame.PortraitContainer or frame, center = portrait })
	end
	-- (`outward`) the game's portrait corner -- its art and the portrait's container -- on the outward rail's corner;
	-- the portrait too where the game hangs it on the window itself (the bags: ContainerFrame_OnLoad's
	-- SetPortraitTextureSizeAndOffset -- the user, 2026-10-10: the ring out, the bag icon left behind)
	-- `below` (0.20.1, with `outward`): regions the game hangs under the window's bottom edge (the merchant's tabs) go
	-- down with the bottom rail, the root of each anchor chain listed; `right` likewise: regions it hangs past the
	-- window's right edge (the guild window's side tabs, its member card) go out with the right rail
	if Kit.outwardOf[frame] and railRep and corner then
		local container = frame.PortraitContainer
		self:OutwardFollow(railRep, frame, { left = { corner, container or false }, portrait = portrait, container = container,
			below = opts.below, right = opts.right })
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
	if not Kit.portraitSavedOf[portrait] then
		local points = {}
		for i = 1, portrait:GetNumPoints() do
			points[i] = { portrait:GetPoint(i) }
		end
		local cx, cy = portrait:GetCenter()
		local px, py = portrait:GetParent():GetLeft(), portrait:GetParent():GetTop()
		if not (cx and px) then
			return             -- not laid out yet (the window hidden): try again on the next refresh
		end
		Kit.portraitSavedOf[portrait] = { points = points, w = portrait:GetWidth(), h = portrait:GetHeight(),
			cx = cx - px, cy = cy - py }
	end
	local saved = Kit.portraitSavedOf[portrait]
	local size = self:MedallionSize(ring.tex)
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
		local piece = PIECES[Kit.pieceNameOf[ring.tex] or "window/portrait_ring"]
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
		self:RefitRegion(portrait)   -- (a portrait moved in the kit editor stays moved)
	end
end

function Kit:UnfitPortrait(portrait)
	local saved = portrait and Kit.portraitSavedOf[portrait]
	if saved then
		portrait:ClearAllPoints()
		for _, pt in ipairs(saved.points) do
			portrait:SetPoint(unpack(pt))
		end
		portrait:SetSize(saved.w, saved.h)
		Kit.portraitSavedOf[portrait] = nil
		self:RefitRegion(portrait)
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
	-- (on the screen: a tab scaled apart from its window, the bag window's, 0.22.0, reads in its own units)
	local ok, tx, wx = pcall(function()
		return tab:GetCenter() * tab:GetEffectiveScale(), window:GetCenter() * window:GetEffectiveScale()
	end)
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

Kit.auraLooks = { { value = "black", label = "Plain black edge" } }
for _, v in ipairs(Kit.buttonLooks.borders) do
	Kit.auraLooks[#Kit.auraLooks + 1] = v
end
-- The windows' frame and title (0.20.1; the user, 2026-10-10: "use thinner borders (yes the thick outer one aswell)"
-- and the header at the game's own size; our own art in the style of the RPG packs they showed, examples 3 and 4 to
-- test): variants of the NineSlicePanelTemplate and TitleBar rules, written into Kit.Replacements before a window is
-- dressed (Kit:SyncWindowLook: at the first window rule asked, once the settings are read, and on a choice). A
-- window already dressed keeps its look until a /reload.
--   classic  the double rail grown outward with gem corners; the red plate riding it (0.19.x)
--   stone    the thin stone rail on the window's edge (window/stone_*, Tools/make_window_stone.py)
--   ribbon   the red ribbon on the game's title bar (window/ribbon_*), the title on it
--   band     a plain band with the stone line under it (window/band_*), the title on it
-- `atBorder`: the rail drawn at the game's border's level, just under it (NineSlicePanelTemplate: 500, its corner ring
-- on it), over the window's panes -- the thin rail lies on the window's edge, where a pane's own border reaches (the
-- user, 2026-10-10: the rail missing beside and under the paperdoll); the double rail lies outside the window and
-- draws the window's stone, so it stays under. `railUnder`: the rail's top edge under the title bar, across the
-- window, as the game's top edge is as tall as its title bar (Kit:TitleRail).
Kit.windowFrames = {
	-- (0.20.1, the user's design: the game's portrait corner on the frame's corner, unscaled -- the double rail hugs
	-- the window, 3 piece px outside it, the plate riding through the window's title band; on the window's edge, so at
	-- the border's level as the thin rail; 0.19.x grew it 42 outward round a kit ring scaled to fit)
	-- `railOver` (the user, in game: the panes' corners and the character window's divider -- the game's, at 505 -- drew
	-- over the hugging rail): the rails and gems over the window's content, under its title bar (510), the game's ring
	-- under them shown whole through their cut at its outer edge (CutRailAtRing), the plate over them
	classic = { prefix = "window/frame", scale = 1.0, corners = "gem", outset = 3, atBorder = true, railOver = true },
	stone = { prefix = "window/stone", scale = 0.5, outset = 3, atBorder = true },
}
Kit.windowTitles = {
	classic = { base = "tabs/top", state = "open", heightScale = 1.5, onRail = true },
	ribbon = { base = "window/ribbon", heightScale = 1.0, centreTitle = true, railUnder = true },
	band = { base = "window/band", heightScale = 1.0, centreTitle = true },
}
Kit.windowFrameLooks = {
	{ value = "stone", label = "Thin stone rail" },
	{ value = "classic", label = "Double rail with gem corners" },
}
Kit.windowTitleLooks = {
	{ value = "ribbon", label = "Red ribbon" },
	{ value = "band", label = "Plain band with a rail line" },
	{ value = "classic", label = "Red plate on the rail (with the double rail)" },
}

-- the rule fields a look sets, written over the rule in place (every reader keeps the same table); `synced` once
-- the settings were read. (One table, no top-level locals: the file is at Lua 5.1's 200.)
Kit.windowLookState = { synced = false,
	frameFields = { "prefix", "scale", "corners", "outset", "atBorder", "railOver" },
	titleFields = { "base", "state", "heightScale", "onRail", "centreTitle", "railUnder" } }

function Kit:SyncWindowLook()
	local st = self.windowLookState
	local frame = self.windowFrames[self:BorderValue("window") or "stone"] or self.windowFrames.stone
	local title = self.windowTitles[self:BorderValue("windowtitle") or "ribbon"] or self.windowTitles.ribbon
	local fr, tr = self.Replacements["NineSlicePanelTemplate"], self.Replacements["TitleBar"]
	for _, f in ipairs(st.frameFields) do
		fr[f] = frame[f]
	end
	for _, f in ipairs(st.titleFields) do
		tr[f] = title[f]
	end
end

-- (once the settings can be read: before that a read is the defaults, and the first window dressed after it would
-- wear them)
function Kit:SyncWindowLookOnce()
	local st = self.windowLookState
	if st.synced then
		return
	end
	local um = MelloUI:GetModule("UIModifications")
	if um and um.db then
		st.synced = true
		self:SyncWindowLook()
	end
end

function Kit:WindowFrameRule()
	self:SyncWindowLookOnce()
	return self.Replacements["NineSlicePanelTemplate"]
end

-- The game's portrait corner kept on a dressed window (0.20.1; the user, 2026-10-10: "hide the stubs"): its ring and
-- the portrait stay the game's, at the game's size and place, and the stubs of the game's metal rails beside the ring
-- are cut away, the kit's rail running into the ring. A mask made on the corner's own frame (a mask works only on its
-- frame's textures; no key is written on the game's), laid over the corner's whole square: Masks/portrait_corner
-- (Tools/make_portrait_corner_mask.py, measured on the corner's art) keeps the ring with its gold rim and soft halo
-- whole and cuts each stub at the rim (a round cut either left slivers of the stubs or clipped the rim: in game,
-- 2026-10-10); on with the rep, off with it. (A stand-in window's own copy of the corner: KitWindow.)
-- The kit's rail is cut there too (the user, 2026-10-10: its corner peeked out past the ring's top left; the game's
-- window has none, the ring is its corner): the ring's corner cut (Masks/ring_corner: the quarter above and left of
-- the ring's centre and a hole under its rim) on the rail's own textures, centred on the game's ring -- x, y from the
-- corner's top left (its art: the centre at 76, 76 of 190 px for 95 units), `hole` inside the rim's outer edge (30)
-- -- as the rep's `outerCut`, which the shade puts on the rail's partners (KitShade's Cut).
-- (`outer`, 0.20.1: the rim's outer edge, the cut for rails drawn OVER the ring -- railOver -- so none of it covers
-- the rim)
-- The bags' corner is the small ring (ui-frame-portraitmetal-cornertopleftsmall, their HeldBagLayout; the user,
-- 2026-10-10: cut as the big one, the header and the left rail cut off): its centre at 53.5, 66.5 of its 190 px, its
-- rim ending at 40 -- Kit.cornerCutSmall, its own mask; Kit:CornerCutOf(corner) tells them by the corner's atlas.
Kit.cornerCut = { mask = EDGE_ROOT .. "portrait_corner", x = 38, y = -38, hole = 27, outer = 30 }
Kit.cornerCutSmall = { mask = EDGE_ROOT .. "portrait_corner_small", x = 26.75, y = -33.25, hole = 18, outer = 20 }

function Kit:CornerCutOf(corner)
	local ok, atlas = false, nil
	if corner and corner.GetAtlas then
		ok, atlas = pcall(corner.GetAtlas, corner)
	end
	if ok and type(atlas) == "string" and not Secret(atlas) and atlas:lower():find("cornertopleftsmall", 1, true) then
		return self.cornerCutSmall
	end
	return self.cornerCut
end

function Kit:CornerCutMask(owner, corner)
	local mask = owner:CreateMaskTexture()
	mask:SetTexture(self:CornerCutOf(corner).mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(corner)
	return mask
end

-- (made once, at the rail's first enable: a window's rail art is laid as it is replaced)
function Kit:CutRailAtRing(rep, corner)
	local skin = rawget(rep, "skin")
	if not (skin and skin.CreateMaskTexture) then
		rep.outerCut = false
		return
	end
	local list = {}
	for _, t in ipairs(skin.all or {}) do
		list[#list + 1] = t
	end
	for _, t in ipairs(skin.art or {}) do
		list[#list + 1] = t
	end
	local c = self:CornerCutOf(corner)
	local size = 2 * ((rep.rule and rep.rule.railOver) and c.outer or c.hole) / RING_HOLE_FILL
	local function Place(cut)
		cut:SetPoint("CENTER", corner, "TOPLEFT", c.x, c.y)
		cut:SetSize(size, size)
		return cut
	end
	-- (the skin's: its stone and the shade's partners on it, KitShade; the rails' frame's: the rails)
	rep.outerCut = Place(RingCut(skin, list))
	local rails = rawget(skin, "railHost")
	if rails then
		rep.railCut = Place(RingCut(rails, list))
	end
end

-- (0.20.1; the user, 2026-10-10: the border missing under the title) The game's top edge is as tall as its title bar
-- (the corner's art: its lower edge 26 units down; the title bar 1..21): with a title that sits inside the window's
-- top (the ribbon: Replacements.TitleBar.railUnder), the rail's own top edge runs under the title bar, across the
-- window from the left rail (under the game's ring, cut with the rail) to the right one. A texture of the rail's skin,
-- shown and hidden with it, placed by the title bar's own anchors (PortraitFrameTemplate: 58 and -24 from the sides).
function Kit:TitleRail(rep, region)
	local skin = rawget(rep, "skin")
	local window = region.GetParent and region:GetParent()
	local tc = window and rawget(window, "TitleContainer")
	if not (self.Replacements["TitleBar"].railUnder and skin and tc and tc.GetNumPoints and rep.rule.prefix) then
		return
	end
	local left, right = 58, -24
	for i = 1, tc:GetNumPoints() do
		local ok, point, _, _, x = pcall(tc.GetPoint, tc, i)
		if ok and not Secret(x) and type(x) == "number" then
			if point == "TOPLEFT" then
				left = x
			elseif point == "TOPRIGHT" then
				right = x
			end
		end
	end
	local T = skin.thickness or 0
	local o = (rep.rule.outset or 0) * (skin.kitScale or 0)
	local line = Tiled(rawget(skin, "railHost") or skin, rep.rule.prefix .. "_t", "BORDER", 0, skin.kitScale)
	line:SetPoint("TOPLEFT", tc, "BOTTOMLEFT", -left - o, 0)
	line:SetPoint("TOPRIGHT", tc, "BOTTOMRIGHT", -right + o - T, 0)
	line:SetHeight(T)
	skin.titleRail = line
	table.insert(skin.tiled, line)
	table.insert(skin.art, line)
	table.insert(skin.all, line)
	self:Retile(line)
end

function Kit:CutGameCorner(rep, corner)
	local owner = corner.GetParent and corner:GetParent()
	if not (owner and owner.CreateMaskTexture and corner.AddMaskTexture) then
		return
	end
	local mask = self:CornerCutMask(owner, corner)
	local on = false
	local onEnable, onDisable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if onEnable then
			onEnable(...)
		end
		if not on then
			on = pcall(corner.AddMaskTexture, corner, mask)
		end
		if rawget(rep, "outerCut") == nil then
			Kit:CutRailAtRing(rep, corner)
		end
	end
	rep.onDisable = function(...)
		if onDisable then
			onDisable(...)
		end
		if on then
			on = false
			pcall(corner.RemoveMaskTexture, corner, mask)
		end
	end
	rep.cornerCut = mask
end

-- The painted engine's border kinds, round the core's (Kit.borderKinds: round, colours), in their old order
do
	local before = {
		{ kind = "window", key = "windowBorder", default = "stone", name = "Window Border", values = Kit.windowFrameLooks,
		  desc = "The frame round every window: a thin stone rail on the window's edge, or the double rail with gem corners. Windows already opened change after a /reload." },
		{ kind = "windowtitle", key = "windowTitle", default = "ribbon", name = "Window Title", values = Kit.windowTitleLooks,
		  desc = "The title bar of every window, at the game's own size: a red ribbon, or a plain band with a rail line under it. The red plate riding the rail goes with the double rail. Windows already opened change after a /reload." },
		{ kind = "button", key = "buttonBorder", default = "thin", name = "Button Border", values = Kit.buttonLooks.borders, preview = "rim",
		  desc = "The rim on every square button: the action bars, the micro menu, the bag bar, your bags, the equipment slots and the spell book's spells." },
		{ kind = "sidetab", key = "sideTabBorder", default = "slot", name = "Side Tab Border", values = Kit.sideTabLooks, preview = "rim",
		  desc = "The rim on every window's side tabs and the spell book's category tabs, all at the character window's size." },
		{ kind = "bar", key = "barBorder", default = "frame", name = "Progress Bar Border", values = Kit.buttonLooks.barBorders, preview = "bar",
		  desc = "The frame round every progress bar: reputation and skills, the professions' ranks, legacy, guild, experience, the tracker's, the tooltip's and the damage meter's. The unit frames, the nameplates, the cast bar, the swing timers and the Personal Display have a border of their own." },
		{ kind = "nameplate", key = "nameplateBorder", default = "frame", name = "Nameplate Border", values = Kit.buttonLooks.barBorders, preview = "bar",
		  desc = "The frame round the nameplates' health bars." },
	}
	for _, k in ipairs(before) do
		Kit:AddBorderKind(k, nil, "round")
	end
	Kit:AddBorderKind(
		{ kind = "aura", key = "auraBorder", default = "thin", name = "Aura Border", values = Kit.auraLooks, preview = "rim",
		  desc = "The rim round your buffs and debuffs, the target's and the nameplates' (Buffs & Debuffs): a plain black edge or one of the thin rims the buttons wear. The debuff colour stays round the icon. Only MelloUI's own aura rows wear it (Buffs & Debuffs, off by default): the game's own buff and debuff icons keep their edge, which Dark Mode's Buffs & Debuffs darkens." }, "round")
end

local buttonRims = setmetatable({}, { __mode = "k" })   -- [button] = true: a skinned button whose rim is a thin look
local borderBars = { bar = setmetatable({}, { __mode = "k" }), nameplate = setmetatable({}, { __mode = "k" }),
	-- (0.19.8: the unit frames' bars and the cast bar, a border of their own each)
	unitframe = setmetatable({}, { __mode = "k" }), castbar = setmetatable({}, { __mode = "k" }) }

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

-- The painted engine's kinds' choice to every element of them (Kit:ApplyBorder's, beside the core's round rims and
-- Kit Colours)
function Kit.__.ApplyBorderKind(self, kind, value)
	if kind == "button" then
		for button in pairs(buttonRims) do
			self:SetButtonBorder(button, value)
		end
	elseif kind == "sidetab" then
		self:SetSideTabBorder()
	elseif kind == "raid" then
		self:ApplyRaidBorders()   -- (the border library's: Modules/KitBorders.lua)
	elseif kind == "personal" then
		self:ApplyPersonalBorder()   -- (the border library's: Modules/KitBorders.lua)
	elseif kind == "portrait" then
		self:ApplyPortraitRings()   -- (the border library's rings: Modules/KitBorders.lua)
	elseif kind == "cooldown" then
		self:ApplyCooldownBorders()   -- (the Cooldown Manager's icons: Modules/KitBorders.lua)
	elseif kind == "orb" then
		-- (the frames not dressed yet take it now; the dressed ones after a /reload)
		if MelloUI.Announce then
			MelloUI:Announce("Level orb changed: type /reload to see it on frames already shown.", "info")
		end
	elseif kind == "window" or kind == "windowtitle" then
		-- (the windows not dressed yet take it now; the dressed ones after a /reload)
		self:SyncWindowLook()
		if MelloUI.Announce then
			MelloUI:Announce("Window look changed: type /reload to see it on windows already opened.", "info")
		end
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
end


-- A large side tab (SidePanelTabButtonMixin: Background common-sidetab, Icon,
-- SelectedTexture / TabGlow / HighlightTexture): the gold rim with the icon
-- fitted in, the glow while `checked()` (default: the game's SelectedTexture shown).
function Kit:SkinSideTab(tab, replace, checked)
	if not (tab and tab.Background) or Kit.repOf[tab] ~= nil then
		return tab and Kit.repOf[tab] or nil
	end
	Kit.repOf[tab] = replace(tab.Background, { as = "common-sidetab", button = tab, parent = tab, icon = tab.Icon,
		checked = checked or function() return tab.SelectedTexture and tab.SelectedTexture:IsShown() end,
		alsoFade = { tab.SelectedTexture, tab.TabGlow, tab.HighlightTexture } }) or false
	return Kit.repOf[tab] or nil
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
		if region ~= button.Icon and region:GetObjectType() == "Texture" and not Kit.pieceOf[region] then
			extra[#extra + 1] = region
		end
	end
	self:StateIconReps(button, button.Icon, button, replace, extra)
end

-- A search box (SearchBoxTemplate): the edit plate with its glass cap in
-- place of the game's icon; the text and instructions start past the cap.
-- `beside` (0.20.1): the region a filter button's plate is drawn on, right of
-- the box: the field takes that plate's height (the caller centres the box on
-- it: Kit:AlignBeside), so the two stand on one line
-- (0.20.1) A SearchBoxNineSliceTemplate box (the social window's, the user's screenshot): one Background
-- (common-searchbar-a) in place of the Left / Middle / Right pieces -- the same field on it.
function Kit:SkinSearchBox(search, replace, beside)
	local art = search and (search.Middle or (not search.Left and search.Background))
	if not art or Kit.repOf[search] ~= nil then
		return search and Kit.repOf[search] or nil
	end
	-- (0.19.1: the field flat, the Configurator's search box -- the game's
	-- glass stays inside it and the text where the game has it; the S1 strip
	-- had its own glass cap, the game's faded and the text moved past the cap)
	local rule = self:RuleFor("common-search-border-middle")
	local flat = rule and rule.kind == "flat"
	-- (left: the field reaches over the art's 5 px left of the box, the glass
	-- inside it -- the search box's own span, as W.FlatSearch's)
	local fit
	if beside then
		local okW, w = pcall(beside.GetWidth, beside)
		local okH, h = pcall(beside.GetHeight, beside)
		if okW and okH and not Secret(w) and not Secret(h) and (w or 0) > 0 and (h or 0) > 0 then
			fit = math.min(w, h)
		end
	end
	local rep = replace(art, { as = "common-search-border-middle", rect = search, edit = search,
		left = flat and 5 or nil, fitHeight = fit,
		alsoFade = flat and { search.Left, search.Right } or { search.Left, search.Right, search.searchIcon } })
	Kit.repOf[search] = rep or false
	if not rep or flat then
		return rep or nil
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
	if not button or Kit.repOf[button] ~= nil then
		return button and Kit.repOf[button] or nil
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
		Kit.repOf[button] = false
		return nil
	end
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= anchor and region ~= button.Left and region ~= button.Right
			and not Kit.pieceOf[region] and region:GetDrawLayer() == "HIGHLIGHT" then
			extra[#extra + 1] = region
		end
	end
	Kit.repOf[button] = replace(anchor, { as = key, rect = button, button = button, alsoFade = extra, dropCap = opts.dropCap, capless = opts.capless }) or false
	return Kit.repOf[button] or nil
end

-- A check button (CheckButton with the minimal or the classic check box
-- art): the kit's check box off / on / hover on its normal texture's rect.
function Kit:SkinCheckButton(cb, replace, key)
	if not (cb and cb.GetNormalTexture and cb:GetNormalTexture()) or Kit.repOf[cb] ~= nil then
		return cb and Kit.repOf[cb] or nil
	end
	local normal = cb:GetNormalTexture()
	-- the states the button has, gap-free: a radio has no pushed texture, and
	-- a nil in the list ended the fade at it (the checked / highlight /
	-- disabled art stayed the game's)
	local fade = {}
	for _, getter in ipairs({ "GetPushedTexture", "GetCheckedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local t = cb[getter] and cb[getter](cb)
		if t then
			fade[#fade + 1] = t
		end
	end
	Kit.repOf[cb] = replace(normal, { as = key or "checkbox-minimal", button = cb, rect = normal, alsoFade = fade }) or false
	return Kit.repOf[cb] or nil
end

-- P1 on a StatusBar whose bracket art is one of its own textures (`frame`,
-- e.g. LegacyProgressBarTemplate's ProgressBarFrame) and whose background
-- (`bg`) is a texture of the parent the bar is anchored to: the bracket and
-- trough become regions of the bar's frame on the background's rect, the
-- background and the game's bracket are faded, and the StatusBar itself is
-- moved into the opening (its fill spans the bracket's whole height, behind
-- the rails), put back on disable. `key` is the mapping (the bracket's atlas).
function Kit:SkinStatusBar(bar, frame, bg, replace, key)
	if not (bar and frame and bg) or Kit.repOf[bar] ~= nil then
		return bar and Kit.repOf[bar] or nil
	end
	local rep = replace(frame, { as = key or self:ArtKey(frame), rect = bg, parent = bar, alsoFade = { bg } })
	Kit.repOf[bar] = rep or false
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

-- Every skinned panel tab (Kit:SkinPanelTab), for the shared handlers below
-- (user, 2026-09-24: one handler for all of them, the tab's own state kept
-- here): its two cards, and which tab a hooked region belongs to
local panelTabs = setmetatable({}, { __mode = "k" })     -- [tab] = { plain = rep, open = rep, rep = the one Steady reads, text = }
local panelTabOf = setmetatable({}, { __mode = "k" })    -- [tab.Left / tab.LeftActive / tab.Text] = tab

-- the cards shown with the game's art (the game hides the plain set and
-- shows the active one on select)
local function PanelTab_Follow(tab, st)
	if st.plain then st.plain:SetShown(tab.Left:IsShown()) end
	if st.open then st.open:SetShown(tab.LeftActive:IsShown()) end
end
local PanelTab_OnArt = Shared("Show / Hide on a panel tab's art", function(region)
	local tab = panelTabOf[region]
	PanelTab_Follow(tab, panelTabs[tab])
end)

-- the text held where the plate wants it (below)
local function PanelTab_Steady(tab, st)
	local rep, open, text = st.rep, st.open, st.text
	if Kit.steadyingOf[tab] or not (rep.object:IsShown() or (open and open.object:IsShown())) then
		return
	end
	Kit.steadyingOf[tab] = true
	local dy = 0
	if rep.strip then
		local mid = PIECES[StripName(rep.strip.base, "mid", rep.strip.state)]
		if mid and mid.box then
			dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (rep.strip.scale or Kit.scale)
		end
	end
	local okP, _, _, _, x = pcall(text.GetPoint, text, 1)
	text:SetPoint("CENTER", tab, "CENTER", (okP and x) or 0, dy)
	Kit.steadyingOf[tab] = nil
end
local PanelTab_OnTextPoint = Shared("SetPoint on a panel tab's text", function(text)
	local tab = panelTabOf[text]
	PanelTab_Steady(tab, panelTabs[tab])
end)

-- A PanelTabButtonTemplate / TabSystem tab (Left / Middle / Right plain,
-- LeftActive / MiddleActive / RightActive open; the game shows one set):
-- T1, one plate per set on the tab's rect, following the game's Show / Hide.
-- The open card of a tab not selected now is laid when the tab is first
-- selected (user, 2026-09-24: two cards per tab were the largest part of a
-- tabbed window's first frame, ~200 engine calls a tab, and a tab shows only
-- one): made now, in its place, its textures waiting (Kit:Replace's
-- `layWith`). Only for a panel that follows its cards (skin.followers),
-- syncing them with the game's art whenever it switches the kit on; a card
-- left on screen without its art is laid in its first frame there
-- (Waiting_OnUpdate).
function Kit:SkinPanelTab(tab, replace, skin)
	if not (tab and tab.Left and tab.LeftActive) or Kit.repOf[tab] ~= nil then
		return
	end
	Kit.repOf[tab] = false
	local follows = skin and skin.followers
	local plain = replace(tab.Left, { as = "uiframe-tab-left", rect = tab, button = tab, alsoFade = { tab.Middle, tab.Right, tab.LeftHighlight, tab.MiddleHighlight, tab.RightHighlight } })
	local open = replace(tab.LeftActive, { as = "uiframe-activetab-left", rect = tab, alsoFade = { tab.MiddleActive, tab.RightActive },
		layWith = (follows and not tab.LeftActive:IsShown()) and tab.LeftActive or nil })
	Kit.repOf[tab] = plain or open or false
	if follows then
		if plain then
			follows[#follows + 1] = { rep = plain, region = tab.Left }
		end
		if open then
			follows[#follows + 1] = { rep = open, region = tab.LeftActive }
		end
	end
	local st = { plain = plain, open = open }
	panelTabs[tab] = st
	panelTabOf[tab.Left], panelTabOf[tab.LeftActive] = tab, tab
	-- the game hides the plain set and shows the active one on select
	hooksecurefunc(tab.Left, "Show", PanelTab_OnArt)
	hooksecurefunc(tab.Left, "Hide", PanelTab_OnArt)
	hooksecurefunc(tab.LeftActive, "Show", PanelTab_OnArt)
	hooksecurefunc(tab.LeftActive, "Hide", PanelTab_OnArt)
	PanelTab_Follow(tab, st)
	-- the game bobs the tab's text on select / deselect (a few px up and
	-- down, to sit on its own tab art); on the kit's plate it stays put,
	-- centred on the plate's painted box (user, 2026-09-21). Re-applied
	-- after each of the game's SetPoint calls on the text, only while a
	-- plate is on.
	local text = tab.Text
	local rep = plain or open
	if text and rep then
		st.rep, st.text = rep, text
		panelTabOf[text] = tab
		hooksecurefunc(text, "SetPoint", PanelTab_OnTextPoint)
		PanelTab_Steady(tab, st)
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
	if not inset or Kit.repOf[inset] ~= nil then
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
	Kit.repOf[inset] = replace(inset, { as = "common-insideframe", parent = parent, rect = inset, level = level, body = withBody and true or false, noFade = true, alsoFade = extra }) or false
end

-- The controls every window has, found by what they ARE under `root` (a
-- window, a page): search boxes, red buttons, check boxes, dropdowns, panel
-- tabs, insets, scroll bars — each to its fixed look. `skip` frames are not
-- walked into (a map canvas). The game's own icons and pictures are left.
-- `shownOnly`: every child of a frame walked is looked at, but only the
-- shown ones are walked into, a hidden page left for when it first shows
-- (the walk some panels make themselves over a one-level sweep, in one call
-- and one GetChildren a frame; user, 2026-09-24).
function Kit:SweepControls(root, replace, skin, skip, depth, shownOnly)
	depth = depth or 0
	if not root or depth > 8 or root == skip or root == skin then
		return
	end
	local list, n = WalkChildren(root, depth)
	for i = 1, n do
		local child = list[i]
		local kind = child:GetObjectType()
		if child.Track and child.Track.Thumb and child.Back and child.Forward then
			self:SkinScrollBar(child, replace)
		elseif kind == "EditBox" and (child.Middle or (child.Background and not child.Left)) and child.searchIcon then
			self:SkinSearchBox(child, replace)
		elseif child.Left and child.LeftActive and child.Middle then
			self:SkinPanelTab(child, replace, skin)
		elseif kind == "Button" and (child.Center or (child.Left and child.Middle and child.Right)) and child:GetFontString() and child:GetFontString():GetText()
			and not child.Icon and not child.Background and not child.CollapsedIcon and not (root.LayoutColumns) then
			-- (a column display's header buttons have the same Left / Middle /
			-- Right shape but are the window's to map: GC1, not B1)
			self:SkinRedButton(child, replace)
		elseif kind == "CheckButton" and child.GetCheckedTexture and child:GetCheckedTexture() and child:GetCheckedTexture():GetTexture()
			and not child.Icon and not child.Ring and (child:GetWidth() <= 40 or child:GetWidth() == 0) and Kit.repOf[child] == nil then
			local normal = child.GetNormalTexture and child:GetNormalTexture()
			local key = normal and self:ArtKey(normal)
			self:SkinCheckButton(child, replace, (key and self:RuleFor(key)) and key or "UI-CheckBox-Up")
		elseif child.Background and child.Arrow and child.Text and Kit.repOf[child] == nil then
			Kit.repOf[child] = replace(child.Background, { as = "common-dropdown-textholder", rect = child, button = child, alsoFade = { child.Arrow } }) or false
		elseif child.Background and child.Text and self:ArtKey(child.Background) == "common-dropdown-b-button" and Kit.repOf[child] == nil then
			Kit.repOf[child] = replace(child.Background, { as = "common-dropdown-b-button", rect = child, button = child, parent = child }) or false
		elseif child.NineSlice and child.Bg and (child.layoutType == "InsetFrameTemplate" or child.NineSlice.layoutType == "InsetFrameTemplate"
			or (child.NineSlice.TopLeftCorner and tostring(self:ArtKey(child.NineSlice.TopLeftCorner)):find("^UI%-Frame%-Inner"))) then
			self:SkinInset(child, replace, root)
		end
		if not (child.Track and child.Track.Thumb) and not (shownOnly and not child:IsShown()) then
			self:SweepControls(child, replace, skin, skip, depth + 1, shownOnly)
		end
	end
	WalkDone(list)
end

-- A list's rows as they are acquired by a WowScrollBoxList (and the ones it
-- already holds): `rowSkin(frame)` once per row, guarded by the panel.
-- `initialized`: call `rowSkin` after the row's own Init instead (a pool
-- whose frames serve as header AND row: the look is known only then).
function Kit:HookScrollBoxRows(scrollBox, rowSkin, isActive, initialized)
	if not (scrollBox and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) or Kit.kitHookedOf[scrollBox] then
		return
	end
	Kit.kitHookedOf[scrollBox] = true
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
					ok and string.format("%.2f", u1) or "?", ok and string.format("%.2f", u2) or "?", ok and string.format("%.2f", v2) or "?", tostring(Kit.pieceNameOf[rep.tex]))
			end
			if rep.strip then
				-- a strip's fit: its scale, the caps' widths as laid out and
				-- the cap decisions (a plate that lost its caps shows why)
				local st = rep.strip
				more = string.format("%s scale=%.3f wl=%.1f wr=%.1f%s%s%s%s%s%s%s", more, st.scale or 0, st.wl or 0, st.wr or 0,
					st.capless and " CAPLESS" or "", st.dropCap and (" drop=" .. tostring(st.dropCap)) or "",
					st.endL and " endL" or "", st.endR and " endR" or "", st.noL and " noL" or "",
					-- (a title plate's fit that could not read its ring or its window, or failed, and how often:
					-- Kit.TitleRefitLater; the last failure's message)
					rawget(rep, "fitMiss") and (" miss=" .. rep.fitMiss .. "x" .. tostring(rawget(rep, "fitTries"))) or "",
					rawget(rep, "fitError") and (" err=" .. tostring(rep.fitError):sub(1, 120)) or "")
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
			if region:GetObjectType() == "Texture" and not Kit.pieceOf[region] and okV and not Secret(visible) and visible then
				local ok, alpha = pcall(region.GetAlpha, region)
				if ok and alpha and not Secret(alpha) and alpha > 0 then
					n = n + 1
					local okL, layer, sub = pcall(region.GetDrawLayer, region)
					if not okL or Secret(layer) or Secret(sub) then
						layer, sub = "?", "?"
					end
					Rect(string.format("%d %s/%s", n, Name(frame), region:GetName() or Kit.pieceNameOf[region] or region:GetDebugName()), region,
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
	Perf.SetScript(f, "OnDragStart", f.StartMoving)
	Perf.SetScript(f, "OnDragStop", f.StopMovingOrSizing)
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
	Perf.SetScript(close, "OnClick", function() f:Hide() end)

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
	-- a read, or `d` when it is nil or secret (a piece on a frame whose
	-- place or look the game hides reads secret, in a fight or on
	-- nameplates: the secret test before anything else, 2026-09-25)
	local function N(v, d)
		if (Secret and Secret(v)) or v == nil then
			return d
		end
		return v
	end
	local rows = {}
	for tex in pairs(SHADED) do
		local ok, visible = pcall(tex.IsVisible, tex)
		if ok and N(visible, false) then
			local okR, l, b, w, h = pcall(tex.GetRect, tex)
			local okS, es = pcall(tex.GetEffectiveScale, tex)
			l, b, w, h, es = N(l), N(b), N(w), N(h), N(es)
			if okR and l and b and w and h and okS and es and es > 0 then
				local x, y = cx / es, cy / es
				if x >= l and x <= l + w and y >= b and y <= b + h then
					local parent = tex:GetParent()
					-- GetTexCoord: UL x y, LL x y, UR x y, LR x y
					local okT, u1, v1, _, _, _, _, u2, v2 = pcall(tex.GetTexCoord, tex)
					u1, v1, u2, v2 = N(u1), N(v1), N(u2), N(v2)
					local okV, r, g, bl = pcall(tex.GetVertexColor, tex)
					r, g, bl = N(r, 1), N(g, 1), N(bl, 1)
					local okL, layer, sub = pcall(tex.GetDrawLayer, tex)
					layer, sub = N(layer), N(sub, 0)
					local _, file = pcall(tex.GetTexture, tex)
					file = N(file, "?")
					local strata = N(parent and parent.GetFrameStrata and parent:GetFrameStrata(), "?")
					local level = N(parent and parent.GetFrameLevel and parent:GetFrameLevel(), 0)
					local order = ({ BACKGROUND = 0, LOW = 1, MEDIUM = 2, HIGH = 3, DIALOG = 4, FULLSCREEN = 5, FULLSCREEN_DIALOG = 6, TOOLTIP = 7 })[strata] or 0
					local layerOrder = ({ BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 })[okL and layer or ""] or 0
					local kp = type(Kit.pieceOf[tex]) == "table" and Kit.pieceOf[tex] or nil   -- (true: a flat colour of ours)
					local pieceW, pieceH = kp and kp.w or 0, kp and kp.h or 0
					local rimInfo = ""
					if tex.button then
						local bt = tex.button
						local okCk, ck = pcall(function() return bt.GetChecked and bt:GetChecked() end)
						local okSt, st = pcall(function() return bt.GetButtonState and bt:GetButtonState() end)
						rimInfo = string.format("  RIM state=%s hover=%s pressed=%s lastChecked=%s isChecked=%s | button checked=%s state=%s enabled=%s",
							tostring(tex.state), tostring(tex.hover), tostring(tex.pressed), tostring(tex.lastChecked),
							tex.isChecked and tostring(N(select(2, pcall(tex.isChecked)), "secret/nil")) or "-",
							okCk and tostring(N(ck, "secret/nil")) or "err", okSt and tostring(N(st, "secret/nil")) or "err",
							tostring(N(bt.IsEnabled and bt:IsEnabled(), "secret/nil")))
					end
					-- the share of the piece's own uv shown (its rectangle in an
					-- atlas sheet is a small part of the file)
					local shownW = (okT and u2 and u1) and (u2 - u1) or 0
					local shownH = (v2 or 0) - (v1 or 0)
					if kp and type(kp.uv) == "table" and kp.tile ~= "slice" then
						local du, dv = (kp.uv[2] or 1) - (kp.uv[1] or 0), (kp.uv[4] or 1) - (kp.uv[3] or 0)
						shownW = du ~= 0 and shownW / du or 0
						shownH = dv ~= 0 and shownH / dv or 0
					end
					-- a one-texture nine-slice: its family, and its w / h are the painted px it shows
					local isSlice = kp and kp.tile == "slice"
					if isSlice then
						shownW, shownH = 1, 1
					end
					rows[#rows + 1] = {
						key = order * 1e6 + level * 1e3 + layerOrder * 10 + (okL and sub or 0),
						text = string.format("%-34s %4dx%-4d  uv %.3f..%.3f x %.3f..%.3f  (%s: %dx%d px shown on %dx%d)  tint %.2f %.2f %.2f a=%.2f  %s/%s  %s L%d %s  file=%s",
							tostring(Kit.pieceNameOf[tex] or (isSlice and ("slice " .. tostring(kp.prefix)))), w, h, u1 or 0, u2 or 0, v1 or 0, v2 or 0,
							isSlice and "nine-slice" or kp and kp.tile and "tile" or "picture", math.floor(pieceW * shownW + 0.5), math.floor(pieceH * shownH + 0.5), w, h,
							okV and r or 1, okV and g or 1, okV and bl or 1, N(tex:GetAlpha(), 1),
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

--------------------------------------------------------------------------------
-- /mellokit: the one-texture nine-slices' switch and their test (user,
-- 2026-09-24: stage 2 of the performance programme, off by default).
--   /mellokit                   the switch, the data, the client's support
--   /mellokit slices on | off   the switch (saved); the UI reloads, so the
--                               whole kit is laid again the new way
--   /mellokit slices unit <n>   UI units one margin texel covers (1): only if
--                               the test shows the one-texture corners at
--                               another size than the pieces' (then /reload)
--   /mellokit slices count      every nine-slice built so far, per window: its
--                               rail textures in pieces and as one texture
--   /mellokit slicetest         today's rails beside the one-texture ones, at
--                               three sizes per case, and a third copy that
--                               blinks between the two (a difference jumps)
--------------------------------------------------------------------------------

do
	-- the rail textures a skin needs in pieces and as one texture, from what
	-- it holds (edges on the closed sides, each closed corner mitred or a gem).
	-- A skin whose rails wait (NineSlice's `defer`: a tab's open card not yet
	-- selected) is counted as it will be laid, from the options it keeps --
	-- no gem corners there, one texture if the switch was on when it was made
	-- (review, 2026-09-24: the count had them as skins of no pieces)
	local function RailCounts(skin)
		local wait = rawget(skin, "pendingArt")
		local cut = skin.slice and Kit.pieceOf[skin.slice]
		local open = {}
		for _, side in ipairs({ "t", "b", "l", "r" }) do
			if cut then
				open[side] = type(cut) == "table" and cut.open and cut.open:find(side, 1, true) ~= nil or false
			elseif wait then
				open[side] = (wait.open or ""):find(side, 1, true) ~= nil
			else
				open[side] = skin[side] == nil
			end
		end
		if wait then
			local want = wait.slices
			if want == nil then
				want = skin.slicesWas
			end
			local prefix = wait.prefix or "window/frame"
			local entry = want and Slices.api ~= false and SliceFamily(prefix)
			cut = entry and SliceCut(prefix, entry, open.l, open.r, open.t, open.b) or nil
		end
		local edges, mitred, gems = 0, 0, 0
		for _, side in ipairs({ "t", "b", "l", "r" }) do
			edges = edges + (open[side] and 0 or 1)
		end
		for _, c in ipairs({ "tl", "tr", "bl", "br" }) do
			if not open[c:sub(1, 1)] and not open[c:sub(2, 2)] then
				if skin.gemCorner and skin.gemCorner[c] then
					gems = gems + 1
				else
					mitred = mitred + 1
				end
			end
		end
		-- (a skin with a gem corner stays in pieces either way)
		return edges + mitred, (gems > 0) and (edges + mitred) or 1, cut and true or false
	end

	-- the window a frame is in: its last ancestor under UIParent
	local function TopWindow(frame)
		local f = frame
		for _ = 1, 40 do
			local p = f:GetParent()
			if not p or p == UIParent then
				break
			end
			f = p
		end
		local ok, name = pcall(f.GetName, f)
		if not (ok and type(name) == "string") then
			local okD, debugName = pcall(f.GetDebugName, f)
			name = okD and tostring(debugName) or "?"
		end
		return name
	end

	local function Count()
		local windows, order = {}, {}
		local total = { skins = 0, shown = 0, pieces = 0, one = 0, now = 0 }
		local f = EnumerateFrames()
		while f do
			if rawget(f, "melloSkin") and rawget(f, "all") then
				local pieces, one, sliced = RailCounts(f)
				local name = TopWindow(f)
				local w = windows[name]
				if not w then
					w = { skins = 0, shown = 0, pieces = 0, one = 0, now = 0 }
					windows[name] = w
					order[#order + 1] = name
				end
				local okV, visible = pcall(f.IsVisible, f)
				local shown = (okV and not Secret(visible) and visible) and 1 or 0
				for _, t in ipairs({ w, total }) do
					t.skins, t.shown = t.skins + 1, t.shown + shown
					t.pieces, t.one = t.pieces + pieces, t.one + one
					t.now = t.now + (sliced and one or pieces)
				end
			end
			f = EnumerateFrames(f)
		end
		table.sort(order, function(a, b) return windows[a].pieces - windows[a].one > windows[b].pieces - windows[b].one end)
		MelloUI:ClearLog()
		MelloUI:Print("Nine-slice rails built so far (a window's are built when it first opens), per window:")
		MelloUI:Print("%-44s %5s %5s %7s %9s %6s %4s", "window", "skins", "shown", "pieces", "one each", "saved", "now")
		for _, name in ipairs(order) do
			local w = windows[name]
			MelloUI:Print("%-44s %5d %5d %7d %9d %6d %4d", name:sub(1, 44), w.skins, w.shown, w.pieces, w.one, w.pieces - w.one, w.now)
		end
		MelloUI:Print("%-44s %5d %5d %7d %9d %6d %4d", "all", total.skins, total.shown, total.pieces, total.one, total.pieces - total.one, total.now)
		MelloUI:Print("pieces: rail textures as eight pieces; one each: as one texture (and a corner that stays its own); now: as the switch has them (%s)",
			Kit:SlicesOn() and "on" or "off")
		MelloUI:ShowLog("mellokit slices count")
	end

	local function Status()
		local data = SliceData()
		MelloUI:Print("One-texture nine-slices: %s (/mellokit slices on | off); a margin texel covers %s UI units.", Kit:SlicesOn() and "ON" or "off", tostring(SliceUnit()))
		if not data then
			MelloUI:Print("  Media\\KitSlices.lua is not loaded (not in MelloUI.toc?): everything stays in pieces.")
		else
			for prefix, entry in pairs(data) do
				MelloUI:Print("  %s: picture %dx%d texels, corners %d texels, %s; %s", prefix, entry.grid[1], entry.grid[2], entry.corner,
					PieceRoot(prefix .. "_t") .. tostring(entry.full), SliceFamily(prefix) and "ready" or "its pieces were tuned or rebuilt: stays in pieces")
			end
			MelloUI:Print("  a rail with gem corners (a window's outer rail) stays in pieces.")
		end
		if Slices.api == nil then
			-- not tried yet this session: one hidden texture asked, once
			local probe = UIParent:CreateTexture()
			probe:Hide()
			Slices.api = (probe.SetTextureSliceMargins and probe.SetTextureSliceMode and probe.SetScale) and true or false
		end
		MelloUI:Print("  this client %s cut a texture into a nine-slice.", Slices.api and "can" or "can NOT")
	end

	----------------------------------------------------------------------------
	-- The test window: one page per case, three sizes; per size the rails in
	-- pieces, as one texture, and a copy blinking between the two. The body
	-- (the stone) is the same texture in all three.
	----------------------------------------------------------------------------
	local test

	local function BuildTest()
		local SIZES = { { 140, 110 }, { 200, 140 }, { 260, 170 } }
		local COLUMN = 290

		local function Cases()
			-- (a window's outer rail, gem-cornered, stays in pieces: not a case)
			local frameScale = Kit.scale * (Kit.frameScale or 1.6)
			return {
				{ label = "Frames, insets and lists (window/single at the frame scale)", prefix = "window/single", scale = frameScale },
				{ label = "window/frame with its mitred corners", prefix = "window/frame", scale = Kit.scale },
				{ label = "window/single open at the top (an attached box: no top rail, no top corners)", prefix = "window/single", scale = frameScale, open = "t" },
				{ label = "window/single open on the right (the viewport, where it meets the pane divider)", prefix = "window/single", scale = frameScale, open = "r" },
				{ label = "window/frame open on the right, mitred corners", prefix = "window/frame", scale = Kit.scale, open = "r" },
			}
		end

		local function Label(parent, text, font)
			local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
			Kit:Paint(fs, "text", "text")   -- (by its key: a new palette paints it again)
			fs:SetText(text)
			return fs
		end

		-- what the page's one-texture skin is, and what a corner should cover
		local function Notes(case, pieces, sliced)
			local cut = sliced.slice and Kit.pieceOf[sliced.slice]
			local first
			if cut then
				local okS, texScale = pcall(sliced.slice.GetScale, sliced.slice)
				texScale = (okS and type(texScale) == "number") and texScale or 0
				local file = (PieceRoot(cut.prefix .. "_t") .. cut.file):gsub("^.-Media\\", "")
				first = string.format("one texture: %s, %dx%d texels shown, margins %d/%d/%d/%d (l/t/r/b), texture scale %.3f: a corner covers %.2f UI units",
					file, cut.w / cut.texel, cut.h / cut.texel,
					cut.margins[1], cut.margins[2], cut.margins[3], cut.margins[4], texScale, (cut.margins[1] > 0 and cut.margins[1] or cut.margins[3]) * texScale * SliceUnit())
			else
				first = "one texture: NOT drawn (/mellokit says why): both columns are pieces"
			end
			local tl = Kit:Piece(case.prefix .. "_tl")
			local second = string.format("pieces: a corner covers %.2f UI units (%d painted px x %.3f); rail textures per skin: %d in pieces, %d as one texture",
				pieces.thickness or 0, tl and tl.w or 0, case.scale, #pieces.art, #sliced.art)
			return first, second
		end

		local function BuildPage(parent, case, blinks)
			local page = CreateFrame("Frame", nil, parent)
			page:SetAllPoints(parent)
			page:Hide()
			for i, text in ipairs({ "Today (eight pieces)", "One texture", "Blinking between the two" }) do
				local h = Label(page, text, "GameFontNormal")
				h:SetPoint("TOPLEFT", page, "TOPLEFT", 90 + (i - 1) * COLUMN, -56)
			end
			local y = -84
			local first, second
			page.rows = {}
			for _, size in ipairs(SIZES) do
				local sizeLabel = Label(page, string.format("%d x %d", size[1], size[2]))
				sizeLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 16, y - 4)
				local skins = {}
				local row = { label = sizeLabel, size = size, cells = {} }
				page.rows[#page.rows + 1] = row
				for col = 1, 3 do
					local cell = CreateFrame("Frame", nil, page)
					cell:SetSize(size[1], size[2])
					cell:SetPoint("TOPLEFT", page, "TOPLEFT", 90 + (col - 1) * COLUMN, y)
					row.cells[col] = { frame = cell, x = 90 + (col - 1) * COLUMN, y = y }
					local function Skin(sliced)
						return Kit:NineSlice(cell, { prefix = case.prefix, scale = case.scale, corners = case.corners, skip = case.skip,
							open = case.open, gems = false, body = true, slices = sliced })
					end
					if col < 3 then
						skins[col] = Skin(col == 2)
					else
						local a, b = Skin(false), Skin(true)
						b:Hide()
						blinks[#blinks + 1] = { a, b }
					end
				end
				if not first then
					first, second = Notes(case, skins[1], skins[2])
				end
				y = y - size[2] - 28
			end
			local n1 = Label(page, first or "")
			n1:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 16, 58)
			local n2 = Label(page, second or "")
			n2:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 16, 42)
			return page
		end

		-- Zoom x2: the first size alone, its cells at twice the scale (the
		-- rails; the stone keeps the screen's one density), in the same
		-- columns; the window, its notes and buttons stay as they are (the
		-- whole window at x2 ran past the screen, its buttons with it --
		-- review, 2026-09-24)
		local function ZoomPage(page, on)
			for i, row in ipairs(page.rows) do
				local shown, s = not on or i == 1, (on and i == 1) and 2 or 1
				row.label:SetShown(shown)
				row.label:SetText(string.format("%d x %d%s", row.size[1], row.size[2], s > 1 and "\nat x2" or ""))
				for _, cell in ipairs(row.cells) do
					cell.frame:SetShown(shown)
					cell.frame:SetScale(s)
					cell.frame:ClearAllPoints()
					cell.frame:SetPoint("TOPLEFT", page, "TOPLEFT", cell.x / s, cell.y / s)
				end
			end
		end

		local f = CreateFrame("Frame", "MelloUISliceTest", UIParent)
		f:SetSize(960, 640)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		Perf.SetScript(f, "OnDragStart", f.StartMoving)
		Perf.SetScript(f, "OnDragStop", f.StopMovingOrSizing)
		f:SetClampedToScreen(true)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(f)
		Kit:Paint(bg, "innerPanel", "fill", 0.97)   -- (follows a palette switch)
		local title = Label(f, "", "GameFontNormal")
		title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
		local caseLabel = Label(f, "")
		caseLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
		local blinkLabel = Label(f, "")
		blinkLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 90 + 2 * COLUMN, -40)

		local cases, pages, blinks = Cases(), {}, {}
		for i, case in ipairs(cases) do
			blinks[i] = {}
			pages[i] = BuildPage(f, case, blinks[i])
		end
		local index = 1
		local function ShowPage(i)
			index = ((i - 1) % #pages) + 1
			for n, page in ipairs(pages) do
				page:SetShown(n == index)
			end
			title:SetText(string.format("MelloUI one-texture nine-slices: case %d of %d (switch %s, Kit.scale %.3f)", index, #pages,
				Kit:SlicesOn() and "ON" or "off", Kit.scale))
			caseLabel:SetText(cases[index].label)
		end
		local function Button(text, x, fn)
			local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			b:SetSize(96, 22)
			b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 10)
			b:SetText(text)
			Perf.SetScript(b, "OnClick", fn)
			return b
		end
		Button("< Previous", 16, function() ShowPage(index - 1) end)
		Button("Next >", 118, function() ShowPage(index + 1) end)
		local zoomed = false
		Button("Zoom x2", 220, function(self)
			zoomed = not zoomed
			for _, page in ipairs(pages) do
				ZoomPage(page, zoomed)
			end
			self:SetText(zoomed and "Zoom x1" or "Zoom x2")
			-- the stone repeats at the screen's one density again; the rails follow the scale
			Kit:RetileBackgrounds()
		end)
		Button("Close", 960 - 112, function() f:Hide() end)

		-- the blink: every 0.6 s the third copy swaps, while the window is open
		local phase, ticker = false, nil
		local function Blink()
			phase = not phase
			for _, pair in ipairs(blinks[index] or {}) do
				pair[1]:SetShown(not phase)
				pair[2]:SetShown(phase)
			end
			blinkLabel:SetText(phase and "showing: one texture" or "showing: pieces")
		end
		Perf.HookScript(f, "OnShow", function()
			if not ticker then
				ticker = C_Timer.NewTicker(0.6, Blink)
			end
		end)
		Perf.HookScript(f, "OnHide", function()
			if ticker then
				ticker:Cancel()
				ticker = nil
			end
		end)
		ShowPage(1)
		return f
	end

	-- luacheck: globals SLASH_MELLOKIT1
	SLASH_MELLOKIT1 = "/mellokit"
	SlashCmdList.MELLOKIT = function(msg)
		local words = {}
		for w in (msg or ""):lower():gmatch("%S+") do
			words[#words + 1] = w
		end
		local cmd, arg, value = words[1], words[2], words[3]
		if cmd == "slicetest" then
			if test then
				-- made afresh each time: the switch, the unit or the look may have changed
				test:Hide()
				test:SetParent(nil)
				test = nil
			end
			if not LAYOUT then
				MelloUI:Print("Kit layout missing (Media/KitLayout.lua).")
				return
			end
			test = BuildTest()
			test:Show()
		elseif cmd == "slices" and (arg == "on" or arg == "off") then
			local db = MelloUI.db
			if type(db) ~= "table" then
				MelloUI:Print("The settings are not loaded yet; try again in a moment.")
				return
			end
			db.kitSlices = (arg == "on") or nil
			-- (never ReloadUI here: the game blocks a reload MelloUI's code asks for, 0.19.9)
			MelloUI:Print("One-texture nine-slices %s: type /reload to lay the kit again.", arg)
		elseif cmd == "slices" and arg == "unit" then
			local db = MelloUI.db
			local n = tonumber(value)
			if type(db) == "table" then
				db.kitSliceUnit = (n and n > 0 and n ~= 1) and n or nil
			end
			MelloUI:Print("A margin texel covers %s UI units at texture scale 1: /mellokit slicetest shows it; /reload for the rest of the UI.", tostring(SliceUnit()))
		elseif cmd == "slices" and arg == "count" then
			Count()
		elseif cmd == "mouse" then
			-- the frames that are no button whose mouse a rim's hooks would have
			-- turned on (FollowButton put it back: Kit.mouseKept), by name
			local rows = 0
			MelloUI:ClearLog()
			for frame, kept in pairs(Kit.mouseKept) do
				rows = rows + 1
				local ok, name = pcall(frame.GetDebugName, frame)
				if not ok or Secret(name) or type(name) ~= "string" then
					name = "?"
				end
				MelloUI:Print("  %s: %s left off", name, kept)
			end
			MelloUI:Print("Frames under a rim that kept their mouse off: %d (open windows add to it).", rows)
			MelloUI:ShowLog("mellokit mouse")
		else
			Status()
			MelloUI:Print("  /mellokit slices on | off, /mellokit slicetest, /mellokit slices count, /mellokit slices unit <n>, /mellokit mouse")
		end
	end
end
