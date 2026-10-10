import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import SenLearn

final class TextRecognizerTests: XCTestCase {
    func testVisionCoordinatesConvertToTopLeftAndStayWithinPage() {
        let rect = TextRecognizer.topLeftRect(from: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.2))
        XCTAssertEqual(rect.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(rect.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.2, accuracy: 0.0001)
        let clipped = TextRecognizer.topLeftRect(from: CGRect(x: -0.1, y: 0.8, width: 0.4, height: 0.3))
        XCTAssertEqual(clipped.x, 0, accuracy: 0.0001)
        XCTAssertEqual(clipped.y, 0, accuracy: 0.0001)
        XCTAssertEqual(clipped.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(clipped.height, 0.2, accuracy: 0.0001)
    }

    func testSentenceContinuesAcrossEnglishLineBreaks() {
        let first = line("The little fox", words: ["The", "little", "fox"])
        let second = line("runs through the forest. It is happy.", words: ["runs", "through", "the", "forest", "It", "is", "happy"])
        XCTAssertEqual(TextRecognizer.sentence(containing: first.words[2].id, in: [first, second]), "The little fox runs through the forest.")
        XCTAssertEqual(TextRecognizer.sentence(containing: second.words[5].id, in: [first, second]), "It is happy.")
    }

    func testSentenceSelectsTheCorrectRepeatedWord() {
        let text = line("Here is a fox. Here is a bird.", words: ["Here", "is", "a", "fox", "Here", "is", "a", "bird"])
        XCTAssertEqual(TextRecognizer.sentence(containing: text.words[4].id, in: [text]), "Here is a bird.")
    }

    func testDistantHeadingIsNotReadAsPartOfTappedSentence() {
        var title = line("Forest Friends", words: ["Forest", "Friends"])
        title.bounds = NormalizedRect(x: 0.1, y: 0.03, width: 0.4, height: 0.03)
        var body = line("A squirrel lives here.", words: ["A", "squirrel", "lives", "here"])
        body.bounds = NormalizedRect(x: 0.1, y: 0.75, width: 0.8, height: 0.05)
        XCTAssertEqual(TextRecognizer.sentence(containing: body.words[1].id, in: [title, body]), "A squirrel lives here.")
    }

    func testVisionRecognizesChineseWithBoundedTapTargets() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 500), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 500))
            ("小松鼠住在森林里。" as NSString).draw(at: CGPoint(x: 100, y: 140), withAttributes: [
                .font: UIFont.systemFont(ofSize: 88), .foregroundColor: UIColor.black
            ])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(image.pngData()).write(to: url)
        let lines = try await TextRecognizer().recognize(imageURL: url)
        XCTAssertTrue(lines.map(\.text).joined().contains("森林"))
        let words = lines.flatMap(\.words)
        XCTAssertFalse(words.isEmpty)
        XCTAssertTrue(words.allSatisfy { $0.bounds.width > 0 && $0.bounds.y >= 0 && $0.bounds.y + $0.bounds.height <= 1 })
    }

    func testChineseSentenceContinuesWithoutAnInsertedSpace() {
        let first = line("小狐狸住在", words: ["小", "狐狸", "住", "在"])
        let second = line("森林里。它很快乐。", words: ["森林", "里", "它", "很", "快乐"])
        XCTAssertEqual(TextRecognizer.sentence(containing: second.words[0].id, in: [first, second]), "小狐狸住在森林里。")
        XCTAssertEqual(TextRecognizer.sentence(containing: second.words[4].id, in: [first, second]), "它很快乐。")
    }

    func testReadingOrderUsesRowsThenHorizontalPosition() {
        var left = line("left", words: ["left"])
        left.bounds = NormalizedRect(x: 0.1, y: 0.11, width: 0.2, height: 0.1)
        var right = line("right", words: ["right"])
        right.bounds = NormalizedRect(x: 0.6, y: 0.10, width: 0.2, height: 0.1)
        var below = line("below", words: ["below"])
        below.bounds = NormalizedRect(x: 0.1, y: 0.3, width: 0.2, height: 0.1)
        XCTAssertEqual(TextRecognizer.readingOrder([below, right, left]).map(\.text), ["left", "right", "below"])
    }

    func testVisionRecognizesRenderedTextWithRealWordBounds() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 900), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_600, height: 900))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 86, weight: .regular), .foregroundColor: UIColor.black]
            ("The little fox." as NSString).draw(at: CGPoint(x: 150, y: 140), withAttributes: attributes)
            ("The happy bird." as NSString).draw(at: CGPoint(x: 150, y: 400), withAttributes: attributes)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(image.jpegData(compressionQuality: 1)).write(to: url)
        let lines = try await TextRecognizer().recognize(imageURL: url)
        XCTAssertEqual(lines.count, 2)
        let fox = try XCTUnwrap(lines.flatMap(\.words).first { $0.text.lowercased() == "fox" })
        XCTAssertEqual(TextRecognizer.sentence(containing: fox.id, in: lines), "The little fox.")
        XCTAssertLessThan(fox.bounds.y, 0.35, "Vision's bottom-left coordinates must be flipped for the page view.")
        XCTAssertGreaterThan(fox.bounds.width, 0)
        XCTAssertLessThan(fox.bounds.width, 0.2, "A single word must not use the entire line's rectangle.")
        XCTAssertLessThan(lines[0].bounds.y, lines[1].bounds.y)
    }

    private func line(_ text: String, words: [String]) -> RecognizedLine {
        let bounds = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.1)
        return RecognizedLine(text: text, bounds: bounds, words: words.map { RecognizedWord(text: $0, bounds: bounds) })
    }
}

