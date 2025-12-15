//
//  AppCoordinator.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit
import WebKit

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

@Observable
class AppCoordinator {
    private var chatBar: ChatBarPanel?
    var webViewModel = WebViewModel()

    var openWindowAction: ((String) -> Void)?

    var canGoBack: Bool { webViewModel.canGoBack }
    var canGoForward: Bool { webViewModel.canGoForward }

    init() {
        // Observe notifications for window opening
        NotificationCenter.default.addObserver(forName: .openMainWindow, object: nil, queue: .main) { [weak self] _ in
            self?.openMainWindow()
        }
    }

    // MARK: - Navigation

    func goBack() { webViewModel.goBack() }
    func goForward() { webViewModel.goForward() }
    func goHome() { webViewModel.loadHome() }
    func reload() { webViewModel.reload() }

    // MARK: - Zoom

    func zoomIn() { webViewModel.zoomIn() }
    func zoomOut() { webViewModel.zoomOut() }
    func resetZoom() { webViewModel.resetZoom() }

    // MARK: - Chat Bar

    func showChatBar() {
        // Hide main window when showing chat bar
        closeMainWindow()

        if let bar = chatBar {
            // Reuse existing chat bar - reposition to current mouse screen
            repositionChatBarToMouseScreen(bar)
            bar.orderFront(nil)
            bar.makeKeyAndOrderFront(nil)
            bar.checkAndAdjustSize()
            return
        }

        let contentView = ChatBarView(
            webView: webViewModel.wkWebView,
            onExpandToMain: { [weak self] in
                self?.expandToMainWindow()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let bar = ChatBarPanel(contentView: hostingView)

        // Position at bottom center of the screen where mouse is located
        if let screen = screenAtMouseLocation() {
            let screenRect = screen.visibleFrame
            let barSize = bar.frame.size
            let x = screenRect.origin.x + (screenRect.width - barSize.width) / 2
            let y = screenRect.origin.y + Constants.dockOffset
            bar.setFrameOrigin(NSPoint(x: x, y: y))
        }

        bar.orderFront(nil)
        bar.makeKeyAndOrderFront(nil)
        chatBar = bar
    }

    /// Returns the screen containing the current mouse cursor location
    private func screenAtMouseLocation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main
    }

    /// Repositions an existing chat bar to the screen containing the mouse cursor
    private func repositionChatBarToMouseScreen(_ bar: ChatBarPanel) {
        guard let screen = screenAtMouseLocation() else { return }
        let screenRect = screen.visibleFrame
        let barSize = bar.frame.size
        let x = screenRect.origin.x + (screenRect.width - barSize.width) / 2
        let y = screenRect.origin.y + Constants.dockOffset
        bar.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hideChatBar() {
        chatBar?.orderOut(nil)
    }

    func closeMainWindow() {
        // Find and hide the main window
        for window in NSApp.windows {
            if window.identifier?.rawValue == Constants.mainWindowIdentifier || window.title == Constants.mainWindowTitle {
                if !(window is NSPanel) {
                    window.orderOut(nil)
                }
            }
        }
    }

    func toggleChatBar() {
        if let bar = chatBar, bar.isVisible {
            hideChatBar()
        } else {
            showChatBar()
        }
    }

    func expandToMainWindow() {
        hideChatBar()
        openMainWindow()
    }

    func openMainWindow() {
        // Hide chat bar first - WebView can only be in one view hierarchy
        hideChatBar()

        let hideDockIcon = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hideDockIcon.rawValue)
        if !hideDockIcon {
            NSApp.setActivationPolicy(.regular)
        }

        // Find existing main window (may be hidden/suppressed)
        let mainWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue == Constants.mainWindowIdentifier || $0.title == Constants.mainWindowTitle
        })

        if let window = mainWindow {
            // Window exists - show it (works for suppressed windows too)
            window.makeKeyAndOrderFront(nil)
        } else if let openWindowAction = openWindowAction {
            // Window doesn't exist yet - use SwiftUI openWindow to create it
            openWindowAction("main")
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}


extension AppCoordinator {

    struct Constants {
        static let dockOffset: CGFloat = 50
        static let mainWindowIdentifier = "main"
        static let mainWindowTitle = "Gemini Desktop"
    }

}
