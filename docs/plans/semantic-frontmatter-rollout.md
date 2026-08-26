# Plan — arxa file structure (semantic frontmatter + locked sections)

**Status:** confirmed with owner 2026-08-07; implementation is delegated.
**Pilot (reference, DONE):** `kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart` — treat it as the living example; do not restyle it.
**Remaining pilots:** `kit/showcase_app/lib/services/showcase_notes_services/facades/showcase_notes_facade_service.dart`, `.../adapters/showcase_notes_media_adapter_service.dart`, `.../repositories/showcase_notes_repository_service.dart`.

## The spine (every covered file, in this order)

Library doc comment (`///`) above `library;`, containing:

1. **Layer intro** — what this *kind* of file is, in flow vocabulary. For a
   viewmodel: actions in, streams out, never touches the view. Per-layer
   variants use the same data-flow framing.
2. **Plain paragraph** — opens with the file's role in plain terms, then what
   it does for an average human. Role names are fixed:
   - view → `This is the user interface for …`
   - viewmodel → `This is the business logic for …`
   - facade → `This is the front door for …`
   - adapter → `This is the bridge to the device for …`
   - repository → `This is the store for …`
3. **Requirements** — numbered list. Format: `N. [Name] — story-id(s)` on one
   line, one plain sentence on the next. `[Name]` brackets are mandatory;
   multiple stories separated by ` / `. The story-id tail appears ONLY when a
   real story in `map.json` covers it — never invent citations (startup/infra
   files list requirements story-free).
4. **Relationships** — ASCII diagram per the fixed grammar below, then the
   column inventory.
5. **History** — `History: git log --follow -- <repo-relative path>`.

Then `library;`, then imports, then the class.

## Body sections (locked order per kind, `// ── Name ──` separators)

- **viewmodel**: Setup / Initial state / Streams / Commands / Actions /
  Side effects / Cleanup. The Commands section carries the sentence
  `// Commands decide when — and whether — Actions run.`
- **facade**: Setup / Initial state / Streams / Writes / Reads / Cleanup
  (every write is a `mutate` op).
- **adapter**: Setup / Initial state / Streams / Actions / Cleanup.
- **repository**: Setup / Reads / Writes / Cleanup.
- **views/widgets**: same spine frontmatter; body sections follow the file's
  natural build order (no invented sections).

**Empty sections are omitted** (a VM with no hub commands has no Commands
section; the sentence appears only where the section exists).

Inline comment style: `/// [N. Requirement name] One short sentence.` citing
the requirement from the frontmatter; the code carries the rest. Comments
support the code, never restate it.

## Diagram grammar (fixed — review-enforced, not negotiable per file)

- Boxes `┌──┐ │ │ └──┘`, label centered with one-space padding.
- The file's own box is centered; every tier above/below center-aligns to it.
- Arrows between tiers: `ACT ▼` (actions down) / `▲ STRM` (streams up), tips
  touching box edges, each with a connecting line.
- Numbered ranges `[1-13]` sit centered under their **labels** (not boxes).
- Last diagram line: `════════ abxAction ════════` rail, bare, no caption.
- Below the diagram, the column inventory: `streams (STRM)` / `actions (ACT)`
  / `commands (CMD)` — numbered items, one kind per column, aligned; numbers
  match the diagram ranges.

## Plain-language canon (every prose `///` block, measured from the pilot)

The pilot VM is the measuring stick; these numbers are taken from it.

- **Frontmatter paragraphs** (intro, plain paragraph): ≤ 6 comment lines each.
- **Class doc comments: none.** The frontmatter speaks for the class — a
  class-level `///` block repeating it is a violation. (One plain sentence
  allowed for a secondary class in the same file.)
- **Member docs**: `/// [N. Requirement name] One plain sentence.` — ≤ 2
  lines, the citation first.
- **Vocabulary**: user-visible behavior in plain present-tense verbs ("Pins
  or unpins the note", "Where an attachment's file lives"). No API type
  names, no framework talk, no jargon in prose. Technical refs only in
  backticks and only when load-bearing (route paths, flag/operator names
  like `take(1)`).
- **Banned-token seed list** (gate-enforced, extend as found): paradigm,
  leverage, utilize, facilitate(s), abstraction, boilerplate, wrapper,
  self-contained — plus Flutter/stacked API symbols named in prose:
  PreferredSizeWidget, NestedRouter, IndexedStack, StatelessWidget,
  StatefulWidget, BuildContext, Scaffold, PreferredSizeWidget.
- **Exempt zones**: requirement lines, the ```text diagram, the inventory
  columns, the History line, `//` code comments, and backticked spans.

## Coverage (blast radius)

- **Full spine**: views, viewmodels, facades, adapters, repositories, widgets.
- **Light variant** (role paragraph + field-purpose comments, no diagram):
  models.
- **Exempt**: enum files (one-line doc), tests (story-ids live in test names
  per behavior-TDD canon).

## Rollout (strict order)

1. **Facade pilot** — apply to `showcase_notes_facade_service.dart`; STOP for
   owner review before continuing.
2. **Adapter + repository pilots** — after owner approves the facade.
3. **Canon spec** — add the full grammar (this doc's spine, sections, diagram
   rules, requirement format) to `skills/arxa-builder/BUILDER_playbook.mdx`;
   one bullet in `skills/arxa-builder/SKILL.md`; reference section in
   `kit/showcase_app/PLAYBOOK.md`.
4. **Showcase sweep** — all remaining views/VMs/services/widgets in
   `kit/showcase_app/lib`, fanned out to subagents per shell. The prose sweep
   (G13-language violations) rides along in the same pass — one sweep, not
   two.
5. **G13 light gate** — `arxa/lib/arch_guard.dart` + tests. Mechanical
   checks ONLY: frontmatter block + `library;` present; the five spine parts
   in order; requirement lines match `N. [Name]( — story-ids)?`; section
   separators present in the locked order for the file kind. Diagram geometry
   stays a review rule. Land after the sweep so the gate is born green.
   **G13-language (lands first, drives the prose sweep):** the plain-language
   canon above, checked mechanically — paragraph/member-doc line caps,
   no class doc above a frontmatter-covered class, banned tokens outside
   backticks and exempt zones. Run against covered dirs to LIST violations;
   the sweep fixes what it reports.
6. **Scaffolder** — `skills/arxa-scaffolder` templates emit the structure
   for new apps.

## Verification (every step)

- `cd kit/showcase_app && dart analyze lib test` — zero issues
- `cd kit/showcase_app && flutter test` — all green (baseline 111)
- after G13: `cd arxa && dart test test/arch_guard_test.dart` and
  `dart run bin/arxa.dart gate arch --target ../kit/showcase_app` — PASS
