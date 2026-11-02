import Foundation

/// Jellyfin measures time in .NET ticks: 10,000,000 per second.
public enum Ticks {
    public static let perSecond: Int64 = 10_000_000

    public static func seconds(_ ticks: Int64) -> TimeInterval {
        TimeInterval(ticks) / TimeInterval(perSecond)
    }

    public static func ticks(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * TimeInterval(perSecond)).rounded())
    }
}
