import Cocoa
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var snapsWindow: NSWindow?

    /// When non-nil, the menu shows this as a disabled status line at
    /// the top and the status-bar icon switches to a warning glyph.
    private var errorMessage: String?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Error state

    func showError(_ message: String) {
        errorMessage = message
        updateIcon()
    }

    func clearError() {
        errorMessage = nil
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if errorMessage != nil {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Sniq Error"
            )?.withSymbolConfiguration(config)
        } else {
            button.image = MenuBarIcon.make()
        }
        button.appearsDisabled = errorMessage == nil && PauseState.isPaused
    }

    // MARK: - Actions (invoked by AppMenuBuilder via #selector)

    @objc func togglePause(_ sender: NSMenuItem) {
        PauseState.isPaused.toggle()
        updateIcon()
    }

    @objc func openSnaps(_ sender: Any?) {
        showSnapsWindow()
    }

    @objc func openSettings(_ sender: Any?) {
        if reveal(settingsWindow) { return }
        settingsWindow = presentAuxiliaryWindow(
            title: "Sniq Settings",
            size: NSSize(width: 440, height: 600),
            placement: .belowStatusItemFitted,
            rootView: SettingsView()
        )
    }

    @objc func openOnboarding(_ sender: Any?) {
        showOnboarding()
    }

    @objc func openAbout(_ sender: Any?) {
        if reveal(aboutWindow) { return }
        aboutWindow = presentAuxiliaryWindow(
            title: "About Sniq",
            size: NSSize(width: 320, height: 340),
            rootView: AboutView()
        )
    }

    func showOnboarding() {
        if reveal(onboardingWindow) { return }
        onboardingWindow = presentAuxiliaryWindow(
            title: "How to Use Sniq",
            size: NSSize(width: 380, height: 500),
            rootView: OnboardingView()
        )
    }

    private func showSnapsWindow() {
        if reveal(snapsWindow) { return }
        snapsWindow = presentAuxiliaryWindow(
            title: "Snaps",
            size: NSSize(width: 480, height: 860),
            styleMask: [.titled, .closable, .resizable],
            rootView: SnapsWindowView()
        )
    }

    // MARK: - Window presentation

    private enum WindowPlacement {
        case mouseScreenCenter
        /// Sizes the window to its SwiftUI content, then pins it under
        /// the status-bar icon.
        case belowStatusItemFitted
    }

    /// Brings an already-visible auxiliary window to front. Returns true
    /// when that was enough and no new window is needed.
    private func reveal(_ window: NSWindow?) -> Bool {
        guard let window, window.isVisible else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Creates, positions, and fronts one of the app's auxiliary windows
    /// (Settings, About, Onboarding, Snaps) with the shared boilerplate:
    /// SwiftUI hosting, delegate wiring, and regular activation policy.
    private func presentAuxiliaryWindow<Content: View>(
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask = [.titled, .closable],
        placement: WindowPlacement = .mouseScreenCenter,
        rootView: Content
    ) -> NSWindow {
        let window = ShortcutWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        let hosting = NSHostingView(rootView: rootView)
        window.contentView = hosting

        switch placement {
        case .mouseScreenCenter:
            window.centerOnMouseScreen()
        case .belowStatusItemFitted:
            window.setContentSize(hosting.fittingSize)
            positionBelowStatusItem(window)
        }

        window.isReleasedWhenClosed = false
        window.delegate = self
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Window placement

    /// Places `window` just below the status-bar icon, right-aligned to
    /// it, so Settings opens next to the trigger instead of at screen
    /// center (minimizes cursor travel from the menu bar).
    private func positionBelowStatusItem(_ window: NSWindow) {
        guard let button = statusItem.button,
              let buttonWindow = button.window
        else {
            window.center()
            return
        }
        let buttonFrame = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let screenFrame = buttonWindow.screen?.visibleFrame ?? .zero
        let gap: CGFloat = 6
        let w = window.frame.width
        let h = window.frame.height
        let x = max(
            screenFrame.minX + 8,
            min(buttonFrame.maxX - w, screenFrame.maxX - w - 8)
        )
        let y = buttonFrame.minY - h - gap
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Menu delegate

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        AppMenuBuilder.rebuild(menu: menu, target: self, errorMessage: errorMessage)
    }
}

// MARK: - Window delegate

extension StatusBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window === snapsWindow {
            snapsWindow = nil
        }
        // Return to accessory policy (no Dock icon) once every auxiliary
        // window has closed.
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - Screen helpers

extension NSScreen {
    static var withMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
    }
}

extension NSWindow {
    /// Centers the window on the screen currently holding the mouse
    /// cursor so menu-bar windows surface on the display the user is
    /// actively using rather than the primary screen.
    func centerOnMouseScreen() {
        guard let screen = NSScreen.withMouse else {
            center()
            return
        }
        let visible = screen.visibleFrame
        let size = frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        setFrameOrigin(origin)
    }
}
