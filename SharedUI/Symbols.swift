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
    // "dumbbell"/"dumbbell.fill" have NO mapping: Material's mapped set has no
    // barbell, and the list.bullet stand-in read as a BULLET LIST on the
    // Workout tab icon, every equipment chip and the history card (operator
    // directive 0a — a missing mapping means the closest same-meaning icon,
    // never a different object). Call sites draw DumbbellShape
    // (DumbbellGlyph.swift) behind #if os(Android); a new sym("dumbbell")
    // caller renders the warning triangle so the gap is caught, not hidden.
    // "flame.fill" has NO mapping: skip-ui's Material map contains no fire
    // glyph at all, and the star fallback read as a rating next to "active
    // cal" and "1 week streak" (directive 0a). Call sites draw FlameShape
    // (FlameGlyph.swift) behind #if os(Android); a new sym("flame.fill")
    // caller renders the warning triangle so the gap is caught, not hidden.
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
    // target has NO mapping: Material's set has no bullseye and the house
    // stand-in read as HOME on the Today tab — a different object, the same
    // failure as the shopping-cart food icon. The tab bar draws TargetShape
    // (TargetGlyph.swift) instead.
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
         "figure.cross.training", "figure.mixed.cardio": return "person"
    case "trophy.fill": return "star.fill"
    // "circle" is deliberately UNMAPPED. Material has no outline circle, and
    // the old `checkmark.circle` fallback drew a check on every UN-DONE set and
    // every UNSELECTED row — a fallback that reads as the OPPOSITE of the real
    // state is worse than a visible gap. Both call sites now draw a real ring
    // via Circle().stroke() behind #if os(Android): ActiveWorkoutView (set done
    // toggle) and ExercisePickerView (row selection).
    case "xmark.circle", "xmark.circle.fill": return "xmark"
    case "sparkles": return "star.fill"
    case "arrow.up.circle.fill": return "paperplane.fill"
    case "plus.circle": return "plus.circle.fill"
    case "timer": return "calendar"
    case "number": return "list.bullet"
    // Template-package menu rows. Material has no numbered circles; the row
    // TEXT carries the numbering ("Load Drift Package II"), so a generic list
    // marker is decoration, not a competing meaning.
    case "1.circle", "2.circle", "3.circle", "4.circle",
         "square.stack.3d.up": return "list.bullet"
    // "Save as Template" sits directly under "Edit Name & Notes" in the workout
    // ⋯ menu, so mapping doc.on.doc to pencil drew the SAME glyph on both rows
    // (#1076). Material's mapped set has no doc/copy icon at all; bookmark
    // ("save this for reuse") is the closest surviving meaning and, unlike
    // pencil, does not collide with Edit.
    case "doc.on.doc": return "bookmark"
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
