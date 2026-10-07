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
-- persists stays after that, until it is done or its reason ends. In a rest
-- area all four do (the user, after RC4: "the widget the be running when
-- something needs to be restocked or learned or have an email when you are
-- in a safe zones"): with Stay Up In Rest Areas on (Rem:StayUp) each stays
-- until it is done (restocked, a mailbox opened, the gear repaired, the
-- class spells learned or the profession's rank learned: each user's own
-- "wanted" ending) or until the player leaves the rest area; switched on
-- there, the ones wanted come up again at once. Left click: the
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
--     persistent  fn(key) -> true while it stays up after its hold (the four
--                 users: while wanted and Rem:StayUp())
--     fight       fn(key) -> true while it lasts through a fight (0.16.0, the
--                 bags; user 2026-09-30: "even in combat until the space is
--                 freed"): it stays drawn in combat, and a check of it runs
--                 in combat too; the others hide as before. Only the secure
--                 part is taken off before the lockdown (it lies over the
--                 button from UIParent, never inside the widget)
--     target      fn(key) -> the name of the NPC a click targets while in reach
--     secure      fn(key) -> a macro the click runs (0.17.0, the buff
--                 reminders: "/cast [@player] Arcane Intellect"; nil: none
--                 now): out of combat the one secure button lies over the
--                 button the pointer is on -- the round button or one of the
--                 others out on hover -- and runs it; in a fight none (the
--                 game places no protected frame then), the tooltip says so
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
--                 stays up: any of the four in a rest area)
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
--   Rem:StayUp() -> true while Stay Up In Rest Areas is on (the Reminders
--       setting stayResting, the one switch of all four) and the player
--       rests now (IsResting; a secret or missing answer is no) or is in a
--       town (0.16.0: a named subzone with an innkeeper or a flight master
--       within 200 yards, measured at each subzone change): what the
--       users' persistent() asks, with their own "still wanted"
--   Rem:Each(fn)   fn(key, active, up) for each registered one, in rank order
--   Rem:Act(key[, mouseButton])   what a left click on it does (a tray row)
--   Rem:Text(key), Rem:Icon(key), Rem:Label(key)
--   Rem.TEXT       its in-game strings (read only by convention)
--   spec.column = true: a row of the widget COLUMN instead (0.16.0: Voice
--       Over and the other widgets; its fields in "The column", below)
-- Bus: 'reminder' (key, active, up), when one's state changes.
--
-- The settings are the Reminders module's, read when used (a missing one is
-- its default, so they hold with that module off): place ("left" of the
-- ring, "above" or "right"; not saved: the side the ring's anchor names,
-- else left), glow ("pulse": about 10 s, then steady; "still"; "off"), hold
-- (4-20 s, 8), stayResting (on: Rem:StayUp) and remind_<key> (on). Reduce
-- Motion stills the glow and lands
-- every move at once (MelloUI.Anim, MelloUI.Shade:Glow).
--
-- Where it sits: on the player's portrait ring, UnitFramePanel:ReminderAnchor()
-- -> region, side, reach, far (the ring with the kit or the game's portrait,
-- its free side, how far its art stands past the region, the frame's other
-- end), by anchors only (it follows the player frame with no code): left of
-- the ring, above it, or right past the frame's far end (the bars; not over
-- the name band). While the player frame is hidden (no anchor), on a place of
-- its own: MelloUI's one mover and position store (key "reminders"; Edit
-- Layout shows it with a sample line on its plate to drag, and its Reset puts
-- it back; beside the portrait its plate is locked, the ring places it).
-- While Edit Layout holds a change of it, its own placing waits and lays it
-- again once the change is saved or dropped ('mover' "released"); Edit
-- Layout's first open builds it (a mover source) while the Reminders module
-- is on. Hidden in combat (the secure part is taken off at
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
-- (0.17.1, docs/plans/game-look.md) the look of MelloUI's own parts: the
-- painted one with the reskin, the game's own without (the "own" area)
local Look = MelloUI.Look

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
	secureFight = "In a fight the click cannot do it: the game allows it only out of combat.",
	-- (Edit Layout's box and plate: why it cannot be moved there)
	locked = "It sits beside your portrait while your player frame shows.",
	-- the column (0.16.0)
	colTitle = "Widgets",
	colLocked = "Locked: Lock The Widgets is on (Reminders > Widgets, or Voice Over's padlock).",
	paused = "Paused",
	left = "%s left",
	outOfCombat = "Only out of combat.",
	-- the fold row: the widgets past the cap, and the ones that sit a fight out
	fold = "+%d more",
	foldTitle = "Waiting",
	foldCombat = "Back when the fight is over.",
	foldHint = "Click: the list. In the list, a click acts, a right-click puts it away.",
}
local TEXT = Rem.TEXT

local DEFAULTS = { glow = "pulse", hold = HOLD, stayResting = true, widgetLock = false, widgetMax = 4 }
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
local Col = {}                            -- the column's side of Core's functions ("The column")
-- the moment's state: login (the login moment came), combat, instance,
-- resting, hovered, the hold (due time, over), pending (a raise waited for
-- combat or an instance), preview (the sample while Edit Layout shows), the
-- watches, notNow (the rest flags' prefix, read once: RestFlag)
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
	if not Look:On() then
		return "off"   -- (0.17.1: the game's look has no glow)
	end
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
-- Restock -- and, in a rest area, any of the four -- until the player leaves
-- a rest area and enters one again, and a reload in the inn is no leaving):
-- one flag per character and reminder in
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
-- one up that lasts through a fight (spec.fight)
local function LastsFight(key)
	local fight = specs[key].fight
	return fight ~= nil and Yes(fight, key)
end

local function FightUp()
	for i = 1, #order do
		local key = order[i]
		if states[key].up and LastsFight(key) then
			return true
		end
	end
	return false
end

local function Collect()
	local n = 0
	for i = 1, #order do
		local key = order[i]
		if states[key].up and (not S.combat or LastsFight(key)) then
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
-- target: the button it lies over (default: the widget's round button).
local function OverlayPlace(o, target)
	local b = target or (ui and ui.button)
	if not (o and b) or InCombatLockdown() then
		return false
	end
	local okC, cx, cy = pcall(b.GetCenter, b)
	local okS, w, h = pcall(b.GetSize, b)
	local okE, bs = pcall(b.GetEffectiveScale, b)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	if not (okC and okS and okE and okU) or Secret(cx) or Secret(cy) or Secret(w) or Secret(h)
		or Secret(bs) or Secret(us) or not (cx and cy and w and h and bs and us) then
		return false
	end
	local k = bs / us
	local x, y, sw, sh = cx * k, cy * k, w * k, h * k
	-- finite only (NaN passes a "<= 0" test): never handed to the secure button
	if not (k > 0 and k < math.huge and x > -math.huge and x < math.huge and y > -math.huge and y < math.huge
		and sw >= 0 and sw < math.huge and sh >= 0 and sh < math.huge) then
		return false
	end
	o:ClearAllPoints()
	o:SetSize(sw, sh)
	o:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	return true
end

-- laid: on the ring while it has one, else on its own place (home: its
-- standard place, the store passed by -- the mover's default, Edit Layout's
-- reset before it is saved)
local function Hang(home)
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
		if home or not MelloUI:RestorePosition(MOVER_KEY, holder) then
			Home(holder)
		end
	end
	-- the secure target button follows the widget (placed by measure)
	local o = ui.overlay
	if o and o:IsShown() and not OverlayPlace(o, o.target) and not InCombatLockdown() then
		o:Hide()
	end
end

-- Laid where it belongs; not while Edit Layout holds a change of it (its
-- session keeps it where the player put it): laid again when the session
-- lets go of it (Save, Discard: 'mover' "released", Build's listener)
local function Place()
	if not ui then
		return
	end
	local LS = MelloUI.LayoutSession
	if ui.entry and LS and LS.Holds(ui.entry) then
		return
	end
	Hang(false)
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

-- the macro a click on a reminder runs: its own (spec.secure, 0.17.0), else
-- on the round button, in reach of an NPC with a name, the one targeting him
local function MacroOf(key, main)
	local spec = specs[key]
	if spec and spec.secure ~= nil then
		local m = Value(spec.secure, key)
		if not Secret(m) and type(m) == "string" and m ~= "" then
			return m
		end
	end
	local name = main and TargetName(key)
	return name and ("/targetexact " .. name) or nil
end

-- the secure part over a button: the round button (target left out) or one
-- of the others out on hover, with its reminder's macro
local function Attach(key, target)
	if S.combat or InCombatLockdown() then
		return
	end
	if S.preview then
		Detach()   -- (the sample: nothing to target; its plate lies over it)
		return
	end
	target = target or ui.button
	local main = target == ui.button
	local macro = MacroOf(key, main)
	if not macro then
		if main then
			Detach()
		end
		return
	end
	local o = ui.overlay
	if not o then
		o = CreateFrame("Button", "MelloUIReminderTarget", UIParent, "SecureActionButtonTemplate")
		o:RegisterForClicks("AnyUp", "AnyDown")
		o:SetAttribute("type1", "macro")
		o.isMain = true
		W.HoverLight(o, "round")   -- (it takes the mouse from the round button it lies over: the button's light, on it)
		Perf.SetScript(o, "PostClick", OverlayClick)
		Perf.SetScript(o, "OnEnter", Enter)
		Perf.SetScript(o, "OnLeave", Leave)
		o:Hide()
		ui.overlay = o
	end
	if o.macro ~= macro then
		o:SetAttribute("macrotext1", macro)
		o.macro = macro
	elseif o.key == key and o.target == target and o:IsShown() then
		return   -- (laid over the button already)
	end
	o.key, o.target, o.isMain = key, target, main
	o:SetFrameStrata(ui.holder:GetFrameStrata())
	o:SetFrameLevel(target:GetFrameLevel() + 5)
	if not OverlayPlace(o, target) then
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
	Perf.SetScript(m, "OnClick", Click)
	Perf.SetScript(m, "OnEnter", Enter)
	Perf.SetScript(m, "OnLeave", Leave)
	m:SetKit(KitOn())
	m.glow = MelloUI.Shade:Glow(m, { region = m, size = MINI })   -- look-ok: ApplyGlow, none in the game's look (GlowMode)
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

-- the mover's default: its standard place, laid whether Edit Layout holds
-- it or not (its Reset's preview; a first place at the registration)
local function PlaceHome()
	if ui then
		Hang(true)
	end
end

-- Edit Layout's plate: locked while the ring places it
local function Locked()
	if S.attached then
		return TEXT.locked
	end
	return nil
end

-- live while the Reminders module is on (its users need it: Restock's too)
local function RemindersOn()
	local module = MelloUI:GetModule(SETTINGS)
	return module ~= nil and module.isEnabled and true or false
end

-- Edit Layout's session let go of it: laid again where it now belongs
local function OnMover(what, entry)
	if what == "released" and ui and entry == ui.entry then
		Place()
	end
end

Build = function()
	if ui then
		return ui
	end
	ui = { minis = {}, place = "left" }
	-- (0.17.0: on the Fader's host, which fades it as the user picks)
	local holder = CreateFrame("Frame", "MelloUIReminders", (MelloUI.Fader and MelloUI.Fader:Host("reminders") or UIParent))
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
	ui.glow = MelloUI.Shade:Glow(b, { region = b, size = SIZE })   -- look-ok: ApplyGlows, none in the game's look (GlowMode)
	-- the count: a number on a small dark disc at the button's lower right
	-- (the game's look: its corner number, no disc; Look.Count)
	local disc = b:CreateTexture(nil, "OVERLAY", nil, 6)
	disc:SetTexture(ROUND)
	disc:SetSize(17, 17)
	disc:SetPoint("CENTER", b, "BOTTOMRIGHT", -5, 5)
	Look.Paint(disc, "innerPanel", "vertex", 0.9)
	disc:Hide()
	ui.disc = disc
	local count = b:CreateFontString(nil, "OVERLAY")
	count:Hide()
	Look.Count(count, disc, b, COUNT_SIZE)
	ui.count = count
	-- the label: its line beside the button while it is new, on a soft band
	local lf = CreateFrame("Frame", nil, holder)
	lf:SetAllPoints(holder)
	lf:Hide()
	ui.labelFrame = lf
	local label = lf:CreateFontString(nil, "OVERLAY")
	Look.Text(label, "text", LABEL_SIZE)
	label:SetWordWrap(false)
	ui.label = label
	-- (its plate: the soft band painted, the game's tooltip frame in its look)
	ui.band = Look.Plate(lf, { alpha = 0.7, feather = 16 })
	ui.band:Anchor(label, 8, 4)
	AnchorLabel()
	-- its own place, on the one mover (used while the ring is hidden): moved
	-- in Edit Layout (its plate, locked while the ring places it), never by a
	-- drag of its own -- the buttons keep their mouse
	ui.entry = MelloUI:RegisterMover(holder, holder, { key = MOVER_KEY, anchor = "CENTER", save = SaveFree,
		reset = ForgetFree, default = PlaceHome, label = "Reminders", page = SETTINGS, when = RemindersOn,
		locked = Locked })
	MelloUI:On("mover", OnMover, OWNER)
	-- placed again when the player frame shows or hides, the kit's unit
	-- frames switch, or Edit Mode closes (hooks on the game's frame)
	local pf = _G.PlayerFrame
	if type(pf) == "table" and pf.HookScript then
		local placeLater = Shared("OnShow / OnHide on the player frame (the reminder widget placed)", PlaceLater, "script")
		Perf.HookScript(pf, "OnShow", placeLater)
		Perf.HookScript(pf, "OnHide", placeLater)
	end
	MelloUI:On("look:unitframes", OnLook, OWNER)
	-- (0.17.1: the glow is the painted look's own: none in the game's)
	MelloUI:On("look:own", ApplyGlows, OWNER .. " (its glow)")
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
		Look.CountShown(ui.count, false)
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
		Look.CountShown(ui.count, true)
	else
		Look.CountShown(ui.count, false)
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
	return S.login and not S.instance and (not S.combat or FightUp())
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

-- the sample while Edit Layout shows and it has its own place (no ring to
-- hang from), so its plate can be dragged (the plate over it takes the
-- mouse: the buttons keep theirs)
Preview = function()
	local want = S.login and MelloUI:EditingLayout() and RemindersOn() and not Anchor() and true or false
	if want == S.preview then
		return
	end
	S.preview = want
	if want then
		Build()
	elseif not ui then
		return
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
	local P = MelloUI.Look.Palette()   -- (the reskin off: the game's gold and white)
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
	if spec.secure ~= nil and (S.combat or InCombatLockdown()) then
		GameTooltip:AddLine(TEXT.secureFight, text[1], text[2], text[3], true)
	elseif name and ui.overlay and ui.overlay:IsShown() then
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
	-- (one of the others with a click of its own: the secure part moves
	-- onto it, out of combat; its tooltip is then the secure part's)
	if not self.isMain and self ~= ui.overlay and self.key and specs[self.key]
		and specs[self.key].secure ~= nil and not InCombatLockdown() then
		Attach(self.key, self)
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
	-- (the secure part over one going in: back over the round button)
	local o = ui.overlay
	if self == o and o.target ~= ui.button and not InCombatLockdown() then
		if ui.button.key then
			Attach(ui.button.key)
		else
			Detach()
		end
	end
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
	if not S.login then
		return   -- (the login moment runs them)
	end
	S.walks = 0
	local any = false
	for i = 1, #order do
		local key = order[i]
		local why = dirty[key]
		-- (in a fight only the ones that last through it; the rest after it)
		if why and (not S.combat or specs[key].fight ~= nil) then
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
	if specs[key].column then
		Col.Queue(key, why, raise)
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
	Col.All("login")
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

-- A town (user, 2026-09-30: "shown the whole time when in town, city or
-- rested area, including locations like Sentinel Hill in westfall", where
-- the rest area is only the inn): a named subzone with an innkeeper or a
-- flight master within TOWN_YARDS, by the Services' own places. Measured at
-- each subzone change (ZONE_CHANGED*), never polled; no Services, no towns.
local TOWN_YARDS = 200
local TOWN_KINDS = { "innkeeper", "flight" }

local function InTown()
	local ok, sub = pcall(_G.GetSubZoneText)
	sub = ok and MelloUI.Safe.Text(sub) or nil
	local services = sub and sub ~= "" and MelloUI:GetModule("Services")
	if not (services and type(services.Nearest) == "function") then
		return false
	end
	for i = 1, #TOWN_KINDS do
		local okN, d = pcall(services.Nearest, services, TOWN_KINDS[i])
		d = okN and Num(d) or nil
		if d and d <= TOWN_YARDS then
			return true
		end
	end
	return false
end

-- a rest area or a town entered: a Not now until then is over, and every
-- reminder checked and raised; left: what persisted only there goes (after
-- its hold)
local function OnResting()
	local fn = _G.IsResting
	if type(fn) ~= "function" then
		return
	end
	local ok, resting = pcall(fn)
	if not ok or Secret(resting) then
		return   -- (read again at its next change)
	end
	S.town = InTown()
	resting = (resting or S.town) and true or false
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
-- a fight's start and end (PLAYER_REGEN_DISABLED / _ENABLED, and the
-- preview's pretend fight)
local function FightOn()
	S.combat = true
	-- the secure part taken off before the lockdown; what lasts through a
	-- fight (spec.fight: the bags) stays drawn, the rest hides
	if ui and ui.holder:IsShown() and FightUp() then
		Detach()
		Lay()
		Watch()
	else
		Hide(true)
	end
	Col.Combat(true)
end

local function FightOff()
	S.combat = false
	RunDirty()
	Resume()
	Col.Combat(false)
end

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
			local key = keys[i]
			if specs[key].column then
				Col.Event(key, event)
			else
				Queue(key, event)
			end
		end
	end
	if event == "PLAYER_REGEN_DISABLED" then
		S.pretend = false   -- (a real fight: the preview stops, this is its own now)
		FightOn()
	elseif event == "PLAYER_REGEN_ENABLED" then
		FightOff()
	elseif event == "PLAYER_UPDATE_RESTING" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
		OnResting()
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		OnResting()
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

-- the Reminders settings, Edit Layout shown or not, a profile load
local function OnSetting(module, key)
	if module == SETTINGS then
		if key == "place" then
			Place()
			Preview()
		elseif key == "glow" then
			ApplyGlows()
			Col.Glows()
		elseif key == "widgetMax" then
			Col.Relay()
		elseif key == "stayResting" then
			-- (no check() changes: every one asked again, so one held up in a
			-- rest area goes after its hold once the switch is off; switched on
			-- while the player rests, the ones wanted come up again now and
			-- stay, a Not now still holding left as it is. One pass per click.)
			local raise = Rem:StayUp()
			for i = 1, #order do
				local k = order[i]
				Queue(k, "setting", raise and not Dismissed(states[k]))
			end
		elseif type(key) == "string" and key:sub(1, 7) == "remind_" then
			Queue(key:sub(8), "setting")
		end
	end
end

-- Edit Layout shown, paused or closed: the sample with it
local function OnEditLayout()
	Preview()
end

local function OnRestart()
	for i = 1, #order do
		Queue(order[i], "setting")
	end
	Col.All("setting")
	Place()
	ApplyGlows()
	Preview()
end

local CORE_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

-- the preview's pretend fight (Core/Preview.lua): its pull and its kill as
-- a fight's start and end; stopped by a real fight ("combat"), the combat
-- state is left as it is (PLAYER_REGEN_DISABLED makes it the fight's own)
local function OnPreview(beat, _, reason)
	local P = MelloUI.Preview
	if beat == "pull" then
		-- (the widgets' part or the reminders': the others leave them be)
		if not S.combat and P and (P:Plays("widgets") or P:Plays("reminders")) then
			S.pretend = true
			FightOn()
		end
	elseif (beat == "kill" or beat == "stop") and S.pretend then
		S.pretend = false
		if not (beat == "stop" and reason == "combat") then
			FightOff()
		end
	end
end

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
	MelloUI:On("editlayout", OnEditLayout, OWNER)
	MelloUI:On("restart", OnRestart, OWNER)
	MelloUI:On("preview", OnPreview, OWNER)
	-- registered after the login's world was entered (a module switched on
	-- later, or in Core's start-up pass, which runs after it): the login
	-- moment comes by itself; before it, on that event
	if not MelloUI.initializingModules or (MelloUI.WorldEntered and MelloUI:WorldEntered()) then
		S.loginAsked = true
		C_Timer.After(LOGIN_DELAY, LoginMoment)
	end
end

--------------------------------------------------------------------------------
-- The column (0.16.0; the user, 2026-09-29: Voice Over "way smaller" on this
-- widget, and twelve more users -- loot rolls, the corpse run, timed quests,
-- a summon, a resurrect offer, a ready check, whispers, the hunter's pet,
-- the auction house, a crafting batch, a profession cooldown -- several up
-- at once stacked "in one column", the newest on top, one Edit Layout place;
-- the picked look: docs/plans/next-update-refs/voiceover_widget_picked.jpg).
-- A spec with column = true is one ROW of the column, not a reminder by the
-- portrait:
--   the face    the round kit rim (W.RoundIcon, FACE units) with `icon`, or
--               `model` (fn(key) -> a creature id): its 3D face in the
--               rim's opening, the camera on the face, talking while
--               `talking` (fn(key) -> true) says so; or `portrait` (fn(key)
--               -> a unit token: its 2D portrait, SetPortraitTexture); or
--               `turn` = true: an arrow in the opening over the dark ground
--               (Route's Navigation arrow, user 2026-10-03: nav_widget_looks
--               pick A), `turnArt` fn(texture, key) handed it at each fill:
--               its owner dresses and turns it (the column runs nothing per
--               frame); a low glow round it
--   the band    a soft shade (Shade:Band) behind two lines: `title` (fn(key)
--               -> text[, r, g, b]: an item's quality, a class colour; the
--               label in the palette's gold when left out) and `text`, the
--               time at the right end, and `sub` (fn(key) -> text) wrapped
--               under them (the band grows with it)
--   the ring    `progress` fn(key) -> start, duration[, pausedAt] (GetTime
--               seconds): a gold ring round the face fills clockwise as the
--               time runs -- a Cooldown frame's swipe with the ring texture
--               (Media/Textures/ProgressRing), run by the engine; pausedAt
--               (a GetTime) holds it there, muted, the face dimmed under a
--               pause glyph. The time: "0:19 left" or "Paused", or `time`
--               fn(key, left, paused) -> text (nil: none)
--               `fraction` fn(key) -> 0..1 instead: the ring held at that
--               share, with no time (a pet's happiness)
--   the crest   `crest` fn(key) -> "rare" | "rareelite" (0.18.5, the Rare
--               Alert): a crest on the rim's top, the kit's (marks/crest_rare,
--               a silver star; crest_rareelite, a gold one) while the kit's
--               unit frames are on, else the game's own rank icon
--               (MelloUI.Look's rareMark / rareEliteMark); made on a row's
--               first crest
--   the glow    low, as the Reminders' glow setting has it; `alert` fn(key)
--               -> true: bright, and pulsing for as long as it says so
--               (0.18.5, a rare just spotted; user 2026-10-04: "make the
--               Widget pulse when its detected")
--   the count   `count` fn(key) -> n: a small disc on the face while n > 0
--   actions     { { glyph = "pause" | icon = texture, tip, desc, fn(key),
--               shown = fn(key), tray = true, secure = fn(key) -> macro
--               text } ... }: small round buttons that slide out under the
--               band on hover (Anim:Expand). tray: the button opens the
--               row's tray. secure: out of combat the one secure button
--               (SecureActionButtonTemplate, laid by measure over it) runs
--               the macro with the player's own click (Feed Pet); in combat
--               it says so. glyph: pause play skip stop list padlock padlockOpen
--               check cross way reply (the widget set's one sheet, W.Glyph)
--   tray        fn(key, rows) -> footer: the list under the band (W.TrayBox):
--               the spec fills rows[1..n] = { glyph | icon, text, right,
--               onClick = fn(key, entry, mouseButton) } and sets rows.n;
--               opened by an action with tray = true, or Rem:Tray(key)
--   onClick     fn(key, mouseButton): a click on the face or the band;
--               rightClick = true hands it the right click too (else the
--               right click is Not now)
--   secure      fn(key) -> macro text: a left click on the FACE runs it
--               (0.17.0, the quest item: "/use item:<id>"): out of combat
--               the one secure button lies over the face while the pointer
--               is on it (its right click still Not now); in combat none,
--               the tooltip says so
--   combat      false: folded while in combat, back in its place after it
--               (default: shown; a loot roll, a summon, Voice Over)
--   priority    "now" (a timer or a decision: a loot roll, a summon, a
--               ready check), "ongoing" (the default) or "wait" (a whisper,
--               the auction house): the column's order and what folds first
--   bottom      true: the bottom slot, never moved by another row (Voice
--               Over: what is being read stays where the eye is)
--   compact     fn(key) -> true: in combat only the face and its ring, the
--               lines and the band away (Voice Over's Compact In Combat)
--   dismiss     its Not now (default "moment": until it is not wanted any
--               more, one of its `when` events, or Rem:Refresh(key, true);
--               "session", seconds as Rem:Dismiss takes them)
-- check, when, label, enabled, hint and tooltip as a reminder's. A row is
-- checked on its events (in combat too) and at the login moment, on the
-- next frame; it shows while check() says so and no Not now holds.
--   Rem:Tray(key[, open])   its tray opened, closed (false) or toggled
-- The column: one holder on MelloUI's one mover (key "widgets", "Widgets":
-- its plate even while no row shows; the wheel sizes it; locked while the
-- Reminders setting widgetLock is on, Voice Over's Lock button), growing up
-- from its bottom edge (user, 2026-09-30): the bottom slot first, then the
-- rows by priority -- now, ongoing, wait -- each the older below, so a new
-- row moves only the rows of a lower priority. At most widgetMax rows (the
-- Reminders setting, 2 to 6; a "now" row is always shown); the rest, and in
-- combat the rows with combat = false, fold into one slim row on top: their
-- small faces and "+N more", its list in a tray on a click. Folded rows keep
-- their state and come back as they were, with no sound. Nothing at login: the holder
-- with the first row up (or Edit Layout's first open while a column user is
-- registered), each row the first time it is needed, its buttons and tray
-- at their first use. One shared timer (TICK s) only while a shown row has
-- a running time or a face that talks or loads: the time texts, a time run
-- out checked again, the talk animation. Nothing is made per event.
--------------------------------------------------------------------------------

-- (a function of its own: the file's main chunk would pass Lua 5.1's 200
-- locals with these)
local function Column()
	local COL_KEY = "widgets"
	local ROW_W, ROW_H, FACE, BTN = 330, 72, 62, 26
	-- the subtitles' width: the row's, less the face and the margins (given
	-- outright, not by anchors: a width the anchors give is known only once
	-- laid out, and the subtitles were measured before -- a line or two
	-- short, the band ending above them; user, 2026-10-01)
	local SUB_W = ROW_W - (6 + FACE + 10) - 12
	local BTN_STEP, TRAY_W, TRAY_ROW = 36, 280, 22
	local TITLE_SIZE, LINE_SIZE, SUB_SIZE, SUB_LINES = 14, 13, 12, 4
	local RING_FRAME = 1.16        -- the swipe's frame against the face (Tools/make_widget_art.py)
	local TICK = 0.5
	local GLOW_LOW = 0.4
	local ROW_FADE = 0.25
	local DIM_ALPHA = 0.6
	local SHARE_SPAN, FULL = 100, 0.999   -- a share's swipe (a full one would end the cooldown: drawn nothing)
	local MEDIA = "Interface\\AddOns\\MelloUI\\Media\\Textures\\"   -- look-ok: the painted ring's (Look.Ring: the game's sweep)
	local RING_TEX = MEDIA .. "ProgressRing"   -- look-ok: Look.Ring's painted texture
	local TALK_ANIMATION, TALK_TIME, LOAD_TRIES = 60, 2, 8
	-- a talk animation's length in seconds by model file ID (from the
	-- VoiceOver addon, MIT licence; the Voice Over overlay's until 0.16.0);
	-- one not listed is played again every TALK_TIME seconds
	local TALK = {
		[116921] = 4.0, [1100258] = 4.0, [117170] = 2.0, [1100087] = 2.0,
		[117437] = 3.0, [1022598] = 3.0, [117721] = 3.334, [1005887] = 3.334,
		[118135] = 2.0, [950080] = 2.0, [118355] = 2.0, [878772] = 2.0,
		[119063] = 4.0, [940356] = 4.0, [119159] = 4.0, [900914] = 4.0,
		[119369] = 1.8, [119376] = 1.8,
		[119563] = 2.667, [1000764] = 2.667, [119940] = 2.0, [1011653] = 2.0,
		[120263] = 3.0, [120294] = 3.0,
		[120590] = 2.1, [921844] = 2.1, [120791] = 2.0, [974343] = 2.0,
		[121087] = 2.0, [949470] = 2.0, [121287] = 2.0, [917116] = 2.0,
		[121608] = 2.0, [997378] = 2.467, [121768] = 2.667, [959310] = 2.667,
		[121942] = 2.667, [121961] = 2.934, [986648] = 2.934, [122055] = 2.934, [968705] = 2.934,
		[122414] = 2.5, [1018060] = 2.5, [122560] = 2.5, [1022938] = 2.5,
	}

	-- the order (user, 2026-09-30): the bottom slot, then now, ongoing, wait
	local RANK = { now = 1, ongoing = 2, wait = 3 }
	local MAX_ROWS, MIN_ROWS, MAX_CAP = 4, 2, 6   -- widgetMax: its default and range
	local FOLD_H, FOLD_ICON, FOLD_ICONS = 30, 22, 5

	local colOrder = {}          -- the column's keys, in the order registered
	local colDirty = {}          -- [key] = why: checked on the next frame (false: not)
	local colRaise = {}          -- [key] = true: a raise with it (a Not now "moment" over)
	local up = { n = 0 }         -- the keys shown, bottom first (reused)
	local folded = { n = 0 }     -- the keys up but folded, in the column's order (reused)
	local cand = { n = 0 }       -- the keys up, in the column's order (reused)
	local CS = { queued = false, serial = 0, ticking = false, hovered = nil, secureFor = nil }
	local col = nil              -- the column, made with the first row up
	local trayRows = { n = 0 }   -- a tray's rows as its spec fills them (reused)
	local EXP = { count = 0 }    -- Anim:Expand's options for a row's buttons (one table)
	local RowEnter, RowLeave, RowClick, BtnClick, TrayClick, SecureEnter, SecureLeave, SecurePostClick, ColDragStart,
		ColDragStop
	local FoldEnter, FoldLeave, FoldClick, FoldTrayClick
	local ColLay, Tick

	local function ColOn()
		return #colOrder > 0
	end

	-- a column setting: the lock (Voice Over's Lock button sets it)
	local function ColLocked()
		if Setting("widgetLock") == true then
			return TEXT.colLocked
		end
		return nil
	end

	local function Font(fs, size)
		local object = _G.GameFontHighlight or GameFontHighlightSmall
		if object then
			fs:SetFontObject(object)
		end
		if MelloUI.StyleFont and object then
			MelloUI:StyleFont(fs, "fontText", object, size)
		end
	end

	-- a button's or a tray row's picture: a glyph in the palette's text
	-- colour, or an icon as it is
	local function SetPicture(tex, glyph, icon)
		if glyph and W.Glyph(tex, glyph) then
			Look.Paint(tex, "text", "vertex")
			return
		end
		Look.Unpaint(tex)
		local Kit = MelloUI.Kit
		if Kit and Kit.Unpaint then
			Kit:Unpaint(tex, "vertex")
		end
		tex:SetTexture(icon)
		tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
		tex:SetVertexColor(1, 1, 1, 1)
	end

	-- a spec's field as fn(key) -> several values (an error reported: none)
	local function Values(field, key)
		if type(field) ~= "function" then
			return field
		end
		local ok, a, b, c, d = pcall(field, key)
		if not ok then
			Report(a)
			return nil
		end
		return a, b, c, d
	end

	local function Clock(secs)
		secs = math.floor(secs + 0.5)
		if secs >= 3600 then
			return string.format("%d:%02d:%02d", math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60)
		end
		return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
	end
	Rem.Clock = Clock   -- (the users' own time texts: "Page 2 of 5 · 1:52 left")

	--------------------------------------------------------------------------
	-- The column's place
	--------------------------------------------------------------------------

	-- its standard place: above the middle of the action bars, where Voice
	-- Over's window stood
	local function ColHome(frame)
		frame = frame or (col and col.holder)
		if not frame then
			return false
		end
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
		return true
	end

	local function OnLookCol(on)
		if not col then
			return
		end
		local Kit = on and MelloUI.Kit or false
		for i = 1, #col.rows do
			local row = col.rows[i]
			row.face:SetKit(Kit)
			if row.crest and row.crest.kind then
				Col.Crest(row, row.crest.kind)   -- (the kit's crest or the game's icon)
			end
			for j = 1, #row.btns do
				row.btns[j]:SetKit(Kit)
			end
			if row.tray then
				row.tray:SetKit(Kit)
			end
		end
		local f = col.fold
		if f then
			for i = 1, #f.icons do
				f.icons[i]:SetKit(Kit)
			end
			if f.tray then
				f.tray:SetKit(Kit)
			end
		end
	end

	local function ColBuild()
		if col then
			return col
		end
		col = { rows = {} }
		-- (0.17.0: on the Fader's host, which fades it as the user picks)
		local holder = CreateFrame("Frame", "MelloUIWidgets", (MelloUI.Fader and MelloUI.Fader:Host("widgets") or UIParent))
		holder:SetSize(ROW_W, ROW_H)
		holder:SetFrameStrata("MEDIUM")
		holder:SetClampedToScreen(true)
		holder:Hide()
		col.holder = holder
		ColHome(holder)
		-- moved in Edit Layout (its plate) and, while the lock is open, by a
		-- drag on any of its rows (user, 2026-09-30: "unlocked, but i cant
		-- drag it"): the rows are the drag's handles, the holder itself takes
		-- no mouse (its empty parts stay the world's)
		col.entry = MelloUI:RegisterMover(holder, holder, { key = COL_KEY, anchor = "BOTTOM", default = ColHome,
			label = TEXT.colTitle, page = SETTINGS, when = ColOn, locked = ColLocked, placeholder = { ROW_W, ROW_H },
			min = 0.6, max = 1.6, plainDrag = "always" })
		holder:EnableMouse(false)
		MelloUI:RestorePosition(COL_KEY, holder)
		MelloUI:On("look:unitframes", OnLookCol, OWNER .. " column")
		-- (0.17.1: the glow is the painted look's own; the rest of a row's look
		-- follows the own look by itself: MelloUI.Look)
		MelloUI:On("look:own", function()
			for i = 1, #col.rows do
				ApplyGlow(col.rows[i].glow)
			end
		end, OWNER .. " column (its glows)")
		return col
	end

	--------------------------------------------------------------------------
	-- A row
	--------------------------------------------------------------------------

	local ModelHide = Shared("OnHide on a widget's 3D face (its model let go)", function(self)
		pcall(self.ClearModel, self)
		self.creature, self.loaded, self.tries, self.anim, self.animAt, self.fileID = nil, nil, nil, nil, nil, nil
	end, "script")

	local function NewRow()
		local row = CreateFrame("Frame", nil, col.holder)
		row:SetSize(ROW_W, ROW_H)
		row:EnableMouse(true)
		row:Hide()
		row.row, row.btns = row, {}
		Perf.SetScript(row, "OnEnter", RowEnter)
		Perf.SetScript(row, "OnLeave", RowLeave)
		Perf.SetScript(row, "OnMouseUp", RowClick)
		Perf.SetScript(row, "OnDragStart", ColDragStart)
		Perf.SetScript(row, "OnDragStop", ColDragStop)
		MelloUI:AddMoverHandle(col.holder, row)
		local base = row:GetFrameLevel()
		-- the 3D face lies UNDER the face's rim (a model cannot be masked
		-- round): the corners of its square hide under the rim's metal; a
		-- dark ground in the opening under it while it loads
		local ground = row:CreateTexture(nil, "BACKGROUND", nil, 1)
		ground:SetTexture(ROUND)
		Look.Paint(ground, "innerPanel", "vertex")
		ground:Hide()
		row.ground = ground
		local model = CreateFrame("DressUpModel", nil, row)
		model:SetFrameLevel(base + 1)
		model:EnableMouse(false)
		model:Hide()
		Perf.SetScript(model, "OnHide", ModelHide)
		row.model = model
		-- the face: its scripts before its kit look (the kit's rim hooks them)
		local face = W.RoundIcon(row, FACE, nil, ROUND_OPTS)
		face:SetFrameLevel(base + 3)
		face:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -5)
		face.row = row
		Perf.SetScript(face, "OnClick", RowClick)
		Perf.SetScript(face, "OnEnter", RowEnter)
		Perf.SetScript(face, "OnLeave", RowLeave)
		Perf.SetScript(face, "OnDragStart", ColDragStart)
		Perf.SetScript(face, "OnDragStop", ColDragStop)
		MelloUI:AddMoverHandle(col.holder, face)
		face:SetKit(KitOn())
		row.face = face
		ground:SetAllPoints(face.icon)
		model:SetAllPoints(face.icon)
		row.glow = MelloUI.Shade:Glow(face, { region = face, size = FACE, strength = GLOW_LOW })   -- look-ok: ApplyGlows (GlowMode)
		-- the ring: a dark track, the gold swipe over it (the game's look:
		-- the cooldown's own dark sweep over the face; Look.Ring)
		local ring = CreateFrame("Cooldown", nil, face)
		ring:SetFrameLevel(face:GetFrameLevel() + 2)
		ring:EnableMouse(false)
		ring:SetDrawEdge(false)
		ring:SetDrawBling(false)
		ring:SetHideCountdownNumbers(true)
		ring:SetReverse(true)
		ring:Hide()
		row.ring = ring
		local track = face:CreateTexture(nil, "BACKGROUND", nil, -6)
		track:SetTexture(RING_TEX)
		track:SetAllPoints(ring)
		Look.Paint(track, "innerPanel", "vertex", 0.85)
		track:Hide()
		row.track = track
		Look.Ring(ring, { texture = RING_TEX, face = face, size = FACE * RING_FRAME, track = track })
		-- paused: the face dimmed under a pause glyph
		local dim = face:CreateTexture(nil, "OVERLAY", nil, 5)
		dim:SetTexture(ROUND)
		dim:SetAllPoints(face.icon)
		Look.Paint(dim, "innerPanel", "vertex", DIM_ALPHA)
		dim:Hide()
		row.dim = dim
		local pause = face:CreateTexture(nil, "OVERLAY", nil, 6)
		W.Glyph(pause, "pause")
		pause:SetSize(24, 24)
		pause:SetPoint("CENTER", face.icon, "CENTER", 0, 0)
		Look.Paint(pause, "text", "vertex")
		pause:Hide()
		row.pauseGlyph = pause
		-- the count: a number on a small dark disc at the face's lower right,
		-- over the ring (user, 2026-09-30: the ring's swipe covered it)
		local over = CreateFrame("Frame", nil, face)
		over:SetAllPoints(face)
		over:SetFrameLevel(ring:GetFrameLevel() + 1)
		local disc = over:CreateTexture(nil, "OVERLAY", nil, 6)
		disc:SetTexture(ROUND)
		disc:SetSize(19, 19)
		disc:SetPoint("CENTER", face, "BOTTOMRIGHT", -8, 8)
		Look.Paint(disc, "innerPanel", "vertex", 0.95)
		disc:Hide()
		row.disc = disc
		local count = over:CreateFontString(nil, "OVERLAY")
		count:Hide()
		Look.Count(count, disc, face, COUNT_SIZE)
		row.count = count
		-- the lines: the title, the line and its time, the subtitles
		local title = row:CreateFontString(nil, "OVERLAY")
		Look.Text(title, "gold", TITLE_SIZE)
		title:SetPoint("TOPLEFT", face, "TOPRIGHT", 10, -9)
		title:SetPoint("RIGHT", row, "RIGHT", -12, 0)
		title:SetJustifyH("LEFT")
		title:SetWordWrap(false)
		row.title = title
		local time = row:CreateFontString(nil, "OVERLAY")
		Look.Text(time, "note", LINE_SIZE - 1)
		time:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -6)
		time:SetJustifyH("RIGHT")
		row.time = time
		local text = row:CreateFontString(nil, "OVERLAY")
		Look.Text(text, "text", LINE_SIZE)
		text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
		text:SetPoint("RIGHT", time, "LEFT", -8, 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		row.text = text
		local sub = row:CreateFontString(nil, "OVERLAY")
		Look.Text(sub, "text", SUB_SIZE)
		sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
		sub:SetWidth(SUB_W)
		sub:SetJustifyH("LEFT")
		sub:SetJustifyV("TOP")
		sub:SetWordWrap(true)
		if sub.SetMaxLines then
			sub:SetMaxLines(SUB_LINES)
		end
		sub:Hide()
		row.sub = sub
		-- the band behind them (an empty region its anchor: the rect)
		local box = row:CreateTexture(nil, "BACKGROUND")
		box:SetPoint("TOPLEFT", title, "TOPLEFT", -4, 5)
		box:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 12)
		row.box = box
		-- (featherY: a fixed top and bottom fade, so the name and the last
		-- subtitle line sit on the band's full strength however tall it is)
		-- (the painted look's soft band; the game's tooltip frame in its look: Look.Plate)
		row.band = Look.Plate(row, { alpha = 0.7, feather = 18, featherY = 14, region = box, padX = 2, padY = 0 })
		col.rows[#col.rows + 1] = row
		return row
	end

	-- the row for the i-th key up (made the first time)
	local function Row(i)
		return col.rows[i] or NewRow()
	end

	--------------------------------------------------------------------------
	-- Its buttons, its tray and the secure button
	--------------------------------------------------------------------------

	-- a button's place under the face, below the row's lowest line: under the
	-- subtitles while they show (row.btnDrop, set by Fill), where Anim:Expand
	-- slides it out to
	local function PlaceBtn(row, i)
		local b = row.btns[i]
		b:ClearAllPoints()
		b:SetPoint("CENTER", row.face, "CENTER", FACE / 2 + 18 + (i - 1) * BTN_STEP, -(FACE / 2 + 9) - (row.btnDrop or 0))
	end

	local function Btn(row, i)
		local b = row.btns[i]
		if b then
			return b
		end
		b = W.GlyphButton(row, BTN, nil, ROUND_OPTS)
		b:SetFrameLevel(row.face:GetFrameLevel() + 6)
		b:Hide()
		b.row, b.index = row, i
		Perf.SetScript(b, "OnClick", BtnClick)
		Perf.SetScript(b, "OnEnter", RowEnter)
		Perf.SetScript(b, "OnLeave", RowLeave)
		b:SetKit(KitOn())
		-- (Anim:Expand slides it out from the face to its place)
		row.btns[i] = b
		PlaceBtn(row, i)
		return b
	end

	-- the actions shown now onto the row's buttons: how many
	local function LayButtons(row, key)
		local spec = specs[key]
		local actions = spec and spec.actions
		local n = 0
		if type(actions) == "table" then
			for i = 1, #actions do
				local a = actions[i]
				if a.shown == nil or Yes(a.shown, key) then
					n = n + 1
					local b = Btn(row, n)
					b.action = a
					SetPicture(b.icon, Value(a.glyph, key), Value(a.icon, key))
					b:SetOn(not (a.secure and InCombatLockdown()))
				end
			end
		end
		for i = n + 1, #row.btns do
			row.btns[i].action = nil
		end
		row.nBtns = n
		return n
	end

	local function TrayRow(t, i)
		local r = t.lines[i]
		if r then
			return r
		end
		r = CreateFrame("Button", nil, t)
		r:SetHeight(TRAY_ROW)
		r:SetPoint("TOPLEFT", t, "TOPLEFT", 6, -6 - (i - 1) * TRAY_ROW)
		r:SetPoint("RIGHT", t, "RIGHT", -6, 0)
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r.tray = t
		Perf.SetScript(r, "OnClick", TrayClick)
		W.RowPlate(r, { look = "palette" })
		local pic = r:CreateTexture(nil, "ARTWORK")
		pic:SetSize(14, 14)
		pic:SetPoint("LEFT", r, "LEFT", 4, 0)
		r.pic = pic
		local right = r:CreateFontString(nil, "OVERLAY")
		Font(right, LINE_SIZE - 1)
		right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
		right:SetJustifyH("RIGHT")
		W.Paint(right, "text", "text")
		r.right = right
		local text = r:CreateFontString(nil, "OVERLAY")
		Font(text, LINE_SIZE - 1)
		text:SetPoint("LEFT", pic, "RIGHT", 6, 0)
		text:SetPoint("RIGHT", right, "LEFT", -8, 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		W.Paint(text, "text", "text")
		r.text = text
		t.lines[i] = r
		return r
	end

	local function TrayBox(row)
		local t = row.tray
		if t then
			return t
		end
		t = W.TrayBox(row)
		t:SetFrameLevel(row.face:GetFrameLevel() + 8)
		t:SetWidth(TRAY_W)
		t:SetPoint("TOPLEFT", row.box, "BOTTOMLEFT", 2, 4)
		t:EnableMouse(true)
		t:Hide()
		t.lines, t.row = {}, row
		local foot = t:CreateFontString(nil, "OVERLAY")
		Font(foot, LINE_SIZE - 1)
		foot:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -10, 7)
		foot:SetJustifyH("RIGHT")
		W.Paint(foot, "selectedTrim", "text")
		t.foot = foot
		local rule = t:CreateTexture(nil, "ARTWORK")
		rule:SetHeight(1)
		rule:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 8, 26)
		rule:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -8, 26)
		W.Paint(rule, "border", "vertex", 0.9)
		t.rule = rule
		t:SetKit(KitOn())
		row.tray = t
		return t
	end

	-- the tray filled by its spec; closed when it has nothing
	local function FillTray(row)
		local key, t = row.key, row.tray
		local spec = key and specs[key]
		if not (t and spec and type(spec.tray) == "function") then
			return
		end
		trayRows.n = 0
		local ok, foot = pcall(spec.tray, key, trayRows)
		if not ok then
			Report(foot)
			foot = nil
		end
		local n = Num(trayRows.n) or 0
		for i = 1, n do
			local e, r = trayRows[i], TrayRow(t, i)
			r.entry = e
			SetPicture(r.pic, e.glyph, e.icon)
			r.pic:SetShown(e.glyph ~= nil or e.icon ~= nil)
			r.text:SetText(e.text or "")
			r.right:SetText(e.right or "")
			r:Show()
		end
		for i = n + 1, #t.lines do
			t.lines[i].entry = nil
			t.lines[i]:Hide()
		end
		local hasFoot = (Secret(foot) or (type(foot) == "string" and foot ~= "")) and true or false
		t.foot:SetText(hasFoot and foot or "")
		t.foot:SetShown(hasFoot)
		t.rule:SetShown(hasFoot and n > 0)
		t:SetHeight(12 + n * TRAY_ROW + (hasFoot and 26 or 0))
	end

	local function SetTray(row, open)
		if open and not (row.key and specs[row.key] and type(specs[row.key].tray) == "function") then
			open = false
		end
		row.trayOpen = open and true or false
		if open then
			Anim:Retract(row.btns)
			local t = TrayBox(row)
			FillTray(row)
			if not t:IsShown() then
				Anim:FadeIn(t, 0.15)
			end
		elseif row.tray and row.tray:IsShown() then
			Anim:FadeOut(row.tray, 0.12)
		end
	end

	-- the one secure button: laid over a button whose action runs a macro
	-- with the player's own click, out of combat only (OverlayPlace, above)
	local function SecureBtn()
		local o = CS.secure
		if o then
			return o
		end
		o = CreateFrame("Button", "MelloUIWidgetAction", UIParent, "SecureActionButtonTemplate")
		o:RegisterForClicks("AnyUp", "AnyDown")
		o:SetAttribute("type1", "macro")
		W.HoverLight(o, "round")   -- (it takes the mouse from the round button it lies over: the button's light, on it)
		Perf.SetScript(o, "OnEnter", SecureEnter)
		Perf.SetScript(o, "OnLeave", SecureLeave)
		Perf.SetScript(o, "PostClick", SecurePostClick)
		o:Hide()
		CS.secure = o
		return o
	end

	local function SecureOff()
		local o = CS.secure
		if o and o:IsShown() and not InCombatLockdown() then
			o:ClearAllPoints()
			o:Hide()
		end
		CS.secureFor = nil
	end

	-- what a button's secure click runs: its action's, or on the face its
	-- row's own (spec.secure)
	local function SecureSource(b)
		local key = b.row and b.row.key
		if not key then
			return nil
		end
		if b.action then
			return b.action.secure
		end
		local spec = specs[key]
		return b == b.row.face and spec and spec.secure or nil
	end

	local function SecureOn(b)
		local key, src = b.row.key, SecureSource(b)
		if not (key and src) or InCombatLockdown() then
			return
		end
		local macro = Value(src, key)
		if Secret(macro) or type(macro) ~= "string" or macro == "" then
			SecureOff()
			return
		end
		local o = SecureBtn()
		o:SetAttribute("macrotext1", macro)
		o:SetFrameStrata(col.holder:GetFrameStrata())
		o:SetFrameLevel(b:GetFrameLevel() + 5)
		if not OverlayPlace(o, b) then
			SecureOff()
			return
		end
		CS.secureFor = b
		o:Show()
	end

	--------------------------------------------------------------------------
	-- A row filled for its key
	--------------------------------------------------------------------------

	-- the time text for a row's ring
	local function TimeText(row)
		local key = row.key
		local spec = specs[key]
		local left, paused = nil, false
		if row.pDur then
			local now = GetTime()
			if row.pPaused then
				paused = true
				left = row.pDur - (row.pPaused - row.pStart)
			else
				left = row.pDur - (now - row.pStart)
			end
			if left < 0 then
				left = 0
			end
		end
		if type(spec.time) == "function" then
			local ok, t = pcall(spec.time, key, left, paused)
			if not ok then
				Report(t)
				t = nil
			end
			return (Secret(t) or type(t) == "string") and t or ""
		end
		if not left then
			return ""
		end
		return paused and TEXT.paused or TEXT.left:format(Clock(left))
	end

	local function SetModel(row, id)
		local m = row.model
		if m.creature ~= id then
			pcall(m.ClearModel, m)
			m.creature, m.loaded, m.tries, m.anim, m.animAt, m.fileID = id, nil, 0, nil, nil, nil
			pcall(m.SetCreature, m, id)
			pcall(m.SetPortraitZoom, m, 0.85)
			pcall(m.SetPosition, m, 0, 0, 0)
			pcall(m.SetRotation, m, 0)
		end
	end

	-- a model's load and talk, run by the shared timer while it shows
	local function Talk(row, now)
		local m = row.model
		if not (m:IsShown() and m.creature) then
			return false
		end
		if not m.loaded then
			local ok, fileID = pcall(m.GetModelFileID, m)
			if ok and fileID and not Secret(fileID) then
				m.loaded, m.fileID = true, fileID
				pcall(m.SetPortraitZoom, m, 0.85)
			else
				m.tries = (m.tries or 0) + 1
				if m.tries > LOAD_TRIES then
					m.loaded = true
				else
					pcall(m.SetCreature, m, m.creature)
					pcall(m.SetPortraitZoom, m, 0.85)
				end
				return true
			end
		end
		local talking = Yes(specs[row.key].talking, row.key)
		local length = TALK[m.fileID or 0] or TALK_TIME
		if talking then
			if m.anim ~= TALK_ANIMATION or now - (m.animAt or 0) >= length then
				m.anim, m.animAt = TALK_ANIMATION, now
				pcall(m.SetAnimation, m, TALK_ANIMATION)
			end
			return true
		end
		if m.anim ~= 0 and now - (m.animAt or 0) >= length then
			m.anim, m.animAt = 0, now   -- (the talk cycle finished, then idle)
			pcall(m.SetAnimation, m, 0)
		end
		return m.anim ~= 0
	end

	-- the turning arrow (spec.turn): its texture in the face over the dark
	-- ground, made at its first use and handed to the spec's turnArt; the
	-- owner turns it (Route, every frame while its row is wanted: the column
	-- runs nothing per frame) and tells its line changes through
	-- Rem:SetLines. (One table: Column's locals.)
	local TURN = { SHARE = 0.5 }

	function TURN.Set(row, spec, on)
		local tex = row.turnTex
		if not on then
			if tex then
				tex:Hide()
			end
			return
		end
		if not tex then
			tex = row.face:CreateTexture(nil, "ARTWORK", nil, 3)
			tex:SetSize(FACE * TURN.SHARE, FACE * TURN.SHARE)
			tex:SetPoint("CENTER", row.face.icon, "CENTER", 0, 0)
			row.turnTex = tex
		end
		tex:Show()
		if type(spec.turnArt) == "function" then
			local ok, err = pcall(spec.turnArt, tex, row.key)
			if not ok then
				Report(err)
			end
		end
	end

	-- a shown row's ring held at a share (a pet's happiness, the way done)
	function TURN.Share(row, share)
		row.liveShare = share
		share = share < 0 and 0 or (share > FULL and FULL or share)
		local ring = row.ring
		ring:SetCooldown(GetTime() - share * SHARE_SPAN, SHARE_SPAN)
		if ring.Pause then
			ring:Pause()
		end
		Look.RingState(ring, "share", true)
		ring:Show()
	end

	local function Fill(row, key)
		local spec = specs[key]
		row.key = key
		row.face.key = key
		-- the title (its own colour, or the palette's gold) and the line
		local title, r, g, b = Values(spec.title, key)
		if not (Secret(title) or type(title) == "string") then
			title = Rem:Label(key)
		end
		row.title:SetText(title)
		row.liveTitle = title
		if type(r) == "number" and type(g) == "number" and type(b) == "number" and not (Secret(r) or Secret(g) or Secret(b)) then
			local c = row.titleColour or {}
			c[1], c[2], c[3] = r, g, b
			row.titleColour = c
			Look.Colour(row.title, c)
		else
			Look.Colour(row.title, nil)
		end
		local text = Value(spec.text, key)
		row.text:SetText((Secret(text) or type(text) == "string") and text or "")
		row.liveText, row.liveShare = text, nil
		-- the face: the turning arrow, a 3D face, a unit's portrait (a pet's)
		-- or the icon
		local turning = spec.turn ~= nil
		TURN.Set(row, spec, turning)
		local id = not turning and Num(Value(spec.model, key)) or nil
		if turning then
			row.model:Hide()
			row.face:SetIcon(nil)
			row.ground:Show()
		elseif id and id > 0 then
			row.face:SetIcon(nil)
			row.ground:Show()
			SetModel(row, id)
			row.model:Show()
		else
			row.model:Hide()
			row.ground:Hide()
			local unit = spec.portrait ~= nil and Value(spec.portrait, key) or nil
			local drawn = false
			if type(unit) == "string" and not Secret(unit) and type(_G.SetPortraitTexture) == "function" then
				drawn = pcall(_G.SetPortraitTexture, row.face.icon, unit)
			end
			if not drawn then
				row.face:SetIcon(Rem:Icon(key) or SAMPLE_ICON)
			end
		end
		-- the crest on the rim (a rare's)
		if spec.crest ~= nil or row.crest then
			Col.Crest(row, spec.crest ~= nil and Value(spec.crest, key) or nil)
		end
		-- the count
		local n = Num(Value(spec.count, key))
		if n and n > 0 then
			row.count:SetText(n)
			Look.CountShown(row.count, true)
		else
			Look.CountShown(row.count, false)
		end
		-- the ring
		local start, duration, pausedAt = Values(spec.progress, key)
		start, duration, pausedAt = Num(start), Num(duration), Num(pausedAt)
		if start and duration and duration > 0 then
			local ring = row.ring
			row.pStart, row.pDur, row.pPaused = start, duration, pausedAt
			row.expired = false
			if pausedAt then
				-- (held where it stopped: the swipe's start moved on by the pause)
				ring:SetCooldown(start + (GetTime() - pausedAt), duration)
				if ring.Pause then
					ring:Pause()
				end
				Look.RingState(ring, "paused", true)
			else
				ring:SetCooldown(start, duration)
				if ring.Resume then
					ring:Resume()
				end
				Look.RingState(ring, "run", true)
			end
			ring:Show()
		else
			row.pStart, row.pDur, row.pPaused = nil, nil, nil
			-- a share with no time (a pet's happiness): the ring held there
			local share = spec.fraction ~= nil and Num(Value(spec.fraction, key)) or nil
			row.liveShare = share
			if share then
				share = share < 0 and 0 or (share > FULL and FULL or share)
				local ring = row.ring
				ring:SetCooldown(GetTime() - share * SHARE_SPAN, SHARE_SPAN)
				if ring.Pause then
					ring:Pause()
				end
				Look.RingState(ring, "share", true)
				ring:Show()
			else
				row.ring:Hide()
				Look.RingState(row.ring, nil, false)
			end
		end
		local paused = pausedAt ~= nil
		row.dim:SetShown(paused)
		row.pauseGlyph:SetShown(paused)
		row.time:SetText(TimeText(row))
		-- the subtitles, the band growing with them
		local sub = Value(spec.sub, key)
		local h = ROW_H
		row.subText = (not Secret(sub) and type(sub) == "string") and sub or nil
		if Secret(sub) or (type(sub) == "string" and sub ~= "") then
			row.sub:SetText(sub)
			row.sub:Show()
			local sh = Num(row.sub:GetStringHeight())
			row.subH = sh
			sh = sh or (SUB_LINES * (SUB_SIZE + 2))
			local need = 9 + TITLE_SIZE + 5 + LINE_SIZE + 6 + sh + 18
			if need > h then
				h = need
			end
		else
			row.subH = nil
			row.sub:SetText("")
			row.sub:Hide()
		end
		-- in combat only the face and its ring, the lines and the band away
		-- (Voice Over's Compact In Combat: the reading goes on)
		local compact = S.combat and spec.compact ~= nil and Yes(spec.compact, key) or false
		row.compact = compact
		row.title:SetShown(not compact)
		row.text:SetShown(not compact)
		row.time:SetShown(not compact)
		row.band:SetShown(not compact)
		if compact then
			row.sub:Hide()
			h = ROW_H
		end
		row:SetWidth(compact and (FACE + 12) or ROW_W)
		row:SetHeight(h)
		-- the buttons below the lowest line (user, 2026-09-30: they covered a
		-- subtitle): as far down as the row grew for it, and a little more
		local drop = h > ROW_H and (h - ROW_H + 6) or 0
		if row.btnDrop ~= drop then
			row.btnDrop = drop
			for i = 1, #row.btns do
				PlaceBtn(row, i)
			end
		end
		-- the glow: low, as the Reminders' glow setting has it (bright while
		-- the spec's `alert` says so)
		Col.Glow(row, key)
		LayButtons(row, key)
		if row.trayOpen then
			FillTray(row)
		end
		return h
	end

	--------------------------------------------------------------------------
	-- The shared timer: the time texts, a time run out, the faces' talk
	--------------------------------------------------------------------------

	local function Wanted()
		if not (col and col.holder:IsShown()) then
			return false
		end
		for i = 1, up.n do
			local row = col.rows[i]
			if (row.pDur and not row.pPaused) or (row.model:IsShown() and row.model.creature) then
				return true
			end
		end
		return false
	end

	local function StartTick()
		if not CS.ticking and Wanted() then
			CS.ticking = true
			C_Timer.After(TICK, Tick)
		end
	end

	Tick = Shared("timer: the widget column's times and faces", function()
		CS.ticking = false
		if not (col and col.holder:IsShown()) then
			return
		end
		local now, more, relay = GetTime(), false, false
		for i = 1, up.n do
			local row = col.rows[i]
			if row.key and specs[row.key] then
				if row.pDur and not row.pPaused then
					row.time:SetText(TimeText(row))
					if now - row.pStart >= row.pDur then
						if not row.expired then
							row.expired = true
							Queue(row.key, "expired")
						end
					else
						more = true
					end
				end
				if Talk(row, now) then
					more = true
				end
				-- (the subtitles' next page, as the voice goes on: laid again)
				local spec = specs[row.key]
				if spec.sub ~= nil and row.pDur and not row.pPaused then
					local sub = Value(spec.sub, row.key)
					if not Secret(sub) and (type(sub) == "string" and sub or nil) ~= row.subText then
						relay = true
					end
				end
			end
		end
		if relay then
			ColLay()
		end
		if more then
			CS.ticking = true
			C_Timer.After(TICK, Tick)
		end
	end)

	--------------------------------------------------------------------------
	-- The column laid
	--------------------------------------------------------------------------

	-- a row's place in the order: the bottom slot, then now, ongoing, wait
	local function Rank(key)
		local spec = specs[key]
		if spec.bottom then
			return 0
		end
		return RANK[spec.priority] or RANK.ongoing
	end

	-- how many rows show: widgetMax (2 to 6)
	local function Cap()
		local v = Num(Setting("widgetMax"))
		if not v then
			return MAX_ROWS
		end
		v = math.floor(v + 0.5)
		return v < MIN_ROWS and MIN_ROWS or (v > MAX_CAP and MAX_CAP or v)
	end

	-- sitting this fight out: folded while in combat
	local function SitsFightOut(key)
		return S.combat and specs[key].combat == false
	end

	-- the keys up now, in the column's order, bottom first (an insertion
	-- sort: a handful): `up` the rows shown -- the bottom slot and every
	-- "now" row, then the others while the cap allows -- and `folded` the
	-- rest, with the ones sitting a fight out
	local function CollectCol()
		local n = 0
		for i = 1, #colOrder do
			local key = colOrder[i]
			local st = states[key]
			if st.up then
				n = n + 1
				local r, j = Rank(key), n
				while j > 1 do
					local prev = cand[j - 1]
					local rp = Rank(prev)
					if rp < r or (rp == r and states[prev].since <= st.since) then
						break
					end
					cand[j] = prev
					j = j - 1
				end
				cand[j] = key
			end
		end
		for i = n + 1, cand.n do
			cand[i] = false
		end
		cand.n = n
		local cap, shown = Cap(), 0
		for i = 1, n do
			local key = cand[i]
			if Rank(key) <= RANK.now and not SitsFightOut(key) then
				shown = shown + 1
			end
		end
		local s, f = 0, 0
		for i = 1, n do
			local key = cand[i]
			local r = Rank(key)
			if not SitsFightOut(key) and (r <= RANK.now or shown < cap) then
				if r > RANK.now then
					shown = shown + 1
				end
				s = s + 1
				up[s] = key
			else
				f = f + 1
				folded[f] = key
			end
		end
		for i = s + 1, up.n do
			up[i] = false
		end
		up.n = s
		for i = f + 1, folded.n do
			folded[i] = false
		end
		folded.n = f
		return s
	end

	local function RowOff(row)
		if row.trayOpen then
			row.trayOpen = false
			if row.tray then
				row.tray:Hide()
			end
		end
		Anim:Retract(row.btns)
		if CS.secureFor and CS.secureFor.row == row then
			SecureOff()
		end
		if CS.hovered == row then
			CS.hovered = nil
		end
		row.key, row.face.key = nil, nil
		row.model:Hide()
		row:Hide()
	end

	--------------------------------------------------------------------------
	-- The fold row: the widgets past the cap, and the ones sitting a fight out
	--------------------------------------------------------------------------

	local function FoldIcon(f, i)
		local b = f.icons[i]
		if b then
			return b
		end
		b = W.RoundIcon(f, FOLD_ICON, nil, ROUND_OPTS)
		b:SetFrameLevel(f:GetFrameLevel() + 2)
		b:EnableMouse(false)
		b:SetPoint("LEFT", f, "LEFT", 8 + (i - 1) * (FOLD_ICON + 4), 0)
		b:SetKit(KitOn())
		f.icons[i] = b
		return b
	end

	local function FoldBuild()
		local f = col.fold
		if f then
			return f
		end
		f = CreateFrame("Button", nil, col.holder)
		f:SetSize(ROW_W, FOLD_H)
		f:RegisterForClicks("LeftButtonUp")
		f:Hide()
		f.icons = {}
		Perf.SetScript(f, "OnClick", FoldClick)
		Perf.SetScript(f, "OnEnter", FoldEnter)
		Perf.SetScript(f, "OnLeave", FoldLeave)
		Perf.SetScript(f, "OnDragStart", ColDragStart)
		Perf.SetScript(f, "OnDragStop", ColDragStop)
		MelloUI:AddMoverHandle(col.holder, f)
		local label = f:CreateFontString(nil, "OVERLAY")
		Font(label, LINE_SIZE)
		label:SetJustifyH("LEFT")
		W.Paint(label, "selectedTrim", "text")
		f.label = label
		local box = f:CreateTexture(nil, "BACKGROUND")
		box:SetAllPoints(f)
		-- (its plate as the rows': the band painted, the game's tooltip frame)
		f.band = Look.Plate(f, { alpha = 0.7, feather = 18, region = box, padX = 2, padY = 0 })
		col.fold = f
		return f
	end

	local function FoldTray(f)
		local t = f.tray
		if t then
			return t
		end
		t = W.TrayBox(f)
		t:SetFrameLevel(f:GetFrameLevel() + 8)
		t:SetWidth(TRAY_W)
		t:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 2)
		t:EnableMouse(true)
		t:Hide()
		t.lines, t.row, t.fold = {}, f, true
		t:SetKit(KitOn())
		f.tray = t
		return t
	end

	-- the list: each folded widget's face and title (a click acts, a right
	-- click puts it away: FoldTrayClick)
	local function FoldTrayFill(f)
		local t = FoldTray(f)
		local n = folded.n
		for i = 1, n do
			local key, r = folded[i], TrayRow(t, i)
			local title = Values(specs[key].title, key)
			if not Secret(title) and (type(title) ~= "string" or title == "") then
				title = Rem:Label(key)
			end
			r.entry = key
			SetPicture(r.pic, nil, Rem:Icon(key) or SAMPLE_ICON)
			r.pic:Show()
			r.text:SetText(title)
			r.right:SetText("")
			r:Show()
		end
		for i = n + 1, #t.lines do
			t.lines[i].entry = nil
			t.lines[i]:Hide()
		end
		t:SetHeight(12 + n * TRAY_ROW)
	end

	local function FoldFill(f)
		local k = folded.n < FOLD_ICONS and folded.n or FOLD_ICONS
		for i = 1, k do
			local b = FoldIcon(f, i)
			b:SetIcon(Rem:Icon(folded[i]) or SAMPLE_ICON)
			b:Show()
		end
		for i = k + 1, #f.icons do
			f.icons[i]:Hide()
		end
		f.label:ClearAllPoints()
		f.label:SetPoint("LEFT", f.icons[k], "RIGHT", 8, 0)
		f.label:SetText(TEXT.fold:format(folded.n))
		local w = Num(f.label:GetStringWidth()) or 60
		f:SetWidth(8 + k * (FOLD_ICON + 4) + 4 + w + 16)
		if f.trayOpen then
			FoldTrayFill(f)
		end
	end

	local function FoldOff(f)
		f.trayOpen = false
		if f.tray then
			f.tray:Hide()
		end
		if GameTooltip:IsOwned(f) then
			GameTooltip:Hide()
		end
		f:Hide()
	end

	-- The subtitles measured again on the next frame (user, 2026-09-30: the
	-- band ended above their last lines): a font string wraps to a new width
	-- only once it is laid out, so the measure taken as its text is set can be
	-- a line or two short. A changed one lays the column again (the row, its
	-- band and its buttons then as tall as the text); one pass, no poll.
	local Remeasure = Shared("the widget column's subtitles measured again", function()
		CS.remeasure = false
		if not col then
			return
		end
		for i = 1, up.n do
			local row = col.rows[i]
			if row and row.subH and row.sub:IsShown() then
				local sh = Num(row.sub:GetStringHeight())
				if sh and math.abs(sh - row.subH) > 0.5 then
					ColLay()
					return
				end
			end
		end
	end)

	ColLay = function()
		local n = CollectCol()
		if n == 0 and folded.n == 0 and not col then
			return
		end
		ColBuild()
		local holder = col.holder
		local total, below = 0, nil
		-- bottom first, each row above the one before it
		for i = 1, n do
			local row = Row(i)
			local key = up[i]
			local was = row.key
			if was ~= key and row.trayOpen then
				SetTray(row, false)
			end
			-- (one row that fails is reported and the rest still laid)
			local ok, h = pcall(Fill, row, key)
			if not ok then
				CS.lastError = h
				Report(h)
				h = ROW_H
			end
			row:ClearAllPoints()
			if below then
				row:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, 0)
			else
				row:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
			end
			below = row
			total = total + h
			if not row:IsShown() then
				row:SetAlpha(1)
				if was == nil and holder:IsShown() then
					Anim:FadeIn(row, ROW_FADE)
				else
					row:Show()
				end
			end
		end
		for i = n + 1, #col.rows do
			local row = col.rows[i]
			if row.key or row:IsShown() then
				RowOff(row)
			end
		end
		-- the fold row on top of them
		if folded.n > 0 then
			local f = FoldBuild()
			FoldFill(f)
			f:ClearAllPoints()
			if below then
				f:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, 0)
			else
				f:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
			end
			f:Show()
			total = total + FOLD_H
		elseif col.fold and col.fold:IsShown() then
			FoldOff(col.fold)
		end
		holder:SetHeight(total > 0 and total or ROW_H)
		-- (a row with subtitles: measured again once they are laid out)
		if not CS.remeasure then
			for i = 1, n do
				if col.rows[i].subH then
					CS.remeasure = true
					C_Timer.After(0, Remeasure)
					break
				end
			end
		end
		if n > 0 or folded.n > 0 then
			if not holder:IsShown() or Anim:Target(holder, "alpha") == 0 then
				Anim:FadeIn(holder, ROW_FADE)
			end
			StartTick()
		elseif holder:IsShown() then
			for i = 1, #col.rows do
				local row = col.rows[i]
				if GameTooltip:IsOwned(row) or GameTooltip:IsOwned(row.face) then
					GameTooltip:Hide()
				end
			end
			Anim:FadeOut(holder, FADE)
		end
	end

	--------------------------------------------------------------------------
	-- The shared handlers
	--------------------------------------------------------------------------

	local function RowTip(owner, row)
		local key = row.key
		local spec = key and specs[key]
		if not spec then
			return
		end
		local P = MelloUI.Look.Palette()   -- (the reskin off: the game's gold and white)
		local gold, text = P.selectedTrim, P.text
		GameTooltip:SetOwner(owner, "ANCHOR_TOP")
		GameTooltip:SetText(Rem:Label(key), gold[1], gold[2], gold[3])
		local line = Value(spec.text, key)
		if Secret(line) or (type(line) == "string" and line ~= "") then
			GameTooltip:AddLine(line, text[1], text[2], text[3], true)
		end
		if type(spec.tooltip) == "function" then
			local ok, err = pcall(spec.tooltip, key, GameTooltip)
			if not ok then
				Report(err)
			end
		end
		if type(spec.hint) == "string" then
			GameTooltip:AddLine(spec.hint, text[1], text[2], text[3], true)
		end
		if spec.secure ~= nil and InCombatLockdown() then
			GameTooltip:AddLine(TEXT.outOfCombat, text[1], text[2], text[3], true)
		end
		if not spec.rightClick then
			GameTooltip:AddLine(TEXT.notNow, text[1], text[2], text[3], true)
		end
		GameTooltip:Show()
	end

	local function BtnTip(b, owner)
		local a = b.action
		if not a then
			return
		end
		local P = MelloUI.Look.Palette()   -- (the reskin off: the game's gold and white)
		local gold, text = P.selectedTrim, P.text
		GameTooltip:SetOwner(owner or b, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(Value(a.tip, b.row.key) or "", gold[1], gold[2], gold[3])
		local desc = Value(a.desc, b.row.key)
		if type(desc) == "string" and desc ~= "" then
			GameTooltip:AddLine(desc, text[1], text[2], text[3], true)
		end
		if a.secure and InCombatLockdown() then
			GameTooltip:AddLine(TEXT.outOfCombat, text[1], text[2], text[3], true)
		end
		GameTooltip:Show()
	end

	RowEnter = Shared("OnEnter on a widget row", function(self)
		local row = self.row
		if not (row and row.key) then
			return
		end
		CS.hovered = row
		local n = row.nBtns or 0
		if n > 0 and not row.trayOpen then
			EXP.count = n
			Anim:Expand(row.btns, row.face, EXP)
		end
		if self.action then
			BtnTip(self)
			if self.action.secure then
				SecureOn(self)
			end
		elseif self == row.face then
			RowTip(self, row)
			if SecureSource(self) then
				SecureOn(self)
			end
		end
	end, "script")

	RowLeave = Shared("OnLeave on a widget row", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
		local row = self.row
		if not row then
			return
		end
		-- (onto the secure button laid over this button or face: still on it)
		local o = CS.secure
		if o and CS.secureFor == self and o:IsShown() and o:IsMouseOver() then
			return
		end
		EXP.count = #row.btns
		Anim:Collapse(row.btns, row.face, EXP)
	end, "script")

	-- a drag of the column is no click (its mouse-up comes with it)
	local function JustDragged()
		return CS.dragging or (CS.dragEnd ~= nil and GetTime() - CS.dragEnd < 0.3)
	end

	ColDragStart = Shared("OnDragStart on the widget column (its plain drag)", function()
		CS.dragging = true
	end, "script")

	ColDragStop = Shared("OnDragStop on the widget column (its plain drag)", function()
		CS.dragging, CS.dragEnd = false, GetTime()
	end, "script")

	RowClick = Shared("OnClick on a widget row", function(self, mouse)
		if JustDragged() then
			return
		end
		local row = self.row
		local key = row and row.key
		local spec = key and specs[key]
		if not spec then
			return
		end
		if mouse == "RightButton" and not spec.rightClick then
			MelloUI:PlayUISound("check_off")
			Rem:Dismiss(key)
			return
		end
		MelloUI:PlayUISound("tab")
		if type(spec.onClick) == "function" then
			Rem:Act(key, mouse)
		elseif type(spec.tray) == "function" then
			SetTray(row, not row.trayOpen)
		end
		if GameTooltip:IsOwned(self) then
			RowTip(self, row)
		end
	end, "script")

	BtnClick = Shared("OnClick on a widget row's button", function(self)
		local a, row = self.action, self.row
		local key = row and row.key
		if not (a and key and specs[key]) then
			return
		end
		if a.secure then
			return   -- (the secure button over it runs it; in combat: nothing)
		end
		MelloUI:PlayUISound("tab")
		if a.tray then
			SetTray(row, not row.trayOpen)
		end
		if type(a.fn) == "function" then
			local ok, err = pcall(a.fn, key)
			if not ok then
				Report(err)
			end
		end
		if GameTooltip:IsOwned(self) then
			BtnTip(self)
		end
	end, "script")

	TrayClick = Shared("OnClick on a widget tray's row", function(self, mouse)
		if self.tray and self.tray.fold then
			FoldTrayClick(self, mouse)
			return
		end
		local e, row = self.entry, self.tray and self.tray.row
		local key = row and row.key
		if not (e and key and specs[key]) then
			return
		end
		MelloUI:PlayUISound("tab")
		if type(e.onClick) == "function" then
			local ok, err = pcall(e.onClick, key, e, mouse)
			if not ok then
				Report(err)
			end
		end
		if row.trayOpen then
			FillTray(row)
		end
	end, "script")

	SecureEnter = Shared("OnEnter on the widget's secure button", function(self)
		local b = CS.secureFor
		if b and b.row and b.row.key then
			if b.action then
				BtnTip(b, self)
			else
				RowTip(self, b.row)
			end
		end
	end, "script")

	-- (over a face: its right click is still Not now; the left one ran the macro)
	SecurePostClick = Shared("PostClick on the widget's secure button", function(_, mouse, down)
		local b = CS.secureFor
		local key = b and not b.action and b.row and b.row.key
		local spec = key and specs[key]
		if down or mouse ~= "RightButton" or not spec or spec.rightClick then
			return
		end
		MelloUI:PlayUISound("check_off")
		Rem:Dismiss(key)
	end, "script")

	SecureLeave = Shared("OnLeave on the widget's secure button", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
		local b = CS.secureFor
		SecureOff()
		if b and b.row then
			EXP.count = #b.row.btns
			Anim:Collapse(b.row.btns, b.row.face, EXP)
		end
	end, "script")

	-- the fold row: what waits in it, a click its list
	FoldEnter = Shared("OnEnter on the widget column's fold row", function(self)
		local P = MelloUI.Look.Palette()   -- (the reskin off: the game's gold and white)
		local gold, text = P.selectedTrim, P.text
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(TEXT.foldTitle, gold[1], gold[2], gold[3])
		local sitting = false
		for i = 1, folded.n do
			local key = folded[i]
			GameTooltip:AddLine(Rem:Label(key), text[1], text[2], text[3])
			sitting = sitting or SitsFightOut(key)
		end
		if sitting then
			GameTooltip:AddLine(TEXT.foldCombat, text[1], text[2], text[3], true)
		end
		GameTooltip:AddLine(TEXT.foldHint, text[1], text[2], text[3], true)
		GameTooltip:Show()
	end, "script")

	FoldLeave = Shared("OnLeave on the widget column's fold row", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end, "script")

	FoldClick = Shared("OnClick on the widget column's fold row", function(self)
		if JustDragged() then
			return
		end
		MelloUI:PlayUISound("tab")
		self.trayOpen = not self.trayOpen
		if self.trayOpen then
			FoldTrayFill(self)
			if not self.tray:IsShown() then
				Anim:FadeIn(self.tray, 0.15)
			end
		elseif self.tray and self.tray:IsShown() then
			Anim:FadeOut(self.tray, 0.12)
		end
	end, "script")

	-- a widget in the fold's list: a click acts as a click on its face, a
	-- right click puts it away (TrayClick hands it on)
	FoldTrayClick = function(self, mouse)
		local key = self.entry
		local spec = key and specs[key]
		if not spec then
			return
		end
		if mouse == "RightButton" and not spec.rightClick then
			MelloUI:PlayUISound("check_off")
			Rem:Dismiss(key)
			return
		end
		MelloUI:PlayUISound("tab")
		if type(spec.onClick) == "function" then
			Rem:Act(key, mouse)
		end
	end

	--------------------------------------------------------------------------
	-- Checks and the queue
	--------------------------------------------------------------------------

	local function Run()
		CS.queued = false
		local any = false
		for i = 1, #colOrder do
			local key = colOrder[i]
			local why = colDirty[key]
			if why then
				local raise = colRaise[key]
				colDirty[key], colRaise[key] = false, false
				local st = states[key]
				local wasActive, wasUp = st.active, st.up
				Check(key, why)
				if not st.active then
					if st.dismissed == "change" or st.dismissed == "moment" then
						st.dismissed = false
					end
					st.up = false
				else
					if raise and st.dismissed == "moment" then
						st.dismissed = false
					end
					if Dismissed(st) then
						st.up = false
					elseif not st.up then
						st.up = true
						CS.serial = CS.serial + 1
						st.since = CS.serial
					end
				end
				if st.active ~= wasActive or st.up ~= wasUp then
					Tell(key)
				end
				any = true
			end
		end
		if any then
			ColLay()
		end
	end

	-- checked on the next frame; raise: a Not now until its next moment is over
	local function ColQueue(key, why, raise)
		if not colDirty[key] or raise then
			colDirty[key] = why or "refresh"
		end
		if raise then
			colRaise[key] = true
		end
		if not CS.queued then
			CS.queued = true
			local Kit = MelloUI.Kit
			if Kit and Kit.NextFrame then
				Kit:NextFrame("Reminders: column", Run)
			else
				C_Timer.After(0, Run)
			end
		end
	end

	--------------------------------------------------------------------------
	-- Core's side (the reminders' functions route a column key here)
	--------------------------------------------------------------------------

	Col.Queue = ColQueue

	function Col.Add(key)
		colOrder[#colOrder + 1] = key
		colDirty[key], colRaise[key] = false, false
		ColQueue(key, "refresh", true)
	end

	function Col.Drop(key)
		for i = #colOrder, 1, -1 do
			if colOrder[i] == key then
				table.remove(colOrder, i)
			end
		end
		colDirty[key], colRaise[key] = false, false
		if col then
			ColLay()
		end
	end

	-- the login moment, a restart: every row checked again
	function Col.All(why)
		for i = 1, #colOrder do
			ColQueue(colOrder[i], why)
		end
	end

	-- one of its own events: a new moment (a Not now until then is over)
	function Col.Event(key, event)
		ColQueue(key, event, true)
	end

	-- combat: the rows that sit it out hidden, the secure button off
	-- (PLAYER_REGEN_DISABLED comes before the lockdown)
	function Col.Combat(on)
		if on then
			SecureOff()
		end
		if col then
			ColLay()
		end
	end

	function Col.Dismissed()
		if col then
			ColLay()
		end
	end

	-- widgetMax changed: laid again with the new cap
	function Col.Relay()
		if col or up.n > 0 or folded.n > 0 then
			ColLay()
		end
	end

	-- a timed Not now run out: raised again while it is wanted
	function Col.Expire(now)
		for i = 1, #colOrder do
			local key = colOrder[i]
			local d = states[key].dismissed
			if type(d) == "number" and now + 0.05 >= d then
				states[key].dismissed = false
				ColQueue(key, "refresh", true)
			end
		end
	end

	function Col.Glows()
		if not col then
			return
		end
		for i = 1, up.n do
			local row = col.rows[i]
			Col.Glow(row, row.key)
		end
	end

	-- a row's glow: low, as the Reminders' glow setting has it; bright, and
	-- pulsing in the "pulse" setting, while its spec's `alert` says so
	function Col.Glow(row, key)
		local spec = key and specs[key]
		local alert = spec and spec.alert ~= nil and Value(spec.alert, key)
		alert = not Secret(alert) and alert == true
		ApplyGlow(row.glow)
		local mode = GlowMode()
		if alert and mode ~= "off" then
			row.glow:SetStrength("reach")
			if mode == "pulse" then
				row.glow:Pulse()
			end
		else
			row.glow:SetStrength(GLOW_LOW)
		end
	end

	-- the crest on a row's rim (spec.crest): the kit's while the kit's unit
	-- frames are on, else the game's own rank icon; made on its first use
	Col.CREST = { rare = { "marks/crest_rare", "rareMark" }, rareelite = { "marks/crest_rareelite", "rareEliteMark" } }
	Col.CREST_SIZE = 0.38   -- of the face (the sketch's 24 on a 62 face)
	function Col.Crest(row, kind)
		local art = type(kind) == "string" and not Secret(kind) and Col.CREST[kind] or nil
		local tex = row.crest
		if not art then
			if tex then
				tex:Hide()
				tex.kind = nil
			end
			return
		end
		if not tex then
			tex = row.face:CreateTexture(nil, "OVERLAY", nil, 7)
			tex:SetSize(FACE * Col.CREST_SIZE, FACE * Col.CREST_SIZE)
			tex:SetPoint("CENTER", row.face, "TOP", 0, -2)
			row.crest = tex
		end
		local Kit = KitOn()
		if Kit and Kit.Apply then
			Kit:Apply(tex, art[1])   -- look-ok: the kit's crest while the kit's unit frames are on (KitOn)
		else
			tex:SetAtlas((select(2, Look.Art(art[2]))))
		end
		tex.kind = kind
		tex:Show()
	end

	function Col.Source()
		if not col and ColOn() then
			ColBuild()
		end
	end

	function Rem:Tray(key, open)
		if not (col and key) then
			return
		end
		for i = 1, up.n do
			local row = col.rows[i]
			if row.key == key then
				if open == nil then
					open = not row.trayOpen
				end
				SetTray(row, open)
				return
			end
		end
	end

	-- a shown row's title, line and ring share set now, each when it is
	-- given and changed (the Navigation arrow's distance as the player
	-- walks: a Refresh would lay the whole row again); nothing for a row not
	-- up (its next fill reads the spec)
	function Rem:SetLines(key, title, text, share)
		if not (col and key) then
			return
		end
		for i = 1, up.n do
			local row = col.rows[i]
			if row.key == key and row:IsShown() then
				if type(title) == "string" and title ~= row.liveTitle then
					row.liveTitle = title
					row.title:SetText(title)
				end
				if type(text) == "string" and text ~= row.liveText then
					row.liveText = text
					row.text:SetText(text)
				end
				if type(share) == "number" and share ~= row.liveShare and not row.pDur then
					TURN.Share(row, share)
				end
				return
			end
		end
	end

	-- a subtitle's page fits the rows' subtitle lines whole (Voice Over's
	-- pages): measured by an unseen copy of the line (made the first time)
	function Rem:SubFits(text)
		if not col then
			return true
		end
		local m = col.measure
		if not m then
			m = col.holder:CreateFontString(nil, "OVERLAY")
			Font(m, SUB_SIZE)
			m:SetWidth(SUB_W)
			m:SetWordWrap(true)
			if m.SetMaxLines then
				m:SetMaxLines(SUB_LINES)
			end
			m:SetAlpha(0)
			col.measure = m
		end
		m:SetText(text)
		return not (m.IsTruncated and m:IsTruncated())
	end

	-- the column back at its standard place (/vo reset)
	function Rem:ResetColumnPlace()
		MelloUI:ForgetPosition(COL_KEY)
		if col then
			ColHome(col.holder)
		end
	end

	-- for tests and dumps (read only)
	Rem.column, Rem.columnFolded = up, folded
	function Rem:Column()
		return col
	end

	-- /mello widgets (0.16.0, the user's home test: a second widget did not
	-- show beside Voice Over): the column as it stands, into the copy window
	local function Where(frame)
		local p, rel, rp, x, y = frame:GetPoint(1)
		local l, b, r, t = MelloUI.Safe.ScreenRect(frame)
		local rect = l and string.format("screen %d,%d .. %d,%d", l, b, r, t) or "screen ?"
		return string.format("%s>%s:%s(%s,%s) %dx%d a=%.2f %s %s", tostring(p), tostring(rel and (rel.GetName and rel:GetName() or "?")),
			tostring(rp), tostring(Num(x) and math.floor(x + 0.5)), tostring(Num(y) and math.floor(y + 0.5)),
			Num(frame:GetWidth()) or -1, Num(frame:GetHeight()) or -1, Num(frame:GetAlpha()) or -1,
			frame:IsShown() and "shown" or "hidden", rect)
	end

	function Rem:DumpColumn()
		MelloUI:ClearLog()
		local function P(...)
			MelloUI:Print(...)
		end
		P("Widget column: combat %s, most shown %d, lock %s, %d registered", tostring(S.combat), Cap(),
			tostring(Setting("widgetLock")), #colOrder)
		if col then
			P("  holder %s scale %.2f", Where(col.holder), Num(col.holder:GetEffectiveScale()) or -1)
		else
			P("  holder not made yet")
		end
		for i = 1, #colOrder do
			local key = colOrder[i]
			local st, spec = states[key], specs[key]
			P("  %s: on %s, active %s, up %s, dismissed %s, since %s, place %s%s, dirty %s", key, tostring(Enabled(key)),
				tostring(st.active), tostring(st.up), tostring(st.dismissed), tostring(st.since), tostring(spec.bottom and "bottom"
				or spec.priority or "ongoing"), spec.combat == false and " (steps aside in a fight)" or "", tostring(colDirty[key]))
		end
		local shown, waiting = {}, {}
		for i = 1, up.n do
			shown[i] = tostring(up[i])
		end
		for i = 1, folded.n do
			waiting[i] = tostring(folded[i])
		end
		P("  shown (bottom first): %s; folded: %s", table.concat(shown, ", "), table.concat(waiting, ", "))
		if col then
			for i = 1, #col.rows do
				local row = col.rows[i]
				P("  row %d %s: %s", i, tostring(row.key), Where(row))
			end
			if col.fold then
				P("  fold row: %s", Where(col.fold))
			end
		end
		P("  last error: %s", tostring(CS.lastError or "none"))
		-- the reminders by the portrait (bags, talents, Well Fed ...)
		P("Reminders by the portrait: login run %s, combat %s", tostring(S.login), tostring(S.combat))
		for i = 1, #order do
			local key = order[i]
			local st = states[key]
			local line = Value(specs[key].text, key)
			P("  %s: on %s, active %s, up %s, dismissed %s, says %s", key, tostring(Enabled(key)), tostring(st.active),
				tostring(st.up), tostring(st.dismissed), Secret(line) and "(secret)" or tostring(line))
		end
		MelloUI:ShowLog("widgets")
	end
end
Column()

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
	local column = specs[key].column
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
	if column then
		Col.Drop(key)
	elseif wasUp and ui then
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
	-- player moves while it is up (a column row: none)
	st.byKind = not spec.column and type(spec.kind) == "string"
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
	if spec.column then
		st.since = st.since or 0
		Col.Add(key)
		return key
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
		Col.All("refresh")
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
	Col.Expire(now)
end)

function Rem:Dismiss(key, untilWhat)
	local st, spec = states[key], specs[key]
	if not (st and spec) then
		return
	end
	local d = untilWhat
	if d == nil then
		-- (one staying up now, as any of the four in a rest area: until the
		-- player leaves one and comes back)
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
		if spec.column then
			Col.Dismissed()
		elseif ui then
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

-- Stay Up In Rest Areas: the one switch (on while not saved) and the player
-- resting now, read when asked (at the end of a hold, a Not now): nothing
-- kept, nothing made
function Rem:StayUp()
	if Setting("stayResting") == false then
		return false
	end
	local fn = _G.IsResting
	if type(fn) ~= "function" then
		return false
	end
	local ok, resting = pcall(fn)
	if not ok or Secret(resting) then
		return S.town == true
	end
	-- (or in a town: S.town, measured at each subzone change)
	return (resting or S.town == true) and true or false
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

-- Edit Layout's source (Core's list; run at each of its opens and resumes,
-- never at login): the widget made, so its place can be set before any
-- reminder came up -- while the Reminders module is on and a reminder is
-- registered (its users are there). Built once; nothing new after that.
local function MoverSource()
	if not ui and S.events and RemindersOn() then
		Build()
	end
	Col.Source()
end
if MelloUI.AddMoverSource then
	MelloUI:AddMoverSource(MoverSource)
end

-- for tests and dumps (read only): the widget once made, the moment's state,
-- the ranked list up
Rem.state = S
Rem.list = list
function Rem:Widget()
	return ui
end
