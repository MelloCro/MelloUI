# CurseForge description

Paste the text below into the project description on CurseForge (Markdown). Upload
`docs/update-0.13.2.jpg` as the project image and add the same picture under
"What is new" when a version adds one.

---

**Module based UI tweaks for World of Warcraft: Forever.** Each module can be switched off on
its own; the settings have their own WoW styled window, opened with the **MelloUI** button in
the game menu (Escape) or `/mello`.

## Modules

- **Dark Mode**: darkens the action bars, unit frames, minimap and the rest of the HUD art.
- **Bar Textures, Bar Text, Cooldown Text**: status bar looks, health and power numbers,
  cooldown counts on buttons.
- **Unit Frames, Nameplates, Tooltip, Chat, Fonts, Stats**: small, individually switchable
  tweaks to the frames the client already has.
- **Tweaks**: hide the micro menu and the bag bar (the bag slots dock under the open bag
  window), hide the minimap coordinates, scale the floating combat text.
- **Vendor**: sells grey items and repairs at merchants, with a chat report.
- **Quest List**: a panel next to the world map with every quest of the zone, how many are
  done, who gives them and where. Map pins for quest givers, dungeon and raid doors, boats and
  zeppelins; click a boat or flight master to route there.
- **Route**: a road route and an arrow to the tracked quest, a map pin or a service, learned
  from the ways you walk and shipped with the addon.
- **Services**: a bar of medallions under the minimap that routes to the nearest repair,
  mailbox, innkeeper, flight master, auction house, bank, trainer, barber or transmog. The
  minimap sits in a bronze stand with the objective tracker hanging from it.
- **Voice Over**: quest text read aloud by recorded lines (voice pack) or Windows
  text-to-speech, with paged subtitles and the NPC portrait.

## Install

Unzip into `World of Warcraft\_classic_beta_\Interface\AddOns` so that the folder is
`AddOns\MelloUI`, then `/reload`.

**Voice pack (optional, 1.6 GB):** the recorded lines are a separate addon hosted on GitHub
because of the size: https://github.com/MelloCro/MelloUI/releases/download/v0.13.0/MelloUI_VoiceOverData.zip
Unzip it next to MelloUI (`AddOns\MelloUI_VoiceOverData`) and tick it in the addon list.

## Known issues

- The beta client does not reliably read saved variables back. MelloUI keeps its settings in
  a few hidden account macros named `MelloUI1`, `MelloUI2`, ... as a backup. Do not delete them.
- Doors of instances new to Forever appear on the map after your first visit.
- Route draws a straight line where no road has been learned yet; walking it once teaches it.
- A full client restart is needed after an update that adds files; `/reload` is not enough.

## Links

- Source and issues: https://github.com/MelloCro/MelloUI
- Changelog: https://github.com/MelloCro/MelloUI/blob/main/CHANGELOG.md
