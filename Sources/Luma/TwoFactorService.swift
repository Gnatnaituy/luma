import AppKit
import Combine
import CryptoKit
import Foundation
import Security
import UniformTypeIdentifiers
import Vision

// MARK: - 算法

enum TOTPAlgorithm: String, CaseIterable, Codable, Identifiable {
    case sha1
    case sha256
    case sha512

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    /// otpauth 链接里的算法名。未知取值按规范默认 SHA-1 处理（`SHA-1`、`sha_1` 同样识别）。
    static func named(_ raw: String?) -> TOTPAlgorithm {
        guard let raw else { return .sha1 }
        let normalized = raw
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return TOTPAlgorithm(rawValue: normalized) ?? .sha1
    }
}

// MARK: - Base32

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// 归一化密钥：大写并去掉空格、连字符与填充，便于比较与保存。
    static func normalized(_ text: String) -> String {
        text.uppercased().filter { character in
            !character.isWhitespace && character != "-" && character != "="
        }
    }

    /// 解码 Base32（RFC 4648，容忍小写、空格、连字符与填充）。
    static func decode(_ text: String) -> Data? {
        var buffer = 0
        var bits = 0
        var output = Data()
        for character in normalized(text) {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> bits) & 0xFF))
                buffer &= (1 << bits) - 1
            }
        }
        return output.isEmpty ? nil : output
    }
}

// MARK: - 验证码生成

enum TOTPGenerator {
    /// 密钥长度下限（80 位）：再短的密钥几乎都是输入错误。
    static let minimumSecretBytes = 10
    static let allowedDigits = 4...10
    static let allowedPeriods = 1...600

    static func counter(at date: Date, period: Int) -> UInt64 {
        let interval = max(0, date.timeIntervalSince1970)
        return UInt64(interval / Double(max(1, period)))
    }

    /// RFC 4226 的 HMAC 截断。
    static func hotp(
        secret: Data,
        counter: UInt64,
        algorithm: TOTPAlgorithm,
        digits: Int
    ) -> String {
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let key = SymmetricKey(data: secret)
        let digest: Data
        switch algorithm {
        case .sha1: digest = Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: digest = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: digest = Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }

        let bytes = [UInt8](digest)
        let offset = Int(bytes[bytes.count - 1] & 0x0F)
        let truncated = (UInt32(bytes[offset] & 0x7F) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])

        let count = min(max(digits, allowedDigits.lowerBound), allowedDigits.upperBound)
        var modulus: UInt32 = 1
        for _ in 0..<count { modulus *= 10 }
        return String(format: "%0\(count)d", truncated % modulus)
    }

    /// RFC 6238 的 TOTP。
    static func code(
        secret: Data,
        algorithm: TOTPAlgorithm,
        digits: Int,
        period: Int,
        at date: Date
    ) -> String {
        hotp(
            secret: secret,
            counter: counter(at: date, period: period),
            algorithm: algorithm,
            digits: digits
        )
    }

    static func remainingSeconds(period: Int, at date: Date) -> Int {
        let length = max(1, period)
        let elapsed = Int(max(0, date.timeIntervalSince1970))
        return length - (elapsed % length)
    }

    /// 当前周期已经走完的比例，用于倒计时环。
    static func progress(period: Int, at date: Date) -> Double {
        let length = max(1, period)
        return Double(length - remainingSeconds(period: period, at: date)) / Double(length)
    }

    /// 六位验证码按 `123 456` 分组，八位按 `1234 5678` 分组，便于核对。
    static func grouped(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }
}

// MARK: - otpauth 链接

struct TwoFactorAccountDraft: Equatable {
    var issuer: String
    var name: String
    var secret: String
    var algorithm: TOTPAlgorithm = .sha1
    var digits: Int = 6
    var period: Int = 30

    var normalizedSecret: String { Base32.normalized(secret) }

    /// 与 `TwoFactorAccount` 一致的展示文案，用于导入结果与表单预览。
    var displayTitle: String { issuer.isEmpty ? name : issuer }

    var displaySubtitle: String {
        name == displayTitle ? detailText : "\(name) · \(detailText)"
    }

    var detailText: String {
        L10n.text(
            "\(algorithm.title) · \(digits) 位 · \(period) 秒",
            "\(algorithm.title) · \(digits) digits · \(period)s"
        )
    }

