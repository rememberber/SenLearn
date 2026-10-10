import Foundation
import NaturalLanguage
import Vision

actor TextRecognizer {
    enum RecognitionError: LocalizedError {
        case unreadableImage
        case unsupportedLanguages

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "页面图片无法读取，请重新导入。"
            case .unsupportedLanguages: return "当前设备无法使用中英文识别，请更新系统后重试。"
            }
        }
    }

    func recognize(imageURL: URL) throws -> [RecognizedLine] {
        try Task.checkCancellation()
        guard FileManager.default.isReadableFile(atPath: imageURL.path) else { throw RecognitionError.unreadableImage }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.revision = VNRecognizeTextRequestRevision3
        let supported = try request.supportedRecognitionLanguages()
        let languages = ["en-US", "zh-Hans"].filter { supported.contains($0) }
        guard languages.count == 2 else { throw RecognitionError.unsupportedLanguages }
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: imageURL, orientation: .up)
        try handler.perform([request])
        try Task.checkCancellation()
        let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = candidate.string
            var words: [RecognizedWord] = []
            tokenizer.enumerateTokens(in: candidate.string.startIndex..<candidate.string.endIndex) { range, _ in
                // Never infer word geometry from character counts: Chinese and proportional text
                // need the actual Vision range bounds for reliable tap targets.
                if let box = try? candidate.boundingBox(for: range), box.boundingBox.width > 0, box.boundingBox.height > 0 {
                    words.append(RecognizedWord(text: String(candidate.string[range]), bounds: Self.topLeftRect(from: box.boundingBox)))
                }
                return true
            }
            return RecognizedLine(text: candidate.string, bounds: Self.topLeftRect(from: observation.boundingBox), words: words)
        }
        return Self.readingOrder(lines)
    }

    nonisolated static func topLeftRect(from visionRect: CGRect) -> NormalizedRect {
        let clipped = visionRect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull else { return NormalizedRect(x: 0, y: 0, width: 0, height: 0) }
        return NormalizedRect(x: clipped.minX, y: 1 - clipped.maxY, width: clipped.width, height: clipped.height)
    }

    /// Horizontal reading order: top to bottom; observations sharing a row go left to right.
    nonisolated static func readingOrder(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        let sorted = lines.enumerated().sorted { lhs, rhs in
            if lhs.element.bounds.y != rhs.element.bounds.y { return lhs.element.bounds.y < rhs.element.bounds.y }
            if lhs.element.bounds.x != rhs.element.bounds.x { return lhs.element.bounds.x < rhs.element.bounds.x }
            return lhs.offset < rhs.offset
        }
        var rows: [[(offset: Int, element: RecognizedLine)]] = []
        for item in sorted {
            if let rowIndex = rows.lastIndex(where: { row in
                guard let anchor = row.first?.element else { return false }
                let a = anchor.bounds.cgRect
                let b = item.element.bounds.cgRect
                return abs(a.midY - b.midY) <= min(a.height, b.height) * 0.5
            }) {
                rows[rowIndex].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.flatMap { row in
            row.sorted {
                if $0.element.bounds.x != $1.element.bounds.x { return $0.element.bounds.x < $1.element.bounds.x }
                return $0.offset < $1.offset
            }.map(\.element)
        }
    }

    /// Looks up the occurrence by word ID so repeated words select the right sentence.
    nonisolated static func sentence(containing wordID: UUID, in lines: [RecognizedLine]) -> String {
        guard let targetLine = lines.firstIndex(where: { $0.words.contains { $0.id == wordID } }) else { return "" }
        // A distant heading or caption is not part of the tapped paragraph.
        func separated(_ before: RecognizedLine, _ after: RecognizedLine) -> Bool {
            let gap = after.bounds.y - before.bounds.y - before.bounds.height
            return gap > max(0.035, max(before.bounds.height, after.bounds.height) * 1.5)
        }
        var start = targetLine
        var end = targetLine
        while start > 0 && !separated(lines[start - 1], lines[start]) { start -= 1 }
        while end + 1 < lines.count && !separated(lines[end], lines[end + 1]) { end += 1 }
        var documentText = ""
        var targetOffset: Int?
        var fallback = ""
        for line in lines[start...end] {
            if !documentText.isEmpty {
                let joinsChinese = documentText.last.map(isHanCharacter) == true && line.text.first.map(isHanCharacter) == true
                if !joinsChinese { documentText += " " }
            }
            let lineOffset = documentText.utf16.count
            var searchStart = line.text.startIndex
            for word in line.words {
                guard let range = line.text.range(of: word.text, range: searchStart..<line.text.endIndex) else {
                    if word.id == wordID { fallback = line.text }
                    continue
                }
                if word.id == wordID {
                    targetOffset = lineOffset + range.lowerBound.utf16Offset(in: line.text)
                    fallback = line.text
                }
                searchStart = range.upperBound
            }
            documentText += line.text
        }
        guard let targetOffset, targetOffset < documentText.utf16.count else { return fallback }
        let targetIndex = String.Index(utf16Offset: targetOffset, in: documentText)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = documentText
        var result = fallback
        tokenizer.enumerateTokens(in: documentText.startIndex..<documentText.endIndex) { range, _ in
            guard range.contains(targetIndex) else { return true }
            result = String(documentText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return false
        }
        return result
    }

    private nonisolated static func isHanCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) || (0x20000...0x323AF).contains(scalar.value)
        }
    }
}
