/// Test doubles for ui_library.
///
/// Import this from tests to substitute the UI-coupled services without a
/// navigator, an Overlay, or platform channels:
///
/// ```dart
/// final notifications = FakeAppBoxKitNotificationService();
/// appBoxKitLocator.registerSingleton<AppBoxKitNotificationService>(notifications);
///
/// await viewModel.deleteItem();
/// expect(notifications.lastCall!.kind, AppBoxKitNotificationKind.success);
/// expect(notifications.messages, contains('Item deleted'));
/// ```
///
/// AppBoxKitAction's notification manager resolves `appBoxKitLocator<AppBoxKitNotificationService>()`
/// at call time, so registering the fake also captures every AppBoxKitAction
/// snackbar/toast a ViewModel triggers.
library;

import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart' show PageRouteInfo;
import 'package:stacked_services/stacked_services.dart' show SheetResponse;

import 'services/navigation/appbox_kit_navigation_controller_service.dart';
import 'services/notifications/appbox_kit_notification_service.dart';
import 'services/sheet/appbox_kit_bottom_sheet_service.dart';

export 'package:stacked_services/stacked_services.dart' show SheetResponse;
export 'services/navigation/appbox_kit_navigation_controller_service.dart';
export 'services/notifications/appbox_kit_notification_service.dart';
export 'services/sheet/appbox_kit_bottom_sheet_service.dart';

