<!-- Read-only review of 2026-09-22; line numbers are of that day. What was fixed is in CHANGELOG 0.13.4, what was left in HANDOVER section 0. -->

# Audit: Quest List / Route / Services (MelloUI)

Scope read in full: `Modules/QuestList.lua`, `Modules/QuestListPanel.lua`, `Modules/QuestListMap.lua`, `Modules/QuestListPins.xml`, `Modules/Route.lua`, `Modules/Services.lua`; headers of `Media/QuestListData.lua`, `Media/RouteData.lua`, `Media/RoadData.lua`; README sections Quest List, Route, Services, Slash commands, Settings storage; `Core/Core.lua` + `Core/Backup.lua` for the contracts the modules rely on.

Verified clean (no finding): every field index the code uses matches the data rows. Scripted count over `QuestListData.lua`: quests 5163/5163 rows have 27 fields (code uses 1–27), entrances 45/45 have 9, transports 25/25 have 13, services 946/946 have 7, taxiNodes 72/72 have 5, taxiPaths 294/294 have 3. `F_ENDER` is `""` (never nil) on 220 rows, `F_GIVER` `""` on 422 — both handled. Secret-value reads from unit/quest/map APIs are consistently wrapped in `Plain()`/`IsSecret()` (one exception, item 9). No Blizzard method is replaced (only `hooksecurefunc`/`HookScript`), no Blizzard layout function is called, no secure frame geometry is touched. Map pins are acquired/released only through `map:AcquirePin` / `RemoveAllPinsByTemplate` and `RemoveAllData` runs before every refresh and on disable — no pin leak. `Tools/bake_routes.py` does round-trip `pins` (entrances/transports/services), so `/qlmap` pins and remembered services survive through the baker as designed.

## Medium

### 1. Route: disabling the module stops the graph and all recorded pins from being saved
`Modules/Route.lua:2433` — `OnDisable` calls `eventFrame:UnregisterAllEvents()`, which drops `PLAYER_LOGOUT`; `MelloUIRoutes = LearnedOnly()` runs only in that handler (`Route.lua:2194-2195`). `live.pins` is written to by Quest List (`QuestList.lua:129-143` via `R:Pins()`, no `isEnabled` check) and Services (`Services.lua:243-248`) whether or not Route is enabled.
Inputs → effect: user disables Route (or has it off) and later records `/qlmap dock|entrance`, opens a service window, or has breadcrumbs from earlier in the session → at `/reload`/logout nothing is written → the baker never sees it → lost.
Fix: register `PLAYER_LOGOUT` at file load (outside `OnEnable`) and never unregister it, or write `MelloUIRoutes = LearnedOnly()` in `OnDisable`.

### 2. Quest List: 3-second ticker and event handlers keep running after disable
`Modules/QuestListMap.lua:646-651` — `outsideTicker = C_Timer.NewTicker(3, QL.RememberOutside)` is never cancelled; `Modules/QuestList.lua:899-906` `OnDisable` does not cancel it and does not unregister the events registered at `QuestList.lua:883-894` (`hooked` is one-shot).
Inputs → effect: module disabled → every 3 s `C_Map.GetBestMapForUnit` + `GetPlayerMapPosition` still run; on `PLAYER_ENTERING_WORLD` `QL.LearnEntrance()` (`QuestListMap.lua:658`, no `M.isEnabled` check) still writes learned entrances into the Route pin store and prints `MelloUI:Notice` lines; the handler at `QuestList.lua:844` still schedules panel/pin refreshes on every quest-log update.
Fix: in `OnDisable` do `outsideTicker:Cancel(); outsideTicker = nil` and `eventFrame:UnregisterAllEvents()`; move the registrations into `OnEnable` unconditionally (drop `hooked` for events, keep it only for the `hooksecurefunc`).

