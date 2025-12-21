import XCTest

@testable import CerkitCWCompanionLogic  // We will name the library target this

final class MorseDecoderTests: XCTestCase {
    let decoder = MorseDecoder()

    func testBasicDecoding() {
        // SOS: ... --- ...
        // Dot = 0.1s
        // Dash = 0.3s
        let dot = 0.1
        let dash = 0.3
        let gap = 0.1  // Intra-char
        let letterGap = 0.3  // Inter-char
        let wordGap = 0.7  // Word gap

        // Construct "SOS"
        // S: dot gap dot gap dot
        let sSeq: [(Double, Bool)] = [
            (dot, true), (gap, false),
            (dot, true), (gap, false),
            (dot, true),
        ]

        // O: dash gap dash gap dash
        let oSeq: [(Double, Bool)] = [
            (dash, true), (gap, false),
            (dash, true), (gap, false),
            (dash, true),
        ]

        var sequence = sSeq
        sequence.append((letterGap, false))
        sequence.append(contentsOf: oSeq)
        sequence.append((letterGap, false))
        sequence.append(contentsOf: sSeq)

        // WPM: T=1.2/WPM. If Dot=0.1, WPM=12.
        let result = decoder.decode(durations: sequence, wpm: 12.0)
        XCTAssertEqual(result, "SOS")
    }

    func testHelloWorld() {
        // HELLO WORLD
        // .... . .-.. .-.. --- / .-- --- .-. .-.. -..

        // Simplified test with just "HI"
        // .... ..
        let dot = 0.1
        let gap = 0.1
        let letterGap = 0.3

        let hSeq: [(Double, Bool)] = [
            (dot, true), (gap, false),
            (dot, true), (gap, false),
            (dot, true), (gap, false),
            (dot, true),
        ]

        let iSeq: [(Double, Bool)] = [
            (dot, true), (gap, false),
            (dot, true),
        ]

        var sequence = hSeq
        sequence.append((letterGap, false))
        sequence.append(contentsOf: iSeq)

        let result = decoder.decode(durations: sequence, wpm: 12.0)
        XCTAssertEqual(result, "HI")
    }
}
