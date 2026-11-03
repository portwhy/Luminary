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
///
/// Updates: our signature has no Apple team ID, so the Keychain trusts each exact build separately and a new version
/// would ask for the login password once. To avoid that, the running version calls `handOffForUpdate()` right before
/// an update installs: it moves the session into a private file (0600, in a 0700 folder) and deletes its Keychain
/// item. The new version's `load()` moves it into a Keychain item of its own (trusted for that build) and deletes the
/// file. The file only exists between those two moments; if the update doesn't happen, the old version takes it back
/// the same way.
public struct SessionStore: Sendable {
    private let keychain: KeychainStore
    private let handOffFile: URL
    private static let account = "active-session"

    public init(keychain: KeychainStore = KeychainStore(service: "app.luminary.session")) {
        self.keychain = keychain
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        handOffFile = support.appendingPathComponent("Luminary", isDirectory: true)
            .appendingPathComponent("\(keychain.service).handoff")
    }

    public func load() -> StoredSession? {
        if let handedOff = takeHandOff() { return handedOff }
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
        try? FileManager.default.removeItem(at: handOffFile)
        try keychain.removeData(forAccount: Self.account)
    }

    /// Right before an update installs (see above). Safe to call more than once: once the Keychain item is gone there
    /// is nothing left to move.
    public func handOffForUpdate() {
        guard let data = try? keychain.data(forAccount: Self.account) else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: handOffFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try? fm.removeItem(at: handOffFile)
            guard fm.createFile(atPath: handOffFile.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
            try keychain.removeData(forAccount: Self.account)
        } catch {
            try? fm.removeItem(at: handOffFile) // keep the Keychain copy and let the new version ask instead
        }
    }

    /// The session handed over by the previous version: stored back into the Keychain (as this build's own item),
    /// and the file deleted either way.
    private func takeHandOff() -> StoredSession? {
        guard let data = try? Data(contentsOf: handOffFile) else { return nil }
        try? FileManager.default.removeItem(at: handOffFile)
        guard let session = try? JSONDecoder().decode(StoredSession.self, from: data) else { return nil }
        try? keychain.setData(data, forAccount: Self.account)
        return session
    }
}
#endif
