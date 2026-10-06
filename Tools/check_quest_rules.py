#!/usr/bin/env python3
"""
A LOCAL cross-check of the Quest List's pick-up rules (0.19.5; the user, 2026-10-06, of Questie: it "does not show me
the quests on the map which i cant pickup, only the ones i can"). Never shipped, never part of the addon: QuestieDB is
GPLv3 and MelloUI MIT, so its data is READ here only to list where our rules (Media/QuestListData.lua's `needs`, built
by Tools/build_quest_list.py from classic-db, Wowhead and the client) would show a quest on the map that Questie's
would hide, for a person to review at each data build. Nothing it reads is written anywhere.

    python Tools/check_quest_rules.py [--questie DIR] [--rule NAME] [--all]

  --questie  the folder holding QuestieDB_Forever.toc (default: the user's study copy in Downloads)
  --rule     only that rule's list (class, previous, follow-up, breadcrumb, race, skill, rep, spell, child,
             until, specialisation, disabled, not-in-game)
  --all      every quest of a rule, not the first 15

The counts are of quests where Questie has a requirement our data lacks; a few are already covered another way (our
`after` with a negative id covers a child quest; our giver learning covers what no data has).
"""
import argparse
import base64
import collections
import glob
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_QUESTIE = os.path.join(os.path.expanduser("~"), "Downloads", "Addons")

# QuestieDB's quest fields (src/meta/questMeta.lua)
F = {"races": 6, "classes": 7, "preGroup": 12, "preSingle": 13, "exclusiveTo": 16, "skill": 18, "minRep": 19,
     "maxRep": 20, "next": 22, "special": 24, "parent": 25, "breadcrumbFor": 27, "breadcrumbs": 28, "spell": 30,
     "spec": 31, "maxLevel": 32, "until": 33, "startingWith": 34, "ranks": 35, "disabledBy": 36}


def cbor(b, i=0):
    """A small CBOR reader: what QuestieDB's rows use (ints, text, arrays, maps, simple values, floats)."""
    ib = b[i]
    mt, ai = ib >> 5, ib & 31
    i += 1
    if mt == 7:
        if ai in (20, 21):
            return ai == 21, i
        if ai in (22, 23):
            return None, i
        size = {25: 2, 26: 4, 27: 8}[ai]
        return struct.unpack({2: ">e", 4: ">f", 8: ">d"}[size], b[i:i + size])[0], i + size
    if ai < 24:
        v = ai
    else:
        n = {24: 1, 25: 2, 26: 4, 27: 8}[ai]
        v, i = int.from_bytes(b[i:i + n], "big"), i + n
    if mt == 0:
        return v, i
    if mt == 1:
        return -1 - v, i
    if mt in (2, 3):
        raw = b[i:i + v]
        return (raw if mt == 2 else raw.decode("utf-8", "replace")), i + v
    if mt == 4:
        out = []
        for _ in range(v):
            x, i = cbor(b, i)
            out.append(x)
        return out, i
    if mt == 5:
        out = {}
        for _ in range(v):
            k, i = cbor(b, i)
            x, i = cbor(b, i)
            out[k] = x
        return out, i
    return cbor(b, i)       # a tag: its value


def load_questie(folder):
    tocs = glob.glob(os.path.join(folder, "**", "QuestieDB_Forever.toc"), recursive=True)
    if not tocs:
        sys.exit("no QuestieDB_Forever.toc under %s (give --questie)" % folder)
    meta = {}
    with open(tocs[0], encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("## X-Quest-"):
                k, _, v = line[3:].partition(": ")
                meta[k] = v.strip()
    q = collections.defaultdict(dict)
    for k, v in meta.items():
        m = re.match(r"X-Quest-(\d+)-(S|\d+)$", k)
        if not m:
            continue
        if v.startswith("~"):
            v = "".join(meta[k + "-%d" % j] for j in range(1, int(v.strip("~")) + 1))
        try:
            val, _ = cbor(base64.b64decode(v))
        except (ValueError, KeyError, IndexError):
            continue
        qid = int(m.group(1))
        if m.group(2) == "S":
            items = val.items() if isinstance(val, dict) else enumerate(val or [], 1)
            for fk, fv in items:
                if fv is not None:
                    q[qid][fk] = fv
        else:
            q[qid][int(m.group(2))] = val
    blacklist = set()
    for path in glob.glob(os.path.join(os.path.dirname(os.path.dirname(tocs[0])), "Questie", "Database", "Corrections",
                                       "QuestieQuestBlacklist.lua")):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"\s*\[(\d+)\]\s*=\s*true\b", line)
                if m:
                    blacklist.add(int(m.group(1)))
    return q, blacklist


