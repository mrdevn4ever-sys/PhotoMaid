import Foundation
import Observation
import PhotoMaidCore

/// Lokale deklarative Regeln → Review-Aufgaben. Niemals automatische Löschung.
@MainActor
@Observable
final class RulesStore {
    private(set) var rules: [ReviewRule] = []
    private(set) var tasks: [ReviewTask] = []
    private(set) var lastEvaluatedAt: [ReviewRuleID: Date] = [:]
    /// Einmaliger Testscan in der Rewarded-Vorschau (pro Regel).
    private(set) var testScanUsed: Set<ReviewRuleID> = []

    @ObservationIgnored private let store: CoreDataStore
    private struct Persisted: Codable {
        var rules: [ReviewRule] = []
        var tasks: [ReviewTask] = []
        var lastEvaluatedAt: [ReviewRuleID: Date] = [:]
        var testScanUsed: Set<ReviewRuleID> = []
        var firstSeen: [String: Date] = [:]
    }
    @ObservationIgnored private var firstSeen: [String: Date] = [:]
    private static let key = "rules.state"

    init(store: CoreDataStore) {
        self.store = store
        let p = store.value(Persisted.self, forKey: Self.key) ?? Persisted()
        rules = p.rules; tasks = p.tasks; lastEvaluatedAt = p.lastEvaluatedAt
        testScanUsed = p.testScanUsed; firstSeen = p.firstSeen
    }

    private func save() {
        try? store.setValue(Persisted(rules: rules, tasks: tasks, lastEvaluatedAt: lastEvaluatedAt,
                                      testScanUsed: testScanUsed, firstSeen: firstSeen), forKey: Self.key)
    }

    func upsert(_ rule: ReviewRule, reminders: ReminderScheduler) async {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) { rules[i] = rule } else { rules.append(rule) }
        save()
        reminders.removeRuleReminder(ruleID: rule.id)
        if rule.isEnabled, rule.notify, case .weekly(let wd) = rule.trigger {
            await reminders.scheduleRuleReminder(ruleID: rule.id, weekday: wd)
        }
    }

    /// Regel entfernen: zugehörige Reminder und offene Aufgaben entfernen.
    func delete(_ id: ReviewRuleID, reminders: ReminderScheduler) {
        rules.removeAll { $0.id == id }
        tasks.removeAll { $0.ruleID == id }
        lastEvaluatedAt[id] = nil
        reminders.removeRuleReminder(ruleID: id)
        save()
    }

    func dismissTask(_ id: String) {
        tasks.removeAll { $0.id == id }
        save()
    }

    /// Kernprüfung bei Start/Resume. Nur mit dauerhaft aktiven Routinen (Pro).
    func evaluateOnResume(app: AppModel) async {
        guard app.capabilities.persistentRoutines else { return }
        for rule in rules where rule.isEnabled { await run(rule, app: app) }
    }

    /// „Jetzt ausführen“. In der Rewarded-Vorschau genau ein Testscan je Regel.
    func runNow(_ rule: ReviewRule, app: AppModel) async -> Bool {
        let caps = app.capabilities
        if !caps.persistentRoutines {
            guard caps.oneTimeRuleTestScan, !testScanUsed.contains(rule.id) else { return false }
            testScanUsed.insert(rule.id)
        }
        await run(rule, app: app, force: true)
        return true
    }

    private func run(_ rule: ReviewRule, app: AppModel, force: Bool = false) async {
        let inventory = await inventory(for: rule.source, app: app)
        guard !Task.isCancelled else { return }
        let refs = inventory.map(\.item)
        let records = await app.ledger.records(for: refs)
        var existing = Set(tasks.map(\.id))
        if force { existing = [] }
        let now = Date()
        if let task = RuleEvaluator.evaluate(rule, inventory: inventory, records: records, existingTaskIDs: existing,
                                             lastEvaluatedAt: lastEvaluatedAt[rule.id], now: now, timeZone: .autoupdatingCurrent) {
            tasks.removeAll { $0.id == task.id }
            tasks.append(task)
        }
        lastEvaluatedAt[rule.id] = now
        save()
    }

    /// Tatsächlicher, inkrementeller Scan der Quelle (keine erfundenen Fundzahlen).
    private func inventory(for source: RuleSource, app: AppModel) async -> [InventoryItem] {
        let now = Date()
        func seen(_ key: String) -> Date {
            if let d = firstSeen[key] { return d }
            firstSeen[key] = now
            return now
        }
        switch source {
        case .screenshots, .photos, .videos:
            let category: MediaCategory = source == .screenshots ? .screenshots : (source == .videos ? .videos : .photos)
            return app.photos.assets(category).map {
                // Mediengrößen sind ohne Streaming unbekannt (keine private API) → .unknown.
                InventoryItem(item: $0.reference, source: source, createdAt: $0.creationDate,
                              size: .unknown, firstSeenAt: seen($0.id))
            }
        case .connectedSource(let id):
            guard let root = app.sources.beginAccess(id) else { return [] }
            defer { app.sources.endAccess(root) }
            let entries = (try? await Task.detached(priority: .utility) {
                try FileScanner.scan(root: root, sourceID: id)
            }.value) ?? []
            return entries.map {
                InventoryItem(item: $0.reference, source: source, createdAt: $0.created ?? $0.modified,
                              size: $0.size, firstSeenAt: seen($0.reference.description))
            }
        }
    }
}
