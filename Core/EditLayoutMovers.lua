--------------------------------------------------------------------------------
-- MelloUI - Edit Layout: the plates (0.15.0)
--
-- Every element Edit Layout moves gets a PLATE (D2): a flat frame of our
-- own laid over the element's whole rect, parented to and anchored to
-- UIParent only (never to the element: a frame anchored to a protected
-- window becomes protected and could no longer be hidden at the combat
-- pause), on FULLSCREEN, the larger ones lower (a small element over a big
-- window can still be taken hold of). On a plate: drag (the cursor read by
-- hand every frame while the button is held, so the snapping is live: D3),
-- the wheel (the size, 5 % of the standard size a notch, 1 % with Shift, a
-- detent at 100 %), a click (selected: the arrow keys nudge it), a
-- right-click (the box, Core/EditLayout.lua) and Ctrl+right-click (its
-- pending reset). The look, the guide lines, the readout, the veil, the
-- scrim, the outer glow and the lit rail are here too (Unlock the Windows'
-- SizeTip, OuterGlow, Veil and grid, re-made on palette keys). The spec is
-- v150/editspec/SPEC.md (sections 2.4-2.8, 2.13's nudge, 4 and 5).
--
--   P = MelloUI.EditLayout.Movers, for Core/EditLayout.lua:
--     P.Setup()            the first Open (the palette listener)
--     P.ShowAll()          the scrim and every plate (the mode shows)
--     P.HideAll()          a drag ended where it is, a held arrow stopped,
--                          every plate and piece hidden (a pause, the end)
--     P.SyncAll()          every plate laid from its element again now;
--     P.SyncSoon()         ... once on the next frame (Kit:NextFrame)
--     P.Redraw()           the screen's size changed (guides, grid)
--     P.Dragging() -> entry | nil,  P.EndDrag()   (dropped where it is)
--     P.Selected() -> entry | nil,  P.Deselect(),  P.CanNudge()
--     P.KeyDown(key) / P.KeyUp([key])   the nudge (Shift read at each step)
--                          and its repeat
--     P.ClickedElsewhere() a click on the world: no selection
--     P.PlateAtCursor(), P.RightClick(plate)   (the box's catcher)
--     P.Fraction(entry), P.ScaleTo(entry, fraction), P.CentreOffset(entry),
--     P.MoveCentreTo(entry, x, y)   the box's Size and Position (x or y
--                          nil: that axis stays)
--     P.Label(entry), P.LockedReason(entry), P.Note(entry),
--     P.SnapChoices(entry, values), P.BridgeCount(), P.Dump(print)
--   E.NewPlate() -> plate | nil   a plate for a layer (the bridge): it lays it
--     (plate:Lay(l, b, w, h)), names it (plate:SetLabel(text)), shows it
--     (plate:Show()), gives its hover and right-click (plate:SetBridge({
--     tip, line, onEnter, onLeave, onRightClick })), lights it from its own
--     overlay (plate:SetLit(on)), reads its hover line's rect for that overlay
--     (plate:LineRect() -> l, b, w, h) and gives it back (plate:Release()).
--     A pause hides it; the layer shows it again at its next Sync. nil when
--     the pool is full.
-- The drag (SPEC 2.6): the element's rect and every other plate's are read
-- once at the press; each frame while the button is held reads the cursor,
-- locks the axis (Shift), snaps (MelloUI.EditLayoutSnap; not with Alt),
-- keeps the element on the screen with what moves with it, rounds it to the
-- pixel grid and moves it (Core's MoveEntry), the plate with it -- no frame
-- read, no table or closure made. The drop makes the place pending
-- (LayoutSession.Set) and hangs the element by its own anchor again.
-- No colour number: every colour is a palette key painted through W.Paint,
-- or the selected trim lit to full brightness for the added light (the
-- glow, the guide lines), painted again on 'palette'.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("EditLayoutMovers")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer
local Safe = MelloUI.Safe
local Secret = Safe.IsSecret
local Num = Safe.Number
local W = MelloUI.Widgets
local Snap = MelloUI.EditLayoutSnap
local E = MelloUI.EditLayout

local P = {}
E.Movers = P

local abs, floor, ceil, max, min = math.abs, math.floor, math.ceil, math.max, math.min

local WHITE = "Interface\\Buttons\\WHITE8x8"
local MINUS = "\226\136\146"   -- (U+2212: a readout's minus)
local LEVEL0, LEVEL_STEP = 10, 3          -- the plates' levels on FULLSCREEN: the largest at 10 (a plate, its chip, a glow under it)
local DIALOG_MIN, DIALOG_MAX = 2, 8       -- on FULLSCREEN_DIALOG (an element that stands that high): under the bar and box
local MIN_W, MIN_H = 24, 16               -- a plate's least size, grown about the element's centre
local CHIP_MIN_W, CHIP_MIN_H = 60, 18     -- a plate smaller than this shows its name in the tooltip only
local CHIP_PAD_X, CHIP_PAD_Y = 6, 3
local DRAG_PX = 3                          -- a press becomes a drag past this
local STEP, FINE_STEP = 5, 1               -- %: a wheel notch, with Shift
local RANGE_MIN, RANGE_MAX = 0.5, 2        -- the size's range, of the standard size (an entry's min / max otherwise)
local DETENT = 0.3                         -- s: the wheel holds at 100 %
local HOLD, FADE = 1.2, 0.4                -- s: the readout after a drop, then its fade
local PLATE_FADE = 0.12
-- the outer glow's reach and its strength at the plate (2026-10-04, the user: "kind of too big" while
-- dragging: 28 and 0.7 before)
local GLOW, GLOW_ALPHA = 14, 0.5
local MAX_PLATES, FIRST_BATCH = 64, 32     -- the pool, and the plates made in one frame
local SYNC_KEY = "EditLayout sync"
local HIGH_STRATA = { FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }
local POINT_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5,
	TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local POINT_Y = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
	BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }

-- the states' looks (SPEC 2.4): fill key and alpha, edge key and alpha,
-- edge width in physical pixels
local LOOK = {
	idle = { "innerPanel", 0.35, "trim", 0.8, 1 },
	hover = { "hover", 0.45, "selectedTrim", 1, 1 },
	selected = { "selectedTab", 0.40, "selectedTrim", 1, 2 },
	dragging = { "hover", 0.45, "selectedTrim", 1, 1 },
	locked = { "mainWindow", 0.35, "border", 1, 1 },
	placeholder = { "innerPanel", 0.25, "trim", 0.5, 1 },
	bridge = { "mainWindow", 0.35, "border", 1, 1 },
}

local TEXT = {
	hidden = "%s (hidden)",
	size = "Size %d %%",
	sizeTip = "Size %d %% \194\183 X %d  Y %d",
	hint = "Drag to move, wheel to resize, right-click for options.",
	hintNoSize = "Drag to move, right-click for options.",   -- (resize = false: the wheel does nothing there)
	sizeOff = "Its size is set on its page.",
	gameOwned = "Its place is set in the game's Edit Mode.",
	standard = "The standard size",
	wheelBack = "Wheel back to 100% for the standard size",
	resetHint = "Ctrl+right-click puts it back",
	bridgeLine = "Move via Edit Mode",
}
E.PLATE_TEXTS = TEXT   -- (the plates' in-game texts, beside the mode's E.TEXTS: SPEC 9)

local function Report(err)
	local handler = geterrorhandler and geterrorhandler()
	if type(handler) == "function" then
		handler(err)
	end
end

local function Session()
	return MelloUI.LayoutSession
end

