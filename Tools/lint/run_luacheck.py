"""Run luacheck (pure Lua, runner API, honours .luacheckrc) under lupa; lfs is stubbed with Python.
Usage: python run_luacheck.py file.lua ...   (exit 1 on warnings/errors)"""
import os, sys
import lupa
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "luacheck", "src").replace("\\", "/")
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'package.path = "{SRC}/?.lua;{SRC}/?/init.lua;" .. package.path')

def attributes(path, what=None):
    try:
        st = os.stat(path)
    except OSError:
        return None
    mode = "directory" if os.path.isdir(path) else "file"
    if what == "mode":
        return mode
    if what == "modification":
        return int(st.st_mtime)
    return lua.table(mode=mode, modification=int(st.st_mtime))

def dir_(path):
    it = iter([".", ".."] + os.listdir(path))
    def nxt(*_):
        try:
            return next(it)
        except StopIteration:
            return None
    return nxt

def mkdir(path):
    os.makedirs(path, exist_ok=True)
    return True

lfs = lua.table(attributes=attributes, dir=dir_, mkdir=mkdir, currentdir=lambda: os.getcwd())
lua.globals().python_lfs = lfs
lua.execute('package.preload["lfs"] = function() return python_lfs end')

run = lua.eval('''
function(files)
    local runner = require "luacheck.runner"
    local names = {}
    for i = 1, #files do names[i] = {path = files[i]} end
    local checker, err = runner.new({config = ".luacheckrc", codes = true, color = false, formatter = "default", cache = false})
    assert(checker, err)
    local report = assert(checker:check(names))
    local out = assert(checker:format(report))
    local w, e, f = 0, 0, 0
    for _, fr in ipairs(report) do
        if fr.fatal then f = f + 1 else
            for _, issue in ipairs(fr) do if issue.code:sub(1, 1) == "0" then e = e + 1 else w = w + 1 end end
        end
    end
    return out, w, e, f
end''')
out, w, e, f = run(lua.table_from(sys.argv[1:]))
print(out)
sys.exit(1 if (w + e + f) > 0 else 0)
