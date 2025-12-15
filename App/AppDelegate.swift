//
//  AppDelegate.swift
//  GeminiDesktop
//

import AppKit
    
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var menuBarController: MenuBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Use singleton coordinator
        let coordinator = AppCoordinator.shared
        menuBarController = MenuBarController(coordinator: coordinator)
        
        // Apply launch settings
        applyLaunchSettings()
    }
    
    private func applyLaunchSettings() {
        let hideWindowAtLaunch = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hideWindowAtLaunch.rawValue)
        let hideDockIcon = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hideDockIcon.rawValue)
        
        if hideDockIcon || hideWindowAtLaunch {
            NSApp.setActivationPolicy(.accessory)
            if hideWindowAtLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    for window in NSApp.windows {
                        if window.identifier?.rawValue == "main" || window.title == "Gemini Desktop" {
                            window.orderOut(nil)
                        }
                    }
                }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Always open main window when dock icon is clicked
        // This handles the case where only the chat bar panel is visible
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't auto-terminate when last window closes - app should run in menu bar
        return false
    }
}
