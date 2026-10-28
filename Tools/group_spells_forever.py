"""Group Frames' spell groups (1.2.4, ported from the user's retail copy, 2026-10-27): every class's auras that belong
on party and raid frames, each in its group, from what WoW Forever's own spell data says each one does (SpellEffect
and the like), never a list by hand: one rule for the whole class of spells (memory general-rules-not-exceptions; the
pattern of Tools/heal_flight_spells.py).

Forever's class spells only (the user, 2026-10-26: nothing from other game versions):
  - every talent of Forever's Talent table, each rank (its class: its TalentTab's ClassMask);
  - the trainer spells on each class's skill lines -- a talent tab's line is the one holding most of its talents --
    up to the highest spell ID any talent uses (read from the data, never typed);
  - and the auras those lead to: itself, the spells its effects trigger (Effect 64 / 142, aura 42 / 23 / 231:
    EffectTriggerSpell), and the area auras that hand it on, which no table links: of the same name in its class
    (SpellClassOptions.SpellClassSet) or of none (Leader of the Pack's), and from a summoner, of its name less its last
    word (a totem's: Strength of Earth Totem -> Strength of Earth, cast by the totem); every one under the same cap.
    (Its other ranks are sources of their own: a same-named copy the game's own creatures cast never decides a group.)
An aura counts when the client shows it (SpellMisc Attributes_0: not 0x80 hidden; not 0x40 passive, but for an area
aura, which shows on the others it reaches: a totem's) and it lands on someone (its aura effects' implicit targets, or
an area aura). An aura with no length of its own (an area's, a totem's) lasts as long as the spell that put it there;
its cooldown is the one of the castable spell of its name (Last Stand's). Forever has no specs: a class's groups are
the class's.

The groups, in this order (the first that fits):
    lockout    a debuff on a friend (Attributes_0 0x04000000 "aura is a debuff") lasting 15 s or more that does no
               harm of its own (no damage, no control): Forbearance, Weakened Soul. The game lets a friend's debuff be picked by spell
               only when the spell is never secret (AuraContainerUtil.CanApplyIdentityCandidateFilters): the addon
               offers only those (C_Secrets.GetSpellAuraSecrecy, read in the game).
    external   damage taken down 10 % or more (aura 87), an immunity (39), more health (34 / 133), damage
    raidcd     shared (81, Forever's 562), dodge, parry or block up 25 or more (49, 47, 51) -- on one ally: external
    defensive  (Blessing of Protection, Blessing of Sacrifice); on the group or an area: raidcd; on yourself alone,
               from a spell of 30 s cooldown or more: defensive (Shield Wall, Evasion, Last Stand). An absorb (69)
               from a spell of 60 s cooldown or more counts too, on yourself from one of 30 s (Ice Barrier). (Before
               the lasting buffs: Divine Intervention lasts 3 min.)
    raidbuff   a lasting buff (2 min or more, or no end: Forever's shouts and totems last that) on an ally or the
               group that raises something (a stat, armour or a resistance, attack power, damage or healing, health,
               mana back, less threat, or an amount the server works out): Power Word: Fortitude, Blessing of Might,
               Battle Shout, Strength of Earth. (Forever's lasting buffs go on one ally at a time as often as on the
               group: both are the group's buffs.) A lasting one that only speeds them: movement; a lasting one on
               the whole group that raises nothing of those is the group's all the same (Retribution Aura).
    yours      a lasting buff on one ally that raises nothing of those: Thorns, Fear Ward.
    hot        a heal over time (aura 8) on an ally, before the lasting buffs (a totem's): Renew, Rejuvenation,
               Healing Stream.
    shield     an absorb (aura 69) on an ally: Power Word: Shield.
    power      haste, damage, crit, a stat or mana on an ally or the group, for a while: Power Infusion, Innervate
               (mana back: 24, 85, 110, 134).
    movement   faster (aura 31 / 129) or free of roots and snares (77 on mechanic 7 / 11) on an ally or the group:
               Blessing of Freedom.
    yours      anything else the client shows that you put on an ally.
A lockout a spell's own description names counts too ("Causes Forbearance for $25771d"): the server puts those on, no
table links them. A lockout that only lands on you is listed but off from the start (`off = true`).
One name, one group: the group of the castable spell's own aura, else the one most of the name's auras land in (a
tie: PRIORITY's first); every aura of that name is tracked there.
"yours", "hot", "shield" are your own groups; the rest are everyone's (a group frame shows a member's defensives
whatever their class), listed per class so a player can switch single spells off.

Read from Forever's tables as wow.export wrote them (F:/Download-Backup/Project Web/MelloUI/Workspace/GameData/WoWExport/forever_70532/db2, product wowf);
written to MelloUI_GroupFrames/GroupSpells.lua.

    python Tools/group_spells_forever.py [--report] [--check]
"""
import collections
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB2 = r"F:/Download-Backup/Project Web/MelloUI/Workspace/GameData/WoWExport/forever_70532/db2/"
BUILD = "1.60.1.70532"
OUT = os.path.join(ROOT, "MelloUI_GroupFrames", "GroupSpells.lua")

