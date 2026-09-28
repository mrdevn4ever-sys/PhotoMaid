import Foundation

/// A. Systemkapazität laut öffentlicher API (`volumeTotalCapacity`,
/// `volumeAvailableCapacityForImportantUsage`).
public struct DeviceCapacity: Hashable, Sendable {
    public let totalBytes: Int64
    public let availableForImportantUsageBytes: Int64
    public var usedBytes: Int64 { max(0, totalBytes - availableForImportantUsageBytes) }
    public init(totalBytes: Int64, availableForImportantUsageBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableForImportantUsageBytes = availableForImportantUsageBytes
    }
}

public enum StorageCategory: String, Hashable, Sendable, CaseIterable {
    case photos
    case videos
    /// Teilmenge von `photos`.
    case screenshots
    case connectedFiles
    /// Überlappende Ansicht.
    case largeFiles
    /// Überlappende Ansicht.
    case duplicates

    /// Kategorien, die sich nicht überschneiden und daher addiert werden dürfen.
    public static let disjoint: [StorageCategory] = [.photos, .videos, .connectedFiles]

    public var isOverlappingView: Bool { !Self.disjoint.contains(self) }
}

/// B. Erfasste zugängliche Medien/Dateien. C. bleibt ausdrücklich unbekannt.
public struct StorageOverview: Hashable, Sendable {
    public let device: DeviceCapacity?
    public let categories: [StorageCategory: SizeTally]
    public let scannedAt: Date?

    public init(device: DeviceCapacity?, categories: [StorageCategory: SizeTally], scannedAt: Date?) {
        self.device = device
        self.categories = categories
        self.scannedAt = scannedAt
    }

    /// Summe nur der disjunkten Kategorien. Screenshots/Duplikate/Große Dateien nicht addieren.
    public var scannedTotal: SizeTally {
        var t = SizeTally()
        for c in StorageCategory.disjoint {
            if let tally = categories[c] { t.merge(tally) }
        }
        return t
    }

    // C. Nicht einsehbarer Umfang (andere Apps, System, nicht freigegebene Dateien) wird bewusst
    // NICHT als Differenz berechnet: PhotoKit liefert Originalgrößen, iCloud-optimierte Medien
    // belegen lokal weniger. Eine Differenz wäre eine erfundene Zahl. Die UI benennt C nur textlich.
}
