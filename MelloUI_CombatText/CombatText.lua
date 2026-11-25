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
-- One look whatever the reskin (onelook stage E): the band, the palette's
-- soft shadow, outlined only with Outlined Text on.
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
-- each enemy's nameplate. (2.1.85: the looks redone -- Pop, Slam and Stamp
-- in place of Rise, Beside, Fan and Stack, DEALT.look below; Outlined Numbers;
-- a spell's hit in its school's colour.) A crit bigger, a glancing blow
-- smaller. The source is UNIT_COMBAT for the plates' units
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

-- (0.19.9) an addon of its own, MelloUI_CombatText (docs/plans/split-addons.md):
-- MelloUI is the global the core sets (its own namespace in a world that
-- loads every file as MelloUI's); its load timed under its addon's name
local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_CombatText (Combat Text)")
local GameLook = MelloUI.Look   -- (the palette's paint, outline and shadow)
local hooksecurefunc = Perf.hooksecurefunc

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text

local pairs, ipairs, type, pcall, tremove = pairs, ipairs, type, pcall, table.remove

local OWNER = "CombatText"
local GAME_CVAR = "enableFloatingCombatText"

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
	auraQuiet = 10,                          -- an aura that comes or goes again within this many seconds: told once
}

local TEXT = {
	gameStyle = "Personal Combat Text Style and Combat Damage Style are both Game: the game draws them. Pick Lanes, Feed or Classic, or a Combat Damage Style, to preview MelloUI's.",
	dealtTarget = "Target an enemy, with enemy nameplates on, to preview Combat Damage at its nameplate.",
	missing = "Not in this client",
	dealtOwns = "Off while MelloUI draws your damage (Combat Damage Style)",
	healsOwns = "Off while MelloUI draws your healing (Healing Numbers)",
	editPick = "Pick Pop, Slam or Stamp as Personal Combat Text Style first: their lines have areas you can place.",
	editBusy = "Close Edit Layout first, then press Edit Position again.",
	-- words the game names itself (COMBAT_TEXT_*); these when it does not
	MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", EVADE = "Evade", IMMUNE = "Immune", DEFLECT = "Deflect",
	REFLECT = "Reflect", MISFIRE = "Misfire", BLOCK = "Block", ABSORB = "Absorb", RESIST = "Resist",
	INTERRUPT = "Interrupted", SPELL_DISPELLED = "Dispelled", EXTRA_ATTACKS = "Extra Attack",
	ENTERING_COMBAT = "+Combat", LEAVING_COMBAT = "-Combat", HONOR = "Honor",
	absorbed = "absorb",
}

local STYLES = {
	{ value = "game", label = "Game (Blizzard)" },
	-- (2.1.85: the three looks of Combat Damage Style for the text around you too, each kind of line in its own area)
	{ value = "pop", label = "Pop: lands beside your character" },
	{ value = "slam", label = "Slam: thrown off on an arc" },
	{ value = "stamp", label = "Stamp: tidy columns" },
	{ value = "lanes", label = "Lanes: round your character" },
	{ value = "feed", label = "Feed: over your portrait" },
	{ value = "classic", label = "Classic: one stream, restyled" },
}

-- Your Damage (the header): its looks, the game's numbers it stands in for,
-- the hits that are words, its numbers' sizes and ways
local DEALT = {
	styles = {
		{ value = "game", label = "Game (Blizzard)" },
		{ value = "pop", label = "Pop: lands above the plate" },
		{ value = "slam", label = "Slam: thrown out on an arc" },
		{ value = "stamp", label = "Stamp: a column beside the plate" },
	},
	-- (2.1.85) the looks of before, read as the new one nearest to them
	old = { rise = "pop", side = "pop", fan = "pop", stack = "stamp" },
	outlines = { { value = "thick", label = "Thick" }, { value = "thin", label = "Thin" }, { value = "none", label = "None" } },
	most = 8,          -- the most lines at one plate (its own count: Most Lines is the text around you's)
	word = 0.6,        -- a word (Dodge, Parry ...), times the look's size
	tick = 0.62,       -- a tick of damage over time, times the look's size
	-- the combat log's lines (DEALT.Frame below): this frame's counts, its hits waiting for the frame's end, your
	-- swings whose numbers are still to come (0.3 to 1.3 s after the swing: the user's runs showed 0.48 to 1.10)
	log = { at = -1, lines = 0, swings = 0, casts = 0, hits = {}, n = 0, pending = {}, spare = {}, timer = false,
		lagMin = 0.3, lagMax = 1.3 },
	-- a hit's school, as the game numbers them (UNIT_COMBAT's last value): its meaning colour's key
	schools = { { 2, "combatHoly" }, { 4, "combatFire" }, { 8, "combatNature" }, { 16, "combatFrost" },
		{ 32, "combatShadow" }, { 64, "combatArcane" } },
	keys = { "enemyDamage", "enemyPeriodic", "enemyPet" },
	owns = { enemyDamage = true, enemyPeriodic = true, enemyPet = true },
	words = { DODGE = true, PARRY = true, MISS = true, EVADE = true, IMMUNE = true, DEFLECT = true, REFLECT = true,
		RESIST = true, BLOCK = true, ABSORB = true },
	lanes = {},        -- [nameplate unit] = its lines
	loose = { lines = {} },   -- the lines of a plate that went, finishing where they stand
	-- the text size times this, per look (the game's numbers over enemies are
	-- about twice the size of the text over you; the column smaller), and
	-- times the game's World Text Scale, as its own numbers
	size = { pop = 2.9, slam = 2.9, stamp = 2.9 },
	pool = {},         -- the dealt lines' spares (never shared with the self text's)
	crit = 1.15,       -- a crit, times that (on top of the crit size every line has)
	glancing = 0.8,    -- a glancing blow, times that
	hold = 0.2,        -- a hit before you are on the enemy's list: held this long for the threat update
	held = {},         -- those hits: { unit, at, kind, value, crit, glancing, colour, label } (pooled)
	spare = {},
	samples = {        -- Preview's (made up, plain): event, flag, amount, school
		{ "WOUND", "", 1284, 1 }, { "WOUND", "", 212, 4 }, { "WOUND", "CRITICAL", 3051, 1 }, { "DODGE", "", 0, 1 },
		{ "WOUND", "", 468, 16 }, { "WOUND", "GLANCING", 96, 1 }, { "WOUND", "", 730, 32 }, { "WOUND", "CRITICAL", 2210, 4 },
	},
	-- Preview's on a friend's plate: flag, amount
	heals = { { "", 412 }, { "", 96 }, { "CRITICAL", 1310 }, { "", 388 }, { "", 96 }, { "", 505 } },
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
	desc = "The text around your character in a fight (damage taken, heals, procs) in MelloUI's look, or the game's own.",
	icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
	flavour = "Your hits taken, heals and procs in MelloUI's soft look, or the game's own text.",
	enabledByDefault = true,
	-- the player's own game settings, given back when off (the game's text
	-- around you, its numbers over the enemies): never in a profile
	keep = { "savedDealt", "savedGameText" },
	defaults = {
		style = "game",
		dealt = "game",
		dealtScale = 0.7,   -- (0.25.0: Your Damage Size; players found the numbers too big)
		dealtGroups = true,   -- (2.1.85: Your Damage In Groups, by the combat log's lines)
		dealtHeals = true,    -- (2.1.85: Healing Numbers, your heals at the friend's nameplate)
		dealtOutline = "thick",   -- (2.1.85: Number Outline, the user: "the option to add outline to the damage text")
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
		-- (2.1.85; the user, 2026-11-24, of the two dropdowns: "First one is the Personal Combat Text Style, second one
		-- is Combat Damage Style", and of the two sliders: "first one should scale the Personal Combat Text Style,
		-- second one Combat Damage Style") the names; in the code `style` and `dealt` (Your Damage) as before
		{ type = "dropdown", key = "style", name = "Personal Combat Text Style", values = STYLES,
		  desc = "How the text around your character is shown. Game: the game's own. Pop, Slam or Stamp: MelloUI's new looks, each kind of line in an area of its own (Edit Position). Lanes, Feed and Classic: the earlier looks." },
		{ type = "button", name = "Edit Position", text = "Edit", new = "2.1.85",
		  hint = "move and size each area",
		  desc = "Opens Edit Layout with only Combat Text's areas: Damage Taken, Healing, Procs and Resources. Drag one to move it, use the mouse wheel to size it. For Pop, Slam and Stamp.",
		  onClick = function() M.EditPosition() end },
		{ type = "dropdown", key = "dealt", name = "Combat Damage Style", values = DEALT.styles,
		  desc = "How your damage numbers over enemies look. Game: the game's own. Pop, Slam or Stamp: MelloUI's." },
		{ type = "toggle", key = "dealtGroups", name = "Combat Damage In Groups", new = "2.1.85",
		  desc = "In a group, MelloUI shows your own hits: the ones the game's combat log names as yours. It needs the Combat Log's filter on My actions, and your pet's hits are not shown. Off: the game's own numbers in a group." },
		-- (2.1.85; the user, 2026-11-24: "You forgot the Healing Numbers in the Damage Numbers, the healing that appears
		-- above the friendly player when healing him")
		{ type = "toggle", key = "dealtHeals", name = "Healing Numbers", new = "2.1.85",
		  missing = function() return not Enemy.Name("enemyHealing") and TEXT.missing or nil end,
		  desc = "Your heals in the same look, at the nameplate of the friend you heal, in place of the game's own healing numbers. It needs friendly nameplates shown and the Combat Log's filter on My actions. Where MelloUI cannot draw them (friendly nameplates off, or inside dungeons and raids, where the game keeps friendly nameplates to itself) the game's own numbers show. Off: always the game's own." },
		{ type = "dropdown", key = "dealtOutline", name = "Number Outline", new = "2.1.85", values = DEALT.outlines,
		  desc = "The dark outline around MelloUI's numbers (Combat Damage Style, and the numbers around you in Pop, Slam and Stamp): thick, thin or none. None: the soft shade behind them instead." },
		-- (0.25.0; the user, 2026-10-20: "our custom damage font can not be scaled down, people complain its too big":
		-- this client has no World Text Scale, so nothing sized them)
		{ type = "slider", key = "dealtScale", name = "Combat Damage Size", min = 0.3, max = 1.5, step = 0.05, percent = true,
		  desc = "The size of your damage numbers over enemies in Pop, Slam and Stamp." },
		{ type = "button", name = "Preview", text = "Play",
		  hint = "a short burst in the chosen style",
		  desc = "Plays sample lines in the chosen style.",
		  onClick = function() M.Preview() end },
		{ type = "slider", key = "size", name = "Personal Combat Text Size", min = T.sizeMin, max = T.sizeMax, step = 1,
		  search = "combat text size",
		  desc = "The size of the text around your character. Crits are a third bigger." },
		{ type = "toggle", key = "titleNotices", name = "Notices In Title Font",
		  desc = "Procs and auras in the title font. Off: the text font." },
		{ type = "slider", key = "shadeSize", name = "Shade Size", min = 0, max = 1, step = 0.1, percent = true,
		  desc = "The size of the soft shadow behind combat text. 0: none." },
		{ type = "slider", key = "spread", name = "Lane Spread", min = T.spreadMin, max = T.spreadMax, step = 5,
		  desc = "How far left and right of your character the damage and healing lanes run." },
		{ type = "slider", key = "lines", name = "Most Lines", min = T.linesMin, max = T.linesMax, step = 1,
		  desc = "The most lines shown at once. The oldest goes first." },
		{ type = "toggle", key = "taken", name = "Damage Taken",
		  desc = "Damage you take." },
		{ type = "toggle", key = "heals", name = "Healing",
		  desc = "Healing and shields you get." },
		{ type = "toggle", key = "notices", name = "Procs & Auras",
		  desc = "Procs, auras gained or lost, interrupts and dispels." },
		{ type = "toggle", key = "avoid", name = "Dodge, Parry & Block",
		  desc = "Attacks that miss you: dodge, parry, block, absorb, resist and immune." },
		{ type = "toggle", key = "resource", name = "Resources Gained",
		  desc = "Mana, rage, energy and focus you gain." },
		{ type = "toggle", key = "combat", name = "Entering & Leaving Combat",
		  desc = "A short line when a fight starts and ends." },
		{ type = "toggle", key = "reputation", name = "Reputation & Honor",
		  desc = "Reputation and honor you gain." },
		{ type = "toggle", key = "enemyDamage", name = "Damage Over Enemies",
		  get = function() return Enemy.Get("enemyDamage") end, missing = function() return Enemy.Missing("enemyDamage") end,
		  desc = "Your damage numbers over enemies (the game's own)." },
		{ type = "toggle", key = "enemyPeriodic", name = "DoT Ticks Over Enemies",
		  get = function() return Enemy.Get("enemyPeriodic") end, missing = function() return Enemy.Missing("enemyPeriodic") end,
		  desc = "Your damage over time ticks over enemies (the game's own)." },
		{ type = "toggle", key = "enemyPet", name = "Pet Damage Over Enemies",
		  get = function() return Enemy.Get("enemyPet") end, missing = function() return Enemy.Missing("enemyPet") end,
		  desc = "Your pet's damage over enemies (the game's own)." },
		{ type = "toggle", key = "enemyHealing", name = "Healing Over Friends",
		  get = function() return Enemy.Get("enemyHealing") end, missing = function() return Enemy.Missing("enemyHealing") end,
		  desc = "Your healing numbers over friends (the game's own)." },
	},
})

local function DB()
	return M.db
end

local function Style()
	local db = M.db
	local s = db and db.style
	if s == "lanes" or s == "feed" or s == "classic" or s == "pop" or s == "slam" or s == "stamp" then
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
	d = DEALT.old[d] or d
	if d == "pop" or d == "slam" or d == "stamp" then
		return d
	end
	return "game"
end

-- Number Outline: a dark outline on Your Damage's numbers ("thick", true for thin) and no soft band behind them,
-- or false: the band
function DEALT.Outlined()
	local v = M.db and M.db.dealtOutline
	if v == "none" or v == false then
		return false
	end
	return v == "thin" and true or "thick"
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

-- the friendly players' nameplates shown (the game's switch, its own key); a secret or unknown answer counts as
-- shown
function DEALT.FriendPlates()
	if not (C_CVar and C_CVar.GetCVarBool) then
		return true
	end
	local ok, on = pcall(C_CVar.GetCVarBool, "nameplateShowFriendlyPlayers")
	if ok and on ~= nil and not Secret(on) then
		return on and true or false
	end
	return true
end

-- (retail, never shipped: the user's own play while WoW Forever is down, 2026-10-24: "in the open world the damage
-- numbers are shown from every source, even other players that are attacking the same target as me, that should
-- never be the case") the retail client (MelloUI.Retail): its open-world enemies are shared by everyone who
-- hits them and NPC companions fight at your side, so whose hit UNIT_COMBAT reports cannot be told even solo -- the
-- game's own numbers there (only they know whose hit it is), as in a group
function DEALT.Untellable()
	return MelloUI.Retail
end

-- MelloUI draws your damage now: a look chosen, the plates there, solo
-- (in a group the hits cannot be told apart), and the threat lists readable
-- in this fight (DEALT.threatHidden: a secret answer seen; the fight's end
-- tries again)
local function DealtDrawing()
	if not (DealtOn() and PlatesShown()) or DEALT.Untellable() then
		return false
	end
	if MelloUI.Threat.Grouped() or DEALT.threatHidden then
		return DEALT.ByLog()   -- (2.1.85: your own hits told by the combat log's lines)
	end
	return true
end

-- (2.1.85) The combat log's lines. The user's two runs of /mello combattext log (2026-11-24, a melee character, solo
-- and in a group; the Combat Log's filter on My actions) showed what comes with a hit of your own:
--   a special or a spell   its log line and the hit on the plate in ONE frame, the line first
--   a tick                 the same, the hit first, and no cast of yours in that frame
--   a weapon swing         PLAYER_SWING and its line in one frame, the hit on the plate 0.5 to 1.1 s later (alone);
--                          a swing dodged or parried has no line, its word comes as late
-- and nothing else: a hit with no line in its frame and no swing of yours before it is somebody else's. So each
-- frame's lines, swings and casts are counted (DEALT.Frame), a hit waits for its frame's end (DEALT.Queue ->
-- DEALT.Close) and is yours when a line of that frame is left for it, or a swing of yours is due. The lines are only
-- counted: their text and colour are never read. Solo every hit on an enemy you fight is drawn as before; the lines
-- only tell its ticks. Your pet's hits have no swing event: in a group they are not shown.
function DEALT.LinesOn()
	local CL = rawget(_G, "C_CombatLog")
	local fn = type(CL) == "table" and CL.AreFilteredEventsEnabled
	if type(fn) ~= "function" then
		return false
	end
	local ok, on = pcall(fn)
	return ok and not Secret(on) and on == true
end

function DEALT.ByLog()
	local db = M.db
	return not (db and db.dealtGroups == false) and DEALT.LinesOn()
end

-- The lines' switch is the game's: its Combat Log window turns them off as it hides. While Your Damage is on, a
-- change of that switch applies the state again (the game's own numbers back when the lines stop: a post-hook, the
-- apply a frame later), and in a group with Your Damage In Groups on MelloUI asks for the lines itself
function DEALT.KeepLines()
	if not DealtOn() then
		return
	end
	local CL = rawget(_G, "C_CombatLog")
	if type(CL) ~= "table" or type(CL.SetFilteredEventsEnabled) ~= "function" then
		return
	end
	if not DEALT.hooked then
		DEALT.hooked = true
		hooksecurefunc(CL, "SetFilteredEventsEnabled", function()
			if not DEALT.again then
				DEALT.again = true
				C_Timer.After(0, function()
					DEALT.again = false
					if M.isEnabled and DEALT.Apply then
						DEALT.Apply()   -- (the state applied again: set below, with Apply)
					end
				end)
			end
		end)
	end
	local db = M.db
	local grouped = (MelloUI.Threat.Grouped() or DEALT.threatHidden) and not (db and db.dealtGroups == false)
	-- (your heals are told by the lines everywhere, alone too: DEALT.HealsReady)
	if (grouped or DEALT.HealsReady()) and not DEALT.LinesOn() then
		pcall(CL.SetFilteredEventsEnabled, true)
	end
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
	if key == "enemyHealing" and DEALT.HealsDrawing() then
		return TEXT.healsOwns
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
-- Your heals (2.1.85; the user, 2026-11-24: "You forgot the Healing Numbers in the Damage Numbers, the healing that
-- appears above the friendly player when healing him"): the numbers of the healing you do, at the nameplate of the
-- friend you heal, in Combat Damage Style's look -- IN PLACE of the game's own (Healing Over Friends,
-- floatingCombatTextCombatHealing: off meanwhile, its value noted in db.savedDealt as the damage ones'), never added:
-- only while the game's were on. UNIT_COMBAT says a plate's unit was healed, never by whom, and no threat list helps
-- here: a heal is yours when the combat log's lines say so (DEALT.Queue's vouch, as your damage in a group), alone
-- too, so MelloUI asks for the lines (DEALT.KeepLines). MelloUI draws at a plate, so it stands back -- the game's own
-- numbers shown -- where it has none to stand on: the friendly players' nameplates off (nameplateShowFriendlyPlayers),
-- inside a dungeon or a raid (the game keeps the friendly plates to itself there), and anywhere else such a plate was
-- met (FORBIDDEN_NAME_PLATE_UNIT_ADDED, or a healed plate that cannot be had: DEALT.noFriend, until the next loading
-- screen). Never your own plate (the text around you has that heal), never an enemy healing itself. A friend whose
-- nameplate is not on the screen has no number.
--------------------------------------------------------------------------------

-- the game's healing numbers on, as the player left them (the value noted while MelloUI stands in for them)
function DEALT.GameHeals()
	local name = Enemy.Name("enemyHealing")
	if not name then
		return false
	end
	local db = M.db
	local saved = db and db.savedDealt
	local v = type(saved) == "table" and saved[name] or nil
	if v == nil then
		local ok, now = pcall(C_CVar.GetCVar, name)
		v = ok and Text(now) or nil
	end
	return v == "1"
end

-- a dungeon or a raid: the friendly plates are the game's alone there
function DEALT.Instanced()
	local ok, inside, kind = pcall(IsInInstance)
	return ok and not Secret(inside) and inside == true and not Secret(kind) and (kind == "party" or kind == "raid")
end

-- everything your heals need but the lines
function DEALT.HealsReady()
	local db = M.db
	if not DealtOn() or (db and db.dealtHeals == false) or DEALT.Untellable() then
		return false
	end
	if DEALT.noFriend or DEALT.Instanced() or not DEALT.FriendPlates() then
		return false
	end
	return DEALT.GameHeals()
end

-- MelloUI draws your heals now
function DEALT.HealsDrawing()
	return DEALT.HealsReady() and DEALT.LinesOn()
end

-- why MelloUI does not draw your heals now, in a few words (nil: it does): /mello combattext log's first line
function DEALT.HealsWhy()
	local db = M.db
	if not DealtOn() then
		return "Combat Damage Style is Game"
	elseif db and db.dealtHeals == false then
		return "Healing Numbers is off"
	elseif not Enemy.Name("enemyHealing") then
		return "this client has no switch for the game's healing numbers"
	elseif not DEALT.GameHeals() then
		return "the game's Healing Over Friends is off"
	elseif not DEALT.FriendPlates() then
		return "friendly nameplates are off"
	elseif DEALT.Instanced() then
		return "inside a dungeon or a raid"
	elseif DEALT.noFriend then
		return "a friendly nameplate here is the game's own"
	elseif not DEALT.LinesOn() then
		return "the combat log's lines are not coming"
	end
	return nil
end

-- a friendly plate MelloUI cannot stand on was met: the game's own healing numbers until the next loading screen
function DEALT.NoFriend()
	if not DEALT.noFriend then
		DEALT.noFriend = true
		if DEALT.Apply then
			DEALT.Apply()
		end
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
	local heal = Enemy.Name("enemyHealing")
	if heal and not FreeInCombat(heal) then
		return false
	end
	return true
end

-- one of the game's numbers: off (its value noted), or back as it was
function DEALT.Put(saved, name, off)
	if not name then
		return
	end
	if off then
		DealtOff(saved, name)
	elseif saved[name] ~= nil then
		SetCVar(name, saved[name])
		saved[name] = nil
	end
end

-- (2.1.85: `heals`, the game's healing numbers by themselves -- MelloUI may draw your damage and not your heals, or
-- the other way round) the game's numbers MelloUI stands in for now: the damage ones (`damage`), the healing one
local function DealtSwitch(damage, heals)
	if MelloUI.InCombat() and not DealtFree() then
		S.dealtPending = true   -- (applied again at the fight's end)
		Events()
		return
	end
	S.dealtPending = nil
	local db = DB()
	if not db then
		return
	end
	local saved = db.savedDealt or {}
	for _, key in ipairs(DEALT.keys) do
		DEALT.Put(saved, Enemy.Name(key), damage)
		local also = ENEMY[key].also
		if also then
			DEALT.Put(saved, NameOf(also) or nil, damage)
		end
	end
	DEALT.Put(saved, Enemy.Name("enemyHealing"), heals)
	db.savedDealt = next(saved) ~= nil and saved or nil
end

--------------------------------------------------------------------------------
-- The lines: a sign, the main text (a number, a word or a notice), a tail
-- (a name or a word after it), on one band. One builder for the floating
-- lines and the feed's (which have the kind's mark in front)
--------------------------------------------------------------------------------

local TEXT_LOOK = MelloUI.Shade.TEXT
local PAD_X, FEATHER = TEXT_LOOK.padX, TEXT_LOOK.feather

-- the notice's Outlined Text (Tweaks noticeOutline, off by default)
local function Outline()
	local Look = MelloUI.CentreLook
	return GameLook.Outline(Look and Look.Setting and Look.Setting("noticeOutline"))
end

-- the soft shadow, in the palette
local function Shadow(fs)
	GameLook.Shadow(fs, TEXT_LOOK.shadow)
end

-- the text font at a size (numbers: a Your Damage line's, the Game Numbers
-- Font's face); kept, so a line that keeps its size is not styled again
local function StyleText(fs, size, numbers)
	size = math.floor(size + 0.5)
	local outlined = numbers and DEALT.Outlined() or false
	local key = numbers and -(size + (outlined == "thick" and 0.5 or outlined and 0.25 or 0)) or size
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
			MelloUI:StyleFont(fs, numbers and "fontDamage" or "fontText", object, size, "", outlined or Outline(), numbers or "own")
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
	local fs = row:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontHighlight")
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
	-- (2.1.86: `heal` too -- it stayed set on the one entry table, so after your first heal every hit was kept as a
	-- heal: a weapon swing's number, told by its swing and not by a line, went missing in a group)
	e.who, e.glancing, e.tick, e.heal = nil, nil, nil, nil
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
	-- (2.1.85: an outlined number of Your Damage stands without the band)
	local share = (row.dealt and DEALT.Outlined()) and 0 or ShadeShare()
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
		band:SetShown(false)
		return
	end
	band:SetShown(true)
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
		if e.glyph then
			local g = math.floor(TextSize() * T.glyph + 0.5)
			glyph:SetSize(g, g)
			W.Icon(glyph, e.glyph, g)
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

-- (2.1.53: the middle of the game's screen, where the character stands -- MelloUI:PlayPoint's rule:
-- Offhand's main screen, never the gap between two screens)
local function FloatHome(frame)
	MelloUI:PlayPoint(frame, "CENTER", "CENTER", 0, -20)
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
		default = FloatHome, min = 0.5, max = 2, base = 1, label = "Combat Text", page = OWNER, when = FloatOn(style),
		category = "combat" })
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
	if line.dealt then
		DEALT.LightsOff(line)   -- (a light never outlives its line)
		if line.main and line.main.SetTextScale then
			line.main:SetTextScale(1)
		end
		if line.signed and line.sign.SetTextScale then
			line.sign:SetTextScale(1)   -- (a heal's "+", sized with its number)
		end
	end
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
-- Enemies writes it, where the client has it) and Your Damage Size (0.25.0:
-- this client has no World Text Scale, the numbers had no size of their own);
-- handed to Fill as a factor of the text around you's size, so Text Around You
-- never moves it (the configurator audit: one size per thing on screen)
local function DealtScale(look)
	-- (2.1.85; the user: "both of these sliders do the same thing") the game's World Text Scale no longer sizes
	-- MelloUI's numbers too: it is the size of the game's own (Game Damage Numbers Size), Combat Damage Size ours
	local world = 1
	local own = Num(M.db and M.db.dealtScale) or 0.7
	own = math.max(0.3, math.min(1.5, own))
	return (DEALT.size[look] or 1) * world * own * T.size / TextSize()
end

-- (2.1.85; the user, 2026-11-24: "i want to redo the custom damage text, with much more high quality and better impact
-- and critical effects ... snappier and impactfull", their pick of the sketch's three takes: "all 3") Your Damage's
-- three looks, each ONE drive per line (Anim:Drive -> DEALT.Step: the line's place set from offsets, never read --
-- a plate's anchoring is secret --, the number's size by the engine's text scale, its own colour run to white for its
-- flash, the look's own lights added on). Everything is counted in ems: F, a plain hit's text size, so the looks keep
-- their proportions at every Your Damage Size.
--   pop    a hit lands in one of six slots left and right above the plate with a hard pop, hangs, lifts off (0.8 s);
--          a crit drops in from large above them: flash, ring, rays, a short shake (1.25 s)
--   slam   a hit thrown from above the name on an arc, a streak behind it, falling as it fades (0.8 s); a crit: a
--          gold slash through the plate, streaks thrown from it, the number rising high and hanging (1.3 s)
--   stamp  a column at the plate's right end: each hit stamps in at the foot and shoves the older ones up a row
--          (five rows); a crit over a bar of light, a ring on the plate's end, the column jolts (1.7 s)
-- A word (Dodge, Parry ...) small and quiet in each. Reduce Motion: the number at its place, a fade, nothing else.
-- The lights are made with a line's first need of them and kept with the line; shown only while their part plays.
DEALT.look = {
	pop = { life = 0.8, crit = 1.25, word = 0.68, tick = 0.62 },
	slam = { life = 0.78, crit = 1.32, word = 0.7, tick = 0.58 },
	stamp = { life = 1.15, crit = 1.7, word = 1.15, tick = 0.9, rows = 5, push = 0.09 },
}
DEALT.LIGHTS = { glow = "glow_white.tga", halo = "halo_white.tga", rays = "rays_gold.tga", streakW = "streak_white.tga",
	streakG = "streak_gold.tga", healGlow = "glow_white.tga", healHalo = "halo_white.tga" }
DEALT.DEBRIS = 12
-- (2.1.86; the user in their game, 2026-11-25: "Healing numbers on top of friendly players look like they are taking
-- damage instead of receaving healing") a heal has a way of its own in every look, never a blow's: a "+" before the
-- number, it swells in softly and floats up, a soft light of its own colour behind it -- no white flash, no streak, no
-- gold, no shake; a crit heal bigger, a ring of its colour opening round it (DEALT.Mend, DEALT.MendLight). Its lights
-- are their own textures (TINT), in the line's colour: the white art, tinted.
DEALT.TINT = { healGlow = true, healHalo = true }
DEALT.mend = { life = 1.15, crit = 1.5 }

function DEALT.Seg(t, a, b)
	local v = (t - a) / (b - a)
	return v < 0 and 0 or v > 1 and 1 or v
end

function DEALT.Out(v)   -- (outCubic)
	v = v < 0 and 0 or v > 1 and 1 or v
	local u = 1 - v
	return 1 - u * u * u
end

-- a pop: from `from` up to `peak` by `up` seconds, down to 1 by `down`
function DEALT.Pop(t, from, peak, up, down)
	if t < up then
		return from + (peak - from) * DEALT.Out(t / up)
	end
	return peak + (1 - peak) * DEALT.Out(DEALT.Seg(t, up, down))
end

function DEALT.Shake(t, from, len, amp, r)
	if t < from or t > from + len then
		return 0
	end
	return math.sin((t - from) * 110 + r * 6.283) * amp * (1 - (t - from) / len)
end

-- a light of the line, made at its first need (the look's own art: FrameFX.Light)
function DEALT.Light(line, key)
	local fx = line.fx
	if not fx then
		fx = {}
		line.fx = fx
	end
	local t = fx[key]
	if not t then
		t = line:CreateTexture(nil, "ARTWORK", nil, 6)
		local file = DEALT.LIGHTS[key] or DEALT.LIGHTS.streakG
		local Lights = MelloUI.FrameFX
		if type(Lights) == "table" and Lights.Light then
			Lights.Light(t, file)
		else
			t:SetTexture("Interface\\AddOns\\MelloUI\\Media\\FrameFX\\" .. file)
		end
		t:SetBlendMode("ADD")
		if DEALT.TINT[key] and line.cr then
			t:SetVertexColor(line.cr, line.cg, line.cb)
		end
		fx[key] = t
	end
	return t
end

-- a light shown at (x, y) from `rel`'s point, w by h, at an alpha, turned; alpha 0: away
function DEALT.Lit(line, key, rel, point, x, y, w, h, a, rot)
	if a <= 0.004 then
		local fx = line.fx
		local t = fx and fx[key]
		if t then
			t:Hide()
		end
		return
	end
	local t = DEALT.Light(line, key)
	t:ClearAllPoints()
	if not pcall(t.SetPoint, t, "CENTER", rel, point, x, y) then
		t:Hide()
		return
	end
	t:SetSize(w, h)
	t:SetAlpha(a > 1 and 1 or a)
	if t.SetRotation then
		t:SetRotation(rot or 0)
	end
	t:Show()
end

function DEALT.LightsOff(line)
	local fx = line.fx
	if fx then
		for _, t in pairs(fx) do
			t:Hide()
		end
	end
end

-- the number's size, and its flash: its own colour run towards white (plain numbers: the palette's and the meanings')
function DEALT.Scale(line, k, flash)
	local value = line.main
	if value.SetTextScale then
		value:SetTextScale(k)
	end
	-- (a heal's "+": with its number)
	local sign = line.signed and line.sign or nil
	if sign and sign.SetTextScale then
		sign:SetTextScale(k)
	end
	local r = line.cr
	if r then
		flash = flash < 0 and 0 or flash > 1 and 1 or flash
		if flash ~= line.flashed then
			line.flashed = flash
			value:SetTextColor(r + (1 - r) * flash, line.cg + (1 - line.cg) * flash, line.cb + (1 - line.cb) * flash)
			if sign then
				sign:SetTextColor(r + (1 - r) * flash, line.cg + (1 - line.cg) * flash, line.cb + (1 - line.cb) * flash)
			end
		end
	end
end

-- a heal's lights at `t` of its life: a soft light of its colour behind the number, a crit's ring opening round it
function DEALT.MendLight(line, t, crit)
	local D = DEALT
	local F = line.F
	local e = D.Seg(t, 0.05, crit and 0.6 or 0.45)
	D.Lit(line, "healGlow", line.main, "CENTER", 0, 0, (crit and 6.2 or 3.8) * F, (crit and 3.6 or 2.3) * F,
		(crit and 0.8 or 0.55) * D.Seg(t, 0, 0.08) * (1 - e), 0)
	if crit then
		local open = 0.45 + 1.15 * D.Out(e)
		D.Lit(line, "healHalo", line.main, "CENTER", 0, 0, 4.4 * F * open, 3.6 * F * open, 0.85 * (1 - e), 0)
	end
end

-- a heal in Pop and Slam: its place (from the plate's middle), size and alpha at `t` -- over the plate, to one side
-- by its slot (a crit in the middle, higher), floating up all its life
function DEALT.Mend(line, t)
	local D = DEALT
	local F, life, crit = line.F, line.life, line.kindC == "crit"
	local s = t / life
	local rise = 0.5 * (s + D.Out(s))
	local x, y, k
	if crit then
		x = (line.r1 - 0.5) * 0.8 * F
		y = (2.4 + 1.5 * rise) * F
		k = D.Pop(t, 0.6, 1.22, 0.18, 0.46)
	else
		-- (as far to a side as a blow's slot: two heals on one friend stand clear of each other)
		x = line.side * (1.5 + line.row * 0.45 + line.r1 * 0.4) * F
		y = (1.3 + line.row * 0.35 + 1.9 * rise) * F
		k = D.Pop(t, 0.75, 1.1, 0.14, 0.36)
	end
	D.MendLight(line, t, crit)
	return x, y, k, D.Seg(t, 0, 0.1) * (1 - D.Seg(t, life - 0.35, life))
end

-- the line at (x, y) from the plate's point; false when the plate takes no anchor any more
function DEALT.Place(line, x, y)
	line:ClearAllPoints()
	return pcall(line.SetPoint, line, line.pt, line.plate, line.rel, x, y)
end

-- one step of a line's life (`share` 0..1 of it)
function DEALT.Step(line, share)
	if share >= 1 then
		return
	end
	local D = DEALT
	local Seg, Out = D.Seg, D.Out
	local t, F, life = share * line.life, line.F, line.life
	local look, crit, word = line.look, line.kindC == "crit", line.kindC == "word"
	local tick = line.kindC == "tick"
	local heal = line.heal
	local x, y, a
	local k, flash = 1, 0
	if tick and look ~= "stamp" then
		-- a tick: small and quiet in its own lane at the plate's end (Pop: the right one, Slam: the left), rising
		x = (look == "pop" and 1 or -1) * (0.3 + 0.5 * line.r1) * F
		y = (0.8 * Out(t / life) - 0.1) * F
		a = Seg(t, 0, 0.05) * (1 - Seg(t, life - 0.22, life)) * 0.9
	elseif heal and look ~= "stamp" then
		-- (2.1.86) a heal: never a blow's way
		x, y, k, a = D.Mend(line, t)
	elseif look == "pop" then
		if crit then
			local lift = Out(Seg(t, 0.9, 1.25)) * 0.75 * F
			x = (line.r1 - 0.5) * 1.5 * F + D.Shake(t, 0.11, 0.15, 0.11 * F, line.r2)
			y = (4 + 0.2 * line.r3) * F + lift + D.Shake(t, 0.11, 0.15, 0.08 * F, line.r3)
			k = t < 0.11 and (2.5 - 1.5 * Out(t / 0.11)) or (1 + 0.06 * (1 - Seg(t, 0.11, 0.26)))
			a = Seg(t, 0, 0.055) * (1 - Seg(t, 0.98, 1.25))
			flash = t >= 0.11 and (1 - Seg(t, 0.11, 0.26)) or 0
			local e = Seg(t, 0.11, 0.38)
			local on = t >= 0.11 and 1 or 0
			D.Lit(line, "rays", line.main, "CENTER", 0, 0, 7.75 * F * (0.75 + 0.5 * Out(e)), 7.75 * F * (0.75 + 0.5 * Out(e)),
				on * 0.95 * (1 - e), 0.35 + line.r2)
			D.Lit(line, "halo", line.main, "CENTER", 0, 0, 4.75 * F * (0.5 + 1.2 * Out(e)), 3.75 * F * (0.5 + 1.2 * Out(e)),
				on * 0.9 * (1 - e), 0)
			D.Lit(line, "glow", line.main, "CENTER", 0, 0, 6.5 * F, 3.75 * F, on * 0.9 * (1 - Seg(t, 0.11, 0.25)), 0)
		elseif word then
			x = -(0.3 + 0.75 * Out(Seg(t, 0, life))) * F
			y = (0.4 + 0.3 * line.r1) * F
			k = D.Pop(t, 0.7, 1.12, 0.06, 0.13)
			a = Seg(t, 0, 0.05) * (1 - Seg(t, life - 0.25, life))
		else
			local up = Seg(t, 0.45, 0.8)
			x = line.side * (1.63 + line.row * 0.43 + line.r1 * 1.13) * F
			y = (1.33 + line.row * 0.85 + line.r2 * 0.13 + up * up * 0.8) * F
			k = D.Pop(t, 0.35, 1.32, 0.06, 0.135)
			a = Seg(t, 0, 0.04) * (1 - Seg(t, 0.56, 0.8))
			flash = 0.9 * (1 - Seg(t, 0, 0.12))
			D.Lit(line, "glow", line.main, "CENTER", 0, 0, 3.75 * F, 2.4 * F, 0.5 * (1 - Seg(t, 0, 0.15)), 0)
		end
	elseif look == "slam" then
		local oy = 1.2 * F
		if crit then
			local vx, vy, g = line.side * (0.9 + 1.1 * line.r1) * F, 8.75 * F, 15.6 * F
			x = vx * t + D.Shake(t, 0.12, 0.14, 0.125 * F, line.r2)
			y = oy + 0.75 * F + vy * t - 0.5 * g * t * t + D.Shake(t, 0.12, 0.14, 0.09 * F, line.r3)
			k = t < 0.12 and (0.7 + 0.52 * Out(t / 0.12)) or (1.22 - 0.22 * Out(Seg(t, 0.12, 0.24)))
			a = Seg(t, 0, 0.04) * (1 - Seg(t, 0.98, 1.32))
			flash = 1 - Seg(t, 0.06, 0.24)
			-- the slash and the glow stay on the plate, the streaks fly from it: anchored to the plate, not the number
			local plate = line.plate
			D.Lit(line, "streakG", plate, "CENTER", line.side * 0.4 * F, oy + 1.1 * F, 11.25 * F * Out(Seg(t, 0, 0.11)), 1.9 * F,
				1 - Seg(t, 0, 0.3), 0.42 * line.side)
			D.Lit(line, "glow", plate, "CENTER", 0, oy + F, 5.25 * F, 3.25 * F, 0.8 * (1 - Seg(t, 0, 0.22)), 0)
			local st = Seg(t, 0.02, 0.52)
			local ts = t - 0.02
			for i = 1, D.DEBRIS do
				local ang = (i / D.DEBRIS) * 6.283 + line.r2 * 2
				local sp = (5.25 + ((i * 53) % 100) * 0.0525) * F
				local live = (st > 0 and st < 1) and (1 - st) or 0
				local sx, sy = math.cos(ang) * sp, math.sin(ang) * sp * 0.8 - 22.5 * F * ts
				D.Lit(line, i, plate, "CENTER", math.cos(ang) * sp * ts, oy + F + math.sin(ang) * sp * ts * 0.8 - 11.25 * F * ts * ts,
					1.5 * F * (1 - st * 0.5), 0.33 * F, live, live > 0 and math.atan2(sy, sx) or 0)
			end
		elseif word then
			local vx, vy, g = line.side * 1.9 * F, 4.1 * F, 11.25 * F
			x, y = vx * t, oy - 0.4 * F + vy * t - 0.5 * g * t * t
			a = Seg(t, 0, 0.04) * (1 - Seg(t, life - 0.25, life))
		else
			local vx, vy, g = line.side * (3.75 + 4.1 * line.r1) * F, (10.25 + 2.1 * line.r2) * F, 25 * F
			x, y = vx * t, oy + vy * t - 0.5 * g * t * t
			k = D.Pop(t, 0.5, 1.2, 0.08, 0.17)
			a = Seg(t, 0, 0.03) * (1 - Seg(t, 0.5, 0.78))
			flash = 0.8 * (1 - Seg(t, 0, 0.11))
			local rot = math.atan2(vy - g * t, vx)
			D.Lit(line, "streakW", line.main, "CENTER", -math.cos(rot) * 1.1 * F, -math.sin(rot) * 1.1 * F, 3.75 * F, 0.9 * F,
				0.8 * (1 - Seg(t, 0, 0.17)), rot)
		end
	else
		-- stamp: the rows newer than this one have shoved it up (each over DEALT.look.stamp.push), a crit jolts the column
		local now = GetTime()
		local lane, push = line.lane, D.look.stamp.push
		local above, rows, jolt = 0, 0, 0
		local lines = lane and lane.lines
		if lines then
			local seen = false
			for i = 1, #lines do
				local o = lines[i]
				-- (the ticks a column of their own at the plate's other end)
				if seen and (o.kindC == "tick") == tick then
					above = above + o.rowH * Out((now - o.t0) / push)
					rows = rows + 1
				elseif o == line then
					seen = true
				end
				if o.kindC == "crit" and not tick and not o.heal then   -- (a crit heal jolts nothing)
					jolt = jolt + D.Shake(now - o.t0, 0, 0.15, 0.11 * F, o.r2)
				end
			end
		end
		-- (a row's middle in its own slot: a crit's taller row stands clear of the rows next to it)
		x, y = 0.55 * F + jolt, above + (line.rowH - F) * 0.5
		local dim = rows >= D.look.stamp.rows and 0 or rows == 4 and 0.45 or rows == 3 and 0.75 or 1
		a = Seg(t, 0, 0.035) * (1 - Seg(t, life - 0.22, life)) * dim
		if tick then
			x, y = -0.55 * F, above
			a = Seg(t, 0, 0.04) * (1 - Seg(t, life - 0.25, life)) * (rows >= 3 and 0 or rows == 2 and 0.5 or 0.9)
			k = heal and 1 or D.Pop(t, 1.35, 1, 0.001, 0.09)
		elseif heal then
			-- (2.1.86) a heal in the column: it swells in where a hit stamps, its own light, no streak
			a = Seg(t, 0, 0.1) * (1 - Seg(t, life - 0.3, life)) * dim
			k = crit and D.Pop(t, 0.7, 1.2, 0.16, 0.42) or D.Pop(t, 0.8, 1.08, 0.12, 0.32)
			D.MendLight(line, t, crit)
		elseif crit then
			k = t < 0.09 and (2.3 - 1.3 * Out(t / 0.09)) or (1 + 0.05 * (1 - Seg(t, 0.09, 0.22)))
			flash = 1 - Seg(t, 0.09, 0.25)
			local e = Seg(t, 0.06, 0.34)
			D.Lit(line, "streakG", line.main, "CENTER", 0, 0, 9.5 * F * (0.7 + 0.3 * Out(e)), 2.9 * F, 0.95 * (1 - e), 0)
			D.Lit(line, "halo", line.plate, "RIGHT", 0, 0, 3.75 * F * (0.4 + 1.3 * Out(e)), 3.75 * F * (0.4 + 1.3 * Out(e)),
				0.9 * (1 - e), 0)
			D.Lit(line, "rays", line.main, "CENTER", 0, 0, 5.4 * F * (0.8 + 0.4 * Out(e)), 5.4 * F * (0.8 + 0.4 * Out(e)),
				0.7 * (1 - e), line.r1)
		else
			k = D.Pop(t, 1.7, 1, 0.001, 0.09)
			if not word then
				flash = 0.85 * (1 - Seg(t, 0, 0.11))
				D.Lit(line, "streakW", line.main, "BOTTOM", 0, 0, 3 * F, 0.75 * F, 0.85 * (1 - Seg(t, 0.02, 0.19)), 0)
			end
		end
	end
	if not D.Place(line, x, y) then
		a = 0
	end
	line:SetAlpha(a)
	D.Scale(line, k, flash)
end

-- this frame's counts (a new frame closes the one before it first)
function DEALT.Frame()
	local L, now = DEALT.log, GetTime()
	if L.at ~= now then
		DEALT.Close()
		L.at, L.lines, L.swings, L.casts = now, 0, 0, 0
	end
	return L
end

-- a hit on a plate, kept for its frame's end; `vouch`: drawn only when the log names it yours (a group, and every
-- heal: e.heal)
function DEALT.Queue(unit, e, vouch)
	local L = DEALT.Frame()
	local n = L.n + 1
	L.n = n
	local h = L.hits[n]
	if not h then
		h = {}
		L.hits[n] = h
	end
	h.unit, h.kind, h.value, h.crit, h.glancing, h.colour, h.label = unit, e.kind, e.value, e.crit, e.glancing, e.colour, e.label
	h.word = e.kind == "avoid"
	h.vouch, h.heal = vouch and true or false, e.heal and true or false
	h.free = L.lines - L.swings   -- (the lines seen before it that no swing of this frame takes)
	if not L.timer then
		L.timer = true
		C_Timer.After(0, DEALT.Close)
	end
end

-- its life over, however the drive ended: at rest, put away (OnHide: LineHidden)
function DEALT.StepDone(line)
	DEALT.LightsOff(line)
	DEALT.Scale(line, 1, 0)
	if line.main and line.main.SetTextScale then
		line.main:SetTextScale(1)
	end
	line:Hide()
end

local DealtLine

-- the frame closed: its swings take their lines (one that landed has one), then each waiting hit is told
function DEALT.Close()
	local L = DEALT.log
	L.timer = false
	local pend = L.pending
	local free = L.lines
	for i = 1, #pend do
		local sw = pend[i]
		if sw.line == nil then
			sw.line = free > 0
			if free > 0 then
				free = free - 1
			end
		end
	end
	local n = L.n
	L.n = 0
	for i = 1, n do
		local h = L.hits[i]
		local mine, tick = not h.vouch, false
		if not h.word and free > 0 then
			-- a line of this frame is its own: a special, a spell, a heal or a tick
			free = free - 1
			mine = true
			tick = h.free <= 0 and L.casts == 0
		elseif not h.heal then
			-- a swing of yours whose number is due now: one that landed for a hit, one that did not for a word
			for j = 1, #pend do
				local sw = pend[j]
				local age = L.at - sw.at
				if age >= L.lagMin and age <= L.lagMax and (sw.line == true) == (not h.word) then
					L.spare[#L.spare + 1] = tremove(pend, j)
					mine = true
					break
				end
			end
		end
		if mine then
			local e = Clear(E)
			e.kind, e.value, e.crit, e.glancing, e.colour, e.label = h.kind, h.value, h.crit, h.glancing, h.colour, h.label
			e.tick = tick or nil
			e.heal = h.heal or nil
			DealtLine(h.unit, e)
		end
		h.value, h.colour, h.label = nil, nil, nil   -- (nothing of the game's kept past its frame)
	end
	for j = #pend, 1, -1 do
		if L.at - pend[j].at > L.lagMax then
			L.spare[#L.spare + 1] = tremove(pend, j)
		end
	end
	L.lines, L.swings, L.casts = 0, 0, 0
end

DealtLine = function(unit, e)
	local plate = PlateOf(unit)
	if not plate then
		return nil
	end
	local D = DEALT
	local look = Dealt()
	local spec = D.look[look]
	if not spec then
		return nil
	end
	local lane = D.lanes[unit]
	if not lane then
		lane = { lines = {}, hits = 0, crits = 0 }
		D.lanes[unit] = lane
	end
	while #lane.lines >= D.most do
		local oldest = lane.lines[1]
		LineHidden(oldest)
		oldest:Hide()
	end
	local size = DealtScale(look)
	local word = e.kind == "avoid"
	local tick = e.tick and not e.crit and not word
	local holder = DealtHolder()
	local line = TakeLine(holder, D.pool)
	line.dealt = true   -- (the Game Numbers Font and Outlined Numbers: Fill)
	line.lane = lane
	lane.lines[#lane.lines + 1] = line
	D.LightsOff(line)
	local align = look == "stamp" and "LEFT" or ((look == "pop" and word) and "RIGHT" or "CENTER")
	if tick then
		align = look == "pop" and "LEFT" or "RIGHT"
	end
	-- (2.1.86) a heal: a "+" before its number, as the text around you writes a heal
	local heal = e.heal and not word
	if heal then
		e.sign = "+"
	end
	Fill(line, e, align, size * (e.glancing and D.glancing or 1) * (e.crit and D.crit or 1) * (word and D.word or 1)
		* (tick and D.tick or 1))
	local main = word and line.word or line.value
	line.main = main
	line.heal, line.signed = heal or nil, e.sign ~= nil
	-- its colour, for the flash (a word has none)
	local c = (not word) and e.colour or nil
	line.cr, line.cg, line.cb, line.flashed = c and c[1], c and c[2], c and c[3], 0
	-- (a heal's lights made for an earlier heal of this line: in today's colour)
	if heal and line.fx and c then
		for key in pairs(D.TINT) do
			local t = line.fx[key]
			if t then
				t:SetVertexColor(c[1], c[2], c[3])
			end
		end
	end
	local F = TextSize() * size
	line.F, line.look, line.plate = F, look, plate
	line.kindC = e.crit and "crit" or (word and "word" or (tick and "tick" or "hit"))
	line.r1, line.r2, line.r3 = math.random(), math.random(), math.random()
	line.t0 = GetTime()
	line.life = e.crit and spec.crit or (word and spec.word or (tick and spec.tick or spec.life))
	if heal and not tick and look ~= "stamp" then
		line.life = e.crit and D.mend.crit or D.mend.life   -- (a heal floats: a little longer than a blow)
	end
	if e.crit then
		lane.crits = lane.crits + 1
		line.side = lane.crits % 2 == 0 and 1 or -1
		line.row = 0
	elseif tick then
		line.side, line.row = 1, 0   -- (a tick takes no slot of the hits')
	else
		lane.hits = lane.hits + 1
		line.side = lane.hits % 2 == 0 and 1 or -1
		line.row = math.floor((lane.hits - 1) / 2) % 3
	end
	line.rowH = F * (e.crit and 1.475 or (word and 0.775 or (tick and D.tick or 1)))
	if tick then
		if look == "pop" then
			line.pt, line.rel = "LEFT", "RIGHT"
		else
			line.pt, line.rel = "RIGHT", "LEFT"
		end
	elseif look == "stamp" then
		line.pt, line.rel = "LEFT", "RIGHT"
	elseif look == "pop" and word then
		line.pt, line.rel = "RIGHT", "LEFT"
	else
		line.pt, line.rel = "CENTER", "CENTER"
	end
	holder:Show()
	local Anim = MelloUI.Anim
	if Anim.reduceMotion then
		-- no pop, no travel, no lights: at its place, a fade
		local x, y = 0, 1.6 * F
		if tick then
			x, y = (look == "pop" and 0.5 or -0.5) * F, 0
		elseif look == "stamp" then
			x, y = 0.55 * F, (#lane.lines - 1) * F
		elseif look == "pop" and word then
			x, y = -0.5 * F, 0.4 * F
		elseif e.crit then
			y = 3.2 * F
		else
			x = line.side * (1.6 + line.row * 0.5) * F
		end
		if not D.Place(line, x, y) then
			LineHidden(line)
			line:Hide()
			return nil
		end
		line:SetAlpha(1)
		Anim:Mirror(line, 0.05, line.life - 0.3, 0.25)
		return line
	end
	if not D.Place(line, 0, F) then
		LineHidden(line)
		line:Hide()
		return nil
	end
	line:SetAlpha(0)
	line:Show()
	Anim:Drive(line, D.Step, line.life, "linear", D.StepDone)
	return line
end

--------------------------------------------------------------------------------
-- The text around you in the three looks (2.1.85; the user, 2026-11-24: "we need to redo the Personal Combat text
-- that appears on my character, 3 varriants same style and impact", then "to be able to move and resize the windows of
-- all of those elements separatelly in the Edit Layout, but that specific feature should have its special session in
-- the Edit Layout where only it is shown, nothing else ... and a setting called Edit Position", "build all 3").
-- Four areas, each a holder of its own with its own mover -- moved and sized in Combat Text's own Edit Layout session
-- only (the movers' `session`, MelloUI:StartEditLayout's scope "combattext": the Edit Position button), never in the
-- common one: Damage Taken, Healing, Procs, Resources. A line plays in its kind's area in the chosen look -- Pop, Slam
-- or Stamp: Combat Damage Style's engine and lights (DEALT.Seg / Pop / Shake / Lit / Scale), counted in ems of the
-- text's size. Damage taken grows to the left of its area's right edge and sinks (the area stands left of the
-- character by default), healing to the right of its area's left edge and rises, procs and resources are centred.
-- Numbers wear the crisp look (the numbers' face, Number Outline, no band); a proc keeps its title font and band.
--------------------------------------------------------------------------------
local PERS = {
	looks = { pop = true, slam = true, stamp = true },
	order = { "taken", "heal", "notice", "resource" },
	areas = {
		-- (the labels alone: the session is Combat Text's own, its name on the dock)
		taken = { label = "Damage Taken", x = -200, y = 10, pt = "RIGHT", align = "RIGHT" },
		heal = { label = "Healing", x = 200, y = 10, pt = "LEFT", align = "LEFT" },
		notice = { label = "Procs", x = 0, y = 180, pt = "CENTER", align = "CENTER", w = 240 },   -- (a proc's name is long)
		resource = { label = "Resources", x = 0, y = -160, pt = "CENTER", align = "CENTER" },
	},
	of = { taken = "taken", heal = "heal", notice = "notice", avoid = "notice", combat = "notice", rep = "notice",
		resource = "resource" },
	life = {
		pop = { hit = 0.9, crit = 1.3, heal = 1.0, notice = 1.5, word = 0.75, res = 0.8 },
		slam = { hit = 0.82, crit = 1.35, heal = 1.05, notice = 1.5, word = 0.76, res = 0.8 },
		stamp = { hit = 1.2, crit = 1.7, heal = 1.2, notice = 1.6, word = 1.2, res = 0.9 },
	},
	W = 150, H = 110,   -- an area's box: its plate in Edit Layout
	sampleY = 0.3,      -- a sample's place in the box, of its height from the middle: clear of the plate's name
	most = 8,
	SESSION = "combattext", TITLE = "Combat Text",
}

function PERS.On()
	return M.isEnabled and PERS.looks[Style()] == true
end

-- an area, made at its first line (or for Edit Position): its holder and its mover
function PERS.Area(name)
	local A = PERS.areas[name]
	if not A then
		return nil
	end
	if A.holder then
		return A
	end
	local h = CreateFrame("Frame", "MelloUICombatArea_" .. name, UIParent)
	h:SetSize(A.w or PERS.W, PERS.H)
	h:SetFrameStrata("LOW")
	h:SetClampedToScreen(true)
	h:EnableMouse(false)
	A.holder, A.lines, A.n = h, {}, 0
	-- (the middle of the game's screen, where the character stands: MelloUI:PlayPoint's rule)
	A.home = function(frame)
		MelloUI:PlayPoint(frame, "CENTER", "CENTER", A.x, A.y)
	end
	A.home(h)
	A.entry = MelloUI:RegisterMover(h, h, { key = "combat_" .. name, default = A.home, min = 0.5, max = 2.5, base = 1,
		label = A.label, page = OWNER, when = PERS.On, category = "combat", session = PERS.SESSION })
	if not MelloUI:RestorePosition(A.entry.key, h) then
		A.home(h)
	end
	return A
end

function PERS.Place(line, x, y)
	line:ClearAllPoints()
	line:SetPoint(line.pt, line.area.holder, line.pt, x, y)
end

-- one step of a line's life in its area
function PERS.Step(line, share)
	if share >= 1 then
		return
	end
	local D = DEALT
	local Seg, Out = D.Seg, D.Out
	local t, F, life, look, kc = share * line.life, line.F, line.life, line.look, line.kindC
	local name = line.aname
	local dir = name == "taken" and -1 or 1                               -- (damage taken sinks, the rest rises)
	local side = name == "taken" and -1 or (name == "heal" and 1 or 0)    -- (away from the character)
	local x = 0
	local y, a
	local k, flash = 1, 0
	local out = 1 - Seg(t, life - 0.27, life)
	if look == "stamp" then
		-- a column: each newer line of the area has shoved this one a row (resources: down, under the feet)
		local now, above, rows, jolt = GetTime(), 0, 0, 0
		local lines = line.area.lines
		local seen = false
		for i = 1, #lines do
			local o = lines[i]
			if seen then
				above = above + o.rowH * Out((now - o.t0) / 0.09)
				rows = rows + 1
			elseif o == line then
				seen = true
			end
			if o.kindC == "crit" then
				jolt = jolt + D.Shake(now - o.t0, 0, 0.15, 0.15 * F, o.r2)
			end
		end
		local max = (name == "notice" or name == "resource") and 2 or 5
		x, y = jolt, (name == "resource" and -above or above)
		a = Seg(t, 0, 0.035) * out * (rows >= max and 0 or rows == max - 1 and 0.5 or 1)
		if kc == "crit" then
			k = t < 0.09 and (2.3 - 1.3 * Out(t / 0.09)) or (1 + 0.05 * (1 - Seg(t, 0.09, 0.22)))
			flash = 1 - Seg(t, 0.09, 0.25)
			local e = Seg(t, 0.06, 0.34)
			D.Lit(line, "streakG", line.main, "CENTER", 0, 0, 9 * F * (0.7 + 0.3 * Out(e)), 2.8 * F, 0.95 * (1 - e), 0)
			D.Lit(line, "halo", line.main, "CENTER", 0, 0, 4.2 * F * (0.4 + 1.2 * Out(e)), 3 * F * (0.4 + 1.2 * Out(e)), 0.85 * (1 - e), 0)
			D.Lit(line, "rays", line.main, "CENTER", 0, 0, 5.2 * F * (0.8 + 0.4 * Out(e)), 5.2 * F * (0.8 + 0.4 * Out(e)), 0.7 * (1 - e), line.r1)
		elseif kc == "notice" then
			k = t < 0.09 and (1.9 - 0.9 * Out(t / 0.09)) or (1 + 0.05 * (1 - Seg(t, 0.09, 0.22)))
			D.Lit(line, "streakG", line.main, "CENTER", 0, 0, 11 * F * (0.7 + 0.3 * Out(Seg(t, 0.04, 0.32))), 2.5 * F,
				0.9 * (1 - Seg(t, 0.04, 0.34)), 0)
		else
			k = D.Pop(t, 1.6, 1, 0.001, 0.09)
			if kc == "hit" or kc == "heal" then
				flash = 0.8 * (1 - Seg(t, 0, 0.11))
				D.Lit(line, "streakW", line.main, "BOTTOM", 0, 0, 3 * F, 0.75 * F, 0.8 * (1 - Seg(t, 0.02, 0.19)), 0)
			end
		end
	elseif look == "slam" then
		if kc == "crit" then
			local vx, vy, g = side * (2.9 + 1.8 * line.r1) * F, 13.7 * F, 25 * F
			x = vx * t + D.Shake(t, 0.12, 0.14, 0.2 * F, line.r2)
			y = vy * t - 0.5 * g * t * t + D.Shake(t, 0.12, 0.14, 0.15 * F, line.r3)
			k = t < 0.12 and (0.7 + 0.52 * Out(t / 0.12)) or (1.22 - 0.22 * Out(Seg(t, 0.12, 0.24)))
			a = Seg(t, 0, 0.04) * (1 - Seg(t, life - 0.35, life))
			flash = 1 - Seg(t, 0.06, 0.24)
			-- the slash, the glow and the streaks stay at the area (away from the character), the number flies
			local holder = line.area.holder
			D.Lit(line, "streakG", holder, line.pt, side * 6 * F, 0, 11.5 * F * Out(Seg(t, 0, 0.11)), 2.5 * F, 1 - Seg(t, 0, 0.3),
				-0.42 * side)
			D.Lit(line, "glow", holder, line.pt, side * 3.5 * F, 0, 6.5 * F, 4.2 * F, 0.8 * (1 - Seg(t, 0, 0.22)), 0)
			local st = Seg(t, 0.02, 0.5)
			local ts = t - 0.02
			local base = side < 0 and 3.1416 or 0
			for i = 1, 9 do
				local ang = base + (i / 9 - 0.5) * 2.2 + line.r2 * 0.3
				local sp = (6 + ((i * 53) % 100) * 0.058) * F
				local live = (st > 0 and st < 1) and (1 - st) or 0
				local sx, sy = math.cos(ang) * sp, math.sin(ang) * sp * 0.8 - 39.5 * F * ts
				D.Lit(line, i, holder, line.pt, side * 1.5 * F + math.cos(ang) * sp * ts,
					math.sin(ang) * sp * ts * 0.8 - 19.7 * F * ts * ts, 1.7 * F * (1 - st * 0.5), 0.4 * F, live,
					live > 0 and math.atan2(sy, sx) or 0)
			end
		elseif kc == "hit" then
			local vx, vy, g = side * (6.5 + 5 * line.r1) * F, (8.5 + 3 * line.r2) * F, 39 * F
			x, y = vx * t, vy * t - 0.5 * g * t * t
			k = D.Pop(t, 0.5, 1.2, 0.08, 0.17)
			a = Seg(t, 0, 0.03) * (1 - Seg(t, life - 0.28, life))
			flash = 0.8 * (1 - Seg(t, 0, 0.11))
			local rot = math.atan2(vy - g * t, vx)
			D.Lit(line, "streakW", line.main, "CENTER", -math.cos(rot) * 1.1 * F, -math.sin(rot) * 1.1 * F, 3.7 * F, 0.9 * F,
				0.8 * (1 - Seg(t, 0, 0.17)), rot)
		elseif kc == "heal" then
			local vx, vy, g = (3.9 + 2.4 * line.r1) * F, 7.9 * F, 10 * F
			x, y = vx * t, vy * t - 0.5 * g * t * t
			k = D.Pop(t, 0.6, 1.18, 0.08, 0.17)
			a = Seg(t, 0, 0.04) * out
			flash = 0.6 * (1 - Seg(t, 0, 0.13))
		elseif kc == "notice" then
			y = 2.9 * F * Out(t / 0.26) + 0.5 * F * Seg(t, 0.26, life)
			k = t < 0.11 and (0.6 + 0.65 * Out(t / 0.11)) or (1.25 - 0.25 * Out(Seg(t, 0.11, 0.24)))
			a = Seg(t, 0, 0.04) * out
			D.Lit(line, "streakG", line.main, "BOTTOM", 0, -1.5 * F, 6 * F * (1 - Seg(t, 0.08, 0.3)), 1.6 * F,
				0.9 * (1 - Seg(t, 0.04, 0.3)), 1.5708)
		else
			x = (line.r1 - 0.5) * 7.8 * F * t
			y = 6.8 * F * t - 0.5 * 21 * F * t * t
			a = Seg(t, 0, 0.04) * out
		end
	elseif kc == "crit" then
		x = side * 0.6 * F + D.Shake(t, 0.11, 0.15, 0.18 * F, line.r2)
		y = 2.6 * F + Out(Seg(t, life - 0.35, life)) * dir * F + D.Shake(t, 0.11, 0.15, 0.13 * F, line.r3)
		k = t < 0.11 and (2.4 - 1.4 * Out(t / 0.11)) or (1 + 0.06 * (1 - Seg(t, 0.11, 0.26)))
		a = Seg(t, 0, 0.055) * (1 - Seg(t, life - 0.28, life))
		flash = t >= 0.11 and (1 - Seg(t, 0.11, 0.26)) or 0
		local e = Seg(t, 0.11, 0.38)
		local on = t >= 0.11 and 1 or 0
		D.Lit(line, "rays", line.main, "CENTER", 0, 0, 7.9 * F * (0.75 + 0.5 * Out(e)), 7.9 * F * (0.75 + 0.5 * Out(e)),
			on * 0.9 * (1 - e), 0.35 + line.r2)
		D.Lit(line, "halo", line.main, "CENTER", 0, 0, 5 * F * (0.5 + 1.2 * Out(e)), 4 * F * (0.5 + 1.2 * Out(e)), on * 0.9 * (1 - e), 0)
		D.Lit(line, "glow", line.main, "CENTER", 0, 0, 6.8 * F, 4 * F, on * 0.85 * (1 - Seg(t, 0.11, 0.25)), 0)
	elseif kc == "hit" then
		local row = (line.nth - 1) % 3
		local sink = Seg(t, 0.5, life)
		x = side * line.r1 * 1.2 * F
		y = (1 - row) * 1.3 * F + dir * 0.95 * F * sink * sink
		k = D.Pop(t, 0.35, 1.3, 0.06, 0.135)
		a = Seg(t, 0, 0.04) * out
		flash = 0.9 * (1 - Seg(t, 0, 0.12))
	elseif kc == "heal" then
		x = line.r1 * 0.8 * F
		y = ((line.nth - 1) % 3 - 1) * 1.3 * F + 1.05 * F * Out(t / life)
		k = D.Pop(t, 0.6, 1.18, 0.07, 0.15)
		a = Seg(t, 0, 0.05) * out
		flash = 0.6 * (1 - Seg(t, 0, 0.13))
	elseif kc == "notice" then
		y = ((line.nth - 1) % 2) * 1.4 * F
		k = D.Pop(t, 0.5, 1.25, 0.07, 0.16)
		a = Seg(t, 0, 0.04) * (1 - Seg(t, life - 0.3, life))
		D.Lit(line, "streakG", line.main, "BOTTOM", 0, 0, 11.5 * F * Out(Seg(t, 0, 0.14)), 2 * F, 0.9 * (1 - Seg(t, 0.06, 0.38)), 0)
	elseif kc == "word" then
		x = (line.r1 - 0.5) * 2 * F + 1.05 * F * Out(t / life)
		y = -1.4 * F
		k = D.Pop(t, 0.7, 1.12, 0.06, 0.13)
		a = Seg(t, 0, 0.05) * out
	else
		y = -0.6 * F * Out(t / life)
		k = D.Pop(t, 0.7, 1.1, 0.06, 0.13)
		a = Seg(t, 0, 0.05) * out * 0.95
	end
	PERS.Place(line, x, y or 0)
	line:SetAlpha(a or 1)
	D.Scale(line, k, flash)
	local sign = line.sign
	if sign.SetTextScale then
		sign:SetTextScale(k)   -- (the sign with its number)
	end
end

-- a line in its kind's area; `hold`: a sample, standing still that long
function PERS.Line(e, hold)
	local look = Style()
	local name = PERS.of[e.kind]
	local A = name and PERS.Area(name)
	if not A then
		return nil
	end
	local lines = A.lines
	while #lines >= PERS.most do
		local oldest = lines[1]
		LineHidden(oldest)
		oldest:Hide()
	end
	local line = TakeLine(A.holder, pool)
	line.dealt = true   -- (the crisp look: the numbers' face, Number Outline, no band -- Fill and Lay)
	line.lane = A
	lines[#lines + 1] = line
	DEALT.LightsOff(line)
	if line.sign.SetTextScale then
		line.sign:SetTextScale(1)
	end
	local kind = e.kind
	local word = kind == "avoid" or kind == "combat" or kind == "rep"
	local notice, res = kind == "notice", kind == "resource"
	local crit = e.crit and (kind == "taken" or kind == "heal") or false
	Fill(line, e, A.align, (word and 0.8 or res and 0.7 or notice and 1.15 or 1) * (crit and DEALT.crit or 1))
	local key = (notice and not e.harmful and "notice") or ((kind == "avoid" or kind == "combat") and "word") or "value"
	line.main = line[key]
	local c = key == "value" and e.colour or nil
	line.cr, line.cg, line.cb, line.flashed = c and c[1], c and c[2], c and c[3], 0
	local F = TextSize()
	A.n = A.n + 1
	line.F, line.look, line.area, line.aname, line.pt = F, look, A, name, A.pt
	line.kindC = crit and "crit" or (notice and "notice" or word and "word" or res and "res" or (name == "heal" and "heal" or "hit"))
	line.r1, line.r2, line.r3 = math.random(), math.random(), math.random()
	line.t0, line.nth = GetTime(), A.n
	line.life = PERS.life[look][line.kindC]
	line.rowH = F * (crit and 1.6 or 1.25)
	A.holder:Show()
	local Anim = MelloUI.Anim
	if hold or Anim.reduceMotion then
		-- a sample, or Reduce Motion: at its place, a fade, nothing else (a sample in the box's upper part: the
		-- plate's name stands in its middle)
		PERS.Place(line, 0, (hold and PERS.H * PERS.sampleY or 0) + (#lines - 1) * 1.25 * F * (name == "resource" and -1 or 1))
		line:SetAlpha(1)
		Anim:Mirror(line, hold and T.fadeIn or 0.05, hold or (line.life - 0.3), hold and T.fadeOut or 0.25)
		return line
	end
	PERS.Place(line, 0, 0)
	line:SetAlpha(0)
	line:Show()
	Anim:Drive(line, PERS.Step, line.life, "linear", DEALT.StepDone)
	return line
end

-- every line of the areas gone at once (the style changed, the module off)
function PERS.Clear()
	for _, name in ipairs(PERS.order) do
		local A = PERS.areas[name]
		local lines = A.lines
		while lines and #lines > 0 do
			local line = lines[1]
			LineHidden(line)
			line:Hide()
		end
	end
end

-- Edit Position (the Combat Text tab's button): Combat Text's own Edit Layout session, its four areas alone
function PERS.Edit()
	if not M.isEnabled then
		return
	end
	if not PERS.looks[Style()] then
		MelloUI:Announce(TEXT.editPick, "info")
		return
	end
	for _, name in ipairs(PERS.order) do
		PERS.Area(name)
	end
	if not MelloUI.StartEditLayout or MelloUI:StartEditLayout("configurator", nil, PERS.SESSION, PERS.TITLE) == false then
		MelloUI:Announce(TEXT.editBusy, "info")
	end
end

M.EditPosition = PERS.Edit

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

feed = MelloUI.Feed:New({ name = "MelloUICombatFeed", key = "combatfeed", label = "Combat Text", page = OWNER, category = "combat",
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
	SPELL_AURA_START = { "notice", data = true, aura = "start" }, SPELL_CAST = { "notice", data = true },
	SPELL_AURA_START_HARMFUL = { "notice", data = true, harmful = true, aura = "start" },
	SPELL_AURA_END = { "notice", fades = true, aura = "end" }, SPELL_AURA_END_HARMFUL = { "notice", fades = true, aura = "end" },
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
-- (0.25.0, the user's Batch 14, the lightened ones: MelloUI's icon set) a kind's mark, white and grey for the kind's
-- tint: claw slashes for damage taken, a cross for healing, a star for a notice, a buckler for a dodge, parry or
-- block, a drop for a gain (the widget glyphs triangle, cross, star, ring and drop until then)
local GLYPH = { taken = "ct_taken", heal = "ct_heal", notice = "ct_notice", avoid = "ct_avoid", resource = "ct_gain",
	combat = "ct_notice", rep = "ct_gain" }

-- a word the game names (COMBAT_TEXT_DODGE, ENTERING_COMBAT ...), else ours
local function Word(w)
	return Text(rawget(_G, "COMBAT_TEXT_" .. w)) or Text(rawget(_G, w)) or MelloUI.Widgets.Tr(TEXT[w] or w)
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

-- (1.2.1) An aura that comes or goes again within T.auraQuiet s is told once,
-- then nothing until it has stayed away that long (a player's report,
-- 2026-10-15: a warlock's Demonic Knowledge, given again each time the pet
-- came back in range, a line every few seconds). By its plain name, one
-- time a name in each table (a secret name cannot be told apart: shown).
local auraStarted, auraEnded = {}, {}
local function AuraQuiet(spec, data)
	local name = Text(data)
	if not name then
		return false
	end
	local seen = spec.aura == "start" and auraStarted or auraEnded
	local now, last = GetTime(), seen[name]
	seen[name] = now
	return last ~= nil and now - last < T.auraQuiet
end

-- the event's entry, or nil (a kind not shown, nothing to show)
local function Entry(kind, data, arg3, arg4)
	local spec = KINDS[kind]
	if not spec then
		return nil
	end
	if spec.aura and AuraQuiet(spec, data) then
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
			e.tail = MelloUI.Widgets.Tr(TEXT.absorbed)
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
		-- (2.1.85; the user: "make sure that the damage is colored correctly") a spell's hit in its school's colour,
		-- a crit of it too; a weapon's hit in the text colour, its crit gold. A school the game keeps secret, or one
		-- it has no name for: the spell colour of before
		local s = Num(school)
		local key = nil
		if s and s > 1 then
			-- (each school one power of two in the game's number: its place read by arithmetic alone)
			for i = 1, #DEALT.schools do
				local sc = DEALT.schools[i]
				if math.floor(s / sc[1]) % 2 == 1 then
					key = sc[2]
					break
				end
			end
			key = key or "combatSpell"
		end
		local Meaning = MelloUI.Meaning
		e.colour = (key and (Meaning[key] or Meaning.combatSpell)) or (e.crit and RoleRGB("gold")) or RoleRGB("text")
		return e
	elseif DEALT.words[event] then
		e.kind, e.label = "avoid", Word(event)
		return e
	end
	return nil
end

-- a heal a friend took (UNIT_COMBAT's flag and amount): a number in the healing's colour, a crit bigger
function DEALT.HealEntry(flags, amount)
	local e = Clear(E)
	e.kind, e.value, e.heal = "dealt", amount, true
	e.crit = (Text(flags) == "CRITICAL") or nil
	e.colour = MelloUI.Meaning.combatHeal
	return e
end

-- a friend's plate MelloUI can stand on, not your own: true; a plate the game keeps to itself: nil; anything else
-- (an enemy, yourself, an answer the game keeps secret): false
function DEALT.FriendPlate(unit)
	local okA, attack = pcall(UnitCanAttack, "player", unit)
	if not okA or Secret(attack) or attack then
		return false
	end
	local plate = PlateOf(unit)
	if not plate then
		return nil
	end
	-- (your own plate, the Personal Resource Display's: the plate itself compared, no unit question)
	if plate == PlateOf("player") then
		return false
	end
	return true
end

-- UNIT_COMBAT's HEAL on a plate: kept for its frame's end, yours when a line of the combat log is its own
function DEALT.Heal(unit, flags, amount)
	if not (DEALT.listen and DEALT.HealsDrawing()) then
		return
	end
	local friend = DEALT.FriendPlate(unit)
	if friend == nil then
		DEALT.NoFriend()
		return
	end
	if friend then
		DEALT.Queue(unit, DEALT.HealEntry(flags, amount), true)
	end
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
	if PERS.looks[style] then
		return PERS.Line(e, hold)
	end
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

-- /mello combattext log (2.1.85, docs/plans/damage-text-redo.md, the group source): for LOG_TIME seconds, what the
-- client sends as you fight, in the chat -- each hit an enemy's plate reports (UNIT_COMBAT), each line of the game's
-- combat log (COMBAT_LOG_MESSAGE: only that it came, its order and whether its text and colour are plain), your swings
-- and your casts -- with their times, to see which of them come together. Nothing secret is printed or compared.
local LOG_TIME = 20
-- (a value named for the print: the word "secret" for one the game keeps, never the value itself)
local function Named(v)
	return Secret(v) and "secret" or tostring(v)
end
local function ProbeLog(text, ...)
	if S.logUntil and GetTime() < S.logUntil then
		MelloUI:Print("%.2f " .. text, GetTime() % 100, ...)
	end
end

function M.LogProbe()
	S.logUntil = GetTime() + LOG_TIME
	local CL = rawget(_G, "C_CombatLog")
	local function Ask(name)
		local fn = type(CL) == "table" and CL[name]
		if type(fn) ~= "function" then
			return "none"
		end
		local ok, v = pcall(fn)
		return ok and Named(v) or "refused"
	end
	MelloUI:Print("Combat Text: %d seconds of hits, combat log lines, swings and casts. Fight something, then copy the lines with /mellolog. "
		.. "Lines on: %s. Log restricted: %s. In a group: %s. Your heals: %s.", LOG_TIME, Ask("AreFilteredEventsEnabled"),
		Ask("IsCombatLogRestricted"), tostring(MelloUI.Threat.Grouped() and true or false),
		DEALT.HealsWhy() or "drawn by MelloUI")
	Events()
	C_Timer.After(LOG_TIME + 0.2, Events)
end
M.SlashWords = { order = M.OrderLog, log = M.LogProbe }

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
		local ev, flag, amount, school = ...
		local heal = not Secret(ev) and ev == "HEAL"
		if S.logUntil and GetTime() < S.logUntil then
			if heal then
				local friend = DEALT.FriendPlate(arg1)
				ProbeLog("HEAL %s flag %s amount %s (a friend's plate: %s)", arg1, Named(flag), Secret(amount) and "secret" or "plain",
					friend == true and "yes" or friend == nil and "the game's own" or "no")
			else
				ProbeLog("HIT %s %s flag %s amount %s school %s", arg1, Named(ev), Named(flag), Secret(amount) and "secret" or "plain",
					Named(school))
			end
		end
		-- (2.1.85) a heal: yours when the combat log's lines say so, at a friend's plate
		if heal then
			DEALT.Heal(arg1, flag, amount)
			return
		end
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
		if MelloUI.Threat.Grouped() or DEALT.threatHidden then
			-- (2.1.85) in a group: yours when the combat log's lines say so (DEALT.Close); a friend's plate never
			if fought ~= false then
				local e = DealtEntry(...)
				if e then
					DEALT.Queue(arg1, e, true)
				end
			end
			return
		end
		if fought == nil then
			-- the list secret: whose hit cannot be told by it -- by the combat log's lines from here on
			-- (Your Damage In Groups), else the game's numbers for the rest of this fight
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
			elseif DEALT.listen then
				DEALT.Queue(arg1, e, false)   -- (the lines flow: drawn at its frame's end, a tick told)
			else
				DealtLine(arg1, e)
			end
		end
	elseif event == "COMBAT_LOG_MESSAGE" then
		local message, r, _, _, order = arg1, ...
		ProbeLog("LINE order %s text %s colour %s", Named(order), Secret(message) and "secret" or "plain",
			Secret(r) and "secret" or "plain")
		if DEALT.listen then
			-- (a line replayed at a refilter is an old one: order Oldest)
			local EO = Enum and Enum.CombatLogMessageOrder
			local oldest = type(EO) == "table" and type(EO.Oldest) == "number" and EO.Oldest or 1
			local newest = type(EO) == "table" and type(EO.Newest) == "number" and EO.Newest or 0
			if Secret(order) or order == newest or order ~= oldest then
				local L = DEALT.Frame()
				L.lines = L.lines + 1
			end
		end
	elseif event == "PLAYER_SWING" then
		ProbeLog("SWING type %s", Named((select(1, ...))))
		if DEALT.listen then
			local L = DEALT.Frame()
			L.swings = L.swings + 1
			local sw = tremove(L.spare) or {}
			sw.at, sw.line = L.at, nil
			L.pending[#L.pending + 1] = sw
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		ProbeLog("CAST by %s", Named(arg1))
		if DEALT.listen and arg1 == "player" then
			local L = DEALT.Frame()
			L.casts = L.casts + 1
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
		name = name and name:lower()
		if name == "nameplateshowenemies" or name == "nameplateshowfriendlyplayers" then
			Apply()
		end
	elseif event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
		-- (2.1.85) a friendly plate the game keeps to itself: no place for your heals here
		DEALT.NoFriend()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- (2.1.85) a new place: its friendly plates may be MelloUI's to stand on again, or a dungeon's
		DEALT.noFriend = false
		Apply()
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
			S.dealtPending = nil
			Apply()   -- (the game's numbers MelloUI stands in for, as the state is now)
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
	local heals = chosen and DEALT.HealsReady()
	local waiting = S.cvarPending ~= nil or S.dealtPending ~= nil or next(enemyPending) ~= nil
	local probing = S.logUntil ~= nil and GetTime() < S.logUntil
	-- (2.1.85) the combat log's lines counted while Your Damage (or your heals) is on and they flow
	DEALT.listen = (dealt or heals) and DEALT.LinesOn() or false
	if not (want or chosen or waiting or probing) then
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
		-- (2.1.85) your heals: a new place's friendly plates, and one the game keeps to itself (a client without the
		-- event just lacks that sign)
		local db = DB()
		if not (db and db.dealtHeals == false) then
			events:RegisterEvent("PLAYER_ENTERING_WORLD")
			if not DEALT.noFriend then
				pcall(events.RegisterEvent, events, "FORBIDDEN_NAME_PLATE_UNIT_ADDED")
			end
		end
	end
	if probing or DEALT.listen then
		-- (each asked for under pcall -- a client without one of them just lacks its lines)
		pcall(events.RegisterEvent, events, "COMBAT_LOG_MESSAGE")
		pcall(events.RegisterEvent, events, "PLAYER_SWING")
		pcall(events.RegisterUnitEvent or events.RegisterEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
	end
	if dealt or heals or probing or (S.orderUntil and GetTime() < S.orderUntil) then
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
	-- (2.1.85) a friend targeted: your heals' samples at its plate
	local h = DEALT.HealsDrawing() and DEALT.FriendPlate("target") and DEALT.heals[burst] or nil
	local d = not h and DealtDrawing() and PlateOf("target") and DEALT.samples[burst] or nil
	if not (s or d or h) then
		burst = 0
		return
	end
	if s then
		Show(SampleEntry(s))
	end
	if h then
		DealtLine("target", DEALT.HealEntry(h[1], h[2]))
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
	local heals = DEALT.HealsDrawing() and DEALT.FriendPlate("target")
	if not ours and not heals and not (dealt and PlateOf("target")) then
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
	-- (2.1.85) the three looks' areas show their samples in Combat Text's own session (Edit Position: the bus's
	-- 'editsession'), the earlier styles' lanes in the common one as before
	local want = false
	if Ours() then
		if PERS.looks[Style()] then
			want = MelloUI:EditSession() == PERS.SESSION
		else
			want = MelloUI:EditingLayout() and true or false
		end
	end
	if want == S.samples then
		return
	end
	S.samples = want
	if want then
		local style = Style()
		local list = (style == "lanes" or PERS.looks[style]) and { 1, 2, 5, 6 } or { 1, 2, 5 }
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
	-- (2.1.85: the three looks' areas)
	for _, name in ipairs(PERS.order) do
		local lines = PERS.areas[name].lines
		for i = 1, lines and #lines or 0 do
			fn(lines[i])
		end
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

-- the state the settings ask for: a style of ours on (the game's text kept
-- coming and faded), or the game's own back
Apply = function()
	local db = DB()
	DEALT.KeepLines()
	-- (2.1.85: your heals by themselves -- the game's healing numbers off only while MelloUI draws them)
	local damage, heals = DealtDrawing(), DEALT.HealsDrawing()
	if damage or heals then
		DealtSwitch(damage, heals)
		S.dealtStarted = true
	elseif S.dealtStarted or (db and db.savedDealt ~= nil) then
		S.dealtStarted = false
		DealtSwitch(false, false)
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
		PERS.Clear()
		feed:Clear()
		S.samples = false
		for i = #held, 1, -1 do
			held[i] = nil
		end
	end
	Events()
end

DEALT.Apply = Apply

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
	-- (2.1.85) a look of before, kept as the new one nearest to it (the dropdown shows what is drawn)
	local old = db and DEALT.old[db.dealt]
	if old then
		db.dealt = old
	end
end

function M:OnEnable(db)
	self.db = db
	MelloUI:On("setting", OnSetting, OWNER)
	MelloUI:On("editlayout", OnEditLayout, OWNER)
	MelloUI:On("editsession", OnEditLayout, OWNER)   -- (2.1.85: Combat Text's own session, Edit Position)
	MelloUI:On("restart", OnRestart, OWNER)
	MelloUI:On("palette", Repaint, OWNER)
	MelloUI:On("preview", OnPreview, OWNER)
	-- (switched on again: the lines kept from before -- the pool, the lanes, Your Damage's -- in the fonts and the
	-- palette as they are now; nothing at the login, when none is made yet)
	EachLine(Restyle)
	Repaint()
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
	elseif key == "dealt" or key == "dealtGroups" or key == "dealtHeals" then
		Apply()
	elseif key == "size" or key == "titleNotices" or key == "shadeSize" or key == "dealtOutline" then
		RestyleAll()
	elseif key == "lines" then
		feed:Fit()
	elseif ENEMY[key] then
		Enemy.Write(key, value)
		if key == "enemyHealing" then
			Apply()   -- (2.1.85: the game's healing numbers on: MelloUI's in their place where it draws them)
		end
	end
end
