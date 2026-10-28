--------------------------------------------------------------------------------
-- MelloUI - Mouseover Highlight on the party and raid frames and the nameplates (1.2.4; MelloUI.FrameHover)
--
-- The user, 2026-10-25: "mouseover highligh over party unitframes is not there yet, make them"; their pick of
-- MelloUI-BuildData/output/hover_sketch: "B Pixel outline", on "Party + raid frames" -- while the mouse is over a
-- frame, a crisp outline round its own shape (round on the portrait, straight along the plate; a raid cell's own box):
-- white next to the frame, the palette's selected trim outside it. Drawn by the frames' shape system (FX.Outline,
-- FrameFXBold.lua: the bold landings' frame shape, as an outline -- on WoW Forever in the modern look's crisp lines; the
-- user, 2026-10-26: "The mouseover highlighting should also be imported into the forever addon"; a mirrored party
-- frame, Flip Horizontally, the right way round). Group Frames' buttons, its solo frame and the game's
-- party frames (the Portraits look) attach (a post-hook of their OnEnter, OnLeave and OnHide; nothing written on the
-- game's frames); one board for the frame the mouse is over, made on the first hover. (The user, after B in the game:
-- "add the A version with it aswell": its gold lit and a soft glow behind it too -- Light below.) Group Frames'
-- Mouseover Highlight switches it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Safe = MelloUI.Safe
local Text, Num = Safe.Text, Safe.Number
local Perf = MelloUI.Perf:Scope("Mouseover Highlight")
local FX = MelloUI.FrameFX

local Hover = {}
MelloUI.FrameHover = Hover

local attached = setmetatable({}, { __mode = "k" })   -- [frame] = true: hooked
local board   -- the outline's frame (made on the first hover)
local over    -- the frame the mouse is over

local function On()
	local gf = MelloUI:GetModule("GroupFrames")
	return not (gf and gf.db and gf.db.hover == false)
end

-- the palette's selected trim, { r, g, b } (a new table when it changes: the sprites tint again on a new one)
local trim
local function Trim()
	local c = MelloUI.Palette.selectedTrim
	if type(c) ~= "table" or type(c[1]) ~= "number" then
		return nil
	end
	if not (trim and trim[1] == c[1] and trim[2] == c[2] and trim[3] == c[3]) then
		trim = { c[1], c[2], c[3] }
	end
	return trim
end

-- (2026-10-25, the user, after B in the game: "i would also like to add the A version with it aswell to work together
-- with B" -- A of the sketch, "Lit rim: the frame's gold lights up, a soft glow behind it") the frame's own picture
-- once more over it as light (its gold brightens; its dark plate hardly), and behind the frame a soft glow in the
-- trim: the frame halo (MelloUI.FrameHalo: Shade's round glow round the portrait's ring, a hollow soft band round the
-- plate -- a raid cell's box: the band alone -- under the frame, at the strata below its)
local LIT = 0.45                                     -- the picture's light over it
local A = {}   -- the light's parts: lit (texture on the board) and the halo's (FrameHalo.Make's: back, ring, plate, glow, band)

local function MakeLight()
	A.lit = board:CreateTexture(nil, "ARTWORK")
	MelloUI.FrameHalo.Make({ key = "selectedTrim" }, A)
end

-- the light on `frame`, its shape S (FX.Outline's); nil: away
local function Light(frame, S)
	if not S then
		A.lit:Hide()
		A.back:Hide()
		return
	end
	-- the picture as light (a frame wearing one: Unit Frames' M:PlateOf)
	local panel = MelloUI:GetModule("UnitFrames")
	local pic
	if panel and panel.PlateOf then
		local ok, p = pcall(panel.PlateOf, panel, frame)
		pic = ok and p or nil
	end
	local l, b, r, t
	if pic then
		l, b, r, t = FX.Rect(pic)
	end
	if l and FX.CopyLook and FX.CopyLook(A.lit, pic) then
		A.lit:SetBlendMode("ADD")
		A.lit:ClearAllPoints()
		A.lit:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
		A.lit:SetSize(math.max(1, r - l), math.max(1, t - b))
		A.lit:SetAlpha(LIT)
		A.lit:Show()
	else
		A.lit:Hide()
	end
	-- the glow behind: the frame halo round the shape, under the frame's strata
	A.back:SetShown(MelloUI.FrameHalo.Lay(A, frame, S))
end

local function Show(frame)
	if not (On() and FX.Outline) then
		return
	end
	if not board then
		board = CreateFrame("Frame", nil, UIParent)
		board:EnableMouse(false)
		MakeLight()
	end
	-- (over the frame: its strata, above its own parts)
	local okS, strata = pcall(frame.GetFrameStrata, frame)
	local okL, level = pcall(frame.GetFrameLevel, frame)
	strata, level = okS and Text(strata) or "MEDIUM", okL and Num(level) or 1
	board:SetFrameStrata(strata)
	board:SetFrameLevel(level + 20)
	board:Show()
	over = frame
	Light(frame, FX.Outline(board, frame, Trim()))
end

local function Gone(frame)
	if over == frame and board then
		over = nil
		FX.Outline(board, nil)
		Light(nil, nil)
		board:Hide()
	end
end

local OnEnter = Perf.Shared("the mouse over a party or raid frame: its outline", Show, "script")
local OnLeave = Perf.Shared("the mouse off a party or raid frame: its outline away", Gone, "script")

-- a party or raid frame given the highlight (once)
function Hover.Attach(frame)
	if type(frame) ~= "table" or attached[frame] or type(frame.HookScript) ~= "function" then
		return
	end
	attached[frame] = true
	Perf.HookScript(frame, "OnEnter", OnEnter)
	Perf.HookScript(frame, "OnLeave", OnLeave)
	Perf.HookScript(frame, "OnHide", OnLeave)
end

--------------------------------------------------------------------------------
-- The nameplates (the user, the same day: "mouseover highlith is also missing on the nameplates"). The same outline
-- round each plate's rimmed bar -- the rim as Forever's background art draws it on its rect (the game's own on WoW
-- Forever, retail's copy of it there: the art's right 6 and bottom 8 of its 264 x 38 texels empty, about 3 and 4
-- units) -- anchored to the
-- plate's own background: a plate's place is secret to addons and never read. Which plate the mouse is over is the
-- game's own answer for each (UnitIsUnit: secret on an addon-restricted map) handed straight to its alpha
-- (SetAlphaFromBoolean): at UPDATE_MOUSEOVER_UNIT, all of them away once the mouseover unit is gone (UnitExists, plain:
-- read each frame only while a unit is under the mouse). Made at a plate's first add; Nameplates' Mouseover
-- Highlight switches it.
--------------------------------------------------------------------------------

local P = {
	shown = {},                                       -- [unit token] = its plate's outline (plates shown now)
	of = setmetatable({}, { __mode = "k" }),          -- [a plate's unit frame] = its outline (made once)
	BOX = { 0, 0, -3, 4 },                            -- the rim: left, top (from the background's top left), right, bottom
	                                                  -- (from its bottom right; up)
	LINE = 1,                                         -- units a line (on the plate's pixel grid)
}
Hover.plates = P   -- (the tests')

local function PlatesOn()
	local np = MelloUI:GetModule("Nameplates")
	return np ~= nil and np.isEnabled and not (np.db and np.db.hover == false)
end

-- a line of the outline: d0 .. d1 units out from the box, on side `side`
local function Line(o, bg, side, d0, d1)
	local L, T, R, B = P.BOX[1], P.BOX[2], P.BOX[3], P.BOX[4]
	local t = o:CreateTexture(nil, "OVERLAY", nil, 7)
	t:SetColorTexture(1, 1, 1, 1)
	if t.SetRoundLayoutToNearestPixel then
		pcall(t.SetRoundLayoutToNearestPixel, t, true)
	end
	if side == "top" then
		t:SetPoint("TOPLEFT", bg, "TOPLEFT", L - d1, T + d1)
		t:SetPoint("BOTTOMRIGHT", bg, "TOPRIGHT", R + d1, T + d0)
	elseif side == "bottom" then
		t:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", L - d1, B - d0)
		t:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", R + d1, B - d1)
	elseif side == "left" then
		t:SetPoint("TOPLEFT", bg, "TOPLEFT", L - d1, T + d0)
		t:SetPoint("BOTTOMRIGHT", bg, "BOTTOMLEFT", L - d0, B - d0)
	else
		t:SetPoint("TOPLEFT", bg, "TOPRIGHT", R + d0, T + d0)
		t:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", R + d1, B - d0)
	end
	return t
end

-- the outer lines in the palette's selected trim (again on the bus's palette)
local function PaintPlate(o)
	local c = Trim()
	if c then
		for _, t in ipairs(o.trim) do
			t:SetVertexColor(c[1], c[2], c[3])
		end
	end
end

local function PlateOutline(uf)
	local o = P.of[uf]
	if o then
		return o
	end
	local bars = uf.HealthBarsContainer
	local bar = bars and bars.healthBar
	local bg = bar and bar.bgTexture
	if not bg then
		return nil
	end
	o = CreateFrame("Frame", nil, uf)
	o:SetAllPoints(uf)
	o:EnableMouse(false)
	local okL, level = pcall(bar.GetFrameLevel, bar)
	o:SetFrameLevel((okL and Num(level) or 1) + 10)
	-- (hidden unless a unit is under the mouse: a shown outline at alpha 0 is still laid out each frame as its plate
	-- moves -- the user's recording, many plates: "the FPS drops happen when there are many nameplates visible")
	o:Hide()
	-- (white next to the plate, the trim outside it)
	local line = P.LINE
	o.trim = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		Line(o, bg, side, 0, line)
		o.trim[#o.trim + 1] = Line(o, bg, side, line, 2 * line)
	end
	PaintPlate(o)
	P.of[uf] = o
	return o
end

-- each shown plate lit or not by the game's answer: is it the mouseover unit -- a plain answer shows the one plate
-- (the rest hidden: nothing laid out); a secret one shows each, its alpha the answer (never read)
local function Lit(o, unit, exists)
	if not exists then
		o:Hide()
		return
	end
	local ok, same = pcall(UnitIsUnit, "mouseover", unit)
	if not ok then
		o:Hide()
	elseif not Safe.IsSecret(same) then
		o:SetAlpha(1)
		o:SetShown(same == true)
	elseif o.SetAlphaFromBoolean and pcall(o.SetAlphaFromBoolean, o, same, 1, 0) then
		o:Show()
	else
		o:Hide()
	end
end

local watcher
local function Watch(on)
	if on then
		watcher:SetScript("OnUpdate", P.Tick)
	else
		watcher:SetScript("OnUpdate", nil)
	end
end

local Mouseover = Perf.Shared("UPDATE_MOUSEOVER_UNIT: the plate under the mouse lit", function()
	local exists = PlatesOn() and UnitExists("mouseover") or false
	for unit, o in pairs(P.shown) do
		Lit(o, unit, exists)
	end
	Watch(exists and next(P.shown) ~= nil)
end, "event")

-- (each frame while a unit is under the mouse) gone: every plate's outline away
P.Tick = Perf.Shared("the mouseover unit watched: the plates' outlines away when it is gone", function()
	if not UnitExists("mouseover") then
		for _, o in pairs(P.shown) do
			o:Hide()
		end
		Watch(false)
	end
end, "update")

-- a plate added (Nameplates' NAME_PLATE_UNIT_ADDED): its outline made once, lit if it is the mouseover unit now
function Hover.Plate(plate, unit)
	unit = Text(unit)
	if not (plate and unit and PlatesOn()) or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local uf = plate.UnitFrame
	local o = uf and PlateOutline(uf)
	if not o then
		return
	end
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnEvent", Mouseover)
		watcher:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
		MelloUI:On("palette", function()
			for _, made in pairs(P.of) do
				PaintPlate(made)
			end
		end, "FrameHover")
	end
	P.shown[unit] = o
	Lit(o, unit, UnitExists("mouseover"))
end

-- a plate gone (NAME_PLATE_UNIT_REMOVED)
function Hover.PlateGone(unit)
	unit = Text(unit)
	local o = unit and P.shown[unit]
	if o then
		o:Hide()
		P.shown[unit] = nil
	end
end

-- the highlight switched off (Group Frames' or Nameplates' Mouseover Highlight): what shows away
function Hover.Refresh()
	if over and not On() then
		Gone(over)
	end
	if not PlatesOn() then
		for _, o in pairs(P.shown) do
			o:Hide()
		end
		if watcher then
			Watch(false)
		end
	end
end

Hover.attached = attached   -- (the tests')
function Hover.Board()      -- (the tests')
	return board
end
function Hover.Watcher()    -- (the tests')
	return watcher
end
Hover.Show, Hover.Gone, Hover.light = Show, Gone, A   -- (the tests': the sim fires no hooks)
