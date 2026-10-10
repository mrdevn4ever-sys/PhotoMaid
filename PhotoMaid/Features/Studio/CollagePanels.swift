import PhotoMaidCore
import SwiftUI
import UIKit

// MARK: - Bausteine

/// Farben für Hintergrund, Text und Sticker – mit Namen für VoiceOver.
enum CollagePalette {
    struct Swatch: Identifiable {
        let id: String
        let color: ARGB
    }

    static let swatches: [Swatch] = [
        Swatch(id: "collage_color_white", color: 0xFFFF_FFFF),
        Swatch(id: "collage_color_black", color: 0xFF00_0000),
        Swatch(id: "collage_color_cream", color: 0xFFF4_EFE6),
        Swatch(id: "collage_color_grey", color: 0xFF8E_8E93),
        Swatch(id: "collage_color_red", color: 0xFFFF_3B30),
        Swatch(id: "collage_color_orange", color: 0xFFFF_9500),
        Swatch(id: "collage_color_yellow", color: 0xFFFF_CC00),
        Swatch(id: "collage_color_green", color: 0xFF34_C759),
        Swatch(id: "collage_color_blue", color: 0xFF00_7AFF),
        Swatch(id: "collage_color_pink", color: 0xFFFF_2D55),
    ]

    static func same(_ a: ARGB, _ b: ARGB) -> Bool { UInt32(truncatingIfNeeded: a) == UInt32(truncatingIfNeeded: b) }

    static func color(_ argb: ARGB) -> Color { Color(uiColor: CollageRenderer.uiColor(argb)) }

    @MainActor
    static func argb(_ color: Color) -> ARGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return ARGBColor.make(r: Float(r), g: Float(g), b: Float(b), a: 1)
    }
}

/// Farbfelder plus eigene Farbe (System-Farbwähler).
struct CollageSwatchRow: View {
    let selected: ARGB?
    let pick: (ARGB) -> Void
    @State private var custom: Color = .white

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xxs) {
                ForEach(CollagePalette.swatches) { swatch in
                    swatchButton(swatch)
                }
                ColorPicker(selection: Binding(get: { custom }, set: { value in
                    custom = value
                    pick(CollagePalette.argb(value))
                }), supportsOpacity: false) {
                    Text(key: "collage_color_custom")
                }
                .labelsHidden()
                .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                .accessibilityLabel(Text(key: "collage_color_custom"))
            }
        }
        .onAppear { if let selected { custom = CollagePalette.color(selected) } }
    }

    private func swatchButton(_ swatch: CollagePalette.Swatch) -> some View {
        let on = selected.map { CollagePalette.same($0, swatch.color) } ?? false
        return Button { pick(swatch.color) } label: {
            Circle()
                .fill(CollagePalette.color(swatch.color))
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(on ? AppColors.accentFill : Color.clear, lineWidth: 2.5))
                .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(key: swatch.id))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Beschrifteter Regler (ohne erfundene Zahlen; Drehung in Grad).
struct CollageSliderRow: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var showsDegrees = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: title).font(AppTypography.subheadline).foregroundStyle(AppColors.textPrimary)
                Spacer()
                if showsDegrees {
                    Text(verbatim: Measurement(value: Double(value.rounded()), unit: UnitAngle.degrees)
                        .formatted(.measurement(width: .narrow)))
                        .font(AppTypography.footnote.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(Text(verbatim: title))
        }
    }
}

/// Symbol mit Beschriftung (heller Grund).
struct CollageActionLabel: View {
    let symbol: String
    let title: String
    var active = false
    var destructive = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(height: 24)
            Text(verbatim: title)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 72, minHeight: AppSpacing.touch)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .foregroundStyle(destructive ? AppColors.cleanup : (active ? Color.white : AppColors.textPrimary))
        .background(active ? AppColors.accentFill : AppColors.surface, in: .rect(cornerRadius: AppRadii.small))
        .overlay(RoundedRectangle(cornerRadius: AppRadii.small).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        .contentShape(.rect)
    }
}

