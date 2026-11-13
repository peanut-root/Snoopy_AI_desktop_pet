import AppKit
import ApplicationServices
import Foundation
import Network

/// Keep the localhost bridge secret stable across app rebuilds and outside Git.
private enum LocalBridgePairing {
    static func token(legacyFiles: [URL]) -> String {
        let manager = FileManager.default
        let folder = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snoopy Desktop", isDirectory: true)
        return token(at: folder.appendingPathComponent("connection-token.txt"), legacyFiles: legacyFiles)
    }

    static func token(at file: URL, legacyFiles: [URL]) -> String {
        let manager = FileManager.default
        let folder = file.deletingLastPathComponent()
        if let stored = read(file) { return stored }
        let value = legacyFiles.compactMap(read).first ?? UUID().uuidString + UUID().uuidString
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try Data(value.utf8).write(to: file, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // The bridge still works for this run if local storage is unavailable.
        }
        return value
    }

    private static func read(_ file: URL) -> String? {
        guard let value = try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            (16...128).contains(value.count),
            value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) ||
                                    (97...122).contains($0) || $0 == 45 })
        else { return nil }
        return value
    }
}

func runLocalBridgePairingTests() throws {
    struct Failure: Error, CustomStringConvertible { let description: String }
    func check(_ value: Bool, _ label: String) throws {
        guard value else { throw Failure(description: label) }
    }
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("snoopy-pairing-test-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("private/connection-token.txt")
    let first = LocalBridgePairing.token(at: file, legacyFiles: [])
    try check((16...128).contains(first.count), "A new install receives a valid token")
    try check(LocalBridgePairing.token(at: file, legacyFiles: []) == first,
              "The token remains stable after relaunch")
    let permission = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
    try check(permission?.intValue == 0o600, "The local token is readable only by its owner")
    let old = folder.appendingPathComponent("old-token.txt")
    try Data("0123456789abcdef".utf8).write(to: old)
    let migrated = LocalBridgePairing.token(at: folder.appendingPathComponent("migrated/connection-token.txt"),
                                            legacyFiles: [old])
    try check(migrated == "0123456789abcdef", "A prior local pairing survives an app upgrade")
    print("PASS: 4 private local pairing token checks")
}

// Only lifecycle metadata and accessibility button names are inspected. Prompt and response
// text is never forwarded to the pet, written to disk, or included in diagnostics.
final class ActivityMonitor: @unchecked Sendable {
    private let onEvent: (String, String) -> Void
    private let queue = DispatchQueue(label: "Snoopy.ActivityMonitor", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let accessibilityQueue = DispatchQueue(label: "Snoopy.AccessibilityScan", qos: .utility)
    private var accessibilityScanInProgress = false
    private var axScanGeneration: UInt64 = 0
    private var enhancedAccessibilityPIDs = Set<pid_t>()
    private var bridgeReady = false
    private var bridgeError: String?
    private var webHeartbeatCount = 0
    private var webLastHeartbeatAt: Date?
    private var webLastEventAt: Date?
    private var axLastScanAt: Date?
    private var axLastScanComplete = false
    private var axObservedGenerationCount = 0
    private var axLastDetectedAt: Date?
    private var axLastDetectedBundleID: String?
    private var axBundleIDs: [pid_t: String] = [:]
    private var axLastPhase: String?
    private var axLastPhaseAt: Date?
    private var timer: DispatchSourceTimer?
    private var accessibilityTimer: DispatchSourceTimer?
    private var listener: NWListener?
    private var cursors: [String: LogCursor] = [:]
    private var emitted: [String: String] = [:]
    private var webLastSeen: [String: Date] = [:]
    private var accessibilityEnabled = false
    private var axActive = Set<pid_t>()
    private var axMissing: [pid_t: Int] = [:]
    private var axLastConfirmed: [pid_t: Date] = [:]
    private var running = false
    let connectionToken: String
    var diagnosticStatus: String {
        let details = connectionDiagnostics()
        return Self.describeConnections(
            running: details["running"] as? Bool ?? false,
            optedIn: details["accessibilityOptedIn"] as? Bool ?? false,
            trusted: details["accessibilityTrusted"] as? Bool ?? false,
            bridgeReady: details["bridgeReady"] as? Bool ?? false,
            bridgeError: details["bridgeError"] as? String,
            lastWebEvent: details["webLastEventAt"] as? String,
            webConnected: details["webConnected"] as? Bool ?? false,
            axObservedGenerationCount: details["axObservedGenerationCount"] as? Int ?? 0,
            axLastPhase: details["axLastPhase"] as? String)
    }

    // Read-only, JSON-serializable diagnostics; never include chat titles or contents.
    // The queue-specific marker permits callers already on the monitor queue.
    func connectionDiagnostics() -> [String: Any] {
        let trusted = AXIsProcessTrusted()
        let applications = Self.supportedRunningApplications().map {
            ["bundleID": $0.bundleIdentifier ?? "", "pid": Int($0.processIdentifier)] as [String: Any]
        }
        return onMonitorQueue {
            let formatter = ISO8601DateFormatter()
            let lastEvent = webLastEventAt.map { formatter.string(from: $0) }
            return [
                "scope": "this_process",
                "processID": Int(ProcessInfo.processInfo.processIdentifier),
                "running": running,
                "accessibilityTrusted": trusted,
                "accessibilityOptedIn": accessibilityEnabled,
                "accessibilityState": !accessibilityEnabled ? "disabled" : (!trusted ? "permission_required" : (running ? "observing" : "stopped")),
                "supportedRunningApps": applications,
                "bridgeReady": bridgeReady,
                "bridgeError": bridgeError as Any? ?? NSNull(),
                "bridgeAddress": "127.0.0.1:47831",
                "webActiveSourceCount": webLastSeen.count,
                "webHeartbeatCount": webHeartbeatCount,
                "webLastHeartbeatAt": webLastHeartbeatAt.map { formatter.string(from: $0) } as Any? ?? NSNull(),
                "webLastEventAt": lastEvent as Any? ?? NSNull(),
                "webConnected": bridgeReady && webLastEventAt.map { Date().timeIntervalSince($0) < 30 } == true,
                "axActiveSourceCount": axActive.count,
                "axLastScanAt": axLastScanAt.map { formatter.string(from: $0) } as Any? ?? NSNull(),
                "axLastScanComplete": axLastScanComplete,
                "axHistoryScope": "since_launch",
                "axObservedGenerationCount": axObservedGenerationCount,
                "axLastDetectedAt": axLastDetectedAt.map { formatter.string(from: $0) } as Any? ?? NSNull(),
                "axLastDetectedBundleID": axLastDetectedBundleID as Any? ?? NSNull(),
                "axLastPhase": axLastPhase as Any? ?? NSNull(),
                "axLastPhaseAt": axLastPhaseAt.map { formatter.string(from: $0) } as Any? ?? NSNull(),
                "axPollIntervalSeconds": 0.5
            ]
        }
    }

    private func onMonitorQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return body() }
        return queue.sync(execute: body)
    }

    static func describeConnections(running: Bool, optedIn: Bool, trusted: Bool,
                                    bridgeReady: Bool, bridgeError: String?,
                                    lastWebEvent: String?, webConnected: Bool, axObservedGenerationCount: Int = 0, axLastPhase: String? = nil) -> String {
        let codex = running ? "Codex：自动检测" : "Codex：未启动"
        let desktop: String
        if !optedIn { desktop = "ChatGPT 桌面版：未启用检测" }
        else if !trusted { desktop = "ChatGPT 桌面版：未获辅助功能权限" }
        else { desktop = running ? "ChatGPT 桌面版：已授权，正在观察" : "ChatGPT 桌面版：已授权，检测未启动" }
        let web: String
        if bridgeError != nil { web = "网页：本地连接失败（47831）" }
        else if !bridgeReady { web = "网页：本地连接未启动" }
        else if lastWebEvent == nil { web = "网页：尚未收到扩展事件" }
        else if webConnected { web = "网页：已收到扩展连接" }
        else { web = "网页：曾收到扩展事件，当前无心跳" }
        let phaseLabel = ["working": "生成中", "done": "已结束", "failed": "观察中断"][axLastPhase ?? ""]
        let history = "本次已捕获 \(axObservedGenerationCount) 次 GPT 生成" + (phaseLabel.map { "，最近" + $0 } ?? "")
        return [codex, desktop, web, history].joined(separator: " · ")
    }

    init(onEvent: @escaping (String, String) -> Void) {
        self.onEvent = onEvent
        self.queue.setSpecific(key: queueKey, value: 1)
        self.accessibilityEnabled = UserDefaults.standard.bool(forKey: "monitorChatGPTAccessibility")
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("connection-token.txt"),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("connection-token.txt"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("connection-token.txt")
        ].compactMap { $0 }
        connectionToken = LocalBridgePairing.token(legacyFiles: candidates)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.startBridge()
            self.scanLogs()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in
                guard let self, self.running else { return }
                self.scanLogs()
                self.expireWebLeases()
            }
            self.timer = timer
            timer.resume()
            let accessibilityTimer = DispatchSource.makeTimerSource(queue: self.queue)
            accessibilityTimer.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(75))
            accessibilityTimer.setEventHandler { [weak self] in
                guard let self, self.running, self.accessibilityEnabled else { return }
                self.scanAccessibility()
            }
            self.accessibilityTimer = accessibilityTimer
            accessibilityTimer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.axScanGeneration &+= 1
            self.timer?.cancel(); self.timer = nil
            self.accessibilityTimer?.cancel(); self.accessibilityTimer = nil
            self.listener?.cancel(); self.listener = nil
            self.bridgeReady = false
        }
    }

    func resetActivity() {
        // Preserve log offsets: only genuinely new lifecycle records may restart activity.
        queue.async { [weak self] in
            guard let self else { return }
            self.axScanGeneration &+= 1
            self.emitted.removeAll()
            self.webLastSeen.removeAll()
            self.axActive.removeAll()
            self.axMissing.removeAll()
            self.axLastConfirmed.removeAll()
        }
    }

    func enableAccessibility() {
        // Called by an explicit menu action or --enable-chatgpt-detection launch flag.
        // The operating system, not this setting, grants the actual AX permission.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        UserDefaults.standard.set(true, forKey: "monitorChatGPTAccessibility")
        queue.async { [weak self] in
            guard let self else { return }
            self.accessibilityEnabled = true
            if self.running { self.scanAccessibility() }
        }
    }

    private func emit(_ source: String, _ phase: String) {
        guard running, emitted[source] != phase else { return }
        // Initial idle/completed sources must not play an old celebration on launch.
        if emitted[source] == nil && phase != "working" { return }
        emitted[source] = phase
        if source.hasPrefix("accessibility:") {
            if phase == "working" { axObservedGenerationCount += 1; axLastDetectedAt = Date() }
            axLastPhase = phase
            axLastPhaseAt = Date()
        }
        DispatchQueue.main.async { [weak self] in self?.onEvent(source, phase) }
    }

    private func scanLogs() {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        let recent = Date().addingTimeInterval(-48 * 3600)
        for case let url as URL in files {
            guard url.pathExtension == "jsonl", let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let changed = values.contentModificationDate, changed > recent else { continue }
            let path = url.path
            let cursor = cursors[path] ?? LogCursor()
            cursors[path] = cursor
            let size = UInt64(values.fileSize ?? 0)
            guard size != cursor.offset else { continue }
            if size < cursor.offset { cursor.reset() }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            let firstRead = !cursor.initialized
            let window: UInt64 = 4 * 1024 * 1024
            if firstRead && size > window {
                // Read the metadata header to exclude inherited subagent histories.
                if let header = try? handle.read(upToCount: 128 * 1024) { cursor.inspectHeader(header) }
                cursor.offset = size - window
                cursor.dropFirstLine = true
            }
            do {
                try handle.seek(toOffset: cursor.offset)
                // A burst is bounded; remaining complete lines are consumed next poll.
                let data = try handle.read(upToCount: Int(min(window, size - cursor.offset))) ?? Data()
                cursor.offset += UInt64(data.count)
                let events = cursor.consume(data)
                cursor.initialized = true
                guard !cursor.ignored else { continue }
                if firstRead {
                    // A fresh in-flight turn may already exist when the app launches.
                    // Historic completed/aborted turns are intentionally not replayed.
                    if let event = events.last, event.phase == "working", changed > Date().addingTimeInterval(-15 * 60) {
                        cursor.activeTurn = event.turn
                        emit("codex:" + path, "working")
                    }
                } else {
                    for event in events {
                        if event.phase == "working" { cursor.activeTurn = event.turn; emit("codex:" + path, "working") }
                        else if event.turn == nil || cursor.activeTurn == nil || event.turn == cursor.activeTurn {
                            cursor.activeTurn = nil
                            emit("codex:" + path, event.phase)
                        }
                    }
                }
            } catch { continue }
        }
    }

    private func expireWebLeases() {
        let expired = webLastSeen.filter { Date().timeIntervalSince($0.value) > 30 }.map(\.key)
        for source in expired {
            webLastSeen[source] = nil
            emit(source, "failed")
        }
    }

    private func startBridge() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 47831)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.bridgeReady = true; self?.bridgeError = nil
                case .failed(let error): self?.bridgeReady = false; self?.bridgeError = error.localizedDescription
                case .cancelled: self?.bridgeReady = false
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                let request = BridgeRequest(connection: connection, token: self.connectionToken, status: { [weak self] in
                    self?.connectionDiagnostics() ?? [:]
                }) { [weak self] source, phase in
                    guard let self else { return }
                    let key = "web:" + source
                    self.webLastEventAt = Date()
                    if phase == "working" {
                        self.webHeartbeatCount += 1
                        self.webLastHeartbeatAt = Date()
                    }
                    self.webLastSeen[key] = phase == "working" ? Date() : nil
                    self.emit(key, phase)
                }
                request.start(on: self.queue)
            }
            listener.start(queue: queue)
        } catch { bridgeReady = false; bridgeError = error.localizedDescription }
    }

    private static let supportedBundleIDs: Set<String> = [
        "com.openai.chat", "com.openai.ChatGPT", "com.openai.codex", "com.google.Chrome", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "org.mozilla.firefox", "com.apple.Safari", "company.thebrowser.Browser"
    ]

    private static func supportedRunningApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { supportedBundleIDs.contains($0.bundleIdentifier ?? "") }
    }

    private func scanAccessibility() {
        guard AXIsProcessTrusted(), !accessibilityScanInProgress else { return }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = Self.supportedRunningApplications().sorted { left, right in
            if left.processIdentifier == frontmostPID { return right.processIdentifier != frontmostPID }
            if right.processIdentifier == frontmostPID { return false }
            return (left.bundleIdentifier ?? "") < (right.bundleIdentifier ?? "")
        }
        let present = Set(apps.map(\.processIdentifier))
        axBundleIDs = Dictionary(uniqueKeysWithValues: apps.compactMap { app in app.bundleIdentifier.map { (app.processIdentifier, $0) } })
        enhancedAccessibilityPIDs.formIntersection(present)
        for pid in axActive.subtracting(present) {
            emit("accessibility:\(pid)", "failed")
            axActive.remove(pid); axMissing[pid] = nil; axLastConfirmed[pid] = nil
        }
        let jobs = apps.map { app -> (pid_t, Bool, Bool, Bool) in
            let pid = app.processIdentifier
            let bundle = app.bundleIdentifier ?? ""
            let desktop = bundle == "com.openai.chat" || bundle == "com.openai.ChatGPT"
            let unified = bundle == "com.openai.codex"
            let chromium = ["com.openai.codex", "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac", "company.thebrowser.Browser"].contains(bundle)
            let requestEnhanced = chromium && enhancedAccessibilityPIDs.insert(pid).inserted
            return (pid, desktop, unified, requestEnhanced)
        }
        accessibilityScanInProgress = true
        let generation = axScanGeneration
        accessibilityQueue.async { [weak self] in
            var allComplete = true
            for (pid, desktop, unified, enhance) in jobs {
                let result = Self.findGeneratingButton(pid: pid, chatGPT: desktop, unifiedChatGPT: unified, enableEnhanced: enhance)
                allComplete = allComplete && result.complete
                // Publish the frontmost result immediately instead of waiting on every browser.
                self?.queue.async { [weak self] in
                    guard let self, self.running, self.accessibilityEnabled,
                          self.axScanGeneration == generation, AXIsProcessTrusted() else { return }
                    self.applyAXObservation(pid: pid, found: result.found, complete: result.complete)
                }
            }
            let completed = allComplete
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.accessibilityScanInProgress = false
                self.axLastScanAt = Date()
                self.axLastScanComplete = completed
            }
        }
    }

    private func applyAXObservation(pid: pid_t, found: Bool, complete: Bool) {
        if found {
            axLastConfirmed[pid] = Date()
            axLastDetectedAt = Date()
            axLastDetectedBundleID = axBundleIDs[pid]
            axMissing[pid] = 0
            if axActive.insert(pid).inserted { emit("accessibility:\(pid)", "working") }
        } else if complete && axActive.contains(pid) {
            axMissing[pid, default: 0] += 1
            if axMissing[pid, default: 0] >= 2 {
                axActive.remove(pid); axMissing[pid] = nil; axLastConfirmed[pid] = nil
                emit("accessibility:\(pid)", "done")
            }
        } else if axActive.contains(pid), let last = axLastConfirmed[pid], Date().timeIntervalSince(last) > 30 {
            // Losing the observable UI is not evidence of successful completion.
            axActive.remove(pid); axMissing[pid] = nil; axLastConfirmed[pid] = nil
            emit("accessibility:\(pid)", "failed")
        }
    }

    static func isGeneratingButtonLabel(_ label: String, inChatGPTContext: Bool, allowGenericStop: Bool = true) -> Bool {
        guard inChatGPTContext else { return false }
        let normalized = label.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let phrases = ["stop generating", "stop generation", "stop streaming", "stop responding", "stop response", "stop answering",
                       "停止生成", "停止响应", "停止回答", "停止回复", "停止串流", "停止回應", "停止產生", "停止回覆", "停止生成回复", "停止生成回覆", "停止生成响应"]
        if normalized == "stop" || normalized == "停止" { return allowGenericStop }
        return phrases.contains { phrase in
            if normalized == phrase { return true }
            guard normalized.hasPrefix(phrase), let next = normalized.dropFirst(phrase.count).first else { return false }
            return next.isWhitespace || "([,，·—-".contains(next)
        }
    }

    static func isGeneratingButtonIdentifier(_ identifier: String, inChatGPTContext: Bool, allowUnscopedStop: Bool = true) -> Bool {
        guard inChatGPTContext else { return false }
        let value = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        if value == "stop-button" { return allowUnscopedStop }
        return ["composer-stop-button", "stop-streaming-button", "stop-generating-button"].contains(value)
    }

    static func isKnownComposerPrimaryButtonClasses(_ classes: [String]) -> Bool {
        // Grounded in the shipped ChatGPT U3n primary-action button component.
        // That component's actual aria-label is just Stop / 停止 and has no ID.
        let tokens = Set(classes)
        return tokens.contains("size-token-button-composer") && tokens.contains("bg-composer-primary")
    }

    static func isKnownComposerIdentifier(_ identifier: String) -> Bool {
        let value = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        return ["composer", "chat-composer", "chatgpt-composer", "thread-composer", "composer-container", "composer-footer"].contains(value)
    }

    private static func findGeneratingButton(pid: pid_t, chatGPT: Bool, unifiedChatGPT: Bool, enableEnhanced: Bool) -> (found: Bool, complete: Bool) {
        let nativeChatGPT = chatGPT || unifiedChatGPT
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.12)
        // Chromium documents this as its opt-in to expose the renderer accessibility tree.
        // Request it once per process, never every poll (which can repeatedly rebuild it).
        if enableEnhanced { AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }

        func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
        func isMinimized(_ element: AXUIElement) -> Bool {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success && (value as? Bool) == true
        }
        var windows: [AXUIElement] = []
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = elementAttribute(root, attribute), !isMinimized(window), !windows.contains(where: { CFEqual($0, window) }) { windows.append(window) }
        }
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windowValue) == .success, let all = windowValue as? [AXUIElement] {
            for window in all.prefix(8) where !isMinimized(window) && !windows.contains(where: { CFEqual($0, window) }) { windows.append(window) }
        }
        guard !windows.isEmpty else { return (false, false) }
        if enableEnhanced {
            for window in windows { AXUIElementSetAttributeValue(window, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        }

        var budget = 6500
        var complete = true
        var observedContext = false
        let deadline = Date().addingTimeInterval(1.25)
        let leafRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXImage", "AXLink", "AXHeading"]
        for window in windows {
            var pending: [(AXUIElement, Int, Bool, Bool)] = [(window, 0, nativeChatGPT, false)]
            while let (element, depth, inheritedPage, inheritedComposer) = pending.popLast() {
                budget -= 1
                if budget < 0 || Date() > deadline { return (false, false) }
                var values: CFArray?
                let attributes = [kAXRoleAttribute, kAXChildrenAttribute] as CFArray
                let status = AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values)
                guard status == .success, let list = values as? [Any], list.count == 2, let role = list[0] as? String else { complete = false; continue }
                var isGPTPage = inheritedPage
                if role == "AXWebArea" && !nativeChatGPT {
                    var urlValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlValue) == .success {
                        let url = (urlValue as? URL) ?? (urlValue as? String).flatMap(URL.init(string:))
                        isGPTPage = ["chatgpt.com", "chat.openai.com"].contains(url?.host?.lowercased() ?? "")
                    }
                    // Ignore unrelated websites entirely, including buttons labelled Stop.
                    if !isGPTPage { continue }
                }
                if isGPTPage { observedContext = true }
                var inComposer = inheritedComposer
                if unifiedChatGPT && !leafRoles.contains(role) {
                    var contextIdentifier: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &contextIdentifier) == .success,
                       let value = contextIdentifier as? String, isKnownComposerIdentifier(value) { inComposer = true }
                }
                // The unified application also contains terminals/debug controls. An
                // unscoped Stop button there is not evidence that GPT is generating.
                var allowGenericStop = !unifiedChatGPT || inComposer
                if isGPTPage && role == kAXButtonRole as String {
                    if unifiedChatGPT && !allowGenericStop {
                        var classValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &classValue) == .success,
                           let classes = classValue as? [String] {
                            allowGenericStop = isKnownComposerPrimaryButtonClasses(classes)
                        }
                    }
                    var identifier: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &identifier) == .success,
                       let value = identifier as? String, isGeneratingButtonIdentifier(value, inChatGPTContext: true, allowUnscopedStop: allowGenericStop) { return (true, true) }
                    // Read only control labels; never AXValue or names from message content.
                    var labels: CFArray?
                    if AXUIElementCopyMultipleAttributeValues(element, [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] as CFArray, [], &labels) == .success,
                       let names = labels as? [Any], names.compactMap({ $0 as? String }).contains(where: { isGeneratingButtonLabel($0, inChatGPTContext: true, allowGenericStop: allowGenericStop) }) { return (true, true) }
                }
                if leafRoles.contains(role) { continue }
                if let children = list[1] as? [AXUIElement] {
                    if depth >= 36 && !children.isEmpty { complete = false }
                    else { pending.append(contentsOf: children.map { ($0, depth + 1, isGPTPage, inComposer) }) }
                }
            }
        }
        return (false, complete && observedContext)
    }

}

