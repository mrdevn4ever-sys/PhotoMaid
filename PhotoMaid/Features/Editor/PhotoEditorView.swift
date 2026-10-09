import PhotoMaidCore
import SwiftUI

/// Foto-Editor (immer dunkel): nicht destruktives Rezept, Vorschau = Export (ein Core-Image-Graph), Speichern nur als
/// neue Datei (Vorauswahl „Als Kopie speichern“). Nie verzerren, nie hochskalieren, keine Werbung.
struct PhotoEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditorModel
    @State private var zoom: CGFloat = 1
    @State private var confirmDiscard = false
    @State private var saveSheet = false
    @State private var proSheet = false
    @State private var retouchMode: RetouchMode = .redEye
    @State private var markupMode: MarkupMode = .select
    @State private var stroke: [NormPoint] = []
    @State private var dragStart: CGPoint?
    @State private var dragLayer: Layer?
    @State private var cropHandle: CropMath.Handle?
    @State private var cropStart: NormRect?

    init(assetID: String) { _model = State(initialValue: EditorModel(assetID: assetID)) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: AppSpacing.s) {
                header
                stageArea
                if model.loadState == .ready { toolZone }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await model.load(app: app)
            if model.loadState == .ready { model.tool = .adjust }
        }
        .confirmationDialog(L("edit_discard_title"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L("edit_discard"), role: .destructive) { dismiss() }
            Button(L("edit_keep_editing"), role: .cancel) {}
        } message: {
            Text(key: "edit_discard_text")
        }
        .sheet(isPresented: $saveSheet) { EditSaveSheet(model: model) { dismiss() } }
        .sheet(isPresented: $proSheet) {
            EditProSheet {
                proSheet = false
                model.update { $0 = $0.withoutProTools() }
                saveSheet = true
            } openPro: {
                proSheet = false
                dismiss()
                app.navigate(.pro)
            }
        }
    }

    private var header: some View {
        EditorHeader(cancel: {
            if model.hasChanges { confirmDiscard = true } else { dismiss() }
        }, confirm: {
            guard model.hasChanges else { dismiss(); return }
            if model.recipe.usesProTools && !app.capabilities.hasProToolsAccess { proSheet = true } else { saveSheet = true }
        }, confirmEnabled: model.loadState == .ready && !model.saving) {
            HStack(spacing: AppSpacing.s) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo).accessibilityLabel(Text(key: "undo"))
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo).accessibilityLabel(Text(key: "redo"))
                Menu {
                    Button(L("edit_reset_all"), role: .destructive) { model.update { $0 = EditRecipe() } }
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel(Text(key: "more_actions"))
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(height: AppSpacing.touch)
            .padding(.horizontal, AppSpacing.m)
            .glassCapsule()
        }
    }

    // MARK: Bühne

    @ViewBuilder
    private var stageArea: some View {
        switch model.loadState {
        case .loading:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ErrorState(message: L("edit_err_load")).frame(maxHeight: .infinity)
        case .iCloud:
            VStack(spacing: AppSpacing.m) {
                Text(key: "feed_icloud_only").foregroundStyle(.white)
                Button(L("feed_icloud_load")) { Task { await model.load(app: app, allowNetwork: true) } }.buttonStyle(.glassProminent)
            }
            .frame(maxHeight: .infinity)
        case .ready:
            GeometryReader { geo in
                let image = model.comparing ? model.original : model.preview
                let rect = fitRect(image?.size ?? CGSize(width: 1, height: 1), in: geo.size)
                ZoomableStage(zoom: $zoom) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                        overlay(rect)
                    }
                }
                .contentShape(.rect)
                .gesture(stageGesture(rect), including: zoom > 1.01 ? .subviews : .all)
                .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 8, pressing: { pressing in
                    if model.tool == .adjust || model.tool == .filter { model.comparing = pressing }
                }, perform: {})
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(key: "edit_compare_hint"))
            }
            .padding(.horizontal, AppSpacing.xs)
        }
    }

    private func fitRect(_ img: CGSize, in box: CGSize) -> CGRect {
        guard img.width > 0, img.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let s = min(box.width / img.width, box.height / img.height)
        let w = img.width * s, h = img.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    private func norm(_ p: CGPoint, _ rect: CGRect) -> NormPoint {
        NormPoint(Float((p.x - rect.minX) / max(1, rect.width)), Float((p.y - rect.minY) / max(1, rect.height)))
    }

    @ViewBuilder
    private func overlay(_ rect: CGRect) -> some View {
        switch model.tool {
        case .crop:
            CropOverlay(crop: model.recipe.crop, rect: rect) { handle, translation in
                if cropHandle == nil { cropHandle = handle; cropStart = model.recipe.crop; model.beginChange() }
                guard let start = cropStart else { return }
                model.recipe.crop = CropMath.drag(start, handle: handle, dx: Float(translation.width / rect.width),
                                                  dy: Float(translation.height / rect.height), frame: model.cropFrame,
                                                  ratio: model.aspectRatio)
            } ended: {
                cropHandle = nil; cropStart = nil; model.endChange()
            }
        case .retouch:
            RetouchOverlay(recipe: model.recipe, rect: rect, selected: model.selectedLocal)
        case .markup:
            MarkupOverlay(recipe: model.recipe, rect: rect, selected: model.selectedLayer, stroke: stroke)
        default:
            EmptyView()
        }
    }

    /// Tippen/Ziehen auf der Bühne je Werkzeug. Ziehen ist hier nie eine Entscheidung.
    private func stageGesture(_ rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = norm(v.location, rect)
                switch model.tool {
                case .retouch: retouchDrag(p, start: norm(v.startLocation, rect), translation: v.translation)
                case .markup: markupDrag(p, start: norm(v.startLocation, rect), rect: rect, translation: v.translation)
                default: break
                }
            }
            .onEnded { v in
                let p = norm(v.location, rect)
                let isTap = hypot(v.translation.width, v.translation.height) < 6
                switch model.tool {
                case .retouch: retouchEnd(p, isTap: isTap)
                case .markup: markupEnd(p, start: norm(v.startLocation, rect), isTap: isTap)
                default: break
                }
            }
    }

    // MARK: Retusche

    private func retouchDrag(_ p: NormPoint, start: NormPoint, translation: CGSize) {
        switch retouchMode {
        case .brush:
            if stroke.isEmpty { model.beginChange() }
            stroke.append(p)
            ensureBrushLocal()
            if let i = model.selectedLocal, case .brush(var strokes) = model.recipe.locals[i].mask {
                let s = BrushStroke(points: stroke, radius: 0.04, hardness: 0.5, erase: false)
                if strokes.isEmpty || stroke.count == 1 { strokes.append(s) } else { strokes[strokes.count - 1] = s }
                model.recipe.locals[i].mask = .brush(strokes: strokes)
            }
        case .linear:
            guard hypot(translation.width, translation.height) > 6 else { return }
            if dragStart == nil {
                dragStart = .zero
                model.beginChange()
                model.recipe.locals.append(LocalAdjustment(mask: .linear(start: start, end: p)))
                model.selectedLocal = model.recipe.locals.count - 1
            } else if let i = model.selectedLocal {
                model.recipe.locals[i].mask = .linear(start: start, end: p)
            }
        default:
            break
        }
    }

    private func retouchEnd(_ p: NormPoint, isTap: Bool) {
        defer { stroke = []; dragStart = nil }
        switch retouchMode {
        case .redEye where isTap:
            model.update { $0.redEyes.append(RedEyeSpot(center: p, radius: 0.018)) }
        case .radial where isTap:
            model.update { $0.locals.append(LocalAdjustment(mask: .radial(center: p, rx: 0.18, ry: 0.18, feather: 0.6, invert: false))) }
            model.selectedLocal = model.recipe.locals.count - 1
        case .brush, .linear:
            model.endChange()
        default:
            break
        }
    }

    private func ensureBrushLocal() {
        if let i = model.selectedLocal, model.recipe.locals.indices.contains(i), case .brush = model.recipe.locals[i].mask { return }
        model.recipe.locals.append(LocalAdjustment(mask: .brush(strokes: [])))
        model.selectedLocal = model.recipe.locals.count - 1
    }

    // MARK: Markieren

    private func markupDrag(_ p: NormPoint, start: NormPoint, rect: CGRect, translation: CGSize) {
        switch markupMode {
        case .draw:
            if stroke.isEmpty { model.beginChange() }
            stroke.append(p)
        case .shape, .redact:
            stroke = [start, p]
        case .select:
            guard hypot(translation.width, translation.height) > 4 else { return }
            if dragLayer == nil {
                guard let id = model.selectedLayer ?? hitLayer(start)?.id,
                      let layer = model.recipe.layers.first(where: { $0.id == id }) else { return }
                model.selectedLayer = id
                dragLayer = layer
                model.beginChange()
            }
            if let base = dragLayer {
                let moved = base.moved(dx: Float(translation.width / rect.width), dy: Float(translation.height / rect.height))
                model.recipe.layers = LayerOps.replace(model.recipe.layers, moved)
            }
        default:
            break
        }
    }

    private func markupEnd(_ p: NormPoint, start: NormPoint, isTap: Bool) {
        defer { stroke = []; dragLayer = nil }
        switch markupMode {
        case .draw:
            guard !stroke.isEmpty else { return }
            let s = DrawStroke(points: stroke, width: MarkupStyle.shared.width, color: MarkupStyle.shared.color, brush: MarkupStyle.shared.brush)
            if let i = model.recipe.layers.lastIndex(where: { if case .draw = $0 { true } else { false } }),
               case .draw(var d) = model.recipe.layers[i] {
                d.strokes.append(s)
                model.recipe.layers[i] = .draw(d)
            } else {
                model.recipe.layers.append(.draw(DrawLayer(strokes: [s])))
            }
            model.endChange()
        case .shape:
            guard !isTap else { return }
            var shape = ShapeLayer(kind: MarkupStyle.shared.shape, start: start, end: p)
            shape.color = MarkupStyle.shared.color
            model.update { $0.layers.append(.shape(shape)) }
            model.selectedLayer = shape.id
        case .redact:
            guard !isTap else { return }
            let r = NormRect(left: min(start.x, p.x), top: min(start.y, p.y), right: max(start.x, p.x), bottom: max(start.y, p.y))
            let layer = RedactLayer(mode: MarkupStyle.shared.redact, rect: r)
            model.update { $0.layers.append(.redact(layer)) }
            model.selectedLayer = layer.id
        case .select:
            if isTap { model.selectedLayer = hitLayer(p)?.id } else { model.endChange() }
        default:
            break
        }
    }

    /// Nächstgelegene Ebene (Mittelpunkt) im Umkreis.
    private func hitLayer(_ p: NormPoint) -> Layer? {
        func center(_ l: Layer) -> NormPoint? {
            switch l {
            case .text(let t): t.center
            case .sticker(let s): s.center
            case .shape(let s): NormPoint((s.start.x + s.end.x) / 2, (s.start.y + s.end.y) / 2)
            case .redact(let r): r.rect.map { NormPoint(($0.left + $0.right) / 2, ($0.top + $0.bottom) / 2) }
            case .draw: nil
            }
        }
        return model.recipe.layers.reversed()
            .compactMap { l in center(l).map { (l, hypot(Double($0.x - p.x), Double($0.y - p.y))) } }
            .filter { $0.1 < 0.12 }
            .min { $0.1 < $1.1 }?.0
    }

    // MARK: Werkzeugzone

    private var toolZone: some View {
        VStack(spacing: AppSpacing.s) {
            Group {
                switch model.tool {
                case .crop: CropPanel(model: model)
                case .adjust: AdjustPanel(model: model)
                case .filter: FilterPanel(model: model)
                case .retouch: RetouchPanel(model: model, mode: $retouchMode)
                case .markup: MarkupPanel(model: model, mode: $markupMode)
                case .frame: FramePanel(model: model)
                case .resize: ResizePanel(model: model)
                }
            }
            .frame(minHeight: 110)
            if !app.capabilities.hasProToolsAccess && model.recipe.usesProTools {
                Text(key: "edit_pro_hint").font(AppTypography.caption).foregroundStyle(.yellow)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(EditorTool.allCases) { t in
                            Button { model.tool = t } label: {
                                Label(L(t.titleKey), systemImage: t.symbol)
                                    .font(AppTypography.footnote.weight(.semibold))
                                    .padding(.horizontal, AppSpacing.s)
                                    .frame(minHeight: AppSpacing.minTouch)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(model.tool == t ? .black : .white)
                            .background(model.tool == t ? Color.white : Color.white.opacity(0.1), in: .capsule)
                            .accessibilityAddTraits(model.tool == t ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
            }
        }
        .padding(.bottom, AppSpacing.xs)
    }
}

enum RetouchMode: String, CaseIterable, Identifiable { case redEye, radial, linear, brush; var id: String { rawValue } }
enum MarkupMode: String, CaseIterable, Identifiable { case select, text, sticker, draw, shape, redact; var id: String { rawValue } }

/// Aktuelle Zeichen-Einstellungen (nur im Speicher).
@MainActor
final class MarkupStyle {
    static let shared = MarkupStyle()
    var color: ARGB = 0xFFFF_3B30
    var width: Float = 0.012
    var brush: BrushKind = .pen
    var shape: ShapeKind = .arrow
    var redact: RedactMode = .solid
}

/// Zuschneide-Rahmen mit Griffen (Ecken, Kanten, Verschieben), Drittel-Linien.
struct CropOverlay: View {
    let crop: NormRect
    let rect: CGRect
    let changed: (CropMath.Handle, CGSize) -> Void
    let ended: () -> Void

    var body: some View {
        let r = CGRect(x: rect.minX + CGFloat(crop.left) * rect.width, y: rect.minY + CGFloat(crop.top) * rect.height,
                       width: CGFloat(crop.width) * rect.width, height: CGFloat(crop.height) * rect.height)
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(rect)
                p.addRect(r)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Path { p in
                for i in 1...2 {
                    let x = r.minX + r.width * CGFloat(i) / 3, y = r.minY + r.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
                    p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
            .allowsHitTesting(false)
            Rectangle().strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: r.width, height: r.height)
                .contentShape(.rect)
                .position(x: r.midX, y: r.midY)
                .gesture(drag(.move))
            ForEach(handles(r)) { hp in
                Circle().fill(Color.white).frame(width: 18, height: 18)
                    .frame(width: AppSpacing.touch, height: AppSpacing.touch)
                    .contentShape(.rect)
                    .position(hp.point)
                    .gesture(drag(hp.handle))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(key: "edit_crop_area"))
        .accessibilityAdjustableAction { dir in
            let d: CGFloat = dir == .increment ? -0.02 : 0.02
            changed(.topLeft, CGSize(width: d * rect.width, height: d * rect.height))
            ended()
        }
    }

    struct HandlePoint: Identifiable {
        let handle: CropMath.Handle
        let point: CGPoint
        var id: String { String(describing: handle) }
    }

    private func handles(_ r: CGRect) -> [HandlePoint] {
        [HandlePoint(handle: .topLeft, point: CGPoint(x: r.minX, y: r.minY)),
         HandlePoint(handle: .topRight, point: CGPoint(x: r.maxX, y: r.minY)),
         HandlePoint(handle: .bottomLeft, point: CGPoint(x: r.minX, y: r.maxY)),
         HandlePoint(handle: .bottomRight, point: CGPoint(x: r.maxX, y: r.maxY)),
         HandlePoint(handle: .top, point: CGPoint(x: r.midX, y: r.minY)),
         HandlePoint(handle: .bottom, point: CGPoint(x: r.midX, y: r.maxY)),
         HandlePoint(handle: .left, point: CGPoint(x: r.minX, y: r.midY)),
         HandlePoint(handle: .right, point: CGPoint(x: r.maxX, y: r.midY))]
    }

    private func drag(_ h: CropMath.Handle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in changed(h, v.translation) }
            .onEnded { _ in ended() }
    }
}

/// Bereiche und Rote Augen sichtbar machen (nur Umriss, nie im Export).
struct RetouchOverlay: View {
    let recipe: EditRecipe
    let rect: CGRect
    let selected: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(recipe.redEyes.enumerated()), id: \.offset) { _, s in
                let rad = CGFloat(s.radius) * max(rect.width, rect.height)
                Circle().strokeBorder(Color.white, lineWidth: 1)
                    .frame(width: rad * 2, height: rad * 2)
                    .position(x: rect.minX + CGFloat(s.center.x) * rect.width, y: rect.minY + CGFloat(s.center.y) * rect.height)
            }
            ForEach(Array(recipe.locals.enumerated()), id: \.offset) { i, l in
                let tint = i == selected ? Color.yellow : Color.white.opacity(0.7)
                switch l.mask {
                case .radial(let c, let rx, let ry, _, _):
                    Ellipse().strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .frame(width: CGFloat(rx) * 2 * rect.width, height: CGFloat(ry) * 2 * rect.height)
                        .position(x: rect.minX + CGFloat(c.x) * rect.width, y: rect.minY + CGFloat(c.y) * rect.height)
                case .linear(let s, let e):
                    Path { p in
                        p.move(to: CGPoint(x: rect.minX + CGFloat(s.x) * rect.width, y: rect.minY + CGFloat(s.y) * rect.height))
                        p.addLine(to: CGPoint(x: rect.minX + CGFloat(e.x) * rect.width, y: rect.minY + CGFloat(e.y) * rect.height))
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                case .brush:
                    EmptyView()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Auswahlrahmen der gewählten Ebene und der gerade gezeichnete Strich.
struct MarkupOverlay: View {
    let recipe: EditRecipe
    let rect: CGRect
    let selected: String?
    let stroke: [NormPoint]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if stroke.count > 1 {
                Path { p in
                    p.addLines(stroke.map { CGPoint(x: rect.minX + CGFloat($0.x) * rect.width, y: rect.minY + CGFloat($0.y) * rect.height) })
                }
                .stroke(Color.yellow, lineWidth: 2)
            }
            if let id = selected, let l = recipe.layers.first(where: { $0.id == id }), let c = center(l) {
                Circle().strokeBorder(Color.yellow, lineWidth: 2).frame(width: 44, height: 44)
                    .position(x: rect.minX + CGFloat(c.x) * rect.width, y: rect.minY + CGFloat(c.y) * rect.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func center(_ l: Layer) -> NormPoint? {
        switch l {
        case .text(let t): t.center
        case .sticker(let s): s.center
        case .shape(let s): NormPoint((s.start.x + s.end.x) / 2, (s.start.y + s.end.y) / 2)
        case .redact(let r): r.rect.map { NormPoint(($0.left + $0.right) / 2, ($0.top + $0.bottom) / 2) }
        case .draw: nil
        }
    }
}
