import Foundation
import CoreGraphics

struct NormalizedRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// Top-left origin, normalized to the upright page image.
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct RecognizedWord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var text: String
    var bounds: NormalizedRect
}

struct RecognizedLine: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var text: String
    var bounds: NormalizedRect
    var words: [RecognizedWord]
    var originalText: String? = nil
    var originalWords: [RecognizedWord]? = nil

    func applyingCorrection(_ newText: String) -> RecognizedLine {
        guard newText != text else { return self }
        var result = self
        result.text = newText
        let sourceText = originalText ?? text
        let sourceWords = originalWords ?? words
        if newText == sourceText {
            result.words = sourceWords
            result.originalText = nil
            result.originalWords = nil
        } else {
            result.originalText = sourceText
            result.originalWords = sourceWords
            result.words = []
        }
        return result
    }
}

enum RecognitionState: String, Codable, Sendable {
    case pending, ready, failed
}

struct BookPage: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var imageFilename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var lines: [RecognizedLine] = []
    var recognitionState: RecognitionState = .pending
    var recognitionError: String? = nil

    var text: String { lines.map(\.text).joined(separator: "\n") }
}

struct Book: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var lastOpenedAt: Date = Date()
    var currentPageIndex: Int = 0
    var pages: [BookPage]
    var sourceFilenames: [String] = []
}

struct ImportedPage: Sendable {
    var imageData: Data
    var pixelWidth: Int
    var pixelHeight: Int
}

struct ImportedMaterial: Sendable {
    var title: String
    var pages: [ImportedPage]
    var originalData: Data? = nil
    var originalExtension: String? = nil
}
