import SwiftUI
import DriftCore

// MARK: - Message bubble + thinking indicator + typewriter
//
// `messageBubble(_:)` is the single render path for any chat message —
// dispatches to the right card view based on which optional payload is set on
// the message. Adding a new card type means: add the optional to ChatMessage,
// add a card method in AIChatView+Cards.swift, add a hook here.

extension AIChatView {

    /// Shape for chat-message bubble background + overlay border. Asymmetric
    /// corners give iMessage-style "tail" toward the speaker: user bubbles
    /// have a clipped bottom-right corner, assistant bubbles clip bottom-left.
    fileprivate func bubbleShape(for role: AIChatViewModel.ChatMessage.Role) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: role == .user ? 16 : 4,
            bottomTrailingRadius: role == .user ? 4 : 16,
            topTrailingRadius: 16
        )
    }

    // MARK: Thinking Indicator

    var thinkingIndicator: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                TypingDotsView()
                let baseLabel: String = switch vm.generatingState {
                case .thinking(let step): step
                case .generating: "Writing response..."
                case .idle: ""
                }
                if !baseLabel.isEmpty {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let elapsed = vm.stageStarted.map { context.date.timeIntervalSince($0) } ?? 0
                        let display = elapsed > 0.5
                            ? "\(baseLabel) (\(String(format: "%.1f", elapsed))s)"
                            : baseLabel
                        Text(display)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .id(baseLabel)
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

    // MARK: Typewriter Text

    struct TypewriterText: View {
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

    // MARK: Message Bubble

    func messageBubble(_ msg: AIChatViewModel.ChatMessage) -> some View {
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
                if msg.role == .user, let jpeg = msg.photoAttachment,
                   let uiImage = UIImage(data: jpeg) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

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
                        // User bubble: solid accent (Fitness coral) + white
                        // ink for contrast. Assistant bubble: white card +
                        // ink-primary text. Previously user-bubble was
                        // accent.opacity(0.25) with white text — barely
                        // visible on the resulting pink wash.
                        .foregroundStyle(msg.role == .user ? Color.white : Theme.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            msg.role == .user
                                ? AnyShapeStyle(Theme.accent)
                                : AnyShapeStyle(Theme.cardBackground),
                            in: bubbleShape(for: msg.role)
                        )
                        .overlay(
                            bubbleShape(for: msg.role)
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
                if let card = msg.medicationCard {
                    medicationConfirmationCard(card)
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
                if let card = msg.helpCard {
                    helpCardView(card)
                }
                if let options = msg.clarificationOptions, !options.isEmpty {
                    ClarificationCard(options: options, isDisabled: vm.isGenerating) { picked in
                        vm.inputText = "\(picked.id)"
                        vm.sendMessage()
                    } onOther: {
                        inputFocused = true
                    }
                }
                if let provider = msg.remoteProvider {
                    RemoteProviderBadge(provider: provider)
                }
                if let card = msg.proposedMealCard {
                    proposedMealCardView(card, messageId: msg.id)
                }
                if let retryText = msg.retryTurn {
                    Button {
                        vm.inputText = retryText
                        vm.sendMessage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .medium))
                            Text("Retry")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry: \(retryText)")
                }
            }
            .accessibilityLabel(msg.role == .user ? "You said: \(msg.text)" : "Assistant: \(msg.text)")

            if msg.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 10)
    }
}
