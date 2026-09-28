#!/usr/bin/env python3
"""Voices for MelloUI_VoiceOverData_v2: voices.json, new voicegen voices made from the game's own audio,
one short test line per new voice, and a report.

Every NPC that speaks a line gets ONE voice. The identities come from the research map
(npc_voice_map.csv: entry -> voice identity); each identity is mapped to a voice key here:

  * a library voice of the same name (the game's own NPC greeting sets, made by Denis);
  * a voice MADE on voicegen from the client's own audio when there are at least 6 s of clean speech
    (ASR decides; the reference clips are cut read-only from the local CASC storage);
  * otherwise the closest library voice with filters (a stand-in), listed in the report for the user.

On top of the identities, a per-NPC table (voices.json "npcs", re-map asked for by the user on 2026-09-28 against
Denis's final library of 170 voices) gives every speaking NPC its voice by this priority:

  1   a voice made for exactly that character (retail_<name>, thrall, jainaproudmoore ...)
  2   the game's own NPC voice set of its main display (2p: a silent character model -> its race/sex pool, as before)
  3   a race or creature voice of the library (retail_generic_ogre, retail_quilboar_m, brokennpc1, dryad, satyre ...)
  4   a voice this pipeline made from game audio (voices_made/), only where 1-3 have nothing
  5   the closest voice as a last resort (listed in the report for the user)
  N   the narrator reads it (critters, beasts, machines and objects shown as creatures)

Stages (each one saves its result, so a stage can be re-run on its own):

  python Tools/voice_v2_voices.py plan       identities -> voices, and the reference candidates (no network)
  python Tools/voice_v2_voices.py extract    cut the candidate clips out of the client (read-only) into references/
  python Tools/voice_v2_voices.py asr        transcribe the candidates (/v1/asr); a group passes at >= 6 s clean speech
  python Tools/voice_v2_voices.py make       create the voices that passed (POST /v1/voices/<name>?seconds=14, pick=asr)
  python Tools/voice_v2_voices.py build      write voices.json (identities, per-NPC table, narrators)
  python Tools/voice_v2_voices.py test       one /v1/say per new voice (+ --standins, --alts, --used: every library
                                             voice a speaking NPC uses that has no test line yet) into voice_tests/
  python Tools/voice_v2_voices.py narrators  the narrator comparison: one /v1/say of the same line per library narrator
  python Tools/voice_v2_voices.py report     write voices_report.md (OLD -> NEW against baseline/, counts per rule)
  python Tools/voice_v2_voices.py all        every stage in order

After `build`, re-map the frozen NPC map and the manifests once:
  python Tools/voice_v2/export_lines.py --remap-all --pilot-selection <pilot_selection.json>
The report then checks that lines.json gives every NPC the voice voices.json says.

Output (MelloUI-BuildData/output/voice_v2/): voices.json, voices_report.md, references/<key>/<group>/ (game
audio, local only, never shipped or committed), voices_made/<key>.json + <key>_reference.wav + <key>_test.ogg,
voice_tests/<key>.ogg, voices_state.json (the ASR and make results the report is built from).

Network: only the voicegen box (env VG, default http://172.24.100.77:7895). The token comes from env VG_TOKEN
or the file ~/.voicegen_token and is never printed, logged or written anywhere; errors never show headers.
Standard library only.
"""
from __future__ import annotations

import csv
import glob
import hashlib
import json
import os
import re
import shutil
import struct
import sys
import time
import urllib.error
import urllib.request
import uuid
import zlib
from collections import Counter, OrderedDict, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from paths import CACHE, OUTPUT  # noqa: E402

V2 = os.path.join(OUTPUT, "voice_v2")
REFS = os.path.join(V2, "references")
MADE_DIR = os.path.join(V2, "voices_made")
TESTS_DIR = os.path.join(V2, "voice_tests")
VOICES_JSON = os.path.join(V2, "voices.json")
REPORT_MD = os.path.join(V2, "voices_report.md")
STATE_JSON = os.path.join(V2, "voices_state.json")
INPUTS = os.path.join(V2, "inputs")
LINES_JSON = os.path.join(V2, "lines.json")
BASELINE = os.path.join(V2, "baseline")              # the assignment before the 2026-09-28 re-map (OLD in the report)
NPC_VOICES_CSV = os.path.join(HERE, "voice_v2", "npc_voices.csv")

# Research inputs (the scratchpad of the 2026-09-28 research). Copied into output/voice_v2/inputs on first use,
# so later runs do not depend on that folder.
RESEARCH = os.environ.get("MELLOUI_VOICE_RESEARCH", os.path.join(
    os.path.expanduser("~"), "AppData", "Local", "Temp", "claude", "F--Download-Backup-Project-Web-MelloUI-Test",
    "4d7e610c-71a7-442c-9c0f-b0e61551b191", "scratchpad", "voice"))
DB2 = os.environ.get("MELLOUI_DB2_160", r"F:\Download-Backup\WoWExport\db2_1.60")
LISTFILE = os.path.join(CACHE, "verified-listfile.csv")
WOW = os.environ.get("MELLOUI_WOW", r"F:\World of Warcraft")
PRODUCT = "wow_classic_beta"
CASC_READER = os.environ.get("MELLOUI_CASC_LOCAL", os.path.join(RESEARCH, "casc_local.py"))

VG = os.environ.get("VG", "http://172.24.100.77:7895")
DEFAULT_SEED = 42
MIN_CLEAN_SECONDS = 6.0
MIN_CLIP_SECONDS = 1.0
REF_SECONDS = 14
BUILD_DATE = "2026-09-28"

TEST_LINE_NPC = "Well met, traveler. Rest a moment by the fire, then we will speak of the task at hand."
TEST_LINE_NARRATOR = ("The old tower stands silent. Its door hangs open, and the wind carries the smell of smoke "
                      "from the valley below.")

KEY_RE = re.compile(r"^[a-z0-9_]+$")

# ----------------------------------------------------------------------------------------------------------------
# What to make: every voice key that has no library voice of its own, with the client audio to try, in order of
# preference. A group is ONE speaker (never mix speakers in one reference). The first group with >= 6 s of clean
# speech (ASR) wins. Without one, the voice stays a stand-in: `fallback` (a library voice + filters).
#   kits     NPCSounds / SoundKit IDs (SoundKitEntry -> FileDataID)
#   fdids    FileDataIDs
#   folder   a listfile folder; include / exclude are regexes on the file name; limit caps the clip count
# ----------------------------------------------------------------------------------------------------------------
CANDIDATES = OrderedDict([
    ("narrator_neutral", {
        "service": "narrator_forever", "narrator": True,
        "what": "neutral narrator: directions, object and item quests, stage directions",
        "groups": [
            {"label": "forever_intro", "why": "the Forever intro narration (BroadcastText 316345-316358, SoundKits "
             "351602-351614 and 351616; kit 351615 left out: old files)",
             "fdids": [7940966, 7940972, 7940975, 7940978, 7940981, 7940984, 7940987, 7940990, 7941000, 7941005,
                       7941008, 7941011]},
        ],
        "fallback": {"service": "narrator_alliance_v2"},
    }),
    ("skyborne_f368869", {
        "what": "Skyborne female, rare greeting kit 368869 (Constable Aonda)",
        "groups": [{"label": "kit368869", "why": "NPCSounds 3820: greeting kit 368869 + farewell kit 368870",
                    "kits": [368869, 368870]}],
        "fallback": {"service": "skyborne_female", "seed": 7, "key": "skyborne_female"},
    }),
    ("skyborne_f347830", {
        "what": "Skyborne female, rare greeting kit 347830 (Ayessa Dawnsinger)",
        "groups": [{"label": "kit347830", "why": "NPCSounds 3764: greeting kit 347830 + farewell kit 347833",
                    "kits": [347830, 347833]}],
        "fallback": {"service": "skyborne_female", "seed": 7, "key": "skyborne_female"},
    }),
    ("wc3_peasant", {
        "what": "the peasant unit voice (NPCSounds 161)",
        "groups": [{"label": "peasant", "why": "sound/creature/peasant (the unit's 12 lines; NPCSounds 161 uses 4)",
                    "folder": "sound/creature/peasant"}],
        "fallback": {"service": "humanmalestandardnpc"},
    }),
    ("wc3_witchdoctor", {
        "what": "the witch doctor unit voice (NPCSounds 86)",
        "groups": [{"label": "witchdoctor", "why": "sound/creature/witch doctor (the unit's 14 lines; NPCSounds 86 uses 5)",
                    "folder": "sound/creature/witch doctor",
                    "skip": [564191, 564190], "skipWhy": "ASR garbled them (\"Dbby good choicece man\", \"I do it no\")"},
                   {"label": "troll_witch_doctor", "why": "sound/creature/troll_witch_doctor dialogue lines",
                    "folder": "sound/creature/troll_witch_doctor", "include": r"_\d\d_m\.ogg$"}],
        "fallback": {"service": "trollmaleshamannpc"},
    }),
    ("creature_ogre", {
        "what": "ogres (and giants, which the spec folds into the ogre voice)",
        "groups": [{"label": "ogre_vo801", "why": "sound/creature/ogre vo_801_ogre_*: an ogre's spoken lines",
                    "folder": "sound/creature/ogre", "include": r"^vo_801_ogre",
                    "reject": "made and tried: the clone is unstable (its lines are slow, with long grunting pauses). "
                              "The test line came out 21.5 s for 18 words with words repeated at seed 42, cut short "
                              "(\"W met the\") at seed 7 and garbled at seed 1234"},
                   {"label": "ogre_forgemaster", "why": "sound/creature/gogduh: the forgemaster ogre's event and spell lines",
                    "folder": "sound/creature/gogduh", "include": r"(event|spell|aggro|slay|intro)"},
                   {"label": "ogre_classic", "why": "sound/creature/ogre + ogremage: the classic ogre barks",
                    "folder": "sound/creature/ogre", "include": r"^mogre"}],
        "fallback": {"service": "orcmaleguardnpc", "tempo": 0.92},
    }),
    ("creature_dragon", {
        "what": "dragons, drakes, dragonspawn and whelps",
        "groups": [{"label": "azuregos", "why": "sound/creature/azuregos vo_703: Azuregos (a blue dragon; Awbee is "
                    "blue flight, and Azuregos is one of the NPCs)", "folder": "sound/creature/azuregos",
                    "include": r"^vo_703_azuregos", "limit": 24,
                    "skip": [1382047, 1382049, 1382056, 1382063, 1382094, 1382095, 1382099, 1382100],
                    "skipWhy": "ASR misheard names or words in them (\"Ethereum\", \"tririnket\")"},
                   {"label": "vaelastrasz", "why": "sound/creature/vaelastrasz: Vaelastrasz's Blackwing Lair lines",
                    "folder": "sound/creature/vaelastrasz"}],
        "fallback": {"service": "kalecgos"},
    }),
    ("creature_keeper", {
        "what": "keepers of the grove (split from creature_ancient: Keeper Remulos himself is one of them)",
        "groups": [{"label": "keeper_remulos", "why": "sound/creature/keeper_remulos vo_703: Keeper Remulos's spoken lines",
                    "folder": "sound/creature/keeper_remulos", "include": r"^vo_703_keeper_remulos", "limit": 24,
                    "skip": [1384568, 1384598, 1384603, 1384623, 1388799, 1388806, 1406698, 1406699, 1407433,
                             1407434, 1407435],
                    "skipWhy": "names ASR garbled (Elune, Cenarius, Hamuul Runetotem, Malorne) and three combat barks"}],
        "fallback": {"key": "creature_ancient"},
    }),
    ("creature_ancient", {
        "what": "ancients and treants (Onu, Arei, Ancient of Lore/War, Old Ironbark ...)",
        "groups": [{"label": "ancient_protector", "why": "sound/creature/ancient_protector vo_70 lines",
                    "folder": "sound/creature/ancient_protector"},
                   {"label": "treant", "why": "sound/creature/treant vo_703_treant_01", "folder": "sound/creature/treant"},
                   {"label": "ancient_of_war", "why": "sound/creature/ancient_of_war vo_703_ancient_of_war_01",
                    "folder": "sound/creature/ancient_of_war"}],
        "fallback": {"service": "taurenmaleeldernpc", "tempo": 0.9},
    }),
    ("creature_furbolg", {
        "what": "furbolgs",
        "groups": [{"label": "furbolg", "why": "sound/creature/furbolg: the only furbolg audio (combat barks)",
                    "folder": "sound/creature/furbolg"}],
        "fallback": {"service": "taurenmalewarriornpc", "tempo": 0.95},
    }),
    ("creature_elemental", {
        "what": "elementals (earth, water, air, fire manifestations; Duke Hydraxis; Lokholar)",
        "groups": [{"label": "elemental_forgemaster", "why": "sound/creature/magmolatus: a molten elemental's event "
                    "and spell lines", "folder": "sound/creature/magmolatus", "include": r"forgemaster_elemental",
                    "reject": "a processed, shouted boss voice: ASR misheard about 8 of its 13 'usable' lines "
                              "(\"I return Judus\", \"Yes, the mood weekend\", \"Seeear my flames\"), so not clean"},
                   {"label": "lilragnaros", "why": "sound/creature/lilragnaros: the pet's two spoken lines",
                    "folder": "sound/creature/lilragnaros", "include": r"line"}],
        "fallback": {"service": "thorim", "why": "the spec's titannpcgreetings is broken on the server (a one-word "
                     "line came back as 58 s of audio; the test line failed with HTTP 500 three times); thorim reads "
                     "the test line cleanly"},
    }),
    ("creature_imp", {
        "what": "imps",
        "groups": [{"label": "imp_pet", "why": "sound/creature/impvo: the warlock imp's spoken lines",
                    "folder": "sound/creature/impvo", "skip": [552527, 552526, 552528],
                    "skipWhy": "ASR garbled them"},
                   {"label": "imp_vo703", "why": "sound/creature/imp vo_703_imp_*", "folder": "sound/creature/imp",
                    "include": r"^vo_703_imp"}],
        "fallback": {"service": "gnomemalezanynpc", "tempo": 1.1},
    }),
    ("creature_succubus", {
        "what": "succubi (Mistress Nagmara)",
        "groups": [{"label": "succubus_pet", "why": "sound/creature/succubusvo: the warlock succubus's spoken lines",
                    "folder": "sound/creature/succubusvo", "skip": [561152, 561157, 561163],
                    "skipWhy": "ASR garbled them (the long joke line above all)"}],
        "fallback": {"service": "npcbloodelffemalenoble"},
    }),
    ("creature_centaur", {
        "what": "centaurs",
        "groups": [{"label": "centaur", "why": "sound/creature/centaur: combat barks only",
                    "folder": "sound/creature/centaur"},
                   {"label": "centaurfemale", "why": "sound/creature/centaurfemale: combat barks only",
                    "folder": "sound/creature/centaurfemale"}],
        "fallback": {"service": "taurenmaleshamannpc"},
    }),
    ("creature_naga_f", {
        "what": "female naga / sirens (Meridith the Mermaiden)",
        "groups": [{"label": "naga_female_vo801", "why": "sound/creature/naga_female vo_801 lines (combat lines: "
                    "the tone is hostile)", "folder": "sound/creature/naga_female",
                    "skip": [1884147, 1884151, 1884153, 1884154, 1884155, 1884157],
                    "skipWhy": "ASR garbled them (names, hissed words)"}],
        "fallback": {"service": "nightelffemalepriestessnpc"},
    }),
    ("creature_naga_m", {
        "what": "male naga (Zalashji)",
        "groups": [{"label": "genericnagamale", "why": "sound/creature/genericnagamale: a naga NPC greeting set "
                    "(greeting, farewell, pissed)", "folder": "sound/creature/genericnagamale"},
                   {"label": "naga_male_vo801", "why": "sound/creature/naga_male vo_801 lines",
                    "folder": "sound/creature/naga_male"}],
        "fallback": {"service": "orcmaleshadynpc"},
    }),
    ("creature_gnoll", {
        "what": "gnolls",
        "groups": [{"label": "gnollv2", "why": "sound/creature/gnollv2: combat barks only",
                    "folder": "sound/creature/gnollv2", "include": r"(aggro|preaggro)"}],
        "fallback": {"service": "goblinmalegruffnpc",
                     "why": "the plain voice, without the spec's 0.5 brute filter (no ghoul filter anywhere, the "
                            "user's decision of 2026-09-28)"},
    }),
    ("creature_child_f", {
        "what": "girls (Odd Child, Thra, and the kid-model girls: Pamela Redpath, Hilary, Spoops ...)",
        "groups": [{"label": "kul_tiran_kid_f", "why": "sound/creature/kul_tiran_kid *_f: a human girl's lines",
                    "folder": "sound/creature/kul_tiran_kid", "include": r"_f\.ogg$", "limit": 20,
                    "skip": [1993589, 1993591, 1993592, 1993593, 1993594, 1993595, 1993596, 1993597],
                    "skipWhy": "the lines calling the cat \"Scratchy\": ASR spelled the name five ways"},
                   {"label": "pandaren_female_child", "why": "sound/creature/pandarenfemalechild greeting set",
                    "folder": "sound/creature/pandarenfemalechild"}],
        "fallback": {"service": "gnomefemalehappynpc"},
    }),
    ("creature_child_m", {
        "what": "boys (Migi, and the kid-model boys: the Human and Orcish Orphans, Billy Maclure, Flik ...)",
        "groups": [{"label": "kul_tiran_kid_m", "why": "sound/creature/kul_tiran_kid *_m: a human boy's lines",
                    "folder": "sound/creature/kul_tiran_kid", "include": r"_m\.ogg$", "limit": 20,
                    "skip": [1993629, 1993640, 1993648], "skipWhy": "ASR garbled them"},
                   {"label": "pandaren_male_child", "why": "sound/creature/pandarenmalechild greeting set",
                    "folder": "sound/creature/pandarenmalechild"}],
        "fallback": {"service": "gnomemaleyoungnpc"},
    }),
])

