"""
make_plain_plate.py -- a gemless row plate for the kit, from the row's own art.

lists/row_mid_<state>  ->  lists/plate_mid_<state>    (unchanged)
                       ->  lists/plate_cap_l_<state>  the mid's first columns,
                                                       closed by a vertical rail
                       ->  lists/plate_cap_r_<state>  mirrored
The vertical rail is the mid's own top-rail band rotated 90 degrees, so the
plate closes with the same bevel it has along its top and bottom.
Writes into kit/v2_2x/lists/ and updates manifest.json; run build_kit.py after.
"""
import os, json
import numpy as np
from PIL import Image

KIT = r"C:\Users\mortu\Downloads\UITest\kit\v2_2x"
LISTS = os.path.join(KIT, "lists")
BUTTONS = os.path.join(KIT, "buttons")
CAP_W = 14          # cap width in piece px (2x): the rail plus a little slab
# (source mid base, output base, states)
PLATES = (
    ("row", "plate", ("plain", "hover", "selected")),        # list rows / stat rows
    ("category", "catplate", ("closed", "open")),            # category headers (no chevron, no label)
)
# gemless END caps for the gemmed button plates: buttons/<base>_end_{l,r}_<state>,
# the mid closed by its own rail, for a button whose gem cap on that side is dropped
ENDS = (
    ("redbtn", ("normal", "hover", "pressed", "disabled")),
    ("textbtn", ("normal", "hover", "pressed", "disabled")),
)


def rail_band(a):
    """Rows of the top rail: from the first opaque row down to where the
    bright bevel gives way to the dark slab."""
    al = a[..., 3]
    lum = a[..., :3].mean(axis=2)
    rows = np.where((al > 128).mean(axis=1) > 0.5)[0]
    top = rows.min()
    core = lum[top:rows.max() + 1][:, a.shape[1] // 4: 3 * a.shape[1] // 4].mean(axis=1)
    slab = core[len(core) // 2]                      # the slab's brightness, mid-height
    y = top
    while y < rows.max() and lum[y, a.shape[1] // 4: 3 * a.shape[1] // 4].mean() > slab * 1.35:
        y += 1
    return top, max(y, top + 3), rows.max() + 1


def end_caps(base, state):
    mid = np.array(Image.open(os.path.join(BUTTONS, f"{base}_mid_{state}.png")).convert("RGBA"))
    H, W = mid.shape[:2]
    top, rail_end, bottom = rail_band(mid)
    rail_h = rail_end - top
    band = mid[top:rail_end, W // 4: W // 4 + (bottom - top)]
    vert = np.rot90(band, k=-1)[: bottom - top]
    cap = mid[:, :CAP_W].copy()
    cap[top:top + vert.shape[0], :rail_h] = vert[:, :rail_h]
    cap[top:rail_end, :rail_h] = mid[top:rail_end, :rail_h]
    cap[bottom - rail_h:bottom, :rail_h] = mid[bottom - rail_h:bottom, :rail_h]
    Image.fromarray(cap).save(os.path.join(BUTTONS, f"{base}_end_l_{state}.png"))
    Image.fromarray(cap[:, ::-1].copy()).save(os.path.join(BUTTONS, f"{base}_end_r_{state}.png"))
    return cap.shape


def make(src, dst, state):
    mid = np.array(Image.open(os.path.join(LISTS, f"{src}_mid_{state}.png")).convert("RGBA"))
    H, W = mid.shape[:2]
    top, rail_end, bottom = rail_band(mid)
    rail_h = rail_end - top
    # the rail as a vertical strip: a slice of the top rail, rotated
    band = mid[top:rail_end, W // 4: W // 4 + (bottom - top)]          # rail_h x plateH
    vert = np.rot90(band, k=-1)                                          # plateH x rail_h
    vert = vert[: bottom - top]
    cap = mid[:, :CAP_W].copy()
    cap[top:top + vert.shape[0], :rail_h] = vert[:, :rail_h]
    # keep the horizontal rails over the corner so the joint reads as a mitre
    cap[top:rail_end, :rail_h] = mid[top:rail_end, :rail_h]
    cap[bottom - rail_h:bottom, :rail_h] = mid[bottom - rail_h:bottom, :rail_h]
    cap_l = cap
    cap_r = cap[:, ::-1].copy()
    Image.fromarray(cap_l).save(os.path.join(LISTS, f"{dst}_cap_l_{state}.png"))
    Image.fromarray(mid).save(os.path.join(LISTS, f"{dst}_mid_{state}.png"))
    Image.fromarray(cap_r).save(os.path.join(LISTS, f"{dst}_cap_r_{state}.png"))
    return { f"lists/{dst}_cap_l_{state}": cap_l.shape, f"lists/{dst}_mid_{state}": mid.shape, f"lists/{dst}_cap_r_{state}": cap_r.shape }, (top, rail_end, bottom)


def main():
    man_path = os.path.join(KIT, "manifest.json")
    man = json.load(open(man_path))
    for src, dst, states in PLATES:
        for state in states:
            pieces, info = make(src, dst, state)
            for name, shape in pieces.items():
                man["v2_2x/" + name] = { "w": int(shape[1]), "h": int(shape[0]), "scale": 1.0, "src": f"synth from {src}_mid_{state}" }
            print(dst, state, "rail rows", info)
    for base, states in ENDS:
        for state in states:
            shape = end_caps(base, state)
            for side in ("l", "r"):
                man[f"v2_2x/buttons/{base}_end_{side}_{state}"] = { "w": int(shape[1]), "h": int(shape[0]), "scale": 1.0, "src": f"synth from {base}_mid_{state}" }
            print(base, state, "end caps", shape)
    json.dump(man, open(man_path, "w"), indent=1, sort_keys=True)
    # preview
    row = []
    for _, dst, states in PLATES:
      for state in states:
        parts = [Image.open(os.path.join(LISTS, f"{dst}_{p}_{state}.png")).convert("RGBA") for p in ("cap_l", "mid", "cap_r")]
        w = sum(p.width for p in parts); h = parts[0].height
        line = Image.new("RGBA", (w, h)); x = 0
        for p in parts:
            line.alpha_composite(p, (x, 0)); x += p.width
        row.append(line)
    sheet = Image.new("RGBA", (max(r.width for r in row) + 20, sum(r.height + 10 for r in row) + 10), (50, 50, 50, 255)); y = 10
    for r in row:
        sheet.alpha_composite(r, (10, y)); y += r.height + 10
    sheet = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    sheet.save(os.path.join(KIT, "..", "..", "kit_raw", "plate_preview.png"))


if __name__ == "__main__":
    main()
