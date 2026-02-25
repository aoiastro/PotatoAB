import SwiftUI

struct ContentView: View {
    @StateObject private var controller = RobotController()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if controller.llmManager.isDownloading {
                DownloadingView(progress: controller.llmManager.downloadProgress)
            } else {
                RobotFaceView(
                    expression: controller.expression.emoji,
                    spokenText: controller.spokenText,
                    statusText: controller.statusText
                )
            }
        }
        .task {
            await controller.start()
        }
    }
}

struct RobotFaceView: View {
    let expression: String
    let spokenText: String
    let statusText: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text(statusText)
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.top)
            
            Spacer()
            
            Text(expression)
                .font(.system(size: 200))
                .id(expression)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: expression)
            
            Spacer()
            
            Text(spokenText)
                .font(.title)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(16)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
    }
}

struct DownloadingView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .padding(.horizontal, 60)
            
            Text("Downloading Qwen3-1.7B Model...")
                .foregroundColor(.white)
                .font(.headline)
            
            Text("\(Int(progress * 100))%")
                .foregroundColor(.gray)
                .font(.subheadline)
        }
    }
}

#Preview {
    ContentView()
}
