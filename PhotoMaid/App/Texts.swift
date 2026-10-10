import Foundation
import PhotoMaidCore

/// Titel in Alltagssprache, z. B. „Videos größer als 100 MB“, „Screenshots älter als 30 Tage“.
enum CollectionText {
    static func title(_ c: SmartCollection) -> String {
        let what = switch c.source {
        case .photos: L("cat_photos")
        case .videos: L("cat_videos")
        case .screenshots: L("cat_screenshots")
        }
        switch c.filter {
        case .largerThan(let bytes): return L("col_title_larger", what, SizeText.bytes(bytes))
        case .olderThan(let days): return L("col_title_older", what, age(days))
        }
    }

    static func age(_ days: Int) -> String {
        switch days {
        case 182: L("col_age_6m")
        case 365: L("col_age_1y")
        case 730: L("col_age_2y")
        default: LP("col_age_days", days)
        }
    }

    static func symbol(_ c: SmartCollection) -> String {
        switch c.source {
        case .photos: "photo"
        case .videos: "video"
        case .screenshots: "camera.viewfinder"
        }
    }
}

enum QuickAccessText {
    /// Alben heißen wie in der Fotos-App.
    static func title(_ q: QuickAccessItem) -> String {
        switch q.kind {
        case .photos: L("qa_photos")
        case .videos: L("qa_videos")
        case .screenshots: L("qa_screenshots")
        case .latestPhotos: L("qa_latest_photos")
        case .latestVideos: L("qa_latest_videos")
        case .thisWeek: L("qa_this_week")
        case .album: AlbumNames.title(q.album) ?? L("qa_folder")
        case .random: L("qa_random")
        case .onThisDay: L("qa_on_this_day")
        case .longVideos: L("qa_long_videos")
        case .selfies: L("qa_selfies")
        case .portraits: L("qa_portraits")
        case .livePhotos: L("qa_live_photos")
        case .favorites: L("qa_favorites")
        }
    }

    static func symbol(_ q: QuickAccessItem) -> String {
        switch q.kind {
        case .photos: "photo.on.rectangle"
        case .videos: "video"
        case .screenshots: "camera.viewfinder"
        case .latestPhotos: "sparkles"
        case .latestVideos: "play.rectangle"
        case .thisWeek: "calendar"
        case .album: "rectangle.stack"
        case .random: "shuffle"
        case .onThisDay: "calendar.badge.clock"
        case .longVideos: "film"
        case .selfies: "person.crop.square"
        case .portraits: "cube"
        case .livePhotos: "livephoto"
        case .favorites: "heart"
        }
    }

    static func emptyText(_ q: QuickAccessItem) -> String {
        switch q.kind {
        case .photos: L("feed_empty_photos")
        case .videos: L("feed_empty_videos")
        case .screenshots: L("feed_empty_screenshots")
        case .latestPhotos: L("feed_empty_latest_photos")
        case .latestVideos: L("feed_empty_latest_videos")
        case .thisWeek: L("feed_empty_this_week")
        case .album: L("feed_empty_folder")
        case .random: L("feed_empty_random")
        case .onThisDay: L("feed_empty_on_this_day")
        case .longVideos: L("feed_empty_long_videos")
        case .selfies: L("feed_empty_selfies")
        case .portraits: L("feed_empty_portraits")
        case .livePhotos: L("feed_empty_live_photos")
        case .favorites: L("feed_empty_favorites")
        }
    }
}

/// Albumtitel der Fotos-App über die Kennung (nur lokal gelesen, nie gespeichert außer der Kennung selbst).
enum AlbumNames {
    static func title(_ id: String?) -> String? {
        guard let id else { return nil }
        return PhotoLibraryService.albumTitle(id)
    }
}
