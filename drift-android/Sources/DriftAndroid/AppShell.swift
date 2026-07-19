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
                    withAnimation(.easeOut(duration: 0.22)) { selected = tab }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: sym(tab.icon))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(height: 20)
                        Text(tab.label)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
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
        .shadowSoft()
    }
}

/// Floating Drift Coach entry — mirrors iOS ChatIconButton placement.
struct ChatIconButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: sym("bubble.left.fill"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Theme.ink, in: Circle())
                .shadowSoft()
        }
        .buttonStyle(.plain)
    }
}

/// Placeholder until #1066 lands the full chat UI — the Nebius brain is
/// already cross-platform; this is honest about what's wired.
struct CoachComingSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: sym("bubble.left.fill"))
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
                Text("Drift Coach").font(Theme.fontTitle)
                Text("The Coach is coming to Android in the next update — same brain as the iPhone, chat + voice logging for meals, workouts, and weight.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(24)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
