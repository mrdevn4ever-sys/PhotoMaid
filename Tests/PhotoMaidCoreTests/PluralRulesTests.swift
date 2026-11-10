import XCTest
@testable import PhotoMaidCore

final class PluralRulesTests: XCTestCase {
    private func cats(_ lang: String, _ ns: [Int]) -> [PluralCategory] { ns.map { PluralRules.category($0, language: lang) } }

    func testBisherigeSprachenUnverändert() {
        XCTAssertEqual(cats("de", [0, 1, 2]), [.other, .one, .other])
        XCTAssertEqual(cats("pt-PT", [0, 1, 2]), [.other, .one, .other])
        XCTAssertEqual(cats("ru", [1, 3, 5, 21]), [.one, .few, .many, .one])
    }

    func testNeueSprachen() {
        XCTAssertEqual(cats("pt-BR", [0, 1, 2]), [.one, .one, .other])
        XCTAssertEqual(cats("cs", [1, 2, 4, 5, 22]), [.one, .few, .few, .other, .other])
        XCTAssertEqual(cats("sk", [1, 3, 5]), [.one, .few, .other])
        XCTAssertEqual(cats("hr", [1, 2, 5, 11, 21, 22, 25]), [.one, .few, .other, .other, .one, .few, .other])
        XCTAssertEqual(cats("sl", [1, 2, 3, 5, 101, 102, 104]), [.one, .two, .few, .other, .one, .two, .few])
        XCTAssertEqual(cats("he", [1, 2, 3, 20]), [.one, .two, .other, .other])
        XCTAssertEqual(cats("hi", [0, 1, 2]), [.one, .one, .other])
        XCTAssertEqual(cats("pa", [0, 1, 2]), [.one, .one, .other])
        XCTAssertEqual(cats("ta", [0, 1, 2]), [.other, .one, .other])
        XCTAssertEqual(cats("zh-Hant", [1, 2]), [.other, .other])
        XCTAssertEqual(cats("vi", [1]), [.other])
        XCTAssertEqual(cats("ca", [1, 2, 1_000_000]), [.one, .other, .many])
        XCTAssertEqual(cats("nb", [1, 2]), [.one, .other])
    }

    func testLookupFälltAufOtherZurück() {
        XCTAssertEqual(PluralRules.lookupOrder(3, language: "cs"), [.few, .other])
        XCTAssertEqual(PluralRules.lookupOrder(5, language: "cs"), [.other])
    }
}
