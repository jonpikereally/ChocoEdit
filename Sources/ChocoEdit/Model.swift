import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Which part of the settings the main area is editing.
enum EditArea: Hashable {
    case custom   // Custom MIDI (advanced) groups
    case mix      // Mix Key groups
    case keyboard // Custom keyboard groups
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var ports: [MIDIPortInfo] = []
    @Published var selectedPortName: String?
    @Published var identity: Pedal.Identity?
    @Published var connectedPortName: String?

    /// What the pedal held when last read (or written). nil until read.
    @Published var baseline: [UInt8]?
    /// The settings being edited.
    @Published var settings: PedalSettings?
    @Published var fileURL: URL?

    @Published var busy: String?
    @Published var progress: Double = 0
    @Published var status: String = "Plug in the pedal with USB and click Read from Pedal."
    @Published var lastError: AppError?

    @Published var area: EditArea = .custom
    @Published var group = 0
    @Published var selectedSwitch = 0

    /// Messages the pedal sends when you step on it, newest first.
    @Published var liveMessages: [(Date, String)] = []

    private var midi: MIDIConnection?
    private let queue = DispatchQueue(label: "chocoedit.pedal")

    var isDirty: Bool {
        guard let s = settings else { return false }
        return baseline.map { $0 != s.bytes } ?? true
    }
    var isConnected: Bool { connectedPortName != nil }

    init() {
        do {
            let m = try MIDIConnection()
            m.onSetupChanged = { [weak self] in self?.refreshPorts() }
            m.onOtherMessage = { [weak self] msg in
                DispatchQueue.main.async { self?.logLive(msg) }
            }
            midi = m
        } catch {
            fail(AppError(wrapping: error, as: .midiUnavailable), alert: false)
        }
        refreshPorts()
    }

    // MARK: Ports

    /// True once you've picked a port yourself; until then ChocoEdit keeps
    /// following the pedal (e.g. when it's plugged in after the app opened).
    private var portPickedByUser = false

    func pickPort(_ name: String?) {
        selectedPortName = name
        portPickedByUser = true
    }

    func refreshPorts() {
        ports = MIDIConnection.ports()
        let pedal = ports.first(where: \.looksLikeChocolate)?.name
        let current = ports.first(where: { $0.name == selectedPortName })
        if current == nil {
            // Never fall back to an IAC bus: it's a loopback, not hardware.
            selectedPortName = pedal ?? ports.first(where: { !$0.name.hasPrefix("IAC") })?.name ?? ports.first?.name
            portPickedByUser = false
        } else if let pedal, current?.looksLikeChocolate == false, !portPickedByUser {
            selectedPortName = pedal
            status = "Found the pedal on \(pedal)."
        }
        if let c = connectedPortName, !ports.contains(where: { $0.name == c }) {
            connectedPortName = nil
            identity = nil
            status = "The pedal was unplugged."
        }
    }

    private func openSelected() throws -> Pedal {
        guard let midi else { throw AppError(.midiUnavailable) }
        guard let name = selectedPortName, let port = ports.first(where: { $0.name == name }) else {
            throw AppError(.noPedal, ports.isEmpty ? "no MIDI ports" : "ports: " + ports.map(\.name).joined(separator: ", "))
        }
        if midi.current?.name != port.name { try midi.open(port) }
        return Pedal(midi)
    }

    // MARK: Pedal operations

    /// Runs `work` on the pedal queue with a progress bar.
    private func run(_ label: String, _ work: @escaping (Pedal, @escaping (Double) -> Void) throws -> Void,
                     done: @escaping () -> Void = {}) {
        guard busy == nil else { return }
        let pedal: Pedal
        do { pedal = try openSelected() } catch { fail(AppError(wrapping: error)); return }
        busy = label
        progress = 0
        let report: (Double) -> Void = { f in DispatchQueue.main.async { self.progress = f } }
        queue.async {
            do {
                try work(pedal, report)
                DispatchQueue.main.async { self.busy = nil; done() }
            } catch {
                DispatchQueue.main.async {
                    self.busy = nil
                    self.fail(AppError(wrapping: error))
                }
            }
        }
    }

