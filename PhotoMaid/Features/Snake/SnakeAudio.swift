import AVFoundation

@MainActor
final class SnakeAudio {
    enum Cue: String, CaseIterable { case collect, tap, new_record, turn, game_over, photo_added }
    private var players: [Cue: AVAudioPlayer] = [:]
    private var prepared = false
    func prepare() {
        // Ambient respects Silent Mode and other apps' music. No microphone or recording session.
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient || session.mode != .default {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
        guard !prepared else { return }
        prepared = true
        for cue in Cue.allCases {
            guard let url = Bundle.main.url(forResource: "sfx_" + cue.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = 0.36; player.prepareToPlay(); players[cue] = player
        }
    }
    func play(_ cue: Cue, enabled: Bool) {
        guard enabled else { return }
        prepare()
        guard let player = players[cue] else { return }
        player.currentTime = 0; player.play()
    }
    func stop() { for player in players.values { player.stop() } }
}
