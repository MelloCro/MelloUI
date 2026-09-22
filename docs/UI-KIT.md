# MelloUI painted UI kit: what to deliver per element

The goal: every remaining window and HUD element is ASSEMBLED from reusable parts instead of cut from a
per-window picture. Each part is its own file. Nothing in a part is text, a number, an item or spell icon,
or a portrait: the game draws all of that.

## Global rules (apply to every file)

- PNG, RGBA, transparent background. Straight, hard outer edges where pieces join (no soft shadow bleeding
  past the piece), soft edges only on free-standing ornaments (gems, orbs).
- Deliver at 2x: the sizes below are the intended on-screen size at 1x ("1x" = one physical pixel per art
  pixel times 0.75, the rule the bars use); the file is twice that. Example: a 32 px tall button is a 64 px
  tall file.
- Same light direction and palette in every piece (the current art is lit from the top-left, bronze/iron
  on dark stone, red gems, gold text).
- Pieces that repeat (edges, bar middles, background tiles) must be seamless along the repeat axis: the left
  column of pixels continues into the right column.
- Pieces that cap a stretch (left cap / middle / right cap) share the same height and meet on a straight
  vertical cut: the cap's inner edge and the middle's edge are the same pixels.
- Corners are square and exactly as thick as the edges they join.
- Interiors that show game content (icon holes, portrait discs, card interiors, body tiles under text) are
  fully transparent (alpha 0), not painted dark.
- File names: `kit/<group>/<element>_<piece>_<state>.png`, states `normal`, `hover`, `pressed`, `checked`,
  `disabled`, `open` (tabs) as listed per element. Pieces: `tl tr bl br` corners, `t b l r` edges, `cap_l
  mid cap_r`, `body`.

## 1. Window frame (one nine-slice for every panel: character, bags, map, social, tooltip, chat...)

