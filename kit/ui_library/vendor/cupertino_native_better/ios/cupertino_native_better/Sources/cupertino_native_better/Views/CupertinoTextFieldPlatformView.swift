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
  private let appearanceEpoch: CNAppearanceEpoch
  private let settleReplay = CNAppearanceSettleReplay()

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
    let appearanceEpoch = CNAppearanceEpoch()
    self.appearanceEpoch = appearanceEpoch

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
    var minLines: Int? = nil
    var maxLines: Int? = nil

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
      if let v = dict["minLines"] as? Int { minLines = v }
      if let v = dict["maxLines"] as? Int { maxLines = v }
    }

    // Capture the channel for closures (self.channel is already initialized).
    let channelRef = self.channel

    let model = TextModel(
      text: text,
      placeholder: placeholder,
      isSecure: isSecure,
      autofocus: autofocus,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
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
      },
      onHeightChanged: { height in
        channelRef.invokeMethod("heightChanged", arguments: ["height": height])
      }
    )
    self.model = model

    let textFieldView = CNTextFieldSwiftUI(model: model, focusBinding: focusBinding, appearanceEpoch: appearanceEpoch)
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
          CNAppearance.trace("CNTextField", "setBrightness isDark=\(isDark)")
          if #available(iOS 13.0, *) {
            self.applyBrightness(isDark)
            // After a rapid flip storm, replay the final state once so a
            // mid-storm-coalesced render can't strand this view on the
            // previous theme (14-01 clip). See CNAppearanceSettleReplay.
            self.settleReplay.poke { [weak self] in self?.applyBrightness(isDark) }
          }
          CNAppearance.trace("CNTextField", "setBrightness applied")
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

  /// Push the in-app brightness to every tier of this text field. Extracted
  /// from the `setBrightness` handler so `CNAppearanceSettleReplay` can
  /// replay it verbatim after a rapid flip storm (14-01 clip).
  @available(iOS 13.0, *)
  private func applyBrightness(_ isDark: Bool) {
    CNAppearance.applyInstantly(forcing: [self.container, self.hostingController.view]) {
      self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
      // Also the hosting controller — attached with
      // `addSubview(hostingController.view)` and no `addChild`, so it is
      // outside the view-controller hierarchy. See
      // `GlassButtonGroupView.applyBrightness`.
      self.hostingController.overrideUserInterfaceStyle = isDark ? .dark : .light
      // Recreate the glass capsule via its `.id` epoch — the trait
      // pins alone leave the material stale.
      self.appearanceEpoch.epoch &+= 1
    }
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
  // Bumped per theme flip; hung on the glass background via `.id` (see
  // CNSearchBarSwiftUI for why not a re-root).
  @ObservedObject var appearanceEpoch: CNAppearanceEpoch
  @FocusState private var isFocused: Bool

  @ViewBuilder
  var body: some View {
    // The multiline composer needs TextField(axis:) + range lineLimit (iOS 16+).
    // Below iOS 16 the field gracefully degrades to the single-line capsule —
    // the pre-composer behavior on those OSes.
    if model.isMultiline && !model.isSecure {
      if #available(iOS 16.0, *) {
        multilineBody
      } else {
        singleLineBody
      }
    } else {
      singleLineBody
    }
  }

  /// The growing composer (Apple's sanctioned shape: `TextField(axis: .vertical)`
  /// + a `lineLimit(min...max)` range — it starts one line tall and grows with
  /// content, switching to internal scrolling at the cap). Height reports flow
  /// to Flutter (`heightChanged`) so the platform-view slot tracks the capsule;
  /// the frame change is animated (SwiftUI does not animate it for free).
  /// iOS 16+ (the axis initializer + range lineLimit); below, the guarded call
  /// site falls back to the single-line capsule.
  @available(iOS 16.0, *)
  private var multilineBody: some View {
    let minH = CGFloat(44)
    return HStack(alignment: .bottom, spacing: 8) {
      TextField(model.placeholder, text: $model.text, axis: .vertical)
        .keyboardType(model.uiKeyboardType)
        .foregroundColor(model.textColor ?? .primary)
        .focused($isFocused)
        .lineLimit((model.minLines ?? 1)...(model.maxLines ?? Int.max))
        .submitLabel(.send)
        .onSubmit { model.onSubmit(model.text) }
        .onChange(of: model.text) { newValue in
          model.onChange(newValue)
        }

      if !model.text.isEmpty {
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
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    // NO maxHeight .infinity: the host box (Flutter side) is sized by the
    // heightChanged report; content claiming infinity inside a bounded host
    // compresses the TextField to its 22pt minimum and shrinks the tap area
    // to that sliver (measured via the AX tree on device, 2026-08).
    .frame(minHeight: minH, alignment: .bottomLeading)
    .background(multilineGlassBackground)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .animation(.easeOut(duration: 0.18), value: model.text)
    .onChange(of: isFocused) { focused in
      model.onFocusChanged(focused)
    }
    .onChange(of: focusBinding.state) { state in
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
    .background(
      // Intrinsic-height reporter — the DEADLOCK-FREE kind. Reporting the
      // composed frame's own height is circular: the Flutter host proposes the
      // current box height, so the report always equals the proposal and the
      // box never grows (measured on device: text clipped to one line forever).
      // Instead a HIDDEN measuring Text — same width, same line-limit range,
      // `fixedSize(vertical: true)` so it takes its IDEAL height — reports the
      // content's true wrapped height; the Flutter box grows to match (clamped
      // by maxLines' ceiling there).
      HeightReporter(model: model) { height in
        model.onHeightChanged?(Double((height).rounded()))
      }
      .opacity(0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    )
  }

  private var singleLineBody: some View {
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
      // The `.id` epoch destroys + recreates ONLY this background subtree on
      // a theme flip — trait mutation alone leaves the material stale.
      Color.clear.glassEffect(.regular, in: .capsule)
        .id(appearanceEpoch.epoch)
    } else {
      Color(.systemGray6)
    }
  }

  /// Multiline variant of [glassBackground]: a rounded rectangle, not a capsule
  /// — a `Capsule` taller than ~2× its width degenerates to a stadium with
  /// semicircular ends, wrong for a growing composer. Continuous corners match
  /// the kit's pill language; same `.id` epoch theme-recreate rule.
  @ViewBuilder
  private var multilineGlassBackground: some View {
    if #available(iOS 26.0, *) {
      Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .id(appearanceEpoch.epoch)
    } else {
      Color(.systemGray6)
    }
  }
}

/// Invisible intrinsic-height measurer. A hidden `Text` mirroring the field's
/// content (same width via the background placement, same lineLimit range,
/// `fixedSize(vertical: true)` for its ideal wrapped height) whose measured
/// height is reported so Flutter can grow the platform-view slot. NOT the
/// composed frame's height — that is circular with the host's proposal.
/// iOS 16+ (range lineLimit), matching the multiline body it serves.
@available(iOS 16.0, *)
private struct HeightReporter: View {
  @ObservedObject var model: TextModel
  let onChange: (CGFloat) -> Void

  var body: some View {
    Text(model.text.isEmpty ? " " : model.text)
      .font(.body)
      .lineLimit((model.minLines ?? 1)...(model.maxLines ?? Int.max))
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 10)
      .background(
        GeometryReader { proxy in
          Color.clear
            .onChange(of: proxy.size.height) { h in onChange(h) }
            .onAppear { onChange(proxy.size.height) }
        }
      )
  }
}
