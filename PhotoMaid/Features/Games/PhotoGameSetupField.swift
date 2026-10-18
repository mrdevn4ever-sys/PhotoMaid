import SwiftUI

/// A visible label above each choice also leaves room for long translations and large text.
struct PhotoGameSetupField<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

struct PhotoGameCloudOption: View {
    @Binding var allowsCloud: Bool
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(L("memory_cloud"), isOn: $allowsCloud)
                .font(.subheadline).tint(AppColors.success)
                .accessibilityIdentifier(identifier)
            Text(key: "game_setup_cloud_note")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
