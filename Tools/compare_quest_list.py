"""Two Media/QuestListData.lua files side by side, quest by quest (docs/plans/quest-scan.md, step 4: after the
quest list is built from the game client's quest cache, what came back, what is new, what changed).

    python Tools/compare_quest_list.py NEW [OLD]      OLD: the committed Media/QuestListData.lua (git HEAD)
    python Tools/compare_quest_list.py NEW --list added|removed|title|level|reqlevel|side|class|zone|giver
"""
import argparse
import collections
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# a quest row: {id,"title",level,req,side,class,quest zone,giver zone,"giver",gx,gy,kind,...}
ROW = re.compile(r'^\t\t\{(\d+),"((?:[^"\\]|\\.)*)",(-?\d+),(-?\d+),(-?\d+),(-?\d+),(-?\d+),(-?\d+),"((?:[^"\\]|\\.)*)",',
                 re.M)
FIELDS = ("title", "level", "reqlevel", "side", "class", "zone", "giverZone", "giver")


def rows(text):
    i = text.find("\tquests = {")
    out = {}
    for m in ROW.finditer(text, i if i >= 0 else 0):
        qid, title, level, req, side, cls, zone, gzone, giver = m.groups()
        out[int(qid)] = {"title": title, "level": int(level), "reqlevel": int(req), "side": int(side),
                         "class": int(cls), "zone": int(zone), "giverZone": int(gzone), "giver": giver}
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("new")
    ap.add_argument("old", nargs="?")
    ap.add_argument("--list", help="print every quest of one kind of change")
    args = ap.parse_args()
    new = rows(open(args.new, encoding="utf-8").read())
    if args.old:
        old_text = open(args.old, encoding="utf-8").read()
    else:
        old_text = subprocess.run(["git", "-C", ROOT, "show", "HEAD:Media/QuestListData.lua"], capture_output=True,
                                  text=True, encoding="utf-8", check=True).stdout
    old = rows(old_text)
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = collections.defaultdict(list)
    for qid in sorted(set(new) & set(old)):
        for f in FIELDS:
            if new[qid][f] != old[qid][f]:
                changed[f].append(qid)
    print("old %d quests, new %d: %d added, %d removed, %d in both" % (
        len(old), len(new), len(added), len(removed), len(set(new) & set(old))))
    for f in FIELDS:
        if changed[f]:
            print("  %-9s changed on %d" % (f, len(changed[f])))
    giverless = [q for q in added if not new[q]["giver"]]
    print("  of the added: %d with a giver, %d without (listed without a pin)" % (len(added) - len(giverless), len(giverless)))

    def show(q, row):
        return "%6d  %-44s lvl %2d/%-2d side %d class %4d zone %5d  giver %s" % (
            q, row["title"][:44], row["level"], row["reqlevel"], row["side"], row["class"], row["zone"],
            row["giver"] or "-")
    if args.list in ("added", "removed"):
        for q in added if args.list == "added" else removed:
            print(show(q, (new if args.list == "added" else old)[q]))
    elif args.list:
        key = {"class": "class", "zone": "zone", "giver": "giver"}.get(args.list, args.list)
        for q in changed.get(key, []):
            print("%6d  %-40s %r -> %r" % (q, new[q]["title"][:40], old[q][key], new[q][key]))
    else:
        for name, ids, src in (("added", added, new), ("removed", removed, old)):
            if ids:
                print("\n%s (first 15):" % name)
                for q in ids[:15]:
                    print("  " + show(q, src[q]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
