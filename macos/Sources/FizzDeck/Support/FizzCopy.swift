import Foundation

enum CopyMode: String, CaseIterable, Identifiable, Sendable {
    case plain
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: FizzL10n.text("人话（适合新手）", "Plain English")
        case .pro: FizzL10n.text("专业（Git 术语）", "Git Terms")
        }
    }

    var shortTitle: String {
        switch self {
        case .plain: FizzL10n.text("人话", "Plain English")
        case .pro: FizzL10n.text("专业", "Git Terms")
        }
    }
}

enum CopyModePreferences {
    static let key = "fizzdeck.copyMode"
    static let onboardingSeenKey = "fizzdeck.plainModeOnboardingSeen"
    static let defaultValue: CopyMode = .plain

    static func mode(in defaults: UserDefaults = .standard) -> CopyMode {
        guard let raw = defaults.string(forKey: key) else { return defaultValue }
        return CopyMode(rawValue: raw) ?? defaultValue
    }

    static func set(_ mode: CopyMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

enum MergedProjectTabKey: String, CaseIterable, Identifiable, Sendable {
    case progress
    case run
    case version
    case info

    var id: String { rawValue }
}

struct TextWithHint: Equatable, Sendable {
    let text: String
    let proHint: String?
}

enum FizzCopy {
    static var conversationsNavTitle: String { FizzL10n.text("对话", "Conversations") }
    static var runningServicesTag: String { FizzL10n.text("服务", "Services") }
    static let runningAITag = "AI"

    static func tabTitle(_ tab: MergedProjectTabKey, mode: CopyMode) -> String {
        switch (tab, mode) {
        case (.progress, .plain): FizzL10n.text("进度", "Progress")
        case (.progress, .pro): FizzL10n.text("概览", "Overview")
        case (.run, .plain): FizzL10n.text("运行", "Run")
        case (.run, .pro): FizzL10n.text("运行与测试", "Run & Test")
        case (.version, .plain): FizzL10n.text("版本", "Version")
        case (.version, .pro): "Git"
        case (.info, _): FizzL10n.text("项目信息", "Info")
        }
    }

    static func focusSectionTitle(_ mode: CopyMode) -> String {
        switch mode {
        case .plain: FizzL10n.text("关注", "Following")
        case .pro: FizzL10n.text("星标", "Starred")
        }
    }

    static func uncommittedChanges(count: Int? = nil, mode: CopyMode) -> TextWithHint {
        if let count {
            return TextWithHint(
                text: mode == .plain ? FizzL10n.text("有 \(count) 个改动还没存成版本", "Unsaved changes: \(count) \(count == 1 ? "file" : "files")") : FizzL10n.text("\(count) 个文件未提交", "Uncommitted: \(count) \(count == 1 ? "file" : "files")"),
                proHint: mode == .plain ? FizzL10n.text("Git 术语：未提交改动（\(count) 个文件）", "Git: uncommitted changes (\(count) \(count == 1 ? "file" : "files"))") : nil
            )
        }
        return TextWithHint(
            text: mode == .plain ? FizzL10n.text("有改动还没存成版本", "Unsaved changes") : FizzL10n.text("未提交改动", "Uncommitted"),
            proHint: mode == .plain ? FizzL10n.text("Git 术语：未提交改动", "Git: uncommitted changes") : nil
        )
    }

    static func commitAction(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? FizzL10n.text("存个版本", "Save a version") : "Commit",
            proHint: mode == .plain ? FizzL10n.text("Git 术语：Commit", "Git: Commit") : nil
        )
    }

    static func commitAndPushAction(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? FizzL10n.text("存个版本并上传", "Save and upload") : "Commit & Push",
            proHint: mode == .plain ? FizzL10n.text("Git 术语：Commit & Push", "Git: Commit & Push") : nil
        )
    }

    static func unpushed(count: Int? = nil, mode: CopyMode) -> TextWithHint {
        if let count {
            return TextWithHint(
                text: mode == .plain ? FizzL10n.text("存了 \(count) 个版本但还没上传", "Saved versions to upload: \(count)") : FizzL10n.text("\(count) 个提交未推送", "Unpushed commits: \(count)"),
                proHint: mode == .plain ? FizzL10n.text("Git 术语：未推送（\(count) 个 Commit）", "Git: unpushed commits (\(count))") : nil
            )
        }
        return TextWithHint(
            text: mode == .plain ? FizzL10n.text("存了但还没上传", "Saved but not uploaded") : FizzL10n.text("未推送", "Unpushed"),
            proHint: mode == .plain ? FizzL10n.text("Git 术语：未推送", "Git: unpushed commits") : nil
        )
    }

    static func behind(count: Int? = nil, mode: CopyMode) -> TextWithHint {
        if let count {
            return TextWithHint(
                text: mode == .plain ? FizzL10n.text("云端有 \(count) 个新内容", "New versions online: \(count)") : FizzL10n.text("落后远端 \(count) 个提交", "Behind remote by \(count)"),
                proHint: mode == .plain ? FizzL10n.text("Git 术语：落后远端 \(count) 个提交", "Git: \(count) behind remote") : nil
            )
        }
        return TextWithHint(
            text: mode == .plain ? FizzL10n.text("云端有新内容", "New version online") : FizzL10n.text("落后远端", "Behind remote"),
            proHint: mode == .plain ? FizzL10n.text("Git 术语：落后远端", "Git: behind remote") : nil
        )
    }

