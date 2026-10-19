import AVKit
import ImageIO
import PDFKit
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

/// Deliberately not Quick Look: unsupported documents can be stored without opening a public share/open-in UI.
struct VaultDocumentPreview: View {
    let document: VaultDocument
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    @State private var url: URL?
    @State private var image: UIImage?
    @State private var pdf: PDFDocument?
    @State private var player: AVPlayer?
    @State private var text: String?
    @State private var loading = true
    @State private var error: String?
    @State private var share: VaultShare?

    private var type: UTType { UTType(document.typeIdentifier) ?? .data }
    private var supported: Bool {
        type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .plainText)
    }
    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView() }
                else if let pdf { VaultPDFContent(document: pdf) }
                else if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image).resizable().scaledToFit().containerRelativeFrame(.horizontal)
                    }
                } else if let player {
                    VideoPlayer(player: player).accessibilityLabel(document.name)
                } else if let text {
                    ScrollView { Text(verbatim: text).frame(maxWidth: .infinity, alignment: .leading).padding() }
                } else {
                    ContentUnavailableView(L("vault2_no_preview"), systemImage: "doc", description: Text(L("vault2_no_preview_text")))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(document.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L("done")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("share"), systemImage: "square.and.arrow.up") {
                        Task {
                            do { share = VaultShare(urls: try await vault.shareDocuments([document.id])) }
                            catch is CancellationError {} catch { self.error = VaultWorkspaceMessages.error(error) }
                        }
                    }
                }
            }
            .task(id: document.id) {
                loading = true; defer { loading = false }
                guard supported else { return }
                do {
                    let activeLease = try vault.requireLease()
                    let value = try await vault.documentPreview(document.id)
                    guard vault.accepts(activeLease), !Task.isCancelled else { vault.removeTempFiles([value]); return }
                    url = value
                    if type.conforms(to: .pdf) { pdf = PDFDocument(url: value) }
                    else if type.conforms(to: .image) {
                        // Decode a bounded image, not a potentially gigapixel original.
                        let imageURL = value
                        let loaded = await Task.detached(priority: .userInitiated) {
                            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return nil as UIImage? }
                            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096]
                            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
                        }.value
                        guard vault.accepts(activeLease), !Task.isCancelled else { return }
                        image = loaded
                    } else if type.conforms(to: .audio) || type.conforms(to: .movie) { player = AVPlayer(url: value) }
                    else if type.conforms(to: .plainText), document.byteCount <= 2 << 20 {
                        text = try String(contentsOf: value, encoding: .utf8)
                    }
                } catch is CancellationError {} catch { self.error = VaultWorkspaceMessages.error(error) }
            }
            .sheet(item: $share) { value in ShareSheet(items: value.urls) { vault.removeTempFiles(value.urls) } }
            .vaultWorkspaceError($error)
            .onChange(of: vault.phase) { _, value in if value != .unlocked { clear(); dismiss() } }
            .onDisappear { clear() }
        }
    }
    private func clear() {
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil; image = nil; pdf = nil; text = nil
        if let url { vault.removeTempFiles([url]) }; url = nil
    }
}

private struct VaultPDFContent: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> VaultPrivatePDFView {
        let view = VaultPrivatePDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = document; return view
    }
    func updateUIView(_ view: VaultPrivatePDFView, context: Context) { if view.document !== document { view.document = document } }
    static func dismantleUIView(_ view: VaultPrivatePDFView, coordinator: ()) { view.document = nil }
}
private final class VaultPrivatePDFView: PDFView {
    override func perform(_ action: PDFAction) {
        // Only local page navigation; no URL, external document, print or executable action.
        if action is PDFActionGoTo { super.perform(action) }
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}
