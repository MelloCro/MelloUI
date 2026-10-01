--------------------------------------------------------------------------------
-- MelloUI - Fader (0.17.0)
--
-- One system that fades parts of the UI away while they are not needed (the
-- user, 2026-10-01: "players can pick and choose which UI element or action
-- bar, or chat, minimap, party frames, microbar, bag bar, quest tracker etc
-- can fade when out of combat, some people like to have their whole UI fade
-- out when not in combat", and later "not only ... fade out of combat, but
-- also to show on mouseover"; docs/plans/fader-0.17.md). The engine of Unit
-- Frames' Fade Out Of Combat (0.14.0) lifted here: one fader, every element
-- on it. Its settings are the Fader module's (Modules/Fader.lua: the page,
-- the element list, the player frame's own reasons).
--
--   local Fader = MelloUI.Fader
--   Fader:Register(el)   one element (registered again: replaced)
--     key       a unique string; its setting is the Fader module's
--               "show_<key>": "always" (never faded, the default), "combat"
--               (faded out of combat, back in a fight) or "mouseover" (faded
--               all the time, a fight too, shown while the pointer is on it)
--     frames    fn() -> { frame, ... }: the frames whose OWN alpha is faded
--               (their children fade with them)
--     mouse     fn() -> { frame, ... }: the frames that take the pointer
--               (the bar's buttons, not only the bar: a bar never hears an
--               OnEnter its buttons take); hooked once each, out of combat
--     needed    fn() -> true while it must show anyway (its own reasons: the
--               player frame while you are hurt, the chat while you type)
--     follows   the key of the element whose choice it takes while the
--               setting `followsWhen` (a Fader key) is on (the pet frame:
--               the player frame's, Pet Frame Too); it shows whenever that
--               one shows, and otherwise is "always"
--     own       fn() -> { frame, ... }: frames under it that keep their own
--               alpha while it fades (they ignore the parent's; their old
--               setting back after; out of combat): the player frame's pet
--               frame and cast bar
--     watch     fn(on): its own events on or off with the element
--     fixedBase the alpha its frames are kept at by MelloUI (the chat's: 1):
--               a write of the game's on them is answered with the fade
--               (counted), never taken as their new alpha
--   Fader:Host(key)       (0.17.0, the user's test: MelloUI's own parts that
--                         fade their own alpha -- the reminders, the widget
--                         column, Route's arrow and World Marker) a plain
--                         frame over the screen that such a part is parented
--                         to; the Fader fades the host, nobody else writes
--                         its alpha. Made on first ask (when the part is)
--   Fader:Holds(frame)    the Fader has the frame's alpha now (the chat's
--                         own hold of its line, ChatPanel's, steps aside)
--   Fader:Poke()          something an element's reasons hang on changed:
--                         looked at again on the next frame (one look a frame)
--   Fader:Shown(key)      the element is shown (or not faded) now
--   Fader:Mode(key)       its choice as it applies now
--   Fader:Start(db) / Fader:Stop()   the module on / off (its settings)
--   Fader:Changed(key)    a Fader setting changed (from the module)
--   Fader.T               the timings (read only)
--
-- When an element is back (both choices): Edit Layout, Edit Mode or the
-- configurator open; its own reasons; the pointer on it (In Combat: with
-- Also Show On Mouseover). In Combat also: a fight, and a target (Show With A
-- Target). A pointer leaving an On Mouseover element fades it after a short
-- grace (T.GRACE: crossing from one button to the next does not flicker);
-- anything else waits Fade After. Out at Fade Speed, in fast (T.IN); a fight
-- brings the In Combat ones back at once (no tween racing the fight). Through
-- MelloUI.Anim (Reduce Motion: at once).
--
-- Alpha only: never Show, Hide or SetPoint (most of these frames are secure;
-- SetAlpha is allowed on them in a fight too). Never fight a game alpha: the
-- fade is relative to the alpha the frame had (Edit Mode's Opacity of the
-- unit and aura frames), learned before the first fade and from a post-hook
-- on its SetAlpha (a write not ours: the new base, the fade put on it again;
-- a frame written again within T.BUSY is left as written, counted by
-- Perf.WriteBack). Released, a frame gets its base back.
--
-- Nothing is made, hooked or registered while the module is off: the event
-- frame and the bus listeners come with Start; the pointer hooks (post-hooks,
-- which cannot be taken off) are inert after Stop. No ticker, no OnUpdate:
-- the holds are timers (one pending at most), the fades are Anim's.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Fader")
local C_Timer = Perf.C_Timer
local Shared = Perf.Shared

local Secret = MelloUI.Safe.IsSecret
local Finite = MelloUI.Safe.Finite
local pcall, type, ipairs, GetTime = pcall, type, ipairs, GetTime

local Fader = {
	T = {
		IN = 0.15,      -- s: the way back in
		GRACE = 0.3,    -- s: an On Mouseover element after the pointer left
		AFTER = 1.5,    -- s: Fade After's default (the unit frames' old hold)
		SPEED = 0.6,    -- s: Fade Speed's default (their old fade)
		MAX = 0.5,      -- Faded Opacity's top
		BUSY = 0.5,     -- s: a frame the game writes again within this is left to it
	},
	elements = {},   -- in order registered
	byKey = {},
}
MelloUI.Fader = Fader

local T = Fader.T
local OWNER = "Fader"
local HOOK_KEY = "Fader: the pointer hooks"
local OWN_KEY = "Fader: the frames that keep their own alpha"
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
	"GROUP_ROSTER_UPDATE" }

-- the engine's state: on, combat, editMode; db (the module's settings);
-- st[key] = { active, mode, state ("shown" / "faded" / nil), due (a hold's
-- end), over (the pointer on it), lost (it heard the pointer leave while
-- the pointer is still on its rect) }; base[frame] (its alpha before us),
-- want[frame] (the alpha we last asked for), owner[frame] (its element's
-- key), foreign[frame] (the last write not ours); hooked[frame] (pointer
-- hooks), watched[frame] (the SetAlpha post-hook), kept[frame] (an own
-- frame's ignore-parent-alpha before); queued (a look on the next frame),
-- nextDue (the pending hold timer's time)
local S = { on = false, combat = false, editMode = false, db = nil, st = {}, base = {}, want = {}, owner = {},
	foreign = {}, hooked = {}, watched = {}, kept = {}, queued = false, nextDue = nil, events = nil }
Fader.state = S   -- (read only: the tests')

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

-- fn's yes (a secret, an error or no function: no)
local function Yes(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	local ok, v = pcall(fn, ...)
	return ok and not Secret(v) and v and true or false
end

local function Setting(key, default)
	local db = S.db
	local v = db and db[key]
	if v == nil then
		return default
	end
	return v
end

local function FadedAlpha()
	local a = Finite(tonumber(Setting("alpha", 0))) or 0
	return a < 0 and 0 or a > T.MAX and T.MAX or a
end

local function After()
	local a = Finite(tonumber(Setting("after", T.AFTER))) or T.AFTER
	return a < 0 and 0 or a
end

local function Speed()
	local a = Finite(tonumber(Setting("speed", T.SPEED))) or T.SPEED
	return a < 0.05 and 0.05 or a
end

local function List(fn)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, list = pcall(fn)
	return ok and type(list) == "table" and list or nil
end

-- what an element's setting says (the module's "show_<key>"); a follower
-- takes its leader's while its switch is on, else "always"
function Fader:Mode(key)
	local el = self.byKey[key]
	if not el or not S.on then
		return "always"
	end
	if el.follows then
		if Setting(el.followsWhen or "", true) == false then
			return "always"
		end
		return self:Mode(el.follows)
	end
	local m = Setting("show_" .. key, "always")
	return (m == "combat" or m == "mouseover") and m or "always"
end

function Fader:Shown(key)
	local st = S.st[key]
	return not (st and st.active and st.state == "faded")
end

-- Edit Layout, Edit Mode or the configurator open: every element shows
local function Editing()
	if S.editMode or MelloUI:EditingLayout() then
		return true
	end
	local cfg = rawget(_G, "MelloUIConfigFrame")
	return cfg ~= nil and Yes(cfg.IsShown, cfg)
end

-- the pointer on one of its frames' rects, on screen (a secret answer: not)
local function OnRect(el)
	for _, f in ipairs(List(el.frames) or {}) do
		if Yes(f.IsVisible, f) and Yes(f.IsMouseOver, f) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- The alpha: relative to the frame's own, never fighting a write of the game
--------------------------------------------------------------------------------

local Watch   -- (below)

local function Base(frame)
	local b = S.base[frame]
	if b == nil then
		local el = Fader.byKey[S.owner[frame] or ""]
		local ok, a = pcall(frame.GetAlpha, frame)
		b = (el and el.fixedBase) or (ok and not Secret(a) and Finite(a)) or 1
		S.base[frame] = b
		if not S.watched[frame] then
			S.watched[frame] = true
			Perf.hooksecurefunc(frame, "SetAlpha", Watch)
		end
	end
	return b
end

-- seen: a secret answer counts as seen (the move is only a tween)
local function Seen(frame)
	local ok, seen = pcall(frame.IsVisible, frame)
	if ok and Secret(seen) then
		return true
	end
	return ok and seen and true or false
end

local function Write(frame, share, duration, easing)
	local a = Base(frame) * share
	S.want[frame] = a
	if duration and duration > 0 and Seen(frame) then
		MelloUI.Anim:To(frame, "alpha", a, duration, easing)
	else
		MelloUI.Anim:Stop(frame, "alpha")
		frame:SetAlpha(a)
	end
end

-- a write on a faded frame: ours (the tween's steps, what we asked for) or
-- the game's (its new base, the fade put on it again unless it is busy)
Watch = function(frame, a)
	local key = S.owner[frame]
	if not key or Secret(a) or S.want[frame] == nil then
		return
	end
	a = tonumber(a)
	if not a or MelloUI.Anim:IsRunning(frame, "alpha") or math.abs(a - S.want[frame]) < 0.002 then
		return
	end
	local now = GetTime()
	local busy = S.foreign[frame] and now - S.foreign[frame] < T.BUSY
	S.foreign[frame] = now
	local st = S.st[key]
	local share = st and st.state == "faded" and FadedAlpha() or 1
	local el = Fader.byKey[key]
	if el and el.fixedBase then
		-- (a part MelloUI keeps at its own alpha: the game's write answered)
		if not busy then
			if MelloUI.Perf.WriteBack then
				MelloUI.Perf.WriteBack("Fader: " .. key)
			end
			frame:SetAlpha(S.want[frame])
		end
		return
	end
	S.base[frame] = a   -- (the game's own alpha, as the game means it)
	if share == 1 or busy then
		S.want[frame] = a   -- (taken as it is)
		return
	end
	-- (a game write on a faded frame: the fade on its new alpha; counted)
	if MelloUI.Perf.WriteBack then
		MelloUI.Perf.WriteBack("Fader: " .. key)
	end
	S.want[frame] = a * share
	frame:SetAlpha(a * share)
end

local function Bring(el, st, instant)
	if st.state == "shown" then
		return
	end
	st.state = "shown"
	for _, f in ipairs(List(el.frames) or {}) do
		S.owner[f] = el.key
		Write(f, 1, not instant and T.IN or 0, "outQuad")
	end
end

local function Dim(el, st)
	if st.state == "faded" then
		return
	end
	st.state = "faded"
	local share = FadedAlpha()
	for _, f in ipairs(List(el.frames) or {}) do
		S.owner[f] = el.key
		Write(f, share, Speed(), "inOutQuad")
	end
end

-- an element let go: its frames back to their own alpha at once
local function Release(el, st)
	if st.state == nil then
		return
	end
	st.state = nil
	for _, f in ipairs(List(el.frames) or {}) do
		if S.owner[f] == el.key then
			MelloUI.Anim:Stop(f, "alpha")
			local b = S.base[f] or 1
			S.owner[f], S.want[f], S.base[f], S.foreign[f] = nil, nil, nil, nil
			f:SetAlpha(b)
		end
	end
end

--------------------------------------------------------------------------------
-- The look: needed now, else after its hold
--------------------------------------------------------------------------------

local Look   -- (below)

-- one shared timer function: a look that settles the holds that are over
-- (a timer that finds a later hold reschedules it; an extra look is harmless)
local HoldDone = Shared("the Fader's hold", function()
	S.nextDue = nil
	Look(true)
end)

local function Schedule(due)
	if S.nextDue and S.nextDue <= due and S.nextDue > GetTime() then
		return   -- (a sooner look is pending: it schedules the next)
	end
	S.nextDue = due
	C_Timer.After(math.max(0.01, due - GetTime()), HoldDone)
end

-- the preview's pretend fight (Core/Preview.lua: between its pull and its
-- kill, while it plays the Fader's part) counts as a fight for the In Combat
-- elements
local function Pretend()
	local P = MelloUI.Preview
	return P ~= nil and P:Fighting() and P:Plays("fader")
end

local function Needed(el, st)
	if Editing() then
		return true
	end
	if el.needed and Yes(el.needed) then
		return true
	end
	local mode = st.mode
	if (st.over or (st.lost and OnRect(el))) and (mode == "mouseover" or Setting("mouse", true) ~= false) then
		return true
	end
	if el.follows and Fader:Shown(el.follows) and S.st[el.follows] and S.st[el.follows].active then
		return true
	end
	if mode == "combat" then
		if S.combat or InCombatLockdown() or Pretend() then
			return true
		end
		if Setting("target", true) ~= false and Yes(UnitExists, "target") then
			return true
		end
	end
	return false
end

-- settle: the holds that are over end now (their timer)
Look = function(settle)
	if not S.on then
		return
	end
	local now = GetTime()
	local soonest
	for _, el in ipairs(Fader.elements) do
		local st = S.st[el.key]
		if st and st.active then
			if st.lost and not OnRect(el) then
				st.lost = false   -- (the pointer gone from it at last)
			end
			if Needed(el, st) then
				st.due = nil
				Bring(el, st, st.instant)
				st.instant = nil
			elseif el.follows and S.st[el.follows] and S.st[el.follows].state == "faded" then
				-- (a follower goes with its leader: the pet frame with the player's)
				st.due = nil
				Dim(el, st)
			elseif st.state ~= "faded" then
				if not st.due then
					st.due = now + (st.leftAt and st.mode == "mouseover" and T.GRACE or After())
				end
				if settle and now + 0.02 >= st.due then
					st.due = nil
					Dim(el, st)
				else
					soonest = soonest and math.min(soonest, st.due) or st.due
				end
			end
			st.leftAt = nil
			-- (the pointer still on a frame that heard it leave: looked at again)
			if st.lost and st.state ~= "faded" and not soonest then
				soonest = now + math.max(After(), 0.5)
			end
		end
	end
	if soonest then
		Schedule(soonest)
	end
end

local function LookSoon()
	if S.queued or not S.on then
		return
	end
	S.queued = true
	C_Timer.After(0, function()
		S.queued = false
		Look()
	end)
end

function Fader:Poke()
	LookSoon()
end

-- MelloUI's own parts that fade their own alpha sit on a host the Fader fades
Fader.hosts = {}

function Fader:Host(key)
	local h = self.hosts[key]
	if not h then
		h = CreateFrame("Frame", "MelloUIFadeHost_" .. key, UIParent)
		h:SetAllPoints(UIParent)
		self.hosts[key] = h
	end
	return h
end

function Fader:Holds(frame)
	return S.on and S.owner[frame] ~= nil
end

--------------------------------------------------------------------------------
-- The pointer: one pair of hooks per frame, for every element that has it
--------------------------------------------------------------------------------

local OnEnter = Shared("OnEnter on a faded element: the Fader", function(self)
	local key = S.hooked[self]
	local st = key and S.st[key]
	if not (S.on and st and st.active) then
		return
	end
	st.over, st.lost, st.due = true, false, nil
	Look()
end, "script")

local OnLeave = Shared("OnLeave on a faded element: the Fader", function(self)
	local key = S.hooked[self]
	local st = key and S.st[key]
	local el = key and Fader.byKey[key]
	if not (S.on and st and st.active and el) then
		return
	end
	st.over = false
	st.lost = OnRect(el)
	st.leftAt = GetTime()
	st.due = nil
	Look()
end, "script")

local function HookMouse(el)
	for _, f in ipairs(List(el.mouse) or List(el.frames) or {}) do
		if type(f) == "table" and f.HookScript and S.hooked[f] == nil then
			S.hooked[f] = el.key
			Perf.HookScript(f, "OnEnter", OnEnter)
			Perf.HookScript(f, "OnLeave", OnLeave)
		end
	end
end

local function HookAll()
	for _, el in ipairs(Fader.elements) do
		local st = S.st[el.key]
		if st and st.active then
			HookMouse(el)
		end
	end
end

-- the frames under an element that keep their own alpha while it is active
local function OwnAlphaNow()
	for _, el in ipairs(Fader.elements) do
		local st = S.st[el.key]
		local on = S.on and st and st.active
		for _, f in ipairs(List(el.own) or {}) do
			if f.SetIgnoreParentAlpha then
				if on then
					if S.kept[f] == nil then
						local ok, was = pcall(f.IsIgnoringParentAlpha, f)
						S.kept[f] = (ok and not Secret(was) and was) and true or false
					end
					f:SetIgnoreParentAlpha(true)
				elseif S.kept[f] ~= nil then
					f:SetIgnoreParentAlpha(S.kept[f])
					S.kept[f] = nil
				end
			end
		end
	end
end

-- (the kit is loaded by the time the Fader starts: the module's OnEnable)
local function OutOfCombat(fn, key)
	MelloUI.Kit:WhenOutOfCombat(fn, key)
end

--------------------------------------------------------------------------------
-- The elements' choices applied
--------------------------------------------------------------------------------

-- every element's state from its choice now (the module's settings)
local function Sync()
	for _, el in ipairs(Fader.elements) do
		local st = S.st[el.key]
		if not st then
			st = {}
			S.st[el.key] = st
		end
		local mode = Fader:Mode(el.key)
		local active = S.on and mode ~= "always"
		if active ~= (st.active or false) and type(el.watch) == "function" then
			pcall(el.watch, active)
		end
		if not active then
			Release(el, st)
			st.due, st.over, st.lost = nil, false, false
		elseif st.mode ~= mode then
			st.due = nil
		end
		st.active, st.mode = active, mode
	end
	OutOfCombat(HookAll, HOOK_KEY)
	OutOfCombat(OwnAlphaNow, OWN_KEY)
	Look()
end

local OnEvent = function(_, event)
	if not S.on then
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		S.combat = true
		-- (the In Combat ones back at once: no tween racing the fight)
		for _, el in ipairs(Fader.elements) do
			local st = S.st[el.key]
			if st and st.active and st.mode == "combat" and st.state == "faded" then
				st.instant = true
			end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		S.combat = false
		OutOfCombat(HookAll, HOOK_KEY)   -- (a group's new frames, hooked now)
	elseif event == "PLAYER_ENTERING_WORLD" then
		S.combat = InCombatLockdown() or Yes(UnitAffectingCombat, "player")
	elseif event == "GROUP_ROSTER_UPDATE" then
		OutOfCombat(HookAll, HOOK_KEY)
	end
	Look()
end

local function OnEditLayout()
	Look()
end

-- the preview's beats: its pull brings the In Combat ones back at once (as
-- a fight does), its kill and its stop let them fade as after one
local function OnPreview(beat)
	if beat == "pull" and Pretend() then
		for _, el in ipairs(Fader.elements) do
			local st = S.st[el.key]
			if st and st.active and st.mode == "combat" and st.state == "faded" then
				st.instant = true
			end
		end
		Look()
	elseif beat == "kill" or beat == "stop" then
		Look()
	end
end

local function OnEditMode(entering)
	S.editMode = entering and true or false
	Look()
end

--------------------------------------------------------------------------------
-- The registry and the module's calls
--------------------------------------------------------------------------------

function Fader:Register(el)
	if type(el) ~= "table" or type(el.key) ~= "string" then
		return
	end
	local old = self.byKey[el.key]
	if old then
		for i, e in ipairs(self.elements) do
			if e == old then
				self.elements[i] = el
				break
			end
		end
	else
		self.elements[#self.elements + 1] = el
	end
	self.byKey[el.key] = el
	if S.on then
		Sync()
	end
end

function Fader:Start(db)
	S.db = db
	if not S.on then
		S.on = true
		if not S.events then
			S.events = CreateFrame("Frame")
			Perf.SetScript(S.events, "OnEvent", OnEvent)
		end
		for _, e in ipairs(EVENTS) do
			S.events:RegisterEvent(e)
		end
		MelloUI:On("editlayout", OnEditLayout, OWNER)
		MelloUI:On("editmode", OnEditMode, OWNER)
		-- (the configurator: looked at on the next frame -- inside its OnHide
		-- it may still read as shown)
		MelloUI:On("configurator", LookSoon, OWNER)
		MelloUI:On("preview", OnPreview, OWNER)
		S.combat = InCombatLockdown() or Yes(UnitAffectingCombat, "player")
		S.editMode = MelloUI.EditModeOpen and MelloUI.EditModeOpen() or false
	end
	Sync()
end

function Fader:Stop()
	if not S.on then
		return
	end
	S.on = false
	if S.events then
		S.events:UnregisterAllEvents()
	end
	MelloUI:Off(OWNER)
	for _, el in ipairs(self.elements) do
		local st = S.st[el.key]
		if st then
			if st.active and type(el.watch) == "function" then
				pcall(el.watch, false)
			end
			Release(el, st)
			st.active, st.mode, st.due, st.over, st.lost = false, nil, nil, false, false
		end
	end
	S.nextDue = nil
	OutOfCombat(OwnAlphaNow, OWN_KEY)
end

-- a setting changed: the choices again; a new Faded Opacity on what is faded
function Fader:Changed(key)
	if not S.on then
		return
	end
	if key == "alpha" then
		local share = FadedAlpha()
		for _, el in ipairs(self.elements) do
			local st = S.st[el.key]
			if st and st.active and st.state == "faded" then
				for _, f in ipairs(List(el.frames) or {}) do
					Write(f, share, T.IN, "outQuad")
				end
			end
		end
		return
	end
	Sync()
end

-- (the tests: the element's state)
function Fader:StateOf(key)
	return S.st[key]
end

-- a frame that joins an element now (made after the element's state was
-- set: the preview's stand-in party frames, in its frames list from then on)
-- takes that state at once
function Fader:Join(key, frame)
	local st = S.on and S.st[key]
	if not (st and st.active and st.state and frame) then
		return
	end
	S.owner[frame] = key
	Write(frame, st.state == "faded" and FadedAlpha() or 1, 0)
end
