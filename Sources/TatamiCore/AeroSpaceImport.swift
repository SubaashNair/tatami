import Foundation

/// One `[[on-window-detected]]` rule from an AeroSpace config.
public struct AeroRule: Equatable {
    public var appID: String?
    /// `if.app-name-regex-substring`: a case-insensitive regex matched against the app name.
    public var nameRegex: String?
    /// The target of `move-node-to-workspace`.
    public var workspace: String?
    /// `layout floating`.
    public var floating: Bool
    /// Conditions Tatami cannot express (window titles, startup, workspace), kept so the import can say what it skipped.
    public var unsupported: [String]
    /// `check-further-callbacks = true`: later rules still apply to the apps this one matched. AeroSpace stops otherwise.
    public var checkFurther: Bool

    public init(appID: String?, nameRegex: String?, workspace: String?, floating: Bool, unsupported: [String], checkFurther: Bool = false) {
        self.appID = appID; self.nameRegex = nameRegex; self.workspace = workspace; self.floating = floating; self.unsupported = unsupported
        self.checkFurther = checkFurther
    }
}

/// Reads the part of an AeroSpace `~/.aerospace.toml` that matters here. It is a small TOML subset reader, not a full parser:
/// `[[on-window-detected]]` tables with string or string-array values, comments and quotes handled.
public enum AeroSpaceConfig {
    public static func parse(_ text: String) -> [AeroRule] {
        var rules: [AeroRule] = []
        var current: AeroRule?
        func finish() { if let rule = current { rules.append(rule) }; current = nil }

        var lines = text.components(separatedBy: .newlines)[...]
        while let raw = lines.popFirst() {
            let line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && !line.contains("=") || line.hasPrefix("[[") && line.hasSuffix("]]") {
                finish()
                if line == "[[on-window-detected]]" { current = AeroRule(appID: nil, nameRegex: nil, workspace: nil, floating: false, unsupported: []) }
                continue
            }
            guard current != nil, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            // A multi-line array runs until its closing bracket, never into the next table, and never past 100 lines.
            var extra = 0
            while value.hasPrefix("["), !closesArray(value), extra < 100, let peek = lines.first {
                let trimmed = stripComment(peek).trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[[") || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && !trimmed.contains("=") && !trimmed.contains("'") && !trimmed.contains("\"")) { break }
                lines.removeFirst()
                value += " " + trimmed
                extra += 1
            }
            let strings = quotedStrings(in: value)
            switch key {
            case "if.app-id": current?.appID = strings.first
            case "if.app-name-regex-substring": current?.nameRegex = strings.first
            case "run": for command in strings { apply(command, to: &current) }
            case "check-further-callbacks": current?.checkFurther = value.lowercased() == "true"
            default: if key.hasPrefix("if.") { current?.unsupported.append(key) }
            }
        }
        finish()
        return rules
    }

    private static func apply(_ command: String, to rule: inout AeroRule?) {
        let words = command.split(separator: " ").map(String.init)
        guard let name = words.first else { return }
        if name == "move-node-to-workspace", let workspace = words.dropFirst().last(where: { !$0.hasPrefix("-") }), !["next", "prev"].contains(workspace) { rule?.workspace = workspace }
        if name == "layout", words.dropFirst().contains("floating") { rule?.floating = true }
    }

    /// Removes a `#` comment, ignoring a `#` inside quotes.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?, escaped = false
        for index in line.indices {
            let c = line[index]
            if escaped { escaped = false; continue }
            if let open = quote {
                if c == "\\" && open == "\"" { escaped = true } else if c == open { quote = nil }
            } else if c == "'" || c == "\"" { quote = c }
            else if c == "#" { return String(line[..<index]) }
        }
        return line
    }

    private static func closesArray(_ value: String) -> Bool {
        var quote: Character?, escaped = false
        for c in value {
            if escaped { escaped = false; continue }
            if let open = quote {
                if c == "\\" && open == "\"" { escaped = true } else if c == open { quote = nil }
            } else if c == "'" || c == "\"" { quote = c }
            else if c == "]" { return true }
        }
        return false
    }

    /// Every single- or double-quoted string in a value, in order.
    /// Single quotes are literal; in double quotes `\\` and `\"` are unescaped, other escapes are kept as written.
    private static func quotedStrings(in value: String) -> [String] {
        var result: [String] = [], quote: Character?, buffer = "", escaped = false
        for c in value {
            if let open = quote {
                if escaped {
                    escaped = false
                    if c != "\\" && c != "\"" { buffer.append("\\") }  // an escape we do not translate is kept as written
                    buffer.append(c)
                } else if c == "\\" && open == "\"" { escaped = true }
                else if c == open { result.append(buffer); buffer = ""; quote = nil }
                else { buffer.append(c) }
            } else if c == "'" || c == "\"" { quote = c }
        }
        return result
    }
}

/// AeroSpace's `if.app-name-regex-substring`: a regex found anywhere in the app name, ignoring case.
public enum AeroNameMatcher {
    static let maxPatternLength = 500

