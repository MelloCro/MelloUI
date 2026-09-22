<!-- Read-only review of 2026-09-22; line numbers are of that day. What was fixed is in CHANGELOG 0.13.4, what was left in HANDOVER section 0. -->

# HUD panels audit (MelloUI, read-only)

Scope: the 12 HUD/window panel modules + the `Kit.lua` entry points they use. Every `as = "..."` key in the 12 panels, plus the keys used by the Kit helpers they call (`SkinActionButton`, `SkinWindowShell`, `SkinPanelTab`, `SkinScrollBar`, `SkinSearchBox`, `SkinCheckButton`, `SkinInset`, `SweepControls`, `StateIconReps` atlases), resolves against `Kit.Replacements` (case-insensitively via `Kit:RuleFor`). No missing rules. Client facts below were checked against `%TEMP%\wowui-src`.

Verified non-issues (not repeated below): no OnUpdate scripts in any panel; all per-frame/per-sweep hooks are guarded (`melloRep`, `melloKit`, `melloToggle`, `melloIconHooked`, `melloDividerHook`, `melloChatSkinned`, `melloNoFade`, `skin.bars/status/party/targets`, `HookScrollBoxRows.melloKitHooked`); event registrations are cleared on disable (UnitFramePanel, DamageMeterPanel; the others register none); the mover grab frames are `EnableMouse(false)` until "Unlock the Windows" (UIModifications `SetUnlocked`), so nothing blocks clicks while locked; the tracker and damage-meter minimize buttons swap atlases through `normalTexture:SetAtlas` (Container.lua:267-275, Module.lua:791-799, DamageMeterSessionWindow.lua:880-885), so the `SetAtlas` post-hooks do fire; nameplate `UpdateAnchors` re-anchors `healthBar` from scratch each call (Blizzard_NamePlateUnitFrame.lua:676+), so the per-call inset there is correct.

## HIGH

### 1. UnitFramePanel.lua:924-927, 291-306 — module disabled in combat loses the bars' original anchors for good
`M:OnDisable` calls `Deactivate()` directly (no `InCombatLockdown` / `Kit:WhenOutOfCombat`), unlike `OnEnable` (918). `Deactivate` -> `UntuckBars` does `bar:ClearAllPoints()/SetPoint/SetSize` on `PlayerFrame...HealthBar`, `ManaBar`, the target/focus/pet/party bars. Those StatusBars inherit `SecureFrameParentPropagationTemplate` -> `SecureFrameTemplate protected="true"` (Blizzard_FrameXML/SecureTemplatesBase.xml:4-7; PlayerFrame.xml:171/253, TargetFrame.xml:140/213/448/486, PartyFrameTemplates.xml:150/241), so in combat the SetPoint is refused. The refusal is swallowed by the `pcall` at 295, but 302 still clears `bar.melloTuck` and 305 empties `tucked`: the saved anchors are gone, the bars stay tucked (re-anchored 2 px under a ring that is now hidden), and the next `Activate` (817-831 -> `RetuckAll` -> `TuckBar` 243-249) records the *tucked* geometry as the game's own. Same shape in `Kit.UnfitPortrait` calls (169-172, pcall'd, portrait `melloSaved` cleared inside `UnfitPortrait` only on success — fine) — the bars are the real loss.
Fix: `function M:OnDisable() eventFrame:UnregisterAllEvents(); Kit:WhenOutOfCombat(Deactivate) end`, and in `UntuckBars` clear `bar.melloTuck` / drop it from `tucked` only when the pcall returned true.

## MEDIUM

### 2. CastBarPanel.lua:55-56, 219-229 — stopping `InterruptSparkAnim` breaks the interrupted-cast fill
`ANIM_KEYS` includes `InterruptSparkAnim`; the `Play` post-hook calls `a:Stop()` at once. The client's bar relies on that animation's `OnFinished` (`CastingBarAnim_OnInterruptSparkAnimFinish` -> `ApplyInterruptFilledState`: `SetValue(maxValue)`, `UpdateCastTimeText`, `HideSpark`; CastingBarFrame.xml:183, CastingBarFrame.lua:565-571, 669-678 — "an interrupted cast bar does not fill immediately but rather waits for the InterruptSparkAnim to finish"). `Stop()` fires OnStop, not OnFinished, so an interrupted cast leaves the bar at the interrupted value with the red pip spark showing until the bar hides. The spark is not in `FX_KEYS` (nothing of it is faded), so there is no reason to stop it.
Fix: remove `"InterruptSparkAnim"` from `ANIM_KEYS` (or, if kept, call `a:GetParent():ApplyInterruptFilledState()` after `a:Stop()`).

