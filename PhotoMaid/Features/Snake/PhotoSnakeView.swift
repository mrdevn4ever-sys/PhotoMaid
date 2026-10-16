import AVFoundation
import PhotoMaidCore
import SwiftUI
import UIKit

struct PhotoSnakeView: View {
    private enum Source: Hashable { case library, favorites, collection, manual }
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onResults: (SmartReviewKind) -> Void
    let onChooseGame: () -> Void
    let onClose: () -> Void
    @State private var setup = true
    @State private var gallery = false
    @State private var settings = false
    @State private var collectionPicker = false
    @State private var source = Source.manual
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
        ZStack {
            forest
            if playing, let game = model.game { play(game) }
            else { menu }
        }
        .tint(.white)
        .sheet(isPresented: $gallery) { SnakeGalleryView(model: model) }
        .sheet(isPresented: $settings) { settingsSheet }
        .sheet(isPresented: $collectionPicker) {
            PhotoMemoryCollectionPicker { id, title in collectionID = id; collectionTitle = title }.environment(app)
        }
        .task {
            await SnakeArt.preload()
            if model.preferences.sound { model.audio.prepare() }
            await model.gallery.restore(); model.applyGalleryChanges()
        }
        .onAppear { restore(); model.validatePhotos(); model.updateTemperature() }
        .keepsScreenAwake(model.running && scenePhase == .active)
        .onDisappear { model.pause(); model.audio.stop(); model.photos.cancelLoading() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pause(); model.audio.stop() }
            else { model.validatePhotos() }
        }
        .onChange(of: voiceOver) { _, enabled in if enabled { model.useStepMode() } }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in model.updateTemperature() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
                model.pause(); model.audio.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .analysisVisibilityChanged)) { _ in model.validatePhotos() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.memoryWarning()
        }
    }

    private var forest: some View {
        GeometryReader { geo in
            Image(uiImage: SnakeArt.image(model.preferences.night ? "bg_forest_night" : "bg_forest_day"))
                .resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
                .overlay(Color.black.opacity(model.preferences.night ? 0.15 : 0.08))
        }
        .ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
    private var menu: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(uiImage: SnakeArt.image(model.preferences.character.idle))
                        .resizable().scaledToFit().frame(height: 152).shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                        .accessibilityHidden(true)
                    Text(key: "snake_title").font(.system(.largeTitle, design: .rounded).bold())
                    Text(key: "snake_swipe_intro").multilineTextAlignment(.center).font(.subheadline)
                    Text(verbatim: model.menuBest(mode: mode, speed: speed, stepMode: usesStepInput).map { L("game_best_eaten", $0) } ?? L("game_no_best"))
                        .font(.subheadline.weight(.semibold)).monospacedDigit().accessibilityIdentifier("snake.menuBest")
                    PhotoGameAnalysisStatus(onResults: onResults)
                    PhotoGameRecordSaveStatus()
                    if let error = model.photos.error { Text(verbatim: error).font(.callout) }
                    if let error = model.preferencesError { Text(verbatim: error).font(.callout) }
                    if model.photos.isLoading {
                        ProgressView(L("memory_loading"))
                        Button(L("cancel")) { model.photos.cancelLoading(); setup = true }
                    } else {
                        menuConfiguration
                        Button { startPhotos() } label: {
                            HStack {
                                Image(uiImage: SnakeArt.image("ui_play")).resizable().scaledToFit().frame(width: 32, height: 32)
                                Text(key: "snake_photo_play").font(.headline)
                            }.frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent).tint(Color(red: 0.28, green: 0.63, blue: 0.18))
                        .disabled(model.gallery.busy || (source != .manual && app.isLoadingLibrary))
                        .accessibilityIdentifier("snake.prepare")
                        HStack {
                            artButton("ui_gallery", label: "snake_gallery_title") { openGallery() }
                            Spacer()
                            artButton("ui_settings", label: "settings") { openSettings() }.accessibilityIdentifier("snake.settings")
                        }
                        Button(L("snake_symbols")) {
                            setup = false; model.startMotifs(mode: mode, speed: speed, stepMode: usesStepInput)
                        }
                        .buttonStyle(.bordered).accessibilityIdentifier("snake.symbols")
                        if model.game != nil {
                            Button(L("memory_resume")) { setup = false }.buttonStyle(.bordered)
                                .accessibilityIdentifier("snake.resume")
                        }
                    }
                }
                .padding(24).frame(maxWidth: 560)
                .background(Color(red: 0.04, green: 0.15, blue: 0.09).opacity(0.91), in: .rect(cornerRadius: 30))
                .padding(16).frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden).background { forest }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("close"), action: close).accessibilityIdentifier("snake.close")
                }
                ToolbarItem(placement: .topBarTrailing) { Button(L("games_choose")) { model.pause(); onChooseGame() } }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .background(.clear).foregroundStyle(.white)
    }
    private var menuConfiguration: some View {
        VStack(spacing: 12) {
            Picker(L("memory_source"), selection: $source) {
                Text(key: "memory_own").tag(Source.manual)
                Text(key: "memory_source_library").tag(Source.library)
                Text(key: "memory_source_favorites").tag(Source.favorites)
                Text(key: "memory_source_collection").tag(Source.collection)
            }
            if source == .manual {
                Text(verbatim: L("snake_gallery_count", model.gallery.ids.count)).font(.footnote)
            } else {
                if source == .collection {
                    Button { collectionPicker = true } label: {
                        Label(collectionID == nil ? L("memory_pick_collection") : collectionTitle, systemImage: "folder")
                    }
                    .disabled(!app.library.access.canRead)
                }
                Toggle(L("memory_cloud"), isOn: $allowNetwork)
                Text(key: "snake_photos_note").font(.footnote)
            }
            Picker(L("snake_mode"), selection: $mode) {
                Text(key: "snake_relaxed").tag(PhotoSnakeGame.Mode.relaxed)
                Text(key: "snake_classic").tag(PhotoSnakeGame.Mode.classic)
            }
            Picker(L("snake_speed"), selection: $speed) {
                Text(key: "snake_gentle").tag(PhotoSnakeModel.Speed.gentle)
                Text(key: "snake_normal").tag(PhotoSnakeModel.Speed.normal)
                Text(key: "snake_fast").tag(PhotoSnakeModel.Speed.fast)
            }
        }
        .pickerStyle(.menu).padding(16).background(.white.opacity(0.07), in: .rect(cornerRadius: 18))
    }

    private func play(_ game: PhotoSnakeGame) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                artButton("ui_back", label: "close", action: close).accessibilityIdentifier("snake.close")
                artButton("ui_pause", label: "snake_pause") { model.pause() }.accessibilityIdentifier("snake.pause")
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: L("snake_eaten", model.presentedScore)).font(.headline)
                        .accessibilityIdentifier("snake.score")
                    Text(verbatim: model.bestEaten.map { L("game_best_eaten", $0) } ?? L("game_no_best"))
                        .font(.caption).accessibilityIdentifier("snake.best")
                }
                .monospacedDigit().accessibilityElement(children: .combine)
                artButton("ui_settings", label: "settings") { openSettings() }.accessibilityIdentifier("snake.settings")
            }
            .padding(8).background(.black.opacity(0.65), in: .rect(cornerRadius: 24)).padding(.horizontal, 12)
            ZStack {
                PhotoSnakeBoard(model: model, active: scenePhase == .active && !model.tooWarm && !gallery && !settings, reduceMotion: reduceMotion)
                    .environment(\.layoutDirection, .leftToRight)
                    .contentShape(.rect)
                    .highPriorityGesture(DragGesture(minimumDistance: 16).onEnded { gesture in
                        let x = gesture.translation.width, y = gesture.translation.height
                        model.swipe(abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up))
                    })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(key: "snake_board"))
                    .accessibilityValue(Text(verbatim: boardDescription(game)))
                    .accessibilityIdentifier("snake.board")
                    .accessibilityHint(Text(verbatim: swipeHint(game)))
                    .accessibilityAction(named: Text(key: "snake_up")) { model.swipe(.up) }
                    .accessibilityAction(named: Text(key: "snake_right")) { model.swipe(.right) }
                    .accessibilityAction(named: Text(key: "snake_down")) { model.swipe(.down) }
                    .accessibilityAction(named: Text(key: "snake_left")) { model.swipe(.left) }
                    .accessibilityAction(named: Text(key: "snake_pause")) { model.pause() }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        model.updateViewport(width: Double(size.width), height: Double(size.height))
                    }
                if !model.running && (game.status == .playing || !model.presentationPending) { pausePanel }
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
        }
        .foregroundStyle(.white).accessibilityIdentifier("snake.play")
        .statusBarHidden(true).persistentSystemOverlays(.hidden)
    }

    private var pausePanel: some View {
        VStack(spacing: 16) {
            Text(key: model.displayedStatus == .won ? "snake_won" : model.displayedStatus == .lost ? "snake_over" : "snake_title")
                .font(.system(.title, design: .rounded).bold()).multilineTextAlignment(.center)
            if model.displayedStatus != .playing {
                Text(verbatim: L("snake_eaten", model.presentedScore)).font(.title2.bold()).monospacedDigit()
            }
            if model.newBest { Label(L("game_new_best"), systemImage: "trophy.fill").foregroundStyle(.yellow) }
            Text(verbatim: model.tooWarm ? L("ana2_stage_cooling") : swipeHint(model.game!))
                .multilineTextAlignment(.center).font(.headline).allowsHitTesting(false)
            if let error = model.photos.error { Text(verbatim: error).font(.footnote).multilineTextAlignment(.center) }
            if model.started || model.displayedStatus != .playing {
                Button(L(model.displayedStatus == .playing ? "memory_resume" : "memory_new")) {
                    if model.displayedStatus != .playing { model.restart() }
                    model.resume()
                }
                .buttonStyle(.borderedProminent).tint(.green)
            }
            HStack {
                Button(L("snake_gallery_title")) { openGallery() }
                Spacer()
                Button(L("games_choose")) { model.pause(); setup = true }
            }.font(.subheadline)
        }
        .padding(24).frame(maxWidth: 360)
        .background(Color(red: 0.03, green: 0.13, blue: 0.08).opacity(0.95), in: .rect(cornerRadius: 28))
        .padding(24)
        // Gestures on explanatory panel space still reach the board; buttons keep their own actions.
        .simultaneousGesture(DragGesture(minimumDistance: 16).onEnded { gesture in
            let x = gesture.translation.width, y = gesture.translation.height
            model.swipe(abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up))
        })
    }

    private var settingsSheet: some View {
        @Bindable var boundModel = model
        return NavigationStack {
            Form {
                Section(L("snake_character")) {
                    Picker(L("snake_character"), selection: $boundModel.preferences.character) {
                        ForEach(PhotoSnakeCharacter.allCases, id: \.self) { character in
                            Label { Text(key: "snake_character_" + character.rawValue) } icon: {
                                Image(uiImage: SnakeArt.image(character.idle)).resizable().scaledToFit().frame(width: 44, height: 44)
                            }.tag(character)
                        }
                    }.pickerStyle(.inline)
                }
                Section {
                    Toggle(L("snake_night"), isOn: $boundModel.preferences.night)
                    Toggle(L("snake_sound"), isOn: $boundModel.preferences.sound)
                    Toggle(L("snake_haptics"), isOn: $boundModel.preferences.haptics)
                    Toggle(L("snake_shuffle"), isOn: $boundModel.preferences.shufflePhotos)
                    Picker(L("snake_food"), selection: $boundModel.preferences.food) {
                        ForEach(PhotoSnakeFood.allCases, id: \.self) { food in Text(key: "snake_food_" + food.rawValue).tag(food) }
                    }
                    Text(key: "snake_shuffle_note").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.preferencesError { Text(verbatim: error).foregroundStyle(.red) }
            }
            .navigationTitle(L("settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { settings = false } } }
        }.tint(.green)
    }
    private func artButton(_ asset: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            model.audio.play(.tap, enabled: model.preferences.sound)
            action()
        } label: {
            Image(uiImage: SnakeArt.image(asset)).resizable().scaledToFit().frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(Text(key: label))
    }
    private func openGallery() { model.pause(); gallery = true }
    private func openSettings() { model.pause(); settings = true }
    private func close() { model.pause(); model.audio.stop(); onClose() }
    private func swipeHint(_ game: PhotoSnakeGame) -> String {
        if model.displayedStatus != .playing { return L("snake_swipe_restart") }
        return L(model.running ? "snake_swipe_steer" : model.started ? "snake_swipe_resume" : "snake_swipe_start")
    }
    private func boardDescription(_ game: PhotoSnakeGame) -> String {
        guard let head = game.body.first, let food = game.food else { return L("snake_won") }
        let d = game.nextDirection
        let x = head.x + (d == .left ? -1 : d == .right ? 1 : 0)
        let y = head.y + (d == .up ? -1 : d == .down ? 1 : 0)
        let wall = game.mode == .classic && (x < 0 || x >= game.width || y < 0 || y >= game.height)
        let next = PhotoSnakeGame.Cell((x + game.width) % game.width, (y + game.height) % game.height)
        let body = next == food ? game.body[...] : game.body.dropLast()
        let direction: String
        switch d { case .up: direction = "snake_up"; case .right: direction = "snake_right"; case .down: direction = "snake_down"; case .left: direction = "snake_left" }
        return L("snake_board_position", head.x + 1, head.y + 1, food.x + 1, food.y + 1) + ". " + L(direction) + ". " + L(wall || body.contains(next) ? "snake_obstacle" : "snake_clear_path")
    }
    private func restore() {
        guard !restored else { return }; restored = true
        mode = model.game?.mode ?? model.preferences.mode; speed = model.game == nil ? model.preferences.speed : model.speed
        if voiceOver { model.useStepMode() }
        allowNetwork = model.photos.allowsCloud
        switch model.photos.randomSource {
        case .library: source = .library
        case .favorites: source = .favorites
        case .collection(let id, let title): source = .collection; collectionID = id; collectionTitle = title
        case nil: source = .manual
        }
    }
    private func startPhotos() {
        if source == .manual {
            setup = false; model.startSaved(mode: mode, speed: speed, stepMode: usesStepInput); return
        }
        guard app.library.access.canRead else {
            if app.library.access == .notDetermined {
                Task { await app.library.requestAccess(); app.reloadLibraryIfNeeded(force: true) }
            } else if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
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
