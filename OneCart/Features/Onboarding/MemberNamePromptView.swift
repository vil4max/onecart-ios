import SwiftUI

struct MemberNamePromptView: View {
    @Bindable var viewModel: MemberNamePromptViewModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("name_prompt.title")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("name_prompt.message")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                TextField("name_prompt.placeholder", text: $viewModel.name)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit(save)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("name_prompt.field")

                VStack(spacing: 8) {
                    Button(action: save) {
                        Text("name_prompt.save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.canSave)
                    .accessibilityIdentifier("name_prompt.save")

                    Button("name_prompt.not_now") {
                        viewModel.notNow()
                    }
                    .controlSize(.large)
                    .disabled(viewModel.isSaving)
                    .accessibilityIdentifier("name_prompt.not_now")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(viewModel.isSaving)
        .onAppear { fieldFocused = true }
    }

    private func save() {
        Task { await viewModel.save() }
    }
}
