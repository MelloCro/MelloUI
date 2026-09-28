"""The frozen NPC -> voice map of the v2 pack (SPEC.md 4.2-4.3) and the voice settings the exporter needs.

    load_voices()            Tools/voice_v2/voices.json when it exists (the Voices agent owns it), else the
                             spec's initial table (4.1 / 4.3) built in here. Returns (voices dict, source label).
    resolve_identity(...)    identity -> voice key: the identities table, then the spec's creature rows
                             (race pools by crc32 of the NPC ID, creature families, the narrator for the rest)
    NpcVoiceMap              npc_voices.csv: built ONCE from the research draft (npc_voice_map.csv), then only
                             appended to: a missing NPC gets its voice by the same rule (REPORT.md section 3),
                             and a row is never changed.

The rule for a new NPC (a port of the research's voice_rule.py):
  1. display list: the Forever client's creature cache, else cmangos ModelId1-4, else the Forever client's
     Creature table, else the cached Wowhead NPC page
  2. main display: the highest weight, ties -> the first listed
  3. its NPCSounds greeting set (vendor rows merged into the same recording set) when it is speech;
     else a set of another display of the same race and sex; else crc32(entry) over the race/sex pool;
     else the non-character model: "creature:<MelloUI race key>" or "creature:model:<model name>"
"""
from __future__ import annotations

import collections
import csv
import datetime
import json
import os
import re
import sys
import zlib

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sources as S  # noqa: E402

VOICES_JSON = os.path.join(HERE, "voices.json")
NPC_VOICES_CSV = os.path.join(HERE, "npc_voices.csv")
CSV_COLUMNS = ["npc", "name", "voice", "identity", "reason", "source", "assigned"]

# ---------------------------------------------------------------------------------------------- the spec's table
LIBRARY_GENERIC = [
    "dwarffemaleguard", "dwarffemalematernal", "dwarffemaleyoung", "dwarfmalegrim", "dwarfmaleguard",
    "dwarfmalestandard", "gnomefemalehappy", "gnomefemalenerdy", "gnomefemalestandard", "gnomemalestandard",
    "gnomemaleyoung", "gnomemalezany", "goblinfemalezany", "goblinmalegruff", "goblinmaleguard", "goblinmalezany",
    "humanfemaleofficial", "humanfemalestandard", "humanfemalewarrior", "humanmaleofficial", "humanmalestandard",
    "humanmalewarrior", "nightelffemalepriestess", "nightelffemalesentinel", "nightelffemalestandard",
    "nightelfmaleofficial", "nightelfmalestandard", "nightelfmalewarrior", "orcfemaleshaman", "orcfemalestandard",
    "orcfemalewarrior", "orcmaleguard", "orcmaleshady", "orcmalestandard", "taurenfemaleofficial",
    "taurenfemaleshaman", "taurenfemalestandard", "taurenmaleelder", "taurenmaleshaman", "taurenmalewarrior",
    "trollfemalelaidback", "trollfemaleold", "trollfemalestandard", "trollmaledark", "trollmaleshaman",
    "trollmalestandard", "undeadfemalemagic", "undeadfemalestandard", "undeadfemalewarrior", "undeadmaledark",
    "undeadmalestandard", "undeadmalewarrior",
]
LIBRARY_NAMED = ["archbishopbenedictus", "baronrevilgaz", "cairnebloodhoof", "fandralstaghelm", "gazlowe",
                 "hightinkermekkatorque", "jainaproudmoore", "kinganduinwrynn", "kingmagnibronzebeard",
                 "magathagrimtotem", "sylvanaswindrunner", "thrall", "tyrandewhisperwind", "varimathras", "voljin"]
UNDEAD_NOTE = "no ghoul (Forsaken) filter: the user's decision by ear, 2026-09-28"


