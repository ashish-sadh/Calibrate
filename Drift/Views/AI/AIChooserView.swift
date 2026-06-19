import SwiftUI
import DriftCore

/// Empty-state chooser for users with neither backend configured. Shows two
/// honest cards side-by-side — Cloud BYOK or On-device — and routes the user
/// into whichever flow they pick. Copy is deliberately plain; the spec calls
/// for "no marketing-speak. Treat users like adults." #515.
struct AIChooserView: View {
    @State private var aiService = LocalAIService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer().frame(height: 12)
                heading
                cardStack
                Spacer().frame(height: 18)
                privacyFootnote
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
        }
        .navigationTitle("Set up Drift AI")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var heading: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text("Pick your AI")
                .font(.title2.weight(.bold))
            Text("Either works. You can switch later from inside the chat.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.top, 12)
    }

    private var cardStack: some View {
        VStack(spacing: 12) {
            cloudCard
            onDeviceCard
        }
    }

    private var cloudCard: some View {
        Button {
            // Drift Coach cloud — Nebius team key from AppConfig, no user setup.
            // Selecting it installs the backend immediately; LocalAIService.state
            // flips to .ready, which advances the setup flow into the chat.
            Preferences.preferredAIBackend = .remote
            AIBackendCoordinator.installCoachBackend()
        } label: {
            chooserCard(
                icon: "cloud.fill",
                tint: Theme.accent,
                title: "Drift Coach (cloud)",
                tagline: "Smartest, fastest. Messages leave your device when on.",
                bullets: [
                    ("bolt.fill", "Top-tier reasoning + photo understanding"),
                    ("sparkles", "Powered by the cloud — no key or setup needed"),
                    ("network", "Needs a working internet connection")
                ],
                ctaLabel: "Use Drift Coach"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai-chooser-cloud")
    }

    private var onDeviceCard: some View {
        Button {
            Preferences.preferredAIBackend = .llamaCpp
            Task { await aiService.downloadModel() }
        } label: {
            chooserCard(
                icon: "cpu",
                tint: Theme.deficit,
                title: "On-device AI",
                tagline: "Free, private, slower. Uses 2GB of phone storage.",
                bullets: [
                    ("lock.shield.fill", "Nothing leaves your phone — ever"),
                    ("externaldrive", "One-time \(aiService.downloadSizeText) download (Wi-Fi recommended)"),
                    ("hare", "Fast for most things; slower on complex multi-step questions")
                ],
                ctaLabel: "Download on-device model"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai-chooser-local")
    }

    private var privacyFootnote: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.deficit).font(.caption)
                Text("Your data stays yours")
                    .font(.caption.weight(.medium))
            }
            Text("Drift never collects messages, photos, or telemetry. Drift Coach (cloud) sends only your message to the model. On-device AI sends nothing anywhere.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Card Factory

    /// Single card layout — keeps the two cards visually identical so the
    /// choice reads as Tradeoff A vs Tradeoff B, not Big Deal vs Side Note.
    private func chooserCard(
        icon: String,
        tint: Color,
        title: String,
        tagline: String,
        bullets: [(String, String)],
        ctaLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold))
                    Text(tagline).font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(bullets, id: \.1) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: bullet.0)
                            .font(.caption2).foregroundStyle(tint.opacity(0.8))
                            .frame(width: 16)
                        Text(bullet.1)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Text(ctaLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tint.opacity(0.25), lineWidth: 0.5)
        )
    }
}
