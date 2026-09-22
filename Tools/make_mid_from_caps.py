"""
make_mid_from_caps.py -- for cap/mid/cap sets whose caps and middle were painted
as separate plates (and so do not meet on the same rows), rebuild the middle
from the caps' own joint columns: the left cap's last N columns and the right
cap's first N columns, cross-faded and repeated. Rails, slab and shade then
continue exactly across the joint.

The painted middle keeps its texture: its rows are resampled band by band
(top rail, slab, bottom rail) onto the rows the cap has at its joint, and the
slab is tinted to the red button's red.
"""
import os, sys, json
import numpy as np
from PIL import Image

KIT = r"C:\Users\mortu\Downloads\UITest\kit\v2_2x"
PROFILE = 4     # columns taken from the cap's joint end (past the glyphs)
MID_W = 128     # width of the rebuilt middle


def bands(col_lum, opaque):
    """(top, end of the top rail, start of the bottom rail, bottom) from a
    column: the rails are the first and last runs brighter than 1.3 x the slab
    (a dark outline may precede the top rail)."""
    rows = np.where(opaque)[0]
    top, bot = rows.min(), rows.max() + 1
    lum = col_lum[top:bot]
    n = len(lum)
    slab = np.median(lum[n // 4: 3 * n // 4])
    bright = lum > slab * 1.3
    a = 0
    while a < n and not bright[a]:
        a += 1
    b = a
    while b < n and bright[b]:
        b += 1
    d = n
    while d > 0 and not bright[d - 1]:
        d -= 1
    c = d
    while c > 0 and bright[c - 1]:
        c -= 1
    if b <= 0 or c <= b:
        b, c = max(1, n // 8), n - max(1, n // 8)
    return top, top + b, top + c, bot


def remap_rows(img, src_marks, dst_marks, H):
    """piecewise vertical resample: each band between consecutive marks of the
    source is resized onto the band between the matching destination marks."""
    out = np.zeros((H, img.shape[1], 4), np.float64)
    for k in range(len(src_marks) - 1):
        s0, s1 = src_marks[k], src_marks[k + 1]
        d0, d1 = dst_marks[k], dst_marks[k + 1]
        if s1 <= s0 or d1 <= d0:
            continue
        band = Image.fromarray(np.clip(img[s0:s1], 0, 255).astype(np.uint8)).resize((img.shape[1], d1 - d0), Image.LANCZOS)
        out[d0:d1] = np.array(band).astype(np.float64)
    return out


def rebuild(base, state, mid_from, red_from="buttons/redbtn_mid_normal"):
    def load(name):
        return np.array(Image.open(os.path.join(KIT, name + ".png")).convert("RGBA")).astype(float)
    cap = load(f"{base}_cap_l_{state}")
    src = load(mid_from)
    H = cap.shape[0]
    # landmarks: the cap's joint column, the painted middle's centre column
    ccol = cap[:, -PROFILE:].mean(axis=1)
    cmarks = bands(ccol[:, :3].mean(axis=1), ccol[:, 3] > 128)
    mcol = src[:, src.shape[1] // 2 - 2: src.shape[1] // 2 + 2].mean(axis=1)
    mmarks = bands(mcol[:, :3].mean(axis=1), mcol[:, 3] > 128)
    print(f"  cap rails/slab rows {cmarks}, painted middle {mmarks}")
    mid = remap_rows(src, (0,) + mmarks + (src.shape[0],), (0,) + cmarks + (H,), H)
    # the slab tinted to the red button's red
    rows = np.arange(cmarks[1], cmarks[2])
    ref = load(red_from)
    rr, rg, rb, ral = ref[..., 0], ref[..., 1], ref[..., 2], ref[..., 3]
    target = ref[(ral > 128) & (rr > 60) & (rr > rg * 1.6) & (rr > rb * 1.6)][:, :3].mean(axis=0)
    slab = mid[rows][..., :3].reshape(-1, 3)
    cur = slab[(slab[:, 0] > 60) & (slab[:, 0] > slab[:, 1] * 1.6)].mean(axis=0) if (slab[:, 0] > 60).any() else slab.mean(axis=0)
    mid[rows, :, :3] = np.clip(mid[rows, :, :3] * (target / np.maximum(cur, 1)), 0, 255)
    out = os.path.join(KIT, f"{base}_mid_{state}.png")
    Image.fromarray(np.clip(mid, 0, 255).astype(np.uint8)).save(out)
    man_path = os.path.join(KIT, "manifest.json")
    man = json.load(open(man_path))
    key = f"v2_2x/{base}_mid_{state}"
    man[key] = dict(man.get(key, {}), w=int(mid.shape[1]), h=int(mid.shape[0]), src=f"{mid_from} rows remapped onto {base}_cap_l_{state}")
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)
    print(f"{base}_mid_{state}: {mid.shape[1]}x{mid.shape[0]}, rows remapped to the cap")


if __name__ == "__main__":
    rebuild("tabs/top", "title", mid_from="tabs/top_mid_open")
