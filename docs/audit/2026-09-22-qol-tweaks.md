<!-- Read-only review of 2026-09-22; line numbers are of that day. What was fixed is in CHANGELOG 0.13.4, what was left in HANDOVER section 0. -->

# MelloUI QoL modules audit (read-only)

Scope: `Modules/Chat.lua`, `Nameplates.lua`, `Tooltip.lua`, `UnitFrames.lua`, `ClassIcons.lua`, `BarTextures.lua`, `BarText.lua`, `CooldownText.lua`, `Media/ClassIcons.lua`, plus the folding in `UIModifications.lua` (TWEAKS / Want / OnInit) and `Kit:IsCovered`. All paths relative to `F:\Download-Backup\Project Web\MelloUI`.

Lifecycle fact that several findings depend on (`Core/Core.lua:297-320`, `:350-356`): `SetModuleEnabled(false)` sets `module.isEnabled = false` and calls `OnDisable`, but `module.db` (set in `OnInit`) is never cleared. A callback that only checks `M.db.<key>` keeps acting after the module is switched off.

## High

### 1. ClassIcons keeps replacing portraits after it is disabled, and never restores them
`Modules/ClassIcons.lua:120`, `:177`, `:194`, `:208` gate only on `M.db and M.db.portraits` / `M.db.pvpFlag`, never on `M.isEnabled`; `OnDisable` (`:239-243`) is empty and its comment ("disabling the module ... just makes them no-ops") is false because `M.db` survives disable (see above). Inputs: user turns off "Class medallions" on the UI Modifications page (or disables UI Modifications) -> every later `SetPortraitTexture` / `UnitFramePortrait_Update` / `PlayerFrame_ShowPvPIcon` still swaps in the medallion. Portraits already replaced (`texture.melloClassIcon`, `:112`) and the PvP icon (`:219`) are also left as-is. `M:RefreshPortraits` (`:132`) likewise ignores `isEnabled`.
Fix: add `M.isEnabled` to every gate (`TryReplacePlayerPortrait`, the three hooks, `RefreshPortraits`); in `OnDisable` iterate textures tagged `melloClassIcon`, clear the tag and re-call `SetPortraitTexture(texture, unit)` (pcall) for the unit-frame portraits, and re-run the PvP icon through `PlayerFrame_ShowPvPIcon`'s normal path by leaving the atlas to Blizzard (at minimum `icon:SetAtlas` of the original, captured before `:219`).

### 2. Chat replaces a Blizzard function outright
`Modules/Chat.lua:349`: `ChatFrameUtil.ResolvePrefixedChannelName = function(...)` overwrites Blizzard's method (the header comment `:13` calls this "wrapped"). This is the one "never replace Blizzard methods" violation in the set; Blizzard's chat formatting then runs through addon code on every channel message, and the replacement is never removed on disable (`:478-487`), only short-circuited via `Active("shortChannels")`.
Fix: drop the replacement. Short numbered-channel tags can be produced from the `addMessageObserver` / `TransformMessages` path that already exists for bracket stripping (`:380-391`): match `|Hchannel:channel:%d+|h[%d. name]|h` in the added line and rewrite it there; or, if `ChatFrameUtil` exposes a filter/registration API on this client, use that.

