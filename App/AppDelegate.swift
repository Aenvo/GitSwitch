import AppKit
import ServiceManagement
import WidgetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let server = StatusServer()
    private var setupWindow: SetupWindowController?
    private var accountChooserWindow: AccountChooserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--unregister-login-item") {
            try? SMAppService.mainApp.unregister()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        server.start()
        Task {
            _ = await SwitchCoordinator.shared.currentStatus(refresh: true)
            WidgetCenter.shared.reloadAllTimelines()
        }
        registerLoginItemIfPossible()

        let firstLaunch = !UserDefaults.standard.bool(forKey: "didCompleteFirstLaunch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if firstLaunch {
                self.showSetupWindow()
            }
            UserDefaults.standard.set(true, forKey: "didCompleteFirstLaunch")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetupWindow()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "gitswitch" && $0.host == "choose" }) else {
            return
        }
        showAccountChooser()
    }

    private func registerLoginItemIfPossible() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
            fputs("GitSwitch: login item registered\n", stderr)
        } catch {
            fputs("GitSwitch: login item registration failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func showSetupWindow() {
        if setupWindow == nil {
            setupWindow = SetupWindowController()
        }
        setupWindow?.showWindow(nil)
        setupWindow?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAccountChooser() {
        if accountChooserWindow == nil {
            accountChooserWindow = AccountChooserWindowController()
        }
        accountChooserWindow?.showWindow(nil)
        accountChooserWindow?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}
