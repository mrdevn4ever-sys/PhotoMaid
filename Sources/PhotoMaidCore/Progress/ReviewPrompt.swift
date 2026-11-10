import Foundation

/// Wann GaleriQ Apples Bewertungsdialog anfragt (Nutzer 11.11.2026). Nur Apples Systemdialog
/// (`AppStore.requestReview`, App-Review-Richtlinie 5.6.1: keine eigenen Bewertungsabfragen, keine Vorab-Frage
/// „Bist du zufrieden?“, die nur Zufriedene weiterleitet). „Nicht jetzt“ und „nie wieder“ regelt iOS selbst
/// (höchstens dreimal im Jahr, Einstellungen › App Store › Bewertungen in Apps).
/// Unsere eigenen Grenzen darüber: nur nach einer gelungenen Aufräum-Sitzung, nicht in den ersten Tagen,
/// höchstens alle 120 Tage, höchstens dreimal insgesamt.
public struct ReviewPromptState: Codable, Equatable, Sendable {
    public var firstUse: Date?
    public var goodSessions = 0
    public var lastRequest: Date?
    public var requests = 0
    public init() {}
}

public enum ReviewPromptPolicy {
    /// Eine Sitzung zählt ab so vielen Entscheidungen als „gelungen“.
    public static let minimumDecisions = 10
    public static let minimumSessions = 3
    public static let minimumDaysSinceFirstUse = 3
    public static let daysBetweenRequests = 120
    public static let maximumRequests = 3

    /// Merkt sich den ersten Start (nur einmal).
    public static func noteUse(_ state: inout ReviewPromptState, now: Date) {
        if state.firstUse == nil { state.firstUse = now }
    }

    /// Nach einer beendeten Feed-Sitzung: zählt sie und sagt, ob jetzt der Systemdialog angefragt werden darf.
    /// Bei `true` ist die Anfrage bereits vermerkt (eine Sitzung = höchstens eine Anfrage).
    public static func sessionEnded(_ state: inout ReviewPromptState, decisions: Int, now: Date,
                                    calendar: Calendar = .current) -> Bool {
        noteUse(&state, now: now)
        guard decisions >= minimumDecisions else { return false }
        state.goodSessions += 1
        guard state.goodSessions >= minimumSessions, state.requests < maximumRequests,
              let first = state.firstUse,
              days(from: first, to: now, calendar) >= minimumDaysSinceFirstUse else { return false }
        if let last = state.lastRequest, days(from: last, to: now, calendar) < daysBetweenRequests { return false }
        state.lastRequest = now
        state.requests += 1
        return true
    }

    private static func days(from a: Date, to b: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }
}
