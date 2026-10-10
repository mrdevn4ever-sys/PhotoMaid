import AVFoundation
import Photos
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

/// „Video zusammenfügen“: Clips (Videos und Fotos) nacheinander, optional Schwarzblende, Format, Qualität, Musik.
/// Jede Einstellung erklärt sich selbst (Untertitel oder Fußnote). Speichern legt immer ein neues Video an.
struct MovieView: View {
    @Environment(AppModel.self) private var app
    let initialIDs: [String]
    @State private var project = VideoProject(id: UUID().uuidString, clips: [])
    @State private var picker = false
    @State private var importingMusic = false
    @State private var musicURL: URL?
    @State private var photoSeconds = 3
    @State private var kenBurns = true
    @State private var fadeThroughBlack = false
    @State private var editMode: EditMode = .inactive
    @State private var loadedInitial = false
    @State private var errorKey: String?

    var body: some View {
        content
            .appPage()
            .navigationTitle(L("movie_title"))
            .safeAreaInset(edge: .bottom) { saveBar }
            .overlay { if ExportCoordinator.shared.isBusy { ExportProgressOverlay(coordinator: ExportCoordinator.shared) } }
            .sheet(isPresented: $picker) {
                StudioMediaPicker(allowsVideos: true, limit: VideoRules.maxClips, initial: Set(project.clips.map(\.mediaId))) { ids in
                    merge(ids)
                }
            }
            .fileImporter(isPresented: $importingMusic, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                musicURL = url
                project.music = PhotoMaidCore.MusicTrack(uri: url.absoluteString, name: url.lastPathComponent)
            }
            .alert(L("error_title"), isPresented: Binding(get: { errorKey != nil }, set: { if !$0 { errorKey = nil } })) {
                Button(L("ok")) { errorKey = nil }
            } message: { Text(key: errorKey ?? "movie_failed") }
            .task {
                guard !loadedInitial else { return }
                loadedInitial = true
                if project.clips.isEmpty { merge(initialIDs) }
            }
    }

    private var content: some View {
        List {
            clipsSection
            if hasPhotos { photoSection }
            if project.clips.count > 1 { transitionSection }
            formatSection
            qualitySection
            musicSection
        }
        .environment(\.editMode, $editMode)
    }

    private var hasPhotos: Bool { project.clips.contains(where: \.isPhoto) }

    // MARK: Clips

    private var clipsSection: some View {
        Section {
            if project.clips.isEmpty {
                Text(key: "movie_too_few").foregroundStyle(AppColors.textSecondary)
            }
            ForEach(Array(project.clips.enumerated()), id: \.element.id) { index, clip in
                clipRow(index, clip)
            }
            .onMove { source, destination in moveClips(source, destination) }
            .onDelete { offsets in removeClips(offsets) }
            Button { picker = true } label: {
                Label(L(project.clips.isEmpty ? "movie_pick" : "movie_add"), systemImage: "plus")
                    .frame(minHeight: AppSpacing.minTouch)
            }
        } header: {
            clipsHeader
        } footer: {
            if !project.clips.isEmpty { Text(key: "movie_clips_note") }
        }
    }

