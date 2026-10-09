import PhotoMaidCore
import SwiftUI

/// Zuschneiden: Drehen, Spiegeln, Begradigen, Seitenverhältnis, Perspektive (kostenlos wie Android).
struct CropPanel: View {
    @Bindable var model: EditorModel
    @State private var perspective = false
    @State private var vertical: Float = 0
    @State private var horizontal: Float = 0

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Picker("", selection: $perspective) {
                Text(key: "edit_crop_mode_crop").tag(false)
                Text(key: "edit_crop_mode_perspective").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppSpacing.pageMargin)
            if perspective {
                EditorRuler(title: L("edit_persp_vertical"), value: Binding(get: { vertical }, set: { vertical = $0; applyKeystone() }),
                            range: -100...100, onBegin: model.beginChange, onEnd: model.endChange)
                EditorRuler(title: L("edit_persp_horizontal"), value: Binding(get: { horizontal }, set: { horizontal = $0; applyKeystone() }),
                            range: -100...100, onBegin: model.beginChange, onEnd: model.endChange)
                Button(L("edit_persp_reset")) { vertical = 0; horizontal = 0; model.update { $0.perspective = nil } }
                    .foregroundStyle(.yellow)
            } else {
                HStack(spacing: AppSpacing.m) {
                    RoundToolButton(symbol: "rotate.right", title: L("edit_rotate")) { model.rotate() }
                    RoundToolButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: L("edit_flip_h"),
                                    active: model.recipe.flipH) { model.update { $0.flipH.toggle(); $0.crop = $0.crop.flippedH() } }
                    Menu {
                        ForEach(AspectPreset.allCases, id: \.self) { p in
                            Button { model.applyAspect(p) } label: {
                                if model.aspect == p { Label(aspectName(p), systemImage: "checkmark") } else { Text(verbatim: aspectName(p)) }
                            }
                        }
                        Divider()
                        Button(L(model.landscape ? "edit_portrait" : "edit_landscape")) {
                            model.landscape.toggle()
                            model.applyAspect(model.aspect)
                        }
                    } label: {
                        RoundToolButton(symbol: "aspectratio", title: aspectName(model.aspect), active: model.aspect != .free) {}
                            .allowsHitTesting(false)
                    }
                    RoundToolButton(symbol: "arrow.counterclockwise", title: L("edit_reset")) {
                        model.update { $0.crop = .full; $0.straighten = 0; $0.quarterTurns = 0; $0.flipH = false; $0.flipV = false }
                        model.aspect = .free
                    }
                }
                EditorRuler(title: L("edit_straighten"), value: Binding(get: { model.recipe.straighten }, set: { model.recipe.straighten = $0 }),
                            range: -45...45, onBegin: model.beginChange, onEnd: model.endChange)
            }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }

    private func applyKeystone() {
        let q = PerspectiveMath.keystone(vertical: vertical, horizontal: horizontal)
        model.recipe.perspective = q.isIdentity ? nil : q
    }

    private func aspectName(_ p: AspectPreset) -> String {
        switch p {
        case .free: L("edit_aspect_free")
        case .original: L("edit_aspect_original")
        case .square: "1:1"
        case .r4x5: model.landscape ? "5:4" : "4:5"
        case .r3x4: model.landscape ? "4:3" : "3:4"
        case .r2x3: model.landscape ? "3:2" : "2:3"
        case .r9x16: model.landscape ? "16:9" : "9:16"
        case .r16x9: model.landscape ? "16:9" : "9:16"
        }
    }
}

