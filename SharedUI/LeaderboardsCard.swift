import SwiftUI
import DriftCore

/// Boards among friends — as many as the group actually has in common.
///
/// Not a fixed set of tabs. `LeaderboardService` returns whatever boards exist
/// for you and your friends this period, and a board only appears when at least
/// two of you have a value on it (operator 2026-07-30: "sometimes auto render
/// based on what you are doing… like steps, deadlift highest weight etc"). So a
/// group that deadlifts gets a deadlift board and a group that walks doesn't,
/// with no setting to configure and no code change to add one.
///
/// Rendered as a compact list, boards stacked, top three rows each. The full
/// board is one tap away rather than everything expanded at once — six boards
/// fully expanded is a screen nobody reads.
///
/// OPT-IN and symmetric: dark until you turn it on, and turning it on is what
/// puts you on other people's boards too. Off, there's an invitation with no
/// data in it — never a preview of what you're missing, which is pressure
/// dressed up as a feature.
struct LeaderboardsCard: View {
    let connections: [Connection]

    /// Not private — Fuse can't bridge private @State.
    @State var sharing = Preferences.shareStatsWithFriends
    @State var sections: [Leaderboard.Section] = []
    @State var expanded: Set<String> = []
    @State var loading = false
    @State var busy = false
    /// Global boards, keyed by board. Fetched only for boards the user chose to
    /// publish globally — you can't browse a global board you haven't joined,
    /// which is what keeps it symmetric rather than a place to watch strangers.
    @State var globalBoards: [String: GlobalBoard] = [:]
    @State var strangers: [String: SharedProfile] = [:]
    @State var viewing: SharedProfile?
    @State var viewingContext: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !sharing {
                invitation
            } else if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if sections.isEmpty {
                Text("Nothing shared yet. Boards appear once you and a friend both have numbers for the same thing — steps, a lift, anything.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(sections) { section in
                    boardView(section)
                }
            }
        }
        .card()
        .task { await refresh() }
        // One presentation modifier per view (progress-photos lesson): the
        // profile sheet is the only thing this card presents.
        .sheet(item: $viewing) { person in
            PublicProfileSheet(profile: person, context: viewingContext)
        }
    }

    // MARK: - Header + consent

    var header: some View {
        HStack(spacing: 6) {
            Text("LEADERBOARDS").sectionHeading()
            Spacer()
            Toggle("", isOn: Binding(
                get: { sharing },
                set: { on in
                    sharing = on
                    Preferences.shareStatsWithFriends = on
                    Task { await consentChanged(on) }
                }
            ))
            .labelsHidden()
            .tint(Theme.accent)
            .disabled(busy)
        }
    }

    var invitation: some View {
        Text("Turn this on to compare steps, calories, workouts and your lifts with friends. Boards appear only where you and a friend train the same thing — and you'll appear on theirs too.")
            .font(.caption).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - One board

    func boardView(_ section: Leaderboard.Section) -> some View {
        let isOpen = expanded.contains(section.board.key)
        // Three rows is enough to see the shape of it; the rest is on request.
        let shown = isOpen ? section.rows : Array(section.rows.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if isOpen { expanded.remove(section.board.key) }
                else { expanded.insert(section.board.key) }
            } label: {
                HStack(spacing: 6) {
                    Text(section.board.title)
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(section.board.period.label)
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    if section.rows.count > 3 {
                        Text(isOpen ? "Less" : "All \(section.rows.count)")
                            .font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(shown) { row in
                HStack(spacing: 8) {
                    Text("\(row.rank)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(row.rank == 1 ? Theme.accent : Theme.textTertiary)
                        .frame(width: 16, alignment: .trailing)
                    Text(row.isMe ? "You" : "@\(row.profile.username)")
                        .font(.caption.weight(row.isMe ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(Leaderboard.formatted(row.value, board: section.board))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                }
            }

            if let standing = Leaderboard.standing(section) {
                Text(standing)
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }

            globalStrip(section.board)
        }
        .padding(.bottom, 2)
    }

    /// The global half of a board: a podium to aspire to, then the people
    /// nearest you. Only rendered when this board is set to global — and the
    /// switch to do that lives right here, next to the board it affects, rather
    /// than in a settings screen away from the consequence.
    @ViewBuilder
    func globalStrip(_ board: LeaderboardBoard) -> some View {
        let isGlobal = Preferences.globalBoardKeys.contains(board.key)
        Button {
            var keys = Preferences.globalBoardKeys
            if isGlobal { keys.remove(board.key) } else { keys.insert(board.key) }
            Preferences.globalBoardKeys = keys
            Task { await consentChanged(true) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sym(isGlobal ? "globe" : "person.2.fill"))
                    .font(.caption2)
                Text(isGlobal ? "Global" : "Friends only")
                    .font(.caption2)
                Spacer()
                Text(isGlobal ? "Make private" : "Go global")
                    .font(.caption2).foregroundStyle(Theme.accent)
            }
            .foregroundStyle(Theme.textTertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if isGlobal, let global = globalBoards[board.key] {
            if !global.podium.isEmpty {
                Text("TOP 3 WORLDWIDE").font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(Array(global.podium.enumerated()), id: \.element.userId) { index, entry in
                    strangerRow(rank: index + 1, entry: entry, board: board)
                }
            }
            if !global.bracket.isEmpty {
                Text("AROUND YOU").font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(global.bracket, id: \.userId) { entry in
                    strangerRow(rank: nil, entry: entry, board: board)
                }
            }
        }
    }

    /// A row for someone you don't know. Tapping opens their profile — the
    /// discovery path. Handles resolve lazily; an unresolved one still renders
    /// (as a truncated id) rather than vanishing, because a missing row looks
    /// like a bug while an ugly one looks like loading.
    func strangerRow(rank: Int?, entry: LeaderboardEntryDTO,
                    board: LeaderboardBoard) -> some View {
        let profile = strangers[entry.userId]
        let isMe = entry.userId == SharingService.shared.currentSession?.userID
        return Button {
            guard let profile, !isMe else { return }
            viewingContext = "\(Leaderboard.formatted(entry.value, board: board)) · \(board.title)"
            viewing = profile
        } label: {
            HStack(spacing: 8) {
                Text(rank.map(String.init) ?? "·")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rank == 1 ? Theme.accent : Theme.textTertiary)
                    .frame(width: 16, alignment: .trailing)
                Text(isMe ? "You" : "@\(profile?.username ?? String(entry.userId.prefix(6)))")
                    .font(.caption.weight(isMe ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                Text(Leaderboard.formatted(entry.value, board: board))
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                if !isMe, profile != nil {
                    Image(systemName: sym("chevron.right"))
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMe || profile == nil)
    }

    // MARK: - Data

    var myID: String? { SharingService.shared.currentSession?.userID }

    func refresh() async {
        guard sharing else { sections = []; globalBoards = [:]; return }
        loading = true
        sections = await LeaderboardService.sections(connections: connections)
        loading = false
        await loadGlobal()
    }

    /// Global boards, one fetch per board the user opted into — bounded by how
    /// many they chose, not by how many exist. Strangers' handles resolve in ONE
    /// batched profile call across every board rather than per row.
    func loadGlobal() async {
        let keys = Preferences.globalBoardKeys.intersection(Set(sections.map(\.board.key)))
        guard !keys.isEmpty else { globalBoards = [:]; return }
        var boards: [String: GlobalBoard] = [:]
        for key in keys {
            if let board = await LeaderboardService.globalBoard(key) { boards[key] = board }
        }
        globalBoards = boards

        let unknown = Set(boards.values.flatMap(\.userIDs)).subtracting(strangers.keys)
        guard !unknown.isEmpty else { return }
        let fetched = (try? await SharingService.shared.profiles(ids: Array(unknown))) ?? []
        for profile in fetched { strangers[profile.id] = profile }
    }

    /// Flipping the switch acts immediately in both directions: on publishes so
    /// you're not absent from a board you just joined, off deletes what was
    /// published rather than merely stopping future writes.
    func consentChanged(_ on: Bool) async {
        busy = true
        defer { busy = false }
        if on {
            await LeaderboardPublisher.publishIfDue(force: true)
            await refresh()
        } else {
            await LeaderboardService.withdraw()
            sections = []
        }
    }
}
