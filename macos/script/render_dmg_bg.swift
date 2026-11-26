#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: render_dmg_bg.swift <output-dir>\n", stderr)
    exit(2)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let baseWidth = 660
let baseHeight = 420

func renderPNG(scale: Int, to url: URL) throws {
    let pixelWidth = baseWidth * scale
    let pixelHeight = baseHeight * scale

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "DMGRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bitmap"])
    }
    rep.size = NSSize(width: baseWidth, height: baseHeight)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "DMGRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    // Flip to top-left origin matching 660x420 SVG coordinates
    cg.translateBy(x: 0, y: CGFloat(baseHeight))
    cg.scaleBy(x: 1, y: -1)

    drawBackground(in: cg)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DMGRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try png.write(to: url, options: .atomic)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawBackground(in cg: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: baseWidth, height: baseHeight)
    let space = CGColorSpaceCreateDeviceRGB()

    // Base soft gradient
    if let baseGrad = CGGradient(
        colorsSpace: space,
        colors: [color(0xFAF9F7).cgColor, color(0xF2F1EE).cgColor] as CFArray,
        locations: [0, 1]
    ) {
        cg.drawLinearGradient(baseGrad, start: .zero, end: CGPoint(x: baseWidth, y: baseHeight), options: [])
    }

    // Subtle corner glows
    drawGlow(in: cg, space: space, center: CGPoint(x: 80, y: 60), radius: 300, hex: 0xFFA6AD, alpha: 0.14)
    drawGlow(in: cg, space: space, center: CGPoint(x: 590, y: 70), radius: 320, hex: 0x6438FF, alpha: 0.11)

    // Floating minimal project-card fragments (no mascots)
    drawCardFragment(in: cg, origin: CGPoint(x: 534, y: 72), size: CGSize(width: 58, height: 38), angleDeg: 14, dotHex: 0x6438FF, opacity: 0.65)
    drawCardFragment(in: cg, origin: CGPoint(x: 410, y: 42), size: CGSize(width: 52, height: 34), angleDeg: -10, dotHex: 0x16A34A, opacity: 0.58)
    drawCardFragment(in: cg, origin: CGPoint(x: 86, y: 296), size: CGSize(width: 54, height: 35), angleDeg: -13, dotHex: 0xF59E0B, opacity: 0.60)

    // Dotted double-bounce arc
    cg.saveGState()
    cg.setStrokeColor(color(0x111315, alpha: 0.28).cgColor)
    cg.setLineWidth(2.5)
    cg.setLineCap(.round)
    cg.setLineDash(phase: 0, lengths: [2, 7.5])
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 238, y: 196))
    arc.addQuadCurve(to: CGPoint(x: 330, y: 212), control: CGPoint(x: 284, y: 134))
    arc.addQuadCurve(to: CGPoint(x: 422, y: 196), control: CGPoint(x: 376, y: 134))
    cg.addPath(arc)
    cg.strokePath()
    cg.restoreGState()

    // Bounce impact ticks
    cg.saveGState()
    cg.setStrokeColor(color(0x111315, alpha: 0.24).cgColor)
    cg.setLineWidth(1.6)
    cg.setLineCap(.round)
    let ticks: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 330, y: 222), CGPoint(x: 330, y: 229)),
        (CGPoint(x: 322, y: 220), CGPoint(x: 318, y: 226)),
        (CGPoint(x: 338, y: 220), CGPoint(x: 342, y: 226)),
    ]
    for (p1, p2) in ticks {
        cg.move(to: p1)
        cg.addLine(to: p2)
    }
    cg.strokePath()
    cg.restoreGState()

    // Neutral frosted label capsules under icon slots for Light/Dark Finder label contrast
    drawPill(in: cg, rect: CGRect(x: 118, y: 256, width: 124, height: 24), fill: color(0x9E9BAA, alpha: 0.32).cgColor)
    drawPill(in: cg, rect: CGRect(x: 418, y: 256, width: 124, height: 24), fill: color(0x9E9BAA, alpha: 0.32).cgColor)

    // Centered Headline: "Drag FizzDeck to Applications" with gradient FizzDeck
    drawHeadline(in: cg, space: space, rect: rect)

    // Gatekeeper hint subtitle
    let subtitle = NSAttributedString(
        string: "首次打开如提示未公证：右键 → 打开",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: color(0x18191C, alpha: 0.52),
        ]
    )
    let subSize = subtitle.size()
    subtitle.draw(at: NSPoint(x: (CGFloat(baseWidth) - subSize.width) / 2, y: 350))
}

