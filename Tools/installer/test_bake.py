"""The shipped Full ("MelloUI" in Media/Profiles.lua) against its bake.

  python Tools/installer/test_bake.py

Checks (the installer build's spec, sections 1.1 and 1.4):
  - the file: Lua 5.1 loads it; besides the head's comments only the
    "MelloUI" entry may differ from HEAD; it holds no other profile;
  - the entry is exactly what bake_full.py makes from the snapshot now
    (reproducible; its sha256 printed); the whisper windows' old corner is
    moved by Chat's own login step, the voice overlay's by the bake, and
    --check names a player's own profile left in the file;
  - it round-trips through the profile loader: a new player's Profiles()
    copies it, LoadProfile applies every entry, SaveProfile gives the same
    text back; after a login (every module's OnInit / OnEnable, their one-time
    steps) it is still the same; loaded over the user's own setup it gives
    the same text and the player's personal keys stay;
  - no personal data (1.4): no kept key, none of the installer's additions,
    no one-time flag by its name, no character or flight data, no value of a
    personal key of the snapshot;
  - the UI scale is not in it;
  - the places: the 12 window places, and fitted at the design size by the
    fitter's own test world they come back unchanged; none of the four Edit
    Mode frames, no QuestTracker.pos, no layoutFitFor; the three places wave
    3 moved are store entries, never the old keys; every whisper window
    (its size, all six cascade places) opens inside the design screen;
  - test_options.py's Full rules: <= 4,000 characters, no FULL_DROP key, every
    key in its module's defaults or the declared nil-default list, every flag
    a registered module that is not driven by UI Modifications;
  - the snapshot record (in a temporary build data folder): a snapshot in
    the build data is recorded as it is, a live saved file is copied in first.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

import bakeworld as B
import bake_full as F

fails = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)
    return cond


WINDOWS12 = ["CharacterFrame", "CollectionsJournal", "CommunitiesFrame", "ContainerFrameCombinedBags", "FriendsFrame",
             "LFGParentFrame", "LegacySystemFrame", "MacroFrame", "MelloUIConfigFrame", "PlayerSpellsFrame",
             "ProfessionsFrame", "WorldMapFrame"]
ANCHOR_RX = re.compile(r"\s+")


def raw_snapshot():
    """The snapshot's modules as saved (a plain Lua 5.1 runtime, no addon code)."""
    import lupa.lua51 as L51
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(F.SNAP, encoding="utf-8").read())
    return B.py(lua, lua.eval("MelloUIDB.modules"))


def moved_places(snap):
    """The store entries the three moved windows must have, by the rule the
    modules document (written again here, independently): Chat's
    whisperPopupPos {x, y} -> whisper {relPoint = BOTTOMLEFT, x, y};
    VoiceOver's overlayPoint / RelativePoint / X / Y -> voiceOverlay {point
    unless BOTTOMLEFT, relPoint unless CENTER, x, y}; a snapshot that has the
    store entries already keeps them."""
    um = snap.get("UIModifications", {})
    store = um.get("positions") or {}
    out = {}
    chat, vo = snap.get("Chat", {}), snap.get("VoiceOver", {})
    old = chat.get("whisperPopupPos")
    if isinstance(old, dict) and isinstance(old.get("x"), (int, float)) and isinstance(old.get("y"), (int, float)):
        out["whisper"] = {"relPoint": "BOTTOMLEFT", "x": old["x"], "y": old["y"]}
    elif "whisper" in store:
        out["whisper"] = store["whisper"]

    def anchor(v):
        v = ANCHOR_RX.sub("", v).upper() if isinstance(v, str) else None
        return v if v in ANCHORS else None
    point = anchor(vo.get("overlayPoint"))
    if point:
        rel = anchor(vo.get("overlayRelativePoint")) or point
        e = {"x": vo.get("overlayX") or 0, "y": vo.get("overlayY") or 0}
        if point != "BOTTOMLEFT":
            e["point"] = point
        if rel != "CENTER":
            e["relPoint"] = rel
        out["voiceOverlay"] = e
    elif "voiceOverlay" in store:
        out["voiceOverlay"] = store["voiceOverlay"]
    if "routeArrow" in store:
        out["routeArrow"] = store["routeArrow"]
    return out
NIL_DEFAULTS = {"QuestTracker.pos", "UIModifications.qol_Auras", "UIModifications.qol_ErrorFilter", "UIModifications.layoutFitFor"}
ANCHORS = {"TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"}


