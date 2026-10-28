"""Bake "Full experience": the shipped profile "MelloUI" in Media/Profiles.lua
(the installer's Full setup and the Profiles page's "MelloUI").

  python Tools/installer/bake_full.py [--snapshot PATH] [--check] [--write] [--deps] [--tries N] [--wait S]
  python Tools/installer/bake_full.py --string FILE | --clipboard [--fill-missing] [--carry FILE] [--write]

(1.2.4, the user 2026-10-28: "make sure that all 3 Themes follow the same Profiles, no more separate profiles
depending on the Theme") "MelloUI" is the one shipped profile for every skin: the installer applies it for Default,
Modern and Oldschool alike, and the Skin step sets the skin over it (UIModifications.skin and reskin, SKIN_KEYS, are
never in it). So it carries MelloUI_Oldschool's own settings too -- its modules' and the keys its parts bring into
MelloUI's (the painted reskin's borders, kit colours, parchment areas) -- read with it loaded; the rest is read
without it, as before (its painted Minimap skin never dresses the bake's fit).

From a profile share string (1.2.4): Save the setup as a profile in game, Export it (the Profiles page, or
/mello profile export <name>), copy the string into a file (or leave it on the clipboard), then
  python Tools/installer/bake_full.py --string FILE            a look: what would ship, every entry accounted for
  python Tools/installer/bake_full.py --string FILE --write    ship it: the "MelloUI" entry, and the string's
                                                               snapshot recorded for --check and the release
The string is decoded and checked (a damaged or foreign one is refused), read into a fresh saved variable by the
addon's own reader -- that file, with the string and its text beside it, is kept in the build data
(installer/full_string_<date>/) and recorded in full_snapshot.txt -- then baked as below. Every entry of the string
is listed as shipped, shipped changed (the fitter's places, a login step) or left out with its reason (a player's
own key, a one-time mark, an old key, a module the string's client has and this one has not ...); one left out for
no known reason stops the --write. A module the shipped Full has settings for and the string none (a feature addon
the client it came from lacks) is named; --fill-missing carries the shipped Full's own entries for it, and the
shipped Full's MelloUI_Oldschool entries the string has none of (one made without it loaded). --carry FILE (a
profile text or share string) carries that text's MelloUI_Oldschool entries the string has none of, before
--fill-missing: on 2026-10-28 the frozen "MelloUI Oldschool" profile of 1.0, when the one profile took its place. The
string's own entries always win; what was carried, and from where, is listed and kept beside the string.

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
  3. FULL_DROP back to the defaults, FULL_DROP_IN's entries taken out of
     their table settings (kept-but-unread legacy; a player's own saved copy
     keeps them);
  4. the fitter's design-size places laid over (the real Core/LayoutFit.lua:
     LayoutFit:Fit(info, DESIGN_W, DESIGN_H, LayoutFit:Inputs())): (1.2.4,
     the user 2026-10-28: "MelloUI Configurator Export is always being
     Prioritized over the Game Edit Mode Export", LayoutFit's ownPlaces) the
     store places of the four Edit Mode frames and Edit Layout's EditMode.*
     copies KEPT, the window places and QuestTracker.pos as fitted (at the
     design size: the snapshot's own unless one leaves the screen), the
     tracker's and Quest List's sizes as fitted; layoutFitFor NOT baked. The
     moved places the fitter does not place are checked on the screen at the
     design size: every whisper window (the popup's size, all six cascade
     places) and the anchors of the other two;
  5. MelloUI:SaveProfile("MelloUI") (StripPersonal with the current keep
     lists), then the installer's own personal rules for keep entries not in
     the modules yet: seenVersion, ^layoutAsked_, layoutFitFor, layoutFitRev and any
     one-time flag by its name (...Migrated, Folded, Once, Asked, Shown,
     Applied, Version, Done);
  6. MelloUI_Oldschool's own entries added: the snapshot logged in again with
     it loaded, FULL_DROP, SaveProfile, its modules' entries and the keys it
     brings taken (the skin's, SKIN_KEYS, never).

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

# (the two old objectives switches, VoiceOver.questObjectives and questLogObjectives, became Quest Objectives in
# 0.15.0: a snapshot's saved value of either is dropped, never shipped as a key no module reads. Quest Objectives
# and Read Books And Letters Aloud are on for everyone (user, 2026-09-29): a snapshot with either off never ships
# it off -- the Full profile leaves both at their default, on; test_bake.py's "no FULL_DROP key" checks it. Race
# Pitch & Speed and Profile Strength were removed in 0.15.0: a snapshot's value of either is dropped too)
# (0.16.0: the keys the merged settings and the Voice Over widget took out -- carried to the key that lives on at
# the login, MelloUI:MergeSettings and VoiceOver's OnInit -- dropped here too, so none ships)
FULL_DROP = ["VoiceOver.collectLines", "CharacterPanel.slotBorder", "BackpackPanel.itemBorder",
             "VoiceOver.questObjectives", "VoiceOver.questLogObjectives",
             "VoiceOver.recordedObjectives", "VoiceOver.readBooks",
             "VoiceOver.raceProfiles", "VoiceOver.profileStrength",
             "Chat.nameStyle", "Chat.classColors", "Route.textShade", "Tweaks.zoneTextShade", "Tweaks.centreTextShade",
             "NameplatePanel.shadeStrength", "UIModifications.shade_nameplates", "Tooltip.classNames",
             "Tooltip.barTexture", "DarkMode.auraIconBorder", "Route.notice", "Route.noticeSound",
             "Reminders.remind_restock", "VoiceOver.overlayLock", "VoiceOver.overlayScale",
             # (0.17.0, the user's pick C of chat_menu_sketch: Hide Chat Buttons became Chat Buttons, on for the Full
             # experience too -- a snapshot's old "hide them" is dropped, never shipped)
             "Chat.hideButtons",
             # (0.17.0: Unit Frames' Fade Out Of Combat, Faded Opacity and Pet Frame Too: the Fader's now, carried
             # at the login by MelloUI:MergeSettings)
             "UnitFrames.fadeOutOfCombat", "UnitFrames.fadeAlpha", "UnitFrames.fadePet",
             # (0.19.4: the Fonts' Scale Title / Scale Text became Size Title / Size Text, the face's correction its
             # own -- carried at the login by MelloUI:MergeSettings; Scale Damage gone. Full is gothic: Alegreya-
             # Regular's own 1.1 makes Full's Size Text 1, the default)
             "Fonts.scaleTitle", "Fonts.scaleText", "Fonts.scaleDamage",
             # (0.19.4, the options audit: Class Icons' PvP Flag Icon removed; MelloUI:MergeSettings drops it)
             "ClassIcons.pvpFlag",
             # (0.25.0, the race bar's rail: Race Bar Height removed, Race Bar Thickness (Meter.railHeight) in its
             # place, a new key; a saved height is simply not read)
             "Meter.barHeight",
             # (one look, stage E, the user 2026-10-15: the Quest Tracker's Painted Skin removed; the login's
             # MelloUI:MergeSettings drops a saved key, its one-time flag stays personal: EXTRA_PERSONAL)
             "UIModifications.questTrackerKit",
             # (1.2.4: Oldschool's painted Game Menu removed -- one Game Menu for every skin; the configurator audit:
             # Reskin Brightness folded into Dark Mode's one Brightness, Shade: Buffs and Swing Timer Border removed)
             "UIModifications.GameMenuPanel", "DarkMode.kitShade", "UIModifications.shade_buffs",
             "UIModifications.swingTimerBorder",
             # (1.2.4, fr-02: a raid-style party reads Raid's `parts`; the party's own places from one look C9 are
             # kept in a player's saved settings, unread, and never shipped)
             "GroupFrames.partyParts"]
# The same for entries inside a table setting: {setting: the entry keys' pattern}, those entries taken out of the
# bake's copy (a player's own saved copy keeps them). (1.2.4, fr-02: the party's own spell groups and their marks,
# gparty@<spec>, are no longer read by the frames)
FULL_DROP_IN = {"GroupFrames.sets": "^gparty@", "GroupFrames.started": "^gparty@"}
EDIT_MODE_FRAMES = ["MinimapCluster", "DamageMeter", "ChatFrame1", "ObjectiveTrackerFrame"]
# (1.2.4) the skin: the installer's Skin step sets it over the one profile, so the profile never carries it (a
# profile loaded on the Profiles page leaves the skin in use as it is)
SKIN_KEYS = ["UIModifications.skin", "UIModifications.reskin"]
# the installer's additions to the keep lists and the one-time flag name rule
# (the installer build's test_options.py name check)
# (1.0: ^featureAsked_ the one-time offer flags of the scrapped Accounting, read by no code now; BagWindow.seenN the
# bag window's count of items it has seen, one character's)
EXTRA_PERSONAL = {"UIModifications": ["seenVersion", "^layoutAsked_", "layoutFitFor", "layoutFitRev", "questTrackerKitMigrated",
                                      "^featureAsked_"],
                  "BagWindow": ["seenN"]}
ONE_TIME = re.compile(r"(Migrated|Folded|Once|Asked|Shown|Applied|Version|Done)$")
# (1.0) store places of a mover gone from the code: never shipped (the 2026-10-20 snapshot's effectTester, a Frame
# Effects test window that no code places any more)
STALE_PLACES = ["effectTester"]
LEGACY_PLACES = ["VoiceOver.overlayPoint", "VoiceOver.overlayRelativePoint", "VoiceOver.overlayX", "VoiceOver.overlayY",
                 "Chat.whisperPopupPos", "Route.arrowX", "Route.arrowY"]

# The places moved into the store (UI Modifications' positions) by the module
# that owns the window: the store key, the migration function (found by its
# name among the modules' upvalues, in its file), the old keys it removes,
# and when the game runs it. `bake: True` = the bake calls it after the login
# (Chat's is called again too, a no-op after its OnEnable, so a snapshot with
# Chat off still gets the move).
MOVES = {
    "whisper": {"fn": "MovePopupPlace", "file": "@MelloUI_Chat/Chat.lua", "old": ["Chat.whisperPopupPos"],
                "when": "Chat's OnEnable (a login step since the wave 3 integration fix)"},
    "routeArrow": {"fn": None, "file": "@MelloUI_Route/Route.lua", "old": ["Route.arrowX", "Route.arrowY"],
                   "when": "the arrow's first show (needs its frame: a snapshot with the old keys is refused)"},
}
ANCHORS = {"TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"}
ANCHOR_WS = re.compile(r"\s+")
# the whisper windows: one size (MelloUI_Chat/Chat.lua POPUP_W, POPUP_H), the n-th
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
    -- (0.16.0: the merged settings carried first, as Core's own login does)
    if M.MergeSettings then M:MergeSettings() end
    M.initializingModules = true
    for _, module in M:IterateModules() do M:InitModule(module) end
    M.initializingModules = nil
    TEXT_LOGIN = M:SerializeSettings()
    STORE_LOGIN = Store()
end

-- wanted: { [function name] = "@<folder>/<Module>.lua" } (Modules/, or a feature addon's folder since 0.19.9:
-- the module named by the file's own name)
function MovePlaces(wanted)
    local roots = { M }
    for _, file in pairs(wanted) do
        roots[#roots + 1] = M.modules[file:match("/(%w+)%.lua$")]
    end
    local found = FindUpvalues(roots, wanted)
    local out = {}
    for name, file in pairs(wanted) do
        local fn = found[name]
        if not fn then error("migration " .. name .. " (" .. file .. ") not found: renamed or gone?") end
        local modName = file:match("/(%w+)%.lua$")
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
        -- (a module of a feature addon the world leaves out, bakeworld's FULL_WITHOUT: Oldschool's panels, not baked)
        if M.modules[name] then
            M:GetModuleDB(name)[key] = M.modules[name].defaults[key]
        end
    end
end

-- FULL_DROP_IN: a table setting's entries whose key matches, taken out of a copy laid in its place
function DropIn(list)
    for spec, pattern in pairs(list) do
        local name, key = spec:match("^([^.]+)%.(.+)$")
        local t = M.modules[name] and M:GetModuleDB(name)[key]
        if type(t) == "table" then
            local kept = {}
            for k, v in pairs(t) do
                if not (type(k) == "string" and k:find(pattern)) then kept[k] = v end
            end
            M:GetModuleDB(name)[key] = kept
        end
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
        -- what failed, named (the checks' lists and the unsolved flags)
        local why = {}
        local rep = report and report.checks or {}
        for _, list in ipairs({ "off", "hard", "centre", "stores", "windows" }) do
            for _, t in ipairs(rep[list] or {}) do why[#why + 1] = list .. ": " .. tostring(t) end
        end
        for _, t in ipairs(report and report.flags or {}) do why[#why + 1] = "flag: " .. tostring(t) end
        for _, p in ipairs(report and report.pieces or {}) do
            why[#why + 1] = string.format("piece: %s [%s] L%.1f T%.1f R%.1f B%.1f", tostring(p.name), tostring(p.cat),
                p.l or -1, p.t or -1, p.r or -1, p.b or -1)
        end
        why[#why + 1] = string.format("screen: %.1f x %.1f", W, H)
        for _, t in ipairs(report and report.log or {}) do why[#why + 1] = "log: " .. tostring(t) end
        for _, t in ipairs(report and report.levelsTried or {}) do why[#why + 1] = "tried: " .. tostring(t) end
        error("the design-size fit did not pass: " .. tostring(report and report.verdict) .. "\n  " .. table.concat(why, "\n  "))
    end
    local um = M:GetModuleDB("UIModifications")
    if type(um.positions) ~= "table" then um.positions = {} end
    for _, k in ipairs(places.remove or {}) do um.positions[k] = nil end
    for k, p in pairs(places.windows or {}) do um.positions[k] = Copy(p) end
    for k, p in pairs(places.own or {}) do um.positions[k] = Copy(p) end   -- (1.2.4: MelloUI's places win)
    local qt = M:GetModuleDB("QuestTracker")
    -- (1.2.4, ownPlaces: its own place kept, as the fit kept it on the screen)
    if places.questTracker.clearPos then qt.pos = nil
    elseif places.questTracker.pos then qt.pos = Copy(places.questTracker.pos) end
    qt.maxHeight, qt.width = places.questTracker.maxHeight, places.questTracker.width
    -- places.layoutFitFor: one machine's fact, never baked
    STORE_FITTED = Store()
    return { W = W, H = H, verdict = report.verdict, layoutName = report.layoutName, places = places, inputs = inputs,
        eye = report.eye }
end

function DropPlaces(list)
    local um = M:GetModuleDB("UIModifications")
    if type(um.positions) ~= "table" then return end
    for _, k in ipairs(list) do um.positions[k] = nil end
end

function Save()
    local ok, why = M:SaveProfile("MelloUI")
    if not ok then error("SaveProfile: " .. tostring(why)) end
    return M.db.profiles.MelloUI
end

-- (1.2.4) a text as a new player's game writes it back (SerializeSettings' order: the loaded modules', then the
-- features not loaded): read into a new player's saved variables, written out; the live ones put back after
function Canonical(text)
    local live = M.db
    M.db = { enabled = {}, modules = {}, profiles = {} }
    M.ApplyDefaults(M.db, { enabled = {}, modules = {}, profiles = {} })
    for name in M:IterateModules() do M:GetModuleDB(name) end
    local ok, out = pcall(function()
        M:DeserializeSettings(text)
        return M:SerializeSettings()
    end)
    M.db = live
    if not ok then error("Canonical: " .. tostring(out)) end
    return out
end
'''


def own_of(theirs, ours):
    """The feature addons a world leaves out, from two worlds' default keys (B.default_keys: `theirs` with them,
    `ours` without): (their modules, {a loaded module: the keys their parts bring into it})."""
    return set(theirs) - set(ours), {m: theirs[m] - ours[m] for m in ours if theirs.get(m, set()) - ours[m]}


def split_key(key):
    """'Module.key' -> (module, key); '!Module' -> ('!', module), as B.entries gives them."""
    if key.startswith("!"):
        return "!", key[1:]
    m, _, k = key.partition(".")
    return m, k


def is_own(own, m, k):
    """Whether an entry (B.entries' module, key; '!' for a flag) is one of those addons' own."""
    mods, brought = own
    if m == "!":
        return k in mods
    return m in mods or k in brought.get(m, ())


_OWN = []


def feature_own(tries=5, wait=60, log=print):
    """own_of for the bake's world (B.FULL_WITHOUT left out), from two fresh worlds; made once a run."""
    if not _OWN:
        theirs, _, _, _ = B.make_world_retry(tries, wait, log, without=())
        ours, _, _, _ = B.make_world_retry(tries, wait, log, without=B.FULL_WITHOUT)
        _OWN.append(own_of(B.default_keys(theirs), B.default_keys(ours)))
    return _OWN[0]


def extra_personal(module, key):
    for e in EXTRA_PERSONAL.get(module, []):
        if e == key or (e.startswith("^") and re.search(e, key)):
            return True
    # (1.0) a module's qolFolded is no one-time flag but the mark the settings fold reads (MERGES): a profile without
    # it is taken for one from before the fold, and loading a Full bake without it switched Buffs & Debuffs off (the
    # bake of 2026-10-16, reverted). It ships, as the player's own export keeps it.
    if key == "qolFolded":
        return False
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
LOGIN_STEPS = {"UIModifications.questTrackerKit",   # dropped at the login: Core's MERGES (one look, stage E)
               # 0.16.0: the merged settings (Core/Core.lua MelloUI:MergeSettings, before the modules come up) and the
               # Voice Over widget's (VoiceOver's OnInit: its padlock is Reminders' widgetLock; its old place, the
               # store's voiceOverlay, and its scale are gone)
               "Chat.nameStyle", "UIModifications.nameFormat", "Route.textShade", "Tweaks.zoneTextShade",
               "Tweaks.centreTextShade", "Tweaks.textShade", "NameplatePanel.shadeStrength",
               "UIModifications.shade_nameplates", "NameplatePanel.nameShade", "Chat.classColors", "Tooltip.classNames",
               "UIModifications.classNames", "Tooltip.barTexture", "BarTextures.tooltip", "DarkMode.auraIconBorder",
               "Route.notice", "Route.noticeSound", "Reminders.remind_restock", "VoiceOver.overlayLock",
               "VoiceOver.overlayScale", "VoiceOver.overlayPoint", "VoiceOver.overlayRelativePoint", "VoiceOver.overlayX",
               "VoiceOver.overlayY", "Reminders.widgetLock",
               # (Show Names As's form, handed on to the frames' own copies by UI Modifications' OnEnable)
               "UnitFrames.nameFormat", "Nameplates.nameFormat",
               # 0.18.5: the backdrops' switches taken over from the looks (ActionBarPanel's MigrateBackdrops: a player
               # from before keeps Action Bar 1's, the micro menu's and the bag bar's)
               "ActionBarPanel.backdropBar1", "ActionBarPanel.backdropMicro", "ActionBarPanel.backdropBags"}
# (one look, stage D4: Hide Page Arrows and the backdrop switches moved from ActionBarPanel to ActionBars, the core's
# action bars; the login's merge (Core/Core.lua MERGES) carries them, so both spellings may change, and the 0.18.5 step
# now runs in ActionBars' OnEnable)
LOGIN_STEPS |= {m + "." + k for m in ("ActionBarPanel", "ActionBars") for k in ["hidePageArrows"] + [
    "backdrop" + e for e in ("Bar1", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8", "Stance", "Pet", "Possess",
                             "Totem", "Micro", "Bags", "XP", "XP2")]}
# (one look, stage D3: Quality Gems and Grey Out Junk moved from BackpackPanel to Tweaks; the login's merge removes the
# old keys and carries a saved off, so both spellings may change)
LOGIN_STEPS |= {m + "." + k for m in ("BackpackPanel", "Tweaks") for k in ("qualityGems", "greyJunk")}
# store entries the login takes out (0.16.0: VoiceOver's OnInit forgets the old overlay's place)
LOGIN_DROPS = {"voiceOverlay"}


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
        without two numbers the old key only goes.
    (0.16.0: the Voice Over overlay's old place moves no more: the widget
    column has its own, and the login forgets the old one, LOGIN_DROPS.)"""
    out = {}
    old = (mods.get("Chat") or {}).get("whisperPopupPos")
    if isinstance(old, dict):
        x, y = _num(old.get("x")), _num(old.get("y"))
        if x is not None and y is not None:
            out["whisper"] = {"relPoint": "BOTTOMLEFT", "x": x, "y": y}
    return out


def check_moves(mods, saved, login, moved):
    """Which move ran when: {store key: "login" | "bake"}. SystemExit when
    the store after the moves is not the saved store plus exactly the
    documented entries, or the login left the store in any other state."""
    want = dict(saved)
    want.update(expected_moves(mods))
    for k in LOGIN_DROPS:
        want.pop(k, None)
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
    for k in LOGIN_DROPS:
        if k in saved:
            stages[k] = "login"
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
    src = open(B.ROOT + "MelloUI_Chat/Chat.lua", encoding="utf-8").read()
    m = re.search(r"^local POPUP_W, POPUP_H = (\d+), (\d+)", src, re.M)
    if not m:
        raise SystemExit("MelloUI_Chat/Chat.lua has no 'local POPUP_W, POPUP_H = <w>, <h>' line any more: teach bake_full.py "
                         "the whisper window's size")
    return int(m.group(1)), int(m.group(2))


def moved_on_screen(store, W, H):
    """[problem] for the moved places the fitter does not place, at W x H:
    every whisper window (its size, all six cascade places) inside the
    screen; the Route arrow's anchor on it."""
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
    for key in ("routeArrow",):
        p = store.get(key)
        if p:
            l, b, _, _ = _rect(p, 0, 0, W, H)
            if l < 0 or b < 0 or l > W or b > H:
                out.append("%s's anchor %.1f,%.1f is off the %.2f x %.2f screen" % (key, l, b, W, H))
    return out


def saved_text(snapshot, tries, wait, log):
    """The snapshot as saved: every module registered and OnInit run (its
    defaults complete), no OnEnable / OnDisable (no one-time step yet)."""
    lua, _, _, _ = B.make_world_retry(tries, wait, log, without=B.FULL_WITHOUT)
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


def logged_in(snapshot, tries, wait, log, without=None):
    """A world (bakeworld's, `without` those feature addons) with the snapshot logged in: every module's defaults as
    its OnInit / OnEnable leave them (UI Modifications' area and shade switches come at the login)."""
    lua, _, _, _ = B.make_world_retry(tries, wait, log, without=without)
    lua.execute(open(snapshot, encoding="utf-8").read())
    lua.execute(B.BUDGET)
    lua.execute(LUA_STEPS)
    lua.globals().Login()
    return lua


def bake(snapshot=SNAP, tries=5, wait=60, log=print):
    text_saved = saved_text(snapshot, tries, wait, log)
    mods = raw_modules(snapshot)
    lua, errs, ns, tried = B.make_world_retry(tries, wait, log, without=B.FULL_WITHOUT)
    lua.execute(open(snapshot, encoding="utf-8").read())
    lua.execute(B.BUDGET)
    lua.execute(LUA_STEPS)
    g = lua.globals()
    g.Login()
    wanted = {spec["fn"]: spec["file"] for spec in MOVES.values() if spec["fn"]}
    migrated = sorted(B.py(lua, g.MovePlaces(B.to_lua(lua, wanted))).values())
    stages = check_moves(mods, B.py(lua, g.STORE_SAVED), B.py(lua, g.STORE_LOGIN), B.py(lua, g.STORE_MOVED))
    g.DropFull(B.to_lua(lua, FULL_DROP))
    g.DropIn(B.to_lua(lua, FULL_DROP_IN))
    if lua.eval('rawget(MelloUI, "LayoutFit")') is None:
        loadf = lua.eval(B.LOADF)
        e = loadf(open(B.ROOT + "Core/LayoutFit.lua", encoding="utf-8").read(), "@Core/LayoutFit.lua", ns)
        if e:
            raise SystemExit("Core/LayoutFit.lua did not load: " + e)
    fit = g.DesignPlaces(design_info(lua), 3440, 1440)
    g.DropPlaces(B.to_lua(lua, STALE_PLACES))
    fit_py = B.py(lua, fit)
    fitted_store = B.py(lua, g.STORE_FITTED)
    off = moved_on_screen(fitted_store, fit_py["W"], fit_py["H"])
    if off:
        raise SystemExit("a moved place is off the screen at the design size (move that window in game, then take a "
                         "new snapshot): %s" % off)
    saved = g.Save()
    kept, dropped, skin, carried = [], [], [], []
    # (1.2.4: the one profile for every skin) the settings of the feature addons the world leaves out (bakeworld's
    # FULL_WITHOUT: Oldschool's modules, and the keys its parts bring into a loaded one -- the painted reskin's
    # switches and border kinds in UI Modifications) are read from the snapshot logged in WITH them, against their
    # own defaults; this world's copy of them (kept as it came, or no default to compare with) is passed by
    with_lua = logged_in(snapshot, tries, wait, log, without=())
    own = own_of(B.default_keys(with_lua), B.default_keys(lua))

    def key_of(m, k):
        return "!" + k if m == "!" else m + "." + k

    for m, k, v in B.entries(saved):
        if is_own(own, m, k):
            continue
        if key_of(m, k) in SKIN_KEYS:
            skin.append(key_of(m, k))
            continue
        (dropped if (m != "!" and extra_personal(m, k)) else kept).append((m, k, v))
    gw = with_lua.globals()
    gw.DropFull(B.to_lua(with_lua, FULL_DROP))
    for m, k, v in B.entries(gw.Save()):
        if not is_own(own, m, k):
            continue
        if key_of(m, k) in SKIN_KEYS:
            skin.append(key_of(m, k))
            continue
        (dropped if (m != "!" and extra_personal(m, k)) else carried).append((m, k, v))
    joined = ";".join(key_of(m, k) + "=" + v for m, k, v in kept + carried)
    # (Oldschool's entries in their places: the text as a new player's game writes it back, so a save of the loaded
    # profile gives it byte for byte; never an entry more or less)
    full = g.Canonical(joined) if carried else joined
    if B.entry_map(full) != B.entry_map(joined):
        raise SystemExit("writing the profile back changed it: %s" % diff(joined, full))
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
        "moves": {k: {"stage": v, "entry": fitted_store.get(k),
                      "when": MOVES[k]["when"] if k in MOVES else "the login (dropped)"}
                  for k, v in sorted(stages.items())},
        "migrationChanges": diff(g.TEXT_LOGIN, g.TEXT_MIGRATED),
        "fullDrop": FULL_DROP,
        "fullDropIn": FULL_DROP_IN,
        "fit": {"W": fit_py["W"], "H": fit_py["H"], "verdict": fit_py["verdict"], "layoutName": fit_py["layoutName"],
                "places": fit_py["places"], "eye": [str(v) for v in (fit_py.get("eye") or {}).values()],
                "inputs": fit_py["inputs"]},
        "extraPersonalDropped": [m + "." + k + "=" + v for m, k, v in dropped],
        "skinLeftOut": sorted(set(skin)),
        "featureCarried": [key_of(m, k) for m, k, v in carried],
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


# ---------------------------------------------------------------------------------------------------------------
# A profile share string as the source (1.2.4; the user, 2026-10-28: "i will then make a new MelloUI Profile export
# string and that is going to be shipped as Default when people decide to use MelloUI Layout in the Installer").
# The string (the Profiles page's Export, or /mello profile export <name>) is decoded here as the game decodes it
# (Base64, then Deflate), checked as Core's MelloUI:DecodeProfileString checks it, and read into a fresh saved
# variable by the addon's own reader (MelloUI:DeserializeSettings): that file is the bake's snapshot from then on, in
# the build data like any other (full_snapshot.txt records it, so --check and the release bake it again), with the
# string and its text beside it. Every entry of the string is then accounted for against the baked text: shipped as
# it is, shipped changed (the fitter's places, a login step) or left out, each with its reason. One left out for no
# known reason stops a --write.

SHARE_TAG = "!MelloUI1!"
SHARE_LETTERS, SHARE_TEXT = 131072, 1048576   # (Core/Core.lua's limits for an import)
STRING_FILE, TEXT_FILE = "profile_string.txt", "profile_text.txt"
CARRIED_FILE = "carried.txt"   # (the entries carried into the snapshot beside the string's own, each with its reason)


def read_share(path=None, clipboard=False):
    """The share string from a file or the clipboard."""
    if path:
        with open(path, encoding="utf-8-sig") as fh:
            return fh.read()
    try:
        import tkinter
        root = tkinter.Tk()
        root.withdraw()
        try:
            return root.clipboard_get()
        finally:
            root.destroy()
    except Exception:  # noqa: BLE001  (no Tk: Windows' own clipboard)
        import subprocess
        out = subprocess.run(["powershell", "-NoProfile", "-Command", "Get-Clipboard -Raw"], capture_output=True,
                             text=True, encoding="utf-8")
        if out.returncode != 0:
            raise SystemExit("the clipboard could not be read: %s" % out.stderr.strip()[:200])
        return out.stdout


def decode_share(s):
    """The settings text inside a share string; SystemExit with the reason when it is not one."""
    import base64
    import zlib
    if not isinstance(s, str) or len(s) > 4 * SHARE_LETTERS:
        raise SystemExit("not a MelloUI profile string (nothing, or far longer than any profile)")
    s = re.sub(r"\s+", "", s)
    if not s.startswith(SHARE_TAG):
        raise SystemExit("not a MelloUI profile string (it starts with %s): copy the whole string from the Profiles "
                         "page's Export" % SHARE_TAG)
    letters = s[len(SHARE_TAG):]
    if len(letters) > SHARE_LETTERS:
        raise SystemExit("the string is far longer than any MelloUI profile")
    packed = None
    for decode in (base64.b64decode, base64.urlsafe_b64decode):
        try:
            packed = decode(letters + "=" * (-len(letters) % 4))
            break
        except ValueError:
            continue
    if not packed:
        raise SystemExit("the string is damaged (cut short while copying?): its letters are not Base64")
    text = None
    for wbits in (-15, 47):   # (the game's Deflate is raw; a zlib or gzip header is read too)
        try:
            d = zlib.decompressobj(wbits)
            out = d.decompress(packed, SHARE_TEXT + 1)
            if len(out) > SHARE_TEXT:
                raise SystemExit("the string unpacks to far more than any MelloUI profile")
            if d.eof:
                text = out.decode("utf-8", errors="surrogateescape")
                break
        except zlib.error:
            continue
    if text is None:
        raise SystemExit("the string is damaged (cut short while copying?): it does not unpack")
    for e in text.split(";"):
        if e and not re.match(r"^[^=]+=.", e):
            raise SystemExit("the string holds something that is not a MelloUI setting: %r" % e[:80])
    return text


# the decoded text read into a fresh saved variable by the addon's own reader, each entry checked, the result as a
# saved-variables file (Lua source: the bake's snapshot)
STRING_STEPS = r'''
local M = MelloUI
local function Num(v)
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    local s = tostring(v)
    if tonumber(s) ~= v then s = string.format("%.17g", v) end
    return s
end
local function Dump(v, indent)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then return Num(v) end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return nil end
    local keys = {}
    for k in pairs(v) do
        if type(k) == "string" or (type(k) == "number" and Num(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    local parts = {}
    for _, k in ipairs(keys) do
        local inner = Dump(v[k], indent .. "\t")
        if inner then parts[#parts + 1] = indent .. "\t[" .. Dump(k, "") .. "] = " .. inner .. "," end
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
end
-- each entry: its owner known (a module, or a feature addon the world leaves out), readable (the reader takes it)
function CheckEntries(text)
    local out = {}
    for entry in text:gmatch("[^;]+") do
        local key = entry:match("^([^=]+)=") or entry
        local owner = key:match("^!?([^.]+)")
        local known = owner and (M.modules[owner] ~= nil or (M.Features and M.Features[owner]) ~= nil) or false
        local applied = known and M:DeserializeSettings(entry, { modules = {}, enabled = {} }) or 0
        out[#out + 1] = { key = key, known = known, readable = applied > 0 }
    end
    return out
end
-- (the save's own merge marks, MelloUIDB.merged, as a new player's first login lays them with nothing to carry: a
-- profile never holds them, and without them the bake's login takes the string's settings for an old save's and
-- carries them again -- Chat's Background "dark" came back as no pick. Only the marks: what those merges write
-- into the modules on an empty save -- Buffs & Debuffs' rows off -- the installer's target replaces in the game)
function StringSnapshot(text)
    local saved = M.db
    local scratch = { enabled = {}, modules = {}, profiles = {} }
    M.db = scratch
    if M.MergeSettings then M:MergeSettings() end
    local db = { enabled = {}, modules = {}, profiles = {}, merged = scratch.merged }
    M.db = db
    local applied = M:DeserializeSettings(text)
    M.db = saved
    return "MelloUIDB = " .. Dump(db, "") .. "\n", applied
end
'''


def string_snapshot(text, tries=5, wait=60, log=print):
    """(saved-variables source, [entry checks]) of a settings text, by the addon's own reader."""
    lua, _, _, _ = B.make_world_retry(tries, wait, log, without=B.FULL_WITHOUT)
    lua.execute(STRING_STEPS)
    g = lua.globals()
    checks = [B.py(lua, c) for c in B.py(lua, g.CheckEntries(text)).values()]
    src, applied = g.StringSnapshot(text)
    return src, checks, applied


def missing_modules(text, shipped):
    """The modules the shipped Full carries entries for and the string carries none for (its flag included): a
    feature addon not in the client the string came from (the retail copy has no Route, Quest List, Map, Dungeon
    Info or Voice Over) -- {module: [entries]}."""
    have = {k if m == "!" else m for m, k, _ in B.entries(text)}
    out = {}
    for m, k, v in B.entries(shipped or ""):
        name = k if m == "!" else m
        if name not in have:
            out.setdefault(name, []).append(("!" + k if m == "!" else m + "." + k) + "=" + v)
    return out


# where a string entry's value changed or went in the bake, by its key (the fitter's places, the documented login
# steps and moves); anything else changed is named as such
FITTED = {"UIModifications.positions", "QuestTracker.pos", "QuestTracker.maxHeight", "QuestTracker.width",
          "Auras.playerPerRow", "Auras.playerSize"}


def account(text, full, report, lua, checks, carried=None):
    """Every entry of the string, sorted: {"same": [...], "changed": [(key, why)], "dropped": [(key, why)],
    "unexplained": [key], "added": [(key, why)]} (carried: {key: why} of the entries carried into its snapshot)."""
    M = lua.globals().MelloUI
    src, out = B.entry_map(text), B.entry_map(full)
    check = {c["key"]: c for c in checks}
    registered = lua.eval("(function(n) return MelloUI.modules[n] ~= nil end)")
    login = {c["key"] for c in report.get("loginChanges", []) + report.get("migrationChanges", [])}
    skin = set(report.get("skinLeftOut", []))
    feature = set(report.get("featureCarried", []))
    carried = carried or {}
    own_login = "%s's own, as its login leaves it (read with it loaded)" % ", ".join(B.FULL_WITHOUT)
    res = {"same": [], "changed": [], "dropped": [], "unexplained": [],
           "added": [(key, carried.get(key) or (own_login if key in feature else "a login step of the current code"
                                                if key in login else "added by the bake"))
                     for key in sorted(set(out) - set(src))],
           # (an entry carried into the snapshot that did not ship: a login step took it -- Oldschool's own, read with
           # it loaded, or one of the current code's)
           "carriedGone": [(key, "a login step of the current code" if key in login else own_login
                            if is_own(feature_own(), *split_key(key)) else "taken out by the bake")
                           for key in sorted(set(carried) - set(out))]}
    for key, value in sorted(src.items()):
        if key in out:
            if out[key] == value:
                res["same"].append(key)
            elif key in FITTED:
                res["changed"].append((key, "fitted to the design size (the installer fits it again to each screen)"))
            elif key in FULL_DROP_IN:
                res["changed"].append((key, "its entries matching %s left out: kept-but-unread legacy the current code "
                                            "no longer reads (FULL_DROP_IN)" % FULL_DROP_IN[key]))
            elif key in login or key in LOGIN_STEPS:
                res["changed"].append((key, "a login step of the current code"))
            else:
                res["changed"].append((key, "changed by the bake"))
            continue
        name, _, sub = key.lstrip("!").partition(".")
        c = check.get(key, {})
        if not c.get("known", True):
            why = "not a MelloUI module (an addon or a version this one does not have)"
        elif not c.get("readable", True):
            why = "a value the reader cannot take (damaged?)"
        elif not key.startswith("!") and M.IsPersonalKey(M, name, sub):
            why = "a player's own key (the module's keep list): never shipped"
        elif not key.startswith("!") and extra_personal(name, sub):
            why = "a one-time mark (the bake's own rule): never shipped"
        elif key in FULL_DROP:
            why = "kept-but-unread legacy: an old key the current code no longer reads (FULL_DROP)"
        elif key in skin or key in SKIN_KEYS:
            why = "the skin: the installer's Skin step sets it over the one profile (SKIN_KEYS)"
        elif (not registered(name) or is_own(feature_own(), *split_key(key))) and key not in feature:
            why = "%s's, equal to its default with it loaded (read with it loaded)" % ", ".join(B.FULL_WITHOUT)
        elif key in login or key in LOGIN_STEPS or key in [k for spec in MOVES.values() for k in spec["old"]]:
            why = "taken out by a login step of the current code (a merge or a move)"
        else:
            res["unexplained"].append(key)
            continue
        res["dropped"].append((key, why))
    return res


def carry_entries(text, source, own, why):
    """The entries of `source` that are a left-out feature addon's own (is_own), not the skin's and not set by `text`:
    [(entry, why)]."""
    have = set(B.entry_map(text))
    out = []
    for m, k, v in B.entries(source or ""):
        key = "!" + k if m == "!" else m + "." + k
        if key not in have and key not in SKIN_KEYS and is_own(own, m, k):
            have.add(key)
            out.append((key + "=" + v, why))
    return out


def ship_string(args):
    """--string / --clipboard: the string becomes the bake's snapshot, then the bake runs as for any snapshot.
    -> (snapshot, the string's own text, {key: why carried}, entry checks)"""
    raw = read_share(args.string, args.clipboard)
    own_text = decode_share(raw)
    text = own_text
    print("the string: %d letters, its text %d characters, %d entries" % (len(re.sub(r"\s+", "", raw)), len(text),
                                                                         len([e for e in text.split(";") if e])))
    src, _ = current_entry()
    shipped = shipped_text(src)
    carried = []
    own = feature_own(args.tries, args.wait) if (args.carry or args.fill_missing) else None
    if args.carry:
        given = read_share(args.carry).strip()
        given = decode_share(given) if given.startswith(SHARE_TAG) else given
        carried += carry_entries(text, given, own, "carried from %s (--carry): %s's own, the string has none"
                                 % (os.path.basename(args.carry), ", ".join(B.FULL_WITHOUT)))
    missing = missing_modules(text, shipped)
    if missing:
        print("modules the shipped Full has settings for and the string has none for (not in the client it came "
              "from?):")
        for name, es in sorted(missing.items()):
            print("  %-22s %3d entries%s" % (name, len(es), "  -> carried over from the shipped Full (--fill-missing)"
                                             if args.fill_missing else ""))
        if not args.fill_missing:
            print("  (they ship at their defaults; --fill-missing carries the shipped Full's own entries for them)")
    if args.fill_missing:
        have = set(B.entry_map(text)) | {e.partition("=")[0] for e, _ in carried}
        for name, es in sorted(missing.items()):
            carried += [(e, "carried from the shipped Full (--fill-missing): the string has no entry for %s" % name)
                        for e in es if e.partition("=")[0] not in have]
        carried += carry_entries(";".join([text] + [e for e, _ in carried]), shipped, own,
                                 "carried from the shipped Full (--fill-missing): %s's own, the string has none"
                                 % ", ".join(B.FULL_WITHOUT))
    if carried:
        print("carried into the string's snapshot (the string's own entries always win):")
        for e, why in carried:
            print("  %-48s %s" % (e.partition("=")[0], why))
        text = ";".join([e for e in text.split(";") if e] + [e for e, _ in carried])
    sv, checks, applied = string_snapshot(text, args.tries, args.wait)
    print("read by the addon's own reader: %d of %d entries applied" % (applied, len(checks)))
    # (a --write keeps it in the build data, where --check and the release bake it again; a look only, in a
    # folder of its own that goes with the run)
    if args.write:
        folder = B.build_data("installer", "full_string_" + time.strftime("%Y-%m-%d_%H%M%S"))
        os.makedirs(folder, exist_ok=True)
    else:
        import tempfile
        folder = tempfile.mkdtemp(prefix="bake_string_")
    snapshot = os.path.join(folder, "MelloUI.SavedVariables.lua")
    files = [(snapshot, sv), (os.path.join(folder, STRING_FILE), re.sub(r"\s+", "", raw) + "\n"),
             (os.path.join(folder, TEXT_FILE), own_text + "\n")]
    if carried:
        files.append((os.path.join(folder, CARRIED_FILE), "".join("%s\t%s\n" % (e, why) for e, why in carried)))
    for name, body in files:
        with open(name, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(body)
    print("the string's snapshot: %s" % snapshot)
    return snapshot, own_text, {e.partition("=")[0]: why for e, why in carried}, checks


def print_account(acc):
    print("every entry of the string: %d shipped as it is, %d shipped changed, %d left out, %d added by the bake"
          % (len(acc["same"]), len(acc["changed"]), len(acc["dropped"]), len(acc["added"])))
    for key, why in acc["changed"]:
        print("  changed   %-48s %s" % (key, why))
    for key, why in acc["dropped"]:
        print("  left out  %-48s %s" % (key, why))
    for key, why in acc["added"]:
        print("  added     %-48s %s" % (key, why))
    for key, why in acc.get("carriedGone", []):
        print("  carried, not shipped  %-36s %s" % (key, why))
    for key in acc["unexplained"]:
        print("  LEFT OUT FOR NO KNOWN REASON  %s" % key)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--snapshot", default=SNAP)
    ap.add_argument("--string", metavar="FILE", help="bake from a profile share string in this file (the Profiles "
                    "page's Export): it becomes the bake's snapshot")
    ap.add_argument("--clipboard", action="store_true", help="as --string, the string read from the clipboard")
    ap.add_argument("--fill-missing", action="store_true", help="with --string: a module the string has no entry "
                    "for (a feature addon its client lacks) keeps the shipped Full's own entries, and so do "
                    "MelloUI_Oldschool's settings the string has none of")
    ap.add_argument("--carry", metavar="FILE", help="with --string: MelloUI_Oldschool's settings from this profile "
                    "text or share string, where the string has none (before --fill-missing)")
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
    acc = None
    if (a.fill_missing or a.carry) and not (a.string or a.clipboard):
        raise SystemExit("--fill-missing and --carry go with --string or --clipboard")
    if a.string or a.clipboard:
        a.snapshot, source_text, carried, checks = ship_string(a)
    full, report, lua = bake(a.snapshot, a.tries, a.wait)
    if a.string or a.clipboard:
        acc = account(source_text, full, report, lua, checks, carried)
        report["stringAccount"] = acc
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
    for t in report["fit"]["eye"]:
        print("  the user's eye:", t)
    print("extra personal dropped:", report["extraPersonalDropped"])
    print("%s's own, read with it loaded: %d entries; the skin left out: %s" % (
        ", ".join(B.FULL_WITHOUT), len(report["featureCarried"]), report["skinLeftOut"]))
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
    if acc is not None:
        print_account(acc)
        if acc["unexplained"]:
            raise SystemExit("%d entries of the string were left out for no known reason (listed above): nothing "
                             "written" % len(acc["unexplained"]))
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
