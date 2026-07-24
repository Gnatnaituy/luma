import AppKit

enum ClipboardKind: String, CaseIterable, Identifiable {
    case text
    case image
    case file
    case link

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "文本"
        case .image: "图片"
        case .file: "文件"
        case .link: "链接"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        case .link: "link"
        }
    }
}

enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case text
    case image
    case file
    case link

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .favorites: "收藏"
        case .text: "文本"
        case .image: "图片"
        case .file: "文件"
        case .link: "链接"
        }
    }
}

enum ClipboardPayload: Equatable {
    case text(String)
    case image(ClipboardImage)
    case files([URL])
    case link(URL)
}

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let payload: ClipboardPayload
    let copiedAt: Date
    var isFavorite: Bool

    init(id: UUID = UUID(), payload: ClipboardPayload, copiedAt: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.payload = payload
        self.copiedAt = copiedAt
        self.isFavorite = isFavorite
    }

    var kind: ClipboardKind {
        switch payload {
        case .text: .text
        case .image: .image
        case .files: .file
        case .link: .link
        }
    }

    var title: String {
        switch payload {
        case .text(let value): return value
        case .image: return "剪贴板图片"
        case .files(let urls):
            if urls.count == 1 { return urls[0].lastPathComponent }
            return urls[0].lastPathComponent + " 等 " + String(urls.count) + " 个文件"
        case .link(let url): return url.absoluteString
        }
    }

    var searchDisplayTitle: String {
        let compactTitle = title
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return compactTitle.isEmpty ? kind.title : compactTitle
    }

    func matchesSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return false }

        let payloadText: String
        switch payload {
        case .text(let value):
            payloadText = value
        case .image:
            payloadText = "剪贴板图片 图片 image"
        case .files(let urls):
            payloadText = urls
                .flatMap { [$0.lastPathComponent, $0.path] }
                .joined(separator: " ")
        case .link(let url):
            payloadText = url.absoluteString
        }

        let searchableText = [payloadText, kind.title, isFavorite ? "收藏" : ""]
            .joined(separator: " ")
        return terms.allSatisfy(searchableText.localizedCaseInsensitiveContains)
    }
}

enum ClipboardHistory {
    static func inserting(
        _ payload: ClipboardPayload,
        into entries: [ClipboardEntry],
        copiedAt: Date = Date()
    ) -> [ClipboardEntry] {
        switch payload {
        case .text, .link:
            let duplicates = entries.filter { $0.payload == payload }
            let isFavorite = duplicates.contains(where: \.isFavorite)
            var updated = entries.filter { $0.payload != payload }
            updated.insert(
                ClipboardEntry(
                    payload: payload,
                    copiedAt: copiedAt,
                    isFavorite: isFavorite
                ),
                at: 0
            )
            return updated
        case .image, .files:
            guard entries.first?.payload != payload else { return entries }
            var updated = entries
            updated.insert(ClipboardEntry(payload: payload, copiedAt: copiedAt), at: 0)
            return updated
        }
    }
}

