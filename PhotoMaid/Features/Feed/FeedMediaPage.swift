import AVFoundation
import Photos
import PhotoMaidCore
import SwiftUI

/// Ein Medium im Feed: Foto oder Video-Standbild, eingepasst (nie verzerrt, nie beschnitten), auf dunkler Bühne.
/// Meldet, ob eine Vorschau tatsächlich sichtbar ist – nur dann darf entschieden werden.
struct FeedMediaPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var scale
    let asset: MediaAsset
    let isTop: Bool
    let state: PreviewState
    let retry: Int
    let intentColor: Color?
    let onResult: (Bool) -> Void
    let onRetry: () -> Void
    let onSkip: () -> Void

    @State private var image: UIImage?
    /// Volle Qualität kommt gerade aus iCloud (0…1); die schnelle Vorschau ist schon sichtbar.
    @State private var downloadProgress: Double?
    /// Video wird vorbereitet (bei iCloud-Videos gestreamt).
    @State private var videoLoading = false
    /// Nichts ließ sich anzeigen und das Original liegt in iCloud (z. B. ohne Netz).
    @State private var cloudFailed = false
    @State private var videoFailed = false
    /// Vorschau sichtbar, volle Qualität aus iCloud aber nicht geladen: „!“ unten rechts wie in der Fotos-App.
    @State private var qualityFailed = false
    /// Erneuter Versuch über „!“ (ändert nichts am Prüfstand, die Vorschau bleibt stehen).
    @State private var reload = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AppColors.stage
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityHidden(true)
                }
                if isTop, asset.isVideo, app.player.itemID == asset.id {
                    PlayerLayerView(player: app.player.player)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                switch state {
                case .loading where image == nil:
                    ProgressView().tint(.white)
                case .failed:
                    failedView
                default:
                    EmptyView()
                }
                if isTop, image != nil { cloudBadge }
            }
            .clipShape(.rect(cornerRadius: AppRadii.card))
            .overlay {
                if let intentColor {
                    RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(intentColor, lineWidth: 3)
                }
            }
            .task(id: "\(asset.id)-\(retry)-\(reload)") { await load(size: geo.size) }
            .task(id: "\(asset.id)-\(isTop)-\(state == .ready)-\(reload)") { await startVideoIfNeeded() }
        }
    }

    private var failedView: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(key: cloudFailed ? "feed_icloud_only" : "preview_failed")
                .font(AppTypography.headline).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(key: cloudFailed ? "feed_icloud_hint" : "preview_failed_hint")
                .font(AppTypography.footnote).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            if isTop {
                GlassEffectContainer(spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) {
                        if cloudFailed {
                            Button(action: onRetry) { Text(key: "feed_icloud_load") }.buttonStyle(.glassProminent)
                        } else {
                            Button(action: onRetry) { Text(key: "retry") }.buttonStyle(.glass)
                        }
                        Button(action: onSkip) { Text(key: "skip_without_decision") }.buttonStyle(.glass)
                    }
                }
            }
        }
        .padding(AppSpacing.l)
        .accessibilityElement(children: .contain)
    }

    /// Unten rechts wie in der Fotos-App: Fortschritt, solange die volle Qualität oder das Video aus iCloud kommt;
    /// „!“, wenn das nicht geklappt hat (offline, mobile Daten für Fotos aus) – Tippen lädt erneut. Entschieden
    /// werden kann die ganze Zeit mit der sichtbaren Vorschau.
    @ViewBuilder
    private var cloudBadge: some View {
        Group {
            if downloadProgress != nil || videoLoading {
                CloudProgressBadge(progress: downloadProgress)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(key: "feed_loading"))
            } else if qualityFailed || videoFailed {
                CloudRetryBadge { reload += 1 }
            }
        }
        .padding(AppSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .environment(\.layoutDirection, .leftToRight)
    }

    /// Wie die Fotos-App: sofort die Vorschau, die auf dem iPhone liegt – Entscheiden ist damit möglich –, danach
    /// automatisch die volle Qualität aus iCloud. Klappt das nicht, bleibt die Vorschau und unten rechts steht „!“.
    private func load(size: CGSize) async {
        let target = PreviewPipeline.targetSize(for: size, scale: scale)
        cloudFailed = false
        qualityFailed = false
        videoFailed = false
        var shown = false
        defer { downloadProgress = nil }
        for await update in app.previews.progressiveImage(for: asset.id, targetSize: target) {
            switch update {
            case .image(let img, let isFinal):
                image = img
                if isFinal { downloadProgress = nil }
                if !shown { shown = true; onResult(true) }
            case .progress(let p):
                downloadProgress = p < 1 ? p : nil
            case .failed(let inCloud):
                if shown { qualityFailed = inCloud } else { cloudFailed = inCloud }
            }
        }
        guard !shown, !Task.isCancelled else { return }
        // Kam gar nichts an: wenigstens die kleine Vorschau zeigen (wie die Fotos-App), „!“ lädt das Original.
        if let thumb = await ThumbnailLoader.shared.image(asset.id, size: CGSize(width: 600, height: 600)) {
            image = thumb
            qualityFailed = cloudFailed
            onResult(true)
        } else {
            onResult(false)
        }
    }

    /// Video des obersten Mediums laden (stumm; iCloud-Videos werden gestreamt). Videoende bleibt beim Medium –
    /// keine Entscheidung.
    private func startVideoIfNeeded() async {
        guard isTop, asset.isVideo, state == .ready, app.player.itemID != asset.id else { return }
        videoLoading = true
        defer { videoLoading = false }
        switch await app.previews.playerItem(for: asset.id) {
        case .item(let box):
            guard isTop else { return }
            app.player.load(itemID: asset.id, item: box.value, autoplay: true, duration: asset.duration)
        case .notLocallyAvailable, .failed:
            videoFailed = true
        }
    }
}

