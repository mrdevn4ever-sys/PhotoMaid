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
    var body: some View {
        NavigationStack {
            List {
                Section { Text(L("vault2_trash_explanation")) }
                Section(L("vault2_media")) {
                    ForEach(vault.workspace.mediaTrash) { archived in
                        if let item = try? JSONDecoder().decode(VaultItem.self, from: archived.encodedItem) {
                            row(item.displayName, id: item.id, scope: nil)
                        }
                    }
                }
                Section(L("vault2_notes")) {
                    ForEach(vault.workspace.notes.filter { $0.trashedMs != nil }) { note in
                        row(note.title.isEmpty ? L("vault2_untitled") : note.title, id: note.id, scope: .notes)
                    }
                }
                Section(L("vault2_files")) {
                    ForEach(vault.workspace.files.filter { $0.trashedMs != nil }) { file in
                        row(file.name, id: file.id, scope: .files)
                    }
                }
                if vault.workspace.trashCount == 0 { Text(L("vault2_trash_empty")).foregroundStyle(.secondary) }
            }
            .navigationTitle(L("vault2_trash"))
            .toolbar { Button(L("done")) { dismiss() } }
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
            .vaultWorkspaceError($error)
        }
    }
    private func row(_ name: String, id: String, scope: VaultFolderScope?) -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: name).font(.headline)
            HStack {
                Button(L("vault2_put_back"), systemImage: "arrow.uturn.backward") {
                    if let scope {
                        perform { try vault.workspaceTransaction { try $0.restore([id], scope: scope) } }
                    } else {
                        Task {
                            do { try await vault.restoreMediaFromTrash([id], app: app) }
                            catch { self.error = VaultWorkspaceMessages.error(error) }
                        }
                    }
                }
                .accessibilityIdentifier("vault.trash.restore.\(id)")
                Spacer()
                Button(L("vault2_delete_forever"), systemImage: "trash", role: .destructive) { pending = VaultTrashAction(id: id, scope: scope) }
                    .accessibilityIdentifier("vault.trash.purge.\(id)")
            }.buttonStyle(.borderless).frame(minHeight: 48)
        }.padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("vault.trash.item.\(id)")
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = VaultWorkspaceMessages.error(error) } }
}
private struct VaultTrashAction { let id: String; let scope: VaultFolderScope? }
