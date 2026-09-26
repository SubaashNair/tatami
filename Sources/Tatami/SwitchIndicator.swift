import AppKit
import SwiftUI
import TatamiCore

/// Click-through pill naming the Stage after a switch (M2 decision 9). Instant switching has no animation,
/// so without it a keyboard switch gives no sign of which Stage you landed on.
@MainActor final class SwitchIndicator {
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    private static let visibleFor: TimeInterval = 1.5
    private static let offsetFromTop: CGFloat = 140  // below the Stages Bar area

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    }

    func show(index: Int, stage: Stage) {
        let host = NSHostingView(rootView: IndicatorPill(number: index + 1, name: stage.name, symbol: stage.symbol))
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.maxY - Self.offsetFromTop))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self?.panel.animator().alphaValue = 0
            } completionHandler: { self?.panel.orderOut(nil) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }
}

private struct IndicatorPill: View {
    let number: Int
    let name: String
    let symbol: String
    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 24, height: 24).background(.white.opacity(0.18), in: Circle())
            Image(systemName: symbol).font(.system(size: 13))
            Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.black.opacity(0.72), in: Capsule())
        .padding(4)
    }
}
