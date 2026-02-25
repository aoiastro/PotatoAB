import Foundation
import SwiftUI
import MLX
import MLXRandom
import MLXLLM
import MLXLMCommon

@MainActor
@Observable
class LLMManager {
    var isDownloading = false
    var downloadProgress: Double = 0.0
    var isModelLoaded = false
    var isGenerating = false
    
    // MLX objects
    private var modelConfiguration = ModelConfiguration(
        id: "mlx-community/Qwen3-1.7B-4bit"
    )
    private var session: ChatSession?
    
    init() {
    }
    
    // System prompt forces the model to reply in a strict JSON format matching App needs.
    private let systemPrompt = """
    あなたはPotatoABという、フレンドリーで表情豊かなAIロボットです。
    返答は必ず以下のJSON形式のオブジェクトのみを出力してください。それ以外のテキスト（挨拶や説明など）は一切含めないでください。
    JSONは以下の2つのキーを持つ必要があります：
    - "speech": あなたが声に出して話す内容（日本語）。
    - "expression": あなたの今の気分を表す単語。以下のうち、どれか1つだけを正確に指定してください："Idle", "Listening", "Thinking", "Happy", "Sad", "Surprised"。
    
    出力例:
    {
      "speech": "こんにちは、ポテトです。",
      "expression": "Happy"
    }
    """
    
    func loadModel() async {
        guard !isModelLoaded else { return }
        isDownloading = true
        
        do {
            // MLXLLM has a load mechanism that reports progress.
            let modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: modelConfiguration
            ) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress.fractionCompleted
                }
            }
            
            self.session = ChatSession(
                modelContainer,
                instructions: systemPrompt,
                generateParameters: GenerateParameters(temperature: 0.6)
            )
            self.isModelLoaded = true
            self.isDownloading = false
        } catch {
            print("Failed to load MLX model: \(error)")
            self.isDownloading = false
        }
    }
    
    struct JSONOutput: Codable {
        let speech: String
        let expression: String
    }
    
    // Runs the LLM synchronously (but wrapped in Swift Concurrency so it doesn't block main)
    func generate(prompt: String) async -> JSONOutput? {
        guard isModelLoaded, let session = self.session else { return nil }
        
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            let text = try await session.respond(to: prompt)
            print("Raw LLM text: \(text)")
            
            if let parsed = parseJSON(from: text) {
                return parsed
            } else {
                return JSONOutput(speech: text, expression: "Thinking") // fallback
            }
        } catch {
            print("Generation Error: \(error)")
            return nil
        }
    }
    
    private func parseJSON(from string: String) -> JSONOutput? {
        var strToParse = string
        
        if let start = string.range(of: "{")?.lowerBound,
           let end = string.range(of: "}", options: .backwards)?.upperBound {
            strToParse = String(string[start..<end])
        }
        
        if let data = strToParse.data(using: .utf8) {
            return try? JSONDecoder().decode(JSONOutput.self, from: data)
        }
        return nil
    }
}
