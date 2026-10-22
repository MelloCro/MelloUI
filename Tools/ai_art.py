"""
Generate art with OpenAI's image API (the user, 2026-10-22: "for you to use it and generate assets when needed" --
their pick of the API over driving the ChatGPT app). A picture from a prompt, or an edit of pictures handed in (a
sheet to restyle, references to match the look, a mask for the part to change), saved as PNG / WebP under
MelloUI-BuildData/output/ai_art/<name>/ (Tools/paths.py: never inside the addon) with a <name>.json beside it
recording what was asked (the prompt, the model, the settings, the references -- never the key).

The key: the environment variable OPENAI_API_KEY, the user's own (never in the project, never on the command line,
never printed). Read from the process's environment, else from the user's Windows environment in the registry
(HKCU\\Environment), so a key set with `setx` works without restarting anything.

    python Tools/ai_art.py "a gold ring, cartoon, thick dark outline" --name ring_test --transparent
    python Tools/ai_art.py "the same frame in silver" --name frame_silver --ref sheet.png --ref style.png
    python Tools/ai_art.py "repaint the gem red" --name gem_red --ref icon.png --mask gem_mask.png
    python Tools/ai_art.py --check            whether a key is found (it is never shown)

    --size WxH|auto      1024x1024 (default), 1536x1024, 1024x1536, or any multiple of 16 (edges <= 3840)
    --quality Q          low | medium | high (default) | xhigh | max | auto
    --transparent        a transparent background (PNG / WebP)
    --n N                how many to make (default 1)
    --model M            gpt-image-2.5-sunburst (default: precise, the edits'), or --fast: gpt-image-2.5-flare
    --format F           png (default) | webp | jpeg
    --ref PATH           a picture to edit or to match (repeat for several; the first is the one a mask applies to)
    --mask PATH          a PNG with alpha the size of the first --ref: its clear part is what changes
    --out DIR            where to save (default MelloUI-BuildData/output/ai_art/<name>)
    --dry                print the request (no key, no call) and stop
"""
import argparse
import base64
import datetime
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request
import uuid

from paths import OUTPUT

API = "https://api.openai.com/v1/images/"
MODEL, FAST = "gpt-image-2.5-sunburst", "gpt-image-2.5-flare"
KEY_NAME = "OPENAI_API_KEY"
TIMEOUT = 600   # (seconds: a max-quality picture takes a while)


def api_key():
    """the user's key: the process's environment, else the user's Windows environment (a fresh `setx`)"""
    key = os.environ.get(KEY_NAME, "").strip()
    if key:
        return key
    if sys.platform == "win32":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
                value, _ = winreg.QueryValueEx(k, KEY_NAME)
                return str(value).strip()
        except OSError:
            return ""
    return ""


def multipart(fields, files):
    """a multipart/form-data body: fields [(name, value)], files [(name, path)]"""
    boundary = "----melloui" + uuid.uuid4().hex
    out = []
    for name, value in fields:
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n"
                    % (boundary, name, value)).encode("utf-8"))
    for name, path in files:
        mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
        head = ("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
                % (boundary, name, os.path.basename(path), mime)).encode("utf-8")
        with open(path, "rb") as f:
            out.append(head + f.read() + b"\r\n")
    out.append(("--%s--\r\n" % boundary).encode("utf-8"))
    return b"".join(out), "multipart/form-data; boundary=" + boundary


def request(endpoint, key, body, content_type):
    req = urllib.request.Request(API + endpoint, data=body, method="POST")
    req.add_header("Authorization", "Bearer " + key)
    req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read().decode("utf-8")).get("error", {}).get("message", "")
        except (ValueError, AttributeError):
            msg = ""
        sys.exit("the API refused it (%d): %s" % (e.code, msg or e.reason))
    except urllib.error.URLError as e:
        sys.exit("no answer from the API: %s" % e.reason)


def main():
    p = argparse.ArgumentParser(description="Generate art with OpenAI's image API (the key: %s)." % KEY_NAME)
    p.add_argument("prompt", nargs="?")
    p.add_argument("--name")
    p.add_argument("--size", default="1024x1024")
    p.add_argument("--quality", default="high")
    p.add_argument("--transparent", action="store_true")
    p.add_argument("--n", type=int, default=1)
    p.add_argument("--model", default=MODEL)
    p.add_argument("--fast", action="store_true")
    p.add_argument("--format", default="png", choices=("png", "webp", "jpeg"))
    p.add_argument("--ref", action="append", default=[])
    p.add_argument("--mask")
    p.add_argument("--out")
    p.add_argument("--dry", action="store_true")
    p.add_argument("--check", action="store_true")
    a = p.parse_args()

    key = api_key()
    if a.check:
        print("key found (%s)" % KEY_NAME if key else "no key: set %s (see the docstring)" % KEY_NAME)
        return 0 if key else 1
    if not (a.prompt and a.name):
        p.error("a prompt and --name are needed")
    if a.transparent and a.format == "jpeg":
        p.error("a transparent background needs png or webp")
    for path in a.ref + ([a.mask] if a.mask else []):
        if not os.path.isfile(path):
            p.error("not a file: " + path)
    if a.mask and not a.ref:
        p.error("--mask needs the picture it applies to (--ref)")

    model = FAST if a.fast else a.model
    settings = {"model": model, "prompt": a.prompt, "n": a.n, "size": a.size, "quality": a.quality,
                "output_format": a.format}
    if a.transparent:
        settings["background"] = "transparent"
    endpoint = "edits" if a.ref else "generations"
    if a.dry:
        print(json.dumps({"endpoint": endpoint, "settings": settings, "ref": a.ref, "mask": a.mask}, indent=2))
        return 0
    if not key:
        sys.exit("no key: set %s (see the docstring)" % KEY_NAME)

    if a.ref:
        files = [("image[]" if len(a.ref) > 1 else "image", path) for path in a.ref]
        if a.mask:
            files.append(("mask", a.mask))
        body, ctype = multipart([(k, str(v)) for k, v in settings.items()], files)
    else:
        body, ctype = json.dumps(settings).encode("utf-8"), "application/json"
    print("asking %s (%s, %s, %s)..." % (model, endpoint, a.size, a.quality), flush=True)
    answer = request(endpoint, key, body, ctype)

    out = a.out or os.path.join(OUTPUT, "ai_art", a.name)
    os.makedirs(out, exist_ok=True)
    saved = []
    for i, item in enumerate(answer.get("data") or []):
        data = item.get("b64_json")
        if not data:
            continue
        path = os.path.join(out, "%s%s.%s" % (a.name, "_%d" % (i + 1) if a.n > 1 else "", a.format))
        with open(path, "wb") as f:
            f.write(base64.b64decode(data))
        saved.append(path)
        print("->", os.path.normpath(path))
    record = dict(settings, endpoint=endpoint, ref=[os.path.abspath(r) for r in a.ref],
                  mask=os.path.abspath(a.mask) if a.mask else None, files=saved, usage=answer.get("usage"),
                  made=datetime.datetime.now().isoformat(timespec="seconds"))
    with open(os.path.join(out, a.name + ".json"), "w", encoding="utf-8") as f:
        json.dump(record, f, indent=2)
    if not saved:
        sys.exit("the answer held no picture")
    return 0


if __name__ == "__main__":
    sys.exit(main())
