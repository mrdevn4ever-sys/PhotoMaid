import Foundation
import Observation
import PhotoMaidCore

/// Schlagwörter, Notizen und Auswahlkorb – reine PhotoMaid-Verwaltungsdaten (Port von Android `OrganizeStore`).
/// Ändern nie eine Datei, sind nie eine Entscheidung (kein Ledger), beruhen nur auf Eingaben des Nutzers.
/// Bezüge über `localIdentifier` + Fingerabdruck (`MediaRef`), damit sie eine Neuindizierung überstehen.
@MainActor
@Observable
final class OrganizeStore {
    private(set) var tags: [String: [String]]
    private(set) var notes: [String: String]
    private(set) var refs: [String: MediaRef]
    private(set) var basket: [String]
    /// Nicht mehr auffindbare Bezüge (sichtbar gezählt, nur auf Wunsch entfernt).
    private(set) var missing: [String] = []
    @ObservationIgnored private let kv: KeyValueStore?

    init(kv: KeyValueStore?) {
        self.kv = kv
        tags = kv?.get(StoreKeys.tags) ?? [:]
        notes = kv?.get(StoreKeys.notes) ?? [:]
        refs = kv?.get(StoreKeys.refs) ?? [:]
        basket = kv?.get(StoreKeys.selectionBasket) ?? []
    }

    // MARK: Schlagwörter

    func tags(of id: String) -> [String] { tags[id] ?? [] }

    /// Ohne Medien im Tresor (auch nicht mitgezählt).
    var allTags: [(tag: String, count: Int)] {
        let visible = VaultConcealment.shared.visible(Set(tags.keys))
        return TagRules.counts(visible.count == tags.count ? tags : tags.filter { visible.contains($0.key) })
    }

    @discardableResult
    func addTags(_ raw: [String], to assets: [MediaAsset]) -> Bool {
        let clean = raw.compactMap(TagRules.normalize)
        guard !clean.isEmpty, !assets.isEmpty else { return false }
        var t = tags
        for a in assets { t[a.id] = TagRules.merge(t[a.id] ?? [], clean) }
        return save(tags: t, touching: assets)
    }

    @discardableResult
    func removeTag(_ tag: String, from ids: [String]) -> Bool {
        var t = tags
        for id in ids {
            let rest = TagRules.remove(t[id] ?? [], tag)
            t[id] = rest.isEmpty ? nil : rest
        }
        return save(tags: t, touching: [])
    }

    /// Medien mit diesem Schlagwort (für Suche und die Schlagwort-Ansicht).
    func ids(withTag tag: String) -> [String] {
        let key = TagRules.key(tag)
        return tags.filter { $0.value.contains { TagRules.key($0) == key } }.map(\.key)
    }

    // MARK: Notizen

    func note(of id: String) -> String? { notes[id] }

    @discardableResult
    func setNote(_ raw: String, for asset: MediaAsset) -> Bool {
        var n = notes
        n[asset.id] = NoteRules.normalize(raw)
        do {
            try kv?.set(StoreKeys.notes, n)
            notes = n
            remember([asset])
            return true
        } catch {
            return false
        }
    }

    // MARK: Auswahlkorb (≠ Papierkorb)

    /// Fügt hinzu (Reihenfolge des Hinzufügens, höchstens `BasketRules.max`). Gibt die Zahl der neuen Einträge zurück.
    func addToBasket(_ assets: [MediaAsset]) -> Int {
        let (list, added) = BasketRules.add(basket, assets.map(\.id))
        guard added > 0 else { return 0 }
        do {
            try kv?.set(StoreKeys.selectionBasket, list)
            basket = list
            remember(assets)
            return added
        } catch {
            return 0
        }
    }

    func removeFromBasket(_ ids: [String]) {
        let remove = Set(ids)
        let list = basket.filter { !remove.contains($0) }
        if (try? kv?.set(StoreKeys.selectionBasket, list)) != nil || kv == nil { basket = list }
    }

    func clearBasket() {
        if (try? kv?.set(StoreKeys.selectionBasket, [String]())) != nil || kv == nil { basket = [] }
    }

    // MARK: Wiederfinden

