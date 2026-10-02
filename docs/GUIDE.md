# MelloUI guide

Everything the [README](../README.md) leaves out: each feature in detail, the voice pack install, every slash command and module, and how the addon is built and released.

# Features in detail

## 🎨 Your whole UI, reskinned

One switch and every window, every bar, the minimap, the nameplates, the chat, the tooltips, even the settings window itself gets the Old-School RPG Look. Gems, rails, the works.

- Don't like it? Flip it off. The game looks like the game again and everything else still works.
- Turn it on and your action bars, side bars, unit frames and party frames snap into the layout it was drawn for, fitted to your screen. No fiddling.
- Dark Mode darkens the reskin too, with a brightness slider, for the night owls.

## 🎨 Seven palettes and a soft shade

Ember, the warm brown and bronze MelloUI started with, now has company: **Obsidian** (black glass and pewter), **Royal Azure** (deep navy and gold) and **Fel Ember** (charred black, fel green and void purple), each with a brighter **Vibrant** version. Every palette comes with its own painted kit, so the rails, gems and plates change colour with it, and every MelloUI window, text and highlight follows.

- Pick one on Look > General (Home's Your setup names yours, with Change… to it), or on the installer's Look step in Fresh start. Kit Colours then offers that palette's kit or the Original (under Ember: Warm iron, Bronze or the Original).
- A soft dark shade follows the outline of every painted piece, so the interface stands out from the world: windows, bars, unit frames, chat, bags, the minimap, the trackers, buffs, event widgets and nameplates. It is on at 70 %. UI Shade, Shade Strength and a switch per area are on Look > General; each area's own page links to its switch.
- Items you can't use and spells you can't learn stay on dark red in every palette.

## 🖱️ Drag. Everything.

Press **Edit Layout** at the top of the settings window (or type `/mello edit`). Every part of the interface gets a plate you can drag: MelloUI's trackers and notices, the minimap, chat, the damage meter and any window you have open. The arrow, the Voice Over window and the whisper windows get one too, even while they are hidden.

- Scroll the mouse wheel on a plate to make it bigger or smaller; it stops at 100 % on the way.
- It snaps to the nearest element's edges and centre, and a gold line shows where. Hold Shift for a straight line, Alt to drop it freely.
- Right-click a plate for its size, exact position, what it snaps to, Reset, and a link to its settings. Some elements show their own settings there too (the race bar's Width and Height): the same settings as in the configurator, so a change in either place is the other's. Ctrl+right-click resets it. Click one and use the arrow keys to nudge it a pixel at a time.
- Nothing is kept until you leave: then you choose Save or Discard. A fight pauses Edit Layout; it comes back afterwards with your changes still waiting. A /reload while editing drops unsaved changes.
- While Edit Layout is open the plates take the mouse, so chat links and window buttons wait until you are done.
- Action bars, unit frames and the rest that the game places show "Move via Edit Mode"; that opens the game's Edit Mode, and Edit Layout comes back when you close it. Edit Mode has a "MelloUI Edit Layout" button too.
- Works with the reskin off as well.
- A moved bag keeps the bags the game stacks on it (above it, then in columns to its left) on the screen with it, wherever you put it.
- Edit Layout replaces Unlock the Windows, Auto Snapping and Reset positions (0.15.0): its bar has the Snap switch and Reset all.

## 🔊 Every click has a new sound

I re-recorded the whole interface. Clicks, pages, pouches, buckles, coins, whispers, the dungeon pop, the level-up jingle. Iron, leather, parchment and stone instead of the stock beeps.

- Off by default, because taste is taste. Turn on the families you like, leave the rest.
- There's a Preview tab with a Play button for every single sound. Listen first, decide after.

## 🎙️ Quest givers talk to you

Every quest offer, progress line, turn-in and greeting is read out loud (and with the voice pack, the objectives too), and so are the pages of books, letters, plaques and signs. With the voice pack every NPC keeps one voice for all of its lines; without it, the game's text-to-speech picks a voice that fits the NPC's race and gender. And it always reads the right quest. Yes, that was a thing.

- A small widget shows who's talking: their face, the line, and a gold ring that fills as it plays, with the time left (a book: the whole book). Point at it for Pause, Skip, the lines waiting and the padlock; subtitles if you like.
- Every quest, every greeting and the books voiced, with the free voice pack below.
- No voice pack? The game's own text-to-speech kicks in (it needs a voice installed in the Windows speech settings). Works out of the box.
- Forgot what a quest was about? Open your quest log, hit Read, done.

**Get the voice pack (free, 2.6 GB, totally optional but so worth it):**

It comes in two parts, and you need both.

1. Download [MelloUI_VoicePack_Part1.zip](https://github.com/MelloCro/MelloUI/releases/download/v0.15.0/MelloUI_VoicePack_Part1.zip) and [MelloUI_VoicePack_Part2.zip](https://github.com/MelloCro/MelloUI/releases/download/v0.15.0/MelloUI_VoicePack_Part2.zip).
2. Unzip both into `World of Warcraft\_classic_beta_\Interface\AddOns`. They fill the same `MelloUI_VoicePack` folder next to MelloUI (if Windows asks about files that are already there, replace them). The `.toc` file must be directly inside `MelloUI_VoicePack`, not in another folder.
3. Had the old pack, `MelloUI_VoiceOverData`? Delete that folder. `MelloUI_VoicePack` replaces it, and MelloUI never uses the old one while the new one is installed.
4. Start the game, tick **MelloUI Voice Pack** in the addon list at the character screen. That's it. `/vo packs` in game shows the pack is loaded.

*(Still on the old pack? It keeps playing until you install the new one, and MelloUI tells you once in chat where to get it.)*

## 🗺️ The map that actually helps

- **Quest List:** every quest in the zone next to your map. Who gives it, where they stand, what's left to do, how much of the zone you've finished. Filters for dungeons, raids, class quests, attunements, events.
- **Pins for everything:** quest givers, hand-ins, dungeon doors, boats, zeppelins, flight masters. Click a door to see its quests, click a boat to get routed to the dock.
- **Smart Route:** a trail of red dots along real roads to wherever you're going, plus an arrow. Cut a corner or take a shortcut? It just keeps going instead of nagging you to turn around. It learns the roads you walk.
- **Service Finder:** need a mailbox, a repair guy, an inn, a trainer? Little icons under the minimap. Click one, the arrow takes you to the nearest.
- **Nearest quest first:** MelloUI's Quest Tracker sorts your quests by distance, shows how far each one is and who takes a finished quest back.
- **Quest tooltips:** an item your quest needs shows your progress; an NPC says "Turn in here" when your quest is ready for them.
- **Flights:** the flight map shows where your route flies and how long it takes, and the arrow counts down to your landing.

## 👥 Small things you'll use every day

- **Party Markers:** your group's class icons float over their heads, green ring for the healer. No more "who heals?" (Open world only, the game hides friendly nameplates in dungeons.)
- **Names:** everyone in Forever has a surname now. Too much? Show first names only. Or last names. Frames, nameplates and your own head, one setting.
- **Bars & fonts:** pick your health bar style, pick a font for text, chat, titles and damage numbers, and how big each one is.
- **Chat:** short channel tags, class colours, input box on top if you want it, one background opacity for every chat window.
- **Auto-vendor:** sells your greys and repairs your gear the moment you talk to a merchant.
- **Quality Gems:** every item in your bags, the bank and the guild bank wears a small gem in its quality's colour (grey junk, white common, then green, blue, purple, orange), so junk and loot worth keeping jump out at a glance. Windows > Bags (the Bank and the Guild bank too).
- **Grey Out Junk** (0.16.0, on): junk (grey quality) items show grey in the same three windows; the
  game's own grey for an item you picked up does not take it off.
- **Special bags** (0.16.0): the slots of a profession or ammo bag (mining, herbs, enchanting, a quiver, a soul
  bag ...) wear their bag type's colour on the slot border, so you see at a glance which slots take what.
- **And:** cooldown numbers on buttons, clean dark tooltips, CC and quest icons on nameplates, FPS and latency, hidden micro menu and bag bar, class medallions on portraits.

## 🧺 Errands, handled

A small round button beside your portrait taps you on the shoulder, then tucks itself away: drink or food running low, new mail, gear wearing out, a trainer with something new. Several at once? One button with a count; point at it and the others slide out. Click one and the arrow takes you to the nearest place for it; close to the NPC, a click targets them. Right-click says "not now".

- **Restock** keeps a list per character (drink, food, arrows or bullets, reagents) and reminds you before you run dry.
- In an inn or a city every reminder stays up until it is done (restocked, a mailbox opened, gear repaired, your new spells or a profession's next rank learned) or you leave.
- At a shop that sells what you are low on, a small shopping list opens beside it. Nothing is bought until you click **Buy**.
- Bags almost full, talent points to spend and Well Fed running out get the same little button.
- So do your buffs: a poison or an oil that ran out on your weapon (while you carry one to put back), one of your own buffs missing on you, and your buffs missing on your group, with their names. They stay up until it is back on, in fights too, and a click puts it back on (out of combat).
- It all lives on the **Reminders** page, one switch per reminder. The Services bar's **Errands** group shows the same reminders.

And what needs you *right now* shows up as small widgets in one column, each with a gold ring for its time: loot rolls (Need, Greed, Pass right there), the way back to your corpse, a timed quest's clock, summons and resurrect offers (Accept or Decline), ready checks, whispers (Reply opens the conversation), a hungry pet (Feed Pet), outbid / sold / won at the auction house, your crafting batch ("Crafting 12 of 20") and a profession cooldown that's ready again. Voice Over lives there too, always at the bottom: nothing moves what's being read, and a fight never stops it. Loot rolls, summons and ready checks sit right above it; at most four show at once (**Most Widgets Shown**), the rest wait in a slim "+2 more" row you can click open, and whispers or the auction house step aside in a fight and come back after. Move and size the column in Edit Layout; each one has its switch on the Reminders page's **Widgets** tab.

## 🧭 Set up in a minute

The first time you log in with MelloUI, a few seconds in, the installer asks how you want to start:

- **Full experience** (recommended): Mello's own setup. The reskin in the Ember palette, the features and Mello's Edit Mode layout, fitted to your screen.
- **No reskin, features on:** the game's look stays and MelloUI's features come on. No Edit Mode change.
- **Reskin only:** the painted look and Mello's layout; the features stay off.
- **Fresh start:** everything off, then one step at a time: the look (the reskin, the palette, Kit Colours, the button borders, class icons), the minimap (Round or Square), parchment and dark mode, fonts, the features, your screen, chat and the windows. Each step's choices start at Mello's own, and nothing changes until you install. On the Features step every feature starts off: switch on the ones you want, or all of them with **All features**. Each one you switch on comes with Mello's own settings for it; the rest wait in `/mello`.

Dark Mode is yours: no setup changes it and no profile carries it. Fresh start's dark mode row starts at your own choice (off on a new character).

Then:

- **Your screen:** Mello's layout was made on a 21:9 screen; the installer fits it to yours (pieces at an edge keep their distance to it, the middle group tightens, then everything is checked for overlaps). Leave the Edit Mode layout out if you like: your own Edit Mode layouts always stay, and your UI scale is never changed.
- **Review:** what will change, before anything does.
- **Install:** your current setup is saved as the profile **Before install** first. Then you have 15 seconds: **Keep** the new setup, or **Revert** to go back at once; if you don't answer, it goes back by itself. A fight or Edit Mode pauses the countdown, and a `/reload` in the middle brings it back with 15 seconds. Before install stays on the Profiles page, so you can load it later too.
- **Done:** take the tour, open MelloUI, or reload once if the fonts over characters' heads changed.

Close it without installing and nothing changes. Run it again any time: **Install…** at the top of `/mello`, **Install again** on its Home page, or `/mello install`. Updating from an earlier version? No installer, just one line in chat. If you put Mello's layout in with 0.13.x, press **Fit to this screen** once on Home > Your setup (or type `/mello layout apply`): the Services row under the minimap is shorter since 0.14.0, and the fit closes the gap under it. The game keeps the Edit Mode layout per character: on another character, `/mello layout apply` makes Mello's layout the active one there too.

## ⚙️ The settings window

`/mello`, or the **MelloUI** button in the game menu (Escape), opens it. A page's name after it opens that page: `/mello chat`, `/mello unit frames`, `/mello fonts` (a module's name works too).

- **Top bar:** on the left, **Preview** (below); on the right, **Install…** (the installer), **Edit Layout** (move and resize the interface on the screen itself, as in Drag. Everything. above; it works with UI Modifications off too) and close.
- **Preview:** see how your interface behaves in a fight before you are in one. The button opens a list: **Solo Fight** and **Party Fight** play everything, then one part at a time: **Fader**, **Reminders**, **Widget Column**, **Party Frames**, **Damage Meter**, **Combat Text** and **Gains**. A click plays a short scene (about 26 seconds) with made-up names and numbers: resting, the pull, a fight, the kill and after it. The settings window steps aside while it plays and comes back after; a strip at the top of the screen names what plays, the moment ("Resting", "In a fight", "After the fight") and has **Stop**. What you set shows as you set it: what you fade In Combat comes back in the fight and fades after it, the reminders hide in the fight, the widgets that wait for a fight's end fold away. Party Fight and Party Frames draw stand-ins where your party frames sit (the game shows its own only in a real group), their health falling and healed back; the meter's numbers and race bar show the made-up group, and the fight summary after the kill says it is made up (it is never in your Fight History). Your Damage shows at your target's nameplate while you have a target. A part whose module is off is dimmed in the list. Out of combat only: a real fight, or opening Edit Layout, stops it at once (the settings window then stays shut). `/mello preview solo`, `party` or a part's word (`fader`, `reminders`, `widgets`, `partyframes`, `meter`, `combattext`, `gains`), and `/mello preview stop`.
- **Side list:** Home, then the pages in five groups, then Profiles: **The look** (Look, Windows, Fader), **Frames and bars** (Unit Frames, Nameplates, Action Bars, Minimap, Bars & Meters, Swing Timers), **Chat and text** (Chat, Tooltip, Screen Text), **Quests and travel** (Quest Tracker, Quest List, Route, Reminders, Gains) and **Sound** (Voice Over, Custom Sounds). Click a group's name to fold it away. A page whose switch is off has a dimmed icon, and a name too long for the list shows in full when you point at it.
- **Pages:** every page is laid out the same way. At the top its name and what it holds, its switch where the page is one module's (Look's is **UI Modifications**: the painted reskin and every feature that tunes the interface go with it; the palette, the UI Shade and Reduce Motion keep working without it) and **Reset this page** (every setting on the page back to its default, on every tab; on a page with a picker, for the one picked and the settings every pick shares; the switches of whole modules and what is your character's own stay; it asks first, saying how many settings change). Under it the tabs, and on every tab the same sections in the same order: General, Look, Text, Layout, Behaviour, Sound, Advanced (a section with nothing in it is left out). Pages and tabs slide and fade in, and the wheel glides the page and the list; Reduce Motion (Look > General) makes all of it instant.
- **Every setting in one place:** each setting lives on one page only. What the whole interface shares (the palette, the Kit Colours, the borders, the Font Style and its sizes, the UI Shade and its areas, the parchment sheets, Dark Mode's brightness, the bar texture and the health bar colours) lives on **Look**. A page it touches shows a **link row**: the setting's value and a button naming the page it lives on (**Look >**, **Minimap >**, **Windows >**) that takes you to it.
- **Pickers:** Unit Frames (Player, Target, Focus, Pet, Party, Raid Frames, Cast Bars, Personal Resource), Action Bars (Action Bars, Micro Menu, Bag Bar) and Windows (every game window the reskin dresses, from the AddOn list to the Trainers) have a picker at the top: the page's settings are for the one picked. **Copy from…** gives it another one's settings; it asks first ("Copy the Target frame's settings to Player?"). **All**, beside a setting, gives its value to every one that has it; it shows while their values differ. A setting that is one for several says **shared**, and its tooltip names them ("One setting for Player, Target and Focus."). Unit Frames shows a live preview of the picked frame in its header, following your settings as you change them.
- **Pictures:** the looks you choose by sight (the borders, the backdrops and backgrounds, the minimap's shape and square border) show the chosen one's picture. Click it and every choice opens as a picture under the row; a click on one puts it on at once. Not in a fight.
- **Dimmed options:** an option that needs another switch, or that the one picked does not have, is dimmed and says why ("Switch on "UI Modifications" first (Look).", "Not for Pet"). When that switch is on another page or pick, a click on the dimmed option takes you to it.
- **Search:** the box at the top of the side list finds any setting, page, tab or pick. Type two letters or more: the list shows what matches, best first (a name that matches, then its place, then what it does), each with its place over its name as a breadcrumb (Page > Tab > Section: "Unit Frames > Buffs & Debuffs > Layout") and the New tag if it is new; "Bank" finds "Windows > Bank". Point at a result for its whole place and what it does. Click one, or pick it with Up and Down and press Enter: its page opens on its tab and pick, at that setting, which lights up for a moment. Escape, the little X or an empty box brings the side list back. If a fight starts while you type, the keys go back to your character and your search stays.
- **Home:** the Tutorial, What's new (Earlier versions for the rest), Your setup (the profile in use, with a list to load another; the palette and your Kit Colours, each with Change… to its row on Look; your screen, with **Fit to this screen** when Mello's layout was fitted to another one; Install again) and Help with every command.
- **New tags:** everything this update added (a switch, a slider, a dropdown, a button) has a small gold **New** tag right after its name. The tags also lead the way: on its page's entry in the side list (on a group's name while it is folded), on the tab that holds it, inside the **Edit Layout** button, and at the top of What's new. The next update's new options get the tags; this update's go away by themselves.
- **Long lists:** a dropdown with many choices (the fonts, the Windows picker) shows 18 at a time, never more than half the screen, with a scroll bar; the mouse wheel scrolls it, and it opens at your current choice.
- Drag the window by its top edge: it stays where you put it. Escape closes it. At a large Font Style a page's tabs take a second row.

## 💾 Your settings are safe

The game saves your settings like any addon's, so they're still there after a restart. Profiles let you save and load whole setups too.

Want an extra copy? **Macro Backup** on the Profiles page (off unless you turn it on) keeps one in your account macros, which the game keeps for your whole account: handy for a new PC or a wiped `WTF` folder. The copy is only ever brought back when you ask: **Restore…** on the Profiles page, or `/mello backup restore`. Turn it off and its macros are removed. The `MelloUI1`, `MelloUI2`... macros earlier versions kept are removed by themselves once your settings have loaded normally, so their slots are free again.

## 🐛 Good to know

- Not every Forever-only NPC is recorded yet; those lines use text-to-speech for now.
- Instance doors new to Forever show up on the map after your first visit (or `/qlmap entrance`).
- Where no road is known yet, the route goes over the walkable ground (0.17.0: measured from the game's own terrain, so it goes round ridges and cliffs). Only where the ground is not known (in an instance) is it a straight guess, and the arrow then says "straight · no known way". Walk it once and it learns.
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
that is applied when the addon starts with no settings at all, such as on a fresh install; out of the box
that is the built-in **Everything Off** profile (every module off, made from the module list
at each login, so it cannot be deleted or overwritten), and the installer opens a few seconds
later (*Set up in a minute* above). The installer adds two more: the shipped **MelloUI**
profile is its Full experience, and **Before install** is the setup you had before you last
installed. Profiles are
kept in the saved variables with the rest of the settings, so they stay from one session to the
next. The Profiles page also holds **Macro Backup** (see *Your settings are safe* above). On a development copy, `Tools\bake_routes.py --watch` (the same watcher that bakes the
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
| `/mello status` | whether the client loaded the saved variables, where the settings in use came from, and the state of Macro Backup |
| `/mello backup ...` | Macro Backup: `on`, `off`, `restore` (asks first) or `delete` (at once); with no word it says how the copy stands |
| `/mello profile ...` | `save <name>`, `load <name>`, `delete <name>`, `default <name>` or `default none`, `export <name>` (a share string to copy), `import <name>` (paste someone's string in as that profile), `list` (see *Profiles*) |
| `/mello cpu` | CPU time per handler and hook of every module since login (needs `/console scriptProfile 1` and a `/reload`); `/mello cpu reset` zeroes the counters |
| `/mello preload` | How many artwork files Preload Artwork holds, and how many the game has loaded |
| `/mello preview solo` / `party` | a short scene of how the interface behaves in a fight, alone or in a group (the settings window's **Preview**) |
| `/mello preview <part>` | one part alone: `fader`, `reminders`, `widgets`, `partyframes`, `meter`, `combattext`, `gains`; `/mello preview stop` ends it |
| `/mello swing log` | 20 seconds of your swings and shots as the game reports them, to copy from `/mellolog` (Swing Timers) |
| `/mello help` | the command list in chat |
| `/mello tutorial` | the guided tour of the settings window (also the Tutorial button on its Home page) |
| `/mello install` | the installer: a setup for the whole interface, fitted to your screen, with 15 seconds to keep it or go back (also **Install…** in the settings window's top bar and **Install again** on its Home page) |
| `/mello edit` | Edit Layout: move and resize the interface (also **Edit Layout** in the settings window's top bar); `/mello edit dump` logs every element it knows, and why one has no plate, to the copy window |
| `/mello layout` | the Edit Mode layout the reskin is drawn for: `apply` fits it to your screen and puts it into Edit Mode as an account layout ("MelloUI", or "MelloUI <width>x<height>" on another screen size) and makes it active (done once by itself when you switch the reskin on by hand; the installer puts it in for you), `export` prints the active layout's share string for baking into `Media\EditModeLayout.lua` |
| `/mellolog [clear]` | the copy window with what the dump commands logged (`clear` empties it) |
| `/mello combattext test` | Combat Text: a few sample lines in the chosen style |
| `/vo ...` | Voice Over: `stop`, `pause`, `skip`, `test`, `voices`, `npc`, `packs`, `lines`, `reset` |
| `/qlmap` | Quest List map pins: diagnostics, and `dock`, `zeppelin`, `arrive`, `entrance`, `remove`, `list` to record pins by hand (see Quest List) |
| `/route` | Route: how much has been learned, the current route, your map and how Route places you on it, and how many flight times it has learned; `/route quest` (what the client reports for the tracked quest), `/route clear`, `/route arrow reset`, `/route reset confirm`, `/route dots` (the route painters, for the copy window) |
| `/services [kind]` | Services: open the nearest-service menu, or route straight to the nearest `repair`, `mailbox`, `innkeeper`, `flight`, `auction`, `bank`, `class trainer`, `profession trainer`, `barber` or `transmog` |
| `/restock` | Restock: your Restock List window (what this character keeps in its bags) |
| `/sfx` | Custom Sounds: the state; `/sfx play <name>` auditions a sound, `/sfx list` names them, `/sfx log` prints every sound kit the game plays and what replaced it, `/sfx kit <id>` what a kit maps to; `/sfxdump` the last sound events in the copy window |
| `/kitwhat` | every kit texture under the mouse cursor, back to front: the piece, its size, its crop, its tint, the frame it is on (for a background that is not the one expected) |
| `/xxdump` | every reskinned window and HUD area has a dump command that logs its frames to the copy window: `/cpdump` (character), `/sbdump`, `/profdump`, `/legdump`, `/qldump` (quest log), `/gfdump`, `/gdump` (guild), `/coldump`, `/socdump`, `/ufdump`, `/cbdump`, `/rfdump`, `/abdump`, `/bagdump`, `/mmdump`, `/trdump`, `/chdump`, `/dmdump`, `/ttdump`, `/npdump`, `/pmdump` (party markers), `/icondump` (class icons), `/sfxdump` (custom sounds), `/kitdemo` |

## Modules

### Palettes and the UI Shade (UI Modifications)

**Palette** (UI Modifications, set on Look > General above Kit Colours, or on the installer's Look
step; Home's Your setup names it): Ember (the default), Obsidian, Obsidian Vibrant,
Royal Azure, Royal Azure Vibrant, Fel Ember and Fel Ember Vibrant. A palette is ten colours
(the window, the inner panel, raised panels, borders, trim, text, muted text, the selected tab,
its gold trim, the hover), and everything MelloUI draws takes its colours from the one in use:
its windows, texts, highlights, the notice, Route's lines, the shades. Each palette but Ember
has its own painted kit (`Media\Kit<Name>`); **Kit Colours** then offers that kit or the
Original, and under Ember Warm iron, Bronze and the Original as before. A switch changes
everything at once, with no `/reload`, and works with UI Modifications off too. The installer's
Full experience and Reskin only put in Ember; No reskin and Fit to this screen keep yours. A few
colours carry a meaning and stay the same in every palette: the chat channels, Voice Over's
states, Route's straight-guess blue and beam red, the map's quest-giver blue, and the dark red
of what you can't use or learn (merchants, trade, trainers).

**UI Shade** (on) and **Shade Strength** (70 %, 30-90 %) on Look > General, with a switch per
area there (each area's own page links to it): Windows, Action Bars, Cast Bars, Unit Frames,
Chat (the whisper popups too), Bags, Minimap (and the Services bar), Tracker (the objective
tracker and the Quest Tracker), Buffs, Event Widgets and Nameplates. Every outline piece of the painted kit gets a soft dark shade of its own shape,
laid under it so it never darkens the window's own stone: the outer rails, title plates, rings
and crests of the windows, the bars' backdrops and end caps (and the rims of bars with no
backdrop), the brackets and plates of the cast bars, the rings, name plates, bar brackets and
orbs of the unit and party frames, the chat rail, tabs, minimized card and input box, the
minimap's ring or square frame and zone plate, the tracker's rail and title plate, each aura's
rim, the battleground and event widgets' bars (and a soft band behind their score and timer
lines), and the nameplates on Whole plate. A window gets its shade on its first show; nothing
is made at login for what you have not opened. The shade takes the palette's darkest tone and
needs the reskin (each area follows its own part of it).

### Quality Gems (Backpack Kit)

**Quality Gems** (on; Windows, on the Bags, Bank or Guild bank pick): every item in the bag windows,
the bank and the guild bank shows a small gem in the top-left corner of its slot, in the game's
own colour for its quality: grey for junk, white for common, green, blue, purple, orange, and the
artifact and heirloom colours. It is the gem the parchment tooltips put before item names, about
a third of the slot's size, 2 px in from the icon's corner; the stack count keeps its corner.
While the game shows its own mark in the top-left corner (the junk coin at a merchant, the
upgrade arrow, the "!" on an item that starts a quest, the quality badge on a crafting reagent,
which crafted gear wears while the Professions window is open) the gem moves to the top-right
corner, and a slot the search box dims has its gem dimmed too. An empty slot shows none, and
neither do the bank's bag slots (they hold bags). The gems belong to the painted slots: a window
whose reskin is off (its Painted Skin on the Windows page, or the reskin itself) shows none. The
one switch covers all three windows and shows on each one's pick, live while that window's
Painted Skin is on, so it can be changed on the Bank while the Bags' skin is off. Nothing is made
at login: a slot's gem is made the first time it holds an item, and the game's own updates of the
slot recolour it.

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
- Hide the chat window background and border art, the input box art, and optionally the
  tab background.
- Chat Buttons (0.17.0, on; Hide Chat Buttons before, which hid them): the game's own chat
  buttons in their column left of the chat -- the chat menu (Say, Party, Raid, Guild, Yell,
  whisper and reply, macros, emotes and voice emotes, and the language you speak), Channels and
  Friends with its online count. With the chat reskin they wear the whisper window's round
  buttons (the kit's rim, a dark disc, our glyph); every click and menu stays the game's, so the
  language you pick is the game's own choice. While you speak more than one language, the one you
  speak shows at the right end of the line you type in, and what you type stays clear of it.
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
- Whisper Popup Window: each conversation gets a small window of its own. Its header has four
  buttons (0.16.0): Add Friend, Invite To Group, Ignore (it asks first) and Report. Report opens
  the game's own report window for their last whisper; it is the chat's own "report this line"
  link, clicked through the chat frame's own handler, so the game lets the report be sent. A
  button dims when there is nothing to do (a friend already, in your group, ignored, no whisper
  from them yet) and its tooltip says why. A Battle.net conversation has Invite (while they play
  this game) and Report.

### Names

Characters on this client have a first name and a surname. UI Modifications has one "Show Names
As" dropdown (Look > General): first name, last name, or both, for everything at once: the player,
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

**Threat Line** (on, 0.16.0; Nameplates > Plates): in a group fight, a thin bar along the bottom of
an enemy's health bar -- in the groove of the Nameplate Kit's lower rail, the bracket its outline;
without the kit along the bar's bottom edge with a thin dark edge -- fills toward the point
where the mob would turn on you: gold while safe, amber from 80 % of the pull, red once it is on
you. For a tank (the TANK role, else Defensive Stance or a bear form) it is gold while the mob is on
you and red when it is not. No number, nothing else. Where the game keeps the numbers secret (in
the open world it often does for a nameplate) the bar takes the secret value itself: the game draws
it, MelloUI never reads it, and its colour follows the threat state while that is open (gold when
that is secret too). Solo, out of a fight and on friendly plates it stays away. One reader with the
Threat widget: Core/Threat.lua.

With the reskin's Nameplate Kit on, the level circle sits on the right end's diamond and covers it (0.16.0: the game's
level frame stays where the game lays it; only its circle, number and target ring move onto the diamond), and the
name is centred on the bracket, gem to gem. The name above each health bar sits on a soft dark band, as long
as the name, that fades out at its ends (Name Shade: Name, the default). Whole plate adds a soft shadow that follows
the plate's own shape: round the level circle, round each end gem and along the bar, in every
Nameplate Border look; this needs the UI Shade and its Shade: Nameplates switch on (Look >
General). Off: no shade. Shade Strength sets how dark it is (the nameplates' own, apart from the
UI Shade's). Both sit on Nameplates > Plates, with the nameplates' Painted Skin.

### Tweaks

- Hide the micro menu and/or the bag bar. They come back while Edit Mode is open so they can
  still be moved.
- With the bag bar hidden, the bag slots dock under the open bag window (combined or separate
  bags) so bags can still be equipped and removed. Off switch: "Bag Slots on Bag Window".
- Hide the player coordinates the client writes under the minimap ("Hide Minimap
  Coordinates", on by default).
- "Chat Notices" (on by default) covers the lines MelloUI writes to chat on its own: a
  learned dungeon entrance, a note about the macro backup's copy, hints. Replies to slash
  commands always show.
- "On-screen Notices" (on by default): MelloUI's one on-screen notice, the short line in the
  upper third of the screen that Route, the Services bar and the Quest List use (a route set
  or finished, a service remembered, a dungeon's quests listed). Soft text in the palette's
  colours (gold for a new destination or an arrival) over a dark shade with soft edges, in
  your Font Style; held four seconds, then faded (at once with Reduce Motion). It works with
  Route off. Edit Layout shows a sample line there to drag; its Reset puts it back at the top
  centre. Under it: "Send To Chat Instead" (off; the lines go to the chat, where
  Chat Notices applies) and "Notice Sounds" (on).
- "Zone Text Shade" (on by default): the game's zone text -- the zone's name when you enter
  a new area, the subzone under it and the PvP line ("Contested Territory", "Sanctuary") --
  in the notice's look: each line on the same soft dark shade, without the outline (Outlined
  Text brings it back for both), in the game's own colours and sizes, fading as the game fades
  it. Off: the game's own look.
- "Centre Text Shade" (on by default), after Zone Text Shade: the game's messages in the middle
  of the screen -- the red errors ("Not enough energy"), the yellow info lines such as quest
  progress, raid warnings and boss emotes -- in the notice's look: each line on the same soft
  dark shade, fading as the game fades the line, without the outline (Outlined Text brings it
  back), in the game's own colours. Private boss emotes keep the game's look. Off: the game's
  own look.
- "Outlined Text" (off), after Centre Text Shade: draws the notice's lines, the zone text and
  the game's centre messages with an outline. It is not under On-screen Notices, so it also
  sets the zone text's outline with the notices off.
- Numbers Over Enemies (Screen Text > Combat Text; it was World Text Scale) slider (0.5x to 3.0x, default 1.0x) for the floating damage and healing
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

With Tooltip Parchment on, a gem before an item's name shows its quality, and one before a player's name shows their class. The name is in dark ink, or in a dark shade of its reaction colour where the game shows one (unit frames, Class Coloured Names off). NPC names keep a dark shade of their reaction colour and have no gem.

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

Fading the player frame out of combat (0.14.0's Fade Out Of Combat) is the **Fader**'s since
0.17.0 (below): its Player Frame row, Faded Opacity and Pet Frame Too; your settings carry over.
The Unit Frames page has a link row to it.

### Fader

The Fader page (The look, 0.17.0; off by default, its switch in the page header) fades parts of
the interface away while you do not need them. Each element has one **Show** choice:

- **Always**: never faded (the default).
- **In Combat**: faded out of combat, back at once in a fight (no fade racing the fight); also back
  with a target (**Show With A Target**, on) and while you point at it (**Also Show On
  Mouseover**, on).
- **On Mouseover**: faded all the time, a fight too, and shown only while you point at it. A
  short grace when the pointer leaves, so moving from one button to the next does not flicker.
  Keys still work on a faded bar, and an On Mouseover bar at 0 % still shows when you point at it.

Every element also comes back while Edit Layout, Edit Mode or the configurator is open. The
elements: **Frames** (Player Frame and **Pet Frame Too**, Target Frame, Party Frames, Raid Frames,
Buffs & Debuffs), **Bars** (Main Action Bar, Action Bar 2 to 8 each on its own, Stance & Pet Bar,
Micro Menu, Bag Bar, Experience & Reputation Bars; and the Reminders by your portrait under Frames)
and **Chat & Map** (the chat with its tabs, buttons, the Friends button and the line you type in, the
Minimap with its band and the Services row, the Quest Tracker, the game's Objective Tracker, the
Widget Column, and Route's arrow and World Marker). **Fade Everything** puts every element on In Combat,
**Fade Nothing** on Always. **Faded Opacity** (0-50 %), **Fade After** (how long it waits after a
fight, a target or the pointer leaving; 1.5 s) and **Fade Speed** (0.6 s; coming back is always
quick; Reduce Motion: at once) shape it.

Its own reasons keep a few things up: the player frame while your health or mana is below full
or you are dead (this client keeps your health, and usually your mana, hidden from addons, so
MelloUI goes by the game's own updates: the frame stays while your health or mana is still
changing, and after a spell's mana cost it waits out the five-second pause), the pet frame while
your pet is hurt, the chat while you type. The reminder button beside the portrait (its own row,
Reminders) and your cast bar stay in full view while the player frame is faded. Left out on purpose, as they only come up
when they matter: Gains, the cast bar, the damage meter's
race bar and summary, Combat Text and the notices. (The reminders, the widget column and Route's
arrow and marker fade their own way too: the Fader fades a frame they sit on, so neither gets in the
other's way.) The page also holds **Windows Fade In** (the
game's windows fade in when they open) and the chat's **Tabs Only On Mouseover**, with link rows
where they were.

The Fader only sets the alpha of each part (never shows, hides or moves one), on top of the
alpha the game gives it (Edit Mode's Opacity of the unit and aura frames is kept). `/mello fade`
opens the page.

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
offers, quest progress and turn-in text. A quest's objectives are only ever the voice pack's
recording ("Quest Objectives", on by default): text-to-speech never reads them. Speech is not
tied to the window, so the NPC keeps talking while you walk away; a new dialog interrupts the old
one and `/vo stop` cuts it off. Voices are the ones installed in Windows (Settings, Time & Language,
Speech); the Windows 11 natural voices become available to the game through the open source
NaturalVoiceSAPIAdapter.

Each NPC is looked up by ID in `Media\NPCVoiceData.lua` to find its race and gender, and every
race group can be given its own voice. NPCs missing from the data use the male / female voice;
`/vo npc` shows what the module knows about the targeted NPC and `Media\NPCVoiceOverrides.lua`
adds or corrects entries by hand. The Voices tab's text-to-speech settings (the Male NPCs and
Female NPCs voices, Speed, Volume and the voice per race) only change text-to-speech: a recorded
line keeps its own voice, pace and volume (the Sound Channel's), so they are dimmed while "Read
Unvoiced Lines" is off, and a click on one goes to that switch. (0.15.0 dropped the race pitch and
speed profiles: a recording cannot be sped up, so they only ever shaped text-to-speech.)

`Media\NPCVoiceData.lua` is generated by `Tools\extract_npc_voices.py` (Python 3, standard
library only) from the cmangos vanilla database, wago.tools DB2 exports and the wowdev
listfile, plus the Forever client's own `creaturecache.wdb` for NPCs you have met that are not
in the vanilla data. Re-run it now and then to fold in newly met NPCs.

Lines are queued and read one after another (a greeting finishes before the quest offer that
follows it; greetings never wait behind quest lines), advancing on the client's playback
finished event. The **widget** (0.16.0; one row of the widget column, see Widgets below; it
replaced the 600 x 200 overlay) shows the speaking NPC's 3D face in the round rim, playing its
talk animation (the book for a page or an object, and with 3D Portrait off), the NPC's name, the
line with its kind's bullet, and a gold ring round the face that fills as the line plays: a voice
pack line by its clip's exact length, a text-to-speech line by the estimate (its time with a
"~"), a book as the whole book ("Page 2 of 5 · 1:52 left"). The count is the lines waiting.
Paused, the ring stops and dims and the face goes dark under a pause glyph (a resume starts the
line again). Point at it for its buttons: Pause / Resume (a click on the face too), Skip (Stop
when nothing waits; it ends a book too), Lines (the tray: every line's length and "3 lines: 0:39
left in all"; a click skips the one being read or takes a waiting one out) and the padlock (Lock
The Widgets). Right-click stops. Subtitles show the text under the line in pages that fit (split
at sentences), turning as the voice goes on. The kind bullets and the book come from the
VoiceOver addon (`Media\Textures\VoiceOver`, Unlicense).

**The voice pack.** `MelloUI_VoicePack` (0.15.0; a separate, load-on-demand addon, downloaded in
two parts from the v0.15.0 release) gives every NPC one voice for all of its lines. Its one index,
`index.lua`, maps a key to a clip (`sounds\<voice>\<hash12>.ogg`) and the clip's length: quest
lines by `<questID>-<kind>` (accept, objectives, progress, complete; `m-` / `f-` in front for a
line whose words depend on the player's sex; `-<npcID>` behind where a second giver or turn-in NPC
has a voice of its own, `-0` for an object or an item, read by a narrator), every text an NPC's
window shows by `g-<npcID>-<hash8>` (greetings, gossip pages, quest-giver and trainer greetings:
a hash of the words with the player's name, class and race left out; a changed text still plays
when at least 40% of its words match), and the pages of books, letters, plaques and signs by
`r-<hash8>`, read by the narrator. Quest IDs are read once the quest panel has settled (the client
can still report the previous quest when the event fires), else looked up by title. The speaker is
the dialog's NPC, never the target, and a clip in another voice than the NPC's is not played. The
module loads the pack on demand and plays its line whenever it has one; everything else is read
with text-to-speech, unless "Read Unvoiced Lines" is off: then only recorded lines are heard and the
rest stays silent (the quest log's Read button included). The channel the recordings play on can
be chosen (Master by default). "Prefer Recordings" (off by default) plays an NPC's only recorded
greeting even when Forever changed the greeting text, instead of reading the new text. `/vo packs`
shows the pack's build and counts and the last lookups.

**The old packs.** `MelloUI_VoicePack` replaces `MelloUI_VoiceOverData` (the pack offered up to
0.14.0) and the VoiceOver data packs before it (`AI_VoiceOverData_Vanilla`). The old pack is no
longer offered. While `MelloUI_VoicePack` is installed, only it is read: the old packs are never
loaded, not even for a line it lacks. With only an old pack installed, it still plays as it did
(quest lines by quest ID, a renumbered vanilla quest through its title and giver, greetings by NPC
and text), and MelloUI says once per account in chat where to get the new pack. The VoiceOver
player addon itself is not needed and should be disabled so lines are not read twice.

**Building the voice pack (maintainers).** The tools are `Tools\voice_v2_*.py` and the
`Tools\voice_v2` folder (`Tools\voice_v2_pack.py`'s header describes the addon it builds); they
write to `MelloUI-BuildData\output\voice_v2`:

1. `Tools\voice_v2_lines.py` (`Tools\voice_v2\export_lines.py`) exports every voiceable line as a
   manifest, `lines.json` (`--readables` for the book pages: `lines_readables.json`): the texts from
   the classic-db dump, the cached Wowhead pages of Forever's quests and items, the Forever client's
   caches and the lines the in-game collector kept; every line gets one speaker, and every NPC its
   one voice from `Tools\voice_v2\npc_voices.csv`.
2. `Tools\voice_v2_voices.py` keeps `voices.json`, the voices (made from the game's own NPC
   recordings) and their seeds.
3. `Tools\voice_v2\generate.py <manifest>` makes the clips on the speech service, batch by batch,
   into the clip library (`clips\`); a re-run only makes what is missing.
4. `python Tools\voice_v2_pack.py lines.json lines_readables.json` checks every key, clip and voice
   and builds the addon into `output\voice_v2\MelloUI_VoicePack` (`--check` checks only;
   `--install` copies the build into the game's AddOns folder, only when asked). It never writes
   to any folder but one named `MelloUI_VoicePack`.

The module still records every greeting and quest line it sees when asked ("Record Dialog Lines",
off by default) into the `MelloUIVoiceLines` saved variable, which the game saves at logout and on
`/reload` and keeps from one session to the next; the export reads it for the Forever texts no
other source has. `/vo lines` shows what has been collected so far.

**The old pack's tools** (kept for reference; `MelloUI_VoiceOverData` is no longer built or
offered): `Tools\merge_voice_packs.py` merged `AI_VoiceOverData_Vanilla` and
`AI_VoiceOverData_Forever` into that pack and zipped it; `Tools\build_voice_pack.py` built new
Forever lines straight into the installed pack.
`Tools\export_voice_lines.py` merges each saved file into
`Tools\cache\voice_lines.json` and writes `Tools\output\forever_voice_lines.txt` / `.csv`: every
line with no usable recording, grouped by NPC with a race and gender hint, placeholders replaced
by spoken words, and the file name each MP3 should get. Generate the lines (the vanilla pack's
voices were the author's own ElevenLabs clones; cloning a few of the pack's MP3s per race and gender gives matching voices), then
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
the giver's voice (the voice pack's offer line when it has one, else text-to-speech unless "Read
Unvoiced Lines" is off), then the voice pack's objectives line when it has one and "Quest
Objectives" is on. The objectives and their counts are never read with text-to-speech.
The giver comes from the Quest List data (every vanilla and Forever quest carries its giver's
NPC id), so the race and gender voice is right even for quests accepted long ago. The
description read this way is collected like any other line, so old quests without a recording
get generated too; the objectives are not.

**Books and letters.** "Read Books And Letters Aloud" (on by default) reads books, letters, notes,
plaques and signs (the game's item text window) in a narrator's voice, and it reads the whole
book: the page you open, then every page after it in order, each one as the page before ends, with
no page turning. Closing the book, or walking away so the game closes it, does not stop it.
Turning a page by hand reads on from that page, opening another book reads that one instead, and
Stop (the widget's button with nothing waiting, `/vo stop`) ends it; `/vo skip`, the widget's Skip
or a click on the line in its tray skips to the next page. The widget's line says which page is
read ("Page 2 of 7") under the book's name, and its ring covers the whole book. A page opened while a quest line is read waits for it, as before; a quest line opened
while a page is read comes after that page, then the book goes on. The pages come from the voice
pack: its index keeps each book's pages in reading order (`P.readPages`), and when two books share
a name, the page's words, its number and whether the window shows a next page tell which one is
open. Without the voice pack, or for a book it does not have, only the page shown is read, with
text-to-speech when Read Unvoiced Lines is on. Switched off, no page is read at all.

Commands: `/vo stop`, `/vo pause`, `/vo skip`, `/vo read`, `/vo test`, `/vo voices`, `/vo npc`,
`/vo packs`, `/vo lines`, `/vo reset`.

### Quest List

A page in the world map's quest log, styled like the quest log, listing the quests picked up
in a zone. A button on the quest log's top row, where the game shows its quest count, switches the
column between your quest log ("Quest List") and the list ("Quest Log" takes you back); the
column remembers which one it showed, and opening a quest's details shows the log until you go
Back. The list has a "done / total" count, then every quest under collapsible gold headers, one per
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
searches every zone by quest title, giver or zone. The dropdown under it picks the view; the gear
beside the search box holds what quests start from (a quest giver, a mob drop, an item picked up,
unknown), Hide quests 5+ levels above me and Hide completed quests. Options: hide completed; other faction's and other classes' quests (off by
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

**Tooltips** (Quest List, Tooltips; both on by default). An item one of your quests asks for
shows the quest and your progress ("Quest: Red Linen Goods (4/6)", muted once that objective is
done; left out where the game shows its own quest line). An NPC who takes one of your quests
back says "Turn in here: <quest>" once it is ready, and a quieter "Quest ends here: <quest>"
while it is in progress, ready ones first, at most five and then "and N more of your quests".
Only the quests in your log are looked at, and only when a tooltip shows after the log changed,
so nothing runs while nothing is hovered. For other modules: `MelloUI:QuestTurnIn(questID)`
gives the turn-in NPC's name, id, continent, world position and zone, also with the Quest List
off (the Quest Tracker's turn-in line uses it).

**Zephras Isle and neutral characters.** The isle's map has no continent above it, so the Quest
List takes the isle as its own continent: its givers and turn-ins land on its map and the
Current Continent view lists its quests. A character that has not chosen a faction yet sees the
quests open to both factions.

### Route

The ground (0.17.0): besides the roads traced from the map art and the paths you walked, Route knows
the walkable ground of both continents and Zephras Isle, measured offline from the game's own
terrain (slopes over about 50 degrees are walls, deep water is swum at a slower pace). Routes go
round a ridge instead of over it: from Northshire to Stone Cairn Lake the way leads out of the valley
and round. A road always wins a like way over open ground. The straight line to the goal, the legs
from you and to the goal onto the roads, and the jumps between two paths are taken only where the
ground is walkable. Where no ground is known (an instance) the old rule stays: a route far longer
than the straight line gives way to a straight guess, and the arrow then reads "444 yd straight ·
no known way" instead of a time. Buildings, bridges and caves are not ground: the traced roads
cover towns and bridges, and a road always counts.

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
nothing is super-tracked). An objective that needs an item in your bags first (Marla's Last
Wish: Samuel's Remains, dropped by Samuel Fipps, before Marla's Grave) is routed to where the
item comes from (the creature that drops it, the object that holds it, else a vendor) until
the bags hold it: the route, the arrow, the World Marker (Route puts its own map pin on the
source, the way it does on a dock, while every open objective waits on an item; remove the pin
and the quest stays followed without it) and the Quest Tracker's "First: loot Samuel's Remains
from Samuel Fipps" line under the objective; the moment it is looted they all go to the
objective and the quest is super-tracked again. An item used up by the objective's own step (a
carcass that calls the beast, remains buried) still counts until the objective moves on, five
minutes at most. Where several are dropped for the quest, as many as the objective still lacks
are asked for, or all at once where one thing is made of them. The client has no road or terrain data
for addons, so the roads come from two places: the ones traced from the zone maps' art
(`MelloUI_Companion\RoadData.lua`, loaded when a route is needed; see *Traced roads* below) and the ones the module learns from you: every
half second outdoors it drops a breadcrumb and links it to the previous one, flights you take become links, opening a flight
master's map records the links from there to every reachable point, and the boats, zeppelins
and the vanilla flight network from the Quest List data connect the rest (only flight points
your character has discovered are used). A route is the cheapest way through that graph, in
seconds, with straight legs to reach it; where nothing has been learned yet it is a straight
line. Routes may cross continents: walk to the dock, boat, walk.

The route is drawn as a chain of red dots (0.16.0; small gems before): solid along paths you
have walked or that were traced from the map, paler and farther apart where the route is a
straight guess, smaller and farther apart for a flight or a boat leg. On the minimap the
nearby part is drawn the same way, clipped to the minimap's shape. A direction arrow (the
minimap's own player arrow at double resolution, top centre of the screen by default, drag to
move, `/route arrow reset`) points along the next leg relative to where you face, with the
remaining distance and about how long the rest of the way takes ("1.2 km · about 2 min") and
the destination's name and icon under it. Every new destination shows
a line in MelloUI's on-screen notice (see Tweaks: On-screen Notices) with the client's
super-track chime ("Tracking quest giver Marshal McBride for Kobold Camp Cleanup, 240 yd away"),
and arriving shows "Arrived" with a softer sound; On-screen Notices and Notice Sounds switch
Route's lines and their chime, as every notice's. Within 25 yards of a pin the
route ends and the pin is cleared; near a quest objective the drawing pauses but the
destination stays. Options: the two drawings, the dot size, the distance text, the travel time, the arrow, the
World Marker and its beam, arrival distance, the flight help, and learning on or off (the text shade is Look's one
Text Shade, the arrow's size Edit Layout's).

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

World Marker (on by default; 0.15.0 states): a gem hung on the game's own navigation point over
the destination. Far away it is a *beacon*: the gem with the red Light Beam rising from it (a
ring of light on the ground at its foot, the gem lit red by it; 0.16.0) and the distance and
travel time under it, faint while it stands in the middle of the screen, where
your character is. Within 100 yards it becomes the *pin*: the beam fades out on the way in, the
gem lands on the place with a small pop and stays on top of the NPC, object or item's source
until it is done (never faint). Off screen, an arrow beside your character points the way to
turn. Inside a quest's objective area (a camp to clear, a field to search: the client's quest
area, where it can say) the marker hides, the game's own marker too, and comes back once you
leave; one spot never hides it, nor Route's own pin, nor a quest MelloUI has no objective places
for (the game's own point could be one NPC). Every border has a buffer so it never
flickers from one look to the other: the pin at 100 yards in and 115 out, the screen's edge a
little inside on the way back, the middle of the screen, and the area's border (back only 10
yards out of it, or after 3 seconds).

The first route of a session waits a few seconds while the road data loads: meanwhile the
on-screen notice says "Loading navigation..." (a Route line: the notice's own switches apply,
no sound) and the direction arrow breathes, turning slowly round while it
has nothing to point at yet (with Reduce Motion on it is not shown until it has); both go the
moment the route is ready. A load the game puts off until a fight is over says nothing until
it really starts.

**Flights** (Route, Flights; both on by default). *Flight Map Help:* when a flight master's map
opens, the route is planned again from the flight points you know, and the map's title band
says where it flies and about how long it takes ("Route: fly to Sentinel Hill · about 1:16"),
in the palette's gold on the soft text shade; a small gem pulses on that flight point's button,
never on the picture. Pointing at a flight point adds its flight time to the tooltip ("Flight
time: about 1:16"), and "Your route flies here" on the wanted one. *Landing Countdown:* once you
take off, the on-screen notice says "Flying to Sentinel Hill, about 1:16", and the Direction Arrow
(when it is on) points at the landing, also with no route set, counting down ("Landing at
Sentinel Hill in about 0:52", then "soon"); on landing it says "Landed at Sentinel Hill (1:22)"
and the arrow goes back to the route. Flight times come from your own timed flights first
(learned per pair of flight points, kept with the learned paths), then the flight path data,
then a straight line at flying speed.

**Where Route can't place you.** Some maps have no continent above them (Zephras Isle, the
Skyborne start): Route takes such a map as its own continent, so you are placed, routed and
served there like anywhere else. Where the game gives no position at all, Route says "Route
can't place you on this map (<name>), so there is no route from here." once per map and
session (not in instances or on flights, and only with On-screen Notices on), and `/route`
names your map and why.

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
(Route's own lines, through the on-screen notice); `Where` and `WantWhere` with the bus topic `where`
(where the player is, every 2 seconds while someone wants it and only after 10 yards of
movement: the Quest Tracker's distances and the reminders' reach), `WorldYards`,
`ObjectivePlaces`, `ItemFirst` (what to do first for an objective whose needed item is not in
the bags), `PinnedQuest` (the quest Route's own pin follows for now), `FollowedRemaining` (the
way left along the route followed), `YardsText`,
`PlaceNear` (a named town, camp, flight point or sub-zone near a point), `ContinentOf` and
`PlayerSide` / `SideOpen` (a neutral character's rows are the ones open to both factions). A line of any module's own goes to the on-screen
notice with `MelloUI:Announce(text, kind)` (Core/Notice.lua), which works with Route off; a line
held for as long as its caller waits on something (Route's "Loading navigation...") with
`MelloUI:AnnounceWait(text)` and let go with `MelloUI:AnnounceDone(text)` (no sound, no 4 s hold;
a new line takes its place as ever). The
soft band behind its text is the shared `MelloUI.Shade:Band` (Core/Shade.lua).

### Services

A bar of service icons under the minimap (it moves with the minimap in Edit Mode), in groups
or in two rows (Button Layout, below): repair,
mailbox, innkeeper, flight master, auction house, bank, class trainer, profession trainer,
barber and transmogrifier, drawn with the client's own minimap tracking icons. Hover an icon
for the nearest one's name and distance; click it and the Route module takes the few closest
candidates, routes to the one that is cheapest to reach by road, boat or flight (a bank across
the river is not "nearest" when the bridge is a long way round), but one in your own zone wins a
near tie (at most a quarter farther, or 300 yards, whichever is more: from Deathknell the Brill
innkeeper, at Silverpine's border the Sepulcher's, which is clearly nearer), drops the map pin on it and
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

Button Layout picks how the bar stands. Groups (the default): one row of six group buttons
as wide as the map (Travel: flight master, innkeeper; Trade: auction house, bank, mailbox;
Repair; Trainers: class and profession trainer; Looks: barber, transmogrifier; Errands:
Restock, Mail, Repair Gear and Trainer, each with its reminder's line, gold while it is up, or
the nearest place's distance, a click going where that reminder sends you). Hover a group
for each of its services with the distance to the nearest one; click it for a small list
beside the minimap column, toward the middle of the screen, with the same distances, and
click a service there to route to it (the profession trainer asks which profession first).
Repair has no list: a click routes at once. Escape, a click elsewhere or the same group
again closes the list, another group switches it; right-click a group to stop the route. A
group is grey only while none of its services is known on your continent. Merged into the
square minimap's frame, the row sits under the divider rail with its gem caps and the
"Services" name (centred; at the rail's left end while Route's distance line stands at its
right end) and the clock moves beside the zone name. All Buttons: the two rows of an icon per
service, as before. The minimap button keeps to the map's edge at any size, round, square or
cropped to the Minimap Kit's Width and Height. On a map where you can't be placed, a click says "Can't place you on this map, so no
route to the nearest ..." instead of claiming none is known on your continent; a character that
has not chosen a faction sees the services open to both. The service data also holds the
vendors and what they sell (food and drink, arrows and bullets, class reagents), which Restock
uses, and Zephras Isle's innkeeper, trainers, repairer and vendors. For modules:
`Services:ColumnRow()` answers whether the row of groups stands under the map and its height
(MinimapPanel's column asks it); `Services:GoTo(kind, opts)` routes to the nearest of a kind
(true, or false and why: "unknown", "off", "noplace", "none"), `Services:Nearest(kind, opts)`
gives its yards, name and sub-name, and `Services:Learn` remembers a place met in game (the
Reminders and Restock go through these).

### Reminders

One small round button beside your portrait for errands, each with its own switch on the page
(the module is on for players who update to 0.14.0; a fresh install starts with it off, as with
every module):

- **Restock** (Restock's rows sit under it, see below): something on your restock list is low.
- **New Mail:** mail is waiting. It goes once you open a mailbox and comes back only for mail
  that arrives after.
- **Repair Gear:** your most worn piece is down to **Remind At** (30 %); broken gear goes first.
- **Trainer:** **Class Spells** (you reached a level with new spells; it stays until you have
  learned them, and each visit to your class trainer tells MelloUI when the next ones come, kept
  per character; before the first visit it goes by the levels trainers teach at) and **Profession Ranks** (a profession can learn
  Journeyman, Expert or Artisan).

A new reminder comes up with a short line beside the button and goes after **Show For** (8 s,
4-20; held while the pointer is on it). **Stay Up In Rest Areas** (on, one switch for all four):
in an inn, a city or a town every reminder stays up until it is done (restocked, a mailbox opened, gear
repaired, your new spells or the profession's rank learned) or you leave. A town (0.16.0) is a
named subzone with an innkeeper or a flight master within 200 yards (the Services' own places, looked
at each time the subzone changes), so Sentinel Hill or Lakeshire count as a whole; switched on
there, the ones waiting come back at once; off, they come and go there too. Several at once
show as one button with a count, the most urgent on it
(broken gear, Restock, Repair Gear, New Mail, Trainer); the tooltip lists them all, and pointing at the
button softly slides the others out of it, each a button of its own (at once with Reduce
Motion). Left-click: the way to the nearest place for it, through the Services. Within about
40 yards of that NPC the glow brightens, the tooltip says "Click: target <name>" and a click
targets them (never a mailbox; set up out of combat only). Right-click: **Not now** (in an inn
or a city while Stay Up In Rest Areas is on, and always for Restock, it lasts until you next enter
a rest area, across a `/reload` too; otherwise only until it comes up again by itself: a new zone,
an inn, your next login).
**Glow:** a gentle gold pulse
for a few seconds, then steady (Pulse, then steady), always steady, or off. **Place:** left of,
above or right of the portrait; with the player frame hidden the button keeps a place of its
own, which you can drag in Edit Layout (a sample shows there). Nothing is checked before
the first moments after login or during a fight, and nothing runs while nothing changes.

For modules: `MelloUI.Reminders` (Core/Reminders.lua) is the one widget. `Rem:Register(spec)`
with a key, `check(key, why) -> active[, reach]`, an icon, `text`, `urgency`, the events that
matter (`when`), `onClick`, `persistent`, a Services `kind` for the reach and the target;
`Rem:Refresh(key[, raise])`, `Rem:Dismiss(key, untilWhat)`, `Rem:State(key)`, `Rem:Act(key)`;
the bus topic `reminder` (key, active, up). A spec with `column = true` is a row of the widget
column instead (0.16.0): `title` (and its colour), `model` / `portrait` / `icon` for the face,
`progress` (start, duration, pausedAt: the gold ring, a Cooldown swipe run by the engine) or
`fraction`, `time`, `count`, `sub`, `actions` (the hover buttons; `secure` for a macro run with
the player's own click), `tray` and `rightClick`, `combat = false` to fold while in combat,
`priority` ("now", "ongoing", "wait": the order and what folds first), `bottom` (Voice Over's slot)
and `compact` (only the face and ring in combat); `Rem:Tray(key[, open])`. Core/Reminders.lua's "The column" header has the whole contract.

### Widgets

The widget column (0.16.0): small live widgets in one column beside the screen's middle, each a
row with a face in the round kit rim, two lines on a soft band, a gold ring for its time and buttons
that slide out on hover. Right-click puts one away until something new happens.

Its order, bottom first: Voice Over (the bottom place: no other widget moves what is being read,
and a fight never stops it; **Compact In Combat**, on by default, shrinks it to the face and ring
while you fight), then the ones that need an answer now (loot rolls, summons, resurrect offers,
ready checks), then the ongoing ones, then the ones that can wait (whispers, the auction house,
profession cooldowns); within each, the older lower, so a new widget only moves the ones of a lower
priority. **Most Widgets Shown** (Reminders > Widgets, 4; 2 to 6) caps the rows: the rest fold into
a slim "+2 more" row on top with their small faces, and a click there lists them (a click acts, a
right-click puts one away). A "now" widget always shows. In a fight whispers, the auction house,
profession cooldowns, Feed Pet and crafting fold too and come back where they were after it, with
no sound.
Move and size the column in Edit Layout ("Widgets"), or, while the widgets are unlocked, drag any
widget; **Lock The Widgets** (Reminders > Widgets, and Voice Over's padlock) keeps it where it is.
`/mello widgets` lists what the column holds now (each widget, what shows, where) in the copy
window, for a report. Voice Over is one of its rows; the rest are
the **Widgets** module's (Modules/Widgets.lua), each with its switch on the Reminders page's
Widgets tab:

- **Loot Rolls:** the item in its quality colour, the ring the roll's time, Need / Greed / Pass
  (Need only when it can be needed); the count is the rolls waiting. While it is on, the game's
  own roll windows still open and close but draw nothing and take no clicks (hiding them from an
  addon would lay out the bottom of the screen as the addon's code: blocked in a fight); with the
  Gamepad UI they stay.
- **Threat** (0.16.0): only in a group fight and only when it matters. A damage dealer or healer
  close to pulling their target sees the mob's face, "86% of <the tank>'s threat" and "Ease off"
  (amber); once it is on them "It is attacking you" and "Aggro" (red); it stays until the threat
  falls under 70 % (no flicker at the edge). A tank sees "2 mobs not on you", the first one and who
  it is on, and your threat on it. The ring is your threat against the pull; point at it (or its
  list button) for the group's threat on your target, highest first, the tank marked. Where the game
  hides the numbers (a boss): "Close to pulling", no ring. A "now" widget: it never folds.
- **Corpse Run:** as a ghost, how far your body is and which way, the ring the corpse recovery
  delay; a click shows the way (Route).
- **Timed Quests:** the quest's name and first objective, the ring its whole time limit.
- **Summons / Resurrect Offers:** who and where, the time left, Accept / Decline. While on, the
  game's own popup still opens, times out and answers as the game has it, but is see-through and
  click-through (not hidden: hiding a game popup from an addon froze Escape in 0.15.0); it still
  takes a popup's place, so another popup shows below it. With the Gamepad UI it stays visible. At
  your body the Corpse Run widget has Resurrect, and the game's Resurrect popup is see-through too.
- **Ready Checks:** the leader's check and its time, Ready / Not Ready on it (a click on the face:
  Ready). While it is on, the game's ready check box no longer opens (it stops listening for
  READY_CHECK); with the Gamepad UI it stays. Your own check shows nothing.
- **Whispers:** the sender in their class colour, the last line (when it can be read), the unread
  count; Reply opens their whisper window (Chat's Whisper Popup Window on). While it is on, a
  whisper to a conversation whose window is not open shows only the widget; a window that is open
  takes the line and no widget comes up.
- **Hunter Pet:** a pet that is not happy, its face, the ring its happiness, Feed Pet (then click
  a food; out of combat).
- **Auction House:** outbid, sold, won and expired in one list (the tray), heard from the auction
  house's own notices (this client sends no system message for them); a click shows the way to the
  nearest mailbox, and opening one clears it. A sale while you were offline comes only as mail.
- **Crafting:** a batch, "Crafting 12 of 20", the ring each item's cast, Stop.
- **Profession Cooldowns:** a transmute, mooncloth or the salt shaker ready again (learned while
  the profession is open, kept per character).
- **Quest Items** (0.17.0): in a quest's objective area (the game's quest area on the map, or
  within 100 yards of the objective Route leads you to) while you carry that quest's item to use
  (the item the Quest Tracker's item button uses): the item, the open objective's line ("2/4 Oil
  drums filled"), the ring its progress, the count you carry and "Click to use". A click on its
  face uses the item: out of combat a secure button lies over the face while you point at it (a
  right click is still Not now). It folds away in a fight (the game allows that click only out of
  combat) and comes back after it. Checked when the quest log or the bags change, at a new
  subzone, when you stop, and as you travel (Route's place, asked for only while you carry a
  quest's item).
- **Healer Drinking** (0.17.0): when you tank a group (the TANK role, or a tanking form), between
  pulls: a healer of your group drinking, "Aldwyn is drinking / Wait for them before the next
  pull" (two: both names; more: how many, the names in the tooltip). A healer is the HEALER role,
  or, when nobody in the group has a role, a priest, druid, paladin or shaman. The game keeps
  party mana hidden from addons (measured), so it shows the Drink buff, not their mana; it goes
  when they stop drinking or a fight starts (auras are read only out of combat).

And three more reminders by the portrait: **Bags Almost Full** (at **Free Slots**, 2; a click shows
the way to the nearest vendor), **Talent Points** and **Well Fed Ending** (its last two minutes).
Bags Almost Full stays the whole time the bags are at or under Free Slots, in a fight too, until
you make room (a reminder's `fight`: in a fight only such ones stay drawn and are checked; the
secure target button is taken off before the lockdown as before).

The buff reminders (0.17.0), by the portrait too. Each stays up the whole time it is wanted,
anywhere and in fights too (the reminders' `persistent` and `fight`). A fight's auras are the
game's secrets (each read asks `C_Secrets.ShouldAurasBeSecret` first): a read that cannot see
them keeps the last state it knew, so a buff lost in a fight shows after it; the weapon's enchant
is no secret and is read in a fight too. A click puts it back on (the widget's secure part,
`secure`, laid out of combat over the button the pointer is on, the round one or one of the
others out on hover; in a fight the tooltip says the click cannot):
- **Weapon Poisons & Oils:** a poison, an oil, a sharpening stone or weightstone (or one of
  Forever's imbue scrolls, a warlock's stone) that ran out on a weapon, or has two minutes left,
  while you carry one that puts the same enchant back: "Main hand: Instant Poison ran out". The
  enchant is the one last seen on that hand; another weapon there forgets it. The items come
  from the client's own tables (`Tools/weapon_enchants.py`). A click: `/use item:<id>` then
  `/use 16` (or 17), the game's way of putting it on that weapon.
- **Your Buffs:** your own buffs missing on you, only the ones you know: Arcane Intellect and a
  mage's armor, Fortitude, Inner Fire and Divine Spirit, Mark of the Wild, a warlock's armor. A
  group version on you counts (Arcane Brilliance, Prayer of Fortitude, Gift of the Wild); the armor
  is named as the one you wore last. After a death the tooltip says so. A click casts it on you.
- **Your Buffs On The Group:** the others in your group missing a buff you can cast ("2 without
  your Power Word: Fortitude"; Arcane Intellect and Divine Spirit only on those who use mana), their
  names in the tooltip; the dead, offline and far away left out; not read in a fight. A click
  casts it on the first one missing it, then the next.
Each comes up when something goes missing and at the usual moments, and a right click (Not now)
lasts until everything is back on and something goes missing again.

### Restock

Keeps drink, food, ammunition and reagents in your bags (its rows are on the Reminders page).
Each character has its own list, which profiles never carry or wipe; a new one starts with
suggestions for its class: drink for the classes that use mana, food for everyone, 1000 arrows
for a hunter (bullets with a gun), all from level 5, and class reagents at the levels they are used. Older,
lower-level stock counts toward a line. **Remind Below** (50 %): a line that drops below that
share of its amount brings up the reminder, and a click routes you to the nearest vendor that
sells it (shops you have opened are remembered; the innkeeper for drink and food when none is
known). In an inn or a city the reminder stays until you restock or leave (the Reminders page's
**Stay Up In Rest Areas**, every reminder's). **Shopping List At The Shop** (on): at a merchant who sells what you are low
on, a small list beside the shop window shows each item, "+20 (have 3)", the price, the total
and the gold left, with **Buy**, **Not now** and **Edit list**. It picks the best item you can
use from the merchant's own list, in whole purchases, limited by the stock, your bag space
(quiver and ammo pouch first) and your gold. Nothing is bought without the Buy click; the
purchases go one at a time and stop when the shop closes or the game refuses one, and Vendor's
Report In Chat says what was bought. **Restock List** (Edit, or `/restock`): a window with a
slider per line and Remove, Add a line, Suggested (click twice) to go back to the class
suggestions, and it takes items dropped from your bags or from a shop. Counting runs just after
your bags change, never in combat.

### Gains

Short lines beside your character (right of the screen's centre, a little below) show what you just gained, each on the on-screen notice's soft dark shade, without an outline unless the notice's **Outlined Text** is on. It is on by default (the installer's Fresh start begins with every feature off):

- **Skill Ups:** "+1 Defense 57 / 80" when a skill goes up: weapon skills, Defense, professions, secondary skills and languages (the lines the Skills tab lists, a folded heading's too). A newly learned skill is no "+1", and a new rank from a trainer (or a riding rank) only changes the numbers a line shows. **Show Skill Values** (on): the value and the cap after the name.
- **Looted & Received Items:** "+3 Linen Cloth" for each item that comes into your bags: loot, quest rewards, crafted items, mail and trades. The small gem before the name is the item's quality colour, the same gem as in the bags and the tooltips. Moving items between your bags, the bank and your gear never counts. When one loot brings more than five items, the best of them are shown.
- **Bought Items:** the same line with a quiet "bought" after it, for what you buy from a merchant, buybacks too. A sale makes no line for the item (its money is a Money line).
- **Junk Items** (on): grey items too.
- **Money** (on): "+" and the game's own coins when your money goes up: loot, quest rewards, sales, mail and trades. Several gains in a row add up on one line; spending makes no line.
- **Currencies** (on): "+15" with the currency's own icon and name for honor, tokens and other currencies.
- **Item Names In Quality Colour** (off): item names in their quality colour beside the gem; blue and purple read less well over bright ground.

The count is in gold and the name in the palette's text colour; the value and "bought" are smaller and a little fainter. A very long name ends in "...". The newest line is on top and at most five show; gaining the same skill or item again while its line shows adds to it ("+2 Defense") and brings it back to the top. Each line fades after **Show For** (5 s, 2-15), so the oldest go first; with Reduce Motion the lines do not slide, they only fade. Edit Layout shows three sample lines to drag the feed; its Reset puts it back, and profiles carry the place. Nothing is read in the first moments after login; a skill point or item the game keeps hidden during a fight shows as soon as the fight is over.

### Combat Text

The text that floats over your character in a fight (the damage you take, your heals, Dodge and Parry, procs, the resources you gain) can be drawn by MelloUI, each line on the on-screen notice's soft dark shade instead of a thick outline (**Outlined Text** outlines it too). **Combat Text Style** (Screen Text, Combat Text tab) picks who draws it:

- **Game (Blizzard)** (the default): the game's own text, exactly as before; MelloUI does nothing at all.
- **Lanes:** round your character. Damage taken falls on your left, healing rises on your right, procs, auras, Dodge and Parry and the start and end of a fight sit above your head, and the resources you gain show small under your feet.
- **Feed:** one column over your portrait, the newest on top, each line with a small mark for its kind (a point for a hit, a plus for a heal, a star for a proc, a ring for a miss, a drop for a resource) and the healer's name.
- **Classic:** one stream over your head, like the game's, in MelloUI's font and shade.

**Preview** plays a few made-up lines in the chosen style (also `/mello combattext test`). Damage taken is red, healing green, resources blue, procs in the palette's gold; crits are a third bigger. **Shade Size** (how big the soft shade behind every line is, the text over you and Your Damage alike: 100% as the notices', less hugs the numbers closer, 0% none), **Text Around You** (the size of these styles' text), **Notices In Title Font** (procs and auras in the title font, as the window titles), **Lane Spread** (how far left and right the Lanes run) and **Most Lines** (per lane, in the stream or in the feed) shape it (each dimmed on Game, where the game draws the text: its size is then **Game Text Around You**); each kind has its switch (Damage Taken, Healing, Procs & Auras, Dodge, Parry & Block, Resources Gained, Entering & Leaving Combat, Reputation & Honor). Each style moves and sizes in Edit Layout, which shows sample lines to drag. While a MelloUI style is on, the game's own text is kept quiet (its switch in the game's options stays on, as the text needs it); back on Game it is as it was. In a fight the game hides the amounts from addons: MelloUI shows them as the game gives them, with no totals of its own.

**Your Damage** draws the numbers of the damage you deal in MelloUI's look as well, at each enemy's nameplate: **Rise** (straight up, as the game's), **Fan** (up, left and right in turn) or **Stack** (a short column beside the enemy, the newest on top). Crits are gold and bigger, spells violet, a glancing blow smaller, and a dodge or parry shows as a word. It keeps the feel of the game's numbers: as big as they are (**Numbers Over Enemies** sizes it, as it sizes the game's; Text Around You does not), starting on the enemy and shooting up, about a second and a half each, and the killing blow finishes rising after the enemy's nameplate is gone. Only your own and your pet's hits show: a hit is drawn on an enemy you or your pet are fighting (on its threat list), never another player's first hit on a fresh mob. The game only tells an addon that an enemy was hit, not by whom, so in a group, or where the game keeps threat hidden, the game's own numbers show (they know whose hit it is), and MelloUI's come back when you play solo again. One case it cannot tell apart: alone, a passer-by hitting the same mob you fight. The game's own damage numbers are switched off meanwhile and come back as they were on **Game** (the default). MelloUI draws at the enemies' nameplates, so with enemy nameplates off (the V key) the game's own numbers show until you turn them on again. Preview shows it at your target's nameplate. `/mello combattext order` prints, for 15 seconds, the order in which a hit and the threat update arrive (a check for the hits held a moment for it).

On **Game**, the numbers over the enemies are drawn by the game: their font is **Game Numbers Font** on the same tab and their size **Numbers Over Enemies**. Your Damage's numbers take the Game Numbers Font too (at once, no /reload), so every number over the enemies is one font. One size per thing on the screen: Text Around You (MelloUI's styles), Game Text Around You (the Game style) and Numbers Over Enemies (the game's numbers or Your Damage, whichever draws them); the search finds them by their old names too. The tab also has the game's own switches for them: **Damage Over Enemies**, **DoT Ticks Over Enemies**, **Pet Damage Over Enemies** and **Healing Over Friends**. They show the game's setting as it is and change it only when you do; one this client does not have is dimmed ("Not in this client"), and the damage ones are dimmed while Your Damage draws the numbers.

### Damage Meter

MelloUI's damage meter **in place of the game's** (Bars & Meters, Damage Meter). Its switch,
**Use MelloUI's Damage Meter (replaces the game's)**, is on by default: while it is on the game's
own meter windows never show (MelloUI switches off the game's "Enable Damage Meter" setting out
of combat and puts your own value back when you switch MelloUI's meter off). The numbers are the
game's own: a pet's damage counts for its owner, and in a fight the game hides the amounts from
addons, so MelloUI shows them as the game gives them.

- **Your Values** and **Party Values**: three numbers by every frame. The sword is this fight's
  damage per second (gold), the hourglass this run's (in a fight: as of the last fight), the cross
  your healing per second (green); a zero is a dim dash. Yours sit on top of your frame, over
  its name plate; move them in Edit Layout (Your Values; Reset puts them back on the frame).
  They show, hide and fade with your frame. The party's sit on top of each party frame. To make
  room there, Party Values
  switches on the game's own Show Party Pets (the frames stand a little further apart, party pets
  show under them); your own setting comes back when it is off. In a fight a party member's
  number is live while no one else in the group has their class, else it fills in when the fight
  ends.
- **On Raid-Style Frames** (0.17.1): on every raid-style party frame and every raid frame, one
  small number on the right, on the health %'s line: a damage dealer's DPS (gold, the sword), a
  healer's HPS (green, the cross; the group role decides, and without one the larger side of their
  last fight). No shade behind it, an outline instead, so forty boxes stay clean. In a fight it is
  live for you and for anyone whose class no one else in the group has (the game hides who the
  others are), and empty, never a dash, for the rest until the fight ends; after it, each player's
  number from the last fight, until the next one starts. Pointing at such a frame adds three lines
  to its tooltip: this fight, this run and healing. Never on pets' or arena frames.
- **Race Bar**: in a fight, one bar for the group, captioned "Current DPS" (or HPS). The top
  player is its right end with their value above it ("41 dps"), everyone else a class medallion
  under the bar at their share of the top, labelled 2nd, 3rd ...; you are the gold-ringed pin and
  the bar is filled up to you. Crowded pins keep the pin and drop the label (yours always shows);
  the pointer on it lists everyone. It fades in when a fight starts and out after it. With the
  painted look it wears the kit's bar frame (your Bar Border choice) and your Bar Texture. **Race
  Bar Shows** (Auto: healing for a healer, else damage), **Race Bar Pins** (2 to 10), **Race Bar
  Width** and **Race Bar Height**. Move it in Edit Layout; right-click it there for Width and Height too. In a
  fight the game keeps the numbers hidden from addons: they show as whole numbers then, with one
  decimal after the fight.
- **Fight Summary**: for a few seconds after a fight (longer while you point at it), a row in the widget column: won or lost and its
  length, your damage, DPS and rank, the gold ring your share of the group. The pointer shows the
  top five; a click opens that fight in the Fight History.
- **Fight History**: every fight of this session, newest first, grouped by run ("The Deadmines,
  run 1"); "This run" on top. A fight's Damage and Healing tabs list everyone with their class
  medallion, share line, per second and total; Your spells lists your top eight (a pet's under
  its own name). **Fights Kept** (10 to 200, 100) keeps that many; Clear asks first. The history
  stays over a /reload and starts empty at the next login. It opens from its button in the chat's
  button column (a small bar chart under the channels' "#") and from the summary.

A **run** starts when you enter a dungeon or raid (not on a corpse run back in), when your group
changes, or at your first fight in another place; out in the world it lasts from login. Run DPS is
the run's damage divided by its fight time. `/mello meter test` records a made-up fight to see the
summary and the History.

### Swing Timers

A shot bar and a melee bar in MelloUI's look **in place of the game's swing timers** (Frames
and bars, Swing Timers; 0.17.1). Off by default. While it is on, the game's own swing timers are
switched off (its "Show Swing Timer" setting, out of combat) and stay off: switched on in the game's
settings, they go off again (after a fight, if you are in one), so the two never show together. Your
own choice comes back when you switch MelloUI's off.

- **Shot Bar**: a bow, gun, crossbow or thrown weapon's Auto Shot, in two stages. First the
  reload: cream, it shrinks from both ends to the middle, and you can move. Then the aim, the
  last half second: red, it grows from the middle while you stand still ("Hold"). Moving holds
  the shot back: the red empties and waits ("Moving") and starts again when you stop. Full cream
  again at each shot; it fades out when Auto Shot stops.
- **Melee Bar**: each swing of your main hand, pale, shrinking to the middle; full again at the
  next swing. A wand's shots ("Shoot (wand)") count down on it too.
- **Off Hand Bar**: a thinner bar under it for your off-hand weapon, while you carry one.
- **Look**: Cast Bar (the cast bar's frame, the bar's name above it on the left and the seconds
  left on the right: **Label And Time**) or Hairline (a thin rim on a soft shade, nothing else).
  With the cast bars' painted look off, both are a plain bar.
- **Show**: In Combat (a bar shows in a fight once it swings or shoots, and fades out when the
  fight ends) or Always (each bar at rest while you carry a weapon for it).
- **Width** and **Height**; out of range a bar dims, as the game's does. Move them in Edit Layout
  (Shot Timer and Swing Timer, just above your cast bar at first); right-click them there for
  Width and Height too.

The bars are counted down by the game itself, not by MelloUI each frame, so they cost no frame
rate. `/mello swing log` prints 20 seconds of your swings and shots as the game reports them, to
copy from `/mellolog`.

### Minimap Panel

The minimap cluster in the kit (part of the reskin in UI Modifications): the iron ring
around the map with the zone name on a title plate standing on it, the tracking button in a
round rim, plus / minus zoom buttons. Edit Mode places the cluster; Edit Layout can move it too,
and while it has a place there, that place wins (its Reset gives it back to Edit Mode). `/mmdump` prints the rects.

**Width** and **Height** (98 to 400, 198 x 198 by default: the game's map at 100 %) size the
map. The round map is as tall as it is wide, and its painted ring grows and shrinks with it;
the square map can be up to twice as wide as tall or the other way round. The square map's
border, the zoom and tracking buttons and the zone name keep their size, and so do the Services
buttons under the map (spread across a wider map; smaller only on a map narrower than the
game's, where they would not fit). The game's map stays square underneath (its arrow and
terrain need a square), and a mask shows the Width x Height of it
(`Media\Textures\Masks\Minimap`, made by `Tools\make_minimap_masks.py`; the short side in
256ths of the long one, within a unit of the Height asked for), so a click on the hidden part
goes through to the world; the player's coordinates stay under the map's shown bottom. While
the Minimap Kit is on, Edit Mode's minimap Size stays at 100 %. A Size you had set yourself
before 0.15.0 became your Width and Height once, so the map kept its size on the screen; the
150 % (or 90 - 140 %) that MelloUI's own layout had set did not, so that map is back at its
normal size. The group finder's eye stays where Edit Mode puts it, on the map's edge at 198:
drag it in Edit Mode for another size. Edit Mode's box still fits round the map and still moves
it.

The square map in the Window frame carries the zone name's plate on its top rail, its caps on
the frame's top corners, the clock beside the calendar on it: merged with Services or not, and
with Services off (0.17.0; before, without the merge, the plate stood above the frame where the
game puts it). The game still lays the cluster round the plate's own place (Edit Mode puts it
back there before it lays the cluster), so Edit Mode's box and the day / night dial stay where
they were; the plate goes back onto the rail right after. A picture frame or no border: the
game's place.

What stands under the map follows it: the Services row of groups, and MelloUI's Quest Tracker
with "Match The Minimap's Width" (Quest Tracker), which also hangs right under the map and moves
with it. For modules: `MinimapPanel:MapFrame()` is the map's shown part (hang things from it,
not from `Minimap`, whose square can be bigger), `MinimapPanel:ColumnWidth()` gives the map's
width on the screen and the width the frames line up to (the square border's frame where it is
wider), `MinimapPanel:ColumnAnchor()` the frame and offset the tracker hangs from. MelloUI's own
Edit Mode layout (`/mello layout apply`, the installer) puts the minimap at 100 % and the game's
tracker (which MelloUI's hangs on) right under the column with its right edge on the frame's;
where the tracker or your buffs have less room than they want (a 5:4 screen such as 1280 x
1024), the fit lays the layout for the Minimap Kit's map a step smaller, 90 % (178 x 178 from
the default: the approved layout's own size), the installer sets that Width and Height, and
its report says so (`/mello layout apply` only asks you to set it).
Where your buff rows by the column would reach into the centre third, the layout is fitted for
fewer icons a row or smaller icons, and the installer's report says which to set in Buffs &
Debuffs (the fit changes them itself only for a caller that writes its `places.auras`:
`inputs.auras.fitRows`).

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
place and height from the game's tracker in Edit Mode, is moved in Edit Layout (a drag gives it a
place of its own; its Reset puts it back where the game or the minimap column lays it), and a grip in its bottom-left corner sizes it; Height, Width, Scale, Text Size and
Scroll Step are in its settings.

"Match The Minimap's Width" (on by default, needs the Minimap Kit) makes the tracker as wide on
the screen as the minimap above it: the round map, or the square map's frame, so the two line
up. Unless you moved the tracker yourself, it also hangs right under the map, 8 units below
everything the map's column paints, and moves with the map when you drag it. Change the
minimap's Width in the Minimap Kit and the tracker follows; the grip then sizes only its
height. Off, it takes its own Width.

"Nearest Quest First" (on by default, needs Route) puts the nearest quest on top, the one you
follow above it, and quests with no known place after them in watch order; a quest only moves
past another when its distance really changed, so the list does not twitch as you walk. The
arrow on the left of the tracker's title switches it too. "Distances" (on) shows how far each
quest is at the end of its title line ("240 yd", "1.2 km"): its open objectives, or the one who
takes it back once it is done; the quest you follow shows the way left along its route, as the
arrow does. "Turn-in Line" (on) makes a finished quest say who takes it and where ("Turn in:
Gryan Stoutmantle, Sentinel Hill"). An objective that needs an item in your bags first says
where to get it on a line of its own under it, in gold ("First: loot Samuel's Remains from
Samuel Fipps"; a count when more than one is needed), until the item is looted; the quest stays
the followed one while Route's own pin on the item's source holds the game's tracking. Inside an instance, with no position, or with Route off,
the tracker keeps the watch order without distances. It asks Route for positions only while it
is shown and its Quests section is open.

The tracker stands in front of the minimap column (MEDIUM strata over the column's LOW), so a
click on the minimap, which raises the whole cluster, never brings the map or the Services row
over it; the Services group lists still open above it. While it stands where the game or the
installer's fit put it, it hangs right under the column (Match The Minimap's Width, above), or,
with that off or the Minimap Kit off, keeps clear of it: it moves down under everything the
column paints (the square frame's bottom gems, and with the Minimap Kit off the game's own
frame round the map) when the minimap's size, the Services bar's Button Layout or merge, or the
UI scale changes. The installer records the place its fit wrote, so that place still counts as
the game's own (Revert takes the record back); a tracker you moved yourself, in Edit Mode or
in Edit Layout, stays where you put it. The keep-clear only ever moves it down.

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

With the reskin and the UI Shade on, each of your and the target's aura buttons casts a soft
shade inside the gap between icons: the thin rim's own shape, or a soft square round the icon in
the black-edge look (Shade: Buffs on Look > General). Nameplate auras get none.

### Error Messages

Hides the red error messages you choose from the middle of the screen (off by default), a kind
at a time: not enough resources, not ready yet, out of range, facing and target, busy or
moving. MelloUI takes the error event from the game's error frame while a kind is hidden and
hands every other message to the frame's own handler, so those show as always. The messages
it lets through get Centre Text Shade's soft shade (Tweaks) like any other.

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

Every option a release adds names that release: `new = "0.14.0"` on its schema entry, `RowOpts(sec, TABLE.new)` or `opts.new` for a hand-built row, or a `W.NewTag` / `W.ButtonTag` call that names a bare control (`docs/WINDOW-RULES.md`, section 6). A new page with nothing on it tagged puts `new` on its RegisterModule. The settings window tags an option New only while that version runs. `release.py` runs `python Tools/lint/check_new_tags.py --version <version>` before it commits or tags: it compares every option with the previous release tag (a key whose kind changed counts as new) and refuses the release when a new option lacks that version's tag, an older option is tagged with it, a new page has nothing tagged, or a file builds controls the check does not know. It stops without checking when a file or a module's OnInit fails in its world, then takes the older versions' tags out of the files (`--fix`; with `--dry-run` it only lists them); its removals go into the release commit.

The GitHub Action (`.github/workflows/release.yml`, BigWigs packager) zips the addon minus what
`.pkgmeta` ignores, uploads it to CurseForge (project id from `## X-Curse-Project-ID` in the
TOC, token from the `CF_API_KEY` repository secret) and attaches the same zip to the GitHub
release for the tag. A tag that already has a release is skipped, so a moved tag cannot upload
a duplicate; a repository ruleset also forbids moving or deleting `v*` tags. The voice pack is
not part of that: when the lines changed, build it (`python Tools\voice_v2_pack.py lines.json
lines_readables.json`), zip the `MelloUI_VoicePack` folder in two parts, each under GitHub's 2 GB
limit for a release file and both holding their files under `MelloUI_VoicePack\`
(`MelloUI_VoicePack_Part1.zip`, `MelloUI_VoicePack_Part2.zip`: unzipped into the same place they
make one folder), upload both to the release by hand, then update the direct links and the size
in the README, this guide and the CurseForge description.

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
(`Kit:Shadow`: the UI Shade's partners for every outline piece, as pieces, nine-slices of the
rails and the synthetic square, round and capsule shapes; the nameplates' Whole plate shade,
the World Marker's gem `deco/gem_large`). `Tools\make_soft_glow.py` builds
`Media\Textures\SoftGlowRound.tga`, the round soft glow laid round a round button
(`MelloUI.Shade:Glow`: the Reminder widget). `Tools\make_active_look.py` builds
`Media\Textures\ActiveLook.tga`, the active look laid round whatever is on, checked or
selected (`Kit:SetActive`: a gold ring with a halo and an inner glow, its two dark edge lines
in a cell of their own; square and round cells, cut into nine for tabs and rows, whose cut
stops at the ring's inner line: no glow over their text). All four are
white with a soft alpha, tinted in game with a palette colour (innerPanel for the shades and
the ring's lines, selectedTrim for the glows, added as light). `Tools\kit_palette.py` recolours the painted kit for each palette of `Tools\palettes.json`
(the same colours as Core.lua's `MelloUI.Palettes`) into its own `Media\Kit<Name>` folder;
`texture_pack.py ship` then packs it like the other looks.

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

What the module is, is said in the same call, never in a hand list (the header of
`Core/Core.lua` has every field): `icon` and `flavour` for its page header, `role` for what the
installer's setups do with it ("core", "look", "feature", "adds" or "replaces"), for a
feature folded under UI Modifications `tweak = { label, desc, order }` (its switch, `qol_<Name>`),
and for a window the reskin dresses `window = { label, desc, tab = "Windows" | "HUD", ... }`
(`docs/WINDOW-RULES.md`, section 6). Where its options show in the settings window is one line
each in `Core/ConfigLayout.lua`, `R(page, tab, section, "YourModule.someToggle")`: that file
holds the side list, the pages and every option's one place, so a new option is its schema
entry here and its line there (one with no line lands at the end of its module's page, under
Advanced, and the checks name it).

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
  come. Macro Backup (`Core\Backup.lua`) is off unless the player turns it on, and its copy is
  brought back only when the player asks (`/mello backup restore`), never by itself.
- Some maps have no continent above them (Zephras Isle, UiMap 2521, sits right under the world
  map): `C_Map` gives no continent for them, so Route's `ContinentOf` takes such a map as its own
  continent. A map kind or parent that reads secret gives no continent.
