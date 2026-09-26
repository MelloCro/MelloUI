#!/usr/bin/env python3
"""
Bake the Route module's learned paths into Media/RouteData.lua.

This client keeps addon saved variables only in memory across /reload and
drops them at restart, but it writes the file. The Route module saves its
graph as MelloUIRoutes; this script reads that file after a /reload and
writes it as an ordinary addon data file, into the project and straight into
the game's AddOns folder, so the next /reload starts from everything learned.

It also keeps the player's own saved settings profiles (MelloUIDB.profiles)
in Media/Profiles.lua, for the same reason. That file ships, and two names
in it are never the saved variables' to write (SHIPPED_PROFILES): "MelloUI",
the Full experience the installer applies, baked by
Tools/installer/bake_full.py, and "Everything Off", which Core builds at
every login. Their entries, the file's head and its `default` line stay
exactly as they are; only the other profiles are written, from the saved
variables. A file whose layout it does not know is left alone.

Usage:
  python Tools/bake_routes.py            bake once
  python Tools/bake_routes.py --watch    bake whenever the saved file changes
"""

import argparse
import glob
import os
import re
import sys
import time

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_OUT = os.path.join(HERE, "..", "Media", "RouteData.lua")
DEFAULT_WTF = "F:/World of Warcraft/_classic_beta_/WTF"
DEFAULT_GAME_OUT = "F:/World of Warcraft/_classic_beta_/Interface/AddOns/MelloUI/Media/RouteData.lua"
PROFILES_OUT = os.path.join(HERE, "..", "Media", "Profiles.lua")

# Profiles in Media/Profiles.lua the saved variables never write: the name and
# who makes it. A player's saved copy under one of these names (Core's
# Profiles() copies the shipped "MelloUI" into the saved profiles, and writes
# "Everything Off" there at every login) is skipped.
SHIPPED_PROFILES = {
    "MelloUI": "baked by Tools/installer/bake_full.py (the Full experience)",
    "Everything Off": "built in: Core makes it from the module list at every login",
}


def log(msg):
    print(time.strftime("%H:%M:%S ") + msg, file=sys.stderr, flush=True)


def saved_files(wtf):
    return glob.glob(os.path.join(wtf, "Account", "*", "SavedVariables", "MelloUI.lua"))


def lua_value(v):
    """Lua table -> dict (string keys), scalars unchanged."""
    if lupa.lua_type(v) == "table":
        out = {}
        for k, x in v.items():
            if isinstance(k, float) and k.is_integer():
                k = int(k)
            out[str(k)] = lua_value(x)
        return out
    return v


def load_pins(path):
    """{kind: {name: {field: value}}} recorded map pins from MelloUIRoutes."""
    runtime = lupa.LuaRuntime()
    runtime.execute(open(path, encoding="utf-8", errors="replace").read())
    routes = runtime.globals().MelloUIRoutes
    pins = {"entrances": {}, "transports": {}, "services": {}}
    if routes is None or routes["pins"] is None:
        return pins
    for kind in pins:
        table = routes["pins"][kind]
        if table is not None:
            for name, v in table.items():
                if lupa.lua_type(v) == "table":
                    pins[kind][str(name)] = lua_value(v)
    return pins


def load_profiles(path):
    """({name: serialised settings}, default name or None) from MelloUIDB in a saved file."""
    runtime = lupa.LuaRuntime()
    runtime.execute(open(path, encoding="utf-8", errors="replace").read())
    db = runtime.globals().MelloUIDB
    profiles, default = {}, None
    if db is None:
        return profiles, default
    if db["profiles"] is not None:
        for name, text in db["profiles"].items():
            if isinstance(text, str):
                profiles[str(name)] = text
    if isinstance(db["defaultProfile"], str):
        default = db["defaultProfile"]
    return profiles, default


# one profile of Media/Profiles.lua: the whole line, one "name" = "text"
PROFILE_LINE = re.compile(r'\t\t\["((?:[^"\\]|\\.)*)"\] = "(?:[^"\\]|\\.)*",(?:\r?\n)?$')


def read_text(path):
    """A file's text exactly as it is (line ends untouched)."""
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.read()


