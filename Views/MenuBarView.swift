//
//  MenuBarContentView.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit

struct MenuBarView: View {
    @Binding var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Open Gemini Desktop") {
                coordinator.openMainWindow()
            }

            Button("Toggle Chat Bar") {
                coordinator.toggleChatBar()
            }

            Divider()

            Button("Settings...") {
                openSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            coordinator.openWindowAction = { id in
                openWindow(id: id)
            }
        }
    }

    private func openSettingsWindow() {
        if let settingsWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue == GeminiDesktopApp.Constants.settingsWindowID || $0.title == GeminiDesktopApp.Constants.settingsWindowTitle
        }) {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: GeminiDesktopApp.Constants.settingsWindowID)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
