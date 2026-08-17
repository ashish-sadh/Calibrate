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
    // Not `fileprivate` — Skip Fuse can't bridge private/fileprivate members of
    // a shared view ([Fuse Can't Bridge Private Views/State]). #1066
    func bubbleShape(for role: AIChatViewModel.ChatMessage.Role) -> UnevenRoundedRectangle {
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
            Group {
                #if os(Android)
                // Material has no sparkle glyph — draw it (see Symbols.swift). #1066
                SparkleShape().fill(Theme.accent).frame(width: 11, height: 11)
                #else
                Image(systemName: "sparkles").font(.system(size: Theme.FontSize.micro))
                    .foregroundStyle(Theme.accent)
                #endif
            }
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
                    #if !os(Android)
                    // TimelineView (the live elapsed-seconds counter) is absent in
                    // SkipUI; available on iOS + the Darwin bridging pass. Android
                    // shows the static stage label below. #1066
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let elapsed = vm.stageStarted.map { context.date.timeIntervalSince($0) } ?? 0
                        let display = elapsed > 0.5
                            ? "\(baseLabel) (\(String(format: "%.1f", elapsed))s)"
                            : baseLabel
                        Text(display)
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .id(baseLabel)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                    #else
                    Text(baseLabel)
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                    #endif
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
        // Not `private` — Skip Fuse can't bridge private @State. #1066
        @State var revealed: Int = 0
        @State var done = false

        var body: some View {
            Text(done ? text : String(text.prefix(revealed)))
                .onAppear {
                    guard !text.isEmpty, !done else { return }
                    let total = text.count
                    let charsPerTick = max(1, total / 40)
                    Task {
                        while revealed < total {
                            // `Task.sleep(for:)` never resumes off-Darwin, so the
                            // reveal froze at 0 and every fresh assistant reply
                            // rendered as a permanently empty bubble on Android.
                            // `nanoseconds:` works on both ([SharedUI/ChatView]). #1066
                            try? await Task.sleep(nanoseconds: 18_000_000)
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
                Group {
                    #if os(Android)
                    // Material has no sparkle glyph — draw it (see Symbols.swift). #1066
                    SparkleShape().fill(Theme.accent).frame(width: 11, height: 11)
                    #else
                    Image(systemName: "sparkles").font(.system(size: Theme.FontSize.micro))
                        .foregroundStyle(Theme.accent)
                    #endif
                }
                    .frame(width: 20, height: 20)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .padding(.bottom, 2)
            }

            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 6) {
                #if DRIFT_IOS_APP
                // UIImage is UIKit-only; DRIFT_IOS_APP keeps it out of the
                // Darwin bridging pass. Android renders the same photo from the
                // cached file below (#1174).
                if msg.role == .user, let jpeg = msg.photoAttachment,
                   let uiImage = UIImage(data: jpeg) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }
                #elseif os(Android)
                if msg.role == .user, let path = msg.photoAttachmentPath {
                    AsyncImage(url: URL(fileURLWithPath: path)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Theme.cardBackgroundElevated)
                    }
                    .frame(width: 200, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }
                #endif

                if !msg.text.isEmpty {
                    #if os(Android)
                    // TypewriterText advances `revealed` from a Task, and @State
                    // writes off the composition never schedule a recomposition on
                    // Fuse — the delivery kick paints prefix(0) and no tick ever
                    // repaints, so every reply that lands in <1s (the rules-path
                    // answers: protein, calories, water, weight) was a permanently
                    // empty bubble. Plain Text paints at that same kick. The reveal
                    // animation is iOS-only polish. #1232
                    let isNewInstant = false
                    #else
                    let isNewInstant = msg.role == .assistant
                        && msg.id != vm.streamingMessageId
                        && Date().timeIntervalSince(msg.createdAt) < 1.0
                    #endif
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

                // Tool-result cards (foodConfirmationCard … helpCardView) live in
                // the iOS-only +Cards extension (DRIFT_IOS_APP, not synced to
                // Android); they land on Android in #1125. Every card-emitting turn
                // also carries a text summary, so a card-less bubble still informs.
                #if DRIFT_IOS_APP
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
                #endif
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
                #if DRIFT_IOS_APP
                if let card = msg.proposedMealCard {
                    proposedMealCardView(card, messageId: msg.id)
                }
                #elseif os(Android)
                // The one card the photo turn needs to be usable — the other 12
                // stay in #1125. Mirrors +Cards.swift:14-89. #1174
                if let card = msg.proposedMealCard {
                    proposedMealCardAndroid(card, messageId: msg.id)
                }
                #endif
                if let retryText = msg.retryTurn {
                    Button {
                        vm.inputText = retryText
                        vm.sendMessage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: sym("arrow.clockwise"))
                                .font(.system(size: Theme.FontSize.micro, weight: .medium))
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

/// The mandatory "via <provider>" cloud disclosure shown under any bubble a
/// cloud backend handled (privacy tenet — Drift Coach IS cloud). Extracted from
/// the iOS-only +Cards extension so it survives the card gate on Android (#1066).
///
/// Android renders it text-only: `cloud.fill` is unmapped (→ warning triangle)
/// and `.popover` doesn't bridge, so the drawn cloud glyph + the tap-for-details
/// popover land with the cards in #1125. The "via Nebius" text alone still
/// discloses the cloud touch-point, which is the privacy requirement.
struct RemoteProviderBadge: View {
    let provider: String

    #if os(Android)
    var body: some View {
        Text("via \(provider)")
            .font(.system(size: Theme.FontSize.micro))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.05), in: Capsule())
            .accessibilityLabel("Handled by \(provider).")
    }
    #else
    @State var showingPopover = false

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: Theme.FontSize.nano))
                Text("via \(provider)")
                    .font(.system(size: Theme.FontSize.micro))
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Processed by \(provider)", systemImage: "cloud.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Your API key, no Drift servers. Messages go directly to \(provider)'s API and are subject to their privacy policy.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Handled by \(provider). Tap for privacy details.")
    }
    #endif
}
