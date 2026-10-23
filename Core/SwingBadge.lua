--------------------------------------------------------------------------------
-- MelloUI - Swing Badge (1.2.0)
--
-- Your swing timer as a badge (the user, 2026-10-21: the swing "reimagined ... a visual indicator/feedback without it
-- cluttering the screen with bars, but that its noticable of whats happening", "shown on the enemy nameplates", "more
-- expressive"; the pick: BuildData/output/animation_previews/pull_expressive.html, the plan docs/plans/swing-badge.md).
-- (Animations round 3, the user 2026-10-22, "yes to all" to more_anims.html: docs/plans/animations-3.md, item 1) One
-- system for everyone: the Personal Display's Swing Badge and the Swing Timers both wear it (their bars retired), one
-- at a time -- the Personal Display's while it shows the badge, else the Swing Timers'.
--
-- Your weapon in the gold ring (W.RoundIcon), the game's own sweep over it (its shade turning off as the next swing
-- nears: the engine counts it), on your target's plate right of its level box -- the off hand's smaller one beside it,
-- away from the bar -- or, with no plate for your target (nameplates off, the target off screen), at the host's own
-- place: the Personal Display's left end, the Swing Timers' mover above the cast bar. The timing is the client's alone
-- (PLAYER_SWING: its seconds to the next swing, the hand): nothing counted here. The motion (Anim:Drive: Lua only while
-- one runs; Reduce Motion: no wind-up, the rest at its end at once): the wind-up over the wait's last share (the weapon
-- drawn back from the bar, a warm glow); the strike as the blow lands (an axe, a sword, a mace chops; a dagger or a fist
-- weapon stabs: snapped toward the bar, settled on a spring), a streak across the target's health bar and the bar lit.
-- (The user, 2026-10-23, with a video: the glow "starts when the attack animation starts ... way before the attack lands
-- on the enemy") PLAYER_SWING comes as a swing begins; the game's report of the blow on your target (UNIT_COMBAT,
-- "target") a moment later, as it lands -- so a swing's strike waits for that report, the time between the two learned
-- from your last swings (Swing.Gap: their middle, so a bleed's tick or another's blow in between can't move it): a
-- report near that time strikes with its outcome, one far earlier is left out, and with none the strike comes at the
-- learned time. The outcome: a critical blow gold and bigger, a dodge, parry or miss bounced back grey with the
-- game's word; (the user, 2026-10-22: "as the hits land, there should be like sun rays sparking from the middle of the
-- icon") every blow that lands sparks sun rays from the weapon's middle (the look's light art, FrameFX.Art: the
-- modern look's own), a critical one bigger and brighter -- each strike's turned a little from the last. Auto Shot: its aim red, four chevrons closing on the badge (moving holds them, spread and dimmed), the
-- shot a recoil and a tracer into the plate; a wand gathers three motes and throws its bolt. Out of range (the game's
-- own check, PLAYER_SWING_RANGE_UPDATE: the Swing Timers' before) a badge's weapon red-tinted (Meaning.actionRange).
-- Made with the first swing (nothing at login); nothing written on the game's frames (the badge is parented to the
-- plate's UnitFrame, as the combo points' row is: Nameplates' TargetPlate).
--
--   SB:Use(host) / SB:Drop(host)   a host in use or not: the events listened to while one is; the badges laid at the
--       one in charge (SB.Active: the Personal Display's first). host = {
--         key    "personal" | "swingtimers"
--         Here(big, small)   the two laid at its own place (SB.Attach, their points): no plate for your target
--         Wants(hand)        (optional) whether a hand's swing shows: "main", "off", "ranged"
--         Quiet()            (optional) true while it plays its own preview: the game's swings and stops left out
--         Style(fs, size)    (optional) the word's font (else the Interface text's)
--       }
--   SB.Start(hand, seconds), SB.Shot(seconds), SB.Outcome(action, flag): a swing, a shot, the game's report of a blow
--       (a host's preview drives them too); SB.Off(): every badge put away; SB.Lay(): laid again (the host's place
--       moved)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("SwingBadge")
local C_Timer = Perf.C_Timer
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Anim = MelloUI.Anim
local W = MelloUI.Widgets

local SB = {}
MelloUI.SwingBadge = SB

-- the badge's size as made (on a target's plate, in its units), the off hand's share of it, the gap to what it
-- stands beside; the wind-up (the wait's last share), the strike's length, how soon after your swing the game's report
-- of the blow on your target is taken as its outcome; how long after a swing's time with no next one it goes; the aim
-- at a shot's end (Auto Shot's last half second, standing still); the word's size
SB.T = { badge = 24, badgeOff = 0.66, badgeGap = 4, windup = 0.25, strike = 0.5, outcomeWindow = 0.2, swingGrace = 0.6,
	aim = 0.5, word = 12,
	-- (the sun rays as a blow lands) how long they spark (a crit's a little longer), their size against the badge's
	-- at the start and at the end (a crit's), their strength, how far each strike's turns from the last's
	rays = 0.32, raysCrit = 0.42, raysFrom = 0.5, raysTo = 2.2, raysCritTo = 3.6, raysA = 0.75, raysCritA = 1,
	raysTurn = 0.7,
	-- (a swing's blow: 2026-10-23) the time from a swing to its blow's report before any is learned (the user's video:
	-- ~0.6 s), the swings it is learned from, how near the learned time a report must come to be the blow (a share of
	-- that time), and how long after its swing a blow is waited for at most
	-- (and the least time learned: a report sooner after its swing -- a tick in the same moment -- is never its blow)
	landGuess = 0.6, landSamples = 9, landNear = 0.4, landWindow = 1.0, landMin = 0.15 }
local T = SB.T

-- the badge's art and its lights' colours; the slot of each hand's weapon; a weapon whose blow is a stab (a fist
-- weapon, a dagger: the item subclass); a badge with no weapon (unarmed); the outcomes of the game's report; the
-- swing types of PLAYER_SWING
SB.ART = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\"
SB.ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
SB.WHITE = "Interface\\Buttons\\WHITE8X8"
SB.GOLD, SB.STEEL, SB.ARCANE = { 1, 0.8, 0.35 }, { 0.75, 0.8, 0.9 }, { 0.78, 0.67, 1 }
SB.PLAIN = { 1, 1, 1 }
SB.SLOT = { main = 16, off = 17, ranged = 18 }
SB.STAB = { [13] = true, [15] = true }
SB.UNARMED = "Interface\\Icons\\INV_Gauntlets_04"
SB.OUTCOME = { DODGE = "dodge", PARRY = "parry", MISS = "miss" }
SB.WORD = { dodge = "DODGE", parry = "PARRY", miss = "MISS" }   -- (the game's own words, its globals)
SB.WORDS = { DODGE = "Dodge", PARRY = "Parry", MISS = "Miss" }   -- (where the game's are not there)
SB.HAND = { [0] = "main", [1] = "off", [2] = "ranged" }

local Badge = { list = {}, pending = { at = nil, what = nil } }   -- (pending: a report of the blow before the swing)
-- (gaps: the times from your last swings to their blows' reports, a ring of T.landSamples)
local Swing = { due = { main = 0, off = 0, ranged = 0 }, gaps = {}, nGap = 0, sorted = {} }
-- (Auto Shot) the stage -- "reload", "aim", "hold" (moving), "wand" -- and the aim's due time: one C_Timer.After a
-- shot, the function shared (a later shot moves aimAt, an earlier call finds it not due); the range per hand
local Ranged = { stage = nil, aimAt = 0, moving = false, wand = false }
SB.Badge, SB.Swing, SB.Ranged = Badge, Swing, Ranged   -- (the tests')
SB.hosts, SB.ORDER = {}, { "personal", "swingtimers" }
SB.out = {}   -- [hand] = true out of range

-- a call a frame may lack on this client (each set once, at the sweep's making)
local function Try(frame, method, ...)
	local fn = frame[method]
	if type(fn) == "function" then
		pcall(fn, frame, ...)
	end
end

-- a light: Frame Effects' art added to what is under it, in a colour
local function Spark(parent, layer, sub, file, colour)
	local tex = parent:CreateTexture(nil, layer, nil, sub)
	tex:SetTexture(SB.ART .. file)
	tex:SetBlendMode("ADD")
	if colour then
		tex:SetVertexColor(colour[1], colour[2], colour[3])
	end
	return tex
end

-- the host in charge: the Personal Display's while it shows the badge, else the Swing Timers'
function SB.Active()
	for _, key in ipairs(SB.ORDER) do
		local host = SB.hosts[key]
		if host then
			return host
		end
	end
	return nil
end

-- the word's font: the host's, else the Interface text's
local function StyleWord(b)
	local host = SB.Active()
	if host and host.Style then
		host.Style(b.word, T.word)
	else
		MelloUI.Look.Text(b.word, "text", T.word)
		b.word:SetShadowOffset(1, -1)
	end
end

--------------------------------------------------------------------------------
-- The badges
--------------------------------------------------------------------------------

-- one badge (made with the first swing, kept): a holder its parent carries (the plate's UnitFrame, or the host's
-- place), the ring and the weapon, the sweep, and over them its lights: the glow, the burst, the word, the aim's four
-- chevrons, the wand's three motes; on the plate the health bar's light and streak, the shot's tracer
function Badge.Make(small)
	local d = T.badge * (small and T.badgeOff or 1)
	local b = CreateFrame("Frame", nil, UIParent)
	b:SetSize(d, d)
	b:EnableMouse(false)
	b:Hide()
	b.d = d
	local ring = W.RoundIcon(b, d, nil)
	ring:EnableMouse(false)   -- (a picture in a rim)
	ring:SetKit(W.KitFor("unitframes"))
	b.ring = ring
	local sweep = CreateFrame("Cooldown", nil, ring, "CooldownFrameTemplate")
	sweep:SetAllPoints(ring.icon)
	Try(sweep, "SetSwipeTexture", SB.ROUND)
	Try(sweep, "SetDrawEdge", false)
	Try(sweep, "SetHideCountdownNumbers", true)
	sweep:EnableMouse(false)
	b.sweep = sweep
	local fx = CreateFrame("Frame", nil, b)
	fx:SetAllPoints(b)
	b.fx = fx
	b.glow = Spark(fx, "OVERLAY", 4, "glow_white.tga")
	b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
	-- (the sun rays from the weapon's middle, over it: the look's own light art at about a texel a pixel)
	b.burst = fx:CreateTexture(nil, "OVERLAY", nil, 7)
	b.burst:SetTexture(MelloUI.FrameFX and MelloUI.FrameFX.Art and MelloUI.FrameFX.Art("rays_gold_small.tga")
		or SB.ART .. "rays_gold_small.tga")
	b.burst:SetBlendMode("ADD")
	b.burst:SetPoint("CENTER", ring, "CENTER", 0, 0)
	b.ticks, b.motes = {}, {}
	local aim = MelloUI.Meaning.swingAim
	for i = 1, 4 do
		local t = fx:CreateTexture(nil, "OVERLAY", nil, 6)
		W.Icon(t, "edge_arrow")
		t:SetVertexColor(aim[1], aim[2], aim[3])
		t:SetSize(d * 0.42, d * 0.42)
		t:SetRotation((i - 0.5) * math.pi / 2 + 3 * math.pi / 2)   -- (the art's V points down: turned at the badge)
		b.ticks[i] = t
	end
	for i = 1, 3 do
		b.motes[i] = Spark(fx, "OVERLAY", 6, "glow_white.tga", SB.ARCANE)
		b.motes[i]:SetSize(d * 0.34, d * 0.34)
	end
	b.word = fx:CreateFontString(nil, "OVERLAY")
	StyleWord(b)
	b.flash = fx:CreateTexture(nil, "OVERLAY", nil, 3)
	b.flash:SetTexture(SB.WHITE)
	b.flash:SetBlendMode("ADD")
	-- (the streak from the badge's side: the bar's right end, its head bright)
	local streak = CreateFrame("StatusBar", nil, fx)
	streak:SetStatusBarTexture(SB.WHITE)
	local style = Enum and Enum.StatusBarFillStyle
	if style and style.Reverse and streak.SetFillStyle then
		pcall(streak.SetFillStyle, streak, style.Reverse)
	end
	local tex = streak:GetStatusBarTexture()
	tex:SetBlendMode("ADD")
	if tex.SetGradient and CreateColor then
		pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(1, 1, 1, 0.95), CreateColor(1, 1, 1, 0))
	end
	streak:SetMinMaxValues(0, 1)
	b.streak = streak
	b.tracer = Spark(fx, "OVERLAY", 7, "glow_white.tga", SB.GOLD)
	b.tracer:SetSize(d * 0.6, d * 0.4)
	Badge.list[#Badge.list + 1] = b
	Badge.Rest(b)
	return b
end

-- a badge's weapon in its own colours, or red-tinted out of range
local function Base(b)
	return SB.out[b.hand] and MelloUI.Meaning.actionRange or SB.PLAIN
end

-- a badge at rest: the weapon still and plain, every light out
function Badge.Rest(b)
	local ring = b.ring
	local c = Base(b)
	ring.icon:SetRotation(0)
	ring.icon:SetVertexColor(c[1], c[2], c[3])
	ring:SetScale(1)
	W.RoundIconRefit(ring)
	ring:ClearAllPoints()
	ring:SetPoint("CENTER", b, "CENTER", 0, 0)
	for _, r in ipairs({ b.glow, b.burst, b.word, b.flash, b.streak, b.tracer }) do
		r:SetAlpha(0)
	end
	for _, t in ipairs(b.ticks) do
		t:SetAlpha(0)
	end
	for _, m in ipairs(b.motes) do
		m:SetAlpha(0)
	end
end

-- the badge's parent, scale and levels (the plate's health bar under it, or the host's place)
function SB.Attach(b, parent, level, k)
	if b.parent ~= parent then
		b.parent = parent
		b:SetParent(parent)
	end
	b:SetScale(k)
	b:SetFrameLevel(level)
	b.ring:SetFrameLevel(level + 1)
	b.sweep:SetFrameLevel(level + 2)
	b.fx:SetFrameLevel(level + 4)
	b.streak:SetFrameLevel(level + 3)
end

-- the plate's health bar under a badge's light and streak (nil: none, the badge at the host's place)
function Badge.BarOn(b, hb)
	if b.bar == hb then
		return
	end
	b.bar = hb
	b.flash:ClearAllPoints()
	b.streak:ClearAllPoints()
	if hb then
		b.flash:SetAllPoints(hb)
		b.streak:SetAllPoints(hb)
	end
end

-- where the badges stand: on your target's plate (right of its level box while that shows, else of its health bars;
-- the strike toward the bar on their left, dir -1), else at the host's place (dir 1, no bar). Laid on a new target,
-- a plate added or taken, each swing (cheap) and when the host's place moves (SB.Lay)
function Badge.Place()
	local big, small = Badge.big, Badge.small
	local host = SB.Active()
	if not (big and host) then
		return
	end
	local NP = MelloUI:GetModule("Nameplates")
	local uf = NP and NP.TargetPlate and NP:TargetPlate()
	if uf then
		local container = uf.HealthBarsContainer
		local hb = container.healthBar
		local lf = uf.PlayerLevelDiffFrame
		local beside = (lf and MelloUI.Safe.Call(lf, "IsShown") == true) and lf or container
		local ok, level = pcall(hb.GetFrameLevel, hb)
		level = ((ok and Num(level)) or 0) + 10
		SB.Attach(big, uf, level, 1)
		SB.Attach(small, uf, level, 1)
		big:ClearAllPoints()
		big:SetPoint("LEFT", beside, "RIGHT", T.badgeGap, 0)
		small:ClearAllPoints()
		small:SetPoint("LEFT", big, "RIGHT", 3, 0)
		Badge.BarOn(big, hb)
		Badge.BarOn(small, hb)
		big.dir, small.dir = -1, -1
		return
	end
	host.Here(big, small)
	Badge.BarOn(big, nil)
	Badge.BarOn(small, nil)
	big.dir, small.dir = 1, 1
end

function SB.Lay()
	if Badge.big then
		Badge.Place()
	end
end

-- the badge of a hand (the off hand's the small one; a shot's the main one), both made the first time
function Badge.For(hand)
	if not Badge.big then
		Badge.big, Badge.small = Badge.Make(false), Badge.Make(true)
		Badge.Place()
	end
	return hand == "off" and Badge.small or Badge.big
end

-- the weapon a badge shows and its blow: the slot's icon (unarmed: a gauntlet); a dagger or a fist weapon stabs, the
-- rest chops; the ranged slot's while shooting (a wand: its bolt, else the shot)
function Badge.Weapon(b, hand)
	local slot = SB.SLOT[hand]
	local okT, tex = pcall(GetInventoryItemTexture, "player", slot)
	b.ring:SetIcon((okT and not Secret(tex) and tex) or SB.UNARMED)
	if hand == "ranged" then
		b.kind = Ranged.wand and "wand" or "shot"
		return
	end
	local sub
	local okI, id = pcall(GetInventoryItemID, "player", slot)
	local info = C_Item and C_Item.GetItemInfoInstant
	if okI and not Secret(id) and type(id) == "number" and info then
		local okS, _, _, _, _, _, _, subclass = pcall(info, id)
		sub = okS and Num(subclass) or nil
	end
	b.kind = SB.STAB[sub] and "stab" or "chop"
end

-- a hand's run: its badge shown with its weapon, the sweep over the `seconds` to the next swing, the wind-up (a
-- wand: its motes) set for its last share
function Badge.Run(hand, seconds)
	local b = Badge.For(hand)
	b.hand = hand
	Badge.Weapon(b, hand)
	Badge.Place()
	Try(b.sweep, "SetCooldown", GetTime(), seconds)
	b.running = true
	Anim:Stop(b, "alpha")
	if not b:IsShown() then
		b:SetAlpha(0)
		b:Show()
	end
	Anim:To(b, "alpha", 1, 0.15)
	if b.kind == "shot" or Anim.reduceMotion then
		b.windAt = nil
		return
	end
	local lead = seconds * (b.kind == "wand" and 0.5 or T.windup)
	b.windAt, b.windFor = GetTime() + seconds - lead, lead
	C_Timer.After(seconds - lead, Badge.WindUp)
end

-- (C_Timer.After) the wind-up (or the wand's motes) of each badge whose time it is
function Badge.WindUp()
	local now = GetTime()
	for _, b in ipairs(Badge.list) do
		if b.windAt and b.running and now + 0.01 >= b.windAt then
			b.windAt = nil
			b.motion = b.kind == "wand" and "motes" or "windup"
			Anim:Drive(b, Badge.Step, b.windFor, "linear")
		end
	end
end

-- the time from a swing to its blow's report: the middle of the last ones (T.landGuess before any)
function Swing.Gap()
	local gaps, sorted = Swing.gaps, Swing.sorted
	local n = #gaps
	if n == 0 then
		return T.landGuess
	end
	for i = 1, n do
		sorted[i] = gaps[i]
	end
	table.sort(sorted)
	return sorted[math.floor((n + 1) / 2)]
end

function Swing.Learn(gap)
	Swing.nGap = Swing.nGap % T.landSamples + 1
	Swing.gaps[Swing.nGap] = gap
end

-- the strike, the blow's outcome ("hit" when no report told one)
function Badge.Land(b, what)
	b.swungAt = nil
	b.landAt = GetTime()
	b.outcome, b.told = what or "hit", what ~= nil
	Badge.Said(b)
	b.raysAt = ((b.raysAt or 0) + T.raysTurn) % (2 * math.pi)   -- (each strike's rays turned from the last's)
	b.motion = "strike"
	Anim:Drive(b, Badge.Step, T.strike, "linear")
end

-- a swing of `hand` began (its badge's run to the next one just started): its blow waited for -- the one before struck
-- now if it still waits; a report just before this swing (a host's preview tells them in that order) strikes at once
function Badge.Swung(hand)
	local b = hand == "off" and Badge.small or Badge.big
	if not (b and b.running and b.hand == hand) then
		return
	end
	if b.swungAt then
		Badge.Land(b, nil)
	end
	local now, p = GetTime(), Badge.pending
	if p.at and now - p.at <= T.outcomeWindow then
		local what = p.what
		p.at = nil
		Badge.Land(b, what)
		return
	end
	b.swungAt, b.gap, b.learned = now, Swing.Gap(), false
	C_Timer.After(b.gap, Badge.Due)
end

-- (C_Timer.After) the strike of each swing whose blow came at no report by its learned time
function Badge.Due()
	local now = GetTime()
	for _, b in ipairs(Badge.list) do
		if b.swungAt and now + 0.01 >= b.swungAt + b.gap then
			Badge.Land(b, nil)
		end
	end
end

-- an avoided blow's word (the game's own: DODGE, PARRY, MISS)
function Badge.Said(b)
	local key = SB.WORD[b.outcome]
	if key then
		local text = rawget(_G, key)
		if Secret(text) or type(text) ~= "string" or text == "" then
			text = SB.WORDS[key] or key
		end
		b.word:SetText(text)
	end
end

-- (UNIT_COMBAT on your target) the game's report of a blow: the swing waiting longest for its blow -- its first
-- report is learned from; one near its learned time (or after) strikes it, one far earlier (a bleed's tick, another
-- player's blow) is left out. With none waiting: the outcome of the strike made just before it (its learned time came
-- first; a shot's, which strikes as it is fired), else kept for a swing that comes just after it. Another player's
-- blow in that moment can be taken for yours
function SB.Outcome(action, flag)
	if not Badge.big or Secret(action) or type(action) ~= "string" then
		return
	end
	local what
	if action == "WOUND" then
		what = (not Secret(flag) and flag == "CRITICAL") and "crit" or "hit"
	else
		what = SB.OUTCOME[action]
	end
	if not what then
		return
	end
	local now, wait = GetTime(), nil
	for _, b in ipairs(Badge.list) do
		if b.swungAt and now - b.swungAt <= T.landWindow and (not wait or b.swungAt < wait.swungAt) then
			wait = b
		end
	end
	if wait then
		local gap = now - wait.swungAt
		if not wait.learned and gap >= T.landMin then
			wait.learned = true
			Swing.Learn(gap)
		end
		if gap >= wait.gap * (1 - T.landNear) then
			Badge.Land(wait, what)
		end
		return
	end
	local best = nil
	for _, b in ipairs(Badge.list) do
		if b.landAt and now - b.landAt <= T.outcomeWindow and (not best or b.landAt > best.landAt) then
			best = b
		end
	end
	if best then
		if not best.told then   -- (one report a blow: the first)
			best.outcome, best.told = what, true
			Badge.Said(best)
		end
	else
		Badge.pending.at, Badge.pending.what = now, what
	end
end

-- Auto Shot's aim: the badge red, the four chevrons closing on it over T.aim; held (moving): spread and dimmed
function Badge.Aim(held)
	local b = Badge.big
	if not (b and b.running) then
		return
	end
	if held then
		Anim:Stop(b, "drive")
		b.motion = "hold"
		Badge.Step(b, 0)
	else
		b.motion = "aim"
		Anim:Drive(b, Badge.Step, T.aim, "linear")
	end
end

-- a badge's swing long past (no next one): put away
function Badge.Away(b)
	b.running, b.windAt, b.motion = false, nil, nil
	Anim:Stop(b, "drive")
	Badge.Rest(b)
	Anim:FadeOut(b, 0.25)
end

local function Spring(t, amp, k, w)
	return amp * math.exp(-k * t) * math.cos(w * t)
end

-- one frame of a badge's motion (Anim:Drive's step; `share` of its time). Turns are toward the bar positive (the
-- bar on the badge's left turns it counter-clockwise), offsets in the badge's units
function Badge.Step(b, share)
	local motion, dir, d = b.motion, b.dir or -1, b.d
	local outCubic = Anim.easing.outCubic
	local rot, dx, dy, scale, tint = 0, 0, 0, 1, nil
	local glowA, glowCol, glowK = 0, SB.GOLD, 2.4
	local burstA, burstK, wordA, wordY, raysTurn = 0, 1, 0, 0, 0
	local flashA, flashCol, streakA, streakV, tracerA, tracerX = 0, nil, 0, 0, 0, 0
	local ticksA, ticksD, motesA, motesR = 0, 0, 0, 0
	if motion == "windup" then
		local w = share * share
		if b.kind == "stab" then
			dx = -dir * 3 * w
		else
			rot = -0.5 * w
		end
		scale, glowA = 1 + 0.08 * w, 0.32 * w
	elseif motion == "motes" then
		motesA, motesR, glowA, glowCol = 0.8 * share, d * (0.78 - 0.2 * share), 0.25 * share, SB.ARCANE
	elseif motion == "aim" or motion == "hold" then
		local held = motion == "hold"
		local close = held and 0 or outCubic(share)
		ticksA, ticksD = held and 0.45 or 0.95, d * (1.15 - 0.5 * close)
		glowA, glowCol = held and 0.15 or 0.3 + 0.35 * close, MelloUI.Meaning.swingAim
		tint, scale, rot = MelloUI.Meaning.swingAim, 1.06, -0.1
	elseif motion == "strike" then
		if share >= 1 then
			b.motion = nil
			Badge.Rest(b)
			return
		end
		local L = share * T.strike
		local out = b.outcome
		local crit, avoided = out == "crit", SB.WORD[out] ~= nil
		if b.kind == "chop" then
			if L < 0.07 then
				rot = -0.5 + 1.1 * outCubic(L / 0.07)
			else
				rot = avoided and Spring(L - 0.07, -0.7, 7, 15) or Spring(L - 0.07, 0.6, 8, 16)
			end
		elseif b.kind == "stab" then
			if L < 0.06 then
				dx = dir * 6 * outCubic(L / 0.06)
			else
				dx = avoided and Spring(L - 0.06, -dir * 5, 9, 18) or Spring(L - 0.06, dir * 6, 10, 14)
			end
		elseif b.kind == "shot" then
			dx = -dir * 5 * math.exp(-9 * L) * math.min(1, L / 0.04)
		end
		scale = 1 + (crit and 0.5 or avoided and 0.12 or 0.3) * math.exp(-9 * L) * math.min(1, L / 0.05)
		if crit and L < 0.25 then
			local k = 1 - L / 0.25
			dx, dy = dx + math.sin(L * 120) * 1.6 * k, math.cos(L * 97) * 1.3 * k
		end
		if avoided then
			glowA, glowCol, glowK = 0.9 * (1 - share), SB.STEEL, 1.6
			tint = L < 0.3 and SB.STEEL or nil
			wordA, wordY = 1 - share, 10 * share
		else
			glowA, glowCol = (crit and 0.8 or 0.5) * (1 - share), crit and SB.GOLD or MelloUI.Meaning.swingMelee
			glowK = crit and 3.2 or 2.4
			-- (the sun rays sparking from the weapon's middle: in at once, out as they spread)
			local life = crit and T.raysCrit or T.rays
			if L < life then
				local q = L / life
				burstA = (crit and T.raysCritA or T.raysA) * math.min(1, L / 0.03) * (1 - q) ^ 1.5
				burstK = T.raysFrom + ((crit and T.raysCritTo or T.raysTo) - T.raysFrom) * outCubic(q)
				raysTurn = (b.raysAt or 0) + 0.25 * q
			end
			if b.bar then
				local travel = (b.kind == "wand" and 0.14) or (b.kind == "shot" and 0.06) or 0
				if L < travel then
					tracerA, tracerX = 1, -d * 1.3 * (L / travel)
				else
					local t2 = L - travel
					flashA = (crit and 0.6 or 0.35) * (1 - math.min(1, t2 / 0.35)) ^ 2
					flashCol = crit and SB.GOLD or nil
					if travel == 0 and t2 < 0.16 then
						streakA, streakV = 0.95, outCubic(t2 / 0.16)
					end
				end
			end
		end
	end
	-- the weapon
	local ring, icon = b.ring, b.ring.icon
	icon:SetRotation(-dir * rot)
	if tint then
		icon:SetVertexColor(1, 0.55 + 0.45 * tint[2], 0.55 + 0.45 * tint[3])
	else
		local c = Base(b)
		icon:SetVertexColor(c[1], c[2], c[3])
	end
	ring:SetScale(scale)
	W.RoundIconRefit(ring)   -- (its ring sharp at every step of the strike)
	ring:SetPoint("CENTER", b, "CENTER", dx / scale, dy / scale)
	-- the lights
	b.glow:SetVertexColor(glowCol[1], glowCol[2], glowCol[3])
	b.glow:SetSize(d * glowK, d * glowK)
	b.glow:SetAlpha(glowA)
	b.burst:SetSize(d * burstK, d * burstK)
	b.burst:SetRotation(raysTurn)
	b.burst:SetAlpha(burstA)
	b.word:SetAlpha(wordA)
	if wordA > 0 then
		b.word:SetPoint("BOTTOM", b, "TOP", 0, 2 + wordY)
	end
	for i, t in ipairs(b.ticks) do
		t:SetAlpha(ticksA)
		if ticksA > 0 then
			local an = (i - 0.5) * math.pi / 2
			t:SetPoint("CENTER", b, "CENTER", math.cos(an) * ticksD, math.sin(an) * ticksD)
		end
	end
	local now = GetTime()
	for i, m in ipairs(b.motes) do
		m:SetAlpha(motesA)
		if motesA > 0 then
			local an = now * (3 + 9 * share) + i * 2.094
			m:SetPoint("CENTER", b, "CENTER", math.cos(an) * motesR, math.sin(an) * motesR)
		end
	end
	local fc = flashCol or MelloUI.Meaning.swingMelee
	b.flash:SetVertexColor(fc[1], fc[2], fc[3])
	b.flash:SetAlpha(flashA)
	b.streak:SetAlpha(streakA)
	b.streak:SetValue(streakV)
	b.tracer:SetAlpha(tracerA)
	if tracerA > 0 then
		b.tracer:SetPoint("CENTER", b, "LEFT", tracerX, 0)
	end
end

--------------------------------------------------------------------------------
-- Swings and shots
--------------------------------------------------------------------------------

-- a badge whose swing is long past: put away
function Swing.Idle()
	local now = GetTime()
	for _, b in ipairs(Badge.list) do
		if b.running and now + 0.01 >= Swing.due[b.hand] then
			Badge.Away(b)
		end
	end
end

-- whether a hand's swing shows: a host in charge, and its wish
local function Shows(hand)
	local host = SB.Active()
	return host ~= nil and (host.Wants == nil or host.Wants(hand) ~= false)
end

-- a swing of `hand` ("main" / "off") due in `seconds`: the one before landed
function SB.Start(hand, seconds)
	if not (seconds and seconds > 0) or not Shows(hand) then
		return
	end
	Badge.Run(hand, seconds)
	Badge.Swung(hand)   -- (after the run: a fight's first swing is a blow too)
	Swing.due[hand] = GetTime() + seconds + T.swingGrace
	C_Timer.After(seconds + T.swingGrace, Swing.Idle)
end

-- the aim: run now, or held while moving
function Ranged.Aim()
	if not (Badge.big and Badge.big.running and Badge.big.hand == "ranged") then
		return
	end
	if Ranged.moving then
		Ranged.stage = "hold"
		Swing.due.ranged = math.huge   -- (held for as long as it takes)
		Badge.Aim(true)
	else
		Ranged.stage = "aim"
		Swing.due.ranged = GetTime() + T.aim + T.swingGrace
		C_Timer.After(T.aim + T.swingGrace, Swing.Idle)
		Badge.Aim(false)
	end
end

-- the reload's end (C_Timer.After): the aim, unless a later shot moved it
function Ranged.Due()
	if Ranged.stage == "reload" and GetTime() + 0.01 >= Ranged.aimAt then
		Ranged.Aim()
	end
end

-- a shot fired (the one before landed), the next one due in `seconds`: the reload (a wand's whole run), then the aim
function SB.Shot(seconds)
	if not (seconds and seconds > 0) or not Shows("ranged") then
		return
	end
	-- (a shot strikes as it is fired: the arrow is on its way; its report comes as it hits, the outcome then)
	local b, p = Badge.big, Badge.pending
	if b and b.running and b.hand == "ranged" then
		local what = (p.at and GetTime() - p.at <= T.outcomeWindow) and p.what or nil
		p.at = nil
		Badge.Land(b, what)
	end
	Badge.Run("ranged", seconds)
	local reload = Ranged.wand and seconds or (seconds - T.aim)
	Ranged.stage = Ranged.wand and "wand" or "reload"
	Ranged.aimAt = GetTime() + math.max(reload, 0)
	Swing.due.ranged = GetTime() + seconds + T.swingGrace
	C_Timer.After(seconds + T.swingGrace, Swing.Idle)
	if reload > 0 then
		if not Ranged.wand then
			C_Timer.After(reload, Ranged.Due)
		end
	else
		Ranged.Aim()
	end
end

-- started or stopped moving: the aim held, or run again
function Ranged.Moving(moving)
	Ranged.moving = moving
	if (moving and Ranged.stage == "aim") or (not moving and Ranged.stage == "hold") then
		Ranged.Aim()
	end
end

-- Auto Shot stopped: no shot on its way
function Ranged.Stop()
	Ranged.stage = nil
	local b = Badge.big
	if b and b.running and b.hand == "ranged" then
		Badge.Away(b)
	end
end

-- PLAYER_SWING (the client's own swing timer: seconds, the swing type -- 0 main hand, 1 off hand, 2 ranged)
function SB.Event(seconds, swingType)
	seconds = Num(seconds)
	if Secret(swingType) or not seconds then
		return
	end
	if swingType == 2 then
		SB.Shot(seconds)
	else
		SB.Start(swingType == 1 and "off" or "main", seconds)
	end
end

-- every badge put away at once
function SB.Off()
	Ranged.stage = nil
	Badge.pending.at = nil
	for _, b in ipairs(Badge.list) do
		b.running, b.windAt, b.motion, b.swungAt = false, nil, nil, nil
		Anim:Stop(b, "drive")
		Anim:Stop(b, "alpha")
		Badge.Rest(b)
		b:Hide()
	end
end

--------------------------------------------------------------------------------
-- Range (the game's own check: C_SwingTimer, PLAYER_SWING_RANGE_UPDATE)
--------------------------------------------------------------------------------

-- a hand out of range or back: its badge's weapon tinted (at rest; a motion under way paints it each frame)
local function Range(swingType, out)
	local hand = SB.HAND[swingType]
	if not hand then
		return
	end
	out = out and true or false
	if SB.out[hand] == out then
		return
	end
	SB.out[hand] = out
	for _, b in ipairs(Badge.list) do
		if b.hand == hand and not b.motion then
			local c = Base(b)
			b.ring.icon:SetVertexColor(c[1], c[2], c[3])
		end
	end
end

-- the range checks on (a host in use: a moment after the game's own timers let theirs go) or off
function SB.RangeChecks(on)
	local api = _G.C_SwingTimer
	if not (api and api.EnableRangeCheck) then
		return
	end
	for swingType in pairs(SB.HAND) do
		pcall(api.EnableRangeCheck, swingType, on and true or false)
	end
end

local function RangeLater()
	if SB.Active() then
		SB.RangeChecks(true)
	end
end

-- the target changed: each hand's range asked again
local function TargetRange()
	local api = _G.C_SwingTimer
	if not (api and api.IsTargetWithinSwingRange) then
		return
	end
	for swingType in pairs(SB.HAND) do
		local ok, inRange = pcall(api.IsTargetWithinSwingRange, swingType)
		Range(swingType, ok and not Secret(inRange) and inRange == false)
	end
end

--------------------------------------------------------------------------------
-- Events: while a host is in use
--------------------------------------------------------------------------------

local function Quiet()
	local host = SB.Active()
	return host ~= nil and host.Quiet ~= nil and host.Quiet() == true
end

local OnEvent = Perf.Shared("OnEvent of the swing badge", function(_, event, a1, a2, a3)
	if event == "PLAYER_SWING" then
		if not Quiet() then
			SB.Event(a1, a2)
		end
	elseif event == "UNIT_COMBAT" then
		-- (a blow on your target: the swing's outcome)
		if not Secret(a1) and a1 == "target" then
			SB.Outcome(a2, a3)
		end
	elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
		Ranged.Moving(event == "PLAYER_STARTED_MOVING")
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		if not Quiet() then
			Ranged.Stop()
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		Ranged.wand = MelloUI.Safe.RangedIsWand() == true
	elseif event == "PLAYER_SWING_RANGE_UPDATE" then
		-- (swingType, isInRange, checksRange)
		if not Secret(a1) and not Secret(a2) and not Secret(a3) then
			Range(a1, a3 and not a2)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		TargetRange()
		SB.Lay()   -- (the badge onto your new target's plate, or at the host's place)
	elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		SB.Lay()
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(0.5, RangeLater)
	end
end, "event")

local EVENTS = { "PLAYER_SWING", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "STOP_AUTOREPEAT_SPELL",
	"PLAYER_EQUIPMENT_CHANGED", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED",
	"NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD" }

-- the events while a host is in use (the frame made with the first host)
local function Events()
	local on = SB.Active() ~= nil
	local f = SB.frame
	if not f then
		if not on then
			return
		end
		f = CreateFrame("Frame")
		Perf.SetScript(f, "OnEvent", OnEvent)
		SB.frame = f
	end
	f:UnregisterAllEvents()
	if not on then
		return
	end
	for _, event in ipairs(EVENTS) do
		pcall(f.RegisterEvent, f, event)
	end
	-- (the blows on your target)
	pcall(f.RegisterUnitEvent, f, "UNIT_COMBAT", "target")
	Ranged.wand = MelloUI.Safe.RangedIsWand() == true
	local okM, moving = pcall(_G.IsPlayerMoving)
	Ranged.moving = okM and not Secret(moving) and moving == true or false
end

-- a host in use: the events listened to, the badges laid at the one in charge (and its word's font)
function SB:Use(host)
	if type(host) ~= "table" or not host.key then
		return
	end
	local was = SB.Active()
	self.hosts[host.key] = host
	Events()
	if not was then
		C_Timer.After(0.5, RangeLater)
	end
	for _, b in ipairs(Badge.list) do
		StyleWord(b)
	end
	SB.Lay()
end

-- a host no longer in use: the badges at the next one in charge, or put away (the events let go with the last)
function SB:Drop(host)
	local key = type(host) == "table" and host.key or host
	if not self.hosts[key] then
		return
	end
	self.hosts[key] = nil
	if SB.Active() then
		for _, b in ipairs(Badge.list) do
			StyleWord(b)
		end
		SB.Lay()
	else
		SB.Off()
		SB.RangeChecks(false)
	end
	Events()
end