def split_profiles_file(text):
    """(head, {name: line}, tail) of a Profiles.lua in the layout it has always
    had (the head is everything up to and including the '\tprofiles = {'
    line: the comments and `default`; the tail is from its closing '\t},'),
    each part byte for byte; None when the text is not in that layout."""
    lines = text.splitlines(keepends=True)
    start = next((n for n, line in enumerate(lines) if line.rstrip("\r\n") == "\tprofiles = {"), None)
    if start is None:
        return None
    end = next((n for n in range(start + 1, len(lines)) if lines[n].rstrip("\r\n") == "\t},"), None)
    if end is None or "".join(lines[end:]).replace("\r", "").rstrip("\n") != "\t},\n}":
        return None
    entries = {}
    for line in lines[start + 1:end]:
        m = PROFILE_LINE.match(line)
        if not m:
            return None
        entries[re.sub(r"\\(.)", r"\1", m.group(1))] = line
    return "".join(lines[:start + 1]), entries, "".join(lines[end:])


def profile_line(name, text, newline):
    body = text.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n")
    return f'\t\t{lua_key(name)} = "{body}",{newline}'


def write_profiles(profiles, path, template=None):
    """Put the player's own saved profiles into the Profiles.lua at `path`.

    The file keeps its head (comments and `default`), its tail and every
    SHIPPED_PROFILES entry byte for byte; a saved profile under a shipped name
    is skipped, and the other entries are the saved profiles, sorted by name
    with the shipped ones. `template` is the file to take the head and the
    shipped entries from while `path` does not exist yet (the game's copy).
    Returns (own names written, shipped names kept), or None when the file is
    not in the known layout: then nothing is written."""
    source = path if os.path.isfile(path) else template
    if not source or not os.path.isfile(source):
        return None
    parts = split_profiles_file(read_text(source))
    if parts is None:
        return None
    head, entries, tail = parts
    newline = "\r\n" if head.endswith("\r\n") else "\n"
    lines = {name: line for name, line in entries.items() if name in SHIPPED_PROFILES}
    kept = sorted(lines)
    own = sorted(name for name in profiles if name not in SHIPPED_PROFILES)
    for name in own:
        lines[name] = profile_line(name, profiles[name], newline)
    body = head + "".join(lines[name] for name in sorted(lines)) + tail
    if not (os.path.isfile(path) and read_text(path) == body):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(body)
    return own, kept


def bake_profiles(profiles, outs):
    """The player's own saved profiles into every Profiles.lua in `outs` (the
    project's first: it is the layout for a game copy that does not exist yet)."""
    own = sorted(name for name in profiles if name not in SHIPPED_PROFILES)
    written = []
    for out in outs:
        if write_profiles(profiles, out, template=outs[0]) is None:
            log(f"left {out} alone: it is not in the Profiles.lua layout this script knows (restore it from git)")
        else:
            written.append(out)
    if written:
        log(f"baked {len(own)} profile(s) of your own ({', '.join(own) or 'none'}); "
            f"{' and '.join(sorted(SHIPPED_PROFILES))} left as shipped -> {', '.join(written)}")
    return written


def load_graphs(path):
    """{continent: {cell: (x, y, {cell: cost})}} from MelloUIRoutes in a saved file."""
    runtime = lupa.LuaRuntime()
    runtime.execute(open(path, encoding="utf-8", errors="replace").read())
    routes = runtime.globals().MelloUIRoutes
    graphs = {}
    if routes is None or routes["graphs"] is None:
        return graphs
    for cont, g in routes["graphs"].items():
        nodes = {}
        for key, node in g.items():
            try:
                x, y = float(node[1]), float(node[2])
            except (TypeError, ValueError, KeyError):
                continue
            edges = {}
            if node[3] is not None:
                for other, cost in node[3].items():
                    edges[str(other)] = float(cost)
            nodes[str(key)] = (x, y, edges)
        graphs[int(cont)] = nodes
    return graphs


def merge_into(target, graphs):
    for cont, nodes in graphs.items():
        mine = target.setdefault(cont, {})
        for key, (x, y, edges) in nodes.items():
            if key not in mine:
                mine[key] = (x, y, dict(edges))
            else:
                mx, my, medges = mine[key]
                for other, cost in edges.items():
                    if other not in medges or medges[other] > cost:
                        medges[other] = cost


