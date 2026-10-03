import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import UIKit

struct ContentView: View {
    @EnvironmentObject private var locations: LocationStore
    @EnvironmentObject private var favorites: FavoriteStore
    @EnvironmentObject private var log: AppLog

    @State private var showLocationPicker = false
    @State private var showSettings = false
    @State private var showFavorites = false
    @State private var showLogs = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink(destination: BrowserView(directoryURL: locations.documentsURL)) {
                        LocationRow(title: "Documents", subtitle: locations.documentsURL.path, symbol: "doc")
                    }
                    NavigationLink(destination: BrowserView(directoryURL: locations.containerURL)) {
                        LocationRow(title: "Container", subtitle: locations.containerURL.path, symbol: "shippingbox")
                    }
                    NavigationLink(destination: BrowserView(directoryURL: locations.temporaryURL)) {
                        LocationRow(title: "Temp", subtitle: locations.temporaryURL.path, symbol: "clock.arrow.circlepath")
                    }
                } header: {
                    Label("Filos", systemImage: "folder")
                }

                Section {
                    ForEach(locations.savedLocations) { item in
                        if let url = locations.url(for: item) {
                            NavigationLink(destination: BrowserView(directoryURL: url)) {
                                LocationRow(title: item.name, subtitle: url.path, symbol: "externaldrive")
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    locations.removeLocation(item)
                                } label: {
                                    Label("Remove Location", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        showLocationPicker = true
                    } label: {
                        Label("Add Location…", systemImage: "plus")
                    }
                } header: {
                    Label("Locations", systemImage: "externaldrive")
                } footer: {
                    Text("Choose folders from Files, iCloud Drive, or a connected external drive. Filos keeps access using a security-scoped bookmark.")
                }
            }
            .navigationTitle("/")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showFavorites = true
                        } label: {
                            Label("Favorites", systemImage: "star")
                        }
                        Button {
                            showLogs = true
                        } label: {
                            Label("Logs", systemImage: "terminal")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .fileImporter(
            isPresented: $showLocationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                try locations.addLocation(url)
                log.write("Added location: \(url.path)")
            } catch {
                errorMessage = error.localizedDescription
                log.write("Failed to add location: \(error)")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesView()
        }
        .sheet(isPresented: $showLogs) {
            LogView()
        }
        .alert(item: Binding(
            get: { errorMessage.map(MessageBox.init) },
            set: { _ in errorMessage = nil }
        )) { message in
            Alert(title: Text("Filos"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }
}

private struct LocationRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct MessageBox: Identifiable {
    let id = UUID()
    let text: String
    init(_ text: String) { self.text = text }
}

private enum PromptAction {
    case newFile
    case newFolder
    case newPlist
    case newSymlink
    case rename(FileEntry)
    case move(FileEntry)
    case goTo
}

private struct PromptRequest: Identifiable {
    let id = UUID()
    let title: String
    let placeholder: String
    let initialText: String
    let action: PromptAction
}

private struct ViewerRoute: Identifiable {
    enum Kind {
        case info
        case text
        case plist
    }

    let id = UUID()
    let kind: Kind
    let entry: FileEntry
}

struct BrowserView: View {
    @EnvironmentObject private var locations: LocationStore
    @EnvironmentObject private var favorites: FavoriteStore
    @EnvironmentObject private var log: AppLog

    let directoryURL: URL

    @State private var entries: [FileEntry] = []
    @State private var searchText = ""
    @State private var stateMessage: String?
    @State private var prompt: PromptRequest?
    @State private var viewer: ViewerRoute?
    @State private var quickLookURL: URL?
    @State private var shareURL: ShareItem?
    @State private var jumpURL: URL?
    @State private var showImporter = false
    @State private var showFavorites = false
    @State private var showSettings = false
    @State private var showLogs = false

    @AppStorage("filos.sortMode") private var sortMode: FileSortMode = .system
    @AppStorage("filos.ascending") private var ascending = true
    @AppStorage("filos.hideDates") private var hideDates = false

    private var visibleEntries: [FileEntry] {
        if searchText.isEmpty { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if let stateMessage, entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(stateMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.largeTitle)
                    Text("This directory is empty.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleEntries) { entry in
                        row(for: entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if entry.writable {
                                    Button(role: .destructive) {
                                        perform("Delete \(entry.name)") {
                                            try FileOps.remove(entry)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }

                                Button {
                                    favorites.toggle(entry.url)
                                } label: {
                                    Label(
                                        favorites.contains(entry.url) ? "Unfavorite" : "Favorite",
                                        systemImage: favorites.contains(entry.url) ? "star.slash" : "star"
                                    )
                                }
                                .tint(.yellow)
                            }
                    }
                }
                .searchable(text: $searchText)
                .refreshable {
                    load()
                }
            }
        }
        .navigationTitle(directoryURL.lastPathComponent.isEmpty ? "/" : directoryURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(FileSortMode.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Button {
                        ascending.toggle()
                    } label: {
                        Label(ascending ? "Ascending" : "Descending", systemImage: ascending ? "chevron.up" : "chevron.down")
                    }
                    .disabled(sortMode == .system)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Menu {
                        Button {
                            prompt = PromptRequest(
                                title: "What would you like to call your new file?",
                                placeholder: "new.txt",
                                initialText: "",
                                action: .newFile
                            )
                        } label: {
                            Label("File", systemImage: "doc")
                        }

                        Button {
                            prompt = PromptRequest(
                                title: "What would you like to call your new property list?",
                                placeholder: "Settings",
                                initialText: "",
                                action: .newPlist
                            )
                        } label: {
                            Label("Property List", systemImage: "tablecells")
                        }

                        Button {
                            prompt = PromptRequest(
                                title: "What would you like to call your new folder?",
                                placeholder: "Folder Name",
                                initialText: "",
                                action: .newFolder
                            )
                        } label: {
                            Label("Folder", systemImage: "folder")
                        }

                        Button {
                            prompt = PromptRequest(
                                title: "Where should the new symlink point?",
                                placeholder: "Authorized path",
                                initialText: directoryURL.path,
                                action: .newSymlink
                            )
                        } label: {
                            Label("Symlink", systemImage: "arrow.up.right.circle")
                        }
                    } label: {
                        Label("New…", systemImage: "plus")
                    }

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import File", systemImage: "arrow.down.doc")
                    }

                    Divider()

                    Button {
                        showFavorites = true
                    } label: {
                        Label("Favorites", systemImage: "star")
                    }

                    Button {
                        prompt = PromptRequest(
                            title: "Where would you like to go?",
                            placeholder: "Authorized path",
                            initialText: directoryURL.path,
                            action: .goTo
                        )
                    } label: {
                        Label("Go to Directory…", systemImage: "arrow.right.arrow.left")
                    }

                    Divider()

                    Button {
                        showLogs = true
                    } label: {
                        Label("Logs", systemImage: "terminal")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .background(
            NavigationLink(
                destination: jumpDestination,
                isActive: Binding(
                    get: { jumpURL != nil },
                    set: { if !$0 { jumpURL = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        )
        .onAppear { load() }
        .onChange(of: sortMode) { _ in load() }
        .onChange(of: ascending) { _ in load() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            do {
                let urls = try result.get()
                try FileOps.importItems(urls, into: directoryURL)
                log.write("Imported \(urls.count) item(s) into \(directoryURL.path)")
                load()
            } catch {
                showError(error)
            }
        }
        .sheet(item: $prompt) { request in
            PromptSheet(request: request) { value in
                handlePrompt(request, value: value)
            }
        }
        .sheet(item: $viewer) { route in
            switch route.kind {
            case .info:
                FileInfoView(entry: route.entry)
            case .text:
                TextEditorView(entry: route.entry)
            case .plist:
                PlistEditorView(entry: route.entry)
            }
        }
        .sheet(item: $shareURL) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showLogs) {
            LogView()
        }
        .quickLookPreview($quickLookURL)
        .alert(item: Binding(
            get: { stateMessage.map(MessageBox.init) },
            set: { _ in stateMessage = nil }
        )) { message in
            Alert(title: Text("Filos"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private func row(for entry: FileEntry) -> some View {
        if entry.kind == .folder {
            NavigationLink(destination: BrowserView(directoryURL: entry.url)) {
                BrowserRow(entry: entry, hideDates: hideDates)
            }
            .contextMenu { entryMenu(entry) }
        } else if entry.kind == .symlink && locations.isAuthorized(entry.destinationURL) {
            NavigationLink(destination: BrowserView(directoryURL: entry.destinationURL)) {
                BrowserRow(entry: entry, hideDates: hideDates)
            }
            .contextMenu { entryMenu(entry) }
        } else {
            Button {
                open(entry)
            } label: {
                BrowserRow(entry: entry, hideDates: hideDates)
            }
            .buttonStyle(.plain)
            .contextMenu { entryMenu(entry) }
        }
    }

    @ViewBuilder
    private func entryMenu(_ entry: FileEntry) -> some View {
        Button {
            viewer = ViewerRoute(kind: .info, entry: entry)
        } label: {
            Label("Get Info", systemImage: "info.circle")
        }

        if entry.kind == .file {
            Button {
                open(entry)
            } label: {
                Label("Open", systemImage: "doc.text.magnifyingglass")
            }
        }

        Divider()

        if entry.writable {
            Button {
                prompt = PromptRequest(
                    title: "What would you like to rename this item to?",
                    placeholder: entry.name,
                    initialText: entry.name,
                    action: .rename(entry)
                )
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }

        if entry.readable {
            Button {
                perform("Duplicate \(entry.name)") {
                    try FileOps.duplicate(entry)
                }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            if entry.kind != .symlink {
                if entry.contentType.conforms(to: .zip) {
                    Button {
                        perform("Uncompress \(entry.name)") {
                            try FileOps.unzip(entry)
                        }
                    } label: {
                        Label("Uncompress", systemImage: "archivebox")
                    }
                } else {
                    Button {
                        perform("Compress \(entry.name)") {
                            try FileOps.zip(entry)
                        }
                    } label: {
                        Label("Compress", systemImage: "archivebox")
                    }
                }
            }

            Button {
                prompt = PromptRequest(
                    title: "Where would you like to move this item?",
                    placeholder: "Authorized folder path",
                    initialText: directoryURL.path,
                    action: .move(entry)
                )
            } label: {
                Label("Move", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }

        Button {
            do {
                let temp = try FileOps.temporaryCopy(of: entry)
                shareURL = ShareItem(url: temp)
            } catch {
                showError(error)
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Button {
            favorites.toggle(entry.url)
        } label: {
            Label(
                favorites.contains(entry.url) ? "Unfavorite" : "Favorite",
                systemImage: favorites.contains(entry.url) ? "star.slash" : "star"
            )
        }

        if entry.writable {
            Divider()
            Button(role: .destructive) {
                perform("Delete \(entry.name)") {
                    try FileOps.remove(entry)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var jumpDestination: some View {
        if let jumpURL {
            BrowserView(directoryURL: jumpURL)
        } else {
            EmptyView()
        }
    }

    private func load() {
        guard locations.isAuthorized(directoryURL) else {
            entries = []
            stateMessage = "This location is outside the app's authorized file roots."
            return
        }

        do {
            entries = try FileOps.contents(of: directoryURL, sort: sortMode, ascending: ascending)
            stateMessage = nil
        } catch {
            entries = []
            stateMessage = error.localizedDescription
            log.write("Failed to load \(directoryURL.path): \(error)")
        }
    }

    private func open(_ entry: FileEntry) {
        if FileOps.isPropertyList(entry.url) {
            viewer = ViewerRoute(kind: .plist, entry: entry)
        } else if FileOps.isText(entry.url) {
            viewer = ViewerRoute(kind: .text, entry: entry)
        } else {
            quickLookURL = entry.url
        }
    }

    private func handlePrompt(_ request: PromptRequest, value: String?) {
        guard let value else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            switch request.action {
            case .newFile:
                try FileOps.createFile(in: directoryURL, name: trimmed)
            case .newFolder:
                try FileOps.createFolder(in: directoryURL, name: trimmed)
            case .newPlist:
                try FileOps.createPlist(in: directoryURL, name: trimmed)
            case .newSymlink:
                guard let target = locations.validatedURL(from: trimmed, relativeTo: directoryURL) else {
                    throw "The symlink target must be inside an authorized location."
                }
                try FileOps.createSymlink(in: directoryURL, destination: target)
            case .rename(let entry):
                try FileOps.rename(entry, to: trimmed)
            case .move(let entry):
                guard let destination = locations.validatedURL(from: trimmed, relativeTo: directoryURL) else {
                    throw "The destination must be inside an authorized location."
                }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw "The destination is not a folder."
                }
                try FileOps.move(entry, into: destination)
            case .goTo:
                guard let destination = locations.validatedURL(from: trimmed, relativeTo: directoryURL) else {
                    throw "That path is outside the app's authorized locations."
                }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw "That path is not a directory."
                }
                jumpURL = destination
                return
            }

            log.write("Completed operation in \(directoryURL.path)")
            load()
        } catch {
            showError(error)
        }
    }

    private func perform(_ label: String, action: () throws -> Void) {
        do {
            try action()
            log.write(label)
            load()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        stateMessage = error.localizedDescription
        log.write("Error: \(error)")
    }
}

private struct BrowserRow: View {
    let entry: FileEntry
    let hideDates: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundColor(entry.hidden ? .secondary : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .foregroundColor(entry.hidden ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !hideDates, let modified = entry.modified, entry.kind == .file {
                    Text(modified.filosDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if entry.kind == .file {
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if entry.kind == .symlink {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var symbol: String {
        switch entry.kind {
        case .folder: return "folder"
        case .symlink: return "arrow.up.right.circle"
        case .file: return "doc"
        }
    }
}

private struct PromptSheet: View {
    @Environment(\.presentationMode) private var presentationMode

    let request: PromptRequest
    let completion: (String?) -> Void

    @State private var value: String

    init(request: PromptRequest, completion: @escaping (String?) -> Void) {
        self.request = request
        self.completion = completion
        _value = State(initialValue: request.initialText)
    }

    var body: some View {
        NavigationView {
            Form {
                TextField(request.placeholder, text: $value)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        completion(nil)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        completion(value)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct FileInfoView: View {
    @Environment(\.presentationMode) private var presentationMode
    let entry: FileEntry

    var body: some View {
        NavigationView {
            List {
                Section {
                    info("Name", entry.name)
                    info("Path", entry.url.path)
                    if entry.kind == .symlink {
                        info("Destination Path", entry.destinationURL.path)
                    }
                    if entry.kind == .file {
                        info("Size", ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                    }
                }

                Section(header: Label("File", systemImage: "doc")) {
                    info("UTType", entry.contentType.identifier)
                    info("Creation Date", entry.created?.filosDisplay ?? "")
                    info("Last Modified", entry.modified?.filosDisplay ?? "")
                    info("Symlink", entry.kind == .symlink ? "Yes" : "No")
                }

                Section(header: Label("Permissions", systemImage: "shield")) {
                    info("POSIX Permissions", entry.permissions)
                    info("Owner", entry.owner)
                    info("Group", entry.group)
                    info("Readable", entry.readable ? "Yes" : "No")
                    info("Writable", entry.writable ? "Yes" : "No")
                    info("Executable", entry.executable ? "Yes" : "No")
                }
            }
            .navigationTitle("\(entry.kind.rawValue.capitalized) Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .contextMenu {
            Button("Copy Value") {
                UIPasteboard.general.string = value
            }
        }
    }
}

struct TextEditorView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var log: AppLog

    let entry: FileEntry

    @AppStorage("filos.textSize") private var textSize = 11
    @AppStorage("filos.monospaced") private var monospaced = true

    @State private var original = ""
    @State private var text = ""
    @State private var editing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if editing {
                    TextEditor(text: $text)
                        .font(.system(size: CGFloat(textSize), design: monospaced ? .monospaced : .default))
                        .padding(4)
                } else {
                    ScrollView {
                        Text(original)
                            .font(.system(size: CGFloat(textSize), design: monospaced ? .monospaced : .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if editing {
                        Button("Cancel") {
                            text = original
                            editing = false
                        }
                    } else {
                        Menu {
                            Button("Copy") {
                                UIPasteboard.general.string = original
                            }
                            if entry.writable {
                                Button("Edit") {
                                    editing = true
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if editing {
                        Button("Save") {
                            save()
                        }
                    } else {
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { load() }
        .alert(item: Binding(
            get: { errorMessage.map(MessageBox.init) },
            set: { _ in errorMessage = nil }
        )) { message in
            Alert(title: Text("Filos"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }

    private func load() {
        do {
            let loaded = try String(contentsOf: entry.url, encoding: .utf8)
            original = loaded
            text = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try Data(text.utf8).write(to: entry.url, options: .atomic)
            original = text
            editing = false
            log.write("Saved text file: \(entry.url.path)")
        } catch {
            errorMessage = error.localizedDescription
            log.write("Failed to save text file: \(error)")
        }
    }
}

struct PlistEditorView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var log: AppLog

    let entry: FileEntry

    @State private var text = ""
    @State private var original = ""
    @State private var editing = false
    @State private var originalFormat: PropertyListSerialization.PropertyListFormat = .xml
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if editing {
                    TextEditor(text: $text)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(4)
                } else {
                    ScrollView {
                        Text(original)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if editing {
                        Button("Cancel") {
                            text = original
                            editing = false
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if editing {
                        Button("Save") {
                            save()
                        }
                    } else {
                        if entry.writable {
                            Button("Edit") {
                                editing = true
                            }
                        } else {
                            Button("Close") {
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if !editing && entry.writable {
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { load() }
        .alert(item: Binding(
            get: { errorMessage.map(MessageBox.init) },
            set: { _ in errorMessage = nil }
        )) { message in
            Alert(title: Text("Filos"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: entry.url)
            var format = PropertyListSerialization.PropertyListFormat.xml
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            let xml = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            guard let string = String(data: xml, encoding: .utf8) else {
                throw "Unable to represent this property list as text."
            }
            originalFormat = format
            original = string
            text = string
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            guard let input = text.data(using: .utf8) else {
                throw "Unable to encode property-list text."
            }
            var ignored = PropertyListSerialization.PropertyListFormat.xml
            let object = try PropertyListSerialization.propertyList(from: input, options: [], format: &ignored)
            let output = try PropertyListSerialization.data(fromPropertyList: object, format: originalFormat, options: 0)
            try output.write(to: entry.url, options: .atomic)
            editing = false
            load()
            log.write("Saved property list: \(entry.url.path)")
        } catch {
            errorMessage = error.localizedDescription
            log.write("Failed to save property list: \(error)")
        }
    }
}

struct FavoritesView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var favorites: FavoriteStore
    @EnvironmentObject private var locations: LocationStore

    var body: some View {
        NavigationView {
            List {
                ForEach(favorites.paths, id: \.self) { path in
                    let url = URL(fileURLWithPath: path).standardizedFileURL
                    if locations.isAuthorized(url) {
                        NavigationLink(destination: favoriteDestination(url)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                Text(path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                favorites.remove(path: path)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                Text(path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "lock")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func favoriteDestination(_ url: URL) -> some View {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            BrowserView(directoryURL: url)
        } else {
            BrowserView(directoryURL: url.deletingLastPathComponent())
        }
    }
}

struct SettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var locations: LocationStore
    @EnvironmentObject private var log: AppLog

    @AppStorage("filos.hideDates") private var hideDates = false
    @AppStorage("filos.textSize") private var textSize = 11
    @AppStorage("filos.monospaced") private var monospaced = true

    @State private var showLocationPicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                Section(header: Label("Locations", systemImage: "externaldrive")) {
                    ForEach(locations.savedLocations) { item in
                        HStack {
                            Image(systemName: "externaldrive")
                            VStack(alignment: .leading) {
                                Text(item.name)
                                if let url = locations.url(for: item) {
                                    Text(url.path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                locations.removeLocation(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showLocationPicker = true
                    } label: {
                        Label("Add Location…", systemImage: "plus")
                    }
                }

                Section(header: Label("View Options", systemImage: "eye")) {
                    Toggle("Hide Dates", isOn: $hideDates)
                }

                Section(header: Label("Text Viewer", systemImage: "doc.plaintext")) {
                    Stepper(value: $textSize, in: 8...30) {
                        HStack {
                            Text("Text Size")
                            Spacer()
                            Text("\(textSize)")
                                .foregroundColor(.secondary)
                        }
                    }
                    Toggle("Monospaced Font", isOn: $monospaced)
                }

                Section(header: Label("About", systemImage: "info.circle")) {
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("App Store Safe")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Bundle ID")
                        Spacer()
                        Text("com.nightvibes33.filos")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    Text("Uses public iOS APIs and only the app container plus folders explicitly selected by the user.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showLocationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                try locations.addLocation(url)
                log.write("Added location from Settings: \(url.path)")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert(item: Binding(
            get: { errorMessage.map(MessageBox.init) },
            set: { _ in errorMessage = nil }
        )) { message in
            Alert(title: Text("Filos"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }
}

struct LogView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var log: AppLog
    @State private var shareURL: ShareItem?

    var body: some View {
        NavigationView {
            ScrollView {
                Text(log.text.isEmpty ? "No log output yet." : log.text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Copy Output") {
                            UIPasteboard.general.string = log.text
                        }
                        Button("Export Logs") {
                            do {
                                let url = FileManager.default.temporaryDirectory
                                    .appendingPathComponent("Filos-Log-\(Int(Date().timeIntervalSince1970)).txt")
                                try Data(log.text.utf8).write(to: url)
                                shareURL = ShareItem(url: url)
                            } catch {
                                log.write("Failed to export logs: \(error)")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .sheet(item: $shareURL) { item in
            ShareSheet(items: [item.url])
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
