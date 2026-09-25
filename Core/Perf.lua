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
			return frame:HookScript(script, fn, ...)
		end
		if prewrapped[fn] then
			scope.nPassed = scope.nPassed + 1
			return frame:HookScript(script, fn, ...)
		end
		local kind = script == "OnUpdate" and "update" or "script"
		scope.nWraps = scope.nWraps + 1
		return frame:HookScript(script, Wrap(Row(name, kind, script .. " on " .. FrameLabel(frame, name)), fn), ...)
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
	if Perf.loadedAt then
		-- a load opened after login still open here never saw its addon
		-- loaded (its LoadAddOn failed): dropped, not counted up to now
		loadName = nil
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
	if r.limit and now() - r.t0 >= r.limit * 1000 then
		Perf:Stop()
	end
end)

function Perf:IsRecording()
	return recording
end

function Perf:Start(seconds)
	if recording then
		MelloUI:Print("Already recording. /melloperf stop ends it.")
		return
	end
	for _, row in pairs(rows) do
		row.calls, row.time, row.max, row.mem, row.over = 0, 0, 0, 0, 0
	end
	depth = 0
	local P, E = Profiler()
	if P and E.RecentAverageTime then
		GetAddonMetric, GetOverallMetric, RECENT = P.GetAddOnMetric, P.GetOverallMetric, E.RecentAverageTime
	else
		GetAddonMetric, GetOverallMetric = nil, nil
	end
	rec = {
		t0 = now(), limit = seconds and seconds > 0 and seconds or nil,
		frames = 0, recent = 0, samples = 0, recentAll = 0, samplesAll = 0,
		before = Counters(),
		memStart = AddonMemory(), combat = InCombatLockdown and InCombatLockdown() or false,
	}
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
	elseif Perf.loadedAt and loadName and LoadOf(addon) then
		CloseLoad(now())
	end
end)

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
	elseif cmd == "load" then
		MelloUI:ShowText("Performance: loading", Perf:LoadReport())
	else
		MelloUI:ShowText("Performance", Perf:Overview())
	end
end
