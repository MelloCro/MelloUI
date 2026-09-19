"""
Generate the soft click sounds the configuration window uses, as Ogg Vorbis
files in Media/Sounds. Pure synthesis (numpy + soundfile), no samples.

    python Tools\make_ui_sounds.py

Sounds:
    check_on.ogg    checkbox ticked: short warm tock, rising a touch
    check_off.ogg   checkbox cleared: the same, a little lower and softer
    tab.ogg         tab switch: two quick soft ticks
    page.ogg        page switch (icon strip, tiles): soft whoosh with a low pop
"""
import os
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Media", "Sounds")
SR = 44100


def env(n, attack, decay):
    """Exponential decay after a short linear attack, n samples."""
    t = np.arange(n) / SR
    e = np.exp(-t / decay)
    a = int(attack * SR)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def tone(freq, seconds, decay, attack=0.002, harmonics=((1, 1.0), (2, 0.25), (3, 0.08))):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for mult, amp in harmonics:
        out += amp * np.sin(2 * np.pi * freq * mult * t)
    return out * env(n, attack, decay)


def noise_burst(seconds, decay, lowpass=0.15, seed=1):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    x = rng.standard_normal(n)
    # one-pole low-pass for a soft, woody transient
    y = np.zeros(n)
    acc = 0.0
    for i in range(n):
        acc += lowpass * (x[i] - acc)
        y[i] = acc
    return y * env(n, 0.0005, decay)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def normalise(x, peak=0.45):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def pad(x, seconds=0.03):
    return np.concatenate([x, np.zeros(int(seconds * SR))])


def write(name, data):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    sf.write(path, pad(normalise(data)).astype(np.float32), SR, format="OGG", subtype="VORBIS")
    print(name, f"{len(data) / SR * 1000:.0f} ms")


def tock(freq, body_decay, click_gain=0.35):
    return mix(
        tone(freq, 0.12, body_decay),
        tone(freq * 0.5, 0.10, body_decay * 0.8, harmonics=((1, 0.6),)),
        noise_burst(0.02, 0.004) * click_gain,
    )


def shifted(x, seconds):
    return np.concatenate([np.zeros(int(seconds * SR)), x])


def main():
    write("check_on.ogg", tock(880, 0.030))
    write("check_off.ogg", tock(660, 0.026, click_gain=0.25) * 0.85)
    write("tab.ogg", mix(tock(1046, 0.018, click_gain=0.3) * 0.8, shifted(tock(784, 0.024, click_gain=0.3), 0.055)))
    # page: airy whoosh that swells and dies, with a soft low pop at its peak
    whoosh = noise_burst(0.20, 0.06, lowpass=0.06, seed=3)
    n = len(whoosh)
    swell = np.sin(np.linspace(0, np.pi, n)) ** 2
    whoosh = whoosh / (np.max(np.abs(whoosh)) or 1) * swell
    pop = shifted(tone(330, 0.16, 0.05, harmonics=((1, 1.0), (2, 0.15))), 0.05)
    write("page.ogg", mix(whoosh * 0.6, pop))


if __name__ == "__main__":
    main()
