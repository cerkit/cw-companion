import Foundation

class MorseDecoder {
    // International Morse Code Dictionary
    private let morseCodeMap: [String: String] = [
        ".-": "A", "-...": "B", "-.-.": "C", "-..": "D", ".": "E",
        "..-.": "F", "--.": "G", "....": "H", "..": "I", ".---": "J",
        "-.-": "K", ".-..": "L", "--": "M", "-.": "N", "---": "O",
        ".--.": "P", "--.-": "Q", ".-.": "R", "...": "S", "-": "T",
        "..-": "U", "...-": "V", ".--": "W", "-..-": "X", "-.--": "Y",
        "--..": "Z",
        ".----": "1", "..---": "2", "...--": "3", "....-": "4", ".....": "5",
        "-....": "6", "--...": "7", "---..": "8", "----.": "9", "-----": "0",
        ".-.-.-": ".", "--..--": ",", "..--..": "?", "-..-.": "/", "-....-": "-",
        "-.--.": "(", "-.--.-": ")",
    ]

    // Configurable WPM parameters (approximations)
    // Standard Morse: Dot = 1 unit, Dash = 3 units
    // Intra-char space = 1 unit, Inter-char space = 3 units, Word space = 7 units

    /// Decodes a sequence of on/off durations into text.
    func decode(durations: [(Double, Bool)], wpm: Double = 20.0) -> String {
        return decodeWithTimestamps(durations: durations, wpm: wpm).map { $0.0 }.joined()
    }

    /// Decodes with timestamps for each character.
    /// - Returns: Array of (CharacterString, EndTimeInterval)
    func decodeWithTimestamps(durations: [(Double, Bool)], wpm: Double = 20.0) -> [(
        String, TimeInterval
    )] {
        let unitTime = 1.2 / wpm
        let dotLimit = unitTime * 1.5
        let symbolSpaceLimit = unitTime * 2.0
        let wordSpaceLimit = unitTime * 5.0

        var currentSymbol = ""
        var accumulatedTime: TimeInterval = 0
        var results: [(String, TimeInterval)] = []

        for (duration, isOn) in durations {
            accumulatedTime += duration

            if isOn {
                if duration < dotLimit {
                    currentSymbol += "."
                } else {
                    currentSymbol += "-"
                }
            } else {
                if duration > wordSpaceLimit {
                    // Word boundary (implies character boundary first)
                    if let char = morseCodeMap[currentSymbol] {
                        results.append((char, accumulatedTime))
                    }
                    if !results.isEmpty && results.last?.0 != " " {
                        results.append((" ", accumulatedTime))
                    }
                    currentSymbol = ""
                } else if duration > symbolSpaceLimit {
                    // Character boundary
                    if let char = morseCodeMap[currentSymbol] {
                        results.append((char, accumulatedTime))
                    }
                    currentSymbol = ""
                }
            }
        }

        // Trailing char
        if !currentSymbol.isEmpty, let char = morseCodeMap[currentSymbol] {
            results.append((char, accumulatedTime))
        }

        return results
    }
}
