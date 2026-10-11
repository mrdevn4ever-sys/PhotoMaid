import Foundation
import Observation
import PhotoMaidCore

/// Durable metadata is preserved. Only a privacy-filtered projection is public;
/// locking/importing must not turn old notes/tags into a second vault index.
@MainActor @Observable
final class OrganizeStore {
    private var storedTags: [String: [String]]
    private var storedNotes: [String: String]
    private var storedRefs: [String: MediaRef]
    private var storedBasket: [String]
    private var storedMissing: [String] = []
    private var privacyRevision = UUID()
    @ObservationIgnored private let kv: KeyValueStore?

    var tags: [String: [String]] { _ = privacyRevision; return storedTags.filter { VaultIsolation.shared.allows($0.key) } }
    var notes: [String: String] { _ = privacyRevision; return storedNotes.filter { VaultIsolation.shared.allows($0.key) } }
    var refs: [String: MediaRef] { _ = privacyRevision; return storedRefs.filter { VaultIsolation.shared.allows($0.key) } }
    var basket: [String] { _ = privacyRevision; return storedBasket.filter { VaultIsolation.shared.allows($0) } }
    var missing: [String] { _ = privacyRevision; return storedMissing.filter { VaultIsolation.shared.allows($0) } }

    init(kv: KeyValueStore?) {
        self.kv = kv
        // Storage ownership, not a UI read: public getters above apply the gate.
        storedTags = kv?.vaultMigrationValue(StoreKeys.tags) ?? [:]
        storedNotes = kv?.vaultMigrationValue(StoreKeys.notes) ?? [:]
        storedRefs = kv?.vaultMigrationValue(StoreKeys.refs) ?? [:]
        storedBasket = kv?.vaultMigrationValue(StoreKeys.selectionBasket) ?? []
    }
    func refreshPrivacy() { privacyRevision = UUID() }
    func tags(of id: String) -> [String] { VaultIsolation.shared.allows(id) ? storedTags[id] ?? [] : [] }
    var allTags: [(tag: String, count: Int)] { TagRules.counts(tags) }

    @discardableResult func addTags(_ raw: [String], to assets: [MediaAsset]) -> Bool {
        let clean = raw.compactMap(TagRules.normalize)
        let safe = assets.filter { VaultIsolation.shared.allows($0.id) }
        guard !clean.isEmpty, !safe.isEmpty else { return false }
        var proposed = storedTags
        for asset in safe { proposed[asset.id] = TagRules.merge(proposed[asset.id] ?? [], clean) }
        return save(tags: proposed, touching: safe)
    }
    @discardableResult func removeTag(_ tag: String, from ids: [String]) -> Bool {
        var proposed = storedTags
        for id in ids where VaultIsolation.shared.allows(id) {
            let rest = TagRules.remove(proposed[id] ?? [], tag)
            proposed[id] = rest.isEmpty ? nil : rest
        }
        return save(tags: proposed, touching: [])
    }
    func ids(withTag tag: String) -> [String] {
        let key = TagRules.key(tag)
        return tags.filter { $0.value.contains { TagRules.key($0) == key } }.map(\.key)
    }
    func note(of id: String) -> String? { VaultIsolation.shared.allows(id) ? storedNotes[id] : nil }
    @discardableResult func setNote(_ raw: String, for asset: MediaAsset) -> Bool {
        guard VaultIsolation.shared.allows(asset.id) else { return false }
        var proposed = storedNotes
        proposed[asset.id] = NoteRules.normalize(raw)
        do { try kv?.set(StoreKeys.notes, proposed); storedNotes = proposed; remember([asset]); return true }
        catch { return false }
    }
    func addToBasket(_ assets: [MediaAsset]) -> Int {
        let safe = assets.filter { VaultIsolation.shared.allows($0.id) }
        let (list, added) = BasketRules.add(storedBasket, safe.map(\.id))
        guard added > 0 else { return 0 }
        do { try kv?.set(StoreKeys.selectionBasket, list); storedBasket = list; remember(safe); return added }
        catch { return 0 }
    }
    func removeFromBasket(_ ids: [String]) {
        let remove = Set(ids.filter { VaultIsolation.shared.allows($0) })
        let proposed = storedBasket.filter { !remove.contains($0) }
        do { try kv?.set(StoreKeys.selectionBasket, proposed); storedBasket = proposed } catch {}
    }
    func clearBasket() { removeFromBasket(basket) }

