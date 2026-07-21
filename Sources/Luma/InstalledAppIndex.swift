import Combine
import Foundation

struct InstalledApplication: Equatable, Identifiable {
    let url: URL
    let name: String
    let bundleIdentifier: String?

    var id: String { url.path }

    func matches(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return false }
        return name.lowercased().contains(value)
            || (bundleIdentifier?.lowercased().contains(value) ?? false)
    }
}

final class InstalledAppIndex: ObservableObject {
    @Published private(set) var applications: [InstalledApplication]

    private let roots: [URL]
    private var hasStarted: Bool

    init(
        applications: [InstalledApplication]? = nil,
        roots: [URL] = InstalledAppIndex.standardRoots
    ) {
        self.roots = roots
        self.applications = applications ?? []
        hasStarted = applications != nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let roots = roots
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let applications = Self.scan(roots: roots)
            DispatchQueue.main.async {
                self?.applications = applications
            }
        }
    }

    func search(_ query: String, limit: Int = 12) -> [InstalledApplication] {
        Array(applications.lazy.filter { $0.matches(query) }.prefix(limit))
    }

    static func scan(roots: [URL], fileManager: FileManager = .default) -> [InstalledApplication] {
        var found: [String: InstalledApplication] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .localizedNameKey]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory == true else { continue }
                let name = values?.localizedName
                    ?? url.deletingPathExtension().lastPathComponent
                let application = InstalledApplication(
                    url: url,
                    name: name.replacingOccurrences(of: ".app", with: ""),
                    bundleIdentifier: Bundle(url: url)?.bundleIdentifier
                )
                found[url.standardizedFileURL.path] = application
            }
        }

        return found.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static var standardRoots: [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true)
        ]
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        roots.append(homeApplications)
        return roots
    }
}
