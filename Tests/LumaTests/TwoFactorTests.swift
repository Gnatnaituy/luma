import AppKit
import CoreImage
import Foundation
import Testing

@testable import Luma

@Suite
struct TwoFactorTests {
    // MARK: - RFC 4226 / RFC 6238

    @Test
    func hotpMatchesRFC4226Vectors() throws {
        // RFC 4226 附录 D：密钥为 ASCII "12345678901234567890"，6 位验证码。
        let secret = Data("12345678901234567890".utf8)
        let expected = [
            "755224", "287082", "359152", "969429", "338314",
            "254676", "287922", "162583", "399871", "520489"
        ]
        for (counter, code) in expected.enumerated() {
            let generated = TOTPGenerator.hotp(
                secret: secret,
                counter: UInt64(counter),
                algorithm: .sha1,
                digits: 6
            )
            try expect(generated == code, "HOTP counter \(counter) is \(code)")
        }
    }

    @Test
    func totpMatchesRFC6238Vectors() throws {
        // RFC 6238 附录 B：同一时间点上三种算法的 8 位验证码。
        let sha1Secret = Data("12345678901234567890".utf8)
        let sha256Secret = Data("12345678901234567890123456789012".utf8)
        let sha512Secret = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

        let vectors: [(time: TimeInterval, sha1: String, sha256: String, sha512: String)] = [
            (59, "94287082", "46119246", "90693936"),
            (1_111_111_109, "07081804", "68084774", "25091201"),
            (1_111_111_111, "14050471", "67062674", "99943326"),
            (1_234_567_890, "89005924", "91819424", "93441116"),
            (2_000_000_000, "69279037", "90698825", "38618901"),
            (20_000_000_000, "65353130", "77737706", "47863826")
        ]

        for vector in vectors {
            let date = Date(timeIntervalSince1970: vector.time)
            try expect(
                TOTPGenerator.code(secret: sha1Secret, algorithm: .sha1, digits: 8, period: 30, at: date) == vector.sha1,
                "SHA-1 code at \(vector.time)"
            )
            try expect(
                TOTPGenerator.code(secret: sha256Secret, algorithm: .sha256, digits: 8, period: 30, at: date) == vector.sha256,
                "SHA-256 code at \(vector.time)"
            )
            try expect(
                TOTPGenerator.code(secret: sha512Secret, algorithm: .sha512, digits: 8, period: 30, at: date) == vector.sha512,
                "SHA-512 code at \(vector.time)"
            )
        }
    }

    @Test
    func totpCounterPeriodAndCountdown() throws {
        let secret = Data("12345678901234567890".utf8)
        let start = Date(timeIntervalSince1970: 1_111_111_100)

        try expect(TOTPGenerator.counter(at: start, period: 30) == 37_037_036, "counter follows the 30 second period")
        try expect(TOTPGenerator.remainingSeconds(period: 30, at: start) == 10, "countdown reports the remaining seconds")
        try expect(TOTPGenerator.progress(period: 30, at: start) == 2.0 / 3.0, "progress reports the elapsed fraction")

        // 同一个周期内验证码不变，跨周期后改变。
        let withinPeriod = start.addingTimeInterval(9)
        try expect(
            TOTPGenerator.code(secret: secret, algorithm: .sha1, digits: 6, period: 30, at: start)
                == TOTPGenerator.code(secret: secret, algorithm: .sha1, digits: 6, period: 30, at: withinPeriod),
            "the code is stable inside one period"
        )
        try expect(
            TOTPGenerator.code(secret: secret, algorithm: .sha1, digits: 6, period: 30, at: start)
                != TOTPGenerator.code(secret: secret, algorithm: .sha1, digits: 6, period: 30, at: start.addingTimeInterval(30)),
            "the code rotates with the next period"
        )
        try expect(TOTPGenerator.remainingSeconds(period: 30, at: start.addingTimeInterval(10)) == 30, "countdown restarts each period")
        try expect(TOTPGenerator.grouped("123456") == "123 456", "six digit codes are grouped")
        try expect(TOTPGenerator.grouped("12345678") == "1234 5678", "eight digit codes are grouped")
    }

