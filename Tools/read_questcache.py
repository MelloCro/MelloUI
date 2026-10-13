"""The game client's quest cache (docs/plans/quest-scan.md; the user, 2026-10-13: "There has to be a way to get the
actual quest data"). The client keeps every quest the server told it about in Cache/WDB/enUS/questcache.wdb, and the
MelloUIDataScan dev addon (MelloUI Test, /melloscan quests) asks the server for every quest of the client's QuestV2
table. This reads that cache: Forever's own server's answers, so the quest list no longer needs Wowhead's listing.

The file (build 1.60.1.70338): a 24-byte header ("TSQW", build, locale, record size, version, 0), then records of
quest ID, length and data until an ID and length of 0. A record, worked out from the 108 cached quests against
classic-db's quest_template (58 of them classic):
    0 quest ID      4 type (classic-db Method)   8 level      16 min level   24 sort (zone, or a negative sort)
    28 quest info (81 dungeon, 62 raid, 1 group, 41 PvP)      32 suggested group   36 next in chain
    40 XP difficulty   44 XP multiplier (float)   48 money    52 money difficulty   56 money multiplier (float)
    64 reward display spells (a count: 12 bytes each before the objectives)   68 reward spell
    96 start item   100 flags   104 flags ex   116.. reward items (item, amount) x4   180.. choice items (item,
    amount, display) x6   300.. reputation (faction, value, override, cap) x5   436 objectives (a count)
    440 races (64-bit; -1 every race)
    488 the reward display spells, then the objectives: ID, type (byte; 0 monster, 1 item, 2 object, 3 talk to,
    10 area trigger, 14 criteria ...), index (+8), object ID (+9), amount (+13), effects (a count at +33, the list
    from +41), then the description's length and a bit byte and the description.
    Then 12 bytes of bit-packed string lengths (9, 12, 12, 9, 10, 8, 10, 8, 11 bits, the high bit first) and the
    strings: title, objective summary, description, area description, portrait giver text and name, portrait
    turn-in text and name, completion text.
The extracted cache stays local (the wow-export rule): only data derived from it ships.

    python Tools/read_questcache.py                 every quest, written to BuildData/cache/questcache_<build>.json
    python Tools/read_questcache.py --check         and compared with classic-db's quest_template
    python Tools/read_questcache.py --quest 170     one quest, in full
"""
import argparse
import glob
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from paths import CACHE  # noqa: E402
GAME = "F:/World of Warcraft/_classic_beta_"
WDB = GAME + "/Cache/WDB/enUS/questcache.wdb"
MAGIC = b"TSQW"
STRINGS = ("title", "summary", "description", "area", "giverText", "giverName", "turnInText", "turnInName",
           "completion")
STRING_BITS = (9, 12, 12, 9, 10, 8, 10, 8, 11)
STRING_HEADER = 12


class Reader:
    def __init__(self, data):
        self.d, self.at = data, 0

    def int(self, at=None):
        return struct.unpack_from("<i", self.d, self.at if at is None else at)[0]

    def take(self, n):
        out = self.d[self.at:self.at + n]
        if len(out) < n:
            raise ValueError("record ends at %d, wanted %d more bytes" % (len(self.d), self.at + n - len(self.d)))
        self.at += n
        return out

    def text(self, n):
        return self.take(n).decode("utf-8", errors="replace")


def bits(data, widths):
    """unsigned fields of the given widths, the high bit first"""
    value, have, out, at = 0, 0, [], 0
    for w in widths:
        while have < w:
            value, have, at = (value << 8) | data[at], have + 8, at + 1
        have -= w
        out.append((value >> have) & ((1 << w) - 1))
    return out


def records(path=WDB):
    """(build, {quest ID: raw record})"""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != MAGIC:
        raise ValueError("%s is not a quest cache (%r)" % (path, data[:4]))
    build = struct.unpack_from("<I", data, 4)[0]
    at, out = 24, {}
    while at + 8 <= len(data):
        qid, n = struct.unpack_from("<II", data, at)
        if qid == 0 and n == 0:
            break
        out[qid] = data[at + 8:at + 8 + n]
        at += 8 + n
    return build, out


