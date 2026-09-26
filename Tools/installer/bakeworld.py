# The lupa world for the Full bake: the REAL Core/Core.lua, Core/Backup.lua
# and every TOC file (module bodies run against the stand-ins of world.py
# beside this file), on Lua 5.1 as the game runs it -- so a number is
# written by tostring exactly as the game writes it ("n0", never "n0.0").
# Read-only on the addon.
import os
import re
import sys
import time

import lupa.lua51 as L51

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, TOOLS)
import world as W  # noqa: E402  (PRELUDE and ROOT only; its runtime is not used)
import paths as P  # noqa: E402  (Tools/paths.py: where the build data lives)

# the addon folder, "/"-terminated (ROOT + "Core/Core.lua")
ROOT = W.ROOT


def build_data(*parts):
    """A path in the build data folder beside the addon (MelloUI-BuildData,
    or MELLOUI_BUILD_DATA when set, as Tools/paths.py resolves it): the
    snapshots the bake reads and what it writes, never inside the addon."""
    base = os.environ.get("MELLOUI_BUILD_DATA", "").strip() or P.SIBLING
    return os.path.join(base, *parts)

LOADF = r'''function(src, name, ns)
  local f, e = loadstring(src, name)
  if not f then return "SYNTAX " .. e end
  debug.sethook(function() error("__budget") end, "", 50000000)
  local ok, err = pcall(f, "MelloUI", ns)
  debug.sethook()
  if not ok and not tostring(err):find("__budget") then return tostring(err) end
  return nil
end'''

AFTER_CORE = r'''
local M = _G.MelloUI
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
for _, flag in ipairs({ "initialized", "initializingModules", "dbIsTemporary", "restoredFromBackup",
    "profileAppliedAtLogin", "menuTipTimer", "adoptTicker", "printHold" }) do
    rawset(M, flag, false)
end
'''

# every module method under an instruction budget (a module body that loops
# forever over the stand-ins is cut and reported like any module error);
# Lua 5.1 form of compute_options.py's login()
BUDGET = r'''
TICKS, DEADLINE, CUTS, OVER = 0, false, 0, false
local rawpcall = pcall
pcall = function(f, ...)
    if OVER then return false, "__budget" end
    return rawpcall(f, ...)
end
RAWPCALL = rawpcall
debug.sethook(function()
    TICKS = TICKS + 1
    if DEADLINE and TICKS > DEADLINE then
        if not OVER then CUTS = CUTS + 1 end
        OVER = true
        error("__budget", 0)
    end
end, "", 1000)
local function pack(...) return { n = select("#", ...), ... } end
for name, module in pairs(MelloUI.modules) do
    for _, method in ipairs({ "OnInit", "OnEnable", "OnDisable", "OnSettingChanged" }) do
        local fn = rawget(module, method)
        if type(fn) == "function" then
            module[method] = function(...)
                local saved, wasOver, start = DEADLINE, OVER, TICKS
                DEADLINE = TICKS + 300
                local r = pack(RAWPCALL(fn, ...))
                DEADLINE, OVER = saved and (saved + (TICKS - start)) or false, wasOver
                if not r[1] then error(r[2], 0) end
                return unpack(r, 2, r.n)
            end
        end
    end
end
local M = MelloUI
M.Print = function(self, msg, ...)
    local ok, line = RAWPCALL(string.format, tostring(msg), ...)
    PRINTED[#PRINTED + 1] = ok and line or tostring(msg)
end
rawset(M, "CorePerf", false)
M.ScheduleBackup = function() end
'''


def toc_files():
    toc = [l.strip().replace("\\", "/") for l in open(ROOT + "MelloUI.toc", encoding="utf-8-sig").read().split("\n")]
    return [l for l in toc if l.endswith(".lua") and l not in ("Core/Core.lua", "Core/Perf.lua")]


def _fatal(path, err):
    """A load error that matters to the bake: Core, Backup, the profiles file,
    or any file that registers a module (its settings and keep list)."""
    if path in ("Core/Core.lua", "Core/Backup.lua", "Media/Profiles.lua"):
        return True
    try:
        src = open(ROOT + path, encoding="utf-8").read()
    except OSError:
        return True
    return "RegisterModule(" in src


def make_world():
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(W.PRELUDE)
    loadf = lua.eval(LOADF)
    ns = lua.eval("{}")
    errs = {}
    e = loadf(open(ROOT + "Core/Core.lua", encoding="utf-8").read(), "@Core/Core.lua", ns)
    if e:
        errs["Core/Core.lua"] = e
    lua.execute(AFTER_CORE)
    for f in toc_files():
        try:
            src = open(ROOT + f, encoding="utf-8").read()
        except FileNotFoundError:
            errs[f] = "MISSING"
            continue
        e = loadf(src, "@" + f, ns)
        if e:
            errs[f] = e[:300]
    return lua, errs, ns


def make_world_retry(attempts=5, wait=60, log=print):
    """A world whose Core and module files all load; a file another task is
    editing right now (wave 3 in the same tree) is waited for: up to
    `attempts` tries, `wait` seconds apart. Errors in files that register no
    module are reported, not fatal."""
    for i in range(attempts):
        lua, errs, ns = make_world()
        fatal = {k: v for k, v in errs.items() if _fatal(k, v)}
        if not fatal:
            for k, v in errs.items():
                log("  (not fatal) %s: %s" % (k, v[:160]))
            return lua, errs, ns, i + 1
        log("load try %d of %d failed in %s" % (i + 1, attempts, ", ".join(sorted(fatal))))
        for k, v in sorted(fatal.items()):
            log("    %s: %s" % (k, v[:200]))
        if i + 1 < attempts:
            time.sleep(wait)
    raise SystemExit("the addon did not load in %d tries: a file is mid-edit or broken" % attempts)


def py(lua, v):
    if L51.lua_type(v) == "table":
        return {(k if isinstance(k, (int, float)) else str(k)): py(lua, v[k]) for k in list(v.keys())}
    return v


def to_lua(lua, v):
    if isinstance(v, dict):
        t = lua.table()
        for k, x in v.items():
            if x is None:
                continue
            t[k] = to_lua(lua, x)
        return t
    if isinstance(v, (list, tuple)):
        t = lua.table()
        for i, x in enumerate(v):
            t[i + 1] = to_lua(lua, x)
        return t
    return v


def entries(text):
    """[(module, key, raw value)] of a settings text; flags as ('!', name, raw)."""
    out = []
    for e in text.split(";"):
        if not e:
            continue
        k, _, v = e.partition("=")
        if k.startswith("!"):
            out.append(("!", k[1:], v))
        else:
            m, _, key = k.partition(".")
            out.append((m, key, v))
    return out


def entry_map(text):
    return {("!" + k if m == "!" else m + "." + k): v for m, k, v in entries(text)}


def profiles_line_re():
    return re.compile(r'^\t\t\["MelloUI"\] = "(?:[^"\\]|\\.)*",$', re.M)
