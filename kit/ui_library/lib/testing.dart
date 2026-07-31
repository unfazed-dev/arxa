/// Test doubles for ui_library.
///
/// Import this from tests to substitute the UI-coupled services without a
/// navigator, an Overlay, or platform channels:
///
/// ```dart
/// final notifications = FakeKitNotificationService();
/// locator.registerSingleton<KitNotificationService>(notifications);
///
/// await viewModel.deleteItem();
/// expect(notifications.lastCall!.kind, KitNotificationKind.success);
/// expect(notifications.messages, contains('Item deleted'));
/// ```
///
/// KitAction's notification manager resolves `locator<KitNotificationService>()`
/// at call time, so registering the fake also captures every KitAction
/// snackbar/toast a ViewModel triggers.
library;

import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart' show PageRouteInfo;
import 'package:stacked_services/stacked_services.dart' show SheetResponse;

import 'services/navigation/kit_navigation_controller_service.dart';
import 'services/notifications/kit_notification_service.dart';
import 'services/sheet/kit_bottom_sheet_service.dart';

export 'package:stacked_services/stacked_services.dart' show SheetResponse;
export 'services/navigation/kit_navigation_controller_service.dart';
export 'services/notifications/kit_notification_service.dart';
export 'services/sheet/kit_bottom_sheet_service.dart';

/// One recorded [KitNotificationService.show] call.
class KitNotificationRecord {
  const KitNotificationRecord({
    required this.message,
    required this.kind,
    this.duration,
    this.title,
    this.variant,
    this.actionLabel,
    required this.hasAction,
    required this.position,
  });

  /// The positional `message` argument.
  final String message;

  /// The `kind` argument (drives toast style / snackbar variant).
  final KitNotificationKind kind;

  /// The `duration` argument.
  final Duration? duration;

  /// The `title` argument (snackbar tiers only).
  final String? title;

  /// The `variant` argument (snackbar tiers only).
  final dynamic variant;

  /// The `actionLabel` argument — non-null forces the snackbar tier on iOS.
  final String? actionLabel;

  /// Whether an `onAction` callback was passed.
  final bool hasAction;

  /// The `position` argument (CNToast tier: all values; snackbar tiers:
  /// `center` renders the kit floating pill).
  final KitToastPosition position;
}

/// A [KitNotificationService] that records every [show] call instead of
/// touching CNToast / SnackbarService / the navigator-key context.
class FakeKitNotificationService extends KitNotificationService {
  /// Every [show] call, in call order.
  final List<KitNotificationRecord> calls = [];

  /// When non-null, [show] throws this instead of recording.
  Object? showError;

  @override
  Future<void> show(
    String message, {
    KitNotificationKind kind = KitNotificationKind.info,
    Duration? duration,
    BuildContext? context,
    String? title,
    dynamic variant,
    String? actionLabel,
    VoidCallback? onAction,
    KitToastPosition position = KitToastPosition.top,
  }) {
    if (showError != null) throw showError!;
    calls.add(KitNotificationRecord(
      message: message,
      kind: kind,
      duration: duration,
      title: title,
      variant: variant,
      actionLabel: actionLabel,
      hasAction: onAction != null,
      position: position,
    ));
    return Future.value();
  }

  // ---- query helpers ---------------------------------------------------------

  /// The most recently recorded call, or null if none.
  KitNotificationRecord? get lastCall => calls.isEmpty ? null : calls.last;

  /// Every recorded message, in call order.
  List<String> get messages =>
      calls.map((c) => c.message).toList(growable: false);

  /// All recorded calls with [kind].
  List<KitNotificationRecord> callsOfKind(KitNotificationKind kind) =>
      calls.where((c) => c.kind == kind).toList(growable: false);

  /// True if a message containing [substring] was shown at least once.
  bool didShow(String substring) =>
      calls.any((c) => c.message.contains(substring));

  /// Clear the recorded calls (reuse the same instance across cases).
  void reset() => calls.clear();
}

/// One recorded [KitBottomSheetService.showBottomSheet] call.
class KitBottomSheetCall {
  const KitBottomSheetCall({
    required this.title,
    this.description,
    required this.confirmButtonTitle,
    this.cancelButtonTitle,
    required this.barrierDismissible,
  });

  /// The `title` argument.
  final String title;

  /// The `description` argument.
  final String? description;

  /// The `confirmButtonTitle` argument.
  final String confirmButtonTitle;

  /// The `cancelButtonTitle` argument (null = confirm-only sheet).
  final String? cancelButtonTitle;

  /// The `barrierDismissible` argument.
  final bool barrierDismissible;
}

/// One recorded [KitBottomSheetService.showCustomSheet] call.
class KitCustomSheetCall {
  const KitCustomSheetCall({
    this.variant,
    this.title,
    this.description,
    this.data,
  });