    // MARK: - Base32

    @Test
    func base32Decoding() throws {
        // RFC 4648 测试向量：MY====== 是 "f"，MZXW6=== 是 "foo"，MZXW6YTBOI====== 是 "foobar"。
        try expect(Base32.decode("MY======") == Data("f".utf8), "single byte")
        try expect(Base32.decode("MZXW6===") == Data("foo".utf8), "three bytes")
        try expect(Base32.decode("MZXW6YTBOI======") == Data("foobar".utf8), "six bytes")
        try expect(
            Base32.decode("mzxw 6ytb-oi") == Data("foobar".utf8),
            "lowercase, spaces and separators are tolerated"
        )
        try expect(Base32.normalized("jbsw-y3dp ehpk3pxp=") == "JBSWY3DPEHPK3PXP", "normalization uppercases and strips separators")
        try expect(Base32.decode("MZXW6YTBOI") == Data("foobar".utf8), "missing padding still decodes")
        try expect(Base32.decode("0189!!") == nil, "invalid characters are rejected")
        try expect(Base32.decode("") == nil, "an empty secret is rejected")
        try expect(TOTPAlgorithm.named("SHA-256") == .sha256, "algorithm names tolerate separators")
        try expect(TOTPAlgorithm.named(nil) == .sha1, "the default algorithm is SHA-1")
        try expect(TOTPAlgorithm.named("sha512") == .sha512, "algorithm names are case insensitive")
        try expect(TOTPAlgorithm.named("md5") == .sha1, "unknown algorithms fall back to SHA-1")
    }

    // MARK: - otpauth 链接

    @Test
    func otpauthLinkParsing() throws {
        let link = "otpauth://totp/GitHub:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA256&digits=8&period=60"
        guard case .success(let draft) = OTPAuthURIParser.draft(from: link) else {
            throw TestFailure("a complete otpauth link must parse")
        }
        try expect(draft.issuer == "GitHub", "the issuer parameter wins")
        try expect(draft.name == "alice@example.com", "the label is percent decoded")
        try expect(draft.secret == "JBSWY3DPEHPK3PXP", "the secret is normalized")
        try expect(draft.algorithm == .sha256, "the algorithm is read")
        try expect(draft.digits == 8, "the digits are read")
        try expect(draft.period == 60, "the period is read")

        // 默认值：SHA-1 / 6 位 / 30 秒，发行方取自标签前缀。
        guard case .success(let defaults) = OTPAuthURIParser.draft(
            from: "otpauth://totp/ACME%20Co:bob?secret=JBSWY3DPEHPK3PXP"
        ) else {
            throw TestFailure("a minimal otpauth link must parse")
        }
        try expect(defaults.issuer == "ACME Co", "the label prefix supplies the issuer")
        try expect(defaults.name == "bob", "the label suffix supplies the account name")
        try expect(
            defaults.algorithm == .sha1 && defaults.digits == 6 && defaults.period == 30,
            "missing parameters fall back to the specification defaults"
        )

        // 只有账户名时，账户名同时作为标题。
        guard case .success(let plain) = OTPAuthURIParser.draft(
            from: "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&issuer=GitLab"
        ) else {
            throw TestFailure("a link without a label prefix must parse")
        }
        try expect(plain.issuer == "GitLab" && plain.name == "alice", "the query issuer is used when the label has no prefix")

        // 从整段文字里提取链接。
        let text = "扫描下面的二维码：\notpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub\n谢谢"
        try expect(
            OTPAuthURIParser.firstLink(in: text) == "otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub",
            "a link is extracted from surrounding text"
        )
        try expect(OTPAuthURIParser.firstLink(in: "没有任何链接") == nil, "plain text yields no link")
    }

