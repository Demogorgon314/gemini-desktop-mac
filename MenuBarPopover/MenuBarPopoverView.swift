//
//  MenuBarPopoverView.swift
//  GeminiDesktop
//
//  Created on 2025-12-19.
//

import SwiftUI
import WebKit

/// SwiftUI view for the menu bar popover content
struct MenuBarPopoverView: View {
    let webView: WKWebView
    let onExpandToMain: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeminiWebView(webView: webView)

            // Control buttons - appear on hover
            HStack(spacing: Constants.buttonSpacing) {
                // Expand to main window button
                Button(action: onExpandToMain) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: Constants.buttonFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Expand to main window")

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: Constants.buttonFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(Constants.buttonPadding)
            .opacity(isHovering ? 1 : 0.6)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: Constants.hoverAnimationDuration)) {
                    isHovering = hovering
                }
            }
        }
    }
}

extension MenuBarPopoverView {

    struct Constants {
        static let buttonFontSize: CGFloat = 12
        static let buttonSize: CGFloat = 28
        static let buttonPadding: CGFloat = 12
        static let buttonSpacing: CGFloat = 6
        static let hoverAnimationDuration: Double = 0.2
    }
}
