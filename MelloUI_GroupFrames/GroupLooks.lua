--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the looks
--
-- One indicator's regions and how each look lays them on a frame (a "host":
-- a game compact frame, your frame while solo, a sample in the Designer).
-- The same regions serve a slot of the game's aura container (the engine
-- fills them: the aura's icon, its time, its stacks, its debuff colour) and a
-- sample (filled here with made-up values, nothing read).
--   Looks.Make(b) -> parts        the regions, made once on the button b
--   Looks.Lay(b, parts, ind, host, healthFill, free, rgb)   placed and sized
--                                  for its look; the parts its look does not
--                                  use hidden (`free`: sized only -- a spell
--                                  group's container lays its buttons; `rgb`:
--                                  { r, g, b } in place of the indicator's own)
--   Looks.Hand(b, parts, ind)     the parts its look uses handed to the
--                                  slot's button (the others taken back)
--   Looks.Sample(b, parts, ind, frac)   a sample's made-up state (frac: the
--                                  time left, 0..1)
-- The looks (the user, 2026-10-09: "choose if something like renew is going
-- as an icon, or draining icon etc, font sizes and positions is also very
-- important"; pick 1A for the square):
--   icon    the aura's icon, its time as a sweep (a debuff's: the game's
--           border in its type's colour)
--   drain   the aura's icon drawn as a bar's fill, emptying from the top as
--           the time runs out, on its own dark shade
--   square  a square in the player's colour on its own dark shade, draining
--           from the top
--   bar     a thin bar along an edge (TOP / BOTTOM: across, LEFT / RIGHT: up),
--           its length the time left
--   health  the health bar's fill in the player's colour ("recolor your
--           Healthbar when you have certain Hots"): a tint over the fill,
--           drawn in the slot's button so it shows exactly while the game
--           shows the slot
-- The time and the stacks: text in their own size and place (3 x 3 round
-- the indicator, and an offset).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local W = MelloUI.Widgets
local Num = MelloUI.Safe.Number
local RD = ns.RD

local Looks = {}
ns.Looks = Looks

local WHITE = "Interface\\Buttons\\WHITE8X8"   -- look-ok: the square's and the bar's fill, in the player's colour
local CROP = 0.08                              -- an icon's rim cropped off
local SHADE = 0.85                             -- the square's own dark shade

-- a debuff kind's picture on a sample (the game's own icons)
local KIND_ICON = {
	Magic = "Interface\\Icons\\Spell_Holy_DispelMagic",          -- look-ok: a sample's picture
	Curse = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",      -- look-ok: a sample's picture
	Disease = "Interface\\Icons\\Spell_Shadow_CallofBone",        -- look-ok: a sample's picture
	Poison = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",    -- look-ok: a sample's picture
	boss = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",       -- look-ok: a sample's picture
	cc = "Interface\\Icons\\Spell_Nature_Polymorph",              -- look-ok: a sample's picture
}
local KIND_SAMPLE_TYPE = { group = "Magic", mine = "Magic", any = "Magic", Magic = "Magic", Curse = "Curse",
	Disease = "Disease", Poison = "Poison" }
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"   -- look-ok: a spell not known yet
Looks.KIND_ICON, Looks.UNKNOWN_ICON = KIND_ICON, UNKNOWN_ICON   -- (the spell groups' page)

-- the indicators' time and stacks: their Font row's face (one look C11,
-- GroupFrames.indicatorFont; RD.DB() so the stage's Try shows it), else the
-- numbers' face as the Fonts module has it
local function FontFile()
	local face = MelloUI:FaceOf(RD.DB().indicatorFont)
	if face then
		return face
	end
	local f = rawget(_G, "NumberFontNormalSmall") or rawget(_G, "GameFontHighlightSmall")
	local file = f and f.GetFont and f:GetFont()
	return file or rawget(_G, "STANDARD_TEXT_FONT")
end

-- a frame drawn at its parent's level (the client's SetUsingParentLevel; one
-- without it: the parent's level, set once)
function Looks.ParentLevel(f, on)
	if type(f.SetUsingParentLevel) == "function" then
		f:SetUsingParentLevel(on)
	elseif on then
		local parent = f:GetParent()
		if parent then
			f:SetFrameLevel(parent:GetFrameLevel())
		end
	end
end

-- a status bar's fill texture (nil where the client gives none)
function Looks.Fill(bar)
	return bar and type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture() or nil
end

-- the time as the bare number of seconds, rounded up, counting down to 1 (the
-- user, 2026-10-09: "they dont need to state "s" as in for seconds, they
-- should just count down ... just the raw number"): the core's one formatter
-- (MelloUI.Anim:RawSeconds, the nameplates' debuffs wear it too); nil where
-- the client has none (the game's own then)
local function RawSeconds()
	local Anim = MelloUI.Anim
	return Anim and Anim.RawSeconds and Anim:RawSeconds() or nil
end
Looks.RawSeconds = RawSeconds

local function Call(obj, method, ...)
	local fn = obj and obj[method]
	if type(fn) ~= "function" then
		return false
	end
	local ok = pcall(fn, obj, ...)
	return ok
end

--------------------------------------------------------------------------------
-- Make
--------------------------------------------------------------------------------

function Looks.Make(b)
	local p = {}
	p.shade = b:CreateTexture(nil, "BACKGROUND")
	p.shade:SetAllPoints(b)
	W.Paint(p.shade, "mainWindow", "fill", SHADE)
	p.icon = b:CreateTexture(nil, "ARTWORK")
	p.icon:SetAllPoints(b)
	p.icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
	p.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	p.cd:SetAllPoints(b)
	Call(p.cd, "SetDrawEdge", false)
	Call(p.cd, "SetHideCountdownNumbers", true)
	p.fill = CreateFrame("StatusBar", nil, b)
	p.fill:SetAllPoints(b)
	p.fill:SetStatusBarTexture(WHITE)
	p.fill:SetMinMaxValues(0, 1)
	p.fill:SetValue(1)
	p.border = b:CreateTexture(nil, "OVERLAY")
	p.border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
	p.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	p.edges = W.Edges(b, "mainWindow", "OVERLAY")
	p.tint = b:CreateTexture(nil, "OVERLAY")
	p.tint:SetTexture(WHITE)
	-- the texts over everything of the indicator's (a frame of their own above
	-- the sweep and the fill)
	p.texts = CreateFrame("Frame", nil, b)
	p.texts:SetAllPoints(b)
	p.texts:SetFrameLevel(b:GetFrameLevel() + 5)
	p.text = p.texts:CreateFontString(nil, "OVERLAY")
	p.count = p.texts:CreateFontString(nil, "OVERLAY")
	for _, fs in ipairs({ p.text, p.count }) do
		fs:SetFont(FontFile(), RD.SIZE.text, "OUTLINE")
		W.Paint(fs, "text", "text")
	end
	return p
end

--------------------------------------------------------------------------------
-- Lay
--------------------------------------------------------------------------------

local function ShowEdges(p, on)
	for i = 1, #p.edges do
		p.edges[i]:SetShown(on)
	end
end

-- (retail, never shipped: the user, 2026-10-24, the icons "make it a problem to
-- click cast heal") an aura button lets a click through to the frame under it
-- -- click casting, the unit's own click -- its hover still its tooltip. Set as
-- the button is made (the game holds a button to itself once its auras are
-- secret); WoW Forever's buttons as before
function Looks.ClickThrough(b)
	if RD.Retail() and type(b) == "table" and type(b.SetMouseClickEnabled) == "function" then
		pcall(b.SetMouseClickEnabled, b, false)
	end
end

-- every part put away (a Designer mark that holds a spell group's items, not
-- a look of its own)
function Looks.HideAll(p)
	for _, k in ipairs({ "shade", "icon", "cd", "fill", "border", "tint", "text", "count" }) do
		p[k]:Hide()
	end
	ShowEdges(p, false)
end

-- a text at its place round the indicator (or round the host for a bar
-- and the health colour: their own button is a line or nothing)
local function LayText(fs, t, anchor)
	fs:ClearAllPoints()
	if not (t and t.show) then
		fs:Hide()
		return
	end
	fs:SetFont(FontFile(), t.size or RD.SIZE.text, "OUTLINE")
	local point = t.point or "CENTER"
	fs:SetPoint(point, anchor, point, t.x or 0, t.y or 0)
	fs:Show()
end

local EDGE_INSET = 1

-- (one look C9) a bar's place as numbers, the one rule: the point it is
-- anchored by on the host (CENTER is the bottom edge's middle), the offset
-- that rule gives before the player's own, whether it runs up (LEFT and
-- RIGHT), and its size on a host w x h
function Looks.BarSpot(point, size, length, w, h)
	point = point or "BOTTOM"
	size = size or 3
	local len = math.max(0.1, math.min(1, length or 1))
	if point == "LEFT" or point == "RIGHT" then
		return point, point == "LEFT" and EDGE_INSET or -EDGE_INSET, 0, true, size, math.max(1, (h - 2 * EDGE_INSET) * len)
	end
	local edge = (point:find("TOP") and "TOP") or "BOTTOM"
	local side = (point:find("LEFT") and "LEFT") or (point:find("RIGHT") and "RIGHT") or ""
	local dx = (side == "LEFT" and EDGE_INSET) or (side == "RIGHT" and -EDGE_INSET) or 0
	return edge .. side, dx, edge == "TOP" and -EDGE_INSET or EDGE_INSET, false, math.max(1, (w - 2 * EDGE_INSET) * len), size
end

-- (one look C9) BarSpot the other way: a bar dropped at l, b, r, t (the
-- host's units from its bottom left) -> the point, x and y that lay it there
-- (a drag keeps its direction: `keep`; else a bar taller than wide runs up).
-- Its edge and its side the ones it lies nearest, each by its gap (an edge's
-- inset, the middle's centre); a tie keeps the one it had
local FX = { LEFT = 0, RIGHT = 1 }
function Looks.BarDrop(l, b, r, t, w, h, ind, keep)
	local was = ind and ind.point or "BOTTOM"
	local vertical
	if keep then
		vertical = was == "LEFT" or was == "RIGHT"
	else
		vertical = (t - b) > (r - l)
	end
	local gl, gr = math.abs(l - EDGE_INSET), math.abs(w - EDGE_INSET - r)
	local point
	if vertical then
		point = (gl < gr or (gl == gr and was ~= "RIGHT")) and "LEFT" or "RIGHT"
	else
		local gt, gb = math.abs(h - EDGE_INSET - t), math.abs(b - EDGE_INSET)
		local edge = (gt < gb or (gt == gb and was:find("^TOP") ~= nil)) and "TOP" or "BOTTOM"
		local gc = math.abs((l + r) / 2 - w / 2)
		local side = was:match("LEFT$") or was:match("RIGHT$") or ""
		local best = (side == "LEFT" and gl) or (side == "RIGHT" and gr) or gc
		if gl < best then
			side, best = "LEFT", gl
		end
		if gc < best then
			side, best = "", gc
		end
		if gr < best then
			side = "RIGHT"
		end
		point = edge .. side
	end
	local at, dx, dy, _, bw, bh = Looks.BarSpot(point, ind and ind.size, ind and ind.length, w, h)
	local fx = FX[at:match("LEFT$") or at:match("RIGHT$") or ""] or 0.5
	local fy = (at:find("^TOP") and 1) or (at:find("^BOTTOM") and 0) or 0.5
	local x = (l + fx * bw) - fx * w - dx
	local y = (b + fy * bh) - fy * h - dy
	return point, math.floor(x + 0.5), math.floor(y + 0.5)
end

-- a bar's edge: its points on the host and whether it runs up (`free`: its
-- size only, a spell group's bars laid by their container: across)
local function BarPlace(b, ind, host, free)
	local w, h = Num(host:GetWidth()) or 72, Num(host:GetHeight()) or 36
	local at, dx, dy, vertical, bw, bh = Looks.BarSpot(free and "BOTTOM" or ind.point, ind.size, ind.length, w, h)
	if free then
		b:SetSize(bw, bh)
		return false
	end
	b:ClearAllPoints()
	b:SetSize(bw, bh)
	b:SetPoint(at, host, at, dx + (ind.x or 0), dy + (ind.y or 0))
	return vertical
end

function Looks.Lay(b, p, ind, host, healthFill, free, rgb)
	local look = ind.look
	local size = ind.size or 12
	-- (a debuff in its type's colour: the game colours the fill or the tint;
	-- a lay leaves it alone; a spell group's debuffs too)
	local own = not ((ind.kind == "debuff" or ind.kind == "group") and ind.colourBy == "type")
	local cr, cg, cb = ind.r or 1, ind.g or 1, ind.b or 1
	if rgb then
		cr, cg, cb = rgb[1] or cr, rgb[2] or cg, rgb[3] or cb
	end
	p.shade:Hide()
	p.icon:Hide()
	p.cd:Hide()
	p.fill:Hide()
	p.border:Hide()
	p.tint:Hide()
	ShowEdges(p, false)
	if look == "bar" then
		local vertical = BarPlace(b, ind, host, free)
		p.fill:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
		p.fill:SetStatusBarTexture(WHITE)
		if own then
			p.fill:SetStatusBarColor(cr, cg, cb)
		end
		p.shade:Show()
		p.fill:Show()
	elseif look == "health" then
		if not free then
			b:ClearAllPoints()
			b:SetPoint("CENTER", host, "CENTER", 0, 0)
		end
		b:SetSize(1, 1)
		p.tint:ClearAllPoints()
		if healthFill then
			p.tint:SetAllPoints(healthFill)
		end
		if own then
			p.tint:SetVertexColor(cr, cg, cb, ind.alpha or 0.55)
		else
			p.tint:SetAlpha(ind.alpha or 0.55)
		end
		p.tint:Show()
	else
		if not free then
			b:ClearAllPoints()
			b:SetPoint(ind.point or "CENTER", host, ind.point or "CENTER", ind.x or 0, ind.y or 0)
		end
		b:SetSize(size, size)
		if look == "icon" then
			p.icon:Show()
			p.cd:Show()
			ShowEdges(p, true)
			p.border:SetShown(not own)
		elseif look == "drain" then
			p.shade:Show()
			p.fill:SetOrientation("VERTICAL")
			p.fill:SetStatusBarColor(1, 1, 1)
			p.fill:Show()
			ShowEdges(p, true)
		else
			-- square (pick 1A: its own dark shade, draining from the top)
			p.shade:Show()
			p.fill:SetOrientation("VERTICAL")
			p.fill:SetStatusBarTexture(WHITE)
			if own then
				p.fill:SetStatusBarColor(cr, cg, cb)
			end
			p.fill:Show()
			ShowEdges(p, true)
		end
	end
	local anchor = (look == "health") and host or b
	LayText(p.text, look ~= "bar" and ind.text, anchor)
	LayText(p.count, look ~= "bar" and look ~= "health" and ind.count, anchor)
end

--------------------------------------------------------------------------------
-- Block (the spell groups, GroupSpellGroups.lua): n items of iw x ih laid
-- the group's way from its spot -- the first where one alone would stand,
-- the rest along its Grow, a new line after Per Line, the lines away from the
-- edge it stands on. The block's size, and each item's top left in it (right,
-- down); Pin: where the block hangs. One rule for the game's container (a
-- flowing group), your order's slots on the frames and the Designer's samples.
--   Looks.Way(ind) -> dir, wx, wy, fx, fy   (a bar's way upright, as the container lays it)
--   Looks.Block(ind, n, iw, ih, out) -> bw, bh, out
--   Looks.Pin(ind, iw, ih) -> point, x, y   the block's own point, off the group's spot
--   Looks.AtBlock(b, host, ind, bw, bh, at, iw, ih)   item b laid at its place
--------------------------------------------------------------------------------

local DIR = { RIGHT = { 1, 0 }, LEFT = { -1, 0 }, DOWN = { 0, 1 }, UP = { 0, -1 } }
Looks.FX = { TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, LEFT = 0, CENTER = 0.5, RIGHT = 1, BOTTOMLEFT = 0, BOTTOM = 0.5,
	BOTTOMRIGHT = 1 }
Looks.FY = { TOPLEFT = 0, TOP = 0, TOPRIGHT = 0, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, BOTTOMLEFT = 1, BOTTOM = 1,
	BOTTOMRIGHT = 1 }

function Looks.Way(ind)
	local point = ind.point or "TOPRIGHT"
	local fx, fy = Looks.FX[point] or 0.5, Looks.FY[point] or 0.5
	local grow = ind.grow
	if ind.look == "bar" and grow ~= "UP" and grow ~= "DOWN" then
		grow = fy == 1 and "UP" or "DOWN"
	end
	local dir = DIR[grow] or DIR.LEFT
	local wx = dir[1] == 0 and (fx == 1 and -1 or 1) or 0
	local wy = dir[1] ~= 0 and (fy == 1 and -1 or 1) or 0
	return dir, wx, wy, fx, fy
end

-- (2026-10-25, the user: Grow Right "doesn't change anything" -- the block hung by its spot's own corner, so a
-- Grow only turned its order round) the block hangs by its first item: where one alone would stand on the spot,
-- the block going the Grow's way from it; across, on the spot's line
function Looks.Pin(ind, iw, ih)
	local dir, _, _, fx, fy = Looks.Way(ind)
	local h, v, x, y
	if dir[1] ~= 0 then
		h = dir[1] > 0 and "LEFT" or "RIGHT"
		v = fy == 0 and "TOP" or fy == 1 and "BOTTOM" or ""
		x, y = dir[1] > 0 and -fx * iw or (1 - fx) * iw, 0
	else
		v = dir[2] > 0 and "TOP" or "BOTTOM"
		h = fx == 0 and "LEFT" or fx == 1 and "RIGHT" or ""
		x, y = 0, dir[2] > 0 and fy * ih or -(1 - fy) * ih
	end
	local point = v .. h
	return point == "" and "CENTER" or point, (ind.x or 0) + x, (ind.y or 0) + y
end

function Looks.Block(ind, n, iw, ih, out)
	local dir, wx, wy = Looks.Way(ind)
	local per = math.max(1, ind.perLine or 4)
	local gap = ind.spacing or 1
	out = out or {}
	local minx, miny, maxx, maxy = 0, 0, 0, 0
	for i = 1, n do
		local a, line = (i - 1) % per, math.floor((i - 1) / per)
		local x = dir[1] * a * (iw + gap) + wx * line * (iw + gap)
		local y = dir[2] * a * (ih + gap) + wy * line * (ih + gap)
		out[i] = out[i] or {}
		out[i][1], out[i][2] = x, y
		minx, miny = math.min(minx, x), math.min(miny, y)
		maxx, maxy = math.max(maxx, x + iw), math.max(maxy, y + ih)
	end
	for i = 1, n do
		out[i][1], out[i][2] = out[i][1] - minx, out[i][2] - miny
	end
	return maxx - minx, maxy - miny, out
end

function Looks.AtBlock(b, host, ind, bw, bh, at, iw, ih)
	local pin, x, y = Looks.Pin(ind, iw, ih)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", host, ind.point or "TOPRIGHT", x - Looks.FX[pin] * bw + at[1], y + Looks.FY[pin] * bh - at[2])
end

--------------------------------------------------------------------------------
-- Hand: the parts a look uses handed to a slot's button, the rest taken back
--------------------------------------------------------------------------------

local function Enum2(group, name)
	local E = rawget(_G, "Enum")
	local t = type(E) == "table" and E[group]
	return type(t) == "table" and t[name] or nil
end

function Looks.Hand(b, p, ind)
	local look = ind.look
	for _, m in ipairs({ "ClearIcon", "ClearDurationCooldown", "ClearDurationBar", "ClearDurationText", "ClearApplicationCount" }) do
		Call(b, m)
	end
	if p.typed then
		Call(b, "RemoveDispelTypeTexture", p.typed)
		p.typed = nil
	end
	local remaining = Enum2("StatusBarTimerDirection", "RemainingTime")
	local barOpts = remaining and { direction = remaining } or nil
	local byType = (ind.kind == "debuff" or ind.kind == "group") and ind.colourBy == "type"
	local style = Enum2("CustomAuraButtonDispelTypeTextureStyle", byType and look == "icon" and "Border" or "PreserveAsset")
	local typed = nil
	if look == "icon" then
		Call(b, "SetIcon", p.icon)
		Call(b, "SetDurationCooldown", p.cd)
		typed = byType and p.border
	elseif look == "drain" then
		Call(b, "SetIcon", Looks.Fill(p.fill))
		Call(b, "SetDurationBar", p.fill, barOpts)
	elseif look == "square" or look == "bar" then
		Call(b, "SetDurationBar", p.fill, barOpts)
		typed = byType and Looks.Fill(p.fill)
	elseif look == "health" then
		typed = byType and p.tint
	end
	if typed and style ~= nil then
		if Call(b, "AddDispelTypeTexture", typed, { style = style, showWhenHarmful = true, showWithoutDispelType = true }) then
			p.typed = typed
		end
	end
	if look ~= "bar" and ind.text and ind.text.show then
		local f = RawSeconds()
		Call(b, "SetDurationText", p.text, f and { textFormatter = f } or nil)
	end
	if look ~= "bar" and look ~= "health" and ind.count and ind.count.show then
		Call(b, "SetApplicationCount", p.count)
	end
end

--------------------------------------------------------------------------------
-- Sample: a made-up state (the Designer, the fake raid): nothing read
--------------------------------------------------------------------------------

local function SampleTypeColour(ind)
	local t = KIND_SAMPLE_TYPE[ind.what]
	local c = t and rawget(_G, "DEBUFF_TYPE_" .. t:upper() .. "_COLOR")
	if type(c) == "table" and c.GetRGB then
		return c:GetRGB()
	end
	return RD.NamedColour("RED_FONT_COLOR")
end

function Looks.Sample(b, p, ind, frac)
	frac = frac or 0.6
	local look = ind.look
	local icon = (ind.kind == "buff" and (RD:SpellIcon(ind) or UNKNOWN_ICON)) or KIND_ICON[ind.what] or KIND_ICON.Magic
	local byType = ind.kind == "debuff" and ind.colourBy == "type"
	if look == "icon" then
		p.icon:SetTexture(icon)
		Call(p.cd, "SetCooldown", GetTime() - (1 - frac) * 15, 15)
		if byType then
			p.border:SetTexture(WHITE)
			p.border:SetVertexColor(SampleTypeColour(ind))
			p.border:SetDrawLayer("BACKGROUND", -1)
		end
	elseif look == "drain" then
		p.fill:SetStatusBarTexture(icon)
		p.fill:SetValue(frac)
	elseif look == "square" or look == "bar" then
		p.fill:SetValue(frac)
		if byType then
			p.fill:SetStatusBarColor(SampleTypeColour(ind))
		end
	elseif look == "health" and byType then
		local r, g, bl = SampleTypeColour(ind)
		p.tint:SetVertexColor(r, g, bl, ind.alpha or 0.55)
	end
	p.text:SetText(tostring(math.floor(frac * 15 + 0.5)))
	p.count:SetText("2")
	b:Show()
end