### 3. Route: `SetDestinationTo(..., pin=true)` marks the destination as a waypoint even when no waypoint was placed → cleared within 1 s
`Modules/Route.lua:1402` sets `fromWaypoint = pin and true or nil` before the attempt at `1403-1411`, which is skipped when `CanSetUserWaypointOnMap` is false, `C_Map.SetUserWaypoint`/`UiMapPoint` is missing, or the `pcall` fails. The 1 s tick (`Route.lua:2220`) then runs `ReadWaypoint` (`1304-1311`): `HasUserWaypoint()` false + `destination.fromWaypoint` → `destination = nil`, route and arrow vanish. If `C_Map.HasUserWaypoint` is nil (`1300-1302`) the fall-through to `ReadTrackedQuest` (`1255` does not early-return for `fromWaypoint`) overwrites the pin with the tracked quest instead.
Callers affected: `QL.RouteToPoint` (`QuestList.lua:709-716`, entrances/docks/flight masters) and Services `GoTo` (`Services.lua:344`) — neither checks the waypoint API first (QuestList `SetWaypoint` at `676-681` does).
Fix: set `destination.fromWaypoint = true` only after `pcall(C_Map.SetUserWaypoint, ...)` returned ok (and, if available, `C_Map.HasUserWaypoint()` is true); otherwise leave it nil so the destination lives until `Clear()`/arrival.

## Low

### 4. Route: `/route arrow reset` is undone by the macro backup on the next restart
`Modules/Route.lua:2264` sets `M.db.arrowX, M.db.arrowY = nil, nil` directly. Backups are written only from `MelloUI:ScheduleBackup` (`Core/Backup.lua:373`), which runs on `NotifySettingChanged`/`SetModuleEnabled`/profile changes — there is no logout backup. Saved variables are not read back on this client, so on restart the macro restores the old `arrowX/arrowY` (`Core/Backup.lua:162-170` serialises any key that differs from defaults).
Fix: `MelloUI:NotifySettingChanged(M.name, "arrowX", nil); MelloUI:NotifySettingChanged(M.name, "arrowY", nil)` (this also calls `PlaceArrow` through `OnSettingChanged`).

### 5. Route: `/route reset confirm` also discards the traced roads and corrupts the `/route` counts
`Modules/Route.lua:2268` replaces `live` with an empty graph, but the traced roads from `MelloUI_RoadData` were merged into the same `live.graphs` (`MergeRoads`, `467-512`) and `tracedNodes` is not reset. Effect: no road routing for the rest of the session (README says the traced roads are not part of the learned data), and `/route` prints `nodes - tracedNodes` (`2312-2313`) as a negative number. `graphVersion` is not bumped either, so `buckets`/`hubLinks` (`807`, `865`) keep keys of deleted nodes until the next breadcrumb.
Fix: after the reset do `tracedNodes = 0; graphVersion = graphVersion + 1; if type(MelloUI_RoadData) == "table" then MergeRoads(MelloUI_RoadData) end`.

### 6. Quest List: `/qlmap` (no argument) errors when the data file is missing
`Modules/QuestList.lua:857-860` — `OnEnable` returns early with a warning, but the slash command stays registered and `QuestList.lua:917` `local data = QL.Data()` is nil, so `QuestList.lua:998` `#(data.entrances or {})` raises "attempt to index a nil value". (`/qlmap dock|entrance` also write pins for a module that never built its index.)
Fix: at the top of the handler, `if type(data) ~= "table" then MelloUI:Print("Quest List data is missing.") return end`.

### 7. Route: baked coordinates can land in a different cell than their saved key → dangling links
`Modules/Route.lua:441-456` — `Merge` checks `mine[key]` with the saved key but `AddNode` (`378-401`) stores the node under `KeyOf(node[1], node[2])`. `bake_routes.py` writes coordinates with one decimal (`RouteData.lua` rows such as `{15555.3,17225.1,...}`), so a coordinate like 15559.97 → `15560.0` moves from cell 1555 to 1556. Links copied at `449-453` still name the old key, which never exists; `Relax` (`993`) pushes those ids, `Position` (`938-950`) returns nil for them. No crash, but the edges into that node are silently lost after every bake, and `mine[key]` stays nil so the node is "added" again on every merge.
Fix: in `Merge`, use the key returned by `AddNode` (`local k2, created = AddNode(...)`) and remap the link keys through a `keyMap` exactly as `MergeRoads` does at `485-506`.

