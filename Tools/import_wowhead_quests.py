#!/usr/bin/env python3
"""
Import quest dialog for WoW: Forever from Wowhead's Forever database into the
voice line store, so the generator can voice quests before you meet them.

A quest the vanilla database never had (and with an ID of 60000 or more) is a
Forever quest; vanilla quests are already covered by the vanilla sound pack, so
only the new ones are imported by default. Wowhead's "added in patch" tag is
not used: it has been re-tagged more than once (2.0.0, then 16001 for newer
Forever quests and 1.13.x for vanilla ones, 2026-09-23). Each quest page gives
the quest ID, the start and end NPC with their IDs, and the offer (description),
progress and completion text with <name> / <class> / <race> placeholders.

Wowhead's Forever database is not complete (some beta quests are missing), so
in-game collection remains the safety net for the rest.

Usage:
  python Tools/import_wowhead_quests.py             import new quests (patch 2.0.0)
  python Tools/import_wowhead_quests.py --all       import every quest Wowhead lists
  python Tools/import_wowhead_quests.py --ids 76240 83934
  python Tools/import_wowhead_quests.py --refresh   ignore cached pages

Pages are cached under MelloUI-BuildData/cache/wowhead so re-runs only fetch new quests.
After importing, run generate_voice_lines.py (or let the watcher do it).
"""

import argparse
import datetime
import html
import json
import os
import re
import sys
import time
import urllib.request
from paths import CACHE

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = "https://www.wowhead.com/forever"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Upgrade-Insecure-Requests": "1",
    "sec-ch-ua": '"Chromium";v="128", "Google Chrome";v="128"',
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": '"Windows"',
}
# Listing pages cap at 1000 rows; these bands keep every band below that.
LEVEL_BANDS = [
    "min-level:1/max-level:10", "min-level:11/max-level:20", "min-level:21/max-level:30",
    "min-level:31/max-level:40", "min-level:41/max-level:50", "min-level:51/max-level:59",
    # level 60 with a lower requirement outgrew one page (1,003 rows, 2026-09-23:
    # Forever's Craftsman's Writs): split at required level 50
    "min-level:60/max-level:60/min-req-level:1/max-req-level:50",
    "min-level:60/max-level:60/min-req-level:51/max-req-level:55",
    "min-level:60/max-level:60/min-req-level:56/max-req-level:60",
    "min-level:61/max-level:99",
]
PLACEHOLDERS = {"name": "$n", "class": "$c", "race": "$r"}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def fetch(url, cache_path=None, refresh=False, delay=2.5):
    if cache_path and not refresh and os.path.exists(cache_path):
        return open(cache_path, encoding="utf-8").read()
    req = urllib.request.Request(url, headers=HEADERS)
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                text = resp.read().decode("utf-8", "replace")
            break
        except urllib.error.HTTPError as exc:
            if exc.code in (403, 429) and attempt < 5:
                # Wowhead's edge starts refusing after a burst; back off hard.
                wait = 90 * (attempt + 1)
                log(f"   blocked (HTTP {exc.code}); waiting {wait} s before retrying")
                time.sleep(wait)
                continue
            raise
        except Exception as exc:  # noqa: BLE001
            if attempt == 5:
                raise
            log(f"   retry after error: {exc}")
            time.sleep(10)
    if cache_path:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        open(cache_path, "w", encoding="utf-8").write(text)
    time.sleep(delay)
    return text


def listing_data(page_html):
    idx = page_html.find("data:[")
    if idx < 0:
        return []
    start = idx + 5
    depth = 0
    for i in range(start, len(page_html)):
        c = page_html[i]
        if c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                return json.loads(page_html[start:i + 1])
    return []


