--------------------------------------------------------------------------------
-- MelloUI - Reminders
--
-- One reminder widget for all of MelloUI (0.14.0; the user, 2026-09-26: its
-- users are Restock, New Mail, Repair Gear and Trainer, "without having them
-- stay on screen the whole time, except when you are in a safe zone, then the
-- Restock should be shown the whole time until the player either restocks or
-- leaves the safe area"). ONE round button beside the player's portrait ring
-- shows the most urgent reminder, with a count when there are more; the
-- tooltip lists them all. Hovering it softly expands the others out of it,
-- each one a round button of its own; leaving it eases them back in (after a
-- short grace, so the pointer can travel onto one). A round glow in the
-- palette's gold pulses for about 10 s, then holds steady, and brightens
-- while the player is in reach of where the reminder sends him. With the
-- kit's unit frames, the round rims are the kit's and wear the whole UI's
-- shade (Kit:ShadeElement, the unit frames' area): a dark halo under them.
--
-- A reminder is transient: it comes up, stays a short while (8 s; held while
-- the pointer is on it, then 2 s more) and goes. Only one that says it
-- persists stays after that, until it is done or its reason ends (Restock
-- while resting: until restocked or out of the rest area). Left click: the
-- reminder's own action (the way there, through the Services); in reach of
-- the NPC with a name to target, a secure button targets him instead (the
-- player's own click). Right click: Not now.
--
--   local Rem = MelloUI.Reminders
--   Rem:Register(spec) -> key
--     key         a unique string ("restock", "mail", "repair", "trainer");
--                 registered again, the new spec replaces the old one
--     check       fn(key, why) -> active[, reach]: is it wanted now? reach:
--                 the player stands in reach of where it sends him (the glow
--                 brightens; a click targets `target`). A secret answer
--                 counts as not wanted, not in reach. why: the event's name,
--                 or "login", "rest", "zone", "refresh", "setting", "where",
--                 "stopped". Called only after login, never in combat.
--     icon        a texture (path or file id), or fn(key) -> one
--     text        fn(key) -> its line: beside the button while it is new, and
--                 in the tooltip ("Restock: 2 low"); a string works too
--     label       its name, the tooltip's title (default: the key)
--     urgency     a number, or fn(key) -> one: higher comes first (0; the
--                 user's pick: a click goes to the most urgent). At the same
--                 urgency one in reach comes first; then the order registered.
--     when        its moments: game events (UPPER_CASE), each checking it again
--                 (listened for while it is registered), and these words:
--                   "stopped"  checked again when the player stops moving,
--                              only while it is up (PLAYER_STOPPED_MOVING)
--                   "where"    checked again on Route's 'where' (every few
--                              seconds while the player travels), only while
--                              it is up (Route:WantWhere)
--                 Every reminder also has Core's three moments, which check it
--                 and raise it again while it is active: "login" (8 s after
--                 entering the world), "rest" (entering a rest area) and
--                 "zone" (a new zone; once in 5 min each). when.login = false
--                 (and .rest, .zone) leaves one out: neither raised by that
--                 moment nor brought up with another one it raises. A game
--                 event of Core's own (PLAYER_REGEN_ENABLED ...) works too.
--     onClick     fn(key, mouseButton): its action (Services:GoTo ...)
--     persistent  fn(key) -> true while it stays up after its hold
--     target      fn(key) -> the name of the NPC a click targets while in reach
--     kind        a Services kind its click goes to ("mailbox", "repair",
--                 "classtrainer", "proftrainer", "vendor", ...), with
--                 profession / letters / skip / extra as Services:Nearest
--                 takes them (read when measured: they may change in place;
--                 as the click's route has them, so the two agree). While
--                 check() gives no reach, the reach is measured here -- the nearest
--                 one within 40 yd, on the frames after a raise, when the
--                 player stops and on Route's 'where', only while it is up,
--                 at most two walks of the rows a frame -- and a click in
--                 reach targets that NPC (with no `target`; never a mailbox)
--     hint        the click's line in the tooltip ("Click: show the way there")
--     enabled     fn(key) -> false while it is switched off; left out: the
--                 Reminders setting remind_<key> (on while not saved)
--     dismiss     what its right click's Not now lasts (Dismiss's untilWhat;
--                 default "moment", or "rest" while persistent() says it
--                 stays up: Restock in a rest area)
--     tooltip     fn(key, tooltip): more lines in its tooltip
--   Rem:Unregister(key)
--   Rem:Refresh([key][, raise])   checked again on the next frame (no key:
--       every one); raise: raised again if active (the caller's own moment:
--       near a vendor that sells a low item)
--   Rem:Dismiss(key[, untilWhat])   Not now: down, and not raised until
--       "rest"    the player leaves a rest area and enters one again (kept
--                 over a reload: one flag per character in the Reminders
--                 settings, notnow_<GUID>_<key>, dropped at that entry or
--                 when the player logs in outside a rest area)
--       "moment"  its next moment of its own: wanted again after not, a raise
--                 of its own (Refresh(key, true)), login, a rest area, a zone
--       "change"  it is not wanted any more, then wanted again
--       "session" the next login or reload
--       seconds   that many seconds (then raised again while wanted)
--   Rem:State(key) -> active, up, reach, dismissed (false when not)
--   Rem:Each(fn)   fn(key, active, up) for each registered one, in rank order
--   Rem:Act(key[, mouseButton])   what a left click on it does (a tray row)
--   Rem:Text(key), Rem:Icon(key), Rem:Label(key)
--   Rem.TEXT       its in-game strings (read only by convention)
-- Bus: 'reminder' (key, active, up), when one's state changes.
--
-- The settings are the Reminders module's, read when used (a missing one is
-- its default, so they hold with that module off): place ("left" of the
-- ring, "above" or "right"; not saved: the side the ring's anchor names,
-- else left), glow ("pulse": about 10 s, then steady; "still"; "off"), hold
-- (4-20 s, 8) and remind_<key> (on). Reduce Motion stills the glow and lands
-- every move at once (MelloUI.Anim, MelloUI.Shade:Glow).
--
-- Where it sits: on the player's portrait ring, UnitFramePanel:ReminderAnchor()
-- -> region, side, reach, far (the ring with the kit or the game's portrait,
-- its free side, how far its art stands past the region, the frame's other
-- end), by anchors only (it follows the player frame with no code): left of
-- the ring, above it, or right past the frame's far end (the bars; not over
-- the name band). While the player frame is hidden (no anchor), on a place of
-- its own: MelloUI's one mover and position store (key "reminders", the
-- holder its handle; Unlock the Windows shows it with a sample line, the
-- buttons letting the mouse go so it can be dragged; Reset positions puts it
-- back). Hidden in combat (the secure part is taken off at
-- PLAYER_REGEN_DISABLED, before the lockdown) and in instances; shown again
-- after while it is still up.
--
-- Nothing is made at login: one event frame, its events and three bus
-- listeners with the first Register; the widget (a frame, the button, its
-- glow, a label on a soft band, the count) with the first raise, which never
-- comes before 8 s after entering the world; each more reminder's button when
-- first needed; the secure part the first time one is in reach. No ticker and
-- no OnUpdate: the hold is a timer, the moments are events, the expand and
-- the glow are run by the engine. Nothing is made per event: the lists are
-- reused and nothing is checked before login or in combat.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Reminders")
local C_Timer = Perf.C_Timer
local Shared = Perf.Shared
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Anim = MelloUI.Anim
local W = MelloUI.Widgets

