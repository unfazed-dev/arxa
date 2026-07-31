import SwiftUI

struct CupertinoSwitchView: View {
  @ObservedObject var model: SwitchModel

  var body: some View {
    configuredToggle
      // Prevent SwiftUI's automatic keyboard-avoidance from pushing the
      // switch upward when the on-screen keyboard appears (Issue #4).
      .ignoresSafeArea(.keyboard)
  }

  @ViewBuilder
  private var configuredToggle: some View {
    // VoiceOver gap fix: give the Toggle its real title — `.labelsHidden()`
    // hides it visually but keeps it as the accessibility label, so the AX
    // tree no longer exposes an unlabeled switch (kit ticket #13).
    let base = Toggle(model.accessibilityLabel ?? "", isOn: $model.value)
      .labelsHidden()
      .disabled(!model.enabled)

    if #available(iOS 14.0, *) {
      if #available(iOS 15.0, *) {
        base
          .onChange(of: model.value) { newValue in
            model.onChange(newValue)
          }
          .tint(model.tintColor)
      } else {
        base
          .onChange(of: model.value) { newValue in
            model.onChange(newValue)
          }
          .accentColor(model.tintColor)
      }
    } else {
      if #available(iOS 15.0, *) {
        base
          .onReceive(model.$value) { newValue in
            model.onChange(newValue)
          }
          .tint(model.tintColor)
      } else {
        base
          .onReceive(model.$value) { newValue in
            model.onChange(newValue)
          }
          .accentColor(model.tintColor)
      }
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