private struct LifecycleEvent {
    let turn: String?
    let phase: String
}

private final class LogCursor {
    var offset: UInt64 = 0
    var initialized = false
    var ignored = false
    var dropFirstLine = false
    var activeTurn: String?
    private var pending = Data()
    func reset() { offset = 0; initialized = false; ignored = false; pending.removeAll(); dropFirstLine = false; activeTurn = nil }
    func inspectHeader(_ data: Data) {
        guard let end = data.firstIndex(of: 10), let obj = try? JSONSerialization.jsonObject(with: data[..<end]) as? [String: Any], let payload = obj["payload"] as? [String: Any] else { return }
        ignored = (payload["source"] as? [String: Any])?["subagent"] != nil || payload["parent_thread_id"] is String
    }
    func consume(_ data: Data) -> [LifecycleEvent] {
        pending.append(data)
        var result: [LifecycleEvent] = []
        while let end = pending.firstIndex(of: 10) {
            let line = pending[..<end]
            pending.removeSubrange(...end)
            if dropFirstLine { dropFirstLine = false; continue }
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = obj["type"] as? String, let payload = obj["payload"] as? [String: Any] else { continue }
            if type == "session_meta" { ignored = (payload["source"] as? [String: Any])?["subagent"] != nil || payload["parent_thread_id"] is String; continue }
            guard type == "event_msg", let name = payload["type"] as? String else { continue }
            let phase: String
            switch name {
            case "task_started": phase = "working"
            case "task_complete", "task_finished": phase = payload["error"] != nil && !(payload["error"] is NSNull) ? "failed" : "done"
            case "turn_aborted", "task_failed": phase = "failed"
            default: continue
            }
            result.append(LifecycleEvent(turn: payload["turn_id"] as? String, phase: phase))
        }
        // A corrupt line cannot grow memory without bound.
        if pending.count > 8 * 1024 * 1024 { pending.removeAll(); dropFirstLine = true }
        return result
    }
}

