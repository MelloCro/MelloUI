#!/usr/bin/env python3
"""Generate the clips of a voice line manifest on voicegen (the voice pack spec, section 7.2).

    python Tools/voice_v2/generate.py <manifest.json> --dry-run      the batch plan, nothing sent
    python Tools/voice_v2/generate.py <manifest.json>                send, wait, download, validate, delete
    ... --max-batch-minutes M   speech minutes per batch (default 2.5: a batch under ~3 min runs on the box's
                                loaded model, with no second machine to set up)
    ... --max-total-minutes M   refuse a manifest with more speech than this (default 10: the pilot only)
    ... --clips DIR             the clip library (default MelloUI-BuildData/output/voice_v2/clips)
    ... --only P01,P02          only these pilot lines (meta.pilot), e.g. to redo a few

The manifest is lines.json / lines_pilot.json (format "melloui-voice-lines/2"). Every job goes to /v1/batches with
its voicegen fields only (id, text or segments, voice, seed, ghoul, tempo, act, seconds); keys and meta stay here.

For each batch, strictly one after another:
  1. /v1/health must be ok and idle; while another batch runs or is queued, wait (poll 60 s, give up after 30 min)
  2. jobs whose clips/<id>.ogg already exists and validates are left out (a re-run only makes what is missing)
  3. POST /v1/batches, then poll /v1/batches/<id> every 30 s
  4. download clips.zip resumably (HTTP Range); accept only entries <voiceKey>/<hash12>.ogg (zip-slip guard);
     a clip the zip lacks is fetched on its own
  5. validate every clip (OggS + Vorbis identification header, mono, >= 0.3 s, <= 4 + words / 1.5 s): good ones go
     to clips/<id>.ogg, bad ones to clips/_rejected/ and the record
  6. /jobs gives the seed each job really used (the service re-rolls a piece its speech check rejected)
  7. write batches/<batchId>.json and update clips/index.json (id -> seconds, bytes, sha1, batch, seedUsed, made)
  8. DELETE the batch on the server; Ctrl-C cancels it first

Network: only the voicegen box (env VG, default http://172.24.100.77:7895). The token comes from env VG_TOKEN or
~/.voicegen_token and is never printed, logged or written; errors never show headers. Standard library only.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
from paths import OUTPUT  # noqa: E402
import voice_v2_pack as PACK  # noqa: E402   the clip validation the pack build uses
import voice_v2_voices as VV  # noqa: E402   the voicegen client (token handling, health, waiting)

V2 = os.path.join(OUTPUT, "voice_v2")
MANIFEST_FORMAT = "melloui-voice-lines/2"
VG_FIELDS = ("id", "text", "segments", "voice", "seed", "ghoul", "tempo", "act", "seconds")
ENTRY_RE = re.compile(r"^[a-z0-9_]+/[0-9a-f]{12}\.ogg$")
POLL_SECONDS = 30
BATCH_TIMEOUT = 90 * 60
TERMINAL = {"done", "failed", "cancelled", "canceled", "finished", "complete", "completed", "error"}


def say(*a):
    print(*a, flush=True)


def load_json(path, default=None):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def sha1_bytes(b: bytes) -> str:
    return hashlib.sha1(b).hexdigest()


# ------------------------------------------------------------------------------------------------------------
# the plan
# ------------------------------------------------------------------------------------------------------------
def vg_job(job: dict) -> dict:
    """The voicegen fields of a manifest job, as written (absent fields stay absent)."""
    return {k: job[k] for k in VG_FIELDS if k in job}


def words_of(job: dict) -> int:
    return PACK.words_of(job)


def speech_seconds(job: dict) -> float:
    """The service's own estimate: `seconds` when set, else words / 2.5."""
    if isinstance(job.get("seconds"), (int, float)):
        return float(job["seconds"])
    return words_of(job) / 2.5


def clip_path(clips: str, jid: str) -> str:
    voice, h12 = jid.split("/")
    return os.path.join(clips, voice, h12 + ".ogg")


def clip_ok(path: str, words: int):
    """The clip's info when it exists and validates, else None."""
    if not os.path.isfile(path):
        return None
    try:
        return PACK.validate_clip(path, words)
    except PACK.BuildError:
        return None


