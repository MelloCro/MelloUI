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
   rail junctions).
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
| title bar | `tabs/top` in the `title` look (rune caps, F's red) at 1.5 x the bar's height, the outer rail's WHOLE width (the window plus the outset each side), standing ON the outer rail: its bottom on the band's top edge (`Kit:OuterRailTop`, above the window's top edge), the title text centred on it (user, 2026-09-21: the header sits on top of the thick border of every window) |
| close button | `window/close` states on the button's normal texture rect |
| portrait icon in the ring (user, 2026-09-21) | the game's portrait is fitted to the CLASS MEDALLION's size in the character window's ring (0.759 x the ring, `Kit:FitPortrait`, aspect kept). If the icon then does not cover the opening (a shield, a non-round asset), it gets the dark grey round background behind it (`Kit:RingDisc`) at that same medallion size — never a loose icon over the page. Two outcomes only: scaled to the medallion, or scaled to the medallion on the disc |
| portrait corner | `window/portrait_ring` square on the ring's rect, the class medallion inside it (plain variant, 0.759 x ring) |
| backdrops (pane pictures, model landscape) | `tiles/stone` tiled at native scale, no edge of their own |
| dividers / lines | `window/single_l` edge for the pane divider; `window/divider` strip for scroll lines; natural size + `widthFrac` for a line inside a glow atlas |
| headers / plates | `lists/header` for titles and level plates; `lists/plate` plain (gemless, pitch-fitted) for rows and row highlights; `lists/catplate` closed for category headers (no chevron; the game's glyph stays) |
| TALL list rows (50 px and more: the LFG who / browse lists) | R3 (user, 2026-09-21): a single-rail card with stone under the row (`frame` with `hover` / `checkedTint`), its iron lit gold while selected — the plate's rails get fat when stretched that tall |
| equipment / icon slots | `buttons/slot` rim UNDER the button, sized by `gemSpan` to the slot pitch so neighbours share a gem |
| side tabs | `buttons/slot` gold rim at rest (pick I) + the same rim additively as the selected / hover glow |
| bottom / top tabs (`PanelTabButtonTemplate`, `TabSystemTemplate`), every window | **TB6** (user, 2026-09-21, `kit_raw/bottomtab_catalog.png`; was T1, the `tabs/top` plate): the single rail with the stone card on the tab's rect, its iron lit gold while open, brighter on hover; the tab's text held centred on the card (the game bobs it on select) — `Kit:SkinPanelTab` |
| check boxes, everywhere | `buttons/checkbox` off / on / hover — CONSISTENCY (user, 2026-09-21): every check box, expand / collapse glyph and pane toggle in a window is the kit's, none stay the game's |
| expand / collapse glyphs (+ / -), sub-header toggles | `buttons/plus` / `buttons/minus` plates on the glyph's rect, switched with the atlas the game puts there (`Kit:StateIconReps`) |
| pane toggles (page arrows) | `buttons/arrow_left` / `_right` at the button's height |
| scroll bars (`MinimalScrollBar`) | THE scroll bar, T2 / H1 / S1: `bars/trough_v` track, `lists/scrollthumb` gem-slab thumb stretching with the content, `buttons/arrow_up` / `_down` steppers at natural size |
| progress bars (`ColoredProgressBar`) | P1: `bars/frame` bracket with the trough in its opening, the game's tinted fill BEHIND it on the bracket's whole height (its mask sized the same) |
| picture cards (a card whose background is a painting) | `picture` kind: the painted panel cropped to the card's aspect (crop 1 = bottom), its `_grey` twin while the game marks it missing / inactive, the single rail 1.6 over it (pick F) |
| cards without a painting | single rail 1.6 + stone body (pick A) |
| search / edit boxes | `inputs/edit` plate (S1), focused while typing; too narrow for its caps = middle only |
| dropdowns | `inputs/dropdown` plate (D1), hover from the button |
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
| MelloUI's configurator (user, 2026-09-21/22) | outer double rail, title plate fitted to 20 px, page stone; ST5 L1 box under the icon strip with SI1 rims on 57 px icons and names under them; CA1 TB6 tabs; L1 section boxes; CR4 rows (alternating faint bands, plate on hover only); SH3 sub-headings on the header plate; kit check boxes, SL1 slider, B1 / D1 by the sweep; CT2 tiles |
| the bag windows (user, 2026-09-21) | the flat window shell as any window; R1 rims to the grid's pitch with icons filling them and stone in empty slots; the game's quality border kept INSIDE the rim (the rim untinted — the bags differ from the windows' item slots here); the money strip on `lists/header` (B2), raised above the rims; search S1, sort K2 |
| HUD action bars, micro menu, bag bar, status bars (user, 2026-09-21) | R1 rims to the pitch with the icon filling the opening (empty: stone), the bars' frame art faded (under the rims), gryphons → `deco/rail_cap` orbs behind every bar (X2), page arrows hidden, micro buttons on the cog plate with the game's glyphs (M1), XP / rep bars P1 with the caps outside and `bars/tick` on the segments |
| HUD compact raid frames (user, 2026-09-21) | F1 G1: the single rail at 0.8 with stone as regions of the frame (rails above the fills, under the icons); the group border on the single rail 1.6; the totem borders → round rims; selection edge and aggro glow the game's |
| HUD cast bars (user, 2026-09-21) | C1 T1: `bars/castbar` with the game's bar as its opening and the caps outside, the bar narrowed by the arms so it reads the game's width; `lists/header` on the 12 px under the standalone bar; all FX faded and their animations stopped |
| HUD unit frames (player / target / focus / ToT / pet; user, 2026-09-21) | B3 R1 L1 N3: the frame's one picture faded; `window/portrait_ring` with its opening on the portrait (the portrait at the medallion size, 2b); the P1 bracket on each bar, ring side capless, far cap grown outward, the fill on the whole rect; the bars END on the ring's round body 2 px under it (never deeper: the fill must be readable to its end) and the ring's own pixels are drawn once more over their ends (`RingCover`); `buttons/orb` under the level / PvP circle; the `tabs/top` title plate on the name band with the name centred on it. Party frames the same (Round 3, done): the ring and plate at BACKGROUND under the name (the party picture is drawn above its portrait), the plate centred over the health bar at the frame's proportion × 1.2, wide enough for its rune caps |

A new element type = a new catalogue for the user to pick from
(`UITest/tools/*_catalog.py` -> `kit_raw/*_catalog.png`, lettered options at the
game's size), then the pick recorded here and in KIT-MAPPING. Never choose a
look for a new element type silently.

## 2c. MANDATORY: the title plate stands on the outer border (user, 2026-09-21)

Every window's title plate (the `TitleBar` rule, `onRail`) is placed the same
way, by the rule itself — never per window:

1. Its BOTTOM sits on the outer rail's top edge (`Kit:OuterRailTop()`: the
   outset less the rail piece's box top, above the window's top edge) — the
   header stands on top of the thick border, not inside the window.
2. It spans the outer rail's WHOLE width: the window's width plus the rail's
   outward growth (`Kit:OuterRailOutset()`) on each side, anchored to the
   window's top corners, its rune caps ending at the border's outer edges.
3. The window's title text is centred on the plate and put back on disable.

Check on every window: the plate's bottom touches the border's top, the caps
reach the border's ends, the title sits on the plate.

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
  colour picker, calendar, clock and stopwatch, channels, help. A NEW window is checked against
  this before it is handed over.
- Before handing a window over: look at it and ask "is there small text on
  brown?" — if yes, it needs the panel.

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
- A window that relied on the kit's shell for its Unlock-the-Windows mover
  names its frames in its module's registry entry, `window = { frames = {
  "FrameName" }, plainGrab = true }`, so it is movable from login (UI
  Modifications builds its plain-grab list from the registry since wave 3;
  nothing is added there by hand).
- Check with /melloperf: a new window adds no kit pieces at login
  (`/run print(#MelloUI.Kit.repList)` before and after), and no handler of it
  runs while it is closed.

## 2b. MANDATORY for a window's portrait icon (user, 2026-09-21)

The portrait inside the ring is always brought to the class medallion's size
of the character window (0.759 x the ring, `Kit:FitPortrait`, aspect kept).
Then check the opening: if the icon does not cover it (the Legacy shield,
any asset that is not a full round picture), add the dark grey round
background behind it (`Kit:RingDisc`) — the icon stays at the medallion size
on the disc. Either the icon fills the ring, or it sits on the disc; nothing
else. The professions window's round icons are the first case; the Legacy
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
  caps must show (the party name plate) gets a rect at least that wide, or
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
window MelloUI makes itself (the configurator, the installer, Dynamic UI
Modification, the Quest List beside the world map, the Quest Tracker under the
minimap, the whisper popups, the Voice Over overlay, the Route arrow, the
Services bar, the copy window) keeps every rule above and uses the SAME shared
systems as the game's windows. It never carries its own copy of one; the
ratchet (`python Tools/lint/check_panels.py`, run by the Lint workflow) fails
when a copy is added and names the system to use.

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
- **Its registry entry.** Its module's `MelloUI:RegisterModule` carries what
  the configurator and UI Modifications show (Core.lua's header has the
  shape): `window = { label, desc, tab = "Windows" | "HUD", order, switch,
  frames, plainGrab, addon, firstOpen }` gives it a row on UI Modifications'
  Windows or HUD tab with nothing edited there or in Config; `area = { key,
  follows }`; `group` (one of "The look", "Quests and travel", "Chat and
  sound", "Frames and bars"); `icon` and `flavour` for its configurator tile;
  a feature folded under UI Modifications is `tweak = { label, desc, order,
  off, always }`. A field of the wrong type is reported, never fatal.
- **Its place: `MelloUI:RegisterMover` (Core).** `MelloUI:RegisterMover(frame,
  handle, { key, anchor, default, save, reset, min, max, base, with,
  plainDrag })`: one store (UI Modifications' `positions`, kept whether that
  module is on or off, so profiles, share strings and the macro backup carry
  it), and Unlock the Windows, Reset positions and the UI-scale put-back
  reach the window. `plainDrag = "always"` drags it with UI Modifications
  off. Set the frame's own OnShow / OnHide BEFORE registering, and never
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
  "scale", "editmode", "shell", "palette", "column" (Core.lua lists what each
  carries). Never `hooksecurefunc(MelloUI, ...)` or `hooksecurefunc(Kit, ...)`
  on MelloUI's own functions: such a hook runs for every setting of every
  module and can never be taken off. Many settings at once go through
  `MelloUI:Batch(fn)` (one Fire per key, one backup). A UI-scale change:
  `Kit:OnUIScaleChanged(fn)`.
- **Its text on parchment: `QI.Surface`.** A window with a parchment sheet
  registers `QI.Surface(area, { on = fn, sheet = true, skip = fn, roots = fn
  })` (`sheet = true`: the inks set for the kit's darker sheet);
  `Kit:SetParchment(area)` refreshes it. Strings are never recoloured by hand
  (the parchment ink rule).
- **Motion: `MelloUI.Anim`.** `Anim:To / From / FadeIn / FadeOut / Pop` for a
  tween, `Anim:PlayGroup(group, settle)` / `Anim:StopGroup(group)` for an
  AnimationGroup, so Reduce Motion is honoured. Never a raw group's `:Play()`
  or an OnUpdate tween of its own.
- **Colours: the palette only.** `MelloUI.Palette.<role>` (Core.lua) and
  `MelloUI:PaletteCode(role)` for text codes, read when drawn (more palettes
  are planned). No number literals, and no `MelloUI.Palette and ... or { ...
  }` fallback: the palette is defined in Core.lua, which loads first.
- **Sounds: `MelloUI:PlayUISound(kind)` (Core).** Never call `PlaySound`
  directly, whatever its argument. The soft clicks "page", "tab", "check_on", "check_off"; the game's
  own "option_on", "option_off", "menu_open", "menu_close", "menu_button",
  "window_open", "window_close", "tick", "waypoint_set", "waypoint_clear". A
  new sound is one row of Core's SOUNDS table; Custom Sounds is asked first
  and its PlaySound hook swaps a game kit as it does any game click.
- **Secret values: `MelloUI.Safe`.** Bound plainly at load, `local Secret =
  MelloUI.Safe.IsSecret` (also Value, Number, Text, Call). No helper of its
  own and no stand-in: a test world that loads a file without Core runs
  Core's Safe block itself.
- **Later, not a timer: `Kit:NextFrame(key, fn)`**, fn made once per key.
- **Escape closes it:** its frame name in `UISpecialFrames` (the configurator,
  the copy window and Dynamic UI do so today; the shared own-window shell,
  audit rank 8, will own this).
- **The window rules hold for it too:** the title ON the plate in
  `Kit:TitleFont` (2c), the ring never empty, text-dense areas on the inner
  panel (2e), nothing built at login if it is rarely opened (2f), one
  background per surface.