/// Anpassen: runde Regler-Knöpfe je Gruppe + Skalenregler. Farbmischer als eigene Gruppe.
struct AdjustPanel: View {
    @Bindable var model: EditorModel
    @State private var mix = false
    @State private var band: ColorBand = .red

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            if mix {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(ColorBand.allCases, id: \.self) { b in
                            Button { band = b } label: {
                                Circle().fill(bandColor(b)).frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: band == b ? 3 : 0))
                                    .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(key: "edit_band_\(b.rawValue.lowercased())"))
                        }
                        Button(L("done")) { mix = false }.foregroundStyle(.yellow).padding(.leading, AppSpacing.s)
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
                mixRuler(L("edit_mix_hue"), \.hue)
                mixRuler(L("edit_mix_saturation"), \.saturation)
                mixRuler(L("edit_mix_luminance"), \.luminance)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(AdjustParam.allCases) { p in
                            RoundToolButton(symbol: p.symbol, title: L(p.titleKey), active: model.param == p,
                                            changed: abs(model.recipe.adjust[keyPath: p.keyPath]) >= 0.5) { model.param = p }
                        }
                        RoundToolButton(symbol: "swatchpalette", title: L("edit_grp_mix"), changed: !model.recipe.colorMix.isNeutral) { mix = true }
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                }
                EditorRuler(title: L(model.param.titleKey),
                            value: Binding(get: { model.recipe.adjust[keyPath: model.param.keyPath] },
                                           set: { model.recipe.adjust[keyPath: model.param.keyPath] = $0 }),
                            range: model.param.range, onBegin: model.beginChange, onEnd: model.endChange)
                    .padding(.horizontal, AppSpacing.pageMargin)
            }
        }
    }

    private func mixRuler(_ title: String, _ kp: WritableKeyPath<HslShift, Float>) -> some View {
        EditorRuler(title: title, value: Binding(get: { model.recipe.colorMix[band][keyPath: kp] }, set: { v in
            var s = model.recipe.colorMix[band]
            s[keyPath: kp] = v
            model.recipe.colorMix = model.recipe.colorMix.with(band, s)
        }), range: -100...100, onBegin: model.beginChange, onEnd: model.endChange)
        .padding(.horizontal, AppSpacing.pageMargin)
    }

    private func bandColor(_ b: ColorBand) -> Color {
        Color(hue: Double(b.centerDeg) / 360, saturation: 0.85, brightness: 0.95)
    }
}

/// Filter: fertige Farbmatrizen (kein Download) mit Stärke.
struct FilterPanel: View {
    @Bindable var model: EditorModel
    @State private var thumbs: [FilterId: UIImage] = [:]

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.s) {
                    ForEach(FilterId.allCases, id: \.self) { f in
                        Button {
                            model.update { $0.filter = f; if f != .none && $0.filterIntensity <= 0.01 { $0.filterIntensity = 1 } }
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    if let t = thumbs[f] { Image(uiImage: t).resizable().scaledToFill() } else { Color.white.opacity(0.1) }
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow, lineWidth: model.recipe.filter == f ? 2 : 0))
                                Text(verbatim: name(f)).font(.caption2).foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.recipe.filter == f ? .isSelected : [])
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
            }
            if model.recipe.filter != .none {
                EditorRuler(title: L("edit_filter_strength"),
                            value: Binding(get: { model.recipe.filterIntensity * 100 }, set: { model.recipe.filterIntensity = $0 / 100 }),
                            range: 0...100, onBegin: model.beginChange, onEnd: model.endChange)
                    .padding(.horizontal, AppSpacing.pageMargin)
            }
        }
        .task { await renderThumbs() }
    }

    private func name(_ f: FilterId) -> String {
        switch f {
        case .none: L("edit_filter_none")
        case .mono: L("edit_filter_mono")
        case .monoContrast: L("edit_filter_mono_contrast")
        case .warm: L("edit_filter_warm")
        case .cool: L("edit_filter_cool")
        case .sepia: L("edit_filter_sepia")
        case .fade: L("edit_filter_fade")
        case .vivid: L("edit_filter_vivid")
        }
    }

    private func renderThumbs() async {
        guard let base = model.original?.cgImage else { return }
        let box = UncheckedBox(base)
        thumbs = await Task.detached(priority: .utility) { () -> [FilterId: UIImage] in
            let src = EditRenderer.downscaled(EditRenderer.source(box.value), maxEdge: 160)
            var out: [FilterId: UIImage] = [:]
            for f in FilterId.allCases {
                var r = EditRecipe()
                r.filter = f
                let img = EditRenderer.shared.render(src, recipe: r, forPreview: true)
                if let cg = EditRenderer.shared.cgImage(img) { out[f] = UIImage(cgImage: cg) }
            }
            return out
        }.value
    }
}