def plan_batches(jobs: list, max_minutes: float) -> list:
    """Jobs in manifest order, cut into batches of at most max_minutes of estimated speech."""
    batches, cur, cur_s = [], [], 0.0
    for job in jobs:
        s = speech_seconds(job)
        if cur and (cur_s + s) / 60 > max_minutes:
            batches.append(cur)
            cur, cur_s = [], 0.0
        cur.append(job)
        cur_s += s
    if cur:
        batches.append(cur)
    return batches


# ------------------------------------------------------------------------------------------------------------
# network (voicegen only; the token is added here and never shown)
# ------------------------------------------------------------------------------------------------------------
def api(path, data=None, method=None, timeout=300):
    body = VV._call(path, data, method, "application/json" if data is not None else None, timeout=timeout)
    return json.loads(body) if body else None


def download_resumable(path: str, dest: str, tries: int = 10) -> int:
    """GET path into dest with HTTP Range resume; returns the byte count. The token is never shown."""
    tok = VV._token()
    if not tok:
        raise VV.VGError("no voicegen token: set VG_TOKEN or save it to ~/.voicegen_token")
    part = dest + ".part"
    total = None
    for attempt in range(tries):
        have = os.path.getsize(part) if os.path.exists(part) else 0
        if total is not None and have >= total:
            break
        headers = {"Authorization": "Bearer " + tok}
        if have:
            headers["Range"] = "bytes=%d-" % have
        req = urllib.request.Request(VV.VG + path, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                status = r.status
                if have and status != 206:
                    have = 0                       # the server sent the whole file: start again
                crange = r.headers.get("Content-Range") or ""
                m = re.match(r"bytes \d+-\d+/(\d+)", crange)
                if m:
                    total = int(m.group(1))
                elif r.headers.get("Content-Length"):
                    total = have + int(r.headers["Content-Length"])
                with open(part, "ab" if have else "wb") as f:
                    while True:
                        chunk = r.read(1 << 16)
                        if not chunk:
                            break
                        f.write(chunk)
            size = os.path.getsize(part)
            if total is None or size >= total:
                break
            say("    download cut at %d of %d bytes; resuming" % (size, total))
        except urllib.error.HTTPError as e:
            if e.code == 416 and have:           # nothing left to send: complete
                break
            raise VV.VGError("GET %s: HTTP %d" % (path, e.code)) from None
        except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.IncompleteRead, OSError) as e:
            say("    download interrupted (%s); retry %d" % (type(e).__name__, attempt + 1))
            time.sleep(min(30, 3 * (attempt + 1)))
    else:
        raise VV.VGError("GET %s: gave up after %d tries" % (path, tries))
    os.replace(part, dest)
    return os.path.getsize(dest)


def download_bytes(path: str) -> bytes:
    return VV._call(path, timeout=120)


