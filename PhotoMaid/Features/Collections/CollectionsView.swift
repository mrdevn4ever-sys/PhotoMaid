import PhotoMaidCore
import SwiftUI

struct CollectionsView: View {
    @Environment(AppModel.self) private var app
    @State private var source = CollectionSource.photos
    @State private var older = 30
    var body: some View {
        List {
            Section(L("col_builtin_header")) {
                ForEach(SmartCollections.builtIns) { collection in row(collection) }
            }
            Section(L("col_custom_header")) {
                ForEach(app.customCollections) { collection in row(collection) }
                Picker(L("col_condition"), selection: $source) {
                    Text(key: "cat_photos").tag(CollectionSource.photos)
                    Text(key: "cat_videos").tag(CollectionSource.videos)
                    Text(key: "cat_screenshots").tag(CollectionSource.screenshots)
                }
                Picker(L("col_older"), selection: $older) {
                    ForEach(SmartCollections.ageChoices, id: \.self) { Text(verbatim: LP("col_age_days", $0)).tag($0) }
                }
                Button(L("col_add")) { add() }.disabled(!app.capabilities.customCollections)
            }
            Text(key: "col_intro").font(AppTypography.caption)
        }.appPage().navigationTitle(L("hub_tab_collections"))
    }
    private func row(_ collection: SmartCollection) -> some View {
        Button { app.navigate(.grid(.collection(collection)), in: .cleanup) } label: {
            NavRow(symbol: CollectionText.symbol(collection), title: CollectionText.title(collection))
        }.buttonStyle(.plain)
    }
    private func add() {
        guard app.capabilities.customCollections else { app.navigate(.pro); return }
        var list = app.customCollections
        list.append(SmartCollection(source: source, filter: .olderThan(days: older)))
        app.setCustomCollections(list)
    }
}
