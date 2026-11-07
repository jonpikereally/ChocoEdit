import AppKit

/// Every failure a user can run into has a stable code, so it can be looked up
/// on the public error list (ERRORS.md) or pasted into an LLM. Add new codes
/// here and to ERRORS.md together, and never show an error without one.
/// Codes are never reused or renumbered.
enum ErrorCode: String, CaseIterable {
    // 1xx — updates
    case noUpdateSource = "CE-101"
    case badUpdateSource = "CE-102"
    case updateSourceUnreachable = "CE-103"
    case updateServerError = "CE-104"
    case updateInfoMalformed = "CE-105"
    case updateDownloadFailed = "CE-106"
    case updateUnpackFailed = "CE-107"
    case updateMissingApp = "CE-108"
    case updateWrongApp = "CE-109"
    case updateDamagedApp = "CE-110"
    case updateInstallerFailed = "CE-111"
    case updateSwapFailed = "CE-112"
    // 2xx — talking to the pedal
    case midiUnavailable = "CE-201"
    case noPedal = "CE-202"
    case portOpenFailed = "CE-203"
    case notConnected = "CE-204"
    case sendFailed = "CE-205"
    case noReply = "CE-206"
    case badReply = "CE-207"
    case writeRejected = "CE-208"
    case verifyFailed = "CE-209"
    case wrongDevice = "CE-210"
    // 3xx — files and backups
    case fileReadFailed = "CE-301"
    case fileWrongSize = "CE-302"
    case fileWriteFailed = "CE-303"
    case backupFailed = "CE-304"
    // 6xx — reserved for the installer scripts
    // 9xx — anything not covered above
    case unexpected = "CE-999"

    var summary: String {
        switch self {
        case .noUpdateSource: return "No update source is set."
        case .badUpdateSource: return "The update source isn't a web link or a file path."
        case .updateSourceUnreachable: return "Couldn't reach the update source."
        case .updateServerError: return "The update server returned an error."
        case .updateInfoMalformed: return "The update information is damaged or in the wrong format."
        case .updateDownloadFailed: return "Couldn't download the update."
        case .updateUnpackFailed: return "Couldn't unpack the downloaded update."
        case .updateMissingApp: return "The downloaded update doesn't contain ChocoEdit."
        case .updateWrongApp: return "The downloaded update is a different app."
        case .updateDamagedApp: return "The downloaded update is damaged."
        case .updateInstallerFailed: return "Couldn't start installing the update."
        case .updateSwapFailed: return "Installing the update failed, so the previous version was kept."
        case .midiUnavailable: return "macOS's MIDI system couldn't be opened."
        case .noPedal: return "No Chocolate Plus was found."
        case .portOpenFailed: return "Couldn't open the pedal's MIDI port."
        case .notConnected: return "The pedal isn't connected."
        case .sendFailed: return "Couldn't send MIDI to the pedal."
        case .noReply: return "The pedal didn't answer."
        case .badReply: return "The pedal sent an answer ChocoEdit didn't expect."
        case .writeRejected: return "The pedal refused to save a setting."
        case .verifyFailed: return "A setting read back differently from what was written."
        case .wrongDevice: return "The connected device isn't a Chocolate Plus."
        case .fileReadFailed: return "Couldn't open the settings file."
        case .fileWrongSize: return "That file isn't a Chocolate Plus settings file."
        case .fileWriteFailed: return "Couldn't save the settings file."
        case .backupFailed: return "Couldn't save a backup of the pedal's settings, so nothing was written."
        case .unexpected: return "Something unexpected went wrong."
        }
    }

    var hint: String {
        switch self {
        case .noUpdateSource, .badUpdateSource:
            return "Set one with “Update Source…” in the ChocoEdit menu, or leave it empty to use the built-in source."
        case .updateSourceUnreachable:
            return "Check your internet connection and try again."
        case .updateServerError, .updateDownloadFailed:
            return "Try again in a few minutes. If it keeps happening, download the latest version from GitHub."
        case .updateInfoMalformed, .updateUnpackFailed, .updateMissingApp, .updateWrongApp, .updateDamagedApp:
            return "The published update is broken. Download the latest version from GitHub instead."
        case .updateInstallerFailed, .updateSwapFailed:
            return "Make sure ChocoEdit is in ~/Applications and that the folder isn't locked, then try again."
        case .midiUnavailable:
            return "Quit and reopen ChocoEdit. If it keeps happening, restart the Mac."
        case .noPedal:
            return "Plug the pedal into the Mac with a USB-C data cable (not charge-only), switch it on, and click Refresh. Quit CubeSuite first: two editors talking to the pedal at once confuse it."
        case .portOpenFailed, .sendFailed:
            return "Unplug the pedal, plug it back in, and click Refresh. Quit CubeSuite if it's open."
        case .notConnected:
            return "Pick the pedal in the port menu and click Connect."
        case .noReply:
            return "Use the USB cable rather than Bluetooth, quit CubeSuite, and try again. If it still doesn't answer, switch the pedal off and on."
        case .badReply:
            return "Try again. If it keeps happening, copy the details: the pedal's firmware may use a newer protocol."
        case .writeRejected, .verifyFailed:
            return "Read the settings from the pedal again before writing. Your backup from before the write is in ~/Documents/ChocoEdit Backups and can be loaded and written back."
        case .wrongDevice:
            return "Pick the Chocolate Plus in the port menu. ChocoEdit only edits the Chocolate Plus."
        case .fileReadFailed, .fileWriteFailed:
            return "Check the file is where you think and that the folder isn't locked."
        case .fileWrongSize:
            return "ChocoEdit opens .chocoplus files it saved, and CubeSuite .fcp exports of the same size."
        case .backupFailed:
            return "Check there's space on the disk and that ~/Documents isn't locked, then try again."
        case .unexpected:
            return "Try again. If it keeps happening, copy the details and ask for help."
        }
    }
}

