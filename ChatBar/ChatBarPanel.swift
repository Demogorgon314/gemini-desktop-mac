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

    // JavaScript to observe input field height changes - with persistent monitoring
    private let observeInputHeightScript = """
        (function() {
            // Prevent multiple initializations of the body observer
            if (window.__chatBarBodyObserverInitialized) {
                // Just try to setup observer for current input if not already done
                setupInputObserver();
                return getCurrentInputHeight();
            }
            window.__chatBarBodyObserverInitialized = true;

            let currentResizeObserver = null;
            let currentMutationObserver = null;
            let lastHeight = 0;

            // Function to notify native code of height change
            function notifyHeightChange(height) {
                if (Math.abs(height - lastHeight) > 2) {
                    lastHeight = height;
                    console.log('[ChatBar] Input height changed:', height);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.inputHeightChanged) {
                        window.webkit.messageHandlers.inputHeightChanged.postMessage({ height: height });
                    }
                }
            }

            // Get current input height
            function getCurrentInputHeight() {
                const inputInner = document.querySelector('.text-input-field_textarea-inner');
                return inputInner ? inputInner.getBoundingClientRect().height : null;
            }

            // Setup observer for a specific input element
            function setupInputObserver() {
                const inputInner = document.querySelector('.text-input-field_textarea-inner');

                if (!inputInner) {
                    console.log('[ChatBar] Input inner not found, will retry...');
                    return null;
                }

                // Check if this specific element already has an observer
                if (inputInner.dataset.hasHeightObserver === 'true') {
                    return inputInner.getBoundingClientRect().height;
                }

                console.log('[ChatBar] Setting up observer for input element');
                inputInner.dataset.hasHeightObserver = 'true';

                // Clean up old observers if they exist
                if (currentResizeObserver) {
                    currentResizeObserver.disconnect();
                }
                if (currentMutationObserver) {
                    currentMutationObserver.disconnect();
                }

                // Store initial height
                lastHeight = inputInner.getBoundingClientRect().height;
                console.log('[ChatBar] Initial input height:', lastHeight);

                // Create a ResizeObserver to watch for size changes
                currentResizeObserver = new ResizeObserver((entries) => {
                    for (const entry of entries) {
                        notifyHeightChange(entry.contentRect.height);
                    }
                });

                currentResizeObserver.observe(inputInner);

                // Also use MutationObserver to watch for style attribute changes
                currentMutationObserver = new MutationObserver((mutations) => {
                    for (const mutation of mutations) {
                        if (mutation.type === 'attributes' && mutation.attributeName === 'style') {
                            const height = inputInner.getBoundingClientRect().height;
                            notifyHeightChange(height);
                        }
                    }
                });

                currentMutationObserver.observe(inputInner, {
                    attributes: true,
                    attributeFilter: ['style']
                });

                // Also observe the ql-editor for content changes
                const qlEditor = inputInner.querySelector('.ql-editor') || document.querySelector('.ql-editor');
                if (qlEditor && !qlEditor.dataset.hasInputListener) {
                    qlEditor.dataset.hasInputListener = 'true';
                    currentResizeObserver.observe(qlEditor);

                    // Watch for input events on the editor
                    qlEditor.addEventListener('input', () => {
                        setTimeout(() => {
                            const height = inputInner.getBoundingClientRect().height;
                            notifyHeightChange(height);
                        }, 10);
                    });
                }

                return lastHeight;
            }

            // Use MutationObserver on document body to detect when input field is added/replaced
            // This handles SPA navigation where the DOM is dynamically rebuilt
            const bodyObserver = new MutationObserver((mutations) => {
                const inputInner = document.querySelector('.text-input-field_textarea-inner');
                if (inputInner && inputInner.dataset.hasHeightObserver !== 'true') {
                    console.log('[ChatBar] Detected new input element, setting up observer');
                    setupInputObserver();
                }
            });

            bodyObserver.observe(document.body, {
                childList: true,
                subtree: true
            });

            // Also set up a periodic check as a fallback (every 2 seconds)
            setInterval(() => {
                const inputInner = document.querySelector('.text-input-field_textarea-inner');
                if (inputInner && inputInner.dataset.hasHeightObserver !== 'true') {
                    console.log('[ChatBar] Periodic check: setting up observer for input');
                    setupInputObserver();
                }
            }, 2000);

            // Initial setup
            return setupInputObserver();
        })();
        """

    private var inputHeightObserverSetup = false
    private var baseInputHeight: CGFloat = 0

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

    /// Scroll the WebView content to the top to ensure header is visible
    private func scrollToTop() {
        let scrollScript = """
            window.scrollTo(0, 0);
            document.documentElement.scrollTop = 0;
            document.body.scrollTop = 0;
        """
        webView?.evaluateJavaScript(scrollScript, completionHandler: nil)
    }


    /// Setup the message handler to receive input height changes from JavaScript
    private func setupInputHeightObserver() {
        guard let webView = webView, !inputHeightObserverSetup else { return }
        inputHeightObserverSetup = true

        // Add message handler for input height changes
        webView.configuration.userContentController.add(self, name: "inputHeightChanged")

        // Delay slightly to ensure page is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.initializeInputHeightObserver()
        }
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
        guard message.name == "inputHeightChanged",
              let body = message.body as? [String: Any],
              let height = body["height"] as? CGFloat else { return }

        adjustHeightForInput(newInputHeight: height)
    }

    /// Adjust panel height based on input field height changes
    private func adjustHeightForInput(newInputHeight: CGFloat) {
        // Only adjust when not expanded (on start page)
        guard !isExpanded else { return }

        // If base height is not set yet, set it now and don't adjust
        if baseInputHeight <= 0 {
            baseInputHeight = newInputHeight
            print("[ChatBar] Set base input height: \(baseInputHeight)")
            return
        }

        // Calculate height difference from base (can be negative for shrinking)
        let heightDiff = newInputHeight - baseInputHeight

        // Calculate new panel height using default height as baseline (not user-saved size)
        // This ensures consistent behavior regardless of user's saved panel size
        let newPanelHeight = max(
            Constants.defaultHeight,
            min(Constants.defaultHeight + heightDiff, Constants.maxInputExpandHeight)
        )

        // Don't resize if panel height change is negligible
        guard abs(frame.height - newPanelHeight) > 2 else { return }

        print("[ChatBar] Adjusting height: base=\(baseInputHeight), new=\(newInputHeight), diff=\(heightDiff), panelHeight=\(newPanelHeight)")

        let currentFrame = frame

        // Keep the bottom of the panel fixed, expand upward
        // In macOS coordinates, origin is bottom-left, so we keep origin.y the same
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y,  // Keep bottom position fixed
            width: currentFrame.width,
            height: newPanelHeight
        )

        // Animate the resize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(newFrame, display: true)
        }
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

        // Add global click monitor to dismiss when clicking outside
        setupClickOutsideMonitor()
    }

    private var clickOutsideMonitor: Any?

    private func setupClickOutsideMonitor() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            self.orderOut(nil)
        }
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

    /// Focus the input field in the WebView
    func focusInput() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(focusInputScript, completionHandler: nil)
    }

    deinit {
        pollingTimer?.invalidate()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "inputHeightChanged")
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        // Only persist size when in initial (non-expanded) state
        guard !isExpanded else { return }

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

    }
}
