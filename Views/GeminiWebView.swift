//
//  GeminiWebView.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import WebKit

struct GeminiWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WebViewContainer {
        let container = WebViewContainer(webView: webView, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: WebViewContainer, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
        private var downloadDestination: URL?
        
        // MARK: - WKScriptMessageHandler
        
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

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            // Handle blob: URLs - cancel navigation, downloads are handled by injected script
            if url.scheme == "blob" {
                decisionHandler(.cancel)
                // The injected JavaScript should have already handled the download
                // If we get here, the script didn't catch it, so we can't do much
                return
            }
            
            // Allow navigation within Google domains (gemini.google.com, accounts.google.com, etc.)
            let host = url.host?.lowercased() ?? ""
            let isGoogleDomain = host.hasSuffix("google.com") || host.hasSuffix("googleapis.com")
            
            // For user-initiated link clicks to external sites, open in default browser
            if navigationAction.navigationType == .linkActivated && !isGoogleDomain {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
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
                "application/octet-stream": "bin"
            ]
            return mimeMap[mimeType] ?? mimeType.components(separatedBy: "/").last ?? "bin"
        }
        
        private func saveBlobData(_ data: Data, filename: String, mimeType: String? = nil) {
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = filename
            savePanel.canCreateDirectories = true
            
            savePanel.begin { [weak self] response in
                if response == .OK, let url = savePanel.url {
                    do {
                        try data.write(to: url)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } catch {
                        self?.showDownloadError("Failed to save file: \(error.localizedDescription)")
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

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            var destination = downloadsURL.appendingPathComponent(suggestedFilename)

            // Handle duplicate filenames
            var counter = 1
            let fileManager = FileManager.default
            let nameWithoutExtension = destination.deletingPathExtension().lastPathComponent
            let fileExtension = destination.pathExtension

            while fileManager.fileExists(atPath: destination.path) {
                let newName = fileExtension.isEmpty
                    ? "\(nameWithoutExtension) (\(counter))"
                    : "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
                destination = downloadsURL.appendingPathComponent(newName)
                counter += 1
            }

            downloadDestination = destination
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let destination = downloadDestination else { return }
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            let alert = NSAlert()
            alert.messageText = "Download Failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: GeminiWebView.Constants.textFieldWidth, height: GeminiWebView.Constants.textFieldHeight))
            textField.stringValue = defaultText ?? ""
            alert.accessoryView = textField

            completionHandler(alert.runModal() == .alertFirstButtonReturn ? textField.stringValue : nil)
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host.contains(GeminiWebView.Constants.trustedHost) ? .grant : .prompt)
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.canChooseFiles = true
            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }
    }
}

class WebViewContainer: NSView {
    let webView: WKWebView
    let coordinator: GeminiWebView.Coordinator
    private var windowObserver: NSObjectProtocol?

    init(webView: WKWebView, coordinator: GeminiWebView.Coordinator) {
        self.webView = webView
        self.coordinator = coordinator
        super.init(frame: .zero)
        autoresizesSubviews = true
        setupWindowObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupWindowObserver() {
        // Observe when ANY window becomes key - then check if we should have the webView
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let keyWindow = notification.object as? NSWindow,
                  self.window === keyWindow else { return }
            // Our window became key, attach webView
            self.attachWebView()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && window?.isKeyWindow == true {
            attachWebView()
        }
    }

    override func layout() {
        super.layout()
        if webView.superview === self {
            webView.frame = bounds
        }
    }

    private func attachWebView() {
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        addSubview(webView)
    }
}


extension GeminiWebView {

    struct Constants {
        static let textFieldWidth: CGFloat = 200
        static let textFieldHeight: CGFloat = 24
        static let trustedHost = "google.com"
    }

}