    @Test
    func otpauthLinkRejections() throws {
        try expect(
            OTPAuthURIParser.draft(from: "https://example.com").failureError == .missingLink,
            "a non otpauth link is rejected"
        )
        try expect(
            OTPAuthURIParser.draft(from: "otpauth://totp/alice?issuer=GitHub").failureError == .missingSecret,
            "a missing secret is reported"
        )
        try expect(
            OTPAuthURIParser.draft(from: "otpauth://totp/alice?secret=0189!!").failureError == .invalidSecret,
            "an invalid secret is reported"
        )
        try expect(
            OTPAuthURIParser.draft(from: "otpauth://totp/alice?secret=MZXW6").failureError == .secretTooShort,
            "a short secret is reported"
        )
        try expect(
            OTPAuthURIParser.draft(from: "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&digits=3").failureError == .invalidDigits,
            "an out of range digit count is reported"
        )
        try expect(
            OTPAuthURIParser.draft(from: "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&period=0").failureError == .invalidPeriod,
            "an out of range period is reported"
        )
        try expect(
            OTPAuthURIParser.draft(from: "otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP&counter=1").failureError == .counterBasedNotSupported,
            "HOTP links are reported as unsupported"
        )
        try expect(
            OTPAuthURIParser.draft(from: "otpauth-migration://offline?data=AAAA").failureError == .migrationNotSupported,
            "Google Authenticator migration links are reported as unsupported"
        )
        try expect(
            OTPAuthURIParser.draft(from: "otpauth://totp/?secret=JBSWY3DPEHPK3PXP").failureError == .missingLabel,
            "a link without any label is rejected"
        )
    }

    // MARK: - 账户存储

