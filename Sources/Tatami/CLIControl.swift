import AppKit
import TatamiCore

/// The `tatami` command: a private local socket (same user only) that runs the same actions as the keyboard shortcuts.
/// Nothing here runs a program or touches files; commands only call actions that already exist.
extension AppModel {
    private var cliSocketPath: String { CLIPaths.socketPath(home: NSHomeDirectory(), uid: getuid()) }

    func startCLIServer() {
        // An isolated data folder (tests, snapshots) must never take over the real user's socket.
        guard state.cliEnabled, cliServer == nil, ProcessInfo.processInfo.environment["TATAMI_DATA_DIR"] == nil else { return }
        let server = CLIServer(path: cliSocketPath) { [weak self] request in
            await AppModel.handleCLI(request, on: self)  // hops to the main actor, where all window state lives
        }
        do { try server.start(); cliServer = server }
        catch { self.error = "The tatami command is unavailable (\(error)). Another Tatami may be running, or ~/Library/Application Support/Tatami is not private to you." }
    }

    private static func handleCLI(_ request: CLIRequest, on model: AppModel?) -> CLIResponse {
        model?.runCLI(request) ?? .failure("Tatami is quitting.")
    }

    func stopCLIServer() {
        cliServer?.stop()
        cliServer = nil
    }

    func setCLIEnabled(_ on: Bool) {
        state.cliEnabled = on
        persist()
        if on { startCLIServer() } else { stopCLIServer() }
        if on && cliServer == nil { return }  // startCLIServer already explained why
        notice = on ? "The tatami command is on." : "The tatami command is off."
    }

    // MARK: running a request

    func runCLI(_ request: CLIRequest) -> CLIResponse {
        switch CLICommand.parse(request.args) {
        case .failure(.empty): return .failure(CLICommand.helpText)
        case .failure(.unknown(let name)): return .failure("Unknown command \"\(name)\". Run: tatami help")
        case .failure(.usage(let text)): return .failure(text)
        case .success(let command): return execute(command)
        }
    }

    private func execute(_ command: CLICommand) -> CLIResponse {
        switch command {
        case .status(let json): return .success(cliStatus(json: json))
        case .list(let what, let json): return .success(cliListing(what, json: json))
        case .home(let room, let display): return setRoomHome(room: room, display: display)
        case .start:
            if !managing { toggleManagement() }
            return managing ? .success("Managing windows.") : .failure(error ?? "Could not start. Grant Accessibility access first.")
        case .pause:
            if managing { toggleManagement() }
            return .success("Paused. Windows are restored.")
        case .rescue:
            rescue()
            return .success("Windows restored. Management is paused.")
        default: break
        }
        // Like the keyboard shortcuts, the rest only work while Tatami is managing.
        guard managing else { return .failure("Tatami is paused. Run: tatami start") }
        notice = nil
        error = nil
        switch command {
        case .stage(let number):
            guard state.stages.indices.contains(number - 1) else { return .failure("There is no Room \(number).") }
            switchStage(state.stages[number - 1].id)
        case .stageStep(let step): switchStage(roomID(offset: step))
        case .roomBack: goToPreviousRoom()
        case .send(let number):
            guard state.stages.indices.contains(number - 1) else { return .failure("There is no Room \(number).") }
            guard let id = service.focusedID() else { return .failure("Focus a window first.") }
            send(id, to: state.stages[number - 1].id)
        case .focus(let direction): focusDirectional(direction)
        case .move(let direction): moveDirectional(direction)
        case .cycle(let step): cycleWindows(offset: step)
        case .pane(let number): focusPane(number: number)
        case .movePane(let number): moveToPane(number: number)
        case .float: toggleFloating()
        case .floatApp: toggleFloatingForApp()
        case .rotate: rotateSplit()
        case .tiles: toggleWindowMode()
        case .display(let step): sendFocusedWindowToDisplay(offset: step)
        case .undoLayout: undoLayout()
        case .status, .list, .start, .pause, .rescue, .home: break  // handled above
        }
        if let message = error { return .failure(message) }
        return .success(notice ?? "")
    }