struct CollageActionButton: View {
    let symbol: String
    let title: String
    var active = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CollageActionLabel(symbol: symbol, title: title, active: active, destructive: destructive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Kleine Vorschauen der Fotos (eingepasst beschnitten, nie verzerrt) zum Auswählen.
struct CollageThumbRow: View {
    @Bindable var model: CollageModel
    let selected: Int?
    let pick: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(Array((model.project?.items ?? []).enumerated()), id: \.offset) { index, item in
                    Button { pick(index) } label: { thumb(item, on: selected == index) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: L("collage_photo_n", index + 1)))
                        .accessibilityAddTraits(selected == index ? .isSelected : [])
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func thumb(_ item: CollageItem, on: Bool) -> some View {
        ZStack {
            Rectangle().fill(AppColors.backgroundTint)
            if let image = model.image(for: item) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? AppColors.accentFill : Color.clear, lineWidth: 3))
        .frame(width: AppSpacing.touch + 8, height: AppSpacing.touch + 8)
        .contentShape(.rect)
    }
}

/// Gezeichnete Vorschau einer Vorlage (Felder als Flächen) – statt kryptischer Kennungen.
struct CollageLayoutThumb: View {
    let template: String
    let count: Int
    let aspect: Float
    let selected: Bool

    var body: some View {
        let cells = Array(CollageLayout.cells(CollageLayout.template(template, count)).values)
        let box = Self.box(aspect)
        let fill = selected ? Color.white : AppColors.accent.opacity(0.55)
        return Canvas { ctx, size in
            for r in cells {
                let rect = CGRect(x: CGFloat(r.left) * size.width, y: CGFloat(r.top) * size.height,
                                  width: CGFloat(r.width) * size.width, height: CGFloat(r.height) * size.height)
                    .insetBy(dx: 1.25, dy: 1.25)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(fill))
            }
        }
        .frame(width: box.width, height: box.height)
        .padding(7)
        .background(selected ? AppColors.accentFill : AppColors.surface, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? AppColors.accentFill : AppColors.surfaceStroke,
                                                                 lineWidth: selected ? 2 : 1))
        .accessibilityHidden(true)
    }

    static func box(_ aspect: Float) -> CGSize {
        let side: CGFloat = 50
        let a = CGFloat(min(max(aspect, 0.5), 2))
        return a >= 1 ? CGSize(width: side, height: side / a) : CGSize(width: side * a, height: side)
    }
}

/// VoiceOver-Namen der Vorlagen.
enum CollageLayoutNames {
    static func label(_ id: String) -> String {
        switch CollageLayout.shape(id) {
        case .grid: return L("collage_layout_grid")
        case .rows(let counts): return L("collage_layout_rows", list(counts))
        case .columns(let counts): return L("collage_layout_columns", list(counts))
        case .big(let side):
            switch side {
            case "r": return L("collage_layout_big_right")
            case "t": return L("collage_layout_big_top")
            case "b": return L("collage_layout_big_bottom")
            default: return L("collage_layout_big_left")
            }
        }
    }

    private static func list(_ counts: [Int]) -> String {
        let parts = counts.map { String($0) }
        let formatter = ListFormatter()
        formatter.locale = Locale(identifier: Strings.language)
        return formatter.string(from: parts) ?? parts.joined(separator: ", ")
    }
}

/// Seitenverhältnisse der Collage.
struct CollageAspectOption: Identifiable {
    let id: String
    let value: Float
    var labelKey: String?

    var label: String { labelKey.map { L($0) } ?? id }

    static let all: [CollageAspectOption] = [
        CollageAspectOption(id: "1:1", value: 1),
        CollageAspectOption(id: "4:5", value: 0.8),
        CollageAspectOption(id: "3:4", value: 0.75),
        CollageAspectOption(id: "2:3", value: 2.0 / 3),
        CollageAspectOption(id: "9:16", value: 9.0 / 16),
        CollageAspectOption(id: "4:3", value: 4.0 / 3),
        CollageAspectOption(id: "3:2", value: 1.5),
        CollageAspectOption(id: "16:9", value: 16.0 / 9),
        CollageAspectOption(id: "a4-portrait", value: Float(CollageExport.a4Short) / Float(CollageExport.a4Long),
                            labelKey: "col_a4_portrait"),
        CollageAspectOption(id: "a4-landscape", value: Float(CollageExport.a4Long) / Float(CollageExport.a4Short),
                            labelKey: "col_a4_landscape"),
    ]
}

