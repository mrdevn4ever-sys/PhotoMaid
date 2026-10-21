import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(AppModel.self) private var app
    @State private var file: ExportedFile?
    @State private var exporting = false
    @State private var importing = false
    @State private var importSummary: String?
    @State private var restorePlan: RestorePlan?

    var body: some View {
        Form {
            Section(L("backup_save_header")) {
                Text(key: "backup_save_text")
                Button { Task { await makeBackup() } } label: { Label(L("backup_save_button"), systemImage: "square.and.arrow.up") }
            }
            Section(L("backup_restore_header")) {
                Text(key: "backup_restore_text")
                Button { importing = true } label: { Label(L("backup_open_button"), systemImage: "folder") }
                if let importSummary { Text(verbatim: importSummary) }
                if let restorePlan {
                    Button { Task { await apply(restorePlan) } } label: { Text(key: "backup_apply") }
                        .buttonStyle(.pmProminent)
                }
            }
            Text(key: "backup_privacy").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
        }
        .appPage().navigationTitle(L("backup_title"))
        .fileExporter(isPresented: $exporting, document: file, contentType: .json,
                      defaultFilename: L("backup_file_name")) { result in
            if case .failure = result { app.showError(L("backup_save_failed")) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            inspect(url)
        }
    }

    private func makeBackup() async {
        do {
            let backup = await app.makeBackup()
            let data = try JSONEncoder().encode(backup)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("photomaid-backup.json")
            try data.write(to: url, options: .atomic)
            file = ExportedFile(url: url)
            exporting = true
        } catch { app.showError(L("backup_save_failed")) }
    }

    private func inspect(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { app.showError(L("backup_unreadable")); return }
        switch BackupRules.check(data: data) {
        case .ok(let backup):
            let refs = app.visibleMedia.map { asset in
                MediaRef(id: asset.id, name: PhotoLibraryService.originalFilename(asset.id), size: nil,
                         takenMillis: asset.creationDate.map { Int64($0.timeIntervalSince1970 * 1000) })
            }
            let dispositions = Dictionary(uniqueKeysWithValues: app.visibleMedia.map { ($0.id, app.record($0.reference).disposition) })
            let plan = BackupRestore.plan(backup, current: refs, ref: { $0 }, dispositions: dispositions,
                                          albumNames: [], notesPresent: Set(app.organize.notes.keys))
            restorePlan = plan
            importSummary = L("backup_from") + " " + backup.appVersion + " · " + String(plan.missing.count)
        case .notABackup: app.showError(L("backup_not_backup"))
        case .tooNew: app.showError(L("backup_too_new"))
        }
    }

    private func apply(_ plan: RestorePlan) async {
        for (id, decision) in plan.decisions {
            let reference = ItemReference.photo(id)
            switch decision.state {
            case .kept: _ = await app.decide(reference, .keep)
            case .marked: _ = await app.decide(reference, .markForCleanup)
            case .later:
                _ = await app.decide(reference, .later(session: ReviewSessionID()))
                if decision.bookmarked { _ = await app.decide(reference, .bookmark) }
                if let due = decision.due { _ = await app.decide(reference, .schedule(due)) }
            }
        }
        for (id, tags) in plan.tags {
            if let asset = app.asset(id) { _ = app.organize.addTags(tags, to: [asset]) }
        }
        for (id, note) in plan.notes {
            if let asset = app.asset(id) { _ = app.organize.setNote(note, for: asset) }
        }
        let basketAssets = plan.basket.compactMap(app.asset)
        _ = app.organize.addToBasket(basketAssets)
        app.hide(plan.hidden)
        restorePlan = nil
        app.showToast(L("backup_done"))
    }
}