    /// 手动输入与链接导入共用的校验：密钥可解码、参数在允许范围内、标题非空。
    func validated() -> Result<TwoFactorAccountDraft, OTPAuthImportError> {
        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmedIssuer.isEmpty && trimmedName.isEmpty) else { return .failure(.missingLabel) }
        guard let secretData = Base32.decode(secret) else { return .failure(.invalidSecret) }
        guard secretData.count >= TOTPGenerator.minimumSecretBytes else { return .failure(.secretTooShort) }
        guard TOTPGenerator.allowedDigits.contains(digits) else { return .failure(.invalidDigits) }
        guard TOTPGenerator.allowedPeriods.contains(period) else { return .failure(.invalidPeriod) }

        var draft = self
        draft.issuer = trimmedIssuer
        draft.name = trimmedName.isEmpty ? trimmedIssuer : trimmedName
        draft.secret = Base32.normalized(secret)
        return .success(draft)
    }
}

enum OTPAuthImportError: Error, Equatable, LocalizedError {
    case missingLink
    case migrationNotSupported
    case counterBasedNotSupported
    case missingSecret
    case invalidSecret
    case secretTooShort
    case invalidDigits
    case invalidPeriod
    case missingLabel

    var errorDescription: String? {
        switch self {
        case .missingLink:
            L10n.text("没有识别到 otpauth:// 链接", "No otpauth:// link was found")
        case .migrationNotSupported:
            L10n.text(
                "这是 Google Authenticator 迁移二维码，暂不支持，请在原应用中逐个查看密钥",
                "This is a Google Authenticator migration code, which is not supported yet. Read each secret in the original app instead"
            )
        case .counterBasedNotSupported:
            L10n.text("暂不支持基于计数器的 HOTP 账户", "Counter-based HOTP accounts are not supported yet")
        case .missingSecret:
            L10n.text("链接缺少 secret 参数", "The link has no secret parameter")
        case .invalidSecret:
            L10n.text("密钥不是合法的 Base32 字符串", "The secret is not valid Base32")
        case .secretTooShort:
            L10n.text("密钥太短，请检查是否复制完整", "The secret is too short. Check that it was copied completely")
        case .invalidDigits:
            L10n.text("验证码位数需要在 4 到 10 之间", "Code length must be between 4 and 10 digits")
        case .invalidPeriod:
            L10n.text("刷新周期需要在 1 到 600 秒之间", "The refresh period must be between 1 and 600 seconds")
        case .missingLabel:
            L10n.text("请填写发行方或账户名", "Enter an issuer or account name")
        }
    }
}

enum OTPAuthURIParser {
    static let scheme = "otpauth://"
    static let migrationScheme = "otpauth-migration://"

    /// 从任意文本（粘贴内容、二维码载荷或导出文件）中取出第一条 otpauth 链接。
    static func firstLink(in text: String) -> String? {
        links(in: text).first
    }

    /// 取出文本里的全部 otpauth 链接。
    ///
    /// Ente Auth 的明文导出是每行一条 `otpauth://` 链接，Aegis、2FAS 等导出里也常把链接
    /// 作为字段值，所以按「以空白分隔的 token」逐个扫描，比按行切分更宽容。
    static func links(in text: String) -> [String] {
        var links: [String] = []
        var remainder = Substring(text)
        while let range = remainder.range(of: "otpauth", options: [.caseInsensitive]) {
            let candidate = remainder[range.lowerBound...]
            let end = candidate.firstIndex(where: \.isWhitespace) ?? candidate.endIndex
            let token = String(candidate[candidate.startIndex..<end])
            let lowercased = token.lowercased()
            if lowercased.hasPrefix(scheme) || lowercased.hasPrefix(migrationScheme) {
                links.append(token)
            }
            remainder = candidate[end...]
        }
        return links
    }

