import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

enum FileKind: String {
    case file
    case folder
    case symlink
}

enum FileSortMode: String, CaseIterable, Identifiable {
    case system
    case name
    case date
    case type
    case size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Default"
        case .name: return "Name"
        case .date: return "Date"
        case .type: return "Type"
        case .size: return "Size"
        }
    }
}

struct FileEntry: Identifiable, Hashable {
    let id: String
    let url: URL
    let destinationURL: URL
    let name: String
    let kind: FileKind
    let contentType: UTType
    let size: Int
    let created: Date?
    let modified: Date?
    let hidden: Bool
    let permissions: String
    let owner: String
    let group: String
    let readable: Bool
    let writable: Bool
    let executable: Bool

    init(url: URL) {
        let fm = FileManager.default
        let normalized = url.standardizedFileURL
        var destination = normalized
        let keys: Set<URLResourceKey> = [
            .isSymbolicLinkKey,
            .isDirectoryKey,
            .contentTypeKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isHiddenKey
        ]
        let values = try? normalized.resourceValues(forKeys: keys)
        let isLink = values?.isSymbolicLink ?? false
        let isDirectory = values?.isDirectory ?? false

        if isLink, let rawDestination = try? fm.destinationOfSymbolicLink(atPath: normalized.path) {
            if rawDestination.hasPrefix("/") {
                destination = URL(fileURLWithPath: rawDestination).standardizedFileURL
            } else {
                destination = normalized.deletingLastPathComponent()
                    .appendingPathComponent(rawDestination)
                    .standardizedFileURL
            }
        }

        var mode = ""
        var ownerName = ""
        var groupName = ""
        if let attributes = try? fm.attributesOfItem(atPath: normalized.path) {
            if let value = attributes[.posixPermissions] as? NSNumber {
                mode = String(format: "%04o", value.intValue)
            }
            ownerName = attributes[.ownerAccountName] as? String ?? ""
            groupName = attributes[.groupOwnerAccountName] as? String ?? ""
        }

        id = normalized.path
        url = normalized
        destinationURL = destination
        name = normalized.lastPathComponent.isEmpty ? "/" : normalized.lastPathComponent
        kind = isLink ? .symlink : (isDirectory ? .folder : .file)
        contentType = values?.contentType ?? (isDirectory ? .folder : .data)
        size = values?.fileSize ?? 0
        created = values?.creationDate
        modified = values?.contentModificationDate
        hidden = values?.isHidden ?? normalized.lastPathComponent.hasPrefix(".")
        permissions = mode
        owner = ownerName
        group = groupName
        readable = fm.isReadableFile(atPath: normalized.path)
        writable = fm.isWritableFile(atPath: normalized.path)
        executable = fm.isExecutableFile(atPath: normalized.path)
    }
}

struct SavedLocation: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bookmark: Data
}

@MainActor
final class LocationStore: ObservableObject {
    @Published private(set) var savedLocations: [SavedLocation] = []

    private let defaultsKey = "filos.savedLocations.v1"
    private var resolved: [UUID: URL] = [:]
    private var scopedAccess: [UUID: URL] = [:]

    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL
    }

    var containerURL: URL {
        documentsURL.deletingLastPathComponent().standardizedFileURL
    }

    var temporaryURL: URL {
        FileManager.default.temporaryDirectory.standardizedFileURL
    }

    init() {
        load()
    }

    deinit {
        for url in scopedAccess.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func addLocation(_ pickedURL: URL) throws {
        let normalized = pickedURL.standardizedFileURL
        let started = normalized.startAccessingSecurityScopedResource()
        defer {
            if started {
                normalized.stopAccessingSecurityScopedResource()
            }
        }

        let bookmark = try normalized.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        if let existing = savedLocations.first(where: {
            guard let url = resolved[$0.id] else { return false }
            return url.standardizedFileURL.path == normalized.path
        }) {
            resolved[existing.id] = normalized
            if scopedAccess[existing.id] == nil && normalized.startAccessingSecurityScopedResource() {
                scopedAccess[existing.id] = normalized
            }
            return
        }

        let item = SavedLocation(
            id: UUID(),
            name: normalized.lastPathComponent.isEmpty ? "Location" : normalized.lastPathComponent,
            bookmark: bookmark
        )
        savedLocations.append(item)
        resolved[item.id] = normalized
        if normalized.startAccessingSecurityScopedResource() {
            scopedAccess[item.id] = normalized
        }
        persist()
    }

    func removeLocation(_ item: SavedLocation) {
        if let url = scopedAccess.removeValue(forKey: item.id) {
            url.stopAccessingSecurityScopedResource()
        }
        resolved.removeValue(forKey: item.id)
        savedLocations.removeAll { $0.id == item.id }
        persist()
    }

    func renameLocation(_ item: SavedLocation, to name: String) {
        guard let index = savedLocations.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedLocations[index].name = trimmed
        persist()
    }

    func url(for item: SavedLocation) -> URL? {
        resolved[item.id]
    }

    var authorizedRoots: [URL] {
        var roots = [containerURL]
        roots.append(contentsOf: savedLocations.compactMap { resolved[$0.id] })
        return roots
    }

    func isAuthorized(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL
        return authorizedRoots.contains { root in
            Self.contains(candidate, in: root)
        }
    }

    func validatedURL(from raw: String, relativeTo base: URL? = nil) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else if let base {
            candidate = base.appendingPathComponent(trimmed).standardizedFileURL
        } else {
            return nil
        }

        return isAuthorized(candidate) ? candidate : nil
    }

    func displayName(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path == documentsURL.path { return "Documents" }
        if path == temporaryURL.path { return "Temp" }
        if path == containerURL.path { return "Container" }
        if let saved = savedLocations.first(where: { resolved[$0.id]?.standardizedFileURL.path == path }) {
            return saved.name
        }
        return url.lastPathComponent
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data)
        else {
            return
        }

        savedLocations = decoded
        for item in decoded {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: item.bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                continue
            }

            let normalized = url.standardizedFileURL
            resolved[item.id] = normalized
            if normalized.startAccessingSecurityScopedResource() {
                scopedAccess[item.id] = normalized
            }

            if stale,
               let refreshed = try? normalized.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
               ),
               let index = savedLocations.firstIndex(where: { $0.id == item.id }) {
                savedLocations[index].bookmark = refreshed
            }
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedLocations) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func contains(_ child: URL, in root: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if childPath == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return childPath.hasPrefix(prefix)
    }
}