def shipped_text():
    import lupa.lua51 as L51
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(F.PROFILES, encoding="utf-8").read())
    p = lua.globals().MelloUI_Profiles
    return p, {str(k): p.profiles[k] for k in p.profiles.keys()}


def world_new():
    """A new player's world: no saved variables, every module registered."""
    lua, errs, ns, _ = B.make_world_retry(5, 60)
    lua.execute(B.BUDGET)
    lua.execute(F.LUA_STEPS)
    lua.execute('''
        local M = MelloUI
        M.db = { enabled = {}, modules = {}, profiles = {} }
        M.ApplyDefaults(M.db, { enabled = {}, modules = {}, profiles = {} })
        for name in M:IterateModules() do M:GetModuleDB(name) end
    ''')
    return lua


def strip_extra(text):
    return ";".join(e for e in text.split(";") if e and not (
        not e.startswith("!") and F.extra_personal(*e.split("=", 1)[0].split(".", 1))))


def main():
    print("== the file")
    p, profiles = shipped_text()
    text = profiles.get("MelloUI")
    check(isinstance(text, str) and text != "", "Media/Profiles.lua loads; it has a \"MelloUI\" profile")
    check(p.default == "MelloUI", "default stays \"MelloUI\" (unread by Core)")
    head = subprocess.run(["git", "-C", B.ROOT, "show", "HEAD:Media/Profiles.lua"], capture_output=True, text=True,
                          encoding="utf-8").stdout
    now = open(F.PROFILES, encoding="utf-8").read()
    rx = B.profiles_line_re()

    def body(src):   # the file without its head's comments and the "MelloUI" line
        lines = src.split("\n")
        while lines and lines[0].startswith("--"):
            lines.pop(0)
        return rx.sub("", "\n".join(lines))
    check(bool(rx.search(head)) and body(head) == body(now),
          "besides the head's comments only the \"MelloUI\" entry differs from HEAD")
    check(sorted(profiles) == ["MelloUI"], "the profiles are the same as before: %s%s" % (
        sorted(profiles), "" if sorted(profiles) == ["MelloUI"] else
        " -- a player's own profiles, kept by the watcher (Tools/bake_routes.py --watch); see bake_full.py --check"))
    check(not F.missing_dependencies(), "every file the bake reads is there: %s" % F.missing_dependencies())

    print("== reproducible")
    full, report, bw = F.bake(tries=5, wait=60)
    check(text == full, "the entry is exactly the bake of the snapshot through the current code")
    probs = F.file_problems(now, rx.search(now), full)
    check(not probs, "bake_full.py --check finds nothing to fix: %s" % probs)
    # a player's own profile the watcher keeps in the file is named by --check
    # (a release would ship it), and so is a stale entry
    fake = rx.sub(lambda mm: mm.group(0) + '\n\t\t["Raid"] = "!Chat=b0",', now)
    fprobs = F.file_problems(fake, rx.search(fake), full)
    check(any("bake_routes.py" in p and "Raid" in p for p in fprobs),
          "a player's own profile in the file is named by --check, with the watcher that keeps it")
    stale = rx.sub(lambda mm: F.entry_line(full + ";Chat.nameStyle=sfull"), now)
    check(any("not this bake" in p for p in F.file_problems(stale, rx.search(stale), full)), "a stale entry is named by --check")
    sha = hashlib.sha256(text.encode("utf-8")).hexdigest()
    print("  Full: %d characters, sha256 %s" % (len(text), sha))
    check(not report["unexpectedChanges"], "the login and the moves changed only personal / one-time / known keys")
    check(report["migrations"] and sorted(report["migrations"]) == ["MoveOldPlace", "MovePopupPlace"],
          "the modules' own moves ran: %s" % report["migrations"])
    stages = {k: v["stage"] for k, v in report["moves"].items()}
    check(stages == {"whisper": "login", "voiceOverlay": "bake"},
          "the whisper windows' corner moved at the login (Chat's OnEnable), the voice overlay's by the bake: %s" % stages)
    check(all(k in {c["key"] for c in report["loginChanges"]} for k in ("Chat.whisperPopupPos", "UIModifications.positions")),
          "the login changes the bake knows include the whisper move (the old key gone, the store written)")
    # the move check itself, on made-up stores: the documented move passes
    # (at the login or by the bake); anything else riding along stops the bake
    mods = {"Chat": {"whisperPopupPos": {"x": 10, "y": 20}}}
    moved = {"whisper": {"relPoint": "BOTTOMLEFT", "x": 10, "y": 20}}
    check(F.check_moves(mods, {}, moved, moved) == {"whisper": "login"}
          and F.check_moves(mods, {}, {}, moved) == {"whisper": "bake"}, "the move check: the whisper rule, either stage")

    def stops(*a):
        try:
            F.check_moves(*a)
        except SystemExit:
            return True
        return False
    check(stops(mods, {}, moved, dict(moved, CharacterFrame={"x": 1, "y": 2}))
          and stops(mods, {}, moved, {"whisper": {"relPoint": "BOTTOMLEFT", "x": 11, "y": 20}})
          and stops(mods, {"FriendsFrame": {"x": 1, "y": 1}}, dict(moved, FriendsFrame={"x": 2, "y": 1}),
                    dict(moved, FriendsFrame={"x": 1, "y": 1})),
          "the move check stops on another store entry, a wrong move, or a login that changed another place")
    check(report["fit"]["verdict"] == "PASS" and report["fit"]["layoutName"] == "MelloUI"
          and abs(report["fit"]["W"] - 2866.6666666666665) < 1e-9 and report["fit"]["H"] == 1200,
          "the fit ran at the design size (2866.67 x 1200): %s" % report["fit"]["verdict"])

    ents = B.entries(text)
    emap = B.entry_map(text)

    print("== round trip through the profile loader")
    lua = world_new()
    M = lua.globals().MelloUI
    shipped = M.Profiles(M)["MelloUI"]
    check(shipped == text, "a new player's Profiles() copies the shipped text")
    check(M.IsProfileBaked(M, "MelloUI") is True, "the Profiles page shows it as baked")
    check(M.LoadProfile(M, "MelloUI") is True and lua.eval("MelloUI.db.activeProfile") == "MelloUI", "LoadProfile applies it")
    applied = M.DeserializeSettings(M, text)
    check(applied == len(ents), "every entry lands (%d of %d)" % (applied, len(ents)))
    M.SaveProfile(M, "RoundTrip")
    back = lua.eval("MelloUI.db.profiles.RoundTrip")
    check(back == text, "saved again it is the same text, byte for byte")
    lua.globals().PRINTED = lua.table()
    lua.execute('''
        local M = MelloUI
        M.initialized = true
        M.initializingModules = true
        for _, module in M:IterateModules() do M:InitModule(module) end
        M.initializingModules = nil
    ''')
    M.SaveProfile(M, "AfterLogin")
    after = lua.eval("MelloUI.db.profiles.AfterLogin")
    check(strip_extra(after) == text, "after a new player's login (every OnEnable) it is still the same")
    if strip_extra(after) != text:
        for c in F.diff(text, strip_extra(after)):
            print("      ", c)
    ex = lua.eval("MelloUI.db.modules.UIModifications.questTrackerKit")
    check(ex is True, "the Quest Tracker's kit switch after that login is on, as in the user's setup")

    # over the user's own setup: same text; the player's personal keys stay
    lua2, errs, ns, _ = B.make_world_retry(5, 60)
    lua2.execute(open(F.SNAP, encoding="utf-8").read())
    lua2.execute(B.BUDGET)
    lua2.execute(F.LUA_STEPS)
    lua2.globals().Login()
    M2 = lua2.globals().MelloUI
    personal_of = lua2.eval('''function()
        local M, t = MelloUI, {}
        for name in M:IterateModules() do
            for k, v in pairs(M:GetModuleDB(name)) do
                if M:IsPersonalKey(name, k) and type(v) ~= "table" then t[name .. "." .. k] = tostring(v) end
            end
        end
        return t end''')
    personal_before = B.py(lua2, personal_of())
    M2.ApplySettingsText(M2, text)
    M2.SaveProfile(M2, "Over")
    check(strip_extra(lua2.eval("MelloUI.db.profiles.Over")) == text, "loaded over the user's setup it gives the same text")
    personal_after = B.py(lua2, personal_of())
    check(personal_after == personal_before and any(k.startswith("Route.flights_") for k in personal_before),
          "the player's personal keys stay (%d, the flight points among them)" % len(personal_before))

    print("== no personal data (1.4)")
    personal = [k for m, k, v in ents if m != "!" and M.IsPersonalKey(M, m, k)]
    check(not personal, "no key the modules keep: %s" % personal)
    extra = [m + "." + k for m, k, v in ents if m != "!" and F.extra_personal(m, k)]
    check(not extra, "none of the installer's keep additions, no one-time flag by its name: %s" % extra)
    check("flights_" not in text and not re.search(r"Player-?\d+-?[0-9A-F]{6,}", text), "no flight points, no character ID")
    # every string a personal key of the snapshot holds (the borrowed game
    # settings, names), and every personal key's name
    snap = raw_snapshot()
    leaks = []
    for mod, db in snap.items():
        if not isinstance(db, dict):
            continue
        for k, v in db.items():
            if M.IsPersonalKey(M, mod, str(k)) or F.extra_personal(mod, str(k)):
                if (mod + "." + str(k) + "=") in text:
                    leaks.append(mod + "." + str(k))
                if isinstance(v, str) and len(v) >= 4 and v in text:
                    leaks.append("%s.%s value" % (mod, k))
    check(not leaks, "no personal key or personal value of the snapshot in it: %s" % leaks)
    top = ["kitTuning", "kitEditor", "profiles", "profilesShipped", "activeProfile", "defaultProfile", "installer"]
    known = lua.eval("function(n) return MelloUI.modules[n] ~= nil end")
    check(all(known(k if m == "!" else m) for m, k, v in ents) and not any(t + "." in text or t + "=" in text for t in top),
          "only module settings, no top-level db key")

    print("== the UI scale")
    check(not re.search(r"ui_?scale", text, re.I), "no UI-scale key or value anywhere in the text")
    check(not any(re.search(r"scale", k, re.I) for m, k, v in ents if m == "UIModifications"),
          "no scale of UI Modifications' own")

    print("== the places")
    lua.execute("PLACE_DB = { enabled = {}, modules = {}, profiles = {} }")
    pos = B.py(lua, lua.eval('''(function(text)
        local M = MelloUI
        M:ApplySettingsText(text)
        return M:GetModuleDB("UIModifications").positions end)''')(text))
    names = sorted(pos)
    moved = moved_places(snap)
    check(sorted(n for n in names if n not in moved) == sorted(WINDOWS12), "the 12 window places: %s" % names)
    check(all(n not in pos for n in F.EDIT_MODE_FRAMES), "no store place for the four Edit Mode frames")
    for n, want in moved.items():
        got = pos.get(n)
        check(got is not None and {k: got[k] for k in got} == want, "the moved place %s is a store entry %s" % (n, got))
    for k in F.LEGACY_PLACES:
        check(k not in emap, "no old place key %s" % k)
    check("QuestTracker.pos" not in emap and "UIModifications.layoutFitFor" not in emap, "no QuestTracker.pos, no layoutFitFor")
    well = all(isinstance(p.get("x"), (int, float)) and isinstance(p.get("y"), (int, float))
               and p.get("point", "BOTTOMLEFT") in ANCHORS and p.get("relPoint", "CENTER") in ANCHORS for p in pos.values())
    check(well, "every place in the store's form (anchors, numbers)")
    # the whisper windows at the design size: each is the popup's size (read
    # from Modules/Chat.lua), the n-th one 24 right and 24 down of the stored
    # corner, six places round; all six inside 2866.67 x 1200
    chat = open(B.ROOT + "Modules/Chat.lua", encoding="utf-8").read()
    size = re.search(r"POPUP_W, POPUP_H = (\d+), (\d+)", chat)
    wp = pos.get("whisper")
    dw, dh = 3440 * 1200 / 1440, 1200.0
    if check(bool(size) and wp is not None and wp.get("point", "BOTTOMLEFT") == "BOTTOMLEFT"
             and wp.get("relPoint") == "BOTTOMLEFT", "the whisper place is the windows' bottom-left corner from the screen's"):
        pw, ph = int(size.group(1)), int(size.group(2))
        boxes = [(wp["x"] + 24 * i, wp["y"] - 24 * i, wp["x"] + 24 * i + pw, wp["y"] - 24 * i + ph) for i in range(6)]
        check(all(l >= 0 and b >= 0 and r <= dw and t <= dh for l, b, r, t in boxes),
              "every whisper window (%dx%d, six cascade places from %s,%s) opens on the design screen" % (pw, ph, wp["x"], wp["y"]))
    check(not F.moved_on_screen(pos, dw, dh), "the bake's own on-screen check passes for Full's places")
    off = dict(pos, whisper={"relPoint": "BOTTOMLEFT", "x": dw - 100, "y": 364})
    check(any("whisper window" in p for p in F.moved_on_screen(off, dw, dh)),
          "the bake's on-screen check catches a whisper corner that would put windows off the right edge")
    # the fitter's own test world (independent of the bake's): the design
    # size is a fixed point for Full's places
    sys.path.insert(0, F.FIT_COMMON)
    import common as FC
    flua, fit = FC.new_world()
    info = FC.source_info()
    inputs = {"positions": {n: pos[n] for n in pos}, "tracker": {"width": 300, "maxHeight": 440, "scale": 1},
              "questlist": {"width": 380}, "hideBagBar": False, "statsOn": False}
    fitted, places, rep = fit.Fit(fit, FC.to_lua(flua, info), fit.DESIGN_W, fit.DESIGN_H, FC.to_lua(flua, inputs),
                                  FC.to_lua(flua, {"screenW": 3440, "screenH": 1440}))
    rep, places = FC.from_lua(flua, rep), FC.from_lua(flua, places)
    check(rep["verdict"] == "PASS", "the fitter's world: %s at the design size" % rep["verdict"])
    # (the fit hands back every store entry it keeps: the 12 windows it
    # places, and the other entries as they are)
    same = sorted(places["windows"]) == sorted(pos) and all(places["windows"][n] == pos[n] for n in pos)
    check(same, "fitted at the design size, the 12 window places come back unchanged (the moved two as they are)")
    check(places["questTracker"]["maxHeight"] == 440 and places["questTracker"]["width"] == 300
          and places["questList"]["width"] == 380, "the tracker's and the Quest List's sizes are the design's")

    print("== the Full rules of test_options.py")
    check(len(text) <= 4000, "%d characters (at most 4,000)" % len(text))   # (the macro backup holds 6,000 since MAX_CHUNKS 24)
    check(not any(k in emap for k in F.FULL_DROP), "no FULL_DROP key")
    stale = []
    for m, k, v in ents:
        if m == "!":
            continue
        has = lua.eval("(function(m, k) return MelloUI.modules[m].defaults[k] ~= nil end)")(m, k)
        if not has and (m + "." + k) not in NIL_DEFAULTS:
            stale.append(m + "." + k)
    check(not stale, "every key is in its module's defaults or the nil-default list: %s" % stale)
    flags = [k for m, k, v in ents if m == "!"]
    check(all(lua.eval("(function(n) local m = MelloUI.modules[n]; return m ~= nil and not m.hidden end)")(n) for n in flags),
          "every flag a registered module UI Modifications does not drive: %s" % flags)

    print("== the snapshot record")
    check(os.path.normcase(os.path.abspath(F.SNAP)) == os.path.normcase(os.path.abspath(F.recorded_snapshot()))
          and os.path.isfile(F.SNAP), "full_snapshot.txt names the snapshot the shipped Full is baked from: %s" % F.SNAP)
    record, env = F.SNAPSHOT_RECORD, os.environ.get("MELLOUI_BUILD_DATA")
    with tempfile.TemporaryDirectory(prefix="bake_record_") as tmp:
        data = os.path.join(tmp, "BuildData")
        inside = os.path.join(data, "installer", "mine", "MelloUI.SavedVariables.lua")
        os.makedirs(os.path.dirname(inside))
        shutil.copyfile(F.SNAP, inside)
        live = os.path.join(tmp, "WTF", "MelloUI.lua")
        os.makedirs(os.path.dirname(live))
        shutil.copyfile(F.SNAP, live)
        os.environ["MELLOUI_BUILD_DATA"] = data
        F.SNAPSHOT_RECORD = os.path.join(tmp, "full_snapshot.txt")
        try:
            rel = F.keep_snapshot(inside)
            check(rel == "installer/mine/MelloUI.SavedVariables.lua" and F.recorded_snapshot() == inside
                  and open(F.SNAPSHOT_RECORD).read() == rel + "\n", "a snapshot in the build data is recorded as it is")
            rel = F.keep_snapshot(live)
            copied = F.recorded_snapshot()
            check(rel.startswith("installer/full_") and os.path.isfile(copied) and os.path.abspath(copied) != os.path.abspath(live)
                  and open(copied, "rb").read() == open(live, "rb").read(),
                  "a live saved file is copied into the build data first (%s)" % rel)
        finally:
            F.SNAPSHOT_RECORD = record
            if env is None:
                os.environ.pop("MELLOUI_BUILD_DATA", None)
            else:
                os.environ["MELLOUI_BUILD_DATA"] = env
    check(os.path.normcase(F.recorded_snapshot()) == os.path.normcase(F.SNAP), "the repository's record is untouched")

    print()
    print("%d checks failed" % len(fails) if fails else "all checks pass")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
