import PhotoMaidCore
import SwiftUI
import UIKit

struct PhotoSnakeView: View {
    private enum Source: Hashable { case library, favorites, collection, manual }
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let onResults: (SmartReviewKind) -> Void
    let onChooseGame: () -> Void
    @State private var setup = false
    @State private var picker = false
    @State private var collectionPicker = false
    @State private var source = Source.library
    @State private var collectionID: String?
    @State private var collectionTitle = ""
    @State private var mode = PhotoSnakeGame.Mode.relaxed
    @State private var speed = PhotoSnakeModel.Speed.normal
    @State private var stepMode = false
    @State private var allowNetwork = false
    @State private var restored = false
    @State private var analysisHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private var model: PhotoSnakeModel { app.snake }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: AppSpacing.s) {
                        PhotoGameAnalysisStatus(onResults: onResults)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { analysisHeight = $0 }
                        PhotoGameRecordSaveStatus()
                        if let error = model.photos.error {
                            InfoBanner(symbol: "exclamationmark.triangle", tint: AppColors.warning, text: error)
                        }
                        if model.photos.isLoading {
                            LoadingState(message: L("memory_loading"))
                            Button(L("cancel")) { model.photos.cancelLoading() }
                        } else if setup || model.game == nil {
                            configuration
                        } else if let game = model.game {
                            play(game, viewport: geo.size)
                        }
                    }
                    .padding(AppSpacing.pageMargin)
                    .frame(maxWidth: 1100).frame(maxWidth: .infinity)
                }
                .appPage()
                .scrollPosition($scrollPosition)
            }
            .navigationTitle(L("snake_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("close")) { model.pause(); dismiss() }.accessibilityIdentifier("snake.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("games_choose")) { model.pause(); onChooseGame() }
                }
            }
            .sheet(isPresented: $picker) {
                StudioMediaPicker(allowsVideos: false, limit: 18, minimumSelection: 1,
                                  initial: Set(model.photos.photoIDs)) { ids in
                    setup = false
                    model.startPhotos(ids, app: app, allowNetwork: allowNetwork, mode: mode,
                                      speed: speed, stepMode: stepMode || voiceOver)
                }
            }
            .sheet(isPresented: $collectionPicker) {
                PhotoMemoryCollectionPicker { id, title in collectionID = id; collectionTitle = title }.environment(app)
            }
            .task(id: driverID) { await runTicks() }
            .onAppear { restore(); model.validatePhotos(); model.updateTemperature() }
            .onChange(of: model.roundID) { _, _ in scrollPosition.scrollTo(edge: .top) }
            .keepsScreenAwake(model.running && scenePhase == .active)
            .onDisappear { model.pause(); model.photos.cancelLoading() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.pause() } }
            .onChange(of: voiceOver) { _, enabled in if enabled { model.useStepMode(); stepMode = true } }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                model.updateTemperature()
            }
        }
    }

    private var driverID: String { "\(model.roundID)-\(model.running)-\(model.stepMode)-\(scenePhase == .active)-\(setup)" }

    private func runTicks() async {
        guard model.running, !model.stepMode, scenePhase == .active, !setup else { return }
        while !Task.isCancelled, model.running {
            do { try await Task.sleep(for: .seconds(model.speed.interval)) } catch { return }
            guard !Task.isCancelled, scenePhase == .active else { return }
            model.tick()
        }
    }

    private var configuration: some View {
        VStack(spacing: AppSpacing.m) {
            Text(key: "snake_intro").multilineTextAlignment(.center)
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Picker(L("snake_mode"), selection: $mode) {
                        Text(key: "snake_relaxed").tag(PhotoSnakeGame.Mode.relaxed)
                        Text(key: "snake_classic").tag(PhotoSnakeGame.Mode.classic)
                    }
                    Picker(L("snake_speed"), selection: $speed) {
                        Text(key: "snake_gentle").tag(PhotoSnakeModel.Speed.gentle)
                        Text(key: "snake_normal").tag(PhotoSnakeModel.Speed.normal)
                        Text(key: "snake_fast").tag(PhotoSnakeModel.Speed.fast)
                    }
                    Toggle(L("snake_step_mode"), isOn: $stepMode).accessibilityIdentifier("snake.stepMode")
                    Picker(L("memory_source"), selection: $source) {
                        Text(key: "memory_source_library").tag(Source.library)
                        Text(key: "memory_source_favorites").tag(Source.favorites)
                        Text(key: "memory_source_collection").tag(Source.collection)
                        Text(key: "memory_own").tag(Source.manual)
                    }
                    if source == .collection {
                        Button { collectionPicker = true } label: {
                            Label(collectionID == nil ? L("memory_pick_collection") : collectionTitle, systemImage: "folder")
                        }
                        .disabled(!app.library.access.canRead)
                    }
                    Toggle(L("memory_cloud"), isOn: $allowNetwork)
                    Button { startPhotos() } label: { Label(L("snake_prepare"), systemImage: "photo.on.rectangle") }
                        .buttonStyle(.glassProminent).disabled(app.isLoadingLibrary).accessibilityIdentifier("snake.prepare")
                    Text(key: "snake_photos_note").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                }
                .pickerStyle(.menu)
            }
            Button(L("snake_symbols")) {
                setup = false
                model.startMotifs(mode: mode, speed: speed, stepMode: stepMode || voiceOver)
            }
            .buttonStyle(.glass).accessibilityIdentifier("snake.symbols")
            if model.game != nil { Button(L("memory_resume")) { setup = false } }
        }
    }

    private func play(_ game: PhotoSnakeGame, viewport: CGSize) -> some View {
        let wide = AppWorkspace.isWide(viewport, accessibility: dynamicType.isAccessibilitySize)
        let controlsWidth: CGFloat = 264 // Three native glass buttons are 80 pt wide, plus two 8 pt gaps.
        let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.l))
                          : AnyLayout(VStackLayout(spacing: AppSpacing.s))
        let width = min(1100, viewport.width) - AppSpacing.pageMargin * 2 - (wide ? controlsWidth + AppSpacing.l : 0)
        let height = max(256, min(width * 4 / 3, viewport.height - (wide ? 120 : 330) - analysisHeight))
        return layout {
            VStack(spacing: AppSpacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack { eatenLabel(game.score); Spacer(); bestLabel }
                    VStack(alignment: .leading) { eatenLabel(game.score); bestLabel }
                }
                .font(AppTypography.headline).monospacedDigit()
                PhotoSnakeBoard(game: game, strip: model.strip, foodPicture: model.foodPicture, images: visibleImages)
                    .frame(height: height)
                    .environment(\.layoutDirection, .leftToRight)
                    .contentShape(.rect)
                    .highPriorityGesture(DragGesture(minimumDistance: 12).onEnded { gesture in
                        let x = gesture.translation.width, y = gesture.translation.height
                        model.steer(abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up))
                    })
                    .accessibilityIdentifier("snake.board")
            }
            .frame(maxWidth: .infinity)
            playControls(game).frame(width: wide ? controlsWidth : nil)
        }
    }

    private func playControls(_ game: PhotoSnakeGame) -> some View {
        VStack(spacing: AppSpacing.s) {
            if model.tooWarm { Text(key: "ana2_stage_cooling").font(AppTypography.footnote) }
            if game.status == .playing {
                Text(key: model.running ? (model.stepMode ? "snake_step_hint" : "snake_controls_hint") : (model.started ? "snake_paused" : "snake_ready"))
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
                HStack {
                    Button(L(model.running ? "snake_pause" : (model.started ? "snake_resume" : "snake_start"))) {
                        if model.running { model.pause() } else { model.resume() }
                    }
                    .buttonStyle(.glassProminent).disabled(model.tooWarm)
                    .accessibilityIdentifier("snake.toggleRunning")
                    if model.stepMode { Button(L("snake_forward")) { model.tick() }.buttonStyle(.glass).disabled(!model.running) }
                }
                directionPad
            } else {
                Text(key: game.status == .won ? "snake_won" : "snake_over").font(AppTypography.title3)
                if model.newBest { Label(L("game_new_best"), systemImage: "trophy.fill").foregroundStyle(AppColors.accent) }
                Button(L("memory_new")) { model.restart() }.buttonStyle(.glassProminent)
            }
            Button(L("snake_configure")) { model.pause(); setup = true }.buttonStyle(.glass).accessibilityIdentifier("snake.change")
        }
    }

    private func eatenLabel(_ count: Int) -> some View {
        Text(verbatim: L("snake_eaten", count)).accessibilityIdentifier("snake.score")
    }

    private var bestLabel: some View {
        Text(verbatim: model.bestEaten.map { L("game_best_eaten", $0) } ?? L("game_no_best"))
            .accessibilityIdentifier("snake.best")
    }

    private var visibleImages: [String: UIImage] {
        Dictionary(uniqueKeysWithValues: model.photos.photoIDs.compactMap { id in model.photos.image(for: id).map { (id, $0) } })
    }

    private var directionPad: some View {
        VStack(spacing: AppSpacing.xs) {
            directionButton(.up, symbol: "arrow.up", key: "snake_up")
            HStack(spacing: AppSpacing.xs) {
                directionButton(.left, symbol: "arrow.left", key: "snake_left")
                directionButton(.down, symbol: "arrow.down", key: "snake_down")
                directionButton(.right, symbol: "arrow.right", key: "snake_right")
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .disabled(!model.running)
    }

    private func directionButton(_ direction: PhotoSnakeGame.Direction, symbol: String, key: String) -> some View {
        Button { model.steer(direction) } label: {
            Image(systemName: symbol).font(.title3).frame(width: 56, height: AppSpacing.touch)
        }
        .buttonStyle(.glass).accessibilityLabel(Text(verbatim: L(key)))
        .accessibilityIdentifier("snake.direction.\(direction.rawValue)")
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        mode = model.game?.mode ?? .relaxed; speed = model.speed
        stepMode = model.game == nil ? voiceOver : model.stepMode
        if voiceOver { model.useStepMode(); stepMode = true }
        allowNetwork = model.photos.allowsCloud
        switch model.photos.randomSource {
        case .library: source = .library
        case .favorites: source = .favorites
        case .collection(let id, let title): source = .collection; collectionID = id; collectionTitle = title
        case nil: if !model.photos.photoIDs.isEmpty { source = .manual }
        }
    }

    private func startPhotos() {
        guard app.library.access.canRead else {
            if app.library.access == .notDetermined {
                Task { await app.library.requestAccess(); app.reloadLibraryIfNeeded(force: true) }
            } else if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
        if source == .manual { picker = true; return }
        let selected: PhotoGameSource
        switch source {
        case .library: selected = .library
        case .favorites: selected = .favorites
        case .collection:
            guard let id = collectionID else { collectionPicker = true; return }
            selected = .collection(id: id, title: collectionTitle)
        case .manual: return
        }
        setup = false
        model.startRandom(source: selected, app: app, allowNetwork: allowNetwork, mode: mode, speed: speed, stepMode: stepMode || voiceOver)
    }
}
