// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "pray.daily", platforms: [.macOS(.v14)], products: [.executable(name: "pray.daily", targets: ["PrayDaily"])], targets: [.executableTarget(name: "PrayDaily", resources: [.copy("methods.json")])])
