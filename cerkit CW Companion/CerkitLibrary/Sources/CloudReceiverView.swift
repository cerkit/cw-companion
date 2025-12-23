import Combine
import SwiftUI

public struct CloudReceiverView: View {
    @StateObject private var kiwiClient = KiwiClient(host: "kphsdr.com", port: 8073)  // Default KPH
    @StateObject private var ft8Engine = FT8Engine()
    @State private var cancellables = Set<AnyCancellable>()

    public init() {
        print("CloudReceiverView: Initialized")
    }

    // Curated list of reliable public receivers
    // Note: These are example public SDRs. Availability may vary.
    let receivers = [
        ("KPH San Francisco", "kphsdr.com", 8073),
        ("K3FEF Pennsylvania", "kiwisdr.k3fef.com", 8073),  // Fixed Hostname
        ("W2SDR New Jersey", "kiwi.w2sdr.com", 8073),
        ("NO1D Maine", "sdr.no1d.com", 8073),
    ]

    @State private var selectedReceiverIndex = 0

    public var body: some View {
        VStack {
            // Header / Controls
            HStack {
                Picker("Receiver", selection: $selectedReceiverIndex) {
                    ForEach(0..<receivers.count, id: \.self) { index in
                        Text(receivers[index].0).tag(index)
                    }
                }
                .frame(width: 250)  // Widened for longer names
                .onChange(of: selectedReceiverIndex) { newIndex in
                    if kiwiClient.isConnected {
                        kiwiClient.disconnect()
                        // Auto-reconnect or wait for user?
                        // Let's wait for user to click Connect again to be safe
                    }
                }

                Button(kiwiClient.isConnected ? "Disconnect" : "Connect") {
                    print("CloudReceiverView: 'Connect/Disconnect' button pressed")
                    if kiwiClient.isConnected {
                        kiwiClient.disconnect()
                    } else {
                        // Update client host/port based on selection
                        let rec = receivers[selectedReceiverIndex]
                        print(
                            "CloudReceiverView: Requesting connection to \(rec.0) (\(rec.1):\(rec.2))"
                        )

                        // Update the client target
                        kiwiClient.host = rec.1
                        kiwiClient.port = rec.2

                        kiwiClient.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(kiwiClient.isConnected ? .red : .green)

                Text(kiwiClient.connectionStatus)
                    .foregroundColor(.secondary)
                    .font(.caption)

                Spacer()

                Button("Clear") {
                    ft8Engine.decodedMessages.removeAll()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Decoded Traffic List
            List {
                ForEach(ft8Engine.decodedMessages) { msg in
                    HStack(alignment: .top) {
                        Text(msg.timestamp, style: .time)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Text("\(msg.signal) dB")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)
                            .foregroundColor(msg.signal > -10 ? .green : .orange)

                        Text(String(format: "%.1f Hz", msg.frequency))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 80, alignment: .trailing)
                            .foregroundColor(.blue)

                        Text(msg.text)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)

            // Status Bar
            HStack {
                Text("FT8 Decoder Active")
                Spacer()
                Text("Target: 14.074 MHz (20m)")
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            // Wire Audio Stream
            kiwiClient.audioStream
                .receive(on: DispatchQueue.main)  // Or background queue for performance
                .sink { samples in
                    ft8Engine.appendAudio(samples)
                }
                .store(in: &cancellables)
        }
        .onDisappear {
            kiwiClient.disconnect()
        }
    }
}
