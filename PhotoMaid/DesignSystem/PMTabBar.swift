import SwiftUI

/// Schwebende Tableiste des Artefakts: Kapsel 68 pt (Abstand 16 seitlich, 22 unten), vier Einträge und in der Mitte
/// der runde Bernstein-Knopf „Aufräumen“ (60 pt, ragt über die Leiste). Ersetzt die System-Tableiste.
struct PMTabBar: View {
    @Binding var selection: AppTab
    /// Erneutes Tippen auf den aktiven Tab: zurück zur ersten Seite (wie die System-Tableiste).
    let reselect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.today, icon: .house, title: L("app_name"), index: 0)
            item(.library, icon: .grid, title: L("tab_library"), index: 1)
            center
            item(.studio, icon: .wand, title: L("tab_studio"), index: 3)
            item(.history, icon: .history, title: L("tab_history"), index: 4)
        }
        .padding(.horizontal, 6)
        .frame(height: 68)
        .background(AppColors.surface.opacity(0.94), in: .capsule)
        .overlay(Capsule().strokeBorder(AppColors.control, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func tap(_ tab: AppTab) {
        if selection == tab { reselect(tab) } else { selection = tab }
    }

    private func item(_ tab: AppTab, icon: PMIconName, title: String, index: Int) -> some View {
        let active = selection == tab
        return Button { tap(tab) } label: {
            VStack(spacing: 3) {
                PMIcon(icon, size: 22)
                Text(verbatim: title).font(AppTypography.tab).lineLimit(1).fixedSize()
            }
            .foregroundStyle(active ? AppColors.textPrimary : AppColors.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(PMPressStyle())
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { PMTabBarFrames.frames[index] = $0 }
    }

    private var center: some View {
        let active = selection == .cleanup
        return Button { tap(.cleanup) } label: {
            PMIcon(.layers, size: 26, lineWidth: 2.2)
                .foregroundStyle(AppColors.onAccent)
                .frame(width: 60, height: 60)
                .background(AppColors.accentFill, in: .circle)
                .overlay(Circle().strokeBorder(active ? AppColors.textPrimary : AppColors.background, lineWidth: 4))
                .shadow(color: AppColors.accent.opacity(0.3), radius: 12, y: 8)
                .contentShape(.circle)
        }
        .buttonStyle(PMPressStyle())
        .frame(maxWidth: .infinity)
        .offset(y: -15)
        .accessibilityLabel(Text(key: "tab_cleanup"))
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .accessibilityIdentifier("tab.cleanup")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { PMTabBarFrames.frames[2] = $0 }
    }
}

/// Lage der eigenen Tab-Einträge (für den Rundgang, der auf Tabs zeigt).
@MainActor
enum PMTabBarFrames {
    static var frames: [Int: CGRect] = [:]
}
