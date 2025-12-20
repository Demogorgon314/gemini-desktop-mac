//
//  UserDefaultsKeys.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import Foundation

enum UserDefaultsKeys: String {
    case panelWidth
    case panelHeight
    case pageZoom
    case hideWindowAtLaunch
    case hideDockIcon
    case resetChatBarPosition
    case leftClickAction  // "menuBarPopover", "chatBar", or "mainWindow"
    case closeWindowOnClickOutside  // Close floating windows when clicking outside
}
