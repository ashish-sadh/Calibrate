import SwiftUI
import DriftCore
import UIKit

/// BYOK settings for the Photo Log Beta. Controls the opt-in toggle, the
/// provider choice, the API-key entry + Keychain handoff, and the [Test
/// Connection] ping. First cloud feature — privacy copy is load-bearing.
/// #224 / #266.
struct PhotoLogBetaSettingsView: View {
    @State private var enabled: Bool = Preferences.photoLogEnabled
    @State private var provider: CloudVisionProvider = Preferences.photoLogProvider
    @State private var model: String = Preferences.photoLogModel(for: Preferences.photoLogProvider)
    @State private var keyInput: String = ""
    @State private var storedKeyMasked: String? = nil
    @State private var status: StatusMessage? = nil
    @State private var testing: Bool = false
    /// Toggles the raw-key SecureField on top of a stored key. Hidden by
    /// default once a key is saved — user has to tap "Replace key" to reveal
    /// the input so we don't leave a second input sitting next to the masked
    /// badge (past confusion: "does Drift round-robin between keys?").
    @State private var replacingKey: Bool = false

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
                modelPicker
                keySection
                actionSection
                if let status {
                    Text(status.text)
                        .font(.caption)
                        .foregroundStyle(status.isError ? Theme.surplus : Theme.deficit)
                        .padding(.horizontal, 4)
                }
                // Bottom spacer so the actionSection card clears the global
                // AI chat orb (bottom-right). Without this, Test Connection
                // + Clear Key get obscured when scrolled to the bottom.
                Color.clear.frame(height: 80)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Provider").font(.subheadline.weight(.medium))
            // Menu-style picker — segmented was truncating the 3 full names
            // (each ≥15 chars) into unreadable stubs on narrow screens. Menu
            // shows the selection in full with a dropdown affordance.
            Menu {
                ForEach(CloudVisionProvider.allCases, id: \.self) { p in
                    Button {
                        provider = p
                        Preferences.photoLogProvider = p
                        // Reload model for the new provider — it remembers
                        // its own last-picked model independently.
                        model = Preferences.photoLogModel(for: p)
                        refreshStoredKey()
                        status = nil
                    } label: {
                        if p == provider {
                            Label(p.displayName, systemImage: "checkmark")
                        } else {
                            Text(p.displayName)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(provider.displayName).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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

    /// Second-tier picker for the specific model within the selected
    /// provider. Lets users pick paid-tier models (Opus, GPT-4o, Gemini
    /// Pro) once billing is set up without editing code. The picker uses
    /// the same Menu style as the provider picker for visual parity.
    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Model").font(.subheadline.weight(.medium))
                Spacer()
                Text("\(provider.availableModels.count) available")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Menu {
                ForEach(provider.availableModels, id: \.self) { m in
                    Button {
                        model = m
                        Preferences.setPhotoLogModel(m, for: provider)
                        status = nil
                    } label: {
                        if m == model {
                            Label("\(m) — \(CloudVisionProvider.modelDescription(m))",
                                  systemImage: "checkmark")
                        } else {
                            Text("\(m) — \(CloudVisionProvider.modelDescription(m))")
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model).font(.subheadline.weight(.semibold))
                        Text(CloudVisionProvider.modelDescription(model))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Paid-tier models (Claude Opus, GPT-4o, Gemini 2.5 Pro) require billing on the provider. Test Connection below surfaces the provider's actual error — quota exhaustion, key scope, or model-not-available — verbatim.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .card()
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key").font(.subheadline.weight(.medium))
            if let masked = storedKeyMasked, !replacingKey {
                storedKeyRow(masked: masked)
            } else {
                keyInputRow
            }
            Text("Stored in iOS Keychain, protected by Face ID. Never uploaded.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .card()
    }

    /// Shown once a key is saved. No second input box — the "Replace key"
    /// button is the only way to reveal the SecureField, so the user can't
    /// accidentally stack two keys and wonder if we're round-robining.
    private func storedKeyRow(masked: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
            Text(masked).font(.caption.monospaced())
            Spacer()
            Button {
                keyInput = ""
                replacingKey = true
            } label: {
                Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
    }

    /// Paste + Save controls — visible when no key exists or the user tapped
    /// "Replace". Save clears `replacingKey` via `saveKey` so the card falls
    /// back to the masked row.
    private var keyInputRow: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                if storedKeyMasked != nil {
                    Button {
                        keyInput = ""
                        replacingKey = false
                    } label: {
                        Text("Cancel").font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    saveKey()
                } label: {
                    Text("Save").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyInput.isEmpty)
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Test Connection is the primary action after pasting a key —
            // promote it to a filled button so it reads as the CTA and
            // clears the chat-orb obscuring the bottom of the screen.
            Button {
                Task { await runTestConnection() }
            } label: {
                HStack(spacing: 8) {
                    if testing {
                        ProgressView().scaleEffect(0.8).tint(.white)
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
                    }
                    Text(testing ? "Testing…" : "Test Connection")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(testing || !CloudVisionKey.has(provider: provider))

            Button(role: .destructive) {
                clearKey()
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear Key").font(.subheadline.weight(.medium))
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.surplus)
            .disabled(!CloudVisionKey.has(provider: provider))
        }
        .card()
    }

    // MARK: - Actions

    private func refreshStoredKey() {
        storedKeyMasked = CloudVisionKey.has(provider: provider) ? "•••• stored in Keychain" : nil
        keyInput = ""
        replacingKey = false
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
            let model = Preferences.photoLogModel(for: provider)
            switch provider {
            case .anthropic:
                try await AnthropicVisionClient(apiKey: key, model: model).ping()
                status = .success("Connection OK — \(model).")
            case .openai:
                try await OpenAIVisionClient(apiKey: key, model: model).ping()
                status = .success("Connection OK — \(model).")
            case .gemini:
                try await GeminiVisionClient(apiKey: key, model: model).ping()
                status = .success("Connection OK — \(model).")
            }
        } catch let error as CloudVisionError {
            // LocalizedError conformance gives actionable copy per case.
            status = .error(error.errorDescription ?? "Could not reach provider.")
        } catch {
            status = .error("Could not reach provider: \(error.localizedDescription)")
        }
    }
}
