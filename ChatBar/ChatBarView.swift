//
//  ChatBarContent.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import WebKit
import AppKit

// MARK: - Native Drag Handle View

/// A native NSView that handles window dragging properly
class DragHandleNSView: NSView {
    var onTap: (() -> Void)?
    private var isDragging = false
    private var mouseDownLocation: NSPoint?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        isDragging = false
        mouseDownLocation = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        
        // Mark as dragging after minimal movement
        if !isDragging {
            isDragging = true
        }
        
        // Use native window dragging - this is the smoothest approach
        window.performDrag(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            // It was a click, not a drag
            onTap?()
        } else {
            // Drag ended - constrain window to screen bounds
            if let chatBarPanel = self.window as? ChatBarPanel {
                chatBarPanel.constrainToScreen()
            }
        }
        isDragging = false
        mouseDownLocation = nil
    }
}

/// SwiftUI wrapper for the native drag handle
struct DragHandleView: NSViewRepresentable {
    let onTap: () -> Void
    
    func makeNSView(context: Context) -> DragHandleNSView {
        let view = DragHandleNSView()
        view.onTap = onTap
        return view
    }
    
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {
        nsView.onTap = onTap
    }
}

// MARK: - ChatBarView

struct ChatBarView: View {
    let webView: WKWebView
    let onExpandToMain: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeminiWebView(webView: webView)

            // Button container with hover detection
            HStack(spacing: Constants.buttonSpacing) {
                // Drag handle button - supports both drag and click
                ZStack {
                    // Visual appearance
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: Constants.buttonFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                        .background(.ultraThinMaterial, in: Circle())
                        .allowsHitTesting(false)
                    
                    // Native drag handling overlay
                    DragHandleView(onTap: onExpandToMain)
                        .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                        .clipShape(Circle())
                }
                
                // Close button - appears on hover
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: Constants.buttonFontSize, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(Constants.buttonPadding)
            .offset(x: Constants.buttonOffsetX)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: Constants.hoverAnimationDuration)) {
                    isHovering = hovering
                }
            }
        }
    }
}

extension ChatBarView {

    struct Constants {
        static let buttonFontSize: CGFloat = 14
        static let buttonSize: CGFloat = 38
        static let buttonPadding: CGFloat = 16
        static let buttonOffsetX: CGFloat = -2
        static let dragThreshold: CGFloat = 3
        static let buttonSpacing: CGFloat = 8
        static let hoverAnimationDuration: Double = 0.2
    }

}

