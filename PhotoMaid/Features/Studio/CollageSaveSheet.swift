import PhotoMaidCore
import SwiftUI

/// „Collage speichern“: Ziel (Standard: als neues Bild in Fotos), Auflösung und Dateityp. Die Originalfotos bleiben
/// immer unverändert – es entsteht nur eine neue Datei.
struct CollageSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var options: CollageSaveOptions
    let project: CollageProject
    let aspect: Float
    let confirm: () -> Void
    @State private var pickingAlbum = false

    private var output: PxSize { CollageGeometry.outputSize(project, aspect: aspect, resolution: options.resolution) }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                resolutionSection
                formatSection
                Section {
                    Label(L("collage_originals_safe"), systemImage: "checkmark.shield")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .appPage()
            .navigationTitle(L("col_save_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: confirmTitle, symbol: confirmSymbol) {
                    confirm()
                    dismiss()
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.vertical, AppSpacing.xs)
            }
            .sheet(isPresented: $pickingAlbum) {
                AlbumPickerSheet(assetIDs: []) { id, title in
                    options.destination = .album(id: id, title: title)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Ziel

    private var destinationSection: some View {
        Section {
            option(selected: options.destination == .photos, symbol: "photo.on.rectangle", title: L("collage_dest_photos"),
                   subtitle: L("collage_dest_photos_sub")) { options.destination = .photos }
            option(selected: isAlbum, symbol: "rectangle.stack.badge.plus", title: L("collage_dest_album"),
                   subtitle: albumTitle ?? L("collage_dest_album_sub")) { pickingAlbum = true }
            option(selected: options.destination == .files, symbol: "folder", title: L("files"),
                   subtitle: L("collage_dest_files_sub")) { options.destination = .files }
            option(selected: options.destination == .share, symbol: "square.and.arrow.up", title: L("share"),
                   subtitle: L("collage_dest_share_sub")) { options.destination = .share }
        } header: {
            Text(key: "collage_dest_header")
        }
    }

    private var isAlbum: Bool {
        if case .album = options.destination { return true }
        return false
    }

    private var albumTitle: String? {
        if case .album(_, let title) = options.destination { return title }
        return nil
    }

    // MARK: Auflösung

    private var resolutionSection: some View {
        Section {
            ForEach(CollageSaveOptions.resolutions, id: \.self) { value in
                option(selected: options.resolution == value, symbol: nil, title: Self.resolutionTitle(value), subtitle: nil) {
                    options.resolution = value
                }
            }
        } header: {
            Text(key: "lib_info_resolution")
        } footer: {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: L("collage_res_result", output.width, output.height)).monospacedDigit()
                Text(key: project.kind == .strip ? "collage_res_strip_hint" : "collage_res_hint")
            }
        }
    }

    static func resolutionTitle(_ value: Int) -> String {
        switch value {
        case ...1080: L("collage_res_standard")
        case ...2048: L("collage_res_high")
        default: L("collage_res_max")
        }
    }

    // MARK: Dateityp

    private var formatSection: some View {
        Section {
            Picker(L("col_format"), selection: $options.format) {
                Text(verbatim: "JPEG").tag(EditFormat.jpeg)
                Text(verbatim: "PNG").tag(EditFormat.png)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(key: "col_format")
        } footer: {
            Text(key: options.format == .png ? "col_png_hint" : "col_jpeg_hint")
        }
    }

    // MARK: Bausteine

    private var confirmTitle: String {
        switch options.destination {
        case .photos: L("collage_action_photos")
        case .album: L("collage_action_album")
        case .files: L("collage_action_files")
        case .share: L("share")
        }
    }

    private var confirmSymbol: String {
        switch options.destination {
        case .photos, .album: "square.and.arrow.down"
        case .files: "folder"
        case .share: "square.and.arrow.up"
        }
    }

    private func option(selected: Bool, symbol: String?, title: String, subtitle: String?,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppSpacing.s) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(AppColors.accent)
                    .accessibilityHidden(true)
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(AppColors.textSecondary).frame(width: 24).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).foregroundStyle(AppColors.textPrimary)
                    if let subtitle {
                        Text(verbatim: subtitle).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: AppSpacing.minTouch)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}
