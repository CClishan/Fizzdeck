import Foundation
import SwiftUI

enum ProjectGrouping {
    static let order = ["产品站", "工作区", "工具库", "官网", "上屏管家", "其他"]

    static func color(for group: String) -> Color {
        switch group {
        case "产品站": .blue
        case "工作区": .purple
        case "工具库": .green
        case "官网": .orange
        case "上屏管家": .pink
        default: .secondary
        }
    }
}
