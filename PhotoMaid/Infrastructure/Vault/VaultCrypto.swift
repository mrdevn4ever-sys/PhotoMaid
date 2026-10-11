import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import PhotoMaidCore
import Security

struct VaultKey: Sendable {
    let data: Data
    var symmetric: SymmetricKey { SymmetricKey(data: data) }
    static func random() throws -> VaultKey { VaultKey(data: Data(try VaultCrypto.randomBytes(32))) }
}
enum VaultCryptoError: Error { case random, derivation, seal, format, authentication, io }

enum VaultCrypto {
    static let codeRounds: UInt32 = 600_000
    static let recoveryRounds: UInt32 = 100_000
    static func randomBytes(_ count: Int) throws -> [UInt8] {
        guard count > 0, count <= 1024 else { throw VaultCryptoError.format }
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw VaultCryptoError.random }
        return bytes
    }
    static func pbkdf2(_ secret: String, salt: [UInt8], rounds: UInt32) throws -> SymmetricKey {
        guard salt.count == 16, (100_000...2_000_000).contains(rounds), secret.utf8.count <= 4096 else {
            throw VaultCryptoError.format
        }
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
    static func wrap(_ key: VaultKey, secret: String, rounds: UInt32) throws -> VaultWrappedKey {
        let salt = try randomBytes(16)
        let kek = try pbkdf2(secret, salt: salt, rounds: rounds)
        guard let box = try AES.GCM.seal(key.data, using: kek).combined else { throw VaultCryptoError.seal }
        return VaultWrappedKey(salt: Data(salt), rounds: rounds, box: box)
    }
    static func unwrap(_ wrapped: VaultWrappedKey, secret: String) throws -> VaultKey {
        guard wrapped.box.count == 60 else { throw VaultCryptoError.format }
        let kek = try pbkdf2(secret, salt: Array(wrapped.salt), rounds: wrapped.rounds)
        do {
            let data = try AES.GCM.open(AES.GCM.SealedBox(combined: wrapped.box), using: kek)
            guard data.count == 32 else { throw VaultCryptoError.format }
            return VaultKey(data: data)
        } catch { throw VaultCryptoError.authentication }
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
    private var closed = false

    init(url: URL, master: VaultKey, chunkSize: Int = VaultChunkLayout.defaultChunkSize) throws {
        guard (1...(64 << 20)).contains(chunkSize) else { throw VaultCryptoError.format }
        let salt = try VaultCrypto.randomBytes(VaultChunkLayout.saltLength)
        key = VaultCrypto.subkey(master, salt: salt, info: "pm-vault-file")
        self.chunkSize = chunkSize
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.complete]) else { throw VaultCryptoError.io }
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data(VaultChunkLayout.header(chunkSize: chunkSize, salt: salt)))
    }
    func receive(_ data: Data) {
        lock.withLock {
            guard failure == nil, !closed else { return }
            do {
                hasher.update(data: data); total += Int64(data.count); buffer.append(data)
                while buffer.count > chunkSize {
                    try emit(buffer.prefix(chunkSize), last: false)
                    buffer = Data(buffer.dropFirst(chunkSize))
                }
            } catch { failure = error }
        }
    }
    func finish() throws -> (size: Int64, sha256: String) {
        try lock.withLock {
            guard !closed else { throw VaultCryptoError.io }
            defer { closed = true; buffer = Data(); try? handle.close() }
            if let failure { throw failure }
            try emit(buffer, last: true)
            try handle.synchronize()
            return (total, Array(hasher.finalize()).hexString)
        }
    }
    func abort() { lock.withLock { closed = true; buffer = Data(); try? handle.close() } }
    private func emit(_ plain: Data, last: Bool) throws {
        let aad = Data(VaultChunkLayout.aad(index: index, isLast: last))
        guard let combined = try AES.GCM.seal(Data(plain), using: key, authenticating: aad).combined else { throw VaultCryptoError.seal }
        try handle.write(contentsOf: combined)
        index += 1
    }
}

enum VaultFileReader {
    /// Bounded RAM for photos. Video playback/exports use the streaming sink.
    static func data(at url: URL, master: VaultKey, expected: VaultResource? = nil,
                     lease: VaultSessionFence.Lease? = nil, maximumBytes: Int = 128 << 20) throws -> Data {
        if let expected, expected.size > Int64(maximumBytes) { throw VaultCryptoError.format }
        var result = Data()
        try forEachChunk(url, master: master, lease: lease) { plain in
            guard plain.count <= maximumBytes - result.count else { throw VaultCryptoError.format }
            result.append(plain)
        }
        try verify(size: Int64(result.count), digest: Array(SHA256.hash(data: result)).hexString, expected: expected)
        try lease?.requireValid()
        return result
    }

