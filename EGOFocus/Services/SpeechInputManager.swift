import Foundation
import Speech
import AVFoundation

/// Arabic dictation with Apple's Speech framework. Requests on-device recognition when the
/// device supports it for Arabic; otherwise Apple's speech service may process the audio.
@MainActor
final class SpeechInputManager: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published var errorMessage: String?
    @Published private(set) var usesOnDeviceRecognition = false

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "ar"))

    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        guard !isRecording, !isStarting else { return }
        errorMessage = nil
        isStarting = true
        defer { isStarting = false }

        guard let recognizer else {
            errorMessage = "التعرف على الكلام باللغة العربية غير مدعوم على هذا الجهاز."
            return
        }

        switch await Self.requestSpeechAuthorization() {
        case .authorized:
            break
        case .denied:
            errorMessage = "تم رفض إذن التعرف على الكلام. يمكنك تفعيله من: الإعدادات ← EGO FOCUS."
            return
        case .restricted:
            errorMessage = "التعرف على الكلام مقيّد على هذا الجهاز."
            return
        default:
            errorMessage = "لم يتم منح إذن التعرف على الكلام."
            return
        }

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "تم رفض إذن الميكروفون. يمكنك تفعيله من: الإعدادات ← EGO FOCUS."
            return
        }

        guard recognizer.isAvailable else {
            errorMessage = "خدمة التعرف على الكلام غير متاحة حالياً. حاول لاحقاً أو اكتب المهمة."
            return
        }

        do {
            try begin(with: recognizer)
        } catch {
            stop()
            errorMessage = "تعذر بدء التسجيل: \(error.localizedDescription)"
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        stop()
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            usesOnDeviceRecognition = true
        } else {
            usesOnDeviceRecognition = false
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "EGOFocus.Speech", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "لا يوجد ميكروفون متاح."])
        }
        Self.installTap(on: input, format: format, request: request)
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
        transcript = ""
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text, !text.isEmpty { self.transcript = text }
                if isFinal || failed {
                    if self.isRecording { self.stop() }
                    if failed && self.transcript.isEmpty {
                        self.errorMessage = "لم يتم التقاط كلام واضح. حاول مرة أخرى أو اكتب المهمة."
                    }
                    self.recognitionTask = nil
                }
            }
        }
    }

    /// Installed from a nonisolated context: the tap block runs on the audio thread.
    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