    static func draft(from raw: String) -> Result<TwoFactorAccountDraft, OTPAuthImportError> {
        guard let link = firstLink(in: raw) else { return .failure(.missingLink) }
        let lowercased = link.lowercased()
        guard !lowercased.hasPrefix(migrationScheme) else { return .failure(.migrationNotSupported) }
        guard lowercased.hasPrefix(scheme) else { return .failure(.missingLink) }

        let body = String(link.dropFirst(scheme.count))
        let segments = body.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let labelPath = String(segments[0])
        let query = segments.count > 1 ? String(segments[1]) : ""

        let pathParts = labelPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let type = pathParts.first?.lowercased() ?? ""
        guard type == "totp" || type == "hotp" else { return .failure(.missingLink) }
        guard type == "totp" else { return .failure(.counterBasedNotSupported) }

        let label = decodeComponent(pathParts.count > 1 ? String(pathParts[1]) : "")
        let parameters = self.parameters(in: query)

        guard let rawSecret = parameters["secret"], !rawSecret.isEmpty else {
            return .failure(.missingSecret)
        }

        var digits = 6
        if let rawDigits = parameters["digits"], !rawDigits.isEmpty {
            guard let value = Int(rawDigits) else { return .failure(.invalidDigits) }
            digits = value
        }

        var period = 30
        if let rawPeriod = parameters["period"], !rawPeriod.isEmpty {
            guard let value = Int(rawPeriod) else { return .failure(.invalidPeriod) }
            period = value
        }

        let labelIssuer: String
        let labelName: String
        if let colon = label.firstIndex(of: ":") {
            labelIssuer = String(label[label.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            labelName = String(label[label.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            labelIssuer = ""
            labelName = label.trimmingCharacters(in: .whitespaces)
        }

        let queryIssuer = parameters["issuer"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let draft = TwoFactorAccountDraft(
            issuer: queryIssuer.isEmpty ? labelIssuer : queryIssuer,
            name: labelName,
            secret: rawSecret,
            algorithm: TOTPAlgorithm.named(parameters["algorithm"]),
            digits: digits,
            period: period
        )
        return draft.validated()
    }

    static func parameters(in query: String) -> [String: String] {
        var parameters: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = pieces.first else { continue }
            let key = decodeComponent(String(rawKey)).lowercased()
            let value = pieces.count > 1 ? decodeComponent(String(pieces[1])) : ""
            if parameters[key] == nil { parameters[key] = value }
        }
        return parameters
    }

    static func decodeComponent(_ text: String) -> String {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text
    }
}

// MARK: - 密钥存储

protocol TwoFactorSecretStoring {
    func secret(for id: UUID) -> String
    @discardableResult func setSecret(_ secret: String, for id: UUID) -> Bool
    @discardableResult func removeSecret(for id: UUID) -> Bool
    /// 密钥当前是否可读。钥匙串条目因为重新签名而等待授权时为 false。
    var isAvailable: Bool { get }
}

extension TwoFactorSecretStoring {
    var isAvailable: Bool { true }
}

/// 钥匙串条目里的 `{账户 id: 密钥}` 映射。
enum TwoFactorSecretArchive {
    static func encode(_ secrets: [UUID: String]) -> Data {
        let payload = Dictionary(uniqueKeysWithValues: secrets.map { ($0.key.uuidString, $0.value) })
        return (try? JSONEncoder().encode(payload)) ?? Data()
    }

    static func decode(_ data: Data) -> [UUID: String]? {
        guard let payload = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        var secrets: [UUID: String] = [:]
        for (key, value) in payload {
            guard let id = UUID(uuidString: key) else { continue }
            secrets[id] = value
        }
        return secrets
    }
}

/// 全部密钥合并成一个钥匙串条目。
///
/// 每个账户一个条目时，`install-app.sh` 每次重新构建都会改变 ad-hoc 签名，钥匙串 ACL 随之
/// 失配，读 25 个账户就要授权 25 次；合并成一条后重新授权最多发生一次（与 AI API Key 相同）。
/// 代价是读取失败时不能安全地做增量写入，因此读失败会让写入一并失败，由调用方如实报告，
/// 而不是用一份空表覆盖掉已经存在的密钥。
final class KeychainTwoFactorSecretStore: TwoFactorSecretStoring {
    private let service = "app.luma.launcher.two-factor"
    private let account = "secrets"

    private var cached: [UUID: String]?
    private var didFailToLoad = false

    var isAvailable: Bool { cached != nil || !didFailToLoad }

    func secret(for id: UUID) -> String {
        load()[id] ?? ""
    }

    @discardableResult
    func setSecret(_ secret: String, for id: UUID) -> Bool {
        var secrets = load()
        if secret.isEmpty {
            guard secrets[id] != nil else { return true }
            secrets[id] = nil
        } else {
            secrets[id] = secret
        }
        return persist(secrets)
    }

    @discardableResult
    func removeSecret(for id: UUID) -> Bool {
        var secrets = load()
        guard secrets[id] != nil else { return true }
        secrets[id] = nil
        return persist(secrets)
    }

    private func load() -> [UUID: String] {
        if let cached { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, let secrets = TwoFactorSecretArchive.decode(data) else {
                didFailToLoad = true
                return [:]
            }
            cached = secrets
            didFailToLoad = false
            return secrets
        case errSecItemNotFound:
            cached = [:]
            didFailToLoad = false
            return [:]
        default:
            // 不缓存空结果：用户完成授权后下一次读取会重新尝试。
            didFailToLoad = true
            return [:]
        }
    }

    private func persist(_ secrets: [UUID: String]) -> Bool {
        guard !didFailToLoad else { return false }
        let data = TwoFactorSecretArchive.encode(secrets)
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // 应用刚被替换、重新签名后，钥匙串访问可能瞬时失败（实测一次 25 条的批量导入有 9 条
        // 写入失败，重跑同一文件即全部成功），因此失败后重试一次，两次都失败才上报。
        var status = errSecSuccess
        for attempt in 0..<2 {
            status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = key
                item[kSecValueData as String] = data
                status = SecItemAdd(item as CFDictionary, nil)
            }
            if status == errSecSuccess {
                cached = secrets
                return true
            }
            if attempt == 0 { Thread.sleep(forTimeInterval: 0.05) }
        }
        NSLog("Luma two-factor keychain write failed: %d", status)
        return false
    }
}

final class InMemoryTwoFactorSecretStore: TwoFactorSecretStoring {
    private var values: [UUID: String] = [:]

    func secret(for id: UUID) -> String { values[id] ?? "" }

    @discardableResult
    func setSecret(_ secret: String, for id: UUID) -> Bool {
        if secret.isEmpty { return removeSecret(for: id) }
        values[id] = secret
        return true
    }

    @discardableResult
    func removeSecret(for id: UUID) -> Bool {
        values[id] = nil
        return true
    }
}

// MARK: - 账户

struct TwoFactorAccount: Codable, Equatable, Identifiable {
    let id: UUID
    var issuer: String
    var name: String
    var algorithm: TOTPAlgorithm
    var digits: Int
    var period: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        issuer: String,
        name: String,
        algorithm: TOTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.createdAt = createdAt
    }

    init(id: UUID = UUID(), draft: TwoFactorAccountDraft, createdAt: Date = Date()) {
        self.init(
            id: id,
            issuer: draft.issuer,
            name: draft.name,
            algorithm: draft.algorithm,
            digits: draft.digits,
            period: draft.period,
            createdAt: createdAt
        )
    }

    /// 列表主标题：优先发行方，没有发行方时退回账户名。
    var title: String { issuer.isEmpty ? name : issuer }

    /// 副标题：发行方与账户名相同时不重复展示。
    var subtitle: String { issuer.isEmpty || issuer == name ? "" : name }

    var detailText: String {
        L10n.text(
            "\(algorithm.title) · \(digits) 位 · \(period) 秒",
            "\(algorithm.title) · \(digits) digits · \(period)s"
        )
    }

    var initial: String {
        String(title.prefix(1)).uppercased()
    }

    func matches(_ query: String) -> Bool {
        let value = query.lowercased()
        return issuer.lowercased().contains(value)
            || name.lowercased().contains(value)
            || detailText.lowercased().contains(value)
    }
}

// MARK: - 账户存储

@MainActor
final class TwoFactorStore: ObservableObject {
    enum AddOutcome: Equatable {
        case added(TwoFactorAccount)
        /// 账户已存在但密钥丢失，这次把密钥补了回来。
        case restored(TwoFactorAccount)
        case duplicate(TwoFactorAccount)
        case failed
    }

    @Published private(set) var accounts: [TwoFactorAccount] = []
    /// 复制验证码后自动收起面板，默认开启：符合启动器「取码即走」的用法。
    @Published var autoDismissesAfterCopy: Bool {
        didSet { defaults.set(autoDismissesAfterCopy, forKey: autoDismissKey) }
    }
    /// 剩余时间不足时把验证码与倒计时环标红。
    @Published var highlightsExpiringCodes: Bool {
        didSet { defaults.set(highlightsExpiringCodes, forKey: highlightKey) }
    }

    private let defaults: UserDefaults
    private let secrets: TwoFactorSecretStoring
    private let accountsKey = "luma.twofactor.accounts.v1"
    private let autoDismissKey = "luma.twofactor.auto-dismiss.v1"
    private let highlightKey = "luma.twofactor.highlight-expiring.v1"

    private var secretCache: [UUID: String] = [:]
    private var codeCache: [UUID: CachedCode] = [:]

    private struct CachedCode {
        let counter: UInt64
        let algorithm: TOTPAlgorithm
        let digits: Int
        let period: Int
        let code: String
    }

    init(
        defaults: UserDefaults = .standard,
        secrets: TwoFactorSecretStoring = KeychainTwoFactorSecretStore()
    ) {
        self.defaults = defaults
        self.secrets = secrets
        if let data = defaults.data(forKey: accountsKey),
           let saved = try? JSONDecoder().decode([TwoFactorAccount].self, from: data) {
            accounts = saved
        }
        autoDismissesAfterCopy = defaults.object(forKey: autoDismissKey) as? Bool ?? true
        highlightsExpiringCodes = defaults.object(forKey: highlightKey) as? Bool ?? true
    }

    var isEmpty: Bool { accounts.isEmpty }

    var missingSecretCount: Int {
        accounts.filter { !hasSecret(for: $0) }.count
    }

    /// 钥匙串当前读不到密钥（例如重新签名后等待授权）。此时缺失密钥不等于账户损坏。
    var secretsUnavailable: Bool { !secrets.isAvailable }

    func accounts(matching query: String) -> [TwoFactorAccount] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return accounts }
        return accounts.filter { $0.matches(value) }
    }

