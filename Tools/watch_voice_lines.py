#!/usr/bin/env python3
"""
Keep the Forever voice pack up to date while you play.

Watches the game's saved-variables file, which the client rewrites on every
/reload, and whenever it changes runs the full loop: export the collected
lines, generate the missing ones with ElevenLabs, rebuild the pack.

Limits set by the client, not by this script:
  - lines reach the file only on /reload, so reload now and then while playing
    (the module reminds you in chat after every few new lines);
  - after a run finishes, /reload once more so the game picks up the new
    sound files (a full restart is not needed on this client).

Usage:
  python Tools/watch_voice_lines.py --player Warr [--interval 15] [--skip-progress] [--once]

Stop it with Ctrl+C.
"""

import argparse
import datetime
import glob
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_WTF = "F:/World of Warcraft/_classic_beta_/WTF"


def saved_files(wtf):
    return glob.glob(os.path.join(wtf, "Account", "*", "SavedVariables", "MelloUI.lua"))


def newest_mtime(paths):
    return max((os.path.getmtime(p) for p in paths if os.path.exists(p)), default=0)


def stamp():
    return datetime.datetime.now().strftime("%H:%M:%S")


def run_loop(args):
    cmd = [sys.executable, os.path.join(HERE, "generate_voice_lines.py")]
    if args.player:
        cmd += ["--player", args.player]
    if args.skip_progress:
        cmd += ["--skip-progress"]
    print(f"[{stamp()}] saved file changed, running export + generate + build", flush=True)
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in (result.stdout + result.stderr).splitlines():
        if line.startswith(("vanilla quests", "session data", "downloading")):
            continue
        print(f"    {line}", flush=True)
    if result.returncode != 0:
        print(f"[{stamp()}] the loop failed (exit {result.returncode}); waiting for the next reload", flush=True)
    else:
        print(f"[{stamp()}] done; /reload in game to hear the new lines, and again after your next NPC visits", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--player", default=None)
    ap.add_argument("--wtf", default=DEFAULT_WTF)
    ap.add_argument("--interval", type=float, default=15, help="seconds between checks")
    ap.add_argument("--skip-progress", action="store_true")
    ap.add_argument("--once", action="store_true", help="run the loop once now and exit")
    args = ap.parse_args()

    files = saved_files(args.wtf)
    if not files:
        sys.exit(f"no MelloUI.lua under {args.wtf}")
    if args.once:
        run_loop(args)
        return

    last = newest_mtime(files)
    print(f"[{stamp()}] watching {len(files)} saved-variables file(s); /reload in game to trigger a run. Ctrl+C stops.", flush=True)
    try:
        while True:
            time.sleep(args.interval)
            current = newest_mtime(saved_files(args.wtf))
            if current > last:
                # Let the client finish writing before reading.
                time.sleep(2)
                current = newest_mtime(saved_files(args.wtf))
                last = current
                run_loop(args)
    except KeyboardInterrupt:
        print(f"\n[{stamp()}] stopped", flush=True)


if __name__ == "__main__":
    main()
