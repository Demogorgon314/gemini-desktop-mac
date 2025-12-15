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
    private var openWindowAction: ((String) -> Void)?
    
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        setupStatusItem()
    }
    
    func setOpenWindowAction(_ action: @escaping (String) -> Void) {
        self.openWindowAction = action
        coordinator.openWindowAction = action
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
        let leftClickAction = UserDefaults.standard.string(forKey: UserDefaultsKeys.leftClickAction.rawValue) ?? "chatBar"
        
        if leftClickAction == "mainWindow" {
            coordinator.openMainWindow()
        } else {
            coordinator.showChatBar()
        }
    }
    
    private func showMenu() {
        let menu = NSMenu()
        
        let openItem = NSMenuItem(title: "Open Gemini Desktop", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        openItem.target = self
        menu.addItem(openItem)
        
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
    
    @objc private func openSettings() {
        if let action = openWindowAction {
            action("settings")
        }
        // Fallback: try to open settings via NSApp
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
