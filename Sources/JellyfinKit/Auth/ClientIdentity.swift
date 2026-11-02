import Foundation
#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

/// Who we are to the Jellyfin server. Sent on every request in the `Authorization` header and used by the
/// server's Dashboard → Devices / Activity pages. Signing in again from the same DeviceId replaces that
/// device's previous token instead of piling up sessions.
public struct ClientIdentity: Sendable, Hashable {
    public var clientName: String
    public var deviceName: String
    public var deviceID: String
    public var version: String

    public init(
        clientName: String = "Luminary",
        deviceName: String = ClientIdentity.defaultDeviceName,
        deviceID: String = ClientIdentity.persistentDeviceID(),
        version: String = "0.1.0"
    ) {
        self.clientName = clientName
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.version = version
    }

    /// `MediaBrowser Client="Luminary", Device="...", DeviceId="...", Version="0.1.0", Token="..."`
    public func authorizationHeader(token: String? = nil) -> String {
        var parts = [
            "Client=\"\(Self.sanitize(clientName))\"",
            "Device=\"\(Self.sanitize(deviceName))\"",
            "DeviceId=\"\(Self.sanitize(deviceID))\"",
            "Version=\"\(Self.sanitize(version))\"",
        ]
        if let token, !token.isEmpty {
            parts.append("Token=\"\(Self.sanitize(token))\"")
        }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    /// Header values must be ASCII and can't contain the quote/comma delimiters the server splits on.
    /// "Alex’s MacBook Pro" becomes "Alex's MacBook Pro".
    static func sanitize(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\u{2019}", with: "'")
        let scalars = normalized.unicodeScalars.filter { scalar in
            scalar.isASCII && scalar != "\"" && scalar != "," && scalar != "\n" && scalar != "\r"
        }
        return String(String.UnicodeScalarView(scalars))
    }

    public static var defaultDeviceName: String {
        // SCDynamicStore reads the "Computer Name" from System Settings without the reverse-DNS
        // lookup that makes Host.current().localizedName occasionally block for seconds.
        #if canImport(SystemConfiguration)
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty {
            return name
        }
        #endif
        return "Mac"
    }

    /// A stable per-install identifier, generated once and kept in UserDefaults (it isn't a secret).
    public static func persistentDeviceID(defaults: UserDefaults = .standard) -> String {
        let key = "app.luminary.deviceId"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(fresh, forKey: key)
        return fresh
    }
}
