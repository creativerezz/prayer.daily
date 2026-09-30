// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Hilal", platforms: [.macOS(.v14)], products: [.executable(name: "pray.daily", targets: ["Hilal"])], targets: [.executableTarget(name: "Hilal", resources: [.copy("methods.json")])])
