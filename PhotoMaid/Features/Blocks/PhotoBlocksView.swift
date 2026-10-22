import PhotoMaidCore
import SwiftUI
import UIKit

struct PhotoBlocksView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    let onChooseGame: () -> Void
    var onClose: () -> Void = {}
    @State private var showPhotos = false
    @State private var choosePhotos = false
    private var model: PhotoBlocksModel { app.blocks }

    var body: some View {
        NavigationStack {
            Group {
                if model.game.phase == .ready { startMenu }
                else { play.padding(.horizontal, AppSpacing.pageMargin).padding(.top, 4).padding(.bottom, 8) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appPage()
            // Gleiche Kopfzeile wie Paare und Snake (Design vereinheitlicht, 22.10.2026); „blocks.back“ = Andere Spiele.
            .gameToolbar(title: L("blocks_title"), closeID: "blocks.close", otherGamesID: "blocks.back",
                         close: { model.pause(); onClose() }, otherGames: { model.pause(); onChooseGame() })
        }
        .tint(AppColors.accent)
        .sheet(isPresented: $showPhotos, onDismiss: { model.refreshPhotos(app: app); model.checkpoint() }) { photoSheet }
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
        .onReceive(NotificationCenter.default.publisher(for: .analysisVisibilityChanged).receive(on: RunLoop.main)) { _ in
            model.invalidatePhotos(); model.refreshPhotos(app: app)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.pause(); model.photos.clear()
        }
        .keepsScreenAwake(model.game.acceptsInput && scenePhase == .active)
    }

    private var startMenu: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(spacing: 20) {
                GameIntro(text: L("blocks_subtitle"), best: L("blocks_best", model.best), bestIdentifier: "blocks.best") {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 34, weight: .medium)).foregroundStyle(AppColors.accent)
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 16) {
                        PhotoGameSetupField(title: L("game_setup_photos")) {
                            Picker(L("blocks_photo_source"), selection: $model.source) {
                                Text(key: "blocks_random").tag(PhotoBlocksPhotos.Source.random)
                                Text(key: "blocks_newest").tag(PhotoBlocksPhotos.Source.newest)
                                Text(key: "blocks_favorites").tag(PhotoBlocksPhotos.Source.favorites)
                                Text(key: "blocks_selection").tag(PhotoBlocksPhotos.Source.selection)
                            }
                            .pickerStyle(.menu).labelsHidden()
                            .accessibilityIdentifier("blocks.sourceMenu")
                            .onChange(of: model.source) { _, _ in model.refreshPhotos(app: app); model.checkpoint() }
                        }
                        Button { showPhotos = true } label: { Label(L("blocks_photos"), systemImage: "photo.on.rectangle") }
                            .buttonStyle(GameButtonStyle())
                            .accessibilityIdentifier("blocks.photos")
                        Text(key: "blocks_photo_privacy").font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("blocks.photoPrivacy")
                    }
                }
                Button { model.start(app: app) } label: { Label(L("blocks_start"), systemImage: "play.fill") }
                    .buttonStyle(GameButtonStyle(prominent: true))
                    .accessibilityIdentifier("blocks.start")
                gestureHelp.foregroundStyle(AppColors.textSecondary)
                if model.saveFailed { saveError }
            }
            .padding(AppSpacing.pageMargin)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
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
                    if model.game.isPaused { pauseMenu.frame(maxWidth: max(1, min(360, geo.size.width - 12)), maxHeight: max(1, min(440, geo.size.height - 12))) }
                    else if model.game.phase == .gameOver { gameOver.frame(maxWidth: max(1, min(360, geo.size.width - 12)), maxHeight: max(1, min(520, geo.size.height - 12))) }
                    else if model.game.phase == .discovered {
                        VStack {
                            Spacer()
                            Label(L("blocks_discovered"), systemImage: "sparkles")
                                .font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                                .padding(14).background(.black.opacity(0.8), in: .capsule)
                                .padding(.bottom, 16)
                        }.allowsHitTesting(false)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Kein Hinweistext im Spiel (Nutzer, 22.10.2026: „Der Text soll nie kommen“) – „Bilder werden vorbereitet …“
            // erschien bei jedem Nachladen des Fotos unter dem Feld und ließ es wackeln. Ohne Foto bleibt der neutrale Grund.
        }
    }

    /// Spielstand als App-Karte; Pause (und ggf. „Speichern fehlgeschlagen“) als runde Knöpfe rechts – feste Höhe,
    /// das Spielfeld darunter rückt nie.
    private var hud: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: L("blocks_score", model.game.score)).font(PMFont.heading(20, relativeTo: .title3))
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityIdentifier("blocks.score")
                    Text(verbatim: L("blocks_best", model.best)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
                // Eine Zeile je Wert: wachsende Zahlen dürfen die Kopfzeile nie höher machen (sonst rückt das Feld).
                .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: L("blocks_level", model.game.level)).font(AppTypography.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(verbatim: L("blocks_rows", model.game.totalRows)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                VStack(spacing: 0) {
                    Text(key: "blocks_next").font(.caption2).foregroundStyle(AppColors.textSecondary)
                    PhotoBlocksNext(shape: model.game.next)
                }
                if model.saveFailed {
                    hudButton("exclamationmark.triangle.fill", label: L("blocks_save_retry"), tint: AppColors.warning) { model.checkpoint() }
                }
                hudButton("pause.fill", label: L("blocks_pause")) { model.pause() }
                    .accessibilityIdentifier("blocks.pause")
                    .disabled(model.game.phase == .gameOver || model.game.isPaused)
            }.monospacedDigit()
            VStack(spacing: 4) {
                HStack {
                    Text(key: "blocks_progress")
                    Spacer()
                    Text(verbatim: "\(model.game.revealedStrips * 10)%").monospacedDigit()
                }
                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                ProgressView(value: model.game.progress).tint(AppColors.accent)
                    .accessibilityLabel(L("blocks_progress"))
                    .accessibilityIdentifier("blocks.progress")
            }
        }
        .padding(12)
        .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }

    private func hudButton(_ symbol: String, label: String, tint: Color = AppColors.textPrimary,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(AppColors.background, in: .circle)
                .overlay(Circle().strokeBorder(AppColors.control, lineWidth: 1))
                .contentShape(.circle)
        }
        .buttonStyle(PMPressStyle())
        .accessibilityLabel(Text(verbatim: label))
    }

    private var pauseMenu: some View {
        GamePanel {
            Text(key: "blocks_paused").font(AppTypography.title)
            Button { model.resume(app: app) } label: { Label(L("blocks_continue"), systemImage: "play.fill") }
                .buttonStyle(GameButtonStyle(prominent: true))
                .accessibilityIdentifier("blocks.resume")
            Button { model.start(app: app) } label: { Label(L("blocks_restart"), systemImage: "arrow.clockwise") }
                .buttonStyle(GameButtonStyle())
            Button { showPhotos = true } label: { Label(L("blocks_change_photos"), systemImage: "photo.on.rectangle") }
                .buttonStyle(GameButtonStyle())
            Button { model.pause(); onChooseGame() } label: { Label(L("snake_other_games"), systemImage: "square.grid.2x2") }
                .buttonStyle(.pmBordered)
        }
    }
    private var gameOver: some View {
        GamePanel {
            Text(key: "blocks_over").font(AppTypography.title)
            if model.newBest { Label(L("blocks_new_best"), systemImage: "trophy.fill").foregroundStyle(AppColors.accent) }
            Text(verbatim: L("blocks_score", model.game.score)).font(PMFont.heading(28)).monospacedDigit()
            Text(verbatim: L("blocks_level", model.game.level) + " · " + L("blocks_rows", model.game.totalRows))
                .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
            Text(verbatim: L("blocks_found", model.discoveredImages))
                .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
            Button { model.start(app: app) } label: { Label(L("blocks_replay"), systemImage: "arrow.clockwise") }
                .buttonStyle(GameButtonStyle(prominent: true))
            Button { showPhotos = true } label: { Label(L("blocks_change_photos"), systemImage: "photo.on.rectangle") }
                .buttonStyle(GameButtonStyle())
            Button { model.pause(); onChooseGame() } label: { Label(L("snake_other_games"), systemImage: "square.grid.2x2") }
                .buttonStyle(.pmBordered)
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
                        .disabled(!app.library.access.canRead)
                    if !model.selection.isEmpty {
                        Text(verbatim: L("blocks_selected", model.selection.count))
                        Button(L("blocks_clear_selection"), role: .destructive) {
                            model.choose([], app: app)
                        }
                    }
                }
                Section {
                    Text(key: "blocks_photo_privacy")
                        .accessibilityIdentifier("blocks.photoPrivacy")
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
                                  initial: Set(model.selection), secureGame: true) { model.choose($0, app: app) }
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
        Button(L("blocks_save_retry")) { model.checkpoint() }.font(.footnote).buttonStyle(.pmBordered)
    }
}