    // MARK: 密钥与验证码

    func secret(for account: TwoFactorAccount) -> String? {
        if let cached = secretCache[account.id] { return cached.isEmpty ? nil : cached }
        let stored = secrets.secret(for: account.id)
        // 只缓存读到的密钥：钥匙串暂时不可用时不能把「空」缓存下来，否则用户完成授权后
        // 账户仍会一直显示缺少密钥。
        if !stored.isEmpty { secretCache[account.id] = stored }
        return stored.isEmpty ? nil : stored
    }

    func hasSecret(for account: TwoFactorAccount) -> Bool {
        secret(for: account) != nil
    }

    /// 当前周期的验证码。同一周期内复用缓存，倒计时刷新不会反复计算 HMAC。
    func code(for account: TwoFactorAccount, at date: Date = Date()) -> String? {
        guard let stored = secret(for: account), let key = Base32.decode(stored) else { return nil }
        let counter = TOTPGenerator.counter(at: date, period: account.period)
        if let cached = codeCache[account.id],
           cached.counter == counter,
           cached.algorithm == account.algorithm,
           cached.digits == account.digits,
           cached.period == account.period {
            return cached.code
        }
        let code = TOTPGenerator.hotp(
            secret: key,
            counter: counter,
            algorithm: account.algorithm,
            digits: account.digits
        )
        codeCache[account.id] = CachedCode(
            counter: counter,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
            code: code
        )
        return code
    }

