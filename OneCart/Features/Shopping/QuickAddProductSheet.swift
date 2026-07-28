import SwiftUI

struct QuickAddProductSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    let listID: UUID
    var product: ProductEntity?

    @State private var name: String
    @State private var isSaving = false

    init(listID: UUID, product: ProductEntity? = nil) {
        self.listID = listID
        self.product = product
        _name = State(initialValue: product?.displayName ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEditing: Bool {
        product != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("cart.add_placeholder", text: $name)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        OneCartPalette.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .disabled(isSaving)

                Button {
                    save()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text(isEditing ? "common.save" : "cart.add_to_cart")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OneCartPrimaryButtonStyle())
                .disabled(trimmedName.isEmpty || isSaving)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "cart.edit_title" : "cart.add_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                nameFocused = true
            }
        }
        .oneCartMediumSheet()
    }

    private func save() {
        guard model.canEdit, !trimmedName.isEmpty, !isSaving else { return }
        guard let list = model.lists.first(where: { $0.id == listID }) else {
            dismiss()
            return
        }

        isSaving = true
        let draft = ProductDraft(
            name: trimmedName,
            quantity: product?.quantityValue ?? 1,
            unit: product?.unitValue ?? .piece,
            category: product?.categoryValue ?? ProductCategory.inferred(from: trimmedName),
            estimatedPrice: product?.estimatedPriceValue ?? 0,
            note: product?.noteValue ?? "",
            imageURL: product?.imageURL,
            sourceURL: product?.sourceURL,
            originalPrice: product?.originalPrice?.doubleValue,
            loyaltyPrice: product?.loyaltyPrice?.doubleValue,
            catalogFetchedAt: product?.catalogFetchedAt,
            promotionEndsAt: product?.promotionEndsAt
        )

        Task {
            defer { isSaving = false }
            if let product {
                let productID = product.id
                await model.updateProduct(product, draft: draft)
                if let productID,
                   model.products(inListID: listID).contains(where: { $0.id == productID })
                {
                    dismiss()
                }
            } else {
                let before = Set(model.products(inListID: listID).compactMap(\.id))
                await model.addProduct(to: list, draft: draft)
                let after = Set(model.products(inListID: listID).compactMap(\.id))
                guard !after.subtracting(before).isEmpty else { return }
                dismiss()
            }
        }
    }
}

// Kept for any remaining call sites; forwards to the quick name editor.
