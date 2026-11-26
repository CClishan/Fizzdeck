import SwiftUI

struct FizzShimmerPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let width: CGFloat
    var height: CGFloat = 12
    var cornerRadius: CGFloat = FizzRadius.micro

    @State private var phase: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(FizzTheme.recessedFill)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(
                                    FizzShimmerMetrics.highlightOpacity(for: colorScheme)
                                ),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(18, proxy.size.width * FizzShimmerMetrics.bandFraction))
                        .offset(
                            x: FizzShimmerMetrics.bandOffset(
                                phase: phase,
                                width: proxy.size.width
                            )
                        )
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FizzTheme.hairline, lineWidth: 0.6)
            }
            .frame(width: width, height: height)
            .task(id: reduceMotion) {
                phase = 0
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(
                    .linear(duration: FizzShimmerMetrics.duration)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
            .accessibilityHidden(true)
    }
}