def parse(raw):
    r = Reader(raw)
    i = r.int
    q = {
        "id": i(0), "type": i(4), "level": i(8), "minLevel": i(16), "sort": i(24), "info": i(28), "group": i(32),
        "next": i(36), "xpDifficulty": i(40), "money": i(48), "rewardSpell": i(68), "startItem": i(96),
        "flags": i(100) & 0xffffffff, "flagsEx": i(104) & 0xffffffff,
        "races": struct.unpack_from("<q", raw, 440)[0],
        "rewardItems": [(i(116 + 8 * k), i(120 + 8 * k)) for k in range(4) if i(116 + 8 * k)],
        "choiceItems": [(i(180 + 12 * k), i(184 + 12 * k)) for k in range(6) if i(180 + 12 * k)],
        "reputation": [(i(300 + 16 * k), i(304 + 16 * k)) for k in range(5) if i(300 + 16 * k)],
    }
    spells, count = i(64), i(436)
    if not (0 <= spells < 16 and 0 <= count < 32):
        raise ValueError("odd counts: %d reward spells, %d objectives" % (spells, count))
    r.at = 488
    q["displaySpells"] = []
    for _ in range(spells):
        q["displaySpells"].append(r.int())
        r.take(12)
    q["objectives"] = []
    for _ in range(count):
        o = r.take(41)
        effects = struct.unpack_from("<i", o, 33)[0]
        if not 0 <= effects < 16:
            raise ValueError("odd objective effects count %d" % effects)
        r.take(4 * effects)
        length = r.take(2)[0]
        q["objectives"].append({
            "id": struct.unpack_from("<i", o, 0)[0], "type": o[4], "index": o[8],
            "object": struct.unpack_from("<i", o, 9)[0], "amount": struct.unpack_from("<i", o, 13)[0],
            "text": r.text(length),
        })
    for name, n in zip(STRINGS, bits(r.take(STRING_HEADER), STRING_BITS)):
        q[name] = r.text(n)
    q["rest"] = len(raw) - r.at
    return q


def load(path=WDB):
    """(build, {quest ID: quest}, {quest ID: why it could not be read})"""
    build, raw = records(path)
    quests, broken = {}, {}
    for qid, data in raw.items():
        try:
            quests[qid] = parse(data)
        except (ValueError, IndexError, struct.error) as e:
            broken[qid] = str(e)
    return build, quests, broken


# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------

def classic_db():
    sys.path.insert(0, HERE)
    import build_quest_list as B  # noqa: E402
    return {int(r["entry"]): r for r in B.sql_rows(os.path.join(B.CACHE, "ClassicDB.sql.gz"), "quest_template")}


def check(quests):
    """classic-db's answers for the classic quests in the cache -> (checked, differences)"""
    cdb = classic_db()
    diffs, checked = [], 0
    for qid, q in sorted(quests.items()):
        c = cdb.get(qid)
        if not c:
            continue
        checked += 1
        n = lambda k: int(float(c[k] or 0))  # noqa: E731
        want = {"level": n("QuestLevel"), "minLevel": n("MinLevel"), "sort": n("ZoneOrSort"), "type": n("Method"),
                "next": n("NextQuestInChain"), "startItem": n("SrcItemId"), "title": c["Title"]}
        for key, value in want.items():
            if q[key] != value:
                diffs.append((qid, key, value, q[key]))
        targets = sorted((n("ReqCreatureOrGOId%d" % k), n("ReqCreatureOrGOCount%d" % k)) for k in range(1, 5)
                         if n("ReqCreatureOrGOId%d" % k))
        targets += sorted((n("ReqItemId%d" % k), n("ReqItemCount%d" % k)) for k in range(1, 5) if n("ReqItemId%d" % k))
        got = sorted((abs(o["object"]), o["amount"]) for o in q["objectives"] if o["type"] in (0, 1, 2))
        if got != sorted((abs(t), a) for t, a in targets):
            diffs.append((qid, "objectives", targets, [(o["type"], o["object"], o["amount"]) for o in q["objectives"]]))
    return checked, diffs


# ---------------------------------------------------------------------------
# the scan addon's saved answers, and the snapshots the builders read
# ---------------------------------------------------------------------------

TOKEN = re.compile(r'\s+|--[^\n]*|"((?:[^"\\]|\\.)*)"|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|([A-Za-z_]\w*)|(.)', re.S)
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'"}


def lua_values(text):
    """A saved variables file (machine written: names = tables of strings, numbers, booleans) -> {name: value};
    a table with keys 1..n only becomes a list"""
    tokens = []
    for m in TOKEN.finditer(text):
        s, num, name, punct = m.groups()
        if s is not None:
            tokens.append(("s", re.sub(r"\\(.)", lambda e: ESCAPES.get(e.group(1), e.group(1)), s)))
        elif num is not None:
            tokens.append(("n", float(num) if "." in num or "e" in num.lower() else int(num)))
        elif name is not None:
            tokens.append(("w", name))
        elif punct is not None:
            tokens.append(("p", punct))
    at = [0]

    def take():
        t = tokens[at[0]]
        at[0] += 1
        return t

    def value():
        kind, v = take()
        if kind == "p" and v == "{":
            out, n = {}, 0
            while tokens[at[0]] != ("p", "}"):
                if tokens[at[0]] == ("p", "["):
                    take()
                    key = value()
                    take()   # ]
                    take()   # =
                    out[key] = value()
                else:
                    n += 1
                    out[n] = value()
                if tokens[at[0]] in (("p", ","), ("p", ";")):
                    take()
            take()
            if out and all(isinstance(k, int) for k in out) and sorted(out) == list(range(1, len(out) + 1)):
                return [out[k] for k in range(1, len(out) + 1)]
            return out
        if kind == "w":
            return {"true": True, "false": False, "nil": None}.get(v, v)
        return v

    found = {}
    while at[0] < len(tokens):
        kind, name = take()
        if kind == "w" and tokens[at[0]] == ("p", "="):
            take()
            found[name] = value()
    return found


