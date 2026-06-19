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
        Group {
            if vm.talkModeEnabled {
                ImmersiveVoiceView(
                    state: circleState,
                    caption: immersiveCaption,
                    proposal: immersiveProposal,
                    onCircleTap: startOrStopVoice,
                    onConfirm: confirmFromImmersive,
                    onCancel: cancelFromImmersive,
                    onExit: { vm.toggleTalkMode() })
            } else {
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
            }
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
            // Cloud-first coach. Install the Nebius brain SYNCHRONOUSLY here so the
            // very first turn routes remote — the old async `.task` install raced the
            // user's first message and the turn fell through to on-device Gemma. And
            // when the cloud coach is configured, do NOT warm the local model: loading
            // ~2.9GB of Gemma is pure waste on the cloud path and slow on A19 Pro
            // (Metal falls back to CPU). Only warm on-device when there's no cloud
            // brain to serve the turn. #coach-speed
            if AIBackendCoordinator.hasCoachCloud {
                AIBackendCoordinator.installCoachBackend()
            } else if !vm.aiService.isModelLoaded && vm.aiService.state == .ready {
                vm.aiService.loadModel()
            }
        }
        .onDisappear {
            vm.aiService.scheduleUnload(delay: 60)
            vm.voiceService.stop()
        }
        .onChange(of: vm.rearmMicTick) { _, _ in rearmMic() }
        .onChange(of: vm.talkModeEnabled) { _, on in handleTalkModeChange(on) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { talkModeToggleButton }
        }
    }

    // MARK: - Immersive talk-mode

    /// The top speaker button — master switch into/out of full-screen talk-mode.
    var talkModeToggleButton: some View {
        Button { vm.toggleTalkMode() } label: {
            Image(systemName: vm.talkModeEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(vm.talkModeEnabled ? Theme.accent : Theme.textSecondary)
        }
        .accessibilityLabel(vm.talkModeEnabled ? "Talk mode on" : "Talk mode off")
        .accessibilityIdentifier("coach-talk-toggle")
    }

    /// Live caption under the immersive circle: your words while listening, the
    /// coach's last reply while it speaks / awaits a confirm, blank otherwise
    /// (the circle's own caption covers idle/thinking).
    var immersiveCaption: String {
        if vm.speechService.isRecording { return vm.speechService.transcript }
        if vm.isGenerating { return "" }
        if vm.voiceService.isSpeaking || vm.pendingProposalTurnId != nil {
            return vm.messages.last(where: { $0.role == .assistant })?.text ?? ""
        }
        return ""
    }

    /// The pending meal proposal, surfaced as the immersive Confirm/Cancel card.
    var immersiveProposal: AIChatViewModel.ProposedMealCardData? {
        guard let id = vm.pendingProposalTurnId else { return nil }
        return vm.messages.first(where: { $0.id == id })?.proposedMealCard
    }

    /// Tap-Confirm (the tap half of dual confirm) — commit the proposed meal,
    /// then speak + keep listening.
    func confirmFromImmersive() {
        guard let id = vm.pendingProposalTurnId,
              let card = vm.messages.first(where: { $0.id == id })?.proposedMealCard else { return }
        vm.confirmProposedMeal(card, messageId: id)
        vm.speakVoiceTurn(reply: "Logged it.", action: nil)
    }

    /// Tap-Cancel — skip the proposed meal, then speak + keep listening.
    func cancelFromImmersive() {
        guard let id = vm.pendingProposalTurnId else { return }
        if let idx = vm.messages.firstIndex(where: { $0.id == id }) {
            vm.messages[idx].proposedMealCard = nil
            vm.messages[idx].text = "Okay, skipped that."
        }
        vm.clearPendingProposal()
        vm.speakVoiceTurn(reply: "Okay, cancelled.", action: nil)
    }

    /// Entering talk-mode starts listening right away (hands-free); leaving it
    /// halts the mic + any speech so nothing keeps running behind the text UI.
    func handleTalkModeChange(_ on: Bool) {
        if on {
            if !vm.isGenerating, !vm.voiceService.isSpeaking, !vm.speechService.isRecording {
                beginListening()
            }
        } else {
            vm.speechService.forceStop()
            vm.voiceService.stop()
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
        beginListening()
    }

    /// Start (or toggle-stop) voice capture. onDone auto-sends and flags the turn
    /// as voice so the coach speaks its reply and re-arms the mic afterward.
    func beginListening() {
        vm.voiceService.stop()
        vm.speechService.toggleRecording(
            onTranscript: { self.vm.inputText = $0 },
            onDone: { self.vm.submitVoiceTurn($0) }
        )
    }

    /// Re-open the mic after the coach finishes speaking (the hands-free loop).
    /// Guarded so it never opens on top of an in-flight turn or active speech.
    func rearmMic() {
        guard vm.voiceOutputEnabled, !vm.isGenerating,
              !vm.speechService.isRecording, !vm.voiceService.isSpeaking else { return }
        beginListening()
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
