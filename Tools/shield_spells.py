"""The Personal Display's shields (docs/plans/personal-display.md; the user, 2026-10-12: "a single shield bar which
includes all of the shields in the game, there are certain passives and active spells that give you a shield, also
some items which absorb certain damage types"; their pick B of prd_multishield: one column in parts, each shield its own
colour). Every shield comes from what the client's own spell data says it does, never a list by hand: a spell with an
aura 69 SCHOOL_ABSORB or 97 MANA_SHIELD (SpellEffect, Effect 6 APPLY_AURA) is a shield -- a spell, a talent or an
item's (a potion's, a trinket's) alike.

Each one's code: its amount's place among the aura's values (AuraData.points: the absorbing effect's EffectIndex + 1)
times ten, plus its colour's school:
    0 none of these (the shield's blue)   1 holy   2 fire   3 nature   4 frost   5 shadow   6 arcane
the one school it absorbs when it is one (EffectMiscValue_0: Fire Ward, a Fire Protection Potion -> fire), else the
spell's own school (SpellMisc.SchoolMask: Power Word: Shield holy, Ice Barrier frost, Mana Shield arcane), physical or
several -> 0. Read from the client's tables as wow.export wrote them (F:/Download-Backup/WoWExport/db2); written to
MelloUI_PersonalDisplay/ShieldSpells.lua.

    python Tools/shield_spells.py
"""
import csv
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB2 = r"F:/Download-Backup/WoWExport/db2/"
OUT = os.path.join(ROOT, "MelloUI_PersonalDisplay", "ShieldSpells.lua")

ABSORB_AURAS = {69, 97}
# a school's bit -> its code (physical, 1, has none)
SCHOOL = {2: 1, 4: 2, 8: 3, 16: 4, 32: 5, 64: 6}
NAMES = ["none", "holy", "fire", "nature", "frost", "shadow", "arcane"]


def num(v):
    try:
        return int(float(v or 0))
    except ValueError:
        return 0


def one_school(mask):
    """a mask of one school other than physical -> its code, else None"""
    return SCHOOL.get(mask)


def read():
    shields = {}   # spell -> (effect index, absorbed mask)
    with open(DB2 + "SpellEffect.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if num(row.get("Effect")) != 6 or num(row.get("EffectAura")) not in ABSORB_AURAS:
                continue
            if num(row.get("DifficultyID")) != 0:
                continue
            spell = num(row.get("SpellID"))
            index = num(row.get("EffectIndex"))
            mask = num(row.get("EffectMiscValue_0"))
            # (the first absorbing effect of a spell)
            if spell not in shields or index < shields[spell][0]:
                shields[spell] = (index, mask)
    own = {}
    with open(DB2 + "SpellMisc.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            spell = num(row.get("SpellID"))
            if spell in shields and num(row.get("DifficultyID")) == 0:
                own[spell] = num(row.get("SchoolMask"))
    codes = {}
    for spell, (index, mask) in shields.items():
        school = one_school(mask)
        if school is None:
            school = one_school(own.get(spell, 0)) or 0
        codes[spell] = (index + 1) * 10 + school
    return codes


def write(codes):
    counts = [0] * len(NAMES)
    for c in codes.values():
        counts[c % 10] += 1
    lines = [
        "--------------------------------------------------------------------------------",
        "-- MelloUI - Personal Display: every shield, from the client's own spell data",
        "-- (written by Tools/shield_spells.py: never edit by hand). [spell] = its amount's",
        "-- place among the aura's values x 10 + its colour's school (0 none, 1 holy,",
        "-- 2 fire, 3 nature, 4 frost, 5 shadow, 6 arcane)",
        "--   %d shields: %s" % (len(codes), ", ".join("%s %d" % (NAMES[i], n) for i, n in enumerate(counts) if n)),
        "--------------------------------------------------------------------------------",
        "",
        "local _, ns = ...",
        "",
        "ns.ShieldSpells = {",
    ]
    items = sorted(codes.items())
    for i in range(0, len(items), 8):
        lines.append("\t" + " ".join("[%d] = %d," % kv for kv in items[i:i + 8]))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return OUT


if __name__ == "__main__":
    codes = read()
    print(write(codes), len(codes), "shields")
    for spell in (17, 11426, 1463, 543, 6143, 17543, 23506):
        print("  %6d -> %s" % (spell, codes.get(spell)))
