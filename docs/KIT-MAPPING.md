# Kit mapping: which kit piece replaces which game art

The rule (HANDOVER.md 3.9): a kit skin **replaces** the game's art one to one and **adds nothing**. A panel
module never chooses a piece; it hands the game region to `MelloUI.Kit:Replace(region, opts)` and the
library looks the piece up in `Kit.Replacements` (Modules/Kit.lua), keyed by the art's **atlas name** (or a
texture file's base name, or a name of ours for art without an atlas). The piece is built on the region's
own rectangle, sized to it, as a child of the region's frame, and the original is faded (alpha 0, kept by
a post-hook). **Draw order is part of the element:** before mapping, check the art's frame strata, frame level
and draw layer and what the game draws over it (icons, quality borders, text); the piece goes at the same place
in the stack (`under` for a slot picture beneath the icon, `level` relative to the parent for frames and strips).
This file is the readable copy of that table: **change both together.**

**Borders are single-line and one weight** (rules, 2026-09-21): every `frame` and `edge` mapping uses the single-rail family `window/single_*` (`Kit.framePrefix`) at ONE scale, `Kit.frameScale` = 1.6 (the user's pick B1), unless the user states otherwise for a specific element; no rule carries its own weight. The window's double-rail edge (`window/frame_*`) is used only for the OUTER border of a window (`NineSlicePanelTemplate`), with its painted gem corners.

**States share one rectangle:** the kit normaliser (`normalize.py`) resizes every state of a piece onto the first state's opaque box, because the game's hover and selection cover the same rectangle; a state must never change a piece's size.

## Kinds

| kind | what the library builds on the rect |
|---|---|
| `frame` | an inner nine-slice from the single-rail family `window/single_*` (default; `prefix = "window/frame"` only when the double rail is asked for); mitred corners, stone body; `scale` defaults to `Kit.frameScale` (one weight per window; a rule sets its own only when the user asks); `body = false` for edges only; `open = "l"` (or r/t/b) leaves a side without edge or corners: attached borders; `checkedTint` colours the iron when the module's `checked()` says so |
| `edge` | one repeatable edge tile (`piece`) on the rect: divider lines |
| `strip` | a cap / mid / cap strip (`base`): its OPAQUE part (the piece's `box`, recorded by the builder) is fitted to the rect's **height** (or kept at the kit's natural size with `natural`, spanning `widthFrac` of the rect, for lines inside glow atlases) — or to `opts.fitHeight` / `rep:SetFitHeight(h)` (a row pitch) — and centred on the rect's centre line, since the art is not centred in its canvas; with a first `state` |
| `slot` | the `buttons/slot` rim on a button, over the game's icon; states hover / pressed / checked (`checked` = a function of the module's choosing); `rest` fixes the look and `glow` adds the rim additively for selected / hover |
| `state` | a state texture on a button (`base`), e.g. the close button; `rect = "normal"` takes the button's normal texture rect |
| `texture` | one piece (`piece`); `square` sizes it to the rect's shorter side and centres it on `opts.center` |
| `tile` | a repeatable tile (`piece`) filling the rect at its native scale |

## The table

Window frames and their parts

| game art (atlas / key) | where it is | kit piece |
|---|---|---|
| `NineSlicePanelTemplate` (the frame's `NineSlice` + `Bg`) | every PortraitFrame / ButtonFrame window | `frame` from the window sheet as painted (user, 2026-09-21: "ideal on every window as an outer border"): the DOUBLE rail `window/frame_*` at 1.0 with the painted gem corners `window/frame_gem_*` over the edges (`corners = "gem"`; `Tools/make_gem_corners.py` scales the corners to the edge's rail and fades their arm ends into it; their `overhang` puts the gem 12 px past the frame's corner). The frame is `outset` 42 px: it grows OUTWARD from the window (the rails lie outside it, only the 6 px inner bevel on its edge), so the wider border does not eat into the window. A window whose corner is a portrait ring passes `skip = "tl"`. This is the one border the single-line rule does not cover. |
| `TitleBar` | window title bar: in this client `TitleContainer` holds only the text, no background art (`/cpdump title`), so this is an AGREED ADDITION on the container's rect, under the text (`noFade`); where a client does paint a title background, that texture is what gets replaced | `strip tabs/top` in a `title` look: the `open` pieces (rune caps, red plate; catalogue pick **H**) with the red re-tinted to the red button's (F: mean RGB 111/2/2 instead of 140/10/9), fitted to 1.5 x the bar's 20 px (`heightScale`), the width unchanged. **H3** (user, 2026-09-21, `kit_raw/titlemid_catalog.png`): the MIDDLE is the open tab's brighter red (`tabs/top_mid_open`) on the title caps — a library alias (`STRIP_ALIAS` in Kit.lua, `Kit:StripPieceName` resolves it) so every title plate follows (window titles, the minimap band, the tracker header, the unit frame name bands) |
| `_UI-Frame-TopTileStreaks` | the band under the title bar | `frame` (single rail, `Kit.frameScale`) |
| `UI-Frame-PortraitMetal-CornerTopLeft` | the nine-slice's portrait corner (the ring) | `texture window/portrait_ring`, square, centred on the portrait |
| `RedButton-Exit` (+ pressed / highlight / disabled faded) | close buttons | `state window/close` on the normal texture's rect |

Inset frames and backdrops

| game art | where | kit piece |
|---|---|---|
| `common-insideframe`, `-2x` | the stats scroll box `Border`, any inset panel | `frame` (single rail, `Kit.frameScale`) |
| `UI-Character-Info-General-BG` | left pane backdrop picture (no rail of its own at the pane seam) | `tile tiles/stone`, no edges |
| `UI-Character-Info-Stat-BG` | right pane backdrop picture (no rail of its own at the pane seam) | `tile tiles/stone`, no edges |
| `UI-Character-Info-Stat-StoneBG`, `-StoneBG2` | the stone plate under the level line (paper doll only; follows the game's visibility) | `frame` (single rail, `Kit.frameScale`) |
| `common-framedivider` | the vertical line between the panes (unnamed child of `RightPaneHost`) | `edge window/single_l` (`Kit.frameScale`) |

Lines, plates and list rows

| game art | where | kit piece |
|---|---|---|
| `UI-Character-Info-ScrollLine` | the divider under a side pane's title (reputation, currency, skills, PvP; hidden with `SetEmpty`) | `strip window/divider` |
| `UI-Character-Info-ScrollLine-Long` | the lines above and below a scroll box's rows (reputation, currency, skills, statistics) | `strip window/divider` |
| `UI-Character-Info-Honor-LevelBG` | the line under the PvP tab's rank name: a thin line inside a large soft-glow atlas, whose box says nothing about the line | `strip window/divider` at its NATURAL kit size (`natural`), centred on the atlas, spanning half its width (`widthFrac` 0.5) |
| `UI-Character-Info-Title` | stat category headers | `strip lists/header` |
| `UI-Character-Info-ItemLevel-Bounce` | the "Level N Class" plate | `strip lists/header` |
| `UI-Character-Info-Line-Bounce`, `-Bounce2` | stat rows: a plain line in the game, no diamonds; it backs every other row (the plate shows only where the game's does) | `strip lists/plate` plain / hover: the GEMLESS plate (`Tools/make_plain_plate.py` closes the row mid with its own rail; no gems, unlike `lists/row`), fitted to the rows' PITCH (`fitHeight`), so stacked plates butt exactly |
| `common-button-list-collapseExpand` (+ its additive hover copy faded) | reputation / currency / skills / statistics category headers; the game's art is the same collapsed or open (only the +/- glyph changes) and prints its name at the left edge | `strip lists/catplate` (`closed` look always): the category mid closed with its own rail (`make_plain_plate.py`), so cap and mid are ONE texture (no stitch), no chevron under the game's text, no leftover label. The gemmed / glyphed `lists/category` is not used. |
| `charactercreate-customize-dropdown-linemouseover-middle` (+ `-side` ×2 faded) | reputation / currency / skills / statistics entry highlight (`Content.BackgroundHighlight`) | `strip lists/plate` (the GEMLESS plate; the gemmed `lists/row` overshoots a list row and its gems get clipped) on the highlight's rect; shown under the game's conditions (`IsSelected`, `IsMouseOver`, `IsAtWar`), selected / hover / plain |

Backdrops without a frame

| game art | where | kit piece |
|---|---|---|
| `ModelSceneBackground` (the four race-landscape quadrants of `CharacterModelScene`; the `RaceBG-Overlay` vignette stays the game's, on top) | behind the character model | `tile tiles/stone` on the quadrants' union, at the scene's level — which is ABOVE the pane host's backdrop, exactly as the landscape is in the default (the host frame stays hidden under it there too) |

The equipment manager (`PaperDollFrame.EquipmentManagerPane`, shown by the sidebar tab)

| game art | where | kit piece |
|---|---|---|
| `common-insideframe` (`Border`) | the pane's inset | the table's row (single rail) |
| `UI-Character-Info-OutfitCard` / `-Hover` / `-Selected` (`HighlightBar` / `SelectedBar` shown and hidden by the game) | outfit cards, 152 x 49 | `strip lists/plate` plain / hover / selected as regions of the card (BACKGROUND 0 / 1 / 2), the bars following the game's Show / Hide |
| `_128-RedButton-Center` (`EquipSet`, `SaveSet`: the same three-slice as the crafting page's Create) | Equip / Save, 99 x 28 | the table's row (B1) |
| `common-button-tertiary-normal` / `-hover` / `-pressed` / `-disabled` (`NewSet.StateTexture`, re-atlased in `OnButtonStateChanged`) | New Set, 180 x 34 | `strip buttons/redbtn` (B1) from the button's state, the game's + icon and text on top |
| `MinimalScrollBar` | the outfit list | T2 / H1 / S1 |

## The spell book (Modules/SpellBookPanel.lua)

User's picks, 2026-09-21 (`kit_raw/spellbook_catalog.png`: P2 C1 H3 K4 T1). The window frame, portrait ring, title, close, search boxes and the small dropdown arrows are the table's existing rows. The TALENTS page stays the game's (class paintings, nodes, tree headers, dividers, the unspent box, Apply) until the user's per-class art arrives; only its search box, dropdown arrow and top tabs are skinned.

| game art | where | kit piece |
|---|---|---|
| `spellbook-Page-Right-C60` / `-Left-` (`BookBGHalved` / `BookBGLeft` / `BookBGRight`, the game shows the halved one minimized, the pair maximized) | the book page, 806 x 702 | the user's parchment page painting `backdrops/page_parchment` (parchmentnew.png, 2026-09-21, painted at the page's 1.15 aspect, stored at 1024 px), `picture` cropped from the middle, one level UNDER the SpellBookFrame (which sits at level 100, above the window's skin and below its own controls); followers of the game's Show / Hide |
| `spellbook-Tab-Frame-C60` (+ `-Glow-` and the gradient, shown while selected) | the category tabs, 43 x 38 icon squares (`TabSystemButtonArtTemplate` in square mode) | **C1**: `slot buttons/slot` as a SQUARE around the icon the game draws (the game re-anchors and resizes that icon on tab changes: it is left alone, the square follows it and is sized so the icon fills the rim's opening), gold (checked) while `tab.isSelected` |
| `spellbook-list-backplate` | the header's backplate behind "General" | **H3**: faded (the text on the page) |
| `spellbook-divider` | the 652 px line under the header | **H3**: `strip window/divider` |
| `spellbook-item-backplate` | a spell card, 256 x 64 | **K4** (re-picked from K1 on sight): faded — the rim and the text on the page |
| `spellbook-item-iconframe` / `-inactive` / `-passive` / `-passive-inactive`, and `talents-node-circle-gray` (what this client puts on passives) — the game re-atlases `Button.Border` per spell | the icon frame, 52 x 48 (active) / 40 x 40 (passive) | `slot buttons/slot` for the square (active) frames, `buttons/roundslot` for the passives' (their icons are round), one rim per atlas seen (`Kit:StateIconReps`), every rim on the game's active frame rect (52 x 48; its passive frame is only 40 px) at 1.0 (the user tried 1.15 and came back); the icon is NOT touched (user, 2026-09-21: the game's 36 px); the border shadow and hover glow faded; the sheen and unassigned-glow animations stay the game's |
| `uiframe-tab-left` / `-center` / `-right` and `uiframe-activetab-*` (`TabSystemButtonArtTemplate`: the game shows the plain set or the active set in `SetTabSelected`) | the top tab system (Spellbook / Specialization / Talents; Talents' Primary / Secondary), 156 x 32 | **TB6** (user, 2026-09-21; was T1): `frame` — the single rail with the stone card on the tab's rect, the plain set at level 0 with a hover lift, the active set lit gold (`lit`), each following the game's choice; `Kit:SkinPanelTab` holds the tab's text centred |
| `common-dropdown-a-button` | the settings / search-options arrow, 27 x 27 | `state buttons/cog` under the game's arrow (K2) |
| `RedButton-Expand` / `-Condense` | maximize / minimize | `state buttons/arrow_up` / `_down` on the button's normal texture; followers |
| `UI-SpellbookIcon-PrevPage-Up` / `-NextPage-Up` | the paging arrows, 32 x 32 | the table's arrows at the button's height |

Agreed additions (the only pieces without a game element under them)

| key | where | kit piece |
|---|---|---|
| `ViewportFrame` | around `CharacterModelScene` (the character viewport), over its backdrop | `frame` from the SINGLE-rail family `window/single_*` at 1.6 (catalogue pick **B1**, `kit_raw/viewport_catalog.png`), edges only, OPEN on the right where it meets the pane divider (one rail at the seam, as in the default), one level above the scene. The window's own edge is a double rail; `Tools/make_single_rail.py` makes the single one from the bar frame's rail. The user asked for this frame explicitly; it is passed with `noFade` and is the documented exception to rule 9. |
| `RailJoint` | on the junctions of rails (T and +), where the game paints nothing: the pane divider's top under the title plate, the stats box's top edge (the inset's top rail and the stone plate's bottom rail both meet the divider there) and its bottom on the window's bottom rail | `texture inputs/slider_thumb_normal` at the kit's natural size (the gem in a dark bezel: catalogue pick **K**, `kit_raw/joint_catalog.png`, chosen for EVERY junction), centred on the crossing by `Kit:Joint` — the rail's centre line comes from the piece's box (`Kit:RailInset`), never from a guessed offset. Lives on the divider's own frame (level 505 in the game's layout) so it collapses with it; the stats one shows with its box. User's pick, 2026-09-21. |

Slots and tabs

| game art | where | kit piece |
|---|---|---|
| `UI-Character-Info-GearSlot` (inside the 1 × 1 `BorderFrame`) | equipment slot border; the game's pictures overlap so neighbouring slots SHARE their corner diamonds | `slot` rim centred on the picture, sized from the slot pitch (`gemSpan` 97/135 × 92/130: the rim's gem centres land half a pitch from the slot centre, so neighbours share a gem exactly as the game does), drawn UNDER the button (`under`) like the game's picture, so the icon and its quality border sit on top of the rim |
| `common-sidetab` (`Background`, gold on every tab) + `SelectedTexture` + `TabGlow` (additive) + `HighlightTexture` | the window's side tabs | `slot` gemmed rim, resting in its gold `checked` look on every tab (catalogue pick **I**), as the game's background is; the selected tab gets the same rim additively at 0.7 (its `SelectedTexture` + `TabGlow`), a hovered tab at 0.35 (its `HighlightTexture`). The attached bracket (`frame` with `open`) stays available for tabs that should read as attached.; the tab's icon (drawn by the game 3 px off-centre, 50 px, clipped by its own mask that is faded with the art) is fitted into the rim's opening (`icon`), re-fitted after the game's press / release re-anchoring |

Small controls

| game art | where | kit piece |
|---|---|---|
| `checkbox-minimal` / `checkmark-minimal` | check boxes | `state buttons/checkbox` (off / on / hover) |
| `common-button-list-plus` / `-minus` (a header's `StateIcon`, re-atlased with the collapse state; the recipe list's `CollapseButton.Icon` likewise) | category headers in every list (reputation, skills, currency, statistics, recipes) | `state buttons/plus` / `buttons/minus` at natural size on the glyph's rect — one replacement per atlas the glyph has shown, the current one visible (`Kit:StateIconReps`), refreshed on the row's initialisation |
| `campaign_headericon_closed` / `_open` (+ `pressed` faded) | a reputation sub-header's toggle button (`RefreshIcon`) | `state buttons/plus` / `buttons/minus` on the button's normal texture, the same per-atlas switching |
| `UI-SpellbookIcon-PrevPage-Up` / `-NextPage-Up` (file textures the game swaps in `UpdateRightPaneToggleButton`) | `CharacterFrame.RightPaneToggleButton`, the arrow that folds the stats pane away: left while open, right while collapsed | `state buttons/arrow_left` / `_right` at the button's height, one per texture, the current one shown (`Kit:StateIconReps` after the game's update) |

Scroll bars and progress bars (user's picks, 2026-09-21: `kit_raw/scroll_catalog.png`, `bar_catalog.png`)

**Rule: T2 / H1 / S1 is THE scroll bar** — every `MinimalScrollBar` gets exactly this look, nothing else is used for a scroll bar.

**Rule: a progress bar's fill sits BEHIND the bracket** (user, 2026-09-21) — in every skinned bar (skills, reputation, the detail panes, any bar mapped later) the game's fill spans the bracket's WHOLE height (its rows from the top rail's outer edge to the bottom rail's, `into = 1`) and a little under the caps' gems; its Mask is sized the same, since the mask clips the fill to its own height, and the bracket art is drawn over it so the rails and gem bezels cover the fill's edges. The bracket and trough are therefore REGIONS of the bar's own frame (trough in the replaced background's layer, bracket in BORDER above the game's fill and below its ARTWORK text), never a child frame under it.

| game art | where | kit piece |
|---|---|---|
| `minimal-scrollbar-track-middle` (+ `-track-top` / `-bottom` faded) | `MinimalScrollBar.Track` (8 px wide): the stats boxes, the reputation / skills / currency / statistics lists, the paper doll's title and equipment panes, the side panes' description | **T2**: `edge bars/trough_v` (the bar trough stood upright, `Tools/make_scroll_pieces.py`) on the whole Track, one level under it; the game shows / hides the bar and the track itself |
| `minimal-scrollbar-small-thumb-middle` (+ `-top` / `-bottom` faded; the `-over` / `-down` atlases the game swaps in are the same three regions) | `Track.Thumb`, an EventButton whose height follows the content | **H1**: `vstrip lists/scrollthumb` (cap_t / mid / cap_b cut from the painted thumb, normal = dark slab, hover = red slab, `make_scroll_pieces.py`) on the thumb's rect at 1.25 x its width, the state read from the button's `over` / `down` after `OnButtonStateChanged`; the gem caps shrink on a thumb shorter than both |
| `minimal-scrollbar-arrow-top` / `-bottom` (+ `-over` / `-down`) | `Back` / `Forward` stepper buttons, 17 x 11 | **S1**: `state buttons/arrow_up` / `arrow_down` at the kit's natural size (16 x 15) centred on the stepper's texture |
| `common-stat-bar-BG` | `ColoredProgressBarTemplate` (160 x 29): reputation and skill rows, the reputation detail's `StandingBar`, the skill detail's `RankBar` | **P1** at `heightScale` 0.85 (user, 2026-09-21: the borders 15 % smaller; the bracket centred on the bar, the fill fitted into its opening), and on the Reputation and Skills tabs (rows and both detail panes) the panel's `artScale` 0.85 on top (user, 2026-09-24: the border textures 15 % smaller again, in every Progress Bar Border look; the bracket ~0.72 of the bar's height, the fill in its smaller opening; a bar on another tab's pane keeps the rule's size): `bar bars/frame` — the hollow gem bracket fitted to the bar's height with `bars/trough` in its opening, as regions of the bar's frame: the trough in BACKGROUND, the bracket in BORDER above the game's `Fill` (tinted per standing) and below its `Text`. The fill and its `Mask` are moved onto the bracket's whole height (see the rule above); the fill's `SetAtlas` is post-hooked too, since the skill rows re-atlas it with the atlas size on every initialisation. `thicken` on the rule would make the bracket taller than the bar (tried at 50, reverted: the rows are 30 px apart) and `SetFillWidth` is post-hooked to scale the game's percent x width onto the opening's width; both are put back when the skin is off. This is the one place the game's fill geometry is touched: the opening is where the replaced background's bar was. |

## The professions window (Modules/ProfessionsPanel.lua)

Book page (user's picks, 2026-09-21: `kit_raw/card_catalog.png` A / F crop 1 / K1). The frame, portrait ring, title, close and the seven side tabs are the table's existing rows (`SidePanelTabButtonMixin:SetChecked` shows `SelectedTexture`: that is the tabs' checked state).

| game art | where | kit piece |
|---|---|---|
| `Profession-Background-Overview` (`ProfessionsFrame.Bg`) | the book page's backdrop behind the cards | `picture backdrops/page_stone` — the user's grey cracked-stone page with gothic pilasters at its sides (sheet c71f07ff, painted at the page's 1.17 aspect, stored at 1024 px wide), level 0. Tried and rejected before it: the kit's soft stone, `tiles/crackle`, a plain grey. |
| `Profession-overview-Card` (a primary card with no profession in it) | the two primary profession cards, 664 x 142 | **A**: `frame` — single rail 1.6 with the stone body, one level under the card |
| `Profession-overview-Card-Alchemy` … `-Blacksmithing`, `-Enchanting`, `-Engineering`, `-Herbalism`, `-Leatherworking`, `-Mining`, `-Skinning`, `-Tailoring` (the game re-atlases the card's `Background` per profession in `FormatProfession`) | a primary card with that profession | `picture cards/<profession>` (the user's banner sheets, 2026-09-21: the still-life at the right on stone; `Tools/cut_cards.py`), shown WHOLE at the card's height against its right edge (`fit = "right"`: the card is wider than the banner, so a crop would cut the still-life — user, 2026-09-21), the banner's own left stone columns mirrored across the rest of the card, the single rail over it. The panel keeps one replacement per atlas a card has shown and shows the one for its current atlas (`RefreshCard` after `FormatProfession`). |
| `Profession-overview-card-generic-Cooking` / `-Fishing` / `-FirstAid` | the three secondary cards, 225 x 275 | **F, crop 1**: `picture backdrops/profession_<name>` cropped to the card's aspect from the BOTTOM of the panel (the objects), the `_grey` twin while the card's `missingHeader` shows (not learned), the single-rail edges over it (`frame`); re-picked after the game's `FormatProfession` |
| `Profession-square-frame` (`IconTextureOverlay`, 48 x 48 over the 40 px icon) | the profession spell buttons on every card | `slot buttons/slot` on the overlay's rect, OVER the icon as the game's frame is |
| `Profession-ProgressBar-BG` (+ `Profession-ProgressBar-frame` faded) | the cards' rank bars (`ProfessionsRankBarTemplate`: full-width flipbook `Fill` revealed by the `Mask`'s width, the `Flare` at its end, all ARTWORK 1-3) | **P1**: `bar bars/frame` with the bracket's caps in ARTWORK 4 and its middle in ARTWORK 3 (both above the fill's ARTWORK 2; a strip's middle sits one sublevel under its caps) and the trough in BACKGROUND; the fill on the bracket's whole height, the mask's width post-hooked from ratio x bar width to ratio x opening width, the mask's HEIGHT untouched (resizing this mask blanks the fill in this client; its 18 px band sits centred in the bracket, the rails cover its edges); the Flare stays the game's |
| `Profession-button-red-crossmark` | the unlearn button | left as the game's (a glyph) |
| the portrait (`PortraitContainer.portrait`, set by `SetPortraitToAsset`: the professions side-tab icon on the book page, the profession's spell icon on a crafting tab) | the ring at the top-left | the user's round icons (sheets 4ea91585 / 4f78b4a9, `Tools/cut_icons.py`, 192 px cut and clipped to the circle, stored at 96 px for the 62 px portrait): `icons/professions` (crossed pick and hammer) on the book page, `icons/profession_<name>` on each tab, chosen by the profession's name; the game's last asset is put back on disable |

The tall colour panels `backdrops/profession_<profession>` (the 3 x 3 sheet) are cut and in the kit, not mapped yet: candidates for the crafting page's schematic backdrop.

Crafting page (user's picks, 2026-09-21: `kit_raw/controls_catalog.png` S1 D1 B1 N1 R1 O1 K2 L1 T1; the `/profdump` of the page, 135 regions, is the inventory)

| game art | where | kit piece |
|---|---|---|
| `Profession-Background-Template2` (the page's unnamed BACKGROUND texture) | the crafting page's backdrop | `picture backdrops/page_stone` (the same page stone as the book's), one level under the page |
| `Professions-background-summarylist` (`RecipeList.Background`) | the recipe list box, 304 x 517 | **L1**: `frame` — single rail 1.6, stone body |
| `common-search-border-middle` (+ `-left` / `-right` faded) | the recipe search box (192 x 20) and the quantity spinner's box (36 x 20; its second, file-based border set is faded too) | **S1 / N1**: `strip inputs/edit`, `focused` while the box has focus; a rect narrower than the two caps shows the middle alone (the spinner) |
| `common-dropdown-b-button` (`FilterDropdown.Background`) | the filter dropdown, 100 x 26 | **B6** (re-picked from the button catalogue, 2026-09-21): `frame` — single rail 1.6 with stone, one level under the button, its states a tint of the whole skin (hover 1.25, pressed 0.75, disabled 0.6) |
| `_128-RedButton-Center` / `-Center-Disabled` (+ `Left` / `Right` / the highlight faded) | Create and Create All, 80 / 104 x 28 | **B1**: `strip buttons/redbtn` normal / hover / pressed / disabled from the button, at 0.8 x the button's height (the 22 px of the spinner's arrows: level with them) with the gem caps reaching 0.35 of their width past the button's ends (`capOverhang`); the cap facing the count spinner is dropped (`dropCap`: Create All's right, Create's left) and closed with the plate's gemless END piece (`buttons/redbtn_end_l/r_<state>`, `Tools/make_plain_plate.py`); the buttons are re-anchored FLUSH to the spinner's - / + after the game's `SetControlAnchors`, one continuous bar (the user's mockup) (the user's layout; put back on disable), as the game's own Left / Right pieces sit outside its Center — at 28 px the two caps would otherwise cover the whole 80 px button |
| `UI-SpellbookIcon-PrevPage-Up` / `-NextPage-Up` (file textures; the key is passed by the panel) | the spinner's - / + buttons, 23 x 22 | **N1**: `state buttons/arrow_left` / `_right` at natural size |
| `Professions-Slot-Frame` (`IconBorder`, 48 x 48 over a 39 px icon; `Professions-Slot-bg` under the icon stays) | reagent slots (pooled by the schematic form: skinned once each after `SchematicForm:Init`) | **R1**: `slot buttons/slot` over the icon |
| `auctionhouse-itemicon-border-white` (`OutputIcon.IconBorder`, quality-coloured, + its highlight copy faded) | the output icon, 68 x 68 | **O2** (changed from O1 on sight): `slot buttons/roundslot` over the icon — the icon is round — tinted with the border's vertex colour (post-hook on `SetVertexColor`, re-applied after hover), shown / hidden with the border |
| `common-button-tertiary-square-normal` (`LinkButton.Background`) | the chat-link button, 23 x 23 | **K2**: `state buttons/cog` at natural size in BACKGROUND, the game's chain-link icon on top |
| `Professions_Recipe_Hover` (a HIGHLIGHT-layer texture the engine shows on mouse-over) / `Professions_Recipe_Active` (shown / hidden by the game) | recipe rows | `strip lists/plate` hover / selected, one level under the row (under its text); shown on the row's enter / leave, and after the game's Show / Hide of the selected overlay |
| `common-button-list-collapseExpand` (unnamed ARTWORK texture + additive HIGHLIGHT copy) | category headers (`ListHeaderVisualTemplate`) | the catplate row of the table |
| `Profession-background-card-<Profession>` (`SchematicForm.Background`, re-atlased in `ProfessionsCraftingPageMixin:Refresh`, hidden in the minimized view) | the schematic backdrop, 360 x 484 | **T1**: `picture backdrops/profession_<profession>` (the 3 x 3 colour sheet: the same 0.744 aspect) with the single rail on the same holder (`frame`), one level under the form — the form sits at the page's own level, so a deeper level fell under the page's backdrop (the video showed page stone where the panel should be); the form's `common-insideframe` texture is faded with it. One replacement per atlas seen, the current one shown. `-Cooking` / `-Fishing` / `-FirstAid` use `backdrops/schematic_<name>`: the user's tall strips (sheet 3d259005) cut at the schematic's aspect on the band with the most colour (the still-life), stored 1:1 like the primaries' panels. |
| `checkbox-minimal` | Track Recipe | the table's row |
| `Professions-skillbar-bg` (+ `-frame` faded) | the crafting page's rank bar | P1, as the book's bars (`Profession-ProgressBar-*`); the same `SkinRankBar` |
| `MinimalScrollBar` | the recipe list | T2 / H1 / S1, via `Kit:SkinScrollBarsIn` |
| left as the game's | the skill-up arrows, the favourite star, the chain-link icon, `Professions-Slot-bg` under a reagent's icon |

## Shared controls met in the legacy, quest log and guild windows (2026-09-21)

Helpers in `Modules/Kit.lua` (`Kit:SkinWindowShell`, `SkinSideTab`, `SkinSearchBox`, `SkinRedButton`,
`SkinCheckButton`, `SkinCollapseButton`, `SkinStatusBar`, `RimRect`, `FitPortrait`, `HookScrollBoxRows`,
`DumpWindow`) carry the code the first three panels had inline; the new panels are thin.
`Kit:RimRect` sizes a rim for an icon the game rings thinly (a masked round icon): the icon's edge runs under
the MIDDLE of the bezel (`into` 0.5), so a 67 px tree icon gets an 84 px rim, a 50 px challenge icon 63, a 64 px
reward icon 82 — the game's own ring sizes, give or take (user, 2026-09-21: the full-opening rims overlapped).

| game art | element | kit piece |
|---|---|---|
| `UI-Panel-Button-Up` (keyed by hand) | `UIPanelButtonTemplate` (Left / Middle / Right file pieces: Apply, Abandon, Share, Track, Back, Guild Control, ...) | B1: `strip buttons/redbtn` as a region of the button at 0.8 x its height, caps 0.35 past its ends — the 128-RedButton rule; via `Kit:SkinRedButton` |
| `UI-CheckBox-Up` (keyed by hand) | the classic check box (`UICheckButtonTemplate`) | the kit's check box, as `checkbox-minimal`; `Kit:SkinCheckButton` |
| `questlog-icon-ticksquare` | the quest log's tracking tick (a Frame: tick square, a CheckMark the game shows / hides, a hover copy) | the kit's check box, `checked` read from the CheckMark's visibility |
| `common-dropdown-textholder` (+ `common-dropdown-a-button` arrow faded) | a text dropdown (`WowStyle1DropdownTemplate`) | D1: `strip inputs/dropdown` on the button, hover from it |
| `ui-journeys-delve-arrow-small-left` / `-right` | a reward track's scroll arrows | `buttons/arrow_left` / `_right` natural |
| `128-redbutton-plus` / `-minus` | a card's expand glyph | `buttons/plus` / `minus` natural, one per atlas seen |
| `UI-Background-Rock` (keyed by hand) | `ButtonFrameTemplate`'s rock background, a column display's band | the page stone as a REGION of the frame (`picture`, `owner`) |
| `UI-Background-Marble` (keyed by hand) | the marble strip under a list's scroll bar | faded (the trough is the bar's) |

**Mechanics added:** the `picture` kind takes `owner = true`: the picture is a region of the replaced texture's
frame in that texture's layer / sublevel — a page backdrop under the page's own children whatever their levels,
with no holder and so no level tie (the legacy pages sit at level 100 with children at 800; the character /
professions holders at ±1 stay as they are). `Kit:SkinStatusBar` is P1 for a StatusBar whose bracket art is one
of its own textures: bracket and trough become regions of the bar on the background's rect, the StatusBar itself
is moved into the opening (its fill spans the bracket's height behind the rails), put back on disable.

## The legacy window (Modules/LegacyPanel.lua)

`LegacySystemFrame` (Blizzard_LegacySystem, on demand): the Reward Track, Challenges and Legacy Tree pages
(level 100 children of the window, their own children up to 800). The tree's nodes are talent buttons and stay
the game's, as the talents page does. User's picks (`kit_raw/legacy_catalog.png`, 2026-09-21): LC1 LR1 LD2 LT4 LS1.
`/legdump [frames|reps]`.

| game art | element | kit piece |
|---|---|---|
| `NineSlicePanelTemplate`, `TitleBar`, `RedButton-Exit`, `_UI-Frame-TopTileStreaks`, `UI-Frame-PortraitMetal-CornerTopLeft` | the window (`Kit:SkinWindowShell`) | the table's rows; the game's shield portrait (`Legacy-up-c60`, 45 x 62) fitted into the ring like the medallion, aspect kept (`Kit:FitPortrait`) |
| (agreed addition, user 2026-09-21) | the ring's opening around the shield | `Kit:RingDisc`: a dark grey disc (0.16, 0.16, 0.17) masked round with the game's circle mask, in the PortraitContainer's BACKGROUND under the OVERLAY portrait, the class medallion's size (0.759 x the ring); shown / hidden with the ring |
| `common-sidetab` | the three side tabs | the table's row (`Kit:SkinSideTab`) |
| `Legacy-Rewards-Tracker-background`, `Legacy-Challenge-BG`, `Legacy-Tree-Frame-background` | the pages' backdrops | the page stone as a region of the page (`picture`, `owner`) |
| `Legacy-Tree-Frame-divider-Vertical` | the pane divider (12 x 503) on both pages | `edge window/single_l`, as the character window's divider |
| `Legacy-Progressbar-Frame` (+ `Legacy-Progressbar-BG` faded) | `LegacyProgressBarTemplate` StatusBars: the reward track's, the challenge points', a criteria row's | P1 via `Kit:SkinStatusBar`: caps ARTWORK 2, middle 1 over the fill (ARTWORK 0), the text (OVERLAY) over both |
| `common-dropdown-b-button`, `common-search-border-middle` | the challenge list's filter and search | B6 / S1 (the crafting page's rows) |
| `common-button-list-collapseExpand`, `Legacy-Challenge-Left-Sub-Tab`, `-selected` | the category list: a header's normal texture, a leaf's (re-atlased with the selection, one rep per atlas seen), the additive highlight faded | the category plate; `lists/plate` plain (hover from the button) / selected as regions of the button |
| the header's `CollapseButton.Icon` | +/- glyph | `Kit:SkinCollapseButton` (the plus / minus rule) |
| `Legacy-Challenge-Cards-Bar` | a criteria row's bar (180 x 30), shown by the game when no progress bar is | `lists/plate` plain as a region of the row, following the game's Show / Hide |
| `Legacy-Tree-Frame-icon-frame` | a challenge card's icon frame (the 50 px icon masked round by `UI-Frame-IconMask`) | O2: `roundslot` on a square rect whose opening is the icon (`Kit:RimRect`) |
| `Legacy-Tree-Frame-Points-Icon`, `UI-Legacy-Points-icon-c60`, `Legacy-Challenge-Cards-Date-BG`, `Legacy-Rewards-Tracker-Icon` | shields and the date plate | left as the game's (decorative pictures) |
| the Tracked check box | `AchievementCheckButtonBaseTemplate` | the kit's check box (`Kit:SkinCheckButton`, keyed from its normal texture, else `UI-CheckBox-Up`) |
| `Legacy-Rewards-Tracker-Icons-Frame` / `-Disable` | a reward card's icon border (80 on a 64 icon, re-atlased per `Refresh`) | R1: `slot` on a rect whose opening is the icon, one rep per atlas |
| `Legacy-Tree-Frame-Card-Ring`, `Legacy-Tree-Frame-Ring-big` | a tree card's ring (70 on a 67 masked icon), the selected tree's (130 on 110) | O2: `roundslot` on a rect whose opening is the icon |
| `Legacy-Tree-Frame-Card`, `-Card-Glow` | a tree selection card's picture and selection glow | **LT4**: faded — the rim only, lit (its hover look additive, `glow`) while the card is checked, refreshed on the game's `RefreshSelectionVisuals` |
| `Legacy-Tree-Frame-level-circle` | the spent-points circle under the big ring | **LS1**: `texture deco/gem_large` square on its rect as a region under the frame's text |
| `Legacy-Challenge-Cards` / `-Disable`, the tiled `-top` / `-vertical` / `-bottom` trio | a challenge card's body (collapsed picture, or the trio when expanded) | **LC1**: one `frame` (single rail + stone) on the card's rect, the trio faded with it; the game's `SelectedOverlay` stays |
| `Legacy-Challenge-Cards-Ribbon-Brown` / `-Blue` (+ `-Disable`) | the card's title ribbon (blue = account-wide), re-atlased on Saturate / Desaturate | **LC1**: `lists/header` as a region under the Label, one rep per atlas seen |
| `Legacy-Rewards-Tracker-Cards` / `-Green` / `-Disable` | a reward card's body, re-atlased per `Refresh` | **LR1**: one `frame` (single rail + stone) on the card's rect |
| `Legacy-Rewards-Tracker-Diamond` / `-Disable` | the card's level diamond | **LD2**: `texture deco/gem_large` square on its rect, the Level text over it; one rep per atlas |
| `Legacy-Tree-Frame-Points-Bar` | the "Available points" plate | `lists/header` |
| `UI-Panel-Button-Up` | Apply Changes | B1 (`Kit:SkinRedButton`) |
| `talents-button-reset`, `Legacy-Tree-Frame-reset-button` | Reset / Undo (`IconButtonTemplate`: an icon, no plate) | left as the game's |
| `MinimalScrollBar` | the category list, the detail pane | T2 / H1 / S1 |

## The quest log (Modules/QuestLogPanel.lua)

`QuestMapFrame`, the side panel of the world map window (`WorldMapFrame.BorderFrame`, a
`PortraitFrameTemplateMinimizable`); Camelot hides the Events and Map Legend tabs. The map canvas and its own
controls (nav bar, tracking and filter buttons, zoom) are the map's and untouched. Pending the user's picks
(`kit_raw/questlog_catalog.png`; QP2 parchment picked 2026-09-21; the user called the window done as it stands, so QS / QR / QC stay the game's unless asked) the story header's `StoryHeader-BG`,
the rewards box (`questlog-reward-*`) and the campaign headers stay the game's. `/qldump [frames|reps|log]`.

| game art | element | kit piece |
|---|---|---|
| the window rows | `WorldMapFrame.BorderFrame` (`Kit:SkinWindowShell`): outer rail, title, close, maximize / minimize, the ring on the book icon (fitted like the medallion) | the table's rows |
| (agreed addition, user 2026-09-21) `MapTitleBand` | the map window's title band (window top to the title container's bottom), bare once the title plate stands on the rail and the body is off for the canvas | `picture backdrops/page_stone` on a helper frame inside the outer rail, at the border frame's level (its buttons are above) |
| `common-sidetab` | the Quests tab (hidden in Camelot) | the table's row |
| `QuestLog-main-background` | the list's page (a region of `QuestScrollFrame`); also MelloUI's own Quests panel (`QuestListPanel`), filled to the outer rail's bevel | **QP2** (user, 2026-09-21): `picture backdrops/page_parchment` as a region — the parchment, as the spell book's page |
| `QuestDetailsBackgrounds` | a quest's details page | the same parchment, cropped from the top |
| `questlog-frame` (+ `questlog-frame-filigree`, `questlog-frame-gradient-bottom` faded) | `QuestLogBorderFrameTemplate` around the list and the details | `frame` edges only (single rail) |
| `QuestLog-frame-devider` | the separator, the story header's line | `window/divider` |
| `common-button-list-collapseExpand` + `CollapseButton.Icon` | a quest header (`QuestLogHeaderTemplate`) | the category plate; the plus / minus glyphs |
| `questlog-quest-glow-yellow` | a quest title's highlight (shown on hover and on the called-out quest) | `lists/plate` hover as a region of the title, following the game's Show / Hide |
| `questlog-icon-ticksquare` (+ `questlog-icon-checkmark-yellow`, the hover copy faded) | the tracking tick box | the kit's check box, checked while the CheckMark is shown |
| `common-search-border-middle`, `questlog-icon-setting` | the search box, the settings button | S1; K2 (the cog plate) |
| `UI-Panel-Button-Up` | Back, Abandon, Share, Track | B1 |
| `QuestListFilter` / `-Selected` (keyed by hand) | MelloUI's Quests panel filter buttons (two rows of four `UIPanelButtonTemplate`s 3 px apart: gem caps collided) | **F7** (user, 2026-09-21; `kit_raw/filter_catalog.png`): `lists/plate` plain as a region of the button (hover from it) and the selected plate on the active filter, switched on the panel's `Update`; the panel's own alpha dimming is off while the skin is on |
| `MinimalScrollBar` | the list and the details | T2 / H1 / S1 (the map canvas is skipped when walking) |
| `Waypoint-MapPin-Untracked` / `-Tracked` / `-Highlight` | the map's waypoint pin (`WaypointLocationPinTemplate`, pooled by the map; the Quests panel's row pin too) | **I6 / I7** (user, 2026-09-21; `kit_raw/pure_icons.png`): `inputs/slider_thumb_normal` untracked, `_hover` tracked and on hover — applied to the game's own texture after each `SetAtlas` (`SkinPinTexture`), the atlas put back on disable |
| `Interface/Common/Indicator-*` (Route's dots) | MelloUI's tracking route on the map and the minimap (`Modules/Route.lua`, STYLE) | **I2**: `deco/gem_small` for every style, the style's tint and alpha kept; the game's dots are the fallback without the kit |
| `QuestSharing-QuestLog-Button`, `questlog-storylineicon`, `TaskPOI-Icon`, the POI buttons | pictures | left as the game's |

## The guild and communities window (Modules/GuildPanel.lua)

`CommunitiesFrame` (Blizzard_Communities, on demand): a `ButtonFrameTemplateMinimizable` with the communities
list at the left, the chat / roster / guild benefits / guild info pages at the right, side tabs on the right edge.
Nearly all of its art is file textures (the `GuildFrame` and `bluemenu` sheets, cut by texcoords), which this
client reads back as numeric ids: every piece is keyed by hand from the templates. User's picks (`kit_raw/guild_catalog.png`, 2026-09-21): GC1 GH1 GP1. The Benefits tab (perks / rewards) is not shown in
this client. `/gdump [frames|reps]`.

| game art | element | kit piece |
|---|---|---|
| the window rows + `UI-Background-Rock` | the window (`Kit:SkinWindowShell` with `bg`): outer rail, page stone on the rock, streaks, title, close, maximize / minimize, the ring on the portrait (the avatar or the guild's three tabard textures, each fitted like the medallion) | the table's rows |
| `InsetFrameTemplate` (the frame's `Inset`) | the inset | `common-insideframe`: the single rail, one level UNDER the window (its `useParentLevel` children sit at the window's level) |
| `SpellBook-SkillLineTab` (keyed by hand) | the side tabs (`RightSideTabTemplate`, 32 px) | `common-sidetab`: the gold rim, the icon fitted, glow while checked |
| `bluemenu-main` (the list's `Bg`, filigrees) → `CommunitiesListBody`; the gold border + `InsetFrame` → `CommunitiesListBox` | the communities list's box | L1 in two parts: the stone body (`tile window/single_body`, `owner`) as a region of the list under its rows; the single rail on the `InsetFrame` rect at that frame's own level (200), OVER the rows |
| `bluemenu-main` (an entry's `Background`) → `CommunitiesListEntry`; `-selected` (its `Selection`) faded | a communities list entry (68 px tall) | R3 (user, 2026-09-21): the single-rail card with stone, its iron lit gold while the game shows the Selection, hover from the button |
| `communities-ring-gold` | an entry's icon ring | O2: `roundslot` on a rect whose opening is the icon, following the game |
| `common-dropdown-textholder` | the list, stream, member list and add-to-chat dropdowns | D1 |
| `InsetFrameTemplate` | the member list's and the chat's insets | `common-insideframe` at the inset's own level (100), over the rows (user, 2026-09-21: the border was behind the bars) |
| `GuildFrame` sheet (a member row's normal texture), `UI-FriendsFrame-HighlightBar` | a roster row | `lists/plate` plain as a region of the row, hover from it; the highlight faded |
| `CollapsibleHeader` Left / Middle / Right, `Char-Stat-Plus` / `-Minus` | a roster profession header and its glyphs | the category plate; the plus / minus plates following the game's two icons |
| `UI-CheckBox-Up` | Show Offline | the kit's check box |
| `UI-Background-Rock`, `_UI-Frame-TopTileStreaks` | the column display's band | the page stone as a region; the streaks faded |
| `UI-ChatInputBorder-Mid2` (+ Left / Right) | the guild chat's input line | S1's middle only (`capless`: no search glass, it is a chat line), focused while typing |
| `UI-Panel-Button-Up` | Invite, Guild Log, Settings, Guild Control, Recruitment, Jump to Unread | B1 |
| `GuildFrame` sheet → `GuildFrame-Bar` (BG; Left / Middle / Right / Shadow faded) | the guild reputation bar (`CommunitiesGuildProgressBarTemplate`, a `Progress` texture the game widens to value x (width - 4)) | P1: the bracket on the BG's rect, the fill moved into the opening, its width re-scaled onto the opening's width on the game's `SetWidth` |
| `UI-Frame-Inner*` loose pieces → `UI-Frame-InnerBorderPiece` | the roster column band's and the info page's two columns' inset borders (separate textures) | faded — the member list's rail and the pane divider stand in |
| the info page's `InsetBorderRight` | the line between the Info and News columns | `common-framedivider`: the single rail edge (the pane divider) |
| `GuildFrame` sheet pieces → `GuildFrame-Sheet` | the info and news columns' sheet backgrounds | faded, the page stone shows |
| `UI-ClassTrainer-HorizontalBar` | the info page's bars over its headers | faded (a divider's gems on top of the header plate's read as clutter); the header plate alone marks the section |
| `UIDropDownMenu` (Left / Middle / Right file art, keyed by hand) | the preferred play settings' two old-style dropdowns | D1 fitted to the 24 px box in the middle of the 64 px art, the arrow button faded |
| `GuildFrame` headers (`Header1..3`, News `Header`) → `GuildFrame-Header` | the guild info / news page headers | **GH1** (user, 2026-09-21; `kit_raw/guild_catalog.png`): `lists/header` as a region under the text |
| `WhoFrame-ColumnTabs` (Left / Middle / Right, keyed by hand) → `ColumnDisplayButton` | the roster's column header buttons, re-laid by the game's `LayoutColumns` | **GC1**: `lists/header` per column, cap-less on all (the one wide column's gem sat under its text), hover from the button |
| the news rows' `UI-FriendsFrame-HighlightBar-Blue` → `GuildNewsRow` | a guild news row | **GP1**: `lists/plate` plain under the row, hover from it; the blue highlight faded |
| `UI-Background-Marble` | the strip under the roster's scroll bar | faded |
| `MinimalScrollBar` | every list | T2 / H1 / S1 |

## The group finder (Modules/GroupFinderPanel.lua) and the collections (Modules/CollectionsPanel.lua)

First pass (2026-09-21). This client's group finder is the VANILLA-STYLE one (`LFGParentFrame`,
Blizzard_GroupFinder_VanillaStyle): the Listing, Browse and Who pages on side tabs, each page its own
`PortraitFrameTemplateNoCloseButton`, the eye portrait the parent's (one ring per page, on the eye). The
collections (`CollectionsJournal`, Blizzard_Collections) shows the Appearances tab in this client. Both lean on
`Kit:SweepControls`, which finds every common control under the window by what it IS and gives it its fixed
look: scroll bars, search boxes (S1), PanelTab tabs (T1, `Kit:SkinPanelTab`), red buttons (B1), check boxes,
text dropdowns (D1), filter dropdowns (B6), insets (`Kit:SkinInset`: the single rail, edges only, at the inset's
own level over the rows; only the inset's ART is faded, never the frame — an inset may hold content). The
collections window's body is OFF (its holder sat over the wardrobe's slot buttons): the rock is the page stone
as a region under everything. The dumps: `/gfdump`, `/coldump`.

| game art | element | kit piece |
|---|---|---|
| the window rows, `common-sidetab` | the pages' shells, the side tabs | the table's rows |
| `UI-LFG-BlueBG` (keyed by hand) | the listing's role band | faded (the window's one page picture runs under it); only the inside of the inset rail is the darker stone |
| `groupfinder-background-page` (the browse page's `BackgroundArt`) | the browse page's page-level painting over its inset | faded (the window's page stone is under it; the inset's darker stone shows) |
| `groupfinder-background` (the insets' CustomBG); `common-insideframe` → `WhoListBody` | the listing's category area, the browse list's inset, the who list's box | the darker list-box stone (`tile window/single_body`) as a region under the rows (user, 2026-09-21) |
| `UI-CheckBox-Up` | the role buttons' and activity rows' check boxes | the kit's check box (the role pictures stay) |
| `UI-MinusButton-UP` / `UI-PlusButton-UP` (read from the game's `SetNormalTexture`) | an activity row's expand glyph | the minus / plus plates, one per glyph |
| `OptionsIcon-Brown` → `common-dropdown-a-button`, `UI-SquareButton-Up` (keyed by hand), `common-button-tertiary-square-normal` | the option cogs, the browse refresh, the who search | K2: the cog plate under the game's icon |
| `shop-list-rule` | the activity list's rule | `window/divider` |
| `LFGBrowse-Result` (a colour texture, keyed by hand), `groupfinder-highlightbar-yellow`, `-blue` | a browse result row (50 px tall), its selection and hover bars | **R3** (user, 2026-09-21; `kit_raw/tallrow_catalog.png`): a `frame` — single rail + stone under the row, its iron lit gold (`checkedTint`) while the game shows the Selected bar, brighter on hover; the bars faded. THE look for any tall list row |
| `LFGBrowse-Grouping` | a grouping header (short) | `lists/catplate` closed |
| `QuestLog-icon-Expand` / `-shrink` | a grouping header's glyphs | plus / minus plates following the game |
| `common-button-list-large` / `-selected` / `-hover` | a who list row (58 px tall) | R3, as the browse rows |
| `groupfinder-Stat-StoneBG`, `glues-characterSelect-searchbar` | the who list's header band, its search box's own backdrop | `tiles/stone` as a region; faded (S1 stands in) |
| `groupfinder-button-cover` (+ `groupfinder-button-*` paintings, `PvPMegaQueue` selection kept) | the four painted category buttons (Dungeons / Quests & Zones / Battlegrounds / Custom) | the single rail, edges only, at the button's level over the painting (user, 2026-09-21); the painting, selection and hover stay the game's |
| `UI-Background-Rock` (CollectionsJournalBg) | the collections window's rock | the page stone as a region |
| `collections-background-tile`; `-shadow-large` / `-small`, `-corner` faded | an icon grid's backdrop (the wardrobe's items, toys, heirlooms) | the page stone as a region under the slots; the shadowed edges faded |
| `PetList-ButtonBackground`, `PetList-ButtonSelect`, `WhiteIconFrame` (keyed by hand) | a mount list row | `lists/plate` plain (hover) / selected (following the game); the square rim on the icon |
| pending the dump | the wardrobe's slot cells and models, the pet list, toy / heirloom slots | — |

## The HUD: unit frames (Modules/UnitFramePanel.lua, 2026-09-21)

The player, target, focus, target-of-target and pet frames (this client: the Dragonflight layout with
Camelot overrides — the level circle and the PvP badge are separate regions, `UI-HUD-UnitFrame-SmallCircle`).
User's picks from `kit_raw/unitframe_catalog.png` (`UITest/tools/unitframe_catalog.py`): **B3 R1 L1 N3**.
`/ufdump [player|target|focus|pet|tot|party] [frames|reps]` (reps also prints the portrait, mask, bars and
ring cover with their levels). Covers the Dark Mode group `unitframes` while on.

| game art | where | kit piece |
|---|---|---|
| `UI-HUD-UnitFrame-Player-PortraitOn` / `-Target-PortraitOn` / `-TargetofTarget-PortraitOn` (`FrameTexture`, `PetFrameTexture`; the vehicle / class-resource / rare / minus variants are the same region re-atlased) | the frame's ONE picture: ring, name band, both bar rims | faded; the pieces below stand on the frame's own sub-rects, as regions in this picture's layer or of the bars |
| the same region, `UnitFramePortraitRing` (keyed by hand) | the portrait (60 / 58 / 37 px) | **R1**: `window/portrait_ring` with its OPENING on the portrait's rect (`opening = true`), a region in the picture's layer (BACKGROUND 2 under the bars). The portrait (and a mask with its own anchors, the player's) fitted to the medallion size, 0.759 × ring (rule 2b), re-fitted on every portrait update; Class Icons puts the plain medallion inside a kit ring (`melloKitRing`). The elite / rare / boss rings (`-Boss-Gold`, `-Silver-Winged` …) faded and the kit ring tinted gold / silver instead (`CheckClassification` post-hook) |
| the same region, `UnitFrameBar` / `UnitFrameBarMirrored` | the health bar (124 × 20 / 126 × 20 / 70 × 10) and the power bar (124 × 10 / 134 × 10 / 74 × 7), the bracket on the BAR's own rect | **B3**: the P1 `bars/frame` bracket as regions of the bar, one layer above its fill (the health fills draw at BACKGROUND → BORDER; the power bars have no drawLayer → ARTWORK → OVERLAY 0, under the OVERLAY 1 text), the trough one layer below; ring side capless (`dropCap`), the far gem cap grown OUTWARD past the rect (`capOut`) so the fill keeps its width. Bar Textures drops its shaped mask on a bracketed bar (`melloKitBracket`, `M:RefreshMask`) |
| the bars' ring-side end (their own anchors) | the game runs the bars into the ring's opening (the target's power bar 8 px past its health bar: the DF art tucked them under its ring) | TUCKED (user, 2026-09-21): each bar's ring-side edge re-anchored to the ring's round BODY (KitLayout `radius`, measured off the compass gems) at the bar's height, 2 px under it — a clean butt joint on the curve, the fill readable to its end (a deeper tuck hid the last per cent of health); far edge and height kept, relative to the frame the game anchors it to; put back on disable. Re-applied on `CheckClassification`, the player's art swaps, frame show |
| `UI-HUD-UnitFrame-SmallCircle` (`LevelBackgroundCircle`, `PvpBackgroundCircle`, 39 px) | the level badge's circle, the PvP badge's circle | **L1**: `buttons/orb` square on the circle's rect as a region under the frame's own level text / faction icon, following the game's show / hide |
| `UI-HUD-UnitFrame-Target-PortraitOn-Type` (`ReputationColor`, 135 × 18) → faded; `UnitFrameNameBand` (keyed by hand) | the target's reaction strip = the name band; the player's band is the same rect mirrored (a sizer, TOPLEFT +75 for the target's TOPRIGHT −75) | **N3**: `tabs/top` title plate on the band's rect, a region in the picture's layer (BACKGROUND 1, so the ring made after it draws over its end); the name centred on it (width = the plate's, justify CENTER, like a window title on its plate; the Unit Frames tweak leaves names alone while covered) |
| `-InCombat` flashes, `-Status` rings, `-CornerEmbellishment`, `-Vehicle`, `-ClassResource` | combat / threat flash, rest-status ring, the corner flourish, the art variants | faded (decoration) |
| left as the game's | the portrait render / medallion, level and name text, the rest zzz, leader / guide / role / PvP / raid-target / quest / boss icons, the auras, the heal-prediction and absorb fills (still masked to the DF shape), the class resource bars, the ToT / pet name (their art has no band to replace) | — |

Party frames (`PartyFrame`'s pooled `PartyMemberFrameTemplate` 120 × 53 and each member's pet frame, in the
same module, 2026-09-21 — the same picks, no catalogue; covers `partyframes`):

| game art | where | kit piece |
|---|---|---|
| `UI-HUD-UnitFrame-Party-PortraitOn` (`Texture`, ARTWORK 0 of the member frame; the pet's lowercase twin at half scale), `-Vehicle`, `-InCombat`, `-Status` | the member's picture and its variants | faded |
| the same region, `UnitFramePortraitRingParty` | the 37 px portrait (pet: 18) | R1 as above, but at BACKGROUND 2 (`layer` / `sublevel` on an owner-mode texture rule): the party picture is drawn ABOVE its portrait with the name after it in ARTWORK, so the ring must sit under the name |
| the bars (70 × 10 health at BACKGROUND, 74 × 7 power at ARTWORK; the pet's 71 × 10 at half scale) | | B3 brackets, tucked, ring cover — as the player's |
| the name (`Name`, 57 × 12 at TOPLEFT 46, −6) | the party art's name band | N3 on a sizer: the plate CENTRED over the health bar on the name's line, the player band's height scaled by the portraits' ratio (37 / 60) × 1.2, at least as wide as the two rune caps at that height (else it went capless) — user's calls on sight, 2026-09-21; the name centred on it; re-laid on `UpdateNameTextAnchors` / `UpdateArt` |
| `PartyFrame.Background` (Edit Mode's optional backdrop, `BackdropTemplate` pieces `Center` / edges / corners faded) → `PartyFrameBackground` | the party backdrop | L1: the single rail with the stone body, as its child (follows the opacity slider) |
| left as the game's | leader / guide / role / PvP / disconnect / not-present icons, ready check, auras, the pet's name | — |

The member frames are released and re-acquired from the pool on every `PartyFrame` show
(`InitializePartyMemberFrames`): the skin runs from that post-hook and marks each frame once.

Agreed addition for the HUD (a stacking device, not a new element):

| key | where | kit piece |
|---|---|---|
| `RingCover` (`UnitFramePanel` `RingCover`) | the strip where the bars meet the ring: the bars' vertical span, from their ring-side edge to the ring's far edge | the ring's OWN pixels drawn once more (the same piece, cropped by `SetTexCoord` to that strip) on a holder one level above the bars, because the ring is a region under the bar frames and the user wants the border over the bars' ends (2026-09-21). Follows the ring's tint; re-laid with the bars; covers nothing else (badge, zzz, leader icons and raid marks lie outside the strip) |

## The HUD: cast bars (Modules/CastBarPanel.lua, 2026-09-21)

The player's cast bar (`PlayerCastingBarFrame`, standalone 208 × 11 and locked-to-frame 150 × 10 looks),
the overlay bar, the pet's, the target's and focus' spell bars (`TargetSpellBarTemplate` 150 × 10). User's
picks (`kit_raw/castbar_catalog.png`, `UITest/tools/castbar_catalog.py`): **C1 T1**. `/cbdump [player|pet|
target|focus|overlay] [frames|reps]`. Covers the Dark Mode group `castbar`.

| game art | where | kit piece |
|---|---|---|
| `ui-castingbar-frame` (`Border`) | the bar's rim | **C1**: `bars/castbar` (gem-cluster caps) as regions of the bar one layer above its fill (`Kit:BracketLayers`), the bar's own rect as its opening and the caps OUTSIDE it (`capOut`); the bar narrowed by the caps' arms after each of the game's `SetLook` (saved width put back on disable) so the whole reads the game's width; the spell icon moved out past the cap by the same arm |
| `ui-castingbar-background` (`Background`) | the trough art | faded; the bracket's trough |
| `ui-castingbar-textbox` (`TextBorder`, 208 × 23 from the bar's top to 12 px under it; shown by the standalone look only) | the spell name's box | **T1**: `lists/header` on the box's lower 12 px (a sizer from the bar's bottom to the box's bottom), following the game's show / hide |
| `ui-castingbar-full-glow-standard` (`Flash`, `ChargeFlash`), `castbar_shadow_embedded`, the glow / flake / wisp / sparkle / shine regions (`CastBarFX`, keyed by parentKey) | the effects | faded; their animation groups (`FlashLoopingAnim`, `StandardFinish`, `InterruptGlowAnim` …) stopped on `Play` — they drive alpha past the fade hook. The bar's own fade-out animations stay |
| left as the game's | the fill (Bar Textures drops its shaped mask on a bracketed bar), spark, icon, uninterruptible shield, texts, empower stage pips and tiers | — |

Under the target frame every rect reads SECRET, our own regions' included: those bars fit to the
template's sizes (`fitHeight` / `fitWidth` fallbacks, `KNOWN` in the panel), and strips never read their
own cap or middle sizes back (`strip.wl` / `wr`, `mid.kitTileW`).

## The HUD: compact raid frames and totems (Modules/RaidFramePanel.lua, 2026-09-21)

`CompactUnitFrameTemplate` (raid members, raid-style party members, pets / mini frames; 72 × 36 by default,
Edit Mode sizes them) and `CompactRaidGroupTemplate`'s border. User's picks (`kit_raw/raidframe_catalog.png`,
`UITest/tools/raidframe_catalog.py`): **F1 G1**. `/rfdump [frame name] [frames|reps]`. Covers `raidframes`.

| game art | where | kit piece |
|---|---|---|
| `raidframe-hp-bg-white` (`background`, the frame's dark backing; the health bar inset 1 px with its fill at BORDER) | a compact frame | **F1**: a `frame` in OWNER mode — the single rail at 0.8 × the window weight with the stone body, as REGIONS of the frame: stone at BACKGROUND 1 (above the faded backing), rails at ARTWORK −1 (above the BORDER fills, under the ARTWORK role / status icons and name, the OVERLAY target edge and the aggro glow). Set up from the game's `DefaultCompactUnitFrameSetup` / `DefaultCompactMiniFrameSetup` post-hooks |
| `options_frame_child` (`borderFrame.Background`) | a raid group's border (Edit Mode 'display border' with separate groups) | **G1**: the single rail 1.6, edges only, a child of the border frame (shows / hides with it); skinned from `CompactRaidGroup_UpdateBorder` |
| `UI-HUD-UnitFrame-TotemFrame` (`Border`, 30 px OVERLAY over the 22 px round icon) | a totem button | O2: `buttons/roundslot` square on the border's rect, a region in its layer; the pooled buttons skinned from `TotemFrame:Update` |
| left as the game's | fills (and their heal-prediction / absorb overlays), name, status text, role / ready-check / centre-status icons, the white selection edge, the red aggro glow, the dispel / buff / debuff icons, the manager side panel (its buttons are a later pass) | — |

Same-level frames share ONE layer order (the health bar, `useParentLevel`, draws its BORDER fill under the
frame's own ARTWORK name): a piece that must sit between a child bar's fill and the frame's icons is a REGION
of the frame in the layer between — `Kit:NineSlice` owner mode (`owner`, `bodyLayer` / `edgeLayer`).

## The HUD: action bars, micro menu, bag bar, status bars (Modules/ActionBarPanel.lua, 2026-09-21)

User's picks (`kit_raw/actionbar_catalog.png`, `UITest/tools/actionbar_catalog.py`): **X2 M1**, "no custom icons
on the micro bar"; the buttons are the rule book's R1. `/abdump [bar|micro|bags|xp] [frames|reps]` (the main
bar's prints the measured pitch, the xp one the fill's state). Covers `actionbars`, `micromenu`, `bagbar`,
`statusbars`. `Kit:SkinActionButton(button, replace, pitch)` does a button; the pieces sheet is
`kit_raw/hud_pieces.png` (`tools/hud_pieces_sheet.py`).

| game art | where | kit piece |
|---|---|---|
| `UI-HUD-ActionBar-IconFrame` (`NormalTexture`; `-Down` pushed, `-Mouseover` highlight / checked) | every action-style button: `ActionButtonTemplate` and `SmallActionButtonTemplate` (main, multi bars, stance, pet, possess) and the Camelot square bag slots | **R1**: `buttons/slot` on the button at the NormalTexture's ARTWORK (sublevel 2: above the Flash, under the OVERLAY name, equipped border, highlights, and the level-500 keybind / count), sized to the bar's PITCH (`gemSpan` 97/135 × 92/130: the first button's size + `bar.buttonPadding`) so neighbours share a gem; the icon fitted into the opening with its rounded `IconMask` / `SquareMask` taken off; pushed / highlight / checked faded (the rim's states). Re-sized from the bar's `UpdateGridLayout` (`rep:SetPitch`) |
| `UI-HUD-ActionBar-IconFrame-Background` (`SlotBackground`), `ui-hud-actionbar-iconframe-slot` (`SlotArt`) | an empty slot | `tiles/stone` in the rim's opening at BACKGROUND −1 (under the icon), shown while the slot is EMPTY (the game hides the icon then — its own backing only shows on a bar whose art is hidden; on the main bar the faded frame art was the empty look); the ornament faded |
| `UI-HUD-ActionBar-IconFrame-Border` (`Border`) | the equipped-item border | faded; the rim tinted green while the game shows it |
| `UI-HUD-ActionBar-Frame` (`BorderArt` of the main bar, micro menu, bag bar), the main bar's pooled `-Divider-ThreeSlice-*` frames, `MicroMenu.BackgroundArt` | the bars' frame art | faded: it lies under the pitch-sized rims |
| `ui-hud-actionbar-gryphon-left` / `-right` (`EndCaps.LeftEndCap.Texture`, 154 × 95) | the main bar's end caps | **X2**: `deco/rail_cap_l` / `_r` at the gryphon's height on its inner bottom corner, on holders at the BACKGROUND strata (user: the caps behind ALL the bars and the status bars), following the caps' rects and `EndCaps`' show / hide |
| `ui-hud-actionbar-pageuparrow-up` / `-pagedownarrow-up` (+ down / mouseover / disabled) | the page arrows | `buttons/arrow_up` / `_down` at their size — and the whole `ActionBarPageNumber` faded with its mouse off by the module option "Hide Page Arrows" (user, 2026-09-21; on by default) |
| `UI-HUD-MicroMenu-ButtonBG-Up` / `-Down` (`Background` / `PushedBackground`) | a micro button's plate | the R1 slot rim, SQUARE at the bar's pitch (the spacing between neighbours, 27 px for 32 px buttons: the game's plates overlap) so neighbours share a gem, centred on the tall button (OVERLAY, over the glyph's edges), the game's glyph fitted into the rim's opening (its pushed / highlight / disabled states and the character portrait anchored to it, the fit redone after every state-atlas set), the stone tile (`tiles/stone`) in the opening under the glyph as an empty action slot has it (an agreed addition, user 2026-09-22: "a background to those icons"); the character button's portrait is its icon, fitted into the opening on the stone like the glyphs (user, 2026-09-22: "only the real icons", "but the custom borders", "square rim at the button's width"; M1's cog plates are gone) |
| `UI-HUD-ExperienceBar-Frame` (`BarFrameTexture`, 1192 × 17), `-Background` | a status bar container (XP / reputation / honour; two may stack) | P1: `bars/frame` bracket as the container's OVERLAY regions with the caps OUTSIDE the bar (`capOut`); the trough on a holder at the LOW strata one level under the fill's status bar (the fill is a LOW frame under the MEDIUM container: an opaque trough on the container hid it); Bar Textures drops its mask (`melloKitBracket`). The containers by name (the manager's `barContainers` is filled on this client too); re-fitted from `LayoutBars` / `UpdateBarsShown` |
| `UI-HUD-ExperienceBar-Divider` (pooled `StatusBarDividerTemplate` frames, 20 per bar) | the segment dividers | `bars/tick` at its size on each, re-skinned from `UpdateDividers` |
| left as the game's | icons, keybinds, counts, cooldowns, the auto-attack flash, spell-alert / proc glows, the new-action glow, the rested tick (`ExhaustionTick`) and rested fill, the bag bar's expand arrow and "bag open" highlight, the micro glyphs and the character portrait, `ExtraActionBar` / `ZoneAbilityFrame` | — |

## The backpack and bag windows (Modules/BackpackPanel.lua, 2026-09-21)

`ContainerFrameCombinedBags` and `ContainerFrame1..7` (`PortraitFrameFlatTemplate`). User's pick
(`kit_raw/bag_catalog.png`, `UITest/tools/bag_catalog.py`): **B2**. `/bagdump [1-7|combined] [frames|reps]`.
Covers `backpack`.

| game art | where | kit piece |
|---|---|---|
| the flat window: `NineSlice`, `Bg` (`FlatPanelBackgroundTemplate` pieces `uiframebackground-nineslice-*`), `PortraitContainer.portrait`, `TitleContainer`, `CloseButton` | the shell | `Kit:SkinWindowShell` with `bg`: outer rail, ONE page stone inside it (the picture holder honours `inset` now), the ring on the bag icon fitted to the medallion size on the dark disc (2b: a square item icon), the title plate on the rail (2c), the close button; the Bg pieces faded |
| `UI-Quickslot2` (the item button's `NormalTexture`), pushed / highlight | a bag slot (`ContainerFrameItemButtonTemplate`, pooled, re-laid by `UpdateItemLayout`) | R1 via `Kit:SkinActionButton` with `emptyStone`: the rim sized to the grid's pitch (from the first two buttons' positions), the icon filling it, stone in an empty slot's opening (there is no backing region: the stone replaces the NormalTexture's empty look), pushed / highlight faded |
| `WhiteIconFrame` (`IconBorder`, the quality border) | an item's quality | LEFT THE GAME'S, anchored to the icon so it sits inside the rim with it — the rim is NOT tinted by the quality (user, 2026-09-21; unlike the windows' O2 / R1 rule) |
| `UI-Bag-Components` (`ItemSlotBackground`, keyed `BagSlotBackground`), `UI-Bag-1Slot` | the combined bags' slot-cell picture, a one-slot bag's picture | faded |
| `common-coinbox-left / -center / -right` (`MoneyFrame.Border`) | the money strip | **B2**: `lists/header` on the border's rect; the money frame raised one level above the item buttons while on (the bottom row's pitch-sized rims reached over the coins), put back on disable |
| `BagSearchBoxTemplate` (`BagItemSearchBox`, re-parented among the bags) | the search box | S1 (`Kit:SkinSearchBox`) |
| `bags-button-autosort-up` (`BagItemAutoSortButton`) | the sort button | K2: the cog plate UNDER the game's round button (its glyph is its plate: kept, not faded) |
| left as the game's | icons, counts, cooldowns, the new-item / flash glows, junk coin, quest and upgrade marks, the search dimming, the filter icon, the free-slot count, the bag-icon dropdown, the bank | — |

## The minimap cluster (Modules/MinimapPanel.lua, 2026-09-21)

This client (Blizzard_Minimap/Camelot/Skin.lua): a round frame `UI-HUD-Minimap-Frame` (215 × 226, `-Pointer` +
`-Circle` underlay when rotating) around the 198 px map, the zone band `BorderTop` (175 × 16) above it, the
tracking button on its left. User's picks (`kit_raw/minimap_catalog.png`, `UITest/tools/minimap_catalog.py`):
**R1 Z2**, the ring then "25 % smaller, the map untouched". `/mmdump [frames|reps]`. Covers `minimap`.

| game art | where | kit piece |
|---|---|---|
| `UI-HUD-Minimap-Frame` (`MinimapCompassTexture`, OVERLAY of `MinimapBackdrop`), `-Circle` underlay | the round frame | **R1 × 0.75**: `window/portrait_ring` sized from the map's opening (`opening = true`) × `openingScale` 0.75, its rim over the map's outer ~25 px, on a holder ONE LEVEL ABOVE the map (parent the cluster); the band, its text, the tracking button, the indicators and the calendar raised one level above the ring while on (game levels put back on disable). The compass letters go with the frame |
| `BorderTop` (a nine-slice of textures, keyed `MinimapZoneBand`) | the zone band | **Z2**: `tabs/top` title plate as the band's own regions (BACKGROUND, under the OVERLAY zone text of its sibling at the same level), standing on the ring's top rim |
| `ui-hud-minimap-button` (`Tracking.Background`) | the tracking button's round plate | `buttons/roundslot` on its rect, the game's glyph on it |
| `ui-hud-minimap-zoom-in` / `-out` (+ down / mouseover / disabled) | the zoom buttons (shown on hover) | `buttons/plus` / `buttons/minus` at their size |
| left as the game's | the map, the calendar, mail and crafting-order icons, the landing-page button, the day / night dial, the queue status, the addon compartment, MelloUI's Services bar and Route dots | — |

## The objective tracker (Modules/TrackerPanel.lua, 2026-09-21)

`ObjectiveTrackerFrame` and its modules. User's pick: **T2**; on sight: header texts centred, the toggles left of
the caps' gems, a backdrop with a border that follows Edit Mode's opacity and retracts when collapsed.
`/trdump [frames|reps]`. Covers `tracker`. Agreed addition (user, 2026-09-22): a black shade over the backdrop's
stone under the text, 60 % down the middle fading to nothing at both sides (two gradient halves on the backdrop's
holder at BACKGROUND 2, above the body, under the rails).

| game art | where | kit piece |
|---|---|---|
| `ui-questtracker-primary-objective-header` (`Header.Background`, 260 × 32) | the tracker's header band | **T2**: `tabs/top` title plate as the header's regions; the text centred on it; the minimize button moved left past the cap's gem (57 % of the title cap, measured) |
| `UI-QuestTracker-Secondary-Objective-Header` (a module's `Header.Background`, 260 × 26) | a module's header band | `lists/header`; text centred; the toggle left of the gem (23 % of the header cap) |
| `ui-questtrackerbutton-collapse-all` / `-expand-all` / `-secondary-collapse` / `-secondary-expand` | the collapse / expand toggles | `buttons/minus` / `buttons/plus`, switched with the atlas the game sets (`Kit:StateIconReps` on the normal texture's `SetAtlas`) |
| `ui-questtrackerbutton-filter` | the filter button | K2: the cog plate under the game's glyph |
| the container's `NineSlice` (`common-opacity-background`, Edit Mode's opacity box) → `ObjectiveTrackerBackground` | the tracker's backdrop | L1: `frame`, with a parchment sheet on its stone ending in the dry-brush edge (TrackerPanel, user 2026-09-23) (single rail + stone) on the NineSlice's rect as the TRACKER's child at its level, its alpha following the game's `SetBackgroundAlpha` (Edit Mode's opacity, 0 by default), retracting to the header while collapsed (`SetCollapsed`); the game's box pieces faded |
| `UI-Quickslot2` (a quest item button's NormalTexture, pooled right-edge frames) | quest items | R1 via `Kit:SkinActionButton` (no stone) |
| `UI-Character-Skills-BarBorder` (a progress bar's `BorderLeft` / `Mid` / `Right`, keyed on the middle) | a tracker progress bar | P1 as the bar's regions above its fill |
| left as the game's | block texts and their hover colour, POI buttons (the map's pin rules apply where the game re-atlases them), timers, the auto-quest pop-ups, the header shine / glow FX | — |

A module header's `AddAnim` fades its `Background` back in (an Alpha animation with `setToFinalAlpha`, run by the
client past the fade's `SetAlpha` hook): the game's band came back over the plate's middle (user, 2026-09-21). While
the kit is on, that Alpha animation is retargeted to 0 -> 0 and the band re-faded on `OnFinished`; the glow, shine and
button parts of the animation still play (`SilenceAddAnim` in TrackerPanel).

## The social window (Modules/SocialPanel.lua, 2026-09-21)

`FriendsFrame` (Camelot's own XML: Contacts with its Friends / Ignore / Recent Allies top tabs, the Raid pane from
the classic `Blizzard_RaidUI`, Quick Join). User's pick: **G3** (`kit_raw/social_catalog.png`); the tabs **TB6**
(`kit_raw/bottomtab_catalog.png`, chosen here and applied to every tabbed window). `/socdump [frames|reps]`. Covers
`social`.

| game art | where | kit piece |
|---|---|---|
| the flat window shell (`NineSlice`, `Bg`, `PortraitContainer`, `TitleContainer`, `CloseButton`) | the shell | `Kit:SkinWindowShell` with `UI-Background-Rock`: outer rail, one page stone, the ring on the dark disc with `FriendsFrameIcon` at the medallion size (2b, as every window's portrait: the 1.3 x of 2026-09-21 outgrew the ring — user, 2026-09-24; re-fitted on every `SetTexture`), the title plate on the rail, the close button |
| `Inset` (`InsetFrameTemplate`) | the list box | `Kit:SkinInset`: single rail (L1) |
| `FriendsFrameTab1..4` (`PanelTabButtonTemplate`) and the `FriendsTabHeader.TabSystem` tabs | bottom / top tabs | **TB6** via `Kit:SkinPanelTab` |
| `battlenet-friends-main` (the Battle.net tag band's first texture) | under the top tabs | `lists/header` as the band's regions |
| `UI-QuestLogTitleHighlight` file art (a friend / ignore / raid-info row's highlight, keyed `FriendsRowHighlight`) | list rows | `lists/plate` hover as the row's region, shown on hover only (the game's highlight draws itself on hover; a replacement region is shown by hand — `HoverPlate`) |
| `UI-Background-Rock` + arrows on a pending-invite header (keyed `FriendsPendingHeader`) | invite headers | `lists/catplate` closed, the game's arrows on it, the `Flash` faded |
| `UI-FriendsFrame-OnlineDivider` | the online / offline line | `window/divider` |
| `friendslist-invitebutton-default-normal` | the invite icon button on a row | K2: the cog plate under the game's glyph |
| `UI-RaidFrame-GroupOutline` (a raid group box's 162 x 80 outline picture) | the raid pane's eight group boxes | **G3**: `frame` at 0.8 (the raid frames' weight) with the stone body; the rows stay bare text |
| `WhoFrame-ColumnTabs` file pieces (`RaidInfoInstanceLabel` / `RaidInfoIDLabel`, keyed `ColumnDisplayButton`) | the raid info popup's column headers | GC1: `lists/header` |
| `UI-RaidInfo-Header` (`RaidInfoDetailHeader` / `Footer`) | the raid info popup's bands | faded (the dialog's own border stands) |
| red buttons, dropdowns, check boxes, scroll bars, edit boxes on the window, the raid pane and the raid info popup | controls | the fixed looks by `Kit:SweepControls` (again on every show: the tabs and pooled frames come and go with the window) |
| the ignore list window (`IgnoreListWindow`) | a second small window | the shell without a ring, its inset and rows the same |

## The chat windows (Modules/ChatPanel.lua, 2026-09-21)

`ChatFrame1..10` (`FloatingChatFrameTemplate`), their tabs, minimized tabs, edit boxes, side button frames and the
menu / channel / voice buttons. User's picks: **CH1 CT2** (`kit_raw/chat_catalog.png`); and **no chat fade**: the
tabs, the side button frame, the edit box (the game's inactive 0.35) and the minimized tabs are held at full alpha by
a `SetAlpha` post-hook while the module is on, the background held at the alpha slider's value (`chatFrame.oldAlpha`,
re-applied after `FCF_SetWindowAlpha`) instead of brightening under the mouse; the rail never follows an alpha.
`/chdump [n] [frames|reps]`. Covers `chat` (the `Chat` tweak module's art toggles act only while this is off).
The body is the stone tile at the slider's alpha (2026-09-21, after the round: "only a solid dark colour").

| game art | where | kit piece |
|---|---|---|
| `UI-ChatFrame-BorderCorner` / `-BorderTop` / `-BorderLeft` file pieces (the eight `<name>TopLeftTexture`... around `<name>Background`; keyed `ChatFrameBorder` on the top-left corner) | the window's border, the side button frame's | **CH1**: `frame` with no body, as REGIONS of the chat frame in the pieces' BORDER layer, `outset` 8 so the rail is centred on the Background's edge (the pieces reach 4 px past it) |
| `ChatFrameBackground` file art (`<name>Background`, the flat translucent black; keyed `ChatFrameBody`) | the window's body, the side button frame's | `tile window/single_body` as a region in its place (user, 2026-09-21: the dark cracked stone, not a flat colour), its alpha the slider's value (`chatFrame.oldAlpha`, re-read after every `SetAlpha` the game makes by name and after `FCF_SetWindowAlpha`) |
| `ChatFrameTab-BGLeft` / `-Mid` / `-Right` (`Left` / `Middle` / `Right`), `-Selected*` (`ActiveLeft`..., shown by `FCFTab_UpdateColors`), `-Highlight*`; the `-min` set on a minimized tab | the chat tabs | **CT2** = TB6 via the `uiframe-tab-left` / `uiframe-activetab-left` rules on a sizer 8 px under the tab's top (the art is bottom-anchored in the 32 px tab); the text held centred on the card (the game puts it 5 px under the tab's centre) |
| `UI-ChatInputBorder-Left2` / `-Mid2` / `-Right2` and the `-Focus-*` set | the edit box | S1 (`UI-ChatInputBorder-Mid2`) with `dropCap = "l"`: the plate's left cap carries the search glyph, so on a chat box it is dropped and the plate closes with `inputs/edit_end_l` (the right cap mirrored, made 2026-09-21); the focused look while typing; the game's own 15 px header inset then puts "Say:" and the text in the field |
| `UI-ChatIcon-Chat-Up` (menu), `-Minimize-Up`, `-Maximize-Up` (keyed `ChatIconButton`) | the icon buttons | K2: the cog plate at its natural size under the game's glyph |
| `chatframe-button-up` (the channel / voice buttons' own round plate, the glyph on their `Icon`) | the channel / voice buttons | K2: the cog on the plate's rect, the pushed / highlight art faded, the glyph kept |
| `minimal-scrollbar-arrow-returntobottom` | scroll-to-bottom | `buttons/arrow_down` on the button's rect (its new-message flash stays, an FX) |
| `MinimalScrollBar` | the scroll bar | T2 / H1 / S1 by the sweep (its mouse-away fade is the game's, left) |
| left as the game's | the resize grabber (`UI-ChatIM-SizeGrabber`), the dock's overflow arrow (`chat-tab-arrow`), the tabs' new-message glow / flash, the combat log's filter bar (`CombatLogQuickButtonFrame_Custom`), the social toast button | — |

## The damage meter (Modules/DamageMeterPanel.lua, 2026-09-21)

`DamageMeter` (Blizzard_DamageMeter, an Edit Mode system) and its session windows `DamageMeterSessionWindowN` with
their source / spell breakdown window. User's pick: **D1 = P1** (`kit_raw/dpsmeter_catalog.png`); on sight: the
header's controls and the bars' contents condensed into their plates. `/dmdump [n] [frames|reps]`. Covers
`damagemeter`.

| game art | where | kit piece |
|---|---|---|
| `damagemeters-background` (`MinimizeContainer.Background`, alpha = the meter's transparency setting) | a session window's body | L1: `frame` (single rail + stone) as the container's child ONE LEVEL UNDER the window (so the header plate, a region of the window, draws over the rail where they cross), its alpha following `SetBackgroundAlpha` (the transparency slider), collapsing with the container |
| `common-dropdown-bg` (the breakdown window's `Background`, keyed `DamageMeterSourceBackground`) | the source / spell breakdown window's body | L1 the same, at the session window's transparency |
| `ui-damagemeters-header-bar` (`Header`, 32 px) | the header band | `lists/header` as the window's regions; the timer, type / session dropdowns, settings cog and minimize button at 0.8 of their size, each centred on the band's line, the outer ones off the caps' gems (23 % of a header cap); the game's anchors restored on disable |
| `ui-damagemeters-bar-shadowbg` + `-shadowedge` (an entry's `StatusBar.Background` / `BackgroundEdge`) | every entry bar (list rows, the pinned local player row, the breakdown rows) | **P1** with `capOut`: the bracket as the bar's regions one layer above the fill, the caps OUTSIDE the bar's rect and the bar set in from the game's anchors by the arms — a StatusBar's fill cannot be re-anchored, so the bar itself ends where the gems begin; the trough under the fill; the name and value at 0.8 of the meter's text scale inside it; the icon square at the entry's height (the XML fixes it at 24 px whatever the bar height) |
| (fit, 2026-09-23) | every entry's bracket | the WHOLE bracket, gem caps included, is the row's height (`StripMixin:FitWhole`: the cap piece is 1.6x the mid's box, so fitted to the bar the caps stood ~5 px out of a 23 px row and the right one into the rail); the StatusBar is shortened to the opening at that scale and set in by the arms at that scale, from the game's own anchors, so SetBarHeight refits it (user: "scale down the artwork ... to fit") |
| the class icon (`GetClassAtlas`, a source entry's `Icon.Icon`) | the rows' icons | the painted class medallion (`MelloUI:ClassIconPath`) after the game's `UpdateIcon`; a spec icon, which the game prefers when it knows the spec, stays; no rim added (no border art there) |
| `ui-questtrackerbutton-collapse-all` / `-expand-all` | the minimize button | `buttons/minus` / `plus` following the atlas the game sets (the rule lookup is case-insensitive now: the client hands the canonical `UI-QuestTrackerButton-Collapse-All` back) |
| the settings dropdown's `Icon` (`common-dropdown-a-button-settings-shadowless`, keyed `DamageMeterSettingsIcon`) | the settings button | K2: the kit's cog in the glyph's place, the glyph faded (2026-09-23; laid under it, the two gears read as stacked) |
| the type dropdown's `Arrow` (`WowStyle1ArrowDropdownTemplate`, `hasShadow` false: the game re-atlases it through `common-dropdown-a-button-shadowless` / `-hover-` / `-pressed-` / `-open-` / `-disabled-shadowless`; keyed by hand on the first) | the "Damage Done" / "Healing Done" … dropdown | `state buttons/arrow_down`, natural size, in the arrow's place; hover and press from the button (user, 2026-09-23: **A** of `kit_raw/meter_arrow_catalog.png`, not K2, which would stand a second cog beside the settings cog) |
| `WowStyle2DropdownTemplate` (session: `common-dropdown-c-button`, sized 18 or 32 px in Lua for a short name) | the session dropdown | **B6** (`common-dropdown-b-button`: the single-rail band, tints for its states), claimed by the panel before the sweep, its hover arrow faded. Was D1 by the sweep until 2026-09-23: the plate's caps are wider than the button and it collapsed into a stub |
| `MinimalScrollBar` | the scroll bars | T2 / H1 / S1 by the sweep |
| left as the game's | the type dropdown's arrow button (`common-dropdown-a-button-shadowless`, undecided), the scale handles (functional grips), the "not active" text, the entries' texts and fills | — |

The hover effect (the resize grip and the scroll bar fading in) starts from each window's own `OnEnter`, which a cursor
landing on a row never fires (the rows take the mouse; the main window's poll only runs while a session timer is
live): every row's `OnEnter` hands it on to its window (`HandOnHover`).

## MelloUI's own services bar (Modules/Services.lua, 2026-09-22)

Not a game frame either: the bar under the minimap and its nearest-service menu. User's picks **SV1 SR2**
(`kit_raw/services_catalog.png`). The look goes with the minimap area of the reskin (`Kit:IsCovered("minimap")`),
the game's backdrop and tracking rims otherwise.

| part | kit piece (key) |
|---|---|
| the bar, the menu | **SV1**: `Professions-background-summarylist` (L1 box) on an invisible anchor, one level under the frame; the frame's own backdrop off |
| the icons | **SR2**: the kit's round rim (`Kit:Slot` kind `roundslot`), the button grown to the rim's size and the icon fitted into its opening (`SlotPlaceIcon`), the round mask kept; with "Round Icons" off the square R1 rim instead |

## MelloUI's own configurator (Core/Config.lua, 2026-09-21/22)

Not a game window: the kit skin lives inside Config.lua (`KIT`, `KitReplace`, `KitAnchor`) and is decided once, when
the window is built, from UI Modifications' reskin switch (a change shows after /reload). User's picks: **CT2** tiles,
**SI1** strip icons, **ST5** strip background, **SL1** slider, **CR4** rows, **SH3** sub-headings, **CA1** tabs
(`kit_raw/config_catalog*.png`); the rest are the fixed looks, through the existing keys.

| part | kit piece (key) |
|---|---|
| the window | `NineSlicePanelTemplate` (outer double rail with gems, outward) on an invisible anchor region; `UI-Background-Rock` (page stone) in place of the rock, inset by `Kit:OuterRailInset()` |
| the title band | `TitleBar` on the band's paint (`band.TitleText` = the title, `fitHeight` 20: a game window's title container, not the 40 px band); the window registers with the window mover |
| the close button | `RedButton-Exit` |
| the icon strip | **ST5**: `Professions-background-summarylist` (L1 box) at the strip's own level (one under it tied with the page stone and the dark body did not show); icons 57 px in **SI1** R1 rims (`UI-HUD-ActionBar-IconFrame` as regions of the icon's own frame, the hover handed on from the button), packed with an 8 px gap, centred, every icon's name under it (gold for the current page) |
| page header | R1 rim on the icon, the title in the kit's title face, description and status lines light with an outline (the dim grey drowned on the stone) |
| a page's tabs | **CA1** TB6 via `Kit:SkinPanelTab` (PanelTopTabButtonTemplate) |
| a section | L1 box (`Professions-background-summarylist`, level -1 under the section), rows set in by `SEC_INSET` |
| option rows | **CR4**: a faint band on every other row, `FriendsRowHighlight` (the plate's hover look) shown on the hovered row only |
| sub-headings | **SH3**: `GuildFrame-Header` (the header plate), the text past its gem cap |
| switches | the kit's check box (`Kit:SkinCheckButton`) |
| sliders | **SL1**: `_Minimal_SliderBar_Middle` (inputs/slider track) at the piece's own thickness (`fitHeight` from its box), `Minimal_SliderBar_Button` gem thumb, `Minimal_SliderBar_Button_Left/Right` arrow steppers |
| buttons, dropdowns | B1 red plates and D1 by `Kit:SweepControls` on the page |
| Home tiles | **CT2**: L1 box (level -1 under the tile), the R1 rim on the icon, the glow and IMPORTANT badge kept |
| left as they were | the window's scroll bar (the classic UIPanelScrollFrame bar; the kit's T2-H1-S1 needs the minimal one), the profile name box (InputBoxTemplate) |

## Deliberately left as the game's (no kit piece yet)

| game art | reason |
|---|---|
| PvP tab `RankProgressBarDisplay` (a radial Cooldown with `Honor-Bar-BG-Glow`, `Background`, `Bar`, `FactionBadge`) and `NextRewardLevel` | a radial progress dial; no kit equivalent |
| Blizzard's own hover on stat rows / headers | the kit's hover states cover rows; category plates have none, so the game's additive hover is faded, not replaced |

## Adding a mapping

1. Read the template in `%TEMP%\wowui-src` (Camelot file first, then Mainline): find the region, its atlas,
   its anchors (useAtlasSize? centred? a 1 × 1 holder frame?), and every method that shows / hides / re-skins it.
2. Add the atlas to `Kit.Replacements` with the kind that matches what the art *is* (a frame, a line, a plate,
   a rim), never what would look nicer.
3. In the module: `Kit:Replace(region, { as = "<atlas>", ... })`, mirror the game's state with post-hooks on the
   game's own methods, register the replacement for enable / disable.
4. Add the row here.