struct AppError: LocalizedError {
    let code: ErrorCode
    /// Technical specifics (byte offsets, system status codes). Never file contents.
    let detail: String?

    init(_ code: ErrorCode, _ detail: String? = nil) {
        self.code = code
        self.detail = detail
    }

    init(wrapping error: Error, as code: ErrorCode = .unexpected) {
        if let e = error as? AppError { self = e } else { self.init(code, error.localizedDescription) }
    }

    var errorDescription: String? { "\(code.summary) (\(code.rawValue))" }
}

/// Logs every error to ~/Library/Application Support/ChocoEdit/errors.log and
/// shows it with its code.
final class ErrorReporter {
    enum Surface { case alert, logOnly }

    static let shared = ErrorReporter()
    static let helpURL = "https://github.com/\(AppVersion.repo)/blob/main/ERRORS.md"
    static let plainTextHelpURL = "https://raw.githubusercontent.com/\(AppVersion.repo)/main/ERRORS.md"
    static let tooltip = "Look up this error code on the ChocoEdit error list: \(helpURL)\n"
        + "You can also give that page and the copied error details to an AI assistant for help."

    private var lastLogged: [ErrorCode: Date] = [:]

    static let logURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChocoEdit", isDirectory: true)
            .appendingPathComponent("errors.log")
    }()

    func report(_ error: AppError, surface: Surface, title: String = "ChocoEdit ran into a problem") {
        DispatchQueue.main.async {
            self.log(error)
            if surface == .alert { self.present(error, title: title) }
        }
    }

    @discardableResult
    func present(_ error: AppError, title: String, actions: [String] = []) -> Int? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        var text = error.code.summary
        if let d = error.detail, !d.isEmpty { text += "\n\n\(d)" }
        text += "\n\n\(error.code.hint)\n\nError code: \(error.code.rawValue)"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        for a in actions { alert.addButton(withTitle: a) }
        alert.addButton(withTitle: "Copy Error Details")
        alert.addButton(withTitle: "Open Error List")
        Self.addTooltips(to: alert)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if response == actions.count + 1 {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(Self.details(error), forType: .string)
            return nil
        }
        if response == actions.count + 2 {
            if let url = URL(string: Self.helpURL) { NSWorkspace.shared.open(url) }
            return nil
        }
        if response >= 1 && response <= actions.count { return response - 1 }
        return nil
    }

    static func addTooltips(to alert: NSAlert) {
        alert.layout()
        func walk(_ view: NSView) {
            if view is NSTextField { view.toolTip = tooltip }
            view.subviews.forEach(walk)
        }
        if let content = alert.window.contentView {
            content.toolTip = tooltip
            walk(content)
        }
    }

    static func details(_ error: AppError) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        var lines = ["ChocoEdit error \(error.code.rawValue): \(error.code.summary)"]
        if let d = error.detail, !d.isEmpty { lines.append("Details: \(d)") }
        lines.append("Suggested fix: \(error.code.hint)")
        lines.append("ChocoEdit v\(AppVersion.version) (built \(AppVersion.built)), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(arch)")
        lines.append("Time: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Error code list: \(helpURL)")
        lines.append("Plain-text error list for AI assistants: \(plainTextHelpURL)")
        return lines.joined(separator: "\n")
    }

    func log(_ error: AppError) {
        let now = Date()
        if let last = lastLogged[error.code], now.timeIntervalSince(last) < 60 { return }
        lastLogged[error.code] = now
        let line = "\(ISO8601DateFormatter().string(from: now)) \(error.code.rawValue) v\(AppVersion.version) "
            + error.code.summary + (error.detail.map { " — \($0)" } ?? "") + "\n"
        let url = Self.logURL
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512 * 1024 {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