### 3. NameplatePanel.lua:147-172 — health-bar inset is never restored and is applied cumulatively
`rep.onDisable` (147-157) only resets the strip's vertex colour; the `hb` points shifted by `InsetHealthBar` (91-100) are left shifted when the module goes off. On the next enable, `Activate` (229-231) -> `rep:Enable()` -> `onEnable` (164-169) -> `InsetHealthBar` reads the *already inset* points and insets again: the bar shrinks by `armL + armR` per off/on cycle until the game's next `UpdateAnchors`. The same double application happens within one `Activate` for any plate skinned during `Build` (line 171 insets, then the 229-231 loop's `Enable` insets again). Contrast TooltipPanel.lua:63-103, which saves `bar.melloInset` once, skips when set, and restores on disable.
Fix: save the game's points once in `hb.melloInset`, return early when set, clear it in the `UpdateAnchors` hook (159-162; the game re-anchors there), restore from it in `onDisable`.

### 4. BackpackPanel.lua:116-123 and SocialPanel.lua:208-218 — `RingDisc` enable/disable wrappers overwritten; the dark disc stays behind when the module is off
`Kit:RingDisc(ring, ...)` chains `ring.onEnable`/`ring.onDisable` to `disc:Show()`/`disc:Hide()` (Kit.lua:2830-2842). Both panels then assign `ring.onEnable = Fit` and `ring.onDisable = function() ... UnfitPortrait ... end` (Backpack 120-123, Social 215-218) *after* the `RingDisc` call, discarding the disc's wrappers. Result: `disc` is shown once at creation (`disc:SetShown(ring.object:IsShown())`) and never hidden again — after "Backpack Kit" / "Social Panel Kit" is switched off, a grey round disc remains in the portrait corner of the bag / social window over the game's own art; on re-enable it is not re-fitted.
Fix: call `Kit:RingDisc` *after* assigning `ring.onEnable`/`onDisable` (it chains whatever is there), or chain manually.

### 5. TrackerPanel.lua:366-377 (with 61-74) and DamageMeterPanel.lua:499-513 (with 243-256) — minus and plus plates both shown after an off/on cycle
`Kit:StateIconReps` creates one `state` rep per atlas seen on the minimize button and shows only the current one (Kit.lua:2675-2692). `Deactivate` hides all reps; `Activate` then calls `rep:Enable()` on every rep, and `ReplacementMixin:Enable` does an unconditional `self.object:Show()` (Kit.lua:1705). Nothing re-selects by the current atlas until the game's next `SetAtlas`, so a button that has been toggled at least once shows the minus *and* the plus plate on top of each other after the module is re-enabled (tracker header, every module header, the meter's minimize button).
Fix: in `SkinToggle`, wrap the first rep's `onEnable` to re-run `Kit:StateIconReps(button, normal, button, Replace, extra)`, or after the enable loop in `Activate` iterate the toggled buttons and call it.

## LOW

### 6. CastBarPanel.lua:138-153, 304-306 — `Widen` clears the saved width even when the restore failed
Same pattern as #1 in miniature: `Widen` runs in a `pcall`, then 152 sets `bar.melloNarrow = nil` unconditionally; `OnDisable` is unguarded. If `SetWidth` on `TargetFrame.spellbar` / `FocusFrame.spellbar` (children of the protected TargetFrame; the panel already routes its own `Narrow` through `WhenOutOfCombat`, 196) is refused in combat, the bar stays narrowed and the next enable saves the narrowed width as the game's width, narrowing again. Fix: `Kit:WhenOutOfCombat(Deactivate)`; clear `melloNarrow` only on a successful pcall.

### 7. Incomplete secret guards on anchor-point returns
The code treats `GetPoint` x/y as possibly secret but then compares / string-ops the *point name* unguarded:
- UnitFramePanel.lua:653 `point ~= "TOPLEFT"` (party frames, where "every size reads secret" per HANDOVER §0),
- NameplatePanel.lua:94-97 `point:find("LEFT")`,
- TooltipPanel.lua:84-87 `point:find("LEFT")`,
- DamageMeterPanel.lua:144-146 `point == "LEFT"`.
A secret string there throws inside the party `InitializePartyMemberFrames` hook / `UpdateAnchors` hook / `OnShow` hook. Also BackpackPanel.lua:70: `math.abs(bb - ab)` on `GetTop` results that were pcall'd but not `Secret`-checked (only `al`/`bl` are). Fix: add `Secret(point)` to the guards; check `ab`/`bb`.

### 8. DamageMeterPanel.lua:447-452 — grab frame relies on creation order at an equal frame level
The mover's grab is placed at `box:GetFrameLevel()` "made after it" so it sits above the ScrollBox's stone but under the rows. WINDOW-RULES §5 states same-level order may change between loads; if the client draws the box above the grab, the mouse-enabled box takes the drag and the meter cannot be moved while unlocked (the bug this code was written to fix). Fix: give the grab `box level + 1` and the rows are already at `box level + 1`? — rows keep their clicks only if above; so instead re-level the grab to `box + 1` and raise the rows' level by one in `SkinEntry`, or parent the grab under the box at a strata below and let `EnableMouse` decide.

### 9. UnitFramePanel.lua:872-893 / 579-594 — art-swap and classification hooks refit every bar rep of every frame
Each `PlayerFrame_UpdateArt` / `CheckClassification` call queues a refit of all `bar` reps, all names, all covers across player/target/focus/pet/party. Bounded by game calls, no OnUpdate, so not a throttle problem — noted only because `CheckClassification` runs on every target change in a fight and the queue (`Kit.combatQueue`) grows one closure per call while in combat, all executed at `PLAYER_REGEN_ENABLED`. Fix (optional): coalesce with a `pending` flag before queueing.