local Rem = {}
MelloUI.Reminders = Rem

local OWNER = "Reminders"          -- the bus owner
local NEXT_KEY = "Reminders: checks"   -- Kit:NextFrame's key
local SETTINGS = "Reminders"       -- the module whose settings it reads
local MOVER_KEY = "reminders"      -- its own place in the store
local SIZE, MINI, GAP = 36, 30, 6  -- the button, each more one, the gap
local HOLD, HOLD_MIN, HOLD_MAX = 8, 4, 20
local LEAVE_HOLD = 2               -- s up after the pointer leaves
local FADE, POP, RISE = 0.6, 0.25, 6
local LABEL_FADE = 0.2
local LOGIN_DELAY = 8              -- s after entering the world: the login moment
local ZONE_AGAIN = 300             -- s: a zone raises the same one again at most this often
local LABEL_SIZE, COUNT_SIZE = 13, 11
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- a white disc (the count's ground)
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_Note_01"
-- the round buttons' kit rim wears the whole UI's shade in the unit frames'
-- area (the widget follows the kit's unit frames): a dark halo under the
-- rim and the gold glow, so the glow reads over snow and sand too
local ROUND_OPTS = { shade = "unitframes" }

Rem.TEXT = {
	title = "Reminders",
	preview = "Reminders show here. Drag to move.",
	go = "Click: show the way there",
	target = "Click: target %s",
	interact = "Then press %s to talk",
	notNow = "Right-click: not now",
}
local TEXT = Rem.TEXT

local DEFAULTS = { glow = "pulse", hold = HOLD }
local GLOWS = { pulse = true, still = true, off = true }
local SIDES = { LEFT = "left", RIGHT = "right", TOP = "above", left = "left", right = "right", above = "above" }
-- each place: the widget's point on the ring's, the way out of the button
-- (the more ones and the label go further that way), the tooltip's side
local PLACES = {
	left = { point = "RIGHT", rel = "LEFT", dx = -1, dy = 0, tip = "ANCHOR_LEFT", label = "RIGHT", labelRel = "LEFT",
		justify = "RIGHT" },
	right = { point = "LEFT", rel = "RIGHT", dx = 1, dy = 0, tip = "ANCHOR_RIGHT", label = "LEFT", labelRel = "RIGHT",
		justify = "LEFT" },
	above = { point = "BOTTOM", rel = "TOP", dx = 0, dy = 1, tip = "ANCHOR_TOP", label = "BOTTOM", labelRel = "TOP",
		justify = "CENTER" },
}

local specs, states, order = {}, {}, {}   -- [key] = spec, [key] = its state, the keys registered in order
local byEvent = {}                        -- [event] = { keys that listen for it }
local list = { n = 0 }                    -- the reminders up, in rank order (reused)
local dirty = {}                          -- [key] = why: checked on the next frame (false: not)
local raising = {}                        -- [key] = true: raised then when active
local ui = nil                            -- the widget, made with the first raise
-- the moment's state: login (the login moment came), combat, instance,
-- resting, hovered, the hold (due time, over), pending (a raise waited for
-- combat or an instance), preview (the sample while unlocked), the watches,
-- notNow (the rest flags' prefix, read once: RestFlag)
local S = { login = false, loginAsked = false, combat = false, instance = false, resting = false,
	hovered = false, holdDue = 0, holdOver = true, pending = false, preview = false, attached = false,
	queued = false, show = false, stopped = false, where = false, serial = 0, walks = 0, events = nil,
	notNow = nil }
local EXPAND = { count = 0 }              -- Anim:Expand's options (one table, count set per call)

local function Report(err)
	geterrorhandler()(err)
end

-- the Reminders settings as saved (nil before there are any)
local function Saved()
	local db = MelloUI.db
	local modules = db and db.modules
	local s = type(modules) == "table" and modules[SETTINGS] or nil
	return type(s) == "table" and s or nil
end

-- a Reminders setting as saved, a missing one its default
local function Setting(key)
	local s = Saved()
	local v
	if s then
		v = s[key]
	end
	if v == nil then
		return DEFAULTS[key]
	end
	return v
end

local function HoldTime()
	local h = Num(Setting("hold")) or HOLD
	return h < HOLD_MIN and HOLD_MIN or (h > HOLD_MAX and HOLD_MAX or h)
end

local function GlowMode()
	local g = Setting("glow")
	return (not Secret(g) and GLOWS[g]) and g or "pulse"
end

-- a spec's field that may be a value or fn(key) -> one (an error reported, nil)
local function Value(field, key)
	if type(field) ~= "function" then
		return field
	end
	local ok, v = pcall(field, key)
	if not ok then
		Report(v)
		return nil
	end
	return v
end

-- a yes from a user's function: a secret or false answer is no
local function Yes(fn, key)
	if type(fn) ~= "function" then
		return false
	end
	local ok, v = pcall(fn, key)
	if not ok then
		Report(v)
		return false
	end
	return not Secret(v) and v and true or false
end

local function Enabled(key)
	local fn = specs[key].enabled
	if fn ~= nil then
		if type(fn) ~= "function" then
			return fn and true or false
		end
		local ok, on = pcall(fn, key)
		if not ok then
			Report(on)
			return false
		end
		return Secret(on) or (on and true or false)
	end
	return Setting(states[key].setting) ~= false
end

function Rem:Label(key)
	local spec = specs[key]
	if not spec then
		return nil
	end
	local label = Value(spec.label, key)
	return (Secret(label) or type(label) == "string") and label or key
end

function Rem:Text(key)
	local spec = specs[key]
	if not spec then
		return nil
	end
	local text = Value(spec.text, key)
	if Secret(text) or type(text) == "string" then
		return text
	end
	return self:Label(key)
end

function Rem:Icon(key)
	local spec = specs[key]
	return spec and Value(spec.icon, key) or nil
end

local function Tell(key)
	local st = states[key]
	MelloUI:Fire("reminder", key, st.active, st.up)
end

-- A "rest" Not now kept over a reload (the user's pick: Not now hides
-- Restock until the player leaves a rest area and enters one again, and a
-- reload in the inn is no leaving): one flag per character and reminder in
-- the Reminders settings, notnow_<GUID>_<key> (a keep key of that module:
-- never in a profile). Set by Dismiss, dropped at the next rest entry, by
-- another Not now, and at the login moment outside a rest area. Nothing is
-- written or read per event: only at these moments.
local function RestFlag(key)
	local prefix = S.notNow
	if prefix == nil then
		local ok, guid = pcall(UnitGUID, "player")
		if not ok or Secret(guid) or type(guid) ~= "string" or guid == "" then
			return nil   -- (read again next time)
		end
		prefix = "notnow_" .. guid:gsub("[^%w]", "") .. "_"
		S.notNow = prefix
	end
	return prefix .. key
end

local function KeepRest(key, on)
	local s, flag = Saved(), RestFlag(key)
	if s and flag then
		s[flag] = on and true or nil
	end
end

-- at the login moment (or a registration after it): a flag found brings
-- its Not now back while the player rests; outside a rest area it is over
local function RestoreRest(key)
	local s, flag = Saved(), RestFlag(key)
	if not (s and flag and s[flag]) then
		return
	end
	local st = states[key]
	if S.resting == false then
		s[flag] = nil
	elseif not st.dismissed then
		st.dismissed = "rest"
	end
end

-- a Not now still holding (a timed one that ran out is over)
local function Dismissed(st)
	local d = st.dismissed
	if not d then
		return false
	end
	if type(d) == "number" and GetTime() >= d then
		st.dismissed = false
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- The ranking: the reminders up, most urgent first
--------------------------------------------------------------------------------

-- (the most urgent first: the user's "a click goes to the most urgent";
-- reach only breaks a tie, so broken gear keeps the button by a mailbox)
local function Before(a, b)
	local sa, sb = states[a], states[b]
	if sa.urgency ~= sb.urgency then
		return sa.urgency > sb.urgency
	end
	if sa.reach ~= sb.reach then
		return sa.reach
	end
	return sa.serial < sb.serial
end

-- the reminders up into `list`, ranked (an insertion sort: a handful, no table)
local function Collect()
	local n = 0
	for i = 1, #order do
		local key = order[i]
		if states[key].up then
			n = n + 1
			local j = n
			while j > 1 and Before(key, list[j - 1]) do
				list[j] = list[j - 1]
				j = j - 1
			end
			list[j] = key
		end
	end
	for i = n + 1, list.n do
		list[i] = false
	end
	list.n = n
	return n
end

--------------------------------------------------------------------------------
-- Where it sits
--------------------------------------------------------------------------------

-- the player's ring (UnitFramePanel's contract): region (the ring, or the
-- game's portrait), side (its free side), reach (how far its art stands past
-- region: added to the gap), far (the frame's other end: the "right" place
-- goes past it, not onto the name band); nil while the player frame is
-- hidden or there is no such panel
local function Anchor()
	local panel = MelloUI.GetModule and MelloUI:GetModule("UnitFramePanel")
	local fn = type(panel) == "table" and panel.ReminderAnchor
	if type(fn) ~= "function" then
		return nil
	end
	local ok, region, side, reach, far = pcall(fn, panel)
	if not ok then
		Report(region)
		return nil
	end
	if Secret(region) or type(region) ~= "table" then
		return nil
	end
	if Secret(side) then
		side = nil
	end
	if Secret(far) or type(far) ~= "table" then
		far = nil
	end
	return region, side, Num(reach) or 0, far
end

local function PlaceOf(side)
	local place = Setting("place")
	if not Secret(place) and PLACES[place] then
		return place
	end
	return SIDES[side] or "left"
end

-- its own place's default: left of the screen's middle, a little below
local function Home(frame)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", -300, -160)
end

-- each more reminder rests beyond the button, the way out of it
local function AnchorMini(m, i)
	local p = PLACES[ui.place]
	local d = SIZE / 2 + GAP + MINI / 2 + (i - 1) * (MINI + GAP)
	m:ClearAllPoints()
	m:SetPoint("CENTER", ui.button, "CENTER", p.dx * d, p.dy * d)
end

local function AnchorLabel()
	local p = PLACES[ui.place]
	local label = ui.label
	label:ClearAllPoints()
	label:SetPoint(p.label, ui.button, p.labelRel, p.dx * (GAP + 6), p.dy * (GAP + 4))
	label:SetJustifyH(p.justify)
end

-- The secure target button (a protected frame) laid over the round button by
-- measure, on UIParent: the widget hangs from the player portrait, a region,
-- and the game refuses a protected frame anchored to a chain that ends on a
-- region (user, 2026-09-26: "Cannot anchor protected frames to regions").
-- Out of combat only (a protected frame); false when a read is secret.
local function OverlayPlace(o)
	local b = ui and ui.button
	if not (o and b) or InCombatLockdown() then
		return false
	end
	local okC, cx, cy = pcall(b.GetCenter, b)
	local okS, w, h = pcall(b.GetSize, b)
	local okE, bs = pcall(b.GetEffectiveScale, b)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	if not (okC and okS and okE and okU) or Secret(cx) or Secret(cy) or Secret(w) or Secret(h)
		or Secret(bs) or Secret(us) or not (cx and cy and w and h and bs and us) or us <= 0 then
		return false
	end
	local k = bs / us
	o:ClearAllPoints()
	o:SetSize(w * k, h * k)
	o:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * k, cy * k)
	return true
end

local function Place()
	if not ui then
		return
	end
	local holder = ui.holder
	if ui.entry and ui.entry.moving then
		return   -- (being dragged: laid again when let go)
	end
	Anim:Land(holder, "y")   -- a rise under way ends first: the anchor is laid anew
	local region, side, reach, far = Anchor()
	local place = PlaceOf(side)
	if place ~= ui.place then
		ui.place = place
		for i = 1, #ui.minis do
			AnchorMini(ui.minis[i], i)
		end
		AnchorLabel()
	end
	holder:ClearAllPoints()
	if region then
		S.attached = true
		local p = PLACES[place]
		local gap = GAP + reach
		if place == "right" and far then
			region, gap = far, GAP   -- (past the bars' end, not over the name band)
		end
		holder:SetPoint(p.point, region, p.rel, p.dx * gap, p.dy * gap)
	else
		S.attached = false
		if not MelloUI:RestorePosition(MOVER_KEY, holder) then
			Home(holder)
		end
	end
	-- the secure target button follows the widget (placed by measure)
	local o = ui.overlay
	if o and o:IsShown() and not OverlayPlace(o) and not InCombatLockdown() then
		o:Hide()
	end
end

--------------------------------------------------------------------------------
-- The widget
--------------------------------------------------------------------------------

local Build, Lay, Hide, Show, Tip, Preview
local Queue   -- (checks and raises, below)

-- the kit while the kit's unit frames are on (handed to the round buttons'
-- kit look, W.RoundIcon), else false: their plain look
local function KitOn()
	local Kit = MelloUI.Kit
	return (Kit and Kit.IsOn and Kit:IsOn("unitframes")) and Kit or false
end

local function ApplyGlow(glow)
	local mode = GlowMode()
	if mode == "off" then
		glow:SetShown(false)
		return
	end
	if mode == "still" then
		glow:Still()
	else
		glow:Settle()
	end
	glow:SetShown(true)
end

local function ApplyGlows()
	if not ui then
		return
	end
	if ui.button.key or not S.preview then
		ApplyGlow(ui.glow)
	end
	for i = 1, #ui.minis do
		ApplyGlow(ui.minis[i].glow)
	end
end

-- the line beside the button: faded in and out, but gone at once for the
-- pointer (the others expand where it was: the hover runs no Lua per frame)
local function ShowLabel(on)
	if not ui then
		return
	end
	local lf = ui.labelFrame
	if on and not S.hovered then
		if not lf:IsShown() or Anim:Target(lf, "alpha") == 0 then
			Anim:FadeIn(lf, LABEL_FADE)
		end
	elseif S.hovered then
		Anim:Stop(lf)
		lf:Hide()
		lf:SetAlpha(1)
	elseif lf:IsShown() then
		Anim:FadeOut(lf, LABEL_FADE)
	end
end

-- the secure part: laid over the button while its reminder is in reach and
-- names an NPC, so the player's click targets him (/targetexact); only out
-- of combat, and taken off before the lockdown
local function Detach()
	local o = ui and ui.overlay
	if o and o:IsShown() and not InCombatLockdown() then
		o:ClearAllPoints()
		o:Hide()
	end
end

local function TargetName(key)
	local st, spec = states[key], specs[key]
	if not (st and spec and st.reach) then
		return nil
	end
	local name
	if spec.target ~= nil then
		name = Value(spec.target, key)
	else
		name = st.nearName
	end
	if Secret(name) or type(name) ~= "string" or name == "" then
		return nil
	end
	return name
end

-- Reach, for a reminder that names where its click goes (spec.kind, a
-- Services kind, with spec.profession / letters / skip / extra) and gives
-- no reach of its own: the nearest one of that kind within REACH_YARDS,
-- measured at a raise, when the player stops, and on Route's 'where' -- never per event
-- (a walk of the service rows). Its NPC's name is what a click targets
-- (never a mailbox's: an object is no target).
local REACH_YARDS = 40
local NEAR_OPTS = {}   -- (Services:Nearest's filters, one table, filled per ask)

local function Measure(key)
	local st, spec = states[key], specs[key]
	if not (st.measured and st.active) then
		return
	end
	local services = MelloUI.GetModule and MelloUI:GetModule("Services")
	local fn = type(services) == "table" and services.Nearest
	local yards, name
	if type(fn) == "function" then
		local profession, letters, skip, extra = spec.profession, spec.letters, spec.skip, spec.extra
		NEAR_OPTS.profession, NEAR_OPTS.letters, NEAR_OPTS.skip, NEAR_OPTS.extra = profession, letters, skip, extra
		local ok, d, n = pcall(fn, services, spec.kind, (profession or letters or skip or extra) and NEAR_OPTS or nil)
		if ok then
			yards, name = Num(d), n
		else
			Report(d)
		end
	end
	st.reach = yards ~= nil and yards <= REACH_YARDS
	st.nearName = (st.reach and spec.kind ~= "mailbox" and not Secret(name) and type(name) == "string") and name or nil
end

-- the ones up, measured again on the next frame (not in the frame that
-- shows the widget: a walk each), at most WALKS a frame
local WALKS = 2
local function MeasureUp()
	for i = 1, #order do
		local key = order[i]
		local st = states[key]
		if st.up and st.measured then
			Queue(key, "where")
		end
	end
end

local Enter, Leave, Click, OverlayClick   -- the shared handlers (below)

local function Attach(key)
	if S.combat or InCombatLockdown() then
		return
	end
	if S.preview then
		Detach()   -- (dragged by the holder under it: nothing over it)
		return
	end
	local name = TargetName(key)
	if not name then
		Detach()
		return
	end
	local o = ui.overlay
	if not o then
		o = CreateFrame("Button", "MelloUIReminderTarget", UIParent, "SecureActionButtonTemplate")
		o:RegisterForClicks("AnyUp", "AnyDown")
		o:SetAttribute("type1", "macro")
		o.isMain = true
		Perf.SetScript(o, "PostClick", OverlayClick)
		Perf.SetScript(o, "OnEnter", Enter)
		Perf.SetScript(o, "OnLeave", Leave)
		o:Hide()
		ui.overlay = o
	end
	if o.name ~= name then
		o:SetAttribute("macrotext1", "/targetexact " .. name)
		o.name = name
	elseif o.key == key and o:IsShown() then
		return   -- (laid over the button already)
	end
	o.key = key
	o:SetFrameStrata(ui.holder:GetFrameStrata())
	o:SetFrameLevel(ui.button:GetFrameLevel() + 5)
	if not OverlayPlace(o) then
		o:Hide()   -- (no measure: the button's own click routes instead)
		return
	end
	o:Show()
end

-- the moments only a shown widget listens for: the player stopping, and
-- Route's 'where' (asked for only while wanted)
local function Watch()
	local stopped, where = false, false
	if ui and ui.holder:IsShown() and not S.combat then
		for i = 1, list.n do
			local st = states[list[i]]
			stopped = stopped or st.stopped
			where = where or st.where
		end
	end
	if stopped ~= S.stopped and S.events then
		S.stopped = stopped
		if not byEvent.PLAYER_STOPPED_MOVING then
			if stopped then
				S.events:RegisterEvent("PLAYER_STOPPED_MOVING")
			else
				S.events:UnregisterEvent("PLAYER_STOPPED_MOVING")
			end
		end
	end
	if where ~= S.where then
		S.where = where
		local R = MelloUI.Route
		if type(R) == "table" and type(R.WantWhere) == "function" then
			local ok, err = pcall(R.WantWhere, R, OWNER, where)
			if not ok then
				Report(err)
			end
		end
	end
end

local function Mini(i)
	local m = ui.minis[i]
	if m then
		return m
	end
	m = W.RoundIcon(ui.holder, MINI, nil, ROUND_OPTS)
	m:Hide()
	m:EnableMouse(not S.preview)   -- (the preview's drag: the holder's)
	Perf.SetScript(m, "OnClick", Click)
	Perf.SetScript(m, "OnEnter", Enter)
	Perf.SetScript(m, "OnLeave", Leave)
	m:SetKit(KitOn())
	m.glow = MelloUI.Shade:Glow(m, { region = m, size = MINI })
	ApplyGlow(m.glow)
	ui.minis[i] = m
	AnchorMini(m, i)
	return m
end

-- the look and the ring's anchor follow the kit's unit frames
local function OnLook(on)
	if not ui then
		return
	end
	local Kit = on and MelloUI.Kit or false
	ui.button:SetKit(Kit)
	for i = 1, #ui.minis do
		ui.minis[i]:SetKit(Kit)
	end
	Place()
end

local function OnWhere()
	if not S.where then
		return
	end
	for i = 1, list.n do
		local key = list[i]
		if states[key].where then
			Queue(key, "where")
		end
	end
end

-- the player frame shown or hidden, Edit Mode closed: on the ring or on its
-- own place again (the preview with it), on the next frame
local function PlaceAgainLater()
	Preview()
	Place()
end

local function PlaceLater()
	local Kit = MelloUI.Kit
	if ui and Kit and Kit.NextFrame then
		Kit:NextFrame("Reminders: place", PlaceAgainLater)
	end
end

-- its own place: saved only while it has no ring to hang from (dragged while
-- it hangs there, it goes back to the ring)
local function SaveFree(frame)
	if not S.attached then
		MelloUI:SavePosition(MOVER_KEY, frame)
	end
	Place()
end

local function ForgetFree()
	MelloUI:ForgetPosition(MOVER_KEY)
end

local function PlaceAgain()
	Place()
end

Build = function()
	if ui then
		return ui
	end
	ui = { minis = {}, place = "left" }
	local holder = CreateFrame("Frame", "MelloUIReminders", UIParent)
	holder:SetSize(SIZE, SIZE)
	holder:SetFrameStrata("MEDIUM")
	holder:SetClampedToScreen(true)
	holder:Hide()
	ui.holder = holder
	-- the button: its scripts before its kit look (the kit's rim hooks them)
	local b = W.RoundIcon(holder, SIZE, nil, ROUND_OPTS)
	b:SetAllPoints(holder)
	b.isMain = true
	Perf.SetScript(b, "OnClick", Click)
	Perf.SetScript(b, "OnEnter", Enter)
	Perf.SetScript(b, "OnLeave", Leave)
	b:SetKit(KitOn())
	ui.button = b
	ui.glow = MelloUI.Shade:Glow(b, { region = b, size = SIZE })
	-- the count: a number on a small dark disc at the button's lower right
	local disc = b:CreateTexture(nil, "OVERLAY", nil, 6)
	disc:SetTexture(ROUND)
	disc:SetSize(17, 17)
	disc:SetPoint("CENTER", b, "BOTTOMRIGHT", -5, 5)
	W.Paint(disc, "innerPanel", "vertex", 0.9)
	disc:Hide()
	ui.disc = disc
	local count = b:CreateFontString(nil, "OVERLAY")
	local numberFont = _G.NumberFontNormalSmall or GameFontHighlightSmall
	if numberFont then
		count:SetFontObject(numberFont)
	end
	if MelloUI.StyleFont and numberFont then
		MelloUI:StyleFont(count, "fontChat", numberFont, COUNT_SIZE)
	end
	count:SetPoint("CENTER", disc, "CENTER", 0, 0)
	W.Paint(count, "selectedTrim", "text")
	count:Hide()
	ui.count = count
	-- the label: its line beside the button while it is new, on a soft band
	local lf = CreateFrame("Frame", nil, holder)
	lf:SetAllPoints(holder)
	lf:Hide()
	ui.labelFrame = lf
	local label = lf:CreateFontString(nil, "OVERLAY")
	local textFont = _G.GameFontHighlight or GameFontHighlightSmall
	if textFont then
		label:SetFontObject(textFont)
	end
	if MelloUI.StyleFont and textFont then
		MelloUI:StyleFont(label, "fontText", textFont, LABEL_SIZE)
	end
	label:SetWordWrap(false)
	W.Paint(label, "text", "text")
	ui.label = label
	ui.band = MelloUI.Shade:Band(lf, { alpha = 0.7, feather = 16 })
	ui.band:Anchor(label, 8, 4)
	AnchorLabel()
	-- its own place, on the one mover (used while the ring is hidden). The
	-- holder is the drag handle: the mover takes a handle's mouse while the
	-- windows are locked, and the buttons keep theirs (they let it go only
	-- for the preview's drag)
	ui.entry = MelloUI:RegisterMover(holder, holder, { key = MOVER_KEY, anchor = "CENTER", save = SaveFree,
		reset = ForgetFree, default = PlaceAgain })
	-- placed again when the player frame shows or hides, the kit's unit
	-- frames switch, or Edit Mode closes (hooks on the game's frame)
	local pf = _G.PlayerFrame
	if type(pf) == "table" and pf.HookScript then
		local placeLater = Shared("OnShow / OnHide on the player frame (the reminder widget placed)", PlaceLater, "script")
		Perf.HookScript(pf, "OnShow", placeLater)
		Perf.HookScript(pf, "OnHide", placeLater)
	end
	MelloUI:On("look:unitframes", OnLook, OWNER)
	MelloUI:On("editmode", PlaceLater, OWNER)
	MelloUI:On("where", OnWhere, OWNER)
	Place()
	return ui
end

-- The widget laid for the reminders up: the most urgent on the button (its
-- icon, glow, the count, its line, the secure part in reach), the others on
-- the more buttons that expand on hover. The preview's sample when none is.
Lay = function()
	if not ui then
		return
	end
	local n = Collect()
	if n == 0 and not S.preview then
		Hide()
		return
	end
	local b = ui.button
	local shown = 0
	for i = 1, #ui.minis do
		if ui.minis[i]:IsShown() then
			shown = i
		end
	end
	if n == 0 then
		b.key = nil
		b:SetIcon(SAMPLE_ICON)
		ui.glow:SetShown(false)
		ui.disc:Hide()
		ui.count:Hide()
		ui.label:SetText(TEXT.preview)
		Anim:Retract(ui.minis)
		Detach()
		return
	end
	local top = list[1]
	b.key = top
	b:SetIcon(Rem:Icon(top))
	ui.glow:SetStrength(states[top].reach and "reach" or "near")
	if n > 1 then
		ui.count:SetText(n)
		ui.count:Show()
		ui.disc:Show()
	else
		ui.count:Hide()
		ui.disc:Hide()
	end
	ui.label:SetText(Rem:Text(top))
	for i = 2, n do
		local m = Mini(i - 1)
		local key = list[i]
		m.key = key
		m:SetIcon(Rem:Icon(key))
		m.glow:SetStrength(states[key].reach and "reach" or "near")
	end
	-- fewer than are out: all in at once; the right ones out (hovered)
	EXPAND.count = n - 1
	if shown > n - 1 then
		Anim:Retract(ui.minis)
	end
	if S.hovered and n > 1 then
		Anim:Expand(ui.minis, b, EXPAND)
	end
	if ui.holder:IsShown() then
		Attach(top)
	else
		Detach()
	end
end

-- the line wanted: while the hold runs, or the preview's sample
local function LabelWanted()
	return not S.holdOver or (S.preview and list.n == 0)
end

-- hidden: at once (combat, an instance) or fading; the expand, the secure
-- part and the watches off
local Due   -- (the hold, below)

Hide = function(now)
	if not ui then
		return
	end
	local holder = ui.holder
	-- a hidden widget holds nothing (no OnLeave may come): a hold the
	-- pointer held goes on as after a leave, so it ends (one still due
	-- later keeps its own timer)
	local held = S.hovered
	S.hovered = false
	if held and not S.holdOver then
		local due = GetTime() + LEAVE_HOLD
		if due > S.holdDue then
			Due(due)
		end
	end
	Anim:Retract(ui.minis)
	Detach()
	if now then
		Anim:Stop(holder)
		holder:Hide()
		holder:SetAlpha(1)
		Anim:Stop(ui.labelFrame)
		ui.labelFrame:Hide()
		ui.labelFrame:SetAlpha(1)
	elseif holder:IsShown() then
		ShowLabel(false)
		Anim:FadeOut(holder, FADE)
	end
	-- (its tooltip, whichever part owns it)
	local owned = GameTooltip:IsOwned(ui.button) or (ui.overlay and GameTooltip:IsOwned(ui.overlay))
	for i = 1, #ui.minis do
		owned = owned or GameTooltip:IsOwned(ui.minis[i])
	end
	if owned then
		GameTooltip:Hide()
	end
	Watch()
end

local function CanShow()
	return S.login and not S.combat and not S.instance
end

-- the hold: up for HoldTime(), then only what persists stays; a new raise
-- starts it again, the pointer holds it, and 2 s more after it leaves. One
-- shared function for every timer: a timer that finds a later due time
-- leaves it to the later one.
local HoldTimer

Due = function(at)
	S.holdDue = at
	C_Timer.After(at - GetTime(), HoldTimer)
end

local function StartHold()
	S.holdOver = false
	Due(GetTime() + HoldTime())
end

-- after the hold: each one up that does not persist goes down; the widget
-- hides once none is left (the preview aside)
local function TakeDown()
	if not S.holdOver or S.hovered then
		return
	end
	for i = 1, #order do
		local key = order[i]
		local st = states[key]
		if st.up and not Yes(specs[key].persistent, key) then
			st.up = false
			Tell(key)
		end
	end
	if ui and ui.holder:IsShown() then
		Lay()
		Watch()
	end
end

HoldTimer = function()
	if S.holdOver or S.hovered or GetTime() + 0.05 < S.holdDue then
		return
	end
	S.holdOver = true
	ShowLabel(LabelWanted())   -- (gone, but for the preview's sample)
	TakeDown()
end

-- shown (a raise): laid, placed, risen in (Anim:Pop) when it was not up, its
-- glow's 10 s again, its line, the hold started
Show = function()
	if not CanShow() then
		S.pending = true
		return
	end
	S.pending = false
	if Collect() == 0 and not S.preview then
		return
	end
	Build()
	if not ui.holder:IsVisible() then
		S.hovered = false   -- (a widget not on screen is not under the pointer)
	end
	StartHold()
	MeasureUp()
	Lay()
	Place()
	local holder = ui.holder
	if not holder:IsShown() or Anim:Target(holder, "alpha") == 0 then
		Anim:Pop(holder, POP, RISE)
	end
	if ui.button.key then
		ApplyGlow(ui.glow)
		Attach(ui.button.key)
	end
	ShowLabel(true)
	Watch()
end

-- shown again after combat or an instance: what is still up, the hold
-- going on as it was (a raise that waited starts one)
local function Resume()
	if not CanShow() then
		return
	end
	if S.pending then
		Show()
		return
	end
	if not ui or (Collect() == 0 and not S.preview) then
		return
	end
	MeasureUp()
	Lay()
	Place()
	if not ui.holder:IsShown() then
		Anim:Pop(ui.holder, POP, RISE)
	end
	if ui.button.key then
		Attach(ui.button.key)
	end
	ShowLabel(LabelWanted())
	Watch()
end

-- the sample while the windows are unlocked and it has its own place (no
-- ring to hang from), so it can be dragged
Preview = function()
	local want = S.login and MelloUI:WindowsUnlocked() and not Anchor() and true or false
	if want == S.preview then
		return
	end
	S.preview = want
	if want then
		Build()
	elseif not ui then
		return
	end
	-- the buttons let the mouse go while it is dragged (the holder under
	-- them is the handle), and take it again after
	ui.button:EnableMouse(not want)
	for i = 1, #ui.minis do
		ui.minis[i]:EnableMouse(not want)
	end
	if want then
		Detach()
		if not CanShow() then
			return
		end
		Lay()
		Place()
		if not ui.holder:IsShown() or Anim:Target(ui.holder, "alpha") == 0 then
			Anim:FadeIn(ui.holder)
		end
		ShowLabel(LabelWanted())
	else
		if list.n == 0 then
			Hide()
		else
			Lay()
			ShowLabel(LabelWanted())
		end
	end
end

--------------------------------------------------------------------------------
-- The shared handlers
--------------------------------------------------------------------------------

function Rem:Act(key, mouse)
	local spec = specs[key]
	if not (spec and type(spec.onClick) == "function") then
		return
	end
	local ok, err = pcall(spec.onClick, key, mouse or "LeftButton")
	if not ok then
		Report(err)
	end
end

Tip = function(self)
	local key = self.key
	if key and not specs[key] then
		-- (a reminder unregistered while its widget fades: nothing to tell)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
		return
	end
	-- (the title in gold, the lines and the hints in the body text: small
	-- text is never mutedText, the palette rule)
	local P = MelloUI.Palette
	local gold, text = P.selectedTrim, P.text
	GameTooltip:SetOwner(self, PLACES[ui.place].tip)
	if not key then
		GameTooltip:SetText(TEXT.title, gold[1], gold[2], gold[3])
		GameTooltip:AddLine(TEXT.preview, text[1], text[2], text[3], true)
		GameTooltip:Show()
		return
	end
	if self.isMain and list.n > 1 then
		GameTooltip:SetText(TEXT.title, gold[1], gold[2], gold[3])
		for i = 1, list.n do
			GameTooltip:AddLine(Rem:Text(list[i]), text[1], text[2], text[3], true)
		end
	else
		GameTooltip:SetText(Rem:Label(key), gold[1], gold[2], gold[3])
		GameTooltip:AddLine(Rem:Text(key), text[1], text[2], text[3], true)
	end
	local spec = specs[key]
	if type(spec.tooltip) == "function" then
		local ok, err = pcall(spec.tooltip, key, GameTooltip)
		if not ok then
			Report(err)
		end
	end
	local name = self.isMain and TargetName(key)
	if name and ui.overlay and ui.overlay:IsShown() then
		GameTooltip:AddLine(TEXT.target:format(name), text[1], text[2], text[3], true)
		local bind = _G.GetBindingKey and _G.GetBindingKey("INTERACTTARGET")
		if type(bind) == "string" and not Secret(bind) then
			GameTooltip:AddLine(TEXT.interact:format(bind), text[1], text[2], text[3], true)
		end
	else
		local hint = spec.hint
		GameTooltip:AddLine(type(hint) == "string" and hint or TEXT.go, text[1], text[2], text[3], true)
	end
	GameTooltip:AddLine(TEXT.notNow, text[1], text[2], text[3], true)
	GameTooltip:Show()
end

-- on any part: held (the hold waits), the line out of the way, the others
-- out (called back where they were going in), the tooltip. Not while it
-- fades out with nothing left up (it goes all the same).
Enter = Shared("OnEnter on the reminder widget", function(self)
	if list.n == 0 and not S.preview then
		return
	end
	S.hovered = true
	ShowLabel(false)
	if list.n > 1 then
		EXPAND.count = list.n - 1
		Anim:Expand(ui.minis, ui.button, EXPAND)
	end
	Tip(self)
end, "script")

-- off it: the others in after the grace (a move onto one calls them back),
-- and the hold goes on for at least 2 s more
Leave = Shared("OnLeave on the reminder widget", function(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
	if not S.hovered then
		return   -- (hidden under the pointer, or entered while it faded: nothing held)
	end
	S.hovered = false
	EXPAND.count = #ui.minis
	Anim:Collapse(ui.minis, ui.button, EXPAND)
	-- (a hold still due later keeps its own timer: none more is asked for)
	local due = GetTime() + LEAVE_HOLD
	if S.holdOver or due > S.holdDue then
		S.holdOver = false
		Due(due)
	end
end, "script")

Click = Shared("OnClick on the reminder widget", function(self, mouse)
	local key = self.key
	if not key then
		return
	end
	if mouse == "RightButton" then
		MelloUI:PlayUISound("check_off")
		Rem:Dismiss(key)
	else
		MelloUI:PlayUISound("tab")
		Rem:Act(key, mouse)
	end
end, "script")

-- the secure part's click: the target is the game's; a right click is Not now
OverlayClick = Shared("PostClick on the reminder widget's target button", function(self, mouse, down)
	if down then
		return
	end
	local key = self.key
	if mouse == "RightButton" and key then
		MelloUI:PlayUISound("check_off")
		Rem:Dismiss(key)
	elseif key and ui and GameTooltip:IsOwned(self) then
		Tip(self)
	end
end, "script")

--------------------------------------------------------------------------------
-- Checks, raises and the moments
--------------------------------------------------------------------------------

-- the one check of a reminder: its state from its user's answer (a reach
-- left out, for one that names a Services kind: the last one measured)
local function Check(key, why)
	local st = states[key]
	local active, reach = false, false
	if Enabled(key) then
		local ok, a, r = pcall(specs[key].check, key, why)
		if not ok then
			Report(a)
		else
			active = not Secret(a) and a and true or false
			st.measured = st.byKind and not Secret(r) and r == nil
			if st.measured then
				reach = active and st.reach or false
			else
				reach = active and not Secret(r) and r and true or false
			end
		end
	end
	st.active, st.reach = active, reach
	if active then
		local u = Num(Value(specs[key].urgency, key))
		st.urgency = u or 0
	end
end

local MOMENTS = { login = true, rest = true, zone = true }

-- one that one of Core's moments leaves down: it opted out of that moment,
-- or (a zone) a zone raised it less than ZONE_AGAIN ago
local function SitsOut(key, why, now)
	local when = specs[key].when
	if type(when) == "table" and when[why] == false then
		return true
	end
	return why == "zone" and now - states[key].zoneAt < ZONE_AGAIN
end

-- raised: it comes up, and every other one wanted and not put off comes up
-- with it (the unread ones; by one of Core's moments, only those the moment
-- would raise itself: a zone raises each one once in ZONE_AGAIN, however
-- it comes up); shown, its hold started again
local function Raise(key, why)
	local st = states[key]
	if not st.active then
		return
	end
	if st.dismissed == "moment" then
		st.dismissed = false   -- (its own moment ends a Not now until then)
	end
	if Dismissed(st) then
		return
	end
	local now = GetTime()
	local moment = MOMENTS[why]
	if why == "zone" then
		st.zoneAt = now
	end
	for i = 1, #order do
		local k = order[i]
		local s = states[k]
		if s.active and not s.up and not Dismissed(s) and (k == key or not (moment and SitsOut(k, why, now))) then
			s.up = true
			if s.measured then
				-- (its reach measured again on the next frame, MeasureUp: the
				-- last one may be from far away, so none until then)
				s.reach, s.nearName = false, nil
			end
			if why == "zone" then
				s.zoneAt = now
			end
			if k ~= key then
				Tell(k)
			end
		end
	end
	S.show = true   -- (shown once, when the pass's checks are all in)
end

-- checked, then raised on an edge (wanted after not) or when asked
local function Take(key, why, raise)
	local st = states[key]
	local wasActive, wasUp = st.active, st.up
	Check(key, why)
	if st.up and st.measured and (why == "stopped" or why == "where") then
		-- (the player moved: its reach again; past this frame's walks, on
		-- the next frame)
		if S.walks < WALKS then
			S.walks = S.walks + 1
			Measure(key)
		else
			Queue(key, why)
		end
	end
	if not st.active then
		if st.dismissed == "change" then
			st.dismissed = false
		end
		st.up = false
	elseif raise or wasActive == false then
		Raise(key, why)
	end
	if st.active ~= wasActive or st.up ~= wasUp then
		Tell(key)
	end
end

local function RunDirty()
	S.queued = false
	if not S.login or S.combat then
		return   -- (the login moment, or the end of the fight, runs them)
	end
	S.walks = 0
	local any = false
	for i = 1, #order do
		local key = order[i]
		local why = dirty[key]
		if why then
			local raise = raising[key]
			dirty[key], raising[key] = false, false
			Take(key, why, raise)
			any = true
		end
	end
	if not any then
		return
	end
	if S.show then
		S.show = false
		Show()
	elseif S.holdOver and not S.hovered then
		TakeDown()
	elseif ui and ui.holder:IsShown() then
		-- (the hold running, or held by the pointer after it: laid for
		-- what is up now, one gone no longer on the button)
		Lay()
		Watch()
	end
end

Queue = function(key, why, raise)
	if not specs[key] then
		return
	end
	if not dirty[key] or raise then
		dirty[key] = why
	end
	if raise then
		raising[key] = true
	end
	if not S.queued then
		S.queued = true
		local Kit = MelloUI.Kit
		if Kit and Kit.NextFrame then
			Kit:NextFrame(NEXT_KEY, RunDirty)
		else
			C_Timer.After(0, RunDirty)
		end
	end
end

-- one of Core's moments: every reminder checked, and raised while active
-- (a zone: once in ZONE_AGAIN each; a reminder may leave a moment out)
local function Moment(why)
	local now = GetTime()
	for i = 1, #order do
		local key = order[i]
		if not SitsOut(key, why, now) then
			Queue(key, why, true)
		elseif why == "login" then
			Queue(key, why)   -- (its state read all the same, not raised)
		end
	end
end

local function LoginMoment()
	if S.login then
		return
	end
	S.login = true
	-- (a reload in a fight: no PLAYER_REGEN_DISABLED came, the lockdown is on;
	-- PLAYER_REGEN_ENABLED runs the checks after it)
	if InCombatLockdown() then
		S.combat = true
	end
	-- where the player stands now: the next rest change is an edge from here
	local fn = _G.IsResting
	if type(fn) == "function" then
		local ok, resting = pcall(fn)
		if ok and not Secret(resting) then
			S.resting = resting and true or false
		end
	end
	for i = 1, #order do
		RestoreRest(order[i])
	end
	Preview()
	Moment("login")
end

local function InInstance()
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or Secret(inside) or Secret(kind) then
		return nil
	end
	return (inside == true and type(kind) == "string" and kind ~= "none") and true or false
end

local function SetInstance()
	local inside = InInstance()
	if inside == nil or inside == S.instance then
		return
	end
	S.instance = inside
	if inside then
		Hide(true)
	else
		Resume()
	end
end

-- a rest area entered: a Not now until then is over, and every reminder
-- checked and raised; left: what persisted only there goes (after its hold)
local function OnResting()
	local fn = _G.IsResting
	if type(fn) ~= "function" then
		return
	end
	local ok, resting = pcall(fn)
	if not ok or Secret(resting) then
		return   -- (read again at its next change)
	end
	resting = resting and true or false
	if resting == S.resting then
		return
	end
	S.resting = resting
	if not S.login then
		return
	end
	if resting then
		for i = 1, #order do
			local key = order[i]
			local st = states[key]
			if st.dismissed == "rest" then
				st.dismissed = false
				KeepRest(key, false)
			end
		end
		Moment("rest")
	else
		-- persistent() answers anew: checked again, what no longer persists
		-- goes once its hold is over
		for i = 1, #order do
			local key = order[i]
			if states[key].up then
				Queue(key, "rest")
			end
		end
	end
end

-- (no `...`: a Lua 5.1 function that takes it and never reads it makes an
-- `arg` table per call)
local function OnEvent(_, event)
	if event == "PLAYER_STOPPED_MOVING" and S.stopped then
		for i = 1, list.n do
			local key = list[i]
			if states[key].stopped then
				Queue(key, "stopped")   -- (first: the reach measured again)
			end
		end
	end
	-- the users' own (one of Core's events too: checked on the next frame,
	-- or after the fight)
	local keys = byEvent[event]
	if keys then
		for i = 1, #keys do
			Queue(keys[i], event)
		end
	end
	if event == "PLAYER_REGEN_DISABLED" then
		S.combat = true
		Hide(true)   -- (the secure part taken off before the lockdown)
	elseif event == "PLAYER_REGEN_ENABLED" then
		S.combat = false
		RunDirty()
		Resume()
	elseif event == "PLAYER_UPDATE_RESTING" then
		OnResting()
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		SetInstance()
		if S.login then
			Moment("zone")
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		SetInstance()
		if not S.loginAsked then
			S.loginAsked = true
			S.resting = nil   -- (read at the login moment's first rest change)
			C_Timer.After(LOGIN_DELAY, LoginMoment)
		end
	end
end

-- the Reminders settings, the windows unlocked, a profile load
local function OnSetting(module, key)
	if module == SETTINGS then
		if key == "place" then
			Place()
			Preview()
		elseif key == "glow" then
			ApplyGlows()
		elseif type(key) == "string" and key:sub(1, 7) == "remind_" then
			Queue(key:sub(8), "setting")
		end
	elseif module == "UIModifications" and key == "unlock" then
		Preview()
	end
end

local function OnModule(name)
	if name == "UIModifications" then
		Preview()
	end
end

local function OnRestart()
	for i = 1, #order do
		Queue(order[i], "setting")
	end
	Place()
	ApplyGlows()
	Preview()
end

local CORE_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

-- the event frame and the bus listeners, with the first Register
local function EnsureEvents()
	if S.events then
		return
	end
	local f = CreateFrame("Frame")
	for i = 1, #CORE_EVENTS do
		f:RegisterEvent(CORE_EVENTS[i])
	end
	Perf.SetScript(f, "OnEvent", OnEvent)
	S.events = f
	MelloUI:On("setting", OnSetting, OWNER)
	MelloUI:On("module", OnModule, OWNER)
	MelloUI:On("restart", OnRestart, OWNER)
	-- registered after the login pass (a module switched on later): the
	-- world is already entered, so the login moment comes by itself
	if not MelloUI.initializingModules then
		S.loginAsked = true
		C_Timer.After(LOGIN_DELAY, LoginMoment)
	end
end

--------------------------------------------------------------------------------
-- The API
--------------------------------------------------------------------------------

local function Listen(key, event)
	local keys = byEvent[event]
	if not keys then
		keys = {}
		byEvent[event] = keys
		S.events:RegisterEvent(event)
	end
	keys[#keys + 1] = key
end

local function Unlisten(key)
	for event, keys in pairs(byEvent) do
		for i = #keys, 1, -1 do
			if keys[i] == key then
				table.remove(keys, i)
			end
		end
		if #keys == 0 then
			byEvent[event] = nil
			local core = false
			for j = 1, #CORE_EVENTS do
				core = core or CORE_EVENTS[j] == event
			end
			if not core and not (event == "PLAYER_STOPPED_MOVING" and S.stopped) then
				S.events:UnregisterEvent(event)
			end
		end
	end
end

function Rem:Unregister(key)
	if not specs[key] then
		return
	end
	Unlisten(key)
	specs[key] = nil
	for i = #order, 1, -1 do
		if order[i] == key then
			table.remove(order, i)
		end
	end
	local st = states[key]
	dirty[key], raising[key] = false, false
	local wasUp = st.up
	st.up, st.active, st.reach = false, nil, false
	MelloUI:Fire("reminder", key, false, false)
	if wasUp and ui then
		Lay()
		Watch()
	end
end

function Rem:Register(spec)
	assert(type(spec) == "table" and type(spec.key) == "string" and type(spec.check) == "function",
		"MelloUI.Reminders:Register{ key = string, check = function, ... }")
	local key = spec.key
	if specs[key] then
		self:Unregister(key)
	end
	EnsureEvents()
	specs[key] = spec
	S.serial = S.serial + 1
	-- a state kept over a new registration (a module switched off and on):
	-- its Not now and zone time stay
	local st = states[key]
	if not st then
		st = { dismissed = false, zoneAt = -ZONE_AGAIN, setting = "remind_" .. key }
		states[key] = st
	end
	st.serial, st.active, st.up, st.reach, st.urgency = S.serial, nil, false, false, 0
	-- one that names a Services kind: its reach measured, followed as the
	-- player moves while it is up
	st.byKind = type(spec.kind) == "string"
	st.measured, st.nearName = st.byKind, nil
	st.stopped, st.where = st.byKind, st.byKind
	local when = spec.when
	if type(when) == "table" then
		for i = 1, #when do
			local word = when[i]
			if word == "stopped" then
				st.stopped = true
			elseif word == "where" then
				st.where = true
			elseif type(word) == "string" and word:find("^[A-Z][A-Z0-9_]+$") then
				Listen(key, word)
			end
		end
	end
	order[#order + 1] = key
	dirty[key], raising[key] = false, false
	-- after the login moment: checked and raised now (a user switched on)
	if S.login then
		RestoreRest(key)
		Queue(key, "refresh", true)
	end
	return key
end

function Rem:Refresh(key, raise)
	if key == nil then
		for i = 1, #order do
			Queue(order[i], "refresh", raise)
		end
		return
	end
	Queue(key, "refresh", raise)
end

-- a timed Not now run out: raised again while it is wanted (one shared
-- function for every such timer: each finds the ones over by then)
local NotNowOver = Shared("timer: a timed Not now over (its reminder raised again)", function()
	local now = GetTime()
	for i = 1, #order do
		local key = order[i]
		local st = states[key]
		local d = st.dismissed
		if type(d) == "number" and now + 0.05 >= d then
			st.dismissed = false
			Queue(key, "refresh", true)
		end
	end
end)

function Rem:Dismiss(key, untilWhat)
	local st, spec = states[key], specs[key]
	if not (st and spec) then
		return
	end
	local d = untilWhat
	if d == nil then
		-- (one staying up now, as Restock in a rest area: until the player
		-- leaves one and comes back)
		d = spec.dismiss or (Yes(spec.persistent, key) and "rest" or "moment")
	end
	if type(d) == "number" and not Secret(d) then
		local secs = d > 0 and d or 0
		d = GetTime() + secs
		C_Timer.After(secs, NotNowOver)
	elseif d ~= "rest" and d ~= "change" and d ~= "session" then
		d = "moment"
	end
	if d == "rest" then
		KeepRest(key, true)
	elseif st.dismissed == "rest" then
		KeepRest(key, false)
	end
	st.dismissed = d
	if st.up then
		st.up = false
		Tell(key)
		if ui then
			Lay()
			Watch()
		end
	end
end

function Rem:State(key)
	local st = states[key]
	if not (st and specs[key]) then
		return false, false, false, false
	end
	return st.active and true or false, st.up, st.reach, st.dismissed
end

do
	local each = { n = 0 }   -- (reused: the registered ones, ranked)
	function Rem:Each(fn)
		local n = #order
		for i = 1, n do
			local key = order[i]
			local j = i
			while j > 1 and Before(key, each[j - 1]) do
				each[j] = each[j - 1]
				j = j - 1
			end
			each[j] = key
		end
		for i = n + 1, each.n do
			each[i] = false
		end
		each.n = n
		for i = 1, n do
			local key = each[i]
			local st = states[key]
			fn(key, st.active and true or false, st.up)
		end
	end
end

-- for tests and dumps (read only): the widget once made, the moment's state,
-- the ranked list up
Rem.state = S
Rem.list = list
function Rem:Widget()
	return ui
end
