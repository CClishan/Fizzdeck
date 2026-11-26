import SwiftUI

struct ToastOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var center: ToastCenter

    var body: some View {
        Group {
            if let toast = center.current {
                HStack(spacing: 8) {
                    FizzIcon(symbol: toast.symbol, size: 12)
                        .foregroundStyle(toast.tint)
                        .symbolEffect(.bounce, value: toast.id)

                    Text(toast.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .fizzAdaptiveShadow(.floating)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(toast.title)
            }
        }
        .allowsHitTesting(false)
        .animation(FizzMotion.resolved(reduceMotion, FizzMotion.spring), value: center.current?.id)
    }
}
