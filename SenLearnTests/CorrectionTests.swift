import XCTest
@testable import SenLearn

final class CorrectionTests: XCTestCase {
    func testEditingInvalidatesGeometryAndRepeatedEditsKeepOriginalForUndo() {
        let bounds = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04)
        let original = RecognizedLine(text: "A trec.", bounds: bounds, words: [RecognizedWord(text: "trec", bounds: bounds)])
        let first = original.applyingCorrection("A tree.")
        XCTAssertEqual(first.id, original.id)
        XCTAssertTrue(first.words.isEmpty, "An edited sentence cannot keep unverified word positions.")
        let second = first.applyingCorrection("A big tree.")
        XCTAssertEqual(second.originalText, original.text)
        XCTAssertEqual(second.originalWords, original.words)
        XCTAssertTrue(second.words.isEmpty)
        let restored = second.applyingCorrection(original.text)
        XCTAssertEqual(restored, original)
    }
}
