import Foundation
import CoreGraphics

/// A window as the AI sees it. `ref` ("w1") is the only identifier sent; the ref → live window table stays local.
public struct PlanWindow: Equatable {
    public var ref: String
    public var appName: String
    public var bundleID: String
    public var title: String
    public var stageName: String
    public var display: Int
    public var frame: CGRect
    public init(ref: String, appName: String, bundleID: String, title: String, stageName: String, display: Int, frame: CGRect) {
        self.ref = ref; self.appName = appName; self.bundleID = bundleID; self.title = title
        self.stageName = stageName; self.display = display; self.frame = frame
    }
}

public struct PlanContext {
    public var windows: [PlanWindow]
    public var stageNames: [String]
    /// Index 0 is display 1.
    public var displays: [CGSize]
    public init(windows: [PlanWindow], stageNames: [String], displays: [CGSize]) {
        self.windows = windows; self.stageNames = stageNames; self.displays = displays
    }
}

/// A checked action. Stage names are canonical (matching existing or earlier-created casing).
public enum PlanAction: Equatable {
    case createStage(name: String)
    case renameStage(from: String, to: String)
    case assign(window: String, stage: String)
    case snap(window: String, zone: SnapZone, display: Int?)
}

public struct DroppedAction: Equatable {
    public var description: String
    public var reason: String
}

public struct ValidatedPlan: Equatable {
    public var summary: String
    public var valid: [PlanAction]
    public var dropped: [DroppedAction]
}

public enum AIPlanError: LocalizedError, Equatable {
    case noJSON, invalidShape
    public var errorDescription: String? {
        switch self {
        case .noJSON: "The model did not return a plan."
        case .invalidShape: "The model returned a plan Tatami could not read."
        }
    }
}

/// The model's raw, untrusted reply. Every field is optional so one bad action cannot sink the whole plan.
public struct AIPlan: Decodable {
    public static let maxActions = 200
    /// The summary is model-written text shown as-is; keep it short so it cannot dominate the preview.
    public static let maxSummaryLength = 300

    public struct RawAction: Decodable {
        public var type: String?
        public var name: String?
        public var from: String?
        public var to: String?
        public var window: String?
        public var stage: String?
        public var zone: String?
        public var display: Int?

        private enum CodingKeys: String, CodingKey { case type, name, from, to, window, stage, zone, display }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Each field is read on its own. A wrong type loses that field, so validation drops the action with a reason,
            // instead of one mistyped value rejecting the whole plan. Numbers sent as text ("2") are accepted.
            type = try? c.decodeIfPresent(String.self, forKey: .type)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            from = try? c.decodeIfPresent(String.self, forKey: .from)
            to = try? c.decodeIfPresent(String.self, forKey: .to)
            window = try? c.decodeIfPresent(String.self, forKey: .window)
            stage = try? c.decodeIfPresent(String.self, forKey: .stage)
            zone = try? c.decodeIfPresent(String.self, forKey: .zone)
            display = (try? c.decodeIfPresent(Int.self, forKey: .display)) ?? (try? c.decodeIfPresent(String.self, forKey: .display)).flatMap { Int($0) }
        }

