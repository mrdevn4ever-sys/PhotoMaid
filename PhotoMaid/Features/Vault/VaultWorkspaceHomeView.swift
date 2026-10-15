import PhotoMaidCore
import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import UniformTypeIdentifiers

/// These are internal vault tabs, never destinations in PhotoMaid's public navigation.
struct VaultWorkspaceHomeView: View {
    @State private var vault = VaultStore.shared
    @State private var tab = 0
    @State private var tools = false
    @State private var trash = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(L("vault_title"), selection: $tab) {
                    Text(L("vault2_media")).tag(0)
                    Text(L("vault2_notes")).tag(1)
                    Text(L("vault2_files")).tag(2)
                }.pickerStyle(.segmented)
                Menu {
                    Button(L("vault2_trash"), systemImage: "trash") { trash = true }
                    Button(L("vault2_tools"), systemImage: "lock.shield") { tools = true }
                    Button(L("vault2_lock"), systemImage: "lock.fill") { vault.lock() }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 48, height: 48) }
                .accessibilityLabel(L("more_actions"))
                .accessibilityIdentifier("vault.workspace.more")
            }.padding(.horizontal)
            switch tab {
            case 1: VaultNotesView()
            case 2: VaultFilesView()
            default: VaultHomeView()
            }
        }
        .sheet(isPresented: $tools) { VaultWorkspaceToolsView() }
        .sheet(isPresented: $trash) { VaultWorkspaceTrashView() }
        .background(VaultActivityMonitor())
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                vault.checkInactivity()
            }
        }
        .alert(L("vault2_save_failed"), isPresented: $vault.operationFailed) {
            Button(L("ok"), role: .cancel) {}
        } message: { Text(L("vault2_operation_failed")) }
    }
}

/// ✕ oben links: Tresor schließen (sperrt sofort). Auf allen drei Reitern (Medien, Notizen, Dateien) gleich.
struct VaultCloseToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { VaultStore.shared.lock() } label: { Image(systemName: "xmark") }
                .accessibilityLabel(Text(key: "vault_close"))
        }
    }
}

struct VaultNotesView: View {
    @State private var vault = VaultStore.shared
    @State private var query = ""
    @State private var folder: String?
    @State private var editor: VaultNote?
    @State private var error: String?
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var pendingDelete: Set<String>?
    private var notes: [VaultNote] { vault.workspace.visibleNotes(query: query, folderID: folder) }

    var body: some View {
        NavigationStack {
            List {
                VaultWorkspaceFolderBar(scope: .notes, folder: $folder)
                if notes.isEmpty { Text(L("vault2_empty_notes")).foregroundStyle(.secondary) }
                ForEach(notes) { note in
                    Button {
                        if selecting {
                            if selection.contains(note.id) { selection.remove(note.id) } else { selection.insert(note.id) }
                        } else { editor = note }
                    } label: {
                        HStack {
                            if selecting { Image(systemName: selection.contains(note.id) ? "checkmark.circle.fill" : "circle") }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    if note.pinned { Image(systemName: "pin.fill") }
                                    Text(verbatim: note.title.isEmpty ? L("vault2_untitled") : note.title).font(.headline)
                                }
                                Text(verbatim: note.plainText).lineLimit(2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                        .contentShape(.rect)
                    }.buttonStyle(.plain)
                    .accessibilityIdentifier("vault.notes.item.\(note.id)")
                    .accessibilityAddTraits(selection.contains(note.id) ? .isSelected : [])
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !selecting {
                            // A destructive swipe role removes the row optimistically,
                            // before our confirmation. Keep it present until confirmed.
                            Button(L("vault2_to_trash"), systemImage: "trash") { pendingDelete = [note.id] }
                                .tint(.red)
                        }
                    }
                    .contextMenu {
                        Button(L("vault2_pin"), systemImage: "pin") { changePin(note) }
                        VaultMoveMenu(scope: .notes, ids: [note.id])
                        Button(L("vault2_to_trash"), systemImage: "trash", role: .destructive) {
                            pendingDelete = [note.id]
                        }
                    }
                }
            }
            .navigationTitle(L("vault2_notes"))
            .searchable(text: $query, prompt: L("vault2_search"))
            .onChange(of: query) { _, _ in selection = []; vault.touch() }
            .onChange(of: folder) { _, _ in selection = [] }
            .toolbar {
                VaultCloseToolbarItem()
                VaultSelectionToolbarItem(scope: "notes", isEmpty: notes.isEmpty, selecting: $selecting, selection: $selection)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("vault2_new_note"), systemImage: "square.and.pencil") {
                        var note = VaultNote(nowMs: vault.nowMs); note.folderID = folder
                        perform {
                            try vault.saveNote(note, expectedRevision: nil)
                            editor = vault.workspace.notes.first { $0.id == note.id }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        Text(verbatim: LP("grid_selected", selection.count))
                        Spacer()
                        Button(L("vault2_to_trash"), systemImage: "trash", role: .destructive) { pendingDelete = selection }
                            .labelStyle(.iconOnly).frame(minWidth: 48, minHeight: 48)
                            .accessibilityIdentifier("vault.notes.trash")
                    }.padding(.horizontal).background(.regularMaterial).disabled(selection.isEmpty)
                }
            }
            .vaultTrashConfirmation($pendingDelete) { ids in
                perform {
                    try vault.workspaceTransaction { try $0.trash(ids, scope: .notes, nowMs: vault.nowMs) }
                    selection.subtract(ids)
                    if selection.isEmpty { selecting = false }
                }
            }
            .sheet(item: $editor) { VaultNoteEditor(initial: $0) }
            .vaultWorkspaceError($error)
        }
    }
    private func changePin(_ note: VaultNote) {
        var value = note; value.pinned.toggle()
        perform { try vault.saveNote(value, expectedRevision: note.revision) }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = VaultWorkspaceMessages.error(error) } }
}

