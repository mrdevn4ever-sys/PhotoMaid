import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct ReviewProgressTests {
    private let tz = TimeZone(identifier: "Europe/Zurich")!
    // Mittwoch, 21. Oktober 2026
    private let today = LocalDay(year: 2026, month: 10, day: 21)

    private func item(_ n: Int) -> ItemReference { ItemReference(provider: .photoLibrary, localIdentifier: "id\(n)") }

    private func at(_ day: LocalDay, hour: Int = 10) -> Date {
        day.startOfDay(in: tz).addingTimeInterval(Double(hour) * 3600)
    }

    private func decision(_ n: Int, _ day: LocalDay, _ to: Disposition = .kept, hour: Int = 10) -> DecisionEvent {
        DecisionEvent(commandID: CommandID(), item: item(n), kind: .decision, from: DecisionSnapshot(disposition: .undecided),
                      to: DecisionSnapshot(disposition: to, dueDay: to == .later ? day.adding(days: 2) : nil),
                      revision: 1, at: at(day, hour: hour), sessionID: nil)
    }

    private func undo(_ n: Int, _ day: LocalDay) -> DecisionEvent {
        DecisionEvent(commandID: nil, item: item(n), kind: .undo, from: DecisionSnapshot(disposition: .kept),
                      to: DecisionSnapshot(disposition: .undecided), revision: 2, at: at(day, hour: 11), sessionID: nil)
    }

    private func progress(_ events: [DecisionEvent]) -> ReviewProgress {
        var records: [ItemReference: ItemRecord] = [:]
        for e in events.sorted(by: { $0.at < $1.at }) {
            records[e.item] = ItemRecord(item: e.item, revision: e.revision, disposition: e.to.disposition,
                                         dueDay: e.to.dueDay, bookmarked: e.to.bookmarked)
        }
        return ReviewProgress.compute(events: events, records: records, today: today, timeZone: tz)
    }

    private func days(_ offsets: [Int]) -> [DecisionEvent] {
        offsets.enumerated().map { i, o in decision(i, today.adding(days: -o)) }
    }

    @Test func countsEveryDecisionKindEquallyAndSubtractsSameDayUndo() {
        let p = progress([decision(1, today, .kept), decision(2, today, .markedForCleanup), decision(3, today, .later),
                          decision(4, today, .kept), undo(4, today)])
        #expect(p.reviewedToday == 3)
        #expect(p.totalReviewed == 3)
    }

    @Test func streakCountsConsecutiveDaysAndTodayWithoutDecisionDoesNotBreakIt() {
        #expect(progress(days([0, 1, 2, 3])).streak == 4)
        #expect(progress(days([1, 2, 3])).streak == 3)
    }

    @Test func oneMissingDayPerWeekIsForgivenButNotTwo() {
        // Heute Mi 21.; Mo 19. fehlt (Pausentag) → Serie Di+Mi + So 18. … Do 15.
        let bridged = progress(days([0, 1, 3, 4, 5, 6]))
        #expect(bridged.streak == 6)
        #expect(bridged.pauseDays == [today.adding(days: -2)])
        // Zwei fehlende Tage in derselben Woche (Mo 19. und Di 20.) beenden die Serie.
        #expect(progress(days([0, 3, 4])).streak == 1)
    }

    @Test func longestStreakAndReachedDays() {
        let p = progress(days([10, 11, 12, 13, 14, 15, 16, 0]))
        #expect(p.longestStreak == 7)
        #expect(p.streakMilestones[3] == today.adding(days: -14))
        #expect(p.streakMilestones[7] == today.adding(days: -10))
    }

    @Test func reviewedMilestoneDateIsWhenTheHundredthMediumWasFirstDecided() {
        let events = (0..<120).map { decision($0, today.adding(days: $0 < 100 ? -1 : 0), hour: 9) }
        let p = progress(events)
        #expect(p.reviewedMilestones[100] == at(today.adding(days: -1), hour: 9))
        #expect(p.reviewedMilestones[1_000] == nil)
    }

    @Test func levelsUseTheFixedThresholds() {
        #expect(ReviewLevel(total: 0).number == 1)
        #expect(ReviewLevel(total: 49).number == 1)
        #expect(ReviewLevel(total: 50).number == 2)
        #expect(ReviewLevel(total: 4_230).number == 5)
        #expect(ReviewLevel(total: 4_230).remaining == 770)
        #expect(ReviewLevel(total: 100_000).next == nil)
    }

    @Test func weekStartsOnMonday() {
        #expect(ReviewProgress.monday(of: today) == LocalDay(year: 2026, month: 10, day: 19))
        #expect(ReviewProgress.monday(of: LocalDay(year: 2026, month: 10, day: 25)) == LocalDay(year: 2026, month: 10, day: 19))
        #expect(progress(days([0, 1])).currentWeek.map(\.reviewed) == [0, 1, 1, 0, 0, 0, 0])
    }

    @Test func achievementsOnlyFromRealData() {
        let p = progress(days([0, 1, 2]))
        let state = Achievements.evaluate(AchievementInput(progress: p, timeZone: tz, pairsTimes: [(6, 25.7), (12, 73.9)],
                                                            snakeBest: 78, blocksBest: 3_979))
        #expect(state[.firstDecision]?.isEarned == true)
        #expect(state[.activeDays3]?.isEarned == true)
        #expect(state[.activeDays7] == .open(remaining: 4))
        #expect(state[.pairsUnder30]?.isEarned == true)
        #expect(state[.pairs12]?.isEarned == true)
        #expect(state[.snake50]?.isEarned == true)
        #expect(state[.blocks5000] == .open(remaining: 1_021))
        #expect(state[.allGames]?.isEarned == true)
        #expect(state[.laterCleared]?.isEarned == false)
        #expect(AchievementID.allCases.count == 24)
    }

    @Test func medalsMeasureOnlyOwnValues() {
        #expect(GameMedal.pairs(seconds: 25.71, pairs: 6) == .silver)
        #expect(GameMedal.pairs(seconds: 20, pairs: 6) == .gold)
        #expect(GameMedal.snake(78) == .gold)
        #expect(GameMedal.blocks(3_979) == .silver)
        #expect(GameMedal.next(after: 3_979, steps: GameMedal.blocksSteps)?.at == 5_000)
        #expect(GameMedal.next(after: 78, steps: GameMedal.snakeSteps) == nil)
    }
}
