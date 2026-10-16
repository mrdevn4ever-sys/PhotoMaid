import PhotoMaidCore
import SwiftUI
import UIKit

struct PhotoSnakeView: View {
    private enum Source: Hashable { case library, favorites, collection, manual }
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let onResults: (SmartReviewKind) -> Void
    let onChooseGame: () -> Void
    let onClose: () -> Void
    @State private var setup = true
    @State private var picker = false
    @State private var collectionPicker = false
    @State private var source = Source.library
    @State private var collectionID: String?
    @State private var collectionTitle = ""
    @State private var mode = PhotoSnakeGame.Mode.relaxed
    @State private var speed = PhotoSnakeModel.Speed.normal
    @State private var allowNetwork = false
    @State private var restored = false

    private var model: PhotoSnakeModel { app.snake }
    private var playing: Bool { !setup && !model.photos.isLoading && model.game != nil }
    private var usesStepInput: Bool {
        #if QA_FIXTURES && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-snake-swipe-steps") { return true }
        #endif
        return voiceOver
    }

    var body: some View {
        Group {
            if playing, let game = model.game {
                play(game)
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: AppSpacing.m) {
                            PhotoGameAnalysisStatus(onResults: onResults)
                            PhotoGameRecordSaveStatus()
                            if let error = model.photos.error {
                                InfoBanner(symbol: "exclamationmark.triangle", tint: AppColors.warning, text: error)
                            }
                            if model.photos.isLoading {
                                LoadingState(message: L("memory_loading"))
                                Button(L("cancel")) { model.photos.cancelLoading(); setup = true }
                            } else { configuration }
                        }
                        .padding(AppSpacing.pageMargin)
                        .frame(maxWidth: 620).frame(maxWidth: .infinity)
                    }
                    .appPage()
                    .navigationTitle(L("snake_title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("close"), action: close).accessibilityIdentifier("snake.close")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L("games_choose")) { model.pause(); onChooseGame() }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $picker) {
            StudioMediaPicker(allowsVideos: false, limit: 18, minimumSelection: 1,
                              initial: Set(model.photos.photoIDs)) { ids in
                setup = false
                model.startPhotos(ids, app: app, allowNetwork: allowNetwork, mode: mode,
                                  speed: speed, stepMode: usesStepInput)
            }
        }
        .sheet(isPresented: $collectionPicker) {
            PhotoMemoryCollectionPicker { id, title in collectionID = id; collectionTitle = title }.environment(app)
        }
        .task(id: driverID) { await runTicks() }
        .onAppear { restore(); model.validatePhotos(); model.updateTemperature() }
        .keepsScreenAwake(model.running && scenePhase == .active)
        .onDisappear { model.pause(); model.photos.cancelLoading() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.pause() } }
        .onChange(of: voiceOver) { _, enabled in if enabled { model.useStepMode() } }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            model.updateTemperature()
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

    private func close() { model.pause(); onClose() }

    private func play(_ game: PhotoSnakeGame) -> some View {
        ZStack {
            GeometryReader { geo in
                PhotoSnakeBoard(game: game, strip: model.strip, foodPicture: model.foodPicture, images: visibleImages)
                    .environment(\.layoutDirection, .leftToRight)
                    .contentShape(.rect)
                    .highPriorityGesture(DragGesture(minimumDistance: 16).onEnded { gesture in
                        let x = gesture.translation.width, y = gesture.translation.height
                        model.swipe(abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up))
                    })
                    .accessibilityIdentifier("snake.board")
                    .accessibilityHint(Text(verbatim: swipeHint(game)))
                    .accessibilityAction(named: Text(key: "snake_up")) { model.swipe(.up) }
                    .accessibilityAction(named: Text(key: "snake_right")) { model.swipe(.right) }
                    .accessibilityAction(named: Text(key: "snake_down")) { model.swipe(.down) }
                    .accessibilityAction(named: Text(key: "snake_left")) { model.swipe(.left) }
                    .accessibilityAction(named: Text(key: "snake_pause")) { model.pause() }
                    .accessibilityAction(named: Text(key: "memory_new")) { model.restart() }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        model.updateViewport(width: Double(size.width), height: Double(size.height))
                    }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: AppSpacing.s) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.title3.weight(.semibold))
                            .frame(width: AppSpacing.touch, height: AppSpacing.touch)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain).glassCapsule(interactive: true)
                    .accessibilityLabel(Text(key: "close")).accessibilityIdentifier("snake.close")
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        Text(verbatim: L("snake_eaten", game.score)).font(AppTypography.headline)
                            .accessibilityIdentifier("snake.score")
                        Text(verbatim: model.bestEaten.map { L("game_best_eaten", $0) } ?? L("game_no_best"))
                            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                            .accessibilityIdentifier("snake.best")
                    }
                    .monospacedDigit().padding(AppSpacing.s)
                    .background(AppColors.background.opacity(0.94), in: .rect(cornerRadius: AppRadii.small))
                    .allowsHitTesting(false)
                }
                Spacer()
                if !model.running || game.status != .playing {
                    VStack(spacing: AppSpacing.s) {
                        if game.status != .playing {
                            Text(key: game.status == .won ? "snake_won" : "snake_over").font(AppTypography.title)
                            if model.newBest {
                                Label(L("game_new_best"), systemImage: "trophy.fill").foregroundStyle(AppColors.accent)
                            }
                        }
                        Text(verbatim: model.tooWarm ? L("ana2_stage_cooling") : swipeHint(game))
                            .font(AppTypography.headline).multilineTextAlignment(.center)
                    }
                    .padding(AppSpacing.l)
                    .frame(maxWidth: 440)
                    .background(AppColors.background.opacity(0.94), in: .rect(cornerRadius: AppRadii.card))
                    .allowsHitTesting(false)
                }
                Spacer()
            }
            .padding(.horizontal, AppSpacing.pageMargin).padding(.top, AppSpacing.xs)
        }
        .background(AppColors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snake.play")
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func swipeHint(_ game: PhotoSnakeGame) -> String {
        if game.status != .playing { return L("snake_swipe_restart") }
        if model.running { return L("snake_swipe_steer") }
        return L(model.started ? "snake_swipe_resume" : "snake_swipe_start")
    }

    private var visibleImages: [String: UIImage] {
        Dictionary(uniqueKeysWithValues: model.photos.photoIDs.compactMap { id in model.photos.image(for: id).map { (id, $0) } })
    }

    private var configuration: some View {
        VStack(spacing: AppSpacing.m) {
            Text(key: "snake_swipe_intro").multilineTextAlignment(.center)
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
                model.startMotifs(mode: mode, speed: speed, stepMode: usesStepInput)
            }
            .buttonStyle(.glass).accessibilityIdentifier("snake.symbols")
            if model.game != nil { Button(L("memory_resume")) { setup = false }.accessibilityIdentifier("snake.resume") }
        }
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        mode = model.game?.mode ?? .relaxed; speed = model.speed
        if voiceOver { model.useStepMode() }
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
        model.startRandom(source: selected, app: app, allowNetwork: allowNetwork, mode: mode, speed: speed, stepMode: usesStepInput)
    }
}
