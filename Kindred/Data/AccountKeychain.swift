import Foundation
import Security

enum AccountKeychain {
    enum Item: String {
        case session, passwordRecovery
    }

    struct StorageError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Kindred couldn’t access secure storage. Try again after unlocking your device." }
    }

    static func load<Value: Decodable>(_ type: Value.Type, for item: Item) throws -> Value? {
        var request = query(for: item)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StorageError(status: status) }
        return try JSONDecoder().decode(type, from: data)
    }

    static func save<Value: Encodable>(_ value: Value, for item: Item) throws {
        let data = try JSONEncoder().encode(value)
        var request = query(for: item)
        let status = SecItemUpdate(request as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StorageError(status: status) }
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(request as CFDictionary, nil)
        guard added == errSecSuccess else { throw StorageError(status: added) }
    }

    static func remove(_ item: Item) throws {
        let status = SecItemDelete(query(for: item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError(status: status) }
    }

    private static func query(for item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.kindred.prototype.auth",
         kSecAttrAccount as String: item.rawValue,
         kSecUseDataProtectionKeychain as String: true]
    }
}
