"""
normalize.py -- scale kit/<variant>/ to the 2x sizes in docs/UI-KIT.md,
writing kit/<variant>_2x/.

One scale factor per FAMILY (nine-slice, a cap/mid/cap set, a button's states),
taken from the family's reference piece and its reference measure, so pieces
that join keep joining.  All states of one piece are then forced to the exact
same pixel size (they differ by a pixel or two in the source), and the tiles
are forced square.
"""
import os, re, sys, json, shutil
import numpy as np
from PIL import Image
import name_kit as nk   # seam helpers

KIT = r"C:\Users\mortu\Downloads\UITest\kit"
variant = sys.argv[1] if len(sys.argv) > 1 else "v2"
SRC, DST = os.path.join(KIT, variant), os.path.join(KIT, variant + "_2x")

# (member regex, reference piece, measure, target px at 2x)
#   measure: h/w = opaque height/width of the reference, max = larger opaque dim
FAMILIES = [
    (r"window/frame_(t|b|l|r|tl|tr|bl|br)$", "window/frame_t",         "h",   48),   # edges 24 thick
    (r"window/frame_body$",                  "window/frame_body",      "h",   512),
    (r"window/title_",                       "window/title_mid",       "h",   72),   # 36 tall
    (r"window/divider_",                     "window/divider_mid",     "h",   16),   # 8 tall
    (r"window/portrait_ring$",               "window/portrait_ring",   "h",   192),
    (r"window/close_",                       "window/close_normal",    "h",   56),
    (r"window/corner_ornament_tl$",          "window/corner_ornament_tl", "max", 96),
    (r"buttons/textbtn_",                    "buttons/textbtn_mid_normal", "h", 64),
    (r"buttons/redbtn_",                     "buttons/redbtn_mid_normal",  "h", 64),
    (r"buttons/slot_",                       "buttons/slot_normal",    "h",   128),
    (r"buttons/roundslot_",                  "buttons/roundslot_normal", "h", 128),
    (r"buttons/orb_",                        "buttons/orb_normal",     "h",   96),
    (r"buttons/cog_",                        "buttons/cog_normal",     "h",   48),
    (r"buttons/arrow_",                      "buttons/arrow_up_normal", "h",  40),
    (r"buttons/checkbox_",                   "buttons/checkbox_off",   "h",   40),
    (r"buttons/(plus|minus)_",               "buttons/plus_normal",    "h",   36),
    (r"tabs/top_",                           "tabs/top_mid_plain",     "h",   64),
    (r"tabs/bottom_",                        "tabs/bottom_mid_plain",  "h",   72),
    (r"tabs/side_",                          "tabs/side_plain",        "h",   92),
    (r"lists/row_",                          "lists/row_mid_plain",    "h",   56),
    (r"lists/header_",                       "lists/header_mid",       "h",   60),
    (r"lists/category_",                     "lists/category_mid_closed", "h", 60),
    (r"lists/scrolltrack_",                  "lists/scrolltrack_mid",  "w",   32),
    (r"lists/scrollthumb_",                  "lists/scrollthumb_normal", "w", 32),
    (r"lists/card_",                         "lists/card_plain",       "h",   224),
    (r"inputs/edit_",                        "inputs/edit_mid_normal", "h",   56),
    (r"inputs/search_",                      "inputs/search_mid_normal", "h", 56),
    (r"inputs/dropdown_",                    "inputs/dropdown_mid_normal", "h", 56),
    (r"inputs/slider_(cap|mid)",             "inputs/slider_mid",      "h",   24),
    (r"inputs/slider_thumb_",                "inputs/slider_thumb_normal", "h", 40),
    (r"bars/frame_",                         "bars/frame_mid",         "h",   40),
    (r"bars/trough$",                        "bars/trough",            "h",   40),
    (r"bars/tick$",                          "bars/tick",              "h",   40),
    (r"bars/castbar_",                       "bars/castbar_mid",       "h",   40),   # same trough as plain caps
    (r"deco/gem_small$",                     "deco/gem_small",         "h",   24),
    (r"deco/gem_large$",                     "deco/gem_large",         "h",   40),
    (r"deco/gemarrow_",                      "deco/gemarrow_l",        "h",   24),
    (r"deco/gem_joint$",                     "deco/gem_joint",         "w",   48),
    (r"deco/ornament",                       "deco/ornament_tl",       "max", 96),
    (r"deco/rail_",                          "deco/rail_mid",          "h",   96),
    (r"tiles/ironplate$",                    "tiles/ironplate",        "w",   256),
    (r"tiles/",                              None,                     "w",   512),   # each tile on its own
]
STATE = re.compile(r"_(normal|hover|pressed|checked|disabled|plain|open|closed|selected|focused|off|on)$")
SQUARE = re.compile(r"(tiles/|window/frame_body$)")