struct VaultNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    @State private var draft: VaultNote
    @State private var savedRevision: UInt64
    @State private var discard = false
    @State private var editorLease: VaultSessionLease?
    @State private var saved = true
    @State private var error: String?
    @State private var attachments = false
    @State private var picking = false
    @State private var busy = false
    @State private var preview: VaultDocument?

    init(initial: VaultNote) {
        _draft = State(initialValue: initial)
        _savedRevision = State(initialValue: initial.revision)
        _editorLease = State(initialValue: try? VaultStore.shared.requireLease())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L("vault2_title"), text: field(\.title), axis: .vertical)
                        .font(.title2.bold()).autocorrectionDisabled()
                        .accessibilityIdentifier("vault.note.title")
                    Toggle(L("vault2_pin"), isOn: field(\.pinned))
                }
                Section {
                    ForEach(draft.blocks) { block in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if block.style == .checklist {
                                    Button {
                                        editBlock(block.id) { $0.checked.toggle() }
                                    } label: { Image(systemName: block.checked ? "checkmark.circle.fill" : "circle").frame(width: 48, height: 48) }
                                    .accessibilityLabel(L("vault2_check"))
                                }
                                TextField(L("vault2_text"), text: blockText(block.id), axis: .vertical)
                                    .font(block.style == .heading ? .title3.bold() : .body.weight(block.bold ? .bold : .regular))
                                    .strikethrough(block.checked && block.style == .checklist)
                                    .autocorrectionDisabled()
                                Menu {
                                    ForEach(VaultNoteStyle.allCases, id: \.self) { style in
                                        Button(VaultWorkspaceMessages.name(style)) { editBlock(block.id) { $0.style = style } }
                                    }
                                    Button(L("vault2_bold")) { editBlock(block.id) { $0.bold.toggle() } }
                                    Button(L("vault2_remove_block"), role: .destructive) {
                                        change { $0.blocks.removeAll { $0.id == block.id } }
                                    }
                                } label: { Image(systemName: "textformat").frame(width: 48, height: 48) }
                                .accessibilityLabel(L("vault2_format"))
                            }
                        }
                    }
                    .onMove { offsets, destination in change { $0.blocks.move(fromOffsets: offsets, toOffset: destination) } }
                    Button(L("vault2_add_block"), systemImage: "plus") { change { $0.blocks.append(VaultNoteBlock()) } }
                }
                Section(L("vault2_attachments")) {
                    ForEach(draft.attachmentIDs, id: \.self) { id in
                        if let file = vault.workspace.files.first(where: { $0.id == id && $0.trashedMs == nil }) {
                            HStack {
                                Button { preview = file } label: { Label(file.name, systemImage: "paperclip") }
                                Spacer()
                                Button(L("vault2_detach"), systemImage: "minus.circle", role: .destructive) {
                                    change { $0.attachmentIDs.removeAll { $0 == id } }
                                }.labelStyle(.iconOnly).frame(minWidth: 48, minHeight: 48)
                            }
                        }
                    }
                    Button(L("vault2_attach_existing"), systemImage: "paperclip") { attachments = true }
                    Button(L("vault2_import"), systemImage: "square.and.arrow.down") { picking = true }
                }
                if !saved {
                    Section {
                        Text(L("vault2_not_saved")).foregroundStyle(.red)
                        Button(L("vault2_retry")) { persist() }
                        Button(L("vault2_save_as_new")) { saveAsNew() }
                        Button(L("vault2_discard"), role: .destructive) { discard = true }
                    }
                }
            }
            .navigationTitle(L("vault2_notes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("done")) { if saved { dismiss() } else { persist(); if saved { dismiss() } } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Label(L(saved ? "vault2_saved" : "vault2_not_saved"), systemImage: saved ? "checkmark.shield" : "exclamationmark.triangle")
                        .font(.caption).accessibilityIdentifier("vault.note.save-status")
                }
            }
            .confirmationDialog(L("vault2_discard"), isPresented: $discard, titleVisibility: .visible) {
                Button(L("vault2_discard"), role: .destructive) { draft = VaultNote(nowMs: 0); dismiss() }
                Button(L("cancel"), role: .cancel) {}
            } message: { Text(L("vault2_discard_warning")) }
            .interactiveDismissDisabled(!saved || busy)
            .disabled(busy)
            .overlay { if busy { ProgressView() } }
            .sheet(isPresented: $attachments) {
                NavigationStack {
                    List(vault.workspace.visibleFiles()) { file in
                        Button {
                            if !draft.attachmentIDs.contains(file.id) { change { $0.attachmentIDs.append(file.id) } }
                            attachments = false
                        } label: { Label(file.name, systemImage: draft.attachmentIDs.contains(file.id) ? "checkmark" : "doc") }
                    }.navigationTitle(L("vault2_attachments"))
                    .toolbar { Button(L("cancel")) { attachments = false } }
                }
            }
            .sheet(item: $preview) { VaultDocumentPreview(document: $0) }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task {
                        busy = true; defer { busy = false }
                        let report = await vault.importDocuments(urls)
                        guard vault.phase == .unlocked else { return }
                        change { $0.attachmentIDs.append(contentsOf: report.imported) }
                        if report.failed > 0 { error = L("vault2_import_failed", report.imported.count, report.failed) }
                    }
                case .failure: error = L("vault2_operation_failed")
                }
            }
            .vaultWorkspaceError($error)
            .onChange(of: vault.phase) { _, value in
                if value != .unlocked { draft = VaultNote(nowMs: 0); preview = nil; attachments = false; dismiss() }
            }
        }
    }
    private func field<T>(_ path: WritableKeyPath<VaultNote, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: path] }, set: { value in change { $0[keyPath: path] = value } })
    }
    private func blockText(_ id: String) -> Binding<String> {
        Binding(get: { draft.blocks.first { $0.id == id }?.text ?? "" }, set: { text in editBlock(id) { $0.text = text } })
    }
    private func editBlock(_ id: String, _ action: (inout VaultNoteBlock) -> Void) {
        change { value in if let i = value.blocks.firstIndex(where: { $0.id == id }) { action(&value.blocks[i]) } }
    }
    private func change(_ action: (inout VaultNote) -> Void) { action(&draft); saved = false; persist() }
    private func saveAsNew() {
        do {
            guard let editorLease, vault.accepts(editorLease) else { throw CancellationError() }
            var copy = VaultNote(nowMs: vault.nowMs)
            copy.title = draft.title; copy.blocks = draft.blocks; copy.attachmentIDs = draft.attachmentIDs
            copy.folderID = draft.folderID; copy.pinned = draft.pinned
            try vault.saveNote(copy, expectedRevision: nil)
            guard let value = vault.workspace.notes.first(where: { $0.id == copy.id }) else { throw VaultWorkspaceError.missingItem }
            draft = value; savedRevision = value.revision; saved = true; error = nil
        } catch { saved = false; self.error = VaultWorkspaceMessages.error(error) }
    }
    private func persist() {
        do {
            guard let editorLease, vault.accepts(editorLease) else { throw CancellationError() }
            try vault.saveNote(draft, expectedRevision: savedRevision)
            guard let value = vault.workspace.notes.first(where: { $0.id == draft.id }) else { throw VaultWorkspaceError.missingItem }
            draft = value; savedRevision = value.revision; saved = true
        } catch { saved = false; self.error = VaultWorkspaceMessages.error(error) }
    }
}

