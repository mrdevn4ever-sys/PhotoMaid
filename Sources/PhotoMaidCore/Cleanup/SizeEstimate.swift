import Foundation

/// Größe für die Anzeige: gemessen oder – wo iOS keine Größe nennt (z. B. Original nur in iCloud) – geschätzt.
/// Geschätztes wird IMMER als „ca.“ gezeigt und nie als gemessen ausgegeben (Nutzerentscheidung E17, 14.10.2026).
public enum SizeValue: Hashable, Sendable {
    case exact(Int64)
    case approximate(Int64)

    public var bytes: Int64 {
        switch self {
        case .exact(let b), .approximate(let b): b
        }
    }

    public var isApproximate: Bool {
        if case .approximate = self { return true }
        return false
    }

    /// Gemessen, sonst die Schätzung.
    public static func of(_ size: KnownSize, estimate: @autoclosure () -> Int64) -> SizeValue {
        if case .known(let b) = size { return .exact(b) }
        return .approximate(estimate())
    }
}

/// Summe gemessener und geschätzter Größen. Ist ein Teil geschätzt, ist die ganze Summe „ca.“.
public struct SizeSum: Hashable, Sendable {
    public private(set) var bytes: Int64 = 0
    public private(set) var approximate = false
    public private(set) var count = 0

    public init() {}

    public init<S: Sequence>(_ values: S) where S.Element == SizeValue {
        for v in values { add(v) }
    }

    public mutating func add(_ v: SizeValue) {
        bytes += max(0, v.bytes)
        approximate = approximate || v.isApproximate
        count += 1
    }

    public var value: SizeValue { approximate ? .approximate(bytes) : .exact(bytes) }
}

/// Was die Schätzung über ein Medium bzw. eine Datei weiß (nur Metadaten, keine Bilddaten).
public enum EstimateKind: String, Hashable, Sendable, CaseIterable {
    case photo, livePhoto, screenshot, video, file
}

public struct EstimateInput: Hashable, Sendable {
    public let kind: EstimateKind
    public let pixels: Int
    public let duration: TimeInterval
    /// Dateityp (z. B. UTI) – nur für Dateien.
    public let fileType: String?

    public init(kind: EstimateKind, pixels: Int = 0, duration: TimeInterval = 0, fileType: String? = nil) {
        self.kind = kind
        self.pixels = pixels
        self.duration = duration
        self.fileType = fileType
    }
}

public struct SizeSample: Hashable, Sendable {
    public let input: EstimateInput
    public let bytes: Int64
    public init(_ input: EstimateInput, bytes: Int64) {
        self.input = input
        self.bytes = bytes
    }
}

/// Schätzt Größen aus den GEMESSENEN Medien dieser Mediathek: Fotos über Bytes je Pixel, Videos über Bytes je Pixel
/// und Sekunde, Dateien über den Median gleichen Typs – jeweils der Median (robust gegen Ausreißer). Gibt es zu wenige
/// Messungen, gelten vorsichtige Richtwerte für iPhone-Aufnahmen (HEIC/HEVC). Ergebnis immer > 0, immer „ca.“.
public struct SizeEstimator: Sendable, Equatable {
    public static let minimumSamples = 5
    /// Richtwerte ohne eigene Messungen: Bytes je Pixel (Fotos) bzw. je Pixel·Sekunde (Videos).
    public static let fallbackRates: [EstimateKind: Double] = [.photo: 0.2, .livePhoto: 0.4, .screenshot: 0.4, .video: 0.4]
    public static let fallbackPixels = 12_000_000
    public static let fallbackVideoPixels = 1920 * 1080
    public static let fallbackFileBytes: Int64 = 1_000_000

    public private(set) var rates: [EstimateKind: Double] = [:]
    public private(set) var fileMedians: [String: Int64] = [:]
    public private(set) var fileMedian: Int64?

    public init(samples: [SizeSample] = []) {
        var ratios: [EstimateKind: [Double]] = [:]
        var files: [String: [Int64]] = [:]
        var allFiles: [Int64] = []
        for s in samples where s.bytes > 0 {
            switch s.input.kind {
            case .file:
                allFiles.append(s.bytes)
                if let t = s.input.fileType { files[t, default: []].append(s.bytes) }
            case .video:
                guard s.input.pixels > 0, s.input.duration >= 1 else { continue }
                ratios[.video, default: []].append(Double(s.bytes) / (Double(s.input.pixels) * s.input.duration))
            case .photo, .livePhoto, .screenshot:
                guard s.input.pixels > 0 else { continue }
                ratios[s.input.kind, default: []].append(Double(s.bytes) / Double(s.input.pixels))
            }
        }
        for (kind, values) in ratios where values.count >= Self.minimumSamples {
            rates[kind] = Self.median(values)
        }
        for (type, values) in files where values.count >= Self.minimumSamples {
            fileMedians[type] = Self.median(values)
        }
        if allFiles.count >= Self.minimumSamples { fileMedian = Self.median(allFiles) }
    }

    /// Kalibriert (aus eigenen Messungen) statt Richtwert?
    public func isCalibrated(_ kind: EstimateKind) -> Bool {
        kind == .file ? fileMedian != nil : rates[kind] != nil
    }

    public func estimate(_ i: EstimateInput) -> Int64 {
        let bytes: Double
        switch i.kind {
        case .file:
            return max(1, i.fileType.flatMap { fileMedians[$0] } ?? fileMedian ?? Self.fallbackFileBytes)
        case .video:
            let rate = rates[.video] ?? Self.fallbackRates[.video]!
            let pixels = i.pixels > 0 ? i.pixels : Self.fallbackVideoPixels
            let seconds = i.duration.isFinite && i.duration > 0 ? max(1, i.duration) : 1
            bytes = rate * Double(pixels) * seconds
        case .photo, .livePhoto, .screenshot:
            let rate = rates[i.kind] ?? Self.fallbackRates[i.kind]!
            let pixels = i.pixels > 0 ? i.pixels : Self.fallbackPixels
            bytes = rate * Double(pixels)
        }
        guard bytes.isFinite else { return Self.fallbackFileBytes }
        return max(1_000, Int64(bytes.rounded()))
    }

    /// Für die Anzeige: auf zwei gültige Stellen gerundet (eine Schätzung ist keine Messung).
    public static func rounded(_ bytes: Int64) -> Int64 {
        guard bytes >= 100 else { return max(0, bytes) }
        var magnitude: Int64 = 1
        while bytes / magnitude >= 100 { magnitude *= 10 }
        return ((bytes + magnitude / 2) / magnitude) * magnitude
    }

    private static func median<T: Comparable>(_ values: [T]) -> T {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