    @Test
    @MainActor
    func storeAddsGeneratesAndPersists() throws {
        let suiteName = "app.luma.twofactor-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secrets = InMemoryTwoFactorSecretStore()
        let store = TwoFactorStore(defaults: defaults, secrets: secrets)
        try expect(store.accounts.isEmpty, "a fresh store has no accounts")
        try expect(store.autoDismissesAfterCopy, "copying hides the panel by default")

        let draft = TwoFactorAccountDraft(
            issuer: "GitHub",
            name: "alice@example.com",
            secret: "gezd-gnbv gy3tqojq gezdgnbvgy3tqojq",
            algorithm: .sha1,
            digits: 6,
            period: 30
        )
        guard case .added(let account) = store.add(draft) else {
            throw TestFailure("a valid draft must be added")
        }
        try expect(account.issuer == "GitHub" && account.name == "alice@example.com", "metadata is stored")
        try expect(account.title == "GitHub" && account.subtitle == "alice@example.com", "the issuer is the title")
        try expect(account.initial == "G", "the avatar initial comes from the title")
        try expect(store.secret(for: account) == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "the secret is normalized before storage")
        try expect(store.hasSecret(for: account), "the account has a secret")

        // 账户里保存的是 RFC 6238 的密钥（Base32 形式），T=59 对应 RFC 向量。
        let date = Date(timeIntervalSince1970: 59)
        try expect(store.code(for: account, at: date) == "287082", "the store generates the RFC 4226 vector code")
        try expect(store.code(for: account, at: date) == "287082", "the cached code is stable")
        try expect(store.remainingSeconds(for: account, at: date) == 1, "the countdown is derived from the period")
        try expect(store.isExpiring(account, at: date), "one second left is expiring")
        try expect(store.isExpiring(account, at: Date(timeIntervalSince1970: 40)) == false, "twenty seconds left is not expiring")

        // 相同密钥不会重复添加。
        try expect(store.add(draft) == .duplicate(account), "the same secret is rejected as a duplicate")
        try expect(store.accounts.count == 1, "the duplicate was not appended")

        // 搜索。
        try expect(store.accounts(matching: "git").count == 1, "search matches the issuer")
        try expect(store.accounts(matching: "ALICE").count == 1, "search is case insensitive")
        try expect(store.accounts(matching: "nothing").isEmpty, "search misses are empty")

        // 编辑：改名与换算法后旧验证码缓存失效，结果与 RFC 6238 的 SHA-256 向量一致
        //（该向量的种子是 32 字节，因此这里同时换掉密钥）。
        var edited = account
        edited.name = "bob@example.com"
        edited.digits = 8
        let editDraft = TwoFactorAccountDraft(
            issuer: edited.issuer,
            name: edited.name,
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA",
            algorithm: .sha256,
            digits: 8,
            period: 30
        )
        try expect(store.update(account, with: editDraft), "editing succeeds")
        let updated = try #require(store.accounts.first)
        try expect(updated.name == "bob@example.com" && updated.algorithm == .sha256 && updated.digits == 8, "edits are applied")
        try expect(store.code(for: updated, at: date) == "46119246", "the code follows the new algorithm")

        // 重新载入：元数据来自偏好设置，密钥来自密钥存储。
        let restored = TwoFactorStore(defaults: defaults, secrets: secrets)
        try expect(restored.accounts.count == 1, "accounts survive a relaunch")
        try expect(
            restored.secret(for: try #require(restored.accounts.first))
                == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA",
            "secrets survive a relaunch"
        )
        try expect(restored.accounts.first?.algorithm == .sha256, "algorithm changes survive a relaunch")

        // 删除会同时清掉密钥。
        store.remove(updated)
        try expect(store.accounts.isEmpty, "the account is removed")
        try expect(secrets.secret(for: updated.id).isEmpty, "the secret is removed from the key store")
        try expect(store.missingSecretCount == 0, "no missing secrets after a clean removal")
    }

    @Test
    @MainActor
    func storeReportsMissingSecrets() throws {
        let suiteName = "app.luma.twofactor-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secrets = InMemoryTwoFactorSecretStore()
        let store = TwoFactorStore(defaults: defaults, secrets: secrets)
        guard case .added(let account) = store.add(
            TwoFactorAccountDraft(issuer: "GitHub", name: "alice", secret: "JBSWY3DPEHPK3PXP")
        ) else {
            throw TestFailure("a valid draft must be added")
        }

        // 模拟钥匙串条目丢失（例如从另一台机器导入了配置）。
        secrets.removeSecret(for: account.id)
        let restored = TwoFactorStore(defaults: defaults, secrets: secrets)
        let orphan = try #require(restored.accounts.first)
        try expect(restored.hasSecret(for: orphan) == false, "a missing keychain entry is detected")
        try expect(restored.code(for: orphan) == nil, "a missing secret yields no code")
        try expect(restored.missingSecretCount == 1, "missing secrets are counted")

        // 无效草稿不会被保存。
        try expect(store.add(TwoFactorAccountDraft(issuer: "x", name: "y", secret: "!!")) == .failed, "an invalid secret cannot be added")
        try expect(store.add(TwoFactorAccountDraft(issuer: "", name: "", secret: "JBSWY3DPEHPK3PXP")) == .failed, "a nameless account cannot be added")
        try expect(store.accounts.count == 1, "failed adds do not change the list")

        restored.removeAll()
        try expect(restored.accounts.isEmpty, "clearing removes every account")
        try expect(secrets.secret(for: orphan.id).isEmpty, "clearing removes every secret")
    }

    // MARK: - 二维码识别

    @Test
    func qrCodeScreenshotDecoding() throws {
        let link = "otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30"
        let image = try #require(qrImage(for: link), "a QR code image can be generated for the test")

        let payloads = TwoFactorQRCodeDecoder.payloads(in: image)
        try expect(payloads.contains(link), "the QR payload is decoded from the image")

        let result = TwoFactorImporter.importFromClipboardImage(image)
        try expect(result.source == .clipboard, "the import records its source")
        try expect(result.items.count == 1, "one QR code yields one item")
        try expect(result.drafts.count == 1, "the payload parses into a draft")
        let draft = try #require(result.drafts.first)
        try expect(draft.issuer == "GitHub" && draft.name == "alice", "the decoded draft carries the issuer and account")

        // 非 2FA 二维码会被识别到，但解析时报错而不是静默丢弃。
        let plainImage = try #require(qrImage(for: "https://example.com"), "a plain QR code image can be generated")
        let plainResult = TwoFactorImporter.importFromClipboardImage(plainImage)
        try expect(plainResult.items.count == 1, "the unrelated QR code is detected")
        try expect(plainResult.drafts.isEmpty, "the unrelated QR code yields no draft")
        try expect(plainResult.items.first?.error == .missingLink, "the unrelated QR code reports a missing link")

        // 没有二维码的图片不产生任何条目。
        let blank = NSImage(size: NSSize(width: 64, height: 64))
        blank.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        blank.unlockFocus()
        try expect(TwoFactorQRCodeDecoder.payloads(in: blank).isEmpty, "a blank image yields no payload")

        // 剪贴板文本里的链接也能直接导入。
        let fromText = TwoFactorImporter.importFromText("请添加 \(link) 到验证器")
        try expect(fromText?.drafts.count == 1, "a link inside clipboard text is imported")
        try expect(TwoFactorImporter.importFromText("没有链接") == nil, "text without a link is not imported")
    }

    // MARK: - 插件注册

    @Test
    func twoFactorPluginIsRegistered() throws {
        try expect(Plugin.allCases.contains(.twoFactor), "the two-factor plugin is part of the catalog")
        try expect(Plugin.twoFactor.title == "两步验证", "the plugin has a Chinese title")
        try expect(Plugin.twoFactor.symbol == "lock.badge.clock", "the plugin has a menu bar friendly symbol")
        try expect(Plugin.twoFactor.matches("2fa"), "the plugin matches its English keyword")
        try expect(Plugin.twoFactor.matches("totp"), "the plugin matches the TOTP keyword")
        try expect(Plugin.twoFactor.matches("动态口令"), "the plugin matches its Chinese keyword")
        try expect(Plugin.twoFactor.keywords.contains("验证码"), "the plugin advertises the verification code keyword")
        try expect(
            SettingsSection.allCases.contains(.twoFactor) && SettingsSection.twoFactor.category == .plugins,
            "the settings sidebar exposes a two-factor section"
        )
        try expect(
            SettingsBackup.supportedKeys.contains("luma.twofactor.accounts.v1"),
            "account metadata is part of the exported configuration"
        )
    }

    // MARK: - 导出文件批量导入

    @Test
    @MainActor
    func exportFileImport() throws {
        // 复刻 Ente Auth 明文导出的形态：每行一条链接，issuer 用 + 表示空格，
        // 并带上插件不认识的 codeDisplay 参数。
        let export = """
        otpauth://totp/Aliyun%20%E5%A2%A8%E8%A5%BF%E5%93%A5:tiantangyu@5490201939098538?algorithm=sha1&digits=6&issuer=Aliyun+%E5%A2%A8%E8%A5%BF%E5%93%A5&period=30&secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&codeDisplay=%7B%22pinned%22%3Afalse%7D
        otpauth://totp/OpenAI:OpenAI?algorithm=sha1&digits=6&issuer=OpenAI&period=30&secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA
        otpauth://totp/%E8%8F%B2%E5%BE%8B%E5%AE%BESendGird:tracy@massser.com?algorithm=sha1&digits=6&issuer=%E8%8F%B2%E5%BE%8B%E5%AE%BESendGird&period=30&secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP

        这段说明文字里没有链接。
        """

        let links = OTPAuthURIParser.links(in: export)
        try expect(links.count == 3, "every otpauth link in the file is found")
        try expect(links.allSatisfy { $0.hasPrefix("otpauth://") }, "only otpauth tokens are collected")

        let result = TwoFactorImporter.importFromExportText(export, fileName: "ente-auth-codes.txt")
        try expect(result.items.count == 3, "each link becomes an import item")
        try expect(result.drafts.count == 3, "every line parses into a draft")
        try expect(result.sourceTitle == "ente-auth-codes.txt", "the import remembers the file name")

        let aliyun = try #require(result.drafts.first)
        try expect(aliyun.issuer == "Aliyun 墨西哥", "plus signs decode as spaces in the issuer")
        try expect(aliyun.name == "tiantangyu@5490201939098538", "the account name is decoded")
        try expect(aliyun.displaySubtitle.hasPrefix("tiantangyu@5490201939098538 · SHA1 · 6 位 · 30 秒"), "the subtitle stays localized")

        let openAI = try #require(result.drafts.dropFirst().first)
        try expect(openAI.issuer == "OpenAI" && openAI.name == "OpenAI", "a single-name account keeps its issuer")
        try expect(openAI.displaySubtitle.hasPrefix("SHA1"), "the subtitle drops a duplicated account name")

        // 写进临时文件后走真实的文件读取路径。
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("luma-twofactor-export-\(UUID().uuidString).txt")
        try export.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let fromFile = try #require(TwoFactorImporter.importFromExportFile(url))
        try expect(fromFile.drafts.count == 3, "the export file is read from disk")

        // 批量写入：新增 2 个，第 3 个密钥重复。
        let suiteName = "app.luma.twofactor-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TwoFactorStore(defaults: defaults, secrets: InMemoryTwoFactorSecretStore())

        let summary = store.addAll(result.drafts)
        try expect(summary.added.count == 3 && summary.duplicates.isEmpty && summary.failed == 0, "the first import adds every account")
        try expect(summary.message.contains("已添加 3 个账户"), "the summary reports the batch size")
        try expect(summary.isProblem == false, "a clean import is not a problem")

        let second = store.addAll(result.drafts)
        try expect(second.added.isEmpty && second.duplicates.count == 3, "re-importing the same file adds nothing")
        try expect(second.isProblem, "an all-duplicate import is reported as a problem")
        try expect(second.message.contains("3 个密钥已存在"), "the summary names the duplicate count")
        try expect(store.accounts.count == 3, "the store keeps exactly one copy of each account")

        // 同一份导出里混入坏行时，好行照常导入。
        let mixed = export + "\notpauth://totp/Broken:bob?secret=0189!!\n"
        let mixedResult = TwoFactorImporter.importFromExportText(mixed, fileName: "mixed.txt")
        try expect(mixedResult.items.count == 4 && mixedResult.drafts.count == 3, "a broken line does not block the rest")
        try expect(mixedResult.items.last?.error == .invalidSecret, "the broken line reports its own error")
    }

    // MARK: - 密钥归档与补回

    @Test
    func secretArchiveRoundTrip() throws {
        let first = UUID()
        let second = UUID()
        let encoded = TwoFactorSecretArchive.encode([first: "JBSWY3DPEHPK3PXP", second: "GEZDGNBVGY3TQOJQ"])
        let decoded = try #require(TwoFactorSecretArchive.decode(encoded))
        try expect(decoded == [first: "JBSWY3DPEHPK3PXP", second: "GEZDGNBVGY3TQOJQ"], "the archive round-trips")

        try expect(TwoFactorSecretArchive.decode(Data("not json".utf8)) == nil, "corrupt payloads are rejected")
        try expect(TwoFactorSecretArchive.decode(Data("{}".utf8))?.isEmpty == true, "an empty archive decodes to no secrets")
        // 无法解析成 UUID 的键会被跳过，而不是让整包解码失败。
        let mixed = try #require(TwoFactorSecretArchive.decode(Data(#"{"not-a-uuid":"x"}"#.utf8)))
        try expect(mixed.isEmpty, "unknown keys are skipped")
    }

    @Test
    @MainActor
    func importRestoresSecretsInsteadOfDuplicating() throws {
        let suiteName = "app.luma.twofactor-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secrets = InMemoryTwoFactorSecretStore()
        let store = TwoFactorStore(defaults: defaults, secrets: secrets)
        let draft = TwoFactorAccountDraft(
            issuer: "GitHub",
            name: "alice",
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        )
        guard case .added(let account) = store.add(draft) else {
            throw TestFailure("the first add must succeed")
        }

        // 模拟密钥丢失：账户元数据还在，钥匙串里没有密钥。
        secrets.removeSecret(for: account.id)
        let restoredStore = TwoFactorStore(defaults: defaults, secrets: secrets)
        try expect(restoredStore.accounts.count == 1, "the account metadata survives")
        try expect(restoredStore.hasSecret(for: try #require(restoredStore.accounts.first)) == false, "the secret is gone")
        try expect(restoredStore.missingSecretCount == 1, "the missing secret is reported")

        // 重新导入同一份导出：补回密钥，而不是插入重复账户。
        let orphan = try #require(restoredStore.accounts.first)
        guard case .restored(let restored) = restoredStore.add(draft) else {
            throw TestFailure("importing again must restore the missing secret")
        }
        try expect(restored.id == orphan.id, "the existing account is reused")
        try expect(restoredStore.accounts.count == 1, "no duplicate account is created")
        try expect(restoredStore.hasSecret(for: orphan), "the secret is back")
        try expect(
            restoredStore.code(for: orphan, at: Date(timeIntervalSince1970: 59)) == "287082",
            "the restored secret generates the RFC vector code"
        )

        // 再导入一次就是普通重复。
        try expect(restoredStore.add(draft) == .duplicate(orphan), "a third import reports a duplicate")

        // 补回时用草稿里的参数刷新元数据（位数/算法可能已经改过）。
        let updatedDraft = TwoFactorAccountDraft(
            issuer: "GitHub",
            name: "alice",
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            algorithm: .sha256,
            digits: 8
        )
        secrets.removeSecret(for: orphan.id)
        let third = TwoFactorStore(defaults: defaults, secrets: secrets)
        guard case .restored(let refreshed) = third.add(updatedDraft) else {
            throw TestFailure("restoring must also refresh metadata")
        }
        try expect(refreshed.algorithm == .sha256 && refreshed.digits == 8, "metadata follows the draft")
    }

    @Test
    @MainActor
    func unavailableKeychainBlocksWrites() throws {
        let suiteName = "app.luma.twofactor-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 读不到密钥的存储：写入必须失败，而不是用一份空表覆盖已有密钥。
        let store = TwoFactorStore(defaults: defaults, secrets: UnavailableSecretStore())
        try expect(store.secretsUnavailable, "an unreadable keychain is reported")
        try expect(
            store.add(TwoFactorAccountDraft(issuer: "GitHub", name: "alice", secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")) == .failed,
            "writes fail while the keychain is unreadable"
        )
        try expect(store.accounts.isEmpty, "nothing is written")

        let summary = store.addAll([TwoFactorAccountDraft(issuer: "GitHub", name: "alice", secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")])
        try expect(summary.failed == 1 && summary.isProblem, "the summary reports the failure")
    }

    // MARK: - 辅助

    private func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw TestFailure(name) }
    }

    /// 用 CoreImage 生成一张二维码图片，模拟用户截图。
    private func qrImage(for text: String) -> NSImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(text.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter?.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

private extension Result where Failure == OTPAuthImportError {
    var failureError: OTPAuthImportError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

/// 模拟钥匙串等待授权：读不到密钥，写入也必须拒绝。
private final class UnavailableSecretStore: TwoFactorSecretStoring {
    var isAvailable: Bool { false }
    func secret(for id: UUID) -> String { "" }
    func setSecret(_ secret: String, for id: UUID) -> Bool { false }
    func removeSecret(for id: UUID) -> Bool { false }
}
