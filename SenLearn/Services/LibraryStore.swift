import Combine
import Foundation
import SQLite3

/// Keeps page images and original imports on disk, with book metadata in SQLite.
/// Published state changes only after the corresponding database transaction commits.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var errorMessage: String?
    private(set) var isAvailable = false

    private let rootDirectory: URL
    private let imagesDirectory: URL
    private let sourcesDirectory: URL
    // SQLite access is confined to the main actor; deinit only closes the handle.
    nonisolated(unsafe) private var database: OpaquePointer?

    init(rootDirectory: URL? = nil) {
        let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SenLearn", isDirectory: true)
        let root = rootDirectory ?? defaultRoot
        self.rootDirectory = root
        imagesDirectory = root.appendingPathComponent("Images", isDirectory: true)
        sourcesDirectory = root.appendingPathComponent("Sources", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try openDatabase()
            let loadedBooks = try loadBooks()
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
            books = sorted(loadedBooks)
            isAvailable = true
        } catch {
            // Never replace an unreadable database with an empty library.
            if let database { sqlite3_close(database) }
            database = nil
            errorMessage = "书架读取失败，原有资料已保留。\(error.localizedDescription)"
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func book(id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    func imageURL(for page: BookPage) -> URL {
        // Also constrain arbitrary caller-provided pages to the images directory.
        imagesDirectory.appendingPathComponent((page.imageFilename as NSString).lastPathComponent)
    }

    @discardableResult
    func importMaterial(_ material: ImportedMaterial, appendingTo bookID: UUID? = nil) throws -> UUID {
        try recordingErrors {
            try requireAvailable()
            guard !material.pages.isEmpty else { throw StoreError.noPages }
            guard material.pages.allSatisfy({ !$0.imageData.isEmpty && $0.pixelWidth > 0 && $0.pixelHeight > 0 }) else {
                throw StoreError.invalidImage
            }

            var importedBook: Book
            if let bookID {
                guard let existing = book(id: bookID) else { throw StoreError.bookNotFound }
                importedBook = existing
            } else {
                importedBook = Book(title: try validatedTitle(material.title), pages: [])
            }

            var writtenFiles: [URL] = []
            do {
                for page in material.pages {
                    let filename = "\(UUID().uuidString).\(imageExtension(for: page.imageData))"
                    let imageURL = imagesDirectory.appendingPathComponent(filename)
                    // Record before writing so partially created files are rolled back too.
                    writtenFiles.append(imageURL)
                    try page.imageData.write(to: imageURL, options: .atomic)
                    importedBook.pages.append(BookPage(
                        imageFilename: filename,
                        pixelWidth: page.pixelWidth,
                        pixelHeight: page.pixelHeight
                    ))
                }
                if let data = material.originalData {
                    let filename = "\(UUID().uuidString).\(sourceExtension(material.originalExtension))"
                    let sourceURL = sourcesDirectory.appendingPathComponent(filename)
                    writtenFiles.append(sourceURL)
                    try data.write(to: sourceURL, options: .atomic)
                    importedBook.sourceFilenames.append(filename)
                }
                try saveBook(importedBook)
            } catch {
                for url in writtenFiles { try? FileManager.default.removeItem(at: url) }
                throw error
            }

            publish(importedBook)
            return importedBook.id
        }
    }

    func updatePage(_ page: BookPage, in bookID: UUID) throws {
        try recordingErrors {
            try requireAvailable()
            guard var updatedBook = book(id: bookID) else { throw StoreError.bookNotFound }
            guard let index = updatedBook.pages.firstIndex(where: { $0.id == page.id }) else {
                throw StoreError.pageNotFound
            }
            let existingPage = updatedBook.pages[index]
            guard page.imageFilename == existingPage.imageFilename,
                  page.pixelWidth == existingPage.pixelWidth,
                  page.pixelHeight == existingPage.pixelHeight else {
                throw StoreError.invalidImage
            }
            try validate(page)
            updatedBook.pages[index] = page
            try saveBook(updatedBook)
            publish(updatedBook)
        }
    }

    func setReadingPosition(bookID: UUID, index: Int) throws {
        try recordingErrors {
            try requireAvailable()
            guard var updatedBook = book(id: bookID) else { throw StoreError.bookNotFound }
            guard updatedBook.pages.indices.contains(index) else { throw StoreError.invalidPageIndex }
            updatedBook.currentPageIndex = index
            updatedBook.lastOpenedAt = Date()
            try saveBook(updatedBook)
            publish(updatedBook)
        }
    }

    func renameBook(id: UUID, title: String) throws {
        try recordingErrors {
            try requireAvailable()
            guard var updatedBook = book(id: id) else { throw StoreError.bookNotFound }
            updatedBook.title = try validatedTitle(title)
            try saveBook(updatedBook)
            publish(updatedBook)
        }
    }

    func deleteBook(id: UUID) throws {
        try recordingErrors {
            try requireAvailable()
            guard let removedBook = book(id: id) else { throw StoreError.bookNotFound }
            try transaction {
                let statement = try prepare("DELETE FROM books WHERE id = ?;")
                defer { sqlite3_finalize(statement) }
                try bind(id.uuidString, to: statement, at: 1)
                try step(statement)
            }
            books.removeAll { $0.id == id }
            // Files remain intact if SQL fails. Unreferenced files are harmless if cleanup fails.
            for page in removedBook.pages { try? FileManager.default.removeItem(at: imageURL(for: page)) }
            for filename in removedBook.sourceFilenames {
                try? FileManager.default.removeItem(at: sourcesDirectory.appendingPathComponent(filename))
            }
        }
    }

    private func openDatabase() throws {
        let url = rootDirectory.appendingPathComponent("library.sqlite")
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else { throw databaseError() }
        sqlite3_busy_timeout(database, 3_000)
        try execute("CREATE TABLE IF NOT EXISTS books (id TEXT PRIMARY KEY NOT NULL, json BLOB NOT NULL);")
    }

    private func loadBooks() throws -> [Book] {
        let statement = try prepare("SELECT id, json FROM books;")
        defer { sqlite3_finalize(statement) }
        var loaded: [Book] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let idText = sqlite3_column_text(statement, 0),
                      let blob = sqlite3_column_blob(statement, 1) else { throw StoreError.invalidStoredData }
                let id = String(cString: idText)
                let length = Int(sqlite3_column_bytes(statement, 1))
                guard length > 0 else { throw StoreError.invalidStoredData }
                let data = Data(bytes: blob, count: length)
                let book = try JSONDecoder().decode(Book.self, from: data)
                guard book.id.uuidString == id else { throw StoreError.invalidStoredData }
                try validate(book)
                loaded.append(book)
            case SQLITE_DONE:
                return loaded
            default:
                throw databaseError()
            }
        }
    }

    private func saveBook(_ book: Book) throws {
        try validate(book)
        let data = try JSONEncoder().encode(book)
        guard data.count <= Int(Int32.max) else { throw StoreError.invalidStoredData }
        try transaction {
            let statement = try prepare("INSERT INTO books (id, json) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json;")
            defer { sqlite3_finalize(statement) }
            try bind(book.id.uuidString, to: statement, at: 1)
            let result = data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard result == SQLITE_OK else { throw databaseError() }
            try step(statement)
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError()
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw databaseError() }
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func databaseError() -> StoreError {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开本地数据库"
        return .database(detail)
    }

    private func requireAvailable() throws {
        guard isAvailable, database != nil else { throw StoreError.unavailable }
    }

    private func recordingErrors<T>(_ action: () throws -> T) throws -> T {
        do {
            let value = try action()
            errorMessage = nil
            return value
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func publish(_ book: Book) {
        var updated = books.filter { $0.id != book.id }
        updated.append(book)
        books = sorted(updated)
    }

    private func sorted(_ books: [Book]) -> [Book] {
        books.sorted {
            if $0.lastOpenedAt != $1.lastOpenedAt { return $0.lastOpenedAt > $1.lastOpenedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func validatedTitle(_ title: String) throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw StoreError.emptyTitle }
        return title
    }

    private func validate(_ book: Book) throws {
        _ = try validatedTitle(book.title)
        guard !book.pages.isEmpty,
              book.pages.indices.contains(book.currentPageIndex),
              Set(book.pages.map(\.id)).count == book.pages.count,
              Set(book.pages.map(\.imageFilename)).count == book.pages.count,
              book.sourceFilenames.allSatisfy(isGeneratedFilename) else {
            throw StoreError.invalidStoredData
        }
        for page in book.pages { try validate(page) }
    }

    private func validate(_ page: BookPage) throws {
        guard page.pixelWidth > 0, page.pixelHeight > 0, isGeneratedFilename(page.imageFilename) else {
            throw StoreError.invalidImage
        }
        for line in page.lines {
            guard validBounds(line.bounds),
                  line.words.allSatisfy({ validBounds($0.bounds) }),
                  line.originalWords?.allSatisfy({ validBounds($0.bounds) }) ?? true else {
                throw StoreError.invalidBounds
            }
        }
    }

    private func validBounds(_ bounds: NormalizedRect) -> Bool {
        [bounds.x, bounds.y, bounds.width, bounds.height].allSatisfy(\.isFinite)
            && bounds.x >= 0 && bounds.y >= 0 && bounds.width > 0 && bounds.height > 0
            && bounds.x + bounds.width <= 1.000_001 && bounds.y + bounds.height <= 1.000_001
    }

    private func isGeneratedFilename(_ filename: String) -> Bool {
        guard filename == (filename as NSString).lastPathComponent else { return false }
        let components = filename.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 2 && UUID(uuidString: String(components[0])) != nil
            && !components[1].isEmpty && components[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private func imageExtension(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) { return "png" }
        if data.starts(with: [0xff, 0xd8, 0xff]) { return "jpg" }
        return "img"
    }

    private func sourceExtension(_ value: String?) -> String {
        let ext = (value ?? "bin").trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !ext.isEmpty, ext.count <= 12, ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return "bin"
        }
        return ext
    }

    private enum StoreError: LocalizedError {
        case unavailable, noPages, invalidImage, bookNotFound, pageNotFound, invalidPageIndex
        case emptyTitle, invalidBounds, invalidStoredData
        case database(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "书架暂时无法使用，请保留资料并重新打开应用。"
            case .noPages: "没有可导入的页面。"
            case .invalidImage: "页面图片或尺寸无效。"
            case .bookNotFound: "没有找到这本书。"
            case .pageNotFound: "没有找到这个页面。"
            case .invalidPageIndex: "阅读页码超出了书本范围。"
            case .emptyTitle: "书名不能为空。"
            case .invalidBounds: "识别区域超出了页面范围。"
            case .invalidStoredData: "书架数据格式无效。"
            case .database(let detail): "资料保存失败：\(detail)"
            }
        }
    }
}
