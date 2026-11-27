import Foundation

enum CopyMode: String, CaseIterable, Identifiable, Sendable {
    case plain
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: "人话（适合新手）"
        case .pro: "专业（Git 术语）"
        }
    }

    var shortTitle: String {
        switch self {
        case .plain: "人话"
        case .pro: "专业"
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
    static let conversationsNavTitle = "对话"
    static let runningServicesTag = "服务"
    static let runningAITag = "AI"

    static func tabTitle(_ tab: MergedProjectTabKey, mode: CopyMode) -> String {
        switch (tab, mode) {
        case (.progress, .plain): "进度"
        case (.progress, .pro): "概览"
        case (.run, .plain): "运行"
        case (.run, .pro): "运行与测试"
        case (.version, .plain): "版本"
        case (.version, .pro): "Git"
        case (.info, _): "项目信息"
        }
    }

    static func focusSectionTitle(_ mode: CopyMode) -> String {
        switch mode {
        case .plain: "关注"
        case .pro: "星标"
        }
    }

    static func uncommittedChanges(count: Int? = nil, mode: CopyMode) -> TextWithHint {
        if let count {
            return TextWithHint(
                text: mode == .plain ? "有 \(count) 个改动还没存成版本" : "\(count) 个文件未提交",
                proHint: mode == .plain ? "Git 术语：未提交改动（\(count) 个文件）" : nil
            )
        }
        return TextWithHint(
            text: mode == .plain ? "有改动还没存成版本" : "未提交改动",
            proHint: mode == .plain ? "Git 术语：未提交改动" : nil
        )
    }

    static func commitAction(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? "存个版本" : "Commit",
            proHint: mode == .plain ? "Git 术语：Commit" : nil
        )
    }

    static func commitAndPushAction(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? "存个版本并上传" : "Commit & Push",
            proHint: mode == .plain ? "Git 术语：Commit & Push" : nil
        )
    }

    static func unpushed(count: Int? = nil, mode: CopyMode) -> TextWithHint {
        if let count {
            return TextWithHint(
                text: mode == .plain ? "存了 \(count) 个版本但还没上传" : "\(count) 个提交未推送",
                proHint: mode == .plain ? "Git 术语：未推送（\(count) 个 Commit）" : nil
            )
        }
        return TextWithHint(
            text: mode == .plain ? "存了但还没上传" : "未推送",
            proHint: mode == .plain ? "Git 术语：未推送" : nil
        )
    }

    static func behind(count: Int? = nil, mode: CopyMode) -> TextWithHint {
        if let count {
            return TextWithHint(
                text: mode == .plain ? "云端有 \(count) 个新内容" : "落后远端 \(count) 个提交",
                proHint: mode == .plain ? "Git 术语：落后远端 \(count) 个提交" : nil
            )
        }
        return TextWithHint(
            text: mode == .plain ? "云端有新内容" : "落后远端",
            proHint: mode == .plain ? "Git 术语：落后远端" : nil
        )
    }

    static func pullAction(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? "拿回云端的新内容" : "Pull",
            proHint: mode == .plain ? "Git 术语：Pull" : nil
        )
    }

    static func stashAction(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? "先把改动收起来" : "Stash",
            proHint: mode == .plain ? "Git 术语：Stash" : nil
        )
    }

    static func portOccupied(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? "有别的程序占了这个位置，项目开不起来" : "端口被占用",
            proHint: mode == .plain ? "专业术语：端口被占用" : nil
        )
    }

    static func missingDependencies(_ mode: CopyMode) -> TextWithHint {
        TextWithHint(
            text: mode == .plain ? "项目需要的零件还没装" : "node_modules 未安装",
            proHint: mode == .plain ? "专业术语：缺少依赖（node_modules 未安装）" : nil
        )
    }

    static func greeting(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<9: return "早上好"
        case 9..<12: return "上午好"
        case 12..<18: return "下午好"
        default: return "晚上好"
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
            if activeCount > 0 { parts.append("\(activeCount) 个活跃项目") }
            if brokenCount > 0 { parts.append("\(brokenCount) 个异常") }
            if attentionCount > 0 {
                parts.append("\(attentionCount) 项待处理")
            } else if parts.isEmpty {
                parts.append("暂无待处理")
            }
            return parts.joined(separator: " · ")
        }

        if brokenCount > 0 && activeCount > 0 {
            return "\(activeCount) 个项目在进行，\(brokenCount) 个跑不起来"
        }
        if brokenCount > 0 {
            return "\(brokenCount) 个项目跑不起来，点进去看看"
        }
        if activeCount > 0 && attentionCount > 0 {
            return "\(activeCount) 个项目在进行，\(attentionCount) 件事需要你看一下"
        }
        if activeCount > 0 {
            return "\(activeCount) 个项目在进行，状态都挺好"
        }
        if attentionCount > 0 {
            return "\(attentionCount) 件事需要你看一下"
        }
        return "一切顺利，没有需要处理的项目"
    }

    static func allClearTitle(_ mode: CopyMode) -> String {
        mode == .plain ? "都挺好的。要接着做哪个？" : "一切就绪"
    }

    static func weeklyOutputLabel(_ mode: CopyMode) -> String {
        mode == .plain ? "改动文件" : "本周提交"
    }

    static func continueWorkTitle(_ mode: CopyMode) -> String {
        mode == .plain ? "接着做" : "继续工作"
    }

    static func attentionTitle(_ mode: CopyMode) -> String {
        mode == .plain ? "需要你看一下" : "待处理"
    }

    static func timelineTitle(_ mode: CopyMode) -> String {
        mode == .plain ? "这周做了什么" : "本周活动"
    }

    static func costTitle(_ mode: CopyMode) -> String {
        mode == .plain ? "花了多少" : "AI 费用构成"
    }

    static func heatmapTitle(_ mode: CopyMode) -> String {
        mode == .plain ? "AI 活动热力" : "提交活跃度"
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
            return mode == .plain ? "当前代码很干净，改动都已存好" : "工作区干净"
        }
        return parts.joined(separator: "，")
    }
}
