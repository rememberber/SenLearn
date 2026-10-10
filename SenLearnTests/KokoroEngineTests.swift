import AVFoundation
import Darwin
import KokoroRuntime
import XCTest
@testable import SenLearn

final class KokoroEngineTests: XCTestCase {
    func testBundledModelProducesChineseEnglishAndMixedAudioWithCache() async throws {
        XCTAssertTrue(KokoroEngine.isBundled, "Model and pronunciation resources must be bundled, not downloaded by the app.")
        let engine = KokoroEngine()
        for (name, text) in [("english-word", "squirrel"), ("chinese-word", "松鼠"), ("english", "The little squirrel lives in the forest."),
                             ("chinese", "小松鼠在森林里找到了一个种子。"),
                             ("mixed", "今天读 English，第 2 页。2026年10月10日。") ] {
            let result = try await engine.synthesize(text: text, speed: 0.8)
            XCTAssertEqual(result.audio.sampleRate, 24_000)
            XCTAssertGreaterThan(result.audio.duration, 0.15)
            XCTAssertLessThan(result.audio.duration, 30)
            XCTAssertTrue(result.audio.samples.allSatisfy(\.isFinite))
            let rms = sqrt(result.audio.samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(result.audio.samples.count))
            XCTAssertGreaterThan(rms, 0.001, "Generated speech must contain non-silent PCM.")
            let replay = try await engine.synthesize(text: text, speed: 0.8)
            XCTAssertTrue(replay.cached)
            XCTAssertEqual(replay.audio.samples, result.audio.samples)
            let wav = result.audio.wavData
            XCTAssertEqual(String(data: wav.prefix(4), encoding: .utf8), "RIFF")
            let decodedDuration = try await Task.detached { try AVAudioPlayer(data: wav).duration }.value
            XCTAssertEqual(decodedDuration, result.audio.duration, accuracy: 0.05)
            let attachment = XCTAttachment(data: wav, uniformTypeIdentifier: "com.microsoft.waveform-audio")
            attachment.name = "kokoro-\(name).wav"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("KOKORO_METRIC \(name) generation=\(result.elapsed) audio=\(result.audio.duration) cache=\(replay.elapsed) rms=\(rms) \(memoryMetrics())")
        }
        let normal = try await engine.synthesize(text: "A little squirrel.", speed: 1.0)
        let slower = try await engine.synthesize(text: "A little squirrel.", speed: 0.5)
        XCTAssertGreaterThan(slower.audio.duration, normal.audio.duration * 1.3)
        XCTAssertFalse(slower.cached, "Speed must be part of the audio cache key.")
    }

    private func memoryMetrics() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "memory=unavailable" }
        return "footprintMiB=\(Double(info.phys_footprint) / 1_048_576) residentPeakMiB=\(Double(info.resident_size_peak) / 1_048_576)"
    }

    func testPagePlaybackChunksStayWithinMeasuredMemoryBounds() async throws {
        let engine = KokoroEngine()
        let text = "今天读 English，第 2 页。2026年10月10日。The little squirrel lives in the forest."
        let chunks = KokoroEngine.chunks(for: text)
        var duration = 0.0
        for chunk in chunks {
            let result = try await engine.synthesize(text: chunk, speed: 0.8)
            duration += result.audio.duration
        }
        XCTAssertGreaterThan(duration, 1)
        print("KOKORO_METRIC chunked-page chunks=\(chunks.count) audio=\(duration) \(memoryMetrics())")
    }

    func testCancelledInferenceCannotReturnOrCachePartialAudio() async throws {
        let engine = KokoroEngine()
        _ = try await engine.synthesize(text: "Warm up.", speed: 1.0)
        let text = "小松鼠在森林里找到了一个种子。" + String(repeating: "今天一起学习。", count: 12)
        let task = Task { try await engine.synthesize(text: text, speed: 0.8) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled request must not return stale audio.") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let next = try await engine.synthesize(text: "Hello.", speed: 0.8)
        XCTAssertGreaterThan(next.audio.duration, 0)
    }

    func testMissingModelFailsWithoutSystemOrNetworkFallback() async {
        do {
            _ = try await KokoroEngine(directory: URL(fileURLWithPath: "/missing-kokoro-model")).synthesize(text: "Hello", speed: 0.8)
            XCTFail("Missing assets must be reported.")
        } catch KokoroEngine.EngineError.missingModel {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testLongPageChunkingPreservesAllWordsAndChineseCharacters() {
        let english = Array(repeating: "The little squirrel finds a seed.", count: 30).joined(separator: " ")
        let chinese = String(repeating: "小松鼠在森林里找到了一个种子。", count: 40)
        for text in [english, chinese, Array(repeating: "squirrel", count: 70).joined(separator: " "), String(repeating: "小松鼠喜欢森林", count: 25)] {
            let chunks = KokoroEngine.chunks(for: text)
            XCTAssertGreaterThan(chunks.count, 1)
            XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= (KokoroEngine.containsChinese(text) ? 20 : 60) })
            let normalize: (String) -> String = { String($0.filter { !$0.isWhitespace }) }
            XCTAssertEqual(normalize(chunks.joined()), normalize(text))
        }
        XCTAssertTrue(KokoroEngine.chunks(for: " \n ").isEmpty)
    }

    @MainActor
    func testStoppingAndRapidReplacementOnlyPlayLatestRequest() async throws {
        let saved = UserDefaults.standard.object(forKey: "speech.engine")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "speech.engine") }
            else { UserDefaults.standard.removeObject(forKey: "speech.engine") }
        }
        let player = SpeechPlayer()
        player.engine = .kokoro
        player.speak("This first request should never finish playing.")
        player.stop()
        XCTAssertFalse(player.isSpeaking)
        player.speak("Hello.")
        player.togglePause() // Pause during preparation is retained for the generated player.
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(player.isPaused)
        player.togglePause()
        for _ in 0..<200 where player.isSpeaking { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(player.isSpeaking)
        XCTAssertNil(player.statusMessage)
        XCTAssertNotNil(player.synthesisSummary)
        player.stop()
    }
}
