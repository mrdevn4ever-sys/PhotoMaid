import AVKit
import PhotoMaidCore
import SwiftUI

/// Diashow: nur Ansehen, nie eine Entscheidung. Bildschirm bleibt an, Videos stumm (abschaltbar).
struct SlideshowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ids: [String]
    @State private var order: [String] = []
    @State private var index = 0
    @State private var playing = true
    @State private var chrome = false
    @State private var settingsOpen = false
    @State private var finished = false
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if order.isEmpty {
                Text(key: "slideshow_empty").foregroundStyle(.white)
            } else if finished {
                VStack(spacing: AppSpacing.m) {
                    Text(key: "slideshow_end").font(AppTypography.title).foregroundStyle(.white)
                    Button(L("slideshow_again")) { index = 0; finished = false; playing = true }.buttonStyle(.glassProminent)
                    Button(L("close")) { dismiss() }.buttonStyle(.glass)
                }
            } else {
                ZStack {
                    if let player {
                        VideoPlayer(player: player).disabled(true)
                    } else {
                        LargePreview(assetID: order[index]).id(order[index])
                            .transition(app.settings.slideshow.transition == .fade && !reduceMotion ? .opacity : .identity)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: index)
                .onTapGesture { chrome.toggle() }
            }
            if chrome && !finished { controls }
        }
        .keepsScreenAwake(true)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            order = Slideshow.order(ids.compactMap { app.asset($0) }, settings: app.settings.slideshow,
                                    seed: UInt64.random(in: 1...UInt64.max), album: { _ in nil }, date: \.creationDate).map(\.id)
        }
        .onDisappear {
            player?.pause()
        }
        .task(id: "\(index)-\(playing)-\(finished)") { await advanceLoop() }
        .sheet(isPresented: $settingsOpen) { SlideshowSettingsSheet() }
    }

    private var controls: some View {
        VStack {
            HStack {
                GlassIconButton(symbol: "xmark", label: L("close")) { dismiss() }
                Spacer()
                GlassIconButton(symbol: "slider.horizontal.3", label: L("slideshow_settings")) { settingsOpen = true; playing = false }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            Spacer()
            GlassEffectContainer(spacing: AppSpacing.s) {
                HStack(spacing: AppSpacing.s) {
                    GlassIconButton(symbol: "backward.fill", label: L("slideshow_prev")) { step(-1) }
                    GlassIconButton(symbol: playing ? "pause.fill" : "play.fill", label: L(playing ? "slideshow_pause" : "play"),
                                    prominent: true) { playing.toggle() }
                    GlassIconButton(symbol: "forward.fill", label: L("slideshow_next")) { step(1) }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.bottom, AppSpacing.l)
        }
    }

    private func step(_ d: Int) {
        player?.pause()
        player = nil
        let n = index + d
        if n >= order.count {
            if app.settings.slideshow.loop { index = 0 } else { finished = true }
        } else {
            index = max(0, n)
        }
    }

    private func advanceLoop() async {
        guard playing, !finished, order.indices.contains(index), let a = app.asset(order[index]) else { return }
        if a.isVideo && app.settings.slideshow.playVideos {
            if case .item(let box) = await app.previews.playerItem(for: a.id) {
                let p = AVPlayer(playerItem: box.value)
                p.isMuted = true
                player = p
                p.play()
                try? await Task.sleep(for: .seconds(max(1, a.duration)))
            }
        } else if a.isVideo {
            step(1)
            return
        } else {
            try? await Task.sleep(for: .seconds(app.settings.slideshow.seconds))
        }
        guard !Task.isCancelled, playing else { return }
        step(1)
    }
}

struct SlideshowSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                let s = app.settings.slideshow
                Picker(L("slideshow_order"), selection: binding(\.order)) {
                    Text(key: "slideshow_order_chrono").tag(SlideshowOrder.chronological)
                    Text(key: "slideshow_order_random").tag(SlideshowOrder.random)
                }
                Picker(L("slideshow_duration"), selection: binding(\.seconds)) {
                    ForEach(SlideshowSettings.secondsChoices, id: \.self) { Text(verbatim: L("slideshow_seconds", $0)).tag($0) }
                }
                Picker(L("slideshow_transition"), selection: binding(\.transition)) {
                    Text(key: "slideshow_fade").tag(SlideshowTransition.fade)
                    Text(key: "slideshow_cut").tag(SlideshowTransition.none)
                }
                Toggle(L("slideshow_videos"), isOn: binding(\.playVideos))
                Toggle(L("slideshow_loop"), isOn: binding(\.loop))
                Section { Text(key: "slideshow_note").font(AppTypography.footnote) }
                    .opacity(s.loop ? 1 : 1)
            }
            .navigationTitle(L("slideshow_settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func binding<V>(_ kp: WritableKeyPath<SlideshowSettings, V>) -> Binding<V> {
        Binding(get: { app.settings.slideshow[keyPath: kp] }, set: { v in app.updateSettings { $0.slideshow[keyPath: kp] = v } })
    }
}
