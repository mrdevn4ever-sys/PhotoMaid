import AVKit
import PhotoMaidCore
import SwiftUI

/// Ansicht im Tresor: Fotos eingepasst (nie verzerrt), Videos aus einer geschützten Temp-Datei. Wischen blättert;
/// Teilen, Zurück in Fotos und Löschen unten. Nichts davon ist eine Entscheidung im Sinne des Prüfstands.
struct VaultViewer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    let ids: [String]
    @State private var index: Int
    @State private var share: VaultShare?
    @State private var confirmDelete = false
    @State private var confirmRestore = false
    @State private var notice: String?

    init(ids: [String], start: Int) {
        self.ids = ids
        _index = State(initialValue: start)
    }

    private var current: VaultItem? {
        guard ids.indices.contains(index) else { return nil }
        return vault.index.items.first { $0.id == ids[index] }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(ids.enumerated()), id: \.offset) { i, id in
                    if let item = vault.index.items.first(where: { $0.id == id }) {
                        VaultViewerPage(item: item, isCurrent: i == index).tag(i)
                    } else {
                        Color.black.tag(i)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                GlassIconButton(symbol: "xmark", label: L("vault_close_viewer")) { dismiss() }
                Spacer()
                if let item = current, let ms = item.creationMs {
                    Text(verbatim: DateText.longWithTime(Date(timeIntervalSince1970: Double(ms) / 1000)))
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, 6)
                        .glassCapsule()
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: AppSpacing.l) {
                GlassIconButton(symbol: "square.and.arrow.up", label: L("share")) { Task { await shareCurrent() } }
                GlassIconButton(symbol: "photo.badge.arrow.down", label: L("vault_restore")) { confirmRestore = true }
                GlassIconButton(symbol: "trash", label: L("vault_delete")) { confirmDelete = true }
            }
            .padding(.bottom, AppSpacing.l)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $share) { item in
            ShareSheet(items: item.urls) { vault.removeTempFiles(item.urls) }
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
        .onChange(of: vault.phase) { _, phase in if phase != .unlocked { dismiss() } }
    }

    private func shareCurrent() async {
        guard let item = current else { return }
        let urls = await vault.shareFiles([item.id])
        if urls.isEmpty { notice = L("share_failed") } else { share = VaultShare(urls: urls) }
    }

    private func deleteCurrent() {
        guard let item = current else { return }
        guard vault.delete([item.id], app: app) else {
            notice = L("vault_error_generic")
            return
        }
        if vault.index.items.isEmpty || !ids.contains(where: { id in vault.index.items.contains { $0.id == id } }) { dismiss() }
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
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                        .environment(\.layoutDirection, .leftToRight)
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityLabel(Text(key: "vault_kind_photo"))
                } else if failed {
                    Label(L("preview_failed"), systemImage: "exclamationmark.triangle").foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: item.id) {
                if item.isVideo {
                    image = vault.thumbnails[item.id]
                    if let url = await vault.videoFile(item) { player = AVPlayer(url: url) } else { failed = true }
                } else {
                    let side = max(geo.size.width, geo.size.height) * scale
                    image = vault.thumbnails[item.id]
                    if let full = await vault.photo(item, maxPixel: min(4096, side * 1.5)) { image = full } else if image == nil { failed = true }
                }
            }
            .onChange(of: isCurrent) { _, current in if !current { player?.pause() } }
            .onDisappear { player?.pause() }
        }
    }
}
