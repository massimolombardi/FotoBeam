import AppKit
import Carbon
import SwiftUI

@main
struct FotoBeamApp: App {
    @NSApplicationDelegateAdaptor(FotoBeamAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
    }
}

final class FotoBeamAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        transformToForegroundApplication()
        NSApp.setActivationPolicy(.regular)
        bringAppToFront()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringAppToFront()
        return true
    }

    private func bringAppToFront() {
        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func transformToForegroundApplication() {
        var process = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        TransformProcessType(&process, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
    }
}
