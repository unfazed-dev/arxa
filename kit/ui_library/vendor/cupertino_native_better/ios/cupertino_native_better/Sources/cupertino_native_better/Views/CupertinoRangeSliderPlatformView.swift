import Flutter
import UIKit

/// Routes each touch to the nearer of the two `UISlider` thumbs so the native
/// control owns the press. iOS-26 Liquid Glass on a slider thumb fires in the
/// highlighted/pressed state — which only happens when the `UISlider` itself
/// receives the touch. Two stacked full-width sliders would otherwise let only
/// the top one ever receive touches; this override restores per-thumb press →
/// genuine glass on BOTH thumbs, matching a standalone [CNSlider].
final class RangeSliderContainer: UIView {
  weak var lowSlider: UISlider?
  weak var highSlider: UISlider?
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard bounds.contains(point), let low = lowSlider, let high = highSlider else {
      return super.hitTest(point, with: event)
    }
    let lowX = thumbCenter(in: low).x
    let highX = thumbCenter(in: high).x
    // Collapsed (overlapping — closer than one thumb-width): hand the grab to the
    // "opener" so a collapsed pair is always escapable — high thumb near min
    // (drag right to reopen), low thumb near max (drag left).
    if abs(lowX - highX) < thumbDiameter(in: low) {
      return (lowX + highX) / 2 < bounds.midX ? high : low
    }
    return abs(point.x - lowX) <= abs(point.x - highX) ? low : high
  }

  private func thumbCenter(in slider: UISlider) -> CGPoint {
    let b = slider.bounds
    let track = slider.trackRect(forBounds: b)
    let thumb = slider.thumbRect(forBounds: b, trackRect: track, value: slider.value)
    return convert(CGPoint(x: thumb.midX, y: thumb.midY), from: slider)
  }

  private func thumbDiameter(in slider: UISlider) -> CGFloat {
    let b = slider.bounds
    let track = slider.trackRect(forBounds: b)
    return slider.thumbRect(forBounds: b, trackRect: track, value: slider.value).width
  }
}

