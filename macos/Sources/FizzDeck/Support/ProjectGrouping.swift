import Foundation
import SwiftUI

enum ProjectGrouping {
    static let order: [String] = ProjectKind.allCases.map(\.groupKey)

    static func ordered(_ groups: some Sequence<String>) -> [String] {
        let detected = Set(groups)
        return order.filter(detected.contains)
            + detected.subtracting(order).sorted()
    }

    static func detected(for path: String, kind: ProjectKind? = nil) -> String {
        let resolved = kind ?? ProjectKindDetector.detect(directory: URL(fileURLWithPath: path))
        return resolved.groupKey
    }

    static func title(for group: String) -> String {
        ProjectKind.allCases.first { $0.groupKey == group }?.title ?? group
    }

    static func color(for group: String) -> Color {
        ProjectAccentColor.color(for: group)
    }
}