# ------------------------------------------------------------------------------------------------------------
# one batch
# ------------------------------------------------------------------------------------------------------------
def run_batch(name: str, jobs: list, clips: str, batches_dir: str, index: dict) -> dict:
    health = VV.wait_idle()
    t0 = time.time()
    payload = {"name": name, "jobs": [vg_job(j) for j in jobs]}
    reply = api("/v1/batches", json.dumps(payload, ensure_ascii=False).encode("utf-8"), "POST")
    bid = reply["id"]
    # the client retries a POST whose reply was lost: never leave a second copy of this batch running
    try:
        for other in api("/v1/batches") or []:
            oid = other.get("id") if isinstance(other, dict) else None
            if oid and oid != bid and other.get("name") == name:
                say("  a duplicate of %s (%s) was queued: cancelling and deleting it" % (name, oid))
                api("/v1/batches/%s/cancel" % oid, b"", "POST")
                VV._call("/v1/batches/%s" % oid, method="DELETE", timeout=60)
    except (VV.VGError, ValueError) as e:
        say("  batch list unreadable (%s)" % e)
    say("  batch %s (%s): %s jobs, %s speech minutes, mode %s" % (name, bid, reply.get("jobs"),
                                                                  reply.get("speech_minutes"), reply.get("mode")))
    record = {"batch": bid, "name": name, "submitted": time.strftime("%Y-%m-%dT%H:%M:%S"),
              "box": health.get("box_ui"), "mode": reply.get("mode"), "speechMinutes": reply.get("speech_minutes"),
              "jobs": len(jobs), "failures": [], "seedsUsed": {}, "rerolled": []}
    deleted = False
    try:
        last = None
        while True:
            st = api("/v1/batches/%s" % bid)
            line = "state %s, %s/%s done, eta %s min" % (st.get("state"), st.get("done"), st.get("total"),
                                                         st.get("eta_minutes"))
            if line != last:
                say("    " + line)
                last = line
            state = str(st.get("state", "")).lower()
            if state in TERMINAL:
                break
            if time.time() - t0 > BATCH_TIMEOUT:
                raise VV.VGError("batch %s did not finish in %d minutes" % (bid, BATCH_TIMEOUT // 60))
            time.sleep(POLL_SECONDS)
        record.update({"state": st.get("state"), "audioMinutes": st.get("audio_minutes"),
                       "clipsPerMinute": st.get("clips_per_minute"), "serverFailed": st.get("failed"),
                       "finished": time.strftime("%Y-%m-%dT%H:%M:%S"), "wallSeconds": round(time.time() - t0)})
        # the seeds each job really used
        server_jobs = {}
        try:
            for j in api("/v1/batches/%s/jobs" % bid) or []:
                if isinstance(j, dict) and j.get("id"):
                    server_jobs[j["id"]] = j
        except (VV.VGError, ValueError) as e:
            say("    /jobs unreadable: %s" % e)
        # the clips
        zpath = os.path.join(batches_dir, bid + ".zip")
        got = {}
        try:
            n = download_resumable("/v1/batches/%s/clips.zip" % bid, zpath)
            say("    clips.zip: %d bytes" % n)
            with zipfile.ZipFile(zpath) as z:
                bad = z.testzip()
                if bad:
                    raise VV.VGError("clips.zip entry %s is damaged" % bad)
                for info in z.infolist():
                    if info.is_dir():
                        continue
                    if not ENTRY_RE.match(info.filename):
                        say("    zip entry ignored: %s" % info.filename[:80])
                        continue
                    got[info.filename[:-4]] = z.read(info)
        except (VV.VGError, zipfile.BadZipFile) as e:
            say("    clips.zip failed (%s); fetching clips one by one" % e)
        for job in jobs:
            jid = job["id"]
            if jid not in got:
                try:
                    got[jid] = download_bytes("/v1/batches/%s/clips/%s.ogg" % (bid, jid))
                except VV.VGError as e:
                    record["failures"].append({"id": jid, "pilot": (job.get("meta") or {}).get("pilot"),
                                               "why": "no clip: %s" % e})
        # validate and place
        for job in jobs:
            jid = job["id"]
            blob = got.get(jid)
            if blob is None:
                continue
            words = words_of(job)
            dst = clip_path(clips, jid)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            tmp = dst + ".tmp"
            with open(tmp, "wb") as f:
                f.write(blob)
            try:
                info = PACK.validate_clip(tmp, words)
            except PACK.BuildError as e:
                rej = os.path.join(clips, "_rejected", jid.replace("/", "__") + ".ogg")
                os.makedirs(os.path.dirname(rej), exist_ok=True)
                os.replace(tmp, rej)
                record["failures"].append({"id": jid, "pilot": (job.get("meta") or {}).get("pilot"),
                                           "why": "invalid clip: %s" % e, "file": rej})
                continue
            os.replace(tmp, dst)
            sj = server_jobs.get(jid, {})
            seed_used = sj.get("seeds", sj.get("seed"))
            record["seedsUsed"][jid] = seed_used
            asked = [s.get("seed") for s in job["segments"]] if "segments" in job else [job.get("seed")]
            used = seed_used if isinstance(seed_used, list) else [seed_used]
            if seed_used is not None and [u for u in used] != asked:
                record["rerolled"].append({"id": jid, "asked": asked, "used": seed_used})
            index[jid] = {"seconds": round(info["seconds"], 3), "bytes": info["bytes"], "sha1": sha1_bytes(blob),
                          "batch": bid, "seedUsed": seed_used, "made": record["finished"]}
        if os.path.exists(zpath):
            os.remove(zpath)
    except KeyboardInterrupt:
        say("  interrupted: cancelling batch %s" % bid)
        try:
            api("/v1/batches/%s/cancel" % bid, b"", "POST")
        except VV.VGError:
            pass
        raise
    finally:
        record["clipsSaved"] = sum(1 for j in jobs if index.get(j["id"], {}).get("batch") == bid)
        save_json(os.path.join(batches_dir, bid + ".json"), record)
        save_json(os.path.join(clips, "index.json"), index)
        try:
            VV._call("/v1/batches/%s" % bid, method="DELETE", timeout=60)
            deleted = True
        except VV.VGError as e:
            say("    DELETE failed: %s" % e)
        record["deletedOnServer"] = deleted
        save_json(os.path.join(batches_dir, bid + ".json"), record)
    say("    saved %d of %d clips, %d failures, %d re-rolled seeds; batch deleted on the server: %s"
        % (record["clipsSaved"], len(jobs), len(record["failures"]), len(record["rerolled"]), deleted))
    return record


# ------------------------------------------------------------------------------------------------------------
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("manifest")
    ap.add_argument("--clips", default=os.path.join(V2, "clips"))
    ap.add_argument("--batches", default=os.path.join(V2, "batches"))
    ap.add_argument("--max-batch-minutes", type=float, default=2.5)
    ap.add_argument("--max-total-minutes", type=float, default=10.0)
    ap.add_argument("--only", default="", help="comma list of meta.pilot names (P01,P18m ...)")
    ap.add_argument("--name", default=None, help="batch name prefix (default melloui-v2-<scope>-<yyyymmdd-hhmm>)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

    manifest = load_json(args.manifest)
    if not manifest or manifest.get("format") != MANIFEST_FORMAT:
        say("not a %s manifest: %s" % (MANIFEST_FORMAT, args.manifest))
        return 1
    jobs = manifest.get("jobs", [])
    ids = [j.get("id") for j in jobs]
    if len(set(ids)) != len(ids):
        say("the manifest has a job id twice")
        return 1
    for j in jobs:
        if not PACK.ID_RE.match(j.get("id", "")) or ("text" in j) == ("segments" in j):
            say("bad job %r" % j.get("id"))
            return 1
    if args.only:
        want = {p.strip() for p in args.only.split(",") if p.strip()}
        jobs = [j for j in jobs if (j.get("meta") or {}).get("pilot") in want]
    index = load_json(os.path.join(args.clips, "index.json"), {})
    todo, have = [], 0
    for j in jobs:
        if clip_ok(clip_path(args.clips, j["id"]), words_of(j)):
            have += 1
        else:
            todo.append(j)
    total_min = sum(speech_seconds(j) for j in todo) / 60
    say("%s: %d jobs, %d already made, %d to make (%.2f speech minutes)"
        % (os.path.basename(args.manifest), len(jobs), have, len(todo), total_min))
    if total_min > args.max_total_minutes:
        say("refusing: %.1f speech minutes is more than --max-total-minutes %.1f" % (total_min, args.max_total_minutes))
        return 1
    batches = plan_batches(todo, args.max_batch_minutes)
    for n, b in enumerate(batches, 1):
        say("  batch %d: %d jobs, %.2f speech minutes, %s .. %s" % (
            n, len(b), sum(speech_seconds(j) for j in b) / 60,
            (b[0].get("meta") or {}).get("pilot"), (b[-1].get("meta") or {}).get("pilot")))
    if args.dry_run or not batches:
        return 0
    prefix = args.name or "melloui-v2-%s-%s" % (manifest.get("scope") or "full", time.strftime("%Y%m%d-%H%M"))
    records = []
    try:
        for n, b in enumerate(batches, 1):
            name = prefix if len(batches) == 1 else "%s-%d" % (prefix, n)
            records.append(run_batch(name, b, args.clips, args.batches, index))
    except VV.VGError as e:
        say("voicegen: %s" % e)
        return 1
    fails = [f for r in records for f in r["failures"]]
    say("done: %d batches, %d clips saved, %d failures" % (len(records), sum(r["clipsSaved"] for r in records),
                                                           len(fails)))
    for f in fails:
        say("  FAILED %s %s: %s" % (f.get("pilot"), f["id"], f["why"]))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
