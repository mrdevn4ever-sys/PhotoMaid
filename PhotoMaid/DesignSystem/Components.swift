import Photos
import SwiftUI

/// Ruhiger, warmer Grund für alle Seiten außerhalb von Medien-Bühnen.
struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [AppColors.background, AppColors.backgroundTint], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    /// Seitengrund + Listenhintergrund ausblenden (Listen liegen auf dem warmen Grund).
    func appPage() -> some View {
        scrollContentBackground(.hidden).background(AppBackground())
    }
}

/// Deckende Inhaltsfläche (kein Glas) für Karten.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = AppSpacing.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
            .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: AppSpacing.xs)
            if let actionTitle, let action {
                Button(action: action) { Text(verbatim: actionTitle).font(AppTypography.subheadline.weight(.semibold)) }
                    .frame(minHeight: AppSpacing.minTouch)
                    .foregroundStyle(AppColors.accent)
            }
        }
    }
}

/// Zeile mit Symbol, Titel, Untertitel, Wert und Chevron (Aufräumen, Einstellungen, Studio).
struct NavRow: View {
    let symbol: String
    var tint: Color = AppColors.accent
    let title: String
    var subtitle: String?
    var value: String?
    var badge: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: AppRadii.small))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(verbatim: title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                    if let badge { BadgeText(text: badge) }
                }
                if let subtitle {
                    Text(verbatim: subtitle).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AppSpacing.xs)
            if let value {
                Text(verbatim: value).font(AppTypography.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary).monospacedDigit()
            }
            if showsChevron {
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary).accessibilityHidden(true)
            }
        }
        .frame(minHeight: AppSpacing.touch)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Kleines Etikett („Pro“, „Neu“).
struct BadgeText: View {
    let text: String
    var tint: Color = AppColors.accentFill

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(tint, in: .capsule)
    }
}

/// Kennzahl mit ehrlicher Beschriftung („mind.“ bei unbekannten Größen).
struct MetricCard: View {
    let value: String
    let caption: String
    var progress: Double?
    var footnote: String?

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    Text(verbatim: value).font(AppTypography.metric).foregroundStyle(AppColors.textPrimary)
                    Text(verbatim: caption).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                if let progress { ProgressView(value: min(max(progress, 0), 1)).tint(AppColors.accent) }
                if let footnote {
                    Text(verbatim: footnote).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hinweisleiste (eingeschränkter Zugriff, unterbrochene Operation, Limit).
struct InfoBanner: View {
    let symbol: String
    var tint: Color = AppColors.accent
    var title: String?
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        SurfaceCard(padding: AppSpacing.s) {
            HStack(alignment: .top, spacing: AppSpacing.s) {
                Image(systemName: symbol).font(.title3).foregroundStyle(tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    if let title {
                        Text(verbatim: title).font(AppTypography.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    Text(verbatim: text).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle, let action {
                        Button(action: action) {
                            Text(verbatim: actionTitle).font(AppTypography.subheadline.weight(.semibold))
                        }
                        .frame(minHeight: AppSpacing.minTouch)
                        .foregroundStyle(AppColors.accent)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }
        } description: {
            if let message { Text(verbatim: message) }
        } actions: {
            if let actionTitle, let action {
                Button(action: action) { Text(verbatim: actionTitle) }.buttonStyle(.glassProminent)
            }
        }
    }
}

struct ErrorState: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label { Text(key: "error_title") } icon: { Image(systemName: "exclamationmark.triangle") }
        } description: {
            Text(verbatim: message)
        } actions: {
            if let retry { Button(action: retry) { Text(key: "retry") }.buttonStyle(.glass) }
        }
    }
}

struct LoadingState: View {
    var message: String?

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ProgressView()
            if let message {
                Text(verbatim: message).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Fortschritt einer langen Arbeit mit Abbrechen (Export, Analyse, Kopieren).
struct ProgressPanel: View {
    let title: String
    let fraction: Double?
    var detail: String?
    var cancel: (() -> Void)?

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(verbatim: title).font(AppTypography.headline)
                if let fraction {
                    ProgressView(value: min(max(fraction, 0), 1))
                } else {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                }
                if let detail {
                    Text(verbatim: detail).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                }
                if let cancel {
                    Button(role: .cancel, action: cancel) { Text(key: "cancel") }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Umschalter mit Erklärung (Einstellungen).
struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                if let subtitle {
                    Text(verbatim: subtitle).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .frame(minHeight: AppSpacing.minTouch)
    }
}

/// Vorschaubild eines PhotoKit-Assets (quadratisch beschnitten, nie verzerrt). Lädt nur lokal Vorhandenes.
struct AssetThumbnail: View {
    let assetID: String
    var side: CGFloat = 80
    var cornerRadius: CGFloat = AppRadii.thumb
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(AppColors.backgroundTint)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(AppColors.textSecondary).accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .task(id: assetID) {
            image = nil
            failed = false
            let size = CGSize(width: side * scale, height: side * scale)
            if let img = await ThumbnailLoader.shared.image(assetID, size: size) { image = img } else { failed = true }
        }
    }
}

/// Flexible Variante für Raster (füllt die vorgegebene Zelle).
struct AssetCell: View {
    let assetID: String
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(AppColors.backgroundTint)
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .task(id: assetID) {
                let s = CGSize(width: geo.size.width * scale, height: geo.size.height * scale)
                image = await ThumbnailLoader.shared.image(assetID, size: s)
            }
        }
    }
}

/// Gemeinsamer Lader für kleine Vorschauen (schnelles Format; fehlt die kleine Fassung, aus iCloud).
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 600 }

    func image(_ assetID: String, size: CGSize) async -> UIImage? {
        let key = "\(assetID)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return nil }
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .fast
        let box = UncheckedBox(manager)
        let result: UncheckedBox<UIImage?> = await withCheckedContinuation { cont in
            box.value.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: o) { @Sendable img, _ in
                cont.resume(returning: UncheckedBox(img))
            }
        }
        if let img = result.value { cache.setObject(img, forKey: key) }
        return result.value
    }

    func clear() { cache.removeAllObjects() }
}

/// Kurze Meldung unten (Fehler, „Gespeichert“, Rückgängig). Verschwindet von selbst; VoiceOver liest sie vor.
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var isError = false
    var actionTitle: String?
    var action: (@MainActor () -> Void)?

    static func == (a: ToastMessage, b: ToastMessage) -> Bool { a.id == b.id }
}

struct ToastView: View {
    let toast: ToastMessage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? AppColors.cleanup : AppColors.success)
                .accessibilityHidden(true)
            Text(verbatim: toast.text).font(AppTypography.subheadline).foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppSpacing.xs)
            if let title = toast.actionTitle, let action = toast.action {
                Button { action(); dismiss() } label: { Text(verbatim: title).font(AppTypography.subheadline.weight(.semibold)) }
                    .frame(minHeight: AppSpacing.minTouch)
                    .foregroundStyle(AppColors.accent)
            }
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, AppSpacing.xs)
        .frame(minHeight: AppSpacing.touch)
        .glassPanel(radius: AppRadii.card)
        .padding(.horizontal, AppSpacing.pageMargin)
        .accessibilityElement(children: .combine)
    }
}
