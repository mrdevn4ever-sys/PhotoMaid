import Foundation

/// CAF 1.0: big-endian structure fields; little-endian signed 16-bit mono PCM.
/// The final data chunk has the standard unknown-length marker, allowing encrypted streaming
/// without ever seeking back into a plaintext recording. Apple CAF specification, Audio Data Chunk.
public enum VaultAudioFormat {
    public static func header(sampleRate: Double) throws -> Data {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate) else { throw VaultWorkspaceError.invalidData }
        func be(_ value: UInt64, _ count: Int) -> Data {
            Data((0..<count).map { UInt8((value >> UInt64((count - 1 - $0) * 8)) & 255) })
        }
        var data = Data("caff".utf8)
        data.append(be(1, 2)); data.append(be(0, 2))
        data.append(Data("desc".utf8)); data.append(be(32, 8))
        data.append(be(sampleRate.bitPattern, 8)); data.append(Data("lpcm".utf8))
        data.append(be(2, 4)) // CAF IsLittleEndian (not AudioStreamBasicDescription's flag constants).
        data.append(be(2, 4)); data.append(be(1, 4)); data.append(be(1, 4)); data.append(be(16, 4))
        data.append(Data("data".utf8)); data.append(be(UInt64.max, 8)); data.append(be(0, 4))
        return data
    }
}
