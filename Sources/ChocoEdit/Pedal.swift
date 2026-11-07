import Foundation

/// Talks to a Chocolate Plus over an open MIDIConnection. Every call blocks,
/// so run them off the main thread.
/// What Pedal needs from a MIDI connection; tests swap in a fake pedal.
protocol PedalTransport: AnyObject {
    func clearInbox()
    func send(_ bytes: [UInt8]) throws
    func nextSysEx(timeout: TimeInterval) -> [UInt8]?
}

extension MIDIConnection: PedalTransport {}

final class Pedal {
    let midi: PedalTransport
    /// Bytes of settings per read/write packet. CubeSuite uses the device's
    /// packet size minus 15 (113, 497 or 1009 depending on the chip); 113 is
    /// the smallest and works on all of them.
    var chunk = 113
    var timeout: TimeInterval = 2.0
    var retries = 2
    /// Called with every raw packet sent/received when set (probe --verbose).
    var trace: ((String) -> Void)?

    init(_ midi: PedalTransport) { self.midi = midi }

    struct Identity {
        let name: String
        let version: String
        let raw: [UInt8]
    }

    private func exchange(_ packet: [UInt8], expect: SysEx.Command) throws -> SysEx.Reply {
        var lastError: AppError = AppError(.noReply)
        var heardEcho = false
        for attempt in 0...retries {
            midi.clearInbox()
            trace?("→ \(SysEx.hex(packet))")
            try midi.send(SysEx.wrap(packet))
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                let left = deadline.timeIntervalSinceNow
                guard left > 0, let msg = midi.nextSysEx(timeout: left) else {
                    lastError = heardEcho
                        ? AppError(.echoPort, "the port sent back exactly what ChocoEdit sent and nothing else")
                        : AppError(.noReply, "no answer to command \(String(format: "%02X", packet[2])) within \(timeout)s (try \(attempt + 1))")
                    break
                }
                let raw = SysEx.unwrap(msg)
                trace?("← \(SysEx.hex(raw))")
                // A loopback port (an IAC bus, or a MIDI thru) hands our own
                // request straight back. It's never the pedal's answer.
                if raw == packet { heardEcho = true; continue }
                guard raw.count >= 3, raw[0] == 0x00, raw[1] == 0x59 else { continue } // someone else's SysEx
                do {
                    let reply = try SysEx.parse(raw)
                    guard reply.command == expect.rawValue else {
                        lastError = AppError(.badReply, String(format: "expected command %02X, got %02X", expect.rawValue, reply.command))
                        break
                    }
                    return reply
                } catch {
                    lastError = AppError(.badReply, "\(error)")
                    break
                }
            }
        }
        throw lastError
    }

    func identify() throws -> Identity {
        let r = try exchange(SysEx.queryPacket(), expect: .query)
        let p = r.payload
        // A real Chocolate Plus answers "FootCtrlPlus_016": model name, then
        // the firmware version after the underscore (seen 2026-11-07).
        let nameBytes = p.prefix(16).prefix { $0 != 0 }
        let full = String(decoding: nameBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        let parts = full.split(separator: "_", maxSplits: 1).map(String.init)
        let name = parts.first ?? full
        var version = parts.count > 1 ? parts[1] : ""
        if version.count == 3, version.allSatisfy(\.isNumber) { version = version.map(String.init).joined(separator: ".") }
        return Identity(name: name, version: version, raw: p)
    }

    /// Reads `length` bytes of settings starting at `address`.
    func read(address: Int = 0, length: Int, progress: ((Double) -> Void)? = nil) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(length)
        var addr = address
        while out.count < length {
            let n = min(chunk, length - out.count)
            let r = try exchange(SysEx.readPacket(type: SysEx.settingsFlash, address: UInt32(addr), length: n), expect: .flashRead)
            let p = r.payload
            guard p.count >= 8 else { throw AppError(.badReply, "read reply only \(p.count) bytes") }
            let type = p[0], gotAddr = Int(SysEx.readLE(p, 1, 4)), gotLen = Int(SysEx.readLE(p, 5, 3))
            guard type == SysEx.settingsFlash, gotAddr == addr, gotLen == n, p.count == 8 + n else {
                throw AppError(.badReply, "asked for \(n) bytes at \(addr), got type \(type), \(gotLen) bytes at \(gotAddr) (\(p.count - 8) carried)")
            }
            out += p[8...]
            addr += n
            progress?(Double(out.count) / Double(length))
        }
        return out
    }

    /// Writes bytes to the settings at `address`.
    func write(address: Int, bytes: [UInt8], progress: ((Double) -> Void)? = nil) throws {
        var done = 0
        while done < bytes.count {
            let n = min(chunk, bytes.count - done)
            let slice = Array(bytes[done..<(done + n)])
            let r = try exchange(SysEx.writePacket(type: SysEx.settingsFlash, address: UInt32(address + done), data: slice), expect: .response)
            guard let status = r.payload.first else { throw AppError(.badReply, "empty write reply") }
            guard status == 0 else { throw AppError(.writeRejected, "pedal answered status \(status) for \(n) bytes at \(address + done)") }
            done += n
            progress?(Double(done) / Double(bytes.count))
        }
    }

    /// Writes only the byte ranges that differ, then reads them back to check.
    /// Returns the number of bytes written.
    @discardableResult
    func writeChanges(from old: [UInt8], to new: [UInt8], progress: ((Double) -> Void)? = nil) throws -> Int {
        precondition(old.count == new.count)
        let ranges = Self.diffRanges(old, new)
        let total = ranges.reduce(0) { $0 + $1.count }
        guard total > 0 else { return 0 }
        var done = 0
        for r in ranges {
            try write(address: r.lowerBound, bytes: Array(new[r])) { f in
                progress?((Double(done) + f * Double(r.count)) / Double(total) * 0.5)
            }
            done += r.count
        }
        done = 0
        for r in ranges {
            let back = try read(address: r.lowerBound, length: r.count) { f in
                progress?(0.5 + (Double(done) + f * Double(r.count)) / Double(total) * 0.5)
            }
            guard back == Array(new[r]) else {
                let i = zip(back, new[r]).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? 0
                throw AppError(.verifyFailed, "byte \(r.lowerBound + i) reads back as \(back[i]), wrote \(new[r.lowerBound + i])")
            }
            done += r.count
        }
        return total
    }

    /// Changed byte ranges, merging gaps shorter than 16 bytes so we don't
    /// send hundreds of tiny packets.
    static func diffRanges(_ a: [UInt8], _ b: [UInt8], mergeGap: Int = 16) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        while i < a.count {
            if a[i] == b[i] { i += 1; continue }
            var j = i + 1
            var lastDiff = i
            while j < a.count && j - lastDiff <= mergeGap {
                if a[j] != b[j] { lastDiff = j }
                j += 1
            }
            out.append(i..<(lastDiff + 1))
            i = lastDiff + 1
        }
        return out
    }
}
