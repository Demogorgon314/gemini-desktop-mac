//
//  GeminiDesktopApp.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import KeyboardShortcuts
import AppKit
import Combine

// MARK: - Keyboard Shortcut Definition
extension KeyboardShortcuts.Name {
    static let bringToFront = Self("bringToFront", default: nil)
}

// MARK: - Main App
@main
struct GeminiDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var coordinator = AppCoordinator()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Gemini Desktop", id: "main") {
            MainWindowContent(coordinator: $coordinator)
                .toolbarBackground(Color(red: 241/255, green: 244/255, blue: 248/255), for: .windowToolbar)
                .frame(minWidth: 400, minHeight: 300)
        }
        .defaultSize(width: 1000, height: 700)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Settings", id: "settings") {
            ScrollView {
                SettingsView(coordinator: $coordinator)
            }
            .frame(minWidth: 500, minHeight: 200)
        }
        .defaultSize(width: 500, height: 200)

        MenuBarExtra {
            MenuBarContentView(coordinator: coordinator)
        } label: {
            Image(systemName: "sparkle")
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        KeyboardShortcuts.onKeyDown(for: .bringToFront) { [self] in
            coordinator.toggleChatBar()
        }
    }

    private func openSettingsWindow() {
        if let settingsWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "settings" || $0.title == "Settings"
        }) {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "settings")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Menu Bar Scene
struct MenuBarScene: Scene {
    @Bindable var coordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(coordinator: coordinator)
        } label: {
            Image(systemName: "sparkle")
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Menu Bar Content View
struct MenuBarContentView: View {
    @Bindable var coordinator: AppCoordinator
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
            $0.identifier?.rawValue == "settings" || $0.title == "Settings"
        }) {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "settings")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let hideWindowAtLaunch = UserDefaults.standard.bool(forKey: "hideWindowAtLaunch")

        if hideWindowAtLaunch {
            // Hide dock icon and close main window
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    if window.identifier?.rawValue == "main" || window.title == "Gemini Desktop" {
                        window.close()
                    }
                }
            }
        } else {
            // Show dock icon (window auto-launches from SwiftUI)
            NSApp.setActivationPolicy(.regular)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Show main window when clicking dock icon (if visible)
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
        return true
    }
}
