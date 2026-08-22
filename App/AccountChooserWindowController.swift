import AppKit
import SwiftUI

@MainActor
final class AccountChooserWindowController: NSWindowController {
    init() {
        let controller = NSHostingController(
            rootView: AccountChooserView {
                NSApp.keyWindow?.close()
            }
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "切换 GitHub 账号"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 340))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
