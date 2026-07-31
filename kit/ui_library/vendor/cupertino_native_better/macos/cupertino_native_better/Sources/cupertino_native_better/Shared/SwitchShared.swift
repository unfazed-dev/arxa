import SwiftUI

import SwiftUI

struct CupertinoSwitchView: View {
  @ObservedObject var model: SwitchModel

  var body: some View {
    // VoiceOver gap fix: give the Toggle its real title — `.labelsHidden()`
    // hides it visually but keeps it as the accessibility label (kit #13).
    let base = Toggle(model.accessibilityLabel ?? "", isOn: $model.value)
      .labelsHidden()
      // On macOS a default Toggle renders as a checkbox; force the switch
      // style so CNSwitch is a real toggle (iOS already defaults to a switch).
      .toggleStyle(.switch)
      .disabled(!model.enabled)
      .onChange(of: model.value) { newValue in
        model.onChange(newValue)
      }

    if #available(macOS 12.0, *) {
      base.tint(model.tintColor)
    } else {
      base.accentColor(model.tintColor)
    }
  }
}

class SwitchModel: ObservableObject {
  @Published var value: Bool
  @Published var enabled: Bool
  @Published var tintColor: Color = .accentColor
  /// VoiceOver label surfaced through the (visually hidden) Toggle title.
  @Published var accessibilityLabel: String?
  var onChange: (Bool) -> Void

  init(
    value: Bool, enabled: Bool, accessibilityLabel: String? = nil,
    onChange: @escaping (Bool) -> Void
  ) {
    self.value = value
    self.enabled = enabled
    self.accessibilityLabel = accessibilityLabel
    self.onChange = onChange
  }
}
