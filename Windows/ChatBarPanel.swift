//
//  ChatBar.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit
import WebKit

class ChatBarPanel: NSPanel, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {

    private var initialSize: NSSize {
        let width = UserDefaults.standard.double(forKey: UserDefaultsKeys.panelWidth.rawValue)
        let height = UserDefaults.standard.double(forKey: UserDefaultsKeys.panelHeight.rawValue)
        return NSSize(
            width: width > 0 ? width : Constants.defaultWidth,
            height: height > 0 ? height : Constants.defaultHeight
        )
    }

    /// Returns the screen where this panel is currently located
    private var currentScreen: NSScreen? {
        let panelCenter = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { screen in
            screen.frame.contains(panelCenter)
        } ?? NSScreen.main
    }

    // Expanded height: 70% of screen height or initial height, whichever is larger
    private var expandedHeight: CGFloat {
        let screenHeight = currentScreen?.visibleFrame.height ?? 800
        return max(screenHeight * Constants.expandedScreenRatio, initialSize.height)
    }

    private var isExpanded = false
    private var pollingTimer: Timer?
    private weak var webView: WKWebView?
    private var hasScrolledToTopAfterLoad = false

    // Returns true if in a conversation (not on start page)
    private let checkConversationScript = """
        (function() {
            const scroller = document.querySelector('infinite-scroller[data-test-id="chat-history-container"]');
            if (!scroller) { return false; }
            const hasResponseContainer = scroller.querySelector('response-container') !== null;
            const hasRatingButtons = scroller.querySelector('[aria-label="Good response"], [aria-label="Bad response"]') !== null;
            return hasResponseContainer || hasRatingButtons;
        })();
        """

    // JavaScript to focus the input field and setup Enter key handler
    private let focusInputScript = """
        (function() {
            const input = document.querySelector('rich-textarea[aria-label="Enter a prompt here"]') ||
                          document.querySelector('[contenteditable="true"]') ||
                          document.querySelector('textarea');
            if (input) {
                input.focus();
                
                // Scroll to top to ensure header area is visible
                window.scrollTo(0, 0);
                document.documentElement.scrollTop = 0;
                document.body.scrollTop = 0;
                
                // Add Enter key listener if not already added
                if (!input.dataset.hasEnterHandler) {
                    input.addEventListener('keydown', (e) => {
                        if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
                            e.preventDefault();
                            e.stopPropagation();
                            
                            // Try to find the send button
                            const sendButton = document.querySelector('button[aria-label="Send message"]') ||
                                             document.querySelector('button.send-button') ||
                                             document.querySelector('button[data-testid="send-button"]') ||
                                             document.querySelector('button .material-symbols-outlined[data-test-id="send-icon"]')?.closest('button');
                            
                            if (sendButton) {
                                sendButton.click();
                            }
                        }
                    }, true); // Use capture to ensure we handle it first
                    input.dataset.hasEnterHandler = 'true';
                }
                return true;
            }
            return false;
        })();
        """
    
