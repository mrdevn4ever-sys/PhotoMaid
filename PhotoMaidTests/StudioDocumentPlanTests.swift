import XCTest
import PhotoMaidCore
@testable import PhotoMaid

final class StudioDocumentPlanTests: XCTestCase {
    func testMovieHandoffPreservesOrderAndTransitions() {
        let clips = [MoviePlan.photoClip(id: "a", mediaId: "1"),
                     MoviePlan.photoClip(id: "b", mediaId: "2")]
        var project = VideoProject(id: "movie", clips: clips)
        project.transitions = [.fadeBlack]
        let moved = project.move(from: 0, to: 1)
        XCTAssertEqual(moved.clips.map(\.mediaId), ["2", "1"])
        XCTAssertEqual(moved.transition(at: 0), .fadeBlack)
        XCTAssertEqual(MoviePlan.blackSeams(moved), [VideoRules.photoDefaultMs])
    }

    func testCollagePreviewAndExportUseSameGeometry() {
        let project = CollageProject.create(id: "c", ids: ["1", "2", "3"])
        let cells = project.cellRects()
        XCTAssertEqual(cells.count, 3)
        XCTAssertTrue(cells.allSatisfy { $0.width > 0 && $0.height > 0 })
        XCTAssertEqual(CollageExport.size(aspect: project.aspect, longEdge: 2048).height, 2048)
    }

    func testWorkflowUnreachableDoesNotClaimTargetMet() async throws {
        var attempts = 0
        let outcome = try await TargetSize.search(maxBytes: 100, startEdge: 2048, startQuality: 90,
                                                  minEdge: 1024, minQuality: 60, lossless: false) { _ in
            attempts += 1
            return 1_000
        }
        guard case .unreachable = outcome else { return XCTFail("Expected unreachable") }
        XCTAssertGreaterThan(attempts, 0)
    }

    func testPdfEditNeverRemovesLastPage() {
        let pages = [PdfPageRef(document: 0, page: 0)]
        XCTAssertEqual(PdfEdit.remove(pages, at: [0]), pages)
    }

    func testBackupRejectsNonBackupJSON() {
        XCTAssertEqual(BackupRules.check(data: Data("{}".utf8)), .notABackup)
    }
}
