import ProjectDescription

let project = Project(
    name: "Bart",
    packages: [
        .remote(url: "https://github.com/sparkle-project/Sparkle", requirement: .upToNextMajor(from: "2.6.0")),
    ],
    targets: [
        .target(
            name: "Bart",
            destinations: .macOS,
            product: .app,
            bundleId: "com.mattbond.bart",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .file(path: "Configuration/Bart-Info.plist"),
            sources: ["Sources/Bart/**"],
            resources: ["dist/AppIcon.icns", "Sources/Bart/Resources/**"],
            entitlements: .file(path: "Configuration/Bart.entitlements"),
            dependencies: [.target(name: "BartWidget"), .package(product: "Sparkle")],
            settings: .settings(base: ["SWIFT_VERSION": "5.0", "CODE_SIGNING_ALLOWED": "NO"])
        ),
        .target(
            name: "BartWidget",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "com.mattbond.bart.widget",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .file(path: "Configuration/BartWidget-Info.plist"),
            sources: [
                "Sources/Bart/Models.swift",
                "Sources/Bart/Stations.swift",
                "Sources/Bart/Realtime.swift",
                "Sources/Bart/BARTService.swift",
                "Sources/Bart/SharedBoard.swift",
                "Sources/Bart/TrainStyle.swift",
                "WidgetExtension/BartWidget.swift",
            ],
            entitlements: .file(path: "Configuration/BartWidget.entitlements"),
            settings: .settings(base: ["SWIFT_VERSION": "5.0", "CODE_SIGNING_ALLOWED": "NO"])
        ),
    ]
)
