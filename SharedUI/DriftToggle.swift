import SwiftUI

/// The iPhone's switch, drawn.
///
/// SkipUI hands `Toggle` straight to Material3's `Switch`, and Material's OFF
/// state is a visibly different control from UIKit's: a 2dp outline around the
/// track and a small dark thumb about half the track's height, where iOS draws
/// an unoutlined grey capsule with a near-full-height white knob. Side by side
/// (#1197 drive, `SharedUI/CoachSharingCard.swift`'s seven consent rows) they do
/// not read as the same app.
///
/// Neither of the two hooks that could fix it in place is reachable from Fuse:
/// `.toggleStyle(_:)` is `return self` in
/// `skip-fuse-ui/Sources/SkipSwiftUI/Controls/Toggle.swift`, and skip-ui's
/// `.material3ColorScheme` — which owns `uncheckedBorderColor`/
/// `uncheckedThumbColor` — takes a `@Composable` closure and so is
/// transpiled-only, exactly the wall `IOSSegmentedPicker` hit on
/// `.material3SegmentedButton`. `.tint()` reaches only `checkedTrackColor`
/// (`skip-ui/.../Controls/Toggle.swift:69`), which is why the ON state already
/// matched and the OFF state never could. Drawing the control is what's left.
///
/// Geometry and colours are MEASURED off an iPhone 17 Pro (iOS 26.5, light) —
/// the accessibility tree reports the switch as `63 × 28` points, and the pixels
/// give a `#C3C3C5` off-track, a white knob spanning 36pt inset 2pt, and
/// `#FF375F` when on, which is `Theme.accent` exactly. Not eyeballed.
///
/// Declared outside any `os(Android)` gate on purpose: SharedUI also compiles in
/// Skip's Darwin bridging pass, where anything behind that gate is invisible and
/// a call site in a sibling file fails with "cannot find … in scope".
struct IOSSwitch: View {
    @Binding var isOn: Bool
    /// Drawn controls don't inherit `.disabled()` the way a real `Toggle` does,
    /// so callers that gate on an in-flight write pass it explicitly.
    var enabled = true

    private static let trackWidth: CGFloat = 63
    private static let trackHeight: CGFloat = 28
    private static let knobWidth: CGFloat = 36
    private static let knobInset: CGFloat = 2
    private static let offTrack = Color(hex: "C3C3C5")

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Theme.accent : Self.offTrack)
                .frame(width: Self.trackWidth, height: Self.trackHeight)
            Capsule()
                .fill(Color.white)
                .frame(width: Self.knobWidth,
                       height: Self.trackHeight - Self.knobInset * 2)
                .padding(.horizontal, Self.knobInset)
        }
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard enabled else { return }
            withAnimation(.easeInOut(duration: 0.18)) { isOn.toggle() }
        }
    }
}

/// A `Toggle` that keeps looking like a `Toggle` on Android.
///
/// One wrapper rather than a `#if` at every consent row: the switch is the same
/// control everywhere it appears, and a site that forgets the gate is a site
/// that ships Material's outline again. iOS gets the real `Toggle` verbatim,
/// tint included — this is a no-op there by construction (`0-IOS-GUARD`).
///
/// The whole row is the tap target on Android, matching SwiftUI (tapping a
/// Toggle's label flips it) and Material (which wraps the row too) — dropping to
/// a 63pt switch would have made every one of these rows harder to hit than it
/// is on the phone.
struct DriftToggle<Label: View>: View {
    @Binding var isOn: Bool
    var enabled = true
    let label: Label

    init(isOn: Binding<Bool>, enabled: Bool = true, @ViewBuilder label: () -> Label) {
        self._isOn = isOn
        self.enabled = enabled
        self.label = label()
    }

    var body: some View {
        #if os(Android)
        HStack(spacing: 10) {
            label
            Spacer(minLength: 8)
            IOSSwitch(isOn: $isOn, enabled: enabled)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard enabled else { return }
            withAnimation(.easeInOut(duration: 0.18)) { isOn.toggle() }
        }
        #else
        Toggle(isOn: $isOn) { label }
            .tint(Theme.accent)
            .disabled(!enabled)
        #endif
    }
}
