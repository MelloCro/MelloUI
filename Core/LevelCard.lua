--------------------------------------------------------------------------------
-- MelloUI - Level Up Card (1.2.4; MelloUI.LevelCard)
--
-- A small window at each level gained that says what the level gave you: the level over the moment line's gold rule,
-- the stats gained (old › new  +gain), the spells now at your class trainer and a talent point, the quests the level
-- opened nearby, and your nearest class trainer with "Set a route". The user, 2026-10-30, to the sketch
-- (BuildData/output/levelup_sketch): yes, on by default; level, stats and trainer; the top middle;
-- milestones' rays once; shown at once in a fight; one card for several levels ("Level 18 - 20"); "Level Up Card".
-- Its motion is the user's own: "Spark flying from the Character on the top, explodes and the Animated line shows up,
-- expands into the Levelup window, and the stats and spells start appearing with animation" -- a spark leaves the
-- character's chest (as Route's wisp starts: the screen's middle, WISP_FROM under it), flies to the
-- card's place and bursts there; the moment line draws out of the burst, the number rolling over; the line opens up
-- and down into the window; the stat rows slide in one after another and the spells land one by one, one ring of
-- light each. Every tenth level a ring of rays turns once behind the number. One drive (MelloUI.Anim:Drive) plays it
-- all, once; nothing repeats. Reduce Motion: the finished card at once, no spark. Held HOLD seconds (and while the
-- mouse is over it), then faded; the close button or a right-click ends it.
--
-- Its data, all plain, never a secret compared:
--   the gains   PLAYER_LEVEL_UP's own payload (health, power, talent points, strength, agility, stamina, intellect:
--               the client's API docs; and spirit after them, as the game's own level-up lines read it on Forever;
--               Tweaks' Level hands them on); a client whose event has no spirit: its base value's change since the
--               last experience update Level Up reads anyway (Card.Note); a total that reads secret shows the gain
--               alone
--   the spells  Media/TrainerSpells.lua (Tools/build_trainer_spells.py: a rule over Forever's own client tables): the
--               class's spells of the levels gained, for the player's race, a talent's later rank only with the
--               talent, none the player knows
--   the trainer Services' nearest class trainer (M:Nearest: no table made); its route through Services' M:GoTo on
--               the click (held until the fight ends in combat)
-- Several levels while it shows (a quest turned in at once, a dungeon's): one card, the gains added up, every spell.
--
-- Where: its own place, the top middle, Card.TOP UI units under the screen's top (an-07, the user 2026-10-31:
-- "its currently attached to the routing notification text, that should not be the case, it should retain this
-- height and be fixed"): it had taken the notice's mover's place AND its scale, so it moved with Route's "Tracking"
-- line and drew small, its hero -- on UIParent, unscaled -- across the panes. Its own mover since (the user, the
-- same day: "Add it"): "Level Up Card" in Edit Layout (key "levelcard", MelloUI's one mover and position store), an
-- empty frame as big as the card's largest layout for its plate; a place saved there, the card hangs from it at its
-- size from its next show; none saved, it stands at its own place as before. While the card shows a level, Level
-- Up's own moment line steps aside (Tweaks' Level.Notice: a line, not a place). Its size is its content's: the hero
-- on its own band over the panes, every row and spell, the footer, measured from the fonts. Built in MelloUI's one
-- systems: the
-- own-window shell (Kit:OwnWindow, every skin's dress), W.Panel / W.Text / W.IconBox, the palette (W.Paint,
-- W.Paint by key), the notice's shade band (MelloUI.Shade), the effects' art (FX.Art: each skin's set).
-- Nothing at login: made at the first level gained (or /mello player level); its place with it, or at Edit Layout's
-- open (its mover source) while the card is on. No secure frame: it shows in a fight.
--
--   MelloUI.LevelCard.Level(new, gains)   a level gained: gains = { health, power, talents, str, agi, sta, int, spi }
--                                         (the event's, plain numbers or nil); sub: the quests line (or nil)
--   MelloUI.LevelCard.Note()              the base Spirit kept (Tweaks' Level at each experience update)
--   MelloUI.LevelCard.Preview(level)      the card for `level` with sample gains (/mello player level)
--   MelloUI.LevelCard.Hide()              gone at once
--   MelloUI.LevelCard.Shown() -> bool     a card shows (the notice's line steps aside)
--   MelloUI.LevelCard.Spells(from, to[, all]) -> list   the trainer's spells of the levels after `from` up to `to`
--                                         for this character (all: the known ones too)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Safe = MelloUI.Safe
local Secret, Num, Text = Safe.IsSecret, Safe.Number, Safe.Text
local Perf = MelloUI.Perf:Scope("Level card")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer
local max, min, floor, ceil, sin, pi, rad = math.max, math.min, math.floor, math.ceil, math.sin, math.pi, math.rad
local format = string.format

-- (an-07, the user 2026-10-31: "the window needs to be bigger and make sure everything fits inside of it") Every
-- room below is the room PAST a text: the texts' own heights and widths are measured from their fonts as drawn (the
-- Font Style and the text size reach them), and the window grows to its content
local Card = {
	W = 440, PAD = 10, GAP = 8,                          -- the window's least width, its content's inset, the panes' gap
	IN = 8, COL = 12, ROW_GAP = 6, HEAD_GAP = 7,         -- a pane's inset and its columns' gap; a row's and a heading's room
	ICON = 26, ICON_GAP = 3, PER_ROW = 8, ICON_ROWS = 5, -- the trainer's icons: eight a row (the most a level brings, 25,
	                                                     -- in four full rows; several levels' up to five)
	HERO_PAD = 6, RULE_GAP = 6, SUB_GAP = 5, HERO_FOOT = 10,   -- the hero's band: over the word, the word to the rule,
	                                                     -- the rule to the quests line, under them (over the panes)
	FOOT_PAD = 5, FOOT_ICON = 20, TALENT_GAP = 5, HERO_SIZE = 26, SUB_SIZE = 14,
	RULE_W = 260, RULE_H = 2, RULE_ALPHA = 0.85,         -- the gold rule (the moment line's)
	-- its own place (an-07, the user 2026-10-31: "it should retain this height and be fixed"): its top TOP under the
	-- screen's top in UI units -- where their card stood (351 px down their 1440 px screen at UI scale 0.64: 292), never
	-- the notice's -- and KEEP inside the screen's edge
	TOP = 292, KEEP = 8,
	-- (the user, 2026-10-31: "Add it") its mover's key, and its plate's height until a card has measured the largest
	-- layout (the modern look's at the standard fonts: the quests line, five rows of spells, the talent line, the footer)
	KEY = "levelcard", PLATE_H = 370,
	SPARK = 40, TRAIL = 4, BURST = 72, GLOW = 48, RAYS = 150, RING = 1.85,   -- the lights' sizes (never past their files)
	HOLD = 9, FADE = 1.5, STRATA = "DIALOG", PAINTED_TOP = -64,
	MILESTONE = 10,                                      -- every tenth level: the rays
	-- the drive's beats, in seconds (the sketch's take U, motion.py, line for line)
	T = { FLY = 0.55, BURST = 0.55, LINE = 0.6, WORD = 0.68, ROLL = 0.9, OPEN = 1.05, OPEN_T = 0.45, SHADE_OUT = 1.05,
		HEAD = 1.45, ROWS = 1.55, ROW_STEP = 0.08, ICONS = 1.75, ICON_STEP = 0.07, AFTER = 0.7, TOTALS = 1.3 },
	WISP_FROM = -20,                                     -- the chest under the screen's middle (Route's Beacon)
	shown = false,
}
MelloUI.LevelCard = Card

-- the stats in the card's order: the event's gain field, the stat's index for UnitStat (nil: health / power), the
-- game's own name for it
local STATS = {
	{ key = "health", label = "HEALTH", fallback = "Health" },
	{ key = "power", power = true },
	{ key = "str", stat = 1, label = "SPELL_STAT1_NAME", fallback = "Strength" },
	{ key = "agi", stat = 2, label = "SPELL_STAT2_NAME", fallback = "Agility" },
	{ key = "sta", stat = 3, label = "SPELL_STAT3_NAME", fallback = "Stamina" },
	{ key = "int", stat = 4, label = "SPELL_STAT4_NAME", fallback = "Intellect" },
	{ key = "spi", stat = 5, label = "SPELL_STAT5_NAME", fallback = "Spirit" },
}
-- (/mello player level) the preview's gains: a small level's, so the card shows as it does
local PREVIEW = { health = 18, power = 31, talents = 1, sta = 1, int = 2, spi = 2 }

local function Seg(t, a, d)
	local v = (t - a) / d
	return v < 0 and 0 or v > 1 and 1 or v
end

local function Ease(p)
	local q = 1 - p
	return 1 - q * q * q
end

local function Bump(p)
	return (p > 0 and p < 1) and sin(pi * p) or 0
end

--------------------------------------------------------------------------------
-- The data
--------------------------------------------------------------------------------

local function PlayerClass()
	local _, token = UnitClass("player")
	return Text(token)
end

local function RaceBit()
	local _, _, id = UnitRace("player")
	id = Num(id)
	return id and id >= 1 and 2 ^ (id - 1) or nil
end

local function HasBit(mask, bit)
	return bit ~= nil and floor(mask / bit) % 2 == 1
end

-- (the client's spell and stat getters, looked up when asked: a client without one answers nothing)
local function Ask(name, ...)
	local fn = rawget(_G, name)
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

local function Knows(id)
	local ok, known = Ask("IsPlayerSpell", id)
	if ok and not Secret(known) and known then
		return true
	end
	ok, known = Ask("IsSpellKnown", id)
	return ok and not Secret(known) and known and true or false
end

-- the class trainer's spells of the levels after `from` up to `to` for this character: its race's, a talent's
-- later rank only with the talent, none it knows (all: the known ones too); the kept list, filled again
local spellList = {}
function Card.Spells(from, to, all)
	for i = #spellList, 1, -1 do
		spellList[i] = nil
	end
	local data = rawget(_G, "MelloUI_TrainerSpells")
	local levels = type(data) == "table" and data[PlayerClass() or ""]
	if type(levels) ~= "table" then
		return spellList
	end
	local races, needs, bit = data.races or {}, data.needs or {}, RaceBit()
	for level = from + 1, to do
		local list = levels[level]
		if type(list) == "table" then
			for _, id in ipairs(list) do
				local mask = races[id]
				local talent = needs[id]
				if (not mask or HasBit(mask, bit)) and (not talent or Knows(talent)) and (all or not Knows(id)) then
					spellList[#spellList + 1] = id
				end
			end
		end
	end
	return spellList
end

-- a total now (nil: secret, or none)
local function Total(row)
	local ok, v
	if row.key == "health" then
		ok, v = pcall(UnitHealthMax, "player")
	elseif row.power then
		local okT, kind = pcall(UnitPowerType, "player")
		ok, v = pcall(UnitPowerMax, "player", okT and Num(kind) or nil)
	else
		local okS, _, effective = Ask("UnitStat", "player", row.stat)
		ok, v = okS, effective
	end
	return ok and Num(v) or nil
end

-- the base Spirit now (nil: secret)
local function BaseSpirit()
	local ok, base = Ask("UnitStat", "player", 5)
	return ok and Num(base) or nil
end

-- the power's name (the game's: MANA "Mana")
local function PowerName()
	local ok, _, token = pcall(UnitPowerType, "player")
	token = ok and Text(token) or nil
	local name = token and rawget(_G, token)
	return type(name) == "string" and name or "Power"
end

function Card.Note()
	Card.spirit = BaseSpirit()
end

--------------------------------------------------------------------------------
-- The frames (made at the first card)
--------------------------------------------------------------------------------

local W, FX, Anim
local B = {}   -- the parts: holder, win, shell, hero, fx, panels, pools

-- (the languages: every text the card draws through W.Tr, the English as it is while no language table is in use)
local function Tr(text)
	return W and W.Tr and W.Tr(text) or text
end

local function Light(parent, layer, file, sub)
	local t = parent:CreateTexture(nil, layer, nil, sub or 0)
	t:SetTexture(FX.Art(file))
	t:SetBlendMode("ADD")
	t:SetAlpha(0)
	return t
end

-- the hero: the line's parts over the window (not clipped while it opens): the band, the rays and glow, the word and
-- the number in its clip, the rule and its sparks, the quests line
local function MakeHero()
	local hero = CreateFrame("Frame", nil, UIParent)
	hero:SetFrameStrata(Card.STRATA)
	hero:SetSize(Card.W, Card.HERO_SIZE * 2)   -- (its band's real size: LayHero, from the fonts)
	hero:EnableMouse(false)
	B.hero = hero
	B.band = MelloUI.Shade:Band(hero, MelloUI.Shade.TEXT)
	B.rays = Light(hero, "BACKGROUND", "rays_gold.tga")
	B.glow = Light(hero, "BORDER", "glow_gold.tga")
	B.burst = Light(hero, "BORDER", "ring_gold.tga", 1)
	local word = hero:CreateFontString(nil, "OVERLAY")
	B.word = word
	local clip = CreateFrame("Frame", nil, hero)
	clip:SetClipsChildren(true)
	B.clip = clip
	B.old = clip:CreateFontString(nil, "OVERLAY")
	B.new = clip:CreateFontString(nil, "OVERLAY")
	local rule = CreateFrame("StatusBar", nil, hero)
	rule:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	if rule.SetFillStyle then
		rule:SetFillStyle("CENTER")   -- (drawn out from its middle, as the moment line's)
	end
	rule:SetMinMaxValues(0, 1)
	rule:SetValue(0)
	rule:SetSize(Card.RULE_W, Card.RULE_H)
	rule:SetAlpha(Card.RULE_ALPHA)
	B.rule = rule
	B.sparks = { Light(hero, "OVERLAY", "spark_gold.tga"), Light(hero, "OVERLAY", "spark_gold.tga") }
	for _, s in ipairs(B.sparks) do
		s:SetSize(22, 22)
	end
	B.sub = hero:CreateFontString(nil, "OVERLAY")
	local huge, plain = rawget(_G, "GameFontNormalHuge"), rawget(_G, "GameFontHighlight")
	for _, fs in ipairs({ word, B.old, B.new }) do
		fs:SetFontObject(huge)
		MelloUI:StyleFont(fs, "fontTitle", huge, Card.HERO_SIZE, "", false)
		fs:SetShadowOffset(1, -1)
	end
	B.sub:SetFontObject(plain)
	MelloUI:StyleFont(B.sub, "fontText", plain, Card.SUB_SIZE, "", false)
	B.band:Anchor(word, 40, 10)
end

-- the spark and its trail: their own frame over the whole screen (it flies from the character to the card)
local function MakeSpark()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetAllPoints(UIParent)
	f:SetFrameStrata(Card.STRATA)
	f:EnableMouse(false)
	B.fx = f
	B.trail = {}
	for i = 0, Card.TRAIL do
		local s = Light(f, "OVERLAY", "spark_gold.tga")
		local size = Card.SPARK * (1 - i * 0.15)
		s:SetSize(size, size)
		B.trail[i] = s
	end
end

local Route   -- the route's click (below)
local Shell_OnKit   -- the look switch's (below)

local Icon_OnEnter = Shared("a level card icon's OnEnter", function(self)
	if not self.spell then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetSpellByID(self.spell)
	GameTooltip:Show()
end, "handler")

local Icon_OnLeave = Shared("a level card icon's OnLeave", function()
	GameTooltip:Hide()
end, "handler")

local Win_OnMouseUp = Shared("the level card's OnMouseUp", function(_, button)
	if button == "RightButton" then
		Card.Hide()
	end
end, "handler")

-- (its close, a right-click, its fade's end: the line and the spark go with it)
local Win_OnHide = Shared("the level card's OnHide", function()
	Card.Hide()
end, "script")

local function MakeWindow()
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:SetFrameStrata(Card.STRATA)
	holder:SetClipsChildren(true)
	holder:EnableMouse(false)
	B.holder = holder
	local win = CreateFrame("Frame", "MelloUILevelCard", holder)
	win:SetSize(Card.W, Card.W / 2)   -- (its real size: Fill, from its content)
	win:SetFrameStrata(Card.STRATA)
	win:EnableMouse(true)
	win:Hide()
	Perf.SetScript(win, "OnMouseUp", Win_OnMouseUp)
	Perf.SetScript(win, "OnHide", Win_OnHide)
	B.win = win
	-- (the ring's emblem: the class medallion, as the fight history's window has it; none known: the shell's own)
	local token = PlayerClass()
	local medal = token and MelloUI.ClassIconPath and MelloUI:ClassIconPath(token) or nil
	B.shell = MelloUI.Kit:OwnWindow(win, { area = "copy", ring = { at = "tl", texture = medal }, plate = "rail",
		title = Tr("Level Up"), close = true, calm = true })
	B.statsPanel = W.Panel(win)
	B.trainPanel = W.Panel(win)
	B.statsHead = W.Text(B.statsPanel, "GameFontNormal", Tr("Stats gained"), "selectedTrim")
	B.trainHead = W.Text(B.trainPanel, "GameFontNormal", Tr("New at your trainer"), "selectedTrim")
	B.trainCount = W.Text(B.trainPanel, "GameFontNormal", nil, "selectedTrim")
	B.rows, B.icons, B.rings = {}, {}, {}
	B.talent = W.Text(B.trainPanel, "GameFontHighlight", nil, "text")
	local foot = CreateFrame("Frame", nil, win)
	B.foot = foot
	B.footIcon = foot:CreateTexture(nil, "ARTWORK")
	B.footIcon:SetSize(Card.FOOT_ICON, Card.FOOT_ICON)
	MelloUI.Icons.Set(B.footIcon, "svc_classtrainer", Card.FOOT_ICON)
	B.footText = W.Text(foot, "GameFontHighlight", nil, "text")
	local link = CreateFrame("Button", nil, foot)
	link.text = W.Text(link, "GameFontNormal", Tr("Set a route \226\128\186"), "selectedTrim")
	link.text:SetPoint("RIGHT")
	Perf.SetScript(link, "OnClick", Route)
	B.link = link
	B.line = W.Solid(win, "ARTWORK", "trim", 0.55)
	B.line:SetHeight(1)
end

local function Row(i)
	local r = B.rows[i]
	if not r then
		r = { label = W.Text(B.statsPanel, "GameFontHighlight", nil, "text"),
			value = W.Text(B.statsPanel, "GameFontHighlight", nil, "text"),
			gain = W.Text(B.statsPanel, "GameFontHighlight", nil, "selectedTrim") }
		r.gain:SetJustifyH("RIGHT")
		B.rows[i] = r
	end
	return r
end

local function IconAt(i)
	local b = B.icons[i]
	if not b then
		b = W.IconBox(B.trainPanel, Card.ICON, nil, B.shell)
		b:EnableMouse(true)
		Perf.SetScript(b, "OnEnter", Icon_OnEnter)
		Perf.SetScript(b, "OnLeave", Icon_OnLeave)
		B.icons[i] = b
		local ring = Light(B.trainPanel, "OVERLAY", "ring_gold.tga", 7)
		ring:SetPoint("CENTER", b, "CENTER")
		B.rings[i] = ring
	end
	return b
end

local function Make()
	if B.win then
		return
	end
	W, FX, Anim = MelloUI.Widgets, MelloUI.FrameFX, MelloUI.Anim
	MakeWindow()
	MakeHero()
	MakeSpark()
	B.shell:OnKit(Shell_OnKit)
	-- (by palette key: painted again at every palette and skin change)
	local fill = B.rule.GetStatusBarTexture and B.rule:GetStatusBarTexture()
	if fill then
		W.Paint(fill, "selectedTrim", "vertex")
	end
	for _, fs in ipairs({ B.word, B.old, B.new }) do
		W.Paint(fs, "selectedTrim", "text")
	end
	W.Paint(B.sub, "text", "text")
end

--------------------------------------------------------------------------------
-- What the card says, and its layout
--------------------------------------------------------------------------------

local S = { from = nil, to = nil, gains = {}, sub = nil, preview = false }

-- the rows' totals (old > new) read now: the game applies a new level's stats a moment after its event, so read
-- again as the rows come in (the drive, T.TOTALS); a total that reads secret shows the gain alone
function Card.Totals()
	for i = 1, B.nRows or 0 do
		local r = B.rows[i]
		local total = r.row and Total(r.row)
		r.value:SetText(total and format("%d \226\128\186 %d", total - r.gainValue, total) or "")
	end
end

local function Count(n, one, many)
	return format(n == 1 and one or many, n)
end

-- a text's line height and its width as drawn (its font's real size: the Font Style and the text size reach it)
local function LineH(fs)
	local h = Num(fs:GetStringHeight())
	if not (h and h > 0) then
		local ok, _, size = pcall(fs.GetFont, fs)
		h = ok and Num(size) or nil
	end
	return ceil(h and h > 0 and h or Card.SUB_SIZE)
end

local function TextW(fs)
	return ceil(Num(fs:GetStringWidth()) or 0)
end

-- the content laid out in the window: the hero's band, the panes with their rows and icons, the talent line, the
-- footer; the window's width and height from them (an-07: every height and width measured from the texts as drawn,
-- nothing cut and nothing crossing: the hero on its own band over the panes)
local function Fill()
	local shell, win = B.shell, B.win
	-- (the shell's content inset in its look: a side inset and a negative y -- the painted look's under its corner
	-- ring, as the copy window's)
	local edge, topY = shell:Inset(Card.PAD, Card.PAINTED_TOP)
	local top = -topY
	local IN, COL, ICON, IGAP = Card.IN, Card.COL, Card.ICON, Card.ICON_GAP
	-- the rows: the gains above 0, with the totals where they read plain
	local n = 0
	for _, row in ipairs(STATS) do
		local gain = Num(S.gains[row.key])
		if gain and gain > 0 then
			n = n + 1
			local r = Row(n)
			local label = row.power and PowerName() or (type(rawget(_G, row.label)) == "string" and _G[row.label]
				or row.fallback)
			r.label:SetText(label)
			r.row, r.gainValue = row, gain
			r.gain:SetText("+" .. gain)
			r.label:Show()
			r.value:Show()
			r.gain:Show()
		end
	end
	for i = n + 1, #B.rows do
		local r = B.rows[i]
		r.label:Hide()
		r.value:Hide()
		r.gain:Hide()
	end
	B.nRows = n
	Card.Totals()
	-- the spells, the talent line
	local spells = Card.Spells(S.spellFrom or S.from, S.spellTo or S.to, S.preview)
	local hasIcons = #spells > 0
	B.trainCount:SetText(hasIcons and tostring(#spells) or "")
	local talents = Num(S.gains.talents) or 0
	B.talent:SetText(talents > 0 and Count(talents, Tr("+%d talent point to spend"), Tr("+%d talent points to spend"))
		or "")
	-- the hero: the word, the numbers, the quests line
	local single = S.to - S.from <= 1
	B.word:SetText(single and Tr("Level") or format(Tr("Level %d -"), S.from + 1))
	B.old:SetText(tostring(S.rollFrom or S.to - 1))
	B.new:SetText(tostring(S.to))
	B.sub:SetText(S.sub or "")
	-- the footer's line: the nearest class trainer and the route (none known, or no Services: the plain line)
	local services = MelloUI:GetModule("Services")
	local name
	if services and type(services.Nearest) == "function" then
		-- (yards and the name; none known: nil and why)
		local ok, yards, who = pcall(services.Nearest, services, "classtrainer")
		name = ok and Num(yards) and Text(who) or nil
	end
	local wantFoot = hasIcons
	B.footText:SetText(name and format(Tr("Nearest trainer: %s"), name) or Tr("Visit your class trainer"))
	B.link:SetShown(name ~= nil)
	B.link.text:SetText(Tr(B.routeHeld and "Route after the fight" or "Set a route \226\128\186"))
	-- measured: the hero's band, a heading's and a row's room, the stats' columns, the talent line, the footer
	local wordH = LineH(B.new)
	local heroH = Card.HERO_PAD + wordH + Card.RULE_GAP + Card.RULE_H + (S.sub and (Card.SUB_GAP + LineH(B.sub)) or 0)
		+ Card.HERO_FOOT
	B.wordH, B.heroH = wordH, heroH
	local heroW = max(TextW(B.word) + 6 + max(TextW(B.old), TextW(B.new)), TextW(B.sub), Card.RULE_W + 22)
	local headH = Card.HEAD_GAP + LineH(B.statsHead) + Card.HEAD_GAP
	local rowLine = n > 0 and LineH(B.rows[1].label) or 0
	local rowH = rowLine + Card.ROW_GAP
	B.headH, B.rowH = headH, rowH
	local labelW, valueW, gainW = 0, 0, 0
	for i = 1, n do
		local r = B.rows[i]
		labelW = max(labelW, TextW(r.label))
		valueW = max(valueW, TextW(r.value))
		gainW = max(gainW, TextW(r.gain))
	end
	B.labelW = labelW
	-- (a total read again as the rows come -- the game applies the level a moment after its event -- may be a digit
	-- longer: room for one)
	local digit = ceil(rowLine * 0.6)
	local showStats = n > 0 or (not hasIcons and talents > 0)
	local talentLine = talents > 0 and LineH(B.talent) or 0
	local talentH = talents > 0 and (Card.TALENT_GAP + talentLine) or 0
	local statsW = showStats and max(IN + labelW + COL + valueW + digit + COL + gainW + IN, IN + TextW(B.statsHead) + IN,
		hasIcons and 0 or (IN + TextW(B.talent) + IN)) or 0
	local trainNat = hasIcons and max(2 * IN + Card.PER_ROW * ICON + (Card.PER_ROW - 1) * IGAP,
		IN + TextW(B.trainHead) + COL + TextW(B.trainCount) + IN, IN + TextW(B.talent) + IN) or 0
	local footLine = max(Card.FOOT_ICON, LineH(B.footText), name and LineH(B.link.text) or 0)
	local footH = footLine + 2 * Card.FOOT_PAD
	local footW = wantFoot and (2 + Card.FOOT_ICON + 6 + TextW(B.footText) + COL
		+ (name and (TextW(B.link.text) + 4) or 0) + 2) or 0
	-- the largest card in this look and these fonts (its place's plate in Edit Layout): the quests line, the most rows
	-- (every stat, or five rows of spells and the talent line), the footer
	local hl = LineH(B.talent)
	B.largestH = top + Card.HERO_PAD + wordH + Card.RULE_GAP + Card.RULE_H + Card.SUB_GAP + LineH(B.sub) + Card.HERO_FOOT
		+ headH + max(#STATS * (hl + Card.ROW_GAP) - Card.ROW_GAP, Card.ICON_ROWS * (ICON + IGAP) - IGAP
		+ Card.TALENT_GAP + hl) + IN + Card.GAP + footH + edge
	-- the width: the panes side by side, the footer's line, the hero's; the trainer's pane takes what is over
	local both = showStats and hasIcons
	local panesW = both and (statsW + Card.GAP + trainNat) or (showStats and statsW or trainNat)
	local width = max(Card.W, 2 * edge + max(panesW, footW, heroW))
	win:SetWidth(width)
	local content = width - 2 * edge
	local trainW = both and (content - statsW - Card.GAP) or content
	local per = max(1, floor((trainW - 2 * IN + IGAP) / (ICON + IGAP)))
	local shownIcons = min(#spells, per * Card.ICON_ROWS)
	for i = 1, shownIcons do
		local b = IconAt(i)
		b.spell = spells[i]
		local spellApi = rawget(_G, "C_Spell")
		local ok, tex = false, nil
		if type(spellApi) == "table" and spellApi.GetSpellTexture then
			ok, tex = pcall(spellApi.GetSpellTexture, spells[i])
		end
		b.icon:SetTexture(ok and tex or nil)
		b:Show()
	end
	for i = shownIcons + 1, #B.icons do
		B.icons[i]:Hide()
		B.icons[i].spell = nil
		B.rings[i]:SetAlpha(0)
	end
	B.nIcons = shownIcons
	local iconRows = shownIcons > 0 and ceil(shownIcons / per) or 0
	local iconsH = iconRows > 0 and (iconRows * (ICON + IGAP) - IGAP) or 0
	-- the heights: a pane's heading, its rows or icons, the talent line (under the icons; with no spells, under the
	-- rows), its inset under them
	local statsH = showStats and (headH + max(0, n * rowH - Card.ROW_GAP) + (hasIcons and 0 or talentH) + IN) or 0
	local trainH = hasIcons and (headH + iconsH + talentH + IN) or 0
	-- the layout: the hero's band, then the panes under it
	local y = top + heroH
	local sp, tp = B.statsPanel, B.trainPanel
	sp:ClearAllPoints()
	tp:ClearAllPoints()
	sp:SetShown(showStats)
	tp:SetShown(hasIcons)
	if both then
		local h = max(statsH, trainH)
		sp:SetPoint("TOPLEFT", win, "TOPLEFT", edge, -y)
		sp:SetSize(statsW, h)
		tp:SetPoint("TOPLEFT", sp, "TOPRIGHT", Card.GAP, 0)
		tp:SetSize(trainW, h)
		y = y + h
	elseif showStats or hasIcons then
		local p, h = showStats and sp or tp, showStats and statsH or trainH
		p:SetPoint("TOPLEFT", win, "TOPLEFT", edge, -y)
		p:SetSize(content, h)
		y = y + h
	end
	-- the rows' places (their x moved by the drive from here), the headings, the icons, the talent line
	B.statsHead:ClearAllPoints()
	B.statsHead:SetPoint("TOPLEFT", sp, "TOPLEFT", IN, -Card.HEAD_GAP)
	B.trainHead:ClearAllPoints()
	B.trainHead:SetPoint("TOPLEFT", tp, "TOPLEFT", IN, -Card.HEAD_GAP)
	B.trainCount:ClearAllPoints()
	B.trainCount:SetPoint("TOPRIGHT", tp, "TOPRIGHT", -IN, -Card.HEAD_GAP)
	for i = 1, shownIcons do
		local c, r = (i - 1) % per, floor((i - 1) / per)
		local b = B.icons[i]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", tp, "TOPLEFT", IN + c * (ICON + IGAP), -(headH + r * (ICON + IGAP)))
		local ring = B.rings[i]
		ring:SetSize(ICON * Card.RING, ICON * Card.RING)
	end
	B.talent:ClearAllPoints()
	if hasIcons then
		B.talent:SetParent(tp)
		B.talent:SetPoint("TOPLEFT", tp, "TOPLEFT", IN, -(headH + iconsH + Card.TALENT_GAP))
	else
		B.talent:SetParent(sp)
		B.talent:SetPoint("TOPLEFT", sp, "TOPLEFT", IN, -(headH + max(0, n * rowH - Card.ROW_GAP) + Card.TALENT_GAP))
	end
	-- the footer
	B.foot:SetShown(wantFoot)
	if wantFoot then
		y = y + Card.GAP
		B.foot:ClearAllPoints()
		B.foot:SetPoint("TOPLEFT", win, "TOPLEFT", edge, -y)
		B.foot:SetSize(content, footH)
		B.footIcon:ClearAllPoints()
		B.footIcon:SetPoint("LEFT", B.foot, "LEFT", 2, 0)
		B.footText:ClearAllPoints()
		B.footText:SetPoint("LEFT", B.footIcon, "RIGHT", 6, 0)
		B.link:ClearAllPoints()
		B.link:SetPoint("RIGHT", B.foot, "RIGHT", -2, 0)
		B.link:SetSize(TextW(B.link.text) + 4, footH)
		B.line:ClearAllPoints()
		B.line:SetPoint("TOPLEFT", win, "TOPLEFT", edge, -(y - Card.GAP / 2))
		B.line:SetPoint("TOPRIGHT", win, "TOPRIGHT", -edge, -(y - Card.GAP / 2))
		B.line:Show()
		y = y + footH
	else
		B.line:Hide()
	end
	win:SetHeight(y + edge)
	B.heroTop = top
end

-- the rows' and the hero's places at the drive's share (x offsets of the rows; the hero's numbers)
local function LayRow(i, dx)
	local r = B.rows[i]
	local sp = B.statsPanel
	local y = -(B.headH + (i - 1) * B.rowH)
	r.label:ClearAllPoints()
	r.label:SetPoint("TOPLEFT", sp, "TOPLEFT", Card.IN + dx, y)
	r.value:ClearAllPoints()
	r.value:SetPoint("TOPLEFT", sp, "TOPLEFT", Card.IN + B.labelW + Card.COL + dx, y)
	r.gain:ClearAllPoints()
	r.gain:SetPoint("TOPRIGHT", sp, "TOPRIGHT", -Card.IN, y)
end

-- the hero's band over the window's top, as wide as the window, at its scale (the band's offsets are the window's
-- units: a window scaled alone left its hero over the panes, an-07)
local function LayHero()
	local hero, win = B.hero, B.win
	hero:SetScale(win:GetScale() or 1)
	hero:ClearAllPoints()
	hero:SetPoint("TOP", win, "TOP", 0, -B.heroTop)
	hero:SetSize(win:GetWidth(), B.heroH)
	local ww, nw = B.word:GetStringWidth() or 0, max(B.old:GetStringWidth() or 0, B.new:GetStringWidth() or 0)
	local gap = 6
	local x0 = -(ww + gap + nw) / 2
	local h = B.wordH
	local wy = -(Card.HERO_PAD + h / 2)
	B.word:ClearAllPoints()
	B.word:SetPoint("LEFT", hero, "TOP", x0, wy)
	B.numberH = h
	B.clip:ClearAllPoints()
	B.clip:SetPoint("LEFT", hero, "TOP", x0 + ww + gap - 2, wy)
	B.clip:SetSize(nw + 6, h + 4)
	B.rule:ClearAllPoints()
	B.rule:SetPoint("TOP", hero, "TOP", 0, -(Card.HERO_PAD + h + Card.RULE_GAP))
	B.sub:ClearAllPoints()
	B.sub:SetPoint("TOP", B.rule, "BOTTOM", 0, -Card.SUB_GAP)
	local cx = x0 + ww + gap + nw / 2
	B.numX = cx
	for _, t in ipairs({ B.rays, B.glow }) do
		t:ClearAllPoints()
		t:SetPoint("CENTER", hero, "TOP", cx, wy)
	end
	B.burst:ClearAllPoints()
	B.burst:SetPoint("CENTER", B.rule, "CENTER")
end

local function SetNumber(fs, dy)
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", B.clip, "LEFT", 2, dy)
end

--------------------------------------------------------------------------------
-- The drive: the user's motion (the sketch's take U)
--------------------------------------------------------------------------------

-- where the spark starts: the character's chest, as Route's wisp has it -- the screen's middle, WISP_FROM under it
local function SparkFrom()
	-- (2.1.51) the world's screen's middle: Offhand's main screen while it runs (MelloUI.Integrations.PlayArea)
	local I = rawget(MelloUI, "Integrations")
	if I and I.PlayArea then
		local l, b, w, h = I.PlayArea()
		return l + w / 2, b + h / 2 + Card.WISP_FROM
	end
	return UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 + Card.WISP_FROM
end

-- the rule's middle in UIParent's units (our own frame: plain)
local function RuleAt()
	local x, y = B.rule:GetCenter()
	local k = B.rule:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return (x or 0) * k, (y or 0) * k
end

local function Step(_, share)
	local T = Card.T
	local t = B.t0 + share * (B.total - B.t0)
	local done = share >= 1
	local refresh = B.refresh
	-- the spark from the character to the line, its trail behind it
	local x0, y0, x1, y1 = B.fromX, B.fromY, B.toX, B.toY
	for i = 0, Card.TRAIL do
		local s = B.trail[i]
		local tt = t - i * 0.03
		local a = (done or refresh) and 0 or (tt >= 0 and (1 - Seg(tt, T.BURST, 0.08)) * (1 - i * 0.18) or 0)
		s:SetAlpha(a)
		if a > 0 then
			local f = Ease(Seg(tt, 0, T.FLY))
			s:ClearAllPoints()
			s:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)
		end
	end
	-- the burst, the glow, a milestone's rays
	local p = Seg(t, T.BURST, 0.5)
	B.burst:SetAlpha((t >= T.BURST and not (done or refresh)) and 0.95 * (1 - p) or 0)
	local bs = Card.BURST * (0.3 + 1.4 * Ease(p))
	B.burst:SetSize(bs, bs)
	local g = Seg(t, T.BURST - 0.05, 0.75)
	B.glow:SetAlpha((B.milestone and 0.85 or 0.7) * Bump(g))
	local gs = Card.GLOW * (0.7 + 0.6 * g)
	B.glow:SetSize(gs, gs)
	local r = Seg(t, T.BURST, 1.4)
	B.rays:SetAlpha(B.milestone and 0.55 * Bump(r) or 0)
	local rs = Card.RAYS * (0.8 + 0.35 * r)
	B.rays:SetSize(rs, rs)
	B.rays:SetRotation(rad(-30 * r))
	-- the moment line: its band, the rule drawn out with a spark at each end, the word, the number rolling over
	B.band:SetStrength(Ease(Seg(t, T.LINE, 0.25)) * (1 - Ease(Seg(t, T.SHADE_OUT, 0.35))))
	B.band:SetShown(not (done or refresh))
	local f = refresh and 1 or Ease(Seg(t, T.LINE, 0.45))
	B.rule:SetValue(f)
	local sa = (done or refresh) and 0 or 0.9 * Seg(t, T.LINE, 0.08) * (1 - Seg(t, T.LINE + 0.35, 0.25))
	for side, s in ipairs(B.sparks) do
		s:SetAlpha(sa)
		s:ClearAllPoints()
		s:SetPoint("CENTER", B.rule, "CENTER", (side == 1 and -1 or 1) * f * Card.RULE_W / 2, 0)
	end
	B.word:SetAlpha(refresh and 1 or Ease(Seg(t, T.WORD, 0.25)))
	local roll = Ease(Seg(t, T.ROLL, 0.3))
	B.old:SetAlpha(done and 0 or (refresh and 1 or Ease(Seg(t, T.WORD, 0.2))) * (1 - Seg(t, T.ROLL, 0.3)))
	SetNumber(B.old, B.numberH * roll)
	B.new:SetAlpha(Seg(t, T.ROLL, 0.3))
	SetNumber(B.new, -B.numberH * (1 - roll))
	B.sub:SetAlpha(Ease(Seg(t, T.ROLL + 0.1, 0.3)))
	-- the line opens up and down into the window (its holder's clip from the rule's line out)
	local e = refresh and 1 or Ease(Seg(t, T.OPEN, T.OPEN_T))
	local holder = B.holder
	if done or e >= 1 then
		holder:ClearAllPoints()
		holder:SetAllPoints(UIParent)
	else
		local k = B.win:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local l, b, w, h = B.win:GetRect()
		l, b, w, h = (l or 0) * k, (b or 0) * k, (w or 0) * k, (h or 0) * k
		local up, down = (b + h + 30) - y1, y1 - (b - 30)
		holder:ClearAllPoints()
		holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l - 40, y1 - down * e)
		holder:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l + w + 40, y1 + up * e + 0.5)
	end
	-- the rows slide in, the spells land one by one, one ring each, then the lines
	if not B.totalsRead and (t >= T.TOTALS or done) then
		B.totalsRead = true
		Card.Totals()
	end
	local head = Ease(Seg(t, T.HEAD, 0.25))
	B.statsHead:SetAlpha(head)
	B.trainHead:SetAlpha(head)
	B.trainCount:SetAlpha(head)
	for i = 1, B.nRows do
		local q = Ease(Seg(t, T.ROWS + T.ROW_STEP * (i - 1), 0.3))
		local row = B.rows[i]
		row.label:SetAlpha(q)
		row.value:SetAlpha(q)
		LayRow(i, -20 * (1 - q))
		row.gain:SetAlpha(Ease(Seg(t, T.ROWS + T.ROW_STEP * (i - 1) + 0.25, 0.15)))
	end
	for i = 1, B.nIcons do
		local a = T.ICONS + T.ICON_STEP * (i - 1)
		B.icons[i]:SetAlpha(Ease(Seg(t, a, 0.18)))
		local q = Seg(t, a + 0.05, 0.45)
		local ring = B.rings[i]
		ring:SetAlpha((t >= a + 0.05 and not done) and 0.9 * (1 - q) or 0)
		local size = Card.ICON * Card.RING * (0.45 + 0.9 * Ease(q))
		ring:SetSize(size, size)
	end
	local lines = Ease(Seg(t, T.ICONS + T.ICON_STEP * B.nIcons + 0.1, 0.3))
	B.talent:SetAlpha(lines)
	B.foot:SetAlpha(lines)
	B.line:SetAlpha(lines)
end

--------------------------------------------------------------------------------
-- Showing, holding, fading
--------------------------------------------------------------------------------

local Hold   -- (below)

local function Fade()
	B.holdTimer = nil
	if not Card.shown then
		return
	end
	if B.win:IsMouseOver() then
		-- (held while the mouse is over it: looked at again in a second)
		B.holdTimer = C_Timer.NewTimer(1, Fade)
		return
	end
	Card.shown = false
	Anim:FadeOut(B.win, Card.FADE)
	Anim:FadeOut(B.hero, Card.FADE)
end

function Hold()
	if B.holdTimer then
		B.holdTimer:Cancel()
	end
	B.holdTimer = C_Timer.NewTimer(Card.HOLD, Fade)
end

local Done = Shared("the level card's entrance done", function()
	Step(nil, 1)
	Hold()
end, "callback")

-- its home: the top middle, Card.TOP under the screen's top (its place's while none is saved; a Reset's preview)
local function Home(f)
	f:ClearAllPoints()
	f:SetPoint("TOP", UIParent, "TOP", 0, -Card.TOP)
	return true
end

-- the card on (Tweaks' Level Up Card): its plate shows and its place is kept only then
local function CardOn()
	local tweaks = MelloUI:GetModule("Tweaks")
	return tweaks ~= nil and tweaks.isEnabled == true and type(tweaks.db) == "table" and tweaks.db.levelCard ~= false
end

-- its place on MelloUI's one mover (the user 2026-10-31, "Add it"): an empty frame, the mouse through it, as big as the
-- card's largest layout (Edit Layout's plate), made with the first card or at Edit Layout's open
local function PlaceFrame()
	local f = B.place
	if f then
		return f
	end
	f = CreateFrame("Frame", "MelloUILevelCardPlace", UIParent)
	f:SetSize(Card.W, B.largestH or Card.PLATE_H)
	f:EnableMouse(false)
	Home(f)
	B.place = f
	B.entry = MelloUI:RegisterMover(f, f, { key = Card.KEY, anchor = "TOP", default = Home, min = 0.5, max = 2,
		base = 1, label = "Level Up Card", page = "Tweaks", category = "text", placeholder = true, when = CardOn })
	return f
end

-- the card's place: a place saved in Edit Layout (or its plate being dragged there now), the card hung from its top at
-- its size; none, its own: the top middle Card.TOP under the screen's top, kept KEEP inside the screen (a short screen:
-- higher). Never the notice's mover (an-07: its place and its scale had come with it). Its place as big as the
-- largest card or this one, so a place kept on the screen keeps the card on it
local function Place()
	local win, place = B.win, PlaceFrame()
	place:SetSize(max(Card.W, win:GetWidth()), max(B.largestH or Card.PLATE_H, win:GetHeight()))
	win:ClearAllPoints()
	local entry = B.entry
	if (entry and entry.moving) or MelloUI:RestorePosition(Card.KEY, place) then
		MelloUI.Kit:SetFrameScale(win, place:GetScale() or 1)
		win:SetPoint("TOP", place, "TOP", 0, 0)
		return
	end
	-- (its place there too, at its 100 %: Edit Layout's plate shows where the card stands)
	Home(place)
	MelloUI.Kit:SetFrameScale(place, 1)
	MelloUI.Kit:SetFrameScale(win, 1)
	local room = UIParent:GetHeight() - win:GetHeight() - Card.KEEP
	win:SetPoint("TOP", UIParent, "TOP", 0, -max(Card.KEEP, min(Card.TOP, room)))
end

-- Edit Layout's plate: the card's place made when it opens, while the card is on (never at login)
local function MoverSource()
	if CardOn() then
		PlaceFrame()
	end
end

-- (the shell's look switched while it shows -- a skin, the reskin: the content laid again in the new inset)
-- the card laid again with its content now (a level more, the quests line, a look switch): its size, its place (a
-- taller card on a short screen goes up), the hero, the spark's goal
local function Relay()
	Fill()
	Place()
	LayHero()
	B.toX, B.toY = RuleAt()
end

Shell_OnKit = Shared("the level card's look switch", function()
	if Card.shown and B.win:IsShown() then
		Relay()
		Step(nil, 1)
	end
end, "callback")

-- the card for S, its entrance from the start (or, while it shows, its content again)
local function Play(again)
	Make()
	Fill()
	Place()
	LayHero()
	B.milestone = S.to >= Card.MILESTONE and floor(S.to / Card.MILESTONE) > floor(S.from / Card.MILESTONE)
	local T = Card.T
	B.total = T.ICONS + T.ICON_STEP * B.nIcons + T.AFTER
	B.t0, B.refresh, B.totalsRead = again and T.ROLL - 0.05 or 0, again or false, false
	-- (the line over the window and every part of it -- the shell's rims ride 60 over it -- the spark over both)
	local level = B.win:GetFrameLevel()
	B.hero:SetFrameLevel(level + 80)
	B.fx:SetFrameLevel(level + 90)
	Anim:Stop(B.win)
	Anim:Stop(B.hero)
	B.win:SetAlpha(1)
	B.hero:SetAlpha(1)
	B.win:Show()
	B.hero:Show()
	B.fx:Show()
	Card.shown = true
	if B.holdTimer then
		B.holdTimer:Cancel()
		B.holdTimer = nil
	end
	B.fromX, B.fromY = SparkFrom()
	B.toX, B.toY = RuleAt()
	-- (again: a level more after it came in -- its content now, the number rolled over again, the rows and spells
	-- landing again, the window open all along)
	Step(nil, 0)
	Anim:Drive(B, Step, B.total - B.t0, "linear", Done)
end

function Card.Level(new, gains, sub)
	new = Num(new)
	if not new then
		return
	end
	local merge = Card.shown and S.to and new > S.to and not S.preview
	S.rollFrom = merge and S.to or nil
	if merge then
		for k, v in pairs(gains or {}) do
			v = Num(v)
			if v then
				S.gains[k] = (Num(S.gains[k]) or 0) + v
			end
		end
	else
		S.from = new - 1
		for k in pairs(S.gains) do
			S.gains[k] = nil
		end
		for k, v in pairs(gains or {}) do
			S.gains[k] = Num(v)
		end
	end
	-- Spirit: the event's own on Forever; a client whose event has none: the base's change since the last
	-- experience update
	local spirit, before = BaseSpirit(), Card.spirit
	if Num((gains or {}).spi) == nil and spirit and before and spirit > before then
		S.gains.spi = (merge and Num(S.gains.spi) or 0) + spirit - before
	end
	Card.spirit = spirit
	S.to, S.preview, S.spellFrom, S.spellTo = new, false, nil, nil
	if sub ~= nil then
		S.sub = sub
	elseif not merge then
		S.sub = nil
	end
	if merge and Anim:IsRunning(B, "drive") then
		-- (its entrance under way: the content now, the drive goes on; the new spells land at its end)
		Relay()
		return
	end
	Play(merge)
end

-- the quests line, when it comes after the card (Tweaks' Level.Notice's moment)
function Card.Sub(sub)
	if Card.shown and type(sub) == "string" and sub ~= "" and S.sub ~= sub then
		S.sub = sub
		B.sub:SetText(sub)
		Relay()
	end
end

function Card.Preview(level)
	level = Num(level)
	if not level then
		return
	end
	S.from, S.to, S.preview, S.sub, S.rollFrom = level - 1, level, true, nil, nil
	for k in pairs(S.gains) do
		S.gains[k] = nil
	end
	for k, v in pairs(PREVIEW) do
		S.gains[k] = v
	end
	-- (2026-10-30: a level gives power only to a mana user -- the game's event names none for rage or energy -- so a
	-- warrior's or a rogue's preview shows no "Rage +31")
	local okT, kind = pcall(UnitPowerType, "player")
	if not (okT and Num(kind) == 0) then
		S.gains.power = nil
	end
	-- (the spells of the level, or of the last level before it that has some)
	local at = level
	while at > 1 and #Card.Spells(at - 1, at, true) == 0 do
		at = at - 1
	end
	S.spellFrom, S.spellTo = at - 1, at
	Play(false)
end

function Card.Hide()
	if not B.win or B.hiding then
		return
	end
	B.hiding = true
	Card.shown = false
	if B.holdTimer then
		B.holdTimer:Cancel()
		B.holdTimer = nil
	end
	Anim:Land(B, "drive")
	Anim:Stop(B.win)
	Anim:Stop(B.hero)
	B.win:Hide()
	B.hero:Hide()
	B.fx:Hide()
	B.holder:ClearAllPoints()
	B.holder:SetAllPoints(UIParent)
	B.hiding = false
end

function Card.Shown()
	return Card.shown
end

--------------------------------------------------------------------------------
-- The route: Services' to the nearest class trainer; in a fight, held until it ends
--------------------------------------------------------------------------------

local routeFrame
local function GoRoute()
	B.routeHeld = false
	if B.link then
		B.link.text:SetText(Tr("Set a route \226\128\186"))
	end
	local services = MelloUI:GetModule("Services")
	if services and type(services.GoTo) == "function" then
		pcall(services.GoTo, services, "classtrainer")
	end
end

local Route_OnEvent = Shared("the level card's route after the fight", function(self)
	self:UnregisterAllEvents()
	GoRoute()
end, "event")

Route = Shared("the level card's Set a route", function()
	if InCombatLockdown() then
		if not routeFrame then
			routeFrame = CreateFrame("Frame")
			Perf.SetScript(routeFrame, "OnEvent", Route_OnEvent)
		end
		routeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		B.routeHeld = true
		B.link.text:SetText(Tr("Route after the fight"))
		return
	end
	GoRoute()
end, "handler")

if MelloUI.AddMoverSource then
	MelloUI:AddMoverSource(MoverSource)
end

Card.B, Card.S = B, S   -- (the tests')
