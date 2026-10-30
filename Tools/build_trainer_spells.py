"""Bakes Media/TrainerSpells.lua: the spells each class's trainer teaches and the level each comes at, from WoW
Forever's own client tables -- one rule, never a hand-kept list (1.2.4, the Level Up Card: "New at your trainer").

The rule (WoWExport/forever_70532/db2, client 1.60.1.70532):
  a class's trainer spell  a SkillLineAbility row on one of the class's three skill lines, learned by training
                           (AcquireMethod 0), its spell ID under 30000 (Forever's class spells: the classic trainer
                           spells), not passive (SpellMisc Attributes_0 0x40), not a spell of Forever's own Talent
                           table, not a spell a talent sets off (a SpellEffect of a talent's spell triggers it: Impact,
                           Clearcasting ...). (Not told apart by the tables: the few ranks a tome teaches at 56-60 --
                           every trainer spell has a teaching spell too -- and the Polymorph variants.)
  its level                SpellLevels.BaseLevel (difficulty 0), its SpellLevel where the base is 0 (Rockbiter,
                           Dash, Eye of Kilrogg ...)
  its races                SkillLineAbility.RaceMasks_0 when it names some races only (a side's teleports and
                           portals, a race's own priest spells): `races` keeps the mask (bit raceID - 1)
  a talent's later rank    its SupercedesSpell chain ends at a talent's spell, or it has a talent's spell's name
                           (Pyroblast, Mortal Strike ...): `needs` names that spell (the trainer teaches the rank
                           only to who has the talent)
Written: Media/TrainerSpells.lua, MelloUI_TrainerSpells = { [CLASS] = { [level] = { spellID, ... } }, races =
{...}, needs = {...} }. --check prints, per class, how many of the cached trainer pages' spells (Workspace/BuildData/
cache/wowhead, through build_quest_list's own reader) the rule finds at the same level.

    python Tools/build_trainer_spells.py [--check] [--out FILE]   (--out: written there instead: the suite's guard)
"""
import argparse
import collections
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from paths import WORKSPACE  # noqa: E402

DB2 = os.path.join(WORKSPACE, "GameData", "WoWExport", "forever_70532", "db2")
OUT = os.path.join(HERE, "..", "Media", "TrainerSpells.lua")
# the class skill lines by ID (the names repeat: Holy, Protection, Restoration), as heal_flight_spells.py
CLASS_LINES = {
    "WARRIOR": {26, 256, 257}, "PALADIN": {594, 267, 184}, "HUNTER": {50, 163, 51}, "ROGUE": {253, 38, 39},
    "PRIEST": {613, 56, 78}, "SHAMAN": {375, 373, 374}, "MAGE": {237, 8, 6}, "WARLOCK": {355, 354, 593},
    "DRUID": {574, 134, 573},
}
CLASS_BIT = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 4, "ROGUE": 8, "PRIEST": 16, "SHAMAN": 64, "MAGE": 128,
             "WARLOCK": 256, "DRUID": 1024}
TRAINER_MAX = 30000
PASSIVE = 0x40
ALL_RACES = 0xFF   # the eight races' bits: a mask naming them all is no limit


