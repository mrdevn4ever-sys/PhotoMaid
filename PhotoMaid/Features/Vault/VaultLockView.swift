import PhotoMaidCore
import SwiftUI

/// Sperrbildschirm: Code, auf Wunsch Face ID/Touch ID, „Code vergessen?“ mit Notfallschlüssel. Nach Fehlversuchen
/// nur Wartezeit, nie Löschen.
/// Experiment-Design: wie im Artefakt – „Privater Tresor“, Punkte und rundes Ziffernfeld (72 pt) für die PIN; ein
/// Passwort wird weiter über die Tastatur eingegeben. Statt der Schloss-Kachel ein Zahlenschloss-Rad (Nutzerwunsch
/// 21.10.2026), das sich je Eingabe abwechselnd links und rechts dreht – um feste Winkel, nie zur getippten Ziffer.
struct VaultLockView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vault = VaultStore.shared
    @State private var code = ""
    @State private var message: String?
    @State private var lockedUntil: Date?
    @State private var busy = false
    @State private var recoverySheet = false
    @State private var dialTurn = 0.0
    @FocusState private var focused: Bool

    private var kind: VaultCodeKind { vault.settings?.codeKind ?? .password }
    private var inputDisabled: Bool { busy || lockedUntil != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        GlassIconButton(symbol: "xmark", label: L("vault_close")) { vault.lock() }
                        Spacer()
                    }
                    CombinationDial(rotation: dialTurn)
                        .frame(width: 104, height: 104)
                        .shadow(color: AppColors.shadow, radius: 14, y: 8)
                        .padding(.top, 4)
                    VStack(spacing: 4) {
                        Text(key: "vault_title").font(PMFont.display(30, relativeTo: .title)).tracking(-0.6)
                            .foregroundStyle(AppColors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(key: kind == .pin ? "vault_enter_pin" : "vault_enter_password")
                            .font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    if kind == .pin {
                        dots
                    } else {
                        SecureField(L("vault_code_enter"), text: $code)
                            .keyboardType(.default)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit { Task { await unlock() } }
                            .font(AppTypography.body)
                            .padding(.horizontal, 16).frame(minHeight: 52)
                            .background(AppColors.surface, in: .rect(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppColors.control, lineWidth: 1))
                            .disabled(inputDisabled)
                    }
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
                    if kind == .pin {
                        keypad
                    } else {
                        PrimaryButton(title: L("vault_unlock")) { Task { await unlock() } }
                            .disabled(code.isEmpty || inputDisabled)
                    }
                    if vault.settings?.biometrics == true, let name = vault.biometryName {
                        Button { Task { await unlockWithBiometrics() } } label: {
                            Text(verbatim: L("vault_biometric_open", name))
                                .font(PMFont.text(.semibold, 16, relativeTo: .body)).foregroundStyle(AppColors.accent)
                                .padding(.horizontal, 8).frame(minHeight: AppSpacing.minTouch)
                                .contentShape(.rect)
                        }
                        .buttonStyle(PMPressStyle())
                    }
                    Button { recoverySheet = true } label: {
                        Text(key: "vault_forgot")
                            .font(PMFont.text(.semibold, 14, relativeTo: .subheadline)).foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, 8).frame(minHeight: AppSpacing.minTouch)
                            .contentShape(.rect)
                    }
                    .buttonStyle(PMPressStyle())
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.bottom, AppSpacing.xl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .appPage()
            .navigationTitle(L("vault_title"))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $recoverySheet) { VaultRecoveryUnlockSheet() }
            .onChange(of: code.count) { old, new in turnDial(from: old, to: new) }
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

    /// Sechs Punkte (14 pt, 2-pt-Rand); gefüllt = eingegebene Ziffer.
    private var dots: some View {
        HStack(spacing: 14) {
            ForEach(0..<VaultCodeRules.pinLength, id: \.self) { i in
                Circle()
                    .fill(i < code.count ? AppColors.textPrimary : Color.clear)
                    .overlay(Circle().strokeBorder(i < code.count ? AppColors.textPrimary : AppColors.textTertiary, lineWidth: 2))
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L("art_pin_progress", code.count, VaultCodeRules.pinLength)))
        .accessibilityIdentifier("vault.pin.dots")
    }

    /// Ziffernfeld 3 × 4: 1–9, leer, 0, Löschen. Runde Tasten 72 pt, Abstand 14 × 26.
    private var keypad: some View {
        Grid(horizontalSpacing: 26, verticalSpacing: 14) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { column in digit(String(row * 3 + column)) }
                }
            }
            GridRow {
                Color.clear.frame(width: 72, height: 72).accessibilityHidden(true)
                digit("0")
                Button {
                    if !code.isEmpty { code.removeLast() }
                } label: {
                    Image(systemName: "delete.left").font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 72, height: 72)
                        .contentShape(.circle)
                }
                .buttonStyle(PMPressStyle())
                .disabled(code.isEmpty || inputDisabled)
                .accessibilityLabel(Text(key: "art_pin_delete"))
                .accessibilityIdentifier("vault.key.delete")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func digit(_ d: String) -> some View {
        Button {
            guard !inputDisabled, code.count < VaultCodeRules.pinLength else { return }
            code += d
            Haptics.tick()
            if code.count == VaultCodeRules.pinLength { Task { await unlock() } }
        } label: {
            Text(verbatim: d)
                .font(PMFont.keypad(28))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 72, height: 72)
                .background(AppColors.surface, in: .circle)
                .overlay(Circle().strokeBorder(AppColors.control, lineWidth: 1))
                .contentShape(.circle)
        }
        .buttonStyle(PMPressStyle())
        .disabled(inputDisabled)
        .accessibilityIdentifier("vault.key." + d)
    }

    /// Je Zeichen eine Drehung, abwechselnd links und rechts (erste links); Löschen nimmt die letzte zurück, eine leere
    /// Eingabe (falscher Code, Löschen) federt auf null. Die Winkel hängen nur von der Anzahl ab, nie vom Zeichen.
    private func turnDial(from old: Int, to new: Int) {
        guard !reduceMotion else { return }
        if new == 0 {
            withAnimation(.spring(duration: 0.55, bounce: 0.3)) { dialTurn = 0 }
        } else if new > old {
            let direction = new % 2 == 1 ? -1.0 : 1.0
            withAnimation(.easeInOut(duration: 0.4)) { dialTurn += direction * 150 }
        } else {
            let direction = old % 2 == 1 ? -1.0 : 1.0
            withAnimation(.easeOut(duration: 0.25)) { dialTurn -= direction * 150 }
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