    // JavaScript to observe input field height changes
    private let observeInputHeightScript = """
        (function() {
            // Target the specific element that has the dynamic height
            // Based on actual Gemini HTML structure:
            // .text-input-field_textarea-inner has explicit height style
            const inputInner = document.querySelector('.text-input-field_textarea-inner');
            
            if (!inputInner) {
                console.log('[ChatBar] Input inner not found');
                return null;
            }
            
            if (inputInner.dataset.hasHeightObserver) {
                return getTotalHeight();
            }
            
            inputInner.dataset.hasHeightObserver = 'true';
            
            // Function to get the uploader height from the CSS variable
            function getUploaderHeight() {
                const qlEditor = document.querySelector('.ql-editor');
                if (qlEditor) {
                    // First check if there's actually any uploaded content
                    const filePreviewContainer = document.querySelector('.file-preview-container');
                    const hasFiles = filePreviewContainer && filePreviewContainer.children.length > 0;
                    
                    if (!hasFiles) {
                        return 0; // No files uploaded, no uploader height needed
                    }
                    
                    const uploaderHeightVar = getComputedStyle(qlEditor).getPropertyValue('--uploader-height');
                    if (uploaderHeightVar) {
                        const match = uploaderHeightVar.match(/([\\d.]+)/);
                        if (match) {
                            return parseFloat(match[1]);
                        }
                    }
                }
                return 0;
            }
            
            // Function to calculate total height including uploader
            function getTotalHeight() {
                const baseHeight = inputInner.getBoundingClientRect().height;
                const uploaderHeight = getUploaderHeight();
                return baseHeight + uploaderHeight;
            }
            
            // Store initial height
            let lastHeight = getTotalHeight();
            console.log('[ChatBar] Initial input height:', lastHeight);
            
            // Function to notify native code of height change
            function notifyHeightChange() {
                const height = getTotalHeight();
                if (Math.abs(height - lastHeight) > 2) {
                    lastHeight = height;
                    console.log('[ChatBar] Input height changed:', height, '(uploader:', getUploaderHeight(), ')');
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.inputHeightChanged) {
                        window.webkit.messageHandlers.inputHeightChanged.postMessage({ height: height });
                    }
                }
            }
            
            // Create a ResizeObserver to watch for size changes
            const resizeObserver = new ResizeObserver((entries) => {
                notifyHeightChange();
            });
            
            resizeObserver.observe(inputInner);
            
            // Also use MutationObserver to watch for style attribute changes
            // This catches cases where the height is set via inline style
            const mutationObserver = new MutationObserver((mutations) => {
                for (const mutation of mutations) {
                    if (mutation.type === 'attributes' && mutation.attributeName === 'style') {
                        notifyHeightChange();
                    }
                }
            });
            
            mutationObserver.observe(inputInner, { 
                attributes: true, 
                attributeFilter: ['style'] 
            });
            
            // Also observe the ql-editor for content changes and uploader appearance
            const qlEditor = document.querySelector('.ql-editor');
            if (qlEditor) {
                resizeObserver.observe(qlEditor);
                
                // Watch for style changes on ql-editor (uploader height is set via --uploader-height CSS variable)
                mutationObserver.observe(qlEditor, {
                    attributes: true,
                    attributeFilter: ['style']
                });
                
                // Watch for input events on the editor
                qlEditor.addEventListener('input', () => {
                    setTimeout(notifyHeightChange, 10);
                });
            }
            
            // Also observe the text input field container for uploader elements being added/removed
            const textInputField = document.querySelector('.text-input-field') || inputInner.closest('.text-input-field');
            if (textInputField) {
                const uploaderObserver = new MutationObserver((mutations) => {
                    // Check for any child list changes that might indicate uploader appearance
                    setTimeout(notifyHeightChange, 50);
                });
                uploaderObserver.observe(textInputField, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['style', 'class']
                });
            }
            
            return getTotalHeight();
        })();
        """
    
    // JavaScript to observe menu visibility changes
    private let observeMenuVisibilityScript = """
        (function() {
            function checkMenu() {
                // 1. Check Angular CDK overlay popups (excluding tooltips)
                const overlay = document.querySelector('.cdk-overlay-container');
                let hasRealPopup = false;
                if (overlay) {
                    const children = Array.from(overlay.children);
                    hasRealPopup = children.some(child => {
                        return !child.querySelector('[role="tooltip"], .mat-mdc-tooltip-panel, .mat-tooltip-panel, .gmat-tooltip-panel');
                    });
                }
                
                // 2. Check for standard menus
                const hasMenu = document.querySelector('[role="menu"], [role="listbox"], .mat-menu-panel, .popover, .dropdown-menu') !== null;
                
                // 3. Check for Google account menu (aria-expanded="true" on the avatar button)
                const hasExpandedButton = document.querySelector('.gb_B[aria-expanded="true"], [role="button"][aria-expanded="true"]') !== null;
                
                // 4. Check for visible iframe-based menus (Google account dropdown)
                const iframeContainers = document.querySelectorAll('.gb_2d iframe[name="account"]');
                let hasVisibleIframe = false;
                iframeContainers.forEach(iframe => {
                    const container = iframe.parentElement;
                    if (container && container.style.visibility !== 'hidden' && container.style.height !== '0px') {
                        hasVisibleIframe = true;
                    }
                });
                
                return hasRealPopup || hasMenu || hasExpandedButton || hasVisibleIframe;
            }

            let lastVisible = false;
            const observer = new MutationObserver(() => {
                const isVisible = checkMenu();
                if (isVisible !== lastVisible) {
                    lastVisible = isVisible;
                    console.log('[ChatBar] Menu visibility changed:', isVisible);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.menuVisibilityChanged) {
                        window.webkit.messageHandlers.menuVisibilityChanged.postMessage({ isVisible: isVisible });
                    }
                }
            });
            
            observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['aria-expanded', 'style', 'class'] });
            
            // Initial check
            const isVisible = checkMenu();
            if (isVisible) {
                lastVisible = true;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.menuVisibilityChanged) {
                    window.webkit.messageHandlers.menuVisibilityChanged.postMessage({ isVisible: true });
                }
            }
        })();
        """
    
