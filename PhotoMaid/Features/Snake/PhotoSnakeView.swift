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
    @Environment(\.dynamicTypeSize) private var dynamicType
    let onResults: (SmartReviewKind) -> Void
    let onChooseGame: () -> Void
    let onClose: () -> Void
    @State private var setup = true
    @State private var gallery = false
    @State private var settings = false
    @State private var collectionPicker = false
    @State private var source = Source.library
    @State private var collectionID: String?
    @State private var collectionTitle = ""
    @State private var mode = PhotoSnakeGame.Mode.relaxed
    @State private var speed = PhotoSnakeModel.Speed.normal
    @State private var allowNetwork = true
    @State private var showOptions = false
    @State private var restored = false
    @State private var startWhenReady = false

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
        .onChange(of: model.roundID) { _, _ in if model.game != nil { setup = false } }
        .keepsScreenAwake(model.running && scenePhase == .active)
        .onDisappear { startWhenReady = false; model.pause(); model.audio.stop(); model.photos.cancelLoading() }
        .onChange(of: model.photos.isLoading) { _, loading in
            if !loading && model.photos.error != nil { startWhenReady = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { startWhenReady = false; model.pause(); model.audio.stop() }
            else { model.validatePhotos() }
        }
        .onChange(of: voiceOver) { _, enabled in if enabled { model.useStepMode() } }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in model.updateTemperature() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
                startWhenReady = false; model.pause(); model.audio.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .analysisVisibilityChanged)) { _ in model.validatePhotos() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            startWhenReady = false; model.memoryWarning()
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
                    VStack(spacing: 10) {
                        Image(uiImage: SnakeArt.headImage(model.preferences.character))
                            .resizable().scaledToFit().frame(height: 64)
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6).accessibilityHidden(true)
                        Text(key: "snake_title").font(.system(.largeTitle, design: .rounded).bold())
                        Text(verbatim: model.menuBest(mode: mode, speed: speed, stepMode: usesStepInput).map { L("game_best_eaten", $0) } ?? L("snake_record_empty"))
                            .font(.subheadline.weight(.semibold)).monospacedDigit().accessibilityIdentifier("snake.menuBest")
                    }
                    PhotoGameAnalysisStatus(onResults: onResults)
                    PhotoGameRecordSaveStatus()
                    if let error = model.photos.error { Text(verbatim: error).font(.callout) }
                    if let error = model.preferencesError { Text(verbatim: error).font(.callout) }
                    if model.photos.isLoading {
                        ProgressView(L("memory_loading"))
                        Button(L("cancel")) { startWhenReady = false; model.photos.cancelLoading(); setup = true }
                    } else {
                        menuConfiguration
                        Button { startPhotos() } label: { Label(L("snake_start_game"), systemImage: "play.fill") }
                        .buttonStyle(SnakeActionButtonStyle(prominent: true))
                        .disabled(model.gallery.busy || (source != .manual && app.isLoadingLibrary) ||
                                  (source == .manual && model.gallery.ids.isEmpty) || (source == .collection && collectionID == nil))
                        .accessibilityIdentifier("snake.prepare")
                        Text(key: "snake_controls_hint").font(.subheadline).multilineTextAlignment(.center)
                        menuOptions
                        Button {
                            startWhenReady = true; setup = false
                            model.startMotifs(mode: mode, speed: speed, stepMode: usesStepInput)
                        } label: { Label(L("game_setup_without_photos"), systemImage: "leaf") }
                        .buttonStyle(.bordered).accessibilityIdentifier("snake.symbols")
                        if model.game != nil {
                            Button(L("memory_resume")) { startWhenReady = true; setup = false }.buttonStyle(.bordered)
                                .accessibilityIdentifier("snake.resume")
                        }
                    }
                }
                .padding(20).frame(maxWidth: 560)
                .background((model.preferences.night ? Color(red: 0.04, green: 0.10, blue: 0.16) : Color(red: 0.04, green: 0.15, blue: 0.09)).opacity(0.94), in: .rect(cornerRadius: 30))
                .padding(16).frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden).background { forest }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("close"), action: close).accessibilityIdentifier("snake.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.pause(); onChooseGame() } label: { Label(L("snake_other_games"), systemImage: "square.grid.2x2") }
                        .labelStyle(.titleAndIcon).buttonStyle(.bordered).accessibilityIdentifier("snake.otherGames")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .background(.clear).foregroundStyle(.white)
    }
    private var menuConfiguration: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotoGameSetupField(title: L("game_setup_photos")) {
                Picker(L("memory_source"), selection: $source) {
                    Text(key: "memory_source_library").tag(Source.library)
                    Text(key: "memory_source_favorites").tag(Source.favorites)
                    Text(key: "memory_source_collection").tag(Source.collection)
                    Text(key: "memory_own").tag(Source.manual)
                }
                .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("snake.source")
            }
            if source == .manual {
                if !model.gallery.ids.isEmpty {
                    Text(verbatim: L("snake_gallery_count", model.gallery.ids.count)).font(.footnote).monospacedDigit()
                }
            } else {
                if source == .collection {
                    Button { collectionPicker = true } label: {
                        Label(collectionID == nil ? L("memory_pick_collection") : collectionTitle, systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!app.library.access.canRead)
                    .accessibilityIdentifier("snake.chooseCollection")
                }
            }
            Button {
                source = .manual; openGallery()
            } label: { Label(L(photoActionLabel), systemImage: "photo.on.rectangle") }
            .buttonStyle(SnakeActionButtonStyle())
            .disabled(model.gallery.busy).accessibilityIdentifier("snake.editPhotos")
            Text(key: "game_setup_private").font(.footnote).foregroundStyle(.secondary)
        }
        .pickerStyle(.menu).tint(.white)
        .padding(16).background(.white.opacity(0.07), in: .rect(cornerRadius: 18))
    }

    private var photoActionLabel: String {
        let hasPhotos = source == .manual ? !model.gallery.ids.isEmpty : !model.photos.photoIDs.isEmpty
        return hasPhotos ? "game_setup_edit_photos" : "game_setup_choose_photos"
    }

    private var hasRoundPhotos: Bool {
        model.usesSavedPhotos ? !model.gallery.ids.isEmpty : !model.photos.photoIDs.isEmpty
    }

    private var menuOptions: some View {
        DisclosureGroup(isExpanded: $showOptions) {
            VStack(alignment: .leading, spacing: 14) {
                if source != .manual {
                    PhotoGameCloudOption(allowsCloud: $allowNetwork, identifier: "snake.cloud")
                }
                PhotoGameSetupField(title: L("snake_mode")) {
                    Picker(L("snake_mode"), selection: $mode) {
                        Text(key: "snake_relaxed").tag(PhotoSnakeGame.Mode.relaxed)
                        Text(key: "snake_classic").tag(PhotoSnakeGame.Mode.classic)
                    }
                    .labelsHidden().accessibilityIdentifier("snake.mode")
                }
                PhotoGameSetupField(title: L("snake_speed")) {
                    Picker(L("snake_speed"), selection: $speed) {
                        Text(key: "snake_gentle").tag(PhotoSnakeModel.Speed.gentle)
                        Text(key: "snake_normal").tag(PhotoSnakeModel.Speed.normal)
                        Text(key: "snake_fast").tag(PhotoSnakeModel.Speed.fast)
                    }
                    .labelsHidden().accessibilityIdentifier("snake.speed")
                }
                Button { openSettings() } label: { Label(L("game_setup_appearance"), systemImage: "paintbrush") }
                    .accessibilityIdentifier("snake.settings")
            }
            .padding(.top, 12)
        } label: {
            Label(L("game_setup_options"), systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("snake.options")
        }
        .pickerStyle(.menu).padding(16).background(.white.opacity(0.07), in: .rect(cornerRadius: 18))
    }

    private func play(_ game: PhotoSnakeGame) -> some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    artButton("ui_back", label: "close", action: close).accessibilityIdentifier("snake.close")
                    artButton("ui_pause", label: "snake_pause") { model.pause() }.accessibilityIdentifier("snake.pause")
                    Spacer(minLength: 0)
                    if !dynamicType.isAccessibilitySize { scoreHUD }
                    artButton("ui_settings", label: "settings") { openSettings() }.accessibilityIdentifier("snake.settings")
                }
                if dynamicType.isAccessibilitySize {
                    // Keep the words Score and Record visible instead of ambiguous bare numbers.
                    VStack(alignment: .leading, spacing: 4) { scoreText; bestText }.monospacedDigit()
                }
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
                        // Start only after this board has its real dimensions. Loading/selection alone
                        // never starts a round; this flag represents the user's explicit Start tap.
                        if startWhenReady && size.width > 0 && size.height > 0 {
                            startWhenReady = false; model.resume()
                        }
                    }
                if !model.running && (game.status == .playing || !model.presentationPending) {
                    Color.black.opacity(0.24).allowsHitTesting(false)
                    ViewThatFits(in: .vertical) {
                        pausePanel.fixedSize(horizontal: false, vertical: true)
                        ScrollView { pausePanel }.contentMargins(.vertical, 8).scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
        }
        .foregroundStyle(.white).accessibilityElement(children: .contain).accessibilityIdentifier("snake.play")
        .statusBarHidden(true).persistentSystemOverlays(.hidden)
    }

    private var scoreHUD: some View {
        VStack(alignment: .trailing, spacing: 2) { scoreText; bestText }.monospacedDigit()
    }
    private var scoreText: some View {
        Text(verbatim: L("snake_eaten", model.presentedScore))
            .font(.headline).lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityLabel(Text(verbatim: L("snake_eaten", model.presentedScore)))
            .accessibilityIdentifier("snake.score")
    }
    private var bestText: some View {
        Text(verbatim: bestLabel)
            .font(.caption).lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityLabel(Text(verbatim: bestLabel))
            .accessibilityIdentifier("snake.best")
    }
    private var bestLabel: String { model.bestEaten.map { L("game_best_eaten", $0) } ?? L("snake_record_empty") }

    private var pausePanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(uiImage: SnakeArt.headImage(model.preferences.character))
                    .resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                Text(key: "snake_title").font(.system(.title, design: .rounded).bold())
            }
            if model.started || model.displayedStatus != .playing {
                Text(key: model.displayedStatus == .won ? "snake_won" : model.displayedStatus == .lost ? "snake_over" : "snake_pause")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if model.displayedStatus != .playing {
                Text(verbatim: L("snake_eaten", model.presentedScore)).font(.title2.bold()).monospacedDigit()
                Text(verbatim: bestLabel).font(.subheadline).monospacedDigit()
            }
            if model.newBest { Label(L("game_new_best"), systemImage: "trophy.fill").foregroundStyle(.yellow) }
            Text(verbatim: model.tooWarm ? L("ana2_stage_cooling") : L("snake_controls_hint"))
                .multilineTextAlignment(.center).font(.subheadline).allowsHitTesting(false)
            if let error = model.photos.error { Text(verbatim: error).font(.footnote).multilineTextAlignment(.center) }
            Button {
                if model.displayedStatus != .playing { model.restart() }
                model.resume()
            } label: {
                Label(L(model.displayedStatus != .playing ? "memory_new" : model.started ? "memory_resume" : "snake_start_game"),
                      systemImage: model.displayedStatus != .playing ? "arrow.clockwise" : "play.fill")
            }
            .buttonStyle(SnakeActionButtonStyle(prominent: true))
            .disabled(model.tooWarm || model.photos.isLoading).accessibilityIdentifier("snake.start")
            Button {
                if model.usesSavedPhotos { openGallery() }
                else { model.pause(); setup = true }
            } label: { Label(L(hasRoundPhotos ? "game_setup_edit_photos" : "game_setup_choose_photos"), systemImage: "photo.on.rectangle") }
            .buttonStyle(SnakeActionButtonStyle()).accessibilityIdentifier("snake.changePhotos")
            Button { model.pause(); onChooseGame() } label: { Label(L("snake_other_games"), systemImage: "square.grid.2x2") }
                .buttonStyle(.bordered).accessibilityIdentifier("snake.otherGames")
        }
        .padding(24).frame(maxWidth: 360)
        .background(Color(red: 0.03, green: 0.13, blue: 0.08).opacity(0.95), in: .rect(cornerRadius: 28))
        .padding(24)
        // Gestures on explanatory panel space still reach the board; buttons keep their own actions.
        .simultaneousGesture(DragGesture(minimumDistance: 16).onEnded { gesture in
            guard !dynamicType.isAccessibilitySize else { return } // Large-text scrolling must not start the game.
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
                                Image(uiImage: SnakeArt.headImage(character)).resizable().scaledToFit().frame(width: 44, height: 44)
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
        return L(model.running ? "snake_swipe_steer" : model.started ? "snake_swipe_resume" : "snake_controls_hint")
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
        case nil: source = model.usesSavedPhotos ? .manual : .library
        }
    }
    private func startPhotos() {
        if source == .manual {
            guard !model.gallery.ids.isEmpty else { openGallery(); return }
            startWhenReady = true; setup = false
            model.startSaved(mode: mode, speed: speed, stepMode: usesStepInput); return
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
        startWhenReady = true; setup = true
        model.startRandom(source: selected, app: app, allowNetwork: allowNetwork, mode: mode, speed: speed, stepMode: usesStepInput)
    }
}

/// Full-width filled actions, shared by setup and the initial/pause overlay.
private struct SnakeActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).multilineTextAlignment(.center)
            .foregroundStyle(prominent ? Color(red: 0.04, green: 0.14, blue: 0.07) : .white)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(prominent ? Color(red: 0.66, green: 0.9, blue: 0.36) : .white.opacity(0.12), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(prominent ? 0.12 : 0.16), lineWidth: 1) }
            .opacity(!enabled ? 0.42 : configuration.isPressed ? 0.78 : 1)
            .contentShape(.rect(cornerRadius: 16))
    }
}
