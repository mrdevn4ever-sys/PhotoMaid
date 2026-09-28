import PhotoMaidCore
import SwiftUI

@main
struct PhotoMaidApp: App {
    @State private var boot = AppBoot()

    init() {
        RulesBackgroundTask.register {
            // Best effort; die eigentliche Prüfung läuft bei Start/Resume.
        }
    }

    var body: some Scene {
        WindowGroup {
            switch boot.state {
            case .ready(let app):
                RootView()
                    .environment(app)
                    .preferredColorScheme(app.settings.appearance.colorScheme)
            case .failed(let message):
                ErrorState(message: Text(message))
                    .background(AppBackground())
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(AppBackground())
            }
        }
    }
}

@MainActor
@Observable
final class AppBoot {
    enum State { case loading, ready(AppModel), failed(String) }
    private(set) var state: State = .loading

    init() {
        do {
            #if QA_FIXTURES
            let qa = ProcessInfo.processInfo.arguments.contains("-qa-fixtures")
            let store = try CoreDataStore(inMemory: qa)
            state = .ready(try AppModel(store: store, qaFixtures: qa))
            #else
            state = .ready(try AppModel(store: CoreDataStore()))
            #endif
        } catch {
            state = .failed(String(localized: "Der lokale Speicher konnte nicht geöffnet werden."))
        }
    }
}
