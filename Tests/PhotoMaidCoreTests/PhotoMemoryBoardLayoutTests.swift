import Testing
@testable import PhotoMaidCore

struct PhotoMemoryBoardLayoutTests {
    @Test func fitsPhoneAndOpenDisplayWithoutTinyTargets() {
        for width in [280.0, 335, 390, 620, 900] {
            for cards in stride(from: 4, through: 36, by: 2) {
                let layout = PhotoMemoryBoardLayout(cards: cards, width: width, availableHeight: 430)
                #expect(layout.cardHeight >= 44)
                #expect((width - Double(layout.columns - 1) * 8) / Double(layout.columns) >= 44)
                #expect(!layout.requiresScrolling)
            }
        }
    }
    @Test func accessibilityAndShortWindowsKeepTargetsAndDeclareScrolling() {
        let layout = PhotoMemoryBoardLayout(cards: 36, width: 280, availableHeight: 160, accessibility: true)
        #expect(layout.columns == 2 && layout.cardHeight >= 44 && layout.requiresScrolling)
    }
}
