import SwiftUI

enum FizzShimmerMetrics {
    static let duration: TimeInterval = 1.45
    static let bandFraction: CGFloat = 0.62

    static func bandOffset(phase: Double, width: CGFloat) -> CGFloat {
        let clamped = CGFloat(min(1, max(0, phase)))
        let bandWidth = max(18, width * bandFraction)
        return -bandWidth + clamped * (width + bandWidth)
    }

    static func highlightOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.12 : 0.52
    }
}

enum LibraryCoverPreference {
    static let key = "fizzdeck.library.showCoverPreview"
    static let defaultValue = true

    static func resolved(_ storedValue: Bool?) -> Bool {
        storedValue ?? defaultValue
    }
}