    func readFromPedal() {
        if isDirty, settings != nil, !confirm("Replace your unsaved edits?",
                                             "Reading from the pedal throws away the changes you haven't written or saved.",
                                             ok: "Read from Pedal") { return }
        var id: Pedal.Identity?
        var bytes: [UInt8] = []
        let port = selectedPortName
        run("Reading from pedal…", { pedal, progress in
            id = try pedal.identify()
            guard id?.name == "FootCtrlPlus" else { throw AppError(.wrongDevice, "the device calls itself “\(id?.name ?? "")”") }
            bytes = try pedal.read(length: PedalSettings.size, progress: progress)
        }, done: {
            self.identity = id
            self.connectedPortName = port
            self.baseline = bytes
            self.settings = PedalSettings(bytes: bytes)
            self.fileURL = nil
            self.followPedalMode()
            self.status = "Read \(bytes.count) bytes from \(port ?? "the pedal")."
            self.autoBackup(bytes, reason: "read")
        })
    }

    func writeToPedal() {
        guard let edited = settings?.bytes else { return }
        let base = baseline
        var written = 0
        var fresh: [UInt8] = []
        run("Writing to pedal…", { pedal, progress in
            let id = try pedal.identify()
            guard id.name == "FootCtrlPlus" else { throw AppError(.wrongDevice, "the device calls itself “\(id.name)”") }
            // Always back up what's on the pedal right now, before touching it.
            fresh = try pedal.read(length: PedalSettings.size) { progress($0 * 0.3) }
            try EditorModel.backup(fresh, reason: "before-write")
            // Write what you changed since reading (so the pedal's own state,
            // like its current group, isn't reverted), or everything that
            // differs when editing a file.
            let from = base ?? fresh
            var target = fresh
            for r in Pedal.diffRanges(from, edited, mergeGap: 0) { target.replaceSubrange(r, with: edited[r]) }
            written = try pedal.writeChanges(from: fresh, to: target) { progress(0.3 + $0 * 0.7) }
            fresh = target
        }, done: {
            self.baseline = fresh
            self.settings = PedalSettings(bytes: fresh)
            self.status = written == 0 ? "The pedal already had these settings." : "Wrote and verified \(written) bytes."
        })
    }

    // MARK: Files