    func remainingSeconds(for account: TwoFactorAccount, at date: Date = Date()) -> Int {
        TOTPGenerator.remainingSeconds(period: account.period, at: date)
    }

    func isExpiring(_ account: TwoFactorAccount, at date: Date = Date()) -> Bool {
        remainingSeconds(for: account, at: date) <= 5
    }

    // MARK: 增删改

    @discardableResult
    func add(_ draft: TwoFactorAccountDraft, at date: Date = Date()) -> AddOutcome {
        guard case .success(let value) = draft.validated() else { return .failed }
        if let existing = accounts.first(where: { secret(for: $0) == value.normalizedSecret }) {
            return .duplicate(existing)
        }
        // 账户还在、密钥没了（换了存储方式、从备份恢复、钥匙串条目被删）时补写密钥，
        // 而不是再插一条同名账户。同名账户的标签相同、可互换，所以取第一个匹配项即可：
        // 补回一个之后它就有密钥了，下一个同名草稿会自然落到下一个账户上。
        if let orphan = accounts.first(where: {
            !hasSecret(for: $0) && $0.issuer == value.issuer && $0.name == value.name
        }) {
            guard secrets.setSecret(value.normalizedSecret, for: orphan.id) else { return .failed }
            secretCache[orphan.id] = value.normalizedSecret
            codeCache[orphan.id] = nil
            var restored = orphan
            restored.algorithm = value.algorithm
            restored.digits = value.digits
            restored.period = value.period
            if let index = accounts.firstIndex(where: { $0.id == orphan.id }) {
                accounts[index] = restored
            }
            persist()
            return .restored(restored)
        }
        let account = TwoFactorAccount(draft: value, createdAt: date)
        guard secrets.setSecret(value.normalizedSecret, for: account.id) else { return .failed }
        secretCache[account.id] = value.normalizedSecret
        accounts.append(account)
        persist()
        return .added(account)
    }

