"""
blp_dxt.py -- BLP2 texture files with DXT (BC1 / BC3) compression, in numpy.

The client's own texture format: the GPU samples DXT blocks as they are, so a
BLP is read from disk at 1/4 (DXT5) or 1/8 (DXT1) of a 32-bit TGA's bytes and
uploaded without being unpacked, and it holds 1/4 or 1/8 of the video memory.

  BC1 (DXT1)  8 bytes per 4x4 block: two RGB565 endpoints + 2-bit indices.
              Opaque art (alpha depth 0), or art whose alpha is only 0 / 255
              (alpha depth 1: the block's 3-colour mode, index 3 = transparent
              black).
  BC3 (DXT5) 16 bytes per block: the BC1 colour block (always 4-colour) after
              an alpha block (two 8-bit endpoints + 3-bit indices), for art
              with smooth alpha (anti-aliased edges, soft shadows, masks).

The block encoder (all blocks of an image at once, in chunks):
  colour  weighted principal axis of the block's pixels (power iteration on
          the covariance), endpoints at the extreme projections; the
          bounding box on that axis's diagonal as a second candidate; then
          least-squares refits of both endpoints from the chosen indices, and
          a +-1 step search on each of the six quantised 565 components.
          Pixels are weighted by their alpha (a nearly transparent pixel's
          colour hardly shows), with a small floor so the colour under the
          edge of a shape (what bilinear filtering blends in) stays close.
  alpha   both BC3 modes tried per block (8 levels between min and max, or
          6 levels between the inner min / max plus exact 0 and 255), the
          8-level one refitted by least squares and a +-1 search; the better
          one kept.

BLP2 header (1172 bytes before the data; little-endian):
  "BLP2", uint32 type = 1, uint8 encoding = 2 (DXT), uint8 alpha depth
  (0 / 1 / 8), uint8 alpha encoding (0 = DXT1, 7 = DXT5), uint8 has-mips,
  uint32 width, uint32 height, uint32 mip offsets[16], uint32 mip sizes[16],
  256 x uint32 palette (unused by DXT, zero).
  Mip chain: complete, each level half the last on both sides (a side that
  has reached 1 stays 1) down to 1 x 1, as the format expects. The square
  VoiceOver BLPs the addon draws chain to 1 x 1 like this; the one
  non-square BLP in Media (VoiceOver/BackgroundGradient, 256 x 16) stops at
  16 x 1, but no Lua file draws it, so it proves nothing about a short
  chain -- which is why none is written (and texture_pack's probe has a
  non-square file to confirm the full chain in game).

Hidden colour: under alpha 0 a TGA may hold any RGB (637 of the kit's TGAs
hold non-black colour there). bleed() fills it from the nearest visible
texels before a DXT5 level is encoded, so a block along a shape's edge
spends its four colours on what shows, and the colour that bilinear
filtering pulls in from a transparent neighbour (straight alpha: it blends
the RGB before the alpha) is the edge's own, not a dark or stray fringe.
DXT1 with 1-bit alpha decodes every transparent texel as black whatever it
held, so it is left as painted (those TGAs hold black there already).

Decoders: decode_gpu() follows the D3D block rules (565 expanded by bit
replication, rounded interpolation); decode_pillow() reproduces PIL's
BlpImagePlugin exactly (565 expanded by a plain shift, floored interpolation),
so a file can be checked bit for bit against what Pillow reads.
"""
import struct

import numpy as np

HEADER_SIZE = 1172
ENC_DXT = 2
AE_DXT1, AE_DXT5 = 0, 7

CHUNK = 16384                                           # blocks per numpy pass

_E5 = ((np.arange(32) << 3) | (np.arange(32) >> 2)).astype(np.int32)
_E6 = ((np.arange(64) << 2) | (np.arange(64) >> 4)).astype(np.int32)
_Q5 = np.abs(_E5[None, :] - np.arange(256)[:, None]).argmin(1).astype(np.int32)
_Q6 = np.abs(_E6[None, :] - np.arange(256)[:, None]).argmin(1).astype(np.int32)
_QMAX = np.array([31, 63, 31], np.int32)


