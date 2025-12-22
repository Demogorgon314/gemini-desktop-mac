//
//  UserScripts.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit

/// Collection of user scripts injected into WKWebView
enum UserScripts {

    /// Message handler name for console log bridging
    static let consoleLogHandler = "consoleLog"
    
    /// Message handler name for blob downloads
    static let blobDownloadHandler = "blobDownload"

    /// Creates all user scripts to be injected into the WebView
    static func createAllScripts() -> [WKUserScript] {
        var scripts: [WKUserScript] = [
            createIMEFixScript(),
            createBlobDownloadScript()
        ]

        #if DEBUG
        scripts.insert(createConsoleLogBridgeScript(), at: 0)
        #endif

        return scripts
    }

    /// Creates a script that bridges console.log to native Swift
    private static func createConsoleLogBridgeScript() -> WKUserScript {
        WKUserScript(
            source: consoleLogBridgeSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// Creates the IME fix script that resolves the double-enter issue
    /// when using input method editors (e.g., Chinese, Japanese, Korean input)
    private static func createIMEFixScript() -> WKUserScript {
        WKUserScript(
            source: imeFixSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }
    
    /// Creates the blob download script that intercepts blob URL downloads
    /// and sends the data to native Swift for saving
    private static func createBlobDownloadScript() -> WKUserScript {
        WKUserScript(
            source: blobDownloadSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    // MARK: - Script Sources

    /// JavaScript to bridge console.log to native Swift via WKScriptMessageHandler
    private static let consoleLogBridgeSource = """
    (function() {
        const originalLog = console.log;
        console.log = function(...args) {
            originalLog.apply(console, args);
            try {
                const message = args.map(arg => {
                    if (typeof arg === 'object') {
                        return JSON.stringify(arg, null, 2);
                    }
                    return String(arg);
                }).join(' ');
                window.webkit.messageHandlers.\(consoleLogHandler).postMessage(message);
            } catch (e) {}
        };
    })();
    """

    /// JavaScript to fix IME double-enter issue on Gemini
    /// When using IME (e.g., Chinese/Japanese input), pressing Enter after completing
    /// composition would require a second Enter to send. This script detects when
    /// IME composition just ended and automatically clicks the send button.
    /// https://update.greasyfork.org/scripts/532717/阻止Gemini两次点击.user.js
    private static let imeFixSource = """
    (function() {
        'use strict';

        // IME state tracking
        let imeActive = false;
        let imeJustEnded = false;
        let lastImeEndTime = 0;
        const IME_BUFFER_TIME = 300; // Response time after IME ends (milliseconds)

        // Check if IME input just finished
        function justFinishedImeInput() {
            return imeJustEnded || (Date.now() - lastImeEndTime < IME_BUFFER_TIME);
        }

        // Handle IME composition events
        document.addEventListener('compositionstart', function(e) {
            console.log('[IME Debug] compositionstart:', {
                data: e.data,
                target: e.target?.tagName,
                previousImeActive: imeActive
            });
            imeActive = true;
            imeJustEnded = false;
        }, true);

        document.addEventListener('compositionend', function(e) {
            
            imeActive = false;
            imeJustEnded = true;
            lastImeEndTime = Date.now();
            console.log('[IME Debug] IME ended, setting imeJustEnded=true, lastImeEndTime=' + lastImeEndTime);
            setTimeout(() => {
                imeJustEnded = false;
                console.log('[IME Debug] Buffer time expired, imeJustEnded reset to false');
            }, IME_BUFFER_TIME);
        }, true);

        // Find and click the send button
        function findAndClickSendButton() {
            console.log('[IME Debug] findAndClickSendButton called');
            const selectors = [
                'button[type="submit"]',
                'button.send-button',
                'button.submit-button',
                '[aria-label="发送"]',
                '[aria-label="Send"]',
                'button:has(svg[data-icon="paper-plane"])',
                '#send-button',
            ];

            for (const selector of selectors) {
                const buttons = document.querySelectorAll(selector);
                console.log('[IME Debug] Checking selector:', selector, 'found:', buttons.length);
                for (const button of buttons) {
                    const isVisible = button.offsetParent !== null;
                    const isDisplayed = getComputedStyle(button).display !== 'none';
                    console.log('[IME Debug] Button check:', {
                        selector: selector,
                        disabled: button.disabled,
                        isVisible: isVisible,
                        isDisplayed: isDisplayed,
                        classList: button.className,
                        ariaLabel: button.getAttribute('aria-label')
                    });
                    if (button &&
                        !button.disabled &&
                        isVisible &&
                        isDisplayed) {
                        console.log('[IME Debug] Clicking button:', button);
                        button.click();
                        return true;
                    }
                }
            }

            // Fallback: try form submission
            const activeElement = document.activeElement;
            console.log('[IME Debug] No button found, trying form submission. Active element:', activeElement?.tagName);
            if (activeElement && (activeElement.tagName === 'TEXTAREA' || activeElement.tagName === 'INPUT')) {
                const form = activeElement.closest('form');
                if (form) {
                    console.log('[IME Debug] Found form, dispatching submit event');
                    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
                    return true;
                }
            }

            console.log('[IME Debug] No send button or form found');
            return false;
        }

        // Listen for Enter key
        document.addEventListener('keydown', function(e) {
            // Only log Enter key events to reduce noise
            if (e.key === 'Enter' || e.keyCode === 13) {
                console.log('[IME Debug] Enter keydown:', {
                    shiftKey: e.shiftKey,
                    ctrlKey: e.ctrlKey,
                    altKey: e.altKey,
                    imeActive: imeActive
                });
            }

            // Submit on Enter (but not Shift+Enter for new line, and not during IME composition)
            if ((e.key === 'Enter' || e.keyCode === 13) &&
                !e.shiftKey && !e.ctrlKey && !e.altKey &&
                !imeActive) {
                console.log('[IME Debug] Enter detected, attempting to click send button');
                if (findAndClickSendButton()) {
                    console.log('[IME Debug] Send button clicked successfully');
                    e.stopImmediatePropagation();
                    e.preventDefault();
                    return false;
                } else {
                    console.log('[IME Debug] Failed to find/click send button');
                }
            }
        }, true);

        // Enhance input elements
        function enhanceInputElement(input) {
            console.log('[IME Debug] Enhancing input element:', input.tagName, input.id, input.className);
            const originalKeyDown = input.onkeydown;

            input.onkeydown = function(e) {
                // Submit on Enter (but not Shift+Enter, and not during IME)
                if ((e.key === 'Enter' || e.keyCode === 13) &&
                    !e.shiftKey && !e.ctrlKey && !e.altKey &&
                    !imeActive) {
                    console.log('[IME Debug] Enhanced input: Enter detected');
                    if (findAndClickSendButton()) {
                        console.log('[IME Debug] Enhanced input: Send button clicked');
                        e.stopPropagation();
                        e.preventDefault();
                        return false;
                    }
                }
                if (originalKeyDown) return originalKeyDown.call(this, e);
            };
        }

        // Process existing and new input elements
        function processInputElements() {
            document.querySelectorAll('textarea, input[type="text"]').forEach(enhanceInputElement);
        }

        // Initial processing after page load
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
                setTimeout(processInputElements, 1000);
            });
        } else {
            setTimeout(processInputElements, 1000);
        }

        // Monitor DOM changes for new input elements
        if (window.MutationObserver) {
            const observer = new MutationObserver((mutations) => {
                mutations.forEach((mutation) => {
                    if (mutation.addedNodes && mutation.addedNodes.length > 0) {
                        mutation.addedNodes.forEach((node) => {
                            if (node.nodeType === 1) {
                                if (node.tagName === 'TEXTAREA' ||
                                    (node.tagName === 'INPUT' && node.type === 'text')) {
                                    enhanceInputElement(node);
                                }

                                const inputs = node.querySelectorAll ?
                                    node.querySelectorAll('textarea, input[type="text"]') : [];
                                if (inputs.length > 0) {
                                    inputs.forEach(enhanceInputElement);
                                }
                            }
                        });
                    }
                });
            });

            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
        }
    })();
    """
    
    /// JavaScript to intercept blob downloads and send data to native Swift
    /// This script overrides URL.createObjectURL and intercepts anchor clicks
    /// to capture blob data before it's downloaded via blob: URLs
    private static let blobDownloadSource = """
    (function() {
        'use strict';
        
        // Store original functions
        const originalCreateObjectURL = URL.createObjectURL;
        const originalRevokeObjectURL = URL.revokeObjectURL;
        
        // Map to store blob data
        const blobMap = new Map();
        
        // Override URL.createObjectURL
        URL.createObjectURL = function(blob) {
            const url = originalCreateObjectURL.call(URL, blob);
            if (blob instanceof Blob) {
                blobMap.set(url, blob);
            }
            return url;
        };
        
        // Override URL.revokeObjectURL
        URL.revokeObjectURL = function(url) {
            blobMap.delete(url);
            return originalRevokeObjectURL.call(URL, url);
        };
        
        // Intercept anchor clicks
        document.addEventListener('click', function(e) {
            const anchor = e.target.closest('a');
            if (!anchor) return;
            
            const href = anchor.href;
            if (!href || !href.startsWith('blob:')) return;
            
            const blob = blobMap.get(href);
            if (!blob) return;
            
            e.preventDefault();
            e.stopPropagation();
            
            // Read blob and send to native
            const reader = new FileReader();
            reader.onload = function() {
                const base64Data = reader.result;
                const filename = anchor.download || 'download';
                const mimeType = blob.type || 'application/octet-stream';
                
                window.webkit.messageHandlers.blobDownload.postMessage({
                    data: base64Data,
                    filename: filename,
                    mimeType: mimeType
                });
            };
            reader.readAsDataURL(blob);
        }, true);
        
        // Also intercept programmatic anchor clicks
        const originalClick = HTMLAnchorElement.prototype.click;
        HTMLAnchorElement.prototype.click = function() {
            const href = this.href;
            if (href && href.startsWith('blob:')) {
                const blob = blobMap.get(href);
                if (blob) {
                    const reader = new FileReader();
                    reader.onload = () => {
                        const base64Data = reader.result;
                        const filename = this.download || 'download';
                        const mimeType = blob.type || 'application/octet-stream';
                        
                        window.webkit.messageHandlers.blobDownload.postMessage({
                            data: base64Data,
                            filename: filename,
                            mimeType: mimeType
                        });
                    };
                    reader.readAsDataURL(blob);
                    return;
                }
            }
            return originalClick.call(this);
        };
    })();
    """
}
