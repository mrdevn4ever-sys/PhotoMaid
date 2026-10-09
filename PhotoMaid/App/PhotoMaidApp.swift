import Observation
import PhotoMaidCore
import SwiftUI
import UIKit

@main
struct PhotoMaidApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var boot = AppModel.bootstrap()

    init() {
        MetricsSubscriber.shared.start()
        Diagnostics.log(.app, "launch \(AppConfig.appVersion)(\(AppConfig.buildNumber))")
    }

    var body: some Scene {
        WindowGroup {
            switch boot {
            case .success(let app):
                RootView()
                    .environment(app)
                    .onAppear { QuickActions.install() }
                    #if QA_FIXTURES
                    .task { if app.isQAFixtureMode { QAFixtures.install(into: app) } }
                    #endif
            case .failure:
                StartupErrorView()
            }
        }
    }
}

/// Schnellaktionen am App-Symbol. Öffnen nur Ansichten (wie Android-Shortcuts): nie Entscheidung, nie Löschen.
@MainActor
@Observable
final class QuickActions {
    static let shared = QuickActions()
    var pending: AppRoute?

    static func install() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(type: "review", localizedTitle: L("shortcut_review"), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "rectangle.stack"), userInfo: nil),
            UIApplicationShortcutItem(type: "trash", localizedTitle: L("shortcut_trash"), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "trash"), userInfo: nil),
            UIApplicationShortcutItem(type: "later", localizedTitle: L("shortcut_later"), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "clock"), userInfo: nil),
            UIApplicationShortcutItem(type: "studio", localizedTitle: L("shortcut_studio"), localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: "paintpalette"), userInfo: nil),
        ]
    }

    static func route(_ item: UIApplicationShortcutItem) -> AppRoute? {
        switch item.type {
        case "review": .startReview
        case "trash": .trash
        case "later": .later
        case "studio": .studio
        default: nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { QuickActions.shared.pending = QuickActions.route(item) }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let route = QuickActions.route(shortcutItem)
        QuickActions.shared.pending = route
        completionHandler(route != nil)
    }
}
