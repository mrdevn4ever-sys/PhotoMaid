import AVKit
import PhotoMaidCore
import SwiftUI

/// Vollbild-Betrachter: blättern, zoomen, runter = schließen (keine Wisch-Aktion nach oben). Ansehen ist nie eine
/// Entscheidung; nur „In den Papierkorb“ (PhotoMaid-eigen, Favoriten geschützt, Rückgängig) geht über den Ledger.
struct ViewerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ids: [String]
    @State private var index: Int
    @State private var chrome = true
    @State private var showInfo = false
    @State private var albumSheet = false
    @State private var shareItem: MediaShareItem?
    @State private var dragDown: CGFloat = 0
    @State private var zoomed = false

    init(ids: [String], startIndex: Int) {
        self.ids = ids
        _index = State(initialValue: min(max(0, startIndex), max(0, ids.count - 1)))
    }

    private var current: MediaAsset? { ids.indices.contains(index) ? app.asset(ids[index]) : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(ids.enumerated()), id: \.offset) { i, id in
                    ViewerPage(assetID: id, isCurrent: i == index, zoomed: $zoomed) { chrome.toggle() }
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragDown)
            .opacity(1 - Double(min(dragDown, 300)) / 600)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { v in
                        guard !zoomed, v.translation.height > 0, abs(v.translation.height) > abs(v.translation.width) else { return }
                        dragDown = v.translation.height
                    }
                    .onEnded { v in
                        if !zoomed && v.translation.height > 120 && abs(v.translation.height) > abs(v.translation.width) {
                            dismiss()
                        } else {
                            withAnimation(AppMotion.standard(reduceMotion)) { dragDown = 0 }
                        }
                    }
            )
            if chrome { overlay }
        }
        .statusBarHidden(!chrome)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showInfo) { if let a = current { MediaInfoSheet(asset: a) } }
        .sheet(isPresented: $albumSheet) {
            if let a = current {
                AlbumPickerSheet(assetIDs: [a.id]) { albumID, title in
                    Task {
                        if await app.library.add([a.id], toAlbum: albumID) == .done {
                            app.rememberRecentAlbum(albumID)
                            app.showToast(LP("org_added_to_album", 1, 1, title))
                        } else {
                            app.showError(L("album_failed"))
                        }
                    }
                }
            }
        }
        .sheet(item: $shareItem) { ShareSheet(items: $0.items) }
        .accessibilityAction(.escape) { dismiss() }
    }

    private var overlay: some View {
        VStack {
            GlassEffectContainer(spacing: AppSpacing.s) {
                HStack {
                    GlassIconButton(symbol: "xmark", label: L("close")) { dismiss() }
                    Spacer()
                    if let a = current {
                        VStack(spacing: 0) {
                            if let d = a.creationDate {
                                Text(verbatim: DateText.long(d)).font(AppTypography.subheadline.weight(.semibold))
                                Text(verbatim: DateText.time(d)).font(AppTypography.caption)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, 4)
                        .glassCapsule()
                    }
                    Spacer()
                    GlassIconButton(symbol: "info.circle", label: L("info")) { showInfo = true }
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            Spacer()
            if let a = current { bottomBar(a) }
        }
    }

    private func bottomBar(_ a: MediaAsset) -> some View {
        let record = app.record(a.reference)
        return GlassEffectContainer(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                GlassIconButton(symbol: "square.and.arrow.up", label: L("share")) {
                    Task { if let s = await MediaShare.prepare([a.id]) { shareItem = s } else { app.showError(L("share_failed")) } }
                }
                GlassIconButton(symbol: a.isFavorite ? "heart.fill" : "heart", label: L(a.isFavorite ? "fav_remove" : "fav_add")) {
                    Task {
                        if await app.library.setFavorite([a.id], !a.isFavorite) == .failed { app.showError(L("fav_failed")) }
                        app.reloadLibraryIfNeeded(force: true)
                    }
                }
                GlassIconButton(symbol: "pencil", label: L("edit_action")) {
                    let id = a.id
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        app.fullScreen = a.isVideo ? .videoEditor(assetID: id) : .editor(assetID: id)
                    }
                }
                GlassIconButton(symbol: "rectangle.stack.badge.plus", label: L("org_add_to_album")) { albumSheet = true }
                if record.disposition == .markedForCleanup {
                    GlassIconButton(symbol: "arrow.uturn.backward", label: L("put_back")) {
                        Task { await app.decide(a.reference, .unmark) }
                    }
                } else {
                    GlassIconButton(symbol: "trash", label: L("lib_trash_action")) {
                        if app.settings.protectFavorites && a.isFavorite {
                            app.showError(L("lib_trash_fav_protected"))
                        } else {
                            Task {
                                await app.decide(a.reference, .markForCleanup)
                                app.showToast(L("lib_trashed_one"), actionTitle: L("undo")) { Task { _ = await app.undo() } }
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, AppSpacing.s)
    }
}

/// Eine Seite des Betrachters: Foto mit Zoom (zwei Finger, Doppeltipp) oder Video mit Systemsteuerung.
struct ViewerPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var scale
    let assetID: String
    let isCurrent: Bool
    @Binding var zoomed: Bool
    let toggleChrome: () -> Void
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    /// Volle Qualität oder Video kommt noch (ggf. aus iCloud); `downloadProgress` nur bei iCloud-Fotos.
    @State private var loading = false
    @State private var downloadProgress: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                        .environment(\.layoutDirection, .leftToRight)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .offset(pan)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(MagnifyGesture()
                            .onChanged { v in zoom = min(6, max(1, zoomBase * v.magnification)); zoomed = zoom > 1.01 }
                            .onEnded { _ in zoomBase = zoom; if zoom <= 1.01 { reset() } })
                        .simultaneousGesture(DragGesture()
                            .onChanged { v in pan = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height) }
                            .onEnded { _ in panBase = pan }, including: zoom > 1.01 ? .all : .none)
                        .onTapGesture(count: 2) {
                            withAnimation(.snappy) { if zoom > 1.01 { reset() } else { zoom = 2.5; zoomBase = 2.5; zoomed = true } }
                        }
                        .onTapGesture { toggleChrome() }
                        .accessibilityLabel(Text(verbatim: app.asset(assetID).map(MediaInfoLine.describe) ?? ""))
                } else {
                    ProgressView().tint(.white)
                }
                if loading && image != nil && player == nil {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "icloud.and.arrow.down")
                            if let downloadProgress {
                                Text(verbatim: downloadProgress.formatted(.percent.precision(.fractionLength(0))))
                                    .monospacedDigit()
                            } else {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                        }
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, 6)
                        .glassCapsule()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(key: "feed_loading"))
                        .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                }
            }
            .task(id: assetID) { await load(geo.size) }
            .onChange(of: isCurrent) { _, cur in
                if !cur { player?.pause(); reset() }
            }
        }
    }

    private func reset() {
        zoom = 1; zoomBase = 1; pan = .zero; panBase = .zero; zoomed = false
    }

    /// Wie die Fotos-App: sofort eine Vorschau, danach volle Qualität bzw. das Video – bei Bedarf aus iCloud.
    private func load(_ size: CGSize) async {
        guard let a = app.asset(assetID) else { return }
        loading = true
        defer { loading = false; downloadProgress = nil }
        if a.isVideo {
            image = await ThumbnailLoader.shared.image(assetID, size: CGSize(width: 800, height: 800))
            if case .item(let box) = await app.previews.playerItem(for: assetID) {
                player = AVPlayer(playerItem: box.value)
            }
            return
        }
        let target = PreviewPipeline.targetSize(for: CGSize(width: size.width * 2, height: size.height * 2), scale: scale)
        for await update in app.previews.progressiveImage(for: assetID, targetSize: target) {
            switch update {
            case .image(let img, _): image = img
            case .progress(let p): downloadProgress = p < 1 ? p : nil
            case .failed: break
            }
        }
        if image == nil, !Task.isCancelled {
            image = await ThumbnailLoader.shared.image(assetID, size: CGSize(width: 800, height: 800))
        }
    }
}

