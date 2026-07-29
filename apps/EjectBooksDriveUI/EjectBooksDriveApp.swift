import AppKit
import SwiftUI

@main
struct EjectBooksDriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            EjectSessionRoot()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct EjectSessionRoot: View {
    @StateObject private var session = EjectSessionController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var settled = false

    var body: some View {
        EjectWindowView(
            model: session.presentation,
            onPrimary: { session.primary() },
            onSecondary: { session.secondary() }
        )
        .offset(y: settleOffset)
        .background(Palette.of(scheme).ground)
        .ignoresSafeArea() // kill the empty system titlebar inset
        .onAppear {
            session.onAppear()
            AppDelegate.styleOpenWindows()
        }
        .onChange(of: session.presentation.state) { _, new in
            guard [.succeeded, .partial, .failed].contains(new) else { return }
            if reduceMotion {
                settled = true
                return
            }
            settled = false
            withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.3)) {
                settled = true
            }
        }
    }

    private var settleOffset: CGFloat {
        let isResult = [.succeeded, .partial, .failed].contains(session.presentation.state)
        if !isResult { return 0 }
        if reduceMotion { return 0 }
        return settled ? 0 : 6
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Self.styleOpenWindows()
    }

    static func styleOpenWindows() {
        for window in NSApp.windows {
            window.title = "Eject Books Drive"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.remove(.resizable)
            // Opaque ground — a clear window left a translucent “empty” strip above the Plate UI.
            window.isOpaque = true
            window.backgroundColor = NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                if dark {
                    return NSColor(srgbRed: 18 / 255, green: 19 / 255, blue: 20 / 255, alpha: 1) // #121314
                }
                return NSColor(srgbRed: 241 / 255, green: 240 / 255, blue: 236 / 255, alpha: 1) // #F1F0EC
            }
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if #available(macOS 11.0, *) {
                window.toolbarStyle = .unifiedCompact
            }
            window.toolbar = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
