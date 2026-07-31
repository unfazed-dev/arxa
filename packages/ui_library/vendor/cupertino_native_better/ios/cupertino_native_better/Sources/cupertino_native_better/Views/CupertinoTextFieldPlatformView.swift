import Flutter
import UIKit
import SwiftUI

/// Platform view for [CNTextField] — a native iOS text field (Liquid Glass on
/// iOS 26+, `Color(.systemGray6)` capsule below) hosted in a `UIHostingController`.
///
/// Mirrors [CupertinoSearchBarPlatformView]'s structure (per-instance method
/// channel, args parsing, container + hosting controller, `cnBlockSafeArea`,
/// `setInteractive` for the modal-hide mixin) but hosts a `TextModel`-backed
/// `CNTextFieldSwiftUI` so `setText`/`clear`/`focus`/`unfocus` actually take
/// effect (the search bar's channel handlers are stubs that return `nil`).
class CupertinoTextFieldPlatformView: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let hostingController: UIHostingController<AnyView>
  private let container: UIView
  private let model: TextModel
  private let focusBinding: ExternalFocusBinding

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(
      name: "CNTextField_\(viewId)",
      binaryMessenger: messenger
    )
    self.container = UIView(frame: frame)
    // Stored property with a default initializer — set before super.init() and
    // safe to capture in the closures below via the local `focusBindingRef`.
    let focusBinding = ExternalFocusBinding()
    self.focusBinding = focusBinding

    // Parse args (keys mirror CNSearchBar's contract + text-input additions).
    var text = ""
    var placeholder = ""
    var isSecure = false
    var autofocus = false
    var keyboardType = "default"
    var tint = Color.accentColor
    var textColor: Color? = nil
    var placeholderColor: Color? = nil
    var isDark = false

    if let dict = args as? [String: Any] {
      if let v = dict["text"] as? String { text = v }
      if let v = dict["placeholder"] as? String { placeholder = v }
      if let v = dict["isSecure"] as? Bool { isSecure = v }
      if let v = dict["autofocus"] as? Bool { autofocus = v }
      if let v = dict["keyboardType"] as? String { keyboardType = v }
      if let v = dict["tint"] as? NSNumber { tint = Color(uiColor: ImageUtils.colorFromARGB(v.intValue)) }
      if let v = dict["textColor"] as? NSNumber { textColor = Color(uiColor: ImageUtils.colorFromARGB(v.intValue)) }
      if let v = dict["placeholderColor"] as? NSNumber { placeholderColor = Color(uiColor: ImageUtils.colorFromARGB(v.intValue)) }
      if let v = dict["isDark"] as? Bool { isDark = v }
    }

    // Capture the channel for closures (self.channel is already initialized).
    let channelRef = self.channel

    let model = TextModel(
      text: text,
      placeholder: placeholder,
      isSecure: isSecure,
      autofocus: autofocus,
      keyboardType: keyboardType,
      tint: tint,
      textColor: textColor,
      placeholderColor: placeholderColor,
      onChange: { value in
        channelRef.invokeMethod("textChanged", arguments: ["text": value])
      },
      onSubmit: { value in
        channelRef.invokeMethod("submitted", arguments: ["text": value])
      },
      onFocusChanged: { focused in
        channelRef.invokeMethod("focusChanged", arguments: ["focused": focused])
      }
    )
    self.model = model

    let textFieldView = CNTextFieldSwiftUI(model: model, focusBinding: focusBinding)
    // Type-erase to AnyView so the stored `UIHostingController<AnyView>` property
    // holds a concrete content type without exposing it on the class surface.
    let hosting = UIHostingController(rootView: AnyView(textFieldView))
    // REQUIRED for every SwiftUI-in-Flutter host (repo guard test enforces it):
    // Flutter moves the platform view in window coords during scroll, which
    // makes a stock UIHostingController inset its content near the safe area.
    hosting.cnBlockSafeArea()
    self.hostingController = hosting

    super.init()

    container.backgroundColor = .clear
    if #available(iOS 13.0, *) {
      container.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    hostingController.view.backgroundColor = .clear
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hostingController.view)

    NSLayoutConstraint.activate([
      hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      hostingController.view.topAnchor.constraint(equalTo: container.topAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    setupMethodChannel()
  }

  private func setupMethodChannel() {
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }

      switch call.method {
      case "setText":
        // Two-way controller: Dart pushed a programmatic text change (e.g. the
        // host's TextEditingController.text was set). Mutate the model so SwiftUI
        // updates. `onChange` is NOT fired here — the change originated from
        // Dart, so echoing it back would loop.
        if let args = call.arguments as? [String: Any],
           let value = args["text"] as? String {
          self.model.text = value
        }
        result(nil)
      case "clear":
        self.model.text = ""
        result(nil)
      case "focus":
        // SwiftUI's @FocusState can only be driven from the view tree, so the
        // channel flips this ObservableObject and the view applies the focus.
        self.focusBinding.request()
        result(nil)
      case "unfocus":
        self.focusBinding.relinquish()
        result(nil)
      case "setBrightness":
        if let args = call.arguments as? [String: Any],
           let isDark = (args["isDark"] as? NSNumber)?.boolValue {
          if #available(iOS 13.0, *) {
            self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
          }
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
        }
      case "setInteractive":
        // ModalHideMixin toggles user interaction on a CN widget when a modal
        // opens above it (Issue #53 z-order bleed). Mirrors search bar's handler.
        let interactive = ((call.arguments as? [String: Any])?["interactive"] as? NSNumber)?.boolValue ?? true
        self._cnSetInteractiveRecursive(self.container, interactive)
        self._cnSetInteractiveRecursive(self.hostingController.view, interactive)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  private func _cnSetInteractiveRecursive(_ view: UIView?, _ interactive: Bool) {
    guard let view = view else { return }
    view.isUserInteractionEnabled = interactive
    for sub in view.subviews { _cnSetInteractiveRecursive(sub, interactive) }
  }
}

// MARK: - Focus request bridge

/// A focus signal the method channel can trigger and SwiftUI can observe.
/// SwiftUI's `@FocusState` can only be mutated from the view tree, so this
/// `ObservableObject` is the sanctioned bridge: the channel calls
/// `request()`/`relinquish()`, the view observes `state`, and applies it to
/// its `@FocusState`, then resets to `.idle`.
final class ExternalFocusBinding: ObservableObject {
  enum State { case idle, requesting, relinquishing }
  @Published var state: State = .idle

  func request() { state = .requesting }
  func relinquish() { state = .relinquishing }
}

// MARK: - SwiftUI text field

struct CNTextFieldSwiftUI: View {
  @ObservedObject var model: TextModel
  @ObservedObject var focusBinding: ExternalFocusBinding
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 8) {
      field
        .foregroundColor(model.textColor ?? .primary)
        .focused($isFocused)
        .submitLabel(.done)
        .onSubmit { model.onSubmit(model.text) }
        .onChange(of: model.text) { newValue in
          model.onChange(newValue)
        }

      if !model.isSecure && !model.text.isEmpty {
        Button(action: {
          model.text = ""
          model.onChange("")
        }) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16))
            .foregroundColor(model.placeholderColor ?? .secondary)
        }
        .transition(.opacity.combined(with: .scale))
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 44)
    .background(glassBackground)
    .clipShape(Capsule())
    .onChange(of: isFocused) { focused in
      model.onFocusChanged(focused)
    }
    .onChange(of: focusBinding.state) { state in
      // Apply the external focus request, then reset so the same direction can
      // fire again later (Published changes only notify on a new value).
      switch state {
      case .requesting:
        isFocused = true
        focusBinding.state = .idle
      case .relinquishing:
        isFocused = false
        focusBinding.state = .idle
      case .idle:
        break
      }
    }
    .onAppear {
      if model.autofocus {
        DispatchQueue.main.async { isFocused = true }
      }
    }
  }

  /// Secure vs. plain field.
  @ViewBuilder
  private var field: some View {
    if model.isSecure {
      SecureField(model.placeholder, text: $model.text)
    } else {
      TextField(model.placeholder, text: $model.text)
        .keyboardType(model.uiKeyboardType)
    }
  }

  /// Liquid Glass capsule on iOS 26+, `systemGray6` capsule below (same shape
  /// rule as CNSearchBar's glassBackground).
  @ViewBuilder
  private var glassBackground: some View {
    if #available(iOS 26.0, *) {
      Color.clear.glassEffect(.regular, in: .capsule)
    } else {
      Color(.systemGray6)
    }
  }
}
