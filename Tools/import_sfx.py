r"""
Bring the custom UI sound library into the addon: the FIRST variant of every
sound (user, 2026-09-22: "i would just go with the first variant of each")
encoded as Ogg Vorbis into Media/Sounds/SFX/<Name>.ogg, where the Custom
Sounds module (Modules/CustomSounds.lua) plays them by name.

    python Tools\import_sfx.py [source folder] [--variant N] [--all] [--picks FILE]

The source is the SFX library folder (default below): 48 kHz 24-bit WAV
masters in category folders, "<Name>_01.wav" .. "<Name>_NN.wav". The WAVs
are not shipped (the game reads Ogg, and they are 24-bit); the Oggs keep the
sample rate and the library's relative loudness, nothing is normalised.

--all keeps every variant as <Name>_NN.ogg beside <Name>.ogg, for a later
round-robin. --picks takes the user's chosen variant per sound from a list of
"<Name> = NN" lines (a set's picks.txt, e.g. the Modern set's: the names carry
the set's prefix, so the Oggs land beside the others as Modern_<Name>.ogg) and
brings in only those. A NEW .ogg needs a full client restart, not /reload.
"""
import os
import re
import sys
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Media", "Sounds", "SFX")
DEFAULT_SOURCE = r"F:\Download-Backup\Project Web\MelloUI\Workspace\Test\SFX"


def read_picks(path):
    """'<Name> = NN ...' lines -> {name: NN}; '#' lines are notes"""
    picks = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s*([^#=\s]+)\s*=\s*(\d+)", line)
            if m:
                picks[m.group(1)] = int(m.group(2))
    return picks


def main():
    argv = sys.argv[1:]
    valued = {"--variant", "--picks"}
    args = [a for i, a in enumerate(argv) if not a.startswith("--") and (i == 0 or argv[i - 1] not in valued)]
    source = args[0] if args else DEFAULT_SOURCE
    variant = 1
    if "--variant" in argv:
        variant = int(argv[argv.index("--variant") + 1])
    keep_all = "--all" in argv
    chosen = read_picks(argv[argv.index("--picks") + 1]) if "--picks" in argv else None
    os.makedirs(OUT, exist_ok=True)
    groups = {}
    for root, _, files in os.walk(source):
        for name in files:
            m = re.match(r"^(.*)_(\d\d)\.wav$", name, re.I)
            if m:
                groups.setdefault(m.group(1), []).append((int(m.group(2)), os.path.join(root, name)))
    if not groups:
        sys.exit("no <Name>_NN.wav files under " + source)
    if chosen is not None:
        missing = sorted(n for n, v in chosen.items() if v not in {i for i, _ in groups.get(n, [])})
        if missing:
            sys.exit("picked but not in the library: " + ", ".join(missing))
    written = []
    for base in sorted(groups):
        if chosen is not None and base not in chosen:
            continue
        variants = sorted(groups[base])
        if chosen is not None:
            picks = [v for v in variants if v[0] == chosen[base]]
        else:
            picks = variants if keep_all else [v for v in variants if v[0] == variant] or variants[:1]
        for index, path in picks:
            data, rate = sf.read(path)
            target = base + (("_%02d" % index) if keep_all else "") + ".ogg"
            out = os.path.join(OUT, target)
            sf.write(out, data, rate, format="OGG", subtype="VORBIS")
            written.append((target, len(data) / rate, os.path.getsize(out)))
    for name, seconds, size in written:
        print("%-36s %6.0f ms %7d bytes" % (name, seconds * 1000, size))
    print("%d files in %s" % (len(written), os.path.abspath(OUT)))


if __name__ == "__main__":
    main()
