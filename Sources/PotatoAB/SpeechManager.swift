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
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }
            
            recognitionRequest.shouldReportPartialResults = true
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
                recognitionRequest.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            state = .waitingForWakeWord
            
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.handleTranscriptionUpdate(text)
                    }
                }
                
                if error != nil || (result?.isFinal ?? false) {
                    self.stopAudioEngine()
                    // Auto restart if waiting for wake word and it closed
                    if self.state == .waitingForWakeWord {
                        self.startListening()
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
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(commandFinished), object: nil)
            perform(#selector(commandFinished), with: nil, afterDelay: 2.0)
            
        case .processing:
            break
        }
    }
    
    @objc private func commandFinished() {
        guard state == .listeningToCommand, !recognizedText.isEmpty else { return }
        print("Command Finished: \(recognizedText)")
        state = .processing
        stopAudioEngine()
        
        onCommandDetected?(recognizedText)
    }
}
