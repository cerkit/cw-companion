import Combine
import MetalKit
import SwiftUI

public struct MetalWaterfallView: NSViewRepresentable {
    @ObservedObject var kiwiClient: KiwiClient

    public init(kiwiClient: KiwiClient) {
        self.kiwiClient = kiwiClient
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator.renderer
        mtkView.preferredFramesPerSecond = 30
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false

        // Initialize Renderer
        context.coordinator.renderer = WaterfallRenderer(metalView: mtkView)

        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        // Update bindings if needed
    }

    public class Coordinator: NSObject {
        var parent: MetalWaterfallView
        var renderer: WaterfallRenderer?
        var cancellable: AnyCancellable?

        init(_ parent: MetalWaterfallView) {
            self.parent = parent
            super.init()

            // Subscribe to data
            self.cancellable = parent.kiwiClient.spectrumStream
                .receive(on: DispatchQueue.main)  // Metal updates main thread usually safest for texture? Or renderer implementation handles it.
                // Actually replaceRegion is thread safe but MTKView draw is main thread.
                // Let's receive on main to keep it simple.
                .sink { [weak self] data in
                    self?.renderer?.appendSpectrum(data: data)
                }
        }
    }
}
