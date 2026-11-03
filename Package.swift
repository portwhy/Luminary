// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Luminary",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Luminary", targets: ["Luminary"]),
        .library(name: "JellyfinKit", targets: ["JellyfinKit"]),
    ],
    dependencies: [
        // libmpv + FFmpeg + libass + libplacebo + MoltenVK as prebuilt xcframeworks.
        .package(url: "https://github.com/mpvkit/MPVKit.git", exact: "1.0.0"),
        // In-app updates (Luminary → Check for Updates…), signed with our own EdDSA key.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Pure networking + models. No UI imports, so it stays fast to build and easy to test.
        .target(
            name: "JellyfinKit",
            path: "Sources/JellyfinKit"
        ),
        // The SwiftUI app.
        .executableTarget(
            name: "Luminary",
            dependencies: [
                "JellyfinKit",
                .product(name: "MPVKit-GPL", package: "MPVKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Luminary",
            // Sparkle.framework is embedded in Luminary.app/Contents/Frameworks (scripts/make-app.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "JellyfinKitTests",
            dependencies: ["JellyfinKit"],
            path: "Tests/JellyfinKitTests"
        ),
    ]
)
