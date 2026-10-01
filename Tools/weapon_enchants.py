"""The items that put a timed enchant back on a weapon (a poison, an oil, a sharpening stone or a weightstone), from
the Forever client's own tables, as the Lua table Modules/Widgets.lua keeps (WEAPON_ITEMS: [enchant id] = { item id,
... }). IDs only: the names are read from the game at run time.

The tables come from wow.export (see the wow-export notes; they stay local, nothing extracted ships):
SpellEffect (effect 54 "enchant item temporary", and 360, this client's poisons), SpellItemEnchantment (its
Duration: a timed one), ItemEffect + ItemXItemEffect (the item whose use casts the spell) and ItemSparse (only items
this client has). Left out: fishing lures, a recipe's imbue, the runecarving test items and a shield's coating.

    python Tools/weapon_enchants.py [--db2 F:/Download-Backup/WoWExport/db2]   prints the Lua table
"""
import argparse
import collections
import csv
import os

SKIP_ENCHANT = ("Fishing Lure",)
SKIP_ITEM = ("Formula:", "Runecarving Test", "Conductive Shield Coating")


def rows(d, name):
    with open(os.path.join(d, name + ".csv"), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def table(d):
    enchant_of_spell = {int(r["SpellID"]): int(r["EffectMiscValue_0"])
                        for r in rows(d, "SpellEffect") if r["Effect"] in ("54", "360")}
    enchants = {int(r["ID"]): r for r in rows(d, "SpellItemEnchantment")}
    effect_spell = {int(r["ID"]): int(r["SpellID"]) for r in rows(d, "ItemEffect")}
    names = {int(r["ID"]): r["Display_lang"] for r in rows(d, "ItemSparse")}
    out = collections.defaultdict(set)
    for r in rows(d, "ItemXItemEffect"):
        item = int(r["ItemID"])
        enchant = enchant_of_spell.get(effect_spell.get(int(r["ItemEffectID"]), -1))
        info = enchants.get(enchant or -1)
        if not info or int(info["Duration"] or 0) <= 1 or item not in names:
            continue
        if info["Name_lang"].startswith(SKIP_ENCHANT) or names[item].startswith(SKIP_ITEM):
            continue
        out[enchant].add(item)
    return {e: sorted(v) for e, v in out.items()}, names


def lua(t, names):
    lines = []
    for e in sorted(t):
        lines.append("\t[%d] = { %s },   -- %s" % (e, ", ".join(str(i) for i in t[e]),
                                                 ", ".join(names[i] for i in t[e])))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db2", default=r"F:/Download-Backup/WoWExport/db2")
    a = ap.parse_args()
    t, names = table(a.db2)
    print(lua(t, names))
    print("-- %d enchants, %d items" % (len(t), sum(len(v) for v in t.values())))


if __name__ == "__main__":
    main()
