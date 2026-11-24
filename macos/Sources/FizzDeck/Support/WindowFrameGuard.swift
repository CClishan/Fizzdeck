import AppKit
import SwiftUI

struct WindowFrameGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowGuardView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowGuardView: NSView {
    private var didCheck = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didCheck, let window else { return }
        didCheck = true
        DispatchQueue.main.async {
            WindowFrameGuard.ensureVisible(window)
        }
    }
}

extension WindowFrameGuard {
    static func ensureVisible(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window.frame
        guard !isReachable(frame, in: visible) else { return }

        let width = min(frame.width, visible.width - 40)
        let height = min(frame.height, visible.height - 40)
        let target = NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(target, display: true)
    }

    private static func isReachable(_ frame: NSRect, in visible: NSRect) -> Bool {
        let intersection = frame.intersection(visible)
        guard !intersection.isNull, intersection.width >= 320, intersection.height >= 200 else {
            return false
        }

        let titleBar = NSRect(
            x: frame.minX,
            y: frame.maxY - 30,
            width: frame.width,
            height: 30
        )
        return titleBar.intersects(visible)
    }
}
