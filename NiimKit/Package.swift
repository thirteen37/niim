// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NiimKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NiimKit", targets: ["NiimKit"])],
    targets: [
        .target(name: "NiimKit"),
        .testTarget(name: "NiimKitTests", dependencies: ["NiimKit"]),
    ],
    swiftLanguageModes: [.v5]  // ponytail: CoreBluetooth delegates vs strict concurrency, move to v6 when CB is Sendable
)
