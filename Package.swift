// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Resize",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Resize", targets: ["Resize"])],
    targets: [
        .target(name: "ResizeKit"),
        .executableTarget(name: "Resize", dependencies: ["ResizeKit"]),
        .testTarget(name: "ResizeKitTests", dependencies: ["ResizeKit"]),
    ]
)