def builtin_voices() -> dict:
    """The initial voices.json of SPEC.md 4.1 / 4.3, used only until the Voices agent's file exists. No voice
    carries the ghoul filter (the user's decision by ear, 2026-09-28)."""
    v = {}
    for ident in LIBRARY_GENERIC:
        key = ident + "npc"
        v[key] = {"source": "library", "status": "ok"}
        if ident.startswith("undead"):
            v[key]["notes"] = UNDEAD_NOTE
    for name in LIBRARY_NAMED + ["abomination", "necromancer", "dryad", "satyre", "peon", "npcbloodelffemalestandard",
                                 "narrator_alliance", "narrator_alliance_old", "narrator_alliance_v2", "narrator_horde"]:
        v[name] = {"source": "library", "status": "ok"}
    v["skyborne_female"] = {"source": "made", "status": "ok", "seed": 7,
                            "reference": {"kits": [353056, 353064], "folder": "scratchpad/voice/samples/skyborne_female"}}
    v["skyborne_male"] = {"source": "made", "status": "ok", "seed": 42,
                          "reference": {"kits": [353070, 353076], "folder": "scratchpad/voice/samples/skyborne_male"}}
    v["narrator_neutral"] = {"source": "made", "service": "narrator_forever", "status": "pilot",
                             "reference": {"kits": [351602, 351604, 351605, 351606, 351608, 351609, 351610, 351611,
                                                    351612, 351613, 351614, 351616]}}
    stand_ins = {
        "wc3_peasant": ("humanmalestandardnpc", {}), "wc3_witchdoctor": ("trollmaleshamannpc", {}),
        "creature_ogre": ("orcmaleguardnpc", {"tempo": 0.92}),
        "creature_dragon": ("kalecgos", {}), "creature_ancient": ("taurenmaleeldernpc", {"tempo": 0.9}),
        "creature_furbolg": ("taurenmalewarriornpc", {"tempo": 0.95}),
        "creature_elemental": ("titannpcgreetings", {}), "creature_imp": ("gnomemalezanynpc", {"tempo": 1.1}),
        "creature_demon": ("varimathras", {}), "creature_succubus": ("npcbloodelffemalenoble", {}),
        "creature_centaur": ("taurenmaleshamannpc", {}),
        "creature_naga_f": ("nightelffemalepriestessnpc", {}), "creature_naga_m": ("orcmaleshadynpc", {}),
        "creature_spirit": ("nightelffemalepriestessnpc", {}), "creature_gnoll": ("goblinmalegruffnpc", {}),
        "creature_child_f": ("gnomefemalehappynpc", {}), "creature_child_m": ("gnomemaleyoungnpc", {}),
    }
    for key, (service, extra) in stand_ins.items():
        v[key] = {"source": "stand-in", "service": service, "status": "pilot", **extra}
    identities = {i: i + "npc" for i in LIBRARY_GENERIC}
    identities.update({n: n for n in LIBRARY_NAMED})
    identities.update({"abominationwhat": "abomination", "necromancerwhat": "necromancer", "dryadwhat": "dryad",
                       "satyrewhat": "satyre", "peonwhat": "peon", "peasantwhat": "wc3_peasant",
                       "witchdoctorwhat": "wc3_witchdoctor", "creature:highelf_f": "npcbloodelffemalestandard"})
    for kit in (353056, 353064, 368869, 347830):
        identities["unnamed_kit%d" % kit] = "skyborne_female"
    for kit in (353070, 353076):
        identities["unnamed_kit%d" % kit] = "skyborne_male"
    narr = "narrator_neutral"
    return {"format": "melloui-voices/1", "defaultSeed": 42, "voices": v, "identities": identities,
            "narrators": {"stage": narr, "object": {"1": narr, "2": narr, "3": narr},
                          "item": {"1": narr, "2": narr, "3": narr}, "gossipObject": narr}}


VOICES_JSON_OUTPUT = os.path.join(S.V2_OUT, "voices.json")     # where the Voices agent's run writes it


def voices_path():
    """Tools/voice_v2/voices.json (SPEC.md 4.1), else the copy the voice maker writes to BuildData, else None."""
    for p in (VOICES_JSON, VOICES_JSON_OUTPUT):
        if os.path.exists(p):
            return p
    return None


def load_voices(path: str | None = None):
    """(voices config, label): voices.json when present, else the spec's initial table."""
    path = path or voices_path()
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh), path
    return builtin_voices(), "builtin (SPEC.md 4.1/4.3; voices.json not written yet)"


