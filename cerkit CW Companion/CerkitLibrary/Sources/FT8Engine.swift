import Combine
import Foundation
import ft8_lib  // Integrated C Library

public struct FT8Message: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let signal: Int  // dB
    public let frequency: Double  // Hz offset
    public let text: String
    public let grid: String?
}

public class FT8Engine: ObservableObject {
    @Published public var decodedMessages: [FT8Message] = []

    private var audioBuffer: [Int16] = []
    private let sampleRate: Int = 12000
    private let slotTime: Double = 15.0  // FT8 cycle time
    private let samplesPerSlot: Int = 12000 * 15  // ~180,000
    private var isAligned = false

    public init() {}

    public func appendAudio(_ samples: [Int16]) {
        // Time Alignment Logic
        if audioBuffer.isEmpty {
            let now = Date()
            let seconds = Calendar.current.component(.second, from: now)
            // Allow 1 second window to latch onto the start of a slot (00, 15, 30, 45)
            // Note: FT8 slots are 15s. We want to start buffer at :00, :15, :30, :45.
            let remainder = seconds % 15
            if remainder == 0 || remainder == 1 {
                if !isAligned {
                    print("FT8Engine: Aligned with time slot at \(now). Capturing...")
                    isAligned = true
                }
            } else {
                // Not aligned, drop data
                if isAligned {
                    isAligned = false
                }
                return
            }
        }

        audioBuffer.append(contentsOf: samples)

        // Check if we have enough samples for a full cycle
        if audioBuffer.count >= samplesPerSlot {
            // Take the slot's worth of data
            let slotData = Array(audioBuffer.prefix(samplesPerSlot))

            // Remove processed data
            // FT8 slots are aligned to :00, :15, :30, :45.
            // For this simple implementation, we just drain the buffer and unalign to force re-sync
            audioBuffer.removeFirst(samplesPerSlot)

            // Safer to reset alignment for now to re-lock every slot to wall clock.
            audioBuffer.removeAll(keepingCapacity: true)
            isAligned = false

            // Start slot logging
            let now = Date()
            print("FT8Engine: Buffer full. Decoding slot ending at \(now).")

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
        let blockSize = Int(mon.block_size)
        let sampleCount = floatSamples.count

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
        print("FT8Engine: Found \(numCandidates) candidates.")

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
                // Pass dummy offsets to prevent crash if library writes to it
                var offsets = ftx_message_offsets_t()
                ftx_message_decode(&message, nil, &textBuffer, &offsets)

                let text = String(cString: textBuffer)
                let _ =
                    Float(candidate.freq_offset)
                    * (Float(config.sample_rate) / 2.0 / Float(mon.wf.num_bins))
                // This is rough frequency calc.

                let timestamp = Date()  // Now, or approximate slot time

                // Parse Grid Square
                // Regex: 2 A-R, 2 0-9. e.g. "PL02", "FM18"
                // Often at the end of message "CQ K1ABC FN42"
                var extractedGrid: String? = nil
                let gridPattern = "[A-R]{2}[0-9]{2}"

                if let range = text.range(of: gridPattern, options: .regularExpression) {
                    extractedGrid = String(text[range])
                }

                let msg = FT8Message(
                    timestamp: timestamp,
                    signal: Int(candidate.score),  // Score is roughly SNR/quality
                    frequency: Double(status.freq),
                    text: text,
                    grid: extractedGrid
                )
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
