import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit

// Simple Biquad Filter implementation
class BiquadFilter {
    // Coefficients
    private var c_b0: Double = 0.0
    private var c_b1: Double = 0.0
    private var c_b2: Double = 0.0
    private var c_a1: Double = 0.0
    private var c_a2: Double = 0.0

    // State history
    private var x1: Double = 0.0  // x[n-1]
    private var x2: Double = 0.0  // x[n-2]
    private var y1: Double = 0.0  // y[n-1]
    private var y2: Double = 0.0  // y[n-2]

    func configure(frequency: Double, sampleRate: Double, q: Double) {
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let tSin = sin(w0)
        let tCos = cos(w0)
        let alpha = tSin / (2.0 * q)

        let b0 = alpha
        let b1 = 0.0
        let b2 = -alpha
        let a0 = 1.0 + alpha
        let a1 = -2.0 * tCos
        let a2 = 1.0 - alpha

        c_b0 = b0 / a0
        c_b1 = b1 / a0
        c_b2 = b2 / a0
        c_a1 = a1 / a0
        c_a2 = a2 / a0
    }

    func processSample(_ sample: Float) -> Float {
        let x = Double(sample)
        // y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
        let y = c_b0 * x + c_b1 * x1 + c_b2 * x2 - c_a1 * y1 - c_a2 * y2

        // Shift history
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y

        return Float(y)
    }
}

public class AudioModel: ObservableObject {
    @Published public var decodedText: String = ""
    @Published public var isProcessing: Bool = false
    @Published public var isPlaying: Bool = false
    @Published public var isReadyToPlay: Bool = false
    @Published public var statusMessage: String = "Ready to load audio."

    // Playback
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: AnyCancellable?

    // Data
    private let decoder = MorseDecoder()
    private var timedDecodedEvents: [(String, TimeInterval)] = []
    private var nextEventIndex = 0

    // Transmission
    private let encoder = MorseEncoder()
    private let generator = AudioGenerator()

    // Live Capture
    public let captureManager = AudioCaptureManager()
    private let streamingDecoder = StreamingMorseDecoder()

    // Filter
    private let bandpassFilter = BiquadFilter()
    private var filterConfigured = false

    // Live Processing State
    private var isLiveListening = false
    private var liveStartTime: AVAudioTime?
    // Envelope State for Live Streaming
    private var liveEnvelope: Float = 0.0
    private var liveIsSignalOn: Bool = false
    private var liveStateDurationFrames: Int = 0

    public init() {
        captureManager.setAudioCallback { [weak self] buffer in
            self?.processLiveBuffer(buffer)
        }

        // Propagate changes from nested ObservableObject
        captureManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    public func startLiveListening(window: SCWindow) async {
        self.stopAudio()
        self.decodedText = ""
        self.statusMessage =
            "Listening to \(window.owningApplication?.applicationName ?? "Window")..."
        DispatchQueue.main.async {
            self.isLiveListening = true
            self.isProcessing = true
        }

        // Reset decoder state
        streamingDecoder.setWPM(20.0)  // Or dynamic?
        liveEnvelope = 0.0
        liveIsSignalOn = false
        liveStateDurationFrames = 0
        filterConfigured = false  // Re-configure filter for new stream

        do {
            try await captureManager.startStream(window: window)
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Capture failed: \(error.localizedDescription)"
                self.isLiveListening = false
                self.isProcessing = false
            }
        }
    }

    public func stopLiveListening() async {
        await captureManager.stopStream()
        DispatchQueue.main.async {
            self.isLiveListening = false
            self.isProcessing = false
            self.statusMessage = "Live listening stopped."
        }
    }

    private func processLiveBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isLiveListening else { return }
        guard let floatChannelData = buffer.floatChannelData else { return }

        // Similar logic to extractDurations but stateful across buffers
        let frameCount = Int(buffer.frameLength)
        let samples = floatChannelData[0]
        let sampleRate = buffer.format.sampleRate

        // Configure Filter if needed
        if !filterConfigured {
            // Target 600Hz, Q=5.0 for a decent passband
            bandpassFilter.configure(frequency: 600.0, sampleRate: sampleRate, q: 5.0)
            filterConfigured = true
        }

        let threshold: Float = 0.01  // Lowered for sensitivity
        let decay = Float(exp(-1.0 / (sampleRate * 0.005)))

        var newText = ""

        // Lock for thread safety if needed, but we are just appending text
        // Note: Audio callback is on global queue.

        for i in 0..<frameCount {
            let rawSample = samples[i]
            let filteredSample = bandpassFilter.processSample(rawSample)

            let absVal = abs(filteredSample)

            // Envelope
            if absVal > liveEnvelope {
                liveEnvelope = absVal
            } else {
                liveEnvelope *= decay
            }

            let nowOn = liveEnvelope > threshold

            if nowOn == liveIsSignalOn {
                liveStateDurationFrames += 1
            } else {
                // State Changed!
                // Calculate duration of PREVIOUS state
                let durationSecs = Double(liveStateDurationFrames) / sampleRate

                // Filter glitches
                if durationSecs > 0.005 {
                    // Valid previous state
                    if let char = streamingDecoder.processEvent(
                        duration: durationSecs, isOn: liveIsSignalOn)
                    {
                        newText += char
                    }

                    // Start new state
                    liveIsSignalOn = nowOn
                    liveStateDurationFrames = 0
                } else {
                    // Glitch: Ignore transition.
                    liveStateDurationFrames += 1
                }
            }
        }

