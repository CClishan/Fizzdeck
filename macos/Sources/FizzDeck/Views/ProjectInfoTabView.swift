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

    private var nonGitOnboardingMessage: String {
        "开启时会按技术栈补全忽略规则，并记下第一份可还原的基线。"
    }

    private var nonGitGuidePanel: some View {
        Panel(title: "还没有开启版本保护", symbol: "exclamationmark.shield") {
            HStack(spacing: 12) {
                Text(nonGitOnboardingMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                EnableVersionProtectionButton(project: project)
                    .buttonStyle(.glassProminent)
                    .tint(FizzTheme.accent)
            }
        }
    }

    private var infoAndNotePanel: some View {
        Panel(title: "项目信息与备注", symbol: "note.text") {
            VStack(alignment: .leading, spacing: 12) {
                if !project.intro.text.isEmpty {
                    Text(project.intro.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    TagChip(text: project.kind.title, tint: .secondary, compact: true)
                    TagChip(text: project.group, tint: ProjectGrouping.color(for: project.group), compact: true)
                    if let branch = project.branch {
                        TagChip(text: branch, tint: .blue, compact: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        SystemActions.copy(project.path)
                        ToastCenter.shared.show("已复制项目路径", symbol: "doc.on.doc.fill", tint: FizzTheme.accent)
                    } label: {
                        Label("复制路径", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }

                HStack(spacing: 10) {
                    TextField("给这个项目留一句话", text: $noteDraft)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            FizzTheme.recessedFill,
                            in: RoundedRectangle(cornerRadius: FizzRadius.control, style: .continuous)
                        )
                        .onSubmit(saveNote)

                    Text("\(noteDraft.count)/200")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)

                    Button {
                        saveNote()
                    } label: {
                        Label("保存", systemImage: "checkmark")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
        }
    }

    private var stackAndSizePanel: some View {
        Panel(title: "技术栈与空间", symbol: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 12) {
                let stackItems = project.stacks.flatMap(\.items)
                if stackItems.isEmpty {
                    Text("暂未识别到主要技术栈标签")
                        .font(.callout)
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

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("占用空间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(project.sizeLoadState == .ready ? Format.bytes(project.size.totalBytes) : "统计中…")
                            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    }

                    Spacer(minLength: 12)

                    if project.cleanup.reusableBytes > 0 {
                        Button {
                            onShowCleanup()
                        } label: {
                            Label(
                                "清理空间（可省 \(Format.bytes(project.cleanup.reusableBytes))）",
                                systemImage: "trash"
                            )
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var documentsListPanel: some View {
        Panel(title: "项目文档", symbol: "doc.text") {
            if docs.isEmpty {
                Text("暂未检测到 README、PRODUCT、HANDOFF、AGENTS 等说明文档。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(docs) { doc in
                        HStack(spacing: 10) {
                            Button {
                                previewDoc = doc
                            } label: {
                                HStack(spacing: 10) {
                                    FizzIcon(symbol: "doc.plaintext", size: 13)
                                        .foregroundStyle(FizzTheme.accent)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(doc.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        HStack(spacing: 5) {
                                            Text(doc.file)
                                            Text("·")
                                            Text("\(doc.lines) 行")
                                            Text("·")
                                            Text(Format.bytes(doc.bytes))
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                SystemActions.copy("\(project.path)/\(doc.file)")
                                ToastCenter.shared.show("已复制文档路径", symbol: "doc.on.doc.fill", tint: FizzTheme.accent)
                            } label: {
                                FizzIcon(symbol: "doc.on.doc", size: 11)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .help("复制文件路径")
                            .accessibilityLabel("复制 \(doc.file) 路径")

                            Button {
                                SystemActions.open("\(project.path)/\(doc.file)")
                            } label: {
                                FizzIcon(symbol: "arrow.up.forward.app", size: 11)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .help("用默认应用打开")
                            .accessibilityLabel("打开 \(doc.file)")
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
                    .font(.caption.monospacedDigit())
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
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.title)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        Text(doc.file)
                        Text("·")
                        Text("\(doc.lines) 行")
                        Text("·")
                        Text(Format.bytes(doc.bytes))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    SystemActions.open("\(project.path)/\(doc.file)")
                } label: {
                    Label("用默认应用打开", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .tint(FizzTheme.accent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(FizzTheme.sidebar)

            Divider()

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(verbatim: text)
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
        }
        .frame(width: 680, height: 520)
        .background(FizzTheme.page)
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
