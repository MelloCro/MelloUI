r"""
The update in one picture: docs/update-<version>.jpg, 1920 wide, composed
from screenshots and short captions in the style of docs/update-0.13.2.jpg
(dark stone ground, gold serif headings, a section per theme, a caption
under every picture). For the CurseForge page and the GitHub release.

    python Tools\make_presentation.py [pictures folder]

The pictures folder defaults to the user's News folder; SPEC below names
each file and its caption. Windows fonts (Constantia for the headings,
Calibri for the text).
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
PICS = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\mortu\Pictures\News"
OUT = os.path.join(ROOT, "docs", "update-0.13.4.jpg")
LOGO = os.path.join(ROOT, "Media", "Textures", "LogoIcon.tga")

W = 1920
MARGIN = 46
GAP = 24
BG = (31, 31, 33)
EDGE = (58, 52, 40)
GOLD = (222, 184, 92)
GOLD_DIM = (168, 140, 74)
TEXT = (222, 218, 208)
DIM = (150, 146, 138)
FRAME = (14, 12, 12)

FONTS = r"C:\Windows\Fonts"


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


F_TITLE = font("constanb.ttf", 66)
F_SUB = font("calibri.ttf", 30)
F_BULLET = font("calibri.ttf", 27)
F_HEAD = font("constanb.ttf", 40)
F_CAP = font("calibri.ttf", 26)
F_CAP2 = font("calibri.ttf", 22)
F_FOOT = font("calibri.ttf", 24)

VERSION = "0.13.4"
SUBTITLE = "The update in one picture.  World of Warcraft: Forever  -  github.com/MelloCro/MelloUI  -  CurseForge: MelloUI"
BULLETS = [
    "Your whole UI, repainted. One switch. Flip it off and it's the normal game again",
    "Grab any window and drop it wherever you want. Wheel to resize. It stays",
    "Every click, page and pouch has a new sound. 32 of them. Preview before you commit",
    "See at a glance who in your party is the healer",
    "Sick of surnames? Show first names only. Or last. Your call",
    "Fresh install? Nothing is on. A quick tour shows you the ropes",
]
FOOTER = "MelloUI  -  free on CurseForge and GitHub, voice pack (1.6 GB) on the GitHub releases page  -  turn on only what you want"

# Sections: a heading, then rows of cells. A cell is (file, caption, small
# caption[, scale]); a row's pictures share one height and fill the width; a
# list inside a row is a stacked column. Captions say what it DOES, plainly.
SPEC = [
    ("Your whole UI just got painted", [
        [("UIReskin.png", "Windows, bars, frames, minimap, tracker, chat, meter: everything gets the iron-and-stone look at once. One switch.",
          "Don't like it? Flip it off, the game looks like the game again, and every other feature keeps working.")],
    ]),
    ("Drag. Everything.", [
        [("ClickAndDragWindowsResizeMouseWheel.png", "Tick Unlock, then just grab a window and drop it where you want it. Scroll the wheel while holding it to make it bigger or smaller. It snaps to the middle if you get close.",
          "Reload, restart, log out for a week: it's still where you left it. Works on the minimap, the tracker, the chat and the meter too."),
         [("UnlockallWindowsCheckbox.png", "This is the whole setup. One tick. Works with the paint job off as well.", None, 2.0),
          ("ActionBarsReskin.png", "Your bars and your health bars get the same treatment, and your Edit Mode layout loads by itself when you turn the paint on.", None, 1.0),
          ("RemadeDialogueBox.png", "Quest givers still talk to you, now on a proper scroll. And it always reads the right quest.", None, 1.0)]],
    ]),
    ("Small things you'll use every day", [
        [("NameplateClassIcons.png", "Party Markers: your group's class icons float over their heads, green ring for the healer. No more asking who heals.", None),
         ("SingleNameNameplate.png", "Everyone has a surname now. Too much? Show first names only. Or last names. Frames, nameplates and your own head, one setting.", None),
         ("VoiceOverReadQuestFromQuestLog.png", "Forgot what a quest was about? Open the log, hit Read, and it's read to you.", None),
         ("NavigationTab.png", "Need a mailbox? Repair? An inn? Click it here and the arrow takes you to the nearest one.", None)],
    ]),
    ("Never get lost, never hear a boring click again", [
        [("NavigationRoutes.png", "The route follows real roads and follows YOU: cut a corner, take a shortcut, it just keeps going instead of nagging you to turn around.", None),
         ("CustomSounds.png", "Every sound in the interface is new: clicks, pages, pouches, buckles, coins, whispers, the dungeon pop, the level-up. Hit Play on any of them before you decide.",
          "Off by default. Turn on the families you like, leave the rest.")],
    ]),
]


def load(name):
    return Image.open(os.path.join(PICS, name)).convert("RGB")


def wrap(draw, text, f, width):
    words = text.split()
    lines, line = [], ""
    for word in words:
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=f) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def text_block(draw, x, y, text, f, colour, width, spacing=6):
    for line in wrap(draw, text, f, width):
        draw.text((x, y), line, font=f, fill=colour)
        y += f.size + spacing
    return y


def framed(canvas, im, x, y):
    """The picture with a thin dark frame and a soft shadow."""
    shadow = Image.new("RGBA", (im.width + 24, im.height + 24), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle([8, 10, im.width + 16, im.height + 18], fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(6))
    canvas.paste(shadow, (x - 12, y - 12), shadow)
    canvas.paste(im, (x, y))
    ImageDraw.Draw(canvas).rectangle([x - 1, y - 1, x + im.width, y + im.height], outline=FRAME, width=2)


def cell_height(draw, cell, width):
    """The height of a cell's caption block."""
    _, cap, small = cell[0], cell[1], cell[2]
    h = 12
    h += len(wrap(draw, cap, F_CAP, width)) * (F_CAP.size + 6)
    if small:
        h += len(wrap(draw, small, F_CAP2, width)) * (F_CAP2.size + 5) + 2
    return h


