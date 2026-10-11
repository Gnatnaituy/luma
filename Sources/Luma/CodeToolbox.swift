import CryptoKit
import Foundation

enum CodeToolboxError: LocalizedError {
    case invalidBase64
    case invalidHex
    case invalidUTF8
    case invalidUnicodeEscape
    case invalidTimestamp
    case invalidDate
    case nothingToDo

    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            L10n.text("不是合法的 Base64", "Not valid Base64")
        case .invalidHex:
            L10n.text("不是合法的十六进制（长度需为偶数）", "Not valid hexadecimal (the length must be even)")
        case .invalidUTF8:
            L10n.text("解码结果不是 UTF-8 文本", "The decoded bytes are not UTF-8 text")
        case .invalidUnicodeEscape:
            L10n.text("没有找到可解析的 \\uXXXX 转义", "No \\uXXXX escape to decode")
        case .invalidTimestamp:
            L10n.text("请输入 Unix 时间戳（秒或毫秒）", "Enter a Unix timestamp in seconds or milliseconds")
        case .invalidDate:
            L10n.text(
                "无法识别日期，试试 2024-05-01 或 2024-05-01T12:00:00Z",
                "Unrecognized date; try 2024-05-01 or 2024-05-01T12:00:00Z"
            )
        case .nothingToDo:
            L10n.text("先输入要处理的文本", "Enter some text first")
        }
    }
}

/// 编码小助手的工具分组；分组只影响界面上一次显示多少个按钮。
enum CodeToolboxCategory: String, CaseIterable, Identifiable {
    case json
    case encoding
    case hashing
    case naming
    case generate
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: "JSON"
        case .encoding: L10n.text("编码", "Encoding")
        case .hashing: L10n.text("哈希", "Hashing")
        case .naming: L10n.text("命名", "Naming")
        case .generate: L10n.text("生成", "Generate")
        case .text: L10n.text("文本", "Text")
        }
    }

    var tools: [CodeToolboxTool] {
        CodeToolboxTool.allCases.filter { $0.category == self }
    }
}

/// 合并「JSON 编辑器」后的全部文本工具。每个工具都是「输入 → 输出」的纯变换，
/// 集中在这里便于单测，界面只负责选择工具与展示结果。
enum CodeToolboxTool: String, CaseIterable, Identifiable {
    case jsonFormat
    case jsonMinify
    case jsonEscape
    case jsonUnescape
    case base64Encode
    case base64Decode
    case urlEncode
    case urlDecode
    case hexEncode
    case hexDecode
    case unicodeEscape
    case unicodeUnescape
    case sha256
    case sha512
    case sha1
    case md5
    case camelCase
    case pascalCase
    case snakeCase
    case kebabCase
    case constantCase
    case uuid
    case timestampToDate
    case dateToTimestamp
    case sortLines
    case dedupeLines
    case reverseLines
    case removeEmptyLines

    var id: String { rawValue }

    var category: CodeToolboxCategory {
        switch self {
        case .jsonFormat, .jsonMinify, .jsonEscape, .jsonUnescape:
            .json
        case .base64Encode, .base64Decode, .urlEncode, .urlDecode,
             .hexEncode, .hexDecode, .unicodeEscape, .unicodeUnescape:
            .encoding
        case .sha256, .sha512, .sha1, .md5:
            .hashing
        case .camelCase, .pascalCase, .snakeCase, .kebabCase, .constantCase:
            .naming
        case .uuid, .timestampToDate, .dateToTimestamp:
            .generate
        case .sortLines, .dedupeLines, .reverseLines, .removeEmptyLines:
            .text
        }
    }

    var title: String {
        switch self {
        case .jsonFormat: L10n.text("格式化", "Format")
        case .jsonMinify: L10n.text("压缩", "Minify")
        case .jsonEscape: L10n.text("转义", "Escape")
        case .jsonUnescape: L10n.text("去转义", "Unescape")
        case .base64Encode: L10n.text("Base64 编码", "Base64 Encode")
        case .base64Decode: L10n.text("Base64 解码", "Base64 Decode")
        case .urlEncode: L10n.text("URL 编码", "URL Encode")
        case .urlDecode: L10n.text("URL 解码", "URL Decode")
        case .hexEncode: L10n.text("Hex 编码", "Hex Encode")
        case .hexDecode: L10n.text("Hex 解码", "Hex Decode")
        case .unicodeEscape: L10n.text("Unicode 转义", "Unicode Escape")
        case .unicodeUnescape: L10n.text("Unicode 去转义", "Unicode Unescape")
        case .sha256: "SHA-256"
        case .sha512: "SHA-512"
        case .sha1: "SHA-1"
        case .md5: "MD5"
        case .camelCase: "camelCase"
        case .pascalCase: "PascalCase"
        case .snakeCase: "snake_case"
        case .kebabCase: "kebab-case"
        case .constantCase: "CONSTANT_CASE"
        case .uuid: L10n.text("UUID v4", "UUID v4")
        case .timestampToDate: L10n.text("时间戳 → 日期", "Timestamp → Date")
        case .dateToTimestamp: L10n.text("日期 → 时间戳", "Date → Timestamp")
        case .sortLines: L10n.text("排序行", "Sort Lines")
        case .dedupeLines: L10n.text("去重行", "Dedupe Lines")
        case .reverseLines: L10n.text("反转行", "Reverse Lines")
        case .removeEmptyLines: L10n.text("去空行", "Remove Empty Lines")
        }
    }