-- a palette colour at full brightness (its brightest channel at 1): the
-- added light's colour
local function Lit(key)
	local c = MelloUI.Look.Palette()[key]   -- (the reskin off: the game's colours)
	local m = max(c[1], c[2], c[3])
	if m <= 0 then
		return c[1], c[2], c[3]
	end
	return c[1] / m, c[2] / m, c[3] / m
end

-- the screen in UI units, and its physical pixels per unit (read at every
-- show and screen change, never per frame)
local screenW, screenH, perUnit = 0, 0, 1
local function ReadScreen()
	screenW, screenH = Num(UIParent:GetWidth()) or 0, Num(UIParent:GetHeight()) or 0
	local ok, _, ph = pcall(GetPhysicalScreenSize)
	perUnit = Snap.PerUnit(ok and Num(ph) or nil, screenH)
end

local function Cursor()
	local x, y = GetCursorPosition()
	local us = Num(UIParent:GetEffectiveScale()) or 1
	if us <= 0 then
		us = 1
	end
	return (Num(x) or 0) / us, (Num(y) or 0) / us
end

-- a number as a readout writes it (the typographic minus)
local function Signed(v)
	v = floor(v + 0.5)
	if v < 0 then
		return MINUS .. tostring(-v)
	end
	return tostring(v)
end

--------------------------------------------------------------------------------
-- An entry, read
--------------------------------------------------------------------------------

function P.Label(entry)
	local label = entry.label or entry.key
	if label == nil and entry.frame and entry.frame.GetName then
		local ok, name = pcall(entry.frame.GetName, entry.frame)
		label = ok and Safe.Text(name) or nil
	end
	return tostring(label or "?")
end

-- an owner's function of the entry, its text or nil
local function Ask(entry, field)
	local fn = entry[field]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, text = pcall(fn, entry)
	if not ok then
		Report(text)
		return nil
	end
	return type(text) == "string" and not Secret(text) and text or nil
end

function P.LockedReason(entry)
	return Ask(entry, "locked")
end

function P.Note(entry)
	return Ask(entry, "note")
end

-- its own scale, read plainly
local function FrameScale(entry)
	local f = entry.frame
	local ok, s = pcall(f.GetScale, f)
	s = ok and Num(s)
	return (s and s > 0) and s or nil
end

local function Base(entry)
	local base = MelloUI.EntryBase and MelloUI:EntryBase(entry)
	base = Num(base)
	return (base and base > 0) and base or 1
end

-- the scale the session keeps: false (none) at exactly 100 % when the entry
-- names its 100 % (Unlock the Windows' rule)
local function ScaleArg(entry, scale)
	local named = Num(entry.base)
	if named and named > 0 and abs(scale - named) <= 0.001 then
		return false
	end
	return scale
end

local function Range(entry)
	local base = Base(entry)
	return Num(entry.min) or RANGE_MIN * base, Num(entry.max) or RANGE_MAX * base
end

-- the point that stays put when it is sized: its own anchor's, else its
-- centre
local function Pivot(entry, l, b, w, h)
	local a = entry.anchor
	if a and POINT_X[a] then
		return l + POINT_X[a] * w, b + POINT_Y[a] * h
	end
	return l + w / 2, b + h / 2
end

-- the frames kept on the screen with it (a frame, a list, or a function
-- giving either: a bag window's stack, worked out as it is needed)
local function WithOf(entry)
	local with = entry.with
	if type(with) == "function" then
		local ok, got = pcall(with, entry)
		with = ok and got or nil
	end
	return type(with) == "table" and with or nil
end

local function IsWith(frame, with)
	if with == nil then
		return false
	end
	if with == frame then
		return true
	end
	if with.GetObjectType == nil then
		for i = 1, #with do
			if with[i] == frame then
				return true
			end
		end
	end
	return false
end

-- the extents grown by one shown frame's rect (UI units)
local function Grow(f, l, b, w, h, eL, eB, eR, eT, us)
	if type(f) ~= "table" or type(f.IsShown) ~= "function" then
		return eL, eB, eR, eT
	end
	local ok, shown = pcall(f.IsShown, f)
	if not ok or Secret(shown) or not shown then
		return eL, eB, eR, eT
	end
	local fl, fb, fr, ft = Safe.ScreenRect(f)
	if not fl then
		return eL, eB, eR, eT
	end
	fl, fb, fr, ft = fl / us, fb / us, fr / us, ft / us
	return max(eL, l - fl), max(eB, b - fb), max(eR, fr - (l + w)), max(eT, ft - (b + h))
end

-- how far the shown `with` frames reach past the element's own edges (UI
-- units, each 0 or more)
local function Extents(entry, l, b, w, h)
	local with = WithOf(entry)
	local eL, eB, eR, eT = 0, 0, 0, 0
	if with == nil then
		return eL, eB, eR, eT
	end
	local us = Num(UIParent:GetEffectiveScale()) or 1
	if us <= 0 then
		us = 1
	end
	if with.GetObjectType then
		return Grow(with, l, b, w, h, eL, eB, eR, eT, us)
	end
	for i = 1, #with do
		eL, eB, eR, eT = Grow(with[i], l, b, w, h, eL, eB, eR, eT, us)
	end
	return eL, eB, eR, eT
end

-- `frame` is `target` or a frame parented to it (a few steps up)
local function Under(frame, target)
	local f = frame
	for _ = 1, 4 do
		if f == target then
			return true
		end
		if type(f) ~= "table" or type(f.GetParent) ~= "function" then
			return false
		end
		local ok, parent = pcall(f.GetParent, f)
		if not ok or Secret(parent) or type(parent) ~= "table" then
			return false
		end
		f = parent
	end
	return false
end

-- an element that HANGS on the dragged one: its first anchor's frame,
-- followed up to four steps through each frame's own first anchor, is the
-- dragged frame or one of its children (the Quest Tracker glued under a
-- dragged minimap column); plain reads only
local function HangsOn(frame, target)
	local f = frame
	for _ = 1, 4 do
		if type(f) ~= "table" or type(f.GetPoint) ~= "function" then
			return false
		end
		local ok, _, rel = pcall(f.GetPoint, f, 1)
		if not ok or Secret(rel) or type(rel) ~= "table" or rel == UIParent then
			return false
		end
		if Under(rel, target) then
			return true
		end
		f = rel
	end
	return false
end

--------------------------------------------------------------------------------
-- Plates: a pool of flat frames of our own
--------------------------------------------------------------------------------

local pool = {}                                      -- free plates
local active = {}                                    -- plates in use (the entries' and the layers')
local plateOf = setmetatable({}, { __mode = "k" })   -- [entry] = its plate
local madeCount, serial = 0, 0
local selected = nil                                 -- the selected entry
local drag = { cands = {}, nc = 0, hangers = {}, nh = 0 }
local driver                                         -- the drag's and the held arrow's OnUpdate frame
local Paint, LayChip, PlateEnter   -- below

-- the edges' width: `all` physical pixels, the top one `top` (a pending
-- change's mark)
local function Thickness(plate, all, top)
	local t, tt = all / perUnit, max(all, top) / perUnit
	if plate.edgeT == t and plate.edgeTT == tt then
		return
	end
	plate.edgeT, plate.edgeTT = t, tt
	local e = plate.edges
	e[1]:SetPoint("BOTTOMRIGHT", plate, "TOPRIGHT", 0, -tt)
	e[2]:SetPoint("TOPLEFT", plate, "BOTTOMLEFT", 0, t)
	e[3]:SetPoint("BOTTOMRIGHT", plate, "BOTTOMLEFT", t, 0)
	e[4]:SetPoint("TOPLEFT", plate, "TOPRIGHT", -t, 0)
end

local function StateOf(plate)
	if drag.started and drag.plate == plate then
		return "dragging"
	end
	if plate.kind == "bridge" then
		return "bridge"
	end
	if plate.locked then
		return "locked"
	end
	if selected ~= nil and plate.entry == selected then
		return "selected"
	end
	if plate.hover or plate.lit then
		return "hover"
	end
	if plate.hidden then
		return "placeholder"
	end
	return "idle"
end

Paint = function(plate)
	local look = LOOK[StateOf(plate)]
	W.Paint(plate.fill, look[1], "fill", look[2])
	local edgeKey, edgeAlpha, px = look[3], look[4], look[5]
	if plate.target then
		edgeKey, edgeAlpha, px = "selectedTrim", 1, 2
	end
	local e = plate.edges
	W.Paint(e[1], plate.changed and "selectedTrim" or edgeKey, "fill", plate.changed and 1 or edgeAlpha)
	for i = 2, 4 do
		W.Paint(e[i], edgeKey, "fill", edgeAlpha)
	end
	Thickness(plate, px, plate.changed and 2 or px)
end

-- the chip: the name on a dark panel (never text on a light wash), and on
-- hover a second line (the size when not 100 %, the bridge's "Move via
-- Edit Mode")
LayChip = function(plate)
	local chip = plate.chip
	local r = plate.rect
	if r.w < CHIP_MIN_W or r.h < CHIP_MIN_H then
		chip:Hide()
		return
	end
	local second = nil
	if plate.kind == "bridge" then
		if plate.hover or plate.lit then
			second = plate.line or TEXT.bridgeLine
		end
	elseif plate.hover and plate.entry then
		local scale = FrameScale(plate.entry)
		local percent = scale and floor(scale / Base(plate.entry) * 100 + 0.5)
		if percent and percent ~= 100 then
			second = string.format(TEXT.size, percent)
		end
	end
	chip.label:SetText(plate.label or "")
	chip.line2:SetText(second or "")
	chip.line2:SetShown(second ~= nil)
	W.Paint(chip.line2, plate.kind == "bridge" and "selectedTrim" or "text", "text")
	local tw = Num(chip.label:GetStringWidth()) or 0
	local th = Num(chip.label:GetStringHeight()) or 12
	if second then
		tw = max(tw, Num(chip.line2:GetStringWidth()) or 0)
		th = th + 1 + (Num(chip.line2:GetStringHeight()) or 12)
	end
	chip:SetSize(ceil(tw) + 2 * CHIP_PAD_X, ceil(th) + 2 * CHIP_PAD_Y)
	chip:Show()
end

-- laid from the element's rect (UI units), drawn at least MIN_W x MIN_H
local function PlateLay(plate, l, b, w, h)
	local r = plate.rect
	local sized = r.w ~= w or r.h ~= h
	r.l, r.b, r.w, r.h = l, b, w, h
	plate.area = w * h
	local dw, dh = max(w, MIN_W), max(h, MIN_H)
	local dl, db = l - (dw - w) / 2, b - (dh - h) / 2
	plate.l, plate.b, plate.w, plate.h = dl, db, dw, dh
	plate:ClearAllPoints()
	plate:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", dl, db)
	if sized then
		plate:SetSize(dw, dh)
		LayChip(plate)
	end
end

local function PlateLabel(plate, text)
	plate.label = text
	LayChip(plate)
end

local function PlateBridge(plate, spec)
	plate.bridge = type(spec) == "table" and spec or nil
	plate.line = plate.bridge and plate.bridge.line or nil
end

local function PlateLit(plate, on)
	plate.lit = on and true or nil
	Paint(plate)
	LayChip(plate)
end

-- the hover line's rect (UI units): the chip's width, from its bottom to
-- the line's top (a layer's secure overlay goes over it); nil while the
-- line does not show
local function PlateLineRect(plate)
	local chip, line = plate.chip, plate.chip.line2
	if not (chip:IsShown() and line:IsShown()) then
		return nil
	end
	local l, b, r = Safe.ScreenRect(chip)
	local lh = Num(line:GetStringHeight())
	if not (l and lh) then
		return nil
	end
	local us = Num(UIParent:GetEffectiveScale()) or 1
	if us <= 0 then
		us = 1
	end
	return l / us, b / us, (r - l) / us, lh + CHIP_PAD_Y + 1
end

local Release   -- below

local function PlateRelease(plate)
	Release(plate)
end

local PlateLeave, PlateDown, PlateUp, PlateWheel   -- below

local function NewPlateFrame()
	if madeCount >= MAX_PLATES then
		return nil
	end
	madeCount = madeCount + 1
	local plate = CreateFrame("Frame", nil, UIParent)
	plate:Hide()
	plate:SetFrameStrata("FULLSCREEN")
	plate:EnableMouse(true)
	plate:EnableMouseWheel(true)
	plate.fill = plate:CreateTexture(nil, "BACKGROUND")
	plate.fill:SetAllPoints(plate)
	plate.edges = W.Edges(plate, "trim", "BORDER")
	local chip = W.Panel(plate, { alpha = 0.8 })
	chip:EnableMouse(false)
	chip:SetPoint("CENTER", plate, "CENTER", 0, 0)
	chip.label = W.Text(chip, "GameFontHighlight", nil, "text")
	chip.label:SetJustifyH("CENTER")
	chip.label:SetWordWrap(false)
	chip.label:SetPoint("TOP", chip, "TOP", 0, -CHIP_PAD_Y)
	chip.line2 = W.Text(chip, "GameFontHighlight", nil, "text")
	chip.line2:SetJustifyH("CENTER")
	chip.line2:SetWordWrap(false)
	chip.line2:SetPoint("TOP", chip.label, "BOTTOM", 0, -1)
	chip.line2:Hide()
	plate.chip = chip
	plate.rect = { l = 0, b = 0, w = 0, h = 0, plate = plate }
	plate.Lay, plate.SetLabel, plate.SetBridge, plate.SetLit = PlateLay, PlateLabel, PlateBridge, PlateLit
	plate.LineRect, plate.Release = PlateLineRect, PlateRelease
	Perf.SetScript(plate, "OnEnter", PlateEnter)
	Perf.SetScript(plate, "OnLeave", PlateLeave)
	Perf.SetScript(plate, "OnMouseDown", PlateDown)
	Perf.SetScript(plate, "OnMouseUp", PlateUp)
	Perf.SetScript(plate, "OnMouseWheel", PlateWheel)
	return plate
end

local function Acquire()
	local plate = table.remove(pool)
	if not plate then
		plate = NewPlateFrame()
		if not plate then
			return nil
		end
	end
	serial = serial + 1
	plate.serial = serial
	plate.inUse = true
	active[#active + 1] = plate
	return plate
end

Release = function(plate)
	if not plate.inUse then
		return
	end
	plate.inUse = nil
	for i = #active, 1, -1 do
		if active[i] == plate then
			table.remove(active, i)
			break
		end
	end
	if plate.entry and plateOf[plate.entry] == plate then
		plateOf[plate.entry] = nil
	end
	MelloUI.Anim:Stop(plate, "alpha")
	plate:Hide()
	plate:SetAlpha(1)
	if drag.plate == plate then
		drag.plate, drag.entry, drag.started = nil, nil, nil
	end
	E:TooltipHide(plate)
	plate.entry, plate.frame, plate.key, plate.group, plate.kind = nil, nil, nil, nil, nil
	plate.hover, plate.lit, plate.target, plate.changed, plate.hidden, plate.locked = nil, nil, nil, nil, nil, nil
	plate.bridge, plate.line, plate.label, plate.dialog, plate.faded = nil, nil, nil, nil, nil
	plate.detent, plate.landed = nil, nil
	local r = plate.rect
	r.l, r.b, r.w, r.h = 0, 0, 0, 0
	pool[#pool + 1] = plate
end

-- a layer's plate (the bridge's)
function E.NewPlate()
	local plate = Acquire()
	if not plate then
		return nil
	end
	plate.kind = "bridge"
	Paint(plate)
	return plate
end

--------------------------------------------------------------------------------
-- The pieces around the plates: the scrim, the veil, the guides and grid,
-- the outer glow, the readout
--------------------------------------------------------------------------------

local scrim, veil, guides, glow, readout
local guideLevel = LEVEL0   -- the guides' level: over the highest plate on FULLSCREEN (Rank)

local function MakeScrim()
	-- the world dimmed, never the UI: the lowest strata, no mouse
	scrim = CreateFrame("Frame", nil, UIParent)
	scrim:Hide()
	scrim:SetFrameStrata("BACKGROUND")
	scrim:SetFrameLevel(0)
	scrim:SetAllPoints(UIParent)
	scrim:EnableMouse(false)
	scrim.tex = W.Solid(scrim, "BACKGROUND", "innerPanel", 0.25)
	scrim.tex:SetAllPoints(scrim)
end

local WheelDrag   -- below

local VeilWheel = Shared("OnMouseWheel on Edit Layout's veil", function(_, delta)
	WheelDrag(delta)
end, "script")

local function MakeVeil()
	veil = CreateFrame("Frame", nil, UIParent)
	veil:Hide()
	veil:SetAllPoints(UIParent)
	veil.tex = W.Solid(veil, "BACKGROUND", "innerPanel", 0.6)
	veil.tex:SetAllPoints(veil)
	Perf.SetScript(veil, "OnMouseWheel", VeilWheel)
end

-- the rest of the screen darkens while one moves (at its strata, under
-- everything drawn there); it catches the wheel, so an element scaled down
-- under the cursor can be scaled up again
local function VeilOn(strata)
	if not veil then
		MakeVeil()
	end
	veil:SetFrameStrata(strata or "MEDIUM")
	veil:SetFrameLevel(0)
	veil:EnableMouse(true)
	veil:EnableMouseWheel(true)
	veil:Show()
end

local function VeilOff()
	if veil then
		veil:EnableMouseWheel(false)
		veil:EnableMouse(false)
		veil:Hide()
	end
end

-- the lit golds (the guides, the centre lines): computed from the palette,
-- painted again on 'palette'
local function PaintGuides()
	if not guides then
		return
	end
	local r, g, b = Lit("selectedTrim")
	guides.x:SetColorTexture(r, g, b, 0.9)
	guides.y:SetColorTexture(r, g, b, 0.9)
	guides.cx:SetColorTexture(r, g, b, 0.35)
	guides.cy:SetColorTexture(r, g, b, 0.35)
end

-- a line the full screen long, 1 physical pixel wide, at `at`
local function LayLine(tex, vertical, at)
	tex:ClearAllPoints()
	if vertical then
		tex:SetSize(1 / perUnit, screenH)
		tex:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", at, 0)
	else
		tex:SetSize(screenW, 1 / perUnit)
		tex:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, at)
	end
end

local function MakeGuides()
	guides = CreateFrame("Frame", nil, UIParent)
	guides:Hide()
	guides:SetFrameStrata("FULLSCREEN")
	guides:SetFrameLevel(guideLevel)   -- (made at the first drag: over the plates ranked before it)
	guides:SetAllPoints(UIParent)
	guides:EnableMouse(false)
	guides.x = guides:CreateTexture(nil, "OVERLAY")
	guides.y = guides:CreateTexture(nil, "OVERLAY")
	guides.cx = guides:CreateTexture(nil, "ARTWORK")
	guides.cy = guides:CreateTexture(nil, "ARTWORK")
	guides.axis = W.Solid(guides, "ARTWORK", "selectedTrim", 0.5)
	guides.grid = {}
	guides.gridW, guides.gridH = 0, 0
	PaintGuides()
end

-- the grid (grid mode): a line every GRID units out from the screen's
-- centre, in the text colour, faint; drawn again when the screen's size in
-- units changed since
local function DrawGrid()
	local pool2 = guides.grid
	if guides.gridW == screenW and guides.gridH == screenH and guides.gridPer == perUnit then
		return
	end
	guides.gridW, guides.gridH, guides.gridPer = screenW, screenH, perUnit
	local used = 0
	local function Line(vertical, at)
		used = used + 1
		local tex = pool2[used]
		if not tex then
			tex = W.Solid(guides, "BORDER", "text", 0.08)
			pool2[used] = tex
		end
		LayLine(tex, vertical, at)
	end
	local grid = Snap.GRID
	local cx, cy = screenW / 2, screenH / 2
	local n = 0
	while n * grid <= cx do
		Line(true, cx + n * grid)
		if n > 0 then
			Line(true, cx - n * grid)
		end
		n = n + 1
	end
	n = 0
	while n * grid <= cy do
		Line(false, cy + n * grid)
		if n > 0 then
			Line(false, cy - n * grid)
		end
		n = n + 1
	end
	for i = used + 1, #pool2 do
		pool2[i]:Hide()
	end
	guides.gridUsed = used
end

local function ShowGrid(on)
	local list = guides.grid
	if on then
		DrawGrid()
	end
	for i = 1, (guides.gridUsed or 0) do
		list[i]:SetShown(on)
	end
end

local function GuidesOn(gridMode)
	if not guides then
		MakeGuides()
	end
	LayLine(guides.cx, true, screenW / 2)
	LayLine(guides.cy, false, screenH / 2)
	guides.x:Hide()
	guides.y:Hide()
	guides.axis:Hide()
	ShowGrid(gridMode)
	guides:Show()
end

local function GuidesOff()
	if guides then
		guides:Hide()
	end
end

-- the outer glow: four additive bands out from the PLATE's edges, fading
-- away from it, one level under it (never on the element)
local function PaintGlow()
	if not glow then
		return
	end
	local r, g, b = Lit("selectedTrim")
	local inner, outer = glow.inner, glow.outer
	inner.r, inner.g, inner.b, inner.a = r, g, b, GLOW_ALPHA
	outer.r, outer.g, outer.b, outer.a = r, g, b, 0
	for i = 1, 4 do
		local band = glow.bands[i]
		if band.fromInner then
			band.tex:SetGradient(band.orientation, inner, outer)
		else
			band.tex:SetGradient(band.orientation, outer, inner)
		end
	end
end

local function MakeGlow()
	glow = CreateFrame("Frame", nil, UIParent)
	glow:Hide()
	glow:EnableMouse(false)
	glow.bands = {}
	local r, g, b = Lit("selectedTrim")
	glow.inner, glow.outer = CreateColor(r, g, b, GLOW_ALPHA), CreateColor(r, g, b, 0)
	for i = 1, 4 do
		local tex = glow:CreateTexture(nil, "BACKGROUND")
		tex:SetTexture(WHITE)
		tex:SetBlendMode("ADD")
		glow.bands[i] = { tex = tex, orientation = (i <= 2) and "VERTICAL" or "HORIZONTAL", fromInner = (i == 1 or i == 4) }
	end
	PaintGlow()
end

local function GlowOn(plate)
	if not glow then
		MakeGlow()
	end
	glow:SetFrameStrata(plate:GetFrameStrata())
	glow:SetFrameLevel(max((plate:GetFrameLevel() or 1) - 1, 0))
	-- (the frame round the plate, the bands on its edges: on our own plate)
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", plate, "TOPLEFT", -GLOW, GLOW)
	glow:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", GLOW, -GLOW)
	local bands = glow.bands
	-- top upward, bottom downward, left leftward, right rightward
	local t, bo, le, ri = bands[1].tex, bands[2].tex, bands[3].tex, bands[4].tex
	t:ClearAllPoints()
	t:SetPoint("BOTTOMLEFT", plate, "TOPLEFT", 0, 0)
	t:SetPoint("TOPRIGHT", plate, "TOPRIGHT", 0, GLOW)
	bo:ClearAllPoints()
	bo:SetPoint("TOPLEFT", plate, "BOTTOMLEFT", 0, 0)
	bo:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", 0, -GLOW)
	le:ClearAllPoints()
	le:SetPoint("TOPRIGHT", plate, "TOPLEFT", 0, 0)
	le:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", -GLOW, 0)
	ri:ClearAllPoints()
	ri:SetPoint("TOPLEFT", plate, "TOPRIGHT", 0, 0)
	ri:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", GLOW, 0)
	glow:Show()
end

local function GlowOff()
	if glow then
		glow:Hide()
	end
end

-- a kit-dressed window's outer rail lit while it moves: our own rep's art
-- drawn additively in the lit gold, put back as it was after
local railLit = { n = 0, tex = {}, blend = {}, r = {}, g = {}, b = {}, a = {} }

local function RailOn(frame)
	local Kit = MelloUI.Kit
	local known = Kit and Kit.shells and Kit.shells[frame]
	local outer = known and known.outer
	local art = type(outer) == "table" and outer.skin and outer.skin.art
	if type(art) ~= "table" then
		return
	end
	local r, g, b = Lit("selectedTrim")
	local L = railLit
	for i = 1, #art do
		local tex = art[i]
		L.n = L.n + 1
		local n = L.n
		L.tex[n], L.blend[n] = tex, tex:GetBlendMode()
		L.r[n], L.g[n], L.b[n], L.a[n] = tex:GetVertexColor()
		tex:SetBlendMode("ADD")
		tex:SetVertexColor(r, g, b)
	end
end

local function RailOff()
	local L = railLit
	for i = 1, L.n do
		local tex = L.tex[i]
		tex:SetBlendMode(L.blend[i] or "BLEND")
		tex:SetVertexColor(L.r[i], L.g[i], L.b[i], L.a[i])
		L.tex[i] = nil
	end
	L.n = 0
end

-- The size and place readout (Unlock the Windows' SizeTip): above the
-- element, else below it, else over its top; the size against its standard
-- size, its centre from the screen's centre while it moves, and how to get
-- back. On the tooltip strata, anchored to the screen.
local function MakeReadout()
	readout = CreateFrame("Frame", nil, UIParent)
	readout:Hide()
	readout:SetFrameStrata("TOOLTIP")
	readout:SetClampedToScreen(true)
	readout:EnableMouse(false)
	readout.fill = W.Solid(readout, "BACKGROUND", "mainWindow", 0.94)
	readout.fill:SetAllPoints(readout)
	readout.edges = W.Edges(readout, "trim", "BORDER")
	readout.value = W.Text(readout, "GameFontNormalLarge", nil, "selectedTrim")
	readout.value:SetJustifyH("CENTER")
	readout.value:SetPoint("TOP", readout, "TOP", 0, -7)
	MelloUI.Kit:TitleFont(readout.value, true)
	readout.pos = W.Text(readout, "GameFontHighlight", nil, "text")
	readout.pos:SetJustifyH("CENTER")
	readout.pos:SetPoint("TOP", readout.value, "BOTTOM", 0, -3)
	readout.hint = W.Text(readout, "GameFontHighlight", nil, "text")
	readout.hint:SetJustifyH("CENTER")
	readout.shown = { percent = false, x = false, y = false, hint = false }
end

local function ReadoutPlace(l, b, w, h)
	local th = Num(readout:GetHeight()) or 40
	local cx, top = l + w / 2, b + h
	readout:ClearAllPoints()
	if top + 8 + th <= screenH then
		readout:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, top + 8)
	elseif b - 8 - th >= 0 then
		readout:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, b - 8)
	else
		readout:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, top - 30)
	end
