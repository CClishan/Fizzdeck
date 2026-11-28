import SwiftUI

enum ProjectBadgeKind: String, CaseIterable, Sendable {
    case next
    case vite
    case react
    case vue
    case svelte
    case astro
    case nuxt
    case swift
    case flutter
    case game
    case go
    case rust
    case python
    case docker
    case cloudflare
    case cli
    case web
    case miniProgram
    case other

    static func resolve(stacks: [StackGroup], kind: ProjectKind) -> ProjectBadgeKind {
        let items = Set(stacks.flatMap(\.items).map { $0.lowercased() })
        func has(_ values: [String]) -> Bool {
            values.contains(where: items.contains)
        }

        if has(["next.js", "next"]) { return .next }
        if has(["nuxt"]) { return .nuxt }
        if has(["sveltekit", "svelte"]) { return .svelte }
        if has(["astro"]) { return .astro }
        if has(["vue"]) { return .vue }
        if has(["react", "react native"]) { return .react }
        if has(["vite"]) { return .vite }

        if has(["swift", "swiftui", "appkit"]) { return .swift }
        if has(["flutter"]) { return .flutter }
        if has(["unity", "godot", "unreal"]) { return .game }
        if has(["go", "golang", "go module"]) { return .go }
        if has(["rust", "cargo"]) { return .rust }
        if has(["python", "django", "flask", "fastapi"]) { return .python }
        if has(["docker", "docker-compose"]) { return .docker }
        if has(["cloudflare", "d1", "r2", "kv"]) { return .cloudflare }

        return switch kind {
        case .macApp: .swift
        case .flutter: .flutter
        case .game: .game
        case .cli: .cli
        case .miniProgram: .miniProgram
        case .web: .web
        case .other: .other
        }
    }

    var title: String {
        switch self {
        case .next: "Next.js"
        case .vite: "Vite"
        case .react: "React"
        case .vue: "Vue"
        case .svelte: "Svelte"
        case .astro: "Astro"
        case .nuxt: "Nuxt"
        case .swift: "Swift"
        case .flutter: "Flutter"
        case .game: "Game"
        case .go: "Go"
        case .rust: "Rust"
        case .python: "Python"
        case .docker: "Docker"
        case .cloudflare: "Cloudflare"
        case .cli: "CLI"
        case .web: "Web"
        case .miniProgram: "Mini Program"
        case .other: "Project"
        }
    }

    var badgeText: String? {
        switch self {
        case .next, .react, .vite, .swift, .game, .docker, .cloudflare, .cli, .web, .other:
            nil
        case .vue: "V"
        case .svelte: "S"
        case .astro: "A"
        case .nuxt: "N"
        case .flutter: "F"
        case .go: "G"
        case .rust: "R"
        case .python: "P"
        case .miniProgram: "M"
        }
    }

    var symbol: String? {
        switch self {
        case .next: "triangle.fill"
        case .vite: "bolt.fill"
        case .react: "atom"
        case .swift: "swift"
        case .game: "gamecontroller.fill"
        case .docker: "shippingbox.fill"
        case .cloudflare: "cloud.fill"
        case .cli: "terminal.fill"
        case .web: "globe"
        case .other: "folder.fill"
        case .vue, .svelte, .astro, .nuxt, .flutter, .go, .rust, .python, .miniProgram:
            nil
        }
    }

}

struct ProjectBadgeIcon: View {
    let project: RepoProject
    var size: CGFloat = 30
    var framed: Bool = true

    private var kind: ProjectBadgeKind {
        ProjectBadgeKind.resolve(stacks: project.stacks, kind: project.kind)
    }

    private var symbolSize: FizzIconSize {
        switch size {
        case ..<20: .xs
        case ..<32: .sm
        case ..<48: .md
        default: .lg
        }
    }

    var body: some View {
        ZStack {
            if framed {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(FizzTheme.elevatedFill)

                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }

            glyph
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let tag = project.color {
                Circle().fill(tag.color).frame(width: 6, height: 6)
                    .help(tag.label)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if let text = kind.badgeText {
            Text(text)
                .font(FizzTypography.font(size * (framed ? 0.42 : 0.56), weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if let symbol = kind.symbol {
            FizzIcon(symbolSize, symbol: symbol)
                .foregroundStyle(.secondary)
        }
    }

}
