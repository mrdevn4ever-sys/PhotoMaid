import PhotoMaidCore
import SwiftUI

/// Einrichten in fünf kurzen Schritten: Was der Tresor tut (und was nicht) → Code → Face ID → Notfallschlüssel →
/// Eingang verstecken. Nichts wird angelegt, bevor der letzte Schritt bestätigt ist.
struct VaultSetupView: View {
    @State private var vault = VaultStore.shared
    @State private var step = 0
    @State private var kind = VaultCodeKind.pin
    @State private var code = ""
    @State private var confirmation = ""
    @State private var biometrics = true
    @State private var recoveryKey = VaultStore.makeRecoveryKey()
    @State private var useRecovery = true
    @State private var confirmSkipRecovery = false
    @State private var hideEntry = true
    @State private var busy = false
    @State private var failed = false

    private var steps: Int { vault.biometryName == nil ? 4 : 5 }
    /// Schritte ohne Face ID-Seite überspringen deren Index.
    private var page: Int { vault.biometryName == nil && step >= 2 ? step + 1 : step }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    content
                }
                .padding(AppSpacing.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .appPage()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("vault_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == 0 {
                        Button { vault.lock() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(Text(key: "vault_close"))
                    } else {
                        Button { step -= 1 } label: { Image(systemName: "chevron.backward") }
                            .accessibilityLabel(Text(key: "back"))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(verbatim: L("onb_progress", step + 1, steps)).font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: L(step == steps - 1 ? "vault_setup_finish" : (page == 3 ? "vault_recovery_done" : "onb_next"))) { next() }
                    .disabled(!canContinue || busy)
                    .padding(AppSpacing.pageMargin)
            }
            .overlay {
                if busy {
                    LoadingState(message: L("vault_setup_running"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert(L("vault_recovery_skip_title"), isPresented: $confirmSkipRecovery) {
                Button(L("vault_recovery_skip"), role: .destructive) { useRecovery = false; step += 1 }
                Button(L("cancel"), role: .cancel) {}
            } message: {
                Text(key: "vault_recovery_skip_text")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case 0:
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(key: "vault_intro_title").font(AppTypography.title)
            ForEach([("lock.shield", "vault_intro_1"), ("trash", "vault_intro_2"), ("externaldrive.badge.icloud", "vault_intro_3"),
                     ("folder", "vault_intro_4")], id: \.1) { item in
                Label { Text(key: item.1).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: item.0).foregroundStyle(AppColors.accent)
                }
                .font(AppTypography.body)
            }
        case 1:
            Text(key: "vault_code_title").font(AppTypography.title)
            Text(key: "vault_code_text").foregroundStyle(AppColors.textSecondary)
            VaultCodeFields(kind: $kind, code: $code, confirmation: $confirmation)
        case 2:
            Text(verbatim: L("vault_biometric_title", vault.biometryName ?? "")).font(AppTypography.title)
            Toggle(L("vault_biometric_toggle", vault.biometryName ?? ""), isOn: $biometrics)
            Text(key: "vault_biometric_text").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
        case 3:
            Text(key: "vault_recovery_step_title").font(AppTypography.title)
            if let recoveryKey {
                VaultRecoveryKeyCard(key: recoveryKey)
                Button(L("vault_recovery_skip")) { confirmSkipRecovery = true }
                    .frame(minHeight: AppSpacing.minTouch)
            } else {
                Text(key: "vault_error_generic").foregroundStyle(AppColors.cleanup)
            }
        default:
            Text(key: "vault_hide_title").font(AppTypography.title)
            Toggle(L("vault_hide_entry"), isOn: $hideEntry)
            Text(key: "vault_hide_entry_text").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            if failed { Text(key: "vault_error_generic").font(AppTypography.footnote).foregroundStyle(AppColors.cleanup) }
        }
    }

    private var canContinue: Bool {
        switch page {
        case 1: VaultCodeRules.validate(code, kind: kind, confirmation: confirmation) == nil
        default: true
        }
    }

    private func next() {
        if page == 3 { useRecovery = recoveryKey != nil }
        guard step == steps - 1 else { step += 1; return }
        Task {
            busy = true
            failed = false
            let ok = await vault.setUp(code: code, kind: kind, recoveryKey: useRecovery ? recoveryKey : nil,
                                       biometrics: vault.biometryName != nil && biometrics, hideEntry: hideEntry)
            busy = false
            failed = !ok
            if ok { Haptics.commit() }
        }
    }
}
