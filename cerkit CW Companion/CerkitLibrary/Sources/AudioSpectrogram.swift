import Accelerate
import Foundation

/// Analyzes audio samples and produces frequency domain data (waterfall/spectrum)
public class AudioSpectrogram {
    private var fftSetup: vDSP_DFT_Setup?
    private let fftLength: vDSP_Length
    private let log2n: vDSP_Length
    private let windowSize: Int
    private var window: [Float]

    // Buffers for FFT processing
    private var realParts: [Float]
    private var imagParts: [Float]
    private var inputBuffer: [Float]

    public init(sampleCount: Int = 1024) {
        let log2n = vDSP_Length(log2(Float(sampleCount)))
        self.log2n = log2n
        self.fftLength = vDSP_Length(sampleCount)
        self.windowSize = sampleCount

        self.realParts = [Float](repeating: 0, count: sampleCount / 2)
        self.imagParts = [Float](repeating: 0, count: sampleCount / 2)
        self.inputBuffer = [Float](repeating: 0, count: sampleCount)

        // Log-base-2 FFT Setup
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        self.window = [Float](repeating: 0, count: sampleCount)
        vDSP_hann_window(&window, vDSP_Length(sampleCount), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    public func process(samples: [Int16]) -> [UInt8]? {
        guard samples.count >= windowSize else { return nil }

        // 1. Convert Int16 -> Float
        let suffix = samples.suffix(windowSize)
        var floats = [Float](repeating: 0, count: windowSize)
        suffix.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) {
                vDSP_vflt16(base, 1, &floats, 1, vDSP_Length(windowSize))
            }
        }

        // 2. Apply Window Function
        vDSP_vmul(floats, 1, window, 1, &inputBuffer, 1, vDSP_Length(windowSize))

        // 2b. Normalize to [-1.0, 1.0] roughly (divide by 32768.0)
        // This prevents massive dB values appearing.
        var normalizationFactor: Float = 1.0 / 32768.0
        vDSP_vsmul(inputBuffer, 1, &normalizationFactor, &inputBuffer, 1, vDSP_Length(windowSize))

        var output: [UInt8] = []

        // Wrap pointers for safety
        realParts.withUnsafeMutableBufferPointer { realPtr in
            imagParts.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress,
                    let imagBase = imagPtr.baseAddress
                else { return }

                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)

                // 3. Convert Real Input -> Split Complex (Even/Odd packing for zrip)
                inputBuffer.withUnsafeBufferPointer { inputPtr in
                    if let base = inputPtr.baseAddress {
                        base.withMemoryRebound(to: DSPComplex.self, capacity: windowSize / 2) {
                            typePtr in
                            vDSP_ctoz(typePtr, 2, &splitComplex, 1, vDSP_Length(windowSize / 2))
                        }
                    }
                }

                // 4. Perform Forward FFT
                if let setup = fftSetup {
                    vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                }

                // 5. Compute Magnitudes
                var magnitudes = [Float](repeating: 0, count: windowSize / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(windowSize / 2))

                // 6. Convert to Decibels
                var db = [Float](repeating: 0, count: windowSize / 2)
                var ref: Float = 1.0
                vDSP_vdbcon(magnitudes, 1, &ref, &db, 1, vDSP_Length(windowSize / 2), 1)

                // Normalize to UInt8
                // Recalibrated Range: 0dB to 100dB
                // Accounts for unscaled FFT gain which boosts signals to ~60dB+
                let minDb: Float = 0.0
                let maxDb: Float = 100.0
                let scale = 255.0 / (maxDb - minDb)

                output = [UInt8](repeating: 0, count: windowSize / 2)
                for i in 0..<(windowSize / 2) {
                    let val = db[i]
                    let normalized = (val - minDb) * scale
                    let clamped = max(0, min(255, normalized))
                    output[i] = UInt8(clamped)
                }
            }
        }
        return output
    }
}
