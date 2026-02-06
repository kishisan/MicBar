import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: AudioDeviceMonitor!
    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        monitor = AudioDeviceMonitor()
        monitor.onStateChanged = { [weak self] state in
            self?.statusBarController.update(state: state)
        }
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }
}
