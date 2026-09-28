import Foundation

/// Herkunft eines Items. Fotos/Videos bleiben logische PhotoKit-Assets,
/// Dateien gehören immer zu genau einer vom Nutzer verbundenen Quelle.
public enum ItemProvider: Hashable, Codable, Sendable {
    case photoLibrary
    case connectedSource(ConnectedSourceID)
    case appContainer
}

public struct ConnectedSourceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var description: String { rawValue.uuidString }
}

/// Stabile lokale Identität eines Items: Provider + lokale Kennung.
///
/// - Für PhotoKit: `PHAsset.localIdentifier` (nicht geräteübergreifend stabil).
/// - Für Dateien: Bookmark-relativer Pfad **plus** Datei-Ressourcen-ID des Systems
///   (`fileResourceIdentifier`), sobald verfügbar. Ein Pfad allein ist keine stabile Identität;
///   Aliasprüfung erfolgt über `aliasKey` im jeweiligen Provider.
public struct ItemReference: Hashable, Codable, Sendable, CustomStringConvertible {
    public let provider: ItemProvider
    public let localIdentifier: String

    public init(provider: ItemProvider, localIdentifier: String) {
        self.provider = provider
        self.localIdentifier = localIdentifier
    }

    public static func photo(_ id: String) -> ItemReference {
        ItemReference(provider: .photoLibrary, localIdentifier: id)
    }

    public var description: String {
        switch provider {
        case .photoLibrary: "photo:\(localIdentifier)"
        case .connectedSource(let s): "file[\(s)]:\(localIdentifier)"
        case .appContainer: "app:\(localIdentifier)"
        }
    }
}

public enum MediaKind: String, Hashable, Codable, Sendable, CaseIterable {
    case photo
    case video
    case screenshot
    case file
}