end

local readoutTimer

local ReadoutFade = function()
	readoutTimer = nil
	if readout and readout:IsShown() then
		MelloUI.Anim:FadeOut(readout, FADE)
	end
end

-- the readout for an entry at l, b, w, h; `pos`: with its X / Y line; the
-- texts set only when they change (a drag frame makes no string otherwise)
local function ReadoutShow(entry, l, b, w, h, pos, moving)
	local scale = FrameScale(entry)
	if not scale then
		return
	end
	if not readout then
		MakeReadout()
	end
	if readoutTimer then
		readoutTimer:Cancel()
		readoutTimer = nil
	end
	local percent = floor(scale / Base(entry) * 100 + 0.5)
	local x = pos and floor(l + w / 2 - screenW / 2 + 0.5) or false
	local y = pos and floor(b + h / 2 - screenH / 2 + 0.5) or false
	local hint = percent == 100 and TEXT.standard or (moving and TEXT.wheelBack) or TEXT.resetHint
	local seen = readout.shown
	local changed = seen.percent ~= percent or seen.x ~= x or seen.y ~= y or seen.hint ~= hint
	if changed then
		seen.percent, seen.x, seen.y, seen.hint = percent, x, y, hint
		readout.value:SetText(string.format(TEXT.size, percent))
		readout.pos:SetShown(pos and true or false)
		if pos then
			readout.pos:SetText("X " .. Signed(x) .. "  Y " .. Signed(y))
		end
		readout.hint:ClearAllPoints()
		readout.hint:SetPoint("TOP", pos and readout.pos or readout.value, "BOTTOM", 0, -3)
		readout.hint:SetText(hint)
		local edge = percent == 100 and "selectedTrim" or "trim"
		for i = 1, 4 do
			W.Paint(readout.edges[i], edge, "fill", 1)
		end
		local tw = max(Num(readout.value:GetStringWidth()) or 0, Num(readout.hint:GetStringWidth()) or 0,
			pos and Num(readout.pos:GetStringWidth()) or 0)
		local th = (Num(readout.value:GetStringHeight()) or 16) + 3 + (Num(readout.hint:GetStringHeight()) or 12)
			+ (pos and (3 + (Num(readout.pos:GetStringHeight()) or 12)) or 0)
		readout:SetSize(ceil(tw) + 24, ceil(th) + 16)
	end
	ReadoutPlace(l, b, w, h)
	if not readout:IsShown() or MelloUI.Anim:IsRunning(readout, "alpha") then
		MelloUI.Anim:Stop(readout, "alpha")
		readout:SetAlpha(1)
		readout:Show()
	end
