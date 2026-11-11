import AVFoundation
import PhotoMaidCore
import SwiftUI

/// „Video verkleinern“ aus „Große Dateien“ (11/2026): neue, kleinere Datei über dieselbe Export-Pipeline wie der
/// Video-Editor (nie hochskalieren, nie verzerren). Das Original bleibt – außer der Nutzer wählt ausdrücklich
/// „Kopie speichern, Original in den Papierkorb“ (Systembestätigung, „Zuletzt gelöscht“). Die Ersparnis wird gemessen;
/// ist das Ergebnis nicht kleiner, wird KEINE Datei gespeichert. Keine Wisch-Entscheidung, kein automatisches Löschen.
struct VideoShrinkSheet: View {
    let asset: MediaAsset
    /// Gemessene Größe des Originals (`nil` = nicht gemessen, z. B. nur in iCloud).
    let originalBytes: Int64?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var av: AVAsset?
    @State private var info: VideoInfo?
    @State private var loadFailed = false
    @State private var profile = ExportProfile.balanced
    @State private var working = false
    @State private var result: Result?

    private enum Result: Equatable {
        case saved(bytes: Int64?, outcome: EditSaveOutcome)
        case notSmaller
        case failed(String)
    }

    private static let profiles: [ExportProfile] = [.balanced, .small]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AppSpacing.s) {
                        AssetThumbnail(assetID: asset.id, side: 56)
                        VStack(alignment: .leading) {
                            Text(verbatim: MediaInfoLine.describe(asset)).font(AppTypography.subheadline).lineLimit(2)
                            if let originalBytes {
                                Text(verbatim: SizeText.bytes(originalBytes)).font(AppTypography.headline).monospacedDigit()
                            }
                        }
                    }
                }
                if let result {
                    resultSection(result)
                } else if loadFailed {
                    Section { Text(key: "preview_failed").foregroundStyle(AppColors.textSecondary) }
                } else if info == nil {
                    Section { HStack { ProgressView(); Text(key: "ana2_stage_preparing").foregroundStyle(AppColors.textSecondary) } }
                } else {
                    optionsSection
                    actionsSection
                }
            }
            .navigationTitle(L("tools_resize"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L(result == nil ? "cancel" : "done")) { dismiss() }.disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
        }
        .task { await load() }
    }

    private var optionsSection: some View {
        Section {
            Picker(L("vid_profile"), selection: $profile) {
                ForEach(Self.profiles, id: \.self) { p in
                    Text(verbatim: label(p)).tag(p)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(key: "vid_estimate_hint")
                if info?.hdr == true { Text(key: "vid_hdr_hint_ios") }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button { Task { await run(.copy) } } label: {
                Label(L("edit_save_copy_action"), systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive) { Task { await run(.replace) } } label: {
                Label(L("edit_save_replace_action"), systemImage: "trash")
            }
        } footer: {
            Text(key: "edit_save_replace_text")
        }
        .disabled(working || !worthIt)
    }

    @ViewBuilder
    private func resultSection(_ r: Result) -> some View {
        Section {
            switch r {
            case .saved(let bytes, let outcome):
                if let originalBytes, let bytes {
                    Text(verbatim: L("tools_sizes", SizeText.bytes(originalBytes), SizeText.bytes(bytes)))
                        .font(AppTypography.headline).monospacedDigit()
                }
                Text(key: outcomeKey(outcome)).foregroundStyle(AppColors.textSecondary)
            case .notSmaller:
                Text(key: "wf_status_notmet").font(AppTypography.headline)
                Text(key: "tools_originals_kept").foregroundStyle(AppColors.textSecondary)
            case .failed(let message):
                Text(verbatim: message).foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func outcomeKey(_ o: EditSaveOutcome) -> String {
        switch o {
        case .replaced: "edit_done_replaced"
        case .replaceDeclined: "edit_done_declined"
        default: "edit_done_copy"
        }
    }

    /// „Ausgewogen (Full HD) · ca. 120 MB“.
    private func label(_ p: ExportProfile) -> String {
        let title = L(p == .small ? "vid_profile_small" : "vid_profile_balanced")
        guard let e = estimate(p) else { return title }
        return title + " · " + L("vid_estimate", SizeText.bytes(SizeEstimator.rounded(e)))
    }

    private func project(_ p: ExportProfile) -> VideoProject? {
        guard let info else { return nil }
        var project = VideoProject(id: UUID().uuidString,
                                   clips: [MoviePlan.videoClip(id: "c0", mediaId: asset.id, durationMs: info.durationMs)])
        project.profile = p
        return project
    }

    private func estimate(_ p: ExportProfile) -> Int64? {
        guard let info, let project = project(p) else { return nil }
        let layout = VideoPlan.layout(display: info.display, clip: project.clips[0], project: project)
        return VideoPlan.estimateBytes(project, layout: layout, fps: info.fps)
    }

    /// Nur anbieten, wenn die Schätzung unter dem gemessenen Original liegt (unbekannt: anbieten, das Ergebnis wird gemessen).
    private var worthIt: Bool {
        guard let originalBytes, let e = estimate(profile) else { return true }
        return e < originalBytes
    }

    private func load() async {
        guard av == nil else { return }
        guard let loaded = await VideoSource.asset(asset.id, allowNetwork: true),
              let i = await VideoSource.info(loaded), i.durationMs > VideoRules.minClipMs else { loadFailed = true; return }
        av = loaded
        info = i
        // Vorauswahl: die größte Stufe, die noch kleiner als das Original geschätzt wird.
        if let originalBytes, let e = estimate(.balanced), e >= originalBytes { profile = .small }
    }

    private func run(_ mode: SaveMode) async {
        guard !working, let av, let info, let project = project(profile) else { return }
        working = true
        defer { working = false }
        let name = PhotoLibraryService.originalFilename(asset.id)
        let base = (EditNames.copyName(original: name, suffix: L("edit_copy_suffix"), fileExtension: "x") as NSString)
            .deletingPathExtension
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = UncheckedBox(av)
        do {
            let url = try await ExportCoordinator.shared.run(title: L("vid_export_running")) { progress in
                try await VideoExportJob.renderEdit(asset: source.value, info: info, project: project, folder: folder,
                                                    baseName: base, progress: progress)
            }
            let bytes = VideoExportJob.fileSize(url)
            // Gemessen nicht kleiner als das Original → keine Datei speichern, Original unberührt.
            if let originalBytes, let bytes, bytes >= originalBytes { result = .notSmaller; return }
            let req = PhotoLibraryService.SaveRequest(
                fileURL: url, isVideo: true, creationDate: asset.creationDate, latitude: asset.latitude,
                longitude: asset.longitude, favorite: mode == .replace && asset.isFavorite, albumID: nil,
                filename: url.lastPathComponent)
            guard case .saved(let newID) = await app.library.save(req) else { result = .failed(L("edit_err_save")); return }
            let outcome = await EditSaver.finish(app: app, original: asset, newID: newID, mode: mode, video: true,
                                                 kind: .compress, bytes: bytes)
            Haptics.success()
            result = .saved(bytes: bytes, outcome: outcome)
        } catch is CancellationError {
            // Abgebrochen: nichts gespeichert, Blatt bleibt für einen neuen Versuch offen.
        } catch ExportCoordinator.Failure.busy {
            result = .failed(L("export_busy"))
        } catch {
            result = .failed(L("edit_err_save"))
        }
    }
}
