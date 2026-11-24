--------------------------------------------------------------------------------
-- MelloUI - Performance (/melloperf)
--
-- (user, 2026-09-24: "im having concerns about Addon performance, is there a
-- way to measure how it impacts game performance?" / "melloperf next, before
-- building the installer i want to make sure it runs correctly")
--
-- Two sources, side by side:
--  * the game's own addon profiler (C_AddOnProfiler): MelloUI's time per frame
--    against every addon's and the whole frame's. The truth, but one number
--    for the whole addon.
--  * our own attribution: every file opens a scope (Perf:Scope("Chat")) and
--    hooks, sets scripts and starts timers through it. A handler installed that
--    way is wrapped: while nothing records, the wrapper only passes the call
--    on (one extra call); while recording it times the handler's OWN work (not
--    the handlers it sets off) and the memory it made, per file and handler.
--    A handler one file hooks on many objects is wrapped once for all of them
--    (scope.Shared) and handed on as it is.
-- Always kept, a few timestamps each: every file's load time (from its scope
-- to the next one) and every module's OnEnable / OnDisable (Core's SafeCall).
--
-- Saved variables load late on this client, after the files have run, so the
-- wrappers cannot wait for a setting: they are always in place, and cost only
-- that one call while idle.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local rawHook = hooksecurefunc
local rawTimer = C_Timer
local now = debugprofilestop
local gc = collectgarbage
local format = string.format

local Perf = {}
MelloUI.Perf = Perf

local SPIKE_MS = 5          -- a single call this long is a slow call
local SPIKE_TIMES = 4       -- a slow handler lists when its first few slow calls came
local MAX_SPIKES = 25       -- slow handlers listed
local EVERY_FRAME = 0.9     -- a handler called on this share of the frames runs every frame
local OVER = { 1, 5, 10, 50, 100 }   -- the game counts MelloUI's frames over these (ms)

local recording = false
local rec = nil              -- the recording under way (or the last one)
local rows = {}              -- key -> { scope, kind, label, calls, time, max, mem, over, at }
local depth = 0
local tChild, mChild = {}, {}

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

--------------------------------------------------------------------------------
-- Measuring
--
-- Nothing on this path makes garbage once a handler has run once: the rows,
-- the slow-call times and the timer wrappers are all kept and reused, so what
-- a handler is charged is its own.
--------------------------------------------------------------------------------

local function Row(scope, kind, label)
	local key = scope .. "\t" .. kind .. "\t" .. label
	local row = rows[key]
	if not row then
		row = { scope = scope, kind = kind, label = label, calls = 0, time = 0, max = 0, mem = 0, over = 0 }
		rows[key] = row
	end
	return row
end

-- A slow call, counted on its handler with the time of the first few: the
-- report gives one line per handler (a ticker slow every second filled 20 of
-- the 25 lines on its own when every call had one)
local function Spike(row, ms, t)
	local n = row.over + 1
	row.over = n
	if ms > row.max then
		row.max = ms
	end
	if n <= SPIKE_TIMES then
		local at = row.at
		if not at then
			at = { 0, 0, 0, 0 }   -- SPIKE_TIMES long, made once per handler
			row.at = at
		end
		at[n] = (t - rec.t0) / 1000
	end
end

-- One call, timed. A handler that sets off others (a hook firing a Kit
-- refresh that fires another hook) is charged only for its own part: each
-- level adds its whole time to the level above's children. The clock is read
-- outside the memory reads, so a nested call's measuring falls inside its own
-- time and is not charged to its caller. A handler that raises never closes
-- its level; the recording's frame driver starts every frame from the top
-- again.
local function Measure(row, fn, ...)
	depth = depth + 1
	local d = depth
	tChild[d], mChild[d] = 0, 0
	local t0 = now()
	local m0 = gc("count")
	fn(...)
	local dm = gc("count") - m0
	local dt = now() - t0
	if dm < 0 then
		dm = 0   -- a collection ran during the call
	end
	depth = d - 1
	if d > 1 then
		tChild[d - 1] = tChild[d - 1] + dt
		mChild[d - 1] = mChild[d - 1] + dm
	end
	local own, ownMem = dt - tChild[d], dm - mChild[d]
	row.calls = row.calls + 1
	row.time = row.time + own
	if ownMem > 0 then
		row.mem = row.mem + ownMem
	end
	if own > row.max then
		row.max = own
	end
	if own >= SPIKE_MS then
		Spike(row, own, t0)
	end
end

local function Wrap(row, fn)
	return function(...)
		if not recording then
			return fn(...)
		end
		Measure(row, fn, ...)
	end
end

-- Handlers a file wrapped once itself (scope.Shared): the installers hand
-- them to the game as they are, with no label, row or wrapper per object
local prewrapped = setmetatable({}, { __mode = "k" })

-- an event frame's handler: one row per event, so the report says WHICH
-- event costs
local function WrapEvents(scope, label, fn)
	local byEvent = {}
	return function(self, event, ...)
		if not recording then
			return fn(self, event, ...)
		end
		local row = byEvent[event]
		if not row then
			row = Row(scope, "event", tostring(event) .. " (" .. label .. ")")
			byEvent[event] = row
		end
		Measure(row, fn, self, event, ...)
	end
end

-- One-shot timers started while recording: their wrappers come from a pool
-- and go back when they fire, so a handler that starts timers (QuestInk's
-- re-passes on every OnShow) is not charged a new wrapper for each. A
-- cancelled timer never hands its wrapper back; the collector takes it.
local shots = {}

