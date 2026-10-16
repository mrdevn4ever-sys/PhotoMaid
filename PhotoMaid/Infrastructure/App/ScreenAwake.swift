import SwiftUI
import UIKit

/// Independent activities release only their own request, so a dismissed screen cannot stop an export or scan.
@MainActor final class ScreenAwake {
    static let shared = ScreenAwake()
    private var requests: Set<UUID> = []
    func set(_ id: UUID, active: Bool) {
        if active { requests.insert(id) } else { requests.remove(id) }
        UIApplication.shared.isIdleTimerDisabled = !requests.isEmpty
    }
}

private struct ScreenAwakeModifier: ViewModifier {
    let active: Bool
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content.onAppear { ScreenAwake.shared.set(id, active: active) }
            .onChange(of: active) { _, value in ScreenAwake.shared.set(id, active: value) }
            .onDisappear { ScreenAwake.shared.set(id, active: false) }
    }
}

extension View {
    func keepsScreenAwake(_ active: Bool) -> some View { modifier(ScreenAwakeModifier(active: active)) }
}
