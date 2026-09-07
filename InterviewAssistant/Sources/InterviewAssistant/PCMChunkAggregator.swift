import Foundation

final class PCMChunkAggregator {
    private var buffer = Data()
    private let flushByteCount: Int
    private let onChunk: (Data) -> Void

    init(sampleRate: Int, chunkMilliseconds: Int = 100, onChunk: @escaping (Data) -> Void) {
        let samplesPerChunk = sampleRate * chunkMilliseconds / 1000
        self.flushByteCount = samplesPerChunk * 2 // Int16 = 2 bytes per sample
        self.onChunk = onChunk
    }

    func append(_ data: Data) {
        buffer.append(data)
        while buffer.count >= flushByteCount {
            let chunk = buffer.prefix(flushByteCount)
            onChunk(Data(chunk))
            buffer.removeFirst(flushByteCount)
        }
    }
}