    // MARK: queries

    private func cliStatus(json: Bool) -> String {
        let onStage = service.windows.filter { $0.stageID == state.activeStageID }.count
        if json {
            return CLIFormat.json([["version": Release.version, "release": Release.stage, "protocol": "\(CLIProtocol.version)", "managing": managing ? "yes" : "no",
                                    "room": state.activeStage.name, "windows": "\(onStage)", "displays": "\(displays.count)"]])
        }
        return ["Tatami \(Release.label)", managing ? "Managing" : "Paused", "Room: \(state.activeStage.name)",
                "Windows on this Room: \(onStage)", "Displays: \(displays.count)"].joined(separator: "\n")
    }

    private func cliListing(_ what: CLIListing, json: Bool) -> String {
        let rows: [[String: String]]
        let columns: [String]
        switch what {
        case .windows:
            columns = ["id", "app", "title", "room", "display", "mode"]
            rows = service.windows.map { window in
                let frame = window.hidden == nil ? window.frame : window.realFrame
                let mode = window.hidden != nil ? "hidden" : layoutKey(containing: window.id) != nil ? "tiled" : isFloating(window) ? "floating" : "free"
                return ["id": String(window.id.uuidString.prefix(8)), "app": window.appName, "title": window.title,
                        "room": state.stages.first { $0.id == window.stageID }?.name ?? "", "display": service.display(for: frame)?.name ?? "", "mode": mode]
            }
        case .rooms:
            // The home column only appears once a Room has a home, so output is unchanged for everyone else.
            let anyHome = state.stages.contains { $0.homeDisplay != nil }
            columns = ["number", "name", "active", "windows"] + (anyHome ? ["home"] : [])
            rows = state.stages.enumerated().map { index, stage in
                var row = ["number": "\(index + 1)", "name": stage.name, "active": stage.id == state.activeStageID ? "yes" : "no",
                           "windows": "\(service.windows.filter { $0.stageID == stage.id }.count)"]
                if anyHome {
                    row["home"] = stage.homeDisplay.map { key in service.displays.first { $0.id == key }?.name ?? "(unplugged)" } ?? "-"
                }
                return row
            }
        case .displays:
            columns = ["number", "name", "size", "mode"]
            rows = orderedDisplays.enumerated().map { index, display in
                ["number": "\(index + 1)", "name": display.name, "size": "\(Int(display.fullFrame.width))x\(Int(display.fullFrame.height))",
                 "mode": isTiled(stage: state.activeStageID, display: display.id) ? "tiles" : "freeform"]
            }
        }
        return json ? CLIFormat.json(rows) : CLIFormat.table(rows, columns: columns)
    }

    // MARK: installing the command

    /// Links the command inside the app into ~/.local/bin, which needs no administrator password. A real file with
    /// the same name is never replaced.
    func installCommandLineTool() {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tatami")
        guard FileManager.default.isExecutableFile(atPath: source.path) else {
            error = "This build has no command-line tool inside it. Build the app with scripts/package_app.sh."
            return
        }
        guard !source.path.contains("/AppTranslocation/"), !source.path.hasPrefix("/Volumes/") else {
            error = "Move Tatami.app to your Applications folder first, then install the command, so the link keeps working."
            return
        }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        let link = folder.appendingPathComponent("tatami")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) {
                if existing != source.path {
                    // Only a link into some Tatami.app is replaced; a link to another tool is left alone.
                    guard existing.hasSuffix("/Contents/Helpers/tatami") else {
                        error = "~/.local/bin/tatami already points to \(existing). Move it aside first."
                        return
                    }
                    try FileManager.default.removeItem(at: link)
                }
            } else if FileManager.default.fileExists(atPath: link.path) {
                error = "A file named tatami already exists in ~/.local/bin. Move it aside first."
                return
            }
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil {
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            }
            notice = "Installed ~/.local/bin/tatami. If the command is not found, add ~/.local/bin to your PATH."
        } catch {
            self.error = "Could not install the command: \(error.localizedDescription)"
        }
    }
}
