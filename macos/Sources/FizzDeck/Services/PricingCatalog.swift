import Foundation

enum PricingCatalog {
    private struct Price {
        let input: Double
        let cachedInput: Double
        let cacheWrite: Double
        let output: Double
    }

    static func estimate(model: String?, usage: TokenUsage?) -> Double? {
        guard let model, let usage, !usage.isEmpty, let price = price(for: model) else {
            return nil
        }

        let cached = min(usage.cachedInputTokens, usage.inputTokens)
        let regular = max(0, usage.inputTokens - cached)
        let inputCost = Double(regular) / 1_000_000 * price.input
        let cachedCost = Double(cached) / 1_000_000 * price.cachedInput
        let cacheWriteCost = Double(usage.cacheWriteInputTokens) / 1_000_000 * price.cacheWrite
        let outputCost = Double(usage.outputTokens) / 1_000_000 * price.output
        return inputCost + cachedCost + cacheWriteCost + outputCost
    }

    private static func price(for model: String) -> Price? {
        let name = model.lowercased()

        if name.contains("gpt-5.4") || name.contains("gpt-5.3") || name.contains("gpt-5.2") || name.contains("gpt-5.1") || name.contains("gpt-5-1") || name.hasSuffix("/gpt-5") || name == "gpt-5" {
            return Price(input: 1.25, cachedInput: 0.125, cacheWrite: 0, output: 10)
        }
        if name.contains("gpt-5-mini") {
            return Price(input: 0.25, cachedInput: 0.025, cacheWrite: 0, output: 2)
        }
        if name.contains("gpt-5-nano") {
            return Price(input: 0.05, cachedInput: 0.005, cacheWrite: 0, output: 0.4)
        }
        if name.contains("gpt-4.1") || name.contains("gpt-4-1") {
            return Price(input: 2, cachedInput: 0.5, cacheWrite: 0, output: 8)
        }
        if name.contains("gpt-4o") {
            return Price(input: 2.5, cachedInput: 1.25, cacheWrite: 0, output: 10)
        }
        if name.contains("claude-opus-5") || name.contains("claude-opus-4-5") || name.contains("claude-opus-4") {
            return Price(input: 15, cachedInput: 1.5, cacheWrite: 18.75, output: 75)
        }
        if name.contains("claude-sonnet-4") {
            return Price(input: 3, cachedInput: 0.3, cacheWrite: 3.75, output: 15)
        }
        if name.contains("claude-haiku-4-5") || name.contains("claude-haiku-4.5") {
            return Price(input: 1, cachedInput: 0.1, cacheWrite: 1.25, output: 5)
        }
        if name.contains("deepseek") {
            if name.contains("reasoner") || name.contains("r1") || name.contains("v4-pro") {
                return Price(input: 0.55, cachedInput: 0.14, cacheWrite: 0, output: 2.19)
            }
            if name.contains("flash") {
                return Price(input: 0.14, cachedInput: 0.014, cacheWrite: 0, output: 0.28)
            }
            return Price(input: 0.28, cachedInput: 0.028, cacheWrite: 0, output: 0.42)
        }
        if name.contains("gemini") {
            if name.contains("flash") {
                return Price(input: 0.15, cachedInput: 0.0375, cacheWrite: 0, output: 0.60)
            }
            return Price(input: 1.25, cachedInput: 0.31, cacheWrite: 0, output: 10)
        }
        if name.contains("grok") {
            if name.contains("mini") || name.contains("fast") {
                return Price(input: 0.30, cachedInput: 0.075, cacheWrite: 0, output: 0.50)
            }
            return Price(input: 3, cachedInput: 0.75, cacheWrite: 0, output: 15)
        }
        return nil
    }
}
