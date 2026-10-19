import PhotoMaidCore
import SwiftUI

/// Privater Tresor (E16) als eigene Vollbild-Ebene. Einrichten → Sperrbildschirm → Inhalt. Beim Verlassen der App
/// sperrt `RootView` den Tresor und schließt diese Ebene; im App-Umschalter ist der Inhalt abgedeckt.
struct VaultRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vault = VaultStore.shared

    var body: some View {
        ZStack {
            if !vault.isPresented {
                // Schließen läuft (Ausblende-Animation): nicht kurz den Sperrbildschirm zeigen – der würde sonst
                // Face ID von selbst starten und den Tresor unsichtbar wieder öffnen.
                PrivacyShield()
            } else {
                switch vault.phase {
                case .notSetUp:
                    VaultSetupView()
                case .locked:
                    VaultLockView()
                case .unlocked:
                    if vault.needsNewCode { VaultNewCodeView() } else { VaultWorkspaceHomeView() }
                }
            }
            if scenePhase != .active {
                PrivacyShield().zIndex(5)
            }
        }
        .animation(AppMotion.open(reduceMotion), value: vault.phase)
        .privacySensitive()
        .accessibilityHidden(scenePhase != .active)
        .allowsHitTesting(scenePhase == .active)
    }
}

/// Eingabe eines neuen Codes (PIN oder Passwort) mit Wiederholung und verständlicher Prüfung.
struct VaultCodeFields: View {
    @Binding var kind: VaultCodeKind
    @Binding var code: String
    @Binding var confirmation: String
    @FocusState private var focused: Bool

    var problem: VaultCodeRules.Problem? { VaultCodeRules.validate(code, kind: kind, confirmation: confirmation) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Picker(L("vault_code_kind"), selection: $kind) {
                Text(key: "vault_code_pin").tag(VaultCodeKind.pin)
                Text(key: "vault_code_password").tag(VaultCodeKind.password)
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, _ in code = ""; confirmation = "" }
            field(L("vault_code_enter"), text: $code).focused($focused)
            field(L("vault_code_repeat"), text: $confirmation)
            if let message { Text(verbatim: message).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary) }
        }
        .onAppear { focused = true }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .keyboardType(kind == .pin ? .numberPad : .default)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(AppSpacing.s)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.small))
            .onChange(of: text.wrappedValue) { _, v in
                if kind == .pin && v.count > VaultCodeRules.pinLength { text.wrappedValue = String(v.prefix(VaultCodeRules.pinLength)) }
            }
    }

    /// Hinweis erst, wenn etwas eingegeben wurde (keine rote Fehlermeldung beim Öffnen).
    private var message: String? {
        guard !code.isEmpty else { return L(kind == .pin ? "vault_code_rule_pin" : "vault_code_rule_password") }
        switch problem {
        case .tooShort: return L(kind == .pin ? "vault_code_rule_pin" : "vault_code_rule_password")
        case .notDigits: return L("vault_code_digits")
        case .mismatch: return confirmation.isEmpty ? nil : L("vault_code_mismatch")
        case nil: return nil
        }
    }
}

/// Notfallschlüssel groß und gut lesbar (zum Abschreiben). Kein Kopieren in die Zwischenablage.
struct VaultRecoveryKeyCard: View {
    let key: String

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Label { Text(key: "vault_recovery_title") } icon: { Image(systemName: "key.fill") }
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.accent)
                Text(verbatim: key)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.disabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(verbatim: key.map { String($0) }.joined(separator: " ")))
                Text(key: "vault_recovery_text").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

/// Nach dem Öffnen mit dem Notfallschlüssel: neuen Code festlegen.
struct VaultNewCodeView: View {
    @State private var vault = VaultStore.shared
    @State private var kind = VaultCodeKind.pin
    @State private var code = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    Text(key: "vault_new_code_text").foregroundStyle(AppColors.textSecondary)
                    VaultCodeFields(kind: $kind, code: $code, confirmation: $confirmation)
                    if failed { Text(key: "vault_error_generic").font(AppTypography.footnote).foregroundStyle(AppColors.cleanup) }
                }
                .padding(AppSpacing.pageMargin)
            }
            .appPage()
            .navigationTitle(L("vault_new_code_title"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: L("vault_save_code")) {
                    Task {
                        busy = true
                        failed = !(await vault.changeCode(code, kind: kind))
                        busy = false
                    }
                }
                .disabled(busy || VaultCodeRules.validate(code, kind: kind, confirmation: confirmation) != nil)
                .padding(AppSpacing.pageMargin)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { vault.lock() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text(key: "vault_close"))
                }
            }
            .overlay { if busy { LoadingState().frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial) } }
        }
    }
}
