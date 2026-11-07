import Foundation

// chocoprobe — command-line companion to ChocoEdit for testing the protocol
// against a real Chocolate Plus and for working out unverified settings.
//
//   chocoprobe list                     MIDI ports
//   chocoprobe id                       ask the pedal its name and version
//   chocoprobe dump <file>              read all settings into a file
//   chocoprobe show <file>              decode a settings file
//   chocoprobe diff <old> <new>         list changed bytes with their meaning
//   chocoprobe write <file> --yes       back up, then write the changes and verify
//
// Options: --port <name part>  --chunk <bytes>  --verbose

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
let portName = option("--port")
let chunk = option("--chunk").flatMap(Int.init)
let verbose = flag("--verbose")
let yes = flag("--yes")

func die(_ e: Error) -> Never {
    let err = AppError(wrapping: e)
    FileHandle.standardError.write(("\nError \(err.code.rawValue): \(err.code.summary)\n"
        + (err.detail.map { "  \($0)\n" } ?? "")
        + "  \(err.code.hint)\n  Error list: \(ErrorReporter.helpURL)\n").data(using: .utf8)!)
    exit(1)
}

func loadFile(_ path: String) -> PedalSettings {
    guard let d = FileManager.default.contents(atPath: path) else { die(AppError(.fileReadFailed, path)) }
    guard d.count == PedalSettings.size else { die(AppError(.fileWrongSize, "\(path) is \(d.count) bytes, expected \(PedalSettings.size)")) }
    return PedalSettings(bytes: [UInt8](d))
}

func connect() -> (MIDIConnection, Pedal) {
    do {
        let midi = try MIDIConnection()
        let ports = MIDIConnection.ports()
        let port: MIDIPortInfo?
        if let want = portName?.lowercased() {
            port = ports.first { $0.name.lowercased().contains(want) }
        } else {
            port = ports.first { $0.looksLikeChocolate }
        }
        guard let p = port else {
            throw AppError(.noPedal, "ports seen: " + (ports.isEmpty ? "none" : ports.map(\.name).joined(separator: ", ")))
        }
        try midi.open(p)
        let pedal = Pedal(midi)
        if let c = chunk { pedal.chunk = c }
        if verbose { pedal.trace = { print($0) } }
        print("Port: \(p.name)")
        return (midi, pedal)
    } catch { die(error) }
}

func progressBar(_ label: String) -> (Double) -> Void {
    var last = -1
    return { f in
        let pct = Int(f * 100)
        if pct != last { last = pct; print("\r\(label) \(pct)%", terminator: pct == 100 ? "\n" : ""); fflush(stdout) }
    }
}

func show(_ s: PedalSettings) {
    let mode = PedalMode(rawValue: s.mode)
    print("Mode: \(s.mode) \(mode?.title ?? "(unknown)")")
    print("MIDI channel: \(s.midiChannel + 1)")
    print("Max group counts (unverified): \(s.maxGroupCounts.map(String.init).joined(separator: ", "))")
    print("Custom current group: \(s.customCurrentGroup + 1), mix current group: \(s.mixCurrentGroup + 1)")
    print(String(format: "Header 0x00–0x0C: %@", SysEx.hex(s.bytes[0..<0x0D])))
    print(String(format: "Tail 0x5C55–0x5C5D: %@", SysEx.hex(s.bytes[0x5C55...0x5C5D])))
    print("\nCustom MIDI groups:")
    for g in 0..<PedalSettings.customGroups {
        var lines: [String] = []
        for sw in 0..<4 {
            let p = s.customSwitch(group: g, sw: sw)
            let a = p.messages(bank: 0), b = p.messages(bank: 1)
            if a.isEmpty && b.isEmpty && p.stompModeRaw == 0 { continue }
            var line = "  \(["A", "B", "C", "D"][sw]): \(p.stompMode?.title ?? "stomp \(p.stompModeRaw)")"
            if !a.isEmpty { line += " | A: " + a.map { $0.kind == .custom ? "raw[\(SysEx.hex(p.rawBytes(bank: 0)))]" : $0.summary }.joined(separator: "; ") }
            if !b.isEmpty { line += " | B: " + b.map { $0.kind == .custom ? "raw[\(SysEx.hex(p.rawBytes(bank: 1)))]" : $0.summary }.joined(separator: "; ") }
            lines.append(line)
        }
        if !lines.isEmpty { print(" Group \(g + 1)"); lines.forEach { print($0) } }
    }
    print("\nMix Key groups:")
    for g in 0..<PedalSettings.mixGroups {
        var lines: [String] = []
        for sw in 0..<4 {
            let m = s.mixSwitch(group: g, sw: sw)
            let a = m.program.messages(bank: 0)
            if a.isEmpty && m.keyBytes.allSatisfy({ $0 == 0 }) && m.function == 0 { continue }
            lines.append("  \(["A", "B", "C", "D"][sw]): function \(m.function), keys \(SysEx.hex(m.keyBytes)), A: "
                + a.map(\.summary).joined(separator: "; "))
        }
        if !lines.isEmpty { print(" Group \(g + 1)"); lines.forEach { print($0) } }
    }
}

