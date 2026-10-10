import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

struct ArchiveView: View {
    @Environment(AppModel.self) private var app
    let initialIDs: [String]
    @State private var ids: [String] = []
    @State private var target: URL?
    @State private var pickingFolder = false
    @State private var pickingMedia = false
    @State private var options = ArchiveOptions()
    @State private var journal: ArchiveJournal?
    @State private var running = false

    var body: some View {
        Form {
            Section(L("archive_target")) {
                Button { pickingFolder = true } label: { Label(L("archive_choose"), systemImage: "folder") }
                Text(verbatim: target?.lastPathComponent ?? L("archive_target_none"))
                Button { pickingMedia = true } label: { Label(L("archive_pick"), systemImage: "photo.on.rectangle") }
                Text(verbatim: LP("archive_files", ids.count))
            }
            Section(L("archive_options")) {
                Toggle(L("archive_by_month"), isOn: $options.byMonth)
                Toggle(L("archive_write_list"), isOn: $options.writeList)
            }
            Button { Task { await run() } } label: { Label(L("archive_start"), systemImage: "externaldrive.badge.plus") }
                .buttonStyle(.glassProminent).disabled(target == nil || ids.isEmpty || running)
            if let journal {
                Section(L("archive_result_title")) {
                    Text(verbatim: LP("archive_part_verified", journal.summary.verified))
                    Text(verbatim: LP("archive_part_failed", journal.summary.failed))
                    Text(verbatim: SizeText.bytes(journal.summary.verifiedBytes))
                }
            }
        }
        .appPage().navigationTitle(L("archive_title"))
        .overlay { if running { LoadingState(message: L("archive_running")).background(.ultraThinMaterial) } }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result { target = urls.first }
        }
        .sheet(isPresented: $pickingMedia) {
            StudioMediaPicker(allowsVideos: true, limit: 500, initial: Set(ids)) { ids = $0 }
        }
        .onAppear { ids = initialIDs }
    }

    private func run() async {
        guard let target else { return }
        running = true
        defer { running = false }
        let scoped = target.startAccessingSecurityScopedResource()
        defer { if scoped { target.stopAccessingSecurityScopedResource() } }
        journal = await ArchiveService.copy(app: app, ids: ids, target: target, options: options)
        try? app.kv?.set(StoreKeys.archiveJournal, journal)
    }
}
