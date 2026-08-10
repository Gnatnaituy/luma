import AppKit
import Carbon.HIToolbox
import SwiftUI

struct GlobalShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        let requiredModifiers = UInt32(controlKey | optionKey | cmdKey)
        guard carbonModifiers & requiredModifiers != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
    }

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        let key = Self.keyNames[keyCode] ?? L10n.text("按键 \(keyCode)", "Key \(keyCode)")
        return result + (key.count == 1 ? key.uppercased() : " " + key)
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9"
    ]
}

struct KeywordShortcutBinding: Codable, Equatable, Identifiable {
    let id: UUID
    var keyword: String
    var shortcut: GlobalShortcut?

    init(id: UUID = UUID(), keyword: String = "", shortcut: GlobalShortcut? = nil) {
        self.id = id
        self.keyword = keyword
        self.shortcut = shortcut
    }

    var normalizedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class ShortcutSettings: ObservableObject {
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var errorMessage: String?
    @Published private(set) var keywordBindings: [KeywordShortcutBinding]
    @Published private(set) var keywordErrorIDs: Set<UUID> = []

    var applyHandler: ((GlobalShortcut) -> Bool)?
    var keywordApplyHandler: ((UUID, GlobalShortcut?, GlobalShortcut?) -> Bool)?

    private let defaults: UserDefaults
    private let shortcutStorageKey = "Luma.globalShortcut"
    private let keywordStorageKey = "Luma.keywordShortcuts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: shortcutStorageKey),
           let saved = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
        if let data = defaults.data(forKey: keywordStorageKey),
           let saved = try? JSONDecoder().decode([KeywordShortcutBinding].self, from: data) {
            keywordBindings = saved
        } else {
            keywordBindings = []
        }
    }

    func bind(_ newShortcut: GlobalShortcut) {
        guard newShortcut != shortcut else {
            errorMessage = nil
            return
        }
        guard applyHandler?(newShortcut) ?? true else {
            errorMessage = L10n.text(
                "该快捷键已被其他应用占用，请换一个组合。",
                "That shortcut is used by another app. Choose a different combination."
            )
            return
        }
        shortcut = newShortcut
        errorMessage = nil
        if let data = try? JSONEncoder().encode(newShortcut) {
            defaults.set(data, forKey: shortcutStorageKey)
        }
    }

    func reportRegistrationFailure() {
        errorMessage = L10n.text(
            "当前快捷键已被其他应用占用，请录入新的组合。",
            "The current shortcut is used by another app. Record a new combination."
        )
    }

    @discardableResult
    func addKeywordBinding() -> UUID {
        let binding = KeywordShortcutBinding()
        keywordBindings.append(binding)
        persistKeywordBindings()
        return binding.id
    }

    func updateKeyword(id: UUID, keyword: String) {
        guard let index = keywordBindings.firstIndex(where: { $0.id == id }) else { return }
        keywordBindings[index].keyword = keyword
        persistKeywordBindings()
    }

    func bindKeywordShortcut(id: UUID, shortcut: GlobalShortcut) {
        guard let index = keywordBindings.firstIndex(where: { $0.id == id }) else { return }
        let previous = keywordBindings[index].shortcut
        guard previous != shortcut else {
            keywordErrorIDs.remove(id)
            return
        }
        guard keywordApplyHandler?(id, previous, shortcut) ?? true else {
            keywordErrorIDs.insert(id)
            return
        }
        keywordBindings[index].shortcut = shortcut
        keywordErrorIDs.remove(id)
        persistKeywordBindings()
    }

    func removeKeywordBinding(id: UUID) {
        guard let binding = keywordBindings.first(where: { $0.id == id }) else { return }
        guard keywordApplyHandler?(id, binding.shortcut, nil) ?? true else { return }
        keywordBindings.removeAll(where: { $0.id == id })
        keywordErrorIDs.remove(id)
        persistKeywordBindings()
    }

    func keyword(for id: UUID) -> String? {
        keywordBindings.first(where: { $0.id == id })?.normalizedKeyword
    }

    func reportKeywordRegistrationFailure(id: UUID) {
        keywordErrorIDs.insert(id)
    }

    private func persistKeywordBindings() {
        guard let data = try? JSONEncoder().encode(keywordBindings) else { return }
        defaults.set(data, forKey: keywordStorageKey)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: GlobalShortcut?
    let onChange: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onChange = onChange
        button.updateShortcut(shortcut)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onChange = onChange
        button.updateShortcut(shortcut)
    }
}

final class ShortcutRecorderButton: NSButton {
    var onChange: ((GlobalShortcut) -> Void)?
    private var shortcut: GlobalShortcut?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = L10n.text("设置快捷键", "Set Shortcut")
        bezelStyle = .shadowlessSquare
        isBordered = false
        controlSize = .large
        font = .systemFont(ofSize: 14, weight: .semibold)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        updateButtonBackground(isPressed: false)
        target = self
        action = #selector(beginRecording)
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        updateButtonBackground(isPressed: true)
        super.mouseDown(with: event)
        updateButtonBackground(isPressed: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateButtonBackground(isPressed: false)
    }

    func updateShortcut(_ shortcut: GlobalShortcut?) {
        self.shortcut = shortcut
        if !isRecording { title = shortcut?.displayString ?? L10n.text("设置快捷键", "Set Shortcut") }
    }

    @objc private func beginRecording() {
        isRecording = true
        title = L10n.text("请按新快捷键…", "Press a new shortcut…")
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }
        guard let newShortcut = GlobalShortcut(event: event) else {
            NSSound.beep()
            title = L10n.text("需包含 ⌘、⌥ 或 ⌃", "Include ⌘, ⌥, or ⌃")
            return
        }
        shortcut = newShortcut
        finishRecording()
        onChange?(newShortcut)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { finishRecording() }
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
        title = shortcut?.displayString ?? L10n.text("设置快捷键", "Set Shortcut")
    }

    private func updateButtonBackground(isPressed: Bool) {
        layer?.backgroundColor = NSColor.labelColor
            .withAlphaComponent(isPressed ? 0.10 : 0.045)
            .cgColor
    }
}
