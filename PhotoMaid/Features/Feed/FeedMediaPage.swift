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
    let cachedPoster: UIImage?
    let retry: Int
    let intentColor: Color?
    let onLoading: (Bool) -> Void
    let onResult: (FeedPreviewResult) -> Void
    let onRetry: () -> Void
    let onSkip: () -> Void

    @State private var image: UIImage?
    private var visibleImage: UIImage? { image ?? cachedPoster }
    @State private var gifData: Data?
    /// Volle Qualität kommt gerade aus iCloud (0…1); die schnelle Vorschau ist schon sichtbar.
    @State private var downloadProgress: Double?
    /// Video wird vorbereitet (bei iCloud-Videos gestreamt).
    @State private var videoLoading = false
    /// Nichts ließ sich anzeigen und das Original liegt in iCloud (z. B. ohne Netz).
    @State private var cloudFailed = false
    @State private var videoFailed = false
    @State private var videoReady = false
    @State private var imageFinished = false
    /// Vorschau sichtbar, volle Qualität aus iCloud aber nicht geladen: „!“ unten rechts wie in der Fotos-App.
    @State private var qualityFailed = false
    /// Erneuter Versuch über „!“ (ändert nichts am Prüfstand, die Vorschau bleibt stehen).
    @State private var reload = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AppColors.stage
                if let gifData, isTop {
                    AnimatedGIFView(data: gifData)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else if let image = visibleImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityHidden(true)
                }
                if isTop, asset.isVideo, app.player.itemID == asset.id {
                    PlayerLayerView(player: app.player.player) {
                        guard isTop, app.player.itemID == asset.id, app.player.failedItemID != asset.id else { return }
                        videoReady = true
                        videoLoading = false
                        onResult(.videoFrame)
                    }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if isTop {
                    switch state {
                    case .loading where visibleImage == nil && !videoReady:
                        loadingView
                    case .failed:
                        failedView
                    default:
                        EmptyView()
                    }
                }
                if isTop, visibleImage != nil { cloudBadge }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(videoReady ? "feed.video.ready" :
                (asset.isVideo && visibleImage != nil ? "feed.video.poster" : "feed.media"))
            .accessibilityHidden(!isTop)
            .clipShape(.rect(cornerRadius: AppRadii.card))
            .overlay {
                if let intentColor {
                    RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(intentColor, lineWidth: 3)
                }
            }
            .task(id: "\(asset.id)-\(isTop)-\(retry)-\(reload)-\(Int(geo.size.width))-\(Int(geo.size.height))") { await load(size: geo.size) }
            .task(id: "\(asset.id)-gif-\(isTop)") {
                guard isTop else { gifData = nil; return }
                if let data = await GIFPlayback.data(for: asset.id), !Task.isCancelled { gifData = data }
            }
            .task(id: "\(asset.id)-\(isTop)-\(retry)-\(reload)") { await startVideoIfNeeded() }
            .onChange(of: app.player.failedItemID) { _, failed in
                guard isTop, failed == asset.id else { return }
                videoLoading = false; videoFailed = true; videoReady = false
                reportUnavailableIfFinished()
            }
        }
    }

    private var skipButton: some View {
        Button(action: onSkip) { Text(key: "skip_without_decision").padding(.vertical, AppSpacing.xs) }
            .buttonStyle(.glass)
            .accessibilityIdentifier("feed.skipUnavailable")
    }

    private var loadingView: some View {
        VStack(spacing: AppSpacing.m) {
            ProgressView().tint(.white)
            Text(key: "feed_loading").foregroundStyle(.white)
                .accessibilityIdentifier("feed.preview.loading")
            if isTop { skipButton }
        }
        .padding(AppSpacing.l)
    }

    private var failedView: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(key: cloudFailed ? "feed_icloud_only" : "preview_failed")
                .font(AppTypography.headline).foregroundStyle(.white).multilineTextAlignment(.center)
                .accessibilityIdentifier("feed.preview.failed")
            Text(key: cloudFailed ? "feed_icloud_hint" : "preview_failed_hint")
                .font(AppTypography.footnote).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            if isTop {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.xs) { retryButton; skipButton }
                    VStack(spacing: AppSpacing.s) { retryButton; skipButton }
                }
            }
        }
        .padding(AppSpacing.l)
        .accessibilityElement(children: .contain)
    }

    private var retryButton: some View {
        Button(action: onRetry) { Text(key: cloudFailed ? "feed_icloud_load" : "retry").padding(.vertical, AppSpacing.xs) }
            .buttonStyle(.glass)
            .accessibilityIdentifier("feed.retryPreview")
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
        onLoading(visibleImage != nil || (videoReady && app.player.itemID == asset.id))
        cloudFailed = false
        qualityFailed = false
        imageFinished = false
        var shown = visibleImage != nil
        defer { downloadProgress = nil }
        if asset.isVideo, !shown {
            // A small on-device poster can exist even when the display-sized image needs iCloud.
            // Show it first; neither original quality nor playback readiness is needed to decide.
            let poster = await app.previews.image(for: asset.id, targetSize: CGSize(width: 600, height: 600),
                                                  allowNetwork: false)
            guard !Task.isCancelled else { return }
            if case .image(let thumb) = poster {
                let prepared = await thumb.byPreparingForDisplay() ?? thumb
                guard !Task.isCancelled else { return }
                image = prepared
                shown = true
                onResult(.poster(prepared))
            }
        }
        for await update in app.previews.progressiveImage(for: asset.id, targetSize: target, allowNetwork: isTop) {
            guard !Task.isCancelled else { return }
            switch update {
            case .image(let img, let isFinal):
                // Abseits des Hauptthreads dekodieren: sonst dekodiert SwiftUI ein frisch aus iCloud geladenes Bild
                // beim Zeichnen – genau während der Wisch-Animation (Ruckeln bei schnellem Wischen).
                let prepared = await img.byPreparingForDisplay() ?? img
                guard !Task.isCancelled else { return }
                image = prepared
                if isFinal { downloadProgress = nil }
                shown = true
                onResult(.poster(prepared))
            case .progress(let p):
                // Fortschritt nur in sichtbaren Schritten (PhotoKit meldet sehr oft; jede Meldung zeichnet neu).
                let value: Double? = p < 1 ? p : nil
                if value == nil || downloadProgress == nil || abs((downloadProgress ?? 0) - p) >= 0.05 {
                    downloadProgress = value
                }
            case .failed(let inCloud):
                if shown { qualityFailed = true } else { cloudFailed = inCloud }
            }
        }
        guard !Task.isCancelled else { return }
        if !shown {
            // A small local poster may still exist when the requested display resolution failed.
            let fallback = await app.previews.image(for: asset.id, targetSize: CGSize(width: 600, height: 600),
                                                   allowNetwork: false)
            guard !Task.isCancelled else { return }
            if case .image(let thumb) = fallback {
                image = thumb
                qualityFailed = cloudFailed
                onResult(.poster(thumb))
            }
        }
        imageFinished = true
        reportUnavailableIfFinished()
    }

    private func reportUnavailableIfFinished() {
        guard visibleImage == nil, !videoReady, imageFinished else { return }
        // A missing video poster is not a failed video. Its first frame can make the card usable.
        if !isTop || !asset.isVideo || videoFailed { onResult(.unavailable) }
    }

    /// Start the visible video independently of its poster. Cancel/ignore results from a previous card.
    private func startVideoIfNeeded() async {
        guard isTop, asset.isVideo else {
            videoLoading = false; videoReady = false
            return
        }
        guard app.player.itemID != asset.id || app.player.failedItemID == asset.id else { return }
        videoLoading = true
        videoFailed = false
        videoReady = false
        onLoading(visibleImage != nil)
        let requestID = app.player.beginLoading()
        let result = await app.previews.playerItem(for: asset.id)
        guard !Task.isCancelled else { return }
        switch result {
        case .item(let box):
            _ = app.player.load(itemID: asset.id, item: box.value, autoplay: true, duration: asset.duration,
                                requestID: requestID)
        case .notLocallyAvailable:
            videoLoading = false; videoFailed = true; cloudFailed = true
            reportUnavailableIfFinished()
        case .failed:
            videoLoading = false; videoFailed = true
            reportUnavailableIfFinished()
        }
    }

}

/// Videosteuerung unter dem Medium (Play/Pause, Ton, Position). Nie eine Entscheidung.
struct FeedVideoControls: View {
    @Environment(AppModel.self) private var app
    let asset: MediaAsset

    var body: some View {
        let player = app.player
        let available = player.itemID == asset.id && player.failedItemID != asset.id
        HStack(spacing: AppSpacing.s) {
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: player.isPlaying ? "pause" : "play"))
            Slider(value: Binding(get: { player.progress }, set: { player.seek(fraction: $0) }), in: 0...1)
                .tint(AppColors.accent)
                .accessibilityLabel(Text(key: "playback_position"))
                .accessibilityValue(Text(verbatim: DateText.duration(player.progress * asset.duration)))
            Text(verbatim: DateText.duration(max(0, asset.duration - player.progress * asset.duration)))
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(AppColors.textSecondary)
            Button { player.toggleMute() } label: {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: player.isMuted ? "unmute" : "mute"))
        }
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, AppSpacing.s)
        .glassCapsule()
        .environment(\.layoutDirection, .leftToRight) // Zeitleisten werden in RTL nicht gespiegelt
        .opacity(available ? 1 : 0)
        .disabled(!available)
        .accessibilityHidden(!available)
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
