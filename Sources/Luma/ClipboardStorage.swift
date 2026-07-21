import AppKit
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
        case .threeDays: "3 天"
        case .sevenDays: "7 天"
        case .oneMonth: "1 个月"
        case .threeMonths: "3 个月"
        case .sixMonths: "6 个月"
        case .oneYear: "1 年"
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

struct ClipboardImage: Equatable {
    let inlineData: Data?
    let fileURL: URL?

    init(data: Data) {
        inlineData = data
        fileURL = nil
    }

    init(fileURL: URL) {
        inlineData = nil
        self.fileURL = fileURL
    }

    func makeImage() -> NSImage? {
        if let inlineData { return NSImage(data: inlineData) }
        if let fileURL { return NSImage(contentsOf: fileURL) }
        return nil
    }

    func dataForPersistence() -> Data? {
        if let inlineData { return inlineData }
        guard let fileURL else { return nil }
        return try? Data(contentsOf: fileURL, options: .mappedIfSafe)
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
            let records = try entries.map(makeRecord)
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
            let fileName = entry.id.uuidString + ".image"
            let destination = imagesDirectory.appendingPathComponent(fileName, isDirectory: false)
            if !fileManager.fileExists(atPath: destination.path) {
                guard let data = image.dataForPersistence() else { throw StorageError.missingImageData }
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
