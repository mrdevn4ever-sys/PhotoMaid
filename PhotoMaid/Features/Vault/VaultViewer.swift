import AVKit
import PhotoMaidCore
import SwiftUI

/// Gleiche Bühne wie in Fotos: Tippen blendet Leisten aus/ein, Fotos zoomen,
/// Videos haben genau eine Steuerung unter dem Medium. Laden bleibt im Tresor.
struct VaultViewer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    @State private var ids: [String]
    @State private var index: Int
    /// Bild- oder Videobearbeitung im Tresor (Ergebnis bleibt im Tresor).
    @State private var editing: VaultEditTarget?
    @State private var savedBanner: String?
    @State private var share: VaultShare?
    @State private var confirmDelete = false
    @State private var confirmRestore = false
    @State private var notice: String?
    @State private var chrome = true
    @State private var zoomed = false
    @State private var activeVideoPlayer: AVPlayer?

    init(ids: [String], start: Int) {
        _ids = State(initialValue: ids)
        _index = State(initialValue: min(max(0, start), max(0, ids.count - 1)))
    }

    private var current: VaultItem? {
        guard ids.indices.contains(index) else { return nil }
        return vault.index.items.first { $0.id == ids[index] }
    }

    var body: some View {
        VStack(spacing: 0) {
            if chrome { headerBar }
            TabView(selection: $index) {
                ForEach(Array(ids.enumerated()), id: \.offset) { i, id in
                    if let item = vault.index.items.first(where: { $0.id == id }) {
                        VaultViewerPage(item: item, isCurrent: i == index, zoomed: $zoomed,
                                        activeVideoPlayer: $activeVideoPlayer) { chrome.toggle() }
                            .tag(i)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                if !zoomed && value.translation.height > 120 && abs(value.translation.height) > abs(value.translation.width) {
                    dismiss()
                }
            })
            if chrome, let item = current {
                VStack(spacing: AppSpacing.s) {
                    if item.isVideo, let activeVideoPlayer {
                        ViewerVideoControls(player: activeVideoPlayer, duration: item.duration)
                            .id(item.id)
                            .accessibilityIdentifier("vault.viewer.playback")
                    }
                    actionBar
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.s)
                .background(Color.black)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(!chrome)
        .preferredColorScheme(.dark)
        .sheet(item: $share) { item in
            ShareSheet(items: item.urls) { vault.removeTempFiles(item.urls) }
        }
        .fullScreenCover(item: $editing, onDismiss: showEditResult) { target in
            Group {
                if target.video {
                    VideoEditorView(assetID: target.id, inVault: true)
                } else {
                    PhotoEditorView(assetID: target.id, inVault: true)
                }
            }
            .environment(app)
        }
        .overlay(alignment: .top) {
            if let savedBanner {
                Text(verbatim: savedBanner)
                    .font(AppTypography.footnote.weight(.semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.m).padding(.vertical, AppSpacing.xs)
                    .glassCapsule()
                    .padding(.top, 60).padding(.horizontal, AppSpacing.pageMargin)
                    .transition(.opacity)
                    .accessibilityIdentifier("vault.viewer.saved")
                    .task(id: savedBanner) {
                        try? await Task.sleep(for: .seconds(3))
                        self.savedBanner = nil
                    }
            }
        }
        .alert(L("vault_delete_title", 1), isPresented: $confirmDelete) {
            Button(L("vault_delete"), role: .destructive) { deleteCurrent() }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(key: "vault_delete_text")
        }
        .confirmationDialog(L("vault_restore"), isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(L("vault_restore_move")) { Task { await restoreCurrent(remove: true) } }
            Button(L("vault_restore_copy")) { Task { await restoreCurrent(remove: false) } }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(key: "vault_restore_text")
        }
        .alert(L("vault_title"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(L("ok")) { notice = nil }
        } message: {
            Text(verbatim: notice ?? "")
        }
        .onChange(of: index) { _, _ in
            activeVideoPlayer?.pause()
            activeVideoPlayer = nil
            zoomed = false
        }
        .onChange(of: vault.phase) { _, phase in
            if phase != .unlocked {
                activeVideoPlayer?.pause()
                activeVideoPlayer?.replaceCurrentItem(with: nil)
                activeVideoPlayer = nil
                dismiss()
            }
        }
        .onDisappear {
            activeVideoPlayer?.pause()
            activeVideoPlayer = nil
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    private var headerBar: some View {
        GlassEffectContainer(spacing: AppSpacing.s) {
            HStack {
                GlassIconButton(symbol: "xmark", label: L("vault_close_viewer")) { dismiss() }
                    .accessibilityIdentifier("vault.viewer.close")
                Spacer()
                if let item = current, let ms = item.creationMs {
                    Text(verbatim: DateText.longWithTime(Date(timeIntervalSince1970: Double(ms) / 1000)))
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, 6)
                        .glassCapsule()
                        .accessibilityIdentifier("vault.viewer.date")
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var actionBar: some View {
        GlassEffectContainer(spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.l) {
                if let item = current {
                    GlassIconButton(symbol: "pencil", label: L("edit_action")) {
                        activeVideoPlayer?.pause()
                        editing = VaultEditTarget(id: item.id, video: item.isVideo)
                    }
                    .accessibilityIdentifier("vault.viewer.edit")
                }
                GlassIconButton(symbol: "square.and.arrow.up", label: L("share")) { Task { await shareCurrent() } }
                GlassIconButton(symbol: "photo.badge.arrow.down", label: L("vault_restore")) { confirmRestore = true }
                GlassIconButton(symbol: "trash", label: L("vault_delete")) { confirmDelete = true }
                    .accessibilityIdentifier("vault.viewer.trash")
            }
        }
    }

    /// Nach dem Speichern im Tresor-Editor die neue Fassung zeigen (beim Ersetzen an Stelle des Originals).
    private func showEditResult() {
        guard let result = vault.lastEdit else { return }
        vault.lastEdit = nil
        guard vault.index.items.contains(where: { $0.id == result.newID }) else { return }
        ids.insert(result.newID, at: min(index + 1, ids.count))
        if result.replaced { ids.removeAll { $0 == result.originalID } }
        index = ids.firstIndex(of: result.newID) ?? index
        savedBanner = L(result.replaced ? "vault_edit_replaced" : "vault_edit_saved")
    }

    private func shareCurrent() async {
        guard let item = current else { return }
        guard let urls = await vault.shareFiles([item.id]) else { return }
        if urls.isEmpty { notice = L("share_failed") } else { share = VaultShare(urls: urls) }
    }

    private func deleteCurrent() {
        guard let item = current else { return }
        guard vault.moveToTrash([item.id]) else {
            notice = L("vault_error_generic")
            return
        }
        let remaining = ids.indices.filter { i in vault.index.items.contains { $0.id == ids[i] } }
        if let next = remaining.first(where: { $0 > index }) ?? remaining.last {
            index = next
        } else {
            dismiss()
        }
    }

    private func restoreCurrent(remove: Bool) async {
        guard let item = current else { return }
        let report = await vault.restore([item.id], removeFromVault: remove, app: app)
        if report.restored == 1 {
            if report.keptComplete > 0 {
                notice = L("vault_restore_done", 1) + "\n\n" + L("vault_restore_kept_complete", report.keptComplete)
            } else if remove {
                dismiss()
            } else {
                notice = L("vault_restore_done", 1)
            }
        } else {
            notice = L("vault_restore_failed", 1)
        }
    }
}

private struct VaultViewerPage: View {
    @State private var vault = VaultStore.shared
    @Environment(\.displayScale) private var scale
    let item: VaultItem
    let isCurrent: Bool
    @Binding var zoomed: Bool
    @Binding var activeVideoPlayer: AVPlayer?
    let toggleChrome: () -> Void
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    /// Entschlüsselte Videodatei dieser Seite (beim Weiterblättern gelöscht, spätestens beim Sperren).
    @State private var videoURL: URL?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let player {
                    PlayerLayerView(player: player)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(.rect)
                        .onTapGesture { toggleChrome() }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(key: "vault_kind_video"))
                        .accessibilityHint(Text(key: "viewer_controls_hint"))
                        .accessibilityAction(named: Text(key: "viewer_toggle_controls"), toggleChrome)
                        .accessibilityIdentifier("vault.viewer.video")
                        .environment(\.layoutDirection, .leftToRight)
                } else if let image {
                    ViewerPhotoSurface(image: image, size: geo.size, isCurrent: isCurrent,
                                       zoomed: $zoomed, toggleChrome: toggleChrome)
                        .accessibilityLabel(Text(key: "vault_kind_photo"))
                        .accessibilityIdentifier("vault.viewer.photo")
                } else if failed {
                    Label(L("preview_failed"), systemImage: "exclamationmark.triangle").foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: "\(item.id)-\(isCurrent)") {
                guard isCurrent, vault.phase == .unlocked else { return }
                if item.isVideo {
                    image = vault.thumbnails[item.id]
                    let url = await vault.videoFile(item)
                    guard !Task.isCancelled, vault.phase == .unlocked else {
                        if let url { vault.removeTempFiles([url]) }
                        return
                    }
                    if let url {
                        videoURL = url
                        let loaded = AVPlayer(url: url)
                        player = loaded
                        activeVideoPlayer = loaded
                    } else { failed = true }
                } else {
                    let side = max(geo.size.width, geo.size.height) * scale
                    image = vault.thumbnails[item.id]
                    let full = await vault.photo(item, maxPixel: min(4096, side * 1.5))
                    guard !Task.isCancelled, vault.phase == .unlocked else { return }
                    if let full { image = full } else if image == nil { failed = true }
                }
            }
            .onChange(of: isCurrent) { _, current in if !current { stopPlayback() } }
            .onChange(of: vault.phase) { _, phase in
                if phase != .unlocked { image = nil; stopPlayback() }
            }
            .onAppear { if isCurrent, let player { activeVideoPlayer = player } }
            .onDisappear { player?.pause() }
        }
    }

    private func stopPlayback() {
        player?.pause()
        if let player, activeVideoPlayer === player { activeVideoPlayer = nil }
        player?.replaceCurrentItem(with: nil)
        player = nil
        if let videoURL {
            vault.removeTempFiles([videoURL])
            self.videoURL = nil
        }
    }
}

/// Was im Tresor bearbeitet wird: Foto (auch Live Photo als Standbild) oder Video.
struct VaultEditTarget: Identifiable, Hashable {
    let id: String
    let video: Bool
}
