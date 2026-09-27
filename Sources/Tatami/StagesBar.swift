import AppKit
import SwiftUI
import TatamiCore

@MainActor final class BarState: ObservableObject {
    @Published var selected = 0
    @Published var keyboard = false
    @Published var renaming: UUID?
    @Published var renameText = ""
}

/// Borderless panels cannot take key focus unless asked; the bar only wants it when opened from the keyboard.
final class BarPanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}

/// The Stages Bar (M2 decisions 2, 3, 12): opened from the top-centre hot zone without taking focus,
/// or from the shortcut with keyboard navigation.
@MainActor final class StagesBarController {
    private let model: AppModel
    private let panel = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let host: NSHostingController<StagesBarView>
    private let bar = BarState()
    private var monitors: [Any] = []
    private var dwellWork: DispatchWorkItem?
    private var leaveWork: DispatchWorkItem?
    private var openedByHover = false
    private static let leaveDelay: TimeInterval = 2
    private static let edgeTolerance: CGFloat = 2
    private static let topMargin: CGFloat = 8
    private static let hoverSlack: CGFloat = 16

    init(model: AppModel) {
        self.model = model
        let bar = self.bar
        host = NSHostingController(rootView: StagesBarView(model: model, bar: bar, close: {}, requestKey: {}))
        host.sizingOptions = .preferredContentSize
        host.rootView = StagesBarView(model: model, bar: bar, close: { [weak self] in self?.close() }, requestKey: { [weak self] in self?.takeKey() })
        panel.contentViewController = host
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        installMonitors()
    }

    var isOpen: Bool { panel.isVisible }

    /// Shortcut: repeat to dismiss (BAR-06).
    func toggle() { isOpen ? close() : open(keyboard: true) }

    func open(keyboard: Bool) {
        bar.keyboard = keyboard
        bar.renaming = nil
        bar.selected = model.state.stages.firstIndex { $0.id == model.state.activeStageID } ?? 0
        openedByHover = !keyboard
        panel.acceptsKey = keyboard
        position()
        if keyboard { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }

    func close() {
        dwellWork?.cancel(); dwellWork = nil
        leaveWork?.cancel(); leaveWork = nil
        bar.renaming = nil
        panel.orderOut(nil)
    }

    private func takeKey() {
        panel.acceptsKey = true
        openedByHover = false  // renaming: stay open until done
        panel.makeKey()
    }

    private func position() {
        host.view.layoutSubtreeIfNeeded()
        panel.setContentSize(host.view.fittingSize)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - Self.topMargin - size.height))
    }

    // MARK: input

    private func installMonitors() {
        let moved: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved() } }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moved) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { moved($0); return $0 }) { monitors.append(m) }
        // Global monitors never see clicks in our own panel, so any click they report is outside it (BAR-06).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { if self?.isOpen == true { self?.close() } }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) == true } ? nil : event
        }) { monitors.append(m) }
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        if isOpen {
            guard openedByHover else { return }
            if panel.frame.insetBy(dx: -Self.hoverSlack, dy: -Self.hoverSlack).contains(point) || inHotZone(point) {
                leaveWork?.cancel(); leaveWork = nil
            } else if leaveWork == nil {
                let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.close() } }
                leaveWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.leaveDelay, execute: work)
            }
            return
        }
        guard model.managing, model.state.barHotZone, inHotZone(point) else { dwellWork?.cancel(); dwellWork = nil; return }
        guard dwellWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dwellWork = nil
                if self.inHotZone(NSEvent.mouseLocation) && !self.isOpen { self.open(keyboard: false) }
            }
        }
        dwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + model.state.barDelay, execute: work)
    }

    /// Top-centre third of the display under the pointer, optionally excluding the notch.
    private func inHotZone(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return false }
        let frame = screen.frame
        guard point.y >= frame.maxY - Self.edgeTolerance else { return false }
        let third = frame.width / 3
        guard point.x >= frame.minX + third, point.x <= frame.minX + 2 * third else { return false }
        if model.state.barIgnoresNotch, screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let notchHalfWidth = (frame.width - left.width - right.width) / 2
            if abs(point.x - frame.midX) <= notchHalfWidth { return false }
        }
        return true
    }

    /// Keyboard mode only: ←/→ select, Return switch, 1–9 jump, Esc close.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isOpen, panel.isKeyWindow else { return false }
        if bar.renaming != nil {
            if event.keyCode == 53 { bar.renaming = nil; return true }
            return false  // the rename field handles typing and Return
        }
        let stages = model.state.stages
        switch event.keyCode {
        case 53: close()
        case 123: bar.selected = max(0, bar.selected - 1)
        case 124: bar.selected = min(stages.count - 1, bar.selected + 1)
        case 36, 76: if stages.indices.contains(bar.selected) { model.switchStage(stages[bar.selected].id); close() }
        default:
            guard let digit = event.charactersIgnoringModifiers.flatMap(Int.init), stages.indices.contains(digit - 1) else { return false }
            model.switchStage(stages[digit - 1].id); close()
        }
        return true
    }
}

// MARK: views

