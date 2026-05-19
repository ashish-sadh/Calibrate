import SwiftUI
import DriftCore

/// Restore picker: list of available backups, confirmation, atomic restore.
/// Section D of `561-icloud-backup.md`.
///
/// The sheet is dismissed when restore completes; the app shows a banner and
/// the caller is responsible for prompting the user to relaunch (SwiftUI can't
/// cleanly re-open AppDatabase mid-session — confirmed by BackupRestorer's
/// atomic file-swap path).
struct RestorePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var backups: [BackupInfo] = []
    @State private var isLoading = true
    @State private var pendingRestore: BackupInfo?
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var restoredManifest: BackupManifest?

    private let service: BackupService

    init(service: BackupService = .shared) {
        self.service = service
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isLoading {
                    loadingCard
                } else if backups.isEmpty {
                    emptyCard
                } else {
                    ForEach(backups) { backup in
                        backupRow(backup)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Restore from Backup")
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .task { await reload() }
        .alert(item: $pendingRestore) { backup in
            Alert(
                title: Text("Restore from \(Self.dateFormatter.string(from: backup.timestamp))?"),
                message: Text("This will replace your current Drift data. You cannot undo this. Continue?"),
                primaryButton: .destructive(Text("Restore")) {
                    Task { await runRestore(backup) }
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Restore complete", isPresented: Binding(
            get: { restoredManifest != nil },
            set: { if !$0 { restoredManifest = nil; dismiss() } }
        )) {
            Button("OK") {
                restoredManifest = nil
                dismiss()
            }
        } message: {
            Text("Relaunch Drift to see your restored data.")
        }
        .alert("Restore failed", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.accent)
            Text("Checking iCloud…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .card()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No backups found").font(.subheadline.weight(.medium))
            Text("Backups will appear here once you tap Back Up Now or after a nightly automatic backup runs on this iCloud account.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .card()
    }

    private func backupRow(_ backup: BackupInfo) -> some View {
        Button {
            if !isRestoring { pendingRestore = backup }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tray.full")
                    .foregroundStyle(Theme.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateFormatter.string(from: backup.timestamp))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Drift \(backup.appVersion) (\(backup.appBuild))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if isRestoring, pendingRestore?.id == backup.id {
                    ProgressView().tint(Theme.accent)
                } else {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
        .card()
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        backups = service.availableBackups()
    }

    private func runRestore(_ backup: BackupInfo) async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let manifest = try await service.restore(from: backup.url)
            restoredManifest = manifest
        } catch {
            restoreError = String(describing: error)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

#Preview {
    NavigationStack {
        RestorePickerView()
    }
    .preferredColorScheme(.light)
}
