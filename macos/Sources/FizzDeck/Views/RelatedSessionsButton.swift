import Foundation
import SwiftUI

struct RelatedSessionsButton: View {
    let project: RepoProject
    let file: String
    var compact = false

    @Environment(RepositoryStore.self) private var store
    @State private var isPresented = false
    @State private var isLoading = false
    @State private var results: [SessionSearchResult] = []

    var body: some View {
        Button {
            isPresented.toggle()
            guard isPresented else { return }
            Task { await load() }
        } label: {
            if compact {
                FizzIcon(symbol: "text.bubble", size: 10)
                    .foregroundStyle(FizzTheme.accent)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            } else {
                Label("查相关对话", systemImage: "text.bubble")
                    .font(.system(size: 10.5, weight: .medium))
            }
        }
        .buttonStyle(.glass)
        .controlSize(.mini)
        .help("查看改过 \(URL(fileURLWithPath: file).lastPathComponent) 的历史对话")
        .accessibilityLabel("查相关对话")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("改过这个文件的对话")
                    .font(.system(size: 13, weight: .semibold))
                Text(file)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Divider()
                .opacity(0.4)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在翻这段时间的记录…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            } else if results.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("还没有对话改过这个文件")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("之后 AI 在这里改动后，会自动出现在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { result in
                            sessionRow(result)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(FizzSpacing.panel)
        .frame(width: 380)
        .background(FizzTheme.cardFill)
    }

    private func sessionRow(_ result: SessionSearchResult) -> some View {
        Button {
            isPresented = false
            Task { await open(result) }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                FizzIcon(
                    symbol: result.endedWithError ? "exclamationmark.bubble" : "bubble.left",
                    size: 12
                )
                .foregroundStyle(result.endedWithError ? Color.orange : FizzTheme.accent)
                .frame(width: 16, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TagChip(
                            text: HomeDashboardModel.toolTitle(result.tool),
                            tint: DetectedTool(rawValue: result.tool)?.tint ?? .secondary,
                            compact: true
                        )
                        Text(Format.relative(result.modified))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                        if result.endedWithError {
                            Text("报错结束")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(result.primaryIntent.isEmpty ? (result.lastUser ?? "未记录起始描述") : result.primaryIntent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if result.endedWithError,
                       let error = result.lastError,
                       !error.isEmpty {
                        Text(error)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                FizzIcon(symbol: "chevron.right", size: 8)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(HomeDashboardModel.toolTitle(result.tool))，\(result.primaryIntent)")
    }

    private func load() async {
        isLoading = true
        defer {
            isLoading = false
        }
        results = await store.relatedSessions(forFile: file, in: project)
    }

    private func open(_ result: SessionSearchResult) async {
        guard let target = store.projects.first(where: { $0.path == result.projectPath }) else {
            return
        }

        let mark = store.preferredMark(
            sessionStableID: result.sessionStableID,
            sessionID: result.sessionID,
            startedAt: nil,
            modified: result.modified,
            projectPath: target.path
        )
        var availableMarkID: String?
        if let mark {
            let isAvailable = await SessionMarkService.isAvailable(
                mark,
                in: URL(fileURLWithPath: target.path)
            )
            if isAvailable {
                availableMarkID = mark.id
            }
        }

        store.requestedMarkIDForDiff = availableMarkID
        store.openProject(target, tab: .progress, sessionID: result.sessionID)
    }
}
