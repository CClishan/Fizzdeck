import Foundation

enum StackDetector {
    private static let languageKeys = [
        "TS", "JS", "TypeScript", "JavaScript", "React", "Vue", "Svelte", "Astro",
        "Vite", "Java", "Android", "uni-app", "Node", "Go", "Python", "Rust",
    ]
    private static let frameworkKeys = [
        "Next.js", "TanStack Start", "SvelteKit", "Astro", "Nuxt", "RuoYi",
        "Spring Boot", "Gradle", "Go Module", "Cargo",
    ]
    private static let infrastructureKeys = [
        "Cloudflare", "D1", "R2", "KV", "Drizzle", "Stripe", "Auth", "MQTT", "Docker",
    ]
    private static let featureKeys = ["GSAP", "WebGL", "SSG", "Agent Skill"]

    static func detect(_ directory: URL) -> [StackGroup] {
        var languages: [String] = []
        var frameworks: [String] = []
        var tags: [String] = []

        func add(_ target: inout [String], _ value: String) {
            if !target.contains(value) { target.append(value) }
        }
        func has(_ name: String) -> Bool {
            FileTools.exists(directory.appendingPathComponent(name))
        }

        if has("tsconfig.json") || has("next-env.d.ts") { add(&languages, "TS") }
        if has("jsconfig.json") { add(&languages, "JS") }
        if has("astro.config.mjs") || has("astro.config.ts") { add(&frameworks, "Astro") }
        if has("svelte.config.js") {
            add(&languages, "Svelte")
            add(&frameworks, "SvelteKit")
        }
        if has("vite.config.js") || has("vite.config.ts") { add(&languages, "Vite") }
        if has("pom.xml") {
            add(&languages, "Java")
            add(&frameworks, "Spring Boot")
        }
        if has("build.gradle") {
            add(&languages, "Android")
            add(&frameworks, "Gradle")
        }
        if has("manifest.json") && has("pages") { add(&languages, "uni-app") }
        if has("go.mod") {
            add(&languages, "Go")
            add(&frameworks, "Go Module")
        }
        if has("requirements.txt") || has("pyproject.toml") { add(&languages, "Python") }
        if has("Cargo.toml") {
            add(&languages, "Rust")
            add(&frameworks, "Cargo")
        }
        if has("Dockerfile") || has("docker-compose.yml") { add(&tags, "Docker") }
        if has("SKILL.md") || has(".agents") { add(&tags, "Agent Skill") }

        var dependencies = Set<String>()
        if let package = FileTools.json(directory.appendingPathComponent("package.json")) {
            for key in ["dependencies", "devDependencies"] {
                if let values = package[key] as? [String: Any] {
                    dependencies.formUnion(values.keys)
                }
            }
        }
        func dependency(_ name: String) -> Bool { dependencies.contains(name) }

        if dependency("next") { add(&frameworks, "Next.js") }
        if dependency("react") { add(&languages, "React") }
        if dependency("vue") { add(&languages, "Vue") }
        if dependency("@tanstack/react-start") {
            add(&frameworks, "TanStack Start")
            add(&tags, "Cloudflare")
        }
        if dependency("svelte") { add(&languages, "Svelte") }
        if dependency("wrangler") || has("wrangler.toml") || has("wrangler.json") || has("wrangler.jsonc") {
            add(&tags, "Cloudflare")
        }

        let wrangler = ["wrangler.toml", "wrangler.json", "wrangler.jsonc"]
            .map { FileTools.readFileIfExists(directory.appendingPathComponent($0), maxBytes: 64 * 1024) }
            .joined()
        if wrangler.range(of: "d1_databases", options: .regularExpression) != nil { add(&tags, "D1") }
        if wrangler.range(of: "r2_buckets", options: .regularExpression) != nil { add(&tags, "R2") }
        if wrangler.range(of: "kv_namespaces", options: .regularExpression) != nil { add(&tags, "KV") }
        if dependency("drizzle-orm") { add(&tags, "Drizzle") }
        if dependency("stripe") { add(&tags, "Stripe") }
        if dependency("better-auth") { add(&tags, "Auth") }
        if dependency("gsap") { add(&tags, "GSAP") }
        if dependency("three") || has("src/lib/gl") { add(&tags, "WebGL") }
        if FileTools.readFileIfExists(directory.appendingPathComponent("svelte.config.js"))
            .range(of: "adapter-static", options: .regularExpression) != nil {
            add(&tags, "SSG")
        }

        let scanned = FileTools.readFileIfExists(directory.appendingPathComponent("build.mjs"))
            + FileTools.head(directory.appendingPathComponent("README.md"), bytes: 500)
        if scanned.range(of: #"node:|from 'node:|require\("#, options: .regularExpression) != nil {
            add(&languages, "Node")
        }
        if languages.isEmpty { languages.append("其他") }

        let all = frameworks + languages + tags
        func take(_ keys: [String]) -> [String] { all.filter { keys.contains($0) } }
        let classified = Set(languageKeys + frameworkKeys + infrastructureKeys + featureKeys)
        let rest = all.filter { !classified.contains($0) }

        return [
            StackGroup(key: "framework", label: "框架", items: take(frameworkKeys)),
            StackGroup(key: "language", label: "语言", items: take(languageKeys)),
            StackGroup(key: "infra", label: "基础设施", items: take(infrastructureKeys)),
            StackGroup(key: "feature", label: "能力", items: take(featureKeys) + rest),
        ].filter { !$0.items.isEmpty }
    }
}
