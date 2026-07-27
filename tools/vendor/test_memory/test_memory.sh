#!/usr/bin/env bash
# test_memory.sh — five-tier verification of the stacked_kit memory system.
#
# Tiers (the operator-facing taxonomy):
#   smoke       — happy paths on the real tree (files exist, formats conform,
#                 facts valid + in parity with kit dirs, extractor runs clean)
#   pressure    — volume + determinism (50 kits, 3x-run byte-identical output,
#                 900-symbol kit, real-tree re-extraction idempotency)
#   stress      — hostile inputs (malformed/empty/folded pubspecs, no-lib kits,
#                 adversarial Dart content, 10k-entry log, corrupted facts,
#                 concurrent extraction)
#   integration — memory wired into the kit gates (zero-drift vs git, fixity
#                 drift fires + heals, full validate_docs.sh composition)
#   e2e         — the documented AGENTS.md workflows in a hermetic sandbox:
#                 ingest (extract -> gen_playbook -> build_toc -> validate)
#                 and the drift-and-heal loop + log-append discipline
#
# Harness conventions mirror tools/test_gates.sh: bash 3.2-safe (no assoc
# arrays / mapfile / readlink -f), deliberately NO `set -e` so one failure
# does not abort the suite, hermetic sandboxes under mktemp.
#
#   tools/test_memory.sh            # full suite
#   tools/test_memory.sh -v         # verbose (show every PASS)
#   tools/test_memory.sh -g NAME    # one group: smoke|pressure|stress|integration|e2e
set -uo pipefail
REAL="$(cd "$(dirname "$0")/.." && pwd)"
VERBOSE=0; WANT=""
while [ $# -gt 0 ]; do
  case "$1" in -v) VERBOSE=1;; -g) shift; WANT="${1:-}";; *) WANT="$1";; esac
  shift
done

PASS=0; FAIL=0; FAILED=()
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

