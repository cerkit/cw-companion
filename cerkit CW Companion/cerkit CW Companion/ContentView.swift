//
//  ContentView.swift
//  cerkit CW Companion
//
//  Created by Michael Earls on 12/21/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var audioModel = AudioModel()

    // Receive Tab State
    @State private var isImporterPresented = false

    // Transmit Tab State
    @State private var transmitText: String = ""
    @State private var isExporterPresented = false
    @State private var generatedWAVData: Data?
    @State private var lastExportURL: URL?

    var body: some View {
        TabView {
            // MARK: - RECEIVE TAB
            VStack(spacing: 20) {
                Text("Receive Mode")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)

                // Status Area
                HStack {
                    Text("Status:")
                        .fontWeight(.semibold)
                    Text(audioModel.statusMessage)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Output Area
                VStack(alignment: .leading) {
                    Text("Decoded Message:")
                        .font(.headline)
                        .padding(.bottom, 5)

                    TextEditor(text: .constant(audioModel.decodedText))
                        .font(.system(.body, design: .monospaced))
                        .padding(5)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding()

                // Controls
                HStack {
                    Button(action: {
                        isImporterPresented = true
                    }) {
                        Label("Load Audio (.wav)", systemImage: "waveform.circle")
                    }
                    .disabled(audioModel.isProcessing || audioModel.isPlaying)

                    Spacer()

                    if audioModel.isPlaying {
                        Button(action: {
                            audioModel.stopAudio()
                        }) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button(action: {
                            audioModel.playAudio()
                        }) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .disabled(!audioModel.isReadyToPlay)
                    }

                    if audioModel.isProcessing {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }
                .padding(.bottom)
            }
            .tabItem {
                Label("Receive", systemImage: "antenna.radiowaves.left.and.right")
            }

            // MARK: - TRANSMIT TAB
            VStack(spacing: 20) {
                Text("Transmit Mode")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)

                Text("Enter text to encode (20 WPM @ 600Hz)")
                    .foregroundColor(.secondary)

                TextEditor(text: $transmitText)
                    .font(.system(.body, design: .monospaced))
                    .padding(5)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .padding()

                HStack {
                    Button(action: {
                        // Generate
                        if let data = audioModel.generateAudio(
                            from: transmitText, wpm: 20.0, frequency: 600.0)
                        {
                            generatedWAVData = data
                            isExporterPresented = true
                        }
                    }) {
                        Label("Generate & Save .wav", systemImage: "square.and.arrow.up")
                    }
                    .disabled(transmitText.isEmpty)
                }
                .padding(.bottom)
            }
            .tabItem {
                Label("Transmit", systemImage: "waveform.path.ecg")
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 450)

        // MARK: - File Handling
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType.wav],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile = try result.get().first else { return }
                audioModel.loadAndProcessAudio(url: selectedFile)
            } catch {
                audioModel.statusMessage = "Error selecting file: \(error.localizedDescription)"
            }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: PCMFile(data: generatedWAVData),
            contentType: UTType.wav,
            defaultFilename: "morse_message.wav"
        ) { result in
            // Handle save result if needed
        }
    }
}

// Helper struct for FileExporter
struct PCMFile: FileDocument {
    static var readableContentTypes: [UTType] { [.wav] }

    var data: Data?

    init(data: Data?) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        // We don't read with this
        data = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data ?? Data())
    }
}

#Preview {
    ContentView()
}
