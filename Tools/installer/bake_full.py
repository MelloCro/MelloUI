"""Bake "Full experience": the shipped profile "MelloUI" in Media/Profiles.lua
(the installer's Full setup and the Profiles page's "MelloUI").

  python Tools/installer/bake_full.py [--snapshot PATH] [--check] [--write] [--deps] [--tries N] [--wait S]

The text is made by the addon's own code, in a Lua 5.1 world with the REAL
Core, Backup and every TOC file of the working tree:
  1. the snapshot (a saved MelloUI.lua) is logged in: every module's OnInit /
     OnEnable runs, so the current code's one-time steps run as at a login;
  2. the three windows that keep their place in UI Modifications' position
     store since hardening wave 3 get it there by their modules' own
     migration functions (MOVES below): Chat moves the whisper windows' old
     corner at its OnEnable, so the login step 1 already did it; the bake
     calls VoiceOver's MoveOldPlace itself (the game runs it at the overlay's
     first show). Every move is checked against its rule, written again
     here: the store after the moves must be the saved store plus exactly
     the documented entries. A snapshot still holding Route.arrowX / arrowY
     is refused (that move measures the arrow's frame: show the arrow once
     in game first);
  3. FULL_DROP back to the defaults;
  4. the fitter's design-size places laid over (the real Core/LayoutFit.lua:
     LayoutFit:Fit(info, DESIGN_W, DESIGN_H, LayoutFit:Inputs())): the four
     Edit Mode frames' store places removed, the window places as fitted
     (at the design size: the snapshot's own), QuestTracker.pos cleared, the
     tracker's and Quest List's sizes as fitted; layoutFitFor NOT baked. The
     moved places the fitter does not place are checked on the screen at the
     design size: every whisper window (the popup's size, all six cascade
     places) and the anchors of the other two;
  5. MelloUI:SaveProfile("MelloUI") (StripPersonal with the current keep
     lists), then the installer's own personal rules for keep entries not in
     the modules yet: seenVersion, ^layoutAsked_, layoutFitFor and any
     one-time flag by its name (...Migrated, Folded, Once, Asked, Shown,
     Applied, Version, Done).

The snapshot lives in the build data beside the addon (MelloUI-BuildData,
or MELLOUI_BUILD_DATA): it holds a player's own data and never goes into the
repository. full_snapshot.txt beside this file names it (relative to that
folder); a --write with --snapshot records the new one there, copying a live
saved file (WTF/Account/<account>/SavedVariables/MelloUI.lua) into
installer/full_<date>/ first, so --check and the release bake it again.
What the bake writes goes to the build data too: output/installer_bake/
full.txt, entry.txt (the Lua line) and bake_report.json.

  (no option)  bake, print the text's length and sha256 and how it compares
               with the "MelloUI" entry in Media/Profiles.lua. Read-only.
  --check      the same, then exit 1 unless Media/Profiles.lua holds exactly
               this text and no profile besides the shipped "MelloUI"
               (Tools/release.py runs it and refuses a release on exit 1).
  --write      put the line into Media/Profiles.lua: only the "MelloUI"
               entry changes, nothing else in the file.
  --deps       list the files this bake reads, then exit (1 if one is
               missing).

Who writes Media/Profiles.lua: this bake writes the "MelloUI" entry and
nothing else. The watcher (Tools/bake_routes.py --watch) keeps the player's
own saved profiles in the file too (so they ship with the addon); it never writes
"MelloUI" or the built-in "Everything Off" and leaves the file's head as it
is. A release ships only "MelloUI", so --check names any other profile.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import time

import bakeworld as B

# The snapshot the shipped Full is baked from, relative to the build data
# folder: full_snapshot.txt beside this file (a --write from another snapshot
# records it there), else the 2026-09-24 21:9 setup.
SNAPSHOT_RECORD = os.path.join(B.HERE, "full_snapshot.txt")
DEFAULT_SNAPSHOT = "installer/2026-09-24_21x9_3440x1440/MelloUI.SavedVariables.lua"


def recorded_snapshot():
    try:
        with open(SNAPSHOT_RECORD, encoding="utf-8") as fh:
            rel = fh.read().strip() or DEFAULT_SNAPSHOT
    except OSError:
        rel = DEFAULT_SNAPSHOT
    return B.build_data(*rel.replace("\\", "/").split("/"))


SNAP = recorded_snapshot()
PROFILES = B.ROOT + "Media/Profiles.lua"
OUT = os.path.join(B.P.OUTPUT, "installer_bake")
FIT_COMMON = os.path.join(B.HERE, "fit")
FITTING = os.path.join(B.HERE, "fitting")

FULL_DROP = ["VoiceOver.collectLines", "CharacterPanel.slotBorder", "BackpackPanel.itemBorder"]
EDIT_MODE_FRAMES = ["MinimapCluster", "DamageMeter", "ChatFrame1", "ObjectiveTrackerFrame"]
# the installer's additions to the keep lists and the one-time flag name rule
# (the installer build's test_options.py name check)
EXTRA_PERSONAL = {"UIModifications": ["seenVersion", "^layoutAsked_", "layoutFitFor", "questTrackerKitMigrated"]}
ONE_TIME = re.compile(r"(Migrated|Folded|Once|Asked|Shown|Applied|Version|Done)$")
LEGACY_PLACES = ["VoiceOver.overlayPoint", "VoiceOver.overlayRelativePoint", "VoiceOver.overlayX", "VoiceOver.overlayY",
                 "Chat.whisperPopupPos", "Route.arrowX", "Route.arrowY"]

# The places moved into the store (UI Modifications' positions) by the module
# that owns the window: the store key, the migration function (found by its
# name among the modules' upvalues, in its file), the old keys it removes,
# and when the game runs it. `bake: True` = the bake calls it after the login
# (Chat's is called again too, a no-op after its OnEnable, so a snapshot with
# Chat off still gets the move).
MOVES = {
    "whisper": {"fn": "MovePopupPlace", "file": "@Modules/Chat.lua", "old": ["Chat.whisperPopupPos"],
                "when": "Chat's OnEnable (a login step since the wave 3 integration fix)"},
    "voiceOverlay": {"fn": "MoveOldPlace", "file": "@Modules/VoiceOver.lua",
                     "old": ["VoiceOver.overlayPoint", "VoiceOver.overlayRelativePoint", "VoiceOver.overlayX", "VoiceOver.overlayY"],
                     "when": "the overlay's first show (the bake calls it)"},
    "routeArrow": {"fn": None, "file": "@Modules/Route.lua", "old": ["Route.arrowX", "Route.arrowY"],
                   "when": "the arrow's first show (needs its frame: a snapshot with the old keys is refused)"},
}
ANCHORS = {"TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"}
ANCHOR_WS = re.compile(r"\s+")
# the whisper windows: one size (Modules/Chat.lua POPUP_W, POPUP_H), the n-th
# one opens 24 units right and down of the stored corner, six places round
WHISPER_CASCADE = 6
WHISPER_STEP = 24

# every file this bake reads besides the addon's own
DEPENDENCIES = [
    ("snapshot (default; build data, never in the repository)", SNAP),
    ("which snapshot (relative to the build data)", SNAPSHOT_RECORD),
    ("this bake", os.path.join(B.HERE, "bake_full.py")),
    ("the lupa world", os.path.join(B.HERE, "bakeworld.py")),
    ("the bake test", os.path.join(B.HERE, "test_bake.py")),
    ("stand-in game (PRELUDE)", os.path.join(B.HERE, "world.py")),
    ("where the build data is (Tools/paths.py)", os.path.join(B.TOOLS, "paths.py")),
    ("fitter test helpers", os.path.join(FIT_COMMON, "common.py")),
    ("fitter test world", os.path.join(FIT_COMMON, "world.lua")),
    ("golden helpers", os.path.join(FITTING, "golden.py")),
    ("reference fitter (imported by golden.py)", os.path.join(FITTING, "fit.py")),
    ("HUD geometry (imported by golden.py)", os.path.join(FITTING, "hud.py")),
    ("layout string codec", os.path.join(FITTING, "lib", "layoutcodec.py")),
    ("frame rects (imported by hud.py)", os.path.join(FITTING, "lib", "rects_orig.py")),
    ("approved layout's info", os.path.join(FITTING, "goldens", "source.json")),
]


def missing_dependencies():
    return [(what, path) for what, path in DEPENDENCIES if not os.path.exists(path)]


LUA_STEPS = r'''
local M = MelloUI

-- a function kept as an upvalue somewhere under the roots, by its name and
-- the file it was written in
function FindUpvalues(roots, wanted)
    local seen, queue, head, found = {}, {}, 1, {}
    for _, r in ipairs(roots) do queue[#queue + 1] = r end
    local function push(x)
        local t = type(x)
        if (t == "function" or t == "table") and x ~= DUMMY and not seen[x] then queue[#queue + 1] = x end
    end
    while head <= #queue do
        local v = queue[head]
        head = head + 1
        if not seen[v] then
            seen[v] = true
            if type(v) == "function" then
                local i = 1
                while true do
                    local name, val = debug.getupvalue(v, i)
                    if not name then break end
                    local file = wanted[name]
                    if file and type(val) == "function" and found[name] == nil
                        and debug.getinfo(val, "S").source == file then
                        found[name] = val
                    end
                    push(val)
                    i = i + 1
                end
            else
                for k, x in next, v do
                    push(k)
                    push(x)
                end
            end
        end
    end
    return found
end

-- the position store as it is now (a copy: the entries are flat)
function Store()
    local um = M:GetModuleDB("UIModifications")
    local out = {}
    if type(um.positions) == "table" then
        for k, p in pairs(um.positions) do
            if type(p) == "table" then
                local c = {}
                for f, v in pairs(p) do c[f] = v end
                out[k] = c
            else
                out[k] = p
            end
        end
    end
    return out
end

function Login()
    M.db = MelloUIDB
    M.ApplyDefaults(M.db, { enabled = {}, modules = {}, profiles = {} })
    for name in M:IterateModules() do M:GetModuleDB(name) end
    TEXT_SAVED = M:SerializeSettings()
    STORE_SAVED = Store()
    PRINTED = {}
    M.initialized = true
    M.initializingModules = true
    for _, module in M:IterateModules() do M:InitModule(module) end
    M.initializingModules = nil
    TEXT_LOGIN = M:SerializeSettings()
    STORE_LOGIN = Store()
end

-- wanted: { [function name] = "@Modules/<Module>.lua" }
function MovePlaces(wanted)
    local roots = { M }
    for _, file in pairs(wanted) do
        roots[#roots + 1] = M.modules[file:match("Modules/(%w+)%.lua")]
    end
    local found = FindUpvalues(roots, wanted)
    local out = {}
    for name, file in pairs(wanted) do
        local fn = found[name]
        if not fn then error("migration " .. name .. " (" .. file .. ") not found: renamed or gone?") end
        local modName = file:match("Modules/(%w+)%.lua")
        local module = M.modules[modName]
        -- (the function reads the module's own M.db, set by its OnInit)
        if rawget(module, "db") == nil then rawset(module, "db", M:GetModuleDB(modName)) end
        fn()
        out[#out + 1] = name
    end
    local route = M:GetModuleDB("Route")
    if route.arrowX ~= nil or route.arrowY ~= nil then
        error("the snapshot still holds Route.arrowX / arrowY: that move measures the arrow's frame; show the Route arrow once in game (or /route arrow reset) and take the snapshot again")
    end
    TEXT_MIGRATED = M:SerializeSettings()
    STORE_MOVED = Store()
    return out
end

function DropFull(list)
    for _, spec in ipairs(list) do
        local name, key = spec:match("^([^.]+)%.(.+)$")
        M:GetModuleDB(name)[key] = M.modules[name].defaults[key]
    end
end

local function Copy(p)
    local c = {}
    for k, v in pairs(p) do c[k] = v end
    return c
end

-- the fitter at the design size, fed the live (migrated) settings as the
-- installer feeds it; its places laid over the settings
function DesignPlaces(info, sw, sh)
    local LF = rawget(M, "LayoutFit")
    local W, H = LF.DESIGN_W, LF.DESIGN_H
    local inputs = LF:Inputs()
    local fitted, places, report = LF:Fit(info, W, H, inputs, { screenW = sw, screenH = sh })
    if not fitted or not report.pass then
        error("the design-size fit did not pass: " .. tostring(report and report.verdict))
    end
    local um = M:GetModuleDB("UIModifications")
    if type(um.positions) ~= "table" then um.positions = {} end
    for _, k in ipairs(places.remove or {}) do um.positions[k] = nil end
    for k, p in pairs(places.windows or {}) do um.positions[k] = Copy(p) end
    local qt = M:GetModuleDB("QuestTracker")
    if places.questTracker.clearPos then qt.pos = nil end
    qt.maxHeight, qt.width = places.questTracker.maxHeight, places.questTracker.width
    M:GetModuleDB("QuestList").width = places.questList.width
    -- places.layoutFitFor: one machine's fact, never baked
    STORE_FITTED = Store()
    return { W = W, H = H, verdict = report.verdict, layoutName = report.layoutName, places = places, inputs = inputs }
end

function Save()
    local ok, why = M:SaveProfile("MelloUI")
    if not ok then error("SaveProfile: " .. tostring(why)) end
    return M.db.profiles.MelloUI
end
'''


def extra_personal(module, key):
    for e in EXTRA_PERSONAL.get(module, []):
        if e == key or (e.startswith("^") and re.search(e, key)):
            return True
    return bool(ONE_TIME.search(key))


def diff(a, b):
    ma, mb = B.entry_map(a), B.entry_map(b)
    out = []
    for k in sorted(set(ma) | set(mb)):
        if ma.get(k) != mb.get(k):
            out.append({"key": k, "from": ma.get(k), "to": mb.get(k)})
    return out


def design_info(lua):
    """The approved layout's game info (the fitter's golden source), checked
    against Media/EditModeLayout.lua's current string first."""
    sys.path.insert(0, FIT_COMMON)
    import common as FC  # noqa: E402  (the fitter tests' codec and golden helpers)
    src = FC.source_info()
    approved = FC.approved_string()
    again = FC.C.encode(FC.G.from_game_info(src, FC.C.decode(approved)))
    if again != approved:
        raise SystemExit("fitting/goldens/source.json is not the approved layout in Media/EditModeLayout.lua any more: "
                         "python Tools/installer/fitting/golden.py writes it again")
    return B.to_lua(lua, src)


