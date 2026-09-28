import PhotoMaidCore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Screen 7 – Downloads/Dateien. Nur verbundene Quellen. Heißt „Downloads“ nur,
/// wenn eine entsprechende Quelle verbunden wurde.
struct FileBrowserView: View {
    @Environment(AppModel.self) private var app
    @State private var index = FileIndex()
    @State private var query = ""
    @State private var kind: FileKindFilter = .all
    @State private var previewURL: URL?
    @State private var previewRoot: URL?
    @State private var showImporter = false
    @State private var importAsDownloads = true
    @State private var records: [ItemReference: ItemRecord] = [:]
    @State private var errorText: String?

    private var title: LocalizedStringKey { app.sources.downloadsSource == nil ? "Dateien" : "Downloads" }

    private var filtered: [FileEntry] {
        index.entries
            .filter { kind == .all || $0.kind == kind }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    var body: some View {
        List {
            if app.sources.sources.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Text("Noch kein Ordner verbunden").font(AppTypography.headline)
                        Text("iOS erlaubt PhotoMaid keinen Zugriff auf alle Dateien. Wähle einen Ordner aus, z. B. deinen Downloads-Ordner in der Dateien-App.")
                            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        Button("Ordner auswählen") { showImporter = true }.buttonStyle(.glassProminent)
                    }
                }
            } else {
                Section {
                    Picker("Dateityp", selection: $kind) {
                        Text("Alle").tag(FileKindFilter.all)
                        Text("PDFs").tag(FileKindFilter.pdf)
                        Text("Archive").tag(FileKindFilter.archive)
                        Text("Bilder").tag(FileKindFilter.image)
                        Text("Videos").tag(FileKindFilter.video)
                        Text("Dokumente").tag(FileKindFilter.document)
                        Text("Andere").tag(FileKindFilter.other)
                    }
                    .pickerStyle(.menu)
                }
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { entry in fileRow(entry) }
                    }
                }
                if !index.failedSources.isEmpty {
                    Section {
                        Label("Mindestens eine Quelle ist nicht erreichbar. Verbinde den Ordner erneut.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppColors.warning)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text(title))
        .searchable(text: $query, prompt: Text("Dateien durchsuchen …"))
        .overlay { if index.isScanning && index.entries.isEmpty { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ordner hinzufügen", systemImage: "folder.badge.plus") { showImporter = true }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do { try app.sources.add(folderURL: url, asDownloads: importAsDownloads && app.sources.downloadsSource == nil) }
                catch SourceProblem.cloudProviderNotSupported {
                    errorText = String(localized: "Cloud-Ordner (z. B. iCloud Drive) werden nicht als lokale Quelle unterstützt.")
                } catch {
                    errorText = String(localized: "Der Ordner konnte nicht verbunden werden.")
                }
                Task { await reload() }
            case .failure:
                errorText = String(localized: "Der Ordner konnte nicht verbunden werden.")
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, url in
            // Security-scoped Zugriff nach Schließen der Vorschau ausgleichen.
            if url == nil, let root = previewRoot { app.sources.endAccess(root); previewRoot = nil }
        }
        .alert("Hinweis", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var groups: [(String, [FileEntry])] {
        let now = Date()
        var today: [FileEntry] = [], month: [FileEntry] = [], older: [FileEntry] = []
        for e in filtered {
            guard let m = e.modified else { older.append(e); continue }
            if Calendar.current.isDateInToday(m) { today.append(e) }
            else if now.timeIntervalSince(m) < 30 * 86_400 { month.append(e) }
            else { older.append(e) }
        }
        return [(String(localized: "Heute"), today), (String(localized: "Letzte 30 Tage"), month),
                (String(localized: "Älter"), older)].filter { !$0.1.isEmpty }
    }

    private func reload() async {
        await index.scan(app.sources)
        records = await app.ledger.records(for: index.entries.map(\.reference))
    }

    private func fileRow(_ e: FileEntry) -> some View {
        let state = records[e.reference]?.disposition ?? .undecided
        return Button { open(e) } label: {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: symbol(e.kind)).font(.title2).foregroundStyle(tint(e.kind))
                    .frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(AppTypography.subheadline.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(AppColors.textPrimary)
                    HStack(spacing: 4) {
                        SizeText.size(e.size)
                        if let m = e.modified { Text("·"); Text(m.formatted(date: .abbreviated, time: .omitted)) }
                    }
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                if state == .markedForCleanup { Image(systemName: "trash").foregroundStyle(AppColors.cleanup) }
                if state == .later { Image(systemName: "bookmark").foregroundStyle(AppColors.later) }
                if state == .kept { Image(systemName: "checkmark").foregroundStyle(AppColors.keep) }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Behalten") { Task { await decide(e, .keep) } }.tint(AppColors.keep)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Vormerken") { Task { await decide(e, .markForCleanup) } }.tint(AppColors.cleanup)
            Button("Später") { Task { await decide(e, .later(session: ReviewSessionID())) } }.tint(AppColors.later)
        }
    }

    private func decide(_ e: FileEntry, _ action: DecisionAction) async {
        await app.decide(e.reference, action)
        records[e.reference] = await app.ledger.record(for: e.reference)
    }

    /// Native Vorschau (Quick Look). Keine unsichere WebView, kein Entpacken, kein Ausführen.
    private func open(_ e: FileEntry) {
        guard e.kind != .archive, e.kind != .other else { return }
        guard let root = app.sources.beginAccess(e.sourceID) else { return }
        // Zugriff bleibt für die Dauer der Vorschau offen und wird beim Schließen ausgeglichen.
        if let url = FileScanner.safeURL(root: root, relativePath: e.relativePath) {
            previewRoot = root
            previewURL = url
        } else {
            app.sources.endAccess(root)
        }
    }

    private func symbol(_ k: FileKindFilter) -> String {
        switch k {
        case .pdf: "doc.richtext.fill"
        case .archive: "doc.zipper"
        case .image: "photo.fill"
        case .video: "film.fill"
        case .document: "doc.text.fill"
        case .other, .all: "doc.fill"
        }
    }

    private func tint(_ k: FileKindFilter) -> Color {
        switch k {
        case .pdf: .red
        case .archive: .gray
        case .image: .blue
        case .video: .purple
        default: .blue
        }
    }
}

/// Verbundene Quellen verwalten. Entfernen löscht keine Dateien.
struct SourcesView: View {
    @Environment(AppModel.self) private var app
    @State private var showImporter = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(app.sources.sources) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.displayName).font(AppTypography.headline)
                            if s.isDownloads { Text("Downloads").font(AppTypography.caption).foregroundStyle(AppColors.accent) }
                        }
                        Text(s.isWritable ? "Lesen und Löschen möglich" : "Nur lesen (schreibgeschützt)")
                            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        if app.sources.problems[s.id] != nil {
                            Text("Nicht erreichbar – bitte erneut verbinden").font(AppTypography.caption).foregroundStyle(AppColors.warning)
                        }
                    }
                    .swipeActions {
                        Button("Verbindung entfernen", role: .destructive) { try? app.sources.remove(s.id) }
                    }
                }
            } footer: {
                Text("Verbindung entfernen löscht keine Dateien. PhotoMaid sieht nur Ordner, die du hier auswählst.")
            }
            Section {
                Button("Ordner hinzufügen", systemImage: "folder.badge.plus") { showImporter = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Verbundene Quellen"))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                do { try app.sources.add(folderURL: url, asDownloads: false) }
                catch { errorText = String(localized: "Der Ordner konnte nicht verbunden werden.") }
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }
}
