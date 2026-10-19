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
    var loops = false

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.duration > 0, time.seconds.isFinite else { return }
                self.progress = min(1, max(0, time.seconds / self.duration))
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

    func load(itemID: String, item: AVPlayerItem, autoplay: Bool, duration: Double) {
        stop()
        self.itemID = itemID
        self.duration = duration.isFinite ? max(0, duration) : 0
        progress = 0
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] notification in
            guard let ended = notification.object as? AVPlayerItem else { return }
            let endedID = ObjectIdentifier(ended)
            MainActor.assumeIsolated {
                guard let self, let current = self.player.currentItem,
                      ObjectIdentifier(current) == endedID else { return }
                self.progress = 1
                if self.loops { self.player.seek(to: .zero); self.player.play() } else { self.isPlaying = false }
            }
        }
        // Rückkehr/Autoplay niemals ungefragt mit Ton.
        isMuted = true
        player.isMuted = true
        if autoplay { play() }
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
        guard duration > 0, fraction.isFinite, player.currentItem != nil else { return }
        let fraction = min(1, max(0, fraction))
        player.seek(to: CMTime(seconds: duration * fraction, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        progress = fraction
    }

    /// Bei Routewechsel, Werbung, Hintergrund, Gerätesperre, Verlassen des Items.
    func stop() {
        player.pause()
        isPlaying = false
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
        itemID = nil
        progress = 0
        duration = 0
        isMuted = true
        player.isMuted = true
    }
}

/// Minimaler Layer-Host für den gemeinsamen Player (keine System-Controls).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let v = PlayerHostView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect // vollständiges Motiv, kein Beschnitt
        return v
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
