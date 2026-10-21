import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

struct VaultWorkspaceToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var vault = VaultStore.shared
    @State private var password = ""
    @State private var repeatPassword = ""
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    @State private var share: VaultShare?
    @State private var restored = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L("vault2_auto_lock")) {
                    Picker(L("vault2_auto_lock"), selection: Binding(get: { vault.workspace.inactivitySeconds }, set: { value in
                        do { try vault.setInactivity(value) } catch { self.error = VaultWorkspaceMessages.error(error) }
                    })) {
                        Text(L("vault2_seconds", 30)).tag(30)
                        ForEach([1, 2, 5, 10], id: \.self) { value in Text(L("vault2_minutes", value)).tag(value * 60) }
                    }
                    Text(L("vault2_background_lock")).font(.footnote)
                    Button(L("vault2_lock"), systemImage: "lock.fill") { vault.lock() }
                }
                Section(L("vault2_backup")) {
                    Text(L("vault2_backup_explanation"))
                    SecureField(L("vault2_backup_password"), text: $password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: password) { _, _ in vault.touch() }
                    SecureField(L("vault2_repeat_password"), text: $repeatPassword)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: repeatPassword) { _, _ in vault.touch() }
                    Button(L("vault2_export_backup"), systemImage: "lock.doc") {
                        Task {
                            busy = true; defer { busy = false; password = ""; repeatPassword = "" }
                            do {
                                let url = try await vault.encryptedBackup(password: password)
                                share = VaultShare(urls: [url])
                            } catch is CancellationError {} catch { self.error = VaultWorkspaceMessages.error(error) }
                        }
                    }.disabled(password.count < 12 || password != repeatPassword)
                    Button(L("vault2_restore_backup"), systemImage: "arrow.down.doc") { importing = true }
                        .disabled(password.count < 12)
                    Text(L("vault2_restore_explanation")).font(.footnote)
                }
                Section {
                    Text(L("vault2_local_only")).font(.footnote)
                }
            }
            .navigationTitle(L("vault2_tools"))
            .toolbar { Button(L("done")) { dismiss() } }
            .disabled(busy)
            .interactiveDismissDisabled(busy)
            .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: .rect(cornerRadius: 16)) } }
            .sheet(item: $share) { value in ShareSheet(items: value.urls) { vault.removeTempFiles(value.urls) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url):
                    Task {
                        guard await VaultDisclosure.confirm(messageKey: "vault2_restore_explanation") else { return }
                        busy = true; defer { busy = false; password = ""; repeatPassword = "" }
                        do {
                            try await vault.restoreEncryptedBackup(url, password: password,
                                                                   unlimited: app.capabilities.hasProToolsAccess, app: app)
                            restored = true
                        } catch is CancellationError {} catch { self.error = L("vault2_backup_failed") }
                    }
                case .failure: error = L("vault2_operation_failed")
                }
            }
            .alert(L("vault2_restored"), isPresented: $restored) { Button(L("ok"), role: .cancel) {} }
            .vaultWorkspaceError($error)
            .onDisappear { password = ""; repeatPassword = "" }
        }
    }
}

