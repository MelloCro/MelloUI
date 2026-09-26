# MelloUI guide

Everything the [README](../README.md) leaves out: each feature in detail, the voice pack install, every slash command and module, and how the addon is built and released.

# Features in detail

## 🎨 Your whole UI, reskinned

One switch and every window, every bar, the minimap, the nameplates, the chat, the tooltips, even the settings window itself gets the Old-School RPG Look. Gems, rails, the works.

- Don't like it? Flip it off. The game looks like the game again and everything else still works.
- Turn it on and your action bars, side bars, unit frames and party frames snap into the layout it was drawn for, fitted to your screen. No fiddling.
- Dark Mode darkens the reskin too, with a brightness slider, for the night owls.

## 🖱️ Drag. Everything.

Switch on Unlock the Windows at the top of the settings window, then grab any window and drop it wherever you want. Minimap, quest tracker, chat, damage meter, all of it.

- Scroll the mouse wheel while you're holding it to make it bigger or smaller.
- With Auto Snapping on it snaps to the middle if you get close, and it stays where you drop it.
- Works with the reskin off as well.

## 🔊 Every click has a new sound

I re-recorded the whole interface. Clicks, pages, pouches, buckles, coins, whispers, the dungeon pop, the level-up jingle. Iron, leather, parchment and stone instead of the stock beeps.

- Off by default, because taste is taste. Turn on the families you like, leave the rest.
- There's a Preview tab with a Play button for every single sound. Listen first, decide after.

## 🎙️ Quest givers talk to you

Every quest offer, progress line, turn-in and greeting is read out loud in a voice that fits the NPC's race and gender. And it always reads the right quest. Yes, that was a thing.

- A little overlay on a scroll shows who's talking, with subtitles.
- 11,503 recorded lines for Vanilla and the Forever-only quests, with the free voice pack below.
- No voice pack? The game's own text-to-speech kicks in (it needs a voice installed in the Windows speech settings). Works out of the box.
- Forgot what a quest was about? Open your quest log, hit Read, done.

**Get the voice pack (free, 1.6 GB, totally optional but so worth it):**

