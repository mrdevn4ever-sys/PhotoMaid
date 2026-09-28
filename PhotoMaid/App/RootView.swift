import PhotoMaidCore
import SwiftUI

enum AppTab: Hashable { case today, cleanup, organize, history }

/// Vier Haupttabs entsprechend den Mockups. Jeder Tab besitzt einen eigenen NavigationStack
/// und bewahrt seinen Zustand. Einstellungen über das Zahnrad, Pro kontextuell.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today
    @State private var feed: FeedRequest?
    @State private var showSettings = false
    @State private var privacyShield = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Heute", systemImage: "house.fill", value: AppTab.today) {
                NavigationStack { TodayView(openFeed: { feed = $0 }, openSettings: { showSettings = true }) }
            }
            Tab("Aufräumen", systemImage: "square.stack.3d.up", value: AppTab.cleanup) {
                NavigationStack { CleanUpHubView(openFeed: { feed = $0 }, openSettings: { showSettings = true }) }
            }
            Tab("Ordnen", systemImage: "folder", value: AppTab.organize) {
                NavigationStack { OrganizeView(openFeed: { feed = $0 }) }
            }
            Tab("Verlauf", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack { HistoryView() }
            }
        }
        .tint(AppColors.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Fokussierter Feed: normale Tabbar ausgeblendet (Vollbild).
        .fullScreenCover(item: $feed) { request in
            ReviewFeedView(request: request)
                .environment(app)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }.environment(app)
        }
        .overlay {
            // App-Umschalter-Vorschau neutralisieren.
            if privacyShield {
                ZStack { AppBackground(); Image(systemName: "photo.stack").font(.largeTitle).foregroundStyle(AppColors.accent) }
                    .accessibilityHidden(true)
            }
        }
        .task { await app.onForeground() }
        .task {
            // Rewarded-Vorschau: Restzeit/Ablauf sichtbar halten.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                app.entitlements.tick()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            privacyShield = phase != .active
            switch phase {
            case .active: Task { await app.onForeground() }
            case .background, .inactive: app.player.stop()
            @unknown default: break
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { app.lastError != nil }, set: { if !$0 { app.clearError() } })) {
            Button("OK", role: .cancel) { app.clearError() }
        } message: {
            Text(app.lastError ?? "")
        }
    }
}

/// Anfrage an den Feed: Quelle + Warteschlange.
struct FeedRequest: Identifiable, Hashable {
    enum Source: Hashable {
        case category(MediaCategory)
        case due
        case task(ReviewTask)
        case items([ItemReference], title: String)
    }
    let id = UUID()
    let source: Source

    var title: LocalizedStringKey {
        switch source {
        case .category(.photos): "Fotos prüfen"
        case .category(.videos): "Videos prüfen"
        case .category(.screenshots): "Screenshots prüfen"
        case .due: "Wieder fällig"
        case .task: "Regel-Aufgabe"
        case .items(_, let title): LocalizedStringKey(title)
        }
    }
}
