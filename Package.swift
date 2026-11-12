// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sugrob",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Sugrob", path: "Sources/Sugrob"),
        // Помощник для значков рабочего стола. В приложение кладётся не эта сборка, а замороженная
        // копия из Resources/SugrobIcons.app (см. tools/icons-helper/freeze.sh).
        .executableTarget(name: "SugrobIcons", path: "Sources/SugrobIcons")
    ]
)