struct StagesBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var bar: BarState
    let close: () -> Void
    let requestKey: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(model.state.stages.enumerated()), id: \.element.id) { index, stage in
                StageCard(index: index, stage: stage, windows: windows(on: stage), displays: model.displays,
                          active: stage.id == model.state.activeStageID, selected: bar.keyboard && bar.selected == index,
                          canClose: model.state.stages.count > 1, bar: bar,
                          onSwitch: { model.switchStage(stage.id); close() },
                          onClose: { model.deleteStage(stage.id) },
                          onBeginRename: { bar.renameText = stage.name; bar.renaming = stage.id; requestKey() },
                          onRename: { model.renameStage(stage.id, name: $0); bar.renaming = nil })
            }
            if model.state.stages.count < 9 { newStageCard }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
        .fixedSize()
    }

    private func windows(on stage: Stage) -> [LiveWindow] {
        model.windows.filter { $0.stageID == stage.id && !model.state.excludedBundleIDs.contains($0.bundleID) }
    }

    private var newStageCard: some View {
        Button { model.addStage(model.state.nextStageName()); close() } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.secondary).frame(width: StageCard.previewSize.width, height: StageCard.previewSize.height)
                    .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary))
                Text("New Stage").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(10)
        }.buttonStyle(.plain).help("New Stage")
    }
}

struct StageCard: View {
    static let previewSize = CGSize(width: 176, height: 96)
    let index: Int
    let stage: Stage
    let windows: [LiveWindow]
    let displays: [DisplayInfo]
    let active: Bool
    let selected: Bool
    let canClose: Bool
    @ObservedObject var bar: BarState
    let onSwitch: () -> Void
    let onClose: () -> Void
    let onBeginRename: () -> Void
    let onRename: (String) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeskSchematic(windows: windows, displays: displays).frame(width: Self.previewSize.width, height: Self.previewSize.height)
            HStack(spacing: 6) {
                Text("\(index + 1)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                if bar.renaming == stage.id {
                    TextField("Stage name", text: $bar.renameText).textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .onSubmit { onRename(bar.renameText) }
                } else {
                    Text(stage.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .onTapGesture(perform: onBeginRename).help("Click to rename")
                }
                Spacer(minLength: 4)
                Text("\(windows.count)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : active ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            if hovering && canClose {
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).symbolRenderingMode(.hierarchical) }
                    .buttonStyle(.plain).padding(5).help("Close Stage (Undo available)")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSwitch)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stage \(index + 1), \(stage.name), \(windows.count) windows\(active ? ", active" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// Every display in its real arrangement, with each window drawn at its real (unparked) frame (M2 decisions 1 and 10).
struct DeskSchematic: View {
    let windows: [LiveWindow]
    let displays: [DisplayInfo]

    var body: some View {
        GeometryReader { geometry in
            let bounds = displays.map(\.fullFrame).reduce(CGRect.null) { $0.union($1) }
            if !bounds.isNull, bounds.width > 0, bounds.height > 0 {
                let transform = Transform(bounds: bounds, size: geometry.size)
                ZStack(alignment: .topLeading) {
                    ForEach(displays) { display in
                        let r = transform.map(display.fullFrame)
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.09))
                            .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                    }
                    ForEach(windows) { window in
                        let r = transform.map(window.realFrame.intersection(bounds))
                        if !r.isNull, r.width > 2, r.height > 2 {
                            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: .windowBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                                .help(window.title.isEmpty ? window.appName : "\(window.appName): \(window.title)")
                        }
                    }
                    // Windows often overlap exactly (maximized or tiled), so name the apps per display instead of per window.
                    ForEach(displays) { display in
                        let r = transform.map(display.fullFrame)
                        let apps = appsShown(on: display)
                        HStack(spacing: 2) {
                            ForEach(apps.icons.indices, id: \.self) { i in Image(nsImage: apps.icons[i]).resizable().scaledToFit().frame(width: 14, height: 14) }
                            if apps.more > 0 { Text("+\(apps.more)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                        }
                        .padding(2).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .offset(x: r.minX + 3, y: r.maxY - 21)
                        .opacity(apps.icons.isEmpty ? 0 : 1)
                    }
                }
            }
        }
    }

    private static let maxIcons = 4

    /// Distinct apps whose windows sit mostly on `display`, in window order.
    private func appsShown(on display: DisplayInfo) -> (icons: [NSImage], more: Int) {
        var seen = Set<String>(), icons: [NSImage] = []
        for window in windows where display.fullFrame.contains(CGPoint(x: window.realFrame.midX, y: window.realFrame.midY)) {
            guard seen.insert(window.bundleID).inserted, let icon = window.icon else { continue }
            icons.append(icon)
        }
        return (Array(icons.prefix(Self.maxIcons)), max(0, icons.count - Self.maxIcons))
    }

    private struct Transform {
        let bounds: CGRect
        let scale: CGFloat
        let inset: CGPoint
        init(bounds: CGRect, size: CGSize) {
            self.bounds = bounds
            scale = min(size.width / bounds.width, size.height / bounds.height)
            inset = CGPoint(x: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2)
        }
        func map(_ rect: CGRect) -> CGRect {
            guard !rect.isNull else { return .null }
            return CGRect(x: inset.x + (rect.minX - bounds.minX) * scale, y: inset.y + (rect.minY - bounds.minY) * scale,
                          width: rect.width * scale, height: rect.height * scale)
        }
    }
}
