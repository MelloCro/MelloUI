"""Text rules of MelloUI_VoicePack: canonical text, greeting hash, spoken text.

A port of the normative reference (ref_vtext.py, written with the v2 format spec). It must give the same
results on the spec's test vectors (hash, keyText, runtime, spoken); the Lua twin lives in
Modules/VoiceOver.lua. Standard library only.

    source_clean(text)            decode a source text (HTML entities, Wowhead tokens, $B, CR/LF)
    sex_variants(text)            ["m", "f"] when the text has a $G token, else [None]
    key_text(text, sex)           the canonical normalised string of a SOURCE text (build side)
    runtime_key_forms(shown, who) the forms the runtime computes from the text the game SHOWS
    hash8(s)                      8 hex digits, the greeting key hash
    greeting_key(npc, s)          "g-<npc>-<hash8>"  (npc 0 = an object)
    spoken(text, sex)             -> (segments, flags): [("speaker"|"narrator", text), ...] and review flags

Helpers for the exporter: words(), canon_title(), override_key(), has_letters(), final_problems().
"""
import hashlib
import html
import re

# ---------------------------------------------------------------- source decoding
WH_TOKENS = [(re.compile(r"<\s*name\s*>", re.I), "$N"), (re.compile(r"<\s*class\s*>", re.I), "$C"),
             (re.compile(r"<\s*race\s*>", re.I), "$R")]
WH_GENDER = re.compile(r"<\s*([A-Za-z']+)\s*/\s*([A-Za-z']+)\s*>")     # <guy/girl>, <Lord/Lady>
G_RE = re.compile(r"\$[gG]\s*([^:;]*):([^;]*);")                       # $Gmale:female;  (colon form, spaces allowed)
B_RE = re.compile(r"\$[bB]")
TOKEN_RE = re.compile(r"\$[nNcCrR]|\$\d+o[a-z]?")                   # name/class/race, objective amount
WORLD_STATE_RE = re.compile(r"\$\d+[wW]")                                # live world-state counter ($2063w)
OBJ_AMOUNT_RE = re.compile(r"\$\d+o[a-z]?")                              # objective amount ($2oa)


def source_clean(text):
    """Decode one source text. SQL escapes must already be decoded by the dump reader (\\n -> newline)."""
    if text is None:
        return ""
    t = html.unescape(text)
    t = t.replace("\r\n", "\n").replace("\r", "\n")
    for rx, tok in WH_TOKENS:
        t = rx.sub(tok, t)
    t = WH_GENDER.sub(lambda m: "$G%s:%s;" % (m.group(1), m.group(2)), t)
    t = B_RE.sub("\n", t)
    return t.strip()


def sex_variants(text):
    return ["m", "f"] if G_RE.search(text) else [None]


def resolve_g(text, sex):
    if sex is None:
        return text
    return G_RE.sub(lambda m: (m.group(1) if sex == "m" else m.group(2)).strip(), text)


# ---------------------------------------------------------------- canonical normalisation + hash
def _canon(t):
    t = t.lower()                                   # ASCII only matters: non a-z0-9 becomes a space below
    t = re.sub(r"[^a-z0-9]", " ", t)
    return re.sub(r" +", " ", t).strip()


UI_ESC = [(re.compile(r"\|c[0-9a-fA-F]{8}"), ""), (re.compile(r"\|r"), ""), (re.compile(r"\|T.*?\|t"), ""),
          (re.compile(r"\|A.*?\|a"), ""), (re.compile(r"\|H.*?\|h(.*?)\|h"), r"\1"), (re.compile(r"\|n"), " ")]


def key_text(text, sex=None):
    """Build side: source text (after source_clean) -> canonical string."""
    t = resolve_g(text, sex)
    t = TOKEN_RE.sub(" ", t)                        # player name / class / race are not part of the key
    for rx, rep in UI_ESC:                          # the runtime strips UI escapes, so the build side does too
        t = rx.sub(rep, t)
    return _canon(t)


