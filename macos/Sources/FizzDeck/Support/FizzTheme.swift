import AppKit
import SwiftUI

enum FizzTheme {
    static let accent = Color(red: 100 / 255, green: 56 / 255, blue: 255 / 255)
    static let page = Color(red: 248 / 255, green: 248 / 255, blue: 247 / 255)
    static let sidebar = Color(red: 247 / 255, green: 246 / 255, blue: 246 / 255)
    static let warmGlow = Color(red: 1.00, green: 0.65, blue: 0.68)
    static let coolGlow = Color(red: 0.67, green: 0.58, blue: 0.98)
    static let hairline = Color.black.opacity(0.065)
    static let stroke = Color.black.opacity(0.06)
    static let selectedFill = Color.black.opacity(0.055)
    static let cardFill = Color.white
    static let mutedFill = Color.black.opacity(0.035)
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
    var body: some View {
        ZStack {
            FizzTheme.page

            RadialGradient(
                colors: [FizzTheme.warmGlow.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 470
            )

            RadialGradient(
                colors: [FizzTheme.coolGlow.opacity(0.14), .clear],
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
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let image = FizzAsset.logo {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ZStack {
                    FizzTheme.accent
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: size * 0.43, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

extension View {
    func fizzCard(
        radius: CGFloat = 16,
        fill: Color = FizzTheme.cardFill
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FizzTheme.stroke, lineWidth: 1)
            }
    }
}
