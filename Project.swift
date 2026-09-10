import ProjectDescription

let bundleIdPrefix = "com.roomy.mac"

let infoPlist: [String: Plist.Value] = [
    "CFBundleShortVersionString": "1.0",
    "CFBundleVersion": "1",
    "NSHumanReadableCopyright": "Copyright © 2026 Roomy.",
    "LSApplicationCategoryType": "public.app-category.utilities",
    "NSAppleEventsUsageDescription": "Roomy asks Finder to empty the Trash when you tap Empty Trash.",
]

let target = Target(
    name: "Roomy",
    platform: .macOS,
    product: .app,
    bundleId: bundleIdPrefix,
    deploymentTarget: .macOS(targetVersion: "14.0"),
    infoPlist: .extendingDefault(with: infoPlist),
    sources: ["Sources/**"],
    resources: ["Resources/**"],
    entitlements: .file(path: "Roomy.entitlements"),
    settings: .settings(
        base: [
            "ARCHS": "arm64",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "CODE_SIGN_STYLE": "Manual",
        ],
        configurations: [
            .debug(name: .debug, settings: [
                "CODE_SIGN_IDENTITY": "Roomy Local Dev",
                "DEVELOPMENT_TEAM": "",
            ]),
            .release(name: .release, settings: [
                "CODE_SIGN_IDENTITY": "Developer ID Application",
                "DEVELOPMENT_TEAM": "",
                "ENABLE_HARDENED_RUNTIME": "YES",
            ]),
            .release(name: .configuration("LocalRelease"), settings: [
                "CODE_SIGN_IDENTITY": "Roomy Local Dev",
                "DEVELOPMENT_TEAM": "",
            ]),
        ]
    )
)

let testTarget = Target(
    name: "RoomyTests",
    platform: .macOS,
    product: .unitTests,
    bundleId: "\(bundleIdPrefix).Tests",
    deploymentTarget: .macOS(targetVersion: "14.0"),
    infoPlist: .default,
    sources: ["Tests/**"],
    dependencies: [.target(name: "Roomy")]
)

let project = Project(
    name: "Roomy",
    organizationName: "Roomy",
    options: .options(disableSynthesizedResourceAccessors: true),
    settings: .settings(configurations: [
        .debug(name: .debug),
        .release(name: .release),
        .release(name: .configuration("LocalRelease")),
    ]),
    targets: [target, testTarget],
    schemes: [
        Scheme(
            name: "Roomy",
            shared: true,
            buildAction: .buildAction(targets: ["Roomy"]),
            testAction: .targets(["RoomyTests"]),
            runAction: .runAction(executable: "Roomy")
        ),
        Scheme(
            name: "Roomy (Fast)",
            shared: true,
            buildAction: .buildAction(targets: ["Roomy"]),
            runAction: .runAction(configuration: .configuration("LocalRelease"), executable: "Roomy")
        ),
    ]
)