# Stand-ins with no usable client audio at all (checked: the family's only files are ambient loops or none).
STAND_INS = OrderedDict([
    ("creature_spirit", {"what": "spirit healers and wisps", "service": "nightelffemalepriestessnpc",
                         "why": "sound/creature/spirithealer holds only an ambient loop; wisps only chime"}),
    ("creature_demon", {"what": "dreadlords (Lord Banehollow)", "service": "varimathras",
                        "why": "Varimathras is a dreadlord greeting set in the library"}),
])

# Library voices tried against the family keys on 2026-09-28 (test lines in voice_tests/alt_<name>.ogg).
ALTERNATES = OrderedDict([
    ("creature_centaur", ["retail_centaur_m", "retail_centaur_f"]),
    ("creature_elemental", ["retail_unleashed_elemental", "retail_duke_hydraxis"]),
    ("creature_ogre", ["retail_generic_ogre"]),
    ("creature_dragon", ["retail_azuregos"]),
    ("creature_keeper", ["retail_keeper_remulos"]),
    ("creature_imp", ["retail_hellish_imp"]),
])

# ----------------------------------------------------------------------------------------------------------------
# The per-NPC assignment (2026-09-28, against Denis's final library). See the priority in the module docstring.
# ----------------------------------------------------------------------------------------------------------------
RULES = OrderedDict([
    ("1", "own voice: made for exactly that character"),
    ("2", "the game's own voice set of the main display"),
    ("2p", "silent character model: race/sex pool (as before)"),
    ("3", "race or creature voice of the library"),
    ("4", "voice made by this pipeline from game audio"),
    ("5", "closest voice (last resort)"),
    ("N", "the narrator reads it"),
])

# Rule 3 for a whole family: the family key keeps its name (it is a folder in the addon) and takes Denis's library
# voice as its service. The voice this pipeline made for the family (rule 4) stays on the server, unused.
FAMILY_LIBRARY = OrderedDict([
    ("creature_ogre", "retail_generic_ogre"),
    ("creature_imp", "retail_hellish_imp"),
    ("creature_centaur", "retail_centaur_m"),     # Denis split retail_centaur_type_two into _m / _f (2026-09-28)
    ("creature_elemental", "retail_unleashed_elemental"),
])

# Library voices that ARE one character (rule 1 when that character speaks them). The game's own named greeting
# sets (thrall ...) come in through the identities; the retail_* ones Denis cloned from retail WoW come in per NPC.
NAMED_LIBRARY = ("archbishopbenedictus", "arthas", "baronrevilgaz", "brann", "cairnebloodhoof", "darionmograine",
                 "fandralstaghelm", "gazlowe", "hightinkermekkatorque", "jainaproudmoore", "kalecgos", "kinganduinwrynn",
                 "kingmagnibronzebeard", "lichking", "magathagrimtotem", "sylvanaswindrunner", "thassarian", "thorim",
                 "thrall", "tirionfordring", "tyrandewhisperwind", "varianwrynn", "varimathras", "velen", "voljin")

# Rule 1 per NPC: npc -> (voice, why). Found by name over npc_voices.csv (every speaking NPC is in it).
NAMED_NPCS = OrderedDict([
    (1855, ("retail_tirionfordring", "Tirion Fordring (the hermit of Eastweald). The library also has the game set "
                                     "`tirionfordring` (a later display's greetings); Denis cloned retail_tirionfordring "
                                     "for the Tirion the old game left silent")),
    (12126, ("retail_tirionfordring", "Lord Tirion Fordring: the same character")),
    (10667, ("retail_chromie", "Chromie (shown as a gnome: was gnomefemalenerdynpc)")),
    (15192, ("retail_anachronos", "Anachronos")),
    (11832, ("retail_keeper_remulos", "Keeper Remulos")),
    (13278, ("retail_duke_hydraxis", "Duke Hydraxis")),
    (3679, ("retail_naralex", "Naralex")),
    (9039, ("retail_doomrel", "Doom'rel")),
    (8929, ("retail_moira", "Princess Moira Bronzebeard")),
    (6109, ("retail_azuregos", "Azuregos")),
    (15481, ("retail_azuregos", "Spirit of Azuregos: the same character")),
    (15380, ("retail_arygos", "Arygos (shown as a gnome: was gnomemalezanynpc)")),
    (15379, ("retail_caelestrasz", "Caelestrasz (shown as a night elf: was nightelfmalewarriornpc)")),
    (15378, ("retail_merithra_of_the_dream", "Merithra of the Dream (shown as a night elf: was nightelffemalesentinelnpc)")),
    (13020, ("retail_vaelastrasz", "Vaelastrasz the Corrupt")),
    (11699, ("varianwrynn", "Varian Wrynn: the library's game set of that name (he speaks no line today)")),
])

# Children: the display model is humanmalekid / humanfemalekid / orcmalekid / orcfemalekid (checked against the
# client's CreatureDisplayInfo -> CreatureModelData on 2026-09-28). They sat under creature:human_* / orc_* and got an
# adult voice from the race pool; the child voices are made (rule 4: the library has none).
KIDS_M = OrderedDict([(247, "Billy Maclure"), (664, "Benjamin Carevin"), (1429, "Thurman Schneider"),
                      (1672, "Lohgan Eva"), (4982, "Thomas"), (8666, "Lil Timmy"), (8965, "Shawn"),
                      (14305, "Human Orphan"), (14444, "Orcish Orphan"), (14860, "Flik"), (15310, "Jesper")])
KIDS_F = OrderedDict([(851, "Hannah"), (1673, "Alyssa Eva"), (8962, "Hilary"), (10926, "Pamela Redpath"),
                      (15309, "Spoops")])

# Rules 3, 5 and N per NPC: npc -> (voice key, rule, why).
NPC_OVERRIDES = OrderedDict([
    (3430, ("retail_quilboar_m", "3", "Mangletooth, a quilboar (was read by the narrator); Denis's male quilboar "
                                     "voice (retail_quilboar was split into _m / _f on 2026-09-28)")),
    (5397, ("retail_centaur_f", "3", "Uthek the Wise, a female centaur: Denis's female centaur voice (was the male "
                                    "centaur voice of the family)")),
    (1776, ("brokennpc1", "3", "Magtoor, a Lost One (a Broken draenei): the library's Broken voice (was the narrator)")),
    (7363, ("brokennpc2", "3", "Kum'isha the Collector, a Lost One: the library's other Broken voice (was the narrator)")),
    (11874, ("brokennpc1", "3", "Masat T'andr, a Lost One (speaks no line today)")),
    (7918, ("thorim", "5", "Stone Watcher of Norgannon, a titan construct: the library's titan keeper Thorim "
                           "(titannpcgreetings, the titan set, is broken on the server); was the keeper voice")),
    (7172, ("thorim", "5", "Lore Keeper of Norgannon, a titan construct (speaks no line today)")),
    (1244, ("creature_ancient", "5", "Rethiel the Greenwarden, a bog beast guarding the land, speaks in the first "
                                     "person: the ancient's voice (was the narrator)")),
    (11956, ("creature_ancient", "5", "Great Bear Spirit, a wild god's spirit teaching druids (was the narrator)")),
    (255853, ("creature_ancient", "5", "Urs'endris, a bear avatar teaching druids (was the narrator)")),
    (222522, ("creature_ancient", "5", "Spirit of Agamaggan, the boar demigod (an Ancient) (was the narrator)")),
    (10799, ("creature_ogre", "5", "Warosh, a troglodyte brute (\"Argh! So hard to speak!\"): the ogre voice "
                                   "(was the narrator)")),
    (6669, ("narrator_neutral", "N", "The Threshwackonator 4100, a harvest machine: its text is narration "
                                     "(was the ogre voice through creature:giant_n)")),
    (7166, ("narrator_neutral", "N", "Wrenix's Gizmotronic Apparatus, a machine: its text is narration "
                                     "(was the ogre voice)")),
    (12245, ("narrator_neutral", "N", "Vendor-Tron 1000, a machine (speaks no line today)")),
    (12246, ("narrator_neutral", "N", "Super-Seller 680, a machine (speaks no line today)")),
    (16431, ("narrator_neutral", "N", "Cracked Necrotic Crystal, an object: its text is narration (was an undead "
                                      "male pool voice)")),
    (16531, ("narrator_neutral", "N", "Faint Necrotic Crystal, an object (was an undead male pool voice)")),
    (224965, ("narrator_neutral", "N", "Khonsu (a horisath model): its two texts are narration (was the dragon voice)")),
])
for _n, _name in KIDS_M.items():
    NPC_OVERRIDES[_n] = ("creature_child_m", "4", f"{_name}, a boy (kid model; was an adult race-pool voice)")