# ---------------------------------------------------------------------------------------------- identity -> voice
PLAYABLE = {"human", "dwarf", "nightelf", "gnome", "orc", "undead", "tauren", "troll", "goblin", "skyborne", "bloodelf"}
POOL_RACE = {"undead": "scourge"}                  # the display tables call the Forsaken "scourge"
CREATURE_FAMILIES = [                              # (regex on the identity, voice key)  -- SPEC.md 4.3
    (r"^creature:(ogre|giant)_|^creature:model:ogre$", "creature_ogre"),
    (r"^creature:dragon_|^creature:model:(dragonspawn|horisath)$", "creature_dragon"),
    (r"^creature:(treant_n|keeper_m)$|^creature:model:ancientof(lore|war)$", "creature_ancient"),
    (r"^creature:furbolg_", "creature_furbolg"),
    (r"^creature:elemental_|^creature:model:.*elemental", "creature_elemental"),
    (r"^creature:imp_m$|^creature:model:imp$", "creature_imp"),
    (r"^creature:demon_m$", "creature_demon"),
    (r"^creature:succubus_f$", "creature_succubus"),
    (r"^creature:centaur_", "creature_centaur"),
    (r"^creature:naga_f$", "creature_naga_f"),
    (r"^creature:naga_m$", "creature_naga_m"),
    (r"^creature:spirit_", "creature_spirit"),
    (r"^creature:gnoll_", "creature_gnoll"),
    (r"^creature:model:(humanfemalekid|orcfemalekid)$", "creature_child_f"),
    (r"^creature:model:orcmalekid$", "creature_child_m"),
    # not a row of the spec's table (one NPC, Anilia 3920, a dryad model): the library's dryad voice, like dryadwhat
    (r"^creature:dryad_f$", "dryad"),
]
POOL_MODELS = {"creature:model:humanmalecaster": ("human", "m"), "creature:model:madscientist": ("human", "m")}


def crc(entry: int) -> int:
    return zlib.crc32(str(entry).encode())


def pool_identity(entry: int, race: str, sex: str, pools: dict):
    """The race/sex pool's generic set picked by crc32(entry); None when the race has no pool."""
    g = pools.get((POOL_RACE.get(race, race), sex)) or []
    return g[crc(entry) % len(g)] if g else None


def resolve_identity(identity: str, entry: int, cfg: dict, pools: dict):
    """(voice key, how). voices.json "npcs" (the per-NPC choices: a character's own voice, a race voice, a closest
    voice or the narrator) beats the identity. Raises KeyError for an identity no rule covers."""
    npc = (cfg.get("npcs") or {}).get(str(entry))
    if npc:
        return (npc["voice"] if isinstance(npc, dict) else npc), "npc table, rule %s" % (
            npc.get("rule", "?") if isinstance(npc, dict) else "?")
    ids = cfg.get("identities", {})
    if identity in ids:
        v = ids[identity]
        if not v.startswith("pool:"):
            return v, "identities"
        # voices.json writes the per-NPC pool rows as "pool:<race>_<sex>" + a pools table of voice keys
        name = v[5:]
        pool = (cfg.get("pools") or {}).get(name)
        if pool:
            return pool[crc(entry) % len(pool)], "pool %s" % name
        race, _, sex = name.rpartition("_")
        pick = pool_identity(entry, race, sex, pools)
        if pick and pick in ids:
            return ids[pick], "pool %s -> %s" % (name, pick)
        raise KeyError(identity)
    m = re.match(r"^creature:([a-z]+)_([mfn])$", identity)
    if identity in POOL_MODELS or (m and m.group(1) in PLAYABLE):
        race, sex = POOL_MODELS.get(identity) or (m.group(1), m.group(2))
        pick = pool_identity(entry, race, "m" if sex == "n" else sex, pools)
        if pick and pick in ids:
            return ids[pick], "pool %s_%s -> %s" % (race, sex, pick)
    for rx, key in CREATURE_FAMILIES:
        if re.search(rx, identity):
            return key, "creature family"
    if identity.startswith("creature:") or identity.startswith("emitter_"):
        return cfg["narrators"].get("gossipObject", "narrator_neutral"), "creature: narrator"
    raise KeyError(identity)


