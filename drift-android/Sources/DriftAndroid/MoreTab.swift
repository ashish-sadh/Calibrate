import SwiftUI
import DriftCore

/// Minimal More tab (#1067 tracks the full iOS settings hub). Weight-unit
/// preference is live; the rest lists what's coming so nothing looks broken.
struct MoreTab: View {
    @State var unit = Preferences.weightUnit
    @State var showingSupplements = false
    @State var showingProgress = false
    @State var showingSupport = false
    @State var usageTelemetry = Preferences.usageTelemetryEnabled
    @State var aiCapture = Preferences.aiCaptureEnabled
    /// 0 unavailable (card hidden) · 1 available · 2 provider update needed.
    /// Starts at 0 so an unknown seam hides the card instead of promising a
    /// sync it may not be able to do.
    @State var hcAvailability = 0
    @State var hcStatus: String?
    @State var hcBlocked = false
    /// Only the newest status line gets to clear itself — otherwise an earlier
    /// tap's timer wipes a later tap's result.
    @State var hcStatusToken = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PREFERENCES").sectionHeading()
                        HStack {
                            Text("Weight unit").font(.subheadline)
                            Spacer()
                            Picker("", selection: $unit) {
                                Text("lbs").tag(WeightUnit.lbs)
                                Text("kg").tag(WeightUnit.kg)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRIVACY").sectionHeading()
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.deficit)
                            // Copy corrected 2026-07-28: this used to promise
                            // "no analytics", which the anonymous usage
                            // pipeline below makes untrue. A stale privacy
                            // claim is worse than the feature it hides.
                            Text("Your health data stays on this device. No account needed. Anonymous usage counts help us see what to improve — switch them off below.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }

                        Toggle(isOn: $usageTelemetry) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Share anonymous usage").font(.subheadline)
                                Text("Which screens and actions get used — never your food, weight or health data.")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .tint(Theme.accent)
                        .onChange(of: usageTelemetry) { _, newValue in
                            Preferences.usageTelemetryEnabled = newValue
                        }

                        Toggle(isOn: $aiCapture) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Share AI conversations").font(.subheadline)
                                Text("Uploads what you ask Drift Coach and Describe, plus the reply, so bad answers can be fixed. Off by default.")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .tint(Theme.accent)
                        .onChange(of: aiCapture) { _, newValue in
                            Preferences.aiCaptureEnabled = newValue
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Health Connect (#1207). Gated on the seam's real
                    // tri-state and never silent: the old card promised a sync
                    // on every device and swallowed every outcome, so the
                    // first tap imported nothing and said nothing.
                    if hcAvailability != 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HEALTH CONNECT").sectionHeading()
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.accent)
                                Text(hcAvailability == 2
                                     ? "Health Connect needs an update on this device before Drift can read your health data."
                                     : "Weights from scale apps, steps, calories and sleep sync automatically when permissions are granted.")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            if hcAvailability == 1 {
                                Button {
                                    // Set synchronously in the handler so the
                                    // tap always paints something.
                                    setHealthStatus("Syncing…", autoClear: false)
                                    Task { @MainActor in await runHealthSync() }
                                } label: {
                                    Text("Connect / Sync now")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                                }
                                // Android stops showing the permission sheet
                                // once a denial is USER_FIXED, so a status
                                // line alone would leave the user with a dead
                                // button and no way back.
                                if hcBlocked {
                                    Button {
                                        if !HealthConnectService.shared.openHealthConnectSettings() {
                                            setHealthStatus("Couldn't open Health Connect on this device.")
                                        }
                                    } label: {
                                        Text("Open Health Connect settings")
                                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                                    }
                                }
                                if let status = hcStatus {
                                    Text(status).font(.caption2).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    // Supplements — the iOS screen, ported to SharedUI (#1121).
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRACKING").sectionHeading()
                        Button { showingSupplements = true } label: {
                            HStack(spacing: 10) {
                                Text("Supplements")
                                    .font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: sym("chevron.right"))
                                    .font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Theme.separator)
                        Button { showingSupport = true } label: {
                            HStack(spacing: 10) {
                                Text("Support & feedback")
                                    .font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: sym("chevron.right"))
                                    .font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Theme.separator)
                        Button { showingProgress = true } label: {
                            HStack(spacing: 10) {
                                Text("Progress Photos")
                                    .font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: sym("chevron.right"))
                                    .font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Friends & Trainer sharing (#sharing) — single-source
                    // SharingView from SharedUI. NavigationLink push (not a
                    // sheet) keeps this view at its existing two presentation
                    // modifiers; Skip Fuse breaks on stacked presentations.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SOCIAL").sectionHeading()
                        NavigationLink { SharingView() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: sym("person.2.fill"))
                                    .font(.subheadline).foregroundStyle(Theme.deficit)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Friends & Coaches").font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    Text("Share workouts · connect with a trainer")
                                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: sym("chevron.right"))
                                    .font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("COMING TO ANDROID").sectionHeading()
                        ForEach(["Drift Coach chat + voice", "Photo & barcode logging",
                                 "Sleep & biomarkers detail screens",
                                 "Backup & restore"], id: \.self) { item in
                            HStack(spacing: 6) {
                                Circle().fill(Theme.textQuaternary).frame(width: 5, height: 5)
                                Text(item).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Build stamp — diagnosing "which build are you on" from a
                    // screenshot instead of guessing (2026-07-27 incident).
                    Text("Drift for Android · build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("More")
            .onChange(of: unit) { _, newValue in
                Preferences.weightUnit = newValue
            }
            .task {
                // One bridged hop, off `body` (every JNI call costs a frame).
                hcAvailability = HealthConnectService.shared.availability
            }
            .sheet(isPresented: $showingSupplements) { SupplementsTabView() }
            .sheet(isPresented: $showingProgress) { ProgressGalleryAndroid() }
            .sheet(isPresented: $showingSupport) { NavigationStack { SupportView() } }
        }
    }

    /// iOS's `clearStatus()` grammar — a status line says its piece and gets
    /// out of the way after ~3s (`MoreTabView.swift:813`).
    func setHealthStatus(_ text: String?, autoClear: Bool = true) {
        hcStatus = text
        hcStatusToken += 1
        guard autoClear, text != nil else { return }
        let token = hcStatusToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if hcStatusToken == token { withAnimation { hcStatus = nil } }
        }
    }

    /// The iOS one-button flow (`MoreTabView.swift:272-286`): authorize, FULL
    /// resync (incremental-vs-full is not a choice a user should make, and the
    /// full path is the only escape from a poisoned anchor), body composition,
    /// and always a word about what happened.
    @MainActor func runHealthSync() async {
        let health = HealthConnectService.shared
        // Waits for the real grant result — the sync used to race the sheet
        // and read permissions the user hadn't granted yet.
        let outcome = await health.requestAuthorizationInteractive()
        do {
            let weight = try await health.fullResyncWeight()
            let bodyComp = (try? await health.syncBodyComposition()) ?? 0
            // The escape hatch belongs on screen only for the real dead end:
            // the ask was refused AND nothing came in. A partial denial that
            // still imported weight doesn't need a route out, and a granted
            // ask that simply found no data never did.
            hcBlocked = weight + bodyComp == 0 && (outcome == .denied || outcome == .unavailable)
            if weight + bodyComp > 0 {
                setHealthStatus("Imported \(weight) weight + \(bodyComp) body-composition entries")
            } else if hcBlocked {
                setHealthStatus("Health Connect didn't grant access. Allow Weight for Drift in Health Connect → App permissions, then sync again.")
            } else {
                setHealthStatus("No data found. If Health Connect has your weight, allow Weight for Drift in Health Connect → App permissions, then sync again.")
            }
        } catch {
            setHealthStatus("Sync failed: \(error.localizedDescription)")
        }
    }
}
