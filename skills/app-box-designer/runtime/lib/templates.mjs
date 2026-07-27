import nunjucks from 'nunjucks';

// Templates render in two modes (ADR-0003):
//   'ui/views/.../home_view.html'        → full page
//   'ui/views/.../home_view.html#rows'   → Named Fragment: the `rows` macro in that file
// Macros take one argument: the context bag `c` (pages pass `c`; see helpers.render).
export function createTemplates(artifactDir) {
  const env = new nunjucks.Environment(
    new nunjucks.FileSystemLoader(artifactDir, { watch: false, noCache: false }),
    { autoescape: true, throwOnUndefined: false },
  );

  return {
    render(viewRef, ctx) {
      const hash = viewRef.indexOf('#');
      if (hash === -1) return env.render(viewRef, ctx);
      const file = viewRef.slice(0, hash);
      const macro = viewRef.slice(hash + 1);
      return env.renderString(`{% import "${file}" as f %}{{ f.${macro}(c) }}`, ctx);
    },
  };
}