def runtime_key_text(shown, player):
    """Runtime side: the text the game shows (name/class/race filled in, $G resolved) -> canonical string.
    player = {"name": ..., "class": ..., "race": ...} (plain strings; missing ones are skipped)."""
    t = shown
    for rx, rep in UI_ESC:
        t = rx.sub(rep, t)
    t = _canon(t)
    for k in ("name", "class", "race"):
        w = _canon(player.get(k) or "")
        if w:
            t = re.sub(r"(?<![a-z0-9])" + re.escape(w) + r"(?![a-z0-9])", " ", t)
    return re.sub(r" +", " ", t).strip()


def runtime_key_forms(shown, player):
    """The canonical forms the runtime tries, in order: A = name, class and race removed; B = name only
    (for texts that spell a class or race out literally, e.g. "an undead infestation" read by an undead)."""
    a = runtime_key_text(shown, player)
    b = runtime_key_text(shown, {"name": player.get("name")})
    return [a] if a == b else [a, b]


def hash8(s):
    h = 0
    for b in s.encode("ascii", "replace"):
        h = (h * 31 + b) % 4294967296
    return "%04x%04x" % (h // 65536, h % 65536)


def greeting_key(npc, canon):
    return "g-%d-%s" % (npc or 0, hash8(canon))


def jaccard(a, b):
    A, B = set(a.split()), set(b.split())
    if not A and not B:
        return 0.0
    return len(A & B) / len(A | B)


# ---------------------------------------------------------------- spoken text
DIRECTION_RE = re.compile(r"<([^<>]*)(?:>|$)|::([^:]+)::")        # an unclosed "<" runs to the end
PREPOSITIONS = {"to", "for", "of", "with", "from", "by", "about", "like", "than", "upon", "on", "at", "toward",
                "towards", "before", "behind", "beside", "unto", "into", "onto", "among", "against", "without"}
VOCATIVE_PRE = {"young", "brave", "dear", "good", "noble", "mighty", "my", "little", "fellow", "honored",
                "honoured", "great", "old", "kind", "sweet", "valiant", "wise", "doctor", "master", "commander",
                "lord", "lady", "sir", "madam", "junior", "surveyor", "champion", "hero", "citizen", "strong"}
MODIFIED_NOUNS = {"trainer", "trainers", "acquaintance", "buddy", "chatterbox", "front", "mage", "friend",
                  "friends", "brethren", "kind", "people", "lands", "blood", "brother", "sister", "hero"}
MIN_DIRECTION_WORDS = 3
_TOK = r"\$[NnCcRr]"
_ANY_TOK = re.compile(r"(%s(?:\s+%s)*)('s|s(?![A-Za-z])|[A-Za-z]+)?" % (_TOK, _TOK))
DETERMINERS = {"a", "an", "the", "this", "that", "any", "every", "each", "some", "another"}


def _drop_tokens(t, flags):
    """Remove the player's name / class / race from spoken text (SPEC.md 3.4, rules A-D)."""
    while True:
        m = _ANY_TOK.search(t)
        if not m:
            break
        head, after, suffix = t[:m.start()], t[m.end():], (m.group(2) or "")
        prev_m = re.search(r"([A-Za-z']+)(\s*)$", head)          # a word DIRECTLY before (only spaces between)
        prev_word = prev_m.group(1).lower() if prev_m else ""
        next_m = re.match(r"\s*([A-Za-z][A-Za-z']*)", after)       # a word directly after (not punctuation)
        next_word = next_m.group(1).lower() if next_m else ""
        rep = ""
        if suffix == "'s":                                           # A. possessive
            rep = "an adventurer's" if prev_word in DETERMINERS else "your"
            if prev_word in DETERMINERS:
                head = head[:prev_m.start()]
            flags.add("placeholder-possessive")
        elif suffix and suffix != "s":                               # glued word ("$Nath"): dropped whole
            flags.add("placeholder-glued")
        elif prev_m and prev_word in PREPOSITIONS and next_word not in MODIFIED_NOUNS:
            rep = "adventurers" if suffix == "s" else "you"          # B. object of a preposition
            flags.add("placeholder-object")                          #    ("for $N." / "for $N in the Hunt")
        elif prev_m and prev_word in DETERMINERS and next_word not in MODIFIED_NOUNS:
            rep = "adventurers" if suffix == "s" else "adventurer"   # "teach the $C." / "another $R has"
            flags.add("placeholder-in-phrase")
        elif not next_m:                                             # C. vocative: dropped
            chain = re.search(r"((?:[A-Za-z']+\s+)+)$", head)
            if chain:
                words_ = chain.group(1).split()
                n = 0
                for w in reversed(words_):
                    if w.lower() in VOCATIVE_PRE:
                        n += 1
                    else:
                        break
                if n:
                    cut = head
                    for _ in range(n):
                        cut = re.sub(r"[A-Za-z']+\s+$", "", cut)
                    if cut.strip() == "" or re.search(r"[,.;:!?(\-]\s*$", cut):
                        head = cut                                   # ", young $N." -> drop the chain too
            if prev_m and not re.search(r"[,.;:!?(\-]\s*$", head) and head.strip():
                flags.add("placeholder-bare-vocative")               # "Well done $N!", "Me crush tiny $R!"
        else:                                                        # D. in the middle of a phrase
            if next_word in MODIFIED_NOUNS:
                pass                                                 # "a $C trainer" -> "a trainer"
            elif prev_m and prev_word not in {"and", "or", "but"}:
                rep = "adventurers" if suffix == "s" else "adventurer"
            flags.add("placeholder-in-phrase")
        if rep == "" and (head.strip() == "" or re.search(r"[.!?]\s*$", head)):
            after = re.sub(r"^[\s,;:]*([a-z])", lambda mm: " " + mm.group(1).upper(), after, count=1)
        t = head + rep + after
    return re.sub(r"\b([Aa]) (adventurer)", r"\1n \2", t)


PH_RE = re.compile(r"\[PH\]\s*")                                     # Blizzard's "[PH]" unfinished-text mark
ELLIPSES_RE = re.compile(r"(\.\.\.|…)(?:\s*(?:\.\.\.|…))+")              # "it... ...I'm" -> "it... I'm"
LEAD_ELLIPSIS_RE = re.compile(r"([.!?…])\s+(?:\.\.\.|…)+\s*(\w)")         # "back. ...So easy" -> "back. So easy"


def _tidy(t):
    t = re.sub(r"[ \t]+", " ", t)
    t = ELLIPSES_RE.sub(r"\1 ", t)
    t = LEAD_ELLIPSIS_RE.sub(lambda m: m.group(1) + " " + m.group(2).upper(), t)
    t = re.sub(r" +([,.;:!?])", r"\1", t)
    for _ in range(3):
        t = re.sub(r",\s*,", ",", t)
        t = re.sub(r",\s*([.;:!?])", r"\1", t)
        t = re.sub(r"([.;:!?])\s*,", r"\1", t)
    t = re.sub(r"^[\s,;:.!?/\-–—]+", "", t)                   # also what "$N! ..." / "$C - ..." leave at the start
    t = re.sub(r"([.!?])\s+[,;:]+\s*", r"\1 ", t)
    t = re.sub(r" +", " ", t).strip()
    return t[:1].upper() + t[1:]


def _paragraphs(t):
    parts = [p.strip() for p in t.split("\n") if p.strip()]
    fixed = []
    for p in parts:
        if not re.search(r"[.!?…\"')\]]$", p):
            p += "."
        fixed.append(p)
    return " ".join(fixed)


def spoken(text, sex=None):
    """Source text (after source_clean) -> ([(role, text)...], flags). role "speaker" or "narrator"."""
    flags = set()
    t = resolve_g(text, sex)
    if WORLD_STATE_RE.search(t):
        return [], ["dynamic-value"]                         # "$2063w": a live server counter, not voiceable
    if OBJ_AMOUNT_RE.search(t):
        t = OBJ_AMOUNT_RE.sub("", t)                         # "$2oa": the objective's count, said by the UI
        flags.add("objective-amount")
    if PH_RE.search(t):
        t = PH_RE.sub("", t)                                 # "[PH] Collect frogs": the mark is not read
        flags.add("placeholder-text")
    pieces, pos = [], 0                                      # (role, text); "short" = a direction too short to read
    for m in DIRECTION_RE.finditer(t):
        pieces.append(("speaker", t[pos:m.start()]))
        d = (m.group(1) if m.group(1) is not None else m.group(2)).strip()
        if len(re.findall(r"[A-Za-z0-9']+", d)) >= MIN_DIRECTION_WORDS:
            pieces.append(("narrator", d))
        elif d:
            pieces.append(("short", d))
        pos = m.end()
    pieces.append(("speaker", t[pos:]))
    short = [("narrator", d) for role, d in pieces if role == "short"]
    if short and not any(role != "short" and re.search(r"[A-Za-z0-9]", x) for role, x in pieces):
        segs = short                                         # "<Thrall grunts.>" alone: the narrator reads it
    else:
        if short:
            flags.add("direction-dropped")                   # "<grin>" inside a spoken line: left out, and the
        segs = []                                            # words around it stay ONE sentence ("I <sigh>
        for role, x in pieces:                               # suppose so." -> "I suppose so.", not "I. Suppose")
            if role == "short":
                role, x = "speaker", " "
            if role == "speaker" and segs and segs[-1][0] == "speaker":
                segs[-1] = ("speaker", segs[-1][1] + x)
            elif role == "narrator" or x.strip():
                segs.append((role, x))
    out = []
    for role, s in segs:
        if "<" in s or ">" in s:
            s = s.replace("<", " ").replace(">", " ")        # an unmatched bracket in the source
            flags.add("stray-bracket")
        s = _tidy(_paragraphs(_drop_tokens(s, flags)))
        if not re.search(r"[A-Za-z0-9]", s):
            continue
        if role == "narrator" and not re.search(r"[.!?…]$", s):
            s += "."
        if out and out[-1][0] == role:
            out[-1] = (role, out[-1][1] + " " + s)
        else:
            out.append((role, s))
    return out, sorted(flags)


# ---------------------------------------------------------------- exporter helpers (not in the reference)
WORD_RE = re.compile(r"[A-Za-z0-9']+")


def words(text):
    """Words of a spoken text, as the spec counts them for lengths and stats."""
    return len(WORD_RE.findall(text))


def has_letters(text):
    """Speakable: at least one letter after cleaning (SPEC.md 3.2)."""
    return bool(text) and re.search(r"[A-Za-z]", text) is not None


def canon_title(title):
    """The canonical quest title of P.titles: the same canonicalisation as greetings."""
    return _canon(source_clean(title or ""))


def override_key(source_text):
    """The key of spoken_overrides.json: sha1 of the source text (after source_clean), 12 hex digits."""
    return hashlib.sha1((source_text or "").encode("utf-8")).hexdigest()[:12]


FINAL_BAD = [(re.compile(r"[$<>|{}]"), "markup character"), (re.compile(r"\bNULL\b"), "the word NULL"),
             (re.compile(r"\bnn[A-Z]"), "an escape left as 'nn'")]


def final_problems(segments):
    """The spec's final checks (3.4) on spoken segments: a list of problems, empty when the line is clean."""
    out = []
    for _, s in segments:
        for rx, why in FINAL_BAD:
            if rx.search(s):
                out.append("%s in %r" % (why, s[:80]))
    return out
