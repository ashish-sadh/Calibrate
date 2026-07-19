import Foundation

/// SkipUI maps a limited SF Symbol set to Material icons — unmapped names
/// render as a warning triangle on Android. `sym` substitutes the closest
/// mapped glyph on Android and passes the real symbol through on Darwin,
/// so the shared view code can keep the iOS names.
func sym(_ name: String) -> String {
    #if os(Android)
    switch name {
    case "figure.strengthtraining.traditional": return "play.fill"
    case "brain.head.profile": return "person.crop.circle"
    case "clock.arrow.circlepath": return "arrow.clockwise.circle"
    case "ellipsis.circle": return "ellipsis"
    case "dumbbell", "dumbbell.fill": return "list.bullet"
    case "flame.fill": return "star.fill"
    case "figure.walk": return "person"
    case "chart.line.uptrend.xyaxis": return "chart.bar.xaxis"
    case "scalemass": return "chart.bar.xaxis"
    case "clock": return "calendar"
    case "mic.fill", "mic": return "paperplane.fill"
    case "star.slash": return "star"
    case "square.and.arrow.down": return "list.bullet"
    default: return name
    }
    #else
    return name
    #endif
}
