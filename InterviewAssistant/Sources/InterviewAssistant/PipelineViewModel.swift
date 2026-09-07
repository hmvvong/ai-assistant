import Foundation
import AVFoundation
import AppKit

@MainActor
final class PipelineViewModel: ObservableObject {
    @Published var status: String = "未启动"
    @Published var myStatus: String = "未连接"
    @Published var micEngineStatus: String = "未启动"
    @Published var micBufferCount: Int = 0
    @Published var question: String = ""
    @Published var myTranscript: String = ""
    @Published var answer: String = ""

    @Published var company: String = ""
    @Published var position: String = ""
    @Published var round: String = ""
    @Published var companyContext: String = ""

    private var didStart = false

    private var history: [ChatTurn] = []
    private var pendingQuestion: String?
    private var pendingAnswerFragments: [String] = []
    private var flushTask: Task<Void, Never>?

    private let assemblyKey: String
    private let anthropicKey: String
    private let llm: AnthropicClient

    private var interviewerSTT: AssemblyAIStreamingClient?
    private var systemAudio: SystemAudioCapture?
    private var interviewerAggregator: PCMChunkAggregator?
    private var systemAudioRetryCount = 0
    private let systemAudioMaxRetries = 5

    private var mySTT: AssemblyAIStreamingClient?
    private var mic: MicCapture?
    private var micAggregator: PCMChunkAggregator?

    private let systemPromptBase = "You are the interviewee's personal assistant, helping them draft a quick answer to an interview question. You'll see the running interview transcript so far (interviewer questions and the candidate's own prior answers) — use it to stay consistent with what the candidate already said, especially for follow-up questions. First figure out the question type: (1) Behavioral/personal questions (about experience, projects, motivation, \"tell me about a time...\") — write 2-3 sentences, first person, conversational spoken English, like something a real person would actually say out loud. (2) Technical/definitional questions (e.g. \"what's the difference between GET and POST\", \"what does idempotent mean\") — answer concisely and directly like a textbook/reference answer, only covering what was actually asked; do not pad with unrelated extra info, examples, or tangents the interviewer didn't ask for. In both cases: no bullet points, no headers, and avoid stock AI phrasing like \"great question\" or \"I'd be happy to.\" Draw on the candidate's background and project details below to make behavioral answers specific and personal rather than generic. If the interviewer's question closely matches one of the Prepared Answers, or matches a section in the Company & Role Context (e.g. \"why this company\" matching the \"Why This Company\" section), reproduce that prepared text WORD FOR WORD — do not paraphrase, shorten, or rewrite it. For every other behavioral question, use the Prepared Answers as your style/tone reference and the Company & Role Context as grounding — match tone and vocabulary when drafting a fresh answer."

    /// 从 company_context.md 里解析 "Company: xxx" 这种结构化行，取不到就返回空字符串。
    private func extractField(_ name: String, from text: String) -> String {
        let prefix = "\(name):"
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                return trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    /// 每次提问时重新构建（公司信息中途可能会改），profile.md 这部分内容不变时 prompt caching 仍然命中。
    private func buildSystemPrompt() -> String {
        var prompt = systemPromptBase

        let profile = (try? String(contentsOf: AppPaths.profile, encoding: .utf8)) ?? ""
        if !profile.isEmpty {
            prompt += "\n\n--- Candidate Background ---\n" + profile
        }

        let preparedAnswers = (try? String(contentsOf: AppPaths.questions, encoding: .utf8)) ?? ""
        if !preparedAnswers.isEmpty {
            prompt += "\n\n--- Prepared Answers (VERBATIM on a close match; otherwise use as style reference) ---\n" + preparedAnswers
        }

        if !company.isEmpty || !position.isEmpty || !companyContext.isEmpty {
            prompt += "\n\n--- Company & Role Context (VERBATIM on a section match, e.g. a \"Why This Company\" style question) ---\n"
            if !company.isEmpty { prompt += "Company: \(company)\n" }
            if !position.isEmpty { prompt += "Role: \(position)\n" }
            if !companyContext.isEmpty { prompt += "\(companyContext)\n" }
        }

        return prompt
    }

    init?(assemblyKey: String?, anthropicKey: String?) {
        guard let assemblyKey, let anthropicKey, !assemblyKey.isEmpty, !anthropicKey.isEmpty else { return nil }
        self.assemblyKey = assemblyKey
        self.anthropicKey = anthropicKey
        self.llm = AnthropicClient(apiKey: anthropicKey)
    }

    func start() {
        guard !didStart else { return } // 多个窗口/onAppear重复触发时，只启动一次后台流水线
        didStart = true

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.flushPendingAnswer() }
        }

        if let loaded = try? String(contentsOf: AppPaths.companyContext, encoding: .utf8) {
            companyContext = loaded
            company = extractField("Company", from: loaded)
            position = extractField("Position", from: loaded)
            round = extractField("Round", from: loaded)
        }

