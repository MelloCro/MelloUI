#!/usr/bin/env python3
"""Export every voiceable line of the v2 pack as a generation manifest (SPEC.md section 3).

    python Tools/voice_v2/export_lines.py [--pilot-selection PATH] [--no-full] [--research-map PATH]
    python Tools/voice_v2/export_lines.py --readables [--include-orphans]     the readable pages only

Writes to MelloUI-BuildData/output/voice_v2/:
    lines.json, review.csv                 scope "Everything": every quest and NPC text (NOT generated here)
    lines_pilot.json, review_pilot.csv     the pilot: exactly the keys of pilot_selection.json, plus its narrator
                                           A/B alternate, when --pilot-selection is given
    export_counts.json                     the counts per line type, with the research census for comparison
    lines_readables.json, review_readables.csv   with --readables: books, letters, notes, plaques, signs and
                                           tablets, every page read by the narrator, keyed "r-<hash8>" (see
                                           "readables" below); written alone, nothing else is touched

Sources (read-only): the cmangos dump (Classic quests, npc_text / gossip menus and sub-pages, quest-giver and
trainer greetings, holiday conditions), the cached Wowhead pages (Forever quests, both page layouts), the
in-game collector store (fallback for Forever quest texts, Forever NPC greetings), the Forever client's quest
cache (fallback for Forever accept / objectives). Media/QuestListData.lua gives the quest list and giver kinds.

Every line gets exactly one speaker: accept and objectives the giver, progress and complete the turn-in NPC,
0 (a narrator) for objects and items. Each NPC speaks in its one voice from npc_voices.csv (created once from
the research draft, then only appended to). Player name / class / race are left out of the spoken text, $G
lines become two versions, stage directions become narrator segments, and the same words in the same voice
are made once (one job serving several keys). The exporter fails loudly when a check of SPEC.md 3.6 fails.
"""
from __future__ import annotations

import argparse
import collections
import copy
import csv
import datetime
import hashlib
import json
import os
import re
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_voices as NV  # noqa: E402
import sources as S  # noqa: E402
import vtext as V  # noqa: E402

OVERRIDES = os.path.join(HERE, "spoken_overrides.json")
QUEST_KINDS = ("accept", "objectives", "progress", "complete")
QUEST_COLUMN = {"accept": "Details", "objectives": "Objectives", "progress": "RequestItemsText",
                "complete": "OfferRewardText"}
# text kinds, in the order a shared key keeps its first kind
TEXT_KINDS = ("greeting", "state", "qgreet", "trainer", "sub", "holiday", "default")
DEFAULT_GREETING = "Greetings, $N"          # cmangos' DEFAULT_GOSSIP_MESSAGE for a gossip NPC without text
GOSSIP_FLAG = 1
# research census (counts.md / REPORT.md section 4, scenario C, clips at L2 with $G lines as two clips)
CENSUS = {"accept": (3434, 1339), "objectives": (3478, 1226), "progress": (2699, 535), "complete": (3576, 643),
          "greeting": 1511, "state": 813, "qgreet": 207, "holiday": 670, "sub": 2760, "trainer": 267,
          "total": 22386}


def log(msg):
    print(msg, flush=True)