| piece | size at 1x | notes |
|---|---|---|
| corners tl tr bl br | 48 x 48 | tl may carry the ornament; tr/bl/br plain or with the corner gem |
| edges t b l r | 256 long x 24 thick | seamless along their length |
| body tile | 256 x 256 | the dark stone under content, seamless both axes, no vignette |
| title plate cap_l / mid / cap_r | 40 x 36 / 64 x 36 / 40 x 36 | mid seamless; runes on the caps only if they do not read as text |
| portrait ring | 96 x 96 | round rim, interior transparent (the game's portrait shows through) |
| close button normal / hover / pressed | 28 x 28 | the red X plate; the X glyph is art here |
| inset (inner list/box) corners + edges + body | 24 x 24 corners, 128 x 12 edges, 128 x 128 body | thinner second frame for list areas and boxes inside a window |
| divider rule cap_l / mid / cap_r | 16 x 8 / 64 x 8 / 16 x 8 | horizontal separators |

## 2. Buttons

| element | pieces | states | size at 1x |
|---|---|---|---|
| text button (wide plate) | cap_l / mid / cap_r | normal, hover, pressed, disabled | 24 x 32 / 64 x 32 / 24 x 32 |
| red text button (primary action) | cap_l / mid / cap_r | normal, hover, pressed, disabled | same |
| square icon slot (action bars, bag slots, spells) | one square | normal, hover, pressed, checked | 64 x 64, hole 52 x 52 transparent, rim 6 |
| round icon slot (service icons, medallions) | one square | normal, hover, pressed | 64 x 64, disc interior transparent |
| orb (edge bars, big toggles) | one square | normal, hover, pressed | 48 x 48 |
| small square (cog, filter, minimize) | one square | normal, hover, pressed | 24 x 24, glyph is art |
| arrow buttons up / down / left / right | one square each | normal, hover, pressed | 20 x 20 |
| checkbox | one square | off, on, hover | 20 x 20 |
| plus / minus (expand, collapse) | one square each | normal, hover | 18 x 18 |

## 3. Tabs

| element | pieces | states | size at 1x |
|---|---|---|---|
| top tab (chat, character tabs) | cap_l / mid / cap_r | plain, open | 16 x 32 / 32 x 32 / 16 x 32 |
| side tab (spell book, professions, legacy) | one square | plain, open | 44 x 46 |
| bottom tab (social, map bottom tabs) | cap_l / mid / cap_r | plain, open | 16 x 36 / 32 x 36 / 16 x 36 |

## 4. Lists and scrolling

| element | pieces | states | size at 1x |
|---|---|---|---|
| list row plate | cap_l / mid / cap_r | plain, hover, selected | 12 x 28 / 64 x 28 / 12 x 28 |
| list header plate | cap_l / mid / cap_r | plain | 12 x 30 / 64 x 30 / 12 x 30 |
| category / expandable header | cap_l / mid / cap_r | closed, open | 12 x 30 / 64 x 30 / 12 x 30 (chevron on cap_l) |
| scroll track | top / mid / bottom | plain | 16 x 24 / 16 x 64 / 16 x 24 |
| scroll thumb | top / mid / bottom | normal, hover | 16 x 12 / 16 x 32 / 16 x 12 |
| item card (transmog, quest rewards) | one square | plain, selected | 96 x 112, interior transparent, gem corners |

## 5. Inputs

| element | pieces | states | size at 1x |
|---|---|---|---|
| edit / search box | cap_l / mid / cap_r | normal, focused | 28 x 28 / 64 x 28 / 28 x 28 (magnifier on cap_l for the search variant, plain cap_l for the edit variant) |
| dropdown | cap_l / mid / cap_r | normal, hover | 12 x 28 / 64 x 28 / 28 x 28 (arrow on cap_r) |
| slider track cap_l / mid / cap_r + thumb | as named | normal, hover (thumb) | 8 x 12 / 64 x 12 / 8 x 12, thumb 16 x 20 |
| chat input row | cap_l / mid / cap_r | normal | 36 x 28 / 64 x 28 / 20 x 28 (bubble glyph on cap_l) |

## 6. Status bars

| element | pieces | size at 1x |
|---|---|---|
| bar frame (health, power, cast, xp, reputation, progress) | cap_l / mid / cap_r | 24 x 20 / 64 x 20 / 24 x 20, interior transparent |
| bar trough tile | 64 x 20 | the dark under-fill, seamless |
| segment divider tick | 4 x 20 | for segmented bars |
| big gem cluster caps (cast bar, unit frame bars) | cap_l / cap_r | 48 x 40 each, optional richer variant of the plain caps |

## 7. Decoration

| element | size at 1x | notes |
|---|---|---|
| gem diamond small / large | 12 x 12 / 20 x 20 | placed at grid crossings and corners |
| gem joint (between stacked boxes) | 24 x 8 | |
| corner ornament (the scroll/flourish) | 48 x 48 | |
| rail (the edge bar) cap_l / mid / cap_r | 96 x 48 / 256 x 48 / 96 x 48 | the orbs belong to the caps |
| medallion ring for class icons | 128 x 128 | already delivered |

## 8. Backgrounds

| element | size | notes |
|---|---|---|
| dark stone tile | 512 x 512 | seamless, low contrast, no bright veins (they show as loops) |
| parchment tile | 512 x 512 | seamless |
| iron plate tile | 256 x 256 | for header bands |

## 8a. File density (audit, 2026-09-21)

The pieces are painted at 2x, but the windows show most of them at about a third of that (a 71 px row plate
on a 24 px row, a 135 px slot rim on a 48 px slot, a 50 px window edge at 19 px), while Blizzard's atlases
are drawn 1:1 in UI pixels. `Tools/build_kit.py` therefore writes each file at a DENSITY per piece
(the `DENSITY` table: pattern -> pixels in the file per painted pixel), chosen so a piece holds about
1.3-1.5 x the pixels it shows on screen - a UI px is up to 1.33 screen px at common UI scales, so a little
over 1:1 keeps the art crisp, and the pieces that were UNDER-sampled at a flat 0.5 (the 11 px single
rails, the stone body at the frame scale, the check box) went back up. `Media/KitLayout.lua` keeps the
painted 2x numbers, so nothing in the Lua changes; only the uv is measured on the file.
Result: 33 MB of uncompressed texture (58 before), of which the kit's plates, rails, rims and tiles are
6 MB and the pictures (page, cards, panels, at ~1:1) 26 MB. `python Tools/build_kit.py --report` lists
every piece's painted size and density. Blizzard's files are DXT-compressed BLP on top of that (4-8 x
smaller again); a BLP writer would be the next step if memory ever matters.

## 8b. Picture backdrops (delivered 2026-09-21)

Full-bleed still-life panels for windows that show a profession or a theme behind their content, one
panel per subject, delivered as a row of three per sheet separated by a dark seam (`Tools/cut_panels.py`
cuts on the seams). Each panel is 512 x 1024 in the client, colour AND greyscale (`_grey`, for a tint
with SetVertexColor). In the kit: `backdrops/profession_cooking`, `_fishing`, `_firstaid` (+ `_grey`).
More subjects arrive the same way: a sheet id plus three names in `cut_panels.py`.
The primary professions came as WIDE banners (a 2 x 4 grid on black plus a single mining sheet; the
still-life at the right on stone, monochrome): `cards/<profession>` for the 664 x 142 primary cards, and as a
3 x 3 grid of TALL colour panels: `backdrops/profession_<profession>` (`Tools/cut_cards.py`).
Round profession ICONS (a 4 x 3 + 4 grid on transparency and one big crossed pick-and-hammer) are cut by
`Tools/cut_icons.py` into `icons/profession_<name>` and `icons/professions`, 192 px, clipped to their circle.
The secondary professions' schematic panels came as three 362 x 1448 strips (`backdrops/schematic_<name>`, the
band at the schematic's aspect with the still-life, chosen by colour).

## 9. Per-window layout map (with the kit, this is the only per-window file)

A copy of your mockup for that window with coloured rectangles and a legend, for example:
"red = list area, blue = search box, green = close, yellow = tabs (left to right), purple = model area".
Plus a line for anything that should stay Blizzard's. Windows with variable size (chat, bags) need the
body marked as the resizable part.

## 10. Style sheet (one page, once)

Text colours (title gold, body text, disabled), the scale rule (native pixels x 0.75), spacing between
stacked elements, which windows get a portrait ring, what never gets a plate (e.g. chat text lines).

## What already exists and does not need re-delivery

Action bar slot/gems/rails, unit frame ring and bars, cast bar, minimap stand and services grid, tracker
panel, class and faction medallions, edge bars with orbs, and the per-window art of the finished panels.
When the kit lands, the finished panels stay as they are; new windows use the kit.
