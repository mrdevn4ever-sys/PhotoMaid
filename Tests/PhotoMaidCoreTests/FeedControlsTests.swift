import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct FeedControlsTests {
    @Test func standardMatchesFixedGestures() {
        let c = FeedControls.standard
        #expect(c.action(for: .up) == .keep)
        #expect(c.action(for: .left) == .trash)
        #expect(c.action(for: .right) == .later)
        #expect(c.action(for: .down) == .previous)
        #expect(c.visibility == .accessibilityOnly && c.placement == .belowMedia)
        // Gleiche Entscheidungen wie die bisherige feste Belegung.
        for d in [SwipeDirection.up, .left, .right, .down] { #expect(c.action(for: d).intent == FeedIntent(d)) }
    }

    @Test func albumActionKeepsAndIsADecision() {
        let a = FeedAction.album(id: "A1", title: "Urlaub")
        #expect(a.intent == .keep && a.isDecision && a.albumID == "A1")
        #expect(!FeedAction.previous.isDecision && FeedAction.nothing.intent == nil)
        #expect(FeedAction.laterPickDate.intent == .laterCustom)
    }

    @Test func remapRightToAlbum() {
        var c = FeedControls.standard
        c.set(.album(id: "A1", title: "Urlaub"), for: .right)
        #expect(c.action(for: .right).albumID == "A1")
        #expect(c.direction(of: .album(id: "A1", title: "Urlaub")) == .right)
        #expect(c.direction(of: .later) == nil)
    }

    @Test func sanitizeRemovesDuplicatesNoneAndLimits() {
        var c = FeedControls()
        c.buttons = [.keep, .keep, .nothing, .trash, .album(id: "", title: "x"), .later, .laterPickDate, .previous,
                     .album(id: "B", title: "b"), .album(id: "C", title: "c")]
        c.set(.album(id: "", title: "leer"), for: .up)
        let s = c.sanitized()
        #expect(s.buttons == [.keep, .trash, .later, .laterPickDate, .previous, .album(id: "B", title: "b")])
        #expect(s.up == .nothing)
    }

    @Test func addableButtonsExcludeExisting() {
        var c = FeedControls()
        c.buttons = [.keep, .trash]
        let album = FeedAction.album(id: "A", title: "a")
        #expect(c.addableButtons(albums: [album]) == [.later, .laterPickDate, .previous, album])
    }

    @Test func removingDeletedAlbum() {
        var c = FeedControls()
        c.set(.album(id: "A", title: "a"), for: .right)
        c.buttons.append(.album(id: "A", title: "a"))
        let r = c.removingAlbum("A")
        #expect(r.right == .nothing && !r.buttons.contains(where: { $0.albumID == "A" }))
    }

    @Test func codableRoundTripAndTolerantDecoding() throws {
        var c = FeedControls()
        c.set(.album(id: "A", title: "Urlaub"), for: .right)
        c.visibility = .always
        c.placement = .aboveMedia
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(FeedControls.self, from: data) == c)
        // Älterer/teilweiser Stand: fehlende Felder = Standard.
        let partial = try JSONDecoder().decode(FeedControls.self, from: Data(#"{"visibility":"always"}"#.utf8))
        #expect(partial.visibility == .always && partial.up == .keep && partial.buttons == FeedControls.standard.buttons)
    }
}
