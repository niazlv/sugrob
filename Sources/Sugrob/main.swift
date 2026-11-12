import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--selftest") {
    let dir = i + 1 < args.count ? args[i + 1] : FileManager.default.currentDirectoryPath
    exit(SelfTest.run(outDir: dir))
}

if let i = args.firstIndex(of: "--fuzz") {
    let secs = i + 1 < args.count ? Float(args[i + 1]) ?? 120 : 120
    let seed = i + 2 < args.count ? UInt64(args[i + 2]) ?? 1 : 1
    let cell = i + 3 < args.count ? Float(args[i + 3]) ?? 3 : 3
    exit(Fuzz.run(seconds: secs, seed: seed, cell: cell))
}

if let i = args.firstIndex(of: "--people-test") {
    let dir = i + 1 < args.count ? args[i + 1] : FileManager.default.currentDirectoryPath
    exit(PeopleTest.run(outDir: dir, args: Array(args.dropFirst(i + 2))))
}

if let i = args.firstIndex(of: "--wind-test") {
    let dir = i + 1 < args.count ? args[i + 1] : FileManager.default.currentDirectoryPath
    exit(WindTest.run(outDir: dir, args: Array(args.dropFirst(i + 2))))
}

if let i = args.firstIndex(of: "--ax-dump") {
    exit(DesktopIcons.dump(to: i + 1 < args.count ? args[i + 1] : "/dev/stdout"))
}

if args.contains("--version") {
    let i = Bundle.main.infoDictionary
    print("\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))")
    exit(0)
}

if args.contains("--update-now") {
    exit(UpdateCLI.run(relaunch: args.contains("--relaunch")))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
