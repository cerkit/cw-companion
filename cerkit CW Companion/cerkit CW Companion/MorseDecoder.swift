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

class StreamingMorseDecoder {
    private let morseCodeMap: [String: String]
    private var wpm: Double
    private var unitTime: Double

    // State
    private var currentSymbol = ""
    private var lastCharacterEmitted = false  // Track if we just finished a char to avoid dupe spaces

    init(wpm: Double = 20.0) {
        // Copy the map from the main decoder for convenience, or static lookup.
        // For now, hardcoding/duplicating or we could make map public static.
        self.morseCodeMap = [
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
        self.wpm = wpm
        self.unitTime = 1.2 / wpm
    }

    func setWPM(_ wpm: Double) {
        self.wpm = wpm
        self.unitTime = 1.2 / wpm
    }

    /// Processes a completed state (beep or silence) and returns any decoded text.
    func processEvent(duration: Double, isOn: Bool) -> String? {
        let dotLimit = unitTime * 1.5
        let symbolSpaceLimit = unitTime * 2.0
        let wordSpaceLimit = unitTime * 5.0

        if isOn {
            // A signal just finished. Was it a dot or a dash?
            if duration < dotLimit {
                currentSymbol += "."
            } else {
                currentSymbol += "-"
            }
            lastCharacterEmitted = false
            return nil

        } else {
            // A silence just finished. What does it mean?
            // If silence was short (intra-char), do nothing.
            // If silence was medium (inter-char), emit currentSymbol.
            // If silence was long (word), emit currentSymbol + space.

            // NOTE: This is called when silence ENDS (next beep started).
            // But we also need to handle "timeout" (silence continues).
            // This method handles the "Next beep just started" case.

            var output = ""

            if duration > wordSpaceLimit {
                // We definitely finished a word.
                // Did we have a pending character?
                if !currentSymbol.isEmpty, let char = morseCodeMap[currentSymbol] {
                    output += char
                }
                currentSymbol = ""
                output += " "
                lastCharacterEmitted = true

            } else if duration > symbolSpaceLimit {
                // Finished a character.
                if !currentSymbol.isEmpty, let char = morseCodeMap[currentSymbol] {
                    output += char
                }
                currentSymbol = ""
                lastCharacterEmitted = true
            }

            return output.isEmpty ? nil : output
        }
    }

    /// Called periodically to check if the CURRENT ongoing silence constitutes a character/word break.
    func checkTimeout(silenceDuration: Double) -> String? {
        // If we are in the middle of a symbol, and silence is long enough, finalize it.
        let symbolSpaceLimit = unitTime * 2.0
        let wordSpaceLimit = unitTime * 5.0

        // If silence > wordSpaceLimit and we haven't emitted the trailing space yet...
        if silenceDuration > wordSpaceLimit {
            var output = ""

            // 1. Flush character if pending
            if !currentSymbol.isEmpty {
                if let char = morseCodeMap[currentSymbol] {
                    output += char
                }
                currentSymbol = ""
            }

            // 2. Emit space if we haven't already (and if we actually outputted something previously)
            // But this function might be called repeatedly. We don't want "       ".
            // We need to track state.
            // Simplification: This returns text ONE TIME when the threshold is crossed.
            // But how do we know if we crossed it just now?
            // Logic handled by caller potentially, OR we statefully track "I am waiting for word space".

            // Re-think: This is tricky to call "repeatedly".
            // Caller should probably call `processEvent` when state *changes*.
            // This function is for "User stopped typing".

            // Let's rely on `currentSymbol` presence.
            if !output.isEmpty {
                output += " "
                return output
            }

            // If we already flushed char, but silence keeps growing into a word space?
            // We need to emit " ".
            // This requires separate tracking. A bit complex for single pass.
            // For now: Only flush pending CHARACTERS. Phase 3 MVP.
            return nil

        } else if silenceDuration > symbolSpaceLimit {
            if !currentSymbol.isEmpty {
                if let char = morseCodeMap[currentSymbol] {
                    currentSymbol = ""
                    return char
                }
            }
        }

        return nil
    }
}
