"""Read-only source readers for the v2 voice line export (SPEC.md 3.1-3.2).

Every reader here only reads. Nothing is fetched from the internet: the Wowhead pages are the ones already
cached by import_wowhead_quests.py, and the Forever client data is read from files already on this PC.

    cmangos()             the classic-db dump's tables, parsed with a correct reader (NULL -> None, escapes decoded)
    quest_list()          Media/QuestListData.lua: the quests the addon knows (origin 1 Classic, 2 Forever)
    wowhead_quest(path)   one cached Wowhead quest page, BOTH section layouts, page scripts removed first
    wowhead_quests()      every cached quest page
    wowhead_npc_display() NPC ID -> the display ID on its cached Wowhead page
    wowhead_books()       the book text (readable pages) of every cached Forever item / object page
    collector()           the in-game collector store (Forever texts seen in game)
    questcache()          the Forever client's quest cache (questcache.wdb): title, objectives and details
    pagetextcache()       the Forever client's page text cache (pagetextcache.wdb): the pages it was sent
    gameobjectcache_readables()  the readable objects (TEXT / GOOBER with a page) the Forever client has seen
    creaturecache()       the Forever client's creature cache (creaturecache.wdb): the displays the server sent
    hotfix_broadcast()    BroadcastText rows from the Forever client's hotfix cache (extracted CSV)
    db2(name)             a Forever 1.60 client table (CSV extracted by wow.export)

Why a new SQL reader: Tools/extract_npc_voices.parse_sql_values turns an unquoted NULL into the string "NULL"
and keeps only the letter of an escape ("\\n" -> "n"). It stays as it is because build_quest_list.py uses it for
the shipped QuestListData; this reader is separate.
"""
from __future__ import annotations

import csv
import gzip
import hashlib
import html
import json
import os
import pickle
import re
import struct
import sys

sys.dont_write_bytecode = True
TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
from paths import CACHE, OUTPUT  # noqa: E402

ADDON = os.path.dirname(TOOLS)
DUMP = os.path.join(CACHE, "ClassicDB.sql.gz")
QUEST_LIST = os.path.join(ADDON, "Media", "QuestListData.lua")
NPC_VOICE_DATA = os.path.join(ADDON, "Media", "NPCVoiceData.lua")
WOWHEAD = os.path.join(CACHE, "wowhead")
STORE = os.path.join(CACHE, "voice_lines.json")
LISTFILE = os.path.join(CACHE, "verified-listfile.csv")
DB2_DIR = os.environ.get("MELLOUI_DB2_DIR", r"F:\Download-Backup\WoWExport\db2_1.60")
GAME_WDB = os.environ.get("MELLOUI_WDB_DIR", r"F:\World of Warcraft\_classic_beta_\Cache\WDB\enUS")
V2_OUT = os.path.join(OUTPUT, "voice_v2")
PARSE_CACHE = os.path.join(V2_OUT, "_cache")


def sha1_file(path: str) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ------------------------------------------------------------------------------------------ SQL dump
TABLES = {
    "quest_template": ("entry", "Title", "Details", "Objectives", "RequestItemsText", "OfferRewardText",
                       "QuestLevel", "Method", "Type", "QuestFlags", "SpecialFlags"),
    "creature_template": ("Entry", "Name", "SubName", "ModelId1", "ModelId2", "ModelId3", "ModelId4", "Faction",
                          "NpcFlags", "GossipMenuId", "CreatureType", "TrainerType", "TrainerClass"),
    "creature": ("guid", "id"),
    "creature_spawn_entry": ("guid", "entry"),
    "creature_questrelation": None,
    "creature_involvedrelation": None,
    "gameobject_questrelation": None,
    "gameobject_involvedrelation": None,
    "gameobject_template": ("entry", "type", "name", "data0", "data1", "data2", "data3", "data19"),
    "item_template": ("entry", "name", "startquest"),
    "gossip_menu": None,
    "gossip_menu_option": ("menu_id", "id", "option_text", "action_menu_id", "condition_id"),
    "npc_text": None,
    "npc_text_broadcast_text": None,
    "broadcast_text": ("Id", "Text", "Text1", "SoundEntriesID1", "SoundEntriesID2"),
    "npc_gossip": None,
    "questgiver_greeting": ("Entry", "Type", "Text"),
    "trainer_greeting": None,
    "conditions": ("condition_entry", "type", "value1", "value2", "flags", "comments"),
    "game_event": ("entry", "holiday", "description"),
}

