import AVFoundation
import Combine
import UIKit

enum SpeechEngine: String, CaseIterable, Identifiable {
    case kokoro, system
    var id: String { rawValue }
    var name: String { self == .kokoro ? "Kokoro 离线声音" : "系统声音" }
}

/// Bundled Kokoro is the default; system speech remains an explicit comparison option.
@MainActor
final class SpeechPlayer: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var statusMessage: String?
    @Published var rate: Double {
        didSet {
            let normalized = rate.isFinite ? min(max(rate, 0.5), 1.2) : 0.8
            if rate != normalized { rate = normalized }
            UserDefaults.standard.set(normalized, forKey: "speech.rate")
        }
    }

    @Published var engine: SpeechEngine {
        didSet {
            guard oldValue != engine else { return }
            stop()
            UserDefaults.standard.set(engine.rawValue, forKey: "speech.engine")
        }
    }
    @Published private(set) var synthesisSummary: String?
    private let kokoro = KokoroEngine()
    private var offlineTask: Task<Void, Never>?
    private var offlineRequestID: UUID?
    private var audioPlayer: AVAudioPlayer?
    private var playbackCompletion: CheckedContinuation<Void, Error>?

    @Published private var lastText = ""
    private var synthesizer: AVSpeechSynthesizer?
    private let audioSessionQueue = DispatchQueue(label: "com.senlearn.audio-session")
    private var activeUtteranceID: ObjectIdentifier?
    private var pendingUtterance: AVSpeechUtterance?
    private var hasStartedSpeech = false
    private var preparationTimeout: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    var canReplay: Bool { !lastText.isEmpty }

    var voiceAvailabilitySummary: String {
        if engine == .kokoro {
            return KokoroEngine.isBundled ? "中文和英文声音已随应用安装，可直接离线朗读。" : "离线声音文件不完整，请重新安装包含模型的版本。"
        }
        let hasEnglish = availableVoice(language: "en-US") != nil
        let hasChinese = availableVoice(language: "zh-CN") != nil
        switch (hasEnglish, hasChinese) {
        case (true, true): return "已找到这台设备的中文和英文声音。"
        case (true, false): return "已找到英文声音，中文声音暂不可用。"
        case (false, true): return "已找到中文声音，英文声音暂不可用。"
        case (false, false): return "这台设备暂未提供可用的中文或英文声音。"
        }
    }

    override init() {
        let savedRate = UserDefaults.standard.object(forKey: "speech.rate") as? Double ?? 0.8
        engine = SpeechEngine(rawValue: UserDefaults.standard.string(forKey: "speech.engine") ?? "") ?? .kokoro
        rate = savedRate.isFinite ? min(max(savedRate, 0.5), 1.2) : 0.8
        super.init()

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stop()
                    await self.kokoro.releaseResources()
                }
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor [weak self] in self?.stop() }
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                guard rawReason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                Task { @MainActor [weak self] in self?.stop() }
            }
            .store(in: &subscriptions)
    }

    func speak(_ text: String) {
        // Clear identity before stopping: delayed callbacks from a previous tap cannot
        // alter the new selection's playback state.
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastText = trimmed

        guard let language = supportedLanguage(for: trimmed) else {
            statusMessage = "请选择中文或英文文字后点读。"
            return
        }
        if engine == .kokoro {
            speakOffline(trimmed)
            return
        }
        guard let voice = availableVoice(language: language) else {
            let name = language == "zh-CN" ? "中文" : "英文"
            statusMessage = "这台设备的\(name)声音暂不可用，请在系统设置中添加声音后重试。"
            return
        }

        if synthesizer == nil {
            synthesizer = AVSpeechSynthesizer()
            synthesizer?.delegate = self
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
        utterance.volume = 1
        activeUtteranceID = ObjectIdentifier(utterance)
        pendingUtterance = utterance
        hasStartedSpeech = false
        isSpeaking = true
        statusMessage = "正在准备声音"
        let expectedID = ObjectIdentifier(utterance)
        // Serial session work stays off the UI thread. Stop/new-tap requests enqueue
        // in order, and an obsolete activation can never start an old utterance.
        audioSessionQueue.async { [weak self] in
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try audioSession.setActive(true)
                Task { @MainActor [weak self] in
                    guard let self, self.activeUtteranceID == expectedID, let utterance = self.pendingUtterance else { return }
                    self.pendingUtterance = nil
                    self.synthesizer?.speak(utterance)
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self, self.activeUtteranceID == expectedID else { return }
                    self.stop()
                    self.statusMessage = "暂时无法播放声音，请稍后再试。"
                }
            }
        }

        preparationTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, activeUtteranceID == expectedID, !hasStartedSpeech else { return }
            stop()
            statusMessage = "此声音暂不可用，请检查设备的声音设置后重试。"
        }
    }

    func replay() {
        guard canReplay else { return }
        speak(lastText)
    }

    func stop() {
        offlineRequestID = nil
        offlineTask?.cancel()
        offlineTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        let completion = playbackCompletion
        playbackCompletion = nil
        completion?.resume(throwing: CancellationError())
        activeUtteranceID = nil
        pendingUtterance = nil
        preparationTimeout?.cancel()
        preparationTimeout = nil
        synthesizer?.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        hasStartedSpeech = false
        statusMessage = nil
        deactivateAudioSession()
    }

    func togglePause() {
        if offlineRequestID != nil, isSpeaking {
            isPaused.toggle()
            if isPaused { audioPlayer?.pause() }
            else { audioPlayer?.play() }
            return
        }
        guard activeUtteranceID != nil, isSpeaking else { return }
        if isPaused {
            if synthesizer?.continueSpeaking() == true { isPaused = false }
        } else if synthesizer?.pauseSpeaking(at: .immediate) == true {
            isPaused = true
        }
    }

    private func speakOffline(_ text: String) {
        let requestID = UUID()
        offlineRequestID = requestID
        let speed = rate
        isSpeaking = true
        statusMessage = "正在准备离线声音"
        offlineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let chunks = KokoroEngine.chunks(for: text)
                for chunk in chunks {
                    let result = try await kokoro.synthesize(text: chunk, speed: speed)
                    try Task.checkCancellation()
                    guard offlineRequestID == requestID else { throw CancellationError() }
                    synthesisSummary = String(format: "准备 %.2f 秒 · 音频 %.1f 秒%@", result.elapsed, result.audio.duration, result.cached ? " · 已缓存" : "")
                    let player = try await preparePlayer(result)
                    try Task.checkCancellation()
                    guard offlineRequestID == requestID else { throw CancellationError() }
                    player.delegate = self
                    audioPlayer = player
                    statusMessage = nil
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        self.playbackCompletion = continuation
                        // A pause requested during synthesis also applies to this new player.
                        if !self.isPaused, !player.play() {
                            self.playbackCompletion = nil
                            continuation.resume(throwing: PlaybackError.failed)
                        }
                    }
                    audioPlayer = nil
                }
                guard offlineRequestID == requestID else { return }
                offlineRequestID = nil; offlineTask = nil
                isSpeaking = false; isPaused = false; statusMessage = nil
                deactivateAudioSession()
            } catch is CancellationError {
                // stop() owns state cleanup; an old request must never alter a new one.
            } catch {
                guard offlineRequestID == requestID else { return }
                stop()
                statusMessage = error.localizedDescription
            }
        }
    }

    private func preparePlayer(_ result: SynthesizedSpeech) async throws -> AVAudioPlayer {
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                    try session.setActive(true)
                    let player = try AVAudioPlayer(data: result.audio.wavData)
                    guard player.prepareToPlay() else { throw PlaybackError.failed }
                    continuation.resume(returning: player)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func finishedPlayback(id: ObjectIdentifier, success: Bool) {
        guard let audioPlayer, ObjectIdentifier(audioPlayer) == id else { return }
        let completion = playbackCompletion
        playbackCompletion = nil
        if success { completion?.resume() }
        else { completion?.resume(throwing: PlaybackError.failed) }
    }

    private enum PlaybackError: LocalizedError {
        case failed
        var errorDescription: String? { "暂时无法播放声音，请稍后再试。" }
    }

    private func availableVoice(language: String) -> AVSpeechSynthesisVoice? {
        // Choose only an explicitly enumerated device voice, never the implicit
        // system fallback or a voice that might need an on-demand download.
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                return $0.identifier < $1.identifier
            }
            .first
    }

    private func supportedLanguage(for text: String) -> String? {
        if text.unicodeScalars.contains(where: { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value) ||
            (0x20000...0x323AF).contains(scalar.value)
        }) { return "zh-CN" }
        if text.unicodeScalars.contains(where: { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }) { return "en-US" }
        return nil
    }

    private func deactivateAudioSession() {
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func didStart(id: ObjectIdentifier) {
        guard activeUtteranceID == id else { return }
        hasStartedSpeech = true
        preparationTimeout?.cancel()
        preparationTimeout = nil
        statusMessage = nil
        isSpeaking = true
        isPaused = false
    }

    private func didEnd(id: ObjectIdentifier) {
        guard activeUtteranceID == id else { return }
        activeUtteranceID = nil
        pendingUtterance = nil
        preparationTimeout?.cancel()
        preparationTimeout = nil
        isSpeaking = false
        isPaused = false
        hasStartedSpeech = false
        statusMessage = nil
        deactivateAudioSession()
    }

    private func didPause(id: ObjectIdentifier, paused: Bool) {
        guard activeUtteranceID == id else { return }
        isPaused = paused
    }
}

extension SpeechPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didStart(id: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didEnd(id: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didEnd(id: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didPause(id: id, paused: true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didPause(id: id, paused: false) }
    }
}

extension SpeechPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.finishedPlayback(id: id, success: flag) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.finishedPlayback(id: id, success: false) }
    }
}
