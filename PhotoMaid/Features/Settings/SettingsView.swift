import PhotoMaidCore
import StoreKit
import SwiftUI
import UIKit

/// Experiment-Design: Einstellungen wie im Artefakt – Pro-Karte, gruppierte Karten mit Trennlinien, Bricolage-Titel.
/// Das Erscheinungsbild entfällt hier: das Artefakt-Design gibt es nur dunkel (kein toter Umschalter).
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.purchase) private var purchase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeading(title: L("settings"))
                proCard
                heading(L("set_controls"))
                card {
                    NavigationLink(value: Route.feedControls) {
                        row(L("fc_title"), subtitle: FeedControlsText.summary(app.settings.feedControls))
                    }
                    .buttonStyle(PMPressStyle())
                    divider
                    toggle(L("set_haptics"), \.haptics)
                    divider
                    toggle(L("set_hints"), \.showGestureHintOnOpen)
                    divider
                    toggle(L("set_protect_favorites"), \.protectFavorites, subtitle: L("art_protect_fav_sub"))
                    divider
                    laterDefault
                }
                heading(L("art_privacy_data"))
                card {
                    if !VaultStore.shared.hidesEntry {
                        Button { VaultStore.shared.present() } label: {
                            row(L("vault_title"), subtitle: L("vault_settings_row_hint"), icon: .lock)
                        }
                        .buttonStyle(PMPressStyle())
                        divider
                    }
                    NavigationLink(value: Route.excludedAlbums) { row(L("set_excluded_folders")) }.buttonStyle(PMPressStyle())
                    divider
                    NavigationLink(value: Route.backup) { row(L("backup_title")) }.buttonStyle(PMPressStyle())
                    divider
                    NavigationLink(value: Route.privacy) { row(L("privacy_title")) }.buttonStyle(PMPressStyle())
                    divider
                    // Von Google für EWR/UK/Schweiz verlangt: Einwilligung zur Werbung jederzeit ändern (nur Gratis).
                    if AdsService.shared.privacyOptionsRequired && !app.capabilities.isLifetimePro {
                        Button { Task { await AdsService.shared.presentPrivacyOptions() } } label: { row(L("set_ad_privacy")) }
                            .buttonStyle(PMPressStyle())
                        divider
                    }
                    // App-Sprache stellt iOS ein (Einstellungen › PhotoMaid › Sprache); kein eigener Sprachumschalter.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        row(L("set_language"), value: languageName)
                    }
                    .buttonStyle(PMPressStyle())
                    .accessibilityHint(Text(key: "set_language_hint"))
                    divider
                    NavigationLink(value: Route.help) { row(L("help")) }.buttonStyle(PMPressStyle())
                }
                if !VaultStore.shared.hidesEntry {
                    Text(key: "vault_hide_entry_text").font(AppTypography.footnote).foregroundStyle(AppColors.textTertiary)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .appPage()
        .navigationTitle(L("settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .task { if !app.capabilities.isLifetimePro { await app.purchases.refresh() } }
    }

    // MARK: Pro

    /// Pro-Karte (Radius 28): Krone, Titel, Vorteile, Kauf mit `Product.displayPrice`, Wiederherstellen.
    /// Kopf und Vorteile öffnen die ausführliche Pro-Seite.
    private var proCard: some View {
        let active = app.capabilities.isLifetimePro
        return VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: Route.pro) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        PMIcon(.crown, size: 22)
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 44, height: 44)
                            .background(AppColors.warm, in: .rect(cornerRadius: 14))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key: active ? "pro_active_title" : "pro_title").font(AppTypography.title)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(key: active ? "pro2_active_sub" : "pro_subtitle")
                                .font(PMFont.text(.regular, 14, relativeTo: .subheadline))
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    if !active {
                        // E19: Pro = ohne Werbung, ohne Tageslimit, Tresor-Ordner ohne Werbung.
                        VStack(alignment: .leading, spacing: 6) {
                            Text(key: "pro_f1")
                            Text(key: "pro_f2")
                            Text(key: "pro2_f3")
                        }
                        .font(PMFont.text(.regular, 14, relativeTo: .subheadline))
                        .foregroundStyle(AppColors.hex(0xD8D0C6))
                    }
                }
                .multilineTextAlignment(.leading)
                .contentShape(.rect)
            }
            .buttonStyle(PMPressStyle())
            .accessibilityIdentifier("settings.pro")
            if !active {
                offer
                if app.purchases.isConfigured {
                    Button { Task { await restore() } } label: {
                        Text(key: "pro_restore")
                            .font(PMFont.text(.semibold, 14, relativeTo: .subheadline))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(PMPressStyle())
                    .disabled(app.purchases.isBusy)
                }
            }
        }
        .padding(20)
        .background(AppColors.surface, in: .rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }

    /// Kaufknopf: Preis nur aus dem Store; ohne Angebot führt er zur Pro-Seite, die den Grund nennt.
    @ViewBuilder
    private var offer: some View {
        switch app.purchases.offer {
        case .ready(let product):
            Button { Task { await buy() } } label: {
                buyLabel(product.displayPrice + " · " + L("set_pro_once"))
            }
            .buttonStyle(PMPressStyle())
            .disabled(app.purchases.isBusy)
            .accessibilityIdentifier("settings.buy")
        case .loading:
            HStack(spacing: AppSpacing.s) {
                ProgressView().tint(AppColors.textSecondary)
                Text(key: "pro_price_loading")
            }
            .font(PMFont.text(.semibold, 15, relativeTo: .subheadline))
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppColors.control, in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        case .unavailable, .notConfigured:
            NavigationLink(value: Route.pro) { buyLabel(L("pro_unlock")) }
                .buttonStyle(PMPressStyle())
        }
    }

    private func buyLabel(_ title: String) -> some View {
        Text(verbatim: title)
            .font(PMFont.text(.bold, 16, relativeTo: .headline))
            .foregroundStyle(AppColors.onAccent)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppColors.accentFill, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
    }

    private func buy() async { show(await app.purchases.purchasePro(using: purchase)) }
    private func restore() async { show(await app.purchases.restore()) }
    private func show(_ result: PurchaseResult) {
        let text = ProView.message(for: result)
        if !text.isEmpty { app.showToast(text) }
    }

    // MARK: Bausteine

    private func heading(_ title: String) -> some View {
        Text(verbatim: title).font(AppTypography.title3).foregroundStyle(AppColors.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 6).padding(.horizontal, 4)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(AppColors.surface, in: .rect(cornerRadius: 22))
            .clipShape(.rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(AppColors.surfaceStroke).frame(height: 1).accessibilityHidden(true)
    }

    /// Zeile mit Titel (16/600), optional Erklärung, Wert und Pfeil; mit Symbol als 38-pt-Kachel.
    private func row(_ title: String, subtitle: String? = nil, value: String? = nil, icon: PMIconName? = nil) -> some View {
        HStack(spacing: 14) {
            if let icon {
                PMIcon(icon, size: 19)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 38, height: 38)
                    .background(AppColors.warm, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(PMFont.text(.semibold, 16, relativeTo: .body)).foregroundStyle(AppColors.textPrimary)
                if let subtitle {
                    Text(verbatim: subtitle).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if let value {
                Text(verbatim: value).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary).lineLimit(1)
            }
            PMIcon(.chevronRight, size: 18)
                .foregroundStyle(AppColors.textTertiary)
                .flipsForRightToLeftLayoutDirection(true)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(minHeight: subtitle == nil ? 56 : 64)
        .contentShape(.rect)
    }

    private func toggle(_ title: String, _ path: WritableKeyPath<AppSettingsData, Bool>, subtitle: String? = nil) -> some View {
        Toggle(isOn: setting(path)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(PMFont.text(.semibold, 16, relativeTo: .body)).foregroundStyle(AppColors.textPrimary)
                if let subtitle {
                    Text(verbatim: subtitle).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(AppColors.success)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(subtitle.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 60)
    }

    /// „Später: Standardabstand“ als Menü mit den erlaubten Abständen.
    private var laterDefault: some View {
        Menu {
            Picker(L("set_later_default"), selection: setting(\.laterDefaultDays)) {
                ForEach(LaterInterval.allowedQuickDays, id: \.self) { Text(verbatim: LP("set_in_days", $0)).tag($0) }
            }
        } label: {
            row(L("set_later_default"), value: LP("set_in_days", app.settings.laterDefaultDays))
        }
        .accessibilityIdentifier("settings.later_default")
    }

    /// Name der aktuell verwendeten App-Sprache in dieser Sprache („Deutsch“, „English“ …).
    private var languageName: String {
        let id = Strings.language
        return Locale(identifier: id).localizedString(forIdentifier: id)?.capitalized(with: Locale(identifier: id)) ?? id
    }

    private func setting<T>(_ path: WritableKeyPath<AppSettingsData, T>) -> Binding<T> {
        Binding(get: { app.settings[keyPath: path] }, set: { value in app.updateSettings { $0[keyPath: path] = value } })
    }
}
