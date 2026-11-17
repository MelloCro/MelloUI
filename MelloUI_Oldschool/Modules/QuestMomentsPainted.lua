--------------------------------------------------------------------------------
-- MelloUI - Quest Moments, the painted reskin's part (2.1.59)
--
-- The user, 2026-11-17: "all of the animations that we added recently must have ther oldschool look aswell, like the
-- new quest animations", "Redraw and sketch"; to the sketch (BuildData/output/oldschool_quest_moments_sketch, the
-- artifact 4qdz8UFLQWFyeDK2xfK7eq) "A for all 3": the Set plaque. The three moments keep their motions (Core/
-- QuestMoments.lua: the item to the tracker, the ring closes, the drop onto its place) and wear the frame set:
--   progress   the icon on a dark disc in the set's level ring, its count arcs inside the ring, the count on a small
--              plate of the set (its bar frame) under it; then the flight to the tracker's line, a painted ring of
--              light where it lands
--   objective  the same medallion; the name and the count on a plaque of the set's window frame (the chat's, one
--              stretching texture, a dark ground in its hole) that unfurls from behind it; painted rays behind once
--              the ring is whole, a halo, a star, sparks, the tick
--   quest      the set's ring drops onto the top edge of a plaque that opens from its middle, the hand-in mark pops
--              inside it; Quest Complete, the title and Ready to turn in on the plaque, one sheen across it
-- The lights are Oldschool's painted ones (MelloUI.FrameFX.Art), the icons its painted set (MelloUI.Icons).
--
-- How: the provider MelloUI.QuestMoments.dress, asked at each moment's start -- on while the painted effects are
-- (Kit:IsOn("effects"), as the lights' art goes). It steps the moment itself, each a function of its time, with the
-- core's pieces and helpers (MelloUI.QuestMoments.__, read only) and a few pieces of its own, made at the first
-- dressed moment (nothing at login) and laid for the frame set at each moment's start (a new set: the next moment
-- wears it). Sizes in UIParent units: the sketch's pixels, one a unit.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Q = MelloUI.QuestMoments
local H = Q and Q.__
local Kit = MelloUI.Kit
local Sets = Kit and Kit.Sets
if not (H and Sets and MelloUI.FrameFX) then
	return   -- (a MelloUI without the provider: the moments as it draws them)
end

local B = H.B
local Seg, OutCubic, InCubic, InOutCubic, OutBack, Spring, Hump = H.Seg, H.OutCubic, H.InCubic, H.InOutCubic, H.OutBack,
	H.Spring, H.Hump
local Put, PutText, SX, SY = H.Put, H.PutText, H.SX, H.SY
local max, min, sin, cos, pi = math.max, math.min, math.sin, math.cos, math.pi
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- a round icon's mask (Widgets' own)

local D = {
	HR = { progress = 20, objective = 22, quest = 26 },   -- the ring's opening by moment: the icon's radius in it
	OPEN = 1.2,                 -- the opening past the icon
	ARC = { progress = 3.4, objective = 3.6 },             -- the count arcs: this far inside the icon's radius
	HEAD = 18,                  -- the bright head of an arc drawing in
	NAME = 15, COUNT = 16.5, CHIP = 14.5, WORD = 13, BROW = 12.5,
	CHIP_W = 100, CHIP_H = 27, CHIP_DOWN = 50,             -- the count's plate: its size, its middle under the icon's
	ITEM_DOWN = 4,              -- the item's medallion under the line
	FRAME = 0.27,               -- the plaque: units a pixel of the set's window frame
	OBJ_H = 54, OBJ_GAP = 12, OBJ_PAD = 24,                -- the objective's plaque: its height, the words' gap and pad
	QUEST_W = 380, QUEST_PAD = 170, QUEST_H = 112, QUEST_TOP = 30, QUEST_FROM = 110,
	FLY_X = 430, FLY_Y = 70,    -- the flight's bend: its control point from the medallion
}
local Dress = {}

