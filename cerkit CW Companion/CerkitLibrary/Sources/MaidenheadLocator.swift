import CoreLocation
import Foundation

/// Converts Maidenhead Grid Locators to Coordinates
public struct MaidenheadLocator {

    /// Converts a grid string (e.g. "JO22", "JO22AB") to standard coordinates.
    /// Returns center of the grid square.
    public static func coordinates(for grid: String) -> CLLocationCoordinate2D? {
        let cleanGrid = grid.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanGrid.count >= 4 else { return nil }

        let chars = Array(cleanGrid)

        // Field (A-R): 20x10 degrees
        guard let fieldLon = value(for: chars[0], base: "A"),
            let fieldLat = value(for: chars[1], base: "A")
        else { return nil }

        // Square (0-9): 2x1 degrees
        guard let squareLon = value(for: chars[2], base: "0"),
            let squareLat = value(for: chars[3], base: "0")
        else { return nil }

        var lon = (Double(fieldLon) * 20.0) - 180.0 + (Double(squareLon) * 2.0)
        var lat = (Double(fieldLat) * 10.0) - 90.0 + Double(squareLat)

        // Center the point in the square (Standard 4-char grid is 2x1 degree box)
        var lonDelta = 2.0
        var latDelta = 1.0

        // Subsquare (a-x): 5x2.5 minutes (Optional)
        if chars.count >= 6 {
            if let subLon = value(for: chars[4], base: "A"),
                let subLat = value(for: chars[5], base: "A")
            {

                lon += (Double(subLon) * (2.0 / 24.0))  // 5 mins
                lat += (Double(subLat) * (1.0 / 24.0))  // 2.5 mins

                lonDelta = 2.0 / 24.0
                latDelta = 1.0 / 24.0
            }
        }

        // Move to center of box
        lon += (lonDelta / 2.0)
        lat += (latDelta / 2.0)

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func value(for char: Character, base: Character) -> Int? {
        guard let charVal = char.asciiValue,
            let baseVal = base.asciiValue
        else { return nil }
        return Int(charVal) - Int(baseVal)
    }
}
