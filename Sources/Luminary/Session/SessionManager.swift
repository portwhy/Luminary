import Foundation
import JellyfinKit
import Observation

struct AuthenticatedSession {
    let client: JellyfinClient
    let user: UserDto
    let serverName: String
}

/// App-wide auth state: restores the Keychain session on launch, signs in and out.
@MainActor
@Observable
final class SessionManager {
    enum State {
        case restoring
        case signedOut
        case signedIn(AuthenticatedSession)
    }

    private(set) var state: State = .restoring

    private let store = SessionStore()
    private let identity = ClientIdentity(version: AppVersion.current)
    private static let lastServerKey = "app.luminary.lastServer"

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    static var lastServerInput: String {
        UserDefaults.standard.string(forKey: lastServerKey) ?? ""
    }

    func restore() async {
        guard let stored = store.load() else {
            state = .signedOut
            return
        }
        let client = JellyfinClient(serverURL: stored.serverURL, identity: identity, credentials: stored.credentials)
        let serverName = stored.serverName ?? stored.serverURL.host ?? "Jellyfin"
        do {
            let user = try await client.currentUser()
            state = .signedIn(AuthenticatedSession(client: client, user: user, serverName: serverName))
        } catch JellyfinError.unauthorized {
            // Token was revoked (e.g. removed under Dashboard → Devices).
            try? store.clear()
            state = .signedOut
        } catch {
            // Server unreachable right now: keep the session; screens show errors and can retry.
            state = .signedIn(AuthenticatedSession(client: client, user: stored.user, serverName: serverName))
        }
    }

    func signIn(server: String, username: String, password: String) async throws {
        let (anonymous, info) = try await JellyfinClient.discover(server, identity: identity)
        let result = try await anonymous.authenticate(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        let client = anonymous.authenticated(with: Credentials(accessToken: result.accessToken, userId: result.user.id))

        let stored = StoredSession(
            serverURL: client.serverURL,
            serverId: info.id ?? result.serverId,
            serverName: info.serverName,
            user: result.user,
            accessToken: result.accessToken
        )
        do {
            try store.save(stored)
        } catch {
            // Not fatal: you stay signed in for this launch, you just won't be remembered.
            print("Luminary: couldn't save session to Keychain: \(error.localizedDescription)")
        }
        UserDefaults.standard.set(server, forKey: Self.lastServerKey)

        state = .signedIn(AuthenticatedSession(
            client: client,
            user: result.user,
            serverName: info.serverName ?? client.serverURL.host ?? "Jellyfin"
        ))
    }

    func signOut() async {
        if case .signedIn(let session) = state {
            try? await session.client.logout()
        }
        try? store.clear()
        state = .signedOut
    }
}
