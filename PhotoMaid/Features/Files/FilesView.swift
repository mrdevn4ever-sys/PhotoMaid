import PhotoMaidCore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Dateien aus selbst gewählten Ordnern (Dateien-App, security-scoped). Ansehen per Quick Look. Aussortieren legt
/// Dateien in den PhotoMaid-Papierkorb; gelöscht wird erst dort nach eigener deutlicher Bestätigung (endgültig).
struct FilesView: View {
    @Environment(AppModel.self) private var app
    @State private var importing = false
    @State private var kind: FileKindFilter = .all
    @State private var sort = 0
    @State private var query = ""
    @State private var previewURL: URL?
    @State private var previewRoot: URL?

    var body: some View {
        List {
            Section {
                ForEach(app.sources.sources) { s in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(AppColors.amber)
                        VStack(alignment: .leading) {
                            Text(verbatim: s.displayName)
                            Text(key: app.sources.problems[s.id] != nil ? "sources_unreachable" : (s.isWritable ? "sources_rw" : "sources_ro"))
                                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .swipeActions {
                        Button(L("sources_remove"), role: .destructive) {
                            try? app.sources.remove(s.id)
                            Task { await app.files.scan(app.sources) }
                        }
                    }
                }
                Button { importing = true } label: { Label(L("add_folder"), systemImage: "folder.badge.plus") }
                    .frame(minHeight: AppSpacing.minTouch)
            } header: {
                Text(key: "connected_sources")
            } footer: {
                Text(key: "sources_footer")
            }
            if app.sources.sources.isEmpty {
                EmptyState(symbol: "folder", title: L("files_none_title"), message: L("files_none_message"),
                           actionTitle: L("choose_folder")) { importing = true }
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    Picker(L("file_type"), selection: $kind) {
                        ForEach(FileKindFilter.allCases) { k in Text(verbatim: kindName(k)).tag(k) }
                    }
                    Picker(L("order_title"), selection: $sort) {
                        Text(key: "sort_largest").tag(0)
                        Text(key: "sort_newest").tag(1)
                        Text(key: "sort_oldest").tag(2)
                    }
                    if !app.files.failedSources.isEmpty {
                        Text(key: "files_source_unreachable").font(AppTypography.footnote).foregroundStyle(AppColors.warning)
                    }
                }
                Section {
                    if app.files.isScanning { ProgressView() }
                    ForEach(visible) { f in fileRow(f) }
                }
            }
        }
        .searchable(text: $query, prompt: Text(key: "files_search"))
        .appPage()
        .navigationTitle(L("files"))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                do {
                    try app.sources.add(folderURL: url, asDownloads: false)
                    Task { await app.files.scan(app.sources) }
                } catch SourceProblem.cloudProviderNotSupported {
                    app.showError(L("error_cloud_folder"))
                } catch {
                    app.showError(L("error_folder_connect"))
                }
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, url in
            if url == nil, let root = previewRoot { app.sources.endAccess(root); previewRoot = nil }
        }
        .task { if app.files.scannedAt == nil { await app.files.scan(app.sources) } }
        .refreshable { await app.files.scan(app.sources) }
    }

    private var visible: [FileEntry] {
        let tokens = SearchText.tokens(query)
        var list = app.files.entries.filter { kind == .all || $0.kind == kind }
        if !tokens.isEmpty { list = list.filter { SearchText.matches(tokens, fields: [$0.name]) } }
        switch sort {
        case 1: list.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        case 2: list.sort { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
        default: list.sort { ($0.size.bytes ?? -1) > ($1.size.bytes ?? -1) }
        }
        return list
    }

    private func kindName(_ k: FileKindFilter) -> String {
        switch k {
        case .all: L("kind_all")
        case .pdf: L("kind_pdf")
        case .archive: L("kind_archive")
        case .image: L("kind_image")
        case .video: L("kind_video")
        case .document: L("kind_document")
        case .other: L("kind_other")
        }
    }

    private func fileRow(_ f: FileEntry) -> some View {
        let record = app.record(f.reference)
        let marked = record.disposition == .markedForCleanup
        return HStack(spacing: AppSpacing.s) {
            Image(systemName: f.kind == .pdf ? "doc.richtext" : (f.kind == .image ? "photo" : (f.kind == .video ? "film" : "doc")))
                .foregroundStyle(AppColors.textSecondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: f.name).lineLimit(1).truncationMode(.middle)
                Text(verbatim: [SizeText.size(f.size), f.modified.map(DateText.abbreviated)].compactMap { $0 }.joined(separator: " · "))
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
            if marked { Image(systemName: "trash.fill").foregroundStyle(AppColors.cleanup).accessibilityLabel(Text(key: "dir_trash")) }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .onTapGesture { preview(f) }
        .swipeActions(edge: .leading) {
            Button { Task { await app.decide(f.reference, .keep) } } label: { Label(L("keep"), systemImage: "checkmark") }
                .tint(AppColors.success)
        }
        .swipeActions(edge: .trailing) {
            if marked {
                Button { Task { await app.decide(f.reference, .unmark) } } label: { Label(L("put_back"), systemImage: "arrow.uturn.backward") }
            } else {
                Button { Task { await app.decide(f.reference, .markForCleanup) } } label: { Label(L("dir_trash"), systemImage: "trash") }
                    .tint(AppColors.cleanup)
            }
        }
        .accessibilityAction(named: Text(key: "dir_trash")) { Task { await app.decide(f.reference, .markForCleanup) } }
    }

    private func preview(_ f: FileEntry) {
        guard let root = app.sources.beginAccess(f.sourceID),
              let url = FileScanner.safeURL(root: root, relativePath: f.relativePath) else {
            app.showError(L("no_viewer"))
            return
        }
        previewRoot = root
        previewURL = url
    }
}
