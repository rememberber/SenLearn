import Foundation
import NaturalLanguage
import KokoroRuntime

struct SynthesizedSpeech: Sendable {
    let audio: KokoroAudio
    let elapsed: Double
    let cached: Bool
}

actor KokoroEngine {
    static let requiredFiles = ["model.int8.onnx", "voices.bin", "tokens.txt", "lexicon-us-en.txt", "lexicon-zh.txt",
                                "date-zh.fst", "number-zh.fst", "phone-zh.fst", "dict/jieba.dict.utf8", "espeak-ng-data/phontab"]
    private let directory: URL?
    private var session: KokoroSession?
    private var cache: [(key: String, audio: KokoroAudio)] = []
    private let maximumCacheBytes = 12 * 1_024 * 1_024

    init(directory: URL? = Bundle.main.url(forResource: "Kokoro", withExtension: nil)) { self.directory = directory }

    nonisolated static var isBundled: Bool {
        guard let directory = Bundle.main.url(forResource: "Kokoro", withExtension: nil) else { return false }
        return requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    func synthesize(text: String, speed: Double) async throws -> SynthesizedSpeech {
        let cancellation = KokoroCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 120,
                  !text.contains("\0"), speed.isFinite, (0.5...1.2).contains(speed) else { throw KokoroError.invalidRequest }
            let started = Date()
            guard let directory, Self.requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) else {
                throw EngineError.missingModel
            }
            let speaker = Self.containsChinese(text) ? 3 : 0 // zf_001 / af_maple, pinned v1.1 voice map.
            let key = "\(speaker)|\(speed)|\(text)"
            if let index = cache.firstIndex(where: { $0.key == key }) {
                let hit = cache.remove(at: index); cache.append(hit)
                return SynthesizedSpeech(audio: hit.audio, elapsed: Date().timeIntervalSince(started), cached: true)
            }
            if session == nil { session = try KokoroSession(directory: directory) }
            try Task.checkCancellation()
            let audio = try session!.generate(text: text, speaker: speaker, speed: Float(speed), cancellation: cancellation)
            try Task.checkCancellation()
            let cost = audio.samples.count * MemoryLayout<Float>.size
            if cost <= maximumCacheBytes {
                cache.append((key, audio))
                while cache.reduce(0, { $0 + $1.audio.samples.count * MemoryLayout<Float>.size }) > maximumCacheBytes { cache.removeFirst() }
            }
            return SynthesizedSpeech(audio: audio, elapsed: Date().timeIntervalSince(started), cached: false)
        } onCancel: { cancellation.cancel() }
    }

    func releaseResources() { cache.removeAll(); session = nil }

    nonisolated static func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) || (0x20000...0x323AF).contains($0.value) }
    }

    /// Limit each native inference call, preserving all text and sentence/word boundaries.
    nonisolated static func chunks(for text: String, maximum: Int = 60) -> [String] {
        precondition(maximum > 0)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            var remaining = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            // Chinese characters yield more phonemes per character than English.
            let chunkLimit = Self.containsChinese(remaining) ? min(maximum, 20) : maximum
            while remaining.count > chunkLimit {
                let limit = remaining.index(remaining.startIndex, offsetBy: chunkLimit)
                let prefix = remaining[..<limit]
                let split = prefix.lastIndex(where: { $0.isWhitespace }) ?? limit
                let boundary = split == remaining.startIndex ? limit : split
                result.append(String(remaining[..<boundary]))
                remaining = String(remaining[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !remaining.isEmpty { result.append(remaining) }
            return true
        }
        return result
    }

    enum EngineError: LocalizedError {
        case missingModel
        var errorDescription: String? { "离线声音文件不完整，请重新安装包含 Kokoro 模型的版本。" }
    }
}

extension KokoroAudio {
    /// Mono 16-bit WAV consumed by AVAudioPlayer; no files or networking at playback time.
    var wavData: Data {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            var value = Int16((min(1, max(-1, sample)) * Float(Int16.max)).rounded()).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var result = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { result.append(contentsOf: $0) } }
        append(UInt32(36 + pcm.count)); result.append(Data("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16)); result.append(Data("data".utf8)); append(UInt32(pcm.count)); result.append(pcm)
        return result
    }
}
