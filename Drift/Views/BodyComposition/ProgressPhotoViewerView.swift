import SwiftUI
import DriftCore

/// Full-screen photo viewer — the delight surface. One pane per check-in with
/// a Front/Back/Left/Right pose switcher, pose-relevant measurement stats
/// overlaid on the photo (weight + waist always; front shows chest/shoulders,
/// the sides show that side's arm & leg), swipe between dates, and a compare
/// mode that puts two dates side-by-side with the pose-relevant deltas.
struct ProgressPhotoViewerView: View {
    let entries: [ProgressEntry]          // photo entries, newest-first
    let weightByDate: [String: Double]
    let startDate: String
    let startPose: ProgressPose
    var onEdit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var pose: ProgressPose
    @State private var comparing = false
    @State private var compareIndex: Int

    private var inInches: Bool { Preferences.weightUnit == .lbs }

    init(entries: [ProgressEntry], weightByDate: [String: Double], startDate: String,
         startPose: ProgressPose, startComparing: Bool = false, onEdit: @escaping (String) -> Void) {
        self.entries = entries
        self.weightByDate = weightByDate
        self.startDate = startDate
        self.startPose = startPose
        self.onEdit = onEdit
        let start = entries.firstIndex { $0.date == startDate } ?? 0
        _index = State(initialValue: start)
        _pose = State(initialValue: startPose)
        _comparing = State(initialValue: startComparing)
        // Default the compare slot to the OLDEST entry (a wider before/after).
        _compareIndex = State(initialValue: max(0, entries.count - 1))
    }

    private var current: ProgressEntry? { entries[safe: index] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if comparing { compareLayout } else { singleLayout }
            topBar
        }
        .statusBarHidden()
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            HStack(spacing: 12) {
                iconButton("xmark") { dismiss() }
                Spacer()
                if let date = current?.date {
                    VStack(spacing: 1) {
                        Text(longDate(date)).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        if let kg = weightByDate[date] {
                            Text(weightText(kg)).font(.caption2).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                Spacer()
                iconButton(comparing ? "rectangle" : "rectangle.split.2x1", active: comparing) {
                    withAnimation { comparing.toggle() }
                }
                if !comparing, let date = current?.date {
                    iconButton("pencil") { onEdit(date); dismiss() }
                }
            }
            .padding(.horizontal, 16).padding(.top, 12)
            Spacer()
        }
    }

    private func iconButton(_ system: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? Theme.accent : .white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.4), in: Circle())
        }
    }

    // MARK: - Single view

    private var singleLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                photo(for: current, pose: pose)
                    .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                        if v.translation.width < -40, index < entries.count - 1 { withAnimation { index += 1 } }
                        else if v.translation.width > 40, index > 0 { withAnimation { index -= 1 } }
                    })
                if let entry = current { statOverlay(for: entry) }
            }
            Spacer(minLength: 0)
            poseSwitcher
        }
    }

    // MARK: - Compare view

    private var compareLayout: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 40)
            HStack(spacing: 6) {
                comparePane(entries[safe: compareIndex], label: "Then")
                comparePane(current, label: "Now")
            }
            .frame(maxHeight: 380)
            compareDeltas
            Spacer(minLength: 0)
            poseSwitcher
        }
    }

    private func comparePane(_ entry: ProgressEntry?, label: String) -> some View {
        VStack(spacing: 4) {
            Menu {
                ForEach(entries.indices, id: \.self) { i in
                    Button(shortDate(entries[i].date)) {
                        if label == "Then" { compareIndex = i } else { index = i }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(entry.map { shortDate($0.date) } ?? "—").font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }.foregroundStyle(.white)
            }
            photo(for: entry, pose: pose).frame(maxHeight: 340)
        }
    }

    private var compareDeltas: some View {
        let then = entries[safe: compareIndex]?.measurement
        let now = current?.measurement
        let sites = pose.relevantSites
        return VStack(spacing: 4) {
            // Weight delta first (always relevant).
            if let tw = entries[safe: compareIndex].flatMap({ weightByDate[$0.date] }),
               let nw = current.flatMap({ weightByDate[$0.date] }) {
                deltaRow("Weight", then: tw, now: nw, unit: Preferences.weightUnit.displayName, toDisplay: { inInches ? $0 * 2.20462 : $0 })
            }
            ForEach(sites, id: \.self) { site in
                if let t = then?.value(for: site), let n = now?.value(for: site) {
                    deltaRow(site.displayName, then: t, now: n, unit: inInches ? "in" : "cm", toDisplay: { inInches ? $0 / 2.54 : $0 })
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func deltaRow(_ name: String, then: Double, now: Double, unit: String, toDisplay: (Double) -> Double) -> some View {
        let t = toDisplay(then), n = toDisplay(now), d = n - t
        return HStack {
            Text(name).font(.caption).foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(fmt(t)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
            Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
            Text(fmt(n)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
            Text("\(d >= 0 ? "+" : "−")\(fmt(abs(d)))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(abs(d) < 0.05 ? .white.opacity(0.5) : (d < 0 ? Theme.deficit : Theme.stepsOrange))
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Stat overlay (single mode)

    private func statOverlay(for entry: ProgressEntry) -> some View {
        var chips: [(String, String)] = []
        if let kg = weightByDate[entry.date] { chips.append(("Weight", weightText(kg))) }
        for site in pose.relevantSites {
            if let cm = entry.measurement?.value(for: site) {
                chips.append((site.displayName, measurementText(cm)))
            }
        }
        return Group {
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                            VStack(spacing: 1) {
                                Text(chip.0).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                                Text(chip.1).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Pose switcher

    private var poseSwitcher: some View {
        Picker("Pose", selection: $pose) {
            ForEach(ProgressPose.allCases, id: \.self) { Text($0.shortName).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16).padding(.bottom, 24).padding(.top, 8)
        .colorScheme(.dark)
    }

    // MARK: - Photo

    private func photo(for entry: ProgressEntry?, pose: ProgressPose) -> some View {
        Group {
            if let entry, let p = entry.photo(for: pose), let img = ProgressPhotoStore.load(p.filename) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera").font(.title).foregroundStyle(.white.opacity(0.4))
                    Text("No \(pose.shortName.lowercased()) photo").font(.caption).foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Formatting

    private func weightText(_ kg: Double) -> String {
        String(format: "%.1f %@", inInches ? kg * 2.20462 : kg, Preferences.weightUnit.displayName)
    }
    private func measurementText(_ cm: Double) -> String {
        inInches ? String(format: "%.1f in", cm / 2.54) : String(format: "%.1f cm", cm)
    }
    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    private func longDate(_ s: String) -> String { formatDate(s, long: true) }
    private func shortDate(_ s: String) -> String { formatDate(s, long: false) }
    private func formatDate(_ dateStr: String, long: Bool) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0, d = Int(parts[2]) ?? 0
        guard m > 0, m <= 12 else { return dateStr }
        return long ? "\(months[m]) \(d), \(parts[0])" : "\(months[m]) \(d)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
