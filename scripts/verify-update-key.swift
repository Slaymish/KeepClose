import Foundation
import CryptoKit

// Compare a secret seed's public key with the committed app configuration, without printing it.
let seedText = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
guard let seed = Data(base64Encoded: seedText), seed.count == 32 else {
    fputs("Expected a 32-byte Sparkle signing seed.\n", stderr); exit(1)
}
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
let config = try String(contentsOfFile: "project.yml", encoding: .utf8)
let expected = config.split(separator: "\n").first { $0.contains("INFOPLIST_KEY_SUPublicEDKey") }?.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
guard expected == key.publicKey.rawRepresentation.base64EncodedString() else {
    fputs("Sparkle secret does not match the app's public key. Do not rotate it during a release.\n", stderr); exit(1)
}
print("Sparkle signing key matches the app configuration.")
