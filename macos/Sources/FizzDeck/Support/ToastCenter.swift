import Foundation
import Observation
import SwiftUI

enum ToastPipelineState: String, Equatable, Sendable {
    case running
    case failed
    case live
}

enum ToastCompactState: String, Equatable, Sendable {
    case warning
    case working
    case done
}

enum ToastCellKind: Equatable, Sendable {
    case empty
    case positive
    case negative
    case warning
    case neutral
}

enum ToastMicroViz: Equatable, Sendable {
    case tests(passed: Int, failed: Int)
    case gitMerge
    case pipeline(step: Int, state: ToastPipelineState)
    case bars(values: [Double], improved: Bool)
    case diff(added: Int, removed: Int)
    case compact(state: ToastCompactState)

    static let testColumns = 13
    static let testRows = 4
    static let diffColumns = 10
    static let diffRows = 4

    static func testCells(passed: Int, failed: Int) -> [ToastCellKind] {
        let capacity = testColumns * testRows
        let passed = min(capacity, max(0, passed))
        let failed = min(capacity - passed, max(0, failed))
        return (0..<capacity).map { index in
            if index < passed { return .positive }
            if index < passed + failed { return .negative }
            return .empty
        }
    }

    static func diffCells(added: Int, removed: Int) -> [ToastCellKind] {
        let capacity = diffColumns * diffRows
        let total = max(0, added) + max(0, removed)
        guard total > 0 else {
            return Array(repeating: .empty, count: capacity)
        }

        let filled = min(capacity, max(1, total))
        let positive = Int((Double(max(0, added)) / Double(total) * Double(filled)).rounded())
        let negative = min(filled - positive, max(0, removed))
        let remaining = filled - positive - negative

        return (0..<capacity).map { index in
            if index < positive { return .positive }
            if index < positive + negative { return .negative }
            if index < positive + negative + remaining { return .negative }
            return .empty
        }
    }

    static func normalizedBars(_ values: [Double]) -> [Double] {
        let values = Array(values.prefix(8))
        guard let peak = values.max(), peak > 0 else {
            return Array(repeating: 0.08, count: 8)
        }
        return (0..<8).map { index in
            guard index < values.count else { return 0.08 }
            return max(0.08, min(1, values[index] / peak))
        }
    }

    var accessibilitySummary: String {
        switch self {
        case .tests(let passed, let failed):
            "测试通过 \(passed) 项，失败 \(failed) 项"
        case .gitMerge:
            "Git 提交汇入主干"
        case .pipeline(let step, let state):
            "管线第 \(min(5, max(1, step + 1))) 步，\(state.accessibilityLabel)"
        case .bars(_, let improved):
            improved ? "指标柱状图改善" : "指标柱状图更新"
        case .diff(let added, let removed):
            "代码新增 \(added) 行，删除 \(removed) 行"
        case .compact(let state):
            state.accessibilityLabel
        }
    }
}

extension ToastPipelineState {
    var accessibilityLabel: String {
        switch self {
        case .running: "进行中"
        case .failed: "失败"
        case .live: "已完成"
        }
    }
}

extension ToastCompactState {
    var accessibilityLabel: String {
        switch self {
        case .warning: "需要处理"
        case .working: "进行中"
        case .done: "已完成"
        }
    }
}

struct ToastAction {
    let title: String
    var symbol: String? = nil
    let handler: @MainActor () -> Void
}

struct ToastMessage: Identifiable {
    let id: UUID
    var symbol: String
    var title: String
    var subtitle: String?
    var tint: Color
    var microViz: ToastMicroViz?
    var action: ToastAction?
    var duration: TimeInterval?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        symbol: String = "checkmark.circle.fill",
        title: String,
        subtitle: String? = nil,
        tint: Color = FizzTheme.statusSuccess,
        microViz: ToastMicroViz? = nil,
        action: ToastAction? = nil,
        duration: TimeInterval? = 2.2
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.microViz = microViz
        self.action = action
        self.duration = action == nil ? duration : nil
        self.createdAt = Date()
    }
}

@Observable
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    private(set) var messages: [ToastMessage] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    init() {}

    var current: ToastMessage? {
        messages.first
    }

    @discardableResult
    func show(
        _ title: String,
        symbol: String = "checkmark.circle.fill",
        tint: Color = FizzTheme.statusSuccess,
        duration: TimeInterval? = 2.2,
        subtitle: String? = nil,
        microViz: ToastMicroViz? = nil,
        action: ToastAction? = nil
    ) -> UUID {
        let message = ToastMessage(
            symbol: symbol,
            title: title,
            subtitle: subtitle,
            tint: tint,
            microViz: microViz,
            action: action,
            duration: duration
        )
        messages.insert(message, at: 0)
        scheduleDismiss(for: message.id, after: message.duration)
        trimIfNeeded()
        return message.id
    }

    @discardableResult
    func update(
        _ id: UUID,
        duration: TimeInterval? = nil,
        mutate: (inout ToastMessage) -> Void
    ) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return false
        }
        var message = messages[index]
        mutate(&message)
        if message.action != nil {
            message.duration = nil
        } else if let duration {
            message.duration = duration > 0 ? duration : nil
        }
        messages[index] = message
        scheduleDismiss(for: id, after: message.duration)
        return true
    }

    func dismiss(id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        messages.removeAll { $0.id == id }
    }

    func dismiss() {
        for task in dismissTasks.values {
            task.cancel()
        }
        dismissTasks.removeAll()
        messages.removeAll()
    }

    private func scheduleDismiss(for id: UUID, after duration: TimeInterval?) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil

        guard let duration, duration > 0 else { return }
        dismissTasks[id] = Task { @MainActor [weak self] in
            let nanos = UInt64(max(0.2, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.dismiss(id: id)
        }
    }

    private func trimIfNeeded() {
        let overflow = max(0, messages.count - 20)
        guard overflow > 0 else { return }
        for message in messages.suffix(overflow) {
            dismissTasks[message.id]?.cancel()
            dismissTasks[message.id] = nil
        }
        messages.removeLast(overflow)
    }
}