        // Update UI periodically, not every sample
        if !newText.isEmpty {
            DispatchQueue.main.async {
                self.decodedText += newText
            }
        }

        // Check timeout
        if !liveIsSignalOn {
            let currentSilence = Double(liveStateDurationFrames) / sampleRate
            if let timeoutChar = streamingDecoder.checkTimeout(silenceDuration: currentSilence) {
                DispatchQueue.main.async {
                    self.decodedText += timeoutChar
                }
            }
        }
    }

    public func loadAndProcessAudio(url: URL) {
        self.isProcessing = true
        self.isReadyToPlay = false
        self.statusMessage = "Loading audio..."
        self.decodedText = ""  // Clear previous text
        self.stopAudio()  // Stop any current playback

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Access scope
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                // 1. Prepare Player
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()

                // 2. Read Buffer for Processing
                let file = try AVAudioFile(forReading: url)
                guard
                    let format = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate,
                        channels: 1, interleaved: false),
                    let buffer = AVAudioPCMBuffer(
                        pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
                else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Failed to create buffer."
                        self.isProcessing = false
                    }
                    return
                }
                try file.read(into: buffer)

                DispatchQueue.main.async { self.statusMessage = "Analyzing signal..." }

                // 3. Process
                let durations = self.extractDurations(from: buffer)
                let estimatedWpm = self.estimateWPM(durations: durations)
                let timedEvents = self.decoder.decodeWithTimestamps(
                    durations: durations, wpm: estimatedWpm)

                DispatchQueue.main.async {
                    self.audioPlayer = player
                    self.timedDecodedEvents = timedEvents
                    self.statusMessage = "Ready. (Est. \(Int(estimatedWpm)) WPM)"
                    self.isProcessing = false
                    self.isReadyToPlay = true
                }

            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Error: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    public func generateAudio(from text: String, wpm: Double = 20.0, frequency: Double = 600.0)
        -> Data?
    {
        let events = encoder.encode(text: text, wpm: wpm)
        return generator.generateWAV(from: events, frequency: frequency)
    }

    public func playAudio() {
        guard let player = audioPlayer, !player.isPlaying else { return }

        // Reset text state if starting from beginning
        if player.currentTime < 0.1 || player.currentTime >= player.duration - 0.1 {
            player.currentTime = 0
            decodedText = ""
            nextEventIndex = 0
        }

        player.play()
        isPlaying = true
        statusMessage = "Playing..."

        // Start Timer
        playbackTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStreamingText()
            }
    }

    public func stopAudio() {
        audioPlayer?.stop()
        isPlaying = false
        playbackTimer?.cancel()
        playbackTimer = nil
        statusMessage = "Stopped."
    }

    private func updateStreamingText() {
        guard let player = audioPlayer, player.isPlaying else {
            // Player finished naturally?
            if isPlaying {
                stopAudio()
                statusMessage = "Playback finished."
            }
            return
        }

        let currentTime = player.currentTime

        // Append all events that have happened up to now
        while nextEventIndex < timedDecodedEvents.count {
            let (text, timestamp) = timedDecodedEvents[nextEventIndex]
            if timestamp <= currentTime {
                decodedText += text
                nextEventIndex += 1
            } else {
                break
            }
        }
    }

    /// Converts raw audio samples into a sequence of (Duration, IsOn) tuples.
    private func extractDurations(from buffer: AVAudioPCMBuffer) -> [(Double, Bool)] {
        guard let floatChannelData = buffer.floatChannelData else { return [] }

        let frameCount = Int(buffer.frameLength)
        let samples = floatChannelData[0]
        let sampleRate = buffer.format.sampleRate

        // Envelope follower parameters
        var envelope: Float = 0.0
        let threshold: Float = 0.05

        // Decay factor per sample: envelope *= (1 - release)
        // timeConstant ~ 0.005s => decay = exp(-1.0 / (sampleRate * 0.005))
        let decay = Float(exp(-1.0 / (sampleRate * 0.005)))

        var isSignalOn = false
        var currentStartFrame = 0
        var events: [(Double, Bool)] = []

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
                let durationFrames = i - currentStartFrame
                let durationSeconds = Double(durationFrames) / sampleRate

                // Filter out extremely short glitches (< 5ms)
                if durationSeconds > 0.005 {
                    events.append((durationSeconds, isSignalOn))
                    isSignalOn = nowOn
                    currentStartFrame = i
                }
            }
        }

        // Final event
        let finalDuration = Double(frameCount - currentStartFrame) / sampleRate
        events.append((finalDuration, isSignalOn))

        return events
    }

    private func estimateWPM(durations: [(Double, Bool)]) -> Double {
        let onDurations = durations.filter { $0.1 }.map { $0.0 }
        guard !onDurations.isEmpty else { return 20.0 }

        let sorted = onDurations.sorted()
        let dotProxy = sorted[Int(Double(sorted.count) * 0.25)]

        let wpm = 1.2 / dotProxy
        return min(max(wpm, 5.0), 60.0)
    }
}
