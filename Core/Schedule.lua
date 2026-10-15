--------------------------------------------------------------------------------
-- MelloUI - Schedule
--
-- (one look, stage D1, 2026-10-15: out of Modules/Kit.lua, the kit's generic
-- services for every file, painted or not.) When work runs: the next frame
-- (one timer a frame for every key), after the fight (the combat queue for
-- geometry on a protected frame's children) or once the queue is idle, and
-- the UI scale / Edit Mode watcher, the one source of the bus's 'scale' and
-- 'editmode' topics (Core.lua).
--
--   MelloUI.Schedule:NextFrame(key, fn)            fn(key) once on the next frame
--   MelloUI.Schedule:WhenOutOfCombat(fn, key)      fn() now, or after the fight
--   MelloUI.Schedule:WhenQueueIdle(fn)             fn() once the queue is through
--   MelloUI.Schedule:IsQueueBusy()                 in combat, or queued work waiting
--   MelloUI.Schedule:SetFrameScale(frame, scale, setScale) -> changed, laid
--   MelloUI.Schedule:OnUIScaleChanged(fn)          the bus's 'scale', counted
--   MelloUI.Schedule:RefitForScale(reason)         the refit, at once
--   MelloUI.Schedule:ScheduleScaleRefit(reason)    the refit, a moment later
--   /uiscaledump [refit]
-- Every method ignores self: Kit's old names (Kit:NextFrame,
-- Kit:WhenOutOfCombat, ...) are these same functions. The kit's own part of a
-- refit (its shadows, its backgrounds) is looked up on MelloUI.Kit when it
-- runs, so a world without the kit refits nothing of it.
-- Nothing is made at load but the combat queue's frame and the scale
-- watcher's (both made by the kit at load before).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("Schedule")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Secret = MelloUI.Safe.IsSecret

local S = { scaleListenerCount = 0 }   -- (how many came through S:OnUIScaleChanged, for /uiscaledump)
MelloUI.Schedule = S

--------------------------------------------------------------------------------
-- The next frame
--------------------------------------------------------------------------------
-- S:NextFrame(key, fn): fn(key) once on the next frame, however often it
-- was asked for before then (audit, 2026-09-24: panels kept a pending flag
-- each and made a new closure for C_Timer.After(0) on every ask). One timer
-- a frame for every key. A key asked for again before it ran runs once, in
-- the place it was first asked for, with the fn given last. `fn` is made
-- once by the caller -- a file's own function, handed the key (the skin or
-- frame it works on) -- so an ask makes no closure. An error in one is
-- reported and the rest still run. A key asked for while they run (from
-- inside one of them) waits for the frame after once it has run; one still
-- waiting further on in the same run runs there only, with the fn given last
-- (review, 2026-09-24: it ran twice, then and on the next frame).
do
	local nextKeys, nextFns = {}, {}   -- the keys in the order asked, [key] = its fn
	local runKeys, runFns = {}, {}     -- the same two, emptied as they run
	local nextQueued = false

	local function RunNextFrame()
		nextQueued = false
		local keys, fns = nextKeys, nextFns
		nextKeys, nextFns, runKeys, runFns = runKeys, runFns, keys, fns
		for i = 1, #keys do
			local key = keys[i]
			local fn = fns[key]
			keys[i], fns[key] = nil, nil
			local ok, err = pcall(fn, key)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end

	function S:NextFrame(key, fn)
		if key == nil or type(fn) ~= "function" then
			return
		end
		if runFns[key] ~= nil then
			runFns[key] = fn   -- (still waiting in the run under way)
			return
		end
		if nextFns[key] == nil then
			nextKeys[#nextKeys + 1] = key
		end
		nextFns[key] = fn
		if not nextQueued then
			nextQueued = true
			C_Timer.After(0, RunNextFrame)
		end
	end
end

--------------------------------------------------------------------------------
-- Combat: geometry on a protected frame's children is refused while the
-- player is in combat; the HUD modules queue it here and it runs at
-- PLAYER_REGEN_ENABLED (at once when out of combat). A refit hook on the
-- game's own layout method goes through the same queue.
-- A fight can leave a lot queued (/melloperf 2026-09-24: 16.8 ms in the
-- frame the fight ended): it runs in order, a few ms of it per frame, and
-- stops if a new fight starts before it is through (the rest waits for that
-- one to end). The same work queued twice in a row runs once. Anything asked
-- for out of combat while some is still waiting goes in behind it, in the
-- same slices, so the order is kept and no frame pays for the lot; what a
-- queued piece asks for runs at once, as it did.
-- A caller can name its work: S:WhenOutOfCombat(fn, key), the key being
-- the frame or rep it refits. Asked for again under the same key while the
-- first is still waiting, the waiting one is dropped and the new one goes in
-- at the end: a fight's many asks for one refit (a hook on every target
-- change makes a new closure each time) run once, last, as the last of them
-- did. Only for work that just re-reads the frame: an on / off pair must not
-- share a key.
--------------------------------------------------------------------------------
local combatQueue, queueAt = {}, 1   -- the queued work and the next piece to run
local queueKeys = {}                 -- [index] = the key its piece was queued under
local waitingKeys = {}               -- [key] = the index of that key's piece still waiting
local QUEUE_BUDGET = 3               -- ms of queued work per frame after a fight
local runningQueued = false
local combatFrame = CreateFrame("Frame")
combatFrame:Hide()