_SQL_TOKEN = re.compile(r"'((?:[^'\\]|\\.)*)'|(NULL)|([-+]?[0-9][0-9.eE+-]*)|(\()|(\))", re.S)
_SQL_ESC = {"n": "\n", "r": "\r", "t": "\t", "0": "\0", "Z": "\x1a", "b": "\b", "\\": "\\", "'": "'", '"': '"',
            "%": "\\%", "_": "\\_"}
_SQL_ESC_RE = re.compile(r"\\(.)", re.S)


def _sql_string(raw: str) -> str:
    if "\\" not in raw:
        return raw
    return _SQL_ESC_RE.sub(lambda m: _SQL_ESC.get(m.group(1), m.group(1)), raw)


def _sql_number(tok: str):
    try:
        return int(tok)
    except ValueError:
        try:
            return float(tok)
        except ValueError:
            return tok


def parse_sql_values(body: str):
    """Yield the rows of one INSERT ... VALUES body as lists: str (escapes decoded), int/float, or None for NULL."""
    row = None
    for m in _SQL_TOKEN.finditer(body):
        s, null, num, open_, close = m.groups()
        if open_ is not None:
            row = []
        elif close is not None:
            if row is not None:
                yield row
            row = None
        elif row is None:
            continue
        elif s is not None:
            row.append(_sql_string(s))
        elif null is not None:
            row.append(None)
        else:
            row.append(_sql_number(num))


# The readable texts (books, letters, notes, plaques, signs, tablets): the pages and what shows them. An item
# shows the page chain its PageText starts; a world object of type 9 (TEXT) the chain of data0, a type 10
# (GOOBER) the chain of data7 (its pageId). Read with cmangos(tables=READABLE_TABLES): a cache of its own, so
# the line export's cache (TABLES) is unchanged.
READABLE_TABLES = {
    "page_text": ("entry", "text", "next_page"),
    "item_template": ("entry", "name", "class", "subclass", "PageText", "LanguageID", "PageMaterial", "startquest"),
    "gameobject_template": ("entry", "type", "name", "data0", "data1", "data2", "data7", "data8", "data9"),
}


