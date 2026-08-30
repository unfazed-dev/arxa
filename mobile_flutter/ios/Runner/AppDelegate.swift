import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let apns = ApnsBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // D68 phone leg: raw-APNs presentation + tap routing. Set before any
    // push can arrive (cold start from a tapped notification included).
    UNUserNotificationCenter.current().delegate = apns
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    apns.bindChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  // APNs registration results — forwarded to the bridge (FlutterAppDelegate
  // has no default behavior for either).
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    apns.deviceToken = deviceToken
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    apns.registrationError = error.localizedDescription
  }

  // B2 phase-1b (the visible→silent swap): a silent (content-available)
  // doorbell may WAKE the app (remote-notification background mode). Only
  // content-available pushes are ours; anything else defers to super.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let aps = userInfo["aps"] as? [String: Any]
    if (aps?["content-available"] as? Int) == 1 {
      apns.handleSilentWake(userInfo, completionHandler)
      return
    }
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }
}

/// Raw-APNs bridge (D68 phone leg): mints the device token, asks permission,
/// presents pushes while foregrounded, and forwards taps — no Firebase in the
/// path (cairn-push's ApnsRail + the operator's .p8; ADR-0037 keeps provider
/// wiring app-side).
///
/// Bidirectional method channel `arxa/apns`:
///   Dart→native: initialize (no-op), requestPermission {alert,badge,sound},
///     permissionStatus, getToken, getRegistrationError, setBadgeCount
///     {count}, clearBadge, showLocalNotification {id,title,body,payload,
///     badge}, cancel {id}, cancelAll, pendingTap (read-and-clear)
///   native→Dart: 'event' {type: willPresent|tap, title, body, category,
///     requestId, collapseKey?, userInfo}
final class ApnsBridge: NSObject, UNUserNotificationCenterDelegate {
  static let channelName = "arxa/apns"

  private var channel: FlutterMethodChannel?
  fileprivate(set) var deviceToken: Data?
  fileprivate(set) var registrationError: String?

  /// The latest tap, buffered BEFORE the channel invoke so a cold launch
  /// (Dart handler not yet registered → null reply) can still drain it via
  /// the 'pendingTap' method (read-and-clear).
  fileprivate(set) var pendingTap: [String: Any]?

  /// A silent doorbell wake is pending Dart handling (same cold-launch
  /// buffering discipline as the tap). Drained via 'pendingSilentWake'
  /// (read-and-clear); finished via 'silentWakeDone'.
  fileprivate(set) var pendingSilentWake = false
  private var pendingWakeCompletions: [(UIBackgroundFetchResult) -> Void] = []

  /// The APNs device token as lowercase hex (the wire form cairn-push's
  /// registry stores; same encoding APNs debugging docs use).
  var deviceTokenHex: String? {
    guard let token = deviceToken else { return nil }
    return token.map { String(format: "%02x", $0) }.joined()
  }

