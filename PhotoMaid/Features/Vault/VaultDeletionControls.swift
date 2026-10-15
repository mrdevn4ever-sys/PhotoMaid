import SwiftUI

/// Auf allen Tresor-Reitern direkt erreichbar, auch ohne langes Drücken oder ein Menü.
struct VaultSelectionToolbarItem: ToolbarContent {
    let scope: String
    let isEmpty: Bool
    @Binding var selecting: Bool
    @Binding var selection: Set<String>

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(L(selecting ? "done" : "vault_select")) {
                selecting.toggle()
                selection = []
            }
            .disabled(!selecting && isEmpty)
            .accessibilityIdentifier("vault.\(scope).select")
        }
    }
}

private struct VaultTrashConfirmation: ViewModifier {
    @Binding var pending: Set<String>?
    let onConfirm: (Set<String>) -> Void

    func body(content: Content) -> some View {
        content.alert(L("vault_delete_title", pending?.count ?? 0), isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), presenting: pending) { ids in
            Button(L("vault_delete"), role: .destructive) { onConfirm(ids); pending = nil }
            Button(L("cancel"), role: .cancel) { pending = nil }
        } message: { _ in
            Text(key: "vault_delete_text")
        }
    }
}

extension View {
    func vaultTrashConfirmation(_ pending: Binding<Set<String>?>,
                                onConfirm: @escaping (Set<String>) -> Void) -> some View {
        modifier(VaultTrashConfirmation(pending: pending, onConfirm: onConfirm))
    }
}