def rows(name):
    with open(os.path.join(DB2, name + ".csv"), encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def build():
    base = {int(r["SpellID"]): int(r["BaseLevel"]) or int(r["SpellLevel"])
            for r in rows("SpellLevels") if r["DifficultyID"] == "0"}
    names = {int(r["ID"]): r["Name_lang"] for r in rows("SpellName")}
    passive = {int(r["SpellID"]) for r in rows("SpellMisc")
               if r["DifficultyID"] == "0" and int(r["Attributes_0"]) & PASSIVE}
    tab_class = {}
    for r in rows("TalentTab"):
        for cls, bit in CLASS_BIT.items():
            if int(r["ClassMask"] or 0) & bit:
                tab_class[int(r["ID"])] = cls
    talent, talent_class = set(), {}
    for r in rows("Talent"):
        for i in range(9):
            v = int(r["SpellRank_%d" % i] or 0)
            if v:
                talent.add(v)
                talent_class[v] = tab_class.get(int(r["TabID"] or 0))
    # a class's talent's spell by its name (the lowest ID of that name: its first rank)
    talent_named = {}
    for sid in sorted(talent):
        talent_named.setdefault((talent_class.get(sid), names.get(sid)), sid)
    triggered = set()
    for r in rows("SpellEffect"):
        sid, trig = int(r["SpellID"]), int(r["EffectTriggerSpell"] or 0)
        if trig and sid in talent:
            triggered.add(trig)
    sla = rows("SkillLineAbility")
    supersedes = {int(r["Spell"]): int(r["SupercedesSpell"] or 0) for r in sla}

    def root(sid):
        seen = set()
        while supersedes.get(sid) and sid not in seen:
            seen.add(sid)
            sid = supersedes[sid]
        return sid

    spells = collections.defaultdict(lambda: collections.defaultdict(set))
    races, needs = {}, {}
    for r in sla:
        sid, line = int(r["Spell"]), int(r["SkillLine"])
        if sid >= TRAINER_MAX or r["AcquireMethod"] != "0":
            continue
        if sid in passive or sid in talent or sid in triggered:
            continue
        lv = base.get(sid, 0)
        if lv < 1:
            continue
        for cls, lines in CLASS_LINES.items():
            if line in lines:
                spells[cls][lv].add(sid)
                m = int(r["RaceMasks_0"] or 0) & 0xFFFF
                if m and m & ALL_RACES != ALL_RACES:
                    races[sid] = m
                first = root(sid)
                if first != sid and first in talent:
                    needs[sid] = first
                elif (cls, names.get(sid)) in talent_named:
                    needs[sid] = talent_named[(cls, names[sid])]
    return spells, races, needs


def write(spells, races, needs, out_path=OUT):
    out = ["-- Generated by Tools/build_trainer_spells.py from WoW Forever's own client tables (1.60.1.70532): the",
           "-- spells each class's trainer teaches, by the level they come at (the Level Up Card's \"New at your",
           "-- trainer\"). Do not edit by hand.",
           "-- [CLASS] = { [level] = { spellID, ... } }; races: [spellID] = the races it is for (bit raceID - 1), a",
           "-- spell for some races only; needs: [spellID] = the talent's spell the trainer asks for first",
           "MelloUI_TrainerSpells = {"]
    for cls in CLASS_LINES:
        out.append("\t%s = {" % cls)
        for lv in sorted(spells[cls]):
            out.append("\t\t[%d] = { %s }," % (lv, ", ".join(str(s) for s in sorted(spells[cls][lv]))))
        out.append("\t},")
    out.append("\traces = {")
    for sid in sorted(races):
        out.append("\t\t[%d] = %d," % (sid, races[sid]))
    out.append("\t},")
    out.append("\tneeds = {")
    for sid in sorted(needs):
        out.append("\t\t[%d] = %d," % (sid, needs[sid]))
    out.append("\t},")
    out.append("}")
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")


def check(spells):
    """the cached trainer pages' spells under 30000, per class: how many the rule has at the same level"""
    import build_quest_list as bql
    pages = bql.load_npc_pages()
    want = collections.defaultdict(set)
    for p in pages.values():
        m = re.match(r"^(\w+) Trainer$", p["tag"])
        cls = m and m.group(1).upper()
        if cls in CLASS_LINES and p["patch"] in (bql.FOREVER_PATCH, bql.CLASSIC_PATCH):
            for d in p["abilities"]:
                if isinstance(d.get("level"), int) and isinstance(d.get("id"), int) and d["id"] < TRAINER_MAX:
                    want[cls].add((d["id"], d["level"]))
    for cls in CLASS_LINES:
        ours = {(s, lv) for lv, ss in spells[cls].items() for s in ss}
        print("%-8s rule %3d  pages %3d  both %3d  pages only %s" % (
            cls, len(ours), len(want[cls]), len(ours & want[cls]), sorted(want[cls] - ours)[:8]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()
    spells, races, needs = build()
    write(spells, races, needs, args.out)
    n = sum(len(ss) for c in spells.values() for ss in c.values())
    print(os.path.normpath(args.out), n, "spells,", len(races), "for some races,", len(needs), "after a talent")
    if args.check:
        check(spells)


if __name__ == "__main__":
    main()
