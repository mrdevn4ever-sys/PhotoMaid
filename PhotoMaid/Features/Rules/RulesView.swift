import PhotoMaidCore
import SwiftUI

/// Screen 12 – Regeln & Routinen. Erstellen, Bearbeiten, Pausieren, Löschen, Jetzt ausführen.
/// Regeln erzeugen immer Review-Aufgaben, niemals automatische Löschung.
struct RulesView: View {
    @Environment(AppModel.self) private var app
    let openFeed: (FeedRequest) -> Void
    @State private var editing: ReviewRule?
    @State private var showPro = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Text("Einrichten und vergessen. PhotoMaid arbeitet auf deinem Gerät und erstellt nur Prüfaufgaben.")
                    .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                if !app.capabilities.persistentRoutines {
                    Label(app.capabilities.oneTimeRuleTestScan
                          ? "In der Pro-Vorschau ist je Regel ein einmaliger Testlauf möglich."
                          : "Dauerhaft aktive Routinen sind Teil von PhotoMaid Pro. Regeln kannst du trotzdem anlegen.",
                          systemImage: "info.circle")
                        .font(AppTypography.caption)
                    Button("PhotoMaid Pro ansehen") { showPro = true }
                }
            }
            Section {
                ForEach(app.rules.rules) { rule in
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Toggle(isOn: Binding(get: { rule.isEnabled }, set: { on in
                            var r = rule; r.isEnabled = on
                            Task { await app.rules.upsert(r, reminders: app.reminders) }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RuleText.title(rule)).font(AppTypography.headline)
                                Text(RuleText.detail(rule)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        HStack {
                            Button("Jetzt ausführen") {
                                Task {
                                    let ok = await app.rules.runNow(rule, app: app)
                                    message = ok ? String(localized: "Prüfung abgeschlossen. Neue Aufgaben findest du unter Ordnen.")
                                                 : String(localized: "Für diese Regel ist aktuell kein Lauf möglich.")
                                }
                            }
                            .buttonStyle(.glass)
                            Button("Bearbeiten") { editing = rule }.buttonStyle(.glass)
                        }
                    }
                    .swipeActions {
                        Button("Löschen", role: .destructive) { app.rules.delete(rule.id, reminders: app.reminders) }
                    }
                }
                Button("Neue Regel hinzufügen", systemImage: "plus") {
                    editing = ReviewRule(source: .screenshots, filter: .olderThan(days: 30), trigger: .daily)
                }
            }
            Section {
                Label("Alle Regeln laufen lokal. Hintergrundausführung ist von iOS nicht garantiert; die Prüfung erfolgt sicher beim Öffnen der App.",
                      systemImage: "checkmark.shield")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Regeln & Routinen"))
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, sources: app.sources.sources) { r in
                Task { await app.rules.upsert(r, reminders: app.reminders) }
            }
        }
        .sheet(isPresented: $showPro) { NavigationStack { ProView() }.environment(app) }
        .alert("Hinweis", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}

enum RuleText {
    static func title(_ r: ReviewRule) -> String {
        let source: String = switch r.source {
        case .screenshots: String(localized: "Screenshots")
        case .photos: String(localized: "Fotos")
        case .videos: String(localized: "Videos")
        case .connectedSource: String(localized: "Verbundener Ordner")
        }
        switch r.filter {
        case .olderThan(let d): return String(localized: "\(source) älter als \(d) Tage prüfen")
        case .knownSizeAtLeast(let b): return String(localized: "\(source) ab \(SizeText.bytes(b)) zeigen")
        case .all: return String(localized: "\(source) prüfen")
        }
    }

    static func detail(_ r: ReviewRule) -> String {
        switch r.trigger {
        case .daily: return String(localized: "Täglich beim Öffnen – erstellt eine Prüfaufgabe")
        case .weekly(let wd):
            let name = Calendar.current.weekdaySymbols[(wd - 1) % 7]
            return String(localized: "Jeden \(name) – erstellt eine Prüfaufgabe")
        case .newlyDiscovered(let n):
            return String(localized: "Sobald \(n) neu entdeckte Elemente warten")
        }
    }
}

struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: ReviewRule
    let sources: [ConnectedSource]
    let save: (ReviewRule) -> Void
    @State private var days = 30
    @State private var sizeMB = 1000
    @State private var filterKind = 0
    @State private var triggerKind = 0
    @State private var weekday = 1
    @State private var count = 10

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quelle", selection: $rule.source) {
                    Text("Screenshots").tag(RuleSource.screenshots)
                    Text("Fotos").tag(RuleSource.photos)
                    Text("Videos").tag(RuleSource.videos)
                    ForEach(sources) { s in Text(s.displayName).tag(RuleSource.connectedSource(s.id)) }
                }
                Picker("Filter", selection: $filterKind) {
                    Text("Älter als …").tag(0)
                    Text("Bekannte Größe ab …").tag(1)
                    Text("Alle").tag(2)
                }
                if filterKind == 0 { Stepper("\(days) Tage", value: $days, in: 1...3650) }
                if filterKind == 1 { Stepper("\(sizeMB) MB", value: $sizeMB, in: 10...100_000, step: 100) }
                Picker("Auslöser", selection: $triggerKind) {
                    Text("Täglich").tag(0)
                    Text("Wöchentlich").tag(1)
                    Text("Nach neu entdeckten Elementen").tag(2)
                }
                if triggerKind == 1 {
                    Picker("Wochentag", selection: $weekday) {
                        ForEach(1...7, id: \.self) { d in Text(Calendar.current.weekdaySymbols[d - 1]).tag(d) }
                    }
                    Toggle("Erinnerung senden", isOn: $rule.notify)
                }
                if triggerKind == 2 { Stepper("\(count) Elemente", value: $count, in: 1...500) }
                Section {
                    Text("Regeln erzeugen nur Prüfaufgaben. Es wird nie automatisch gelöscht.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
            .navigationTitle(Text("Regel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        rule.filter = [RuleFilter.olderThan(days: days), .knownSizeAtLeast(bytes: Int64(sizeMB) * 1_000_000), .all][filterKind]
                        rule.trigger = [RuleTrigger.daily, .weekly(weekday: weekday), .newlyDiscovered(count: count)][triggerKind]
                        save(rule)
                        dismiss()
                    }
                }
            }
            .onAppear {
                switch rule.filter {
                case .olderThan(let d): filterKind = 0; days = d
                case .knownSizeAtLeast(let b): filterKind = 1; sizeMB = Int(b / 1_000_000)
                case .all: filterKind = 2
                }
                switch rule.trigger {
                case .daily: triggerKind = 0
                case .weekly(let w): triggerKind = 1; weekday = w
                case .newlyDiscovered(let n): triggerKind = 2; count = n
                }
            }
        }
    }
}
