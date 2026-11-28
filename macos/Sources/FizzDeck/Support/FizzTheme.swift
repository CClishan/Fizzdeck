import AppKit
import CoreText
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: FizzL10n.text("跟随系统", "Follow System")
        case .light: FizzL10n.text("浅色", "Light")
        case .dark: FizzL10n.text("暗色", "Dark")
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
    static let card: CGFloat = 12
    static let grid: CGFloat = 12
    static let row: CGFloat = 8
}

enum FizzIconSize: CGFloat, CaseIterable {
    case xs = 10
    case sm = 12
    case md = 14
    case lg = 22
}

@MainActor enum FizzTypography {
    enum Weight: String, CaseIterable {
        case regular = "Regular", medium = "Medium", semibold = "SemiBold", bold = "Bold"

        fileprivate var systemWeight: NSFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    private static let descriptors: [Weight: CTFontDescriptor] = {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        // The packaged executable ships Fonts directly; it has no SwiftPM resource bundle.
        let main = Bundle.main
        bundle = main.bundleURL.pathExtension == "app" && main.executableURL?.lastPathComponent == "FizzDeck" ? main : .module
        #else
        bundle = .main
        #endif
        return Dictionary(uniqueKeysWithValues: Weight.allCases.map { weight in
            let name = "ObelMono-\(weight.rawValue)"
            guard let url = bundle.url(forResource: name, withExtension: "otf", subdirectory: "Fonts") else {
                fatalError("Missing Fonts/\(name).otf in \(bundle.bundlePath)")
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                guard let failure = error?.takeRetainedValue() else { fatalError("Could not register \(url.path)") }
                // ATS can already have registered this URL on app launch.
                guard CFErrorGetDomain(failure) == kCTFontManagerErrorDomain,
                      CFErrorGetCode(failure) == CTFontManagerError.alreadyRegistered.rawValue else {
                    fatalError("Could not register \(url.path): \(failure)")
                }
            }
            guard let file = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [NSFontDescriptor])?.first,
                  file.postscriptName == name else { fatalError("Invalid font at \(url.path); expected \(name)") }

            let system = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: weight.systemWeight)
            // A generic cascade substitutes Semibold for Bold. Use the actual Chinese UI face.
            let chinese = CTFontCreateForStringWithLanguage(
                system, "汉" as CFString, CFRange(location: 0, length: 1), "zh-Hans" as CFString
            ) as NSFont
            let descriptor = file.addingAttributes([.cascadeList: [chinese.fontDescriptor, system.fontDescriptor]]) as CTFontDescriptor
            let face = CTFontCreateWithFontDescriptor(descriptor, NSFont.systemFontSize, nil)
            guard let source = CTFontCopyAttribute(face, kCTFontURLAttribute) as? URL,
                  source.standardizedFileURL == url.standardizedFileURL else { fatalError("CoreText substituted \(url.path)") }
            return (weight, descriptor)
        })
    }()

    static func registerBundledFonts() { _ = descriptors }

    static func font(_ size: CGFloat, weight: Weight = .regular) -> Font {
        Font(CTFontCreateWithFontDescriptor(descriptors[weight]!, size, nil))
    }

    static let pageTitle = font(22, weight: .semibold)
    static let sectionTitle = sectionTitle(.semibold)
    static let cardTitle = font(13, weight: .semibold)
    static let body = body(.regular)
    static let caption = caption(.regular)
    static let micro = micro(.medium)
    static let mono = mono(.regular)
    static let monoSmall = monoSmall(.regular)

    static func sectionTitle(_ weight: Weight) -> Font { font(14, weight: weight) }
    static func body(_ weight: Weight) -> Font { font(12.5, weight: weight) }
    static func caption(_ weight: Weight) -> Font { font(11, weight: weight) }
    static func micro(_ weight: Weight) -> Font { font(10, weight: weight) }
    static func mono(_ weight: Weight) -> Font { font(11.5, weight: weight) }
    static func monoSmall(_ weight: Weight) -> Font { font(10.5, weight: weight) }
}

