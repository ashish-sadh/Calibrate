import SwiftUI
import DriftCore

/// One-time prompt on first launch (after the restore check) that nudges the
/// user to enable iCloud backup. Stays out of the way for users who are
/// restoring (the restore flow already runs and would have set them up) and
/// for users whose iCloud Drive is off (no point — backup would fail).
///
/// Toggled by `drift.hasSeenBackupOnboarding`. Either button dismisses and
/// marks seen so this never re-shows for the install.
struct BackupOnboardingSheet: View {
    @AppStorage("drift_backup_enabled") private var backupEnabled: Bool = false
    @AppStorage("drift.hasSeenBackupOnboarding") private var seen: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 8)
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 4)

            Text("Back up to iCloud")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Drift saves your food log, weight history, recipes, and workouts to your iCloud Drive every night. If you ever lose your phone or switch devices, your data comes back exactly as it was.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 10) {
                row(icon: "lock.shield", text: "Stored in your iCloud account, not on Drift's servers.")
                row(icon: "clock.arrow.circlepath", text: "Automatic daily snapshot — only the latest 11 are kept.")
                row(icon: "arrow.up.arrow.down", text: "Restore on any new iPhone signed in to the same Apple ID.")
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    backupEnabled = true
                    seen = true
                    dismiss()
                } label: {
                    Text("Enable iCloud Backup")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Turn on automatic daily backups to iCloud.")

                Button {
                    seen = true
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Skip for now. You can enable backup later in Settings.")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .background(Theme.background.ignoresSafeArea())
        .interactiveDismissDisabled(false)
    }

    private func row(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// Decides whether to show the onboarding sheet on first launch.
/// Centralised so DriftApp's `.task` block stays small and the rule is
/// testable. Show when:
///   - the user has never seen the prompt
///   - backup is not already enabled
///   - iCloud Drive is available (else the prompt would lead to a failing toggle)
///   - the restore sheet didn't fire (caller decides this; we don't know)
public enum BackupOnboardingDecision {
    public static func shouldShow(
        userDefaults: UserDefaults = .standard,
        iCloudAvailable: Bool
    ) -> Bool {
        let seen = userDefaults.bool(forKey: "drift.hasSeenBackupOnboarding")
        let enabled = userDefaults.bool(forKey: "drift_backup_enabled")
        return !seen && !enabled && iCloudAvailable
    }
}

#Preview {
    BackupOnboardingSheet()
        .preferredColorScheme(.light)
}
