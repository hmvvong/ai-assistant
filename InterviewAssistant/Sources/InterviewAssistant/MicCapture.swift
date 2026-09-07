import AVFoundation

final class MicCapture {
    private let engine = AVAudioEngine()
    private(set) var bufferCount = 0
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    var sampleRate: Double {
        engine.inputNode.outputFormat(forBus: 0).sampleRate
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.bufferCount += 1
            self?.onBuffer?(buffer)
        }
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
