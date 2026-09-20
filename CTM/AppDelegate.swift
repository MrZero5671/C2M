import Cocoa
import ApplicationServices
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var rightClickMenu: NSMenu!
    var eventTap: CFMachPort?
    var permissionCheckTimer: Timer?

    private let minimizeFeatureKey = "isMinimizeFeatureEnabled"
    private let languageKey = "appLanguage"

    var isMinimizeFeatureEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: minimizeFeatureKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: minimizeFeatureKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: minimizeFeatureKey) }
    }

    // MARK: - Language

    enum AppLanguage: String {
        case english = "en"
        case vietnamese = "vi"
    }

    var currentLanguage: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: languageKey), let lang = AppLanguage(rawValue: raw) {
                return lang
            }
            return .english
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: languageKey) }
    }

    struct Strings {
        let minimizeToggle: String
        let launchAtLogin: String
        let language: String
        let english: String
        let vietnamese: String
        let quit: String
    }

    var strings: Strings {
        switch currentLanguage {
        case .vietnamese:
            return Strings(
                minimizeToggle: "Bật minimize khi click icon Dock",
                launchAtLogin: "Khởi động cùng macOS",
                language: "Ngôn ngữ",
                english: "Tiếng Anh",
                vietnamese: "Tiếng Việt",
                quit: "Thoát"
            )
        case .english:
            return Strings(
                minimizeToggle: "Minimize on Dock icon click",
                launchAtLogin: "Launch at login",
                language: "Language",
                english: "English",
                vietnamese: "Vietnamese",
                quit: "Quit"
            )
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermission()
        setupStatusItem()
        setupMenu()
        startEventTap()
        startPermissionMonitoring()
    }

    // MARK: - Event Tap

    func startEventTap() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)
                       | (1 << CGEventType.tapDisabledByTimeout.rawValue)
                       | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                return appDelegate.handleTappedEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func startPermissionMonitoring() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let trusted = AXIsProcessTrusted()

            if trusted {
                if let tap = self.eventTap {
                    if !CGEvent.tapIsEnabled(tap: tap) {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                } else {
                    self.startEventTap()
                }
            } else {
                if let tap = self.eventTap, CGEvent.tapIsEnabled(tap: tap) {
                    CGEvent.tapEnable(tap: tap, enable: false)
                }
            }
        }
    }

    func handleTappedEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap, AXIsProcessTrusted() {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard isMinimizeFeatureEnabled else {
            return Unmanaged.passRetained(event)
        }

        guard AXIsProcessTrusted() else {
            return Unmanaged.passRetained(event)
        }

        guard let clickedAppInfo = dockIconUnderCursor() else {
            return Unmanaged.passRetained(event)
        }

        guard clickedAppInfo.pid != Int32(ProcessInfo.processInfo.processIdentifier) else {
            return Unmanaged.passRetained(event)
        }

        let appElement = AXUIElementCreateApplication(clickedAppInfo.pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let allWindows = windowsRef as? [AXUIElement], !allWindows.isEmpty else {
            return Unmanaged.passRetained(event)
        }

        let realWindows = allWindows.filter { window in
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
            let subrole = (subroleRef as? String) ?? ""
            return subrole == "AXStandardWindow"
        }

        guard !realWindows.isEmpty else {
            return Unmanaged.passRetained(event)
        }

        var minimizedWindow: AXUIElement?
        var hasVisibleWindow = false

        for window in realWindows {
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            let isMin = (minimizedRef as? Bool) ?? false

            if isMin {
                minimizedWindow = window
            } else {
                hasVisibleWindow = true
            }
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return Unmanaged.passRetained(event)
        }
        let isTargetAppActive = (frontApp.processIdentifier == clickedAppInfo.pid)

        if let minimizedWindow = minimizedWindow, !hasVisibleWindow {
            AXUIElementSetAttributeValue(minimizedWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            NSRunningApplication(processIdentifier: clickedAppInfo.pid)?.activate(options: [.activateAllWindows])
            return nil
        } else if hasVisibleWindow && isTargetAppActive {
            if let visibleWindow = realWindows.first(where: { window in
                var minimizedRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
                return !((minimizedRef as? Bool) ?? false)
            }) {
                AXUIElementSetAttributeValue(visibleWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Menu bar icon

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "arrow.down.right.and.arrow.up.left",
                accessibilityDescription: "Click2Minimize"
            )
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func setupMenu() {
        let s = strings
        rightClickMenu = NSMenu()

        let toggleItem = NSMenuItem(
            title: s.minimizeToggle,
            action: #selector(toggleMinimizeFeature),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = isMinimizeFeatureEnabled ? .on : .off
        rightClickMenu.addItem(toggleItem)

        let launchAtLoginItem = NSMenuItem(
            title: s.launchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        rightClickMenu.addItem(launchAtLoginItem)

        rightClickMenu.addItem(NSMenuItem.separator())

        // Submenu Language
        let languageItem = NSMenuItem(title: s.language, action: nil, keyEquivalent: "")
        let languageSubmenu = NSMenu()

        let englishItem = NSMenuItem(
            title: s.english,
            action: #selector(selectEnglish),
            keyEquivalent: ""
        )
        englishItem.target = self
        englishItem.state = (currentLanguage == .english) ? .on : .off
        languageSubmenu.addItem(englishItem)

        let vietnameseItem = NSMenuItem(
            title: s.vietnamese,
            action: #selector(selectVietnamese),
            keyEquivalent: ""
        )
        vietnameseItem.target = self
        vietnameseItem.state = (currentLanguage == .vietnamese) ? .on : .off
        languageSubmenu.addItem(vietnameseItem)

        languageItem.submenu = languageSubmenu
        rightClickMenu.addItem(languageItem)

        rightClickMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: s.quit,
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        rightClickMenu.addItem(quitItem)
    }

    @objc func handleStatusItemClick() {
        statusItem?.menu = rightClickMenu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.statusItem?.menu = nil
        }
    }

    @objc func toggleMinimizeFeature(_ sender: NSMenuItem) {
        isMinimizeFeatureEnabled.toggle()
        sender.state = isMinimizeFeatureEnabled ? .on : .off
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = !isLaunchAtLoginEnabled()
        setLaunchAtLogin(enabled: newState)
        sender.state = newState ? .on : .off
    }

    @objc func selectEnglish() {
        currentLanguage = .english
        setupMenu()
    }

    @objc func selectVietnamese() {
        currentLanguage = .vietnamese
        setupMenu()
    }

    @objc func quitApp() {
        permissionCheckTimer?.invalidate()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Launch at Login

    func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Bỏ qua lỗi đăng ký launch-at-login nếu có
        }
    }

    func isLaunchAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    // MARK: - Accessibility

    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Dock icon detection

    struct DockIconInfo {
        let pid: pid_t
        let title: String
    }

    func dockIconUnderCursor() -> DockIconInfo? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)

        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef)
        guard let topChildren = childrenRef as? [AXUIElement], !topChildren.isEmpty else { return nil }

        guard let list = topChildren.first(where: { child in
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            return (roleRef as? String) == "AXList"
        }) else { return nil }

        var iconsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &iconsRef)
        guard let icons = iconsRef as? [AXUIElement] else { return nil }

        let mouseLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let flippedMouseLocation = NSPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)

        for icon in icons {
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(icon, kAXPositionAttribute as CFString, &positionRef)
            AXUIElementCopyAttributeValue(icon, kAXSizeAttribute as CFString, &sizeRef)
            guard let positionValue = positionRef, let sizeValue = sizeRef else { continue }

            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            let iconFrame = CGRect(origin: position, size: size)

            if iconFrame.contains(flippedMouseLocation) {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(icon, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? ""
                if let pid = pidForAppName(title) {
                    return DockIconInfo(pid: pid, title: title)
                }
            }
        }
        return nil
    }

    func pidForAppName(_ name: String) -> pid_t? {
        for app in NSWorkspace.shared.runningApplications {
            if app.localizedName == name && app.activationPolicy == .regular {
                return app.processIdentifier
            }
        }
        return nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
