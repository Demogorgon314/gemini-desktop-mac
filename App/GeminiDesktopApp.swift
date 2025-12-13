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
        Window(AppCoordinator.Constants.mainWindowTitle, id: Constants.mainWindowID) {
            MainWindowView(coordinator: $coordinator)
                .toolbarBackground(Color(red: Constants.toolbarColor.red, green: Constants.toolbarColor.green, blue: Constants.toolbarColor.blue), for: .windowToolbar)
                .frame(minWidth: Constants.mainWindowMinWidth, minHeight: Constants.mainWindowMinHeight)
        }
        .defaultSize(width: Constants.mainWindowDefaultWidth, height: Constants.mainWindowDefaultHeight)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window(Constants.settingsWindowTitle, id: Constants.settingsWindowID) {
            ScrollView {
                SettingsView(coordinator: $coordinator)
            }
            .frame(minWidth: Constants.settingsWindowMinWidth, minHeight: Constants.settingsWindowMinHeight)
        }
        .defaultSize(width: Constants.settingsWindowMinWidth, height: Constants.settingsWindowMinHeight)

        MenuBarExtra {
            MenuBarView(coordinator: $coordinator)
        } label: {
            Image(systemName: Constants.menuBarIcon)
                .onAppear {
                    let hideWindowAtLaunch = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hideWindowAtLaunch.rawValue)
                    if hideWindowAtLaunch {
                        NSApp.setActivationPolicy(.accessory)
                        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.hideWindowDelay) {
                            for window in NSApp.windows {
                                if window.identifier?.rawValue == Constants.mainWindowID || window.title == AppCoordinator.Constants.mainWindowTitle {
                                    window.orderOut(nil)
                                }
                            }
                        }
                    } else {
                        NSApp.setActivationPolicy(.regular)
                    }
                }
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
            $0.identifier?.rawValue == GeminiDesktopApp.Constants.settingsWindowID || $0.title == GeminiDesktopApp.Constants.settingsWindowTitle
        }) {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: GeminiDesktopApp.Constants.settingsWindowID)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Constants
extension GeminiDesktopApp {
    struct Constants {
        // Main Window
        static let mainWindowMinWidth: CGFloat = 400
        static let mainWindowMinHeight: CGFloat = 300
        static let mainWindowDefaultWidth: CGFloat = 1000
        static let mainWindowDefaultHeight: CGFloat = 700

        // Settings Window
        static let settingsWindowMinWidth: CGFloat = 500
        static let settingsWindowMinHeight: CGFloat = 200

        // Window Identifiers
        static let mainWindowID = "main"
        static let settingsWindowID = "settings"
        static let settingsWindowTitle = "Settings"

        // Appearance
        static let toolbarColor = (red: 241.0/255.0, green: 244.0/255.0, blue: 248.0/255.0)
        static let menuBarIcon = "sparkle"

        // Timing
        static let hideWindowDelay: TimeInterval = 0.1
    }
}