# the effects that put an aura on (APPLY_AURA, the area auras: party, raid, friend, party non-random; APPLY_AURA_2)
AURA = {6, 35, 65, 128, 174, 202, 270}
AREA_AURA = {35, 65, 128, 270}
# the spells an effect triggers: TRIGGER_SPELL, TRIGGER_SPELL_WITH_VALUE; the auras PROC_TRIGGER_SPELL,
# PERIODIC_TRIGGER_SPELL, PROC_TRIGGER_SPELL_WITH_VALUE
TRIGGER_EFFECTS = {64, 142}
TRIGGER_AURAS = {42, 23, 231}
# the friendly units an effect reaches (implicit targets): you; one ally (the target ally, the raid's member, the
# party member, your master, ally-or-raid); anyone (25: an ally only where what the aura does is help -- a heal, a
# shield, less damage, haste, speed); the group or the allies in an area (nearby ally / party, round you, round a
# place, the party, the raid, a chain of allies, a cone, a rectangle or a line of allies). The enemies' and the
# places' own targets never count.
SELF = {1}
ONE = {21, 27, 35, 57, 118}
ANY = {25}
AREA = {3, 4, 20, 30, 31, 33, 34, 37, 45, 56, 58, 59, 61, 128, 133, 136, 153}   # (153: a class's members, Greater Blessings)
# a spell that lays an area (CREATE_AREATRIGGER), summons (a totem) or works on an area of allies hands its aura on
# through a spell of its own name (a summoner: of its name less its last word)
AREA_EFFECTS = {179, 28}
SUMMON = 28
LONG = 120000                                 # a lasting buff: 2 min or more (ms)
DEBUFF = 0x04000000                           # Attributes_0: the aura is a debuff
PASSIVE, HIDDEN = 0x40, 0x80
LOCKOUT = 15000                               # a lockout lasts 15 s or more
# a lockout does nothing of its own: no aura, a dummy, an immunity to a mechanic (Forbearance's), or a modifier at 0
HARMLESS = {0, 4, 77}
HARMLESS_AT_0 = {79, 87}
# auras that only help getting about (stealth, invisibility, water breathing, water walking, slow fall, flight,
# gliding): no frame shows them
UTILITY = {16, 18, 82, 104, 105, 201, 409}
# a group buff raises something: a stat (29, 137), armour (674) or a resistance (22), attack power (99, 124, 166,
# 167), damage or healing done (13, 79, 135), health (34), mana back (MANA), haste (65, 193), crit (52, 57, 290), a
# rating (189), mounted speed (172, 211), or an amount the server works out (4, a dummy with an amount: Blessing of
# Light); or takes damage (87, 14: by an amount, Stoneskin's) or threat (10) down
MANA = {24, 85, 110, 134}
BOOST = {29, 137, 674, 22, 99, 124, 166, 167, 13, 79, 135, 34, 65, 193, 52, 57, 290, 189, 172, 211, 4} | MANA
LESS = {87, 14, 10}
SPEED = {31, 129}
SHARED = {81, 316, 562}       # damage shared or death held off (562: Forever's Blessing of Sacrifice)
AVOID = {47, 49, 51}          # parry, dodge, block
# a description's spell references ($25771d: Forbearance's length)
REF = re.compile(r"\$@?(?:spell\w*?)?(\d{2,8})[a-zA-Z]")