    static func pullAction(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? FizzL10n.text("拿回云端的新内容", "Get online changes") : "Pull",
            proHint: mode == .plain ? FizzL10n.text("Git 术语：Pull", "Git: Pull") : nil
        )
    }

    static func stashAction(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? FizzL10n.text("先把改动收起来", "Set changes aside") : "Stash",
            proHint: mode == .plain ? FizzL10n.text("Git 术语：Stash", "Git: Stash") : nil
        )
    }

    static func portOccupied(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? FizzL10n.text("有别的程序占了这个位置，项目开不起来", "Another app is using this port") : FizzL10n.text("端口被占用", "Port in use"),
            proHint: mode == .plain ? FizzL10n.text("专业术语：端口被占用", "Port conflict") : nil
        )
    }

    static func missingDependencies(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? FizzL10n.text("项目需要的零件还没装", "Install the project’s dependencies") : FizzL10n.text("node_modules 未安装", "Missing node_modules"),
            proHint: mode == .plain ? FizzL10n.text("专业术语：缺少依赖（node_modules 未安装）", "Missing dependencies (node_modules)") : nil
        )
    }

    static func greeting(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<9: return FizzL10n.text("早上好", "Good morning")
        case 9..<12: return FizzL10n.text("上午好", "Good morning")
        case 12..<18: return FizzL10n.text("下午好", "Good afternoon")
        default: return FizzL10n.text("晚上好", "Good evening")
        }
    }

    static func dashboardStatusLine(
        activeCount: Int,
        brokenCount: Int,
        attentionCount: Int,
        mode: CopyMode
    ) -> String {
        if mode == .pro {
            var parts: [String] = []
            if activeCount > 0 { parts.append(FizzL10n.text("\(activeCount) 个活跃项目", "Active projects: \(activeCount)")) }
            if brokenCount > 0 { parts.append(FizzL10n.text("\(brokenCount) 个异常", "Issues: \(brokenCount)")) }
            if attentionCount > 0 {
                parts.append(FizzL10n.text("\(attentionCount) 项待处理", "To review: \(attentionCount)"))
            } else if parts.isEmpty {
                parts.append(FizzL10n.text("暂无待处理", "Nothing to review"))
            }
            return parts.joined(separator: " · ")
        }

        if brokenCount > 0 && activeCount > 0 {
            return FizzL10n.text("\(activeCount) 个项目在进行，\(brokenCount) 个跑不起来", "Projects in progress: \(activeCount) · Unable to run: \(brokenCount)")
        }
        if brokenCount > 0 {
            return FizzL10n.text("\(brokenCount) 个项目跑不起来，点进去看看", "Unable to run: \(brokenCount)")
        }
        if activeCount > 0 && attentionCount > 0 {
            return FizzL10n.text("\(activeCount) 个项目在进行，\(attentionCount) 件事需要你看一下", "Projects in progress: \(activeCount) · To review: \(attentionCount)")
        }
        if activeCount > 0 {
            return FizzL10n.text("\(activeCount) 个项目在进行，状态都挺好", "Projects in progress: \(activeCount) · All clear")
        }
        if attentionCount > 0 {
            return FizzL10n.text("\(attentionCount) 件事需要你看一下", "To review: \(attentionCount)")
        }
        return FizzL10n.text("一切顺利，没有需要处理的项目", "Everything looks good")
    }

    static func allClearTitle(_ mode: CopyMode) -> String {
        mode == .plain ? FizzL10n.text("都挺好的。要接着做哪个？", "All clear. What’s next?") : FizzL10n.text("一切就绪", "All clear")
    }

    static func weeklyOutputLabel(_ mode: CopyMode) -> String {
        mode == .plain ? FizzL10n.text("改动文件", "Files changed") : FizzL10n.text("本周提交", "Commits this week")
    }

    static func continueWorkTitle(_ mode: CopyMode) -> String {
        mode == .plain ? FizzL10n.text("接着做", "Pick up where you left off") : FizzL10n.text("继续工作", "Resume work")
    }

    static func attentionTitle(_ mode: CopyMode) -> String {
        mode == .plain ? FizzL10n.text("需要你看一下", "Needs your attention") : FizzL10n.text("待处理", "To review")
    }

    static func timelineTitle(_ mode: CopyMode) -> String {
        mode == .plain ? FizzL10n.text("这周做了什么", "Your week") : FizzL10n.text("本周活动", "Weekly activity")
    }

    static func costTitle(_ mode: CopyMode) -> String {
        mode == .plain ? FizzL10n.text("花了多少", "AI spending") : FizzL10n.text("AI 费用构成", "AI cost breakdown")
    }

    static func heatmapTitle(_ mode: CopyMode) -> String {
        mode == .plain ? FizzL10n.text("AI 活动热力", "AI activity") : FizzL10n.text("提交活跃度", "Commit activity")
    }

    static func projectStatusSummary(
        dirtyCount: Int,
        ahead: Int,
        behind: Int,
        mode: CopyMode
    ) -> String {
        var parts: [String] = []
        if dirtyCount > 0 {
            parts.append(Self.uncommittedChanges(count: dirtyCount, mode: mode).text)
        }
        if ahead > 0 {
            parts.append(Self.unpushed(count: ahead, mode: mode).text)
        }
        if behind > 0 {
            parts.append(Self.behind(count: behind, mode: mode).text)
        }
        if parts.isEmpty {
            return mode == .plain ? FizzL10n.text("当前代码很干净，改动都已存好", "All changes are saved") : FizzL10n.text("工作区干净", "Working tree clean")
        }
        return parts.joined(separator: FizzL10n.text("，", ", "))
    }
}
