import Foundation
#if canImport(Security)
import Security
#endif

public enum JellyfinError: Error, LocalizedError, Sendable {
    case invalidServerURL(String)
    case serverUnreachable(String, underlying: String)
    case unsupportedServerVersion(String)
    case notAuthenticated
    case unauthorized
    case forbidden
    case notFound(String)
    case http(status: Int, body: String?)
    case decoding(String)
    case transport(String)
    case keychain(status: Int32)
    case playbackRefused(String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL(let input):
            return "“\(input)” isn’t a valid server address."
        case .serverUnreachable(let input, let underlying):
            return "Couldn’t find a Jellyfin server at “\(input)”. \(underlying)"
        case .unsupportedServerVersion(let version):
            return "Jellyfin \(version) is too old. Luminary needs Jellyfin 10.9 or newer."
        case .notAuthenticated:
            return "You’re not signed in."
        case .unauthorized:
            return "The server rejected the sign-in. Check your username and password."
        case .forbidden:
            return "Your account doesn’t have permission to do that."
        case .notFound(let path):
            return "The server couldn’t find \(path)."
        case .http(let status, let body):
            return "The server returned HTTP \(status)." + (body.map { " \($0)" } ?? "")
        case .decoding(let detail):
            return "Unexpected response from the server (\(detail))."
        case .transport(let detail):
            return detail
        case .playbackRefused(let code):
            switch code {
            case "NotAllowed": return "Your Jellyfin account isn’t allowed to play this."
            case "RateLimitExceeded": return "The server’s streaming limit has been reached. Try a lower quality."
            default: return "The server couldn’t produce a playable stream (\(code))."
            }
        case .keychain(let status):
            #if canImport(Security)
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error: \(message)"
            }
            #endif
            return "Keychain error \(status)."
        }
    }
}
