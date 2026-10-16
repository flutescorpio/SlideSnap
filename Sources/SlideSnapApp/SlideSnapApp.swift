import AppKit
import SwiftUI

@main
struct SlideSnapApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup("SlideSnap") {
            ContentView()
                .environmentObject(model)
                .onAppear { delegate.model = model }
        }
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

/// Files dropped on the Dock icon or opened with "Open With" go to the window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: Model?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched from a plain binary (swift run): still a regular app with a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in self.model?.addInputs(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
