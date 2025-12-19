//
//  WebViewModel.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit
import Combine
import AppKit

/// Handles console.log messages from JavaScript
class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? String {
            print("[WebView] \(body)")
        }
    }
}

/// Handles blob downloads from JavaScript
class BlobDownloadHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == UserScripts.blobDownloadHandler,
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

/// Observable wrapper around WKWebView with Gemini-specific functionality
@Observable
class WebViewModel {

    // MARK: - Constants

    static let geminiURL = URL(string: "https://gemini.google.com/app")!
    static let defaultPageZoom: Double = 1.0

    private static let geminiHost = "gemini.google.com"
    private static let geminiAppPath = "/app"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private static let minZoom: Double = 0.6
    private static let maxZoom: Double = 1.4

    // MARK: - Public Properties

    let wkWebView: WKWebView
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var isAtHome: Bool = true

    // MARK: - Private Properties

    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private let consoleLogHandler = ConsoleLogHandler()
    private let blobDownloadHandler = BlobDownloadHandler()

    // MARK: - Initialization

    init() {
        self.wkWebView = Self.createWebView(consoleLogHandler: consoleLogHandler, blobDownloadHandler: blobDownloadHandler)
        setupObservers()
        loadHome()
    }

    // MARK: - Navigation

    func loadHome() {
        isAtHome = true
        canGoBack = false
        wkWebView.load(URLRequest(url: Self.geminiURL))
    }

    func goBack() {
        isAtHome = false
        wkWebView.goBack()
    }

    func goForward() {
        wkWebView.goForward()
    }

    func reload() {
        wkWebView.reload()
    }

    // MARK: - Zoom

    func zoomIn() {
        let newZoom = min((wkWebView.pageZoom * 100 + 1).rounded() / 100, Self.maxZoom)
        setZoom(newZoom)
    }

    func zoomOut() {
        let newZoom = max((wkWebView.pageZoom * 100 - 1).rounded() / 100, Self.minZoom)
        setZoom(newZoom)
    }

    func resetZoom() {
        setZoom(Self.defaultPageZoom)
    }

    private func setZoom(_ zoom: Double) {
        wkWebView.pageZoom = zoom
        UserDefaults.standard.set(zoom, forKey: UserDefaultsKeys.pageZoom.rawValue)
    }

    // MARK: - Private Setup

    private static func createWebView(consoleLogHandler: ConsoleLogHandler, blobDownloadHandler: BlobDownloadHandler) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Add user scripts
        for script in UserScripts.createAllScripts() {
            configuration.userContentController.addUserScript(script)
        }

        // Register console log message handler (debug only)
        #if DEBUG
        configuration.userContentController.add(consoleLogHandler, name: UserScripts.consoleLogHandler)
        #endif
        
        // Register blob download message handler
        configuration.userContentController.add(blobDownloadHandler, name: UserScripts.blobDownloadHandler)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.customUserAgent = userAgent

        let savedZoom = UserDefaults.standard.double(forKey: UserDefaultsKeys.pageZoom.rawValue)
        webView.pageZoom = savedZoom > 0 ? savedZoom : defaultPageZoom

        return webView
    }

    private func setupObservers() {
        backObserver = wkWebView.observe(\.canGoBack, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canGoBack = !self.isAtHome && webView.canGoBack
            }
        }

        forwardObserver = wkWebView.observe(\.canGoForward, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canGoForward = webView.canGoForward
            }
        }

        urlObserver = wkWebView.observe(\.url, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentURL = webView.url else { return }

                let isGeminiApp = currentURL.host == Self.geminiHost &&
                                  currentURL.path.hasPrefix(Self.geminiAppPath)

                if isGeminiApp {
                    self.isAtHome = true
                    self.canGoBack = false
                } else {
                    self.isAtHome = false
                    self.canGoBack = webView.canGoBack
                }
            }
        }
    }
}
