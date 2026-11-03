import Darwin
import Foundation
import JellyfinKit
import Network
import Observation

/// Whether the Mac is on the same network as the Jellyfin server ("at home"), for the home/away quality setting.
/// The server reports its own LAN address; if one of the Mac's addresses is in the same /24, we're home. Nothing
/// leaves the Mac and no location permission is needed. Re-checked whenever the network changes.
@MainActor
@Observable
final class NetworkLocation {
    static let shared = NetworkLocation()

    /// Until the server's LAN address is known this stays true (both qualities default to Original anyway).
    private(set) var isHome = true

    @ObservationIgnored private var serverPrefix: String?
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { _ in
            Task { @MainActor in NetworkLocation.shared.recompute() }
        }
        monitor.start(queue: DispatchQueue(label: "luminary.network-location", qos: .utility))
    }

    /// Learn the server's LAN address (one small request, in the background after sign-in).
    func update(client: JellyfinClient) async {
        if let host = client.serverURL.host, Self.prefix(of: host) != nil {
            serverPrefix = Self.prefix(of: host) // signed in with a LAN address
        } else if let info = try? await client.publicSystemInfo(timeout: 5),
                  let address = info.localAddress, let host = URL(string: address)?.host {
            serverPrefix = Self.prefix(of: host)
        }
        recompute()
    }

    private func recompute() {
        guard let serverPrefix else { return }
        let home = Self.localIPv4Addresses().contains { Self.prefix(of: $0) == serverPrefix }
        if home != isHome { isHome = home }
    }

    /// "192.168.1" for a private IPv4 address, nil for anything else (public IPs, hostnames, IPv6).
    private static func prefix(of host: String) -> String? {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        let isPrivate = parts[0] == 10
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
        return isPrivate ? parts.prefix(3).map(String.init).joined(separator: ".") : nil
    }

    private static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = pointer.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: buffer))
            }
        }
        return result
    }
}
