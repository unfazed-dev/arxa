# content_firewall.py
#!/usr/bin/env python3
"""content_firewall — the IP boundary. Classifies every skeleton node as
mechanism (reproduce) vs content (redact to a typed slot), strips content from
emitted nodes, and audits a written bundle/ for any content leak. The bundle is
content-free BY CONSTRUCTION: audit_bundle() is the unconditional gate."""
from __future__ import annotations
import json
import re
from pathlib import Path

ICON_MAX_PX = 48  # an inline svg whose largest side <= this is treated as a UI icon


def _svg_class(node):
    b = node.get("bbox") or {}
    longest = max(b.get("w") or 0, b.get("h") or 0)
    return "icon" if longest <= ICON_MAX_PX else "illustration"


def classify_node(node):
    """Classify a skeleton node. Returns {klass, type[, svg_class]}.
    klass: 'content' (redact->slot) | 'kept-content' (svg: keep geometry, tag) |
    'mechanism' (reproduce as-is)."""
    role = node.get("role")
    if role == "image":
        return {"klass": "content", "type": "image"}
    if role == "text":
        return {"klass": "content", "type": "text"}
    if role == "svg":
        return {"klass": "kept-content", "type": "svg",
                "svg_class": _svg_class(node)}
    return {"klass": "mechanism", "type": role}


# literal-content keys that must never survive onto an emitted node.
CONTENT_KEYS = ("text", "src", "href", "url", "background_image",
                "alt", "title", "aria_label", "placeholder", "value", "content")


def redact_node(node):
    """Return a copy of node with every CONTENT_KEYS entry removed. Mechanism
    keys (bbox, role, aria_role, token_ref, anim_ref, font, text_len, sizing, layout, ...)
    are preserved. text_len is intentionally KEPT — it is a sizing input, not
    content."""
    return {k: v for k, v in node.items() if k not in CONTENT_KEYS}


# leak signatures
# Any data: URI, ANY encoding (base64 / url-encoded / ;utf8 / plain). A real data URI is
# `data:[<mediatype>][;base64],<payload>` — the comma after the metadata is mandatory and is the
# unambiguous discriminator. Encoding-agnostic to MATCH (not lag) the redactor this audit backstops:
# _style._is_external treats every `data:` as content regardless of encoding, so a base64-only audit
# was the weaker of the two. The `(?<![a-zA-Z])` word-boundary anchor requires `data:` at a token
# start (preceded by quote / `(` / whitespace / `,` / start-of-value — always true for a real data
# URI), which kills the substring class `metadata:foo,` / `somedata:x,` (the `data` there is preceded
# by a letter) without losing any genuine match. Linear (fixed-width lookbehind + one char-class run +
# a literal comma, no backtracking → no ReDoS). No false-positive on realistic post-redaction bundle
# values (verified: the only `data:` in committed artifacts is the RAW un-audited capture input, never
# a shipped/redacted bundle). Metadata charset covers type/subtype + `;charset=…;base64`.
_DATA_URI = re.compile(r"(?<![a-zA-Z])data:[a-zA-Z0-9.+/;=_-]*,", re.I)
_B64_BLOB = re.compile(r"[A-Za-z0-9+/]{200,}={0,2}")
_CONTENT_URL = re.compile(
    r"https?://[^\s\"')]+\.(?:png|jpe?g|gif|webp|avif|svg|mp4|webm|mov|woff2?|ttf|otf)",
    re.I)
# CSS url()-WRAPPED external reference, extension-AGNOSTIC. _CONTENT_URL above only fires on a
# known media/font extension; an external asset URL with no such extension (CDN image w/o ext,
# `cursor: url(x.cur)`, etc.) slips past it. Such URLs reach disk only inside computed-style
# DELTA values (theme/responsive/form_state) — base nodes have background_image etc. stripped by
# redact_node (a CONTENT_KEYS key), but delta dicts are not key-stripped and their redactor is a
# passthrough, so the firewall is the sole backstop. The `url(` wrapper is the discriminator: it
# catches asset refs in any property value WITHOUT firing on the bundle's bare top-level `url`
# field (not url()-wrapped) or `url(#fragment)` internal refs (no scheme). Chrome serializes the
# value quoted (`url("https://…")`) and json.dumps escapes the quote on disk (`url(\"https…`), so
# tolerate an optional backslash + quote + whitespace after `url(`. (Gap surfaced by the
# form-state cursor canary; closes the pre-existing background-image-no-ext delta leak too.)
# ONE \s* (not two straddling the optional quote): two cause O(n^2) backtracking (ReDoS) on a
# long whitespace run with no following scheme, and audit_bundle text-scans EVERY file as an
# independent backstop (a malformed bundle file is in scope). Chrome never emits `url(" https`, so
# the single \s* loses nothing real. Residual ceiling: protocol-relative `url(//cdn/x)` has no
# scheme and would slip, but Chrome absolutizes computed url() to http(s) before capture, so a raw
# `//` never reaches disk (see _style.py absolutization).
_CSS_URL_REF = re.compile(r"url\(\s*\\?[\"']?https?://", re.I)
# prose = a run of mostly-ASCII letters (space optional) past the theme noise
# floor. ASCII-only by construction; non-ASCII scripts → _NONASCII_PROSE below.
_PROSE = re.compile(r"[A-Za-z][A-Za-z ,.''\-]{24,}")
# non-ASCII prose: a run of >=4 letters from spaceless / non-Latin scripts that
# _PROSE cannot see (CJK, kana, Hangul, Greek, Cyrillic, Hebrew, Arabic, Thai,
# precomposed Latin-ext). Real bundle copy on non-English sites (e.g. Japanese
# kasane) decodes to these via json.loads and would otherwise ship silently.
# NOTE: non-ASCII-ALPHA detection, NOT full prose — scattered-diacritic Latin/
# Vietnamese and sub-4-char content remain residual gaps (documented).
_NONASCII_PROSE = re.compile(
    r"[À-ɏͰ-ϿЀ-ӿ֐-׿؀-ۿ"
    r"฀-๿Ḁ-ỿ぀-ヿㇰ-ㇿ㐀-䶿"
    r"一-鿿가-힯豈-﫿ｦ-ﾟ]{4,}")
