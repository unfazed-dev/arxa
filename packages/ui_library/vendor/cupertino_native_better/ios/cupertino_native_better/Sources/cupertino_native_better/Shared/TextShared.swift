import SwiftUI

/// Two-way model for [CNTextField], mirroring [SliderModel].
///
/// The search bar's known limitation is that its `setText`/`focus` handlers
/// are stubs — it has no bridged model, so a Flutter `TextEditingController`
/// can't drive the native field. A text input's contract is stronger: form
/// submission reads `controller.text` after the user types, and may also set
/// it programmatically (autofill, validation reset). So [CNTextField] holds
/// its text in an `ObservableObject` the method channel mutates, and the
/// SwiftUI `TextField` binds to `$model.text` — both directions work.
///
/// `onChange` fires on every keystroke (forwarded to Flutter as `textChanged`);
/// the Flutter side writes the value back into the host controller, so reads
/// stay in sync without a round-tr.
class TextModel: ObservableObject {
  /// Current text. Mutated by SwiftUI on keystroke and by the method channel
  /// on `setText`/`clear`. Binding it to `TextField($model.text)` is what makes
  /// programmatic control work both ways.
  @Published var text: String

  /// Placeholder text shown when empty.
  @Published var placeholder: String

  /// `true` → `SecureField` (passwords / OTP codes). Set once at creation.
  @Published var isSecure: Bool

  /// Autofocus on appearance.
  @Published var autofocus: Bool

  /// Keyboard type: "default", "number", "emailAddress", "phone".
  @Published var keyboardType: String

  /// Accent / caret / clear-button tint.
  @Published var tint: Color

  /// Text color (nil → `.primary`).
  @Published var textColor: Color?

  /// Placeholder color (nil → `.secondary`).
  @Published var placeholderColor: Color?

  // Focus is owned by SwiftUI via @FocusState in the view, not here — publishing
  // it from the model would race the SwiftUI focus system. The view forwards
  // focus changes back through `onFocusChanged`.

  /// Fired on every keystroke with the new value.
  var onChange: (String) -> Void

  /// Fired on submit (return key).
  var onSubmit: (String) -> Void

  /// Fired when focus enters/leaves the field.
  var onFocusChanged: (Bool) -> Void

  init(
    text: String,
    placeholder: String,
    isSecure: Bool,
    autofocus: Bool,
    keyboardType: String,
    tint: Color,
    textColor: Color?,
    placeholderColor: Color?,
    onChange: @escaping (String) -> Void,
    onSubmit: @escaping (String) -> Void,
    onFocusChanged: @escaping (Bool) -> Void
  ) {
    self.text = text
    self.placeholder = placeholder
    self.isSecure = isSecure
    self.autofocus = autofocus
    self.keyboardType = keyboardType
    self.tint = tint
    self.textColor = textColor
    self.placeholderColor = placeholderColor
    self.onChange = onChange
    self.onSubmit = onSubmit
    self.onFocusChanged = onFocusChanged
  }

  // MARK: - Keyboard

  /// Maps the string sent from Flutter to a SwiftUI `KeyboardType`.
  var uiKeyboardType: UIKeyboardType {
    switch keyboardType {
    case "number": return .numberPad
    case "phone": return .phonePad
    case "emailAddress": return .emailAddress
    case "url": return .URL
    default: return .default
    }
  }
}
