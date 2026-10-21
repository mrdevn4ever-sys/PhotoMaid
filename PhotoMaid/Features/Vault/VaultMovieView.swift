import AVFoundation
import PhotoMaidCore
import SwiftUI

/// Videos im Tresor zusammenfügen (Nutzerwunsch 21.10.2026): ausgewählte Tresor-Videos in Reihenfolge, optional
/// Schwarzblende, Format und Qualität – derselbe Export wie „Video zusammenfügen“ im Studio. Das Ergebnis ist ein neues
/// Video nur im Tresor; die Quellen bleiben unverändert. Tempo und Schnitt je Video: „Bearbeiten“ im Tresor-Betrachter.
struct VaultMovieView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var vault = VaultStore.shared
    @State private var project: VideoProject
    @State private var fadeThroughBlack = false
    @State private var editMode: EditMode = .inactive
    @State private var working = false
    @State private var failure: String?
    /// Tresor-Sitzung beim Öffnen: Quellen und Ergebnis nur in genau dieser Sitzung.
    @State private var lease = VaultStore.shared.editSession()

    init(itemIDs: [String]) {
        let items = VaultStore.shared.index.items
        let clips = itemIDs.compactMap { id -> VideoClip? in
            guard let item = items.first(where: { $0.id == id }), item.isVideo else { return nil }
            return MoviePlan.videoClip(id: UUID().uuidString, mediaId: id, durationMs: Int64(item.duration * 1000))
        }
        _project = State(initialValue: VideoProject(id: UUID().uuidString, clips: clips))
    }

    var body: some View {
        NavigationStack {
            List {
                clipsSection
                if project.clips.count > 1 { transitionSection }
                formatSection
            }
            .environment(\.editMode, $editMode)
            .appPage()
            .navigationTitle(L("movie_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() }.disabled(working) }
                if project.clips.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L(editMode == .active ? "done" : "movie_reorder")) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .overlay {
                if ExportCoordinator.shared.isBusy {
                    ExportProgressOverlay(coordinator: ExportCoordinator.shared)
                } else if working {
                    LoadingState(message: L("movie_running")).background(.ultraThinMaterial)
                }
            }
            .alert(L("vault_title"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button(L("ok")) { failure = nil }
            } message: {
                Text(verbatim: failure ?? "")
            }
        }
        .interactiveDismissDisabled(working)
        .onChange(of: vault.phase) { _, phase in
            // Tresor gesperrt: sofort schließen (entschlüsselte Quellen werden beim Sperren gelöscht).
            if phase != .unlocked { dismiss() }
        }
    }

    // MARK: Teile

    private var clipsSection: some View {
        Section {
            ForEach(project.clips, id: \.id) { clip in
                clipRow(clip)
            }
            .onMove { source, destination in
                var clips = project.clips
                clips.move(fromOffsets: source, toOffset: destination)
                project = project.withClips(clips)
                applyTransitions()
            }
            .onDelete { offsets in
                var clips = project.clips
                clips.remove(atOffsets: offsets)
                project = project.withClips(clips)
                applyTransitions()
                if project.clips.count < 2 { editMode = .inactive }
            }
        } header: {
            Text(key: "movie_tab_clips")
        } footer: {
            Text(key: "vault_edit_private_note")
        }
    }

    private func clipRow(_ clip: VideoClip) -> some View {
        let item = vault.index.items.first { $0.id == clip.mediaId }
        return HStack(spacing: AppSpacing.s) {
            ZStack {
                if let item, let thumb = vault.thumbnails[item.id] {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    AppColors.surfaceStroke
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
            .task { if let item { await vault.thumbnail(item) } }
            Text(verbatim: L("movie_clip_video", DateText.duration(Double(clip.outputDurationMs) / 1000)))
                .font(AppTypography.body)
            Spacer(minLength: 0)
        }
        .frame(minHeight: AppSpacing.minTouch)
    }

    private var transitionSection: some View {
        Section {
            ToggleRow(title: L("movie_fade_black"), subtitle: L("movie_transition_note"), isOn: Binding(get: { fadeThroughBlack }, set: {
                fadeThroughBlack = $0
                applyTransitions()
            }))
        } header: {
            Text(key: "movie_tab_transition")
        }
    }

    private var formatSection: some View {
        Section {
            Picker(L("movie_format"), selection: Binding(get: { project.aspect ?? 0 }, set: { value in
                project.aspect = value == 0 ? nil : value
            })) {
                Text(key: "movie_format_first").tag(Float(0))
                Text(key: "movie_aspect_916").tag(Float(9.0 / 16.0))
                Text(key: "movie_aspect_45").tag(Float(0.8))
                Text(key: "movie_aspect_square").tag(Float(1))
                Text(key: "movie_aspect_169").tag(Float(16.0 / 9.0))
            }
            Picker(L("movie_fit_label"), selection: $project.fill) {
                Text(key: "movie_fit_whole").tag(false)
                Text(key: "movie_fit_fill").tag(true)
            }
            .pickerStyle(.segmented)
            Picker(L("movie_quality"), selection: $project.profile) {
                Text(key: "movie_quality_high").tag(ExportProfile.high)
                Text(key: "movie_quality_balanced").tag(ExportProfile.balanced)
                Text(key: "movie_quality_small").tag(ExportProfile.small)
            }
        } header: {
            Text(key: "movie_tab_format")
        } footer: {
            Text(key: "movie_fit_note")
        }
    }

    private var saveBar: some View {
        VStack(spacing: AppSpacing.xs) {
            if let reason = blockedReason {
                Text(verbatim: reason).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            PrimaryButton(title: L("vault_merge_save"), symbol: "lock.fill") { Task { await save() } }
                .disabled(blockedReason != nil || working || ExportCoordinator.shared.isBusy)
                .accessibilityIdentifier("vault.merge.save")
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.vertical, AppSpacing.xs)
        .background(.bar)
    }

    private var blockedReason: String? {
        guard let problem = MoviePlan.problem(project) else { return nil }
        return switch problem {
        case .tooFew: L("movie_too_few")
        case .tooMany: L("movie_too_many")
        case .tooLong: L("movie_too_long")
        }
    }

    private func applyTransitions() {
        project.transitions = Array(repeating: fadeThroughBlack ? .fadeBlack : .none, count: max(0, project.clips.count - 1))
    }

    // MARK: Speichern

    /// Quellen in die Temp-Ablage der Sitzung entschlüsseln, exportieren, verschlüsselt ablegen; Klartext sofort weg.
    private func save() async {
        guard blockedReason == nil, let first = project.clips.first,
              let firstItem = vault.index.items.first(where: { $0.id == first.mediaId }) else { return }
        guard let lease else { failure = L("vault_error_generic"); return }
        working = true
        vault.beginEditWork()
        var temps: [URL] = []
        defer {
            vault.removeTempFiles(temps)
            vault.endEditWork()
            working = false
        }
        do {
            var assets: [String: AVAsset] = [:]
            var infos: [String: VideoInfo] = [:]
            for clip in project.clips where assets[clip.mediaId] == nil {
                guard let source = await vault.editVideoSource(clip.mediaId, lease: lease) else { throw EditSaveError.render }
                temps.append(source.url)
                let asset = AVURLAsset(url: source.url)
                guard let info = await VideoSource.info(asset) else { throw EditSaveError.render }
                assets[clip.mediaId] = asset
                infos[clip.mediaId] = info
            }
            // Clip-Längen aus den gelesenen Videos (die gespeicherte Dauer kann fehlen).
            let measured = project.withClips(project.clips.map { clip in
                guard let ms = infos[clip.mediaId]?.durationMs, ms > 0 else { return clip }
                return MoviePlan.videoClip(id: clip.id, mediaId: clip.mediaId, durationMs: ms)
            })
            let frame = MoviePlan.frame(measured, first: VSize(max(2, firstItem.pixelWidth), max(2, firstItem.pixelHeight)))
            let result = try await VaultEditSaver.saveMovie(project: measured, assets: assets, infos: infos, frame: frame,
                                                            basedOn: firstItem.id,
                                                            unlimited: app.capabilities.hasProToolsAccess, lease: lease)
            vault.lastEdit = result
            Haptics.success()
            dismiss()
        } catch {
            failure = VaultEditSaver.message(for: error)
        }
    }
}

/// Auswahl für „Zusammenfügen“ im Tresor (Reihenfolge wie im Raster).
struct VaultMergeRequest: Identifiable {
    let id = UUID()
    let ids: [String]
}
