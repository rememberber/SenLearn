import Foundation
import SherpaOnnxC

/// May be set from the UI while the serial inference executor is inside the C API.
public final class KokoroCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

public struct KokoroAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    public var duration: Double { Double(samples.count) / Double(sampleRate) }
}

public enum KokoroError: Error, LocalizedError {
    case initializationFailed, noAudio, invalidRequest
    public var errorDescription: String? {
        switch self {
        case .initializationFailed: return "离线声音初始化失败，请检查模型文件。"
        case .noAudio: return "没有生成可播放的声音，请检查文字后重试。"
        case .invalidRequest: return "朗读文字、声音或语速无效。"
        }
    }
}

/// Confine this session to a single actor. Paths remain alive throughout C initialization.
public final class KokoroSession {
    private let handle: OpaquePointer

    public init(directory: URL) throws {
        var strings: [UnsafeMutablePointer<CChar>] = []
        defer { strings.forEach { free($0) } }
        func cString(_ value: String) -> UnsafePointer<CChar> {
            let pointer = strdup(value)!
            strings.append(pointer)
            return UnsafePointer(pointer)
        }
        func path(_ name: String) -> UnsafePointer<CChar> { cString(directory.appendingPathComponent(name).path) }
        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model = path("model.int8.onnx")
        config.model.kokoro.voices = path("voices.bin")
        config.model.kokoro.tokens = path("tokens.txt")
        config.model.kokoro.data_dir = path("espeak-ng-data")
        config.model.kokoro.dict_dir = path("dict")
        config.model.kokoro.lexicon = cString(["lexicon-us-en.txt", "lexicon-zh.txt"].map { directory.appendingPathComponent($0).path }.joined(separator: ","))
        config.model.kokoro.length_scale = 1
        config.model.num_threads = 2
        config.model.provider = cString("cpu")
        config.max_num_sentences = 1
        config.silence_scale = 0.2
        config.rule_fsts = cString(["date-zh.fst", "number-zh.fst", "phone-zh.fst"].map { directory.appendingPathComponent($0).path }.joined(separator: ","))
        guard let handle = SherpaOnnxCreateOfflineTts(&config) else { throw KokoroError.initializationFailed }
        self.handle = handle
    }

    deinit { SherpaOnnxDestroyOfflineTts(handle) }

    public var speakerCount: Int { Int(SherpaOnnxOfflineTtsNumSpeakers(handle)) }

    public func generate(text: String, speaker: Int, speed: Float, cancellation: KokoroCancellation) throws -> KokoroAudio {
        guard !text.isEmpty, !text.contains("\0"), speaker >= 0, speaker < speakerCount,
              speed.isFinite, (0.5...1.2).contains(speed) else { throw KokoroError.invalidRequest }
        if cancellation.isCancelled { throw CancellationError() }
        var config = SherpaOnnxGenerationConfig()
        config.sid = Int32(speaker)
        config.speed = speed
        config.silence_scale = 0.2
        let callback: SherpaOnnxGeneratedAudioProgressCallbackWithArg = { _, _, _, argument in
            guard let argument else { return 0 }
            let token = Unmanaged<KokoroCancellation>.fromOpaque(argument).takeUnretainedValue()
            return token.isCancelled ? 0 : 1
        }
        let argument = Unmanaged.passUnretained(cancellation).toOpaque()
        let audio = text.withCString { SherpaOnnxOfflineTtsGenerateWithConfig(handle, $0, &config, callback, argument) }
        guard let audio else {
            if cancellation.isCancelled { throw CancellationError() }
            throw KokoroError.noAudio
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        if cancellation.isCancelled { throw CancellationError() }
        guard audio.pointee.n > 0, audio.pointee.sample_rate > 0, let samples = audio.pointee.samples else { throw KokoroError.noAudio }
        let result = Array(UnsafeBufferPointer(start: samples, count: Int(audio.pointee.n)))
        guard result.allSatisfy(\.isFinite), result.contains(where: { abs($0) > 0.0001 }) else { throw KokoroError.noAudio }
        return KokoroAudio(samples: result, sampleRate: Int(audio.pointee.sample_rate))
    }
}