def clean_text(fragment):
    text = re.sub(r"<br\s*/?>", "\n", fragment, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    for word, placeholder in PLACEHOLDERS.items():
        text = re.sub(r"<\s*" + word + r"\s*>", placeholder, text, flags=re.I)
    text = text.replace("\xa0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\s*\n\s*", " ", text)
    return text.strip()


def parse_quest(page_html, quest_id):
    out = {"id": quest_id}
    m = re.search(r"<title>(.*?) - Quest - Forever</title>", page_html)
    out["title"] = html.unescape(m.group(1)) if m else None
    unescaped = page_html.replace("\\/", "/")
    for key in ("Start", "End"):
        m = re.search(key + r": \[url=/forever/npc=(\d+)/[^\]]*\]([^\[]*)\[/url\]", unescaped)
        out[key.lower()] = {"npcID": int(m.group(1)), "name": html.unescape(m.group(2))} if m else None
    m = re.search(r'<h2 class="heading-size-3">Description</h2>(.*?)<h2', page_html, re.S)
    out["accept"] = clean_text(m.group(1)) if m else ""
    m = re.search(r'id="lknlksndgg-progress"[^>]*>(.*?)</div>', page_html, re.S)
    out["progress"] = clean_text(m.group(1)) if m else ""
    m = re.search(r'id="lknlksndgg-completion"[^>]*>(.*?)</div>', page_html, re.S)
    out["complete"] = clean_text(m.group(1)) if m else ""
    return out


def load_npc_data(path):
    """race/gender by NPC ID from Media/NPCVoiceData.lua and the overrides file."""
    npcs = {}
    if os.path.exists(path):
        text = open(path, encoding="utf-8").read()
        # Each group is one or more "..." strings joined with .. ; concatenate, then split.
        for m in re.finditer(r'\["(\w+)_(\w)"\] = ((?:"[^"]*"\s*(?:\.\.\s*)?)+)', text):
            race, gender = m.group(1), m.group(2)
            ids = " ".join(re.findall(r'"([^"]*)"', m.group(3)))
            for npc_id in ids.split():
                npcs[int(npc_id)] = {"race": race, "gender": gender}
    overrides = os.path.join(os.path.dirname(path), "NPCVoiceOverrides.lua")
    if os.path.exists(overrides):
        text = open(overrides, encoding="utf-8").read()
        for m in re.finditer(r'^\s*\[(\d+)\]\s*=\s*\{\s*race\s*=\s*"(\w+)"\s*,\s*gender\s*=\s*"(\w)"', text, re.M):
            npcs[int(m.group(1))] = {"race": m.group(2), "gender": m.group(3)}
    return npcs


def resolve_npcs(store, cache, refresh=False, only_unknown=True):
    """Race and gender for NPCs from their Wowhead display ID, through the same
    creature display tables the NPC data was built from."""
    sys.path.insert(0, HERE)
    from extract_npc_voices import load_db2, load_listfile, classify, fetch as fetch_file, LISTFILE  # noqa: E402
    data_cache = CACHE
    display, model_fdid, extra = load_db2(data_cache, "1.15.9.69722")
    r_display, r_model, r_extra = load_db2(data_cache, "12.1.0.69814")
    for k, v in r_display.items():
        display.setdefault(k, v)
    for k, v in r_model.items():
        model_fdid.setdefault(k, v)
    for k, v in r_extra.items():
        extra.setdefault(k, v)
    paths = load_listfile(fetch_file(LISTFILE, os.path.join(data_cache, "verified-listfile.csv")))
    todo = [(npc_id, rec) for npc_id, rec in store.get("npcs", {}).items() if not only_unknown or not rec.get("gender")]
    log(f"resolving {len(todo)} NPCs through Wowhead display IDs")
    resolved = 0
    for n, (npc_id, rec) in enumerate(todo, 1):
        try:
            page = fetch(f"{BASE}/npc={npc_id}", os.path.join(cache, f"npc_{npc_id}.html"), refresh)
        except Exception as exc:  # noqa: BLE001
            log(f"npc {npc_id} ({rec.get('name')}): fetch failed: {exc}")
            continue
        m = re.search(r"displayId\s*=\s*(\d+)", page)
        if not m:
            log(f"npc {npc_id} ({rec.get('name')}): no display ID on Wowhead")
            continue
        display_id = int(m.group(1))
        race, gender, path = classify({"models": [display_id]}, display, model_fdid, extra, paths)
        rec["displayID"] = display_id
        if race:
            rec["race"] = race
            rec["gender"] = gender if gender in ("m", "f") else rec.get("gender") or "n"
            rec["source"] = "wowhead-display"
            resolved += 1
            log(f"   {rec.get('name')}: {race} {gender} ({os.path.basename(path)})")
        else:
            log(f"   {rec.get('name')}: display {display_id} is not in the display tables")
        if n % 25 == 0:
            json.dump(store, open(os.path.join(CACHE, "voice_lines.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    log(f"resolved {resolved} of {len(todo)} NPCs")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--store", default=os.path.join(CACHE, "voice_lines.json"))
    ap.add_argument("--cache", default=os.path.join(CACHE, "wowhead"))
    ap.add_argument("--all", action="store_true", help="import every quest, not only the ones added by Forever")
    ap.add_argument("--min-id", type=int, default=60000,
                    help="lowest quest ID treated as Forever content; lower IDs missing from vanilla are cut vanilla quests")
    ap.add_argument("--ids", nargs="*", type=int, default=None, help="only these quest IDs")
    ap.add_argument("--refresh", action="store_true", help="ignore every cached page")
    ap.add_argument("--refresh-listing", action="store_true", help="re-fetch only the quest listing pages, to pick up quests Wowhead added since")
    ap.add_argument("--limit", type=int, default=None, help="stop after this many quest pages (for a trial run)")
    ap.add_argument("--npcs", action="store_true", help="only resolve race / gender of NPCs in the store that lack it, via their Wowhead display ID")
    args = ap.parse_args()

    os.makedirs(args.cache, exist_ok=True)
    store = json.load(open(args.store, encoding="utf-8")) if os.path.exists(args.store) else {}
    store.setdefault("quests", {})
    store.setdefault("npcs", {})
    known = load_npc_data(os.path.join(HERE, "..", "Media", "NPCVoiceData.lua"))

    if args.npcs:
        resolve_npcs(store, args.cache, args.refresh)
        json.dump(store, open(args.store, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
        return

    if args.ids:
        wanted = [{"id": i, "name": None} for i in args.ids]
    else:
        quests = {}
        for band in LEVEL_BANDS:
            page = fetch(f"{BASE}/quests/{band}", os.path.join(args.cache, "listing_" + band.replace("/", "_").replace(":", "-") + ".html"), args.refresh or args.refresh_listing)
            rows = listing_data(page)
            truncated = "_truncated: 1" in page
            log(f"listing {band}: {len(rows)} quests{' (TRUNCATED, band too wide)' if truncated else ''}")
            for row in rows:
                quests[row["id"]] = row
        # A quest the vanilla database never had is a Forever quest. (Wowhead's
        # "added in patch" flag is not usable: it marks vanilla 1.11 quests too.)
        sys.path.insert(0, HERE)
        from export_voice_lines import load_vanilla_quests  # noqa: E402
        vanilla = load_vanilla_quests(CACHE)
        junk = re.compile(r"^\s*[<\[]|UNUSED|\bTEST\b|\bNYI\b|DEPRECATED|\bDND\b|\bTXT\b|^zz|\(123\)|REUSE|Never used", re.I)
        wanted = []
        for q in quests.values():
            if not args.all and (q["id"] in vanilla or q["id"] < args.min_id):
                continue
            if junk.search(q["name"] or ""):
                continue
            wanted.append(q)
        log(f"{len(quests)} quests listed, {len(wanted)} selected (not in the vanilla database, ID >= {args.min_id}, no placeholders)")

    added = skipped = fetched = 0
    today = datetime.datetime.now().strftime("%Y-%m-%d")
    for n, q in enumerate(sorted(wanted, key=lambda q: q["id"]), 1):
        if args.limit and fetched >= args.limit:
            break
        quest_id = q["id"]
        cache_path = os.path.join(args.cache, f"quest_{quest_id}.html")
        first_time = not os.path.exists(cache_path)
        try:
            page = fetch(f"{BASE}/quest={quest_id}", cache_path, args.refresh)
        except Exception as exc:  # noqa: BLE001
            log(f"quest {quest_id}: fetch failed: {exc}")
            continue
        if first_time or args.refresh:
            fetched += 1
        info = parse_quest(page, quest_id)
        if not info["title"]:
            log(f"quest {quest_id}: not on Wowhead")
            continue
        entry = store["quests"].setdefault(str(quest_id), {})
        for kind, npc_key in (("accept", "start"), ("progress", "end"), ("complete", "end")):
            text = info[kind]
            npc = info[npc_key]
            if not text or not npc:
                continue
            if kind in entry:
                skipped += 1
                continue
            entry[kind] = {
                "text": text, "title": info["title"], "npc": npc["name"], "npcID": npc["npcID"],
                "recorded": False, "seen": today, "source": "wowhead",
            }
            added += 1
            rec = store["npcs"].setdefault(str(npc["npcID"]), {})
            rec.setdefault("name", npc["name"])
            rec.setdefault("source", "wowhead")
            data = known.get(npc["npcID"])
            if data:
                rec.setdefault("race", data["race"])
                rec.setdefault("gender", data["gender"])
        if not entry:
            del store["quests"][str(quest_id)]
        if n % 25 == 0:
            log(f"   {n}/{len(wanted)} quests processed")
            json.dump(store, open(args.store, "w", encoding="utf-8"), indent=1, ensure_ascii=False)

    os.makedirs(os.path.dirname(args.store), exist_ok=True)
    json.dump(store, open(args.store, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    unknown = sorted({rec.get("name", npc_id) for npc_id, rec in store["npcs"].items() if not rec.get("gender")})
    log(f"imported {added} lines ({skipped} already known), {fetched} pages fetched; store now {len(store['quests'])} quests")
    if unknown:
        log(f"{len(unknown)} NPCs without race/gender (add them to Media/NPCVoiceOverrides.lua or meet them in game): "
            + ", ".join(unknown[:15]) + (" ..." if len(unknown) > 15 else ""))


if __name__ == "__main__":
    main()