@MainActor
final class FavoriteStore: ObservableObject {
    @Published private(set) var paths: [String] = []

    private let key = "filos.favoritePaths.v1"

    init() {
        paths = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func contains(_ url: URL) -> Bool {
        paths.contains(url.standardizedFileURL.path)
    }

    func toggle(_ url: URL) {
        let path = url.standardizedFileURL.path
        if let index = paths.firstIndex(of: path) {
            paths.remove(at: index)
        } else {
            paths.append(path)
        }
        UserDefaults.standard.set(paths, forKey: key)
    }

    func remove(path: String) {
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: key)
    }
}

@MainActor
final class AppLog: ObservableObject {
    @Published var text = ""

    func write(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        text += "[\(formatter.string(from: Date()))] \(message)\n"
    }
}

enum FileOps {
    static let fm = FileManager.default

    static func contents(of url: URL, sort: FileSortMode, ascending: Bool) throws -> [FileEntry] {
        var entries = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentTypeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isHiddenKey
            ],
            options: []
        ).map(FileEntry.init)

        switch sort {
        case .system:
            break
        case .name:
            entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date:
            entries.sort { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
        case .type:
            entries.sort { $0.contentType.identifier < $1.contentType.identifier }
        case .size:
            entries.sort { $0.size < $1.size }
        }

        if !ascending {
            entries.reverse()
        }

        entries.sort {
            if $0.kind == $1.kind { return false }
            if $0.kind == .folder { return true }
            if $1.kind == .folder { return false }
            if $0.kind == .symlink { return true }
            return false
        }
        return entries
    }

    static func createFile(in directory: URL, name: String) throws {
        let destination = directory.appendingPathComponent(name)
        guard !fm.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try Data().write(to: destination)
    }

    static func createFolder(in directory: URL, name: String) throws {
        let destination = directory.appendingPathComponent(name)
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
    }

    static func createPlist(in directory: URL, name: String) throws {
        let filename = name.lowercased().hasSuffix(".plist") ? name : name + ".plist"
        let destination = directory.appendingPathComponent(filename)
        let data = try PropertyListSerialization.data(
            fromPropertyList: [String: Any](),
            format: .xml,
            options: 0
        )
        try data.write(to: destination, options: .atomic)
    }

    static func createSymlink(in directory: URL, destination target: URL) throws {
        let link = directory.appendingPathComponent(target.lastPathComponent)
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
    }

    static func rename(_ entry: FileEntry, to newName: String) throws {
        let destination = entry.url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !fm.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.moveItem(at: entry.url, to: destination)
    }

    static func duplicate(_ entry: FileEntry) throws {
        let parent = entry.url.deletingLastPathComponent()
        let ext = entry.url.pathExtension
        let stem = entry.url.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? "\(stem)_copy" : "\(stem)_copy.\(ext)"
        var destination = parent.appendingPathComponent(name)
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            let numbered = ext.isEmpty ? "\(stem)_copy_\(counter)" : "\(stem)_copy_\(counter).\(ext)"
            destination = parent.appendingPathComponent(numbered)
            counter += 1
        }
        try fm.copyItem(at: entry.url, to: destination)
    }

    static func move(_ entry: FileEntry, into directory: URL) throws {
        let destination = directory.appendingPathComponent(entry.url.lastPathComponent)
        guard !fm.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.moveItem(at: entry.url, to: destination)
    }

    static func remove(_ entry: FileEntry) throws {
        try fm.removeItem(at: entry.url)
    }

    static func zip(_ entry: FileEntry) throws {
        let destination = entry.url.appendingPathExtension("zip")
        guard !fm.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.zipItem(at: entry.url, to: destination, shouldKeepParent: true)
    }

    static func unzip(_ entry: FileEntry) throws {
        let destination = entry.url.deletingPathExtension()
        guard !fm.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try fm.unzipItem(at: entry.url, to: destination)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    static func importItems(_ urls: [URL], into directory: URL) throws {
        for source in urls {
            let access = source.startAccessingSecurityScopedResource()
            defer {
                if access {
                    source.stopAccessingSecurityScopedResource()
                }
            }
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        }
    }

    static func temporaryCopy(of entry: FileEntry) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(entry.url.pathExtension)
        try fm.copyItem(at: entry.url, to: destination)
        return destination
    }

    static func isPropertyList(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil
    }

    static func isText(_ url: URL) -> Bool {
        (try? String(contentsOf: url, encoding: .utf8)) != nil
    }
}

extension Date {
    var filosDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy h:mm a"
        return formatter.string(from: self)
    }
}

extension String: @retroactive Error {}
