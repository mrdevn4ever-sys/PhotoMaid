import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import PhotoMaidCore
import Security

/// Hauptschlüssel des Tresors (256 Bit). Liegt nur im Speicher, solange der Tresor offen ist.
struct VaultKey: Sendable {
    let data: Data

    var symmetric: SymmetricKey { SymmetricKey(data: data) }

    static func random() throws -> VaultKey { VaultKey(data: Data(try VaultCrypto.randomBytes(32))) }
}

enum VaultCryptoError: Error {
    case random, derivation, seal, format, authentication, io
}

/// Verschlüsselung des Tresors: AES-GCM (CryptoKit), Schlüssel je Datei über HKDF aus dem Hauptschlüssel, der
/// Hauptschlüssel selbst mit einem aus Code bzw. Notfallschlüssel abgeleiteten Schlüssel (PBKDF2-SHA256) verpackt.
/// Ausschließlich Apple-Frameworks, nichts verlässt das Gerät.
enum VaultCrypto {
    /// Ableitungsrunden für den Code (hoch, weil eine PIN wenig Entropie hat) und den Notfallschlüssel (128 Bit).
    static let codeRounds: UInt32 = 600_000
    static let recoveryRounds: UInt32 = 100_000

    static func randomBytes(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw VaultCryptoError.random }
        return bytes
    }

    static func pbkdf2(_ secret: String, salt: [UInt8], rounds: UInt32) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let length = secret.utf8.count
        let status: Int32 = secret.withCString { password in
            salt.withUnsafeBufferPointer { s in
                derived.withUnsafeMutableBufferPointer { d in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, length, s.baseAddress, s.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, d.baseAddress, d.count)
                }
            }
        }
        guard status == Int32(kCCSuccess) else { throw VaultCryptoError.derivation }
        return SymmetricKey(data: Data(derived))
    }

    /// Hauptschlüssel mit einem Geheimnis verpacken (langsam: im Hintergrund aufrufen).
    static func wrap(_ key: VaultKey, secret: String, rounds: UInt32) throws -> VaultWrappedKey {
        let salt = try randomBytes(16)
        let kek = try pbkdf2(secret, salt: salt, rounds: rounds)
        guard let box = try AES.GCM.seal(key.data, using: kek).combined else { throw VaultCryptoError.seal }
        return VaultWrappedKey(salt: Data(salt), rounds: rounds, box: box)
    }

    /// Falsches Geheimnis → `.authentication` (der Prüfwert von AES-GCM passt dann nicht).
    static func unwrap(_ wrapped: VaultWrappedKey, secret: String) throws -> VaultKey {
        let kek = try pbkdf2(secret, salt: Array(wrapped.salt), rounds: wrapped.rounds)
        do {
            let data = try AES.GCM.open(AES.GCM.SealedBox(combined: wrapped.box), using: kek)
            guard data.count == 32 else { throw VaultCryptoError.format }
            return VaultKey(data: data)
        } catch {
            throw VaultCryptoError.authentication
        }
    }

    static func subkey(_ key: VaultKey, salt: [UInt8], info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key.symmetric, salt: Data(salt), info: Data(info.utf8), outputByteCount: 32)
    }

    static func seal(_ data: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw VaultCryptoError.seal }
        return combined
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }
}

/// Schreibt eine Datei verschlüsselt in Blöcken (Format: `VaultChunkLayout`). Wird von PhotoKit-Callbacks
/// nacheinander gefüttert; Fehler werden gesammelt und bei `finish()` geworfen.
final class VaultFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private let key: SymmetricKey
    private let chunkSize: Int
    private var buffer = Data()
    private var index: UInt64 = 0
    private var hasher = SHA256()
    private var total: Int64 = 0
    private var failure: (any Error)?

    init(url: URL, master: VaultKey, chunkSize: Int = VaultChunkLayout.defaultChunkSize) throws {
        let salt = try VaultCrypto.randomBytes(VaultChunkLayout.saltLength)
        key = VaultCrypto.subkey(master, salt: salt, info: "pm-vault-file")
        self.chunkSize = chunkSize
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw VaultCryptoError.io
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data(VaultChunkLayout.header(chunkSize: chunkSize, salt: salt)))
    }

    func receive(_ data: Data) {
        lock.withLock {
            guard failure == nil else { return }
            do {
                hasher.update(data: data)
                total += Int64(data.count)
                buffer.append(data)
                // Volle Blöcke nur, wenn danach noch Daten folgen (der letzte Block trägt die Markierung).
                while buffer.count > chunkSize {
                    try emit(buffer.prefix(chunkSize), last: false)
                    buffer = Data(buffer.dropFirst(chunkSize))
                }
            } catch {
                failure = error
            }
        }
    }

    /// Schließt die Datei ab. Ergebnis: Klartextgröße und SHA-256 des Klartexts.
    func finish() throws -> (size: Int64, sha256: String) {
        try lock.withLock {
            if let failure { try? handle.close(); throw failure }
            try emit(buffer, last: true)
            buffer = Data()
            try handle.synchronize()
            try handle.close()
            return (total, Array(hasher.finalize()).hexString)
        }
    }

    func abort() {
        lock.withLock { try? handle.close() }
    }

    private func emit(_ plain: Data, last: Bool) throws {
        let aad = Data(VaultChunkLayout.aad(index: index, isLast: last))
        guard let combined = try AES.GCM.seal(Data(plain), using: key, authenticating: aad).combined else {
            throw VaultCryptoError.seal
        }
        try handle.write(contentsOf: combined)
        index += 1
    }
}

