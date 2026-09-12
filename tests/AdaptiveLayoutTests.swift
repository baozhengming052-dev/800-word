import Foundation

// Run on macOS: swiftc Words800App/AdaptiveLayout.swift tests/AdaptiveLayoutTests.swift -o /tmp/adaptive-layout-tests && /tmp/adaptive-layout-tests
// Catches a width-only breakpoint incorrectly splitting a phone or portrait iPad,
// and an orientation-only breakpoint squeezing Split View into two columns.
@main
struct AdaptiveLayoutTests {
    static func main() {
        let cases: [(String, CGFloat, CGFloat, Bool, Bool)] = [
            ("11-inch iPad landscape", 1194, 750, true, true),
            ("12.9-inch iPad landscape", 1366, 920, true, true),
            ("11-inch iPad portrait", 834, 1080, true, false),
            ("12.9-inch iPad portrait", 1024, 1250, true, false),
            ("iPhone 14 Pro Max portrait", 430, 800, false, false),
            ("iPhone 14 Pro Max landscape", 932, 340, false, false),
            ("narrow iPad Split View", 700, 700, true, false),
            ("compact wide window", 1100, 700, false, false),
            ("square window", 1100, 1100, true, false)
        ]
        for (name, width, height, regular, expected) in cases {
            let actual = AdaptiveLayoutRules.usesTwoColumns(
                width: width, height: height, regularWidth: regular)
            precondition(actual == expected, "Unexpected layout: \(name)")
        }
        print("Adaptive layout: \(cases.count) cases passed")
    }
}
