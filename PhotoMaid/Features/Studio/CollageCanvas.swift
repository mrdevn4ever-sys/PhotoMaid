import PhotoMaidCore
import SwiftUI
import UIKit

/// Bühne über den Einstellungen: passt die Collage in die verfügbare Fläche. Lange Streifen werden scrollbar gezeigt.
struct CollageStage: View {
    @Bindable var model: CollageModel
    let box: CGSize

    var body: some View {
        if let p = model.project, let scene = model.scene {
            let fit = Self.fit(scene.aspect, in: box)
            if p.kind == .strip, let long = Self.scrollSize(scene.aspect, vertical: p.stripVertical, box: box, fit: fit) {
                ScrollView(p.stripVertical ? .vertical : .horizontal) {
                    canvas(long)
                        .padding(AppSpacing.xs)
                        .frame(minWidth: box.width, minHeight: box.height)
                }
                .frame(width: box.width, height: box.height)
            } else {
                canvas(fit).frame(width: box.width, height: box.height)
            }
        }
    }

    private func canvas(_ size: CGSize) -> some View {
        CollageCanvas(model: model, size: size)
            .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 2)
    }

    static func fit(_ aspect: Float, in box: CGSize) -> CGSize {
        let a = CGFloat(max(aspect, 0.0001))
        guard box.width > 0, box.height > 0 else { return .zero }
        return box.width / box.height > a ? CGSize(width: box.height * a, height: box.height)
            : CGSize(width: box.width, height: box.width / a)
    }

    /// Größe eines langen Streifens zum Scrollen (`nil` = passt gut in die Fläche).
    static func scrollSize(_ aspect: Float, vertical: Bool, box: CGSize, fit: CGSize) -> CGSize? {
        let a = CGFloat(max(aspect, 0.0001))
        if vertical {
            guard fit.width < box.width * 0.5 else { return nil }
            let w = min(box.width * 0.62, 340)
            return CGSize(width: w, height: w / a)
        }
        guard fit.height < box.height * 0.5 else { return nil }
        let h = box.height - 2 * AppSpacing.xs
        return CGSize(width: h * a, height: h)
    }
}

/// Interaktive Collage-Vorschau. Zeichnet mit `CollageGeometry` und `CollageRenderer.drawRect` – genau wie der Export.
/// Tippen wählt ein Foto, Ziehen verschiebt den Ausschnitt (Raster) bzw. das Foto (Frei), zwei Finger zoomen und drehen,
/// Halten und Ziehen tauscht zwei Felder. Weiße Griffe verschieben die Trennlinien. Nichts davon ist eine Entscheidung.
struct CollageCanvas: View {
    @Bindable var model: CollageModel
    let size: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var dragTarget: DragTarget?
    @State private var moved = false
    @State private var swapTarget: Int?
    @State private var holdTask: Task<Void, Never>?
    @State private var pinchTarget: PinchTarget?
    @State private var pinchScale: CGFloat = 1
    @State private var pinchAngle: Double = 0
    @State private var pinchActive = false
    @State private var rotateActive = false

    static let space = "collage-canvas"

    private enum DragTarget {
        case cell(index: Int, panX: Float, panY: Float)
        case free(index: Int, center: NormPoint)
        case swap(from: Int)
        case nothing
    }

    private enum PinchTarget {
        case layer(id: String, size: Float, rotation: Float)
        case cell(index: Int, zoom: Float)
        case free(index: Int, width: Float, rotation: Float)
    }

    var body: some View {
        if let p = model.project, let scene = model.scene {
            interactive(stage(p, scene), kind: p.kind)
        }
    }

    // MARK: Zeichnen

