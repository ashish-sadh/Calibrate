import SwiftUI
import DriftCore
import PhotosUI

/// Chat-style AI assistant — chain-of-thought reasoning with smart suggestion pills.
///
/// View body owns the layout shell (scroll view, input bar, sheet bindings). All
/// state lives on `AIChatViewModel`; messageBubble + cards live in extension files.
struct AIChatView: View {
    @State var vm = AIChatViewModel()
    @FocusState var inputFocused: Bool
    @State var photoPickerItem: PhotosPickerItem? = nil

    /// Optional pre-filled input — used by VoiceLogSheet's "Edit in chat"
    /// hand-off so the user can refine a transcript before sending.
    let prefill: String

    init(prefill: String = "") {
        self.prefill = prefill
    }

    var body: some View {
        // V7: DriftCoachSheet owns the visible backend picker now, so
        // AIChatView no longer renders an inline `backendSelectorHeader`
        // (the old "Local Brain | Cloud AI" tiles). Removed to avoid two
        // stacked pickers.
        VStack(spacing: 0) {
            if isEmptyState {
                // Voice-first hero: a big tap-to-talk circle. The user can also
                // type or attach an image via the input bar below.
                Spacer(minLength: 0)
                ListeningCircle(state: circleState, onTap: startOrStopVoice)
                if !vm.pageInsight.isEmpty {
                    Text(vm.pageInsight)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36).padding(.top, 10)
                }
                Spacer(minLength: 0)
            } else {
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
            }

            // Apple Foundation Models is system-managed and ready
            // synchronously — there's no model file to load, no
            // download to wait for. Suppress the "Preparing AI
            // assistant..." spinner for that backend; it stays valid
            // for Drift Brain (GGUF) and BYOK cloud (handshake).
            if case .loading = vm.aiService.state,
               vm.activeBackend != .foundationModels {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Preparing AI assistant...")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            if !vm.isGenerating {
                suggestionsRow
            }

            if !vm.pendingUndoEntryIds.isEmpty {
                undoChip
            }

            Divider().overlay(Theme.separator)

            inputBar
        }
        .sheet(isPresented: $vm.showingFoodSearch, onDismiss: { vm.mealLogRevision += 1 }) {
            // FoodSearchView owns its own NavigationStack + toolbar Done — no
            // outer wrapper, or the sheet shows two "Done" buttons.
            FoodSearchView(viewModel: FoodLogViewModel(), initialQuery: vm.foodSearchQuery, initialServings: vm.foodSearchServings, initialMealType: vm.foodSearchMealType)
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
            if !prefill.isEmpty && vm.inputText.isEmpty {
                vm.inputText = prefill
                inputFocused = true
            }
            if !vm.aiService.isModelLoaded && vm.aiService.state == .ready {
                vm.aiService.loadModel()
            }
        }
        .onDisappear {
            vm.aiService.scheduleUnload(delay: 60)
        }
    }

    // MARK: - Listening-circle hero (voice-first empty state)

    /// Empty state = no real conversation yet (just the seeded greeting). The
    /// greeting is appended as a message in onAppear, so `messages.isEmpty` is
    /// never true after first render — match the greeting-only case explicitly.
    var isEmptyState: Bool {
        if vm.messages.isEmpty { return true }
        return vm.messages.count == 1
            && vm.messages[0].role == .assistant
            && vm.messages[0].text == vm.pageInsight
    }

    /// Drive the hero circle's animation/caption from the live voice + generation
    /// state. Precedence: speaking > processing > listening > idle.
    var circleState: ListeningCircle.CircleState {
        if case .unavailable = vm.speechService.recordingState { return .unavailable }
        if vm.voiceService.isSpeaking { return .speaking }
        if vm.isGenerating { return .processing }
        if vm.speechService.isRecording { return .listening }
        return .idle
    }

    /// One voice flow shared by the hero circle and the small mic button — start
    /// recording (auto-sends on silence/stop), or stop speaking if the coach is
    /// mid-reply. Prevents duplicated callback logic / double-sends.
    func startOrStopVoice() {
        if vm.voiceService.isSpeaking { vm.voiceService.stop(); return }
        // Talking to the coach implies it talks back — turn on Apple TTS
        // (CoachVoiceService) for this session when starting a voice turn.
        if !vm.speechService.isRecording && !vm.voiceOutputEnabled {
            vm.toggleVoiceOutput()
        }
        vm.voiceService.stop()
        vm.speechService.toggleRecording(
            onTranscript: { self.vm.inputText = $0 },
            onDone: {
                self.vm.inputText = VoiceTranscriptionPostFixer.fix($0)
                self.vm.sendMessage()
            }
        )
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
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.pillBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 0.5))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    // MARK: - 10-second Undo Chip (after photo meal card confirm)

    private var undoChip: some View {
        HStack {
            Spacer()
            Button { vm.undoProposedMeal() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                    Text("Undo")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Color.red.opacity(0.75)))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
