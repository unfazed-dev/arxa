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
/// This is a convenience wrapper over Flutter's stock [StreamBuilder], not a
/// replacement for stacked's own primitives. When to use what:
/// - **[KitStreamBuilder]** — displaying one or more kit-data streams in a
///   view's body, where each stream should rebuild its own subtree
///   independently.
/// - **stacked's `StreamViewModel<T>`** — the viewmodel itself needs to
///   react to / transform a single dominant stream.
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
    final seededStream = stream;
    final seed = initialData ??
        (seededStream is ValueStream<T> ? seededStream.valueOrNull : null);

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
        if (!snapshot.hasData) {
          return loadingBuilder?.call(context) ??
              const Center(child: KitNativeLoadingIndicator());
        }
        return builder(context, snapshot.data as T);
      },
    );
  }
}
