import PhotoMaidCore
import SwiftUI

/// Sperrbildschirm: Code, auf Wunsch Face ID/Touch ID, „Code vergessen?“ mit Notfallschlüssel. Nach Fehlversuchen
/// nur Wartezeit, nie Löschen.
struct VaultLockView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var vault = VaultStore.shared
    @State private var code = ""
    @State private var message: String?
    @State private var lockedUntil: Date?
    @State private var busy = false
    @State private var recoverySheet = false
    @FocusState private var focused: Bool

    private var kind: VaultCodeKind { vault.settings?.codeKind ?? .password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.l) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .padding(.top, AppSpacing.xl)
                        .accessibilityHidden(true)
                    Text(key: kind == .pin ? "vault_enter_pin" : "vault_enter_password")
                        .font(AppTypography.title)
                        .multilineTextAlignment(.center)
                    SecureField(L("vault_code_enter"), text: $code)
                        .keyboardType(kind == .pin ? .numberPad : .default)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { Task { await unlock() } }
                        .onChange(of: code) { _, v in
                            if kind == .pin, v.count == VaultCodeRules.pinLength { Task { await unlock() } }
                            if kind == .pin, v.count > VaultCodeRules.pinLength { code = String(v.prefix(VaultCodeRules.pinLength)) }
                        }
                        .padding(AppSpacing.s)
                        .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.small))
                        .disabled(busy || lockedUntil != nil)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let lockedUntil, lockedUntil > context.date {
                            Text(verbatim: L("vault_locked_wait", DateText.duration(lockedUntil.timeIntervalSince(context.date).rounded(.up))))
                                .font(AppTypography.footnote)
                                .foregroundStyle(AppColors.warning)
                                .multilineTextAlignment(.center)
                        } else if let message {
                            Text(verbatim: message).font(AppTypography.footnote).foregroundStyle(AppColors.cleanup)
                                .multilineTextAlignment(.center)
                        }
                    }
                    if kind == .password {
                        PrimaryButton(title: L("vault_unlock")) { Task { await unlock() } }
                            .disabled(code.isEmpty || busy || lockedUntil != nil)
                    }
                    if vault.settings?.biometrics == true, let name = vault.biometryName {
                        Button { Task { await unlockWithBiometrics() } } label: {
                            Label(L("vault_biometric_open", name), systemImage: name == "Touch ID" ? "touchid" : "faceid")
                        }
                        .buttonStyle(.pmBordered)
                        .frame(minHeight: AppSpacing.minTouch)
                    }
                    Button(L("vault_forgot")) { recoverySheet = true }
                        .frame(minHeight: AppSpacing.minTouch)
                }
                .padding(AppSpacing.pageMargin)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .appPage()
            .navigationTitle(L("vault_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { vault.lock() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text(key: "vault_close"))
                }
            }
            .sheet(isPresented: $recoverySheet) { VaultRecoveryUnlockSheet() }
            .task {
                refreshLockout()
                // Face ID nur von selbst starten, wenn der Tresor wirklich sichtbar geöffnet wird (nicht beim Schließen
                // und nicht, solange die App nicht aktiv ist).
                if vault.isPresented, scenePhase == .active,
                   vault.settings?.biometrics == true, vault.biometryName != nil {
                    await unlockWithBiometrics()
                } else {
                    focused = true
                }
            }
        }
    }

    private func refreshLockout() {
        guard let s = vault.settings else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let wait = s.lockout.remainingSeconds(nowMs: now)
        lockedUntil = wait > 0 ? Date().addingTimeInterval(TimeInterval(wait)) : nil
        if let until = lockedUntil {
            Task {
                try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
                if let current = lockedUntil, current <= Date() { lockedUntil = nil; focused = true }
            }
        }
    }

    private func unlock() async {
        guard !busy, !code.isEmpty, lockedUntil == nil else { return }
        busy = true
        let result = await vault.unlock(code: code)
        busy = false
        code = ""
        switch result {
        case .opened:
            message = nil
            Haptics.success()
        case .wrong:
            message = L("vault_wrong")
            Haptics.error()
            focused = true
        case .lockedOut:
            message = nil
            Haptics.error()
            refreshLockout()
        case .unavailable:
            message = L("vault_code_unavailable")
        case .cancelled:
            message = nil // inzwischen gesperrt (App verlassen): kein Fehlversuch, keine Meldung
        }
    }

    private func unlockWithBiometrics() async {
        if await vault.unlockWithBiometrics() { Haptics.success() } else { focused = true }
    }
}

/// „Code vergessen?“: mit dem Notfallschlüssel öffnen und danach einen neuen Code festlegen.
struct VaultRecoveryUnlockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    @State private var input = ""
    @State private var wrong = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                if vault.settings?.recovery == nil {
                    Text(key: "vault_forgot_none").foregroundStyle(AppColors.textSecondary)
                } else {
                    Section {
                        TextField(L("vault_recovery_enter"), text: $input, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } footer: {
                        Text(key: wrong ? "vault_recovery_wrong" : "vault_recovery_enter_hint")
                    }
                    Button(L("vault_unlock")) {
                        Task {
                            busy = true
                            let result = await vault.unlock(recoveryKey: input)
                            busy = false
                            switch result {
                            case .opened: dismiss()
                            case .cancelled: break
                            default: wrong = true
                            }
                        }
                    }
                    .disabled(VaultRecoveryKey.normalize(input) == nil || busy)
                }
            }
            .navigationTitle(L("vault_forgot"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
            }
        }
    }
}
