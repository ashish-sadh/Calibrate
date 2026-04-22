import SwiftUI
import UIKit

/// BYOK settings for the Photo Log Beta. Controls the opt-in toggle, the
/// provider choice, the API-key entry + Keychain handoff, and the [Test
/// Connection] ping. First cloud feature — privacy copy is load-bearing.
/// #224 / #266.
struct PhotoLogBetaSettingsView: View {
    @State private var enabled: Bool = Preferences.photoLogEnabled
    @State private var provider: CloudVisionProvider = Preferences.photoLogProvider
    @State private var keyInput: String = ""
    @State private var storedKeyMasked: String? = nil
    @State private var status: StatusMessage? = nil
    @State private var testing: Bool = false

    enum StatusMessage: Equatable {
        case success(String)
        case error(String)

        var text: String { switch self { case .success(let s), .error(let s): return s } }
        var isError: Bool { if case .error = self { return true }; return false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                privacyBanner
                enabledToggle
                providerPicker
                keySection
                actionSection
                if let status {
                    Text(status.text)
                        .font(.caption)
                        .foregroundStyle(status.isError ? Theme.surplus : Theme.deficit)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Photo Log (Beta)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshStoredKey)
    }

    // MARK: - Sections

    private var privacyBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Beta — sends photos to cloud AI", systemImage: "cloud")
                .font(.subheadline.weight(.semibold))
            Text("Turning on Photo Log sends your meal photos to the provider you choose (Anthropic or OpenAI). Everything else in Drift stays on your device. You pay for your own API key — Drift never sees your photos or key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var enabledToggle: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable Photo Log").font(.subheadline.weight(.medium))
                Text("Adds a camera button in chat and food log.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .onChange(of: enabled) { _, on in
            Preferences.photoLogEnabled = on
            status = .success(on ? "Photo Log enabled." : "Photo Log disabled.")
        }
        .card()
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider").font(.subheadline.weight(.medium))
            Picker("Provider", selection: $provider) {
                ForEach(CloudVisionProvider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: provider) { _, new in
                Preferences.photoLogProvider = new
                refreshStoredKey()
                status = nil
            }
            // Tier / cost line for the currently selected provider. Makes the
            // Gemini free-tier path discoverable so new users don't assume
            // every option costs money.
            Text(provider.pricingLine)
                .font(.caption).foregroundStyle(.secondary)
            Text("Keys for the other providers stay saved — switching back keeps you signed in.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .card()
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key").font(.subheadline.weight(.medium))
            if let masked = storedKeyMasked {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
                    Text(masked).font(.caption.monospaced())
                    Spacer()
                }
            }
            SecureField("Paste \(provider.displayName) API key", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack(spacing: 12) {
                Button {
                    if let clipboard = UIPasteboard.general.string {
                        keyInput = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    saveKey()
                } label: {
                    Text("Save").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyInput.isEmpty)
            }
            Text("Stored in iOS Keychain, protected by Face ID. Never uploaded.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .card()
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await runTestConnection() }
            } label: {
                HStack {
                    if testing { ProgressView().scaleEffect(0.8) }
                    Text(testing ? "Testing…" : "Test Connection")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "bolt.horizontal.fill").foregroundStyle(Theme.accent)
                }
            }
            .disabled(testing || !CloudVisionKey.has(provider: provider))

            Button(role: .destructive) {
                clearKey()
            } label: {
                HStack {
                    Text("Clear Key").font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "trash").foregroundStyle(Theme.surplus)
                }
            }
            .disabled(!CloudVisionKey.has(provider: provider))
        }
        .card()
    }

    // MARK: - Actions

    private func refreshStoredKey() {
        storedKeyMasked = CloudVisionKey.has(provider: provider) ? "•••• stored in Keychain" : nil
        keyInput = ""
    }

    private func saveKey() {
        do {
            try CloudVisionKey.set(keyInput, for: provider)
            refreshStoredKey()
            status = .success("Key saved.")
        } catch {
            status = .error("Could not save key: \(error.localizedDescription)")
        }
    }

    private func clearKey() {
        do {
            try CloudVisionKey.clear(for: provider)
            refreshStoredKey()
            status = .success("Key cleared.")
        } catch {
            status = .error("Could not clear key: \(error.localizedDescription)")
        }
    }

    private func runTestConnection() async {
        testing = true
        defer { testing = false }
        do {
            guard let key = try await CloudVisionKey.get(for: provider) else {
                status = .error("No key stored.")
                return
            }
            switch provider {
            case .anthropic:
                try await AnthropicVisionClient(apiKey: key).ping()
                status = .success("Connection OK.")
            case .openai:
                try await OpenAIVisionClient(apiKey: key).ping()
                status = .success("Connection OK.")
            case .gemini:
                try await GeminiVisionClient(apiKey: key).ping()
                status = .success("Connection OK.")
            }
        } catch let error as CloudVisionError {
            // LocalizedError conformance gives actionable copy per case.
            status = .error(error.errorDescription ?? "Could not reach provider.")
        } catch {
            status = .error("Could not reach provider: \(error.localizedDescription)")
        }
    }
}
