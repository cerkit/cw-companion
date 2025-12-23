import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit

public struct SimpleWindow: Identifiable, Hashable {
    public let id: Int
    public let name: String

    public init(window: SCWindow) {
        self.id = Int(window.windowID)
        let app = window.owningApplication?.applicationName ?? "Unknown App"
        let title = window.title ?? "Untitled"
        self.name = "\(app): \(title)"
    }
}

public class AudioCaptureManager: NSObject, ObservableObject {
    @Published public var availableWindows: [SimpleWindow] = []
    @Published public var availableDisplays: [SCDisplay] = []
    @Published public var isRecording: Bool = false
    @Published public var permissionError: Bool = false

    // Internal cache for starting stream
    private var rawWindows: [SCWindow] = []

    private var stream: SCStream?
    private var audioCallback: ((AVAudioPCMBuffer) -> Void)?

    public override init() {
        super.init()
    }

    public func setAudioCallback(_ callback: @escaping (AVAudioPCMBuffer) -> Void) {
        self.audioCallback = callback
    }

    public func refreshAvailableContent() async {
        do {
            // Fetch everything first to debug
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)

            print("DEBUG: Found \(content.windows.count) raw windows.")
            print("DEBUG: Found \(content.displays.count) displays.")

            DispatchQueue.main.async {
                self.availableDisplays = content.displays
                self.rawWindows = content.windows

                // Extremely relaxed filter for debugging
                let filtered = content.windows.filter { window in
                    // Must have an app.
                    let hasApp = window.owningApplication != nil
                    return hasApp
                }
                .sorted {
                    ($0.owningApplication?.applicationName ?? "")
                        < ($1.owningApplication?.applicationName ?? "")
                }

                self.availableWindows = filtered.map { SimpleWindow(window: $0) }

                print("DEBUG: Filtered and mapped to \(self.availableWindows.count) windows.")
            }
        } catch {
            print("Error refreshing content: \(error)")
            DispatchQueue.main.async { self.permissionError = true }
        }
    }

    public func startStream(window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        // config.capturesShadows is deprecated/unavailable or handled differently. Removing.
        config.showsCursor = false

        // We don't really care about video, but we must configure it.
        config.width = 100
        config.height = 100
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps

        // Audio Settings
        config.sampleRate = 44100
        config.channelCount = 1

        stream = SCStream(filter: filter, configuration: config, delegate: nil)

        try stream?.addStreamOutput(
            self, type: .audio, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))

        try await stream?.startCapture()

        DispatchQueue.main.async {
            self.isRecording = true
        }
    }

    public func stopStream() async {
        if let stream = stream {
            try? await stream.stopCapture()
        }
        stream = nil
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    public func getRawWindow(id: Int) -> SCWindow? {
        return rawWindows.first(where: { Int($0.windowID) == id })
    }
}

extension AudioCaptureManager: SCStreamOutput {
    public func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }

        if let audioBuffer = createPCMBuffer(from: sampleBuffer) {
            audioCallback?(audioBuffer)
        }
    }

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let numSamples = CMSampleBufferGetNumSamples(sampleBuffer) as Int?, numSamples > 0
        else { return nil }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)!.pointee

        // Create AVAudioFormat from ASBD
        // Use withUnsafePointer to properly pass the pointer
        guard
            let avFormat = withUnsafePointer(
                to: &asbd,
                { ptr in
                    return AVAudioFormat(streamDescription: ptr)
                })
        else { return nil }

        guard
            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(numSamples))
        else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Copy data...
        let audioBufferList = pcmBuffer.mutableAudioBufferList
        // CMSampleBufferCopyPCMDataIntoAudioBufferList(_:at:frameCount:into:)
        // Note: The newer Swift overlay signature drops the flags and blockBufferOut?
        // Let's rely on standard signature from Apple Docs for recent Swift versions.
        // It seems newer overlays might use `try? sampleBuffer.copyPCMData(...)` or similar?
        // Or strictly: CMSampleBufferCopyPCMDataIntoAudioBufferList(sbuf, offset, frames, bufferList)

        // Let's try the 4-argument version if the user error said 5,6 were extra.
        // wait, the user's error said "Extra arguments at positions #5, #6".
        // This confirms it expects 4 arguments.

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(numSamples),
            into: audioBufferList
        )

        if status == noErr {
            return pcmBuffer
        } else {
            print("Error copying buffer: \(status)")
            return nil
        }
    }
}