    private func stage(_ p: CollageProject, _ scene: CollageScene) -> some View {
        ZStack(alignment: .topLeading) {
            CollageBackgroundView(background: p.background, blurImage: blurImage(p), size: size)
            ForEach(scene.placements, id: \.index) { pl in
                placementView(pl, item: p.items[pl.index])
            }
            selectionLayer(scene)
            CollageLayerOverlay(layers: p.layers, size: size, scale: min(displayScale, 2)).equatable()
            if p.kind == .grid { dividerHandles(p) }
            ForEach(p.layers) { layer in
                CollageLayerHandle(model: model, layer: layer, canvas: size)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .contentShape(.rect)
        .coordinateSpace(.named(Self.space))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(key: "col_stage"))
    }

    private func blurImage(_ p: CollageProject) -> CGImage? {
        guard p.background.kind == .blur, !p.items.isEmpty else { return nil }
        let i = min(max(p.background.blurIndex, 0), p.items.count - 1)
        return model.image(for: p.items[i])
    }

    private func placementView(_ pl: CollagePlacement, item: CollageItem) -> some View {
        let frame = CollageRenderer.rect(pl.frame, size.width, size.height)
        let photo = CollageRenderer.rect(pl.photo, size.width, size.height)
        let short = min(size.width, size.height)
        return ZStack(alignment: .topLeading) {
            if pl.polaroid {
                RoundedRectangle(cornerRadius: CGFloat(pl.frameCorner) * short)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: short * 0.012, x: 0, y: short * 0.006)
                    .frame(width: frame.width, height: frame.height)
            }
            CollagePhotoTile(image: model.image(for: item), source: pl.source, size: photo.size,
                             corner: CGFloat(pl.photoCorner) * short)
                .offset(x: photo.minX - frame.minX, y: photo.minY - frame.minY)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .rotationEffect(.degrees(Double(pl.rotation)))
        .position(x: frame.midX, y: frame.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L("collage_photo_n", pl.index + 1)))
        .accessibilityAddTraits(model.selected == pl.index ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { select(pl.index) }
    }

    @ViewBuilder
    private func selectionLayer(_ scene: CollageScene) -> some View {
        if let s = model.selected, let pl = scene.placements.first(where: { $0.index == s }) {
            outline(pl, filled: false)
        }
        if let t = swapTarget, case .swap(let from)? = dragTarget,
           let source = scene.placements.first(where: { $0.index == from }) {
            outline(source, filled: true).opacity(0.6)
            if t != from, let target = scene.placements.first(where: { $0.index == t }) {
                outline(target, filled: true)
            }
        }
    }

    private func outline(_ pl: CollagePlacement, filled: Bool) -> some View {
        let frame = CollageRenderer.rect(pl.frame, size.width, size.height)
        let radius = CGFloat(pl.frameCorner) * min(size.width, size.height)
        return RoundedRectangle(cornerRadius: radius)
            .fill(filled ? AppColors.accentFill.opacity(0.3) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(AppColors.accentFill, lineWidth: 3))
            .frame(width: frame.width, height: frame.height)
            .rotationEffect(.degrees(Double(pl.rotation)))
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func dividerHandles(_ p: CollageProject) -> some View {
        let handles = p.dividerHandles().map { CollageDividerItem(id: $0.divider.path, divider: $0.divider, point: $0.point) }
        return ForEach(handles) { h in
            CollageDividerHandle(model: model, divider: h.divider, point: h.point, canvas: size)
        }
    }

    // MARK: Gesten

    @ViewBuilder
    private func interactive(_ content: some View, kind: CollageKind) -> some View {
        if kind == .strip {
            // Streifen können scrollen: nur Tippen, Reihenfolge über die Tasten im Bereich „Foto“.
            content.onTapGesture(coordinateSpace: .local) { location in tap(at: location) }
        } else {
            content
                .gesture(canvasDrag)
                .simultaneousGesture(pinch.simultaneously(with: twist))
        }
    }

    private var canvasDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in dragChanged(value) }
            .onEnded { value in dragEnded(value) }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !pinchActive {
                    pinchActive = true
                    // `startAnchor` (UnitPoint, iOS 17+) relativ zur Bühne → Punkt in derselben Fläche.
                    let anchor = value.startAnchor
                    beginPinch(at: CGPoint(x: anchor.x * size.width, y: anchor.y * size.height))
                }
                pinchScale = value.magnification
                applyPinch()
            }
            .onEnded { _ in
                pinchActive = false
                endPinchIfDone()
            }
    }

    private var twist: some Gesture {
        RotateGesture()
            .onChanged { value in
                if !rotateActive {
                    rotateActive = true
                    beginPinch(at: nil)
                }
                pinchAngle = value.rotation.degrees
                applyPinch()
            }
            .onEnded { _ in
                rotateActive = false
                endPinchIfDone()
            }
    }

    private func norm(_ p: CGPoint) -> (x: Float, y: Float) {
        (Float(p.x / max(size.width, 1)), Float(p.y / max(size.height, 1)))
    }

    private func hit(_ p: CGPoint) -> Int? {
        let n = norm(p)
        return model.scene?.hit(n.x, n.y)
    }

    private func dragChanged(_ v: DragGesture.Value) {
        guard let p = model.project else { return }
        if dragTarget == nil { beginDrag(at: v.startLocation, p) }
        if !moved && hypot(v.translation.width, v.translation.height) > 6 {
            moved = true
            if case .swap? = dragTarget {} else { holdTask?.cancel() }
        }
        guard moved, let target = dragTarget else { return }
        switch target {
        case .cell(let i, let startX, let startY):
            pan(i, startX: startX, startY: startY, translation: v.translation)
        case .free(let i, let start):
            if model.selected != i {
                model.selected = i
                model.selectedLayer = nil
            }
            let dx = Float(v.translation.width / max(size.width, 1)), dy = Float(v.translation.height / max(size.height, 1))
            model.update { proj in
                guard proj.items.indices.contains(i) else { return }
                proj.items[i].center = FreeLayout.moved(start, dx: dx, dy: dy)
            }
        case .swap:
            swapTarget = hit(v.location)
        case .nothing:
            break
        }
    }

    private func pan(_ i: Int, startX: Float, startY: Float, translation: CGSize) {
        guard let p = model.project, p.items.indices.contains(i), !p.items[i].fit,
              let pl = model.scene?.placements.first(where: { $0.index == i }) else { return }
        if model.selected != i { model.selected = i }
        let cell = CollageRenderer.rect(pl.frame, size.width, size.height)
        let item = p.items[i]
        let aspects = model.imageAspects
        let img = CollageGeometry.turnedAspect(i < aspects.count ? aspects[i] : 1, quarterTurns: item.quarterTurns)
        let cellAspect = Float(cell.width / max(cell.height, 1))
        let dx = Float(translation.width / max(cell.width, 1))
        let dy = Float(translation.height / max(cell.height, 1))
        let r = CellFit.panned(panX: startX, panY: startY, zoom: item.zoom, imgAspect: img, cellAspect: cellAspect,
                               dx: dx, dy: dy)
        model.update { proj in
            proj.items[i].panX = r.x
            proj.items[i].panY = r.y
        }
    }

    private func beginDrag(at point: CGPoint, _ p: CollageProject) {
        moved = false
        guard let i = hit(point), p.items.indices.contains(i) else {
            dragTarget = .nothing
            return
        }
        switch p.kind {
        case .grid:
            dragTarget = .cell(index: i, panX: p.items[i].panX, panY: p.items[i].panY)
            startHold(i)
        case .free:
            // Auswahl erst beim Ziehen (Tippen schaltet die Auswahl um, siehe `tap`).
            dragTarget = .free(index: i, center: p.items[i].center)
        case .strip:
            dragTarget = .nothing
        }
    }

    /// Halten (ohne zu ziehen) startet das Tauschen.
    private func startHold(_ i: Int) {
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, !moved, dragTarget != nil else { return }
            dragTarget = .swap(from: i)
            swapTarget = i
            model.selected = i
            Haptics.threshold()
        }
    }

    private func dragEnded(_ v: DragGesture.Value) {
        holdTask?.cancel()
        holdTask = nil
        defer {
            dragTarget = nil
            swapTarget = nil
            moved = false
        }
        if case .swap(let from)? = dragTarget {
            if let to = swapTarget, to != from, let p = model.project {
                model.replace(p.swap(from, to))
                model.selected = to
                Haptics.commit()
            }
            return
        }
        if !moved { tap(at: v.location) }
    }

    private func tap(at point: CGPoint) {
        model.selectedLayer = nil
        guard let i = hit(point) else {
            model.selected = nil
            return
        }
        if model.selected == i {
            model.selected = nil
        } else {
            select(i)
        }
    }

    private func select(_ i: Int) {
        model.selected = i
        model.selectedLayer = nil
        model.tab = .photo
    }

    private func beginPinch(at point: CGPoint?) {
        guard pinchTarget == nil, let p = model.project else { return }
        pinchScale = 1
        pinchAngle = 0
        if let id = model.selectedLayer, let layer = p.layers.first(where: { $0.id == id }),
           let t = CollageLayerEdit.transform(layer) {
            pinchTarget = .layer(id: id, size: t.size, rotation: t.rotation)
            return
        }
        var index = model.selected
        if let point, let h = hit(point) { index = h }
        guard let i = index, p.items.indices.contains(i) else { return }
        switch p.kind {
        case .grid:
            pinchTarget = .cell(index: i, zoom: p.items[i].zoom)
            model.selected = i
        case .free:
            pinchTarget = .free(index: i, width: p.items[i].width, rotation: p.items[i].rotation)
            model.selected = i
        case .strip:
            break
        }
    }

    private func applyPinch() {
        guard let target = pinchTarget else { return }
        let scale = Float(pinchScale), angle = Float(pinchAngle)
        switch target {
        case .layer(let id, let startSize, let startRotation):
            let rotation = LayerOps.snapRotation(FreeLayout.normalizedRotation(startRotation + angle)).value
            model.update { proj in
                proj.layers = proj.layers.map { l in
                    l.id == id ? CollageLayerEdit.withTransform(l, size: startSize * scale, rotation: rotation) : l
                }
            }
        case .cell(let i, let zoom):
            model.update { proj in
                guard proj.items.indices.contains(i), !proj.items[i].fit else { return }
                proj.items[i].zoom = CellFit.zoomed(zoom, by: scale)
            }
        case .free(let i, let width, let rotation):
            let r = LayerOps.snapRotation(FreeLayout.normalizedRotation(rotation + angle)).value
            model.update { proj in
                guard proj.items.indices.contains(i) else { return }
                proj.items[i].width = FreeLayout.clampWidth(width * scale)
                proj.items[i].rotation = r
            }
        }
    }

    private func endPinchIfDone() {
        guard !pinchActive, !rotateActive else { return }
        pinchTarget = nil
        pinchScale = 1
        pinchAngle = 0
    }
}

