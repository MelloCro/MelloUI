"""Where the big generated folders live.

`Tools/output` (the built voice pack and every rendered preview, ~3 GB) and
`Tools/cache` (the downloaded cmangos dump and wago tables, ~350 MB) used to sit
inside the addon folder. They are generated, gitignored and enormous, and the
addon folder is something the user backs up and syncs, so they were moved out
(user, 2026-09-22) to a sibling folder:

    Project Web/MelloUI/            the addon and its tools
    Project Web/MelloUI-BuildData/  output/ and cache/

Nothing about the addon or the release depends on them. `.pkgmeta` already kept
`Tools` out of the zip, so this changes what is on disk, not what ships.

    from paths import OUTPUT, CACHE

Resolution order, so that a machine which never moved them still works:

    1. MELLOUI_BUILD_DATA, if it is set
    2. the old Tools/output, Tools/cache, if they are still there
    3. the sibling MelloUI-BuildData folder  (created on demand)

`pack_sources` deliberately did NOT move: it is the kit's source art, and
kitforge (in `MelloUI Test/tools/kitforge`) points straight at
`Tools/pack_sources/kit/v2_2x`.

The texture MASTERS moved out too (user, 2026-09-24: the compressed textures
approved; Media keeps only what ships). Every tool that paints art writes
its 32-bit TGA master under `MelloUI-BuildData/masters/Media/...`, at the path
the file used to have in the addon (masters/Media/Kit/window/frame_t.tga,
masters/Media/Textures/GameMenuFrame.tga ...), with the master
KitLayout.lua and KitSlices.lua beside them. The addon's Media holds what
the client loads, made from the masters by one command:

    python Tools/texture_pack.py ship

(BLP / DXT where the quality gate passes, atlas sheets for the small kit
pieces, TGA where it fails; Media/KitLayout.lua and Media/KitSlices.lua).
The masters never ship and are never written by that command.

    from paths import MASTERS, MASTER_MEDIA, ADDON_MEDIA

Resolution: MELLOUI_BUILD_DATA/masters if that is set, else the sibling
MelloUI-BuildData/masters (never inside the addon: the masters must not ship).
"""
from __future__ import annotations

import os

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
SIBLING = os.path.join(os.path.dirname(ADDON), "MelloUI-BuildData")


def _resolve(name: str) -> str:
    override = os.environ.get("MELLOUI_BUILD_DATA", "").strip()
    if override:
        return os.path.join(override, name)
    in_repo = os.path.join(HERE, name)
    if os.path.isdir(in_repo):
        return in_repo
    return os.path.join(SIBLING, name)


#: The built voice pack, rendered frames and every preview a tool writes.
OUTPUT = _resolve("output")
#: Downloaded source data: the cmangos dump, wago tables, Wowhead pages.
CACHE = _resolve("cache")
#: The cut source art the kit is built from. Still inside Tools -- see above.
PACK_SOURCES = os.path.join(HERE, "pack_sources")


def _masters() -> str:
    override = os.environ.get("MELLOUI_BUILD_DATA", "").strip()
    return os.path.join(override if override else SIBLING, "masters")


#: The texture masters (32-bit TGA, never shipped) and their layout data.
MASTERS = _masters()
#: ... laid out as the addon's Media was: MASTER_MEDIA/Kit/window/frame_t.tga
MASTER_MEDIA = os.path.join(MASTERS, "Media")
#: The addon's own Media: what the client loads (and the ship step writes).
ADDON_MEDIA = os.path.join(ADDON, "Media")


def master(*parts: str) -> str:
    """A path under the masters' Media, for a tool that writes or reads a
    TGA master: master("Textures", "GameMenuFrame.tga")."""
    return os.path.join(MASTER_MEDIA, *parts)


def ensure(path: str) -> str:
    """Make a folder and return it, for a tool that is about to write into it."""
    os.makedirs(path, exist_ok=True)
    return path


if __name__ == "__main__":
    for label, value in (("OUTPUT", OUTPUT), ("CACHE", CACHE), ("PACK_SOURCES", PACK_SOURCES),
                         ("MASTERS", MASTERS), ("ADDON_MEDIA", ADDON_MEDIA)):
        print(f"{label:14} {value}{'' if os.path.isdir(value) else '   (does not exist yet)'}")
