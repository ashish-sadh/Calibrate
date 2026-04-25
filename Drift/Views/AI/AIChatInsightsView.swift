import SwiftUI
import DriftCore

/// Surfaces AI chat telemetry (opt-in, local-only). Shows top tools, top
/// failure intents, and latency percentiles so we can see real-world failure
/// hot-spots instead of gold-set assumptions. #261.
struct AIChatInsightsView: View {
    @State private var tools: [ChatTelemetryService.ToolStat] = []
    @State private var failures: [ChatTelemetryService.ToolStat] = []
    @State private var latency: ChatTelemetryService.LatencyStat = .init(p50: 0, p95: 0, count: 0)
    @State private var totalTurns: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                if totalTurns == 0 {
                    emptyState
                } else {
                    latencyCard
                    toolCard(title: "Top tools", stats: tools, emphasizeFailures: true)
                    toolCard(title: "Top failure routes", stats: failures, emphasizeFailures: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("AI Chat Insights")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: reload)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("On-device only")
                    .font(.caption2).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(totalTurns) turns")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text("No raw query text is stored. Only a short hash, the routed tool, and success or failure.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title2).foregroundStyle(.tertiary)
            Text("No chat turns recorded yet.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(Preferences.chatTelemetryEnabled
                 ? "Send a chat message to populate this view."
                 : "Turn on AI Chat Telemetry in Settings to start recording.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .card()
    }

    private var latencyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latency")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                statTile(label: "p50", value: "\(latency.p50) ms")
                statTile(label: "p95", value: "\(latency.p95) ms")
                statTile(label: "samples", value: "\(latency.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func toolCard(title: String, stats: [ChatTelemetryService.ToolStat], emphasizeFailures: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if stats.isEmpty {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(stats, id: \.tool) { stat in
                    HStack {
                        Text(stat.tool)
                            .font(.subheadline).foregroundStyle(.primary)
                        Spacer()
                        if emphasizeFailures && stat.failed > 0 {
                            Text("\(stat.failed) failed")
                                .font(.caption2).foregroundStyle(Theme.surplus)
                        }
                        Text("\(stat.count)")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.fontStat).foregroundStyle(.primary)
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reload() {
        let service = ChatTelemetryService.shared
        tools = service.topTools()
        failures = service.topFailures()
        latency = service.latency()
        totalTurns = service.count()
    }
}