/// Retusche: Rote Augen (kostenlos), Bereiche Kreis/Verlauf/Pinsel (rein manuell, Speichern mit Pro).
struct RetouchPanel: View {
    @Bindable var model: EditorModel
    @Binding var mode: RetouchMode
    @State private var param: AdjustParam = .exposure

    private static let localParams: [AdjustParam] = [.exposure, .brightness, .contrast, .saturation, .warmth]

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Picker("", selection: $mode) {
                Text(key: "ret_red_eye").tag(RetouchMode.redEye)
                Text(key: "ret_radial").tag(RetouchMode.radial)
                Text(key: "ret_linear").tag(RetouchMode.linear)
                Text(key: "ret_brush").tag(RetouchMode.brush)
            }
            .pickerStyle(.segmented)
            if mode == .redEye {
                Text(key: "ret_red_eye_hint").font(AppTypography.caption).foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                if !model.recipe.redEyes.isEmpty {
                    Button(L("ret_red_eye_undo")) { model.update { _ = $0.redEyes.popLast() } }.foregroundStyle(.yellow)
                }
            } else if let i = model.selectedLocal, model.recipe.locals.indices.contains(i) {
                HStack {
                    ForEach(Self.localParams) { p in
                        Button { param = p } label: { Image(systemName: p.symbol).frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch) }
                            .foregroundStyle(param == p ? .yellow : .white)
                            .accessibilityLabel(Text(key: p.titleKey))
                    }
                    Spacer()
                    Button(role: .destructive) {
                        model.update { $0.locals.remove(at: i) }
                        model.selectedLocal = nil
                    } label: { Image(systemName: "trash").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch) }
                        .accessibilityLabel(Text(key: "ret_delete"))
                }
                EditorRuler(title: L(param.titleKey),
                            value: Binding(get: { model.recipe.locals[i].adjust[keyPath: param.keyPath] },
                                           set: { model.recipe.locals[i].adjust[keyPath: param.keyPath] = $0 }),
                            range: -100...100, onBegin: model.beginChange, onEnd: model.endChange)
                if case .radial(let c, let rx, let ry, let feather, let invert) = model.recipe.locals[i].mask {
                    EditorRuler(title: L("ret_size"), value: Binding(get: { rx * 200 }, set: { v in
                        let k = max(0.02, v / 200)
                        model.recipe.locals[i].mask = .radial(center: c, rx: k, ry: k * (ry / max(rx, 0.0001)), feather: feather, invert: invert)
                    }), range: 4...100, onBegin: model.beginChange, onEnd: model.endChange)
                }
            } else {
                Text(key: mode == .brush ? "ret_hint_brush" : "ret_hint_tap").font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }
}

/// Markieren: Text, Sticker, Zeichnen, Formen, Abdecken (Abdecken wird in die Pixel gerechnet).
struct MarkupPanel: View {
    @Bindable var model: EditorModel
    @Binding var mode: MarkupMode
    @State private var askText = false
    @State private var text = ""
    @State private var emoji = ""
    @State private var askEmoji = false