# ---------------------------------------------------------------------------------------------- the rule (appends)
class VoiceRule:
    """The research's one-voice rule, for NPCs the frozen map does not have yet. Loaded lazily."""

    NONSPEECH = re.compile(r"attack|wound|aggro|footstep|clickable|click|fidget|chirp|squawk|death|serpent|funsized|"
                           r"zergling|pandacub|babymurloc")

    def __init__(self, cm_tables: dict):
        self.cdi = {int(r["ID"]): r for r in S.db2("CreatureDisplayInfo")}
        self.cdie = {int(r["ID"]): r for r in S.db2("CreatureDisplayInfoExtra")}
        self.races = {int(r["ID"]): r["ClientFileString"] for r in S.db2("ChrRaces")}
        self.cmd = {int(r["ID"]): r for r in S.db2("CreatureModelData")}
        self.npcsounds = {int(r["ID"]): [int(r["SoundID_%d" % i]) for i in range(4)] for r in S.db2("NPCSounds")}
        ske = collections.defaultdict(list)
        for r in S.db2("SoundKitEntry"):
            ske[int(r["SoundKitID"])].append(int(r["FileDataID"]))
        self.names = S.listfile_paths()
        self.ct = {r["Entry"]: r for r in cm_tables["creature_template"]}
        self.cache = S.creaturecache(cdi_ids=set(self.cdi))
        self.client_creature = {}
        for r in S.db2("Creature"):
            ds = [(int(r["DisplayID_%d" % i] or 0), float(r["DisplayProbability_%d" % i] or 0)) for i in range(4)]
            self.client_creature[int(r["ID"])] = (r["Name_lang"], [(d, w) for d, w in ds if d])
        self.wh = S.wowhead_npc_display()
        self.nvd = S.npc_voice_data()
        # archetypes: NPCSounds rows whose greeting kits share an audio file are one recording set
        parent = {n: n for n in self.npcsounds}

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x
        owner = {}
        for n, s in self.npcsounds.items():
            for f in ske.get(s[0], []):
                if f in owner:
                    parent[find(n)] = find(owner[f])
                else:
                    owner[f] = n
        clusters = collections.defaultdict(list)
        for n in self.npcsounds:
            clusters[find(n)].append(n)
        self.arch_of, self.speech = {}, {}
        for members in clusters.values():
            files = [f for n in members for f in ske.get(self.npcsounds[n][0], [])]
            stems = collections.Counter(self._stem(self.names[f]) for f in files if f in self.names)
            if stems:
                label = re.sub(r"(npc)?(greetings?|vendor)$", "", stems.most_common(1)[0][0])
            elif files:
                label = "unnamed_kit%d" % self.npcsounds[min(members)][0]
            else:
                label = "nofiles_npcsounds%d" % min(members)
            for n in members:
                self.arch_of[n] = label
            self.speech[label] = bool(files) and not self.NONSPEECH.search(label)
        pool = collections.defaultdict(collections.Counter)
        for d, r in self.cdi.items():
            rs = self.race_sex(d)
            n = int(r["NPCSoundID"])
            if rs and n and self.speech[self.arch_of[n]]:
                pool[rs][self.arch_of[n]] += 1
        self.pools = {rs: sorted(a for a, c in cnt.items() if c >= 5) for rs, cnt in pool.items()}

    @staticmethod
    def _stem(p):
        b = re.sub(r"\.(ogg|mp3|wav)$", "", os.path.basename(p))
        return re.sub(r"_?\d+[a-z]?$", "", b)

    def race_sex(self, did):
        r = self.cdi.get(did)
        if not r:
            return None
        ext = int(r["ExtendedDisplayInfoID"])
        if ext and ext in self.cdie:
            e = self.cdie[ext]
            return (self.races.get(int(e["DisplayRaceID"]), e["DisplayRaceID"]).lower(),
                    "m" if e["DisplaySexID"] == "0" else "f")
        return None

    def display_list(self, e):
        if e in self.cache:
            return "forever-cache", [(d, w) for d, _, w in self.cache[e]["displays"]]
        if e in self.ct:
            ms = [int(self.ct[e]["ModelId%d" % i] or 0) for i in range(1, 5)]
            return "cmangos", [(m, 1.0) for m in ms if m]
        if e in self.client_creature and self.client_creature[e][1]:
            return "forever-client", self.client_creature[e][1]
        if e in self.wh and self.wh[e][0]:
            return "wowhead", [(self.wh[e][0], 1.0)]
        return "none", []

    def name(self, e):
        if e in self.ct:
            return self.ct[e]["Name"] or ""
        if e in self.cache:
            return self.cache[e]["name"]
        if e in self.client_creature:
            return self.client_creature[e][0]
        return (self.wh.get(e) or (None, ""))[1] or ""

    def identity(self, e, store_npcs=None):
        """(source, identity, reason). identity None when nothing is known about the NPC."""
        src, L = self.display_list(e)
        L = [(d, w) for d, w in L if d in self.cdi]
        if not L:
            rec = (store_npcs or {}).get(str(e)) or {}
            race, sex = (rec.get("race") or "").lower(), (rec.get("gender") or "").lower()
            if race and sex in ("m", "f"):
                pick = pool_identity(e, race, sex, self.pools)
                if pick:
                    return "collector", pick, "no display known; collector race/sex -> crc32(entry) mod pool"
            return src, None, "no display known"
        best = max(w for _, w in L)
        primary = next(d for d, w in L if w == best)
        rs = self.race_sex(primary)
        n = int(self.cdi[primary]["NPCSoundID"])
        if n and self.speech[self.arch_of[n]]:
            return src, self.arch_of[n], "game greeting set of primary display"
        for d, _ in L:
            nn = int(self.cdi[d]["NPCSoundID"])
            if nn and self.race_sex(d) == rs and self.speech[self.arch_of[nn]]:
                return src, self.arch_of[nn], "set of another display, same race/sex"
        if rs:
            g = self.pools.get(rs) or []
            if g:
                return src, g[crc(e) % len(g)], "silent in game -> crc32(entry) mod race/sex pool"
            return src, "%s_%s:default" % rs, "silent, race/sex without pool"
        key = self.nvd.get(e)
        if not key:
            mp = self.names.get(int(self.cmd.get(int(self.cdi[primary]["ModelID"]), {}).get("FileDataID", 0) or 0), "")
            key = "model:" + (os.path.basename(mp).replace(".m2", "") or "?")
        return src, "creature:%s" % key, "non-character model -> MelloUI race key (or model name)"


