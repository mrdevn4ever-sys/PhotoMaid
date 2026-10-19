import Security
import XCTest
@testable import PhotoMaid

/// Exercise the real device keychain, including the simulator's signing/entitlement requirement.
@MainActor
final class VaultKeychainTests: XCTestCase {
    func testCodeKeychainRoundTripAndReplacement() async throws {
        let account = "qa.roundtrip." + UUID().uuidString
        defer { VaultKeychain.delete(account) }
        let initial = Data("first test envelope".utf8)
        do {
            try VaultKeychain.set(initial, account: account)
        } catch {
            let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrService as String: "PhotoMaid.QA",
                                        kSecAttrAccount as String: account,
                                        kSecValueData as String: initial]
            let status = SecItemAdd(probe as CFDictionary, nil)
            SecItemDelete(probe as CFDictionary)
            XCTFail("Keychain write failed; Security probe OSStatus: \(status)")
            throw error
        }
        XCTAssertEqual(VaultKeychain.get(account), initial)
        let replacement = Data("replacement test envelope".utf8)
        try VaultKeychain.set(replacement, account: account)
        XCTAssertEqual(VaultKeychain.get(account), replacement)
        VaultKeychain.delete(account)
        XCTAssertNil(VaultKeychain.get(account))
    }
}
