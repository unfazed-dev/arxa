// FilesRepository — the fixture file bodies behind the Files activity views.
// Locale-neutral: code, docs and assets read the same in every locale. The
// productionize swap (a real FS/DB read) happens behind this seam — the
// seeds own the file LISTS, this repository owns the file CONTENT.
// Text modes carry an inline body; binary modes carry a served asset src.

const BRIEF_MD = `# Petal & Stem — design brief

Hand-tied bouquets, same day. The client runs a two-person flower studio and
needs a shop that feels like the studio: warm, quick, unhurried.

## Releases

- **R1 Dogfood** — browse, cart, checkout, confirmation.
- **R2 Anywhere** — occasions, delivery windows, order lookup.

## Surfaces

The surface inventory is the traceability source: every registry surface
traces to a row here, and the registry is seeded from it.
`;

const STORY_MAP_JSON = `{
  "project": "petal-and-stem",
  "epics": [
    { "id": "shop", "features": [
      { "id": "browse", "stories": [
        { "id": "s-1", "name": "Browse bouquets", "priority": "must", "release": "R1 Dogfood" },
        { "id": "s-2", "name": "Filter by occasion", "priority": "should", "release": "R2 Anywhere" }
      ] }
    ] }
  ]
}
`;

const STORY_MAP_HTML = `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Petal &amp; Stem — story map</title></head>
<body>
  <h1>Story map</h1>
  <p>Epic → Feature → Story, MoSCoW priorities, release swimlanes.</p>
</body>
</html>
`;

const MOODBOARD_MD = `# Moodboard — builders & pipeline

What to steal from the gathered references.

- **Dreamflow** — tri-surface editor: agent chat, visual canvas, code in
  live sync. Steal the tri-pane, keep our composer panel single-state.
- **Linear** — features page: restrained colour, generous whitespace.
`;

const STRUCTURE_JSON = `{
  "$schema": "appbox/structure@1",
  "registry": "models/screens_model/registry.json",
  "screens": []
}
`;

const RUN_JSON = `{
  "run": 7,
  "policy": { "stopOnRed": true, "escLimit": 3, "rungs": ["390", "744", "1280"] }
}
`;

const DART_VIEW = `class LoopView extends StackedView<LoopViewModel> {
  const LoopView({super.key});

  @override
  Widget builder(BuildContext context, LoopViewModel vm, Widget? child) {
    return PanelScaffold(
      activity: ActivityPanel(vm.activityView),
      main: MainPanel(vm.artifact),
      composer: ComposerPanel(vm.thread),
    );
  }
}
`;

const DART_TEST = `void main() {
  testWidgets('loop renders the three panels', (tester) async {
    await tester.pumpWidget(const LoopView());
    expect(find.byType(ActivityPanel), findsOneWidget);
    expect(find.byType(MainPanel), findsOneWidget);
    expect(find.byType(ComposerPanel), findsOneWidget);
  });
}
`;

const DESIGN_SEED_JSON = `{
  "surfaces": 11,
  "rungs": [390, 744, 1280],
  "kit": 82
}
`;

const FILES = {
  // intake seed list
  'docs/design/brief.md': { body: BRIEF_MD },
  'docs/design/story-map.json': { body: STORY_MAP_JSON },
  'docs/design/story_map.html': { body: STORY_MAP_HTML },
  'docs/moodboards/ai-builders-and-flows-canvas.md': { body: MOODBOARD_MD },
  'docs/moodboards/builder-and-pipeline.md': { body: MOODBOARD_MD },
  'docs/moodboards/companion-and-macos-polish.md': { body: MOODBOARD_MD },
  'docs/moodboards/shots/dreamflow__tri-surface.png': { src: '/assets/images/moodboard/builders/dreamflow__tri-surface.png' },
  'docs/moodboards/shots/linear__features.png': { src: '/assets/images/moodboard/pipeline/linear__features.png' },
  'docs/moodboards/shots/dreamflow__walkthrough.mp4': { src: '/assets/files/walkthrough.mp4' },
  'docs/design/flows.svg': { src: '/assets/files/flows.svg' },
  'docs/design/brief.pdf': { src: '/assets/files/brief.pdf' },
  // design seed list
  'designs/appbox-studio/models/design_model/design_seed.en.json': { body: DESIGN_SEED_JSON },
  'designs/appbox-studio/models/design_model/run.json': { body: RUN_JSON },
  'app/structure.json': { body: STRUCTURE_JSON },
  // build seed list
  'app/lib/ui/views/build/loop_view.dart': { body: DART_VIEW },
  'app/test/ui/views/build/loop_viewmodel_test.dart': { body: DART_TEST },
  'app/lib/ui/views/intake/mapping_view.dart': { body: DART_VIEW },
  'app/lib/ui/views/design/chat_view.dart': { body: DART_VIEW },
  'app/lib/ui/views/access/pairing_view.dart': { body: DART_VIEW },
  'designs/frozen/build.loop/expanded.png': { src: '/assets/images/variant-comparison/focus-expanded.png' },
  'docs/structure.json': { body: STRUCTURE_JSON },
};

// { body } for text modes, { src } for binary modes; null when the path has
// no fixture content (the row renders inert — honest over invented).
export const read = (path) => FILES[path] ?? null;
