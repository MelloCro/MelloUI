--------------------------------------------------------------------------------
-- MelloUI - Level Up Card (1.2.4; MelloUI.LevelCard)
--
-- A small window at each level gained that says what the level gave you: the new level on a gilded seal, the stats
-- gained (old › new  +gain), the spells now at your class trainer and a talent point, the quests the level opened
-- nearby, and your nearest class trainer with "Set a route". The user, 2026-10-30, to the sketch
-- (BuildData/output/levelup_sketch): yes, on by default; level, stats and trainer; the top middle;
-- milestones' rays once; shown at once in a fight; one card for several levels ("Level 18 - 20"); "Level Up Card".
-- Its motion (2.1.54, remade in the Quest Moments' look; the user, 2026-11-15: "Remake the Leveling Toast animation to
-- a highest quality look similar to the Quest Animations", then of BuildData/output/levelup_remake_sketch: "Combination
-- with My Moution with C?", "Yes, build D") is the user's own October motion with the seal card's seal: a spark leaves
-- the character's chest (as Route's wisp starts: the screen's middle, WISP_FROM under it) and curves up to the card's
-- top left, where it lands as a gilded seal with the new level engraved -- bigger at first, it stamps (a small shake),
-- a flare, a wave of light and a burst of sparks. The gold rule draws out of the seal to the right, LEVEL UP draws
-- together beside it, "Level 20" rises through the rule with the number rolling over and one sheen crossing its
-- letters, the quests line under the rule; then the rule opens up and down into the window. The panes come, the stat
-- rows slide in one after another (the new total rolling up, the gain counting up with a little light), the spells
-- land one by one from a little higher and bigger, one ring of light each, their names under them; the talent point's
-- star pops with a few sparks; the footer rises in; one sheen crosses the window. Every tenth level a ring of rays turns
-- once behind the seal. One drive (MelloUI.Anim:Drive) plays it all, once; nothing repeats. Reduce Motion: the finished
-- card at once, no spark. Held HOLD seconds (and while the mouse is over it), then faded; the close button or a
-- right-click ends it.
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
-- Up's own moment line steps aside (Tweaks' Level.Notice: a line, not a place). Its size is its content's: the header
-- (the seal, the words, the rule) over the panes, every row and spell, the footer, measured from the fonts. Built in
-- MelloUI's one systems: the own-window shell (Kit:OwnWindow, every skin's dress; since 2.1.54 no ring or title plate
-- of its own -- the seal and LEVEL UP stand in that corner -- so the Default skin's game window has no portrait), W.Panel
-- / W.Text / W.IconBox / W.Button, the palette (W.Paint by key), the notice's shade band (MelloUI.Shade), the effects'
-- art (FX.Art: each skin's set).
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
local max, min, floor, ceil, sin, cos, exp, pi = math.max, math.min, math.floor, math.ceil, math.sin, math.cos,
	math.exp, math.pi
local format, concat = string.format, table.concat

-- (an-07, the user 2026-10-31: "the window needs to be bigger and make sure everything fits inside of it") Every
-- room below is the room PAST a text: the texts' own heights and widths are measured from their fonts as drawn (the
-- Font Style and the text size reach them), and the window grows to its content. (2.1.54) The sketch's take D in UI
-- units: its numbers / 1.1, the sketch's own scale
local Card = {
	W = 440, PAD = 10, GAP = 8,                          -- the window's least width, its content's inset, the panes' gap
	IN = 8, COL = 12, ROW_GAP = 6, HEAD_GAP = 7,         -- a pane's inset and its columns' gap; a row's and a heading's room
	ARROW_GAP = 6,                                       -- a total to its arrow, the arrow to the new total
	ICON = 30, ICON_GAP = 6, PER_ROW = 8, ICON_ROWS = 5, -- the trainer's icons: eight a row (the most a level brings, 25,
	                                                     -- in four full rows; several levels' up to five)
	NAMES_GAP = 5, STAR = 16, STAR_GAP = 5,              -- the icons to their names' line; the talent point's star
	-- the header (take D): the seal at the window's top left, LEVEL UP and the level beside it, the gold rule out of the
	-- seal, the quests line under the rule. Down from the header's top: HEAD_PAD, LEVEL UP's line, CAPS_GAP, the level's
	-- line, RULE_GAP, the rule, SUB_GAP, the quests line, HEAD_FOOT; the seal's middle SEAL_UP over the rule's
	HEAD_PAD = 12, CAPS_GAP = 2, RULE_GAP = 1, SUB_GAP = 7, HEAD_FOOT = 6, BODY_GAP = 7,
	SEAL_X = 56, SEAL_UP = 11, SEAL_R = 30, SEAL_LIGHT = 84, SEAL_SIZE = 27,
	TEXT_X = 111, NUM_GAP = 6, RULE_FROM = 36, RULE_END = 20, RULE_H = 6, RULE_ALPHA = 0.9,
	CAPS_SIZE = 12, CAPS_FROM = 6.4, CAPS_SPACING = 2.5, HERO_SIZE = 24, SUB_SIZE = 13,
	KIT_TOP = 16,                                        -- the header under the painted rail (Oldschool)
	FOOT_PAD = 6, FOOT_ICON = 22, TALENT_GAP = 6,
	ROUTE_H = 25, ROUTE_ICON = 15, ROUTE_IN = 9, ROUTE_GAP = 5,   -- Set a route: its button, the route's icon on it
	-- its own place (an-07, the user 2026-10-31: "it should retain this height and be fixed"): its top TOP under the
	-- screen's top in UI units -- where their card stood (351 px down their 1440 px screen at UI scale 0.64: 292), never
	-- the notice's -- and KEEP inside the screen's edge
	TOP = 292, KEEP = 8,
	-- (the user, 2026-10-31: "Add it") its mover's key, and its plate's height until a card has measured the largest
	-- layout (the modern look's at the standard fonts: the quests line, five rows of spells, their names, the talent
	-- line, the footer)
	KEY = "levelcard", PLATE_H = 400,
	-- the lights' sizes (never past their files)
	SPARK = 40, SPARK_GLOW = 58, GHOST = 31, TRAIL = 7, GLOW = 127, RAYS = 209, FLARE = 73, WAVE = 84, HEAD = 24,
	SPARKS = 16, CURVE_X = 109, CURVE_Y = 55,            -- the burst's sparks; the flight's curve past the screen's middle
	HOLD = 9, FADE = 1.5, STRATA = "DIALOG",
	MILESTONE = 10,                                      -- every tenth level: the rays
	-- the drive's beats, in seconds (the sketch's take D, line for line): the spark's flight, the seal landing and its
	-- stamp, the rule, LEVEL UP, the level rising and rolling, its sheen, the quests line, the window opening (and the
	-- words' band leaving), the close, the panes, the rows one after another, the spells one by one (their step shorter
	-- for many: all of them within ICONS_SPAN), then after the last spell the talent point, the footer and the window's
	-- sheen
	T = { FLY = 0.55, LAND = 0.52, STAMP = 0.64, LINE = 0.7, LINE_T = 0.38, CAPS = 0.76, WORD = 0.82, ROLL = 1.0,
		ROLL_T = 0.28, SHEEN = 1.3, SUB = 1.15, OPEN = 1.05, OPEN_T = 0.45, SHADE_OUT = 1.05, CLOSE = 1.4, PANES = 1.35,
		ROWS = 1.5, ROW_STEP = 0.08, ICONS = 1.75, ICON_STEP = 0.1, ICONS_SPAN = 1.4, TALENT = 0.25, FOOT = 0.15,
		SHINE = 0.25, SHINE_T = 0.7, TOTALS = 1.3 },
	WISP_FROM = -20,                                     -- the chest under the screen's middle (Route's Beacon)
	shown = false,
}
MelloUI.LevelCard = Card

