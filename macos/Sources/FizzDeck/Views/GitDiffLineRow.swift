import SwiftUI

struct GitDiffLineRow: View {
    let line: GitDiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(FizzTypography.monoSmall)
        .padding(.horizontal, FizzSpacing.row)
        .padding(.vertical, 1)
        .background(line.kind == .hunk ? FizzTheme.mutedFill : Color.clear)
    }

    private var textColor: Color {
        switch line.kind {
        case .addition: FizzTheme.statusSuccess
        case .deletion: FizzTheme.statusDanger
        case .context: .primary
        case .hunk, .meta, .header: .secondary
        }
    }
}
