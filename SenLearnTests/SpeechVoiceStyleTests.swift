import AVFoundation
import XCTest
@testable import SenLearn

final class SpeechVoiceStyleTests: XCTestCase {
    func testPitchChangesFrequencyWithoutSpeedingUpOrDroppingTheEnding() throws {
        let sampleRate = 24_000
        let samples = sine(frameCount: sampleRate)
        XCTAssertEqual(try SpeechPitchProcessor.process(samples, sampleRate: sampleRate, style: .natural), samples)
        for style in [SpeechVoiceStyle.bright, .playful] {
            let adjusted = try SpeechPitchProcessor.process(samples, sampleRate: sampleRate, style: style)
            XCTAssertTrue(adjusted.allSatisfy(\.isFinite))
            XCTAssertGreaterThanOrEqual(adjusted.count, samples.count)
            XCTAssertLessThanOrEqual(adjusted.count, samples.count + sampleRate * 15 / 100)
            let middle = Array(adjusted[6000..<18000])
            let risingCrossings = zip(middle, middle.dropFirst()).filter { $0.0 <= 0 && $0.1 > 0 }.count
            let measuredFrequency = Double(risingCrossings) * Double(sampleRate) / Double(middle.count)
            let expectedFrequency = 220 * pow(2, Double(style.pitchCents) / 1200)
            XCTAssertEqual(measuredFrequency, expectedFrequency, accuracy: 6)
            let ending = adjusted[(samples.count - 2400)..<samples.count]
            XCTAssertGreaterThan(ending.reduce(0) { $0 + Double($1 * $1) } / Double(ending.count), 0.01)
        }
    }

    func testCancelledPitchRenderingCannotReturnPartialAudio() throws {
        let samples = sine(frameCount: 48_000)
        var checks = 0
        XCTAssertThrowsError(try SpeechPitchProcessor.process(samples, sampleRate: 24_000, style: .playful) {
            checks += 1
            return checks > 3
        }) { XCTAssertTrue($0 is CancellationError) }
    }

    private func sine(frameCount: Int) -> [Float] {
        let angularStep = 2 * Double.pi * 220 / 24_000
        return (0..<frameCount).map { Float(0.3 * sin(angularStep * Double($0))) }
    }

    @MainActor
    func testVoiceStylePersistsAndChangingItStopsOldPlayback() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "speech.voiceStyle")
        defer {
            if let saved { defaults.set(saved, forKey: "speech.voiceStyle") }
            else { defaults.removeObject(forKey: "speech.voiceStyle") }
        }
        defaults.removeObject(forKey: "speech.voiceStyle")
        let player = SpeechPlayer()
        XCTAssertEqual(player.voiceStyle, .playful)
        player.speak("Hello, little squirrel!")
        player.voiceStyle = .natural
        XCTAssertFalse(player.isSpeaking)
        XCTAssertEqual(SpeechPlayer().voiceStyle, .natural)
    }

    func testChineseEnglishStyleSamplesAndCacheIsolation() async throws {
        let engine = KokoroEngine()
        for (language, text) in [("chinese", "小松鼠，我们一起去森林玩吧！"), ("english", "Hello, little squirrel! Let's play in the forest.")] {
            let natural = try await engine.synthesize(text: text, speed: 0.8, style: .natural)
            let playful = try await engine.synthesize(text: text, speed: 0.8, style: .playful)
            XCTAssertFalse(playful.cached, "Changing style must not replay the old voice from cache.")
            XCTAssertNotEqual(playful.audio.samples, natural.audio.samples)
            XCTAssertEqual(playful.audio.duration, natural.audio.duration, accuracy: 0.15)
            let cached = try await engine.synthesize(text: text, speed: 0.8, style: .playful)
            XCTAssertTrue(cached.cached)
            XCTAssertEqual(cached.audio.samples, playful.audio.samples)
            for (name, result) in [("natural", natural), ("playful", playful)] {
                let wav = result.audio.wavData
                let duration = try await Task.detached { try AVAudioPlayer(data: wav).duration }.value
                XCTAssertEqual(duration, result.audio.duration, accuracy: 0.05)
                let attachment = XCTAttachment(data: wav, uniformTypeIdentifier: "com.microsoft.waveform-audio")
                attachment.name = "\(language)-\(name).wav"
                attachment.lifetime = .keepAlways
                add(attachment)
                print("VOICE_STYLE_METRIC \(language) \(name) generation=\(result.elapsed) duration=\(result.audio.duration)")
            }
        }
    }
}
