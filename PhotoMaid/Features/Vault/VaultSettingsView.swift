import PhotoMaidCore
import SwiftUI

/// Einstellungen im Tresor: Code ändern, Face ID, Eingang verstecken, Notfallschlüssel, Tresor löschen.
struct VaultSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    @State private var changingCode = false
    @State private var newRecoveryKey: String?
    @State private var confirmRemoveRecovery = false
    @State private var confirmDeleteVault = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(L("vault_change_code")) { changingCode = true }
                    if let name = vault.biometryName {
                        Toggle(L("vault_biometric_toggle", name), isOn: Binding(
                            get: { vault.settings?.biometrics == true },
                            set: { if !vault.setBiometrics($0) { notice = L("vault_error_generic") } }))
                    }
                }
                Section {
                    Toggle(L("vault_hide_entry"), isOn: Binding(get: { vault.settings?.hideEntry == true },
                                                                set: { vault.setHideEntry($0) }))
                } footer: {
                    Text(key: "vault_hide_entry_text")
                }
                Section {
                    if let newRecoveryKey {
                        VaultRecoveryKeyCard(key: newRecoveryKey)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Button(L(vault.settings?.recovery == nil ? "vault_recovery_create" : "vault_recovery_renew")) {
                        Task {
                            newRecoveryKey = await vault.renewRecoveryKey()
                            if newRecoveryKey == nil { notice = L("vault_error_generic") }
                        }
                    }
                    if vault.settings?.recovery != nil {
                        Button(L("vault_recovery_remove"), role: .destructive) { confirmRemoveRecovery = true }
                    }
                } header: {
                    Text(key: "vault_recovery_title")
                } footer: {
                    Text(key: vault.settings?.recovery == nil ? "vault_recovery_missing" : "vault_recovery_present")
                }
                Section {
                    Button(L("vault_delete_all"), role: .destructive) { confirmDeleteVault = true }
                } footer: {
                    Text(key: "vault_backup_note")
                }
            }
            .navigationTitle(L("vault_settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } } }
            .sheet(isPresented: $changingCode) { VaultChangeCodeSheet() }
            .alert(L("vault_recovery_remove"), isPresented: $confirmRemoveRecovery) {
                Button(L("vault_recovery_remove"), role: .destructive) { vault.removeRecoveryKey(); newRecoveryKey = nil }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(key: "vault_recovery_skip_text")
            }
            .alert(L("vault_delete_all_title"), isPresented: $confirmDeleteVault) {
                Button(L("vault_delete_all"), role: .destructive) { vault.deleteVault(app: app) }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(verbatim: L("vault_delete_all_text", vault.index.items.count))
            }
            .alert(L("vault_title"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button(L("ok")) { notice = nil }
            } message: {
                Text(verbatim: notice ?? "")
            }
        }
    }
}

private struct VaultChangeCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    @State private var kind = VaultStore.shared.settings?.codeKind ?? .pin
    @State private var code = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    VaultCodeFields(kind: $kind, code: $code, confirmation: $confirmation)
                    if failed { Text(key: "vault_error_generic").font(AppTypography.footnote).foregroundStyle(AppColors.cleanup) }
                }
                .padding(AppSpacing.pageMargin)
            }
            .navigationTitle(L("vault_change_code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("save")) {
                        Task {
                            busy = true
                            let ok = await vault.changeCode(code, kind: kind)
                            busy = false
                            if ok { dismiss() } else { failed = true }
                        }
                    }
                    .disabled(busy || VaultCodeRules.validate(code, kind: kind, confirmation: confirmation) != nil)
                }
            }
            .overlay { if busy { ProgressView() } }
        }
    }
}
