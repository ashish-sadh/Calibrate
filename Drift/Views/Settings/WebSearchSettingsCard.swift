import SwiftUI
import DriftCore

/// Settings card for the coach's web_search provider ladder (Google Custom
/// Search → Brave → DuckDuckGo). Keys live in UserDefaults via `Preferences`
/// (same pattern as the USDA key). The active-provider line makes the ladder
/// state visible so a typo'd key is diagnosable at a glance.
struct WebSearchSettingsCard: View {
    @State private var googleKey = Preferences.googleSearchApiKey
    @State private var googleCx = Preferences.googleSearchEngineId
    @State private var braveKey = Preferences.braveSearchApiKey
    @State private var expanded = false

    private var activeProvider: String {
        if !googleKey.isEmpty && !googleCx.isEmpty { return "Google" }
        if !braveKey.isEmpty { return "Brave" }
        return "DuckDuckGo (limited — add a key for real results)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coach Web Search").font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Looks up restaurant & brand nutrition — active: \(activeProvider)")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Custom Search").font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        TextField("API key (console.cloud.google.com)", text: $googleKey)
                            .textFieldStyle(.roundedBorder).font(.caption)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .onChange(of: googleKey) { _, v in Preferences.googleSearchApiKey = v.trimmingCharacters(in: .whitespaces) }
                        TextField("Engine ID / cx (programmablesearchengine.google.com)", text: $googleCx)
                            .textFieldStyle(.roundedBorder).font(.caption)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .onChange(of: googleCx) { _, v in Preferences.googleSearchEngineId = v.trimmingCharacters(in: .whitespaces) }
                        Text("Free 100 searches/day. Create an engine with “Search the entire web” on.")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Brave Search (alternative)").font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        TextField("API key (brave.com/search/api)", text: $braveKey)
                            .textFieldStyle(.roundedBorder).font(.caption)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .onChange(of: braveKey) { _, v in Preferences.braveSearchApiKey = v.trimmingCharacters(in: .whitespaces) }
                    }
                    Text("Only the search query (e.g. “chipotle bowl calories”) is sent to the provider — never your logs or personal data.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .padding(.leading, 36)
            }
        }
        .card()
    }
}