def _bbox(a):
    m = a[..., 3] > 128
    ys, xs = np.where(m)
    if len(ys) == 0:
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def measure(a, how):
    m = a[..., 3] > 128
    ys, xs = np.where(m)
    h, w = ys.max() - ys.min() + 1, xs.max() - xs.min() + 1
    return {"h": h, "w": w, "max": max(h, w)}[how]


def main():
    man = json.load(open(os.path.join(KIT, "manifest.json")))
    names = sorted(n.split("/", 1)[1] for n in man if n.startswith(variant + "/"))
    if os.path.isdir(DST):
        shutil.rmtree(DST, ignore_errors=True)
    load = lambda n: np.array(Image.open(os.path.join(SRC, n + ".png")).convert("RGBA"))

    # 1. factor per family
    factor, family_of = {}, {}
    for n in names:
        if n.endswith("_art"):
            continue
        for i, (rx, ref, how, target) in enumerate(FAMILIES):
            if re.match(rx, n):
                key = i if ref else n           # tiles: each is its own family
                if key not in factor:
                    factor[key] = target / measure(load(ref or n), how)
                family_of[n] = key
                break
        else:
            print("  !! no family rule for", n)

    # 2. scale; then force every state of one piece to the first state's size
    out, role_size, report = {}, {}, {}
    for n in names:
        if n not in family_of:
            continue
        f = factor[family_of[n]]
        a = load(n)
        if SQUARE.search(n):
            # tiles: uniform scale so the pattern isn't squashed, one seamless period,
            # capped at 3x so a small crop doesn't turn to mush
            target = FAMILIES[family_of[n]][3] if isinstance(family_of[n], int) else 512
            f = min(target / max(a.shape[:2]), 3.0)
        w, h = max(1, round(a.shape[1] * f)), max(1, round(a.shape[0] * f))
        role = STATE.sub("", n)
        w, h = role_size.setdefault(role, (w, h))
        im = Image.fromarray(a).resize((w, h), Image.LANCZOS)
        # resampling softens the wrap edge: re-seal it, and keep repeatable middles a sane length
        axes = nk.seamless_axes(variant + "/" + n)
        if axes:
            arr = np.array(im)
            for ax in axes:
                if ax == "x" and arr.shape[1] > 600:
                    arr = arr[:, :600]
                arr, _ = nk.make_seamless(arr, ax, min_frac=0.9)
            im = Image.fromarray(arr); w, h = im.size
            role_size[role] = (w, h)
        path = os.path.join(DST, n + ".png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        im.save(path)
        out[variant + "_2x/" + n] = {"w": w, "h": h, "scale": round(f, 4), "src": man[variant + "/" + n]["src"]}
        report.setdefault(family_of[n], []).append((n, a.shape[1], a.shape[0], w, h))

    # 3. every state of one piece shares the same OPAQUE extent (the game's hover
    #    and selection cover the same rectangle): the other states' opaque box is
    #    resized onto the first state's box
    STATE_ORDER = ("normal", "plain", "closed", "off")
    roles = {}
    for n in list(out):
        rel = n.split("/", 1)[1]
        role = STATE.sub("", rel)
        if role != rel:
            roles.setdefault(role, []).append(rel)
    equalised = 0
    for role, members in roles.items():
        members.sort(key=lambda m: next((i for i, st in enumerate(STATE_ORDER) if m.endswith("_" + st)), 99))
        ref = np.array(Image.open(os.path.join(DST, members[0] + ".png")).convert("RGBA"))
        rb = _bbox(ref)
        if rb is None:
            continue
        for m in members[1:]:
            path = os.path.join(DST, m + ".png")
            cur = np.array(Image.open(path).convert("RGBA"))
            cb = _bbox(cur)
            if cb is None or (cb == rb and cur.shape == ref.shape):
                continue
            core = Image.fromarray(cur[cb[1]:cb[3], cb[0]:cb[2]]).resize((rb[2] - rb[0], rb[3] - rb[1]), Image.LANCZOS)
            canvas = np.zeros(ref.shape, np.uint8)
            canvas[rb[1]:rb[3], rb[0]:rb[2]] = np.array(core)
            Image.fromarray(canvas).save(path)
            out[variant + "_2x/" + m].update({"w": int(canvas.shape[1]), "h": int(canvas.shape[0]), "equalised_to": members[0]})
            equalised += 1
    print(f"{equalised} state pieces equalised to their first state's opaque extent")

    json.dump(out, open(os.path.join(DST, "manifest.json"), "w"), indent=1, sort_keys=True)

    print(f"{len(out)} pieces -> {DST}\n")
    print(f"{'family reference':34s} {'scale':>6s}   native -> 2x (reference piece)")
    for key, rows in report.items():
        rx, ref, how, target = FAMILIES[key] if isinstance(key, int) else (key, key, "w", 512)
        r = next((r for r in rows if r[0] == (ref or key)), rows[0])
        print(f"{(ref or key):34s} {factor[key]:6.3f}   {r[1]}x{r[2]} -> {r[3]}x{r[4]}   target {how}={target}")


if __name__ == "__main__":
    main()
