import AVFoundation

public class StreamAudioPlayer: ObservableObject {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat

    public init() {
        // Standard system format (44.1kHz or 48kHz usually)
        // But input is 12kHz. We should convert or tell engine input is 12kHz.
        // Let's rely on the engine to mix. We will configure the PlayerNode input format as 12kHz.
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 12000, channels: 1, interleaved: false)!

        setupEngine()
    }

    private func setupEngine() {
        let mainMixer = engine.mainMixerNode
        engine.attach(playerNode)

        // Connect player (12k) to mixer (System default, e.g. 48k). Engine handles resampling.
        engine.connect(playerNode, to: mainMixer, format: format)

        do {
            try engine.start()
            playerNode.play()
        } catch {
            print("StreamAudioPlayer: Engine start failed: \(error)")
        }
    }

    public func resizeBuffer(newSampleRate: Double) {
        // Todo: support dynamic handling
    }

    public func ingest(samples: [Int16]) {
        guard engine.isRunning else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        pcmBuffer.frameLength = frameCount

        // Convert Int16 -> Float32 [-1.0, 1.0]
        if let floatChannelData = pcmBuffer.floatChannelData {
            let ptr = floatChannelData[0]
            for i in 0..<Int(frameCount) {
                // Normalize 16-bit signed to float
                ptr[i] = Float(samples[i]) / 32768.0
            }
        }

        playerNode.scheduleBuffer(pcmBuffer)
    }
}
