import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var applicationController: ApplicationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = ApplicationController()
        applicationController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        applicationController?.stop()
    }
}
