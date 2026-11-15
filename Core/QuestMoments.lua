--------------------------------------------------------------------------------
-- MelloUI - Quest Moments (2.1.52; MelloUI.QuestMoments)
--
-- The game's yellow quest lines in the middle of the screen ("Mudsnout Blossoms: 3/6", "Hillsbrad Farmhand slain:
-- 6/6") played as moments instead. The user, 2026-11-14: "Can we sketch a animation for picking up a quest item,
-- quest objective completed and quest completed animation instead of the plain text that appears on the screen",
-- "i want very high quality animations"; to the sketch (BuildData/output/quest_moments_sketch, the artifact
-- GuCdDf5PdohLceJzTGkPg7) "C, A, A":
--   progress   (C, To the tracker) the item's icon in a gilded medallion, its count ring of one arc a needed item,
--              the new arc drawn in and the count rolling up under it; then the medallion flies to the objective's
--              line in the tracker (Questie's, dressed, or MelloUI's own) and lights it. No line found: it fades in
--              place
--   objective  (A, Ring closes) the last arc closes the ring: it flares, a wave of light opens, rays turn behind
--              for a moment, sparks fly and a tick lands; the count turns into Complete
--   quest      (A, Gilded crest) the crest drops in with the hand-in mark, rays open once it has landed, Quest
--              Complete draws together, the title opens from its middle with one sheen, two rules draw out
-- Each plays once (one Anim:Drive, a function of time as the sketch's scenes were) and settles; nothing repeats,
-- nothing is drawn over the character. Reduce Motion: the settled moment, held and gone, nothing moving.
--
-- What it takes: the game's info event from its error frame (UnregisterEvent, nothing replaced -- ErrorFilter's way
-- with the error event): a quest line that a moment plays is kept back (its sound played as the frame would), every
-- other line handed straight to the frame's own handler, so it shows as always and Core/CentreText.lua shades it.
-- A line it cannot place in the quest log -- or one whose moment is switched off -- goes to the frame: the game's
-- text as before. Told apart by the game's own message names (GetGameMessageInfo) and read by its own format
-- strings, so it follows the client's language. A secret line is always handed on. The lines it keeps back: a count
-- ("Mudsnout Blossoms: 3/6", "... slain: 6/6", "Players slain: 3/10"), an objective's "(Complete)" and the quest's
-- "... completed." (the user, 2026-11-14: "the default text is still showing" -- the last two went through before).
-- /mello moments why: the last quest lines it handed to the game and why.
--
-- Where: the game's line (UIErrorsFrame: TOP -122 units), the quest's crest a little under it. Its frames are made
-- at the first moment (nothing at login), on UIParent, no mouse, no secure frame: it plays in a fight.
-- Several pickups at once count up in one moment; a quest done in the same breath as its last objective plays the
-- quest's moment alone. The Quest Tracker's own Progress Motion stays and plays beside it.
--
--   MelloUI.QuestMoments.Play(kind, data)   a moment (the Animations page's Play): kind "progress" | "objective" |
--                                           "quest"; data = { questID, index, name, icon, from, to, of, title }
--   MelloUI.QuestMoments.Shown() -> bool    a moment plays
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Safe = MelloUI.Safe
local Secret, Num, Text = Safe.IsSecret, Safe.Number, Safe.Text
local Perf = MelloUI.Perf:Scope("Quest moments")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer
local sin, cos, pi, max, min, exp = math.sin, math.cos, math.pi, math.max, math.min, math.exp

local M = MelloUI:RegisterModule("QuestMoments", {
	title = "Quest Moments",
	play = "quest",   -- its switch row's Play, the Animations page
	slash = "moments",   -- /mello moments item | objective | quest | all: each moment played once
	desc = "The game's yellow quest lines in the middle of the screen become moments: an item picked up flies to its line in your tracker, a finished objective closes its ring, a finished quest lands a gilded crest.",
	icon = "Interface\\Icons\\INV_Misc_Note_02",
	flavour = "Every blossom counts, and you see it count.",
	enabledByDefault = true,
	defaults = {
		progress = true,
		objective = true,
		quest = true,
	},
	options = {
		{ type = "toggle", key = "progress", play = "progress", name = "Item Picked Up",
		  desc = "An item or a kill for a quest: its icon counts up in a gilded ring, then flies to its line in your quest tracker." },
		{ type = "toggle", key = "objective", play = "objective", name = "Objective Done",
		  desc = "An objective finished: its ring closes with a flare of light, sparks and a tick, and the count turns into Complete." },
		{ type = "toggle", key = "quest", play = "quest", name = "Quest Done",
		  desc = "A quest ready to turn in: a gilded crest lands with the hand-in mark, and the quest's title opens under Quest Complete." },
	},
})

local LIGHT = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\Light\\"   -- onelook-allow: a moment's light, in both looks
local GLOW = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\glow_gold"   -- onelook-allow: a moment's light, in both looks
local ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\"

-- (one table: the file's locals) the sizes in UIParent units -- the sketch's pixels at its 1.1 pixels a unit
local Q = {
	LINE = 132,                 -- the game's line's middle under the screen's top (its frame at TOP -122)
	QUEST_DOWN = 42,            -- the crest's middle under the line
	R = 21, RING = 28,          -- the medallion's radius, its count ring's
	BEAD = 4.2,                 -- an arc's width (the head's light is seven of it)
	-- the ring's pictures (Tools/make_quest_rings.py: its UNITS, WIDTH, GAP and the counts it drew)
	RING_TEX = "Interface\\AddOns\\MelloUI\\Media\\Textures\\QuestMoments\\",
	RING_FRAME = 64, RING_W = 4.2, RING_GAP = 1.6, RING_MAX = 20,
	NAME = 14.5, COUNT = 16.5, WORD = 12.5, TITLE = 28, BROW = 12, SUB = 13.5,
	GAP = 15,                   -- the medallion to its words
	-- each moment's length and when it leaves (the sketch's, line for line)
	DUR = { progress = 2.4, objective = 3.0, quest = 4.4 },
	OUT = { progress = 2.2, objective = 2.45, quest = 3.7 },
	-- (Reduce Motion) the time each moment is shown at, settled: the count rolled, the ring closed, the crest landed
	STILL = { progress = 0.9, objective = 1.6, quest = 2.4 },
	-- (the progress moment) its flight: when it leaves for the tracker and how long it flies
	FLY = 0.95, FLY_T = 0.65,
	SPARKS = 18, MOTES = 11, TRAIL = 6,
	queue = {}, pool = {},      -- the moments waiting (records from the pool: nothing made per line)
	complete = {}, seen = {},   -- [questID] = the quest log's IsComplete as last read; this scan's mark
	ready = false,              -- the quest log read once (only a change after it plays)
	took = false,               -- the info event is ours (taken from the game's frame)
	scanQueued = false,
	patterns = {},              -- [the game's message name] = its format string as a pattern
	unnamed = {},               -- [the game's message name] = a format with no name: its words before the count
	why = {}, whyN = 0,         -- the last quest lines handed to the game: records in a ring, how many so far
}
MelloUI.QuestMoments = Q
local B = {}                    -- the frames, made at the first moment
local eventFrame                -- its events' frame, made when it is first switched on (Events, below)

--------------------------------------------------------------------------------
-- Time, easing and a seeded random (every moment a function of its time)
--------------------------------------------------------------------------------

local function Seg(t, a, b)
	local v = (t - a) / (b - a)
	return v < 0 and 0 or v > 1 and 1 or v
end
local function OutCubic(p) local q = 1 - p return 1 - q * q * q end
local function InCubic(p) return p * p * p end
local function InOutCubic(p) if p < 0.5 then return 4 * p * p * p end local q = -2 * p + 2 return 1 - q * q * q / 2 end
local function OutExpo(p) return p >= 1 and 1 or 1 - 2 ^ (-10 * p) end
local function OutBack(p, s)
	s = s or 1.70158
	local q = p - 1
	return 1 + (s + 1) * q * q * q + s * q * q
end
-- a spring that settles at 1 after one overshoot (no wobble that reads as a repeat)
local function Spring(p)
	if p <= 0 then
		return 0
	end
	local k, z = 11, 0.5
	return 1 - exp(-z * k * p) * cos(k * (1 - z * z) ^ 0.5 * p)
end
local function Hump(p) return (p > 0 and p < 1) and sin(pi * p) or 0 end

local seed = 1
local function Rand()
	seed = (seed * 1664525 + 1013904223) % 4294967296
	return seed / 4294967296
end

--------------------------------------------------------------------------------
-- The frames (made at the first moment)
--------------------------------------------------------------------------------

local W   -- MelloUI.Widgets, read at the first moment

local function Tex(file, layer, sub, add)
	local t = B.root:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
	t:SetTexture(file)
	if add then
		t:SetBlendMode("ADD")
	end
	t:Hide()
	return t
end

local function Face(fs, size)
	local Kit = rawget(MelloUI, "Kit")
	local face = Kit and Kit.titleFont or "Interface\\AddOns\\MelloUI\\Media\\Fonts\\Fredoka\\Fredoka-SemiBold.ttf"
	if not MelloUI:SetFace(fs, face, size, "") then
		-- (the face's file not read yet: the game's own font this time, never a blank text; the next moment tries again)
		fs:SetFontObject(W.FontObject("MelloUIFont_GameFontHighlight"))
	end
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetShadowOffset(1, -1)
end

local function Words(parent, size, key)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	Face(fs, size)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	W.Paint(fs, key or "text", "text")
	fs:Hide()
	return fs
end

-- a piece at a point in UIParent's units (the screen's bottom left), w x h, alpha a (hidden at 0)
local function Put(r, x, y, w, h, a, rot)
	if not a or a <= 0.003 or w <= 0.05 or h <= 0.05 then
		r:Hide()
		return
	end
	r:ClearAllPoints()
	r:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	r:SetSize(w, h)
	r:SetAlpha(a > 1 and 1 or a)
	if rot then
		r:SetRotation(rot)
	end
	r:Show()
end

local function PutText(fs, point, x, y, a)
	if not a or a <= 0.003 then
		fs:Hide()
		return
	end
	fs:ClearAllPoints()
	fs:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
	fs:SetAlpha(a > 1 and 1 or a)
	fs:Show()
end

local function Build()
	if B.root then
		return
	end
	W = MelloUI.Widgets
	local root = CreateFrame("Frame", nil, UIParent)
	root:SetAllPoints(UIParent)
	root:SetFrameStrata("HIGH")
	root:EnableMouse(false)
	root:Hide()
	B.root = root
	-- the soft band under the words (MelloUI.Shade: the notice's own), on a box the moment lays
	B.box = CreateFrame("Frame", nil, root)
	B.box:SetSize(1, 1)
	B.band = MelloUI.Shade:Band(root, { colour = "innerPanel", alpha = 0.8, feather = 24 })
	if B.band then
		B.band:Anchor(B.box, 0, 0)
	end
	-- the lights behind (back to front): rays, the halo, the bloom
	B.rays = Tex(LIGHT .. "rays_gold", "BACKGROUND", 2, true)
	B.halo = Tex(LIGHT .. "halo_white", "BORDER", 0, true)
	W.Paint(B.halo, "selectedTrim", "vertex")
	B.glow = Tex(GLOW, "BORDER", 1, true)
	B.crest = Tex(LIGHT .. "crest_gold", "ARTWORK", 0, true)
	B.wave = Tex(LIGHT .. "wave_gold", "ARTWORK", 1, true)
	B.flare = Tex(LIGHT .. "ring_gold", "OVERLAY", 3, true)
	-- the medallion: the kit's round icon (its plate, mask and gilded rim), no mouse of its own
	B.medal = W.RoundIcon(root, Q.R * 2)
	B.medal:EnableMouse(false)
	B.medal:SetFrameLevel(root:GetFrameLevel() + 2)
	B.medal:Hide()
	B.tick = B.medal:CreateTexture(nil, "OVERLAY", nil, 7)
	B.tick:Hide()
	-- (2.1.52; the user, of the first build's ring of dots: "not as smooth as i expected them to be, and have very
	-- sharp edges") the count ring: smooth arcs of its own art (Tools/make_quest_rings.py, one picture for each count
	-- needed), its dark edge and grey track under the gold, which fills through the game's own radial sweep (a
	-- Cooldown's swipe at a share, as the game's renown rings: CooldownFrame_SetDisplayAsPercentage); whole, the gold
	-- picture itself. On a frame of its own that follows the medallion's place and size
	local ring = CreateFrame("Frame", nil, root)
	ring:SetSize(Q.RING_FRAME, Q.RING_FRAME)
	ring:SetFrameLevel(root:GetFrameLevel() + 1)
	ring:Hide()
	B.ring = ring
	B.ringEdge = ring:CreateTexture(nil, "ARTWORK", nil, 1)
	B.ringTrack = ring:CreateTexture(nil, "ARTWORK", nil, 2)
	B.ringFull = ring:CreateTexture(nil, "ARTWORK", nil, 4)
	for _, t in ipairs({ B.ringEdge, B.ringTrack, B.ringFull }) do
		t:SetAllPoints(ring)
	end
	W.Paint(B.ringEdge, "innerPanel", "vertex", 0.95)
	W.Paint(B.ringTrack, "border", "vertex")
	W.Paint(B.ringFull, "selectedTrim", "vertex")
	local swipe = CreateFrame("Cooldown", nil, ring)
	swipe:SetAllPoints(ring)
	swipe:SetFrameLevel(ring:GetFrameLevel() + 1)
	swipe:EnableMouse(false)
	swipe:SetDrawEdge(false)
	swipe:SetDrawBling(false)
	swipe:SetHideCountdownNumbers(true)
	swipe:SetReverse(true)
	swipe:Hide()
	W.Paint(swipe, "selectedTrim", "swipe")
	B.swipe = swipe
	-- the bright head of an arc drawing in, and the light where it lands: over the gold
	B.over = CreateFrame("Frame", nil, root)
	B.over:SetAllPoints(root)
	B.over:SetFrameLevel(root:GetFrameLevel() + 4)
	B.head = B.over:CreateTexture(nil, "OVERLAY", nil, 4)
	B.head:SetTexture(LIGHT .. "spark_gold")
	B.head:SetBlendMode("ADD")
	B.head:Hide()
	B.land = B.over:CreateTexture(nil, "OVERLAY", nil, 2)
	B.land:SetTexture(GLOW)
	B.land:SetBlendMode("ADD")
	B.land:Hide()
	-- the words: the name, the count rolling in its clip, the gold word
	B.name = Words(root, Q.NAME)
	B.clip = CreateFrame("Frame", nil, root)
	B.clip:SetClipsChildren(true)
	B.old = Words(B.clip, Q.COUNT)
	B.new = Words(B.clip, Q.COUNT)
	B.letters = {}
	-- the quest's words: the title in its opening clip, its sheen (a gold copy in a moving window), the rules
	B.titleClip = CreateFrame("Frame", nil, root)
	B.titleClip:SetClipsChildren(true)
	B.title = Words(B.titleClip, Q.TITLE)
	B.title:SetJustifyH("CENTER")
	B.sheenWin = CreateFrame("Frame", nil, B.titleClip)
	B.sheenWin:SetClipsChildren(true)
	B.sheen = Words(B.sheenWin, Q.TITLE, "selectedTrim")
	B.sheen:SetJustifyH("CENTER")
	B.ruleL = Tex(LIGHT .. "line_h", "ARTWORK", 2, true)
	B.ruleR = Tex(LIGHT .. "line_h", "ARTWORK", 2, true)
	W.Paint(B.ruleL, "selectedTrim", "vertex")
	W.Paint(B.ruleR, "selectedTrim", "vertex")
	B.star = Tex(LIGHT .. "star_gold", "OVERLAY", 2, true)
	B.sub = Words(root, Q.SUB)
	B.mark = Tex(nil, "OVERLAY", 5)
	-- the one-shot pieces: sparks, motes, the flight's trail
	B.sparks, B.motes, B.trail = {}, {}, {}
	for i = 1, Q.SPARKS do
		B.sparks[i] = Tex(LIGHT .. "spark_gold", "OVERLAY", 6, true)
	end
	for i = 1, Q.MOTES do
		B.motes[i] = Tex(LIGHT .. "star_gold", "OVERLAY", 6, true)
	end
	for i = 1, Q.TRAIL do
		B.trail[i] = Tex(GLOW, "OVERLAY", 1, true)
	end
	B.arrive = Tex(LIGHT .. "ring_gold", "OVERLAY", 3, true)
	B.streak = Tex(LIGHT .. "line_h", "OVERLAY", 2, true)
	W.Paint(B.streak, "selectedTrim", "vertex")
end

--------------------------------------------------------------------------------
-- A moment's layout: the ring's picture for its count, the words measured
--------------------------------------------------------------------------------

-- the ring for `of` needed: its picture (a count past the most drawn: the whole ring), and each arc's span and the
-- gap before it as shares of the circle, as Tools/make_quest_rings.py drew them (its GAP and the arcs' round ends)
local function LayRing(of)
	of = max(1, of or 1)
	local file = Q.RING_TEX .. "ring_" .. (of <= Q.RING_MAX and of or "all")
	B.ringEdge:SetTexture(file .. "_edge")
	B.ringTrack:SetTexture(file)
	B.ringFull:SetTexture(file)
	B.swipe:SetSwipeTexture(file)
	B.of = of
	if of == 1 or of > Q.RING_MAX then
		B.arcSpan, B.arcGap = 1 / of, 0
	else
		local slot = 2 * pi / of
		local span = max(0.02, slot - (Q.RING_GAP + Q.RING_W) / Q.RING)
		B.arcSpan, B.arcGap = span / (2 * pi), (slot - span) / 2 / (2 * pi)
	end
end

-- the game's sweep at a share of the circle, held there (its renown rings' way: paused, started that share ago)
local function Sweep(share)
	local s = B.swipe
	if share <= 0.0005 then
		s:Hide()
		return
	end
	s:Pause()
	s:SetCooldown(GetTime() - 100 * share, 100)
	s:Show()
end

-- the ring at (x, y): `full` arcs gold, the next drawn to `part`; alpha a; returns the drawing head's place
local function DrawRing(x, y, full, part, a, scale)
	scale = max(0.05, scale or 1)
	local ring = B.ring
	if a <= 0.003 then
		ring:Hide()
		return nil
	end
	ring:ClearAllPoints()
	ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	ring:SetScale(scale)
	ring:SetAlpha(a > 1 and 1 or a)
	ring:Show()
	local of = B.of or 1
	if full >= of or (full + 1 >= of and part >= 1) then
		B.ringFull:Show()
		B.swipe:Hide()
		return nil
	end
	B.ringFull:Hide()
	-- the share swept: the counted arcs with their gaps, then into the next arc past its gap
	local share = full / of + (part > 0 and B.arcGap + part * B.arcSpan or 0)
	Sweep(min(0.9995, share))
	if part > 0 and part < 1 then
		local angle = share * 2 * pi
		return x + sin(angle) * Q.RING * scale, y + cos(angle) * Q.RING * scale
	end
	return nil
end

-- the medallion's picture: an item's icon, MelloUI's kill mark, a mark for the other kinds
local function SetMedal(icon)
	local m = B.medal
	if type(icon) == "number" or (type(icon) == "string" and icon:find("^Interface\\Icons")) then
		m:SetIcon(icon)
	else
		m:SetIcon(ICONS .. (icon or "quest_mark"))
	end
end

local function Measure(fs, text)
	fs:SetText(text)
	local w = Num(fs:GetStringWidth())
	return w or 0
end

-- (a word drawn letter by letter, so its letters can draw together) the word's letters laid at a spacing
local function Letters(text, size, key)
	local n = 0
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		local fs = B.letters[n]
		if not fs then
			fs = Words(B.root, size, key)
			B.letters[n] = fs
		end
		Face(fs, size)
		W.Paint(fs, key, "text")
		fs.w = Measure(fs, ch)
	end
	for i = n + 1, #B.letters do
		B.letters[i]:Hide()
		B.letters[i].w = nil
	end
	B.nLetters = n
end

local function PutLetters(cx, y, spacing, a)
	local total = 0
	for i = 1, B.nLetters do
		total = total + B.letters[i].w + (i > 1 and spacing or 0)
	end
	local x = cx - total / 2
	for i = 1, B.nLetters do
		local fs = B.letters[i]
		PutText(fs, "LEFT", x, y, a)
		x = x + fs.w + spacing
	end
end

-- (the gold word, "COMPLETE", beside the medallion: its letters from its left edge at a little spacing)
local function PutLettersAt(x, y, a)
	local total = 0
	for i = 1, (B.nLetters or 0) do
		total = total + B.letters[i].w + (i > 1 and 2 or 0)
	end
	PutLetters(x + total / 2, y, 2, a)
end

local function HideAll()
	if not B.root then
		return
	end
	for _, r in ipairs({ B.rays, B.halo, B.glow, B.crest, B.wave, B.flare, B.head, B.land, B.name, B.old, B.new, B.title,
		B.sheen, B.ruleL, B.ruleR, B.star, B.sub, B.mark, B.arrive, B.streak, B.tick }) do
		r:Hide()
	end
	for _, list in ipairs({ B.sparks, B.motes, B.trail, B.letters }) do
		for _, r in ipairs(list) do
			r:Hide()
		end
	end
	B.clip:Hide()
	B.titleClip:Hide()
	B.sheenWin:Hide()
	B.ring:Hide()
	B.swipe:Hide()
	B.medal:Hide()
	if B.band then
		B.band:SetShown(false)
	end
end

--------------------------------------------------------------------------------
-- The one-shot pieces: sparks thrown out (slowed by the air, a little gravity), motes rising
--------------------------------------------------------------------------------

local spark = { ang = {}, spd = {}, life = {}, size = {}, delay = {} }
local mote = { ox = {}, oy = {}, vy = {}, life = {}, size = {}, delay = {}, ph = {} }

local function SeedSparks(n, s0, s1, l0, l1, z0, z1)
	for i = 1, n do
		spark.ang[i] = 2 * pi * (i + Rand() * 0.8) / n
		spark.spd[i] = s0 + (s1 - s0) * Rand()
		spark.life[i] = l0 + (l1 - l0) * Rand()
		spark.size[i] = z0 + (z1 - z0) * Rand()
		spark.delay[i] = Rand() * 0.06
	end
	spark.n = n
end

local function DrawSparks(t, x, y, r0, g, a)
	for i = 1, Q.SPARKS do
		local s = B.sparks[i]
		local tt = i <= (spark.n or 0) and t - spark.delay[i] or -1
		if tt < 0 or tt > spark.life[i] then
			s:Hide()
		else
			local k = (1 - exp(-3.2 * tt)) / 3.2
			local d = r0 + spark.spd[i] * k
			local life = tt / spark.life[i]
			local size = spark.size[i] * (1 - 0.55 * life)
			Put(s, x + cos(spark.ang[i]) * d, y + sin(spark.ang[i]) * d - 0.5 * g * tt * tt, size, size, (1 - life) ^ 1.4 * a)
		end
	end
end

local function SeedMotes(n, w, h, v0, v1, l0, l1, z0, z1, stagger)
	for i = 1, n do
		mote.ox[i], mote.oy[i] = (Rand() - 0.5) * w, (Rand() - 0.5) * h
		mote.vy[i] = v0 + (v1 - v0) * Rand()
		mote.life[i] = l0 + (l1 - l0) * Rand()
		mote.delay[i] = Rand() * stagger
		mote.size[i] = z0 + (z1 - z0) * Rand()
		mote.ph[i] = Rand() * 2 * pi
	end
	mote.n = n
end

local function DrawMotes(t, x, y, sway, a)
	for i = 1, Q.MOTES do
		local m = B.motes[i]
		local tt = i <= (mote.n or 0) and t - mote.delay[i] or -1
		if tt < 0 or tt > mote.life[i] then
			m:Hide()
		else
			local p = tt / mote.life[i]
			local alpha = Hump(min(1, p * 1.6)) * (1 - p) * a
			Put(m, x + mote.ox[i] + sin(mote.ph[i] + tt * 2.4) * sway, y + mote.oy[i] + mote.vy[i] * tt, mote.size[i],
				mote.size[i], alpha)
		end
	end
end

--------------------------------------------------------------------------------
-- The moments (each a function of its time t, in seconds)
--------------------------------------------------------------------------------

-- where a moment plays: the middle of the GAME'S SCREEN, Q.LINE under its top -- MelloUI:PlayArea, the rule for
-- everything placed by the screen's middle (2.1.53; the user, 2026-11-15: with Offhand's two screens the moments
-- played between the screens, the UI's middle, as the World Marker once did); the UI whole without Offhand
local function Middle()
	local l, b, w, h = MelloUI:PlayArea()
	l, b, w, h = Num(l) or 0, Num(b) or 0, Num(w) or 1024, Num(h) or 768
	return l + w / 2, b + h - Q.LINE
end

-- the count's roll: the old number up and out, the new one in from below
local function Roll(p, x, y, oldS, newS)
	local h = Q.COUNT * 1.1
	B.clip:ClearAllPoints()
	B.clip:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x, y)
	B.clip:SetSize(120, h * 1.3)
	B.old:SetText(oldS)
	B.new:SetText(newS)
	B.old:ClearAllPoints()
	B.old:SetPoint("LEFT", B.clip, "LEFT", 0, h * 0.9 * InCubic(p))
	B.old:SetAlpha(1 - OutCubic(p))
	B.old:SetShown(p < 1)
	B.new:ClearAllPoints()
	B.new:SetPoint("LEFT", B.clip, "LEFT", 0, -h * 0.9 * (1 - OutBack(p, 2.2)))
	B.new:SetAlpha(OutCubic(p))
	B.new:SetShown(p > 0)
	B.clip:Show()
end

-- the medallion moments: its bloom and halo, the medallion springing in, its ring, the band and the words.
-- `done`: the objective's (the ring closes); otherwise the progress moment, which flies to the tracker
local function StepMedal(t, done)
	local d, mx, my = B.data, B.mx, B.my
	local out = Q.OUT[B.kind]
	local exit = done and Seg(t, out, out + 0.45) or 0
	local A0 = 1 - InCubic(exit)
	local dy = 10 * OutCubic(exit)
	my = my + dy
	-- the progress moment's flight: from the medallion to the tracker's line, smaller as it goes
	local fx, fy, fs = mx, my, 1
	local flyP = (not done and B.toX) and Seg(t, Q.FLY, Q.FLY + Q.FLY_T) or 0
	if flyP > 0 then
		local q = InOutCubic(flyP)
		local cx, cy = mx + 560, my + 80
		fx = (1 - q) * (1 - q) * mx + 2 * (1 - q) * q * cx + q * q * B.toX
		fy = (1 - q) * (1 - q) * my + 2 * (1 - q) * q * cy + q * q * B.toY
		fs = 1 - 0.58 * q
		for i = 1, Q.TRAIL do   -- the trail: a few lights behind it
			local qq = InOutCubic(max(0, flyP - i * 0.028))
			local tx = (1 - qq) * (1 - qq) * mx + 2 * (1 - qq) * qq * cx + qq * qq * B.toX
			local ty = (1 - qq) * (1 - qq) * my + 2 * (1 - qq) * qq * cy + qq * qq * B.toY
			local s = 27 * (1 - i / 8)
			Put(B.trail[i], tx, ty, s, s, (flyP < 1) and 0.5 * (1 - i / 7) or 0)
		end
	else
		for i = 1, Q.TRAIL do
			B.trail[i]:Hide()
		end
	end
	local arrived = (not done and B.toX) and Seg(t, Q.FLY + Q.FLY_T, Q.FLY + Q.FLY_T + 0.55) or 0
	-- no line to fly to: it leaves in place, as the objective's does
	if not done and not B.toX then
		exit = Seg(t, out - 0.9, out - 0.45)
		A0 = 1 - InCubic(exit)
	end
	local medalA = Seg(t, 0, 0.14) * A0 * (1 - min(1, arrived * 1.5))
	-- the bloom and the ring of light opening once
	local bp = Seg(t, 0, 0.55)
	local bs = Q.R * 2 * (1.3 + 2.2 * OutCubic(bp))
	Put(B.glow, mx, my, bs, bs, 0.85 * Seg(t, 0, 0.06) * (1 - Seg(t, 0.1, 0.7)) * A0)
	local hp = Seg(t, 0.04, 0.6)
	local hs = Q.RING * 2 * (1 + 0.7 * OutCubic(hp))
	Put(B.halo, mx, my, hs, hs, 0.55 * (1 - hp) * Seg(t, 0.04, 0.1) * A0)
	-- the medallion: a spring in, then the flight's size
	local sc = (0.45 + 0.55 * Spring(Seg(t, 0, 0.34))) * fs
	local m = B.medal
	if medalA > 0.003 then
		m:ClearAllPoints()
		m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fx / sc, fy / sc)
		m:SetScale(max(0.05, sc))
		m:SetAlpha(medalA)
		m:Show()
	else
		m:Hide()
	end
	-- the ring: the counted arcs, the new one drawn in with its bright head
	local fill = InOutCubic(Seg(t, 0.34, 0.64))
	local ringA = Seg(t, 0.1, 0.3) * A0 * (1 - (flyP > 0 and InOutCubic(flyP) or 0))
	local hx, hy = DrawRing(fx, fy, d.from, fill, ringA, sc)
	if hx then
		Put(B.head, hx, hy, Q.BEAD * 7, Q.BEAD * 7, ringA)
	else
		B.head:Hide()
	end
	-- the new arc flashes as it lands
	local la = d.from + 0.5
	local landA = fill >= 1 and 0.9 * (1 - Seg(t, 0.64, 1.0)) * A0 or 0
	Put(B.land, mx + sin(la * 2 * pi / d.of) * Q.RING, my + cos(la * 2 * pi / d.of) * Q.RING, 31, 31, landA)
	if done then
		-- the ring whole: it flares, a wave opens, rays behind for a moment, sparks thrown out, the tick lands
		local f, w = Seg(t, 0.62, 1.15), Seg(t, 0.64, 1.3)
		local s1 = Q.RING * 2.3 * (1 + 0.75 * OutCubic(f))
		Put(B.flare, mx, my, s1, s1, (1 - f) * A0)
		local s2 = Q.RING * 2 * (1 + 1.5 * OutCubic(w))
		Put(B.wave, mx, my, s2, s2, 0.8 * (1 - w) * A0)
		local rp, rf = Seg(t, 0.58, 1.0), 1 - Seg(t, 1.0, 1.7)
		local s3 = Q.RING * 5.2 * (0.6 + 0.4 * OutCubic(rp))
		Put(B.rays, mx, my, s3, s3, 0.8 * rp * rf * A0, t * 0.35)
		DrawSparks(t - 0.62, mx, my, Q.RING, 140, A0)
		local cb = Seg(t, 0.72, 1.0)
		local ts = 22 * OutBack(cb, 2.4)
		if cb > 0 and ts > 0.5 then
			B.tick:ClearAllPoints()
			B.tick:SetPoint("CENTER", B.medal, "CENTER", Q.R * 0.78, -Q.R * 0.72)
			B.tick:SetSize(ts, ts)
			B.tick:SetAlpha(cb)
			B.tick:Show()
		else
			B.tick:Hide()
		end
	else
		B.flare:Hide()
		B.wave:Hide()
		B.rays:Hide()
		B.tick:Hide()
		DrawSparks(-1, 0, 0, 0, 0, 0)
		-- motes from the arc that landed, once
		DrawMotes(fill >= 1 and t - 0.62 or -1, mx + sin(la * 2 * pi / d.of) * Q.RING, my + cos(la * 2 * pi / d.of) * Q.RING, 5,
			A0 * (1 - flyP))
	end
	-- the band and the words: the objective's beside the medallion; the progress moment's count under it
	local tx = mx + Q.RING + Q.GAP
	local slide = 10 * (1 - OutCubic(Seg(t, 0.22, 0.5)))
	local wordsA = Seg(t, 0.22, 0.44) * A0
	local cp = Seg(t, B.rollAt or 0.52, (B.rollAt or 0.52) + 0.32)
	if done then
		local unf = OutCubic(Seg(t, 0.12, 0.48)) * (1 - InCubic(exit))
		B.box:ClearAllPoints()
		B.box:SetPoint("LEFT", UIParent, "BOTTOMLEFT", mx - Q.RING * 0.6, my)
		B.box:SetSize(max(1, (B.groupW - Q.RING * 0.4) * unf), 40)
		if B.band then
			B.band:SetStrength(0.8 * A0 * min(1, unf * 3))
			B.band:SetShown(unf > 0)
		end
		PutText(B.name, "LEFT", tx - slide, my + 10, wordsA)
		local swap = Seg(t, 0.98, 1.26)
		B.clip:SetAlpha(wordsA * (1 - swap))
		Roll(cp, tx - slide, my - 11, d.from .. " / " .. d.of, d.to .. " / " .. d.of)
		PutLettersAt(tx, my - 11 - 4 * (1 - OutCubic(swap)), swap * A0)
	else
		-- the chip under the medallion: the count rolling up, gone as it leaves for the tracker
		local chipA = Seg(t, 0.3, 0.5) * (1 - Seg(t, 0.9, 1.1)) * A0
		B.box:ClearAllPoints()
		B.box:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx, my - 42)
		B.box:SetSize(60, 18)
		if B.band then
			B.band:SetStrength(0.75 * chipA)
			B.band:SetShown(chipA > 0)
		end
		B.name:Hide()
		local cw = Measure(B.new, d.to .. " / " .. d.of)
		B.clip:SetAlpha(chipA)
		Roll(cp, mx - cw / 2, my - 42, d.from .. " / " .. d.of, d.to .. " / " .. d.of)
		for i = 1, (B.nLetters or 0) do
			B.letters[i]:Hide()
		end
		-- arriving: a ring of light on the tracker's line, a soft light along it
		if arrived > 0 and B.toX then
			local s = 36 * (1 + 1.2 * OutCubic(arrived))
			Put(B.arrive, B.toX, B.toY, s, s, 1 - arrived)
			Put(B.streak, B.toX + 55, B.toY, 190 * OutCubic(arrived), 12, 0.9 * (1 - arrived))
			DrawSparks(t - Q.FLY - Q.FLY_T, B.toX, B.toY, 0, 60, 1)
		else
			B.arrive:Hide()
			B.streak:Hide()
		end
	end
