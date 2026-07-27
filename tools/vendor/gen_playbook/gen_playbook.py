#!/usr/bin/env python3
"""gen_playbook.py — render a per-kit <kit>_playbook.mdx from its fact JSON + README.

Produces a comprehensive, valid visual-plan MDX playbook that lets a human or LLM
use, wire, and extend the kit without reading its source. Mechanical sections (API
table, integration map, features checklist) come from memory/facts/<kit>.json;
narrative sections are mined from the kit's README and mapped by header. Any
section without a source emits a <!-- TODO(prose): ... --> marker for the prose pass.

Usage: gen_playbook.py <kit> [<kit> ...]     # writes <stacked_kit>/<kit>/<kit>_playbook.mdx
Env:   KIT_FACTS_DIR — read facts from here instead of memory/facts (read-only
       regen against a live tempdir extraction; validate_docs.sh check 5)
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # stacked_kit/
# Facts source: committed baselines by default; KIT_FACTS_DIR overrides (used by
# validate_docs.sh to regen against a LIVE tempdir extraction, read-only).
FACTS_DIR = os.environ.get('KIT_FACTS_DIR') or os.path.join(ROOT, 'memory', 'facts')

def load_fact(kit):
    with open(os.path.join(FACTS_DIR, f'{kit}.json')) as f:
        return json.load(f)

def read_readme(kit):
    """Return (intro, {header: body_lines})."""
    p = os.path.join(ROOT, kit, 'README.md')
    if not os.path.isfile(p):
        return '', {}, []
    lines = open(p).read().split('\n')
    intro, secs, cur, hdrs = [], {}, None, []
    for ln in lines:
        m = re.match(r'^(#{1,6})\s+(.*)', ln)
        if m and len(m.group(1)) <= 2:
            cur = m.group(2).strip()
            secs[cur] = []
            hdrs.append(cur)
        elif cur is None:
            intro.append(ln)
        else:
            secs[cur].append(ln)
    # promote first header's role if intro is just the title
    intro_t = '\n'.join(intro).strip()
    return intro_t, secs, hdrs

def find_section(secs, hdrs, *needles):
    for h in hdrs:
        hl = h.lower()
        if any(n in hl for n in needles):
            return '\n'.join(secs[h]).strip()
    return ''

def md_escape_table(s):
    return s.replace('\\','\\\\').replace('"','\\"')

def table(rows, columns, block_id):
    """Render a <Table> block. rows: list of list-of-str; columns: list-of-str."""
    cols_json = json.dumps(columns)
    rows_json = json.dumps(rows)
    return f'<Table id="{block_id}" columns={{{cols_json}}} rows={{{rows_json}}} />'

def checklist(items, block_id):
    """items: list of (id, label[, note])."""
    objs = []
    for it in items:
        obj = {'id': it[0], 'label': it[1]}
        if len(it) > 2 and it[2]:
            obj['note'] = it[2]
        objs.append(obj)
    return f'<Checklist id="{block_id}" items={{{json.dumps(objs)}}} />'

def qform(kit):
    return (
        f'<QuestionForm id="open-questions" questions={{[\n'
        f'  {{\n'
        f'    id: "q-{kit}-gaps",\n'
        f'    title: "What is unclear or missing from this playbook?",\n'
        f'    mode: "freeform",\n'
        f'    placeholder: "Note anything a new contributor or agent would need that is not covered above.",\n'
        f'  }},\n'
        f']}} />'
    )

def split_surface(syms):
    api, test = [], []
    for s in syms:
        (test if (s['file'] == 'testing.dart' or s['name'].startswith(('Fake', 'Recording', 'Scripted', 'Stub'))) else api).append(s)
    return api, test

# Lines that terminate a narrative section (the next block is mechanical, not prose).
_PROSE_BOUNDARY = ('<!-- kb:begin', '<!-- kb:end', '<QuestionForm')

def existing_sections(path):
    """{title: stripped_body} for each '### Title' section (for prose-preserving
    regen). Fence-aware: '### ' in a ``` block is not a header; a body stops at the
    next header or a kb/QuestionForm boundary. {} if no playbook yet."""
    if not os.path.isfile(path):
        return {}
    lines = open(path).read().split('\n')
    secs, cur, buf, in_fence = {}, None, [], False
    for ln in lines:
        if ln.lstrip().startswith('```'):
            in_fence = not in_fence
            if cur is not None:
                buf.append(ln)
            continue
        if not in_fence and ln.startswith('### '):
            if cur is not None:
                secs[cur] = '\n'.join(buf).strip()
            cur, buf = ln[4:].strip(), []
        elif cur is not None:
            if any(ln.startswith(b) for b in _PROSE_BOUNDARY):
                secs[cur] = '\n'.join(buf).strip()
                cur, buf = None, []
            else:
                buf.append(ln)
    if cur is not None:
        secs[cur] = '\n'.join(buf).strip()
    return secs

