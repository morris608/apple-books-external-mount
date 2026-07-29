import AppKit
import Combine
import Foundation

/// Maps the eject engine onto `EjectPresentation` (docs/IMPLEMENTATION.md §1 / §4).
@MainActor
final class EjectSessionController: ObservableObject {
    @Published private(set) var presentation: EjectPresentation
    @Published private(set) var previewMode = false

    private var process: Process?
    private var countdownTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var startedAt: Date?
    private var frozenElapsed: TimeInterval?
    private var step: Int = 1
    private var logLines: [LogLine] = []
    private var holder: String?
    private var failureReason: String?
    private var volumeName = "Audiobooks"
    private var deviceName = "disk6s2"
    private var facts: [FactRow] = []
    private var didStartSession = false

    private var repoRoot: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var ejectScript: URL {
        repoRoot.appendingPathComponent("scripts/apple-books-external-mount.sh")
    }

    private var statusFile: URL {
        URL(fileURLWithPath: "/tmp/apple-books-external-mount.eject-status")
    }

    private var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Logs/apple-books-external-mount/apple-books-external-mount-eject.log"
            )
    }

    private var imageURL: URL {
        URL(fileURLWithPath: "/Volumes/25External/BooksSafety/phase0b-populated.sparsebundle")
    }

    init() {
        presentation = .fixture(.armed)
        parseLaunchArguments()
    }

    func onAppear() {
        // SwiftUI can call onAppear more than once; only arm once.
        guard !didStartSession else { return }
        didStartSession = true
        if previewMode { return }
        if ProcessInfo.processInfo.arguments.contains("--no-auto") {
            enterIdle()
            return
        }
        beginArmedCountdown()
    }

    // MARK: - Actions

    func primary() {
        switch presentation.state {
        case .armed:
            cancelCountdown()
            beginEject()
        case .idle:
            beginEject()
        case .running:
            break
        case .succeeded:
            NSApp.keyWindow?.close()
        case .partial:
            quitHolderIfPossible()
            beginEject()
        case .failed:
            beginEject()
        }
    }

    func secondary() {
        switch presentation.state {
        case .armed:
            cancelCountdown()
            enterIdle()
        case .idle:
            NSApp.keyWindow?.close()
        case .running, .succeeded, .partial, .failed:
            revealLog()
        }
    }

    func revealLog() {
        try? FileManager.default.createDirectory(
            at: logFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logFile.path) {
            try? "".write(to: logFile, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([logFile])
    }

    // MARK: - Launch / preview

    private func parseLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(where: { $0.hasPrefix("--preview") }) else { return }
        previewMode = true
        let arg = args[idx]
        let stateName: String
        if arg.contains("=") {
            stateName = String(arg.split(separator: "=").last ?? "running")
        } else if args.indices.contains(idx + 1), !args[idx + 1].hasPrefix("-") {
            stateName = args[idx + 1]
        } else {
            stateName = "running"
        }
        let state = EjectState(rawValue: stateName) ?? .running
        presentation = .fixture(state)
    }

    // MARK: - Armed / idle

    private func beginArmedCountdown() {
        cancelCountdown()
        logLines = []
        appendSessionLog("mounted")
        appendSessionLog("armed")
        // Paint immediately — don't block the countdown on diskutil.
        publish(state: .armed, countdown: 3, elapsed: 0)
        Task { @MainActor in
            self.refreshVolumeMetadata()
        }

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in [3, 2, 1] {
                if Task.isCancelled { return }
                self.publish(state: .armed, countdown: remaining, elapsed: 0)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
            if Task.isCancelled { return }
            self.countdownTask = nil
            self.beginEject()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func enterIdle() {
        cancelCountdown()
        refreshVolumeMetadata()
        facts = gatherFacts()
        if logLines.isEmpty {
            appendSessionLog("mounted")
            appendSessionLog("awaiting")
        }
        publish(state: .idle, countdown: 0, elapsed: 0)
    }

    // MARK: - Eject engine

    private func beginEject() {
        cancelCountdown()
        guard process == nil else { return }

        holder = nil
        failureReason = nil
        frozenElapsed = nil
        step = 1
        logLines = []
        startedAt = Date()
        publish(state: .running, countdown: 0, elapsed: 0)

        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if self.frozenElapsed != nil { return }
                if self.presentation.state != .running { return }
                if let startedAt = self.startedAt {
                    self.publish(state: .running, countdown: 0,
                                 elapsed: Date().timeIntervalSince(startedAt))
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        try? FileManager.default.removeItem(at: statusFile)
        try? FileManager.default.createDirectory(
            at: logFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard FileManager.default.fileExists(atPath: ejectScript.path) else {
            failureReason = "missing apple-books-external-mount.sh"
            finish(state: .failed)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [ejectScript.path, "eject"]
        process.currentDirectoryURL = repoRoot

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.ingestEngineOutput(chunk)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handleTermination(exitCode: proc.terminationStatus)
            }
        }

        self.process = process
        do {
            try process.run()
        } catch {
            failureReason = error.localizedDescription
            finish(state: .failed)
        }
    }

    private func ingestEngineOutput(_ chunk: String) {
        let parts = chunk.split(whereSeparator: \.isNewline).map(String.init)
        for line in parts where !line.isEmpty {
            let message = sanitizeLogMessage(line)
            appendSessionLog(message)
            advanceStep(from: message)
            if let found = extractHolder(from: message) {
                holder = found
            }
        }
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        publish(state: .running, countdown: 0, elapsed: elapsed)
    }

    private func handleTermination(exitCode: Int32) {
        process = nil
        let status = (try? String(contentsOf: statusFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fullLog = logLines.map { "\($0.time) \($0.message)" }.joined(separator: "\n") + "\n"
        try? fullLog.write(to: logFile, atomically: true, encoding: .utf8)

        let drivePresent = FileManager.default.fileExists(atPath: "/Volumes/25External")
            || FileManager.default.fileExists(atPath: "/Volumes/Time Machine")

        // Already clear = success. Never show the EBUSY boilerplate for that.
        if !drivePresent && status != "partial" {
            if status != "ok" {
                appendSessionLog("already clear")
            }
            finish(state: .succeeded)
            return
        }

        if holder == nil {
            holder = detectBusyHolder()
        }

        switch status {
        case "ok":
            finish(state: .succeeded)
        case "partial":
            finish(state: .partial)
        default:
            if exitCode == 0 {
                finish(state: .succeeded)
            } else {
                failureReason = inferredFailureReason(drivePresent: drivePresent)
                finish(state: .failed)
            }
        }
    }

    /// Prefer a real reason from the log; never invent “EBUSY” unless the log said so.
    private func inferredFailureReason(drivePresent: Bool) -> String {
        let joined = logLines.map(\.message).joined(separator: "\n").lowercased()
        if joined.contains("ebusy") {
            return "the disk reported busy (EBUSY)"
        }
        if !drivePresent {
            return "25External is not mounted"
        }
        if let last = logLines.last?.message, !last.isEmpty {
            return last
        }
        return "the eject script exited without finishing"
    }

    private func finish(state: EjectState) {
        elapsedTask?.cancel()
        elapsedTask = nil
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? presentation.elapsed
        frozenElapsed = elapsed
        if state == .succeeded { step = 4 }
        publish(state: state, countdown: 0, elapsed: elapsed)
        announceResult(state)
    }

    private func announceResult(_ state: EjectState) {
        let text: String
        switch state {
        case .succeeded: text = "Safe to unplug."
        case .partial: text = "One hold. Your move."
        case .failed: text = "Still mounted."
        default: return
        }
        let announcement = NSAttributedString(string: text)
        NSAccessibility.post(
            element: NSApp.mainWindow as Any? ?? NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement]
        )
    }

    // MARK: - Log / step mapping

    private func appendSessionLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())
        var lines = logLines.map {
            LogLine(id: $0.id, time: $0.time, message: $0.message, isCurrent: false)
        }
        lines.append(LogLine(time: time, message: message, isCurrent: true))
        if lines.count > 40 { lines = Array(lines.suffix(40)) }
        logLines = lines
    }

    private func sanitizeLogMessage(_ line: String) -> String {
        // Strip script timestamp prefix: [2026-…] msg
        if let close = line.firstIndex(of: "]") {
            let after = line.index(after: close)
            return line[after...].trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private func advanceStep(from message: String) {
        let m = message.lowercased()
        let next: Int
        if m.contains("eject") || m.contains("detach") || m.contains("unplug") {
            next = 4
        } else if m.contains("time machine") || m.contains("tmutil") || m.contains("stopbackup") {
            next = 3
        } else if m.contains("flush") || m.contains("sync") || m.contains("quit") || m.contains("unmount") {
            next = 2
        } else if m.contains("resolve") || m.contains("sparsebundle") || m.contains("image") || m.contains("mount") {
            next = 1
        } else {
            return
        }
        if next >= step { step = next }
    }

    private func extractHolder(from message: String) -> String? {
        // e.g. "pid 4412 Music" or "Music still busy"
        if let range = message.range(of: #"pid\s+\d+\s+(\S+)"#, options: .regularExpression) {
            let chunk = String(message[range])
            return chunk.split(separator: " ").last.map(String.init)
        }
        return nil
    }

    private func detectBusyHolder() -> String? {
        let volume = "/Volumes/25External"
        guard FileManager.default.fileExists(atPath: volume) else { return "Time Machine" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-t", volume]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return "Time Machine" }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return "Time Machine" }
        let pids = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        guard let pid = pids.first else {
            // Common case for this disk: TM holds without a clean lsof hit.
            return "Time Machine"
        }
        let nameProc = Process()
        nameProc.executableURL = URL(fileURLWithPath: "/bin/ps")
        nameProc.arguments = ["-p", pid, "-o", "comm="]
        let namePipe = Pipe()
        nameProc.standardOutput = namePipe
        nameProc.standardError = FileHandle.nullDevice
        try? nameProc.run()
        nameProc.waitUntilExit()
        let nameData = namePipe.fileHandleForReading.readDataToEndOfFile()
        let name = String(data: nameData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            if name.contains("backupd") || name.lowercased().contains("time") {
                return "Time Machine"
            }
            return URL(fileURLWithPath: name).lastPathComponent
        }
        return "Time Machine"
    }

    private func quitHolderIfPossible() {
        guard let holder else { return }
        let lower = holder.lowercased()
        if lower.contains("time machine") || lower.contains("backupd") {
            _ = Process.launchedProcess(launchPath: "/usr/bin/tmutil", arguments: ["stopbackup"])
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = [holder]
        try? proc.run()
        proc.waitUntilExit()
    }

    // MARK: - Facts / metadata

    private func refreshVolumeMetadata() {
        volumeName = "Audiobooks"
        if let bsd = bsdName(for: "/Volumes/25External") {
            deviceName = bsd
        }
    }

    private func gatherFacts() -> [FactRow] {
        [
            FactRow(label: "volume", value: volumeFact()),
            FactRow(label: "last write", value: lastWriteFact()),
            FactRow(label: "time machine", value: timeMachineFact())
        ]
    }

    private func volumeFact() -> String {
        let path = "/Volumes/25External"
        guard FileManager.default.fileExists(atPath: path) else { return "unknown" }
        do {
            let values = try URL(fileURLWithPath: path)
                .resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            guard let total = values.volumeTotalCapacity,
                  let avail = values.volumeAvailableCapacity,
                  total > 0 else { return "unknown" }
            let used = total - avail
            let pct = Int((Double(used) / Double(total) * 100).rounded())
            return "\(formatBytes(Int64(total))) · \(pct)% full"
        } catch {
            return "unknown"
        }
    }

    private func lastWriteFact() -> String {
        let path = imageURL.path
        guard FileManager.default.fileExists(atPath: path) else { return "unknown" }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return "unknown" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) hr ago" }
        return "\(Int(seconds / 86_400)) day ago"
    }

    private func timeMachineFact() -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        proc.arguments = ["status"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return "unknown" }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("Running = 1") { return "backing up" }
        if text.contains("Running = 0") { return "idle" }
        return "unknown"
    }

    private func bsdName(for path: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        proc.arguments = ["info", path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            if line.contains("Device Node") {
                let part = line.split(separator: ":").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let part, part.hasPrefix("/dev/") {
                    return String(part.dropFirst(5))
                }
                return part.map { String($0) }
            }
        }
        return nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let tb = 1_000_000_000_000.0
        let gb = 1_000_000_000.0
        let b = Double(bytes)
        if b >= tb { return String(format: "%.2f TB", b / tb) }
        return String(format: "%.0f GB", b / gb)
    }

    // MARK: - Publish

    private func publish(state: EjectState, countdown: Int, elapsed: TimeInterval) {
        var model = EjectPresentation(state: state)
        model.volumeName = volumeName
        model.deviceName = deviceName
        model.step = max(1, min(4, step))
        model.countdown = countdown
        model.elapsed = frozenElapsed ?? elapsed
        model.holder = holder
        model.failureReason = failureReason
        model.facts = facts
        model.log = Array(logLines.suffix(4))
        presentation = model
    }
}
