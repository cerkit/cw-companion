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
        "-.--.": "(", "-.--.-": ")"
    ]
    
    // Configurable WPM parameters (approximations)
    // Standard Morse: Dot = 1 unit, Dash = 3 units
    // Intra-char space = 1 unit, Inter-char space = 3 units, Word space = 7 units
    
    /// Decodes a sequence of on/off durations into text.
    /// - Parameters:
    ///   - onOffPairs: An array of tuples/structs (duration, isOn).
    ///   - wpm: Estimated Words Per Minute to calibrate timing thresholds.
    func decode(durations: [(Double, Bool)], wpm: Double = 20.0) -> String {
        // Calculate timing unit (dot length) in seconds based on WPM
        // Standard: T = 1.2 / WPM
        let unitTime = 1.2 / wpm
        
        let dotLimit = unitTime * 1.5 // Cutoff between dot and dash
        // let dashLimit = unitTime * 4.0 // (Not strictly needed if > dotLimit is dash)
        
        let symbolSpaceLimit = unitTime * 2.0 // Cutoff between intra-char and inter-char
        let wordSpaceLimit = unitTime * 5.0 // Cutoff between char space and word space
        
        var currentSymbol = ""
        var fullMessage = ""
        
        for (duration, isOn) in durations {
            if isOn {
                // Signal ON: Determine Dot or Dash
                if duration < dotLimit {
                    currentSymbol += "."
                } else {
                    currentSymbol += "-"
                }
            } else {
                // Signal OFF: Determine Space type
                if duration > wordSpaceLimit {
                    // Word boundary
                    if let char = morseCodeMap[currentSymbol] {
                        fullMessage += char
                    }
                    if !fullMessage.isEmpty && !fullMessage.hasSuffix(" ") {
                         fullMessage += " "
                    }
                    currentSymbol = ""
                } else if duration > symbolSpaceLimit {
                    // Character boundary
                    if let char = morseCodeMap[currentSymbol] {
                        fullMessage += char
                    }
                    currentSymbol = ""
                } else {
                    // Intra-character space (between dots/dashes of same letter)
                    // Do nothing, just waiting for next beep
                }
            }
        }
        
        // Catch trailing character
        if !currentSymbol.isEmpty, let char = morseCodeMap[currentSymbol] {
            fullMessage += char
        }
        
        return fullMessage
    }
}
