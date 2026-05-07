import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: WatchlistWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let controller = WatchlistWindowController(preferences: StockerPreferences())
        windowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
