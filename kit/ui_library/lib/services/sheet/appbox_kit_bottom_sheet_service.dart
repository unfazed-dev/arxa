import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart';

import '../../widgets/appbox_kit_native_sheet.dart';

/// Drop-in [BottomSheetService] that presents through [appBoxKitShowSheet]
/// instead of `Get.bottomSheet`, so every stacked sheet call site
/// (`showBottomSheet`, `showCustomSheet`, AppBoxKitAction's AppBoxKitNotificationManager)
/// gets the kit's platform-adaptive sheet: CNBottomSheet on iOS/macOS,
/// M3-themed `showModalBottomSheet` on Android.
///
/// Register it *as* the base type so call sites stay untouched:
/// `LazySingleton(classType: AppBoxKitBottomSheetService, asType: BottomSheetService)`.
///
/// The API contract is preserved: builders receive the same
/// `SheetRequest` / completer, and both futures resolve with the
/// `SheetResponse` passed to the completer (or null on barrier dismiss).
///
/// ponytail: Get-specific knobs (enter/exit durations, enableDrag,
/// useRootNavigator, elevation) are accepted but ignored — appBoxKitShowSheet
/// exposes primitives only. `isBottomSheetOpen` still reads Get state and
/// will report false for kit-presented sheets; wire a flag if anyone needs it.
class AppBoxKitBottomSheetService extends BottomSheetService {
  final Map<dynamic, SheetBuilder> _builders = {};

  @override
  void setCustomSheetBuilders(Map<dynamic, SheetBuilder> builders) {
    _builders.addAll(builders);
    super.setCustomSheetBuilders(builders);
  }

  BuildContext? get _context => StackedService.navigatorKey?.currentContext;

  @override
  Future<SheetResponse?> showBottomSheet({
    required String title,
    String? description,
    String confirmButtonTitle = 'Ok',
    String? cancelButtonTitle,
    bool enableDrag = true,
    bool barrierDismissible = true,
    bool isScrollControlled = false,
    Duration? exitBottomSheetDuration,
    Duration? enterBottomSheetDuration,
    bool? ignoreSafeArea,
    bool useRootNavigator = false,
    double elevation = 1,
  }) {
    final context = _context;
    if (context == null) {
      debugPrint('AppBoxKitBottomSheetService: no navigator context; sheet skipped');
      return Future.value(null);
    }
    return appBoxKitShowSheet<SheetResponse>(
      context: context,
      isDismissible: barrierDismissible,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(description, style: Theme.of(ctx).textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (cancelButtonTitle != null)
                    TextButton(
                      onPressed: () => Navigator.of(ctx)
                          .pop(SheetResponse(confirmed: false)),
                      child: Text(cancelButtonTitle),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(SheetResponse(confirmed: true)),
                    child: Text(confirmButtonTitle),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Future<SheetResponse<T>?> showCustomSheet<T, R>({
    dynamic variant,
    String? title,
    String? description,
    bool hasImage = false,
    String? imageUrl,
    bool showIconInMainButton = false,
    String? mainButtonTitle,
    bool showIconInSecondaryButton = false,
    String? secondaryButtonTitle,
    bool showIconInAdditionalButton = false,
    String? additionalButtonTitle,
    bool takesInput = false,
    Color barrierColor = Colors.black54,
    double elevation = 1,
    bool barrierDismissible = true,
    bool isScrollControlled = false,
    String barrierLabel = '',
    @Deprecated('Use `data` and pass in a generic type.') dynamic customData,
    R? data,
    bool enableDrag = true,
    Duration? exitBottomSheetDuration,
    Duration? enterBottomSheetDuration,
    bool? ignoreSafeArea,
    bool useRootNavigator = false,
  }) {
    final sheetBuilder = _builders[variant];
    assert(
      sheetBuilder != null,
      'No sheet builder for variant:$variant. Call setCustomSheetBuilders '
      'with a builder for it first.',
    );
    final context = _context;
    if (sheetBuilder == null || context == null) {
      debugPrint('AppBoxKitBottomSheetService: no builder/context; sheet skipped');
      return Future.value(null);
    }
    return appBoxKitShowSheet<SheetResponse<T>>(
      context: context,
      isDismissible: barrierDismissible,
      // No backgroundColor override: the sheet route's own chrome (M3
      // surface on Android, Flutter-glass body on the iOS tier) shows and
      // follows the active theme, so builders render content only — unlike
      // upstream, which forces transparency and makes every builder paint
      // its own box.
      builder: (ctx) => sheetBuilder(
        ctx,
        SheetRequest<R>(
          title: title,
          description: description,
          hasImage: hasImage,
          imageUrl: imageUrl,
          showIconInMainButton: showIconInMainButton,
          mainButtonTitle: mainButtonTitle,
          showIconInSecondaryButton: showIconInSecondaryButton,
          secondaryButtonTitle: secondaryButtonTitle,
          showIconInAdditionalButton: showIconInAdditionalButton,
          additionalButtonTitle: additionalButtonTitle,
          takesInput: takesInput,
          // ignore: deprecated_member_use
          customData: customData,
          variant: variant,
          data: data,
        ),
        (response) => Navigator.of(ctx).pop(response),
      ),
    );
  }
}
