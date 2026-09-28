import SwiftUI

/// Helle, luftige Grundfläche. Die glänzende Präsentationskulisse der Mockups ist KEIN App-Wallpaper.
struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [AppColors.background, AppColors.backgroundTint],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Ruhige Inhaltsfläche (kein Glas), für Listen und Karten.
struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
            .overlay(RoundedRectangle(cornerRadius: AppRadii.card).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }
}

/// Glas nur für schwebende Controls / Navigation. Respektiert Reduce Transparency
/// über das System (Liquid Glass passt sich selbst an); zusätzlich eigener Fallback.
struct GlassCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var interactive = false

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(AppColors.surface, in: .capsule)
                .overlay(Capsule().strokeBorder(AppColors.surfaceStroke))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        }
    }
}

extension View {
    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassCapsuleModifier(interactive: interactive))
    }
}

/// Kopfzeile mit Titel, Untertitel und optionalen Glas-Buttons (Mockup-Stil).
struct GlassToolbar<Leading: View, Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GlassEffectContainer(spacing: AppSpacing.s) {
            HStack(alignment: .top) {
                leading.frame(minWidth: AppSpacing.minTouch, minHeight: AppSpacing.minTouch)
                Spacer(minLength: AppSpacing.xs)
                VStack(spacing: 2) {
                    Text(title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppSpacing.xs)
                trailing.frame(minWidth: AppSpacing.minTouch, minHeight: AppSpacing.minTouch)
            }
        }
        .padding(.horizontal, AppSpacing.pageMargin)
    }
}

/// Zeile für Quellen/Kategorien: Symbol, Titel, Untertitel, Wert, Chevron.
struct SourceRow: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    var subtitle: Text?
    var value: Text?
    var detail: Text?

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: AppRadii.small))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                if let subtitle { subtitle.font(AppTypography.caption).foregroundStyle(AppColors.textSecondary) }
            }
            Spacer(minLength: AppSpacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                if let value { value.font(AppTypography.subheadline.weight(.semibold)).foregroundStyle(AppColors.textPrimary) }
                if let detail { detail.font(AppTypography.caption).foregroundStyle(AppColors.textSecondary) }
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary).accessibilityHidden(true)
        }
        .frame(minHeight: AppSpacing.minTouch)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Kennzahl mit ehrlicher Beschriftung („mind.“ bei unbekannten Größen).
struct MetricCard: View {
    let value: Text
    let caption: Text
    var progress: Double?
    var footnote: Text?

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    value.font(AppTypography.metric).foregroundStyle(AppColors.textPrimary)
                    caption.font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                }
                if let progress {
                    ProgressView(value: min(max(progress, 0), 1)).tint(AppColors.accent)
                }
                if let footnote { footnote.font(AppTypography.caption).foregroundStyle(AppColors.textSecondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Schmaler Auswahlkorb unten im Feed.
struct ReviewDock: View {
    let count: Int
    let sizeText: Text?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "trash").foregroundStyle(AppColors.cleanup).accessibilityHidden(true)
                Text("Auswahlkorb: \(count) Elemente")
                    .font(AppTypography.subheadline.weight(.medium))
                if let sizeText { sizeText.font(AppTypography.caption).foregroundStyle(AppColors.textSecondary) }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.m)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
        .accessibilityHint(Text("Öffnet die vorgemerkten Elemente zur Prüfung"))
    }
}

/// Kurze Quittung in einer stabilen Bedienzone (z. B. Terminleiste nach „Später“).
struct StatusReceipt<Actions: View>: View {
    let message: Text
    var close: (() -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                message.font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.xs)
                if let close {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                            .contentShape(.rect.inset(by: -8)) // Trefferfläche ≥ 44 pt
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel(Text("Leiste schließen"))
                }
            }
            // Passt ohne Scrollen in eine Zeile; bei großer Schrift umbrechen statt abschneiden.
            ViewThatFits(in: .horizontal) {
                GlassEffectContainer(spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) { actions }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) { actions }
                }
            }
        }
        .padding(AppSpacing.s)
        .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.card))
        .accessibilityElement(children: .contain)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.glassProminent)
            }
        }
    }
}

struct ErrorState: View {
    let message: Text
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Etwas hat nicht funktioniert", systemImage: "exclamationmark.triangle")
        } description: {
            message
        } actions: {
            if let retry { Button("Erneut versuchen", action: retry).buttonStyle(.glass) }
        }
    }
}

/// Kreisförmiger Glas-Button für Kopfzeilen (Zurück, Schließen, Mehr, Einstellungen).
struct GlassIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(label))
    }
}