def scan_saved():
    """The MelloUIDataScan addon's saved answers, if a scan was run (the newest file of every account):
    {"done": bool, "build": "1.60.1.70338" or None, "quests": {id: {title, level, objectives ...}}, "failed": {id}}"""
    paths = sorted(glob.glob(GAME + "/WTF/Account/*/SavedVariables/MelloUIDataScan.lua"), key=os.path.getmtime)
    if not paths:
        return None
    saved = lua_values(open(paths[-1], encoding="utf-8", errors="replace").read()).get("MelloUIDataScanSaved") or {}

    def ids(table):
        return table.items() if isinstance(table, dict) else enumerate(table or [], 1)
    build = saved.get("build")
    return {"done": bool(saved.get("done")),
            "build": ".".join(str(v) for v in build[:2]) if isinstance(build, list) else None,
            "quests": {int(k): v for k, v in ids(saved.get("quests")) if isinstance(v, dict)},
            "failed": {int(k) for k, v in ids(saved.get("failed")) if v}}


def snapshot():
    """What the builders read: the newest questcache_<build>.json in BuildData's cache (this tool writes it) and the
    scan's answers saved beside it (questscan_<build>.json) -> (build, {quest ID: quest}, scan or None);
    (None, {}, None) when no cache was read yet."""
    found = sorted((int(m.group(1)), p) for p in glob.glob(os.path.join(CACHE, "questcache_*.json"))
                   for m in [re.search(r"questcache_(\d+)\.json$", p)] if m)
    if not found:
        return None, {}, None
    build, path = found[-1]
    quests = {int(k): v for k, v in json.load(open(path, encoding="utf-8")).items()}
    scan_path = os.path.join(CACHE, "questscan_%d.json" % build)
    scan = None
    if os.path.exists(scan_path):
        raw = json.load(open(scan_path, encoding="utf-8"))
        scan = {"done": raw["done"], "build": raw.get("build"), "failed": set(raw["failed"]),
                "quests": {int(k): v for k, v in raw["quests"].items()}}
    return build, quests, scan


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--wdb", default=WDB)
    ap.add_argument("--check", action="store_true", help="compare with classic-db and the scan addon's answers")
    ap.add_argument("--quest", type=int, help="print one quest in full")
    args = ap.parse_args()
    build, quests, broken = load(args.wdb)
    if args.quest:
        print(json.dumps(quests.get(args.quest) or broken.get(args.quest), indent=1, ensure_ascii=False))
        return 0
    rest = sorted(qid for qid, q in quests.items() if q["rest"])
    print("build %d: %d quests read, %d broken, %d with bytes left over" % (build, len(quests), len(broken), len(rest)))
    for qid, why in sorted(broken.items())[:20]:
        print("  broken %d: %s" % (qid, why))
    for qid in rest[:20]:
        print("  left over %d: %d bytes (%s)" % (qid, quests[qid]["rest"], quests[qid]["title"]))
    out = os.path.join(CACHE, "questcache_%d.json" % build)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump({str(k): v for k, v in sorted(quests.items())}, f, ensure_ascii=False, indent=0)
    print("wrote", out)
    scan = scan_saved()
    if scan:
        # (a scan of another build is left alone: its answers would not match this cache)
        if scan["build"] and scan["build"].split(".")[-1] != str(build):
            print("scan addon: its answers are of build %s, the cache of %d: not kept" % (scan["build"], build))
            scan = None
        else:
            path = os.path.join(CACHE, "questscan_%d.json" % build)
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                json.dump({"done": scan["done"], "build": scan["build"], "failed": sorted(scan["failed"]),
                           "quests": {str(k): v for k, v in sorted(scan["quests"].items())}}, f, ensure_ascii=False,
                          indent=0)
            print("scan addon: %d answers, %d unknown to the server, %s; wrote %s" % (
                len(scan["quests"]), len(scan["failed"]), "done" if scan["done"] else "NOT done", path))
    if not args.check:
        return 1 if broken else 0
    checked, diffs = check(quests)
    print("classic-db: %d classic quests checked, %d differences" % (checked, len(diffs)))
    for d in diffs[:40]:
        print("  %d %s: classic-db %r, cache %r" % d)
    if scan:
        answered = [q for q in scan["quests"] if q in quests]
        off = [(qid, (a.get("title"), a.get("level")), (quests[qid]["title"], quests[qid]["level"]))
               for qid, a in scan["quests"].items()
               if qid in quests and (a.get("title") != quests[qid]["title"] or a.get("level") != quests[qid]["level"])]
        print("scan addon against the cache: %d answered, %d of them cached, %d differ; %d answered but not cached" % (
            len(scan["quests"]), len(answered), len(off), len(scan["quests"]) - len(answered)))
        for o in off[:20]:
            print("  %d addon %r, cache %r" % o)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
