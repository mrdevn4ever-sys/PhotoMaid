import Photos
import PhotoMaidCore
import SwiftUI
import UIKit

struct PrivacyView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        List {
            InfoBanner(symbol: "lock.shield", text: L("privacy_text"))
            Section {
                Text(key: "privacy_media_text")
                if app.library.access == .limited { Button(L("privacy_manage")) { app.library.presentLimitedLibraryPicker() } }
                if app.library.access == .denied || app.library.access == .restricted {
                    Button(L("privacy_open_settings")) { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
            } header: { Text(key: "privacy_media") }
            Section(L("privacy_purchases")) { Text(key: "pro_privacy_no_ads") }
        }.appPage().navigationTitle(L("privacy_title"))
    }
}

struct HelpView: View {
    @Environment(AppModel.self) private var app
    @State private var report: URL?
    var body: some View {
        List {
            Section(L("help_decide")) { Text(key: "help_decide_text") }
            Section(L("help_delete")) { Text(key: "help_delete_text") }
            Section(L("help_cloud")) { Text(key: "help_cloud_text") }
            Button(L("help_tours_again")) { app.updateSettings { $0.todayTourSeen = false; $0.feedTourSeen = false; $0.gridTourSeen = false } }
            if let report { ShareLink(item: report) { Label(L("diag_share"), systemImage: "square.and.arrow.up") } }
        }.appPage().navigationTitle(L("help")).task { report = await Diagnostics.makeReport(appVersion: AppConfig.appVersion, build: AppConfig.buildNumber) }
    }
}

struct ExcludedAlbumsView: View {
    @Environment(AppModel.self) private var app
    @State private var albums: [PhotoAlbum] = []
    var body: some View {
        List(albums.filter { !$0.isFolder }) { album in
            Toggle(isOn: Binding(get: { app.settings.excludedAlbums.contains(album.id) }, set: { enabled in
                app.updateSettings { settings in
                    if enabled { if !settings.excludedAlbums.contains(album.id) { settings.excludedAlbums.append(album.id) } }
                    else { settings.excludedAlbums.removeAll { $0 == album.id } }
                }
            })) { Text(verbatim: album.title) }
        }.appPage().navigationTitle(L("set_excluded_folders")).task { albums = await PhotoLibraryService.loadAlbums() }
    }
}