        Task {
            let micGranted = await AVCaptureDevice.requestAccess(for: .audio)

            setupInterviewerPipeline()
            if micGranted {
                setupMyPipeline()
            }

            status = "连接中..."
            interviewerSTT?.connect()
            mySTT?.connect()
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            do {
                try await systemAudio?.start()
            } catch {
                status = "系统音频采集启动失败: \(error.localizedDescription)"
            }

            if mic == nil {
                micEngineStatus = "未创建(mic权限未授予?)"
            } else {
                do {
                    try mic?.start()
                    micEngineStatus = "启动成功"
                } catch {
                    micEngineStatus = "启动失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func setupInterviewerPipeline() {
        let stt = AssemblyAIStreamingClient(apiKey: assemblyKey, sampleRate: 48000, label: "interviewer")
        stt.onBegin = { [weak self] in
            Task { @MainActor in self?.status = "已连接，等待提问..." }
        }
        stt.onError = { [weak self] error in
            Task { @MainActor in self?.status = "STT错误(面试官): \(error.localizedDescription)" }
        }
        stt.onClose = { [weak self] code, reason in
            Task { @MainActor in self?.status = "连接已关闭(面试官) (\(code)) \(reason)" }
        }
        stt.onTranscript = { [weak self] text, isFinal in
            Task { @MainActor in
                self?.question = text
                if isFinal, !text.isEmpty {
                    self?.flushPendingAnswer()
                    self?.history.append(ChatTurn(role: "user", content: text))
                    self?.pendingQuestion = text
                    self?.askLLM()
                }
            }
        }
        self.interviewerSTT = stt

        let aggregator = PCMChunkAggregator(sampleRate: 48000, chunkMilliseconds: 100) { [weak stt] chunk in
            stt?.send(pcm16: chunk)
        }
        self.interviewerAggregator = aggregator

        let systemAudio = SystemAudioCapture()
        systemAudio.onSampleBuffer = { [weak aggregator] sampleBuffer in
            if let data = PCMConverter.toInt16PCM(sampleBuffer: sampleBuffer) {
                aggregator?.append(data)
            }
        }
        systemAudio.onStreamError = { [weak self] error in
            Task { @MainActor in self?.handleSystemAudioError(error) }
        }
        self.systemAudio = systemAudio
    }

    private func handleSystemAudioError(_ error: Error) {
        guard systemAudioRetryCount < systemAudioMaxRetries else {
            status = "系统音频采集多次中断，已停止自动重连: \(error.localizedDescription)"
            return
        }
        systemAudioRetryCount += 1
        status = "系统音频采集中断，正在重连(\(systemAudioRetryCount)/\(systemAudioMaxRetries))..."
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                try await systemAudio?.start()
                await MainActor.run {
                    self.systemAudioRetryCount = 0
                    self.status = "已重新连接系统音频"
                }
            } catch {
                await MainActor.run { self.handleSystemAudioError(error) }
            }
        }
    }

    private func setupMyPipeline() {
        let mic = MicCapture()
        self.mic = mic

        let stt = AssemblyAIStreamingClient(apiKey: assemblyKey, sampleRate: Int(mic.sampleRate.rounded()), label: "me")
        stt.onBegin = { [weak self] in
            Task { @MainActor in self?.myStatus = "已连接" }
        }
        stt.onError = { [weak self] error in
            Task { @MainActor in self?.myStatus = "STT错误: \(error.localizedDescription)" }
        }
        stt.onClose = { [weak self] code, reason in
            Task { @MainActor in self?.myStatus = "连接已关闭 (\(code)) \(reason)" }
        }
        stt.onTranscript = { [weak self] text, isFinal in
            Task { @MainActor in
                self?.myTranscript = text
                if isFinal, !text.isEmpty {
                    self?.history.append(ChatTurn(role: "assistant", content: text))
                    self?.pendingAnswerFragments.append(text)
                    self?.scheduleFlushOnSilence()
                }
            }
        }
        self.mySTT = stt

        let aggregator = PCMChunkAggregator(sampleRate: Int(mic.sampleRate.rounded()), chunkMilliseconds: 100) { [weak stt] chunk in
            stt?.send(pcm16: chunk)
        }
        self.micAggregator = aggregator

        mic.onBuffer = { [weak self, weak aggregator] buffer in
            if let data = PCMConverter.toInt16PCM(buffer: buffer) {
                aggregator?.append(data)
            }
            Task { @MainActor in self?.micBufferCount += 1 }
        }
    }

    /// 说完话后 5 秒没有新内容，视为回答说完，自动保存（不用等下一个问题或退出app）。
    private func scheduleFlushOnSilence() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self.flushPendingAnswer()
        }
    }

    /// 把攒到的所有回答片段合并成一条完整记录写入日志；在下一个问题出现、静默5秒、或app退出时调用。
    private func flushPendingAnswer() {
        flushTask?.cancel()
        defer { pendingAnswerFragments = [] }
        guard let question = pendingQuestion, !pendingAnswerFragments.isEmpty else { return }
        let fullAnswer = pendingAnswerFragments.joined(separator: " ")
        let record = InterviewRecord(
            timestamp: Date(),
            company: company,
            position: position,
            round: round,
            question: question,
            answer: fullAnswer
        )
        InterviewLog.append(record)
    }

    private func askLLM() {
        answer = ""
        let currentHistory = history
        let systemPrompt = buildSystemPrompt()
        Task {
            do {
                try await llm.streamAnswer(system: systemPrompt, history: currentHistory) { [weak self] delta in
                    Task { @MainActor in self?.answer += delta }
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in self.answer = "生成失败: \(message)" }
            }
        }
    }
}
