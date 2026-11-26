import AppKit
import SwiftUI

/// Shared icon sizes so toolbar, navigation and micro controls stay visually consistent.
enum FizzIconScale {
    /// Window toolbar buttons (sidebar toggle, back, refresh, folder, search).
    static let toolbar: CGFloat = 13
    /// Sidebar navigation rows, search field and rail buttons.
    static let nav: CGFloat = 12
    /// Disclosure chevrons, add buttons and section markers.
    static let micro: CGFloat = 8
}

struct FizzIcon: View {
    let symbol: String
    var size: CGFloat = 14

    var body: some View {
        let side = size * 1.12
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
        "arrow.clockwise": "refresh",
        "arrow.down": "arrow-down",
        "arrow.left": "arrow-left",
        "arrow.right": "arrow-right",
        "arrow.triangle.2.circlepath": "refresh",
        "arrow.triangle.branch": "git-branch",
        "arrow.up": "arrow-up",
        "arrow.up.forward.app": "external-link",
        "arrow.up.right": "arrow-up-right",
        "arrow.up.right.square": "external-link",
        "arrow.uturn.backward": "undo",
        "archivebox": "archive",
        "at": "mention",
        "bell.slash": "bell-off",
        "bubble.left.and.bubble.right": "message",
        "bubble.left.fill": "message",
        "chart.bar": "bar-chart",
        "chart.bar.doc.horizontal": "bar-chart",
        "checkmark": "check",
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
        "clock.arrow.circlepath": "clock",
        "doc.on.clipboard": "copy",
        "doc.on.doc": "copy",
        "doc.text": "file-text",
        "doc.text.magnifyingglass": "file-text",
        "ellipsis": "more-horizontal",
        "exclamationmark.circle": "alert-circle",
        "exclamationmark.triangle": "alert-circle",
        "folder.badge.minus": "folder-minus",
        "folder.badge.plus": "folder-plus",
        "folder.badge.questionmark": "folder",
        "folder.fill": "folder",
        "gearshape": "settings",
        "house": "home",
        "info.circle": "info",
        "internaldrive": "hard-drive",
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
        "play.circle": "play-circle",
        "play.fill": "play",
        "rectangle.on.rectangle": "layers",
        "sidebar.left": "sidebar",
        "slider.horizontal.3": "sliders",
        "square.and.pencil": "edit",
        "square.grid.2x2": "grid",
        "square.stack.3d.up": "layers",
        "star.fill": "star",
        "stop.circle": "stop-circle",
        "text.quote": "message",
        "trash.slash": "trash",
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