struct VaultFilesView: View {
    @State private var vault = VaultStore.shared
    @State private var query = ""
    @State private var folder: String?
    @State private var sort = VaultWorkspaceSort.modified
    @State private var selection: Set<String> = []
    @State private var selecting = false
    @State private var pendingDelete: Set<String>?
    @State private var picking = false
    @State private var scanning = false
    @State private var recording = false
    @State private var preview: VaultDocument?
    @State private var rename: VaultDocument?
    @State private var name = ""
    @State private var error: String?
    @State private var busy = false
    @State private var sharing: VaultShare?
    private var files: [VaultDocument] { vault.workspace.visibleFiles(query: query, folderID: folder, sort: sort) }

    var body: some View {
        NavigationStack {
            List {
                VaultWorkspaceFolderBar(scope: .files, folder: $folder)
                if files.isEmpty { Text(L("vault2_empty_files")).foregroundStyle(.secondary) }
                ForEach(files) { file in
                    Button {
                        if selecting {
                            if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
                        } else { preview = file }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selecting ? (selection.contains(file.id) ? "checkmark.circle.fill" : "circle") : VaultWorkspaceMessages.symbol(file))
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: file.name).foregroundStyle(.primary)
                                Text(verbatim: SizeText.bytes(file.byteCount) + " · " + VaultWorkspaceMessages.name(file.origin))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            .contentShape(.rect)
                    }.buttonStyle(.plain)
                    .accessibilityIdentifier("vault.files.item.\(file.id)")
                    .accessibilityAddTraits(selection.contains(file.id) ? .isSelected : [])
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !selecting {
                            Button(L("vault2_to_trash"), systemImage: "trash") { pendingDelete = [file.id] }
                                .tint(.red)
                        }
                    }
                    .contextMenu {
                        Button(L("vault2_rename"), systemImage: "pencil") { name = file.name; rename = file }
                        VaultMoveMenu(scope: .files, ids: [file.id])
                        Button(L("share"), systemImage: "square.and.arrow.up") { share([file.id]) }
                        if file.origin == .copied, file.sourceBookmark != nil {
                            Button(L("vault2_remove_original"), systemImage: "doc.badge.minus", role: .destructive) {
                                Task { do { try await vault.removeFileOriginal(file.id) } catch is CancellationError {} catch { self.error = VaultWorkspaceMessages.error(error) } }
                            }
                        }
                        Button(L("vault2_to_trash"), systemImage: "trash", role: .destructive) { pendingDelete = [file.id] }
                    }
                }
            }
            .navigationTitle(L("vault2_files"))
            .searchable(text: $query, prompt: L("vault2_search"))
            .onChange(of: query) { _, _ in selection = []; vault.touch() }
            .onChange(of: folder) { _, _ in selection = [] }
            .toolbar {
                VaultCloseToolbarItem()
                VaultSelectionToolbarItem(scope: "files", isEmpty: files.isEmpty, selecting: $selecting, selection: $selection)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(L("vault_sort"), selection: $sort) {
                            ForEach(VaultWorkspaceSort.allCases, id: \.self) { Text(VaultWorkspaceMessages.name($0)).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .accessibilityLabel(L("vault_sort"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(L("vault2_import"), systemImage: "square.and.arrow.down") { picking = true }
                        Button(L("vault2_scan"), systemImage: "doc.viewfinder") { scanning = true }
                        Button(L("vault2_record"), systemImage: "mic") { recording = true }
                    } label: { Image(systemName: "plus") }.accessibilityLabel(L("vault_add"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        Text(verbatim: "\(selection.count)")
                        Spacer()
                        VaultMoveMenu(scope: .files, ids: selection)
                        Button(L("share"), systemImage: "square.and.arrow.up") { share(selection) }
                        Button(L("vault2_to_trash"), systemImage: "trash", role: .destructive) { pendingDelete = selection }
                            .accessibilityIdentifier("vault.files.trash")
                    }.labelStyle(.iconOnly).padding().background(.regularMaterial).disabled(selection.isEmpty)
                }
            }
            .vaultTrashConfirmation($pendingDelete) { trash($0) }
            .disabled(busy)
            .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: .rect(cornerRadius: 16)) } }
            .sheet(item: $preview) { VaultDocumentPreview(document: $0) }
            .sheet(item: $sharing, onDismiss: { vault.touch() }) { value in
                ShareSheet(items: value.urls) { vault.removeTempFiles(value.urls) }
            }
            .fullScreenCover(isPresented: $scanning) {
                VaultDocumentScanner { result in
                    scanning = false
                    switch result {
                    case .success(let data):
                        Task {
                            busy = true; defer { busy = false }
                            do { try await vault.importData(data, name: VaultWorkspaceMessages.fileName("Scan", extension: "pdf"), type: .pdf, folderID: folder) }
                            catch { self.error = VaultWorkspaceMessages.error(error) }
                        }
                    case .failure(let value):
                        if !(value is CancellationError) { error = VaultWorkspaceMessages.error(value) }
                    }
                }
            }
            .sheet(isPresented: $recording) { VaultVoiceRecorderView(folderID: folder) }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task {
                        busy = true; defer { busy = false }
                        let report = await vault.importDocuments(urls, folderID: folder)
                        if report.failed > 0 { error = L("vault2_import_failed", report.imported.count, report.failed) }
                    }
                case .failure: error = L("vault2_operation_failed")
                }
            }
            .alert(L("vault2_rename"), isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
                TextField(L("vault2_name"), text: $name)
                Button(L("save")) {
                    if let file = rename {
                        do { try vault.workspaceTransaction { try $0.renameFile(file.id, name: name, nowMs: vault.nowMs) } }
                        catch { self.error = VaultWorkspaceMessages.error(error) }
                    }; rename = nil
                }
                Button(L("cancel"), role: .cancel) { rename = nil }
            }
            .vaultWorkspaceError($error)
        }
    }
    private func trash(_ ids: Set<String>) {
        do {
            try vault.workspaceTransaction { try $0.trash(ids, scope: .files, nowMs: vault.nowMs) }
            selection.subtract(ids)
            if selection.isEmpty { selecting = false }
        }
        catch { self.error = VaultWorkspaceMessages.error(error) }
    }
    private func share(_ ids: Set<String>) {
        Task {
            busy = true; defer { busy = false }
            do { sharing = VaultShare(urls: try await vault.shareDocuments(ids)) }
            catch is CancellationError {} catch { self.error = VaultWorkspaceMessages.error(error) }
        }
    }
}