// MARK: - Bausteine

/// Ein Foto in seiner Fläche: ganzes Foto gleichmäßig skaliert, auf die Fläche beschnitten (wie `CollageRenderer`).
struct CollagePhotoTile: View {
    let image: CGImage?
    let source: NormRect
    let size: CGSize
    let corner: CGFloat

    var body: some View {
        content
            .frame(width: max(size.width, 0), height: max(size.height, 0), alignment: .topLeading)
            .clipShape(.rect(cornerRadius: corner))
    }

    @ViewBuilder private var content: some View {
        if let image {
            let r = CollageRenderer.drawRect(image, source: source, photo: CGRect(origin: .zero, size: size))
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
        } else {
            Rectangle().fill(Color.gray.opacity(0.25))
        }
    }
}

/// Hintergrund: Farbe oder weichgezeichnetes Foto (füllend, nie gestreckt).
private struct CollageBackgroundView: View {
    let background: CollageBackground
    let blurImage: CGImage?
    let size: CGSize

    var body: some View {
        ZStack {
            Color(uiColor: CollageRenderer.uiColor(background.color))
            if background.kind == .blur, let blurImage {
                Image(decorative: blurImage, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .blur(radius: min(size.width, size.height) * CollageRenderer.blurFraction, opaque: true)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Text und Sticker als Bild – derselbe `LayerRenderer` wie beim Speichern.
private struct CollageLayerOverlay: View, Equatable {
    let layers: [PhotoMaidCore.Layer]
    let size: CGSize
    let scale: CGFloat

    var body: some View {
        if let image = CollageRenderer.shared.layerOverlay(layers, size: PxSize(Int(size.width * scale), Int(size.height * scale))) {
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct CollageDividerItem: Identifiable {
    let id: [Int]
    let divider: PhotoMaidCore.Divider
    let point: NormPoint
}

/// Weißer Griff auf einer Trennlinie (Raster).
private struct CollageDividerHandle: View {
    @Bindable var model: CollageModel
    let divider: PhotoMaidCore.Divider
    let point: NormPoint
    let canvas: CGSize
    @State private var start: (project: CollageProject, divider: PhotoMaidCore.Divider)?

    var body: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: divider.vertical ? 8 : 30, height: divider.vertical ? 30 : 8)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            .contentShape(.rect)
            .position(x: CGFloat(point.x) * canvas.width, y: CGFloat(point.y) * canvas.height)
            .gesture(drag)
            .accessibilityElement()
            .accessibilityLabel(Text(key: divider.vertical ? "col_divider_v" : "col_divider_h"))
            .accessibilityAdjustableAction { direction in
                guard let p = model.project else { return }
                let position = divider.vertical ? point.x : point.y
                switch direction {
                case .increment: model.replace(p.movingDivider(divider, toCanvas: position + 0.04))
                case .decrement: model.replace(p.movingDivider(divider, toCanvas: position - 0.04))
                @unknown default: break
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(CollageCanvas.space))
            .onChanged { v in
                if start == nil, let p = model.project { start = (p, divider) }
                guard let s = start else { return }
                let value = s.divider.vertical ? v.location.x / max(canvas.width, 1) : v.location.y / max(canvas.height, 1)
                model.replace(s.project.movingDivider(s.divider, toCanvas: Float(value)))
            }
            .onEnded { _ in start = nil }
    }
}

/// Unsichtbare Anfassfläche über einem Text/Sticker: antippen wählt, ziehen verschiebt.
private struct CollageLayerHandle: View {
    @Bindable var model: CollageModel
    let layer: PhotoMaidCore.Layer
    let canvas: CGSize
    @State private var start: NormPoint?

    private var selected: Bool { model.selectedLayer == layer.id }

    var body: some View {
        if let center = CollageLayerEdit.center(layer), let box = CollageLayerEdit.box(layer, canvas: canvas) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: max(box.width, AppSpacing.minTouch), height: max(box.height, AppSpacing.minTouch))
                .overlay {
                    if selected {
                        Rectangle()
                            .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .shadow(color: .black.opacity(0.6), radius: 1)
                            .frame(width: box.width, height: box.height)
                    }
                }
                .contentShape(.rect)
                .rotationEffect(.degrees(Double(CollageLayerEdit.transform(layer)?.rotation ?? 0)))
                .position(x: CGFloat(center.x) * canvas.width, y: CGFloat(center.y) * canvas.height)
                .gesture(drag(center))
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: CollageLayerEdit.name(layer)))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
                .accessibilityAction { choose() }
        }
    }

    private func choose() {
        model.selectedLayer = layer.id
        model.selected = nil
        model.tab = .decor
    }

    private func drag(_ center: NormPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(CollageCanvas.space))
            .onChanged { v in
                if start == nil {
                    start = center
                    choose()
                }
                guard let s = start else { return }
                let dx = Float(v.translation.width / max(canvas.width, 1))
                let dy = Float(v.translation.height / max(canvas.height, 1))
                let c = NormPoint(min(max(s.x + dx, 0), 1), min(max(s.y + dy, 0), 1))
                let id = layer.id
                model.update { proj in
                    proj.layers = proj.layers.map { $0.id == id ? CollageLayerEdit.withCenter($0, c) : $0 }
                }
            }
            .onEnded { _ in start = nil }
    }
}

/// Kleine Hilfen für Text- und Sticker-Ebenen der Collage (dieselben Ebenen wie im Foto-Editor).
enum CollageLayerEdit {
    static func center(_ l: PhotoMaidCore.Layer) -> NormPoint? {
        switch l {
        case .text(let t): t.center
        case .sticker(let s): s.center
        default: nil
        }
    }

    static func withCenter(_ l: PhotoMaidCore.Layer, _ c: NormPoint) -> PhotoMaidCore.Layer {
        switch l {
        case .text(var t): t.center = c; return .text(t)
        case .sticker(var s): s.center = c; return .sticker(s)
        default: return l
        }
    }

    static func transform(_ l: PhotoMaidCore.Layer) -> (size: Float, rotation: Float)? {
        switch l {
        case .text(let t): return (size: t.size, rotation: t.rotation)
        case .sticker(let s): return (size: s.size, rotation: s.rotation)
        default: return nil
        }
    }

    /// Größe begrenzt wie `Layer.transformed` (Text 1–60 %, Sticker 3–120 % der kürzeren Kante).
    static func withTransform(_ l: PhotoMaidCore.Layer, size: Float, rotation: Float) -> PhotoMaidCore.Layer {
        switch l {
        case .text(var t):
            t.size = min(max(size, 0.01), 0.6)
            t.rotation = rotation
            return .text(t)
        case .sticker(var s):
            s.size = min(max(size, 0.03), 1.2)
            s.rotation = rotation
            return .sticker(s)
        default:
            return l
        }
    }

    static func withColor(_ l: PhotoMaidCore.Layer, _ c: ARGB) -> PhotoMaidCore.Layer {
        switch l {
        case .text(var t): t.color = c; return .text(t)
        case .sticker(var s): s.color = c; return .sticker(s)
        default: return l
        }
    }

    static func color(_ l: PhotoMaidCore.Layer) -> ARGB? {
        switch l {
        case .text(let t): t.color
        case .sticker(let s): s.color
        default: nil
        }
    }

    /// Ungedrehte Größe in Punkten (gleiche Schrift und Maße wie `LayerRenderer`).
    static func box(_ l: PhotoMaidCore.Layer, canvas: CGSize) -> CGSize? {
        let short = min(canvas.width, canvas.height)
        switch l {
        case .text(let t):
            let fs = max(1, CGFloat(t.size) * short)
            let text = NSAttributedString(string: t.text, attributes: [.font: LayerRenderer.font(t.font, size: fs)])
            let b = text.boundingRect(with: CGSize(width: canvas.width * 0.95, height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral
            let pad = t.style == .pill ? fs * 0.45 : fs * 0.12
            return CGSize(width: b.width + 2 * pad, height: b.height + 2 * pad)
        case .sticker(let s):
            let d = CGFloat(s.size) * short
            return CGSize(width: d, height: d)
        default:
            return nil
        }
    }

    static func name(_ l: PhotoMaidCore.Layer) -> String {
        switch l {
        case .text(let t): t.text
        case .sticker(let s): s.kind == .emoji ? s.value : CollageStickerNames.name(s.kind)
        default: ""
        }
    }
}

/// Namen der Sticker (Texte wie im Foto-Editor).
enum CollageStickerNames {
    static func name(_ k: StickerKind) -> String {
        switch k {
        case .emoji: L("edit_mk_emoji")
        case .arrow: L("edit_st_arrow")
        case .heart: L("edit_st_heart")
        case .star: L("edit_st_star")
        case .check: L("edit_st_check")
        case .cross: L("edit_st_cross")
        case .bubble: L("edit_st_bubble")
        case .circle: L("edit_st_circle")
        case .sparkle: L("edit_st_sparkle")
        case .date: L("edit_st_date")
        }
    }

    static func symbol(_ k: StickerKind) -> String {
        switch k {
        case .emoji: "face.smiling"
        case .arrow: "arrow.right"
        case .heart: "heart.fill"
        case .star: "star.fill"
        case .check: "checkmark"
        case .cross: "xmark"
        case .bubble: "bubble.left.fill"
        case .circle: "circle"
        case .sparkle: "sparkles"
        case .date: "calendar"
        }
    }
}