    static let fileType = UTType(filenameExtension: "chocoplus") ?? .data

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.fileType, UTType(filenameExtension: "fcp") ?? .data, .data]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let d = try Data(contentsOf: url)
            guard d.count == PedalSettings.size else {
                throw AppError(.fileWrongSize, "\(url.lastPathComponent) is \(d.count) bytes; a settings file is \(PedalSettings.size)")
            }
            settings = PedalSettings(bytes: [UInt8](d))
            fileURL = url
            followPedalMode()
            status = "Opened \(url.lastPathComponent). Write to Pedal sends it."
        } catch let e as AppError { fail(e) } catch { fail(AppError(.fileReadFailed, "\(url.path): \(error.localizedDescription)")) }
    }

    func saveFile() {
        guard let s = settings else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.fileType]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Chocolate Plus \(Self.stamp()).chocoplus"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(s.bytes).write(to: url)
            fileURL = url
            status = "Saved \(url.lastPathComponent)."
        } catch { fail(AppError(.fileWriteFailed, "\(url.path): \(error.localizedDescription)")) }
    }

    func revert() {
        guard let b = baseline else { return }
        settings = PedalSettings(bytes: b)
        status = "Back to what the pedal has."
    }

    nonisolated static let backupFolder: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ChocoEdit Backups", isDirectory: true)

    nonisolated static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }

    nonisolated static func backup(_ bytes: [UInt8], reason: String) throws {
        let url = Self.backupFolder.appendingPathComponent("\(Self.stamp()) \(reason).chocoplus")
        do {
            try FileManager.default.createDirectory(at: Self.backupFolder, withIntermediateDirectories: true)
            try Data(bytes).write(to: url)
        } catch {
            throw AppError(.backupFailed, "\(url.path): \(error.localizedDescription)")
        }
    }

    /// Keeps a copy of every read too, but never fails the read over it.
    private func autoBackup(_ bytes: [UInt8], reason: String) {
        do { try Self.backup(bytes, reason: reason) } catch {
            ErrorReporter.shared.report(AppError(wrapping: error), surface: .logOnly)
        }
    }

    // MARK: Editing helpers

    func followPedalMode() {
        guard let s = settings else { return }
        if s.mode == PedalMode.mixKey.rawValue { area = .mix; group = min(s.mixCurrentGroup, PedalSettings.mixGroups - 1) }
        else if s.mode == PedalMode.customKeyboard.rawValue { area = .keyboard; group = min(s.keyboardCurrentGroup, PedalSettings.keyboardGroups - 1) }
        else { area = .custom; group = min(s.customCurrentGroup, PedalSettings.customGroups - 1) }
    }

    var groupCount: Int {
        switch area {
        case .custom: return PedalSettings.customGroups
        case .mix: return PedalSettings.mixGroups
        case .keyboard: return PedalSettings.keyboardGroups
        }
    }

    func keyCombo(sw: Int) -> KeyCombo? {
        guard let s = settings else { return nil }
        return area == .keyboard ? s.keyboardKey(group: group, sw: sw) : s.mixSwitch(group: group, sw: sw).keyCombo
    }

    func setKeyCombo(sw: Int, _ k: KeyCombo) {
        if area == .keyboard { updateSettings { $0.setKeyboardKey(group: group, sw: sw, k) } }
        else { updateMix(sw: sw) { $0.keyCombo = k } }
    }

    func program(sw: Int) -> SwitchProgram? {
        guard let s = settings, area != .keyboard else { return nil }
        return area == .custom ? s.customSwitch(group: group, sw: sw) : s.mixSwitch(group: group, sw: sw).program
    }

    func updateProgram(sw: Int, _ change: (inout SwitchProgram) -> Void) {
        guard var s = settings else { return }
        if area == .custom {
            var p = s.customSwitch(group: group, sw: sw)
            change(&p)
            s.setCustomSwitch(group: group, sw: sw, p)
        } else {
            var m = s.mixSwitch(group: group, sw: sw)
            var p = m.program
            change(&p)
            m.program = p
            s.setMixSwitch(group: group, sw: sw, m)
        }
        settings = s
    }

    func mixSwitch(sw: Int) -> MixSwitch? { settings?.mixSwitch(group: group, sw: sw) }

    func updateMix(sw: Int, _ change: (inout MixSwitch) -> Void) {
        guard var s = settings else { return }
        var m = s.mixSwitch(group: group, sw: sw)
        change(&m)
        s.setMixSwitch(group: group, sw: sw, m)
        settings = s
    }

    func updateSettings(_ change: (inout PedalSettings) -> Void) {
        guard var s = settings else { return }
        change(&s)
        settings = s
    }

    /// Copies switch `from` onto switch `to` within the current group.
    func copySwitch(_ from: Int, to: Int) {
        guard let p = program(sw: from) else { return }
        updateProgram(sw: to) { $0 = p }
    }

    // MARK: Live monitor

    private func logLive(_ msg: [UInt8]) {
        guard let status = msg.first else { return }
        let ch = Int(status & 0x0F) + 1
        let d1 = msg.count > 1 ? Int(msg[1]) : 0, d2 = msg.count > 2 ? Int(msg[2]) : 0
        let text: String
        switch status & 0xF0 {
        case 0xB0: text = "CC \(d1) = \(d2) · ch \(ch)"
        case 0xC0: text = "PC \(d1) · ch \(ch)"
        case 0x90: text = d2 == 0 ? "Note Off \(MidiMessage.noteName(d1)) · ch \(ch)" : "Note On \(MidiMessage.noteName(d1)) vel \(d2) · ch \(ch)"
        case 0x80: text = "Note Off \(MidiMessage.noteName(d1)) · ch \(ch)"
        case 0xE0: text = "Pitch bend \(d1 | d2 << 7) · ch \(ch)"
        default: text = SysEx.hex(msg)
        }
        liveMessages.insert((Date(), text), at: 0)
        if liveMessages.count > 40 { liveMessages.removeLast(liveMessages.count - 40) }
    }

    /// Opens the port just to listen, without reading settings.
    func listen() {
        do { _ = try openSelected(); status = "Listening to \(selectedPortName ?? "the pedal"). Step on a switch." }
        catch { fail(AppError(wrapping: error)) }
    }

    // MARK: Errors

    func fail(_ e: AppError, alert: Bool = true) {
        lastError = e
        status = "\(e.code.summary) (\(e.code.rawValue))"
        ErrorReporter.shared.report(e, surface: alert ? .alert : .logOnly)
    }

    func confirm(_ title: String, _ text: String, ok: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}

// MARK: Hex text

enum Hex {
    /// "F0 7E 7F 06 01 F7" (spaces, commas or 0x optional) → bytes; nil if not valid hex.
    static func parse(_ s: String) -> [UInt8]? {
        let cleaned = s.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .components(separatedBy: CharacterSet(charactersIn: " ,\n\t")).filter { !$0.isEmpty }
        var out: [UInt8] = []
        for tok in cleaned {
            var t = Substring(tok)
            if t.count % 2 == 1 { t = "0" + t }
            while !t.isEmpty {
                guard let b = UInt8(t.prefix(2), radix: 16) else { return nil }
                out.append(b)
                t = t.dropFirst(2)
            }
        }
        return out
    }
    static func format(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }
}
