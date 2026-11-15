import Foundation

// Native Foundation wire-format unit control only. No app UI, PhotoKit fixture,
// fake capture result, model injection or Store output is created here.
let start = Date(timeIntervalSince1970: 1_000)
let members = (0..<3).map {
    PhotoSeries.Member(id: "unit-rectangle-\($0)", group: "unit-only", takenAt: start.addingTimeInterval(Double($0)))
}
let actualGroups = PhotoSeries.groups(members)
precondition(actualGroups.count == 1 && actualGroups[0].count == 3)
let unsafe: [String: Any] = ["series": actualGroups]
precondition(!JSONSerialization.isValidJSONObject(unsafe), "Raw Swift Member structs must be rejected before JSON serialization")
let primitives = actualGroups.map { $0.map(\.id) }
let safe: [String: Any] = ["series": primitives]
precondition(JSONSerialization.isValidJSONObject(safe), "Observed group IDs must be JSON primitives")
let raw = try JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys])
let decoded = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
precondition(decoded["series"] as? [[String]] == primitives)
let badFields = unsafe.keys.filter { !JSONSerialization.isValidJSONObject(["value": unsafe[$0]!]) }.sorted()
precondition(badFields == ["series"])
let error: [String: Any] = ["status": "error", "error": "Non-JSON read-only evidence fields: " + badFields.joined(separator: ", ")]
precondition(JSONSerialization.isValidJSONObject(error))
print("PASS native Foundation JSON wire controls: reject raw Member structs; round-trip actual group IDs; safe error reply")