end

-- it goes after `delay` s (then fades; with Reduce Motion it just goes)
local function ReadoutRelease(delay)
	if not (readout and readout:IsShown()) then
		return
	end
	if readoutTimer then
		readoutTimer:Cancel()
		readoutTimer = nil
	end
	if delay and delay > 0 then
		readoutTimer = C_Timer.NewTimer(delay, ReadoutFade)
	else
		ReadoutFade()
	end
end

local function ReadoutOff()
	if readoutTimer then
		readoutTimer:Cancel()
		readoutTimer = nil
	end
	if readout then
		MelloUI.Anim:Stop(readout, "alpha")
		readout:Hide()
	end
end

--------------------------------------------------------------------------------
-- Moving and sizing one element (pending: the session keeps it)
--------------------------------------------------------------------------------

-- its plate laid again from where it is now
local function Relay(entry)
	local plate = plateOf[entry]
	if not plate then
		return nil
	end
	local l, b, w, h = MelloUI:EntryRect(entry)
	if l then
		plate:Lay(l, b, w, h)
	end
	return l, b, w, h
end

-- sized to `scale` about (px, py), UI units; the new rect
local function ScaleAbout(entry, scale, px, py)
	local l, b, w, h = MelloUI:EntryRect(entry)
	local s0 = FrameScale(entry)
	if not (l and s0) then
		return nil
	end
	if not MelloUI:ScaleEntry(entry, scale) then
		return nil
	end
	local k = scale / s0
	local nl, nb = Snap.Round(px - (px - l) * k, perUnit), Snap.Round(py - (py - b) * k, perUnit)
	MelloUI:MoveEntry(entry, nl, nb)
	return nl, nb, w * k, h * k
