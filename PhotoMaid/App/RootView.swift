import PhotoMaidCore
import SwiftUI

/// Wurzel: fünf Tabs (Heute · Fotos · Aufräumen · Studio · Verlauf) mit Liquid-Glass-Tableiste, darüber der Feed
/// als Vollbild-Ebene (kurzes Einblenden wie Android, ohne Animation bei „Bewegung reduzieren“).
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shielded = false
    @State private var quick = QuickActions.shared
    @State private var vault = VaultStore.shared

    var body: some View {
        @Bindable var app = app
        ZStack {
            if app.settings.onboardingVersion < OnboardingFlow.version {
                OnboardingFlow()
                    .transition(.opacity)
            } else {
                tabs
                if let request = app.feed {
                    FeedView(request: request, app: app)
                        .id(request.id)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            if shielded {
                PrivacyShield().zIndex(3)
            }
        }
        .animation(AppMotion.open(reduceMotion), value: app.feed?.id)
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(toast: toast) { app.toast = nil }
                    .padding(.bottom, app.feed == nil ? 72 : AppSpacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(AppMotion.standard(reduceMotion), value: app.toast?.id)
        .fullScreenCover(item: $app.fullScreen) { request in
            FullScreenHost(request: request)
                .environment(app)
        }
        .preferredColorScheme(app.settings.appearance.colorScheme)
        .task { await app.onForeground() }
        .task {
            // Uhr für Tageswechsel (Limit, Später fällig) und Restzeiten.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                app.tick()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                shielded = false
                PrivacyCover.hide()
                Task { await app.onForeground() }
            case .background:
                shielded = true
                PrivacyCover.show()
                app.player.stop()
                vault.lock() // Tresor beim Verlassen der App immer sperren und schließen
            default:
                // Tresor offen: schon beim Wechsel in den App-Umschalter alles abdecken – auch Betrachter, Blätter und
                // Teilen-Fenster, die über der Tresor-Ebene liegen.
                if vault.isPresented { PrivacyCover.show() }
                app.player.pause()
            }
        }
        .onChange(of: app.library.changeToken) { _, _ in app.reloadLibraryIfNeeded() }
        // Tresor geschlossen: Ablagen und Löschungen darin auch im Bereich „Dateien“ abgleichen.
        .onChange(of: vault.isPresented) { _, presented in
            if !presented { Task { await app.refreshVaultConcealment() } }
        }
        .onChange(of: quick.pending) { _, route in
            guard let route else { return }
            quick.pending = nil
            handle(route)
        }
        .onChange(of: app.pendingRoute) { _, route in
            guard let route else { return }
            app.pendingRoute = nil
            handle(route)
        }
        .onOpenURL { url in handle(.openFiles([url])) }
        .onAppear {
            if let route = quick.pending { quick.pending = nil; handle(route) }
        }
    }

    private var tabs: some View {
        @Bindable var app = app
        @Bindable var vault = vault
        return TabView(selection: $app.selectedTab) {
            Tab(L("tab_today"), systemImage: "house", value: AppTab.today) {
                stack(.today) { TodayView() }
            }
            Tab(L("tab_library"), systemImage: "photo.on.rectangle.angled", value: AppTab.library) {
                stack(.library) { LibraryView() }
            }
            Tab(L("tab_cleanup"), systemImage: "square.stack.3d.up", value: AppTab.cleanup) {
                stack(.cleanup) { CleanUpHubView() }
            }
            Tab(L("tab_studio"), systemImage: "paintpalette", value: AppTab.studio) {
                stack(.studio) { StudioView() }
            }
            Tab(L("tab_history"), systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                stack(.history) { HistoryView() }
            }
        }
        .tint(AppColors.accent)
        .fullScreenCover(isPresented: $vault.isPresented, onDismiss: { vault.lock() }) {
            VaultRootView()
                .environment(app)
        }
    }

    private func stack<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: Binding(get: { app.paths[tab] ?? [] }, set: { app.paths[tab] = $0 })) {
            content()
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
    }

    /// Einstiege öffnen nur Ansichten – nie eine Entscheidung, nie ein Löschen, nie ein Start ohne Tipp.
    private func handle(_ route: AppRoute) {
        guard app.settings.onboardingVersion >= OnboardingFlow.version else { return }
        switch route {
        case .startReview:
            app.selectedTab = .today
            if app.library.access.canRead { app.open(FeedRequest(.allMedia)) }
        case .trash:
            app.feed = nil
            app.popToRoot(.cleanup)
            app.navigate(.trash, in: .cleanup)
        case .later:
            app.feed = nil
            app.popToRoot(.cleanup)
            app.navigate(.later, in: .cleanup)
        case .studio:
            app.feed = nil
            app.selectedTab = .studio
        case .openFiles(let urls):
            app.feed = nil
            app.popToRoot(.studio)
            app.navigate(.received(urls), in: .studio)
        }
    }
}

/// Sichtschutz im App-Umschalter: keine Fotos in der Vorschau des Systems.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            AppBackground()
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

/// Sichtschutz in einem eigenen Fenster über allem, was die App zeigt (Vollbild-Ebenen, Blätter, Teilen-Fenster).
/// Systemabfragen (Face ID, Löschen in der Fotos-App) liegen außerhalb der App und bleiben bedienbar.
@MainActor
enum PrivacyCover {
    private static var window: UIWindow?

    static func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 1
        cover.overrideUserInterfaceStyle = scene.windows.first { $0.isKeyWindow }?.overrideUserInterfaceStyle ?? .unspecified
        let host = UIHostingController(rootView: PrivacyShield())
        cover.rootViewController = host
        cover.isHidden = false
        window = cover
    }

    static func hide() {
        window?.isHidden = true
        window = nil
    }
}

/// Vollbild-Seiten (Betrachter, Editor, Diashow, Scanner).
struct FullScreenHost: View {
    let request: FullScreenRequest

    var body: some View {
        switch request {
        case .viewer(let ids, let index): ViewerView(ids: ids, startIndex: index)
        case .editor(let id): PhotoEditorView(assetID: id)
        case .videoEditor(let id): VideoEditorView(assetID: id)
        case .slideshow(let ids): SlideshowView(ids: ids)
        case .scanner: DocumentScannerHost()
        }
    }
}

/// Start gescheitert (Datenbank nicht ladbar): keine Ersatz-Wahrheit, damit keine Entscheidung verloren geht.
struct StartupErrorView: View {
    @State private var report: URL?

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: AppSpacing.l) {
                EmptyState(symbol: "externaldrive.badge.exclamationmark", title: L("startup_failed_title"),
                           message: L("startup_failed_text"))
                if let report {
                    ShareLink(item: report) { Text(key: "diag_share") }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(AppSpacing.pageMargin)
        }
        .task { report = await Diagnostics.makeReport(appVersion: AppConfig.appVersion, build: AppConfig.buildNumber) }
    }
}
