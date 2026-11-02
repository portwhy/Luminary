#if canImport(Security)
import Foundation
import Security

/// Minimal wrapper over a generic-password Keychain item.
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    #if DEBUG || LUMINARY_DEV_STORE
    // Dev builds (debug, or release built by scripts/dev.sh) keep the session in a private file instead of the Keychain. A debug build is re-signed
    // (new cdhash) on every compile, and the Keychain re-prompts for the login password each time. Release
    // builds, which are signed once, use the real Keychain below.
    private func debugFile(account: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Luminary-Dev", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("\(service).\(account)")
    }

    public func data(forAccount account: String) throws -> Data? {
        try? Data(contentsOf: debugFile(account: account))
    }

    public func setData(_ data: Data, forAccount account: String) throws {
        let url = debugFile(account: account)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func removeData(forAccount account: String) throws {
        try? FileManager.default.removeItem(at: debugFile(account: account))
    }
    #else
    public func data(forAccount account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw JellyfinError.keychain(status: status)
        }
    }

    public func setData(_ data: Data, forAccount account: String) throws {
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel as String] = "Luminary (Jellyfin session)"
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw JellyfinError.keychain(status: addStatus) }
        } else if status != errSecSuccess {
            throw JellyfinError.keychain(status: status)
        }
    }

    public func removeData(forAccount account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JellyfinError.keychain(status: status)
        }
    }
    #endif
}
#endif