enum FizzControlHeight: CGFloat, CaseIterable {
    case standard = 28
    case compact = 24
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
    private static let accentLight = fizzHexColor(0x6941E8)
    private static let accentDark = fizzHexColor(0x9F82FF)
    static let accent = fizzAdaptiveColor(light: accentLight, dark: accentDark)
    static let accentSoft = fizzAdaptiveColor(
        light: accentLight.withAlphaComponent(0.10), dark: accentDark.withAlphaComponent(0.16)
    )
    static let statusDanger = fizzAdaptiveColor(light: 0xDC3848, dark: 0xFF6B78)
    static let statusWarning = fizzAdaptiveColor(light: 0xCF6E0C, dark: 0xFFA940)
    static let statusSuccess = fizzAdaptiveColor(light: 0x159662, dark: 0x38D399)
    static let page = fizzAdaptiveColor(light: 0xFFFFFF, dark: 0x111316)
    static let sidebar = fizzAdaptiveColor(light: 0xF8F9FB, dark: 0x16191F)
    static let hairline = fizzAdaptiveColor(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.09)
    )
    static let stroke = fizzAdaptiveColor(
        light: NSColor.black.withAlphaComponent(0.085),
        dark: NSColor.white.withAlphaComponent(0.09)
    )
    static let selectedFill = fizzAdaptiveColor(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    static let cardFill = fizzAdaptiveColor(light: 0xFFFFFF, dark: 0x1A1D23)
    static let recessedFill = fizzAdaptiveColor(light: 0xF4F5F7, dark: 0x14171B)
    static let elevatedFill = fizzAdaptiveColor(light: 0xFFFFFF, dark: 0x242830)
    static let mutedFill = fizzAdaptiveColor(
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
}

enum ProjectAccentColor {
    static let mauve = fizzAdaptiveColor(light: 0x744CE8, dark: 0xA88BFF)
    static let slate = fizzAdaptiveColor(light: 0x2B6EF2, dark: 0x6BA4FF)
    static let sage = fizzAdaptiveColor(light: 0x0E9384, dark: 0x35D8C0)
    private static let olive = fizzAdaptiveColor(light: 0x1D9A56, dark: 0x4CE08A)
    static let ochre = fizzAdaptiveColor(light: 0xD96218, dark: 0xFF984F)
    static let rose = fizzAdaptiveColor(light: 0xD9327A, dark: 0xFF70B5)
    private static let palette = [mauve, slate, sage, olive, ochre, rose]

    static func color(for projectID: String) -> Color {
        // FNV-1a keeps project colors stable between launches.
        let hash = projectID.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return palette[Int(hash % UInt32(palette.count))]
    }
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
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let morph = Animation.spring(response: 0.38, dampingFraction: 0.82)

    static func resolved(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

enum FizzAsset {
    private static let pngLogo = loadImage(named: "FizzDeck_logo", extension: "png")
    private static let lightLogo = loadImage(named: logoResourceName(for: .light), extension: "svg") ?? pngLogo
    private static let darkLogo = loadImage(named: logoResourceName(for: .dark), extension: "svg") ?? pngLogo

    static func logo(for colorScheme: ColorScheme) -> NSImage? {
        colorScheme == .dark ? darkLogo : lightLogo
    }

    static func logoResourceName(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "FizzDeck_logo_dark" : "FizzDeck_logo_light"
    }

    private static func loadImage(named name: String, extension fileExtension: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
           let image = NSImage(contentsOf: url) {
            return image
        }

        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for directory in ["Resources", "macos/Resources"] {
            let url = current
                .appendingPathComponent(directory)
                .appendingPathComponent("\(name).\(fileExtension)")
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}

struct FizzBackground: View {
    var body: some View {
        FizzTheme.page.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct FizzLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: CGFloat = 30

    private var fallbackIconSize: FizzIconSize {
        switch size {
        case ..<24: .xs
        case ..<40: .sm
        case ..<48: .md
        default: .lg
        }
    }

    var body: some View {
        Group {
            if let image = FizzAsset.logo(for: colorScheme) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    FizzTheme.elevatedFill
                    FizzIcon(fallbackIconSize, symbol: "bubble.left.fill")
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(width: size, height: size)
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
