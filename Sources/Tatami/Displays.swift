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
    func displaysChanged() {
        let before = service.displays
        // Read before writing: the checkpoint on disk predates the change, while live frames may already
        // have been moved by macOS when the display vanished.
        let checkpoint = (try? Data(contentsOf: checkpointURL)).flatMap { try? JSONDecoder().decode(Checkpoint.self, from: $0) }
        service.updateDisplays()
        let after = service.displays
        let afterKeys = Set(after.map(\.id)), beforeKeys = Set(before.map(\.id))
        let gone = before.filter { !afterKeys.contains($0.id) }
        let returned = after.filter { !beforeKeys.contains($0.id) }

        if managing, !gone.isEmpty, let target = displayUnderPointer() ?? after.first {
            relocate(from: gone, to: target, checkpoint: checkpoint)
            detachLayouts(of: gone, into: target)
        }
        for display in returned {
            // TabStack windows are also in `displaced`; count each window once.
            let count = max(displaced.values.filter { $0.display == display.id }.count,
                            detachedLayouts.filter { $0.key.display == display.id }.values.reduce(0) { $0 + $1.windows.count })
            if count > 0 { onReconnectOffer?(ReconnectOffer(displayName: display.name, displayKey: display.id, count: count)) }
        }
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

    /// A TabStack display went away: its windows become tabs in the focused pane on `target` when that display
    /// is also TabStack (otherwise they stay free-floating there), and its layout waits for Restore.
    private func detachLayouts(of gone: [DisplayInfo], into target: DisplayInfo) {
        let goneKeys = Set(gone.map(\.id))
        for (key, layout) in layouts where goneKeys.contains(key.display) {
            detachedLayouts[key] = layout
            layouts[key] = nil
            let destination = LayoutKey(stage: key.stage, display: target.id)
            guard var receiving = layouts[destination] else { continue }
            for window in layout.windows { receiving.add(window, to: receiving.focused) }
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
