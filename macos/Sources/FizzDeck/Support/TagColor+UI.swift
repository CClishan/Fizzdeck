import SwiftUI

extension TagColor {
    var color: Color {
        switch self {
        case .red: ProjectAccentColor.rose
        case .amber: ProjectAccentColor.ochre
        case .green: ProjectAccentColor.sage
        case .blue: ProjectAccentColor.slate
        case .violet: ProjectAccentColor.mauve
        }
    }
}
