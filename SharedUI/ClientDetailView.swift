import SwiftUI
import DriftCore

/// A coach's view of ONE client — what makes "coach" more than "friend":
/// see how the client is doing (their shared workouts) and **assign** them a
/// workout from your own templates, plus message them. Single-source SharedUI.
struct ClientDetailView: View {
    let client: SharedProfile

    @State var sessions: [LiveWorkoutDTO] = []
    @State var templates: [WorkoutTemplate] = []
    @State var loading = true
    @State var assignedIDs: Set<Int64> = []
    @State var assigningID: Int64?
    @State var error: String?

    private var svc: SharingService { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                messageCard
                recentWorkoutsCard
                assignCard
                if let error {
                    Text(error).font(.caption).foregroundStyle(Theme.surplus)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 110)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("@\(client.username)")
        #if !os(Android)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(client.username.first.map { String($0).uppercased() } ?? "?")
                .font(.title3.weight(.bold)).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Theme.accentGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(client.username)").font(.title3.weight(.bold))
                Text("Your client\(lastActiveSubtitle)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var lastActiveSubtitle: String {
        guard let d = sessions.compactMap(\.activityDate).max() else { return "" }
        return " · last active \(RelativeTime.string(from: d))"
    }

    private var messageCard: some View {
        NavigationLink { ChatView(peer: client, relationship: "client") } label: {
            HStack(spacing: 10) {
                Image(systemName: sym("bubble.left.fill")).foregroundStyle(Theme.chartTrend)
                Text("Message @\(client.username)").font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: sym("chevron.right")).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var recentWorkoutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW THEY'RE DOING").sectionHeading()
            if loading {
                ProgressView()
            } else if sessions.isEmpty {
                Text("No workouts shared with you yet. When @\(client.username) finishes a workout and shares it, it'll show up here.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(sessions.prefix(10)) { s in
                    NavigationLink {
                        ClientSessionDetailView(session: s, fromUsername: "@\(client.username)")
                    } label: {
                        HStack(spacing: 10) {
                            #if os(Android)
                            // Pinned skip-ui 1.58 has no chart glyph (sym's
                            // chart.bar.xaxis target is 1.59+) — drawn bars
                            // instead (ChartGlyph.swift).
                            BarChartShape().fill(Theme.accent).frame(width: 15, height: 15)
                            #else
                            Image(systemName: sym("chart.line.uptrend.xyaxis"))
                                .font(.subheadline).foregroundStyle(Theme.accent)
                            #endif
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.templateName ?? "Workout").font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(s.status == .live ? "training now · live 🔴"
                                     : (s.activityDate.map { RelativeTime.string(from: $0) } ?? "completed"))
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: sym("chevron.right")).font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        .contentShape(Rectangle()).padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    if s.id != sessions.prefix(10).last?.id { Divider().overlay(Theme.separatorFaint) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var assignCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ASSIGN A WORKOUT").sectionHeading()
            Text("Pick one of your templates to send @\(client.username). They accept it into their library and can run it.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
            if templates.isEmpty {
                Text("You have no templates yet. Build one on the Workout tab, then assign it here.")
                    .font(.caption).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            } else {
                ForEach(templates) { t in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name).font(.subheadline.weight(.medium))
                            Text("\(t.exercises.count) exercises").font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if let id = t.id, assignedIDs.contains(id) {
                            Label("Assigned", systemImage: sym("checkmark"))
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.deficit)
                        } else if assigningID == t.id {
                            ProgressView()
                        } else {
                            Button { Task { await assign(t) } } label: {
                                Text("Assign").font(.caption.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(Theme.ink, in: Capsule()).foregroundStyle(.white)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    if t.id != templates.last?.id { Divider().overlay(Theme.separatorFaint) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func load() async {
        loading = true
        templates = (try? WorkoutService.fetchTemplates()) ?? []
        let all = (try? await svc.clientSessions()) ?? []
        sessions = all.filter { $0.clientId == client.id }
        loading = false
    }

    private func assign(_ template: WorkoutTemplate) async {
        guard let id = template.id else { return }
        assigningID = id; error = nil
        do {
            try await svc.shareTemplate(template, to: client.id, role: .trainer,
                                        note: "Assigned by your coach")
            assignedIDs.insert(id)
        } catch {
            self.error = (error as? SharingError).map(String.init(describing:)) ?? error.localizedDescription
        }
        assigningID = nil
    }
}