def lay_row(canvas, draw, y, row, left, width):
    """A row of cells (a cell may be a column of cells): pictures at one
    height, filling the width; returns the bottom."""
    # a column: laid out on its own width share, top-aligned
    cols = [c if isinstance(c, list) else [c] for c in row]
    # each column's natural aspect: pictures stacked (a column) at a common width
    def col_aspect(col):
        # width / height of the column's pictures stacked at width 1
        total = 0
        for c in col:
            im = load(c[0])
            scale = c[3] if len(c) > 3 and c[3] else 1
            total += im.height / (im.width) / scale if scale != 1 else im.height / im.width
        return total
    if all(len(c) == 1 for c in cols):
        # one picture per column: a common height
        aspects = [load(c[0][0]).width / load(c[0][0]).height for c in cols]
        avail = width - GAP * (len(cols) - 1)
        h = avail / sum(aspects)
        widths = [a * h for a in aspects]
        x = left
        bottom = y
        for col, w in zip(cols, widths):
            c = col[0]
            im = load(c[0]).resize((int(round(w)), int(round(h))), Image.LANCZOS)
            framed(canvas, im, int(x), y)
            cy = y + im.height + 14
            cy = text_block(draw, int(x), cy, c[1], F_CAP, TEXT, int(w))
            if c[2]:
                cy = text_block(draw, int(x), cy + 2, c[2], F_CAP2, DIM, int(w), 5)
            bottom = max(bottom, cy)
            x += w + GAP
        return bottom + 10
    # mixed: the first column a single picture, the second a stack; widths
    # split so the stack's pictures fit beside it at the picture's height
    avail = width - GAP * (len(cols) - 1)
    shares = []
    for col in cols:
        if len(col) == 1:
            im = load(col[0][0])
            shares.append(im.width / im.height)
        else:
            shares.append(1.0)
    # the single pictures at a height h, the stacks take the rest
    single_w = avail * 0.5
    x = left
    bottom = y
    for col in cols:
        w = single_w if len(col) == 1 else avail - single_w
        if len(col) == 1:
            c = col[0]
            im = load(c[0])
            h = w * im.height / im.width
            im = im.resize((int(round(w)), int(round(h))), Image.LANCZOS)
            framed(canvas, im, int(x), y)
            cy = y + im.height + 14
            cy = text_block(draw, int(x), cy, c[1], F_CAP, TEXT, int(w))
            if c[2]:
                cy = text_block(draw, int(x), cy + 2, c[2], F_CAP2, DIM, int(w), 5)
            bottom = max(bottom, cy)
        else:
            cy = y
            for c in col:
                im = load(c[0])
                scale = c[3] if len(c) > 3 and c[3] and c[3] != 1 else None
                if scale:
                    pw, ph = int(im.width * scale), int(im.height * scale)
                    pw = min(pw, int(w))
                    ph = int(pw * im.height / im.width)
                else:
                    pw, ph = int(w), int(w * im.height / im.width)
                im = im.resize((pw, ph), Image.LANCZOS)
                if scale:
                    # a small control: the picture on the left, the caption beside it
                    framed(canvas, im, int(x), cy)
                    ty = text_block(draw, int(x) + pw + 20, cy + 4, c[1], F_CAP, TEXT, int(w) - pw - 20)
                    cy = max(cy + ph, ty) + 26
                else:
                    framed(canvas, im, int(x), cy)
                    cy = cy + ph + 14
                    cy = text_block(draw, int(x), cy, c[1], F_CAP, TEXT, int(w))
                    if c[2]:
                        cy = text_block(draw, int(x), cy + 2, c[2], F_CAP2, DIM, int(w), 5)
                    cy += 22
            bottom = max(bottom, cy)
        x += w + GAP
    return bottom + 10


