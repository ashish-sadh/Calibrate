import SwiftUI
import DriftCore
import Combine

/// Live backup status for the Settings screen. MainActor-isolated (hence
/// implicitly Sendable) so the off-main progress callback from `performBackup`
/// can capture it and update it via `Task { @MainActor in }`. #backup-progress
@MainActor @Observable final class BackupProgressModel {
    var message: String?
}

/// Settings → Data → Backup screen (Section E of `561-icloud-backup.md`).
/// Toggle + Back Up Now + Restore picker + "What's in my backup?" disclosure.
struct BackupSettingsView: View {
    @AppStorage("drift_backup_enabled") private var backupEnabled: Bool = false
    @State private var isBackingUp = false
    @State private var lastBackupError: String?
    @State private var lastSuccessfulDate: Date?
    @State private var showingRestorePicker = false
    @State private var showingICloudUnavailable = false
    /// Live phase text ("Compressing 3.2 MB…", "Uploading to iCloud…",
    /// "Backed up ✓"). Reference type so the @Sendable progress callback can
    /// update it from a background thread (via the main actor).
    @State private var progress = BackupProgressModel()

    private let service: BackupService

    init(service: BackupService = .shared) {
        self.service = service
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                automaticBackupCard
                actionsCard
                whatsIncludedCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Backup")
        .toolbarColorScheme(.light, for: .navigationBar)
        .onAppear { refreshState() }
        .onReceive(NotificationCenter.default.publisher(for: .driftBackupUploadStateChanged)) { _ in
            // Upload confirmed (or failed) by the iCloud metadata query — update
            // live instead of waiting for the next onAppear. This is the answer
            // to "is it actually working?": the line flips to "Backed up ✓".
            refreshState()
            if let err = service.lastBackupError {
                progress.message = nil
                lastBackupError = err
            } else if service.lastSuccessfulBackupDate != nil {
                progress.message = "Backed up ✓"
                let model = progress
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    if model.message == "Backed up ✓" { model.message = nil }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: progress.message)
        .sheet(isPresented: $showingRestorePicker) {
            NavigationStack {
                RestorePickerView(service: service)
            }
        }
        .alert("iCloud Drive is off", isPresented: $showingICloudUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable iCloud Drive in Settings → Apple ID → iCloud → iCloud Drive, then try again.")
        }
    }

    private var automaticBackupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "icloud")
                    .foregroundStyle(Theme.textSecondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic Backups (iCloud)").font(.subheadline.weight(.medium))
                    Text("Daily snapshot of your Drift data to iCloud Drive")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $backupEnabled).labelsHidden().tint(Theme.ink)
            }

            if let date = lastSuccessfulDate {
                Text("Last backed up: \(BackupSettingsView.relativeFormatter.localizedString(for: date, relativeTo: Date()))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if backupEnabled {
                Text("No backups yet — first backup runs tonight at 3 AM, or tap Back Up Now.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let err = lastBackupError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.surplus)
            }
        }
        .card()
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button {
                Task { await runBackup() }
            } label: {
                HStack(spacing: 12) {
                    if isBackingUp {
                        ProgressView().tint(Theme.ink).frame(width: 24)
                    } else {
                        Image(systemName: "arrow.up.to.line").foregroundStyle(Theme.textSecondary).frame(width: 24)
                    }
                    Text("Back Up Now").foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(isBackingUp || !backupEnabled)
            .accessibilityHint(isBackingUp ? "Backup in progress" : "Backs up Drift to iCloud immediately")

            if let status = progress.message {
                HStack(spacing: 6) {
                    if isBackingUp { ProgressView().scaleEffect(0.7) }
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.hasSuffix("✓") ? Theme.deficit : Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            Divider().overlay(Theme.separator)

            Button {
                showingRestorePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.to.line").foregroundStyle(Theme.textSecondary).frame(width: 24)
                    Text("Restore from Backup…").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private var whatsIncludedCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("Included")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Your food log, weight history, recipes, workouts, biomarkers, and app preferences.")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Not included")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text("Photos, HealthKit data (Apple syncs this separately), and security keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle").foregroundStyle(Theme.textSecondary).frame(width: 24)
                Text("What's in my backup?").font(.subheadline.weight(.medium))
            }
        }
        .tint(Theme.textPrimary)
        .card()
    }

    private func refreshState() {
        lastSuccessfulDate = service.lastSuccessfulBackupDate
        lastBackupError = service.lastBackupError
    }

    private func runBackup() async {
        guard !isBackingUp else { return }
        isBackingUp = true
        progress.message = nil
        lastBackupError = nil
        // Capture the reference (Sendable, MainActor-isolated) so the off-main
        // packaging callback can post phase updates back to the UI.
        let model = progress
        defer {
            isBackingUp = false
            refreshState()
        }
        do {
            _ = try await service.performBackup(progress: { phase in
                Task { @MainActor in model.message = phase.message }
            })
            // performBackup already emitted .uploading; that line stays until the
            // metadata query confirms the upload (onReceive flips it to ✓).
        } catch BackupError.iCloudUnavailable {
            progress.message = nil
            showingICloudUnavailable = true
        } catch {
            progress.message = nil
            lastBackupError = String(describing: error)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

#Preview {
    NavigationStack {
        BackupSettingsView()
    }
    .preferredColorScheme(.light)
}
