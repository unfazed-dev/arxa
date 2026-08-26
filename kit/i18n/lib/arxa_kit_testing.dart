/// Test doubles for arxa_kit_i18n.
///
/// Import this from tests to script the persisted override and assert on
/// store traffic:
///
/// ```dart
/// final store = FakeArxaKitLocaleStore();
/// store.queueReads(['pl']);
/// final i18n = ArxaKitI18n(store: store);
/// await i18n.load();
/// expect(i18n.bcp47, 'pl');
/// expect(store.readCalls, 1);
/// ```
library;

import 'src/arxa_kit_locale_store.dart';

export 'src/arxa_kit_i18n.dart';
export 'src/arxa_kit_language.dart';
export 'src/arxa_kit_locale_store.dart';

/// In-memory [ArxaKitLocaleStore] with a script queue for [read] results plus
/// call counts, so tests never touch platform channels.
class FakeArxaKitLocaleStore implements ArxaKitLocaleStore {
  final List<String?> _readQueue = [];

  /// Number of times [read] was invoked.
  int readCalls = 0;

  /// Number of times [write] was invoked.
  int writeCalls = 0;

  /// Number of times [clear] was invoked.
  int clearCalls = 0;

  /// The last tag passed to [write], or null after [clear] / never written.
  String? lastWritten;

  /// Queue results [read] returns, one per call (in order). When the queue is
  /// exhausted, [read] returns null.
  void queueReads(List<String?> results) => _readQueue.addAll(results);

  @override
  Future<String?> read() async {
    readCalls++;
    return _readQueue.isEmpty ? null : _readQueue.removeAt(0);
  }

  @override
  Future<void> write(String tag) async {
    writeCalls++;
    lastWritten = tag;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    lastWritten = null;
  }

  /// Clear the script queue, call counts, and [lastWritten] (reuse the same
  /// instance across cases).
  void reset() {
    _readQueue.clear();
    readCalls = 0;
    writeCalls = 0;
    clearCalls = 0;
    lastWritten = null;
  }
}
