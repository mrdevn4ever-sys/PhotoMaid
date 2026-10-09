import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct HistoryGroupingTests {
    let item = ItemReference.photo("a")
    let t0 = Date(timeIntervalSince1970: 1_000)

    func event(_ kind: HistoryKind, from: DecisionSnapshot, to: DecisionSnapshot, rev: Int, op: OperationID? = nil,
               item: ItemReference? = nil) -> DecisionEvent {
        DecisionEvent(commandID: op == nil ? CommandID() : nil, operationID: op, item: item ?? self.item, kind: kind,
                      from: from, to: to, revision: rev, at: t0.addingTimeInterval(Double(rev)), sessionID: nil)
    }

    @Test func laterAndFirstScheduleBecomeOneEntry() {
        let s = ReviewSessionID()
        let later = DecisionSnapshot(disposition: .later, skippedInSession: s)
        let day = LocalDay(year: 2026, month: 10, day: 11)
        let scheduled = DecisionSnapshot(disposition: .later, dueDay: day, skippedInSession: s)
        let entries = HistoryGrouping.group([
            event(.decision, from: DecisionSnapshot(disposition: .undecided), to: later, rev: 1),
            event(.scheduleChanged, from: later, to: scheduled, rev: 2),
        ])
        #expect(entries.count == 1)
        #expect(entries[0].schedule?.to.dueDay == day)
    }

    @Test func scheduleAfterOtherChangeStaysSeparate() {
        let later = DecisionSnapshot(disposition: .later)
        let day = LocalDay(year: 2026, month: 10, day: 11)
        let entries = HistoryGrouping.group([
            event(.decision, from: DecisionSnapshot(disposition: .undecided), to: later, rev: 1),
            event(.undo, from: later, to: DecisionSnapshot(disposition: .undecided), rev: 2),
            event(.scheduleChanged, from: later, to: DecisionSnapshot(disposition: .later, dueDay: day), rev: 3),
        ])
        #expect(entries.count == 3)
    }

    @Test func sameOperationIsBatched() {
        let op = OperationID()
        let marked = DecisionSnapshot(disposition: .markedForCleanup)
        let entries = HistoryGrouping.group((0..<10).map { i in
            event(.cleanupNotPerformed, from: marked, to: marked, rev: 1, op: op, item: .photo("x\(i)"))
        })
        #expect(entries.count == 1)
        #expect(entries[0].itemCount == 10)
    }
}
