import AVFoundation
import Foundation

class AudioGenerator {

    /// Generates a WAV file data from Morse events.
    /// - Parameters:
    ///   - events: Sequence of (Duration, IsOn).
    ///   - frequency: Sine wave frequency (default 600Hz).
    ///   - sampleRate: Audio sample rate (default 44100).
    /// - Returns: Data containing the full WAV file, or throws.
    func generateWAV(
        from events: [(Double, Bool)], frequency: Double = 600.0, sampleRate: Double = 44100.0
    ) -> Data? {

        // 1. Calculate total frames
        let totalDuration = events.reduce(0) { $0 + $1.0 }
        let totalFrames = Int(totalDuration * sampleRate)

        // 2. Setup Audio Buffer
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1,
                interleaved: false)
        else { return nil }
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(totalFrames)
        guard let channelData = buffer.int16ChannelData else { return nil }
        let samples = channelData[0]

        // 3. Generate Samples
        var currentFrame = 0
        let envelopeDuration = 0.005  // 5ms attack/release
        let envelopeFrames = Int(envelopeDuration * sampleRate)

        for (duration, isOn) in events {
            let eventFrames = Int(duration * sampleRate)

            if isOn {
                for i in 0..<eventFrames {
                    // Time in local beep
                    let t = Double(i) / sampleRate

                    // Sine Wave
                    let rawSample = sin(
                        2.0 * .pi * frequency * Double(currentFrame + i) / sampleRate)

                    // Envelope (Attack / Release / Sustain)
                    var amplitude: Double = 1.0

                    if i < envelopeFrames {
                        // Attack
                        amplitude = Double(i) / Double(envelopeFrames)
                    } else if i > (eventFrames - envelopeFrames) {
                        // Release
                        let framesLeft = eventFrames - i
                        amplitude = Double(framesLeft) / Double(envelopeFrames)
                    }

                    // Convert to Int16
                    let sampleValue = Int16(rawSample * amplitude * 32000.0)  // slightly under max 32767 for headroom
                    samples[currentFrame + i] = sampleValue
                }
            } else {
                // Silence
                for i in 0..<eventFrames {
                    samples[currentFrame + i] = 0
                }
            }

            currentFrame += eventFrames
        }

        // 4. Convert Buffer to WAV Data
        return bufferToWAVData(buffer: buffer)
    }

    private func bufferToWAVData(buffer: AVAudioPCMBuffer) -> Data {
        let channelCount = 1
        let channels = channelCount
        let bitsPerSample = 16
        let sampleRate = Int(buffer.format.sampleRate)
        let dataSize = Int(buffer.frameLength) * channels * bitsPerSample / 8

        var header = Data()

        // RIFF chunk
        header.append("RIFF".data(using: .ascii)!)
        header.append(UInt32(36 + dataSize).littleEndianData)  // File size - 8
        header.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        header.append("fmt ".data(using: .ascii)!)
        header.append(UInt32(16).littleEndianData)  // Chunk size
        header.append(UInt16(1).littleEndianData)  // Audio format (1 = PCM)
        header.append(UInt16(channels).littleEndianData)
        header.append(UInt32(sampleRate).littleEndianData)
        header.append(UInt32(sampleRate * channels * bitsPerSample / 8).littleEndianData)  // Byte rate
        header.append(UInt16(channels * bitsPerSample / 8).littleEndianData)  // Block align
        header.append(UInt16(bitsPerSample).littleEndianData)

        // data chunk
        header.append("data".data(using: .ascii)!)
        header.append(UInt32(dataSize).littleEndianData)

        var wavData = header

        let ptr = buffer.int16ChannelData![0]
        let dataBuffer = UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength))
        wavData.append(Data(buffer: dataBuffer))

        return wavData
    }
}

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