def cmangos(dump: str = DUMP, tables: dict | None = None) -> dict:
    """{"tables": {name: [row dict]}, "sha1": dump sha1}. Parsed once, then cached under voice_v2/_cache.
    tables: {table: kept columns or None for all}; the line export's TABLES by default."""
    tables = TABLES if tables is None else tables
    digest = sha1_file(dump)
    spec = hashlib.sha1(json.dumps(tables, sort_keys=True).encode()).hexdigest()[:8]   # the kept columns
    pk = os.path.join(PARSE_CACHE, "cmangos_%s_%s.pickle" % (digest[:12], spec))
    if os.path.exists(pk):
        with open(pk, "rb") as fh:
            return pickle.load(fh)
    columns, rows, current = {}, {name: [] for name in tables}, None
    with gzip.open(dump, "rt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("CREATE TABLE `"):
                name = line[14:line.index("`", 14)]
                current = name if name in tables else None
                if current:
                    columns[current] = []
                continue
            if current:
                m = re.match(r"\s*`(\w+)`", line)
                if m:
                    columns[current].append(m.group(1))
                elif line.startswith(")"):
                    current = None
                continue
            if line.startswith("INSERT INTO `"):
                name = line[13:line.index("`", 13)]
                if name not in tables:
                    continue
                cols, keep = columns[name], tables[name]
                for row in parse_sql_values(line[line.index("VALUES") + 6:]):
                    if len(row) != len(cols):
                        raise SystemExit("cmangos %s: a row has %d values for %d columns" % (name, len(row), len(cols)))
                    rec = dict(zip(cols, row))
                    if keep:
                        rec = {k: rec.get(k) for k in keep}
                    rows[name].append(rec)
    missing = [n for n in tables if n not in columns]
    if missing:
        raise SystemExit("cmangos dump lacks tables: %s" % ", ".join(missing))
    out = {"tables": rows, "sha1": digest}
    os.makedirs(PARSE_CACHE, exist_ok=True)
    with open(pk, "wb") as fh:
        pickle.dump(out, fh)
    return out


def text_or_none(v):
    """A DB text value, or None when it is NULL, empty or has no letters (SPEC.md 3.2)."""
    if v is None:
        return None
    v = str(v)
    if v.strip().upper() == "NULL":        # 3 quests store the quoted string 'NULL' (8101, 8110, 8116)
        return None
    return v if re.search(r"[A-Za-z]", v) else None


# ------------------------------------------------------------------------------------------ QuestListData.lua
QL_FIELDS = ("id", "title", "level", "reqLevel", "side", "classMask", "zone", "pickupZone", "giverName", "giverX",
             "giverY", "giverKind", "event", "chain", "dungeon", "attunement", "prevQuest", "giverContinent",
             "giverWX", "giverWY", "giverNPC", "turninName", "turninNPC", "turninZone", "turninContinent",
             "turninWX", "turninWY", "origin")
_LUA_TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|(-?\d+(?:\.\d+)?)')
_LUA_ESC = re.compile(r"\\(\d{1,3}|.)", re.S)


def _lua_string(raw: str) -> str:
    def esc(m):
        c = m.group(1)
        if c.isdigit():
            return chr(int(c))
        return {"n": "\n", "t": "\t", "r": "\r"}.get(c, c)
    s = _LUA_ESC.sub(esc, raw)
    try:                                   # decimal escapes are bytes: re-read them as UTF-8
        return s.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return s


def quest_list(path: str = QUEST_LIST) -> dict:
    """quest ID -> {field: value} for the quests of MelloUI_QuestListData.quests (standard library only)."""
    text = open(path, encoding="utf-8").read()
    start = text.index("\tquests = {")
    out = {}
    for line in text[start:].splitlines()[1:]:
        s = line.strip()
        if not s.startswith("{"):
            if s.startswith("}"):
                break
            continue
        vals = []
        for m in _LUA_TOKEN.finditer(s):
            if m.group(1) is not None:
                vals.append(_lua_string(m.group(1)))
            else:
                n = m.group(2)
                vals.append(float(n) if "." in n else int(n))
        if len(vals) != len(QL_FIELDS):
            raise SystemExit("QuestListData: a quest row has %d fields, expected %d: %s" % (len(vals), len(QL_FIELDS), s[:80]))
        rec = dict(zip(QL_FIELDS, vals))
        out[int(rec["id"])] = rec
    return out


def npc_voice_data(path: str = NPC_VOICE_DATA) -> dict:
    """NPC ID -> MelloUI's race key ("human_m", "undead_n" ...) from Media/NPCVoiceData.lua."""
    src = open(path, encoding="utf-8").read()
    out = {}
    for key, body in re.findall(r'\["(\w+)"\]\s*=\s*((?:"[^"]*"\s*(?:\.\.\s*)?)+)', src):
        for n in re.findall(r"\d+", "".join(re.findall(r'"([^"]*)"', body))):
            out[int(n)] = key
    return out


# ------------------------------------------------------------------------------------------ Wowhead pages
_SCRIPT_RE = re.compile(r"<(script|style)\b.*?</\1\s*>", re.S | re.I)
_TAG_RE = re.compile(r"<[^>]+>")
SECTION_END = r"(?:<table|<div|<h2|<script|<ul|<pre|$)"


def wowhead_text(fragment: str) -> str:
    """One page section -> source text: <br> and line breaks are paragraph breaks, tags go, entities stay
    encoded until the tags are gone (so &lt;name&gt; survives as <name> for source_clean)."""
    t = re.sub(r"<br\s*/?>", "\n", fragment, flags=re.I)
    t = _TAG_RE.sub("", t)
    t = html.unescape(t)
    t = t.replace("\xa0", " ").replace("\r", "")
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r" *\n[\s]*", "\n", t)                 # a run of line breaks is one paragraph break
    return t.strip()


