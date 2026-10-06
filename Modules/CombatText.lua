--------------------------------------------------------------------------------
-- MelloUI - Combat Text
--
-- (user, 2026-10-01: "make all 3, make it an option in the configurator, and
-- selectable, the current Blizzard damage numbers should be set as default,
-- but i want to test your 3 versions aswell"; the sketch:
-- docs/plans/next-update-refs/combat_text_looks.jpg, the plan:
-- docs/plans/combat-text.md)
--
-- The text the game floats over your character (the damage you take, your
-- heals, Dodge and Parry, procs, the resources you gain), in one of four
-- styles (Combat Text Style):
--   game     (the default) the game's own: MelloUI does nothing at all -- no
--            frame, no hook, no event, no CVar touched, nothing at login
--   lanes    A: round the character. Damage taken falls on the left (right
--            aligned), healing rises on the right (left aligned), notices
--            (procs, auras, Dodge / Parry, the fight's start and end, your
--            reputation) above the head, resources small under the feet
--   feed     B: one column over the player portrait, the newest on top, the
--            older ones fading: a small mark per kind (MelloUI.Widgets'
--            glyphs: hit, heal, proc, avoid, gain) and the healer's name
--            where the game gives a plain one. The Gains feed's engine
--            (MelloUI.Feed, Core/Feed.lua) and look
--   classic  C: one stream over the head, as the game's, drawn by MelloUI in
--            its font on the soft shade instead of thick outlines
-- Every line lies on the soft dark band that hugs its text (MelloUI.Shade's
-- text look, Shade.TEXT, as the notices and the Gains lines), the notice's
-- text shadow, no outline unless the notice's Outlined Text is on. Numbers
-- and words in the interface text font (MelloUI:StyleFont "fontText"); the
-- notices in the kit's title font (Kit:TitleFont, Notices In Title Font);
-- Your Damage in the Game Numbers Font (0.17.0, the user's pick: one font for
-- every number over the enemies; its face only, its size Numbers Over Enemies).
-- Shade Size (0.17.0, the user: "an option to reduce the size of the shading
-- behind the damage numbers, both my own character scrolling text and the
-- damage numbers themselves"): the band's share of the text look, for every
-- line -- 100% the notices' own, less hugs the text closer (less padding,
-- shorter soft ends, a lower band), 0% none.
-- Colours: the meaning colours MelloUI.Meaning.combatTaken / combatHeal /
-- combatResource; the notices in the palette's gold (selectedTrim), the
-- words and names in its text colour, by key (painted again on the
-- palette). Crits are 1.35 times as big and held a little longer.
-- With the reskin off (MelloUI.Look, docs/plans/game-look.md wave 3) the
-- game's floating text: no band, the game's black shadow, outlined, the
-- words white and the notices gold in the game's colours (the meaning
-- colours stay: they say what a number is).
--
-- One source: COMBAT_TEXT_UPDATE (C_CombatText.GetCurrentEventInfo: data,
-- arg3, arg4 -- SecretReturns, so any of them may be secret) and the fight's
-- start and end (PLAYER_REGEN_DISABLED / ENABLED). Each event becomes ONE
-- entry (a reused table: no garbage per event) from ONE map of the game's
-- kinds (KINDS, from Blizzard_CombatText's CombatTextTypeInfo): taken, heal,
-- notice, avoid, resource, combat or rep. A secret amount or name is never
-- compared, joined or summed: it goes through BreakUpLargeNumbers (a C
-- function that takes secrets on this client and answers in kind) and
-- FontString:SetText, both cleared for secrets (AllowedWhenTainted); its
-- sign is a FontString of its own. Lines are never merged by sum: lines of
-- one lane that come within 0.3 s stack a slot apart. Health and mana low
-- are the game's own sums of secret health (never ours): shown only as the
-- game sends them, here never.
--
-- The game's own text while a MelloUI style is on: the game's switch
-- (enableFloatingCombatText) is kept on -- the events come while it is
-- (set on, its value noted, when it was off; put back on Game) -- and the
-- game's CombatText frame is faded: alpha 0 and a SetAlpha post-hook that
-- keeps it there (never hidden, its events never touched: it is the game's
-- frame). Back on Game everything goes back as it was. A CVar is written
-- only out of combat (a change made in a fight waits for its end).
--
-- Your Damage (0.17.0, asked after the first in-game test: "everything works
-- except the damage im dealing", then "All 3, with a dropdown menu" and "the
-- behaviour should stay the same as its the default, i dont want to change
-- the feel of dealing damage"; the sketch combat_dealt_looks.jpg): Game (the
-- default: the engine's numbers, untouched), or MelloUI draws the hits at
-- each enemy's nameplate -- Rise (straight up, as the game's), Fan (up, left
-- and right in turn) or Stack (a short column beside the plate, newest on
-- top). As the game's: a crit bigger, a glancing blow smaller, about a
-- second and a half each. The source is UNIT_COMBAT for the plates' units
-- (the user's check: it comes for target AND nameplateN, the same hit -- the
-- plates only, so no hit counts twice -- with plain amounts in a fight; the
-- combat log is restricted on this client). UNIT_COMBAT says what the enemy
-- took, never WHO hit it, so (the user, 2026-10-01: "it should only show my
-- and my pets damage number, never the ones from other players";
-- docs/plans/fps-portrait-fix.md section 7):
--   * only an enemy you or your pet are FIGHTING: on its threat list
--     (MelloUI.Threat.Read "player" / "pet"), as well as one you can attack
--     that no one else has tapped. A hit on an enemy you are not on the list
--     of yet is held for HOLD seconds -- your own first hit may come before
--     the threat update that puts you on it (UNIT_THREAT_LIST_UPDATE) -- and
--     drawn if you are on it by then, else dropped: a stranger's first hit on
--     a fresh mob is never drawn;
--   * in a group, or where the game keeps the threat answer secret, MelloUI
--     cannot tell whose hit it is: the game's own numbers show (the engine
--     knows), as with the plates off, until you are solo again / the fight
--     ends;
--   * the one gap left: solo, a passer-by hitting the same mob you are also
--     fighting. Both of you are on its list and nothing an addon gets tells
--     the hits apart: their hits are drawn too. Not solved.
-- /mello combattext order: 15 seconds of the two events' order in the chat.
-- While it is on the game's damage, DoT and pet numbers are off (their CVars'
-- values noted in db.savedDealt, put back on Game; their rows dimmed). A
-- plate is the only place an addon knows an enemy stands at: with the enemy
-- nameplates off (nameplateShowEnemies, the V key; CVAR_UPDATE tells) there
-- is nowhere to draw, so the game's own numbers come back meanwhile (the
-- user's video, 2026-10-01: "it does not show the damage numbers when i
-- disable nameplates") -- the default's behaviour kept. These CVars are
-- written in a fight too when the game lets them be (GetCVarInfo's isSecure
-- false); a locked one waits for the fight's end. The feel is the game's
-- (the user's videos, 2026-10-01, the game's numbers against Rise): as big
-- as its numbers and sized by its World Text Scale too, starting on the
-- enemy and shooting up most of the way at once. A frame anchored to a
-- nameplate has secret anchoring on this client (GetPoint, GetRect,
-- GetCenter answer secret: the second video's numbers never moved under
-- Anim:To; the engine's Translation then moved the shade but not the text),
-- so the numbers are slid by setting their anchor from the offsets given
-- (Anim:Slide), Stack's column is laid again from them too, and nothing
-- reads where a number is. A plate that goes (the killing blow) leaves its numbers on the frame
-- the game hid, where it last stood, to finish their drift and fade; the
-- dealt lines have their own spares, so a line the self text takes was
-- never anchored to a plate.
--
-- The numbers over the enemies are the engine's, not ours: their font is
-- Fonts' Damage Numbers face (Fonts.fontDamage, on the same tab), their size
-- the World Text Scale (Tweaks.worldTextScale). Here: four switches, each
-- the game's own CVar (Damage, DoT Ticks, Pet Damage, Healing Over Enemies):
-- a row shows the CVar as it is and writes it only when changed; a CVar
-- this client lacks dims its row ("Not in this client"). Probed when the
-- page first asks, never at login.
--
-- Its places: one mover per style (Edit Layout: lanes "combatlanes",
-- classic "combatstream", the feed "combatfeed"), each live while its style
-- is the one chosen; Edit Layout shows sample lines on its plate. Preview
-- (the row's button, /mello combattext test) plays a short burst of made-up
-- lines in the chosen style.
--
-- Cost. Game: nothing. Another style: one event frame after the login's
-- frames (MelloUI:AfterLogin); the holders and the lines (pooled) come with
-- the first entry, the first Preview or Edit Layout. No OnUpdate of its
-- own, no ticker: each line is one engine-driven fade (Anim:Mirror) and one
-- move (Anim:To, Anim's driver only while lines move; Reduce Motion: no
-- travel, only the fade).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("CombatText")
local GameLook = MelloUI.Look   -- (the reskin off: the game's floating text)
local hooksecurefunc = Perf.hooksecurefunc

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text

local pairs, ipairs, type, pcall, tremove = pairs, ipairs, type, pcall, table.remove

local OWNER = "CombatText"
local GAME_CVAR = "enableFloatingCombatText"
local NEW = "0.17.0"

-- the numbers, in one table (the file's locals stay few)
local T = {
	size = 20, sizeMin = 12, sizeMax = 36,   -- the text size
	crit = 1.35,                             -- a crit's size, times the text's
	tail = 0.72,                             -- a name or a word after a number, times the text's
	small = 0.8,                             -- the lanes' resources under the feet
	lines = 5, linesMin = 2, linesMax = 10,  -- most lines per lane / in the stream / in the feed
	spread = 110, spreadMin = 50, spreadMax = 260,
	fadeIn = 0.12, hold = 0.9, critHold = 1.3, fadeOut = 0.6,
	travel = 70,                             -- a floating line's way over its life
	stack = 0.3,                             -- lines of one lane within this many seconds stack
	gap = 6,                                 -- a number to its name or word
	feedHold = 4, feedWidth = 380,
	lineWidth = 420,
	sampleHold = 3600,                       -- Edit Layout's samples: held until it closes
	glyph = 0.8,                             -- the feed's mark, times the text size
}

local TEXT = {
	gameStyle = "Combat Text Style and Your Damage are both Game: the game draws them. Pick Lanes, Feed or Classic, or a Your Damage look, to preview MelloUI's.",
	dealtTarget = "Target an enemy, with enemy nameplates on, to preview Your Damage at its nameplate.",
	missing = "Not in this client",
	dealtOwns = "Off while MelloUI draws your damage (Your Damage)",
	-- words the game names itself (COMBAT_TEXT_*); these when it does not
	MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", EVADE = "Evade", IMMUNE = "Immune", DEFLECT = "Deflect",
	REFLECT = "Reflect", MISFIRE = "Misfire", BLOCK = "Block", ABSORB = "Absorb", RESIST = "Resist",
	INTERRUPT = "Interrupted", SPELL_DISPELLED = "Dispelled", EXTRA_ATTACKS = "Extra Attack",
	ENTERING_COMBAT = "+Combat", LEAVING_COMBAT = "-Combat", HONOR = "Honor",
	absorbed = "absorb",
}

local STYLES = {
	{ value = "game", label = "Game (Blizzard)" },
	{ value = "lanes", label = "Lanes: round your character" },
	{ value = "feed", label = "Feed: over your portrait" },
	{ value = "classic", label = "Classic: one stream, restyled" },
}

-- Your Damage (the header): its looks, the game's numbers it stands in for,
-- the hits that are words, its numbers' sizes and ways
local DEALT = {
	styles = {
		{ value = "game", label = "Game (Blizzard)" },
		{ value = "rise", label = "Rise: up from the enemy" },
		{ value = "fan", label = "Fan: up, left and right" },
		{ value = "stack", label = "Stack: a column beside the enemy" },
	},
	keys = { "enemyDamage", "enemyPeriodic", "enemyPet" },
	owns = { enemyDamage = true, enemyPeriodic = true, enemyPet = true },
	words = { DODGE = true, PARRY = true, MISS = true, EVADE = true, IMMUNE = true, DEFLECT = true, REFLECT = true,
		RESIST = true, BLOCK = true, ABSORB = true },
	lanes = {},        -- [nameplate unit] = its lines
	loose = { lines = {} },   -- the lines of a plate that went, finishing where they stand
	-- the text size times this, per look (the game's numbers over enemies are
	-- about twice the size of the text over you; the column smaller), and
	-- times the game's World Text Scale, as its own numbers
	size = { rise = 3.2, fan = 2.9, stack = 1.5 },
	pool = {},         -- the dealt lines' spares (never shared with the self text's)
	stagger = 30,      -- Rise: a hit close behind the last, beside it in turn
	crit = 1.15,       -- a crit, times that (on top of the crit size every line has)
	glancing = 0.8,    -- a glancing blow, times that
	startY = 6,        -- Rise and Fan start on the enemy: over its plate's middle
	rise = 150,        -- Rise's way up, most of it at once (outCubic)
	fanX = 80, fanY = 120,
	hold = 0.2,        -- a hit before you are on the enemy's list: held this long for the threat update
	held = {},         -- those hits: { unit, at, kind, value, crit, glancing, colour, label } (pooled)
	spare = {},
	samples = {        -- Preview's (made up, plain): event, flag, amount, school
		{ "WOUND", "", 1284, 1 }, { "WOUND", "CRITICAL", 3051, 1 }, { "DODGE", "", 0, 1 }, { "WOUND", "", 212, 4 },
		{ "WOUND", "GLANCING", 96, 1 },
	},
}

-- the over-enemy switches: the game's own CVars, both spellings (this
-- client's Lua names none of them: probed when first asked)
local ENEMY = {
	enemyDamage = { "floatingCombatTextCombatDamage", "floatingCombatTextCombatDamage_v2" },
	enemyPeriodic = { "floatingCombatTextCombatLogPeriodicSpells", "floatingCombatTextCombatLogPeriodicSpells_v2" },
	enemyPet = { "floatingCombatTextPetMeleeDamage", "floatingCombatTextPetMeleeDamage_v2",
		also = { "floatingCombatTextPetSpellDamage", "floatingCombatTextPetSpellDamage_v2" } },
	enemyHealing = { "floatingCombatTextCombatHealing", "floatingCombatTextCombatHealing_v2" },
}

local M   -- (the module, registered below)
local Enemy = {}   -- the over-enemy CVars: probe, read, write (below)

local function Size(v, min, max, default)
	v = Num(v) or default
	if v < min then
		return min
	elseif v > max then
		return max
	end
	return v
end

M = MelloUI:RegisterModule("CombatText", {
	title = "Combat Text",
	desc = "The text that floats over your character in a fight (damage taken, heals, Dodge and Parry, procs, resources gained) in MelloUI's look, in one of three styles, or the game's own.",
	icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
	flavour = "Your hits taken, heals and procs in MelloUI's soft look, or the game's own text.",
	-- (a look: how the game's combat text is drawn, Game by default; the
	-- installer's setups leave it as it is, no Features row of its own)
	role = "look",
	enabledByDefault = true,
	new = NEW,
	-- the player's own game settings, given back when off (the game's text
	-- around you, its numbers over the enemies): never in a profile
	keep = { "savedDealt", "savedGameText" },
	defaults = {
		style = "game",
		dealt = "game",
		size = T.size,
		titleNotices = true,
		shadeSize = 1,
		spread = T.spread,
		lines = T.lines,
		taken = true,
		heals = true,
		notices = true,
		avoid = true,
		resource = true,
		combat = true,
		reputation = true,
	},
	options = {
		{ type = "dropdown", key = "style", name = "Combat Text Style", new = NEW, values = STYLES,
		  desc = "Who draws the text over your character. Game: the game's own, as it always was. Lanes: damage taken falls on your left, healing rises on your right, procs and Dodge / Parry above your head, resources under your feet. Feed: one column over your portrait, the newest on top. Classic: one stream over your head, like the game's, in MelloUI's font and soft shade." },
		{ type = "dropdown", key = "dealt", name = "Your Damage", new = NEW, values = DEALT.styles,
		  desc = "The numbers of the damage you deal, over the enemies. Game: the game's own numbers, as always. Rise, Fan or Stack: drawn by MelloUI at each enemy's nameplate in its soft look, the game's numbers switched off meanwhile: crits gold and bigger, spells violet, a dodge or parry as a word, about a second and a half each, only on enemies you or your pet are fighting. Rise, Fan and Stack draw your hits while you play solo. In a group, or where the game keeps threat hidden, the game's own numbers show, because only they know whose hit it is. With enemy nameplates off, the game's own numbers show too (the plates are where MelloUI draws)." },
		{ type = "button", name = "Preview", text = "Play", new = NEW,
		  hint = "a short burst in the chosen style",
		  desc = "Plays a few made-up lines (hits, a crit, heals, a Dodge, a proc) in the chosen style, so you can compare them without a fight. Also /mello combattext test.",
		  onClick = function() M.Preview() end },
		{ type = "slider", key = "size", name = "Text Around You", new = NEW, min = T.sizeMin, max = T.sizeMax, step = 1,
		  search = "combat text size",
		  desc = "The size of the text around your character in the Lanes, Feed and Classic styles. Crits are a third bigger. The Fonts' Interface text and Titles & headers sizes do not change it (only their faces). The numbers over the enemies have their own size: Numbers Over Enemies." },
		{ type = "toggle", key = "titleNotices", name = "Notices In Title Font", new = NEW,
		  desc = "Procs and auras in the title font, as the window titles. Off: in the text font, as the numbers." },
		{ type = "slider", key = "shadeSize", name = "Shade Size", new = NEW, min = 0, max = 1, step = 0.1, percent = true,
		  desc = "The size of the soft shade behind the combat text, the text over you and Your Damage alike. 100% is the notices' shade; less hugs the numbers closer; 0% shows none." },
		{ type = "slider", key = "spread", name = "Lane Spread", new = NEW, min = T.spreadMin, max = T.spreadMax, step = 5,
		  desc = "How far from your character the damage and healing lanes run, left and right. Move the whole text in Edit Layout." },
		{ type = "slider", key = "lines", name = "Most Lines", new = NEW, min = T.linesMin, max = T.linesMax, step = 1,
		  desc = "The most lines around your character at once: per lane for Lanes, in the stream for Classic, in the column for Feed. The oldest goes first. Your Damage keeps its own count per enemy." },
		{ type = "toggle", key = "taken", name = "Damage Taken", new = NEW,
		  desc = "The damage you take, crits bigger." },
		{ type = "toggle", key = "heals", name = "Healing", new = NEW,
		  desc = "The healing you get, and shields put on you." },
		{ type = "toggle", key = "notices", name = "Procs & Auras", new = NEW,
		  desc = "Abilities that light up (Overpower!), auras you gain or lose, interrupts and dispels." },
		{ type = "toggle", key = "avoid", name = "Dodge, Parry & Block", new = NEW,
		  desc = "Attacks that miss you: misses, dodges, parries, blocks, absorbs, resists and immunes." },
		{ type = "toggle", key = "resource", name = "Resources Gained", new = NEW,
		  desc = "Mana, rage, energy and focus you gain (+12 Rage)." },
		{ type = "toggle", key = "combat", name = "Entering & Leaving Combat", new = NEW,
		  desc = "A short line when a fight starts and when it ends." },
		{ type = "toggle", key = "reputation", name = "Reputation & Honor", new = NEW,
		  desc = "Reputation and honor you gain." },
		{ type = "toggle", key = "enemyDamage", name = "Damage Over Enemies", new = NEW,
		  get = function() return Enemy.Get("enemyDamage") end, missing = function() return Enemy.Missing("enemyDamage") end,
		  desc = "The numbers of your damage over the enemies (the game's own setting: drawn by the game in the Game Numbers Font, at Numbers Over Enemies' size)." },
		{ type = "toggle", key = "enemyPeriodic", name = "DoT Ticks Over Enemies", new = NEW,
		  get = function() return Enemy.Get("enemyPeriodic") end, missing = function() return Enemy.Missing("enemyPeriodic") end,
		  desc = "Your damage over time ticks over the enemies (the game's own setting)." },
		{ type = "toggle", key = "enemyPet", name = "Pet Damage Over Enemies", new = NEW,
		  get = function() return Enemy.Get("enemyPet") end, missing = function() return Enemy.Missing("enemyPet") end,
		  desc = "Your pet's damage over the enemies (the game's own setting)." },
		{ type = "toggle", key = "enemyHealing", name = "Healing Over Friends", new = NEW,
		  get = function() return Enemy.Get("enemyHealing") end, missing = function() return Enemy.Missing("enemyHealing") end,
		  desc = "The numbers of your healing over the ones you heal (the game's own setting)." },
	},
})

local function DB()
	return M.db
end

local function Style()
	local db = M.db
	local s = db and db.style
	if s == "lanes" or s == "feed" or s == "classic" then
		return s
	end
	return "game"
end

-- a style of MelloUI's on (the module on, the style not Game)
local function Ours()
	return M.isEnabled and Style() ~= "game"
end

-- Your Damage's look, and whether MelloUI draws it
local function Dealt()
	local db = M.db
	local d = db and db.dealt
	if d == "rise" or d == "fan" or d == "stack" then
		return d
	end
	return "game"
end

local function DealtOn()
	return M.isEnabled and Dealt() ~= "game"
end

-- the enemy nameplates shown (the game's switch, the V key); a secret or
-- unknown answer counts as shown
local function PlatesShown()
	if not (C_CVar and C_CVar.GetCVarBool) then
		return true
	end
	local ok, on = pcall(C_CVar.GetCVarBool, "nameplateShowEnemies")
	if ok and not Secret(on) then
		return on and true or false
	end
	return true
end

-- MelloUI draws your damage now: a look chosen, the plates there, solo
-- (in a group the hits cannot be told apart), and the threat lists readable
-- in this fight (DEALT.threatHidden: a secret answer seen; the fight's end
-- tries again)
local function DealtDrawing()
	return DealtOn() and PlatesShown() and not MelloUI.Threat.Grouped() and not DEALT.threatHidden
end

local function TextSize()
	local db = DB()
	return Size(db and db.size, T.sizeMin, T.sizeMax, T.size)
end

local function MostLines()
	local db = DB()
	return math.floor(Size(db and db.lines, T.linesMin, T.linesMax, T.lines))
end

local function Spread()
	local db = DB()
	return Size(db and db.spread, T.spreadMin, T.spreadMax, T.spread)
end

local function Pitch()
	return math.floor(TextSize() * 1.45 + 0.5)
end

--------------------------------------------------------------------------------
-- The over-enemy CVars (probed when first asked: the page's first open)
--------------------------------------------------------------------------------

local enemyName = {}      -- [key] = the CVar name this client has, or false
local enemyPending = {}   -- [key] = a value set in a fight, written after it

local function Known(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then
		return false
	end
	local ok, value = pcall(C_CVar.GetCVarInfo, name)
	return ok and value ~= nil and not Secret(value)
end

local function NameOf(list)
	for _, name in ipairs(list) do
		if Known(name) then
			return name
		end
	end
	return false
end

function Enemy.Name(key)
	local name = enemyName[key]
	if name == nil then
		local spec = ENEMY[key]
		name = spec and NameOf(spec) or false
		enemyName[key] = name
	end
	return name
end

function Enemy.Missing(key)
	if DEALT.owns[key] and DealtOn() then
		return TEXT.dealtOwns
	end
	if Enemy.Name(key) then
		return nil
	end
	return TEXT.missing
end

function Enemy.Get(key)
	local pending = enemyPending[key]
	if pending ~= nil then
		return pending
	end
	local name = Enemy.Name(key)
	if not name then
		return nil
	end
	local ok, value = pcall(C_CVar.GetCVarBool, name)
	if ok and not Secret(value) then
		return value and true or false
	end
	return nil
end

local events   -- the event frame (made for a style of ours, or a queued CVar)
local Events   -- (below)
local Apply    -- (below: the state the settings ask for)

local function SetCVar(name, value)
	if name and C_CVar and C_CVar.SetCVar then
		pcall(C_CVar.SetCVar, name, value)
	end
end

function Enemy.Write(key, value)
	local name = Enemy.Name(key)
	if not name then
		return
	end
	if MelloUI.InCombat() then
		enemyPending[key] = value and true or false
		Events()
		return
	end
	enemyPending[key] = nil
	local v = value and "1" or "0"
	SetCVar(name, v)
	local also = ENEMY[key].also
	if also then
		SetCVar(NameOf(also) or nil, v)
	end
end

function Enemy.Flush()
	for key, value in pairs(enemyPending) do
		enemyPending[key] = nil
		Enemy.Write(key, value)
	end
end

--------------------------------------------------------------------------------
-- The game's own text: kept coming, faded while a style of ours is on
--------------------------------------------------------------------------------

local S = {
	started = false, faded = false, hooked = false, settingAlpha = false, gameAlpha = 1,
	cvarPending = nil,   -- "on" / "off": the game's switch to set after the fight
	preview = false, samples = false,
}

local function GameFrame()
	local f = rawget(_G, "CombatText")
	if type(f) == "table" and f.SetAlpha then
		return f
	end
	return nil
end

local function OnGameAlpha(frame)
	if S.faded and not S.settingAlpha then
		S.settingAlpha = true
		frame:SetAlpha(0)
		S.settingAlpha = false
	end
end

local function FadeGame(on)
	local f = GameFrame()
	if not f then
		return
	end
	if on then
		if not S.faded then
			local a = Num(f:GetAlpha())
			S.gameAlpha = (a and a > 0) and a or 1
		end
		if not S.hooked then
			S.hooked = true
			hooksecurefunc(f, "SetAlpha", OnGameAlpha)
		end
		S.faded = true
		S.settingAlpha = true
		f:SetAlpha(0)
		S.settingAlpha = false
	elseif S.faded then
		S.faded = false
		f:SetAlpha(S.gameAlpha or 1)
	end
end

local function GameCVar()
	if not (C_CVar and C_CVar.GetCVar) then
		return nil
	end
	local ok, value = pcall(C_CVar.GetCVar, GAME_CVAR)
	return ok and Text(value) or nil
end

-- the game's switch on (its value noted when it was off), or back to what it
-- had; in a fight it waits for the end
local function GameSwitch(on)
	if MelloUI.InCombat() then
		S.cvarPending = on and "on" or "off"
		Events()
		return
	end
	S.cvarPending = nil
	local db = DB()
	if not db then
		return
	end
	if on then
		local now = GameCVar()
		if now ~= nil and now ~= "1" then
			if db.savedGameText == nil then
				db.savedGameText = now
			end
			SetCVar(GAME_CVAR, "1")
		end
	elseif db.savedGameText ~= nil then
		local saved = db.savedGameText
		db.savedGameText = nil
		SetCVar(GAME_CVAR, saved)
	end
end

-- Your Damage on: the game's damage, DoT and pet numbers over the enemies off
-- (each CVar's value noted, the first time); off: each back as it was. In a
-- fight it waits for the end
local function DealtOff(saved, name)
	if not name then
		return
	end
	if saved[name] == nil then
		local ok, v = pcall(C_CVar.GetCVar, name)
		v = ok and Text(v) or nil
		if v == nil then
			return
		end
		saved[name] = v
	end
	SetCVar(name, "0")
end

-- a CVar the game lets an addon set in a fight (its isSecure plainly false)
local function FreeInCombat(name)
	if not (name and C_CVar and C_CVar.GetCVarInfo) then
		return false
	end
	local ok, _, _, _, _, _, secure = pcall(C_CVar.GetCVarInfo, name)
	return ok and not Secret(secure) and secure == false
end

local function DealtFree()
	for _, key in ipairs(DEALT.keys) do
		local name = Enemy.Name(key)
		if name and not FreeInCombat(name) then
			return false
		end
		local also = ENEMY[key].also
		local other = also and NameOf(also) or nil
		if other and not FreeInCombat(other) then
			return false
		end
	end
	return true
end

local function DealtSwitch(on)
	if MelloUI.InCombat() and not DealtFree() then
		S.dealtPending = on and "on" or "off"
		Events()
		return
	end
	S.dealtPending = nil
	local db = DB()
	if not db then
		return
	end
	if on then
		local saved = db.savedDealt or {}
		db.savedDealt = saved
		for _, key in ipairs(DEALT.keys) do
			DealtOff(saved, Enemy.Name(key))
			local also = ENEMY[key].also
			if also then
				DealtOff(saved, NameOf(also) or nil)
			end
		end
	else
		local saved = db.savedDealt
		if saved then
			db.savedDealt = nil
			for name, v in pairs(saved) do
				SetCVar(name, v)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The lines: a sign, the main text (a number, a word or a notice), a tail
-- (a name or a word after it), on one band. One builder for the floating
-- lines and the feed's (which have the kind's mark in front)
--------------------------------------------------------------------------------

local TEXT_LOOK = MelloUI.Shade.TEXT
local PAD_X, FEATHER = TEXT_LOOK.padX, TEXT_LOOK.feather

-- the notice's Outlined Text (Tweaks noticeOutline, off by default); the
-- reskin off: outlined, as the game's floating texts
local function Outline()
	local Look = MelloUI.CentreLook
	return GameLook.Outline(Look and Look.Setting and Look.Setting("noticeOutline"))
end

-- the soft shadow (the reskin off: the game's black one)
local function Shadow(fs)
	GameLook.Shadow(fs, TEXT_LOOK.shadow)
end

-- the text font at a size (numbers: a Your Damage line's, the Game Numbers
-- Font's face); kept, so a line that keeps its size is not styled again
local function StyleText(fs, size, numbers)
	size = math.floor(size + 0.5)
	local key = numbers and -size or size
	if fs.melloSize == key then
		return
	end
	fs.melloSize = key
	local object = numbers and MelloUI.GameNumbersFont and MelloUI:GameNumbersFont() or _G.GameFontHighlight
	if type(object) == "table" then
		fs:SetFontObject(object)
		if MelloUI.StyleFont then
			-- (the size is Combat Text's own: the face's correction alone, never
			-- the Fonts' Interface text size; 0.19.4)
			MelloUI:StyleFont(fs, numbers and "fontDamage" or "fontText", object, size, "", Outline(), numbers or "own")
		end
	end
end

-- a notice: the title font (Notices In Title Font) at a size, else the text
-- font. Kit:TitleFont takes the font the string has as its base: the text
-- font at the size, out of StyleFont's registry first (its next 'fonts'
-- Fire would put the text face back)
local function StyleNotice(fs, size)
	size = math.floor(size + 0.5)
	local db = DB()
	local title = not db or db.titleNotices ~= false
	local key = title and -size or size
	if fs.melloSize == key then
		return
	end
	local Kit = MelloUI.Kit
	if Kit then
		Kit:TitleFont(fs, false)
	end
	fs.melloSize = nil
	StyleText(fs, size)
	if title and Kit then
		if MelloUI.StyleFont then
			MelloUI:StyleFont(fs, "fontText", nil)
		end
		Kit:TitleFont(fs, true, true)   -- (its size is Combat Text's: the title size slider passes it by)
	end
	fs.melloSize = key
end

-- a line's text regions, in order
local REGIONS = { "sign", "value", "word", "notice", "tail" }

-- (made with the game's font object: the client refuses a text on a string
-- with no font yet -- "FontString:SetText(): Font not set", the first
-- Preview, 2026-10-01; StyleText sets the size and face after)
local function NewFont(row)
	local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetWordWrap(false)
	fs:SetShadowOffset(TEXT_LOOK.shadowX, TEXT_LOOK.shadowY)
	Shadow(fs)
	return fs
end

-- a line's regions; `glyph`: the feed's mark in front
local function Build(row, glyph)
	row.sign = NewFont(row)
	row.value = NewFont(row)
	row.word = NewFont(row)
	row.notice = NewFont(row)
	row.tail = NewFont(row)
	GameLook.Paint(row.word, "text", "text")
	GameLook.Paint(row.notice, "selectedTrim", "text")
	GameLook.Paint(row.tail, "text", "text", 0.85)   -- (small text is never mutedText: the palette rule)
	if glyph then
		local g = row:CreateTexture(nil, "OVERLAY")
		row.glyph = g
	end
	row.band = MelloUI.Shade:Band(row, TEXT_LOOK)
	GameLook.Hide(row.band)   -- (no band in the game's look)
end

-- the colour of a number: the kind's meaning colour
local function Colour(fs, c)
	if c then
		fs:SetTextColor(c[1], c[2], c[3])
	end
end

-- a number or a name as the game gave it: a number broken up into groups
-- (BreakUpLargeNumbers takes a secret one and answers in kind), shown with
-- SetText only; nothing joined, compared or summed
local function SetValue(fs, v)
	if v == nil then
		fs:SetText("")
		return
	end
	if Secret(v) or type(v) == "number" then
		local ok, s = pcall(BreakUpLargeNumbers, v)
		if ok and s ~= nil then
			fs:SetText(s)
			return
		end
	end
	fs:SetText(v)
end

-- the entry (one table, filled per event)
local E = {}

local function Clear(e)
	e.kind, e.value, e.sign, e.crit, e.label, e.name, e.tail, e.colour, e.glyph, e.harmful = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
	e.who, e.glancing = nil, nil
	return e
end

-- Shade Size's share of the text look's shade (0..1)
local function ShadeShare()
	local db = DB()
	local v = Num(db and db.shadeSize) or 1
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

-- the regions laid for an alignment and a main text, only when they change
-- (a pooled line serves every kind); `size` the main text's, for its shade
local function Lay(row, align, main, hasTail, hasSign, size)
	local share = ShadeShare()
	size = math.floor((Num(size) or TextSize()) + 0.5)
	local key = align .. main .. (hasTail and "t" or "") .. (hasSign and "s" or "") .. size .. ":" .. share
	if row.laid == key then
		return
	end
	row.laid = key
	local m = row[main]
	local sign, tail, glyph = row.sign, row.tail, row.glyph
	for i = 1, #REGIONS do
		row[REGIONS[i]]:ClearAllPoints()
	end
	local edge = PAD_X + FEATHER
	local gap = hasTail and T.gap or 0
	if align == "RIGHT" then
		local last = hasTail and tail or m
		last:SetPoint("RIGHT", row, "RIGHT", -edge, 0)
		if hasTail then
			m:SetPoint("RIGHT", tail, "LEFT", -gap, 0)
		end
		sign:SetPoint("RIGHT", m, "LEFT", 0, 0)
	elseif align == "CENTER" then
		m:SetPoint("CENTER", row, "CENTER", 0, 0)
		sign:SetPoint("RIGHT", m, "LEFT", 0, 0)
		tail:SetPoint("LEFT", m, "RIGHT", gap, 0)
	else
		local first = hasSign and sign or m
		if glyph then
			glyph:ClearAllPoints()
			glyph:SetPoint("LEFT", row, "LEFT", edge, 0)
			first:SetPoint("LEFT", glyph, "RIGHT", T.gap, 0)
		else
			first:SetPoint("LEFT", row, "LEFT", edge, 0)
		end
		if hasSign then
			m:SetPoint("LEFT", sign, "RIGHT", 0, 0)
		end
		tail:SetPoint("LEFT", m, "RIGHT", gap, 0)
	end
	-- the band from the first region shown to the last, its size Shade
	-- Size's share: at 100% the text look's own padding and soft ends; less
	-- pulls them in and the band into the text's box (a big number's box is
	-- far taller than its digits); 0% no band
	local band = row.band
	if share <= 0 then
		GameLook.Show(band, false)
		return
	end
	GameLook.Show(band, true)
	band:SetFeather(math.max(4, FEATHER * share))
	local left = (glyph and align == "LEFT") and glyph or (hasSign and sign or m)
	local right = hasTail and tail or m
	local padY = MelloUI.Shade:LinePadY(TextSize()) * share - (1 - share) * size * 0.2
	band:Anchor(left, right, PAD_X * share, padY)
end

-- a line's texts and look from the entry
local function Fill(row, e, align, scale)
	row.sample = nil
	local size = TextSize() * (scale or 1)
	local main = e.kind == "notice" and not e.harmful and "notice"
		or ((e.kind == "avoid" or e.kind == "combat") and "word") or "value"
	local big = e.crit and T.crit or 1
	local hasSign = main == "value" and e.sign ~= nil
	-- (the healer's name: the feed's rows only, the floating lines stay short)
	local who = row.glyph and e.who or nil
	local hasTail = e.tail ~= nil or e.name ~= nil or who ~= nil
	-- the sizes and colours first (a string has its font before its text)
	local numbers = row.dealt
	StyleText(row.sign, size * big, numbers)
	StyleText(row.value, size * big, numbers)
	StyleText(row.word, size, numbers)
	StyleNotice(row.notice, size * big)
	StyleText(row.tail, size * T.tail, numbers)
	Colour(row.sign, e.colour)
	Colour(row.value, e.colour)
	-- the texts: the main one, the others empty
	row.sign:SetText(hasSign and e.sign or "")
	if main == "value" then
		if e.value ~= nil then
			SetValue(row.value, e.value)
		else
			row.value:SetText(e.label or "")
		end
	else
		row.value:SetText("")
	end
	row.word:SetText(main == "word" and (e.label or "") or "")
	row.notice:SetText(main == "notice" and (e.label or "") or "")
	if e.name ~= nil then
		row.tail:SetText(e.name)
	elseif who ~= nil then
		row.tail:SetText(who)
	else
		row.tail:SetText(e.tail or "")
	end
	local glyph = row.glyph
	if glyph then
		local W = MelloUI.Widgets
		if e.glyph and W.Glyph(glyph, e.glyph) then
			local g = math.floor(TextSize() * T.glyph + 0.5)
			glyph:SetSize(g, g)
			-- (the kind's meaning colour, else the look's gold or white as it is
			-- now: a line lives a few seconds, the mark is never registered for
			-- a repaint)
			local c = e.colour
			if c then
				glyph:SetVertexColor(c[1], c[2], c[3])
			else
				glyph:SetVertexColor(GameLook.RoleColour(e.kind == "notice" and "gold" or "text"))
			end
			glyph:Show()
		else
			glyph:Hide()
		end
	end
	Lay(row, align, main, hasTail, hasSign, size * big)
end

-- a crit's gold and a hit's white as the look shows them now (one table
-- each, filled as asked: an entry makes no table of its own)
local RoleRGB
do
	local kept = { gold = { 1, 1, 1 }, text = { 1, 1, 1 } }
	RoleRGB = function(role)
		local t = kept[role]
		t[1], t[2], t[3] = GameLook.RoleColour(role)
		return t
	end
end

local function Restyle(row)
	for i = 1, #REGIONS do
		local fs = row[REGIONS[i]]
		if fs == row.notice then
			MelloUI.Kit:TitleFont(fs, false)
		end
		fs.melloSize = nil
	end
	row.laid = nil
end

local function ShadowRow(row)
	for i = 1, #REGIONS do
		Shadow(row[REGIONS[i]])
	end
end

--------------------------------------------------------------------------------
-- The floating lines (Lanes and Classic): a holder per style (its mover), a
-- pool of lines, the lanes (each its lines, oldest first)
--------------------------------------------------------------------------------

local float = {}   -- [style] = { holder, entry, lanes = { [name] = lane } }
local pool = {}    -- the spare floating lines (both styles share them)

local function FloatOn(style)
	return function()
		return M.isEnabled and Style() == style
	end
end

local function FloatHome(frame)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, -20)
end

local function Holder(style)
	local f = float[style]
	if f then
		return f
	end
	local lanes = style == "lanes"
	local holder = CreateFrame("Frame", lanes and "MelloUICombatLanes" or "MelloUICombatStream", UIParent)
	holder:SetSize(lanes and (2 * T.spreadMax + 200) or 360, lanes and 420 or 360)
	holder:SetFrameStrata("LOW")
	holder:SetClampedToScreen(true)
	holder:EnableMouse(false)
	FloatHome(holder)
	f = { holder = holder, lanes = {} }
	float[style] = f
	f.entry = MelloUI:RegisterMover(holder, holder, { key = lanes and "combatlanes" or "combatstream",
		default = FloatHome, min = 0.5, max = 2, base = 1, label = "Combat Text", page = OWNER, when = FloatOn(style) })
	if not MelloUI:RestorePosition(f.entry.key, holder) then
		FloatHome(holder)
	end
	return f
end

-- a floating line over (its fade ended, or dropped): out of its lane, back
-- with the spares
local function LineHidden(line)
	local lane = line.lane
	if not lane then
		return
	end
	line.lane = nil
	local lines = lane.lines
	for i = #lines, 1, -1 do
		if lines[i] == line then
			tremove(lines, i)
			break
		end
	end
	MelloUI.Anim:Stop(line)
	MelloUI.Anim:StopMirror(line)
	local spares = line.spares or pool
	spares[#spares + 1] = line
end
local OnLineHide   -- (LineHidden wrapped once, with the first line)

-- a spare line from `spares` (the self text's by default), else a new one
local function TakeLine(holder, spares)
	spares = spares or pool
	local n = #spares
	local line
	if n > 0 then
		line = spares[n]
		spares[n] = nil
		line:SetParent(holder)
	else
		line = CreateFrame("Frame", nil, holder)
		line:SetSize(T.lineWidth, 40)
		line:EnableMouse(false)
		line:Hide()
		line.spares = spares
		Build(line, false)
		if not OnLineHide then
			OnLineHide = Perf.Shared("OnHide on a combat text line (its line over)", LineHidden, "script")
		end
		Perf.SetScript(line, "OnHide", OnLineHide)
	end
	return line
end

-- where each kind goes: its lane, alignment, start and way (`dir` up 1 or
-- down -1, `travel` a share of T.travel)
local LANES = {
	lanes = {
		taken = { align = "RIGHT", side = -1, y = 40, dir = -1, travel = 1 },
		heal = { align = "LEFT", side = 1, y = -10, dir = 1, travel = 1 },
		notice = { align = "CENTER", y = 150, dir = 1, travel = 0.4 },
		resource = { align = "CENTER", y = -120, dir = -1, travel = 0.35, small = true },
	},
	classic = {
		stream = { align = "CENTER", y = 0, dir = 1, travel = 1.6, stagger = true },
	},
}
local LANE_OF = {
	lanes = { taken = "taken", heal = "heal", notice = "notice", avoid = "notice", combat = "notice", rep = "notice",
		resource = "resource" },
	classic = {},
}

local function Lane(f, style, name)
	local lane = f.lanes[name]
	if not lane then
		lane = { name = name, spec = LANES[style][name], lines = {}, last = -10, stack = 0, flip = 1 }
		f.lanes[name] = lane
	end
	return lane
end

local function FloatLine(style, e, hold)
	local f = Holder(style)
	local laneName = LANE_OF[style][e.kind] or "stream"
	local lane = Lane(f, style, laneName)
	local spec = lane.spec
	-- the lane full: its oldest goes now
	local most = MostLines()
	while #lane.lines >= most do
		local oldest = lane.lines[1]
		LineHidden(oldest)
		oldest:Hide()
	end
	local line = TakeLine(f.holder)
	line.lane = lane
	lane.lines[#lane.lines + 1] = line
	Fill(line, e, spec.align, spec.small and T.small or nil)
	-- a line close behind the last of its lane stacks a slot away from it
	local now = GetTime()
	if now - lane.last < T.stack then
		lane.stack = math.min(lane.stack + 1, most)
	else
		lane.stack = 0
	end
	lane.last = now
	local x = 0
	if spec.side then
		x = spec.side * Spread()
	elseif spec.stagger and (e.kind == "taken" or e.kind == "avoid") then
		lane.flip = -lane.flip
		x = lane.flip * 18
	end
	local y = spec.y - spec.dir * lane.stack * Pitch()
	line:ClearAllPoints()
	line:SetPoint(spec.align, f.holder, "CENTER", x, y)
	f.holder:Show()
	local Anim = MelloUI.Anim
	local held = hold or (e.crit and T.critHold or T.hold)
	Anim:Mirror(line, T.fadeIn, held, T.fadeOut)
	if not Anim.reduceMotion then
		Anim:To(line, "y", y + spec.dir * spec.travel * T.travel, T.fadeIn + held + T.fadeOut, "outQuad")
	end
	return line
end

-- Your Damage's lines, at an enemy's nameplate (no mover: the plate is the
-- place): one holder, a lane per plate (its lines, oldest first)
local dealtHolder

local function DealtHolder()
	if not dealtHolder then
		dealtHolder = CreateFrame("Frame", "MelloUICombatDealt", UIParent)
		dealtHolder:SetSize(1, 1)
		dealtHolder:SetPoint("CENTER")
		dealtHolder:SetFrameStrata("MEDIUM")
		dealtHolder:EnableMouse(false)
	end
	return dealtHolder
end

local function PlateOf(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return nil
	end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if ok and type(plate) == "table" and not Secret(plate) then
		return plate
	end
	return nil
end

-- a look's size: the base text size's share, times the game's World Text
-- Scale (the size of its own numbers over the enemies: Tweaks' Numbers Over
-- Enemies writes it); handed to Fill as a factor of the text around you's
-- size, so Text Around You never moves it (the configurator audit: one size
-- per thing on screen)
local function DealtScale(look)
	local world = 1
	if C_CVar and C_CVar.GetCVar then
		local ok, v = pcall(C_CVar.GetCVar, "WorldTextScale")
		world = ok and tonumber(Text(v)) or 1
		if world < 0.5 then
			world = 0.5
		elseif world > 3 then
			world = 3
		end
	end
	return (DEALT.size[look] or 1) * world * T.size / TextSize()
end

local function DealtLine(unit, e, hold)
	local plate = PlateOf(unit)
	if not plate then
		return nil
	end
	local look = Dealt()
	local lane = DEALT.lanes[unit]
	if not lane then
		lane = { lines = {}, last = -10, stack = 0, flip = 1 }
		DEALT.lanes[unit] = lane
	end
	local most = T.lines   -- (its own count: Most Lines is the text around you's)
	while #lane.lines >= most do
		local oldest = lane.lines[1]
		LineHidden(oldest)
		oldest:Hide()
	end
	local size = DealtScale(look)
	local pitch = math.floor(Pitch() * size + 0.5)
	-- Stack: the lines there a slot down under the new one (laid again from
	-- the offsets given: a plate's anchoring cannot be read back)
	if look == "stack" then
		for _, old in ipairs(lane.lines) do
			old.slotY = (old.slotY or 0) - pitch
			old:ClearAllPoints()
			pcall(old.SetPoint, old, "LEFT", plate, "TOPRIGHT", 6, old.slotY)
		end
	end
	local holder = DealtHolder()
	local line = TakeLine(holder, DEALT.pool)
	line.dealt = true   -- (the Game Numbers Font: Fill)
	line.lane = lane
	lane.lines[#lane.lines + 1] = line
	Fill(line, e, look == "stack" and "LEFT" or "CENTER",
		size * (e.glancing and DEALT.glancing or 1) * (e.crit and DEALT.crit or 1))
	-- (Rise: a hit close behind the last starts beside it, in turn)
	local now = GetTime()
	if now - lane.last < T.stack then
		lane.stack = math.min(lane.stack + 1, most)
	else
		lane.stack = 0
	end
	lane.last = now
	local point, rel, x, y = "CENTER", "CENTER", 0, DEALT.startY
	if look == "stack" then
		point, rel, x, y = "LEFT", "TOPRIGHT", 6, 0
		line.slotY = 0
	elseif look == "rise" and lane.stack > 0 then
		lane.flip = -lane.flip
		x, y = lane.flip * DEALT.stagger, y - pitch * 0.4
	end
	line:ClearAllPoints()
	if not pcall(line.SetPoint, line, point, plate, rel, x, y) then
		LineHidden(line)
		line:Hide()
		return nil
	end
	holder:Show()
	local Anim = MelloUI.Anim
	local held = hold or (e.crit and T.critHold or T.hold)
	local life = T.fadeIn + held + T.fadeOut
	Anim:Mirror(line, T.fadeIn, held, T.fadeOut)
	if look == "rise" then
		Anim:Slide(line, point, plate, rel, x, y, 0, DEALT.rise, life, "outCubic")
	elseif look == "fan" then
		lane.flip = -lane.flip
		Anim:Slide(line, point, plate, rel, x, y, lane.flip * DEALT.fanX, DEALT.fanY, life, "outCubic")
	end
	return line
end

-- every line of a plate gone at once (Your Damage off, the plates off)
local function DealtDrop(unit)
	local lane = DEALT.lanes[unit]
	if not lane then
		return
	end
	while #lane.lines > 0 do
		local line = lane.lines[1]
		LineHidden(line)
		line:Hide()
	end
end

-- a plate gone (its enemy dead -- the killing blow -- away or out of
-- sight): its lines leave its lane and finish their way and fade on the
-- frame the game hid, where it last stood, as the game's numbers do (where
-- a number is cannot be read: the plate's anchoring is secret). A plate the
-- game gives straight to another enemy takes them along, for the moment
-- they have left
local function DealtLetGo(unit)
	local lane = DEALT.lanes[unit]
	if not lane then
		return
	end
	local loose = DEALT.loose
	while #lane.lines > 0 do
		local line = tremove(lane.lines, 1)
		line.lane = loose
		loose.lines[#loose.lines + 1] = line
	end
end

local function ClearDealt()
	for unit in pairs(DEALT.lanes) do
		DealtDrop(unit)
	end
	local loose = DEALT.loose.lines
	while #loose > 0 do
		local line = loose[1]
		LineHidden(line)
		line:Hide()
	end
end

local function ClearFloat()
	for _, f in pairs(float) do
		for _, lane in pairs(f.lanes) do
			while #lane.lines > 0 do
				local line = lane.lines[1]
				LineHidden(line)
				line:Hide()
			end
		end
		f.holder:Hide()
	end
end

--------------------------------------------------------------------------------
-- The feed (B): MelloUI.Feed, over the player portrait, standing on its
-- bottom (the newest on top)
--------------------------------------------------------------------------------

local feed

local function FeedOn()
	return M.isEnabled and Style() == "feed"
end

local function FeedHome(frame)
	frame:ClearAllPoints()
	local pf = rawget(_G, "PlayerFrame")
	if type(pf) == "table" and pf.GetLeft then
		frame:SetPoint("BOTTOMLEFT", pf, "TOPLEFT", 10, 6)
	else
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 300)
	end
end

local function NewFeedRow(row)
	Build(row, true)
end

local function ApplyFeed(row, new, e)
	Fill(row, e, "LEFT")
end

feed = MelloUI.Feed:New({ name = "MelloUICombatFeed", key = "combatfeed", label = "Combat Text", page = OWNER,
	when = FeedOn, width = T.feedWidth, pitch = 30, max = MostLines, home = FeedHome, newRow = NewFeedRow,
	from = "bottom", fadeIn = 0.12, fadeOut = 1.0, slide = 0.15 })

--------------------------------------------------------------------------------
-- The entries: the game's kinds -> ours (Blizzard_CombatText's
-- CombatTextTypeInfo and CombatText.lua's own reading of each)
--------------------------------------------------------------------------------

local WORD = { "MISS", "DODGE", "PARRY", "EVADE", "IMMUNE", "DEFLECT", "REFLECT", "MISFIRE" }
local GUARD = { "BLOCK", "ABSORB", "RESIST" }
local KINDS = {
	DAMAGE = { "taken" }, SPELL_DAMAGE = { "taken" }, DAMAGE_SHIELD = { "taken" }, SPLIT_DAMAGE = { "taken" },
	DAMAGE_CRIT = { "taken", crit = true }, SPELL_DAMAGE_CRIT = { "taken", crit = true },
	HEAL = { "heal" }, PERIODIC_HEAL = { "heal" }, HEAL_ABSORB = { "heal" }, PERIODIC_HEAL_ABSORB = { "heal" },
	HEAL_CRIT = { "heal", crit = true }, PERIODIC_HEAL_CRIT = { "heal", crit = true },
	HEAL_CRIT_ABSORB = { "heal", crit = true },
	ABSORB_ADDED = { "heal", shield = true },
	ENERGIZE = { "resource" }, PERIODIC_ENERGIZE = { "resource" },
	SPELL_ACTIVE = { "notice", crit = true, data = true },
	SPELL_AURA_START = { "notice", data = true }, SPELL_CAST = { "notice", data = true },
	SPELL_AURA_START_HARMFUL = { "notice", data = true, harmful = true },
	SPELL_AURA_END = { "notice", fades = true }, SPELL_AURA_END_HARMFUL = { "notice", fades = true },
	INTERRUPT = { "notice", word = "INTERRUPT" }, SPELL_DISPELLED = { "notice", word = "SPELL_DISPELLED" },
	EXTRA_ATTACKS = { "notice", word = "EXTRA_ATTACKS" },
	FACTION = { "rep" }, HONOR_GAINED = { "rep", honor = true },
	ENTERING_COMBAT = { "combat", word = "ENTERING_COMBAT" }, LEAVING_COMBAT = { "combat", word = "LEAVING_COMBAT" },
}
for _, w in ipairs(WORD) do
	KINDS[w] = { "avoid", word = w }
	KINDS["SPELL_" .. w] = { "avoid", word = w }
end
for _, w in ipairs(GUARD) do
	KINDS[w] = { "avoid", word = w, partial = true }
	KINDS["SPELL_" .. w] = { "avoid", word = w, partial = true }
end

-- the setting each kind follows
local SWITCH = { taken = "taken", heal = "heals", notice = "notices", avoid = "avoid", resource = "resource",
	combat = "combat", rep = "reputation" }
local GLYPH = { taken = "hit", heal = "heal", notice = "proc", avoid = "avoid", resource = "gain", combat = "proc",
	rep = "gain" }

-- a word the game names (COMBAT_TEXT_DODGE, ENTERING_COMBAT ...), else ours
local function Word(w)
	return Text(rawget(_G, "COMBAT_TEXT_" .. w)) or Text(rawget(_G, w)) or TEXT[w] or w
end

-- a value that is there: a secret one, or a plain one that is not nil
local function Present(v)
	return Secret(v) or v ~= nil
end

-- a plain amount's sign test (a number, or a number given as text); nil
-- when it cannot be told (secret, not a number)
local function Positive(v)
	if Secret(v) then
		return nil
	end
	v = tonumber(v)
	if v == nil then
		return nil
	end
	return v > 0
end

-- the player's own name, plain (to leave out a heal's healer when it is you)
local function PlayerName()
	local ok, name = pcall(UnitName, "player")
	return ok and Text(name) or nil
end

-- the event's entry, or nil (a kind not shown, nothing to show)
local function Entry(kind, data, arg3, arg4)
	local spec = KINDS[kind]
	if not spec then
		return nil
	end
	local e = Clear(E)
	local k = spec[1]
	e.kind, e.crit, e.glyph = k, spec.crit or nil, GLYPH[k]
	local Meaning = MelloUI.Meaning
	if k == "taken" then
		-- (the game leaves out a hit of 0; a secret one cannot be told: shown)
		if Num(data) == 0 then
			return nil
		end
		e.value, e.sign, e.colour = data, "-", Meaning.combatTaken
	elseif k == "heal" then
		e.value, e.sign, e.colour = arg3, "+", Meaning.combatHeal
		if spec.shield then
			e.tail = TEXT.absorbed
		end
		-- the healer: a plain name that is not yours (the feed shows it)
		local name = Text(data)
		if name and name ~= "" and name ~= PlayerName() then
			e.who = name
		end
	elseif k == "resource" then
		if Positive(data) == false then
			return nil   -- (nothing gained)
		end
		e.value, e.sign, e.colour = data, "+", Meaning.combatResource
		local token = Text(arg3)
		if not token then
			local ok, _, own = pcall(UnitPowerType, "player")
			token = ok and Text(own) or nil
		end
		e.tail = token and Text(rawget(_G, token)) or nil
	elseif k == "avoid" then
		if spec.partial and Present(arg3) then
			-- a partial block, absorb or resist: the damage that came through
			e.kind, e.glyph = "taken", GLYPH.taken
			e.value, e.sign, e.colour = data, "-", Meaning.combatTaken
			e.tail = Word(spec.word)
		else
			e.label = Word(spec.word)
		end
	elseif k == "notice" then
		if spec.data then
			if not Present(data) then
				return nil
			end
			e.label = data
			if spec.harmful then
				e.harmful, e.colour = true, Meaning.combatTaken
			end
		elseif spec.fades then
			-- "<aura> fades": a plain name only (a format with a secret is not ours)
			local name = Text(data)
			local form = Text(rawget(_G, "AURA_END"))
			if not (name and form) then
				return nil
			end
			local ok, s = pcall(string.format, form, name)
			if not ok then
				return nil
			end
			e.label = s
		else
			e.label = Word(spec.word)
		end
	elseif k == "rep" then
		local amount = spec.honor and data or arg3
		local up = Positive(amount)
		if up == nil and not Secret(amount) then
			return nil
		end
		e.value, e.colour = amount, Meaning.combatResource
		e.sign = up == true and "+" or nil
		e.tail = spec.honor and Word("HONOR") or (Text(data) or nil)
		if not spec.honor and Secret(data) then
			e.name = data
		end
	elseif k == "combat" then
		e.label = Word(spec.word)
	end
	return e
end

-- an enemy of your fights: one you can attack that no one else has tapped
-- (a question the game keeps secret: shown, as the game would), and that
-- you or your pet are on the threat list of. Answers "held" when you are
-- not on it (yet), nil when the list is secret
local function Fought(unit)
	local okA, attackable = pcall(UnitCanAttack, "player", unit)
	if okA and not Secret(attackable) and not attackable then
		return false
	end
	local okT, denied = pcall(UnitIsTapDenied, unit)
	if okT and not Secret(denied) and denied then
		return false
	end
	local Threat = MelloUI.Threat
	local mine = Threat.Read("player", unit)
	if type(mine) == "number" then
		return true
	end
	local pet = Threat.Read("pet", unit)
	if type(pet) == "number" then
		return true
	end
	if mine == nil or pet == nil then
		return nil   -- (a secret list: who hit it cannot be told)
	end
	return "held"
end

-- a hit an enemy took (UNIT_COMBAT's event, flag, amount, school), as the
-- game's own CombatFeedback reads it: a wound a number (a crit or a crushing
-- blow bigger, a glancing one smaller; a spell violet), a miss of any kind a
-- word; a heal or a gain on the enemy nothing
local function DealtEntry(event, flags, amount, school)
	if Secret(event) or type(event) ~= "string" then
		return nil
	end
	local e = Clear(E)
	local flag = Text(flags)
	if event == "WOUND" then
		if Num(amount) == 0 then
			if flag and DEALT.words[flag] then
				e.kind, e.label = "avoid", Word(flag)
				return e
			end
			return nil
		end
		e.kind, e.value = "dealt", amount
		e.crit = (flag == "CRITICAL" or flag == "CRUSHING") or nil
		e.glancing = flag == "GLANCING" or nil
		local physical = Enum and Enum.Damageclass and Enum.Damageclass.MaskPhysical or 1
		local s = Num(school)
		e.colour = e.crit and RoleRGB("gold") or ((s and s ~= physical) and MelloUI.Meaning.combatSpell)
			or RoleRGB("text")
		return e
	elseif DEALT.words[event] then
		e.kind, e.label = "avoid", Word(event)
		return e
	end
	return nil
end

--------------------------------------------------------------------------------
-- Showing an entry in the chosen style
--------------------------------------------------------------------------------

local function Wanted(e)
	local db = DB()
	local key = SWITCH[e.kind]
	return not (db and key and db[key] == false)
end

local function Show(e, hold)
	local style = Style()
	if style == "feed" then
		feed:SetPitch(Pitch())
		return feed:Put("line", nil, hold or T.feedHold, ApplyFeed, e)
	elseif style == "lanes" or style == "classic" then
		return FloatLine(style, e, hold)
	end
	return nil
end

-- /mello combattext order (docs/plans/fps-portrait-fix.md section 7):
-- for ORDER_TIME seconds, the order of UNIT_COMBAT and UNIT_THREAT_LIST_UPDATE
-- on the plates in the chat, to see whether your first hit comes before the
-- update that puts you on the list
local ORDER_TIME = 15
local function OrderLog(text, ...)
	if S.orderUntil and GetTime() < S.orderUntil then
		MelloUI:Print("%.2f " .. text, GetTime() % 100, ...)
	end
end

function M.OrderLog()
	S.orderUntil = GetTime() + ORDER_TIME
	MelloUI:Print("Combat Text: the order of hits and threat updates on the plates for %d seconds. Pull a fresh mob.", ORDER_TIME)
	Events()
end
M.SlashWords = { order = M.OrderLog }

-- a hit held for the threat update: drawn when you are on the list in time
local function Hold(unit, e)
	local h = tremove(DEALT.spare) or {}
	h.unit, h.at = unit, GetTime()
	h.kind, h.value, h.crit, h.glancing, h.colour, h.label = e.kind, e.value, e.crit, e.glancing, e.colour, e.label
	DEALT.held[#DEALT.held + 1] = h
	if not S.holdTimer then
		S.holdTimer = true
		C_Timer.After(DEALT.hold + 0.05, function()
			S.holdTimer = false
			local now, held = GetTime(), DEALT.held
			for i = #held, 1, -1 do
				if now - held[i].at >= DEALT.hold then
					DEALT.spare[#DEALT.spare + 1] = tremove(held, i)
				end
			end
			if #held > 0 then
				S.holdTimer = true
				C_Timer.After(DEALT.hold, function()
					S.holdTimer = false
					for i = #DEALT.held, 1, -1 do
						DEALT.spare[#DEALT.spare + 1] = tremove(DEALT.held, i)
					end
				end)
			end
		end)
	end
end

-- the unit's threat list changed: its held hits drawn when you are on it now
local function Release(unit)
	local held = DEALT.held
	if #held == 0 then
		return
	end
	local ok = Fought(unit) == true
	local now = GetTime()
	for i = 1, #held do
		local h = held[i]
		if h.unit == unit and now - h.at < DEALT.hold + 0.05 then
			if ok then
				local e = Clear(E)
				e.kind, e.value, e.crit, e.glancing, e.colour, e.label = h.kind, h.value, h.crit, h.glancing, h.colour, h.label
				DealtLine(unit, e)
			end
			h.at = -math.huge   -- (spent: dropped at the next sweep)
		end
	end
end

local function OnEvent(_, event, arg1, ...)
	if event == "UNIT_COMBAT" then
		-- the plates only (the same hit comes for target too)
		if Secret(arg1) or type(arg1) ~= "string" or not arg1:find("^nameplate%d") then
			return
		end
		local drawing = DealtDrawing()
		local logging = S.orderUntil and GetTime() < S.orderUntil
		if not (drawing or logging) then
			return
		end
		local fought = Fought(arg1)
		if logging then
			OrderLog("UNIT_COMBAT %s %s (on its list: %s)", arg1, tostring(Text((...)) or "?"),
				fought == true and "yes" or fought == "held" and "no" or tostring(fought))
		end
		if not drawing then
			return
		end
		if fought == nil then
			-- the list secret: whose hit cannot be told, the game's numbers
			-- for the rest of this fight
			DEALT.threatHidden = true
			Apply()
			return
		end
		if not fought then
			return
		end
		local e = DealtEntry(...)
		if e then
			if fought == "held" then
				Hold(arg1, e)
			else
				DealtLine(arg1, e)
			end
		end
	elseif event == "UNIT_THREAT_LIST_UPDATE" then
		if not Secret(arg1) and type(arg1) == "string" and arg1:find("^nameplate%d") then
			OrderLog("UNIT_THREAT_LIST_UPDATE %s", arg1)
			Release(arg1)
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		-- solo or grouped: MelloUI's numbers or the game's
		Apply()
	elseif event == "CVAR_UPDATE" then
		-- the enemy nameplates on or off: MelloUI's numbers or the game's
		local name = Text(arg1)
		if name and name:lower() == "nameplateshowenemies" then
			Apply()
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		if not Secret(arg1) and type(arg1) == "string" then
			DealtLetGo(arg1)
		end
	elseif event == "COMBAT_TEXT_UPDATE" then
		if not Ours() or Secret(arg1) or type(arg1) ~= "string" then
			return
		end
		local data, arg3, arg4
		if C_CombatText and C_CombatText.GetCurrentEventInfo then
			local ok, a, b, c = pcall(C_CombatText.GetCurrentEventInfo)
			if ok then
				data, arg3, arg4 = a, b, c
			end
		end
		local e = Entry(arg1, data, arg3, arg4)
		if e and Wanted(e) then
			Show(e)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if Ours() then
			local e = Entry("ENTERING_COMBAT")
			if e and Wanted(e) then
				Show(e)
			end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		Enemy.Flush()
		if DEALT.threatHidden then
			DEALT.threatHidden = false
			Apply()
		end
		if S.cvarPending then
			GameSwitch(S.cvarPending == "on")
		end
		if S.dealtPending then
			DealtSwitch(S.dealtPending == "on")
		end
		if Ours() then
			local e = Entry("LEAVING_COMBAT")
			if e and Wanted(e) then
				Show(e)
			end
		end
		Events()
	elseif event == "ADDON_LOADED" then
		if arg1 == "Blizzard_CombatText" then
			if Ours() then
				FadeGame(true)
			end
			Events()
		end
	end
end

-- the events this state needs: a style of ours its source; a fight's end
-- while a CVar waits; the game's text not loaded yet while ours is on
Events = function()
	local want = Ours()
	local chosen = DealtOn()
	local dealt = chosen and PlatesShown()
	local waiting = S.cvarPending ~= nil or S.dealtPending ~= nil or next(enemyPending) ~= nil
	if not (want or chosen or waiting) then
		if events then
			events:UnregisterAllEvents()
		end
		return
	end
	if not events then
		events = CreateFrame("Frame")
		Perf.SetScript(events, "OnEvent", OnEvent)
	end
	events:UnregisterAllEvents()
	if want then
		events:RegisterEvent("COMBAT_TEXT_UPDATE")
		events:RegisterEvent("PLAYER_REGEN_DISABLED")
		if not GameFrame() then
			events:RegisterEvent("ADDON_LOADED")
		end
	end
	if chosen then
		events:RegisterEvent("CVAR_UPDATE")
		events:RegisterEvent("GROUP_ROSTER_UPDATE")
	end
	if dealt or (S.orderUntil and GetTime() < S.orderUntil) then
		events:RegisterEvent("UNIT_COMBAT")
		events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
		events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	end
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
end

--------------------------------------------------------------------------------
-- Samples: Edit Layout's (held on the plate while it shows) and Preview's
-- burst (made-up plain lines)
--------------------------------------------------------------------------------

local SAMPLE = {
	{ "taken", 61 }, { "heal", 180, name = "Renew" }, { "avoid", label = "DODGE" }, { "taken", 245 },
	{ "notice", label = "Overpower!", crit = true }, { "resource", 12, tail = "Rage" }, { "taken", 1020, crit = true },
	{ "heal", 75 }, { "avoid", label = "PARRY" }, { "heal", 46, tail = "absorb" },
}
local SIGN = { taken = "-", heal = "+", resource = "+" }
local COLOUR = { taken = "combatTaken", heal = "combatHeal", resource = "combatResource" }

local function SampleEntry(s)
	local e = Clear(E)
	local k = s[1]
	e.kind, e.value, e.sign, e.crit, e.glyph = k, s[2], SIGN[k], s.crit, GLYPH[k]
	e.label = k == "avoid" and Word(s.label) or s.label
	e.who, e.tail = s.name, s.tail
	e.colour = COLOUR[k] and MelloUI.Meaning[COLOUR[k]] or nil
	return e
end

-- Preview's burst: one line every 0.18 s, from one timer chain: the text
-- over you in the chosen style, and Your Damage at your target's plate
local burst = 0
local function BurstStep()
	burst = burst + 1
	local s = Ours() and SAMPLE[burst] or nil
	local d = DealtDrawing() and PlateOf("target") and DEALT.samples[burst] or nil
	if not (s or d) then
		burst = 0
		return
	end
	if s then
		Show(SampleEntry(s))
	end
	if d then
		local e = DealtEntry(d[1], d[2], d[3], d[4])
		if e then
			DealtLine("target", e)
		end
	end
	C_Timer.After(0.18, BurstStep)
end

function M.Preview()
	if not M.isEnabled then
		return
	end
	local ours, dealt = Ours(), DealtDrawing()
	if not (ours or DealtOn()) then
		MelloUI:Announce(TEXT.gameStyle, "info")
		return
	end
	if not ours and not (dealt and PlateOf("target")) then
		MelloUI:Announce(TEXT.dealtTarget, "info")
		return
	end
	if burst > 0 then
		burst = 0   -- (a burst running: start again)
	end
	BurstStep()
end

-- the preview's fight (0.17.0, Core/Preview.lua): each of its hits one
-- sample line over you in the chosen style, and Your Damage at your target's
-- plate while you have a target (the samples in turn)
local function OnPreview(beat, _, n)
	local P = MelloUI.Preview
	if beat ~= "hit" or not M.isEnabled or type(n) ~= "number" or not (P and P:Plays("combattext")) then
		return
	end
	if Ours() then
		Show(SampleEntry(SAMPLE[(n - 1) % #SAMPLE + 1]))
	end
	local d = DealtDrawing() and PlateOf("target") and DEALT.samples[(n - 1) % #DEALT.samples + 1] or nil
	if d then
		local e = DealtEntry(d[1], d[2], d[3], d[4])
		if e then
			DealtLine("target", e)
		end
	end
end

-- /mello combattext test
function M:SlashTest()
	M.Preview()
end

-- Edit Layout's samples: a line in every lane (the feed: three), held while
-- it shows, faded when it closes
local held = {}   -- the sample lines shown
local function Samples()
	local want = Ours() and MelloUI:EditingLayout() and true or false
	if want == S.samples then
		return
	end
	S.samples = want
	if want then
		local style = Style()
		local list = style == "lanes" and { 1, 2, 5, 6 } or { 1, 2, 5 }
		for _, i in ipairs(list) do
			local row = Show(SampleEntry(SAMPLE[i]), T.sampleHold)
			if row then
				row.sample = true
				held[#held + 1] = row
			end
		end
	else
		for i = #held, 1, -1 do
			local row = held[i]
			held[i] = nil
			-- (still a sample: a line taken again since is another's)
			if row.sample and row:IsShown() then
				MelloUI.Anim:Mirror(row, 0, 0, T.fadeOut)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Turning it on and off
--------------------------------------------------------------------------------

-- fn(line) for every line made: the spares, the floating lanes', Your
-- Damage's, the feed's
local function EachLine(fn)
	for _, line in ipairs(pool) do
		fn(line)
	end
	for _, f in pairs(float) do
		for _, lane in pairs(f.lanes) do
			for _, line in ipairs(lane.lines) do
				fn(line)
			end
		end
	end
	for _, lane in pairs(DEALT.lanes) do
		for _, line in ipairs(lane.lines) do
			fn(line)
		end
	end
	for _, line in ipairs(DEALT.loose.lines) do
		fn(line)
	end
	for _, line in ipairs(DEALT.pool) do
		fn(line)
	end
	feed:Each(fn)
end

local function RestyleAll()
	EachLine(Restyle)
	feed:SetPitch(Pitch())
end

local function Repaint()
	EachLine(ShadowRow)
end

-- the reskin switched: the lines there are styled again at their next fill,
-- their shadows now
local function OnLook()
	EachLine(Restyle)
	EachLine(ShadowRow)
end

-- the state the settings ask for: a style of ours on (the game's text kept
-- coming and faded), or the game's own back
Apply = function()
	local db = DB()
	if DealtDrawing() then
		DealtSwitch(true)
		S.dealtStarted = true
	elseif S.dealtStarted or (db and db.savedDealt ~= nil) then
		S.dealtStarted = false
		DealtSwitch(false)
		ClearDealt()
	end
	if Ours() then
		GameSwitch(true)
		FadeGame(true)
		S.started = true
	elseif S.started or (db and db.savedGameText ~= nil) then
		S.started = false
		FadeGame(false)
		GameSwitch(false)
		ClearFloat()
		feed:Clear()
		S.samples = false
		for i = #held, 1, -1 do
			held[i] = nil
		end
	end
	Events()
end

local function OnSetting(module, key)
	if module == "Tweaks" and key == "noticeOutline" then
		RestyleAll()
	end
end

local function OnEditLayout()
	Samples()
end

local function OnRestart()
	if feed.ui and M.isEnabled then
		RestyleAll()
		feed:Place()
	end
	Apply()
	Samples()
end

local function Start()
	if M.isEnabled then
		Apply()
	end
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	MelloUI:On("setting", OnSetting, OWNER)
	MelloUI:On("editlayout", OnEditLayout, OWNER)
	MelloUI:On("restart", OnRestart, OWNER)
	MelloUI:On("palette", Repaint, OWNER)
	MelloUI:On("preview", OnPreview, OWNER)
	GameLook.Watch(M, OnLook)   -- (the reskin switched: the lines shown restyled)
	-- Game: nothing more (no frame, no event, no CVar)
	if Style() ~= "game" or Dealt() ~= "game" or (db and (db.savedGameText ~= nil or db.savedDealt ~= nil)) then
		MelloUI:AfterLogin(Start)
	end
end

function M:OnDisable()
	MelloUI:Off(OWNER)
	burst = 0
	Apply()   -- (the game's own back, when a style of ours was on)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "style" then
		Apply()
		RestyleAll()
		Samples()
	elseif key == "dealt" then
		Apply()
	elseif key == "size" or key == "titleNotices" or key == "shadeSize" then
		RestyleAll()
	elseif key == "lines" then
		feed:Fit()
	elseif ENEMY[key] then
		Enemy.Write(key, value)
	end
end
