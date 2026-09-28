import Foundation
import SwiftUI
import PhotoMaidCore

/// Ehrliche Formatierung von Größen. Unbekannt bleibt unbekannt.
enum SizeText {
    static func bytes(_ b: Int64) -> String {
        b.formatted(.byteCount(style: .file))
    }

    static func size(_ s: KnownSize) -> Text {
        switch s {
        case .known(let b): Text(bytes(b))
        case .unknown: Text("Größe unbekannt")
        }
    }

    /// „mind. 1,2 GB“, wenn unbekannte Größen enthalten sind.
    static func tally(_ t: SizeTally) -> Text {
        if t.knownCount == 0 && t.unknownCount > 0 { return Text("Größe unbekannt") }
        if t.isLowerBound { return Text("mind. \(bytes(t.knownBytes))") }
        return Text(bytes(t.knownBytes))
    }
}

enum DayText {
    static func string(_ day: LocalDay) -> String {
        day.startOfDay(in: .autoupdatingCurrent).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func text(_ day: LocalDay) -> Text { Text(string(day)) }
}
