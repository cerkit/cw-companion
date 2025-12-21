import Foundation

class MorseEncoder {
    // Inverse Morse Code Dictionary
    private let charToMorse: [Character: String] = [
        "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".",
        "f": "..-.", "g": "--.", "h": "....", "i": "..", "j": ".---",
        "k": "-.-", "l": ".-..", "m": "--", "n": "-.", "o": "---",
        "p": ".--.", "q": "--.-", "r": ".-.", "s": "...", "t": "-",
        "u": "..-", "v": "...-", "w": ".--", "x": "-..-", "y": "-.--",
        "z": "--..",
        "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....",
        "6": "-....", "7": "--...", "8": "---..", "9": "----.", "0": "-----",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "/": "-..-.", "-": "-....-",
        "(": "-.--.", ")": "-.--.-",
    ]

    // Timing Units (WPM dependent, calculated on the fly or fixed here)
    // Dot = 1 unit
    // Dash = 3 units
    // Intra-char space = 1 unit
    // Inter-char space = 3 units (Wait period after a character)
    // Word space = 7 units

    /// Encodes text into a sequence of (Duration, IsOn) tuples.
    /// - Parameters:
    ///   - text: The text to encode.
    ///   - wpm: Words Per Minute (default 20).
    /// - Returns: An array of audio events (duration in seconds, signalOn).
    func encode(text: String, wpm: Double = 20.0) -> [(Double, Bool)] {
        let unitTime = 1.2 / wpm
        var events: [(Double, Bool)] = []

        let normalizedText = text.lowercased()

        for (index, char) in normalizedText.enumerated() {
            if char == " " {
                // Word space (7 units)
                // Note: We already added inter-char space (3 units) after prev char.
                // We need to add enough silence to make it 7.
                // Previous char ended with 3 units of silence?
                // Actually, simpler logic:
                // Inter-char space is added AFTER each char.
                // Word space replaces inter-char space or adds to it?
                // Standard: Space between words is 7 units.
                // Let's rely on looking ahead or handling spaces explicitly.

                // If we treat space as a character that produces 7 units of silence,
                // but we must be careful not to double up with inter-char silence.

                // Better approach:
                // If space: add (unitTime * 4, false).
                // Why 4? Because we always append 3 units of silence after a valid char.
                // Total = 3 + 4 = 7.
                events.append((unitTime * 4, false))
            } else if let code = charToMorse[char] {
                // Encode dots and dashes
                for symbol in code {
                    if symbol == "." {
                        events.append((unitTime * 1.0, true))  // Dot
                    } else {
                        events.append((unitTime * 3.0, true))  // Dash
                    }
                    // Intra-char space (1 unit) after every symbol
                    events.append((unitTime * 1.0, false))
                }

                // Correct the last intra-char space (1 unit) to be inter-char space (3 units)
                // We appended (1, false) at the end of the loop.
                // We want that last silence to be 3 units total.
                // So we add 2 more units of silence.
                if !events.isEmpty {
                    events.append((unitTime * 2.0, false))
                }
            }
        }

        // Final cleanup: The loop logic adds 3 units of silence after every char.
        // If the text ends with a char, we have 3 units trailing silence. This is fine.

        return events
    }
}
