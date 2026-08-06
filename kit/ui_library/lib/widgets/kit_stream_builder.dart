import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart' show ValueStream;

import 'kit_native_loading_indicator.dart';

/// Thin [StreamBuilder] wrapper with rxdart-aware initial-data resolution.
///
/// If [initialData] isn't given and [stream] is a [ValueStream] (e.g. a
/// `BehaviorSubject`), its current [ValueStream.valueOrNull] seeds the first
/// build — no loading flash for already-seeded streams. Also shares default
/// loading/error UI so views don't hand-roll it per stream.
///
/// Nullability: once the stream is active (first event received), `null` is
/// treated as a real value and passed to [builder] — the loading state is
/// only "no seed and no event yet". This is what makes nullable streams
/// (`Stream<Thing?>`, e.g. role-gated data that emits null on purpose)
/// bindable without an infinite spinner.
///
/// This is the kit's ONE view-binding convention (streams-only views): views
/// bind facade/viewmodel streams with [KitStreamBuilder] and never render
/// from `notifyListeners` relay fields. It is a convenience wrapper over
/// Flutter's stock [StreamBuilder], not a replacement for stacked's own
/// primitives. When to use what:
/// - **[KitStreamBuilder]** — displaying one or more kit-data streams in a
///   view's body, where each stream should rebuild its own subtree
///   independently.
/// - **stacked's `StreamViewModel<T>`** — avoided in kit apps: it rebuilds
///   the whole view via `notifyListeners` per emission and covers one stream
///   only; expose the stream from the viewmodel and bind it here instead.
/// - Avoid stacked's `MultipleStreamViewModel` — its stringly-keyed stream
///   data map isn't type-safe.
class KitStreamBuilder<T> extends StatelessWidget {
  const KitStreamBuilder({
    super.key,
    required this.stream,
    this.initialData,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final Stream<T> stream;
  final T? initialData;
  final Widget Function(BuildContext context, T data) builder;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final valueStream = stream is ValueStream<T> ? stream as ValueStream<T> : null;
    // hasValue, not valueOrNull: a seeded-null BehaviorSubject HAS a value
    // (null is the data), valueOrNull can't tell the two apart.
    final hasSeed = initialData != null || (valueStream?.hasValue ?? false);
    final seed = initialData ?? valueStream?.valueOrNull;

    return StreamBuilder<T>(
      stream: stream,
      initialData: seed,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return errorBuilder?.call(context, snapshot.error!) ??
              // ponytail: "minimal unobtrusive default" per spec — render
              // nothing rather than guess at error UI hosts didn't ask for.
              const SizedBox.shrink();
        }
        // Loading only before the FIRST event with no seed — once the stream
        // is active (or a seed exists), null is a real value (nullable
        // streams like "am I admin?" emit null on purpose) and goes to the
        // builder.
        if (snapshot.connectionState == ConnectionState.waiting && !hasSeed) {
          return loadingBuilder?.call(context) ??
              const Center(child: KitNativeLoadingIndicator());
        }
        return builder(context, snapshot.data as T);
      },
    );
  }
}
