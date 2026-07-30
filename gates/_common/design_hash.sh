#!/usr/bin/env bash
# gates/_common/design_hash.sh — the canonical design-tree hash (§6 hash-bound
# approval). Prints one sha256 hexdigest for a design dir: for every file under
# the tree, update(sorted relative path, NUL, raw contents). Paths are part of
# the hash, so a rename is a move; contents are raw bytes, so a one-char edit
# is a move.
#
# Excluded (volatile — never part of the design's intent):
#   .DS_Store       Finder droppings
#   approval.lock   the freeze gate's own stamp (carries an approvedAt timestamp;
#                   hashing it would make every --approve a design "move")
#
# Usage: design_hash.sh <design-dir>   (prints the hexdigest; exit 2 on bad input)
set -uo pipefail

DESIGN="${1:-}"
[ -d "$DESIGN" ] || { echo "FAIL: design_hash.sh: no design dir at ${DESIGN:-<none>}" >&2; exit 2; }

python3 - "$DESIGN" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
EXCLUDE = {".DS_Store", "approval.lock"}
h = hashlib.sha256()
paths = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for fn in filenames:
        if fn in EXCLUDE:
            continue
        paths.append(os.path.relpath(os.path.join(dirpath, fn), root))
for rel in sorted(paths):
    h.update(rel.encode())
    h.update(b"\0")
    with open(os.path.join(root, rel), "rb") as fh:
        h.update(fh.read())
print(h.hexdigest())
PY
