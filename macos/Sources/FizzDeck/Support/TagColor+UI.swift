import SwiftUI

extension TagColor {
    var color: Color {
        switch self {
        case .red:
            Color(.sRGB, red: 0.80, green: 0.35, blue: 0.32, opacity: 1)
        case .amber:
            Color(.sRGB, red: 0.92, green: 0.66, blue: 0.24, opacity: 1)
        case .green:
            Color(.sRGB, red: 0.30, green: 0.70, blue: 0.48, opacity: 1)
        case .blue:
            Color(.sRGB, red: 0.28, green: 0.55, blue: 0.92, opacity: 1)
        case .violet:
            Color(.sRGB, red: 0.62, green: 0.42, blue: 0.92, opacity: 1)
        }
    }
}

extension StackGroup {
    var color: Color {
        switch key {
        case "framework": .blue
        case "language": .purple
        case "infra": .green
        case "feature": .orange
        default: .secondary
        }
    }
}
