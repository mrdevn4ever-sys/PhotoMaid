import QuickLook
import SwiftUI

struct ReceivedView: View {
    let urls: [URL]
    @State private var preview: URL?
    @State private var accessed: URL?
    @State private var visibleURLs: [URL] = []
    var body: some View {
        List(visibleURLs, id: \.self) { url in
            Button {
                guard FileScanner.isPublic(url) else { return }
                if url.startAccessingSecurityScopedResource() { accessed = url }
                preview = url
            } label: { NavRow(symbol: "doc", title: url.lastPathComponent) }.buttonStyle(.plain)
        }
        .appPage().navigationTitle(L("folder_open")).quickLookPreview($preview)
        .onAppear { visibleURLs = urls.filter(FileScanner.isPublic) }
        .onChange(of: urls) { _, value in visibleURLs = value.filter(FileScanner.isPublic) }
        .onChange(of: preview) { _, value in
            if value == nil { accessed?.stopAccessingSecurityScopedResource(); accessed = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .analysisVisibilityChanged)) { _ in
            visibleURLs = urls.filter(FileScanner.isPublic)
            if let value = preview, !FileScanner.isPublic(value) { preview = nil }
        }
        .onDisappear { accessed?.stopAccessingSecurityScopedResource(); accessed = nil }
    }
}
