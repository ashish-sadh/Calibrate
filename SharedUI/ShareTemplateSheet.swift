import SwiftUI
import DriftCore

/// Pick a friend or coach to send/assign a workout template to. Pushed from
/// the template preview's "Send to a friend" action. Single-source
/// (iOS + Android). Pushed rather than sheet-presented so it never stacks a
/// second presentation modifier on the preview sheet (Skip Fuse breaks on
/// stacked presentations). The recipient list itself is the shared
/// FriendSharePicker (coach-first ordering, search, share-with-all).
struct ShareTemplateSheet: View {
    let template: WorkoutTemplate
    var onSent: () -> Void = {}

    @State var note = ""

    private var svc: SharingService { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.headline)
                    Text("\(template.exercises.count) exercises").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTE (OPTIONAL)").sectionHeading()
                    TextField("e.g. Try this for leg day 💪", text: $note)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if !svc.isSignedIn {
                    signInPrompt
                } else {
                    FriendSharePicker { c in
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        try await svc.shareTemplate(template, to: c.profile.id,
                                                    note: trimmed.isEmpty ? nil : trimmed)
                    } onSent: { _ in
                        FeatureUsage.record(TelemetryEvent.templateShared)
                        onSent()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Send to a friend")
        #if !os(Android)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var signInPrompt: some View {
        VStack(spacing: 8) {
            Text("Sign in to share").font(.subheadline.weight(.semibold))
            Text("Open More → Friends to set up sharing, then send this workout to a friend.")
                .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).card()
    }
}
