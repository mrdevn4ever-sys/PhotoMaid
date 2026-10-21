import Photos
import SwiftUI

/// Ruhiger deckender Grund; Glas bleibt schwebenden Bedienelementen vorbehalten.
struct AppBackground: View {
    var body: some View {
        AppColors.background
            .ignoresSafeArea()
    }
}

extension View {
    /// Einheitlicher Seitengrund statt eigener Hintergründe je Feature.
    func appPage() -> some View {
        scrollContentBackground(.hidden).background(AppBackground())
    }
}

/// Seitenkopf des Artefakts: Titel 40 pt (Bricolage 800, Laufweite −0,02 em) in der Farbe der Seite, darunter
/// eine Zeile Erklärung (15 pt, gedämpft).
struct PageHeading: View {
    let title: String
    var color: Color = AppColors.textPrimary
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).font(AppTypography.largeTitle).tracking(-0.8).foregroundStyle(color)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(verbatim: subtitle).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: AppSpacing.xs)
            if let actionTitle, let action {
                Button(action: action) { Text(verbatim: actionTitle).font(PMFont.text(.semibold, 15, relativeTo: .subheadline)) }
                    .frame(minHeight: AppSpacing.minTouch)
                    .foregroundStyle(AppColors.accent)
            }
        }
    }
}

