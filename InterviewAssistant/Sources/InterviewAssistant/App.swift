import SwiftUI

/// 双击打包后的 .app 启动时没有 shell，读不到 export 的环境变量，
/// 所以优先看环境变量（swift run 场景），拿不到就回退读 ~/Documents/InterviewAssistant/.env
private func loadKey(_ name: String, envFileContent: [String: String]) -> String? {
    if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
        return value
    }
    return envFileContent[name]
}

private func parseEnvFile() -> [String: String] {
    guard let content = try? String(contentsOf: AppPaths.envFile, encoding: .utf8) else { return [:] }
    var result: [String: String] = [:]
    for line in content.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eqIndex = trimmed.firstIndex(of: "=") else { continue }
        let key = String(trimmed[..<eqIndex])
        let value = String(trimmed[trimmed.index(after: eqIndex)...])
        result[key] = value
    }
    return result
}

@main
struct InterviewAssistantApp: App {
    @StateObject private var viewModel: PipelineViewModel

    init() {
        let envFileContent = parseEnvFile()
        let assemblyKey = loadKey("ASSEMBLYAI_API_KEY", envFileContent: envFileContent)
        let anthropicKey = loadKey("ANTHROPIC_API_KEY", envFileContent: envFileContent)
        guard let vm = PipelineViewModel(assemblyKey: assemblyKey, anthropicKey: anthropicKey) else {
            fatalError("请设置 ASSEMBLYAI_API_KEY 和 ANTHROPIC_API_KEY（在 ~/Documents/InterviewAssistant/.env 里写 KEY=VALUE，一行一个）")
        }
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear { viewModel.start() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // 禁止 Cmd+N / "文件->新建窗口"，避免开出第二个窗口
        }
    }
}