def prose_for(title, default_body, existing):
    """Existing narrative prose if present + non-TODO, else the generated default."""
    body = existing.get(title, '')
    if body and 'TODO(prose)' not in body:
        return body
    return default_body

def render(kit):
    fact = load_fact(kit)
    name = fact['name']
    intro, secs, hdrs = read_readme(kit)
    if not intro:
        intro = fact.get('readmeFirst') or name
    desc = fact.get('description') or ''
    api, test = split_surface(fact.get('publicSurface', []))
    ex = existing_sections(os.path.join(ROOT, kit, f'{kit}_playbook.mdx'))  # prose-preserving regen

    overview_parts = []
    if desc:
        overview_parts.append(desc)
    intro_s = intro.strip()
    title_like = {name, fact.get('readmeFirst', ''), f'# {name}', f'# {name} '}
    if intro_s and intro_s not in title_like and not intro_s.startswith('#'):
        overview_parts.append(intro_s)
    overview = '\n\n'.join(overview_parts)
    scope = find_section(secs, hdrs, 'scope')
    usage = find_section(secs, hdrs, 'usage', 'quick start', 'example', 'examples')
    wiring = find_section(secs, hdrs, 'setup', 'install', 'wiring', 'registration', 'register')
    arch = find_section(secs, hdrs, 'architecture', 'dependency direction', 'design', 'layer')
    gotchas = find_section(secs, hdrs, 'gotcha', 'caveat', 'known issue', 'note', 'notes', 'platform', 'maintenance', 'native')
    testing = find_section(secs, hdrs, 'testing', 'test')
    decisions = find_section(secs, hdrs, 'decision', 'adr', 'rationale')

    api_rows = [[s['name'], s['kind'], s['file']] for s in api] or [['—', '—', 'no public symbols extracted']]
    api_table = table(api_rows, ['Symbol', 'Kind', 'Defined in'], f'{kit}-api')
    test_md = ''
    if test:
        test_md = '\n\nTest doubles in `lib/testing.dart`: ' + ', '.join(f'`{s["name"]}`' for s in test) + '.'
    if fact.get('hasTesting'):
        test_md += '\n\nScripts and call-counts — tests never touch platform channels.'

    integ_rows = [[
        ', '.join(fact.get('frameworkDeps', [])) or '—',
        ', '.join(fact.get('backingPackages', [])) or '— (SDK only / pure Dart)',
        ', '.join(fact.get('kitDeps', [])) or '— (standalone)',
    ]]
    integ_table = table(integ_rows, ['Stacked framework deps', 'Backing SDK packages', 'Depends on (kit)'], f'{kit}-integration')

    feat_items = [(f'{kit}-feat-{i}', f'`{s["name"]}` — {s["kind"]}') for i, s in enumerate(api[:12])]
    if not feat_items:
        feat_items = [(f'{kit}-feat-0', 'See README for the feature list')]
    feats = checklist(feat_items, f'{kit}-features')

    def block(title, body, fallback_todo):
        body = body.strip()
        if body:
            return f'\n### {title}\n\n{body}\n'
        return f'\n### {title}\n\n<!-- TODO(prose): {fallback_todo} -->\n'

    out = []
    out.append(f'<Callout id="header" tone="info">\n')
    out.append(f'# {name} — Per-Package Playbook\n\n')
    out.append(f'`{name}` v**{fact.get("version","?")}** · `publish_to: \'none\'` · status: **active**\n\n')
    out.append(f'**Role (one line):** {desc.split(".")[0] if desc else (fact.get("readmeFirst") or name)}.\n\n')
    out.append(f'**Scope of this document:** lets a human OR an LLM use, wire, and extend `{name}` **without reading its source**. '
               f'The public surface below was extracted from the barrel; README content is folded into the narrative sections.\n\n')
    out.append('## Table of contents\n\n0. Header & TOC — *you are here* · 1. Overview & role · 2. Public surface · '
               '3. Usage & wiring · 4. Integration map · 5. Architecture · 6. Gotchas · 7. Testing · '
               '8. Features · 9. Decisions · 10. References · 11. Open questions\n\n')
    out.append('</Callout>\n')
    out.append(block('Overview & role', prose_for('Overview & role', overview, ex), f'summarize what {name} does and when to reach for it, from the barrel doc comment and README intro'))
    out.append(block('Public surface', f'Exported from `lib/{name}.dart`:\n\n{api_table}{test_md}',
                     f'document each exported symbol’s purpose from its doc comment'))
    out.append(block('Usage & wiring', prose_for('Usage & wiring', '\n\n'.join(p for p in [usage, wiring] if p), ex),
                     f'show install + registration (locator/StackedApp) + a minimal usage snippet, from the README Usage/Setup sections'))
    out.append(block('Integration map', f'{integ_table}\n\nSee `kit_matrix.md` for the full routing + dependency graph.', 'annotate the integration map'))
    out.append(block('Architecture', prose_for('Architecture', arch, ex), f'describe the port/adapter or service structure and dependency direction of {name}'))
    out.append(block('Gotchas', prose_for('Gotchas', gotchas, ex), f'list platform setup (native permissions/manifest keys), maintenance risks, and known pitfalls from the README'))
    out.append(block('Testing', prose_for('Testing', testing or (f'`{name}` ships `lib/testing.dart`.' if fact.get("hasTesting") else ''), ex),
                     f'explain the test seam: how fakes are scripted and what call-counts are asserted'))
    out.append(block('Features', feats, 'annotate the feature checklist'))
    out.append(block('Decisions / ADRs', prose_for('Decisions / ADRs', decisions, ex), f'record why {name} chose its backing packages / standalone stance, from the README and kit_matrix decisions log'))
    out.append('<!-- kb:begin -->\n### References\n<!-- kb:end -->\n')
    out.append(qform(kit))
    out.append('\n')
    return '\n'.join(out)

def main():
    args = sys.argv[1:]
    out_override = None
    kits = []
    i = 0
    while i < len(args):
        if args[i] == '-o' and i + 1 < len(args):
            out_override = args[i + 1]; i += 2      # -o PATH: write elsewhere (fixity check), prose still read from the canonical path
        else:
            kits.append(args[i]); i += 1
    if not kits:
        print('usage: gen_playbook.py [-o PATH] <kit> [<kit> ...]', file=sys.stderr); sys.exit(2)
    for kit in kits:
        try:
            mdx = render(kit)
        except FileNotFoundError as e:
            print(f'  skip {kit}: {e}'); continue
        outp = out_override or os.path.join(ROOT, kit, f'{kit}_playbook.mdx')
        with open(outp, 'w') as f:
            f.write(mdx)
        todos = mdx.count('TODO(prose)')
        print(f'  {kit}: wrote {outp} ({len(mdx.splitlines())}L, {todos} prose TODOs)')

if __name__ == '__main__':
    main()
