"""
Post a release into the Discord #releases channel -- only text the user has
read first.

    python Tools/discord_announce.py --version 0.13.6 --dry-run   # show the post, send nothing
    gh workflow run announce.yml -f version=0.13.6                 # send it (the Announce workflow)

The post is NOT the changelog (user, 2026-09-23: "avoid overcomplicating the
release message, keep it interesting to read but condense and be on point ...
before the discord releases it, i want to inspect the release text"). Each
release gets its own short Discord text in docs/discord/<version>.md, written
for the channel and read by the user; the Announce workflow, started by hand
once they have approved it, posts exactly that. Without that file nothing is
posted. The Release workflow no longer posts on its own.

Every post opens with DISCLAIMER: CurseForge verifies each new file before it
reaches the CurseForge app, which usually takes about an hour.

Two rules it follows deliberately:

  It never fails a run. A Discord outage, a revoked webhook or a rate limit
  prints what went wrong and how to retry, and exits 0.

  The webhook URL is a credential and lives only in the environment (the
  repository secret). Anyone holding it can post as the server, so it is never
  committed, never written to a file, and never printed -- including on the
  failure paths, which is why the retry hint names the workflow instead.

No dependencies: urllib, because Tools/ is plain Python.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "MelloUI.toc")
NOTES_DIR = os.path.join(ROOT, "docs", "discord")

REPO = "MelloCro/MelloUI"
RELEASES = f"https://github.com/{REPO}/releases"
CURSEFORGE = "https://www.curseforge.com/wow/addons/melloui"
ACCENT = 0x9B8CFF          # the TOC title colour, |cff9b8cff
DESCRIPTION_LIMIT = 4096   # Discord's hard cap on embed.description
# Opens every release post (user, 2026-09-23): CurseForge holds each new file
# for review, so the update reaches the CurseForge app about an hour after the
# post; the GitHub download is attached before the post goes out.
DISCLAIMER = (
    "> **Heads up:** the update usually takes about an hour to show up on CurseForge "
    "while they verify it. GitHub has it right away."
)


def read(path: str) -> str:
    with io.open(path, encoding="utf-8") as fh:
        return fh.read().replace("﻿", "")


def toc_version() -> str:
    m = re.search(r"^##\s*Version:\s*(.+)$", read(TOC), re.M)
    return m.group(1).strip() if m else ""


def reviewed_text(version: str) -> str:
    """The Discord text the user approved for this release, or "" when none."""
    path = os.path.join(NOTES_DIR, f"{version}.md")
    return read(path).strip() if os.path.isfile(path) else ""


def describe(body: str) -> str:
    """The disclaimer, then the reviewed text. That text is written short; if it
    still does not fit, refuse rather than cut a post the user approved."""
    text = DISCLAIMER + "\n\n" + body
    if len(text) > DESCRIPTION_LIMIT:
        raise ValueError(f"the Discord text is {len(text)} characters with the disclaimer; "
                         f"Discord takes {DESCRIPTION_LIMIT}. Shorten docs/discord/<version>.md.")
    return text


def payload(version: str, body: str, role_id: str = "") -> dict:
    embed = {
        "title": f"MelloUI {version}",
        "url": f"{RELEASES}/tag/v{version}",
        "color": ACCENT,
        "description": describe(body),
        "fields": [
            {
                "name": "Get it",
                "value": f"[GitHub]({RELEASES}/tag/v{version}) · [CurseForge]({CURSEFORGE})",
                "inline": True,
            },
            {
                "name": "Update",
                "value": "Replace the `MelloUI` folder in `Interface\\AddOns`, then `/reload`.",
                "inline": True,
            },
            {
                "name": "Everything that changed",
                "value": f"[Full notes on GitHub]({RELEASES}/tag/v{version})",
                "inline": False,
            },
        ],
        "footer": {"text": "Your settings are kept. /mello status says where they came from."},
    }
    out = {
        "username": "MBot",
        "embeds": [embed],
        # Nothing in the text may ping anybody, except the @Release pings role
        # when one is given -- the only mention this post is allowed to make.
        "allowed_mentions": {"parse": [], "roles": [role_id] if role_id else []},
    }
    if role_id:
        out["content"] = f"<@&{role_id}> MelloUI {version} is out."
    return out


def post(url: str, body: dict) -> None:
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "MelloUI-release"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        if response.status >= 300:
            raise RuntimeError(f"Discord answered {response.status}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Post a MelloUI release into Discord.")
    parser.add_argument("--version", default="", help="which release to announce (default: the TOC's)")
    parser.add_argument("--dry-run", action="store_true", help="print the post, send nothing")
    parser.add_argument("--no-ping", action="store_true", help="leave out the @Release pings mention")
    args = parser.parse_args()

    version = (args.version or toc_version()).lstrip("vV").strip()
    body = reviewed_text(version) if version else ""
    if not body:
        print(f"no reviewed Discord text for {version or 'this release'} (docs/discord/{version}.md) -- nothing posted. "
              "Write it, let it be read, then run the Announce workflow.")
        return 0

    role_id = "" if args.no_ping else os.environ.get("DISCORD_RELEASE_ROLE_ID", "").strip()
    try:
        data = payload(version, body, role_id)
    except ValueError as e:
        print(f"not posted: {e}")
        return 0

    if args.dry_run:
        print(json.dumps(data, indent=2, ensure_ascii=False))
        print(f"\n({len(data['embeds'][0]['description'])} of {DESCRIPTION_LIMIT} description characters used)")
        return 0

    url = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not url:
        print("DISCORD_WEBHOOK_URL is not set -- skipping the Discord post.")
        return 0

    try:
        post(url, data)
        print(f"announced MelloUI {version} in Discord.")
    except (urllib.error.URLError, urllib.error.HTTPError, RuntimeError, TimeoutError) as e:
        detail = getattr(e, "reason", None) or getattr(e, "code", None) or e
        print(f"could not post to Discord: {detail}")
        print(f"Retry:  gh workflow run announce.yml -f version={version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