-- (a round white: W.GlyphButton's disc, as the quest pages' discs) the seal's disc, and a fine white ring for its edge
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING = "Interface\\AddOns\\MelloUI\\Media\\Textures\\ProgressRing"

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

local function Ease(p)   -- (out, cubic)
	local q = 1 - p
	return 1 - q * q * q
end

local function InCubic(p)
	return p * p * p
end

local function InOut(p)
	if p < 0.5 then
		return 4 * p * p * p
	end
	local q = -2 * p + 2
	return 1 - q * q * q / 2
end

local function OutBack(p, s)
	local q = p - 1
	return 1 + (s + 1) * q * q * q + s * q * q
end

local function Bump(p)
	return (p > 0 and p < 1) and sin(pi * p) or 0
end

local function Lerp(a, b, p)
	return a + (b - a) * p
end

local seed = 1
local function Rand()
	seed = (seed * 1664525 + 1013904223) % 4294967296
	return seed / 4294967296
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

-- a spell's name (the client's; nil: none, or secret)
local function SpellName(id)
	local api = rawget(_G, "C_Spell")
	local ok, name = false, nil
	if type(api) == "table" and api.GetSpellName then
		ok, name = pcall(api.GetSpellName, id)
	end
	if not (ok and name) then
		ok, name = Ask("GetSpellInfo", id)
	end
	return ok and Text(name) or nil
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
local B = {}   -- the parts: holder, win, shell, hero, seal, fx, panels, pools

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

-- a text in the card's title face or text face at a size (the Font Style and the text size reach it)
local function Face(fs, role, object, size)
	fs:SetFontObject(object)
	MelloUI:StyleFont(fs, role, object, size, "", false)
	fs:SetShadowOffset(1, -1)
end