    /// 生成类工具不读输入，输入为空时也能点。
    var ignoresInput: Bool { self == .uuid }

    func apply(to input: String) throws -> String {
        switch self {
        case .jsonFormat: return try JSONTool.format(input, pretty: true)
        case .jsonMinify: return try JSONTool.format(input, pretty: false)
        case .jsonEscape: return try JSONTool.escape(input)
        case .jsonUnescape: return try JSONTool.unescape(input)
        case .base64Encode: return CodeTool.base64Encode(input)
        case .base64Decode:
            guard let value = CodeTool.base64Decode(input) else { throw CodeToolboxError.invalidBase64 }
            return value
        case .urlEncode: return CodeTool.urlEncode(input)
        case .urlDecode: return CodeTool.urlDecode(input)
        case .hexEncode: return CodeTool.hexEncode(input)
        case .hexDecode: return try CodeTool.hexDecode(input)
        case .unicodeEscape: return CodeTool.unicodeEscape(input)
        case .unicodeUnescape: return try CodeTool.unicodeUnescape(input)
        case .sha256: return CodeTool.sha256(input)
        case .sha512: return CodeTool.sha512(input)
        case .sha1: return CodeTool.sha1(input)
        case .md5: return CodeTool.md5(input)
        case .camelCase: return CodeTool.camelCase(input)
        case .pascalCase: return CodeTool.pascalCase(input)
        case .snakeCase: return CodeTool.snakeCase(input)
        case .kebabCase: return CodeTool.kebabCase(input)
        case .constantCase: return CodeTool.constantCase(input)
        case .uuid: return UUID().uuidString
        case .timestampToDate: return try CodeTool.timestampToDate(input)
        case .dateToTimestamp: return try CodeTool.dateToTimestamp(input)
        case .sortLines: return CodeTool.sortedLines(input)
        case .dedupeLines: return CodeTool.dedupedLines(input)
        case .reverseLines: return CodeTool.reversedLines(input)
        case .removeEmptyLines: return CodeTool.linesWithoutBlanks(input)
        }
    }
}

extension CodeTool {
    // MARK: - 哈希

    static func sha512(_ input: String) -> String {
        digest(SHA512.hash(data: Data(input.utf8)))
    }

    static func sha1(_ input: String) -> String {
        digest(Insecure.SHA1.hash(data: Data(input.utf8)))
    }

    static func md5(_ input: String) -> String {
        digest(Insecure.MD5.hash(data: Data(input.utf8)))
    }

