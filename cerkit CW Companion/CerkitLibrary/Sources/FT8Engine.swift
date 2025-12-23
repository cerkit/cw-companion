import Combine
import Foundation
import ft8_lib  // Integrated C Library

public struct FT8Message: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let signal: Int  // dB
    public let frequency: Double  // Hz offset
    public let text: String
}

public class FT8Engine: ObservableObject {
    @Published public var decodedMessages: [FT8Message] = []

    private var audioBuffer: [Int16] = []
    private let sampleRate: Int32 = 12000
    private let slotTime: Double = 15.0  // FT8 cycle time
    private let samplesPerSlot = 12000 * 15  // ~180,000

    public init() {}

    public func appendAudio(_ samples: [Int16]) {
        audioBuffer.append(contentsOf: samples)

        // Decode continuously or in chunks?
        // FT8 is slotted. We should ideally wait for the buffer to fill (~15s)
        // Check if we have enough samples for a full cycle
        if audioBuffer.count >= samplesPerSlot {
            // Take the slot's worth of data
            let slotData = Array(audioBuffer.prefix(samplesPerSlot))

            // Remove processed data (sliding window? or strict slots?)
            // FT8 slots are aligned to :00, :15, :30, :45.
            // For this simple implementation, we just drain the buffer.
            audioBuffer.removeFirst(samplesPerSlot)

            // Start slot logging
            print("FT8Engine: Buffer full (\(audioBuffer.count) samples). Starting decode of slot.")

            // Decode in background
            DispatchQueue.global(qos: .userInitiated).async {
                self.processSlot(slotData)
            }
        }
    }

    private func processSlot(_ int16Samples: [Int16]) {
        // 1. Convert to Float
        // ft8_lib typically expects normalized floats [-1.0, 1.0]
        let floatSamples = int16Samples.map { Float($0) / 32768.0 }

        // 2. Configure Monitor
        var config = monitor_config_t()
        config.f_min = 100  // standard passband
        config.f_max = 3000
        config.sample_rate = Int32(sampleRate)
        config.time_osr = 2
        config.freq_osr = 2
        config.protocol = FTX_PROTOCOL_FT8

        var mon = monitor_t()
        monitor_init(&mon, &config)

        // 3. Process Audio Frames
        // monitor_process expects blocks. We identify the block size from the initialized monitor.
        // Usually block_size represents the number of new samples to ingest per step (often equal to nfft or hop_size)
        // In kgoba/ft8_lib, it seems monitor_process takes 'block_size' samples.

        let blockSize = Int(mon.block_size)
        let sampleCount = floatSamples.count

        // Ensure we don't read past end
        // Simple processing loop
        var processedCount = 0
        floatSamples.withUnsafeBufferPointer { buffer in
            guard let basePtr = buffer.baseAddress else { return }

            while processedCount + blockSize <= sampleCount {
                let framePtr = basePtr.advanced(by: processedCount)
                monitor_process(&mon, framePtr)
                processedCount += blockSize
            }
        }

        // 4. Find Candidates
        let maxCandidates = 120
        var candidates = [ftx_candidate_t](repeating: ftx_candidate_t(), count: maxCandidates)

        let numCandidates = ftx_find_candidates(&mon.wf, Int32(maxCandidates), &candidates, 10)  // min score 10

        // 5. Decode Candidates
        var newMessages: [FT8Message] = []

        for i in 0..<Int(numCandidates) {
            var candidate = candidates[i]

            var message = ftx_message_t()
            var status = ftx_decode_status_t()

            if ftx_decode_candidate(&mon.wf, &candidate, 50, &message, &status) {
                // Successful Decode!

                // Get Text
                var textBuffer = [CChar](repeating: 0, count: 128)
                // We don't have a hash interface implemented yet, pass nil
                ftx_message_decode(&message, nil, &textBuffer, nil)

                let text = String(cString: textBuffer)
                let _ =
                    Float(candidate.freq_offset)
                    * (Float(config.sample_rate) / 2.0 / Float(mon.wf.num_bins))
                // This is rough frequency calc. monitor.c usually has helper or we reproduce logic:
                // freq = (candidate.freq_offset + candidate.freq_sub / freq_osr) * tone_spacing + f_min
                // Let's use status.freq if defined?
                // decode.h struct has 'float freq' in ftx_decode_status_t!

                let timestamp = Date()  // Now, or approximate slot time

                let msg = FT8Message(
                    timestamp: timestamp,
                    signal: Int(candidate.score),  // Score is roughly SNR/quality
                    frequency: Double(status.freq),
                    text: text)
                newMessages.append(msg)
            }
        }

        monitor_free(&mon)

        // 6. Update UI
        if !newMessages.isEmpty {
            DispatchQueue.main.async {
                self.decodedMessages.append(contentsOf: newMessages)
            }
        }
    }
}
