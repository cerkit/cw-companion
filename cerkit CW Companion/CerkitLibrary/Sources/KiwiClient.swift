import Combine
import Foundation

public enum KiwiSDRMessage {
    case audio([Int16])  // 12kHz mono audio samples
    case spectrum([UInt8])  // Waterfall data
}

public class KiwiClient: NSObject, ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var connectionStatus: String = "Disconnected"

    // Publishers for data streams
    public let audioStream = PassthroughSubject<[Int16], Never>()
    public let spectrumStream = PassthroughSubject<[UInt8], Never>()

    private var webSocketTask: URLSessionWebSocketTask?

    // Properties
    public var host: String
    public var port: Int
    private var pingTimer: Timer?
    private var urlSession: URLSession!
    private var sessionID: String = ""
    private var hasRequestedAudio: Bool = false
    private let adpcmDecoder: IMAADPCMDecoder? = IMAADPCMDecoder()

    // Local Audio FFT Processor
    private let spectrogram = AudioSpectrogram(sampleCount: 1024)

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
        super.init()
        self.urlSession = URLSession(
            configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
    }

    public func connect() {
        self.hasRequestedAudio = false
        print("KiwiClient: Connect AUDIO method called via \(host):\(port)")
        // KiwiSDR expects: ws://host:port/{timestamp}/{id}
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let idVal = "cw_comp_" + String(Int.random(in: 100...999))
        self.sessionID = idVal

        let urlString = "ws://\(host):\(port)/ws/kiwi/\(timestamp)/SND"
        print("KiwiClient: Connecting to \(urlString)")

        guard let url = URL(string: urlString) else {
            self.connectionStatus = "Invalid URL"
            return
        }

        self.connectionStatus = "Connecting..."
        self.webSocketTask = urlSession.webSocketTask(with: url)
        self.webSocketTask?.resume()

        self.listen()
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
        connectionStatus = "Disconnected"
        pingTimer?.invalidate()
    }

    private func send(command: String) {
        // print("KiwiClient: Sending -> \(command)")
        // KiwiSDR expects commands terminated by newline, even in WebSocket frames
        let message = URLSessionWebSocketTask.Message.string(command + "\n")
        webSocketTask?.send(message) { error in
            if let error = error {
                print("WebSocket sending error: \(error)")
            }
        }
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("KiwiClient: WebSocket receive error: \(error)")
                self.cleanupConnection()
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleBinaryMessage(data)
                case .string(let text):
                    self.handleTextMessage(text)
                @unknown default:
                    break
                }

                // Continue listening
                if self.isConnected {
                    self.listen()
                }
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        // Handle control messages like "MSG config_param=..."
        if text.hasPrefix("MSG") {
            // print("Kiwi MSG: \(text)")
        }
    }

    private func handleBinaryMessage(_ data: Data) {
        // KiwiSDR binary protocol:
        // First 3 bytes are command: "SND" (audio) or "MSG" (metadata)

        guard data.count > 3 else { return }

        let prefix = String(decoding: data.prefix(3), as: UTF8.self)

        if prefix == "SND" {
            // "SND " (4 bytes) + Seq (4 bytes) + Smeter (2 bytes) + Data
            // Expected Header Size: 10 bytes (including SND+space)

            guard data.count > 10 else {
                print("KiwiClient: SND packet too small (\(data.count) bytes)")
                return
            }

            // Extract Audio Data (Bytes 10...)
            let audioData = data.dropFirst(10)

            var samples: [Int16]
            if let decoder = self.adpcmDecoder {
                // Decode ADPCM
                samples = decoder.decode(audioData)
            } else {
                // Fallback / Unknown format
                samples = []
            }

            // 1. Send Audio to UI/Decoder
            self.audioStream.send(samples)

            // 2. Process for Local Waterfall (FFT)
            // Ideally we accumulate enough samples for FFT size, but AudioSpectrogram handles windowing?
            // Actually AudioSpectrogram expects 'sampleCount' (1024) in the process method normally,
            // or we feed it chunks. Our 'samples' here are small chunks (e.g. 512 or so?).
            // Let's rely on simple processing: If we pass whatever we get, the FFT might be noisy or partial
            // if the chunk is small.
            // For robustness, we might need a circular buffer in KiwiClient or AudioSpectrogram.
            // But let's try direct feed first.
            if let spectrum = self.spectrogram.process(samples: samples) {
                self.spectrumStream.send(spectrum)
            }

        } else if prefix == "MSG" {
            // Metadata / Control
            if let stringContent = String(data: data.dropFirst(4), encoding: .utf8) {
                print("KiwiClient: Received MSG packet: '\(stringContent)'")

                // Handshake Logic: Wait for configuration to load before requesting audio
                if !self.hasRequestedAudio
                    && (stringContent.contains("cfg_loaded")
                        || stringContent.contains("audio_init"))
                {
                    print(
                        "KiwiClient: Configuration loaded / Audio Init detected. Requesting stream start..."
                    )
                    self.send(command: "SET snd=1")
                    self.hasRequestedAudio = true
                }

            } else {
                print("KiwiClient: Received MSG packet (binary, \(data.count) bytes)")
            }
        }
    }
}

extension KiwiClient: URLSessionWebSocketDelegate {
    public func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("KiwiClient: WebSocket DID OPEN! Protocol: \(String(describing: `protocol`))")

        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionStatus = "Connected"
            print("KiwiClient: Starting Minimal Handshake")

            // Send standard WebSocket Ping first to wake up connection
            self.webSocketTask?.sendPing { error in
                if let error = error {
                    print("KiwiClient: Ping failed: \(error)")
                } else {
                    print("KiwiClient: Ping successful")
                }
            }

            self.send(command: "SET auth t=kiwi p=")
            self.send(command: "SET check=0")  // Disable checks? Seen in some logs
            self.send(command: "SET user=\(self.sessionID)")
            self.send(command: "SET ident_user=\(self.sessionID)")
            self.send(command: "SET mod=usb low_cut=100 high_cut=2800 freq=14074.0")
            self.send(command: "SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=0")  // Standard AGC
            self.send(command: "SET compression=1")
            self.send(command: "SET AR OK in=12000 out=44100")  // Standard browser rate (resampled)
            self.send(command: "SET squelch=0")
            self.send(command: "SET override inactivity_timeout=0")
            self.send(command: "SET rx_chan=0")
            self.send(command: "SET gen=0")
            // self.send(command: "SET snd=1") // MOVED: Wait for cfg_loaded
            self.send(command: "SET keepalive")

            // Re-enable keeping alive manually
            self.pingTimer?.invalidate()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
                [weak self] _ in
                guard let self = self, self.isConnected else { return }
                self.send(command: "SET keepalive")
            }
        }
    }

    private func cleanupConnection() {
        self.isConnected = false
        self.connectionStatus = "Disconnected"
        self.pingTimer?.invalidate()
        self.pingTimer = nil
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        if let error = error {
            print("KiwiClient: WebSocket DID COMPLETE WITH ERROR: \(error)")
        } else {
            print("KiwiClient: WebSocket DID COMPLETE (Closed)")
        }
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Disconnected"
        }
    }
}
