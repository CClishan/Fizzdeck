import SwiftUI

struct DocsTabView: View {
    let project: RepoProject
    let docs: [DocFile]

    @State private var selected: String?
    @State private var text = ""
    @State private var loading = false

    private var selectedDoc: DocFile? {
        docs.first { $0.file == selected }
    }

    var body: some View {
        HStack(spacing: 0) {
            if docs.isEmpty {
                ContentUnavailableView(
                    "没有文档",
                    systemImage: "doc.text",
                    description: Text("支持 README、PRODUCT、HANDOFF、AGENTS 等常见文档。")
                )
            } else {
                List(selection: $selected) {
                    ForEach(docs) { doc in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(doc.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                Text(doc.file)
                                Text("·")
                                Text(Format.bytes(doc.bytes))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        .padding(.vertical, 3)
                        .tag(doc.file)
                    }
                }
                .listStyle(.inset)
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 280)

                Divider()

                docReader
            }
        }
        .onAppear {
            if selected == nil { selected = docs.first?.file }
        }
        .onChange(of: docs) { _, value in
            if let selected, value.contains(where: { $0.file == selected }) { return }
            selected = value.first?.file
        }
        .task(id: "\(project.path)|\(selected ?? "")") {
            guard let selected else {
                text = ""
                return
            }
            let directory = URL(fileURLWithPath: project.path)
            loading = true
            let content = await Task.detached(priority: .userInitiated) {
                DocService.read(directory, file: selected)
            }.value
            guard !Task.isCancelled else { return }
            text = content ?? ""
            loading = false
        }
    }

    @ViewBuilder
    private var docReader: some View {
        if let doc = selectedDoc {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title)
                            .font(.headline)
                        HStack(spacing: 6) {
                            Text(doc.file)
                            Text("·")
                            Text("\(doc.lines) 行")
                            Text("·")
                            Text(Format.bytes(doc.bytes))
                            if let modified = doc.modified {
                                Text("·")
                                Text(Format.relative(modified))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        SystemActions.copy("\(project.path)/\(doc.file)")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .help("复制文件路径")
                    .accessibilityLabel("复制文件路径")
                    Button {
                        SystemActions.open("\(project.path)/\(doc.file)")
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .help("用默认应用打开")
                    .accessibilityLabel("用默认应用打开")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(verbatim: text)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "选择一份文档",
                systemImage: "doc.text",
                description: Text("左侧列出项目根目录下的常见说明文件。")
            )
        }
    }
}
