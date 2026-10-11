import AVFoundation
import PhotoMaidCore
import SwiftUI

/// PhotoMaid's only video transport surface inside the full-screen viewer.
/// AVPlayerLayer renders frames without the system VideoPlayer chrome, so the
/// scrubber and PhotoMaid actions never compete for the same screen area.
struct ViewerVideoControls: View {
    let player: AVPlayer
    let duration: TimeInterval

    @State private var seconds: Double = 0
    @State private var seeking = false
    @State private var playing = false

    private var maximum: Double { duration.isFinite && duration > 0 ? duration : 1 }

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.s) {
                Text(verbatim: DateText.duration(seconds))
                    .font(AppTypography.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 37, alignment: .leading)

                Slider(value: Binding(get: { min(max(seconds, 0), maximum) },
                                      set: { seconds = $0 }),
                       in: 0...maximum, onEditingChanged: { editing in
                    seeking = editing
                    if !editing { seek(seconds) }
                })
                .tint(.white)
                .accessibilityLabel(Text(key: "playback_position"))

                Text(verbatim: DateText.duration(duration))
                    .font(AppTypography.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 37, alignment: .trailing)
            }

            HStack(spacing: AppSpacing.xl) {
                transport("gobackward.10", description: "−10 s") { seek(seconds - 10) }
                transport(playing ? "pause.fill" : "play.fill",
                          description: L(playing ? "pause" : "play")) {
                    if playing {
                        player.pause()
                    } else {
                        if seconds >= maximum - 0.1 { seek(0) }
                        player.play()
                    }
                    playing = player.rate > 0
                }
                transport("goforward.10", description: "+10 s") { seek(seconds + 10) }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, AppSpacing.xs)
        .background(.black.opacity(0.82), in: .rect(cornerRadius: AppRadii.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadii.card)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .task {
            // Cancellation is automatic when changing pages or hiding this dock.
            // No persistent timer observer, unsafe executor assumption or busy loop.
            while !Task.isCancelled {
                let t = player.currentTime().seconds
                if !seeking, t.isFinite { seconds = min(max(t, 0), maximum) }
                playing = player.rate > 0
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
            }
        }
    }

    private func seek(_ target: Double) {
        let bounded = min(max(target, 0), maximum)
        seconds = bounded
        player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func transport(_ symbol: String, description: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: AppSpacing.touch, height: AppSpacing.touch)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: description))
    }
}