    func rematch(current: [MediaAsset]) {
        let stored = Array(refs.values)
        guard !stored.isEmpty else { storedMissing = []; return }
        let safe = current.filter { VaultIsolation.shared.allows($0.id) }
        let present = Set(safe.map(\.id))
        let wantedTimes = Set(stored.filter { !present.contains($0.id) }.compactMap(\.takenMillis))
        let result = Rematch.resolve(stored: stored, current: safe) { asset in
            let millis = asset.creationDate.map { Int64($0.timeIntervalSince1970 * 1000) }
            let name = millis.map { wantedTimes.contains($0) } == true ? PhotoLibraryService.originalFilename(asset.id) : nil
            return MediaRef(id: asset.id, name: name, size: nil, takenMillis: millis)
        }
        if !result.moved.isEmpty { applyMoves(result.moved) }
        storedMissing = result.missing
    }
    func forgetMissing() {
        let gone = Set(missing)
        guard !gone.isEmpty else { return }
        var t = storedTags, n = storedNotes, r = storedRefs
        for id in gone { t[id] = nil; n[id] = nil; r[id] = nil }
        let b = storedBasket.filter { !gone.contains($0) }
        do {
            try kv?.set(StoreKeys.tags, t); try kv?.set(StoreKeys.notes, n)
            try kv?.set(StoreKeys.refs, r); try kv?.set(StoreKeys.selectionBasket, b)
            storedTags = t; storedNotes = n; storedRefs = r; storedBasket = b; storedMissing = []
        } catch {}
    }
    func mergeRestored(tags newTags: [String: [String]], notes newNotes: [String: String], basket newBasket: [String]) {
        var t = storedTags, n = storedNotes
        for (id, list) in newTags where VaultIsolation.shared.allows(id) { t[id] = TagRules.merge(t[id] ?? [], list) }
        for (id, note) in newNotes where VaultIsolation.shared.allows(id) && n[id] == nil { n[id] = note }
        let b = BasketRules.add(storedBasket, newBasket.filter { VaultIsolation.shared.allows($0) }).list
        do {
            try kv?.set(StoreKeys.tags, t); try kv?.set(StoreKeys.notes, n); try kv?.set(StoreKeys.selectionBasket, b)
            storedTags = t; storedNotes = n; storedBasket = b
        } catch {}
    }
    private func save(tags proposed: [String: [String]], touching assets: [MediaAsset]) -> Bool {
        do { try kv?.set(StoreKeys.tags, proposed); storedTags = proposed; if !assets.isEmpty { remember(assets) }; return true }
        catch { return false }
    }
    private func remember(_ assets: [MediaAsset]) {
        var proposed = storedRefs
        for asset in assets where VaultIsolation.shared.allows(asset.id) && proposed[asset.id] == nil {
            proposed[asset.id] = MediaRef(id: asset.id, name: PhotoLibraryService.originalFilename(asset.id), size: nil,
                                         takenMillis: asset.creationDate.map { Int64($0.timeIntervalSince1970 * 1000) })
        }
        guard proposed != storedRefs else { return }
        do { try kv?.set(StoreKeys.refs, proposed); storedRefs = proposed } catch {}
    }
    private func applyMoves(_ moved: [String: String]) {
        var t = storedTags, n = storedNotes, r = storedRefs, b = storedBasket
        for (old, new) in moved where VaultIsolation.shared.allows(old) && VaultIsolation.shared.allows(new) {
            if let value = t.removeValue(forKey: old) { t[new] = TagRules.merge(t[new] ?? [], value) }
            if let value = n.removeValue(forKey: old), n[new] == nil { n[new] = value }
            if let value = r.removeValue(forKey: old) { r[new] = MediaRef(id: new, name: value.name, size: value.size, takenMillis: value.takenMillis) }
            b = b.map { $0 == old ? new : $0 }
        }
        do {
            try kv?.set(StoreKeys.tags, t); try kv?.set(StoreKeys.notes, n); try kv?.set(StoreKeys.refs, r); try kv?.set(StoreKeys.selectionBasket, b)
            storedTags = t; storedNotes = n; storedRefs = r; storedBasket = b
        } catch {}
    }
}
