import Foundation
import Security

protocol GeminiCredentialStoring: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

enum GeminiCredentialError: LocalizedError {
    case invalidKey, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Enter a nonempty API key on one line. Google checks it when you make a request."
        case .keychain(let status): return "macOS Keychain could not complete the request (\(status)). Unlock your login keychain and try again."
        }
    }
}

enum GeminiCredentialValue {
    /// Credentials are opaque: do not assume a prefix, alphabet, punctuation or provider length.
    static func normalized(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 16_384,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw GeminiCredentialError.invalidKey
        }
        return value
    }
}

/// One local, non-synchronizing credential. No API key is ever persisted in preferences.
struct GeminiKeychainStore: GeminiCredentialStoring {
    let service: String
    let account: String

    init(service: String = "Notchloom.Gemini", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GeminiCredentialError.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw GeminiCredentialError.keychain(errSecDecode)
        }
        return key
    }

    func save(_ key: String) throws {
        let key = try GeminiCredentialValue.normalized(key)
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(attributes as CFDictionary, nil)
            guard result == errSecSuccess else { throw GeminiCredentialError.keychain(result) }
        } else if status != errSecSuccess {
            throw GeminiCredentialError.keychain(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeminiCredentialError.keychain(status)
        }
    }
}
