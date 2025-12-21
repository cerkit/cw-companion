# CW Companion

CW Companion is a macOS application designed for Morse Code (CW) enthusiasts. It provides tools for both receiving (decoding) and transmitting (encoding) Morse code, featuring real-time system audio capture and advanced signal processing.

## Key Features

### 1. Morse Code Decoder (Receive)
*   **Live Audio Capture**: Utilizes **ScreenCaptureKit** to capture high-quality audio directly from specific active windows on your Mac. This allows you to decode CW from SDR software, web-based radios, or videos without using a microphone.
*   **Signal Processing Pipeline**:
    *   **Bandpass Filter**: Implements a custom **Digital Biquad Filter** centered at **600Hz** (Q=5.0). This pre-processing step attenuates background noise and isolates the CW signal for cleaner detection.
    *   **Envelope Follower**: Converts the filtered AC audio signal into a DC amplitude envelope with fast attack and calculated decay, enabling robust signal detection even with varying amplitudes.
    *   **Adaptive Thresholding**: Dynamically detects Signal ON/OFF states based on audio levels.
*   **Algorithmic Decoding**:
    *   Uses a time-based state machine to interpret signal duration.
    *   Automatically distinguishes between Dots, Dashes, Intra-character gaps, Inter-character gaps, and Word spaces.
    *   **Adaptive WPM**: Capable of estimating the sender's speed (Words Per Minute) to adjust timing tolerances.
*   **File Input**: Supports loading and decoding existing `.wav` audio files.

### 2. Morse Code Encoder (Transmit)
*   **Text-to-CW**: Converts typed text into standard International Morse Code timing.
*   **Audio Synthesis**: Generates clean 600Hz sine wave audio.
*   **Envelope Shaping**: Applies a 5ms linear rise and fall time (ramp) to every key-down event. This essentially eliminates "key clicks" (spectral splatter) common in simple square-wave generators.
*   **WAV Export**: Saves the generated Morse code audio to a broadcast-quality `.wav` file for sharing or practice.

## Technical Architecture

*   **Platform**: macOS 12.3+ (Required for `ScreenCaptureKit`).
*   **Language**: Swift 5.
*   **UI Framework**: SwiftUI.
*   **Audio Engine**: `AVFoundation` for low-level audio buffer manipulation/playback and `ScreenCaptureKit` for system audio streams.
*   **Concurrency**:
    *   Uses Swift structured concurrency (`async`/`await`) for managing live stream sessions.
    *   Utilizes `DispatchQueue` and `Combine` pipelines to offload heavy DSP (Digital Signal Processing) tasks from the main UI thread.

## Usage

### Receive Mode
1.  Go to the **Receive** tab.
2.  Switch the input mode to **Live Window**.
3.  Select the target application (e.g., your SDR program or web browser) from the list.
4.  The app will immediately start capturing audio, filtering for 600Hz tones, and streaming decoded text to the window.

### Transmit Mode
1.  Go to the **Transmit** tab.
2.  Enter your text message.
3.  Adjust the WPM (Speed) and Frequency if desired.
4.  Press **Play** to preview or **Save WAV** to export the audio file.

## Development

*   **AudioProcessing.swift**: core logic for DSP, including the `BiquadFilter`, `AudioModel` state management, and the `processLiveBuffer` loop.
*   **AudioCaptureManager.swift**: Handles the `ScreenCaptureKit` stream lifecycle and permission handling.
*   **MorseDecoder.swift**: Logic for translating time intervals into characters.
