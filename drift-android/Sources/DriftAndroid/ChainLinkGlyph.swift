import SwiftUI

/// Chain-link glyph for the "Cable" equipment chip. skip-ui's Material map has
/// no `link`, and `sym()` used to route it — along with `circle.fill` and
/// `circle.dotted` — onto `wrench`, so a cable machine advertised itself with a
/// TOOL, and did it with the same glyph as Kettlebells, Exercise ball and Foam
/// Roll. Directive 0a: a missing mapping means the closest same-meaning icon,
/// never a different object.
///
/// Two interlocking capsule outlines are the universally-read "link" mark and
/// the shape Material's own `link` icon uses. Drawn horizontally rather than on
/// iOS's diagonal so no `rotationEffect` is involved — at 8pt the diagonal buys
/// nothing and rotation is one more Compose behaviour to trust.
struct ChainLinkGlyph: View {
    let tint: Color

    var body: some View {
        ZStack {
            Capsule().stroke(tint, lineWidth: 1).frame(width: 5.5, height: 4).offset(x: -1.4)
            Capsule().stroke(tint, lineWidth: 1).frame(width: 5.5, height: 4).offset(x: 1.4)
        }
        .frame(width: 8, height: 8)
    }
}
