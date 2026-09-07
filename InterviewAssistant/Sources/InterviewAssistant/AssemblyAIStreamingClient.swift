import Foundation

final class AssemblyAIStreamingClient: NSObject, URLSessionWebSocketDelegate {
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private let apiKey: String
    private let sampleRate: Int
    let label: String
    private var didReportError = false
    private var isOpen = false

    var onTranscript: ((_ text: String, _ isFinal: Bool) -> Void)?
    var onBegin: (() -> Void)?
    var onError: ((Error) -> Void)?
    var onClose: ((_ code: Int, _ reason: String) -> Void)?

    init(apiKey: String, sampleRate: Int, label: String) {
        self.apiKey = apiKey
        self.sampleRate = sampleRate
        self.label = label
    }

    func connect() {
        var components = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        components.queryItems = [
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "format_turns", value: "true"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiveLoop()
    }

    func send(pcm16 data: Data) {
        guard isOpen else { return }
        task?.send(.data(data)) { [weak self] error in
            if let error {
                self?.reportError(error)
            }
        }
    }

    func terminate() {
        task?.send(.string("{\"type\":\"Terminate\"}")) { _ in }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isOpen = true
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isOpen = false
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "(no reason)"
        onClose?(closeCode.rawValue, reasonText)
    }

    private func reportError(_ error: Error) {
        guard !didReportError else { return }
        didReportError = true
        onError?(error)
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.reportError(error)
                return
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handle(text)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "Begin":
            onBegin?()
        case "Turn":
            let transcript = obj["transcript"] as? String ?? ""
            let endOfTurn = obj["end_of_turn"] as? Bool ?? false
            if !transcript.isEmpty {
                onTranscript?(transcript, endOfTurn)
            }
        default:
            break
        }
    }
}
