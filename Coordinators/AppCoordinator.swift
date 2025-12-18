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
    static let shared = AppCoordinator()
    
    private var chatBar: ChatBarPanel?
    let webView: WKWebView
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var isAtHome: Bool = true

    var openWindowAction: ((String) -> Void)?
    
    private let downloadHandler = DownloadHandler()

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Add message handler for blob downloads
        configuration.userContentController.add(downloadHandler, name: "blobDownload")
        
        // Inject script to intercept blob downloads
        let downloadScript = WKUserScript(
            source: AppCoordinator.blobDownloadInterceptScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(downloadScript)

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
            },
            onClose: { [weak self] in
                self?.hideChatBar()
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

    func toggleMainWindow() {
        // Check if main window exists and is visible
        let mainWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue == Constants.mainWindowIdentifier || $0.title == Constants.mainWindowTitle
        })
        
        if let window = mainWindow, window.isVisible && window.isKeyWindow {
            closeMainWindow()
        } else {
            openMainWindow()
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
    
    // JavaScript to intercept blob downloads
    static let blobDownloadInterceptScript = """
    (function() {
        // Store blob URLs and their corresponding blobs
        const blobRegistry = new Map();
        
        // Override URL.createObjectURL to track blob URLs
        const originalCreateObjectURL = URL.createObjectURL;
        URL.createObjectURL = function(blob) {
            const url = originalCreateObjectURL.call(URL, blob);
            if (blob instanceof Blob) {
                blobRegistry.set(url, blob);
            }
            return url;
        };
        
        // Override URL.revokeObjectURL to clean up
        const originalRevokeObjectURL = URL.revokeObjectURL;
        URL.revokeObjectURL = function(url) {
            blobRegistry.delete(url);
            return originalRevokeObjectURL.call(URL, url);
        };
        
        // Intercept clicks on download links
        document.addEventListener('click', function(event) {
            const anchor = event.target.closest('a[download]');
            if (!anchor) return;
            
            const href = anchor.href;
            if (!href || !href.startsWith('blob:')) return;
            
            const blob = blobRegistry.get(href);
            if (!blob) return;
            
            // Prevent default navigation
            event.preventDefault();
            event.stopPropagation();
            
            // Read blob and send to native
            const reader = new FileReader();
            reader.onloadend = function() {
                const filename = anchor.download || 'download';
                window.webkit.messageHandlers.blobDownload.postMessage({
                    data: reader.result,
                    mimeType: blob.type || 'application/octet-stream',
                    filename: filename
                });
            };
            reader.readAsDataURL(blob);
        }, true);
    })();
    """

}

// MARK: - Download Handler

class DownloadHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "blobDownload",
              let body = message.body as? [String: Any],
              let base64Data = body["data"] as? String,
              let mimeType = body["mimeType"] as? String,
              let filename = body["filename"] as? String else {
            return
        }
        
        // Remove the data URL prefix if present (e.g., "data:image/png;base64,")
        let base64String: String
        if let commaIndex = base64Data.firstIndex(of: ",") {
            base64String = String(base64Data[base64Data.index(after: commaIndex)...])
        } else {
            base64String = base64Data
        }
        
        guard let data = Data(base64Encoded: base64String) else {
            showDownloadError("Failed to decode download data")
            return
        }
        
        saveBlobData(data, filename: filename, mimeType: mimeType)
    }
    
    private func mimeTypeToExtension(_ mimeType: String) -> String {
        let mimeMap: [String: String] = [
            "image/png": "png",
            "image/jpeg": "jpg",
            "image/gif": "gif",
            "image/webp": "webp",
            "image/svg+xml": "svg",
            "application/pdf": "pdf",
            "application/zip": "zip",
            "application/json": "json",
            "text/plain": "txt",
            "text/html": "html",
            "text/css": "css",
            "text/javascript": "js",
            "application/javascript": "js",
            "audio/mpeg": "mp3",
            "audio/wav": "wav",
            "video/mp4": "mp4",
            "video/webm": "webm",
            "application/octet-stream": "bin",
            "text/markdown": "md",
            "application/x-python": "py",
            "text/x-python": "py"
        ]
        return mimeMap[mimeType] ?? mimeType.components(separatedBy: "/").last ?? "bin"
    }
    
    private func saveBlobData(_ data: Data, filename: String, mimeType: String) {
        DispatchQueue.main.async {
            // Check if filename has an extension, if not add one based on mimeType
            var finalFilename = filename
            if !filename.contains(".") || filename.hasSuffix(".") {
                let ext = self.mimeTypeToExtension(mimeType)
                finalFilename = filename.hasSuffix(".") ? "\(filename)\(ext)" : "\(filename).\(ext)"
            }
            
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = finalFilename
            savePanel.canCreateDirectories = true
            savePanel.level = .floating  // Ensure panel appears above ChatBar
            
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    do {
                        try data.write(to: url)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } catch {
                        self.showDownloadError("Failed to save file: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func showDownloadError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Download Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
