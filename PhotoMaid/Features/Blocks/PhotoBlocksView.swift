import PhotoMaidCore
import SwiftUI
import UIKit

struct PhotoBlocksView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    let onChooseGame: () -> Void
    @State private var showPhotos = false
    @State private var choosePhotos = false
    private var model: PhotoBlocksModel { app.blocks }

    var body: some View {
        VStack(spacing: 10) {
            header
            if model.game.phase == .ready { startMenu }
            else { play }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
        .background(PhotoBlocksPalette.ink.ignoresSafeArea()).foregroundStyle(.white)
        .tint(PhotoBlocksPalette.accent)
        .sheet(isPresented: $showPhotos, onDismiss: { model.refreshPhotos(app: app) }) { photoSheet }
        .onAppear { model.attach(app: app) }
        .onDisappear { model.releaseResources() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pause(); model.photos.clear() }
            else { app.library.refreshAccess(); model.refreshPhotos(app: app) }
        }
        .onChange(of: app.library.changeToken) { _, _ in
            // Invalidate first; the existing AppModel reload will repopulate the allowed scope.
            model.invalidatePhotos()
            model.refreshPhotos(app: app)
        }
        .onReceive(NotificationCenter.default.publisher(for: .analysisVisibilityChanged)) { _ in
            model.invalidatePhotos(); model.refreshPhotos(app: app)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.pause(); model.photos.clear()
        }
        .keepsScreenAwake(model.game.acceptsInput && scenePhase == .active)
    }

    private var header: some View {
        HStack {
            Button { model.pause(); onChooseGame() } label: {
                Label(L("blocks_games"), systemImage: "chevron.backward")
            }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("blocks.back")
            Spacer(minLength: 6)
            Text(key: "blocks_title").font(.headline)
            Spacer(minLength: 6)
            if model.game.phase != .ready {
                Button { model.pause() } label: { Image(systemName: "pause.fill").frame(width: 28, height: 28) }
                    .buttonStyle(.bordered).frame(minWidth: 44, minHeight: 44).accessibilityLabel(L("blocks_pause"))
                    .accessibilityIdentifier("blocks.pause")
                    .disabled(model.game.phase == .gameOver)
            }
        }
    }

    private var startMenu: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 66, weight: .light)).foregroundStyle(PhotoBlocksPalette.accent)
                    .padding(.top, 28).accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text(key: "blocks_title").font(.system(.largeTitle, design: .rounded).bold())
                    Text(key: "blocks_subtitle").font(.title3).foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                    Text(verbatim: L("blocks_best", model.best)).font(.headline).monospacedDigit()
                }
                VStack(spacing: 12) {
                    action("blocks_start", symbol: "play.fill", prominent: true) { model.start(app: app) }
                        .accessibilityIdentifier("blocks.start")
                    action("blocks_photos", symbol: "photo.on.rectangle") { showPhotos = true }
                        .accessibilityIdentifier("blocks.photos")
                }
                gestureHelp
                Text(key: "blocks_offline").font(.footnote).foregroundStyle(.white.opacity(0.62)).multilineTextAlignment(.center)
                if model.saveFailed { saveError }
            }
            .padding(22).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }
    }

    private var play: some View {
        VStack(spacing: 10) {
            hud
            GeometryReader { geo in
                let width = min(geo.size.width, max(1, geo.size.height) * CGFloat(model.game.width) / CGFloat(model.game.height))
                ZStack {
                    PhotoBlocksBoard(game: model.game, image: model.image, onActions: model.apply)
                        .frame(width: width)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                            model.setDisplaySize(size, scale: displayScale, app: app)
                        }
                    if model.game.isPaused { pauseMenu.frame(maxWidth: max(1, min(360, geo.size.width - 12)), maxHeight: max(1, min(420, geo.size.height - 12))) }
                    else if model.game.phase == .gameOver { gameOver.frame(maxWidth: max(1, min(360, geo.size.width - 12)), maxHeight: max(1, min(500, geo.size.height - 12))) }
                    else if model.game.phase == .discovered {
                        VStack {
                            Spacer()
                            Label(L("blocks_discovered"), systemImage: "sparkles")
                                .font(.headline).padding(14).background(.black.opacity(0.8), in: .capsule)
                                .padding(.bottom, 16)
                        }.allowsHitTesting(false)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.image == nil {
                Text(key: model.photos.isLoading ? "memory_loading" : "blocks_fallback").font(.caption).foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center).accessibilityIdentifier("blocks.fallback")
            }
            if model.saveFailed { saveError }
        }
    }

    private var hud: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: L("blocks_score", model.game.score)).font(.title3.bold())
                        .accessibilityIdentifier("blocks.score")
                    Text(verbatim: L("blocks_best", model.best)).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(verbatim: L("blocks_level", model.game.level)).font(.subheadline.bold())
                    Text(verbatim: L("blocks_rows", model.game.totalRows)).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                VStack(spacing: 0) {
                    Text(key: "blocks_next").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    PhotoBlocksNext(shape: model.game.next)
                }
            }.monospacedDigit()
            VStack(spacing: 4) {
                HStack {
                    Text(key: "blocks_progress")
                    Spacer()
                    Text(verbatim: "\(model.game.revealedStrips * 10)%").monospacedDigit()
                }.font(.caption)
                ProgressView(value: model.game.progress).tint(PhotoBlocksPalette.accent)
                    .accessibilityLabel(L("blocks_progress"))
                    .accessibilityIdentifier("blocks.progress")
            }
        }
        .padding(12).background(.white.opacity(0.055), in: .rect(cornerRadius: 16))
    }

    private var pauseMenu: some View {
        panel {
            Text(key: "blocks_paused").font(.title2.bold())
            action("blocks_continue", symbol: "play.fill", prominent: true) { model.resume(app: app) }
                .accessibilityIdentifier("blocks.resume")
            action("blocks_restart", symbol: "arrow.clockwise") { model.start(app: app) }
            action("blocks_change_photos", symbol: "photo.on.rectangle") { showPhotos = true }
            action("blocks_quit", symbol: "chevron.backward") { model.pause(); onChooseGame() }
        }
    }
    private var gameOver: some View {
        panel {
            Text(key: "blocks_over").font(.title2.bold())
            if model.newBest { Label(L("blocks_new_best"), systemImage: "trophy.fill").foregroundStyle(PhotoBlocksPalette.accent) }
            Text(verbatim: L("blocks_score", model.game.score)).font(.title.bold()).monospacedDigit()
            Text(verbatim: L("blocks_level", model.game.level) + " · " + L("blocks_rows", model.game.totalRows)).font(.subheadline)
            Text(verbatim: L("blocks_found", model.discoveredImages)).font(.subheadline)
            action("blocks_replay", symbol: "arrow.clockwise", prominent: true) { model.start(app: app) }
            action("blocks_change_photos", symbol: "photo.on.rectangle") { showPhotos = true }
            action("blocks_games", symbol: "chevron.backward", perform: onChooseGame)
        }.accessibilityIdentifier("blocks.gameOver")
    }

    private var photoSheet: some View {
        @Bindable var model = model
        return NavigationStack {
            Form {
                Section(L("blocks_photo_source")) {
                    Picker(L("blocks_photo_source"), selection: $model.source) {
                        Text(key: "blocks_random").tag(PhotoBlocksPhotos.Source.random)
                        Text(key: "blocks_newest").tag(PhotoBlocksPhotos.Source.newest)
                        Text(key: "blocks_favorites").tag(PhotoBlocksPhotos.Source.favorites)
                        Text(key: "blocks_selection").tag(PhotoBlocksPhotos.Source.selection)
                    }.pickerStyle(.inline).labelsHidden().accessibilityIdentifier("blocks.source")
                    Button { choosePhotos = true } label: {
                        Label(L("blocks_photos"), systemImage: "photo.badge.plus")
                    }.frame(minHeight: 44).accessibilityIdentifier("blocks.picker")
                    if !model.selection.isEmpty {
                        Text(verbatim: L("blocks_selected", model.selection.count))
                        Button(L("blocks_clear_selection"), role: .destructive) {
                            model.choose([], app: app)
                        }
                    }
                }
                Section {
                    Text(key: "blocks_offline")
                    if !app.library.access.canRead {
                        Button(L("blocks_allow_photos")) {
                            if app.library.access == .notDetermined {
                                Task {
                                    await app.library.requestAccess(); app.reloadLibraryIfNeeded(force: true)
                                    model.refreshPhotos(app: app)
                                }
                            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else if app.library.access == .limited {
                        Button(L("blocks_manage_access")) { app.library.presentLimitedLibraryPicker() }
                    }
                    Text(key: "blocks_safe_selection").font(.footnote).foregroundStyle(.secondary)
                }
                Section(L("blocks_how")) { gestureHelp }
            }
            .navigationTitle(L("blocks_photos"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { showPhotos = false } } }
            .onChange(of: model.source) { _, _ in model.refreshPhotos(app: app) }
            .sheet(isPresented: $choosePhotos) {
                StudioMediaPicker(allowsVideos: false, limit: 200, minimumSelection: 0,
                                  initial: Set(model.selection), offlineGame: true) { model.choose($0, app: app) }
            }
        }
    }

    private var gestureHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("blocks_hint_move"), systemImage: "arrow.left.and.right")
            Label(L("blocks_hint_rotate"), systemImage: "hand.tap")
            Label(L("blocks_hint_drop"), systemImage: "arrow.down")
        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var saveError: some View {
        Button(L("blocks_save_retry")) { model.checkpoint() }.font(.footnote).buttonStyle(.bordered)
    }
    private func action(_ key: String, symbol: String, prominent: Bool = false,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(L(key), systemImage: symbol).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12).padding(.vertical, 3)
                .foregroundStyle(prominent ? PhotoBlocksPalette.ink : .white)
                .background(prominent ? PhotoBlocksPalette.accent : .white.opacity(0.10), in: .rect(cornerRadius: 15))
        }.buttonStyle(.plain)
    }
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 12, content: content).padding(22)
        }
        .background(PhotoBlocksPalette.ink.opacity(0.97), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.2), lineWidth: 1) }
    }
}
