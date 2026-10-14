import PhotoMaidCore
import SwiftUI

/// Einstellungen › Wischen & Tasten (E18): jede Wischrichtung frei belegen (auch „In Album legen“), Tasten auswählen,
/// ordnen und platzieren, festlegen, wann sie erscheinen. Wischen und Tasten lösen dasselbe aus
/// (`FeedViewModel.perform`). Gelöscht wird hier nie; „Papierkorb“ ist der PhotoMaid-eigene.
struct FeedControlsView: View {
    @Environment(AppModel.self) private var app
    @State private var albumFor: AlbumTarget?
    @State private var confirmReset = false

    enum AlbumTarget: Identifiable, Hashable {
        case direction(SwipeDirection)
        case button
        var id: String {
            switch self {
            case .direction(let d): "dir-\(d)"
            case .button: "button"
            }
        }
    }

    private static let directions: [SwipeDirection] = [.up, .left, .right, .down]
    private var controls: FeedControls { app.settings.feedControls }

    private func update(_ change: (inout FeedControls) -> Void) {
        app.updateSettings { s in
            var c = s.feedControls
            change(&c)
            s.feedControls = c.sanitized()
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(Self.directions, id: \.self) { d in directionRow(d) }
            } header: {
                Text(key: "fc_swipes")
            } footer: {
                Text(key: "fc_swipes_footer")
            }
            Section {
                Picker(L("fc_visibility"), selection: Binding(get: { controls.visibility },
                                                               set: { v in update { $0.visibility = v } })) {
                    Text(key: "fc_vis_accessibility").tag(FeedButtonVisibility.accessibilityOnly)
                    Text(key: "fc_vis_always").tag(FeedButtonVisibility.always)
                }
                Picker(L("fc_placement"), selection: Binding(get: { controls.placement },
                                                              set: { p in update { $0.placement = p } })) {
                    Text(key: "fc_place_below").tag(FeedButtonPlacement.belowMedia)
                    Text(key: "fc_place_above").tag(FeedButtonPlacement.aboveMedia)
                }
            } header: {
                Text(key: "fc_buttons")
            }
            Section {
                if controls.buttons.isEmpty {
                    Text(key: "fc_no_buttons").foregroundStyle(AppColors.textSecondary)
                }
                ForEach(controls.buttons, id: \.self) { a in buttonRow(a) }
                    .onMove { from, to in update { $0.buttons.move(fromOffsets: from, toOffset: to) } }
                    .onDelete { offsets in update { $0.buttons.remove(atOffsets: offsets) } }
                if controls.buttons.count < FeedControls.maxButtons {
                    Menu {
                        ForEach(controls.addableButtons(), id: \.self) { a in
                            Button { update { $0.buttons.append(a) } } label: {
                                Label(FeedActionText.title(a), systemImage: FeedActionText.symbol(a))
                            }
                        }
                        Button { albumFor = .button } label: {
                            Label(L("fc_choose_album"), systemImage: "rectangle.stack.badge.plus")
                        }
                    } label: {
                        Label(L("fc_add_button"), systemImage: "plus.circle")
                    }
                }
            } header: {
                Text(key: "fc_button_order")
            } footer: {
                Text(key: "fc_buttons_footer")
            }
            Section {
                Button(L("fc_reset")) { confirmReset = true }
                    .disabled(controls == FeedControls.standard)
            } footer: {
                Text(key: "fc_footer")
            }
        }
        .appPage()
        .navigationTitle(L("fc_title"))
        .toolbar { EditButton() }
        .sheet(item: $albumFor) { target in
            AlbumPickerSheet(assetIDs: []) { id, title in
                let action = FeedAction.album(id: id, title: title)
                switch target {
                case .direction(let d): update { $0.set(action, for: d) }
                case .button: update { if !$0.buttons.contains(action) { $0.buttons.append(action) } }
                }
            }
        }
        .confirmationDialog(L("fc_reset"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("fc_reset"), role: .destructive) { update { $0 = FeedControls.standard } }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(key: "fc_reset_text")
        }
    }

    /// Eine Richtung: Pfeil (physisch, nie gespiegelt), Name, gewählte Aktion; Antippen öffnet die Auswahl.
    private func directionRow(_ d: SwipeDirection) -> some View {
        let current = controls.action(for: d)
        return Menu {
            ForEach(FeedAction.fixedChoices, id: \.self) { a in
                Button { update { $0.set(a, for: d) } } label: {
                    if a == current {
                        Label(FeedActionText.title(a), systemImage: "checkmark")
                    } else {
                        Text(verbatim: FeedActionText.title(a))
                    }
                }
            }
            SwiftUI.Divider()
            if current.albumID != nil {
                Label(FeedActionText.title(current), systemImage: "checkmark")
            }
            Button { albumFor = .direction(d) } label: {
                Label(L("fc_choose_album"), systemImage: "rectangle.stack.badge.plus")
            }
        } label: {
            HStack(spacing: AppSpacing.s) {
                GestureArrow(direction: d).foregroundStyle(FeedActionText.color(current)).frame(width: 28)
                Text(key: Self.directionKey(d)).foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(verbatim: FeedActionText.title(current)).foregroundStyle(AppColors.textSecondary).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: AppSpacing.minTouch)
            .contentShape(.rect)
        }
        .accessibilityLabel(Text(verbatim: L(Self.directionKey(d)) + ": " + FeedActionText.title(current)))
    }

    private func buttonRow(_ a: FeedAction) -> some View {
        HStack(spacing: AppSpacing.s) {
            Group {
                if let d = controls.direction(of: a) {
                    GestureArrow(direction: d)
                } else {
                    Image(systemName: FeedActionText.symbol(a)).accessibilityHidden(true)
                }
            }
            .foregroundStyle(FeedActionText.color(a))
            .frame(width: 28)
            Text(verbatim: FeedActionText.title(a))
        }
        .frame(minHeight: AppSpacing.minTouch)
    }

    static func directionKey(_ d: SwipeDirection) -> String {
        switch d {
        case .up: "hint_up"
        case .left: "hint_left"
        case .right: "hint_right"
        case .down: "hint_down"
        }
    }
}

enum FeedControlsText {
    /// Kurzfassung für die Einstellungen: „Standard“ oder „Eigene Belegung“.
    static func summary(_ c: FeedControls) -> String {
        L(c == FeedControls.standard ? "fc_summary_standard" : "fc_summary_custom")
    }
}
