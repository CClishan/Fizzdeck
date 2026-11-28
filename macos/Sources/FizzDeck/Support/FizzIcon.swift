import AppKit
import SwiftUI

struct FizzIcon: View {
    let symbol: String
    private let side: CGFloat

    init(_ size: FizzIconSize, symbol: String) {
        self.symbol = symbol
        self.side = size.rawValue
    }

    var body: some View {
        if let image = FizzIconAsset.image(for: symbol) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .renderingMode(.template)
                .frame(width: side, height: side)
        } else {
            Image(systemName: symbol)
                .font(.system(size: side, weight: .medium))
                .frame(width: side, height: side)
        }
    }

    static func hasBundledAsset(for symbol: String) -> Bool {
        FizzIconAsset.image(for: symbol) != nil
    }
}

private enum FizzIconAsset {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    private static let aliases: [String: String] = [
        "archivebox": "archive",
        "arrow.clockwise": "refresh",
        "arrow.clockwise.circle.fill": "refresh",
        "arrow.down": "arrow-down",
        "arrow.down.circle": "circle-arrow-down",
        "arrow.left": "arrow-left",
        "arrow.right": "arrow-right",
        "arrow.right.circle": "circle-arrow-right",
        "arrow.triangle.2.circlepath": "refresh",
        "arrow.triangle.branch": "git-branch",
        "arrow.triangle.merge": "git-merge",
        "arrow.up": "arrow-up",
        "arrow.up.circle": "circle-arrow-up",
        "arrow.up.forward.app": "external-link",
        "arrow.up.forward.square": "external-link",
        "arrow.up.right": "arrow-up-right",
        "arrow.up.right.square": "external-link",
        "arrow.uturn.backward": "undo",
        "arrow.uturn.backward.circle.fill": "undo",
        "at": "mention",
        "atom": "atom",
        "bell": "bell",
        "bell.slash": "bell-off",
        "bolt": "zap",
        "bolt.horizontal": "zap",
        "bookmark": "bookmark",
        "bookmark.circle": "bookmark",
        "bubble.left.and.bubble.right": "message",
        "bubble.left.and.text.bubble.right": "message",
        "bubble.left.fill": "message",
        "calendar": "calendar",
        "calendar.badge.clock": "calendar-clock",
        "chart.bar": "bar-chart",
        "chart.bar.doc.horizontal": "bar-chart",
        "chart.bar.xaxis": "bar-chart",
        "chart.pie": "chart-pie",
        "checkmark": "check",
        "checkmark.bubble": "message",
        "checkmark.circle": "circle-check",
        "checkmark.circle.fill": "circle-check",
        "checkmark.seal": "shield-check",
        "checkmark.shield": "shield-check",
        "checklist": "multi-select",
        "chevron.down": "chevron-down",
        "chevron.left": "chevron-left",
        "chevron.left.forwardslash.chevron.right": "code",
        "chevron.right": "chevron-right",
        "chevron.up": "chevron-up",
        "circle": "circle",
        "circle.lefthalf.filled": "sun-moon",
        "clock": "clock",
        "clock.arrow.circlepath": "clock",
        "cloud": "cloud",
        "cpu": "cpu",
        "desktopcomputer": "monitor",
        "doc.badge.plus": "file-plus",
        "doc.on.clipboard": "copy",
        "doc.on.doc": "copy",
        "doc.plaintext": "file-text",
        "doc.text": "file-text",
        "doc.text.magnifyingglass": "file-search",
        "ellipsis": "more-horizontal",
        "exclamationmark.circle": "alert-circle",
        "exclamationmark.shield": "shield-alert",
        "exclamationmark.triangle": "alert-circle",
        "eye": "eye",
        "eye.slash": "eye-off",
        "folder": "folder",
        "folder.badge.minus": "folder-minus",
        "folder.badge.plus": "folder-plus",
        "folder.badge.questionmark": "folder",
        "folder.fill": "folder",
        "gamecontroller": "gamepad",
        "gearshape": "settings",
        "globe": "globe",
        "hand.raised": "hand",
        "house": "home",
        "info.circle": "info",
        "internaldrive": "hard-drive",
        "key": "key",
        "line.3.horizontal.decrease": "filter",
        "line.3.horizontal.decrease.circle": "filter",
        "link": "external-link",
        "link.badge.plus": "external-link",
        "list.bullet": "list-bullet",
        "list.bullet.rectangle": "list-bullet",
        "lock.shield": "shield-lock",
        "magnifyingglass": "search",
        "network": "server",
        "note.text": "edit",
        "paintpalette": "edit",
        "photo": "image",
        "photo.badge.checkmark": "image",
        "photo.badge.plus": "image",
        "photo.on.rectangle": "image",
        "pin": "pin",
        "play.circle": "play-circle",
        "play.fill": "play",
        "plus": "plus",
        "point.3.connected.trianglepath.dotted": "workflow",
        "power": "power",
        "rectangle.on.rectangle": "layers",
        "rectangle.stack": "layers",
        "shippingbox": "box",
        "sidebar.left": "sidebar",
        "slider.horizontal.3": "sliders",
        "sparkles": "sparkles",
        "sparkles.rectangle.stack": "sparkles",
        "square.and.pencil": "edit",
        "square.grid.2x2": "grid",
        "square.grid.3x3": "grid-3x3",
        "square.stack.3d.up": "layers",
        "star": "star",
        "star.fill": "star",
        "star.slash": "star-off",
        "stethoscope": "stethoscope",
        "stop": "stop",
        "stop.circle": "stop-circle",
        "terminal": "terminal",
        "text.bubble": "message",
        "text.quote": "message",
        "trash": "trash",
        "trash.slash": "trash",
        "triangle": "triangle",
        "xmark": "close",
        "xmark.circle": "x-circle",
        "xmark.circle.fill": "x-circle",
    ]

    static func image(for symbol: String) -> NSImage? {
        let name = aliases[symbol]
            ?? aliases[symbol.replacingOccurrences(of: ".fill", with: "")]
            ?? symbol
        let key = name as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let url = assetURL(named: name),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }

    private static func assetURL(named name: String) -> URL? {
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: "Icons"
        ) {
            return url
        }

        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            current.appendingPathComponent("Resources/Icons/\(name).svg"),
            current.appendingPathComponent("macos/Resources/Icons/\(name).svg"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
