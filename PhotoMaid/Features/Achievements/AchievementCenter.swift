import Foundation
import Observation
import PhotoMaidCore

/// Gespeicherte Abzeichen: einmal erreicht, bleibt erreicht. `at` nil = vor Beginn der Aufzeichnung erreicht.
struct AchievementStoreState: Codable, Sendable, Equatable {
    struct Stamp: Codable, Sendable, Equatable { var at: Date? }
    var initialized = false
    var earned: [String: Stamp] = [:]
}

/// Zeitpunkt eines Bestwerts (nur Zahlen). `at` nil = Bestwert stammt aus der Zeit vor der Aufzeichnung.
struct GameRecordStamp: Codable, Sendable, Hashable {
    var value: Double
    var at: Date?
}

/// Abzeichen und Bestwert-Zeitpunkte (Gamification, Nutzerentscheidung 21.10.2026). Rechnet nur mit echten Daten aus
/// Ledger, Mediathek, Spielen und „Bearbeitet“. Löst nie eine Entscheidung aus.
@MainActor @Observable
final class AchievementCenter {
    private(set) var states: [AchievementID: AchievementState] = [:]
    private(set) var store: AchievementStoreState
    private(set) var recordStamps: [String: GameRecordStamp]
    @ObservationIgnored private let kv: KeyValueStore?

    init(kv: KeyValueStore?) {
        self.kv = kv
        store = kv?.get(StoreKeys.achievements) ?? .init()
        recordStamps = kv?.get(StoreKeys.recordStamps) ?? [:]
    }

    func isEarned(_ id: AchievementID) -> Bool { store.earned[id.rawValue] != nil || states[id]?.isEarned == true }
    func earnedAt(_ id: AchievementID) -> Date? { store.earned[id.rawValue]?.at ?? nil }
    var earnedCount: Int { AchievementID.allCases.filter(isEarned).count }

    static func memoryKey(_ c: PhotoGameRecords.MemoryCategory) -> String {
        "memory:\(c.pairs):\(c.usesPhotos ? 1 : 0):\(c.manualMismatch ? 1 : 0)"
    }

    /// Jüngster Bestwert mit bekanntem Zeitpunkt.
    var latestRecord: (key: String, stamp: GameRecordStamp)? {
        recordStamps.compactMap { key, stamp in stamp.at.map { (key, stamp, $0) } }
            .max { $0.2 < $1.2 }.map { (key: $0.0, stamp: $0.1) }
    }

    func newRecords(from start: Date, to end: Date) -> Int {
        recordStamps.values.filter { ($0.at.map { $0 >= start && $0 < end }) ?? false }.count
    }

    /// Nach jeder Änderung an Ledger, Mediathek oder Spielen. Vor dem ersten vollständigen Laden wird nichts
    /// gespeichert; beim ersten Mal werden bereits erreichte Abzeichen still übernommen (keine Pillen-Flut).
    func refresh(app: AppModel) {
        updateRecordStamps(app: app)
        states = Achievements.evaluate(input(app))
        guard app.readReady && app.snapshot.loaded else { return }
        var newly: [AchievementID] = []
        var changed = false
        for id in AchievementID.allCases {
            guard case .earned(let at)? = states[id], store.earned[id.rawValue] == nil else { continue }
            store.earned[id.rawValue] = .init(at: store.initialized ? (at ?? app.now) : at)
            changed = true
            if store.initialized { newly.append(id) }
        }
        if !store.initialized { store.initialized = true; changed = true }
        if changed { try? kv?.set(StoreKeys.achievements, store) }
        guard let first = newly.first, app.settings.showAchievements else { return }
        let text = L("ach_new", AchievementText.title(first))
        if app.feed == nil {
            app.showToast(text, actionTitle: L("ach_view")) { app.navigate(.achievements) }
        } else {
            app.showToast(text) // Im Feed nie aus dem Wischen herausreißen.
        }
    }

    private func input(_ app: AppModel) -> AchievementInput {
        let r = app.read
        let edits = app.kv?.get(StoreKeys.edits) ?? []
        func first(_ kinds: Set<EditKind>) -> Date? {
            edits.filter { kinds.contains($0.kind) }.map { Date(timeIntervalSince1970: Double($0.atMs) / 1000) }.min()
        }
        return AchievementInput(progress: r.progress, timeZone: .autoupdatingCurrent, monthsDone: r.monthsDone,
                                monthsTotal: r.monthsTotal, laterEverUsed: r.laterEverUsed, laterOpen: r.laterRecords.count,
                                dailyGoal: app.settings.dailyGoal,
                                pairsTimes: app.gameScores.records.memory.map { (pairs: $0.category.pairs, seconds: $0.seconds) },
                                snakeBest: app.gameScores.records.snakeOverallBest, blocksBest: app.blocks.best,
                                firstCollage: first([.collage]), firstPDF: first([.pdf]), firstFilm: first([.merge, .slideshow]))
    }

    private func updateRecordStamps(app: AppModel) {
        var stamps = recordStamps
        let dated = store.initialized
        let now = app.now
        func mark(_ key: String, _ value: Double, better: (Double, Double) -> Bool) {
            if let old = stamps[key] {
                if better(value, old.value) { stamps[key] = .init(value: value, at: now) }
            } else {
                stamps[key] = .init(value: value, at: dated ? now : nil)
            }
        }
        for record in app.gameScores.records.memory { mark(Self.memoryKey(record.category), record.seconds, better: <) }
        if let snake = app.gameScores.records.snakeOverallBest { mark("snake", Double(snake), better: >) }
        if app.blocks.best > 0 { mark("blocks", Double(app.blocks.best), better: >) }
        guard stamps != recordStamps else { return }
        recordStamps = stamps
        try? kv?.set(StoreKeys.recordStamps, stamps)
    }
}
