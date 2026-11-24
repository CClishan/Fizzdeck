import Foundation
import SwiftUI

enum ProjectGrouping {
    static let order = ["产品站", "工作区", "工具库", "官网", "上屏管家", "其他"]

    static func ordered(_ groups: some Sequence<String>) -> [String] {
        let detected = Set(groups)
        return order.filter(detected.contains)
            + detected.subtracting(order).sorted()
    }

    static func detected(for path: String) -> String {
        let name = (path as NSString).lastPathComponent.lowercased()
        let value = path.lowercased()
        if value.contains("workspace") || value.contains("cpa-manager") { return "工作区" }
        if name.hasPrefix("tsys") { return "上屏管家" }
        if value.contains("converter-tools")
            || value.contains("alimama-cli")
            || value.contains("cliproxyapi")
            || value.contains("shipany") {
            return "工具库"
        }
        if value.contains("noplan") { return "官网" }
        if value.contains("zoopfizz")
            || value.contains("video-tem")
            || value.contains("pixloading")
            || value.contains("cardfun")
            || value.contains("a2o")
            || value.contains("tapinchina") {
            return "产品站"
        }
        return "其他"
    }

    static func color(for group: String) -> Color {
        switch group {
        case "产品站": .blue
        case "工作区": .purple
        case "工具库": .green
        case "官网": .orange
        case "上屏管家": .pink
        case "其他": .secondary
        default:
            customColors[paletteIndex(for: group)]
        }
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
