--------------------------------------------------------------------------------
-- MelloUI - the Supporters page's banner hall (2.1.37; the user, 2026-11-10: "reworking the supporters page, with
-- the 3 banners ... the highest quality page we can make, animated", then "Build, lets see how it works ingame";
-- the sketch: artifact AF6nA2ekLUxDAFmZbP5kCe, Workspace/BuildData/output/supporters_banners). Three cloth banners on
-- gold rods, one a tier: the Champions left, the Legends in the middle and tallest, the Supporters right, the names
-- written on them as text (sharp, every alphabet). Made on the page's first open (CONFIG.BuildSupportersPage,
-- Core/Config.lua): nothing at login.
--   MelloUI.SupportersHall.Build(parent, width, data, skin) -> height   the thanks, the invite line with Patreon
--       and Discord (a copy box: the game opens no web page), the hall and the "As of" line, laid from parent's top;
--       data: MelloUI_Supporters (Media/SupportersData.lua)
-- Its motion is MelloUI.Anim's, so Reduce Motion shows the finished page at once:
--   the opening, each time the page shows: the banners unroll from their rods (the Legends first), each crest
--       lights as its banner lands, then its names fade in one by one (one Drive, two to four seconds)
--   then only drifting, while the page shows: folds of light across each cloth, the tassels swing, embers rise
--       behind, a glint runs along a rod now and then, the Legends' rays turn (AnimationGroups, stopped on hide)
-- The art (Media/Textures/Supporters; drawn from the sketch's own code by Workspace/BuildData/output/
-- supporters_banners/tex_export.html, 2 px a unit): banner_<tier>.tga 512 x 512 (the top slice at y 0, the tails
-- and their fringe at 320, the body row at 504; a banner is the three, the body stretched between), crest_<tier>.tga,
-- banner_parts.tga (rod, finial, peg, glint, tassel, embers, glows, rays, rolls) and banner_folds.tga (tiles across).
--------------------------------------------------------------------------------

local ADDON, ns = ...
local MelloUI = ns.MelloUI
local W = MelloUI.Widgets
local Anim = MelloUI.Anim
local Perf = MelloUI.Perf:Scope("SupportersHall")

local ART = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Textures\\Supporters\\"
local FONTS = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Fonts\\"
local PARTS = ART .. "banner_parts"
local floor, max, min, exp = math.floor, math.max, math.min, math.exp

local Hall = {}
MelloUI.SupportersHall = Hall

-- the hall's measures (UI units; the sketch's)
Hall.T = {
	CLOTH_TOP = 27,   -- the cloth's top below the hall's (its sleeve round the rod)
	ROD_Y = 35, PEG_Y = 6, ROD_OVER = 8, ROD_H = 9,
	SPREAD = 268,     -- the side banners' middles from the hall's middle (more when a wide banner needs the room)
	ROD_GAP = 14,     -- the least room between two rods' finials
	FINIAL = 10,      -- a finial's reach past its rod's end
	FRINGE = 16,      -- the fringe under the tails
	TWO_W = 262,      -- the Supporters banner with its names in two columns (over 7 names)
	EMBERS = 18,
	BELOW = 44,       -- the hall's room under the longest banner (the tassels)
}
local T = Hall.T

-- the tiers left to right; slot: their place in banner_parts' rows (legend, champion, supporter)
Hall.TIERS = {
	{ key = "champion", heading = "Champions", w = 204, art = 210, min = 322, crest = 66, tail = 44, slot = 1,
		face = FONTS .. "AlegreyaSC\\AlegreyaSC-Bold.ttf", size = 18, line = 26, ink = "text", glow = .08 },
	{ key = "legend", heading = "Legends", w = 232, art = 240, min = 360, crest = 80, tail = 54, slot = 0,
		face = FONTS .. "Cinzel\\Cinzel-Bold.ttf", size = 22, line = 33, ink = "selectedTrim", glow = .16, rays = true },
	{ key = "supporter", heading = "Supporters", w = 204, art = 210, min = 322, crest = 66, tail = 44, slot = 2,
		face = FONTS .. "Alegreya\\Alegreya-Bold.ttf", size = 17, line = 23, ink = "text", glow = .08 },
}
-- the opening: each tier's start and how long it unrolls
local START = { legend = .15, champion = .45, supporter = .75 }

