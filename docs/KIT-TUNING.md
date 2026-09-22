# Kit tuning: adjusting the painted kit by hand

`Core/KitTuning.lua` is a thin override layer over `Media/KitLayout.lua` (what
`Tools/build_kit.py` measured) and `Kit.Replacements` (which piece dresses
which game element, see `docs/KIT-MAPPING.md`). **The addon never writes
tuning**; it only obeys it, so an empty tuning table leaves the kit exactly as
built and the addon ships and behaves as before.

Two editing tools write it, and **neither ships with the addon** — they live
outside this repository, in `MelloUI Test/`:

| tool | where | what it edits |
|---|---|---|
| `MelloUIKitEditor` | a separate addon, `/mkit` | placement, size, colour and which piece is used, on the real frames |
| `tools/kitforge` | a local web tool | the sprite pixels, the piece geometry, and `Media/KitTuning.lua` itself |

Their guide is `MelloUI Test/tools/kitforge/README.md`.

---

## Where the values come from

```
Media/KitTuning.lua   MelloUI_KitTuning   baked into the repository, the floor
MelloUIDB.kitTuning                       this account's live edits, on top
```

Both are optional. Clearing a value that the baked file sets writes the marker
`"\0nil"` rather than removing the key, because saved variables cannot carry a
`nil` — the merge turns that marker back into "no value", so *clear* really
clears.

`MelloUI.KitTuning:Rebuild()` layers the two and bumps `KT.serial`; anything
that caches a lookup (`Kit:RuleFor`) re-reads when the serial moves.

---

## The four sections

### `globals`

`scale` (file px per UI unit, normally 0.375), `frameScale` (the one weight a
window's inner rails are drawn at, normally 1.6) and `framePrefix` (the rail
family, normally `window/single`). `Kit:ApplyTuning` remembers the built-in
value the first time, so clearing one puts it back without a reload.

### `pieces`

Keyed by piece name (`window/frame_t`). Any field of a `MelloUI_KitLayout`
entry — `w`, `h`, `uv`, `box`, `open`, `tile`, `overhang`, `radius`, `file` —
merged over what `build_kit.py` measured. The original values are kept, so
dropping the override restores them. A name the layout does not have is
*created*, which is how a piece added by hand can be used before a rebuild.

Arrays (`uv`, `box`, `open`) are replaced whole, never merged element by
element: half a rectangle from each side is never what anyone wants.

### `rules`

Keyed by the element key `Kit:ArtKey` produces — the atlas name, a texture
file's base name, or one of our own names (`TitleBar`, `ViewportFrame`). The
lookup ignores case, as `Kit:RuleFor` already did, because the client returns
the canonical case of an atlas.

Each entry has two halves:

```lua
["UI-HUD-ActionBar-IconFrame"] = {
    rule = { ... },   -- merged onto Kit.Replacements[key]
    tune = { ... },   -- applied to what was built
}
```

**`rule`** takes any field the library understands: `kind`, `piece`, `base`,
`state`, `slot`, `prefix`, `scale`, `heightScale`, `widthScale`, `widthFrac`,
`capOverhang`, `outset`, `openingScale`, `natural`, `square`, `under`,
`level`, `layer`, `sublevel`, `corners`, `lit`, `hover` … A rule override may
also *invent* a rule for an element the library never mapped, as long as it
says what `kind` to draw. The library's own table is never edited: the merge
is made on a copy.

**`tune`** is the by-hand layer, applied after the piece is built:

| field | |
|---|---|
| `x`, `y` | move the replacement, in UI units |
| `padL`, `padR`, `padT`, `padB` | grow (+) or shrink (−) its rectangle |
| `alpha` | on the whole replacement |
| `tint` `{r, g, b}` | on every painted texture in it |
| `desat` | greyscale |
| `blend` | `BLEND`, `ADD`, `MOD`, `ALPHAKEY`, `DISABLE` |
| `coord` `{l, r, t, b}` | crop, as fractions of the piece |
| `flipH`, `flipV` | mirror |
| `layer`, `sublevel` | draw layer of its textures |
| `texAlpha` | on the textures rather than the frame |
| `level` | frame level, relative to the parent |
| `texture` | any texture path instead of the kit piece |
| `hidden` | do not replace at all: the game's own art stays |

`x`, `y` and the paddings work through a **proxy rectangle** made in
`Kit:Replace` between the game's element and our piece. Everything downstream
already anchors to `rect`, so one insertion point moves and resizes every kind
without the game's own layout being touched. The proxy is made whenever the
element carries tuning, and always while `Kit.liveEdit` is on (the editor
addon sets it) so a drag has something to move.

`Kit:TuneTexture` only touches what the tune actually names, and puts a field
back when it stops naming it — so a placement-only tune does not flatten a
tint a module set itself (the green equipped border, a lit tab).

### `elements`

Keyed by a frame's global name — a game window, or one of MelloUI's own
(`MelloUIConfigFrame`, `MelloUIQuestListPanel`, `MelloUIStatsFrame`,
`MelloUIServicesBar`, …). `pos`, `size`, `scale`, `alpha`, `hidden`, and
`regions` keyed by a texture's name, its key in the frame table, or its atlas.
The frame's state is remembered before the first change, so clearing an
element puts it back without a reload.

A module can expose a frame the editor would otherwise not find:

```lua
MelloUI.KitTuning:Register("MelloUIWhatever", frame, "Whatever", "MelloUI")
```

---

## What applies at once and what needs a reload

| change | |
|---|---|
| `tune` placement, colour, crop, alpha, layer | straight away |
| `globals`, `pieces` | straight away (`Kit:ApplyTuning`) |
| `elements` | straight away |
| `rule` kind, piece, base, scale, outset … | needs the panels rebuilt: `/reload` |

`Kit.repList` holds every replacement built this session, which is what
`Kit:RefreshTuning` walks and what the editor lists as "on screen".

---

## Checking it

The override layer runs outside the client under `lupa`:

```bash
python "MelloUI Test/tools/kitforge/test_tuning.py"   # Core/KitTuning.lua
python "MelloUI Test/tools/kitforge/test_kit.py"      # Kit.lua's tuning hooks
```
