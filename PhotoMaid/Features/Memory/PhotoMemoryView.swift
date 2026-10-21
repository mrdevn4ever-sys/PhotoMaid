import PhotoMaidCore
import SwiftUI
import UIKit

/// Optional pause; the app owns the round, so dismissing this view never rebuilds the deck or changes a decision.
struct PhotoMemoryView: View {
    private enum Source: Hashable { case library, favorites, collection, manual }
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    let onResults: (SmartReviewKind) -> Void
    var onChooseGame: (() -> Void)? = nil
    @State private var picker = false
    @State private var setup = false
    @State private var allowNetwork = true
    @State private var source = Source.library
    @State private var pairCount = 12
    @State private var collectionPicker = false
    @State private var collectionID: String?
    @State private var collectionTitle = ""
    @State private var analysisHeight: CGFloat = 0
    @State private var boardNeedsScrolling = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var configurationLoaded = false

    private var model: PhotoMemoryModel { app.memory }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: AppSpacing.m) {
                        PhotoGameAnalysisStatus(onResults: onResults)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { analysisHeight = $0 }
                        PhotoGameRecordSaveStatus()
                        if let error = model.error {
                            InfoBanner(symbol: "exclamationmark.triangle", tint: AppColors.warning, text: error)
                        }
                        if model.isLoading {
                            LoadingState(message: L("memory_loading"))
                            Button(L("cancel")) { model.cancelLoading() }
                        } else if setup || model.game == nil {
                            configuration
                        } else if let game = model.game {
                            board(game, viewport: geo.size)
                        }
                    }
                    .padding(AppSpacing.pageMargin)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                .appPage()
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height > $0.containerSize.height + 1 } action: { _, scrolling in
                    boardNeedsScrolling = scrolling
                    if scrolling, !setup, !model.isLoading { model.noteManualMismatch() }
                }
            }
            .navigationTitle(L("memory_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("close")) { dismiss() }.accessibilityIdentifier("memory.close")
                }
            }
            .toolbar {
                if let onChooseGame {
                    ToolbarItem(placement: .topBarTrailing) { Button(L("games_choose"), action: onChooseGame) }
                }
            }
            .sheet(isPresented: $picker) {
                StudioMediaPicker(allowsVideos: false, limit: PhotoMemoryGame.maximumPairs, minimumSelection: 2,
                                  initial: Set(model.photoIDs)) { ids in
                    setup = true
                    model.startPhotos(ids, previews: app.previews, allowNetwork: allowNetwork, manualMismatch: voiceOver)
                }
            }
            .sheet(isPresented: $collectionPicker) {
                PhotoMemoryCollectionPicker { id, title in
                    collectionID = id; collectionTitle = title
                }
                .environment(app)
            }
            .task(id: mismatchTaskID) {
                // VoiceOver users control how long both cards stay visible with the explicit button.
                guard !voiceOver, scenePhase == .active, !setup, !picker, !collectionPicker, !model.isLoading,
                      model.game?.hasMismatch == true else { return }
                let round = model.roundID, faceUp = model.game?.faceUp ?? []
                do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                model.concealMismatch(round: round, faceUp: faceUp)
            }
            .onAppear {
                model.validatePhotos()
                restoreConfiguration()
                if voiceOver { model.noteManualMismatch() }
                model.setTimingActive(shouldTime)
            }
            .onChange(of: shouldTime) { _, active in model.setTimingActive(active) }
            .onChange(of: model.roundID) { _, _ in
                if model.game != nil { setup = false }
                scrollPosition.scrollTo(edge: .top)
                if voiceOver || boardNeedsScrolling { model.noteManualMismatch() }
            }
            .onChange(of: voiceOver) { _, enabled in if enabled { model.noteManualMismatch() } }
            .onDisappear {
                model.setTimingActive(false)
                model.cancelLoading()
            }
        }
    }

    private var mismatchTaskID: String {
        "\(model.roundID)-\(model.game?.faceUp.description ?? "")-\(boardNeedsScrolling)-\(voiceOver)-\(scenePhase == .active)-\(setup)-\(picker)-\(collectionPicker)-\(model.isLoading)"
    }

    private var shouldTime: Bool {
        scenePhase == .active && !setup && !picker && !collectionPicker && !model.isLoading && model.game?.isFinished == false
    }

    private var configuration: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 36, weight: .medium)).foregroundStyle(AppColors.accent)
                .frame(width: 76, height: 76)
                .background(AppColors.accent.opacity(0.12), in: .rect(cornerRadius: 24))
                .accessibilityHidden(true)
            Text(key: "game_setup_pairs_intro").font(AppTypography.body).multilineTextAlignment(.center)
            SurfaceCard {
                VStack(alignment: .leading, spacing: 16) {
                    PhotoGameSetupField(title: L("game_setup_photos")) {
                        Picker(L("memory_source"), selection: $source) {
                            Text(key: "memory_source_library").tag(Source.library)
                            Text(key: "memory_source_favorites").tag(Source.favorites)
                            Text(key: "memory_source_collection").tag(Source.collection)
                            Text(key: "memory_own").tag(Source.manual)
                        }
                        .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("memory.source")
                    }
                    if source != .manual {
                        PhotoGameSetupField(title: L("memory_size")) {
                            Picker(L("memory_size"), selection: $pairCount) {
                                ForEach([6, 12, 18], id: \.self) { count in
                                    Text(verbatim: L("memory_pair_option", count, count * 2)).tag(count)
                                }
                            }
                            .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("memory.size")
                        }
                    }
                    if source == .collection {
                        Button { collectionPicker = true } label: {
                            Label(collectionID == nil ? L("memory_pick_collection") : collectionTitle, systemImage: "folder")
                        }
                        .disabled(!app.library.access.canRead)
                        .accessibilityIdentifier("memory.chooseCollection")
                    }
                    if source == .manual {
                        Text(key: "game_setup_pairs_manual").font(.footnote).foregroundStyle(.secondary)
                    }
                    PhotoGameCloudOption(allowsCloud: $allowNetwork, identifier: "memory.cloud")
                    Text(key: "game_setup_private").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button { startChosenSource() } label: {
                Label(L(source == .manual ? "game_setup_choose_photos" : "snake_photo_play"),
                      systemImage: source == .manual ? "photo.badge.plus" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.pmProminent)
            .disabled(app.isLoadingLibrary || (source == .collection && collectionID == nil && app.library.access.canRead))
            .accessibilityIdentifier("memory.startPhotos")
            Button {
                setup = false
                model.startMotifs(manualMismatch: voiceOver)
            } label: { Label(L("game_setup_pairs_symbols"), systemImage: "sun.max") }
                .buttonStyle(.pmBordered)
                .accessibilityIdentifier("memory.startMotifs")
            if model.game != nil {
                Button(L("memory_resume")) { setup = false }
            }
        }
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
    }

    private func board(_ game: PhotoMemoryGame, viewport: CGSize) -> some View {
        let layout = PhotoMemoryBoardLayout(cards: game.cards.count,
            width: min(900, viewport.width) - AppSpacing.pageMargin * 2,
            availableHeight: viewport.height - 225 - analysisHeight,
            accessibility: dynamicType.isAccessibilitySize)
        return VStack(spacing: AppSpacing.m) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(verbatim: L("memory_pairs", game.matchedPairs.count, game.pairCount))
                    Spacer()
                    Text(verbatim: L("memory_moves", game.moves))
                }
                VStack(alignment: .leading) {
                    Text(verbatim: L("memory_pairs", game.matchedPairs.count, game.pairCount))
                    Text(verbatim: L("memory_moves", game.moves))
                }
            }
            .font(AppTypography.headline).monospacedDigit()
            ViewThatFits(in: .horizontal) {
                HStack { elapsedLabel; Spacer(); bestTimeLabel }
                VStack(alignment: .leading) { elapsedLabel; bestTimeLabel }
            }
            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).monospacedDigit()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.xs),
                                     count: layout.columns),
                      spacing: AppSpacing.xs) {
                ForEach(game.cards) { card in
                    cardButton(card, game: game).frame(height: layout.cardHeight)
                }
            }
            .frame(maxWidth: CGFloat(layout.columns) * (dynamicType.isAccessibilitySize ? 180 : 112) + CGFloat(layout.columns - 1) * AppSpacing.xs)
            Button(L("memory_flip")) { model.concealMismatch() }.buttonStyle(.pmBordered)
                .accessibilityIdentifier("memory.flip")
                .disabled(!game.hasMismatch).opacity(game.hasMismatch ? 1 : 0)
                .accessibilityHidden(!game.hasMismatch)
            if game.isFinished {
                Label(L("memory_done"), systemImage: "checkmark.circle.fill")
                    .font(AppTypography.title3).foregroundStyle(AppColors.success)
                    .accessibilityIdentifier("memory.finished")
                if model.newBest { Label(L("game_new_best"), systemImage: "trophy.fill").foregroundStyle(AppColors.accent) }
                Button(L("memory_new")) { replay() }.buttonStyle(.pmProminent)
            }
            Button(L("memory_change")) { setup = true }.buttonStyle(.pmBordered)
                .accessibilityIdentifier("memory.change")
        }
    }

    private var elapsedLabel: some View {
        TimelineView(.periodic(from: .now, by: model.timerRunning ? 0.1 : 3600)) { _ in
            Text(verbatim: L("memory_elapsed", DateText.gameDuration(model.elapsedSeconds)))
                .accessibilityIdentifier("memory.elapsed")
        }
    }

    private var bestTimeLabel: some View {
        Text(verbatim: model.bestSeconds.map { L("game_best_time", DateText.gameDuration($0)) } ?? L("game_no_best"))
            .accessibilityIdentifier("memory.best")
    }

    private func restoreConfiguration() {
        guard !configurationLoaded else { return }
        configurationLoaded = true
        allowNetwork = model.allowsCloud
        if let count = model.game?.pairCount, [6, 12, 18].contains(count) { pairCount = count }
        switch model.randomSource {
        case .library: source = .library
        case .favorites: source = .favorites
        case .collection(let id, let title):
            source = .collection; collectionID = id; collectionTitle = title
        case nil: if !model.photoIDs.isEmpty { source = .manual }
        }
    }

    private func replay() {
        if let saved = model.randomSource, let count = model.game?.pairCount {
            model.startRandom(source: saved, pairCount: count, app: app, allowNetwork: model.allowsCloud, manualMismatch: voiceOver)
        } else { model.replay(manualMismatch: voiceOver) }
    }

    private func startChosenSource() {
        guard app.library.access.canRead else { choosePhotos(); return }
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
        setup = true
        model.startRandom(source: selected, pairCount: pairCount, app: app, allowNetwork: allowNetwork, manualMismatch: voiceOver)
    }

    private func cardButton(_ card: PhotoMemoryGame.Card, game: PhotoMemoryGame) -> some View {
        let revealed = game.isRevealed(card)
        let matched = game.matchedPairs.contains(card.pairID)
        return Button { model.reveal(card.id) } label: {
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadii.small)
                        .fill(revealed ? AppColors.surface : AppColors.accentFill)
                        .overlay { if !revealed { RoundedRectangle(cornerRadius: AppRadii.small).strokeBorder(.white.opacity(0.18), lineWidth: 1) } }
                    if revealed {
                        if let image = model.image(for: card.pairID) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height).clipped()
                        } else if model.photoIDs.isEmpty {
                            Image(systemName: card.pairID).font(.largeTitle).foregroundStyle(AppColors.accent)
                        }
                    } else {
                        Image(systemName: "photo.on.rectangle.angled").font(.title2.weight(.medium)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .clipShape(.rect(cornerRadius: AppRadii.small))
                .overlay(alignment: .bottomTrailing) {
                    if matched {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, AppColors.success)
                            .padding(AppSpacing.xs)
                    }
                }
            }
            .frame(minHeight: AppSpacing.minTouch)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(revealed)
        .accessibilityLabel(Text(verbatim: L("memory_card", card.id + 1)))
        .accessibilityValue(Text(verbatim: cardValue(card, revealed: revealed, matched: matched)))
        .accessibilityIdentifier("memory.card.\(card.id)")
        .animation(AppMotion.standard(reduceMotion), value: revealed)
    }

    private func cardValue(_ card: PhotoMemoryGame.Card, revealed: Bool, matched: Bool) -> String {
        guard revealed else { return L("memory_hidden") }
        let value: String
        if let index = model.photoIDs.firstIndex(of: card.pairID) {
            value = L("memory_photo", index + 1)
        } else {
            let keys = ["memory_sun", "memory_leaf", "memory_mountain", "memory_camera", "memory_heart", "memory_moon"]
            value = PhotoMemoryModel.motifs.firstIndex(of: card.pairID).map { L(keys[$0]) } ?? ""
        }
        return matched ? L("memory_matched") + ", " + value : value
    }

    private func choosePhotos() {
        if app.library.access.canRead {
            picker = true
        } else if app.library.access == .notDetermined {
            Task {
                await app.library.requestAccess()
                app.reloadLibraryIfNeeded(force: true)
                if app.library.access.canRead, source == .manual { picker = true }
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