def _section(page: str, pattern: str) -> str:
    m = re.search(pattern, page, re.S)
    return wowhead_text(m.group(1)) if m else ""


def wowhead_quest(path: str, qid: int | None = None) -> dict:
    """A cached Wowhead Forever quest page. Page scripts and styles are removed first; progress and completion
    are read from the collapsible div AND from the inline heading layout used by pages with no description."""
    raw = open(path, encoding="utf-8", errors="replace").read()
    out = {"id": qid, "layout": []}
    m = re.search(r"<title>(.*?) - Quest - Forever</title>", raw)
    out["title"] = html.unescape(m.group(1)) if m else None
    un = raw.replace("\\/", "/")
    for key in ("Start", "End"):
        hits = re.findall(key + r": \[url=/forever/(npc|object|item)=(\d+)/", un)
        out[key.lower()] = [(kind, int(i)) for kind, i in dict.fromkeys(hits)]
    page = _SCRIPT_RE.sub("<div>", raw)             # a removed block still ends the section it interrupted
    body_start = page.find('<h1 class="heading-size-1">')
    body = page[body_start:] if body_start >= 0 else ""
    out["objectives"] = _section(body, r'<h1 class="heading-size-1">.*?</h1>(.*?)' + SECTION_END)
    out["accept"] = _section(body, r'<h2 class="heading-size-3">Description</h2>(.*?)' + SECTION_END)
    for name, key, div in (("Progress", "progress", "lknlksndgg-progress"),
                           ("Completion", "complete", "lknlksndgg-completion")):
        t = _section(body, r'id="' + div + r'"[^>]*>(.*?)</div>')
        if t:
            out["layout"].append(key + ":collapsible")
        else:
            t = _section(body, r'<h2 classes="first" class="heading-size-3">' + name + r'</h2>(.*?)' + SECTION_END)
            if t:
                out["layout"].append(key + ":inline")
        out[key] = t
    return out


def wowhead_quests(folder: str = WOWHEAD) -> dict:
    out = {}
    for f in os.listdir(folder):
        m = re.match(r"quest_(\d+)\.html$", f)
        if m:
            q = int(m.group(1))
            out[q] = wowhead_quest(os.path.join(folder, f), q)
    return out


def wowhead_npc_display(folder: str = WOWHEAD) -> dict:
    """NPC ID -> (display ID, name) from the cached Wowhead NPC pages."""
    out = {}
    for f in os.listdir(folder):
        m = re.match(r"npc_(\d+)\.html$", f)
        if not m:
            continue
        page = open(os.path.join(folder, f), encoding="utf-8", errors="replace").read()
        d = re.search(r"displayId\s*=\s*(\d+)", page)
        t = re.search(r"<title>(.*?) - NPC - Forever</title>", page)
        out[int(m.group(1))] = (int(d.group(1)) if d else None, html.unescape(t.group(1)) if t else None)
    return out


def _book_pages(raw: str):
    """The pages of a cached Wowhead item / object page's book viewer (new Book({... pages: [...]})), or None.
    The array is read with the JSON decoder from its opening bracket: no regex over the whole page."""
    i = raw.find("new Book(")
    if i < 0:
        return None
    j = raw.find("pages:", i, i + 400)
    k = raw.find("[", j) if j >= 0 else -1
    if k < 0:
        return None
    try:
        pages, _ = json.JSONDecoder().raw_decode(raw, k)
    except ValueError:
        return None
    return [p for p in pages if isinstance(p, str)] if isinstance(pages, list) else None


