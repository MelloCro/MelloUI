--------------------------------------------------------------------------------
-- MelloUI - Heal probe (/melloheal)
--
-- A developer probe for the heal flight (the user, 2026-10-09: "a healing
-- looking sfx gathering onto my castbar and traveling to the targeted
-- unitframe"): what the game tells an addon about who a cast of yours goes
-- to, and when, in a fight and out of one. Forever may hand any of it out as
-- a secret (the client's API docs: UNIT_SPELLCAST_SENT's target name is
-- ConditionalSecret, UnitIsUnit secret while unit comparison is restricted,
-- UnitCastingInfo secret while the spell cast is restricted); nothing secret
-- is compared here, it is noted as "secret".
-- Each cast of yours is noted (the last 12) with every way of finding whom it
-- went to:
--   frame    the unit frame under the mouse as you cast (MelloUI's or the game's)
--   click    the unit frame under the mouse when your target last changed
--            (a click on it; nothing when the target changed by keys or Tab)
--   name     the target's name from UNIT_SPELLCAST_SENT, matched to a member
--   target   UnitIsUnit("target", member)
--   hover    UnitIsUnit("mouseover", member)
--   self     no friend targeted: the game casts the heal on you (its self-cast)
--   landed   UNIT_COMBAT's HEAL on a member within 0.6 s of the cast's end
-- and whether the cast bar and that member's frame can be placed on the
-- screen (their rects plain), the cast's times (UnitCastingInfo), the
-- client's own secrecy predicates (C_Secrets) and which addon restrictions
-- were active (C_RestrictedActions).
--   /melloheal          listen until /melloheal off (made on its first use, never at login)
--   /melloheal fly      listen, and a dot flies from the cast bar to the found
--                       frame at each cast's end (again: the dot off)
--   /melloheal report   the notes and a summary, in chat and the copy window
--   /melloheal off      stop listening (the notes stay for the report)
--   /melloheal clear    forget the notes
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("HealProbe")
local Secret = MelloUI.Safe.IsSecret
local Text = MelloUI.Safe.Text
local Num = MelloUI.Safe.Number
local ScreenRect = MelloUI.Safe.ScreenRect

local P = { on = false, fly = false, n = 0, casts = {}, current = nil, landing = nil, click = nil,
	members = {}, memberSet = {}, combat = {}, cn = 0, others = {}, otherN = 0 }
MelloUI.HealProbe = P   -- (the tests')

local KEEP = 12            -- casts kept for the report
local LAND_WINDOW = 0.6    -- s after a cast's end a HEAL on a member counts as where it landed
local LANDED_MAX = 4       -- landings noted per cast
local CAST_MAX = 15        -- s a cast may run between its SENT and its end
local COMBAT_KEEP = 40     -- UNIT_COMBATs kept (anyone's), for each cast's "round the end"
local AROUND_MAX = 6       -- of them shown per cast
local OTHERS_KEEP = 40     -- your group mates' casts kept
local DOT = { size = 14, flight = 0.3, fade = 0.25 }
local WHITE = "Interface\\Buttons\\WHITE8X8"   -- look-ok: the probe's dot, tinted by palette key
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- look-ok: the dot's round mask
-- (in Heal Flight's order: the first found is the one picked)
local METHODS = { "name", "frame", "target", "click", "hover", "self" }
local OWN_HEADERS = { "MelloUIGroupPartyHeader", "MelloUIGroupRaidHeader" }
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }

local TEXT = {
	on = "Heal probe: listening (the dot %s). Heal your group in and out of a fight, then /melloheal report.",
	off = "Heal probe: stopped (%d casts noted; /melloheal report shows them).",
	cleared = "Heal probe: the notes are gone.",
	usage = "Heal probe: /melloheal [fly | report | off | clear]",
	head = "Heal probe: listening %s, dot %s, Reduce Motion %s, %d casts noted (the last %d, oldest first)",
	none = "  (no casts yet: /melloheal, then cast)",
}

local function Say(fmt, ...)
	MelloUI:Print(fmt, ...)
end

-- a value told back by the game: "secret" for a secret, else as it is
local function Shown(v)
	if Secret(v) then
		return "secret"
	end
	return tostring(v)
end

-- a yes or no from the game: true, false, "secret", "error" or "none" (no such call)
local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return "none"
	end
	local ok, v = pcall(fn, ...)
	if not ok then
		return "error"
	end
	if Secret(v) then
		return "secret"
	end
	return v and true or false
end

local function Visible(f)
	local ok, v = pcall(f.IsVisible, f)
	return ok and not Secret(v) and v == true
end

--------------------------------------------------------------------------------
-- The group, the frames and the mouse
--------------------------------------------------------------------------------

-- your group's unit tokens now (you alone while solo); in a raid "player"
-- joins the set too, for UNIT_COMBAT's sake
local function Members()
	local list, set = P.members, P.memberSet
	wipe(list)
	wipe(set)
	local okR, raid = pcall(IsInRaid)
	if okR and not Secret(raid) and raid then
		local okN, count = pcall(GetNumGroupMembers)
		count = okN and Num(count) or 0
		for i = 1, math.min(count, 40) do
			list[#list + 1] = "raid" .. i
		end
		set.player = true
	else
		list[1] = "player"
		for i = 1, 4 do
			local unit = "party" .. i
			if Ask(UnitExists, unit) == true then
				list[#list + 1] = unit
			end
		end
	end
	for _, unit in ipairs(list) do
		set[unit] = true
	end
	return list
end

-- the unit a frame shows: its secure "unit" attribute, else its unit field
local function FrameUnit(f)
	if type(f) ~= "table" then
		return nil
	end
	local unit
	if f.GetAttribute then
		local ok, v = pcall(f.GetAttribute, f, "unit")
		unit = ok and Text(v) or nil
	end
	return unit or Text(rawget(f, "unit"))
end

local function FrameName(f)
	local ok, name = pcall(f.GetName, f)
	return ok and Text(name) or "(no name)"
end

-- the frame under the mouse and the unit it (or a parent of it) shows
local function MouseUnit()
	local f
	if GetMouseFoci then
		local ok, list = pcall(GetMouseFoci)
		f = ok and type(list) == "table" and list[1] or nil
	elseif GetMouseFocus then
		local ok, focus = pcall(GetMouseFocus)
		f = ok and focus or nil
	end
	local top = f
	for _ = 1, 3 do
		if type(f) ~= "table" or (f.IsForbidden and f:IsForbidden()) then
			break
		end
		local unit = FrameUnit(f)
		if unit then
			return f, unit
		end
		f = f.GetParent and f:GetParent() or nil
	end
	return top, nil
end

local function Shows(f, unit)
	return type(f) == "table" and FrameUnit(f) == unit and Visible(f)
end

-- the unit's frame on the screen and whose it is: MelloUI's group frames
-- first, then the game's party, raid and player frames
local function FrameOf(unit)
	for _, name in ipairs(OWN_HEADERS) do
		local h = rawget(_G, name)
		if type(h) == "table" then
			for i = 1, 41 do
				local b = rawget(h, i)
				if b == nil and h.GetAttribute then
					local ok, v = pcall(h.GetAttribute, h, "child" .. i)
					b = ok and v or nil
				end
				if type(b) ~= "table" then
					break
				end
				if rawget(b, "unit") == unit and Visible(b) then
					return b, "MelloUI's"
				end
			end
		end
	end
	for i = 1, 5 do
		local f = rawget(_G, "CompactPartyFrameMember" .. i)
		if Shows(f, unit) then
			return f, "the game's"
		end
	end
	for i = 1, 40 do
		local f = rawget(_G, "CompactRaidFrame" .. i)
		if Shows(f, unit) then
			return f, "the game's"
		end
	end
	for g = 1, 8 do
		for i = 1, 5 do
			local f = rawget(_G, "CompactRaidGroup" .. g .. "Member" .. i)
			if Shows(f, unit) then
				return f, "the game's"
			end
		end
	end
	local pf = rawget(_G, "PartyFrame")
	if type(pf) == "table" and pf.PartyMemberFramePool then
		for f in pf.PartyMemberFramePool:EnumerateActive() do
			if Shows(f, unit) then
				return f, "the game's"
			end
		end
	end
	local player = rawget(_G, "PlayerFrame")
	if unit == "player" and type(player) == "table" and Visible(player) then
		return player, "the game's player"
	end
	return nil
end

-- the cast bar shown: the one on the player frame (Edit Mode's) when it is,
-- else the free one
local function CastBar()
	local overlay = rawget(_G, "OverlayPlayerCastingBarFrame")
	if type(overlay) == "table" and Visible(overlay) then
		return overlay
	end
	return rawget(_G, "PlayerCastingBarFrame")
end

-- a region's centre in UIParent's units, or nil when its rect is not plain
local function Centre(region)
	local l, b, r, t = ScreenRect(region)
	if not l then
		return nil
	end
	local s = UIParent:GetEffectiveScale()
	return (l + r) / 2 / s, (b + t) / 2 / s
end

--------------------------------------------------------------------------------
-- The dot (/melloheal fly; made on its first flight)
--------------------------------------------------------------------------------

local function Dot()
	if P.dot then
		return P.dot
	end
	local d = CreateFrame("Frame", nil, UIParent)
	d:SetSize(DOT.size, DOT.size)
	d:SetFrameStrata("HIGH")
	local tex = d:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints(d)
	tex:SetTexture(WHITE)
	local W = MelloUI.Widgets
	if W and W.Paint then
		W.Paint(tex, "selectedTrim", "vertex")
	end
	local mask = d:CreateMaskTexture()
	mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(d)
	tex:AddMaskTexture(mask)
	d:Hide()
	P.dot = d
	return d
end

local function Land()
	if P.dot then
		MelloUI.Anim:FadeOut(P.dot, DOT.fade)
	end
end

local function Fly(x0, y0, x1, y1)
	local d = Dot()
	MelloUI.Anim:Stop(d, "alpha")
	d:SetAlpha(1)
	d:Show()
	MelloUI.Anim:Slide(d, "CENTER", UIParent, "BOTTOMLEFT", x0, y0, x1 - x0, y1 - y0, DOT.flight)
	C_Timer.After(DOT.flight, Land)
end

--------------------------------------------------------------------------------
-- The notes: one per cast, the last KEEP kept (their tables reused)
--------------------------------------------------------------------------------

local function NewRecord()
	P.n = P.n + 1
	local i = (P.n - 1) % KEEP + 1
	local rec = P.casts[i]
	if rec then
		wipe(rec.found)
		wipe(rec.why)
		wipe(rec.landed)
	else
		rec = { found = {}, why = {}, landed = {} }
		P.casts[i] = rec
	end
	rec.number, rec.t, rec.clock = P.n, GetTime(), date("%H:%M:%S")
	rec.result, rec.times, rec.castMs, rec.tEnd = "sent", "instant (no cast start)", nil, nil
	rec.pick, rec.pickBy, rec.bar, rec.dest, rec.flight, rec.firstLanded, rec.focus = nil, nil, nil, nil, nil, nil, nil
	return rec
end

-- the addon restrictions active now, joined ("none" when none is)
local function Restricted()
	local api, enum = rawget(_G, "C_RestrictedActions"), rawget(_G, "Enum")
	local fn = api and api.IsAddOnRestrictionActive
	local types = enum and enum.AddOnRestrictionType
	if type(fn) ~= "function" or type(types) ~= "table" then
		return "unknown (no C_RestrictedActions)"
	end
	local out
	for _, key in ipairs(RESTRICTIONS) do
		local value = types[key]
		local a = value ~= nil and Ask(fn, value) or false
		if a == true or a == "secret" then
			out = (out and out .. "+" or "") .. key .. (a == "secret" and "(secret)" or "")
		end
	end
	return out or "none"
end

-- UnitIsUnit(token, member) for every member: the first yes, or why none
local function Compare(rec, key, token, members)
	local secret = 0
	for _, unit in ipairs(members) do
		local a = Ask(UnitIsUnit, token, unit)
		if a == true then
			rec.found[key] = unit
			return
		elseif a == "secret" then
			secret = secret + 1
		end
	end
	rec.why[key] = secret > 0 and ("secret (%d of %d)"):format(secret, #members) or "none"
end

-- the sent name matched to a member's (with or without the realm)
local function MatchName(rec, target, members)
	if Secret(target) then
		rec.why.name = "secret"
		return
	end
	target = Text(target)
	if not target or target == "" then
		rec.why.name = "none (no target name)"
		return
	end
	-- (the name before a "-Realm" or " Realm" too: Heal Flight matches that way;
	-- this client sends "Name Realm")
	local base = target:match("^([^%-%s]+)[%-%s]") or target
	local secret = 0
	for _, unit in ipairs(members) do
		local ok, name, realm = pcall(UnitName, unit)
		if ok and (Secret(name) or Secret(realm)) then
			secret = secret + 1
		elseif ok then
			name, realm = Text(name), Text(realm)
			if name and (target == name or (realm and realm ~= "" and target == name .. "-" .. realm)) then
				rec.found.name = unit
				return
			elseif name and base == name then
				rec.found.name = unit
				rec.nameBase = true
				return
			end
		end
	end
	rec.why.name = secret > 0 and ("no match (%d member names secret)"):format(secret) or "no match (not in your group)"
end

local function SpellText(spellID)
	local id = Num(spellID)
	if not id then
		return Secret(spellID) and "a secret spell" or "spell ?"
	end
	local api = rawget(_G, "C_Spell")
	local ok, name = false, nil
	if api and api.GetSpellName then
		ok, name = pcall(api.GetSpellName, id)
	end
	return ("%s (%d)"):format(ok and Text(name) or "?", id)
end

-- UNIT_SPELLCAST_SENT: a cast of yours leaves; every way of finding its target, now
local function OnSent(target, castGUID, spellID)
	local rec = NewRecord()
	P.current = rec
	local members = Members()
	local secrets = rawget(_G, "C_Secrets") or {}
	rec.fight = InCombatLockdown() and true or false
	rec.restricted = Restricted()
	rec.spell = SpellText(spellID)
	rec.guid = Text(castGUID)
	rec.sentName = Secret(target) and "secret" or (Text(target) and "plain" or "none")
	rec.sentText, rec.you, rec.nameBase = Text(target), nil, nil
	local okY, you, realm = pcall(UnitName, "player")
	you, realm = okY and Text(you), okY and Text(realm)
	if you then
		rec.you = (realm and realm ~= "") and (you .. "-" .. realm) or you
	end
	rec.predCast = "? (the spell ID is secret)"
	if Num(spellID) then
		rec.predCast = Ask(secrets.ShouldUnitSpellCastBeSecret, "player", spellID)
	end
	rec.predCasting = Ask(secrets.ShouldUnitSpellCastingBeSecret, "player")
	rec.predCompare = Ask(secrets.ShouldUnitComparisonBeSecret, "target", members[2] or "player")
	-- frame: what the mouse is on
	local f, unit = MouseUnit()
	if unit and P.memberSet[unit] then
		rec.found.frame = unit
		rec.focus = FrameName(f)
	elseif unit then
		rec.why.frame = unit .. " (not a member's frame)"
	else
		rec.why.frame = f and ("none (on " .. FrameName(f) .. ")") or "none"
	end
	-- click: the frame that set your target
	if P.click and P.memberSet[P.click] then
		rec.found.click = P.click
	else
		rec.why.click = P.click and (P.click .. " (not a member)") or "none (target not set by a frame)"
	end
	MatchName(rec, target, members)
	Compare(rec, "target", "target", members)
	Compare(rec, "hover", "mouseover", members)
	-- self: no friend targeted, so the game casts the heal on you (its self-cast)
	local exists = Ask(UnitExists, "target")
	if exists == false or (exists == true and Ask(UnitCanAssist, "player", "target") == false) then
		rec.found.self = "player"
	else
		rec.why.self = exists == true and "none (a friend targeted)" or "unknown"
	end
end

-- UNIT_SPELLCAST_START: the cast's times
local function OnStart()
	local rec = P.current
	if not rec or GetTime() - rec.t > 1 then
		return
	end
	local ok, _, _, _, startMs, endMs = pcall(UnitCastingInfo, "player")
	if not ok then
		rec.times = "error"
	elseif Secret(startMs) or Secret(endMs) then
		rec.times = "secret"
	elseif Num(startMs) and Num(endMs) then
		rec.times = "plain"
		rec.castMs = endMs - startMs
	else
		rec.times = "none"
	end
end

-- the cast this end belongs to: the current one, when its GUID (both plain) agrees
local function Ending(castGUID)
	local rec = P.current
	if not rec or GetTime() - rec.t > CAST_MAX then
		return nil
	end
	local guid = Text(castGUID)
	if rec.guid and guid and rec.guid ~= guid then
		return nil
	end
	return rec
end

-- UNIT_SPELLCAST_SUCCEEDED: its target picked, both ends placed, the dot flown
local function OnSucceeded(castGUID)
	local rec = Ending(castGUID)
	if not rec or rec.result == "succeeded" then
		return
	end
	rec.result = "succeeded"
	rec.tEnd = GetTime()
	P.landing = rec
	for _, m in ipairs(METHODS) do
		if rec.found[m] then
			rec.pick, rec.pickBy = rec.found[m], m
			break
		end
	end
	local x0, y0 = Centre(CastBar())
	rec.bar = x0 and "placed" or "no plain rect"
	if not rec.pick then
		rec.dest = "no target found"
		return
	end
	local f, whose = FrameOf(rec.pick)
	if not f then
		rec.dest = "no frame shown for " .. rec.pick
		return
	end
	local x1, y1 = Centre(f)
	rec.dest = ("%s frame %s"):format(whose, x1 and "placed" or "with no plain rect")
	if P.fly then
		if x0 and x1 then
			Fly(x0, y0, x1, y1)
			rec.flight = "flew"
		else
			rec.flight = "not flown (an end not placed)"
		end
	end
end

local function OnStopped(castGUID, how)
	local rec = Ending(castGUID)
	if rec and rec.result == "sent" then
		rec.result = how
	end
end

-- your group mates' casts (Frame Effects, 2026-10-09: "Both" -- their frames
-- show their big moments): each noted with whether its spell ID came plain,
-- in a fight or not (the last OTHERS_KEEP, their tables reused)
local function NoteOther(unit, spellID)
	unit = Text(unit)
	if not unit or not (unit:match("^party%d+$") or unit:match("^raid%d+$")) then
		return
	end
	P.otherN = P.otherN + 1
	local i = (P.otherN - 1) % OTHERS_KEEP + 1
	local e = P.others[i]
	if not e then
		e = {}
		P.others[i] = e
	end
	e.clock, e.unit, e.fight = date("%H:%M:%S"), unit, InCombatLockdown() and true or false
	e.secret = Secret(spellID)
	e.spell = e.secret and "a secret spell" or SpellText(spellID)
end

-- every UNIT_COMBAT noted (the last COMBAT_KEEP, their tables reused): the
-- report shows what came round each cast's end, before it too, on anyone
local function NoteCombat(unit, event, flag, amount)
	P.cn = P.cn + 1
	local i = (P.cn - 1) % COMBAT_KEEP + 1
	local e = P.combat[i]
	if not e then
		e = {}
		P.combat[i] = e
	end
	e.t, e.unit, e.event, e.flag, e.amount = GetTime(), Text(unit) or "secret", Shown(event), Shown(flag), Shown(amount)
end

-- UNIT_COMBAT: a heal landing on a member just after a cast of yours ended
local function OnCombat(unit, event, flag, amount)
	NoteCombat(unit, event, flag, amount)
	local rec = P.landing
	if not rec then
		return
	end
	local after = GetTime() - rec.tEnd
	if after > LAND_WINDOW then
		P.landing = nil
		return
	end
	unit = Text(unit)
	if not unit or not P.memberSet[unit] or Text(event) ~= "HEAL" or #rec.landed >= LANDED_MAX then
		return
	end
	rec.landed[#rec.landed + 1] = ("%s +%s at %d ms"):format(unit, Shown(amount), after * 1000)
	rec.firstLanded = rec.firstLanded or unit
end

-- PLAYER_TARGET_CHANGED: the frame under the mouse set it (a click), or nothing did
local function OnTarget()
	local _, unit = MouseUnit()
	P.click = unit
end

local OnEvent = Perf.Shared("the heal probe's events", function(_, event, unit, a1, a2, a3)
	if event == "UNIT_SPELLCAST_SENT" then
		OnSent(a1, a2, a3)
	elseif event == "UNIT_SPELLCAST_START" then
		OnStart()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit == "player" then
			OnSucceeded(a1)
		else
			NoteOther(unit, a2)
		end
	elseif event == "UNIT_SPELLCAST_FAILED" then
		OnStopped(a1, "failed")
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		OnStopped(a1, "interrupted")
	elseif event == "UNIT_COMBAT" then
		OnCombat(unit, a1, a2, a3)
	elseif event == "PLAYER_TARGET_CHANGED" then
		OnTarget()
	end
end, "script")

local PLAYER_EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

local function Listen(on)
	if on and not P.events then
		P.events = CreateFrame("Frame")
		P.events:SetScript("OnEvent", OnEvent)
	end
	local f = P.events
	if not f then
		return
	end
	f:UnregisterAllEvents()
	P.on = on
	if on then
		for _, event in ipairs(PLAYER_EVENTS) do
			f:RegisterUnitEvent(event, "player")
		end
		f:RegisterEvent("UNIT_COMBAT")
		-- (every unit's: your group mates' casts too, for Frame Effects)
		f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		f:RegisterEvent("PLAYER_TARGET_CHANGED")
	end
end

--------------------------------------------------------------------------------
-- The report
--------------------------------------------------------------------------------

local function Method(rec, key)
	return rec.found[key] or rec.why[key] or "?"
end

local function Each(fn)
	for k = math.max(1, P.n - KEEP + 1), P.n do
		fn(P.casts[(k - 1) % KEEP + 1])
	end
end

-- the noted UNIT_COMBATs within LAND_WINDOW either side of `t`, joined
local function Around(t)
	local out, n = {}, 0
	for k = math.max(1, P.cn - COMBAT_KEEP + 1), P.cn do
		local e = P.combat[(k - 1) % COMBAT_KEEP + 1]
		local d = e.t - t
		if d >= -LAND_WINDOW and d <= LAND_WINDOW and n < AROUND_MAX then
			n = n + 1
			out[n] = ("%s %s %s%s at %+d ms"):format(e.unit, e.event, e.amount, e.flag ~= "" and (" " .. e.flag) or "", d * 1000)
		end
	end
	return n > 0 and table.concat(out, "; ") or ("none within %.1f s either side"):format(LAND_WINDOW)
end

local function Cast(rec)
	Say("#%d %s  %s  in a fight: %s  restricted: %s", rec.number, rec.clock, rec.spell,
		rec.fight and "yes" or "no", rec.restricted)
	Say("   secret? sent name %s, cast times %s%s; the client says: cast %s, casting %s, comparison %s",
		rec.sentName, rec.times, rec.castMs and (" (" .. rec.castMs .. " ms)") or "",
		tostring(rec.predCast), tostring(rec.predCasting), tostring(rec.predCompare))
	Say("   found by: frame %s%s | click %s | name %s | target %s | hover %s | self %s", Method(rec, "frame"),
		rec.found.frame and rec.focus and (" (" .. rec.focus .. ")") or "", Method(rec, "click"),
		Method(rec, "name"), Method(rec, "target"), Method(rec, "hover"), Method(rec, "self"))
	if rec.sentText then
		Say('   sent name "%s"; you are "%s"%s', rec.sentText, rec.you or "?",
			rec.nameBase and " (matched without the realm)" or "")
	end
	Say("   end: %s; landed: %s", rec.result,
		#rec.landed > 0 and table.concat(rec.landed, ", ") or ("no HEAL on a member within %.1f s"):format(LAND_WINDOW))
	if rec.tEnd then
		Say("   UNIT_COMBAT round the end (anyone, any kind): %s", Around(rec.tEnd))
	end
	if rec.result == "succeeded" then
		Say("   picked: %s; cast bar %s; %s; dot %s", rec.pick and (rec.pick .. " (by " .. rec.pickBy .. ")") or "nobody",
			tostring(rec.bar), tostring(rec.dest), rec.flight or "off")
	end
end

-- per fight state: how often each way found someone, was secret, and agreed
-- with where the heal landed
local function Summary(fight)
	local casts, landed = 0, 0
	local got, secret, both, agree = {}, {}, {}, {}
	for _, m in ipairs(METHODS) do
		got[m], secret[m], both[m], agree[m] = 0, 0, 0, 0
	end
	Each(function(rec)
		if rec.fight ~= fight or rec.result ~= "succeeded" then
			return
		end
		casts = casts + 1
		if rec.firstLanded then
			landed = landed + 1
		end
		for _, m in ipairs(METHODS) do
			local unit = rec.found[m]
			if unit then
				got[m] = got[m] + 1
				if rec.firstLanded then
					both[m] = both[m] + 1
					if unit == rec.firstLanded then
						agree[m] = agree[m] + 1
					end
				end
			elseif (rec.why[m] or ""):find("secret") then
				secret[m] = secret[m] + 1
			end
		end
	end)
	if casts == 0 then
		Say("%s: no finished casts", fight and "In a fight" or "Out of a fight")
		return
	end
	local parts = {}
	for _, m in ipairs(METHODS) do
		parts[#parts + 1] = ("%s %d/%d (secret %d, agrees with the landing %d/%d)"):format(m, got[m], casts,
			secret[m], agree[m], both[m])
	end
	Say("%s: %d finished casts, %d landed on a member", fight and "In a fight" or "Out of a fight", casts, landed)
	Say("   %s", table.concat(parts, "; "))
end

local function Report()
	MelloUI:ClearLog()
	Say(TEXT.head, P.on and "yes" or "no", P.fly and "on" or "off", MelloUI.Anim.reduceMotion and "on (the dot stays on the bar)" or "off",
		P.n, math.min(P.n, KEEP))
	if P.n == 0 then
		Say(TEXT.none)
	else
		Each(Cast)
		Summary(true)
		Summary(false)
	end
	-- your group mates' casts: does the game hand their spells out plainly in a fight?
	local seen = math.min(P.otherN, OTHERS_KEEP)
	if seen == 0 then
		Say("Your group's casts: none seen (heal or fight with a group to see whether their spells come plain)")
	else
		local fight, fightSecret, calm, calmSecret = 0, 0, 0, 0
		for k = 1, seen do
			local e = P.others[k]
			if e.fight then
				fight = fight + 1
				fightSecret = fightSecret + (e.secret and 1 or 0)
			else
				calm = calm + 1
				calmSecret = calmSecret + (e.secret and 1 or 0)
			end
		end
		Say("Your group's casts (the last %d): in a fight %d (%d secret), out of one %d (%d secret)", seen, fight,
			fightSecret, calm, calmSecret)
		for k = math.max(1, (P.otherN) - 5), P.otherN do
			local e = P.others[(k - 1) % OTHERS_KEEP + 1]
			Say("   %s %s %s%s", e.clock, e.unit, e.spell, e.fight and " (in a fight)" or "")
		end
	end
	MelloUI:ShowLog("melloheal report")
end

--------------------------------------------------------------------------------
-- /melloheal
--------------------------------------------------------------------------------

SLASH_MELLOHEAL1 = "/melloheal"
SlashCmdList.MELLOHEAL = Perf.Shared("/melloheal", function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "" or cmd == "fly" then
		if cmd == "fly" then
			P.fly = not P.fly
		end
		Listen(true)
		Say(TEXT.on, P.fly and "on" or "off")
	elseif cmd == "off" then
		Listen(false)
		Say(TEXT.off, P.n)
	elseif cmd == "report" then
		Report()
	elseif cmd == "clear" then
		P.n, P.current, P.landing, P.click, P.cn, P.otherN = 0, nil, nil, nil, 0, 0
		wipe(P.casts)
		wipe(P.combat)
		wipe(P.others)
		Say(TEXT.cleared)
	else
		Say(TEXT.usage)
	end
end, "script")
