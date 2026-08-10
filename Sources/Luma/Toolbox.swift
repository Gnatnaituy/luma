import CryptoKit
import Foundation
import Security

enum JSONTool {
    static func format(_ input: String, pretty: Bool) throws -> String {
        let data = Data(input.utf8)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed] : [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        let output = try JSONSerialization.data(withJSONObject: object, options: options)
        return String(decoding: output, as: UTF8.self)
    }

    static func escape(_ input: String) throws -> String {
        let literal = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        guard literal.count >= 2 else { throw JSONToolError.invalidStringLiteral }
        return String(literal.dropFirst().dropLast())
    }

    static func unescape(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let literal: String
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            literal = trimmed
        } else {
            literal = "\"\(input)\""
        }
        return try JSONDecoder().decode(String.self, from: Data(literal.utf8))
    }
}

private enum JSONToolError: LocalizedError {
    case invalidStringLiteral

    var errorDescription: String? {
        L10n.text("无法生成 JSON 字符串", "Unable to generate a JSON string")
    }
}

enum TranslationTarget: Equatable {
    case simplifiedChinese
    case english
}

enum TranslationLanguageDetector {
    static func target(for input: String) -> TranslationTarget? {
        let scalars = input.unicodeScalars
        guard scalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            return nil
        }
        if scalars.contains(where: isChinese) { return .english }
        if scalars.contains(where: { CharacterSet.letters.contains($0) }) { return .simplifiedChinese }
        return nil
    }

    private static func isChinese(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x20000...0x2FA1F:
            true
        default:
            false
        }
    }
}

enum PasswordTool {
    static func generate(length: Int, uppercase: Bool, digits: Bool, symbols: Bool) -> String {
        var alphabet = Array("abcdefghijkmnopqrstuvwxyz")
        if uppercase { alphabet += Array("ABCDEFGHJKLMNPQRSTUVWXYZ") }
        if digits { alphabet += Array("23456789") }
        if symbols { alphabet += Array("!@#$%^&*()-_=+") }
        guard !alphabet.isEmpty else { return "" }

        return String((0..<max(6, min(length, 32))).map { _ in
            alphabet[Int(secureRandomIndex(upperBound: UInt32(alphabet.count)))]
        })
    }

    private static func secureRandomIndex(upperBound: UInt32) -> UInt32 {
        let rejectionLimit = UInt32.max - (UInt32.max % upperBound)
        while true {
            var value: UInt32 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &value) == errSecSuccess else {
                return arc4random_uniform(upperBound)
            }
            if value < rejectionLimit { return value % upperBound }
        }
    }
}

enum CodeTool {
    static func base64Encode(_ input: String) -> String {
        Data(input.utf8).base64EncodedString()
    }

    static func base64Decode(_ input: String) -> String? {
        guard let data = Data(base64Encoded: input, options: .ignoreUnknownCharacters) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func urlEncode(_ input: String) -> String {
        input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
    }

    static func urlDecode(_ input: String) -> String {
        input.removingPercentEncoding ?? input
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
