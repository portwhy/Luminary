import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A thin, immutable async/await client for the Jellyfin REST API (targets Jellyfin 10.9+).
///
/// Immutability keeps it trivially `Sendable`: hand the same instance to any view or task.
/// Signing in doesn't mutate a client, it returns a new one via `authenticated(with:)`.
public final class JellyfinClient: Sendable {
    public let serverURL: URL
    public let identity: ClientIdentity
    public let credentials: Credentials?
    private let urlSession: URLSession

    public static let defaultFields = ["PrimaryImageAspectRatio", "Overview", "ChildCount", "MediaSourceCount"]
    static let defaultImageTypes = "Primary,Backdrop,Thumb"

    public static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    public init(
        serverURL: URL,
        identity: ClientIdentity = ClientIdentity(),
        credentials: Credentials? = nil,
        urlSession: URLSession = JellyfinClient.defaultSession
    ) {
        self.serverURL = serverURL
        self.identity = identity
        self.credentials = credentials
        self.urlSession = urlSession
    }

    public func authenticated(with credentials: Credentials) -> JellyfinClient {
        JellyfinClient(serverURL: serverURL, identity: identity, credentials: credentials, urlSession: urlSession)
    }

    public var isAuthenticated: Bool { credentials != nil }

    // MARK: - Server discovery

    /// Turns whatever the user typed ("192.168.1.10", "jellyfin.example.com", "https://x/jellyfin")
    /// into an ordered list of URLs worth probing.
    public static func candidateURLs(for input: String) throws -> [URL] {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { throw JellyfinError.invalidServerURL(input) }

        // Explicit scheme: trust it exactly (keeps reverse-proxy base paths like /jellyfin).
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty
            else { throw JellyfinError.invalidServerURL(input) }
            return [url]
        }

        guard let probe = URLComponents(string: "http://" + trimmed),
              let host = probe.host, !host.isEmpty
        else { throw JellyfinError.invalidServerURL(input) }

        func make(_ scheme: String, port: Int? = nil) -> URL? {
            var components = probe
            components.scheme = scheme
            if let port { components.port = port }
            return components.url
        }