for _n, _name in KIDS_F.items():
    NPC_OVERRIDES[_n] = ("creature_child_f", "4", f"{_name}, a girl (kid model; was an adult race-pool voice)")
del _n, _name

# First-person creatures the narrator still reads (N), for the user to decide (the report lists them).
NARRATOR_TALKERS = {11957: "Great Cat Spirit", 272054: "Avatar of Saeyleenan", 5955: "Tooga (a sea turtle)",
                    6271: "Mouse (\"I need a cookie, see? Nyeah!\")", 13602: "The Abominable Greench (Sacks)"}

# The narrator choice (the `narrators` stage made the comparison clips; the reasons are in the report).
NARRATOR_LIBRARY_CMP = ("narrator_alliance", "narrator_alliance_v2", "narrator_alliance_old", "narrator_horde")

UNDEAD = ("undeadmaledarknpc", "undeadmalestandardnpc", "undeadmalewarriornpc", "undeadfemalemagicnpc",
          "undeadfemalestandardnpc", "undeadfemalewarriornpc")
NARRATOR_LIBRARY = ("narrator_alliance", "narrator_alliance_v2", "narrator_alliance_old", "narrator_horde")

# Pools for silent character models: the race/sex's generic greeting sets sorted by name (REPORT.md section 3).
POOL_RACES = {"human": "human", "dwarf": "dwarf", "gnome": "gnome", "nightelf": "nightelf", "orc": "orc",
              "undead": "undead", "tauren": "tauren", "troll": "troll", "goblin": "goblin"}


# ================================================================================================================
# small helpers
# ================================================================================================================
def say(*a):
    print(*a, flush=True)


def ensure(p):
    os.makedirs(p, exist_ok=True)
    return p


def load_json(p, default=None):
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    return default


def save_json(p, data):
    ensure(os.path.dirname(p))
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, p)


def state():
    return load_json(STATE_JSON, {"extract": {}, "asr": {}, "made": {}, "tests": {}, "library": []})


def save_state(s):
    save_json(STATE_JSON, s)


def research_file(name):
    """A research input: output/voice_v2/inputs/<name>, copied there from the research folder on first use."""
    dst = os.path.join(INPUTS, name)
    if not os.path.exists(dst):
        src = os.path.join(RESEARCH, name)
        if not os.path.exists(src):
            sys.exit(f"missing input {name}: not in {INPUTS} nor in {RESEARCH} (set MELLOUI_VOICE_RESEARCH)")
        ensure(INPUTS)
        shutil.copyfile(src, dst)
    return dst


# ================================================================================================================
# Ogg (standard library): validation and length
# ================================================================================================================
def ogg_info(data: bytes) -> dict:
    """{'channels', 'rate', 'seconds'} of an Ogg Vorbis file; raises ValueError when it is not one."""
    if data[:4] != b"OggS" or len(data) < 64:
        raise ValueError("not an Ogg file")
    nseg = data[26]
    off = 27 + nseg
    if data[off:off + 7] != b"\x01vorbis":
        raise ValueError("first packet is not a Vorbis identification header")
    channels = data[off + 11]
    rate = struct.unpack_from("<I", data, off + 12)[0]
    if not rate:
        raise ValueError("sample rate 0")
    i = data.rfind(b"OggS")
    gran = -1
    while i >= 0:
        if i + 14 <= len(data) and data[i + 4] == 0:
            g = struct.unpack_from("<q", data, i + 6)[0]
            if g >= 0:
                gran = g
                break
        i = data.rfind(b"OggS", 0, i)
    if gran < 0:
        raise ValueError("no page with a granule position")
    return {"channels": channels, "rate": rate, "seconds": round(gran / rate, 3)}


def ogg_file_info(path):
    with open(path, "rb") as f:
        return ogg_info(f.read())


# ================================================================================================================
# voicegen client (token never printed)
# ================================================================================================================
def _token():
    """The bearer token: env VG_TOKEN, else ~/.voicegen_token (utf-8-sig, stripped). Never printed or stored."""
    t = os.environ.get("VG_TOKEN")
    if not t:
        p = os.path.join(os.path.expanduser("~"), ".voicegen_token")
        if os.path.exists(p):
            with open(p, encoding="utf-8-sig") as f:
                t = f.read().strip()
    return t


class VGError(RuntimeError):
    pass


def _call(path, data=None, method=None, ctype=None, timeout=300, auth=True, want_headers=False):
    headers = {}
    if auth:
        tok = _token()
        if not tok:
            raise VGError("no voicegen token: set VG_TOKEN or save it to ~/.voicegen_token")
        headers["Authorization"] = "Bearer " + tok
    if ctype:
        headers["Content-Type"] = ctype
    req = urllib.request.Request(VG + path, data=data, method=method, headers=headers)
    last = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read()
                return (body, dict(r.headers)) if want_headers else body
        except urllib.error.HTTPError as e:
            detail = ""
            try:
                detail = e.read().decode("utf-8", "replace")[:300]
            except Exception:
                pass
            tok = headers.get("Authorization", "")[len("Bearer "):]
            if tok:
                detail = detail.replace(tok, "***")   # never echo the token, even if a server would
            raise VGError(f"{method or ('POST' if data else 'GET')} {path}: HTTP {e.code} {detail}") from None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            last = e
            time.sleep(5 * (attempt + 1))
    raise VGError(f"{path}: network error {type(last).__name__}: {getattr(last, 'reason', last)}")


def vg_health():
    return json.loads(_call("/v1/health", auth=False, timeout=30))


def vg_voices():
    return json.loads(_call("/v1/voices", timeout=60))


def _multipart(paths):
    boundary = uuid.uuid4().hex
    body = bytearray()
    for p in paths:
        with open(p, "rb") as f:
            blob = f.read()
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"files\"; "
                 f"filename=\"{os.path.basename(p)}\"\r\nContent-Type: audio/ogg\r\n\r\n").encode("utf-8")
        body += blob + b"\r\n"
    body += f"--{boundary}--\r\n".encode("utf-8")
    return bytes(body), "multipart/form-data; boundary=" + boundary


def vg_asr(paths):
    body, ctype = _multipart(paths)
    data = json.loads(_call("/v1/asr", body, "POST", ctype, timeout=600))
    return data if isinstance(data, list) else data.get("results", data)


def vg_make_voice(name, paths, seconds=REF_SECONDS):
    if not KEY_RE.match(name.replace("-", "_")):
        raise VGError("bad voice name " + name)
    body, ctype = _multipart(paths)
    return json.loads(_call(f"/v1/voices/{name}?seconds={seconds}&pick=asr", body, "POST", ctype, timeout=900))


def vg_voice_wav(name):
    return _call(f"/v1/voices/{name}.wav", timeout=120)


def vg_say(text, voice, seed=None, extra=None):
    job = {"text": text, "voice": voice}
    if seed is not None:
        job["seed"] = seed
    job.update(extra or {})
    body, headers = _call("/v1/say", json.dumps(job).encode("utf-8"), "POST", "application/json", timeout=300,
                          want_headers=True)
    seed_used = None
    for k, v in headers.items():
        if k.lower() == "x-seed":
            seed_used = v
    return body, seed_used


def wait_idle(max_minutes=30):
    """Etiquette: the GPUs are shared. Wait while a batch runs or is queued (poll every 60 s, give up after 30 min)."""
    t0 = time.time()
    while True:
        h = vg_health()
        if not h.get("ok"):
            raise VGError("voicegen health is not ok")
        if not h.get("running") and not h.get("queued"):
            return h
        if time.time() - t0 > max_minutes * 60:
            raise VGError("voicegen stayed busy for 30 minutes; try again later")
        say(f"  voicegen busy (running {len(h.get('running') or [])}, queued {h.get('queued')}); waiting 60 s")
        time.sleep(60)


# ================================================================================================================
# client data: DB2 tables, listfile, CASC
# ================================================================================================================
_lf = None


def listfile():
    global _lf
    if _lf is None:
        _lf = {}
        with open(LISTFILE, encoding="utf-8", errors="replace") as f:
            for line in f:
                a, _, b = line.rstrip("\n").partition(";")
                if a.isdigit():
                    _lf[int(a)] = b
    return _lf


