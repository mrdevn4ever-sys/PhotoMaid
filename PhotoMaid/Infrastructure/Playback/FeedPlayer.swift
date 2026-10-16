import AVFoundation
import Observation
import SwiftUI
import UIKit

/// Genau ein Player für den Feed. Ausgehende Videos werden sofort pausiert.
/// Videoende bleibt beim selben Medium und erzeugt keine Entscheidung.
@MainActor
@Observable
final class FeedPlayer {
    private(set) var itemID: String?
    private(set) var isPlaying = false
    private(set) var isMuted = true
    private(set) var progress: Double = 0
    private(set) var duration: Double = 0
    private(set) var failedItemID: String?
    var loops = false

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var preparationID: UUID?
    @ObservationIgnored private var generation = UUID()

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.duration > 0 else { return }
                self.progress = min(1, time.seconds / self.duration)
            }
        }
    }

    /// Stumm, ohne fremde Audiowiedergabe zu unterbrechen.
    private func configureSession(muted: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(muted ? .ambient : .playback, mode: .moviePlayback,
                                 options: muted ? [.mixWithOthers] : [])
        try? session.setActive(true, options: [])
    }

    /// A request belongs to this visit to a card, including when the same asset is revisited later.
    func beginLoading() -> UUID {
        stop()
        let id = UUID()
        preparationID = id
        return id
    }

    @discardableResult
    func load(itemID: String, item: AVPlayerItem, autoplay: Bool, duration: Double,
              requestID: UUID? = nil) -> Bool {
        if let requestID, preparationID != requestID { return false }
        stop()
        let expectedGeneration = generation
        self.itemID = itemID
        self.duration = duration
        progress = 0
        player.replaceCurrentItem(with: item)
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] _, change in
            guard change.newValue == .failed else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == expectedGeneration else { return }
                self.player.pause()
                self.isPlaying = false
                self.failedItemID = itemID
                if let error = self.player.currentItem?.error { Diagnostics.error(.video, "feed-player-failed", error) }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.loops { self.player.seek(to: .zero); self.player.play() } else { self.isPlaying = false }
            }
        }
        // Rückkehr/Autoplay niemals ungefragt mit Ton.
        isMuted = true
        player.isMuted = true
        if autoplay { play() }
        return true
    }

    func play() {
        guard player.currentItem != nil else { return }
        configureSession(muted: isMuted)
        if progress >= 0.999 { player.seek(to: .zero) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
        configureSession(muted: isMuted)
    }

    func seek(fraction: Double) {
        guard duration > 0 else { return }
        player.seek(to: CMTime(seconds: duration * fraction, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        progress = fraction
    }

    /// Bei Routewechsel, Werbung, Hintergrund, Gerätesperre, Verlassen des Items.
    func stop() {
        preparationID = nil
        generation = UUID()
        statusObserver = nil
        failedItemID = nil
        player.pause()
        isPlaying = false
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
        itemID = nil
        isMuted = true
        player.isMuted = true
    }
}

/// Minimaler Layer-Host für den gemeinsamen Player (keine System-Controls).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var onReadyForDisplay: (() -> Void)? = nil

    @MainActor final class Coordinator {
        var onReady: (() -> Void)?
        var observation: NSKeyValueObservation?
        init(_ onReady: (() -> Void)?) { self.onReady = onReady }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onReadyForDisplay) }

    func makeUIView(context: Context) -> PlayerHostView {
        let v = PlayerHostView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect // vollständiges Motiv, kein Beschnitt
        let coordinator = context.coordinator
        coordinator.observation = v.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak coordinator] _, change in
            guard change.newValue == true else { return }
            Task { @MainActor [weak coordinator] in coordinator?.onReady?() }
        }
        return v
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        context.coordinator.onReady = onReadyForDisplay
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: PlayerHostView, coordinator: Coordinator) {
        coordinator.observation = nil
        coordinator.onReady = nil
        uiView.playerLayer.player = nil
    }

    final class PlayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
