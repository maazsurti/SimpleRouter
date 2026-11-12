// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleRouter",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SimpleRouter", targets: ["SimpleRouter"]),
        .library(name: "SimpleRouterSwiftUI", targets: ["SimpleRouterSwiftUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/maazsurti/Networking.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SimpleRouter",
            dependencies: [.product(name: "Diagnostics", package: "Networking")]
        ),
        .target(
            name: "SimpleRouterSwiftUI",
            dependencies: [.product(name: "Diagnostics", package: "Networking")]
        ),
        .testTarget(
            name: "SimpleRouterTests",
            dependencies: ["SimpleRouter", .product(name: "Diagnostics", package: "Networking")]
        ),
        .testTarget(
            name: "SimpleRouterSwiftUITests",
            dependencies: ["SimpleRouterSwiftUI", .product(name: "Diagnostics", package: "Networking")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
