import AVFoundation
import Speech

@MainActor
final class VoiceTracker: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var recognizedText = ""
    @Published var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(language: String = "es-ES") async {
        guard await requestSpeechAuthorization() == .authorized else {
            errorMessage = "Activa el reconocimiento de voz en Ajustes."
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            errorMessage = "Activa el micrófono en Ajustes."
            return
        }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request, let recognizer else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.recognizedText = result.bestTranscription.formattedString }
                    if error != nil { self?.stop() }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }
}