/// Infos: Aufnahme, Auflösung, gemessene Größe, Dauer, Dateiname, RAW, Ort (nur Koordinaten, keine Kartenanfrage),
/// eigene Schlagwörter und Notiz (nur PhotoMaid).
struct MediaInfoSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let asset: MediaAsset
    @State private var size: KnownSize?
    @State private var name: String?
    @State private var raw = false
    @State private var note = ""
    @State private var tagSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let d = asset.creationDate { info(L("lib_info_taken"), DateText.longWithTime(d)) }
                    info(L("lib_info_type"), MediaInfoLine.describe(asset).components(separatedBy: " · ").dropFirst().first ?? "")
                    info(L("lib_info_resolution"), "\(asset.pixelWidth) × \(asset.pixelHeight)")
                    info(L("lib_info_size"), size.map(SizeText.size) ?? "…")
                    if asset.isVideo { info(L("lib_info_duration"), DateText.duration(asset.duration)) }
                    if let name { info(L("lib_info_name"), name) }
                    if raw { info(L("lib_info_raw"), L("yes")) }
                    if let lat = asset.latitude, let lon = asset.longitude {
                        info(L("info_location"), String(format: "%.5f, %.5f", lat, lon))
                    }
                }
                Section(L("org_tags")) {
                    let tags = app.organize.tags(of: asset.id)
                    if tags.isEmpty {
                        Text(key: "org_tags_none").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                    } else {
                        ForEach(tags, id: \.self) { t in
                            Text(verbatim: t)
                                .swipeActions { Button(L("org_tag_remove"), role: .destructive) { app.organize.removeTag(t, from: [asset.id]) } }
                        }
                    }
                    Button { tagSheet = true } label: { Label(L("org_tag_add"), systemImage: "tag") }
                }
                Section(L("org_note")) {
                    TextField(L("org_note_hint"), text: $note, axis: .vertical).lineLimit(2...6)
                    Button(L("org_note_save")) {
                        if !app.organize.setNote(note, for: asset) { app.showError(L("error_change_not_saved")) }
                    }
                }
            }
            .navigationTitle(L("info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } } }
            .sheet(isPresented: $tagSheet) { TagEditorSheet(assets: [asset]) }
        }
        .presentationDetents([.medium, .large])
        .task {
            note = app.organize.note(of: asset.id) ?? ""
            let id = asset.id
            name = await Task.detached { PhotoLibraryService.originalFilename(id) }.value
            raw = await Task.detached { PhotoLibraryService.hasRawAlternate(id) }.value
            size = await app.size(asset)
        }
    }

    private func info(_ title: String, _ value: String) -> some View {
        LabeledContent { Text(verbatim: value).multilineTextAlignment(.trailing) } label: { Text(verbatim: title) }
    }
}