    @discardableResult
    static func decrypt(_ url: URL, to target: URL, master: VaultKey, expected: VaultResource? = nil,
                        lease: VaultSessionFence.Lease? = nil) throws -> (size: Int64, sha256: String) {
        func permitted<T>(_ operation: () throws -> T) throws -> T {
            if let lease { return try lease.withValidity(operation) }
            return try operation()
        }
        let output: FileHandle = try permitted {
            guard FileManager.default.createFile(atPath: target.path, contents: nil,
                                                 attributes: [.protectionKey: FileProtectionType.complete]) else { throw VaultCryptoError.io }
            return try FileHandle(forWritingTo: target)
        }
        defer { try? output.close() }
        var hasher = SHA256(); var total: Int64 = 0
        do {
            try forEachChunk(url, master: master, lease: lease) { plain in
                try permitted { try output.write(contentsOf: plain) }
                hasher.update(data: plain); total += Int64(plain.count)
            }
            let digest = Array(hasher.finalize()).hexString
            try verify(size: total, digest: digest, expected: expected)
            try permitted { try output.synchronize() }
            return (total, digest)
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }
    static func digest(_ url: URL, master: VaultKey) throws -> (size: Int64, sha256: String) {
        var hasher = SHA256(); var total: Int64 = 0
        try forEachChunk(url, master: master) { hasher.update(data: $0); total += Int64($0.count) }
        return (total, Array(hasher.finalize()).hexString)
    }
    private static func verify(size: Int64, digest: String, expected: VaultResource?) throws {
        guard let expected else { return }
        guard expected.size == size, expected.sha256.lowercased() == digest.lowercased() else { throw VaultCryptoError.authentication }
    }
    private static func forEachChunk(_ url: URL, master: VaultKey, lease: VaultSessionFence.Lease? = nil,
                                     _ body: (Data) throws -> Void) throws {
        try lease?.requireValid()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let rawLength = try handle.seekToEnd()
        guard rawLength <= UInt64(Int64.max) else { throw VaultCryptoError.format }
        let length = Int64(rawLength)
        try handle.seek(toOffset: 0)
        guard let head = try handle.read(upToCount: VaultChunkLayout.headerLength),
              let header = VaultChunkLayout.parseHeader(Array(head)) else { throw VaultCryptoError.format }
        // Bound descriptor allocation independently of the on-disk header. A
        // corrupted tiny chunkSize must not allocate billions of Chunk values.
        let bodyLength = length - Int64(VaultChunkLayout.headerLength)
        let blockLength = Int64(header.chunkSize + VaultChunkLayout.overhead)
        guard bodyLength >= Int64(VaultChunkLayout.overhead), bodyLength / blockLength <= 1_000_000,
              let chunks = VaultChunkLayout.chunks(fileLength: length, chunkSize: header.chunkSize) else { throw VaultCryptoError.format }
        let key = VaultCrypto.subkey(master, salt: header.salt, info: "pm-vault-file")
        for chunk in chunks {
            try lease?.requireValid()
            try handle.seek(toOffset: UInt64(chunk.offset))
            guard let sealed = try handle.read(upToCount: chunk.length), sealed.count == chunk.length else { throw VaultCryptoError.format }
            let aad = Data(VaultChunkLayout.aad(index: chunk.index, isLast: chunk.isLast))
            let plain: Data
            do { plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: aad) }
            catch { throw VaultCryptoError.authentication }
            try lease?.requireValid()
            try body(plain)
        }
    }
}

/// Wrapped PIN data remains migratable with encrypted device backups. Biometric
/// access is device-bound; a changed set of enrolled faces/fingers invalidates it.
enum VaultKeychain {
    static let codeAccount = "vault.code"
    static let biometricAccount = "vault.biometric"
    static let lockoutAccount = "vault.lockout"
    static let settingsAccount = "vault.settings.v2"
    private static var service: String { (Bundle.main.bundleIdentifier ?? "photomaid") + ".vault" }
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func set(_ data: Data, account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw VaultCryptoError.io }
        var add = query(account)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        add[kSecValueData as String] = data
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw VaultCryptoError.io }
    }
    static func get(_ account: String) -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    static func deleteChecked(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultCryptoError.io }
    }
    static func delete(_ account: String) { try? deleteChecked(account) }
    static func deleteAll() {
        for account in [codeAccount, biometricAccount, lockoutAccount, settingsAccount] { delete(account) }
    }
    static func setBiometric(_ data: Data) throws {
        guard data.count == 32 else { throw VaultCryptoError.format }
        // Existing access-control policy is retained. Never delete the old
        // credential before knowing that the replacement can be committed.
        let updated = SecItemUpdate(query(biometricAccount) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw VaultCryptoError.io }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                         .biometryCurrentSet, &error) else { throw VaultCryptoError.io }
        var add = query(biometricAccount)
        add[kSecAttrAccessControl as String] = access; add[kSecValueData as String] = data
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw VaultCryptoError.io }
    }
    nonisolated static func readBiometric(reason: String) async -> VaultKey? {
        let context = LAContext()
        defer { context.invalidate() }
        context.localizedFallbackTitle = ""
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason),
                  !Task.isCancelled else { return nil }
        } catch { return nil }
        var request = query(biometricAccount)
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              data.count == 32, !Task.isCancelled else { return nil }
        return VaultKey(data: data)
    }
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
