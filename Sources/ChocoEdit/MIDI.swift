import CoreMIDI
import Foundation

/// A MIDI endpoint pair as CoreMIDI shows it.
struct MIDIPortInfo: Hashable, Identifiable {
    let name: String
    let source: MIDIEndpointRef
    let destination: MIDIEndpointRef
    var id: String { name }

    /// Names the Chocolate Plus has been seen under (USB and Bluetooth), plus
    /// CubeSuite's internal name for it.
    var looksLikeChocolate: Bool {
        let n = name.lowercased()
        // Over USB the Chocolate Plus shows up as "SINCO" (its maker, Zhuhai Sinco).
        return ["sinco", "chocolate", "footctrl", "m-vave", "mvave", "cuvave"].contains { n.contains($0) }
    }
}

/// Thin CoreMIDI wrapper: lists ports, sends SysEx, and hands back complete
/// SysEx messages (F0 … F7) received from the open source. Everything else the
/// pedal sends (CC, PC, notes when you step on it) is passed to `onOtherMessage`.
final class MIDIConnection {
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private(set) var current: MIDIPortInfo?

    private let lock = NSCondition()
    private var inbox: [[UInt8]] = []
    private var partial: [UInt8]? = nil

    var onOtherMessage: (([UInt8]) -> Void)?
    var onSetupChanged: (() -> Void)?

    init() throws {
        var status = MIDIClientCreateWithBlock("ChocoEdit" as CFString, &client) { [weak self] note in
            if note.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.onSetupChanged?() }
            }
        }
        guard status == noErr else { throw AppError(.midiUnavailable, "MIDIClientCreate \(status)") }
        status = MIDIOutputPortCreate(client, "ChocoEdit out" as CFString, &outPort)
        guard status == noErr else { throw AppError(.midiUnavailable, "MIDIOutputPortCreate \(status)") }
        status = MIDIInputPortCreateWithBlock(client, "ChocoEdit in" as CFString, &inPort) { [weak self] list, _ in
            self?.receive(list)
        }
        guard status == noErr else { throw AppError(.midiUnavailable, "MIDIInputPortCreate \(status)") }
    }

    deinit {
        MIDIPortDispose(inPort)
        MIDIPortDispose(outPort)
        MIDIClientDispose(client)
    }

    static func endpointName(_ e: MIDIEndpointRef) -> String {
        var cf: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        if MIDIObjectGetStringProperty(e, kMIDIPropertyName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        return "Unnamed port"
    }

    /// Ports that have both an input and an output with the same name.
    static func ports() -> [MIDIPortInfo] {
        var sources: [String: MIDIEndpointRef] = [:]
        for i in 0..<MIDIGetNumberOfSources() {
            let e = MIDIGetSource(i)
            sources[endpointName(e)] = e
        }
        var out: [MIDIPortInfo] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let d = MIDIGetDestination(i)
            let name = endpointName(d)
            if let s = sources[name] { out.append(MIDIPortInfo(name: name, source: s, destination: d)) }
        }
        return out.sorted { ($0.looksLikeChocolate ? 0 : 1, $0.name) < ($1.looksLikeChocolate ? 0 : 1, $1.name) }
    }

    func open(_ port: MIDIPortInfo) throws {
        close()
        let status = MIDIPortConnectSource(inPort, port.source, nil)
        guard status == noErr else { throw AppError(.portOpenFailed, "\(port.name): MIDIPortConnectSource \(status)") }
        current = port
        clearInbox()
    }

    func close() {
        if let c = current { MIDIPortDisconnectSource(inPort, c.source) }
        current = nil
    }

    func clearInbox() {
        lock.lock(); inbox.removeAll(); partial = nil; lock.unlock()
    }

    func send(_ bytes: [UInt8]) throws {
        guard let c = current else { throw AppError(.notConnected) }
        let size = bytes.count + 256
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        let list = buffer.assumingMemoryBound(to: MIDIPacketList.self)
        var pkt = MIDIPacketListInit(list)
        pkt = MIDIPacketListAdd(list, size, pkt, 0, bytes.count, bytes)
        let status = MIDISend(outPort, c.destination, list)
        guard status == noErr else { throw AppError(.sendFailed, "MIDISend \(status)") }
    }

    /// Waits for the next complete SysEx message.
    func nextSysEx(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        lock.lock()
        defer { lock.unlock() }
        while inbox.isEmpty {
            if !lock.wait(until: deadline) { return nil }
        }
        return inbox.removeFirst()
    }

    private func receive(_ list: UnsafePointer<MIDIPacketList>) {
        var others: [[UInt8]] = []
        lock.lock()
        for packet in list.unsafeSequence() {
            let bytes = withUnsafeBytes(of: packet.pointee.data) { raw in
                Array(raw.prefix(Int(packet.pointee.length)))
            }
            var i = 0
            while i < bytes.count {
                let b = bytes[i]
                if b >= 0xF8 { i += 1; continue }               // real-time bytes can appear anywhere
                if b == 0xF0 { partial = [0xF0]; i += 1; continue }
                if var p = partial {
                    if b == 0xF7 {
                        p.append(b); inbox.append(p); partial = nil
                    } else if b & 0x80 != 0 {
                        partial = nil                            // aborted SysEx; reprocess this status byte
                        continue
                    } else {
                        p.append(b); partial = p
                    }
                    i += 1
                    continue
                }
                // A channel message: status + 1 or 2 data bytes.
                if b & 0x80 != 0 {
                    let n = (b & 0xF0 == 0xC0 || b & 0xF0 == 0xD0) ? 2 : 3
                    others.append(Array(bytes[i..<min(i + n, bytes.count)]))
                    i += n
                } else {
                    i += 1                                       // running status: ignore
                }
            }
        }
        if !inbox.isEmpty { lock.broadcast() }
        lock.unlock()
        if let cb = onOtherMessage { for m in others { cb(m) } }
    }
}
