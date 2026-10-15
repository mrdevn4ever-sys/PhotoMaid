import SwiftUI
import UIKit

/// A left swipe only requests confirmation. Vertical scrolling and taps stay with
/// the grid; selection disables the recognizer rather than intercepting row taps.
struct VaultMediaTrashSwipe: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UISwipeGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer()
        recognizer.direction = .left
        recognizer.numberOfTouchesRequired = 1
        recognizer.isEnabled = enabled
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        recognizer.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        if enabled, recognizer.state == .recognized { action() }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

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
