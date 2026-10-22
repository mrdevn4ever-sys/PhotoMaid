import Photos
import PhotoMaidCore
import SwiftUI

/// Entscheidungs-Feed. Gesten (fest, tatsächliche Fingerbewegung): hoch = Behalten, links = Papierkorb,
/// rechts (bis 45°) = Später mit Standardtermin, runter = vorheriges Medium (keine Entscheidung).
/// Keine Entscheidungs-Tasten – außer VoiceOver, Schaltersteuerung oder der Bedienungshilfe „Tasten zum Entscheiden“.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @State private var model: FeedViewModel
    @State private var showHints = false
    @State private var hintToken = 0
    @State private var hintShownAt: TimeInterval = 0
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var showInfo = false
    @State private var showTrash = false
    @State private var showGrid = false
    @State private var confirmExclude = false
    @State private var shareItem: MediaShareItem?
    @State private var tourStep = 0
    @State private var showMemory = false
    @State private var countedAsActiveFeed = false
    @State private var memoryResults: SmartReviewKind?
    @Environment(\.layoutDirection) private var readingDirection
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicType
    @GestureState private var dragging = false

    init(request: FeedRequest, app: AppModel) {
        _model = State(initialValue: FeedViewModel(request: request, app: app))
    }

    private var controls: FeedControls { app.settings.feedControls }
    /// Tasten: mit VoiceOver/Schaltersteuerung immer, sonst nach Einstellung „Wischen & Tasten“ (E18).
    private var needsButtons: Bool {
        !controls.buttons.isEmpty && (voiceOver || switchControl || controls.visibility == .always)
    }
    /// „In Album legen“-Aktionen der eigenen Belegung, zusätzlich als VoiceOver-Aktionen.
    private var albumActions: [FeedAction] {
        var seen = Set<FeedAction>()
        let all = [controls.up, controls.left, controls.right, controls.down] + controls.buttons
        return all.filter { $0.albumID != nil && seen.insert($0).inserted }
    }
    private var zoomed: Bool { zoom > 1.01 }

    // Aufgeteilt (Bühne, Blätter, Hinweise), damit der Type-Checker jede Kette einzeln prüft.
    var body: some View {
        withSheets(feedScene)
            .alert(protectedTitle, isPresented: protectedFavoriteShown) {
                Button(L("fav_remove")) { Task { await model.unfavoriteProtected() } }
                Button(L("cancel"), role: .cancel) { model.protectedFavorite = nil }
            } message: {
                Text(key: "fav_protected_text")
            }
            .alert(L("info"), isPresented: $showInfo) {
                Button(L("ok"), role: .cancel) {}
            } message: {
                Text(verbatim: infoText)
            }
            .alert(excludeTitle, isPresented: $confirmExclude) {
                Button(L("excl_confirm_action")) {
                    if case .album(let id, let title) = model.request.source { Task { await model.excludeAlbum(id, title: title) } }
                }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(key: "excl_confirm_text")
            }
    }

    private var feedScene: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            GeometryReader { geo in
                let wide = AppWorkspace.isWide(geo.size, accessibility: dynamicType.isAccessibilitySize)
                HStack(spacing: wide ? AppSpacing.l : 0) {
                    if wide {
                        FeedBasketPanel { showTrash = true }
                            .environment(\.layoutDirection, readingDirection)
                            .frame(width: min(280, max(180, geo.size.width * 0.32)))
                            .padding(.leading, AppSpacing.pageMargin)
                    }
                    VStack(spacing: AppSpacing.s) {
                        header
                        content
                    }
                    .environment(\.layoutDirection, readingDirection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: geo.size) { _, _ in resetZoom() }
            }
            .padding(.bottom, AppSpacing.xs)
        }
        // Gestenhilfe: Schleier über den ganzen Bildschirm, Hinweise an den Rändern der Bühne.
        .overlayPreferenceValue(FeedStageAnchorKey.self) { stage in
            if showHints, let stage {
                GestureHintOverlay(controls: controls, stage: stage)
                    .transition(.opacity)
            }
        }
        .tourOverlay(step: activeTourStep, isLast: tourStep == tourSteps.count - 1) {
            if tourStep >= tourSteps.count - 1 {
                app.updateSettings { $0.feedTourSeen = true }
            } else {
                tourStep += 1
            }
        } skip: {
            app.updateSettings { $0.feedTourSeen = true }
        }
        .task {
            guard !model.isLoaded else { return } // Returning from a pause keeps this exact session and position.
            model.reduceMotion = reduceMotion
            await model.load()
            if !model.session.items.isEmpty && (app.settings.showGestureHintOnOpen || !app.settings.gestureHintSeen) {
                flashHints()
                if !app.settings.gestureHintSeen { app.updateSettings { $0.gestureHintSeen = true } }
            }
        }
        .task(id: hintToken) {
            guard showHints else { return }
            // Lange genug zum Lesen; ein echter Wisch oder Antippen blendet sie früher aus. Wird die Aufgabe
            // abgebrochen (neu eingeblendet, Ansicht neu aufgebaut), blendet das nie aus – früher verschwand die
            // Hilfe dadurch sofort.
            do { try await Task.sleep(for: .seconds(GestureHintOverlay.duration)) } catch { return }
            Diagnostics.log(.feed, "hints-auto-hidden")
            withAnimation(.easeOut(duration: 0.6)) { showHints = false }
        }
        .onChange(of: reduceMotion) { _, v in model.reduceMotion = v }
        // Gamification: leise Pillen bei jeweils 100 in dieser Sitzung und beim Erreichen des Tagesziels –
        // nie eine Unterbrechung der Geste, nie eine Entscheidung.
        .onChange(of: model.session.summary.reviewed) { old, new in
            guard app.settings.showAchievements, new > old, new / 100 > old / 100 else { return }
            app.showToast(L("feed_milestone", CountText.number(new / 100 * 100)))
        }
        .onChange(of: app.read.progress.reviewedToday) { old, new in
            let goal = app.settings.dailyGoal
            guard app.settings.showAchievements, goal > 0, old < goal, new >= goal else { return }
            Haptics.success()
            app.showToast(L("ach_goal_done"))
        }
        .onChange(of: voiceOver) { _, _ in model.setSuspended(voiceOver || zoomed || showMemory) }
        .onChange(of: zoom) { _, _ in model.setSuspended(voiceOver || zoomed || showMemory) }
        .onChange(of: showMemory) { _, presented in
            model.setSuspended(voiceOver || zoomed || presented)
            if presented { app.player.pause() }
            setFeedActive(!presented)
        }
        .onChange(of: model.session.index) { _, _ in resetZoom() }
        .onChange(of: app.library.changeToken) { _, _ in if model.isLoaded { model.refreshWindowAssets() } }
        .onChange(of: dragging) { _, isDragging in
            // Systemabbruch der Geste (Anruf, Mitteilungszentrale): keine Entscheidung.
            if !isDragging, case .dragging = model.machine.phase { model.dragCancelled() }
            if !isDragging, case .directionLocked = model.machine.phase { model.dragCancelled() }
        }
        // Solange gewischt wird, treten Analyse und Messen zurück (Netz und Rechenzeit für die Vorschauen).
        .onAppear { setFeedActive(!showMemory) }
        .onDisappear { app.player.stop(); setFeedActive(false) }
    }

    private func setFeedActive(_ active: Bool) {
        guard active != countedAsActiveFeed else { return }
        countedAsActiveFeed = active
        if active { ForegroundActivity.feedAppeared() } else { ForegroundActivity.feedDisappeared() }
    }

    private func withSheets(_ content: some View) -> some View {
        content
            .fullScreenCover(isPresented: $showMemory, onDismiss: {
                if let kind = memoryResults {
                    memoryResults = nil
                    model.close()
                    app.navigate(.smartReview(kind), in: .cleanup)
                }
            }) {
                PhotoGamesView { memoryResults = $0 }.environment(app)
            }
            .sheet(item: pickerReceiptItem) { receipt in
                LaterPickerSheet(initial: model.defaultLaterInterval, today: model.today, allowsNoDate: true) { result in
                    Task {
                        switch result {
                        case .day(let d): await model.pickerFinished(receipt, day: d)
                        case .noDate: await model.pickerNoDate(receipt)
                        case .cancelled: await model.pickerFinished(receipt, day: nil)
                        }
                    }
                }
            }
            .sheet(item: customLaterItem) { req in
                LaterPickerSheet(initial: model.defaultLaterInterval, today: model.today, allowsNoDate: false) { result in
                    if case .day(let d) = result { model.customLaterFinished(req, day: d) } else { model.customLaterFinished(req, day: nil) }
                }
            }
            .sheet(item: albumSheetItem) { asset in
                AlbumPickerSheet(assetIDs: [asset.id]) { id, title in Task { await model.addCurrent(toAlbum: id, title: title) } }
            }
            .sheet(item: seriesItem) { box in
                SeriesCompareView(members: box.members) { keep in Task { await model.confirmSeries(box.members, keep: keep) } }
            }
            .sheet(isPresented: $showTrash) {
                NavigationStack { TrashView(inSheet: true) }
            }
            .sheet(isPresented: $showGrid) {
                NavigationStack { MediaGridView(source: .items(model.session.items.dropFirst(model.session.index).map(\.localIdentifier), titleKey: "grid_open")) }
            }
            .sheet(item: $shareItem) { item in ShareSheet(items: item.items) }
    }

    private var pickerReceiptItem: Binding<LaterReceipt?> {
        Binding(get: { model.pickerReceipt }, set: { model.pickerReceipt = $0 })
    }

    private var customLaterItem: Binding<CustomLaterRequest?> {
        Binding(get: { model.customLater }, set: { if $0 == nil, let r = model.customLater { model.customLaterFinished(r, day: nil) } })
    }

    private var albumSheetItem: Binding<MediaAsset?> {
        Binding(get: { model.albumSheetFor }, set: { model.albumSheetFor = $0 })
    }

    private var seriesItem: Binding<SeriesBox?> {
        Binding(get: { model.seriesOpen.map(SeriesBox.init) }, set: { model.seriesOpen = $0?.members })
    }

    private var protectedFavoriteShown: Binding<Bool> {
        Binding(get: { model.protectedFavorite != nil }, set: { if !$0 { model.protectedFavorite = nil } })
    }

    // MARK: Kopf

    private var header: some View {
        GlassEffectContainer(spacing: AppSpacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.s) {
                    headerLeading
                    headerPosition.fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity)
                    headerTrailing
                }
                VStack(spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.s) {
                        headerLeading
                        Spacer(minLength: 0)
                        headerTrailing
                    }
                    headerPosition.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.top, AppSpacing.xs)
    }

    /// Artefakt: große Nummer (Bricolage 700, 18) und „von …“ (12); der Titel der Quelle nur für VoiceOver.
    private var headerPosition: some View {
        VStack(spacing: 0) {
            if !model.session.items.isEmpty {
                let p = model.session.position
                Text(verbatim: CountText.number(p.current)).font(PMFont.heading(18, relativeTo: .headline))
                    .foregroundStyle(AppColors.textPrimary).monospacedDigit().lineLimit(1)
                Text(verbatim: L("art_feed_of", CountText.number(p.total)))
                    .font(PMFont.text(.regular, 12, relativeTo: .caption)).foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit().lineLimit(1)
            } else {
                Text(verbatim: model.request.title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.session.items.isEmpty ? model.request.title :
            model.request.title + ", " + L("feed_position", model.session.position.current, model.session.position.total)))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("feed.position")
    }

    @ViewBuilder private var headerLeading: some View {
        headerButton(icon: .close, label: L("close")) { model.close() }
            .accessibilityIdentifier("feed.close")
    }

    @ViewBuilder private var headerTrailing: some View {
        if model.canReorder && model.isLoaded && !model.session.items.isEmpty {
            Menu {
                Picker(L("order_title"), selection: Binding(get: { model.order }, set: { o in Task { await model.setOrder(o) } })) {
                    Text(key: "order_newest").tag(FeedOrder.newest)
                    Text(key: "order_oldest").tag(FeedOrder.oldest)
                    Text(key: "order_largest").tag(FeedOrder.largest)
                    Text(key: "order_random").tag(FeedOrder.random)
                }
            } label: { headerCircle(Image(systemName: "arrow.up.arrow.down").font(.system(size: 17, weight: .semibold))) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(key: "order_title"))
        }
        headerButton(icon: .cup, label: L("memory_break"), tint: AppColors.later) { showMemory = true }
            .disabled(!model.isLoaded || model.isCommitting)
            .accessibilityIdentifier("feed.memory")
        headerButton(icon: .undo, label: L("undo"), tint: app.read.canUndo ? AppColors.textPrimary : AppColors.disabled) {
            Task { await model.undo() }
        }
            .disabled(!app.read.canUndo)
            .tourTarget("feed.undo")
    }

    /// Runder 44-pt-Knopf wie im Artefakt (dunkle Fläche, feiner Rand).
    private func headerButton(icon: PMIconName, label: String, tint: Color = AppColors.textPrimary,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) { headerCircle(PMIcon(icon, size: 19, lineWidth: icon == .close ? 2.2 : 2).foregroundStyle(tint)) }
            .buttonStyle(PMPressStyle())
            .accessibilityLabel(Text(verbatim: label))
    }

    private func headerCircle(_ content: some View) -> some View {
        content
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: 44, height: 44)
            .background(AppColors.surface, in: .circle)
            .overlay(Circle().strokeBorder(AppColors.control, lineWidth: 1))
            .contentShape(.circle)
    }

    /// Fortschritt der Sitzung (4 pt, Bernstein).
    private var progressBar: some View {
        let p = model.session.position
        let fraction = p.total > 0 ? max(0.015, Double(p.current - 1) / Double(p.total)) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.surfaceStroke)
                Capsule().fill(AppColors.accentFill).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 4)
        .environment(\.layoutDirection, readingDirection)
        .animation(AppMotion.standard(reduceMotion), value: p.current)
        .accessibilityHidden(true)
    }

    // MARK: Inhalt

    @ViewBuilder
    private var content: some View {
        if !model.isLoaded {
            LoadingState(message: L("feed_loading"))
        } else if model.session.items.isEmpty {
            EmptyState(symbol: "checkmark.circle", title: L("qa_all_done"), message: emptyMessage,
                       actionTitle: L("back")) { model.close() }
                .frame(maxHeight: .infinity)
        } else if model.session.isFinished {
            SessionSummaryView(summary: model.session.summary, basketCount: app.read.basket.count,
                               openTrash: { showTrash = true },
                               goBack: { model.perform(.previous) },
                               done: { model.close() })
                .frame(maxHeight: .infinity)
        } else {
            if needsButtons && controls.placement == .aboveMedia {
                DecisionButtons(controls: controls) { model.perform(action: $0) }
                    .padding(.horizontal, AppSpacing.pageMargin)
            }
            progressBar.padding(.horizontal, AppSpacing.pageMargin)
            stage
            VStack(spacing: AppSpacing.xs) {
                if let a = model.currentAsset {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.xs) {
                            MediaInfoLine(asset: a)
                            feedActionButtons.tourTarget("feed.actions")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            MediaInfoLine(asset: a)
                            HStack { Spacer(minLength: 0); feedActionButtons }
                        }
                    }
                    if a.isVideo { FeedVideoControls(asset: a) }
                }
                if needsButtons && controls.placement == .belowMedia {
                    DecisionButtons(controls: controls) { model.perform(action: $0) }
                }
                HStack(spacing: AppSpacing.xs) {
                    FeedGestureLegend(controls: controls)
                    Spacer(minLength: 0)
                    feedCounters
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
        }
    }

    private var emptyMessage: String {
        switch model.request.source {
        case .quick(let q): QuickAccessText.emptyText(q)
        case .category(.photos): L("feed_empty_photos")
        case .category(.videos): L("feed_empty_videos")
        case .category(.screenshots): L("feed_empty_screenshots")
        default: L("feed_empty_message")
        }
    }

    // MARK: Bühne

    private var stageGestureMask: GestureMask {
        guard let current = model.current, model.previews[current] == .ready else { return .subviews }
        return .all
    }

    private var stage: some View {
        GeometryReader { geo in
            stageLayers(size: geo.size)
            .contentShape(.rect)
            .gesture(dragGesture, including: stageGestureMask)
            .simultaneousGesture(magnifyGesture, including: stageGestureMask)
            .simultaneousGesture(tapGestures, including: stageGestureMask)
            .onAppear { model.updateViewport(geo.size, scale: displayScale) }
            .onChange(of: geo.size) { _, size in model.updateViewport(size, scale: displayScale) }
            .onChange(of: displayScale) { _, scale in model.updateViewport(geo.size, scale: scale) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(key: "feed_stage"))
            .accessibilityIdentifier("feed.stage")
            .accessibilityValue(Text(verbatim: model.currentAsset.map(MediaInfoLine.describe) ?? ""))
            .accessibilityAction(named: Text(key: "act_keep_next")) { model.perform(.keep) }
            .accessibilityAction(named: Text(key: "act_trash")) { model.perform(.markForCleanup) }
            .accessibilityAction(named: Text(key: "act_later")) { model.perform(.later) }
            .accessibilityAction(named: Text(key: "act_later_custom")) { model.perform(.laterCustom) }
            .accessibilityAction(named: Text(key: "act_previous")) { model.perform(.previous) }
            .accessibilityAction(named: Text(key: "undo")) { Task { await model.undo() } }
            .accessibilityAction(named: Text(key: "feed_view_basket")) { showTrash = true }
            .accessibilityActions {
                ForEach(albumActions, id: \.self) { action in
                    Button(FeedActionText.accessibility(action)) { model.perform(action: action) }
                }
            }
            // Werbekarte (nur Gratis) liegt über dem Medium und hat eigene Gesten – nie eine Entscheidung.
            .overlay {
                if let card = model.adCard {
                    FeedAdCardView(card: card, dismiss: { model.dismissAdCard() }) {
                        model.dismissAdCard()
                        app.navigate(.pro)
                        model.close()
                    }
                    .transition(.opacity)
                }
            }
            .animation(AppMotion.standard(reduceMotion), value: model.adCard?.id)
        }
        .anchorPreference(key: FeedStageAnchorKey.self, value: .bounds) { $0 }
        .padding(.horizontal, AppSpacing.xs)
    }

    /// Small builders keep the compiler's constraint search bounded (Xcode 26.6).
    private func stageLayers(size: CGSize) -> some View {
        let refs = [model.next, model.current].compactMap { $0 }
        return ZStack {
            ForEach(refs, id: \.self) { ref in
                stageMedia(ref, size: size)
            }
            DirectionPill(direction: model.lockedDirection, action: model.lockedDirection.map { controls.action(for: $0) },
                          ready: model.readyDirection != nil)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, AppSpacing.s)
                .zIndex(2)
            if showHints {
                // Antippen blendet die Hilfe aus. Schleier und Hinweise liegen über der ganzen Ansicht (`feedScene`)
                // und lassen Berührungen durch – Tippen und Wischen landen wie bisher hier auf der Bühne.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { hideHints() }
                    .accessibilityHidden(true)
                    .zIndex(3)
            }
            VStack {
                Spacer()
                if let pill = model.laterPill {
                    LaterPillView(pill: pill) { model.editLater() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let notice = model.notice {
                    NoticePill(text: notice.text).transition(.opacity)
                }
            }
            .padding(.bottom, AppSpacing.l)
            .animation(AppMotion.standard(reduceMotion), value: model.laterPill?.id)
            .animation(AppMotion.standard(reduceMotion), value: model.notice?.id)
            .zIndex(4)
        }
    }

    @ViewBuilder
    private func stageMedia(_ ref: ItemReference, size: CGSize) -> some View {
        if let asset = model.assets[ref.localIdentifier] {
            let top: Bool = ref == model.current
            FeedMediaPage(asset: asset, isTop: top, state: model.previews[ref] ?? .loading,
                          cachedPoster: model.posters[ref],
                          retry: model.retries[ref] ?? 0, intentColor: top ? intentColor : nil,
                          onLoading: { model.previewLoading(ref, hasVisibleContent: $0) },
                          onResult: { result in model.previewResult(ref, result: result) },
                          onRetry: { model.retryPreview(ref) },
                          onSkip: { model.skipWithoutDecision(ref) })
                .scaleEffect(top ? zoom : underScale(size))
                .offset(top ? CGSize(width: model.offset.width + pan.width, height: model.offset.height + pan.height) : .zero)
                .rotationEffect(top && !reduceMotion ? .degrees(model.offset.width / 40) : .zero)
                .opacity(top ? 1 : underOpacity(size))
                .zIndex(top ? 1 : 0)
                .allowsHitTesting(top)
                .accessibilityHidden(!top)
        }
    }

    /// Färbung beim Wischen nach der belegten Aktion (nur Entscheidungen).
    private var intentColor: Color? {
        guard let d = model.readyDirection else { return nil }
        let action = controls.action(for: d)
        return action.isDecision ? FeedActionText.color(action) : nil
    }

    private func reveal(_ size: CGSize) -> CGFloat {
        min(1, max(0, hypot(model.offset.width, model.offset.height) / max(1, size.width * 0.9)))
    }

    private func underOpacity(_ size: CGSize) -> Double { Double(reveal(size)) }

    private func underScale(_ size: CGSize) -> CGFloat { reduceMotion ? 1 : 0.94 + 0.06 * reveal(size) }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { v in
                // Erst ein echter Wisch blendet die Gestenhilfe aus, kein leichtes Aufsetzen oder Zittern.
                if hypot(v.translation.width, v.translation.height) > GestureHintOverlay.dismissDistance { hideHints() }
                if zoomed {
                    pan = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height)
                } else if !voiceOver {
                    model.dragChanged(v.translation)
                }
            }
            .onEnded { v in
                if zoomed {
                    panBase = pan
                } else if !voiceOver {
                    model.dragEnded(v.translation, velocity: v.velocity)
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                model.setSuspended(true)
                zoom = min(5, max(1, zoomBase * v.magnification))
            }
            .onEnded { _ in
                zoomBase = zoom
                if !zoomed { resetZoom() }
            }
    }

    private var tapGestures: some Gesture {
        TapGesture(count: 2).onEnded {
            withAnimation(AppMotion.standard(reduceMotion)) {
                if zoomed { resetZoom() } else { zoom = 2; zoomBase = 2 }
            }
        }
        .exclusively(before: TapGesture(count: 1).onEnded {
            // Tipp aufs Video = Pause/Play. Nie eine Entscheidung.
            if model.currentAsset?.isVideo == true && !zoomed { app.player.togglePlay() }
        })
    }

    private func resetZoom() {
        zoom = 1; zoomBase = 1; pan = .zero; panBase = .zero
        model.setSuspended(voiceOver || showMemory)
    }

    private func flashHints() {
        Diagnostics.log(.feed, "hints-presented")
        hintShownAt = ProcessInfo.processInfo.systemUptime
        withAnimation(.easeOut(duration: 0.2)) { showHints = true }
        hintToken += 1
    }

    /// Ausblenden durch Tippen/Wischen – nicht in der ersten Sekunde (ein noch laufender Tipp vom Öffnen o. Ä.
    /// soll die Hilfe nicht gleich wieder wegnehmen).
    private func hideHints() {
        guard showHints, ProcessInfo.processInfo.systemUptime - hintShownAt >= GestureHintOverlay.minimumVisible else { return }
        withAnimation(.easeOut(duration: 0.2)) { showHints = false }
    }

    // MARK: Aktionsleiste (nie eine Entscheidung)

    private var feedActionButtons: some View {
        let asset = model.currentAsset
        let busy = model.mediaWriteBusy || model.isCommitting
        return GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                let fav = asset?.isFavorite == true
                actionIcon(fav ? "heart.fill" : "heart", icon: .heart, filled: fav, label: L(fav ? "fav_remove" : "fav_add"),
                           tint: fav ? AppColors.cleanup : AppColors.textSecondary, enabled: asset != nil && !busy) {
                    Task { await model.toggleFavorite() }
                }
                .accessibilityValue(Text(key: fav ? "fav_state_on" : "fav_state_off"))
                actionIcon("square.and.arrow.up", icon: .share, label: L("share"), enabled: asset != nil) {
                    guard let a = asset else { return }
                    Task {
                        if let item = await MediaShare.prepare([a.id]) { shareItem = item } else { app.showError(L("share_failed")) }
                    }
                }
                actionIcon("rectangle.stack.badge.plus", icon: .albumAdd, label: L("folder_action"), enabled: asset != nil && !busy) {
                    model.albumSheetFor = asset
                }
                actionIcon("pencil", icon: .pencil, label: L("edit_action"), enabled: asset != nil && !busy) {
                    guard let a = asset else { return }
                    app.player.stop()
                    app.fullScreen = a.isVideo ? .videoEditor(assetID: a.id) : .editor(assetID: a.id)
                }
                Menu {
                    Button { showInfo = true } label: { Label(L("info"), systemImage: "info.circle") }.disabled(asset == nil)
                    Button { flashHints() } label: { Label(L("feed_show_hints"), systemImage: "hand.draw") }
                    Button { showTrash = true } label: { Label(L("feed_view_basket"), systemImage: "trash") }
                    if model.request.isOrderable {
                        Button { showGrid = true } label: { Label(L("grid_open"), systemImage: "square.grid.3x3") }
                    }
                    if case .album = model.request.source {
                        Button { confirmExclude = true } label: { Label(L("excl_action"), systemImage: "eye.slash") }
                    }
                } label: {
                    PMIcon(.more, size: 20)
                        .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text(key: "more_actions"))
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var feedCounters: some View {
        let busy = model.mediaWriteBusy || model.isCommitting
        return HStack(spacing: AppSpacing.xs) {
            if let series = model.currentSeries {
                Button {
                    if app.capabilities.seriesCompare { model.openSeries() } else { app.navigate(.pro); model.close() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.forward.dottedline").foregroundStyle(AppColors.accent)
                        Text(verbatim: "\(series.count)").font(AppTypography.subheadline.weight(.semibold))
                            .monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        if !app.capabilities.seriesCompare { Image(systemName: "crown").font(.caption).foregroundStyle(AppColors.accent) }
                    }
                    .padding(.horizontal, AppSpacing.s)
                    .frame(minHeight: AppSpacing.minTouch)
                }
                .buttonStyle(.plain)
                .glassCapsule(interactive: true)
                .disabled(busy)
                .accessibilityLabel(Text(verbatim: L("series_button", series.count)))
            }
            TrashChip(count: app.read.basket.count) { showTrash = true }
                .accessibilityIdentifier("feed.dock")
                .tourTarget("feed.basket")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func actionIcon(_ symbol: String, icon: PMIconName, filled: Bool = false, label: String,
                            tint: Color = AppColors.textSecondary, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PMIcon(icon, size: 20, filled: filled)
                .foregroundStyle(enabled ? tint : tint.opacity(0.38))
                .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: label))
    }

    // MARK: Texte

    private var protectedTitle: String {
        L(model.protectedFavorite?.isVideo == true ? "fav_protected_video" : "fav_protected_photo")
    }

    private var excludeTitle: String {
        if case .album(_, let title) = model.request.source { return L("excl_confirm_title", title) }
        return ""
    }

    private var infoText: String {
        guard let a = model.currentAsset else { return "" }
        var lines: [String] = []
        if let d = a.creationDate { lines.append(DateText.longWithTime(d)) }
        lines.append("\(a.pixelWidth) × \(a.pixelHeight)")
        if a.isVideo { lines.append(DateText.duration(a.duration)) }
        if let name = PhotoLibraryService.originalFilename(a.id) { lines.append(name) }
        return lines.joined(separator: "\n")
    }

    // MARK: Rundgang (einmal beim ersten Feed)

    private var tourSteps: [TourStep] {
        [TourStep(titleKey: "tour_feed_basket_title", textKey: "tour_feed_basket_text", target: .anchor("feed.basket")),
         TourStep(titleKey: "tour_feed_undo_title", textKey: "tour_feed_undo_text", target: .anchor("feed.undo")),
         TourStep(titleKey: "tour_feed_actions_title", textKey: "tour_feed_actions_text", target: .anchor("feed.actions"))]
    }

    private var activeTourStep: TourStep? {
        guard !app.settings.feedTourSeen, !showHints, model.isLoaded, !model.session.isFinished,
              model.currentAsset != nil, !voiceOver, tourStep < tourSteps.count else { return nil }
        return tourSteps[tourStep]
    }
}

private struct SeriesBox: Identifiable {
    let members: [MediaAsset]
    var id: String { members.map(\.id).joined(separator: ",") }
}
