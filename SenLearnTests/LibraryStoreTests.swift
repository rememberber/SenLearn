import Foundation
import SQLite3
import XCTest
@testable import SenLearn

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testImportPersistsImagesOriginalAndReadingPositionAcrossReopen() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootDirectory: root)
        XCTAssertTrue(store.isAvailable)
        let original = Data("original PDF bytes".utf8)
        var material = sampleMaterial(pageCount: 2)
        material.title = "  我的英语书\n"
        material.originalData = original
        material.originalExtension = "PDF"
        let id = try store.importMaterial(material)
        try store.setReadingPosition(bookID: id, index: 1)
        let saved = try XCTUnwrap(store.book(id: id))

        XCTAssertEqual(saved.title, "我的英语书")
        XCTAssertEqual(saved.currentPageIndex, 1)
        XCTAssertEqual(saved.pages.count, 2)
        for (index, page) in saved.pages.enumerated() {
            XCTAssertEqual(try Data(contentsOf: store.imageURL(for: page)), material.pages[index].imageData)
            XCTAssertNotNil(UUID(uuidString: (page.imageFilename as NSString).deletingPathExtension))
        }
        let source = try XCTUnwrap(saved.sourceFilenames.first)
        XCTAssertEqual((source as NSString).pathExtension, "pdf")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Sources/\(source)")), original)

        let reopened = LibraryStore(rootDirectory: root)
        XCTAssertTrue(reopened.isAvailable)
        XCTAssertEqual(reopened.book(id: id), saved)
    }

    func testAppendPreservesPageOrderAndReadingPosition() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootDirectory: root)
        let id = try store.importMaterial(sampleMaterial(pageCount: 2))
        try store.setReadingPosition(bookID: id, index: 1)
        let original = try XCTUnwrap(store.book(id: id))
        let appendedID = try store.importMaterial(sampleMaterial(pageCount: 2, title: "新拍的页面"), appendingTo: id)
        let appended = try XCTUnwrap(store.book(id: id))

        XCTAssertEqual(appendedID, id)
        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(appended.title, original.title)
        XCTAssertEqual(appended.currentPageIndex, 1)
        XCTAssertEqual(appended.lastOpenedAt, original.lastOpenedAt)
        XCTAssertEqual(Array(appended.pages.prefix(2)), original.pages)
        XCTAssertEqual(appended.pages.count, 4)
        XCTAssertEqual(Set(appended.pages.map(\.imageFilename)).count, 4)
        XCTAssertEqual(LibraryStore(rootDirectory: root).book(id: id), appended)
    }

    func testCorrectionsAndOriginalRecognitionPersist() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootDirectory: root)
        let id = try store.importMaterial(sampleMaterial())
        var page = try XCTUnwrap(store.book(id: id)?.pages.first)
        let bounds = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
        let originalWord = RecognizedWord(text: "Hcllo", bounds: bounds)
        let correctedWord = RecognizedWord(id: originalWord.id, text: "Hello", bounds: bounds)
        page.lines = [RecognizedLine(
            text: "Hello", bounds: bounds, words: [correctedWord],
            originalText: "Hcllo", originalWords: [originalWord]
        )]
        page.recognitionState = .ready
        try store.updatePage(page, in: id)
        try store.renameBook(id: id, title: "  纠错练习  ")

        let reopened = LibraryStore(rootDirectory: root)
        XCTAssertEqual(reopened.book(id: id)?.pages.first, page)
        XCTAssertEqual(reopened.book(id: id)?.title, "纠错练习")
    }

    func testDeleteRemovesOnlyTheSelectedBookAndItsFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootDirectory: root)
        var material = sampleMaterial(pageCount: 2)
        material.originalData = Data("source".utf8)
        material.originalExtension = "pdf"
        let removedID = try store.importMaterial(material)
        let retainedID = try store.importMaterial(sampleMaterial(title: "保留"))
        let removed = try XCTUnwrap(store.book(id: removedID))
        let retained = try XCTUnwrap(store.book(id: retainedID))

        try store.deleteBook(id: removedID)

        XCTAssertNil(store.book(id: removedID))
        XCTAssertEqual(store.book(id: retainedID), retained)
        for page in removed.pages {
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: page).path))
        }
        for source in removed.sourceFilenames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/\(source)").path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(for: retained.pages[0]).path))
        let reopened = LibraryStore(rootDirectory: root)
        XCTAssertEqual(reopened.books, [retained])
    }

    func testInvalidInputCannotMutateExistingBook() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootDirectory: root)
        let id = try store.importMaterial(sampleMaterial())
        let saved = try XCTUnwrap(store.book(id: id))

        XCTAssertThrowsError(try store.renameBook(id: id, title: " \n "))
        XCTAssertThrowsError(try store.setReadingPosition(bookID: id, index: -1))
        XCTAssertThrowsError(try store.setReadingPosition(bookID: id, index: 1))
        XCTAssertThrowsError(try store.importMaterial(ImportedMaterial(title: "空白", pages: [])))
        XCTAssertThrowsError(try store.importMaterial(sampleMaterial(title: "  ")))
        var invalidMaterial = sampleMaterial()
        invalidMaterial.pages[0].pixelWidth = 0
        XCTAssertThrowsError(try store.importMaterial(invalidMaterial, appendingTo: id))

        var page = saved.pages[0]
        page.lines = [RecognizedLine(
            text: "outside", bounds: NormalizedRect(x: 0.9, y: 0, width: 0.2, height: 0.1), words: []
        )]
        XCTAssertThrowsError(try store.updatePage(page, in: id))
        page = saved.pages[0]
        page.imageFilename = "../library.sqlite"
        XCTAssertThrowsError(try store.updatePage(page, in: id))
        XCTAssertEqual(store.book(id: id), saved)
        XCTAssertEqual(store.books.count, 1)
    }

    func testFailedInsertRollsBackCreatedImagesAndOriginal() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootDirectory: root)
        try executeSQL("CREATE TRIGGER reject_insert BEFORE INSERT ON books BEGIN SELECT RAISE(ABORT, 'test write failure'); END;", root: root)
        var material = sampleMaterial(pageCount: 2)
        material.originalData = Data("original".utf8)
        material.originalExtension = "pdf"

        XCTAssertThrowsError(try store.importMaterial(material))

        XCTAssertTrue(store.books.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Images").path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sources").path).isEmpty)
        XCTAssertTrue(LibraryStore(rootDirectory: root).books.isEmpty)
    }

    func testFailedAppendAndDeletePreservePreviouslySavedBookAndFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootDirectory: root)
        let material = sampleMaterial()
        let id = try store.importMaterial(material)
        let original = try XCTUnwrap(store.book(id: id))
        try executeSQL("CREATE TRIGGER reject_update BEFORE UPDATE ON books BEGIN SELECT RAISE(ABORT, 'test update failure'); END;", root: root)

        XCTAssertThrowsError(try store.importMaterial(sampleMaterial(pageCount: 2), appendingTo: id))
        XCTAssertEqual(store.book(id: id), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Images").path).count, 1)

        try executeSQL("CREATE TRIGGER reject_delete BEFORE DELETE ON books BEGIN SELECT RAISE(ABORT, 'test delete failure'); END;", root: root)
        XCTAssertThrowsError(try store.deleteBook(id: id))
        XCTAssertEqual(store.book(id: id), original)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: original.pages[0])), material.pages[0].imageData)
        XCTAssertEqual(LibraryStore(rootDirectory: root).book(id: id), original)
    }

    func testUnreadableMetadataDisablesWritesAndPreservesDatabase() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootDirectory: root)
        let id = try store.importMaterial(sampleMaterial())
        let imageURL = store.imageURL(for: try XCTUnwrap(store.book(id: id)?.pages.first))
        try executeSQL("UPDATE books SET json = x'7B';", root: root)
        let databaseURL = root.appendingPathComponent("library.sqlite")
        let damagedBytes = try Data(contentsOf: databaseURL)

        let reopened = LibraryStore(rootDirectory: root)

        XCTAssertFalse(reopened.isAvailable)
        XCTAssertNotNil(reopened.errorMessage)
        XCTAssertThrowsError(try reopened.importMaterial(sampleMaterial()))
        XCTAssertEqual(try Data(contentsOf: databaseURL), damagedBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    }

    func testUnwritableLibraryLocationIsReportedWithoutClaimingAnEmptyUsableLibrary() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("a file, not a directory".utf8).write(to: root)
        let store = LibraryStore(rootDirectory: root)
        XCTAssertFalse(store.isAvailable)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertThrowsError(try store.importMaterial(sampleMaterial()))
        XCTAssertEqual(try Data(contentsOf: root), Data("a file, not a directory".utf8))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SenLearnTests-\(UUID().uuidString)", isDirectory: false)
    }

    private func sampleMaterial(pageCount: Int = 1, title: String = "练习书") -> ImportedMaterial {
        ImportedMaterial(title: title, pages: (0..<pageCount).map {
            ImportedPage(imageData: Data("encoded image \($0)".utf8), pixelWidth: 100, pixelHeight: 200)
        })
    }

    private func executeSQL(_ sql: String, root: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("library.sqlite").path, &database) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw TestError.database
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw TestError.database }
    }

    private enum TestError: Error { case database }
}
