import Photos
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

/// Auslagern: Fotos und Videos in einen selbst gewählten Ordner kopieren (USB-Stick, Festplatte, Dateien-App) und
/// jede Kopie Byte für Byte prüfen. Ablauf in Schritten: Was → Wohin → Optionen → Start. Nichts wird gelöscht.
struct ArchiveView: View {
    @Environment(AppModel.self) private var app
    let initialIDs: [String]
    @State private var ids: [String] = []
    @State private var target: URL?
    @State private var targetFacts: ArchiveTargetFacts?
    @State private var pickingFolder = false
    @State private var pickingMedia = false
    @State private var options = ArchiveOptions()
    @State private var journal: ArchiveJournal?
    @State private var requestedCount = 0
    @State private var lastJournal: ArchiveJournal?
    @State private var running = false
    @State private var loaded = false

    var body: some View {
        form
            .appPage().readableContent()
            .navigationTitle(L("archive_title"))
            .safeAreaInset(edge: .bottom) { startBar }
            .overlay { if running { LoadingState(message: L("archive_running")).background(.ultraThinMaterial) } }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { choose(url) }
            }
            .sheet(isPresented: $pickingMedia) {
                StudioMediaPicker(allowsVideos: true, limit: 500, initial: Set(ids)) { ids = $0 }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                ids = initialIDs
                lastJournal = app.kv?.get(StoreKeys.archiveJournal)
            }
    }

    private var form: some View {
        Form {
            introSection
            mediaSection
            targetSection
            optionsSection
            if let journal {
                resultSection(journal)
            } else if let lastJournal {
                lastRunSection(lastJournal)
            }
        }
    }

    // MARK: Erklärung

    private var introSection: some View {
        Section {
            Label {
                Text(key: "archive_intro_title").font(AppTypography.headline)
            } icon: {
                Image(systemName: "externaldrive.badge.checkmark").foregroundStyle(AppColors.accent)
            }
            Text(key: "archive_intro").font(AppTypography.subheadline).fixedSize(horizontal: false, vertical: true)
        } footer: {
            Text(key: "archive_meaning")
        }
    }

    // MARK: Schritt 1 – Was

    private var mediaSection: some View {
        Section {
            Button { pickingMedia = true } label: {
                Label(L(ids.isEmpty ? "archive_pick_button" : "archive_pick_change"), systemImage: "photo.on.rectangle")
                    .frame(minHeight: AppSpacing.minTouch)
            }
            StepStatusRow(done: !ids.isEmpty, text: ids.isEmpty ? L("archive_none_selected") : LP("tools_selected", ids.count))
        } header: {
            Text(verbatim: L("archive_step_header", 1, L("archive_pick"))).textCase(nil)
        }
    }

    // MARK: Schritt 2 – Wohin

    private var targetSection: some View {
        Section {
            Button { pickingFolder = true } label: {
                Label(L(target == nil ? "archive_choose" : "archive_choose_other"), systemImage: "folder")
                    .frame(minHeight: AppSpacing.minTouch)
            }
            StepStatusRow(done: target != nil, text: target?.lastPathComponent ?? L("archive_target_none"))
            if let facts = targetFacts {
                Text(verbatim: kindText(facts.kind))
                    .font(AppTypography.footnote)
                    .foregroundStyle(facts.kind == .removable ? AppColors.textSecondary : AppColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: facts.freeBytes.map { L("archive_free", SizeText.bytes($0)) } ?? L("archive_free_unknown"))
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }
        } header: {
            Text(verbatim: L("archive_step_header", 2, L("archive_where"))).textCase(nil)
        } footer: {
            Text(key: "archive_target_note")
        }
    }

    private func kindText(_ kind: TargetKind) -> String {
        switch kind {
        case .removable: L("archive_kind_removable")
        case .sameDevice: L("archive_kind_device")
        case .provider: L("archive_kind_provider")
        }
    }

    // MARK: Optionen

    private var optionsSection: some View {
        Section {
            ToggleRow(title: L("archive_by_month"), subtitle: L("archive_by_month_note"), isOn: $options.byMonth)
            ToggleRow(title: L("archive_write_list"), subtitle: L("archive_write_list_note"), isOn: $options.writeList)
        } header: {
            Text(key: "archive_options")
        }
    }

    // MARK: Ergebnis

    private func resultSection(_ journal: ArchiveJournal) -> some View {
        let summary = journal.summary
        // Medien, die beim Kopieren nicht mehr gefunden wurden, haben keinen Eintrag – sie zählen als „nicht kopiert“.
        let notCopied = summary.notDone + max(0, requestedCount - journal.entries.count)
        let failed = journal.entries.filter { $0.state == .failed }
        return Section {
            Text(verbatim: LP("archive_part_verified", summary.verified))
            if summary.alreadyThere > 0 { Text(verbatim: LP("archive_part_already", summary.alreadyThere)) }
            if summary.failed > 0 { Text(verbatim: LP("archive_part_failed", summary.failed)) }
            if notCopied > 0 { Text(verbatim: LP("archive_part_notdone", notCopied)) }
            if summary.verifiedBytes > 0 { Text(verbatim: L("archive_verified_bytes", SizeText.bytes(summary.verifiedBytes))) }
            if let listName = journal.listName { Text(verbatim: L("archive_list_saved", listName)) }
            ForEach(Array(failed.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.name).font(AppTypography.subheadline)
                    Text(verbatim: reasonText(entry.reason)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        } header: {
            Text(key: "archive_result_title")
        } footer: {
            Text(key: "archive_step_originals")
        }
    }

    private func lastRunSection(_ journal: ArchiveJournal) -> some View {
        let millis = journal.finishedAt ?? journal.startedAt
        let date = DateText.abbreviated(Date(timeIntervalSince1970: Double(millis) / 1000))
        let summary = journal.summary
        return Section {
            Text(verbatim: L("archive_last_result", date, summary.verified + summary.alreadyThere, summary.total))
                .font(AppTypography.footnote)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func reasonText(_ reason: EntryReason?) -> String {
        guard let reason else { return L("archive_reason_write") }
        return switch reason {
        case .readFailed: L("archive_reason_read")
        case .writeFailed: L("archive_reason_write")
        case .mismatch: L("archive_reason_mismatch")
        case .cancelled: L("archive_reason_cancelled")
        case .interrupted: L("archive_reason_interrupted")
        case .noSpace: L("archive_reason_space")
        }
    }

    // MARK: Start

    /// Start erst, wenn Was und Wohin gewählt sind – sonst steht der Grund direkt über dem Knopf.
    private var startBar: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(verbatim: startHint)
                .font(AppTypography.footnote)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            PrimaryButton(title: L("archive_start"), symbol: "externaldrive.badge.checkmark") {
                Task { await run() }
            }
            .disabled(target == nil || ids.isEmpty || running)
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.vertical, AppSpacing.xs)
        .background(.bar)
    }

    private var startHint: String {
        guard let target else { return ids.isEmpty ? L("archive_need_both") : L("archive_need_target") }
        if ids.isEmpty { return L("archive_need_media") }
        return LP("archive_step_copy", ids.count, ids.count, target.lastPathComponent)
    }

    // MARK: Abläufe

    private func choose(_ url: URL) {
        target = url
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
                                         .volumeIsLocalKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        let values = try? url.resourceValues(forKeys: keys)
        let facts = VolumeFacts(isUbiquitous: values?.isUbiquitousItem, volumeIsInternal: values?.volumeIsInternal,
                                volumeIsRemovable: values?.volumeIsRemovable, volumeIsEjectable: values?.volumeIsEjectable,
                                volumeIsLocal: values?.volumeIsLocal)
        let free = values?.volumeAvailableCapacityForImportantUsage ?? values?.volumeAvailableCapacity.map { Int64($0) }
        targetFacts = ArchiveTargetFacts(kind: ArchiveTargets.classify(facts), freeBytes: free)
    }

    private func run() async {
        guard let target, !ids.isEmpty else { return }
        running = true
        defer { running = false }
        let selected = ids
        let scoped = target.startAccessingSecurityScopedResource()
        defer { if scoped { target.stopAccessingSecurityScopedResource() } }
        var result = await ArchiveService.copy(app: app, ids: selected, target: target, options: options)
        if options.writeList && !result.verified.isEmpty {
            result.listName = writeChecklist(result, to: target)
        }
        requestedCount = selected.count
        journal = result
        lastJournal = result
        try? app.kv?.set(StoreKeys.archiveJournal, result)
    }

    /// Prüfliste (CSV) im Zielordner: je geprüfter Kopie Ordner, Name, Aufnahmedatum, Bytes, SHA-256 sowie Alben,
    /// Schlagwörter und Notiz. Nur gemessene Werte; Unbekanntes bleibt leer.
    private func writeChecklist(_ journal: ArchiveJournal, to folder: URL) -> String? {
        let header = ["archive_col_folder", "archive_col_name", "archive_col_taken", "archive_col_bytes", "archive_col_sha",
                      "archive_col_albums", "archive_col_tags", "archive_col_note"].map { L($0) }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let rows = journal.verified.map { entry -> ArchiveList.Row in
            let id = entry.sourceId
            let fileName = entry.targetUri?.split(separator: "/").last.map(String.init) ?? entry.name
            return ArchiveList.Row(folder: entry.folder.joined(separator: "/"), name: fileName,
                                   taken: app.asset(id)?.creationDate.map { dateFormatter.string(from: $0) } ?? "",
                                   bytes: entry.bytes.map { String($0) } ?? "", sha256: entry.sha256 ?? "",
                                   albums: albumTitles(id).joined(separator: "; "),
                                   tags: app.organize.tags(of: id).joined(separator: "; "),
                                   note: app.organize.note(of: id) ?? "")
        }
        let csv = ArchiveList.render(header: header, rows: rows)
        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let wanted = ArchivePlan.safeName(L("archive_list_file", stampFormatter.string(from: Date())), fallback: AppConfig.brandName + ".csv")
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = ArchivePlan.uniqueName(taken: existing, wanted: wanted)
        do {
            try Data(csv.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    private func albumTitles(_ id: String) -> [String] {
        guard let asset = PhotoLibraryService.phAsset(id) else { return [] }
        let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        return (0..<collections.count).compactMap { collections.object(at: $0).localizedTitle }
    }
}

/// Eingeordneter Zielordner: Art des Speichers und gemessener freier Platz (`nil` = unbekannt, nie 0).
private struct ArchiveTargetFacts: Equatable {
    let kind: TargetKind
    let freeBytes: Int64?
}

/// Zustand eines Schritts: erledigt (Häkchen) oder offen (Kreis) mit kurzem Text.
private struct StepStatusRow: View {
    let done: Bool
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text).foregroundStyle(done ? AppColors.textPrimary : AppColors.textSecondary)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? AppColors.success : AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
