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
///     badge}, cancel {id}, cancelAll
///   native→Dart: 'event' {type: willPresent|tap, title, body, category,
///     userInfo}
final class ApnsBridge: NSObject, UNUserNotificationCenterDelegate {
  static let channelName = "arxa/apns"

  private var channel: FlutterMethodChannel?
  fileprivate(set) var deviceToken: Data?
  fileprivate(set) var registrationError: String?

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

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    sendEvent(type: "willPresent", content: notification.request.content)
    // D65 copy presents even while the app is foregrounded — the approvals
    // loop's whole point is catching the owner mid-app.
    completionHandler([.banner, .badge, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    sendEvent(type: "tap", content: response.notification.request.content)
    completionHandler()
  }

  private func sendEvent(type: String, content: UNNotificationContent) {
    var payload: [String: Any] = [
      "type": type,
      "title": content.title,
      "body": content.body,
      "category": content.categoryIdentifier,
    ]
    if !content.userInfo.isEmpty {
      payload["userInfo"] = content.userInfo
    }
    channel?.invokeMethod("event", arguments: payload)
  }
}
