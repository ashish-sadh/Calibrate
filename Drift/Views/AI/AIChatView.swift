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

    var body: some View {
        VStack(spacing: 0) {
            if vm.canToggleBackend {
                backendSelectorHeader
            }

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
