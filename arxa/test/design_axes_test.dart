// design_axes_test.dart — the axes plane's pure machinery: declaration
// parsing, precedence (override > published > shipped default), and the
// serve-time rewrite. The wire half (adapter, auth, SSE) lives in
// arxa_dial_serve_test.dart; the pixels are the lens's job.
import 'package:arxa/design_axes.dart';
import 'package:test/test.dart';

const _page = '<!doctype html><html lang="en" data-axes-themes="system light dark">'
    '<head><link rel="stylesheet" href="/a.css" data-axes-style="glass">'
    '<link rel="stylesheet" href="/b.css" data-axes-style="m3e" disabled>'
    '<link rel="stylesheet" href="/c.css" data-axes-style="shadcn" disabled="disabled">'
    '</head><body>x</body></html>';

void main() {
  test('parses the declaration: order, default, themes', () {
    final decl = parseAxesDeclaration(_page)!;
    expect(decl.styles, ['glass', 'm3e', 'shadcn']);
    expect(decl.defaultStyle, 'glass');
    expect(decl.themes, ['system', 'light', 'dark']);
  });

  test('no declaration means no axes', () {
    expect(parseAxesDeclaration('<html><head></head><body></body></html>'), isNull);
    expect(
        applyAxesToServedHtml('<html><head></head><body></body></html>',
            query: {}, stored: null),
        isNull);
  });

  test('default serve: shipped default enabled, system strips data-theme', () {
    final served = applyAxesToServedHtml(_page, query: {}, stored: null)!;
    expect(served.active, const AxesPick(style: 'glass', theme: 'system'));
    expect(served.published, served.active);
    expect(served.html, contains('data-axes-style="glass">'));
    expect(served.html, contains('data-axes-style="m3e" disabled>'));
    expect(served.html, contains('data-axes-style="shadcn" disabled>'));
    expect(served.html, isNot(contains('data-theme')));
  });

  test('stored pick publishes and renders', () {
    final served = applyAxesToServedHtml(_page,
        query: {}, stored: const AxesPick(style: 'shadcn', theme: 'dark'))!;
    expect(served.active, const AxesPick(style: 'shadcn', theme: 'dark'));
    expect(served.published, served.active);
    expect(served.html, contains('data-axes-style="glass" disabled>'));
    expect(served.html, contains('data-axes-style="shadcn">'));
    expect(served.html, contains('data-theme="dark"'));
  });

  test('query override beats stored, marks previewing', () {
    final served = applyAxesToServedHtml(_page,
        query: const {'style': 'm3e', 'theme': 'light'},
        stored: const AxesPick(style: 'shadcn', theme: 'dark'))!;
    expect(served.active, const AxesPick(style: 'm3e', theme: 'light'));
    expect(served.published, const AxesPick(style: 'shadcn', theme: 'dark'));
    expect(served.config['active'], {'style': 'm3e', 'theme': 'light'});
    expect(served.config['published'], {'style': 'shadcn', 'theme': 'dark'});
    expect(served.html, contains('data-theme="light"'));
  });

  test('invalid or undeclared values fall through silently', () {
    final served = applyAxesToServedHtml(_page,
        query: const {'style': 'neon-noir', 'theme': 'sepia'},
        stored: const AxesPick(style: 'm3e', theme: 'light'))!;
    expect(served.active, const AxesPick(style: 'm3e', theme: 'light'));
  });

  test('a stored style the artifact dropped falls back to the default', () {
    final served = applyAxesToServedHtml(_page,
        query: {}, stored: const AxesPick(style: 'retro', theme: 'dark'))!;
    expect(served.active.style, 'glass');
    expect(served.active.theme, 'dark');
  });

  test('rewrite is idempotent for a stable pick', () {
    final first = applyAxesToServedHtml(_page, query: const {'style': 'm3e'},
        stored: const AxesPick(style: 'shadcn', theme: 'dark'))!;
    final again = applyAxesToServedHtml(first.html,
        query: const {'style': 'm3e'},
        stored: const AxesPick(style: 'shadcn', theme: 'dark'))!;
    expect(again.html, first.html);
  });

  test('system override strips data-theme even when stored set one', () {
    final served = applyAxesToServedHtml('<html data-axes-themes="system light" data-theme="dark"><head><link rel="stylesheet" href="/a.css" data-axes-style="glass"></head><body></body></html>',
        query: const {'theme': 'system'},
        stored: const AxesPick(style: 'glass', theme: 'dark'))!;
    expect(served.html, isNot(contains('data-theme')));
  });

  test('no theme declaration means data-theme is never set', () {
    final served = applyAxesToServedHtml(
        '<html><head><link rel="stylesheet" href="/a.css" data-axes-style="glass"></head><body></body></html>',
        query: const {'theme': 'dark'}, stored: null)!;
    expect(served.html, isNot(contains('data-theme')));
  });
}
