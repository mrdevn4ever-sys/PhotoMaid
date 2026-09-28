import PhotoMaidCore
import SwiftUI

/// Vertikaler Entscheidungs-Feed (Screens 2 und 3).
/// HOCH = Behalten · LINKS = Vormerken · RECHTS = Später · RUNTER = Zurück.
struct ReviewFeedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.displayScale) private var displayScale
    @State private var model: FeedViewModel?
    @State private var showBasket = false
    @State private var showHints = false
    @State private var customDateItem: LaterReceipt?
    @State private var zoomed = false
    let request: FeedRequest

    var body: some View {
        ZStack {
            AppBackground()
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .task {
            let m = FeedViewModel(request: request, app: app)
            model = m
            await m.load()
            showHints = !app.settings.gestureHintSeen && !m.session.items.isEmpty
        }
        .onDisappear { app.player.stop() }
        .sheet(isPresented: $showBasket) {
            NavigationStack { CleanupBasketView() }.environment(app)
        }
    }

    @ViewBuilder
    private func content(_ model: FeedViewModel) -> some View {
        VStack(spacing: AppSpacing.s) {
            header(model)
            if !model.isLoaded {
                Spacer(); ProgressView(); Spacer()
            } else if model.session.items.isEmpty {
                EmptyState(symbol: "checkmark.circle", title: "Nichts zu prüfen",
                           message: "In dieser Auswahl warten gerade keine Elemente auf eine Entscheidung.",
                           actionTitle: "Schließen", action: { dismiss() })
            } else if model.session.isFinished {
                SessionSummaryView(summary: model.session.summary,
                                   basketCount: app.basket.count,
                                   reviewBasket: { showBasket = true },
                                   goBack: { model.perform(.previous, reduceMotion: reduceMotion) },
                                   done: { dismiss() })
            } else {
                mediaStage(model)
                bottomZone(model)
            }
        }
        .padding(.bottom, AppSpacing.xs)
        .sensoryFeedback(.impact(weight: .light), trigger: model.commitCount) { _, _ in app.settings.haptics }
        .sensoryFeedback(.warning, trigger: model.bumpCount) { _, _ in app.settings.haptics }
        .alert("Hinweis", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(item: $customDateItem) { receipt in
            LaterDateSheet(title: "Wunschdatum wählen") { day in
                Task { await model.schedule(day) }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func header(_ model: FeedViewModel) -> some View {
        GlassToolbar(title: request.title,
                     subtitle: model.session.items.isEmpty ? nil
                        : "\(model.session.position.current) von \(model.session.position.total)") {
            GlassIconButton(symbol: "xmark", label: "Schließen") { dismiss() }
        } trailing: {
            Menu {
                Button("Rückgängig", systemImage: "arrow.uturn.backward") { Task { await model.undo() } }
                    .disabled(!app.canUndo)
                Button("Auswahl prüfen", systemImage: "trash") { showBasket = true }
                Button("Gestenhilfe anzeigen", systemImage: "hand.draw") { showHints = true }
            } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold))
                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Weitere Aktionen"))
        }
    }

    // MARK: Medium

    private func mediaStage(_ model: FeedViewModel) -> some View {
        GeometryReader { geo in
            let item = model.current
            ZStack {
                if let item, let asset = model.currentAsset {
                    MediaPage(asset: asset, preview: model.previews[item] ?? .loading,
                              zoomed: $zoomed, skip: { model.skipWithoutDecision() })
                        .id(item)
                        .offset(model.offset)
                        .rotationEffect(.degrees(reduceMotion ? 0 : Double(model.offset.width / 40)))
                        .overlay { directionTint(model) }
                }
                if showHints {
                    GestureHintOverlay { showHints = false; app.updateSettings { $0.gestureHintSeen = true } }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect)
            .gesture(feedDrag(model), including: gestureEnabled ? .all : .subviews)
            .onAppear {
                model.viewSize = geo.size
                model.displayScale = displayScale
                model.refreshWindow()
            }
            .onChange(of: geo.size) { _, s in model.viewSize = s; model.refreshWindow() }
            .onChange(of: zoomed) { _, z in model.machine.isSuspended = z || voiceOver }
            .onChange(of: voiceOver, initial: true) { _, v in model.machine.isSuspended = v || zoomed }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Aktuelles Medium"))
        // Zugängliche Aktionen zusätzlich zu Gesten. Keine Scroll-Aktion (verhindert unbemerktes Vormerken).
        .accessibilityAction(named: Text("Behalten und weiter")) { model.perform(.keep, reduceMotion: true) }
        .accessibilityAction(named: Text("Zur Bereinigung vormerken")) { model.perform(.markForCleanup, reduceMotion: true) }
        .accessibilityAction(named: Text("Später")) { model.perform(.later, reduceMotion: true) }
        .accessibilityAction(named: Text("Vorheriges")) { model.perform(.previous, reduceMotion: true) }
        .accessibilityAction(named: Text("Rückgängig")) { Task { await model.undo() } }
        .accessibilityAction(named: Text("Auswahl prüfen")) { showBasket = true }
    }

    private var gestureEnabled: Bool { !zoomed && !voiceOver && !showHints }

    private func feedDrag(_ model: FeedViewModel) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { v in model.dragChanged(v.translation) }
            .onEnded { v in model.dragEnded(v.translation, velocity: v.velocity, reduceMotion: reduceMotion) }
    }

    /// Dezente Richtungsfarbe während der Bewegung (keine permanente Überdeckung).
    @ViewBuilder
    private func directionTint(_ model: FeedViewModel) -> some View {
        if let d = model.machine.lockedDirection {
            let (color, label, symbol): (Color, LocalizedStringKey, String) = switch FeedIntent(d) {
            case .keep: (AppColors.keep, "Behalten", "arrow.up")
            case .markForCleanup: (AppColors.cleanup, "Vormerken", "arrow.left")
            case .later: (AppColors.later, "Später", "arrow.right")
            case .previous: (AppColors.textSecondary, "Zurück", "arrow.down")
            }
            Label(label, systemImage: symbol)
                .font(AppTypography.headline)
                .padding(.horizontal, AppSpacing.m).padding(.vertical, AppSpacing.xs)
                .foregroundStyle(color)
                .glassCapsule()
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: Untere Bedienzone (stabile Höhe, kein Layoutspringen)

    private func bottomZone(_ model: FeedViewModel) -> some View {
        VStack(spacing: AppSpacing.xs) {
            ZStack {
                if let receipt = model.session.receipt {
                    LaterReceiptBar(receipt: receipt, today: app.today,
                                    choose: { day in Task { await model.schedule(day) } },
                                    more: { customDateItem = receipt },
                                    close: { model.dismissReceipt() })
                        .transition(.opacity)
                }
            }
            .frame(height: 84)
            .animation(AppMotion.standard(reduceMotion), value: model.session.receipt?.id)

            CompactActions(canUndo: app.canUndo,
                           act: { model.perform($0, reduceMotion: reduceMotion) },
                           undo: { Task { await model.undo() } })

            ReviewDock(count: app.basket.count, sizeText: nil) { showBasket = true }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }
}

/// Kompakte native Controls (zusätzlich zu Gesten). Keine sechs riesigen Buttons.
struct CompactActions: View {
    let canUndo: Bool
    let act: (FeedIntent) -> Void
    let undo: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                button("arrow.down", "Vorheriges", AppColors.textSecondary) { act(.previous) }
                button("arrow.left", "Vormerken", AppColors.cleanup) { act(.markForCleanup) }
                button("arrow.up", "Behalten und weiter", AppColors.keep) { act(.keep) }
                button("arrow.right", "Später", AppColors.later) { act(.later) }
                button("arrow.uturn.backward", "Rückgängig", AppColors.textSecondary, action: undo)
                    .disabled(!canUndo)
            }
        }
    }

    private func button(_ symbol: String, _ label: LocalizedStringKey, _ tint: Color,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: AppSpacing.minTouch)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(Text(label))
    }
}

/// Terminleiste nach Swipe rechts: Morgen · 7 Tage · 30 Tage · …
struct LaterReceiptBar: View {
    let receipt: LaterReceipt
    let today: LocalDay
    let choose: (LocalDay) -> Void
    let more: () -> Void
    let close: () -> Void

    var body: some View {
        StatusReceipt(message: Text("Zurückgestellt. Wann wieder zeigen?")) {
            ForEach(LaterPreset.allCases, id: \.self) { preset in
                Button(label(preset)) { choose(preset.dueDay(from: today)) }
                    .buttonStyle(.glass)
            }
            Button("…", action: more).buttonStyle(.glass).accessibilityLabel(Text("Anderes Datum"))
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.glass).accessibilityLabel(Text("Leiste schließen"))
        }
    }

    private func label(_ p: LaterPreset) -> LocalizedStringKey {
        switch p {
        case .tomorrow: "Morgen"
        case .sevenDays: "7 Tage"
        case .thirtyDays: "30 Tage"
        }
    }
}

struct LaterDateSheet: View {
    let title: LocalizedStringKey
    let confirm: (LocalDay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $date, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(Text(title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            confirm(LocalDay(date, timeZone: .autoupdatingCurrent))
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// Einstiegshilfe: vier Richtungen einmal erklären. Über Einstellungen erneut abrufbar.
struct GestureHintOverlay: View {
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: AppSpacing.l) {
                hint("arrow.up", "Wisch nach oben", "Behalten + weiter", AppColors.keep)
                HStack(spacing: AppSpacing.l) {
                    hint("arrow.left", "Wisch nach links", "Vormerken", AppColors.cleanup)
                    hint("arrow.right", "Wisch nach rechts", "Später", AppColors.later)
                }
                hint("arrow.down", "Wisch nach unten", "Vorheriges", AppColors.textSecondary)
                Button("Verstanden", action: done).buttonStyle(.glassProminent).controlSize(.large)
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
    }

    private func hint(_ symbol: String, _ title: LocalizedStringKey, _ meaning: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title2.weight(.bold)).foregroundStyle(tint)
            Text(title).font(AppTypography.caption)
            Text(meaning).font(AppTypography.subheadline.weight(.semibold)).foregroundStyle(tint)
        }
        .padding(AppSpacing.s)
        .frame(minWidth: 120)
        .glassEffect(.regular, in: .rect(cornerRadius: AppRadii.card))
        .accessibilityElement(children: .combine)
    }
}

struct SessionSummaryView: View {
    let summary: SessionSummary
    let basketCount: Int
    let reviewBasket: () -> Void
    let goBack: () -> Void
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(AppColors.accent)
                    .accessibilityHidden(true)
                Text("Durchgang abgeschlossen").font(AppTypography.title)
                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        row("arrow.up", "Behalten", summary.kept, AppColors.keep)
                        row("arrow.left", "Vorgemerkt", summary.marked, AppColors.cleanup)
                        row("arrow.right", "Später", summary.later, AppColors.later)
                    }
                }
                if basketCount > 0 {
                    Button(action: reviewBasket) {
                        Text("Auswahl prüfen (\(basketCount))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    Text("Es wird nichts gelöscht, bevor du die Auswahl prüfst und bestätigst.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
                }
                Button("Zum letzten Element", action: goBack).buttonStyle(.glass)
                Button("Fertig", action: done).buttonStyle(.glass)
            }
            .padding(AppSpacing.pageMargin)
        }
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ n: Int, _ tint: Color) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 28).accessibilityHidden(true)
            Text(title)
            Spacer()
            Text("\(n)").font(AppTypography.headline).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