        let local = looksLocal(host)
        let ordered: [URL?]
        if probe.port != nil {
            ordered = local ? [make("http"), make("https")] : [make("https"), make("http")]
        } else if local {
            // LAN box: Jellyfin's default port first.
            ordered = [make("http", port: 8096), make("http"), make("https")]
        } else {
            // Public hostname: most likely behind a TLS reverse proxy.
            ordered = [make("https"), make("http", port: 8096), make("http")]
        }
        let urls = ordered.compactMap { $0 }
        guard !urls.isEmpty else { throw JellyfinError.invalidServerURL(input) }
        return urls
    }

    static func looksLocal(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") || !host.contains(".") {
            return true
        }
        let octets = host.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// Probes each candidate's `/System/Info/Public` and returns an unauthenticated client for the first
    /// one that answers like a Jellyfin server.
    public static func discover(
        _ input: String,
        identity: ClientIdentity = ClientIdentity(),
        urlSession: URLSession = JellyfinClient.defaultSession
    ) async throws -> (client: JellyfinClient, info: PublicSystemInfo) {
        var lastError: Error = JellyfinError.invalidServerURL(input)
        for url in try candidateURLs(for: input) {
            try Task.checkCancellation()
            let client = JellyfinClient(serverURL: url, identity: identity, urlSession: urlSession)
            do {
                let info = try await client.publicSystemInfo(timeout: 5)
                guard info.id != nil else { continue }
                guard info.isSupportedVersion else {
                    throw JellyfinError.unsupportedServerVersion(info.version ?? "?")
                }
                return (client, info)
            } catch let error as JellyfinError {
                if case .unsupportedServerVersion = error { throw error }
                lastError = error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw JellyfinError.serverUnreachable(input, underlying: lastError.localizedDescription)
    }

    // MARK: - System & auth

    public func publicSystemInfo(timeout: TimeInterval? = nil) async throws -> PublicSystemInfo {
        try await get("/System/Info/Public", timeout: timeout)
    }

    /// POST /Users/AuthenticateByName
    public func authenticate(username: String, password: String) async throws -> AuthenticationResult {
        struct Body: Encodable {
            let Username: String
            let Pw: String
        }
        let body = try JSONEncoder().encode(Body(Username: username, Pw: password))
        let request = try makeRequest("/Users/AuthenticateByName", method: "POST", jsonBody: body)
        return try decode(AuthenticationResult.self, from: try await perform(request))
    }

    /// GET /Users/Me: cheap token validation on launch.
    public func currentUser() async throws -> UserDto {
        _ = try requireCredentials()
        return try await get("/Users/Me")
    }

    /// POST /Sessions/Logout: revokes this device's token server-side.
    public func logout() async throws {
        _ = try requireCredentials()
        try await perform(try makeRequest("/Sessions/Logout", method: "POST"))
    }

    // MARK: - Library

    /// The user's top-level libraries (Movies, Shows, Anime, ...).
    public func userViews() async throws -> [BaseItemDto] {
        let creds = try requireCredentials()
        let result: QueryResult<BaseItemDto> = try await get("/UserViews", query: [
            URLQueryItem(name: "userId", value: creds.userId),
        ])
        return result.items
    }

    /// Continue Watching.
    public func resumeItems(limit: Int = 24) async throws -> [BaseItemDto] {
        let creds = try requireCredentials()
        let result: QueryResult<BaseItemDto> = try await get("/UserItems/Resume", query: [
            URLQueryItem(name: "userId", value: creds.userId),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "mediaTypes", value: "Video"),
            URLQueryItem(name: "fields", value: Self.defaultFields.joined(separator: ",")),
            URLQueryItem(name: "enableImageTypes", value: Self.defaultImageTypes),
            URLQueryItem(name: "imageTypeLimit", value: "1"),
        ])
        return result.items
    }

    /// Every genre, tag and year used in a library, for building filters.
    public func filterOptions(parentId: String, includeItemTypes: [BaseItemKind]) async throws -> FilterOptions {
        let creds = try requireCredentials()
        var query = [
            URLQueryItem(name: "userId", value: creds.userId),
            URLQueryItem(name: "parentId", value: parentId),
        ]
        if !includeItemTypes.isEmpty {
            query.append(URLQueryItem(name: "includeItemTypes", value: includeItemTypes.map(\.rawValue).joined(separator: ",")))
        }
        return try await get("/Items/Filters", query: query)
    }

    /// "Recently Added" for one library (series are grouped, so new episodes show as their show).
    public func latestItems(parentId: String, limit: Int = 24) async throws -> [BaseItemDto] {
        let creds = try requireCredentials()
        return try await get("/Items/Latest", query: [
            URLQueryItem(name: "userId", value: creds.userId),
            URLQueryItem(name: "parentId", value: parentId),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "groupItems", value: "true"),
            URLQueryItem(name: "fields", value: Self.defaultFields.joined(separator: ",")),
            URLQueryItem(name: "enableImageTypes", value: Self.defaultImageTypes),
            URLQueryItem(name: "imageTypeLimit", value: "1"),
        ])
    }

    /// Next Up across all series, or for one series. `includeResumable: false` leaves out episodes that are
    /// already part-watched, since those belong in Continue Watching.
    public func nextUp(limit: Int = 24, seriesId: String? = nil, includeResumable: Bool = true) async throws -> [BaseItemDto] {
        let creds = try requireCredentials()
        var query = [
            URLQueryItem(name: "userId", value: creds.userId),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "fields", value: Self.defaultFields.joined(separator: ",")),
            URLQueryItem(name: "enableImageTypes", value: Self.defaultImageTypes),
            URLQueryItem(name: "imageTypeLimit", value: "1"),
        ]
        if let seriesId { query.append(URLQueryItem(name: "seriesId", value: seriesId)) }
        if !includeResumable { query.append(URLQueryItem(name: "enableResumable", value: "false")) }
        let result: QueryResult<BaseItemDto> = try await get("/Shows/NextUp", query: query)
        return result.items
    }

    /// Generic paged item query (library grids, search).
    public func items(_ itemQuery: ItemQuery) async throws -> QueryResult<BaseItemDto> {
        let creds = try requireCredentials()
        return try await get("/Items", query: itemQuery.queryItems(userId: creds.userId))
    }

    /// Full item detail, including MediaSources/MediaStreams for direct-play decisions.
    public func item(id: String) async throws -> BaseItemDto {
        let creds = try requireCredentials()
        return try await get("/Items/\(id)", query: [URLQueryItem(name: "userId", value: creds.userId)])
    }

    public func seasons(seriesId: String) async throws -> [BaseItemDto] {
        let creds = try requireCredentials()
        let result: QueryResult<BaseItemDto> = try await get("/Shows/\(seriesId)/Seasons", query: [
            URLQueryItem(name: "userId", value: creds.userId),
            URLQueryItem(name: "fields", value: Self.defaultFields.joined(separator: ",")),
        ])
        return result.items
    }

    public func episodes(seriesId: String, seasonId: String? = nil) async throws -> [BaseItemDto] {
        let creds = try requireCredentials()
        var query = [
            URLQueryItem(name: "userId", value: creds.userId),
            URLQueryItem(name: "fields", value: (Self.defaultFields + ["MediaSources"]).joined(separator: ",")),
        ]
        if let seasonId { query.append(URLQueryItem(name: "seasonId", value: seasonId)) }
        let result: QueryResult<BaseItemDto> = try await get("/Shows/\(seriesId)/Episodes", query: query)
        return result.items
    }

    // MARK: - URLs (synchronous; safe to call from view bodies)

    /// Image URL. Images are served without auth by default, so these work with any image loader.
    public func imageURL(itemId: String, type: ImageType, tag: String? = nil, index: Int? = nil, maxWidth: Int? = nil, quality: Int = 90) -> URL? {
        var path = "/Items/\(itemId)/Images/\(type.rawValue)"
        if let index { path += "/\(index)" }
        var query = [URLQueryItem(name: "quality", value: String(quality))]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        if let maxWidth { query.append(URLQueryItem(name: "maxWidth", value: String(maxWidth))) }
        return try? url(path, query: query)
    }

    /// 2:3 poster (series poster for episodes).
    public func posterURL(for item: BaseItemDto, maxWidth: Int = 400) -> URL? {
        if item.type == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag {
            return imageURL(itemId: seriesId, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        if let tag = item.imageTags?[ImageType.primary.rawValue] {
            return imageURL(itemId: item.id, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        return nil
    }

    /// An episode's own screenshot for episode lists (shelves use `landscapeURL`, which prefers the series art).
    public func episodeThumbURL(for episode: BaseItemDto, maxWidth: Int = 480) -> URL? {
        if let tag = episode.imageTags?[ImageType.primary.rawValue] {
            return imageURL(itemId: episode.id, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        return landscapeURL(for: episode, maxWidth: maxWidth)
    }

    /// 16:9 artwork for shelves like Continue Watching.
    public func landscapeURL(for item: BaseItemDto, maxWidth: Int = 640) -> URL? {
        if let tag = item.imageTags?[ImageType.thumb.rawValue] {
            return imageURL(itemId: item.id, type: .thumb, tag: tag, maxWidth: maxWidth)
        }
        if let parent = item.parentThumbItemId, let tag = item.parentThumbImageTag {
            return imageURL(itemId: parent, type: .thumb, tag: tag, maxWidth: maxWidth)
        }
        if item.type == .episode, let tag = item.imageTags?[ImageType.primary.rawValue] {
            return imageURL(itemId: item.id, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        if let tag = item.backdropImageTags?.first {
            return imageURL(itemId: item.id, type: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
        }
        if let parent = item.parentBackdropItemId, let tag = item.parentBackdropImageTags?.first {
            return imageURL(itemId: parent, type: .backdrop, tag: tag, index: 0, maxWidth: maxWidth)
        }
        return posterURL(for: item, maxWidth: maxWidth)
    }

    /// Direct-play URL: the original file, byte-for-byte, no server transcoding.
    /// `/Videos/{id}/stream?static=true&mediaSourceId=...&api_key=...`
    public func directStreamURL(itemId: String, mediaSourceId: String? = nil, playSessionId: String? = nil) throws -> URL {
        let creds = try requireCredentials()
        return try url("/Videos/\(itemId)/stream", query: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId ?? itemId),
            URLQueryItem(name: "deviceId", value: identity.deviceID),
            URLQueryItem(name: "playSessionId", value: playSessionId),
            URLQueryItem(name: "api_key", value: creds.accessToken),
        ])
    }

    /// Turns a server-relative URL (e.g. a TranscodingUrl or subtitle DeliveryUrl) into an absolute one,
    /// adding the access token if the server didn't include one.
    public func absoluteURL(serverRelative path: String) -> URL? {
        var string: String
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            string = path
        } else {
            var base = serverURL.absoluteString
            while base.hasSuffix("/") { base.removeLast() }
            string = base + (path.hasPrefix("/") ? path : "/" + path)
        }
        let lower = string.lowercased()
        if let token = credentials?.accessToken, !lower.contains("api_key=") && !lower.contains("apikey=") {
            string += (string.contains("?") ? "&" : "?") + "api_key=" + token
        }
        return URL(string: string)
    }

    /// Headers for players that can send them (mpv `http-header-fields`). Preferable to `api_key` in the URL
    /// because the token then never shows up in server access logs.
    public var playbackHTTPHeaders: [String: String] {
        ["Authorization": identity.authorizationHeader(token: credentials?.accessToken)]
    }

    // MARK: - Plumbing

    func requireCredentials() throws -> Credentials {
        guard let credentials else { throw JellyfinError.notAuthenticated }
        return credentials
    }

    func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            throw JellyfinError.invalidServerURL(serverURL.absoluteString)
        }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + path
        let items = query.filter { $0.value != nil }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else {
            throw JellyfinError.invalidServerURL(serverURL.absoluteString + path)
        }
        return url
    }

    func makeRequest(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        jsonBody: Data? = nil,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = method
        request.setValue(identity.authorizationHeader(token: credentials?.accessToken), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jsonBody {
            request.httpBody = jsonBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let timeout { request.timeoutInterval = timeout }
        return request
    }

    @discardableResult
    func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw JellyfinError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw JellyfinError.transport("The server sent a non-HTTP response.")
        }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw JellyfinError.unauthorized
        case 403: throw JellyfinError.forbidden
        case 404: throw JellyfinError.notFound(request.url?.path ?? "resource")
        default:
            let body = String(data: data.prefix(300), encoding: .utf8)
            throw JellyfinError.http(status: http.statusCode, body: body)
        }
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval? = nil) async throws -> T {
        let data = try await perform(try makeRequest(path, query: query, timeout: timeout))
        return try decode(T.self, from: data)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JellyfinError.decoding("\(T.self): \(error)")
        }
    }
}

/// Parameters for `GET /Items`.
public struct ItemQuery: Sendable, Hashable {
    public var parentId: String?
    public var includeItemTypes: [BaseItemKind]
    public var recursive: Bool
    public var sortBy: [String]
    public var sortOrder: String
    public var startIndex: Int
    public var limit: Int?
    public var searchTerm: String?
    public var fields: [String]
    /// Server-side filters, e.g. ["IsFavorite"], ["IsUnplayed"].
    public var filters: [String]
    /// Match items with ANY of these tags / genres / production years (categories combine with AND).
    public var tags: [String]
    public var genres: [String]
    public var years: [Int]

    public init(
        parentId: String? = nil,
        includeItemTypes: [BaseItemKind] = [],
        recursive: Bool = false,
        sortBy: [String] = ["SortName"],
        sortOrder: String = "Ascending",
        startIndex: Int = 0,
        limit: Int? = 100,
        searchTerm: String? = nil,
        fields: [String] = JellyfinClient.defaultFields,
        filters: [String] = [],
        tags: [String] = [],
        genres: [String] = [],
        years: [Int] = []
    ) {
        self.tags = tags
        self.genres = genres
        self.years = years
        self.parentId = parentId
        self.includeItemTypes = includeItemTypes
        self.recursive = recursive
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.startIndex = startIndex
        self.limit = limit
        self.searchTerm = searchTerm
        self.fields = fields
        self.filters = filters
    }

    func queryItems(userId: String) -> [URLQueryItem] {
        var q = [URLQueryItem(name: "userId", value: userId)]
        if let parentId { q.append(URLQueryItem(name: "parentId", value: parentId)) }
        if !includeItemTypes.isEmpty {
            q.append(URLQueryItem(name: "includeItemTypes", value: includeItemTypes.map(\.rawValue).joined(separator: ",")))
        }
        q.append(URLQueryItem(name: "recursive", value: recursive ? "true" : "false"))
        q.append(URLQueryItem(name: "sortBy", value: sortBy.joined(separator: ",")))
        q.append(URLQueryItem(name: "sortOrder", value: sortOrder))
        q.append(URLQueryItem(name: "startIndex", value: String(startIndex)))
        if let limit { q.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let searchTerm, !searchTerm.isEmpty { q.append(URLQueryItem(name: "searchTerm", value: searchTerm)) }
        if !fields.isEmpty { q.append(URLQueryItem(name: "fields", value: fields.joined(separator: ","))) }
        if !filters.isEmpty { q.append(URLQueryItem(name: "filters", value: filters.joined(separator: ","))) }
        // Jellyfin: pipe-separated = any of; (a comma-separated tag list matches nothing). Years use commas.
        if !tags.isEmpty { q.append(URLQueryItem(name: "tags", value: tags.joined(separator: "|"))) }
        if !genres.isEmpty { q.append(URLQueryItem(name: "genres", value: genres.joined(separator: "|"))) }
        if !years.isEmpty { q.append(URLQueryItem(name: "years", value: years.map(String.init).joined(separator: ","))) }
        q.append(URLQueryItem(name: "enableImageTypes", value: JellyfinClient.defaultImageTypes))
        q.append(URLQueryItem(name: "imageTypeLimit", value: "1"))
        q.append(URLQueryItem(name: "enableTotalRecordCount", value: "true"))
        return q
    }
}


/// What a library can be filtered by (`/Items/Filters`).
public struct FilterOptions: Decodable, Sendable, Equatable {
    public var genres: [String]
    public var tags: [String]
    public var years: [Int]

    enum CodingKeys: String, CodingKey {
        case genres = "Genres", tags = "Tags", years = "Years"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        years = try c.decodeIfPresent([Int].self, forKey: .years) ?? []
    }
}