# ---------------------------------------------------------------- blocks

def to_blocks(img):
    """HxWxC -> (H/4 * W/4, 16, C), row-major blocks; a side under 4 is
    padded by repeating its last row / column (the decoder crops it off)."""
    h, w = img.shape[:2]
    ph, pw = max(4, (h + 3) // 4 * 4), max(4, (w + 3) // 4 * 4)
    if (ph, pw) != (h, w):
        img = np.pad(img, ((0, ph - h), (0, pw - w), (0, 0)), mode="edge")
    c = img.shape[2]
    return img.reshape(ph // 4, 4, pw // 4, 4, c).transpose(0, 2, 1, 3, 4).reshape(-1, 16, c)


def from_blocks(blocks, h, w):
    ph, pw = max(4, (h + 3) // 4 * 4), max(4, (w + 3) // 4 * 4)
    c = blocks.shape[2]
    img = blocks.reshape(ph // 4, pw // 4, 4, 4, c).transpose(0, 2, 1, 3, 4).reshape(ph, pw, c)
    return img[:h, :w]


# ---------------------------------------------------------------- colour

def _quantise(ep):
    v = np.clip(np.rint(ep), 0, 255).astype(np.int32)
    return np.stack([_Q5[v[:, 0]], _Q6[v[:, 1]], _Q5[v[:, 2]]], 1)


def _expand(q):
    return np.stack([_E5[q[:, 0]], _E6[q[:, 1]], _E5[q[:, 2]]], 1).astype(np.float32)


def _pack565(q):
    return ((q[:, 0] << 11) | (q[:, 1] << 5) | q[:, 2]).astype(np.int32)


def _palette(q0, q1, mode):
    e0, e1 = _expand(q0), _expand(q1)
    if mode == 4:
        return np.stack([e0, e1, (2 * e0 + e1) / 3, (e0 + 2 * e1) / 3], 1)
    return np.stack([e0, e1, (e0 + e1) / 2], 1)


def _eval_colour(px, w, q0, q1, mode):
    pal = _palette(q0, q1, mode)                                   # (N, K, 3)
    d = ((px[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1)    # (N, 16, K)
    idx = d.argmin(-1)
    err = (np.take_along_axis(d, idx[..., None], -1)[..., 0] * w).sum(-1)
    return idx, err


_LSQ_W = {4: np.array([1, 0, 2 / 3, 1 / 3], np.float32), 3: np.array([1, 0, 0.5], np.float32)}


def _lsq(px, w, idx, mode):
    a = _LSQ_W[mode][idx]                                          # weight of endpoint 0
    b = 1 - a
    A, B, C = (w * a * a).sum(1), (w * a * b).sum(1), (w * b * b).sum(1)
    X0 = (w[..., None] * a[..., None] * px).sum(1)
    X1 = (w[..., None] * b[..., None] * px).sum(1)
    det = A * C - B * B
    ok = np.abs(det) > 1e-6
    sd = np.where(ok, det, 1)[:, None]
    e0 = (C[:, None] * X0 - B[:, None] * X1) / sd
    e1 = (A[:, None] * X1 - B[:, None] * X0) / sd
    return e0, e1, ok


def _pca(px, w):
    n = px.shape[0]
    ws = w.sum(1, keepdims=True)
    wn = np.where(ws > 0, w / np.where(ws > 0, ws, 1), 1 / 16).astype(np.float32)
    mean = (px * wn[..., None]).sum(1)
    d = px - mean[:, None, :]
    cov = np.einsum("nk,nki,nkj->nij", wn, d, d)
    # start from the covariance row of the largest variance, then iterate
    k = np.argmax(np.diagonal(cov, axis1=1, axis2=2), 1)
    v = cov[np.arange(n), k]
    for _ in range(8):
        nv = np.linalg.norm(v, axis=1, keepdims=True)
        v = np.where(nv > 1e-9, v / np.maximum(nv, 1e-9), np.float32(0.57735))
        v = np.einsum("nij,nj->ni", cov, v)
    nv = np.linalg.norm(v, axis=1, keepdims=True)
    v = np.where(nv > 1e-9, v / np.maximum(nv, 1e-9), np.float32(0.57735)).astype(np.float32)
    t = (d * v[:, None, :]).sum(-1)
    valid = w > 0
    anyv = valid.any(1, keepdims=True)
    valid = valid | ~anyv
    tmax = np.where(valid, t, -np.inf).max(1)
    tmin = np.where(valid, t, np.inf).min(1)
    return mean, v, tmin, tmax, valid


def _encode_colour_chunk(px, w, mode, effort):
    """px (N,16,3) float32 0..255, w (N,16) weights (0 = transparent in mode
    3). Returns q0, q1 (N,3) quantised endpoints, idx (N,16)."""
    n = px.shape[0]
    mean, v, tmin, tmax, valid = _pca(px, w)
    best_q0 = _quantise(mean + v * tmax[:, None])
    best_q1 = _quantise(mean + v * tmin[:, None])
    best_idx, best_err = _eval_colour(px, w, best_q0, best_q1, mode)

    def consider(q0, q1):
        nonlocal best_q0, best_q1, best_idx, best_err
        idx, err = _eval_colour(px, w, q0, q1, mode)
        better = err < best_err
        best_q0 = np.where(better[:, None], q0, best_q0)
        best_q1 = np.where(better[:, None], q1, best_q1)
        best_idx = np.where(better[:, None], idx, best_idx)
        best_err = np.where(better, err, best_err)

    # the bounding box of the pixels, on the principal axis' diagonal
    big = np.where(valid[..., None], px, np.inf).min(1)
    small = np.where(valid[..., None], px, -np.inf).max(1)
    lo, hi = big, small
    pos = v >= 0
    consider(_quantise(np.where(pos, hi, lo)), _quantise(np.where(pos, lo, hi)))
    # inset by 1/16 of the range (the extremes are rarely hit exactly)
    ins = (hi - lo) / 16
    consider(_quantise(np.where(pos, hi - ins, lo + ins)), _quantise(np.where(pos, lo + ins, hi - ins)))
    if effort < 1:
        return best_q0, best_q1, best_idx
    # least-squares refits from the chosen indices
    for _ in range(2):
        e0, e1, ok = _lsq(px, w, best_idx, mode)
        q0 = np.where(ok[:, None], _quantise(e0), best_q0)
        q1 = np.where(ok[:, None], _quantise(e1), best_q1)
        consider(q0, q1)
    if effort < 2:
        return best_q0, best_q1, best_idx
    # +-1 on each quantised component
    for _ in range(2 if effort >= 3 else 1):
        for end in (0, 1):
            for c in range(3):
                for s in (-1, 1):
                    q0, q1 = best_q0.copy(), best_q1.copy()
                    q = q0 if end == 0 else q1
                    q[:, c] = np.clip(q[:, c] + s, 0, _QMAX[c])
                    consider(q0, q1)
    return best_q0, best_q1, best_idx


def _finish_colour(q0, q1, idx, mode, transparent=None):
    """Order the endpoints for the mode (4: c0 > c1, or c0 == c1 with index
    0 only; 3: c0 <= c1, transparent pixels index 3) -> c0, c1, index words."""
    c0, c1 = _pack565(q0), _pack565(q1)
    idx = idx.astype(np.int32).copy()
    if mode == 4:
        swap = c0 < c1
        idx = np.where(swap[:, None], np.array([1, 0, 3, 2])[idx], idx)
        c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
        idx = np.where((c0 == c1)[:, None], 0, idx)
    else:
        swap = c0 > c1
        idx = np.where(swap[:, None], np.array([1, 0, 2, 3])[idx], idx)
        c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
        if transparent is not None:
            idx = np.where(transparent, 3, idx)
    words = (idx.astype(np.uint64) << (2 * np.arange(16, dtype=np.uint64))).sum(1)
    return c0.astype(np.uint16), c1.astype(np.uint16), words.astype(np.uint32)


# ---------------------------------------------------------------- alpha

_A8 = np.array([[1, 0], [0, 1], [6, 1], [5, 2], [4, 3], [3, 4], [2, 5], [1, 6]], np.float32) / np.array([1, 1, 7, 7, 7, 7, 7, 7], np.float32)[:, None]
_A6 = np.array([[1, 0], [0, 1], [4, 1], [3, 2], [2, 3], [1, 4]], np.float32) / np.array([1, 1, 5, 5, 5, 5], np.float32)[:, None]


def _alpha_palette(a0, a1, mode):
    a0 = a0.astype(np.float32)[:, None]
    a1 = a1.astype(np.float32)[:, None]
    if mode == 8:
        return a0 * _A8[:, 0] + a1 * _A8[:, 1]
    p = a0 * _A6[:, 0] + a1 * _A6[:, 1]
    n = p.shape[0]
    return np.concatenate([p, np.zeros((n, 1), np.float32), np.full((n, 1), 255, np.float32)], 1)


def _eval_alpha(a, a0, a1, mode):
    pal = _alpha_palette(a0, a1, mode)
    d = (a[:, :, None] - pal[:, None, :]) ** 2
    idx = d.argmin(-1)
    return idx, np.take_along_axis(d, idx[..., None], -1)[..., 0].sum(1)


def _encode_alpha_chunk(a, effort):
    """a (N,16) float32 -> a0, a1 (N,) uint8, idx (N,16)."""
    amax, amin = a.max(1), a.min(1)
    # 8 levels between min and max (a0 > a1)
    b0 = amax.astype(np.int32)
    b1 = amin.astype(np.int32)
    flat = b0 == b1
    # a flat block: the 6-level mode with a0 = a1 (index 0 exact)
    idx8, err8 = _eval_alpha(a, b0, b1, 8)
    best = dict(a0=b0, a1=b1, idx=idx8, err=np.where(flat, np.inf, err8), mode=np.full(a.shape[0], 8))

    def consider(a0, a1, mode, allowed):
        idx, err = _eval_alpha(a, a0, a1, mode)
        better = allowed & (err < best["err"])
        best["a0"] = np.where(better, a0, best["a0"])
        best["a1"] = np.where(better, a1, best["a1"])
        best["idx"] = np.where(better[:, None], idx, best["idx"])
        best["err"] = np.where(better, err, best["err"])
        best["mode"] = np.where(better, mode, best["mode"])

    # 6 levels between the inner min and max, plus exact 0 and 255
    inner = (a > 0) & (a < 255)
    lo = np.where(inner, a, 255).min(1)
    hi = np.where(inner, a, 0).max(1)
    none = ~inner.any(1)
    lo = np.where(none, 0, lo).astype(np.int32)
    hi = np.where(none, 0, hi).astype(np.int32)
    consider(lo, hi, 6, np.ones(a.shape[0], bool))
    if effort >= 1:
        # least squares on the 8-level mode's indices
        m8 = best["mode"] == 8
        w0 = _A8[:, 0][best["idx"]]
        w1 = 1 - w0
        A, B, C = (w0 * w0).sum(1), (w0 * w1).sum(1), (w1 * w1).sum(1)
        X0, X1 = (w0 * a).sum(1), (w1 * a).sum(1)
        det = A * C - B * B
        ok = m8 & (np.abs(det) > 1e-6)
        sd = np.where(ok, det, 1)
        e0 = np.clip(np.rint((C * X0 - B * X1) / sd), 0, 255).astype(np.int32)
        e1 = np.clip(np.rint((A * X1 - B * X0) / sd), 0, 255).astype(np.int32)
        consider(e0, e1, 8, ok & (e0 > e1))
    if effort >= 2:
        for _ in range(2):
            for d0, d1 in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                m8 = best["mode"] == 8
                a0 = np.clip(best["a0"] + d0, 0, 255)
                a1 = np.clip(best["a1"] + d1, 0, 255)
                consider(a0, a1, 8, m8 & (a0 > a1))
                m6 = best["mode"] == 6
                a0 = np.clip(best["a0"] + d0, 0, 255)
                a1 = np.clip(best["a1"] + d1, 0, 255)
                consider(a0, a1, 6, m6 & (a0 <= a1))
    # the flat blocks that neither mode beat (a0 = a1: 6-level, index 0)
    fl = flat & ~np.isfinite(best["err"])
    best["a0"] = np.where(fl, b0, best["a0"])
    best["a1"] = np.where(fl, b0, best["a1"])
    best["idx"] = np.where(fl[:, None], 0, best["idx"])
    return best["a0"].astype(np.uint8), best["a1"].astype(np.uint8), best["idx"].astype(np.uint64)


# ---------------------------------------------------------------- level encode

def colour_weights(alpha, floor=1 / 16):
    """How much each pixel's colour counts: its alpha, with a floor (what
    lies under the edge of a shape is blended in by bilinear filtering)."""
    return np.maximum(alpha / 255.0, floor).astype(np.float32)


def encode_level(img, fmt, effort=2):
    """img HxWx4 uint8 RGBA -> bytes of one mip level. fmt: "dxt1" (opaque),
    "dxt1a" (alpha 0 / 255 only) or "dxt5"."""
    h, w = img.shape[:2]
    blocks = to_blocks(img)
    n = blocks.shape[0]
    out = np.zeros((n, 16 if fmt == "dxt5" else 8), np.uint8)
    for s in range(0, n, CHUNK):
        b = blocks[s:s + CHUNK]
        px = b[..., :3].astype(np.float32)
        al = b[..., 3].astype(np.float32)
        m = b.shape[0]
        if fmt == "dxt5":
            wt = colour_weights(al)
            q0, q1, idx = _encode_colour_chunk(px, wt, 4, effort)
            c0, c1, words = _finish_colour(q0, q1, idx, 4)
            a0, a1, aidx = _encode_alpha_chunk(al, effort)
            abits = (aidx << (3 * np.arange(16, dtype=np.uint64))).sum(1)
            rec = np.zeros(m, dtype=[("a0", "u1"), ("a1", "u1"), ("ab", "u1", 6), ("c0", "<u2"), ("c1", "<u2"), ("ix", "<u4")])
            rec["a0"], rec["a1"] = a0, a1
            rec["ab"] = ((abits[:, None] >> (8 * np.arange(6, dtype=np.uint64))) & 0xFF).astype(np.uint8)
            rec["c0"], rec["c1"], rec["ix"] = c0, c1, words
            out[s:s + m] = rec.view(np.uint8).reshape(m, 16)
        else:
            if fmt == "dxt1a":
                transparent = al < 128
                opaque_blk = ~transparent.any(1)
                wt = np.where(transparent, 0, 1).astype(np.float32)
                c0 = np.zeros(m, np.uint16)
                c1 = np.zeros(m, np.uint16)
                words = np.full(m, 0xFFFFFFFF, np.uint32)
                if opaque_blk.any():
                    sel = opaque_blk
                    q0, q1, idx = _encode_colour_chunk(px[sel], wt[sel], 4, effort)
                    c0[sel], c1[sel], words[sel] = _finish_colour(q0, q1, idx, 4)
                part = ~opaque_blk & ~transparent.all(1)
                if part.any():
                    sel = part
                    q0, q1, idx = _encode_colour_chunk(px[sel], wt[sel], 3, effort)
                    c0[sel], c1[sel], words[sel] = _finish_colour(q0, q1, idx, 3, transparent[sel])
            else:
                wt = np.ones((m, 16), np.float32)
                q0, q1, idx = _encode_colour_chunk(px, wt, 4, effort)
                c0, c1, words = _finish_colour(q0, q1, idx, 4)
            rec = np.zeros(m, dtype=[("c0", "<u2"), ("c1", "<u2"), ("ix", "<u4")])
            rec["c0"], rec["c1"], rec["ix"] = c0, c1, words
            out[s:s + m] = rec.view(np.uint8).reshape(m, 8)
    return out.tobytes()


# ---------------------------------------------------------------- mips

def mip_count(w, h):
    """Levels in a complete chain: halving until both sides are 1 (a 256 x
    16 file: 9 levels, the last 1 x 1)."""
    return min(16, int(np.log2(max(w, h))) + 1)


def mip_size(w, h, level):
    return max(1, w >> level), max(1, h >> level)


def next_mip(img):
    """2x2 box on premultiplied alpha (so no dark fringe creeps in from the
    transparent pixels); a power-of-two side halves exactly, so a tiling
    texture stays seamless. A side already 1 stays 1 (the other halves)."""
    f = img.astype(np.float32)
    h, w = f.shape[:2]
    rgb, a = f[..., :3] * f[..., 3:4] / 255, f[..., 3:4]
    def half(x):
        hh, ww = max(1, h // 2), max(1, w // 2)
        if h > 1:
            x = (x[0::2] + x[1::2]) / 2
        if w > 1:
            x = (x[:, 0::2] + x[:, 1::2]) / 2
        return x.reshape(hh, ww, x.shape[2])
    rgb, a = half(rgb), half(a)
    out_rgb = np.where(a > 0, rgb * 255 / np.maximum(a, 1e-6), 0)
    return np.clip(np.rint(np.concatenate([out_rgb, a], 2)), 0, 255).astype(np.uint8)


def _box3(x, wrap):
    """Sum over each pixel's 3x3 neighbourhood; the border repeats the edge,
    or wraps on a tiling axis (wrap = (x, y))."""
    p = np.pad(x, ((1, 1), (0, 0)) + ((0, 0),) * (x.ndim - 2), mode="wrap" if wrap[1] else "edge")
    p = np.pad(p, ((0, 0), (1, 1)) + ((0, 0),) * (x.ndim - 2), mode="wrap" if wrap[0] else "edge")
    h, w = x.shape[:2]
    out = np.zeros_like(x)
    for dy in range(3):
        for dx in range(3):
            out += p[dy:dy + h, dx:dx + w]
    return out


def bleed(img, wrap=(False, False), passes=8):
    """The RGB under alpha 0 filled from the nearest visible texels (each
    ring from the ring inside it, the visible ones weighted by their alpha);
    what is still unfilled after `passes` rings -- far inside a transparent
    area, where no filter or block reaches a visible texel -- takes the
    image's mean visible colour. Alpha is untouched. Returns (image, number
    of texels whose RGB changed)."""
    a = img[..., 3]
    hidden = a == 0
    if not hidden.any():
        return img, 0
    out = img.copy()
    if hidden.all():
        changed = int((img[..., :3] != 0).any(-1).sum())
        out[..., :3] = 0
        return out, changed
    rgb = img[..., :3].astype(np.float32)
    wt = np.where(hidden, 0, a.astype(np.float32) / 255)
    col = rgb * wt[..., None]
    filled = ~hidden
    for _ in range(passes):
        s = _box3(col, wrap)
        n = _box3(wt, wrap)
        new = ~filled & (n > 0)
        if not new.any():
            break
        c = s[new] / n[new][:, None]
        rgb[new] = c
        # a filled texel passes its colour on at a modest weight, below a
        # visible one's
        wt[new] = 0.25
        col[new] = c * 0.25
        filled |= new
        if filled.all():
            break
    if not filled.all():
        va = a.astype(np.float32)[~hidden] / 255
        mean = (img[..., :3][~hidden].astype(np.float32) * va[:, None]).sum(0) / max(va.sum(), 1e-6)
        rgb[~filled] = mean
    new_rgb = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    out[hidden, :3] = new_rgb[hidden]
    changed = int((out[..., :3] != img[..., :3]).any(-1).sum())
    return out, changed


def mip_chain(img, fmt, mips, wrap=(False, False)):
    """The levels a file holds before compression: level 0 and, with mips,
    the complete box-filtered chain. DXT5 levels have their hidden colour
    bled (see the module notes). Returns (levels, texels bled in level 0)."""
    n = mip_count(img.shape[1], img.shape[0]) if mips else 1
    levels, bled0 = [], 0
    cur = img
    for i in range(n):
        if i:
            cur = next_mip(cur)
        if fmt == "dxt5":
            cur, changed = bleed(cur, wrap)
            if i == 0:
                bled0 = changed
        levels.append(cur)
    return levels, bled0


# ---------------------------------------------------------------- BLP2 file

FORMATS = {
    "dxt1": (0, AE_DXT1),
    "dxt1a": (1, AE_DXT1),
    "dxt5": (8, AE_DXT5),
}


def encode_blp(img, fmt, mips=False, effort=2, level_images=None, wrap=(False, False)):
    """RGBA uint8 image (power-of-two sides, each >= 4) -> BLP2 bytes.
    level_images: the levels to encode as they are -- mip_chain()'s output,
    or levels drawn by hand (a diagnostic file) -- in place of the chain
    built here. wrap: the image's tiling axes (x, y), for the bleed."""
    h, w = img.shape[:2]
    if level_images is None:
        level_images, _ = mip_chain(img, fmt, mips, wrap)
    want = mip_count(w, h) if mips else 1
    if len(level_images) != want:
        raise ValueError("%d levels given, the chain has %d" % (len(level_images), want))
    levels = []
    for i, lv in enumerate(level_images):
        if lv.shape[:2] != mip_size(w, h, i)[::-1]:
            raise ValueError("level %d is %dx%d" % (i, lv.shape[1], lv.shape[0]))
        levels.append(encode_level(lv, fmt, effort))
    alpha_depth, alpha_enc = FORMATS[fmt]
    offsets, sizes, pos = [], [], HEADER_SIZE
    for lv in levels:
        offsets.append(pos)
        sizes.append(len(lv))
        pos += len(lv)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    head = b"BLP2" + struct.pack("<I", 1) + struct.pack("<4B", ENC_DXT, alpha_depth, alpha_enc, 1 if mips else 0)
    head += struct.pack("<II", w, h) + struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    head += bytes(1024)
    assert len(head) == HEADER_SIZE
    return head + b"".join(levels)


def read_blp_header(data):
    if data[:4] != b"BLP2":
        raise ValueError("not a BLP2 file")
    typ = struct.unpack_from("<I", data, 4)[0]
    enc, ad, ae, has_mips = data[8], data[9], data[10], data[11]
    w, h = struct.unpack_from("<II", data, 12)
    offs = struct.unpack_from("<16I", data, 20)
    sizes = struct.unpack_from("<16I", data, 84)
    return dict(type=typ, encoding=enc, alpha_depth=ad, alpha_encoding=ae, has_mips=has_mips,
                w=w, h=h, offsets=offs, sizes=sizes)


# ---------------------------------------------------------------- decoders

def _decode_blocks(raw, fmt, mode):
    """raw bytes of one level -> (N,16,4) uint8. mode "gpu" or "pillow"."""
    bs = 16 if fmt == "dxt5" else 8
    b = np.frombuffer(raw, np.uint8).reshape(-1, bs)
    n = b.shape[0]
    cb = b[:, 8:] if fmt == "dxt5" else b
    c0 = cb[:, 0].astype(np.int32) | (cb[:, 1].astype(np.int32) << 8)
    c1 = cb[:, 2].astype(np.int32) | (cb[:, 3].astype(np.int32) << 8)
    ix = (cb[:, 4].astype(np.uint32) | (cb[:, 5].astype(np.uint32) << 8) | (cb[:, 6].astype(np.uint32) << 16)
          | (cb[:, 7].astype(np.uint32) << 24))
    idx = ((ix[:, None] >> (2 * np.arange(16, dtype=np.uint32))) & 3).astype(np.int32)

    def ex(c):
        r, g, bl = (c >> 11) & 31, (c >> 5) & 63, c & 31
        if mode == "gpu":
            return np.stack([_E5[r], _E6[g], _E5[bl]], 1)
        return np.stack([r << 3, g << 2, bl << 3], 1)
    e0, e1 = ex(c0), ex(c1)
    four = (c0 > c1) | (fmt == "dxt5")
    if mode == "gpu":
        p2 = np.where(four[:, None], np.floor((2 * e0 + e1) / 3 + 0.5), np.floor((e0 + e1) / 2 + 0.5))
        p3 = np.floor((e0 + 2 * e1) / 3 + 0.5)
    else:
        p2 = np.where(four[:, None], (2 * e0 + e1) // 3, (e0 + e1) // 2)
        p3 = (e0 + 2 * e1) // 3
    p3 = np.where(four[:, None], p3, 0)
    pal = np.stack([e0, e1, p2, p3], 1).astype(np.int32)                 # (N,4,3)
    rgb = np.take_along_axis(pal, idx[..., None].repeat(3, -1), 1)       # (N,16,3)
    if fmt == "dxt5":
        a0 = b[:, 0].astype(np.int32)
        a1 = b[:, 1].astype(np.int32)
        bits = np.zeros(n, np.uint64)
        for k in range(6):
            bits |= b[:, 2 + k].astype(np.uint64) << np.uint64(8 * k)
        aidx = ((bits[:, None] >> (3 * np.arange(16, dtype=np.uint64))) & np.uint64(7)).astype(np.int32)
        eight = a0 > a1
        if mode == "gpu":
            p8 = [np.floor(((7 - k) * a0 + k * a1) / 7 + 0.5) for k in range(1, 7)]
            p6 = [np.floor(((5 - k) * a0 + k * a1) / 5 + 0.5) for k in range(1, 5)]
        else:
            p8 = [((8 - c) * a0 + (c - 1) * a1) // 7 for c in range(2, 8)]
            p6 = [((6 - c) * a0 + (c - 1) * a1) // 5 for c in range(2, 6)]
        pal8 = np.stack([a0, a1] + list(p8), 1)
        pal6 = np.stack([a0, a1] + list(p6) + [np.zeros(n), np.full(n, 255)], 1)
        apal = np.where(eight[:, None], pal8, pal6).astype(np.int32)
        alpha = np.take_along_axis(apal, aidx, 1)
    else:
        alpha = np.where((~four[:, None]) & (idx == 3), 0, 255)
    return np.concatenate([rgb, alpha[..., None]], 2).clip(0, 255).astype(np.uint8)


def decode_level(raw, fmt, w, h, mode="gpu"):
    return from_blocks(_decode_blocks(raw, fmt, mode), h, w)


def fmt_of(header):
    if header["alpha_encoding"] == AE_DXT5:
        return "dxt5"
    return "dxt1a" if header["alpha_depth"] else "dxt1"


def decode_blp(data, mode="gpu", level=0):
    hd = read_blp_header(data)
    fmt = fmt_of(hd)
    w, h = max(1, hd["w"] >> level), max(1, hd["h"] >> level)
    raw = data[hd["offsets"][level]:hd["offsets"][level] + hd["sizes"][level]]
    return decode_level(raw, fmt, w, h, mode)