local TEXT = {
	thanks = "Thank you, all of you",
	ready = "The hall is ready",
	free = "MelloUI is free for everyone and always will be. These are the people who help keep it going.",
	freeEmpty = "MelloUI is free for everyone and always will be. The people who help keep it going will hang their names here.",
	invite = "Want your name on a banner? Support MelloUI on Patreon, and come say hello on Discord.",
	waiting = "Waiting for its first name",
	asOf = "As of %s",
}
-- the two addresses, shown in the copy box
Hall.LINKS = {
	{ name = "Patreon", url = "https://www.patreon.com/Mello_UI" },
	{ name = "Discord", url = "https://discord.gg/gdpQ6ep7bW" },
}

-- a region of banner_parts (512 x 512) in texture coordinates
local function Part(tex, x, y, w, h, flip)
	tex:SetTexture(PARTS)
	if flip then
		tex:SetTexCoord((x + w) / 512, x / 512, y / 512, (y + h) / 512)
	else
		tex:SetTexCoord(x / 512, (x + w) / 512, y / 512, (y + h) / 512)
	end
end

-- a text's face (MelloUI:SetFace: the other alphabets kept); a file not readable yet is tried again once
local function Face(fs, file, size)
	if not MelloUI:SetFace(fs, file, size) then
		C_Timer.After(.2, function()
			MelloUI:SetFace(fs, file, size)
		end)
	end
end

local function Clamp(v)
	return v < 0 and 0 or (v > 1 and 1 or v)
end
local function EaseOut(p)
	return 1 - (1 - p) ^ 3
end

