import Foundation

/// SkipUI maps a limited SF Symbol set to Material icons — unmapped names
/// render as a warning triangle on Android. `sym` substitutes the closest
/// mapped glyph on Android and passes the real symbol through on Darwin,
/// so the shared view code can keep the iOS names.
func sym(_ name: String) -> String {
    #if os(Android)
    switch name {
    case "brain.head.profile": return "person.crop.circle"
    case "clock.arrow.circlepath": return "arrow.clockwise.circle"
    case "ellipsis.circle": return "ellipsis"
    case "dumbbell", "dumbbell.fill": return "list.bullet"
    case "flame.fill": return "star.fill"
    case "chart.line.uptrend.xyaxis": return "chart.bar.xaxis"
    case "scalemass": return "chart.bar.xaxis"
    // "clock" has NO mapping: the calendar stand-in read as a DATE next to
    // the real calendar glyph (#1074). Call sites draw ClockFaceShape
    // (ClockGlyph.swift) behind #if os(Android) instead — a new sym("clock")
    // caller renders the warning triangle so the gap is caught, not hidden.
    // Material's mapped set has no mic; Android entry is typed until the
    // SpeechRecognizer seam (#1063), so the write glyph reads truthfully.
    case "mic.fill", "mic": return "pencil"
    case "arrow.forward.circle.fill": return "arrow.forward"
    case "exclamationmark.circle.fill": return "exclamationmark.triangle.fill"
    case "arrow.clockwise": return "arrow.clockwise.circle"
    // SkipUI's outline-star mapping is disabled upstream (skip-ui #148:
    // Material's "outlined" star isn't), so both fall back to the fill.
    case "star", "star.slash": return "star.fill"
    case "camera.fill", "camera": return "camera.viewfinder"
    case "square.and.arrow.down": return "list.bullet"
    case "target": return "house"
    // fork.knife has NO mapping: Material's set has no food glyph and the
    // cart stand-in read as SHOPPING (operator, 2026-07-19). App call sites
    // render the drawn ForkKnifeShape (FoodGlyph.swift) instead — shared
    // views that need Image(systemName: "fork.knife") on Android must wait
    // on the symbolset investigation (Fuse builds drop xcassets symbolsets).
    case "message.fill", "bubble.left.fill": return "paperplane.fill"
    // Body-part / activity figures — Material has no exercise figures, so
    // they all read as a person (matches the figure.walk precedent).
    case "figure", "figure.walk", "figure.stand",
         "figure.strengthtraining.traditional", "figure.rowing", "figure.run",
         "figure.boxing", "figure.cooldown", "figure.core.training",
         "figure.mixed.cardio": return "person"
    case "trophy.fill": return "star.fill"
    // Active-workout surfaces (#1064 1c). Material's outline "circle" isn't
    // in skip-ui's map — the un-done set ring reads as an outlined check.
    case "circle": return "checkmark.circle"
    case "xmark.circle", "xmark.circle.fill": return "xmark"
    case "sparkles": return "star.fill"
    case "arrow.up.circle.fill": return "paperplane.fill"
    case "plus.circle": return "plus.circle.fill"
    case "timer": return "calendar"
    case "number": return "list.bullet"
    case "doc.on.doc": return "pencil"
    case "play.circle.fill": return "play.fill"
    case "chart.bar": return "chart.bar.xaxis"
    case "wrench.and.screwdriver": return "wrench"
    // Equipment glyphs with no Material cousin collapse to generic gear.
    case "link", "circle.fill", "circle.dotted": return "wrench"
    case "arrow.left.and.right": return "arrow.forward"
    default: return name
    }
    #else
    return name
    #endif
}