end

-- the next size for a wheel notch, in whole percent of the standard size:
-- a multiple of the step (100 % never stepped over), and a wheel still
-- spinning right after it landed on 100 % held there a moment (the detent).
-- nil: the notch was held.
local function Step(plate, percent, delta, step)
	local now = GetTime()
	if plate.detent and now < plate.detent and (delta > 0) == plate.detentUp then
		return nil
	end
	local p = floor(percent + 0.5)
	local nextP
	if delta > 0 then
		nextP = floor(p / step) * step + step
	else
		nextP = ceil(p / step) * step - step
	end
	plate.detent, plate.landed = nil, nil
	if nextP == 100 and p ~= 100 then
		plate.detent, plate.detentUp, plate.landed = now + DETENT, delta > 0, true
	end
	return nextP
end

-- the scale a notch gives, or nil (held, or no change)
local function NotchScale(plate, entry, delta)
	local current = FrameScale(entry)
	if not current then
		return nil
	end
	local base = Base(entry)
	local percent = Step(plate, current / base * 100, delta, IsShiftKeyDown() and FINE_STEP or STEP)
	if not percent then
		return nil
	end
	local lo, hi = Range(entry)
	local scale = max(lo, min(hi, base * percent / 100))
	if abs(scale - current) < 0.001 then
		plate.landed = nil
		return nil
	end
	return scale
end

local function Movable(plate)
	return plate and plate.kind ~= "bridge" and plate.entry ~= nil and not plate.locked
end

-- (a session that ended under a drag -- Core abandons it for a profile or
-- the installer -- takes nothing more)
local function Live()
	local LS = Session()
	return LS ~= nil and LS.Active() and true or false
end

local function Touch(entry)
	if not Live() then
		return
	end
	local LS = Session()
	local ok, err = pcall(LS.Touch, entry)
	if not ok then
		Report(err)
	end
end

-- the element's place and size now made its pending one, hung by its own
-- anchor again
local function Pend(entry, scale)
	if not Live() then
		return
	end
	local LS = Session()
	local ok, err = pcall(LS.Set, entry, scale)
	if not ok then
		Report(err)
	end
	ok, err = pcall(LS.Hang, entry)
	if not ok then
		Report(err)
	end
end

-- a plate's pending mark: what the bar counts, so a place moved back
-- exactly wears none (Core's LayoutSession.Differs, the count's own rule;
-- Holds, any touched element, where Core has none)
local function Marked(entry)
	local LS = Session()
	local fn = LS and (LS.Differs or LS.Holds)
	if not fn then
		return nil
	end
	local ok, on = pcall(fn, entry)
	return ok and on and true or nil
end

local function Changed(entry)
	local plate = plateOf[entry]
	if plate then
		plate.changed = Marked(entry)
		Paint(plate)
	end
	E:BoxFollow(entry)
	E:Refresh()
end

-- the wheel over a plate (not dragging): about its anchor, else its centre
local function WheelHover(plate, delta)
	local entry = plate.entry
	if not Movable(plate) or entry.resize == false then
		return
	end
	local scale = NotchScale(plate, entry, delta)
	if not scale then
		return
	end
	local l, b, w, h = MelloUI:EntryRect(entry)
	if not l then
		return
	end
	Touch(entry)
	local px, py = Pivot(entry, l, b, w, h)
	if not ScaleAbout(entry, scale, px, py) then
		return
	end
	Pend(entry, ScaleArg(entry, scale))
	l, b, w, h = Relay(entry)
	if l then
		ReadoutShow(entry, l, b, w, h, false, true)
	end
	if plate.landed then
		MelloUI:PlayUISound("tick")
	end
	plate.landed = nil
	LayChip(plate)
	Changed(entry)
end

function P.Fraction(entry)
	local scale = FrameScale(entry)
	return scale and scale / Base(entry) or 1
end

-- the box's Size: a fraction of the standard size, about its anchor or centre
function P.ScaleTo(entry, fraction)
	local lo, hi = Range(entry)
	local scale = max(lo, min(hi, Base(entry) * fraction))
	local current = FrameScale(entry)
	if not current or abs(scale - current) < 0.0005 or entry.resize == false or P.LockedReason(entry) then
		return
	end
	local l, b, w, h = MelloUI:EntryRect(entry)
	if not l then
		return
	end
	Touch(entry)
	local px, py = Pivot(entry, l, b, w, h)
	if ScaleAbout(entry, scale, px, py) then
		Pend(entry, ScaleArg(entry, scale))
		Relay(entry)
		Changed(entry)
	end
end

-- its centre from the screen's centre, whole units
function P.CentreOffset(entry)
	local l, b, w, h = MelloUI:EntryRect(entry)
	if not l then
		return nil
	end
	return floor(l + w / 2 - screenW / 2 + 0.5), floor(b + h / 2 - screenH / 2 + 0.5)
end

