//
//  MenuBarPopoverPanel.swift
//  GeminiDesktop
//
//  Created on 2025-12-19.
//

import SwiftUI
import AppKit
import WebKit

/// A panel that appears below the menu bar status item, showing a mini Gemini chat interface
class MenuBarPopoverPanel: NSPanel, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {

    private weak var webView: WKWebView?
    private var clickOutsideMonitor: Any?
    private var inputHeightObserverSetup = false
    private var baseInputHeight: CGFloat = 0
    private var lastInputHeight: CGFloat = 0
    private var isMenuVisible = false
    private var isAdjustingHeightProgrammatically = false
    private var hasScrolledToTopAfterLoad = false

    // JavaScript to observe input field height changes
    private let observeInputHeightScript = """
        (function() {
            if (window.__menuBarPopoverInputObserverInitialized) {
                return getCurrentInputHeight();
            }
            window.__menuBarPopoverInputObserverInitialized = true;

            let currentResizeObserver = null;
            let lastHeight = 0;

            function notifyHeightChange(height) {
                if (Math.abs(height - lastHeight) > 2) {
                    lastHeight = height;
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.popoverInputHeightChanged) {
                        window.webkit.messageHandlers.popoverInputHeightChanged.postMessage({ height: height });
                    }
                }
            }

            function getCurrentInputHeight() {
                const inputInner = document.querySelector('.text-input-field_textarea-inner');
                return inputInner ? inputInner.getBoundingClientRect().height : null;
            }

            function setupInputObserver() {
                const inputInner = document.querySelector('.text-input-field_textarea-inner');
                if (!inputInner || inputInner.dataset.hasPopoverHeightObserver === 'true') {
                    return inputInner ? inputInner.getBoundingClientRect().height : null;
                }

                inputInner.dataset.hasPopoverHeightObserver = 'true';

                if (currentResizeObserver) {
                    currentResizeObserver.disconnect();
                }

                lastHeight = inputInner.getBoundingClientRect().height;

                currentResizeObserver = new ResizeObserver((entries) => {
                    for (const entry of entries) {
                        notifyHeightChange(entry.contentRect.height);
                    }
                });

                currentResizeObserver.observe(inputInner);

                const qlEditor = inputInner.querySelector('.ql-editor') || document.querySelector('.ql-editor');
                if (qlEditor && !qlEditor.dataset.hasPopoverInputListener) {
                    qlEditor.dataset.hasPopoverInputListener = 'true';
                    currentResizeObserver.observe(qlEditor);
                    qlEditor.addEventListener('input', () => {
                        setTimeout(() => {
                            const height = inputInner.getBoundingClientRect().height;
                            notifyHeightChange(height);
                        }, 10);
                    });
                }

                return lastHeight;
            }

            const bodyObserver = new MutationObserver(() => {
                const inputInner = document.querySelector('.text-input-field_textarea-inner');
                if (inputInner && inputInner.dataset.hasPopoverHeightObserver !== 'true') {
                    setupInputObserver();
                }
            });

            bodyObserver.observe(document.body, { childList: true, subtree: true });

            return setupInputObserver();
        })();
        """

    // JavaScript to observe menu visibility
    private let observeMenuVisibilityScript = """
        (function() {
            function checkMenu() {
                const overlay = document.querySelector('.cdk-overlay-container');
                let hasRealPopup = false;
                if (overlay) {
                    const children = Array.from(overlay.children);
                    hasRealPopup = children.some(child => {
                        return !child.querySelector('[role="tooltip"], .mat-mdc-tooltip-panel');
                    });
                }
                const hasMenu = document.querySelector('[role="menu"], [role="listbox"], .mat-menu-panel') !== null;
                const hasExpandedButton = document.querySelector('[role="button"][aria-expanded="true"]') !== null;
                return hasRealPopup || hasMenu || hasExpandedButton;
            }

            let lastVisible = false;
            const observer = new MutationObserver(() => {
                const isVisible = checkMenu();
                if (isVisible !== lastVisible) {
                    lastVisible = isVisible;
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.popoverMenuVisibilityChanged) {
                        window.webkit.messageHandlers.popoverMenuVisibilityChanged.postMessage({ isVisible: isVisible });
                    }
                }
            });

            observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['aria-expanded'] });
        })();
        """

    // JavaScript to focus input
    private let focusInputScript = """
        (function() {
            const input = document.querySelector('rich-textarea[aria-label="Enter a prompt here"]') ||
                          document.querySelector('[contenteditable="true"]') ||
                          document.querySelector('textarea');
            if (input) {
                input.focus();
                window.scrollTo(0, 0);
                return true;
            }
            return false;
        })();
        """

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Constants.defaultWidth, height: Constants.defaultHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        self.delegate = self

        configureWindow()
        configureAppearance()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, let content = self.contentView else { return }
            self.findWebView(in: content)
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