def lua_key(s):
    return '["' + s.replace("\\", "\\\\").replace('"', '\\"') + '"]'


def lua_literal(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return f"{v:.4f}".rstrip("0").rstrip(".") if isinstance(v, float) else str(v)
    if isinstance(v, dict):
        return "{" + ",".join(f"{lua_key(str(k))}={lua_literal(x)}" for k, x in sorted(v.items())) + "}"
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_lua(graphs, path, pins=None):
    pins = pins or {"entrances": {}, "transports": {}}
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- Generated by Tools/bake_routes.py from the saved variable MelloUIRoutes. Do not edit by hand.\n")
        fh.write("-- Learned paths for the Route module: graphs[continent uiMapID][cell] = { yards east, yards south, { [cell] = seconds } }.\n\n")
        fh.write("MelloUI_RouteData = {\n\tgraphs = {\n")
        for cont in sorted(graphs):
            fh.write(f"\t\t[{cont}] = {{\n")
            for key in sorted(graphs[cont]):
                x, y, edges = graphs[cont][key]
                parts = ",".join(f"{lua_key(o)}={c:.1f}" for o, c in sorted(edges.items()))
                fh.write(f"\t\t\t{lua_key(key)}={{{x:.1f},{y:.1f},{{{parts}}}}},\n")
            fh.write("\t\t},\n")
        fh.write("\t},\n\t-- map pins recorded by hand with /qlmap (Quest List)\n\tpins = {\n")
        for kind in ("entrances", "transports", "services"):
            fh.write(f"\t\t{kind} = {{\n")
            for name in sorted(pins.get(kind, {})):
                fh.write(f"\t\t\t{lua_key(name)}={lua_literal(pins[kind][name])},\n")
            fh.write("\t\t},\n")
        fh.write("\t},\n}\n")


def bake(args):
    files = saved_files(args.wtf)
    if not files:
        log(f"no MelloUI.lua under {args.wtf}")
        return False
    graphs = {}
    pins = {"entrances": {}, "transports": {}, "services": {}}
    profiles = {}
    for path in files:
        try:
            merge_into(graphs, load_graphs(path))
            for kind, table in load_pins(path).items():
                for name, v in table.items():
                    pins[kind].setdefault(name, v)
            p, _ = load_profiles(path)   # (the saved default is not baked: the file's `default` stays)
            profiles.update(p)
        except Exception as exc:  # noqa: BLE001
            log(f"could not read {path}: {exc}")
    nodes = sum(len(n) for n in graphs.values())
    npins = sum(len(t) for t in pins.values())
    if profiles:
        outs = [os.path.abspath(PROFILES_OUT)]
        if args.game_out:
            outs.append(os.path.join(os.path.dirname(args.game_out), "Profiles.lua"))
        bake_profiles(profiles, outs)
    if nodes == 0 and npins == 0:
        log("no learned paths or recorded pins in the saved variables yet (walk around, then /reload)")
        return bool(profiles)
    outs = [os.path.abspath(PROJECT_OUT)]
    if args.game_out:
        outs.append(args.game_out)
    for out in outs:
        write_lua(graphs, out, pins)
    log(f"baked {nodes} points on {len(graphs)} continent(s), {npins} recorded pins -> {', '.join(outs)}")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wtf", default=DEFAULT_WTF)
    ap.add_argument("--game-out", default=DEFAULT_GAME_OUT, help="also write the file here (the game's addon copy); '' to skip")
    ap.add_argument("--watch", action="store_true", help="keep running and bake after every /reload")
    ap.add_argument("--interval", type=float, default=5.0)
    args = ap.parse_args()

    bake(args)
    if not args.watch:
        return
    last = max((os.path.getmtime(p) for p in saved_files(args.wtf)), default=0)
    log("watching the saved variables; /reload in game writes them")
    while True:
        time.sleep(args.interval)
        current = max((os.path.getmtime(p) for p in saved_files(args.wtf)), default=0)
        if current > last:
            time.sleep(2)
            last = max((os.path.getmtime(p) for p in saved_files(args.wtf)), default=0)
            bake(args)


if __name__ == "__main__":
    main()
