import AVFoundation
import Photos
import PhotoMaidCore
import SwiftUI
import UniformTypeIdentifiers

struct MovieView: View {
    @Environment(AppModel.self) private var app
    let initialIDs: [String]
    @State private var project = VideoProject(id: UUID().uuidString, clips: [])
    @State private var picker = false
    @State private var importingMusic = false
    @State private var musicURL: URL?
    @State private var photoSeconds = 3
    @State private var errorKey: String?

    var body: some View {
        List {
            Section {
                ForEach(Array(project.clips.enumerated()), id: \.element.id) { index, clip in
                    HStack {
                        AssetCell(assetID: clip.mediaId).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: AppRadii.small))
                        Text(verbatim: L("movie_clip_n", index + 1)).font(AppTypography.headline)
                        Spacer()
                        Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                        Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.disabled(index == project.clips.count - 1)
                        Button(role: .destructive) { remove(index) } label: { Image(systemName: "trash") }
                    }
                }
                Button { picker = true } label: { Label(L("movie_add"), systemImage: "plus") }
            } header: { Text(key: "movie_tab_clips") }

            Section {
                Stepper(L("movie_photo_duration") + " · " + String(photoSeconds), value: $photoSeconds, in: 1...10)
                    .onChange(of: photoSeconds) { _, seconds in setPhotoDuration(seconds) }
                Toggle(L("movie_kenburns"), isOn: Binding(get: {
                    project.clips.filter(\.isPhoto).allSatisfy(\.kenBurns)
                }, set: { enabled in setKenBurns(enabled) }))
                Toggle(L("movie_fade_black"), isOn: Binding(get: {
                    !project.transitions.isEmpty && project.transitions.allSatisfy { $0 == .fadeBlack }
                }, set: { enabled in
                    project.transitions = Array(repeating: enabled ? .fadeBlack : .none, count: max(0, project.clips.count - 1))
                }))
            } header: { Text(key: "movie_tab_transition") }

            Section {
                Picker(L("movie_format"), selection: Binding(get: { project.aspect ?? 0 }, set: { value in
                    project.aspect = value == 0 ? nil : value
                })) {
                    Text(key: "movie_format_first").tag(Float(0))
                    Text(verbatim: "1:1").tag(Float(1))
                    Text(verbatim: "4:5").tag(Float(0.8))
                    Text(verbatim: "9:16").tag(Float(9.0 / 16.0))
                    Text(verbatim: "16:9").tag(Float(16.0 / 9.0))
                }
                Toggle(L("pdf_fill"), isOn: $project.fill)
                Picker(L("movie_quality"), selection: $project.profile) {
                    Text(key: "movie_quality_high").tag(ExportProfile.high)
                    Text(key: "movie_quality_balanced").tag(ExportProfile.balanced)
                    Text(key: "movie_quality_small").tag(ExportProfile.small)
                }
            } header: { Text(key: "movie_tab_format") }

            Section {
                if let track = project.music {
                    Text(verbatim: track.name)
                    Slider(value: Binding(get: { Double(project.music?.volume ?? 0.8) }, set: { value in
                        project.music?.volume = Float(value)
                    }), in: 0...1)
                    Button(role: .destructive) { project.music = nil; musicURL = nil } label: { Text(key: "movie_music_remove") }
                } else {
                    Button { importingMusic = true } label: { Label(L("movie_music_pick"), systemImage: "music.note") }
                }
            } header: { Text(key: "movie_tab_music") } footer: { Text(key: "movie_music_note") }

            Section {
                Button { Task { await export() } } label: { Label(L("save"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(.glassProminent)
                    .disabled(project.clips.count < 2 || ExportCoordinator.shared.isBusy)
            }
        }
        .appPage()
        .navigationTitle(L("movie_title"))
        .overlay { if ExportCoordinator.shared.isBusy { ExportProgressOverlay(coordinator: ExportCoordinator.shared) } }
        .sheet(isPresented: $picker) {
            StudioMediaPicker(allowsVideos: true, limit: VideoRules.maxClips, initial: Set(project.clips.map(\.mediaId))) { ids in
                build(ids)
            }
        }
        .fileImporter(isPresented: $importingMusic, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            musicURL = url
            project.music = MusicTrack(uri: url.absoluteString, name: url.lastPathComponent)
        }
        .alert(L("error_title"), isPresented: Binding(get: { errorKey != nil }, set: { if !$0 { errorKey = nil } })) {
            Button(L("ok")) { errorKey = nil }
        } message: { Text(key: errorKey ?? "movie_failed") }
        .task { if project.clips.isEmpty { build(initialIDs) } }
    }

    private func build(_ ids: [String]) {
        let clips = ids.compactMap { id -> VideoClip? in
            guard let asset = app.asset(id) else { return nil }
            if asset.isVideo { return MoviePlan.videoClip(id: UUID().uuidString, mediaId: id, durationMs: Int64(asset.duration * 1000)) }
            return MoviePlan.photoClip(id: UUID().uuidString, mediaId: id, durationMs: Int64(photoSeconds * 1000))
        }
        project = project.withClips(clips)
    }

    private func move(_ index: Int, _ delta: Int) { project = project.move(from: index, to: index + delta) }
    private func remove(_ index: Int) { project = project.withClips(project.clips.enumerated().filter { $0.offset != index }.map(\.element)) }
    private func setPhotoDuration(_ seconds: Int) {
        project = project.withClips(project.clips.map { MoviePlan.withPhotoDuration($0, ms: Int64(seconds * 1000)) })
    }
    private func setKenBurns(_ enabled: Bool) {
        var clips = project.clips
        for index in clips.indices where clips[index].isPhoto { clips[index].kenBurns = enabled }
        project = project.withClips(clips)
    }

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
