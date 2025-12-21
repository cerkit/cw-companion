import AVFoundation
import Combine
import Foundation

class AudioModel: ObservableObject {
    @Published var decodedText: String = ""
    @Published var isProcessing: Bool = false
    @Published var statusMessage: String = "Ready to load audio."

    private let decoder = MorseDecoder()

    func loadAndProcessAudio(url: URL) {
        self.isProcessing = true
        self.statusMessage = "Loading audio..."
        self.decodedText = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Start accessing the security-scoped resource on the background thread
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let file = try AVAudioFile(forReading: url)
                guard
                    let format = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate,
                        channels: 1, interleaved: false),
                    let buffer = AVAudioPCMBuffer(
                        pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
                else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Failed to create audio buffer."
                        self.isProcessing = false
                    }
                    return
                }

                try file.read(into: buffer)

                DispatchQueue.main.async {
                    self.statusMessage = "Analyzing signal..."
                }

                let durations = self.extractDurations(from: buffer)

                // Estimate WPM or use default?
                // For Phase 1, we can try to auto-detect or just hardcode a reasonable default.
                // A smart auto-solver would look for the shortest "on" pulse and call that 1 unit.
                let estimatedWpm = self.estimateWPM(durations: durations)

                let text = self.decoder.decode(durations: durations, wpm: estimatedWpm)

                DispatchQueue.main.async {
                    self.decodedText = text
                    self.statusMessage = "Decoding complete (Est. \(Int(estimatedWpm)) WPM)."
                    self.isProcessing = false
                }

            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Error loading file: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    /// Converts raw audio samples into a sequence of (Duration, IsOn) tuples.
    private func extractDurations(from buffer: AVAudioPCMBuffer) -> [(Double, Bool)] {
        guard let floatChannelData = buffer.floatChannelData else { return [] }

        let frameCount = Int(buffer.frameLength)
        let samples = floatChannelData[0]  // Mono assumption

        // 1. Calculate Envelope / Energy
        // Use a simple envelope follower to smooth out zero-crossings
        var isSignalOn = false
        var currentStartFrame = 0
        var events: [(Double, Bool)] = []

        let sampleRate = buffer.format.sampleRate
        let threshold: Float = 0.05

        // Envelope follower parameters
        var envelope: Float = 0.0
        let attack: Float = 1.0  // Instant attack
        let release: Float = 0.005  // Slow release to bridge gaps (e.g. 50-60ms dots, so bridge <5ms gaps)
        // Decay factor per sample: envelope *= (1 - release)
        // If sampleRate is 44100, we want to stay high for ~5ms.
        // 5ms = 220 samples.
        // Let's use a standard coefficient approach.
        // decay = exp(-1.0 / (sampleRate * timeConstant))
        // timeConstant ~ 0.005s.
        let decay = Float(exp(-1.0 / (sampleRate * 0.005)))

        for i in 0..<frameCount {
            let absVal = abs(samples[i])

            // Envelope follower logic
            if absVal > envelope {
                envelope = absVal  // Instant attack
            } else {
                envelope *= decay
            }

            let nowOn = envelope > threshold

            if nowOn != isSignalOn {
                // State changed
                let durationFrames = i - currentStartFrame
                let durationSeconds = Double(durationFrames) / sampleRate

                // Filter out extremely short glitches
                if durationSeconds > 0.005 {
                    events.append((durationSeconds, isSignalOn))
                    isSignalOn = nowOn
                    currentStartFrame = i
                } else {
                    // Glitch ignored - keep previous state
                }
            }
        }

        // Final event
        let finalDuration = Double(frameCount - currentStartFrame) / sampleRate
        events.append((finalDuration, isSignalOn))

        return events
    }

    private func estimateWPM(durations: [(Double, Bool)]) -> Double {
        // Find the median 'short' on-pulse to determine 'dot' length.

        let onDurations = durations.filter { $0.1 }.map { $0.0 }
        guard !onDurations.isEmpty else { return 20.0 }

        // Simple clustering: separating dots and dashes.
        // Assume shortest cluster is dots.
        // Heuristic: Sort, take the 25th percentile as a likely 'dot' representative.
        let sorted = onDurations.sorted()
        let dotProxy = sorted[Int(Double(sorted.count) * 0.25)]

        // Paris standard: T = 1.2 / WPM  => WPM = 1.2 / T
        let wpm = 1.2 / dotProxy

        // Clamp to sane values
        return min(max(wpm, 5.0), 60.0)
    }
}
