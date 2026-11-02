import Foundation

public struct PublicSystemInfo: Codable, Hashable, Sendable {
    public let id: String?
    public let serverName: String?
    public let version: String?
    public let productName: String?
    public let localAddress: String?
    public let startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
        case localAddress = "LocalAddress"
        case startupWizardCompleted = "StartupWizardCompleted"
    }

    /// True for Jellyfin 10.9+, which introduced the `/UserViews`, `/UserItems/*` and `/Items?userId=` routes we use.
    public var isSupportedVersion: Bool {
        guard let version else { return true } // don't block on servers that hide it
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return true }
        return (parts[0], parts[1]) >= (10, 9)
    }
}

public struct UserDto: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let serverId: String?
    public let primaryImageTag: String?
    public let hasPassword: Bool?

    public init(id: String, name: String, serverId: String? = nil, primaryImageTag: String? = nil, hasPassword: Bool? = nil) {
        self.id = id
        self.name = name
        self.serverId = serverId
        self.primaryImageTag = primaryImageTag
        self.hasPassword = hasPassword
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case serverId = "ServerId"
        case primaryImageTag = "PrimaryImageTag"
        case hasPassword = "HasPassword"
    }
}

public struct AuthenticationResult: Decodable, Sendable {
    public let user: UserDto
    public let accessToken: String
    public let serverId: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

/// Jellyfin's paged list envelope: `{ "Items": [...], "TotalRecordCount": n, "StartIndex": i }`.
public struct QueryResult<Item: Decodable & Sendable>: Decodable, Sendable {
    public let items: [Item]
    public let totalRecordCount: Int?
    public let startIndex: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}
