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
        }
        for display in returned {
            let count = displaced.values.filter { $0.display == display.id }.count
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

    func resolveReconnect(_ offer: ReconnectOffer, restore: Bool) {
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