def load_ours():
    import lupa.lua51 as L51
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    with open(os.path.join(ROOT, "Media", "QuestListData.lua"), encoding="utf-8-sig") as fh:
        lua.execute(fh.read())
    d = lua.globals().MelloUI_QuestListData
    rows = {int(r[1]): {"title": r[2], "level": r[3], "class": r[6], "side": r[5], "giver": r[9], "event": r[13],
                        "origin": r[28]} for _, r in d.quests.items()}

    def keys(name):
        t = d.needs[name]
        return {int(k) for k, _ in t.items()} if t is not None else set()
    excl = set()
    for _, members in d.needs.exclusive.items():
        for _, m in members.items():
            excl.add(int(m))
    return rows, {n: keys(n) for n in ("after", "races", "skills", "reps", "maxLevel", "breadcrumbs", "nextChain",
                                        "crumbsTo", "cond")}, excl


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questie", default=DEFAULT_QUESTIE)
    ap.add_argument("--rule")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    q, blacklist = load_questie(args.questie)
    rows, ours, excl = load_ours()
    pinned = {i: r for i, r in rows.items() if r["giver"] and not r["event"]}
    lists = collections.defaultdict(list)
    for qid, r in sorted(pinned.items()):
        x = q.get(qid)
        if qid in blacklist:
            lists["not-in-game"].append(qid)
        if x is None:
            continue
        if x.get(F["classes"]) and not r["class"]:
            lists["class"].append(qid)
        if (x.get(F["preSingle"]) or x.get(F["preGroup"])) and qid not in ours["after"]:
            lists["previous"].append(qid)
        if x.get(F["next"]) and qid not in ours["nextChain"]:
            lists["follow-up"].append(qid)
        if x.get(F["breadcrumbs"]) and qid not in ours["crumbsTo"]:
            lists["breadcrumb"].append(qid)
        if x.get(F["races"]) and r["side"] == 3 and qid not in ours["races"]:
            lists["race"].append(qid)
        if x.get(F["skill"]) and qid not in ours["skills"]:
            lists["skill"].append(qid)
        if (x.get(F["minRep"]) or x.get(F["maxRep"])) and qid not in ours["reps"]:
            lists["rep"].append(qid)
        if x.get(F["spell"]) and qid not in ours["cond"]:
            lists["spell"].append(qid)
        if x.get(F["parent"]) and qid not in ours["after"]:
            lists["child"].append(qid)
        if (x.get(F["until"]) or x.get(F["startingWith"])) and qid not in ours["cond"]:
            lists["until"].append(qid)
        if x.get(F["spec"]) or x.get(F["ranks"]):
            lists["specialisation"].append(qid)
        if x.get(F["disabledBy"]):
            lists["disabled"].append(qid)
    print("map candidates: %d; Questie's Forever rows: %d" % (len(pinned), len(q)))
    for rule in sorted(lists, key=lambda k: -len(lists[k])):
        if args.rule and rule != args.rule:
            continue
        ids = lists[rule]
        print("\n%5d  %s" % (len(ids), rule))
        for qid in ids if args.all else ids[:15]:
            r = rows[qid]
            print("        %6d  %-40s level %-3s %s" % (qid, str(r["title"])[:40], r["level"],
                                                     "Forever's own" if r["origin"] == 2 else ""))


if __name__ == "__main__":
    main()