/// Native two-thumb range slider platform view. Two real `UISlider`s (transparent
/// tracks → only their glass thumbs show) sit above a natively-drawn combined
/// track, inside a [RangeSliderContainer] that routes touches to the nearer
/// thumb. Because the thumbs are real `UISlider` thumbs, iOS 26 auto-applies
/// Liquid Glass and fires it on press — identical to a standalone slider.
///
/// Each thumb traverses the FULL min…max track, exactly like a standalone
/// `CupertinoSliderPlatformView` (the radius slider): UIKit positions a thumb
/// so its centre travels `trackRect.width − thumbRect.width`, i.e. the thumb
/// edges reach the track ends — the track fills fully. In the interior the two
/// thumbs stop when they touch (one thumb-width of centre separation → edge to
/// edge, no overlap, no gap). At the extremes they may collapse: when one thumb
/// is pinned at min the other can slide onto it → `[min, min]`, and when one is
/// pinned at max → `[max, max]`. Overlap is confined to a thumb pinned at an
/// extreme — two thumbs never stack in the interior. No value remapping — the
/// readout is the raw thumb position. When collapsed, the "opener" thumb stays
/// on top and receives the grab (high at min → drag right; low at max → drag
/// left), so a collapsed pair is always escapable.
class CupertinoRangeSliderPlatformView: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let container: RangeSliderContainer
  private let lowSlider: UISlider
  private let highSlider: UISlider
  private let inactiveTrack = UIView()
  private let activeTrack = UIView()

  private var minValue: Double = 0
  private var maxValue: Double = 1
  private var lowValue: Double = 0
  private var highValue: Double = 1
  private var trackTint: UIColor?
  private var trackBgTint: UIColor?
  private var thumbTint: UIColor?

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeRangeSlider_\(viewId)", binaryMessenger: messenger)
    self.container = RangeSliderContainer(frame: frame)
    self.lowSlider = UISlider()
    self.highSlider = UISlider()
    super.init()

    var isDark = false
    if let dict = args as? [String: Any] {
      if let v = dict["min"] as? NSNumber { minValue = v.doubleValue }
      if let v = dict["max"] as? NSNumber { maxValue = v.doubleValue }
      if let v = dict["lowValue"] as? NSNumber { lowValue = v.doubleValue }
      if let v = dict["highValue"] as? NSNumber { highValue = v.doubleValue }
      if let v = dict["enabled"] as? NSNumber {
        lowSlider.isEnabled = v.boolValue
        highSlider.isEnabled = v.boolValue
      }
      if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
      if let style = dict["style"] as? [String: Any] {
        if let n = style["trackTint"] as? NSNumber { trackTint = Self.colorFromARGB(n.intValue) }
        if let n = style["trackBackgroundTint"] as? NSNumber { trackBgTint = Self.colorFromARGB(n.intValue) }
        if let n = style["thumbTint"] as? NSNumber { thumbTint = Self.colorFromARGB(n.intValue) }
      }
    }
    lowValue = min(max(lowValue, minValue), maxValue)
    highValue = min(max(highValue, minValue), maxValue)
    if highValue < lowValue { swap(&lowValue, &highValue) }

    container.backgroundColor = .clear
    if #available(iOS 13.0, *) {
      container.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
    container.lowSlider = lowSlider
    container.highSlider = highSlider
    container.onLayout = { [weak self] in self?.layoutTrack() }

    for s in [lowSlider, highSlider] {
      s.translatesAutoresizingMaskIntoConstraints = false
      s.minimumValue = Float(minValue)
      s.maximumValue = Float(maxValue)
      // Transparent tracks: only the glass thumbs render; the combined track is
      // drawn behind in the same view so the thumbs refract in-layer content.
      s.minimumTrackTintColor = .clear
      s.maximumTrackTintColor = .clear
      if let t = thumbTint { s.thumbTintColor = t }
      container.addSubview(s)
    }
    NSLayoutConstraint.activate([
      lowSlider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      lowSlider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      lowSlider.topAnchor.constraint(equalTo: container.topAnchor),
      lowSlider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      highSlider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      highSlider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      highSlider.topAnchor.constraint(equalTo: container.topAnchor),
      highSlider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    inactiveTrack.backgroundColor = trackBgTint ?? UIColor(white: 0, alpha: 0.12)
    activeTrack.backgroundColor = trackTint ?? UIColor.systemBlue
    container.insertSubview(inactiveTrack, belowSubview: lowSlider)
    container.insertSubview(activeTrack, belowSubview: lowSlider)

    lowSlider.setValue(Float(lowValue), animated: false)
    highSlider.setValue(Float(highValue), animated: false)
    lowSlider.addTarget(self, action: #selector(onLowChanged(_:)), for: .valueChanged)
    highSlider.addTarget(self, action: #selector(onHighChanged(_:)), for: .valueChanged)

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func view() -> UIView { container }

  // MARK: - native → Dart

  /// Low thumb drag. Interior: clamps to `[min, high − sep]` so it stops
  /// touching the high thumb (never crosses). When the high thumb is pinned at
  /// max the gap releases so low can slide up onto it → collapse to `[max, max]`.
  @objc private func onLowChanged(_ s: UISlider) {
    let sep = sepValue()
    let minGap = (highValue >= maxValue) ? 0 : sep
    lowValue = max(minValue, min(Double(s.value), highValue - minGap))
    layoutTrack()
    emit()
  }

  /// High thumb drag. Interior: clamps to `[low + sep, max]`. When the low thumb
  /// is pinned at min the gap releases so high can slide down onto it → `[min, min]`.
  @objc private func onHighChanged(_ s: UISlider) {
    let sep = sepValue()
    let minGap = (lowValue <= minValue) ? 0 : sep
    highValue = min(maxValue, max(Double(s.value), lowValue + minGap))
    layoutTrack()
    emit()
  }

  private func emit() {
    channel.invokeMethod("valuesChanged", arguments: ["lowValue": lowValue, "highValue": highValue])
  }

  // MARK: - Dart → native

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setValues":
      guard let a = call.arguments as? [String: Any],
            let lo = (a["lowValue"] as? NSNumber)?.doubleValue,
            let hi = (a["highValue"] as? NSNumber)?.doubleValue else {
        result(FlutterError(code: "bad_args", message: "lowValue/highValue", details: nil)); return
      }
      lowValue = min(max(lo, minValue), maxValue)
      highValue = min(max(hi, minValue), maxValue)
      if highValue < lowValue { swap(&lowValue, &highValue) }
      layoutTrack(); result(nil)
    case "setRange":
      guard let a = call.arguments as? [String: Any],
            let mn = (a["min"] as? NSNumber)?.doubleValue,
            let mx = (a["max"] as? NSNumber)?.doubleValue else {
        result(FlutterError(code: "bad_args", message: "min/max", details: nil)); return
      }
      minValue = mn; maxValue = mx
      for s in [lowSlider, highSlider] { s.minimumValue = Float(mn); s.maximumValue = Float(mx) }
      lowValue = min(max(lowValue, mn), mx)
      highValue = min(max(highValue, mn), mx)
      if highValue < lowValue { swap(&lowValue, &highValue) }
      layoutTrack(); result(nil)
    case "setEnabled":
      guard let a = call.arguments as? [String: Any], let e = (a["enabled"] as? NSNumber)?.boolValue else {
        result(FlutterError(code: "bad_args", message: "enabled", details: nil)); return
      }
      lowSlider.isEnabled = e; highSlider.isEnabled = e; result(nil)
    case "setStyle":
      guard let a = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "style", details: nil)); return
      }
      if let n = a["trackTint"] as? NSNumber { trackTint = Self.colorFromARGB(n.intValue); activeTrack.backgroundColor = trackTint }
      if let n = a["trackBackgroundTint"] as? NSNumber { trackBgTint = Self.colorFromARGB(n.intValue); inactiveTrack.backgroundColor = trackBgTint }
      if let n = a["thumbTint"] as? NSNumber { thumbTint = Self.colorFromARGB(n.intValue); lowSlider.thumbTintColor = thumbTint; highSlider.thumbTintColor = thumbTint }
      result(nil)
    case "setBrightness":
      if let a = call.arguments as? [String: Any], let d = (a["isDark"] as? NSNumber)?.boolValue {
        if #available(iOS 13.0, *) { container.overrideUserInterfaceStyle = d ? .dark : .light }
        result(nil)
      } else { result(FlutterError(code: "bad_args", message: "isDark", details: nil)) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - touch separation (radius-slider geometry)

  /// Minimum value gap so the two thumb circles touch edge-to-edge (no overlap,
  /// no gap). Measured against the SAME centre travel a single slider's thumb
  /// uses — `thumbRect(max).midX − thumbRect(min).midX` (= trackWidth −
  /// thumbWidth) — so the thumbs fill the track exactly like the radius slider,
  /// then stop the instant their edges meet.
  private func sepValue() -> Double {
    let b = lowSlider.bounds
    let track = lowSlider.trackRect(forBounds: b)
    let c0 = lowSlider.thumbRect(forBounds: b, trackRect: track, value: lowSlider.minimumValue).midX
    let c1 = lowSlider.thumbRect(forBounds: b, trackRect: track, value: lowSlider.maximumValue).midX
    let travel = c1 - c0
    let thumb = lowSlider.thumbRect(forBounds: b, trackRect: track, value: lowSlider.value).width
    guard travel > 0, thumb > 0 else { return 0 }
    // Cap at half the range so a tiny range can't invert the thumbs.
    let frac = min(Double(thumb / travel), 0.5)
    return frac * (maxValue - minValue)
  }

  // MARK: - combined track + positioning

  /// Positions both UISliders at their (full-track) values for the current
  /// geometry (handles initial layout and any resize/rotation) and redraws the
  /// combined track between the actual thumb centres.
  private func layoutTrack() {
    let b = container.bounds
    guard b.width > 0 else { return }

    lowSlider.setValue(Float(lowValue), animated: false)
    highSlider.setValue(Float(highValue), animated: false)

    let lowBounds = lowSlider.bounds
    let lowTrack = lowSlider.trackRect(forBounds: lowBounds)
    let track = container.convert(lowTrack, from: lowSlider)
    guard track.width > 0 else { return }
    let lowThumb = container.convert(
      lowSlider.thumbRect(forBounds: lowBounds, trackRect: lowTrack, value: lowSlider.value),
      from: lowSlider)
    let highThumb = container.convert(
      highSlider.thumbRect(forBounds: highSlider.bounds,
                           trackRect: highSlider.trackRect(forBounds: highSlider.bounds),
                           value: highSlider.value),
      from: highSlider)

    let h: CGFloat = 4
    inactiveTrack.frame = CGRect(x: track.minX, y: track.midY - h / 2, width: track.width, height: h)
    // Active track meets each thumb at its CENTRE, exactly like the radius
    // slider: UIKit draws a single slider's coloured track up to the thumb
    // centre and the thumb caps the boundary. The glass thumb reads as a disc
    // (content behind blurs, doesn't bleed through), so capping at the centre
    // gives the same clean boundary the radius slider has.
    activeTrack.frame = CGRect(x: lowThumb.midX, y: track.midY - h / 2,
                               width: max(0, highThumb.midX - lowThumb.midX), height: h)
    inactiveTrack.layer.cornerRadius = h / 2
    activeTrack.layer.cornerRadius = h / 2

    // Collapsed (overlapping): keep the grabbable opener on top — high near min,
    // low near max — so the visible foreground thumb matches the hitTest target.
    if abs(lowThumb.midX - highThumb.midX) < lowThumb.width {
      let wantLowOnTop = (lowThumb.midX + highThumb.midX) / 2 > container.bounds.midX
      if wantLowOnTop, container.subviews.last !== lowSlider {
        container.bringSubviewToFront(lowSlider)
      } else if !wantLowOnTop, container.subviews.last !== highSlider {
        container.bringSubviewToFront(highSlider)
      }
    }
  }

  private static func colorFromARGB(_ argb: Int) -> UIColor { ImageUtils.colorFromARGB(argb) }
}
