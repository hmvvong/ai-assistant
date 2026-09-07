import Foundation

struct InterviewRecord: Codable {
    let timestamp: Date
    let company: String
    let position: String
    let round: String
    let question: String
    let answer: String
}

enum InterviewLog {
    private static let fileURL = AppPaths.interviewLog

    static func append(_ record: InterviewRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        guard let lineData = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                try? handle.close()
            }
        } else {
            try? lineData.write(to: fileURL)
        }
    }

    /// 读取最近 N 条历史问答（跨会话），用作 few-shot 风格范例。
    static func recent(_ limit: Int) -> [InterviewRecord] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = content.split(separator: "\n").compactMap { line -> InterviewRecord? in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(InterviewRecord.self, from: data)
        }
        return Array(records.suffix(limit))
    }
}
