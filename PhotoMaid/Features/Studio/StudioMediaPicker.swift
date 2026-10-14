import PhotoMaidCore
import SwiftUI

struct StudioMediaPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let allowsVideos: Bool
    let limit: Int
    let initial: Set<String>
    let completion: ([String]) -> Void
    @State private var selection: Set<String>

    init(allowsVideos: Bool, limit: Int, initial: Set<String> = [], completion: @escaping ([String]) -> Void) {
        self.allowsVideos = allowsVideos
        self.limit = limit
        self.initial = initial
        self.completion = completion
        _selection = State(initialValue: initial)
    }

    private var media: [MediaAsset] {
        app.visibleMedia.filter { allowsVideos || !$0.isVideo }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(media) { asset in
                        let selected = selection.contains(asset.id)
                        Button {
                            if selected {
                                selection.remove(asset.id)
                            } else if selection.count < limit {
                                selection.insert(asset.id)
                            } else {
                                app.showError(L("studio_max_selection", limit))
                            }
                        } label: {
                            // Quadratische Zelle (.fit, nicht .fill) mit genau dieser Trefferfläche: ein Tipp wählt nie
                            // die Nachbarzelle (AssetCell nimmt mit dem Bildüberstand keine Tipps an).
                            AssetCell(assetID: asset.id)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selected ? AppColors.accentFill : .white)
                                        .background(Circle().fill(.black.opacity(0.25)))
                                        .padding(4)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if asset.isVideo {
                                        Text(verbatim: DateText.duration(asset.duration)).monospacedDigit()
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .shadow(radius: 2)
                                            .padding(4)
                                    }
                                }
                                .overlay { if selected { Rectangle().fill(.white.opacity(0.18)).allowsHitTesting(false) } }
                                .clipped()
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: MediaInfoLine.describe(asset)))
                        .accessibilityIdentifier("picker.media")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .appPage()
            .navigationTitle(L("tools_pick"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("done")) {
                        completion(media.map(\.id).filter(selection.contains))
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }
}