private struct CollageAspectRow: View {
    @Bindable var model: CollageModel
    let current: Float

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(key: "collage_aspect").font(AppTypography.subheadline.weight(.semibold)).foregroundStyle(AppColors.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(CollageAspectOption.all) { option in
                        chip(option)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(_ option: CollageAspectOption) -> some View {
        let on = abs(current - option.value) < 0.005
        let box = CollageLayoutThumb.box(option.value)
        return Button {
            model.update { $0.aspect = option.value }
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(on ? Color.white : AppColors.accent, lineWidth: 2)
                    .frame(width: box.width * 0.5, height: box.height * 0.5)
                    .frame(width: 30, height: 30)
                Text(verbatim: option.label).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(minWidth: 58, minHeight: AppSpacing.touch)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .foregroundStyle(on ? Color.white : AppColors.textPrimary)
            .background(on ? AppColors.accentFill : AppColors.surface, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: L("collage_aspect_value", option.label)))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Binding auf eine Zahl des Projekts.
@MainActor
private func projectBinding(_ model: CollageModel, _ get: @escaping (CollageProject) -> Float,
                            _ set: @escaping (inout CollageProject, Float) -> Void) -> Binding<Float> {
    Binding(get: { model.project.map(get) ?? 0 }, set: { v in model.update { set(&$0, v) } })
}

// MARK: - Layout

struct CollageLayoutPanel: View {
    @Bindable var model: CollageModel

    var body: some View {
        if let p = model.project {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                switch p.kind {
                case .grid:
                    templates(p)
                    CollageAspectRow(model: model, current: p.aspect)
                case .free:
                    CollageAspectRow(model: model, current: p.aspect)
                    Toggle(L("col_polaroid"), isOn: Binding(get: { model.project?.polaroid ?? true },
                                                           set: { v in model.update { $0.polaroid = v } }))
                    CollageSliderRow(title: L("edit_frame_corner"),
                                     value: projectBinding(model, { $0.corner }, { $0.corner = $1 }), range: 0...0.08)
                case .strip:
                    stripControls(p)
                }
            }
        }
    }

    private func templates(_ p: CollageProject) -> some View {
        let n = p.items.count
        var ids = CollageLayout.featured(for: n)
        if !ids.contains(p.template), CollageLayout.templates(for: n).contains(p.template) { ids.insert(p.template, at: 0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(ids, id: \.self) { id in
                    Button {
                        model.update { $0 = $0.withTemplate(id) }
                    } label: {
                        CollageLayoutThumb(template: id, count: n, aspect: p.aspect, selected: p.template == id)
                            .frame(minWidth: AppSpacing.touch, minHeight: AppSpacing.touch)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: CollageLayoutNames.label(id)))
                    .accessibilityAddTraits(p.template == id ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func stripControls(_ p: CollageProject) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Picker(L("col_tab_layout"), selection: Binding(get: { model.project?.stripVertical ?? true },
                                                          set: { v in model.update { $0.stripVertical = v } })) {
                Text(key: "col_strip_vertical").tag(true)
                Text(key: "col_strip_horizontal").tag(false)
            }
            .pickerStyle(.segmented)
            CollageSliderRow(title: L("col_spacing"), value: projectBinding(model, { $0.spacing }, { $0.spacing = $1 }),
                             range: 0...0.06)
            CollageSliderRow(title: L("col_margin"), value: projectBinding(model, { $0.margin }, { $0.margin = $1 }),
                             range: 0...0.08)
            CollageSliderRow(title: L("edit_frame_corner"), value: projectBinding(model, { $0.corner }, { $0.corner = $1 }),
                             range: 0...0.06)
        }
    }
}

// MARK: - Abstand

struct CollageSpacingPanel: View {
    @Bindable var model: CollageModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            CollageSliderRow(title: L("col_spacing"), value: projectBinding(model, { $0.spacing }, { $0.spacing = $1 }),
                             range: 0...0.08)
            CollageSliderRow(title: L("col_margin"), value: projectBinding(model, { $0.margin }, { $0.margin = $1 }),
                             range: 0...0.1)
            CollageSliderRow(title: L("edit_frame_corner"), value: projectBinding(model, { $0.corner }, { $0.corner = $1 }),
                             range: 0...0.1)
        }
    }
}

// MARK: - Hintergrund

struct CollageBackgroundPanel: View {
    @Bindable var model: CollageModel

    var body: some View {
        if let p = model.project {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Picker(L("col_tab_background"), selection: Binding(get: { model.project?.background.kind ?? .color },
                                                                  set: { v in model.update { $0.background.kind = v } })) {
                    Text(key: "edit_mk_color").tag(BackgroundKind.color)
                    Text(key: "col_bg_blur").tag(BackgroundKind.blur)
                }
                .pickerStyle(.segmented)
                if p.background.kind == .color {
                    CollageSwatchRow(selected: p.background.color) { c in model.update { $0.background.color = c } }
                } else {
                    CollageThumbRow(model: model, selected: min(max(p.background.blurIndex, 0), max(p.items.count - 1, 0))) { i in
                        model.update { $0.background.blurIndex = i }
                    }
                }
            }
        }
    }
}

// MARK: - Foto

struct CollagePhotoPanel: View {
    @Bindable var model: CollageModel
    let replace: (Int) -> Void

    var body: some View {
        if let p = model.project {
            if let i = model.selected, p.items.indices.contains(i) {
                selectedControls(p, i)
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Text(key: "col_photo_hint").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                    CollageThumbRow(model: model, selected: nil) { i in model.selected = i }
                }
            }
        }
    }

    private func itemBinding(_ i: Int, _ get: @escaping (CollageItem) -> Float,
                             _ set: @escaping (inout CollageItem, Float) -> Void) -> Binding<Float> {
        Binding(get: {
            guard let p = model.project, p.items.indices.contains(i) else { return 0 }
            return get(p.items[i])
        }, set: { v in
            model.update { proj in
                guard proj.items.indices.contains(i) else { return }
                set(&proj.items[i], v)
            }
        })
    }

    private func fitBinding(_ i: Int) -> Binding<Bool> {
        Binding(get: {
            guard let items = model.project?.items, items.indices.contains(i) else { return false }
            return items[i].fit
        }, set: { v in
            model.update { proj in
                guard proj.items.indices.contains(i) else { return }
                proj.items[i].fit = v
            }
        })
    }

    private func selectedControls(_ p: CollageProject, _ i: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Text(verbatim: L("collage_photo_n", i + 1)).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button(L("done")) { model.selected = nil }
                    .frame(minHeight: AppSpacing.minTouch)
            }
            switch p.kind {
            case .grid:
                Picker(L("col_tab_photo"), selection: fitBinding(i)) {
                    Text(key: "col_fill").tag(false)
                    Text(key: "col_fit").tag(true)
                }
                .pickerStyle(.segmented)
                if !p.items[i].fit {
                    CollageSliderRow(title: L("collage_zoom"), value: itemBinding(i, { $0.zoom }, { $0.zoom = min(max($1, 1), CellFit.maxZoom) }),
                                     range: 1...CellFit.maxZoom)
                }
            case .free:
                CollageSliderRow(title: L("edit_mk_size"), value: itemBinding(i, { $0.width }, { $0.width = FreeLayout.clampWidth($1) }),
                                 range: 0.08...1.2)
                CollageSliderRow(title: L("collage_rotation"),
                                 value: itemBinding(i, { $0.rotation }, { $0.rotation = FreeLayout.normalizedRotation($1) }),
                                 range: -180...180, showsDegrees: true)
            case .strip:
                CollageSliderRow(title: L(p.stripVertical ? "col_trim_top" : "col_trim_left"),
                                 value: itemBinding(i, { $0.trimStart }, { $0.trimStart = min(max($1, 0), 0.45) }), range: 0...0.45)
                CollageSliderRow(title: L(p.stripVertical ? "col_trim_bottom" : "col_trim_right"),
                                 value: itemBinding(i, { $0.trimEnd }, { $0.trimEnd = min(max($1, 0), 0.45) }), range: 0...0.45)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) { actions(p, i) }
                    .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func actions(_ p: CollageProject, _ i: Int) -> some View {
        let n = p.items.count
        switch p.kind {
        case .grid:
            CollageActionButton(symbol: "arrow.left.arrow.right", title: L("col_swap_next")) {
                guard n > 1 else { return }
                let j = (i + 1) % n
                model.replace(p.swap(i, j))
                model.selected = j
            }
            .disabled(n < 2)
        case .free:
            CollageActionButton(symbol: "square.3.layers.3d.top.filled", title: L("edit_mk_front")) {
                model.replace(p.bringingToFront(i))
                model.selected = n - 1
            }
            .disabled(i == n - 1)
        case .strip:
            CollageActionButton(symbol: p.stripVertical ? "arrow.up" : "arrow.left", title: L("movie_move_earlier")) {
                guard i > 0 else { return }
                model.replace(p.swap(i, i - 1))
                model.selected = i - 1
            }
            .disabled(i == 0)
            CollageActionButton(symbol: p.stripVertical ? "arrow.down" : "arrow.right", title: L("movie_move_later")) {
                guard i < n - 1 else { return }
                model.replace(p.swap(i, i + 1))
                model.selected = i + 1
            }
            .disabled(i >= n - 1)
        }
        CollageActionButton(symbol: "rotate.right", title: L("edit_rotate")) {
            model.update { proj in
                guard proj.items.indices.contains(i) else { return }
                proj.items[i].quarterTurns = (proj.items[i].quarterTurns + 1) % 4
                proj.items[i].zoom = 1
                proj.items[i].panX = 0
                proj.items[i].panY = 0
            }
        }
        CollageActionButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: L("edit_flip_h")) {
            model.update { proj in
                guard proj.items.indices.contains(i) else { return }
                proj.items[i].flipH.toggle()
                proj.items[i].panX = -proj.items[i].panX
            }
        }
        if p.kind == .grid {
            CollageActionButton(symbol: "arrow.counterclockwise", title: L("edit_reset")) {
                model.update { proj in
                    guard proj.items.indices.contains(i) else { return }
                    proj.items[i].zoom = 1
                    proj.items[i].panX = 0
                    proj.items[i].panY = 0
                }
            }
            .disabled(p.items[i].zoom == 1 && p.items[i].panX == 0 && p.items[i].panY == 0)
        }
        CollageActionButton(symbol: "photo.badge.arrow.down", title: L("col_replace")) { replace(i) }
        CollageActionButton(symbol: "trash", title: L("remove"), destructive: true) {
            model.replace(p.removeItem(i))
            model.selected = nil
        }
        .disabled(n < 2)
    }
}

