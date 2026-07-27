#!/usr/bin/env python3
"""Mechanical consistency checks for the app-box knowledge base.

The bookkeeping half of `skills/lint` — deterministic, runnable, fast. It does NOT
judge meaning (that's the agent's semantic pass in SKILL.md); it catches the
mechanical rot that lets contradictions hide: a doc missing from the index, a
dead link, an orphan page, a half-wired supersede pointer.

Usage:
  python skills/lint/lint_kb.py            # lint the repo; exit 1 if any ERROR
  python skills/lint/lint_kb.py --self-test  # synthetic fixtures; assert detection

Exit: 0 = clean (warnings allowed) · 1 = at least one ERROR · 2 = self-test/usage error.
"""
from __future__ import annotations
import re, sys, tempfile
from pathlib import Path

LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")          # [text](target)
WIKILINK = re.compile(r"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]")  # [[slug]] or [[slug|alias]]


def _md_files(d: Path):
    return sorted(p for p in d.rglob("*.md")) if d.is_dir() else []


def check(root: Path, memory: Path | None = None):
    """Return (errors, warnings) — lists of strings — for a knowledge-base root."""
    errors, warnings = [], []
    docs = root / "docs"
    index = docs / "index.md"
    md = [p for p in _md_files(docs)]

    if not index.exists():
        errors.append("docs/index.md is MISSING — the read-first navigator must exist")
        index_txt = ""
    else:
        index_txt = index.read_text(encoding="utf-8", errors="replace")

    # 1. INDEX COVERAGE — every docs/*.md (except the index) named in index.md
    for p in md:
        if p == index:
            continue
        rel = p.relative_to(docs).as_posix()
        if rel not in index_txt:
            errors.append(f"unindexed: {rel} is not referenced in docs/index.md")

    # 2. LINK INTEGRITY — relative .md links resolve
    inbound: set[Path] = set()
    for p in md:
        for m in LINK.finditer(p.read_text(encoding="utf-8", errors="replace")):
            tgt = m.group(1).split("#", 1)[0].strip()
            if not tgt or tgt.startswith(("http://", "https://", "mailto:", "/")):
                continue
            if not tgt.endswith(".md"):
                continue
            dest = (p.parent / tgt).resolve()
            if dest.exists():
                inbound.add(dest)
            else:
                errors.append(f"dead link: {p.relative_to(root).as_posix()} → {tgt}")

    # 3. ORPHANS — docs page with no inbound link AND not in the index (warn)
    for p in md:
        if p == index:
            continue
        rel = p.relative_to(docs).as_posix()
        if p.resolve() not in inbound and rel not in index_txt:
            warnings.append(f"orphan: {rel} has no inbound link and is not indexed")

    # 4. SUPERSEDE CONSISTENCY — every 'supersedes (x)' has a flag on the old entry (warn)
    changelog = docs / "changelog.md"
    if changelog.exists():
        txt = changelog.read_text(encoding="utf-8", errors="replace")
        if re.search(r"supersed", txt, re.I) and not re.search(r"SUPERSEDED", txt):
            warnings.append("changelog: 'supersedes' used but no 'SUPERSEDED' back-pointer found")

    # 5. WIKILINK INTEGRITY (memory) — [[slug]] resolves to a memory file (warn: forward-refs ok)
    if memory and memory.is_dir():
        slugs = {p.stem for p in _md_files(memory)}
        for p in _md_files(memory):
            for m in WIKILINK.finditer(p.read_text(encoding="utf-8", errors="replace")):
                slug = m.group(1).strip()
                if slug not in slugs:
                    warnings.append(f"wikilink: [[{slug}]] in {p.name} has no target file (forward-ref?)")
    return errors, warnings


def _self_test():
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        docs = root / "docs"; docs.mkdir()
        (docs / "index.md").write_text("# index\n- [good](good.md) — ok\n")
        (docs / "good.md").write_text("# good\nsee [other good](good.md)\n")
        (docs / "bad.md").write_text("# bad\nbroken [x](missing.md)\n")  # unindexed + dead link
        (docs / "changelog.md").write_text("supersedes (a)\n")          # no SUPERSEDED → warn
        errors, warnings = check(root)
        joined_e, joined_w = "\n".join(errors), "\n".join(warnings)
        assert any("unindexed: bad.md" in e for e in errors), f"missed unindexed: {joined_e}"
        assert any("dead link" in e and "missing.md" in e for e in errors), f"missed dead link: {joined_e}"
        assert not any("good.md" in e for e in errors), f"false positive on good.md: {joined_e}"
        assert any("SUPERSEDED" in w for w in warnings), f"missed supersede warn: {joined_w}"
    print("self-test: PASS")


def main(argv):
    if "--self-test" in argv:
        _self_test(); return 0
    root = Path(__file__).resolve().parents[2]  # skills/lint/ → repo root
    memory = Path.home() / ".claude/projects/-Volumes-developer-ssd-Developer-factory/memory"
    errors, warnings = check(root, memory)
    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    print(f"\nlint: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
