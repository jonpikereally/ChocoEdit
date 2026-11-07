import Foundation

/// The wire protocol CubeSuite uses with M-VAVE pedals, worked out from
/// CubeSuite's own code (CUSBConnect / CMIDITranfer). See PROTOCOL.md.
///
/// A protocol packet is
///     00 59 | cmd | len (3 bytes, little-endian) | payload (len bytes) | checksum
/// where checksum = ~(sum of payload bytes) & 0xFF. On the wire the whole
/// packet is treated as one little-endian bit stream and cut into 7-bit groups,
/// least significant first, each in its own byte, between F0 and F7.
enum SysEx {
    static let head: [UInt8] = [0x00, 0x59]

    enum Command: UInt8 {
        case response = 0x00     // device's answer to a write: payload[0] = status (0 = OK)
        case query = 0x11        // device name + firmware version
        case flashWrite = 0x22   // payload: type, addr(4), len(3), data
        case flashRead = 0x23    // request payload: type, addr(4), len(3); reply adds the data
    }

    /// The pedal's settings live in flash "type 4" (CubeSuite's EFlashType).
    static let settingsFlash: UInt8 = 4

    // MARK: 7-bit packing

    /// Bytes → F0 … F7, packing 8-bit bytes into 7-bit groups LSB-first.
    static func wrap(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0xF0]
        out.reserveCapacity(bytes.count * 8 / 7 + 3)
        var acc: UInt32 = 0
        var bits = 0
        for b in bytes {
            acc |= UInt32(b) << UInt32(bits)
            bits += 8
            while bits >= 7 {
                out.append(UInt8(acc & 0x7F))
                acc >>= 7
                bits -= 7
            }
        }
        if bits > 0 { out.append(UInt8(acc & 0x7F)) }
        out.append(0xF7)
        return out
    }

    /// F0 … F7 (or just the 7-bit body) → bytes. Leftover bits that don't
    /// make a whole byte are padding and dropped.
    static func unwrap(_ sysex: [UInt8]) -> [UInt8] {
        var body = sysex[...]
        if body.first == 0xF0 { body = body.dropFirst() }
        if body.last == 0xF7 { body = body.dropLast() }
        var out: [UInt8] = []
        out.reserveCapacity(body.count * 7 / 8)
        var acc: UInt32 = 0
        var bits = 0
        for b in body {
            acc |= UInt32(b & 0x7F) << UInt32(bits)
            bits += 7
            if bits >= 8 {
                out.append(UInt8(acc & 0xFF))
                acc >>= 8
                bits -= 8
            }
        }
        return out
    }

    // MARK: Packets

    static func checksum<C: Collection>(_ payload: C) -> UInt8 where C.Element == UInt8 {
        var sum: UInt8 = 0
        for b in payload { sum = sum &+ b }
        return ~sum
    }

    static func le(_ v: UInt32, _ count: Int) -> [UInt8] {
        (0..<count).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) }
    }

    static func readLE(_ b: [UInt8], _ at: Int, _ count: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<count { v |= UInt32(b[at + i]) << (8 * UInt32(i)) }
        return v
    }

    /// The raw (unwrapped) packet.
    static func packet(_ cmd: Command, _ payload: [UInt8]) -> [UInt8] {
        head + [cmd.rawValue] + le(UInt32(payload.count), 3) + payload + [checksum(payload)]
    }

    static func queryPacket() -> [UInt8] { packet(.query, []) }

    static func readPacket(type: UInt8, address: UInt32, length: Int) -> [UInt8] {
        packet(.flashRead, [type] + le(address, 4) + le(UInt32(length), 3))
    }

    static func writePacket(type: UInt8, address: UInt32, data: [UInt8]) -> [UInt8] {
        packet(.flashWrite, [type] + le(address, 4) + le(UInt32(data.count), 3) + data)
    }

    // MARK: Replies

    struct Reply {
        let command: UInt8
        let payload: [UInt8]
    }

    enum ParseError: Error, CustomStringConvertible {
        case tooShort(Int)
        case badHeader([UInt8])
        case badLength(declared: Int, got: Int)
        case badChecksum(calc: UInt8, got: UInt8)

        var description: String {
            switch self {
            case .tooShort(let n): return "reply only \(n) bytes long"
            case .badHeader(let h): return "reply header \(hex(h)), expected 00 59"
            case .badLength(let d, let g): return "reply says \(d) payload bytes but carries \(g)"
            case .badChecksum(let c, let g): return String(format: "reply checksum %02X, calculated %02X", g, c)
            }
        }
    }

    /// Parses an unwrapped reply packet.
    static func parse(_ raw: [UInt8]) throws -> Reply {
        guard raw.count >= 7 else { throw ParseError.tooShort(raw.count) }
        guard raw[0] == head[0], raw[1] == head[1] else { throw ParseError.badHeader(Array(raw.prefix(2))) }
        let len = Int(readLE(raw, 3, 3))
        guard raw.count >= 6 + len + 1 else { throw ParseError.badLength(declared: len, got: raw.count - 7) }
        let payload = Array(raw[6..<(6 + len)])
        let calc = checksum(payload)
        guard calc == raw[6 + len] else { throw ParseError.badChecksum(calc: calc, got: raw[6 + len]) }
        return Reply(command: raw[2], payload: payload)
    }

    static func hex<C: Collection>(_ bytes: C, limit: Int = 64) -> String where C.Element == UInt8 {
        let shown = bytes.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
        return bytes.count > limit ? shown + " … (\(bytes.count) bytes)" : shown
    }
}
