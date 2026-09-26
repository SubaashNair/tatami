// Integration-test helper: prints each window of an app as "visible" or "parked" with its frame.
// Usage: ax_probe <app name> | ax_probe scroll <lines>   (posts a Control+Option scroll)
import AppKit
import ApplicationServices

if CommandLine.arguments.dropFirst().first == "scroll" {
    let lines = Int32(CommandLine.arguments.dropFirst(2).first ?? "-3") ?? -3
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
    event.flags = [.maskControl, .maskAlternate]
    event.post(tap: .cghidEventTap)
    exit(0)
}

let name = CommandLine.arguments.dropFirst().first ?? "TextEdit"
guard AXIsProcessTrusted() else { print("ERROR not trusted"); exit(2) }
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else { print("ERROR \(name) not running"); exit(3) }
let primaryHeight = NSScreen.screens[0].frame.height
let screens = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
var value: CFTypeRef?
AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &value)
for window in (value as? [AXUIElement]) ?? [] {
    var p: CFTypeRef?, s: CFTypeRef?, t: CFTypeRef?, m: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p)
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s)
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &t)
    AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &m)
    var origin = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &origin); AXValueGetValue(s as! AXValue, .cgSize, &size)
    let frame = CGRect(origin: origin, size: size)
    let visible = screens.reduce(0.0) { acc, screen in let r = screen.intersection(frame); return acc + (r.isNull ? 0 : r.width * r.height) }
    let state = (m as? Bool) == true ? "minimized" : visible < frame.width * frame.height * 0.02 ? "parked" : "visible"
    print("\(state)\t\(t as? String ?? "?")\t\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
}
