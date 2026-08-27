import Cocoa

/// Rebuilds the menubar menu for sniq's current state. Kept separate
/// from `StatusBarController` so that class stays focused on lifecycle
/// (icon, windows, delegates) while this file owns the menu layout.
@MainActor
enum AppMenuBuilder {

    /// Replaces `menu`'s items with the current snap-aware layout.
    /// `target` receives all `@objc` actions; `errorMessage` adds a
    /// disabled status line at the top when non-nil.
    static func rebuild(
        menu: NSMenu,
        target: StatusBarController,
        errorMessage: String?
    ) {
        menu.removeAllItems()
        appendErrorBanner(to: menu, message: errorMessage)
        appendPauseToggle(to: menu, target: target)
        menu.addItem(.separator())
        appendSnapItems(to: menu, target: target)
        menu.addItem(.separator())
        appendAppItems(to: menu, target: target)
        menu.addItem(.separator())
        appendQuit(to: menu, target: target)
    }

    // MARK: - Sections

    private static func appendErrorBanner(to menu: NSMenu, message: String?) {
        guard let message else { return }
        let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        menu.addItem(.separator())
    }

    private static func appendPauseToggle(to menu: NSMenu, target: StatusBarController) {
        let item = NSMenuItem(
            title: PauseState.isPaused ? "Resume Sniq" : "Pause Sniq",
            action: #selector(StatusBarController.togglePause(_:)),
            keyEquivalent: ""
        )
        item.target = target
        menu.addItem(item)
    }

    private static func appendSnapItems(to menu: NSMenu, target: StatusBarController) {
        let item = NSMenuItem(
            title: "Snaps…",
            action: #selector(StatusBarController.openSnaps(_:)),
            keyEquivalent: ""
        )
        item.target = target
        menu.addItem(item)
    }

    private static func appendAppItems(to menu: NSMenu, target: StatusBarController) {
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(StatusBarController.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = target
        menu.addItem(settingsItem)

        let howToItem = NSMenuItem(
            title: "How to Use...",
            action: #selector(StatusBarController.openOnboarding(_:)),
            keyEquivalent: ""
        )
        howToItem.target = target
        menu.addItem(howToItem)

        let aboutItem = NSMenuItem(
            title: "About Sniq",
            action: #selector(StatusBarController.openAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = target
        menu.addItem(aboutItem)
    }

    private static func appendQuit(to menu: NSMenu, target: StatusBarController) {
        let item = NSMenuItem(
            title: "Quit Sniq",
            action: #selector(StatusBarController.quit(_:)),
            keyEquivalent: "q"
        )
        item.target = target
        menu.addItem(item)
    }
}
