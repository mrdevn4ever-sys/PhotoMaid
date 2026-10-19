import Foundation
import Testing
@testable import PhotoMaidCore

struct VaultIntegrationCompatibilityTests {
    @Test func originalEditRecordsDecodeWithoutProvenanceMigration() throws {
        let record = EditRecord(newId: "output", sourceId: "original", mode: .copy, video: false,
                                atMs: 1, kind: .edit, count: 1)
        let encoded = try JSONEncoder().encode(record)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "sources")
        let restored = try JSONDecoder().decode(EditRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.sources == nil)
        #expect(VaultDerivation.parents(of: restored) == ["original"])
    }

    @Test func mixedAndMultistageDerivedOutputsRemainPrivate() {
        let records = [
            EditRecord(newId: "collage", sourceId: "", mode: .copy, video: false, atMs: 1,
                       kind: .collage, count: 2, sources: ["private", "public"]),
            EditRecord(newId: "movie", sourceId: "", mode: .copy, video: true, atMs: 2,
                       kind: .merge, count: 2, sources: ["collage", "other"]),
            EditRecord(newId: "gif", sourceId: "", mode: .copy, video: false, atMs: 3,
                       kind: .gif, count: 1, sources: ["movie"])
        ]
        #expect(VaultDerivation.copies(of: ["private"], records: records) == ["collage", "movie", "gif"])
        #expect(VaultDerivation.copies(of: ["unrelated"], records: records).isEmpty)
    }
}
