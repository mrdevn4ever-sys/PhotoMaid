import Foundation
import XCTest
@testable import PhotoMaidCore

final class RetouchSelectionTests: XCTestCase {
    private func radial() -> LocalAdjustment {
        LocalAdjustment(mask: .radial(center: NormPoint(0.5, 0.5), rx: 0.18, ry: 0.36, feather: 0.6, invert: false))
    }

    private func selected(_ local: LocalAdjustment) throws -> (RetouchSelection, RetouchTarget) {
        var selection = RetouchSelection()
        selection.select(local.id)
        return (selection, try XCTUnwrap(selection.target(in: [local])))
    }

    func testEveryNewAdjustmentHasUniqueIdentity() {
        XCTAssertNotEqual(radial().id, radial().id)
    }

    func testIdentitySurvivesValueCopy() {
        let original = radial()
        var copy = original
        copy.adjust.exposure = 20
        XCTAssertEqual(copy.id, original.id)
        XCTAssertEqual(original.adjust.exposure, 0)
    }

    func testIdentityAndValuesSurviveCodableRoundTrip() throws {
        let original = radial()
        let decoded = try JSONDecoder().decode(LocalAdjustment.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testLegacyRecipeWithoutIDGetsStablePersistableIdentity() throws {
        let original = radial()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "id")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(LocalAdjustment.self, from: legacy)
        XCTAssertEqual(decoded.mask, original.mask)
        XCTAssertEqual(decoded.adjust, original.adjust)
        let saved = try JSONEncoder().encode(decoded)
        XCTAssertEqual(try JSONDecoder().decode(LocalAdjustment.self, from: saved).id, decoded.id)
    }

    func testEqualLegacyEntriesDoNotShareAnID() throws {
        let data = Data(#"{"mask":{"brush":{"strokes":[]}}}"#.utf8)
        let a = try JSONDecoder().decode(LocalAdjustment.self, from: data)
        let b = try JSONDecoder().decode(LocalAdjustment.self, from: data)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.adjust, Adjustments())
    }

    func testMissingTargetReadIsSafeAndDoesNotMutate() throws {
        let (selection, target) = try selected(radial())
        let locals: [LocalAdjustment] = []
        XCTAssertNil(selection.local(target, in: locals))
        XCTAssertEqual(selection.adjustment(target, in: locals, keyPath: \.exposure), 0)
        XCTAssertEqual(selection.radialSize(target, in: locals), 4)
        XCTAssertTrue(locals.isEmpty)
    }

    func testDeletedTargetWriteIsANoOp() throws {
        let (selection, target) = try selected(radial())
        var locals: [LocalAdjustment] = []
        XCTAssertFalse(selection.setAdjustment(80, target: target, in: &locals, keyPath: \.exposure))
        XCTAssertFalse(selection.setRadialSize(80, target: target, in: &locals))
        XCTAssertTrue(locals.isEmpty)
    }

    func testSameArrayPositionNeverMeansSameTarget() throws {
        let a = radial(), b = radial()
        let (selection, target) = try selected(a)
        var locals = [b]
        XCTAssertFalse(selection.setAdjustment(80, target: target, in: &locals, keyPath: \.exposure))
        XCTAssertEqual(locals, [b])
    }

    func testLookupFollowsIdentityAfterReordering() throws {
        let a = radial(), b = radial()
        let (selection, target) = try selected(a)
        var locals = [b, a]
        XCTAssertTrue(selection.setAdjustment(42, target: target, in: &locals, keyPath: \.exposure))
        XCTAssertEqual(locals[0], b)
        XCTAssertEqual(locals[1].id, a.id)
        XCTAssertEqual(locals[1].adjust.exposure, 42)
    }

    func testDeselectedTargetCannotWrite() throws {
        let a = radial(), b = radial()
        var (selection, target) = try selected(a)
        selection.select(b.id)
        var locals = [a, b]
        XCTAssertFalse(selection.setAdjustment(10, target: target, in: &locals, keyPath: \.contrast))
        XCTAssertEqual(locals, [a, b])
    }

    func testOldTokenCannotReviveAfterReselection() throws {
        let a = radial()
        var (selection, target) = try selected(a)
        selection.select(nil)
        selection.select(a.id)
        var locals = [a]
        XCTAssertFalse(selection.setAdjustment(10, target: target, in: &locals, keyPath: \.exposure))
        XCTAssertNotEqual(selection.target(in: locals), target)
    }

    func testUndoRedoRestorationDoesNotReviveOldCallbacks() throws {
        let a = radial()
        var (selection, target) = try selected(a)
        var locals = [a]
        let snapshot = locals
        selection.invalidate()
        locals.removeAll()
        selection.reconcile(locals)
        selection.invalidate()
        locals = snapshot
        selection.select(a.id)
        XCTAssertFalse(selection.setAdjustment(99, target: target, in: &locals, keyPath: \.exposure))
        XCTAssertEqual(locals, snapshot)
    }

    func testReconcileClearsRemovedSelection() throws {
        var (selection, _) = try selected(radial())
        selection.reconcile([])
        XCTAssertNil(selection.selectedID)
        XCTAssertNil(selection.target(in: []))
    }

    func testReconcileKeepsExistingIdentity() throws {
        let a = radial()
        var (selection, target) = try selected(a)
        selection.reconcile([a])
        XCTAssertEqual(selection.selectedID, a.id)
        XCTAssertEqual(selection.target(in: [a]), target)
    }

    func testDuplicateIDsFailClosed() throws {
        let a = radial()
        var (selection, target) = try selected(a)
        var locals = [a, a]
        XCTAssertNil(selection.target(in: locals))
        XCTAssertFalse(selection.setAdjustment(10, target: target, in: &locals, keyPath: \.exposure))
        selection.reconcile(locals)
        XCTAssertNil(selection.selectedID)
    }

    func testContextInvalidationRejectsLateEvents() throws {
        let a = radial()
        var (selection, target) = try selected(a)
        selection.invalidate()
        var locals = [a]
        XCTAssertFalse(selection.update(target, in: &locals) { $0.mask = .brush(strokes: []) })
        XCTAssertEqual(locals, [a])
    }

    func testChangingIdentityInsideUpdateIsRejected() throws {
        let a = radial(), b = radial()
        let (selection, target) = try selected(a)
        var locals = [a]
        XCTAssertFalse(selection.update(target, in: &locals) { $0 = b })
        XCTAssertEqual(locals, [a])
    }

    func testNonFiniteAdjustmentValuesAreRejected() throws {
        let a = radial()
        let (selection, target) = try selected(a)
        var locals = [a]
        for value in [Float.nan, .infinity, -.infinity] {
            XCTAssertFalse(selection.setAdjustment(value, target: target, in: &locals, keyPath: \.exposure))
        }
        XCTAssertEqual(locals, [a])
    }

    func testAdjustmentValuesAreClamped() throws {
        let a = radial()
        let (selection, target) = try selected(a)
        var locals = [a]
        XCTAssertTrue(selection.setAdjustment(500, target: target, in: &locals, keyPath: \.exposure))
        XCTAssertEqual(selection.adjustment(target, in: locals, keyPath: \.exposure), 100)
        XCTAssertTrue(selection.setAdjustment(-500, target: target, in: &locals, keyPath: \.exposure))
        XCTAssertEqual(selection.adjustment(target, in: locals, keyPath: \.exposure), -100)
    }

    func testNonFiniteStoredValueHasSafeDisplayFallback() throws {
        var a = radial()
        a.adjust.exposure = .nan
        let (selection, target) = try selected(a)
        XCTAssertEqual(selection.adjustment(target, in: [a], keyPath: \.exposure), 0)
    }

    func testSizeUpdatePreservesCurrentNotCapturedGeometry() throws {
        let a = radial()
        let (selection, target) = try selected(a)
        var locals = [a]
        locals[0].mask = .radial(center: NormPoint(0.2, 0.7), rx: 0.2, ry: 0.3, feather: 0.9, invert: true)
        XCTAssertTrue(selection.setRadialSize(80, target: target, in: &locals))
        guard case .radial(let c, let rx, let ry, let feather, let invert) = locals[0].mask else {
            return XCTFail("Expected radial mask")
        }
        XCTAssertEqual(c, NormPoint(0.2, 0.7))
        XCTAssertEqual(rx, 0.4, accuracy: 0.00001)
        XCTAssertEqual(ry, 0.6, accuracy: 0.00001)
        XCTAssertEqual(feather, 0.9)
        XCTAssertTrue(invert)
    }

    func testRadialControlCannotChangeAnotherMaskKind() throws {
        let a = LocalAdjustment(mask: .brush(strokes: []))
        let (selection, target) = try selected(a)
        var locals = [a]
        XCTAssertFalse(selection.setRadialSize(80, target: target, in: &locals))
        XCTAssertEqual(locals, [a])
    }

    func testInvalidRadialNumbersCannotReachDisplayOrMutation() throws {
        var a = radial()
        a.mask = .radial(center: NormPoint(0.5, 0.5), rx: .nan, ry: 0.2, feather: 0.6, invert: false)
        let (selection, target) = try selected(a)
        var locals = [a]
        XCTAssertEqual(selection.radialSize(target, in: locals), 4)
        XCTAssertFalse(selection.setRadialSize(.infinity, target: target, in: &locals))
        XCTAssertFalse(selection.setRadialSize(40, target: target, in: &locals))
    }

    func testRepeatedDeleteRestoreAndInsertDoesNotRetarget() throws {
        let a = radial()
        var (selection, oldTarget) = try selected(a)
        for _ in 0..<1_000 {
            selection.invalidate()
            var locals = [radial(), a]
            selection.select(a.id)
            XCTAssertFalse(selection.setAdjustment(90, target: oldTarget, in: &locals, keyPath: \.exposure))
            let current = try XCTUnwrap(selection.target(in: locals))
            XCTAssertTrue(selection.setAdjustment(15, target: current, in: &locals, keyPath: \.exposure))
            XCTAssertEqual(locals[0].adjust.exposure, 0)
            XCTAssertEqual(locals[1].adjust.exposure, 15)
            oldTarget = current
        }
    }
}
