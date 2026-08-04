import SwiftUI

/// Camera glyph drawn as a `Path`: skip-ui's Material map has NO camera entry
/// at all — the only near-name, `camera.viewfinder`, maps to
/// `Icons.Outlined.QrCodeScanner`, so the dashboard's "Snap" chip rendered a
/// QR-SCAN square (field report 2026-07-28). A QR scanner is a different
/// object from a camera, which is exactly the directive-0a failure the
/// dumbbell / flame / sparkle glyphs already exist to avoid.
///
/// Body is a rounded rectangle with the little top hump over the lens, matching
/// how SF Symbols composes `camera`. Drawn as an OUTLINE (stroke) at the call
/// site so it reads like the iOS chip rather than a filled blob.
struct CameraShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var p = Path()
        // Body — rounded rect from (2,7) to (22,20).
        let r = 2.6
        p.move(to: pt(2 + r, 7))
        p.addLine(to: pt(22 - r, 7))
        p.addQuadCurve(to: pt(22, 7 + r), control: pt(22, 7))
        p.addLine(to: pt(22, 20 - r))
        p.addQuadCurve(to: pt(22 - r, 20), control: pt(22, 20))
        p.addLine(to: pt(2 + r, 20))
        p.addQuadCurve(to: pt(2, 20 - r), control: pt(2, 20))
        p.addLine(to: pt(2, 7 + r))
        p.addQuadCurve(to: pt(2 + r, 7), control: pt(2, 7))
        p.closeSubpath()

        // Viewfinder hump over the lens.
        p.move(to: pt(8.5, 7))
        p.addLine(to: pt(9.8, 4.4))
        p.addLine(to: pt(14.2, 4.4))
        p.addLine(to: pt(15.5, 7))

        // Lens.
        p.addEllipse(in: CGRect(x: pt(8.4, 9.9).x, y: pt(8.4, 9.9).y,
                                width: 7.2 * s, height: 7.2 * s))
        return p
    }
}

/// Speech-bubble glyph drawn as a `Path`: skip-ui's Material map has no chat /
/// forum / sms entry, so `sym("bubble.left.fill")` fell back to
/// `paperplane.fill` — the dashboard's "Describe" chip rendered a SEND ARROW
/// (field report 2026-07-28), reading as "send a message" rather than
/// "describe your meal".
///
/// Rounded rectangle with a tail at the lower left, matching SF Symbols'
/// `bubble.left`.
struct ChatBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var p = Path()
        let r = 4.0
        // Bubble body (3,4) → (21,17), tail drops from the lower-left corner.
        p.move(to: pt(3 + r, 4))
        p.addLine(to: pt(21 - r, 4))
        p.addQuadCurve(to: pt(21, 4 + r), control: pt(21, 4))
        p.addLine(to: pt(21, 17 - r))
        p.addQuadCurve(to: pt(21 - r, 17), control: pt(21, 17))
        p.addLine(to: pt(9.5, 17))
        // Tail.
        p.addLine(to: pt(6.2, 20.8))
        p.addLine(to: pt(6.6, 17))
        p.addLine(to: pt(3 + r, 17))
        p.addQuadCurve(to: pt(3, 17 - r), control: pt(3, 17))
        p.addLine(to: pt(3, 4 + r))
        p.addQuadCurve(to: pt(3 + r, 4), control: pt(3, 4))
        p.closeSubpath()
        return p
    }
}

/// Photo-stack glyph drawn as a `Path`: skip-ui's Material map has NO photo/
/// gallery/album/picture entry at all (checked `composeSymbolName` directly —
/// zero hits for any "photo.*" name), so any `sym("photo…")` call would fall
/// through to the warning triangle rather than a wrong-but-plausible object.
/// Used for "Choose from Library" on the Snap capture sheet (#1111), where
/// `CameraShape` above is already taken by "Take Photo".
///
/// Two overlapping rounded rectangles (the back one smaller, offset up-left),
/// matching how SF Symbols composes `photo.on.rectangle` minus its interior
/// sun/mountain glyph — dropped for legibility at the 20pt button size this
/// is drawn at; always paired with a text label so the silhouette alone
/// carries no ambiguity risk.
struct PhotoStackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12.0 * s
        let oy = rect.midY - 12.0 * s
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var p = Path()
        // Back rectangle — smaller, offset up-left.
        let rb = 1.6
        p.move(to: pt(1 + rb, 2))
        p.addLine(to: pt(17 - rb, 2))
        p.addQuadCurve(to: pt(17, 2 + rb), control: pt(17, 2))
        p.addLine(to: pt(17, 14 - rb))
        p.addQuadCurve(to: pt(17 - rb, 14), control: pt(17, 14))
        p.addLine(to: pt(1 + rb, 14))
        p.addQuadCurve(to: pt(1, 14 - rb), control: pt(1, 14))
        p.addLine(to: pt(1, 2 + rb))
        p.addQuadCurve(to: pt(1 + rb, 2), control: pt(1, 2))
        p.closeSubpath()

        // Front rectangle — larger, offset down-right, drawn on top.
        let rf = 2.0
        p.move(to: pt(7 + rf, 8))
        p.addLine(to: pt(23 - rf, 8))
        p.addQuadCurve(to: pt(23, 8 + rf), control: pt(23, 8))
        p.addLine(to: pt(23, 22 - rf))
        p.addQuadCurve(to: pt(23 - rf, 22), control: pt(23, 22))
        p.addLine(to: pt(7 + rf, 22))
        p.addQuadCurve(to: pt(7, 22 - rf), control: pt(7, 22))
        p.addLine(to: pt(7, 8 + rf))
        p.addQuadCurve(to: pt(7 + rf, 8), control: pt(7, 8))
        p.closeSubpath()
        return p
    }
}