def lua_literal(s):
    # as Tools/bake_routes.py writes a profile (lua_literal)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def entry_line(text):
    return '\t\t["MelloUI"] = ' + lua_literal(text) + ","


# what a login's one-time steps may change besides the moves (anything else
# stops the bake): a personal key or one-time flag, a FULL_DROP key, or a
# documented step
LOGIN_STEPS = {"UIModifications.questTrackerKit"}   # set once from TrackerPanel (UIModifications' OnEnable)


def raw_modules(snapshot):
    """The snapshot's module settings exactly as saved (plain Lua 5.1, no addon code)."""
    import lupa.lua51 as L51
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(snapshot, encoding="utf-8").read())
    mods = lua.eval("type(MelloUIDB) == 'table' and MelloUIDB.modules or {}")
    return B.py(lua, mods)


def _anchor(v):
    v = ANCHOR_WS.sub("", v).upper() if isinstance(v, str) else None
    return v if v in ANCHORS else None


def _num(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return v
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def expected_moves(mods):
    """{store key: entry} the moves must write, from the saved snapshot by
    each module's documented rule (the store's compact form: point nil =
    BOTTOMLEFT, relPoint nil = CENTER):
      Chat.whisperPopupPos {x, y} -> whisper {relPoint = BOTTOMLEFT, x, y};
        without two numbers the old key only goes;
      VoiceOver.overlayPoint / RelativePoint / X / Y -> voiceOverlay {point
        unless BOTTOMLEFT, relPoint (else the point) unless CENTER, x, y
        (0 when missing)}; without a clean point the old keys only go."""
    out = {}
    old = (mods.get("Chat") or {}).get("whisperPopupPos")
    if isinstance(old, dict):
        x, y = _num(old.get("x")), _num(old.get("y"))
        if x is not None and y is not None:
            out["whisper"] = {"relPoint": "BOTTOMLEFT", "x": x, "y": y}
    vo = mods.get("VoiceOver") or {}
    point = _anchor(vo.get("overlayPoint"))
    if point:
        rel = _anchor(vo.get("overlayRelativePoint")) or point
        e = {"x": _num(vo.get("overlayX")) or 0, "y": _num(vo.get("overlayY")) or 0}
        if point != "BOTTOMLEFT":
            e["point"] = point
        if rel != "CENTER":
            e["relPoint"] = rel
        out["voiceOverlay"] = e
    return out


def check_moves(mods, saved, login, moved):
    """Which move ran when: {store key: "login" | "bake"}. SystemExit when
    the store after the moves is not the saved store plus exactly the
    documented entries, or the login left the store in any other state."""
    want = dict(saved)
    want.update(expected_moves(mods))
    if moved != want:
        bad = sorted(k for k in set(moved) | set(want) if moved.get(k) != want.get(k))
        raise SystemExit("the position store after the moves is not the saved store plus the documented moves "
                         "(MOVES in bake_full.py): %s" % ["%s: %s, want %s" % (k, moved.get(k), want.get(k)) for k in bad])
    wrong = sorted(k for k in set(login) | set(saved) if login.get(k) != saved.get(k) and login.get(k) != want.get(k))
    if wrong:
        raise SystemExit("the login changed store entries no documented move writes: %s" % wrong)
    stages = {}
    for k in want:
        if saved.get(k) != want[k]:
            stages[k] = "login" if login.get(k) == want[k] else "bake"
    return stages


def _rect(p, w, h, W, H, dx=0, dy=0):
    """(left, bottom, right, top) of a w x h frame at a store place, in UI
    units from the screen's bottom-left."""
    def xy(a):
        fx = 0 if "LEFT" in a else 1 if "RIGHT" in a else 0.5
        fy = 0 if a.startswith("BOTTOM") else 1 if a.startswith("TOP") else 0.5
        return fx, fy
    rx, ry = xy(p.get("relPoint") or "CENTER")
    fx, fy = xy(p.get("point") or "BOTTOMLEFT")
    px, py = rx * W + (p.get("x") or 0) + dx, ry * H + (p.get("y") or 0) + dy
    left, bottom = px - fx * w, py - fy * h
    return left, bottom, left + w, bottom + h


def popup_size():
    src = open(B.ROOT + "Modules/Chat.lua", encoding="utf-8").read()
    m = re.search(r"^local POPUP_W, POPUP_H = (\d+), (\d+)", src, re.M)
    if not m:
        raise SystemExit("Modules/Chat.lua has no 'local POPUP_W, POPUP_H = <w>, <h>' line any more: teach bake_full.py "
                         "the whisper window's size")
    return int(m.group(1)), int(m.group(2))


def moved_on_screen(store, W, H):
    """[problem] for the moved places the fitter does not place, at W x H:
    every whisper window (its size, all six cascade places) inside the
    screen; the voice overlay's and the Route arrow's anchor on it."""
    out = []
    p = store.get("whisper")
    if p:
        w, h = popup_size()
        for i in range(WHISPER_CASCADE):
            step = i * WHISPER_STEP
            l, b, r, t = _rect(p, w, h, W, H, step, -step)
            if l < 0 or b < 0 or r > W or t > H:
                out.append("whisper window %d of %d at %.1f,%.1f .. %.1f,%.1f leaves the %.2f x %.2f screen"
                           % (i + 1, WHISPER_CASCADE, l, b, r, t, W, H))
    for key in ("voiceOverlay", "routeArrow"):
        p = store.get(key)
        if p:
            l, b, _, _ = _rect(p, 0, 0, W, H)
            if l < 0 or b < 0 or l > W or b > H:
                out.append("%s's anchor %.1f,%.1f is off the %.2f x %.2f screen" % (key, l, b, W, H))
    return out


def saved_text(snapshot, tries, wait, log):
    """The snapshot as saved: every module registered and OnInit run (its
    defaults complete), no OnEnable / OnDisable (no one-time step yet)."""
    lua, _, _, _ = B.make_world_retry(tries, wait, log)
    lua.execute(open(snapshot, encoding="utf-8").read())
    lua.execute(B.BUDGET)
    lua.execute(LUA_STEPS)
    lua.execute("for _, m in pairs(MelloUI.modules) do m.OnEnable = function() end; m.OnDisable = function() end end")
    lua.globals().Login()
    return lua.globals().TEXT_LOGIN


def unexpected(changes, lua, allowed=()):
    M = lua.globals().MelloUI
    bad = []
    for c in changes:
        k = c["key"]
        if k.startswith("!"):
            bad.append(k)   # a module switched by a login step: never expected
            continue
        m, _, key = k.partition(".")
        if k in allowed or k in FULL_DROP or k in LOGIN_STEPS or M.IsPersonalKey(M, m, key) or extra_personal(m, key):
            continue
        bad.append(k)
    return bad


def _moved_keys(stages, stage):
    """The keys a stage's moves may change: the old keys of every documented
    move (a malformed one is only removed) and, when that stage wrote a store
    entry, the store."""
    keys = [k for spec in MOVES.values() for k in spec["old"]]
    if stage in stages.values():
        keys.append("UIModifications.positions")
    return keys


def bake(snapshot=SNAP, tries=5, wait=60, log=print):
    text_saved = saved_text(snapshot, tries, wait, log)
    mods = raw_modules(snapshot)
    lua, errs, ns, tried = B.make_world_retry(tries, wait, log)
    lua.execute(open(snapshot, encoding="utf-8").read())
    lua.execute(B.BUDGET)
    lua.execute(LUA_STEPS)
    g = lua.globals()
    g.Login()
    wanted = {spec["fn"]: spec["file"] for spec in MOVES.values() if spec["fn"]}
    migrated = sorted(B.py(lua, g.MovePlaces(B.to_lua(lua, wanted))).values())
    stages = check_moves(mods, B.py(lua, g.STORE_SAVED), B.py(lua, g.STORE_LOGIN), B.py(lua, g.STORE_MOVED))
    g.DropFull(B.to_lua(lua, FULL_DROP))
    if lua.eval('rawget(MelloUI, "LayoutFit")') is None:
        loadf = lua.eval(B.LOADF)
        e = loadf(open(B.ROOT + "Core/LayoutFit.lua", encoding="utf-8").read(), "@Core/LayoutFit.lua", ns)
        if e:
            raise SystemExit("Core/LayoutFit.lua did not load: " + e)
    fit = g.DesignPlaces(design_info(lua), 3440, 1440)
    fit_py = B.py(lua, fit)
    fitted_store = B.py(lua, g.STORE_FITTED)
    off = moved_on_screen(fitted_store, fit_py["W"], fit_py["H"])
    if off:
        raise SystemExit("a moved place is off the screen at the design size (move that window in game, then take a "
                         "new snapshot): %s" % off)
    saved = g.Save()
    kept, dropped = [], []
    for m, k, v in B.entries(saved):
        (dropped if (m != "!" and extra_personal(m, k)) else kept).append((m, k, v))
    full = ";".join(("!" + k if m == "!" else m + "." + k) + "=" + v for m, k, v in kept)
    report = {
        "snapshot": snapshot,
        "loadTries": tried,
        "loadErrorsNotFatal": dict(errs),
        "budgetCuts": lua.eval("CUTS"),
        "moduleErrors": [str(x) for x in B.py(lua, lua.eval("PRINTED")).values() if "rror" in str(x)][:20],
        "lengths": {"saved": len(text_saved), "afterLogin": len(g.TEXT_LOGIN), "afterMoves": len(g.TEXT_MIGRATED),
                    "profile": len(saved), "full": len(full)},
        "loginChanges": diff(text_saved, g.TEXT_LOGIN),
        "migrations": migrated,
        "moves": {k: {"stage": v, "entry": fitted_store.get(k), "when": MOVES[k]["when"]} for k, v in sorted(stages.items())},
        "migrationChanges": diff(g.TEXT_LOGIN, g.TEXT_MIGRATED),
        "fullDrop": FULL_DROP,
        "fit": {"W": fit_py["W"], "H": fit_py["H"], "verdict": fit_py["verdict"], "layoutName": fit_py["layoutName"],
                "places": fit_py["places"]},
        "extraPersonalDropped": [m + "." + k + "=" + v for m, k, v in dropped],
        "sha256": sha(full),
        "text": full,
    }
    report["unexpectedChanges"] = (unexpected(report["loginChanges"], lua, _moved_keys(stages, "login"))
                                   + unexpected(report["migrationChanges"], lua, _moved_keys(stages, "bake")))
    if report["unexpectedChanges"]:
        raise SystemExit("the login or the moves changed settings the bake does not know: %s" % report["unexpectedChanges"])
    return full, report, lua


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def current_entry():
    src = open(PROFILES, encoding="utf-8").read()
    m = B.profiles_line_re().search(src)
    return src, m


SHIPPED_NAMES = ["MelloUI"]


def profile_names(src):
    return re.findall(r'^\t\t\["((?:[^"\\]|\\.)*)"\] = ', src, re.M)


def shipped_text(src):
    """The "MelloUI" text Media/Profiles.lua holds (as the game reads it), or None."""
    import lupa.lua51 as L51
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    try:
        lua.execute(src)
        return lua.eval("type(MelloUI_Profiles) == 'table' and type(MelloUI_Profiles.profiles) == 'table' "
                        "and MelloUI_Profiles.profiles.MelloUI or nil")
    except Exception:  # noqa: BLE001  (a file that does not load holds no Full)
        return None


def file_problems(src, m, full):
    """Why Media/Profiles.lua does not hold the shipped Full ([] when it does)."""
    names = profile_names(src)
    out = []
    others = [n for n in names if n not in SHIPPED_NAMES]
    if others:
        out.append("it holds the profiles %s besides the shipped %s: a player's own saved profiles, which the watcher "
                   "(Tools/bake_routes.py --watch) keeps there so they ship with the addon. A release would ship them to "
                   "every player: delete them on the Profiles page and /reload with the watcher running (or take their "
                   "lines out of the file), then check again" % (others, SHIPPED_NAMES))
    if not m:
        out.append('no ["MelloUI"] line in the shipped form (restore it: git -C "%s" checkout -- Media/Profiles.lua, '
                   'then python Tools/installer/bake_full.py --write)' % B.ROOT.rstrip("/"))
    elif m.group(0) != entry_line(full):
        out.append("the \"MelloUI\" entry is not this bake (a stale copy, or the snapshot or a migration changed): "
                   "python Tools/installer/bake_full.py --write, then python Tools/installer/test_bake.py")
    return out


def keep_snapshot(path):
    """Record the snapshot a --write baked from, where --check (and the
    release) bakes again: a file in the build data folder is recorded as it
    is; any other (a live saved file, which the game rewrites at every
    /reload) is copied to <build data>/installer/full_<date>/ first. Returns
    the recorded path, relative to the build data folder."""
    base = os.path.abspath(B.build_data())
    src = os.path.abspath(path)
    try:
        inside = os.path.commonpath([src, base]) == base
    except ValueError:   # (another drive)
        inside = False
    if not inside:
        dest = B.build_data("installer", "full_" + time.strftime("%Y-%m-%d_%H%M%S"), "MelloUI.SavedVariables.lua")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(src, dest)
        src = dest
    rel = os.path.relpath(src, base).replace("\\", "/")
    with open(SNAPSHOT_RECORD, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(rel + "\n")
    return rel


def text_diff(old, new):
    """One line per changed entry: '- key=value' (the file's), '+ key=value' (the bake's)."""
    mo, mn = B.entry_map(old or ""), B.entry_map(new)
    out = []
    for k in sorted(set(mo) | set(mn)):
        if mo.get(k) != mn.get(k):
            if k in mo:
                out.append("- %s=%s" % (k, mo[k]))
            if k in mn:
                out.append("+ %s=%s" % (k, mn[k]))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--snapshot", default=SNAP)
    ap.add_argument("--check", action="store_true", help="exit 1 unless Media/Profiles.lua holds this bake and only it")
    ap.add_argument("--write", action="store_true", help="write the \"MelloUI\" entry of Media/Profiles.lua")
    ap.add_argument("--deps", action="store_true", help="list the files this bake reads, then exit")
    ap.add_argument("--tries", type=int, default=5, help="load tries while another edit leaves a file broken")
    ap.add_argument("--wait", type=int, default=60, help="seconds between load tries")
    a = ap.parse_args()
    if a.deps:
        for what, path in DEPENDENCIES:
            print("%-8s %-56s %s" % ("ok" if os.path.exists(path) else "MISSING", what, path))
        sys.exit(1 if missing_dependencies() else 0)
    gone = missing_dependencies()
    if gone:
        raise SystemExit("the bake's files are missing: %s" % gone)
    full, report, _ = bake(a.snapshot, a.tries, a.wait)
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "full.txt"), "w", encoding="utf-8", newline="\n").write(full)
    open(os.path.join(OUT, "entry.txt"), "w", encoding="utf-8", newline="\n").write(entry_line(full) + "\n")
    json.dump(report, open(os.path.join(OUT, "bake_report.json"), "w", encoding="utf-8"), indent=1, sort_keys=True)
    print("load tries:", report["loadTries"], "| module errors in the stand-in world:", len(report["moduleErrors"]),
          "| budget cuts:", report["budgetCuts"])
    print("lengths:", report["lengths"])
    print("login changed:", [c["key"] for c in report["loginChanges"]])
    print("migrations run:", report["migrations"], "changed:", [c["key"] for c in report["migrationChanges"]])
    for k, mv in report["moves"].items():
        print("moved into the store: %s at %s (%s): %s" % (k, mv["stage"], mv["when"], mv["entry"]))
    print("fit at %.2f x %.2f: %s (%s)" % (report["fit"]["W"], report["fit"]["H"], report["fit"]["verdict"], report["fit"]["layoutName"]))
    print("extra personal dropped:", report["extraPersonalDropped"])
    src, m = current_entry()
    old = shipped_text(src)
    print("Full in Media/Profiles.lua: %s" % ("%d characters, sha256 %s" % (len(old), sha(old)) if old else "none"))
    print("Full baked now:             %d characters, sha256 %s" % (len(full), report["sha256"]))
    changes = text_diff(old, full)
    if changes:
        print("what the bake changes in Full's text (- the file's, + the bake's):")
        for line in changes:
            print("  " + line)
    problems = file_problems(src, m, full)
    same = bool(m) and m.group(0) == entry_line(full)
    print("Media/Profiles.lua holds this text:", same and not problems)
    for p in problems:
        print("  - " + p)
    if a.write:
        if not m:
            raise SystemExit('no ["MelloUI"] line in Media/Profiles.lua')
        if not same:
            new = src[:m.start()] + entry_line(full) + src[m.end():]
            open(PROFILES, "w", encoding="utf-8", newline="\n").write(new)
            print("wrote the \"MelloUI\" entry of Media/Profiles.lua")
        if os.path.normcase(os.path.abspath(a.snapshot)) != os.path.normcase(os.path.abspath(SNAP)):
            print("the bake's snapshot is now %s (Tools/installer/full_snapshot.txt, in the build data folder)"
                  % keep_snapshot(a.snapshot))
    elif a.check and problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
