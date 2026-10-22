import PhotoMaidCore
import SwiftUI

/// Inhalt des Tresors: Ordner, Raster, Sortieren, Auswahl (Verschieben, Zurück in Fotos, Teilen, Löschen) und Ablegen.
/// Meldungen erscheinen hier als Hinweis (die Toasts der App liegen unter dieser Ebene).
struct VaultHomeView: View {
    @Environment(AppModel.self) private var app
    @State private var vault = VaultStore.shared
    @State private var folderID: String?
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var picking = false
    @State private var pendingImport: [String] = []
    /// Von PhotoMaid erstellte Kopien der Auswahl (Bearbeitungen, Collagen, Filme, GIFs) zum Mit-Ablegen.
    @State private var pendingCopies: [String] = []
    @State private var confirmImport = false
    @State private var pendingDelete: Set<String>?
    @State private var confirmRestore = false
    @State private var moveSheet = false
    @State private var settingsSheet = false
    @State private var newFolder = false
    @State private var folderAdPrompt = false
    @State private var watchingAd = false
    @State private var folderName = ""
    @State private var renaming: VaultFolder?
    @State private var deletingFolder: VaultFolder?
    @State private var share: VaultShare?
    @State private var viewer: VaultViewerRequest?
    @State private var notice: String?
    /// Videos zusammenfügen (Ergebnis bleibt im Tresor).
    @State private var merging: VaultMergeRequest?

    private var sort: VaultSort { vault.settings?.sort ?? .captured }
    private var items: [VaultItem] { sort.sorted(vault.index.items(inFolder: folderID)) }
    private var unlimited: Bool { app.capabilities.hasProToolsAccess }
    private var remaining: Int? { VaultPolicy.remaining(existing: vault.mediaSlotsUsed, unlimited: unlimited) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    summary
                    if vault.stillInLibraryCount > 0 { stillInPhotosBanner }
                    folderBar
                    if items.isEmpty {
                        EmptyState(symbol: "lock.rectangle.stack", title: L(folderID == nil ? "vault_empty_title" : "vault_folder_empty"))
                            .padding(.horizontal, -AppSpacing.pageMargin)
                    } else {
                        grid
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.bottom, AppSpacing.xxl)
            }
            .appPage()
            // Einträge älterer Fassungen und eine beschädigte Verbergen-Liste beim Öffnen abgleichen.
            .task { await vault.syncConcealment(app: app) }
            .navigationTitle(L("vault_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    selectionBar
                } else {
                    PrimaryButton(title: L("vault_add"), symbol: "plus") { startImport() }.vaultBottomAction()
                }
            }
            .overlay { progressOverlay }
            // Rückfrage erst, wenn die Auswahl ganz geschlossen ist (sonst erscheint der Dialog nicht).
            .sheet(isPresented: $picking, onDismiss: {
                pendingCopies = pendingImport.isEmpty ? [] : vault.derivedCopies(of: pendingImport, app: app)
                confirmImport = !pendingImport.isEmpty
            }) {
                StudioMediaPicker(allowsVideos: true, limit: remaining ?? 10_000) { ids in pendingImport = ids }
            }
            .sheet(isPresented: $moveSheet) { VaultMoveSheet(ids: selection) { selecting = false; selection = [] } }
            .sheet(isPresented: $settingsSheet) { VaultSettingsView() }
            .sheet(item: $share) { item in
                ShareSheet(items: item.urls) { vault.removeTempFiles(item.urls) }
            }
            .fullScreenCover(item: $viewer) { request in
                VaultViewer(ids: request.ids, start: request.index)
            }
            .fullScreenCover(item: $merging, onDismiss: {
                guard vault.lastEdit != nil else { return }
                vault.lastEdit = nil
                selection = []
                selecting = false
                notice = L("vault_edit_saved")
            }) { request in
                VaultMovieView(itemIDs: request.ids).environment(app)
            }
            .alert(L("vault_import_confirm_title", pendingImport.count), isPresented: $confirmImport) {
                if pendingCopies.isEmpty {
                    Button(L("vault_import_action")) { Task { await runImport(withCopies: false) } }
                } else {
                    Button(L("vault_import_with_copies", pendingCopies.count)) { Task { await runImport(withCopies: true) } }
                    Button(L("vault_import_without_copies")) { Task { await runImport(withCopies: false) } }
                }
                Button(L("cancel"), role: .cancel) { pendingImport = []; pendingCopies = [] }
            } message: {
                if pendingCopies.isEmpty {
                    Text(key: "vault_import_confirm_text")
                } else {
                    Text(verbatim: L("vault_import_confirm_text") + "\n\n" + L("vault_import_copies_text", pendingCopies.count))
                }
            }
            .vaultTrashConfirmation($pendingDelete) { ids in
                if vault.moveToTrash(ids) {
                    selection.subtract(ids)
                    if selection.isEmpty { selecting = false }
                } else {
                    notice = L("vault_error_generic")
                }
            }
            .confirmationDialog(L("vault_restore"), isPresented: $confirmRestore, titleVisibility: .visible) {
                Button(L("vault_restore_move")) { Task { await restore(remove: true) } }
                Button(L("vault_restore_copy")) { Task { await restore(remove: false) } }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(key: "vault_restore_text")
            }
            .alert(L("vault_new_folder"), isPresented: $newFolder) {
                TextField(L("vault_folder_name"), text: $folderName)
                Button(L("save")) {
                    if let f = vault.createFolder(folderName) {
                        folderID = f.id
                        VaultFolderGate.folderCreated(app)
                    } else {
                        notice = L("vault_folder_invalid")
                    }
                    folderName = ""
                }
                Button(L("cancel"), role: .cancel) { folderName = "" }
            }
            // Gratis: je neuem Ordner ein kurzes Werbevideo (E19); mit Pro ohne.
            .confirmationDialog(L("vault_new_folder"), isPresented: $folderAdPrompt, titleVisibility: .visible) {
                Button(L("vault_ad_folder_watch")) { Task { await watchFolderAd() } }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(key: "vault_ad_folder_text")
            }
            .alert(L("vault_rename_folder"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(L("vault_folder_name"), text: $folderName)
                Button(L("save")) {
                    if let r = renaming, !vault.renameFolder(r.id, to: folderName) { notice = L("vault_folder_invalid") }
                    renaming = nil
                    folderName = ""
                }
                Button(L("cancel"), role: .cancel) { renaming = nil; folderName = "" }
            }
            .alert(L("vault_delete_folder"), isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
                Button(L("vault_delete_folder"), role: .destructive) {
                    if let f = deletingFolder { vault.deleteFolder(f.id); if folderID == f.id { folderID = nil } }
                    deletingFolder = nil
                }
                Button(L("cancel"), role: .cancel) { deletingFolder = nil }
            } message: {
                Text(key: "vault_delete_folder_text")
            }
            .alert(L("vault_title"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button(L("ok")) { notice = nil }
            } message: {
                Text(verbatim: notice ?? "")
            }
            .onChange(of: folderID) { _, _ in selection = [] }
        }
    }

