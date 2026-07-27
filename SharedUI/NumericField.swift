import SwiftUI

/// Numeric text field with select-all-on-focus — the cross-platform companion to
/// iOS's global `NumericFieldSelectAll` observer (#1035). iOS installs ONE
/// `UITextField.textDidBeginEditingNotification` observer (wired in `DriftApp.init`)
/// that selects-all on every numeric-keypad field, so on iOS this is just a bare
/// `TextField` + keypad and the observer does the work. Android/Compose has no
/// global hook, so we drive skip-ui's `selection:` binding directly: on the
/// focus-gain transition, select the whole value so the first keystroke replaces.
/// Re-tapping an already-focused field does NOT re-fire (focus stays true), so the
/// caret lands where tapped — parity with #1035. (#1097)
struct NumericField: View {
    let placeholder: String
    @Binding var text: String
    var decimal: Bool = true

    #if os(Android)
    @State var selection: TextSelection?
    @FocusState var focused: Bool
    #endif

    init(_ placeholder: String, text: Binding<String>, decimal: Bool = true) {
        self.placeholder = placeholder
        self._text = text
        self.decimal = decimal
    }

    var body: some View {
        #if os(Android)
        TextField(placeholder, text: $text, selection: $selection)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .focused($focused)
            .onChange(of: focused) { _, isFocused in
                guard isFocused, !text.isEmpty else { return }
                // Defer one runloop so the select lands AFTER Compose places the
                // tap caret — the exact analog of #1035's DispatchQueue.main.async
                // (which runs after UIKit sets the initial caret position).
                DispatchQueue.main.async {
                    guard focused, !text.isEmpty else { return }
                    selection = TextSelection(range: TextSelectionRange(text.startIndex..<text.endIndex, in: text))
                }
            }
        #else
        TextField(placeholder, text: $text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
        #endif
    }
}