final class MaterialImporterTests: XCTestCase {
    func testImageOrientationIsNormalizedAndLongEdgeIsBounded() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3_000, height: 1_000), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3_000, height: 1_000))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let material = try await MaterialImporter().importPhotos([data as Data], title: "Rotated photo")
        let page = try XCTUnwrap(material.pages.first)
        XCTAssertEqual(page.pixelHeight, 2_000)
        XCTAssertLessThan(page.pixelWidth, page.pixelHeight)
        let result = try XCTUnwrap(UIImage(data: page.imageData))
        XCTAssertEqual(result.imageOrientation, .up)
        XCTAssertNil(material.originalData)
    }

    func testPDFImportsAllPagesAndPreservesOriginalBytes() async throws {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
        let source = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for text in ["Page one", "Page two"] {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try source.write(to: url)
        let material = try await MaterialImporter().importFile(at: url)
        XCTAssertEqual(material.pages.count, 2)
        XCTAssertEqual(material.originalData, source)
        XCTAssertEqual(material.originalExtension, "pdf")
        XCTAssertEqual(material.pages[0].pixelWidth, 1_500)
        XCTAssertEqual(material.pages[0].pixelHeight, 2_000)
        let pageURL = url.deletingPathExtension().appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: pageURL) }
        try material.pages[0].imageData.write(to: pageURL)
        let lines = try await TextRecognizer().recognize(imageURL: pageURL)
        XCTAssertTrue(lines.map(\.text).joined(separator: " ").contains("Page one"), "PDF rendering must preserve upright text.")
        let firstLine = try XCTUnwrap(lines.first)
        XCTAssertLessThan(firstLine.bounds.x, 0.2, "Small PDFs must fill the raster instead of being centered at 1:1 points.")
        XCTAssertLessThan(firstLine.bounds.y, 0.2)
        XCTAssertGreaterThan(firstLine.bounds.width, 0.25)
    }

    func testPhotoLimitsFailBeforeDecoding() async throws {
        let importer = MaterialImporter()
        do {
            _ = try await importer.importPhotos([], title: "Empty")
            XCTFail("Empty imports should fail.")
        } catch MaterialImporter.ImportError.noPhotos {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            _ = try await importer.importPhotos(Array(repeating: Data(), count: 31), title: "Too many")
            XCTFail("More than 30 photos should fail.")
        } catch MaterialImporter.ImportError.tooManyPhotos {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCorruptImageReturnsAnActionableError() async throws {
        do {
            _ = try await MaterialImporter().importPhotos([Data("invalid image".utf8)], title: "Invalid")
            XCTFail("Corrupt images should fail.")
        } catch MaterialImporter.ImportError.invalidImage(let number) {
            XCTAssertEqual(number, 1)
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}
