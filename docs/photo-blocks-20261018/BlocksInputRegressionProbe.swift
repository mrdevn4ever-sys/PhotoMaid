import Foundation

/// Compile against the old AND current production Core, rather than copying their implementation.
@main struct BlocksInputRegressionProbe {
    struct Result: Codable {
        let version: String
        let stationaryReleaseRecognizedHardDrop: Bool
        let rowsImmediatelyAfterSoftDropSwitch: Int
    }
    static func main() throws {
        var input = PhotoBlocksInput()
        _ = input.changed(x: 0, y: 0, time: 0, cellSize: 30)
        _ = input.changed(x: 0, y: 75, time: 0.1, cellSize: 30)
        let actions = input.ended(x: 0, y: 75, duration: 0.14, time: 0.14, cellSize: 30)
        var game = PhotoBlocksGame(); game.start()
        for _ in 0..<3 { game.advance(0.22) }
        let row = game.active!.origin.y
        game.setSoftDrop(true); game.advance(0.01)
        let result = Result(version: CommandLine.arguments[1],
                            stationaryReleaseRecognizedHardDrop: actions.contains(.hardDrop),
                            rowsImmediatelyAfterSoftDropSwitch: game.active!.origin.y - row)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(result))
    }
}
