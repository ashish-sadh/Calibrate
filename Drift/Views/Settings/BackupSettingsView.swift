import SwiftUI
import DriftCore

/// Settings → Data → Backup screen (Section E of `561-icloud-backup.md`).
/// Toggle + Back Up Now + Restore picker + "What's in my backup?" disclosure.
struct BackupSettingsView: View {
    @AppStorage("drift_backup_enabled") private var backupEnabled: Bool = false
    @State private var isBackingUp = false
    @State private var lastBackupError: String?
    @State private var lastSuccessfulDate: Date?
    @State private var showingRestorePicker = false
    @State private var showingICloudUnavailable = false
    @State private var transientStatus: String?

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

            if let status = transientStatus {
                Text(status).font(.caption).foregroundStyle(Theme.deficit)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        transientStatus = nil
        defer {
            isBackingUp = false
            refreshState()
        }
        do {
            _ = try await service.performBackup()
            transientStatus = "Backed up — uploading to iCloud…"
        } catch BackupError.iCloudUnavailable {
            showingICloudUnavailable = true
        } catch {
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
