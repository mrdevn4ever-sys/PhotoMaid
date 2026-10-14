import Foundation

/// Was eine Wischrichtung oder eine Taste im Feed auslöst – vom Nutzer selbst belegt (Entscheidung E18, 14.10.2026).
/// Standard wie bisher: hoch Behalten, links Papierkorb, rechts Später, runter Zurück.
/// Regeln bleiben: eine Geste = höchstens ein Schritt, nichts tun = keine Entscheidung, Tasten und Gesten laufen über
/// denselben Weg (`FeedViewModel.perform`), Löschen gibt es hier nie (Papierkorb = PhotoMaid-eigen).
public enum FeedAction: Codable, Hashable, Sendable {
    /// Behalten, nächstes Medium.
    case keep
    /// In den PhotoMaid-Papierkorb (nichts wird gelöscht), nächstes Medium.
    case trash
    /// Später mit Standardtermin, nächstes Medium (Pille „In n Tagen wieder · Ändern“).
    case later
    /// Später mit selbst gewähltem Termin: öffnet erst die Auswahl.
    case laterPickDate
    /// In ein Album der Fotos-App legen und behalten (ein Schritt). Rückgängig nimmt beides zurück.
    case album(id: String, title: String)
    /// Vorheriges Medium (keine Entscheidung).
    case previous
    /// Diese Richtung tut nichts (das Medium springt zurück).
    case nothing

    /// Die Entscheidung im Verlauf, die diese Aktion trifft (`nil` = keine Entscheidung).
    public var intent: FeedIntent? {
        switch self {
        case .keep, .album: .keep
        case .trash: .markForCleanup
        case .later: .later
        case .laterPickDate: .laterCustom
        case .previous: .previous
        case .nothing: nil
        }
    }

    public var isDecision: Bool { intent?.isDecision ?? false }

    public var albumID: String? {
        if case .album(let id, _) = self { return id }
        return nil
    }

    /// Feste Auswahl für die Einstellungen (Album kommt mit gewähltem Album dazu).
    public static let fixedChoices: [FeedAction] = [.keep, .trash, .later, .laterPickDate, .previous, .nothing]
}

/// Wann die Tasten im Feed erscheinen. Mit VoiceOver oder Schaltersteuerung sind sie immer da.
public enum FeedButtonVisibility: String, Codable, Sendable, CaseIterable {
    case accessibilityOnly, always
}

/// Wo die Tasten stehen.
public enum FeedButtonPlacement: String, Codable, Sendable, CaseIterable {
    case belowMedia, aboveMedia
}

public struct FeedControls: Codable, Hashable, Sendable {
    public static let maxButtons = 6

    public var up: FeedAction = .keep
    public var left: FeedAction = .trash
    public var right: FeedAction = .later
    public var down: FeedAction = .previous
    /// Tasten in Reihenfolge (links nach rechts). Leer = keine Tasten.
    public var buttons: [FeedAction] = [.previous, .trash, .keep, .later, .laterPickDate]
    public var visibility: FeedButtonVisibility = .accessibilityOnly
    public var placement: FeedButtonPlacement = .belowMedia

    public init() {}

    public static let standard = FeedControls()

    public func action(for d: SwipeDirection) -> FeedAction {
        switch d {
        case .up: up
        case .left: left
        case .right: right
        case .down: down
        }
    }

    public mutating func set(_ action: FeedAction, for d: SwipeDirection) {
        switch d {
        case .up: up = action
        case .left: left = action
        case .right: right = action
        case .down: down = action
        }
    }

    /// Richtung, auf der eine Aktion liegt (für den Pfeil auf der Taste); `nil`, wenn keine Geste sie auslöst.
    public func direction(of action: FeedAction) -> SwipeDirection? {
        [SwipeDirection.up, .left, .right, .down].first { self.action(for: $0) == action && action != .nothing }
    }

    /// Gültiger Stand: keine „Nichts“-Tasten, keine doppelten Tasten, höchstens `maxButtons`, Alben mit Kennung.
    public func sanitized() -> FeedControls {
        var c = self
        for d in [SwipeDirection.up, .left, .right, .down] {
            if case .album(let id, _) = c.action(for: d), id.isEmpty { c.set(.nothing, for: d) }
        }
        var seen = Set<FeedAction>()
        c.buttons = c.buttons.filter { a in
            if a == .nothing { return false }
            if case .album(let id, _) = a, id.isEmpty { return false }
            return seen.insert(a).inserted
        }
        if c.buttons.count > Self.maxButtons { c.buttons = Array(c.buttons.prefix(Self.maxButtons)) }
        return c
    }

    /// Auswahl für neue Tasten: alles, was noch nicht als Taste da ist.
    public func addableButtons(albums: [FeedAction] = []) -> [FeedAction] {
        (FeedAction.fixedChoices.filter { $0 != .nothing } + albums).filter { !buttons.contains($0) }
    }

    /// Ist das Album (z. B. gelöscht) nicht mehr nutzbar: überall durch „nichts“ ersetzen bzw. Taste entfernen.
    public func removingAlbum(_ albumID: String) -> FeedControls {
        var c = self
        for d in [SwipeDirection.up, .left, .right, .down] where c.action(for: d).albumID == albumID { c.set(.nothing, for: d) }
        c.buttons.removeAll { $0.albumID == albumID }
        return c
    }

    // Tolerant lesen: fehlende Felder = Standard (ältere Stände, beschädigte Werte).
    private enum CodingKeys: String, CodingKey { case up, left, right, down, buttons, visibility, placement }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeedControls()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        up = v(.up, d.up)
        left = v(.left, d.left)
        right = v(.right, d.right)
        down = v(.down, d.down)
        buttons = v(.buttons, d.buttons)
        visibility = v(.visibility, d.visibility)
        placement = v(.placement, d.placement)
        self = sanitized()
    }
}
