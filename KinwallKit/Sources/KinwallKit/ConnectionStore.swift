import Foundation
#if canImport(Security)
import Security
#endif

/// Where the paired connection is kept. The app uses the Keychain; tests use memory.
public protocol ConnectionStore: Sendable {
    func load() throws -> Connection?
    func save(_ connection: Connection) throws
    func clear() throws
}

public final class MemoryConnectionStore: ConnectionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Connection?
    public init(_ value: Connection? = nil) { self.value = value }
    public func load() throws -> Connection? { lock.withLock { value } }
    public func save(_ connection: Connection) throws { lock.withLock { value = connection } }
    public func clear() throws { lock.withLock { value = nil } }
}

#if canImport(Security)
/// The server URL and key as one Keychain item, readable after first unlock so widgets and
/// background refresh can use it. `accessGroup` lets the app and its widgets share it once
/// Keychain Sharing is set up (see docs/PLAN.md: whether a free Personal Team allows it is
/// still to be confirmed).
public struct KeychainConnectionStore: ConnectionStore {
    public let service: String
    public let accessGroup: String?
    public init(service: String = "family.kinwall.connection", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "household"]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    public func load() throws -> Connection? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(Connection.self, from: data)
    }

    public func save(_ connection: Connection) throws {
        let data = try JSONEncoder().encode(connection)
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, Equatable, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? { "Kinwall couldn't read its sign-in from the Keychain (\(status)). Open Kinwall and sign in again." }
}
#endif
