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
        trigger
            .help("查看改过 \(URL(fileURLWithPath: file).lastPathComponent) 的历史对话")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                popoverContent
            }
    }

    @ViewBuilder
    private var trigger: some View {
        if compact {
            FizzIconButton(title: "查相关对话", symbol: "text.bubble", height: .compact, action: togglePopover)
        } else {
            FizzActionButton(title: "查相关对话", symbol: "text.bubble", height: .compact, action: togglePopover)
        }
    }

    private func togglePopover() {
        isPresented.toggle()
        guard isPresented else { return }
        Task { await load() }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            FizzSheetHeader(title: "改过这个文件的对话", subtitle: file) {
                isPresented = false
            }
            .truncationMode(.middle)
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.panel)

            Divider()
                .opacity(0.4)

            popoverBody
                .padding(.horizontal, FizzSpacing.page)
                .padding(.vertical, FizzSpacing.grid)

            Divider()
                .opacity(0.4)

            FizzSheetFooter {
                FizzActionButton(title: "关闭", role: .cancel) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, FizzSpacing.page)
            .padding(.vertical, FizzSpacing.grid)
        }
        .frame(width: 380)
        .background(FizzTheme.cardFill)
    }

    @ViewBuilder
    private var popoverBody: some View {
        if isLoading {
            HStack(spacing: FizzSpacing.row) {
                ProgressView()
                    .controlSize(.small)
                Text("正在翻这段时间的记录…")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        } else if results.isEmpty {
            VStack(alignment: .leading, spacing: FizzSpacing.row) {
                Text("还没有对话改过这个文件")
                    .font(FizzTypography.body(.medium))
                Text("之后 AI 在这里改动后，会自动出现在这里。")
                    .font(FizzTypography.caption)
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

    private func sessionRow(_ result: SessionSearchResult) -> some View {
        Button {
            isPresented = false
            Task { await open(result) }
        } label: {
            HStack(alignment: .top, spacing: FizzSpacing.row) {
                FizzIcon(
                    .sm,
                    symbol: result.endedWithError ? "exclamationmark.bubble" : "bubble.left"
                )
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TagChip(
                            text: HomeDashboardModel.toolTitle(result.tool),
                            tint: .secondary,
                            compact: true
                        )
                        Text(Format.relative(result.modified))
                            .font(FizzTypography.caption)
                            .foregroundStyle(.tertiary)
                        if result.endedWithError {
                            Text("报错结束")
                                .font(FizzTypography.micro)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(result.primaryIntent.isEmpty ? (result.lastUser ?? "未记录起始描述") : result.primaryIntent)
                        .font(FizzTypography.body(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if result.endedWithError,
                       let error = result.lastError,
                       !error.isEmpty {
                        Text(error)
                            .font(FizzTypography.monoSmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                FizzIcon(.xs, symbol: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(FizzSpacing.row)
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
