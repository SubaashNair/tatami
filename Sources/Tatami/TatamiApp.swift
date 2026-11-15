import AppKit
import SwiftUI
import TatamiCore

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
    private var stagesBar: StagesBarController!
    private var tabBars: TabBarController!

    /// Debug: render a tab bar holding the first few real windows to a PNG and quit.
    private func snapshotTabs(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            let key = LayoutKey(stage: model.state.activeStageID, display: model.displays.first?.id ?? "")
            var layout = PaneLayout(root: .pane(Pane()))
            for window in model.windows.prefix(4) { layout.add(window.id, to: layout.root.paneIDs[0]) }
            if let second = model.windows.dropFirst().first { layout.select(second.id); model.minSizeWindows.insert(second.id) }
            model.layouts[key] = layout
            let view = NSHostingView(rootView: TabBarView(model: model, key: key, paneID: layout.root.paneIDs[0]).frame(width: 760, height: 28).padding(12).background(Color(white: 0.55)))
            view.frame.size = view.fittingSize
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    /// Debug: render the dashboard to a PNG and quit. Use TATAMI_DATA_DIR so no real settings are read or written.
    private func snapshotDashboard(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
            guard let view = window.contentView else { return }
            window.setContentSize(NSSize(width: 1180, height: 820))
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    /// Debug: render the Stage cards to a PNG and quit. Our own view, so no Screen Recording is needed.
    private func snapshotBar(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            let bar = BarState(); bar.keyboard = true; bar.selected = 1
            let view = NSHostingView(rootView: StagesBarView(model: model, bar: bar, close: {}, requestKey: {}).padding(20).background(Color(white: 0.55)))
            view.frame.size = view.fittingSize
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

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
        window.backgroundColor = Palette.paper
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Dashboard(model: model))
        window.setFrameAutosaveName("TatamiDashboard")
        window.center()
        setupMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BrandMark.menuBarImage()
        model.showDashboard = { [weak self] in self?.showWindow() }
        stagesBar = StagesBarController(model: model)
        tabBars = TabBarController(model: model)
        model.onLayoutsApplied = { [weak self] in self?.tabBars.update() }
        model.showStagesBar = { [weak self] in self?.stagesBar.toggle() }
        if let path = ProcessInfo.processInfo.environment["TATAMI_SNAPSHOT_BAR"] { snapshotBar(to: path) }
        if let path = ProcessInfo.processInfo.environment["TATAMI_SNAPSHOT_TABS"] { snapshotTabs(to: path) }
        if let path = ProcessInfo.processInfo.environment["TATAMI_SNAPSHOT_DASHBOARD"] { snapshotDashboard(to: path) }
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
    @objc private func sortWindows() { model.prepareSort(); showWindow() }

    private func setupOrganizerPanel() {
        panel = OrganizerPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 180), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = Palette.paper
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
    @objc private func floatOrTile() { model.toggleFloating() }
    @objc private func installCommandLine() { model.installCommandLineTool() }

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
        add(menu, "Sort Windows into Rooms…", #selector(sortWindows))
        add(menu, model.managing ? "Pause & Restore Windows" : "Start Managing", #selector(toggleManagement))
        add(menu, "Float or Tile Focused Window", #selector(floatOrTile))
        add(menu, "Install Command Line Tool…", #selector(installCommandLine))
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