/// Liest verschlüsselte Dateien des Tresors. Jeder Block wird geprüft; Manipulation oder Kürzung → Fehler.
enum VaultFileReader {
    /// Ganze Datei in den Speicher (Vorschaubilder, Fotos).
    static func data(at url: URL, master: VaultKey) throws -> Data {
        var out = Data()
        try forEachChunk(url, master: master) { out.append($0) }
        return out
    }

    /// In eine geschützte Datei entschlüsseln (Videos, Teilen, Zurück in Fotos). Liefert Größe und SHA-256.
    @discardableResult
    static func decrypt(_ url: URL, to target: URL, master: VaultKey) throws -> (size: Int64, sha256: String) {
        guard FileManager.default.createFile(atPath: target.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw VaultCryptoError.io
        }
        let out = try FileHandle(forWritingTo: target)
        defer { try? out.close() }
        var hasher = SHA256()
        var total: Int64 = 0
        do {
            try forEachChunk(url, master: master) { plain in
                hasher.update(data: plain)
                total += Int64(plain.count)
                try out.write(contentsOf: plain)
            }
        } catch {
            try? out.close()
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return (total, Array(hasher.finalize()).hexString)
    }

    /// Prüfsumme des Klartexts, ohne ihn zu speichern (Kontrolle nach dem Ablegen).
    static func digest(_ url: URL, master: VaultKey) throws -> (size: Int64, sha256: String) {
        var hasher = SHA256()
        var total: Int64 = 0
        try forEachChunk(url, master: master) { hasher.update(data: $0); total += Int64($0.count) }
        return (total, Array(hasher.finalize()).hexString)
    }

    private static func forEachChunk(_ url: URL, master: VaultKey, _ body: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = Int64(try handle.seekToEnd())
        try handle.seek(toOffset: 0)
        guard let head = try handle.read(upToCount: VaultChunkLayout.headerLength),
              let header = VaultChunkLayout.parseHeader(Array(head)),
              let chunks = VaultChunkLayout.chunks(fileLength: length, chunkSize: header.chunkSize) else {
            throw VaultCryptoError.format
        }
        let key = VaultCrypto.subkey(master, salt: header.salt, info: "pm-vault-file")
        for chunk in chunks {
            try handle.seek(toOffset: UInt64(chunk.offset))
            guard let sealed = try handle.read(upToCount: chunk.length), sealed.count == chunk.length else {
                throw VaultCryptoError.format
            }
            let aad = Data(VaultChunkLayout.aad(index: chunk.index, isLast: chunk.isLast))
            let plain: Data
            do {
                plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: aad)
            } catch {
                throw VaultCryptoError.authentication
            }
            try body(plain)
        }
    }
}

/// Schlüsselbund-Einträge des Tresors. Der mit dem Code verpackte Hauptschlüssel ist nicht an dieses Gerät
/// gebunden: Er wandert mit verschlüsselten iPhone-Backups auf ein neues Gerät (E16, Variante A). Der Eintrag für
/// Face ID/Touch ID gilt nur auf diesem Gerät und nur mit dem aktuell eingerichteten Gesicht/Finger.
enum VaultKeychain {
    static let codeAccount = "vault.code"
    static let biometricAccount = "vault.biometric"
    private static var service: String { (Bundle.main.bundleIdentifier ?? "photomaid") + ".vault" }

    static func set(_ data: Data, account: String) throws {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: data,
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw VaultCryptoError.io }
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        delete(codeAccount)
        delete(biometricAccount)
    }

    static func setBiometric(_ data: Data) throws {
        delete(biometricAccount)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                           .biometryCurrentSet, &error) else {
            throw VaultCryptoError.io
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricAccount,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: data,
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw VaultCryptoError.io }
    }

    /// Face ID/Touch ID abfragen und den Hauptschlüssel lesen. Läuft nicht auf dem Main Actor (die Abfrage blockiert).
    nonisolated static func readBiometric(reason: String) async -> VaultKey? {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) else {
                return nil
            }
        } catch {
            return nil
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              data.count == 32 else { return nil }
        return VaultKey(data: data)
    }

    /// Welche Biometrie das Gerät anbietet (`nil` = keine eingerichtet).
    static var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }
}