    private let palette: [ARGB] = [0xFFFF_FFFF, 0xFF00_0000, 0xFFFF_3B30, 0xFFFF_9500, 0xFFFF_CC00, 0xFF34_C759, 0xFF00_7AFF, 0xFFAF_52DE]

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    RoundToolButton(symbol: "hand.point.up.left", title: L("edit_mk_select"), active: mode == .select) { mode = .select }
                    RoundToolButton(symbol: "textformat", title: L("edit_mk_text")) { text = L("edit_text_default"); askText = true }
                    Menu {
                        ForEach(StickerKind.allCases, id: \.self) { k in
                            Button(stickerName(k)) { addSticker(k) }
                        }
                    } label: {
                        RoundToolButton(symbol: "face.smiling", title: L("edit_mk_sticker")) {}.allowsHitTesting(false)
                    }
                    RoundToolButton(symbol: "scribble", title: L("edit_mk_draw"), active: mode == .draw) { mode = .draw }
                    Menu {
                        ForEach(ShapeKind.allCases, id: \.self) { k in
                            Button(shapeName(k)) { MarkupStyle.shared.shape = k; mode = .shape }
                        }
                    } label: {
                        RoundToolButton(symbol: "square.on.circle", title: L("edit_mk_shape"), active: mode == .shape) {}.allowsHitTesting(false)
                    }
                    Menu {
                        Button(L("edit_redact_solid")) { MarkupStyle.shared.redact = .solid; mode = .redact }
                        Button(L("edit_redact_pixelate")) { MarkupStyle.shared.redact = .pixelate; mode = .redact }
                        Button(L("edit_redact_blur")) { MarkupStyle.shared.redact = .blur; mode = .redact }
                    } label: {
                        RoundToolButton(symbol: "rectangle.dashed.badge.record", title: L("edit_mk_redact"), active: mode == .redact) {}
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
            }
            HStack(spacing: 6) {
                ForEach(palette, id: \.self) { c in
                    Button {
                        MarkupStyle.shared.color = c
                        recolorSelected(c)
                    } label: {
                        Circle().fill(Color(uiColor: LayerRenderer.color(c))).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                            .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(key: "edit_mk_color"))
                }
                if let id = model.selectedLayer {
                    Button(role: .destructive) {
                        model.update { $0.layers = LayerOps.remove($0.layers, id: id) }
                        model.selectedLayer = nil
                    } label: { Image(systemName: "trash").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch) }
                        .accessibilityLabel(Text(key: "edit_mk_delete"))
                }
            }
            if mode == .redact {
                Text(key: MarkupStyle.shared.redact == .solid ? "edit_mk_redact_solid_hint" : "edit_mk_redact_hint")
                    .font(AppTypography.caption).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            } else {
                Text(key: "edit_mk_hint").font(AppTypography.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .alert(L("edit_mk_text"), isPresented: $askText) {
            TextField(L("edit_mk_text"), text: $text)
            Button(L("done")) {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                var layer = TextLayer(text: t)
                layer.color = MarkupStyle.shared.color
                model.update { $0.layers.append(.text(layer)) }
                model.selectedLayer = layer.id
                mode = .select
            }
            Button(L("cancel"), role: .cancel) {}
        }
        .alert(L("edit_mk_emoji"), isPresented: $askEmoji) {
            TextField(L("edit_mk_emoji"), text: $emoji)
            Button(L("done")) {
                var s = StickerLayer(kind: .emoji, value: String(emoji.prefix(2)))
                s.size = 0.18
                model.update { $0.layers.append(.sticker(s)) }
                model.selectedLayer = s.id
                mode = .select
            }
            Button(L("cancel"), role: .cancel) {}
        }
    }

    private func addSticker(_ k: StickerKind) {
        if k == .emoji { emoji = "😀"; askEmoji = true; return }
        var s = StickerLayer(kind: k, value: k == .date ? Date().formatted(date: .numeric, time: .omitted) : "")
        s.color = MarkupStyle.shared.color
        model.update { $0.layers.append(.sticker(s)) }
        model.selectedLayer = s.id
        mode = .select
    }

    private func recolorSelected(_ c: ARGB) {
        guard let id = model.selectedLayer, let l = model.recipe.layers.first(where: { $0.id == id }) else { return }
        let recolored: Layer
        switch l {
        case .text(var t): t.color = c; recolored = .text(t)
        case .sticker(var s): s.color = c; recolored = .sticker(s)
        case .shape(var s): s.color = c; recolored = .shape(s)
        case .redact(var r): r.color = c; recolored = .redact(r)
        case .draw: return
        }
        model.update { $0.layers = LayerOps.replace($0.layers, recolored) }
    }

    private func stickerName(_ k: StickerKind) -> String {
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

    private func shapeName(_ k: ShapeKind) -> String {
        switch k {
        case .arrow: L("edit_shape_arrow")
        case .rect: L("edit_shape_rect")
        case .ellipse: L("edit_shape_ellipse")
        case .line: L("edit_shape_line")
        }
    }
}

/// Rahmen: außen/innen, Breite, Farbe, gleichmäßig oder Seitenverhältnis.
struct FramePanel: View {
    @Bindable var model: EditorModel
    private let palette: [ARGB] = [0xFFFF_FFFF, 0xFF00_0000, 0xFFF2_EBE3, 0xFF23_1F1C, 0xFF00_64D2]

    var body: some View {
        let f = model.recipe.frame ?? FrameStyle(width: 0)
        VStack(spacing: AppSpacing.s) {
            Picker("", selection: Binding(get: { f.mode }, set: { m in model.update { $0.frame = Self.with(f) { $0.mode = m } } })) {
                Text(key: "edit_frame_outside").tag(FrameMode.outside)
                Text(key: "edit_frame_inside").tag(FrameMode.inside)
            }
            .pickerStyle(.segmented)
            EditorRuler(title: L("edit_frame_width"), value: Binding(get: { f.width * 400 }, set: { v in
                model.recipe.frame = Self.with(f) { $0.width = v / 400 }
            }), range: 0...100, onBegin: model.beginChange, onEnd: model.endChange)
            HStack {
                ForEach(palette, id: \.self) { c in
                    Button { model.update { $0.frame = Self.with(f) { $0.color = c } } } label: {
                        Circle().fill(Color(uiColor: LayerRenderer.color(c))).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                            .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(key: "edit_mk_color"))
                }
                Menu {
                    Button(L("edit_frame_even")) { model.update { $0.frame = Self.with(f) { $0.aspect = nil } } }
                    Button("1:1") { model.update { $0.frame = Self.with(f) { $0.aspect = 1 } } }
                    Button("4:5") { model.update { $0.frame = Self.with(f) { $0.aspect = 0.8 } } }
                    Button("9:16") { model.update { $0.frame = Self.with(f) { $0.aspect = 9.0 / 16 } } }
                } label: { Image(systemName: "aspectratio").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch) }
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }

    static func with(_ f: FrameStyle, _ change: (inout FrameStyle) -> Void) -> FrameStyle? {
        var x = f
        change(&x)
        return x.isNeutral ? nil : x
    }
}

/// Größe: nur proportional, nie größer als der Ausschnitt (PhotoMaid vergrößert nie).
struct ResizePanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        let crop = EditGeometry(src: model.fullSize, recipe: { var r = model.recipe; r.resizeWidth = nil; r.resizeHeight = nil; return r }()).cropSize
        let presets = ResizeRules.presets(for: crop)
        let out = model.outputSize
        VStack(spacing: AppSpacing.s) {
            if presets.isEmpty {
                Text(key: "edit_size_small").font(AppTypography.footnote).foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: AppSpacing.xs) {
                chip(L("edit_size_original"), active: !model.recipe.hasResize) {
                    model.update { $0.resizeWidth = nil; $0.resizeHeight = nil }
                }
                ForEach(presets, id: \.self) { edge in
                    let s = ResizeRules.forLongEdge(crop, edge)
                    chip(L("edit_size_long", edge), active: model.recipe.resizeWidth == s.width && model.recipe.resizeHeight == s.height) {
                        model.update { $0.resizeWidth = s.width; $0.resizeHeight = s.height }
                    }
                }
            }
            Text(verbatim: L("edit_size_result", crop.width, crop.height, out.width, out.height))
                .font(AppTypography.footnote.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(AppTypography.footnote.weight(.semibold))
                .padding(.horizontal, AppSpacing.s).frame(minHeight: AppSpacing.minTouch)
                .foregroundStyle(active ? .black : .white)
                .background(active ? Color.white : Color.white.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Speichern: Vorauswahl immer „Als Kopie speichern“. Ersetzen und „Original bearbeiten“ nur auf ausdrückliche Wahl.
struct EditSaveSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let model: EditorModel
    let finished: () -> Void
    @State private var mode: SaveMode = .copy
    @State private var removeLocation = false
    @State private var working = false
    @State private var shareItem: MediaShareItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    option(.copy, L("edit_save_copy"), L("edit_save_copy_text"))
                    option(.replace, L("edit_save_replace"), L("edit_save_replace_text"))
                    option(.editOriginal, L("edit_save_original"), L("edit_save_original_text"))
                }
                Section {
                    Toggle(L("edit_remove_location"), isOn: $removeLocation)
                        .disabled(mode == .editOriginal)
                } footer: {
                    Text(key: "edit_remove_location_text")
                }
                Section {
                    Button {
                        Task { await shareOnly() }
                    } label: { Label(L("edit_share_only"), systemImage: "square.and.arrow.up") }
                } footer: {
                    Text(key: "edit_share_only_text")
                }
                if working {
                    ProgressView(L("edit_saving"))
                }
            }
            .navigationTitle(L("edit_save_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(mode == .replace ? "edit_save_replace_action" : "edit_save_copy_action")) { Task { await save() } }
                        .disabled(working)
                }
            }
            .sheet(item: $shareItem) { ShareSheet(items: $0.items) }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(working)
    }

    private func option(_ m: SaveMode, _ title: String, _ text: String) -> some View {
        Button { mode = m } label: {
            HStack(alignment: .top) {
                Image(systemName: mode == m ? "largecircle.fill.circle" : "circle").foregroundStyle(AppColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).foregroundStyle(AppColors.textPrimary)
                    Text(verbatim: text).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    private func save() async {
        guard let data = model.data else { return }
        working = true
        model.setSaving(true)
        defer { working = false; model.setSaving(false) }
        do {
            let outcome = try await EditSaver.savePhoto(app: app, assetID: model.assetID, data: data, recipe: model.recipe,
                                                        mode: mode, removeLocation: removeLocation)
            Haptics.success()
            switch outcome {
            case .copy(_, let bytes): app.showToast(bytes.map { L("edit_done_copy_size", SizeText.bytes($0)) } ?? L("edit_done_copy"))
            case .replaced: app.showToast(L("edit_done_replaced"))
            case .replaceDeclined: app.showToast(L("edit_done_declined"))
            case .editedOriginal: app.showToast(L("edit_done_original"))
            }
            dismiss()
            finished()
        } catch EditSaveError.gone {
            app.showError(L("edit_err_gone"))
        } catch EditSaveError.declined {
            app.showError(L("edit_err_declined"))
        } catch {
            app.showError(L("edit_err_save"))
        }
    }

    /// Bearbeitete Fassung nur teilen (keine Kopie in der Mediathek, kein Ledger-Eintrag). Standort entfernt.
    private func shareOnly() async {
        guard let data = model.data else { return }
        working = true
        defer { working = false }
        let recipe = model.recipe
        let name = PhotoLibraryService.originalFilename(model.assetID)
        let url: URL? = await Task.detached(priority: .userInitiated) {
            guard let src = EditRenderer.source(data) else { return nil }
            let meta = EditRenderer.metadata(data)
            let format = EditFormat.forSource(uti: meta?.uti)
            let out = EditRenderer.shared.render(src, recipe: recipe)
            guard let encoded = EditRenderer.shared.encode(out, format: format, metadata: meta?.props, removeLocation: true) else { return nil }
            let dir = MediaShare.directory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(EditNames.copyName(original: name, suffix: "edit", fileExtension: format.fileExtension))
            return (try? encoded.write(to: file)) != nil ? file : nil
        }.value
        if let url { shareItem = MediaShareItem(items: [url], cleanup: [url]) } else { app.showError(L("edit_err_save")) }
    }
}

/// Pro-Werkzeuge verwendet, aber kein Pro: ehrlich erklären, „Nur Zuschnitt speichern“ anbieten.
struct EditProSheet: View {
    let geometryOnly: () -> Void
    let openPro: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            Text(key: "edit_pro_title").font(AppTypography.headline)
            Text(key: "edit_pro_text").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: L("pro_view"), symbol: "crown", action: openPro)
            SecondaryButton(title: L("edit_save_geometry_only"), action: geometryOnly)
        }
        .padding(AppSpacing.pageMargin)
        .presentationDetents([.medium])
    }
}
