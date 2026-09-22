"""
Post a release into the Discord #releases channel.

    DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/... python Tools/discord_announce.py
    python Tools/discord_announce.py --dry-run          # print the payload, post nothing
    python Tools/discord_announce.py --version 0.13.4   # announce an older release

Called at the END of the Release workflow, after the packager has published —
never before. A post linking to a release whose files are not attached yet is
worse than a late post.

Three rules it follows deliberately:

  It never fails the release. By the time this runs the addon is on CurseForge
  and attached to the GitHub release; a Discord outage, a revoked webhook or a
  rate limit must not turn that into a red build. Every failure prints what
  went wrong and how to retry it by hand, and exits 0.

  The webhook URL is a credential and lives only in the environment. Anyone
  holding it can post as the server, so it is never committed, never written
  to a file, and never printed -- including on the failure paths, which is why
  the retry hint names the variable instead of echoing the URL.

  The notes are the changelog's newest section, the same text the release
  itself carries (the workflow writes it to CHANGELOG-release.md, and this
  falls back to cutting CHANGELOG.md the same way). One release, one set of
  words, wherever you read them.

No dependencies: urllib, because Tools/ is plain Python and a release step is
the wrong place to need a pip install.
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
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
CUT_NOTES = os.path.join(ROOT, "CHANGELOG-release.md")

REPO = "MelloCro/MelloUI"
RELEASES = f"https://github.com/{REPO}/releases"
CURSEFORGE = "https://www.curseforge.com/wow/addons/melloui"
ACCENT = 0x9B8CFF          # the TOC title colour, |cff9b8cff
DESCRIPTION_LIMIT = 4096   # Discord's hard cap on embed.description


def read(path: str) -> str:
    with io.open(path, encoding="utf-8") as fh:
        return fh.read().replace("﻿", "")


def toc_version() -> str:
    m = re.search(r"^##\s*Version:\s*(.+)$", read(TOC), re.M)
    return m.group(1).strip() if m else ""


def section(version: str = "") -> tuple[str, str]:
    """The changelog section to announce: (version, body).

    With no version it is the newest, which is what a release cuts. The
    workflow has usually already written that text to CHANGELOG-release.md --
    it is used when it is there, so the post and the release notes cannot
    differ even if the changelog is edited between the two steps.
    """
    if not version and os.path.isfile(CUT_NOTES):
        body = read(CUT_NOTES).strip()
        if body:
            return toc_version(), body

    want = version.lstrip("vV").strip()
    current, body = "", []
    for line in read(CHANGELOG).splitlines():
        head = re.match(r"^##\s+(.+?)\s*$", line)
        if head:
            if current:                      # the section we were collecting ended
                break
            found = head.group(1).strip()
            if not want or found.lstrip("vV").lower() == want.lower():
                current = found
            continue
        if current:
            body.append(line)
    return current, "\n".join(body).strip()


def describe(body: str, version: str) -> str:
    """The changelog section as Discord will render it.

    Markdown carries over unchanged -- Discord understands the bullets and the
    `code spans` the changelog already uses. Only the length is a problem, and
    an over-long description is a 400 for the whole message, so it is cut on a
    bullet boundary and sent with a link to the rest.
    """
    if len(body) <= DESCRIPTION_LIMIT:
        return body
    tail = f"\n\n[Read the rest of the notes]({RELEASES}/tag/v{version})"
    room = DESCRIPTION_LIMIT - len(tail)
    cut = body[:room]
    at = cut.rfind("\n- ")
    return (cut[:at] if at > room * 0.5 else cut).rstrip() + tail


def payload(version: str, body: str, role_id: str = "") -> dict:
    embed = {
        "title": f"MelloUI {version}",
        "url": f"{RELEASES}/tag/v{version}",
        "color": ACCENT,
        "description": describe(body, version),
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
        ],
        "footer": {"text": "Your settings are kept. /mello status says where they came from."},
    }
    out = {
        "username": "MBot",
        "embeds": [embed],
        # Nothing in the notes may ping anybody. Without this an @everyone that
        # someone wrote into a changelog bullet would go out to the whole
        # server -- with the role id below added back explicitly when there is
        # one, which is the only mention this post is allowed to make.
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
    parser.add_argument("--version", default="", help="which release to announce (default: the newest)")
    parser.add_argument("--dry-run", action="store_true", help="print the payload, post nothing")
    args = parser.parse_args()

    version, body = section(args.version)
    version = (version or toc_version()).lstrip("vV")
    if not version or not body:
        print(f"no changelog section found for {args.version or 'the newest version'} -- nothing announced")
        return 0

    role_id = os.environ.get("DISCORD_RELEASE_ROLE_ID", "").strip()
    data = payload(version, body, role_id)

    if args.dry_run:
        print(json.dumps(data, indent=2, ensure_ascii=False))
        print(f"\n({len(data['embeds'][0]['description'])} of {DESCRIPTION_LIMIT} description characters used)")
        return 0

    url = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not url:
        # Not an error: the webhook is optional, and a repository without one
        # should still release. Said out loud so it is not a silent no-op.
        print("DISCORD_WEBHOOK_URL is not set -- skipping the Discord post.")
        return 0

    try:
        post(url, data)
        print(f"announced MelloUI {version} in Discord.")
    except (urllib.error.URLError, urllib.error.HTTPError, RuntimeError, TimeoutError) as e:
        detail = getattr(e, "reason", None) or getattr(e, "code", None) or e
        print(f"could not post to Discord: {detail}")
        print("The release itself is fine -- only the Discord post did not go out.")
        print(f"Retry by hand:  DISCORD_WEBHOOK_URL=... python Tools/discord_announce.py --version {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
