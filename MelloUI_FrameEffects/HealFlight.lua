--------------------------------------------------------------------------------
-- MelloUI - Heal Flight (0.20.0; docs/plans/heal-flight.md)
--
-- The user, 2026-10-09: "a healing animation when im casting a heal onto the
-- party/raid unitframes, to have a healing looking sfx gathering onto my
-- castbar and traveling to the targeted unitframe" (picked: all three looks of
-- the sketch, MelloUI-BuildData/output/heal_flight_sketch). While you cast a
-- heal on someone in your group, light gathers on your cast bar; when the cast
-- ends it flies to their party or raid frame (MelloUI's own Group Frames, or
-- the game's), lands with a burst and fades. Screen only: the game plays its
-- own spell on your character.
--
-- Who the heal goes to (Forever may keep it secret in a fight: the probe,
-- /melloheal, measures each way): the target's name UNIT_SPELLCAST_SENT gives,
-- when plain and a member's (as it is, or before its "-Realm"); else the unit frame under
-- the mouse as you cast (a mouseover heal); else the member that is your
-- target (UnitIsUnit); else the frame whose click set your target; else, with
-- no friend targeted, you (the game's self-cast). While the
-- light flies, the first HEAL UNIT_COMBAT reports on a member within 0.2 s
-- turns it there (not when the name told us). Nothing secret is compared.
-- Each spell's kind comes from the client's own spell data (HealFlightSpells.lua,
-- Tools/heal_flight_spells.py; the user, 2026-10-09): a heal, a heal over time, a
-- shield, protection, a heal to full, a resurrection, a group or chain heal; a
-- buff or anything else: nothing. A cast charges on the cast bar and flies; an
-- instant lands on the frame at once (the user: "why not just give it special
-- animation on the targets unitframe?"). A group heal reaches your party (your
-- group in a raid), Chain Heal hops to whom the game reports it healed.
-- Nothing at login: the layers and their sprites are made on the first heal;
-- the events are listened to while the module is on. Reduce Motion: nothing.
-- The engine and the looks: MelloUI.FrameFX (Core/FrameFX.lua).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_FrameEffects (Heal Flight)")
local Safe = MelloUI.Safe
local Secret, Text, Num = Safe.IsSecret, Safe.Text, Safe.Number
local Anim = MelloUI.Anim
local Looks = MelloUI.FrameFX

local LAND_WINDOW = 0.2   -- s after a cast's end: a HEAL on a member there turns the light to it
local SENT_MAX = 1        -- s from a cast's SENT to its START
local CAST_MAX = 15       -- s from a cast's SENT to its end
local WATCH_AFTER = 0.25  -- s past a cast's end before its charge is looked at (its end's events come first)
local HOP_WINDOW = 1.0    -- s after a Chain Heal's end: its hops, as the game reports them
local SHOWCASE = { "o", "t", "s", "p", "b", "r", "u" }   -- Every Kind's order (1.2.4: u a buff's landing)
local SHOW_GAP = 1.9      -- s between them
local ICON = { fallback = 16, min = 12, max = 28 }
local PREVIEW_CAST = 1.2

local TEXT = {
	noBar = "Heal Effects: your cast bar has no place on the screen yet (cast something once).",
	noFrame = "Heal Effects: no party or raid frame of yours is shown.",
	reduceMotion = "Heal Effects: Reduce Motion is on, so nothing flies.",
	off = "Heal Effects are off.",
	noEffects = "Frame Effects is not loaded (it is turned off in AddOns).",
	usage = "/mellofx: every heal kind on your frame. /mellofx heal: a heal from your cast bar to your frame. "
		.. "/mellofx fx: every Frame Effect. /mellofx stop: clears them.",
	kinds = { o = "Heal over time", t = "A heal over time's tick", s = "Shield", p = "Protection", b = "Heal to full",
		r = "Resurrection", u = "A buff (Power Word: Fortitude)" },
}

local LOOK_VALUES = {
	{ value = "class", label = "By Class: Holy, Nature or Water" },
	{ value = "holy", label = "Holy: a gold comet" },
	{ value = "nature", label = "Nature: ribbons and leaves" },
	{ value = "water", label = "Water: a stream and a splash" },
	{ value = "quiet", label = "Quiet: a thread of light" },
}
-- By Class (the user, 2026-10-09): each healing class its own; anyone else Holy
local CLASS_LOOK = { PRIEST = "holy", PALADIN = "holy", DRUID = "nature", SHAMAN = "water" }

