import Foundation
import Testing
@testable import Roomy

struct StableHueTests {
    @Test func hueIsDeterministic() {
        let a = StableHue.hue(for: "Developer")
        let b = StableHue.hue(for: "Developer")
        #expect(a == b)
    }

    @Test func hueIsDrawnFromFixedPalette() {
        let names = ["Developer", "Documents", "Library", "Movies", "node_modules", "Downloads", "Pictures"]
        let hues = Set(names.map { StableHue.hue(for: $0) })
        #expect(hues.count > 1)
    }

    @Test func hueStaysInUnitRange() {
        for name in ["", "a", "Library", "node_modules", "🎉emoji folder"] {
            let hue = StableHue.hue(for: name)
            #expect(hue >= 0 && hue < 1)
        }
    }
}
