"""Heal Flight's spell kinds (docs/plans/heal-flight.md; the user, 2026-10-09: each kind lands its own way, buffs
nothing). Every spell's kind comes from what the client's own spell data says it does (SpellEffect), never a list by
hand: one rule for the whole class of spells.

    resurrection  Effect 18 RESURRECT / 113 RESURRECT_NEW / 329 (this client's resurrections: Resurrection,
                  Redemption, Rebirth, Ancestral Spirit, Revive)
    big heal      Effect 67 HEAL_MAX_HEALTH (Lay on Hands)
    protection    an aura 39 SCHOOL_IMMUNITY put on an ally (Blessing / Hand of Protection, Divine Intervention)
    shield        an aura 69 SCHOOL_ABSORB put on an ally (Power Word: Shield)
    chain heal    Effect 10 HEAL on implicit target 45 (the chain heal's ally chain)
    group heal    Effect 10 HEAL on a party or area of allies (implicit targets 20, 30, 31, 33, 56, 61, 132)
    heal          Effect 10 HEAL on one ally
    heal over time  an aura 8 PERIODIC_HEAL put on an ally (Renew, Rejuvenation)
in that order (a spell that heals and leaves a heal over time, Regrowth, is a heal). Only what is put on an ally
counts (implicit targets 21 TARGET_ALLY, 25 TARGET_ANY, 57 TARGET_RAID, or the group's): a spell on yourself alone
(a potion, Divine Shield, Ice Block) is none. Read from the client's tables as wow.export wrote them
(F:/Download-Backup/WoWExport/db2/SpellEffect.csv); written to MelloUI_FrameEffects/HealFlightSpells.lua.

A heal over time's ticks (the user, 2026-10-09: "Heal over Time Ticks effect"): every spell that puts an aura 8
PERIODIC_HEAL on an ally (Renew, Rejuvenation, Regrowth's own) gets its tick period (SpellEffect.EffectAuraPeriod)
and its length (SpellMisc.DurationIndex -> SpellDuration.Duration, exported from the client 2026-10-09).

    python Tools/heal_flight_spells.py
"""
import collections
import csv
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB2 = r"F:/Download-Backup/WoWExport/db2/"
SOURCE = DB2 + "SpellEffect.csv"
OUT = os.path.join(ROOT, "MelloUI_FrameEffects", "HealFlightSpells.lua")
EFFECTS_OUT = os.path.join(ROOT, "MelloUI_FrameEffects", "FrameEffectsSpells.lua")

ALLY = {21, 25, 57}
GROUP = {20, 30, 31, 33, 56, 61, 132}
CHAIN = {45}
# the kinds' one-letter codes in the Lua table (HealFlight.lua: KINDS)
CODES = [("r", "resurrection"), ("b", "big heal"), ("p", "protection"), ("s", "shield"), ("c", "chain heal"),
         ("g", "group heal"), ("h", "heal"), ("o", "heal over time")]
EFFECT_CODES = [("W", "roar"), ("U", "taunt"), ("F", "fortify"), ("L", "more health"), ("I", "immunity"),
                ("E", "evasion")]


def kind(effects):
    """effects: (effect, aura, target0, target1) per effect of one spell -> its code, or None"""
    def on(targets, e):
        return e[2] in targets or e[3] in targets
    has = lambda pred: any(pred(e) for e in effects)   # noqa: E731
    if has(lambda e: e[0] in (18, 113, 329)):
        return "r"
    if has(lambda e: e[0] == 67 and on(ALLY, e)):
        return "b"
    if has(lambda e: e[0] == 6 and e[1] == 39 and on(ALLY, e)):
        return "p"
    if has(lambda e: e[0] == 6 and e[1] == 69 and on(ALLY, e)):
        return "s"
    if has(lambda e: e[0] == 10 and on(CHAIN, e)):
        return "c"
    if has(lambda e: e[0] == 10 and on(GROUP, e)):
        return "g"
    if has(lambda e: e[0] == 10 and on(ALLY, e)):
        return "h"
    if has(lambda e: e[0] == 6 and e[1] == 8 and on(ALLY, e)):
        return "o"
    return None