-- S:WhenQueueIdle(fn): fn() once the queue is through, for work that can
-- wait and must not add to the frames the queue works in (the windows built
-- ahead in idle turns). On the next frame when out of combat with nothing
-- waiting; else on the frame after the last queued piece ran, after the
-- fight's end (a new fight before then keeps it waiting). Never at once, so
-- an fn that asks again goes on a frame later, not inside itself. The same
-- fn asked for again while it waits runs once (still waiting further on in
-- a run under way: there only). An error in one is reported and the rest
-- still run. S:IsQueueBusy(): in combat, or queued work still waiting.
-- QueueIdleWaiters(): the queue's end hands on to them.
local QueueIdleWaiters
do
	local idleWaiters, idleRunning = {}, {}   -- the fns in the order asked; the same, being run
	local idleQueued = false
	local runFrom, runTo = 1, 0               -- idleRunning[runFrom..runTo]: yet to run in this one

	local function QueueBusy()
		return InCombatLockdown() or queueAt <= #combatQueue
	end

	local function RunIdleWaiters()
		idleQueued = false
		if QueueBusy() then
			return   -- a new fight or new work since: they wait for that to be through
		end
		local list = idleWaiters
		idleWaiters, idleRunning = idleRunning, list
		runTo = #list
		for i = 1, runTo do
			runFrom = i + 1
			local fn = list[i]
			list[i] = nil
			local ok, err = pcall(fn)
			if not ok then
				geterrorhandler()(err)
			end
		end
		runFrom, runTo = 1, 0
	end

	function QueueIdleWaiters()
		if not idleQueued and idleWaiters[1] ~= nil then
			idleQueued = true
			C_Timer.After(0, RunIdleWaiters)
		end
	end

	function S:WhenQueueIdle(fn)
		if type(fn) ~= "function" then
			return
		end
		for i = runFrom, runTo do
			if idleRunning[i] == fn then
				return
			end
		end
		for i = 1, #idleWaiters do
			if idleWaiters[i] == fn then
				return
			end
		end
		idleWaiters[#idleWaiters + 1] = fn
		if not QueueBusy() then
			QueueIdleWaiters()
		end
	end

	function S:IsQueueBusy()
		return QueueBusy()
	end
end

-- Runs what waits, in order; with a budget only until that many ms have
-- gone (the frame's OnUpdate goes on with the rest). An error in one piece
-- is reported and the rest still run. A dropped piece is a false.
local function RunQueued(budget)
	local t0 = budget and debugprofilestop()
	while queueAt <= #combatQueue do
		if InCombatLockdown() then
			combatFrame:Hide()
			return
		end
		local at = queueAt
		local fn, key = combatQueue[at], queueKeys[at]
		queueAt = at + 1
		if key ~= nil and waitingKeys[key] == at then
			waitingKeys[key] = nil
		end
		if fn then
			runningQueued = true
			local ok, err = pcall(fn)
			runningQueued = false
			if not ok then
				geterrorhandler()(err)
			end
		end
		if budget and queueAt <= #combatQueue and debugprofilestop() - t0 >= budget then
			combatFrame:Show()
			return
		end
	end
	if queueAt > 1 then
		combatQueue, queueKeys, queueAt = {}, {}, 1
	end
	combatFrame:Hide()
	-- through: what waited for that goes on, on the next frame
	QueueIdleWaiters()
end

local function Enqueue(fn, key)
	if key ~= nil then
		local at = waitingKeys[key]
		if at then
			combatQueue[at] = false
		end
	elseif queueAt <= #combatQueue and combatQueue[#combatQueue] == fn then
		return
	end
	local n = #combatQueue + 1
	combatQueue[n], queueKeys[n] = fn, key
	if key ~= nil then
		waitingKeys[key] = n
	end
end

combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
Perf.SetScript(combatFrame, "OnEvent", function()
	RunQueued(QUEUE_BUDGET)
end)
Perf.SetScript(combatFrame, "OnUpdate", function()
	RunQueued(QUEUE_BUDGET)
end)

function S:WhenOutOfCombat(fn, key)
	if InCombatLockdown() then
		Enqueue(fn, key)
	elseif not runningQueued and queueAt <= #combatQueue then
		-- a fight's work is still being worked through: behind it
		Enqueue(fn, key)
		combatFrame:Show()
	else
		fn()
	end
end

--------------------------------------------------------------------------------
-- The UI scale
--------------------------------------------------------------------------------
-- S:SetFrameScale(frame, scale, setScale): the frame's scale set (through
-- setScale(frame, scale) when given: a caller's own unhooked SetScale) and
-- the backgrounds in it laid again -- only those, and only when the frame's
-- scale on the screen really changed (audit, 2026-09-24: six places set a
-- scale and then laid every background in the UI again, the Quest Tracker
-- on each of its settings, a header's collapse too). A scale that reads
-- secret counts as changed. Returns true when it changed, and how many were
-- laid (0 without the kit). A protected frame's scale is the caller's to
-- keep out of combat.
-- A background that only hangs off the frame by its anchors (its holder
-- parented elsewhere) changes size, not scale: the holder's OnSizeChanged
-- lays it, as it always has.
function S:SetFrameScale(frame, scale, setScale)
	if not frame then
		return false, 0
	end
	local okB, before = pcall(frame.GetEffectiveScale, frame)
	if setScale then
		setScale(frame, scale)
	else
		frame:SetScale(scale)
	end
	local okA, after = pcall(frame.GetEffectiveScale, frame)
	if okB and okA and not Secret(before) and not Secret(after) and before == after then
		return false, 0
	end
	-- the kit's part, looked up now (a world without the kit lays nothing)
	local Kit = MelloUI.Kit
	if type(Kit) ~= "table" or not Kit.RetileBackgroundsIn then
		return true, 0
	end
	-- (a shadow partner drawn by another frame than its piece's reaches in
	-- that frame's units: fitted again on the next frame, once for a burst --
	-- a mouse wheel's turns, the saved frames' scales at login -- and only
	-- where the scales changed)
	if Kit.ShadowRefit then
		Kit:ShadowRefit(true)
	end
	return true, (Kit:RetileBackgroundsIn(frame))
end

--------------------------------------------------------------------------------
-- The UI scale watcher (user, 2026-09-24: "UI Scaling Break the UI"). One
-- place that answers a change of the game's UI Scale (the uiScale /
-- useUiScale settings), of the window's resolution, and of an Edit Mode
-- setting (a system's Size): every background laid again at the screen's
-- one density, then every panel that measured something on the screen told
-- through S:OnUIScaleChanged(fn), fn(reason) with reason "uiscale" (the UI
-- Scale or the resolution) or "editmode" (a setting in Edit Mode): the bus's
-- 'scale' topic (Core.lua), this watcher its one source.
-- The work waits a moment and runs once for a burst of changes: when the
-- event comes the game has not yet re-laid everything for the new scale
-- (Edit Mode re-scales and re-places the right-hand action bars and the
-- panel manager moves its windows in their own handlers of the same events),
-- and the settings' slider sends several changes in a row. What a listener
-- does to a protected frame it puts through S:WhenOutOfCombat itself.
-- Bars, rails, caps and pieces in general need nothing: they are sized in
-- their frame's own units and follow any scale with it; only the
-- backgrounds (measured on the screen) and what a panel laid out from
-- screen positions (the action bar backdrops, the saved window places, the
-- drag grid) go stale.
--------------------------------------------------------------------------------
S.lastScaleRefit = nil   -- what the last refit did, for /uiscaledump

-- (an alias of the bus's 'scale' topic, audit 2026-09-24 rank 5: a listener
-- that raises goes to the error handler, the others still run)
function S:OnUIScaleChanged(fn)
	if type(fn) == "function" then
		MelloUI:On("scale", fn)
		S.scaleListenerCount = S.scaleListenerCount + 1
	end
end

-- The refit itself, at once (the watcher calls it a moment after a change;
-- /uiscaledump refit calls it by hand): the kit's backgrounds laid again
-- first, then the 'scale' listeners told
function S:RefitForScale(reason)
	reason = reason or "uiscale"
	local laid, left = 0, 0
	local Kit = MelloUI.Kit
	if type(Kit) == "table" and Kit.RetileBackgrounds then
		laid, left = Kit:RetileBackgrounds()
	end
	MelloUI:Fire("scale", reason)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	S.lastScaleRefit = {
		reason = reason, when = GetTime and GetTime() or 0,
		backgrounds = laid, skipped = left,
		effectiveScale = (okU and not Secret(us)) and us or nil,
	}
	return laid
end

do
	local pending, pendingReason = nil, nil
	local function Run()
		pending = nil
		local reason = pendingReason
		pendingReason = nil
		S:RefitForScale(reason)
	end
	-- a change of the UI Scale outranks an Edit Mode one: its listeners do more
	local function Schedule(reason)
		if pendingReason ~= "uiscale" then
			pendingReason = reason
		end
		if pending then
			pending:Cancel()
		end
		pending = C_Timer.NewTimer(0.15, Run)
	end
	S.ScheduleScaleRefit = function(_, reason)
		Schedule(reason or "uiscale")
	end
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("UI_SCALE_CHANGED")
	ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
	Perf.SetScript(ev, "OnEvent", function()
		Schedule("uiscale")
	end)
	-- the settings themselves, for a client that changes the scale without
	-- the event (it costs nothing twice: the timer runs once)
	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
		for _, cvar in ipairs({ "uiScale", "useUiScale" }) do
			CVarCallbackRegistry:RegisterCallback(cvar, function() Schedule("uiscale") end, S)
		end
	end
	-- Edit Mode opened and closed: the addon's ONE registration (audit,
	-- 2026-09-24, rank 5: six files each had their own), told on the bus as
	-- 'editmode' (entering) from inside the game's event, as theirs were;
	-- a close also lays the backgrounds again, here
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			MelloUI:Fire("editmode", true)
		end, S)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			MelloUI:Fire("editmode", false)
			Schedule("editmode")
		end, S)
	end
	-- a system's Size (or any setting) changed in Edit Mode: laid again while
	-- the window is still open, not only when it closes (a post-hook: Edit
	-- Mode's own code runs untouched)
	local manager = EditModeManagerFrame
	if manager and type(manager.OnSystemSettingChange) == "function" then
		hooksecurefunc(manager, "OnSystemSettingChange", function()
			Schedule("editmode")
		end)
	end
end

-- /uiscaledump [refit]: the UI scale as the game and the kit see it, and what
-- the last refit did (user, 2026-09-24: to check the UI Scale fix in game).
-- "refit" runs a refit now first. Opens the copy window.
SLASH_MELLOUISCALEDUMP1 = "/uiscaledump"
SlashCmdList.MELLOUISCALEDUMP = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "refit" then
		S:RefitForScale("uiscale")
	end
	MelloUI:ClearLog()
	local function Num(v, fmt)
		if type(v) ~= "number" or Secret(v) then
			return tostring(v)
		end
		return string.format(fmt or "%.4f", v)
	end
	local GetCVarFn = (C_CVar and C_CVar.GetCVar) or GetCVar
	local okC, uiScale = pcall(GetCVarFn, "uiScale")
	local okU, useUiScale = pcall(GetCVarFn, "useUiScale")
	MelloUI:Print("cvar uiScale = %s, useUiScale = %s", okC and tostring(uiScale) or "?", okU and tostring(useUiScale) or "?")
	local okS, s = pcall(UIParent.GetScale, UIParent)
	local okE, es = pcall(UIParent.GetEffectiveScale, UIParent)
	local okW, w, h = pcall(UIParent.GetSize, UIParent)
	MelloUI:Print("UIParent scale = %s, effective = %s, size = %s x %s UI units", okS and Num(s) or "?", okE and Num(es) or "?",
		okW and Num(w, "%.1f") or "?", okW and Num(h, "%.1f") or "?")
	if GetPhysicalScreenSize then
		local okP, pw, ph = pcall(GetPhysicalScreenSize)
		if okP and type(ph) == "number" and not Secret(ph) and ph > 0 then
			MelloUI:Print("physical screen = %s x %s px; a pixel-exact UI scale here would be %s", Num(pw, "%d"), Num(ph, "%d"), Num(768 / ph))
			if okE and type(es) == "number" and not Secret(es) and es > 0 then
				MelloUI:Print("one UI unit = %s screen px", Num(es * ph / 768, "%.3f"))
			end
		end
	end
	-- the kit's part, looked up now (none without the kit)
	local Kit = MelloUI.Kit
	if type(Kit) ~= "table" then
		Kit = nil
	end
	local backgrounds = Kit and Kit.BackgroundCount and Kit:BackgroundCount() or 0
	-- (the listeners are the bus's 'scale' topic: one that raises goes to the
	-- error handler when it runs)
	MelloUI:Print("Kit.scale = %s UI units per piece px; backgrounds registered = %d; scale listeners through the kit = %d",
		Num(Kit and Kit.scale, "%.3f"), backgrounds, S.scaleListenerCount)
	local last = S.lastScaleRefit
	if last then
		local ago = GetTime and (GetTime() - (last.when or 0)) or 0
		MelloUI:Print("last refit (%s, %.0f s ago, UIParent effective %s): %d backgrounds laid again, %d left (size unreadable), the 'scale' listeners told",
			tostring(last.reason), ago, Num(last.effectiveScale), last.backgrounds or 0, last.skipped or 0)
		if last.effectiveScale and okE and type(es) == "number" and not Secret(es) and math.abs(last.effectiveScale - es) > 0.0001 then
			MelloUI:Print("the UI scale changed since the last refit and none ran: /uiscaledump refit")
		end
	else
		MelloUI:Print("no refit since the last reload (the UI scale has not changed); /uiscaledump refit runs one")
	end
	MelloUI:ShowLog("uiscaledump")
end
