// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_js",
    platforms: [
        // The host app targets macOS 10.15 (app/macos/Podfile). The upstream
        // podspec still declares 10.11, which SPM would reject against
        // FlutterMacOS's own floor.
        .macOS("10.15")
    ],
    products: [
        // A "_" in the plugin name becomes "-" in the library name.
        .library(name: "flutter-js", targets: ["flutter_js"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_js",
            path: "Sources/flutter_js"
        )
    ]
)
