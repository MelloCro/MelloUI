# Rules for dressing a Blizzard window in the kit

What the Character Panel taught us (2026-09-20/21). These are the rules for every
window MelloUI remakes from here on: the reputation, skills, PvP, currency and
statistics tabs are done; the spellbook, quest log, bags, the options panels and
the rest follow the same rules. `docs/KIT-MAPPING.md` is the mapping table itself,
`Modules/Kit.lua` the library, `Modules/CharacterPanel.lua` the worked example.
MelloUI's own windows (the configurator, the Quest List, the Quest Tracker, the
whisper popups ...) follow the same rules plus section 6: one shared system per
job, for the game's windows and ours alike.

## 0. Before anything: the default window

**Rule (user, 2026-09-21): a window is restored to its default state and
functionality before anything is changed.** If MelloUI already dresses it
another way (a painted page with the game's frames laid over it, moved
controls, hidden art), that goes first: the module is reduced to one that
touches nothing, the client shows the stock window, and the default
screenshots are taken from THAT. Only then are pieces mapped, one element at a
time, on the game's own layout. The old version stays in git history; its art
files are removed (they are rebuilt by their tools if ever wanted).

## 1. The five laws

1. **Replace, never add.** Every kit piece stands in for one game region (a
   texture, a nine-slice, a button's art). Its rectangle, parent, level and
   visibility are the replaced element's. Nothing is drawn onto a window that
   the game does not draw itself. Agreed additions are rare, explicit, listed in
   KIT-MAPPING under "Agreed additions", and passed with `noFade` (so far: the
   viewport frame, the title plate where the client paints none, the covers on
   rail junctions; on MelloUI's own windows the configurator's crest and its
   short title plate).
2. **Research before touching.** Read the window's XML and Lua in
   `%TEMP%\wowui-src` first: which atlas each region uses, its anchors and size,
   who shows / hides / re-atlases it and when. Never guess a rect, a level or a
   behaviour from a screenshot. If the sources are missing, `/cpdump regions`
   (art name, rect, layer, alpha of every visible texture) is the second source.
3. **Match the original's size.** A piece is fitted by its opaque `box`, not
   its canvas, to the element's rect (`FitBox`); stacked elements (rows, slots)
   are fitted to their PITCH so neighbours butt or share gems exactly as the
   game's art does. Only icons and small buttons keep the kit's natural size.
   No pixel offsets by eye: every offset is derived from the piece's `box` /
   `open` (`Kit:RailInset`, `GetOpening`).
4. **Same point in the stack.** Before placing a piece, note the replaced art's
   frame strata, frame level and draw layer, and what the game draws over it
   (text, icons, quality borders, highlights). The piece goes to that point:
   a holder frame at parent level ± n, `under` for art beneath a button's icon,
   and REGIONS of the element's own frame when the piece must sit between two
   of that frame's layers (a bar's fill and its text). Same-level frames draw in
   creation order: never rely on it.
5. **Follow the game's behaviour.** Pieces are children of the element they
   replace, so they move, collapse, show and hide with it. Art the game toggles
   itself is a "follower" (`rep:SetShown(region:IsShown())` on the game's own
   refresh). State is read from the game's flags after its own update
   (`OnButtonStateChanged` -> `over` / `down`; `RefreshBackgroundHighlightOpacity`;
   `SetEmpty` / `ClearEmpty`), by post-hooks on the INSTANCE, never by replacing
   a method. Nothing is moved, resized or re-anchored unless it is part of the
   replaced element's own geometry (a bar's fill inside the bracket that replaced
   its background) — and then it is restored on disable.

## 2. The looks (the user's picks — fixed, not per window)