/// One recorded [AppBoxKitNotificationService.show] call.
class AppBoxKitNotificationRecord {
  const AppBoxKitNotificationRecord({
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
  final AppBoxKitNotificationKind kind;

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
  final AppBoxKitToastPosition position;
}

/// A [AppBoxKitNotificationService] that records every [show] call instead of
/// touching CNToast / SnackbarService / the navigator-key context.
class FakeAppBoxKitNotificationService extends AppBoxKitNotificationService {
  /// Every [show] call, in call order.
  final List<AppBoxKitNotificationRecord> calls = [];

  /// Every [alert] call, as `(title, message)` records, in call order.
  final List<({String title, String? message})> alertCalls = [];

  /// Every [notice] call, as `(title, message)` records, in call order.
  final List<({String title, String message})> noticeCalls = [];

  /// Every [confirm] call, as `(title, message)` records, in call order.
  final List<({String title, String? message})> confirmCalls = [];

  /// Every [prompt] call, as `(title, message)` records, in call order.
  final List<({String title, String? message})> promptCalls = [];

  /// What [confirm] resolves. Tests exercising a VM's confirm path set this —
  /// the real service would need a widget tree.
  bool confirmResult = false;

  /// What [prompt] resolves. See [confirmResult].
  String? promptResult;

  /// When non-null, [show] throws this instead of recording.
  Object? showError;

  @override
  Future<void> show(
    String message, {
    AppBoxKitNotificationKind kind = AppBoxKitNotificationKind.info,
    Duration? duration,
    BuildContext? context,
    String? title,
    dynamic variant,
    String? actionLabel,
    VoidCallback? onAction,
    AppBoxKitToastPosition position = AppBoxKitToastPosition.top,
  }) {
    if (showError != null) throw showError!;
    calls.add(AppBoxKitNotificationRecord(
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

  @override
  Future<void> alert({
    required String title,
    String? message,
    String actionLabel = 'OK',
    bool barrierDismissible = true,
    BuildContext? context,
  }) {
    alertCalls.add((title: title, message: message));
    return Future.value();
  }

  @override
  Future<void> notice({
    required String title,
    required String message,
    BuildContext? context,
  }) {
    noticeCalls.add((title: title, message: message));
    return Future.value();
  }

  @override
  Future<bool> confirm({
    required String title,
    String? message,
    String actionLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    BuildContext? context,
  }) {
    confirmCalls.add((title: title, message: message));
    return Future.value(confirmResult);
  }

  @override
  Future<String?> prompt({
    required String title,
    String? message,
    String? placeholder,
    String? initialValue,
    String actionLabel = 'Save',
    String cancelLabel = 'Cancel',
    BuildContext? context,
  }) {
    promptCalls.add((title: title, message: message));
    return Future.value(promptResult);
  }

  // ---- query helpers ---------------------------------------------------------

  /// The most recently recorded call, or null if none.
  AppBoxKitNotificationRecord? get lastCall => calls.isEmpty ? null : calls.last;

  /// Every recorded message, in call order.
  List<String> get messages =>
      calls.map((c) => c.message).toList(growable: false);

  /// All recorded calls with [kind].
  List<AppBoxKitNotificationRecord> callsOfKind(AppBoxKitNotificationKind kind) =>
      calls.where((c) => c.kind == kind).toList(growable: false);

  /// True if a message containing [substring] was shown at least once.
  bool didShow(String substring) =>
      calls.any((c) => c.message.contains(substring));

  /// Clear the recorded calls (reuse the same instance across cases).
  void reset() => calls.clear();
}

/// One recorded [AppBoxKitBottomSheetService.showBottomSheet] call.
class AppBoxKitBottomSheetCall {
  const AppBoxKitBottomSheetCall({
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

/// One recorded [AppBoxKitBottomSheetService.showCustomSheet] call.
class AppBoxKitCustomSheetCall {
  const AppBoxKitCustomSheetCall({
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

/// A [AppBoxKitBottomSheetService] whose responses you script. Records every call
/// and returns the next entry of the matching queue ([bottomSheetResponses] /
/// [customSheetResponses]), falling back to the matching default once the
/// queue is exhausted. A `null` entry (or the default `null` fallback) is a
/// barrier-dismiss.
///
/// Register it as the base type, like the real service:
/// `appBoxKitLocator.registerSingleton<BottomSheetService>(fake)`.
class FakeAppBoxKitBottomSheetService extends AppBoxKitBottomSheetService {
  FakeAppBoxKitBottomSheetService({
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
  final List<AppBoxKitBottomSheetCall> bottomSheetCalls = [];

  /// Every [showCustomSheet] call, in call order.
  final List<AppBoxKitCustomSheetCall> customSheetCalls = [];

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
    bottomSheetCalls.add(AppBoxKitBottomSheetCall(
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
    customSheetCalls.add(AppBoxKitCustomSheetCall(
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
  AppBoxKitBottomSheetCall? get lastBottomSheetCall =>
      bottomSheetCalls.isEmpty ? null : bottomSheetCalls.last;

  /// The most recently recorded [showCustomSheet] call, or null if none.
  AppBoxKitCustomSheetCall? get lastCustomSheetCall =>
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

/// One recorded [AppBoxKitNavigationControllerService.navigate] call.
class AppBoxKitNavigationRecord {
  const AppBoxKitNavigationRecord({this.viewRoute, this.view});

  /// The `viewRoute` argument (web path).
  final PageRouteInfo? viewRoute;

  /// The `view` argument (native push path).
  final Widget? view;
}

/// A [AppBoxKitNavigationControllerService] that records [navigate] calls instead
/// of pushing routes. `implements` (not `extends`) so construction does NOT
/// resolve `appBoxKitLocator<RouterService>()` — the fake is safe to build before any
/// router is registered.
class FakeAppBoxKitNavigationControllerService
    implements AppBoxKitNavigationControllerService {
  /// Every [navigate] call, in call order.
  final List<AppBoxKitNavigationRecord> calls = [];

  @override
  Future<void> navigate({
    required BuildContext context,
    PageRouteInfo? viewRoute,
    Widget? view,
  }) async {
    calls.add(AppBoxKitNavigationRecord(viewRoute: viewRoute, view: view));
  }

  /// The most recently recorded call, or null if none.
  AppBoxKitNavigationRecord? get lastCall => calls.isEmpty ? null : calls.last;

  /// Clear the recorded calls (reuse the same instance across cases).
  void reset() => calls.clear();
}
