import AppKit
import SwiftUI
import TatamiCore

@MainActor final class BarState: ObservableObject {
    @Published var selected = 0
    @Published var keyboard = false
    @Published var renaming: UUID?
    @Published var renameText = ""
    /// Card frames in the bar's own (flipped) coordinates, for hit-testing a window being dragged over them.
    var cardFrames: [UUID: CGRect] = [:]
    /// Card highlighted while a window is dragged over the bar.
    @Published var dropTarget: UUID?
    static let newStageTarget = UUID()
}

private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
}

private extension View {
    func reportsFrame(_ id: UUID) -> some View {
        background(GeometryReader { Color.clear.preference(key: CardFramesKey.self, value: [id: $0.frame(in: .global)]) })
    }
}

/// Borderless panels cannot take key focus unless asked; the bar only wants it when opened from the keyboard.
final class BarPanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}

/// The Stage cards (M2 decisions 2, 3, 12): opened from the top-centre hot zone without taking focus,
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
    /// A window being dragged by its title bar (M2 decision 11): which one, and where it started.
    private var drag: (window: UUID, origin: CGRect)?
    private var dragStart: NSPoint?
    private static let dragThreshold: CGFloat = 6
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
        let moved: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDragged { self?.pointerDragged() }
                self?.pointerMoved()
            }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dragStart = NSEvent.mouseLocation; self?.drag = nil }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerReleased() }
        }) { monitors.append(m) }
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
        if drag != nil { return }  // a window drag owns the bar until release
        if isOpen {
            // Renaming holds a hover-opened bar open; auto-close resumes once the rename ends.
            guard openedByHover, bar.renaming == nil else { leaveWork?.cancel(); leaveWork = nil; return }
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

    // MARK: window drag onto a card

    private func pointerDragged() {
        let point = NSEvent.mouseLocation
        if drag != nil {
            bar.dropTarget = target(at: point)
            return
        }
        guard model.managing, let start = dragStart, hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold,
              inTopEdge(point), let id = model.service.focusedID(),
              let window = model.service.windows.first(where: { $0.id == id }) else { return }
        // Only a real window move counts; dragging to select text also reaches the top edge.
        guard let live = model.service.liveFrame(id), hypot(live.minX - window.frame.minX, live.minY - window.frame.minY) > Self.dragThreshold else { return }
        drag = (id, window.frame)
        open(keyboard: false)
        openedByHover = false
    }

    private func pointerReleased() {
        defer { dragStart = nil; drag = nil; bar.dropTarget = nil }
        guard let drag, isOpen else { return }
        let target = target(at: NSEvent.mouseLocation)
        close()
        // Always put the window back where the drag began: released on no card, it would otherwise stay
        // at the top edge with its title bar under the menu bar.
        model.service.move(drag.window, to: drag.origin)
        guard let target else { return }
        if target == BarState.newStageTarget { model.sendToNewStage(drag.window) } else { model.send(drag.window, to: target) }
    }

    private func target(at screenPoint: NSPoint) -> UUID? {
        let local = NSPoint(x: screenPoint.x - panel.frame.minX, y: panel.frame.maxY - screenPoint.y)  // flipped, as SwiftUI reports
        return bar.cardFrames.first { $0.value.contains(local) }?.key
    }

    /// Any point along the top edge counts while dragging; the hot zone's centre-third rule is for hovering.
    private func inTopEdge(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return false }
        return point.y >= screen.visibleFrame.maxY - Self.edgeTolerance
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
                          active: stage.id == model.state.activeStageID,
                          selected: bar.dropTarget == stage.id || (bar.keyboard && bar.selected == index),
                          canClose: model.state.stages.count > 1, bar: bar,
                          onSwitch: { model.switchStage(stage.id); close() },
                          onClose: { model.deleteStage(stage.id) },
                          onBeginRename: { bar.renameText = stage.name; bar.renaming = stage.id; requestKey() },
                          onRename: { model.renameStage(stage.id, name: $0); bar.renaming = nil })
                .reportsFrame(stage.id)
                .draggable(stage.id.uuidString)
                .dropDestination(for: String.self) { items, _ in drop(items, on: stage.id) }
            }
            if model.state.stages.count < 9 {
                newStageCard.reportsFrame(BarState.newStageTarget)
                    .dropDestination(for: String.self) { items, _ in drop(items, on: BarState.newStageTarget) }
            }
        }
        .onPreferenceChange(CardFramesKey.self) { bar.cardFrames = $0 }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
        .fixedSize()
    }

    /// Drops from SwiftUI drags: another card (reorder) or a window row from the dashboard (send).
    private func drop(_ items: [String], on target: UUID) -> Bool {
        guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
        if model.state.stages.contains(where: { $0.id == id }) {
            guard target != BarState.newStageTarget else { return false }
            model.moveStage(id, before: target); return true
        }
        guard model.windows.contains(where: { $0.id == id }) else { return false }
        if target == BarState.newStageTarget { model.sendToNewStage(id) } else { model.send(id, to: target) }
        return true
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
                Text("New Room").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(10)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: bar.dropTarget == BarState.newStageTarget ? 2 : 0))
        }.buttonStyle(.plain).help("New Room")
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
                    TextField("Room name", text: $bar.renameText).textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
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
                    .buttonStyle(.plain).padding(5).help("Close Room (Undo available)")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSwitch)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Room \(index + 1), \(stage.name), \(windows.count) windows\(active ? ", active" : "")")
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