/// Eigene Schlagwörter für ein oder mehrere Medien (nur PhotoMaid, keine Erkennung, Datei unverändert).
struct TagEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let assets: [MediaAsset]
    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(L("org_tag_new_hint"), text: $newTag).onSubmit(add)
                        Button(L("org_tag_add"), action: add).disabled(TagRules.normalize(newTag) == nil)
                    }
                }
                let all = app.organize.allTags
                if all.isEmpty {
                    Text(key: "org_tags_none").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                }
                ForEach(all, id: \.tag) { entry in
                    let state = TagRules.state(entry.tag, tagsOfSelection: assets.map { app.organize.tags(of: $0.id) })
                    Button {
                        if state == .all { app.organize.removeTag(entry.tag, from: assets.map(\.id)) }
                        else { app.organize.addTags([entry.tag], to: assets) }
                    } label: {
                        HStack {
                            Image(systemName: state == .all ? "checkmark.circle.fill" : (state == .some ? "minus.circle" : "circle"))
                                .foregroundStyle(AppColors.accent)
                            Text(verbatim: entry.tag)
                            Spacer()
                            if state == .some { Text(key: "org_tag_state_some").font(AppTypography.caption) }
                        }
                    }
                }
            }
            .navigationTitle(LP("org_tags_for", assets.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        guard TagRules.normalize(newTag) != nil else { return }
        if !app.organize.addTags([newTag], to: assets) { app.showError(L("error_change_not_saved")) }
        newTag = ""
    }
}