struct VaultWorkspaceFolderBar: View {
    let scope: VaultFolderScope
    @Binding var folder: String?
    @Environment(AppModel.self) private var app
    @State private var vault = VaultStore.shared
    @State private var creating = false
    @State private var adPrompt = false
    @State private var watching = false
    @State private var renaming: VaultWorkspaceFolder?
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                Button(L("vault_all")) { folder = nil }
                ForEach(vault.workspace.folders.filter { $0.scope == scope }) { value in
                    Button { folder = value.id } label: {
                        Label(value.name, systemImage: folder == value.id ? "folder.fill" : "folder")
                    }
                    .contextMenu {
                        Button(L("vault2_rename")) { name = value.name; renaming = value }
                        Button(L("vault_delete_folder"), role: .destructive) {
                            do { try vault.workspaceTransaction { $0.removeFolder(value.id) }; if folder == value.id { folder = nil } }
                            catch { self.error = VaultWorkspaceMessages.error(error) }
                        }
                    }
                }
                Button(L("vault_new_folder"), systemImage: "folder.badge.plus") { startNewFolder() }
                    .disabled(watching)
            }.buttonStyle(.bordered).frame(minHeight: 48)
        }.scrollIndicators(.hidden)
        // Gratis: je neuem Ordner ein kurzes Werbevideo (E19); mit Pro ohne.
        .confirmationDialog(L("vault_new_folder"), isPresented: $adPrompt, titleVisibility: .visible) {
            Button(L("vault_ad_folder_watch")) { Task { await watchAd() } }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(key: "vault_ad_folder_text")
        }
        .alert(L("vault_new_folder"), isPresented: $creating) {
            TextField(L("vault2_name"), text: $name)
            Button(L("save")) {
                do {
                    var created: String?
                    try vault.workspaceTransaction { created = try $0.createFolder(name: name, scope: scope, nowMs: vault.nowMs).id }
                    folder = created
                    VaultFolderGate.folderCreated(app)
                }
                catch { self.error = VaultWorkspaceMessages.error(error) }
            }
            Button(L("cancel"), role: .cancel) {}
        }
        .alert(L("vault2_rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("vault2_name"), text: $name)
            Button(L("save")) {
                if let value = renaming {
                    do { try vault.workspaceTransaction { try $0.renameFolder(value.id, name: name) } }
                    catch { self.error = VaultWorkspaceMessages.error(error) }
                }; renaming = nil
            }
            Button(L("cancel"), role: .cancel) { renaming = nil }
        }
        .vaultWorkspaceError($error)
    }

    private func startNewFolder() {
        switch VaultFolderGate.access(app) {
        case .free:
            name = ""
            creating = true
        case .watchAd:
            AdsService.shared.preloadRewarded(app: app)
            adPrompt = true
        case .unavailable:
            error = L("vault_ad_folder_unavailable")
        }
    }

    private func watchAd() async {
        watching = true
        defer { watching = false }
        switch await VaultFolderGate.watchAd(app) {
        case .earned:
            name = ""
            creating = true
        case .dismissed:
            error = L("vault_ad_folder_dismissed")
        case .unavailable:
            error = L("vault_ad_folder_unavailable")
        }
    }
}

