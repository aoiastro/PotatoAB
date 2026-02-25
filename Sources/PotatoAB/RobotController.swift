import Foundation
import SwiftUI
import Combine

enum RobotExpression: String {
    case idle = "Idle"
    case listening = "Listening"
    case thinking = "Thinking"
    case happy = "Happy"
    case sad = "Sad"
    case surprised = "Surprised"
    
    var emoji: String {
        switch self {
        case .idle: return "😐"
        case .listening: return "👂"
        case .thinking: return "🤔"
        case .happy: return "😄"
        case .sad: return "😢"
        case .surprised: return "😲"
        }
    }
}

@MainActor
class RobotController: ObservableObject {
    @Published var expression: RobotExpression = .idle
    @Published var spokenText: String = ""
    @Published var statusText: String = "Initializing..."
    
    let llmManager = LLMManager()
    let ttsManager = TTSManager()
    let speechManager = SpeechManager()
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
        
        speechManager.onCommandDetected = { [weak self] command in
            self?.processCommand(command)
        }
        
        ttsManager.onSpeechFinished = { [weak self] in
            self?.expression = .idle
            self?.spokenText = ""
            self?.statusText = "Waiting for Wake Word..."
            self?.speechManager.startListening()
        }
    }
    
    private func setupBindings() {
        speechManager.$state.sink { [weak self] state in
            switch state {
            case .waitingForWakeWord:
                if self?.ttsManager.isSpeaking == false {
                    self?.expression = .idle
                }
                self?.statusText = "Waiting for Wake Word..."
            case .listeningToCommand:
                self?.expression = .listening
                self?.statusText = "Listening..."
            case .processing:
                self?.expression = .thinking
                self?.statusText = "Thinking..."
            }
        }.store(in: &cancellables)
    }
    
    func start() async {
        statusText = "マイクの許可を要求中..."
        speechManager.requestMicrophonePermission()
        
        // Wait for permissions
        while !speechManager.hasPermission {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        statusText = "AIモデルを読み込み中..."
        await llmManager.loadModel()
        
        if llmManager.isModelLoaded {
            statusText = "準備完了"
            speechManager.startListening()
        } else {
            statusText = "モデルの読み込みに失敗しました"
            expression = .sad
        }
    }
    
    private func processCommand(_ command: String) {
        Task {
            spokenText = command
            expression = .thinking
            statusText = "考え中..."
            
            if let response = await llmManager.generate(prompt: command) {
                print("LLM Response: \(response)")
                
                // Parse expression
                if let newExpression = RobotExpression(rawValue: response.expression) {
                    expression = newExpression
                } else {
                    expression = .happy
                }
                
                statusText = "話しています..."
                spokenText = response.speech
                ttsManager.speak(text: response.speech)
            } else {
                statusText = "エラー"
                expression = .sad
                spokenText = "エラーが発生しました。"
                ttsManager.speak(text: "エラーが発生しました。")
            }
        }
    }
}
