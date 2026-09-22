r"""
Bring the custom UI sound library into the addon: the FIRST variant of every
sound (user, 2026-09-22: "i would just go with the first variant of each")
encoded as Ogg Vorbis into Media/Sounds/SFX/<Name>.ogg, where the Custom
Sounds module (Modules/CustomSounds.lua) plays them by name.

    python Tools\import_sfx.py [source folder] [--variant N] [--all]

The source is the SFX library folder (default below): 48 kHz 24-bit WAV
masters in category folders, "<Name>_01.wav" .. "<Name>_NN.wav". The WAVs
are not shipped (the game reads Ogg, and they are 24-bit); the Oggs keep the
sample rate and the library's relative loudness, nothing is normalised.

--all keeps every variant as <Name>_NN.ogg beside <Name>.ogg, for a later
round-robin. A NEW .ogg needs a full client restart, not /reload.
"""
import os
import re
import sys
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Media", "Sounds", "SFX")
DEFAULT_SOURCE = r"F:\Download-Backup\Project Web\MelloUI Test\SFX"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    source = args[0] if args else DEFAULT_SOURCE
    variant = 1
    if "--variant" in sys.argv:
        variant = int(sys.argv[sys.argv.index("--variant") + 1])
    keep_all = "--all" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    groups = {}
    for root, _, files in os.walk(source):
        for name in files:
            m = re.match(r"^(.*)_(\d\d)\.wav$", name, re.I)
            if m:
                groups.setdefault(m.group(1), []).append((int(m.group(2)), os.path.join(root, name)))
    if not groups:
        sys.exit("no <Name>_NN.wav files under " + source)
    written = []
    for base in sorted(groups):
        variants = sorted(groups[base])
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