-- the header's parts over the window (not clipped while it opens), a frame on the window's rect: the words' band, the
-- rays and the glow behind the seal, the seal, the rule, LEVEL UP's letters (made with the first card's text), the
-- level rising in its clip with the number in its own, the sheen's gold copy in its moving clip, the quests line; over
-- them the stamp's flare and wave, the rule's bright head, the sparks, the talent point's star; over everything the
-- window's sheen in the window's clip
local function MakeHero()
	local hero = CreateFrame("Frame", nil, UIParent)
	hero:SetFrameStrata(Card.STRATA)
	hero:SetSize(Card.W, Card.W / 2)   -- (the window's rect: LayHero)
	hero:EnableMouse(false)
	B.hero = hero
	local huge, plain = rawget(_G, "GameFontNormalHuge"), rawget(_G, "GameFontHighlight")
	B.bandBox = CreateFrame("Frame", nil, hero)
	B.band = MelloUI.Shade:Band(hero, MelloUI.Shade.TEXT)
	B.band:Anchor(B.bandBox, 24, 8)
	B.rays = Light(hero, "BACKGROUND", "rays_gold.tga")
	B.glow = Light(hero, "BORDER", "glow_gold.tga")
	-- the seal: a gilded disc (its dark outline, the rim's deeper gold, the lighter face, an engraved ring, the light on
	-- its top left), the seal's light over it, the level cut into it (a light edge under the dark ink); a frame of its
	-- own, scaled as it stamps
	local seal = CreateFrame("Frame", nil, hero)
	local d = 2 * Card.SEAL_R
	seal:SetSize(d, d)
	B.seal = seal
	local function Part(file, sub, size, key, alpha, x, y, add)
		local t = seal:CreateTexture(nil, "ARTWORK", nil, sub)
		t:SetTexture(file)
		t:SetSize(size, size)
		t:SetPoint("CENTER", seal, "CENTER", x or 0, y or 0)
		if add then
			t:SetBlendMode("ADD")
		end
		W.Paint(t, key, "vertex", alpha)
		return t
	end
	Part(ROUND, 0, d + 2, "innerPanel", 0.75)
	Part(ROUND, 1, d, "trim", 1)
	Part(ROUND, 2, d - 6, "selectedTrim", 1, -1, 1)
	Part(RING, 3, d - 10, "trim", 0.7)
	Part(FX.Art("halo_white.tga"), 4, Card.SEAL_R * 1.2, "text", 0.35, -7, 8, true)
	local light = seal:CreateTexture(nil, "OVERLAY", nil, 0)
	light:SetTexture(FX.Art("seal_gold.tga"))
	light:SetBlendMode("ADD")
	light:SetSize(Card.SEAL_LIGHT, Card.SEAL_LIGHT)
	light:SetPoint("CENTER", seal, "CENTER")
	light:SetAlpha(0.8)
	B.sealHi = seal:CreateFontString(nil, "OVERLAY")
	B.sealNum = seal:CreateFontString(nil, "OVERLAY")
	for i, fs in ipairs({ B.sealHi, B.sealNum }) do
		Face(fs, "fontTitle", huge, Card.SEAL_SIZE)
		fs:SetDrawLayer("OVERLAY", i)
		fs:SetShadowOffset(0, 0)
		fs:SetJustifyH("CENTER")
		fs:SetPoint("CENTER", seal, "CENTER", 0, i == 1 and -2 or -1)
	end
	W.Paint(B.sealHi, "text", "text", 0.55)
	W.Paint(B.sealNum, "innerPanel", "text")
	-- the rule: the light's line, drawn out from its left
	local rule = CreateFrame("StatusBar", nil, hero)
	rule:SetStatusBarTexture(FX.Art("line_h.tga"))
	rule:SetMinMaxValues(0, 1)
	rule:SetValue(0)
	rule:SetHeight(Card.RULE_H)
	rule:SetAlpha(Card.RULE_ALPHA)
	B.rule = rule
	B.letters = {}
	-- the level: the word and the number rise through the rule in their clip (under LEVEL UP down to the rule), the
	-- number rolling over in its own
	local rise = CreateFrame("Frame", nil, hero)
	rise:SetClipsChildren(true)
	B.rise = rise
	B.word = rise:CreateFontString(nil, "OVERLAY")
	local clip = CreateFrame("Frame", nil, rise)
	clip:SetClipsChildren(true)
	B.clip = clip
	B.old = clip:CreateFontString(nil, "OVERLAY")
	B.new = clip:CreateFontString(nil, "OVERLAY")
	-- one sheen across the level's letters: their gold copy in a window that moves over them
	local sheen = CreateFrame("Frame", nil, hero)
	sheen:SetClipsChildren(true)
	sheen:Hide()
	B.sheenWin = sheen
	B.sheenWord = sheen:CreateFontString(nil, "OVERLAY")
	B.sheenNum = sheen:CreateFontString(nil, "OVERLAY")
	for _, fs in ipairs({ B.word, B.old, B.new, B.sheenWord, B.sheenNum }) do
		Face(fs, "fontTitle", huge, Card.HERO_SIZE)
	end
	B.sub = hero:CreateFontString(nil, "OVERLAY")
	Face(B.sub, "fontText", plain, Card.SUB_SIZE)
	local over = CreateFrame("Frame", nil, hero)
	over:SetAllPoints(hero)
	B.over = over
	B.wave = Light(over, "OVERLAY", "wave_gold.tga", 0)
	B.burst = Light(over, "OVERLAY", "ring_gold.tga", 1)
	B.star = Light(over, "OVERLAY", "star_gold.tga", 2)
	B.head = Light(over, "OVERLAY", "spark_gold.tga", 3)
	B.head:SetSize(Card.HEAD, Card.HEAD)
	B.sparks = {}
	for i = 1, Card.SPARKS do
		B.sparks[i] = Light(over, "OVERLAY", "spark_gold.tga", 4)
	end
	local shine = CreateFrame("Frame", nil, hero)
	shine:SetAllPoints(hero)
	shine:SetClipsChildren(true)
	B.shine = shine
	B.shineTex = Light(shine, "OVERLAY", "sheen.tga")
	W.Paint(B.shineTex, "text", "vertex")
	B.shineTex:SetAlpha(0)
end

-- the header's frames over one another, from the header's level up (its band and lights under the seal and the words;
-- the stamp's lights over them; the window's sheen over all)
local function LevelHero(level)
	B.hero:SetFrameLevel(level)
	for i, f in ipairs({ B.bandBox, B.seal, B.rule, B.rise, B.clip, B.sheenWin, B.over, B.shine }) do
		f:SetFrameLevel(level + i - 1)
	end
end

-- the spark: its ghosts behind it and its glow, on their own frame over the whole screen (it flies from the character
-- to the seal's place)
local function MakeSpark()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetAllPoints(UIParent)
	f:SetFrameStrata(Card.STRATA)
	f:EnableMouse(false)
	B.fx = f
	B.trail = {}
	for i = 1, Card.TRAIL do
		B.trail[i] = Light(f, "OVERLAY", "glow_gold.tga", 1)
	end
	B.headGlow = Light(f, "OVERLAY", "glow_gold.tga", 2)
	B.headGlow:SetSize(Card.SPARK_GLOW, Card.SPARK_GLOW)
	B.trail[0] = Light(f, "OVERLAY", "spark_gold.tga", 3)
	B.trail[0]:SetSize(Card.SPARK, Card.SPARK)
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

-- (its close, a right-click, its fade's end: the header and the spark go with it)
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
	-- (take D: no ring and no title plate -- the seal and LEVEL UP stand in that corner)
	B.shell = MelloUI.Kit:OwnWindow(win, { area = "copy", close = true, calm = true })
	B.statsPanel = W.Panel(win)
	B.trainPanel = W.Panel(win)
	B.statsHead = W.Text(B.statsPanel, "GameFontNormal", Tr("Stats gained"), "selectedTrim")
	B.trainHead = W.Text(B.trainPanel, "GameFontNormal", Tr("New at your trainer"), "selectedTrim")
	B.trainCount = W.Text(B.trainPanel, "GameFontNormal", nil, "selectedTrim")
	B.rows, B.icons, B.rings, B.nameList = {}, {}, {}, {}
	B.names = W.Text(B.trainPanel, "GameFontHighlight", nil, "text")
	B.names:SetWordWrap(false)
	B.names:SetJustifyH("LEFT")
	B.talent = W.Text(B.trainPanel, "GameFontHighlight", nil, "text")
	local foot = CreateFrame("Frame", nil, win)
	B.foot = foot
	B.footIcon = foot:CreateTexture(nil, "ARTWORK")
	B.footIcon:SetSize(Card.FOOT_ICON, Card.FOOT_ICON)
	MelloUI.Icons.Set(B.footIcon, "svc_classtrainer", Card.FOOT_ICON)
	B.footText = W.Text(foot, "GameFontHighlight", nil, "text")
	-- Set a route: the widget set's button with the route's page icon on it
	local link = W.Button(foot, "Set a route", 100, B.shell, { onClick = Route, height = Card.ROUTE_H })
	link.text = link:GetFontString()
	link.icon = link:CreateTexture(nil, "OVERLAY")
	link.icon:SetSize(Card.ROUTE_ICON, Card.ROUTE_ICON)
	link.icon:SetPoint("LEFT", link, "LEFT", Card.ROUTE_IN, 0)
	MelloUI.Icons.Set(link.icon, "page_route", Card.ROUTE_ICON)
	B.link = link
end

local function Row(i)
	local r = B.rows[i]
	if not r then
		local sp = B.statsPanel
		r = { label = W.Text(sp, "GameFontHighlight", nil, "text"),
			value = W.Text(sp, "GameFontHighlight", nil, "text"),
			arrow = W.Text(sp, "GameFontHighlight", "\226\128\186", "selectedTrim"),
			gain = W.Text(sp, "GameFontHighlight", nil, "selectedTrim") }
		r.gain:SetJustifyH("RIGHT")
		-- the new total rolls up from the old in its clip
		local clip = CreateFrame("Frame", nil, sp)
		clip:SetClipsChildren(true)
		r.clip = clip
		r.rollOld = W.Text(clip, "GameFontHighlight", nil, "text")
		r.rollNew = W.Text(clip, "GameFontHighlight", nil, "text")
		r.newKey = "text"
		r.glow = Light(sp, "OVERLAY", "glow_gold.tga", 6)
		r.glow:SetSize(36, 22)
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
	for _, fs in ipairs({ B.word, B.old, B.new, B.sub }) do
		W.Paint(fs, "text", "text")
	end
	W.Paint(B.sheenWord, "selectedTrim", "text")
	W.Paint(B.sheenNum, "selectedTrim", "text")
end

--------------------------------------------------------------------------------
-- What the card says, and its layout
--------------------------------------------------------------------------------

local S = { from = nil, to = nil, gains = {}, sub = nil, preview = false }

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

-- the rows' totals (old › new, the new one rolling up from the old) read now: the game applies a new level's stats a
-- moment after its event, so read again as the rows come in (the drive, T.TOTALS); a total that reads secret shows
-- the gain alone
function Card.Totals()
	for i = 1, B.nRows or 0 do
		local r = B.rows[i]
		local total = r.row and Total(r.row)
		local old = total and tostring(total - r.gainValue) or ""
		r.value:SetText(old)
		r.rollOld:SetText(old)
		r.rollNew:SetText(total and tostring(total) or "")
		r.arrow:SetShown(total ~= nil)
		r.clip:SetShown(total ~= nil)
		r.valueW = total and TextW(r.value) or 0
		r.newW = total and max(TextW(r.rollNew), TextW(r.rollOld)) or 0
	end
end

local function Count(n, one, many)
	return format(n == 1 and one or many, n)
end

-- LEVEL UP letter by letter, so its letters can draw together (the language's own word: its letters made once more
-- only for a longer one)
local function Letters(text)
	local n = 0
	local caps = rawget(_G, "GameFontNormal")
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		local fs = B.letters[n]
		if not fs then
			fs = B.hero:CreateFontString(nil, "OVERLAY")
			Face(fs, "fontTitle", caps, Card.CAPS_SIZE)
			W.Paint(fs, "selectedTrim", "text")
			B.letters[n] = fs
		end
		fs:SetText(ch)
		fs.w = Num(fs:GetStringWidth()) or 0
		fs:Show()
	end
	for i = n + 1, #B.letters do
		B.letters[i]:SetText("")
		B.letters[i]:Hide()
	end
	B.nLetters = n
end

local function LettersW(spacing)
	local w = 0
	for i = 1, B.nLetters do
		w = w + B.letters[i].w + (i > 1 and spacing or 0)
	end
	return ceil(w)
end

-- Set a route's label (or "Route after the fight"), its button as wide as the icon and the label
local function SetLink(text)
	local link = B.link
	link:SetText(Tr(text))
	link.text:ClearAllPoints()
	link.text:SetPoint("LEFT", link.icon, "RIGHT", Card.ROUTE_GAP, 0)
	link:SetWidth(Card.ROUTE_IN + Card.ROUTE_ICON + Card.ROUTE_GAP + TextW(link.text) + Card.ROUTE_IN + 2)
end

-- a row's total from its row's left (the old total, the arrow, the new total)
local function TotalW(r)
	return (r.valueW or 0) > 0 and (r.valueW + Card.ARROW_GAP + B.arrowW + Card.ARROW_GAP + r.newW) or 0
end

-- the content laid out in the window: the header, the panes with their rows and icons, the spells' names, the talent
-- line, the footer; the window's width and height from them (an-07: every height and width measured from the texts
-- as drawn, nothing cut and nothing crossing: the header over the panes)
local function Fill()
	local shell, win = B.shell, B.win
	-- the shell's side inset in its look; the header's top: under the painted rail (Oldschool), under the game
	-- window's title bar (the Default skin), the window's own top (the modern look)
	local edge = shell:Inset(Card.PAD, -Card.KIT_TOP)
	local top = shell.kit and Card.KIT_TOP or shell:PortraitFoot()
	B.edge = edge
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
			r.row, r.gainValue, r.gainShown = row, gain, gain
			r.gain:SetText("+" .. gain)
			for _, fs in ipairs({ r.label, r.value, r.gain, r.rollOld, r.rollNew }) do
				fs:Show()
			end
		end
	end
	for i = n + 1, #B.rows do
		local r = B.rows[i]
		for _, part in ipairs({ r.label, r.value, r.gain, r.arrow, r.clip }) do
			part:Hide()
		end
		r.glow:SetAlpha(0)
	end
	B.nRows = n
	B.arrowW = n > 0 and TextW(B.rows[1].arrow) or 0
	Card.Totals()
	-- the spells, the talent line
	local spells = Card.Spells(S.spellFrom or S.from, S.spellTo or S.to, S.preview)
	local hasIcons = #spells > 0
	B.nSpells = #spells
	B.trainCount:SetText(hasIcons and tostring(#spells) or "")
	B.countShown = #spells
	local talents = Num(S.gains.talents) or 0
	B.hasTalent = talents > 0
	B.talent:SetText(talents > 0 and Count(talents, Tr("+%d talent point to spend"), Tr("+%d talent points to spend"))
		or "")
	-- the header: LEVEL UP, the word and the numbers, the seal's level, the quests line
	Letters(Tr("LEVEL UP"))
	local single = S.to - S.from <= 1
	local word = single and Tr("Level") or format(Tr("Level %d -"), S.from + 1)
	B.word:SetText(word)
	B.sheenWord:SetText(word)
	B.old:SetText(tostring(S.rollFrom or S.to - 1))
	for _, fs in ipairs({ B.new, B.sheenNum, B.sealNum, B.sealHi }) do
		fs:SetText(tostring(S.to))
	end
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
	SetLink(B.routeHeld and "Route after the fight" or "Set a route")
	-- measured: the header (down from its top), a heading's and a row's room, the stats' columns, the talent line, the
	-- footer
	local capsH = B.nLetters > 0 and LineH(B.letters[1]) or 0
	local wordH = LineH(B.new)
	local capsTop = top + Card.HEAD_PAD
	local wordTop = capsTop + capsH + Card.CAPS_GAP
	local ruleY = wordTop + wordH + Card.RULE_GAP + Card.RULE_H / 2
	local sealY = ruleY - Card.SEAL_UP
	local subTop = ruleY + Card.RULE_H / 2 + Card.SUB_GAP
	local subLine = LineH(B.sub)
	local function HeadFoot(sub)
		return max(sub and (subTop + subLine) or (ruleY + Card.RULE_H / 2), sealY + Card.SEAL_R) + Card.HEAD_FOOT
	end
	local headFoot = HeadFoot(S.sub ~= nil)
	B.capsTop, B.capsH, B.capsY, B.wordH, B.wordY = capsTop, capsH, capsTop + capsH / 2, wordH, wordTop + wordH / 2
	B.ruleY, B.sealY, B.subY, B.headFoot = ruleY, sealY, subTop + subLine / 2, headFoot
	local heroW = Card.TEXT_X + max(LettersW(Card.CAPS_SPACING), TextW(B.word) + Card.NUM_GAP
		+ max(TextW(B.old), TextW(B.new)), S.sub and TextW(B.sub) or 0) + Card.RULE_END
	local headH = Card.HEAD_GAP + LineH(B.statsHead) + Card.HEAD_GAP
	local rowLine = n > 0 and LineH(B.rows[1].label) or 0
	local rowH = rowLine + Card.ROW_GAP
	B.headH, B.rowH, B.rowLine = headH, rowH, rowLine
	local labelW, totalW, gainW = 0, 0, 0
	for i = 1, n do
		local r = B.rows[i]
		labelW = max(labelW, TextW(r.label))
		totalW = max(totalW, TotalW(r))
		gainW = max(gainW, TextW(r.gain))
	end
	B.labelW = labelW
	-- (a total read again as the rows come -- the game applies the level a moment after its event -- may be a digit
	-- longer: room for one)
	local digit = ceil(rowLine * 0.6)
	B.digit = digit
	local showStats = n > 0 or (not hasIcons and talents > 0)
	local talentLine = talents > 0 and LineH(B.talent) or 0
	local talentH = talents > 0 and (Card.TALENT_GAP + talentLine) or 0
	local talentW = Card.STAR + Card.STAR_GAP + TextW(B.talent)
	local statsW = showStats and max(IN + labelW + COL + totalW + digit + COL + gainW + IN, IN + TextW(B.statsHead) + IN,
		hasIcons and 0 or (IN + talentW + IN)) or 0
	local k = min(#spells, Card.PER_ROW)
	local trainNat = hasIcons and max(2 * IN + k * ICON + (k - 1) * IGAP,
		IN + TextW(B.trainHead) + COL + TextW(B.trainCount) + IN, IN + talentW + IN) or 0
	local footLine = max(Card.FOOT_ICON, LineH(B.footText), name and Card.ROUTE_H or 0)
	local footH = footLine + 2 * Card.FOOT_PAD
	local footW = wantFoot and (2 + Card.FOOT_ICON + 6 + TextW(B.footText) + COL
		+ (name and ((Num(B.link:GetWidth()) or 0) + 2) or 0) + 2) or 0
	-- the largest card in this look and these fonts (its place's plate in Edit Layout): the quests line, the most rows
	-- (every stat and the talent line, or five rows of spells, their names and the talent line), the footer with its
	-- button
	local hl, nl = LineH(B.talent), LineH(B.names)
	B.largestH = HeadFoot(true) + Card.BODY_GAP + headH
		+ max(#STATS * (hl + Card.ROW_GAP) - Card.ROW_GAP + Card.TALENT_GAP + hl,
			Card.ICON_ROWS * (ICON + IGAP) - IGAP + Card.NAMES_GAP + nl + Card.TALENT_GAP + hl)
		+ IN + Card.GAP + max(Card.FOOT_ICON, LineH(B.footText), Card.ROUTE_H) + 2 * Card.FOOT_PAD + edge
	-- the width: the panes side by side, the footer's line, the header's; the trainer's pane takes what is over
	local both = showStats and hasIcons
	local panesW = both and (statsW + Card.GAP + trainNat) or (showStats and statsW or trainNat)
	local width = max(Card.W, 2 * edge + max(panesW, footW), heroW)
	win:SetWidth(width)
	B.width = width
	local content = width - 2 * edge
	local trainW = both and (content - statsW - Card.GAP) or content
	local per = max(1, floor((trainW - 2 * IN + IGAP) / (ICON + IGAP)))
	local shownIcons = min(#spells, per * Card.ICON_ROWS)
	local names = B.nameList
	for i = #names, 1, -1 do
		names[i] = nil
	end
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
		names[#names + 1] = SpellName(spells[i])
	end
	for i = shownIcons + 1, #B.icons do
		B.icons[i]:Hide()
		B.icons[i].spell = nil
		B.rings[i]:SetAlpha(0)
	end
	B.nIcons = shownIcons
	B.names:SetText(concat(names, ", "))
	local iconRows = shownIcons > 0 and ceil(shownIcons / per) or 0
	local iconsH = iconRows > 0 and (iconRows * (ICON + IGAP) - IGAP) or 0
	local namesH = shownIcons > 0 and (Card.NAMES_GAP + LineH(B.names)) or 0
	-- the heights: a pane's heading, its rows or icons (and their names), the talent line (under the icons; with no
	-- spells, under the rows), its inset under them
	local rowsH = max(0, n * rowH - Card.ROW_GAP)
	local statsH = showStats and (headH + rowsH + (hasIcons and 0 or talentH) + IN) or 0
	local trainH = hasIcons and (headH + iconsH + namesH + talentH + IN) or 0
	-- the layout: the header, then the panes under it
	local y = headFoot + Card.BODY_GAP
	local paneTop = y
	local sp, tp = B.statsPanel, B.trainPanel
	sp:ClearAllPoints()
	tp:ClearAllPoints()
	sp:SetShown(showStats)
	tp:SetShown(hasIcons)
	local trainX = edge
	if both then
		local h = max(statsH, trainH)
		sp:SetPoint("TOPLEFT", win, "TOPLEFT", edge, -y)
		sp:SetSize(statsW, h)
		tp:SetPoint("TOPLEFT", sp, "TOPRIGHT", Card.GAP, 0)
		tp:SetSize(trainW, h)
		trainX = edge + statsW + Card.GAP
		y = y + h
	elseif showStats or hasIcons then
		local p, h = showStats and sp or tp, showStats and statsH or trainH
		p:SetPoint("TOPLEFT", win, "TOPLEFT", edge, -y)
		p:SetSize(content, h)
		y = y + h
	end
	-- the rows' places (moved by the drive from here), the headings, the icons (by their middles: they land scaled),
	-- the spells' names, the talent line and its star
	B.statsHead:ClearAllPoints()
	B.statsHead:SetPoint("TOPLEFT", sp, "TOPLEFT", IN, -Card.HEAD_GAP)
	B.trainHead:ClearAllPoints()
	B.trainHead:SetPoint("TOPLEFT", tp, "TOPLEFT", IN, -Card.HEAD_GAP)
	B.trainCount:ClearAllPoints()
	B.trainCount:SetPoint("TOPRIGHT", tp, "TOPRIGHT", -IN, -Card.HEAD_GAP)
	for i = 1, shownIcons do
		local c, r = (i - 1) % per, floor((i - 1) / per)
		local b = B.icons[i]
		b.cx, b.cy, b.atRest = IN + c * (ICON + IGAP) + ICON / 2, headH + r * (ICON + IGAP) + ICON / 2, false
	end
	B.names:ClearAllPoints()
	B.names:SetPoint("TOPLEFT", tp, "TOPLEFT", IN, -(headH + iconsH + Card.NAMES_GAP))
	B.names:SetWidth(max(1, trainW - 2 * IN))
	B.names:SetShown(shownIcons > 0)
	local talentY = hasIcons and (headH + iconsH + namesH + Card.TALENT_GAP) or (headH + rowsH + Card.TALENT_GAP)
	B.talent:ClearAllPoints()
	B.talent:SetParent(hasIcons and tp or sp)
	B.talent:SetPoint("TOPLEFT", hasIcons and tp or sp, "TOPLEFT", IN + Card.STAR + Card.STAR_GAP, -talentY)
	B.starX, B.starY = (hasIcons and trainX or edge) + IN + Card.STAR / 2, paneTop + talentY + talentLine / 2
	-- the footer
	B.foot:SetShown(wantFoot)
	B.footShown = wantFoot
	if wantFoot then
		y = y + Card.GAP
		B.footY, B.footDy = y, nil
		B.foot:ClearAllPoints()
		B.foot:SetPoint("TOPLEFT", win, "TOPLEFT", edge, -y)
		B.foot:SetSize(content, footH)
		B.footIcon:ClearAllPoints()
		B.footIcon:SetPoint("LEFT", B.foot, "LEFT", 2, 0)
		B.footText:ClearAllPoints()
		B.footText:SetPoint("LEFT", B.footIcon, "RIGHT", 6, 0)
		B.link:ClearAllPoints()
		B.link:SetPoint("RIGHT", B.foot, "RIGHT", -2, 0)
		y = y + footH
	end
	win:SetHeight(y + edge)
	B.winH = y + edge
end

-- a row at the drive's share: its x moved by dx (sliding in), its new total rolled to share `roll` (0: the old one)
local function LayRow(i, dx, roll)
	local r = B.rows[i]
	local sp = B.statsPanel
	local y = -(B.headH + (i - 1) * B.rowH)
	local x = Card.IN + B.labelW + Card.COL + dx
	r.label:ClearAllPoints()
	r.label:SetPoint("TOPLEFT", sp, "TOPLEFT", Card.IN + dx, y)
	r.value:ClearAllPoints()
	r.value:SetPoint("TOPLEFT", sp, "TOPLEFT", x, y)
	r.gain:ClearAllPoints()
	r.gain:SetPoint("TOPRIGHT", sp, "TOPRIGHT", -Card.IN + dx, y)
	r.glow:ClearAllPoints()
	r.glow:SetPoint("CENTER", sp, "TOPRIGHT", -Card.IN - 12 + dx, y - B.rowLine / 2)
	if (r.valueW or 0) <= 0 then
		return
	end
	x = x + r.valueW + Card.ARROW_GAP
	r.arrow:ClearAllPoints()
	r.arrow:SetPoint("TOPLEFT", sp, "TOPLEFT", x, y)
	x = x + B.arrowW + Card.ARROW_GAP
	local h = B.rowLine
	r.clip:ClearAllPoints()
	r.clip:SetPoint("TOPLEFT", sp, "TOPLEFT", x, y + 2)
	r.clip:SetSize(r.newW + B.digit, h + 4)
	r.rollOld:ClearAllPoints()
	r.rollOld:SetPoint("TOPLEFT", r.clip, "TOPLEFT", 0, -2 + h * 0.9 * InCubic(roll))
	r.rollNew:ClearAllPoints()
	r.rollNew:SetPoint("TOPLEFT", r.clip, "TOPLEFT", 0, -2 - h * 0.9 * (1 - OutBack(roll, 2.2)))
end

-- a spell landing: scaled by sc about its middle, dy over its place
local function LayIcon(i, sc, dy)
	local b = B.icons[i]
	b:SetScale(sc)
	b:ClearAllPoints()
	b:SetPoint("CENTER", B.trainPanel, "TOPLEFT", b.cx / sc, (-b.cy + dy) / sc)
end

-- the header on the window's rect, at its scale (its offsets are the window's units: a window scaled alone left its
-- header over the panes, an-07): the rise's clip under LEVEL UP down to the rule, the number's clip, the sheen's copies
-- on the level's place at rest, the rule out of the seal to the window's right, the quests line, the words' band, the
-- seal's lights, the talent point's star
local function LayHero()
	local hero, win = B.hero, B.win
	hero:SetScale(win:GetScale() or 1)
	hero:ClearAllPoints()
	hero:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
	hero:SetSize(B.width, B.winH)
	local tx, h = Card.TEXT_X, B.wordH
	B.wordX, B.numX = tx, tx + TextW(B.word) + Card.NUM_GAP
	B.wordW = B.numX + TextW(B.new) - tx
	B.rise:ClearAllPoints()
	B.rise:SetPoint("TOPLEFT", hero, "TOPLEFT", tx - 4, -(B.capsTop + B.capsH))
	B.rise:SetPoint("BOTTOMRIGHT", hero, "TOPRIGHT", -Card.RULE_END, -B.ruleY)
	B.clip:SetSize(max(TextW(B.old), TextW(B.new)) + 6, h + 4)
	B.sheenWord:ClearAllPoints()
	B.sheenWord:SetPoint("LEFT", hero, "TOPLEFT", tx, -B.wordY)
	B.sheenNum:ClearAllPoints()
	B.sheenNum:SetPoint("LEFT", hero, "TOPLEFT", B.numX, -B.wordY)
	local x0 = Card.SEAL_X + Card.RULE_FROM
	B.ruleX0, B.ruleW = x0, max(1, B.width - Card.RULE_END - x0)
	B.rule:ClearAllPoints()
	B.rule:SetPoint("LEFT", hero, "TOPLEFT", x0, -B.ruleY)
	B.rule:SetWidth(B.ruleW)
	B.sub:ClearAllPoints()
	B.sub:SetPoint("LEFT", hero, "TOPLEFT", tx, -B.subY)
	B.bandBox:ClearAllPoints()
	B.bandBox:SetPoint("TOPLEFT", hero, "TOPLEFT", tx - 6, -B.capsTop)
	B.bandBox:SetPoint("BOTTOMRIGHT", hero, "TOPRIGHT", -Card.RULE_END, -(B.headFoot - Card.HEAD_FOOT))
	for _, t in ipairs({ B.rays, B.glow, B.burst, B.wave }) do
		t:ClearAllPoints()
		t:SetPoint("CENTER", hero, "TOPLEFT", Card.SEAL_X, -B.sealY)
	end
	B.glow:SetSize(Card.GLOW, Card.GLOW)
	B.star:ClearAllPoints()
	B.star:SetPoint("CENTER", hero, "TOPLEFT", B.starX, -B.starY)
end

local function SetNumber(fs, dy)
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", B.clip, "LEFT", 2, dy)
end

--------------------------------------------------------------------------------
-- The drive: the user's motion with the seal (the sketch's take D)
--------------------------------------------------------------------------------

-- where the spark starts: the character's chest, as Route's wisp has it -- the screen's middle, WISP_FROM under it
local function SparkFrom()
	-- (2.1.51) the world's screen's middle: Offhand's main screen while it runs (MelloUI:PlayArea)
	local l, b, w, h = MelloUI:PlayArea()
	return l + w / 2, b + h / 2 + Card.WISP_FROM
end

-- a point of the header (x right, y down from the window's top left) in UIParent's units (our own frame: plain)
local function HeroPoint(x, y)
	local l, b, _, h = B.hero:GetRect()
	local k = B.hero:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return ((l or 0) + x) * k, ((b or 0) + (h or 0) - y) * k
end

-- the spark's goal (the seal's middle) and its curve, and the line the window opens from (the rule's)
local function Aim()
	B.toX, B.toY = HeroPoint(Card.SEAL_X, B.sealY)
	local _, ry = HeroPoint(0, B.ruleY)
	B.openY = ry
	local l, _, w = MelloUI:PlayArea()
	B.ctlX, B.ctlY = l + w / 2 + Card.CURVE_X, (B.fromY + B.toY) / 2 + Card.CURVE_Y
end

-- the bursts' sparks: each one's angle, speed, life, size and delay, seeded at each card (kept tables, filled again)
local burstSet = { ang = {}, spd = {}, life = {}, size = {}, delay = {}, n = 0 }
local starSet = { ang = {}, spd = {}, life = {}, size = {}, delay = {}, n = 0 }

local function SeedSparks(set, n, s0, s1, l0, l1, z0, z1)
	for i = 1, n do
		set.ang[i] = 2 * pi * (i + Rand() * 0.8) / n
		set.spd[i] = s0 + (s1 - s0) * Rand()
		set.life[i] = l0 + (l1 - l0) * Rand()
		set.size[i] = z0 + (z1 - z0) * Rand()
		set.delay[i] = Rand() * 0.06
	end
	set.n = n
end

-- the sparks of a set flying out from (x, y) of the header, t0 seconds after the burst (below 0: none), r0 out at
-- first, slowed as they go, falling by g
local function DrawSparks(set, t0, x, y, r0, g)
	for i = 1, Card.SPARKS do
		local s = B.sparks[i]
		local tt = (i <= set.n and t0 >= 0) and t0 - set.delay[i] or -1
		if tt < 0 or tt > set.life[i] then
			s:SetAlpha(0)
		else
			local d = r0 + set.spd[i] * (1 - exp(-3.2 * tt)) / 3.2
			local life = tt / set.life[i]
			local size = set.size[i] * (1 - 0.55 * life)
			s:ClearAllPoints()
			s:SetPoint("CENTER", B.hero, "TOPLEFT", x + cos(set.ang[i]) * d, y + sin(set.ang[i]) * d - 0.5 * g * tt * tt)
			s:SetSize(size, size)
			s:SetAlpha((1 - life) ^ 1.4)
		end
	end
end

-- LEVEL UP's letters from the words' left at a spacing
local function PutLetters(spacing, a)
	local x = Card.TEXT_X
	for i = 1, B.nLetters do
		local fs = B.letters[i]
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", B.hero, "TOPLEFT", x, -B.capsY)
		fs:SetAlpha(a)
		x = x + fs.w + spacing
	end
end

-- the spark from the character up its curve to the seal's place, its ghosts behind it
local function StepSpark(t, quiet)
	local fp = Seg(t, 0, Card.T.FLY)
	local flying = not quiet and fp > 0 and fp < 1
	local x0, y0, x1, y1, x2, y2 = B.fromX, B.fromY, B.ctlX, B.ctlY, B.toX, B.toY
	for i = 0, Card.TRAIL do
		local s = B.trail[i]
		if flying then
			local q = InOut(max(0, fp - i * 0.03))
			local u = 1 - q
			local px, py = u * u * x0 + 2 * u * q * x1 + q * q * x2, u * u * y0 + 2 * u * q * y1 + q * q * y2
			s:ClearAllPoints()
			s:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px, py)
			if i == 0 then
				s:SetAlpha(1)
				s:SetRotation(-t * 6)
				B.headGlow:ClearAllPoints()
				B.headGlow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px, py)
			else
				local size = Card.GHOST * (1 - i / 9)
				s:SetSize(size, size)
				s:SetAlpha(0.55 * (1 - i / 8))
			end
		else
			s:SetAlpha(0)
		end
	end
	B.headGlow:SetAlpha(flying and 0.8 or 0)
end

-- the header at time th (at rest while a level more comes in: only the number rolls, at t): the seal landing and
-- stamping, its lights, the rule, LEVEL UP, the level rising and rolling, its sheen, the quests line, the band
local function StepHeader(t, th, quiet, done, refresh)
	local T = Card.T
	local S0 = T.STAMP
	local after = th > S0 and not quiet
	local shake = after and 2.4 * sin((th - S0) * 70) * (1 - Seg(th, S0, 0.26)) or 0
	local ss = Lerp(1.8, 1, InCubic(Seg(th, T.LAND, S0 - T.LAND)))
		* (th > S0 and Lerp(0.94, 1, OutBack(Seg(th, S0, 0.25), 3)) or 1)
	local seal = B.seal
	seal:SetScale(ss)
	seal:ClearAllPoints()
	seal:SetPoint("CENTER", B.hero, "TOPLEFT", (Card.SEAL_X + shake) / ss, -B.sealY / ss)
	seal:SetAlpha(Seg(th, T.LAND, 0.1))
	local num = Seg(th, T.LAND + 0.03, 0.11)
	B.sealNum:SetAlpha(num)
	B.sealHi:SetAlpha(num)
	-- behind it: the glow, a milestone's rays turning once; over it at the stamp: the flare, the wave, the sparks
	B.glow:SetAlpha(0.7 * Seg(th, 0.5, 0.1) * (1 - 0.6 * Seg(th, S0 + 0.3, 1.9 - S0 - 0.3)))
	local rp, rf = Seg(th, S0, 0.7), 1 - Seg(th, S0 + 0.9, 0.9)
	local ra = (B.milestone and not refresh) and 0.75 * rp * rf or 0
	B.rays:SetAlpha(ra)
	if ra > 0 then
		local rs = Card.RAYS * Lerp(0.5, 1.1, Ease(rp))
		B.rays:SetSize(rs, rs)
		B.rays:SetRotation(-(0.2 + th * 0.3))
	end
	local fl = Seg(th, S0, 0.5)
	B.burst:SetAlpha(after and (1 - fl) or 0)
	local fs = Card.FLARE * (1 + 0.9 * Ease(fl))
	B.burst:SetSize(fs, fs)
	local wp = Seg(th, S0, 0.6)
	B.wave:SetAlpha(after and 0.8 * (1 - wp) or 0)
	local ws = Card.WAVE * (1 + 1.4 * Ease(wp))
	B.wave:SetSize(ws, ws)
	if t < B.talentAt then
		DrawSparks(burstSet, quiet and -1 or th - S0, Card.SEAL_X, -B.sealY, 27, 100)
	end
	-- the rule out of the seal, its bright head while it draws
	local lp = Seg(th, T.LINE, T.LINE_T)
	local f = Ease(lp)
	B.rule:SetValue(f)
	local drawing = lp > 0 and lp < 1 and not quiet
	B.head:SetAlpha(drawing and 1 or 0)
	if drawing then
		B.head:ClearAllPoints()
		B.head:SetPoint("CENTER", B.hero, "TOPLEFT", B.ruleX0 + B.ruleW * f, -B.ruleY)
	end
	-- LEVEL UP drawing together; the level rising through the rule, the number rolling over (at t), one sheen
	PutLetters(Lerp(Card.CAPS_FROM, Card.CAPS_SPACING, Ease(Seg(th, T.CAPS, 0.39))), Ease(Seg(th, T.CAPS, 0.24)))
	local wq = Seg(th, T.WORD, 0.26)
	local rise = 18 * (1 - OutBack(wq, 2))
	B.word:ClearAllPoints()
	B.word:SetPoint("LEFT", B.hero, "TOPLEFT", B.wordX, -(B.wordY + rise))
	B.word:SetAlpha(wq)
	B.clip:ClearAllPoints()
	B.clip:SetPoint("LEFT", B.hero, "TOPLEFT", B.numX - 2, -(B.wordY + rise))
	local roll = Seg(t, T.ROLL, T.ROLL_T)
	local h = B.wordH
	SetNumber(B.old, h * 0.9 * InCubic(roll))
	B.old:SetAlpha(done and 0 or wq * (1 - Ease(roll)))
	SetNumber(B.new, -h * 0.9 * (1 - OutBack(roll, 2.2)))
	B.new:SetAlpha(Ease(roll))
	local sp = Seg(th, T.SHEEN, 0.5)
	if sp > 0 and sp < 1 and not done then
		local sw = Card.HERO_SIZE * 1.4
		B.sheenWin:ClearAllPoints()
		B.sheenWin:SetPoint("CENTER", B.hero, "TOPLEFT", B.wordX - sw / 2 + (B.wordW + 2 * sw) * InOut(sp), -B.wordY)
		B.sheenWin:SetSize(sw, h * 1.6)
		B.sheenWin:SetAlpha(0.9 * Bump(sp))
		B.sheenWin:Show()
	else
		B.sheenWin:Hide()
	end
	B.sub:SetAlpha(Seg(th, T.SUB, 0.3))
	B.band:SetStrength(Ease(Seg(th, T.LINE, 0.25)) * (1 - Ease(Seg(th, T.SHADE_OUT, 0.35))))
	B.band:SetShown(not quiet)
end

-- the window's content at time t: the panes, the rows (sliding in, the new total rolling up, the gain counting up
-- with a little light), the spells landing (a ring each) and their count, their names, the talent point, the footer,
-- the window's sheen
local function StepBody(t, done)
	local T = Card.T
	local pa = (done or B.refresh) and 1 or Seg(t, T.PANES, 0.25)
	B.statsPanel:SetAlpha(pa)
	B.trainPanel:SetAlpha(pa)
	if not B.totalsRead and (t >= T.TOTALS or done) then
		B.totalsRead = true
		Card.Totals()
	end
	for i = 1, B.nRows do
		local rt = done and 9 or t - (T.ROWS + T.ROW_STEP * (i - 1))
		local r = B.rows[i]
		local ra = Ease(Seg(rt, 0, 0.28))
		r.label:SetAlpha(ra)
		r.value:SetAlpha(ra)
		r.arrow:SetAlpha(ra)
		local rp = Seg(rt, 0.12, 0.3)
		LayRow(i, -13 * (1 - Ease(Seg(rt, 0, 0.32))), rp)
		r.rollOld:SetAlpha(ra * (1 - Ease(rp)))
		r.rollNew:SetAlpha(ra * Ease(rp))
		local key = rt < 0.9 and "selectedTrim" or "text"
		if r.newKey ~= key then
			r.newKey = key
			W.Paint(r.rollNew, key, "text")
		end
		r.gain:SetAlpha(ra * Seg(rt, 0.16, 0.14))
		local gain = (rt >= 0.62 or rt < 0.16) and r.gainValue or floor(r.gainValue * Ease(Seg(rt, 0.2, 0.42)) + 0.5)
		if r.gainShown ~= gain then
			r.gainShown = gain
			r.gain:SetText("+" .. gain)
		end
		r.glow:SetAlpha((rt > 0.42 and rt < 0.9) and 0.55 * (1 - Seg(rt, 0.42, 0.48)) or 0)
	end
	local nI, step = B.nIcons, B.iconStep
	for i = 1, nI do
		local st = done and 9 or t - (T.ICONS + step * (i - 1))
		local b = B.icons[i]
		local p = Ease(Seg(st, 0, 0.3))
		if p < 1 then
			b.atRest = false
			LayIcon(i, Lerp(1.5, 1, p), 9 * (1 - p))
		elseif not b.atRest then
			b.atRest = true
			LayIcon(i, 1, 0)
		end
		b:SetAlpha(Seg(st, 0, 0.14))
		local f = Seg(st, 0.26, 0.44)
		local ring = B.rings[i]
		ring:SetAlpha((f > 0 and f < 1) and (1 - f) or 0)
		local size = Card.ICON * (1.1 + 0.9 * Ease(f))
		ring:SetSize(size, size)
	end
	-- the spells' count counting up as they land
	if nI > 0 then
		local c = done and 1 or Seg(t, T.ICONS, B.after - T.ICONS + 0.3)
		local shown = max(1, ceil(B.nSpells * c))
		if B.countShown ~= shown then
			B.countShown = shown
			B.trainCount:SetText(tostring(shown))
		end
		B.trainCount:SetAlpha(c > 0 and 1 or 0)
	end
	B.names:SetAlpha(done and 1 or Seg(t, B.after + 0.15, 0.25))
	-- the talent point: its star pops, a few sparks, its line beside it
	local tp = done and 1 or Seg(t, B.talentAt, 0.3)
	B.star:SetAlpha(B.hasTalent and tp or 0)
	local ss = max(1, Card.STAR * OutBack(tp, 2.6))
	B.star:SetSize(ss, ss)
	B.talent:SetAlpha(done and 1 or Seg(t, B.talentAt + 0.08, 0.22))
	if t >= B.talentAt then
		DrawSparks(starSet, (done or not B.hasTalent) and -1 or t - B.talentAt - 0.1, B.starX, -B.starY, 4, 36)
	end
	-- the footer rises in
	local fy = done and 0 or 7 * (1 - Ease(Seg(t, B.footAt, 0.35)))
	B.foot:SetAlpha(done and 1 or Seg(t, B.footAt, 0.3))
	if B.footShown and B.footDy ~= fy then
		B.footDy = fy
		B.foot:ClearAllPoints()
		B.foot:SetPoint("TOPLEFT", B.win, "TOPLEFT", B.edge, -(B.footY + fy))
	end
	-- one sheen across the window
	local sh = done and 1 or Seg(t, B.shineAt, T.SHINE_T)
	if sh > 0 and sh < 1 then
		local H = B.winH
		B.shineTex:ClearAllPoints()
		B.shineTex:SetPoint("CENTER", B.hero, "TOPLEFT", -H + (B.width + 2 * H) * InOut(sh), -H / 2)
		B.shineTex:SetSize(H * 0.9, H * 2.4)
		B.shineTex:SetRotation(-0.35)
		B.shineTex:SetAlpha(0.55 * Bump(sh))
	else
		B.shineTex:SetAlpha(0)
	end
end

local function Step(_, share)
	local T = Card.T
	local t = B.t0 + share * (B.total - B.t0)
	local done = share >= 1
	local refresh = B.refresh
	local quiet = done or refresh   -- (no one-off light: at rest, or a level more while it shows)
	StepSpark(t, quiet)
	StepHeader(t, refresh and max(t, 2) or t, quiet, done, refresh)
	-- the rule opens up and down into the window (its holder's clip from the rule's line out)
	local e = refresh and 1 or Ease(Seg(t, T.OPEN, T.OPEN_T))
	local holder = B.holder
	if done or e >= 1 then
		holder:ClearAllPoints()
		holder:SetAllPoints(UIParent)
	else
		local k = B.win:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local l, b, w, h = B.win:GetRect()
		l, b, w, h = (l or 0) * k, (b or 0) * k, (w or 0) * k, (h or 0) * k
		local y1 = B.openY
		local up, down = (b + h + 30) - y1, y1 - (b - 30)
		holder:ClearAllPoints()
		holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l - 40, y1 - down * e)
		holder:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l + w + 40, y1 + up * e + 0.5)
	end
	local close = B.shell.close
	if close then
		close:SetAlpha((done or refresh) and 1 or Seg(t, T.CLOSE, 0.3))
	end
	StepBody(t, done)
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
-- (2.1.53: of the game's screen -- MelloUI:PlayPoint's rule: Offhand's main screen, never the gap
-- between two screens)
local function Home(f)
	MelloUI:PlayPoint(f, "TOP", "TOP", 0, -Card.TOP)
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
	local _, _, _, screenH = MelloUI:PlayArea()
	local room = screenH - win:GetHeight() - Card.KEEP
	MelloUI:PlayPoint(win, "TOP", "TOP", 0, -max(Card.KEEP, min(Card.TOP, room)))
end

-- Edit Layout's plate: the card's place made when it opens, while the card is on (never at login)
local function MoverSource()
	if CardOn() then
		PlaceFrame()
	end
end

-- (the shell's look switched while it shows -- a skin, the reskin: the content laid again in the new inset)
-- the card laid again with its content now (a level more, the quests line, a look switch): its size, its place (a
-- taller card on a short screen goes up), the header, the spark's goal
local function Relay()
	Fill()
	Place()
	LayHero()
	Aim()
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
	-- the beats after the spells: the last spell's, the talent point's, the footer's, the window's sheen's, the end
	local T = Card.T
	B.iconStep = min(T.ICON_STEP, T.ICONS_SPAN / max(1, B.nIcons))
	B.after = T.ICONS + B.iconStep * max(0, B.nIcons - 1)
	B.talentAt = B.after + T.TALENT
	B.footAt = B.talentAt + T.FOOT
	B.shineAt = B.footAt + T.SHINE
	B.total = B.shineAt + T.SHINE_T
	B.t0, B.refresh, B.totalsRead = again and T.ROLL - 0.05 or 0, again or false, false
	SeedSparks(burstSet, Card.SPARKS, 82, 191, 0.4, 0.85, 7, 13)
	SeedSparks(starSet, 7, 36, 73, 0.3, 0.55, 5, 8)
	-- (the header over the window and every part of it -- the shell's rims ride 60 over it -- the spark over both)
	local level = B.win:GetFrameLevel()
	LevelHero(level + 80)
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
	Aim()
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

-- the quests line, when it comes after the card (Tweaks' Level.Notice's moment): a text, or a moment's second line
-- as the notice reads it (a key and its numbers, in the language in use)
function Card.Sub(sub)
	local read = rawget(MelloUI, "MomentSub")
	if read and type(sub) == "table" then
		sub = read(sub)
	end
	if Card.shown and type(sub) == "string" and sub ~= "" and S.sub ~= sub then
		S.sub = sub
		B.sub:SetText(sub)
		Relay()
		-- (at rest: every part on its new place now; during the entrance the drive lays them)
		if not Anim:IsRunning(B, "drive") then
			Step(nil, 1)
		end
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
		SetLink("Set a route")
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
		SetLink("Route after the fight")
		return
	end
	GoRoute()
end, "handler")

if MelloUI.AddMoverSource then
	MelloUI:AddMoverSource(MoverSource)
end

Card.B, Card.S = B, S   -- (the tests')