        var label: String {
            [type ?? "unknown", window, stage, name, from.map { "\($0) → \(to ?? "?")" }, zone, display.map { "display \($0)" }]
                .compactMap { $0 }.joined(separator: " ")
        }
    }

    public var summary: String
    public var actions: [RawAction]

    private enum CodingKeys: String, CodingKey { case summary, actions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        // An element that is not an object at all ("x", null) is skipped, not the whole plan.
        actions = try c.decode([Lossy<RawAction>].self, forKey: .actions).compactMap(\.value)
    }

    /// Twice the longest reply the token limit allows; anything longer is cut before scanning.
    static let maxReplyCharacters = 64_000

    /// Tolerates prose and code fences around the JSON, as local models often add them.
    public static func parse(_ text: String) throws -> AIPlan {
        let objects = balancedObjects(in: String(text.prefix(maxReplyCharacters)))
        guard !objects.isEmpty else { throw AIPlanError.noJSON }
        for object in objects {
            if let plan = try? JSONDecoder().decode(AIPlan.self, from: Data(object.utf8)) { return plan }
        }
        throw AIPlanError.invalidShape
    }

    // ponytail: rescans from each unmatched '{', O(n²) worst case; replies are a few KB, input is capped at
    // maxReplyCharacters and parsed off the main actor. A single-pass stack scanner if that ever shows up in a profile.
    /// Top-level `{...}` spans, respecting braces inside JSON strings.
    static func balancedObjects(in text: String) -> [String] {
        let chars = Array(text)
        var results: [String] = []
        var start = 0
        while let open = chars[start...].firstIndex(of: "{") {
            var depth = 0, inString = false, escaped = false, end: Int?
            for i in open..<chars.count {
                let c = chars[i]
                if inString {
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                } else if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" { depth -= 1; if depth == 0 { end = i; break } }
            }
            guard let end else { start = open + 1; continue }
            results.append(String(chars[open...end]))
            start = end + 1
        }
        return results
    }

    public func validate(against context: PlanContext) -> ValidatedPlan {
        var stages = context.stageNames
        var missing: Set<String> = []  // lowercased names whose create/rename was dropped, for cascade reasons
        let refs = Set(context.windows.map(\.ref))
        var valid: [PlanAction] = [], dropped: [DroppedAction] = []

        func canonical(_ name: String?) -> String? {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            return stages.first { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        /// `renaming` is the Stage being renamed, so a case-only rename is not a duplicate of itself.
        func newNameProblem(_ name: String?, renaming: String? = nil) -> String? {
            let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty || name.count > 60 { return "Room names must be 1 to 60 characters." }
            if let existing = canonical(name), existing != renaming { return "A Room named \(name) already exists." }
            return nil
        }
        func stageProblem(_ name: String?) -> String {
            let key = name?.lowercased() ?? ""
            return missing.contains(key) ? "Room \(name ?? "") was not created because an earlier action was dropped." : "There is no Room named \(name ?? "(none)")."
        }

        for (index, raw) in actions.enumerated() {
            guard index < Self.maxActions else { dropped.append(.init(description: raw.label, reason: "Plans are limited to \(Self.maxActions) actions.")); continue }
            var problem: String?
            switch raw.type {
            case "createStage":
                let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if let p = newNameProblem(name) { problem = p }
                else if stages.count >= 9 { problem = "Tatami supports up to nine Rooms." }
                else { stages.append(name); valid.append(.createStage(name: name)) }
                if problem != nil { missing.insert(name.lowercased()) }
            case "renameStage":
                let to = raw.to?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if let from = canonical(raw.from) {
                    if let p = newNameProblem(to, renaming: from) { problem = p }
                    else { stages[stages.firstIndex(of: from)!] = to; valid.append(.renameStage(from: from, to: to)) }
                } else { problem = stageProblem(raw.from) }
                if problem != nil { missing.insert(to.lowercased()) }
            case "assign":
                if let window = raw.window, refs.contains(window) {
                    if let stage = canonical(raw.stage) { valid.append(.assign(window: window, stage: stage)) }
                    else { problem = stageProblem(raw.stage) }
                } else { problem = "Unknown window \(raw.window ?? "(none)")." }
            case "snap":
                if let window = raw.window, refs.contains(window) {
                    if let zone = raw.zone.flatMap(SnapZone.init(rawValue:)) {
                        if let display = raw.display, !(1...max(1, context.displays.count)).contains(display) {
                            problem = "There is no display \(display)."
                        } else { valid.append(.snap(window: window, zone: zone, display: raw.display)) }
                    } else { problem = "Unknown zone \(raw.zone ?? "(none)")." }
                } else { problem = "Unknown window \(raw.window ?? "(none)")." }
            default:
                problem = "Tatami cannot perform \(raw.type ?? "unnamed") actions."
            }
            if let problem { dropped.append(.init(description: raw.label, reason: problem)) }
        }
        return ValidatedPlan(summary: String(summary.prefix(Self.maxSummaryLength)), valid: valid, dropped: dropped)
    }
}

public enum AIPrompt {
    public static let system = """
    You arrange macOS windows for Tatami, a workspace manager. A Stage is a named group of windows; only the active Stage's windows are visible.
    Reply with one JSON object and nothing else:
    {"summary": "<one sentence>", "actions": [ ... ]}
    Allowed actions:
    {"type":"createStage","name":"<1-60 chars>"}   (at most 9 Stages in total)
    {"type":"renameStage","from":"<existing>","to":"<new>"}
    {"type":"assign","window":"<ref>","stage":"<Stage name>"}
    {"type":"snap","window":"<ref>","zone":"<zone>","display":<optional 1-based display number>}
    Zones: \(SnapZone.allCases.map(\.rawValue).joined(separator: ", ")).
    Use only window refs and Stage names given by the user (or Stages you create earlier in the same plan). Never delete Stages, close apps, or invent windows. If the request cannot be done, return an empty actions list and explain in summary.
    """

    public static func user(request: String, context: PlanContext, includeTitles: Bool, previousSummary: String?) -> String {
        let displays = context.displays.enumerated().map { "\($0.offset + 1): \(Int($0.element.width))x\(Int($0.element.height))" }
        // A title is the window's own text: a newline or quote in it must not start a section of the prompt.
        func clean(_ text: String) -> String { String(String(text.map { $0.isNewline || $0 == "\"" ? " " : $0 }).prefix(120)) }
        let windows = context.windows.map { w in
            let f = w.frame
            let title = includeTitles ? " \"\(clean(w.title))\"" : ""
            return "\(w.ref) \(clean(w.appName)) (\(w.bundleID))\(title) stage=\(w.stageName) display=\(w.display) frame=\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))"
        }
        var parts = [
            "Stages: \(context.stageNames.joined(separator: ", "))",
            "Displays: \(displays.joined(separator: "; "))",
            "Windows:\n" + windows.joined(separator: "\n"),
        ]
        if let previousSummary { parts.append("Your previous plan was: \(previousSummary). Revise it according to the request.") }
        parts.append("Request: \(request)")
        return parts.joined(separator: "\n\n")
    }
}