GROUPS = ["hot", "shield", "yours", "external", "defensive", "raidcd", "power", "movement", "raidbuff", "lockout"]
OWN = {"hot", "shield", "yours"}             # your own groups; the rest are everyone's
# a name whose auras land in several groups is kept in the one most of them land in; a tie goes to the first of
# these (what reaches others before what stays on you)
PRIORITY = ["external", "raidcd", "hot", "shield", "power", "movement", "raidbuff", "yours", "defensive", "lockout"]


def rows(table):
    with open(DB2 + table + ".csv", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def num(v):
    try:
        return int(float(v or 0))
    except ValueError:
        return 0


class Data:
    def __init__(self):
        self.names = {num(r["ID"]): r["Name_lang"] for r in rows("SpellName")}
        self.effects = collections.defaultdict(list)
        for r in rows("SpellEffect"):
            if r["DifficultyID"] != "0":
                continue
            self.effects[num(r["SpellID"])].append((
                num(r["Effect"]), num(r["EffectAura"]), float(r["EffectBasePointsF"] or 0),
                num(r["ImplicitTarget_0"]), num(r["ImplicitTarget_1"]), num(r["EffectTriggerSpell"]),
                num(r["EffectMiscValue_0"])))
        lengths = {num(r["ID"]): num(r["Duration"]) for r in rows("SpellDuration")}
        self.attr0, self.length = {}, {}
        for r in rows("SpellMisc"):
            sid = num(r["SpellID"])
            if sid in self.attr0 and r["DifficultyID"] != "0":
                continue
            self.attr0[sid] = num(r["Attributes_0"]) & 0xFFFFFFFF
            di = num(r["DurationIndex"])
            self.length[sid] = lengths.get(di, 0) if di else 0
        charge = {num(r["ID"]): num(r["ChargeRecoveryTime"]) for r in rows("SpellCategory")}
        self.cooldown = collections.defaultdict(int)
        for r in rows("SpellCooldowns"):
            sid = num(r["SpellID"])
            self.cooldown[sid] = max(self.cooldown[sid], num(r["RecoveryTime"]), num(r["CategoryRecoveryTime"]))
        for r in rows("SpellCategories"):
            sid = num(r["SpellID"])
            self.cooldown[sid] = max(self.cooldown[sid], charge.get(num(r["ChargeCategory"]), 0))
        self.family = {num(r["SpellID"]): num(r["SpellClassSet"]) for r in rows("SpellClassOptions")}
        # the spells a description names ($25771d)
        self.refs = {}
        for r in rows("Spell"):
            found = {int(x) for x in REF.findall(r["Description_lang"] or "")}
            if found:
                self.refs[num(r["ID"])] = found
        # the classes (ID -> token, class set)
        self.classes = {}
        for r in rows("ChrClasses"):
            if num(r["SpellClassSet"]):
                self.classes[num(r["ID"])] = (r["Filename"], num(r["SpellClassSet"]))
        # every talent's spells (each rank) and its class; the highest of them: the cap on every spell
        tab_class = {}
        for r in rows("TalentTab"):
            mask = num(r["ClassMask"])
            for cid in self.classes:
                if mask & (1 << (cid - 1)):
                    tab_class[num(r["ID"])] = cid
        self.talents = collections.defaultdict(set)    # class -> spells
        self.talent_tab = {}                           # spell -> tab
        for r in rows("Talent"):
            cid = tab_class.get(num(r["TabID"]))
            for i in range(9):
                sid = num(r.get("SpellRank_%d" % i))
                if cid and sid:
                    self.talents[cid].add(sid)
                    self.talent_tab[sid] = num(r["TabID"])
        self.cap = max(self.talent_tab)
        self.tab_class = tab_class
        # the area auras by name and class set (0: none), and the variants named after their source in brackets,
        # under the cap
        self.by_name = collections.defaultdict(set)
        self.variants = collections.defaultdict(set)
        for sid, name in self.names.items():
            if sid <= self.cap and any(e[0] in AREA_AURA for e in self.effects.get(sid, ())):
                fam = self.family.get(sid, 0)
                self.by_name[(fam, name)].add(sid)
                m = re.match(r"^.+ \((.+)\)$", name)
                if m:
                    self.variants[(fam, m.group(1))].add(sid)


def sources(d):
    """class id -> set of spells: its talents (each rank) and the trainer spells on its talent tabs' skill lines"""
    out = collections.defaultdict(set)
    for cid, spells in d.talents.items():
        out[cid] |= spells
    # a tab's skill line: the one holding most of its talents
    held = collections.defaultdict(collections.Counter)    # tab -> line -> talents
    abilities = list(rows("SkillLineAbility"))
    for r in abilities:
        tab = d.talent_tab.get(num(r["Spell"]))
        if tab:
            held[tab][num(r["SkillLine"])] += 1
    line_class = {}
    for tab, lines in held.items():
        line_class[lines.most_common(1)[0][0]] = d.tab_class[tab]
    for r in abilities:
        cid, sid = line_class.get(num(r["SkillLine"])), num(r["Spell"])
        if cid and 0 < sid <= d.cap:
            out[cid].add(sid)
    return out


def lays_area(d, sid):
    return any(e[0] in AREA_EFFECTS or e[0] in AREA_AURA or e[3] in AREA or e[4] in AREA for e in d.effects.get(sid, ()))


def reach(d, root, fam):
    """every spell `root` leads to (3 steps), and whether it came through an area: { spell: area }. A spell leads to
    itself, what its effects trigger, and the area auras of its name in its class or none, the ones named after it in
    brackets, and a summoner's of its name less its last word; never past the cap"""
    seen, todo = {root: False}, [(root, False, 0)]
    while todo:
        sid, area, depth = todo.pop()
        area = area or lays_area(d, sid)
        nxt = set()
        for e in d.effects.get(sid, ()):
            if e[5] and (e[0] in TRIGGER_EFFECTS or (e[0] in AURA and e[1] in TRIGGER_AURAS)):
                nxt.add(e[5])
        name = d.names.get(sid)
        if name and fam:
            names = [name]
            if " " in name and any(e[0] == SUMMON for e in d.effects.get(sid, ())):
                names.append(name.rsplit(" ", 1)[0])
            for n in names:
                for f in (fam, 0):
                    nxt |= d.variants.get((f, n), set()) | d.by_name.get((f, n), set())
        for n in nxt:
            if n <= d.cap and depth < 3 and (n not in seen or (area and not seen[n])):
                seen[n] = seen.get(n, False) or area
                todo.append((n, area, depth + 1))
    return seen


def targets(effects):
    """the aura effects' reach: 'self', 'one' (an ally), 'any' (anyone), 'area' (the group or the allies round a
    place), as a set"""
    out = set()
    for e in effects:
        if e[0] not in AURA:
            continue
        if e[0] in AREA_AURA:
            out.add("area")
        for t in (e[3], e[4]):
            if t in SELF:
                out.add("self")
            elif t in ONE:
                out.add("one")
            elif t in ANY:
                out.add("any")
            elif t in AREA:
                out.add("area")
    return out


def harmless(effects):
    return all(e[1] in HARMLESS or (e[1] in HARMLESS_AT_0 and e[2] == 0) for e in effects)


def group_of(d, sid, cooldown, area, lasts=0):
    """an aura's group, or None (`area`: it came through a spell that lays an area or reaches the group; `lasts`: the
    length of the spells that put it there, for an aura with none of its own)"""
    a0 = d.attr0.get(sid)
    if a0 is None or a0 & HIDDEN:
        return None
    effects = [e for e in d.effects.get(sid, ()) if e[0] in AURA]
    if not effects or (a0 & PASSIVE and not any(e[0] in AREA_AURA for e in effects)):
        return None
    reach_ = targets(effects)
    if area and reach_ & {"one", "any", "area"}:
        reach_ = (reach_ - {"one", "any"}) | {"area"}
    length = d.length.get(sid, 0) or lasts
    auras = lambda pred: any(pred(e) for e in effects)   # noqa: E731
    if a0 & DEBUFF:
        if (length >= LOCKOUT or length < 0) and harmless(effects):
            return "lockout"
        return None
    sure = reach_ & {"one", "area"}             # surely an ally
    helps = reach_ & {"one", "any", "area"}     # an ally where what it does is help
    mitigation = auras(lambda e: (e[1] in (87, 229) and e[2] <= -10) or e[1] == 39 or e[1] in SHARED
                       or (e[1] in (34, 133, 230) and e[2] >= 0) or (e[1] == 186 and e[2] <= -100)
                       or (e[1] in AVOID and e[2] >= 25))
    absorb = auras(lambda e: e[1] == 69)
    big_absorb = absorb and (cooldown >= 60000 and bool(helps) or cooldown >= 30000 and "self" in reach_)
    if mitigation or big_absorb:
        if "area" in reach_:
            return "raidcd"
        if helps:
            return "external"
        return "defensive" if "self" in reach_ and cooldown >= 30000 else None
    if helps and auras(lambda e: e[1] == 8):
        return "hot"
    long_ = length >= LONG or length < 0
    if long_:
        if not sure or all(e[1] in UTILITY for e in effects):
            return None
        if auras(lambda e: e[1] in BOOST and e[2] > 0 or e[1] in LESS and e[2] < 0):
            return "raidbuff"
        if auras(lambda e: e[1] in SPEED and e[2] > 0):
            return "movement"
        return "raidbuff" if "area" in reach_ else "yours"
    if not helps:
        return None
    if auras(lambda e: e[1] == 69):
        return "shield"
    if auras(lambda e: (e[1] in (193, 65, 79, 290, 52, 57, 189, 137) or e[1] in MANA) and e[2] > 0 or e[1] == 21):
        return "power"
    if auras(lambda e: (e[1] in SPEED and e[2] > 0) or (e[1] == 77 and e[6] in (7, 11))):
        return "movement"
    if not sure or all(e[1] in UTILITY for e in effects):
        return None
    return "yours"


def build(d):
    """class token -> group -> [ entry ]; an entry: { 'main', 'ids', 'name', 'off' }"""
    srcs = sources(d)
    out = collections.defaultdict(lambda: collections.defaultdict(dict))
    for cid, spells in srcs.items():
        token, fam = d.classes[cid]
        found = {}   # aura -> [cooldown, roots, area, lockout put on others]
        name_cd = collections.defaultdict(int)   # a castable spell's cooldown by its name (an aura of it: Last Stand)
        for root in spells:
            name_cd[d.names.get(root)] = max(name_cd[d.names.get(root)], d.cooldown.get(root, 0))
        for root in spells:
            cd = d.cooldown.get(root, 0)
            reached = reach(d, root, fam)
            for sid, area in reached.items():
                if d.family.get(sid, fam) not in (fam, 0) or sid not in d.names:
                    continue
                f = found.setdefault(sid, [0, set(), False, None])
                f[0] = max(f[0], cd)
                f[1].add(root)
                f[2] = f[2] or area
            # a lockout its description names (Blessing of Protection: "Causes Forbearance for $25771d"), on from
            # the start where the spell puts it on others
            others = any(targets([e for e in d.effects.get(s, ()) if e[0] in AURA]) & {"one", "any", "area"}
                         or (area and s != root) for s, area in reached.items())
            for ref in (r for s in reached for r in d.refs.get(s, ())):
                a0, length = d.attr0.get(ref, 0), d.length.get(ref, 0)
                effects = [e for e in d.effects.get(ref, ()) if e[0] in AURA]
                if (ref in d.names and ref <= d.cap and a0 & DEBUFF and not a0 & (PASSIVE | HIDDEN)
                        and length >= LOCKOUT and effects and harmless(effects)):
                    f = found.setdefault(ref, [0, set(), False, None])
                    f[3] = bool(f[3]) or others
        landed = collections.defaultdict(dict)   # name -> group -> entry
        for sid, (cd, roots, area, lockout) in found.items():
            # (no length of its own: as long as the spells that put it there; one of no end, no end)
            spans = [d.length.get(r, 0) for r in roots]
            lasts = -1 if any(x < 0 for x in spans) else max(spans, default=0)
            cd = max(cd, name_cd.get(d.names.get(sid), 0))
            g = "lockout" if lockout is not None else group_of(d, sid, cd, area, lasts)
            if not g:
                continue
            name = d.names[sid]
            entry = landed[name].setdefault(g, {"ids": set(), "roots": set(), "name": name, "on": False})
            entry["ids"].add(sid)
            entry["roots"] |= {r for r in roots if d.names.get(r) == name}
            # a lockout of your own listed but off from the start
            entry["on"] = entry["on"] or g != "lockout" or bool(lockout) or bool(
                targets([e for e in d.effects.get(sid, ()) if e[0] in AURA]) & {"one", "area"})
        # a name in one group: its castable spell's own aura's, else the one most of its auras land in (a tie: the
        # first of PRIORITY)
        for name, groups in landed.items():
            own = {k for k, e in groups.items() if e["roots"] & e["ids"]}
            pool = own or set(groups)
            g = min(pool, key=lambda k: (-len(groups[k]["ids"]), PRIORITY.index(k)))
            entry = groups[g]
            for other in groups.values():
                entry["ids"] |= other["ids"]
                entry["roots"] |= other["roots"]
                entry["on"] = entry["on"] or other["on"]
            out[token][g][name] = entry
    # one entry a name: its picture and tooltip from the castable spell of that name, else its lowest aura
    final = {}
    for token, groups in out.items():
        final[token] = {}
        for g, entries in groups.items():
            lst = []
            for name, e in sorted(entries.items(), key=lambda kv: min(kv[1]["ids"])):
                main = min(e["roots"]) if e["roots"] else min(e["ids"])
                lst.append({"main": main, "ids": sorted(e["ids"]), "name": name, "off": not e["on"]})
            final[token][g] = lst
    return final


def lua(d, data):
    counts = collections.Counter()
    for token, groups in data.items():
        for g, lst in groups.items():
            counts[g] += len(lst)
    lines = [
        "--------------------------------------------------------------------------------",
        "-- MelloUI - Group Frames: the spell groups' data (WoW Forever %s), every" % BUILD,
        "-- class's auras that belong on party and raid frames in their groups, from the",
        "-- client's own spell data (written by Tools/group_spells_forever.py: never edit",
        "-- by hand).",
        "--   " + ", ".join("%s %d" % (g, counts[g]) for g in GROUPS),
        "-- ns.GroupSpells[class][group] = { { main, id, id, ... }, ... }: main the spell",
        "-- its name and picture come from, the IDs every aura of that name in that group",
        "-- (includeSpellIDs); off = true: listed but off from the start (a lockout that",
        "-- only lands on you)",
        "--------------------------------------------------------------------------------",
        "",
        "local _, ns = ...",
        "",
        "ns.GroupSpells = {",
        "\tbuild = \"%s\"," % BUILD,
    ]
    for token in sorted(data):
        lines.append("\t%s = {" % token)
        for g in GROUPS:
            lst = data[token].get(g)
            if not lst:
                continue
            lines.append("\t\t%s = {" % g)
            for e in lst:
                lines.append("\t\t\t{ %d, %s%s },   -- %s" % (
                    e["main"], ", ".join(str(i) for i in e["ids"]), ", off = true" if e["off"] else "",
                    e["name"].replace("\n", " ")))
            lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n", counts


def report(data):
    for token in sorted(data):
        print("==", token)
        for g in GROUPS:
            lst = data[token].get(g)
            if lst:
                print("  %-9s %s" % (g, "; ".join("%s%s" % (e["name"], " (off)" if e["off"] else "") for e in lst)))


def main():
    d = Data()
    data = build(d)
    text, counts = lua(d, data)
    if "--check" in sys.argv:
        # (the suite's: the data file as this tool writes it from the tables; nothing written)
        with open(OUT, encoding="utf-8", newline="") as f:
            same = f.read() == text
        print(OUT, "matches" if same else "DIFFERS: run python Tools/group_spells_forever.py")
        return 0 if same else 1
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(OUT, dict(counts), "cap", d.cap)
    if "--report" in sys.argv:
        report(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