### 8. Route: a nil answer from `C_Map.GetMapPosFromWorldPos` is cached as a permanent failure
`Modules/Route.lua:560-562` — `worldYards[key] = false` on the first failure and `545-553` returns nil forever afterwards. `BuildDocks`/`BuildTaxis` run once at `OnEnable` (login), `RectOn` at `145-159` deliberately does not cache failures "the client may answer later" — the same reasoning applies here. Effect: if the API is not ready at login, every dock and flight point is missing for the whole session (`/route` shows 0 docks, 0 flight points; Services shows no flight masters).
Fix: do not write `false` into `worldYards` (return nil, retry next call), and rebuild docks/taxis lazily when `#docks == 0` / `next(taxis) == nil` on the first `FindRoute`.

### 9. Quest List: `MapIDForZoneName` stores an unguarded `info.mapID`
`Modules/QuestList.lua:583-587` stores `info.mapID` from `C_Map.GetMapChildrenInfo` without `QL.Plain`, while the same field is guarded at `QuestListMap.lua:394` and `Route.lua:1205`. The value then reaches `R:SetDestinationTo({ mapID = ... })` → `ToYards` → `ContinentOf` → `contCache[mapID]` (`Route.lua:123`) and `RectOn`'s `mapID .. ":" .. cont` (`Route.lua:146`) — indexing/concatenating with a secret value throws.
Fix: `local id = QL.Plain(info.mapID); if n and id and not mapIDByName[n:lower()] then mapIDByName[n:lower()] = id end`.

### 10. Quest List: flight-master click label reads a field the pin does not carry (verify against this client's `Blizzard_FlightPointDataProvider`)
`Modules/QuestListMap.lua:736-737` reads `pin.poiInfo`; retail's `FlightPointPinMixin:OnAcquired(taxiNodeData)` stores `self.taxiNodeData` and `self.name`, not `poiInfo`. Effect: every routed flight master is labelled "Flight master" instead of its name.
Fix: `local info = pin.taxiNodeData or pin.poiInfo; local name = QL.Plain(pin.name) or (info and QL.Plain(info.name)) or "Flight master"`.

### 11. Services: profession trainers already in the database are re-learned as duplicates
`Modules/Services.lua:407-419` — the 40-yard "already known" check for `kindKey == "trainer"` breaks after the first `KINDS` entry with `data == "trainer"` (`classtrainer`, `Services.lua:141`), whose `Candidates` are filtered by `TrainerMatches(class)`. A known profession trainer is therefore not found and gets a `learned[...]` entry (`421`) that is saved into `MelloUIRoutes.pins.services` and shows up alongside the database row in `Candidates`.
Fix: for the dedupe, iterate `Candidates(kind)` for every kind with `kind.data == kindKey` (do not `break` after the first), or call `Candidates` with a "no trainer filter" flag.

### 12. Documentation / command mismatches
- `/route dots` exists (`Modules/Route.lua:2231-2256`) but is in neither `README.md` (line 115 and the Route section) nor the in-code help line at `Route.lua:2387`.
- `README.md` Services section ("**Minimap stand.**" paragraph, options "Minimap Stand" "(the default)" and "Stand Fit") describes a feature removed on 2026-09-21 (`Modules/Services.lua:705-709`, `WithStand()` returns false, no such settings in `defaults`/`options` at `21-37`). The `trackerNoticeShown` default (`Services.lua:27`) is dead (`TrackerNotice` is empty, `726-727`).
- `Media/QuestListData.lua:5-8` documents 16 quest fields; the rows have 27 and the code indexes 17–27 (`QuestList.lua:105-108`: prev, continent, world x/y, giver NPC, ender name/NPC/zone/continent/world x/y). Update the header emitted by `Tools/build_quest_list.py`.
- `Modules/QuestListPins.xml:3` says the mixin lives in QuestList.lua; it is defined in `Modules/QuestListMap.lua:91-346`.
