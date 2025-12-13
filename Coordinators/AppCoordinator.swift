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

@Observable
class AppCoordinator {
    private var chatBar: ChatBarPanel?
    private var expandedState = ExpandedState()
    let webView: WKWebView
    var canGoBack: Bool = false
    private var backObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var isAtHome: Bool = true

    var openWindowAction: ((String) -> Void)?

    class ExpandedState: ObservableObject {
        @Published var isExpanded: Bool = false
    }

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

    func showChatBar() {
        // Hide main window when showing chat bar
        closeMainWindow()

        if let bar = chatBar {
            // Reuse existing chat bar
            bar.orderFront(nil)
            bar.makeKeyAndOrderFront(nil)
            bar.checkAndAdjustSize()
            return
        }

        let contentView = ChatBarView(
            expandedState: expandedState,
            webView: webView,
            onExpandToMain: { [weak self] in
                self?.expandToMainWindow()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let bar = ChatBarPanel(contentView: hostingView)
        bar.onExpandedChange = { [weak self] expanded in
            self?.expandedState.isExpanded = expanded
        }

        // Position at bottom center, above the dock
        if let screen = NSScreen.main {
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
        NSApp.setActivationPolicy(.regular)

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