local M   -- (the module, registered below)
local P = {
	members = {}, set = {},   -- your group's units now (reused)
	click = nil,              -- the member whose frame's click set your target
	cast = {},                -- the cast in hand: t, guid, spell, unit, by, helpful, charging, done
	prev = {},                -- the cast still on the bar when a queued one is sent (spam: its end still known)
	watchAt = 0,              -- when the charge is looked at next (Watch: it never outlives the cast bar)
	watchStart = nil,         -- the start of the charge Watch looks after (another charge -- the Preview's -- is not its)
	landT = nil, landBy = nil, pending = false,   -- the window after a cast's end
	flying = nil,             -- the landing layer in the air
	kind = nil, fromX = nil, fromY = nil,   -- the last cast's kind and where its light started
	landed = {}, hops = {}, hopFrom = nil,  -- whom it reached; Chain Heal's hops still to fly
	group = {}, show = 0, due = 0,   -- a group heal's units (reused); Every Kind's step, its next one's time
	spell = nil,              -- the last cast's spell (its ticks, when it heals over time)
	ticking = {}, spare = {}, -- your heals over time still ticking (their tables reused)
	buffRead = nil,           -- (Buff Landings) when the group was last read for a landing
	casterAt = nil, caster = nil, casterFrame = nil,   -- (Buff Landings) a wave's caster's frame, read once a moment
}
local chargeLayer
local KINDS = ns.SpellKinds or {}
local TICKS = ns.SpellTicks or {}
local ticker   -- a frame of ours the ticks' Drive runs on (made with the host)

--------------------------------------------------------------------------------
-- The frames and the group: the shared engine's (MelloUI.FrameFX)
--------------------------------------------------------------------------------

local Ask, Visible, Rect, Canon, FrameUnit, FrameOf = Looks.Ask, Looks.Visible, Looks.Rect, Looks.Canon,
	Looks.FrameUnit, Looks.FrameOf

-- your group's units now (you alone while solo), kept in P for the window after a cast
local function Members()
	local list, set = Looks.Members()
	P.members, P.set = list, set
	return list
end

-- the unit of the frame under the mouse (or of a parent of it)
local function MouseUnit()
	local f
	if GetMouseFoci then
		local ok, list = pcall(GetMouseFoci)
		f = ok and type(list) == "table" and list[1] or nil
	elseif GetMouseFocus then
		local ok, focus = pcall(GetMouseFocus)
		f = ok and focus or nil
	end
	for _ = 1, 3 do
		if type(f) ~= "table" or (f.IsForbidden and f:IsForbidden()) then
			return nil
		end
		local unit = FrameUnit(f)
		if unit then
			return Canon(unit)
		end
		f = f.GetParent and f:GetParent() or nil
	end
	return nil
end

--------------------------------------------------------------------------------
-- Who a cast goes to
--------------------------------------------------------------------------------

-- the member the sent name is: as it is, with the member's realm, or the part
-- before a "-Realm" or " Realm" (the probe, 2026-10-09: a self-heal's plain
-- name that matched nobody); nil when it matches nobody -- then the other ways
-- decide (the name is not always the one healed)
local function ByName(target, members)
	if Secret(target) then
		return nil
	end
	target = Text(target)
	if not target or target == "" then
		return nil
	end
	-- (this client sends "Name Realm", a space between: the probe, 2026-10-09,
	-- "Fairyelf Mello" for Fairyelf of Mello; a player's name has neither)
	local base = target:match("^([^%-%s]+)[%-%s]") or target
	for _, unit in ipairs(members) do
		local ok, name, realm = pcall(UnitName, unit)
		if ok and not Secret(name) and not Secret(realm) and type(name) == "string" then
			if target == name or base == name or (type(realm) == "string" and realm ~= ""
				and (target == name .. "-" .. realm or target == name .. " " .. realm)) then
				return unit, "name"
			end
		end
	end
	return nil
end

local function Resolve(target)
	local members = Members()
	local unit, by = ByName(target, members)
	if unit then
		return unit, by
	end
	unit = MouseUnit()
	if unit and P.set[unit] then
		return unit, "frame"
	end
	for _, u in ipairs(members) do
		if Ask(UnitIsUnit, "target", u) then
			return u, "target"
		end
	end
	if P.click and P.set[P.click] then
		return P.click, "click"
	end
	-- (no friend targeted: the game casts the heal on you, its own self-cast
	-- rule; the user, 2026-10-09: "when i healed myself again on full HP ...
	-- not the small glow landing on the unitframe")
	local exists = Ask(UnitExists, "target")
	if exists == false or (exists and Ask(UnitCanAssist, "player", "target") == false) then
		return Canon("player"), "self"
	end
	return nil
end

-- true unless both GUIDs are plain and differ
local function Same(kept, guid)
	guid = Text(guid)
	return not (kept and guid and kept ~= guid)
end

-- whether the spell helps (nil: not known, its ID secret)
local function Helpful(spellID)
	local api = rawget(_G, "C_Spell")
	if not (Num(spellID) and api) then
		return nil
	end
	return Ask(api.IsSpellHelpful, spellID)
end

local function CastTime(spellID)
	local ok, _, _, _, startMs, endMs = pcall(UnitCastingInfo, "player")
	startMs, endMs = ok and Num(startMs), ok and Num(endMs)
	if startMs and endMs and endMs > startMs then
		return (endMs - startMs) / 1000
	end
	local api = rawget(_G, "C_Spell")
	if Num(spellID) and api and api.GetSpellInfo then
		local okI, info = pcall(api.GetSpellInfo, spellID)
		local ms = okI and type(info) == "table" and Num(info.castTime)
		if ms and ms > 0 then
			return ms / 1000
		end
	end
	return 1.5
end

-- still casting (UnitCastingInfo hands something back, secret or not)
local function Count(ok, ...)
	return ok and select("#", ...) > 0
end

local function Casting()
	return Count(pcall(UnitCastingInfo, "player"))
end

--------------------------------------------------------------------------------
-- The stages
--------------------------------------------------------------------------------

-- the charge's layer and the ticks' frame, on the engine's host (made on the first heal)
local function Host()
	if chargeLayer then
		return
	end
	chargeLayer = Looks.Layer(Looks.Host())
	ticker = CreateFrame("Frame", nil, Looks.Host())
end

local FreeLayer = Looks.FreeLayer

-- the cast bar shown: the one on the player frame when it is, else the free one
local function CastBar()
	local overlay = rawget(_G, "OverlayPlayerCastingBarFrame")
	if type(overlay) == "table" and Visible(overlay) then
		return overlay
	end
	return rawget(_G, "PlayerCastingBarFrame")
end

-- the charge's place: the bar, its spell icon (else the bar's left end), the
-- game's fill (the light anchored to it: nothing read); (0.21.0) another
-- place first when one is given (Looks.SetChargePlace: the Personal Display's,
-- at your character's middle)
local function BarPlace(S)
	local place = Looks.chargePlace
	if place and place(S) then
		return true
	end
	local bar = CastBar()
	if type(bar) ~= "table" then
		return false
	end
	local bl, bb, br, bt = Rect(bar)
	if not bl then
		return false
	end
	S.bl, S.bb, S.br, S.bt = bl, bb, br, bt
	local icon = rawget(bar, "Icon")
	local il, ib, ir, it
	if type(icon) == "table" and Visible(icon) then
		il, ib, ir, it = Rect(icon)
	end
	if il and ir > il then
		S.ix, S.iy, S.isz = (il + ir) / 2, (ib + it) / 2, it - ib
	else
		S.ix, S.iy, S.isz = bl, (bb + bt) / 2, ICON.fallback
	end
	S.isz = math.max(ICON.min, math.min(ICON.max, S.isz))
	local fill = Safe.Call(bar, "GetStatusBarTexture")
	S.fill = type(fill) == "table" and fill or nil
	return true
end

-- (one look C13, the user's yes to the audit's drops: Landing In A Raid gone
-- -- a heal lands quietly in a raid, where the frames sit close: MelloUI's
-- choice, today's default)
local function Quiet()
	return Ask(IsInRaid) == true
end

-- the look in use: the chosen one, or By Class's for your class
local function LookName()
	local look = M.db.look
	if look ~= "class" then
		return look
	end
	local ok, _, token = pcall(UnitClass, "player")
	token = ok and Text(token)
	return token and CLASS_LOOK[token] or "holy"
end

-- the light to the unit's frame: flown from (fromX, fromY) -- the charge's
-- icon, or the frame a Chain Heal hops from -- or, with no `fromX`, landing
-- at once (an instant); the layer, or nil (no frame of theirs shown)
local function Shoot(unit, kind, fromX, fromY, hop)
	local frame = FrameOf(unit)
	local l, b, r, t
	if frame then
		l, b, r, t = Rect(frame)
	end
	if not l then
		return nil
	end
	Host()
	local layer = FreeLayer()
	local S = Looks.state[layer]
	S.fl, S.fb, S.fr, S.ft = l, b, r, t
	S.frame, S.Rect, S.unit = frame, Rect, unit
	P.landed[unit] = true
	if fromX then
		S.x0, S.y0 = fromX, fromY
		S.x1, S.y1 = (l + r) / 2, (b + t) / 2
		S.isz = Looks.state[chargeLayer].isz or ICON.fallback
		Looks.Land(layer, LookName(), kind, Quiet(), hop)
		P.flying = layer
	else
		Looks.Strike(layer, LookName(), kind, Quiet())
	end
	return layer
end

--------------------------------------------------------------------------------
-- The ticks: while a heal over time of yours runs, a small pulse on its frame
-- at each tick, timed from the game's spell data (HealFlightSpells.lua: its
-- period and length; the user, 2026-10-09: "Heal over Time Ticks effect").
-- Yours only (the ones you cast); the same spell again on the same one starts
-- its ticks again. One Drive on the ticker steps them while any runs.
--------------------------------------------------------------------------------

local Rearm

local function TickStep()
	local now = GetTime()
	local list = P.ticking
	for i = #list, 1, -1 do
		local h = list[i]
		if now >= h.next then
			h.left = h.left - 1
			h.next = h.next + h.period
			if Ask(UnitIsDeadOrGhost, h.unit) then
				h.left = 0
			else
				Shoot(h.unit, "t")
			end
		end
		if h.left <= 0 then
			table.remove(list, i)
			P.spare[#P.spare + 1] = h
		end
	end
end

local function TickEnd()
	if #P.ticking > 0 and not Anim.reduceMotion then
		Rearm()
	else
		for i = #P.ticking, 1, -1 do
			P.spare[#P.spare + 1] = table.remove(P.ticking, i)
		end
	end
end

-- the Drive again, to the last tick due
Rearm = function()
	local last = GetTime()
	for _, h in ipairs(P.ticking) do
		last = math.max(last, h.next + (h.left - 1) * h.period)
	end
	Anim:Drive(ticker, TickStep, last - GetTime() + 0.2, "linear", TickEnd)
end

local function StartTicks(unit, spellID)
	local data = spellID and TICKS[spellID]
	if not (data and unit and M.db.hotTicks) or Anim.reduceMotion then
		return
	end
	Host()
	local period, count = data[1], math.floor(data[2] / data[1] + 0.001)
	local h
	for _, e in ipairs(P.ticking) do
		if e.unit == unit and e.spell == spellID then
			h = e
			break
		end
	end
	if not h then
		h = table.remove(P.spare) or {}
		P.ticking[#P.ticking + 1] = h
	end
	h.unit, h.spell, h.period, h.next, h.left = unit, spellID, period, GetTime() + period, count
	Rearm()
end

local function StopTicks()
	for i = #P.ticking, 1, -1 do
		P.spare[#P.spare + 1] = table.remove(P.ticking, i)
	end
	if ticker then
		Anim:Stop(ticker, "drive")
	end
end

-- the light in the air turned to another member's frame
local function Retarget(unit)
	local layer = P.flying
	local S = layer and Looks.state[layer]
	if not (S and S.stage == "launch") or S.unit == unit then
		return
	end
	local frame = FrameOf(unit)
	local l, b, r, t
	if frame then
		l, b, r, t = Rect(frame)
	end
	if l then
		S.x1, S.y1 = (l + r) / 2, (b + t) / 2
		S.fl, S.fb, S.fr, S.ft = l, b, r, t
		S.frame, S.unit = frame, unit
	end
end

-- who a group heal reaches: your party; in a raid, your own group of it (by
-- the roster's subgroups; you alone when the roster cannot say)
local function Group()
	local list = P.group
	wipe(list)
	local members = Members()
	if not Ask(IsInRaid) then
		for _, unit in ipairs(members) do
			list[#list + 1] = unit
		end
		return list
	end
	local roster = rawget(_G, "GetRaidRosterInfo")
	local okN, me = pcall(UnitName, "player")
	me = okN and Text(me)
	local mine
	if type(roster) == "function" and me then
		for i = 1, #members do
			local ok, name, _, sub = pcall(roster, i)
			if ok and Text(name) == me then
				mine = Num(sub)
				break
			end
		end
		for i = 1, #members do
			local ok, _, _, sub = pcall(roster, i)
			if ok and mine and Num(sub) == mine then
				list[#list + 1] = "raid" .. i
			end
		end
	end
	if #list == 0 then
		list[1] = Canon("player")
	end
	return list
end

-- Chain Heal's hops, one after another from the frame it last reached (the
-- first when its light has landed); a shared function, the queue in P.hops
local function NextHop()
	local unit = table.remove(P.hops, 1)
	if not unit then
		return
	end
	local from = P.hopFrom and FrameOf(P.hopFrom)
	local l, b, r, t
	if from then
		l, b, r, t = Rect(from)
	end
	if l and M.db.flight then
		Shoot(unit, "h", (l + r) / 2, (b + t) / 2, true)
	else
		Shoot(unit, "h")
	end
	P.hopFrom = unit
end

--------------------------------------------------------------------------------
-- The events
--------------------------------------------------------------------------------

-- Spam (the user's report, 2026-10-14: "spamm clicking the heal sometimes lead to the animation playing on loop even
-- tho nothing is casting"): a press in the cast's last moments is queued, and the game sends it (SENT) before the
-- cast on the bar ends. That cast keeps its own record (P.prev), so its end still finds it and stops its charge; and a
-- charge is looked at once its cast bar should be empty (Watch), ending it there whatever events came or did not.
local function Record(castGUID)
	local prev = P.prev
	local guid = Text(castGUID)
	if prev.t and not prev.done and guid and prev.guid == guid then
		return prev
	end
	if Same(P.cast.guid, castGUID) then
		return P.cast
	end
	return nil
end

local function StopCharge()
	P.cast.charging, P.prev.charging = false, false
	if chargeLayer then
		Looks.Stop(chargeLayer)
	end
end

-- the charge looked at (a shared function: its time in P.watchAt; an earlier call finds it not due and returns):
-- still casting, again a moment later; the bar empty, the charge ends
local function Watch()
	local S = chargeLayer and Looks.state[chargeLayer]
	if not (S and S.stage == "charge") or S.start ~= P.watchStart or GetTime() < P.watchAt - 0.01 then
		return
	end
	if Casting() and GetTime() - (S.start or 0) < CAST_MAX then
		P.watchAt = GetTime() + WATCH_AFTER
		C_Timer.After(WATCH_AFTER, Watch)
		return
	end
	StopCharge()
end

local function OnSent(target, castGUID, spellID)
	-- (the cast on the bar keeps its record while a queued one is sent)
	if P.cast.t and P.cast.charging and not P.cast.done then
		P.prev, P.cast = P.cast, P.prev
	end
	local C = P.cast
	C.t, C.guid, C.spell = GetTime(), Text(castGUID), spellID
	C.charging, C.done = false, false
	local id = Num(spellID)
	C.secret = id == nil
	C.kind = id and KINDS[id] or nil
	C.helpful = Helpful(spellID)
	C.unit, C.by = nil, nil
	-- (only a heal's target is looked for: the spell's kind, or its ID secret)
	if C.kind or C.secret then
		C.unit, C.by = Resolve(target)
	end
end

local function OnStart(castGUID)
	local C = P.cast
	if not C.t or GetTime() - C.t > SENT_MAX or C.done or not Same(C.guid, castGUID) then
		return
	end
	-- (a new cast on the bar: the charge is its from here, never an earlier one's)
	P.prev.charging = false
	-- (a heal by the game's spell data; a spell whose ID is secret, unless it
	-- is known to harm; a buff, a harmful spell: nothing)
	if not (C.kind or (C.secret and C.helpful ~= false)) or Anim.reduceMotion then
		return
	end
	Host()
	local S = Looks.state[chargeLayer]
	if not BarPlace(S) then
		return
	end
	S.start, S.castTime = GetTime(), CastTime(C.spell)
	C.charging = true
	Looks.Charge(chargeLayer, LookName())
	P.watchAt, P.watchStart = S.start + S.castTime + WATCH_AFTER, S.start
	C_Timer.After(S.castTime + WATCH_AFTER, Watch)
end

local function OnSucceeded(castGUID)
	local C = Record(castGUID)
	if not C or not C.t or GetTime() - C.t > CAST_MAX or C.done then
		return
	end
	C.done = true
	local charged = C.charging
	if charged then
		StopCharge()
	end
	-- (a cast whose kind is not known -- its ID secret -- lands as a heal; an
	-- instant whose kind is not known: nothing)
	local kind = C.kind or (charged and "h") or nil
	if not kind or Anim.reduceMotion then
		return
	end
	-- (Flying Light off -- the user's players, 2026-10-09: "the option for the
	-- flying particle to be hidden" -- a cast lands at once, as an instant)
	local fromX, fromY
	if charged and M.db.flight then
		local S = Looks.state[chargeLayer]
		fromX, fromY = S.ix, S.iy
	end
	P.landT, P.landBy, P.kind, P.fromX, P.fromY = GetTime(), C.by, kind, fromX, fromY
	P.spell = Num(C.spell)
	P.pending, P.hopFrom, P.flying = false, nil, nil
	wipe(P.landed)
	wipe(P.hops)
	if kind == "g" then
		for _, unit in ipairs(Group()) do
			Shoot(unit, kind, fromX, fromY)
		end
		P.landT = nil
		return
	end
	if C.unit and Shoot(C.unit, kind, fromX, fromY) then
		P.hopFrom = C.unit
		StartTicks(C.unit, P.spell)
	else
		-- (nobody known yet: the first heal on a member, just now, says who)
		P.pending = C.by ~= "name"
	end
end

local function OnStopped(castGUID)
	local C = Record(castGUID)
	if C and C.charging and not C.done and not Casting() then
		StopCharge()
	end
end

-- a heal landing on a member just after a cast of yours ended: who it was
-- for when nothing knew, where the light turns, or Chain Heal's next hop
local function OnCombat(unit, event)
	if not P.landT then
		return
	end
	local chain = P.kind == "c"
	if GetTime() - P.landT > (chain and HOP_WINDOW or LAND_WINDOW) then
		P.landT, P.pending = nil, false
		return
	end
	unit = Canon(Text(unit))
	if not unit or not P.set[unit] or Text(event) ~= "HEAL" then
		return
	end
	if P.pending then
		P.pending = false
		Shoot(unit, P.kind, P.fromX, P.fromY)
		StartTicks(unit, P.spell)
		P.hopFrom = unit
		if not chain then
			P.landT = nil
		end
		return
	end
	if chain then
		if not P.landed[unit] then
			P.landed[unit] = true
			P.hops[#P.hops + 1] = unit
			local due = P.landT + Looks.TIME.launch + (#P.hops - 1) * Looks.TIME.hop
			C_Timer.After(math.max(0, due - GetTime()), NextHop)
		end
		return
	end
	P.landT = nil
	if P.landBy ~= "name" then
		Retarget(unit)
	end
end

-- your target changed: by a click on a member's frame, or by other means
local function OnTarget()
	local unit = MouseUnit()
	P.click = unit
end

--------------------------------------------------------------------------------
-- Buff Landings (1.2.4; the user, 2026-10-30: "the animation for power word
-- Fortitude is not happening", then the picks of the buff landings sketch,
-- BuildData/output/buff_landings_sketch: "B Spiral", by school, anyone's, a
-- quiet glint in a raid, a wave for group forms, nothing for self-only buffs,
-- the target frame too, on by default). A buff is heard where it lands:
-- UNIT_AURA's added auras on your group's units and your target, the spell
-- one of Forever's class buffs (HealFlightSpells.lua's BuffForms, from the
-- client's own spell data), cast by anyone. Nothing for a refresh (the game
-- tells a renewed aura as updated, not added), a full update (a login, a zone,
-- a new target), an aura put on a while ago (a mate coming into sight), a
-- self-only buff, a secret spell or caster. A group form lands as a wave out
-- of its caster's frame; in a raid each frame glints. Its look is the buff's
-- school's, whatever the heals' Look. Reduce Motion: nothing.
--------------------------------------------------------------------------------

local BUFF_FORMS = ns.BuffForms or {}
local BUFF_SCHOOLS = ns.BuffSchools or {}
local BUFF_FRESH = 2      -- s: an aura put on longer ago than this is not landing now
local BUFF_SAME = 0.2     -- s: the same buff told again on the same frame (player and raid3) is one landing
-- By school (the user's pick): holy gold, nature green, arcane blue, shadow violet, physical amber
local SCHOOL_LOOK = { holy = "holy", nature = "nature", arcane = "water", frost = "water", shadow = "shadow",
	physical = "physical", fire = "physical" }
-- the unit tokens a landing is heard on (any other -- a nameplate's, your focus -- passed over at once)
local BUFF_UNITS = { player = true, target = true }
for i = 1, 4 do
	BUFF_UNITS["party" .. i] = true
end
for i = 1, 40 do
	BUFF_UNITS["raid" .. i] = true
end
local buffAt = setmetatable({}, { __mode = "k" })   -- [frame] = when a buff last landed on it
local buffOf = setmetatable({}, { __mode = "k" })   -- [frame] = that buff's spell

-- the frame a group form's wave runs out of: its caster's, by the token the game names, else the member that is the
-- caster (in a raid the game may name a mate of your own group by its party token, which shows no frame there); read
-- once a moment and caster
local function CasterFrame(caster, now)
	if P.casterAt == now and P.caster == caster then
		return P.casterFrame
	end
	local frame = FrameOf(Canon(caster))
	if not frame then
		for _, u in ipairs(P.members) do
			if Ask(UnitIsUnit, caster, u) then
				frame = FrameOf(u)
				break
			end
		end
	end
	P.casterAt, P.caster, P.casterFrame = now, caster, frame
	return frame
end

local function BuffLand(unit, aura, id, form)
	-- (its caster secret: nothing, never hung on a secret; not told -- out of sight -- the landing comes at once)
	local source = aura.sourceUnit
	if Secret(source) then
		return
	end
	-- (put on just now: its start -- its end less its length -- within BUFF_FRESH; times not plain or none: trusted)
	local ends, length = Num(aura.expirationTime), Num(aura.duration)
	if ends and length and ends > 0 and length > 0 and GetTime() - (ends - length) > BUFF_FRESH then
		return
	end
	local frame
	local now = GetTime()
	-- (the group read once a moment: a prayer tells each of the raid's 40 in one)
	if P.buffRead ~= now then
		P.buffRead = now
		Members()
	end
	if unit == "target" then
		frame = Looks.TargetFrame()
	else
		unit = Canon(unit)
		if not P.set[unit] then
			return   -- (another token of a member: party1 in a raid -- its raid unit tells it)
		end
		frame = FrameOf(unit)
	end
	if not frame then
		return
	end
	if buffOf[frame] == id and now - (buffAt[frame] or 0) < BUFF_SAME then
		return
	end
	buffAt[frame], buffOf[frame] = now, id
	-- (a group form, a Greater Blessing: the wave out of its caster's frame)
	local from
	local caster = form ~= "o" and Text(source)
	if caster then
		from = CasterFrame(caster, now)
	end
	Looks.Show(unit, Quiet() and "q" or "u", SCHOOL_LOOK[BUFF_SCHOOLS[id]] or "holy", false, nil, from, frame)
end

-- a table this code may read: a plain one (UNIT_AURA's payload can be secret in a fight, its tables and its
-- isFullUpdate: never tested or indexed then)
local issecrettable, canaccesstable = rawget(_G, "issecrettable"), rawget(_G, "canaccesstable")
local function Readable(t)
	return type(t) == "table" and not Secret(t) and not (issecrettable and issecrettable(t))
		and (not canaccesstable or canaccesstable(t))
end

-- (the unit first: most of the game's UNIT_AURA are the nameplates', passed over before their payload is looked at --
-- the user, 2026-10-30: "attempt to perform boolean test on field 'isFullUpdate' (a secret boolean value ...)" on
-- nameplate2 in a fight; then a change with nothing added)
local function OnAura(unit, info)
	unit = Text(unit)
	if Anim.reduceMotion or not (unit and BUFF_UNITS[unit]) or not Readable(info) then
		return
	end
	local full, added = info.isFullUpdate, info.addedAuras
	if Secret(full) or full or not Readable(added) then
		return
	end
	for i = 1, #added do
		local aura = added[i]
		local id = Readable(aura) and Num(aura.spellId) or nil
		local form = id and BUFF_FORMS[id]
		-- (a self-only buff -- Inner Fire, the armors -- lands on nothing: the user's pick)
		if form and form ~= "s" then
			BuffLand(unit, aura, id, form)
		end
	end
end

local OnEvent = Perf.Shared("Heal Flight's events", function(_, event, unit, a1, a2, a3)
	if event == "UNIT_AURA" then
		OnAura(unit, a1)
	elseif event == "UNIT_SPELLCAST_SENT" then
		OnSent(a1, a2, a3)
	elseif event == "UNIT_SPELLCAST_START" then
		OnStart(a1)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		OnSucceeded(a1)
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		OnStopped(a1)
	elseif event == "UNIT_COMBAT" then
		OnCombat(unit, a1)
	elseif event == "PLAYER_TARGET_CHANGED" then
		OnTarget()
	end
end, "script")

local PLAYER_EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }
local events

local function Listen(on)
	if on and not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", OnEvent)
	end
	if not events then
		return
	end
	events:UnregisterAllEvents()
	if on then
		for _, event in ipairs(PLAYER_EVENTS) do
			events:RegisterUnitEvent(event, "player")
		end
		events:RegisterEvent("UNIT_COMBAT")
		events:RegisterEvent("PLAYER_TARGET_CHANGED")
		-- (Buff Landings: every unit's, the group's and your target's kept -- RegisterUnitEvent takes two units)
		if M.db.buffs then
			events:RegisterEvent("UNIT_AURA")
		end
	end
end

--------------------------------------------------------------------------------
-- The previews: a made-up heal on you, from where your cast bar stands; every
-- kind's landing on your frame, one after another
--------------------------------------------------------------------------------

-- whether a preview can play; your frame then
local function CanPreview()
	if not (M and M.isEnabled) then
		MelloUI:Announce(TEXT.off, "info")
		return nil
	end
	if Anim.reduceMotion then
		MelloUI:Announce(TEXT.reduceMotion, "info")
		return nil
	end
	Members()
	local unit = Canon("player")
	if not FrameOf(unit) then
		MelloUI:Announce(TEXT.noFrame, "info")
		return nil
	end
	Host()
	return unit
end

local function PreviewLand()
	if chargeLayer and Looks.state[chargeLayer].stage == "charge" then
		Looks.Stop(chargeLayer)
		local S = Looks.state[chargeLayer]
		if M.db.flight then
			Shoot(Canon("player"), "h", S.ix, S.iy)
		else
			Shoot(Canon("player"), "h")
		end
	end
end

local function Preview()
	if not CanPreview() then
		return
	end
	local S = Looks.state[chargeLayer]
	if not BarPlace(S) then
		MelloUI:Announce(TEXT.noBar, "info")
		return
	end
	S.start, S.castTime = GetTime(), PREVIEW_CAST
	Looks.Charge(chargeLayer, LookName())
	C_Timer.After(PREVIEW_CAST, PreviewLand)
end

-- (one chain at a time: a step due before the newest one's time is an older
-- chain's, started again since -- it ends there)
local function ShowNext()
	if GetTime() < P.due - 0.05 then
		return
	end
	P.show = P.show + 1
	local kind = SHOWCASE[P.show]
	if not (kind and M.isEnabled) or (kind == "u" and not M.db.buffs) then
		return
	end
	MelloUI:Announce(TEXT.kinds[kind], "info")
	if kind == "u" then
		-- (Buff Landings: Power Word: Fortitude's, in its school's look -- holy -- whatever the heals' Look)
		Looks.Show(Canon("player"), Quiet() and "q" or "u", "holy")
	else
		Shoot(Canon("player"), kind)
	end
	P.due = GetTime() + SHOW_GAP
	C_Timer.After(SHOW_GAP, ShowNext)
end

local function PreviewKinds()
	if not CanPreview() then
		return
	end
	P.show, P.due = 0, 0
	ShowNext()
end

--------------------------------------------------------------------------------
-- The module
--------------------------------------------------------------------------------

M = MelloUI:RegisterModule("HealFlight", {
	title = "Heal Effects",   -- (0.21.0, the user: the page's switch name, every text alike)
	desc = "Your heals shown as light flying from your cast bar to the frame of the one you heal.",
	icon = "Interface\\Icons\\Spell_Holy_Renew",
	flavour = "Your heals fly from your cast bar to the frame of the one you heal.",
	enabledByDefault = true,
	defaults = {
		look = "class",
		flight = true,
		hotTicks = true,
		buffs = true,
	},
	options = {
		{ type = "dropdown", key = "look", name = "Look", width = 240, values = LOOK_VALUES,
		  desc = "How your heals look. By Class: Holy for priests and paladins, Nature for druids, Water for shamans. Quiet: a subtle thread of light." },
		{ type = "toggle", key = "flight", name = "Flying Light",
		  desc = "A light flies from your cast bar to the healed frame. Off: the heal lands at once; the other effects stay." },
		{ type = "toggle", key = "hotTicks", name = "Heal Over Time Ticks",
		  desc = "Each tick of your heals over time plays a small pulse on the frame." },
		{ type = "toggle", key = "buffs", name = "Buff Landings",
		  desc = "A buff landing on your group or your target plays a spiral of light on the frame, in its school's colour "
			.. "(Fortitude, Mark of the Wild, Arcane Intellect, the blessings ...), whoever cast it. A group buff runs "
			.. "out from the caster's frame; in a raid, a small glint. Buffs you can only cast on yourself play nothing." },
		{ type = "button", name = "Preview", text = "Play",
		  hint = "a made-up heal on you",
		  desc = "Plays the chosen heal look once on your own frame.",
		  onClick = function() Preview() end },
		{ type = "button", name = "Every Kind", text = "Play",
		  hint = "each kind's landing on your frame",
		  desc = "Plays each kind of heal landing on your frame: heal over time, shield, protection, full heal, resurrection, a buff.",
		  onClick = function() PreviewKinds() end },
	},
})

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	Listen(true)
end

function M:OnDisable()
	Listen(false)
	StopTicks()
	P.cast.charging, P.landT, P.pending = false, nil, false
	wipe(P.hops)
	if chargeLayer then
		Looks.Stop(chargeLayer)
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "hotTicks" and not value then
		StopTicks()
	elseif key == "buffs" and self.isEnabled then
		Listen(true)
	end
end

M.Preview = Preview
M.PreviewKinds = PreviewKinds

--------------------------------------------------------------------------------
-- /mellofx: the previews by command (the user, 2026-10-09: "i need the
-- /mellofx command to see a preview of that" -- the effects on the normal
-- party frames, the solo one too): every heal kind on your frame; `heal` a
-- whole heal from your cast bar; `fx` Frame Effects' every effect (its own
-- addon: asked for when loaded); `stop` all of them off at once
--------------------------------------------------------------------------------

local function StopPreviews()
	P.show, P.due = #SHOWCASE, 0
	local fe = MelloUI:GetModule("FrameEffects")
	if fe and fe.StopPreview then
		fe.StopPreview()
	end
	if chargeLayer then
		Looks.Stop(chargeLayer)
	end
	Looks.ClearAll()
end

local COMMANDS = {
	[""] = PreviewKinds,
	heal = Preview,
	fx = function()
		local fe = MelloUI:GetModule("FrameEffects")
		if fe and fe.PreviewAll then
			fe.PreviewAll()
		else
			MelloUI:Announce(TEXT.noEffects, "info")
		end
	end,
	stop = StopPreviews,
}

SLASH_MELLOFX1 = "/mellofx"
SlashCmdList.MELLOFX = function(msg)
	local word = (Text(msg) or ""):lower():match("^%s*(%S*)")
	local run = COMMANDS[word]
	if run then
		run()
	else
		MelloUI:Print(TEXT.usage)
	end
end
