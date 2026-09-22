<!-- Read-only review of 2026-09-22; line numbers are of that day. What was fixed is in CHANGELOG 0.13.4, what was left in HANDOVER section 0. -->

# Audit: Kit library + window panels (read-only)

Scope: `Modules/Kit.lua`, `Media/KitLayout.lua`, `Modules/{Character,GameMenu,Professions,SpellBook,Legacy,QuestLog,Guild,GroupFinder,Collections}Panel.lua`, against `docs/WINDOW-RULES.md` / `docs/HANDOVER.md` §0. Every line read. All 288 `Kit.Replacements` keys were cross-checked against every `as = "..."` literal in the ten files: **no missing or case-only keys**. Hook-once guards (`hooked`, `melloRep`, `melloKitHooked`, `melloIcons`, `melloStates`, `melloGlyphs`) hold in every module; no per-frame `OnUpdate` sweeps exist (the spell book's `PagedContentFrameBaseMixin.Event.OnUpdate` is a content-update event, not a frame tick). No `SetScript` on a Blizzard `OnShow`/`OnSizeChanged` was found (all `HookScript`; the `SetScript` calls are on kit-owned frames). No `InCombatLockdown` issue is traceable: none of these windows' touched frames are protected.

Findings, ranked.

## HIGH

### 1. GameMenuPanel: turning the module off does not restore the game menu
`Modules/GameMenuPanel.lua:212-222`, `:65-75`, `:97-131`, `:227-237`
- `Activate` hides `GameMenuFrame.Border` / `.Header`, fades them, and installs `hooksecurefunc(part, "Show", function(self) self:Hide() end)` (line 219) with **no `active` check**. After `OnDisable` (→ `Deactivate`, which only restores the frame size, lines 233-236), every later `Border:Show()` / `Header:Show()` by the game is immediately undone: the stock menu comes back with no border and no header until `/reload`.
- `Fade()` (65-75) is a one-way SetAlpha-0 hook with no unfade path; `DressButton` (97-131) fades every button texture, swaps the highlight texture, changes the font object and shadow, and hooks `UpdateButton` to keep the slices at alpha 0 — none of it is reverted. Buttons also keep the absolute `SetPoint`/`SetSize` from `Arrange` (170-178).
- Effect: reskin off → game menu still shows MelloUI's button layout/fonts on the stock art with the frame art missing.
- Minimal fix: in the `Show` hook and in `Fade`'s SetAlpha hook and the `UpdateButton` hook, early-return unless `active`; in `Deactivate` call `SetAlpha(1)` on everything faded, `Border:Show()` / `Header:Show()`, restore each button's saved points/size/font object/highlight (save them in `DressButton` before changing). (Also note this module still violates WINDOW-RULES §0 / law 1: it paints its own sheet and relays the buttons; docs say such a module is reduced to "touches nothing" first.)

## MEDIUM

### 2. ProfessionsPanel: portrait fit permanently disabled when activated before the frame is laid out
`Modules/ProfessionsPanel.lua:734-749`, `:1028-1034`
- On `ADDON_LOADED` for `Blizzard_Professions` the module calls `Sync()` → `Activate()` → `ApplyPortrait()` → `FitPortrait()` while `ProfessionsFrame` has never been shown. `portrait:GetCenter()` returns nil (UIPanel not yet anchored), but `portraitSaved` is still written with `cx = nil` (line 741-742) and is never re-taken (`if not portraitSaved`). Every later call hits `portraitSaved.cx == nil` (line 745) and skips: the icon is swapped to the kit piece but never sized to the medallion (WINDOW-RULES 2b). `UnfitPortrait` then restores a size/points captured from an unlaid-out frame.
- `CharacterPanel.lua:402-411` has the same pattern but is only reached from `OnShow`/`IsShown()` paths, so it is latent there.
- Fix: return early without saving when `cx`/`px` is nil (as `Kit:FitPortrait` at `Kit.lua:2963-2967` already does), or replace both local copies with `Kit:FitPortrait`/`Kit:UnfitPortrait`.

### 3. ProfessionsPanel: disable can leave the kit icon file on the game's portrait
`Modules/ProfessionsPanel.lua:785-798`, `:1019-1024`
- `RestorePortrait` only re-sets the texture when `lastAsset` is known, and `lastAsset` is filled solely by the `SetPortraitToAsset` post-hook installed in `Hook()`. If the module is enabled while the window already exists (e.g. reskin switched on at runtime after the window was opened), no asset has been seen; on disable the portrait keeps `Media/Kit/icons/profession_*` with `SetTexCoord(0,1,0,1)` (the whole power-of-two file, icon in its top-left 75 %) until the game next calls `SetPortraitToAsset`.
- Fix: in `ApplyPortrait`, before the first `Kit:Apply`, record the current texture (`pcall(portrait.GetTexture, portrait)`) as the fallback for `lastAsset`; or force a `pf:Refresh()`-equivalent through the game's own path is not allowed, so store the file id.

## LOW

### 4. Progress-bar fills shrink on every disable→enable cycle
- `Modules/CharacterPanel.lua:708-746` (`FitFill` / `RestorePoints`): `RestorePoints` puts back points and height but not width; on the next `rep.onEnable` → `FitFill`, `pct = fw / w` is computed from the already-scaled width, so the fill is scaled by `openW / w` again. Each toggle of the module (or of the umbrella reskin switch) narrows the fill until the game next calls `SetFillWidth`.
- `Modules/GuildPanel.lua:193-224` (`FitFill` reads `fw / maxBar` from the scaled width; `onDisable` restores points/height only): same.
- `Modules/ProfessionsPanel.lua:142-153`, `:160-170`: the mask width is scaled by `share` in `Fit` and not restored on disable; `melloScaled` is cleared, so the next enable scales it by `share` again (`share²`).
- Fix: save the fill/mask width with the points and restore it in `onDisable`; or remember the game's last unscaled value (from the `SetFillWidth` / `SetWidth` post-hook) and compute `pct` from that instead of from the current width.

### 5. Kit:Replace vstrip fallback path is broken (currently unreachable)
`Modules/Kit.lua:2223-2227`
- When the thumb has no `OnButtonStateChanged`, `FollowButton(strip, button)` is used. `Slot_Update` then indexes `rim.button` (never set on the VStrip: line 2215 sets `rep.button`, not `strip.button`) → nil index on the first `OnEnter`; and `Kit:Apply(rim, rim.base .. "_" .. state)` would be called on a Frame. Every current `MinimalScrollBar` thumb carries `ButtonStateBehaviorMixin`, so the branch is not hit today.
- Fix: replace the `else` branch with `rep:SetState()`-driven `HookScript`s on the button (`OnEnter`/`OnLeave`/`OnMouseDown`/`OnMouseUp` → `rep:SetState()`), or set `strip.button = button` and give VStrip its own `Update`.

### 6. SpellBookPanel: top-tab label anchors are not put back on disable
`Modules/SpellBookPanel.lua:134-142`
- `Follow` re-anchors `tab.Text` to the kit strip's `mid` texture and sets `SetJustifyH("CENTER")` on every `SetTabSelected`; `Deactivate` does not restore them. The text stays anchored to a hidden kit region until the game's next `SetTabSelected` re-points it (it does, so this self-heals on the next tab click, but the window opens once with the label off its stock place). `Kit:SkinPanelTab` (`Kit.lua:3193-3214`) uses a `SetPoint` post-hook that steps aside when the plate is hidden; the spell book's local copy should do the same or save/restore the point like the TitleBar rule does (`Kit.lua:2057-2089`).

### 7. Kit:TitleFont retry counter never resets
`Modules/Kit.lua:95-104`
- `fs.melloFontTries` is only cleared on a successful `SetFont`. If the font file was not readable in the first 8 attempts of a session (loading), a later disable→enable of the window module never retries: the title keeps the game's face. Fix: reset `melloFontTries` in the `on == false` branch (line 106-110).

### 8. SpellBookPanel: dynamic page key may not resolve
`Modules/SpellBookPanel.lua:315`
- `Replace(tex, { as = Kit:ArtKey(tex) or "spellbook-Page-Right-C60" })` passes whatever atlas `BookBGHalved` / `BookBGLeft` / `BookBGRight` currently carry; only `spellbook-Page-Left-C60` / `-Right-C60` are mapped. If `BookBGHalved` is a different atlas (e.g. a `-Halved-` variant) it yields a "no kit piece mapped" notice and no page on that texture — not a crash, but the parchment would be missing in the halved layout. Verify with `/sbdump`; if so, add the atlas to `Kit.Replacements` (same rule).

## Checked and clean (for the record)
- Secret values: every size/position read in these modules is on window-side frames; the shared library guards the reads that can be secret (`Retile`, `Refit`, bar `GetOpening`, `BracketLayers`, `DumpWindow`). No secret comparison/arithmetic is reachable from these ten modules.
- Hook growth: `Kit:Replace`'s `rect:HookScript("OnSizeChanged")` (Kit.lua:1995) and the button hooks in the frame/strip/slot kinds are installed once per (frame, rule-key) pair everywhere they are called; `QuestLogPanel.lua:261-270` re-hooks `OnEnter`/`OnLeave` on every row `Init`, but `QuestListPanel.lua:212-213, 241-242` `SetScript`s those handlers on every `Init`, which drops the previous hooks, so the chain does not grow.
- Restore paths in Character, Professions (bar above aside), SpellBook (tab text aside), Legacy, QuestLog, Guild, GroupFinder, Collections disable every rep, unfit portraits, and undo insets/points they changed.
- No Blizzard method is replaced; only kit-owned frames' `Show`/`Hide` are wrapped (`NineSlice`/`Strip` owner mode, bar strip).
