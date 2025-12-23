import MapKit
import SwiftUI

public struct WorldMapView: View {
    @Binding var messages: [FT8Message]

    // Default to a world view
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 120)
        )
    )

    public init(messages: Binding<[FT8Message]>) {
        self._messages = messages
    }

    public var body: some View {
        Map(position: $position) {
            ForEach(messages) { msg in
                if let grid = msg.grid,
                    let coord = MaidenheadLocator.coordinates(for: grid)
                {
                    Annotation(msg.text, coordinate: coord) {
                        VStack(spacing: 4) {
                            Text(msg.grid ?? "")
                                .font(.caption)
                                .padding(4)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(4)

                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.red)
                                .background(Circle().fill(Color.white))
                        }
                    }
                }
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
    }
}
