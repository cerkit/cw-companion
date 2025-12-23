//
//  ContentView.swift
//  cerkit CW Companion
//
//  Created by Michael Earls on 12/21/25.
//

import CerkitCWCompanionLogic
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum InputMode {
    case file
    case live
}

struct ContentView: View {
    @StateObject private var audioModel = AudioModel()

    // Receive Tab State
    @State private var inputMode: InputMode = .file
    @State private var selectedWindowID: Int?
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

                // Live / File Switch
                Picker("Input Source", selection: $inputMode) {
                    Text("File").tag(InputMode.file)
                    Text("Live Window").tag(InputMode.live)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                if inputMode == .live {
                    // Windows Picker
                    VStack(alignment: .leading) {
                        HStack {
                            Picker("Select Window", selection: $selectedWindowID) {
                                Text("Select a window...").tag(nil as Int?)
                                ForEach(audioModel.captureManager.availableWindows) { window in
                                    Text(window.name)
                                        .tag(window.id as Int?)
                                }
                            }

                            Button(action: {
                                Task {
                                    await audioModel.captureManager.refreshAvailableContent()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                        }

                        if audioModel.captureManager.permissionError {
                            Text("⚠️ Screen Recording permission required.")
                                .font(.caption)
                                .foregroundColor(.red)
                            Text("Go to System Settings > Privacy & Security > Screen Recording.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if audioModel.captureManager.availableWindows.isEmpty {
                            Text("No windows found. Try refreshing or check permissions.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .onAppear {
                        Task { await audioModel.captureManager.refreshAvailableContent() }
                    }
                }

                // Controls
                HStack {
                    if inputMode == .file {
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
                    } else {
                        // Live Controls
                        if audioModel.isProcessing {  // Re-using isProcessing for "Listening" state
                            Button(action: {
                                Task { await audioModel.stopLiveListening() }
                            }) {
                                Label("Stop Listening", systemImage: "stop.circle.fill")
                                    .foregroundColor(.red)
                            }
                        } else {
                            Button(action: {
                                if let winID = selectedWindowID,
                                    let win = audioModel.captureManager.getRawWindow(id: winID)
                                {
                                    Task { await audioModel.startLiveListening(window: win) }
                                }
                            }) {
                                Label("Start Listening", systemImage: "mic.fill")
                            }
                            .disabled(selectedWindowID == nil)
                        }
                        Spacer()
                    }

                    if audioModel.isProcessing {
                        ProgressView().scaleEffect(0.5)
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

            // MARK: - CLOUD FT8 TAB
            CloudReceiverView()
                .tabItem {
                    Label("Cloud FT8", systemImage: "globe")
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
