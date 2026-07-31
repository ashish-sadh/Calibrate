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
    /// Boards where I'm publishing but no friend has joined yet.
    @State var solo: [Leaderboard.Section] = []
    /// Which board is on screen. One at a time — twelve stacked cards was a
    /// scroll nobody finished (operator 2026-07-30).
    @State var selectedBoard: String?
    @State var expanded: Set<String> = []
    @State var loading = false
    @State var busy = false
    /// A withdrawal that didn't reach the server. Surfaced, never swallowed.
    @State var withdrawFailed = false
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

            if withdrawFailed {
                Text("Couldn't stop sharing — you're still on your friends' boards. Check your connection and try again.")
                    .font(.caption).foregroundStyle(Theme.surplus)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !sharing {
                invitation
            } else if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if allBoards.isEmpty {
                Text("Nothing shared yet. Boards appear once you and a friend both have numbers for the same thing — steps, calories, workouts or your logging streak.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                boardPicker
                if let shown = currentBoard {
                    boardView(shown)

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
        Text("Compare steps, calories, workouts and your lifts. Boards are visible to EVERYONE on Drift by default, so people can find you — switch any board to friends-only underneath it. Nothing is published until you turn this on.")
            .font(.caption).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - One board

    /// One board, styled to be worth screenshotting.
    ///
    /// The old version was a stack of plain text rows with the title repeated
    /// from the chip above it and the "only you so far" line said twice
    /// (operator 2026-07-30: "doesn't look pretty... make it shareable"). This
    /// leads with the leader, medals the top three, and says the visibility
    /// state as a CONTROL rather than a text link.
    func boardView(_ section: Leaderboard.Section) -> some View {
        let isOpen = expanded.contains(section.board.key)
        let shown = isOpen ? section.rows : Array(section.rows.prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            // Hero: the number that matters, big.
            if let leader = section.rows.first {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Leaderboard.formatted(leader.value, board: section.board))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text(leader.isMe ? "you lead" : "@\(leader.profile.username) leads")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(section.board.period.label)
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }

            ForEach(shown) { row in
                HStack(spacing: 10) {
                    // Medal for the podium, muted number after — the shape
                    // people recognise from a results page.
                    // 22pt was too narrow for "2nd" at bold caption, so it
                    // hyphenated to "2n/d" and shoved that row's avatar and name
                    // out of line with 1st and 3rd. Fixed width + one line keeps
                    // every rank in the same column.
                    Text(medal(row.rank))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(medalTint(row.rank))
                        .lineLimit(1)
                        .frame(width: 30, alignment: .leading)
                    Text(String(row.profile.username.prefix(1)).uppercased())
                        .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(row.isMe ? AnyShapeStyle(Theme.accentGradient)
                                             : AnyShapeStyle(Theme.textTertiary), in: Circle())
                    Text(row.isMe ? "You" : "@\(row.profile.username)")
                        .font(.caption.weight(row.isMe ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Leaderboard.formatted(row.value, board: section.board))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(row.isMe ? Theme.accent.opacity(0.07) : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            if section.rows.count > 5 {
                Button {
                    if isOpen { expanded.remove(section.board.key) }
                    else { expanded.insert(section.board.key) }
                } label: {
                    Text(isOpen ? "Show fewer" : "Show all \(section.rows.count)")
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            if let standing = Leaderboard.standing(section) {
                Text(standing).font(.caption2).foregroundStyle(Theme.textSecondary)
            }

            visibilityControl(section.board)
            globalRows(section.board)
        }
    }

    func medal(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)"
        }
    }

    func medalTint(_ rank: Int) -> Color {
        switch rank {
        case 1: return Theme.accent
        case 2, 3: return Theme.chartTrend
        default: return Theme.textTertiary
        }
    }

    /// Friends vs Global, as an actual two-option control.
    ///
    /// It used to be the words "Friends only" with a red "Go global" link beside
    /// them, which reads as a label plus an ad rather than a setting — the
    /// operator couldn't tell what state he was in. Two capsules, one selected,
    /// says both things at once.
    func visibilityControl(_ board: LeaderboardBoard) -> some View {
        let isGlobal = Preferences.boardIsGlobal(board.key)
        return HStack(spacing: 6) {
            Text("VISIBLE TO").font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            ForEach([false, true], id: \.self) { wantGlobal in
                Button {
                    // Opt-IN set (#1171): boards are friends-only until opened up.
                    var keys = Preferences.globalBoardKeys
                    if wantGlobal { keys.insert(board.key) } else { keys.remove(board.key) }
                    Preferences.globalBoardKeys = keys
                    Task {
                        // Going private must reach EVERY period, not just this
                        // one, or last month's row stays publicly readable.
                        if !wantGlobal { try? await LeaderboardService.unpublish(board: board.key) }
                        await consentChanged(true)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: sym(wantGlobal ? "globe" : "person.2.fill"))
                            .font(.system(size: 9))
                        Text(wantGlobal ? "Everyone" : "Friends").font(.caption2)
                    }
                    #if os(Android)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .frame(minHeight: 26)
                    #else
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    #endif
                    .background(isGlobal == wantGlobal ? Theme.accent.opacity(0.15) : Color.clear,
                                in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(
                            isGlobal == wantGlobal ? Theme.accent.opacity(0.4) : Theme.separatorFaint,
                            lineWidth: 1)
                    }
                    .foregroundStyle(isGlobal == wantGlobal ? Theme.accent : Theme.textSecondary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    /// The global podium + bracket, when this board is public.
    @ViewBuilder
    func globalRows(_ board: LeaderboardBoard) -> some View {
        if Preferences.boardIsGlobal(board.key), let global = globalBoards[board.key] {
            if !global.podium.isEmpty {
                Text("TOP 3 WORLDWIDE").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(Array(global.podium.enumerated()), id: \.element.userId) { index, entry in
                    strangerRow(rank: index + 1, entry: entry, board: board)
                }
            }
            if !global.bracket.isEmpty {
                Text("AROUND YOU").font(.system(size: 9, weight: .bold))
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
                    .lineLimit(1)
                    .frame(width: 16, alignment: .trailing)
                Text(isMe ? "You" : "@\(profile?.username ?? String(entry.userId.prefix(6)))")
                    .font(.caption.weight(isMe ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                Text(Leaderboard.formatted(entry.value, board: board))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                // Always reserve the chevron's width — rendering it only on
                // tappable rows left the values ragged down the right edge.
                Image(systemName: sym("chevron.right"))
                    .font(.caption2)
                    .foregroundStyle((!isMe && profile != nil) ? Theme.textTertiary : .clear)
                    .frame(width: 8)
            }
            // Same 8pt inset as the rows above, so both lists share one left
            // edge instead of the global list hanging outside it.
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMe || profile == nil)
    }

    // MARK: - Data

    var myID: String? { SharingService.shared.currentSession?.userID }

    func refresh() async {
        guard sharing else { sections = []; solo = []; globalBoards = [:]; return }
        loading = true
        await reload()
        loading = false
        await loadGlobal()
        // Refresh MY OWN numbers in the background so everyone reading my row
        // sees today's, not yesterday's — then re-read, but only if a publish
        // actually happened (rate-limited to 10 min). Done AFTER the first read
        // so the board shows instantly rather than waiting on ~14 health
        // queries (no lingering spinner).
        if await LeaderboardPublisher.publishForView() {
            await reload()
            await loadGlobal()
        }
    }

    private func reload() async {
        sections = await LeaderboardService.sections(connections: connections)
        solo = await LeaderboardService.soloSections(connections: connections)
    }

    /// Global boards, one fetch per board the user opted into — bounded by how
    /// many they chose, not by how many exist. Strangers' handles resolve in ONE
    /// batched profile call across every board rather than per row.
    func loadGlobal() async {
        let keys = Leaderboard.globalCandidateKeys(
            sections: sections, solo: solo, isGlobal: Preferences.boardIsGlobal)
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
            do {
                try await LeaderboardService.withdraw()
                sections = []
                globalBoards = [:]
            } catch {
                // Put the switch BACK and say so. Clearing the board on a failed
                // withdrawal showed people the off state while their rows stayed
                // live on other boards, and nothing ever retried.
                sharing = true
                Preferences.shareStatsWithFriends = true
                withdrawFailed = true
            }
        }
    }

    /// Real boards first, then the ones still waiting on a friend.
    var allBoards: [Leaderboard.Section] { sections + solo }

    var currentBoard: Leaderboard.Section? {
        allBoards.first { $0.board.key == selectedBoard } ?? allBoards.first
    }

    /// One tap per board, horizontally scrollable. Chosen over a swipe pager
    /// because a pager hides how many boards exist and how to reach them, and
    /// because SkipUI's paging TabView is not something to rely on across both
    /// platforms. The strip shows the whole set at a glance and stays one tap
    /// from any of them.
    var boardPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(allBoards) { section in
                    let isSelected = section.board.key == (currentBoard?.board.key ?? "")
                    Button { selectedBoard = section.board.key } label: {
                        HStack(spacing: 4) {
                            Text(section.board.title)
                                .font(.caption2.weight(isSelected ? .bold : .regular))
                            // A quiet marker for boards that are still just you,
                            // so the strip doesn't promise a competition.
                            if solo.contains(where: { $0.board.key == section.board.key }) {
                                Image(systemName: sym("hourglass")).font(.system(size: 8))
                            }
                        }
                        // See SocialPillRow: Material's touch-target floor makes
                        // these visibly chunkier than iOS at the same padding.
                        #if os(Android)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .frame(minHeight: 26)
                        #else
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        #endif
                        .background(isSelected ? Theme.accent.opacity(0.15) : Color.clear,
                                    in: Capsule())
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        // Android: a horizontal scroller nested in a vertical one collapses
        // without a pinned minimum height.
        #if os(Android)
        .frame(minHeight: 32)
        #else
        .frame(minHeight: 30)
        #endif
    }

}
