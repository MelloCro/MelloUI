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
    fitter's own test world they come back unchanged; (1.2.4: MelloUI's
    places win) the four Edit Mode frames' places, Edit Layout's copies and
    QuestTracker.pos the snapshot's own, no layoutFitFor; the three places wave
    3 moved are store entries, never the old keys; every whisper window
    (its size, all six cascade places) opens inside the design screen;
  - one profile for every skin (1.2.4): MelloUI_Oldschool's own settings in
    it as the bake read them with it loaded, checked against its defaults;
    the skin (SKIN_KEYS) never; MelloUI_Oldschool ships no profile of its own;
  - test_options.py's Full rules: <= 40,000 characters, no FULL_DROP key, every
    key in its module's defaults or the declared nil-default list, every flag
    a registered module that is not driven by UI Modifications;
  - the snapshot record (in a temporary build data folder): a snapshot in
    the build data is recorded as it is, a live saved file is copied in first;
  - a share string as the source (1.2.4, --string): one as the game makes it
    decodes to its text (raw Deflate or zlib, spaces a copy gained taken out);
    another tag, one cut short, not Base64, one too long, one that is no
    settings text and one that unpacks to far more than a profile are refused;
    a module the string has nothing for (a feature addon its client lacks) is
    named, and --fill-missing carries the shipped Full's own entries for it;
    the shipped Full's own string bakes back to the same text, every entry
    shipped as it is; a --write (into copies: the file, the record, the build
    data) writes that entry, keeps the string's snapshot with the string and
    its text in the build data and records it, and --check's bake of the
    recorded snapshot gives the entry again.
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
# (0.17.0, the 2026-10-01 snapshot: MelloUI's own elements placed in Edit Layout -- its bar, the race bar, your values
# line, the widget column -- are store places too; the Route arrow is a moved one, moved_places)
OWN_PLACES = ["editLayoutBar", "meterbar", "metervalues", "widgets"]
# (1.0, the user's snapshot of 2026-10-20: the Group Frames, the bag window, the map, Combat Text's lanes, the Gains
# feed, the on-screen notice, the Personal Display's bars and shield, the swing timers)
OWN_PLACES += ["GroupFramesParty", "GroupFramesRaid", "MelloUIBagWindow", "MelloUIMap", "combatlanes", "gains", "notice",
               "personalbars", "personalshield", "swingmelee", "swingshot"]
ANCHOR_RX = re.compile(r"\s+")


def raw_snapshot():
    """The snapshot's modules as saved (a plain Lua 5.1 runtime, no addon code)."""
    import lupa.lua51 as L51
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(F.SNAP, encoding="utf-8").read())
    return B.py(lua, lua.eval("MelloUIDB.modules"))


def moved_places(snap):
    """The store entries the moved windows must have, by the rule the modules
    document (written again here, independently): Chat's whisperPopupPos
    {x, y} -> whisper {relPoint = BOTTOMLEFT, x, y}; a snapshot that has the
    store entries already keeps them. (0.16.0: the Voice Over overlay is a row
    of the widget column: its old place is dropped at the login, never
    moved.)"""
    um = snap.get("UIModifications", {})
    store = um.get("positions") or {}
    out = {}
    chat = snap.get("Chat", {})
    old = chat.get("whisperPopupPos")
    if isinstance(old, dict) and isinstance(old.get("x"), (int, float)) and isinstance(old.get("y"), (int, float)):
        out["whisper"] = {"relPoint": "BOTTOMLEFT", "x": old["x"], "y": old["y"]}
    elif "whisper" in store:
        out["whisper"] = store["whisper"]

    if "routeArrow" in store:
        out["routeArrow"] = store["routeArrow"]
    return out
NIL_DEFAULTS = {"QuestTracker.pos", "UIModifications.qol_Auras", "UIModifications.qol_ErrorFilter", "UIModifications.layoutFitFor"}
# (1.0, the user's Full of 2026-10-20: the folded masters' marks, the bag window's kinds in the player's order and their
# own kinds' count, the chat's Background pick, Group Frames' Hide The Game's Frames -- keys with no default)
NIL_DEFAULTS |= {"Auras.qolFolded", "BarText.qolFolded", "ClassIcons.qolFolded", "CooldownText.qolFolded",
                 "BagWindow.kindOrder", "BagWindow.ownN", "Chat.background", "GroupFrames.hideBlizzard"}
