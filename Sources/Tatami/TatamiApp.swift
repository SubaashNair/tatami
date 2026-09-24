import AppKit
import SwiftUI

@main struct TatamiApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var window: NSWindow!
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
        model.menuChanged = { [weak self] in self?.updateStatusMenu() }
        model.start()
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }

    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func toggleManagement() { model.toggleManagement() }
    @objc private func rescue() { model.rescue() }
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
