"""The Personal Display's big cooldowns (docs/plans/personal-display.md; the user, 2026-10-12: "How would it make sense
to add aditional effects like big cooldowns ... not add more bars", their pick C with B's icons, "Also effects like
recklessness and shield block etc"). Every one comes from what the client's own spell data says it does, never a list
by hand: a buff you put on yourself (Effect 6 APPLY_AURA on implicit target 1 CASTER) with a cooldown of 5 s or more
(SpellCooldowns; an item's on its ItemEffect), lasting a while (SpellMisc.DurationIndex -> SpellDuration) or until
used. Spells of the classes' skill lines and the runes' (Tools/heal_flight_spells.py: class_spells, by family -- the
same name -- as Frame Effects reads them, Last Stand's two spells one), the races' (a skill line named "Racial"), and
the on-use spells of equipment (ItemEffect TriggerType 0 of an item that is not a consumable: trinkets, not potions).
Left out: stealth, invisibility, forms, mounts, speed, feign death, and the shields (absorbs: the shield column's).

Each one's kind, the first that fits (its look on your character and its place when several are up):
    I immunity      an aura 39 SCHOOL_IMMUNITY on you (Divine Shield, Ice Block)
    F fortify       an aura 87 damage taken down (Shield Wall, Barkskin, Stoneform)
    L more health   an aura 34 / 133 / 230 (Last Stand)
    B block         an aura 51 MOD_BLOCK_PERCENT (Shield Block)
    E evasion       an aura 49 dodge / 47 parry (Evasion)
    O offence       any other (Recklessness, Death Wish, Arcane Power, Cold Blood, a trinket's)
Written to MelloUI_PersonalDisplay/CooldownSpells.lua: ns.Cooldowns[spell] = kind, ns.CooldownLasts[spell] = s (0:
until used).

    python Tools/personal_cooldowns.py
"""
import collections
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import heal_flight_spells as HF  # noqa: E402

ROOT = os.path.dirname(HERE)
DB2 = HF.DB2
OUT = os.path.join(ROOT, "MelloUI_PersonalDisplay", "CooldownSpells.lua")

SELF = 1
LEAVE = {16, 18, 36, 78, 31, 32, 66, 69, 97}   # stealth, invisibility, form, mounted, speed x2, feign death, absorbs
MIN_CD = 5000
ORDER = ["I", "F", "L", "B", "E", "O"]
NAMES = {"I": "immunity", "F": "fortify", "L": "more health", "B": "block", "E": "evasion", "O": "offence"}


def num(v):
    try:
        return int(float(v or 0))
    except ValueError:
        return 0


def kind_of(effects):
    """effects: (effect, aura, target0, target1, base) of a family -> its kind"""
    own = [e for e in effects if e[0] == 6 and (e[2] == SELF or e[3] == SELF)]
    auras = {e[1] for e in own}
    if 39 in auras:
        return "I"
    if any(e[1] == 87 and e[4] < 0 for e in own):
        return "F"
    if auras & {34, 133, 230}:
        return "L"
    if 51 in auras:
        return "B"
    if auras & {47, 49}:
        return "E"
    return "O"


def racial_spells():
    lines = set()
    with open(DB2 + "SkillLine.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if "Racial" in (r.get("DisplayName_lang") or ""):
                lines.add(num(r["ID"]))
    out = {}
    with open(DB2 + "SkillLineAbility.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if num(r["SkillLine"]) in lines:
                out[num(r["Spell"])] = "Racial"
    return out


def item_spells():
    """on-use spells of items that are not consumables -> their cooldown (ms)"""
    consumable = set()
    with open(DB2 + "ItemSparse.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if num(r.get("ClassID")) == 0:
                consumable.add(num(r["ID"]))
    effect_item = {}
    with open(DB2 + "ItemXItemEffect.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            effect_item[num(r["ItemEffectID"])] = num(r["ItemID"])
    out = {}
    with open(DB2 + "ItemEffect.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if num(r["TriggerType"]) != 0:
                continue
            item = effect_item.get(num(r["ID"]))
            if item is None or item in consumable:
                continue
            sid = num(r["SpellID"])
            out[sid] = max(out.get(sid, 0), num(r["CoolDownMSec"]), num(r["CategoryCoolDownMSec"]))
    return out


def main():
    full = collections.defaultdict(list)
    with open(DB2 + "SpellEffect.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if num(r.get("DifficultyID")) != 0:
                continue
            full[num(r["SpellID"])].append((num(r["Effect"]), num(r["EffectAura"]), num(r["ImplicitTarget_0"]),
                                            num(r["ImplicitTarget_1"]), float(r["EffectBasePointsF"] or 0)))
    names, cds, passive, length = HF.table_names(), HF.cooldowns(), HF.passives(), HF.durations()
    owner = dict(HF.class_spells())
    owner.update({s: c for s, c in racial_spells().items() if s not in owner})
    items = item_spells()
    for s in items:
        owner.setdefault(s, "Item")
        cds[s] = max(cds[s], items[s])
    family = collections.defaultdict(list)
    for sid, who in owner.items():
        if sid in full:
            family[(who, names.get(sid, "?"))].append(sid)
    kinds, lasts = {}, {}
    for (who, name), sids in sorted(family.items()):
        if all(s in passive for s in sids):
            continue
        effects = [e for s in sids for e in full[s]]
        own = [e for e in effects if e[0] == 6 and (e[2] == SELF or e[3] == SELF)]
        if not own or any(e[1] in LEAVE for e in own):
            continue
        if max(cds[s] for s in sids) < MIN_CD:
            continue
        last = max(length.get(s, 0) for s in sids)
        code = kind_of(effects)
        for s in sids:
            if s in passive:
                continue
            kinds[s] = code
            lasts[s] = max(0, last) / 1000
    counts = collections.Counter(kinds.values())
    lines = [
        "--------------------------------------------------------------------------------",
        "-- MelloUI - Personal Display: your big cooldowns, their kinds and how long",
        "-- each lasts, from the client's own spell data (written by",
        "-- Tools/personal_cooldowns.py: never edit by hand)",
        "--   " + ", ".join("%s %s (%d)" % (k, NAMES[k], counts.get(k, 0)) for k in ORDER),
        "--------------------------------------------------------------------------------",
        "",
        "local _, ns = ...",
        "",
        "ns.Cooldowns = {",
    ]
    ids = sorted(kinds)
    for i in range(0, len(ids), 8):
        lines.append("\t" + " ".join('[%d] = "%s",' % (sid, kinds[sid]) for sid in ids[i:i + 8]))
    lines.append("}")
    lines += ["", "-- how long each lasts (s; 0: until used)", "ns.CooldownLasts = {"]
    for i in range(0, len(ids), 8):
        lines.append("\t" + " ".join("[%d] = %g," % (sid, lasts[sid]) for sid in ids[i:i + 8]))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(OUT, len(kinds), dict(counts))
    for sid in (1719, 2565, 12292, 12042, 11129, 13877, 13750, 3045, 20572, 5277, 12328, 20230, 871, 12975, 12976,
                22812, 14177, 12043, 642, 11958, 18499, 20594, 498, 1784, 2983, 5487, 6673):
        print("  %6d %-26s %s %s" % (sid, names.get(sid, "?"), kinds.get(sid), lasts.get(sid)))


if __name__ == "__main__":
    main()
