# The stand-in game for the installer's tools (Tools/installer): a lupa world
# with the REAL Core/Core.lua and Core/Backup.lua and every module file's
# RegisterModule (their bodies run against dummies). Read-only on the addon.
# bakeworld.py uses PRELUDE and ROOT; make_world() is the plain (newer Lua)
# form the installer build's prototypes used.
import os, lupa

HERE = os.path.dirname(os.path.abspath(__file__))
# the addon folder (this file is Tools/installer/world.py), with the trailing
# slash the loaders join paths onto
ROOT = os.path.normpath(os.path.join(HERE, "..", "..")).replace("\\", "/") + "/"

PRELUDE = r'''
local dummy
local mt = {}
mt.__index = function(t, k) if type(k) == "number" then return nil end return dummy end
mt.__call = function() return dummy end
mt.__newindex = function() end
mt.__concat = function(a, b) return "" end
mt.__len = function() return 0 end
mt.__lt = function() return false end
mt.__le = function() return false end
mt.__unm = function() return 0 end
mt.__add = function() return 0 end mt.__sub = mt.__add mt.__mul = mt.__add mt.__div = mt.__add
mt.__tostring = function() return "dummy" end
dummy = setmetatable({}, mt)
DUMMY = dummy
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
-- the Lua 5.1 and WoW string/math globals the addon calls (this runtime is newer)
unpack = unpack or table.unpack
tremove, format, strsub, strlower, strupper, strfind, strmatch, gsub, strrep =
	table.remove, string.format, string.sub, string.lower, string.upper, string.find, string.match, string.gsub, string.rep
floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
issecretvalue = function() return false end
InCombatLockdown = function() return false end
debugprofilestop = function() return 0 end
time = os.time
C_AddOns = { GetAddOnMetadata = function() return "test" end }
PRINTED = {}
print = function(...) PRINTED[#PRINTED + 1] = table.concat({ ... }, " ") end
-- frames keep what is written on them; unknown methods are no-ops, and a
-- Create* method gives another frame-like object (a font string, a texture,
-- an animation group), so file bodies that dress what they make run on
local fmt = {}
fmt.__index = function(t, k)
	if type(k) == "number" then return nil end
	-- a frame's methods are CapitalCase; a lowercase field was never set
	-- (MelloUI is such a frame: its flags must read nil when cleared)
	if type(k) == "string" and k:sub(1, 1):match("%l") then return nil end
	if type(k) == "string" and k:sub(1, 6) == "Create" then
		return function() return setmetatable({}, fmt) end
	end
	return function() return nil end
end
CreateFrame = function() return setmetatable({}, fmt) end
-- the chat window count the game defines (a dummy table here broke
-- UIModifications.lua's CHAT_FRAMES loop, so its OnEnable was never defined)
NUM_CHAT_WINDOWS = 10
TIMERS = {}
C_Timer = { After = function(d, fn) TIMERS[#TIMERS + 1] = fn end,
	NewTimer = function(d, fn) TIMERS[#TIMERS + 1] = fn return { Cancel = function() end } end,
	NewTicker = function() return { Cancel = function() end } end }
ERRORS, LASTERROR = 0, false
geterrorhandler = function() return function(e) ERRORS = ERRORS + 1 LASTERROR = e end end
hooksecurefunc = function() end
setmetatable(_G, { __index = function(_, k) return dummy end })
'''

LOADF = r'''function(src, name, ns)
  local f, e = load(src, name)
  if not f then return "SYNTAX " .. e end
  debug.sethook(function() error("__budget") end, "", 50000000)
  local ok, err = pcall(f, "MelloUI", ns)
  debug.sethook()
  if not ok and not tostring(err):find("__budget") then return tostring(err) end
  return nil
end'''


def make_world(load_modules=True):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    loadf = lua.eval(LOADF)
    ns = lua.eval("{}")
    errs = {}
    err = loadf(open(ROOT + "Core/Core.lua", encoding="utf-8").read(), "@Core/Core.lua", ns)
    if err:
        errs["Core/Core.lua"] = err
    lua.execute('''
        local M = _G.MelloUI
        -- Perf stand-in: every scope's helpers are plain pass-throughs
        local scope = setmetatable({
            C_Timer = C_Timer,
            SetScript = function(f, s, fn) end,
            HookScript = function(f, s, fn) end,
            hooksecurefunc = function() end,
            Shared = function(label, fn) return fn end,
        }, { __index = function() return function() end end })
        M.Perf = setmetatable({ Scope = function() return scope end }, { __index = function() return function() end end })
        M.Perf.loadedAt = nil
        M.db = { version = 1, enabled = {}, modules = {}, profiles = {} }
        -- MelloUI is a stand-in frame whose unknown fields read as functions
        -- (truthy): the login flags are set plainly, or every module would
        -- count as registered after login and run its OnInit at load (UI
        -- Modifications' OnInit then marks no panel hidden)
        for _, flag in ipairs({ "initialized", "initializingModules", "dbIsTemporary", "restoredFromBackup",
            "profileAppliedAtLogin", "menuTipTimer", "adoptTicker", "printHold" }) do
            rawset(M, flag, false)
        end
    ''')
    if load_modules:
        toc = [l.strip().replace("\\", "/") for l in open(ROOT + "MelloUI.toc", encoding="utf-8-sig").read().split("\n")]
        files = [l for l in toc if l.endswith(".lua") and l not in ("Core/Core.lua", "Core/Perf.lua")]
        for f in files:
            try:
                src = open(ROOT + f, encoding="utf-8").read()
            except FileNotFoundError:
                errs[f] = "MISSING"
                continue
            e = loadf(src, "@" + f, ns)
            if e:
                errs[f] = e[:200]
    else:
        e = loadf(open(ROOT + "Core/Backup.lua", encoding="utf-8").read(), "@Core/Backup.lua", ns)
        if e:
            errs["Core/Backup.lua"] = e
    return lua, errs
