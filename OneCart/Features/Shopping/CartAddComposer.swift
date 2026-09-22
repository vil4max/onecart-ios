import SwiftUI

/// The add control at the bottom of the cart: a glass button that morphs into the name
/// composer with its suggestion chips. Every add goes through `CartViewModel.addItem(named:)`.
struct CartAddComposer: View {
    let viewModel: CartViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var glassNamespace
    @State private var isComposing = false
    @State private var draftName = ""
    @State private var suggestions: [String] = []
    @State private var isAdding = false
    @FocusState private var isDraftFocused: Bool

    private var trimmedDraft: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var accent: Color {
        OneCartPalette.primary(for: colorScheme, accent: viewModel.accentColor)
    }

    /// Reduce Motion swaps the glass morph for a cross-fade by dropping the shared identity.
    private var morphID: String? {
        reduceMotion ? nil : "cart.add"
    }

    private var toggleAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4)
    }

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(alignment: .trailing, spacing: 10) {
                if isComposing {
                    if !suggestions.isEmpty {
                        suggestionChips
                            .transition(.opacity)
                    }
                    composerCard
                        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
                        .glassEffectID(morphID, in: glassNamespace)
                        .transition(.opacity)
                } else {
                    addButton
                        .glassEffectID(morphID, in: glassNamespace)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear {
            #if DEBUG
                // Demo launches (`-oneCartDemoComposer`) open the composer for screenshots.
                if ProcessInfo.processInfo.arguments.contains("-oneCartDemoComposer") {
                    Task { await beginComposing() }
                }
            #endif
        }
        .onChange(of: draftName) {
            updateSuggestions()
        }
        .onChange(of: viewModel.contentRevision) {
            if isComposing {
                updateSuggestions()
            }
        }
        .onChange(of: viewModel.canEdit) {
            if !viewModel.canEdit, isComposing {
                close()
            }
        }
    }

    private var addButton: some View {
        Button {
            Task { await beginComposing() }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(accent)
        .accessibilityLabel(Text("cart.add_a11y"))
        .accessibilityIdentifier("cart.add")
        .keyboardShortcut("n", modifiers: .command)
    }

    private var composerCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        categorySymbol
                        draftField
                    }
                    HStack(spacing: 16) {
                        Spacer(minLength: 0)
                        submitButton
                        closeButton
                    }
                }
            } else {
                HStack(spacing: 10) {
                    categorySymbol
                    draftField
                    submitButton
                    closeButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .disabled(isAdding)
    }

    private var categorySymbol: some View {
        Image(systemName: ProductCategory.inferred(from: draftName).symbolName)
            .font(.body.weight(.semibold))
            .foregroundStyle(OneCartPalette.primaryAccent)
            .frame(minWidth: 28)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var draftField: some View {
        TextField("cart.add_placeholder", text: $draftName)
            .focused($isDraftFocused)
            .submitLabel(.done)
            .onSubmit {
                Task { await commitDraft(keepComposing: false) }
            }
            .accessibilityLabel(Text("cart.add_a11y"))
            .accessibilityIdentifier("cart.add_field")
    }

    private var submitButton: some View {
        Button {
            Task { await commitDraft(keepComposing: true) }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .disabled(trimmedDraft.isEmpty)
        .accessibilityLabel(Text("cart.add_a11y"))
        .accessibilityIdentifier("cart.add_submit")
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("common.cancel"))
        .accessibilityIdentifier("cart.add_close")
        .keyboardShortcut(.cancelAction)
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { item in
                    Button {
                        Task { await addSuggestion(item) }
                    } label: {
                        Label(item, systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .tint(accent)
                    .accessibilityLabel(Text("cart.suggestion_chip_a11y \(item)"))
                    .accessibilityIdentifier("cart.suggestion")
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .disabled(isAdding)
    }

    // MARK: - Actions

    private func beginComposing() async {
        guard viewModel.canEdit, !isComposing else { return }
        CartHaptics.light()
        withAnimation(toggleAnimation) {
            draftName = ""
            isComposing = true
        }
        updateSuggestions()
        isDraftFocused = true
    }

    private func close() {
        isDraftFocused = false
        withAnimation(toggleAnimation) {
            isComposing = false
            draftName = ""
            suggestions = []
        }
    }

    private func updateSuggestions() {
        suggestions = viewModel.suggestions(matching: draftName)
    }

    private func commitDraft(keepComposing: Bool) async {
        guard !isAdding else { return }
        guard !trimmedDraft.isEmpty else {
            close()
            return
        }

        isAdding = true
        let outcome = await viewModel.addItem(named: trimmedDraft)
        isAdding = false

        switch outcome {
        case .rejected:
            isDraftFocused = true
        case .duplicate:
            // The ViewModel flashes the existing line instead of adding a second one.
            close()
        case .added:
            CartHaptics.light()
            draftName = ""
            if keepComposing {
                isDraftFocused = true
            } else {
                close()
            }
        }
    }

    private func addSuggestion(_ name: String) async {
        guard !isAdding else { return }
        isAdding = true
        let outcome = await viewModel.addItem(named: name)
        isAdding = false
        if case .added = outcome {
            CartHaptics.light()
        }
        updateSuggestions()
        isDraftFocused = true
    }
}
