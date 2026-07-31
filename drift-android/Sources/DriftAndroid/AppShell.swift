import SwiftUI
import DriftCore

/// Android port of the iOS V7 shell (Drift/ContentView.swift): five primary
/// tabs — Today | Food | Workout | Body | More — selected by the floating
/// PillTabBar with the Drift Coach button beside it. Deltas from iOS, each
/// tracked on #1060: no matchedGeometry slide (SkipUI), no UIKit haptics
/// (Compose ripple covers feedback), content switches rebuild views instead
/// of staying alive in a hidden TabView.
enum PrimaryTab: Int, CaseIterable, Identifiable {
    case today = 0, food = 1, workout = 2, body = 3, more = 4
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .food: return "Food"
        case .workout: return "Workout"
        case .body: return "Body"
        case .more: return "More"
        }
    }
    var icon: String {
        switch self {
        case .today: return "target"
        case .food: return "fork.knife"
        case .workout: return "dumbbell.fill"
        case .body: return "figure"
        case .more: return "line.3.horizontal"
        }
    }
}

struct PillTabBar: View {
    @Binding var selected: PrimaryTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PrimaryTab.allCases) { tab in
                let isSelected = selected == tab
                Button {
                    guard selected != tab else { return }
                    // Theme.Motion.passive == iOS ContentView's tab cross-fade
                    // curve — the token, not a hardcoded copy, so the two
                    // platforms stay in lockstep (#1074 kit, directive-2).
                    withAnimation(Theme.Motion.passive) { selected = tab }
                } label: {
                    VStack(spacing: 2) {
                        if tab == .today {
                            // Drawn glyph — skip-ui mapped target to house, so
                            // the Today TAB read as a home icon instead of the
                            // iPhone's rings (see TargetGlyph.swift).
                            TargetShape()
                                .fill(isSelected ? Theme.ink : Theme.textTertiary)
                                .frame(width: 16, height: 16)
                                .frame(height: 20)
                        } else if tab == .food {
                            // Drawn glyph — skip-ui's map has no food icon
                            // (see FoodGlyph.swift).
                            ForkKnifeShape()
                                .fill(isSelected ? Theme.ink : Theme.textTertiary)
                                .frame(width: 16, height: 16)
                                .frame(height: 20)
                        } else if tab == .workout {
                            // Drawn glyph — skip-ui mapped dumbbell to
                            // list.bullet, so the Workout TAB read as a bullet
                            // list (see DumbbellGlyph.swift).
                            DumbbellShape()
                                .fill(isSelected ? Theme.ink : Theme.textTertiary)
                                .frame(width: 16, height: 16)
                                .frame(height: 20)
                        } else {
                            Image(systemName: sym(tab.icon))
                                .font(.system(size: 16, weight: .semibold))
                                .frame(height: 20)
                        }
                        Text(tab.label)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            // iOS pill bar shrinks-to-fit rather than wrapping
                            // (ContentView.swift:346) — match it.
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Theme.ink : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            Capsule().fill(Theme.ink.opacity(0.10))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .background(Theme.cardBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 0.5))
        .shadowSoft(cornerRadius: 28)
    }
}

/// Floating Drift Coach entry — chrome matches iOS ChatIconButton exactly:
/// light card circle, ink glyph, hairline border, soft shadow (operator:
/// "the coach button doesn't look like iPhone"). The iOS double-bubble
/// glyph is unmapped in skip-ui (the sym() fallback rendered a paper
/// plane), so the bubbles are drawn Paths per the MealGlyphs pattern.
struct ChatIconButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            ChatBubblesGlyph()
                .frame(width: 44, height: 44)
                .background(Theme.cardBackground, in: Circle())
                .overlay(Circle().strokeBorder(Theme.separator, lineWidth: 0.5))
                .shadowSoft(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }
}

/// Two chat bubbles (left solid outline + right offset), ~the silhouette of
/// SF "bubble.left.and.text.bubble.right", drawn at 20x16 inside the 44pt hit.
struct ChatBubblesGlyph: View {
    var body: some View {
        ZStack {
            // left bubble w/ tail
            Path { p in
                p.addRoundedRect(in: CGRect(x: 0, y: 2, width: 13, height: 9.5), cornerSize: CGSize(width: 3.2, height: 3.2))
                p.move(to: CGPoint(x: 2.6, y: 11))
                p.addLine(to: CGPoint(x: 2.2, y: 14.4))
                p.addLine(to: CGPoint(x: 6, y: 11.2))
                p.closeSubpath()
            }
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            // right bubble, slightly lower + overlapping
            Path { p in
                p.addRoundedRect(in: CGRect(x: 8.4, y: 6.2, width: 11.6, height: 8.4), cornerSize: CGSize(width: 3, height: 3))
            }
            .fill(Theme.ink)
        }
        .frame(width: 20, height: 16)
    }
}
