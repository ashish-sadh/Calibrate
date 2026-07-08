import UIKit

/// #1035: app-wide select-all-on-focus for numeric text fields.
///
/// Every numeric `TextField` in the app is a bare SwiftUI `TextField(text:)` with a
/// number/decimal keyboard and no select-all behavior, so focusing a pre-filled field
/// (Servings `1`, weight `220`, reps `10`) places the caret and the first digit *inserts*
/// rather than replaces — `1`→typing `2` yields `21`. Rather than hand-patch ~33 fields
/// across 18 files (and miss every future one), install ONE global observer: when any
/// numeric-keyboard field begins editing, select its whole contents so the first keystroke
/// replaces the value. Tapping an already-focused field again still places the caret to edit
/// in place (select-all only fires on the begin-editing transition).
enum NumericFieldSelectAll {
    private nonisolated(unsafe) static var observer: NSObjectProtocol?

    @MainActor static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UITextField.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let field = note.object as? UITextField else { return }
            switch field.keyboardType {
            case .numberPad, .decimalPad, .asciiCapableNumberPad, .numbersAndPunctuation:
                // Defer one runloop so it runs after UIKit sets the initial caret position;
                // only select when there's actually pre-filled content to replace.
                DispatchQueue.main.async {
                    guard let text = field.text, !text.isEmpty, field.isFirstResponder else { return }
                    field.selectAll(nil)
                }
            default:
                break
            }
        }
    }
}
