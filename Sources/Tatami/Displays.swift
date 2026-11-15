import AppKit
import SwiftUI
import TatamiCore

struct ReconnectOffer {
    let displayName: String
    let displayKey: String
    let count: Int
}

/// Display disconnect and reconnect (M1 decisions 8 and 14).
extension AppModel {
    /// The displays present at launch count as known, so one that is unplugged later is noticed.
    func primeDisplayPresence() {
        _ = displayPresence.update(current: Set(service.displays.map(\.id)), now: ProcessInfo.processInfo.systemUptime)
        for display in service.displays { lastKnownDisplays[display.id] = display }
    }

    func displaysChanged() {
        // Read before writing: the checkpoint on disk predates the change, while live frames may already
        // have been moved by macOS when the display vanished.
        let checkpoint = (try? Data(contentsOf: checkpointURL)).flatMap { try? JSONDecoder().decode(Checkpoint.self, from: $0) }
        service.updateDisplays()
        let after = service.displays
        // A display that vanishes for a few seconds (waking from sleep) is not an unplug: nothing is moved or merged until
        // it has been missing for the whole grace period. Windows macOS moved meanwhile are put back by the layouts.
        let now = ProcessInfo.processInfo.systemUptime
        let wasMissing = displayPresence.pendingMissing
        let change = displayPresence.update(current: Set(after.map(\.id)), now: now)
        // A display that came back inside the grace was never gone, but macOS moved its windows meanwhile: lay them out again.
        if managing, !wasMissing.isDisjoint(with: Set(after.map(\.id))) { applyLayouts() }
        let gone = change.gone.compactMap { lastKnownDisplays[$0] }
        for display in after { lastKnownDisplays[display.id] = display }
        for key in change.gone { lastKnownDisplays[key] = nil }
        let returned = after.filter { change.returned.contains($0.id) }
        displayRecheck?.cancel()
        if let wait = displayPresence.nextCheck(now: now) {
            service.holdDisplaySettling(for: wait + 4)  // windows macOS moved are not the user's doing
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.displaysChanged() } }
            displayRecheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.5, execute: work)
        }

        if managing, !gone.isEmpty, let target = displayUnderPointer() ?? after.first {
            relocate(from: gone, to: target, checkpoint: checkpoint)
            detachLayouts(of: gone, into: target)
        }
        for display in returned {
            // Tiles windows are also in `displaced`; count each window once.
            let count = max(displaced.values.filter { $0.display == display.id }.count,
                            detachedLayouts.filter { $0.key.display == display.id }.values.reduce(0) { $0 + $1.windows.count })
            // With a saved layout for this set of displays and the restore policy, the layout is applied by itself: no question.
            let restoresByItself = managing && state.displayChangePolicy == .restore && displaySetups.setup(for: after.map(\.id)) != nil
            if count > 0 && !restoresByItself { onReconnectOffer?(ReconnectOffer(displayName: display.name, displayKey: display.id, count: count)) }
        }
        if !change.gone.isEmpty || !change.returned.isEmpty { scheduleSetupReconcile() }
        writeCheckpoint()
        refresh()
    }

    /// Proportional placement keeps a left-half window on the left half of the new display.
    private func relocate(from gone: [DisplayInfo], to target: DisplayInfo, checkpoint: Checkpoint?) {
        let goneByKey = Dictionary(gone.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var moved = 0
        for window in service.windows {
            let original: (key: String, frame: CGRect)?
            if let saved = checkpoint?.windows.first(where: { $0.pid == window.pid && $0.windowNumber != nil && $0.windowNumber == window.windowNumber }),
               let key = saved.displayKey, goneByKey[key] != nil {
                original = (key, saved.frame.cgRect)
            } else if let display = gone.first(where: { $0.fullFrame.intersects(window.realFrame) }) {
                original = (display.id, window.realFrame)
            } else { original = nil }
            guard let original, let source = goneByKey[original.key] else { continue }
            displaced[window.id] = (original.key, original.frame)
            if service.place(window.id, at: DisplayRemap.remap(original.frame, from: source.area, to: target.area)) { moved += 1 }
        }
        if moved > 0 { notice = "\(moved) window(s) moved from the disconnected display to \(target.name)." }
    }

    /// A Tiles display went away: its windows become tabs in the focused pane on `target` when that display
    /// is also Tiles (otherwise they stay free-floating there), and its layout waits for Restore.
    private func detachLayouts(of gone: [DisplayInfo], into target: DisplayInfo) {
        let goneKeys = Set(gone.map(\.id))
        for (key, layout) in layouts where goneKeys.contains(key.display) {
            detachedLayouts[key] = layout
            layouts[key] = nil
            let destination = LayoutKey(stage: key.stage, display: target.id)
            guard var receiving = layouts[destination] else { continue }
            for window in layout.windows {
                receiving.add(window, to: receiving.focused)
                freeformFrames[window] = nil  // its saved frame belonged to the display that is gone
            }
            layouts[destination] = receiving
        }
        applyLayouts()
    }

    func resolveReconnect(_ offer: ReconnectOffer, restore: Bool) {
        let detached = detachedLayouts.filter { $0.key.display == offer.displayKey }
        for key in detached.keys { detachedLayouts[key] = nil }
        if restore {
            for (key, layout) in detached {
                for window in layout.windows { for other in Array(layouts.keys) { layouts[other]?.remove(window, keepEmptyPanes: state.keepEmptyPanes) } }
                layouts[key] = layout
            }
            syncLayouts()
            applyLayouts()
        }
        let entries = displaced.filter { $0.value.display == offer.displayKey }
        for (id, entry) in entries {
            displaced[id] = nil
            if restore { service.place(id, at: entry.frame) }
        }
        if restore { notice = "Restored \(entries.count) window(s) to \(offer.displayName)." }
        publish()
    }

    func displayUnderPointer() -> DisplayInfo? {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)  // AppKit → AX coordinates
        return service.displays.first { $0.fullFrame.contains(point) }
    }
}

struct ReconnectView: View {
    let offer: ReconnectOffer
    let resolve: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(offer.displayName) is back", systemImage: "display").font(.system(size: 13, weight: .semibold))
            Text("\(offer.count) window(s) were moved off this display when it disconnected. Put them back where they were?")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Keep Current Layout") { resolve(false) }
                Button("Restore") { resolve(true) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(18).frame(width: 380).foregroundStyle(Theme.ink).tint(Theme.accent)
    }
}
