import AVFoundation
import PhotoMaidCore
import SwiftUI

/// Ein Medium pro Seite. Vollständiges Motiv (Aspect Fit), kein Stretching, Zoom nur bewusst.
struct MediaPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let asset: MediaAsset
    let preview: PreviewState
    @Binding var zoomed: Bool
    let skip: () -> Void
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: AppRadii.sheet)
                .fill(AppColors.surface)
            imageLayer
                .clipShape(.rect(cornerRadius: AppRadii.sheet))
            // Keine Foto-Angaben über dem Motiv; Datum/Maße gibt es im ⋯-Menü unter „Infos“.
            if asset.kind == .video, case .ready = preview {
                VideoOverlay(asset: asset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var imageLayer: some View {
        switch preview {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let image):
            if asset.kind == .video, app.player.itemID == asset.id {
                PlayerLayerView(player: app.player.player)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(zoomGesture)
                    .onTapGesture(count: 2) { withAnimation(AppMotion.standard(reduceMotion)) { scale = 1; zoomed = false } }
                    .accessibilityHidden(true)
            }
        case .notLocallyAvailable:
            VStack(spacing: AppSpacing.s) {
                Image(systemName: "icloud").font(.largeTitle).foregroundStyle(AppColors.textSecondary)
                Text("Nicht lokal verfügbar").font(AppTypography.headline)
                Text("Dieses Medium liegt nur in iCloud. PhotoMaid lädt es nicht automatisch herunter und trifft ohne Vorschau keine Entscheidung.")
                    .font(AppTypography.caption).multilineTextAlignment(.center).foregroundStyle(AppColors.textSecondary)
                Button("Ohne Entscheidung überspringen", action: skip).buttonStyle(.glass)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: AppSpacing.s) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(AppColors.warning)
                Text("Vorschau konnte nicht geladen werden").font(AppTypography.headline)
                Button("Ohne Entscheidung überspringen", action: skip).buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                scale = max(1, min(v.magnification, 5))
                zoomed = scale > 1.01
            }
            .onEnded { _ in
                if scale <= 1.05 { withAnimation(AppMotion.standard(reduceMotion)) { scale = 1 }; zoomed = false }
            }
    }

    private var accessibilityDescription: Text {
        let kind: String = switch asset.kind {
        case .video: String(localized: "Video")
        case .screenshot: String(localized: "Screenshot")
        default: String(localized: "Foto")
        }
        if let d = asset.creationDate {
            return Text("\(kind), \(d.formatted(date: .long, time: .omitted))")
        }
        return Text(kind)
    }
}

/// Video-Steuerung in eigener Control-Zone (konkurriert nicht mit Links/Rechts).
struct VideoOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let asset: MediaAsset
    @State private var loadState: LoadState = .idle

    enum LoadState { case idle, loading, ready, notLocal, failed }

    var body: some View {
        let player = app.player
        let active = player.itemID == asset.id
        VStack(spacing: AppSpacing.xs) {
            Spacer()
            if loadState == .notLocal {
                Label("Video nur in iCloud – nicht lokal verfügbar", systemImage: "icloud")
                    .font(AppTypography.caption).padding(AppSpacing.xs).glassCapsule()
            }
            Button {
                if active { player.togglePlay() } else { Task { await start(autoplay: true) } }
            } label: {
                Image(systemName: active && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title).frame(width: 64, height: 64)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .accessibilityLabel(Text(active && player.isPlaying ? "Pause" : "Abspielen"))
            Spacer()
            HStack(spacing: AppSpacing.s) {
                Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(AppTypography.caption.monospacedDigit())
                if active {
                    Slider(value: Binding(get: { player.progress }, set: { player.seek(fraction: $0) }))
                        .accessibilityLabel(Text("Wiedergabeposition"))
                } else {
                    Spacer()
                }
                Button { player.toggleMute() } label: {
                    Image(systemName: player.isMuted || !active ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .disabled(!active)
                .accessibilityLabel(Text(player.isMuted ? "Ton einschalten" : "Ton ausschalten"))
            }
            .padding(.horizontal, AppSpacing.s).padding(.vertical, AppSpacing.xs)
            .glassEffect(.regular, in: .capsule)
            .padding(AppSpacing.s)
        }
        .task(id: asset.id) {
            // Autoplay stumm, wenn lokal verfügbar und Reduce Motion nicht dagegen steht.
            if !reduceMotion { await start(autoplay: true) }
        }
    }

    private func start(autoplay: Bool) async {
        loadState = .loading
        switch await app.preview.playerItem(for: asset.id) {
        case .item(let box):
            guard !Task.isCancelled else { return }
            app.player.load(itemID: asset.id, item: box.value, autoplay: autoplay, duration: asset.duration)
            loadState = .ready
        case .notLocallyAvailable: loadState = .notLocal
        case .failed: loadState = .failed
        }
    }
}
