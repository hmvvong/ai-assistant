import Foundation

struct ChatTurn {
    let role: String // "user"（面试官）或 "assistant"（我方，麦克风识别到的实际发言）
    let content: String
}

/// Anthropic Messages API 要求 role 严格交替；把连续同角色的发言合并成一条，避免 400。
private func coalesce(_ history: [ChatTurn]) -> [ChatTurn] {
    var result: [ChatTurn] = []
    for turn in history {
        if let last = result.last, last.role == turn.role {
            result[result.count - 1] = ChatTurn(role: last.role, content: last.content + "\n" + turn.content)
        } else {
            result.append(turn)
        }
    }
    return result
}

final class AnthropicClient {
    private let apiKey: String
    private let session = URLSession(configuration: .default)

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func streamAnswer(system: String, history: [ChatTurn], onDelta: @escaping (String) -> Void) async throws {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = coalesce(history).map { ["role": $0.role, "content": $0.content] }
        // system 用数组+cache_control 形式，简历/背景信息这类不常变的内容可以命中缓存，重复调用只按10%计费
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 300,
            "stream": true,
            "system": [
                ["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]
            ],
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw NSError(domain: "AnthropicClient", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status): \(errorBody)"])
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            if type == "content_block_delta",
               let delta = obj["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                onDelta(text)
            }
        }
    }
}
