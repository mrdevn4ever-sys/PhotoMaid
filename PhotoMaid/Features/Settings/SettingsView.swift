import PhotoMaidCore
import SwiftUI
import UIKit

/// Screen 15 – Einstellungen.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showPrivacy = false
    @State private var showPro = false
    @State private var restoreMessage: String?

    var body: some View {
        List {
            Section {
                Button { showPrivacy = true } label: {
                    SourceRow(symbol: "checkmark.shield.fill", tint: .blue, title: "Datenschutz & Zugriff",
                              detail: Text("Verarbeitung auf dem Gerät"))
                }.buttonStyle(.plain)
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    SourceRow(symbol: "bell.fill", tint: .blue, title: "Mitteilungen",
                              detail: Text(app.reminders.access == .allowed ? "Erlaubt" : "Aus"))
                }.buttonStyle(.plain)
                NavigationLink { SourcesView() } label: {
                    SourceRow(symbol: "folder.fill", tint: .blue, title: "Ordnerzugriff",
                              detail: Text("\(app.sources.sources.count) verbunden"))
                }
            }
            Section("Bedienung") {
                Toggle("Haptisches Feedback", isOn: Binding(get: { app.settings.haptics },
                                                            set: { v in app.updateSettings { $0.haptics = v } }))
                Toggle("Gestenhilfe beim Öffnen zeigen", isOn: Binding(get: { app.settings.showGestureHintOnOpen },
                                                                     set: { v in app.updateSettings { $0.showGestureHintOnOpen = v } }))
                Picker("Später (Wisch nach rechts)", selection: Binding(get: { app.settings.laterDefaultDays },
                                                                        set: { v in app.updateSettings { $0.laterDefaultDays = v } })) {
                    ForEach(LaterInterval.allowedQuickDays, id: \.self) { d in
                        Text(d == 1 ? "Morgen" : "In \(d) Tagen").tag(d)
                    }
                }
                Picker("Erscheinungsbild", selection: Binding(get: { app.settings.appearance },
                                                              set: { v in app.updateSettings { $0.appearance = v } })) {
                    Text("System").tag(AppearanceChoice.system)
                    Text("Hell").tag(AppearanceChoice.light)
                    Text("Dunkel").tag(AppearanceChoice.dark)
                }
            }
            Section("So wischst du") {
                HStack(spacing: AppSpacing.xs) {
                    swipeTile("arrow.up", "Hoch", "Behalten", AppColors.keep)
                    swipeTile("arrow.left", "Links", "Papierkorb", AppColors.cleanup)
                    swipeTile("arrow.right", "Rechts", "Später", AppColors.later)
                    swipeTile("arrow.up.right", "Schräg hoch", "Datum wählen", AppColors.later)
                    swipeTile("arrow.down", "Runter", "Zurück", AppColors.textSecondary)
                }
                .listRowBackground(Color.clear)
            }
            Section {
                Button { showPro = true } label: {
                    SourceRow(symbol: "crown.fill", tint: .blue, title: "PhotoMaid Pro",
                              detail: Text(app.entitlements.purchases.state == .purchased ? "Aktiv" : "Einmalkauf"))
                }.buttonStyle(.plain)
                if app.entitlements.purchases.isConfigured {
                    Button("Käufe wiederherstellen") {
                        Task {
                            let r = await app.entitlements.purchases.restore()
                            restoreMessage = r == .purchased ? String(localized: "Dein Kauf wurde wiederhergestellt.")
                                : String(localized: "Es wurde kein Kauf zum Wiederherstellen gefunden.")
                        }
                    }
                }
            }
            Section {
                NavigationLink("Hilfe") { HelpView() }
                LabeledContent("Version", value: Bundle.main.versionString)
                if let url = Bundle.main.privacyPolicyURL {
                    Link("Datenschutzerklärung", destination: url)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Einstellungen"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        .sheet(isPresented: $showPrivacy) { PrivacyAccessView().environment(app) }
        .sheet(isPresented: $showPro) { NavigationStack { ProView() }.environment(app) }
        .alert("Hinweis", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(restoreMessage ?? "") }
    }

    private func swipeTile(_ symbol: String, _ dir: LocalizedStringKey, _ meaning: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(tint)
                .frame(width: 48, height: 48).glassEffect(.regular, in: .rect(cornerRadius: AppRadii.small))
            Text(dir).font(AppTypography.caption.weight(.semibold))
            Text(meaning).font(.caption2).foregroundStyle(AppColors.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section("Entscheiden") {
                Text("Wisch nach oben, um ein Medium zu behalten. Nach links kommt es in den Papierkorb, nach rechts auf später (Standard: in 2 Tagen), schräg nach rechts oben wählst du das Datum selbst. Nach unten kommst du zum vorherigen Medium – ohne etwas zu entscheiden.")
            }
            Section("Löschen") {
                Text("PhotoMaid löscht nie automatisch. Was du nach links wischst, landet im PhotoMaid-Papierkorb; gelöscht wird erst, wenn du ihn leerst. Fotos und Videos entfernt iOS nach deiner Bestätigung in „Zuletzt gelöscht“. Dateien werden endgültig gelöscht.")
            }
            Section("iCloud") {
                Text("Wenn iCloud-Fotos aktiv ist, wirken Löschungen auf allen deinen Geräten. Medien, die nur in iCloud liegen, lädt PhotoMaid nicht herunter.")
            }
            Section("Kostenlos") {
                Text("Ansehen, sortieren und später prüfen ist unbegrenzt. Bestätigte Bereinigungen sind auf 15 pro Tag begrenzt.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Hilfe"))
    }
}

extension Bundle {
    var versionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var privacyPolicyURL: URL? {
        guard let s = infoDictionary?["PMPrivacyPolicyURL"] as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }
}
