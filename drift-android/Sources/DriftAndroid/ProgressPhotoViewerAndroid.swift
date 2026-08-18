import SwiftUI
import DriftCore

/// Android's full-screen progress-photo viewer (#1187) — the line-for-line port
/// of iOS `Drift/Views/BodyComposition/ProgressPhotoViewerView.swift`. One pane
/// per check-in with a Front/Back/Left/Right pose switcher, pose-relevant
/// measurement stats overlaid on the photo (weight + waist always; front shows
/// the torso girths, the sides that side's limbs), navigation between dates, and
/// a compare mode that puts two dates side by side with goal-aware deltas.
///
/// Android-local rather than a SharedUI single-source move: iOS
/// `ProgressGalleryView.swift:59-63` presents `ProgressPhotoViewerView` by that
/// exact type name, so relocating the iOS file would rewrite a shipped iOS
/// delight surface during launch hardening for zero Android benefit. The only
/// genuinely platform-bound line — the image decode — is the same `AsyncImage`
/// over `ProgressPhotoPaths.url(for:)` that `SharedUI/ProgressPhotoImage.swift`
/// already uses; everything else is pure Swift over DriftCore.
struct ProgressPhotoViewerAndroid: View {
    let entries: [ProgressEntry]          // photo entries, newest-first
    let weightByDate: [String: Double]
    let startDate: String
    let startPose: ProgressPose
    var onEdit: (String) -> Void

    // Non-private throughout: Skip Fuse cannot bridge private @State/@Environment
    // and reports the failure as a misleading line-1 error.
    @Environment(\.dismiss) var dismiss
    @State var index: Int
    @State var pose: ProgressPose
    @State var comparing = false
    @State var compareIndex: Int

    var inInches: Bool { Preferences.weightUnit == .lbs }

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

    /// Bounds-checked element access. iOS uses a file-private `Array[safe:]`
    /// subscript; a generic extension on `Array` is more than skipstone needs to
    /// chew on for two call sites, so this is a plain method.
    func entry(at i: Int) -> ProgressEntry? {
        i >= 0 && i < entries.count ? entries[i] : nil
    }

