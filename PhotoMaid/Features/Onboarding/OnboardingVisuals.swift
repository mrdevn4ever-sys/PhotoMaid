import PhotoMaidCore
import SwiftUI

/// Gezeichnete Beispielfotos für die Einführung (vor der Fotofreigabe gibt es keine echten Medien).
struct DemoPhoto: Identifiable, Equatable {
    let id: Int
    let symbol: String
    let colors: [Color]

    static var samples: [DemoPhoto] { [
        DemoPhoto(id: 0, symbol: "sun.horizon.fill", colors: [Color(red: 1.0, green: 0.62, blue: 0.35), Color(red: 0.93, green: 0.33, blue: 0.48)]),
        DemoPhoto(id: 1, symbol: "mountain.2.fill", colors: [Color(red: 0.30, green: 0.75, blue: 0.80), Color(red: 0.16, green: 0.40, blue: 0.75)]),
        DemoPhoto(id: 2, symbol: "pawprint.fill", colors: [Color(red: 0.98, green: 0.80, blue: 0.36), Color(red: 0.88, green: 0.52, blue: 0.20)]),
        DemoPhoto(id: 3, symbol: "person.2.fill", colors: [Color(red: 0.62, green: 0.48, blue: 0.95), Color(red: 0.33, green: 0.27, blue: 0.75)]),
    ] }
}

/// Eine gezeichnete Fotokarte (Verlauf und Motiv-Symbol).
struct DemoPhotoCard: View {
    let photo: DemoPhoto
    var symbolSize: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadii.card)
            .fill(LinearGradient(colors: photo.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: photo.symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            .accessibilityHidden(true)
    }
}

/// Seite 1: aufgefächerter Fotostapel mit den drei Richtungen als kleine Hinweise.
struct OnboardingPhotoStack: View {
    var body: some View {
        ZStack {
            DemoPhotoCard(photo: DemoPhoto.samples[3]).rotationEffect(.degrees(-10)).offset(x: -38, y: 10)
            DemoPhotoCard(photo: DemoPhoto.samples[1]).rotationEffect(.degrees(8)).offset(x: 36, y: 6)
            DemoPhotoCard(photo: DemoPhoto.samples[0])
                .overlay(alignment: .top) { hint(.up, "dir_keep", AppColors.keep).offset(y: -18) }
                .overlay(alignment: .leading) { hint(.left, "dir_trash", AppColors.cleanup).offset(x: -34) }
                .overlay(alignment: .trailing) { hint(.right, "dir_later", AppColors.later).offset(x: 34) }
        }
        .frame(width: 190, height: 250)
        .padding(.vertical, AppSpacing.l)
        .environment(\.layoutDirection, .leftToRight) // Gestenpfeile nie spiegeln
        .accessibilityHidden(true)
    }

    private func hint(_ direction: SwipeDirection, _ key: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            GestureArrow(direction: direction)
            Text(key: key)
        }
        .font(AppTypography.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 4)
        .glassCapsule()
    }
}

/// Seite 2: Übungsstapel. Dieselbe Gesten-Logik wie im Feed (`FeedGestureMachine`), aber nichts wird gespeichert.
struct OnboardingDemoStack: View {
    @State private var machine = FeedGestureMachine()
    @State private var remaining = Array(DemoPhoto.samples.prefix(3))
    @State private var offset: CGSize = .zero

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            ZStack {
                if remaining.isEmpty {
                    VStack(spacing: AppSpacing.s) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(AppColors.success)
                            .accessibilityHidden(true)
                        Text(key: "onb_try_done").font(AppTypography.headline).multilineTextAlignment(.center)
                    }
                    .transition(.opacity)
                }
                ForEach(Array(remaining.enumerated().reversed()), id: \.element.id) { index, photo in
                    DemoPhotoCard(photo: photo)
                        .scaleEffect(index == 0 ? 1 : 0.94)
                        .offset(y: index == 0 ? 0 : 10)
                        .offset(index == 0 ? offset : .zero)
                        .rotationEffect(.degrees(index == 0 ? Double(offset.width) / 18 : 0))
                }
                DirectionPill(direction: machine.lockedDirection, ready: machine.readyToCommit)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: -36)
            }
            .frame(width: 190, height: 250)
            .contentShape(Rectangle())
            .gesture(drag)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(key: "onb_demo_desc"))
            .accessibilityAction(named: Text(key: "dir_keep")) { commit(.up) }
            .accessibilityAction(named: Text(key: "dir_trash")) { commit(.left) }
            .accessibilityAction(named: Text(key: "dir_later")) { commit(.right) }

            Text(key: "onb_demo_desc").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppSpacing.xl)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !remaining.isEmpty else { return }
                machine.update(translation: Vector2(v.translation.width, v.translation.height))
                let o = machine.displayOffset
                offset = CGSize(width: o.dx, height: o.dy)
            }
            .onEnded { v in
                guard !remaining.isEmpty else { return }
                let resolution = machine.end(translation: Vector2(v.translation.width, v.translation.height),
                                             velocity: Vector2(v.velocity.width, v.velocity.height))
                if case .commit(let direction) = resolution, direction != .down {
                    commit(direction)
                } else {
                    machine.finishCommit()
                    withAnimation(.snappy) { offset = .zero }
                }
            }
    }

    /// Übungskarte fliegt in Wischrichtung hinaus; „runter“ ist auch hier keine Entscheidung.
    private func commit(_ direction: SwipeDirection) {
        guard !remaining.isEmpty else { return }
        let target: CGSize = switch direction {
        case .up: CGSize(width: 0, height: -600)
        case .left: CGSize(width: -500, height: 0)
        case .right: CGSize(width: 500, height: 0)
        case .down: .zero
        }
        withAnimation(.easeOut(duration: 0.25)) {
            offset = target
        } completion: {
            remaining.removeFirst()
            offset = .zero
            machine.finishCommit()
        }
        Haptics.commit()
    }
}

/// Seite 3: Weg eines Mediums – Foto → PhotoMaid-Papierkorb → Bestätigung durch iOS.
struct OnboardingSafeFlow: View {
    var body: some View {
        VStack(spacing: AppSpacing.l) {
            HStack(spacing: AppSpacing.s) {
                DemoPhotoCard(photo: DemoPhoto.samples[2], symbolSize: 26).frame(width: 64, height: 84)
                arrow
                badge("trash.fill", AppColors.cleanup)
                arrow
                badge("checkmark.shield.fill", AppColors.success)
            }
            .environment(\.layoutDirection, .leftToRight)
            Label {
                Text(key: "onb_safe_local").font(AppTypography.footnote)
            } icon: {
                Image(systemName: "iphone").foregroundStyle(AppColors.accent)
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(AppSpacing.s)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.small))
        }
        .padding(.vertical, AppSpacing.m)
        .accessibilityElement(children: .combine)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
            .accessibilityHidden(true)
    }

    private func badge(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 64, height: 64)
            .background(tint.opacity(0.14), in: .circle)
            .accessibilityHidden(true)
    }
}

/// Symbolbild für die übrigen Seiten: Symbol auf getönter Glasfläche.
struct OnboardingSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 56, weight: .semibold))
            .foregroundStyle(AppColors.accent)
            .frame(width: 128, height: 128)
            .background(AppColors.accent.opacity(0.12), in: .circle)
            .padding(.vertical, AppSpacing.l)
            .accessibilityHidden(true)
    }
}
