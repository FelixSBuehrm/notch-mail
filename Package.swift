// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchMail",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure logic: state machine, inbox sync, layout, geometry, formatting. No AppKit.
        .target(name: "NotchCore"),
        // Mail providers: Google sign-in, Gmail API, parsing, Keychain. Foundation only.
        .target(name: "MailSources", dependencies: ["NotchCore"]),
        // The menu-bar app: notch panel, SwiftUI views, polling, demo mail.
        .executableTarget(name: "NotchMail", dependencies: ["NotchCore", "MailSources"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
        .testTarget(name: "MailSourcesTests", dependencies: ["MailSources", "NotchCore"]),
    ]
)
