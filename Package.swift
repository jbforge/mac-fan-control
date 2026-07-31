// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-fan-control",
    platforms: [.macOS(.v14)],
    targets: [
        // Low-level AppleSMC access: sensors, fan telemetry, fan control.
        .target(name: "SMC"),
        // Shared models + daemon socket protocol/client.
        .target(name: "FanCore", dependencies: ["SMC"]),
        // Root daemon that owns the fan control loop.
        .executableTarget(name: "fanctld", dependencies: ["SMC", "FanCore"]),
        // CLI client.
        .executableTarget(name: "fanctl", dependencies: ["SMC", "FanCore"]),
        // Menu bar app.
        .executableTarget(name: "FanControlApp", dependencies: ["SMC", "FanCore"]),
    ]
)