final class ClipboardMonitor: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var retentionPeriod: ClipboardRetentionPeriod
    @Published private(set) var storageLimit: ClipboardStorageLimit
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let storage: ClipboardStorage?
    private let settings: UserDefaults
    private let persistenceQueue = DispatchQueue(label: "app.luma.clipboard.persistence", qos: .utility)
    private var queuedPersistenceSnapshot: [ClipboardEntry]?
    private var isPersistenceScheduled = false
    private var lastPurgeDate: Date
    private static let retentionKey = "luma.clipboard.retention.v1"
    private static let storageLimitKey = "luma.clipboard.storage-limit.v1"
    private static let storageFormatKey = "luma.clipboard.storage-format.v2"
    private static let currentStorageFormat = 2

    init(
        entries: [ClipboardEntry]? = nil,
        storage: ClipboardStorage? = nil,
        settings: UserDefaults = .standard,
        retentionPeriod: ClipboardRetentionPeriod? = nil,
        storageLimit: ClipboardStorageLimit? = nil,
        referenceDate: Date = Date()
    ) {
        self.settings = settings
        let savedRetention = settings.string(forKey: Self.retentionKey).flatMap(ClipboardRetentionPeriod.init(rawValue:))
        let resolvedRetention = retentionPeriod ?? savedRetention ?? .threeMonths
        let savedStorageLimit = ClipboardStorageLimit(
            rawValue: settings.integer(forKey: Self.storageLimitKey)
        )
        let resolvedStorageLimit = storageLimit ?? savedStorageLimit ?? .fiveHundredMB
        self.retentionPeriod = resolvedRetention
        self.storageLimit = resolvedStorageLimit
        self.lastPurgeDate = referenceDate

        let resolvedStorage = storage ?? (entries == nil ? ClipboardStorage() : nil)
        self.storage = resolvedStorage
        let loadedEntries = entries ?? resolvedStorage?.load() ?? []
        let retainedEntries = Self.enforcingStorageLimit(
            on: loadedEntries.filter {
            resolvedRetention.shouldKeep($0, relativeTo: referenceDate)
            },
            limit: resolvedStorageLimit
        )
        self.entries = retainedEntries

        let needsStorageMigration = settings.integer(forKey: Self.storageFormatKey)
            < Self.currentStorageFormat
        if retainedEntries.count != loadedEntries.count || needsStorageMigration,
           let resolvedStorage {
            persistenceQueue.async {
                resolvedStorage.save(retainedEntries)
                settings.set(Self.currentStorageFormat, forKey: Self.storageFormatKey)
            }
        }
    }

    func start() {
        captureIfNeeded(force: true)
        purgeExpired()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.25
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        persist()
        flushPersistence()
    }

    func filteredEntries(_ filter: ClipboardFilter) -> [ClipboardEntry] {
        switch filter {
        case .all: entries
        case .favorites: entries.filter(\.isFavorite)
        case .text: entries.filter { $0.kind == .text }
        case .image: entries.filter { $0.kind == .image }
        case .file: entries.filter { $0.kind == .file }
        case .link: entries.filter { $0.kind == .link }
        }
    }

    func filteredEntries(_ filter: ClipboardFilter, matching query: String) -> [ClipboardEntry] {
        let filtered = filteredEntries(filter)
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return filtered }
        return filtered.filter { $0.matchesSearch(value) }
    }

    func copy(_ text: String) {
        write(.text(text))
    }

    func copy(_ entry: ClipboardEntry) {
        write(entry.payload)
    }

    func currentPlainText() -> String? {
        Self.plainText(from: .general)
    }

    static func plainText(from pasteboard: NSPasteboard) -> String? {
        guard case .text(let text) = readPayload(from: pasteboard) else { return nil }
        return text
    }

    func toggleFavorite(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite.toggle()
        persist()
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clearHistory() {
        entries.removeAll { !$0.isFavorite }
        persist()
    }

    func updateRetentionPeriod(_ period: ClipboardRetentionPeriod, referenceDate: Date = Date()) {
        guard retentionPeriod != period else { return }
        retentionPeriod = period
        settings.set(period.rawValue, forKey: Self.retentionKey)
        purgeExpired(referenceDate: referenceDate, forcePersistence: true)
    }

    func updateStorageLimit(_ limit: ClipboardStorageLimit) {
        guard storageLimit != limit else { return }
        storageLimit = limit
        settings.set(limit.rawValue, forKey: Self.storageLimitKey)
        enforceStorageLimit()
        persist()
    }

    func purgeExpired(referenceDate: Date = Date(), forcePersistence: Bool = false) {
        lastPurgeDate = referenceDate
        let originalCount = entries.count
        entries.removeAll { !retentionPeriod.shouldKeep($0, relativeTo: referenceDate) }
        if forcePersistence || entries.count != originalCount {
            persist()
        }
    }

    func flushPersistence() {
        guard let storage else {
            persistenceQueue.sync {}
            return
        }
        let snapshot = entries
        persistenceQueue.sync {
            queuedPersistenceSnapshot = nil
            isPersistenceScheduled = false
            storage.save(snapshot)
        }
    }

    private func write(_ payload: ClipboardPayload) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch payload {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .link(let url):
            pasteboard.writeObjects([url as NSURL])
        case .files(let urls):
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        case .image(let storedImage):
            if let image = storedImage.makeImage() {
                pasteboard.writeObjects([image])
            }
        }
        captureIfNeeded(force: true)
    }

    private func captureIfNeeded(force: Bool = false) {
        let pasteboard = NSPasteboard.general
        guard force || pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let payload = Self.readPayload(from: pasteboard) else { return }
        let updatedEntries = ClipboardHistory.inserting(payload, into: entries)
        guard updatedEntries != entries else { return }
        entries = updatedEntries
        enforceStorageLimit()
        persist()
    }

    private static func readPayload(from pasteboard: NSPasteboard) -> ClipboardPayload? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return .files(urls)
        }

        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           data.count <= 12 * 1024 * 1024,
           NSImage(data: data) != nil {
            return .image(ClipboardImage(data: data))
        }

        let text = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string)
        guard let text, !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return .link(url)
        }
        return .text(text)
    }

    private func tick() {
        captureIfNeeded()
        if Date().timeIntervalSince(lastPurgeDate) >= 60 * 60 {
            purgeExpired()
        }
    }

    private func persist() {
        guard let storage else { return }
        let snapshot = entries
        persistenceQueue.async { [weak self] in
            guard let self else { return }
            self.queuedPersistenceSnapshot = snapshot
            guard !self.isPersistenceScheduled else { return }
            self.isPersistenceScheduled = true
            self.persistenceQueue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                self.isPersistenceScheduled = false
                guard let latest = self.queuedPersistenceSnapshot else { return }
                self.queuedPersistenceSnapshot = nil
                storage.save(latest)
            }
        }
    }

    private func enforceStorageLimit() {
        entries = Self.enforcingStorageLimit(on: entries, limit: storageLimit)
    }

    static func enforcingStorageLimit(
        on entries: [ClipboardEntry],
        limit: ClipboardStorageLimit
    ) -> [ClipboardEntry] {
        var countedImages = Set<String>()
        var usedBytes: Int64 = 0

        for entry in entries where entry.isFavorite {
            guard case .image(let image) = entry.payload,
                  countedImages.insert(image.storageIdentity).inserted else { continue }
            usedBytes += image.storageByteCount
        }

        return entries.filter { entry in
            guard case .image(let image) = entry.payload else { return true }
            let identity = image.storageIdentity
            if entry.isFavorite || countedImages.contains(identity) { return true }
            let size = image.storageByteCount
            guard usedBytes + size <= limit.maximumBytes else { return false }
            countedImages.insert(identity)
            usedBytes += size
            return true
        }
    }
}
