import 'appbox_kit_haptic_locator.dart';
import 'appbox_kit_haptic_service.dart';
import 'package:flutter/widgets.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

/// A widget that wraps its child with haptic feedback functionality
class _HapticGestureDetector extends StatelessWidget {
  final Widget child;
  final HapticsType type;
  final VoidCallback? onTap;

  const _HapticGestureDetector({
    required this.child,
    required this.type,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _handleTap(),
      child: child,
    );
  }

  Future<void> _handleTap() async {
    try {
      await appBoxKitLocator<AppBoxKitHapticService>().triggerHaptic(type);
    } catch (e) {
      // Ignore haptic errors to ensure onTap is still called
    }
    onTap?.call();
  }
}

/// Extension methods for adding haptic feedback to any widget
extension AppBoxKitHapticExtension on Widget {
  /// Wraps the widget with haptic feedback of the specified type
  Widget withHapticFeedback({
    HapticsType type = HapticsType.light,
    VoidCallback? onTap,
  }) {
    return _HapticGestureDetector(
      type: type,
      onTap: onTap,
      child: this,
    );
  }

  /// Convenience methods for common haptic patterns
  Widget withSuccessHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.success, onTap: onTap);

  Widget withWarningHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.warning, onTap: onTap);

  Widget withErrorHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.error, onTap: onTap);

  Widget withLightHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.light, onTap: onTap);

  Widget withMediumHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.medium, onTap: onTap);

  Widget withHeavyHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.heavy, onTap: onTap);

  Widget withRigidHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.rigid, onTap: onTap);

  Widget withSoftHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.soft, onTap: onTap);

  Widget withSelectionHaptic({VoidCallback? onTap}) =>
      withHapticFeedback(type: HapticsType.selection, onTap: onTap);
}
