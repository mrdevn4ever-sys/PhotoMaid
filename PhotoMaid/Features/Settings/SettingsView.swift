import PhotoMaidCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section(L("set_controls")) {
                Toggle(L("set_haptics"), isOn: setting(\.haptics))
                Toggle(L("set_hints"), isOn: setting(\.showGestureHintOnOpen))
                Toggle(L("set_buttons"), isOn: setting(\.decisionButtons))
                Toggle(L("set_protect_favorites"), isOn: setting(\.protectFavorites))
                Picker(L("set_later_default"), selection: setting(\.laterDefaultDays)) {
                    ForEach(LaterInterval.allowedQuickDays, id: \.self) { Text(verbatim: LP("set_in_days", $0)).tag($0) }
                }
            }
            Section(L("set_appearance")) {
                Picker(L("set_appearance"), selection: setting(\.appearance)) {
                    Text(key: "appearance_system").tag(AppearanceChoice.system)
                    Text(key: "appearance_light").tag(AppearanceChoice.light)
                    Text(key: "appearance_dark").tag(AppearanceChoice.dark)
                }
            }
            Section {
                NavigationLink(value: Route.excludedAlbums) { Text(key: "set_excluded_folders") }
                NavigationLink(value: Route.backup) { Text(key: "backup_title") }
                NavigationLink(value: Route.privacy) { Text(key: "privacy_title") }
                NavigationLink(value: Route.help) { Text(key: "help") }
                NavigationLink(value: Route.pro) { Text(key: app.capabilities.hasProToolsAccess ? "set_pro_active" : "set_pro_once") }
            }
        }
        .appPage().navigationTitle(L("settings"))
    }

    private func setting<T>(_ path: WritableKeyPath<AppSettingsData, T>) -> Binding<T> {
        Binding(get: { app.settings[keyPath: path] }, set: { value in app.updateSettings { $0[keyPath: path] = value } })
    }
}