# binary magic numbers for raster/font/video.
_MAGIC = [b"\x89PNG", b"\xff\xd8\xff", b"GIF8", b"RIFF", b"wOFF", b"wOF2",
          b"\x00\x01\x00\x00", b"OTTO", b"\x1a\x45\xdf\xa3"]
# Only FONT-family keys are exempt: font stacks are the lone prose-shaped
# mechanism. url/easing/cubic_bezier/timing/ease are deliberately NOT exempt —
# their values never trip _PROSE (URLs break on :/ , easings break on "("), so
# exempting them bought nothing and only opened a hole for prose hiding under
# those keys. data:/content-url checks run on the whole text regardless.
_PROSE_EXEMPT_KEYS = {"family", "families", "font", "font_family", "fontFamily"}
# generic CSS font keywords — exempt prose runs that are clearly font stacks even
# in keyless text (css/svg) where the JSON-key signal is unavailable.
_FONT_KEYWORDS = ("sans-serif", "serif", "monospace", "system-ui",
                  "-apple-system", "ui-sans-serif", "ui-monospace", "cursive")


def _is_font_value(s):
    low = s.lower()
    return any(kw in low for kw in _FONT_KEYWORDS)


def _walk_strings(obj, key=None):
    """Yield (nearest_mapping_key, string) for every string in a nested JSON
    value. List items inherit their list's key."""
    if isinstance(obj, str):
        yield key, obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            yield from _walk_strings(v, k)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk_strings(v, key)


def _prose_in_json(data, rel):
    for key, s in _walk_strings(data):
        if key in _PROSE_EXEMPT_KEYS or _is_font_value(s):
            continue
        if _PROSE.search(s) or _NONASCII_PROSE.search(s):
            return [{"kind": "prose", "file": rel, "sample": s[:40]}]
    return []


def _prose_raw(txt, rel):
    for m in _PROSE.finditer(txt):
        s = m.group(0)
        if _is_font_value(s):
            continue
        return [{"kind": "prose", "file": rel, "sample": s[:40]}]
    m = _NONASCII_PROSE.search(txt)
    if m:
        return [{"kind": "prose", "file": rel, "sample": m.group(0)[:40]}]
    return []


def _scan_text(path, rel):
    out = []
    txt = path.read_text(errors="replace")
    if _DATA_URI.search(txt):
        out.append({"kind": "data-uri", "file": rel})
    if _CONTENT_URL.search(txt) or _CSS_URL_REF.search(txt):
        out.append({"kind": "content-url", "file": rel})
    if _B64_BLOB.search(txt):
        out.append({"kind": "base64-blob", "file": rel})
    # prose: key-aware for JSON (exempt font/theme keys), raw fallback otherwise.
    if path.suffix.lower() == ".json":
        try:
            out.extend(_prose_in_json(json.loads(txt), rel))
        except ValueError:
            out.extend(_prose_raw(txt, rel))
    else:
        out.extend(_prose_raw(txt, rel))
    return out


def audit_bundle(bundle_dir):
    """Scan every file under bundle_dir for content leaks. Returns a list of
    violations (empty == clean). Bias to false-positive on real content but
    exempts known mechanism (font stacks, theme/easing keys) so legitimate
    bundles pass: catches data: URIs, base64 blobs, retained content URLs,
    prose-like strings, and raster/font/video magic bytes. This is THE
    invariant — callers must treat a non-empty result as a hard failure."""
    root = Path(bundle_dir)
    viol = []
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(root))
        head = p.read_bytes()[:16]
        # magic bytes: raster/font/video. ISO-BMFF (mp4/mov/avif/heic) carries
        # the "ftyp" box type at offset 4, not 0 — check both.
        if any(head.startswith(m) for m in _MAGIC) or head[4:8] == b"ftyp":
            viol.append({"kind": "magic-bytes", "file": rel})
            continue  # binary; don't also text-scan
        # scan EVERY non-binary file as text, not just known extensions — a
        # .js/.xml/extensionless file could still carry prose/urls/base64.
        viol.extend(_scan_text(p, rel))
    return viol
