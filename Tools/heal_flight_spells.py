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
in that order (a spell that heals and leaves a heal over time, Regrowth, is a heal). A class spell with none of
these takes its family's kind (the class's spells of its name: every rank, and the heal the game triggers from it --
Holy Nova, Prayer of Mending). Only what is put on an ally
counts (implicit targets 21 TARGET_ALLY, 25 TARGET_ANY, 57 TARGET_RAID, or the group's): a spell on yourself alone
(a potion, Divine Shield, Ice Block) is none. Read from the client's tables as wow.export wrote them
(F:/Download-Backup/Project Web/MelloUI/Workspace/GameData/WoWExport/db2/SpellEffect.csv); written to MelloUI_FrameEffects/HealFlightSpells.lua.

A heal over time's ticks (the user, 2026-10-09: "Heal over Time Ticks effect"): every spell that puts an aura 8
PERIODIC_HEAL on an ally (Renew, Rejuvenation, Regrowth's own) gets its tick period (SpellEffect.EffectAuraPeriod)
and its length (SpellMisc.DurationIndex -> SpellDuration.Duration, exported from the client 2026-10-09).

Buff Landings (1.2.4; the user, 2026-10-30: "the animation for power word Fortitude is not happening", then the picks
of the buff landings sketch): Forever's class buffs by one rule (buffs(), below), written as ns.BuffForms (one, group,
class, self) and ns.BuffSchools (the family's school) into HealFlightSpells.lua.

    python Tools/heal_flight_spells.py            write the tables
    python Tools/heal_flight_spells.py --check    exit 1 unless both files are what the client's data gives
"""
import collections
import csv
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB2 = r"F:/Download-Backup/Project Web/MelloUI/Workspace/GameData/WoWExport/db2/"
# (Forever's own client export, 1.60.1.70532: its Talent and TalentTab tables -- the 70338 export above has none; the
# buff rule reads every table there but the item tables, which only the 70338 export has)
DB2_FOREVER = r"F:/Download-Backup/Project Web/MelloUI/Workspace/GameData/WoWExport/forever_70532/db2/"
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


# Buff Landings (1.2.4; an-04's census, BuildData/output/buff_landings_sketch/buff_census.py, the same rule):
#   the pool   Forever's own player spells only: a class skill line's trainer spells (SkillLineAbility on the class
#              lines, spell IDs under 30000) and Forever's Talent table (its ranks' spells, the class from
#              TalentTab.ClassMask); a class spell that makes an item (Effect 24 CREATE_ITEM) brings the item's use
#              spell (ItemXItemEffect, ItemEffect: the Soulstone)
#   a buff     an active spell (SpellMisc Attributes_0 0x40 passive: none) putting an aura (Effect 6 APPLY_AURA, 35 / 65
#              the area auras) on an ally or the group, lasting 60 s or more, an aura the game does not call a debuff
#              (Attributes_0 0x04000000: Hunter's Mark, Mind Vision), and not one of Heal Flight's kinds (kind())
#   its form   o one ally (implicit targets 21, 25, 57); g the group (56 the raid round the caster, 20 / 30 / 31 / 33 /
#              61 / 132 the party, an area aura on the caster); c a Greater Blessing (153: the target's class in the
#              raid); s on the caster alone (target 1), lasting 10 min or more (the armors, Inner Fire: they land on
#              nothing -- the user's pick, "Self-only buffs: Nothing")
#   its school the family's (a class's spells of one name, and a single form with the group form of the same aura --
#              Power Word: Fortitude and Prayer of Fortitude): SpellMisc.SchoolMask, the most common of its members
BUFF_ALLY = {21, 25, 57}
BUFF_GROUP = {56, 153, 20, 30, 31, 33, 61, 132}
BUFF_CASTER = {1}
BUFF_AURAS = {6, 35, 65}
BUFF_AREA = {35, 65}
BUFF_LONG = 60000        # ms: a buff lasts a minute or more (a cooldown's boon -- Power Infusion, Innervate -- does not)
BUFF_SELF_LONG = 600000  # ms: a self-only buff ten minutes or more (not a minute's trick: Levitate, Ice Barrier)
BUFF_DEBUFF = 0x04000000
TRAINER_MAX = 30000
SCHOOL = {1: "physical", 2: "holy", 4: "fire", 8: "nature", 16: "frost", 32: "shadow", 64: "arcane"}
BUFF_CODES = [("o", "one"), ("g", "group"), ("c", "class"), ("s", "self")]


def rows(db2, table):
    with open(db2 + table + ".csv", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def num(v):
    try:
        return int(float(v or 0))
    except ValueError:
        return 0


def buff_spells():
    """every buff of the rule: { id, name, class, form ("one", "group", "class", "self"), last (ms), school, auras }"""
    db2 = DB2_FOREVER
    line_class = {sl: c for c, lines in CLASS_LINES.items() for sl in lines}
    cls_of = {}
    for r in rows(db2, "SkillLineAbility"):
        sid, sl = num(r["Spell"]), num(r["SkillLine"])
        if sl in line_class and sid < TRAINER_MAX:
            cls_of[sid] = line_class[sl]
    tab_class = {num(r["ID"]): CLASS_MASK.get(num(r["ClassMask"])) for r in rows(db2, "TalentTab")}
    for r in rows(db2, "Talent"):
        cls = tab_class.get(num(r["TabID"]))
        if cls:
            for i in range(9):
                sid = num(r["SpellRank_%d" % i])
                if sid:
                    cls_of.setdefault(sid, cls)
    makes = collections.defaultdict(set)
    for r in rows(db2, "SpellEffect"):
        sid = num(r["SpellID"])
        if sid in cls_of and r["Effect"] == "24" and num(r["EffectItemType"]):
            makes[num(r["EffectItemType"])].add(sid)
    effect_spell = {num(r["ID"]): num(r["SpellID"]) for r in rows(DB2, "ItemEffect")}
    for r in rows(DB2, "ItemXItemEffect"):
        item = num(r["ItemID"])
        use = effect_spell.get(num(r["ItemEffectID"]))
        if item in makes and use and use not in cls_of:
            cls_of[use] = cls_of[min(makes[item])]
    names = {num(r["ID"]): r["Name_lang"] for r in rows(db2, "SpellName")}
    lengths = {num(r["ID"]): num(r["Duration"]) for r in rows(db2, "SpellDuration")}
    misc = {}
    for r in rows(db2, "SpellMisc"):
        sid = num(r["SpellID"])
        if sid in misc and r["DifficultyID"] != "0":
            continue
        a0 = num(r["Attributes_0"])
        misc[sid] = (bool(a0 & 0x40), bool(a0 & BUFF_DEBUFF), lengths.get(num(r["DurationIndex"]), 0),
                     num(r["SchoolMask"]))
    effects = collections.defaultdict(list)
    for r in rows(db2, "SpellEffect"):
        sid = num(r["SpellID"])
        if sid in cls_of and r["DifficultyID"] == "0":
            effects[sid].append((num(r["Effect"]), num(r["EffectAura"]), num(r["ImplicitTarget_0"]),
                                 num(r["ImplicitTarget_1"]), num(r["EffectMiscValue_0"])))
    out = []
    for sid, cls in cls_of.items():
        m, eff = misc.get(sid), effects.get(sid)
        if not m or not eff or m[0] or m[1] or kind(eff):
            continue
        auras = [e for e in eff if e[0] in BUFF_AURAS and e[1]]
        if not auras:
            continue
        on = lambda e, t: e[2] in t or e[3] in t   # noqa: E731
        if any(on(e, {153}) for e in auras):
            form = "class"
        elif any(on(e, BUFF_GROUP) or (e[0] in BUFF_AREA and on(e, BUFF_CASTER)) for e in auras):
            form = "group"
        elif any(on(e, BUFF_ALLY) for e in auras):
            form = "one"
        elif all(on(e, BUFF_CASTER) for e in auras):
            form = "self"
        else:
            continue   # (on an enemy: not a help)
        if m[2] < (BUFF_SELF_LONG if form == "self" else BUFF_LONG):
            continue
        out.append({"id": sid, "name": names.get(sid, "?"), "class": cls, "form": form,
                    "school": SCHOOL.get(m[3], "mixed"), "auras": {(e[1], e[4]) for e in auras}})
    return out


def buff_families(spells):
    """{ spell: its family's school }: a class's spells of one name, then a single form and a group form of one aura"""
    side = {"one": "single", "group": "group", "class": "group", "self": "self"}
    by_name = collections.defaultdict(list)
    for s in spells:
        by_name[(s["class"], s["name"])].append(s)
    fams = []
    for (cls, _), ms in sorted(by_name.items(), key=lambda kv: min(m["id"] for m in kv[1])):
        sig = set().union(*(m["auras"] for m in ms))
        sides = {side[m["form"]] for m in ms}
        hit = next((f for f in fams if f["class"] == cls and f["sig"] & sig and f["sides"] | sides == {"single", "group"}
                    and not (f["sides"] & sides)), None)
        if hit:
            hit["members"] += ms
            hit["sig"] |= sig
            hit["sides"] |= sides
        else:
            fams.append({"class": cls, "members": list(ms), "sig": sig, "sides": sides})
    school = {}
    for f in fams:
        # (the most common of its members', the single form's first on a tie: Prayer of Shadow Protection is holy in
        # the data, Shadow Protection shadow)
        ms = sorted(f["members"], key=lambda m: (side[m["form"]] == "group", m["id"]))
        pick = collections.Counter(m["school"] for m in ms).most_common(1)[0][0]
        for m in ms:
            school[m["id"]] = pick
    return school, len(fams)


def buffs_text():
    spells = buff_spells()
    school, families = buff_families(spells)
    form = {s["id"]: dict((n, c) for c, n in BUFF_CODES)[s["form"]] for s in spells}
    counts = collections.Counter(form.values())
    schools = collections.Counter(school[s] for s in form if form[s] != "s")
    lines = [
        "",
        "-- Buff Landings (1.2.4): Forever's class buffs by the rule in Tools/heal_flight_spells.py (%d spells, %d" % (
            len(form), families),
        "-- families): each buff's form -- " + ", ".join("%s %s (%d)" % (c, n, counts.get(c, 0)) for c, n in BUFF_CODES),
        "ns.BuffForms = {",
    ]
    ids = sorted(form)
    for i in range(0, len(ids), 8):
        lines.append("\t" + " ".join('[%d] = "%s",' % (sid, form[sid]) for sid in ids[i:i + 8]))
    lines.append("}")
    lines += ["", "-- each buff's family's school (SpellMisc.SchoolMask): the look it lands in -- "
              + ", ".join("%s (%d)" % (s, n) for s, n in sorted(schools.items())) + " cast on others",
              "ns.BuffSchools = {"]
    for i in range(0, len(ids), 6):
        lines.append("\t" + " ".join('[%d] = "%s",' % (sid, school[sid]) for sid in ids[i:i + 6]))
    lines.append("}")
    return lines, len(form), dict(counts)


def main():
    check = "--check" in sys.argv[1:]
    bad = [a for a in sys.argv[1:] if a != "--check"]
    if bad:
        print("unknown argument: %s (nothing written)" % " ".join(bad))
        print(__doc__[__doc__.index("    python Tools/"):].rstrip())
        return 2
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
    names, cls_of, passive = table_names(), class_spells(), passives()
    # every rank and every part of one spell (the user, 2026-11-03: "those animations should ignore the rank of the
    # spell", after Holy Nova and Prayer of Mending showed nothing): a class's active spell with no kind of its own
    # takes its family's -- the class's spells of the same name: its other ranks, and the heal the game triggers from
    # it (Holy Nova's cast only harms; its heal is a Priest's Holy Nova of its own) -- the first by CODES' order. An
    # NPC's spell of the same name never counts (Barkskin, Consecration, Mana Shield keep none).
    order = [c for c, _ in CODES]
    ranks = collections.defaultdict(set)
    for sid, cls in cls_of.items():
        ranks[(cls, names.get(sid, "?"))].add(sid)
    for sids in ranks.values():
        have = sorted({kinds[s] for s in sids if s in kinds}, key=order.index)
        for s in sids:
            if have and s not in kinds and s in spells and s not in passive:
                kinds[s] = have[0]
    # the tanks' tools and defensives, by family
    cds, length = cooldowns(), durations()
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
    buff_lines, nbuffs, bcounts = buffs_text()
    lines += buff_lines
    texts = [(OUT, "\n".join(lines) + "\n")]
    print(OUT, len(kinds), dict(counts), len(ticks), "with ticks;", nbuffs, "buffs", bcounts)

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
    texts.append((EFFECTS_OUT, "\n".join(lines) + "\n"))
    print(EFFECTS_OUT, len(effect_kinds), dict(ecounts), len(lasts), "lasting")
    stale = []
    for path, text in texts:
        if check:
            try:
                with open(path, encoding="utf-8", newline="") as f:
                    if f.read() != text:
                        stale.append(path)
            except OSError:
                stale.append(path)
            continue
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    if check:
        for path in stale:
            print("stale:", os.path.normpath(path))
        print("ok" if not stale else "STALE")
        return 1 if stale else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
