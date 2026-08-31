// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SunsetBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SolarKit", path: "Sources/SolarKit"),
        .executableTarget(name: "SunsetBar", dependencies: ["SolarKit"], path: "Sources/SunsetBar"),
        // Dumps computed solar times as CSV so they can be diffed against an
        // independent ephemeris. See Tests/verify_solar.py.
        .executableTarget(name: "SolarCheck", dependencies: ["SolarKit"], path: "Sources/SolarCheck"),
    ]
)