// MARK: - Text & Sticker

struct CollageDecorPanel: View {
    @Bindable var model: CollageModel
    @State private var askText = false
    @State private var editingID: String?
    @State private var text = ""
    @State private var askEmoji = false
    @State private var emoji = ""

    private var selectedLayer: PhotoMaidCore.Layer? {
        guard let id = model.selectedLayer else { return nil }
        return model.project?.layers.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            addRow
            if let layer = selectedLayer {
                controls(layer)
            } else {
                Text(key: "edit_mk_hint").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
        }
        .alert(L("edit_mk_text"), isPresented: $askText) {
            TextField(L("edit_mk_text"), text: $text)
            Button(L("done")) { commitText() }
            Button(L("cancel"), role: .cancel) { editingID = nil }
        }
        .alert(L("edit_mk_emoji"), isPresented: $askEmoji) {
            TextField(L("edit_mk_emoji"), text: $emoji)
            Button(L("done")) { addEmoji() }
            Button(L("cancel"), role: .cancel) {}
        }
    }

    private var addRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                CollageActionButton(symbol: "textformat", title: L("edit_mk_text")) {
                    editingID = nil
                    text = L("edit_text_default")
                    askText = true
                }
                Menu {
                    ForEach(StickerKind.allCases.filter { $0 != .emoji }, id: \.self) { kind in
                        Button { addSticker(kind) } label: {
                            Label(CollageStickerNames.name(kind), systemImage: CollageStickerNames.symbol(kind))
                        }
                    }
                } label: {
                    CollageActionLabel(symbol: "star.circle", title: L("edit_mk_sticker"))
                }
                .accessibilityLabel(Text(key: "edit_mk_sticker"))
                CollageActionButton(symbol: "face.smiling", title: L("edit_mk_emoji")) {
                    emoji = "😀"
                    askEmoji = true
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func layerBinding(_ get: @escaping (PhotoMaidCore.Layer) -> Float, _ set: @escaping (PhotoMaidCore.Layer, Float) -> PhotoMaidCore.Layer) -> Binding<Float> {
        Binding(get: { selectedLayer.map(get) ?? 0 }, set: { v in
            guard let id = model.selectedLayer else { return }
            model.update { proj in proj.layers = proj.layers.map { $0.id == id ? set($0, v) : $0 } }
        })
    }

    @ViewBuilder
    private func controls(_ layer: PhotoMaidCore.Layer) -> some View {
        let isText: Bool = { if case .text = layer { true } else { false } }()
        CollageSwatchRow(selected: CollageLayerEdit.color(layer)) { c in
            let id = layer.id
            model.update { proj in proj.layers = proj.layers.map { $0.id == id ? CollageLayerEdit.withColor($0, c) : $0 } }
        }
        .id(layer.id)
        CollageSliderRow(title: L("edit_mk_size"), value: layerBinding({ CollageLayerEdit.transform($0)?.size ?? 0 }, { l, v in
            CollageLayerEdit.withTransform(l, size: v, rotation: CollageLayerEdit.transform(l)?.rotation ?? 0)
        }), range: isText ? 0.02...0.3 : 0.05...0.8)
        CollageSliderRow(title: L("collage_rotation"), value: layerBinding({ CollageLayerEdit.transform($0)?.rotation ?? 0 }, { l, v in
            CollageLayerEdit.withTransform(l, size: CollageLayerEdit.transform(l)?.size ?? 0.1, rotation: FreeLayout.normalizedRotation(v))
        }), range: -180...180, showsDegrees: true)
        if case .text(let t) = layer {
            textStyle(t)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) { layerActions(layer) }
                .padding(.vertical, 2)
        }
    }