    var current: ProgressEntry? { entry(at: index) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if comparing { compareLayout } else { singleLayout }
            topBar
        }
        // Real implementation on Skip (AdditionalViewModifiers.swift:1373), not a
        // silent shim — and required here: SyncSystemBarsWithTheme paints DARK
        // status-bar icons for the light-pinned app, which would be invisible on
        // this black canvas.
        .statusBarHidden()
    }

    // MARK: - Top bar

    var topBar: some View {
        VStack {
            HStack(spacing: 12) {
                iconButton(sym("xmark")) { dismiss() }
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
                if entries.count >= 2 {
                    compareButton
                }
                // iOS shows a pencil here that opens AddProgressEntryView. That
                // screen has no Android port yet (#1166), so the button is
                // omitted rather than shipped as a dead tap; `onEdit` stays on
                // the signature so un-hiding it is one line.
            }
            .padding(.horizontal, 16).padding(.top, 12)
            Spacer()
        }
    }

    func iconButton(_ system: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? Theme.accent : .white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.4), in: Circle())
        }
    }

    /// iOS toggles between `rectangle.split.2x1` (enter compare) and `rectangle`
    /// (leave it). skip-ui's Material map has no rectangle, split-view or compare
    /// glyph of any kind under the pinned 1.58 — both names would render the
    /// warning triangle. Rather than substitute a different object, draw the two
    /// shapes from built-in primitives: they *are* a rounded rectangle with and
    /// without a divider, so this matches iOS exactly instead of approximating it.
    var compareButton: some View {
        Button {
            withAnimation { comparing.toggle() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 2.5)
                    .stroke(comparing ? Theme.accent : .white, lineWidth: 1.6)
                    .frame(width: 17, height: 13)
                if !comparing {
                    Rectangle().fill(.white).frame(width: 1.6, height: 13)
                }
            }
            .frame(width: 38, height: 38)
            .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel("Compare two dates")
    }

    // MARK: - Single view

    var singleLayout: some View {
        VStack(spacing: 0) {
            // iOS balances the photo between two `Spacer(minLength: 0)`s. On Fuse
            // the FIRST spacer swallowed all the slack (measured: 672px top, 22px
            // bottom) so the photo hugged the pose switcher. An outer centering
            // ZStack that fills the free height is deterministic and lands the
            // photo where iOS puts it; the inner ZStack still hugs the image so
            // the stat chips stay pinned to its bottom edge, as on iOS.
            ZStack {
                // Inner stack hugs the image, so the stat chips pin to the
                // photo's bottom edge exactly as on iOS.
                //
                // fixedSize is what KEEPS it hugging. Without it the hug held for
                // the first composition only: after any pose tap this stack
                // expanded to the parent's height, and because its alignment is
                // .bottom the photo went with it — the image dropped 108dp on the
                // first tap and stayed there for every pose after (measured: top
                // edge 431px → 729px, while iOS renders 455px for every pose).
                // The chips moved too, which is why the bug reads as "the photo
                // slid down" rather than "the chips came off the photo".
                ZStack(alignment: .bottom) {
                    photo(for: current, pose: pose)
                        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                            if v.translation.width < -40 { step(1) }
                            else if v.translation.width > 40 { step(-1) }
                        })
                    if let entry = current { statOverlay(for: entry) }
                }
                .fixedSize(horizontal: false, vertical: true)
                // The tap zones live in the OUTER stack, which is already
                // flexible. `Rectangle()` has no intrinsic size, so putting them
                // in the inner stack stretched it and dropped the photo onto the
                // pose switcher; `.overlay` does the same, because Fuse renders
                // an overlay as a Box that sizes to its largest child.
                dateTapZones
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            poseSwitcher
        }
    }

    /// DragGesture has no precedent anywhere in this build tree, and a Skip
    /// modifier that silently no-ops would leave date navigation dead. Two
    /// invisible half-width tap zones guarantee it works; they add zero pixels,
    /// so the screen still matches iOS. Empty with a single check-in — an
    /// always-installed zone would be a tap that goes nowhere.
    var dateTapZones: some View {
        Group {
            if entries.count >= 2 {
                HStack(spacing: 0) {
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .onTapGesture { step(-1) }
                        .accessibilityLabel("Previous check-in")
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .onTapGesture { step(1) }
                        .accessibilityLabel("Next check-in")
                }
            }
        }
    }

    /// +1 = older (entries are newest-first), −1 = newer. Clamped at both ends,
    /// matching the iOS drag handler's bounds checks.
    func step(_ delta: Int) {
        let next = index + delta
        guard next >= 0, next < entries.count else { return }
        withAnimation { index = next }
    }

    // MARK: - Compare view

    var compareLayout: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 40)
            HStack(spacing: 6) {
                comparePane(entry(at: compareIndex), label: "Then")
                comparePane(current, label: "Now")
            }
            .frame(maxHeight: 380)
            compareDeltas
            Spacer(minLength: 0)
            poseSwitcher
        }
    }

    func comparePane(_ entry: ProgressEntry?, label: String) -> some View {
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
                    Image(systemName: sym("chevron.down")).font(.system(size: 9))
                }.foregroundStyle(.white)
            }
            photo(for: entry, pose: pose).frame(maxHeight: 340)
        }
    }

    var compareDeltas: some View {
        let then = entry(at: compareIndex)?.measurement
        let now = current?.measurement
        let sites = pose.relevantSites
        return VStack(spacing: 4) {
            // Weight delta first (always relevant). Direction-of-good follows
            // the user's weight goal; neutral when no goal is set.
            if let tw = entry(at: compareIndex).flatMap({ weightByDate[$0.date] }),
               let nw = current.flatMap({ weightByDate[$0.date] }) {
                deltaRow("Weight", then: tw, now: nw, unit: Preferences.weightUnit.displayName,
                         lowerBetter: weightLowerBetter, toDisplay: { inInches ? $0 * 2.20462 : $0 })
            }
            ForEach(sites, id: \.self) { site in
                if let t = then?.value(for: site), let n = now?.value(for: site) {
                    deltaRow(site.displayName, then: t, now: n, unit: inInches ? "in" : "cm",
                             lowerBetter: Self.lowerBetter(site), toDisplay: { inInches ? $0 / 2.54 : $0 })
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// Goal-aware color direction per site: smaller waist/hips read as
    /// progress; bigger muscle girths (chest, arms, thighs…) read as progress.
    /// A +2 cm chest must not wear the "against goal" color.
    static func lowerBetter(_ site: MeasurementSite) -> Bool {
        site == .waist || site == .hips
    }

    /// nil = no goal set → neutral coloring for weight.
    var weightLowerBetter: Bool? {
        guard let goal = WeightGoal.load() else { return nil }
        return goal.targetWeightKg < goal.startWeightKg
    }

    func deltaRow(_ name: String, then: Double, now: Double, unit: String,
                  lowerBetter: Bool?, toDisplay: (Double) -> Double) -> some View {
        let t = toDisplay(then), n = toDisplay(now), d = n - t
        let color: Color = {
            guard abs(d) >= 0.05 else { return .white.opacity(0.5) }
            guard let lowerBetter else { return .white.opacity(0.85) }   // neutral
            return (lowerBetter ? d < 0 : d > 0) ? Theme.deficit : Theme.stepsOrange
        }()
        return HStack {
            Text(name).font(.caption).foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(fmt(t)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
            Image(systemName: sym("arrow.right")).font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
            Text(fmt(n)).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
            Text("\(d >= 0 ? "+" : "−")\(fmt(abs(d)))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Stat overlay (single mode)

    func statOverlay(for entry: ProgressEntry) -> some View {
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
                // A horizontal ScrollView can collapse to zero height on Fuse
                // (skipui_sheet_chrome_and_hscroll_height_traps) — pin the chip
                // row's intrinsic height so the overlay can never vanish.
                .frame(minHeight: 40)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Pose switcher

    /// `.pickerStyle(.segmented)` + `.tint(.white)` got the selected segment off
    /// Material You's wallpaper-derived maroon, but left the three structural
    /// tells that make the row read as Material rather than iOS: the leading ✓,
    /// the inter-segment dividers, and an outlined track where iOS fills one.
    /// IOSSegmentedPicker draws the measured iPhone control instead.
    var poseSwitcher: some View {
        IOSSegmentedPicker(options: ProgressPose.allCases.map { $0.shortName },
                           selection: poseNameBinding)
            .padding(.horizontal, 16).padding(.bottom, 24).padding(.top, 8)
    }

    /// The picker speaks labels, not cases — a generic segmented control has no
    /// precedent on Fuse anywhere in this tree, and an unproven generic View is
    /// not worth spending on four fixed poses.
    var poseNameBinding: Binding<String> {
        Binding(get: { pose.shortName },
                set: { name in
                    if let match = ProgressPose.allCases.first(where: { $0.shortName == name }) {
                        pose = match
                    }
                })
    }

    // MARK: - Photo

    func photo(for entry: ProgressEntry?, pose: ProgressPose) -> some View {
        Group {
            if let entry, let p = entry.photo(for: pose), ProgressPhotoPaths.fileExists(p.filename) {
                // Same load path as SharedUI/ProgressPhotoImage.swift's Android
                // branch — Coil decodes and caches the on-device JPEG. `scaledToFit`
                // (not the shared view's `scaledToFill`) is why this is inline:
                // the viewer must show the whole frame, never a crop.
                AsyncImage(url: ProgressPhotoPaths.url(for: p.filename)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.black
                }
            } else {
                VStack(spacing: 8) {
                    // The pinned skip-ui maps NO camera name at all, and since
                    // #1233 Symbols.swift no longer pretends otherwise: every
                    // camera name now falls through to the warning triangle by
                    // design, so a new caller's gap stays visible. CameraShape
                    // is the drawn glyph the Snap chip already uses for this.
                    CameraShape()
                        .stroke(.white.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                    Text("No \(pose.shortName.lowercased()) photo").font(.caption).foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Formatting

    func weightText(_ kg: Double) -> String {
        String(format: "%.1f %@", inInches ? kg * 2.20462 : kg, Preferences.weightUnit.displayName)
    }
    func measurementText(_ cm: Double) -> String {
        inInches ? String(format: "%.1f in", cm / 2.54) : String(format: "%.1f cm", cm)
    }
    func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    func longDate(_ s: String) -> String { formatDate(s, long: true) }
    func shortDate(_ s: String) -> String { formatDate(s, long: false) }
    func formatDate(_ dateStr: String, long: Bool) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0, d = Int(parts[2]) ?? 0
        guard m > 0, m <= 12 else { return dateStr }
        return long ? "\(months[m]) \(d), \(parts[0])" : "\(months[m]) \(d)"
    }
}
