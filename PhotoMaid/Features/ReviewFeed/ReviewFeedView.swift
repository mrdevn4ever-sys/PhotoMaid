import PhotoMaidCore
import SwiftUI

/// Vertikaler Entscheidungs-Feed (Screens 2 und 3).
/// HOCH = Behalten · LINKS = Papierkorb · RECHTS = Später (Standardtermin) ·
/// SCHRÄG RECHTS OBEN = Später mit Drehrad · RUNTER = Zurück.
struct ReviewFeedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @Environment(\.displayScale) private var displayScale
    @State private var model: FeedViewModel?
    @State private var showBasket = false
    @State private var showHints = false
    @State private var hintToken = 0
    @State private var showInfo = false
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
            if app.settings.showGestureHintOnOpen && !m.session.items.isEmpty { flashHints() }
        }
        .onDisappear { app.player.stop() }
        .sheet(isPresented: $showBasket) {
            NavigationStack { CleanupBasketView(showsDone: true) }.environment(app)
        }
    }

    /// Gestenhilfe kurz einblenden und von selbst ausblenden. Blockiert keine Geste.
    private func flashHints() {
        hintToken += 1
        let token = hintToken
        withAnimation(AppMotion.standard(reduceMotion) ?? .default) { showHints = true }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if hintToken == token { withAnimation(.easeOut(duration: 0.6)) { showHints = false } }
        }
    }

    private func hideHints() {
        guard showHints else { return }
        hintToken += 1
        withAnimation(.easeOut(duration: 0.25)) { showHints = false }
    }

    /// Mit VoiceOver oder Schaltersteuerung bleiben die Aktions-Buttons sichtbar.
    private var needsButtons: Bool { voiceOver || switchControl }

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
        .alert("Infos", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: { Text(infoText(model)) }
        .sheet(item: Binding(get: { model.pickerReceipt }, set: { model.pickerReceipt = $0 })) { receipt in
            LaterPickerSheet(initial: model.defaultLaterInterval, today: app.today) { day in
                Task { await model.pickerFinished(receipt, day: day) }
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled()
        }
    }

    private func infoText(_ model: FeedViewModel) -> String {
        guard let a = model.currentAsset else { return "" }
        var parts: [String] = []
        if let d = a.creationDate { parts.append(d.formatted(date: .long, time: .shortened)) }
        parts.append("\(a.pixelWidth) × \(a.pixelHeight)")
        if a.kind == .video { parts.append(Duration.seconds(a.duration).formatted(.time(pattern: .minuteSecond))) }
        return parts.joined(separator: "\n")
    }

    private func header(_ model: FeedViewModel) -> some View {
        GlassToolbar(title: request.title,
                     subtitle: model.session.items.isEmpty ? nil
                        : "\(model.session.position.current) von \(model.session.position.total)") {
            GlassIconButton(symbol: "xmark", label: "Schließen") { dismiss() }
        } trailing: {
            HStack(spacing: AppSpacing.xs) {
                GlassIconButton(symbol: "arrow.uturn.backward", label: "Rückgängig") { Task { await model.undo() } }
                    .disabled(!app.canUndo)
                    .opacity(app.canUndo ? 1 : 0.45)
                Menu {
                    Button("Papierkorb ansehen", systemImage: "trash") { showBasket = true }
                    Button("Infos", systemImage: "info.circle") { showInfo = true }
                        .disabled(model.currentAsset == nil)
                    Button("Gestenhilfe zeigen", systemImage: "hand.draw") { flashHints() }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold))
                        .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Weitere Aktionen"))
            }
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
                    GestureHintOverlay()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if let pill = model.laterPill {
                    VStack {
                        Spacer()
                        LaterPillView(pill: pill) { model.editLater() }
                            .padding(.bottom, AppSpacing.l)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AppMotion.standard(reduceMotion), value: model.laterPill?.id)
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
        .accessibilityIdentifier("feed.stage")
        // Zugängliche Aktionen zusätzlich zu Gesten. Keine Scroll-Aktion (verhindert unbemerkte Entscheidungen).
        .accessibilityAction(named: Text("Behalten und weiter")) { model.perform(.keep, reduceMotion: true) }
        .accessibilityAction(named: Text("In den Papierkorb")) { model.perform(.markForCleanup, reduceMotion: true) }
        .accessibilityAction(named: Text("Später")) { model.perform(.later, reduceMotion: true) }
        .accessibilityAction(named: Text("Später, Datum wählen")) { model.perform(.laterCustom, reduceMotion: true) }
        .accessibilityAction(named: Text("Vorheriges")) { model.perform(.previous, reduceMotion: true) }
        .accessibilityAction(named: Text("Rückgängig")) { Task { await model.undo() } }
        .accessibilityAction(named: Text("Papierkorb ansehen")) { showBasket = true }
    }

    private var gestureEnabled: Bool { !zoomed && !voiceOver }

    private func feedDrag(_ model: FeedViewModel) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { v in hideHints(); model.dragChanged(v.translation) }
            .onEnded { v in model.dragEnded(v.translation, velocity: v.velocity, reduceMotion: reduceMotion) }
    }

    /// Dezente Richtungsfarbe während der Bewegung (keine permanente Überdeckung).
    @ViewBuilder
    private func directionTint(_ model: FeedViewModel) -> some View {
        if let d = model.machine.lockedDirection {
            let (color, label, symbol): (Color, LocalizedStringKey, String) = switch FeedIntent(d) {
            case .keep: (AppColors.keep, "Behalten", "arrow.up")
            case .markForCleanup: (AppColors.cleanup, "Papierkorb", "trash")
            case .later: (AppColors.later, "Später", "arrow.right")
            case .laterCustom: (AppColors.later, "Später · Datum wählen", "arrow.up.right")
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

    // MARK: Untere Zone

    private func bottomZone(_ model: FeedViewModel) -> some View {
        VStack(spacing: AppSpacing.xs) {
            if needsButtons {
                CompactActions(act: { model.perform($0, reduceMotion: reduceMotion) })
            }
            ReviewDock(count: app.basket.count, sizeText: nil) { showBasket = true }
                .accessibilityIdentifier("feed.dock")
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }
}

/// Aktions-Buttons nur für VoiceOver/Schaltersteuerung (sonst reine Gestenbedienung).
struct CompactActions: View {
    let act: (FeedIntent) -> Void

    var body: some View {
        GlassEffectContainer(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                button("arrow.down", "Vorheriges", AppColors.textSecondary) { act(.previous) }
                button("trash", "In den Papierkorb", AppColors.cleanup) { act(.markForCleanup) }
                button("arrow.up", "Behalten und weiter", AppColors.keep) { act(.keep) }
                button("arrow.right", "Später", AppColors.later) { act(.later) }
                button("calendar", "Später, Datum wählen", AppColors.later) { act(.laterCustom) }
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

/// Kleine Glas-Pille nach „Später“: „In 2 Tagen wieder · Ändern“.
struct LaterPillView: View {
    let pill: LaterPill
    let edit: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(AppColors.later)
                .accessibilityHidden(true)
            Text(LaterText.inInterval(pill.interval))
                .font(AppTypography.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            Button("Ändern", action: edit)
                .font(AppTypography.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accent)
                .frame(minHeight: AppSpacing.minTouch)
                .accessibilityIdentifier("later.edit")
        }
        .padding(.horizontal, AppSpacing.m)
        .glassCapsule(interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("later.pill")
    }
}

enum LaterText {
    static func inInterval(_ i: LaterInterval) -> String {
        switch i.unit {
        case .days: i.value == 1 ? String(localized: "Morgen wieder") : String(localized: "In \(i.value) Tagen wieder")
        case .weeks: i.value == 1 ? String(localized: "In 1 Woche wieder") : String(localized: "In \(i.value) Wochen wieder")
        case .months: i.value == 1 ? String(localized: "In 1 Monat wieder") : String(localized: "In \(i.value) Monaten wieder")
        }
    }

    static func unit(_ u: LaterInterval.Unit, _ n: Int) -> String {
        switch u {
        case .days: n == 1 ? String(localized: "Tag") : String(localized: "Tage")
        case .weeks: n == 1 ? String(localized: "Woche") : String(localized: "Wochen")
        case .months: n == 1 ? String(localized: "Monat") : String(localized: "Monate")
        }
    }
}

/// Drehrad im Apple-Stil wie beim Timer: „In [n] [Tagen | Wochen | Monaten]“,
/// optional ein bestimmtes Datum im Kalender. Abbrechen = Standardtermin.
struct LaterPickerSheet: View {
    let today: LocalDay
    let finish: (LocalDay?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: Int
    @State private var unit: LaterInterval.Unit
    @State private var useDate = false
    @State private var date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    init(initial: LaterInterval, today: LocalDay, finish: @escaping (LocalDay?) -> Void) {
        self.today = today
        self.finish = finish
        _value = State(initialValue: initial.value)
        _unit = State(initialValue: initial.unit)
    }

    private var interval: LaterInterval { LaterInterval(value: value, unit: unit) }
    private var resultDay: LocalDay { useDate ? LocalDay(date, timeZone: .autoupdatingCurrent) : interval.dueDay(from: today) }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.m) {
                if useDate {
                    DatePicker("Datum", selection: $date, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } else {
                    HStack(spacing: 0) {
                        Picker("Anzahl", selection: $value) {
                            ForEach(Array(LaterInterval.range(for: unit)), id: \.self) { n in Text("\(n)").tag(n) }
                        }
                        .pickerStyle(.wheel)
                        Picker("Einheit", selection: $unit) {
                            ForEach(LaterInterval.Unit.allCases, id: \.self) { u in Text(LaterText.unit(u, value)).tag(u) }
                        }
                        .pickerStyle(.wheel)
                    }
                    .onChange(of: unit) { _, u in value = min(value, LaterInterval.range(for: u).upperBound) }
                }
                Text("Wieder zeigen am \(DayText.string(resultDay))")
                    .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                Button(useDate ? "Abstand wählen" : "Bestimmtes Datum …") {
                    withAnimation { useDate.toggle() }
                }
                .buttonStyle(.glass)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(Text("Später"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { finish(nil); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { finish(resultDay); dismiss() }
                }
            }
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

/// Gestenhilfe: erscheint beim Öffnen kurz, blendet von selbst aus, blockiert nichts.
struct GestureHintOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.18).accessibilityHidden(true)
            VStack(spacing: AppSpacing.m) {
                hint("arrow.up", "Hoch", "Behalten", AppColors.keep)
                HStack(spacing: AppSpacing.m) {
                    hint("arrow.left", "Links", "Papierkorb", AppColors.cleanup)
                    VStack(spacing: AppSpacing.s) {
                        hint("arrow.up.right", "Schräg hoch", "Später, Datum wählen", AppColors.later)
                        hint("arrow.right", "Rechts", "Später", AppColors.later)
                    }
                }
                hint("arrow.down", "Runter", "Zurück", AppColors.textSecondary)
            }
            .padding()
        }
        .clipShape(.rect(cornerRadius: AppRadii.sheet))
        .accessibilityHidden(true) // Bedienung per VoiceOver über die Aktionen, nicht über das Overlay
    }

    private func hint(_ symbol: String, _ title: LocalizedStringKey, _ meaning: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(tint)
            Text(title).font(AppTypography.caption)
            Text(meaning).font(AppTypography.caption.weight(.semibold)).foregroundStyle(tint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppSpacing.s).padding(.vertical, AppSpacing.xs)
        .frame(minWidth: 116)
        .glassEffect(.regular, in: .rect(cornerRadius: AppRadii.card))
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
                        row("trash", "Im Papierkorb", summary.marked, AppColors.cleanup)
                        row("arrow.right", "Später", summary.later, AppColors.later)
                    }
                }
                if basketCount > 0 {
                    Button(action: reviewBasket) {
                        Text("Papierkorb ansehen (\(basketCount))").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    Text("Gelöscht wird erst, wenn du den Papierkorb leerst und bestätigst.")
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