  func bindChannel(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize":
      // Channel handler binding is the only native state; already done.
      result(nil)
    case "requestPermission":
      var options = UNAuthorizationOptions()
      if args["alert"] as? Bool ?? true { options.insert(.alert) }
      if args["badge"] as? Bool ?? true { options.insert(.badge) }
      if args["sound"] as? Bool ?? true { options.insert(.sound) }
      let center = UNUserNotificationCenter.current()
      center.requestAuthorization(options: options) { _, _ in
        DispatchQueue.main.async {
          // Token minting needs NO user permission — only the entitlement.
          // Register right after the ask so an instant Allow still mints.
          UIApplication.shared.registerForRemoteNotifications()
        }
        self.replyStatus(result)
      }
    case "permissionStatus":
      replyStatus(result)
    case "getToken":
      result(deviceTokenHex)
    case "getRegistrationError":
      result(registrationError)
    case "setBadgeCount":
      let count = args["count"] as? Int ?? 0
      DispatchQueue.main.async { UIApplication.shared.applicationIconBadgeNumber = count }
      result(nil)
    case "clearBadge":
      DispatchQueue.main.async { UIApplication.shared.applicationIconBadgeNumber = 0 }
      result(nil)
    case "showLocalNotification":
      let content = UNMutableNotificationContent()
      content.title = args["title"] as? String ?? ""
      content.body = args["body"] as? String ?? ""
      if let badge = args["badge"] as? Int { content.badge = NSNumber(value: badge) }
      if let payload = args["payload"] as? String { content.userInfo = ["payload": payload] }
      let id = String(args["id"] as? Int ?? 0)
      let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request) { _ in }
      result(nil)
    case "cancel":
      let id = String(args["id"] as? Int ?? 0)
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [id])
      center.removeDeliveredNotifications(withIdentifiers: [id])
      result(nil)
    case "pendingTap":
      let tap = pendingTap
      pendingTap = nil
      result(tap)
    case "pendingSilentWake":
      let pending = pendingSilentWake
      pendingSilentWake = false
      result(pending)
    case "silentWakeDone":
      completeOneSilentWake(.newData)
      result(nil)
    case "cancelAll":
      let center = UNUserNotificationCenter.current()
      center.removeAllPendingNotificationRequests()
      center.removeAllDeliveredNotifications()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Current authorization status as the kit's enum string.
  private func replyStatus(_ reply: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let status: String
      switch settings.authorizationStatus {
      case .authorized: status = "authorized"
      case .denied: status = "denied"
      case .provisional, .ephemeral: status = "provisional"
      default: status = "notDetermined"
      }
      reply(status)
    }
  }

  // MARK: - Silent doorbell wake (B2 phase-1b)

  /// A content-available push woke the app: hand the wake to Dart (the
  /// tunnel resume + sync + local doorbell live there) and keep the fetch
  /// completion for Dart's 'silentWakeDone' — with a bounded native
  /// fallback so iOS is never left waiting past its ~30s budget.
  func handleSilentWake(
    _ userInfo: [AnyHashable: Any],
    _ completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    pendingWakeCompletions.append(completionHandler)
    pendingSilentWake = true
    channel?.invokeMethod("event", arguments: ["type": "silentWake", "userInfo": userInfo])
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
      self?.completeOneSilentWake(.noData)
    }
  }

  private func completeOneSilentWake(_ result: UIBackgroundFetchResult) {
    guard !pendingWakeCompletions.isEmpty else { return }
    let handler = pendingWakeCompletions.removeFirst()
    handler(result)
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    sendEvent(type: "willPresent", notification: notification)
    // D65 copy presents even while the app is foregrounded — the approvals
    // loop's whole point is catching the owner mid-app. The .list option is
    // what keeps it in Notification Center / the lock-screen list
    // afterwards; banner-only flashed and vanished (2026-08-29: foreground
    // pushes never persisted, background/closed delivery always did — which
    // masked this as a "cellular" issue when it was presentation-path only).
    completionHandler([.banner, .list, .badge, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    sendEvent(type: "tap", notification: response.notification)
    completionHandler()
  }

  private func sendEvent(type: String, notification: UNNotification) {
    let content = notification.request.content
    var payload: [String: Any] = [
      "type": type,
      "title": content.title,
      "body": content.body,
      "category": content.categoryIdentifier,
      // Dedupe key for the Dart drain (cold start may deliver both the
      // live event AND the drained pendingTap for the same notification).
      "requestId": notification.request.identifier,
    ]
    // Task-tap routing: the push class rides the collapse key — thread id
    // first, else the aps dict cairn-push fills in.
    let aps = content.userInfo["aps"] as? [String: Any]
    let collapseKey = content.threadIdentifier.isEmpty
      ? aps?["collapse-id"] as? String : content.threadIdentifier
    if let collapseKey, !collapseKey.isEmpty {
      payload["collapseKey"] = collapseKey
    }
    if !content.userInfo.isEmpty {
      payload["userInfo"] = content.userInfo
    }
    if type == "tap" {
      pendingTap = payload
    }
    channel?.invokeMethod("event", arguments: payload)
  }
}