# research pools (voice_rule_facts.txt), used by the one-time freeze so it needs no DB2 scan
RESEARCH_POOLS = {
    ("human", "m"): ["humanmaleofficial", "humanmalestandard", "humanmalewarrior"],
    ("human", "f"): ["humanfemaleofficial", "humanfemalestandard", "humanfemalewarrior"],
    ("dwarf", "m"): ["dwarfmalegrim", "dwarfmaleguard", "dwarfmalestandard"],
    ("dwarf", "f"): ["dwarffemaleguard", "dwarffemalematernal", "dwarffemaleyoung"],
    ("orc", "m"): ["orcmaleguard", "orcmaleshady", "orcmalestandard"],
    ("orc", "f"): ["orcfemaleshaman", "orcfemalestandard", "orcfemalewarrior"],
    ("nightelf", "m"): ["nightelfmaleofficial", "nightelfmalestandard", "nightelfmalewarrior"],
    ("nightelf", "f"): ["nightelffemalepriestess", "nightelffemalesentinel", "nightelffemalestandard"],
    ("scourge", "m"): ["undeadmaledark", "undeadmalestandard", "undeadmalewarrior"],
    ("scourge", "f"): ["undeadfemalemagic", "undeadfemalestandard", "undeadfemalewarrior"],
    ("tauren", "m"): ["taurenmaleelder", "taurenmaleshaman", "taurenmalewarrior"],
    ("tauren", "f"): ["taurenfemaleofficial", "taurenfemaleshaman", "taurenfemalestandard"],
    ("gnome", "m"): ["gnomemalestandard", "gnomemaleyoung", "gnomemalezany"],
    ("gnome", "f"): ["gnomefemalehappy", "gnomefemalenerdy", "gnomefemalestandard"],
    ("troll", "m"): ["trollmaledark", "trollmaleshaman", "trollmalestandard"],
    ("troll", "f"): ["trollfemalelaidback", "trollfemaleold", "trollfemalestandard"],
    ("goblin", "m"): ["goblinmalegruff", "goblinmaleguard", "goblinmalezany"],
    ("goblin", "f"): ["goblinfemalezany", "vo_goblinguardf_"],
    ("skyborne", "m"): ["unnamed_kit353070", "unnamed_kit353076"],
    ("skyborne", "f"): ["unnamed_kit353056", "unnamed_kit353064"],
    ("bloodelf", "m"): ["nightelfmalestandard"],
    ("bloodelf", "f"): ["nightelffemalestandard"],
}