def durations():
    """spell -> its length in ms (its DurationIndex's, difficulty 0 first)"""
    length = {}
    with open(DB2 + "SpellDuration.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            length[int(r["ID"])] = int(r["Duration"])
    out = {}
    with open(DB2 + "SpellMisc.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            sid, diff = int(r["SpellID"]), int(r["DifficultyID"])
            if sid in out and diff != 0:
                continue
            out[sid] = length.get(int(r["DurationIndex"]), 0)
    return out


# Tanks' tools and defensives (the user, 2026-10-09: "Last Stand, Shield Wall, Aoe Taunt ... a roar effect"; for the
# Frame Effects, a feature of its own): a class's ACTIVE spell (SkillLineAbility; SpellMisc Attributes_0 0x40 = passive) judged by its
# family -- the same name in the same class: Last Stand's button triggers the spell that holds its aura -- with a
# cooldown of 30 s or more (SpellCooldowns), a taunt whatever its cooldown:
#   W roar         an aura 11 MOD_TAUNT on the enemies round you (Challenging Shout, Challenging Roar)
#   U taunt        Effect 114 ATTACK_ME, or an aura 11 on one enemy (Taunt, Growl, Mocking Blow)
#   I immunity     an aura 39 SCHOOL_IMMUNITY on yourself (Divine Shield, Ice Block)
#   F fortify      an aura 87 MOD_DAMAGE_PERCENT_TAKEN below 0 on yourself (Shield Wall, Barkskin)
#   L last stand   an aura 230 / 34 / 133 (more health) on yourself (Last Stand, Vengeance)
#   E evasion      an aura 49 / 47 (dodge, parry) on yourself (Evasion, Deterrence)
# Their effect lasts the family's aura (ns.EffectLasts, s). Written to MelloUI_FrameEffects/FrameEffectsSpells.lua. The class of a skill line: the game's class skill lines
# (SkillLine CategoryID 7), and the runes' (Engraving, Runes) by SkillLineAbility.ClassMask.
CLASS_LINES = {
    "Warrior": {26, 256, 257}, "Paladin": {594, 267, 184}, "Hunter": {50, 163, 51}, "Rogue": {253, 38, 39},
    "Priest": {613, 56, 78}, "Shaman": {375, 373, 374}, "Mage": {237, 8, 6}, "Warlock": {355, 354, 593},
    "Druid": {574, 134, 573},
}
CLASS_MASK = {1: "Warrior", 2: "Paladin", 4: "Hunter", 8: "Rogue", 16: "Priest", 64: "Shaman", 128: "Mage",
              256: "Warlock", 1024: "Druid"}
RUNE_LINES = {2851, 2853}
AREA_ENEMY = {15, 22, 8, 16, 31, 30}
SELF = {1}
COOLDOWN_ORDER = ["W", "U", "F", "L", "I", "E"]


def cooldown_kind(effects):
    """effects: (effect, aura, target0, target1, base points) -> its code, or None"""
    aura = lambda a, t: any(e[0] == 6 and e[1] == a and (e[2] in t or e[3] in t) for e in effects)   # noqa: E731
    if aura(11, AREA_ENEMY):
        return "W"
    if any(e[0] == 114 for e in effects) or aura(11, {6}):
        return "U"
    if aura(39, SELF):
        return "I"
    if any(e[0] == 6 and e[1] == 87 and e[2] in SELF and e[4] < 0 for e in effects):
        return "F"
    if aura(230, SELF) or aura(34, SELF) or aura(133, SELF):
        return "L"
    if aura(49, SELF) or aura(47, SELF):
        return "E"
    return None


def class_spells():
    line_class = {sl: c for c, lines in CLASS_LINES.items() for sl in lines}
    out = {}
    with open(DB2 + "SkillLineAbility.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            sid, sl, mask = int(r["Spell"]), int(r["SkillLine"]), int(r["ClassMask"] or 0)
            cls = line_class.get(sl) or (CLASS_MASK.get(mask) if sl in RUNE_LINES else None)
            if cls:
                out[sid] = cls
    return out


def table_names():
    out = {}
    with open(DB2 + "SpellName.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            out[int(r["ID"])] = r["Name_lang"]
    return out


def cooldowns():
    out = collections.defaultdict(int)
    with open(DB2 + "SpellCooldowns.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            sid = int(r["SpellID"])
            out[sid] = max(out[sid], int(r["RecoveryTime"] or 0), int(r["CategoryRecoveryTime"] or 0))
    return out


def passives():
    out = set()
    with open(DB2 + "SpellMisc.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if int(r["Attributes_0"] or 0) & 0x40:
                out.add(int(r["SpellID"]))
    return out


def main():
    spells = collections.defaultdict(list)
    full = collections.defaultdict(list)
    periods = {}
    with open(SOURCE, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            e = (int(r["Effect"]), int(r["EffectAura"]), int(r["ImplicitTarget_0"]), int(r["ImplicitTarget_1"]))
            spells[int(r["SpellID"])].append(e)
            full[int(r["SpellID"])].append(e + (float(r["EffectBasePointsF"] or 0),))
            if e[0] == 6 and e[1] == 8 and (e[2] in ALLY or e[3] in ALLY or e[2] in GROUP):
                periods[int(r["SpellID"])] = int(r["EffectAuraPeriod"] or 0)
    kinds = {}
    for sid, effects in spells.items():
        k = kind(effects)
        if k:
            kinds[sid] = k
    # the tanks' tools and defensives, by family
    names, cls_of, cds, passive, length = table_names(), class_spells(), cooldowns(), passives(), durations()
    family = collections.defaultdict(list)
    for sid, cls in cls_of.items():
        if sid in full:
            family[(cls, names.get(sid, "?"))].append(sid)
    lasts, effect_kinds, examples = {}, {}, []
    for (cls, name), sids in sorted(family.items()):
        if all(s in passive for s in sids) or any(s in kinds for s in sids):
            continue
        codes = sorted({cooldown_kind(full[s]) for s in sids} - {None})
        if not codes:
            continue
        code = codes[0]
        cd = max(cds[s] for s in sids)
        if code not in ("W", "U") and cd < 30000:
            continue
        last = max(length.get(s, 0) for s in sids) / 1000
        castable = sorted(s for s in sids if cds[s] > 0 and s not in passive) or sorted(s for s in sids if s not in passive)
        for s in sids:
            effect_kinds[s] = code
            if last > 0:
                lasts[s] = last
        examples.append((COOLDOWN_ORDER.index(code), min(sids), cls, name, castable[0], code))
    counts = collections.Counter(kinds.values())
    lines = [
        "--------------------------------------------------------------------------------",
        "-- MelloUI - Heal Flight: each helpful spell's kind, from the client's own",
        "-- spell data (written by Tools/heal_flight_spells.py: never edit by hand)",
        "--   " + ", ".join("%s %s (%d)" % (c, n, counts.get(c, 0)) for c, n in CODES),
        "--------------------------------------------------------------------------------",
        "",
        "local _, ns = ...",
        "",
        "ns.SpellKinds = {",
    ]
    ids = sorted(kinds)
    for i in range(0, len(ids), 8):
        lines.append("\t" + " ".join('[%d] = "%s",' % (sid, kinds[sid]) for sid in ids[i:i + 8]))
    lines.append("}")
    # the ticks: period and length in seconds, for a heal over time of a known kind
    ticks = {sid: (periods[sid], length.get(sid, 0)) for sid in periods
             if sid in kinds and periods[sid] > 0 and length.get(sid, 0) >= periods[sid]}
    lines += ["", "-- a heal over time's ticks: { period, length } in seconds (SpellEffect, SpellMisc, SpellDuration)",
              "ns.SpellTicks = {"]
    ids = sorted(ticks)
    for i in range(0, len(ids), 6):
        lines.append("\t" + " ".join("[%d] = { %g, %g }," % (sid, ticks[sid][0] / 1000, ticks[sid][1] / 1000)
                                     for sid in ids[i:i + 6]))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(OUT, len(kinds), dict(counts), len(ticks), "with ticks")

    # Frame Effects' own table (the user, 2026-10-09: a feature of its own): the tanks' tools and defensives
    ecounts = collections.Counter(effect_kinds.values())
    lines = [
        "--------------------------------------------------------------------------------",
        "-- MelloUI - Frame Effects: the tanks' tools and defensives, their kinds and",
        "-- how long each lasts, from the client's own spell data (written by",
        "-- Tools/heal_flight_spells.py: never edit by hand)",
        "--   " + ", ".join("%s %s (%d)" % (c, n, ecounts.get(c, 0)) for c, n in EFFECT_CODES),
        "--------------------------------------------------------------------------------",
        "",
        "local _, ns = ...",
        "",
        "ns.EffectKinds = {",
    ]
    ids = sorted(effect_kinds)
    for i in range(0, len(ids), 8):
        lines.append("\t" + " ".join('[%d] = "%s",' % (sid, effect_kinds[sid]) for sid in ids[i:i + 8]))
    lines.append("}")
    lines += ["", "-- how long each lasts (s): its family's aura (SpellMisc, SpellDuration)", "ns.EffectLasts = {"]
    ids = sorted(lasts)
    for i in range(0, len(ids), 8):
        lines.append("\t" + " ".join("[%d] = %g," % (sid, lasts[sid]) for sid in ids[i:i + 8]))
    lines.append("}")
    lines += ["", "-- one spell a kind for the Every Effect preview: its class's oldest (the lowest spell ID)",
              "-- { kind, class, name, spell }", "ns.EffectExamples = {"]
    seen = set()
    for _, _, cls, name, sid, code in sorted(examples):
        if code not in seen:
            seen.add(code)
            lines.append('\t{ "%s", "%s", "%s", %d },' % (code, cls, name.replace('"', '\\"'), sid))
    lines.append("}")
    with open(EFFECTS_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(EFFECTS_OUT, len(effect_kinds), dict(ecounts), len(lasts), "lasting")


if __name__ == "__main__":
    main()
