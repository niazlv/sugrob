// Подпись обновлений Сугроба (Ed25519, CryptoKit).
// release.sh собирает её сам: swiftc -O tools/ota_sign.swift -o .build/ota-sign
//
//   ota-sign keygen                                         создать ключ (один раз)
//   ota-sign pub                                            публичный ключ (он вписан в Updater.swift)
//   ota-sign manifest <zip> <версия> <сборка> <macOS> <что нового> [адрес архива]   update.json в stdout
//   ota-sign verify <update.json> <zip>                     проверить манифест и архив
//
// Ключ лежит в ~/.config/sugrob/ota-ed25519.key (или $SUGROB_OTA_KEY). Установленные
// Сугробы принимают только его подпись: потеряется ключ — обновлять их можно будет
// только вручную. Беречь и держать копию.
import CryptoKit
import Foundation

func die(_ s: String) -> Never {
    FileHandle.standardError.write(Data((s + "\n").utf8))
    exit(1)
}

let usage = """
ota-sign keygen | pub | manifest <zip> <версия> <сборка> <macOS> <что нового> [адрес архива] | verify <update.json> <zip>
"""
let keyURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUGROB_OTA_KEY"]
                 ?? NSString(string: "~/.config/sugrob/ota-ed25519.key").expandingTildeInPath)

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let s = try? String(contentsOf: keyURL, encoding: .utf8),
          let raw = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)),
          let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { die("Нет ключа подписи \(keyURL.path). Создать: ota-sign keygen") }
    return k
}

func hex(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

/// Подписываемое сообщение. Должно совпадать с UpdateManifest.signedMessage в Updater.swift.
func message(build: Int, version: String, sha256: String, size: Int, minOS: String, notes: String) -> Data {
    Data("sugrob-ota-1\n\(build)\n\(version)\n\(sha256)\n\(size)\n\(minOS)\n\(notes)".utf8)
}

let a = CommandLine.arguments
switch a.count > 1 ? a[1] : "" {
case "keygen":
    if FileManager.default.fileExists(atPath: keyURL.path) { die("Ключ уже есть: \(keyURL.path) — не перезаписываю") }
    let k = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    guard FileManager.default.createFile(atPath: keyURL.path,
                                         contents: Data((k.rawRepresentation.base64EncodedString() + "\n").utf8),
                                         attributes: [.posixPermissions: 0o600])
    else { die("Не удалось записать \(keyURL.path)") }
    print(k.publicKey.rawRepresentation.base64EncodedString())

case "pub":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())

case "manifest":
    guard a.count == 7 || a.count == 8, let build = Int(a[4]), build > 0 else { die(usage) }
    let zip = URL(fileURLWithPath: a[2])
    let data = try Data(contentsOf: zip)
    let sha = hex(data)
    let sig = try loadKey().signature(for: message(build: build, version: a[3], sha256: sha, size: data.count,
                                                   minOS: a[5], notes: a[6]))
    let obj: [String: Any] = [
        "version": a[3], "build": build, "url": a.count == 8 ? a[7] : zip.lastPathComponent,
        "size": data.count, "sha256": sha,
        "minimumSystemVersion": a[5], "notes": a[6], "signature": sig.base64EncodedString(),
        "published": ISO8601DateFormatter().string(from: Date()),
    ]
    let json = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    FileHandle.standardOutput.write(json + Data("\n".utf8))

case "verify":
    guard a.count == 4 else { die(usage) }
    let m = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[2]))) as? [String: Any] ?? [:]
    let data = try Data(contentsOf: URL(fileURLWithPath: a[3]))
    guard let version = m["version"] as? String, let build = m["build"] as? Int, let size = m["size"] as? Int,
          let sha = m["sha256"] as? String, let minOS = m["minimumSystemVersion"] as? String,
          let notes = m["notes"] as? String, let sigS = m["signature"] as? String, let sig = Data(base64Encoded: sigS)
    else { die("Манифест неполный") }
    guard size == data.count, sha == hex(data) else { die("Архив не совпадает с манифестом") }
    guard loadKey().publicKey.isValidSignature(sig, for: message(build: build, version: version, sha256: sha, size: size,
                                                                 minOS: minOS, notes: notes))
    else { die("Подпись не сошлась") }
    print("ok \(version) (\(build))")

default:
    die(usage)
}