class NpcVoiceMap:
    """npc_voices.csv: npc -> row. Frozen: rows are only ever appended."""

    def __init__(self, cfg: dict, path: str = NPC_VOICES_CSV):
        self.cfg, self.path = cfg, path
        self.rows = collections.OrderedDict()
        self.appended = []
        self.created = False
        if os.path.exists(path):
            with open(path, encoding="utf-8", newline="") as fh:
                for r in csv.DictReader(fh):
                    self.rows[int(r["npc"])] = r

    def freeze_from(self, research_csv: str):
        """Build the map once from the research draft (npc_voice_map.csv). Refuses when the map exists."""
        if self.rows:
            raise SystemExit("npc_voices.csv exists and is frozen; it is only ever appended to")
        today = datetime.date.today().isoformat()
        unmapped = collections.Counter()
        with open(research_csv, encoding="utf-8", newline="") as fh:
            for r in csv.DictReader(fh):
                e = int(r["entry"])
                try:
                    voice, how = resolve_identity(r["voice_identity"], e, self.cfg, RESEARCH_POOLS)
                except KeyError:
                    unmapped[r["voice_identity"]] += 1
                    continue
                self.rows[e] = {"npc": str(e), "name": r["name"], "voice": voice, "identity": r["voice_identity"],
                                "reason": r["reason"] + ("" if how == "identities" else "; " + how),
                                "source": r["display_source"], "assigned": today}
        if unmapped:
            raise SystemExit("identities without a voice: %s" % dict(unmapped))
        self.created = True

    def voice(self, npc: int):
        r = self.rows.get(npc)
        return r["voice"] if r else None

    def drift(self):
        """identity -> (frozen voices, voice the current voices config gives it), for identities whose frozen
        rows no longer match voices.json (e.g. a new voice was made for a rare kit). Reported, never applied."""
        out = {}
        for e, r in self.rows.items():
            try:
                now, _ = resolve_identity(r["identity"], e, self.cfg, RESEARCH_POOLS)
            except KeyError:
                now = None
            if now != r["voice"]:
                d = out.setdefault(r["identity"], [set(), now, 0])
                d[0].add(r["voice"])
                d[2] += 1
        return {k: {"frozen": sorted(v[0]), "now": v[1], "npcs": v[2]} for k, v in out.items()}

    def remap(self, identities):
        """Re-map every row of the given identities to what the current voices config says. Only on an
        explicit request (the map is frozen otherwise). Returns the changed rows."""
        today = datetime.date.today().isoformat()
        changed = []
        for e, r in self.rows.items():
            if r["identity"] not in identities:
                continue
            now, how = resolve_identity(r["identity"], e, self.cfg, RESEARCH_POOLS)
            if now != r["voice"]:
                r["reason"] = "%s; re-mapped %s from %s" % (r["reason"], today, r["voice"])
                r["voice"] = now
                r["assigned"] = today
                changed.append(r)
        self.remapped = changed
        return changed

    def remap_all(self):
        """Re-map every row whose voice differs from what the current voices config gives it (the per-NPC table
        first, then the identity). Only on an explicit request, e.g. the 2026-09-28 re-map against the final
        voice library. Returns the changed rows."""
        today = datetime.date.today().isoformat()
        changed = []
        for e, r in self.rows.items():
            try:
                now, how = resolve_identity(r["identity"], e, self.cfg, RESEARCH_POOLS)
            except KeyError:
                continue
            if now != r["voice"]:
                why = how if how.startswith("npc table") else "identity %s" % r["identity"]
                r["reason"] = "%s; re-mapped %s from %s (%s)" % (r["reason"], today, r["voice"], why)
                r["voice"] = now
                r["assigned"] = today
                changed.append(r)
        self.remapped = changed
        return changed

    def append_missing(self, npcs, rule_factory, store_npcs=None, names=None):
        """Give every NPC of `npcs` that is not in the map a voice by the rule and append it."""
        missing = sorted(n for n in npcs if n and n not in self.rows)
        if not missing:
            return []
        rule = rule_factory()
        today = datetime.date.today().isoformat()
        out = []
        for e in missing:
            src, ident, why = rule.identity(e, store_npcs)
            if ident is None:
                ident = "creature:unknown"
                voice, how = self.cfg["narrators"].get("gossipObject", "narrator_neutral"), "nothing known: narrator"
            else:
                try:
                    voice, how = resolve_identity(ident, e, self.cfg, rule.pools)
                except KeyError:
                    raise SystemExit("new NPC %d: identity %r has no voice in voices.json identities" % (e, ident))
            nm = rule.name(e) or (names or {}).get(e, "")
            row = {"npc": str(e), "name": nm, "voice": voice, "identity": ident,
                   "reason": why + ("" if how == "identities" else "; " + how), "source": src, "assigned": today}
            self.rows[e] = row
            out.append(row)
        self.appended.extend(out)
        return out

    def save(self):
        with open(self.path, "w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=CSV_COLUMNS, lineterminator="\n")
            w.writeheader()
            for r in self.rows.values():
                w.writerow({k: r.get(k, "") for k in CSV_COLUMNS})