end

-- the quest's crest
local function StepQuest(t)
	local cx, cy = B.mx, B.my - Q.QUEST_DOWN
	local out = Q.OUT.quest
	local exit = Seg(t, out, out + 0.6)
	local A0 = 1 - InCubic(exit)
	-- the backing band under the words
	B.box:ClearAllPoints()
	B.box:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy - 84)
	B.box:SetSize(max(240, B.titleW + 80), 78)
	if B.band then
		B.band:SetStrength(0.72 * Seg(t, 0.1, 0.5) * A0)
		B.band:SetShown(true)
	end
	-- rays: they open once the crest has landed, turning slowly, then settle low
	local rIn = OutCubic(Seg(t, 0.3, 0.95))
	local rA = 0.62 * Seg(t, 0.32, 0.6) * (1 - 0.45 * Seg(t, 0.95, 1.8)) * (1 - Seg(t, out - 0.5, out + 0.1))
	local rs = 300 * (0.4 + 0.72 * rIn)
	Put(B.rays, cx, cy, rs, rs, rA, 0.25 + t * 0.1)
	local hp = Seg(t, 0.12, 0.85)
	local hs = 109 * (0.7 + 1.1 * OutExpo(hp))
	Put(B.halo, cx, cy, hs, hs, 0.42 * (1 - hp) * Seg(t, 0.12, 0.2))
	-- the crest drops in and lands; a wave where it lands
	local cs = 1.55 - 0.55 * OutCubic(Seg(t, 0.12, 0.44))
	Put(B.glow, cx, cy, 164, 164, 0.28 * Seg(t, 0.3, 0.55) * (1 - 0.6 * Seg(t, 1.2, 2.2)) * A0)
	Put(B.crest, cx, cy, 107 * cs, 107 * cs, Seg(t, 0.12, 0.3) * A0)
	local wp = Seg(t, 0.42, 1.05)
	local ws = 100 * (1 + 1.3 * OutCubic(wp))
	Put(B.wave, cx, cy, ws, ws, 0.75 * (1 - wp) * A0)
	-- the hand-in mark
	local qp = Seg(t, 0.36, 0.72)
	local qs = 47 * OutBack(qp, 2.6)
	if qp > 0 and qs > 1 then
		B.mark:ClearAllPoints()
		B.mark:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy + 2)
		B.mark:SetSize(qs, qs)
		B.mark:SetAlpha(qp * A0)
		B.mark:Show()
	else
		B.mark:Hide()
	end
	DrawSparks(t - 0.44, cx, cy, 27, 120, A0)
	-- "QUEST COMPLETE": its letters drawing together
	local ep = OutCubic(Seg(t, 0.5, 1.05))
	PutLetters(cx, cy - 58, 8.2 - 5.1 * ep, OutCubic(Seg(t, 0.5, 0.8)) * A0)
	-- the title opens from its middle, one sheen crossing its letters
	local rv = OutCubic(Seg(t, 0.6, 1.05))
	B.titleClip:ClearAllPoints()
	B.titleClip:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy - 87)
	B.titleClip:SetSize(max(1, (B.titleW + 20) * rv), Q.TITLE * 1.6)
	B.titleClip:SetAlpha(Seg(t, 0.6, 0.8) * A0)
	B.titleClip:Show()
	B.title:ClearAllPoints()
	B.title:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy - 87)
	B.title:SetAlpha(1)
	B.title:Show()
	local sp = Seg(t, 1.05, 1.65)
	if sp > 0 and sp < 1 then
		local sw = Q.TITLE * 1.4
		B.sheenWin:ClearAllPoints()
		B.sheenWin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx - B.titleW / 2 - sw + (B.titleW + 2 * sw) * InOutCubic(sp), cy - 87)
		B.sheenWin:SetSize(sw, Q.TITLE * 1.6)
		B.sheenWin:SetAlpha(0.9 * Hump(sp))
		B.sheenWin:Show()
		B.sheen:ClearAllPoints()
		B.sheen:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy - 87)
		B.sheen:SetAlpha(1)
		B.sheen:Show()
	else
		B.sheenWin:Hide()
	end
	-- two fine rules drawing outward under the title, a small star between them
	local lp = OutCubic(Seg(t, 0.78, 1.25))
	local lw = 172 * lp
	Put(B.ruleL, cx - 24 - lw / 2, cy - 109, lw, 6, 0.85 * A0)
	Put(B.ruleR, cx + 24 + lw / 2, cy - 109, lw, 6, 0.85 * A0)
	local ss = 15 * OutBack(Seg(t, 0.8, 1.1))
	Put(B.star, cx, cy - 109, ss, ss, 0.9 * A0)
	PutText(B.sub, "CENTER", cx, cy - 128, Seg(t, 1.05, 1.4) * A0)
	DrawMotes(t - 0.55, cx, cy + 9, 8, A0)
