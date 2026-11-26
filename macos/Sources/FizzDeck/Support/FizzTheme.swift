import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "暗色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AppearancePreferences {
    static let key = "fizzdeck.appearance"

    static func appearance(in defaults: UserDefaults = .standard) -> AppAppearance {
        guard let raw = defaults.string(forKey: key) else { return .system }
        return AppAppearance(rawValue: raw) ?? .system
    }

    static func set(_ appearance: AppAppearance, in defaults: UserDefaults = .standard) {
        defaults.set(appearance.rawValue, forKey: key)
    }

    @MainActor
    static func apply(_ appearance: AppAppearance) {
        NSApp.appearance = appearance.nsAppearance
    }

    @MainActor
    static func applyStoredAppearance() {
        apply(appearance())
    }
}

enum FizzRadius {
    static let frame: CGFloat = 16
    static let panel: CGFloat = 16
    static let card: CGFloat = 14
    static let inset: CGFloat = 10
    static let control: CGFloat = 8
    static let micro: CGFloat = 4
}

enum FizzSpacing {
    static let page: CGFloat = 24
    static let section: CGFloat = 20
    static let panel: CGFloat = 16
    static let grid: CGFloat = 12
    static let row: CGFloat = 8
}

enum FizzElevation {
    case subtle
    case raised
    case floating

    struct Metrics: Equatable {
        let opacity: Double
        let radius: CGFloat
        let y: CGFloat
    }

    func metrics(for colorScheme: ColorScheme) -> Metrics {
        switch (self, colorScheme) {
        case (.subtle, .dark):
            Metrics(opacity: 0.16, radius: 3, y: 1)
        case (.subtle, _):
            Metrics(opacity: 0.04, radius: 6, y: 2)
        case (.raised, .dark):
            Metrics(opacity: 0.20, radius: 6, y: 2)
        case (.raised, _):
            Metrics(opacity: 0.08, radius: 12, y: 4)
        case (.floating, .dark):
            Metrics(opacity: 0.24, radius: 16, y: 6)
        case (.floating, _):
            Metrics(opacity: 0.16, radius: 30, y: 14)
        }
    }
}

enum FizzTheme {
    static let accent = Color(red: 100 / 255, green: 56 / 255, blue: 255 / 255)
    static let page = fizzAdaptiveColor(light: 0xF8F8F7, dark: 0x111315)
    static let sidebar = fizzAdaptiveColor(light: 0xF7F6F6, dark: 0x16181A)
    static let warmGlow = Color(red: 1.00, green: 0.65, blue: 0.68)
    static let coolGlow = Color(red: 0.67, green: 0.58, blue: 0.98)
    static let hairline = fizzAdaptiveColor(
        light: NSColor.black.withAlphaComponent(0.065),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let stroke = fizzAdaptiveColor(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.07)
    )
    static let selectedFill = fizzAdaptiveColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let cardFill = fizzAdaptiveColor(light: 0xFFFFFF, dark: 0x1B1D20)
    static let recessedFill = fizzAdaptiveColor(light: 0xF3F3F2, dark: 0x131517)
    static let elevatedFill = fizzAdaptiveColor(light: 0xFFFFFF, dark: 0x25282C)
    static let mutedFill = fizzAdaptiveColor(
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.white.withAlphaComponent(0.05)
    )
}

private func fizzAdaptiveColor(light: UInt32, dark: UInt32) -> Color {
    fizzAdaptiveColor(light: fizzHexColor(light), dark: fizzHexColor(dark))
}

private func fizzAdaptiveColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

private func fizzHexColor(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

enum FizzMotion {
    static let quick = Animation.snappy(duration: 0.16)
    static let standard = Animation.snappy(duration: 0.22)
    static let panel = Animation.easeOut(duration: 0.12)

    static func resolved(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

enum FizzAsset {
    static let logo: NSImage? = {
        if let url = Bundle.main.url(forResource: "FizzDeck_logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        let direct = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/FizzDeck_logo.png")
        if let image = NSImage(contentsOf: direct) {
            return image
        }

        let nested = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("macos/Resources/FizzDeck_logo.png")
        return NSImage(contentsOf: nested)
    }()
}

struct FizzBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            FizzTheme.page

            RadialGradient(
                colors: [FizzTheme.warmGlow.opacity(colorScheme == .dark ? 0.06 : 0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 470
            )

            RadialGradient(
                colors: [FizzTheme.coolGlow.opacity(colorScheme == .dark ? 0.06 : 0.14), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 680
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct FizzLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: CGFloat = 30

    var body: some View {
        Group {
            if let image = FizzAsset.logo {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .background(logoPlate)
            } else {
                ZStack {
                    FizzTheme.accent
                    FizzIcon(symbol: "bubble.left.fill", size: size * 0.43)
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }

    private var logoPlate: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(colorScheme == .dark ? Color(white: 0.95) : Color(white: 0.99))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.black.opacity(0.10) : FizzTheme.stroke,
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func fizzCard(
        radius: CGFloat = FizzRadius.panel,
        fill: Color = FizzTheme.cardFill
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }
    }

    func fizzAdaptiveShadow(_ level: FizzElevation = .subtle) -> some View {
        modifier(FizzAdaptiveShadowModifier(level: level))
    }
}

private struct FizzAdaptiveShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let level: FizzElevation

    func body(content: Content) -> some View {
        let metrics = level.metrics(for: colorScheme)
        content.shadow(
            color: .black.opacity(metrics.opacity),
            radius: metrics.radius,
            y: metrics.y
        )
    }
}