# (1.2.4: Edit Layout's own choices -- the elements hidden and locked, the grid, the dim, the coordinates -- one table
# with no default, Core/EditLayoutPicker.lua)
NIL_DEFAULTS |= {"UIModifications.editLayout"}
ANCHORS = {"TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"}


def shipped_text():
    import lupa.lua51 as L51
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(F.PROFILES, encoding="utf-8").read())
    p = lua.globals().MelloUI_Profiles
    return p, {str(k): p.profiles[k] for k in p.profiles.keys()}


def world_new():
    """A new player's world: no saved variables, every module registered."""
    lua, errs, ns, _ = B.make_world_retry(5, 60, without=B.FULL_WITHOUT)   # (1.0: the Full is the one look's)
    lua.execute(B.BUDGET)
    lua.execute(F.LUA_STEPS)
    lua.execute('''
        local M = MelloUI
        M.db = { enabled = {}, modules = {}, profiles = {} }
        M.ApplyDefaults(M.db, { enabled = {}, modules = {}, profiles = {} })
        for name in M:IterateModules() do M:GetModuleDB(name) end
    ''')
    return lua


def strip_extra(text, absent=()):
    """`text` without the installer's keep additions, nor the entries the bake leaves out (`absent`, its report's
    skinLeftOut: the skin, which the installer's Skin step sets)."""
    absent = set(absent)
    return ";".join(e for e in text.split(";") if e and e.split("=", 1)[0] not in absent and not (
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
    check(report["migrations"] and sorted(report["migrations"]) == ["MovePopupPlace"],
          "the modules' own moves ran: %s" % report["migrations"])
    stages = {k: v["stage"] for k, v in report["moves"].items()}
    # (a snapshot saved since the move -- 2026-10-01's -- holds the whisper windows' place in the store already:
    # nothing left to move)
    old_whisper = isinstance(raw_snapshot().get("Chat", {}).get("whisperPopupPos"), dict)
    if old_whisper:
        check(stages.get("whisper") == "login" and set(stages) <= {"whisper", "voiceOverlay"}
              and stages.get("voiceOverlay", "login") == "login",
              "the whisper windows' corner moved at the login (Chat's OnEnable); the old voice overlay's place, if any, "
              "dropped at the login (0.16.0): %s" % stages)
        check(all(k in {c["key"] for c in report["loginChanges"]} for k in ("Chat.whisperPopupPos", "UIModifications.positions")),
              "the login changes the bake knows include the whisper move (the old key gone, the store written)")
    else:
        check(set(stages) <= {"voiceOverlay"} and stages.get("voiceOverlay", "login") == "login",
              "the snapshot has the whisper windows' place in the store already: no move left (the old voice overlay's "
              "place, if any, dropped at the login): %s" % stages)
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
    # (1.0: a PASS whose notes are the soft ones only -- a piece in the centre third or over another now and then, as
    # the user laid them out on this screen) (1.2.4: MelloUI's places win, the minimap at the user's own place -- the
    # buff bar beside it wraps its row for it, the user's to look at)
    soft = all(t.startswith(("in the centre third when it shows", "now and then", "buffs wrap at"))
               for t in report["fit"]["eye"])
    check(report["fit"]["verdict"] in ("PASS", "PASS, needs the user's eye") and soft and report["fit"]["layoutName"] == "MelloUI"
          and abs(report["fit"]["W"] - 2866.6666666666665) < 1e-9 and report["fit"]["H"] == 1200,
          "the fit ran at the design size (2866.67 x 1200): %s %s" % (report["fit"]["verdict"], report["fit"]["eye"]))

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
    # (one look, stage E, the user 2026-10-15: the Quest Tracker's Painted Skin is removed, its one-time step with it)
    ex = lua.eval("MelloUI.db.modules.UIModifications.questTrackerKit")
    check(ex is None, "the login leaves no questTrackerKit (stage E: the Painted Skin removed)")

    # over the user's own setup: same text; the player's personal keys stay
    lua2, errs, ns, _ = B.make_world_retry(5, 60, without=B.FULL_WITHOUT)
    lua2.execute(open(F.SNAP, encoding="utf-8").read())
    lua2.execute(B.CVAR_STORE)   # (1.0: a module restarted by the load gives its CVars back and holds them again)
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
    if not any(k.startswith("Route.flights_") for k in personal_before):
        # (1.2.4: a snapshot made from a share string holds none of a player's own data -- a string never carries
        # it; the login's one-time steps write the rest -- so a player's own are laid in first: a character's flight
        # points, a borrowed game setting, a one-time step)
        lua2.execute('''
            local M = MelloUI
            if M.modules.Route then M:GetModuleDB("Route")["flights_Player-1234-0ABCDEF0"] = "1,2,3" end
            if M.modules.Chat then M:GetModuleDB("Chat").savedWhisperMode = "inline" end
            M:GetModuleDB("UIModifications").layoutApplied = true
        ''')
        personal_before = B.py(lua2, personal_of())
    M2.ApplySettingsText(M2, text)
    M2.SaveProfile(M2, "Over")
    over = strip_extra(lua2.eval("MelloUI.db.profiles.Over"), report["skinLeftOut"])
    check(over == text, "loaded over the user's setup it gives the same text")
    if over != text:
        for c in F.diff(text, over):
            print("      ", c)
    personal_after = B.py(lua2, personal_of())
    check(personal_after == personal_before and any(k.startswith("Route.flights_") for k in personal_before),
          "the player's personal keys stay (%d, the flight points among them)" % len(personal_before))
    for k in sorted(set(personal_before) | set(personal_after)):
        if personal_before.get(k) != personal_after.get(k):
            print("       %s: %s -> %s" % (k, personal_before.get(k), personal_after.get(k)))

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
                # (as a value the way the profile writes one -- "=s<value>" or ":s<value>" inside a table -- not a
                # word in another key's name: Chat's own Background copy "parchment" vs parchment_chat, 2026-10-01)
                if isinstance(v, str) and len(v) >= 4 and re.search(r"[=:]s" + re.escape(v) + r"(?=[;,}|]|$)", text):
                    leaks.append("%s.%s value" % (mod, k))
    check(not leaks, "no personal key or personal value of the snapshot in it: %s" % leaks)
    # (0.17.0: a module's saved* keys are the player's own game settings it gives back when off -- Combat Text's
    # and the meter's were about to ship: none in it, whichever module adds one next)
    saved = re.findall(r"(?:^|;)(\w+\.saved[A-Z]\w*)=", text)
    check(not saved, "no saved game setting (a module's saved* backup) in it: %s" % saved)
    top = ["kitTuning", "kitEditor", "profiles", "profilesShipped", "activeProfile", "defaultProfile", "installer"]
    # (1.2.4: MelloUI_Oldschool's own modules too, a feature this world leaves out)
    known = lua.eval("function(n) return MelloUI.modules[n] ~= nil or MelloUI.Features[n] ~= nil end")
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
    # (1.2.4: the Edit Mode frames' places and Edit Layout's copies are kept, the check below)
    check(sorted(n for n in names if n not in moved and n not in F.EDIT_MODE_FRAMES and not n.startswith("EditMode."))
          == sorted(WINDOWS12 + OWN_PLACES), "the 12 window places and MelloUI's own elements' (0.17.0): %s" % names)
    # (1.2.4, the user 2026-10-28: "MelloUI Configurator Export is always being Prioritized over the Game Edit Mode
    # Export": the four Edit Mode frames' places and Edit Layout's copies are the snapshot's own, never taken out)
    snap_pos = (snap.get("UIModifications") or {}).get("positions") or {}
    kept = [n for n in snap_pos if n in F.EDIT_MODE_FRAMES or str(n).startswith("EditMode.")]
    check(all(pos.get(n) == snap_pos[n] for n in kept)
          and not [n for n in pos if (n in F.EDIT_MODE_FRAMES or n.startswith("EditMode.")) and n not in snap_pos],
          "the Edit Mode frames' places and Edit Layout's copies are the snapshot's own, as they are: %s" % sorted(kept))
    check(not [n for n in pos if n in F.STALE_PLACES], "no stale place")
    for n, want in moved.items():
        got = pos.get(n)
        check(got is not None and {k: got[k] for k in got} == want, "the moved place %s is a store entry %s" % (n, got))
    for k in F.LEGACY_PLACES:
        check(k not in emap, "no old place key %s" % k)
    check("voiceOverlay" not in pos, "no voiceOverlay place (0.16.0: the widget column has its own)")
    # (1.2.4: the Quest Tracker's own place is the snapshot's, as the design screen keeps it -- none when it has none)
    tpos = (snap.get("QuestTracker") or {}).get("pos")
    check(("QuestTracker.pos" in emap) == isinstance(tpos, dict) and "UIModifications.layoutFitFor" not in emap,
          "QuestTracker.pos the snapshot's own (%s), no layoutFitFor" % tpos)
    well = all(isinstance(p.get("x"), (int, float)) and isinstance(p.get("y"), (int, float))
               and p.get("point", "BOTTOMLEFT") in ANCHORS and p.get("relPoint", "CENTER") in ANCHORS for p in pos.values())
    check(well, "every place in the store's form (anchors, numbers)")
    # the whisper windows at the design size: each is the popup's size (read
    # from MelloUI_Chat/Chat.lua), the n-th one 24 right and 24 down of the stored
    # corner, six places round; all six inside 2866.67 x 1200
    chat = open(B.ROOT + "MelloUI_Chat/Chat.lua", encoding="utf-8").read()
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
    # (1.0: the Full's own inputs as the bake's fit read them -- the one look's minimap column, the tracker's sizes --
    # its store places the shipped ones)
    inputs = dict(report["fit"]["inputs"], positions={n: pos[n] for n in pos})
    # (1.2.4: the tracker's own place as the Full has it; MelloUI's places win, as LayoutFit:Inputs says)
    qtp = lua.eval('(function(text) MelloUI:ApplySettingsText(text) return MelloUI:GetModuleDB("QuestTracker").pos end)')(text)
    qtp = B.py(lua, qtp) if qtp is not None else None
    inputs["tracker"] = dict(inputs["tracker"], pos=qtp)
    check(inputs.get("ownPlaces") is True, "the bake's fit read MelloUI's places as winning (LayoutFit:Inputs' ownPlaces)")
    fitted, places, rep = fit.Fit(fit, FC.to_lua(flua, info), fit.DESIGN_W, fit.DESIGN_H, FC.to_lua(flua, inputs),
                                  FC.to_lua(flua, {"screenW": 3440, "screenH": 1440}))
    rep, places = FC.from_lua(flua, rep), FC.from_lua(flua, places)
    check(rep["verdict"] in ("PASS", "PASS, needs the user's eye"), "the fitter's world: %s at the design size" % rep["verdict"])
    # (the fit hands back every store entry it keeps: the 12 windows it
    # places, and the other entries as they are)
    # (1.2.4: MelloUI's own places of what the layout places come back apart, places.own)
    back = dict(places["windows"], **(places.get("own") or {}))
    same = sorted(back) == sorted(pos) and all(back[n] == pos[n] for n in pos)
    check(same, "fitted at the design size, the 12 window places come back unchanged (the moved two as they are)")
    check(sorted(places.get("own") or {}) == sorted(n for n in pos if n in F.EDIT_MODE_FRAMES or n.startswith("EditMode.")),
          "the Edit Mode frames' places come back as MelloUI's own (places.own): %s" % sorted(places.get("own") or {}))
    # (after 0.18.0 the Quest List is a page of the map's quest log: the fit has no width of its own for it)
    # (1.0: the tracker's sizes the bake's fit gave, the Full's own -- the user's, its width the minimap column's)
    baked = report["fit"]["places"]["questTracker"]
    check(places["questTracker"]["maxHeight"] == baked["maxHeight"] and places["questTracker"]["width"] == baked["width"]
          and "questList" not in places, "the tracker's sizes are the Full's (%s x %s); no Quest List width any more"
          % (baked["width"], baked["maxHeight"]))

    print("== the Full on other screens (1.0)")
    # the shipped layout holds every frame to its third's edge (fitting/anchor_layout.py: a raw Edit Mode export
    # holds frames from the centre or the top left and leaves a smaller screen)
    sys.path.insert(0, os.path.join(B.HERE, "fitting"))
    import anchor_layout as AL
    _, moved = AL.anchored(AL.C.decode(AL.LAYOUT_RX.search(open(AL.FILE, encoding="utf-8").read()).group(3)))
    check(not moved, "Media/EditModeLayout.lua's layout is held to the screen's edges (anchor_layout.py --check): %s" % moved[:3])
    # the Full's layout and settings fitted on the fitter tests' 18 screens: these PASS (the user's layout of
    # 2026-10-20; the old one also failed 1366x768 and 1024x768, the new one's tall bottom stack 1600x900 and 1280x1024)
    import fit as FP   # (the prototype's screen list and UI scale: fitting/fit.py SCREENS, ui_parent)
    want_fail = {"1366x768", "1600x900", "1280x1024", "1024x768", "1024x768@0.80"}
    # (1.2.4, the user's string of 2026-10-28: on 1680x1050 the queue eye under the minimap meets the debuff rows -- the
    # string's own settings, with MelloUI's places winning or not)
    want_fail |= {"1680x1050"}
    got_fail = set()
    for sid, sw, sh, sc, _ in FP.SCREENS:
        uw, uh, _ = FP.ui_parent(sw, sh, sc)
        slua, sfit = FC.new_world()
        _, _, srep = sfit.Fit(sfit, FC.to_lua(slua, info), uw, uh, FC.to_lua(slua, inputs),
                              FC.to_lua(slua, {"screenW": sw, "screenH": sh}))
        if FC.from_lua(slua, srep)["verdict"].startswith("FAIL"):
            got_fail.add(sid)
    check(got_fail == want_fail, "the Full fits every screen but %s (FAIL: %s)" % (sorted(want_fail), sorted(got_fail)))

    print("== the Full rules of test_options.py")
    check(len(text) <= 40000, "%d characters (at most 40,000)" % len(text))   # (1.0, 2026-10-20: the macro backup that held 6,000 is gone; the user's own Full is about 19,000)
    check(not any(k in emap for k in F.FULL_DROP), "no FULL_DROP key")
    # (1.2.4, fr-02: a table setting's kept-but-unread legacy entries -- the party's own gparty@<spec> spell groups)
    legacy = []
    for spec, pattern in F.FULL_DROP_IN.items():
        mod, key = spec.split(".", 1)
        t = lua.eval("(function(text, m, k) MelloUI:ApplySettingsText(text) return MelloUI:GetModuleDB(m)[k] end)")(text, mod, key)
        legacy += ["%s[%s]" % (spec, k) for k in (B.py(lua, t) if t is not None else {}) if re.search(pattern, str(k))]
    check(not legacy, "no FULL_DROP_IN entry (kept-but-unread legacy inside a table setting): %s" % legacy[:4])
    stale = []
    # (1.2.4: MelloUI_Oldschool's own entries -- its modules, the keys it brings -- against a world with it loaded)
    own = F.feature_own()
    wlua, _, _, _ = B.make_world_retry(5, 60, without=())
    for m, k, v in ents:
        if m == "!":
            continue
        has = (wlua if F.is_own(own, m, k) else lua).eval(
            "(function(m, k) return MelloUI.modules[m] ~= nil and MelloUI.modules[m].defaults[k] ~= nil end)")(m, k)
        if not has and (m + "." + k) not in NIL_DEFAULTS:
            stale.append(m + "." + k)
    check(not stale, "every key is in its module's defaults or the nil-default list: %s" % stale)
    flags = [k for m, k, v in ents if m == "!"]
    check(all((wlua if F.is_own(own, "!", n) else lua).eval(
        "(function(n) local m = MelloUI.modules[n]; return m ~= nil and not m.hidden end)")(n) for n in flags),
          "every flag a registered module UI Modifications does not drive: %s" % flags)

    print("== one profile for every skin (1.2.4)")
    carried = [m + "." + k for m, k, v in ents if m != "!" and F.is_own(own, m, k)]
    check(set(carried) == set(report["featureCarried"]) and carried,
          "MelloUI_Oldschool's own settings are in it, read with it loaded: %d (%s ...)" % (len(carried), carried[:3]))
    check(not [k for k in F.SKIN_KEYS if k in emap], "the skin is not in it (the installer's Skin step sets it): %s"
          % [k for k in F.SKIN_KEYS if k in emap])
    import lupa.lua51 as L51
    olua = L51.LuaRuntime()
    olua.execute(open(B.ROOT + "MelloUI_Oldschool/Media/Shipped.lua", encoding="utf-8").read())
    check(olua.globals().MelloUI_OldschoolShipped is None,
          "MelloUI_Oldschool ships no profile of its own (its Media/Shipped.lua sets nothing)")

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

    print("== a profile share string as the source (1.2.4: --string / --clipboard)")
    string_checks(full)

    print()
    print("%d checks failed" % len(fails) if fails else "all checks pass")
    sys.exit(1 if fails else 0)


def share(text, header=False):
    """a share string as the game makes one: Deflate (raw; `header`: with zlib's), then Base64, behind the tag"""
    import base64
    import zlib
    if header:
        packed = zlib.compress(text.encode("utf-8"))
    else:
        c = zlib.compressobj(9, zlib.DEFLATED, -15)
        packed = c.compress(text.encode("utf-8")) + c.flush()
    return F.SHARE_TAG + base64.b64encode(packed).decode("ascii")


def refused(s):
    try:
        F.decode_share(s)
    except SystemExit:
        return True
    return False


def string_checks(full):
    s = share(full)
    check(F.decode_share(s) == full, "a string as the game makes one decodes to its text (raw Deflate, Base64)")
    check(F.decode_share(share(full, header=True)) == full, "one with a zlib header too")
    check(F.decode_share(s[:40] + "\n  " + s[40:] + "\n") == full, "spaces and line breaks a copy gained are taken out")
    for label, bad in (("another tag", "!WA:2!" + s[len(F.SHARE_TAG):]), ("cut short", s[:len(s) // 2]),
                       ("not Base64", F.SHARE_TAG + "%%%%"), ("too long", F.SHARE_TAG + "A" * (F.SHARE_LETTERS + 4)),
                       ("no settings text", share("hello world")), ("unpacks to far more than a profile",
                                                                      share("x" * (F.SHARE_TEXT + 10)))):
        check(refused(bad), "refused: %s" % label)
    lost = ";".join(e for e in full.split(";") if not e.startswith(("Route.", "!Route=")))
    miss = F.missing_modules(lost, full)
    check(list(miss) == ["Route"] and len(miss["Route"]) == len([e for e in full.split(";") if e.startswith("Route.")
                                                                 or e.startswith("!Route=")]),
          "a module the string has nothing for is named with the shipped Full's entries for it: %s" % list(miss))

    print("   (the shipped Full's own string through --string --write, into copies)")
    record, env, out, profiles, argv = F.SNAPSHOT_RECORD, os.environ.get("MELLOUI_BUILD_DATA"), F.OUT, F.PROFILES, sys.argv
    with tempfile.TemporaryDirectory(prefix="bake_string_test_") as tmp:
        data = os.path.join(tmp, "BuildData")
        os.makedirs(data)
        path = os.path.join(tmp, "string.txt")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(s + "\n")
        copy = os.path.join(tmp, "Profiles.lua")
        shutil.copyfile(F.PROFILES, copy)
        os.environ["MELLOUI_BUILD_DATA"] = data
        F.SNAPSHOT_RECORD, F.OUT, F.PROFILES = os.path.join(tmp, "full_snapshot.txt"), os.path.join(tmp, "out"), copy
        sys.argv = ["bake_full.py", "--string", path, "--write", "--tries", "1"]
        try:
            try:
                F.main()
                ran = True
            except SystemExit as e:
                ran = e.code in (None, 0)
                print("   (main stopped: %s)" % e)
            check(ran, "--string --write runs to its end")
            report = __import__("json").load(open(os.path.join(F.OUT, "bake_report.json"), encoding="utf-8"))
            acc = report.get("stringAccount") or {}
            check(report.get("text") == full, "the shipped Full's own string bakes back to the same text")
            check(not acc.get("unexplained") and not acc.get("dropped") and not acc.get("added")
                  and len(acc.get("same", [])) == len([e for e in full.split(";") if e]),
                  "every entry of the string shipped as it is (%d)" % len(acc.get("same", [])))
            src = open(copy, encoding="utf-8").read()
            check(F.shipped_text(src) == full, "the --write wrote that entry")
            rel = open(F.SNAPSHOT_RECORD, encoding="utf-8").read().strip()
            snap = os.path.join(data, *rel.split("/"))
            folder = os.path.dirname(snap)
            check(rel.startswith("installer/full_string_") and os.path.isfile(snap)
                  and open(os.path.join(folder, F.STRING_FILE), encoding="utf-8").read().strip() == s
                  and open(os.path.join(folder, F.TEXT_FILE), encoding="utf-8").read().strip() == full,
                  "the string's snapshot, the string and its text kept in the build data and recorded (%s)" % rel)
            again, _, _ = F.bake(snap, 1, 1, log=lambda *a: None)
            check(again == full, "--check's bake of the recorded snapshot gives the entry again")
        finally:
            F.SNAPSHOT_RECORD, F.OUT, F.PROFILES, sys.argv = record, out, profiles, argv
            if env is None:
                os.environ.pop("MELLOUI_BUILD_DATA", None)
            else:
                os.environ["MELLOUI_BUILD_DATA"] = env
    check(F.shipped_text(open(F.PROFILES, encoding="utf-8").read()) == full and
          os.path.normcase(F.recorded_snapshot()) == os.path.normcase(F.SNAP),
          "the repository's Media/Profiles.lua and record are untouched")


if __name__ == "__main__":
    main()
