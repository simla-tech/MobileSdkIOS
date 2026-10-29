// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ConsultantSdk",
    defaultLocalization: "ru",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Core",
            targets: ["Core"]
        ),
        .library(
            name: "PushService",
            targets: ["PushService"]
        ),
        .library(
            name: "PushNotificationExtension",
            targets: ["PushNotificationExtension"]
        ),
        .library(
            name: "OnlineConsultant",
            targets: ["OnlineConsultant"]
        ),
        .library(
            name: "Recommendations",
            targets: ["Recommendations"]
        ),
        .library(
            name: "Tracker",
            targets: ["Tracker"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.17.0")
    ],
    targets: [
        .target(name: "SQLiteStorage", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "SDKConfiguration"),
        .target(
            name: "Core",
            dependencies: ["SDKConfiguration"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "OnlineConsultant",
            dependencies: ["Core", "SQLiteStorage"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "PushService",
            dependencies: [
                "Core",
                "PushNotificationExtension",
                "SQLiteStorage",
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "FirebaseInstallations", package: "firebase-ios-sdk"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "PushNotificationExtension",
            dependencies: ["SQLiteStorage", "SDKConfiguration"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "Recommendations",
            dependencies: [
                "Core",
                "Tracker"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "Tracker",
            dependencies: ["Core", "SQLiteStorage"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(name: "SQLiteStorageTests", dependencies: ["SQLiteStorage"]),
        .testTarget(
            name: "OnlineConsultantTests",
            dependencies: [
                "Core",
                "SQLiteStorage",
                "OnlineConsultant"
            ]
        ),
        .testTarget(
            name: "ConsultantSdkTests",
            dependencies: ["Core"]
        ),
        .testTarget(
            name: "PushServiceTests",
            dependencies: [
                "Core",
                "SQLiteStorage",
                "PushService",
                "PushNotificationExtension"
            ]
        ),
        .testTarget(
            name: "PushNotificationExtensionTests",
            dependencies: ["PushNotificationExtension"]
        ),
        .testTarget(
            name: "RecommendationsTests",
            dependencies: [
                "Core",
                "Recommendations",
                "Tracker"
            ]
        ),
        .testTarget(
            name: "TrackerTests",
            dependencies: [
                "Core",
                "Tracker"
            ]
        ),
    ]
)
