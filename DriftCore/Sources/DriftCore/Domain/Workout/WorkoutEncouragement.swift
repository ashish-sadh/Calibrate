import Foundation

/// Coach lines for the transient mid-workout toast (operator 2026-07-12:
/// "say motivating stuff as pop ups during workouts — feels like a real
/// coach and it disappears"). Pure and deterministic: the caller passes a
/// monotonically increasing tick and lines rotate, so it's Tier-0 testable
/// and never repeats back-to-back. Tone rules: short (glanceable between
/// sets), warm, zero shame — a missed rep never gets commentary.
public enum WorkoutEncouragement {

    public enum Event: Equatable, Sendable {
        /// A working set was checked off (no milestone attached).
        case setDone
        /// This set's weight beat last session's top weight for the exercise.
        case beatLastTime
        /// All planned sets of an exercise are done; `remaining` = exercises
        /// still open.
        case exerciseComplete(remaining: Int)
        /// Every planned set in the session is done.
        case workoutComplete
    }

    public static func line(for event: Event, tick: Int) -> String {
        switch event {
        case .setDone:
            return pick([
                "Good set 👊",
                "Clean work — breathe",
                "That's how it's done",
                "Strong. Rest up",
                "Stack 'em up 🧱",
                "Locked in 🔒",
                "Nice rhythm — keep it",
            ], tick)
        case .beatLastTime:
            return pick([
                "Heavier than last time — that's progress 📈",
                "You just beat last session 🎉",
                "Stronger than last week. Noted 📈",
            ], tick)
        case .exerciseComplete(let remaining):
            if remaining <= 0 { return line(for: .workoutComplete, tick: tick) }
            if remaining == 1 {
                return pick([
                    "One more exercise — bring it home 💪",
                    "Last one up next. Finish strong",
                ], tick)
            }
            return pick([
                "That's one done — \(remaining) to go 💪",
                "Crossed off. \(remaining) left — keep moving",
                "Done ✓ \(remaining) more on the board",
            ], tick)
        case .workoutComplete:
            return pick([
                "That's the whole board — hit Finish 🏁",
                "Everything done. Great session 🎉",
                "Board cleared. Go eat something good 🍽️",
            ], tick)
        }
    }

    private static func pick(_ lines: [String], _ tick: Int) -> String {
        lines[abs(tick) % lines.count]
    }
}
