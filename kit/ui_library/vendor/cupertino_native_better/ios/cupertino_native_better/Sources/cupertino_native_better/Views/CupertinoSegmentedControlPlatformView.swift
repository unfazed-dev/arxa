import Flutter
import UIKit

class CupertinoSegmentedControlPlatformView: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let container: UIView
  // `var`, not `let`: theme flips REPLACE the control instance — see
  // replaceControlForThemeFlip.
  private var control: UISegmentedControl
  private var labels: [String] = []
  private var symbols: [String] = []
  private var perSymbolSizes: [CGFloat?] = []
  private var perSymbolColors: [UIColor?] = []
  private var perSymbolPalettes: [[UIColor]] = []
  private var perSymbolModes: [String?] = []
  private var perSymbolGradientEnabled: [NSNumber?] = []
  private var defaultIconSize: CGFloat? = nil
  private var defaultIconColor: UIColor? = nil
  private var defaultIconPalette: [UIColor] = []
  private var defaultIconRenderingMode: String? = nil
  private var defaultIconGradientEnabled: Bool = false
  private let settleReplay = CNAppearanceSettleReplay()

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeSegmentedControl_\(viewId)", binaryMessenger: messenger)
    self.container = UIView(frame: frame)
    self.control = UISegmentedControl(items: [])

    var labels: [String] = []
    var sfSymbols: [String] = []
    var selectedIndex: Int = UISegmentedControl.noSegment
    var enabled: Bool = true
    var isDark: Bool = false
    var tint: UIColor? = nil

    if let dict = args as? [String: Any] {
      if let arr = dict["labels"] as? [String] { labels = arr }
      if let arr = dict["sfSymbols"] as? [String] { sfSymbols = arr }
      if let sizes = dict["sfSymbolSizes"] as? [NSNumber] {
        self.perSymbolSizes = sizes.map { CGFloat(truncating: $0) }
      }
      if let colors = dict["sfSymbolColors"] as? [NSNumber] {
        self.perSymbolColors = colors.map { Self.colorFromARGB($0.intValue) }
      }
      if let palettes = dict["sfSymbolPaletteColors"] as? [[NSNumber]] {
        self.perSymbolPalettes = palettes.map { $0.map { Self.colorFromARGB($0.intValue) } }
      }
      if let modes = dict["sfSymbolRenderingModes"] as? [String?] {
        self.perSymbolModes = modes
      }
      if let gradients = dict["sfSymbolGradientEnabled"] as? [NSNumber?] {
        self.perSymbolGradientEnabled = gradients
      }
      if let v = dict["selectedIndex"] as? NSNumber { selectedIndex = v.intValue }
      if let v = dict["enabled"] as? NSNumber { enabled = v.boolValue }
      if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let n = style["tint"] as? NSNumber { tint = Self.colorFromARGB(n.intValue) }
        if let n = style["iconColor"] as? NSNumber { self.defaultIconColor = Self.colorFromARGB(n.intValue) }
        if let s = style["iconSize"] as? NSNumber { self.defaultIconSize = CGFloat(truncating: s) }
        if let arr = style["iconPaletteColors"] as? [NSNumber] { self.defaultIconPalette = arr.map { Self.colorFromARGB($0.intValue) } }
        if let mode = style["iconRenderingMode"] as? String { self.defaultIconRenderingMode = mode }
        if let g = style["iconGradientEnabled"] as? NSNumber { self.defaultIconGradientEnabled = g.boolValue }
      }
    }

    super.init()

    container.backgroundColor = .clear
    if #available(iOS 13.0, *) {
      container.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    self.labels = labels
    self.symbols = sfSymbols
    rebuildSegments()
    control.selectedSegmentIndex = selectedIndex
    control.isEnabled = enabled
    if #available(iOS 13.0, *), let c = tint { control.selectedSegmentTintColor = c }

    control.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(control)
    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      control.topAnchor.constraint(equalTo: container.topAnchor),
      control.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])

    control.addTarget(self, action: #selector(onChanged(_:)), for: .valueChanged)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getIntrinsicSize":
        let size = self.control.intrinsicContentSize
        result(["width": Double(size.width), "height": Double(size.height)])
      case "setSelectedIndex":
        if let args = call.arguments as? [String: Any], let idx = (args["index"] as? NSNumber)?.intValue {
          UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.control.selectedSegmentIndex = idx
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing index", details: nil)) }
      case "setEnabled":
        if let args = call.arguments as? [String: Any], let e = (args["enabled"] as? NSNumber)?.boolValue {
          UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.control.isEnabled = e
            self.control.alpha = e ? 1.0 : 0.5
          }
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing enabled", details: nil)) }
      case "setStyle":
        if let args = call.arguments as? [String: Any] {
          UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            if #available(iOS 13.0, *), let n = args["tint"] as? NSNumber {
              self.control.selectedSegmentTintColor = Self.colorFromARGB(n.intValue)
            }
          }
          if let n = args["iconColor"] as? NSNumber { self.defaultIconColor = Self.colorFromARGB(n.intValue) }
          if let s = args["iconSize"] as? NSNumber { self.defaultIconSize = CGFloat(truncating: s) }
          self.rebuildSegments()
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing style", details: nil)) }
      case "setBrightness":
        if let args = call.arguments as? [String: Any], let isDark = (args["isDark"] as? NSNumber)?.boolValue {
          CNAppearance.trace("CNSegmentedControl", "setBrightness isDark=\(isDark)")
          if #available(iOS 13.0, *) {
            self.applyBrightness(isDark)
            // After a rapid flip storm, replay the final state once so a
            // mid-storm-coalesced render can't strand this view on the
            // previous theme (14-01 clip). See CNAppearanceSettleReplay.
            self.settleReplay.poke { [weak self] in self?.applyBrightness(isDark) }
          }
          CNAppearance.trace("CNSegmentedControl", "setBrightness applied")
          result(nil)
        } else { result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil)) }
      case "setInteractive":
        if let args = call.arguments as? [String: Any],
           let interactive = (args["interactive"] as? NSNumber)?.boolValue {
          NSLog("[CN Seg] setInteractive=\(interactive)")
          self._cnSetInteractiveRecursive(self.container, interactive)
          self._cnSetInteractiveRecursive(self.control, interactive)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  /// Push the in-app brightness to every tier of this segmented control.
  /// Extracted from the `setBrightness` handler so
  /// `CNAppearanceSettleReplay` can replay it verbatim after a rapid flip
  /// storm (14-01 clip).
  @available(iOS 13.0, *)
  private func applyBrightness(_ isDark: Bool) {
    CNAppearance.applyInstantly(forcing: [self.container, self.control]) {
      self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
      // Full instance replacement. The iOS 26 selection lens is glass;
      // rebuilding SEGMENTS (round 3) cured the permanently-frozen
      // double lens (22:51 clip) but the lens's in-flight slide still
      // leaves frozen smears on the segments it passed over for ~1-2s
      // at rest (10-11 clip, every flip — the flip is triggered by a
      // tap on THIS control, so the slide is always mid-flight when
      // brightness lands). A fresh control has a fresh lens at rest on
      // the selected segment — no in-flight frames to freeze. Same
      // cure as the popup button's instance replacement.
      self.replaceControlForThemeFlip()
    }
  }

  private func _cnSetInteractiveRecursive(_ view: UIView?, _ interactive: Bool) {
    guard let view = view else { return }
    view.isUserInteractionEnabled = interactive
    for sub in view.subviews { _cnSetInteractiveRecursive(sub, interactive) }
  }

  @objc private func onChanged(_ sender: UISegmentedControl) {
    channel.invokeMethod("valueChanged", arguments: ["index": sender.selectedSegmentIndex])
  }

  // Use shared utility functions
  private static func colorFromARGB(_ argb: Int) -> UIColor {
    return ImageUtils.colorFromARGB(argb)
  }

  private func rebuildSegments() {
    // removeAllSegments() resets selectedSegmentIndex to noSegment — preserve
    // the selection across rebuilds (setStyle and brightness flips rebuild).
    let selected = control.selectedSegmentIndex
    control.removeAllSegments()
    let count = max(labels.count, symbols.count)
    for idx in 0..<count {
      if idx < symbols.count, var image = UIImage(systemName: symbols[idx]) {
        if let size = (idx < perSymbolSizes.count ? perSymbolSizes[idx] : nil) ?? defaultIconSize {
          let cfg = UIImage.SymbolConfiguration(pointSize: size)
          if let newImg = image.applyingSymbolConfiguration(cfg) { image = newImg }
        }
        // Rendering mode selection
        let mode = (idx < perSymbolModes.count ? perSymbolModes[idx] : nil) ?? defaultIconRenderingMode
        if let mode = mode {
          switch mode {
          case "hierarchical":
            if #available(iOS 15.0, *), let color = (idx < perSymbolColors.count ? perSymbolColors[idx] : nil) ?? defaultIconColor {
              let cfg = UIImage.SymbolConfiguration(hierarchicalColor: color)
              if let newImg = image.applyingSymbolConfiguration(cfg) { image = newImg }
            }
          case "palette":
            if #available(iOS 15.0, *), !((idx < perSymbolPalettes.count) ? perSymbolPalettes[idx].isEmpty : defaultIconPalette.isEmpty) {
              let colors = (idx < perSymbolPalettes.count && !perSymbolPalettes[idx].isEmpty) ? perSymbolPalettes[idx] : defaultIconPalette
              let cfg = UIImage.SymbolConfiguration(paletteColors: colors)
              if let newImg = image.applyingSymbolConfiguration(cfg) { image = newImg }
            }
          case "multicolor":
            if #available(iOS 15.0, *) {
              let cfg = UIImage.SymbolConfiguration.preferringMulticolor()
              if let newImg = image.applyingSymbolConfiguration(cfg) { image = newImg }
            }
          default:
            break
          }
        } else if let color = (idx < perSymbolColors.count ? perSymbolColors[idx] : nil) ?? defaultIconColor {
          if #available(iOS 13.0, *) {
            image = image.withTintColor(color, renderingMode: .alwaysOriginal)
          }
        }
        // Gradient toggle (built-in in SF Symbols 7). If available, prefer gradient.
        let gradientEnabled = (idx < perSymbolGradientEnabled.count ? perSymbolGradientEnabled[idx]?.boolValue : nil) ?? defaultIconGradientEnabled
        if gradientEnabled {
          // Note: Using future API for built-in gradients when available. Currently no-op on older SDKs.
          // if #available(iOS 18.0, *), let cfg = UIImage.SymbolConfiguration.preferringGradient() { image = image.applyingSymbolConfiguration(cfg) ?? image }
        }
        control.insertSegment(with: image, at: idx, animated: false)
      } else if idx < labels.count {
        control.insertSegment(withTitle: labels[idx], at: idx, animated: false)
      } else {
        control.insertSegment(withTitle: "", at: idx, animated: false)
      }
    }
    control.selectedSegmentIndex = selected
  }

  /// Swaps `self.control` for a fresh instance on a theme flip — see the
  /// setBrightness call site for the device evidence. Content rebuilds from
  /// fields via `rebuildSegments()`; the rest is captured from the old
  /// control (selection, tint, enabled/alpha, interaction). The fresh
  /// control is fully configured BEFORE entering the hierarchy, inside the
  /// caller's `applyInstantly`, so no intermediate frame renders.
  private func replaceControlForThemeFlip() {
    let old = self.control
    let newControl = UISegmentedControl(items: [])
    newControl.translatesAutoresizingMaskIntoConstraints = false
    if #available(iOS 13.0, *) {
      newControl.selectedSegmentTintColor = old.selectedSegmentTintColor
    }
    newControl.isEnabled = old.isEnabled
    newControl.alpha = old.alpha
    newControl.isUserInteractionEnabled = old.isUserInteractionEnabled
    let selected = old.selectedSegmentIndex
    self.control = newControl
    rebuildSegments()
    newControl.selectedSegmentIndex = selected
    newControl.addTarget(self, action: #selector(onChanged(_:)), for: .valueChanged)
    old.removeFromSuperview()
    container.addSubview(newControl)
    NSLayoutConstraint.activate([
      newControl.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      newControl.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      newControl.topAnchor.constraint(equalTo: container.topAnchor),
      newControl.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }
}