local function Lerp(a, b, p)
	return a + (b - a) * p
end

local function Bez(q, a, c, b)
	return (1 - q) * (1 - q) * a + 2 * (1 - q) * q * c + q * q * b
end

--------------------------------------------------------------------------------
-- The pieces (made at the first dressed moment)
--------------------------------------------------------------------------------

local function Build()
	if D.medal then
		return
	end
	local root = B.root
	-- the words' holder: the set's window frame round a rect (no picture: it holds the place), a dark ground in its
	-- hole -- both on the root, under the words
	D.rect = CreateFrame("Frame", nil, root)
	D.rect:SetSize(1, 1)
	D.ground = root:CreateTexture(nil, "BACKGROUND", nil, 3)
	Sets.Ground(D.ground)
	D.ground:Hide()
	D.win = Sets.Window(root, "BACKGROUND", 4)
	-- the count's plate: the set's bar frame round a fill (no picture either)
	D.fill = CreateFrame("Frame", nil, root)
	D.fill:SetSize(1, 1)
	D.strip = Sets.Strip(root, "BACKGROUND", 4)
	D.strip:Ground(true)
	-- the medallion: a dark disc, the icon on it (both in a round mask), the set's ring over them, the tick
	local m = CreateFrame("Frame", nil, root)
	m:SetFrameLevel(root:GetFrameLevel() + 1)
	m:Hide()
	D.medal = m
	D.mask = m:CreateMaskTexture()
	D.mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	D.mask:SetPoint("CENTER", m, "CENTER", 0, 0)
	D.disc = m:CreateTexture(nil, "BACKGROUND")
	D.disc:SetTexture(Sets.WHITE)
	D.disc:SetAllPoints(D.mask)
	D.disc:AddMaskTexture(D.mask)
	Kit:Paint(D.disc, "innerPanel", "vertex")
	D.icon = m:CreateTexture(nil, "ARTWORK")
	D.icon:AddMaskTexture(D.mask)
	D.ring = m:CreateTexture(nil, "OVERLAY", nil, 2)
	D.tick = m:CreateTexture(nil, "OVERLAY", nil, 7)
	D.tick:Hide()
	-- the lights over the medallion (on the core's top frame): the halo opening, the star
	local Art = MelloUI.FrameFX.Art
	D.flare = B.over:CreateTexture(nil, "OVERLAY", nil, 3)
	D.flare:SetTexture(Art("halo_white.tga"))
	D.flare:SetBlendMode("ADD")
	Kit:Paint(D.flare, "selectedTrim", "vertex")
	D.flare:Hide()
	D.star = B.over:CreateTexture(nil, "OVERLAY", nil, 5)
	D.star:SetTexture(Art("star_gold.tga"))
	D.star:SetBlendMode("ADD")
	D.star:Hide()
	-- the sheen across the quest's plaque: a soft band in a window over the plaque's hole
	D.sheenWin = CreateFrame("Frame", nil, root)
	D.sheenWin:SetClipsChildren(true)
	D.sheenWin:Hide()
	D.sheen = D.sheenWin:CreateTexture(nil, "ARTWORK")
	D.sheen:SetTexture(H.LIGHT .. "sheen")
	D.sheen:SetBlendMode("ADD")
	Kit:Paint(D.sheen, "text", "vertex")
end

-- the core's lights in Oldschool's painted art, its count arcs over the icon, once (Off takes them back)
local function Wear()
	if D.worn then
		return
	end
	D.worn = true
	local Art = MelloUI.FrameFX.Art
	B.rays:SetTexture(Art("rays_gold.tga"))
	B.halo:SetTexture(Art("halo_white.tga"))
	B.head:SetTexture(Art("spark_gold.tga"))
	for i = 1, Q.SPARKS do
		B.sparks[i]:SetTexture(Art("spark_gold.tga"))
	end
	local level = B.root:GetFrameLevel()
	B.ring:SetFrameLevel(level + 2)
	B.swipe:SetFrameLevel(level + 3)
end

--------------------------------------------------------------------------------
-- Laid for the frame set (at each moment's start)
--------------------------------------------------------------------------------

-- the set's ring round an icon of radius hr: its scale (units a pixel) and how far its art reaches from the icon's
-- middle to the left, the right, up and down
local function Reach(set, hr)
	local lv = set.level
	local hole = lv.hole
	local cx, cy = (hole[1] + hole[3]) / 2, (hole[2] + hole[4]) / 2
	local k = (hr + D.OPEN) / ((hole[3] - hole[1]) / 2)
	return k, cx * k, (lv.w - cx) * k, cy * k, (lv.h - cy) * k
end

-- the medallion for this moment: its size, the set's ring, its picture (nil: none yet -- the quest's mark pops in)
local function LayMedal(set, hr, icon)
	local m, lv = D.medal, set.level
	local hole = lv.hole
	m:SetSize(hr * 2, hr * 2)
	D.mask:SetSize((hr + 2) * 2, (hr + 2) * 2)
	D.ring:SetTexture(Sets.File(set, "level"))
	D.ring:SetTexCoord(0, lv.u, 0, lv.v)
	D.ring:ClearAllPoints()
	D.ring:SetPoint("CENTER", m, "CENTER", (lv.w / 2 - (hole[1] + hole[3]) / 2) * D.k,
		-(lv.h / 2 - (hole[2] + hole[4]) / 2) * D.k)
	D.ring:SetSize(lv.w * D.k, lv.h * D.k)
	local pic = D.icon
	pic:ClearAllPoints()
	pic:SetPoint("CENTER", m, "CENTER", 0, 0)
	pic:SetAlpha(1)
	if icon == nil then
		pic:Hide()
		return
	end
	local size
	if type(icon) == "number" or (type(icon) == "string" and icon:find("^Interface\\Icons")) then
		-- (a game icon fills the disc, its border cropped; one of MelloUI's marks stands on it)
		size = hr * 2.3
		MelloUI.Icons.Set(pic, icon, size, 0.06, 0.94, 0.06, 0.94)
	else
		size = hr * 1.5
		MelloUI.Icons.Set(pic, H.ICONS .. icon, size)
	end
	pic:SetSize(size, size)
	pic:Show()
end

-- the plaque for this set: the window frame round the rect, the rect's place inside the frame's outer edge (left, up,
-- right, down), the ground and the sheen's window in its hole
local function LayPlaque(set)
	local p = set.chat
	local hole = p.hole
	local s = D.FRAME
	local rail = hole[1] * s
	local half = rail / 2
	D.il, D.iu = half, hole[2] * s - half
	D.ir, D.id = (p.w - hole[3]) * s - half, (p.h - hole[4]) * s - half
	D.win:Lay(set, D.rect, rail)
	D.win.t:Hide()
	local g = D.ground
	g:ClearAllPoints()
	g:SetPoint("TOPLEFT", D.rect, "TOPLEFT", half - 2, 2 - half)
	g:SetPoint("BOTTOMRIGHT", D.rect, "BOTTOMRIGHT", 2 - half, half - 2)
	D.sheenWin:ClearAllPoints()
	D.sheenWin:SetPoint("TOPLEFT", D.rect, "TOPLEFT", half, -half)
	D.sheenWin:SetPoint("BOTTOMRIGHT", D.rect, "BOTTOMRIGHT", -half, half)
end

-- the count's plate for this set: the fill (the plate's hole) and where its middle is from the plate's
local function LayChip(set)
	local p = set.plate
	local hole = p.hole
	local s = D.CHIP_H / p.h
	local depth = (hole[4] - hole[2]) * s
	local length = D.CHIP_W - (hole[1] + p.w - hole[3]) * s
	D.fill:SetSize(length, depth)
	D.fx, D.fy = ((hole[1] + hole[3]) / 2 - p.w / 2) * s, (p.h / 2 - (hole[2] + hole[4]) / 2) * s
	D.strip:Lay(set, "plate", D.fill, depth, length)
	D.strip.t:Hide()
	D.strip.ground:Hide()
end

--------------------------------------------------------------------------------
-- Placed at a moment's time
--------------------------------------------------------------------------------

local function PutMedal(x, y, scale, a)
	local m = D.medal
	if a <= 0.003 then
		m:Hide()
		return
	end
	scale = max(0.05, scale)
	m:ClearAllPoints()
	m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", SX(x) / scale, SY(y) / scale)
	m:SetScale(scale)
	m:SetAlpha(a > 1 and 1 or a)
	m:Show()
end

-- the plaque with its outer edge at left and top, w x h
local function PutPlaque(left, top, w, h, a)
	local t, g = D.win.t, D.ground
	local rw, rh = w - D.il - D.ir, h - D.iu - D.id
	if a <= 0.003 or rw < 1 or rh < 1 then
		t:Hide()
		g:Hide()
		return
	end
	D.rect:ClearAllPoints()
	D.rect:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", SX(left + D.il), SY(top - D.iu))
	D.rect:SetSize(rw, rh)
	a = a > 1 and 1 or a
	t:SetAlpha(a)
	t:Show()
	g:SetAlpha(0.92 * a)
	g:Show()
end

-- the count's plate with its middle at (x, y)
local function PutChip(x, y, a)
	local t, g = D.strip.t, D.strip.ground
	if a <= 0.003 then
		t:Hide()
		g:Hide()
		return
	end
	D.fill:ClearAllPoints()
	D.fill:SetPoint("CENTER", UIParent, "BOTTOMLEFT", SX(x + D.fx), SY(y + D.fy))
	a = a > 1 and 1 or a
	t:SetAlpha(a)
	t:Show()
	g:SetAlpha(0.92 * a)
	g:Show()
end

-- one sheen across a plaque (its outer edge at left and top, w x h) at the share p of its way
local function PutSheen(p, left, top, w, h, a)
	if p <= 0 or p >= 1 or a <= 0.003 then
		D.sheenWin:Hide()
		return
	end
	local s = D.sheen
	s:ClearAllPoints()
	s:SetPoint("CENTER", UIParent, "BOTTOMLEFT", SX(left - h + (w + 2 * h) * InOutCubic(p)), SY(top - h / 2))
	s:SetSize(h * 1.1, h * 2.2)
	s:SetRotation(-0.35)
	s:SetAlpha(0.45 * Hump(p) * a)
	D.sheenWin:Show()
end

--------------------------------------------------------------------------------
-- The provider
--------------------------------------------------------------------------------

function Dress.On()
	return Kit:IsOn("effects") and Sets.Data() ~= nil
end

function Dress.Hide()
	if not D.medal then
		return
	end
	D.medal:Hide()
	D.tick:Hide()
	D.flare:Hide()
	D.star:Hide()
	D.sheenWin:Hide()
	D.win.t:Hide()
	D.ground:Hide()
	D.strip.t:Hide()
	D.strip.ground:Hide()
end

function Dress.Off()
	if not D.worn then
		return
	end
	D.worn = nil
	H.OwnLights()
	local level = B.root:GetFrameLevel()
	B.ring:SetFrameLevel(level + 1)
	B.swipe:SetFrameLevel(level + 2)
	H.Face(B.name, Q.NAME)
	H.Face(B.old, Q.COUNT)
	H.Face(B.new, Q.COUNT)
end

function Dress.Start(rec)
	Build()
	Wear()
	local set = Sets.Data()
	local kind = rec.kind
	local hr = D.HR[kind]
	D.hr = hr
	D.k, D.rl, D.rr, D.ru, D.rd = Reach(set, hr)
	D.mx, D.my = B.cx0, B.cy0
	local Tr = MelloUI.Widgets.Tr
	if kind == "quest" then
		LayMedal(set, hr, nil)
		MelloUI.Icons.Set(D.icon, H.ICONS .. "turnin_mark", 40)
		H.Letters(Tr("QUEST COMPLETE"), D.BROW, "selectedTrim")
		D.w = max(D.QUEST_W, (B.titleW or 200) + D.QUEST_PAD)
		H.SeedSparks(16, 110, 240, 0.5, 1.0, 10, 18)
		LayPlaque(set)
		return
	end
	LayMedal(set, hr, rec.icon or "quest_mark")
	if kind == "objective" then
		-- the medallion, then the words on the plaque: the group in the middle of the line
		H.Face(B.name, D.NAME)
		H.Face(B.old, D.COUNT)
		H.Face(B.new, D.COUNT)
		local textW = max(H.Measure(B.name, rec.name or ""), H.Measure(B.new, rec.to .. " / " .. rec.of))
		H.Letters(Tr("COMPLETE"), D.WORD, "selectedTrim")
		local wordW = 0
		for i = 1, (B.nLetters or 0) do
			wordW = wordW + B.letters[i].w + (i > 1 and 2 or 0)
		end
		D.groupW = D.rl + D.rr + D.OBJ_GAP + max(textW, wordW) + D.OBJ_PAD
		D.left = B.cx0 - D.groupW / 2
		D.mx = D.left + D.rl
		MelloUI.Icons.Set(D.tick, H.ICONS .. "ql_completed", 24)
		H.SeedSparks(14, 110, 240, 0.45, 0.9, 10, 17)
		LayPlaque(set)
	else
		H.Face(B.old, D.CHIP)
		H.Face(B.new, D.CHIP)
		D.my = B.cy0 - D.ITEM_DOWN
		H.SeedSparks(8, 60, 120, 0.3, 0.6, 8, 13)
		LayChip(set)
	end
end

-- the progress and the objective moment (done: the objective's, its ring closes)
function Dress.Medal(t, done)
	local d, hr, mx, my = B.data, D.hr, D.mx, D.my
	local out = Q.OUT[B.kind]
	local exit = done and Seg(t, out, out + 0.45) or 0
	local A0 = 1 - InCubic(exit)
	my = my + 10 * OutCubic(exit)
	-- the progress moment's flight: from its place to the tracker's line, smaller as it goes, a few lights behind it
	local fx, fy, fs = mx, my, 1
	local flyP = (not done and B.toX) and Seg(t, Q.FLY, Q.FLY + Q.FLY_T) or 0
	local fe = InOutCubic(flyP)
	if flyP > 0 then
		local cx, cy = mx + D.FLY_X, my + D.FLY_Y
		fx, fy = Bez(fe, mx, cx, B.toX), Bez(fe, my, cy, B.toY)
		fs = 1 - 0.58 * fe
		for i = 1, Q.TRAIL do
			local q = InOutCubic(max(0, flyP - i * 0.028))
			local s = 28 * (1 - i / 8)
			Put(B.trail[i], Bez(q, mx, cx, B.toX), Bez(q, my, cy, B.toY), s, s, flyP < 1 and 0.5 * (1 - i / 7) or 0)
		end
	else
		for i = 1, Q.TRAIL do
			B.trail[i]:Hide()
		end
	end
	local arrived = (not done and B.toX) and Seg(t, Q.FLY + Q.FLY_T, Q.FLY + Q.FLY_T + 0.55) or 0
	-- no line to fly to: it leaves in place
	if not done and not B.toX then
		exit = Seg(t, out - 0.9, out - 0.45)
		A0 = 1 - InCubic(exit)
	end
	-- the bloom behind, once
	local bs = hr * 2 * (1.3 + (done and 2.2 or 2) * OutCubic(Seg(t, 0, 0.55)))
	Put(B.glow, mx, my, bs, bs, 0.8 * Seg(t, 0, 0.06) * (1 - Seg(t, 0.1, 0.7)) * A0)
	-- the medallion: a spring in, then the flight's size
	local sc = (0.45 + 0.55 * Spring(Seg(t, 0, 0.34))) * fs
	PutMedal(fx, fy, sc, Seg(t, 0, 0.14) * A0 * (1 - min(1, arrived * 1.5)))
	-- the count arcs inside the ring: the counted ones, the new one drawn in with its bright head
	local arc = hr - D.ARC[B.kind]
	local fill = InOutCubic(Seg(t, 0.34, 0.64))
	local ringA = Seg(t, 0.1, 0.3) * A0 * (1 - fe)
	local hx, hy = H.DrawRing(fx, fy, d.from, fill, ringA, sc * arc / Q.RING)
	if hx then
		Put(B.head, hx, hy, D.HEAD, D.HEAD, ringA)
	else
		B.head:Hide()
	end
	local cp = Seg(t, B.rollAt or 0.52, (B.rollAt or 0.52) + 0.32)
	if done then
		-- the new arc flashes as it lands
		local la = (d.from + 0.5) * 2 * pi / d.of
		Put(B.land, mx + sin(la) * arc, my + cos(la) * arc, 30, 30, fill >= 1 and 0.9 * (1 - Seg(t, 0.64, 1.0)) * A0 or 0)
		-- the ring whole: painted rays behind for a moment, a halo opens, a star, sparks thrown out, the tick lands
		local rp, rf = Seg(t, 0.58, 1.0), 1 - Seg(t, 1.0, 1.7)
		local rs = hr * 6.4 * (0.6 + 0.4 * OutCubic(rp))
		Put(B.rays, mx, my, rs, rs, 0.55 * rp * rf * A0, -t * 0.3)
		local f = Seg(t, 0.62, 1.15)
		local s1 = hr * 2.6 * (1 + 0.9 * OutCubic(f))
		Put(D.flare, mx, my, s1, s1, (1 - f) * A0, -f)
		local ss = hr * 3.2 * OutBack(Seg(t, 0.62, 0.9), 2)
		Put(D.star, mx, my, ss, ss, 0.9 * (1 - Seg(t, 0.8, 1.3)) * A0)
		H.DrawSparks(t - 0.62, mx, my, hr, 140, A0)
		local cb = Seg(t, 0.72, 1.0)
		local ts = 24 * OutBack(cb, 2.4)
		if cb > 0 and ts > 0.5 then
			D.tick:ClearAllPoints()
			D.tick:SetPoint("CENTER", D.medal, "CENTER", hr * 0.82, -hr * 0.76)
			D.tick:SetSize(ts, ts)
			D.tick:SetAlpha(cb)
			D.tick:Show()
		else
			D.tick:Hide()
		end
		-- the plaque unfurls from behind the medallion (and folds back into it on the way out); the name, then the
		-- count rolling in after its arc, turning into the gold word
		local unf = OutCubic(Seg(t, 0.12, 0.48)) * (1 - InCubic(exit))
		local px = mx + hr * 0.3
		PutPlaque(px, my + D.OBJ_H / 2, Lerp(hr * 1.4, D.left + D.groupW - px, unf), D.OBJ_H, Seg(t, 0.1, 0.24) * A0)
		local tx = mx + D.rr + D.OBJ_GAP
		local slide = 10 * (1 - OutCubic(Seg(t, 0.22, 0.5)))
		local wordsA = Seg(t, 0.26, 0.48) * A0
		PutText(B.name, "LEFT", tx - slide, my + 11, wordsA)
		local swap = Seg(t, 0.98, 1.26)
		B.clip:SetAlpha(wordsA * (1 - swap))
		H.Roll(cp, tx - slide, my - 12, d.from .. " / " .. d.of, d.to .. " / " .. d.of)
		H.PutLettersAt(tx, my - 12 - 4 * (1 - OutCubic(swap)), swap * A0)
		return
	end
	-- the count on the set's plate under the medallion, gone as it leaves for the tracker
	local chipA = Seg(t, 0.3, 0.5) * (1 - Seg(t, Q.FLY - 0.05, Q.FLY + 0.15)) * A0
	local cy = my - D.CHIP_DOWN
	PutChip(mx, cy, chipA)
	B.name:Hide()
	local cw = H.Measure(B.new, d.to .. " / " .. d.of)
	B.clip:SetAlpha(chipA)
	H.Roll(cp, mx - cw / 2, cy, d.from .. " / " .. d.of, d.to .. " / " .. d.of)
	-- arriving: a painted ring of light on the tracker's line, a soft light along it, a few sparks
	if arrived > 0 and B.toX then
		local s = 44 * (1 + 1.1 * OutCubic(arrived))
		Put(D.flare, B.toX, B.toY, s, s, 1 - arrived, -arrived * 1.2)
		Put(B.streak, B.toX + 60, B.toY, 190 * OutCubic(arrived), 13, 0.9 * (1 - arrived))
		H.DrawSparks(t - Q.FLY - Q.FLY_T, B.toX, B.toY, 0, 60, 1)
	else
		D.flare:Hide()
		B.streak:Hide()
		H.DrawSparks(-1, 0, 0, 0, 0, 0)
	end
end

-- the quest's: the plaque opens from its middle, the set's ring lands on its top edge
function Dress.Quest(t)
	local hr = D.hr
	local cx, cy = D.mx, D.my - Q.QUEST_DOWN
	local out = Q.OUT.quest
	local A0 = 1 - InCubic(Seg(t, out, out + 0.6))
	local land = 0.44
	-- painted rays behind the ring: they open once it has landed, turning slowly, then settle low
	local rA = 0.5 * Seg(t, 0.32, 0.6) * (1 - 0.6 * Seg(t, 0.95, 1.8)) * (1 - Seg(t, out - 0.5, out + 0.1))
	local rs = 300 * (0.4 + 0.7 * OutCubic(Seg(t, 0.3, 0.95)))
	Put(B.rays, cx, cy, rs, rs, rA, -(0.25 + t * 0.1))
	-- the plaque, one sheen across it once the words stand
	local top = cy - D.QUEST_TOP
	local w = Lerp(D.QUEST_FROM, D.w, OutCubic(Seg(t, 0.22, 0.66)))
	PutPlaque(cx - w / 2, top, w, D.QUEST_H, Seg(t, 0.2, 0.34) * A0)
	PutSheen(Seg(t, 1.25, 1.85), cx - D.w / 2, top, D.w, D.QUEST_H, A0)
	-- the ring drops in and lands; a wave of painted light where it lands
	local wp = Seg(t, land - 0.02, 1.05)
	local ws = hr * 3 * (1 + 1.2 * OutCubic(wp))
	Put(B.halo, cx, cy, ws, ws, 0.7 * (1 - wp) * Seg(t, land - 0.02, land + 0.04) * A0, -wp)
	local cs = 1.55 - 0.55 * OutCubic(Seg(t, 0.12, land))
	PutMedal(cx, cy, cs, Seg(t, 0.12, 0.3) * A0)
	-- the hand-in mark pops inside it
	local qp = Seg(t, 0.36, 0.72)
	local qs = 40 * OutBack(qp, 2.6)
	local mark = D.icon
	if qp > 0 and qs > 1 then
		mark:ClearAllPoints()
		mark:SetPoint("CENTER", D.medal, "CENTER", 0, -1)
		mark:SetSize(qs / cs, qs / cs)
		mark:SetAlpha(qp)
		mark:Show()
	else
		mark:Hide()
	end
	H.DrawSparks(t - land, cx, cy, hr + 6, 120, A0)
	-- the words on the plaque: Quest Complete drawing together, the title opening, Ready to turn in
	local y = min(top - 36, cy - D.rd - 13)
	H.PutLetters(cx, y, 8 - 4.8 * OutCubic(Seg(t, 0.5, 1.05)), OutCubic(Seg(t, 0.5, 0.8)) * A0)
	H.PutTitle(t, cx, y - 27, A0)
	PutText(B.sub, "CENTER", cx, y - 53, Seg(t, 1.05, 1.4) * A0)
end

Q.dress = Dress
Q.painted = D   -- (the tests')