  /// The `variant` argument (selects the registered sheet builder).
  final dynamic variant;

  /// The `title` argument.
  final String? title;

  /// The `description` argument.
  final String? description;

  /// The `data` argument (the request payload handed to the builder).
  final dynamic data;
}

/// A [KitBottomSheetService] whose responses you script. Records every call
/// and returns the next entry of the matching queue ([bottomSheetResponses] /
/// [customSheetResponses]), falling back to the matching default once the
/// queue is exhausted. A `null` entry (or the default `null` fallback) is a
/// barrier-dismiss.
///
/// Register it as the base type, like the real service:
/// `locator.registerSingleton<BottomSheetService>(fake)`.
class FakeKitBottomSheetService extends KitBottomSheetService {
  FakeKitBottomSheetService({
    List<SheetResponse<dynamic>?>? bottomSheetResponses,
    this.defaultBottomSheetResponse,
    List<SheetResponse<dynamic>?>? customSheetResponses,
    this.defaultCustomSheetResponse,
  })  : bottomSheetResponses = bottomSheetResponses ?? [],
        customSheetResponses = customSheetResponses ?? [];

  /// Responses handed out by [showBottomSheet], in order.
  final List<SheetResponse<dynamic>?> bottomSheetResponses;

  /// Returned by [showBottomSheet] once [bottomSheetResponses] is exhausted
  /// (null = dismissed).
  SheetResponse<dynamic>? defaultBottomSheetResponse;

  /// Responses handed out by [showCustomSheet], in order.
  final List<SheetResponse<dynamic>?> customSheetResponses;

  /// Returned by [showCustomSheet] once [customSheetResponses] is exhausted
  /// (null = dismissed).
  SheetResponse<dynamic>? defaultCustomSheetResponse;

  /// Every [showBottomSheet] call, in call order.
  final List<KitBottomSheetCall> bottomSheetCalls = [];

  /// Every [showCustomSheet] call, in call order.
  final List<KitCustomSheetCall> customSheetCalls = [];

  int _bottomCursor = 0;
  int _customCursor = 0;

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
  }) async {
    bottomSheetCalls.add(KitBottomSheetCall(
      title: title,
      description: description,
      confirmButtonTitle: confirmButtonTitle,
      cancelButtonTitle: cancelButtonTitle,
      barrierDismissible: barrierDismissible,
    ));
    if (_bottomCursor < bottomSheetResponses.length) {
      return bottomSheetResponses[_bottomCursor++];
    }
    return defaultBottomSheetResponse;
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
  }) async {
    customSheetCalls.add(KitCustomSheetCall(
      variant: variant,
      title: title,
      description: description,
      data: data,
    ));
    final next = _customCursor < customSheetResponses.length
        ? customSheetResponses[_customCursor++]
        : defaultCustomSheetResponse;
    return next as SheetResponse<T>?;
  }

  // ---- query helpers ---------------------------------------------------------

  /// The most recently recorded [showBottomSheet] call, or null if none.
  KitBottomSheetCall? get lastBottomSheetCall =>
      bottomSheetCalls.isEmpty ? null : bottomSheetCalls.last;

  /// The most recently recorded [showCustomSheet] call, or null if none.
  KitCustomSheetCall? get lastCustomSheetCall =>
      customSheetCalls.isEmpty ? null : customSheetCalls.last;

  /// Clear the call records and rewind both response queues (the queued
  /// responses themselves are kept).
  void reset() {
    bottomSheetCalls.clear();
    customSheetCalls.clear();
    _bottomCursor = 0;
    _customCursor = 0;
  }
}

/// One recorded [KitNavigationControllerService.navigate] call.
class KitNavigationRecord {
  const KitNavigationRecord({this.viewRoute, this.view});

  /// The `viewRoute` argument (web path).
  final PageRouteInfo? viewRoute;

  /// The `view` argument (native push path).
  final Widget? view;
}

/// A [KitNavigationControllerService] that records [navigate] calls instead
/// of pushing routes. `implements` (not `extends`) so construction does NOT
/// resolve `locator<RouterService>()` — the fake is safe to build before any
/// router is registered.
class FakeKitNavigationControllerService
    implements KitNavigationControllerService {
  /// Every [navigate] call, in call order.
  final List<KitNavigationRecord> calls = [];

  @override
  Future<void> navigate({
    required BuildContext context,
    PageRouteInfo? viewRoute,
    Widget? view,
  }) async {
    calls.add(KitNavigationRecord(viewRoute: viewRoute, view: view));
  }

  /// The most recently recorded call, or null if none.
  KitNavigationRecord? get lastCall => calls.isEmpty ? null : calls.last;

  /// Clear the recorded calls (reuse the same instance across cases).
  void reset() => calls.clear();
}
