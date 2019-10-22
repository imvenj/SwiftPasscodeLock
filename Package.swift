// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PasscodeLock",
    platforms: [.iOS(.v8), .tvOS(.v10)],
    products: [
        .library(
            name: "PasscodeLock",
            targets: ["PasscodeLock"]),
    ],
    targets: [
        .target(
            name: "PasscodeLock",
            path: "PasscodeLock"),
    ],
    swiftLanguageVersions: [.v5]
)