### 3. Nameplates calls Blizzard layout functions and moves nameplate frames with no combat guard
- `Modules/Nameplates.lua:138` and `:239` call `cc:Layout()`; `:247` calls `unitFrame:UpdateAnchors()` (pcall'd, but still a Blizzard layout/rebuild call). `:134-136` also writes Blizzard's layout field `cc.fixedHeight`.
- `:115-121` (`AnchorCC`: `ClearAllPoints`/`SetPoint` on `CrowdControlListFrame` and `LossOfControlFrame`), `:132` and `:145` (`SetScale`), `:323-327` (quest icon `SetSize`/`SetPoint`) run from `NAME_PLATE_UNIT_ADDED` (`:398-405`), the `RefreshList`/`RefreshLossOfControl`/`UpdateAnchors` hooks (`:164-195`) and `OnSettingChanged`/`OnDisable` (`:458-481`), all of which fire in combat; there is no `InCombatLockdown()` anywhere in the file.
Effect: in combat every aura refresh re-anchors/re-scales nameplate children from addon code; with the client's protected nameplate layout this is exactly the class of call the project rules forbid.
Fix: remove the `Layout()`/`UpdateAnchors()` calls (let Blizzard's own next refresh lay out; the `fixedHeight` write is enough for the CC list), and route `AnchorCC`, `ResizeCCList`, `ResizeLossOfControl`, `GetQuestIcon` and `RestoreAll` through `Kit:WhenOutOfCombat` (`Modules/Kit.lua:1425`) or an explicit `if InCombatLockdown() then return end` with a PLAYER_REGEN_ENABLED re-run.

## Medium

### 4. BarTextures restore path never restores bar colours
`RestoreBar` (`Modules/BarTextures.lua:359-373`) only puts the texture back; `originals[bar]` (`:179-197`) stores no colour. Colours the module itself applied stay on the pre-coloured Blizzard atlases after `OnDisable` (`:902-909`) or a group toggle off (`:926`):
- power bars: `RecolorManaBar` (`:585`) sets the power-type colour; Blizzard expects white on its atlas (comment `:577-578`) -> restored mana/rage bars are tinted until the next `UnitFrameManaBar_UpdateType`.
- XP/reputation/honour: `:350`, `:763` set purple/green/orange; restored atlases are double-tinted.
- cast bars: `RecolorCastBar` (`:646-648`) sets yellow; restored atlases are double-tinted.
- health bars without `lockColor` (all nameplate `healthBar`s, some unit frames): `ResetHealthColors` (`:560-566`) only whitens `lockColor` bars; class/reaction colour stays on nameplates. Blizzard's `CompactUnitFrame_UpdateHealthColor` compares against its cached `healthBar.r/g/b`, which the module never touched, so it will not re-issue `SetStatusBarColor` until the wanted colour changes.
Fix: in `RememberOriginal` also store `bar:GetStatusBarColor()` (when not secret); in `RestoreBar` re-apply it, and for tracked health bars additionally clear Blizzard's cache (`bar.r, bar.g, bar.b = nil`) so its next update recolours.

### 5. BarTextures: threat/class precedence is inconsistent when "Colour Overrides Threat" is off, and switching back to green leaves nameplates coloured
- With `overrideThreat = false` the `SetStatusBarColor` hook (`:545-550`) correctly stands aside, but `ApplyNamePlateUnitFrame` (`:696`) still calls `RecolorHealthBar` on every `NAME_PLATE_UNIT_ADDED` (`:806-810`) and every `UpdateAnchors` post-hook (`:706-710`), and the `UnitFrameHealthBar_Update` hook (`:836-838`) does the same on every health event for unit frames. So the class/reaction colour is re-applied after Blizzard's threat colour anyway on every relayout / health tick; the option's "Off: the game's threat colours show" only holds between relayouts.
- `RecolorHealthBar` returns early for nameplates when `healthColor == "green"` (`:529-531`), so changing `healthColor` class -> green (`OnSettingChanged`, `:938-939`) leaves the last class colour on every visible nameplate (Blizzard will not recolour, see finding 4).
Fix: gate the `:696` / `:836` calls on `M.db.overrideThreat` (apply the colour once at first apply, then leave it to the hook), and on green for nameplates set Blizzard's colour back (clear `healthBar.r/g/b` and let its next update run, or call `SetStatusBarColor(1,1,1)` when the texture is `default`).

### 6. BarTextures "Default (Blizzard)" texture still tints the pre-coloured atlases
With `texture = "default"` (`:42`, `:255-261`) the game's own green health atlas stays, yet `RecolorHealthBar` (`:533`) still applies `HealthColorFor` (green mode -> `0,1,0`, `:516`; class mode -> class colour) and `RecolorManaBar` (`:585`) applies the power colour. A colour multiplied onto an already-coloured atlas gives a darker/muddy bar (class colours become class x green). The option text (`:86`) says the module colours *flat* textures.
Fix: in `RecolorHealthBar` / `RecolorManaBar` / status-bar and cast-bar recolour, when `M.db.texture == "default"` set `1,1,1` (Blizzard's expectation) instead of the derived colour, or skip.

### 7. Tooltip writes the "default" sentinel as a texture path
`Modules/Tooltip.lua:206-211`: `wanted = textures.texture` then `bar:SetStatusBarTexture(wanted)`. When BarTextures' texture is `"default"` (a valid choice, `BarTextures.lua:42`) the tooltip health bar gets the file path `"default"` -> blank bar whenever "Hide Health Bar" is off and "Use Bar Texture" is on.
Fix: `if wanted == "default" then wanted = nil end` before `:210`.

### 8. UIModifications forces the Fonts module on although it is off by default
`Modules/UIModifications.lua:84-90` sets `defaults["qol_" .. name] = true` for every TWEAKS entry, and `Apply` (`:602-607`) then calls `Want("Fonts", true)` on every login, overwriting `MelloUI.db.enabled.Fonts`. `Modules/Fonts.lua:133` declares `enabledByDefault = false` and `README.md:216` says "Fonts (off by default)". Result: a fresh profile gets the interface font replaced.
Fix: add a default field to the TWEAKS rows (e.g. `{ "Fonts", ..., default = false }`) and use `defaults[key] = tweak.default ~= false`.

### 9. UnitFrames touches unit-frame geometry with no combat guard
`Modules/UnitFrames.lua` has no `InCombatLockdown()` at all. `CenterName`/`RestoreName` (`:92-95`, `:103-110`) `ClearAllPoints`/`SetPoint`/`SetWidth` on `PlayerName` and the target/focus `Name`; `SetHidden` (`:65-68`) reparents `FrameFlash`/`Flash`/`StatusTexture` between `PlayerFrame` and a hidden frame. These run from the `PlayerFrame_UpdatePlayerNameTextAnchor`, `PlayerFrame_ToPlayerArt`, `PlayerFrame_ToVehicleArt` post-hooks (`:273-289`, fired when entering/leaving a vehicle in combat), from `OnSettingChanged`/`OnDisable` (`:324-331`) and from the `Kit:OnCover` callback (`:315-319`, fired when the unit-frame reskin is toggled).
Fix: wrap `ApplyAll`, `ApplyNames` and `ApplyGlows` in `Kit:WhenOutOfCombat` (or bail on `InCombatLockdown()` and re-run at PLAYER_REGEN_ENABLED), as UnitFramePanel does.

## Low

### 10. Nameplates `RestoreAll` does arithmetic on a value the module itself treats as possibly secret
`Modules/Nameplates.lua:97-100` guards `auras.auraItemScale` with `IsPlainNumber`, but `RestoreAll` (`:233`, `:236`, `:243`) uses `auras.auraItemScale or 1` unguarded, including `(auras.auraItemScale or 1) * BASE_ITEM_SIZE` (`:236`). If the value is secret (the reason for the guard at `:98`), disabling the tweak or turning off `bigCC` throws on that plate and the remaining plates are not restored.
Fix: reuse `IsPlainNumber(auras.auraItemScale) and auras.auraItemScale or 1`.

### 11. CooldownText: the shared-metatable hook reads a forbidden nameplate cooldown's fields
`Modules/CooldownText.lua:321-338` hook every `Cooldown` object's `SetCooldown`/`Clear`; `StartTimer` -> `Category` (`:95-120`) reads `cooldown.noCooldownCount`, `cooldown:GetParent()`, `parent.cooldown`, `frame:GetName()` with no `IsForbidden` check and no pcall, and `StopTimer` (`:144-158`) indexes `timers[cooldown]` and calls `SetHideCountdownNumbers`. The other nameplate modules (`Nameplates.lua:200`, `BarTextures.lua:688`) guard forbidden plates; here a forbidden plate's aura cooldown raises inside Blizzard's aura refresh. Only reachable if this client forbids nameplates (the modules assume it can).
Fix: first line of `StartTimer` and `StopTimer`: `if cooldown.IsForbidden and cooldown:IsForbidden() then return end`.

### 12. Chat `OnDisable` re-anchors the edit box even when it was never moved
`Modules/Chat.lua:483` calls `SetEditBoxOnTop(false)`, which always `ClearAllPoints` and re-anchors with guessed offsets (`:182-184`), replacing Blizzard's own anchors (right edge tied to `frame.ScrollBar` instead of the frame) even if `editBoxTop` was already off.
Fix: remember the edit box's original points on first move (as `UnitFrames.RememberName` does) and only restore those when the tweak was applied.

## Checked and found sound
- No recursion in the colour/texture hooks: `BarTextures` `applying` (`:262-265`, `:334`) and `recolouring` (`:532-534`, `:546`) flags, `Tooltip` `applyingBarColor` (`:149-151`, `:269`), `CooldownText` `hidingNumbers` (`:124-126`, `:340`), `UnitFrames` band hook calls `SetAlpha` not `SetVertexColor` (`:162-166`).
- No growing hook chains on recycled frames: all per-frame hooks are keyed in weak tables or a frame flag (`Nameplates.lua:60-61`, `BarTextures.lua:166-172`, `:541-544`, `:638`, `:685`, `:775`, `BarText.lua:130`, `CooldownText.lua` metatable once).
- Secret-value reads in `BarText.ReadBar`/`SetRawValue`, `Nameplates.ComputeOffset`/`IsQuestTarget`, `Tooltip.UnitColorFor`, `BarTextures.HealthColorFor`/`RecolorManaBar`/`SetTexture`/`StatusTrackingColorForAtlas`, `CooldownText.StartTimer`/`UsableWidth`/`SetHideCountdownNumbers` and `ClassIcons.SafeValue` are guarded (pcall or `issecretvalue`).
- Timers/OnUpdate stop on disable: `CooldownText` driver hidden (`:372`), `Nameplates` rescan timer checks `QuestActive()` (`:381`).
- `Kit:IsCovered` gating is applied where the TWEAKS descriptions promise it: Chat art (`Chat.lua:65-72`, re-run from `Kit:OnCover`), Tooltip backdrop (`Tooltip.lua:94`), UnitFrames names (`UnitFrames.lua:122`, re-run on uncover). Kit's fade (`Kit.lua:1645-1667`) survives the tweak modules' `SetShown(true)`/`SetAlpha(1)` restore calls, so those restores cannot un-fade a covered region.