func drawGlow(
    in cg: CGContext,
    space: CGColorSpace,
    center: CGPoint,
    radius: CGFloat,
    hex: UInt32,
    alpha: CGFloat
) {
    guard let grad = CGGradient(
        colorsSpace: space,
        colors: [color(hex, alpha: alpha).cgColor, color(hex, alpha: 0).cgColor] as CFArray,
        locations: [0, 1]
    ) else { return }
    cg.drawRadialGradient(
        grad,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
}

func drawCardFragment(
    in cg: CGContext,
    origin: CGPoint,
    size: CGSize,
    angleDeg: CGFloat,
    dotHex: UInt32,
    opacity: CGFloat
) {
    cg.saveGState()
    cg.translateBy(x: origin.x, y: origin.y)
    cg.rotate(by: angleDeg * .pi / 180)
    cg.setAlpha(opacity)

    let cardRect = CGRect(origin: .zero, size: size)
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 9, cornerHeight: 9, transform: nil)
    cg.addPath(cardPath)
    cg.setFillColor(color(0xFFFFFF, alpha: 0.85).cgColor)
    cg.fillPath()

    cg.addPath(cardPath)
    cg.setStrokeColor(color(0x111315, alpha: 0.09).cgColor)
    cg.setLineWidth(1)
    cg.strokePath()

    // Accent dot
    cg.setFillColor(color(dotHex).cgColor)
    cg.fillEllipse(in: CGRect(x: 9, y: 9, width: 8, height: 8))

    // Two minimal text lines
    let line1 = CGPath(roundedRect: CGRect(x: 21, y: 10.5, width: size.width - 30, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
    cg.addPath(line1)
    cg.setFillColor(color(0x111315, alpha: 0.14).cgColor)
    cg.fillPath()

    let line2 = CGPath(roundedRect: CGRect(x: 9, y: 22, width: size.width - 20, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil)
    cg.addPath(line2)
    cg.setFillColor(color(0x111315, alpha: 0.08).cgColor)
    cg.fillPath()

    cg.restoreGState()
}

func drawPill(in cg: CGContext, rect: CGRect, fill: CGColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
    cg.saveGState()
    cg.addPath(path)
    cg.setFillColor(fill)
    cg.fillPath()
    cg.restoreGState()
}

func drawHeadline(in cg: CGContext, space: CGColorSpace, rect: CGRect) {
    let baseFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
    let brandFont = NSFont.systemFont(ofSize: 20, weight: .bold)
    let textColor = color(0x18191C)

    let part1 = NSAttributedString(string: "Drag ", attributes: [.font: baseFont, .foregroundColor: textColor])
    let part2 = NSAttributedString(string: "FizzDeck", attributes: [.font: brandFont, .foregroundColor: NSColor.black])
    let part3 = NSAttributedString(string: " to Applications", attributes: [.font: baseFont, .foregroundColor: textColor])

    let totalWidth = part1.size().width + part2.size().width + part3.size().width
    let startX = (CGFloat(baseWidth) - totalWidth) / 2
    let y: CGFloat = 318

    part1.draw(at: NSPoint(x: startX, y: y))
    part3.draw(at: NSPoint(x: startX + part1.size().width + part2.size().width, y: y))

    // Draw "FizzDeck" with gradient mask
    let brandRect = CGRect(
        x: startX + part1.size().width,
        y: y,
        width: ceil(part2.size().width),
        height: ceil(part2.size().height) + 4
    )

    cg.saveGState()
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    part2.draw(at: brandRect.origin)
    cg.setBlendMode(.sourceIn)
    if let grad = CGGradient(
        colorsSpace: space,
        colors: [color(0x6438FF).cgColor, color(0xD9468F).cgColor, color(0xFF7A59).cgColor] as CFArray,
        locations: [0, 0.52, 1]
    ) {
        cg.drawLinearGradient(
            grad,
            start: CGPoint(x: brandRect.minX, y: brandRect.midY),
            end: CGPoint(x: brandRect.maxX, y: brandRect.midY),
            options: []
        )
    }
    cg.endTransparencyLayer()
    cg.restoreGState()
}

let png1x = outputDir.appendingPathComponent("background@1x.png")
let png2x = outputDir.appendingPathComponent("background@2x.png")
let tiffOut = outputDir.appendingPathComponent("background.tiff")

try renderPNG(scale: 1, to: png1x)
try renderPNG(scale: 2, to: png2x)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
proc.arguments = ["-cathidpicheck", png1x.path, png2x.path, "-out", tiffOut.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else {
    fputs("tiffutil failed with status \(proc.terminationStatus)\n", stderr)
    exit(1)
}
