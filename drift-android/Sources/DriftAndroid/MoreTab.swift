import SwiftUI
import DriftCore

/// Minimal More tab (#1067 tracks the full iOS settings hub). Weight-unit
/// preference is live; the rest lists what's coming so nothing looks broken.
struct MoreTab: View {
    @State var unit = Preferences.weightUnit
    @State var showingSupplements = false
    @State var showingProgress = false
    @State var usageTelemetry = Preferences.usageTelemetryEnabled
    @State var aiCapture = Preferences.aiCaptureEnabled

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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("HEALTH CONNECT").sectionHeading()
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.accent)
                            Text("Weights from scale apps, steps, calories and sleep sync automatically when permissions are granted.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Button {
                            Task { @MainActor in
                                try? await DriftPlatform.health?.requestAuthorization()
                                _ = try? await DriftPlatform.health?.syncWeight()
                            }
                        } label: {
                            Text("Connect / Sync now")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

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
                                    Text("Friends").font(.subheadline).foregroundStyle(Theme.textPrimary)
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
            .sheet(isPresented: $showingSupplements) { SupplementsTabView() }
            .sheet(isPresented: $showingProgress) { ProgressGalleryAndroid() }
        }
    }
}
