import SwiftUI

enum StableHue {
    struct PaletteColor {
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    private static let palette: [PaletteColor] = [
        PaletteColor(hue: 214.14 / 360, saturation: 0.6237, brightness: 0.7294), // blue #4678BA
        PaletteColor(hue: 250.00 / 360, saturation: 0.4483, brightness: 0.6824), // purple #6D60AE
        PaletteColor(hue: 126.43 / 360, saturation: 0.4000, brightness: 0.5490), // green #548C5A
        PaletteColor(hue: 48.24 / 360, saturation: 0.5730, brightness: 0.6980), // gold #B29E4C
        PaletteColor(hue: 300.00 / 360, saturation: 0.3522, brightness: 0.6235), // pink #9F679F
    ]

    static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }

    static func paletteColor(for string: String) -> PaletteColor {
        palette[Int(hash(string) % UInt64(palette.count))]
    }

    static func hue(for string: String) -> Double {
        paletteColor(for: string).hue
    }

    static func color(for string: String) -> Color {
        let entry = paletteColor(for: string)
        return Color(hue: entry.hue, saturation: entry.saturation, brightness: entry.brightness)
    }
}
