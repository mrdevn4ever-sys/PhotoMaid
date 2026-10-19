import Photos
import PhotoMaidCore
import SwiftUI

/// Entscheidungs-Feed. Gesten (fest, tatsächliche Fingerbewegung): hoch = Behalten, links = Papierkorb,
/// rechts (bis 45°) = Später mit Standardtermin, runter = vorheriges Medium (keine Entscheidung).
/// Keine Entscheidungs-Tasten – außer VoiceOver, Schaltersteuerung oder der Bedienungshilfe „Tasten zum Entscheiden“.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @State private var model: FeedViewModel
    @State private var showHints = false
    @State private var hintToken = 0
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
    @GestureState private var dragging = false
    @GestureState private var magnifying = false
    @State private var pinchCancelledDrag = false

    init(request: FeedRequest, app: AppModel) {
        _model = State(initialValue: FeedViewModel(request: request, app: app))
    }

    private var needsButtons: Bool { voiceOver || switchControl || app.settings.decisionButtons }
    private var zoomed: Bool { zoom > 1.01 }
    private var decisionSuspended: Bool { voiceOver || switchControl || zoomed || magnifying || pinchCancelledDrag }

    var body: some View {
        feedSheets
        .alert(protectedTitle, isPresented: Binding(get: { model.protectedFavorite != nil }, set: { if !$0 { model.protectedFavorite = nil } })) {
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

    private var feedContent: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: AppSpacing.s) {
                header
                content
            }
            .padding(.bottom, AppSpacing.xs)
            if let step = activeTourStep { tourCard(step) }
        }
    }

    private var feedLifecycle: some View {
        feedContent
        .task {
            model.reduceMotion = reduceMotion
            model.displayScale = displayScale
            model.setSuspended(decisionSuspended)
            await model.load()
            if !model.session.items.isEmpty && (app.settings.showGestureHintOnOpen || !app.settings.gestureHintSeen) {
                flashHints()
                if !app.settings.gestureHintSeen { app.updateSettings { $0.gestureHintSeen = true } }
            }
        }
        .task(id: hintToken) {
            guard showHints else { return }
            do { try await Task.sleep(for: .seconds(2.6)) } catch { return }
            withAnimation(.easeOut(duration: 0.6)) { showHints = false }
        }
        .onChange(of: reduceMotion) { _, v in model.reduceMotion = v }
        .onChange(of: voiceOver) { _, _ in model.setSuspended(decisionSuspended) }
        .onChange(of: switchControl) { _, _ in model.setSuspended(decisionSuspended) }
        .onChange(of: displayScale) { _, value in model.displayScale = value; model.refreshWindow() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.dragCancelled(); app.player.stop() }
        }
        .onChange(of: zoom) { _, _ in model.setSuspended(decisionSuspended) }
        .onChange(of: magnifying) { _, active in
            if active { pinchCancelledDrag = true; model.dragCancelled() }
            else if !dragging { pinchCancelledDrag = false }
            model.setSuspended(decisionSuspended)
        }
        .onChange(of: model.session.index) { _, _ in resetZoom() }
        .onChange(of: app.library.changeToken) { _, _ in if model.isLoaded { model.refreshWindowAssets() } }
        .onChange(of: dragging) { _, isDragging in
            // Systemabbruch der Geste (Anruf, Mitteilungszentrale): keine Entscheidung.
            if !isDragging, case .dragging = model.machine.phase { model.dragCancelled() }
            if !isDragging, case .directionLocked = model.machine.phase { model.dragCancelled() }
            if !isDragging && !magnifying {
                pinchCancelledDrag = false
                model.setSuspended(decisionSuspended)
            }
        }
        .onDisappear { app.player.stop() }
    }

    private var feedSheets: some View {
        feedLifecycle
        .sheet(item: Binding(get: { model.pickerReceipt }, set: { model.pickerReceipt = $0 })) { receipt in
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
        .sheet(item: Binding(get: { model.customLater }, set: { if $0 == nil, let r = model.customLater { model.customLaterFinished(r, day: nil) } })) { req in
            LaterPickerSheet(initial: model.defaultLaterInterval, today: model.today, allowsNoDate: false) { result in
                if case .day(let d) = result { model.customLaterFinished(req, day: d) } else { model.customLaterFinished(req, day: nil) }
            }
        }
        .sheet(item: Binding(get: { model.albumSheetFor }, set: { model.albumSheetFor = $0 })) { asset in
            AlbumPickerSheet(assetIDs: [asset.id]) { id, title in Task { await model.addCurrent(toAlbum: id, title: title) } }
        }
        .sheet(item: Binding(get: { model.seriesOpen.map(SeriesBox.init) }, set: { model.seriesOpen = $0?.members })) { box in
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

    // MARK: Kopf

    private var header: some View {
        GlassEffectContainer(spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                GlassIconButton(symbol: "xmark", label: L("close")) { model.close() }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(verbatim: model.request.title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    if !model.session.items.isEmpty {
                        let p = model.session.position
                        Text(verbatim: L("feed_position", p.current, p.total))
                            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if model.canReorder && model.isLoaded && !model.session.items.isEmpty {
                    Menu {
                        Picker(L("order_title"), selection: Binding(get: { model.order }, set: { o in Task { await model.setOrder(o) } })) {
                            Text(key: "order_newest").tag(FeedOrder.newest)
                            Text(key: "order_oldest").tag(FeedOrder.oldest)
                            Text(key: "order_largest").tag(FeedOrder.largest)
                            Text(key: "order_random").tag(FeedOrder.random)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body.weight(.semibold))
                            .frame(width: AppSpacing.touch, height: AppSpacing.touch)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text(key: "order_title"))
                }
                GlassIconButton(symbol: "arrow.uturn.backward", label: L("undo")) { Task { await model.undo() } }
                    .disabled(!app.read.canUndo || model.isCommitting)
            }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.top, AppSpacing.xs)
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
            stage
            if let a = model.currentAsset {
                MediaInfoLine(asset: a).padding(.horizontal, AppSpacing.pageMargin)
                if a.isVideo { FeedVideoControls(asset: a).padding(.horizontal, AppSpacing.pageMargin) }
            }
            VStack(spacing: AppSpacing.xs) {
                if needsButtons { DecisionButtons { model.perform($0) } }
                actionBar
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

    private var stage: some View {
        GeometryReader { geo in
            let refs = [model.next, model.current].compactMap { $0 }
            ZStack {
                ForEach(refs, id: \.self) { ref in
                    if let asset = model.assets[ref.localIdentifier] {
                        let top = ref == model.current
                        FeedMediaPage(asset: asset, isTop: top && !model.isCommitting, state: model.previews[ref] ?? .loading,
                                      retry: model.retries[ref] ?? 0, intentColor: top ? intentColor : nil,
                                      onLoading: { model.previewLoading(ref) },
                                      onResult: { ok in model.previewResult(ref, ok: ok) },
                                      onRetry: { model.retryPreview(ref) },
                                      onSkip: { model.skipWithoutDecision() })
                            .scaleEffect(top ? zoom : underScale(geo.size))
                            .offset(top ? CGSize(width: model.offset.width + pan.width, height: model.offset.height + pan.height) : .zero)
                            .rotationEffect(top && !reduceMotion ? .degrees(model.offset.width / 40) : .zero)
                            .opacity(top ? 1 : underOpacity(geo.size))
                            .zIndex(top ? 1 : 0)
                            .allowsHitTesting(top)
                            .accessibilityHidden(!top)
                    }
                }
                DirectionPill(direction: model.lockedDirection, ready: model.readyDirection != nil)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, AppSpacing.s)
                    .zIndex(2)
                if showHints {
                    GestureHintOverlay().transition(.opacity).zIndex(3)
                }
                VStack {
                    Spacer()
                    if let pill = model.laterPill {
                        LaterPillView(pill: pill) { model.editLater() }
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    } else if let notice = model.notice {
                        NoticePill(text: notice.text).transition(.opacity)
                    }
                }
                .padding(.bottom, AppSpacing.l)
                .animation(AppMotion.standard(reduceMotion), value: model.laterPill?.id)
                .animation(AppMotion.standard(reduceMotion), value: model.notice?.id)
                .zIndex(4)
            }
            .contentShape(.rect)
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(tapGestures)
            .onAppear { model.viewSize = geo.size }
            .onChange(of: geo.size) { _, s in model.viewSize = s }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(key: "feed_stage"))
            .accessibilityValue(Text(verbatim: model.currentAsset.map(MediaInfoLine.describe) ?? ""))
            .accessibilityAction(named: Text(key: "act_keep_next")) { model.perform(.keep) }
            .accessibilityAction(named: Text(key: "act_trash")) { model.perform(.markForCleanup) }
            .accessibilityAction(named: Text(key: "act_later")) { model.perform(.later) }
            .accessibilityAction(named: Text(key: "act_later_custom")) { model.perform(.laterCustom) }
            .accessibilityAction(named: Text(key: "act_previous")) { model.perform(.previous) }
            .accessibilityAction(named: Text(key: "undo")) { Task { await model.undo() } }
            .accessibilityAction(named: Text(key: "feed_view_basket")) { showTrash = true }
        }
        .padding(.horizontal, AppSpacing.xs)
    }

    private var intentColor: Color? {
        switch model.readyDirection.map(FeedIntent.init) {
        case .keep: AppColors.keep
        case .markForCleanup: AppColors.cleanup
        case .later, .laterCustom: AppColors.later
        default: nil
        }
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
                hideHints()
                guard !magnifying, !pinchCancelledDrag else { model.dragCancelled(); return }
                if zoomed {
                    pan = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height)
                } else if !voiceOver {
                    model.dragChanged(v.translation)
                }
            }
            .onEnded { v in
                guard !magnifying, !pinchCancelledDrag else { model.dragCancelled(); return }
                if zoomed {
                    panBase = pan
                } else if !voiceOver {
                    model.dragEnded(v.translation, velocity: v.velocity)
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($magnifying) { _, state, _ in state = true }
            .onChanged { v in
                pinchCancelledDrag = true
                model.setSuspended(true)
                zoom = min(5, max(1, zoomBase * v.magnification))
            }
            .onEnded { _ in
                zoomBase = zoom
                if !zoomed { resetZoom() }
                model.setSuspended(decisionSuspended)
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
        model.setSuspended(decisionSuspended)
    }

    private func flashHints() {
        withAnimation(.easeOut(duration: 0.2)) { showHints = true }
        hintToken += 1
    }

    private func hideHints() {
        if showHints { withAnimation(.easeOut(duration: 0.2)) { showHints = false } }
    }

    // MARK: Aktionsleiste (nie eine Entscheidung)

    private var actionBar: some View {
        let asset = model.currentAsset
        let busy = model.mediaWriteBusy || model.isCommitting
        return HStack(spacing: AppSpacing.xs) {
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    let fav = asset?.isFavorite == true
                    actionIcon(fav ? "heart.fill" : "heart", label: L(fav ? "fav_remove" : "fav_add"),
                               tint: fav ? AppColors.cleanup : AppColors.textPrimary, enabled: asset != nil && !busy) {
                        Task { await model.toggleFavorite() }
                    }
                    .accessibilityValue(Text(key: fav ? "fav_state_on" : "fav_state_off"))
                    actionIcon("square.and.arrow.up", label: L("share"), enabled: asset != nil) {
                        guard let a = asset else { return }
                        Task {
                            if let item = await MediaShare.prepare([a.id]) { shareItem = item } else { app.showError(L("share_failed")) }
                        }
                    }
                    actionIcon("rectangle.stack.badge.plus", label: L("folder_action"), enabled: asset != nil && !busy) {
                        model.albumSheetFor = asset
                    }
                    actionIcon("pencil", label: L("edit_action"), enabled: asset != nil && !busy) {
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
                        Image(systemName: "ellipsis")
                            .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(Text(key: "more_actions"))
                    .foregroundStyle(AppColors.textPrimary)
                }
                .padding(.horizontal, AppSpacing.xxs)
                .glassCapsule()
            }
            if let series = model.currentSeries {
                Button {
                    if app.capabilities.seriesCompare { model.openSeries() } else { app.navigate(.pro); model.close() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.forward.dottedline").foregroundStyle(AppColors.accent)
                        Text(verbatim: "\(series.count)").font(AppTypography.subheadline.weight(.semibold))
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
            Spacer(minLength: 0)
            TrashChip(count: app.read.basket.count) { showTrash = true }
        }
    }

    private func actionIcon(_ symbol: String, label: String, tint: Color = AppColors.textPrimary, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
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

    private var tourSteps: [(key: String, text: String)] {
        [("tour_feed_basket_title", "tour_feed_basket_text"),
         ("tour_feed_undo_title", "tour_feed_undo_text"),
         ("tour_feed_actions_title", "tour_feed_actions_text")]
    }

    private var activeTourStep: (key: String, text: String)? {
        guard !app.settings.feedTourSeen, !showHints, model.isLoaded, !model.session.isFinished,
              model.currentAsset != nil, !voiceOver, tourStep < tourSteps.count else { return nil }
        return tourSteps[tourStep]
    }

    private func tourCard(_ step: (key: String, text: String)) -> some View {
        CoachCard(title: L(step.key), text: L(step.text), isLast: tourStep == tourSteps.count - 1) {
            if tourStep >= tourSteps.count - 1 {
                app.updateSettings { $0.feedTourSeen = true }
            } else {
                tourStep += 1
            }
        } skip: {
            app.updateSettings { $0.feedTourSeen = true }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 120)
    }
}

private struct SeriesBox: Identifiable {
    let members: [MediaAsset]
    var id: String { members.map(\.id).joined(separator: ",") }
}
