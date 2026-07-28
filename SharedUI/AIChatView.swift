import SwiftUI
import DriftCore
#if canImport(PhotosUI)
import PhotosUI
#endif

/// Chat-style AI assistant — chain-of-thought reasoning with smart suggestion pills.
///
/// View body owns the layout shell (scroll view, input bar, sheet bindings). All
/// state lives on `AIChatViewModel`; messageBubble + cards live in extension files.
struct AIChatView: View {
    @State var vm = AIChatViewModel()
    @FocusState var inputFocused: Bool
    #if DRIFT_IOS_APP
    @State var photoPickerItem: PhotosPickerItem? = nil
    #endif
    // Not `private` — Skip Fuse can't bridge private @Environment state. #1066
    @Environment(\.dismiss) var dismiss

    /// Optional pre-filled input — used by VoiceLogSheet's "Edit in chat"
    /// hand-off so the user can refine a transcript before sending.
    let prefill: String
    let autoSubmit: Bool

    init(prefill: String = "", autoSubmit: Bool = false) {
        self.prefill = prefill
        self.autoSubmit = autoSubmit
    }

    var body: some View {
        // V7: DriftCoachSheet owns the visible backend picker now, so
        // AIChatView no longer renders an inline `backendSelectorHeader`
        // (the old "Local Brain | Cloud AI" tiles). Removed to avoid two
        // stacked pickers.
        Group {
            // Talk mode (ImmersiveVoiceView) is iOS-only for v1 — its toggle is
            // hidden on Android and `talkModeEnabled` defaults off there, so this
            // branch is never taken on Android; gate the body so it compiles. #1066
            if vm.talkModeEnabled {
                #if DRIFT_IOS_APP
                ImmersiveVoiceView(
                    state: circleState,
                    caption: immersiveCaption,
                    proposal: immersiveProposal,
                    onCircleTap: startOrStopVoice,
                    onConfirm: confirmFromImmersive,
                    onCancel: cancelFromImmersive,
                    onExit: { vm.toggleTalkMode() })
                #endif
            } else {
            VStack(spacing: 0) {
            coachHeader
            if isEmptyState {
                // Voice-first hero: a big tap-to-talk circle. The user can also
                // type or attach an image via the input bar below.
                Spacer(minLength: 0)
                #if DRIFT_IOS_APP
                ListeningCircle(state: circleState, onTap: startOrStopVoice)
                #else
                // Voice hero (ListeningCircle) is iOS-only for v1 — a static
                // sparkle prompt; tapping it focuses the input. SparkleShape lives
                // in the DriftAndroid module (present in both Skip passes). #1066
                Button { inputFocused = true } label: {
                    VStack(spacing: 12) {
                        SparkleShape().fill(Theme.accent).frame(width: 46, height: 46)
                        Text("Ask me anything")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                #endif
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
                            // Scroll sentinel — Fuse's `scrollTo(id)` on a message
                            // id is unreliable, so Android scrolls to this fixed
                            // id instead ([SharedUI/ChatView] pattern). #1066
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.top, 6)
                    }
                    #if os(Android)
                    .onChange(of: vm.messages.count) { _, _ in proxy.scrollTo("bottom") }
                    .onChange(of: vm.messages.last?.text) { _, _ in
                        if vm.streamingMessageId != nil { proxy.scrollTo("bottom") }
                    }
                    #else
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
                    #endif
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
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
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
            // #premium-polish: chat's primary interaction snapped on every turn
            // — the suggestions row, thinking indicator and undo chip appeared
            // and vanished with hard layout jumps (their `.transition`s were
            // dead without an animation driving the state change). Drive the
            // layout changes on the shared passive curve so bubbles, the
            // thinking dots and the undo chip ease in/out.
            .animation(Theme.Motion.passive, value: vm.messages.count)
            .animation(Theme.Motion.passive, value: vm.isGenerating)
            .animation(Theme.Motion.passive, value: vm.pendingUndoEntryIds.isEmpty)
            }
        }
        #if DRIFT_IOS_APP
        .sheet(isPresented: $vm.showingFoodSearch, onDismiss: { vm.mealLogRevision += 1 }) {
            // FoodSearchView owns its own NavigationStack + toolbar Done — no
            // outer wrapper, or the sheet shows two "Done" buttons.
            FoodSearchView(viewModel: FoodLogViewModel(), initialQuery: vm.foodSearchQuery, initialServings: vm.foodSearchServings, initialMealType: vm.foodSearchMealType, initialSelection: vm.foodSearchResolvedName, initialSelectionId: vm.foodSearchResolvedId)
        }
        #endif
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
        #if DRIFT_IOS_APP
        // The food-logging sheets aren't ported to Android yet (#1062); on Android
        // the triggers degrade to an assistant message (see the onChange handlers
        // below). Workout stays live above — ActiveWorkoutView is already SharedUI.
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
        .sheet(isPresented: $vm.showingMealReview, onDismiss: { vm.pendingMealReviewItems = [] }) {
            // "Log my usual lunch" → the editable Snap review sheet, pre-filled.
            MealReviewSheet(
                items: vm.pendingMealReviewItems,
                foodLog: FoodLogViewModel(),
                onLogged: {
                    vm.showingMealReview = false
                    vm.mealLogRevision += 1
                })
        }
        #elseif os(Android)
        // Android: a chat turn that wants an un-ported food sheet degrades to an
        // assistant message instead of a dead flag flip. #1066 / #1062
        .onChange(of: vm.showingFoodSearch) { _, s in if s { vm.showingFoodSearch = false; degradeUnportedSheet() } }
        .onChange(of: vm.showingRecipeBuilder) { _, s in if s { vm.showingRecipeBuilder = false; degradeUnportedSheet() } }
        .onChange(of: vm.showingManualFoodEntry) { _, s in if s { vm.showingManualFoodEntry = false; degradeUnportedSheet() } }
        .onChange(of: vm.showingMealReview) { _, s in if s { vm.showingMealReview = false; degradeUnportedSheet() } }
        .onChange(of: vm.showingBarcodeScanner) { _, s in if s { vm.showingBarcodeScanner = false; degradeUnportedSheet() } }
        #endif
        .onAppear {
            vm.aiService.cancelUnload()
            if vm.messages.isEmpty {
                vm.messages.append(AIChatViewModel.ChatMessage(role: .assistant, text: vm.pageInsight))
            }
            if !prefill.isEmpty && vm.inputText.isEmpty && !autoSubmit {
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
            #if DRIFT_IOS_APP
            if AIBackendCoordinator.hasCoachCloud {
                AIBackendCoordinator.installCoachBackend()
            } else if !vm.aiService.isModelLoaded && vm.aiService.state == .ready {
                vm.aiService.loadModel()
            }
            #else
            // Android (+ the Darwin bridging pass) is Nebius-only — no local model,
            // no backend picker. Install the cloud brain synchronously so the first
            // turn routes remote (mirrors ActiveWorkoutView's askCoach path). #1066
            if CoachCloud.isConfigured { CoachCloud.install() }
            #endif
            // #936: Ask-AI questions fire as a real turn immediately — never
            // left stuck in the input. AFTER the backend install above, or
            // the very first turn races the cloud brain and falls to Gemma.
            if autoSubmit && !prefill.isEmpty && vm.inputText.isEmpty {
                vm.inputText = prefill
                vm.sendMessage()
            }
        }
        .onDisappear {
            vm.aiService.scheduleUnload(delay: 60)
            vm.voiceService.stop()
        }
        .onChange(of: vm.rearmMicTick) { _, _ in rearmMic() }
        .onChange(of: vm.talkModeEnabled) { _, on in handleTalkModeChange(on) }
    }

    // MARK: - Header (voice cluster + title + close)

    /// Custom sheet header replacing the system nav bar. Voice is the coach's
    /// marquee interaction, so its controls sit top-leading at full tap size:
    /// the speaker is THE mute switch for spoken replies (#937 single source
    /// of truth — it used to hide in the input bar behind the recording
    /// controls), and the waveform beside it enters hands-free talk mode.
    /// Replaces the old speaker-slash talk-mode icon that read as "muted"
    /// while speech stayed on.
    var coachHeader: some View {
        ZStack {
            Text("Drift Coach")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            HStack {
                #if DRIFT_IOS_APP
                voiceCluster
                #endif
                Spacer()
                closeButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    #if DRIFT_IOS_APP
    /// Speaker (mute switch) + waveform (talk mode) in one floating capsule.
    /// iOS-app-only: Haptics + `symbolEffect` are unavailable off-Apple and the
    /// whole voice cluster is hidden on Android for v1 (#1066).
    var voiceCluster: some View {
        HStack(spacing: 2) {
            Button {
                Haptics.lightTap()
                if vm.voiceService.isSpeaking { vm.voiceService.stop() } else { vm.toggleVoiceOutput() }
            } label: {
                Image(systemName: vm.voiceOutputEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: vm.voiceService.isSpeaking)
                    .foregroundStyle(vm.voiceOutputEnabled ? Color.white : Theme.textSecondary)
                    .frame(width: 42, height: 36)
                    .background {
                        if vm.voiceOutputEnabled { Capsule().fill(Theme.accent) }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vm.voiceOutputEnabled ? "Mute spoken replies" : "Speak replies aloud")
            .accessibilityIdentifier("coach-speaker-toggle")

            Button {
                Haptics.lightTap()
                vm.toggleTalkMode()
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 42, height: 36)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Talk mode")
            .accessibilityIdentifier("coach-talk-toggle")
        }
        .padding(3)
        .background(Capsule().fill(Theme.cardBackground).shadow(color: .black.opacity(0.06), radius: 6, y: 2))
        .animation(Theme.Motion.passive, value: vm.voiceOutputEnabled)
    }
    #endif

    /// Circular close — replaces the sheet's plain "Done" text button.
    var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.cardBackground).shadow(color: .black.opacity(0.06), radius: 6, y: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("drift-coach-done")
    }

    // MARK: - Immersive talk-mode

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

    #if DRIFT_IOS_APP
    /// Drive the hero circle's animation/caption from the live voice + generation
    /// state. Precedence: speaking > processing > listening > idle.
    /// iOS-app-only: `ListeningCircle.CircleState` is the voice hero, gated off on
    /// Android for v1 (#1066).
    var circleState: ListeningCircle.CircleState {
        if case .unavailable = vm.speechService.recordingState { return .unavailable }
        if vm.voiceService.isSpeaking { return .speaking }
        if vm.isGenerating { return .processing }
        if vm.speechService.isRecording { return .listening }
        return .idle
    }
    #endif

    /// One voice flow shared by the hero circle and the small mic button — start
    /// recording (auto-sends on silence/stop), or stop speaking if the coach is
    /// mid-reply. Prevents duplicated callback logic / double-sends.
    func startOrStopVoice() {
        if vm.voiceService.isSpeaking { vm.voiceService.stop(); return }
        // #937: voice INPUT does not imply voice OUTPUT. The old force-enable
        // here overrode the user's explicit speaker-OFF toggle — dictating a
        // message made the phone talk back unexpectedly. Replies speak only
        // when the speaker toggle is ON.
        beginListening()
    }

    /// Start (or toggle-stop) voice capture. onDone auto-sends and flags the turn
    /// as voice so the coach speaks its reply and re-arms the mic afterward.
    func beginListening() {
        vm.voiceService.stop()
        vm.speechService.toggleRecording(
            onTranscript: { self.vm.inputText = $0 },
            onDone: { self.vm.submitVoiceTurn($0) },
            // Hands-free: submit ~1.8s after you stop talking — no tap needed.
            // Makes the coach feel like a conversation, not a walkie-talkie. #flowy-voice
            endpointSilence: 1.8
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
                            // `.stroke` not `.strokeBorder` — SkipUI's strokeBorder
                            // overload set is ambiguous here (ActiveWorkoutView:754). #1066
                            .overlay(Capsule().stroke(Theme.separator, lineWidth: 0.5))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    // MARK: - 10-second Undo Chip (after photo meal card confirm)

    var undoChip: some View {
        HStack {
            Spacer()
            Button { vm.undoProposedMeal() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: Theme.FontSize.tiny, weight: .medium))
                    Text("Undo")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Theme.surplus.opacity(0.75)))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    #if os(Android)
    /// Append a graceful "add it from the Food tab" message when a chat turn
    /// tries to open a food sheet that isn't ported to Android yet (see the sheet
    /// onChange handlers on `body`). #1066 / #1062
    func degradeUnportedSheet() {
        vm.messages.append(AIChatViewModel.ChatMessage(
            role: .assistant,
            text: "You can add that from the Food tab — Coach food logging is coming to Android soon."))
    }
    #endif
}
