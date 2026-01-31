import Foundation
import Security

/// Service for securely storing credentials
/// Uses file-based storage for development to avoid Keychain permission issues
class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.trustaccountreconciliation"

    // Use Keychain for secure credential storage (required for App Sandbox)
    private let useFileStorage = false

    private init() {}

    // MARK: - Keychain Keys

    enum KeychainKey: String {
        case stripeSecretKey = "stripe_secret_key"
        case stripeWebhookSecret = "stripe_webhook_secret"
        case databaseEncryptionKey = "database_encryption_key"
        case backupEncryptionKey = "backup_encryption_key"
    }

    // MARK: - Save

    /// Saves a string value to the keychain
    func save(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Saves data to the keychain
    func saveData(_ data: Data, for key: KeychainKey) throws {
        // Delete existing item first
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Read

    /// Reads a string value from the keychain
    func read(_ key: KeychainKey) throws -> String? {
        guard let data = try readData(key) else {
            return nil
        }

        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return value
    }

    /// Reads data from the keychain
    func readData(_ key: KeychainKey) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        return result as? Data
    }

    // MARK: - Delete

    /// Deletes a value from the keychain
    func delete(_ key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Update

    /// Updates a string value in the keychain
    func update(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, create it
            try save(value, for: key)
        } else if status != errSecSuccess {
            throw KeychainError.updateFailed(status)
        }
    }

    // MARK: - Encryption Key Generation

    /// Generates a new encryption key and stores it in the keychain
    func generateAndStoreEncryptionKey(for key: KeychainKey) throws -> Data {
        var keyData = Data(count: 32)  // 256-bit key
        let result = keyData.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, 32, pointer.baseAddress!)
        }

        guard result == errSecSuccess else {
            throw KeychainError.keyGenerationFailed
        }

        try saveData(keyData, for: key)
        return keyData
    }

    /// Gets or creates an encryption key
    func getOrCreateEncryptionKey(for key: KeychainKey) throws -> Data {
        if let existingKey = try readData(key) {
            return existingKey
        }
        return try generateAndStoreEncryptionKey(for: key)
    }

    // MARK: - Generic String Key Methods

    /// Saves a string value to the keychain with a generic string key
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieves a string value from the keychain with a generic string key
    func retrieve(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return value
    }

    /// Deletes a value from the keychain with a generic string key
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Stripe Credentials

    /// Saves Stripe API credentials
    func saveStripeCredentials(secretKey: String, webhookSecret: String?) throws {
        try save(secretKey, for: .stripeSecretKey)
        if let webhook = webhookSecret {
            try save(webhook, for: .stripeWebhookSecret)
        }
    }

    /// Gets Stripe credentials
    func getStripeCredentials() throws -> (secretKey: String?, webhookSecret: String?) {
        let secretKey = try read(.stripeSecretKey)
        let webhookSecret = try read(.stripeWebhookSecret)
        return (secretKey, webhookSecret)
    }

    /// Checks if Stripe credentials are configured
    func hasStripeCredentials() -> Bool {
        do {
            let secretKey = try read(.stripeSecretKey)
            return secretKey != nil && !secretKey!.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Clear All

    /// Clears all stored credentials (use with caution)
    func clearAllCredentials() throws {
        for key in [KeychainKey.stripeSecretKey, .stripeWebhookSecret] {
            try delete(key)
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case updateFailed(OSStatus)
    case encodingFailed
    case decodingFailed
    case keyGenerationFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain: \(securityErrorMessage(status))"
        case .readFailed(let status):
            return "Failed to read from keychain: \(securityErrorMessage(status))"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(securityErrorMessage(status))"
        case .updateFailed(let status):
            return "Failed to update keychain: \(securityErrorMessage(status))"
        case .encodingFailed:
            return "Failed to encode value for keychain storage"
        case .decodingFailed:
            return "Failed to decode value from keychain"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        }
    }

    private func securityErrorMessage(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Unknown error (code: \(status))"
    }
}
