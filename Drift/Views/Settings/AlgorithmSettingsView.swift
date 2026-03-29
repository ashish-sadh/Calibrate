import SwiftUI

struct AlgorithmSettingsView: View {
    @State private var config = WeightTrendCalculator.loadConfig()
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Presets
                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        presetButton("Conservative", config: .conservative,
                                     detail: "Lower deficit estimates, closer to MacroFactor")
                        presetButton("Default", config: .default,
                                     detail: "Balanced smoothing and energy density")
                        presetButton("Responsive", config: .responsive,
                                     detail: "Faster reaction, traditional 7700 kcal/kg")
                    }
                }
                .card()

                // EMA Alpha
                parameterCard(
                    title: "EMA Smoothing (alpha)",
                    value: $config.emaAlpha,
                    range: 0.03...0.25,
                    step: 0.01,
                    format: "%.2f",
                    description: "Controls how much today's weight influences the trend. Lower = smoother trend that ignores daily fluctuations. Higher = trend reacts faster to real changes but is noisier.",
                    low: "0.05 smooth",
                    high: "0.20 responsive"
                )

                // Regression Window
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Regression Window")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(config.regressionWindowDays) days")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }

                    Slider(value: Binding(
                        get: { Double(config.regressionWindowDays) },
                        set: { config.regressionWindowDays = Int($0) }
                    ), in: 7...35, step: 1)
                    .tint(Theme.accent)

                    HStack {
                        Text("7 days").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("35 days").font(.caption2).foregroundStyle(.tertiary)
                    }

                    Text("How many days of trend data to use for calculating your weekly rate and deficit. MacroFactor uses ~20 days. Shorter = faster to detect changes. Longer = more stable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .card()

                // Energy Density
                parameterCard(
                    title: "Energy Density (kcal/kg)",
                    value: $config.kcalPerKg,
                    range: 4000...8000,
                    step: 100,
                    format: "%.0f",
                    description: "How many calories correspond to 1 kg of body weight change. The traditional rule is 7700 (pure fat), but real-world weight loss includes water and glycogen. If Drift shows a higher deficit than MacroFactor, lower this value.",
                    low: "4000 (early diet)",
                    high: "7700 (pure fat)"
                )

                // Current estimate
                if let example = exampleDeficit {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Example")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("At a rate of -0.27 kg/week, this config estimates a daily deficit of **\(example) kcal**.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("MacroFactor shows -296 kcal for this rate.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .card()
                }

                // Save button
                Button {
                    WeightTrendCalculator.saveConfig(config)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                } label: {
                    HStack {
                        Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        Text(saved ? "Saved" : "Save Configuration")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(saved ? Theme.deficit : Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Algorithm")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func presetButton(_ name: String, config preset: WeightTrendCalculator.AlgorithmConfig, detail: String) -> some View {
        Button {
            config = preset
        } label: {
            VStack(spacing: 4) {
                Text(name)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isCurrentPreset(preset) ? Theme.accent.opacity(0.2) : Theme.cardBackgroundElevated,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    private func isCurrentPreset(_ preset: WeightTrendCalculator.AlgorithmConfig) -> Bool {
        abs(config.emaAlpha - preset.emaAlpha) < 0.001 &&
        config.regressionWindowDays == preset.regressionWindowDays &&
        abs(config.kcalPerKg - preset.kcalPerKg) < 1
    }

    private func parameterCard(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String, description: String, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }

            Slider(value: value, in: range, step: step)
                .tint(Theme.accent)

            HStack {
                Text(low).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(high).font(.caption2).foregroundStyle(.tertiary)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var exampleDeficit: Int? {
        // -0.27 kg/week is from the MacroFactor screenshot
        let weeklyRate = -0.27
        let dailyDeficit = weeklyRate * config.kcalPerKg / 7
        return Int(dailyDeficit)
    }
}
