import AVFoundation
import Photos
import PhotoMaidCore
import SwiftUI

/// Ein Medium im Feed: Foto oder Video-Standbild, eingepasst (nie verzerrt, nie beschnitten), auf dunkler Bühne.
/// Meldet, ob eine Vorschau tatsächlich sichtbar ist – nur dann darf entschieden werden.
struct FeedMediaPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var scale
    @Environment(\.scenePhase) private var scenePhase
    let asset: MediaAsset
    let isTop: Bool
    let state: PreviewState
    let retry: Int
    let intentColor: Color?
    let onLoading: () -> Void
    let onResult: (Bool) -> Void
    let onRetry: () -> Void
    let onSkip: () -> Void

    @State private var image: UIImage?
    /// Nur eine kleine Vorschau liegt auf dem iPhone; das Original ist in iCloud.
    @State private var cloudOnly = false
    @State private var loadingCloud = false
    @State private var cloudRequest = 0
    @State private var videoFailed = false

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
                if isTop && (cloudOnly || videoFailed) && state == .ready { cloudBadge }
            }
            .clipShape(.rect(cornerRadius: AppRadii.card))
            .overlay {
                if let intentColor {
                    RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(intentColor, lineWidth: 3)
                }
            }
            .onChange(of: isTop) { _, top in
                if !top { cloudRequest = 0 }
            }
            .task(id: "\(asset.id)-\(retry)") { await load(size: geo.size) }
            .task(id: "\(asset.id)-\(isTop)-\(state == .ready)-\(scenePhase)") { await startVideoIfNeeded() }
            .task(id: "\(cloudRequest)-\(isTop)-\(scenePhase)") {
                guard cloudRequest > 0, isTop, scenePhase == .active, cloudOnly || videoFailed else { return }
                await loadFromCloud()
            }
        }
    }

    private var failedView: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(key: cloudOnly ? "feed_icloud_only" : "preview_failed")
                .font(AppTypography.headline).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(key: cloudOnly ? "feed_icloud_hint" : "preview_failed_hint")
                .font(AppTypography.footnote).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            if isTop {
                GlassEffectContainer(spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) {
                        if cloudOnly {
                            Button { cloudRequest += 1 } label: { Text(key: "feed_icloud_load") }
                                .buttonStyle(.glassProminent).disabled(loadingCloud)
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

    private var cloudBadge: some View {
        VStack {
            HStack {
                Spacer()
                Button { cloudRequest += 1 } label: {
                    HStack(spacing: 4) {
                        if loadingCloud { ProgressView().controlSize(.small) } else { Image(systemName: "icloud.and.arrow.down") }
                        Text(key: videoFailed ? "retry" : "feed_icloud_load").font(AppTypography.caption.weight(.semibold))
                    }
                    .padding(.horizontal, AppSpacing.s)
                    .frame(minHeight: AppSpacing.minTouch)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassCapsule(interactive: true)
                .disabled(loadingCloud)
                .padding(AppSpacing.s)
            }
            Spacer()
        }
    }

    private func load(size: CGSize) async {
        let target = PreviewPipeline.targetSize(for: size, scale: scale)
        onLoading()
        image = nil
        cloudOnly = false
        let result = await app.previews.image(for: asset.id, targetSize: target)
        guard !Task.isCancelled else { return }
        switch result {
        case .image(let img):
            image = img
            cloudOnly = false
            onResult(true)
        case .notLocallyAvailable:
            cloudOnly = true
            // Kleine lokale Vorschau zeigt das Medium ehrlich (Entscheiden möglich); Original nur auf Tipp aus iCloud.
            if let thumb = await ThumbnailLoader.shared.image(asset.id, size: CGSize(width: 600, height: 600)) {
                guard !Task.isCancelled else { return }
                image = thumb
                onResult(true)
            } else {
                guard !Task.isCancelled else { return }
                onResult(false)
            }
        case .failed:
            if asset.isVideo, let thumb = await ThumbnailLoader.shared.image(asset.id, size: CGSize(width: 600, height: 600)) {
                guard !Task.isCancelled else { return }
                image = thumb
                onResult(true)
            } else {
                guard !Task.isCancelled else { return }
                onResult(false)
            }
        }
    }

    /// Ausdrücklicher Tipp: Original aus iCloud laden (PhotoKit, nur Download aus der eigenen Mediathek).
    private func loadFromCloud() async {
        guard !loadingCloud, isTop else { return }
        loadingCloud = true
        defer { loadingCloud = false }
        if asset.isVideo {
            if case .item(let box) = await app.previews.playerItem(for: asset.id, allowNetwork: cloudOnly) {
                guard !Task.isCancelled, isTop, scenePhase == .active else { return }
                videoFailed = false
                onResult(true)
                cloudOnly = false
                app.player.load(itemID: asset.id, item: box.value, autoplay: true, duration: asset.duration)
            }
            return
        }
        let target = PreviewPipeline.targetSize(for: CGSize(width: 1200, height: 1600), scale: scale)
        if case .image(let img) = await app.previews.image(for: asset.id, targetSize: target, allowNetwork: true) {
            guard !Task.isCancelled else { return }
            image = img
            cloudOnly = false
            onResult(true)
        }
    }

    /// Video des obersten Mediums laden (stumm, ohne Netzwerk). Videoende bleibt beim Medium – keine Entscheidung.
    private func startVideoIfNeeded() async {
        guard isTop, scenePhase == .active, asset.isVideo, state == .ready, app.player.itemID != asset.id else { return }
        let result = await app.previews.playerItem(for: asset.id)
        guard !Task.isCancelled, isTop, scenePhase == .active else { return }
        switch result {
        case .item(let box):
            guard isTop else { return }
            app.player.load(itemID: asset.id, item: box.value, autoplay: true, duration: asset.duration)
        case .notLocallyAvailable:
            cloudOnly = true
        case .failed:
            videoFailed = true // Retry locally; a decode failure is not evidence of iCloud storage.
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
        .disabled(app.player.itemID != asset.id)
        .accessibilityHidden(app.player.itemID != asset.id)
    }
}
