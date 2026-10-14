import Testing
@testable import PhotoMaidCore

@Suite struct LibraryFilterTests {
    let photo = LibraryMediaFacts(id: "p", kind: .photo, isFavorite: true, isLivePhoto: true)
    let shot = LibraryMediaFacts(id: "s", kind: .screenshot, isEdited: true)
    let slowmo = LibraryMediaFacts(id: "v", kind: .video, isSlowMotion: true)
    let pano = LibraryMediaFacts(id: "pa", kind: .photo, isPanorama: true)

    @Test func mainFiltersLikePhotosApp() {
        let all = [photo, shot, slowmo, pano]
        func ids(_ f: LibraryFilter) -> [String] { LibraryFilter.apply(f, to: all, facts: { $0 }).map(\.id) }
        #expect(ids(.all) == ["p", "s", "v", "pa"])
        #expect(ids(.photos) == ["p", "s", "pa"])
        #expect(ids(.videos) == ["v"])
        #expect(ids(.screenshots) == ["s"])
        #expect(ids(.favorites) == ["p"])
        #expect(ids(.edited) == ["s"])
        #expect(ids(.livePhotos) == ["p"])
        #expect(ids(.slowMotion) == ["v"])
        #expect(ids(.panoramas) == ["pa"])
        #expect(ids(.timelapse).isEmpty)
    }

    @Test func collectionFiltersNeedMembers() {
        #expect(!LibraryFilter.selfies.accepts(photo))
        #expect(LibraryFilter.selfies.accepts(photo, members: ["p"]))
        #expect(!LibraryFilter.raw.accepts(shot, members: ["p"]))
        #expect(LibraryFilter.raw.readsCollection && !LibraryFilter.videos.readsCollection)
    }

    @Test func everyFilterIsOffered() {
        #expect(Set(LibraryFilter.main + LibraryFilter.mediaTypes) == Set(LibraryFilter.allCases))
    }
}
