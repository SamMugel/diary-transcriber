import Foundation

#if canImport(Security)
import Security
#endif

// AI:
//   what: Keychain helper for storing/retrieving the OpenAI API key
//   why:  D-0004 Whisper API fallback requires an API key; per specs/transcription.md
//         it must never be stored in manifest.json or plain text
//   ref:  specs/transcription.md Security section, specs/storage.md D-0005

enum KeychainHelper {
    private static let service = "com.compactifai.diarytranscriber"
    private static let apiKeyAccount = "api-key"

    static func saveAPIKey(_ key: String) throws {
        #if canImport(Security)
        let data = key.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
        #else
        throw KeychainError.unavailable
        #endif
    }

    static func loadAPIKey() -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    static func deleteAPIKey() {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(status: Int32)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Failed to save API key to Keychain (status: \(status))."
        case .unavailable:
            "Keychain is not available on this platform."
        }
    }
}
