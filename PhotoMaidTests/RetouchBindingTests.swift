import Foundation
import SwiftUI
import Testing
import PhotoMaidCore
@testable import PhotoMaid

/// Actual SwiftUI Bindings are retained across recipe changes; no PhotoKit access is needed.
@MainActor
struct RetouchBindingTests {
    private func editor() -> EditorModel {
        let model = EditorModel(assetID: "retouch-regression")
        model.tool = .retouch
        model.retouchMode = .radial
        model.addLocal(mask: .radial(center: NormPoint(0.5, 0.5), rx: 0.18, ry: 0.18, feather: 0.6, invert: false))
        return model
    }

    @Test func retainedBindingsAreSafeAfterDelete() throws {
        let model = editor()
        let target = try #require(model.retouchTarget)
        let exposure = model.adjustmentBinding(target, parameter: .exposure)
        let size = model.radialSizeBinding(target)
        model.deleteLocal(target)
        #expect(exposure.wrappedValue == 0)
        #expect(size.wrappedValue == 4)
        let historyCount = model.history.count
        exposure.wrappedValue = 75
        size.wrappedValue = 90
        model.beginLocalChange(target)
        model.endLocalChange(target)
        model.deleteLocal(target)
        #expect(model.recipe.locals.isEmpty)
        #expect(model.selectedLocalID == nil)
        #expect(model.history.count == historyCount)
    }

    @Test func undoingCreationInvalidatesBindingAndRedoDoesNotReviveIt() throws {
        let model = editor()
        let target = try #require(model.retouchTarget)
        let binding = model.adjustmentBinding(target, parameter: .exposure)
        model.undo()
        #expect(model.recipe.locals.isEmpty)
        #expect(binding.wrappedValue == 0)
        model.redo()
        #expect(model.recipe.locals.first?.id == target.id)
        model.selectLocal(target.id)
        binding.wrappedValue = 90
        #expect(model.recipe.locals.first?.adjust.exposure == 0)
    }

    @Test func resetSettlesGestureAndLateEndDoesNotPolluteHistory() throws {
        let model = editor()
        let target = try #require(model.retouchTarget)
        let binding = model.adjustmentBinding(target, parameter: .exposure)
        model.beginLocalChange(target)
        binding.wrappedValue = 25
        model.update { $0 = EditRecipe() }
        let count = model.history.count
        binding.wrappedValue = 50
        model.endLocalChange(target)
        #expect(model.history.count == count)
        #expect(model.recipe.locals.isEmpty)
        model.undo()
        #expect(model.recipe.locals.first?.adjust.exposure == 25)
    }

    @Test func geometryOnlySaveInvalidatesRetouch() throws {
        let model = editor()
        let target = try #require(model.retouchTarget)
        let binding = model.radialSizeBinding(target)
        model.update { $0 = $0.withoutProTools() }
        binding.wrappedValue = 80
        #expect(model.recipe.locals.isEmpty)
        #expect(model.retouchTarget == nil)
    }

    @Test func parameterChangeFreezesOldBindingAndEndsOneUndoGroup() throws {
        let model = editor()
        let target = try #require(model.retouchTarget)
        let old = model.adjustmentBinding(target, parameter: .exposure)
        model.beginLocalChange(target)
        old.wrappedValue = 30
        model.localParam = .contrast
        let count = model.history.count
        old.wrappedValue = 90
        model.endLocalChange(target)
        #expect(model.recipe.locals.first?.adjust.exposure == 30)
        #expect(model.recipe.locals.first?.adjust.contrast == 0)
        #expect(model.history.count == count)
    }

    @Test func modeChangeRejectsOldControl() throws {
        let model = editor()
        let target = try #require(model.retouchTarget)
        let old = model.adjustmentBinding(target, parameter: .exposure)
        model.retouchMode = .brush
        old.wrappedValue = 90
        #expect(model.selectedLocalID == nil)
        #expect(model.recipe.locals.first?.adjust.exposure == 0)
    }

    @Test func toolChangeAndReturnDoNotReviveOldControl() throws {
        let model = editor()
        let target = try #require(model.retouchTarget)
        let old = model.adjustmentBinding(target, parameter: .exposure)
        model.tool = .crop
        model.tool = .retouch
        old.wrappedValue = 90
        #expect(model.recipe.locals.first?.adjust.exposure == 0)
    }

    @Test func undoDuringLinearGestureDropsLateUpdates() throws {
        let model = EditorModel(assetID: "linear-regression")
        model.tool = .retouch
        model.retouchMode = .linear
        let mask = Mask.linear(start: NormPoint(0.1, 0.1), end: NormPoint(0.6, 0.6))
        let target = try #require(model.beginLocalGesture(mask: mask))
        #expect(model.canUndo)
        model.undo()
        model.changeLocal(target) { $0.mask = .linear(start: NormPoint(0, 0), end: NormPoint(1, 1)) }
        model.endLocalChange(target)
        #expect(model.recipe.locals.isEmpty)
        #expect(model.canRedo)
        model.redo()
        #expect(model.recipe.locals.first?.mask == mask)
    }

    @Test func brushCreationAndStrokeRemainOneUndoStep() throws {
        let model = EditorModel(assetID: "brush-regression")
        model.tool = .retouch
        model.retouchMode = .brush
        let target = try #require(model.beginLocalGesture(mask: .brush(strokes: []), reuseBrush: true))
        model.changeLocal(target) {
            $0.mask = .brush(strokes: [BrushStroke(points: [NormPoint(0.2, 0.3)], radius: 0.04)])
        }
        model.endLocalChange(target)
        #expect(model.history.count == 1)
        model.undo()
        #expect(model.recipe.locals.isEmpty)
        model.redo()
        #expect(model.recipe.locals.first?.id == target.id)
    }

    @Test func oldEndCannotCloseANewerGestureOnRestoredIdentity() throws {
        let model = editor()
        let old = try #require(model.retouchTarget)
        model.deleteLocal(old)
        model.undo()
        model.selectLocal(old.id)
        let current = try #require(model.retouchTarget)
        model.beginLocalChange(current)
        model.adjustmentBinding(current, parameter: .exposure).wrappedValue = 12
        let count = model.history.count
        model.endLocalChange(old)
        #expect(model.history.count == count)
        model.endLocalChange(current)
        #expect(model.history.count == count + 1)
    }

    @Test func recipeRoundTripKeepsLocalIdentity() throws {
        let model = editor()
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(model.recipe))
        #expect(decoded == model.recipe)
        #expect(decoded.locals.first?.id == model.selectedLocalID)
    }
}
