import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSWindowController {
    init() {
        let controller = NSHostingController(rootView: SetupView())
        let window = NSWindow(contentViewController: controller)
        window.title = "GitSwitch"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 390))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