guard let cmd = args.first else {
    print("usage: chocoprobe list | id | dump <file> | show <file> | diff <old> <new> | write <file> --yes  [--port name] [--chunk n] [--verbose]")
    exit(2)
}

switch cmd {
case "list":
    do { _ = try MIDIConnection() } catch { die(error) }
    let ports = MIDIConnection.ports()
    if ports.isEmpty { print("No MIDI ports with both an input and an output.") }
    for p in ports { print((p.looksLikeChocolate ? "* " : "  ") + p.name) }

case "id":
    let (_, pedal) = connect()
    do {
        let id = try pedal.identify()
        print("Name: \(id.name)\nVersion bytes: \(id.version)\nRaw: \(SysEx.hex(id.raw))")
        if id.name != "FootCtrlPlus" { print("Note: CubeSuite opens its Chocolate Plus editor for the name FootCtrlPlus.") }
    } catch { die(error) }

case "dump":
    guard args.count >= 2 else { print("usage: chocoprobe dump <file>"); exit(2) }
    let (_, pedal) = connect()
    do {
        let id = try pedal.identify()
        print("Pedal: \(id.name)")
        let start = Date()
        let bytes = try pedal.read(length: PedalSettings.size, progress: progressBar("Reading"))
        try Data(bytes).write(to: URL(fileURLWithPath: args[1]))
        print(String(format: "Saved %d bytes to %@ in %.1fs", bytes.count, args[1], Date().timeIntervalSince(start)))
        show(PedalSettings(bytes: bytes))
    } catch { die(error) }

case "show":
    guard args.count >= 2 else { print("usage: chocoprobe show <file>"); exit(2) }
    show(loadFile(args[1]))

case "diff":
    guard args.count >= 3 else { print("usage: chocoprobe diff <old> <new>"); exit(2) }
    let a = loadFile(args[1]), b = loadFile(args[2])
    var n = 0
    for i in 0..<PedalSettings.size where a.bytes[i] != b.bytes[i] {
        n += 1
        print(String(format: "0x%04X  %3d → %3d  (%02X → %02X)  %@", i, a.bytes[i], b.bytes[i], a.bytes[i], b.bytes[i],
                     PedalSettings.describe(offset: i)))
    }
    print(n == 0 ? "Identical." : "\(n) bytes differ.")

case "write":
    guard args.count >= 2 else { print("usage: chocoprobe write <file> --yes"); exit(2) }
    let target = loadFile(args[1])
    let (_, pedal) = connect()
    do {
        let id = try pedal.identify()
        guard id.name == "FootCtrlPlus" else { throw AppError(.wrongDevice, "pedal calls itself \(id.name)") }
        let current = try pedal.read(length: PedalSettings.size, progress: progressBar("Reading current"))
        let ranges = Pedal.diffRanges(current, target.bytes)
        let total = ranges.reduce(0) { $0 + $1.count }
        if total == 0 { print("Pedal already matches \(args[1]). Nothing to write."); exit(0) }
        let backup = URL(fileURLWithPath: args[1]).deletingLastPathComponent()
            .appendingPathComponent("backup-before-write-\(Int(Date().timeIntervalSince1970)).chocoplus")
        do { try Data(current).write(to: backup) } catch { throw AppError(.backupFailed, "\(backup.path): \(error.localizedDescription)") }
        print("Backup of the pedal's current settings: \(backup.path)")
        print("\(total) bytes in \(ranges.count) range(s) will change:")
        for r in ranges.prefix(20) { print(String(format: "  0x%04X–0x%04X  %@", r.lowerBound, r.upperBound - 1, PedalSettings.describe(offset: r.lowerBound))) }
        guard yes else { print("Dry run. Add --yes to write."); exit(0) }
        try pedal.writeChanges(from: current, to: target.bytes, progress: progressBar("Writing + verifying"))
        print("Written and verified.")
    } catch { die(error) }

default:
    print("unknown command \(cmd)")
    exit(2)
}