struct VaultMoveMenu: View {
    let scope: VaultFolderScope
    let ids: Set<String>
    @State private var vault = VaultStore.shared
    @State private var error: String?
    var body: some View {
        Menu {
            Button(L("vault2_without_folder")) { move(nil) }
            ForEach(vault.workspace.folders.filter { $0.scope == scope }) { value in
                Button(value.name) { move(value.id) }
            }
        } label: { Label(L("vault_move"), systemImage: "folder") }
        .disabled(ids.isEmpty).vaultWorkspaceError($error)
    }
    private func move(_ folder: String?) {
        do { try vault.workspaceTransaction { try $0.move(ids, scope: scope, folderID: folder, nowMs: vault.nowMs) } }
        catch { self.error = VaultWorkspaceMessages.error(error) }
    }
}

@MainActor enum VaultWorkspaceMessages {
    static func error(_ value: any Error) -> String {
        if let value = value as? VaultWorkspaceError {
            switch value {
            case .attachmentInUse: return L("vault2_attachment_in_use")
            case .conflict: return L("vault2_conflict")
            case .invalidName, .duplicateName: return L("vault_folder_invalid")
            default: break
            }
        }
        return L("vault2_operation_failed")
    }
    static func name(_ style: VaultNoteStyle) -> String {
        switch style {
        case .paragraph: L("vault2_paragraph")
        case .heading: L("vault2_heading")
        case .bullet: L("vault2_bullet")
        case .checklist: L("vault2_checklist")
        }
    }