1. Download it here: [MelloUI_VoiceOverData.zip](https://github.com/MelloCro/MelloUI/releases/download/v0.13.0/MelloUI_VoiceOverData.zip)
2. Unzip it. You get a folder called `MelloUI_VoiceOverData`.
3. Drop that folder next to MelloUI in `World of Warcraft\_classic_beta_\Interface\AddOns` (the `.toc` file must be directly inside it, not in another folder).
4. Start the game, tick **MelloUI VoiceOver Data** in the addon list at the character screen. That's it. `/vo packs` in game shows the pack is loaded.

*(Had `AI_VoiceOverData_Vanilla` before? Delete it, everything in it is already in here. The pack merges the vanilla lines of the wow-voiceover project, Unlicense, with the lines made for Forever's own quests.)*

## 🗺️ The map that actually helps

- **Quest List:** every quest in the zone next to your map. Who gives it, where they stand, what's left to do, how much of the zone you've finished. Filters for dungeons, raids, class quests, attunements, events.
- **Pins for everything:** quest givers, hand-ins, dungeon doors, boats, zeppelins, flight masters. Click a door to see its quests, click a boat to get routed to the dock.
- **Smart Route:** a trail of gems along real roads to wherever you're going, plus an arrow. Cut a corner or take a shortcut? It just keeps going instead of nagging you to turn around. It learns the roads you walk.
- **Service Finder:** need a mailbox, a repair guy, an inn, a trainer? Little icons under the minimap. Click one, the arrow takes you to the nearest.

## 👥 Small things you'll use every day

- **Party Markers:** your group's class icons float over their heads, green ring for the healer. No more "who heals?" (Open world only, the game hides friendly nameplates in dungeons.)
- **Names:** everyone in Forever has a surname now. Too much? Show first names only. Or last names. Frames, nameplates and your own head, one setting.
- **Bars & fonts:** pick your health bar style, pick a font for text, chat, titles and damage numbers, and how big each one is.
- **Chat:** short channel tags, class colours, input box on top if you want it, one background opacity for every chat window.
- **Auto-vendor:** sells your greys and repairs your gear the moment you talk to a merchant.
- **And:** cooldown numbers on buttons, clean dark tooltips, CC and quest icons on nameplates, FPS and latency, hidden micro menu and bag bar, class medallions on portraits.

## 🧭 Set up in a minute

The first time you log in with MelloUI, a few seconds in, the installer asks how you want to start:

- **Full experience** (recommended): Mello's own setup. The reskin, the features and Mello's Edit Mode layout, fitted to your screen.
- **No reskin, features on:** the game's look stays and MelloUI's features come on. No Edit Mode change.
- **Reskin only:** the painted look and Mello's layout; the features stay off.
- **Fresh start:** everything off, then one step at a time: the look (the reskin, Kit Colours, the button borders, class icons), the minimap (Round or Square), parchment and dark mode, fonts, the features, your screen, chat and the windows. Each step's choices start at Mello's own, and nothing changes until you install. On the Features step every feature starts off: switch on the ones you want, or all of them with **All features**. Each one you switch on comes with Mello's own settings for it; the rest wait in `/mello`.

Dark Mode is yours: no setup changes it and no profile carries it. Fresh start's dark mode row starts at your own choice (off on a new character).

Then:

- **Your screen:** Mello's layout was made on a 21:9 screen; the installer fits it to yours (pieces at an edge keep their distance to it, the middle group tightens, then everything is checked for overlaps). Leave the Edit Mode layout out if you like: your own Edit Mode layouts always stay, and your UI scale is never changed.
- **Review:** what will change, before anything does.
- **Install:** your current setup is saved as the profile **Before install** first. Then you have 15 seconds: **Keep** the new setup, or **Revert** to go back at once; if you don't answer, it goes back by itself. A fight or Edit Mode pauses the countdown, and a `/reload` in the middle brings it back with 15 seconds. Before install stays on the Profiles page, so you can load it later too.
- **Done:** take the tour, open MelloUI, or reload once if the fonts over characters' heads changed.

Close it without installing and nothing changes. Run it again any time: **Install…** at the top of `/mello`, **Install again** on its Home page, or `/mello install`. Updating from an earlier version? No installer, just one line in chat. The game keeps the Edit Mode layout per character: on another character, `/mello layout apply` makes Mello's layout the active one there too.

## ⚙️ The settings window

`/mello`, or the **MelloUI** button in the game menu (Escape), opens it.

- **Top bar:** the Layout group on the left: Unlock the Windows, Auto Snapping and Reset positions (dimmed while UI Modifications is off; switch that on first). On the right: **Install…** (the installer), **Dynamic UI Modification** (the look of the reskin, picked on the interface itself) and close.
- **Side list:** Home, then the modules by group (The look, Quests and travel, Chat and sound, Frames and bars), then Profiles. Click a group's name to fold it away. Dark Mode, Fonts, Chat, Unit Frames, Nameplates and Tooltip live on UI Modifications' tabs: their entries open that tab right at their switch. A module that is off has a dimmed icon, and a name too long for the list shows in full when you point at it.
- **Pages:** a module's page has its switch and Defaults at the top and its options on tabs. An option that needs another switch is dimmed and says which one. Pages and tabs slide and fade in, and the wheel glides the page and the list; Reduce Motion (UI Modifications, General) makes all of it instant.
- **Home:** the Tutorial, What's new (Earlier versions for the rest), Your setup (the profile in use, with a list to load another; your Kit Colours, with Change… to Dynamic UI Modification; your screen; Install again) and Help with every command.
- Drag the window by its top edge: it stays where you put it. Escape closes it. At a large Font Style it is a little wider, so UI Modifications' tabs keep to one row.

## 💾 Your settings are safe

The game saves your settings like any addon's, so they're still there after a restart. As a safety net, MelloUI also keeps a copy in a few hidden account macros called `MelloUI1`, `MelloUI2`...: if the saved settings ever go missing (a new PC, a wiped `WTF` folder), that copy brings them back. Keep those macros and you're golden. Profiles let you save and load whole setups too.

## 🐛 Good to know

- Not every Forever-only NPC is recorded yet; those lines use text-to-speech for now.
- Instance doors new to Forever show up on the map after your first visit (or `/qlmap entrance`).
- Where no road is known yet, the route draws a straight guess. Walk it once and it learns.
- Dark Mode only recolours textures (the game's combat rules forbid the rest), so a frame drawn without textures keeps its colours.
- After an update, restart the game once. `/reload` isn't enough for new files.
- The tour uses the game's help tips, so they must be on (Options > Gameplay > Help).

## Install

Download the [latest release](https://github.com/MelloCro/MelloUI/releases/latest) zip (not GitHub's "Source code" zip) and copy every folder in it, `MelloUI` and `MelloUI_Companion`, to:

```
<World of Warcraft>\_classic_beta_\Interface\AddOns\MelloUI
<World of Warcraft>\_classic_beta_\Interface\AddOns\MelloUI_Companion
```

`MelloUI_Companion` holds the Route module's road network and quest objective places and only loads when a route needs them; keep it next to MelloUI and enabled. From a clone of this repository, `MelloUI_Companion` sits inside the `MelloUI` folder: copy it out into `AddOns` beside it. After installing or updating, restart the game fully once (a `/reload` does not find new folders or files).

Start the game. The settings window has its own **MelloUI** button in the game menu (Escape), or type `/mello`; it is not an entry under Options > AddOns. Forever runs the retail (Midnight era, 12.1.x) API and the Dragonflight style HUD with Camelot specific overrides; this addon targets exactly that client (beta 1.60.1, interface `16001`).

---

# Under the hood

Everything below is the detailed reference: profiles, every slash command, what each module does exactly, and how to build and release the addon.

## Profiles

The MelloUI settings have a **Profiles** page. "Save current as" stores every setting of every
module under a name; Load replaces all settings with a profile (it asks first, as the profile
list under Your setup on the Home page does; `/mello profile load <name>` loads at once);
"Set default" marks the one
that is applied when the addon starts with no settings at all, such as on a fresh install or
when neither the saved variables nor the macro backup brought anything back; out of the box
that is the built-in **Everything Off** profile (every module off, made from the module list
at each login, so it cannot be deleted or overwritten), and the installer opens a few seconds
later (*Set up in a minute* above). The installer adds two more: the shipped **MelloUI**
profile is its Full experience, and **Before install** is the setup you had before you last
installed. Profiles are
kept in the saved variables with the rest of the settings, so they stay from one session to the
next. On a development copy, `Tools\bake_routes.py --watch` (the same watcher that bakes the
learned roads) also bakes your own into `Media\Profiles.lua` after each `/reload`. The
watcher never writes the shipped **MelloUI** profile (the Full experience the installer applies,
baked from a saved setup by `Tools\installer\bake_full.py --write`) or Everything Off, and
`Tools\release.py` refuses a release while that file holds a stale MelloUI or any other profile,
which would ship to every player (`python Tools\installer\bake_full.py --check` says which). Only
values that differ from the defaults are stored, so a profile is a few hundred bytes.
What is yours stays out of every profile, saved, shared or shipped: your characters' known
flight points, the game settings MelloUI borrowed, steps done once, and Dark Mode (its switch
under UI Modifications and every Dark Mode setting), which is a personal preference; loading a
profile leaves all of it as it is. Loading one also never runs what switching the reskin on by
hand does: Custom Sounds stays as the profile has it and no Edit Mode layout is put in.
To share a profile, click **Share** on its row and copy the string; to use someone else's, type a name, click **Import as** and paste their string, then load it from the list. `/mello profile` does the same from chat.

## Slash commands

| Command | Effect |
| --- | --- |
| `/mello` | open (or close) the MelloUI configuration window; also the MelloUI button in the game menu |
| `/mello <module>` | open the window on that module's page |
| `/mello list` | list modules and their on/off state |
| `/mello enable <module>` | enable a module |
| `/mello disable <module>` | disable a module |
| `/mello dump [module]` | print the stored settings |
| `/mello status` | whether the client loaded the saved variables, where the settings in use came from, and the state of the macro backup |
| `/mello profile ...` | `save <name>`, `load <name>`, `delete <name>`, `default <name>` or `default none`, `export <name>` (a share string to copy), `import <name>` (paste someone's string in as that profile), `list` (see *Profiles*) |
| `/mello cpu` | CPU time per handler and hook of every module since login (needs `/console scriptProfile 1` and a `/reload`); `/mello cpu reset` zeroes the counters |
| `/mello preload` | How many artwork files Preload Artwork holds, and how many the game has loaded |
| `/mello help` | the command list in chat |
| `/mello tutorial` | the guided tour of the settings window (also the Tutorial button on its Home page) |
| `/mello install` | the installer: a setup for the whole interface, fitted to your screen, with 15 seconds to keep it or go back (also **Install…** in the settings window's top bar and **Install again** on its Home page) |
| `/mello layout` | the Edit Mode layout the reskin is drawn for: `apply` fits it to your screen and puts it into Edit Mode as an account layout ("MelloUI", or "MelloUI <width>x<height>" on another screen size) and makes it active (done once by itself when you switch the reskin on by hand; the installer puts it in for you), `export` prints the active layout's share string for baking into `Media\EditModeLayout.lua` |
| `/mellolog [clear]` | the copy window with what the dump commands logged (`clear` empties it) |
| `/vo ...` | Voice Over: `stop`, `pause`, `skip`, `test`, `voices`, `npc`, `packs`, `lines`, `reset` |
| `/qlmap` | Quest List map pins: diagnostics, and `dock`, `zeppelin`, `arrive`, `entrance`, `remove`, `list` to record pins by hand (see Quest List) |
| `/route` | Route: how much has been learned and the current route; `/route quest` (what the client reports for the tracked quest), `/route clear`, `/route arrow reset`, `/route reset confirm`, `/route dots` (the route painters, for the copy window) |
| `/services [kind]` | Services: open the nearest-service menu, or route straight to the nearest `repair`, `mailbox`, `innkeeper`, `flight`, `auction`, `bank`, `class trainer`, `profession trainer`, `barber` or `transmog` |
| `/sfx` | Custom Sounds: the state; `/sfx play <name>` auditions a sound, `/sfx list` names them, `/sfx log` prints every sound kit the game plays and what replaced it, `/sfx kit <id>` what a kit maps to; `/sfxdump` the last sound events in the copy window |
| `/kitwhat` | every kit texture under the mouse cursor, back to front: the piece, its size, its crop, its tint, the frame it is on (for a background that is not the one expected) |
| `/xxdump` | every reskinned window and HUD area has a dump command that logs its frames to the copy window: `/cpdump` (character), `/sbdump`, `/profdump`, `/legdump`, `/qldump` (quest log), `/gfdump`, `/gdump` (guild), `/coldump`, `/socdump`, `/ufdump`, `/cbdump`, `/rfdump`, `/abdump`, `/bagdump`, `/mmdump`, `/trdump`, `/chdump`, `/dmdump`, `/ttdump`, `/npdump`, `/pmdump` (party markers), `/icondump` (class icons), `/sfxdump` (custom sounds), `/kitdemo` |

## Modules

### Dark Mode

Darkens the Blizzard artwork by desaturating and tinting the frame textures. No layout is
changed, so Edit Mode keeps working and nothing secure is touched.

Components (each with its own toggle): unit frames, cast bars, action bars, action bar end
caps (gryphons), nameplates, personal resource display, experience/reputation/honor bars,
cooldown manager, micro menu and bag bar, minimap, chat frame, buffs and
debuffs. Extra options: brightness, desaturate, aura icon border, keep dispel
colours on debuff borders.

Dark Mode is a personal preference: its switch and every setting here stay out of profiles,
shared strings and the shipped MelloUI profile, and no installer setup changes it (Fresh
start's dark mode row sets it as you choose). A new character starts with it off.

### Bar Textures

Swaps the fill texture of health and power bars (player, target, focus, pet, party, boss,
target-of-target), raid-style party and raid frames, nameplate health and cast bars, the personal resource display, the
experience / reputation / honor bars, cast bars and the cooldown manager bars. Ships with
Flat, Smooth, Gloss and Minimalist textures, lists the two Blizzard bar textures and any
LibSharedMedia status bar textures, and reads custom files from `Media\Textures` listed in
`Media\CustomTextures.lua`. Colours that Blizzard baked into its atlases (power types,
experience, reputation, cast states) are re-applied so bars keep their meaning.

### Chat

- Move the input box above the chat window.
- Hide the chat window background and border art, the input box art, the buttons next to
  the chat, and optionally the
  tab background.
- Short, saturated channel tags: G for Guild (green), P for Party, R for Raid, RW for Raid
  Warning, W for whispers, and G, T, LD, WD, LFG for the numbered channels. Brackets can be
  removed as well.
- Class coloured player names in every chat type through Blizzard's own override CVar.
- Set The Background Opacity (off by default): one Background Opacity (100 % by default) for
  every chat window, docked and floating, whisper tabs and windows opened later included, set
  through the game's own `FCF_SetWindowAlpha` so the chat stone follows. Profiles carry it,
  which the game's own per-character value cannot. While it is on, the game's opacity slider on
  a chat tab changes it for every window; off, MelloUI never writes the opacity and the windows
  keep what they have.

### Names

Characters on this client have a first name and a surname. UI Modifications has one "Show Names
As" dropdown (its Names tab): first name, last name, or both, for everything at once: the player,
target, focus, pet, party and raid frames, the nameplates, and the name over your own head. The
frames' text is re-set after the game sets it (post-hooks on `UnitFrame_Update` and
`CompactUnitFrame_UpdateName`, in the Unit Frames and Nameplates modules); the name over your own
head is the client's own `UnitSurnameOwn` setting (surname on or off, so "Last name" shows both
there; the setting is put back when the module is off). A character with no surname shows the name
it has, and a name the client keeps secret (nameplates inside instances) is shown as the game shows
it. Other players' names drawn over their heads without a nameplate are the engine's: the client
has no setting for their form, so they always show first and last name; turn nameplates on to see
them in the chosen form.

### Nameplates

Moves the crowd-control icon on enemy nameplates from the right side to above the name
(above the debuff row when there is one) and scales it up, 45 px by default. Also enlarges
the loss-of-control icon on enemy player nameplates the same way. Blizzard's own "Crowd
Control" nameplate aura option must be on. Also adds a yellow quest marker left of the health
bar on enemies that still count for an unfinished quest objective (Forever's default
nameplates have no quest icon), read from the unit tooltip data.

With the reskin's Nameplate Kit on, the name above each health bar sits on a soft dark band, as long
as the name, that fades out at its ends (Name Shade: Name, the default). Whole plate adds a soft shadow that follows
the plate's own shape: round the level circle, round each end gem and along the bar, in every
Nameplate Border look. Off: no shade. Shade Strength sets how dark it is. Both sit on UI
Modifications' HUD tab, under the Nameplates switch. The shapes come in a new texture file, so
restart the game once after updating.

### Tweaks

- Hide the micro menu and/or the bag bar. They come back while Edit Mode is open so they can
  still be moved.
- With the bag bar hidden, the bag slots dock under the open bag window (combined or separate
  bags) so bags can still be equipped and removed. Off switch: "Bag Slots on Bag Window".
- Hide the player coordinates the client writes under the minimap ("Hide Minimap
  Coordinates", on by default).
- "Chat Notices" (on by default) covers the lines MelloUI writes to chat on its own: a
  learned dungeon entrance, settings restored from the backup, hints. Replies to slash
  commands always show.
- "On-screen Notices" (on by default): MelloUI's one on-screen notice, the short line in the
  upper third of the screen that Route, the Services bar and the Quest List use (a route set
  or finished, a service remembered, a dungeon's quests listed). Soft text in the palette's
  colours (gold for a new destination or an arrival) over a dark shade with soft edges, in
  your Font Style; held four seconds, then faded (at once with Reduce Motion). It works with
  Route off. Unlock the Windows shows a sample line there to drag; Reset positions puts it back
  at the top centre. Under it: "Send To Chat Instead" (off; the lines go to the chat, where
  Chat Notices applies) and "Notice Sounds" (on).
- "Zone Text Shade" (on by default): the game's zone text -- the zone's name when you enter
  a new area, the subzone under it and the PvP line ("Contested Territory", "Sanctuary") --
  in the notice's look: each line on the same soft dark shade, without the outline (Outlined
  Text brings it back for both), in the game's own colours and sizes, fading as the game fades
  it. Off: the game's own look.
- "Outlined Text" (off), after Zone Text Shade: draws the notice's and the zone text's lines
  with an outline. It is not under On-screen Notices, so it also sets the zone text's outline
  with the notices off.
- World Text Scale slider (0.5x to 3.0x, default 1.0x) for the floating damage and healing
  numbers. Writes the `WorldTextScale` CVar.

### Vendor

- Auto repair when a repair-capable merchant opens, optionally from guild funds with a
  fallback to your own gold.
- Auto sell grey items. Uses Blizzard's bulk junk sale when the client offers it, otherwise
  sells item by item in small batches.
- Optional chat report of repair cost and gold gained.

### Tooltip

Flat dark tooltip backdrop with adjustable opacity, dark border (optionally class / reaction coloured),
class coloured player names, the tooltip health bar hidden by default (or shown with the Bar
Textures fill and class / reaction colour), optional hiding of unit tooltips in combat, anchoring
at or right of the cursor, and a tooltip scale. Blizzard's tooltip health bar fields are never written, since
its update path compares secret health values and must stay untainted.

### Cooldown Timers

Large countdown text on cooldown swipes: outlined numbers that change colour and size
with the time left (red under 5 s, yellow under a minute, dim white for minutes, grey for
hours). Covers action, pet, stance and flyout buttons and the buff / debuff / crowd control
icons on nameplates. Options: minimum duration (skips the global cooldown), text size relative
to the icon, tenths below 5 s, colour by time. Blizzard's built-in numbers are hidden where the
module draws its own; when the client hands over secret start or duration values (possible on
enemy nameplate auras) the built-in numbers are left in place.

### FPS / Latency

Small readout in the bottom right corner: frames per second and home latency (optionally
world latency too), coloured on a green / yellow / red gradient. Hovering it shows home and
world latency, bandwidth and the addon's memory use. Options: which values, font size, offsets
from the corner, update interval.

### Unit Frames

Layout tweaks for the player, target and focus frames: names centred above the health bar,
transparent name band (the reaction coloured strip behind target / focus names), no red combat
flash on player / target / focus / pet / party frames, no resting / combat status glow on the
player frame, and a frame art opacity slider. Together with Dark Mode, Bar Textures set to the
"Class (players) / reaction (NPCs)" health colour and Bar Text this gives the flat RougeUI look.

### Fonts

The "Titles & headers" role is Enchanted Land by default and drives the kit's title plates as well
as the game's title font objects; "Keep the game's" puts Morpheus back on both.

Replaces the font of every global font object and the chat windows. Choose between the
four fonts shipped with the game, fonts other addons register with LibSharedMedia-3.0, or
your own `.ttf` files placed in `Media\Fonts` and listed in `Media\CustomFonts.lua`
(new font files need a full client restart). One face per role: interface text, chat and
numbers, titles and headers, damage numbers, each with its own size slider (the chat windows
scale on top of the game's own chat font size); an outline option forces thin or thick outlines
(Friz Quadrata plus a thin outline is the RougeUI look). The floating combat text and the
names above characters follow the face after a `/reload`; their size is the engine's.

### Party Markers

A class medallion above every party or raid member's head, ringed in the member's assigned role
colour (green healer, blue tank, red damage) when the group has roles set. It rides on the game's
friendly nameplates, the only thing an addon can hang over a player (the controller's interact icon
uses the same mechanism), so turn friendly nameplates on in the game's options. **In the open world
only:** inside dungeons and raids this game draws friendly nameplates on its own side and hands none
of them to addons, so nothing can mark them there (`/pmdump` shows the plates the addon is given).
Options: party and raid members or every friendly player, size, height above the name, the role
ring. A spec cannot be read for other players on this client without inspecting them, so the marker
is the class.

### Custom Sounds

Off by default. The interface's sounds replaced by a recorded library (iron, leather, parchment,
stone; `Media/Sounds/SFX`, the first variant of each sound, brought in by `Tools/import_sfx.py`).
The game plays a sound kit, a kit is a sound file; the module mutes the game's files
(`MuteSoundFile`) and plays the replacement itself: from a hook on `PlaySound` for the sounds the
game's Lua plays (buttons, checkboxes, tabs, scroll arrows, windows opening and closing, the spell
book's pages, the bags, the whisper and invite alerts, the ready check), and from the matching event
for the ones the engine plays on its own side (an item picked up, moved, put down or looted, gear
equipped or taken off, buying and selling, a quest turned in, an item crafted). One toggle per
family: Clicks, Windows, Inventory (a rare or better item has its own sound; this family silences
the game's item sounds, which Equipment and Vendor rely on), Equipment, Vendor, Social, Group
Finder, Crafting, Quests, Errors (the red messages, at most one every half second), Targets
(selected, lost), Level Up, Loot Coins, Spell Icons (dragged, placed), Map Ping, Scroll Wheel (a
cog notch per wheel step on any list or the chat; an addition, the game has none) and Hover Ticks
(an addition too; off). The Preview tab has a Play button per sound, with where the game uses it.
`/sfx log` prints every kit the game plays and what was done with it; a new sound file needs a full
client restart.

### Voice Over

Reads NPC dialog aloud with the client's built in text-to-speech: gossip greetings, quest
offers (optionally with objectives), quest progress and turn-in text. Speech is not tied to
the window, so the NPC keeps talking while you walk away; a new dialog interrupts the old one
and `/vo stop` cuts it off. Voices are the ones installed in Windows (Settings, Time & Language,
Speech); the Windows 11 natural voices become available to the game through the open source
NaturalVoiceSAPIAdapter.

Each NPC is looked up by ID in `Media\NPCVoiceData.lua` to find its race and gender. Races have
a pitch and speed profile (goblins and gnomes high and quick, ogres and tauren low and slow),
scaled by a strength slider, and every race group can be given its own voice. NPCs missing from
the data use the male / female voice at normal pitch; `/vo npc` shows what the module knows
about the targeted NPC and `Media\NPCVoiceOverrides.lua` adds or corrects entries by hand.

`Media\NPCVoiceData.lua` is generated by `Tools\extract_npc_voices.py` (Python 3, standard
library only) from the cmangos vanilla database, wago.tools DB2 exports and the wowdev
listfile, plus the Forever client's own `creaturecache.wdb` for NPCs you have met that are not
in the vanilla data. Re-run it now and then to fold in newly met NPCs.

Lines are queued and read one after another (a greeting finishes before the quest offer that
follows it; greetings never wait behind quest lines), advancing on the client's playback
finished event. An overlay in the style of the VoiceOver addon shows the speaking NPC's 3D
portrait with its talk animation, the NPC name, the line being read and up to three waiting
lines. Click a line to skip or remove it, hover the portrait for pause, use the button next to
the name to stop or skip. The frame can be dragged, locked with the padlock in its corner (or
the option), scaled, reduced to a thin bar without the portrait, and can show the text as
subtitles: the line is split into sentences packed into pages of three lines, and the page
turns as the playback advances, so nothing is ever cut off. The overlay textures come from
the VoiceOver addon (`Media\Textures\VoiceOver`, Unlicense).

`Tools\merge_voice_packs.py` builds the `MelloUI_VoiceOverData` pack offered on the Releases
page. The first time it merged `AI_VoiceOverData_Vanilla` and `AI_VoiceOverData_Forever` into
one addon; since then `Tools\build_voice_pack.py` builds new Forever lines straight into the
installed merged pack, keeping its other lines, and the merge tool simply packages that pack
(`--zip` for the release archive, `--install` to place a build in the game's AddOns folder).

If a VoiceOver data pack is installed and enabled in the addon list (`MelloUI_VoiceOverData`,
or the old `AI_VoiceOverData_Vanilla`: about 1.2 GB of recorded lines for most vanilla quest
offers and turn-ins, few progress lines, and the greetings), the module loads it on demand and
plays the recorded line whenever one exists: quest lines by quest ID (read once the quest panel
has settled, since the client can still report the previous quest when the event fires; a
vanilla quest Forever renumbered is found through its title and giver and plays the old
recording; a line recorded only per player gender plays either file rather than nothing),
greetings by NPC and text. Everything without a recording, such as Forever's new quests, falls
back to text-to-speech, unless "Read Unvoiced Lines" is off: then only recorded lines are heard and
the rest stays silent (the quest log's Read button still reads). The VoiceOver player addon itself is not needed and should be disabled
so lines are not read twice. `/vo packs` shows what was loaded. The channel the recordings play
on can be chosen (Master by default). "Prefer Recordings" (off by default) plays an NPC's only
recorded greeting even when Forever changed the greeting text, instead of reading the new text.

To build a pack for Forever's own content, the module records every greeting and quest line it
sees ("Record Dialog Lines", off by default) into the `MelloUIVoiceLines` saved variable, which
the game saves at logout and on `/reload` and keeps from one session to the next.
`Tools\export_voice_lines.py` merges each saved file into
`Tools\cache\voice_lines.json` and writes `Tools\output\forever_voice_lines.txt` / `.csv`: every
line with no usable recording, grouped by NPC with a race and gender hint, placeholders replaced
by spoken words, and the file name each MP3 should get. `/vo lines` shows what has been
collected so far. Generate the lines (the vanilla pack's voices were the author's own ElevenLabs
clones; cloning a few of the pack's MP3s per race and gender gives matching voices), then
`Tools\build_voice_pack.py assign <download.mp3> <file name>` files each MP3 under
`Tools\pack_sources` and `Tools\build_voice_pack.py build` writes them into the
`MelloUI_VoiceOverData` addon in the game's AddOns folder, adding to its lookup tables and
sound lengths while keeping the vanilla lines it already holds.

The vanilla lines the pack never had are listed by `Tools\export_vanilla_lines.py` from the
cmangos quest texts, restricted to the quests in Forever's quest list (5,228 lines for 3,813
quests at the time of writing: 776 offers, 3,688 progress lines, 764 turn-ins, about 830,000
characters), with the giver or turn-in NPC and its race and gender, as a manifest for
`Tools\generate_voice_lines.py --no-export --manifest Tools\output\vanilla_missing_lines.json`
(`--dry-run` first for the cost; `--skip-progress` or `--max-level` to trim it).

Voice helpers: `Tools\clone_voices.py` creates any missing `<race>-<gender>` voice in the account by
cloning a couple of minutes of the vanilla pack's own lines for that race; `Tools\design_voice.py`
designs a voice from a description (previews saved locally, then `keep`); the ElevenLabs voice
library can supply accented voices (the troll voices are library voices with a Jamaican accent).
Troll lines are respelled in light patois ("de", "dem", "mon", "-in'") before generation
(`--no-patois` turns it off). `Tools\import_wowhead_quests.py` imports the offer, progress and
completion text of Forever's own quests (IDs from 60000, absent from the vanilla database) from
Wowhead's Forever database, so they can be voiced before you meet them; Wowhead does not state
NPC race or gender, so lines of unknown NPCs are held back by the generator until the NPC is met
in game or listed in `Media\NPCVoiceOverrides.lua` (`--allow-unknown` forces them).

**Quest log read-aloud.** The quest log's details view gets a Read button (option "Read Button
In The Quest Log", also `/vo read` for the selected quest). It reads the quest's description in
the giver's voice, then the objectives with their current counts ("Goretusk Liver, 3 of 8").
When a sound pack has the giver's recorded offer line it is played instead of text-to-speech.
The giver comes from the Quest List data (every vanilla and Forever quest carries its giver's
NPC id), so the race and gender voice is right even for quests accepted long ago. The
description read this way is collected like any other line, so old quests without a recording
get generated too; the objectives are not.

Commands: `/vo stop`, `/vo pause`, `/vo skip`, `/vo read`, `/vo test`, `/vo voices`, `/vo npc`,
`/vo packs`, `/vo lines`, `/vo reset`.

### Quest List

A panel to the right of the world map, styled like the quest log, listing the quests picked up
in a zone: a "done / total" count, then every quest under collapsible gold headers, one per
quest chain (named after its first quest; chains come from the vanilla database's hard
prerequisites and Wowhead's series tables) plus "Single quests". Titles are coloured by
difficulty like the quest log and carry the quest markers: yellow "!" for a quest you can pick
up, grey "!" when your level is too low, yellow "?" for a quest in your log with its objectives
done, grey "?" for one still in progress, and a tick for completed quests, which stay in the
list greyed. Each row shows the quest giver and its map coordinates; clicking a quest places
a map pin on the giver and marks that row with the pin icon, clicking it again removes the pin. Everything is sorted by level, lowest first, and quests of the
other faction are left out unless enabled. Views: All (grouped by zone), Current Continent,
Current Zone (the zone the map shows, grouped by chain and dungeon), Class Quests, Dungeons and
Raids (a header per instance, Forever's new ones included, taken from Wowhead's zone list),
Attunements (the Onyxia, Molten Core, Blackwing Lair, Naxxramas, Scholomance and Upper
Blackrock Spire key chains), and Events (Winter Veil, Hallow's End, Darkmoon Faire, Scourge
Invasion, the Grand Tournament of Gnomeregan and so on). A search box like the quest log's
searches every zone by quest title, giver or zone. Options: hide completed; other faction's and other classes' quests (off by
default); a level cap above your level. `Media\QuestListData.lua` is generated by
`Tools\build_quest_list.py` from Wowhead's Forever listing (quest, level, faction, class,
zone), the cmangos vanilla database (quest givers and their spawn points, converted to map
coordinates with the Classic Era map bounds) and Wowhead's quest and NPC pages for Forever's
new quests (giver and zone only, Wowhead has no coordinates for them). Positions the Voice Over
collector records when you talk to an NPC fill in the coordinates of those givers, so re-run
the build now and then.

The data keeps the vanilla givers' *world* coordinates and lets the client place them on its
own maps at login (`C_Map.GetMapPosFromWorldPos`, the continent map's hit test and the zone's
rectangle on it), so Forever's redrawn maps such as Stormwind with its harbour are right and
givers near a zone border land in the correct zone. Chain quests know their predecessor, which
gives "Step 2 of 5" and "Next: ..." in the tooltips and numbered, chain-ordered rows in chain
groups.

**On the map.** The module adds its own pins through the map's data provider system, so they
zoom and pan with the map:

- *Quest givers* on zone maps: one pin per giver location with the marker of the best thing
  you can do there (yellow "!" pick up, yellow "?" turn in, grey "?" in progress, grey "!" too
  low; givers you are done with are hidden unless enabled). Hover for the quests with their
  state and chain step, click to set the waypoint.
- *Zone badges* on the continent maps: a "done / total" badge on every zone; hover for the
  level range and how many quests you could pick up now, click to open the zone.
- *Dungeon and raid entrances* on zone maps, with the game's Dungeon and Raid icons. Positions
  come from the vanilla database's entrance triggers (every door, Dire Maul's wings included).
  Hover for the level range and your quest progress in that instance, click to show its quests
  in the panel, Shift-click to route to the door. Entrances of Forever's new instances come
  from the client's own entrance list and points of interest when this build has them, are
  learned the first time you walk in (the last outdoor position before the loading screen)
  or, when there was none, the first time you walk out (you appear at the door), or are
  recorded by hand with `/qlmap entrance <name>` while standing there. `/qlmap` lists what
  the client reports for the map shown.
- *Boats and zeppelins*: docks and towers with the destination, in the taxi-node icons of
  your faction; click to route to the dock, Shift-click to open the destination's map. The
  vanilla routes come from the
  transport ships' paths; Forever's new routes (Stormwind Harbour, Southshore, Steamwheedle
  Port to Powderfuse Port) are recorded on the spot with `/qlmap dock Boat to Auberdine`
  (`| alliance` or `| horde` for a faction-only route) and linked to their destination with
  `/qlmap arrive <label>` after the crossing. `/qlmap list` and `/qlmap remove <label>`
  manage the recorded pins. Recorded pins are kept with the Route module's learned paths
  (baked by `Tools\bake_routes.py`), not in the settings, so they never crowd the macro
  backup.
- *Flight masters*: the client's own flight point pins; clicking one also routes to the flight
  master. All of these go through the Route module when it is on (road route, arrow, notice)
  and place a plain map waypoint when it is off.

**Turn-ins.** Every quest also knows who takes it back (the vanilla database's involved
relations, Wowhead's End NPC for Forever quests), placed by the client like the giver. The
tooltip names the turn-in NPC and zone; a quest whose objectives are done shows "Turn in: ..."
in its row, its map pin and waypoint move to the turn-in NPC, and the Route module leads
there.

**Entering an instance** prints how many of its quests you have done, how many are in your
log, and the ones you have not picked up with giver and zone, plus where to hand in the ones
that are ready.

### Route

Following: the arrow projects you onto the route and aims a stretch ahead along it (farther ahead
the farther you are from the path), advances eagerly when you cut a corner, and keeps the planned
route while you follow it; a new route is only planned after you have been more than 45 yards
off the path for two seconds (or every 30 seconds as a refresh), and a fresh plan prices joining
the road behind you higher than the road ahead, so a shortcut is never answered with "go back".

Draws the way to your destination on the world map and the minimap, with a direction arrow
and a tracking notice. A destination is a pin: the Quest List's quest giver or turn-in pins,
the Services bar's pins, or a waypoint you place on Blizzard's map. Without a pin the route
follows the quest you super-track (click it in the objective tracker): to its objective area,
and to its turn-in once it is complete, using the markers the client places for quests in
your log ("Fall Back To The First Tracked Quest" follows the top of the tracker instead when
nothing is super-tracked). The client has no road or terrain data
for addons, so the roads come from two places: the ones traced from the zone maps' art
(`MelloUI_Companion\RoadData.lua`, loaded when a route is needed; see *Traced roads* below) and the ones the module learns from you: every
half second outdoors it drops a breadcrumb and links it to the previous one, flights you take become links, opening a flight
master's map records the links from there to every reachable point, and the boats, zeppelins
and the vanilla flight network from the Quest List data connect the rest (only flight points
your character has discovered are used). A route is the cheapest way through that graph, in
seconds, with straight legs to reach it; where nothing has been learned yet it is a straight
line. Routes may cross continents: walk to the dock, boat, walk.

The route is drawn as a chain of small gems like the taxi map: gold along paths you have
walked or that were traced from the map, pale blue where the route is a straight guess, green
for a flight leg. On the minimap the
nearby part is drawn the same way, clipped to the minimap's shape. A direction arrow (the
minimap's own player arrow at double resolution, top centre of the screen by default, drag to
move, `/route arrow reset`) points along the next leg relative to where you face, with the
remaining distance and about how long the rest of the way takes ("1.2 km · about 2 min") and
the destination's name and icon under it. Every new destination shows
a line in MelloUI's on-screen notice (see Tweaks: On-screen Notices) with the client's
super-track chime ("Tracking quest giver Marshal McBride for Kobold Camp Cleanup, 240 yd away"),
and arriving shows "Arrived" with a softer sound; "Route Announces" and "Announce Sound" switch
Route's lines and their chime. Within 25 yards of a pin the
route ends and the pin is cleared; near a quest objective the drawing pauses but the
destination stays. Options: the two drawings, the distance text, the travel time, the text shade, the arrow and
its size, Route Announces and its sound, marker size, arrival distance, and learning on or off.

Travel Time (on by default) puts the time beside the distance under the arrow and on the World
Marker's gem ("under a minute" near the end), in the tracking notice ("Tracking Stormwind:
1.2 km, about 2 min") and in the arrival ("Arrived: Stormwind (2:48)"). The route is priced in
seconds (flights and boats at their own times, the ground at your speed), and your speed is
measured as you move and smoothed, so the time follows you onto a mount. It is hidden while you
are off the path or on a flight. The arrival leaves the time out past an hour, after a
`/reload`, and when Route was switched off on the way. Off, every text is as it was.

Text Shade (on by default) gives the arrow and the World Marker the nameplates' soft shade, so
they read on bright ground: a soft dark band behind the distance line and the name line, each
as wide as its text, a soft shadow of the gem's own shape behind the marker's gem, and a round
soft shade behind the direction arrow and the marker's edge arrow. The distance under the
minimap has no shade. Off, the name line is 180 wide again, a longer name cut.

Learned paths live in the `MelloUIRoutes` saved variable, which the game saves at logout and on
`/reload` and brings back at login, so what you learn stays from one session to the next. The
traced roads are not part of it, only what you walked. To bake what you walked into the addon
itself (so it ships to every player), run the baker while you play:

```
python Tools\bake_routes.py --watch
```

After each `/reload` it writes `Media\RouteData.lua` and your own saved profiles into
`Media\Profiles.lua`, in the project and in the game's copy; the shipped MelloUI profile and the
file's head stay exactly as they are, and the built-in Everything Off is never written (see
*Profiles* above). To change the
shipped Full experience, save the setup in game, `/reload`, and bake it from that saved file:
`python Tools\installer\bake_full.py --snapshot <WTF>\Account\<account>\SavedVariables\MelloUI.lua --write`,
then `python Tools\installer\test_bake.py`.

**Traced roads.** `Tools\trace_roads.py` reads the roads off the zone maps themselves, so routes
follow roads from the first login: it downloads the build's map art and tables from wago.tools
(the base tiles and the explored overlays, with each zone's world bounds), stitches every zone
of both continents, looks for the painted roads (a light line with a dark outline on both
sides, joined along its direction, thinned, cleared of mountain meshes and short strokes) and
writes them as a graph into `MelloUI_Companion\RoadData.lua` in continent yards. The Route module folds
that graph in at login, scaled to the continent sizes the client reports, and never writes it
back into the saved variable. Hand-painted art fools the tracing here and there: ridges, lake
shores, labels and icons come out as roads and some real roads are missed. The tracing is a
best effort and `Tools\roads_review.html` is the correction: serve the Tools folder
(`python -m http.server 8765` in `Tools`), open the page, click traced segments to drop them,
draw missing roads, save `review.json` into `Tools\roads` and run the bake stage again. The
automatic segments (`Tools\roads\segments.json`) and the review are committed, so a bake is
reproducible. Stages: `fetch`, `assemble`, `trace`, `bake`, or `all`; `--zone <uiMapID>` limits a
stage to one zone while tuning. `/route` reports how many traced road points are loaded.

It turns the written file into `Media\RouteData.lua` (project and game copies) after every
`/reload`, and the module merges that file, the saved variable and the current session. The
game saves what was learned at logout and on every `/reload`; the baker picks it up after a
`/reload`. `/route` shows
the counts, `/route quest` what the client reports for the tracked quest, `/route clear`
drops the route and the pin, `/route reset confirm` wipes the learned paths. Other modules
route through `MelloUI.Route`: `SetDestinationTo`, `DistanceTo`, `Cheapest` and `Notify`
(Route's own lines, under Route Announces). A line of any module's own goes to the on-screen
notice with `MelloUI:Announce(text, kind)` (Core/Notice.lua), which works with Route off; the
soft band behind its text is the shared `MelloUI.Shade:Band` (Core/Shade.lua).

### Services

A bar of service icons under the minimap (it moves with the minimap in Edit Mode), in groups
or in two rows (Button Layout, below): repair,
mailbox, innkeeper, flight master, auction house, bank, class trainer, profession trainer,
barber and transmogrifier, drawn with the client's own minimap tracking icons. Hover an icon
for the nearest one's name and distance; click it and the Route module takes the few closest
candidates, routes to the one that is cheapest to reach by road, boat or flight (a bank across
the river is not "nearest" when the bridge is a long way round), drops the map pin on it and
shows the tracking notice with the service's icon. Right-click stops the route. Icons for
services with none known on your continent are greyed. Vanilla service NPCs and mailboxes
come from the vanilla database with their faction, flight masters from the flight point data
(discovered ones only), class and profession trainers are filtered to your class and
professions, and anything else (Forever's barbers and transmogrifiers, NPCs the database does
not know) is remembered the first time you open its window and kept with the Route module's
learned paths. The profession trainer icon asks which profession first: a menu of every
profession with a known trainer on the continent (your own ones first, marked), plus
"Nearest of any". Options: the bar and its distance from the minimap, and the older round
minimap button with a list menu (off by default). `/services <kind>` routes from chat.

Button Layout picks how the bar stands. Groups (the default): one row of five group buttons
as wide as the map (Travel: flight master, innkeeper; Trade: auction house, bank, mailbox;
Repair; Trainers: class and profession trainer; Looks: barber, transmogrifier). Hover a group
for each of its services with the distance to the nearest one; click it for a small list
beside the minimap column, toward the middle of the screen, with the same distances, and
click a service there to route to it (the profession trainer asks which profession first).
Repair has no list: a click routes at once. Escape, a click elsewhere or the same group
again closes the list, another group switches it; right-click a group to stop the route. A
group is grey only while none of its services is known on your continent. Merged into the
square minimap's frame, the row sits under the divider rail with its gem caps and the
"Services" name (centred; at the rail's left end while Route's distance line stands at its
right end) and the clock moves beside the zone name. All Buttons: the two rows of an icon per
service, as before. The minimap button keeps to the map's edge at any Edit Mode size, round
or square. For modules: `Services:ColumnRow()` answers whether the row of groups stands
under the map and its height (MinimapPanel's column asks it).

### Minimap Panel

The minimap cluster in the kit (part of the reskin in UI Modifications): the iron ring
around the map with the zone name on a title plate standing on it, the tracking button in a
round rim, plus / minus zoom buttons. Edit Mode still owns the cluster's position; with "Unlock
the Windows" the map can be dragged by its zone band. `/mmdump` prints the rects.

The map's size is Edit Mode's (Minimap, Size): the border, the map, its buttons and the zone
name all scale together, and MelloUI never resizes them. What stands under the map follows
its width: the Services row of groups, and MelloUI's Quest Tracker with "Match The Minimap's
Width" (Quest Tracker). For modules: `MinimapPanel:ColumnWidth()` gives the map's width on the
screen and the width the frames line up to (the square border's frame where it is wider).
MelloUI's own Edit Mode layout (`/mello layout apply`, the installer) sets the Size to 150 %,
the map about as wide as the Quest Tracker, and puts the game's tracker (which MelloUI's hangs
on) right under the column with its right edge on the frame's. On a smaller screen the fit
(`Core\LayoutFit.lua`) takes the largest step that leaves the tracker 300 units under the
column and your buffs room beside it. Where your buff rows by the column would reach into the
centre third, the layout is fitted for fewer icons a row or smaller icons, and the installer's
report says which to set in Buffs & Debuffs (the fit changes them itself only for a caller
that writes its `places.auras`: `inputs.auras.fitRows`).

### Tracker Panel

The objective tracker in the kit: the title plate on the "All Objectives" header, header plates
on the sections with centred titles, the kit's collapse glyphs, a stone backdrop with a border
that follows Edit Mode's opacity and retracts when collapsed, quest items in rims, progress
bars in the bracket. Hooks only schedule work; nothing is laid out while Edit Mode is open or
in combat. `/trdump` prints the tracker, its header, every module and every shown block.

### Quest Tracker

A quest tracker of MelloUI's own in the game's tracker's place (off by default), because the
game's tracker on this client does not scroll. The mouse wheel scrolls the list. Each quest has the game's map button ("..." in progress, "?"
ready to turn in, lit while followed); click a quest to follow it, Shift-click to stop watching
it, right-click to open it in the quest log. Quest items are used with a click out of combat.
Tracked recipes show under Professions with their reagents, and Quests and Professions each
fold away on their own minus. An objective line glows briefly when it counts up. It takes its
place and height from the game's tracker in Edit Mode, is moved by its header with Unlock the
Windows, and a grip in its bottom-left corner sizes it; Height, Width, Scale, Text Size and
Scroll Step are in its settings.

"Match The Minimap's Width" (on by default, needs the Minimap Kit) makes the tracker as wide on
the screen as the minimap above it: the round map, or the square map's frame, so the two line
up. Make the minimap bigger or smaller in Edit Mode (Minimap, Size) and the tracker follows
when you leave Edit Mode; the grip then sizes only its height. Off, it takes its own Width.

The tracker stands in front of the minimap column (MEDIUM strata over the column's LOW), so a
click on the minimap, which raises the whole cluster, never brings the map or the Services row
over it; the Services group lists still open above it. While it stands where the game or the
installer's fit put it, it keeps clear of the column: it moves down under everything the
column paints (the square frame's bottom gems, and with the Minimap Kit off the game's own
frame round the map) when the minimap's Size, the Services bar's Button Layout or merge, or the
UI scale changes. The installer records the place its fit wrote, so that place still counts as
the game's own (Revert takes the record back); a tracker you moved yourself, in Edit Mode or
with Unlock the Windows, stays where you put it. The keep-clear only ever moves it down.

### Buffs & Debuffs

MelloUI's own aura rows (off by default), drawn by the game's aura container so they keep working
in combat: your buffs and debuffs beside the minimap or where the game's buff bar is (right-click
cancels a buff; the game's bar comes back in Edit Mode), the target's debuffs and buffs under the
target frame, and your debuffs on enemy nameplates. Each part has its own switch and icon size.

"Attach To The Minimap Column" (on by default, needs the Minimap Kit) lines your buffs up level
with the map's top, growing away from it, with your debuffs on the line under them; with the
minimap on the left half of the screen they sit on its right and grow rightwards. They follow the
minimap when it moves or changes size (a change during a fight waits for its end). Off, they
stand where the game's buff bar is.

### Error Messages

Hides the red error messages you choose from the middle of the screen (off by default), a kind
at a time: not enough resources, not ready yet, out of range, facing and target, busy or
moving. MelloUI takes the error event from the game's error frame while a kind is hidden and
hands every other message to the frame's own handler, so those show as always.

## Releasing

A version tag builds and publishes the addon. `python Tools\release.py` bumps the patch
version in `MelloUI.toc` (`minor`, `major` or an explicit `0.14.0` for other bumps), commits
everything pending, tags and pushes; `--dry-run` shows what it would do. By hand it is: bump
`## Version` in `MelloUI.toc`, commit, then

```
git tag v0.14.0 && git push origin main --tags
```

The release notes are the version's section in `CHANGELOG.md`, which must be the newest one;
`release.py` shows the bullets it is about to publish and refuses without them. The workflow
writes that section to `CHANGELOG-release.md` and the packager publishes it as the notes on
CurseForge and GitHub.

The GitHub Action (`.github/workflows/release.yml`, BigWigs packager) zips the addon minus what
`.pkgmeta` ignores, uploads it to CurseForge (project id from `## X-Curse-Project-ID` in the
TOC, token from the `CF_API_KEY` repository secret) and attaches the same zip to the GitHub
release for the tag. A tag that already has a release is skipped, so a moved tag cannot upload
a duplicate; a repository ruleset also forbids moving or deleting `v*` tags. The voice pack is
not part of that: when the lines changed, run `python Tools\merge_voice_packs.py --zip` and
upload the zip to the release by hand, then update the direct links in the README and the
CurseForge description.

Every push runs `luacheck Core Modules Media MelloUI_Companion` (`.github/workflows/lint.yml`,
options in `.luacheckrc`): syntax, unused locals and globals that are neither WoW API nor listed
there. A new Blizzard global goes into the `read_globals` list of `.luacheckrc`. The same
workflow runs the duplication ratchet, `python Tools/lint/check_panels.py`, which fails when a
counted copy of a shared system comes back, or a colour number in one of MelloUI's own windows
(they take their colours from the palette only); its header lists the checks.

Generated media: `Tools\make_ui_sounds.py` synthesizes the configuration window's click sounds
into `Media\Sounds`, `Tools\make_minimap_frame.py` builds the minimap stand and the objective
tracker panel from `docs\minimap-frame.webp` and prints the ring, slot and panel constants the
Services, Minimap Panel and Tracker Panel modules need. `Tools\make_soft_shade.py` builds
`Media\Textures\SoftShade.tga`, the soft band behind text (`MelloUI.Shade`, Core/Shade.lua: the
notice, the zone text, nameplate names, Route's Text Shade), and `Tools\make_kit_shadows.py`
builds `Media\Textures\KitShadows.tga`, a blurred copy of a kit piece's own shape laid under it
(`Kit:Shadow`: the nameplates' Whole plate shade, the World Marker's gem `deco/gem_large`). Both
are white with a soft alpha, tinted in game with a palette colour (innerPanel by default).

## Forever client tables

`Tools\build_quest_list.py` reads the client's own tables from `Tools\cache`. It prefers a
Forever export (`<Table>_1.60.1.69913.csv`, made with the open-source **wow.export** from the
local install, semicolon separated) and falls back per table to the Classic Era export from
wago.tools (`<Table>_1.15.9.69722.csv`); the build log says which build served each table.
With `TaxiPath`, `TaxiPathNode`, `Map` and `AreaTable` exported, the data gains Forever's
flight links, every ship and zeppelin route straight from the path table (Stormwind Harbour,
the Southshore stop, Steamwheedle Port to Powderfuse Port, the Zephras Isle crossings), and
the new instances by name. Still worth exporting: `TaxiNodes` (names and factions of the
new flight points, placed from path geometry until then), `AreaTrigger` (entrances of the
new dungeons), `UiMap` and `UiMapAssignment` (Forever's map bounds for the fallback
positions), `AreaPOI`, `CreatureDisplayInfo` and `CreatureDisplayInfoExtra` (race and gender
of the new NPCs for Voice Over).

## Writing a module

Create `Modules/YourModule.lua`, add it to `MelloUI.toc`, and register it:

```lua
local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("YourModule", {
    title = "Your Module",
    desc = "What it does.",
    enabledByDefault = true,
    defaults = { someToggle = true, someValue = 0.5 },
    options = {
        { type = "header", name = "Section" },
        { type = "toggle", key = "someToggle", name = "Some toggle", desc = "Tooltip" },
        { type = "slider", key = "someValue", name = "Some value", min = 0, max = 1, step = 0.05, percent = true },
        { type = "dropdown", key = "mode", name = "Mode", values = { { value = "a", label = "A" }, { value = "b", label = "B" } } },
    },
})

function M:OnInit(db) end                       -- once, after saved variables load
function M:OnEnable(db) end                     -- when switched on (and at login if enabled)
function M:OnDisable(db) end                    -- when switched off
function M:OnSettingChanged(key, value, db) end -- when an option changes
```

Settings are stored per module in the `MelloUIDB` saved variable (account wide).

Where the module shows up is said in the same call, never in a hand list (the header of
`Core/Core.lua` has every field): `icon` and `flavour` for its page header, `group` for its
entry in the settings window's side list ("The look", "Quests and travel", "Chat and sound" or
"Frames and bars"; no group, no entry) and `navOrder` for its place in that group, `role` for
what the installer's setups do with it ("core", "look", "feature", "adds" or "replaces"), and
for a feature folded under UI Modifications `tweak = { label, desc, order }` (a row on its
tabs). A window the reskin dresses gives `window = { label, desc, tab = "Windows" | "HUD", ... }`
(`docs/WINDOW-RULES.md`, section 6).

## Notes on the Forever client

- Interface version is `16001` (1.60.1). The addon directory is `_classic_beta_`.
- `WOW_PROJECT_ID` reports mainline; there is no runtime flag for Forever. Use the TOC
  interface number or feature probes instead.
- The retail *secret values* system is active. Never compare or format values coming from
  cast or unit APIs in combat without checking `issecretvalue`. Dark Mode avoids this by
  only touching textures.
- `C_Map.GetMapPosFromWorldPos(continent, worldPos)` answers with the *continent* map and a
  position on it, not the zone; the override form returned only an x here. To find the zone
  ask `C_Map.GetMapInfoAtPosition(continentMap, x, y)` and project with
  `C_Map.GetMapRectOnMap(zoneMap, continentMap)`. Quest List and Route both do this.
- Mask textures do not apply to `Line` textures; clip lines yourself.
- New files listed in the TOC (Lua, XML, data) need a full client restart; edits to existing
  files only need a `/reload`.
- Saved variables are saved and loaded as usual, but can arrive a few seconds after
  `PLAYER_LOGIN`: Core and Route keep checking for them for a while and adopt them when they
  come. The macro backup (`Core\Backup.lua`) restores the settings only when they are missing.