    private var clipsHeader: some View {
        HStack {
            Text(key: "movie_tab_clips")
            Spacer(minLength: AppSpacing.xs)
            if project.clips.count > 1 {
                Button {
                    editMode = editMode == .active ? .inactive : .active
                } label: {
                    Text(verbatim: editMode == .active ? L("done") : L("movie_reorder"))
                        .font(AppTypography.subheadline.weight(.semibold))
                        .frame(minHeight: AppSpacing.minTouch)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
        }
        .textCase(nil)
    }

    private func clipRow(_ index: Int, _ clip: VideoClip) -> some View {
        HStack(spacing: AppSpacing.s) {
            AssetCell(assetID: clip.mediaId)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: AppRadii.small))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: L("movie_clip_n", index + 1, project.clips.count)).font(AppTypography.headline)
                Text(verbatim: clipDetail(clip)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppSpacing.xs)
            if editMode != .active { clipMenu(index) }
        }
        .frame(minHeight: AppSpacing.touch)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if index > 0 { Button(L("movie_move_earlier")) { move(index, -1) } }
            if index < project.clips.count - 1 { Button(L("movie_move_later")) { move(index, 1) } }
            Button(L("movie_remove_clip")) { removeClips(IndexSet(integer: index)) }
        }
    }

    /// Ein einziges Bedienelement je Zeile (44 pt): Verschieben und Entfernen stehen mit Text im Menü – kein
    /// versehentliches Löschen durch dicht beieinanderliegende Symbole.
    private func clipMenu(_ index: Int) -> some View {
        Menu {
            Button { move(index, -1) } label: { Label(L("movie_move_earlier"), systemImage: "arrow.up") }
                .disabled(index == 0)
            Button { move(index, 1) } label: { Label(L("movie_move_later"), systemImage: "arrow.down") }
                .disabled(index >= project.clips.count - 1)
            SwiftUI.Divider()
            Button(role: .destructive) { removeClips(IndexSet(integer: index)) } label: {
                Label(L("movie_remove_clip"), systemImage: "minus.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(AppColors.accent)
                .frame(width: AppSpacing.touch, height: AppSpacing.touch)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(verbatim: L("movie_clip_actions", index + 1)))
    }

    private func clipDetail(_ clip: VideoClip) -> String {
        if clip.isPhoto { return L("movie_clip_photo", L("slideshow_seconds", photoSeconds)) }
        return L("movie_clip_video", DateText.duration(Double(clip.outputDurationMs) / 1000))
    }

    // MARK: Fotos

    private var photoSection: some View {
        Section {
            Stepper(value: $photoSeconds, in: 1...10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key: "movie_photo_duration")
                    Text(verbatim: L("slideshow_seconds", photoSeconds))
                        .font(AppTypography.headline).monospacedDigit()
                        .foregroundStyle(AppColors.accent)
                }
            }
            .frame(minHeight: AppSpacing.minTouch)
            .onChange(of: photoSeconds) { _, seconds in setPhotoDuration(seconds) }
            ToggleRow(title: L("movie_kenburns"), subtitle: L("movie_kenburns_note"), isOn: Binding(get: { kenBurns }, set: { enabled in
                kenBurns = enabled
                setKenBurns(enabled)
            }))
        } header: {
            Text(key: "movie_photos_header")
        } footer: {
            Text(key: "movie_photo_duration_note")
        }
    }

    // MARK: Übergang

    private var transitionSection: some View {
        Section {
            ToggleRow(title: L("movie_fade_black"), subtitle: L("movie_transition_note"), isOn: Binding(get: { fadeThroughBlack }, set: { enabled in
                fadeThroughBlack = enabled
                applyTransitions()
            }))
        } header: {
            Text(key: "movie_tab_transition")
        }
    }

    // MARK: Format und Qualität

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
        } header: {
            Text(key: "movie_tab_format")
        } footer: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(key: "movie_format_note")
                Text(key: "movie_fit_note")
            }
        }
    }

    private var qualitySection: some View {
        Section {
            Picker(L("movie_quality"), selection: $project.profile) {
                Text(key: "movie_quality_high").tag(ExportProfile.high)
                Text(key: "movie_quality_balanced").tag(ExportProfile.balanced)
                Text(key: "movie_quality_small").tag(ExportProfile.small)
            }
        } footer: {
            Text(key: "movie_quality_note")
        }
    }

    // MARK: Musik

    private var musicSection: some View {
        Section {
            if let track = project.music {
                Label { Text(verbatim: track.name).lineLimit(2) } icon: { Image(systemName: "music.note") }
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(key: "movie_music_volume")
                    Slider(value: Binding(get: { Double(project.music?.volume ?? 0.8) }, set: { value in
                        project.music?.volume = Float(value)
                    }), in: 0...1) {
                        Text(key: "movie_music_volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
                    }
                }
                Button(role: .destructive) { project.music = nil; musicURL = nil } label: { Text(key: "movie_music_remove") }
                    .frame(minHeight: AppSpacing.minTouch)
            } else {
                Button { importingMusic = true } label: { Label(L("movie_music_pick"), systemImage: "music.note") }
                    .frame(minHeight: AppSpacing.minTouch)
            }
        } header: {
            Text(key: "movie_tab_music")
        } footer: {
            Text(key: "movie_music_note")
        }
    }

    // MARK: Speichern

    /// Hauptaktion fest über der Tableiste: volle Breite, nie vom Inhalt oder der Tableiste verdeckt.
    private var saveBar: some View {
        VStack(spacing: AppSpacing.xs) {
            if let reason = saveBlockedReason {
                Text(verbatim: reason)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            PrimaryButton(title: L(app.capabilities.hasProToolsAccess ? "movie_save_button" : "tools_pro_save"),
                          symbol: app.capabilities.hasProToolsAccess ? "square.and.arrow.down" : "crown") {
                Task { await export() }
            }
            .disabled(saveBlockedReason != nil || ExportCoordinator.shared.isBusy)
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.vertical, AppSpacing.xs)
        .background(.bar)
    }

    private var saveBlockedReason: String? {
        guard let problem = MoviePlan.problem(project) else { return nil }
        return switch problem {
        case .tooFew: L("movie_too_few")
        case .tooMany: L("movie_too_many")
        case .tooLong: L("movie_too_long")
        }
    }

    // MARK: Projekt ändern

    /// Auswahl übernehmen, ohne Reihenfolge und Einstellungen vorhandener Clips zu verlieren: Behaltene bleiben an ihrer
    /// Stelle, neu gewählte kommen ans Ende.
    private func merge(_ ids: [String]) {
        let wanted = Set(ids)
        let kept = project.clips.filter { wanted.contains($0.mediaId) }
        let known = Set(kept.map(\.mediaId))
        let added = ids.filter { !known.contains($0) }.compactMap { makeClip($0) }
        project = project.withClips(kept + added)
        applyTransitions()
        if project.clips.count < 2 { editMode = .inactive }
    }

    private func makeClip(_ id: String) -> VideoClip? {
        guard let asset = app.asset(id) else { return nil }
        if asset.isVideo {
            return MoviePlan.videoClip(id: UUID().uuidString, mediaId: id, durationMs: Int64(asset.duration * 1000))
        }
        return MoviePlan.photoClip(id: UUID().uuidString, mediaId: id, durationMs: Int64(photoSeconds * 1000), kenBurns: kenBurns)
    }

    private func move(_ index: Int, _ delta: Int) {
        project = project.move(from: index, to: index + delta)
        applyTransitions()
    }

    private func moveClips(_ source: IndexSet, _ destination: Int) {
        var clips = project.clips
        clips.move(fromOffsets: source, toOffset: destination)
        project = project.withClips(clips)
        applyTransitions()
    }

    /// Entfernen ohne Rückfrage, aber mit „Rückgängig“. Die Datei in der Mediathek bleibt immer unberührt.
    private func removeClips(_ offsets: IndexSet) {
        let clipsBefore = project.clips
        let removed = offsets.sorted().compactMap { offset -> (offset: Int, clip: VideoClip)? in
            guard clipsBefore.indices.contains(offset) else { return nil }
            return (offset: offset, clip: clipsBefore[offset])
        }
        guard !removed.isEmpty else { return }
        var clips = project.clips
        clips.remove(atOffsets: offsets)
        project = project.withClips(clips)
        applyTransitions()
        if project.clips.count < 2 { editMode = .inactive }
        app.showToast(L("movie_clip_removed"), actionTitle: L("undo")) { restore(removed) }
    }

    private func restore(_ removed: [(offset: Int, clip: VideoClip)]) {
        var clips = project.clips
        for item in removed where !clips.contains(where: { $0.id == item.clip.id }) {
            clips.insert(item.clip, at: min(item.offset, clips.count))
        }
        project = project.withClips(clips)
        applyTransitions()
    }

    private func applyTransitions() {
        project.transitions = Array(repeating: fadeThroughBlack ? .fadeBlack : .none, count: max(0, project.clips.count - 1))
    }

    private func setPhotoDuration(_ seconds: Int) {
        project = project.withClips(project.clips.map { MoviePlan.withPhotoDuration($0, ms: Int64(seconds * 1000)) })
    }

    private func setKenBurns(_ enabled: Bool) {
        var clips = project.clips
        for index in clips.indices where clips[index].isPhoto { clips[index].kenBurns = enabled }
        project = project.withClips(clips)
    }

    // MARK: Export

    private func export() async {
        guard app.capabilities.hasProToolsAccess else { app.navigate(.pro); return }
        if let problem = MoviePlan.problem(project) {
            switch problem {
            case .tooFew: errorKey = "movie_too_few"
            case .tooMany: errorKey = "movie_too_many"
            case .tooLong: errorKey = "movie_too_long"
            }
            return
        }
        do {
            var assets: [String: AVAsset] = [:]
            var infos: [String: VideoInfo] = [:]
            for clip in project.clips where !clip.isPhoto {
                guard let source = await VideoSource.asset(clip.mediaId, allowNetwork: true),
                      let info = await VideoSource.info(source) else { throw VideoError.read }
                assets[clip.mediaId] = source
                infos[clip.mediaId] = info
            }
            guard let first = app.asset(project.clips[0].mediaId) else { throw VideoError.missing }
            let sourceSize = VSize(max(2, first.pixelWidth), max(2, first.pixelHeight))
            let frame = MoviePlan.frame(project, first: sourceSize)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let scoped = musicURL?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { musicURL?.stopAccessingSecurityScopedResource() } }
            let p = project
            let boxedAssets = UncheckedBox(assets)
            let boxedInfos = UncheckedBox(infos)
            let selectedMusic = musicURL
            let url = try await ExportCoordinator.shared.run(title: L("movie_running")) { progress in
                try await VideoExportJob.renderMovie(project: p, assets: boxedAssets.value, infos: boxedInfos.value,
                                                     frame: frame, fps: 30, musicURL: selectedMusic, allowNetwork: true,
                                                     folder: folder, baseName: "PhotoMaid", progress: progress)
            }
            let request = PhotoLibraryService.SaveRequest(fileURL: url, isVideo: true, creationDate: Date(),
                                                          latitude: nil, longitude: nil, filename: url.lastPathComponent)
            guard case .saved(let newID) = await app.library.save(request) else { throw VideoError.write }
            _ = await EditSaver.finish(app: app, original: nil, newID: newID, mode: .copy, video: true,
                                       kind: .merge, count: project.clips.count, bytes: VideoExportJob.fileSize(url))
            app.showToast(L("movie_saved"))
        } catch is CancellationError {
            return
        } catch {
            errorKey = "movie_failed"
        }
    }
}
