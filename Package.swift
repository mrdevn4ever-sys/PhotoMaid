// swift-tools-version: 6.0
import PackageDescription

// PhotoMaidCore: plattformneutrale Domain-Logik (Entscheidungen, Gesten-State-Machine,
// Später-Planung, Undo, Auswahlkorb, Operation-Journal, Free-Limit, Duplikate, Regeln,
// Capabilities). Keine UI, keine Apple-only-Frameworks. Auf Linux und macOS testbar.
//
// swift-crypto wird ausschließlich auf Linux gelinkt, damit dieselbe SHA-256-API wie
// CryptoKit für Tests verfügbar ist. Auf Apple-Plattformen wird CryptoKit verwendet.
let package = Package(
    name: "PhotoMaidCore",
    defaultLocalization: "de",
    // Das App-Target verlangt iOS 27 (project.yml). Das Paket selbst nutzt nur ältere APIs
    // und erlaubt iOS 26, damit CI-Runner ohne iOS-27-SDK den App-Code typprüfen können.
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "PhotoMaidCore", targets: ["PhotoMaidCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    ],
    targets: [
        .target(
            name: "PhotoMaidCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PhotoMaidCoreTests",
            dependencies: ["PhotoMaidCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