-- the copy box for Patreon or Discord (the button's own `link`)
local CopyClick = Perf.Shared("OnClick on the Supporters page's links", function(button)
	local link = button.mellouiLink
	if link then
		MelloUI:ShowText(link.name, link.url)
	end
end, "script")

--------------------------------------------------------------------------------
-- One banner
--------------------------------------------------------------------------------

-- the banner's measures from its names
local function Measure(t, names)
	local b = { t = t, key = t.key, names = names }
	b.two = t.key == "supporter" and #names > 7
	b.w = b.two and T.TWO_W or t.w
	b.crestY = 32 + t.crest / 2
	b.titleY = 32 + t.crest + 22
	b.ruleY = 32 + t.crest + 32
	b.topH = b.ruleY + 12
	b.botH = t.tail + 30
	b.namesTop = b.ruleY + 18
	b.line = b.two and 21 or t.line
	b.size = b.two and 14.5 or t.size
	local rows = b.two and math.ceil(#names / 2) or #names
	b.L = max(t.min, math.ceil(b.namesTop + max(rows, 1) * b.line + 16 + t.tail))
	return b
end

-- a looping group of one animation kind on `region`
local function Loop(region, looping)
	return Anim:Group(region, looping or "REPEAT")
end

-- the banner's frames and art in the hall, its middle at `cx`
local function MakeBanner(hall, b, cx, top)
	local t, w, L = b.t, b.w, b.L
	local tex = ART .. "banner_" .. t.key
	local tw = t.art * 2 / 512   -- (the art's width in its sheet, drawn 2 px a unit; the banner's own width stretches it)
	b.cx = cx
	-- the rod behind the cloth, its finials, cords, peg and glint in front (a frame over the banner)
	local x0, x1 = cx - w / 2 - T.ROD_OVER, cx + w / 2 + T.ROD_OVER
	local rod = hall:CreateTexture(nil, "BORDER")
	Part(rod, 0, 1, 256, 14)
	rod:SetSize(x1 - x0 + T.ROD_H, T.ROD_H)
	rod:SetPoint("TOPLEFT", hall, "TOPLEFT", x0 - T.ROD_H / 2, -(T.ROD_Y - T.ROD_H / 2))
	b.holder = CreateFrame("Frame", nil, hall)
	b.holder:SetFrameLevel(hall:GetFrameLevel() + 2)
	b.holder:SetSize(w, L + T.FRINGE)
	b.holder:SetPoint("TOPLEFT", hall, "TOPLEFT", cx - w / 2, -T.CLOTH_TOP)
	b.front = CreateFrame("Frame", nil, hall)
	b.front:SetFrameLevel(hall:GetFrameLevel() + 4)
	b.front:SetAllPoints(hall)
	for k = 0, 1 do
		local cord = b.front:CreateLine(nil, "ARTWORK")
		cord:SetTexture(PARTS)
		cord:SetTexCoord(0, 256 / 512, 4 / 512, 9 / 512)
		cord:SetThickness(2)
		cord:SetStartPoint("TOPLEFT", hall, cx, -(T.PEG_Y + 3))
		cord:SetEndPoint("TOPLEFT", hall, k == 0 and x0 + 12 or x1 - 12, -T.ROD_Y)
	end
	local peg = b.front:CreateTexture(nil, "OVERLAY")
	Part(peg, 288, 0, 16, 16)
	peg:SetSize(8, 8)
	peg:SetPoint("CENTER", hall, "TOPLEFT", cx, -T.PEG_Y)
	local finL = b.front:CreateTexture(nil, "OVERLAY")
	Part(finL, 256, 0, 32, 32, true)
	finL:SetSize(16, 16)
	finL:SetPoint("TOPLEFT", hall, "TOPLEFT", x0 - 3 - 9, -(T.ROD_Y - 8))
	local finR = b.front:CreateTexture(nil, "OVERLAY")
	Part(finR, 256, 0, 32, 32)
	finR:SetSize(16, 16)
	finR:SetPoint("TOPLEFT", hall, "TOPLEFT", x1 + 3 - 7, -(T.ROD_Y - 8))
	local glint = b.front:CreateTexture(nil, "OVERLAY")
	Part(glint, 320, 0, 64, 32)
	glint:SetBlendMode("ADD")
	glint:SetSize(32, 12)
	glint:SetPoint("CENTER", hall, "TOPLEFT", x0, -T.ROD_Y)
	glint:SetAlpha(0)
	local g = Loop(glint)
	local a1 = g:CreateAnimation("Alpha")
	a1:SetFromAlpha(0)
	a1:SetToAlpha(.9)
	a1:SetDuration(.15)
	a1:SetOrder(1)
	local mv = g:CreateAnimation("Translation")
	mv:SetOffset(x1 - x0, 0)
	mv:SetDuration(1)
	mv:SetSmoothing("IN_OUT")
	mv:SetOrder(1)
	local a2 = g:CreateAnimation("Alpha")
	a2:SetFromAlpha(.9)
	a2:SetToAlpha(0)
	a2:SetStartDelay(.8)
	a2:SetDuration(.2)
	a2:SetOrder(1)
	local hold = g:CreateAnimation("Alpha")   -- (then nothing for 8 to 12 s)
	hold:SetFromAlpha(0)
	hold:SetToAlpha(0)
	hold:SetDuration(8 + 4 * math.random())
	hold:SetOrder(2)
	b.loops = { g }

	-- the cloth, in a frame that clips it while it unrolls
	b.clip = CreateFrame("Frame", nil, b.holder)
	b.clip:SetClipsChildren(true)
	b.clip:SetPoint("TOPLEFT", b.holder, "TOPLEFT", 0, 0)
	b.clip:SetSize(w, L + T.FRINGE)
	local cloth = CreateFrame("Frame", nil, b.clip)
	cloth:SetPoint("TOPLEFT", b.clip, "TOPLEFT", 0, 0)
	cloth:SetSize(w, L + T.FRINGE)
	b.cloth = cloth
	local topT = cloth:CreateTexture(nil, "BACKGROUND")
	topT:SetTexture(tex)
	topT:SetTexCoord(0, tw, 0, b.topH * 2 / 512)
	topT:SetPoint("TOPLEFT")
	topT:SetPoint("TOPRIGHT")
	topT:SetHeight(b.topH)
	local botT = cloth:CreateTexture(nil, "BACKGROUND")
	botT:SetTexture(tex)
	botT:SetTexCoord(0, tw, 320 / 512, (320 + b.botH * 2) / 512)
	botT:SetPoint("BOTTOMLEFT")
	botT:SetPoint("BOTTOMRIGHT")
	botT:SetHeight(b.botH)
	local body = cloth:CreateTexture(nil, "BACKGROUND")
	body:SetTexture(tex)
	body:SetTexCoord(0, tw, 505 / 512, 510 / 512)
	body:SetPoint("TOPLEFT", topT, "BOTTOMLEFT")
	body:SetPoint("BOTTOMRIGHT", botT, "TOPRIGHT")
	-- the folds of light drifting across (twice its width, one width a loop: seamless)
	local fclip = CreateFrame("Frame", nil, cloth)
	fclip:SetClipsChildren(true)
	fclip:SetPoint("TOPLEFT", cloth, "TOPLEFT", 0, -22)
	fclip:SetPoint("BOTTOMRIGHT", cloth, "BOTTOMRIGHT", 0, T.FRINGE + t.tail + 2)
	local folds = fclip:CreateTexture(nil, "ARTWORK")
	folds:SetTexture(ART .. "banner_folds", "REPEAT", "REPEAT")
	folds:SetTexCoord(0, 2, 0, 1)
	folds:SetPoint("TOPLEFT", fclip, "TOPLEFT", 0, 0)
	folds:SetPoint("BOTTOMLEFT", fclip, "BOTTOMLEFT", 0, 0)
	folds:SetWidth(w * 2)
	local fg = Loop(folds)
	local drift = fg:CreateAnimation("Translation")
	drift:SetOffset(-w, 0)
	drift:SetDuration(14 + 3 * t.slot)
	b.loops[#b.loops + 1] = fg
	-- the crest, its flare, the title, the names
	local crest = cloth:CreateTexture(nil, "ARTWORK", nil, 2)
	crest:SetTexture(ART .. "crest_" .. t.key)
	crest:SetSize(t.crest, t.crest)
	crest:SetPoint("CENTER", cloth, "TOP", 0, -b.crestY)
	b.flare = cloth:CreateTexture(nil, "ARTWORK", nil, 3)
	Part(b.flare, t.slot * 128, 128, 128, 128)
	b.flare:SetBlendMode("ADD")
	b.flare:SetSize(t.crest * 1.9, t.crest * 1.9)
	b.flare:SetPoint("CENTER", crest, "CENTER")
	b.flare:SetAlpha(.25)
	local title = W.Text(cloth, nil, W.Tr(t.heading), "selectedTrim")
	Face(title, FONTS .. "Cinzel\\Cinzel-Bold.ttf", 14)
	title:SetText(string.upper(W.Tr(t.heading) or t.heading))
	title:SetJustifyH("CENTER")
	title:SetPoint("BOTTOM", cloth, "TOP", 0, -(b.titleY + 3))
	b.nameFs = {}
	local names = b.names
	if #names == 0 then
		local wait = W.Text(cloth, nil, W.Tr(TEXT.waiting), "text")
		Face(wait, FONTS .. "Fredoka\\Fredoka-Regular.ttf", 13)
		wait:SetJustifyH("CENTER")
		wait:SetWidth(w - 30)
		wait:SetPoint("TOP", cloth, "TOP", 0, -(b.ruleY + 22))
		b.wait = wait
	end
	local colW = b.two and (w - 28) / 2 or w - 40
	for i, name in ipairs(names) do
		local col = b.two and (i - 1) % 2 or 0
		local row = b.two and floor((i - 1) / 2) or i - 1
		-- (a name as it is, never looked up in the language; a pipe would start the game's markup)
		local fs = W.Text(cloth, nil, (tostring(name):gsub("|", "||")), t.ink)
		Face(fs, t.face, b.size)
		-- (a long name shrunk to fit, down to 80 %; past that the game cuts it with "...")
		local wide = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
		if type(wide) == "number" and wide > colW - 4 then
			Face(fs, t.face, max(b.size * .8, floor(b.size * (colW - 4) / wide * 10) / 10))
		end
		fs:SetJustifyH("CENTER")
		fs:SetWidth(colW - 4)
		fs:SetWordWrap(false)
		fs:SetMaxLines(1)
		local x = b.two and (col == 0 and 14 + colW / 2 or w - 14 - colW / 2) or w / 2
		fs.hallX, fs.hallY = x, b.namesTop + row * b.line + (b.line - b.size) / 2
		fs:SetPoint("TOP", cloth, "TOPLEFT", fs.hallX, -fs.hallY)
		b.nameFs[i] = fs
	end
	-- while it unrolls: the roll at its foot
	b.roll = b.holder:CreateTexture(nil, "OVERLAY")
	Part(b.roll, 256, 256 + t.slot * 32, 256, 24)
	b.roll:SetPoint("LEFT", b.clip, "BOTTOMLEFT", -2, 0)
	b.roll:SetPoint("RIGHT", b.clip, "BOTTOMRIGHT", 2, 0)
	b.roll:SetHeight(8)
	b.roll:Hide()
	-- the tassels at the two tails, swinging from their tops
	b.tassels = {}
	for k = 0, 1 do
		local ts = b.holder:CreateTexture(nil, "ARTWORK")
		Part(ts, 384, 0, 32, 64)
		local big = t.key == "legend" and 1.15 or 1
		ts:SetSize(16 * big, 32 * big)
		ts:SetPoint("TOP", b.holder, "TOPLEFT", k == 0 and 1.5 or w - 1.5, -(L - 1.5))
		local sg = Loop(ts, "BOUNCE")
		local swing = sg:CreateAnimation("Rotation")
		swing:SetOrigin("TOP", 0, 0)
		swing:SetDegrees(k == 0 and 6 or -5)
		swing:SetDuration(1.5 + .2 * k + .1 * t.slot)
		swing:SetSmoothing("IN_OUT")
		b.loops[#b.loops + 1] = sg
		b.tassels[#b.tassels + 1] = ts
	end
	-- behind it: its tier's glow, and the Legends' rays turning slowly
	b.glow = hall:CreateTexture(nil, "BACKGROUND", nil, 1)
	Part(b.glow, t.slot * 128, 128, 128, 128)
	b.glow:SetBlendMode("ADD")
	b.glow:SetSize(500, 500)
	b.glow:SetPoint("CENTER", hall, "TOPLEFT", cx, -(T.CLOTH_TOP + 110))
	b.glow:SetAlpha(t.glow)
	if t.rays then
		b.rays = hall:CreateTexture(nil, "BACKGROUND", nil, 2)
		Part(b.rays, 0, 256, 256, 256)
		b.rays:SetBlendMode("ADD")
		b.rays:SetSize(680, 680)
		b.rays:SetPoint("CENTER", hall, "TOPLEFT", cx, -(T.CLOTH_TOP + 70))
		b.rays:SetAlpha(.08)
		local rg = Loop(b.rays)
		local turn = rg:CreateAnimation("Rotation")
		turn:SetDegrees(-360)
		turn:SetDuration(180)
		b.loops[#b.loops + 1] = rg
	end
	b.start = START[t.key] or .15
	b.dur = t.key == "legend" and 1.15 or 1
	b.landed = b.start + b.dur
	b.namesAt = b.landed + .1
	b.stagger = #names > 0 and min(.11, 1.2 / #names) or 0
	b.done = b.namesAt + #names * b.stagger + .5
	return b
end

--------------------------------------------------------------------------------
-- The opening (one Drive over the whole hall) and the drifting (the loops)
--------------------------------------------------------------------------------

-- the opening at `t` seconds: the clips grown, the rolls, the flares, the tassels, the names
local function Lay(hall, t)
	for _, b in ipairs(hall.banners) do
		local full = b.L + T.FRINGE
		local p = Clamp((t - b.start) / b.dur)
		b.clip:SetHeight(max(.01, EaseOut(p) * full))
		if p > 0 and p < 1 then
			b.roll:SetHeight(5 + 12 * (1 - p))
			b.roll:Show()
		else
			b.roll:Hide()
		end
		b.glow:SetAlpha(b.t.glow * p)
		if b.rays then
			b.rays:SetAlpha(.08 * p)
		end
		local landed = t >= b.landed
		b.flare:SetAlpha(landed and (.25 + .55 * exp(-3 * (t - b.landed))) or 0)
		for _, ts in ipairs(b.tassels) do
			ts:SetAlpha(landed and 1 or 0)
		end
		if b.wait then
			b.wait:SetAlpha(.62 * Clamp((t - b.namesAt) / .6))
		end
		for i, fs in ipairs(b.nameFs) do
			local a = EaseOut(Clamp((t - b.namesAt - (i - 1) * b.stagger) / .5))
			fs:SetAlpha(a)
			fs:SetPoint("TOP", b.cloth, "TOPLEFT", fs.hallX, -(fs.hallY + (1 - a) * 6))
		end
	end
end

local function Step(hall, v)
	Lay(hall, v * hall.total)
end

local function Opening(hall)
	if not hall.banners then
		return
	end
	Lay(hall, 0)
	Anim:Drive(hall, Step, hall.total, "linear")
end

local function Shown(hall)
	Opening(hall)
	for _, b in ipairs(hall.banners) do
		for _, g in ipairs(b.loops) do
			Anim:PlayGroup(g)
		end
	end
	for _, e in ipairs(hall.embers) do
		Anim:PlayGroup(e)
	end
end
local HallShown = Perf.Shared("OnShow on the Supporters page's hall", Shown, "script")

local HallHidden = Perf.Shared("OnHide on the Supporters page's hall", function(hall)
	Anim:Stop(hall, "drive")
	Lay(hall, hall.total)
	for _, b in ipairs(hall.banners) do
		for _, g in ipairs(b.loops) do
			Anim:StopGroup(g)
		end
	end
	for _, e in ipairs(hall.embers) do
		Anim:StopGroup(e)
	end
end, "script")

-- the embers: a few sprites rising behind the banners in their tiers' colours, each on its own path and pace
local function MakeEmbers(hall, height)
	hall.embers = {}
	local banners = hall.banners
	for i = 1, T.EMBERS do
		local r = math.random()
		local b = r < .45 and banners[2] or (r < .72 and banners[1] or banners[3])
		local e = hall:CreateTexture(nil, "BACKGROUND", nil, 3)
		Part(e, b.t.slot * 32, 64, 32, 32)
		e:SetBlendMode("ADD")
		local size = 4 + 3 * math.random()
		e:SetSize(size, size)
		e:SetPoint("CENTER", hall, "TOPLEFT", b.cx + (math.random() - .5) * (b.w + 90), -(height - 4))
		e:SetAlpha(0)
		local g = Loop(e)
		local life = 4 + 4.5 * math.random()
		local rise = g:CreateAnimation("Translation")
		rise:SetOffset((math.random() - .5) * 30, height * (.55 + .4 * math.random()))
		rise:SetDuration(life)
		rise:SetStartDelay(4 * math.random())
		rise:SetOrder(1)
		local fadeIn = g:CreateAnimation("Alpha")
		fadeIn:SetFromAlpha(0)
		fadeIn:SetToAlpha(.85)
		fadeIn:SetDuration(life * .25)
		fadeIn:SetStartDelay(rise:GetStartDelay())
		fadeIn:SetOrder(1)
		local fadeOut = g:CreateAnimation("Alpha")
		fadeOut:SetFromAlpha(.85)
		fadeOut:SetToAlpha(0)
		fadeOut:SetStartDelay(rise:GetStartDelay() + life * .55)
		fadeOut:SetDuration(life * .45)
		fadeOut:SetOrder(1)
		hall.embers[i] = g
	end
end

--------------------------------------------------------------------------------
-- The page's content
--------------------------------------------------------------------------------

function Hall.Build(parent, width, data, skin)
	data = type(data) == "table" and data or {}
	local any = false
	for _, t in ipairs(Hall.TIERS) do
		local list = data[t.key]
		if type(list) == "table" and #list > 0 then
			any = true
		end
	end
	-- the thanks and the invite (on the section itself: the parchment's ink reaches them in the kit look)
	local y = 10
	local big = W.Text(parent, nil, W.Tr(any and TEXT.thanks or TEXT.ready), "selectedTrim")
	Face(big, FONTS .. "Fredoka\\Fredoka-SemiBold.ttf", 26)
	big:SetJustifyH("CENTER")
	big:SetWidth(width)
	big:SetPoint("TOP", parent, "TOP", 0, -y)
	y = y + 34
	local small = W.Text(parent, nil, W.Tr(any and TEXT.free or TEXT.freeEmpty), "text")
	small:SetJustifyH("CENTER")
	small:SetWidth(width - 60)
	small:SetWordWrap(true)
	small:SetPoint("TOP", parent, "TOP", 0, -y)
	y = y + max(16, floor((small:GetStringHeight() or 16) + .5)) + 6
	local invite = W.Text(parent, nil, W.Tr(TEXT.invite), "text")
	invite:SetJustifyH("CENTER")
	invite:SetWidth(width - 60)
	invite:SetWordWrap(true)
	invite:SetPoint("TOP", parent, "TOP", 0, -y)
	y = y + max(16, floor((invite:GetStringHeight() or 16) + .5)) + 6
	local prev
	for i, link in ipairs(Hall.LINKS) do
		local bt = W.Button(parent, link.name, 100, skin, { onClick = CopyClick })
		bt.mellouiLink = link
		if i == 1 then
			bt:SetPoint("TOPRIGHT", parent, "TOP", -4, -y)
		else
			bt:SetPoint("LEFT", prev, "RIGHT", 8, 0)
		end
		prev = bt
	end
	y = y + 22 + 8

	-- the hall, laid at its own size (the Legends in the middle, the rods SPREAD apart or as far as a wide Supporters
	-- banner needs to keep them clear) and scaled down to the page only when the page is narrower
	local hall = CreateFrame("Frame", nil, parent)
	hall.banners = {}
	local maxL = 0
	for i, t in ipairs(Hall.TIERS) do
		local list = type(data[t.key]) == "table" and data[t.key] or {}
		local b = Measure(t, list)
		hall.banners[i] = b
		maxL = max(maxL, b.L)
	end
	local bs = hall.banners
	local function Half(b)
		return b.w / 2 + T.ROD_OVER + T.FINIAL
	end
	local spreadL = max(T.SPREAD, Half(bs[1]) + T.ROD_GAP + Half(bs[2]))
	local spreadR = max(T.SPREAD, Half(bs[2]) + T.ROD_GAP + Half(bs[3]))
	local mid = max(spreadL + Half(bs[1]), spreadR + Half(bs[3])) + 4
	local scale = min(1, width / (2 * mid))
	local height = T.CLOTH_TOP + maxL + T.BELOW
	hall:SetScale(scale)
	hall:SetSize(2 * mid, height)
	hall:SetPoint("TOP", parent, "TOP", 0, -y / scale)   -- (offsets in the hall's own, scaled units)
	MakeBanner(hall, bs[1], mid - spreadL, height)
	MakeBanner(hall, bs[2], mid, height)
	MakeBanner(hall, bs[3], mid + spreadR, height)
	local total = 0
	for _, b in ipairs(bs) do
		total = max(total, b.done)
	end
	hall.total = total
	MakeEmbers(hall, height)
	y = y + floor(height * scale + .5)

	-- as of
	if type(data.updated) == "string" and data.updated ~= "" then
		local when = W.Text(parent, nil, MelloUI.Lang.F(TEXT.asOf, data.updated), "text")
		when:SetAlpha(.7)
		when:SetJustifyH("CENTER")
		when:SetWidth(width)
		when:SetPoint("TOP", parent, "TOP", 0, -y)
		y = y + 18
	end

	Lay(hall, total)
	Perf.HookScript(hall, "OnShow", HallShown)
	Perf.HookScript(hall, "OnHide", HallHidden)
	if hall:IsVisible() then
		Shown(hall)
	end
	Hall.current = hall   -- (the tests)
	return y + 10
end
