import XCTest
@testable import JellyfinKit

final class JellyfinKitTests: XCTestCase {
    private let identity = ClientIdentity(clientName: "Luminary", deviceName: "Test Mac", deviceID: "dev123", version: "0.1.0")

    // MARK: Decoding

    func testDecodesAuthenticationResult() throws {
        let json = #"""
        {"User":{"Name":"alex","ServerId":"srv","Id":"u1","HasPassword":true,"PrimaryImageTag":null,
                 "Policy":{"IsAdministrator":true}},
         "SessionInfo":{"Id":"s1"},"AccessToken":"tok","ServerId":"srv"}
        """#
        let result = try JSONDecoder().decode(AuthenticationResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.accessToken, "tok")
        XCTAssertEqual(result.user.id, "u1")
        XCTAssertEqual(result.user.name, "alex")
        XCTAssertEqual(result.serverId, "srv")
    }

    func testDecodesItemPageAndToleratesUnknownKinds() throws {
        let json = #"""
        {"Items":[
          {"Name":"Frieren","Id":"a1","Type":"Series","CollectionType":null,"ProductionYear":2023,
           "ImageTags":{"Primary":"tagP","Thumb":"tagT"},"BackdropImageTags":["b0"],
           "UserData":{"PlaybackPositionTicks":0,"PlayCount":0,"IsFavorite":false,"Played":false,"UnplayedItemCount":12}},
          {"Name":"Episode 3","Id":"e3","Type":"Episode","IndexNumber":3,"ParentIndexNumber":1,
           "SeriesId":"a1","SeriesName":"Frieren","SeriesPrimaryImageTag":"tagS","RunTimeTicks":14400000000,
           "UserData":{"PlaybackPositionTicks":7200000000,"PlayedPercentage":50.0,"Played":false}},
          {"Name":"Something New","Id":"x9","Type":"SomeFutureKind"}
        ],"TotalRecordCount":3,"StartIndex":0}
        """#
        let page = try JSONDecoder().decode(QueryResult<BaseItemDto>.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(page.totalRecordCount, 3)

        let series = page.items[0]
        XCTAssertEqual(series.type, .series)
        XCTAssertEqual(series.imageTags?["Primary"], "tagP")

        let episode = page.items[1]
        XCTAssertEqual(episode.episodeLabel, "S1:E3")
        XCTAssertEqual(episode.runtimeSeconds, 1440)
        XCTAssertEqual(episode.resumeSeconds, 720)
        XCTAssertEqual(episode.progress ?? 0, 0.5, accuracy: 0.0001)

        XCTAssertEqual(page.items[2].type?.rawValue, "SomeFutureKind")
    }

    func testStoredSessionRoundTrips() throws {
        let session = StoredSession(
            serverURL: URL(string: "http://192.0.2.10:8096")!,
            serverId: "srv", serverName: "Home",
            user: UserDto(id: "u1", name: "alex"), accessToken: "tok"
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(StoredSession.self, from: data)
        XCTAssertEqual(decoded, session)
        XCTAssertEqual(decoded.credentials, Credentials(accessToken: "tok", userId: "u1"))
    }

    // MARK: Auth header

    func testAuthorizationHeader() {
        XCTAssertEqual(
            identity.authorizationHeader(),
            #"MediaBrowser Client="Luminary", Device="Test Mac", DeviceId="dev123", Version="0.1.0""#
        )
        XCTAssertTrue(identity.authorizationHeader(token: "abc").hasSuffix(#", Token="abc""#))
    }

    func testHeaderSanitizesDeviceName() {
        XCTAssertEqual(ClientIdentity.sanitize("Alex\u{2019}s \"MacBook\", Pro"), "Alex's MacBook Pro")
        XCTAssertEqual(ClientIdentity.sanitize("Café"), "Caf")
    }

    // MARK: Server URL handling

    func testCandidatesForBareLANAddress() throws {
        let urls = try JellyfinClient.candidateURLs(for: " 192.0.2.10/ ").map(\.absoluteString)
        XCTAssertEqual(urls, ["http://192.0.2.10:8096", "http://192.0.2.10", "https://192.0.2.10"])
    }

    func testCandidatesForAddressWithPort() throws {
        let urls = try JellyfinClient.candidateURLs(for: "192.0.2.10:8096").map(\.absoluteString)
        XCTAssertEqual(urls, ["http://192.0.2.10:8096", "https://192.0.2.10:8096"])
    }

    func testCandidatesForPublicHostname() throws {
        let urls = try JellyfinClient.candidateURLs(for: "media.example.com").map(\.absoluteString)
        XCTAssertEqual(urls, ["https://media.example.com"]) // never falls back to plain http on its own
    }

    func testExplicitHTTPIsKept() throws {
        let urls = try JellyfinClient.candidateURLs(for: "http://media.example.com:8096").map(\.absoluteString)
        XCTAssertEqual(urls, ["http://media.example.com:8096"])
    }

    func testPublicIPIsHTTPSOnly() throws {
        let urls = try JellyfinClient.candidateURLs(for: "203.0.113.7:8096").map(\.absoluteString)
        XCTAssertEqual(urls, ["https://203.0.113.7:8096"])
    }

    func testExplicitSchemeKeepsBasePath() throws {
        let urls = try JellyfinClient.candidateURLs(for: "https://media.example.com/jellyfin/").map(\.absoluteString)
        XCTAssertEqual(urls, ["https://media.example.com/jellyfin"])
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try JellyfinClient.candidateURLs(for: "   "))
        XCTAssertThrowsError(try JellyfinClient.candidateURLs(for: "ftp://nope"))
    }

    // MARK: URL building

    func testDirectStreamURL() throws {
        let client = JellyfinClient(
            serverURL: URL(string: "http://192.0.2.10:8096")!,
            identity: identity,
            credentials: Credentials(accessToken: "tok", userId: "u1")
        )
        XCTAssertEqual(
            try client.directStreamURL(itemId: "abc").absoluteString,
            "http://192.0.2.10:8096/Videos/abc/stream?static=true&mediaSourceId=abc&deviceId=dev123&api_key=tok"
        )
    }

    func testURLsRespectReverseProxyBasePath() throws {
        let client = JellyfinClient(serverURL: URL(string: "https://media.example.com/jellyfin")!, identity: identity)
        XCTAssertEqual(
            try client.url("/System/Info/Public").absoluteString,
            "https://media.example.com/jellyfin/System/Info/Public"
        )
    }

    func testStreamURLRequiresSignIn() {
        let client = JellyfinClient(serverURL: URL(string: "http://localhost:8096")!, identity: identity)
        XCTAssertThrowsError(try client.directStreamURL(itemId: "abc"))
    }

    func testVersionGate() throws {
        func info(_ v: String) throws -> PublicSystemInfo {
            try JSONDecoder().decode(PublicSystemInfo.self, from: Data(#"{"Id":"x","Version":"\#(v)"}"#.utf8))
        }
        XCTAssertTrue(try info("10.10.7").isSupportedVersion)
        XCTAssertTrue(try info("10.9.0").isSupportedVersion)
        XCTAssertFalse(try info("10.8.13").isSupportedVersion)
    }

    func testTicks() {
        XCTAssertEqual(Ticks.seconds(10_000_000), 1)
        XCTAssertEqual(Ticks.ticks(90.5), 905_000_000)
    }
}
