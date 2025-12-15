//
//  AppCoordinator.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit
import WebKit
import Combine

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

@Observable
class AppCoordinator {
    private var chatBar: ChatBarPanel?
    let webView: WKWebView
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var isAtHome: Bool = true

    var openWindowAction: ((String) -> Void)?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = true

        // Set custom User-Agent to appear as Safari
        wv.customUserAgent = Constants.userAgent

        // Apply saved page zoom
        let savedZoom = UserDefaults.standard.double(forKey: UserDefaultsKeys.pageZoom.rawValue)
        wv.pageZoom = savedZoom > 0 ? savedZoom : Constants.defaultPageZoom

        wv.load(URLRequest(url: Constants.geminiURL))

        self.webView = wv

        backObserver = wv.observe(\.canGoBack, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canGoBack = !self.isAtHome && webView.canGoBack
            }
        }

        forwardObserver = wv.observe(\.canGoForward, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canGoForward = webView.canGoForward
            }
        }

        urlObserver = wv.observe(\.url, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentURL = webView.url else { return }

                // Check if we're at the Gemini home/app page
                let isGeminiApp = currentURL.host == Constants.geminiHost && currentURL.path.hasPrefix(Constants.geminiAppPath)

                if isGeminiApp {
                    self.isAtHome = true
                    self.canGoBack = false
                } else {
                    self.isAtHome = false
                    self.canGoBack = webView.canGoBack
                }
            }
        }

        // Observe notifications for window opening
        NotificationCenter.default.addObserver(forName: .openMainWindow, object: nil, queue: .main) { [weak self] _ in
            self?.openMainWindow()
        }
    }

    func reloadHomePage() {
        isAtHome = true
        canGoBack = false
        webView.load(URLRequest(url: Constants.geminiURL))
    }

    func goBack() {
        isAtHome = false
        webView.goBack()
    }

    func reload() {
        webView.reload()
    }

    func goForward() {
        webView.goForward()
    }

    func goHome() {
        reloadHomePage()
    }

    func zoomIn() {
        let newZoom = min((webView.pageZoom * 100 + 1).rounded() / 100, 1.4)
        webView.pageZoom = newZoom
        UserDefaults.standard.set(newZoom, forKey: UserDefaultsKeys.pageZoom.rawValue)
    }

    func zoomOut() {
        let newZoom = max((webView.pageZoom * 100 - 1).rounded() / 100, 0.6)
        webView.pageZoom = newZoom
        UserDefaults.standard.set(newZoom, forKey: UserDefaultsKeys.pageZoom.rawValue)
    }

    func resetZoom() {
        webView.pageZoom = Constants.defaultPageZoom
        UserDefaults.standard.set(Constants.defaultPageZoom, forKey: UserDefaultsKeys.pageZoom.rawValue)
    }

    func showChatBar() {
        // Hide main window when showing chat bar
        closeMainWindow()

        if let bar = chatBar {
            // Check if we should reset position to default
            let shouldResetPosition = UserDefaults.standard.object(forKey: UserDefaultsKeys.resetChatBarPosition.rawValue) as? Bool ?? true
            
            if shouldResetPosition {
                // Reuse existing chat bar - reposition to current mouse screen
                repositionChatBarToMouseScreen(bar)
            }
            // If not resetting, keep the current position
            
            bar.orderFront(nil)
            bar.makeKeyAndOrderFront(nil)
            bar.checkAndAdjustSize()
            return
        }

        let contentView = ChatBarView(
            webView: webView,
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
        // Capture the screen where the chat bar is located before hiding it
        let targetScreen = chatBar.flatMap { bar -> NSScreen? in
            let center = NSPoint(x: bar.frame.midX, y: bar.frame.midY)
            return NSScreen.screens.first { $0.frame.contains(center) }
        } ?? NSScreen.main
        
        hideChatBar()
        openMainWindow(on: targetScreen)
    }

    func openMainWindow(on targetScreen: NSScreen? = nil) {
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
            if let screen = targetScreen {
                // Center the window on the target screen
                let screenFrame = screen.visibleFrame
                let windowSize = window.frame.size
                let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
                let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            window.makeKeyAndOrderFront(nil)
        } else if let openWindowAction = openWindowAction {
            // Window doesn't exist yet - use SwiftUI openWindow to create it
            openWindowAction("main")
            // Position newly created window after a brief delay
            if let screen = targetScreen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    if let window = NSApp.windows.first(where: {
                        $0.identifier?.rawValue == Constants.mainWindowIdentifier || $0.title == Constants.mainWindowTitle
                    }) {
                        let screenFrame = screen.visibleFrame
                        let windowSize = window.frame.size
                        let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
                        let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
                        window.setFrameOrigin(NSPoint(x: x, y: y))
                    }
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}


extension AppCoordinator {

    struct Constants {
        static let geminiURL = URL(string: "https://gemini.google.com/app")!
        static let geminiHost = "gemini.google.com"
        static let geminiAppPath = "/app"
        static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        static let defaultPageZoom: Double = 1.0
        static let dockOffset: CGFloat = 50
        static let mainWindowIdentifier = "main"
        static let mainWindowTitle = "Gemini Desktop"
    }

}