    /// Compiles a config pattern once. Nil for a pattern that is not valid or is longer than a sane app-name pattern.
    public static func compile(_ pattern: String) -> NSRegularExpression? {
        guard pattern.count <= maxPatternLength else { return nil }
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    public static func matches(_ regex: NSRegularExpression, name: String) -> Bool {
        regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    public static func matches(_ pattern: String, name: String) -> Bool {
        compile(pattern).map { matches($0, name: name) } ?? false
    }
}

public struct InstalledApp: Equatable, Hashable {
    public var bundleID: String
    public var name: String
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
}

/// What an import would do, before anything is changed: workspaces to become Rooms, apps for each, and what was skipped.
public struct AeroImportPlan: Equatable {
    public struct Entry: Equatable {
        public var apps: [InstalledApp]
        public var workspace: String?
        public var floating: Bool
        /// The rule in the config's own words, for messages.
        public var label: String
    }
    /// Workspace names in the order the config first uses them, at most nine (the Room limit).
    public var rooms: [String]
    public var entries: [Entry]
    public var skipped: [String]
    /// Monitor lists from `workspace-to-monitor-force-assignment`, for the workspaces that become Rooms.
    public var monitors: [String: [DisplayPreference]] = [:]
}

public enum AeroImport {
    public static func plan(_ rules: [AeroRule], installed: [InstalledApp], monitors: [String: [DisplayPreference]] = [:]) -> AeroImportPlan {
        var rooms: [String] = [], entries: [AeroImportPlan.Entry] = [], skipped: [String] = []
        /// Nil when the pattern does not compile.
        func matchedApps(_ rule: AeroRule) -> [InstalledApp]? {
            let regex = rule.nameRegex.map(AeroNameMatcher.compile)
            if case .some(.none) = regex { return nil }  // a pattern that does not compile
            if let id = rule.appID {
                guard let app = installed.first(where: { $0.bundleID == id }) else { return [InstalledApp(bundleID: id, name: id)] }
                // AeroSpace needs every condition to match, so a name pattern next to an app id narrows it further.
                if let regex = regex ?? nil, !AeroNameMatcher.matches(regex, name: app.name) { return [] }
                return [app]
            }
            guard let regex = regex ?? nil else { return [] }
            var seen = Set<String>()  // one app can be listed under several names
            return installed.filter { AeroNameMatcher.matches(regex, name: $0.name) && seen.insert($0.bundleID).inserted }
        }
        // AeroSpace runs only the first rule that matches a window, unless that rule sets check-further-callbacks.
        var settled = Set<String>()
        for rule in rules {
            let label = rule.appID.map { "app id \($0)" } ?? rule.nameRegex.map { "app names \($0)" } ?? "a rule with no app"
            if !rule.unsupported.isEmpty { skipped.append("Skipped \(label): it also uses \(rule.unsupported.joined(separator: ", ")), which Tatami cannot match."); continue }
            let matched = matchedApps(rule)
            let fresh = (matched ?? []).filter { !settled.contains($0.bundleID) }
            if !rule.checkFurther { settled.formUnion(fresh.map(\.bundleID)) }  // even a rule Tatami skips below ends the search
            guard rule.workspace != nil || rule.floating else { skipped.append("Skipped \(label): it does not move to a workspace or float."); continue }
            guard let matched else { skipped.append("Skipped \(label): not a valid pattern."); continue }
            guard !matched.isEmpty else { skipped.append("Skipped \(label): no installed app matches."); continue }  // and no empty Room for it
            guard !fresh.isEmpty else { skipped.append("Skipped \(label): an earlier rule already handles its apps, and AeroSpace stops at the first match."); continue }
            let apps = fresh
            if let workspace = rule.workspace, !rooms.contains(workspace) {
                guard rooms.count < 9 else { skipped.append("Skipped \(label): workspace \(workspace) would be a tenth Room."); continue }
                rooms.append(workspace)
            }
            entries.append(.init(apps: apps, workspace: rule.workspace, floating: rule.floating, label: label))
        }
        return AeroImportPlan(rooms: rooms, entries: entries, skipped: skipped, monitors: monitors.filter { rooms.contains($0.key) })
    }
}

extension AeroImport {
    /// Why the chosen Room names cannot be used, or nil. Names must be 1 to 60 characters and different from each other.
    public static func nameProblem(plan: AeroImportPlan, roomNames: [String: String]) -> String? {
        var seen = Set<String>()
        for workspace in plan.rooms {
            let name = (roomNames[workspace] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { return "Workspace \(workspace) needs a Room name." }
            if name.count > 60 { return "The name for workspace \(workspace) is longer than 60 characters." }
            if !seen.insert(name.lowercased()).inserted { return "Two workspaces use the name \"\(name)\". Each Room needs its own name." }
        }
        return nil
    }
}

public struct AeroImportResult: Equatable {
    public var roomsCreated: [String] = []
    public var rulesAdded = 0
    public var floatRulesAdded = 0
    /// Apps that already had a routing rule of their own, which wins.
    public var keptExisting = 0
    /// Rooms that got a list of home displays from the monitor assignments.
    public var homesSet = 0
    /// Homes were set but per-display Rooms is off, so they do nothing until it is turned on.
    public var needsPerDisplayRooms = false
    public var skipped: [String] = []
}

extension WorkspaceState {
    /// Adds the plan's Rooms, routing rules and float rules. Rooms with a matching name are reused, an app that already
    /// has a routing rule keeps it, and importing the same plan twice adds nothing the second time.
    /// `roomNames` maps a workspace name to the Room name to use (default: "Workspace X").
    @discardableResult public mutating func applyAeroImport(_ plan: AeroImportPlan, roomNames: [String: String]) -> AeroImportResult {
        var result = AeroImportResult(skipped: plan.skipped)
        // Rules you had before the import, which win over imported ones (an unusable rule does not count).
        let yours = Set(rules.filter { rule in rule.enabled && stages.contains(where: { $0.id == rule.stageID }) && rule.titleContains.isEmpty }.map(\.bundleID))
        var roomForWorkspace: [String: UUID] = [:]
        for workspace in plan.rooms {
            let wanted = (roomNames[workspace] ?? "Workspace \(workspace)").trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = stages.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) {
                roomForWorkspace[workspace] = existing.id
            } else if let created = addStage(name: wanted) {
                roomForWorkspace[workspace] = created.id
                result.roomsCreated.append(created.name)
            } else {
                result.skipped.append("Skipped workspace \(workspace): no room for another Room (limit nine, or the name is empty or too long).")
            }
        }
        for (workspace, preferences) in plan.monitors.sorted(by: { $0.key < $1.key }) {
            // A home you set yourself is never replaced.
            guard let room = roomForWorkspace[workspace], !hasHome(room) else { continue }
            if setHomeFallbacks(preferences, for: room, enablingPerDisplayRooms: false) { result.homesSet += 1 }
        }
        for entry in plan.entries {
            if let workspace = entry.workspace, let room = roomForWorkspace[workspace] {
                for app in entry.apps {
                    let liveRooms = Set(stages.map(\.id))
                    if let existing = rules.first(where: { $0.enabled && $0.bundleID == app.bundleID && $0.titleContains.isEmpty && liveRooms.contains($0.stageID) }) {
                        if yours.contains(app.bundleID), existing.stageID != room { result.keptExisting += 1 }
                        continue
                    }
                    guard rules.count < 500 else {
                        if !result.skipped.contains(where: { $0.contains("500") }) { result.skipped.append("Stopped adding routing rules at the limit of 500.") }
                        break
                    }
                    rules.append(RoutingRule(bundleID: app.bundleID, appName: app.name, stageID: room))
                    result.rulesAdded += 1
                }
            }
            if entry.floating {
                for app in entry.apps where behaviorRules.count < 500 && !behaviorRules.contains(where: { $0.bundleID == app.bundleID && $0.titleContains.isEmpty }) {
                    behaviorRules.append(WindowBehaviorRule(bundleID: app.bundleID, behavior: .floating))
                    result.floatRulesAdded += 1
                }
            }
        }
        result.needsPerDisplayRooms = result.homesSet > 0 && !perDisplayRooms
        return result
    }
}