    static func name(_ origin: VaultFileOrigin) -> String {
        switch origin {
        case .copied: L("vault2_origin_copied")
        case .sourceRemoved: L("vault2_origin_sourceRemoved")
        case .createdInsideVault: L("vault2_origin_createdInsideVault")
        case .restoredFromBackup: L("vault2_origin_restoredFromBackup")
        }
    }

    static func name(_ sort: VaultWorkspaceSort) -> String {
        switch sort {
        case .modified: L("vault2_sort_modified")
        case .name: L("vault2_sort_name")
        case .size: L("vault2_sort_size")
        }
    }

    /// Lesbarer, eindeutiger Name für im Tresor erzeugte Dateien (z. B. „Scan 2026-10-11 14.03.27.pdf“).
    static func fileName(_ prefix: String, extension ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(f.string(from: Date())).\(ext)"
    }

    static func symbol(_ file: VaultDocument) -> String {
        let type = UTType(file.typeIdentifier) ?? .data
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "film" }
        return "doc"
    }
}

private struct VaultWorkspaceErrorModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert(L("vault_title"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(L("ok"), role: .cancel) { message = nil }
        } message: { Text(verbatim: message ?? "") }
    }
}
extension View {
    func vaultWorkspaceError(_ message: Binding<String?>) -> some View { modifier(VaultWorkspaceErrorModifier(message: message)) }
}

/// Jede Berührung irgendwo in der App – auch in Blättern, Vorschauen und im Teilen-Fenster – verlängert die
/// Tresor-Sitzung (Inaktivitätssperre). Blockiert und verzögert keine andere Geste.
struct VaultActivityMonitor: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView {
        private var recognizer: Recognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            let r = Recognizer(target: nil, action: nil)
            r.cancelsTouchesInView = false
            r.delaysTouchesBegan = false
            r.delaysTouchesEnded = false
            r.delegate = r
            window.addGestureRecognizer(r)
            recognizer = r
        }

        func detach() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
        }
    }

    final class Recognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            VaultStore.shared.touch()
            state = .failed
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