    private func configureWindow() {
        isFloatingPanel = true
        level = .popUpMenu
        isMovable = false
        isMovableByWindowBackground = false

        collectionBehavior.insert(.fullScreenAuxiliary)
        collectionBehavior.insert(.transient)

        hidesOnDeactivate = false
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

    // MARK: - Positioning

    /// Position the panel below the status item button
    func positionBelow(statusItemButton: NSStatusBarButton) {
        guard let buttonWindow = statusItemButton.window else { return }

        let buttonFrameInScreen = buttonWindow.convertToScreen(statusItemButton.frame)
        let panelWidth = frame.width
        let panelHeight = frame.height

        // Center horizontally below the button
        let x = buttonFrameInScreen.midX - panelWidth / 2
        // Position just below the menu bar
        let y = buttonFrameInScreen.minY - panelHeight - Constants.verticalOffset

        // Ensure panel stays within screen bounds
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonFrameInScreen.origin) }) ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            var adjustedX = x
            var adjustedY = y

            // Adjust horizontal position if needed
            if adjustedX < screenFrame.minX {
                adjustedX = screenFrame.minX + Constants.horizontalPadding
            } else if adjustedX + panelWidth > screenFrame.maxX {
                adjustedX = screenFrame.maxX - panelWidth - Constants.horizontalPadding
            }

            // Adjust vertical position if needed (shouldn't happen often for menu bar popover)
            if adjustedY < screenFrame.minY {
                adjustedY = screenFrame.minY + Constants.verticalPadding
            }

            setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
        } else {
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: - Show/Hide with Animation

    func showPopover(below statusItemButton: NSStatusBarButton) {
        positionBelow(statusItemButton: statusItemButton)

        // Setup initial state for animation
        alphaValue = 0
        let finalFrame = frame
        let startFrame = NSRect(
            x: finalFrame.origin.x,
            y: finalFrame.origin.y + Constants.animationOffset,
            width: finalFrame.width,
            height: finalFrame.height
        )
        setFrame(startFrame, display: false)

        orderFront(nil)
        makeKeyAndOrderFront(nil)

        // Animate in: fade in + slide down
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.showAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
            self.animator().setFrame(finalFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.setupClickOutsideMonitor()
            self?.focusInput()
        })
    }

    func hidePopover() {
        removeClickOutsideMonitor()

        let currentFrame = frame
        let endFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + Constants.animationOffset,
            width: currentFrame.width,
            height: currentFrame.height
        )

        // Animate out: fade out + slide up
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.hideAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1 // Reset for next show
        })
    }

    /// Hide popover immediately without animation (used when transitioning to main window)
    func hidePopoverImmediately() {
        removeClickOutsideMonitor()
        orderOut(nil)
        alphaValue = 1
    }

    // MARK: - Click Outside Monitor

    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.isVisible else { return }

            // Check if click is outside the panel
            let clickLocationInScreen = NSEvent.mouseLocation

            if !self.frame.contains(clickLocationInScreen) {
                self.hidePopover()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - WebView Integration

    private func setupInputHeightObserver() {
        guard let webView = webView, !inputHeightObserverSetup else { return }
        inputHeightObserverSetup = true

        webView.configuration.userContentController.add(self, name: "popoverInputHeightChanged")
        webView.configuration.userContentController.add(self, name: "popoverMenuVisibilityChanged")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.initializeObservers()
        }
    }

    private func initializeObservers() {
        guard let webView = webView else { return }

        webView.evaluateJavaScript(observeInputHeightScript) { [weak self] result, _ in
            if let height = result as? CGFloat, height > 0 {
                self?.baseInputHeight = height
            }
        }

        webView.evaluateJavaScript(observeMenuVisibilityScript, completionHandler: nil)
    }

    func focusInput() {
        webView?.evaluateJavaScript(focusInputScript, completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

        let host = url.host?.lowercased() ?? ""
        let isGoogleDomain = host.hasSuffix("google.com") || host.hasSuffix("googleapis.com")

        if navigationAction.navigationType == .linkActivated && !isGoogleDomain {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    private func scrollToTop() {
        let scrollScript = """
            window.scrollTo(0, 0);
            document.documentElement.scrollTop = 0;
            document.body.scrollTop = 0;
        """
        webView?.evaluateJavaScript(scrollScript, completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "popoverInputHeightChanged",
           let body = message.body as? [String: Any],
           let height = body["height"] as? CGFloat {
            lastInputHeight = height
            adjustPanelHeight()
        } else if message.name == "popoverMenuVisibilityChanged",
                  let body = message.body as? [String: Any],
                  let isVisible = body["isVisible"] as? Bool {
            isMenuVisible = isVisible
            adjustPanelHeight()
        }
    }

    private func adjustPanelHeight() {
        var targetHeight: CGFloat = Constants.defaultHeight

        if lastInputHeight > 0 && baseInputHeight > 0 {
            let heightDiff = lastInputHeight - baseInputHeight
            targetHeight = max(Constants.defaultHeight, min(Constants.defaultHeight + heightDiff, Constants.maxHeight))
        }

        if isMenuVisible {
            targetHeight = max(targetHeight, Constants.menuExpandHeight)
        }

        guard abs(frame.height - targetHeight) > 2 else { return }

        let currentFrame = frame
        // Grow upward (keep bottom position, adjust top)
        let newY = currentFrame.origin.y + currentFrame.height - targetHeight
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newY,
            width: currentFrame.width,
            height: targetHeight
        )

        isAdjustingHeightProgrammatically = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(newFrame, display: true)
        }, completionHandler: {
            self.isAdjustingHeightProgrammatically = false
        })
    }

    // MARK: - Keyboard Handling

    override func cancelOperation(_ sender: Any?) {
        hidePopover()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Cleanup

    deinit {
        removeClickOutsideMonitor()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "popoverInputHeightChanged")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "popoverMenuVisibilityChanged")
    }
}

// MARK: - Constants

extension MenuBarPopoverPanel {

    struct Constants {
        static let defaultWidth: CGFloat = 400
        static let defaultHeight: CGFloat = 500
        static let maxHeight: CGFloat = 600
        static let menuExpandHeight: CGFloat = 550
        static let cornerRadius: CGFloat = 12
        static let borderWidth: CGFloat = 0.5
        static let verticalOffset: CGFloat = 4
        static let verticalPadding: CGFloat = 10
        static let horizontalPadding: CGFloat = 10

        // Animation
        static let showAnimationDuration: TimeInterval = 0.2
        static let hideAnimationDuration: TimeInterval = 0.15
        static let animationOffset: CGFloat = 8
    }
}
