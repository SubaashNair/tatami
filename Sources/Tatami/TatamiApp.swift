import AppKit
import SwiftUI

@main struct TatamiApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `kill` / `killall Tatami` should restore windows like Quit does, not behave like a crash.
        signal(SIGTERM, SIG_IGN)
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminate.setEventHandler { NSApp.terminate(nil) }
        terminate.resume()
        withExtendedLifetime((delegate, terminate)) { app.run() }
    }
}

/// Titled so it can take keyboard focus; non-activating so it floats over the desk being described.
final class OrganizerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var window: NSWindow!
    private var panel: OrganizerPanel!
    private var reconnectPanels: [NSPanel] = []
    private let indicator = SwitchIndicator()

    /// Menu-bar-only unless the user asks for a Dock icon (M2 decision 6).
    private func applyDockPreference() {
        NSApp.setActivationPolicy(model.state.showInDock ? .regular : .accessory)
    }
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tatami"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Dashboard(model: model))
        window.setFrameAutosaveName("TatamiDashboard")
        window.center()
        setupMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.split.2x2", accessibilityDescription: "Tatami")
        model.showDashboard = { [weak self] in self?.showWindow() }
        model.showStagesBar = { [weak self] in self?.showWindow() }  // M2 step 3 replaces this with the Stages Bar
        model.onStageSwitched = { [weak self] index, stage in self?.indicator.show(index: index, stage: stage) }
        model.onDockPreferenceChanged = { [weak self] in self?.applyDockPreference() }
        applyDockPreference()
        model.menuChanged = { [weak self] in self?.updateStatusMenu() }
        setupOrganizerPanel()
        model.showOrganizer = { [weak self] in self?.toggleOrganizer() }
        model.hideOrganizer = { [weak self] in self?.panel.orderOut(nil) }
        model.onReconnectOffer = { [weak self] offer in self?.showReconnect(offer) }
        model.start()
        if ProcessInfo.processInfo.environment["TATAMI_AUTOSTART"] == "1" && model.trusted { model.toggleManagement() }  // integration tests
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }

    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func toggleManagement() { model.toggleManagement() }
    @objc private func rescue() { model.rescue() }

    private func setupOrganizerPanel() {
        panel = OrganizerPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 180), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        let host = NSHostingController(rootView: AIOrganizerView(model: model).padding(22).frame(width: 580))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        panel.delegate = self
    }

    // Hides on outside click (decision 17). An unapplied plan stays in the model for next time.
    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel { panel.orderOut(nil) }
    }

    /// Non-blocking Restore / Keep Current Layout, on the display under the pointer (M1 decision 8).
    private func showReconnect(_ offer: ReconnectOffer) {
        let reconnect = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
        reconnect.titleVisibility = .hidden
        reconnect.titlebarAppearsTransparent = true
        reconnect.level = .floating
        reconnect.isReleasedWhenClosed = false
        reconnect.hidesOnDeactivate = false
        let host = NSHostingController(rootView: ReconnectView(offer: offer) { [weak self, weak reconnect] restore in
            self?.model.resolveReconnect(offer, restore: restore)
            reconnect?.orderOut(nil)
        })
        host.sizingOptions = .preferredContentSize
        reconnect.contentViewController = host
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            reconnect.setFrameTopLeftPoint(NSPoint(x: area.maxX - reconnect.frame.width - 20, y: area.maxY - 20))
        }
        reconnect.orderFrontRegardless()
        reconnectPanels.removeAll { !$0.isVisible }
        reconnectPanels.append(reconnect)
    }

    @objc private func toggleOrganizer() {
        if panel.isVisible { panel.orderOut(nil); return }
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: area.midX - panel.frame.width / 2, y: area.maxY - 80))
        }
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func selectStage(_ sender: NSMenuItem) { if let id = sender.representedObject as? UUID { model.switchStage(id) } }
    @objc private func preferences() { model.selection = "settings"; showWindow() }

    private func updateStatusMenu() {
        statusItem.button?.title = " \(model.state.activeStage.name)"
        let menu = NSMenu()
        let title = NSMenuItem(title: "Tatami · \(model.managing ? "Managing" : "Paused")", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        for (index, stage) in model.state.stages.enumerated() {
            let item = NSMenuItem(title: "\(index + 1)  \(stage.name)", action: #selector(selectStage(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = stage.id
            item.state = model.state.activeStageID == stage.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add(menu, "Open Tatami", #selector(showWindow))
        add(menu, "Arrange with AI…", #selector(toggleOrganizer))
        add(menu, model.managing ? "Pause & Restore Windows" : "Start Managing", #selector(toggleManagement))
        add(menu, "Rescue Windows", #selector(rescue))
        add(menu, "Preferences…", #selector(preferences))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Tatami & Restore Windows", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); menu.addItem(quit)
        statusItem.menu = menu
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }

    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Tatami", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let preferences = NSMenuItem(title: "Preferences…", action: #selector(self.preferences), keyEquivalent: ","); preferences.target = self; appMenu.addItem(preferences)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Tatami", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Tatami", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        for (name, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
