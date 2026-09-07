import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: PipelineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.status)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("我方STT: \(viewModel.myStatus)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("麦克风引擎: \(viewModel.micEngineStatus) | 音频包: \(viewModel.micBufferCount)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            Text("面试官问题")
                .font(.headline)
            Text(viewModel.question.isEmpty ? "（等待提问...）" : viewModel.question)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(viewModel.question.isEmpty ? .secondary : .primary)

            Text(viewModel.myTranscript.isEmpty ? " " : "你: \(viewModel.myTranscript)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(height: 28, alignment: .top)

            Divider()

            Text("AI 建议回答")
                .font(.headline)
            ScrollView {
                Text(viewModel.answer)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 380, height: 360)
        .background(.thinMaterial)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                window.level = .floating
                window.collectionBehavior.insert(.canJoinAllSpaces)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
