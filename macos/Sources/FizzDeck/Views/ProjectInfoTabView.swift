import SwiftUI

struct ProjectInfoTabView: View {
    let project: RepoProject
    let docs: [DocFile]
    @Binding var noteDraft: String
    let saveNote: () -> Void
    let onShowCleanup: () -> Void

    @State private var previewDoc: DocFile?

    private var hasGitRepository: Bool {
        GitService.hasGit(URL(fileURLWithPath: project.path))
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: FizzSpacing.section) {
                if !hasGitRepository {
                    nonGitGuidePanel
                }
                infoAndNotePanel
                stackAndSizePanel
                documentsListPanel
            }
            .padding(FizzSpacing.page)
        }
        .fizzTracksScrollPastTop()
        .sheet(item: $previewDoc) { doc in
            DocPreviewSheet(project: project, doc: doc)
        }
    }

    private var nonGitGuidePanel: some View {
        Panel(title: "还没有开启版本保护", symbol: "exclamationmark.shield") {
            Text("开启时会按技术栈补全忽略规则，并记下第一份可还原的基线。")
                .font(FizzTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } accessory: {
            EnableVersionProtectionButton(project: project, prominence: .primary)
        }
    }

    private var infoAndNotePanel: some View {
        Panel(title: "项目信息与备注", symbol: "note.text") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                if !project.intro.text.isEmpty {
                    Text(project.intro.text)
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FlowLayout(spacing: FizzSpacing.row) {
                    TagChip(text: project.kind.title, tint: .secondary, compact: true)
                    TagChip(text: project.group, compact: true)
                    if let branch = project.branch {
                        TagChip(text: branch, tint: Color.secondary, compact: true)
                    }
                }

                HStack(spacing: FizzSpacing.row) {
                    TextField("给这个项目留一句话", text: $noteDraft)
                        .textFieldStyle(.plain)
                        .font(FizzTypography.body)
                        .padding(.horizontal, 10)
                        .frame(height: FizzControlHeight.standard.rawValue)
                        .background(
                            FizzTheme.recessedFill,
                            in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        )
                        .onSubmit(saveNote)

                    Text("\(noteDraft.count)/200")
                        .font(FizzTypography.micro)
                        .foregroundStyle(.tertiary)
                }
            }
        } accessory: {
            FizzActionButton(title: "保存备注", symbol: "checkmark", height: .compact, action: saveNote)
        }
    }

    private var stackAndSizePanel: some View {
        Panel(title: "技术栈与空间", symbol: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: FizzSpacing.grid) {
                let stackItems = project.stacks.flatMap(\.items)
                if stackItems.isEmpty {
                    Text("暂未识别到主要技术栈标签")
                        .font(FizzTypography.body)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(stackItems, id: \.self) { item in
                            TagChip(text: item, tint: .secondary, compact: true)
                        }
                    }
                }

                Divider()
                    .opacity(0.25)

                VStack(alignment: .leading, spacing: 2) {
                    Text("占用空间")
                        .font(FizzTypography.caption)
                        .foregroundStyle(.secondary)
                    Text(project.sizeLoadState == .ready ? Format.bytes(project.size.totalBytes) : "统计中…")
                        .font(FizzTypography.mono(.semibold))
                }
            }
        } accessory: {
            FizzActionButton(
                title: project.cleanup.reusableBytes > 0
                    ? "清理空间（可省 \(Format.bytes(project.cleanup.reusableBytes))）"
                    : "清理空间…",
                symbol: "trash.slash",
                height: .compact,
                action: onShowCleanup
            )
        }
    }

    private var documentsListPanel: some View {
        Panel(title: "项目文档", symbol: "doc.text") {
            if docs.isEmpty {
                Text("暂未检测到 README、PRODUCT、HANDOFF、AGENTS 等说明文档。")
                    .font(FizzTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(docs) { doc in
                        HStack(spacing: 10) {
                            Button {
                                previewDoc = doc
                            } label: {
                                HStack(spacing: 10) {
                                    FizzIcon(.md, symbol: "doc.plaintext")
                                        .foregroundStyle(Color.secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(doc.title)
                                            .font(FizzTypography.body(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        HStack(spacing: 5) {
                                            Text(doc.file)
                                            Text("·")
                                            Text("\(doc.lines) 行")
                                            Text("·")
                                            Text(Format.bytes(doc.bytes))
                                        }
                                        .font(FizzTypography.micro)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            FizzIconButton(title: "复制 \(doc.file) 路径", symbol: "doc.on.doc", height: .compact) {
                                SystemActions.copy("\(project.path)/\(doc.file)", feedback: nil)
                                ToastCenter.shared.show("已复制文档路径", symbol: "doc.on.doc.fill", tint: Color.secondary)
                            }

                            FizzIconButton(title: "打开 \(doc.file)", symbol: "arrow.up.forward.app", height: .compact) {
                                SystemActions.open("\(project.path)/\(doc.file)")
                            }
                            .help("用默认应用打开")
                        }
                        .padding(.vertical, 8)

                        if doc.id != docs.last?.id {
                            Divider()
                                .opacity(0.25)
                        }
                    }
                }
            }
        } accessory: {
            if !docs.isEmpty {
                Text("\(docs.count) 份")
                    .font(FizzTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DocPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: RepoProject
    let doc: DocFile

    @State private var text = ""
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            FizzSheetHeader(
                title: doc.title,
                subtitle: "\(doc.file) · \(doc.lines) 行 · \(Format.bytes(doc.bytes))"
            ) {
                dismiss()
            }
            .padding(FizzSpacing.panel)

            Divider()

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(verbatim: text)
                        .font(FizzTypography.body)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(FizzSpacing.panel)
                }
            }

            Divider()

            FizzSheetFooter {
                FizzActionButton(title: "关闭", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                FizzActionButton(title: "用默认应用打开", symbol: "arrow.up.forward.app", prominence: .primary) {
                    SystemActions.open("\(project.path)/\(doc.file)")
                }
            }
            .padding(FizzSpacing.panel)
        }
        .frame(width: 680, height: 520)
        .task(id: doc.file) {
            loading = true
            let directory = URL(fileURLWithPath: project.path)
            let content = await Task.detached(priority: .userInitiated) {
                DocService.read(directory, file: doc.file)
            }.value
            guard !Task.isCancelled else { return }
            text = content ?? ""
            loading = false
        }
    }
}