| element | rule |
|---|---|
| a window's OUTER border (`NineSlicePanelTemplate`) | the painted double rail `window/frame_*` at 1.0 with the gem corners `frame_gem_*` over it, grown OUTWARD (`outset` 42) so it never covers content; `skip = "tl"` where a portrait ring is that corner |
| every border INSIDE a window (insets, viewport, dividers, backdrops with an edge) | SINGLE rail `window/single_*` at ONE weight, `Kit.frameScale` 1.6 (pick B1); no mapping carries its own weight |
| junctions of rails (T and +) | the slider-thumb gem (pick K) via `Kit:Joint`, centred where the rails' centre lines cross |
| title bar | `tabs/top` in the `title` look (rune caps, F's red) at 1.5 x the bar's height, the outer rail's WHOLE width (the window plus the outset each side), standing ON the outer rail: its caps' gems on the band's middle line (`Kit:TitleOnRail` from `Kit:RailMiddle`, above the window's top edge), the title text centred on it (user, 2026-09-21: the header sits on top of the thick border of every window) |
| close button | `window/close` states on the button's normal texture rect |
| portrait icon in the ring (user, 2026-09-21) | the game's portrait is fitted to the CLASS MEDALLION's size in the character window's ring (0.759 x the ring, `Kit:FitPortrait`, aspect kept). If the icon then does not cover the opening (a shield, a non-round asset), it gets the round inner-panel background behind it (`Kit:RingDisc`: the palette's `innerPanel`, painted by its key with `Kit:Paint`, so a new palette paints it again; never a fixed colour) at that same medallion size — never a loose icon over the page. Two outcomes only: scaled to the medallion, or scaled to the medallion on the disc |
| portrait corner | `window/portrait_ring` square on the ring's rect, the class medallion inside it (plain variant, 0.759 x ring) |
| backdrops (pane pictures, model landscape) | `tiles/stone` tiled at native scale, no edge of their own |
| dividers / lines | `window/single_l` edge for the pane divider; `window/divider` strip for scroll lines; natural size + `widthFrac` for a line inside a glow atlas |
| headers / plates | `lists/header` for titles and level plates; `lists/plate` plain (gemless, pitch-fitted) for rows and row highlights; `lists/catplate` closed for category headers (no chevron; the game's glyph stays) |
| TALL list rows (50 px and more: the LFG who / browse lists) | R3 (user, 2026-09-21): a single-rail card with stone under the row (`frame` with `hover` / `checkedTint`), its iron lit gold while selected — the plate's rails get fat when stretched that tall |
| equipment / icon slots | `buttons/slot` rim UNDER the button, sized by `gemSpan` to the slot pitch so neighbours share a gem |
| side tabs | `buttons/slot` gold rim at rest (pick I) + the same rim additively as the hover glow; selected: the active look |
| anything active, checked or selected (user, 2026-09-28, option C: "do it across the board") | THE active look, `Kit:SetActive` (Kit.lua): a gold ring added as light (`selectedTrim`) with a halo outside and a glow inside (none round text: a tab, a row or a card wears the ring, its lines and the halo), its two dark edge lines (`innerPanel`), the icon lifted 1.2 x with no tint; fed by the kit's followers of the state (a rim's checked flag, a frame's `checked()`, a plate in its `selected` state, a rule's `active = true`, kind `active` for a button the kit leaves in the game's art), never polled; a secret flag in combat shown with `SetAlphaFromBoolean`. A window's own copy of a selected look is a bug: KIT-MAPPING "The active look" lists what it stands in for |
| bottom / top tabs (`PanelTabButtonTemplate`, `TabSystemTemplate`), every window | **TB6** (user, 2026-09-21, `kit_raw/bottomtab_catalog.png`; was T1, the `tabs/top` plate): the single rail with the stone card on the tab's rect, its iron lit gold while open, brighter on hover; the tab's text held centred on the card (the game bobs it on select) — `Kit:SkinPanelTab` |
| check boxes, everywhere | `buttons/checkbox` off / on / hover — CONSISTENCY (user, 2026-09-21): every check box, expand / collapse glyph and pane toggle in a window is the kit's, none stay the game's |
| expand / collapse glyphs (+ / -), sub-header toggles | `buttons/plus` / `buttons/minus` plates on the glyph's rect, switched with the atlas the game puts there (`Kit:StateIconReps`) |
| pane toggles (page arrows) | `buttons/arrow_left` / `_right` at the button's height |
| scroll bars (`MinimalScrollBar`) | THE scroll bar, T2 / H1 / S1: `bars/trough_v` track, `lists/scrollthumb` gem-slab thumb stretching with the content, `buttons/arrow_up` / `_down` steppers at natural size |
| progress bars (`ColoredProgressBar`) | P1: `bars/frame` bracket with the trough in its opening, the game's tinted fill BEHIND it on the bracket's whole height (its mask sized the same) |
| picture cards (a card whose background is a painting) | `picture` kind: the painted panel cropped to the card's aspect (crop 1 = bottom), its `_grey` twin while the game marks it missing / inactive, the single rail 1.6 over it (pick F) |
| cards without a painting | single rail 1.6 + stone body (pick A) |
| search / edit boxes | `inputs/edit` plate (S1), focused while typing; too narrow for its caps = middle only |
| dropdowns | `inputs/dropdown` plate (D1), hover from the button; a long list's menu (user, 2026-09-26: the Fonts list ran off the screen) in the game's own scroll mode, at most 18 entries and half the screen, the choice scrolled into view, its scroll bar THE scroll bar while the box's window wears the kit -- one builder for every MelloUI dropdown, `W.DropdownMenu` (Core/Widgets.lua) |
| text buttons (Create, OK, …) | `buttons/redbtn` (B1) with the game's four states, slightly under the button's height |
| numeric spinners | the edit plate's middle + `buttons/arrow_left` / `_right` (N1) |
| item / reagent slots, icon borders | `buttons/slot` rim over a square icon (R1), `buttons/roundslot` over a round one (O2); a quality-coloured border tints the rim the same |
| small square buttons | `buttons/cog` plate under the game's icon (K2) |
| list boxes | single rail 1.6 + stone body (L1) |
| page backdrops | the user's page painting `backdrops/page_stone` (not the kit's soft stone, not a flat colour); the PARCHMENT page `backdrops/page_parchment` for the spell book's pages and for the quest lists (the game's quest log and MelloUI's Quests panel; user, 2026-09-21) |
| a window's tall picture area (the schematic) | the profession's tall colour panel (T1) under the inset rail |
| left as the game's | the PvP rank dial, the game's additive hover on plates that have no hover state, decorative icons that are pictures (skill-up arrows, favourite star, chain link) |
| the minimap cluster (user, 2026-09-21) | R1 × 0.75: the portrait ring sized from the map's opening, its rim over the map's edge, above the map with the band and buttons raised above it; Z2 the title plate on the zone band; round rim on the tracking plate; plus / minus zoom |
| the objective tracker (user, 2026-09-21) | T2 the title plate on the tracker's header, `lists/header` on the modules', texts centred, toggles left of the caps' gems (minus / plus), the cog under the filter; L1 backdrop at Edit Mode's opacity, retracting when collapsed; quest items R1; progress bars P1 |
| title and header TEXT (user, 2026-09-21) | the "Enchanted Land" face (`Media/Fonts/EnchantedLand.ttf`, `Kit:TitleFont`) at the string's own size, on titles and headers ONLY: window title plates, the tracker's and the damage meter's headers, the minimap's zone band; body text, names, numbers and chat stay the game's (a display face: cramped under 14 px) |
| the social window (user, 2026-09-21) | the flat window shell as any window, the portrait icons at the medallion size on the disc (2b; the 1.3 x of 2026-09-21 outgrew the ring — user, 2026-09-24); TB6 tabs (picked here, applied to every tabbed window); `lists/header` on the Battle.net band; rows' hover on the plate's hover look shown by hand; category plate on invite headers; K2 invite cog; **G3** raid group boxes: the single rail at the raid frames' 0.8 weight with stone, rows bare text; GC1 raid info column headers |
| the chat windows (user, 2026-09-21) | CH1 the single rail (no body) in the border pieces' own BORDER layer around the body, which is the list-box stone at the slider's alpha (user: not a flat colour); CT2 = TB6 cards on the tabs; S1 edit plate with the LEFT cap dropped (plain end: no magnifier on a chat box); K2 cogs under the menu / channel / voice / minimize glyphs; arrow on scroll-to-bottom; NO CHAT FADE: tabs, button frame, edit box held at full alpha, the background held at the slider's value |
| the damage meter (user, 2026-09-21) | L1 body one level under the window at the meter's transparency; `lists/header` on the header with its controls condensed (0.8, centred on the band, off the gems); **D1 = P1** brackets on every entry bar with the caps outside the bar (a StatusBar's fill cannot be re-anchored: the bar is set in by the arms), texts at 0.8 inside, the icon square at the row's height, class medallions on class icons; minus / plus, K2 settings cog, D1 dropdowns, scroll bars by the sweep |
| MelloUI's configurator (user, 2026-09-21/22; the approved redesign of 2026-09-24, built 2026-09-26) | on the own-window shell (section 6): outer double rail and page stone; the emblem as a CREST centred on the top rail (`MelloUI-Crest`, the portrait ring at 1.25 x, the emblem on its disc, 2b) with the SHORT title plate under it (`MelloUI-TitlePlate`, 200 wide: the recorded 2c exception); the top bar on the inner panel (`Kit:StoneDim` 0.8, 2e): Install… / Edit Layout / close right, B1 plates (0.15.0: Edit Layout replaces the Layout group of Unlock the Windows, Auto Snapping and Reset positions); the side list in an L1 box: R1 rims on 22 px icons, the palette marker (raised panel, gold edge and name), `common-button-list-plus` / `-minus` fold glyphs on the group headers; the pages on the dark inner panel: CA1 TB6 tabs, L1 section boxes, CR4 rows (alternating faint bands, the plate faded in on hover), SH3 sub-headings on the header plate, kit check boxes, SL1 slider, B1 / D1; Install… a red plate with a gold label and a thin gold outline (palette, no new art); the classic scroll bar kept |
| MelloUI's installer (approved sketch 2026-09-24, built 2026-09-26) | on the own-window shell: the standard corner ring with the emblem on its disc (2b) and the full-width plate on the rail carrying the step's title (2c); the numbered steps rail in an L1 box; the step pages on one `Kit:StoneDim` body (2e); the setup cards in the palette look (raised panel, gold edge and title when chosen); the Keep page's ring (`MelloUI-Crest`, 110 px, the emblem at 35 % on its disc); SH3 headings; B1 buttons, Install gold-trimmed as the configurator's |
| the bag windows (user, 2026-09-21) | the flat window shell as any window; R1 rims to the grid's pitch with icons filling them and stone in empty slots; the game's quality border kept INSIDE the rim (the rim untinted — the bags differ from the windows' item slots here); the money strip on `lists/header` (B2), raised above the rims; search S1, sort K2 |
| HUD action bars, micro menu, bag bar, status bars (user, 2026-09-21) | R1 rims to the pitch with the icon filling the opening (empty: stone), the bars' frame art faded (under the rims), gryphons → `deco/rail_cap` orbs behind every bar (X2), page arrows hidden, micro buttons on the cog plate with the game's glyphs (M1), XP / rep bars P1 with the caps outside and `bars/tick` on the segments |
| HUD compact raid frames (user, 2026-09-21) | F1 G1: the single rail at 0.8 with stone as regions of the frame (rails above the fills, under the icons); the group border on the single rail 1.6; the totem borders → round rims; selection edge and aggro glow the game's |
| HUD cast bars (user, 2026-09-21) | C1 T1: `bars/castbar` with the game's bar as its opening and the caps outside, the bar narrowed by the arms so it reads the game's width; `lists/header` on the 12 px under the standalone bar; all FX faded and their animations stopped |
| HUD unit frames (player / target / focus / ToT / pet; user, 2026-09-21) | B3 R1 L1 N3: the frame's one picture faded; `window/portrait_ring` with its opening on the portrait (the portrait at the medallion size, 2b); the P1 bracket on each bar, ring side capless, far cap grown outward, the fill on the whole rect; the bars END on the ring's round body 2 px under it (never deeper: the fill must be readable to its end) and the ring's own pixels are drawn once more over their ends (`RingCover`); `buttons/orb` under the level / PvP circle, the level's with the nameplates' dark disc (`Kit:OrbDisc`); the name centred on the name band's rect with the nameplates' soft name shade behind it (the `tabs/top` title plate retired 2026-10-03: longer names did not fit it). Party frames the same (Round 3, done): the ring at BACKGROUND under the name (the party picture is drawn above its portrait), the name centred over the health bar |

A new element type = a new catalogue for the user to pick from
(`UITest/tools/*_catalog.py` -> `kit_raw/*_catalog.png`, lettered options at the
game's size), then the pick recorded here and in KIT-MAPPING. Never choose a
look for a new element type silently.

## 2c. MANDATORY: the title plate stands on the outer border (user, 2026-09-21)

Every window's title plate (the `TitleBar` rule, `onRail`) is placed the same
way, by the rule itself — never per window:

1. It rides the outer rail (`Kit:TitleOnRail()`: its centre lifted above the
   window's top edge so its caps' gems sit on the rail's middle line,
   `Kit:RailMiddle()`) — the header stands on the thick border, not inside
   the window.
2. It spans the outer rail's WHOLE width: the window's width plus the rail's
   outward growth (`Kit:OuterRailOutset()`) on each side, anchored to the
   window's top corners, its rune caps ending at the border's outer edges.
3. The window's title text is centred on the plate and put back on disable.

Check on every window: the plate rides the border (its caps' gems on the
rail's middle line), the caps reach the border's ends, the title sits on the
plate.

**One recorded exception (the approved configurator sketch, 2026-09-24):**
the configurator's title stands on a short plate under the centred crest
(`Kit:OwnWindow`'s `plate = "crest"`, rule `MelloUI-TitlePlate`, 200 wide,
its top 8 over the crest's bottom), not on a full-width plate on the rail.
The rest of 2c holds there too: the title is ON the plate in
`Kit:TitleFont`, and the crest's ring is never empty (the emblem on its
disc). The installer and every other window keep the full-width plate on
the rail.

**And (user, 2026-09-24, the Macros window: "the text header is not on the
header, probably not even following the Font Style application, that also
needs to be a rule"):** the title TEXT itself must be found and moved onto
the plate — whatever the window calls it (`TitleContainer.TitleText`,
`TitleText`, `<Name>TitleText`, a `Title` string on the frame or its
NineSlice) — and it must be in the kit's title face, `Kit:TitleFont(fs,
true)`, which follows the Fonts options and the Font Style (the Titles &
headers role); put back (`Kit:TitleFont(fs, false)`, its points) on
disable. A title left at the game's position or in the game's font is a bug.
Check on every window: is the title ON the plate, and does it change when
the Font Style changes?

The same goes for the window's PORTRAIT: when the window has a round
portrait ring, the game's portrait icon must be shown in it (2b below) — an
empty ring is a bug.

## 2e. MANDATORY: no eye strain — text-dense areas on a dark panel (user, 2026-09-24)

"too much small text over a plain brown border is just an eye strain" / "make
that eye strain issue a rule to check". Check it on every window:

- Any area that is mostly TEXT — a list (addons, friends, quests, recipes),
  a section of options / check boxes / sliders, a settings page, a column of
  dropdowns — never lies on the plain brown stone. It gets the palette's
  **inner panel** (`MelloUI.Palette.innerPanel`, #11100D) laid over the stone
  inside its rail, about **0.8** alpha, as a region of the kit's own frame
  (so it comes and goes with the skin).
- Rows on it are striped in the neutral **main window** tone (#1F1B16, about
  0.85 alpha), never the reddish raised panel.
- Labels at the interface's full size (GameFontHighlight), in the palette's
  text colour (#C6AF85); headings in its gold (#AE8546). No small font for
  rows of settings.
- The mechanism: the kit's framed box has a `dim` option (rule field or
  Kit:Replace opts) that lays the inner panel over its stone inside the rail;
  the inset ("common-insideframe") and list box ("Professions-background-
  summarylist", L1) rules carry `dim = 0.8`, so every inset / list box has
  it. `opts.dimColor` gives cards on a dark list the main window tone. Frames
  with a parchment option use `Kit:StoneDim` (the panel only while the
  parchment is off).
- Done (2026-09-24): every window and HUD text frame -- the configurator,
  Dynamic UI Modification, the AddOn list, Macros, Edit Mode, Options, the
  character window's panes, Legacy, Guild & Communities, Social, Group
  Finder, Collections, Professions, tooltips, both trackers, chat, whisper,
  damage meter, dialogs, the Services menu, the quest and gossip dialogs,
  merchants, the auction house, trainers, the tabard vendor, the flight map
  (its map is never dimmed), the mailbox, bank, guild bank, trade, loot,
  books and letters, charters, inspect, dressing room, barber, socketing,
  stable, PvP scoreboard, battlefield map, ready check, split stack,
  colour picker, calendar, clock and stopwatch, channels, help; the
  redesigned configurator (its top bar, side list and pages) and the
  installer (its steps rail and one dark body), 2026-09-26. A NEW window is
  checked against this before it is handed over.
- Before handing a window over: look at it and ask "is there small text on
  brown?" — if yes, it needs the panel.
- The hex values above are Ember's. Since 0.14.0 there are seven palettes
  (section 6, Colours): the code paints by KEY (`innerPanel`, `mainWindow`,
  `text`, `selectedTrim`), never by these numbers, so the rule holds in each.

## 2f. MANDATORY: rarely used windows dress on first open (user, 2026-09-24)

"dress rarely used windows on first open". Building every window's look at
login cost memory (2263 kit replacements right after login, 88 MB live) and
the login frame (the addon profiler's peak 140 % of a frame). So:

- A window the player does not open every session (shops, mail, bank,
  trainers, books, charters, inspect, dressing room, barber, socketing,
  stable, PvP, calendar, clock, channels, help, macros, Edit Mode, the AddOn
  list, Options, group finder, collections, legacy, guild, professions,
  social) builds NOTHING of its look while it has never been shown. Its
  module's Sync builds only when the skin is already built or the window is
  shown right now; the window's OnShow hook builds it synchronously, so the
  first frame it draws is already dressed. Afterwards it stays built for the
  session and switches on and off as before.
- Kept dressed at login: the character window, bags, quest log, spell book,
  the HUD (bars, unit frames, nameplates, chat, tooltips, trackers, minimap)
  and the small popups that open in combat (loot, rolls, ready check,
  dialogs, split stack).
- The first build may run in combat when it only adds our own frames and
  textures and moves only textures and strings; a window whose dress moves
  protected children waits for combat to end.
- Hooks may be installed early if they do nothing until the skin is built;
  border / colour / scale callbacks and the /xxdump commands must cope with a
  window that is not dressed yet ("not dressed yet").
- A game window that should move in Edit Layout names its frames in its
  module's registry entry, `window = { frames = { "FrameName" }, plainGrab =
  true }` (UI Modifications makes its Edit Layout candidates from the
  registry; nothing is added there by hand). Nothing is made for it at
  login: a window with a stored place registers with Core's mover after the
  login (no frame made, its place put back), every other one when Edit
  Layout opens (a mover source, `MelloUI:AddMoverSource`).
- Check with /melloperf: a new window adds no kit pieces at login
  (`/run print(#MelloUI.Kit.repList)` before and after), and no handler of it
  runs while it is closed.

## 2g. MANDATORY: the soft shade follows the outline (user, 2026-09-26)

"on by default, strength 70% (slider 30-90%), outline pieces only"; one
stone per surface and "never a rectangle on round art" (the ui-shade plan).
Every kit element casts a soft dark shade of its OWN shape against the world:

- **Outline pieces only.** A shade partner goes under the pieces that form an
  element's edge against the world: a window's outer rail (outside only), its
  title plate, gem corners, ring or crest; a bar's backdrop rails and end
  caps; a unit frame's ring, bar brackets and orbs; a rim. Never
  under an inner piece (a row plate, a section band, a scroll thumb, a slot
  inside a window): that only darkens the window's own stone.
- **Its own shape.** Pieces take their baked partner from
  `Media/Textures/KitShadows.tga` (the piece's shape blurred), rails a
  nine-slice of it, round art the round shape, a bar with no piece the
  synthetic `shade/capsule` or `shade/square`. No rectangle on round art.
- **Under the element, over the world.** The partners are drawn by ONE shade
  frame per element, a child of its root one level below it (or a `host` of
  the element's own); the inward half of a plate's or ring's shade lies under
  the window's stone, never on it. A window's rail draws its own (outside
  only, the ring's corner cut).
- **Through the one system, never by hand.** Windows need nothing: every shell
  (`SkinWindowShell`, the hand-made shells, `Kit:OwnWindow`) is shaded by
  Modules/KitShade.lua on the bus's `shell`, on its first show. A HUD module
  calls `local el = Kit:ShadeElement(root, "<area>"[, opts])` once and
  `el:Add(rep)` per outline piece when it dresses the element; it never calls
  `Kit:Shadow` / `Kit:ShadowNine` itself (the ratchet's `direct-shadow`
  ceiling counts the two old callers) and needs no `shade` or `setting`
  listener of its own.
- **Its switches.** UI Shade (UI Modifications `uiShade`, on) and Shade
  Strength (`uiShadeStrength`, 0.7, 0.3-0.9), and a switch per area
  (`shade_<area>`, on): windows, actionbars, castbars, unitframes, chat,
  bags, minimap, tracker, buffs, widgets, nameplates (`Kit.shadeAreas`). They
  are all on the configurator's Look page (Look > General), and each area's
  own page has a link row to its switch. An area follows its part of the
  reskin too.
- **Cost.** Nothing at login (a rare window adds nothing until it is shown,
  2f; the HUD's parts, added while logging in, wait until the login's frames
  are over: `MelloUI:LoggingIn()` / `MelloUI:AfterLogin(fn)`, Core.lua, 3 s
  after the first PLAYER_ENTERING_WORLD, the one service for work that can
  wait for the login); at most 24 partner textures a frame (the rest on the next frames); a
  switch or a strength walks the made partners once and makes no garbage;
  the partners are static (nothing for Reduce Motion) and take the palette's
  `innerPanel` (repainted on `palette`).
- **The chat's rules.** The chat window's rail is a nine, outside only; a
  tab's nine leaves its foot open (it stands on the window); the minimized
  card is whole; the input box's plate is cut to its free side (it follows
  Input Box On Top); the button column's rail is shaded with its side toward
  the window open, cut at the window rail's outer edge, and the window's side
  shade stays whole under it. The Background Opacity moves only the stone,
  so the rail and its shade stay at full strength; a whisper popup's shade
  fades with the popup. Each chat element is made on its frame's first show
  while the reskin is on (a window never opened adds nothing).
- **Event widgets.** The game's widget containers lay out every child frame
  and region: nothing is added to a game widget. The shade stands on frames
  of MelloUI's own, one root per container at its strata and level, one frame
  per widget, shown and faded with it.
- **Protected and Edit Mode frames.** A shade frame is never anchored on an
  Edit Mode system frame itself: `Kit:ShadeElement`'s `opts.anchor` lays it on
  a frame or region of MelloUI's own (a bar's backdrop, a cap's holder, the
  XP bar's trough holder, the cast bar's trough, a window's rail skin), and
  the pet frame gets a host of its own, anchored on its texture; a protected
  root waits for the end of combat.

## 2b. MANDATORY for a window's portrait icon (user, 2026-09-21)

The portrait inside the ring is always brought to the class medallion's size
of the character window (0.759 x the ring, `Kit:FitPortrait`, aspect kept).
Then check the opening: if the icon does not cover it (the Legacy shield,
any asset that is not a full round picture), add the round inner-panel
background behind it (`Kit:RingDisc`: the palette's `innerPanel`, painted by
its key with `Kit:Paint`, so a new palette paints it again; never a fixed
colour) — the icon stays at the medallion size on the disc. Either the icon
fills the ring, or it sits on the disc; nothing else. The professions window's round icons are the first case; the Legacy
shield the second.

## 2a. MANDATORY for a window with tabs / pages (user, 2026-09-21)

Check both of these before a tabbed window is called done; they came from the
Legacy window, whose three pages each carried their own backdrop:

1. **One backdrop, one place.** Every page's backdrop picture is fitted to the
   WINDOW's rect (`rect = <window>`), never to the page's own background
   region: the pages' rects differ by a few px and each would get its own
   crop, so the stone would jump when switching tabs. Same picture, same
   crop, same position on every page. (A page hidden while the skin is built
   also has no size to fit to; the window always has one.)
2. **The outer rail stays in front.** A page backdrop stops at the outer
   rail's inner bevel: `inset = Kit:OuterRailInset()` (how far the grown-outward
   rail reaches into the window on each side), so the rail and its bevel are
   drawn over the picture on every page. Pages sit ABOVE the window frame in
   the game's stacking (the Legacy pages at level 100), so this is done by
   insetting the picture, never by raising the frame's level.

Compare every tab against the first one at the same state: the backdrop must
not move, and the border must look identical.

The same holds for any window whose backdrop is on the kit: ONE page picture
fitted to the window's rect inside the outer rail (`Kit:SkinWindowShell` with
`bg`), never a second one for a strip or band — two crops of the same
painting meet with a seam (the LFG who page, 2026-09-21). Bands the game
paints over its rock (a header band) are faded, not re-pictured.

## 2d. The HUD (docs/plans/hud_kit_plan.md section 1, in force from Round 1)

The HUD's elements are small and secure: geometry on a protected frame's
children runs out of combat only (`Kit:WhenOutOfCombat`), every rect read is
guarded against secret values, pieces re-fit from post-hooks on the game's own
layout calls (`CheckClassification`, the player's art swaps, `OnSizeChanged`,
frame show), never from a timer. A kit module declares what it covers
(`Kit:Cover(group)`), and Dark Mode / the Chat module's art hiding / the Unit
Frames tweak's name centring step aside for that group while it is covered
(user rule, 2026-09-21). What the unit frames taught:

- A bar's bracket goes ONE LAYER above the bar's fill, read from the fill
  texture (`BracketLayers`): the health fills draw at BACKGROUND, the power
  bars have no drawLayer (ARTWORK) — a BORDER bracket sat under them.
- This client resets a texture's alpha in `SetVertexColor` (the reaction
  band came back): `Kit:Fade` re-fades on it.
- A round piece's body is smaller than its box (the compass gems stick out):
  KitLayout `radius` (build_kit `body_radius`) is what a bar ends on.
- A frame drawn under other frames cannot cover their ends by level; the
  same piece drawn once more, cropped to the joint, on a higher holder can
  (`RingCover`) — a stacking device, listed under the agreed additions.
- The game's own bar ends can hide under a ring; a bar's visible end must be
  its real end (user: "I could be hitting somebody and not see it").
- Under a unit frame EVERY size reads secret — the frame's, its regions',
  and our own pieces' once they are regions of it. Pieces there fit to the
  sizes the template states (`fitHeight` / `fitWidth`), strips keep their cap
  widths as computed (`strip.wl` / `wr`) and tell their middle its laid-out
  size (`kitTileW`), and `MelloUI:Print` prints a secret as `[secret]`.
- A frame hidden at load (a cast bar) has no rects until it first shows:
  re-fit its pieces on `OnShow`.
- A strip narrower than its two caps goes capless (`FitCaps`): a plate whose
  caps must show (a plate with rune caps) gets a rect at least that wide, or
  a height at which the caps fit.
- A smaller frame gets the bigger frame's element SCALED by their portraits'
  ratio, not the same pixels (the 18 px band ate the 120 px party frame).
- A bar bracket's cap test (capless when narrower than two caps) is only for
  brackets that drop or grow a cap: a window's P1 bars keep BOTH caps even
  overlapping (the 160 px stat bars — that overlap is the approved look).
- A keybind presses a button through `SetButtonState`, not the mouse: a rim's
  pressed state follows that too.
- A pitch-sized rim reaches PAST its button: whatever the game lays next to
  the grid (the bags' money strip) must be raised above the buttons' level or
  it goes under the rims.
- A button skinned while the panel is already on is enabled by `replace`
  before the helper's own onEnable hooks exist: `Kit:SkinActionButton` runs
  them itself afterwards.
- A fill can live on a LOWER strata than the frame that carries its art
  (the status bars: LOW under a MEDIUM container): an opaque trough must go
  on a holder below the fill's frame, the hollow bracket may stay above.
- "Behind the bar" for a piece the game draws over the bar (the gryphons)
  means a holder at a lower STRATA (BACKGROUND), not a lower level: other
  bars sit at other strata / levels.
- Frames at the SAME level share one layer order (a `useParentLevel` bar's
  BORDER fill draws under its parent's ARTWORK text): to put a piece between
  a child's fill and the parent's icons, make it a region of the parent in
  the layer between (`NineSlice` / strip / texture owner modes).

## 3. Order of work on a new window

1. Screenshot the DEFAULT window first, every tab / state (collapsed panes,
   empty lists, hover, selected). It is the reference for every comparison.
2. Read its templates; list every art region: atlas name, rect, layer, owner,
   who toggles it. Most atlases are already in the table — the same atlas gets
   the same piece, no discussion.
3. Map the missing atlases (catalogue -> user's pick -> rule + doc row).
4. Build outside-in: outer border, title / close / portrait, backdrops and
   dividers, insets, lists (rows, headers, highlights), buttons and tabs,
   scroll bars and bars, junction covers last.
5. After each step: `/reload`, screenshot, compare with the default at the same
   state. Look for: art that vanished (a fade that hit a kit texture), a second
   frame behind the window, doubled rails at seams, rims / gems of the wrong
   count, pieces that stay behind when a pane collapses, level fights (a plate
   over text), sizes that do not match the default.
6. Document: KIT-MAPPING rows, CHANGELOG bullet, HANDOVER if a rule changed.
   Lint every Lua file, sync with robocopy, no commit until told.

## 4. Library mechanics to reuse (do not reinvent)

- One system per job (user, 2026-09-25): the look switch, the registry, the
  mover and its store, the settings bus, motion, colours, sounds and secret
  reads are shared by every window, the game's and MelloUI's own; section 6
  lists them. A panel wires them up, it never carries its own copy, and
  `Tools/lint/check_panels.py` fails when a copy comes back.
- `Kit:Replace(region, opts)` with a rule key = the region's atlas; kinds:
  frame, edge, strip, vstrip, slot, state, texture, tile, bar. Register the
  returned rep in the panel's `skin.reps` so enable / disable reach it.
- `Kit:Joint` for rail crossings; `Kit:RailInset` for a rail's centre line.
- ScrollBox lists: `AddAcquiredFrameCallback` (skin the row) +
  `AddInitializedFrameCallback` (refit: the row has its height only then);
  rows carry `frame.melloRep` (`false` = looked at, nothing to replace).
- Find things by what they ARE, not where they are: the pane divider is "the
  unnamed child that paints the divider atlas", a scroll bar is "a frame with
  Track / Thumb / Back / Forward"; the last unnamed child is not the divider.
- Shared parts live in Kit (2026-09-21): `Kit:SkinWindowShell` (rail, streaks,
  ring, title, close, maximize / minimize), `SkinSideTab`, `SkinSearchBox`,
  `SkinRedButton` (UIPanelButton or 128-RedButton), `SkinCheckButton`,
  `SkinCollapseButton`, `SkinStatusBar` (P1 on a StatusBar), `RimRect` (a rim
  whose opening is a given icon size), `FitPortrait` / `UnfitPortrait`,
  `HookScrollBoxRows`, `DumpWindow`. A new window module is the wiring only.
- A page backdrop that must sit under children at arbitrary levels is a
  `picture` with `owner = true`: a region of the page in the replaced
  texture's layer, no holder, no tie (the legacy pages, the quest list, the
  guild window's rock).
- File textures read back as numeric ids in this client: key them by hand
  (`as = "UI-Panel-Button-Up"`), from the template's parentKey, never from
  `Kit:ArtKey`.
- Lazily created frames (panes shown on demand) are picked up by re-running
  the finder on the game's show hook (`ShowSubFrame`), guarded by a marker.

### Sized while hidden (2026-09-22, the "blurred stone")
This client fires no OnSizeChanged for a hidden frame. A tiled body, strip or tile sized while hidden (the
configurator's sections behind the first tab) kept the piece's whole texture stretched over the rect until something
resized it: one 512 px tile over a 900 px box, read as blurred. Every tiled kind re-tiles on OnShow as well now
(`Kit:NineSlice`, the strip's rect, the tile kinds; the picture kind always did). `/kitwhat` shows it as a tile whose
uv is 0..1 on a rect larger than the piece.

### Two backgrounds on one window (2026-09-22, the "random stone")
The outer rail (`NineSlicePanelTemplate`, a frame kind) carries a BODY, the `window/frame_body` stone tile over the
whole rect, in a holder at the window's own level. A window whose `Bg` is also replaced by the page stone (a region
of the window) then has two full backgrounds at ONE level, and which draws on top is the client's creation order,
which changes between loads: the light page stone one time, the darker frame-body tile the next (read as "stretched").
Rule: ONE background per window AT ONE LEVEL. `Kit:SkinWindowShell` drops the rail's body whenever `opts.bg` is
given (both would be at the window's level). A window whose backgrounds sit on child frames above the rail (the
professions pages) keeps the body: no tie there, and the body fills what the pages do not cover. `/kitwhat` lists every
kit texture under the cursor (piece, rect, crop, tint, frame level) when a background is not the one expected.

## 5. Gotchas that cost a screenshot round each

- A nameplate rounds its layout to whole pixels, every frame and region of it,
  once, when the game makes it (`PixelUtil.SetRoundLayoutToNearestPixelRecursively`
  in its OnLoad). Anything added later is NOT rounded and slides by fractions of
  a pixel against the game's parts as the plate moves: the "flicker" of
  2026-10-04 (the fill's visible height flipping 10/11 px frame by frame).
  NameplatePanel's `Round.Tree` rounds the plate's tree again after each game
  layout and after making its shade parts; a new part on a plate needs nothing
  more, but one made at another moment must be rounded there too.
- A bar's fill must never end ON a rail's outer edge (the art's soft rows): a
  pixel's rounding shows it past the rail. Set the fill in to the rails'
  centres and thicken the bracket by the same (the nameplates: `into = 0.5`,
  NameplatePanel's `Inset.Margin`).
- A frame on a nameplate answers its anchors SECRET: never read a plate's
  anchors back to move them; lay them from the game's own layout (its setup
  options), as `Inset.Lay` and `CentreName` do.
- `Kit:Fade` must skip kit textures (`kitPiece`), or our own art vanishes.
- A row acquired before layout has height 0: guard every scale against 0 and
  refit on the initialized callback.
- `SetAtlas(name, UseAtlasSize)` resets a texture's SIZE; if the game calls it
  on every refresh (skill bars), post-hook it and put the fitted size back.
- A `MaskTexture` clips the masked texture to the MASK's rect; size the mask
  with the fill — but only where the client allows it: the character window's
  `common-stat-bar-Mask` takes a new height, the professions rank bar's
  `Professions-skillbar-mask` blanks everything it masks when its height is
  changed (bisected with `/profdump fill ...`). Test each mask; when it will
  not resize, keep its height and let the rails cover the band's edges.
- A WoW anchor carries BOTH coordinates: to place something at (x of A, y of B)
  use a helper frame spanning the two (`Kit:Joint` does).
- Frames at the same level draw in an order the client may change between
  loads (what was raised, what was created when): NEVER let one of our holders
  tie with the game's frame it must sit under or over, nor with another holder
  it must stack with — give each its own level (-2 / -1 / +1), and check the
  game's own levels with the dump (`/profdump frames`), since a page's children
  can sit at the page's level.
- Secret values (`issecretvalue`): `pcall` any read of a game frame's size or
  position that may be secret; never do arithmetic on one.
- Catalogue previews must show the piece at the GAME's size, with the game's
  own overlays (fill, text) where they are, or the pick will not survive the
  client (the bracket's caps hid most of a 160 px bar's fill).
- A new / changed `.tga` or TOC line needs a FULL client restart; Lua only
  `/reload`. The sync's robocopy exit code 1 is success.
- Bash heredocs mangle backslashes and some quotes: write patch scripts with
  the editor tools and run them.
- An `AnimationGroup` sets alpha on the client side, past the `SetAlpha`
  hook `Kit:Fade` relies on: a faded texture that an Alpha animation targets
  (the tracker's module header `AddAnim`, `setToFinalAlpha`) comes back. Find
  the animation with `group:GetAnimations()` / `anim:GetTarget()`, retarget it
  to 0 -> 0 while the kit is on (restore on disable) and re-fade on
  `OnFinished`; leave the rest of the animation to play. Stopping the whole
  group is the cast bar's way, where every part of it is FX.
- A strip's middle sits ONE sublevel under its caps: a game region left at the
  replaced texture's sublevel shows between them (over the middle, under the
  caps) — the dump lists it as a visible game texture. A middle that "does not
  match its caps" is a stray region, not the art: check the dump first.
- Rendering two kit pieces offline from the packed textures (PIL, the same
  uv) settles whether the ART differs; when they match offline, the client
  draws something else there.
- A cap that carries a glyph (the S1 edit plate's magnifier) is wrong on a
  box that is not a search box: drop it (`dropCap`) and give the family a
  plain end piece (`<base>_end_l/r_<state>`, the far cap mirrored, both kit
  folders + manifest, rebuild) — never leave the glyph and shift the text.
- The game's mouse-away fades (chat) set alpha through `SetAlpha` every
  frame (UIFrameFadeIn / Out): a post-hook that puts the wanted alpha back
  holds a frame steady without touching the fade code.
- The client hands atlas names back in canonical case
  (`UI-QuestTrackerButton-Collapse-All` for the XML's lowercase): rule
  lookups go through `Kit:RuleFor`, which retries ignoring case. Key rules as
  the XML spells them; never add a second spelling.
- A real `StatusBar`'s fill is the widget's own texture on its whole rect: it
  cannot be re-anchored into a bracket's opening like a texture fill. Put the
  bracket's caps OUTSIDE the rect (`capOut`) and set the bar in by the arms
  (re-applied after the game's own re-anchor), so the fill ends at the gems.
- A pooled row's name can read secret (the damage meter's entries): the dump
  prints `[secret name]`; never hand a frame's name to `format` unchecked.
- A window whose hover effect starts from its own `OnEnter` never sees a
  cursor that lands on a mouse-enabled child (rows): hand the child's
  `OnEnter` on to the window.
- A strip's cap decision (capless when the rect is narrower than two caps)
  is made from the rect's width at fit time: a box skinned before its window
  laid it out (the backpack's search box, 0 px wide at load) kept its caps
  hidden for good. Strips on a frame rect now refit on its `OnSizeChanged`
  (Kit:Replace); `/xxdump reps` prints every strip's scale, cap widths and
  CAPLESS / drop flags with the caps' rects.

## 6. Own windows: MelloUI's own frames (user, 2026-09-25)

"that should include all of the windows, also our self created ones like the
QuestList, the Custom Scrollable Quest Tracker, Custom Chat etc, so basically
everything should be lined up and working flawlessly with one another". A
window MelloUI makes itself (the configurator, the installer, the question
dialog, the Restock List, the Quest List in the map's quest log, the Quest
Tracker under the minimap, the whisper popups, the widget column, the
Route arrow, the Services bar, the copy window) keeps every rule above and
uses the SAME shared systems as the game's windows. It never carries its own
copy of one; the ratchet (`python Tools/lint/check_panels.py`, run by the
Lint workflow) fails when a copy is added and names the system to use.

- **Its look switch: `Kit.Areas` and `Kit:IsOn(area)`.** The window's area is
  one row of Kit.Areas' list (Kit.lua): `{ name, cover = true }` (a HUD
  group), `follows = "<area>"` (the whisper popups follow `chat`, the Services
  bar `minimap`), `module = "<Module>"` (the Quest List follows QuestLogPanel)
  or `reskin = true` (+ `switch = "<UI Modifications key>"`, the Quest
  Tracker's `questTrackerKit`). The window asks `Kit:IsOn(area)` when it
  builds or shows (live, no table made) and switches an already built look on
  the bus's `look:<area>` (`MelloUI:On("look:<area>", fn, owner)`, told on the
  frame after a change, only when the answer really changed). It never reads
  the reskin switch or another module's state by hand, and nothing polls. The
  listener is idempotent: a window built between a change and the next frame
  reads IsOn live and then gets the 'look' once.
- **Its shell: `Kit:OwnWindow(frame, opts)` (Modules/KitWindow.lua).** One
  call gives an own window everything around its content, the same for the
  configurator (the first) and the installer (the second):
  - the look switch: `area` picks the kit or the plain palette look
    (`Kit:IsOn(area)`) and the shell takes the `look:<area>` listener; the
    plain look is the window's own regions, which the kit's reps fade while
    they are on, so a switch only enables or disables the recorded reps;
  - the outer rail and the page stone, and with `calm = true` (0.15.0, the
    cleaner look the user picked: Background A) ONE flat `mainWindow` ground
    over the page (`shell.calm`, a region over the stone in both looks), the
    stone left only as a band inside the rail: the configurator, the
    installer and the question dialog; their panels (`W.Panel`) lie on that
    ground, one surface, one panel; the emblem as a crest centred on the
    top rail (`ring = { at = "top", scale }`, rule `MelloUI-Crest`) or in
    the standard corner ring (`at = "tl"`), always on its disc (2b); the
    title plate (`plate = "crest"`: the short plate under the crest, the
    configurator's 2c exception; `"rail"`: the standard plate on the rail)
    with `shell.title` in `Kit:TitleFont`;
  - `close`, the drag strip `shell.grab` (down to `grabBottom`), Core's one
    mover (`mover = { key, save, default, plainDrag, label, page, group,
    ... }`: exactly one mover per window, the rail's own shell registration
    joined to it; the crest kept on the screen with the window), `fit` (scaled down to fit,
    never up, not while the mover holds a scale the user gave it, again on
    the `scale` topic), `escape` (UISpecialFrames; `shell:SetEscape(on)`, the
    installer's countdown turns it off) and `sounds` (PlayUISound
    "window_open" / "window_close" on a real open and close, not on Alt+Z);
  - `shell:Replace(region, opts)` (every rep recorded for the switch;
    `shell.replace` and `shell.skin` for the kit's helpers that take them),
    `shell:Kit(fn, ...)` (dressing that needs the kit: now while the kit look
    is on, else at the first switch on), `shell:Plain(region)` (a plain-look
    region, hidden while the kit is on), `shell:OnKit(fn)`, `shell:Fit()`.
  - **`shell:Anchor(parent, layer)` is THE invisible region** to hand to
    Kit:Replace where a widget has no game region of its own: an alpha-0
    solid, the only one in the own-window code. The ratchet exempts exactly
    that line, by its marker comment in KitWindow.lua; any other colour
    number added to KitWindow.lua, Widgets.lua or Config.lua fails it.
  Nothing is made at load: a window builds its shell at its first open (2f),
  and its own OnShow / OnHide are set before the call (SetScript drops
  hooks).
- **Its controls: `MelloUI.Widgets` (Core/Widgets.lua), one set for every
  own window.** The cleaner look (0.15.0, the user's picks: flat in both
  looks; the kit's list box, red plate, slider pieces and header plate stay
  the game windows'): `W.Panel` (THE content panel: a flat `innerPanel` fill
  in a 1 px `border` edge, on the calm ground; never on another panel),
  `W.Header` (a section's heading: the title in `selectedTrim` and a 1 px
  `border` hairline after it, no plate; the configurator's sections and
  cards, the installer's groups), `W.Button` (a flat `raisedPanel` plate in a
  1 px `border` edge, no gem caps; `opts.gold`, the main action (Install…,
  Install again, the installer's Continue, Restock's Buy): its edge and label
  in `selectedTrim`; `W.FlatButton(b, gold)` the same look on a button made
  by hand), `W.Slider` (a thin track, a round knob and a box to type the
  value in: the box never takes the keyboard by itself, Enter, Tab or
  leaving it takes the number, Escape puts it back; `slider:SetRange(min,
  max, step)`), `W.Switch`, `W.Dropdown` (`dd:SetValues(values)`: the list
  swapped), `W.CloseButton`,
  `W.IconBox`, `W.Row` and the typed rows (`W.ToggleRow`, `SliderRow`,
  `DropdownRow`, `ButtonRow`; they take get / set, so any data can sit behind
  them; `opts.gate` dims a row and says "Switch on "X" first." in its hint
  slot, or the gate's own line ("Not for Pet"), so no row changes height;
  `opts.onCover`, the dimmed row's click: the configurator's jump to a switch
  on another page or pick), `W.PictureRow` (a look chosen by its picture:
  the chosen one's picture and name, a click opens `W.PictureMenu`, ONE flyout
  per host window made on its first open, its tiles from a pool drawn by
  `Kit:ChoicePicture`, closed by a tile, Escape, a click outside, a scroll, a
  tab, page or pick change, the host hiding and a fight; it never opens in a
  fight), `W.LinkRow` (a setting whose one place is another page: its value
  and a button naming that page, "Look >"), `W.RowPlate` (one hover for a row, the
  palette wash or the kit's plate, faded through Anim, none on the selected
  row; `W.RowPlateChild` for a control on it; `W.Flash(row)` lights a row's
  hover a moment, held by a one-shot timer: the row a jump brought into
  view), `W.Card` (a choice card),
  `W.NavRail` (a side list or a numbered steps rail: groups that fold, one
  marker that glides, `Reveal`, rows from a pool; a name too long for the
  row is clipped and shown whole in its tooltip; `spec.head` a strip over
  the list for a control, and a search's results in the list's place:
  `ShowResults` / `HideResults` / `MoveResult` / `Result`, two-line rows
  from a pool of their own, as tall as their fonts want, a path too wide
  for the row kept to its end, the same marker), `W.Pager` (pages in one
  scroll frame, switched with a cross-fade and a shield over the page area
  while it runs; `SetPageHeight` is the only height setter),
  `W.RowBudget` (ONE budget of rows a frame for every own window's pages:
  `Begin(ms)` gives the time to stop at or nil, `End()` counts what was
  made, `Spent(ms)` books a first open's own work; never a budget of its
  own), `W.RoundIcon` (a round button: the icon round-masked in the
  minimap's tracking rim, the kit's round rim while `b:SetKit(Kit)`, and
  with `opts.shade` a shade partner of that area on the rim: the Reminder
  widget's buttons), `W.HoverLight(b, shape, region, out)` (0.18.4: a
  button's mouseover light in its border's shape, the user's rule "every
  round border the round glow, every square one the square glow": the
  game's round light over a round border, its square one over a square
  border; the button's own highlight texture, so no script; every own
  button that lights on hover takes it, never a light file set by hand),
  `W.TrayBox` (a small box of the L1 list-box look, the
  inner panel over the stone: Restock's shop list), the palette parts
  `W.PaletteSwatch`, `W.PaletteValues` and `W.PaletteName` (Look's Palette
  row, Home's Your setup and the installer's cards: a picture of one
  palette, or the one in use painted by key) and `W.ShowTooltip`. Each builder takes `skin` (the window's shell, or nil for
  the plain look) and asks it for the kit (`skin:Kit`, `skin.replace`,
  `skin:Anchor`); it never reaches for `MelloUI.Kit` itself. Kit and Fonts
  load after Widgets.lua and Config.lua: nothing of theirs is bound at file
  scope, everything is looked up when a builder runs.
- **Its live, small widgets: the Reminder widget and the widget column
  (`MelloUI.Reminders`, Core/Reminders.lua; 0.16.0).** Anything that wants to
  tell the player something now -- an errand, a line being read, a roll, an
  offer, a timer -- is ONE spec on this widget, never a frame of its own:
  `Rem:Register{ key, check, ... }` puts it by the portrait (a reminder), and
  with `column = true` it is a row of the one column (Voice Over and the
  Widgets module's eleven): the face in the kit's round rim (`icon`, a 3D
  `model`, a unit's `portrait`), `title` and `text` on a soft band, a gold
  progress ring (`progress`: a Cooldown swipe with Media/Textures/
  ProgressRing, run by the engine; paused, muted), `count`, `sub`, the hover
  buttons (`actions`, glyphs from Media/Textures/WidgetGlyphs; `secure` for a
  macro the player's own click runs, out of combat), a `tray` (W.TrayBox) and
  the column's one Edit Layout place ("widgets"; its lock, Reminders'
  widgetLock). Newest on top; shown in combat unless the spec says
  `combat = false`; nothing made at login, one shared timer only while a row
  has a running time or a talking face. The contract is the file's header and
  "The column" section.
- **Its lines that stack and fade: `MelloUI.Feed` (Core/Feed.lua; 0.17.0,
  lifted from Gains when Combat Text's feed came).** A column of soft-shaded
  lines with no frame round them -- newest on top, at most `max`, each held
  and then faded (Anim:Mirror), the ones below sliding a slot (Anim:To),
  Reduce Motion a plain fade -- is ONE `MelloUI.Feed:New(opts)`: its holder
  and Edit Layout mover (`key`, `label`, `page`, `when`), `width` / `pitch`,
  `newRow(row)` for the line's own texts and band (Shade:Band with
  Shade.TEXT), `from = "bottom"` for a column standing on its holder's bottom.
  `feed:Put(kind, id, hold, apply, ...)` raises a line of the same id or makes
  a new one; Gains and Combat Text's Feed are its users. Nothing is made
  before the first line; lines are pooled. The ratchet's `feed-copy` fails a
  column made by hand.
- **Fading parts of the UI: `MelloUI.Fader` (Core/Fader.lua; 0.17.0, Unit
  Frames' Fade Out Of Combat lifted into it).** One fader, every element on it:
  `Fader:Register({ key, frames, mouse, needed, follows, own, watch })`, each
  element's choice the Fader module's `show_<key>` (Always / In Combat / On
  Mouseover; Modules/Fader.lua holds the page and the elements). Alpha only,
  relative to the frame's own alpha (a game write learned by a post-hook, never
  fought on a busy frame), pointer hooks on the children that take the mouse,
  holds as timers, fades through Anim; nothing made while the module is off.
  Never a second fade of a frame from a module of its own.
- **Previews of how the UI behaves: `MelloUI.Preview` (Core/Preview.lua;
  0.17.0, the configurator's Preview list).** One scene engine: it fires the
  bus's `preview` beats (start, pull, hit 1..12, kill, stop) and never fakes a
  game event or touches a game frame. A module that takes part listens on the
  bus, asks `Preview:Plays(part)` before it shows anything (a part played
  alone: only that one), shows its own sample state from its own code, and
  undoes only what it did at "stop" (on "combat" it leaves its combat state
  to the real fight). `Preview.PARTY` is the one made-up group; the stand-in
  party frames are ConfigPreview's sample frames. A new part: an entry in
  `Preview.ITEMS` and the module's own listener -- never a scene of its own.
- **Never fight the game's per-frame writes: COVER (0.17.0; the user's FPS in
  combat, 160 down to 66, docs/plans/fps-portrait-fix.md).** Never undo a
  game write on a path the game runs every frame or every update (the target
  of target's OnUpdate runs `UnitFrame_Update` every frame: its portrait, its
  name, its power bar's art; RefreshAuras its aura cooldowns; the bars'
  OnUpdate their values). Each write back makes the game's next write a real
  change again, and the ENGINE pays (texture loads, layout): a Lua profile
  cannot see it. Instead:
  - cover the game's region with an own one on its rect, in its layer one
    sublevel up (or the same sublevel, made after it), and copy what the
    game changes on it (alpha, colour, desaturation, show) by post-hooks
    that write only when the value changed. The patterns: Class Icons'
    portrait cover (an own texture and a dark round backing), Bar Textures'
    covered power bar (an own fill and backing, cropped to the game's fill by
    a mask on the fill's rect, so a secret value moves it), Unit Frames' name
    cover on the target of target, the execute tint (the bar's rect cropped
    by a mask, so a value change sets its alpha only);
  - or write only when the game's value really changed (compare first; a
    secret cannot be compared: then cover);
  - cost, highest first: texture / atlas swaps and mask changes; anchors and
    sizes; colours and alpha (fight those only when a recording shows them);
  - a write back that remains goes through `MelloUI.Perf.WriteBack(label)`,
    so `/melloperf record`'s "WRITE-BACKS ONTO GAME REGIONS" names it, with
    the hooks over 30 a second and the tweens that kept the driver running.
  MelloUI's own windows and HUD pieces (the damage meter's lines, race bar
  and summary) follow it from the start: own frames, never a game region
  written per update.
- **New tags: every new option says its update (user, 2026-09-26).** "every
  new Dropdown menu, every new slider, every new checkbox etc needs to get a
  "New" tag for people to easly navigate to that option to test it out in
  the Configurator, every next update, the old "New" tags are being removed
  and reapplied to the new stuff". So:
  - an option added in an update carries that update's version: `new =
    "<version>"` on its schema entry (every kind: toggle, slider, dropdown,
    button ...), in the opts of a row built by hand (`W.ToggleRow` and the
    other typed rows, `W.Row`: `opts.new`; in the configurator
    `RowOpts(sec, new)`, `new` a named table's field, as
    `RowOpts(blk, BACKUP_TAG.new)`), or in a table the hand-built control
    names (Home's `PROFILE_DD`, the Profiles page's `BACKUP_TAG`, the top
    bar's `EDIT_LAYOUT`; a `PARCHMENTS` entry, a border kind, a shade area or
    a background section its own `new`); a bare
    control (`W.Button`, a `CreateFrame` button, check box or edit box) by a
    tag call after it that names it (`W.NewTag(row, row.rename,
    RENAME_TAG.new)`, `W.ButtonTag(button, ...)`). A new module
    with a page and no option of its own tagged adds `new` to its
    RegisterModule (its page title and side-list entry). A switch UI
    Modifications defines from the registry (a window's Painted Skin, a folded
    feature's switch) takes it from the registration;
  - it shows ONLY while `MelloUI:IsNew(new)` (Core: the TOC's Version; a
    test build's "0.14.0-rc5" counts as 0.14.0), so the next update shows
    none of the old ones and nobody removes them by hand;
  - the one tag is `W.Tag` (the installer card's "Recommended" plate):
    `W.NewTag` right after the row's label (the hint after the tag, dimmed
    with a sleeping row), `W.Badge` on a tab's top edge (a page's tabs; its
    `inset` keeps it clear of a control at the frame's right: the
    configurator's search box and its clear button), `W.ButtonTag` inside a
    text button at its right (the top bar's Edit Layout, widened by the tag,
    its label keeping its own width), and snug near the right edge of the
    side list's entry and of a folded group's header (`W.NavRail` entries'
    `new`: a page by its rows), and one line in Home's What's new. All of it
    is read from the schemas through the layout's rows
    (Core/ConfigLayout.lua) once, when the configurator is made (made with
    its rows, never at login);
  - `python Tools/lint/check_new_tags.py` (run by `Tools/release.py` before
    anything is tagged) compares every option with the previous release, by
    module and key (a key whose kind changed, a switch become a dropdown, is
    new): it fails on a new option without the current version, on an old
    option tagged with it, on a new page with nothing tagged, and on a file
    that builds controls it does not know (its `OWN_FILES`, the
    configurator's, or `NOT_CONFIGURATOR`); a page's own tools (the picker,
    Copy from…, All, Reset this page) are no options (`PAGE_TOOLS`, never
    tagged), and a setting that was another kind of control in the last
    release keeps its age (`MOVED`: Dynamic UI Modification's own rows of
    0.14.0); it stops (exit 2) when a file or a module's OnInit fails in its
    world. `--fix` takes older versions' tags
    out of the files: table fields, a `x.new = "..."` line and a version
    handed by position; anything else it names for a hand, and a file that
    would not compile after it is put back.
- **Where an option shows: `Core/ConfigLayout.lua` (0.15.0), one place
  each.** The modules keep their option schemas as the definitions (type,
  key, name, desc, values, range, `parent` / `requires`, `new`); the data
  file lays them out: the side list (`L.groups`), the pages (`L.pages`: their
  tabs, the module whose switch heads them, a picker), and one `R(page, tab,
  section, "Module.key", extra)` line per row, in the fixed section order
  (General, Look, Text, Layout, Behaviour, Sound, Advanced). A setting the
  whole interface shares lives on Look, and each page it touches has a
  `Link(...)` row to it instead of a copy. A new option is its schema entry
  and its one line; one with no line lands in Advanced at the end of its
  module's page, and the checks name it.
- **The configurator's search box finds every option by itself.** Its index
  is the layout: each page of the side list, its tabs (two or more), its
  picks ("Windows > Bank", found by the window's own description too) and
  every row (a row per pick is ONE result, found by each of its settings'
  names and descriptions), so a placed schema option needs nothing more.
  A result's small line is its breadcrumb, `Page > Tab > Section`; the jump
  opens the page on its tab and a pick that has the row, scrolls to it and
  lights it (`W.Flash`). Link rows are not results (their target is). A row
  built by hand on Home or the Profiles page is named in its block's
  `HomeSearch` / `ProfilesSearch` (its label, what its tooltip says, its
  `new`, and `when` if it shows only at times: asked once a search, never
  per keystroke, so a `when` may read the game) and found by
  `HomePart` / `ProfilesPart` for the jump; a control that is not a row
  (the top bar's) is added in the Search block's `Build`. The best first: a
  name that is the word, then one that starts with it, has a word starting
  with it, holds it, then the place it lies, then its description; within
  each, a page before a tab or a pick, those before a row.
- **Its registry entry.** Its module's `MelloUI:RegisterModule` carries what
  the configurator, UI Modifications and the installer show; nothing is
  listed by hand anywhere else (UI Modifications makes its PANELS, TWEAKS
  and PLAIN_WINDOWS from it, and the configurator's old MODULE_META is gone;
  Core.lua's header has the shape):
  - `window = { label, desc, tab = "Windows" | "HUD", order, switch, frames,
    plainGrab, addon, firstOpen, include }` makes it a kit panel with nothing
    edited in UI Modifications or Config: UI Modifications defines its
    Painted Skin switch (its name, `UIModifications.<Name>`; `order` sorts
    the definitions); `switch` makes that a setting of UI Modifications (an
    own window's look switch, the Quest Tracker's `questTrackerKit`) instead
    of a module's switch; a `tab = "Windows"` panel without one is a pick of
    the configurator's Windows page by its `label` (its `desc` found by the
    search), and every other panel's Painted Skin row has its `R` line in
    Core/ConfigLayout.lua (the page of what it dresses); `frames` +
    `plainGrab = true`: the named frames move in Edit Layout; `include` is
    the old pages' structure, no longer read (the layout places the panel's
    own options).
  - `group` and `navOrder` are no longer read (0.15.0: the side list is
    Core/ConfigLayout.lua's `L.groups`, the pages its `L.pages`); Core still
    checks their types.
  - `icon` and `flavour` for its side-list icon and page header; `role`
    ("core", "look", "feature", "adds" or "replaces") says what the
    installer's setups do with it (a hidden kit panel with a `window` is
    look); `area = { key, follows }`; a feature folded under UI
    Modifications is `tweak = { label, desc, order, off, always }` (`order`
    as window's); `new = "<version>"` for a brand-new module's page (its
    side-list entry and page title tagged New while that update runs: New
    tags above).
  - `keep = { patterns }`: the module's settings that are one character's
    or one PC's own, which no profile, share string or copy carries and a
    profile load never wipes (Route's `flights_<GUID>`, Restock's
    `list_<GUID>`, the Reminders' `trainer_<GUID>` and
    `notnow_<GUID>_<key>`).
  A field of the wrong type (or an unknown role) is reported, never fatal.
- **Its place: `MelloUI:RegisterMover` (Core).** `MelloUI:RegisterMover(frame,
  handle, { key, anchor, default, save, reset, min, max, base, with,
  plainDrag, label, page, group, placeholder, visible, follow, resize,
  locked, note, resetLabel, when })` (Core.lua's header says what each
  does): one store (UI Modifications' `positions`, kept whether that
  module is on or off, so profiles, share strings and the macro backup carry
  it), and Edit Layout (its plate: `label`, `page` for "All options >",
  `placeholder` for a window still hidden; its Reset and Reset all), its
  session (pending places until Save or Discard) and the UI-scale put-back
  reach the window. `plainDrag = "always"` drags it by its handle at any
  time, with UI Modifications off too, but while Edit Layout shows only a
  `group = "tool"` window's (the configurator's, the installer's, Edit
  Layout's own bar: never a plate, never a pending change). Never register
  a MelloUI frame as an Edit Mode system: the game's own elements get Edit
  Layout's "Move via Edit Mode" instead. Set the frame's own OnShow / OnHide BEFORE registering, and never
  SetScript OnDragStart / OnDragStop / OnShow / OnHide on a registered frame
  (hook them). `MelloUI:FitOnScreen(frame, extraRects)` keeps it on the
  screen. Never `StartMoving` of its own, nor an x / y in its own settings.
  The one exception: the mover takes one handle a window, so a window whose
  child controls must drag it too may start the entry's plain drag itself
  and set `entry.moving = "plain"` (Core's OnHide or the next drag then ends
  it), as the Voice Over overlay's buttons do; such a drag skips the grid
  and the snap. The ratchet's `start-moving` ceiling counts it.
- **What changed: the settings bus, never a self-hook.** `MelloUI:On(topic,
  fn, owner)` / `MelloUI:Off(owner[, topic])` for "setting", "module",
  "restart", "look:<area>", "cover", "parchment", "border", "fonts",
  "scale", "editmode", "shell", "palette", "column", "installer",
  "editmodelayout", "backup", "shade", "where", "reminder", "editlayout",
  "mover", "meter", "configurator" (Core.lua lists what each carries). A window
  takes its listeners when it is built, never at file load, and each
  returns at once while the window is closed
  (at most marking what its next show brings in line). Never
  `hooksecurefunc(MelloUI, ...)` or `hooksecurefunc(Kit, ...)` on MelloUI's
  own functions: such a hook runs for every setting of every module and can
  never be taken off. Many settings at once go through
  `MelloUI:Batch(fn)` (one Fire per key, one backup). Loading a profile,
  Revert, and the configurator's Copy from… and Reset this page ask first
  through `MelloUI:Confirm` (the last two: the user, 2026-09-29), in plain
  words that name the page or pick and how many settings change; Copy
  from… and Reset this page ask nothing when nothing would change or when
  a fight would refuse the writes (the line at once). The configurator's
  All (one row's value for every pick that has it) acts at once, as the
  row's own control does. A UI-scale change: `Kit:OnUIScaleChanged(fn)`.
- **Its text on parchment: `QI.Surface`.** A window with a parchment sheet
  registers `QI.Surface(area, { on = fn, sheet = true, skip = fn, roots = fn
  })` (`sheet = true`: the inks set for the kit's darker sheet);
  `Kit:SetParchment(area)` refreshes it. Strings are never recoloured by hand
  (the parchment ink rule). A character's name on parchment is in the title
  ink with the ONE gem in its class's true colour before it: `QI.Gem(parent,
  size)` where MelloUI owns the region (the tooltips), `QI.GemCode(r, g, b,
  fontSize)` inline where it is text (the chat's and the whisper windows'
  names); the class from the GUID (`QI.ClassColour(classFile)`), never from a
  colour, and no gem when the class is unknown or secret. An item's name gets
  the quality gem where MelloUI writes the name (the tooltips); the chat's
  item links stay bright on their soft band (the user's choice, 2026-09-24).
  The bag, bank and guild bank slots wear the same `QI.Gem` on the item
  button (not a name on parchment). The combat log is never inked (it adds
  lines too fast), so its names keep the game's colours.
- **Motion: `MelloUI.Anim`.** Reduce Motion is honoured by every helper:
  - a tween: `Anim:To / From / FadeIn (onDone) / FadeOut / Pop`,
    `Anim:Land(frame[, prop])` (a running move jumps to its end) and
    `Anim:Target(frame, prop)`; tween tables are pooled, nothing is made per
    move once warm;
  - a page or tab switch: `Anim:CrossFade(old, new, opts)`, one opts table
    per caller (`slide`, `outTime`, `inTime`, `instant`, `outInstant`: the
    leaving frame hides at once and only the new one fades in); the
    configurator's pages use `outInstant`, and a page over 40 rows fades
    without the slide;
  - smooth scrolling: `Anim:Glide(target, opts)`, one glide per scroll frame
    (or `get` / `set` / `range` for an offset surface), `Anim.GLIDE_RATE`,
    wheel steps 80 for pages and 68 for a side list; a set the glide did not
    make (the scroll bar dragged, a jump) stops it where it lands;
  - a looping glow: `Anim:Pulse(region)` (a still picture under Reduce
    Motion); a slow turn round and round: `Anim:Spin(region[, period])`
    (0.15.0, the same); an AnimationGroup: `Anim:PlayGroup(group, settle)` /
    `Anim:StopGroup(group)`;
  - regions that slide softly out of a button and back:
    `Anim:Expand` / `Anim:Collapse` (after a grace, so the pointer can
    travel onto them) / `Anim:Retract` / `Anim:IsExpanded`: two reused
    AnimationGroups a region, no OnUpdate, at once under Reduce Motion (the
    Reminder widget);
  - a band that copies the game's own fade of a line: `Anim:Mirror` /
    `Anim:StopMirror` (the centre texts' shade; it follows the game, so it
    plays under Reduce Motion too);
  - the round soft glow round a round button: `MelloUI.Shade:Glow(parent,
    opts)` (Core/Shade.lua: one texture in the palette's gold, added as
    light, hung by anchors only; `Settle()` pulses three breaths then holds,
    `Still()`, `SetStrength("near" | "reach" | n)`; stopped while hidden,
    steady under Reduce Motion).
  Never a raw group's `:Play()` or an OnUpdate tween of its own. Never tween
  the scale of anything with a background (the fixed-resolution rule).
- **Colours: the palette only, by KEY.** `W.Paint(region, key, how, alpha)`
  (Kit:Paint underneath; `how` "fill", "vertex", "text", "backdrop" or
  "border") looks the colour up in `MelloUI.Palette` when it paints and
  remembers the region, so the bus's `palette` topic paints it again. Where
  a colour is read directly (a tooltip line, `MelloUI:PaletteCode(role)` for
  a text code), it is read when drawn, never held from load. The `palette`
  contract: it is fired after both the palette and the Kit Colours are in
  place; a new palette is a NEW table in `MelloUI.Palette`, never the old
  one edited, so a listener remembers the table it painted from and returns
  at once when it is the same (a Kit Colours change fires the topic too).
  No number literals (the ratchet counts them per own window: Widgets.lua,
  KitWindow.lua, Config.lua, Installer.lua and InstallerWindow.lua at 0,
  the older windows at ceilings that only go down), and no `MelloUI.Palette
  and ... or { ... }` fallback: the palette is defined in Core.lua, which
  loads first.
  - **The palettes (0.14.0).** `MelloUI.Palettes` holds the seven (`order`:
    ember, obsidian, obsidianVibrant, royalAzure, royalAzureVibrant, felEmber,
    felEmberVibrant), each ten roles; `MelloUI.Palette` is the one in use;
    `MelloUI:PaletteId()`, `MelloUI:SetPalette(id)` (the setting
    UIModifications.palette; a switch fires `border`, then exactly one
    `palette`). **`MelloUI:KnownPalette(id)` is the one palette-id rule**
    (a registry id, anything else Ember): Core, the Kit, UI Modifications,
    the widgets and the installer ask it, never a check of their own. The
    kit's folder follows the palette AND Kit Colours: `Kit:LookFolder`,
    `Kit:ColourLooks`, `Kit:ColourLookShown`, `Kit:LookRoot`.
  - **Meaning colours** stay the same under every palette, and only these:
    the chat channel inks, Voice Over's state colours, Route's straight-guess
    blue and beam red, the map's quest-giver blue, and `MelloUI.Meaning`
    (Core.lua: `cannotUse`, #4E1812, what the player cannot use or learn:
    the merchant's and trade's red cards, the trainer's rows; read when
    drawing). Each such line in a file carries the marker `(meaning colour)`;
    the ratchet counts them apart (`meaning:<file>` ceilings).
- **Sounds: `MelloUI:PlayUISound(kind)` (Core).** Never call `PlaySound`
  directly, whatever its argument. The soft clicks "page", "tab", "check_on", "check_off"; the game's
  own "option_on", "option_off", "menu_open", "menu_close", "menu_button",
  "window_open", "window_close", "tick", "waypoint_set", "waypoint_clear";
  the on-screen notice's chimes "notice_track", "notice_arrive",
  "notice_learn", "notice_fail"; Route's World Marker as it changes,
  "marker" (0.18.4: the user's own Quest_TrackChange from their SFX
  library, Media/Sounds/SFX, the game's runecarving kit behind it); the
  Rare Alert's "rare" (0.18.5: the user's own RareMob_Ward, on the Master
  channel, the game's raid warning behind it). A new sound is one row of Core's SOUNDS
  table; Custom Sounds is asked first and its PlaySound hook swaps a game
  kit as it does any game click.
- **Secret values: `MelloUI.Safe`.** Bound plainly at load, `local Secret =
  MelloUI.Safe.IsSecret` (also Value, Number, Text, Call, and ScreenRect: a
  frame's rect on the screen, left, bottom, right, top in pixels, or nil
  when any of it cannot be read plainly; the one reader, no copy of it). No
  helper of its own and no stand-in: a test world that loads a file without
  Core runs Core's Safe block itself.
- **Frames in a window: `local CreateFrame = MelloUI.Safe.CreateFrame`**
  (0.14.0; a player's game froze opening the world map with a gamepad).
  While the game's Gamepad UI is on, its navigation walks a whole open
  window again (every frame in it) for each frame made in it, and that
  walk counts against MelloUI's script time. Every file that dresses a
  window binds Core's maker once at the top: a frame whose parent lies in an
  open window is made with no parent and put on it at once (the Gamepad UI
  off: the game's call, as before). The ratchet's `window-createframe`
  check holds it. With the Gamepad UI on, MelloUI also never writes into, or
  calls, the game's shared menu, popup, panel and map-pool code (0.15.0: the
  Escape menu's entry is an own button, questions go through
  `MelloUI:Confirm`, the Quest List's map marks stay out of the map's pools,
  its panel is not in WorldMapFrame's tree); the ratchet's panel-call checks
  hold that.
- **Later, not a timer: `Kit:NextFrame(key, fn)`**, fn made once per key.
- **Its shade: section 2g.** A window on a shell is shaded by KitShade with
  nothing to do; an own HUD element calls `Kit:ShadeElement(root, area)` and
  `:Add` for its outline pieces, never `Kit:Shadow` directly.
- **A reminder: `MelloUI.Reminders` (Core/Reminders.lua), THE reminder
  widget.** One round button beside the player's portrait ring
  (`UnitFramePanel:ReminderAnchor()`, the ring or the game's portrait; Place
  left, above or right), with a count and a tooltip listing every reminder
  that is up; hover slides the others out (`Anim:Expand`), the glow is
  `Shade:Glow`, the rims `W.RoundIcon` in the unit frames' shade. A module
  never makes a nudge of its own: it registers
  `Rem:Register{ key, check, icon, text, label, urgency, when, onClick,
  persistent, target, kind, hint, enabled, dismiss, tooltip }` and calls
  `Rem:Refresh(key[, raise])`; `Rem:Dismiss(key, untilWhat)` is Not now,
  `Rem:State` / `Rem:Each` / `Rem:Act` / `Rem:Text` / `Rem:Icon` /
  `Rem:Label` read it (the Services' Errands rows do), and the bus topic
  `reminder` (key, active, up) says a change. Its users: Restock, New Mail,
  Repair Gear, Trainer (Modules/Reminders.lua, Modules/Restock.lua). The
  widget is built on first use, never before its login moment (8 s into
  the world) and nothing is checked in combat; with the player frame hidden
  it has its own place, Core's mover key `reminders` (Edit Layout shows a
  sample). The secure target button is set up only out of combat.
  Per-character state is a `keep` key (the registry entry above).
- **Escape closes it:** the shell's `escape = true` puts its frame name in
  `UISpecialFrames` (the configurator, the installer, the question dialog,
  the Restock List and, since the 0.15.0 audit, the copy window: area
  `copy`, built on its first open).
- **The installer is the second shell** (Core/InstallerWindow.lua over the
  engine in Core/Installer.lua): area "installer", always in the kit
  (`Kit.Areas` row `always = true`); the corner ring with the emblem and
  the plate on the rail carrying the step's title; ONE mover with no saved
  place (`save` a shared no-op: a drag moves it for the session, every open
  is centred; `group = "tool"`: never a plate in Edit Layout); the numbered steps from `W.NavRail` (switching setups takes
  rows from its pool), a `W.Pager` page per step made on its first show, on
  the calm ground with ONE `W.Panel` for the body (2e; the pager its child,
  so the pages lie over it), `W.Header` for a group's heading, `W.Card` for
  the setups; Escape and close
  off while the Keep countdown runs. It changes settings only through the
  engine, in one `MelloUI:Batch`, and never sets the UI scale.
- **The window rules hold for it too:** the title ON the plate in
  `Kit:TitleFont` (2c), the ring never empty, text-dense areas on the inner
  panel (2e), nothing built at login if it is rarely opened (2f), one
  background per surface.