end

--------------------------------------------------------------------------------
-- Playing: one moment at a time; the rest wait (several pickups of one objective count up in one)
--------------------------------------------------------------------------------

local Next   -- (below)

local function Step(_, share)
	local t = share * Q.DUR[B.kind]
	B.t = t
	if B.kind == "quest" then
		StepQuest(t)
	else
		StepMedal(t, B.kind == "objective")
	end
end

local Done = Shared("Quest Moments: a moment ended", function()
	B.timer = nil
	HideAll()
	B.root:Hide()
	Q.playing = nil
	if B.data then
		Q.pool[#Q.pool + 1] = B.data
		B.data = nil
	end
	Next()
end)

-- the tracker's line for a quest's objective: Questie's tracker (dressed) or MelloUI's own; its place in UIParent's
-- units, or nil
local function LineAt(questID, index)
	local region
	local QL = rawget(MelloUI, "QuestieLook")
	if QL and QL.ObjectiveLine then
		region = QL.ObjectiveLine(questID, index)
	end
	if not region then
		local T = MelloUI:GetModule("QuestTracker")
		region = T and T.ObjectiveLine and T:ObjectiveLine(questID, index)
	end
	if not (region and region.IsVisible and region:IsVisible()) then
		return nil
	end
	local left, cy = Num(region:GetLeft()), select(2, region:GetCenter())
	cy = Num(cy)
	-- (a text's scale is its frame's: a region without its own answer asks its parent)
	local scaled = region.GetEffectiveScale and region or region:GetParent()
	local s, u = scaled and Num(scaled:GetEffectiveScale()), Num(UIParent:GetEffectiveScale())
	local k = s and u and u > 0 and s / u
	if not (left and cy and k) then
		return nil
	end
	return (left + 34) * k, cy * k
end

local function Start(rec)
	Build()
	HideAll()
	B.data, B.kind = rec, rec.kind
	B.mx, B.my = Middle()
	B.rollAt, B.toX, B.toY, B.t = nil, nil, nil, 0
	seed = (rec.questID or 7) * 31 + (rec.index or 1) * 7 + 1
	if rec.kind == "quest" then
		MelloUI.Icons.Set(B.mark, ICONS .. "turnin_mark", 47)
		B.title:SetText(rec.title or "")
		B.sheen:SetText(rec.title or "")
		Face(B.title, Q.TITLE)
		Face(B.sheen, Q.TITLE)
		B.titleW = Num(B.title:GetStringWidth()) or 200
		Letters(W.Tr("QUEST COMPLETE"), Q.BROW, "selectedTrim")
		B.sub:SetText(W.Tr("Ready to turn in"))
		SeedSparks(18, 110, 250, 0.5, 1.0, 9, 17)
		SeedMotes(11, 100, 27, 24, 55, 1.1, 1.9, 6, 13, 0.7)
	else
		SetMedal(rec.icon)
		LayRing(rec.of)
		local nameW = Measure(B.name, rec.name or "")
		if rec.kind == "objective" then
			MelloUI.Icons.Set(B.tick, ICONS .. "ql_completed", 22)
			Letters(W.Tr("COMPLETE"), Q.WORD, "selectedTrim")
			SeedSparks(16, 120, 260, 0.45, 0.9, 9, 16)
			B.groupW = Q.RING * 2 + Q.GAP + max(nameW, 90) + 26
			-- the group in the middle of the line
			B.mx = B.mx - B.groupW / 2 + Q.RING
		else
			Letters("", Q.WORD, "selectedTrim")
			SeedSparks(8, 60, 120, 0.3, 0.6, 6, 10)
			SeedMotes(5, 15, 6, 20, 42, 0.5, 0.9, 6, 9, 0.15)
			if not MelloUI.Anim.reduceMotion then
				B.toX, B.toY = LineAt(rec.questID, rec.index)
			end
		end
	end
	Q.playing = rec
	B.root:SetAlpha(1)
	B.root:Show()
	if MelloUI.Anim.reduceMotion then
		-- the settled moment, held and gone: nothing moving
		Step(nil, Q.STILL[B.kind] / Q.DUR[B.kind])
		B.timer = C_Timer.NewTimer(Q.OUT[B.kind], Done)
		return
	end
	MelloUI.Anim:Drive(B.root, Step, Q.DUR[B.kind], "linear", Done)
end

Next = function()
	local rec = table.remove(Q.queue, 1)
	if rec then
		Start(rec)
	end
end

-- a record from the pool (nothing made per line once a few are)
local function Record()
	local rec = table.remove(Q.pool) or {}
	rec.kind, rec.questID, rec.index, rec.name, rec.icon, rec.from, rec.to, rec.of, rec.title = nil, nil, nil, nil, nil,
		nil, nil, nil, nil
	return rec
end

local function Enqueue(rec)
	-- the same objective's count waiting already: it counts up in that one
	if rec.kind ~= "quest" then
		for _, q in ipairs(Q.queue) do
			if q.kind ~= "quest" and q.questID == rec.questID and q.index == rec.index then
				q.to = rec.to
				q.kind = rec.kind == "objective" and "objective" or q.kind
				Q.pool[#Q.pool + 1] = rec
				return
			end
		end
		local p = Q.playing
		-- the objective closing already (its count line, then its "(Complete)" line): no second one
		if p and p.kind == "objective" and p.questID == rec.questID and p.index == rec.index then
			Q.pool[#Q.pool + 1] = rec
			return
		end
		-- the one playing: still counting (before it leaves), the roll again to the new count
		if p and p.kind == "progress" and rec.kind == "progress" and p.questID == rec.questID and p.index == rec.index
			and B.data == p and not MelloUI.Anim.reduceMotion and (B.t or 0) < Q.FLY - 0.3 then
			p.from, p.to = p.to, rec.to
			B.rollAt = max(0.52, B.t or 0)
			Q.pool[#Q.pool + 1] = rec
			return
		end
	else
		-- its crest playing or waiting already (the game's line and the quest log's read both tell it): no second one
		local p = Q.playing
		local twice = p and p.kind == "quest" and p.questID == rec.questID
		-- a quest done: its objectives' moments still waiting give way to it
		for i = #Q.queue, 1, -1 do
			local q = Q.queue[i]
			if q.questID == rec.questID then
				if q.kind == "quest" then
					twice = true
				else
					Q.pool[#Q.pool + 1] = table.remove(Q.queue, i)
				end
			end
		end
		if twice then
			Q.pool[#Q.pool + 1] = rec
			return
		end
	end
	Q.queue[#Q.queue + 1] = rec
	if not Q.playing then
		Next()
	end
end

function Q.Shown()
	return Q.playing ~= nil
end

function Q.Play(kind, data)
	if type(data) ~= "table" then
		return false
	end
	local rec = Record()
	rec.kind, rec.questID, rec.index = kind, data.questID, data.index
	rec.name, rec.icon, rec.title = data.name, data.icon, data.title
	rec.of = max(1, Num(data.of) or 1)
	rec.to = min(rec.of, max(0, Num(data.to) or rec.of))
	rec.from = min(rec.to, max(0, Num(data.from) or (rec.to - 1)))
	if kind ~= "quest" and rec.from >= rec.to then
		rec.from = rec.to - 1
	end
	Enqueue(rec)
	return true
end

--------------------------------------------------------------------------------
-- Reading the game's lines: which quest line it is, the objective it counts, the quest it finishes
--------------------------------------------------------------------------------

-- the game's message names, as GetGameMessageInfo gives them, and what each says
local KINDS = {
	ERR_QUEST_ADD_ITEM_SII = "count", ERR_QUEST_ADD_KILL_SII = "count", ERR_QUEST_ADD_FOUND_SII = "count",
	ERR_QUEST_ADD_PLAYER_KILL_SII = "count", ERR_QUEST_OBJECTIVE_COMPLETE_S = "done", ERR_QUEST_COMPLETE_S = "quest",
}
Q.KINDS = KINDS
-- a "(Complete)" line names the objective by its own line ("Mudsnout Blossoms: 6/6"): read by the count lines' formats
-- (the kill's first: "%s: %d/%d" would read "... slain" as a name)
local COUNTS = { "ERR_QUEST_ADD_KILL_SII", "ERR_QUEST_ADD_ITEM_SII", "ERR_QUEST_ADD_PLAYER_KILL_SII" }

-- the game's format string as a pattern: %s a name, %d a number (its magic characters kept as they are)
local function Pattern(name)
	local p = Q.patterns[name]
	if p ~= nil then
		return p
	end
	local fmt = rawget(_G, name)
	if type(fmt) ~= "string" or fmt == "" then
		Q.patterns[name] = false
		return false
	end
	if not fmt:find("%s", 1, true) then
		-- ("Players slain: %d/%d") the objective's name is the words before the count
		Q.unnamed[name] = fmt:match("^(.-)[:%s]*%%d") or fmt
	end
	p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	p = "^" .. p:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)") .. "$"
	Q.patterns[name] = p
	return p
end
Q.Pattern = Pattern

-- a line read by one of the game's formats: its name, the count it has and the count needed (nil where it says none)
local function Read(name, text)
	local p = Pattern(name)
	if not p then
		return nil
	end
	local a, b, c = text:match(p)
	if not a then
		return nil
	end
	local unnamed = Q.unnamed[name]
	if unnamed then
		return unnamed, tonumber(a), tonumber(b)
	end
	return a, tonumber(b), tonumber(c)
end
Q.Read = Read

-- the quest log's objective a line counts: its name in the objective's text, the same number needed
local function FindObjective(name, need)
	local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and select(1, C_QuestLog.GetNumQuestLogEntries()) or 0
	n = Num(n) or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and Num(info.questID)
		if id then
			local objectives = C_QuestLog.GetQuestObjectives(id)
			for j, obj in ipairs(objectives or {}) do
				local text = Text(obj.text)
				local req = Num(obj.numRequired)
				if text and (not need or req == need) and text:find(name, 1, true) then
					return id, j, Text(obj.type), req
				end
			end
		end
	end
	return nil
end
Q.FindObjective = FindObjective

-- the medallion's picture for an objective: an item its own icon, a kill MelloUI's kill mark
local OBJ_ICON = { monster = "kill", object = "obj_use", event = "obj_explore", log = "obj_explore" }
local function IconFor(kind, name)
	if kind == "item" and C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, name)
		icon = ok and Num(icon)
		if icon then
			return icon
		end
		return "loot"
	end
	return OBJ_ICON[kind] or "quest_mark"
end

-- the quest of the log with this title
local function FindQuest(title)
	local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and Num(select(1, C_QuestLog.GetNumQuestLogEntries())) or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and Num(info.questID)
		if id and Text(info.title) == title then
			return id
		end
	end
	return nil
end

-- a quest line handed to the game: kept with its reason for /mello moments why (records in a ring: nothing made once
-- the ring is full); false back, as the line goes to the game
local WHY_MAX = 8
local function Why(name, message, reason)
	local i = Q.whyN % WHY_MAX + 1
	Q.whyN = Q.whyN + 1
	local r = Q.why[i] or {}
	Q.why[i] = r
	r.name, r.message, r.reason = name, message, reason
	return false
end

-- "Humbert's Sword completed.": its crest plays now, and the quest log's read after it plays no second one
local function QuestLine(title, name, message)
	if not M.db.quest then
		return Why(name, message, "Quest Done is off")
	end
	local id = FindQuest(title)
	if not id then
		return Why(name, message, "no quest of that title in the log")
	end
	Q.complete[id] = true
	Q.Play("quest", { questID = id, title = title })
	return true
end

-- one of the game's info lines: true when a moment plays it (the line kept back)
function Q.Line(messageType, message)
	if not (M.isEnabled and M.db) or Secret(message) or Secret(messageType) or type(message) ~= "string" then
		return false
	end
	local ok, name = pcall(rawget(_G, "GetGameMessageInfo") or error, messageType)
	name = ok and Text(name)
	local kind = name and KINDS[name]
	if not kind then
		return false
	end
	local what, have, need = Read(name, message)
	if not what then
		return Why(name, message, "not read by the game's format")
	end
	if kind == "quest" then
		return QuestLine(what, name, message)
	end
	if kind == "done" then
		for _, count in ipairs(COUNTS) do
			local n, h, w = Read(count, what)
			if n then
				what, have, need = n, h, w
				break
			end
		end
	end
	local questID, index, objType, req = FindObjective(what, need)
	if not questID then
		return Why(name, message, "no objective of that name in the log")
	end
	need = need or req or 1
	have = have or need
	local moment = have >= need and "objective" or "progress"
	if not M.db[moment] then
		return Why(name, message, moment == "objective" and "Objective Done is off" or "Item Picked Up is off")
	end
	Q.Play(moment, { questID = questID, index = index, name = what, icon = IconFor(objType, what), from = have - 1,
		to = have, of = need })
	return true
end

-- the sound the game's frame plays with the line it shows (kept for a line kept back)
local function Sound(messageType)
	local ok, _, soundKitID, voiceID = pcall(rawget(_G, "GetGameMessageInfo") or error, messageType)
	if ok then
		MelloUI:PlayGameSound(soundKitID, voiceID)
	end
end

local OnEvent   -- (below)

-- its events' frame: made the first time it is switched on (nothing made at load), its one script set then
local function Events()
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		Perf.SetScript(eventFrame, "OnEvent", OnEvent)
	end
	return eventFrame
end

-- the info event back to the game's frame, or taken from it
local function Take(on)
	local ef = UIErrorsFrame
	if not ef then
		return
	end
	if on and not Q.took then
		if ef:IsEventRegistered("UI_INFO_MESSAGE") then
			ef:UnregisterEvent("UI_INFO_MESSAGE")
			Events():RegisterEvent("UI_INFO_MESSAGE")
			Q.took = true
		end
	elseif not on and Q.took then
		eventFrame:UnregisterEvent("UI_INFO_MESSAGE")
		ef:RegisterEvent("UI_INFO_MESSAGE")
		Q.took = false
	end
end

-- the quest log read again (after its updates settle): a quest just finished plays its crest
local Scan = Shared("Quest Moments: the quest log read", function()
	Q.scanQueued = false
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.IsComplete) then
		return
	end
	local n = Num(select(1, C_QuestLog.GetNumQuestLogEntries())) or 0
	local mark = not Q.mark
	Q.mark = mark
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and Num(info.questID)
		if id then
			local done = C_QuestLog.IsComplete(id) == true
			if Q.ready and Q.complete[id] == false and done and M.db and M.db.quest then
				Q.Play("quest", { questID = id, title = Text(info.title) or "" })
			end
			Q.complete[id] = done
			Q.seen[id] = mark
		end
	end
	for id in pairs(Q.complete) do
		if Q.seen[id] ~= mark then
			Q.complete[id], Q.seen[id] = nil, nil
		end
	end
	Q.ready = true
end)

OnEvent = Shared("Quest Moments: its events", function(_, event, messageType, message, ...)
	if event == "QUEST_LOG_UPDATE" then
		if not Q.scanQueued then
			Q.scanQueued = true
			C_Timer.After(0.15, Scan)
		end
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		Q.ready = false
		C_Timer.After(2, Scan)
		return
	end
	-- UI_INFO_MESSAGE: a quest line a moment plays is kept back (its sound played); the rest to the game's frame
	if Q.Line(messageType, message) then
		Sound(messageType)
		return
	end
	local ef = UIErrorsFrame
	local handler = ef and ef:GetScript("OnEvent")
	if not handler then
		return
	end
	if Secret(message) or Secret(messageType) then
		pcall(handler, ef, event, messageType, message, ...)   -- (ErrorFilter's: a secret never raises)
		return
	end
	handler(ef, event, messageType, message, ...)
end)

--------------------------------------------------------------------------------
-- The Animations page's Play: a moment from your own quest log (else a sample)
--------------------------------------------------------------------------------

local SAMPLE = { name = "Mudsnout Blossoms", icon = "loot", from = 2, to = 3, of = 6, title = "Humbert's Sword" }

local function Sample(kind)
	local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and Num(select(1, C_QuestLog.GetNumQuestLogEntries())) or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and Num(info.questID)
		if id then
			if kind == "quest" then
				return { questID = id, title = Text(info.title) or SAMPLE.title }
			end
			for j, obj in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
				local text, have, need = Text(obj.text), Num(obj.numFulfilled), Num(obj.numRequired)
				if text and have and need and need > 0 and have < need then
					local name = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("[:%s]*%d+%s*/%s*%d+%s*$", "")
					local to = kind == "objective" and need or have + 1
					return { questID = id, index = j, name = name, icon = IconFor(Text(obj.type), name), from = to - 1,
						to = to, of = need }
				end
			end
		end
	end
	local s = {}
	for k, v in pairs(SAMPLE) do
		s[k] = v
	end
	if kind == "objective" then
		s.icon, s.from, s.to = "kill", 5, 6
		s.name = W and W.Tr("Hillsbrad Farmhand slain") or "Hillsbrad Farmhand slain"
	end
	return s
end

M.Plays = {
	progress = function()
		if not M.isEnabled then
			return false
		end
		Q.Play("progress", Sample("progress"))
		return true, Q.DUR.progress
	end,
	objective = function()
		if not M.isEnabled then
			return false
		end
		Q.Play("objective", Sample("objective"))
		return true, Q.DUR.objective
	end,
	quest = function()
		if not M.isEnabled then
			return false
		end
		Q.Play("quest", Sample("quest"))
		return true, Q.DUR.quest
	end,
}

-- /mello moments item | objective | quest | all (the Animations page's Plays from the chat line)
M.SlashWords = {
	item = M.Plays.progress,
	objective = M.Plays.objective,
	quest = M.Plays.quest,
	all = function()
		M.Plays.progress()
		M.Plays.objective()
		M.Plays.quest()
	end,
	-- the last quest lines handed to the game, and why (to send with /mellolog)
	why = function()
		MelloUI:Print("Quest Moments: the game's info lines %s", Q.took and "come to Quest Moments"
			or "are NOT taken: the game's frame still has them")
		local n = min(Q.whyN, WHY_MAX)
		if n == 0 then
			MelloUI:Print("Quest Moments: every quest line since the login played as a moment")
		end
		for k = Q.whyN - n + 1, Q.whyN do
			local r = Q.why[(k - 1) % WHY_MAX + 1]
			MelloUI:Print("  %s | %s | %s", tostring(r.name), tostring(r.message), tostring(r.reason))
		end
	end,
}

--------------------------------------------------------------------------------
-- Enable / disable
--------------------------------------------------------------------------------

function M:OnEnable(db)
	self.db = db
	Take(true)
	Events():RegisterEvent("QUEST_LOG_UPDATE")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	if not Q.ready then
		C_Timer.After(2, Scan)
	end
end

function M:OnDisable()
	Take(false)
	if eventFrame then
		eventFrame:UnregisterEvent("QUEST_LOG_UPDATE")
		eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
	end
	if B.root then
		if B.timer then
			B.timer:Cancel()
			B.timer = nil
		end
		MelloUI.Anim:Stop(B.root, "drive")
		HideAll()
		B.root:Hide()
	end
	Q.playing = nil
	for i = #Q.queue, 1, -1 do
		Q.pool[#Q.pool + 1] = table.remove(Q.queue, i)
	end
end

function M:OnSettingChanged(_, _, db)
	self.db = db
end

-- (the tests')
Q.B, Q.M, Q.Take, Q.Scan, Q.Step = B, M, Take, Scan, Step
