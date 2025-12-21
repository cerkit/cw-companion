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
    @State private var isImporterPresented = false

    var body: some View {
        VStack(spacing: 20) {
            Text("cerkit CW Companion")
                .font(.largeTitle)
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
                    Label("Load Audio File (.wav)", systemImage: "waveform.circle")
                }
                .disabled(audioModel.isProcessing)

                if audioModel.isProcessing {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
            .padding(.bottom)
        }
        .frame(minWidth: 500, minHeight: 400)
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
    }
}

#Preview {
    ContentView()
}
