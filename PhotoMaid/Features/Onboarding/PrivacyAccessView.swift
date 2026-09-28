import SwiftUI
import UIKit

/// Screen 4 – Datenschutz/Zugriff. Zeigt echte Systemzustände; keine Fake-Schalter.
/// Anfragen erfolgen kontextuell per Button, erst nach Erklärung.
struct PrivacyAccessView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                Image(systemName: "checkmark.shield.fill").font(.system(size: 56)).foregroundStyle(AppColors.accent)
                    .padding(AppSpacing.l).glassEffect(.regular, in: .rect(cornerRadius: AppRadii.card))
                    .accessibilityHidden(true)
                Text("Deine Privatsphäre zuerst").font(AppTypography.title).multilineTextAlignment(.center)
                Text("PhotoMaid analysiert deine Fotos, Videos und freigegebenen Dateien auf diesem Gerät. Es gibt keinen PhotoMaid-Server und kein Konto. Wenn du iCloud-Fotos nutzt, synchronisiert Apple deine Mediathek – auch Löschungen können dann andere Geräte betreffen.")
                    .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)

                SurfaceCard { photosRow }
                SurfaceCard { notificationsRow }
                SurfaceCard {
                    HStack(alignment: .top, spacing: AppSpacing.s) {
                        Image(systemName: "folder").foregroundStyle(AppColors.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ordner (optional)").font(AppTypography.headline)
                            Text("Dateien siehst du nur aus Ordnern, die du selbst auswählst. Das geht jederzeit unter Aufräumen › Dateien.")
                                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                Text("Käufe laufen über den App Store und RevenueCat. Freiwillige Werbung stammt von einem Werbeanbieter. Dabei werden keine Fotos, Dateinamen, Pfade oder Hashes übertragen.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
            }
            .padding(AppSpacing.pageMargin)
        }
        // „Weiter“ immer sichtbar, auch auf kleinen iPhones und bei großer Schrift.
        .safeAreaInset(edge: .bottom) {
            Button {
                app.updateSettings { $0.privacyIntroSeen = true }
                dismiss()
            } label: {
                Text("Weiter").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xs)
        }
        .background(AppBackground())
        .task { await app.reminders.refresh() }
    }

    private var photosRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Label("Fotos & Videos", systemImage: "photo.on.rectangle.angled").font(AppTypography.headline)
                Spacer()
                statusBadge
            }
            Text("Zum Anzeigen, Sortieren und – nur nach deiner Bestätigung – Entfernen ausgewählter Medien.")
                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            switch app.photos.access {
            case .notDetermined:
                Button("Zugriff erlauben") { Task { await app.photos.requestAccess() } }.buttonStyle(.glassProminent)
            case .limited:
                Button("Auswahl verwalten") { app.photos.presentLimitedLibraryPicker() }.buttonStyle(.glass)
            case .denied:
                Button("iOS-Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.buttonStyle(.glass)
            case .authorized, .restricted:
                EmptyView()
            }
        }
    }

    private var statusBadge: some View {
        let (text, color): (LocalizedStringKey, Color) = switch app.photos.access {
        case .authorized: ("Voller Zugriff", AppColors.success)
        case .limited: ("Ausgewählte Fotos", AppColors.warning)
        case .denied: ("Abgelehnt", AppColors.cleanup)
        case .restricted: ("Eingeschränkt", AppColors.cleanup)
        case .notDetermined: ("Nicht angefragt", AppColors.textSecondary)
        }
        return Text(text).font(AppTypography.caption.weight(.semibold)).foregroundStyle(color)
    }

    private var notificationsRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Label("Mitteilungen", systemImage: "bell").font(AppTypography.headline)
                Spacer()
                Text(app.reminders.access == .allowed ? "Erlaubt" : (app.reminders.access == .denied ? "Abgelehnt" : "Nicht angefragt"))
                    .font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
            }
            Text("Optional: Erinnerungen an fällige Wiedervorlagen. Ohne Dateinamen auf dem Sperrbildschirm.")
                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            if app.reminders.access == .notDetermined {
                Button("Mitteilungen erlauben") { Task { await app.reminders.requestAccess() } }.buttonStyle(.glass)
            }
        }
    }
}