    @discardableResult
    func add(_ drafts: [TwoFactorAccountDraft], at date: Date = Date()) -> [AddOutcome] {
        drafts.map { add($0, at: date) }
    }

    /// 批量添加并汇总结果。插件页与「用 Luma 打开导出文件」共用同一套文案。
    @discardableResult
    func addAll(_ drafts: [TwoFactorAccountDraft], at date: Date = Date()) -> TwoFactorImportSummary {
        var summary = TwoFactorImportSummary()
        for draft in drafts {
            switch add(draft, at: date) {
            case .added(let account): summary.added.append(account)
            case .restored(let account): summary.restored.append(account)
            case .duplicate(let existing): summary.duplicates.append(existing)
            case .failed: summary.failed += 1
            }
        }
        return summary
    }

    @discardableResult
    func update(_ account: TwoFactorAccount, with draft: TwoFactorAccountDraft) -> Bool {
        guard case .success(let value) = draft.validated(),
              let index = accounts.firstIndex(where: { $0.id == account.id }) else { return false }

        var updated = accounts[index]
        updated.issuer = value.issuer
        updated.name = value.name
        updated.algorithm = value.algorithm
        updated.digits = value.digits
        updated.period = value.period

        if value.normalizedSecret != secret(for: updated) {
            guard secrets.setSecret(value.normalizedSecret, for: updated.id) else { return false }
            secretCache[updated.id] = value.normalizedSecret
        }
        accounts[index] = updated
        codeCache[updated.id] = nil
        persist()
        return true
    }

    func remove(_ account: TwoFactorAccount) {
        guard accounts.contains(where: { $0.id == account.id }) else { return }
        accounts.removeAll { $0.id == account.id }
        secrets.removeSecret(for: account.id)
        secretCache[account.id] = nil
        codeCache[account.id] = nil
        persist()
    }

    func removeAll() {
        for account in accounts { secrets.removeSecret(for: account.id) }
        accounts = []
        secretCache = [:]
        codeCache = [:]
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: accountsKey)
    }
}

/// 批量导入的结果。文案在这里统一生成，插件页与「用 Luma 打开导出文件」共用。
struct TwoFactorImportSummary: Equatable {
    var added: [TwoFactorAccount] = []
    /// 账户本来就在、这次只补回了密钥的数量。
    var restored: [TwoFactorAccount] = []
    var duplicates: [TwoFactorAccount] = []
    var failed = 0

    var isEmpty: Bool { added.isEmpty && restored.isEmpty && duplicates.isEmpty && failed == 0 }

    /// 一个都没写进去（全部重复或全部失败）时按错误样式展示。
    var isProblem: Bool { added.isEmpty && restored.isEmpty }