def wowhead_books(folder: str = WOWHEAD) -> list:
    """[{"kind": "item"|"object", "id", "name", "pages": [source text]}] of the cached Forever item and object
    pages that carry a book (their readable text), in ID order. Page HTML: <br> is a line break, tags go,
    entities are decoded after the tags are gone (so "&lt;name&gt;" survives as "<name>" for source_clean).
    "readable" lists the cached pages that say "Right Click to Read" but have no book text cached."""
    out, missing = [], []
    for f in os.listdir(folder):
        m = re.match(r"(item|object)_(\d+)\.html$", f)
        if not m:
            continue
        raw = open(os.path.join(folder, f), encoding="utf-8", errors="replace").read()
        t = re.search(r"<title>(.*?) - (?:Item|Object) - Forever</title>", raw)
        name = html.unescape(t.group(1)) if t else None
        pages = _book_pages(raw)
        if pages is None:
            if "Right Click to Read" in raw:
                missing.append({"kind": m.group(1), "id": int(m.group(2)), "name": name})
            continue
        out.append({"kind": m.group(1), "id": int(m.group(2)), "name": name,
                    "pages": [wowhead_text(p) for p in pages]})
    out.sort(key=lambda b: (b["kind"], b["id"]))
    wowhead_books.missing = sorted(missing, key=lambda b: (b["kind"], b["id"]))
    return out


wowhead_books.missing = []


# ------------------------------------------------------------------------------------------ collector store
def collector(path: str = STORE) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


# ------------------------------------------------------------------------------------------ Forever client
def _wdb_records(path: str):
    d = open(path, "rb").read()
    magic, build = d[:4], struct.unpack_from("<I", d, 4)[0]
    pos, recs = 0x18, []
    while pos + 8 <= len(d):
        entry, size = struct.unpack_from("<II", d, pos)
        pos += 8
        if entry == 0 and size == 0:
            break
        recs.append((entry, d[pos:pos + size]))
        pos += size
    return magic, build, recs


# QueryQuestInfoResponse string header: bit-packed byte counts, then the strings back to back, unterminated.
_QC_WIDTHS = (9, 12, 12, 9, 10, 8, 10, 8, 11)
_QC_NAMES = ("title", "objectives", "details", "area", "portraitGiverText", "portraitGiverName",
             "portraitTurnInText", "portraitTurnInName", "completionLog")


def _bits(p: bytes, o: int, widths) -> list:
    out, bitpos = [], 0
    for w in widths:
        v = 0
        for _ in range(w):
            byte = p[o + (bitpos >> 3)]
            v = (v << 1) | ((byte >> (7 - (bitpos & 7))) & 1)
            bitpos += 1
        out.append(v)
    return out


def questcache(folder: str = GAME_WDB) -> dict:
    """quest ID -> {title, objectives, details, ...} from the Forever client's questcache.wdb (read-only).
    The strings sit at the end of each record behind a 12-byte bit-packed length header; the header is found
    as the one offset whose lengths add up to exactly the rest of the record."""
    path = os.path.join(folder, "questcache.wdb")
    if not os.path.exists(path):
        return {}
    magic, build, recs = _wdb_records(path)
    if magic != b"TSQW":
        raise SystemExit("questcache.wdb: unexpected magic %r" % magic)
    out = {}
    for entry, p in recs:
        hit = None
        for o in range(len(p) - 13, max(0, len(p) - 6000) - 1, -1):
            lens = _bits(p, o, _QC_WIDTHS)
            start = o + 12
            if lens[0] and sum(lens) == len(p) - start:
                title = p[start:start + lens[0]]
                if all(c >= 32 for c in title):
                    hit = (start, lens)
                    break
        if not hit:
            continue
        start, lens = hit
        rec = {"build": build}
        for name, n in zip(_QC_NAMES, lens):
            rec[name] = p[start:start + n].decode("utf-8", "replace")
            start += n
        out[entry] = rec
    return out


def pagetextcache(folder: str = GAME_WDB) -> dict:
    """page ID -> {"next": next page ID or 0, "text"} from the Forever client's pagetextcache.wdb (read-only):
    the pages the Forever server sent this client. A record is the page ID, the next page's ID, 4 unknown
    bytes, a zero byte, a 12-bit text length (then 4 bits), and the text (no terminator)."""
    path = os.path.join(folder, "pagetextcache.wdb")
    if not os.path.exists(path):
        return {}
    magic, build, recs = _wdb_records(path)
    if magic != b"XTPW":
        raise SystemExit("pagetextcache.wdb: unexpected magic %r" % magic)
    out = {}
    for entry, p in recs:
        if len(p) < 15:
            continue
        n = (p[13] << 4) | (p[14] >> 4)
        if 15 + n != len(p) or struct.unpack_from("<I", p, 0)[0] != entry:
            continue                                   # a layout this reader does not know: left out, not guessed
        out[entry] = {"next": struct.unpack_from("<I", p, 4)[0], "text": p[15:].decode("utf-8", "replace"),
                      "build": build}
    return out


