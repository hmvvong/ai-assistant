import Foundation

/// 打包成 .app 后不能再依赖相对路径（双击启动时当前目录不是项目文件夹），
/// 所有个人数据文件统一固定放在 ~/Documents/InterviewAssistant/。
enum AppPaths {
    static let supportDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/InterviewAssistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var profile: URL { supportDir.appendingPathComponent("profile.md") }
    static var companyContext: URL { supportDir.appendingPathComponent("company_context.md") }
    static var questions: URL { supportDir.appendingPathComponent("questions.md") }
    static var interviewLog: URL { supportDir.appendingPathComponent("interview_log.jsonl") }
    static var envFile: URL { supportDir.appendingPathComponent(".env") }
}
