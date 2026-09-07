// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "InterviewAssistant",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "InterviewAssistant",
            path: "Sources/InterviewAssistant"
        )
    ]
)
