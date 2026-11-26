import Foundation
import SwiftUI

enum ProjectGrouping {
    static let order: [String] = ProjectKind.allCases.map(\.title)

    static func ordered(_ groups: some Sequence<String>) -> [String] {
        let detected = Set(groups)
        return order.filter(detected.contains)
            + detected.subtracting(order).sorted()
    }

    static func detected(for path: String, kind: ProjectKind? = nil) -> String {
        let resolved = kind ?? ProjectKindDetector.detect(directory: URL(fileURLWithPath: path))
        return resolved.title
    }

    static func color(for group: String) -> Color {
        if let kind = ProjectKind.allCases.first(where: { $0.title == group }) {
            return kind.color
        }
        return customColors[paletteIndex(for: group)]
    }

    private static let customColors: [Color] = [
        .blue, .purple, .green, .orange, .pink, .teal, .indigo, .brown,
    ]

    static func paletteIndex(for group: String) -> Int {
        var hash: UInt64 = 14695981039346656037
        for byte in group.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(hash % UInt64(customColors.count))
    }
}