def gameobjectcache_readables(folder: str = GAME_WDB) -> dict:
    """object ID -> {"type", "name", "page"} for the readable world objects (type 9 TEXT: data0; type 10 GOOBER:
    data7) in the Forever client's gameobjectcache.wdb: the objects this client has seen. Read-only; used only
    to report which Forever readables have no page text on this PC."""
    path = os.path.join(folder, "gameobjectcache.wdb")
    if not os.path.exists(path):
        return {}
    magic, _, recs = _wdb_records(path)
    if magic != b"BOGW":
        return {}
    out = {}
    for entry, p in recs:
        try:
            typ = struct.unpack_from("<I", p, 0)[0]
            if typ not in (9, 10):
                continue
            o, names = 8, []
            for _ in range(7):                          # name, 3 unused names, icon, cast bar caption, unknown
                j = p.index(b"\x00", o)
                names.append(p[o:j].decode("utf-8", "replace"))
                o = j + 1
            data = struct.unpack_from("<24i", p, o)
        except (ValueError, struct.error):
            continue
        page = data[0] if typ == 9 else data[7]
        if page > 0:
            out[entry] = {"type": typ, "name": names[0], "page": page}
    return out


def creaturecache(folder: str = GAME_WDB, cdi_ids=None) -> dict:
    """NPC ID -> {"name", "displays": [(display, scale, probability)]} from the Forever client's
    creaturecache.wdb: the display list the Forever server sent (read-only; same scan as the research parser)."""
    path = os.path.join(folder, "creaturecache.wdb")
    if not os.path.exists(path):
        return {}
    if cdi_ids is None:
        cdi_ids = {int(r["ID"]) for r in db2("CreatureDisplayInfo")}
    _, _, recs = _wdb_records(path)
    out = {}
    for entry, p in recs:
        m = re.search(rb"[\x20-\x7e]{2,}\x00", p)
        name = m.group(0)[:-1].decode("ascii", "replace") if m else "?"
        for off in range(0, len(p) - 20):
            cnt = struct.unpack_from("<I", p, off)[0]
            if not 1 <= cnt <= 4 or off + 8 + cnt * 12 > len(p):
                continue
            total = struct.unpack_from("<f", p, off + 4)[0]
            if not (0 <= total <= 1000):
                continue
            tri = [struct.unpack_from("<Iff", p, off + 8 + k * 12) for k in range(cnt)]
            if all(t[0] in cdi_ids and 0 < t[1] < 20 and 0 <= t[2] <= 1000 for t in tri) and \
                    abs(sum(t[2] for t in tri) - total) < 1e-3:
                out[entry] = {"name": name, "displays": [(t[0], round(t[1], 4), round(t[2], 4)) for t in tri]}
                break
    return out


def db2(name: str, folder: str = DB2_DIR) -> list:
    with open(os.path.join(folder, name + ".csv"), encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def hotfix_broadcast(folder: str = DB2_DIR) -> dict:
    """BroadcastText ID -> (Text, Text1) from the Forever client's hotfix cache (DBCache.bin, extracted to CSV)."""
    path = os.path.join(folder, "BroadcastText_hotfix_DBCache.csv")
    if not os.path.exists(path):
        return {}
    return {int(r["ID"]): (r["Text_lang"], r["Text1_lang"]) for r in db2("BroadcastText_hotfix_DBCache", folder)}


def listfile_paths(path: str = LISTFILE) -> dict:
    """FileDataID -> lower-case path, for sound and model files only (the voice rule's archetype names)."""
    out = {}
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            i, _, p = line.partition(";")
            p = p.strip().lower()
            if i.isdigit() and (p.startswith("sound/") or p.endswith(".m2")):
                out[int(i)] = p
    return out
