// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "Harness",
    products: [
        .library(
            name: "Harness",
            targets: ["Harness"]),
    ],
    dependencies: [],
    targets: [
        .systemLibrary(
            name: "CInotify"
        ),
        .systemLibrary(
            name: "CGLib",
            pkgConfig: "glib-2.0"
        ),
        .target(
            name: "Harness",
            dependencies: [
                "CInotify",
                "CGLib",
            ]
        ),
        .testTarget(
            name: "HarnessTests",
            dependencies: ["Harness"]),
    ]
)
