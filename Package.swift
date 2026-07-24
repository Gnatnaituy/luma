// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Luma",
    platforms: [
        .macOS("14.4")
    ],
    products: [
        .executable(name: "Luma", targets: ["Luma"])
    ],
    targets: [
        .executableTarget(
            name: "Luma",
            path: "Sources/Luma",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Translation")
            ]
        ),
        .testTarget(
            name: "LumaTests",
            dependencies: ["Luma"],
            path: "Tests/LumaTests"
        )
    ]
)
