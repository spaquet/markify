// Checks an update archive's EdDSA signature against the app's SUPublicEDKey,
// as Sparkle does before installing, so a release never ships an update that
// installed copies would reject.
//
// Usage: swift verify-update-signature.swift <SUPublicEDKey> <edSignature> <archive>
import CryptoKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: verify-update-signature.swift <public key> <signature> <archive>\n".utf8))
    exit(2)
}
let values = Array(arguments)
guard let keyData = Data(base64Encoded: values[0]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    print("SUPublicEDKey is not an EdDSA public key: \(values[0])")
    exit(1)
}
guard let signature = Data(base64Encoded: values[1]),
      let archive = FileManager.default.contents(atPath: values[2]) else {
    print("Can't read the signature or \(values[2])")
    exit(1)
}
guard key.isValidSignature(signature, for: archive) else {
    print("The signature doesn't match SUPublicEDKey: SPARKLE_PRIVATE_KEY and Info.plist hold different keys.")
    exit(1)
}
print("The update's signature matches SUPublicEDKey.")
