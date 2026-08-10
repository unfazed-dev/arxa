import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Caches one async resolution per [State] so it survives parent rebuilds.
///
/// ## Why this exists
///
/// The components in this package used to build their `future:` argument
/// inside `build()`:
///
/// ```dart
/// return FutureBuilder<IconSource?>(
///   future: resolveIconSource(...),   // new Future on EVERY build
///   builder: ...,
/// );
/// ```
///
/// `FutureBuilder` compares futures by identity, so every parent rebuild
/// re-subscribed and kicked off a completely fresh resolution. Measured cost
/// on the asset branch: two `rootBundle.load` round-trips per parent rebuild,
/// unbounded. On the `customIcon` branch it is a full
/// `PictureRecorder -> toImage -> toByteData` rasterization on the main
/// isolate. Each completion then fires a `setState`, so every parent rebuild
/// also bought a second, redundant subtree rebuild. During a scroll or a
/// route animation that is per-frame raster work.
///
/// (For the record, because the plan document claims otherwise: this did
/// *not* tear the subtree down. Flutter's `_FutureBuilderState`
/// `didUpdateWidget` does `_snapshot.inState(ConnectionState.none)`, and
/// `AsyncSnapshot.inState` preserves `data`, so `hasData` stayed true and the
/// placeholder branch was never taken on a rebuild. The waste was real; the
/// teardown was not.)
///
/// ## Contract
///
/// Implementers supply two things:
///
/// - [resolutionKey] — a **value-equal** digest of every input the resolution
///   depends on. Dart records (`(a, b, c)`) have structural equality and are
///   the intended shape. Return `null` when the current configuration needs
///   no async resolution. Do not put freshly-allocated collections in the key
///   (they compare by identity, so the guard would never hit and you would
///   re-resolve forever, i.e. the exact bug this class removes).
/// - [resolveValue] — performs the resolution. It runs after
///   `didChangeDependencies`, so reading inherited widgets from `context` is
///   safe.
///
/// Call [syncResolution] from `didChangeDependencies` and `didUpdateWidget`.
/// It is deliberately *not* wired into those lifecycle hooks by the mixin, so
/// that each component's ordering against its own native-sync logic stays
/// visible at the call site.
///
/// ## The invariant that matters
///
/// [resolvedValue] is **never cleared**. While a re-resolve is in flight the
/// previous value stays put, and a resolution that completes with `null` is
/// dropped rather than latched. That preservation used to come for free from
/// `FutureBuilder`'s snapshot handling; once a component owns its own cache
/// it becomes this class's job. Clearing it before re-resolving would
/// introduce a genuine placeholder flash where there was none. The
/// placeholder is legitimate on first mount only.
mixin AsyncResolutionState<W extends StatefulWidget, T extends Object>
    on State<W> {
  Object? _resolutionKey;
  bool _hasResolvedOnce = false;
  T? _resolvedValue;
  int _resolutionGeneration = 0;

  /// Value-equal digest of the inputs [resolveValue] depends on, or `null`
  /// when the current configuration needs no async resolution.
  @protected
  Object? resolutionKey();

  /// Performs the async resolution for the current configuration.
  ///
  /// Runs after `didChangeDependencies`, so `context` may be used for
  /// inherited lookups. Returning `null` leaves the cached value untouched.
  @protected
  Future<T?> resolveValue();

  /// The last successfully resolved value, or `null` before the first one
  /// lands. Never reset to `null` afterwards.
  @protected
  T? get resolvedValue => _resolvedValue;

  /// Re-resolves if and only if [resolutionKey] changed since the last call.
  ///
  /// Safe to call on every `didChangeDependencies` — an unrelated
  /// `MediaQuery` or theme change leaves the key equal and is a true no-op:
  /// no future is started and no `setState` is scheduled.
  @protected
  void syncResolution() {
    final key = resolutionKey();
    if (_hasResolvedOnce && _resolutionKey == key) return;
    _hasResolvedOnce = true;
    _resolutionKey = key;

    // Bump unconditionally so any in-flight resolution for the previous key
    // is discarded when it lands, even if the new key needs no resolution.
    final token = ++_resolutionGeneration;
    if (key == null) return;

    resolveValue().then(
      (resolved) {
        if (token != _resolutionGeneration || !mounted) return;
        // Keep the last-good value rather than collapsing to a placeholder.
        if (resolved == null || identical(_resolvedValue, resolved)) return;
        setState(() {
          _resolvedValue = resolved;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        // Swallowing is intentional — a failed icon resolution must not take
        // the frame down, and the last-good value stays on screen. But do not
        // swallow it *silently*: an undiagnosable resolution failure is how
        // this class becomes unmaintainable.
        if (kDebugMode) {
          debugPrint(
            '[cupertino_native_better] icon resolution failed for '
            '$runtimeType: $error',
          );
        }
      },
    );
  }
}