def main():
    # a tall canvas, cropped to the content at the end
    canvas = Image.new("RGB", (W, 6000), BG)
    draw = ImageDraw.Draw(canvas)
    left = MARGIN
    width = W - 2 * MARGIN

    # header: logo, title, subtitle, bullets in two columns
    logo = Image.open(LOGO).convert("RGBA").resize((136, 136), Image.LANCZOS)
    canvas.paste(logo, (left + 6, 42), logo)
    draw.text((left + 176, 44), "MelloUI  " + VERSION, font=F_TITLE, fill=GOLD)
    draw.text((left + 178, 122), SUBTITLE, font=F_SUB, fill=DIM)
    by = 166
    colw = (width - 176) // 2
    f_bullet = F_BULLET
    while any(draw.textlength(b, font=f_bullet) > colw - 40 for b in BULLETS) and f_bullet.size > 20:
        f_bullet = font("calibri.ttf", f_bullet.size - 1)
    for i, bullet in enumerate(BULLETS):
        bx = left + 176 + (i % 2) * colw
        yy = by + (i // 2) * 36
        draw.polygon([(bx, yy + 12), (bx + 6, yy + 6), (bx + 12, yy + 12), (bx + 6, yy + 18)], fill=GOLD)
        draw.text((bx + 22, yy), bullet, font=f_bullet, fill=TEXT)
    y = by + 3 * 36 + 30

    for heading, rows in SPEC:
        draw.text((left, y), heading, font=F_HEAD, fill=GOLD)
        hw = draw.textlength(heading, font=F_HEAD)
        ly = y + F_HEAD.size // 2 + 6
        draw.line([(left + hw + 18, ly), (left + width - 18, ly)], fill=GOLD_DIM, width=2)
        draw.polygon([(left + width - 18, ly), (left + width - 12, ly - 5), (left + width - 6, ly), (left + width - 12, ly + 5)], fill=GOLD_DIM)
        y += F_HEAD.size + 22
        for row in rows:
            y = lay_row(canvas, draw, y, row, left, width)
        y += 26

    # footer
    draw.line([(left, y), (left + width, y)], fill=EDGE, width=1)
    y += 16
    draw.text((left, y), FOOTER, font=F_FOOT, fill=DIM)
    y += F_FOOT.size + 30

    canvas = canvas.crop((0, 0, W, y))
    # the page edge
    d = ImageDraw.Draw(canvas)
    d.rectangle([6, 6, W - 7, y - 7], outline=EDGE, width=2)
    d.rectangle([12, 12, W - 13, y - 13], outline=(44, 40, 34), width=1)
    canvas.save(OUT, quality=90, subsampling=0)
    print("%s  %dx%d" % (OUT, W, y))


if __name__ == "__main__":
    main()
