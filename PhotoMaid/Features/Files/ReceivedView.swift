import QuickLook
import SwiftUI

struct ReceivedView: View {
    let urls: [URL]
    @State private var preview: URL?
    @State private var accessed: URL?
    var body: some View {
        List(urls, id: \.self) { url in
            Button {
                if url.startAccessingSecurityScopedResource() { accessed = url }
                preview = url
            } label: { NavRow(symbol: "doc", title: url.lastPathComponent) }.buttonStyle(.plain)
        }
        .appPage().navigationTitle(L("folder_open")).quickLookPreview($preview)
        .onChange(of: preview) { _, value in
            if value == nil { accessed?.stopAccessingSecurityScopedResource(); accessed = nil }
        }
    }
}
