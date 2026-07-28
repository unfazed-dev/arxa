import 'package:appbox/security/prototype/last_render_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LastRenderStore store;

  setUp(() => store = LastRenderStore());

  test('starts empty', () {
    expect(store.hasRender, false);
    expect(store.lastUrl, isNull);
  });

  test('serve records a render and notifies', () {
    var notified = 0;
    store.addListener(() => notified++);
    store.serve('http://127.0.0.1:1/');
    expect(store.hasRender, true);
    expect(store.lastUrl, 'http://127.0.0.1:1/');
    expect(store.loadedAt, isNotNull);
    expect(notified, 1);
  });

  test('clear drops the render', () {
    store.serve('http://127.0.0.1:1/');
    store.clear();
    expect(store.hasRender, false);
    expect(store.lastUrl, isNull);
  });

  // The defining invariant: there is no public way to clear the render "on
  // channel death". The store only changes on a new serve or an explicit
  // clear() (leaving the view / stop server). A dead server leaves the render
  // in place — proven jointly in fab_dead_while_render_persists_test.
  test('exposes no death-triggered clear (the API shape itself)', () {
    store.serve('http://127.0.0.1:1/');
    // Simulate "channel died" — there is nothing to call; the render stays.
    expect(store.lastUrl, 'http://127.0.0.1:1/');
  });
}