/// Zeile mit Symbol, Titel, Untertitel, Wert und Chevron (Aufräumen, Einstellungen, Studio).
struct NavRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
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
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(PMTile.background(for: tint), in: .rect(cornerRadius: AppRadii.small))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(verbatim: title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge, !typeSize.isAccessibilitySize { BadgeText(text: badge) }
                }
                if let subtitle {
                    Text(verbatim: subtitle).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if typeSize.isAccessibilitySize {
                    if let value {
                        Text(verbatim: value).font(AppTypography.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let badge { BadgeText(text: badge) }
                }
            }
            Spacer(minLength: AppSpacing.xs)
            if let value, !typeSize.isAccessibilitySize {
                Text(verbatim: value).font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary).monospacedDigit()
            }
            if showsChevron {
                PMIcon(.chevronRight, size: 18).foregroundStyle(AppColors.textTertiary)
                    .flipsForRightToLeftLayoutDirection(true)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: AppSpacing.touch)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Dunkle Symbolkachel passend zur Tönung (Artefakt: #2A2418 Bernstein, #33201A Papierkorb, #262236 Später …).
enum PMTile {
    static func background(for tint: Color) -> Color {
        if tint == AppColors.cleanup || tint == AppColors.cleanupFill { return AppColors.tileCleanup }
        if tint == AppColors.later { return AppColors.tileLater }
        if tint == AppColors.keep { return AppColors.tileKeep }
        if tint == AppColors.success { return AppColors.tileGreen }
        if tint == AppColors.accent { return AppColors.tileAmber }
        return tint.opacity(0.12)
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
            .foregroundStyle(AppColors.onAccent)
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
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                        metricValue
                        metricCaption
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        metricValue
                        metricCaption
                    }
                }
                if let progress { ProgressView(value: min(max(progress, 0), 1)).tint(AppColors.accent) }
                if let footnote {
                    Text(verbatim: footnote).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var metricValue: some View {
        Text(verbatim: value).font(AppTypography.metric).foregroundStyle(AppColors.textPrimary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var metricCaption: some View {
        Text(verbatim: caption).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
        VStack(spacing: AppSpacing.s) {
            Image(systemName: symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(AppColors.textTertiary)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(verbatim: title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                if let message {
                    Text(verbatim: message).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) { Text(verbatim: actionTitle) }.buttonStyle(.pmProminent).padding(.top, 4)
            }
        }
        .padding(.vertical, 40).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: AppRadii.card)
            .strokeBorder(AppColors.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .padding(.horizontal, AppSpacing.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
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
            if let retry { Button(action: retry) { Text(key: "retry") }.buttonStyle(.pmBordered) }
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
                        .buttonStyle(.pmBordered).buttonBorderShape(.capsule)
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

/// Vorschaubild eines PhotoKit-Assets (quadratisch beschnitten, nie verzerrt). Bei Bedarf aus iCloud geladen.
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
                // Überstand des beschnittenen Bildes nimmt keine Tipps an (siehe AssetCell).
                Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(AppColors.textSecondary).accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .contentShape(.rect(cornerRadius: cornerRadius))
        .task(id: assetID) {
            image = nil
            failed = false
            let size = CGSize(width: side * scale, height: side * scale)
            let img = await ThumbnailLoader.shared.image(assetID, size: size)
            guard !Task.isCancelled else { return }
            if let img { image = img } else { failed = true }
        }
    }
}

/// Flexible Variante für Raster (füllt die vorgegebene Zelle).
///
/// Trefferfläche = genau die Zelle: `.clipped()` beschneidet nur die Darstellung, nicht das Hit-Testing. Ein
/// hochformatiges Bild (3:4, 9:16) ragt mit `scaledToFill` unsichtbar über die Zelle hinaus; weil spätere Zellen über
/// früheren liegen, fing der Überstand der Zelle darunter Tipps auf den unteren Teil der getippten Zelle ab
/// („wählt das Bild darunter aus“). Deshalb nimmt das Bild selbst keine Berührungen an und die Form ist das Rechteck.
struct AssetCell: View {
    let assetID: String
    /// Ganzes Bild im Seitenverhältnis zeigen (einpassen) statt quadratisch zu beschneiden. Nie verzerrt.
    var fit = false
    var allowNetwork = true
    var requiresGameAccess = false
    @Environment(\.displayScale) private var scale
    @State private var loaded: Loaded?
    @State private var failedID: String?
    @State private var size: CGSize = .zero

    private struct Loaded {
        let id: String
        let image: UIImage
    }

    /// Quantize pixel requests: fractional layout changes must not cancel an
    /// in-flight PhotoKit request and briefly blank the same cell.
    private struct LoadKey: Equatable {
        let assetID: String
        let width: Int
        let height: Int
    }

    private static func bucket(_ pixels: CGFloat) -> Int {
        guard pixels.isFinite, pixels > 0 else { return 0 }
        return min(1024, max(64, Int((pixels / 64).rounded(.up)) * 64))
    }

    private var pixelSize: CGSize {
        CGSize(width: Self.bucket(size.width * scale), height: Self.bucket(size.height * scale))
    }

    private var permitted: Bool {
        !requiresGameAccess || (PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead &&
            VaultConcealment.shared.analysisReady && !VaultConcealment.shared.isConcealed(assetID))
    }
    private var image: UIImage? { permitted && loaded?.id == assetID ? loaded?.image : nil }

    var body: some View {
        Rectangle()
            .fill(AppColors.backgroundTint)
            .overlay {
                if let image, fit {
                    Image(uiImage: image).resizable().scaledToFit().allowsHitTesting(false)
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
                } else {
                    placeholder
                }
            }
            .clipped()
            .contentShape(.rect)
            .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { size = $0 }
            .task(id: LoadKey(assetID: assetID, width: Int(pixelSize.width),
                              height: Int(pixelSize.height))) {
                await load()
            }
            .onDisappear { if requiresGameAccess { loaded = nil } }
    }

    /// Platzhalter statt leerer Fläche: dezentes Symbol beim Laden, deutliches bei einem Fehler.
    private var placeholder: some View {
        let failed = failedID == assetID
        return Image(systemName: failed ? "photo.badge.exclamationmark" : "photo")
            .font(.body)
            .foregroundStyle(AppColors.textSecondary.opacity(failed ? 0.8 : 0.35))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func load() async {
        guard size.width >= 1, size.height >= 1, permitted else { return }
        let id = assetID
        let img = await ThumbnailLoader.shared.image(id, size: pixelSize, allowNetwork: allowNetwork,
                                                    requiresGameAccess: requiresGameAccess)
        // Abgebrochen (aus dem Bild gescrollt) oder inzwischen ein anderes Medium: nichts anzeigen, nicht als Fehler werten.
        guard !Task.isCancelled, id == assetID else { return }
        guard permitted else { loaded = nil; return }
        if let img {
            loaded = Loaded(id: id, image: img)
            failedID = nil
        } else if image == nil {
            failedID = id
        }
    }
}

/// Gemeinsamer Lader für kleine Vorschaubilder: lokale PhotoKit-Previews
/// immer zuerst und ohne Netz, iCloud erst wenn lokal tatsächlich nichts
/// lieferbar ist. Kein Originaldownload für bereits sichtbare Kacheln.
/// Cancellation beim Scrollen bricht die Requests ab.
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 350
        // NSCache evicts automatically when memory is scarce. Use a byte budget
        // in addition to count, otherwise hundreds of large thumbnails can
        // evict visible cells and cause a black/empty-grid reload storm.
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(_ assetID: String, size: CGSize, allowNetwork: Bool = true,
               requiresGameAccess: Bool = false) async -> UIImage? {
        func permitted() -> Bool {
            !requiresGameAccess || (PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead &&
                VaultConcealment.shared.analysisReady && !VaultConcealment.shared.isConcealed(assetID))
        }
        guard permitted() else { return nil }
        guard size.width >= 1, size.height >= 1, !VaultConcealment.shared.isConcealed(assetID) else { return nil }
        if !allowNetwork {
            guard PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead,
                  VaultConcealment.shared.analysisReady else { return nil }
        }
        let key = "\(assetID)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard !Task.isCancelled,
              let asset = PhotoLibraryService.phAsset(assetID) else { return nil } // Tresor-Medien: nie

        // A remote high-quality request for EVERY onscreen cell can cause the
        // entire grid to go blank while the requests wait for iCloud.
        // The local fast result is enough for a small scrolling thumbnail;
        // only genuinely unavailable assets need a remote fallback.
        if let local = await request(asset, size: size, network: false, mode: .fastFormat) {
            // Inzwischen in den Tresor gelegt: verspätetes Ergebnis verwerfen.
            guard !Task.isCancelled, permitted(), !VaultConcealment.shared.isConcealed(assetID) else { return nil }
            store(local, key: key, size: size)
            return local
        }
        guard allowNetwork, !Task.isCancelled, permitted() else { return nil }
        if let remote = await request(asset, size: size, network: true, mode: .highQualityFormat) {
            guard !Task.isCancelled, permitted(), !VaultConcealment.shared.isConcealed(assetID) else { return nil }
            store(remote, key: key, size: size)
            return remote
        }
        return nil
    }

    private func store(_ image: UIImage, key: NSString, size: CGSize) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? Int(max(1, size.width) * max(1, size.height) * 4)
        cache.setObject(image, forKey: key, cost: cost)
    }

    private func request(_ asset: PHAsset, size: CGSize, network: Bool,
                         mode: PHImageRequestOptionsDeliveryMode) async -> UIImage? {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = network
        o.deliveryMode = mode // genau ein Callback
        o.resizeMode = .fast
        let box = ThumbnailRequestBox()
        let managerBox = UncheckedBox(manager)
        let result: UncheckedBox<UIImage?> = await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<UncheckedBox<UIImage?>, Never>) in
                let id = manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill,
                                              options: o) { @Sendable img, _ in
                    cont.resume(returning: UncheckedBox(img))
                }
                box.set(id)
            }
        } onCancel: {
            if let id = box.id { managerBox.value.cancelImageRequest(id) }
        }
        return result.value
    }

    func clear() { cache.removeAllObjects() }
}

/// Kennung eines laufenden Vorschau-Requests, damit ein Abbruch ihn beenden kann.
private final class ThumbnailRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: PHImageRequestID?
    var id: PHImageRequestID? { lock.withLock { _id } }
    func set(_ id: PHImageRequestID) { lock.withLock { _id = id } }
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