local function Shot(row, fn)
	local s = shots[#shots]
	if s then
		shots[#shots] = nil
	else
		s = {}
		s.call = function(...)
			local f, r = s.fn, s.row
			s.fn, s.row = nil, nil
			shots[#shots + 1] = s
			if not recording then
				return f(...)
			end
			Measure(r, f, ...)
		end
	end
	s.fn, s.row = fn, row
	return s.call
end

--------------------------------------------------------------------------------
-- Labels: what a handler hangs on, readable and grouped (row 1..12 are one)
--
-- A named frame is its name. An anonymous one has only a debug name, and
-- where a name or a parentKey would be that holds its table address
-- ("1f3ee8c40", "UIParent.1f3ee8c40"), which the digit grouping turned into
-- "#f#ee#c#". So: a parentKey path from a named frame is kept
-- ("TargetFrameToT.ManaBar"); otherwise it says what the frame is and where
-- it hangs ("StatusBar child of TargetFrame"), or, with no named frame above
-- it, which file hooked it ("Frame made by QuestInk"). Built once per
-- wrapper, so the walk up the parents costs nothing while playing.
--------------------------------------------------------------------------------

-- a plain, non-empty string (a boolean). The secret test first: comparing
-- a secret string with "" is refused (audit, 2026-09-24: it came last).
local function Named(v)
	return not Secret(v) and type(v) == "string" and v ~= ""
end

local function CallMethod(obj, method)
	return obj[method](obj)
end

-- obj:method(), or nil when obj has no such method or it fails
local function Ask(obj, method)
	local ok, v = pcall(CallMethod, obj, method)
	if ok then
		return v
	end
	return nil
end

local function Group(name)
	return (name:gsub("%d+", "#"))
end

-- a table address standing where a name would be
local function IsAddress(part)
	if part:find("0[xX]%x%x%x%x") then
		return true
	end
	return #part >= 6 and part:find("^%x+$") ~= nil and part:find("%d") ~= nil
end

-- the nearest named frame above obj
local function NamedAncestor(obj)
	local p = obj
	for _ = 1, 30 do
		p = Ask(p, "GetParent")
		if type(p) ~= "table" then
			return nil
		end
		local name = Ask(p, "GetName")
		if Named(name) then
			return Group(name)
		end
	end
	return nil
end

-- an anonymous frame without a key; true when the label names the scope
local function Anonymous(obj, scope)
	local kind = Ask(obj, "GetObjectType")
	kind = Named(kind) and kind or "Frame"
	local named = NamedAncestor(obj)
	if named then
		return kind .. " child of " .. named
	end
	return kind .. " made by " .. scope, true
end

-- a widget type's shared methods (a hook there sees every widget of the type:
-- CooldownText's on every Cooldown), told apart by a method only it has
local TYPE_MARKS = { { "SetCooldown", "Cooldown" }, { "SetStatusBarTexture", "StatusBar" } }

-- a table that is not a frame: the addon's own and a widget type's methods
-- are named at once (a module, MelloUI.Kit, "every Cooldown"); others (a
-- game mixin) only when a report is built, from _G
local function TableName(t)
	if t == _G then
		return "_G"
	elseif t == MelloUI then
		return "MelloUI"
	end
	local n = rawget(t, "name")
	if Named(n) and type(MelloUI.modules) == "table" and rawequal(MelloUI.modules[n], t) then
		return n
	end
	for k, v in pairs(MelloUI) do
		if type(v) == "table" and rawequal(v, t) and type(k) == "string" then
			return "MelloUI." .. k
		end
	end
	-- widget methods, not a widget: not in _G, so the report could not name it
	if rawget(t, 0) == nil and type(rawget(t, "GetObjectType")) == "function" then
		for _, mark in ipairs(TYPE_MARKS) do
			if type(rawget(t, mark[1])) == "function" then
				return "every " .. mark[2]
			end
		end
		return "widget methods"
	end
	return nil
end

local labels = setmetatable({}, { __mode = "k" })
local labelScope = setmetatable({}, { __mode = "k" })   -- labels that name their scope
local tableIds = setmetatable({}, { __mode = "k" })
local tableCount = 0
local labelled = {}          -- scope -> objects it labelled (/melloperf load)

-- the label, and true for a table only the report can name
local function FrameLabel(obj, scope)
	if type(obj) ~= "table" then
		return tostring(obj)
	end
	local label = labels[obj]
	if label and (labelScope[obj] == nil or labelScope[obj] == scope) then
		return label
	end
	local byScope
	if not Named(Ask(obj, "GetObjectType")) then
		label = TableName(obj)
		if not label then
			local id = tableIds[obj]
			if not id then
				tableCount = tableCount + 1
				id = tableCount
				tableIds[obj] = id
				labelled[scope] = (labelled[scope] or 0) + 1
			end
			return "table " .. id, true
		end
	else
		local name = Ask(obj, "GetName")
		if Named(name) then
			label = Group(name)
		else
			-- the debug name: the keys after its last address, and whether
			-- there was any address at all
			local debug = Ask(obj, "GetDebugName")
			local tail, levels, clean, parts = nil, 0, true, 0
			if Named(debug) then
				for part in debug:gmatch("[^.]+") do
					parts = parts + 1
					if IsAddress(part) then
						tail, levels, clean = nil, 0, false
					else
						tail = tail and (tail .. "." .. part) or part
						levels = levels + 1
					end
				end
			end
			if clean and parts >= 2 then
				label = Group(debug)
			else
				-- the frame the address stands for: as many parents up as keys
				-- follow it (no address, no keys: the frame itself)
				local anc = obj
				if clean then
					tail = nil
				end
				if tail then
					for _ = 1, levels do
						anc = Ask(anc, "GetParent")
						if type(anc) ~= "table" then
							anc, tail = obj, nil
							break
						end
					end
				end
				label, byScope = Anonymous(anc, scope)
				if tail then
					label = "(" .. label .. ")." .. Group(tail)
				end
			end
		end
	end
	labels[obj] = label
	labelScope[obj] = byScope and scope or nil
	labelled[scope] = (labelled[scope] or 0) + 1
	return label
end

-- the hooked tables no scope could name: row -> table
local unnamed = setmetatable({}, { __mode = "v" })

-- One pass over _G for all of them, when a report is built (not at every
-- hook: _G is large and hooks are set while the addon loads). A table looked
-- for once and not found keeps its number; it is not looked for again, or a
-- hook on it that runs all the time would cost every report that pass.
local function NameTables()
	local want
	for row, t in pairs(unnamed) do
		if row.calls > 0 or row.over > 0 then
			want = want or {}
			want[t] = false
		end
	end
	if not want then
		return
	end
	for k, v in pairs(_G) do
		if type(v) == "table" and want[v] == false and type(k) == "string" then
			want[v] = k
		end
	end
	for row, t in pairs(unnamed) do
		local k = want[t]
		if k then
			row.label = k .. ":" .. row.method
			unnamed[row] = nil
		elseif k == false then
			unnamed[row] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Scopes: one per file, handing out the wrapped installers
--------------------------------------------------------------------------------

local scopes = {}
local loads = {}             -- { name, ms, kb } in load order
local loadName, loadMark, loadMem = nil, nil, nil
local loadStart = now()
local WEAK = { __mode = "kv" }
local WEAK_KEYS = { __mode = "k" }

-- a file's load: its time, and the memory made while it ran (what it keeps
-- and a little garbage; nothing else runs while a file loads). User,
-- 2026-09-24: 88 MB live after a full collect, only ~34 MB explained offline
local function CloseLoad(t)
	if loadName then
		local kb = gc("count") - loadMem
		loads[#loads + 1] = { name = loadName, ms = t - loadMark, kb = kb > 0 and kb or 0 }
		loadName = nil
	end
end

-- a load opened after login is an addon's (the route data companion's):
-- named after it, alone or followed by words ("MelloUI_Companion (route
-- data)"). Only that addon's own ADDON_LOADED ends it
local function LoadOf(addon)
	return loadName == addon or (type(addon) == "string" and loadName:sub(1, #addon + 1) == addon .. " ")
end

-- (1.2.4, the Forever build on the retail client, 2026-10-27) a script hooked on a frame, as frame:HookScript. A
-- frame the client refuses a hook on (retail: one shown or hidden with a secret, "blocked by secret aspects", or a
-- forbidden one) is left alone -- the hook's feature does without it -- and counted (/melloperf's report); any other
-- error is raised as before. Only at hook time: nothing per event
Perf.blockedHooks = 0
function Perf.HookOn(frame, script, fn, ...)
	local ok, err = pcall(frame.HookScript, frame, script, fn, ...)
	if ok then
		return
	end
	if type(err) == "string" and (err:find("secret aspect", 1, true) or err:find("forbidden", 1, true)) then
		Perf.blockedHooks = Perf.blockedHooks + 1
		Perf.blockedLast = tostring(script)
		return
	end
	error(err, 0)
end

local function NewScope(name)
	local scope = {}
	-- a script's wrapper per handler, so a handler set again and again (an
	-- OnUpdate switched on per animation, and off again when idle) is wrapped
	-- once and then costs a lookup, no garbage. Weak both ways, as the wrapper
	-- holds its handler; so each frame also keeps the wrapper it was given
	-- last, or one switched off would be gone after the next collection and
	-- made again when it comes back on (one per frame and script: what the
	-- frame held while it was set)
	local wrapped = {}           -- script -> { byFn = { handler -> wrapper }, held = { frame -> wrapper set last } }
	-- what the file's hooks cost (/melloperf load): wrappers made, shared
	-- handlers, and the hooks those handlers were handed on as they are
	scope.nWraps, scope.nShared, scope.nPassed = 0, 0, 0

	-- One handler for every object a file hooks it on (user, 2026-09-24: the
	-- shared handlers, low-risk steps only): wrapped ONCE, under one row named
	-- by `label` (kind "hook", "script" or "update"), where a handler made
	-- per object costs a wrapper and a label on each. Its report row covers
	-- every object it is on, so a window's own share is not told apart.
	function scope.Shared(label, fn, kind)
		scope.nShared = scope.nShared + 1
		local w = Wrap(Row(name, kind or "hook", label), fn)
		prewrapped[w] = true
		return w
	end

	function scope.hooksecurefunc(a, b, c)
		if type(a) == "string" then
			if prewrapped[b] then
				scope.nPassed = scope.nPassed + 1
				return rawHook(a, b)
			end
			scope.nWraps = scope.nWraps + 1
			return rawHook(a, Wrap(Row(name, "hook", a), b))
		end
		if prewrapped[c] then
			scope.nPassed = scope.nPassed + 1
			return rawHook(a, b, c)
		end
		local label, later = FrameLabel(a, name)
		local row = Row(name, "hook", label .. ":" .. tostring(b))
		if later then
			row.method = tostring(b)
			unnamed[row] = a
		end
		scope.nWraps = scope.nWraps + 1
		return rawHook(a, b, Wrap(row, c))
	end

	function scope.HookScript(frame, script, fn, ...)
		if type(fn) ~= "function" then
			return Perf.HookOn(frame, script, fn, ...)
		end
		if prewrapped[fn] then
			scope.nPassed = scope.nPassed + 1
			return Perf.HookOn(frame, script, fn, ...)
		end
		local kind = script == "OnUpdate" and "update" or "script"
		scope.nWraps = scope.nWraps + 1
		return Perf.HookOn(frame, script, Wrap(Row(name, kind, script .. " on " .. FrameLabel(frame, name)), fn), ...)
	end

	function scope.SetScript(frame, script, fn, ...)
		if type(fn) ~= "function" then
			return frame:SetScript(script, fn, ...)
		end
		local s = wrapped[script]
		if prewrapped[fn] then
			-- the wrapper the frame held before is no longer on it
			if s then
				s.held[frame] = nil
			end
			scope.nPassed = scope.nPassed + 1
			return frame:SetScript(script, fn, ...)
		end
		if not s then
			s = { byFn = setmetatable({}, WEAK), held = setmetatable({}, WEAK_KEYS) }
			wrapped[script] = s
		end
		local w = s.byFn[fn]
		if not w then
			local label = FrameLabel(frame, name)
			if script == "OnEvent" then
				w = WrapEvents(name, label, fn)
			else
				w = Wrap(Row(name, script == "OnUpdate" and "update" or "script", script .. " on " .. label), fn)
			end
			s.byFn[fn] = w
			scope.nWraps = scope.nWraps + 1
		end
		s.held[frame] = w
		return frame:SetScript(script, w, ...)
	end

	-- one-shot timers are wrapped only while recording (they are started at
	-- runtime, often many a second); tickers always (they start at login)
	local timer = setmetatable({}, { __index = rawTimer })
	local afterRow, newTimerRow
	function timer.After(delay, fn)
		if recording and type(fn) == "function" then
			afterRow = afterRow or Row(name, "timer", "C_Timer.After")
			fn = Shot(afterRow, fn)
		end
		return rawTimer.After(delay, fn)
	end
	function timer.NewTimer(delay, fn)
		if recording and type(fn) == "function" then
			newTimerRow = newTimerRow or Row(name, "timer", "C_Timer.NewTimer")
			fn = Shot(newTimerRow, fn)
		end
		return rawTimer.NewTimer(delay, fn)
	end
	function timer.NewTicker(delay, fn, iterations)
		if type(fn) == "function" then
			scope.nWraps = scope.nWraps + 1
			fn = Wrap(Row(name, "timer", format("ticker every %gs", tonumber(delay) or 0)), fn)
		end
		return rawTimer.NewTicker(delay, fn, iterations)
	end
	scope.C_Timer = timer
	return scope
end

-- Called at the top of every file: marks where the file's load starts (the
-- one before it ends there) and returns the file's installers.
function Perf:Scope(name)
	local t = now()
	if Perf.loadedAt and loadName then
		-- a load opened after MelloUI's own still open here: the same
		-- addon's next file (a feature addon of several files,
		-- "MelloUI_QuestList (QuestListPanel)" after "(QuestList)": 0.19.9) is
		-- counted to here; another's never saw its addon loaded (its
		-- LoadAddOn failed): dropped, not counted up to now
		local addon = loadName:match("^(%S+)")
		if not (type(name) == "string" and addon and name:sub(1, #addon + 1) == addon .. " ") then
			loadName = nil
		end
	end
	CloseLoad(t)
	loadName, loadMark, loadMem = name, t, gc("count")
	local scope = scopes[name]
	if not scope then
		scope = NewScope(name)
		scopes[name] = scope
	end
	return scope
end

-- Core's SafeCall: a module's OnEnable / OnDisable / ... how long it took and
-- the memory it made (what a module builds when it comes on)
local moduleCalls = {}        -- "Name OnEnable" -> { count, total, max, kb }

function Perf:ModuleCall(module, method, ms, kb)
	local key = tostring(module) .. " " .. tostring(method)
	local c = moduleCalls[key]
	if not c then
		c = { key = key, count = 0, total = 0, max = 0, kb = 0 }
		moduleCalls[key] = c
	end
	c.count = c.count + 1
	c.total = c.total + ms
	if type(kb) == "number" and kb > 0 then
		c.kb = c.kb + kb
	end
	if ms > c.max then
		c.max = ms
	end
	if recording and ms >= SPIKE_MS then
		Spike(Row(tostring(module), "module", tostring(method)), ms, now() - ms)
	end
end

--------------------------------------------------------------------------------
-- The game's profiler
--------------------------------------------------------------------------------

local function Profiler()
	local P = C_AddOnProfiler
	local E = Enum and Enum.AddOnProfilerMetric
	if not (P and E) then
		return nil
	end
	if P.IsEnabled and not P.IsEnabled() then
		return nil
	end
	return P, E
end

local function Metric(source, name)
	local P, E = Profiler()
	if not (P and E[name]) then
		return nil
	end
	local ok, v
	if source == "addon" then
		ok, v = pcall(P.GetAddOnMetric, ADDON_NAME, E[name])
	elseif source == "overall" then
		ok, v = pcall(P.GetOverallMetric, E[name])
	else
		ok, v = pcall(P.GetApplicationMetric, E[name])
	end
	if ok and type(v) == "number" and not Secret(v) then
		return v
	end
	return nil
end

-- The game's running counts of MelloUI's frames over 1 / 5 / 10 / 50 / 100 ms
-- (those this client has) and its slowest frame, all since the session began
local function Counters()
	local c = {}
	for _, ms in ipairs(OVER) do
		c[ms] = Metric("addon", format("CountTimeOver%dMs", ms))
	end
	c.peak = Metric("addon", "PeakTime")
	return c
end

-- "1 / 5 / 10", "40 / 3 / 1": the limits counted, and the frames over each
-- (since `from` was taken, or in all)
local function OverText(from, to)
	local limits, counts = {}, {}
	for _, ms in ipairs(OVER) do
		if to[ms] and (not from or from[ms]) then
			limits[#limits + 1] = ms
			counts[#counts + 1] = format("%.0f", to[ms] - (from and from[ms] or 0))
		end
	end
	if #limits == 0 then
		return nil
	end
	return table.concat(limits, " / "), table.concat(counts, " / ")
end

-- MelloUI's memory, the route data companion's with it once it is loaded
-- (MelloUI:MemoryKB, Core/Companions.lua); MelloUI's own without that
local function AddonMemory()
	if type(MelloUI.MemoryKB) == "function" then
		local ok, kb = pcall(MelloUI.MemoryKB, MelloUI)
		if ok and type(kb) == "number" and not Secret(kb) then
			return kb
		end
	end
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		pcall(UpdateAddOnMemoryUsage)
		local ok, kb = pcall(GetAddOnMemoryUsage, ADDON_NAME)
		if ok and type(kb) == "number" then
			return kb
		end
	end
	return nil
end

local function SessionLines(add)
	local avg, recent = Metric("addon", "SessionAverageTime"), Metric("addon", "RecentAverageTime")
	if not (avg or recent) then
		add("  The game's addon profiler is not available on this client.")
		return
	end
	local app = Metric("app", "RecentAverageTime")
	if recent then
		add("  Right now: MelloUI %.3f ms per frame%s; all addons %.3f ms", recent,
			app and app > 0 and format(" = %.1f %% of the frame (%.1f ms, %.0f fps)", recent / app * 100, app, 1000 / app) or "",
			Metric("overall", "RecentAverageTime") or 0)
	end
	add("  This session: average %.3f ms per frame, slowest frame %.1f ms%s", avg or 0, Metric("addon", "PeakTime") or 0,
		Metric("addon", "EncounterAverageTime") and format(", in boss fights %.3f ms", Metric("addon", "EncounterAverageTime")) or "")
	local limits, counts = OverText(nil, Counters())
	if limits then
		add("  Frames this session where MelloUI took over %s ms: %s", limits, counts)
	end
end

--------------------------------------------------------------------------------
-- Recording
--
-- The game's figures for a recording: its LastTime, summed every frame, came
-- to about half of what its own averages said (0.35 against 0.65 ms per
-- frame), so it is not used. Instead the frame counters are taken at the
-- start and the end (the difference is exact), the recent average is read
-- every frame and averaged, and the session's slowest frame only says
-- something about the recording when it rose during it.
--------------------------------------------------------------------------------

local GetAddonMetric, GetOverallMetric, RECENT   -- read every frame while recording
local LAST   -- (a login recording: the game's "total time in the most recent tick")

-- A login recording (/melloperf login: the next login or /reload, from the
-- moment MelloUI loads): each tick's whole MelloUI time by the game's
-- profiler, the heaviest kept with the events fired around them -- the
-- client gives every addon a time budget, and a tick past its restricted
-- burst (1000 ms on this client) leaves the game unable to call MelloUI's
-- hooks until it refills (the user's fresh character, 2026-10-05: every
-- hooked method "attempt to call a nil value" at login, MelloUI's peak 1962 ms)
local LOGIN_KEEP, LOGIN_NAMES = 12, 10
local catcher   -- the login recording's event listener (every event, while it lasts)

local function LoginTick(r, ms)
	-- (the whole Lua heap, every addon's: a collection the tick ran shows as a drop)
	r.heapPrev, r.heapNow = r.heapNow, gc("count")
	local heavy = r.heavy
	if #heavy < LOGIN_KEEP or ms > heavy[#heavy].ms then
		local names = {}
		for i = 1, #r.prevEvents do names[#names + 1] = r.prevEvents[i] end
		names[#names + 1] = "|"
		for i = 1, #r.tickEvents do names[#names + 1] = r.tickEvents[i] end
		heavy[#heavy + 1] = { ms = ms, at = (now() - r.t0) / 1000, frame = r.frames, events = table.concat(names, " "),
			heap = r.heapNow, dheap = r.heapNow and r.heapPrev and (r.heapNow - r.heapPrev) or nil }
		table.sort(heavy, function(a, b) return a.ms > b.ms end)
		if #heavy > LOGIN_KEEP then
			heavy[#heavy] = nil
		end
	end
	-- (the events of this tick become the ones before the next)
	r.prevEvents, r.tickEvents = r.tickEvents, r.prevEvents
	wipe(r.tickEvents)
end

local function Catcher_OnEvent(_, event)
	local r = rec
	if not (recording and r and r.login) then
		return
	end
	r.eventCount[event] = (r.eventCount[event] or 0) + 1
	local list = r.tickEvents
	if #list < LOGIN_NAMES then
		for i = 1, #list do
			if list[i] == event then
				return
			end
		end
		list[#list + 1] = event
	end
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
	depth = 0
	if not recording then
		return
	end
	local r = rec
	r.frames = r.frames + 1
	-- a getter that fails is dropped: it would make an error message (garbage)
	-- every frame
	if GetAddonMetric then
		local ok, v = pcall(GetAddonMetric, ADDON_NAME, RECENT)
		if not ok then
			GetAddonMetric = nil
		elseif type(v) == "number" and not Secret(v) then
			r.recent, r.samples = r.recent + v, r.samples + 1
		end
	end
	if GetOverallMetric then
		local ok, v = pcall(GetOverallMetric, RECENT)
		if not ok then
			GetOverallMetric = nil
		elseif type(v) == "number" and not Secret(v) then
			r.recentAll, r.samplesAll = r.recentAll + v, r.samplesAll + 1
		end
	end
	-- (0.17.0) the tweens that run this frame, by frame and prop: which one
	-- keeps the tween driver going (docs/plans/fps-portrait-fix.md)
	local Anim = MelloUI.Anim
	if Anim and Anim.EachRunning and (Anim:Busy()) > 0 then
		Anim:EachRunning(r.sampleTween)
	end
	if r.login and GetAddonMetric and LAST then
		local ok, v = pcall(GetAddonMetric, ADDON_NAME, LAST)
		if ok and type(v) == "number" and not Secret(v) then
			LoginTick(r, v)
		end
	end
	if r.limit and now() - r.t0 >= r.limit * 1000 then
		Perf:Stop()
	end
end)

-- (0.17.0) a write a hook makes back onto a game region (a texture, a
-- colour, a text, a place the game had just set): counted per label while
-- recording, so the next case shows in the report and not only in the FPS.
-- The rule (CLAUDE.md): never undo a game write on a path the game runs
-- every frame; cover it, or write only when the game's value changed.
local writeBacks = {}   -- [label] = count
function Perf.WriteBack(label)
	if recording then
		writeBacks[label] = (writeBacks[label] or 0) + 1
	end
end

-- (the tests' probe)
function Perf:IsRecording()
	return recording
end

function Perf:Start(seconds, login)
	if recording then
		MelloUI:Print("Already recording. /melloperf stop ends it.")
		return
	end
	for _, row in pairs(rows) do
		row.calls, row.time, row.max, row.mem, row.over = 0, 0, 0, 0, 0
	end
	for label in pairs(writeBacks) do
		writeBacks[label] = nil
	end
	depth = 0
	local P, E = Profiler()
	if P and E.RecentAverageTime then
		GetAddonMetric, GetOverallMetric, RECENT, LAST = P.GetAddOnMetric, P.GetOverallMetric, E.RecentAverageTime, E.LastTime
	else
		GetAddonMetric, GetOverallMetric = nil, nil
	end
	rec = {
		t0 = now(), limit = seconds and seconds > 0 and seconds or nil,
		frames = 0, recent = 0, samples = 0, recentAll = 0, samplesAll = 0,
		before = Counters(),
		memStart = AddonMemory(), combat = InCombatLockdown and InCombatLockdown() or false,
		tweens = {},
	}
	-- (one function per recording, not per frame)
	local tweens, keys = rec.tweens, setmetatable({}, { __mode = "k" })
	rec.sampleTween = function(frame, prop)
		local byProp = keys[frame]
		if not byProp then
			byProp = {}
			keys[frame] = byProp
		end
		local key = byProp[prop]
		if not key then
			key = FrameLabel(frame, "Anim") .. " " .. tostring(prop)
			byProp[prop] = key
		end
		tweens[key] = (tweens[key] or 0) + 1
	end
	if login then
		rec.login, rec.heavy, rec.tickEvents, rec.prevEvents, rec.eventCount = true, {}, {}, {}, {}
		if not catcher then
			catcher = CreateFrame("Frame")
			catcher:SetScript("OnEvent", Catcher_OnEvent)
		end
		catcher:RegisterAllEvents()
	end
	recording = true
	driver:Show()
	if rec.limit then
		MelloUI:Print("Recording performance for %d seconds. Play as usual; the report opens by itself (/melloperf stop ends it early).", rec.limit)
	else
		MelloUI:Print("Recording performance until /melloperf stop.")
	end
end

function Perf:Stop()
	if not recording then
		MelloUI:Print("Not recording. /melloperf record starts.")
		return
	end
	recording = false
	driver:Hide()
	if catcher then
		catcher:UnregisterAllEvents()
	end
	rec.duration = (now() - rec.t0) / 1000
	rec.after = Counters()
	rec.memEnd = AddonMemory()
	self.lastReport = self:Report()
	MelloUI:ShowText("Performance", self.lastReport)
end

--------------------------------------------------------------------------------
-- Reports
--------------------------------------------------------------------------------

local function Sorted(list, field)
	table.sort(list, function(a, b) return a[field] > b[field] end)
	return list
end

-- the client's restricted burst for an addon (GetScriptBucketThrottleLimits)
local function LoginBurst()
	local get = rawget(_G, "GetScriptBucketThrottleLimits")
	local ok, l = pcall(get or error)
	if ok and type(l) == "table" and type(l.luaScriptBucketThrottleMaxMsBurstRestricted) == "number" then
		return l.luaScriptBucketThrottleMaxMsBurstRestricted
	end
	return nil
end

function Perf:Report()
	local L = {}
	local function add(...)
		L[#L + 1] = format(...)
	end
	NameTables()
	local r = rec
	local dur = math.max(r.duration or 0, 0.001)
	local frames = math.max(r.frames, 1)
	add("MelloUI %s performance: %.1f s recorded, %d frames (%.0f fps)%s", tostring(MelloUI.version), dur, r.frames,
		r.frames / dur, r.combat and ", started in combat" or "")
	add("")
	add("THE GAME'S PROFILER (all of MelloUI's work each frame, this recorder's measuring included)")
	local game = r.samples > 0 and r.recent / r.samples or nil
	if game then
		local frameMs = dur * 1000 / frames
		add("  During the recording, averaged: MelloUI %.3f ms per frame = %.1f %% of the frame (%.1f ms); all addons %.3f ms",
			game, game / frameMs * 100, frameMs, r.samplesAll > 0 and r.recentAll / r.samplesAll or 0)
		add("    (the game's recent average, read every frame and averaged: it trails the play by a moment)")
	end
	local b, e = r.before, r.after
	if b and e then
		local limits, counts = OverText(b, e)
		if limits then
			add("  Frames during the recording where MelloUI took over %s ms: %s of %d (the game's counters, exact)",
				limits, counts, r.frames)
		end
		if b.peak and e.peak then
			if e.peak > b.peak then
				add("  MelloUI's slowest frame during the recording: %.1f ms (exact: the session's slowest rose from %.1f ms)", e.peak, b.peak)
			else
				add("  No frame during the recording was slower than the session's slowest before it (%.1f ms); the game keeps", b.peak)
				add("    only that one, so the recording's own slowest frame is not known")
			end
		end
	end
	SessionLines(add)
	if r.login and r.heavy then
		add("")
		add("THE HEAVIEST FRAMES SINCE MELLOUI LOADED (all of MelloUI's time in the frame, the game's profiler;")
		add("  the events fired the frame before | in it; the restricted budget here is a %s ms burst)",
			LoginBurst() or "?")
		for _, h in ipairs(r.heavy) do
			add("  %7.1f ms  at %5.2f s (frame %d)  heap %s MB (%s)  %s", h.ms, h.at, h.frame,
				h.heap and format("%.1f", h.heap / 1024) or "?", h.dheap and format("%+.1f MB", h.dheap / 1024) or "-", h.events)
		end
		local events = {}
		for name, n in pairs(r.eventCount or {}) do
			events[#events + 1] = { name = name, n = n }
		end
		Sorted(events, "n")
		local line = {}
		for k = 1, math.min(#events, 15) do
			line[#line + 1] = events[k].name .. " x" .. events[k].n
		end
		add("  the most frequent events: %s", table.concat(line, ", "))
	end
	if r.memStart and r.memEnd then
		add("  Memory: %.1f MB -> %.1f MB", r.memStart / 1024, r.memEnd / 1024)
	end

	-- by file
	local byScope, total, totalMem = {}, 0, 0
	for _, row in pairs(rows) do
		if row.calls > 0 then
			local s = byScope[row.scope]
			if not s then
				s = { name = row.scope, time = 0, calls = 0, mem = 0 }
				byScope[row.scope] = s
			end
			s.time, s.calls, s.mem = s.time + row.time, s.calls + row.calls, s.mem + row.mem
			total, totalMem = total + row.time, totalMem + row.mem
		end
	end
	add("")
	add("MELLOUI'S OWN MEASURE (own time per handler; measuring adds a little, so these run slightly high)")
	add("  %.3f ms per frame measured in MelloUI's handlers%s; %.0f KB of memory made (%.1f KB/s)", total / frames,
		game and game > 0 and format(", %.0f %% of the game's average above", total / frames / game * 100) or "", totalMem, totalMem / dur)
	local list = {}
	for _, s in pairs(byScope) do
		list[#list + 1] = s
	end
	Sorted(list, "time")
	add("")
	add("BY FILE")
	for i = 1, math.min(#list, 30) do
		local s = list[i]
		add("  %-20s %.4f ms/frame  %4.0f %%   %6.1f calls/s   %6.1f KB/s", s.name, s.time / frames,
			total > 0 and s.time / total * 100 or 0, s.calls / dur, s.mem / dur)
	end
	if #list == 0 then
		add("  nothing ran")
	end

	-- by handler
	list = {}
	for _, row in pairs(rows) do
		if row.calls > 0 then
			list[#list + 1] = row
		end
	end
	Sorted(list, "time")
	add("")
	add("BUSIEST HANDLERS")
	for i = 1, math.min(#list, 30) do
		local row = list[i]
		add("  %.4f ms/frame  %6.1f calls/s  avg %.3f  worst %.2f ms  %5.1f KB/s   %s  %s %s", row.time / frames,
			row.calls / dur, row.time / row.calls, row.max, row.mem / dur, row.scope, row.kind, row.label)
	end

	Sorted(list, "mem")
	add("")
	add("MOST MEMORY MADE (garbage the game has to collect: the cause of stutter)")
	local shown = 0
	for i = 1, #list do
		if list[i].mem >= 1 and shown < 12 then
			shown = shown + 1
			add("  %7.1f KB/s   %s  %s %s", list[i].mem / dur, list[i].scope, list[i].kind, list[i].label)
		end
	end
	if shown == 0 then
		add("  none worth naming")
	end

	add("")
	add("RUNS EVERY FRAME (fine while something moves; standing still, nothing should)")
	shown = 0
	for _, row in ipairs(list) do
		if r.frames >= 30 and row.calls >= r.frames * EVERY_FRAME then
			shown = shown + 1
			add("  %s  %s %s  (%.4f ms/frame)", row.scope, row.kind, row.label, row.time / frames)
		end
	end
	if shown == 0 then
		add("  nothing")
	end

	-- (0.17.0) a hook at 50 a second runs every frame while its frame shows
	-- (the target of target's): every hook or script over 30 a second, with
	-- the frame it hangs on (its label)
	add("")
	add("HOOKS AND SCRIPTS OVER 30 A SECOND (every frame while their frame shows)")
	shown = 0
	Sorted(list, "calls")
	for _, row in ipairs(list) do
		if (row.kind == "hook" or row.kind == "script") and row.calls / dur >= 30 then
			shown = shown + 1
			add("  %6.1f calls/s   %s  %s %s", row.calls / dur, row.scope, row.kind, row.label)
		end
	end
	if shown == 0 then
		add("  none")
	end

	-- (0.17.0) writes back onto game regions, per second
	local wb, wbTotal = {}, 0
	for label, n in pairs(writeBacks) do
		wb[#wb + 1] = { label = label, n = n }
		wbTotal = wbTotal + n
	end
	Sorted(wb, "n")
	add("")
	add("WRITE-BACKS ONTO GAME REGIONS: %.1f per second (each one makes the game's next write a real change)", wbTotal / dur)
	for i = 1, math.min(#wb, 12) do
		add("  %6.1f /s   %s", wb[i].n / dur, wb[i].label)
	end

	-- (0.17.0) the tweens that kept the tween driver running
	local tw = {}
	for key, n in pairs(r.tweens or {}) do
		tw[#tw + 1] = { key = key, n = n }
	end
	Sorted(tw, "n")
	add("")
	add("TWEENS RUNNING (frames they ran in, of %d)", r.frames)
	for i = 1, math.min(#tw, 12) do
		add("  %6d   %s", tw[i].n, tw[i].key)
	end
	if #tw == 0 then
		add("  none")
	end

	-- slow calls, one line per handler
	list = {}
	for _, row in pairs(rows) do
		if row.over > 0 then
			list[#list + 1] = row
		end
	end
	Sorted(list, "max")
	add("")
	add("SLOW CALLS (%d MS OR MORE), ONE LINE PER HANDLER, WORST FIRST", SPIKE_MS)
	for i = 1, math.min(#list, MAX_SPIKES) do
		local row = list[i]
		local times = {}
		for j = 1, math.min(row.over, SPIKE_TIMES) do
			times[j] = format("%.1f", row.at[j])
		end
		add("  worst %6.1f ms  %5d x   first at %s s%s   %s  %s %s", row.max, row.over, table.concat(times, ", "),
			row.over > SPIKE_TIMES and ", ..." or "", row.scope, row.kind, row.label)
	end
	if #list > MAX_SPIKES then
		add("  and %d more handlers", #list - MAX_SPIKES)
	elseif #list == 0 then
		add("  none")
	end
	return table.concat(L, "\n")
end

-- (0.19.8) The login's steps: when Core's login handlers began and ended
-- (wall clock from the first file: between two steps the game and other
-- addons run too) and the heap there; then, in the first frames after the
-- login's PLAYER_ENTERING_WORLD, the game's own count of MelloUI's time in
-- the frame before (LastTime). Their difference is what MelloUI is charged
-- for outside its own handlers (the user's login frame, 2026-10-06: 1855 ms
-- against the 1000 ms budget, ~700 ms of it in MelloUI's own code). A few
-- dozen entries, made at login only; /melloperf load shows them.
local loginSteps = {}
function Perf.LoginStep(label)
	if #loginSteps < 40 then
		loginSteps[#loginSteps + 1] = { label = label, t = now(), kb = gc("count") }
	end
end

-- three frames after the login's world: each with the game's figure for the
-- frame before it
function Perf.LoginFrames()
	local n = 0
	local function Ms(source)
		local v = Metric(source, "LastTime")
		return v and format("%.1f", v) or "?"
	end
	local function Probe()
		n = n + 1
		-- (all addons and the whole frame beside it: MelloUI's share of the frame)
		Perf.LoginStep(format("frame %d after the login's world: the game counts %s ms of MelloUI in the frame before"
			.. " (all addons %s ms, the frame %s ms)", n, Ms("addon"), Ms("overall"), Ms("app")))
		if n < 3 then
			C_Timer.After(0, Probe)
		end
	end
	C_Timer.After(0, Probe)
end

-- (0.19.8) the logout's own work, timed and kept in the settings to be saved
-- (MelloUI.db: what Core writes to MelloUIDB at logout), shown once by the
-- next login's /melloperf load: a /reload's logout and its new login are one
-- frame to the game's per-addon count
local lastLogout = nil
function Perf.LogoutStep(label, ms)
	-- (both tables: Core hands MelloUI.db over to MelloUIDB in its own logout
	-- handler, which may run before or after the one timed)
	local line = format("%8.1f ms  %s", ms, label)
	local seen = {}
	for _, db in ipairs({ MelloUI.db, rawget(_G, "MelloUIDB") }) do
		if type(db) == "table" and not seen[db] then
			seen[db] = true
			local t = type(db.perfLogout) == "table" and db.perfLogout or {}
			db.perfLogout = t
			t[#t + 1] = line
		end
	end
end

local function LoginStepLines(add)
	if type(lastLogout) == "table" and #lastLogout > 0 then
		add("")
		add("THE LAST LOGOUT'S OWN WORK (a /reload's logout counts with its new login)")
		for _, line in ipairs(lastLogout) do
			add("  %s", tostring(line))
		end
	end
	if #loginSteps == 0 then
		return
	end
	add("")
	add("THE LOGIN'S STEPS (from MelloUI's first file: the clock, the heap; between steps the game and other addons run too)")
	local last
	for _, s in ipairs(loginSteps) do
		add("  %8.1f ms  %6.1f MB  %s%s", s.t - loadStart, s.kb / 1024, s.label,
			last and format("  (+%.1f ms, %+.1f MB)", s.t - last.t, (s.kb - last.kb) / 1024) or "")
		last = s
	end
	local peak = Metric("addon", "PeakTime")
	if peak then
		add("  the game's slowest MelloUI frame this session: %.1f ms", peak)
	end
end

-- Load and module switches: what login costs
function Perf:LoadReport()
	local L = {}
	local function add(...)
		L[#L + 1] = format(...)
	end
	local list, total, totalKb = {}, 0, 0
	for _, l in ipairs(loads) do
		list[#list + 1] = l
		total, totalKb = total + l.ms, totalKb + (l.kb or 0)
	end
	Sorted(list, "ms")
	add("LOADING MELLOUI'S FILES: %.0f ms and %.1f MB made in all%s", total, totalKb / 1024,
		self.loadedAt and format(" (%.0f ms from the first file to the addon being loaded)", self.loadedAt - loadStart) or "")
	for i = 1, math.min(#list, 25) do
		add("  %7.1f ms  %8.0f KB  %s", list[i].ms, list[i].kb or 0, list[i].name)
	end
	Sorted(list, "kb")
	add("")
	add("THE MOST MEMORY MADE WHILE LOADING")
	for i = 1, math.min(#list, 15) do
		add("  %8.0f KB  %s", list[i].kb or 0, list[i].name)
	end
	local mods, modKb = {}, 0
	total = 0
	for _, c in pairs(moduleCalls) do
		mods[#mods + 1] = c
		total, modKb = total + c.total, modKb + c.kb
	end
	Sorted(mods, "total")
	add("")
	add("MODULES SWITCHING ON AND OFF THIS SESSION: %.0f ms and %.1f MB made in all", total, modKb / 1024)
	for i = 1, math.min(#mods, 25) do
		local c = mods[i]
		add("  %7.1f ms  %8.0f KB  %s  (%d x, slowest %.1f ms)", c.total, c.kb, c.key, c.count, c.max)
	end
	Sorted(mods, "kb")
	add("")
	add("THE MOST MEMORY MADE BY MODULES SWITCHING ON")
	for i = 1, math.min(#mods, 15) do
		add("  %8.0f KB  %s", mods[i].kb, mods[i].key)
	end
	LoginStepLines(add)
	-- what the hooks cost, per file: a wrapper per hook and a label per
	-- hooked object; a shared handler is one wrapper for all its objects
	local files, wraps, passed = {}, 0, 0
	for n, s in pairs(scopes) do
		if s.nWraps + s.nPassed > 0 or labelled[n] then
			files[#files + 1] = { name = n, wraps = s.nWraps, labels = labelled[n] or 0, shared = s.nShared, passed = s.nPassed }
			wraps, passed = wraps + s.nWraps, passed + s.nPassed
		end
	end
	if #files > 0 then
		Sorted(files, "wraps")
		add("")
		add("HOOKS BY FILE: %d wrappers made, %d hooks on shared handlers (one wrapper for all their objects)", wraps, passed)
		for i = 1, math.min(#files, 15) do
			local f = files[i]
			add("  %6d wrappers  %6d labels  %6d on %d shared  %s", f.wraps, f.labels, f.passed, f.shared, f.name)
		end
	end
	if Perf.blockedHooks > 0 then
		add("  %d hooks refused by the client (secret aspects), the last on %s", Perf.blockedHooks, Perf.blockedLast)
	end
	local kb = AddonMemory()
	if kb then
		add("")
		add("MelloUI's memory now: %.1f MB (files %.1f + modules %.1f MB made; the rest is built while playing,", kb / 1024, totalKb / 1024, modKb / 1024)
		add("minus garbage already collected). For the live figure: /run collectgarbage(\"collect\") first.")
	end
	return table.concat(L, "\n")
end

function Perf:Overview()
	local L = {}
	local function add(...)
		L[#L + 1] = format(...)
	end
	add("MelloUI %s performance", tostring(MelloUI.version))
	add("")
	add("THE GAME'S PROFILER")
	SessionLines(add)
	local kb = AddonMemory()
	if kb then
		add("  Memory: %.1f MB", kb / 1024)
	end
	add("")
	add(self:LoadReport())
	add("")
	add("COMMANDS")
	add("  /melloperf record [seconds]  measure every file and handler while you play (30 s by default; 0 = until stop)")
	add("  /melloperf stop               end a recording now and show its report")
	add("  /melloperf report             the last recording's report again")
	add("  /melloperf load               file load and module switch times")
	add("")
	add("Good recordings: standing still in a city (nothing should run), opening and closing every window,")
	add("a busy chat, a fight, a dungeon. Paste the report to compare.")
	return table.concat(L, "\n")
end

--------------------------------------------------------------------------------
-- /melloperf
--------------------------------------------------------------------------------

-- MelloUI's own ADDON_LOADED ends its last file's load. The event stays on
-- after it: a file load opened later (a scope opened for the route data
-- companion loaded on demand) ends with that addon's own ADDON_LOADED, so its
-- time and memory are counted too. Only its own: a load that failed never
-- gets one, and another addon loaded minutes later would count all that time
-- and memory as the companion's
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, _, addon)
	if addon == ADDON_NAME then
		local t = now()
		CloseLoad(t)
		Perf.loadedAt = t
		-- (the last logout's own work: shown once, by /melloperf load)
		if type(MelloUIDB) == "table" then
			lastLogout = MelloUIDB.perfLogout
			MelloUIDB.perfLogout = nil
		end
		-- (/melloperf login: this login recorded from here, 20 seconds)
		if type(MelloUIDB) == "table" and MelloUIDB.perfLogin then
			MelloUIDB.perfLogin = nil
			Perf:Start(20, true)
		end
	elseif Perf.loadedAt and loadName and LoadOf(addon) then
		CloseLoad(now())
	end
end)

-- a feature's own report (/melloperf <cmd> [arg]: the map's, MelloUI_Map): fn(arg) -> its text, shown in the copy window
local reports = {}
function Perf:AddReport(cmd, title, fn)
	if type(cmd) == "string" and type(fn) == "function" then
		reports[cmd:lower()] = { title = title or "Performance", fn = fn }
	end
end

SLASH_MELLOPERF1 = "/melloperf"
SlashCmdList.MELLOPERF = function(msg)
	local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
	if cmd == "record" or cmd == "start" then
		Perf:Start(tonumber(arg) or 30)
	elseif cmd == "stop" then
		Perf:Stop()
	elseif cmd == "report" then
		if Perf.lastReport then
			MelloUI:ShowText("Performance", Perf.lastReport)
		else
			MelloUI:Print("No recording yet. /melloperf record starts one.")
		end
	elseif cmd == "login" then
		if type(MelloUIDB) == "table" then
			MelloUIDB.perfLogin = true
			MelloUI:Print("The next login or /reload is recorded for 20 seconds from the moment MelloUI loads; the report opens by itself.")
		end
	elseif cmd == "load" then
		MelloUI:ShowText("Performance: loading", Perf:LoadReport())
	elseif reports[cmd] then
		local r = reports[cmd]
		MelloUI:ShowText(r.title, r.fn(arg))
	else
		MelloUI:ShowText("Performance", Perf:Overview())
	end
end

--------------------------------------------------------------------------------
-- Blocked actions (/mellobug; 0.19.5, offered at 0.19.3 and taken by the user
-- 2026-10-06). When the game blocks or forbids an action and names MelloUI
-- (ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN; MelloUI, the Companion, or a
-- feature addon of its own, MelloUI_<Feature>: 0.20.0), what a report needs is
-- kept as it happens: the function the game named, whether a fight was on,
-- the time, the zone, MelloUI's version and memory, the Gamepad UI, and the
-- game profiler's figures for MelloUI this session (its average, its slowest
-- frame, its frames over 1 / 5 / 10 / 50 / 100 ms: SessionLines -- a frame
-- past the client's per-addon budget is the known cause of blocked calls,
-- docs: the Lua budget throttle). The last BUG.KEEP in MelloUIDB.blocked (the
-- saved variables' own root, never a profile: a block often ends in a
-- /reload); one chat line a session per function (Chat Notices). /mellobug
-- shows them in the copy window to paste into a report; /mellobug clear
-- forgets them. Two events, nothing else at login; nothing a frame.
-- (1.2.1) A block costs next to nothing. The same function blocked again
-- within REPEAT s only counts on its entry (a hooked method the game blocks
-- on every global cooldown is one entry, not one a block), and the memory is
-- measured at most once in MEMORY_GAP s: UpdateAddOnMemoryUsage walks every
-- addon's heap, and charged to MelloUI on every block it kept MelloUI's
-- budget empty, so the game went on blocking (a player's 2 fps in a fight
-- after learning a stance, 0.23.1, until a restart).
--------------------------------------------------------------------------------
local BUG = { KEEP = 10, REPEAT = 60, MEMORY_GAP = 60, told = {}, seen = {},
	ADDONS = { MelloUI = true, MelloUI_Companion = true } }
Perf.bug = BUG

function BUG.List()
	local db = rawget(_G, "MelloUIDB")
	if type(db) ~= "table" then
		return nil
	end
	if type(db.blocked) ~= "table" then
		db.blocked = {}
	end
	return db.blocked
end

-- (2.1.13; Nixxen, MelloCro/MelloUI#1, BaQstein and the user: a bag item blocked at random, never on demand, so no taint log
-- is on when it comes) The report names what it can from the block itself, then and only then. The game's event comes inside
-- the blocked call, so the stack is the way there (BUG.Way: the real name of an "UNKNOWN()"); what stood under the mouse
-- (BUG.Under); the other addons (BUG.Others); and which of the values the game's own bag click reads on its way to the call
-- are not the game's any more, with who wrote them (BUG.NotGames; ContainerFrameItemButton_OnClick's right click).
BUG.WAY, BUG.NAMES, BUG.OTHERS = 14, 40, 40
BUG.READS = { "ContainerFrameItemButton_OnClick", "ContainerFrame_GetExtendedPriceString", "MerchantFrame_ResetRefundItem",
	"BankUtil_IsAccountBankDepositRefundable", "IsModifiedClick", "GetCursorInfo", "SpellCanTargetItem", "SpellCanTargetItemID",
	"CreateFromMixins", "ItemLocationMixin", "ItemLocation", "ItemButtonUtil", "EventRegistry", "C_Container", "C_Item",
	"C_AuctionHouse", "C_ItemSocketInfo", "C_MountJournal", "C_Spell", "AuctionHouseFrame", "AzeriteRespecFrame",
	"RuneforgeFrame", "MerchantFrame", "BankFrame", "GuildBankFrame", "MailFrame", "AuctionFrame", "TradeFrame",
	"ItemUpgradeFrame", "ObliterumForgeFrame", "ChallengesKeystoneFrame", "StackSplitFrame" }
BUG.FIELDS = { "MerchantFrame", "BankFrame", "ItemButtonUtil", "ItemLocation", "C_Container" }

-- (2.1.61; a controller player's report, 2026-11-19: ten blocks in the game's own gamepad code, each way cut at its 14th
-- line -- all the game's, nothing on where the run began, and the user could capture no taint log) The way keeps both of
-- its ends: its first BUG.WAY lines (the blocked call and what led to it) and its last BUG.WAY_END (where the run began:
-- an event of the game's, or a function of MelloUI's), the middle left out and counted.
BUG.WAY_END = 10

function BUG.Way()
	local ok, text = pcall(rawget(_G, "debugstack") or error, 1, 30, BUG.WAY_END + 4)
	if not ok or Secret(text) or type(text) ~= "string" then
		return nil
	end
	local all = {}
	for line in text:gmatch("[^\n]+") do
		if not line:find("Core/Perf.lua", 1, true) and not line:find("'pcall'", 1, true) then
			all[#all + 1] = (line:gsub("Interface/AddOns/", "")):sub(1, 150)
		end
	end
	if #all <= BUG.WAY + BUG.WAY_END then
		return all
	end
	local way = {}
	for i = 1, BUG.WAY do
		way[i] = all[i]
	end
	way[#way + 1] = format("... (%d lines left out)", #all - BUG.WAY - BUG.WAY_END)
	for i = #all - BUG.WAY_END + 1, #all do
		way[#way + 1] = all[i]
	end
	return way
end

-- (2.1.61, the same report) In the game's Gamepad UI a block comes out of the game's own controller code: its window
-- manager, its navigation, its binding stack and its crossbar pass every window that opens or closes through tables of
-- their own, and one value in them that is no longer the game's stops the next protected call. Which values, and who
-- wrote them: the tables' own keys and the lists one step under them, asked of the game (issecurevariable), at the
-- block and only in the Gamepad UI. A frame found under a key is named, never walked (its fields are its own).
BUG.PAD = {
	{ "SmartNavigation" }, { "SmartNavigation", "activeInfo" },
	{ "GamepadMode", "FrameControlsManager" },
	{ "GamepadSharedUtility", "InputBindingManager" },
	{ "GamepadMainActionBarFrame" }, { "GamepadMainActionBarFrame", "PageUnit" },
	{ "GamepadMainActionBarFrame", "PageUnit", "actionBars" },
	{ "LootFrame" }, { "ActionBarButtonEventsFrame" }, { "ActionBarActionEventsFrame" },
}
BUG.PAD_NAMES, BUG.PAD_KEYS = 40, 400   -- the names kept; the keys looked at in one table

function BUG.PadNotGames()
	local check = rawget(_G, "issecurevariable")
	if type(check) ~= "function" then
		return nil
	end
	local out, seen = {}, {}
	local function Walk(label, t, deep)
		if type(t) ~= "table" or seen[t] then
			return
		end
		seen[t] = true
		local n = 0
		for k, v in pairs(t) do
			n = n + 1
			if n > BUG.PAD_KEYS or #out >= BUG.PAD_NAMES then
				return
			end
			local kind = type(k)
			if kind == "string" or kind == "number" then
				local name = label .. "." .. tostring(k)
				local ok, secure, by = pcall(check, t, k)
				if ok and secure == false then
					out[#out + 1] = format("%s (%s)", name:sub(1, 90), tostring(by))
				end
				if deep and type(v) == "table" and rawget(v, 0) == nil then
					Walk(name, v, false)
				end
			end
		end
	end
	local asked = {}   -- [a global's name] = true: asked once, though several paths begin at it
	for _, path in ipairs(BUG.PAD) do
		local t = rawget(_G, path[1])
		local label = path[1]
		if not asked[label] then
			asked[label] = true
			local ok, secure, by = pcall(check, label)
			if ok and secure == false and #out < BUG.PAD_NAMES then
				out[#out + 1] = format("%s (%s)", label, tostring(by))
			end
		end
		for i = 2, #path do
			t = type(t) == "table" and rawget(t, path[i]) or nil
			label = label .. "." .. path[i]
		end
		Walk(label, t, true)
	end
	-- (2.1.81) the registries' notes of the footers' events: nil values, which no walk of a table passes
	pcall(BUG.PadEvents, function(name, notes, key)
		local ok, secure, by = pcall(check, notes, key)
		if ok and secure == false and #out < BUG.PAD_NAMES then
			out[#out + 1] = format("%s (%s)", name, tostring(by))
		end
	end)
	return out
end

-- (2.1.65; the same controller player's report on 2.1.63, 2026-11-21: the window manager's focus, its bindings and the
-- crossbar's active bar named MelloUI's, while the forbidden call itself came out of the game's own close of the quest
-- window -- so those values were written earlier, on another way, which a block's own way cannot show) Who writes the
-- Gamepad UI's state, as it happens: post-hooks (the game's calls run as before, nothing of its own is written) on the
-- entries of its window manager, its binding stack and the crossbar's page switch. After each call the values that run
-- the pad are asked of the game (issecurevariable); one that turns from the game's to an addon's keeps the call, the
-- frame or set it was for, the time and the way there: the first BUG.WRITES of them a session, in every later entry
-- and under NOW. Hooked as the Gamepad UI comes on (at the login when it is on already, or its bus 'gamepad'), never
-- out of it; a few asks a call, and the manager is called as its windows open and close.
BUG.WRITES, BUG.WRITE_KEYS = 6, 60
BUG.writes = {}
BUG.writeState = {}   -- [a value's name] = the addon that wrote it, as last seen; false: the game's
BUG.WRITE_HOOKS = {
	-- (2.1.69) its navigation first: in the same run its calls come before the bindings they set
	{ path = { "SmartNavigation" }, slots = { "activeInfo", "bindingActive", "currentButton" }, lists = { "activePanels" },
		-- (2.1.81) TriggerEvent: the navigation's own events ("SelectedButtonUpdated", ...), for BUG.PadEvents below
		-- (2.1.84) RegisterCallback / UnregisterCallback: a footer's or a window's own slot in the navigation's registry
		-- (BUG.Ran, below)
		methods = { "HandlePanelOpen", "RefreshButtonGroups", "RemovePanelInfo", "SetActiveFrame", "ActivateBinding",
			"DeactivateBinding", "EnterFocusGroup", "TriggerEvent", "RegisterCallback", "UnregisterCallback" }, walk = "NavWalk" },
	-- (2.1.84) RefreshFocus: the one place "Gamepad.RefreshFrameFocus" is fired from
	{ path = { "GamepadMode", "FrameControlsManager" }, slots = { "isUIFocused", "focusedFrame" },
		methods = { "FrameShown", "FrameHidden", "SetUIFocusState", "ToggleUIFocus", "FocusFrame", "HandlePopupShown",
			"HandlePopupHide", "SuspendFrame", "UnsuspendFrame", "HideActiveFrames", "RefreshFocus" } },
	-- (2.1.84) the game's own registry: only a footer's slot for the manager's event (`only`: the call's first value;
	-- its TriggerEvent is every part of the game's, and is left alone: RefreshFocus above is this event's)
	{ path = { "EventRegistry" }, slots = {}, methods = { "RegisterCallback", "UnregisterCallback" },
		only = { ["Gamepad.RefreshFrameFocus"] = true } },
	{ path = { "GamepadSharedUtility", "InputBindingManager" }, slots = { "currentCoreBindingActive" },
		lists = { "activeBindings" }, methods = { "AddBindingSet", "RemoveSet" } },
	{ path = { "GamepadMainActionBarFrame", "PageUnit" }, slots = { "activeBar" }, methods = { "SetActiveActionBar" } },
}

-- a frame's name, a binding set's own name, or what it is (never a secret)
function BUG.WhatName(v)
	if type(v) ~= "table" then
		return (not Secret(v) and v ~= nil) and tostring(v):sub(1, 40) or ""   -- (the secret test first)
	end
	local own = rawget(v, "name")
	if type(own) == "string" and not Secret(own) then
		return own:sub(1, 60)
	end
	local get = rawget(v, 0) ~= nil and (v.GetDebugName or v.GetName) or nil
	local ok, name = pcall(get or error, v)
	if ok and type(name) == "string" and not Secret(name) and name ~= "" then
		return name:sub(1, 60)
	end
	return "a table"
end

-- the addon that wrote t[key] as the game says, or false (the game's own, or no answer)
local function WrittenBy(check, t, key)
	local ok, secure, by = pcall(check, t, key)
	if ok and secure == false then
		return tostring(by)
	end
	return false
end

-- (2.1.69; the controller player's 2.1.68 report: the first values that turned MelloUI's were written at the game's
-- own open of the mailbox, inside the mail window's pad focus, while the window manager's own focus values, written
-- just before its navigation took the window, stayed the game's -- so the run took its taint in the navigation: its
-- list of open windows, or its walk of the window for buttons (Blizzard_GamepadSmartNavigation Utility.FindButtons:
-- every frame in the window, each one's OnMouseUp and OnMouseDown asked)) Where in the navigation's own tables of a
-- window (`panel`: the call's, else the one it stands in) a value is an addon's. The walk puts the buttons it finds in
-- a list one by one, and a run once tainted stays so: the first entry that is an addon's (looked for from the list's
-- end, halved) is the frame whose reading took it, the one before it the last read clean; a group or the window's
-- info an addon's: before the walk. One line per finding, nil for none
function BUG.NavWalk(check, nav, panel)
	local panels = rawget(nav, "activePanels")
	if type(panel) ~= "table" then
		local active = rawget(nav, "activeInfo")
		panel = type(active) == "table" and rawget(active, "frame") or nil
	end
	if type(panels) ~= "table" or type(panel) ~= "table" then
		return nil
	end
	local info
	for i = 1, math.min(#panels, 40) do
		local p = rawget(panels, i)
		if type(p) == "table" and rawget(p, "frame") == panel then
			info = p
			break
		end
	end
	if not info then
		return nil
	end
	local out, name = {}, BUG.WhatName(panel)
	local function Mark(what, tbl, key)
		local by = type(tbl) == "table" and WrittenBy(check, tbl, key)
		if by then
			out[#out + 1] = format("%s: %s (%s)", name, what, by)
		end
		return type(tbl) == "table" and rawget(tbl, key) or nil
	end
	-- the first entry of a list that is an addon's: none while its last is the game's
	local function First(what, list)
		local n = type(list) == "table" and #list or 0
		if n == 0 or not WrittenBy(check, list, n) then
			return
		end
		local lo, hi = 1, n
		while lo < hi do
			local mid = math.floor((lo + hi) / 2)
			if WrittenBy(check, list, mid) then
				hi = mid
			else
				lo = mid + 1
			end
		end
		local entry = rawget(list, lo)
		entry = type(entry) == "table" and (rawget(entry, "scrollFrame") or entry) or entry
		local before = lo > 1 and rawget(list, lo - 1) or nil
		before = type(before) == "table" and (rawget(before, "scrollFrame") or before) or before
		out[#out + 1] = format("%s: %s %d of %d, %s, after %s (%s)", name, what, lo, n, BUG.WhatName(entry),
			before ~= nil and BUG.WhatName(before) or "none", tostring(WrittenBy(check, list, lo)))
	end
	local groups = Mark("its info's buttonGroups", info, "buttonGroups")
	if type(groups) ~= "table" then
		return out[1] and out or nil
	end
	local main = Mark("its groups' mainGroup", groups, "mainGroup")
	Mark("its groups' subGroups", groups, "subGroups")
	if type(main) == "table" then
		First("button", Mark("its buttons list", main, "buttons"))
		local scrolls = Mark("its scroll frames list", main, "scrollFrames")
		First("scroll frame", scrolls)
		for i = 1, math.min(type(scrolls) == "table" and #scrolls or 0, 20) do
			local s = rawget(scrolls, i)
			if type(s) == "table" then
				First(format("button in scroll frame %d (%s):", i, BUG.WhatName(rawget(s, "scrollFrame"))), rawget(s, "buttons"))
			end
		end
	end
	return out[1] and out or nil
end

-- (2.1.78; the controller player's 2.1.75 report, 2026-11-23: the chat's footer bindings written as an addon's inside
-- the game's own focus of a chat window (FloatingChatFrame FocusGamepad, from the Open Chat key), while the manager's
-- focus, written just before it, and the navigation stayed the game's) The values that focus reads between the two,
-- asked of the game as a write is noted: those an addon wrote, one line each ("" when none)
BUG.CHAT_GLOBALS = { "DEFAULT_CHAT_FRAME", "LAST_ACTIVE_CHAT_EDIT_BOX", "ACTIVE_CHAT_EDIT_BOX", "SELECTED_DOCK_FRAME",
	"GENERAL_CHAT_DOCK", "CHAT_FRAMES", "CHAT_FRAME_TEXTURES", "CHAT_FRAME_FADE_TIME", "DEFAULT_CHATFRAME_ALPHA",
	"GamepadScrollBarHint" }
BUG.CHAT_KEYS = { "oldAlpha", "isDocked", "dock", "editBox", "ScrollBar", "buttonFrame", "footer" }
function BUG.ChatSuspects(check)
	local out = {}
	local function Mark(label, t, key)
		local by = type(t) == "table" and WrittenBy(check, t, key)
		if by then
			out[#out + 1] = format("%s (%s)", label, by)
		end
	end
	for _, name in ipairs(BUG.CHAT_GLOBALS) do
		Mark(name, _G, name)
	end
	local main = rawget(_G, "DEFAULT_CHAT_FRAME")
	local box = type(main) == "table" and rawget(main, "editBox") or nil
	Mark("DEFAULT_CHAT_FRAME.editBox.languageID", box, "languageID")
	local dock = rawget(_G, "GENERAL_CHAT_DOCK")
	if type(dock) == "table" then
		Mark("GENERAL_CHAT_DOCK.selected", dock, "selected")
		Mark("GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES", dock, "DOCKED_CHAT_FRAMES")
		local list = rawget(dock, "DOCKED_CHAT_FRAMES")
		for i = 1, math.min(type(list) == "table" and #list or 0, 20) do
			Mark(format("GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES[%d]", i), list, i)
		end
	end
	local frames = rawget(_G, "CHAT_FRAMES")
	for i = 1, math.min(type(frames) == "table" and #frames or 0, 20) do
		local name = rawget(frames, i)
		local cf = type(name) == "string" and not Secret(name) and rawget(_G, name) or nil
		if type(cf) == "table" then
			for _, key in ipairs(BUG.CHAT_KEYS) do
				Mark(name .. "." .. key, cf, key)
			end
		end
	end
	return out
end

-- (2.1.81; the controller player's 2.1.79 report, read against the game's own source of that build) Where the loot
-- window's pad bindings took MelloUI's name: its footer registers three callbacks as it shows (PromptedBindingFooter
-- ShowAndActivateBindings: EventRegistry's "Gamepad.RefreshFrameFocus", the navigation's "SelectedButtonUpdated" and
-- "SelectedButtonEnabledStateChanged"), and a registry's RegisterCallback reads its own note of that event
-- (CallbackRegistry.lua UnregisterCallback: deferredCallbacks[event]) with no barrier -- a note every TriggerEvent of
-- the event ends by writing (= nil). One of those events fired inside an addon's run leaves the note that addon's,
-- nil as it is, and the next footer reads it. The notes, asked of the game with every watched call (Look: one that
-- turns an addon's keeps the call and the way there -- the run that left it), and under "Not the game's" at a block
BUG.PAD_EVENTS = {
	{ "SmartNavigation", "SelectedButtonUpdated" }, { "SmartNavigation", "SelectedButtonEnabledStateChanged" },
	{ "EventRegistry", "Gamepad.RefreshFrameFocus" },
}
BUG.PAD_EVENT_NOTES = { "deferredCallbacks", "executingEvents" }
function BUG.PadEvents(Look)
	for _, e in ipairs(BUG.PAD_EVENTS) do
		local reg = rawget(_G, e[1])
		if type(reg) == "table" then
			for _, key in ipairs(BUG.PAD_EVENT_NOTES) do
				local notes = rawget(reg, key)
				if type(notes) == "table" then
					Look(format("%s.%s[%s]", e[1], key, e[2]), notes, e[2])
				end
			end
		end
	end
end

-- (2.1.84; the controller player's report on 2.1.83, 2026-11-24: the loot window and the chat no longer turned the pad's
-- state, the game's quest log opened from its ring menu still did -- its footer's bindings written as MelloUI's inside
-- the game's own focus of its map, and nothing of MelloUI's on that way; read against the game's source of that build
-- and traced in the simulator with the Gamepad UI forced on, no call of MelloUI's reached the game's pad code at the
-- open) The note that turns a footer is left EARLIER, by a call of the game's pad code that ran inside an addon's run
-- (its window manager's entries, its navigation's, a registry slot of a footer's events: BUG.WRITE_HOOKS), and the
-- game cannot be asked for it afterwards: it is a nil. So the run itself is caught: with each watched call the way
-- there is read, and a line of MelloUI's on it (this file's own left out) keeps the call, the line and the way -- the
-- first BUG.RUNS of them a session, each call and line once.
BUG.RUNS = 6
BUG.runs = {}
BUG.runSeen = {}
BUG.OURS = "AddOns/MelloUI"

-- the first line of MelloUI's own on the way here (nil: none, or no way to read)
function BUG.Ours()
	local ok, text = pcall(rawget(_G, "debugstack") or error, 1, 40, 20)
	if not ok or Secret(text) or type(text) ~= "string" then
		return nil
	end
	for line in text:gmatch("[^\n]+") do
		if line:find(BUG.OURS, 1, true) and not line:find("Core/Perf.lua", 1, true) then
			return ((line:gsub("^%s+", "")):gsub("Interface/AddOns/", "")):sub(1, 150)
		end
	end
	return nil
end

function BUG.Ran(label, method, arg)
	if #BUG.runs >= BUG.RUNS then
		return
	end
	local ours = BUG.Ours()
	if not ours then
		return
	end
	local what = format("%s:%s(%s)", label, method, BUG.WhatName(arg))
	local key = what .. "\t" .. ours
	if BUG.runSeen[key] then
		return
	end
	BUG.runSeen[key] = true
	local okW, way = pcall(BUG.Way)
	BUG.runs[#BUG.runs + 1] = {
		at = BUG.beganAt and math.floor(GetTime() - BUG.beganAt) or nil,
		what = what, ours = ours, combat = InCombatLockdown() and true or false,
		way = okW and way or nil,
	}
end

function BUG.Wrote(spec, label, t, method, arg)
	pcall(BUG.Ran, label, method, arg)
	if #BUG.writes >= BUG.WRITES then
		return
	end
	local check = rawget(_G, "issecurevariable")
	if type(check) ~= "function" then
		return
	end
	local found
	local function Look(name, tbl, key)
		local by = WrittenBy(check, tbl, key)
		local was = BUG.writeState[name]
		BUG.writeState[name] = by
		if by and by ~= was then
			found = found or {}
			found[#found + 1] = format("%s (%s)", name, by)
		end
	end
	for _, key in ipairs(spec.slots) do
		Look(label .. "." .. key, t, key)
	end
	for _, key in ipairs(spec.lists or {}) do
		local list = rawget(t, key)
		if type(list) == "table" then
			local n = 0
			for k in pairs(list) do
				n = n + 1
				if n > BUG.WRITE_KEYS then
					break
				end
				if type(k) == "string" or type(k) == "number" then
					Look(label .. "." .. key .. "." .. tostring(k), list, k)
				end
			end
		end
	end
	pcall(BUG.PadEvents, Look)   -- (2.1.81: the registries' notes of the footers' three events)
	local walk = spec.walk and BUG[spec.walk]
	if walk then
		local okN, lines = pcall(walk, check, t, arg)
		for _, line in ipairs(okN and type(lines) == "table" and lines or {}) do
			if not BUG.writeState[line] then   -- (each finding once)
				BUG.writeState[line] = true
				found = found or {}
				found[#found + 1] = line
			end
		end
	end
	if not found then
		return
	end
	local okC, suspects = pcall(BUG.ChatSuspects, check)
	for _, line in ipairs(okC and type(suspects) == "table" and suspects or {}) do
		if not BUG.writeState["chat: " .. line] then   -- (each once)
			BUG.writeState["chat: " .. line] = true
			found[#found + 1] = "chat: " .. line
		end
	end
	local okW, way = pcall(BUG.Way)
	-- (2.1.84) the control the game's pad cursor stood on: the footers ask it what it offers
	local nav = rawget(_G, "SmartNavigation")
	local cursor = type(nav) == "table" and rawget(nav, "currentButton") or nil
	BUG.writes[#BUG.writes + 1] = {
		at = BUG.beganAt and math.floor(GetTime() - BUG.beganAt) or nil,
		what = format("%s:%s(%s)", label, method, BUG.WhatName(arg)),
		values = found, combat = InCombatLockdown() and true or false,
		way = okW and way or nil,
		cursor = type(cursor) == "table" and BUG.WhatName(cursor) or nil,
	}
end

-- the hooks, once each table is there (a table not there yet: asked again the next time the Gamepad UI comes on)
function BUG.HookPad()
	if type(rawget(_G, "issecurevariable")) ~= "function" or not MelloUI.Safe.GamepadUI() then
		return
	end
	for _, spec in ipairs(BUG.WRITE_HOOKS) do
		if not spec.hooked then
			local t, label = rawget(_G, spec.path[1]), spec.path[1]
			for i = 2, #spec.path do
				t = type(t) == "table" and rawget(t, spec.path[i]) or nil
				label = label .. "." .. spec.path[i]
			end
			if type(t) == "table" then
				spec.hooked = true
				BUG.padWatched = BUG.padWatched or (BUG.beganAt and math.floor(GetTime() - BUG.beganAt) or 0)
				local only = spec.only
				for _, method in ipairs(spec.methods) do
					if type(t[method]) == "function" then
						rawHook(t, method, function(_, arg)
							-- (a table of the game's own with other users: only the calls named, the secret test first)
							if only and (Secret(arg) or type(arg) ~= "string" or not only[arg]) then
								return
							end
							pcall(BUG.Wrote, spec, label, t, method, arg)
						end)
					end
				end
			end
		end
	end
end

-- the report's lines of it; nil while it never watched (out of the Gamepad UI all session)
function BUG.WriteLines()
	if not BUG.padWatched then
		return nil
	end
	local out = {}
	if #BUG.writes == 0 then
		out[1] = format("The Gamepad UI's state: nothing written outside the game since %d s in.", BUG.padWatched)
	end
	for _, w in ipairs(BUG.writes) do
		out[#out + 1] = format("The Gamepad UI's state written outside the game, %s s in, %s, by %s: %s%s", tostring(w.at or "?"),
			w.combat and "in combat" or "out of combat", w.what, table.concat(w.values, ", "),
			w.cursor and (" (the pad's cursor on " .. w.cursor .. ")") or "")
		for _, line in ipairs(w.way or {}) do
			out[#out + 1] = "  " .. line
		end
	end
	-- (2.1.84) the game's pad code run from MelloUI's own: the runs that can leave a footer's note (BUG.Ran)
	if #BUG.runs == 0 then
		out[#out + 1] = format("The game's pad code: none of it run from MelloUI's own since %d s in.", BUG.padWatched)
	end
	for _, r in ipairs(BUG.runs) do
		out[#out + 1] = format("The game's pad code run from MelloUI's own, %s s in, %s: %s, from %s", tostring(r.at or "?"),
			r.combat and "in combat" or "out of combat", r.what, r.ours)
		for _, line in ipairs(r.way or {}) do
			out[#out + 1] = "  " .. line
		end
	end
	return out
end

function BUG.Under()
	local ok, list = pcall(rawget(_G, "GetMouseFoci") or error)
	local f = ok and type(list) == "table" and list[1] or nil
	if type(f) ~= "table" then
		return nil, nil
	end
	local okN, name = pcall(f.GetDebugName, f)
	local text = "an unnamed frame"
	if okN and not Secret(name) and type(name) == "string" then
		text = name:sub(1, 90)
	end
	local okB, bag = pcall(f.GetBagID, f)
	local okS, slot = pcall(f.GetID, f)
	if okB and okS and not Secret(bag) and not Secret(slot) and type(bag) == "number" and type(slot) == "number" then
		local okI, id = pcall(C_Container.GetContainerItemID, bag, slot)
		text = format("%s: bag %d, slot %d, item %s", text, bag, slot, okI and not Secret(id) and tostring(id) or "?")
	end
	return text, f
end

function BUG.NotGames(button)
	local check = rawget(_G, "issecurevariable")
	if type(check) ~= "function" then
		return nil
	end
	local out = {}
	local function Note(label, ok, secure, by)
		if ok and not secure and #out < BUG.NAMES then
			out[#out + 1] = format("%s (%s)", label, tostring(by))
		end
	end
	local function Fields(label, t)
		if type(t) == "table" then
			for k in pairs(t) do
				if type(k) == "string" then
					Note(label .. "." .. k, pcall(check, t, k))
				end
			end
		end
	end
	for _, name in ipairs(BUG.READS) do
		Note(name, pcall(check, name))
	end
	for _, name in ipairs(BUG.FIELDS) do
		Fields(name, rawget(_G, name))
	end
	local bank = rawget(_G, "BankFrame")
	Fields("BankFrame.BankPanel", type(bank) == "table" and bank.BankPanel or nil)
	Fields("button", button)
	return out
end

function BUG.Others()
	local A = rawget(_G, "C_AddOns")
	if not (type(A) == "table" and A.GetNumAddOns and A.GetAddOnInfo and A.IsAddOnLoaded) then
		return nil
	end
	local out = {}
	for i = 1, A.GetNumAddOns() do
		local name = A.GetAddOnInfo(i)
		if #out < BUG.OTHERS and type(name) == "string" and not name:find("^MelloUI") and not name:find("^Blizzard_")
			and A.IsAddOnLoaded(i) then
			out[#out + 1] = name
		end
	end
	return out
end

-- (2.1.15; the user's report and scans, 2026-11-07: the same bags read 43 of 43 buttons tainted in one session and none
-- in the next two, cause unknown) How this session's bag buttons were made, for the report: one row per run of buttons
-- made alike, each with the way there. Only when a button is made (Modules/BagWindow.lua's SlotButton); not saved
-- until a block keeps a copy.
-- (The user's login, the same day: 27 clean buttons from code that was not secure, so the code's taint alone does not do it.)
BUG.MADE, BUG.MADE_WAY = 6, 14
BUG.made = {}

function BUG.Secure()
	local ok, secure = pcall(rawget(_G, "issecure") or error)
	return ok and secure == true
end

function BUG.Made(button, secure)
	local check = rawget(_G, "issecurevariable")
	local okC, clean = pcall(check or error, button, "SetItem")
	local tainted = okC and clean == false
	local combat = InCombatLockdown() and true or false
	local co = rawget(_G, "coroutine")
	local okR, running = pcall(co and co.running or error)
	local thread = okR and running ~= nil
	local last = BUG.made[#BUG.made]
	if last and last.tainted == tainted and last.secure == secure and last.combat == combat and last.thread == thread then
		last.n = last.n + 1
		return
	end
	if #BUG.made >= BUG.MADE then
		return
	end
	local okW, way = pcall(BUG.Way)
	BUG.made[#BUG.made + 1] = { n = 1, tainted = tainted, secure = secure, combat = combat, thread = thread,
		at = BUG.beganAt and math.floor(GetTime() - BUG.beganAt) or nil, way = okW and way or nil }
end

function BUG.MadeLines()
	local out = { format("This session began with %s.", BUG.began or "a login or reload not seen") }
	if #BUG.made == 0 then
		out[2] = "Bag buttons: none made yet."
	end
	for _, m in ipairs(BUG.made) do
		out[#out + 1] = format("Bag buttons: %d made %s s in, %s, the code %s, %s%s", m.n, tostring(m.at or "?"),
			m.tainted and "TAINTED" or "clean", m.secure and "secure" or "not secure", m.combat and "in combat" or "out of combat",
			m.thread and ", in a coroutine" or "")
		for i, line in ipairs(m.way or {}) do
			if i <= BUG.MADE_WAY then
				out[#out + 1] = "  " .. line
			end
		end
	end
	return out
end

function BUG.Capture(event, addon, func)
	addon = Secret(addon) and nil or addon
	if not (type(addon) == "string" and (BUG.ADDONS[addon] or addon:find("^MelloUI_"))) then
		return
	end
	func = (type(func) == "string" and not Secret(func)) and func or "?"
	local list = BUG.List()
	if not list then
		return
	end
	-- the same function again soon: its entry counts it, nothing else is done
	local at = GetTime()
	local seen = BUG.seen[func]
	if seen and at - seen.at < BUG.REPEAT and seen.entry.func == func then
		seen.at = at
		seen.entry.count = (seen.entry.count or 1) + 1
		return
	end
	local lines = {}
	SessionLines(function(...)
		lines[#lines + 1] = format(...)
	end)
	local okZ, zone = pcall(GetRealZoneText)
	local okC, combat = pcall(InCombatLockdown)
	if not BUG.memoryAt or at - BUG.memoryAt >= BUG.MEMORY_GAP then
		BUG.memoryAt = at
		BUG.memoryKB = AddonMemory()
	end
	local kb = BUG.memoryKB   -- (measured within the last minute)
	local okU, under, button = pcall(BUG.Under)
	local okW, way = pcall(BUG.Way)
	local okT, tainted = pcall(BUG.NotGames, okU and button or nil)
	local okO, others = pcall(BUG.Others)
	local okM, made = pcall(BUG.MadeLines)
	local gamepad = MelloUI.Safe.GamepadUI and MelloUI.Safe.GamepadUI() and true or false
	local okP, pad = false, nil
	if gamepad then
		okP, pad = pcall(BUG.PadNotGames)   -- (the Gamepad UI's own tables: only while it is on)
	end
	local okR, writes = pcall(BUG.WriteLines)
	local entry = {
		when = date("%Y-%m-%d %H:%M:%S"),
		what = event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked",
		addon = addon, func = func,
		combat = okC and combat and true or false,
		zone = okZ and type(zone) == "string" and not Secret(zone) and zone or "?",
		version = MelloUI.version, memory = kb and math.floor(kb + 0.5) or nil,
		gamepad = gamepad,
		lines = lines,
		under = okU and under or nil, way = okW and way or nil,
		tainted = okT and tainted or nil, others = okO and others or nil, made = okM and made or nil,
		pad = okP and pad or nil, writes = okR and writes or nil,
	}
	table.insert(list, 1, entry)
	BUG.seen[func] = { entry = entry, at = at }
	while #list > BUG.KEEP do
		local gone = table.remove(list)
		local s = gone and BUG.seen[gone.func]
		if s and s.entry == gone then
			BUG.seen[gone.func] = nil
		end
	end
	if not BUG.told[func] then
		BUG.told[func] = true
		MelloUI:Notice("The game blocked an action of %s (%s). /mellobug shows a report to send.", addon, func)
	end
end

-- the report: every kept block, newest first, and the session now
function BUG.Report()
	local L = {}
	local function add(...)
		L[#L + 1] = format(...)
	end
	local okB, build, buildNo = pcall(GetBuildInfo)
	add("MelloUI %s, blocked actions report (%s)", tostring(MelloUI.version), date("%Y-%m-%d %H:%M"))
	add("Client %s (%s)", okB and tostring(build) or "?", okB and tostring(buildNo) or "?")
	local list = BUG.List() or {}
	if #list == 0 then
		add("")
		add("No blocked action kept. When the game says MelloUI was blocked, type /mellobug right after it.")
	end
	for i, e in ipairs(list) do
		add("")
		add("%d. %s  %s %s by the game: %s%s", i, e.when or "?", e.addon or "?", e.what or "blocked", e.func or "?",
			(tonumber(e.count) or 1) > 1 and format(" (%d times)", e.count) or "")
		add("   %s, %s%s; MelloUI %s, %s KB", e.combat and "in combat" or "out of combat", e.zone or "?",
			e.gamepad and ", Gamepad UI" or "", tostring(e.version), e.memory and tostring(e.memory) or "?")
		for _, line in ipairs(e.lines or {}) do
			add("  %s", line)
		end
		if e.under then
			add("   Under the mouse: %s", e.under)
		end
		if e.tainted then
			add("   Not the game's: %s", #e.tainted > 0 and table.concat(e.tainted, ", ") or "nothing the bag click reads")
		end
		if e.pad then
			add("   Not the game's, in its Gamepad UI: %s", #e.pad > 0 and table.concat(e.pad, ", ")
				or "nothing in its window manager, navigation, binding stack or crossbar")
		end
		for _, line in ipairs(e.writes or {}) do
			add("   %s", line)
		end
		if e.others and #e.others > 0 then
			add("   Other addons: %s", table.concat(e.others, ", "))
		end
		for _, line in ipairs(e.made or {}) do
			add("   %s", line)
		end
		if e.way then
			add("   The way to it:")
			for _, line in ipairs(e.way) do
				add("     %s", line)
			end
		end
	end
	add("")
	add("NOW")
	SessionLines(add)
	for _, line in ipairs(BUG.MadeLines()) do
		add("  %s", line)
	end
	local okR, writes = pcall(BUG.WriteLines)
	for _, line in ipairs(okR and writes or {}) do
		add("  %s", line)
	end
	add("")
	add("To find the cause: /console taintLog 2, /reload, do what you did; the game writes Logs/taint.log.")
	return table.concat(L, "\n")
end

BUG.frame = CreateFrame("Frame")
BUG.frame:RegisterEvent("ADDON_ACTION_BLOCKED")
BUG.frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
BUG.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
BUG.frame:SetScript("OnEvent", function(_, event, addon, func)
	if event == "PLAYER_ENTERING_WORLD" then
		-- (isInitialLogin, isReloadingUi: BUG.MadeLines; once)
		BUG.frame:UnregisterEvent(event)
		BUG.began = (addon and "a login") or (func and "a reload") or nil
		BUG.beganAt = GetTime()
		pcall(BUG.HookPad)   -- (only while the Gamepad UI is on)
		return
	end
	local ok, err = pcall(BUG.Capture, event, addon, func)
	if not ok then
		geterrorhandler()(err)
	end
end)

if type(MelloUI.On) == "function" then   -- (Core's bus; a world without it: the login's check alone)
	MelloUI:On("gamepad", function(on)
		if on then
			pcall(BUG.HookPad)
		end
	end, "Perf: the blocked actions report watches the Gamepad UI's state")
end

SLASH_MELLOBUG1 = "/mellobug"
SlashCmdList.MELLOBUG = function(msg)
	if strtrim(msg or ""):lower() == "clear" then
		local list = BUG.List()
		if list then
			wipe(list)
		end
		wipe(BUG.told)
		wipe(BUG.seen)
		MelloUI:Print("Blocked actions forgotten.")
		return
	end
	MelloUI:ShowText("Blocked actions", BUG.Report())
end