-- moved so its centre lands on x, y (from the screen's centre), kept on the
-- screen, on the pixel grid, no snapping
local function MoveTo(entry, l, b, w, h)
	local eL, eB, eR, eT = Extents(entry, l, b, w, h)
	l, b = Snap.Clamp(l, b, w, h, eL, eB, eR, eT, screenW, screenH)
	l, b = Snap.Round(l, perUnit), Snap.Round(b, perUnit)
	Touch(entry)
	if MelloUI:MoveEntry(entry, l, b) then
		Pend(entry, nil)
	end
	return Relay(entry)
end

-- (x or y nil: that axis keeps its place as it is, not its field's whole
-- units)
function P.MoveCentreTo(entry, x, y)
	if P.LockedReason(entry) then
		return
	end
	local l, b, w, h = MelloUI:EntryRect(entry)
	if not l then
		return
	end
	MoveTo(entry, x and (screenW / 2 + x - w / 2) or l, y and (screenH / 2 + y - h / 2) or b, w, h)
	Changed(entry)
end

--------------------------------------------------------------------------------
-- The drag (SPEC 2.6, 2.7)
--------------------------------------------------------------------------------

local function SetDriver(fn)
	if not driver then
		driver = CreateFrame("Frame", nil, UIParent)
	end
	Perf.SetScript(driver, "OnUpdate", fn)
end

-- the snap mode for this element: "element" (its named target, else the
-- nearest), "screen", "grid" or "off"
local function ModeFor(entry)
	if not E:SnapOn() then
		return "off", nil
	end
	local t = E:SnapTarget(entry.key)
	if t == "off" or t == "screen" or t == "grid" then
		return t, nil
	end
	return "element", t
end

local function Unlight(plate)
	if plate and plate.target then
		plate.target = nil
		Paint(plate)
	end
end

-- the candidate rects, read once at the press: every other shown plate,
-- less the `with` frames and whatever hangs on the dragged element (their
-- plates fade to 0 for the drag)
local function Candidates(plate, entry)
	local frame = entry.frame
	local with = WithOf(entry)
	local cands, hangers = drag.cands, drag.hangers
	local nc, nh = 0, 0
	drag.target = nil
	for i = 1, #active do
		local p = active[i]
		if p ~= plate and p:IsShown() then
			local f = p.frame
			if f ~= nil and (IsWith(f, with) or HangsOn(f, frame)) then
				nh = nh + 1
				hangers[nh] = p
				p.faded = true
				MelloUI.Anim:Stop(p, "alpha")   -- (a plate still fading in)
				p:SetAlpha(0)
			else
				nc = nc + 1
				cands[nc] = p.rect
				if drag.targetKey ~= nil and p.key == drag.targetKey and p.kind ~= "bridge" then
					drag.target = p.rect
				end
			end
		end
	end
	for i = nc + 1, #cands do
		cands[i] = nil
	end
	drag.nc, drag.nh = nc, nh
end

local function DropRelease()
	for i = 1, drag.nh do
		local p = drag.hangers[i]
		drag.hangers[i] = nil
		p.faded = nil
		p:SetAlpha(1)
	end
	drag.nh = 0
	for i = 1, drag.nc do
		drag.cands[i] = nil
	end
	drag.nc = 0
end

local DragUpdate, PressWatch   -- below

local function StartDrag()
	local plate, entry = drag.plate, drag.entry
	local l, b, w, h = MelloUI:EntryRect(entry)
	if not l then
		drag.plate, drag.entry = nil, nil
		SetDriver(nil)
		return
	end
	E:CloseBox()
	E:TooltipHide()
	P.KeyUp()
	Touch(entry)
	entry.moving = "layout"
	drag.started = true
	drag.l0, drag.b0, drag.w, drag.h = l, b, w, h
	drag.l, drag.b = l, b
	drag.gx, drag.gy = drag.px - l, drag.py - b
	drag.lock, drag.heldX, drag.heldY, drag.lit = nil, nil, nil, nil
	drag.scaled, drag.scale = nil, nil
	drag.mode, drag.targetKey = ModeFor(entry)
	drag.eL, drag.eB, drag.eR, drag.eT = Extents(entry, l, b, w, h)
	Candidates(plate, entry)
	local ok, strata = pcall(entry.frame.GetFrameStrata, entry.frame)
	VeilOn(ok and not Secret(strata) and strata or nil)
	GuidesOn(drag.mode == "grid")
	GlowOn(plate)
	RailOn(entry.frame)
	Paint(plate)
	ReadoutShow(entry, l, b, w, h, true, true)
	SetDriver(DragUpdate)
end

-- one frame of the drag: the cursor, Shift's axis, the snap, the screen, the
-- pixel grid, then the element and its plate moved; the guides laid
DragUpdate = function()
	if not IsMouseButtonDown("LeftButton") then
		P.EndDrag()
		return
	end
	local entry, plate = drag.entry, drag.plate
	local cx, cy = Cursor()
	local w, h = drag.w, drag.h
	local l, b = cx - drag.gx, cy - drag.gy
	-- Shift: the dominant axis once it moved far enough; the other kept
	if IsShiftKeyDown() then
		if not drag.lock then
			drag.lock = Snap.Lock(l - drag.l0, b - drag.b0, Snap.Units(Snap.AXIS_LOCK_PX, perUnit))
		end
	else
		drag.lock = nil
	end
	local lock = drag.lock
	if lock == "x" then
		b = drag.b0
	elseif lock == "y" then
		l = drag.l0
	end
	-- the snap (not with Alt; not on the kept axis)
	local lineX, lineY, rankX, rankY, o = nil, nil, nil, nil, nil
	local mode = drag.mode
	if mode ~= "off" and not IsAltKeyDown() then
		local thrIn, thrOut = Snap.Units(Snap.SNAP_PX, perUnit), Snap.Units(Snap.RELEASE_PX, perUnit)
		if mode == "element" then
			o = drag.target
			if not o then
				local i = Snap.Nearest(drag.cands, drag.nc, l, b, w, h)
				o = i and drag.cands[i] or nil
			end
		end
		local grid = mode == "grid"
		local d
		-- (0.19.9) the bar's Gap between elements snapped side by side
		local gap = o and E.SnapGap and Snap.Units(E:SnapGap(), perUnit) or 0
		if lock ~= "y" then
			if o then
				d, lineX, rankX = Snap.Axis(l, l + w / 2, l + w, o.l, o.l + o.w / 2, o.l + o.w, screenW, false,
					drag.heldX, thrIn, thrOut, gap)
			else
				d, lineX, rankX = Snap.Axis(l, l + w / 2, l + w, nil, nil, nil, screenW, grid, drag.heldX, thrIn, thrOut)
			end
			l = l + d
		end
		if lock ~= "x" then
			if o then
				d, lineY, rankY = Snap.Axis(b, b + h / 2, b + h, o.b, o.b + o.h / 2, o.b + o.h, screenH, false,
					drag.heldY, thrIn, thrOut, gap)
			else
				d, lineY, rankY = Snap.Axis(b, b + h / 2, b + h, nil, nil, nil, screenH, grid, drag.heldY, thrIn, thrOut)
			end
			b = b + d
		end
	end
	drag.heldX, drag.heldY = lineX, lineY
	-- on the screen with what moves with it, on the pixel grid
	l, b = Snap.Clamp(l, b, w, h, drag.eL, drag.eB, drag.eR, drag.eT, screenW, screenH)
	l, b = Snap.Round(l, perUnit), Snap.Round(b, perUnit)
	if l ~= drag.l or b ~= drag.b then
		if MelloUI:MoveEntry(entry, l, b) then
			drag.l, drag.b = l, b
			plate:Lay(l, b, w, h)
		end
	end
	-- at most two guide lines, and the target's edge lit
	local gx, gy = guides.x, guides.y
	if lineX then
		LayLine(gx, true, lineX)
		gx:Show()
	else
		gx:Hide()
	end
	if lineY then
		LayLine(gy, false, lineY)
		gy:Show()
	else
		gy:Hide()
	end
	local target = nil
	if o and ((rankX and rankX <= 1) or (rankY and rankY <= 1)) then
		target = o.plate
	end
	if target ~= drag.lit then
		Unlight(drag.lit)
		drag.lit = target
		if target then
			target.target = true
			Paint(target)
		end
	end
	local axis = guides.axis
	if lock then
		LayLine(axis, lock == "y", lock == "y" and (drag.l0 + w / 2) or (drag.b0 + h / 2))
		axis:Show()
	else
		axis:Hide()
	end
	ReadoutShow(entry, drag.l, drag.b, w, h, true, true)
end

-- a press that has not moved far enough yet
PressWatch = function()
	if not IsMouseButtonDown("LeftButton") then
		drag.plate, drag.entry = nil, nil
		SetDriver(nil)
		return
	end
	local x, y = Cursor()
	local dx, dy = x - drag.px, y - drag.py
	local reach = DRAG_PX / perUnit
	if dx * dx + dy * dy >= reach * reach then
		StartDrag()
	end
end

-- the wheel while dragging: about the cursor (the point under it stays)
WheelDrag = function(delta)
	local plate, entry = drag.plate, drag.entry
	if not (drag.started and entry) or entry.resize == false then
		return
	end
	local scale = NotchScale(plate, entry, delta)
	if not scale then
		return
	end
	local cx, cy = Cursor()
	local s0 = FrameScale(entry)
	if not MelloUI:ScaleEntry(entry, scale) then
		return
	end
	local k = scale / s0
	drag.gx, drag.gy = drag.gx * k, drag.gy * k
	drag.w, drag.h = drag.w * k, drag.h * k
	drag.l, drag.b = Snap.Round(cx - drag.gx, perUnit), Snap.Round(cy - drag.gy, perUnit)
	MelloUI:MoveEntry(entry, drag.l, drag.b)
	plate:Lay(drag.l, drag.b, drag.w, drag.h)
	drag.scaled, drag.scale = true, scale
	ReadoutShow(entry, drag.l, drag.b, drag.w, drag.h, true, true)
	if plate.landed then
		MelloUI:PlayUISound("tick")
	end
	plate.landed = nil
end

-- the drop: where it is now becomes its pending place (and the size, when
-- the wheel changed it in this drag), hung by its own anchor again
local function Drop()
	local plate, entry = drag.plate, drag.entry
	SetDriver(nil)
	drag.plate, drag.entry = nil, nil
	if not drag.started then
		return
	end
	drag.started = nil
	-- (the size only when the wheel changed it in this drag; false: none kept)
	local scale = nil
	if drag.scaled then
		scale = ScaleArg(entry, drag.scale)
	end
	Pend(entry, scale)
	entry.moving = nil
	VeilOff()
	GuidesOff()
	GlowOff()
	RailOff()
	Unlight(drag.lit)
	drag.lit = nil
	DropRelease()
	local l, b, w, h = Relay(entry)
	if l then
		ReadoutShow(entry, l, b, w, h, true, false)
	end
	ReadoutRelease(HOLD)
	if plate then
		Paint(plate)
	end
	Changed(entry)
	-- (every plate again: what hung on it moved with it)
	drag.syncAfter = nil
	P.SyncSoon()
end

function P.Dragging()
	return drag.started and drag.entry or nil
end

-- a drag ends where it is (a pause, the element hidden, the mouse let go):
-- no last snap
function P.EndDrag()
	if drag.started then
		Drop()
	elseif drag.plate then
		drag.plate, drag.entry = nil, nil
		SetDriver(nil)
	end
end

--------------------------------------------------------------------------------
-- The plates' handlers (one set for every plate)
--------------------------------------------------------------------------------

-- the tooltip's lines for a plate
local function TipFor(plate)
	if plate.kind == "bridge" then
		local b = plate.bridge
		return plate.label, (b and b.tip) or TEXT.gameOwned, nil
	end
	local entry = plate.entry
	local reason = plate.locked and P.LockedReason(entry)
	if reason then
		return plate.label, reason, nil
	end
	local r = plate.rect
	local scale = FrameScale(entry)
	local line = nil
	if scale then
		line = string.format(TEXT.sizeTip, floor(scale / Base(entry) * 100 + 0.5),
			floor(r.l + r.w / 2 - screenW / 2 + 0.5), floor(r.b + r.h / 2 - screenH / 2 + 0.5))
	end
	return plate.label, entry.resize == false and (TEXT.hintNoSize .. " " .. TEXT.sizeOff) or TEXT.hint, line
end

PlateEnter = Shared("OnEnter on Edit Layout's plates", function(plate)
	plate.hover = true
	Paint(plate)
	LayChip(plate)
	local title, body, line = TipFor(plate)
	E:Tooltip(plate, title, body, line)
	if plate.kind == "bridge" then
		local b = plate.bridge
		if b and b.onEnter then
			local ok, err = pcall(b.onEnter, plate)
			if not ok then
				Report(err)
			end
		end
	elseif not drag.started and plate.entry and not plate.hidden then
		local r = plate.rect
		local scale = FrameScale(plate.entry)
		if scale and floor(scale / Base(plate.entry) * 100 + 0.5) ~= 100 then
			ReadoutShow(plate.entry, r.l, r.b, r.w, r.h, false, false)
		end
	end
end, "script")

PlateLeave = Shared("OnLeave on Edit Layout's plates", function(plate)
	plate.hover = nil
	Paint(plate)
	LayChip(plate)
	E:TooltipHide(plate)
	if plate.kind == "bridge" then
		local b = plate.bridge
		if b and b.onLeave then
			local ok, err = pcall(b.onLeave, plate)
			if not ok then
				Report(err)
			end
		end
	elseif not drag.started then
		ReadoutRelease(0)
	end
end, "script")

PlateDown = Shared("OnMouseDown on Edit Layout's plates", function(plate, button)
	if button ~= "LeftButton" or not Movable(plate) or drag.plate then
		return
	end
	P.KeyUp()   -- (a held arrow stops: the press takes the driver)
	drag.plate, drag.entry, drag.started = plate, plate.entry, nil
	drag.px, drag.py = Cursor()
	SetDriver(PressWatch)
end, "script")

function P.RightClick(plate)
	if plate.kind == "bridge" then
		local b = plate.bridge
		if b and b.onRightClick then
			local ok, err = pcall(b.onRightClick, plate)
			if not ok then
				Report(err)
			end
		end
		return
	end
	E:OpenBoxForPlate(plate)
end

PlateUp = Shared("OnMouseUp on Edit Layout's plates", function(plate, button)
	if button == "LeftButton" then
		if drag.plate == plate then
			if drag.started then
				Drop()
			else
				drag.plate, drag.entry = nil, nil
				SetDriver(nil)
				P.Select(plate.entry)
			end
		end
	elseif button == "RightButton" then
		if IsControlKeyDown() then
			if plate.kind == "bridge" then
				-- (nothing to reset here: the tooltip says where it is set)
				local title, body = TipFor(plate)
				W.ShowTooltip(plate, title, body)
			elseif plate.entry and not plate.locked then
				E:ResetEntry(plate.entry)
			end
		else
			P.RightClick(plate)
		end
	end
end, "script")

PlateWheel = Shared("OnMouseWheel on Edit Layout's plates", function(plate, delta)
	if drag.started then
		WheelDrag(delta)
		return
	end
	WheelHover(plate, delta)
end, "script")

--------------------------------------------------------------------------------
-- Selection and the arrow keys (SPEC 2.13)
--------------------------------------------------------------------------------

function P.Selected()
	return selected
end

function P.Select(entry)
	if selected == entry then
		return
	end
	local old = selected and plateOf[selected]
	selected = entry
	if old then
		Paint(old)
	end
	local plate = entry and plateOf[entry]
	if plate then
		Paint(plate)
	end
end

function P.Deselect()
	P.KeyUp()
	P.Select(nil)
end

function P.CanNudge()
	local plate = selected and plateOf[selected]
	return plate ~= nil and plate:IsShown() and Movable(plate) and not drag.started and not drag.plate
end

-- a click on the world (the mouse's focus none, or the game's world frame):
-- no selection, so the arrow keys turn the character again. A click on a
-- plate, the bar, the box, a dropdown's list or a window keeps it.
function P.ClickedElsewhere()
	if selected == nil then
		return
	end
	local focus
	if GetMouseFoci then
		local foci = GetMouseFoci()
		focus = type(foci) == "table" and foci[1] or nil
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	if focus == nil or focus == WorldFrame then
		P.Deselect()
	end
end

local nudge = { key = nil, wait = 0, poll = false }

-- the held arrow still held: no edit box has taken the keyboard (the chat's
-- after Enter, a box field: the key's release then goes to it, never to
-- the key frame), and the key still down where the client answers for it
-- (IsKeyDown, trusted when it said "down" at the press)
local function StillHeld()
	if GetCurrentKeyBoardFocus() ~= nil then
		return false
	end
	if nudge.poll then
		local ok, down = pcall(IsKeyDown, nudge.key)
		if ok and down == false then
			return false
		end
	end
	return true
end

local function Nudge(key)
	local entry = selected
	if not (entry and P.CanNudge()) then
		return false
	end
	local l, b, w, h = MelloUI:EntryRect(entry)
	if not l then
		return false
	end
	local u = Snap.Units(IsShiftKeyDown() and Snap.NUDGE_SHIFT_PX or Snap.NUDGE_PX, perUnit)
	if key == "LEFT" then
		l = l - u
	elseif key == "RIGHT" then
		l = l + u
	elseif key == "UP" then
		b = b + u
	elseif key == "DOWN" then
		b = b - u
	end
	l, b, w, h = MoveTo(entry, l, b, w, h)
	if l then
		ReadoutShow(entry, l, b, w, h, true, false)
		ReadoutRelease(HOLD)
	end
	Changed(entry)
	return true
end

-- a held arrow repeats after REPEAT_DELAY, every REPEAT_EVERY (the driver's
-- OnUpdate only while it is held)
local RepeatUpdate = function(_, elapsed)
	if not StillHeld() then
		P.KeyUp()
		return
	end
	nudge.wait = nudge.wait - (elapsed or 0)
	if nudge.wait > 0 then
		return
	end
	nudge.wait = nudge.wait + Snap.REPEAT_EVERY
	if nudge.wait < 0 then
		nudge.wait = 0   -- (a slow frame: one step, not a burst)
	end
	if not Nudge(nudge.key) then
		P.KeyUp()
	end
end

function P.KeyDown(key)
	if not Nudge(key) then
		return
	end
	local ok, down = pcall(IsKeyDown, key)
	nudge.key, nudge.wait, nudge.poll = key, Snap.REPEAT_DELAY, ok and down == true
	SetDriver(RepeatUpdate)
end

function P.KeyUp(key)
	if nudge.key == nil or (key ~= nil and key ~= nudge.key) then
		return
	end
	nudge.key, nudge.poll = nil, false
	if not drag.plate then
		SetDriver(nil)
	end
end

--------------------------------------------------------------------------------
-- Every plate laid from the registry (SPEC 2.3, 2.4): one per key, none for
-- a "tool", a hidden element's through its placeholder; area-ranked levels
--------------------------------------------------------------------------------

local chosen, chosenShown, keep, shownNow = {}, {}, {}, {}

local function ByArea(a, b)
	if a.area ~= b.area then
		return a.area > b.area
	end
	return a.serial < b.serial
end

local function Rank()
	table.sort(active, ByArea)
	local level, dialog = LEVEL0, DIALOG_MIN
	for i = 1, #active do
		local p = active[i]
		if p.dialog then
			p:SetFrameStrata("FULLSCREEN_DIALOG")
			p:SetFrameLevel(dialog)
			p.chip:SetFrameStrata("FULLSCREEN_DIALOG")
			p.chip:SetFrameLevel(dialog + 1)
			dialog = min(dialog + 2, DIALOG_MAX)
		else
			p:SetFrameStrata("FULLSCREEN")
			p:SetFrameLevel(level)
			p.chip:SetFrameStrata("FULLSCREEN")
			p.chip:SetFrameLevel(level + 1)
			level = level + LEVEL_STEP
		end
	end
	guideLevel = level + 1
	if guides then
		guides:SetFrameLevel(guideLevel)
	end
end

-- an entry the mode may give a plate now: live, no tool, shown or with a
-- placeholder
local function Wanted(entry)
	if entry.group == "tool" or not MelloUI:EntryLive(entry) then
		return false
	end
	local shown = MelloUI:EntryShown(entry) and true or false
	shownNow[entry] = shown
	return shown or entry.placeholder ~= nil
end

local function LayEntry(entry, made)
	local l, b, w, h = MelloUI:EntryRect(entry)
	if not (l and w and h and w > 0 and h > 0) then
		return made
	end
	local plate = plateOf[entry]
	local fresh = false
	if not plate then
		if #pool == 0 and made >= FIRST_BATCH then
			return made, true   -- (the rest on the next frame)
		end
		if #pool == 0 then
			made = made + 1
		end
		plate = Acquire()
		if not plate then
			return made
		end
		plate.kind, plate.entry = "entry", entry
		plateOf[entry] = plate
		fresh = true
	end
	keep[entry] = true
	plate.frame, plate.key, plate.group = entry.frame, entry.key, entry.group or "own"
	plate.hidden = not shownNow[entry]
	plate.locked = P.LockedReason(entry) ~= nil or nil
	plate.changed = Marked(entry)
	local ok, strata = pcall(entry.frame.GetFrameStrata, entry.frame)
	plate.dialog = ok and not Secret(strata) and HIGH_STRATA[strata] or nil
	local label = P.Label(entry)
	plate.label = plate.hidden and string.format(TEXT.hidden, label) or label
	plate.rect.w = -1   -- (its chip laid again)
	plate:Lay(l, b, w, h)
	Paint(plate)
	if not plate:IsShown() then
		if fresh then
			MelloUI.Anim:FadeIn(plate, PLATE_FADE)
		else
			plate:Show()
		end
	end
	if plate.faded and not drag.started then
		plate.faded = nil
		plate:SetAlpha(1)
	end
	return made
end

function P.SyncAll()
	if not E:IsShowing() then
		return
	end
	if drag.started then
		drag.syncAfter = true   -- (never under a drag: its drop syncs)
		return
	end
	ReadScreen()
	local list = MelloUI:MoverEntries()
	wipe(chosen)
	wipe(chosenShown)
	wipe(keep)
	wipe(shownNow)
	-- one plate per key: the first shown of the key, else the first with a
	-- placeholder
	for i = 1, #list do
		local entry = list[i]
		local key = entry.key
		if key ~= nil and Wanted(entry) then
			local shown = shownNow[entry]
			if chosen[key] == nil or (shown and not chosenShown[key]) then
				chosen[key], chosenShown[key] = entry, shown
			end
		end
	end
	local made, later = 0, false
	for i = 1, #list do
		local entry = list[i]
		local key = entry.key
		local wanted
		if key ~= nil then
			wanted = chosen[key] == entry
		else
			wanted = Wanted(entry)
		end
		if wanted and E:Shows(entry.group or "own") then
			local more
			made, more = LayEntry(entry, made)
			later = later or more
		end
	end
	for i = #active, 1, -1 do
		local p = active[i]
		if p.kind == "entry" and not keep[p.entry] then
			if selected == p.entry then
				selected = nil
			end
			Release(p)
		end
	end
	E.EachLayer("Sync")
	Rank()
	E:Refresh()
	if later then
		P.SyncSoon()
	end
end

local SyncKey = function()
	P.SyncAll()
end

function P.SyncSoon()
	MelloUI.Kit:NextFrame(SYNC_KEY, SyncKey)
end

function P.Redraw()
	ReadScreen()
	if guides then
		guides.gridW = -1
	end
end

function P.ShowAll()
	ReadScreen()
	if not scrim then
		MakeScrim()
	end
	scrim:Show()
	P.SyncAll()
end

-- a drag dropped where it is (no last snap), a held arrow let go, every
-- plate and piece away
function P.HideAll()
	P.EndDrag()
	P.KeyUp()
	for i = #active, 1, -1 do
		local p = active[i]
		if p.kind == "entry" then
			Release(p)
		else
			p:Hide()
		end
	end
	VeilOff()
	GuidesOff()
	GlowOff()
	RailOff()
	ReadoutOff()
	if scrim then
		scrim:Hide()
	end
end

function P.Setup()
	MelloUI:On("palette", function()
		PaintGuides()
		PaintGlow()
	end, "Edit Layout movers")
end

-- the topmost shown plate under the cursor (the box's catcher)
function P.PlateAtCursor()
	local x, y = Cursor()
	local best, bestRank = nil, nil
	for i = 1, #active do
		local p = active[i]
		if p:IsShown() and p.l and x >= p.l and x <= p.l + p.w and y >= p.b and y <= p.b + p.h then
			local rank = (p.dialog and 100000 or 0) + (Num(p:GetFrameLevel()) or 0)
			if not best or rank > bestRank then
				best, bestRank = p, rank
			end
		end
	end
	return best
end

-- the box's Snap to: every other shown keyed plate, by name
local function ByLabel(a, b)
	return a.label < b.label
end

function P.SnapChoices(entry, values)
	local n0 = #values
	local seen = {}
	for i = 1, #active do
		local p = active[i]
		local key = p.key
		if p.kind == "entry" and key ~= nil and key ~= entry.key and not seen[key] and p:IsShown() then
			seen[key] = true
			values[#values + 1] = { value = key, label = P.Label(p.entry) }
		end
	end
	local extra = {}
	for i = n0 + 1, #values do
		extra[#extra + 1] = values[i]
	end
	table.sort(extra, ByLabel)
	for i = 1, #extra do
		values[n0 + i] = extra[i]
	end
end

function P.BridgeCount()
	local n = 0
	for i = 1, #active do
		local p = active[i]
		if p.kind == "bridge" and p:IsShown() then
			n = n + 1
		end
	end
	return n
end

-- the dump: every entry, whether it has a plate and why not
function P.Dump(print)
	ReadScreen()
	print("screen %.1f x %.1f units, %.3f px a unit; %d plates made (%d in use)", screenW, screenH, perUnit,
		madeCount, #active)
	local list = MelloUI:MoverEntries()
	for i = 1, #list do
		local entry = list[i]
		local plate = plateOf[entry]
		local why
		if plate then
			local r = plate.rect
			why = string.format("plate %.1f, %.1f  %.1f x %.1f%s%s%s", r.l, r.b, r.w, r.h, plate.hidden and " hidden" or "",
				plate.locked and " locked" or "", plate.dialog and " dialog" or "")
		elseif entry.group == "tool" then
			why = "tool (no plate)"
		elseif not MelloUI:EntryLive(entry) then
			why = "not live"
		elseif not (MelloUI:EntryShown(entry) or entry.placeholder) then
			why = "hidden, no placeholder"
		elseif not E:Shows(entry.group or "own") then
			why = "filtered out"
		elseif not MelloUI:EntryRect(entry) then
			why = "no readable rect (secret or not laid out)"
		else
			why = "no plate (another of its key has it, or the pool is full)"
		end
		print("  %s [%s] %s: %s", P.Label(entry), tostring(entry.key), entry.group or "own", why)
	end
	print("  %d plates of layers shown", P.BridgeCount())
end
