import PhotoMaidCore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section(L("set_controls")) {
                Toggle(L("set_haptics"), isOn: setting(\.haptics))
                Toggle(L("set_hints"), isOn: setting(\.showGestureHintOnOpen))
                NavigationLink(value: Route.feedControls) {
                    LabeledContent(L("fc_title"), value: FeedControlsText.summary(app.settings.feedControls))
                }
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
                // App-Sprache stellt iOS ein (Einstellungen › PhotoMaid › Sprache); kein eigener Sprachumschalter.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent(L("set_language"), value: languageName)
                }
                .foregroundStyle(AppColors.textPrimary)
            } header: {
                Text(key: "set_language")
            } footer: {
                Text(key: "set_language_hint")
            }
            if !VaultStore.shared.hidesEntry {
                Section {
                    Button { VaultStore.shared.present() } label: {
                        Label(L("vault_title"), systemImage: "lock.rectangle.stack")
                    }
                    .foregroundStyle(AppColors.textPrimary)
                } footer: {
                    Text(key: "vault_settings_row_hint")
                }
            }
            Section {
                NavigationLink(value: Route.excludedAlbums) { Text(key: "set_excluded_folders") }
                NavigationLink(value: Route.backup) { Text(key: "backup_title") }
                NavigationLink(value: Route.privacy) { Text(key: "privacy_title") }
                // Von Google für EWR/UK/Schweiz verlangt: Einwilligung zur Werbung jederzeit ändern (nur Gratis).
                if AdsService.shared.privacyOptionsRequired && !app.capabilities.isLifetimePro {
                    Button(L("set_ad_privacy")) { Task { await AdsService.shared.presentPrivacyOptions() } }
                }
                NavigationLink(value: Route.help) { Text(key: "help") }
                NavigationLink(value: Route.pro) { Text(key: app.capabilities.isLifetimePro ? "set_pro_active" : "set_pro_once") }
            }
        }
        .appPage().navigationTitle(L("settings"))
    }

    /// Name der aktuell verwendeten App-Sprache in dieser Sprache („Deutsch“, „English“ …).
    private var languageName: String {
        let id = Strings.language
        return Locale(identifier: id).localizedString(forIdentifier: id)?.capitalized(with: Locale(identifier: id)) ?? id
    }

    private func setting<T>(_ path: WritableKeyPath<AppSettingsData, T>) -> Binding<T> {
        Binding(get: { app.settings[keyPath: path] }, set: { value in app.updateSettings { $0[keyPath: path] = value } })
    }
}