    private func textStyle(_ t: TextLayer) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Picker(L("collage_text_style"), selection: Binding(get: { t.style }, set: { v in updateText(t.id) { $0.style = v } })) {
                ForEach(TextStyle.allCases, id: \.self) { s in Text(verbatim: Self.styleName(s)).tag(s) }
            }
            .pickerStyle(.segmented)
            HStack {
                Text(key: "collage_font").font(AppTypography.subheadline).foregroundStyle(AppColors.textPrimary)
                Spacer()
                Picker(L("collage_font"), selection: Binding(get: { t.font }, set: { v in updateText(t.id) { $0.font = v } })) {
                    ForEach(FontId.allCases, id: \.self) { f in Text(verbatim: Self.fontName(f)).tag(f) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private func layerActions(_ layer: PhotoMaidCore.Layer) -> some View {
        let id = layer.id
        if case .text(let t) = layer {
            CollageActionButton(symbol: "pencil", title: L("edit_mk_edit_text")) {
                editingID = id
                text = t.text
                askText = true
            }
        }
        CollageActionButton(symbol: "square.3.layers.3d.top.filled", title: L("edit_mk_front")) {
            model.update { $0.layers = LayerOps.toFront($0.layers, id: id) }
        }
        CollageActionButton(symbol: "plus.square.on.square", title: L("edit_mk_duplicate")) {
            let newID = UUID().uuidString
            model.update { $0.layers = LayerOps.duplicate($0.layers, id: id, newID: newID) }
            model.selectedLayer = newID
        }
        CollageActionButton(symbol: "trash", title: L("edit_mk_delete"), destructive: true) {
            model.update { $0.layers = LayerOps.remove($0.layers, id: id) }
            model.selectedLayer = nil
        }
    }

    private func updateText(_ id: String, _ change: @escaping (inout TextLayer) -> Void) {
        model.update { proj in
            proj.layers = proj.layers.map { l in
                guard case .text(var t) = l, t.id == id else { return l }
                change(&t)
                return .text(t)
            }
        }
    }

    private func commitText() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { editingID = nil }
        guard !value.isEmpty else { return }
        if let id = editingID {
            updateText(id) { $0.text = value }
            return
        }
        let layer = TextLayer(text: value)
        model.update { $0.layers.append(.text(layer)) }
        model.selectedLayer = layer.id
        model.selected = nil
    }

    private func addEmoji() {
        let value = String(emoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
        guard !value.isEmpty else { return }
        var sticker = StickerLayer(kind: .emoji, value: value)
        sticker.size = 0.18
        model.update { $0.layers.append(.sticker(sticker)) }
        model.selectedLayer = sticker.id
        model.selected = nil
    }

    private func addSticker(_ kind: StickerKind) {
        var sticker = StickerLayer(kind: kind, value: kind == .date ? Date().formatted(date: .numeric, time: .omitted) : "")
        sticker.color = 0xFFFF_3B30
        model.update { $0.layers.append(.sticker(sticker)) }
        model.selectedLayer = sticker.id
        model.selected = nil
    }

    static func styleName(_ s: TextStyle) -> String {
        switch s {
        case .fill: L("edit_mk_filled")
        case .outline: L("edit_ts_outline")
        case .pill: L("edit_ts_pill")
        case .shadow: L("edit_ts_shadow")
        }
    }

    static func fontName(_ f: FontId) -> String {
        switch f {
        case .sans: L("edit_font_sans")
        case .sansBold: L("edit_font_bold")
        case .black: L("edit_font_black")
        case .condensed: L("edit_font_condensed")
        case .serif: L("edit_font_serif")
        case .mono: L("edit_font_mono")
        case .handwriting: L("edit_font_hand")
        case .casual: L("edit_font_casual")
        case .smallCaps: L("edit_font_smallcaps")
        }
    }
}
