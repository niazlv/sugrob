// swift-tools-version:5.9
import PackageDescription

// Браузерная сборка Сугроба: то же ядро симуляции, что в приложении, собранное в WebAssembly.
// Исходники ядра не дублируются в репозитории — build.sh копирует их сюда перед сборкой.
let package = Package(
    name: "SugrobWeb",
    targets: [
        .executableTarget(name: "SugrobWeb", path: "Sources/SugrobWeb")
    ]
)
