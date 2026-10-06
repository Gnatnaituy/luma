import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum TwoFactorEditorTab: String, CaseIterable, Identifiable {
    case manual
    case link
    case bulk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: L10n.text("手动输入", "Manual")
        case .link: L10n.text("粘贴链接", "Paste Link")
        case .bulk: L10n.text("批量导入", "Bulk Import")
        }
    }

    var symbol: String {
        switch self {
        case .manual: "keyboard"
        case .link: "link"
        case .bulk: "tray.and.arrow.down"
        }
    }
}

enum TwoFactorEditorTarget: Equatable {
    case create
    case edit(TwoFactorAccount)
}

struct TwoFactorEditorSeed: Equatable {
    var target: TwoFactorEditorTarget = .create
    var tab: TwoFactorEditorTab = .manual
    var importResult: TwoFactorImport?
    var secret: String = ""

    static let create = TwoFactorEditorSeed()

    static func edit(_ account: TwoFactorAccount, secret: String) -> TwoFactorEditorSeed {
        TwoFactorEditorSeed(target: .edit(account), tab: .manual, importResult: nil, secret: secret)
    }

    static func review(_ result: TwoFactorImport) -> TwoFactorEditorSeed {
        TwoFactorEditorSeed(target: .create, tab: .bulk, importResult: result, secret: "")
    }
}

enum TwoFactorPage: Equatable {
    case list
    case editor(TwoFactorEditorSeed)
}

struct TwoFactorPluginView: View {
    @ObservedObject var store: TwoFactorStore
    @ObservedObject var clipboard: ClipboardMonitor
    let dismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var page: TwoFactorPage = .list
    @State private var pendingDeletion: UUID?
    @State private var now = Date()
    @State private var banner: String?
    @State private var bannerToken = 0
    @State private var keyboardMonitor: Any?

    private var visibleAccounts: [TwoFactorAccount] {
        store.accounts(matching: searchText)
    }

