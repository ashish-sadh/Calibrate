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
    // NOTE: "chart.bar.xaxis" only exists in skip-ui ≥1.59 — under the pinned
    // 1.58.0 (#1134) it is UNMAPPED and renders the warning triangle. Workout
    // tab + ClientDetailView call sites draw BarChartShape (ChartGlyph.swift)
    // behind #if os(Android) instead; the mappings stay so the remaining
    // callers (ExerciseDetailView level tag, WorkoutDetailView volume label)
    // light up again the moment the pin is lifted.
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
    // Error states: Material has no speech-bubble variant, and the triangle IS
    // the right meaning here (operator 2026-07-28: "closest icons are fine" —
    // never let a name fall through to the triangle by ACCIDENT, but choosing
    // it deliberately for an error is correct).
    case "exclamationmark.bubble": return "exclamationmark.triangle"
    // Scanning a page/label — Material's QrCodeScanner is genuinely the closest
    // meaning here (unlike for "Snap", where a camera was the real object).
    case "doc.viewfinder": return "camera.viewfinder"
    case "plus.circle": return "plus.circle.fill"
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
    // skip-ui maps NO two-person glyph (person.2/group/people all absent) — only
    // single-person symbols. Fall to the closest mapped one so the Friends row
    // shows a person, never the warning triangle (operator directive 0a).
    case "person.2.fill", "person.2", "person.3.fill", "person.3": return "person.crop.circle.fill"
    // doc.on.doc (copy/duplicate) is unmapped in skip-ui → shipped the ⚠️
    // triangle on Food's "Copy yesterday". Map to the mapped repeat glyph
    // (semantically "copy from a previous day"). Operator directive 0a.
    // This case also wins for the workout "Save as Template" rows — a later
    // duplicate `case "doc.on.doc": return "bookmark"` (#1076) was
    // unreachable AND "bookmark" is 1.59-only, so it was removed; revisit the
    // save-vs-copy split when the skip-ui pin (#1134) is lifted.
    case "doc.on.doc", "doc.on.doc.fill": return "arrow.clockwise.circle"
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
    // "sparkles" is deliberately UNMAPPED. Material has no sparkle glyph, and
    // the old `star.fill` fallback put a solid favourite-star in front of the
    // AI command strip. The call site draws SparkleShape behind #if os(Android);
    // a new caller gets the warning triangle so the gap stays visible.
    case "arrow.up.circle.fill": return "paperplane.fill"
    // "timer" has NO mapping: the calendar stand-in put a DATE glyph on the
    // "Track by Time" row of the exercise-options menu — the same failure as
    // sym("clock") (#1074), and doubly wrong there because the workout header
    // right above it uses the real calendar. The call site draws ClockFaceShape
    // behind #if os(Android); a new sym("timer") caller renders the warning
    // triangle so the gap is caught, not hidden.
    case "number": return "list.bullet"
    // Template-package menu rows. Material has no numbered circles; the row
    // TEXT carries the numbering ("Load Drift Package II"), so a generic list
    // marker is decoration, not a competing meaning.
    case "1.circle", "2.circle", "3.circle", "4.circle",
         "square.stack.3d.up": return "list.bullet"
    case "play.circle.fill": return "play.fill"
    case "chart.bar": return "chart.bar.xaxis"
    case "wrench.and.screwdriver": return "wrench"
    // `link`, `circle.fill` and `circle.dotted` are deliberately UNMAPPED.
    // They used to return "wrench", which drew Cable, Kettlebells, Exercise
    // ball, Medicine ball and Foam Roll as the SAME wrench — and the first
    // four as a TOOL rather than the object iOS shows (directive 0a: a missing
    // mapping means the closest same-meaning icon, never a different object).
    // `equipmentGlyph()` draws all three itself now; leaving them unmapped
    // means a new caller gets a visible warning triangle rather than a silent
    // wrong glyph, the same way sym("timer") was removed in sweep #6.
    case "arrow.left.and.right": return "arrow.forward"
    default: return name
    }
    #else
    return name
    #endif
}