    var message: String {
        var parts: [String] = []
        if added.count == 1, let account = added.first {
            parts.append(L10n.text("已添加「\(account.title)」", "Added \"\(account.title)\""))
        } else if !added.isEmpty {
            parts.append(L10n.text("已添加 \(added.count) 个账户", "Added \(added.count) accounts"))
        }

        if !restored.isEmpty {
            parts.append(L10n.text(
                "已补回 \(restored.count) 个账户的密钥",
                "Restored secrets for \(restored.count) accounts"
            ))
        }

        if !duplicates.isEmpty {
            let titles = duplicates.map(\.title)
            let shown = titles.prefix(3).joined(separator: L10n.text("、", ", "))
            let suffix = titles.count > 3 ? L10n.text(" 等", " and others") : ""
            parts.append(L10n.text(
                "\(duplicates.count) 个密钥已存在：\(shown)\(suffix)",
                "\(duplicates.count) already added: \(shown)\(suffix)"
            ))
        }

        if failed > 0 {
            parts.append(L10n.text("\(failed) 个无法保存", "\(failed) could not be saved"))
        }
        return parts.joined(separator: L10n.text("；", "; "))
    }
}

// MARK: - 二维码识别

enum TwoFactorQRCodeDecoder {
    /// 识别图片中的条码载荷（去重、保持顺序）。截图、图片文件与剪贴板图片都走这里。
    static func payloads(in image: NSImage) -> [String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        return payloads(in: cgImage)
    }

    static func payloads(in data: Data) -> [String] {
        guard let image = NSImage(data: data) else { return [] }
        return payloads(in: image)
    }

    static func payloads(in url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        return payloads(in: data)
    }

    static func payloads(in cgImage: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        var seen = Set<String>()
        var payloads: [String] = []
        for observation in request.results ?? [] {
            guard let payload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !payload.isEmpty,
                  seen.insert(payload).inserted else { continue }
            payloads.append(payload)
        }
        return payloads
    }
}

/// 截图场景下读取剪贴板里的图片：位图、NSImage 对象与图片文件都接受。
enum TwoFactorClipboardImage {
    static func read(from pasteboard: NSPasteboard = .general) -> NSImage? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first {
            return image
        }
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            for url in urls where isImageFile(url) {
                if let image = NSImage(contentsOf: url) { return image }
            }
        }
        return nil
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

// MARK: - 导入

struct TwoFactorImport: Equatable {
    enum Source: Equatable {
        case clipboard
        case file(String)
    }

    struct Item: Equatable, Identifiable {
        let payload: String
        let result: Result<TwoFactorAccountDraft, OTPAuthImportError>

        var id: String { payload }
        var draft: TwoFactorAccountDraft? {
            if case .success(let value) = result { return value }
            return nil
        }
        var error: OTPAuthImportError? {
            if case .failure(let error) = result { return error }
            return nil
        }
    }

    let source: Source
    let items: [Item]

    var drafts: [TwoFactorAccountDraft] { items.compactMap(\.draft) }
    var isEmpty: Bool { items.isEmpty }

    var sourceTitle: String {
        switch source {
        case .clipboard: L10n.text("剪贴板图片", "Clipboard image")
        case .file(let name): name
        }
    }
}

enum TwoFactorImporter {
    static func importFromClipboardImage(_ image: NSImage) -> TwoFactorImport {
        make(payloads: TwoFactorQRCodeDecoder.payloads(in: image), source: .clipboard)
    }

    static func importFromClipboard() -> TwoFactorImport? {
        guard let image = TwoFactorClipboardImage.read() else { return nil }
        return importFromClipboardImage(image)
    }

    static func importFromFile(_ url: URL) -> TwoFactorImport {
        make(
            payloads: TwoFactorQRCodeDecoder.payloads(in: url),
            source: .file(url.lastPathComponent)
        )
    }

    static func importFromText(_ text: String) -> TwoFactorImport? {
        guard let link = OTPAuthURIParser.firstLink(in: text) else { return nil }
        return make(payloads: [link], source: .clipboard)
    }

    /// 读取导出文件（Ente Auth 明文导出、逐行 otpauth 链接、含链接的 JSON 等）。
    static func importFromExportFile(_ url: URL) -> TwoFactorImport? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let text else { return nil }
        return importFromExportText(text, fileName: url.lastPathComponent)
    }

    static func importFromExportText(_ text: String, fileName: String) -> TwoFactorImport {
        make(payloads: OTPAuthURIParser.links(in: text), source: .file(fileName))
    }

    static func make(payloads: [String], source: TwoFactorImport.Source) -> TwoFactorImport {
        TwoFactorImport(
            source: source,
            items: payloads.map { TwoFactorImport.Item(payload: $0, result: OTPAuthURIParser.draft(from: $0)) }
        )
    }
}