private final class BridgeRequest: @unchecked Sendable {
    private let connection: NWConnection
    private let token: String
    private let status: (() -> [String: Any])?
    private let event: (String, String) -> Void
    private var buffer = Data()
    private var finished = false
    private var retained: BridgeRequest?
    private var timeout: DispatchWorkItem?
    init(connection: NWConnection, token: String, status: (() -> [String: Any])? = nil, event: @escaping (String, String) -> Void) {
        self.connection = connection; self.token = token; self.status = status; self.event = event
    }
    func start(on queue: DispatchQueue) {
        retained = self
        connection.start(queue: queue)
        let timeout = DispatchWorkItem { [weak self] in self?.finish() }
        self.timeout = timeout
        queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        receive()
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, !self.finished else { return }
            if let data { self.buffer.append(data) }
            if self.buffer.count > 32768 { self.reply(413); return }
            if self.parse() { return }
            if complete || error != nil { self.reply(400); return }
            self.receive()
        }
    }
    @discardableResult private func parse() -> Bool {
        guard let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > 16384 { reply(431); return true }
            return false
        }
        guard let header = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) else { reply(400); return true }
        let lines = header.components(separatedBy: "\r\n")
        guard let request = lines.first?.split(separator: " "), request.count == 3 else { reply(400); return true }
        let method = String(request[0]), path = String(request[1])
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { reply(400); return true }
            let key = line[..<separator].lowercased()
            guard fields[key] == nil else { reply(400); return true }
            fields[key] = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }
        if let origin = fields["origin"], !(origin.hasPrefix("chrome-extension://") || origin.hasPrefix("moz-extension://")) { reply(403); return true }
        guard fields["transfer-encoding"] == nil else { reply(400); return true }
        if method == "GET" && path == "/health" { reply(200, body: "{\"ok\":true,\"service\":\"snoopy\"}"); return true }
        if method == "GET" && path == "/status" {
            guard let supplied = fields["x-snoopy-token"], constantEqual(supplied, token) else { reply(403); return true }
            guard let status, let bytes = try? JSONSerialization.data(withJSONObject: status(), options: [.sortedKeys]),
                  let body = String(data: bytes, encoding: .utf8) else { reply(503); return true }
            reply(200, body: body)
            return true
        }
        guard method == "POST", path == "/event", let lengthText = fields["content-length"], let length = Int(lengthText), length > 0, length <= 4096,
              fields["content-type"]?.lowercased().hasPrefix("application/json") == true else { reply(400); return true }
        let bodyStart = boundary.upperBound
        guard buffer.count - bodyStart >= length else { return false }
        guard let body = try? JSONSerialization.jsonObject(with: buffer[bodyStart..<(bodyStart + length)]) as? [String: Any],
              let supplied = body["token"] as? String, constantEqual(supplied, token) else { reply(403); return true }
        guard let source = body["source"] as? String, !source.isEmpty, source.utf8.count <= 160, !source.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let phase = body["phase"] as? String, ["working", "done", "failed"].contains(phase) else { reply(400); return true }
        event(source, phase)
        reply(200, body: "{\"ok\":true}")
        return true
    }
    private func constantEqual(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8), rhs = Array(b.utf8)
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(lhs, rhs) { difference |= x ^ y }
        return difference == 0
    }
    private func reply(_ code: Int, body: String = "{\"ok\":false}") {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 413: "Payload Too Large", 431: "Request Header Fields Too Large", 503: "Service Unavailable"][code] ?? "Error"
        let response = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [self] _ in finish() })
    }
    private func finish() { finished = true; timeout?.cancel(); timeout = nil; connection.cancel(); retained = nil }
}
