# hello-hda (example artifact)

A minimal HDA artifact (templates, viewmodels, fixtures, assets) used to
exercise the designer pipeline.

## Serving

```sh
arxa design serve examples/hello-hda
```

The former `serve.mjs` node runtime was archived to
`archives/tooling-pre-dart/skills-pre-dart/arxa-designer/` — serving is now
the Dart `arxa design serve` command (the Task 20 `DesignServer`).

## Fixtures

The fixture files (`*_fixtures.<locale>.json`) are authored by hand from the
matching `*_seed.<locale>.json` sources; the `seed → fixtures` generator that
wrote `_generated_from` was a node script (`generate.mjs`, now archived under
`archives/tooling-pre-dart/skills-pre-dart/arxa-designer/examples-hello-hda-generate.mjs`).
That archived script is the reference if a Dart fixture-generator is ever
re-added as a designer authoring step.