/// Videosteuerung unter dem Medium (Play/Pause, Ton, Position). Nie eine Entscheidung.
struct FeedVideoControls: View {
    @Environment(AppModel.self) private var app
    let asset: MediaAsset

    var body: some View {
        let player = app.player
        HStack(spacing: AppSpacing.s) {
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: player.isPlaying ? "pause" : "play"))
            Slider(value: Binding(get: { player.progress }, set: { player.seek(fraction: $0) }), in: 0...1)
                .accessibilityLabel(Text(key: "playback_position"))
                .accessibilityValue(Text(verbatim: DateText.duration(player.progress * asset.duration)))
            Text(verbatim: DateText.duration(max(0, asset.duration - player.progress * asset.duration)))
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
            Button { player.toggleMute() } label: {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: player.isMuted ? "unmute" : "mute"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.s)
        .glassCapsule()
        .environment(\.layoutDirection, .leftToRight) // Zeitleisten werden in RTL nicht gespiegelt
        .opacity(app.player.itemID == asset.id ? 1 : 0)
    }
}

/// Kleiner Kreis mit Ladefortschritt (wie in der Fotos-App unten rechts).
struct CloudProgressBadge: View {
    let progress: Double?

    var body: some View {
        ZStack {
            if let progress {
                Circle().stroke(.white.opacity(0.3), lineWidth: 2.5)
                Circle().trim(from: 0, to: max(0.03, progress))
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                ProgressView().controlSize(.small).tint(.white)
            }
        }
        .frame(width: 18, height: 18)
        .padding(9)
        .background(.black.opacity(0.35), in: .circle)
    }
}

/// „!“ unten rechts: volle Qualität aus iCloud ließ sich nicht laden. Tippen versucht es erneut. Nie eine Entscheidung.
struct CloudRetryBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.35), in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(key: "feed_icloud_load"))
        .accessibilityHint(Text(key: "feed_icloud_retry_hint"))
    }
}
