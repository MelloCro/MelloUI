-- Stand-ins for the fitter's tests (lupa, Lua 5.1): MelloUI.Safe, Perf:Scope,
-- Kit:NextFrame (a frame queue the test steps), C_Timer.After, UIParent, the clock.
MelloUI = {}
ns = { MelloUI = MelloUI }
-- a secret stand-in: a userdata, which the fit's table copies pass through
-- unchanged (a table would be copied into a plain one before the test) and
-- which errors on arithmetic and comparison like a real secret; every time
-- IsSecret is asked about it is counted
SECRET = newproxy(true)
getmetatable(SECRET).__tostring = function() return "[secret]" end
secretAsks = 0
MelloUI.Safe = {
	IsSecret = function(v)
		if v == SECRET then
			secretAsks = secretAsks + 1
			return true
		end
		return false
	end,
	Number = function(v)
		if v == SECRET or type(v) ~= "number" then return nil end
		return v
	end,
}
scopes = {}
MelloUI.Perf = { Scope = function(self, name) scopes[#scopes + 1] = name; return {} end }

-- Kit:NextFrame as in Modules/Kit.lua: fn(key) once on the next frame
local nextKeys, nextFns = {}, {}
nextAsks, timerAsks = 0, 0
MelloUI.Kit = {
	NextFrame = function(self, key, fn)
		nextAsks = nextAsks + 1
		if nextFns[key] == nil then nextKeys[#nextKeys + 1] = key end
		nextFns[key] = fn
	end,
}
C_Timer = { After = function(d, fn) timerAsks = timerAsks + 1; nextKeys[#nextKeys + 1] = fn; nextFns[fn] = fn end }
function Pending() return #nextKeys end
-- one frame: what was asked for runs once
local spareKeys, spareFns = {}, {}
function RunFrame()
	if #nextKeys == 0 then return 0 end   -- (an idle frame of the stand-in makes nothing)
	local keys, fns = nextKeys, nextFns
	nextKeys, nextFns = spareKeys, spareFns
	spareKeys, spareFns = keys, fns
	local n = #keys
	for i = 1, n do
		local key = keys[i]
		local fn = fns[key]
		keys[i], fns[key] = nil, nil
		if fn == key then fn() else fn(key) end
	end
	return n
end
function geterrorhandler() return function(e) error(e, 0) end end

UIParent = { w = 1920, h = 1080 }
function UIParent:GetSize() return self.w, self.h end

-- the stand-in clock: VM instructions counted by a hook, IPM of them a ms
instr = 0
IPM = 50000
function InstrClock() return instr / IPM end
-- (Lua 5.1 keeps a hook's Lua function per thread: a coroutine made after
-- this gets the same counting hook, so the fit's own coroutine is counted)
local hookFn, hookStep
function StartCount(step)
	hookStep = step or 50
	hookFn = function() instr = instr + hookStep end
	debug.sethook(hookFn, "", hookStep)
end
function StopCount()
	hookFn = nil
	debug.sethook()
end
local rawCreate = coroutine.create
coroutine.create = function(fn)
	local co = rawCreate(fn)
	if hookFn then
		debug.sethook(co, hookFn, "", hookStep)
	end
	return co
end

-- a Lua value as JSON with every number exact (lupa hands an integral
-- number over as a Python int, which drops the sign of -0.0)
local function Num(x)
	if x ~= x then return "NaN" end
	if x == 0 and 1 / x < 0 then return "-0.0" end
	return string.format("%.17g", x)
end
local function Str(s)
	return '"' .. s:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end
function ToJSON(v)
	local t = type(v)
	if t == "number" then return Num(v) end
	if t == "string" then return Str(v) end
	if t == "boolean" then return v and "true" or "false" end
	if t ~= "table" then return "null" end
	local n, count = #v, 0
	for _ in pairs(v) do count = count + 1 end
	local out = {}
	if count == n and n > 0 then
		for i = 1, n do out[i] = ToJSON(v[i]) end
		return "[" .. table.concat(out, ",") .. "]"
	end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do out[#out + 1] = Str(tostring(k)) .. ":" .. ToJSON(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end

function Load(path)
	local fh = assert(io.open(path, "rb"))
	local src = fh:read("*a")
	fh:close()
	local chunk = assert(loadstring(src, "@Core/LayoutFit.lua"))
	chunk("MelloUI", ns)
	return MelloUI.LayoutFit
end