    // MARK: Teile

    private var summary: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "lock.fill").foregroundStyle(AppColors.accent).accessibilityHidden(true)
            Text(verbatim: summaryText).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.top, AppSpacing.s)
    }

    private var summaryText: String {
        let count = vault.index.items.count
        let size = SizeText.bytes(vault.index.totalSize)
        if unlimited { return L("vault_summary", count, size) }
        return L("vault_summary_free", vault.mediaSlotsUsed, VaultPolicy.freeItemLimit, size)
    }

    private var stillInPhotosBanner: some View {
        InfoBanner(symbol: "photo.on.rectangle", tint: AppColors.warning,
                   text: L("vault_still_in_photos", vault.stillInLibraryCount), actionTitle: L("vault_still_in_photos_action")) {
            Task {
                let removed = await vault.retryLibraryRemoval(app: app)
                if removed > 0 { notice = L("vault_removed_from_photos", removed) }
            }
        }
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                chip(title: L("vault_all"), count: vault.index.items.count, selected: folderID == nil) { folderID = nil }
                ForEach(vault.index.folders) { f in
                    chip(title: f.name, count: vault.index.count(inFolder: f.id), selected: folderID == f.id) { folderID = f.id }
                        .contextMenu {
                            Button { folderName = f.name; renaming = f } label: { Label(L("vault_rename_folder"), systemImage: "pencil") }
                            Button(role: .destructive) { deletingFolder = f } label: { Label(L("vault_delete_folder"), systemImage: "trash") }
                        }
                }
                Button { startNewFolder() } label: {
                    Label(L("vault_new_folder"), systemImage: "folder.badge.plus")
                        .font(AppTypography.subheadline.weight(.semibold))
                        .padding(.horizontal, AppSpacing.s)
                        .frame(minHeight: AppSpacing.minTouch)
                }
                .buttonStyle(.pmBordered)
            }
        }
    }

    private func chip(title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                Text(verbatim: "\(count)").foregroundStyle(selected ? AppColors.onAccent.opacity(0.7) : AppColors.textSecondary).monospacedDigit()
            }
            .font(AppTypography.subheadline.weight(.semibold))
            .padding(.horizontal, AppSpacing.s)
            .frame(minHeight: AppSpacing.minTouch)
        }
        .modifier(GlassButtonStyleModifier(prominent: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var grid: some View {
        // Artefakt: drei Spalten, 6 pt Abstand, Hochformat 3 : 4 mit Radius 12.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        let list = items
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                Button {
                    if selecting {
                        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                    } else {
                        viewer = VaultViewerRequest(ids: list.map(\.id), index: index)
                    }
                } label: {
                    VaultCell(item: item, selected: selection.contains(item.id), selecting: selecting)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.contains(item.id) ? .isSelected : [])
                .accessibilityIdentifier("vault.media.item.\(item.id)")
                // Native swipe recognition cooperates with the enclosing ScrollView.
                // A SwiftUI child DragGesture can lose the gesture to scrolling on iOS 26.
                .gesture(VaultMediaTrashSwipe(enabled: !selecting) {
                    pendingDelete = [item.id]
                })
                .contextMenu {
                    Button(L("vault_delete"), systemImage: "trash", role: .destructive) { pendingDelete = [item.id] }
                }
                .accessibilityAction(named: Text(key: "vault_delete")) { pendingDelete = [item.id] }
            }
        }
    }

    private func startNewFolder() {
        switch VaultFolderGate.access(app) {
        case .free:
            newFolder = true
        case .watchAd:
            AdsService.shared.preloadRewarded(app: app)
            folderAdPrompt = true
        case .unavailable:
            notice = L("vault_ad_folder_unavailable")
        }
    }

    private func watchFolderAd() async {
        guard !watchingAd else { return }
        watchingAd = true
        defer { watchingAd = false }
        switch await VaultFolderGate.watchAd(app) {
        case .earned: newFolder = true
        case .dismissed: notice = L("vault_ad_folder_dismissed")
        case .unavailable: notice = L("vault_ad_folder_unavailable")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
        VaultSelectionToolbarItem(scope: "media", isEmpty: items.isEmpty, selecting: $selecting, selection: $selection)
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !selecting {
                Menu {
                    Picker(L("vault_sort"), selection: Binding(get: { sort }, set: { vault.setSort($0) })) {
                        Text(key: "vault_sort_captured").tag(VaultSort.captured)
                        Text(key: "vault_sort_added").tag(VaultSort.added)
                        Text(key: "vault_sort_name").tag(VaultSort.name)
                        Text(key: "vault_sort_size").tag(VaultSort.size)
                    }
                    Button { settingsSheet = true } label: { Label(L("vault_settings"), systemImage: "gearshape") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text(key: "more_actions"))
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: AppSpacing.xs) {
            Text(verbatim: LP("grid_selected", selection.count)).font(AppTypography.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            if selectedVideos.count >= 2 {
                barButton("film.stack", "movie_title") { merging = VaultMergeRequest(ids: selectedVideos) }
                    .accessibilityIdentifier("vault.media.merge")
            }
            barButton("folder", "vault_move") { moveSheet = true }
            barButton("square.and.arrow.up", "share") { Task { await shareSelection() } }
            barButton("photo.badge.arrow.down", "vault_restore") { confirmRestore = true }
            barButton("trash", "vault_delete", tint: AppColors.cleanup) { pendingDelete = selection }
                .accessibilityIdentifier("vault.media.trash")
        }
        .disabled(selection.isEmpty)
        .padding(.horizontal, AppSpacing.m)
        .glassCapsule()
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.bottom, AppSpacing.s)
    }

    /// Ausgewählte Videos in Rasterreihenfolge (für „Zusammenfügen“).
    private var selectedVideos: [String] { items.filter { $0.isVideo && selection.contains($0.id) }.map(\.id) }

    private func barButton(_ symbol: String, _ key: String, tint: Color = AppColors.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
        }
        .accessibilityLabel(Text(key: key))
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if let p = vault.progress {
            VStack(spacing: AppSpacing.s) {
                ProgressView(value: Double(p.done), total: Double(max(1, p.total)))
                    .frame(maxWidth: 220)
                Text(verbatim: L("vault_progress", p.done, p.total)).font(AppTypography.footnote).monospacedDigit()
                Text(key: "vault_progress_hint").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(AppSpacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: Aktionen

    private func startImport() {
        if let remaining, remaining == 0 {
            notice = L("vault_limit_reached", VaultPolicy.freeItemLimit)
            return
        }
        picking = true
    }

    private func runImport(withCopies: Bool) async {
        let ids = pendingImport + (withCopies ? pendingCopies : [])
        pendingImport = []
        pendingCopies = []
        let report = await vault.importAssets(ids, app: app)
        var lines: [String] = []
        if report.imported > 0 { lines.append(L("vault_import_done", report.imported, report.removedFromLibrary)) }
        if report.imported > report.removedFromLibrary { lines.append(L("vault_import_declined")) }
        if report.failed > 0 { lines.append(L("vault_import_failed", report.failed)) }
        if report.skippedByLimit > 0 { lines.append(L("vault_import_limit", report.skippedByLimit, VaultPolicy.freeItemLimit)) }
        if report.removedFromLibrary > 0 { lines.append(L("vault_import_recently_deleted")) }
        notice = lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private func restore(remove: Bool) async {
        let ids = selection
        let report = await vault.restore(ids, removeFromVault: remove, app: app)
        selection = []
        selecting = false
        var text = L("vault_restore_done", report.restored)
        if report.keptComplete > 0 { text += "\n\n" + L("vault_restore_kept_complete", report.keptComplete) }
        if report.failed > 0 { text += "\n\n" + L("vault_restore_failed", report.failed) }
        notice = text
    }

    private func shareSelection() async {
        guard let urls = await vault.shareFiles(selection) else { return }
        if urls.isEmpty { notice = L("share_failed") } else { share = VaultShare(urls: urls) }
    }
}

struct VaultShare: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct VaultViewerRequest: Identifiable {
    let id = UUID()
    let ids: [String]
    let index: Int
}

/// Rasterzelle: entschlüsseltes Vorschaubild (nur im Speicher), quadratisch beschnitten, nie verzerrt.
struct VaultCell: View {
    @State private var vault = VaultStore.shared
    let item: VaultItem
    let selected: Bool
    let selecting: Bool

    var body: some View {
        Rectangle()
            .fill(AppColors.backgroundTint)
            .overlay {
                if let image = vault.thumbnails[item.id] {
                    Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
                } else {
                    Image(systemName: item.isVideo ? "video" : "photo").foregroundStyle(AppColors.textSecondary.opacity(0.4))
                        .accessibilityHidden(true)
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Text(verbatim: DateText.duration(item.duration)).monospacedDigit()
                        .font(.caption2.weight(.semibold)).foregroundStyle(.white).shadow(radius: 2).padding(4)
                } else if item.kind == .livePhoto {
                    Image(systemName: "livephoto").font(.caption).foregroundStyle(.white).shadow(radius: 2).padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? AppColors.accentFill : .white)
                        .background(Circle().fill(.black.opacity(0.25)))
                        .padding(4)
                }
            }
            .overlay { if selected { Rectangle().fill(.white.opacity(0.18)).allowsHitTesting(false) } }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .task(id: item.id) { await vault.thumbnail(item) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var accessibilityText: String {
        let kind = L(item.isVideo ? "vault_kind_video" : "vault_kind_photo")
        guard let ms = item.creationMs else { return kind }
        return kind + " · " + DateText.longWithTime(Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}

/// Ziel zum Verschieben: Ordner oder „Ohne Ordner“.
struct VaultMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    let ids: Set<String>
    let done: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Button { move(nil) } label: { Label(L("vault_no_folder"), systemImage: "tray") }
                ForEach(vault.index.folders) { f in
                    Button { move(f.id) } label: { Label(f.name, systemImage: "folder") }
                }
            }
            .navigationTitle(L("vault_move"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func move(_ folderID: String?) {
        vault.move(ids, to: folderID)
        done()
        dismiss()
    }
}