    private var inputHeightObserverSetup = false
    private var baseInputHeight: CGFloat = 0
    private var isMenuVisible = false
    private var lastInputHeight: CGFloat = 0
    private var isAdjustingHeightProgrammatically = false

    init(contentView: NSView) {
        let width = UserDefaults.standard.double(forKey: UserDefaultsKeys.panelWidth.rawValue)
        let height = UserDefaults.standard.double(forKey: UserDefaultsKeys.panelHeight.rawValue)
        let initWidth = width > 0 ? width : Constants.defaultWidth
        let initHeight = height > 0 ? height : Constants.defaultHeight

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initWidth, height: initHeight),
            styleMask: [
                .nonactivatingPanel,
                .resizable,
                .borderless
            ],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        self.delegate = self

        configureWindow()
        configureAppearance()

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.webViewSearchDelay) { [weak self] in
            guard let self = self, let content = self.contentView else { return }
            self.findWebView(in: content)
            print("[ChatBar] WebView found: \(self.webView != nil)")
            self.startPolling()
        }
    }

    private func findWebView(in view: NSView) {
        if let wk = view as? WKWebView {
            self.webView = wk
            wk.navigationDelegate = self
            setupInputHeightObserver()
            return
        }
        for subview in view.subviews {
            findWebView(in: subview)
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Scroll to top after page finishes loading to ensure header is visible
        if !hasScrolledToTopAfterLoad {
            hasScrolledToTopAfterLoad = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.scrollToTop()
            }
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
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
    
    /// Scroll the WebView content to the top to ensure header is visible
    private func scrollToTop() {
        let scrollScript = """
            window.scrollTo(0, 0);
            document.documentElement.scrollTop = 0;
            document.body.scrollTop = 0;
        """
        webView?.evaluateJavaScript(scrollScript, completionHandler: nil)
    }
    
    /// Scroll the WebView content to ensure input area is visible
    private func scrollToBottom() {
        let scrollScript = """
            window.scrollTo(0, document.body.scrollHeight);
            document.documentElement.scrollTop = document.documentElement.scrollHeight;
            document.body.scrollTop = document.body.scrollHeight;
        """
        webView?.evaluateJavaScript(scrollScript, completionHandler: nil)
    }
    
    /// Setup the message handler to receive input height changes from JavaScript
    private func setupInputHeightObserver() {
        guard let webView = webView, !inputHeightObserverSetup else { return }
        inputHeightObserverSetup = true
        
        // Add message handlers
        webView.configuration.userContentController.add(self, name: "inputHeightChanged")
        webView.configuration.userContentController.add(self, name: "menuVisibilityChanged")
        
        // Delay slightly to ensure page is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.initializeInputHeightObserver()
            self?.initializeMenuVisibilityObserver()
        }
    }
    
    /// Initialize the JavaScript observer for menu visibility
    private func initializeMenuVisibilityObserver() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(observeMenuVisibilityScript, completionHandler: nil)
    }
    
    /// Initialize the JavaScript observer for input height
    private func initializeInputHeightObserver() {
        guard let webView = webView else { return }
        
        webView.evaluateJavaScript(observeInputHeightScript) { [weak self] result, error in
            if let height = result as? CGFloat, height > 0 {
                self?.baseInputHeight = height
                print("[ChatBar] Base input height: \(height)")
            }
        }
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "inputHeightChanged",
           let body = message.body as? [String: Any],
           let height = body["height"] as? CGFloat {
            lastInputHeight = height
            adjustPanelHeight()
        } else if message.name == "menuVisibilityChanged",
                  let body = message.body as? [String: Any],
                  let isVisible = body["isVisible"] as? Bool {
            isMenuVisible = isVisible
            adjustPanelHeight()
        }
    }
    
    /// Adjust panel height based on input height and menu visibility
    private func adjustPanelHeight() {
        // Only adjust when not expanded (on start page or in basic chat bar mode)
        guard !isExpanded else { return }
        
        var targetHeight: CGFloat = Constants.defaultHeight
        
        // 1. Consider Input Height
        if lastInputHeight > 0 && baseInputHeight > 0 {
            let heightDiff = lastInputHeight - baseInputHeight
            targetHeight = max(Constants.defaultHeight, min(Constants.defaultHeight + heightDiff, Constants.maxInputExpandHeight))
        }
        
        // 2. Consider Menu Visibility
        if isMenuVisible {
            // Expand to a taller height to accommodate menus
            targetHeight = max(targetHeight, Constants.menuExpandHeight)
        }
        
        // Don't resize if panel height change is negligible
        guard abs(frame.height - targetHeight) > 2 else { return }
        
        print("[ChatBar] Adjusting height: inputHeight=\(lastInputHeight), isMenuVisible=\(isMenuVisible), oldHeight=\(frame.height), newHeight=\(targetHeight)")
        
        let currentFrame = frame
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y, // Maintain bottom pivot
            width: currentFrame.width,
            height: targetHeight
        )
        
        // Ensure we don't exceed screen boundaries
        if let screen = currentScreen {
            let maxAvailableHeight = screen.visibleFrame.maxY - currentFrame.origin.y - Constants.topPadding
            if newFrame.height > maxAvailableHeight {
                // If the screen isn't tall enough, we might need to shift the origin.y down
                // but usually the chat bar is at the bottom, so this shouldn't be a huge issue
                // unless the user dragged it way up.
            }
        }
        
        // Animate the resize
        isAdjustingHeightProgrammatically = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(newFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.isAdjustingHeightProgrammatically = false
        })
    }

    private func configureWindow() {
        isFloatingPanel = true
        level = .floating
        isMovable = true
        isMovableByWindowBackground = true

        collectionBehavior.insert(.fullScreenAuxiliary)
        collectionBehavior.insert(.canJoinAllSpaces)

        minSize = NSSize(width: Constants.minWidth, height: Constants.minHeight)
        maxSize = NSSize(width: Constants.maxWidth, height: Constants.maxHeight)
    }

    private func configureAppearance() {
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false

        if let contentView = contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = Constants.cornerRadius
            contentView.layer?.masksToBounds = true
            contentView.layer?.borderWidth = Constants.borderWidth
            contentView.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    private func startPolling() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.initialPollingDelay) { [weak self] in
            self?.pollingTimer = Timer.scheduledTimer(withTimeInterval: Constants.pollingInterval, repeats: true) { [weak self] _ in
                self?.checkForConversation()
            }
        }
    }

    private func checkForConversation() {
        guard !isExpanded else { return }
        guard let webView = webView else { return }

        webView.evaluateJavaScript(checkConversationScript) { [weak self] result, _ in
            if let inConversation = result as? Bool, inConversation {
                DispatchQueue.main.async {
                    self?.expandToNormalSize()
                }
            }
        }
    }

    private func expandToNormalSize() {
        guard !isExpanded else { return }
        isExpanded = true
        pollingTimer?.invalidate()

        let currentFrame = self.frame

        // Calculate the maximum available height from the current position to the top of the screen
        guard let screen = currentScreen else { return }
        let visibleFrame = screen.visibleFrame
        let maxAvailableHeight = visibleFrame.maxY - currentFrame.origin.y
        
        // Use the smaller of expandedHeight and available space, with some padding
        let targetHeight = min(self.expandedHeight, maxAvailableHeight - Constants.topPadding)
        let clampedHeight = max(targetHeight, initialSize.height) // Don't shrink below initial size

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y,
                width: currentFrame.width,
                height: clampedHeight
            )
            self.animator().setFrame(newFrame, display: true)
        }
        
        // Ensure input is focused and handler attached when expanding
        focusInput()
    }

    func resetToInitialSize() {
        isExpanded = false
        pollingTimer?.invalidate()

        let currentFrame = frame

        setFrame(NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y,
            width: currentFrame.width,
            height: initialSize.height
        ), display: true)

        startPolling()
    }

    /// Called when panel is shown - check if we should be expanded or initial size
    func checkAndAdjustSize() {
        guard let webView = webView else { return }

        // Focus the input field (and attaching handler)
        focusInput()

        webView.evaluateJavaScript(checkConversationScript) { [weak self] result, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let inConversation = result as? Bool, inConversation {
                    // In conversation - ensure expanded
                    if !self.isExpanded {
                        self.expandToNormalSize()
                    } else {
                        // Already expanded - but verify we fit on the current screen
                        // This fixes the issue when moving between screens (e.g. vertical to horizontal)
                        self.ensureValidExpandedSize()
                    }
                } else {
                    // On start page - ensure initial size
                    if self.isExpanded {
                        self.resetToInitialSize()
                    }
                }
            }
        }
    }
    
    /// Re-calculates and applies the correct expanded size for the current screen
    private func ensureValidExpandedSize() {
        guard isExpanded, let screen = currentScreen else { return }
        
        let visibleFrame = screen.visibleFrame
        var newOriginY = frame.origin.y
        
        // 1. Ensure bottom doesn't go below dock/screen bottom
        if newOriginY < visibleFrame.origin.y {
             newOriginY = visibleFrame.origin.y
        }
        
        let maxAvailableHeight = visibleFrame.maxY - newOriginY
        
        // Use the smaller of expandedHeight and available space, with some padding
        let targetHeight = min(self.expandedHeight, maxAvailableHeight - Constants.topPadding)
        let clampedHeight = max(targetHeight, initialSize.height)
        
        // Only adjust if there's a significant difference (to avoid jitter) or if we moved the origin
        let heightChanged = abs(frame.height - clampedHeight) > 5
        let originChanged = abs(frame.origin.y - newOriginY) > 1
        
        if heightChanged || originChanged {
            print("[ChatBar] Adjusting expanded size: y=\(newOriginY), height=\(clampedHeight)")
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                let newFrame = NSRect(
                    x: frame.origin.x,
                    y: newOriginY, // Use the potentially corrected Y
                    width: frame.width,
                    height: clampedHeight
                )
                self.animator().setFrame(newFrame, display: true)
            }
        }
    }


    /// Focus the input field in the WebView
    func focusInput() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(focusInputScript, completionHandler: nil)
    }

    deinit {
        pollingTimer?.invalidate()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "inputHeightChanged")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "menuVisibilityChanged")
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        // Only persist size when:
        // 1. Not in expanded state
        // 2. Not currently adjusting height programmatically (for input/menu)
        // 3. No menu is visible (to avoid saving the menu-expanded height)
        guard !isExpanded && !isAdjustingHeightProgrammatically && !isMenuVisible else { return }

        UserDefaults.standard.set(frame.width, forKey: UserDefaultsKeys.panelWidth.rawValue)
        UserDefaults.standard.set(frame.height, forKey: UserDefaultsKeys.panelHeight.rawValue)
    }

    // MARK: - Keyboard Handling

    /// Handle ESC key to hide the chat bar
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    // MARK: - Screen Boundary Handling
    
    /// Constrain the window to stay within the current screen bounds
    func constrainToScreen() {
        guard let screen = currentScreen else { return }
        let screenFrame = screen.visibleFrame
        var newFrame = self.frame
        
        // Ensure the window doesn't exceed screen height
        if newFrame.height > screenFrame.height {
            newFrame.size.height = screenFrame.height
        }
        
        // Ensure the window doesn't go above the screen top
        if newFrame.maxY > screenFrame.maxY {
            newFrame.origin.y = screenFrame.maxY - newFrame.height
        }
        
        // Ensure the window doesn't go below the screen bottom
        if newFrame.origin.y < screenFrame.origin.y {
            newFrame.origin.y = screenFrame.origin.y
        }
        
        // Ensure the window doesn't go beyond the left edge
        if newFrame.origin.x < screenFrame.origin.x {
            newFrame.origin.x = screenFrame.origin.x
        }
        
        // Ensure the window doesn't go beyond the right edge
        if newFrame.maxX > screenFrame.maxX {
            newFrame.origin.x = screenFrame.maxX - newFrame.width
        }
        
        // Apply the constrained frame if it changed
        if newFrame != self.frame {
            setFrame(newFrame, display: true)
        }
    }
}


extension ChatBarPanel {

    struct Constants {
        static let defaultWidth: CGFloat = 500
        static let defaultHeight: CGFloat = 202
        static let minWidth: CGFloat = 300
        static let minHeight: CGFloat = 150
        static let maxWidth: CGFloat = 900
        static let maxHeight: CGFloat = 900
        static let cornerRadius: CGFloat = 30
        static let borderWidth: CGFloat = 0.5
        static let expandedScreenRatio: CGFloat = 0.7
        static let animationDuration: Double = 0.3
        static let pollingInterval: TimeInterval = 1.0
        static let initialPollingDelay: TimeInterval = 3.0
        static let webViewSearchDelay: TimeInterval = 0.5
        static let topPadding: CGFloat = 20 // Padding from the top of the screen
        static let maxInputExpandHeight: CGFloat = 400 // Maximum height when input expands
        static let menuExpandHeight: CGFloat = 550 // Height to show menus

    }
}
