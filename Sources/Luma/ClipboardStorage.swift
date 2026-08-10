import AppKit
import CryptoKit
import Foundation

enum ClipboardRetentionPeriod: String, CaseIterable, Identifiable, Codable {
    case threeDays
    case sevenDays
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeDays: L10n.text("3 天", "3 Days")
        case .sevenDays: L10n.text("7 天", "7 Days")
        case .oneMonth: L10n.text("1 个月", "1 Month")
        case .threeMonths: L10n.text("3 个月", "3 Months")
        case .sixMonths: L10n.text("6 个月", "6 Months")
        case .oneYear: L10n.text("1 年", "1 Year")
        }
    }

    func cutoffDate(from date: Date, calendar: Calendar = .current) -> Date {
        let components: DateComponents
        switch self {
        case .threeDays: components = DateComponents(day: -3)
        case .sevenDays: components = DateComponents(day: -7)
        case .oneMonth: components = DateComponents(month: -1)
        case .threeMonths: components = DateComponents(month: -3)
        case .sixMonths: components = DateComponents(month: -6)
        case .oneYear: components = DateComponents(year: -1)
        }
        return calendar.date(byAdding: components, to: date) ?? date
    }

    func shouldKeep(_ entry: ClipboardEntry, relativeTo date: Date, calendar: Calendar = .current) -> Bool {
        entry.isFavorite || entry.copiedAt >= cutoffDate(from: date, calendar: calendar)
    }
}

enum ClipboardStorageLimit: Int, CaseIterable, Identifiable, Codable {
    case oneHundredMB = 100
    case twoHundredFiftyMB = 250
    case fiveHundredMB = 500
    case oneGB = 1_024

    var id: Int { rawValue }
    var maximumBytes: Int64 { Int64(rawValue) * 1_024 * 1_024 }
    var title: String { rawValue == 1_024 ? "1 GB" : "\(rawValue) MB" }
}

struct ClipboardImage: Equatable {
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()
    private let identity: String

    let inlineData: Data?
    let fileURL: URL?

    init(data: Data) {
        identity = Self.sha256(data)
        inlineData = data
        fileURL = nil
    }

    init(fileURL: URL) {
        identity = fileURL.standardizedFileURL.path
        inlineData = nil
        self.fileURL = fileURL
    }

    static func == (lhs: ClipboardImage, rhs: ClipboardImage) -> Bool {
        lhs.identity == rhs.identity
    }

    func makeImage() -> NSImage? {
        if let inlineData { return NSImage(data: inlineData) }
        if let fileURL { return NSImage(contentsOf: fileURL) }
        return nil
    }

    func dataForPersistence() -> Data? {
        let original: Data?
        if let inlineData {
            original = inlineData
        } else if let fileURL {
            original = try? Data(contentsOf: fileURL, options: .mappedIfSafe)
        } else {
            original = nil
        }
        guard let original else { return nil }
        guard let image = NSImage(data: original),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return original
        }
        return png.count < original.count ? png : original
    }

    func thumbnail(maxDimension: CGFloat = 96) -> NSImage? {
        let key = "\(storageIdentity):\(Int(maxDimension))" as NSString
        if let cached = Self.thumbnailCache.object(forKey: key) { return cached }
        guard let image = makeImage(), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = NSSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()
        Self.thumbnailCache.setObject(thumbnail, forKey: key, cost: Int(size.width * size.height * 4))
        return thumbnail
    }

    var storageByteCount: Int64 {
        if let inlineData { return Int64(inlineData.count) }
        guard let fileURL,
              let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return 0 }
        return Int64(size)
    }

    var storageIdentity: String {
        identity
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

final class ClipboardStorage {
    let directory: URL
    private let indexURL: URL
    private let imagesDirectory: URL
    private let fileManager: FileManager

    init(directory: URL = ClipboardStorage.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.indexURL = directory.appendingPathComponent("history.json", isDirectory: false)
        self.imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        self.fileManager = fileManager
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Luma", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
    }

    func load() -> [ClipboardEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let data = try? Data(contentsOf: indexURL),
              let records = try? decoder.decode([StoredEntry].self, from: data) else {
            return []
        }
        return records
            .compactMap(makeEntry)
            .sorted { $0.copiedAt > $1.copiedAt }
    }

    func save(_ entries: [ClipboardEntry]) {
        do {
            try prepareDirectories()
            let records = try entries.map { entry in
                try autoreleasepool {
                    try makeRecord(entry)
                }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(records).write(to: indexURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
            removeOrphanedImages(keeping: Set(records.compactMap(\.imageFileName)))
        } catch {
            NSLog("Luma clipboard persistence failed: %@", error.localizedDescription)
        }
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: imagesDirectory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private func makeRecord(_ entry: ClipboardEntry) throws -> StoredEntry {
        switch entry.payload {
        case .text(let text):
            return StoredEntry(entry: entry, kind: .text, text: text)
        case .link(let url):
            return StoredEntry(entry: entry, kind: .link, urls: [url.absoluteString])
        case .files(let urls):
            return StoredEntry(entry: entry, kind: .file, urls: urls.map(\.absoluteString))
        case .image(let image):
            guard let data = image.dataForPersistence() else { throw StorageError.missingImageData }
            let fileName = ClipboardImage.sha256(data) + ".image"
            let destination = imagesDirectory.appendingPathComponent(fileName, isDirectory: false)
            if !fileManager.fileExists(atPath: destination.path) {
                try data.write(to: destination, options: .atomic)
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
            return StoredEntry(entry: entry, kind: .image, imageFileName: fileName)
        }
    }

    private func makeEntry(_ record: StoredEntry) -> ClipboardEntry? {
        let payload: ClipboardPayload
        switch record.kind {
        case .text:
            guard let text = record.text else { return nil }
            payload = .text(text)
        case .link:
            guard let value = record.urls?.first, let url = URL(string: value) else { return nil }
            payload = .link(url)
        case .file:
            let urls = (record.urls ?? []).compactMap(URL.init(string:))
            guard !urls.isEmpty else { return nil }
            payload = .files(urls)
        case .image:
            guard let fileName = record.imageFileName else { return nil }
            let url = imagesDirectory.appendingPathComponent(fileName, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            payload = .image(ClipboardImage(fileURL: url))
        }
        return ClipboardEntry(
            id: record.id,
            payload: payload,
            copiedAt: record.copiedAt,
            isFavorite: record.isFavorite
        )
    }

    private func removeOrphanedImages(keeping fileNames: Set<String>) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files where !fileNames.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }
    }

    private enum StorageError: Error {
        case missingImageData
    }

    private enum StoredKind: String, Codable {
        case text
        case image
        case file
        case link
    }

    private struct StoredEntry: Codable {
        let id: UUID
        let copiedAt: Date
        let isFavorite: Bool
        let kind: StoredKind
        let text: String?
        let urls: [String]?
        let imageFileName: String?

        init(
            entry: ClipboardEntry,
            kind: StoredKind,
            text: String? = nil,
            urls: [String]? = nil,
            imageFileName: String? = nil
        ) {
            id = entry.id
            copiedAt = entry.copiedAt
            isFavorite = entry.isFavorite
            self.kind = kind
            self.text = text
            self.urls = urls
            self.imageFileName = imageFileName
        }
    }
}
