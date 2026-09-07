import AVFoundation
import CoreMedia

private extension CMSampleBuffer {
    var pcmBuffer: AVAudioPCMBuffer? {
        try? withAudioBufferList { audioBufferList, _ in
            guard let asbd = formatDescription?.audioStreamBasicDescription,
                  let format = AVAudioFormat(standardFormatWithSampleRate: asbd.mSampleRate, channels: asbd.mChannelsPerFrame) else {
                return nil
            }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
}

enum PCMConverter {
    static func toInt16PCM(buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        let channel0 = floatData[0]

        var int16Samples = [Int16](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            let sample = max(-1.0, min(1.0, channel0[i]))
            int16Samples[i] = Int16(sample * Float(Int16.max))
        }
        return int16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func toInt16PCM(sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pcmBuffer = sampleBuffer.pcmBuffer else { return nil }
        return toInt16PCM(buffer: pcmBuffer)
    }
}
