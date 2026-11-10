import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct ReviewPromptTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Zurich")!; return c }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400) }

    @Test func neverOnFirstDaysOrSmallSessions() {
        var s = ReviewPromptState()
        ReviewPromptPolicy.noteUse(&s, now: day(0))
        for _ in 0..<5 { #expect(!ReviewPromptPolicy.sessionEnded(&s, decisions: 50, now: day(1), calendar: calendar)) }
        #expect(!ReviewPromptPolicy.sessionEnded(&s, decisions: 9, now: day(10), calendar: calendar))
        #expect(s.requests == 0)
    }

    @Test func asksAfterThreeGoodSessionsAndWaitsBetweenRequests() {
        var s = ReviewPromptState()
        ReviewPromptPolicy.noteUse(&s, now: day(0))
        #expect(!ReviewPromptPolicy.sessionEnded(&s, decisions: 12, now: day(3), calendar: calendar))
        #expect(!ReviewPromptPolicy.sessionEnded(&s, decisions: 12, now: day(3), calendar: calendar))
        #expect(ReviewPromptPolicy.sessionEnded(&s, decisions: 12, now: day(3), calendar: calendar))
        #expect(!ReviewPromptPolicy.sessionEnded(&s, decisions: 40, now: day(4), calendar: calendar))
        #expect(!ReviewPromptPolicy.sessionEnded(&s, decisions: 40, now: day(122), calendar: calendar))
        #expect(ReviewPromptPolicy.sessionEnded(&s, decisions: 40, now: day(123), calendar: calendar))
        #expect(ReviewPromptPolicy.sessionEnded(&s, decisions: 40, now: day(243), calendar: calendar))
        #expect(!ReviewPromptPolicy.sessionEnded(&s, decisions: 40, now: day(500), calendar: calendar)) // höchstens dreimal
        #expect(s.requests == 3)
    }

    @Test func stateDecodesFromEmptyAndOldData() throws {
        let s = try JSONDecoder().decode(ReviewPromptState.self, from: Data(#"{"goodSessions":2,"requests":0}"#.utf8))
        #expect(s.goodSessions == 2 && s.firstUse == nil)
    }
}