    private static func digest<D: Digest>(_ value: D) -> String {
        value.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 十六进制

    static func hexEncode(_ input: String) -> String {
        Data(input.utf8).map { String(format: "%02x", $0) }.joined()
    }

    /// 允许空白分隔与 `0x` 前缀，长度必须为偶数。
    static func hexDecode(_ input: String) throws -> String {
        var cleaned = input.filter { !$0.isWhitespace }
        if cleaned.lowercased().hasPrefix("0x") { cleaned.removeFirst(2) }
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2),
              cleaned.allSatisfy(\.isHexDigit) else {
            throw CodeToolboxError.invalidHex
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw CodeToolboxError.invalidHex
            }
            bytes.append(byte)
            index = next
        }
        guard let value = String(bytes: bytes, encoding: .utf8) else {
            throw CodeToolboxError.invalidUTF8
        }
        return value
    }

    // MARK: - Unicode 转义

    /// 只转义非 ASCII 字符，ASCII 原样保留，补充平面写成代理对。
    static func unicodeEscape(_ input: String) -> String {
        var output = ""
        for scalar in input.unicodeScalars {
            if scalar.isASCII {
                output.unicodeScalars.append(scalar)
            } else if scalar.value > 0xFFFF {
                let value = scalar.value - 0x10000
                output += String(format: "\\u%04X\\u%04X", 0xD800 + (value >> 10), 0xDC00 + (value & 0x3FF))
            } else {
                output += String(format: "\\u%04X", scalar.value)
            }
        }
        return output
    }

    static func unicodeUnescape(_ input: String) throws -> String {
        var scalars = String.UnicodeScalarView()
        var index = input.startIndex
        var didDecode = false

        while index < input.endIndex {
            let character = input[index]
            if character == "\\", let decoded = escape(in: input, at: index) {
                scalars.append(decoded.scalar)
                index = decoded.end
                didDecode = true
                continue
            }
            scalars.append(contentsOf: String(character).unicodeScalars)
            index = input.index(after: index)
        }

        guard didDecode else { throw CodeToolboxError.invalidUnicodeEscape }
        return String(scalars)
    }

    /// 解析 `\uXXXX`；高代理项后面紧跟低代理项时合并成一个补充平面字符。
    private static func escape(
        in input: String,
        at index: String.Index
    ) -> (scalar: Unicode.Scalar, end: String.Index)? {
        guard let hexStart = input.index(index, offsetBy: 2, limitedBy: input.endIndex),
              input[input.index(after: index)] == "u",
              let hexEnd = input.index(hexStart, offsetBy: 4, limitedBy: input.endIndex),
              let value = UInt32(input[hexStart..<hexEnd], radix: 16) else { return nil }

        if (0xD800...0xDBFF).contains(value) {
            let lowStart = hexEnd
            if input[lowStart...].hasPrefix("\\u"),
               let lowHexStart = input.index(lowStart, offsetBy: 2, limitedBy: input.endIndex),
               let lowEnd = input.index(lowHexStart, offsetBy: 4, limitedBy: input.endIndex),
               let low = UInt32(input[lowHexStart..<lowEnd], radix: 16),
               (0xDC00...0xDFFF).contains(low),
               let scalar = Unicode.Scalar(0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)) {
                return (scalar, lowEnd)
            }
        }

        guard let scalar = Unicode.Scalar(value) else { return nil }
        return (scalar, hexEnd)
    }

    // MARK: - 命名转换

    /// 拆词：先按非字母数字切分，再在 camelCase 边界和连续大写（HTTP、ID）之间切开。
    static func words(in input: String) -> [String] {
        var result: [String] = []
        for chunk in input.components(separatedBy: CharacterSet.alphanumerics.inverted) where !chunk.isEmpty {
            let characters = Array(chunk)
            var current = ""
            for (index, character) in characters.enumerated() {
                let previousIsLowerOrDigit = index > 0
                    && (characters[index - 1].isLowercase || characters[index - 1].isNumber)
                let nextIsLower = index + 1 < characters.count && characters[index + 1].isLowercase
                if character.isUppercase, !current.isEmpty, previousIsLowerOrDigit || nextIsLower {
                    result.append(current)
                    current = ""
                }
                current.append(character)
            }
            if !current.isEmpty { result.append(current) }
        }
        return result.map { $0.lowercased() }
    }

    static func camelCase(_ input: String) -> String {
        let parts = words(in: input)
        guard let first = parts.first else { return "" }
        return first + parts.dropFirst().map(capitalized).joined()
    }

    static func pascalCase(_ input: String) -> String {
        words(in: input).map(capitalized).joined()
    }

    static func snakeCase(_ input: String) -> String {
        words(in: input).joined(separator: "_")
    }

    static func kebabCase(_ input: String) -> String {
        words(in: input).joined(separator: "-")
    }

    static func constantCase(_ input: String) -> String {
        words(in: input).joined(separator: "_").uppercased()
    }

    private static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    // MARK: - 时间戳

    /// 13 位以上按毫秒处理，输出带时区偏移的 ISO 8601。
    static func timestampToDate(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Double(trimmed) else { throw CodeToolboxError.invalidTimestamp }
        let seconds = abs(raw) >= 1e11 ? raw / 1000 : raw
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    static func dateToTimestamp(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = parseDate(trimmed) else { throw CodeToolboxError.invalidDate }
        return String(Int(date.timeIntervalSince1970))
    }

    private static func parseDate(_ input: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: input) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: input) { return date }

        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: input) { return date }
        }
        return nil
    }

    // MARK: - 行处理

    static func sortedLines(_ input: String) -> String {
        let parts = lineParts(input)
        let sorted = parts.lines.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return joined(sorted, trailingNewline: parts.trailingNewline)
    }

    static func dedupedLines(_ input: String) -> String {
        var seen = Set<String>()
        let parts = lineParts(input)
        let unique = parts.lines.filter { seen.insert($0).inserted }
        return joined(unique, trailingNewline: parts.trailingNewline)
    }

    static func reversedLines(_ input: String) -> String {
        let parts = lineParts(input)
        return joined(parts.lines.reversed(), trailingNewline: parts.trailingNewline)
    }

    static func linesWithoutBlanks(_ input: String) -> String {
        let parts = lineParts(input)
        let kept = parts.lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return joined(kept, trailingNewline: parts.trailingNewline)
    }

    /// 统一按 `\n` 处理，并记住原文是否以换行结尾，避免排序时把末尾空行排到最前面。
    private static func lineParts(_ input: String) -> (lines: [String], trailingNewline: Bool) {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        let trailingNewline = lines.count > 1 && lines.last == ""
        if trailingNewline { lines.removeLast() }
        return (lines, trailingNewline)
    }

    private static func joined<S: Sequence>(_ lines: S, trailingNewline: Bool) -> String
    where S.Element == String {
        let text = lines.joined(separator: "\n")
        return trailingNewline ? text + "\n" : text
    }
}
