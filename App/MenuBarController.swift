//
//  MenuBarController.swift
//  GeminiDesktop
//
//  Created on 2025-12-15.
//

import SwiftUI
import AppKit

/// Manages the custom NSStatusItem for menu bar interactions
/// Left-click opens ChatBar or Main Window based on settings
/// Right-click shows the context menu
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var coordinator: AppCoordinator
    
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Gemini Desktop")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            handleLeftClick()
        }
    }
    
    private func handleLeftClick() {
        guard let button = statusItem?.button else { return }

        let leftClickAction = UserDefaults.standard.string(forKey: UserDefaultsKeys.leftClickAction.rawValue) ?? "menuBarPopover"

        switch leftClickAction {
        case "mainWindow":
            coordinator.toggleMainWindow()
        case "chatBar":
            coordinator.toggleChatBar()
        default:
            // Default to menu bar popover
            coordinator.toggleMenuBarPopover(below: button)
        }
    }
    
    private func showMenu() {
        // Hide popover first so it doesn't block the menu
        coordinator.hideMenuBarPopover()

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Gemini Desktop", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        openItem.target = self
        menu.addItem(openItem)

        let popoverItem = NSMenuItem(title: "Toggle Quick Chat", action: #selector(toggleMenuBarPopover), keyEquivalent: "")
        popoverItem.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: nil)
        popoverItem.target = self
        menu.addItem(popoverItem)

        let chatBarItem = NSMenuItem(title: "Toggle Chat Bar", action: #selector(toggleChatBar), keyEquivalent: "")
        chatBarItem.image = NSImage(systemSymbolName: "rectangle.bottomhalf.inset.filled", accessibilityDescription: nil)
        chatBarItem.target = self
        menu.addItem(chatBarItem)

        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // Clear menu so left-click works next time
    }
    
    @objc private func openMainWindow() {
        coordinator.openMainWindow()
    }
    
    @objc private func toggleChatBar() {
        coordinator.toggleChatBar()
    }

    @objc private func toggleMenuBarPopover() {
        guard let button = statusItem?.button else { return }
        coordinator.toggleMenuBarPopover(below: button)
    }
    
    @objc private func openSettings() {
        // Essential: Activate the app first, otherwise menu actions or key events may be ignored
        // or blocked if the app is in the background.
        NSApp.activate(ignoringOtherApps: true)
        
        // Approach 1: Programmatically invoke the standard "Settings..." menu item from the App Menu
        // This is robust because it uses the exact same action standard macOS menu items use.
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            for item in appMenu.items {
                // Check for key equivalent "," which is standard for Settings
                if item.keyEquivalent == "," {
                    if let action = item.action {
                        NSApp.sendAction(action, to: item.target, from: item)
                        return
                    }
                }
            }
        }
        
        // Approach 2: Standard macOS settings selector fallback
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        
        // Approach 3: Simulate Cmd+, keyboard shortcut fallback
        // This is a last resort but effective if the app is active
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: NSPoint.zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43 // Virtual key code for comma
        )
        
        if let event = event {
            NSApp.postEvent(event, atStart: true)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
