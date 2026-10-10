import CoreData
import Foundation
import PhotoMaidCore

/// Lokaler Core-Data-Store ohne CloudKit. Einzige Wahrheit für Entscheidungen, Verlauf,
/// Undo, Operation-Journal, Tageskontingent sowie App-Zustand (Regeln, Quellen, Rewards).
///
/// Backup: Der Store liegt in Application Support und ist im iCloud-/Geräte-Backup des Nutzers
/// enthalten (Entscheidungen sollen eine Wiederherstellung überleben). Abgeleitete Caches
/// (Thumbnails, Hashes) liegen in Caches und sind vom Backup ausgeschlossen.
/// Dateischutz: `completeUntilFirstUserAuthentication` (Hintergrundaufgaben brauchen Zugriff).
final class CoreDataStore: @unchecked Sendable {
    let container: NSPersistentContainer
    let context: NSManagedObjectContext

    enum StoreError: Error { case modelMissing, loadFailed(String) }

    init(inMemory: Bool = false) throws {
        guard let url = Bundle.main.url(forResource: "PhotoMaid", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else { throw StoreError.modelMissing }
        container = NSPersistentContainer(name: "PhotoMaid", managedObjectModel: model)
        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        } else {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            description = NSPersistentStoreDescription(url: dir.appendingPathComponent("PhotoMaid.sqlite"))
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                                  forKey: NSPersistentStoreFileProtectionKey)
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.cloudKitContainerOptions = nil // ausdrücklich kein CloudKit
        container.persistentStoreDescriptions = [description]
        // Box statt erfasster `var`: kompiliert auch, falls das SDK den Handler als @Sendable markiert.
        let loadResult = LoadErrorBox()
        container.loadPersistentStores { _, error in loadResult.error = error }
        if let loadError = loadResult.error { throw StoreError.loadFailed(String(describing: loadError)) }
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.undoManager = nil
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }()
    static let decoder: JSONDecoder = {
        JSONDecoder()
    }()

    // MARK: Key-Value (App-Zustand)

    func value<T: Decodable & Sendable>(_ type: T.Type, forKey key: String) -> T? {
        context.performAndWait {
            let req = NSFetchRequest<NSManagedObject>(entityName: "CDKeyValue")
            req.predicate = NSPredicate(format: "key == %@", key)
            req.fetchLimit = 1
            guard let obj = try? context.fetch(req).first, let data = obj.value(forKey: "payload") as? Data else { return nil }
            return try? Self.decoder.decode(T.self, from: data)
        }
    }

    func setValue<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try Self.encoder.encode(value)
        try context.performAndWait {
            upsert("CDKeyValue", keyName: "key", key: key) { $0.setValue(data, forKey: "payload") }
            do { try context.save() } catch { context.rollback(); throw error }
        }
    }

    fileprivate func upsert(_ entity: String, keyName: String, key: Any, apply: (NSManagedObject) -> Void) {
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.predicate = NSPredicate(format: "%K == %@", keyName, key as! CVarArg)
        req.fetchLimit = 1
        let obj = (try? context.fetch(req).first)
            ?? NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        obj.setValue(key, forKey: keyName)
        apply(obj)
    }
}

/// `LedgerPersistence` über Core Data. `commit` schreibt eine `LedgerChange` in genau einem Save.
final class CoreDataLedgerPersistence: LedgerPersistence, @unchecked Sendable {
    private let store: CoreDataStore
    private static let undoKey = "ledger.undoStack"

    init(store: CoreDataStore) { self.store = store }

    static func itemKey(_ item: ItemReference) -> String { item.description }

    func load() throws -> LedgerState {
        try store.context.performAndWait {
            var state = LedgerState()
            let ctx = store.context
            for obj in try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: "CDItemRecord")) {
                let r = try CoreDataStore.decoder.decode(ItemRecord.self, from: obj.value(forKey: "payload") as! Data)
                state.records[r.item] = r
            }
            let evReq = NSFetchRequest<NSManagedObject>(entityName: "CDEvent")
            evReq.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]
            state.events = try ctx.fetch(evReq).map {
                try CoreDataStore.decoder.decode(DecisionEvent.self, from: $0.value(forKey: "payload") as! Data)
            }
            for obj in try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: "CDIntent")) {
                let i = try CoreDataStore.decoder.decode(OperationIntent.self, from: obj.value(forKey: "payload") as! Data)
                state.intents[i.id] = i
            }
            for obj in try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: "CDDayUsage")) {
                let entry = try CoreDataStore.decoder.decode(DayUsageEntry.self, from: obj.value(forKey: "payload") as! Data)
                state.usage[entry.day] = entry.usage
            }
            state.undoStack = store.value([UndoEntry].self, forKey: Self.undoKey) ?? []
            return state
        }
    }

    func commit(_ change: LedgerChange) throws {
        guard !change.isEmpty else { return }
        let enc = CoreDataStore.encoder
        // Vorab kodieren: Kodierfehler dürfen keinen halben Save hinterlassen.
        let records = try change.records.map { ($0, try enc.encode($0)) }
        let events = try change.events.map { ($0, try enc.encode($0)) }
        let intents = try change.intents.map { ($0, try enc.encode($0)) }
        let usage = try change.usage.map { ($0.key, try enc.encode(DayUsageEntry(day: $0.key, usage: $0.value))) }
        let undo = try change.undoStack.map { try enc.encode($0) }

        try store.context.performAndWait {
            let ctx = store.context
            for (r, data) in records {
                store.upsert("CDItemRecord", keyName: "itemKey", key: Self.itemKey(r.item)) {
                    $0.setValue(Int64(r.revision), forKey: "revision")
                    $0.setValue(r.disposition.rawValue, forKey: "disposition")
                    $0.setValue(r.dueDay?.description, forKey: "dueDayKey")
                    $0.setValue(data, forKey: "payload")
                }
            }
            if !events.isEmpty {
                let countReq = NSFetchRequest<NSManagedObject>(entityName: "CDEvent")
                var seq = Int64(try ctx.count(for: countReq))
                for (e, data) in events {
                    let obj = NSEntityDescription.insertNewObject(forEntityName: "CDEvent", into: ctx)
                    obj.setValue(e.id, forKey: "id")
                    obj.setValue(Self.itemKey(e.item), forKey: "itemKey")
                    obj.setValue(e.kind.rawValue, forKey: "kind")
                    obj.setValue(e.at, forKey: "at")
                    obj.setValue(seq, forKey: "sequence")
                    obj.setValue(data, forKey: "payload")
                    seq += 1
                }
            }
            for (i, data) in intents {
                store.upsert("CDIntent", keyName: "id", key: i.id.rawValue as NSUUID) {
                    $0.setValue(i.state.rawValue, forKey: "state")
                    $0.setValue(data, forKey: "payload")
                }
            }
            for (day, data) in usage {
                store.upsert("CDDayUsage", keyName: "dayKey", key: day.description) {
                    $0.setValue(data, forKey: "payload")
                }
            }
            if let undo {
                store.upsert("CDKeyValue", keyName: "key", key: Self.undoKey) {
                    $0.setValue(undo, forKey: "payload")
                }
            }
            do { try ctx.save() } catch { ctx.rollback(); throw error }
        }
    }
}

private struct DayUsageEntry: Codable {
    let day: LocalDay
    let usage: DayUsage
}

/// Ladefehler aus `loadPersistentStores` (der Handler läuft bei SQLite-Stores synchron).
private final class LoadErrorBox: @unchecked Sendable {
    var error: Error?
}
