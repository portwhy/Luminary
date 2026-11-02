import Foundation

public struct Credentials: Codable, Hashable, Sendable {
    public let accessToken: String
    public let userId: String

    public init(accessToken: String, userId: String) {
        self.accessToken = accessToken
        self.userId = userId
    }
}

/// Everything needed to resume a signed-in session on next launch.
public struct StoredSession: Codable, Hashable, Sendable {
    public var serverURL: URL
    public var serverId: String?
    public var serverName: String?
    public var user: UserDto
    public var accessToken: String

    public init(serverURL: URL, serverId: String?, serverName: String?, user: UserDto, accessToken: String) {
        self.serverURL = serverURL
        self.serverId = serverId
        self.serverName = serverName
        self.user = user
        self.accessToken = accessToken
    }

    public var credentials: Credentials {
        Credentials(accessToken: accessToken, userId: user.id)
    }
}

#if canImport(Security)
/// Persists the active session as a single JSON blob in the login Keychain.
/// (One active server for now; multi-server support can key accounts by serverId later.)
public struct SessionStore: Sendable {
    private let keychain: KeychainStore
    private static let account = "active-session"

    public init(keychain: KeychainStore = KeychainStore(service: "app.luminary.session")) {
        self.keychain = keychain
    }

    public func load() -> StoredSession? {
        guard let data = try? keychain.data(forAccount: Self.account) else { return nil }
        guard let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            try? keychain.removeData(forAccount: Self.account) // corrupt or from an older schema
            return nil
        }
        return session
    }

    public func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        try keychain.setData(data, forAccount: Self.account)
    }

    public func clear() throws {
        try keychain.removeData(forAccount: Self.account)
    }
}
#endif
