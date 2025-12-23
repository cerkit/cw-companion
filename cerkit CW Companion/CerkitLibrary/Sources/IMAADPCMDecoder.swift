import Foundation

public class IMAADPCMDecoder {
    private var predictedValue: Int32 = 0
    private var stepIndex: Int = 0

    // IMA ADPCM Step Size Table
    private let stepSizeTable: [Int32] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
        19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
        130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
        2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
        5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
        15291, 16822, 18506, 20358, 22395, 24633, 27096, 29805, 32785, 36062,
    ]

    // IMA ADPCM Index Table
    private let indexTable: [Int] = [
        -1, -1, -1, -1, 2, 4, 6, 8,
        -1, -1, -1, -1, 2, 4, 6, 8,
    ]

    public init() {}

    public func decode(_ data: Data) -> [Int16] {
        var samples: [Int16] = []
        samples.reserveCapacity(data.count * 2)

        for byte in data {
            // Low nibble
            let lowNibble = Int32(byte & 0x0F)
            samples.append(decodeNibble(lowNibble))

            // High nibble
            let highNibble = Int32((byte >> 4) & 0x0F)
            samples.append(decodeNibble(highNibble))
        }

        return samples
    }

    private func decodeNibble(_ nibble: Int32) -> Int16 {
        var step = stepSizeTable[stepIndex]
        var diff = step >> 3

        if (nibble & 4) != 0 { diff += step }
        if (nibble & 2) != 0 { diff += (step >> 1) }
        if (nibble & 1) != 0 { diff += (step >> 2) }

        if (nibble & 8) != 0 {
            predictedValue -= diff
        } else {
            predictedValue += diff
        }

        // Clamp output
        if predictedValue > 32767 {
            predictedValue = 32767
        } else if predictedValue < -32768 {
            predictedValue = -32768
        }

        // Update step index
        stepIndex += indexTable[Int(nibble)]
        if stepIndex < 0 { stepIndex = 0 } else if stepIndex > 88 { stepIndex = 88 }

        return Int16(predictedValue)
    }

    public func reset() {
        predictedValue = 0
        stepIndex = 0
    }
}
