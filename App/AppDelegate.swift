//
//  AppDelegate.swift
//  GeminiDesktop
//

import AppKit
    
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
        return true
    }
}