def kit_files():
    out = defaultdict(list)
    with open(os.path.join(DB2, "SoundKitEntry.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            out[int(r["SoundKitID"])].append(int(r["FileDataID"]))
    return out


def resolve_group(g, kits=None):
    """[(fdid, file name)] of a candidate group, in a stable order."""
    lf = listfile()
    out = []
    if g.get("fdids"):
        out += [(f, os.path.basename(lf.get(f, f"fdid_{f}.ogg"))) for f in g["fdids"]]
    if g.get("kits"):
        kits = kits or kit_files()
        for k in g["kits"]:
            out += [(f, os.path.basename(lf.get(f, f"kit{k}_{f}.ogg"))) for f in kits.get(k, [])]
    if g.get("folder"):
        folder = g["folder"].lower() + "/"
        inc = re.compile(g["include"], re.I) if g.get("include") else None
        exc = re.compile(g["exclude"], re.I) if g.get("exclude") else None
        hits = sorted((os.path.basename(p), f) for f, p in lf.items() if p.lower().startswith(folder)
                      and "/" not in p[len(folder):] and p.lower().endswith(".ogg"))
        for name, f in hits:
            if inc and not inc.search(name):
                continue
            if exc and exc.search(name):
                continue
            out.append((f, name))
    seen, uniq = set(), []
    for f, n in out:
        if f not in seen:
            seen.add(f)
            uniq.append((f, n))
    if g.get("limit"):
        uniq = uniq[:g["limit"]]
    return uniq


def casc():
    import importlib.util
    spec = importlib.util.spec_from_file_location("casc_local", CASC_READER)
    if not spec or not os.path.exists(CASC_READER):
        sys.exit("CASC reader not found: " + CASC_READER + " (set MELLOUI_CASC_LOCAL)")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.CASC(WOW, PRODUCT)


# ================================================================================================================
# identities -> voice keys
# ================================================================================================================
def library_names(st=None):
    st = st or state()
    lib = st.get("library") or []
    if not lib:
        lib = [v["name"] for v in load_json(research_file("vg_voices.json"), [])]
    return set(lib)


def load_identities():
    """identity -> {'quest': n, 'all': n, 'examples': [...], 'entries': [...]} from npc_voice_map.csv."""
    out = OrderedDict()
    with open(research_file("npc_voice_map.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            i = r["voice_identity"]
            d = out.setdefault(i, {"quest": 0, "all": 0, "examples": [], "entries": []})
            d["all"] += 1
            d["quest"] += 1 if r["quest_npc"] == "1" else 0
            d["entries"].append(int(r["entry"]))
            if len(d["examples"]) < 3:
                d["examples"].append(f"{r['name']} ({r['entry']})")
    return out


def pools(lib):
    out = OrderedDict()
    for race in POOL_RACES:
        for sex, word in (("m", "male"), ("f", "female")):
            g = sorted(n for n in lib if re.fullmatch(f"{race}{word}[a-z]+npc", n))
            if g:
                out[f"{race}_{sex}"] = g
    return out


def map_identity(ident, lib, made_ok):
    """(voice key, how, why). how: library | made | stand-in | pool | narrator."""
    creature = ident.startswith("creature:")
    if not creature and not ident.startswith("unnamed_kit") and not ident.endswith("what") and ident + "npc" in lib:
        return ident + "npc", "library", "the game's own greeting set, as a library voice of the same name"
    if not creature and ident in lib:
        return ident, "library", "named character: library voice of the same name"
    what = {"abominationwhat": "abomination", "necromancerwhat": "necromancer", "dryadwhat": "dryad",
            "satyrewhat": "satyre", "peonwhat": "peon"}
    if ident in what:
        return what[ident], "library", "the unit greeting set, library voice under its short name"
    if ident == "peasantwhat":
        return "wc3_peasant", "made" if "wc3_peasant" in made_ok else "stand-in", "peasant unit voice"
    if ident == "witchdoctorwhat":
        return "wc3_witchdoctor", "made" if "wc3_witchdoctor" in made_ok else "stand-in", "witch doctor unit voice"
    if ident in ("unnamed_kit353056", "unnamed_kit353064"):
        return "skyborne_female", "made", "Skyborne female greeting kits (made earlier from kits 353056 + 353064)"
    if ident in ("unnamed_kit353070", "unnamed_kit353076"):
        return "skyborne_male", "made", "Skyborne male greeting kits (made earlier from kits 353070 + 353076)"
    if ident in ("unnamed_kit368869", "unnamed_kit347830"):
        k = "skyborne_f" + ident[len("unnamed_kit"):]
        if k in made_ok:
            return k, "made", "rare Skyborne female greeting kit, its own voice"
        return "skyborne_female", "made", "rare Skyborne female kit: under 6 s of clean speech, so skyborne_female"
    if creature:
        body = ident[len("creature:"):]
        m = re.fullmatch(r"(human|dwarf|gnome|nightelf|orc|undead|tauren|troll|goblin)_(m|f|n)", body)
        if m:
            sex = "m" if m.group(2) == "n" else m.group(2)
            return f"pool:{m.group(1)}_{sex}", "pool", "silent character model: its race/sex pool by crc32(entry)"
        if body == "model:humanmalecaster":
            return "pool:human_m", "pool", "human male caster model: the human male pool by crc32(entry)"
        if body == "model:madscientist":
            return "pool:human_m", "pool", "mad scientist (a human male model): the human male pool by crc32(entry)"
        if body == "highelf_f":
            return "npcbloodelffemalestandard", "library", "high elf female: the blood elf female library voice"
        if body == "dryad_f":
            return "dryad", "library", "a dryad model: the dryad unit voice (library)"
        fam = [
            (r"(ogre_.*|giant_.*|model:ogre)", "creature_ogre"),
            (r"(dragon_.*|model:dragonspawn|model:horisath)", "creature_dragon"),
            (r"keeper_m", "creature_keeper"),
            (r"(treant_n|model:ancientoflore|model:ancientofwar)", "creature_ancient"),
            (r"furbolg_.*", "creature_furbolg"),
            (r"(elemental_.*|model:.*elemental.*)", "creature_elemental"),
            (r"(imp_m|model:imp)", "creature_imp"),
            (r"demon_m", "creature_demon"),
            (r"succubus_f", "creature_succubus"),
            (r"centaur_.*", "creature_centaur"),
            (r"naga_f", "creature_naga_f"),
            (r"naga_m", "creature_naga_m"),
            (r"spirit_.*", "creature_spirit"),
            (r"gnoll_.*", "creature_gnoll"),
            (r"(model:humanfemalekid|model:orcfemalekid)", "creature_child_f"),
            (r"model:orcmalekid", "creature_child_m"),
        ]
        for rx, key in fam:
            if re.fullmatch(rx, body):
                if key in FAMILY_LIBRARY and FAMILY_LIBRARY[key] in lib:
                    return key, "library", (CANDIDATES.get(key, {}).get("what", key)
                                            + f": the library's family voice {FAMILY_LIBRARY[key]}")
                if key == "creature_keeper" and key not in made_ok:
                    return "creature_ancient", "stand-in", "keeper: no keeper voice was made, so the ancient voice"
                how = "made" if key in made_ok else "stand-in"
                return key, how, CANDIDATES.get(key, STAND_INS.get(key, {})).get("what", key)
        return "narrator_neutral", "narrator", "critter, beast or object shown as a creature: the narrator reads it"
    if ident == "emitter_dalaran_petstore_frog":
        return "narrator_neutral", "narrator", "a frog (Umpi): the narrator reads it"
    return None, "unmapped", "no rule"


# ================================================================================================================
# stages
# ================================================================================================================
def cmd_plan(args):
    st = state()
    lib = library_names(st)
    made_ok = {k for k, v in st.get("made", {}).items() if v.get("ok")}
    ids = load_identities()
    rows = Counter()
    for ident, d in ids.items():
        key, how, why = map_identity(ident, lib, made_ok)
        rows[how] += 1
        if how != "library" or args.verbose:
            say(f"{ident:40} {d['quest']:4}/{d['all']:<4} -> {key:28} [{how}] {why}")
    say("identities:", len(ids), dict(rows))
    if st.get("asr"):
        say(f"\nASR verdicts (clean = usable, >= {MIN_CLIP_SECONDS} s, not skipped by hand):")
        for key in CANDIDATES:
            g, _ = chosen_group(st, key)
            tried = []
            for lab, v in st["asr"].get(key, {}).items():
                gg = next(x for x in CANDIDATES[key]["groups"] if x["label"] == lab)
                tried.append(f"{lab} {group_clean(gg, v):.1f} s" + (" (rejected)" if gg.get("reject") else ""))
            say(f"  {key:20} -> {'MAKE from ' + g['label'] if g else 'stand-in':32} [{', '.join(tried)}]")
    kits = kit_files()
    say("\nreference candidates:")
    for key, c in CANDIDATES.items():
        for g in c["groups"]:
            files = resolve_group(g, kits)
            say(f"  {key:20} {g['label']:22} {len(files):3} clips  {', '.join(n for _, n in files[:4])}")


def cmd_extract(args):
    st = state()
    kits = kit_files()
    c = None
    for key, cand in CANDIDATES.items():
        if args.only and key not in args.only:
            continue
        for g in cand["groups"]:
            files = resolve_group(g, kits)
            out = ensure(os.path.join(REFS, key, g["label"]))
            got = []
            for fdid, name in files:
                dst = os.path.join(out, f"{fdid}_{re.sub(r'[^A-Za-z0-9_.-]', '_', name)}")
                if not dst.lower().endswith(".ogg"):
                    dst += ".ogg"
                if not os.path.exists(dst):
                    if c is None:
                        say("opening the local CASC storage (read-only) ...")
                        c = casc()
                    try:
                        data = c.get(fdid)
                    except Exception as e:  # missing or encrypted file: skip it
                        say(f"  {key}/{g['label']}: {fdid} not readable ({type(e).__name__})")
                        continue
                    try:
                        ogg_info(data)
                    except ValueError as e:
                        say(f"  {key}/{g['label']}: {fdid} {name} is not Ogg Vorbis ({e}); skipped")
                        continue
                    with open(dst, "wb") as f:
                        f.write(data)
                try:
                    info = ogg_file_info(dst)
                except ValueError:
                    continue
                if info["seconds"] < 0.3:   # empty placeholder files (a few vo_703 names hold 0 s)
                    continue
                got.append({"fdid": fdid, "name": name, "file": os.path.relpath(dst, V2).replace("\\", "/"),
                            "seconds": info["seconds"], "channels": info["channels"], "rate": info["rate"]})
            st["extract"].setdefault(key, {})[g["label"]] = got
            say(f"  {key:20} {g['label']:22} {len(got):3} clips, {sum(x['seconds'] for x in got):6.1f} s")
    save_state(st)


def _asr_group(files):
    rows = []
    for i in range(0, len(files), 20):
        chunk = files[i:i + 20]
        res = vg_asr([os.path.join(V2, x["file"]) for x in chunk])
        by_name = {os.path.basename(str(r.get("file", ""))): r for r in res if isinstance(r, dict)}
        for x in chunk:
            r = by_name.get(os.path.basename(x["file"]), {})
            rows.append({"file": x["file"], "fdid": x["fdid"], "seconds": float(r.get("seconds") or x["seconds"]),
                         "text": r.get("text", ""), "language": r.get("language", ""), "usable": bool(r.get("usable")),
                         "why": r.get("why", "")})
    return rows


def cmd_asr(args):
    st = state()
    h = wait_idle()
    say("voicegen:", h.get("box_ui"), "idle")
    for key, groups in st["extract"].items():
        if args.only and key not in args.only:
            continue
        for label, files in groups.items():
            if not files:
                st["asr"].setdefault(key, {})[label] = {"clips": [], "clean": 0.0, "usable": 0}
                continue
            prev = st["asr"].get(key, {}).get(label)
            if prev and not args.force and len(prev.get("clips", [])) == len(files):
                continue
            rows = _asr_group(files)
            clean = round(sum(r["seconds"] for r in rows if r["usable"]), 2)
            st["asr"].setdefault(key, {})[label] = {"clips": rows, "clean": clean,
                                                    "usable": sum(1 for r in rows if r["usable"])}
            save_state(st)
            say(f"  {key:20} {label:22} usable {sum(1 for r in rows if r['usable']):2}/{len(rows):<2} "
                f"clean {clean:5.1f} s" + ("   PASS" if clean >= MIN_CLEAN_SECONDS else ""))
    save_state(st)


def _heard_ok(heard):
    if not heard:
        return False, "empty"
    words = re.findall(r"[A-Za-z']+", heard)
    odd = len(re.findall(r"[^\x00-\x7F’–—…]", heard))
    if odd:
        return False, f"{odd} non-English characters"
    if len(words) < 6:
        return False, f"only {len(words)} words"
    return True, f"{len(words)} words of plain English"


def clean_clips(g, a):
    """The clips that count as clean speech: ASR usable, at least MIN_CLIP_SECONDS long (the service mumbles on very
    short lines), and not skipped by hand after reading the transcripts (garbled = not clean)."""
    if not a:
        return []
    skip = set(g.get("skip") or [])
    return [c for c in a["clips"] if c["usable"] and c["seconds"] >= MIN_CLIP_SECONDS and c["fdid"] not in skip]


def group_clean(g, a):
    return round(sum(c["seconds"] for c in clean_clips(g, a)), 2)


def chosen_group(st, key):
    """The first group (in preference order) with >= 6 s of clean speech that was not rejected, or (None, None)."""
    for g in CANDIDATES[key]["groups"]:
        a = st["asr"].get(key, {}).get(g["label"])
        if a and not g.get("reject") and group_clean(g, a) >= MIN_CLEAN_SECONDS:
            return g, a
    return None, None


def cmd_make(args):
    st = state()
    lib_now = vg_voices()
    st["library"] = sorted(v["name"] for v in lib_now if isinstance(v, dict) and v.get("name"))
    save_state(st)
    ours = {v.get("service") for v in st["made"].values() if v.get("ok")} | {"skyborne_female", "skyborne_male"}
    for key, cand in CANDIDATES.items():
        if args.only and key not in args.only:
            continue
        service = cand.get("service", key)
        g, a = chosen_group(st, key)
        if not g:
            st["made"][key] = {"ok": False, "service": None, "why": "no group with 6 s of clean speech"}
            say(f"  {key:20} stand-in ({st['made'][key]['why']})")
            continue
        prev = st["made"].get(key)
        if prev and prev.get("ok") and prev.get("group") == g["label"] and not args.force:
            say(f"  {key:20} already made as {prev['service']}")
            continue
        if service in st["library"] and service not in ours:
            st["made"][key] = {"ok": False, "service": None, "why": f"name {service} is taken in the library"}
            say(f"  {key:20} REFUSED: {service} exists in the library and is not ours")
            continue
        clips = sorted(clean_clips(g, a), key=lambda c: -len(c["text"].split()))[:20]
        wait_idle()
        reply = vg_make_voice(service, [os.path.join(V2, c["file"]) for c in clips])
        save_json(os.path.join(MADE_DIR, key + ".json"), reply)
        ok_heard, heard_why = _heard_ok(reply.get("heard", ""))
        warn = reply.get("warning")
        ok = bool(not warn and ok_heard and float(reply.get("seconds") or 0) >= MIN_CLEAN_SECONDS)
        wav = vg_voice_wav(service)
        with open(os.path.join(MADE_DIR, key + "_reference.wav"), "wb") as f:
            f.write(wav)
        used = [x for x in reply.get("files", []) if isinstance(x, dict) and x.get("used")]
        st["made"][key] = {"ok": ok, "service": service, "group": g["label"], "why_group": g["why"],
                           "seconds": reply.get("seconds"), "heard": reply.get("heard"), "heardCheck": heard_why,
                           "warning": warn, "uploaded": len(clips), "used": len(used),
                           "fdids": [c["fdid"] for c in clips],
                           "usedFdids": [int(os.path.basename(str(x.get("file"))).split("_")[0]) for x in used
                                         if os.path.basename(str(x.get("file"))).split("_")[0].isdigit()],
                           "made": time.strftime("%Y-%m-%dT%H:%M:%S")}
        save_state(st)
        say(f"  {key:20} made {service}: {reply.get('seconds')} s from {len(used)}/{len(clips)} clips"
            + (f"  WARNING {warn}" if warn else "") + f"; heard: {heard_why}")
    # the library as it is now, with the new voices in it (voices.json checks its services against this)
    st["library"] = sorted(v["name"] for v in vg_voices() if isinstance(v, dict) and v.get("name"))
    save_state(st)


def voice_settings(key, vj):
    v = vj["voices"][key]
    out = {"voice": v.get("service", key), "seed": v.get("seed", vj.get("defaultSeed", DEFAULT_SEED))}
    for f in ("ghoul", "tempo", "act"):
        if f in v:
            out[f] = v[f]
    return out


def _tiny_batch(jobs, label):
    """A tiny batch (a handful of short test lines) for settings /v1/say ignores (ghoul, tempo, act: measured
    2026-09-28, tempo 0.7 gave the same 8.12 s). Waits for an idle box, polls every 15 s, downloads each clip,
    deletes the batch on the server. Returns {job id: (ogg bytes, seeds)}."""
    wait_idle()
    name = f"melloui-v2-{label}-{time.strftime('%Y%m%d-%H%M')}"
    b = json.loads(_call("/v1/batches", json.dumps({"name": name, "jobs": jobs}).encode("utf-8"), "POST",
                         "application/json"))
    bid = b["id"]
    say(f"  batch {name}: {len(jobs)} jobs, {b.get('speech_minutes')} speech minutes")
    try:
        t0 = time.time()
        while True:
            stt = json.loads(_call(f"/v1/batches/{bid}"))
            if stt.get("state") in ("done", "failed", "cancelled", "finished", "complete", "completed"):
                break
            if time.time() - t0 > 1800:
                raise VGError("test batch did not finish in 30 minutes")
            time.sleep(15)
        seeds = {}
        try:
            for j in json.loads(_call(f"/v1/batches/{bid}/jobs")):
                if isinstance(j, dict):
                    seeds[j.get("id")] = j.get("seed", j.get("seeds"))
        except (VGError, ValueError):
            pass
        out = {}
        for j in jobs:
            out[j["id"]] = (_call(f"/v1/batches/{bid}/clips/{j['id']}.ogg"), seeds.get(j["id"]))
        return out
    except KeyboardInterrupt:
        _call(f"/v1/batches/{bid}/cancel", b"", "POST")
        raise
    finally:
        try:
            _call(f"/v1/batches/{bid}", method="DELETE")
        except VGError:
            pass


def cmd_test_alts(args, st):
    """One /v1/say + read-back per library alternate (ALTERNATES) into voice_tests/alt_<name>.ogg."""
    lib = set(st.get("library") or [])
    names = [a for alts in ALTERNATES.values() for a in alts if a in lib]
    names = [a for a in names if args.force or "file" not in st["tests"].get("alt:" + a, {})]
    if not names:
        return
    wait_idle(60)
    outs = []
    for name in names:
        out = os.path.join(TESTS_DIR, f"alt_{name}.ogg")
        try:
            data, seed_used = vg_say(TEST_LINE_NPC, name, DEFAULT_SEED)
        except VGError as e:
            st["tests"]["alt:" + name] = {"error": str(e)}
            say(f"  alt {name}: {e}")
            continue
        with open(out, "wb") as f:
            f.write(data)
        info = ogg_info(data)
        st["tests"]["alt:" + name] = {"file": os.path.relpath(out, V2).replace("\\", "/"), "text": TEST_LINE_NPC,
                                      "voice": name, "seed": DEFAULT_SEED, "seedUsed": seed_used, "filters": {},
                                      "seconds": info["seconds"], "wps": round(len(TEST_LINE_NPC.split()) / info["seconds"], 2),
                                      "bytes": len(data), "kind": "alt", "via": "say"}
        outs.append((name, out))
    if outs:
        heard = {os.path.basename(str(r.get("file", ""))): r for r in vg_asr([p for _, p in outs]) if isinstance(r, dict)}
        for name, out in outs:
            t = st["tests"]["alt:" + name]
            t["heardBack"] = heard.get(os.path.basename(out), {}).get("text", "")
            t["match"] = word_match(t["text"], t["heardBack"])
            say(f"  alt {name:28} {t['seconds']:5.1f} s  heard back {t['match']:.0%}: {t['heardBack']}")
    save_state(st)


def refresh_library(st):
    """GET /v1/voices into voices_state.json 'library' (the list voices.json is checked against)."""
    names = sorted(v["name"] for v in vg_voices() if isinstance(v, dict) and v.get("name"))
    if names:
        st["library"] = names
        save_state(st)
    return set(names)


def test_of_service(st, service):
    """An existing plain test line (no filters) of a voicegen voice, from any test stage, or None."""
    for k, t in st.get("tests", {}).items():
        if t.get("file") and t.get("voice") == service and not t.get("filters") and \
                os.path.exists(os.path.join(V2, t["file"])):
            return k, t
    return None


def used_voices(vj, rows=None, spk=None):
    """voice key -> speaking NPCs, for the voices speaking NPCs get from voices.json."""
    rows = map_rows() if rows is None else rows
    spk = speakers() if spk is None else spk
    out = defaultdict(list)
    for n in spk:
        if n in rows:
            out[resolve_npc(n, rows[n], vj)].append(n)
    return out


def service_of(key, vj):
    return vj["voices"].get(key, {}).get("service", key)


def baseline_services(spk):
    """The voicegen voices speaking NPCs used before the re-map (baseline/), or None without a baseline."""
    bj = load_json(os.path.join(BASELINE, "voices.json"))
    brows = map_rows(os.path.join(BASELINE, "npc_voices.csv"))
    if not bj or not brows:
        return None
    return {service_of(brows[n]["voice"], bj) for n in spk if n in brows}


def cmd_test_used(args, st, vj):
    """One /v1/say of the NPC test line for every voicegen voice that speaking NPCs use now and did not use before
    the re-map (baseline/) and that has no plain test line yet (voice_tests/used_<service>.ogg), then an ASR
    read-back. --all-used: every voice in use without a test line."""
    lib = refresh_library(st)
    spk = speakers()
    before = set() if args.all_used else (baseline_services(spk) or set())
    todo = []
    for key in sorted(used_voices(vj, spk=spk)):
        v = vj["voices"].get(key, {})
        svc = v.get("service", key)
        if svc.startswith("narrator") or svc in before or (test_of_service(st, svc) and not args.force):
            continue
        if args.only and key not in args.only and svc not in args.only:
            continue
        if svc not in lib:
            say(f"  {key}: service {svc} is not in the library; no test")
            continue
        todo.append((key, svc, v.get("seed", vj.get("defaultSeed", DEFAULT_SEED))))
    if not todo:
        say("  every voice in use already has a test line")
        return
    wait_idle()
    done = []
    for key, svc, seed in todo:
        out = os.path.join(TESTS_DIR, f"used_{svc}.ogg")
        try:
            data, seed_used = vg_say(TEST_LINE_NPC, svc, seed)
        except VGError as e:
            st["tests"]["used:" + svc] = {"error": str(e)}
            say(f"  {svc}: {e}")
            continue
        with open(out, "wb") as f:
            f.write(data)
        info = ogg_info(data)
        st["tests"]["used:" + svc] = {"file": os.path.relpath(out, V2).replace("\\", "/"), "text": TEST_LINE_NPC,
                                      "voice": svc, "seed": seed, "seedUsed": seed_used, "filters": {},
                                      "seconds": info["seconds"],
                                      "wps": round(len(TEST_LINE_NPC.split()) / info["seconds"], 2),
                                      "bytes": len(data), "kind": "used", "via": "say", "key": key}
        done.append((svc, out))
        say(f"  {svc:32} {info['seconds']:5.1f} s  seed {seed_used}")
    save_state(st)
    if done:
        heard = {os.path.basename(str(r.get("file", ""))): r for r in vg_asr([p for _, p in done]) if isinstance(r, dict)}
        for svc, out in done:
            t = st["tests"]["used:" + svc]
            t["heardBack"] = heard.get(os.path.basename(out), {}).get("text", "")
            t["match"] = word_match(t["text"], t["heardBack"])
            say(f"  {svc:32} heard back {t['match']:.0%}: {t['heardBack']}")
        save_state(st)


def cmd_narrators(args):
    """The narrator comparison: the same narration line in every library narrator (/v1/say, seed 42) next to
    narrator_neutral's own test line, each reference's transcript (/v1/asr of GET /v1/voices/<name>.wav) and an
    ASR read-back of every clip. Saved to voice_tests/narrator_cmp_<name>.ogg and voices_state.json 'narrators'."""
    st = state()
    refresh_library(st)
    ensure(TESTS_DIR)
    cmp_ = st.setdefault("narrators", {})
    wait_idle()
    clips, refs = [], []
    for name in ("narrator_forever",) + NARRATOR_LIBRARY_CMP:
        out = os.path.join(TESTS_DIR, f"narrator_cmp_{name}.ogg")
        ref = os.path.join(TESTS_DIR, f"narrator_ref_{name}.wav")
        if args.force or not os.path.exists(out):
            data, seed_used = vg_say(TEST_LINE_NARRATOR, name, DEFAULT_SEED)
            with open(out, "wb") as f:
                f.write(data)
            cmp_[name] = {"file": os.path.relpath(out, V2).replace("\\", "/"), "seedUsed": seed_used}
        if args.force or not os.path.exists(ref):
            with open(ref, "wb") as f:
                f.write(vg_voice_wav(name))
        info = ogg_file_info(out)
        cmp_.setdefault(name, {}).update({"file": os.path.relpath(out, V2).replace("\\", "/"),
                                          "seconds": info["seconds"],
                                          "wps": round(len(TEST_LINE_NARRATOR.split()) / info["seconds"], 2),
                                          "reference": os.path.relpath(ref, V2).replace("\\", "/")})
        clips.append((name, out))
        refs.append((name, ref))
    heard = {os.path.basename(str(r.get("file", ""))): r for r in vg_asr([p for _, p in clips]) if isinstance(r, dict)}
    for name, out in clips:
        c = cmp_[name]
        c["heardBack"] = heard.get(os.path.basename(out), {}).get("text", "")
        c["match"] = word_match(TEST_LINE_NARRATOR, c["heardBack"])
    heard = {os.path.basename(str(r.get("file", ""))): r for r in vg_asr([p for _, p in refs]) if isinstance(r, dict)}
    for name, ref in refs:
        r = heard.get(os.path.basename(ref), {})
        cmp_[name]["referenceText"] = r.get("text", "")
        cmp_[name]["referenceSeconds"] = r.get("seconds")
    save_state(st)
    for name, _ in clips:
        c = cmp_[name]
        say(f"  {name:22} {c['seconds']:5.1f} s ({c['wps']:.2f} w/s) read back {c['match']:.0%}; reference says: "
            f"{c.get('referenceText', '')[:140]}")


def cmd_test(args):
    """One short test line per new voice (/v1/say at the voice's seed). With --standins also one per stand-in:
    /v1/say when it has no filters, else one tiny batch (the say endpoint ignores ghoul/tempo/act). With --used one
    per library voice that a speaking NPC now uses and that has no test line yet."""
    st = state()
    vj = load_json(VOICES_JSON)
    if not vj:
        sys.exit("run build first (voices.json is needed for the seeds and filters)")
    ensure(TESTS_DIR)
    if args.used:
        cmd_test_used(args, st, vj)
        return
    todo = [(key, "made") for key, m in st["made"].items() if m.get("ok")]
    if args.standins:
        todo += [(key, "stand-in") for key, v in vj["voices"].items() if v.get("source") == "stand-in"]
    if args.alts:
        cmd_test_alts(args, st)
    plan, batch = [], []
    for key, kind in todo:
        if (args.only and key not in args.only) or key not in vj["voices"]:
            continue
        out = os.path.join(TESTS_DIR, f"{key}.ogg" if kind == "made" else f"standin_{key}.ogg")
        if os.path.exists(out) and not args.force:
            continue
        s = voice_settings(key, vj)
        text = TEST_LINE_NARRATOR if key.startswith("narrator") else TEST_LINE_NPC
        extra = {f: s[f] for f in ("ghoul", "tempo", "act") if f in s}
        (batch if extra else plan).append((key, kind, out, s, text, extra))
    results = {}
    if plan:
        wait_idle()
    for key, kind, out, s, text, extra in list(plan):
        for attempt in range(3):
            try:
                data, seed_used = vg_say(text, s["voice"], s["seed"])
                results[key] = (data, seed_used, "say")
                break
            except VGError as e:
                say(f"  {key}: {e}" + ("; retrying in 20 s" if attempt < 2 else "; skipped"))
                if attempt < 2:
                    time.sleep(20)
        if key not in results:
            plan.remove((key, kind, out, s, text, extra))
            st["tests"][key] = {"error": "voicegen /v1/say failed 3 times"}
    if batch:
        jobs = [dict({"id": f"tests/{key}", "text": text, "voice": s["voice"], "seed": s["seed"]}, **extra)
                for key, kind, out, s, text, extra in batch]
        got = _tiny_batch(jobs, "voice-tests")
        for key, kind, out, s, text, extra in batch:
            data, seeds = got[f"tests/{key}"]
            results[key] = (data, seeds, "batch")
    for key, kind, out, s, text, extra in plan + batch:
        data, seed_used, how = results[key]
        info = ogg_info(data)
        with open(out, "wb") as f:
            f.write(data)
        if kind == "made":
            shutil.copyfile(out, os.path.join(MADE_DIR, key + "_test.ogg"))
        words = len(text.split())
        st["tests"][key] = {"file": os.path.relpath(out, V2).replace("\\", "/"), "text": text, "voice": s["voice"],
                            "seed": s["seed"], "seedUsed": seed_used, "filters": extra, "seconds": info["seconds"],
                            "wps": round(words / info["seconds"], 2), "bytes": len(data), "kind": kind, "via": how}
        say(f"  {key:22} {info['seconds']:5.1f} s ({words / info['seconds']:.2f} words/s)  seed {seed_used}  "
            f"{os.path.basename(out)} [{how}]")
    save_state(st)
    # read every new test line back with ASR: the words must be the test line's (a rambling or cut clone shows here)
    done = [(key, os.path.join(V2, st["tests"][key]["file"])) for key, *_ in plan + batch]
    if done:
        heard = {os.path.basename(str(r.get("file", ""))): r for r in vg_asr([p for _, p in done]) if isinstance(r, dict)}
        for key, path in done:
            r = heard.get(os.path.basename(path), {})
            t = st["tests"][key]
            t["heardBack"] = r.get("text", "")
            t["match"] = word_match(t["text"], t["heardBack"])
            say(f"  {key:22} heard back {t['match']:.0%}: {t['heardBack']}")
        save_state(st)


def word_match(expected, got):
    """Share of the expected words found, in order, in what ASR heard (British spellings count)."""
    norm = lambda x: re.sub(r"[^a-z ]", " ", x.lower().replace("traveller", "traveler")).split()
    e, g = norm(expected), norm(got)
    i = hits = 0
    for w in e:
        j = i
        while j < len(g) and g[j] != w:
            j += 1
        if j < len(g):
            hits += 1
            i = j + 1
    extra = max(0, len(g) - len(e))
    return round(max(0.0, (hits - extra) / max(1, len(e))), 3)


def map_rows(path=None):
    """npc -> row of the frozen NPC map (Tools/voice_v2/npc_voices.csv: npc, name, voice, identity, reason ...)."""
    path = path or NPC_VOICES_CSV
    if not os.path.exists(path):
        return OrderedDict()
    with open(path, encoding="utf-8", newline="") as f:
        return OrderedDict((int(r["npc"]), r) for r in csv.DictReader(f))


def npc_table(lib, rows=None):
    """str(npc) -> {voice, rule, name, why}: the per-NPC choices that beat the identity (rule 1 named characters,
    rules 3 / 4 / 5 / N overrides). A named voice missing from the library is skipped (the identity stays)."""
    rows = map_rows() if rows is None else rows
    out = OrderedDict()
    for n, (voice, why) in NAMED_NPCS.items():
        if voice not in lib:
            say(f"  note: {voice} is not in the voicegen library; NPC {n} keeps its identity's voice")
            continue
        out[str(n)] = {"voice": voice, "rule": "1", "name": rows.get(n, {}).get("name", ""), "why": why}
    for n, (voice, rule, why) in NPC_OVERRIDES.items():
        if not (voice in lib or voice in CANDIDATES or voice in STAND_INS or voice == "narrator_neutral"):
            say(f"  note: {voice} is not in the voicegen library; NPC {n} keeps its identity's voice")
            continue
        out[str(n)] = {"voice": voice, "rule": rule, "name": rows.get(n, {}).get("name", ""), "why": why}
    return out


def resolve_npc(npc, row, vj):
    """The voice key voices.json gives an NPC of the map: its per-NPC choice, else its identity (pools by crc32),
    else (an identity voices.json does not list) the frozen row's voice."""
    t = (vj.get("npcs") or {}).get(str(npc))
    if t:
        return t["voice"]
    key = vj["identities"].get(row["identity"])
    if key is None:
        return row["voice"]
    if key.startswith("pool:"):
        pl = vj["pools"][key[5:]]
        return pl[zlib.crc32(str(npc).encode()) % len(pl)]
    return key


def speakers(path=LINES_JSON, objects=None):
    """npc -> {'keys': runtime keys it speaks, 'voice': the voiceKey lines.json gives it}. NPC 0 (objects and items,
    the narrator) is left out; pass a dict as `objects` to get its key count and voices there."""
    with open(path, encoding="utf-8") as f:
        man = json.load(f)
    out = {}
    for j in man["jobs"]:
        for l in j["meta"]["lines"]:
            n = l.get("npc")
            if n:
                d = out.setdefault(n, {"keys": 0, "voice": set()})
            elif objects is not None:
                d = objects.setdefault(0, {"keys": 0, "voice": set()})
            else:
                continue
            d["keys"] += 1
            d["voice"].add(j["meta"]["voiceKey"])
    return out


def ensure_baseline():
    """Keep the assignment as it was before the 2026-09-28 re-map (voices.json + npc_voices.csv) in baseline/, once:
    the report's OLD column. Never overwritten."""
    if os.path.isdir(BASELINE) and os.listdir(BASELINE):
        return
    ensure(BASELINE)
    for src in (VOICES_JSON, NPC_VOICES_CSV):
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(BASELINE, os.path.basename(src)))
    with open(os.path.join(BASELINE, "README.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("The NPC -> voice assignment before the re-map against Denis's final library (2026-09-28), kept by "
                "Tools/voice_v2_voices.py as the OLD side of voices_report.md. Never overwritten.\n")
    say("baseline kept ->", BASELINE)


def cmd_build(args):
    ensure_baseline()
    st = state()
    lib = library_names(st)
    made_ok = {k for k, v in st.get("made", {}).items() if v.get("ok")}
    ids = load_identities()
    P = pools(lib)
    voices = OrderedDict()
    identities = OrderedDict()
    for ident, d in ids.items():
        key, how, why = map_identity(ident, lib, made_ok)
        if key is None:
            sys.exit("unmapped identity " + ident)
        identities[ident] = key
    npcs = npc_table(lib)
    used = set(k for k in identities.values() if not k.startswith("pool:"))
    used.update(v["voice"] for v in npcs.values())
    for p, members in P.items():
        if any(v == "pool:" + p for v in identities.values()):
            used.update(members)
    # narrators, and the pilot's narrator alternates
    used.update(("narrator_neutral",) + NARRATOR_LIBRARY)
    for key in sorted(used):
        if key == "narrator_neutral":
            m = st["made"].get(key, {})
            if m.get("ok"):
                voices[key] = {"source": "made", "service": m["service"], "status": "pilot",
                               "reference": {"kits": [351602, 351604, 351605, 351606, 351608, 351609, 351610,
                                                      351611, 351612, 351613, 351614, 351616],
                                             "fdids": m.get("usedFdids") or m.get("fdids"),
                                             "folder": "output/voice_v2/references/narrator_neutral"},
                               "notes": "made from the Forever intro narration; the pilot compares it with "
                                        "narrator_alliance and narrator_horde"}
            else:
                voices[key] = {"source": "stand-in", "service": "narrator_alliance_v2", "status": "pilot",
                               "notes": "the intro narration had under 6 s of clean speech: narrator_alliance_v2"}
            continue
        if key in ("skyborne_female", "skyborne_male"):
            voices[key] = {"source": "made", "status": "ok",
                           "reference": {"kits": [353056, 353064] if key.endswith("female") else [353070, 353076],
                                         "folder": f"output/voice_v2/references/{key}"}}
            if key == "skyborne_female":
                voices[key]["seed"] = 7
            continue
        if key in FAMILY_LIBRARY and FAMILY_LIBRARY[key] in lib:
            alt = FAMILY_LIBRARY[key]
            m = st["made"].get(key, {})
            t = st["tests"].get("alt:" + alt) or (test_of_service(st, alt) or (None, {}))[1]
            voices[key] = {"source": "library", "service": alt, "status": "ok",
                           "notes": CANDIDATES[key]["what"] + f". Rule 3: Denis's library family voice {alt} "
                                    f"(test line read back {t.get('match', 0):.0%})."
                                    + (f" The voice this pipeline made ({m['service']}, from {m['group']}) stays on "
                                       "the server, unused." if m.get("ok") else "")}
            continue
        if key in CANDIDATES:
            m = st["made"].get(key, {})
            if m.get("ok"):
                v = {"source": "made", "status": "pilot"}
                if m["service"] != key:
                    v["service"] = m["service"]
                v["reference"] = {"group": m["group"], "fdids": m.get("usedFdids") or m.get("fdids"),
                                  "folder": f"output/voice_v2/references/{key}/{m['group']}"}
                if "kits" in (next((g for g in CANDIDATES[key]["groups"] if g["label"] == m["group"]), {})):
                    v["reference"]["kits"] = next(g for g in CANDIDATES[key]["groups"] if g["label"] == m["group"])["kits"]
                v["notes"] = CANDIDATES[key]["what"] + ". Made from " + m["why_group"] + "."
                voices[key] = v
            else:
                fb = dict(CANDIDATES[key]["fallback"])
                if "key" in fb and "service" not in fb:
                    continue   # mapped to another key instead (creature_keeper -> creature_ancient)
                v = {"source": "stand-in", "service": fb.pop("service"), "status": "pilot"}
                fb.pop("key", None)
                why_fb = fb.pop("why", None)
                v.update(fb)
                v["notes"] = CANDIDATES[key]["what"] + ". No usable client audio (" + (
                    m.get("why") or "not checked") + "); a library voice stands in." + (
                    " Stand-in choice: " + why_fb + "." if why_fb else "")
                voices[key] = v
            continue
        if key in STAND_INS:
            s = STAND_INS[key]
            voices[key] = {"source": "stand-in", "service": s["service"], "status": "pilot",
                           "notes": s["what"] + ". " + s["why"] + "."}
            continue
        if key not in lib:
            sys.exit(f"voice {key} is neither in the library nor made nor a stand-in")
        v = {"source": "library", "status": "ok"}
        if key in UNDEAD:
            v["notes"] = ("no ghoul (Forsaken) filter: the user's decision by ear, 2026-09-28 (voice_seeds.json); "
                          "the pilot has no ghoul A/B pairs")
        if key.startswith("narrator_"):
            v["notes"] = "library narrator (pilot A/B alternate)"
        named = [x for x in npcs.values() if x["voice"] == key and x["rule"] == "1"]
        if named:
            v["notes"] = "rule 1, the character's own voice: " + ", ".join(sorted({x["name"] for x in named}))
        elif key in ("retail_quilboar_m", "retail_centaur_f", "brokennpc1", "brokennpc2"):
            v["notes"] = "rule 3, a race voice of the library: " + ", ".join(
                sorted({x["name"] for x in npcs.values() if x["voice"] == key}))
        elif key == "thorim":
            v["notes"] = "rule 5, closest voice for the titan constructs of Uldum (titannpcgreetings is broken)"
        voices[key] = v
    for k in voices:
        if not KEY_RE.match(k):
            sys.exit("bad voice key " + k)
        if "ghoul" in voices[k]:
            # the user's decision by ear (2026-09-28): no ghoul filter on any voice, undead or not
            sys.exit(f"voice {k} carries ghoul {voices[k]['ghoul']}: the user decided on no ghoul filter anywhere")
    narrators = {"stage": "narrator_neutral",
                 "object": {"1": "narrator_neutral", "2": "narrator_neutral", "3": "narrator_neutral"},
                 "item": {"1": "narrator_neutral", "2": "narrator_neutral", "3": "narrator_neutral"},
                 "gossipObject": "narrator_neutral"}
    out = OrderedDict([
        ("format", "melloui-voices/1"),
        ("created", BUILD_DATE),
        ("defaultSeed", DEFAULT_SEED),
        ("voices", voices),
        ("identities", identities),
        ("pools", OrderedDict((k, v) for k, v in P.items() if any(x == "pool:" + k for x in identities.values()))),
        ("poolRule", "identity 'pool:<race>_<sex>': voice = pools[<race>_<sex>][zlib.crc32(str(npcEntry).encode()) "
                     "% len(pool)] (REPORT.md section 3; the list is sorted by name)"),
        ("npcRule", "an NPC listed in 'npcs' speaks npcs[<id>].voice; every other NPC its identity's voice. Priority "
                    "(voices_report.md): 1 own voice, 2 the display's game set (2p race/sex pool), 3 a library race or "
                    "creature voice, 4 a voice made from game audio, 5 closest voice, N narrator"),
        ("rules", RULES),
        ("npcs", npcs),
        ("narrators", narrators),
    ])
    save_json(VOICES_JSON, out)
    say(f"voices.json: {len(voices)} voices ({Counter(v['source'] for v in voices.values())}), "
        f"{len(identities)} identities, {len(out['pools'])} pools, {len(npcs)} per-NPC choices -> {VOICES_JSON}")


def cmd_copy_skyborne(args):
    """Keep the two Skyborne voices made earlier with the others: reply, reference, test and source clips."""
    src = os.path.join(RESEARCH, "samples")
    for sex in ("female", "male"):
        key = "skyborne_" + sex
        pairs = [(f"skyborne_voice_{sex}.json", f"{key}.json"), (f"{key}_reference.wav", f"{key}_reference.wav"),
                 (f"{key}_test.ogg", f"{key}_test.ogg")]
        for a, b in pairs:
            if os.path.exists(os.path.join(src, a)) and not os.path.exists(os.path.join(MADE_DIR, b)):
                ensure(MADE_DIR)
                shutil.copyfile(os.path.join(src, a), os.path.join(MADE_DIR, b))
        ref = ensure(os.path.join(REFS, key))
        for p in glob.glob(os.path.join(src, key, "*.ogg")):
            if not os.path.exists(os.path.join(ref, os.path.basename(p))):
                shutil.copyfile(p, os.path.join(ref, os.path.basename(p)))


# ================================================================================================================
# report
# ================================================================================================================
def _fmt_filters(v):
    parts = []
    for f in ("ghoul", "tempo", "act"):
        if f in v:
            parts.append(f"{f} {v[f]}")
    if v.get("seed") and v["seed"] != DEFAULT_SEED:
        parts.append(f"seed {v['seed']}")
    return ", ".join(parts)


def _md(x):
    return str(x).replace("|", "/").replace("\n", " ")


def classify(n, row, key, vj):
    """(rule, why) of the voice voices.json gives an NPC of the map (RULES)."""
    t = (vj.get("npcs") or {}).get(str(n))
    if t:
        return t["rule"], t["why"]
    ident = row["identity"]
    v = vj["voices"].get(key, {})
    if key.startswith("narrator"):
        return "N", "critter, beast or object shown as a creature: the narrator reads it"
    if ident in NAMED_LIBRARY and key == ident:
        return "1", "the character's own greeting set"
    if key in FAMILY_LIBRARY and v.get("source") == "library":
        return "3", f"{CANDIDATES[key]['what']}: the library's {v.get('service')}"
    pool_members = {m for ms in (vj.get("pools") or {}).values() for m in ms}
    silent = "crc32" in row.get("reason", "") or "silent" in row.get("reason", "")
    if ident.startswith("creature:"):
        if key in pool_members:
            return "2p", "silent character model: race/sex pool"
        if v.get("source") == "made":
            return "4", CANDIDATES.get(key, {}).get("what", key)
        if v.get("source") == "stand-in":
            return "5", v.get("notes", "")
        return "3", "a race voice of the library"
    if v.get("source") == "stand-in":
        return "5", v.get("notes", "")
    if silent:
        return "2p", "silent display: race/sex pool of game sets"
    if v.get("source") == "made":
        return "2", "the display's own greeting kit, cloned from the game audio"
    return "2", "the game's own voice set of the main display"


def _svc(key, vj):
    return vj["voices"].get(key, {}).get("service", key)


def _voice_cell(key, vj):
    svc = _svc(key, vj)
    return f"`{key}`" if svc == key else f"`{key}` = `{svc}`"


# How this run differs from SPEC.md 4.1 / 4.3 / 4.4 (the spec's table was the starting point).
SPEC_CHANGES = [
    "**Per-NPC table (new):** voices.json has `npcs` (NPC ID -> voice, rule, why), which beats the identity. "
    "`Tools/voice_v2/npc_voices.py` reads it (`resolve_identity`), and `export_lines.py --remap-all` re-maps the "
    "frozen `npc_voices.csv` rows to it (run once on 2026-09-28, on the user's request for the re-map).",
    "**Family keys keep their names, the services change (rule 3 beats rule 4):** `creature_ogre` = "
    "`retail_generic_ogre`, `creature_imp` = `retail_hellish_imp`, `creature_centaur` = `retail_centaur_m`, "
    "`creature_elemental` = `retail_unleashed_elemental`. The spec's own stand-ins for them are gone.",
    "**No ghoul filter anywhere** (the user's decision by ear): not on the six undead voices, and not the spec's 0.5 "
    "brute filter on the gnoll stand-in either. The pilot has no ghoul A/B pairs (`build_pilot` refuses one), and "
    "`build` stops on a voice that carries ghoul.",
    "`creature_dragon`, `creature_keeper`, `creature_ancient`, `creature_succubus`, `creature_naga_f`, `creature_naga_m`, "
    "`creature_child_f`, `creature_child_m`, `wc3_witchdoctor`, `skyborne_f368869` and `skyborne_f347830` are voices "
    "this pipeline made from the client's audio (the spec's stand-ins had usable audio behind them). "
    "`wc3_peasant` stays a stand-in (`humanmalestandardnpc`; its NPC speaks no line).",
    "**New key `creature_keeper`** for `creature:keeper_m` (the spec had keepers on `creature_ancient`).",
    "**`creature:dryad_f`** (Anilia) maps to the library `dryad`, not the narrator.",
    "**Pools:** the spec's \"race/sex pool by crc32(entry)\" rows are identity values `pool:<race>_<sex>` plus a "
    "`pools` table and a `poolRule` in voices.json.",
    "**Where voices.json lives:** `MelloUI-BuildData/output/voice_v2/voices.json` (the exporter reads it there when "
    "`Tools/voice_v2/voices.json` does not exist).",
]

FINDINGS = [
    "The library's `creature_*` voices (ancient, child_f/m, dragon, imp, keeper, naga_f/m, ogre, succubus), "
    "`narrator_forever`, `skyborne_f347830`, `skyborne_f368869` and `wc3_witchdoctor` are this pipeline's own uploads, "
    "not Denis's: each one's reference WAV on the server is byte-identical to `voices_made/<key>_reference.wav` "
    "(checked 2026-09-28). So they rank as rule 4, and Denis's `retail_generic_ogre` and `retail_hellish_imp` (rule 3) "
    "replace the made ogre and imp.",
    "`narrator_alliance` and `narrator_alliance_v2` are the same reference on the server (identical WAV). The three "
    "faction narrators' references are retail quest-NPC dialogue (\"don't make the same mistake I did\", \"Thank you, "
    "champion\", \"You have helped this champion restore balance\"), not narration.",
    "`/v1/say` gives every voice the same length for the same text (all five narrators: 8.4 s = words / 2.5), so the "
    "pace does not tell voices apart; the reference's delivery and room do.",
    "`/v1/say` ignores `ghoul`, `tempo` and `act` (measured: tempo 0.7 gave the same 8.12 s as none).",
    "The first `test --used` run of this re-map tested every voice in use that had no test line yet, not only the "
    "newly used ones: 83 short `/v1/say` lines (about 10 minutes of speech, no batch). The stage now tests only the "
    "voices new against `baseline/` (`--all-used` for the old behaviour). The extra lines are kept in "
    "`voice_tests/used_*.ogg`; every voice in use now has one.",
    "`titannpcgreetings` is broken on the server (a one-word line came back as 58 s; the test line failed with HTTP "
    "500 three times). Worth telling Denis.",
    "Denis renamed three library voices on the evening of 2026-09-28 (the live `GET /v1/voices`, 172 voices): "
    "`retail_quilboar` became `retail_quilboar_m` / `retail_quilboar_f`, `retail_centaur_type_two` became "
    "`retail_centaur_m` / `retail_centaur_f`, and `retail_hakkar` became `retail_hakkar_the_soulflayer`. Mangletooth "
    "speaks `retail_quilboar_m`, the centaur family `retail_centaur_m`, and Uthek the Wise (a female centaur) "
    "`retail_centaur_f`. The saved list `scratchpad/voice/vg_voices.json` still has the old names.",
]

OPEN_QUESTIONS = [
    "**Tirion:** Tirion Fordring (1855) and Lord Tirion Fordring (12126) use Denis's `retail_tirionfordring`. The "
    "library also holds the game's `tirionfordring` greeting set (a later display's). Swapping is one line in "
    "`NAMED_NPCS`.",
    "**Two takes of one character:** `creature_dragon` was made from Azuregos's client lines and now voices the "
    "generic dragons (Awbee, Cyrus Therepentous, Emberstrife, Procrastimond, the Spirit of Lord Valthalak) while "
    "Azuregos himself speaks `retail_azuregos`. `creature_keeper` was made from Keeper Remulos's client lines and "
    "voices the other keepers (Albagorm, Marandis, Celebras, Zaetar's Spirit) while Remulos speaks "
    "`retail_keeper_remulos`. Fine by ear, or should the generic dragons get another voice?",
    "**Closest voices (rule 5), by ear:** Stone Watcher of Norgannon -> `thorim`; Rethiel the Greenwarden, Great Bear "
    "Spirit, Urs'endris and the Spirit of Agamaggan -> `creature_ancient`; Warosh -> the ogre voice; Lord Banehollow "
    "-> `varimathras` (he sounds like Varimathras himself); furbolgs, gnolls, the Spirit Healer and the Forest Wisp "
    "on their stand-ins.",
    "**First-person creatures the narrator still reads:** " + ", ".join(NARRATOR_TALKERS.values()) + ". Give any of "
    "them a voice?",
    "**Highlord Mograine** (242499, the spirit of Alexandros in the Forever Ashbringer quests) keeps "
    "`humanmaleofficialnpc`: `retail_highlord_darion_mograine` is his son Darion, who speaks no line.",
]


def cmd_report(args):
    st = state()
    vj = load_json(VOICES_JSON)
    if not vj:
        sys.exit("run build first")
    lib = library_names(st)
    made_ok = {k for k, v in st.get("made", {}).items() if v.get("ok")}
    rows = map_rows()
    bj = load_json(os.path.join(BASELINE, "voices.json"))
    brows = map_rows(os.path.join(BASELINE, "npc_voices.csv"))
    if not bj or not brows:
        sys.exit("baseline/ is missing (build keeps it on its first run)")
    objs = {}
    spk = speakers(objects=objs)
    new = {n: resolve_npc(n, r, vj) for n, r in rows.items()}
    off_map = sorted(n for n, r in rows.items() if r["voice"] != new[n])
    off_lines = sorted(n for n, d in spk.items() if d["voice"] != {new.get(n)})
    rule_of = {n: classify(n, rows[n], new[n], vj) for n in rows}
    L = []
    w = L.append
    w("# MelloUI_VoiceOverData_v2: voices")
    w("")
    w(f"Built {BUILD_DATE} by `Tools/voice_v2_voices.py` against Denis's final voicegen library ({len(lib)} voices). "
      f"Every NPC of the frozen map (`Tools/voice_v2/npc_voices.csv`, {len(rows)} NPCs) has one voice; "
      f"{len(spk)} of them speak lines in `lines.json`. `voices.json` sits next to this report; the assignment "
      "before this re-map is kept in `baseline/`.")
    w("")
    w("## In short")
    w("")
    w("Priority for each speaking NPC: 1 a voice made for exactly that character; 2 the game's own voice set of its "
      "main display (2p: a silent character model takes its race/sex pool, as before); 3 a race or creature voice of "
      "the library; 4 a voice this pipeline made from game audio, only where 1-3 have nothing; 5 the closest voice, "
      "last resort; N the narrator reads it.")
    w("")
    w("| Rule | Speaking NPCs | Lines (a key per speaker) | Voices | All NPCs in the map |")
    w("|---|---:|---:|---:|---:|")
    tot = Counter()
    for r, name in RULES.items():
        sn = [n for n in spk if rule_of.get(n, ("?",))[0] == r]
        keys = sum(spk[n]["keys"] for n in sn)
        svcs = {_svc(new[n], vj) for n in sn}
        alln = sum(1 for n in rows if rule_of[n][0] == r)
        tot.update({"s": len(sn), "k": keys, "a": alln})
        w(f"| {r}: {name} | {len(sn)} | {keys} | {len(svcs)} | {alln} |")
    all_svc = {_svc(new[n], vj) for n in spk}
    w(f"| **total** | {tot['s']} | {tot['k']} | {len(all_svc)} | {tot['a']} |")
    w("")
    o = objs.get(0, {"keys": 0, "voice": set()})
    w(f"Plus {o['keys']} lines of objects and items (speaker 0), read by "
      + ", ".join(f"`{x}`" for x in sorted(o["voice"])) + ". A plain quest key served for several same-voice "
      "givers counts once per giver here.")
    w("")
    changed = []
    for n in sorted(spk):
        if n not in brows or n not in rows:
            continue
        ok, nk = brows[n]["voice"], new[n]
        osv, nsv = _svc(ok, bj), _svc(nk, vj)
        if (ok, osv) != (nk, nsv):
            changed.append((n, ok, osv, nk, nsv))
    first = sorted({_svc(new[n], vj) for n in spk} - {_svc(brows[n]["voice"], bj) for n in spk if n in brows})
    w(f"- **Changed:** {len(changed)} speaking NPCs ({sum(spk[c[0]]['keys'] for c in changed)} lines) speak another "
      f"voicegen voice now; {len(first)} voices are used for the first time (table below).")
    w(f"- **Checks:** npc_voices.csv agrees with voices.json for {len(rows) - len(off_map)}/{len(rows)} NPCs and "
      f"lines.json for {len(spk) - len(off_lines)}/{len(spk)} speaking NPCs"
      + ("." if not off_map and not off_lines else
         f" (re-run `export_lines.py --remap-all`: {off_map[:8]} {off_lines[:8]})."))
    nsvc = _svc("narrator_neutral", vj)
    w(f"- **Narrator:** `narrator_neutral` (voicegen `{nsvc}`) reads the stage directions, the object and item "
      "quests of every side and object gossip (reasons below).")
    und = [n for n in spk if new[n] in UNDEAD]
    w(f"- **Undead:** the six undead voices carry no ghoul filter now (the user's decision by ear): "
      f"{len(und)} speaking NPCs, {sum(spk[n]['keys'] for n in und)} lines.")
    w("- **Seeds:** `skyborne_female` 7; every other voice 42.")
    w("")
    # narrator
    w("## Narrator")
    w("")
    w("The same narration line in each library narrator (`narrators` stage, seed 42), with what each voice's "
      f"reference says (`/v1/asr` of its reference WAV). Line: \"{TEST_LINE_NARRATOR}\"")
    w("")
    w("| Narrator | Its reference says | Test line | Read back |")
    w("|---|---|---|---:|")
    for name, c in (st.get("narrators") or {}).items():
        w(f"| `{name}` | \"{_md((c.get('referenceText') or '')[:150])}...\" | `{c.get('file')}` "
          f"{c.get('seconds', 0):.1f} s | {c.get('match', 0):.0%} |")
    w("")
    w("**Choice: `narrator_forever` for everything (stage directions, object and item quests on both sides, object "
      "gossip).** Why:")
    w("")
    w("- It is the only one made from real narration: the Forever intro's own narrator (\"Now, a new generation of "
      "Skyborne elves face...\"). It is the game's current narrator voice, calm, deep and even, and names no side.")
    w("- The faction narrators are cloned from retail quest-NPC dialogue: they talk to \"champion\" as characters, "
      "not as a narrator. `narrator_alliance` and `narrator_alliance_v2` are even the same reference, and "
      "`narrator_horde`'s reference is the noisiest of the five (the least quiet floor between words).")
    w("- One narrator for all sides keeps object and item quests of side 3 (both factions) the same as the rest, and "
      "keeps the one-voice rule simple. All five read the line back at 95-100 %, so the choice is about delivery.")
    w("- The faction narrators stay in voices.json: the pilot's one narrator comparison reads P01 (Wanted: Hogger) in "
      "`narrator_neutral` and in `narrator_alliance`; switching is one line in `narrators`.")
    w("")
    # OLD -> NEW
    w("## OLD -> NEW: speaking NPCs whose voice changed")
    w("")
    w("OLD is `baseline/` (the previous run), NEW is `voices.json` now. `key = service` where the addon folder (key) "
      "and the voicegen voice differ.")
    w("")
    w("| NPC | Name | Lines | OLD | NEW | Rule | Why |")
    w("|---:|---|---:|---|---|---|---|")
    order = {r: i for i, r in enumerate(RULES)}
    for n, ok, osv, nk, nsv in sorted(changed, key=lambda c: (order.get(rule_of[c[0]][0], 9), -spk[c[0]]["keys"])):
        r, why = rule_of[n]
        w(f"| {n} | {_md(rows[n]['name'])} | {spk[n]['keys']} | {_voice_cell(ok, bj)} | {_voice_cell(nk, vj)} | {r} | "
          f"{_md(why)} |")
    w("")
    quiet = [(n, brows[n]["voice"], new[n]) for n in rows if n not in spk and n in brows
             and (brows[n]["voice"], _svc(brows[n]["voice"], bj)) != (new[n], _svc(new[n], vj))]
    if quiet:
        w(f"Also re-mapped, but speaking no line today ({len(quiet)}): " + "; ".join(
            f"{n} {_md(rows[n]['name'])} {_voice_cell(a, bj)} -> {_voice_cell(b, vj)}" for n, a, b in sorted(quiet))
          + ".")
        w("")
    # first-time voices
    w("## Voices used for the first time, with their test line")
    w("")
    w(f"One `/v1/say` of \"{TEST_LINE_NPC}\" at the voice's seed, read back with `/v1/asr` (a line made earlier "
      "for the same voice is reused).")
    w("")
    w("| voicegen voice | Key | Rule | Speaking NPCs | Test line | Read back |")
    w("|---|---|---|---|---|---:|")
    for svc in first:
        keys = sorted({new[n] for n in spk if _svc(new[n], vj) == svc})
        who = sorted((n for n in spk if _svc(new[n], vj) == svc), key=lambda n: -spk[n]["keys"])
        rules = sorted({rule_of[n][0] for n in who})
        t = test_of_service(st, svc)
        tt = f"`{t[1]['file']}` {t[1]['seconds']:.1f} s" if t else "-"
        w(f"| `{svc}` | {', '.join('`' + k + '`' for k in keys)} | {', '.join(rules)} | "
          f"{_md(', '.join(rows[n]['name'] for n in who[:5]))}{' ...' if len(who) > 5 else ''} ({len(who)}) | {tt} | "
          f"{(t[1].get('match', 0) if t else 0):.0%} |")
    w("")
    # fallbacks
    w("## Left on a fallback")
    w("")
    w("### Rule 5: the closest voice")
    w("")
    w("| NPC | Name | Lines | Voice | Why |")
    w("|---:|---|---:|---|---|")
    for n in sorted((n for n in spk if rule_of[n][0] == "5"), key=lambda n: -spk[n]["keys"]):
        w(f"| {n} | {_md(rows[n]['name'])} | {spk[n]['keys']} | {_voice_cell(new[n], vj)} | {_md(rule_of[n][1])} |")
    w("")
    nn = [n for n in spk if rule_of[n][0] == "N"]
    w(f"### N: the narrator reads it ({len(nn)} speaking NPCs)")
    w("")
    w("Critters, beasts, machines and objects shown as creatures. Most texts are narration (\"The chicken looks up at "
      "you...\"). These speak in the first person and are the ones to decide by ear: " + "; ".join(
          f"{n} {v}" for n, v in NARRATOR_TALKERS.items()) + ".")
    w("")
    w("All of them: " + ", ".join(f"{_md(rows[n]['name'])} ({n})" for n in sorted(nn)) + ".")
    w("")
    # made voices
    w("## Voices this pipeline made (voices_made/)")
    w("")
    w("| Made voice | Used by speaking NPCs | Note |")
    w("|---|---|---|")
    made_svcs = sorted({m["service"] for m in st["made"].values() if m.get("ok")} | {"skyborne_female", "skyborne_male"})
    unused = []
    for svc in made_svcs:
        who = [n for n in spk if _svc(new[n], vj) == svc]
        keys_now = sorted({k for k, v in vj["voices"].items() if v.get("service", k) == svc})
        if who:
            note = "in use"
        else:
            unused.append(svc)
            if svc in FAMILY_LIBRARY:
                note = f"UNUSED: the key `{svc}` now speaks `{FAMILY_LIBRARY[svc]}` (rule 3 beats rule 4)"
            elif keys_now:
                note = "UNUSED: its key is only used by NPCs that speak no line"
            else:
                note = "UNUSED: no key uses it"
        w(f"| `{svc}` | {len(who)} NPCs, {sum(spk[n]['keys'] for n in who)} lines | {note} |")
    w("")
    w("Unused on the server now: " + (", ".join(f"`{u}`" for u in unused) if unused else "none") + ". Nothing was "
      "deleted; that is the user's call.")
    w("")
    narr = {_svc(k, vj) for k in vj["voices"] if k.startswith("narrator")}
    lib_unused = sorted(lib - all_svc - narr - {"titannpcgreetings"} - set(unused))
    w(f"Library voices no speaking NPC uses ({len(lib_unused)}; the faction narrators, kept as pilot alternates, "
      "and the broken `titannpcgreetings` left out): " + ", ".join(f"`{x}`" for x in lib_unused) + ".")
    w("")
    w("## Changes against SPEC.md 4.1 / 4.3 / 4.4")
    w("")
    for c in SPEC_CHANGES:
        w("- " + c)
    w("")
    w("## Findings about the service")
    w("")
    for c in FINDINGS:
        w("- " + c)
    w("")
    w("## Open questions for the user")
    w("")
    for q in OPEN_QUESTIONS:
        w("- " + q)
    w("")
    w("## Every identity -> voice")
    w("")
    w("The identities of the research map (`npc_voice_map.csv`); the per-NPC table above beats them. "
      "`pool:<race>_<sex>` = `pools[<race>_<sex>][zlib.crc32(str(entry)) % 3]` (sorted by name).")
    w("")
    w("| Identity | Quest NPCs | All NPCs | Voice key | voicegen voice, filters | How | Examples |")
    w("|---|---:|---:|---|---|---|---|")
    ids = load_identities()
    for ident, d in sorted(ids.items(), key=lambda kv: -kv[1]["all"]):
        key, how, why = map_identity(ident, lib, made_ok)
        if key.startswith("pool:"):
            svc = ", ".join(f"`{x}`" for x in vj["pools"][key[5:]])
        else:
            v = vj["voices"].get(key, {})
            svc = f"`{v.get('service', key)}`" + (f", {_fmt_filters(v)}" if _fmt_filters(v) else "")
        w(f"| `{ident}` | {d['quest']} | {d['all']} | `{key}` | {svc} | {how} | {_md(', '.join(d['examples']))} |")
    w("")
    w("## Re-running")
    w("")
    w("`python Tools/voice_v2_voices.py build` rewrites voices.json from the tables in the tool (`NAMED_NPCS`, "
      "`NPC_OVERRIDES`, `KIDS_M`/`KIDS_F`, `FAMILY_LIBRARY`); then `python Tools/voice_v2/export_lines.py --remap-all "
      "--pilot-selection <pilot_selection.json>` re-maps npc_voices.csv and rewrites the manifests; then "
      "`test --used` (one line per newly used voice) and `report`. `narrators` redoes the narrator comparison. The "
      "token comes from `VG_TOKEN` or `~/.voicegen_token` and is never printed or written.")
    w("")
    with open(REPORT_MD, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))
    say("report ->", REPORT_MD)
    say("speaking NPCs per rule: " + ", ".join(
        f"{r} {sum(1 for n in spk if rule_of.get(n, ('?',))[0] == r)}" for r in RULES)
        + f"; changed {len(changed)}; first-time voices {len(first)}; mismatches map {len(off_map)} lines {len(off_lines)}")


# ================================================================================================================
def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stage", choices=["plan", "extract", "asr", "make", "test", "narrators", "build", "report", "all"])
    ap.add_argument("--only", nargs="*", help="only these voice keys")
    ap.add_argument("--force", action="store_true", help="redo work that is already saved")
    ap.add_argument("--standins", action="store_true", help="test: also one line per stand-in")
    ap.add_argument("--alts", action="store_true", help="test: also one line per library alternate (ALTERNATES)")
    ap.add_argument("--used", action="store_true", help="test: one line per voice speaking NPCs newly use (against "
                                                        "baseline/) that has no test line yet (instead of the made voices)")
    ap.add_argument("--all-used", action="store_true", help="test --used: every voice in use without a test line")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    ensure(V2)
    try:
        if args.stage in ("plan",):
            cmd_plan(args)
        if args.stage in ("extract", "all"):
            cmd_copy_skyborne(args)
            cmd_extract(args)
        if args.stage in ("asr", "all"):
            cmd_asr(args)
        if args.stage in ("make", "all"):
            cmd_make(args)
        if args.stage in ("build", "all"):
            cmd_build(args)
        if args.stage in ("test", "all"):
            cmd_test(args)
            if args.stage == "all":
                args.used = True
                cmd_test(args)
        if args.stage == "narrators":
            cmd_narrators(args)
        if args.stage in ("report", "all"):
            cmd_build(args) if args.stage == "report" and not os.path.exists(VOICES_JSON) else None
            cmd_report(args)
    except VGError as e:
        sys.exit("voicegen: " + str(e))


if __name__ == "__main__":
    main()
