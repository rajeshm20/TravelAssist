import CryptoKit
import Foundation
import Security

enum GPXFileCrypto {
    enum CryptoError: Error {
        case keyUnavailable
        case invalidCiphertext
    }

    // Versioned envelope:
    // [0] = version (1)
    // [1...] = AES.GCM.SealedBox.combined (nonce + ciphertext + tag)
    private static let envelopeVersion: UInt8 = 1

    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try symmetricKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw CryptoError.invalidCiphertext
        }
        var out = Data([envelopeVersion])
        out.append(combined)
        return out
    }

    static func decryptIfNeeded(_ data: Data) throws -> Data {
        // Legacy plaintext GPX support.
        if data.starts(with: Data("<gpx".utf8)) || data.starts(with: Data("<?xml".utf8)) {
            return data
        }

        guard let version = data.first, version == envelopeVersion else {
            // Unknown format: treat as plaintext to avoid bricking existing tracks.
            return data
        }
        let combined = data.dropFirst()
        let key = try symmetricKey()
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    private static func symmetricKey() throws -> SymmetricKey {
        if let existing = readKeyData() {
            return SymmetricKey(data: existing)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard storeKeyData(data) else {
            throw CryptoError.keyUnavailable
        }
        return key
    }

    private static let keychainService = "travelassist.gpx.encryption"
    private static let keychainAccount = "symmetric-key"

    private static func readKeyData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func storeKeyData(_ data: Data) -> Bool {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecValueData as String: data
        ]

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }

        if addStatus == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecAttrSynchronizable as String: kCFBooleanTrue as Any
            ]
            let update: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            return updateStatus == errSecSuccess
        }

        return false
    }
}

