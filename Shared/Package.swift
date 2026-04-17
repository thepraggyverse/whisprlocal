// swift-tools-version: 5.10
// WhisprShared — IPC primitives shared between WhisprLocalApp (main app) and
// WhisprKeyboard (extension). Keep this package small; it loads inside the
// keyboard's 48 MB memory ceiling.

import PackageDescription

let package = Package(
    name: "WhisprShared",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "WhisprShared",
            targets: ["WhisprShared"]
        )
    ],
    targets: [
        .target(
            name: "WhisprShared",
            path: "Sources/WhisprShared"
        ),
        .testTarget(
            name: "WhisprSharedTests",
            dependencies: ["WhisprShared"],
            path: "Tests/WhisprSharedTests"
        )
    ]
)
