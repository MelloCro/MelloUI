# Your own sounds in MelloUI

Every sound MelloUI plays is yours to change: the clicks, the bags, whispers, the ready check, Level Up, Rare Alert
and the rest. You can pick another of MelloUI's sounds, the game's own, none at all, any sound from a SharedMedia
pack, or your own files. This guide shows you how to add your own, step by step. It takes about five minutes.

**What you need**

- Your sounds as **.ogg** or **.mp3** files. The game can't play .wav files; converting one takes a minute (see
  [Turning a sound into .ogg](#turning-a-sound-into-ogg)).
- The **MelloUI_MySounds** folder: **MelloUI_MySounds.zip** on
  [MelloUI's Releases page](https://github.com/MelloCro/MelloUI/releases/latest). It's free, and you download it
  once.
- A plain text editor. Notepad is fine.

## Step by step

### 1. Find your AddOns folder

It's the folder that holds your `MelloUI` folder. For World of Warcraft: Forever it is usually:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns
```

Installed WoW somewhere else? Look for `_forever_\Interface\AddOns` inside your World of Warcraft folder.

### 2. Put the MelloUI_MySounds folder there

Unzip **MelloUI_MySounds.zip** into the AddOns folder. You should end up with this:

```
Interface\AddOns\
  MelloUI\
  MelloUI_MySounds\
    MelloUI_MySounds.toc
    MySounds.lua      <- you edit this one
    Sounds\           <- your sound files go here
    Libs\
```

Watch out for a folder inside a folder (`MelloUI_MySounds\MelloUI_MySounds\`). If you see that, move the inner one
up a level.

### 3. Copy your sounds into the Sounds folder

Put your .ogg or .mp3 files into `MelloUI_MySounds\Sounds\`.

Give them simple names: letters, numbers, `-` and `_` only, with no spaces or accents. For example `air_horn.ogg` or
`gong-2.mp3`.

### 4. List them in MySounds.lua

Right-click `MySounds.lua` → **Open with** → **Notepad**. At the bottom, add one line for each sound:

```lua
Sound("Air Horn", "air_horn.ogg")
Sound("My Gong", "gong-2.mp3")
```

The first name is what you'll see in MelloUI's sound lists: any words you like. The second is the file name exactly
as it is in the Sounds folder, ending included. Keep the quotes, the comma and the brackets, then save the file.

### 5. Restart the game completely

Exit World of Warcraft fully and start it again. A `/reload` is not enough: the game only finds new files when it
starts.

At the character screen, open **AddOns** and check that **MelloUI My Sounds** is ticked.

### 6. Pick your sound in MelloUI

Type `/mello`, open **Custom Sounds** (tick **Enabled** at the top right if it's off) and go to the **Your Sounds**
tab. Every sound MelloUI plays is listed there, from clicks and bags to Level Up and Rare Alert.

Open the list next to the sound you want to change: your sounds are under **From SharedMedia**. Press the **Play**
button (▶) to hear your pick.

## Adding more later

Copy the new file into `Sounds\`, add its line to `MySounds.lua`, and restart the game fully. MelloUI updates never
touch the `MelloUI_MySounds` folder, so your sounds stay. Moving to another PC? Copy the whole folder across.

## Turning a sound into .ogg

The free program **Audacity** does it:

1. **File** → **Open**, and choose your sound.
2. **File** → **Export Audio** (older versions: **Export as OGG**), and choose **Ogg Vorbis**.
3. Save it straight into `MelloUI_MySounds\Sounds\`.

Alerts work best short, one to three seconds. Too loud or too quiet? In Audacity, select the whole sound and use
**Effect** → **Normalize** before you export.

## Already have SharedMedia sounds?

If you use **SharedMedia** or a sound pack (many come with BigWigs, DBM or WeakAuras packs), their sounds are
already in MelloUI's lists. There's nothing to do. It works the other way too: the sounds you add with
MelloUI_MySounds also show up in other addons that use SharedMedia.

## Something not working?

**My sound isn't in the list.** Did you restart the game completely, not just `/reload`? Is **MelloUI My Sounds**
ticked in the AddOns list? After you log in, MelloUI My Sounds names in your chat any file it couldn't find. Check
your line in `MySounds.lua`: both names in quotes, a comma between them, and the closing bracket. One typo stops the
whole file, so check every line.

**It's in the list but makes no sound.** A .wav file renamed to .ogg won't play: convert it as shown above. Check the
file plays on your PC, and that the game's sound is on (Custom Sounds plays on the Sound Channel set on its Sounds
tab).

**I see "MelloUI_MySounds\MelloUI_MySounds".** The zip was unpacked one level too deep. Move the inner folder into
AddOns and delete the empty outer one.

Still stuck? Ask in MelloUI's Discord, with a screenshot of your Sounds folder and your `MySounds.lua`.
