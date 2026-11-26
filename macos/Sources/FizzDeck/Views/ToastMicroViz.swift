import SwiftUI

struct ToastMicroVizView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viz: ToastMicroViz

    @State private var phase: Double = 0
    @State private var latestBarGreen = false
    @State private var pulsing = false

    private var animationKey: String {
        String(describing: viz)
    }

    var body: some View {
        Group {
            switch viz {
            case .tests(let passed, let failed):
                testGrid(passed: passed, failed: failed)
            case .gitMerge:
                mergePath
            case .pipeline(let step, let state):
                pipeline(step: step, state: state)
            case .bars(let values, let improved):
                bars(values: values, improved: improved)
            case .diff(let added, let removed):
                diffGrid(added: added, removed: removed)
            case .compact(let state):
                compactGrid(state: state)
            }
        }
        .frame(width: 68, height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viz.accessibilitySummary)
        .task(id: animationKey) {
            await animate()
        }
        .onChange(of: reduceMotion) {
            if reduceMotion {
                phase = 1
                latestBarGreen = true
                pulsing = false
            }
        }
    }

    private func testGrid(passed: Int, failed: Int) -> some View {
        let cells = ToastMicroViz.testCells(passed: passed, failed: failed)
        return MicroGrid(
            cells: cells,
            columns: ToastMicroViz.testColumns,
            rows: ToastMicroViz.testRows,
            cellSize: 3.8,
            spacing: 1.15,
            phase: phase,
            cornerRadius: 1.1,
            columnMajor: true
        )
    }

    private var mergePath: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 7, y: 23))
                path.addLine(to: CGPoint(x: 61, y: 23))
            }
            .trim(from: 0, to: phase)
            .stroke(
                Color.secondary.opacity(0.24),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )

            Path { path in
                path.move(to: CGPoint(x: 15, y: 23))
                path.addCurve(
                    to: CGPoint(x: 34, y: 9),
                    control1: CGPoint(x: 20, y: 23),
                    control2: CGPoint(x: 27, y: 9)
                )
                path.addCurve(
                    to: CGPoint(x: 53, y: 23),
                    control1: CGPoint(x: 41, y: 9),
                    control2: CGPoint(x: 48, y: 23)
                )
            }
            .trim(from: 0, to: phase)
            .stroke(
                LinearGradient(
                    colors: [.blue, FizzTheme.accent],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            mergeCommit(x: 15, y: 23, index: 0)
            mergeCommit(x: 34, y: 9, index: 1)
            mergeCommit(x: 53, y: 23, index: 2)
        }
    }

    private func mergeCommit(x: CGFloat, y: CGFloat, index: Int) -> some View {
        let reveal = max(0, min(1, (phase - Double(index) * 0.18) / 0.46))
        return Circle()
            .fill(
                index == 1
                    ? AnyShapeStyle(LinearGradient(
                        colors: [.blue, FizzTheme.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    : AnyShapeStyle(Color.blue)
            )
            .frame(width: 5, height: 5)
            .overlay {
                Circle()
                    .strokeBorder(FizzTheme.cardFill.opacity(0.85), lineWidth: 1)
            }
            .scaleEffect(reveal == 1 ? 1 : 0.25)
            .opacity(reveal)
            .position(x: x, y: y)
    }

    private func pipeline(step: Int, state: ToastPipelineState) -> some View {
        let step = min(4, max(0, step))
        return GeometryReader { proxy in
            let inset: CGFloat = 8
            let usable = max(1, proxy.size.width - inset * 2)
            let xStep = usable / 4

            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    let active = index < step || state == .live
                    let failed = state == .failed && index == step
                    Capsule()
                        .fill(failed ? Color.red : (active ? Color.green : FizzTheme.hairline))
                        .frame(width: max(1, xStep * revealFor(index)), height: 1.5)
                        .position(
                            x: inset + xStep * CGFloat(index) + xStep / 2,
                            y: proxy.size.height / 2
                        )
                }

                ForEach(0..<5, id: \.self) { index in
                    pipelineNode(index: index, step: step, state: state)
                        .position(
                            x: inset + xStep * CGFloat(index),
                            y: proxy.size.height / 2
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func pipelineNode(
        index: Int,
        step: Int,
        state: ToastPipelineState
    ) -> some View {
        let isFinal = index == 4
        let completed = index < step || state == .live
        let current = index == step && state != .live
        let failed = state == .failed && index == step
        let tint: Color = failed ? .red : (completed || current ? .green : .secondary)

        ZStack {
            if current && !reduceMotion {
                Circle()
                    .stroke(tint.opacity(0.4), lineWidth: 1)
                    .frame(width: 9, height: 9)
                    .scaleEffect(pulsing ? 2.1 : 1)
                    .opacity(pulsing ? 0 : 0.8)
            }

            Circle()
                .fill(completed ? tint : FizzTheme.cardFill)
                .frame(width: isFinal && state == .live ? 8 : 6, height: isFinal && state == .live ? 8 : 6)
                .overlay {
                    Circle()
                        .strokeBorder(tint.opacity(completed || current || failed ? 0.9 : 0.4), lineWidth: 1)
                }

            if failed {
                Image(systemName: "xmark")
                    .font(.system(size: 4.5, weight: .black))
                    .foregroundStyle(.red)
            } else if completed, index > 0 || state == .live {
                Image(systemName: "checkmark")
                    .font(.system(size: index == 4 ? 5.5 : 4, weight: .black))
                    .foregroundStyle(.white)
            }
        }
    }

    private func revealFor(_ index: Int) -> CGFloat {
        let start = Double(index) * 0.16
        return CGFloat(max(0, min(1, (phase - start) / 0.52)))
    }

    private func bars(values: [Double], improved: Bool) -> some View {
        let normalized = ToastMicroViz.normalizedBars(values)
        return HStack(alignment: .bottom, spacing: 2.4) {
            ForEach(Array(normalized.enumerated()), id: \.offset) { index, value in
                let order = Double(index) / 7
                let reveal = max(0, min(1, (phase - order * 0.45) / 0.55))
                let isLatest = index == normalized.count - 1
                Capsule()
                    .fill(
                        isLatest && improved && latestBarGreen
                            ? Color.green
                            : (isLatest ? Color.blue : FizzTheme.accent.opacity(0.55))
                    )
                    .frame(width: 4.5, height: max(3, 24 * value * reveal))
                    .opacity(reveal)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.vertical, 3)
    }

    private func diffGrid(added: Int, removed: Int) -> some View {
        let cells = ToastMicroViz.diffCells(added: added, removed: removed)
        return MicroGrid(
            cells: cells,
            columns: ToastMicroViz.diffColumns,
            rows: ToastMicroViz.diffRows,
            cellSize: 4,
            spacing: 1.4,
            phase: phase,
            cornerRadius: 1.2
        )
    }

    private func compactGrid(state: ToastCompactState) -> some View {
        let cells = Array(
            repeating: ToastCellKind.warning,
            count: ToastMicroViz.diffColumns * ToastMicroViz.diffRows
        )
        let amberOpacity = state == .done || state == .working
            ? max(0, 1 - phase)
            : 1

        return ZStack {
            MicroGrid(
                cells: cells,
                columns: ToastMicroViz.diffColumns,
                rows: ToastMicroViz.diffRows,
                cellSize: 4,
                spacing: 1.4,
                phase: phase,
                tintOverride: .blue,
                cornerRadius: 1.2
            )

            MicroGrid(
                cells: cells,
                columns: ToastMicroViz.diffColumns,
                rows: ToastMicroViz.diffRows,
                cellSize: 4,
                spacing: 1.4,
                phase: phase,
                tintOverride: .orange,
                cornerRadius: 1.2
            )
            .opacity(amberOpacity)
        }
    }

    private func animate() async {
        phase = 0
        latestBarGreen = false
        pulsing = false

        if reduceMotion {
            phase = 1
            latestBarGreen = true
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
        withAnimation(.easeOut(duration: 0.72)) {
            phase = 1
        }

        if case .bars(_, let improved) = viz, improved {
            try? await Task.sleep(for: .milliseconds(460))
            withAnimation(.easeInOut(duration: 0.24)) {
                latestBarGreen = true
            }
        }

        if case .pipeline(_, .running) = viz {
            withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

private struct MicroGrid: View {
    let cells: [ToastCellKind]
    let columns: Int
    let rows: Int
    let cellSize: CGFloat
    let spacing: CGFloat
    let phase: Double
    var tintOverride: Color?
    let cornerRadius: CGFloat
    var columnMajor = false

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        let kind = index < cells.count ? cells[index] : .empty
                        let order = columnMajor
                            ? Double(column) / Double(max(1, columns - 1))
                            : Double(index) / Double(max(1, cells.count - 1))
                        let reveal = max(0, min(1, (phase - order * 0.52) / 0.48))

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(color(for: kind))
                            .frame(width: cellSize, height: cellSize)
                            .scaleEffect(0.72 + 0.28 * reveal)
                            .opacity(reveal)
                    }
                }
            }
        }
    }

    private func color(for kind: ToastCellKind) -> Color {
        switch kind {
        case .empty:
            return FizzTheme.hairline
        case .positive:
            return .green
        case .negative:
            return .red
        case .warning:
            return tintOverride ?? .orange
        case .neutral:
            return .secondary.opacity(0.55)
        }
    }
}
