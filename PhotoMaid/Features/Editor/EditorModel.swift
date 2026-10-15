import CoreImage
import Foundation
import Observation
import Photos
import PhotoMaidCore
import UIKit
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable, Hashable {
    case crop, adjust, filter, retouch, markup, frame, resize
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .crop: "edit_tab_crop"
        case .adjust: "edit_tab_adjust"
        case .filter: "edit_tab_filter"
        case .retouch: "edit_tab_retouch"
        case .markup: "edit_tab_markup"
        case .frame: "edit_tab_frame"
        case .resize: "edit_tab_resize"
        }
    }

    var symbol: String {
        switch self {
        case .crop: "crop.rotate"
        case .adjust: "dial.medium"
        case .filter: "camera.filters"
        case .retouch: "wand.and.rays"
        case .markup: "pencil.tip.crop.circle"
        case .frame: "square.dashed"
        case .resize: "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// Regler im Werkzeug „Anpassen“ (Gruppen wie Android).
enum AdjustParam: String, CaseIterable, Identifiable, Hashable {
    case exposure, brightness, contrast, highlights, shadows, whites, blacks
    case warmth, tint, saturation, vibrance
    case clarity, sharpness, sharpenRadius, sharpenThreshold, noiseReduction
    case vignette, grain
    var id: String { rawValue }

    var group: String {
        switch self {
        case .exposure, .brightness, .contrast, .highlights, .shadows, .whites, .blacks: "edit_grp_light"
        case .warmth, .tint, .saturation, .vibrance: "edit_grp_color"
        case .clarity, .sharpness, .sharpenRadius, .sharpenThreshold, .noiseReduction: "edit_grp_detail"
        case .vignette, .grain: "edit_grp_effects"
        }
    }

    var titleKey: String {
        switch self {
        case .sharpenRadius: "edit_adj_sharpen_radius"
        case .sharpenThreshold: "edit_adj_sharpen_threshold"
        case .noiseReduction: "edit_adj_noise"
        default: "edit_adj_\(rawValue)"
        }
    }

    var range: ClosedRange<Float> {
        switch self {
        case .sharpness, .sharpenRadius, .sharpenThreshold, .grain, .noiseReduction: 0...100
        default: -100...100
        }
    }

    var symbol: String {
        switch self {
        case .exposure: "plusminus.circle"
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .highlights: "sun.max.circle"
        case .shadows: "moon.circle"
        case .whites: "circle"
        case .blacks: "circle.fill"
        case .warmth: "thermometer.medium"
        case .tint: "drop"
        case .saturation: "drop.halffull"
        case .vibrance: "paintpalette"
        case .clarity: "triangle"
        case .sharpness: "rhombus"
        case .sharpenRadius: "smallcircle.filled.circle"
        case .sharpenThreshold: "line.3.horizontal.decrease"
        case .noiseReduction: "aqi.medium"
        case .vignette: "circle.dashed"
        case .grain: "circle.grid.3x3"
        }
    }

    var keyPath: WritableKeyPath<Adjustments, Float> {
        switch self {
        case .exposure: \.exposure
        case .brightness: \.brightness
        case .contrast: \.contrast
        case .highlights: \.highlights
        case .shadows: \.shadows
        case .whites: \.whites
        case .blacks: \.blacks
        case .warmth: \.warmth
        case .tint: \.tint
        case .saturation: \.saturation
        case .vibrance: \.vibrance
        case .clarity: \.clarity
        case .sharpness: \.sharpness
        case .sharpenRadius: \.sharpenRadius
        case .sharpenThreshold: \.sharpenThreshold
        case .noiseReduction: \.noiseReduction
        case .vignette: \.vignette
        case .grain: \.grain
        }
    }
}

/// Zustand des Foto-Editors: nicht destruktives Rezept, Rückgängig/Wiederholen, Vorschau aus demselben Graphen wie der
/// Export. Das Original wird nie überschrieben.
@MainActor
@Observable
final class EditorModel {
    let assetID: String
    private(set) var asset: MediaAsset?
    private(set) var loadState: LoadState = .loading
    var recipe = EditRecipe() {
        didSet {
            if recipe.locals.map(\.id) != oldValue.locals.map(\.id) {
                retouchSelection.invalidate()
                retouchSelection.reconcile(recipe.locals)
            }
            if recipe != oldValue { schedulePreview() }
        }
    }
    private(set) var history: [EditRecipe] = []
    private(set) var future: [EditRecipe] = []
    var tool: EditorTool = .crop {
        willSet { if newValue != tool { finishRetouchInteraction() } }
        didSet {
            // Only crop mode changes the preview recipe. Other tool switches
            // must not queue an identical expensive render before drawing.
            if (tool == .crop) != (oldValue == .crop) { schedulePreview() }
        }
    }
    var retouchMode: RetouchMode = .redEye {
        willSet {
            if newValue != retouchMode {
                finishRetouchInteraction()
                retouchSelection.select(nil)
            }
        }
    }
    var localParam: AdjustParam = .exposure {
        willSet { if newValue != localParam { finishRetouchInteraction() } }
    }
    var param: AdjustParam = .exposure
    var comparing = false
    var aspect: AspectPreset = .free
    var landscape = true
    var selectedLayer: String?
    private(set) var retouchSelection = RetouchSelection()
    var selectedLocalID: UUID? { retouchSelection.selectedID }
    var retouchRevision: UUID { retouchSelection.revision }
    var retouchTarget: RetouchTarget? { retouchSelection.target(in: recipe.locals) }
    var cropEditing: Bool { tool == .crop }
    private(set) var preview: UIImage?
    private(set) var original: UIImage?
    private(set) var fullSize = PxSize(1, 1)
    private(set) var saving = false

    enum LoadState: Equatable { case loading, ready, iCloud, failed }

    @ObservationIgnored private var sourceData: Data?
    @ObservationIgnored private var previewSource: UncheckedBox<CIImage>?
    @ObservationIgnored private var renderGeneration = 0
    @ObservationIgnored private var rendering = false
    @ObservationIgnored private var dirty = false
    private(set) var previewRendering = false
    @ObservationIgnored private var gestureStart: EditRecipe?

    init(assetID: String) { self.assetID = assetID }

    var hasChanges: Bool { !recipe.isIdentity }
    private var hasPendingChange: Bool { gestureStart.map { $0 != recipe } ?? false }
    var canUndo: Bool { !history.isEmpty || hasPendingChange }
    var canRedo: Bool { !future.isEmpty && !hasPendingChange }

    // MARK: Laden

    func load(app: AppModel, allowNetwork: Bool = true) async {
        loadState = .loading
        asset = app.asset(assetID)
        guard let ph = PhotoLibraryService.phAsset(assetID) else { loadState = .failed; return }
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = allowNetwork
        o.version = .current
        o.deliveryMode = .highQualityFormat
        let box = UncheckedBox(ph)
        let result: (Data?, Bool) = await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: box.value, options: o) { @Sendable data, _, _, info in
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                cont.resume(returning: (data, inCloud))
            }
        }
        guard let data = result.0 else { loadState = result.1 ? .iCloud : .failed; return }
        let prepared = await Task.detached(priority: .userInitiated) { () -> (UncheckedBox<CIImage>, PxSize, UIImage?)? in
            guard let src = EditRenderer.source(data) else { return nil }
            let size = PxSize(Int(src.extent.width), Int(src.extent.height))
            let small = EditRenderer.downscaled(src, maxEdge: 1800)
            let orig = EditRenderer.shared.cgImage(small).map { UIImage(cgImage: $0) }
            return (UncheckedBox(small), size, orig)
        }.value
        guard let prepared else { loadState = .failed; return }
        sourceData = data
        previewSource = prepared.0
        fullSize = prepared.1
        original = prepared.2
        preview = prepared.2
        landscape = fullSize.width >= fullSize.height
        loadState = .ready
        schedulePreview()
    }

    var data: Data? { sourceData }

    // MARK: Rückgängig

    /// Vor einer Änderung aufrufen (ein Schritt je Geste/Tipp).
    func checkpoint() {
        history.append(recipe)
        if history.count > 100 { history.removeFirst() }
        future = []
    }

    /// Fortlaufende Änderungen (Regler, Ziehen): Anfang merken, Ende = ein Rückgängig-Schritt.
    func beginChange() { if gestureStart == nil { gestureStart = recipe } }

    func endChange() {
        guard let start = gestureStart else { return }
        gestureStart = nil
        if start != recipe {
            history.append(start)
            if history.count > 100 { history.removeFirst() }
            future = []
        }
    }

    func undo() {
        finishRetouchInteraction()
        guard let prev = history.popLast() else { return }
        future.append(recipe)
        recipe = prev
    }

    func redo() {
        finishRetouchInteraction()
        guard let next = future.popLast() else { return }
        history.append(recipe)
        recipe = next
    }

    func update(_ change: (inout EditRecipe) -> Void) {
        finishRetouchInteraction()
        var next = recipe
        change(&next)
        guard next != recipe else { return }
        checkpoint()
        recipe = next
    }

    // MARK: Retouch identity, binding lifetime and gesture transactions

    /// Settle an in-flight edit BEFORE replacing its recipe or editing context.
    /// Delayed callbacks retain their old revision and cannot reopen this undo group.
    func finishRetouchInteraction() {
        endChange()
        retouchSelection.invalidate()
    }

    func selectLocal(_ id: UUID?) {
        guard id != selectedLocalID else { return }
        finishRetouchInteraction()
        retouchSelection.select(id)
        retouchSelection.reconcile(recipe.locals)
    }

    func local(_ target: RetouchTarget) -> LocalAdjustment? {
        retouchSelection.local(target, in: recipe.locals)
    }

    func beginLocalChange(_ target: RetouchTarget) {
        guard tool == .retouch, local(target) != nil else { return }
        beginChange()
    }

    func endLocalChange(_ target: RetouchTarget) {
        guard local(target) != nil else { return }
        endChange()
    }

    func adjustmentBinding(_ target: RetouchTarget, parameter: AdjustParam) -> Binding<Float> {
        // Both target and parameter are immutable snapshots; the array position is not.
        let keyPath = parameter.keyPath
        return Binding(get: {
            self.retouchSelection.adjustment(target, in: self.recipe.locals, keyPath: keyPath)
        }, set: { value in
            guard self.tool == .retouch else { return }
            var locals = self.recipe.locals
            if self.retouchSelection.setAdjustment(value, target: target, in: &locals, keyPath: keyPath) {
                self.recipe.locals = locals
            }
        })
    }

    func radialSizeBinding(_ target: RetouchTarget) -> Binding<Float> {
        Binding(get: {
            self.retouchSelection.radialSize(target, in: self.recipe.locals)
        }, set: { value in
            guard self.tool == .retouch else { return }
            var locals = self.recipe.locals
            if self.retouchSelection.setRadialSize(value, target: target, in: &locals) {
                self.recipe.locals = locals
            }
        })
    }

    func changeLocal(_ target: RetouchTarget, _ change: (inout LocalAdjustment) -> Void) {
        guard tool == .retouch else { return }
        var locals = recipe.locals
        if retouchSelection.update(target, in: &locals, change) { recipe.locals = locals }
    }

    func deleteLocal(_ target: RetouchTarget) {
        guard tool == .retouch, local(target) != nil else { return }
        update { $0.locals.removeAll { $0.id == target.id } }
    }

    func addLocal(mask: Mask) {
        let local = LocalAdjustment(mask: mask)
        update { $0.locals.append(local) }
        retouchSelection.select(local.id)
    }

    /// The pre-creation snapshot belongs to the same undo step as the complete stroke.
    func beginLocalGesture(mask: Mask, reuseBrush: Bool = false) -> RetouchTarget? {
        guard tool == .retouch else { return nil }
        finishRetouchInteraction()
        beginChange()
        if reuseBrush, let target = retouchTarget, let current = local(target), case .brush = current.mask {
            return target
        }
        let local = LocalAdjustment(mask: mask)
        recipe.locals.append(local)
        retouchSelection.select(local.id)
        return retouchTarget
    }

    // MARK: Vorschau (gleicher Graph wie der Export)

    /// Im Zuschneiden: ganzer Rahmen ohne Ausschnitt (der Rahmen wird darübergelegt).
    var previewRecipe: EditRecipe {
        var r = recipe
        if tool == .crop { r.crop = .full; r.frame = nil }
        return r
    }

    private func schedulePreview() {
        guard previewSource != nil else { return }
        // Invalidate even while a render is running. Otherwise an old drawing
        // can be published AFTER undo, before the queued current recipe finishes.
        renderGeneration += 1
        previewRendering = true
        if rendering { dirty = true; return }
        rendering = true
        let generation = renderGeneration
        let src = previewSource!
        let r = previewRecipe
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                let out = EditRenderer.shared.render(src.value, recipe: r, forPreview: true)
                return EditRenderer.shared.cgImage(out).map { UIImage(cgImage: $0) }
            }.value
            guard let self else { return }
            if generation == self.renderGeneration, let image { self.preview = image }
            self.rendering = false
            if self.dirty { self.dirty = false; self.schedulePreview() }
            else { self.previewRendering = false }
        }
    }

    /// Rahmengröße für das Zuschneiden (nach Drehung und Perspektive, vor dem Ausschnitt), in Pixeln des Originals.
    var cropFrame: PxSize { EditGeometry(src: fullSize, recipe: recipe).frame }
    var outputSize: PxSize { EditRenderer.outputSize(src: fullSize, recipe: recipe) }

    func applyAspect(_ p: AspectPreset) {
        aspect = p
        guard let ratio = CropMath.ratio(p, frame: cropFrame, landscape: landscape) else { return }
        update { $0.crop = CropMath.fitAspect($0.crop, ratio: ratio, frame: cropFrame) }
    }

    var aspectRatio: Double? { CropMath.ratio(aspect, frame: cropFrame, landscape: landscape) }

    func rotate() {
        update { $0 = $0.rotatedClockwise() }
        if aspect != .free && aspect != .original { landscape.toggle() }
    }

    func setSaving(_ v: Bool) { if v { finishRetouchInteraction() }; saving = v }
}
