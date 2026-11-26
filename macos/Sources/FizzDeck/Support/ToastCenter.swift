import Foundation
import Observation
import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id: UUID
    let symbol: String
    let title: String
    let tint: Color

    init(
        id: UUID = UUID(),
        symbol: String = "checkmark.circle.fill",
        title: String,
        tint: Color = .green
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.tint = tint
    }
}

@Observable
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    private(set) var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    init() {}

    func show(
        _ title: String,
        symbol: String = "checkmark.circle.fill",
        tint: Color = .green,
        duration: TimeInterval = 2.0
    ) {
        dismissTask?.cancel()
        let message = ToastMessage(symbol: symbol, title: title, tint: tint)
        current = message

        guard duration > 0 else { return }
        dismissTask = Task { @MainActor [weak self] in
            let nanos = UInt64(max(0.2, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            if self?.current?.id == message.id {
                self?.current = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }
}
