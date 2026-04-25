import SwiftUI
import DriftCore
import PhotosUI

/// Chat-style AI assistant with chain-of-thought reasoning and smart suggestion pills.
struct AIChatView: View {
    @State var vm = AIChatViewModel()
    @FocusState var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.messages) { msg in
                            messageBubble(msg).id(msg.id)
                        }
                        if vm.isGenerating {
                            thinkingIndicator
                        }
                    }
                    .padding(.top, 6)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: vm.messages.last?.text) { _, _ in
                    if vm.streamingMessageId != nil, let last = vm.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Model loading indicator
            if case .loading = vm.aiService.state {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Preparing AI assistant...")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            // Smart suggestion pills
            if !vm.isGenerating {
                suggestionsRow
            }

            Divider().overlay(Color.white.opacity(0.06))

            // Disclaimer note
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                Text("Small on-device model \u{2014} responses may not be perfect. Data never leaves your phone. Thank you for testing! Next release will be faster and smarter. Turn off in More \u{2192} Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.03))

            // Input bar
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent.opacity(0.6))

                TextField(vm.speechService.isRecording ? "Listening..." : "Ask anything...", text: $vm.inputText, axis: .vertical)
                    .textFieldStyle(.plain).font(.subheadline)
                    .lineLimit(1...(vm.speechService.isRecording ? 6 : 3)).focused($inputFocused)
                    .onSubmit { vm.sendMessage() }

                if vm.speechService.isRecording {
                    Button {
                        vm.speechService.forceStop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.surplus)
                    }
                    .accessibilityLabel("Stop recording")

                    Button {
                        vm.speechService.gracefulStop()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Send message")
                } else {
                    Button {
                        vm.speechService.toggleRecording(
                            onTranscript: { text in
                                self.vm.inputText = text
                            },
                            onDone: { finalText in
                                self.vm.inputText = VoiceTranscriptionPostFixer.fix(finalText)
                                self.vm.sendMessage()
                            }
                        )
                    } label: {
                        Image(systemName: "mic")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Voice input")
                    .disabled(vm.isGenerating)

                    Button { vm.sendMessage() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                            .foregroundStyle(vm.inputText.isEmpty ? Color.secondary.opacity(0.5) : Theme.accent)
                    }
                    .accessibilityLabel("Send message")
                    .disabled(vm.inputText.isEmpty || vm.isGenerating)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(vm.speechService.isRecording ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1.5)
                    )
            )
            .animation(.easeInOut(duration: 0.3), value: vm.speechService.isRecording)
            .padding(.horizontal, 8).padding(.bottom, 4)
        }
        .sheet(isPresented: $vm.showingFoodSearch, onDismiss: { vm.mealLogRevision += 1 }) {
            NavigationStack {
                FoodSearchView(viewModel: FoodLogViewModel(), initialQuery: vm.foodSearchQuery, initialServings: vm.foodSearchServings, initialMealType: vm.foodSearchMealType)
            }
        }
        .sheet(isPresented: $vm.showingWorkout) {
            if let template = vm.workoutTemplate {
                NavigationStack {
                    ActiveWorkoutView(template: template) {
                        vm.showingWorkout = false
                        vm.workoutTemplate = nil
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $vm.showingBarcodeScanner) {
            BarcodeLookupView(viewModel: FoodLogViewModel())
        }
        .sheet(isPresented: $vm.showingRecipeBuilder, onDismiss: {
            vm.pendingRecipeItems = []
            vm.pendingRecipeName = ""
        }) {
            QuickAddView(viewModel: FoodLogViewModel(),
                         initialItems: vm.pendingRecipeItems,
                         initialName: vm.pendingRecipeName)
        }
        .sheet(isPresented: $vm.showingManualFoodEntry, onDismiss: {
            vm.pendingManualFoodEntry = nil
        }) {
            ManualFoodEntrySheet(viewModel: FoodLogViewModel(),
                                 prefill: vm.pendingManualFoodEntry,
                                 onLogged: { vm.showingManualFoodEntry = false })
        }
        .onAppear {
            vm.aiService.cancelUnload()
            if vm.messages.isEmpty {
                vm.messages.append(AIChatViewModel.ChatMessage(role: .assistant, text: vm.pageInsight))
            }
            if !vm.aiService.isModelLoaded && vm.aiService.state == .ready {
                vm.aiService.loadModel()
            }
        }
        .onDisappear {
            vm.aiService.scheduleUnload(delay: 60)
        }
    }

    // MARK: - Suggestions Row

    var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.smartSuggestions, id: \.self) { suggestion in
                    Button {
                        vm.inputText = suggestion
                        vm.sendMessage()
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                TypingDotsView()
                let stageLabel: String = switch vm.generatingState {
                case .thinking(let step): step
                case .generating: "Writing response..."
                case .idle: ""
                }
                if !stageLabel.isEmpty {
                    Text(stageLabel)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .id(stageLabel)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.generatingState)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.cardBackground, in: UnevenRoundedRectangle(
                topLeadingRadius: 16, bottomLeadingRadius: 4,
                bottomTrailingRadius: 16, topTrailingRadius: 16
            ))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 10)
        .transition(.opacity)
    }

    // MARK: - Typewriter Text

    private struct TypewriterText: View {
        let text: String
        @State private var revealed: Int = 0
        @State private var done = false

        var body: some View {
            Text(done ? text : String(text.prefix(revealed)))
                .onAppear {
                    guard !text.isEmpty, !done else { return }
                    let total = text.count
                    let charsPerTick = max(1, total / 40)
                    Task {
                        while revealed < total {
                            try? await Task.sleep(for: .milliseconds(18))
                            revealed = min(revealed + charsPerTick, total)
                        }
                        done = true
                    }
                }
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(_ msg: AIChatViewModel.ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if msg.role == .user {
                Spacer(minLength: 60)
            }

            if msg.role == .assistant {
                Image(systemName: "sparkles").font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20, height: 20)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .padding(.bottom, 2)
            }

            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 6) {
                if !msg.text.isEmpty {
                    let isNewInstant = msg.role == .assistant
                        && msg.id != vm.streamingMessageId
                        && Date().timeIntervalSince(msg.createdAt) < 1.0
                    Group {
                        if isNewInstant {
                            TypewriterText(text: msg.text)
                        } else {
                            Text(msg.text)
                        }
                    }
                        .font(.subheadline)
                        .foregroundStyle(msg.role == .user ? .white : Theme.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            msg.role == .user
                                ? AnyShapeStyle(Theme.accent.opacity(0.25))
                                : AnyShapeStyle(Theme.cardBackground),
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: msg.role == .user ? 16 : 4,
                                bottomTrailingRadius: msg.role == .user ? 4 : 16,
                                topTrailingRadius: 16
                            )
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: msg.role == .user ? 16 : 4,
                                bottomTrailingRadius: msg.role == .user ? 4 : 16,
                                topTrailingRadius: 16
                            )
                            .strokeBorder(
                                msg.role == .user
                                    ? Theme.accent.opacity(0.15)
                                    : Theme.separator,
                                lineWidth: 0.5
                            )
                        )
                }

                if let card = msg.foodCard {
                    foodConfirmationCard(card)
                }
                if let card = msg.nutritionCard {
                    nutritionLookupCard(card)
                }
                if let card = msg.weightCard {
                    weightConfirmationCard(card)
                }
                if let card = msg.workoutCard {
                    workoutConfirmationCard(card)
                }
                if let card = msg.navigationCard {
                    navigationConfirmationCard(card)
                }
                if let card = msg.supplementCard {
                    supplementConfirmationCard(card)
                }
                if let card = msg.sleepCard {
                    sleepConfirmationCard(card)
                }
                if let card = msg.glucoseCard {
                    glucoseConfirmationCard(card)
                }
                if let card = msg.biomarkerCard {
                    biomarkerConfirmationCard(card)
                }
                if let options = msg.clarificationOptions, !options.isEmpty {
                    clarificationChips(options)
                }
            }
            .accessibilityLabel(msg.role == .user ? "You said: \(msg.text)" : "Assistant: \(msg.text)")

            if msg.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Clarification Chips (#226)

    /// Tappable chips rendered under a "Did you mean:" message. Tapping a
    /// chip sends its label as a new user message — the VM's
    /// `handleClarificationResponse` picks the option by label match.
    private func clarificationChips(_ options: [ClarificationOption]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(options) { opt in
                Button {
                    vm.inputText = "\(opt.id)"
                    vm.sendMessage()
                } label: {
                    HStack(spacing: 8) {
                        Text("\(opt.id).")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Text(opt.label)
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.accent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.accent.opacity(0.25), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isGenerating)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    // MARK: - Nutrition Lookup Card

    private func nutritionLookupCard(_ card: AIChatViewModel.NutritionLookupCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption).foregroundStyle(Theme.calorieBlue)
                Text(card.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("per \(card.servingSize)\(card.servingUnit)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Per-serving row
            HStack(spacing: 0) {
                ForEach([
                    (value: card.servingCalories, label: "cal",     color: Theme.calorieBlue),
                    (value: card.servingProteinG, label: "protein",  color: Theme.proteinRed),
                    (value: card.servingCarbsG,   label: "carbs",    color: Theme.carbsGreen),
                    (value: card.servingFatG,      label: "fat",      color: Theme.fatYellow),
                ], id: \.label) { item in
                    VStack(spacing: 2) {
                        Text(item.label == "cal" ? "\(item.value)" : "\(item.value)g")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(item.color)
                        Text(item.label).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Per-100g row
            HStack {
                Text("per 100g:")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                Text("\(card.calories100g) cal · \(card.proteinG100g)g P · \(card.carbsG100g)g C · \(card.fatG100g)g F")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }

            Button {
                vm.inputText = "log \(card.name.lowercased())"
                Task { await vm.sendMessage() }
            } label: {
                Label("Log it", systemImage: "plus.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.calorieBlue)
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.calorieBlue.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Food Confirmation Card

    private func foodConfirmationCard(_ card: AIChatViewModel.FoodCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fork.knife")
                    .font(.caption).foregroundStyle(Theme.calorieBlue)
                Text(card.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                // Meal type picker — tapping cycles through options
                Menu {
                    ForEach(MealType.allCases, id: \.self) { meal in
                        Button {
                            vm.foodSearchMealType = meal
                            vm.showingFoodSearch = true
                        } label: {
                            Label(meal.displayName, systemImage: meal.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: card.mealType.icon)
                        Text(card.mealType.displayName)
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.accent.opacity(0.8))
                }
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(card.calories)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.calorieBlue)
                    Text("cal").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.proteinG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.proteinRed)
                    Text("protein").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.carbsG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.carbsGreen)
                    Text("carbs").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.fatG)g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.fatYellow)
                    Text("fat").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.calorieBlue.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Weight Confirmation Card

    private func weightConfirmationCard(_ card: AIChatViewModel.WeightCardData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass.fill")
                .font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%.1f", card.value)) \(card.unit)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if let trend = card.trend {
                    Text(trend)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.title3)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Workout Confirmation Card

    private func workoutConfirmationCard(_ card: AIChatViewModel.WorkoutCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.title3).foregroundStyle(Theme.accentSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.subheadline.weight(.bold))
                    HStack(spacing: 8) {
                        if let mins = card.durationMin {
                            Label("\(mins) min", systemImage: "clock")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let count = card.exerciseCount {
                            Label("\(count) exercises", systemImage: "list.bullet")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if card.confirmed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.title3)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Theme.accentSecondary.opacity(0.5)).font(.title3)
                }
            }

            if !card.muscleGroups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(card.muscleGroups, id: \.self) { group in
                        Label(group, systemImage: muscleIcon(group))
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.accentSecondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.accentSecondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accentSecondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func muscleIcon(_ group: String) -> String {
        switch group {
        case "Chest": "figure.arms.open"
        case "Back": "figure.walk"
        case "Shoulders": "figure.flexibility"
        case "Arms": "figure.boxing"
        case "Core": "figure.core.training"
        case "Legs": "figure.run"
        default: "figure.stand"
        }
    }

    // MARK: - Navigation Confirmation Card

    private func navigationConfirmationCard(_ card: AIChatViewModel.NavigationCardData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: card.icon)
                .font(.title3).foregroundStyle(Theme.accent)
            Text(card.destination)
                .font(.subheadline.weight(.bold))
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(Theme.accent.opacity(0.6)).font(.title3)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Supplement Confirmation Card

    private func supplementConfirmationCard(_ card: AIChatViewModel.SupplementCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pills.fill")
                    .font(.caption).foregroundStyle(Theme.accent)
                if let action = card.action {
                    Text(action)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text("Supplements")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Text("\(card.taken)/\(card.total)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(card.taken == card.total ? .green : Theme.accent)
            }

            if !card.remaining.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "circle")
                        .font(.system(size: 6)).foregroundStyle(.tertiary)
                    Text("Need: \(card.remaining.joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Text("All done for today")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Sleep & Recovery Card

    private func sleepConfirmationCard(_ card: AIChatViewModel.SleepCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "moon.fill")
                    .font(.caption).foregroundStyle(.indigo)
                Text("Sleep & Recovery")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let readiness = card.readiness {
                    Text(readiness)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(readinessColor(readiness))
                }
            }

            HStack(spacing: 0) {
                if let hours = card.sleepHours {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", hours))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.indigo)
                        Text("hours").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let score = card.recoveryScore, score > 0 {
                    VStack(spacing: 2) {
                        Text("\(score)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(score >= 70 ? .green : score >= 40 ? .orange : .red)
                        Text("recovery").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let hrv = card.hrvMs, hrv > 0 {
                    VStack(spacing: 2) {
                        Text("\(hrv)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text("HRV ms").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let rhr = card.restingHR, rhr > 0 {
                    VStack(spacing: 2) {
                        Text("\(rhr)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.proteinRed)
                        Text("RHR").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let rem = card.remHours, let deep = card.deepHours {
                HStack(spacing: 12) {
                    Label(String(format: "%.1fh REM", rem), systemImage: "brain.head.profile")
                        .font(.caption2).foregroundStyle(.secondary)
                    Label(String(format: "%.1fh deep", deep), systemImage: "bed.double.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.indigo.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func readinessColor(_ readiness: String) -> Color {
        if readiness.contains("Good") { return .green }
        if readiness.contains("Moderate") { return .orange }
        if readiness.contains("Low") { return .red }
        return .secondary
    }

    // MARK: - Glucose Confirmation Card

    private func glucoseConfirmationCard(_ card: AIChatViewModel.GlucoseCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.caption).foregroundStyle(.orange)
                Text("Glucose")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(card.readingCount) readings")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(card.avgMgdl)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                    Text("avg mg/dL").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.minMgdl)–\(card.maxMgdl)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text("range").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.inZonePct)%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(card.inZonePct >= 70 ? .green : .orange)
                    Text("in zone").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 2) {
                    Text("\(card.spikeCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(card.spikeCount == 0 ? .green : .red)
                    Text("spikes").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Biomarker Confirmation Card

    private func biomarkerConfirmationCard(_ card: AIChatViewModel.BiomarkerCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "testtube.2")
                    .font(.caption).foregroundStyle(.cyan)
                Text("Biomarkers")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(card.optimalCount)/\(card.totalCount) optimal")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(card.outOfRange.isEmpty ? .green : .orange)
            }

            if card.outOfRange.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Text("All markers in optimal range")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(card.outOfRange.prefix(4), id: \.name) { marker in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(marker.status.contains("high") || marker.status.contains("High") ? .red : .orange)
                                .frame(width: 5, height: 5)
                            Text(marker.name)
                                .font(.caption2.weight(.medium))
                            Spacer()
                            Text(marker.value)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if card.outOfRange.count > 4 {
                        Text("+\(card.outOfRange.count - 4) more")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 0.5)
        )
    }
}
