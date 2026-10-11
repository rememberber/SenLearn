import AVFoundation

enum SpeechVoiceStyle: String, CaseIterable, Identifiable, Sendable {
    case natural, bright, playful

    var id: String { rawValue }
    var name: String {
        switch self {
        case .natural: return "自然女声"
        case .bright: return "清亮女声"
        case .playful: return "童趣女声"
        }
    }
    var detail: String {
        switch self {
        case .natural: return "保留原音色，柔和自然。"
        case .bright: return "声音稍亮一些，轻快清晰。"
        case .playful: return "声音更高、更轻盈，适合活泼的共读。"
        }
    }
    var pitchCents: Float {
        switch self {
        case .natural: return 0
        case .bright: return 150
        case .playful: return 300
        }
    }
}

/// Runs on the inference actor, never the UI thread. Pitch changes independently of speed.
enum SpeechPitchProcessor {
    static func process(_ samples: [Float], sampleRate: Int, style: SpeechVoiceStyle,
                        isCancelled: () -> Bool = { false }) throws -> [Float] {
        if isCancelled() { throw CancellationError() }
        guard style != .natural else { return samples }
        guard !samples.isEmpty, sampleRate > 0, samples.allSatisfy(\.isFinite),
              let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            throw ProcessingError.failed
        }
        // Flush the effect after the final phoneme; do not truncate its tail at the input boundary.
        let padding = Int(Double(sampleRate) * 0.15)
        let total = samples.count + padding
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              let inputChannel = input.floatChannelData?[0] else { throw ProcessingError.failed }
        input.frameLength = AVAudioFrameCount(total)
        inputChannel.initialize(repeating: 0, count: total)
        samples.withUnsafeBufferPointer { inputChannel.update(from: $0.baseAddress!, count: samples.count) }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        engine.attach(player)
        engine.attach(pitch)
        engine.connect(player, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
        pitch.pitch = style.pitchCents
        pitch.rate = 1
        pitch.overlap = 16
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        defer { player.stop(); engine.stop(); engine.disableManualRenderingMode() }
        try engine.start()
        player.scheduleBuffer(input)
        player.play()

        var rendered = [Float]()
        rendered.reserveCapacity(total)
        var retries = 0
        while rendered.count < total {
            if isCancelled() { throw CancellationError() }
            let frames = AVAudioFrameCount(min(4096, total - rendered.count))
            let status = try engine.renderOffline(frames, to: output)
            switch status {
            case .success, .insufficientDataFromInputNode:
                guard output.frameLength > 0, let channel = output.floatChannelData?[0] else {
                    retries += 1
                    break
                }
                rendered.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
                retries = 0
            case .cannotDoInCurrentContext: retries += 1
            case .error: throw ProcessingError.failed
            @unknown default: throw ProcessingError.failed
            }
            guard retries < 100 else { throw ProcessingError.failed }
        }
        if isCancelled() { throw CancellationError() }
        guard rendered.allSatisfy(\.isFinite), let lastSound = rendered.lastIndex(where: { abs($0) > 0.00001 }) else {
            throw ProcessingError.failed
        }
        let end = min(total, max(samples.count, lastSound + 1 + sampleRate / 100))
        return Array(rendered.prefix(end))
    }

    enum ProcessingError: LocalizedError {
        case failed
        var errorDescription: String? { "暂时无法调整声音，请选择自然女声后重试。" }
    }
}