def sha1_text(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()


# ============================================================================================ gathering
class Gather:
    """Loads the sources and collects raw quest texts, quest speakers and NPC / object texts."""

    def __init__(self):
        self.counts = collections.Counter()
        cm = S.cmangos()
        self.cm_sha1 = cm["sha1"]
        T = self.T = cm["tables"]
        self.QL = S.quest_list()
        self.W = S.wowhead_quests()
        self.store = S.collector()
        self.QC = S.questcache()
        self.qt = {r["entry"]: r for r in T["quest_template"]}
        self.ct = {r["Entry"]: r for r in T["creature_template"]}
        rel = collections.defaultdict
        self.starters, self.enders = rel(set), rel(set)
        self.go_start, self.go_end = rel(set), rel(set)
        for r in T["creature_questrelation"]:
            self.starters[r["quest"]].add(r["id"])
        for r in T["creature_involvedrelation"]:
            self.enders[r["quest"]].add(r["id"])
        for r in T["gameobject_questrelation"]:
            self.go_start[r["quest"]].add(r["id"])
        for r in T["gameobject_involvedrelation"]:
            self.go_end[r["quest"]].add(r["id"])
        self.item_start = rel(set)
        for r in T["item_template"]:
            if r["startquest"]:
                self.item_start[r["startquest"]].add(r["entry"])
        self.spawned = {r["id"] for r in T["creature"]} | {r["entry"] for r in T["creature_spawn_entry"]}
        self.nt = {r["ID"]: r for r in T["npc_text"]}
        self.ntb = {r["Id"]: r for r in T["npc_text_broadcast_text"]}
        self.bt = {r["Id"]: r for r in T["broadcast_text"]}
        self.gmenu, self.gmenu_cond = rel(list), {}
        for r in T["gossip_menu"]:
            self.gmenu[r["entry"]].append(r["text_id"])
            self.gmenu_cond[(r["entry"], r["text_id"])] = r["condition_id"] or 0
        self.gopt = rel(list)
        for r in T["gossip_menu_option"]:
            self.gopt[r["menu_id"]].append(r)
        self.cond = {r["condition_entry"]: r for r in T["conditions"]}
        guid_npc = {r["guid"]: r["id"] for r in T["creature"]}
        self.npc_gossip = rel(list)
        for r in T["npc_gossip"]:
            n = guid_npc.get(r["npc_guid"])
            # npc_gossip is keyed by spawn GUID and 27 of its 76 rows point at spawns that are now critters or
            # mobs without any NPC flag (a Rabbit with the Scholomance students' lines): those are stale, skipped
            if n is not None and (self.ct[n]["NpcFlags"] or 0):
                self.npc_gossip[n].append(r["textid"])
            elif n is not None:
                self.counts["npc_gossip rows skipped (stale GUID: NPC has no flags)"] += 1
        self.qgreet, self.qgreet_go = {}, {}
        for r in T["questgiver_greeting"]:
            (self.qgreet if r["Type"] == 0 else self.qgreet_go)[r["Entry"]] = r["Text"]
        self.tgreet = {r["Entry"]: r["Text"] for r in T["trainer_greeting"]}
        self.go = {r["entry"]: r for r in T["gameobject_template"]}

    # ------------------------------------------------------------------ conditions and gossip graphs
    NEGATE = {"event": "notevent", "notevent": "event", "none": "none", "state": "state"}

    def cond_class(self, cid, depth=0):
        """How a gossip text's condition shows it: 'none' (always), 'event' (only while a game event or holiday
        runs), 'notevent' (always, except while an event runs: the guards' normal greeting outside Love is in
        the Air), 'state' (quest, class, aura, item ...). cmangos types: 12 active game event, 26 active
        holiday, -1 AND, -2 OR, -3 NOT; flags bit 1 reverses the result ("Game Event 8 NOT Active")."""
        if not cid:
            return "none"
        r = self.cond.get(cid)
        if not r or depth > 10:
            return "state"
        t = r["type"]
        if t in (12, 26):
            base = "event"
        elif t == -3:
            base = self.NEGATE[self.cond_class(r["value1"] or 0, depth + 1)]
        elif t in (-1, -2):
            subs = [self.cond_class(r["value1"] or 0, depth + 1), self.cond_class(r["value2"] or 0, depth + 1)]
            if t == -1:
                if "event" in subs:
                    base = "event"
                elif all(s in ("none", "notevent") for s in subs):
                    base = "notevent" if "notevent" in subs else "none"
                else:
                    base = "state"
            else:
                base = "event" if subs.count("event") == 2 else ("none" if "none" in subs else "state")
        else:
            base = "state"
        return self.NEGATE[base] if (r.get("flags") or 0) & 1 else base

    def texts_for(self, text_id):
        """Every text variant of one gossip text ID (random variants and the male/female columns)."""
        out = []
        if text_id in self.ntb:
            r = self.ntb[text_id]
            for k in range(8):
                b = r["BroadcastTextId%d" % k]
                if b and b in self.bt:
                    for col in ("Text", "Text1"):
                        t = S.text_or_none(self.bt[b][col])
                        if t and t not in out:
                            out.append(t)
        elif text_id in self.nt:
            r = self.nt[text_id]
            for k in range(8):
                for j in (0, 1):
                    t = S.text_or_none(r["text%d_%d" % (k, j)])
                    if t and t not in out:
                        out.append(t)
        return out

    def submenus(self, root):
        seen, todo = {root}, [root]
        while todo:
            m = todo.pop()
            for o in self.gopt.get(m, []):
                a = o["action_menu_id"] or 0
                if a > 0 and a not in seen:
                    seen.add(a)
                    todo.append(a)
        seen.discard(root)
        return sorted(seen)

    # ------------------------------------------------------------------ quests
    def quest_texts(self, qid, q):
        """kind -> (text, source) for one quest."""
        out = {}
        if q["origin"] == 1 and qid in self.qt:
            for k, col in QUEST_COLUMN.items():
                t = S.text_or_none(self.qt[qid][col])
                if t:
                    out[k] = (t, "cmangos")
        w = self.W.get(qid) if not (q["origin"] == 1 and qid in self.qt) else None
        if w:
            for k in QUEST_KINDS:
                t = S.text_or_none(w.get(k))
                if t:
                    out[k] = (t, "wowhead")
                    if k in ("progress", "complete") and (k + ":inline") in w["layout"]:
                        self.counts["wowhead inline layout: " + k] += 1
        if q["origin"] == 1 and qid in self.qt:
            return out
        sq = self.store.get("quests", {}).get(str(qid)) or {}
        qc = self.QC.get(qid) or {}
        for k in QUEST_KINDS:
            if k in out:
                continue
            rec = sq.get(k) if isinstance(sq.get(k), dict) else None
            t = S.text_or_none(rec.get("text")) if rec else None
            if t:
                if k == "accept":
                    t = self._strip_objectives(t, qid, out)
                out[k] = (t, "collector")
                continue
            t = S.text_or_none(qc.get({"accept": "details", "objectives": "objectives"}.get(k, "-")))
            if t:
                out[k] = (t, "questcache")
        return out

    def _strip_objectives(self, text, qid, have):
        """The collector stores accept as description + objectives: cut the objectives off the end."""
        obj = have.get("objectives", (None,))[0] or S.text_or_none((self.QC.get(qid) or {}).get("objectives"))
        if obj:
            o = re.sub(r"\s+", " ", V.source_clean(obj)).strip()
            t = re.sub(r"\s+", " ", text).strip()
            if o and t.endswith(o) and len(t) > len(o):
                self.counts["collector accept: objectives cut off"] += 1
                return t[:-len(o)].strip()
        return text

    def quest_speakers(self, qid, q, kind):
        """(npc set, zero kind or None, primary, notes). zero kind: 'object' | 'item' | 'unknown'."""
        npcs, zero, notes = set(), None, []
        forever = not (q["origin"] == 1 and qid in self.qt)
        w = self.W.get(qid) if forever else None
        if kind in ("accept", "objectives"):
            npcs |= self.starters.get(qid, set())
            if self.go_start.get(qid):
                zero = "object"
            if self.item_start.get(qid):
                zero = "item"
            if q["giverKind"] == 1 and q["giverNPC"]:
                npcs.add(q["giverNPC"])
            elif q["giverKind"] == 2:
                zero = zero or "object"
            elif q["giverKind"] in (3, 4):
                zero = "item"
            ends = w["start"] if w else []
        else:
            npcs |= self.enders.get(qid, set())
            if self.go_end.get(qid):
                zero = "object"
            if q["turninNPC"]:
                npcs.add(q["turninNPC"])
            ends = w["end"] if w else []
        for typ, i in ends:
            if typ == "npc":
                npcs.add(i)
            else:
                zero = zero or typ
        # The collector's npcID is NOT used as a speaker: it recorded the target when no NPC window was open
        # (97263, a mailbox quest, got a gnome), which is exactly what SPEC.md 5.3 forbids at runtime.
        if not npcs and zero is None:
            zero = "unknown"
            notes.append("speaker-unknown")
        if kind in ("accept", "objectives"):
            if q["giverNPC"] and q["giverNPC"] in npcs:
                primary = q["giverNPC"]
            elif q["giverKind"] in (2, 3, 4) and zero:
                primary = 0
            elif npcs:
                primary = min(npcs)
            else:
                primary = 0
        else:
            if q["turninNPC"] and q["turninNPC"] in npcs:
                primary = q["turninNPC"]
            elif npcs:
                primary = min(npcs)
            else:
                primary = 0
        return npcs, zero, primary, notes

    # ------------------------------------------------------------------ NPC and object texts
    def npc_scope(self, quest_npcs):
        return sorted({n for n in self.ct if n in self.spawned} | {n for n in quest_npcs if n in self.ct})

    def npc_texts(self, npc):
        """[(kind, text, source)] of one cmangos NPC's own window."""
        r = self.ct[npc]
        menu = r["GossipMenuId"] or 0
        out = []
        roots = [(tid, self.cond_class(self.gmenu_cond.get((menu, tid), 0))) for tid in self.gmenu.get(menu, [])]
        roots += [(tid, "none") for tid in self.npc_gossip.get(npc, [])]
        for tid, cc in roots:
            for t in self.texts_for(tid):
                out.append(({"none": "greeting", "notevent": "greeting", "state": "state", "event": "holiday"}[cc],
                            t, "cmangos"))
        has_root = bool(out)
        t = S.text_or_none(self.qgreet.get(npc))
        if t:
            out.append(("qgreet", t, "cmangos"))
        if menu:
            for m in self.submenus(menu):
                for tid in self.gmenu.get(m, []):
                    for t in self.texts_for(tid):
                        out.append(("sub", t, "cmangos"))
        t = S.text_or_none(self.tgreet.get(npc))
        if t:
            out.append(("trainer", t, "cmangos"))
        if not has_root and (r["NpcFlags"] or 0) & GOSSIP_FLAG:
            out.append(("default", DEFAULT_GREETING, "default"))
        return out

    def object_texts(self, quest_objects):
        """[(kind, text, source, object entry)] of objects: quest-giver greetings (Type 1) and the gossip menus
        of quest-giver objects (type 2, data3). All are read by the narrator under NPC ID 0."""
        out = []
        for e, t in sorted(self.qgreet_go.items()):
            t = S.text_or_none(t)
            if t:
                out.append(("qgreet", t, "cmangos", e))
        for e, r in sorted(self.go.items()):
            if r["type"] != 2 or not r["data3"] or r["data3"] not in self.gmenu:
                continue
            if e not in quest_objects:
                continue
            menu = r["data3"]
            for tid in self.gmenu.get(menu, []):
                for t in self.texts_for(tid):
                    out.append(("greeting", t, "cmangos", e))
            for m in self.submenus(menu):
                for tid in self.gmenu.get(m, []):
                    for t in self.texts_for(tid):
                        out.append(("sub", t, "cmangos", e))
        return out


# ============================================================================================ building
class Export:
    def __init__(self, g: Gather, cfg: dict, npcmap, overrides: dict):
        self.g, self.cfg, self.map, self.ov = g, cfg, npcmap, overrides
        self.voices = cfg["voices"]
        self.default_seed = cfg.get("defaultSeed", 42)
        self.key_job = {}                  # key -> job id
        self.jobs = collections.OrderedDict()
        self.review = []                   # rows for review.csv
        self.canon_by_npc = collections.defaultdict(dict)   # npc -> hash8 -> canon
        self.not_voiced = []               # (key, npc, kind, flags, text)
        self.counts = collections.Counter()
        self.kind_jobs = collections.defaultdict(set)
        self.kind_jobs_origin = collections.defaultdict(set)
        self.failures = []
        self.npc_voice_seen = collections.defaultdict(set)
        self.canon_dupes = []

    # ------------------------------------------------------------------ voices
    def vset(self, key):
        v = self.voices.get(key)
        if v is None:
            self.failures.append("voice key %r is not in voices" % key)
            v = {}
        elif v.get("status") not in ("ok", "pilot"):
            self.failures.append("voice key %r has status %r" % (key, v.get("status")))
        return v

    def service(self, key):
        return self.vset(key).get("service") or key

    def seed(self, key):
        return self.vset(key).get("seed", self.default_seed)

    def narrator(self, zero_kind, side):
        n = self.cfg["narrators"]
        side = str(side if side in (1, 2, 3) else 3)
        return n["item"][side] if zero_kind == "item" else n["object"][side]

    def voice_of(self, npc, zero_kind="object", side=3, text_key=False):
        if npc == 0:
            return self.cfg["narrators"]["gossipObject"] if text_key else self.narrator(zero_kind, side)
        v = self.map.voice(npc)
        if not v:
            self.failures.append("NPC %d has no voice in npc_voices.csv" % npc)
        return v

    # ------------------------------------------------------------------ one job
    def make_job(self, vk, segs, words, narr_key=None, speaker_key=None):
        """The voicegen fields of one clip and the voice keys it uses. vk is the speaker's voice key (the clip's
        folder); every segment takes its own voice's settings (a narrator never takes ghoul). narr_key /
        speaker_key replace the narrator's or the speaker's voice (the pilot's narrator A/B)."""
        narr = narr_key or self.cfg["narrators"]["stage"]
        spk = speaker_key or vk
        used = set()

        def filters(target, key, role):
            v = self.vset(key)
            for f in ("ghoul", "tempo") + (("act",) if "text" in target else ()):
                if v.get(f) is not None and not (f == "ghoul" and role == "narrator"):
                    target[f] = v[f]

        if all(role == "speaker" for role, _ in segs):
            job = {"voice": self.service(spk), "text": " ".join(t for _, t in segs), "seed": self.seed(spk)}
            filters(job, spk, "speaker")
            wps = self.vset(spk).get("wps")
            if wps:
                job["seconds"] = round(words / float(wps), 1)
            used.add(spk)
        else:
            out = []
            for role, text in segs:
                key = spk if role == "speaker" else narr
                seg = {"voice": self.service(key), "text": text, "seed": self.seed(key)}
                filters(seg, key, role)
                out.append(seg)
                used.add(key)
            job = {"segments": out}
        return job, used

    def job_id(self, vk, job, used):
        rev = {k: int(self.vset(k).get("rev", 0)) for k in sorted(used)}
        c = json.dumps({"f": 2, "job": job, "rev": rev}, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        return "%s/%s" % (vk, sha1_text(c)[:12])

    def is_narrator(self, key):
        n = self.cfg["narrators"]
        keys = {n["stage"], n["gossipObject"]} | set(n["object"].values()) | set(n["item"].values())
        return key in keys or key.startswith("narrator")

    # ------------------------------------------------------------------ one line
    def spoken(self, text, sex):
        segs, flags = V.spoken(text, sex)
        o = self.ov.get(V.override_key(text))
        if o:
            k = sex or "n"
            if k in o:
                segs = [tuple(s) for s in o[k]]
                flags = sorted(set(flags) | {"override"})
        return segs, flags

    def add_line(self, key, npc, vk, kind, text, sex, source, extra_flags=(), meta_extra=None, origin=None):
        """Register one (key, speaker) line. Lines with the same key share one job (the first one's)."""
        segs, flags = self.spoken(text, sex)
        flags = sorted(set(flags) | set(extra_flags) | ({"source-collector"} if source == "collector" else set()))
        if npc:
            self.npc_voice_seen[npc].add(vk)
        if not segs:
            self.not_voiced.append((key, npc, kind, flags, text))
            self.counts["not voiced: " + ("dynamic-value" if "dynamic-value" in flags else "empty")] += 1
            return
        probs = V.final_problems(segs)
        if probs:
            self.failures.append("%s (NPC %s): %s" % (key, npc, "; ".join(probs)))
        wc = sum(V.words(t) for _, t in segs)
        line = {"key": key, "kind": kind, "quest": (meta_extra or {}).get("quest"), "npc": npc, "sex": sex,
                "source": source, "text": text}
        if meta_extra:
            for k, v in meta_extra.items():
                if k != "quest" and v is not None:
                    line[k] = v
        if key in self.key_job:
            jid = self.key_job[key]
            job = self.jobs[jid]
            same = [l for l in job["meta"]["lines"] if l["key"] == key and l["npc"] == npc]
            spoken_here = " ".join(t for _, t in segs)
            if job["meta"]["_spoken"] != spoken_here and job["meta"]["voiceKey"] == vk:
                self.canon_dupes.append((key, npc, kind, text, job["meta"]["lines"][0]["text"]))
            elif job["meta"]["voiceKey"] != vk:
                self.failures.append("key %s is spoken by two voices (%s, %s)" % (key, job["meta"]["voiceKey"], vk))
            if same:
                kinds = same[0].setdefault("kinds", [same[0]["kind"]])
                if kind not in kinds:
                    kinds.append(kind)
            else:
                job["meta"]["lines"].append(line)
            return
        job, used = self.make_job(vk, segs, wc)
        jid = self.job_id(vk, job, used)
        if jid not in self.jobs:
            job["id"] = jid
            job["keys"] = []
            job["meta"] = {"voiceKey": vk, "words": wc, "flags": [], "lines": [], "ab": None, "pilot": None,
                           "_spoken": " ".join(t for _, t in segs), "_segs": [list(x) for x in segs]}
            self.jobs[jid] = job
        job = self.jobs[jid]
        job["keys"].append(key)
        job["meta"]["lines"].append(line)
        job["meta"]["flags"] = sorted(set(job["meta"]["flags"]) | set(flags))
        self.key_job[key] = jid
        self.kind_jobs[kind].add(jid)
        if origin:
            self.kind_jobs_origin[(kind, origin)].add(jid)
        if flags:
            self.review.append({"key": key, "npc": npc, "voice": vk, "kind": kind, "flags": " ".join(flags),
                                "source text": text,
                                "spoken text": " | ".join("%s: %s" % (r, t) if r == "narrator" else t for r, t in segs),
                                "override": "yes" if "override" in flags else ""})

    def text_key(self, npc, text, sex):
        canon = V.key_text(text, sex)
        if not canon:
            return None, None
        h = V.hash8(canon)
        prev = self.canon_by_npc[npc].get(h)
        if prev is not None and prev != canon:
            self.failures.append("hash collision for NPC %d: %r / %r -> %s" % (npc, prev[:60], canon[:60], h))
        self.canon_by_npc[npc][h] = canon
        return "g-%d-%s" % (npc, h), canon

    # ------------------------------------------------------------------ everything
    def run(self):
        g = self.g
        # ---- quests
        quest_records = []
        quest_npcs = set()
        quest_objects = set()
        for qid, q in sorted(g.QL.items()):
            texts = g.quest_texts(qid, q)
            for kind in QUEST_KINDS:
                if kind not in texts:
                    continue
                text, src = texts[kind]
                text = V.source_clean(text)
                if not V.has_letters(text):
                    self.counts["quest text with no letters after decoding (skipped)"] += 1
                    continue
                npcs, zero, primary, notes = g.quest_speakers(qid, q, kind)
                quest_npcs |= npcs
                quest_records.append((qid, q, kind, text, src, npcs, zero, primary, notes))
                self.counts["quest texts %s origin %d (%s)" % (kind, q["origin"], src)] += 1
            quest_objects |= g.go_start.get(qid, set()) | g.go_end.get(qid, set())
        # ---- NPC / object texts
        text_records = []
        scope = g.npc_scope(quest_npcs)
        for npc in scope:
            for kind, text, src in g.npc_texts(npc):
                text_records.append((npc, kind, V.source_clean(text), src, None))
        # Collected greetings: the collector turned the player's name, class and race back into $n/$c/$r, also
        # where the text spells them out ("the pillar of the human race" -> "$r race"). A collected text whose
        # canonical form equals a database text of the same NPC, with or without the collecting character's
        # class and race words, is that text: skipped. Only really new texts (Forever NPCs) are kept.
        store_gossip = g.store.get("gossip", {})
        who = g.store.get("player") or {}
        known = collections.defaultdict(set)
        for npc, kind, text, src, obj in text_records:
            for sx in V.sex_variants(text):
                c = V.key_text(text, sx)
                known[npc].add(c)
                known[npc].add(V.runtime_key_text(c, {"class": who.get("class"), "race": who.get("race")}))
        for n, texts in sorted(store_gossip.items(), key=lambda kv: int(kv[0])):
            for t in (texts.keys() if isinstance(texts, dict) else texts):
                t = S.text_or_none(t)
                if not t:
                    continue
                t = V.source_clean(t)
                if any(V.key_text(t, sx) in known[int(n)] for sx in V.sex_variants(t)):
                    self.counts["collected greetings already in the database"] += 1
                    continue
                text_records.append((int(n), "greeting", t, "collector", None))
                self.counts["collected greetings kept (not in the database)"] += 1
        for kind, text, src, obj in g.object_texts(quest_objects):
            text_records.append((0, kind, V.source_clean(text), src, obj))
        # ---- voices for every speaker NPC (frozen map; missing NPCs appended by the rule)
        speakers = set(quest_npcs) | {r[0] for r in text_records if r[0]}
        names = {}
        for q in g.QL.values():
            if q["giverNPC"]:
                names.setdefault(q["giverNPC"], q["giverName"])
            if q["turninNPC"]:
                names.setdefault(q["turninNPC"], q["turninName"])
        for n, rec in g.store.get("npcs", {}).items():
            names.setdefault(int(n), rec.get("name", ""))
        added = self.map.append_missing(speakers, lambda: NV.VoiceRule(g.T), g.store.get("npcs", {}), names)
        self.counts["NPCs appended to npc_voices.csv"] = len(added)
        # ---- quest lines
        for qid, q, kind, text, src, npcs, zero, primary, notes in quest_records:
            side = q["side"] if q["side"] in (1, 2, 3) else 3
            spk = sorted(npcs) + ([0] if zero else [])
            pv = self.voice_of(primary, zero or "object", side)
            title = V.canon_title(q["title"])
            for s in spk:
                sv = self.voice_of(s, zero or "object", side)
                body = "%d-%s" % (qid, kind) if (s == primary or sv == pv) else "%d-%s-%d" % (qid, kind, s)
                if s != primary and sv != pv:
                    self.counts["speaker keys (-<npc>)"] += 1
                vk = pv if body == "%d-%s" % (qid, kind) else sv
                flags = list(notes)
                if s and self._stand_in(s, vk):
                    flags.append("voice-stand-in")
                for sex in V.sex_variants(text):
                    key = (sex + "-" if sex else "") + body
                    self.add_line(key, s, vk, kind, text, sex, src, flags,
                                  {"quest": qid, "title": title, "speakerKind": (zero if s == 0 else "npc")},
                                  origin=q["origin"])
        # ---- text lines (NPC ID in the key; objects are NPC 0)
        order = {k: i for i, k in enumerate(TEXT_KINDS)}
        kept = [r for r in text_records if V.has_letters(r[2])]
        self.counts["NPC text with no letters after decoding (skipped)"] = len(text_records) - len(kept)
        text_records = sorted(kept, key=lambda r: (r[0], order[r[1]]))
        for npc, kind, text, src, obj in text_records:
            vk = self.voice_of(npc, text_key=True)
            flags = ["voice-stand-in"] if npc and self._stand_in(npc, vk) else []
            for sex in V.sex_variants(text):
                key, canon = self.text_key(npc, text, sex)
                if not key:
                    self.counts["text with an empty canonical form"] += 1
                    continue
                self.add_line(key, npc, vk, kind, text, sex, src, flags,
                              {"canon": canon, "object": obj})
        # ---- checks
        for npc, vs in self.npc_voice_seen.items():
            if len(vs) > 1:
                self.failures.append("NPC %d speaks in %d voices: %s" % (npc, len(vs), sorted(vs)))
        for jid, job in self.jobs.items():
            if ("text" in job) == ("segments" in job):
                self.failures.append("job %s must have text or segments, not both / neither" % jid)
        allkeys = [k for j in self.jobs.values() for k in j["keys"]]
        if len(allkeys) != len(set(allkeys)):
            self.failures.append("duplicate keys across jobs")
        return self

    def _stand_in(self, npc, vk):
        pick = (self.cfg.get("npcs") or {}).get(str(npc))
        if isinstance(pick, dict) and pick.get("rule") in ("1", "2", "3"):
            return False            # the per-NPC table gave it its own, its display's or its race's voice
        if isinstance(pick, dict) and pick.get("rule") == "5":
            return True             # a closest voice: for review
        row = self.map.rows.get(npc) or {}
        return (row.get("identity", "").startswith("creature:") or row.get("identity", "").startswith("emitter_")
                or self.voices.get(vk, {}).get("source") == "stand-in")


# ============================================================================================ output
def manifest(scope, jobs, inputs, stats_extra=None):
    out_jobs = []
    words = 0
    for job in jobs:
        j = {k: v for k, v in job.items() if k not in ("meta",)}
        meta = {k: v for k, v in job["meta"].items() if not k.startswith("_")}
        j["meta"] = meta
        out_jobs.append(j)
        words += meta["words"]
    stats = {"jobs": len(out_jobs), "keys": sum(len(j["keys"]) for j in out_jobs), "words": words}
    if stats_extra:
        stats.update(stats_extra)
    return {"format": "melloui-voice-lines/2", "scope": scope,
            "created": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "inputs": inputs, "stats": stats, "jobs": out_jobs}


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


REVIEW_COLUMNS = ["key", "npc", "voice", "kind", "flags", "source text", "spoken text", "override"]


def write_review(path, rows):
    with open(path, "w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=REVIEW_COLUMNS)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def comparable(s):
    """Spoken text for the pilot comparison: the pilot texts were made with $B already flattened, so only
    paragraph joins may differ ("Hogger A huge" vs "Hogger. A huge")."""
    return [w.lower() for w in re.findall(r"[A-Za-z0-9']+", s)]


def build_pilot(exp: Export, selection_path: str):
    """The pilot manifest: the export's jobs for exactly the keys of pilot_selection.json, each checked against
    the selection (voice, seed, segment roles, spoken text up to paragraph joins), plus the narrator A/B
    alternates (alternate = another narrator). A keyed pilot job is the full export's job for that key, with the
    voice's own settings: there is no ghoul A/B any more (the user decided by ear on no ghoul filter,
    2026-09-28), and a selection that still asks for one is refused."""
    sel = json.load(open(selection_path, encoding="utf-8"))["lines"]
    problems, jobs = [], collections.OrderedDict()
    alt_count = 0
    for e in sel:
        key = e["key"]
        jid = exp.key_job.get(key)
        if not jid:
            problems.append("%s: key %s is not in the export" % (e["pilot"], key))
            continue
        full = exp.jobs[jid]
        meta = full["meta"]
        vk, segs = meta["voiceKey"], [tuple(x) for x in meta["_segs"]]
        if vk != e["voice"]:
            problems.append("%s %s: voice %s, the selection says %s" % (e["pilot"], key, vk, e["voice"]))
        if exp.seed(vk) != e["seed"]:
            problems.append("%s %s: seed %s, the selection says %s" % (e["pilot"], key, exp.seed(vk), e["seed"]))
        if [r for r, _ in segs] != [r for r, _ in e["spoken"]]:
            problems.append("%s %s: segment roles %s, the selection says %s" % (
                e["pilot"], key, [r for r, _ in segs], [r for r, _ in e["spoken"]]))
        for (r1, t1), (r2, t2) in zip(segs, e["spoken"]):
            if comparable(t1) != comparable(t2):
                problems.append("%s %s: spoken text differs\n   export:    %s\n   selection: %s" % (
                    e["pilot"], key, t1, t2))
        exact = [list(x) for x in segs] == [list(x) for x in e["spoken"]]
        ab = e.get("ab")
        job, used = exp.make_job(vk, segs, meta["words"])
        job["id"] = exp.job_id(vk, job, used)
        if job["id"] != jid:
            problems.append("%s %s: the pilot job %s is not the full export's %s" % (e["pilot"], key, job["id"], jid))
        job["keys"] = [key]
        job["meta"] = {"voiceKey": vk, "words": meta["words"], "flags": meta["flags"],
                       "lines": [copy.deepcopy(l) for l in meta["lines"] if l["key"] == key],
                       "ab": None, "pilot": e["pilot"], "exactSelectionText": exact}
        alt = None
        if ab and ab["group"] == "ghoul":
            problems.append("%s %s: a ghoul A/B, but the user decided on no ghoul filter" % (e["pilot"], key))
            continue
        elif ab and ab["group"] == "narrator":
            other = ab["alternate"]
            if any(r == "narrator" for r, _ in segs):
                a, used = exp.make_job(vk, segs, meta["words"], narr_key=other)
            elif exp.is_narrator(vk):
                a, used = exp.make_job(vk, segs, meta["words"], speaker_key=other)
            else:
                problems.append("%s %s: a narrator A/B on a line without a narrator" % (e["pilot"], key))
                continue
            alt = (a, used, {"group": "narrator", "of": job["id"], "variant": other})
        if job["id"] in jobs:
            jobs[job["id"]]["keys"].append(key)
            jobs[job["id"]]["meta"]["lines"].extend(job["meta"]["lines"])
        else:
            jobs[job["id"]] = job
        if alt:
            a, used, info = alt
            a["id"] = exp.job_id(vk, a, used)
            a["keys"] = []
            a["meta"] = {"voiceKey": vk, "words": meta["words"], "flags": meta["flags"],
                         "lines": copy.deepcopy(job["meta"]["lines"]), "ab": info, "pilot": e["pilot"]}
            if a["id"] == job["id"]:
                problems.append("%s %s: the A/B alternate is identical to the keyed job" % (e["pilot"], key))
            jobs[a["id"]] = a
            alt_count += 1
    got = sorted(k for j in jobs.values() for k in j["keys"])
    want = sorted(e["key"] for e in sel)
    if got != want:
        problems.append("pilot keys differ from the selection: extra %s, missing %s" % (
            sorted(set(got) - set(want)), sorted(set(want) - set(got))))
    return list(jobs.values()), problems, alt_count


def pilot_review(exp, jobs):
    keys = {k for j in jobs for k in j["keys"]}
    return [r for r in exp.review if r["key"] in keys]


# ============================================================================================ readables
# Books, letters, notes, plaques, signs and tablets: every page an item or a world object shows in the game's
# item text window, read by the narrator (the user's decision, 2026-09-28; no ambient chatter or combat shouts).
#
#   key   "r-<hash8>"   hash8 of the page's canonical text: its words with the page's own layout markup
#                       (HTML tags), the player's name / class / race and $B taken out, $G resolved per variant.
#                       The runtime (Modules/VoiceOver.lua, ITEM_TEXT_READY) makes the same key from the page it
#                       shows. Identical pages anywhere in the game are one key and one clip.
#   jobs  one clip per page text, in the narrator's voice (voices.json narrators.readable, else gossipObject);
#         a page is one text: stage directions in it (<The rest of the book is blank>) are read in line.
#   meta  lines[0].canon (the pack's text table), .names (the item / object names showing it: the runtime's
#         fuzzy fallback compares the pages of the open item's name), .places (item / object and page number).
#
# Sources (read-only): the cmangos dump (page_text with its next_page chains; items whose PageText starts a
# chain; objects of type 9 TEXT (data0) and 10 GOOBER (data7)); the Forever client's own caches (its page texts
# win over the dump's for the same page: Forever fixed some; the readable objects it has seen start chains the
# dump's objects may not); the cached Wowhead pages of Forever items (book text). Nothing is downloaded.
READABLE_KIND = "readable"
READABLE_MAX_PLACES = 12
PAGE_HTML_TAGS = {"html", "body", "p", "br", "img", "h1", "h2", "h3"}
_PAGE_TAG_RE = re.compile(r"<\s*/?\s*([A-Za-z0-9]+)([^<>]*)>")
_LUA_SPACE = " \t\n\v\f\r"


def strip_page_html(text, sep="\n"):
    """The book layout's HTML tags out (<HTML> <BODY> <P> <H1>-<H3> <BR> <IMG>, with or without attributes or a
    closing slash); a bracketed stage direction (<The rest of the book is blank>, <illegible text>) stays. The
    runtime's PageText does the same (Lua pattern "<%s*/?%s*(%w+)([^<>]*)>"), so both see the same words."""
    def rep(m):
        rest = m.group(2)
        if m.group(1).lower() in PAGE_HTML_TAGS and (rest == "" or rest[0] in _LUA_SPACE + "/"):
            return sep
        return m.group(0)
    return _PAGE_TAG_RE.sub(rep, text or "")


_HTML_PAGE_RE = re.compile(r"\s*<\s*html\b", re.I)
_CONTINUED_RE = re.compile(r"[ \t]*\n\s*(?=[a-z])")


def page_source(text):
    """A page's source text for the line rules: in a book-layout (HTML) page a line end is only a space and the
    tags make the breaks; the layout tags go, block breaks stay line breaks; then source_clean (entities, Wowhead
    <name>-style tokens, $B, line ends); a line that goes on in lower case continues the sentence ("What follows
    are" / "the military ranks": one <P> per line beside a picture) instead of ending in a full stop. Only spaces
    and line breaks differ from the raw page, so the canonical text (the key) is the same."""
    t = text or ""
    if _HTML_PAGE_RE.match(t):
        t = re.sub(r"\s+", " ", t)
    t = V.source_clean(strip_page_html(t, "\n"))
    return _CONTINUED_RE.sub(" ", t)


def readable_key(canon):
    return "r-" + V.hash8(canon)


class Readables:
    """Every readable page and where it is shown, in a stable order: the dump's items, then its objects (by entry),
    then the objects only the Forever client knows, then the Wowhead Forever books; orphans last when asked."""

    def __init__(self, include_orphans=False, cm=None, client_pages=None, client_objects=None, books=None):
        self.counts = collections.Counter()
        cm = cm if cm is not None else S.cmangos(tables=S.READABLE_TABLES)
        self.cm_sha1 = cm.get("sha1")
        T = cm["tables"]
        self.pages = {r["entry"]: r for r in T["page_text"]}
        self.client_pages = S.pagetextcache() if client_pages is None else client_pages
        self.client_objects = S.gameobjectcache_readables() if client_objects is None else client_objects
        self.books = S.wowhead_books() if books is None else books
        self.books_missing = list(getattr(S.wowhead_books, "missing", [])) if books is None else []
        self.include_orphans = include_orphans
        self.client_differs, self.missing, self.loops = set(), set(), set()
        starts = collections.OrderedDict()             # page ID -> [place]
        for r in sorted(T["item_template"], key=lambda r: r["entry"]):
            if r.get("PageText"):
                starts.setdefault(r["PageText"], []).append({"item": r["entry"], "name": r["name"]})
                self.counts["items with a page text (dump)"] += 1
        go_known = set()
        for r in sorted(T["gameobject_template"], key=lambda r: r["entry"]):
            go_known.add(r["entry"])
            page = r["data0"] if r["type"] == 9 else (r["data7"] if r["type"] == 10 else 0)
            if page and page > 0:
                starts.setdefault(page, []).append({"object": r["entry"], "name": r["name"]})
                self.counts["readable objects (dump, type %d)" % r["type"]] += 1
        for oid, rec in sorted(self.client_objects.items()):
            if oid in go_known:
                continue
            starts.setdefault(rec["page"], []).append({"object": oid, "name": rec["name"], "forever": True})
            self.counts["readable objects only the Forever client knows"] += 1
        self.starts = starts

    def page(self, pid):
        """(text, source) of one page ID: the Forever client's text when it has the page, else the dump's."""
        c = self.client_pages.get(pid)
        d = self.pages.get(pid)
        if c is not None and S.text_or_none(c["text"]):
            if d is not None and d.get("text") != c["text"]:
                self.client_differs.add(pid)
            return c["text"], "forever-client"
        if d is None:
            return None, None
        return d.get("text"), "cmangos"

    def next_page(self, pid):
        c = self.client_pages.get(pid)
        if c is not None:
            return c.get("next") or 0
        d = self.pages.get(pid)
        return (d.get("next_page") or 0) if d else 0

    def chain(self, start):
        """The page IDs of a chain in reading order; stops at a missing page or a loop (both counted)."""
        out, seen, pid = [], set(), start
        while pid:
            if pid in seen:
                self.loops.add(start)
                break
            if pid not in self.pages and pid not in self.client_pages:
                self.missing.add(pid)                  # (a page that is there with no text stays: counted later)
                break
            seen.add(pid)
            out.append(pid)
            pid = self.next_page(pid)
        return out

    def records(self):
        """[(ref, text, source, [place])]: one record per page ID (every place that shows it, with its page
        number), then one per Wowhead book page. ref = page ID or "wh:<kind>:<id>:<n>"."""
        by_page = collections.OrderedDict()
        reached = set()
        for start, places in self.starts.items():
            for n, pid in enumerate(self.chain(start), 1):
                reached.add(pid)
                rec = by_page.setdefault(pid, [])
                for pl in places:
                    rec.append(dict(pl, page=n, pageId=pid))
        heads = set(self.pages) | set(self.client_pages)
        nexts = {self.next_page(p) for p in heads}
        orphans = sorted(p for p in heads if p not in reached)
        self.orphans = orphans
        if self.include_orphans:
            for head in [p for p in orphans if p not in nexts] + orphans:
                for n, pid in enumerate(self.chain(head), 1):
                    if pid in reached:
                        continue
                    reached.add(pid)
                    by_page.setdefault(pid, []).append({"orphan": True, "page": n, "pageId": pid})
        out = []
        for pid, places in by_page.items():
            text, src = self.page(pid)
            out.append((pid, text, src, places))
        for b in self.books:
            for n, text in enumerate(b["pages"], 1):
                out.append(("wh:%s:%d:%d" % (b["kind"], b["id"], n), text, "wowhead",
                            [{b["kind"]: b["id"], "name": b["name"], "page": n, "forever": True}]))
        self.counts["pages where the Forever client's text differs from the dump (client wins)"] = len(self.client_differs)
        self.counts["page IDs referenced but missing"] = len(self.missing)
        self.counts["page chains that loop (cut at the loop)"] = len(self.loops)
        return out


class ReadableExport(Export):
    """The line export's jobs, voices and checks for readable pages: the narrator reads a page as one text."""

    def spoken(self, text, sex):
        segs, flags = Export.spoken(self, text, sex)
        if len(segs) > 1 or (segs and segs[0][0] != "speaker"):
            segs = [("speaker", " ".join(t for _, t in segs))]    # one reader: directions are read in line
        # a heading or a closing that ends in a colon ("Respectfully yours:") got the paragraph's full stop too
        return [(r, re.sub(r"[:;,]\.(?=\s|$)", ".", t)) for r, t in segs], flags


def export_readables(cfg, overrides, include_orphans=False, rd=None):
    """-> (ReadableExport, Readables, groups). Fails (exp.failures) on a hash collision or a spoken-text check."""
    rd = rd or Readables(include_orphans)
    n = cfg["narrators"]
    vk = n.get("readable") or n["gossipObject"]
    exp = ReadableExport(None, cfg, None, overrides)
    exp.vset(vk)
    groups = collections.OrderedDict()        # key -> {canon, text, sex, source, names, places, refs}
    canon_of = {}
    for ref, raw, src, places in rd.records():
        if S.text_or_none(raw) is None:
            rd.counts["pages with no text (NULL / empty)"] += 1
            continue
        text = page_source(raw)
        if not V.has_letters(text):
            rd.counts["pages with no words once the layout is out (a picture page)"] += 1
            continue
        rd.counts["pages with words"] += 1
        for sex in V.sex_variants(text):
            canon = V.key_text(text, sex)
            if not canon:
                continue
            key = readable_key(canon)
            if canon_of.get(key, canon) != canon:
                exp.failures.append("readable hash collision: %r / %r -> %s" % (canon_of[key][:60], canon[:60], key))
                continue
            canon_of[key] = canon
            g = groups.get(key)
            if g is None:
                g = groups[key] = {"canon": canon, "text": text, "sex": sex, "source": src, "names": [],
                                   "places": [], "refs": []}
            else:
                rd.counts["page variants that repeat an earlier page's words (deduped)"] += 1
            g["refs"].append(ref)
            for pl in places:
                if pl.get("name") and pl["name"] not in g["names"]:
                    g["names"].append(pl["name"])
                if len(g["places"]) < READABLE_MAX_PLACES:
                    g["places"].append(pl)
    for key, g in groups.items():
        meta = {"canon": g["canon"], "names": g["names"], "places": g["places"], "pageRefs": len(g["refs"])}
        exp.add_line(key, 0, vk, READABLE_KIND, g["text"], g["sex"], g["source"], (), meta)
    allkeys = [k for j in exp.jobs.values() for k in j["keys"]]
    if len(allkeys) != len(set(allkeys)):
        exp.failures.append("duplicate keys across jobs")
    for jid, job in exp.jobs.items():
        if ("text" in job) == ("segments" in job):
            exp.failures.append("job %s must have text or segments, not both / neither" % jid)
    return exp, rd, groups


def readables_main(args, cfg, cfg_label, overrides):
    rd = Readables(args.include_orphans)
    exp, rd, groups = export_readables(cfg, overrides, args.include_orphans, rd)
    if exp.failures:
        for f in exp.failures[:60]:
            log("FAIL " + f)
        raise SystemExit("readables export failed: %d problems (nothing written)" % len(exp.failures))
    jobs = list(exp.jobs.values())
    main_ids, overlap = set(), 0
    main_path = os.path.join(args.out, "lines.json")
    if os.path.exists(main_path):                       # read only: the same words in the same voice = one clip
        with open(main_path, encoding="utf-8") as fh:
            main_ids = {j["id"] for j in json.load(fh).get("jobs", [])}
        overlap = sum(1 for j in jobs if j["id"] in main_ids)
    words = sum(j["meta"]["words"] for j in jobs)
    orphan_words = 0
    if not args.include_orphans:
        for pid in rd.orphans:
            t, _ = rd.page(pid)
            if S.text_or_none(t):
                orphan_words += V.words(page_source(t))
    coverage = {
        "dumpPagesTotal": len(rd.pages),
        "chainStarts": len(rd.starts),
        "pagesWithWords": rd.counts["pages with words"],
        "keys": len(exp.key_job),
        "jobs": len(jobs),
        "jobsSharedWithLinesJson": overlap,
        "orphanPages": len(rd.orphans),
        "orphanPagesIncluded": bool(args.include_orphans),
        "orphanWordsLeftOut": orphan_words,
        "foreverClientPages": len(rd.client_pages),
        "foreverClientReadableObjects": len(rd.client_objects),
        "foreverClientObjectsWithoutPageText": sorted(
            "%d %s (page %d)" % (o, r["name"], r["page"]) for o, r in rd.client_objects.items()
            if r["page"] not in rd.pages and r["page"] not in rd.client_pages),
        "wowheadBooks": len(rd.books),
        "wowheadBookPages": sum(len(b["pages"]) for b in rd.books),
        "wowheadReadableWithoutBookText": ["%s %d %s" % (b["kind"], b["id"], b["name"]) for b in rd.books_missing],
        "notes": dict(sorted({**rd.counts, **exp.counts}.items())),
    }
    inputs = {"cmangos": rd.cm_sha1, "wowheadBooks": len(rd.books), "foreverPageCache": len(rd.client_pages),
              "voices": S.sha1_file(NV.voices_path()) if NV.voices_path() else "builtin", "narrator": cfg_label}
    m = manifest("readables", jobs, inputs, {"notVoiced": len(exp.not_voiced), "speechMinutes150": round(words / 150.0, 1),
                                             "coverage": coverage})
    os.makedirs(args.out, exist_ok=True)
    out = os.path.join(args.out, "lines_readables.json")
    write_json(out, m)
    rows = list(exp.review) + [{"key": k, "npc": n_, "voice": "", "kind": kind, "flags": " ".join(fl),
                                "source text": t, "spoken text": "(not voiced)", "override": ""}
                               for k, n_, kind, fl, t in exp.not_voiced]
    write_review(os.path.join(args.out, "review_readables.csv"), rows)
    log("wrote %s: %d jobs, %d keys, %d words (~%.1f min at 150 wpm); review_readables.csv %d rows" % (
        out, m["stats"]["jobs"], m["stats"]["keys"], words, words / 150.0, len(rows)))
    for k, v in coverage.items():
        if k != "notes":
            log("  %s: %s" % (k, v))
    for k, v in coverage["notes"].items():
        log("  %s: %s" % (k, v))
    return exp, rd, m


# ============================================================================================ main
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=S.V2_OUT)
    ap.add_argument("--pilot-selection", help="pilot_selection.json (SPEC.md 6.1): also write lines_pilot.json")
    ap.add_argument("--research-map", help="npc_voice_map.csv, used once to create npc_voices.csv")
    ap.add_argument("--no-full", action="store_true", help="skip writing lines.json / review.csv")
    ap.add_argument("--remap-identity", action="append", default=[], metavar="IDENTITY",
                    help="re-map the frozen NPC rows of this voice identity to what voices.json now says "
                         "(only when asked: e.g. after a dedicated voice was made for a rare kit)")
    ap.add_argument("--remap-all", action="store_true",
                    help="re-map every frozen NPC row whose voice differs from voices.json (its per-NPC table, then "
                         "the identities); only when asked, e.g. after a re-map of the whole assignment")
    ap.add_argument("--readables", action="store_true",
                    help="export ONLY the readable pages (books, letters, plaques ...) to lines_readables.json and "
                         "review_readables.csv; lines.json, the pilot and npc_voices.csv are not touched")
    ap.add_argument("--include-orphans", action="store_true",
                    help="with --readables: also the dump's pages no item or object shows (left out by default)")
    args = ap.parse_args(argv)

    cfg, cfg_label = NV.load_voices()
    log("voices: %s" % cfg_label)
    if args.readables:
        overrides = json.load(open(OVERRIDES, encoding="utf-8")) if os.path.exists(OVERRIDES) else {}
        overrides = {k: v for k, v in overrides.items() if not k.startswith("_")}
        return readables_main(args, cfg, cfg_label, overrides)
    nmap = NV.NpcVoiceMap(cfg)
    if not nmap.rows:
        if not args.research_map:
            raise SystemExit("npc_voices.csv does not exist yet: pass --research-map <npc_voice_map.csv> once")
        nmap.freeze_from(args.research_map)
        log("npc_voices.csv: created from %s (%d NPCs)" % (args.research_map, len(nmap.rows)))
    if args.remap_all:
        remapped = nmap.remap_all()
    else:
        remapped = nmap.remap(set(args.remap_identity)) if args.remap_identity else []
    for r in remapped:
        log("re-mapped NPC %s (%s, %s) -> %s" % (r["npc"], r["name"], r["identity"], r["voice"]))
    drift = nmap.drift()
    for ident, d in sorted(drift.items()):
        log("note: identity %s is frozen as %s for %d NPCs; voices config now says %s (re-map with "
            "--remap-identity %s if that is wanted)" % (ident, d["frozen"], d["npcs"], d["now"], ident))
    overrides = json.load(open(OVERRIDES, encoding="utf-8")) if os.path.exists(OVERRIDES) else {}
    overrides = {k: v for k, v in overrides.items() if not k.startswith("_")}

    log("reading sources ...")
    g = Gather()
    exp = Export(g, cfg, nmap, overrides).run()
    if exp.failures:
        for f in exp.failures[:60]:
            log("FAIL " + f)
        raise SystemExit("export failed: %d problems (nothing written)" % len(exp.failures))
    if nmap.created or nmap.appended or remapped:
        nmap.save()
        log("npc_voices.csv: %d NPCs (%d appended this run)" % (len(nmap.rows), len(nmap.appended)))

    os.makedirs(args.out, exist_ok=True)
    inputs = {"cmangos": g.cm_sha1, "questList": S.sha1_file(S.QUEST_LIST), "wowheadPages": len(g.W),
              "collector": S.sha1_file(S.STORE), "questcache": len(g.QC),
              "voices": S.sha1_file(NV.voices_path()) if NV.voices_path() else "builtin",
              "npcVoices": S.sha1_file(NV.NPC_VOICES_CSV) if os.path.exists(NV.NPC_VOICES_CSV) else None}
    jobs = sorted(exp.jobs.values(), key=lambda j: (j["meta"]["voiceKey"], j["keys"][0]))
    counts = summarize(exp, g)
    counts["identityDrift"] = drift
    if not args.no_full:
        write_json(os.path.join(args.out, "lines.json"), manifest("full", jobs, inputs, {"notVoiced": len(exp.not_voiced)}))
        rows = list(exp.review) + [{"key": k, "npc": n, "voice": "", "kind": kind, "flags": " ".join(fl),
                                    "source text": t, "spoken text": "(not voiced)", "override": ""}
                                   for k, n, kind, fl, t in exp.not_voiced]
        write_review(os.path.join(args.out, "review.csv"), rows)
        log("wrote lines.json (%d jobs, %d keys) and review.csv (%d rows)" % (len(jobs), len(exp.key_job), len(rows)))
    if args.pilot_selection:
        pjobs, problems, alts = build_pilot(exp, args.pilot_selection)
        if problems:
            for p in problems:
                log("PILOT " + p)
            raise SystemExit("pilot check failed: %d problems (lines_pilot.json not written)" % len(problems))
        pjobs.sort(key=lambda j: (j["meta"]["pilot"], j["meta"]["ab"] is not None))
        m = manifest("pilot", pjobs, inputs, {"alternates": alts})
        write_json(os.path.join(args.out, "lines_pilot.json"), m)
        write_review(os.path.join(args.out, "review_pilot.csv"), pilot_review(exp, pjobs))
        counts["pilot"] = m["stats"]
        log("wrote lines_pilot.json: %(jobs)d jobs, %(keys)d keys, %(words)d words" % m["stats"])
    write_json(os.path.join(args.out, "export_counts.json"), counts)
    print_counts(counts)
    return exp


def summarize(exp: Export, g: Gather) -> dict:
    out = collections.OrderedDict()
    per = collections.OrderedDict()
    for kind in QUEST_KINDS:
        c1 = len(exp.kind_jobs_origin[(kind, 1)])
        c2 = len(exp.kind_jobs_origin[(kind, 2)])
        per[kind] = {"clips": len(exp.kind_jobs[kind]), "classic": c1, "forever": c2,
                     "census": {"classic": CENSUS[kind][0], "forever": CENSUS[kind][1]}}
    for kind in TEXT_KINDS:
        per[kind] = {"clips": len(exp.kind_jobs[kind]), "census": CENSUS.get(kind)}
    keys_by_kind = collections.Counter()
    for job in exp.jobs.values():
        for l in job["meta"]["lines"]:
            keys_by_kind[l["kind"]] += 1
    out["perKind"] = per
    out["keyLinesByKind"] = dict(keys_by_kind)
    out["total"] = {"jobs": len(exp.jobs), "keys": len(exp.key_job), "census": CENSUS["total"],
                    "words": sum(j["meta"]["words"] for j in exp.jobs.values()),
                    "voices": len({j["meta"]["voiceKey"] for j in exp.jobs.values()}),
                    "npcs": len({l["npc"] for j in exp.jobs.values() for l in j["meta"]["lines"] if l["npc"]})}
    out["total"]["hours150"] = round(out["total"]["words"] / 150 / 60, 1)
    flags = collections.Counter()
    for r in exp.review:
        for f in r["flags"].split():
            flags[f] += 1
    for _, _, _, fl, _ in exp.not_voiced:
        for f in fl:
            flags[f] += 1
    out["reviewFlags"] = dict(flags.most_common())
    out["notes"] = dict(sorted({**g.counts, **exp.counts}.items()))
    out["canonDuplicates"] = len(exp.canon_dupes)
    out["canonDuplicateSamples"] = [list(x[:3]) for x in exp.canon_dupes[:10]]
    new_bt = [i for i in S.hotfix_broadcast() if i not in g.bt]
    out["foreverClientUnlinkedGossip"] = len(new_bt)
    return out


def print_counts(c):
    log("")
    log("%-12s %8s %8s   %s" % ("kind", "clips", "census", "(Classic / Forever)"))
    for kind, v in c["perKind"].items():
        if "classic" in v:
            log("%-12s %8d %8d   %d / %d  (census %d / %d)" % (kind, v["clips"], sum(v["census"].values()),
                                                         v["classic"], v["forever"], v["census"]["classic"],
                                                         v["census"]["forever"]))
        else:
            log("%-12s %8d %8s" % (kind, v["clips"], v["census"] if v["census"] is not None else "-"))
    t = c["total"]
    log("%-12s %8d %8d   keys %d, words %d (~%.1f h at 150 wpm), voices %d, NPCs %d" % (
        "total jobs", t["jobs"], t["census"], t["keys"], t["words"], t["hours150"], t["voices"], t["npcs"]))
    log("review flags: %s" % c["reviewFlags"])
    for k, v in c["notes"].items():
        log("  %s: %s" % (k, v))


if __name__ == "__main__":
    main()