    /// Bezüge gegen die aktuelle Mediathek prüfen: verschobene IDs übernehmen, Fehlendes zählen (nie still löschen).
    func rematch(current: [MediaAsset]) {
        let stored = Array(refs.values)
        guard !stored.isEmpty else { missing = []; return }
        let present = Set(current.map(\.id))
        // Dateinamen nur für Kandidaten lesen, deren Aufnahmezeit zu einem fehlenden Bezug passt (teuer je Medium).
        let wantedTimes = Set(stored.filter { !present.contains($0.id) }.compactMap(\.takenMillis))
        let result = Rematch.resolve(stored: stored, current: current) { a in
            let millis = a.creationDate.map { Int64($0.timeIntervalSince1970 * 1000) }
            let name = millis.map { wantedTimes.contains($0) } == true ? PhotoLibraryService.originalFilename(a.id) : nil
            return MediaRef(id: a.id, name: name, size: nil, takenMillis: millis)
        }
        if !result.moved.isEmpty { applyMoves(result.moved) }
        missing = result.missing
    }

    /// „Nicht auffindbare entfernen“ – nur auf ausdrücklichen Wunsch.
    func forgetMissing() {
        let gone = Set(missing)
        guard !gone.isEmpty else { return }
        var t = tags, n = notes, r = refs
        for id in gone { t[id] = nil; n[id] = nil; r[id] = nil }
        let b = basket.filter { !gone.contains($0) }
        do {
            try kv?.set(StoreKeys.tags, t)
            try kv?.set(StoreKeys.notes, n)
            try kv?.set(StoreKeys.refs, r)
            try kv?.set(StoreKeys.selectionBasket, b)
            tags = t; notes = n; refs = r; basket = b; missing = []
        } catch {}
    }

    /// Nach einer Wiederherstellung aus der Sicherung (Werte bereits zugeordnet). Überschreibt nie Hiesiges.
    func mergeRestored(tags newTags: [String: [String]], notes newNotes: [String: String], basket newBasket: [String]) {
        var t = tags, n = notes
        for (id, list) in newTags { t[id] = TagRules.merge(t[id] ?? [], list) }
        for (id, note) in newNotes where n[id] == nil { n[id] = note }
        let b = BasketRules.add(basket, newBasket).list
        do {
            try kv?.set(StoreKeys.tags, t)
            try kv?.set(StoreKeys.notes, n)
            try kv?.set(StoreKeys.selectionBasket, b)
            tags = t; notes = n; basket = b
        } catch {}
    }

    // MARK: Intern

    private func save(tags t: [String: [String]], touching assets: [MediaAsset]) -> Bool {
        do {
            try kv?.set(StoreKeys.tags, t)
            tags = t
            if !assets.isEmpty { remember(assets) }
            return true
        } catch {
            return false
        }
    }

    /// Fingerabdruck merken (Dateiname nur lokal, nie übertragen).
    private func remember(_ assets: [MediaAsset]) {
        var r = refs
        for a in assets where r[a.id] == nil {
            r[a.id] = MediaRef(id: a.id, name: PhotoLibraryService.originalFilename(a.id), size: nil,
                               takenMillis: a.creationDate.map { Int64($0.timeIntervalSince1970 * 1000) })
        }
        if r != refs, (try? kv?.set(StoreKeys.refs, r)) != nil || kv == nil { refs = r }
    }

    private func applyMoves(_ moved: [String: String]) {
        var t = tags, n = notes, r = refs
        var b = basket
        for (old, new) in moved {
            if let v = t.removeValue(forKey: old) { t[new] = TagRules.merge(t[new] ?? [], v) }
            if let v = n.removeValue(forKey: old), n[new] == nil { n[new] = v }
            if let v = r.removeValue(forKey: old) {
                r[new] = MediaRef(id: new, name: v.name, size: v.size, takenMillis: v.takenMillis)
            }
            b = b.map { $0 == old ? new : $0 }
        }
        do {
            try kv?.set(StoreKeys.tags, t)
            try kv?.set(StoreKeys.notes, n)
            try kv?.set(StoreKeys.refs, r)
            try kv?.set(StoreKeys.selectionBasket, b)
            tags = t; notes = n; refs = r; basket = b
        } catch {}
    }
}
