import Foundation
import Speech
import AVFoundation

enum SpeechManagerState {
    case waitingForWakeWord
    case listeningToCommand
    case processing
}

@MainActor
class SpeechManager: ObservableObject {
    @Published var state: SpeechManagerState = .waitingForWakeWord
    @Published var recognizedText: String = ""
    @Published var hasPermission: Bool = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var completionTask: Task<Void, Never>?
    
    var onCommandDetected: ((String) -> Void)?
    
    init() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            Task { @MainActor in
                self.hasPermission = authStatus == .authorized
            }
        }
    }
    
    func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            if granted {
                SFSpeechRecognizer.requestAuthorization { authStatus in
                    Task { @MainActor in
                        self.hasPermission = authStatus == .authorized
                    }
                }
            }
        }
    }
    
    func startListening() {
        guard hasPermission, !audioEngine.isRunning else { return }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }
            
            recognitionRequest.shouldReportPartialResults = true
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // Remove tap if exists to prevent crash
            inputNode.removeTap(onBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
                recognitionRequest.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            state = .waitingForWakeWord
            
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                Task { @MainActor in
                    if let result = result {
                        let text = result.bestTranscription.formattedString
                        self.handleTranscriptionUpdate(text)
                    }
                    
                    if error != nil || (result?.isFinal ?? false) {
                        self.stopAudioEngine()
                        
                        // Prevent instant infinite loops bounds
                        if self.state == .waitingForWakeWord {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            self.startListening()
                        }
                    }
                }
            }
        } catch {
            print("Audio Engine Failed to Start: \(error)")
        }
    }
    
    func stopListeningAndReset() {
        stopAudioEngine()
        recognizedText = ""
        state = .waitingForWakeWord
    }
    
    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
    }
    
    private func handleTranscriptionUpdate(_ text: String) {
        recognizedText = text
        
        switch state {
        case .waitingForWakeWord:
            if text.contains("ポテト") || text.lowercased().contains("potato") {
                // Wake word detected! Clear the buffer and switch to listening mode
                print("Wake word detected!")
                self.state = .listeningToCommand
                
                // Restart recognition to clear old context
                self.stopAudioEngine()
                self.recognizedText = ""
                self.startListening()
            }
            
        case .listeningToCommand:
            // User is speaking their prompt. We use a heuristic: if they get silent for a short bit, or we hit a specific length.
            // In a real app we would use silence detection. SFSpeechRecognizer returns 'isFinal' if silence is long enough.
            // But we can also cancel the task if we want.
            print("Listening: \(text)")
            
            // To implement silence detection manually:
            completionTask?.cancel()
            completionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled {
                    self.commandFinished()
                }
            }
            
        case .processing:
            break
        }
    }
    
    private func commandFinished() {
        guard state == .listeningToCommand, !recognizedText.isEmpty else { return }
        print("Command Finished: \(recognizedText)")
        state = .processing
        stopAudioEngine()
        
        onCommandDetected?(recognizedText)
    }
}