    var body: some View {
        Group {
            switch page {
            case .list:
                listPage
                    .transition(LumaMotion.contentTransition)
            case .editor(let seed):
                TwoFactorEditorView(
                    seed: seed,
                    store: store,
                    now: now,
                    onCancel: { page = .list },
                    onFinish: { message in
                        page = .list
                        pendingDeletion = nil
                        if let message { showBanner(message) }
                    }
                )
                .transition(LumaMotion.contentTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(LumaMotion.standard, value: page)
        .task { await runClock() }
        .onAppear {
            installKeyboardMonitor()
            ensureSelection()
        }
        .onDisappear(perform: removeKeyboardMonitor)
    }

    // MARK: - 列表

    private var listPage: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
        .overlay(alignment: .bottom) {
            if let banner {
                bannerView(banner)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(LumaMotion.quick, value: banner)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField(L10n.text("搜索账户", "Search Accounts"), text: $searchText)
                .textFieldStyle(LumaTextFieldStyle(height: 32))
                .frame(maxWidth: 240)
                .onChange(of: searchText) { _, _ in
                    pendingDeletion = nil
                    ensureSelection()
                }

            Button {
                scanClipboardImage()
            } label: {
                Label(L10n.text("识别二维码", "Scan QR Code"), systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(LumaTextButtonStyle(height: 28))
            .help(L10n.text(
                "识别剪贴板截图里的二维码；没有截图时可改选图片文件",
                "Read a QR code from a screenshot on the clipboard, or pick an image file"
            ))

            Button {
                page = .editor(.create)
            } label: {
                Label(L10n.text("添加", "Add"), systemImage: "plus")
            }
            .buttonStyle(LumaTextButtonStyle(height: 28))

            Spacer()

            if store.secretsUnavailable {
                Label(
                    L10n.text(
                        "无法读取钥匙串，请在系统弹窗中选择「始终允许」",
                        "Cannot read the Keychain. Choose \"Always Allow\" in the system prompt."
                    ),
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else if store.missingSecretCount > 0 {
                Label(
                    L10n.text("\(store.missingSecretCount) 个账户缺少密钥", "\(store.missingSecretCount) accounts are missing secrets"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text(L10n.text("共 \(store.accounts.count) 个账户", "\(store.accounts.count) accounts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if store.accounts.isEmpty {
            emptyState
        } else if visibleAccounts.isEmpty {
            ContentUnavailableView(
                L10n.text("没有匹配的账户", "No Matching Accounts"),
                systemImage: "magnifyingglass",
                description: Text(L10n.text("尝试其他关键词", "Try another keyword"))
            )
        } else {
            accountList
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.text("还没有两步验证账户", "No Two-Factor Accounts"), systemImage: "lock.badge.clock")
        } description: {
            Text(L10n.text(
                "按 ⌃⇧⌘4 截取二维码后回到这里点「识别二维码」，也可以手动输入密钥。",
                "Press ⌃⇧⌘4 to screenshot a QR code, then choose Scan QR Code here. You can also enter a secret manually."
            ))
        } actions: {
            HStack(spacing: 8) {
                Button {
                    scanClipboardImage()
                } label: {
                    Label(L10n.text("识别二维码", "Scan QR Code"), systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(LumaTextButtonStyle(emphasis: .primary))

                Button {
                    page = .editor(.create)
                } label: {
                    Label(L10n.text("手动添加", "Add Manually"), systemImage: "plus")
                }
                .buttonStyle(LumaTextButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accountList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleAccounts) { account in
                    TwoFactorAccountRow(
                        account: account,
                        code: store.code(for: account, at: now),
                        remaining: store.remainingSeconds(for: account, at: now),
                        isSelected: selectedID == account.id,
                        highlightsExpiring: store.highlightsExpiringCodes,
                        isConfirmingDeletion: pendingDeletion == account.id,
                        isKeychainUnavailable: store.secretsUnavailable,
                        onCopy: { copy(account) },
                        onEdit: {
                            page = .editor(.edit(account, secret: store.secret(for: account) ?? ""))
                        },
                        onRequestDelete: {
                            selectedID = account.id
                            pendingDeletion = account.id
                        },
                        onConfirmDelete: {
                            pendingDeletion = nil
                            store.remove(account)
                            ensureSelection()
                            showBanner(L10n.text("已删除「\(account.title)」", "Deleted \"\(account.title)\""))
                        },
                        onCancelDelete: { pendingDeletion = nil }
                    )
                    .padding(.horizontal, 24)
                    Divider().padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func bannerView(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.1)) }
    }

    // MARK: - 行为

    private func runClock() async {
        while !Task.isCancelled {
            now = Date()
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func copy(_ account: TwoFactorAccount) {
        guard let code = store.code(for: account, at: Date()) else {
            showBanner(L10n.text(
                "「\(account.title)」缺少密钥，请重新添加",
                "\"\(account.title)\" is missing its secret. Add it again."
            ))
            return
        }
        clipboard.copy(code)
        selectedID = account.id
        guard !store.autoDismissesAfterCopy else {
            dismiss()
            return
        }
        showBanner(L10n.text("已复制「\(account.title)」的验证码", "Copied the code for \"\(account.title)\""))
    }

    private func scanClipboardImage() {
        guard let image = TwoFactorClipboardImage.read() else {
            page = .editor(TwoFactorEditorSeed(target: .create, tab: .bulk, importResult: nil, secret: ""))
            return
        }
        page = .editor(.review(TwoFactorImporter.importFromClipboardImage(image)))
    }

    private func showBanner(_ message: String) {
        bannerToken += 1
        let token = bannerToken
        banner = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard token == bannerToken else { return }
            banner = nil
        }
    }

    private func ensureSelection() {
        guard let first = visibleAccounts.first else {
            selectedID = nil
            return
        }
        if let selectedID, visibleAccounts.contains(where: { $0.id == selectedID }) { return }
        selectedID = first.id
    }

    private func moveSelection(_ delta: Int) {
        let accounts = visibleAccounts
        guard !accounts.isEmpty else { return }
        guard let selectedID,
              let index = accounts.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = accounts.first?.id
            return
        }
        let count = accounts.count
        let next = ((index + delta) % count + count) % count
        self.selectedID = accounts[next].id
    }

    private func copySelection() {
        guard let selectedID,
              let account = visibleAccounts.first(where: { $0.id == selectedID }) else { return }
        copy(account)
    }

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard case .list = page else { return event }
            let commandModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.modifierFlags.intersection(commandModifiers).isEmpty else { return event }
            switch event.keyCode {
            case 125: moveSelection(1)
            case 126: moveSelection(-1)
            case 36, 76: copySelection()
            default: return event
            }
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        guard let keyboardMonitor else { return }
        NSEvent.removeMonitor(keyboardMonitor)
        self.keyboardMonitor = nil
    }
}

// MARK: - 账户行

private struct TwoFactorAccountRow: View {
    let account: TwoFactorAccount
    let code: String?
    let remaining: Int
    let isSelected: Bool
    let highlightsExpiring: Bool
    let isConfirmingDeletion: Bool
    let isKeychainUnavailable: Bool
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onRequestDelete: () -> Void
    let onConfirmDelete: () -> Void
    let onCancelDelete: () -> Void

    @State private var isHovering = false

    private var isExpiring: Bool { highlightsExpiring && remaining <= 5 }

    private var fraction: Double {
        Double(remaining) / Double(max(1, account.period))
    }

    private var tint: Color {
        let palette: [Color] = [.blue, .green, .indigo, .orange, .pink, .purple, .teal, .cyan, .mint, .brown]
        let sum = account.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 14) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(account.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(account.subtitle.isEmpty
                        ? account.detailText
                        : "\(account.subtitle) · \(account.detailText)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                codeText
                countdown
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 1).onEnded(onCopy))

            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? LumaTone.selectionFill : (isHovering ? LumaTone.hoverFill : Color.clear),
            in: RoundedRectangle(cornerRadius: LumaRadius.card, style: .continuous)
        )
        .overlay {
            if isSelected { LumaRimStroke(cornerRadius: LumaRadius.card) }
        }
        .animation(LumaMotion.quick, value: isSelected)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(L10n.text("复制验证码", "Copy Code"), action: onCopy)
                .disabled(code == nil)
            Button(L10n.text("编辑", "Edit"), action: onEdit)
            Divider()
            Button(L10n.text("删除", "Delete"), role: .destructive, action: onRequestDelete)
        }
    }

    private var avatar: some View {
        Text(account.initial)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(
                tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: LumaRadius.iconRadius(for: 40), style: .continuous)
            )
    }

    @ViewBuilder
    private var codeText: some View {
        if let code {
            Text(TOTPGenerator.grouped(code))
                .font(.system(size: 21, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isExpiring ? Color.red : Color.primary)
                .contentTransition(.numericText())
                .animation(LumaMotion.quick, value: code)
        } else {
            Label(
                isKeychainUnavailable
                    ? L10n.text("钥匙串未授权", "Keychain Not Authorized")
                    : L10n.text("密钥缺失", "Missing secret"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
        }
    }

    private var countdown: some View {
        ZStack {
            Circle()
                .stroke(LumaTone.controlFill, lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.04, fraction))
                .stroke(
                    isExpiring ? Color.red : Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: fraction)
            Text("\(remaining)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isExpiring ? Color.red : Color.secondary)
        }
        .frame(width: 28, height: 28)
        .help(L10n.text("剩余 \(remaining) 秒", "\(remaining)s remaining"))
    }

    @ViewBuilder
    private var actions: some View {
        if isConfirmingDeletion {
            HStack(spacing: 6) {
                Button(L10n.text("删除", "Delete"), role: .destructive, action: onConfirmDelete)
                    .buttonStyle(LumaTextButtonStyle(emphasis: .destructive, height: 28))
                Button(L10n.text("取消", "Cancel"), action: onCancelDelete)
                    .buttonStyle(LumaTextButtonStyle(height: 28))
            }
            .fixedSize()
        } else {
            HStack(spacing: 4) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                }
                .buttonStyle(LumaIconButtonStyle())
                .disabled(code == nil)
                .help(L10n.text("复制验证码", "Copy Code"))

                Button(action: onEdit) {
                    Image(systemName: "pencil").foregroundStyle(.secondary)
                }
                .buttonStyle(LumaIconButtonStyle())
                .help(L10n.text("编辑", "Edit"))

                Button(role: .destructive, action: onRequestDelete) {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(LumaIconButtonStyle())
                .help(L10n.text("删除", "Delete"))
            }
            .fixedSize()
        }
    }
}

// MARK: - 添加与编辑

private struct TwoFactorEditorView: View {
    let store: TwoFactorStore
    let now: Date
    let onCancel: () -> Void
    let onFinish: (String?) -> Void

    @State private var target: TwoFactorEditorTarget
    @State private var tab: TwoFactorEditorTab
    @State private var issuer: String
    @State private var name: String
    @State private var secret: String
    @State private var algorithm: TOTPAlgorithm
    @State private var digits: Int
    @State private var period: Int
    @State private var linkText: String
    @State private var importResult: TwoFactorImport?
    @State private var message: String?
    @State private var isErrorMessage = false
    @State private var didPrefillLink = false

    init(
        seed: TwoFactorEditorSeed,
        store: TwoFactorStore,
        now: Date,
        onCancel: @escaping () -> Void,
        onFinish: @escaping (String?) -> Void
    ) {
        self.store = store
        self.now = now
        self.onCancel = onCancel
        self.onFinish = onFinish
        _target = State(initialValue: seed.target)
        _tab = State(initialValue: seed.tab)
        _importResult = State(initialValue: seed.importResult)
        _linkText = State(initialValue: "")
        switch seed.target {
        case .create:
            _issuer = State(initialValue: "")
            _name = State(initialValue: "")
            _secret = State(initialValue: "")
            _algorithm = State(initialValue: .sha1)
            _digits = State(initialValue: 6)
            _period = State(initialValue: 30)
        case .edit(let account):
            _issuer = State(initialValue: account.issuer)
            _name = State(initialValue: account.name)
            _secret = State(initialValue: seed.secret)
            _algorithm = State(initialValue: account.algorithm)
            _digits = State(initialValue: account.digits)
            _period = State(initialValue: account.period)
        }
    }

    private var editingAccount: TwoFactorAccount? {
        if case .edit(let account) = target { return account }
        return nil
    }

    private var isEditing: Bool { editingAccount != nil }

    private var title: String {
        isEditing
            ? L10n.text("编辑账户", "Edit Account")
            : L10n.text("添加账户", "Add Account")
    }

    private var digitOptions: [Int] {
        let base = [6, 7, 8]
        return base.contains(digits) ? base : (base + [digits]).sorted()
    }

    private var periodOptions: [Int] {
        let base = [30, 60]
        return base.contains(period) ? base : (base + [period]).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isEditing {
                        manualForm
                    } else {
                        tabPicker
                        switch tab {
                        case .manual: manualForm
                        case .link: linkForm
                        case .bulk: bulkForm
                        }
                    }

                    if let message {
                        Label(message, systemImage: isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isErrorMessage ? Color.red : Color.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear(perform: prefillLinkFromClipboard)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Label(L10n.text("返回", "Back"), systemImage: "chevron.left")
            }
            .buttonStyle(LumaTextButtonStyle(height: 28))

            Text(title).font(.headline)
            Spacer()

            if isEditing || tab != .bulk {
                Button(isEditing ? L10n.text("保存", "Save") : L10n.text("添加", "Add"), action: save)
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary, height: 28))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(TwoFactorEditorTab.allCases) { item in
                Button {
                    tab = item
                    message = nil
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .foregroundStyle(tab == item ? Color.accentColor : Color.primary)
                        .background(
                            tab == item ? Color.accentColor.opacity(0.11) : LumaTone.controlFill,
                            in: RoundedRectangle(cornerRadius: LumaRadius.control, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: 手动输入

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                labeledField(
                    title: L10n.text("发行方", "Issuer"),
                    prompt: "GitHub",
                    text: $issuer
                )
                labeledField(
                    title: L10n.text("账户", "Account"),
                    prompt: "alice@example.com",
                    text: $name
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("密钥（Base32）", "Secret (Base32)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("JBSWY3DPEHPK3PXP", text: $secret)
                    .textFieldStyle(LumaTextFieldStyle())
                    .font(.system(.body, design: .monospaced))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("算法", "Algorithm"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LumaMenuPicker(
                        selection: $algorithm,
                        values: TOTPAlgorithm.allCases,
                        title: { $0.title }
                    )
                    .frame(width: 130)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("位数", "Digits"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LumaMenuPicker(
                        selection: $digits,
                        values: digitOptions,
                        title: { "\($0)" }
                    )
                    .frame(width: 110)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("刷新周期", "Refresh Period"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LumaMenuPicker(
                        selection: $period,
                        values: periodOptions,
                        title: { L10n.text("\($0) 秒", "\($0)s") }
                    )
                    .frame(width: 130)
                }
            }

            if !isManualPristine {
                draftPreview(draftResult)
            }
        }
    }

    /// 空表单不提示校验错误，避免刚打开就出现红色警告。
    private var isManualPristine: Bool {
        issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func labeledField(title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(LumaTextFieldStyle())
        }
    }

    // MARK: 粘贴链接

    private var linkForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(
                "粘贴 otpauth:// 链接，或直接粘贴含链接的整段文字。",
                "Paste an otpauth:// link, or any text that contains one."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("otpauth://totp/GitHub:alice?secret=…&issuer=GitHub", text: $linkText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(LumaTextFieldStyle(height: 56))
                .font(.system(size: 12, design: .monospaced))

            if let parsedLink {
                draftPreview(parsedLink)
            }
        }
    }

    // MARK: 二维码

    private var bulkForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    readClipboardImage()
                } label: {
                    Label(L10n.text("识别剪贴板图片", "Read Clipboard Image"), systemImage: "photo.on.rectangle")
                }
                .buttonStyle(LumaTextButtonStyle(height: 30))

                Button {
                    chooseImageFile()
                } label: {
                    Label(L10n.text("选择图片…", "Choose Image…"), systemImage: "photo.badge.arrow.down")
                }
                .buttonStyle(LumaTextButtonStyle(height: 30))

                Button {
                    chooseExportFile()
                } label: {
                    Label(L10n.text("导入导出文件…", "Import Export File…"), systemImage: "doc.badge.plus")
                }
                .buttonStyle(LumaTextButtonStyle(height: 30))
            }

            Text(L10n.text(
                "在任意界面按 ⌃⇧⌘4 截取二维码后回到这里识别；也可以选择保存好的截图，或直接导入 Ente Auth 等应用的 otpauth 导出文件。",
                "Press ⌃⇧⌘4 to screenshot a QR code, then read it here. You can also pick a saved screenshot or import an otpauth export file from Ente Auth and similar apps."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let importResult {
                if importResult.isEmpty {
                    Label(
                        L10n.text(
                            "没有在「\(importResult.sourceTitle)」里识别到二维码",
                            "No QR code was found in \(importResult.sourceTitle)"
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.text(
                                "识别到 \(importResult.items.count) 个二维码",
                                "\(importResult.items.count) QR codes found"
                            ))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if importResult.drafts.count > 1 {
                                Button {
                                    addAll(importResult.drafts)
                                } label: {
                                    Label(
                                        L10n.text("全部添加", "Add All"),
                                        systemImage: "plus"
                                    )
                                }
                                .buttonStyle(LumaTextButtonStyle(emphasis: .primary, height: 28))
                            }
                        }

                        ForEach(importResult.items) { item in
                            importItemRow(item)
                        }
                    }
                }
            }
        }
    }

    private func importItemRow(_ item: TwoFactorImport.Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.draft == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(item.draft == nil ? Color.orange : Color.green)

            if let draft = item.draft {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(draft.displaySubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("添加", "Add")) { addAll([draft]) }
                    .buttonStyle(LumaTextButtonStyle(height: 28))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("无法识别的内容", "Unrecognized Content"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.error?.localizedDescription ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
        .padding(12)
        .lumaCard(cornerRadius: LumaRadius.card)
    }

    // MARK: 预览与提交

    private var parsedLink: Result<TwoFactorAccountDraft, OTPAuthImportError>? {
        let text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return OTPAuthURIParser.draft(from: text)
    }

    private var draftResult: Result<TwoFactorAccountDraft, OTPAuthImportError> {
        if !isEditing, tab == .link, let parsedLink { return parsedLink }
        return TwoFactorAccountDraft(
            issuer: issuer,
            name: name,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period
        ).validated()
    }

    @ViewBuilder
    private func draftPreview(_ result: Result<TwoFactorAccountDraft, OTPAuthImportError>) -> some View {
        switch result {
        case .success(let draft):
            if let key = Base32.decode(draft.secret) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(draft.displaySubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(TOTPGenerator.grouped(TOTPGenerator.code(
                        secret: key,
                        algorithm: draft.algorithm,
                        digits: draft.digits,
                        period: draft.period,
                        at: now
                    )))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .lumaCard(cornerRadius: LumaRadius.card)
            }
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        switch draftResult {
        case .failure(let error):
            message = error.localizedDescription
            isErrorMessage = true
        case .success(let draft):
            if let account = editingAccount {
                guard store.update(account, with: draft) else {
                    message = L10n.text("保存失败，请重试", "Saving failed. Try again.")
                    isErrorMessage = true
                    return
                }
                onFinish(L10n.text("已更新「\(draft.displayTitle)」", "Updated \"\(draft.displayTitle)\""))
                return
            }
            addAll([draft])
        }
    }

    private func addAll(_ drafts: [TwoFactorAccountDraft]) {
        let summary = store.addAll(drafts)
        guard !summary.isEmpty else { return }
        guard summary.isProblem else {
            onFinish(summary.message)
            return
        }
        message = summary.message
        isErrorMessage = true
    }

    private func readClipboardImage() {
        guard let image = TwoFactorClipboardImage.read() else {
            importResult = nil
            message = L10n.text("剪贴板里没有图片", "There is no image on the clipboard")
            isErrorMessage = true
            return
        }
        message = nil
        importResult = TwoFactorImporter.importFromClipboardImage(image)
    }

    private func chooseExportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.text(
            "选择包含 otpauth:// 链接的导出文件",
            "Choose an export file containing otpauth:// links"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        message = nil
        importResult = TwoFactorImporter.importFromExportFile(url)
    }

    private func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        message = nil
        importResult = TwoFactorImporter.importFromFile(url)
    }

    /// 链接页签打开时，如果剪贴板里正好是链接就直接填好，省一次粘贴。
    private func prefillLinkFromClipboard() {
        guard !didPrefillLink, !isEditing, tab == .link, linkText.isEmpty else { return }
        didPrefillLink = true
        guard let text = NSPasteboard.general.string(forType: .string),
              OTPAuthURIParser.firstLink(in: text) != nil else { return }
        linkText = text
    }
}