struct VaultWorkspaceTrashView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    @State private var error: String?
    @State private var pending: VaultTrashAction?
    @State private var confirmEmpty = false
    /// Experiment-Design: wie im Artefakt – „Fertig“ oben rechts, oranger Titel, Erklärung, großer Knopf
    /// „Alles endgültig löschen“, Karten je Bereich mit „Im Tresor wiederherstellen“ und „Endgültig löschen“.
    var body: some View {
        let media = vault.workspace.mediaTrash.compactMap { try? JSONDecoder().decode(VaultItem.self, from: $0.encodedItem) }
        let notes = vault.workspace.notes.filter { $0.trashedMs != nil }
        let files = vault.workspace.files.filter { $0.trashedMs != nil }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Text(key: "done")
                                .font(PMFont.text(.semibold, 15, relativeTo: .subheadline)).foregroundStyle(AppColors.textPrimary)
                                .padding(.horizontal, 18).frame(minHeight: 44)
                                .background(AppColors.surface, in: .capsule)
                                .overlay(Capsule().strokeBorder(AppColors.control, lineWidth: 1))
                                .contentShape(.capsule)
                        }
                        .buttonStyle(PMPressStyle())
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key: "vault2_trash").font(PMFont.display(36, relativeTo: .largeTitle)).tracking(-0.72)
                            .foregroundStyle(AppColors.cleanup)
                            .accessibilityAddTraits(.isHeader)
                        Text(key: "vault2_trash_explanation").font(PMFont.text(.regular, 14, relativeTo: .subheadline))
                            .foregroundStyle(AppColors.textSecondary).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if vault.workspace.trashCount > 0 {
                        PrimaryButton(title: L("vault2_empty_trash"), symbol: "trash", role: .destructive) { confirmEmpty = true }
                            .accessibilityIdentifier("vault.trash.empty")
                    }
                    if !media.isEmpty {
                        section(L("vault2_media")) { ForEach(media, id: \.id) { row($0.displayName, id: $0.id, scope: nil) } }
                    }
                    if !notes.isEmpty {
                        section(L("vault2_notes")) {
                            ForEach(notes) { row($0.title.isEmpty ? L("vault2_untitled") : $0.title, id: $0.id, scope: .notes) }
                        }
                    }
                    if !files.isEmpty {
                        section(L("vault2_files")) { ForEach(files) { row($0.name, id: $0.id, scope: .files) } }
                    }
                    if vault.workspace.trashCount == 0 {
                        Text(key: "vault2_trash_empty").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 36).padding(.horizontal, 20)
                            .frame(maxWidth: .infinity)
                            .overlay(RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(AppColors.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    }
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.xxl)
            }
            .appPage()
            .navigationTitle(L("vault2_trash"))
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(L("vault2_delete_forever"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button(L("vault2_delete_forever"), role: .destructive) {
                    guard let action = pending else { return }
                    perform {
                        if let scope = action.scope {
                            try vault.workspaceTransaction { try $0.permanentlyRemove([action.id], scope: scope) }
                            vault.finishPendingPurges()
                        } else { try vault.purgeMediaFromTrash([action.id], app: app) }
                    }
                    pending = nil
                }
                Button(L("cancel"), role: .cancel) { pending = nil }
            } message: { Text(L("vault2_delete_forever_warning")) }
            .alert(L("vault2_empty_trash_title"), isPresented: $confirmEmpty) {
                Button(L("vault2_empty_trash"), role: .destructive) { perform { try vault.emptyTrash(app: app) } }
                Button(L("cancel"), role: .cancel) {}
            } message: { Text(L("vault2_empty_trash_message", LP("items_count", vault.workspace.trashCount))) }
            .vaultWorkspaceError($error)
        }
    }

    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: title).font(PMFont.heading(18, relativeTo: .headline)).foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4).padding(.horizontal, 4)
            VStack(spacing: 0) { rows() }
                .background(AppColors.surface, in: .rect(cornerRadius: 20))
                .clipShape(.rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        }
    }

    private func row(_ name: String, id: String, scope: VaultFolderScope?) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: name).font(PMFont.text(.semibold, 15, relativeTo: .subheadline)).foregroundStyle(AppColors.textPrimary)
            HStack(spacing: AppSpacing.xs) {
                Button {
                    if let scope {
                        perform { try vault.workspaceTransaction { try $0.restore([id], scope: scope) } }
                    } else {
                        Task {
                            do { try await vault.restoreMediaFromTrash([id], app: app) }
                            catch { self.error = VaultWorkspaceMessages.error(error) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        PMIcon(.undo, size: 14, lineWidth: 2.4).accessibilityHidden(true)
                        Text(key: "vault2_put_back")
                    }
                    .font(PMFont.text(.semibold, 13, relativeTo: .footnote)).foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 12).frame(minHeight: 40)
                    .background(AppColors.background, in: .capsule)
                    .overlay(Capsule().strokeBorder(AppColors.control, lineWidth: 1))
                    .frame(minHeight: AppSpacing.minTouch)
                    .contentShape(.rect)
                }
                .buttonStyle(PMPressStyle())
                .accessibilityIdentifier("vault.trash.restore.\(id)")
                Spacer(minLength: 0)
                Button { pending = VaultTrashAction(id: id, scope: scope) } label: {
                    Text(key: "vault2_delete_forever")
                        .font(PMFont.text(.semibold, 13, relativeTo: .footnote)).foregroundStyle(AppColors.cleanup)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 12).frame(minHeight: 40)
                        .background(AppColors.hex(0x26150F), in: .capsule)
                        .overlay(Capsule().strokeBorder(AppColors.hex(0x5A2E20), lineWidth: 1))
                        .frame(minHeight: AppSpacing.minTouch)
                        .contentShape(.rect)
                }
                .buttonStyle(PMPressStyle())
                .accessibilityIdentifier("vault.trash.purge.\(id)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(AppColors.surfaceStroke).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vault.trash.item.\(id)")
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = VaultWorkspaceMessages.error(error) } }
}
private struct VaultTrashAction { let id: String; let scope: VaultFolderScope? }