say(){ printf '\n### %s\n' "$1"; }
ok(){ PASS=$((PASS+1)); [ "$VERBOSE" -eq 1 ] && echo "  PASS: $*"; return 0; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$*"); echo "  FAIL: $*"; return 0; }
run(){ ( "$@" ) 2>&1; echo "exit:$?"; }
has(){ [ "${2:-$out}" != "${2%%$1*}" ]; }   # substring test: has NEEDLE [HAY]

# count of NON-conforming header lines in a log file (0 = all conform)
logcheck(){ grep -E '^## \[' "$1" | grep -cvE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] [a-z0-9-]+ \| .+'; }

# mkroot <name> — hermetic mini kit tree with the memory tooling copied in.
# Every tool self-locates from its own path, so the copy is fully hermetic.
mkroot(){
  local p="$SCRATCH/$1"; rm -rf "$p"
  mkdir -p "$p/tools" "$p/memory/facts" "$p/kb"
  cp "$REAL/tools/extract_facts.sh" "$REAL/tools/gen_playbook.py" \
     "$REAL/tools/build_toc.py" "$REAL/tools/validate_docs.sh" \
     "$REAL/tools/kb_check.sh" "$p/tools/"
  printf '{"sources": []}\n' > "$p/kb/sources.json"
  echo "$p"
}

# make_kit <root> <dir> <pkgname> — minimal extraction fodder (2 real symbols)
make_kit(){
  local root=$1 d=$2 name=$3
  mkdir -p "$root/$d/lib/src"
  cat > "$root/$d/pubspec.yaml" <<YAML
name: $name
description: synthetic kit $name
publish_to: 'none'
environment:
  sdk: '>=3.0.3 <4.0.0'
YAML
  # symbols must start uppercase — the extractor's public-surface regex
  # ([A-Z][A-Za-z0-9_]*) deliberately ignores lowercase identifiers
  printf 'class SynthService {}\nenum SynthState { idle, busy }\n' \
    > "$root/$d/lib/src/service.dart"
}

# make_rich_kit <root> <dir> <pkgname> [backing-dep...] — a kit whose README
# fills every gen_playbook narrative section (zero TODO(prose)) and whose
# backing deps satisfy kb_check coverage (>=3 mined package sources).
make_rich_kit(){
  local root=$1 d=$2 name=$3; shift 3
  mkdir -p "$root/$d/lib/src"
  {
    echo "name: $name"
    echo "description: Rich synthetic kit for the memory e2e."
    echo "publish_to: 'none'"
    echo "environment:"
    echo "  sdk: '>=3.0.3 <4.0.0'"
    if [ $# -gt 0 ]; then
      echo "dependencies:"
      local dep; for dep in "$@"; do echo "  $dep: ^1.0.0"; done
    fi
  } > "$root/$d/pubspec.yaml"
  printf "library %s;\nexport 'src/service.dart';\n" "$name" > "$root/$d/lib/$name.dart"
  printf 'class %sService {}\nclass %sConfig {}\ntypedef %sCallback = void Function();\n' \
    "$name" "$name" "$name" > "$root/$d/lib/src/service.dart"
  printf '// testing seam\nclass Fake%sService {}\n' "$name" > "$root/$d/lib/testing.dart"
  cat > "$root/$d/README.md" <<README
# $name

A rich synthetic kit used to prove the memory pipeline end to end.

## Scope
Covers the synthetic domain entirely.

## Usage
Import the barrel and call the service.

## Setup
Register it in the locator at startup.

## Architecture
A single service layer over pure Dart.

## Gotchas
None yet; synthetic.

## Testing
Script the fake in lib/testing.dart.

## Decisions
Pure Dart for portability.
README
}

facts_hash(){ (cd "$1" && cat memory/facts/*.json 2>/dev/null | shasum -a 256 | cut -d' ' -f1); }

# ---------------------------------------------------------------------------
test_smoke(){
  say "SMOKE (real tree)"; local o n f
  # MEMORY.md: the curated, capped session-start memory
  if [ -f "$REAL/memory/MEMORY.md" ]; then
    n=$(wc -l < "$REAL/memory/MEMORY.md" | tr -d ' ')
    [ "$n" -le 110 ] && ok "MEMORY.md exists and is within the ~100-line cap ($n lines)" \
                     || bad "MEMORY.md over cap: $n lines (cap ~100)"
  else bad "MEMORY.md missing"; fi
  # log.md: append-only event log, strict header format
  if [ -f "$REAL/memory/log.md" ]; then
    n=$(logcheck "$REAL/memory/log.md")
    [ "$n" -eq 0 ] && ok "log.md headers all conform to '## [YYYY-MM-DD] type | title'" \
                   || bad "$n log.md header(s) break the entry format"
    [ "$VERBOSE" -eq 1 ] && echo "  log entry types: $(grep -oE '^## \[[0-9-]+\] [a-z0-9-]+' "$REAL/memory/log.md" | awk '{print $3}' | sort -u | tr '\n' ' ')"
  else bad "log.md missing"; fi
  # extractor runs clean on the real tree
  o=$(run bash "$REAL/tools/extract_facts.sh")
  has "exit:0" "$o" && ok "extract_facts.sh runs clean on the real tree" \
                    || bad "extract_facts failed: $(echo "$o" | tail -3)"
  # every fact is valid JSON with the contract keys, and facts <-> kits in parity
  o=$(python3 - "$REAL" <<'PY'
import json, os, sys
root = sys.argv[1]
fd = os.path.join(root, 'memory', 'facts')
REQ = {'kit','name','version','description','dependencies','kitDeps',
       'frameworkDeps','backingPackages','publicSurface','hasTesting',
       'readmeLines','readmeFirst'}
errs = []
facts = set()
for fn in sorted(os.listdir(fd)):
    if not fn.endswith('.json'): continue
    try: d = json.load(open(os.path.join(fd, fn)))
    except Exception as e: errs.append(f'{fn}: invalid JSON ({e})'); continue
    facts.add(fn[:-5])
    miss = REQ - set(d)
    if miss: errs.append(f'{fn}: missing keys {sorted(miss)}')
    if d.get('kit') != fn[:-5]: errs.append(f'{fn}: kit field {d.get("kit")!r} != filename')
kits = set()
for dirpath, dirnames, filenames in os.walk(root):
    depth = dirpath[len(root):].count(os.sep)
    if depth > 1: dirnames[:] = []; continue
    dirnames[:] = [x for x in dirnames if x not in ('.dart_tool','tools','.git')]
    if 'pubspec.yaml' in filenames and depth == 1:
        kits.add(os.path.basename(dirpath))
if facts != kits:
    errs.append(f'fact/kit parity broken: facts-only={sorted(facts-kits)} kits-only={sorted(kits-facts)}')
print('FACTS_OK' if not errs else 'FACTS_BAD: ' + '; '.join(errs))
PY
)
  has "FACTS_OK" "$o" && ok "all facts valid JSON + contract keys + fact<->kit parity" \
                      || bad "facts contract: $o"
}

test_pressure(){
  say "PRESSURE"; local s o i h1 h2 h3 n t0 dt
  # 50 kits extracted in one run
  s="$SCRATCH/p50"; mkdir -p "$s/tools" "$s/memory/facts"
  cp "$REAL/tools/extract_facts.sh" "$s/tools/"
  for i in $(seq 1 50); do make_kit "$s" "k$i" "stacked_kit_k$i"; done
  o=$(run bash "$s/tools/extract_facts.sh")
  n=$(ls "$s"/memory/facts/*.json 2>/dev/null | wc -l | tr -d ' ')
  { has "exit:0" "$o" && [ "$n" -eq 50 ]; } && ok "50 kits extract in one run ($n facts)" \
    || bad "50-kit extraction: n=$n $(echo "$o" | tail -2)"
  python3 -c "import json; d=json.load(open('$s/memory/facts/k50.json')); assert len(d['publicSurface'])==2, d['publicSurface']" \
    && ok "50-kit run: spot-checked symbol extraction (k50 has its 2 symbols)" \
    || bad "50-kit run: k50 surface wrong"
  # determinism: 3 runs over the same tree must be byte-identical
  h1=$(facts_hash "$s"); bash "$s/tools/extract_facts.sh" >/dev/null 2>&1
  h2=$(facts_hash "$s"); bash "$s/tools/extract_facts.sh" >/dev/null 2>&1
  h3=$(facts_hash "$s")
  { [ "$h1" = "$h2" ] && [ "$h2" = "$h3" ]; } && ok "extraction is deterministic (3 runs byte-identical)" \
    || bad "extraction non-deterministic across runs: $h1 / $h2 / $h3"
  # one big kit: 300 files x 3 symbols = 900
  s="$SCRATCH/pbig"; mkdir -p "$s/tools" "$s/memory/facts" "$s/big/lib/src"
  cp "$REAL/tools/extract_facts.sh" "$s/tools/"
  cat > "$s/big/pubspec.yaml" <<'YAML'
name: stacked_kit_big
description: big synthetic kit
publish_to: 'none'
environment:
  sdk: '>=3.0.3 <4.0.0'
YAML
  for i in $(seq 1 300); do
    printf 'class Big%dAlpha {}\nclass Big%dBeta {}\nmixin Big%dMix {}\n' "$i" "$i" "$i" > "$s/big/lib/src/f$i.dart"
  done
  t0=$SECONDS
  o=$(run bash "$s/tools/extract_facts.sh")
  dt=$((SECONDS-t0))
  n=$(python3 -c "import json; print(len(json.load(open('$s/memory/facts/big.json'))['publicSurface']))" 2>/dev/null)
  { has "exit:0" "$o" && [ "${n:-0}" -eq 900 ] && [ "$dt" -lt 60 ]; } \
    && ok "900-symbol kit extracted correctly in ${dt}s" \
    || bad "big kit: symbols=${n:-ERR} time=${dt}s $(echo "$o" | tail -2)"
  # real-tree idempotency: re-extraction changes nothing (content-stable)
  h1=$(facts_hash "$REAL")
  bash "$REAL/tools/extract_facts.sh" >/dev/null 2>&1; h2=$(facts_hash "$REAL")
  bash "$REAL/tools/extract_facts.sh" >/dev/null 2>&1; h3=$(facts_hash "$REAL")
  { [ "$h1" = "$h2" ] && [ "$h2" = "$h3" ]; } && ok "real-tree re-extraction is idempotent (byte-identical)" \
    || bad "real-tree facts changed across re-extraction"
}

test_stress(){
  say "STRESS"; local s o n
  s="$SCRATCH/stress"; mkdir -p "$s/tools" "$s/memory/facts"
  cp "$REAL/tools/extract_facts.sh" "$REAL/tools/gen_playbook.py" "$s/tools/"
  # malformed pubspec variants — extractor must not crash
  mkdir -p "$s/empty/lib"; : > "$s/empty/pubspec.yaml"
  mkdir -p "$s/noname/lib"; printf 'description: no name here\n' > "$s/noname/pubspec.yaml"
  mkdir -p "$s/notyaml/lib"; printf '{{{ definitely not yaml\n' > "$s/notyaml/pubspec.yaml"
  # folded multiline description (regression guard — this class of bug shipped once)
  mkdir -p "$s/folded/lib"
  printf 'name: stacked_kit_folded\ndescription: >-\n  First part\n  second part\n  third\npublish_to: '\''none'\''\n' > "$s/folded/pubspec.yaml"
  o=$(run bash "$s/tools/extract_facts.sh")
  has "exit:0" "$o" && ok "malformed/empty/non-YAML pubspecs: extractor exits 0" \
                    || bad "extractor crashed on malformed pubspecs: $(echo "$o" | tail -3)"
  local fj="$s/memory/facts/folded.json"
  python3 -c "import json; d=json.load(open('$fj')); assert d['description']=='First part second part third', repr(d['description'])" 2>/dev/null \
    && ok "folded multiline YAML description rejoined correctly" \
    || bad "folded description broken: $(python3 -c "import json;print(repr(json.load(open('$fj'))['description']))" 2>/dev/null || echo 'no folded.json')"
  # kit with no lib/ and no README still yields a valid (empty) fact
  mkdir -p "$s/bare"
  printf 'name: stacked_kit_bare\ndescription: bare\npublish_to: '\''none'\''\n' > "$s/bare/pubspec.yaml"
  bash "$s/tools/extract_facts.sh" bare >/dev/null 2>&1
  python3 -c "import json; d=json.load(open('$s/memory/facts/bare.json')); assert d['publicSurface']==[] and d['readmeLines']==0" \
    && ok "no-lib/no-README kit yields valid empty fact" || bad "bare kit fact wrong"
  # adversarial Dart: comment/string-embedded fake symbols vs real ones.
  # The extractor strips non-code (line/nested-block comments, raw/triple/
  # escaped strings, ${} interpolation) before matching — expect ZERO ghosts.
  mkdir -p "$s/adv/lib/src"
  printf 'name: stacked_kit_adv\ndescription: adversarial\npublish_to: '\''none'\''\n' > "$s/adv/pubspec.yaml"
  cat > "$s/adv/lib/src/a.dart" <<'DART'
// class GhostFromComment {}
/* mixin PhantomFromBlock {} */
/* outer /* class GhostFromNested {} */ still comment */
final s = "class SpecterFromString {}";
final t = '''
class GhostFromTriple {}
''';
final r = r'class GhostFromRaw {}';
final e = 'it\'s a class GhostFromEscape {}';
final i = "interp ${'class GhostFromInterp {}'} end";
final j = "${v.length > 12 ? '${v.substring(0, 12)}…' : v})";
class RealOne {}
enum RealTwo { a, b }
DART
  bash "$s/tools/extract_facts.sh" adv >/dev/null 2>&1
  o=$(python3 - "$s/memory/facts/adv.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
names = [x['name'] for x in d['publicSurface']]
ghosts = [g for g in ('GhostFromComment','PhantomFromBlock','GhostFromNested',
                      'SpecterFromString','GhostFromTriple','GhostFromRaw',
                      'GhostFromEscape','GhostFromInterp') if g in names]
real = all(r in names for r in ('RealOne','RealTwo'))
print('ADV_OK real=%s ghosts=%d' % (real, len(ghosts)))
PY
)
  has "ADV_OK real=True ghosts=0" "$o" && ok "adversarial dart: 8 comment/string ghost forms stripped, real symbols kept" \
    || bad "adversarial dart extraction wrong: $o"
  # oversized log: 10k conformant entries stay cheap to check
  python3 -c "
open('$s/biglog.md','w').write(''.join('## [2026-07-%02d] ingest | entry %d\n' % (i%28+1, i) for i in range(10000)))"
  t0=$SECONDS; n=$(logcheck "$s/biglog.md"); dt=$((SECONDS-t0))
  { [ "$n" -eq 0 ] && [ "$dt" -lt 10 ]; } && ok "10k-entry log: format check clean in ${dt}s" \
    || bad "10k-entry log: $n non-conforming in ${dt}s"
  # corrupted fact JSON -> gen_playbook must fail LOUD (non-zero), not silently
  printf '{ not json' > "$s/memory/facts/broken.json"
  o=$(run python3 "$s/tools/gen_playbook.py" broken)
  has "exit:0" "$o" && bad "corrupted fact JSON: gen_playbook exited 0 (silent failure)" \
                    || ok "corrupted fact JSON: gen_playbook fails loud (non-zero)"
  # missing fact -> graceful skip, exit 0
  o=$(run python3 "$s/tools/gen_playbook.py" ghostkit)
  { has "exit:0" "$o" && has "skip ghostkit" "$o"; } && ok "missing fact: gen_playbook skips gracefully" \
    || bad "missing fact: $o"
  # concurrent extraction: 4 parallel runs, no torn JSON
  # (remove the deliberately-corrupted probe first — it served its test above)
  rm -f "$s/memory/facts/broken.json"
  for i in 1 2 3 4; do bash "$s/tools/extract_facts.sh" >/dev/null 2>&1 & done; wait
  o=$(python3 - "$s/memory/facts" <<'PY'
import json, os, sys
bad = []
for f in os.listdir(sys.argv[1]):
    if not f.endswith('.json'): continue
    try: json.load(open(os.path.join(sys.argv[1], f)))
    except Exception: bad.append(f)
print('CONC_OK' if not bad else 'CONC_BAD ' + ','.join(bad))
PY
)
  has "CONC_OK" "$o" && ok "4-way concurrent extraction: all facts still valid JSON" \
    || bad "concurrent extraction tore JSON: $o"
}

test_integration(){
  say "INTEGRATION (real tree + gates)"; local o h1 h2 t
  # the memory's core promise: baselines on disk == live extraction (drift vs
  # COMMITTED baselines is validate_docs check 5's job — a workspace with
  # legitimate uncommitted work must not turn this suite red)
  h1=$(facts_hash "$REAL")
  bash "$REAL/tools/extract_facts.sh" >/dev/null 2>&1
  h2=$(facts_hash "$REAL")
  [ "$h1" = "$h2" ] && ok "on-disk facts == live extraction (re-ingest is a no-op)" \
                    || bad "extraction changed on-disk facts — ingest or drift pending"
  # generated indexes in sync with facts (regen = content no-op)
  h1=$( (cd "$REAL" && cat playbooks.md llms.txt | shasum -a 256) )
  python3 "$REAL/tools/build_toc.py" >/dev/null 2>&1
  h2=$( (cd "$REAL" && cat playbooks.md llms.txt | shasum -a 256) )
  [ "$h1" = "$h2" ] && ok "playbooks.md + llms.txt in sync with facts (build_toc regen is a no-op)" \
                    || bad "build_toc regen changed the generated indexes"
  # fixity drift FIRES when a surface moves, then HEALS on regen
  local s="$SCRATCH/ifx"; mkdir -p "$s/tools" "$s/memory/facts"
  cp "$REAL/tools/extract_facts.sh" "$REAL/tools/gen_playbook.py" "$s/tools/"
  make_rich_kit "$s" alpha Alpha
  bash "$s/tools/extract_facts.sh" >/dev/null 2>&1
  python3 "$s/tools/gen_playbook.py" alpha >/dev/null 2>&1
  printf '\nclass AlphaLate {}\n' >> "$s/alpha/lib/src/service.dart"
  bash "$s/tools/extract_facts.sh" >/dev/null 2>&1
  t=$(mktemp); python3 "$s/tools/gen_playbook.py" alpha -o "$t" >/dev/null 2>&1
  if diff -q "$s/alpha/alpha_playbook.mdx" "$t" >/dev/null 2>&1; then
    bad "fixity blind: a new public symbol did NOT change the regen diff"
  else
    ok "fixity fires: surface change => regen differs from committed playbook"
  fi
  python3 "$s/tools/gen_playbook.py" alpha >/dev/null 2>&1
  python3 "$s/tools/gen_playbook.py" alpha -o "$t" >/dev/null 2>&1
  diff -q "$s/alpha/alpha_playbook.mdx" "$t" >/dev/null 2>&1 \
    && ok "drift heals: regen-in-place returns the tree to fixity-clean" \
    || bad "regen-in-place did not heal drift"
  rm -f "$t"
  # the composed gate: full validate_docs.sh (checks 1-5 incl. fixity) on the real tree
  o=$(run bash "$REAL/tools/validate_docs.sh")
  has "ALL CHECKS PASSED" "$o" && ok "validate_docs.sh full (incl. fixity) green on real tree" \
    || bad "validate_docs full failed: $(echo "$o" | grep -E 'FAIL|WARN' | head -5)"
}

test_e2e(){
  say "E2E (documented workflows, hermetic sandbox)"; local s o n t
  s=$(mkroot e2e)
  make_rich_kit "$s" alpha Alpha http path crypto
  make_rich_kit "$s" beta Beta http path crypto
  # the documented ingest workflow: extract -> gen_playbook -> build_toc
  bash "$s/tools/extract_facts.sh" >/dev/null 2>&1
  python3 "$s/tools/gen_playbook.py" alpha beta >/dev/null 2>&1
  python3 "$s/tools/build_toc.py" >/dev/null 2>&1
  o=$(run ls "$s/alpha/alpha_playbook.mdx" "$s/beta/beta_playbook.mdx" "$s/llms.txt" "$s/playbooks.md")
  has "exit:0" "$o" && ok "ingest produces playbooks + llms.txt + playbooks.md" \
                    || bad "ingest outputs missing: $o"
  grep -q "AlphaService" "$s/alpha/alpha_playbook.mdx" \
    && ok "generated playbook carries the kit's public symbols" \
    || bad "generated playbook missing AlphaService"
  n=$(grep -c 'TODO(prose)' "$s/alpha/alpha_playbook.mdx" "$s/beta/beta_playbook.mdx" | grep -c ':0' || true)
  [ "$n" -eq 2 ] && ok "rich README => zero TODO(prose) markers in generated playbooks" \
                 || bad "unexpected TODO(prose) markers in generated playbooks"
  { grep -q alpha "$s/llms.txt" && grep -q beta "$s/playbooks.md"; } \
    && ok "generated indexes list both kits" || bad "indexes missing kits"
  # fresh tree passes the full validator green (checks 1-5)
  o=$(run bash "$s/tools/validate_docs.sh")
  has "ALL CHECKS PASSED" "$o" && ok "fresh ingested tree: validate_docs.sh ALL CHECKS PASSED" \
    || bad "fresh tree validate failed: $(echo "$o" | tail -6)"
  # drift-and-heal through the REAL gate: surface change -> WARNs -> ingest+regen -> clean
  printf '\nclass AlphaLate {}\n' >> "$s/alpha/lib/src/service.dart"
  o=$(run bash "$s/tools/validate_docs.sh")
  { has "exit:0" "$o" && has "alpha facts drift" "$o" && has "alpha playbook drift" "$o"; } \
    && ok "gate surfaces drift as precise non-fatal WARNs (facts + playbook)" \
    || bad "drift not surfaced by validate_docs: $(echo "$o" | tail -8)"
  # the validator must NOT silently heal: baselines stay stale until the ingest workflow runs
  grep -q AlphaLate "$s/memory/facts/alpha.json" \
    && bad "validate_docs rewrote facts in place (silent heal)" \
    || ok "validator is read-only: stale baseline left for the ingest workflow"
  # the documented heal path: re-ingest (extract baselines) + regen playbook
  bash "$s/tools/extract_facts.sh" >/dev/null 2>&1
  python3 "$s/tools/gen_playbook.py" alpha >/dev/null 2>&1
  o=$(run bash "$s/tools/validate_docs.sh")
  { has "ALL CHECKS PASSED" "$o" && ! has "WARN:" "$o"; } \
    && ok "ingest + regen returns the gate to green (drift healed through the real path)" \
    || bad "heal failed: $(echo "$o" | tail -8)"
  # a broken extractor is a HARD gate failure, not a silent green
  chmod -x "$s/tools/extract_facts.sh"
  o=$(run bash "$s/tools/validate_docs.sh")
  { has "exit:1" "$o" && has "extract_facts.sh failed" "$o"; } \
    && ok "broken extractor: check 5 fails loud (exit 1), never silent" \
    || bad "extractor failure not hard-failed: $(echo "$o" | tail -6)"
  chmod +x "$s/tools/extract_facts.sh"
  # log-append discipline: conformant entry passes, malformed entry is flagged.
  # (Only `## [`-shaped lines are checked — a free-form line is invisible to a
  # header-format check by design; log.md is curated free text.)
  printf '# log\n## [2026-07-21] ingest | a conformant entry\n' > "$s/memory/log.md"
  n=$(logcheck "$s/memory/log.md")
  [ "$n" -eq 0 ] && ok "conformant log append passes the format check" \
                 || bad "conformant log entry flagged: $n"
  printf '## [2026-07-21] ingest missing the pipe separator\n' >> "$s/memory/log.md"
  n=$(logcheck "$s/memory/log.md")
  [ "$n" -eq 1 ] && ok "malformed log entry is flagged by the format check" \
                 || bad "malformed log entry slipped through: $n"
}

run_group(){ case "$1" in
  smoke) test_smoke;; pressure) test_pressure;;
  stress) test_stress;; integration) test_integration;;
  e2e) test_e2e;; *) ;;
esac; }

say "stacked_kit memory-system test suite"
if [ -n "$WANT" ]; then run_group "$WANT"; else
  for g in smoke pressure stress integration e2e; do run_group "$g"; done
fi

say "RESULT"
echo "passed=$PASS failed=$FAIL"
if [ "$FAIL" -gt 0 ]; then echo "FAILURES:"; printf '  - %s\n' "${FAILED[@]}"; exit 1; fi
echo "ALL GREEN"
