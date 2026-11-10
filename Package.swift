// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Planificador",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Planificador", targets: ["Planificador"])],
    targets: [
        .executableTarget(name: "Planificador", path: "Sources/Planificador")
    ]
)
