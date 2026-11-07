import Foundation

/// The Chocolate Plus settings block: 23,646 bytes of flash type 4, read and
/// written whole or in pieces. Offsets come from CubeSuite's FootCtrlPlusDlg
/// (see PROTOCOL.md). Every byte we don't understand is kept exactly as read,
/// so writing back never disturbs settings this editor can't show.
///
/// "Confirmed" fields were traced through CubeSuite's code. "Unverified" ones
/// are educated guesses until a capture proves them; the UI marks them.
struct PedalSettings: Equatable {
    static let size = 0x5C5E

    var bytes: [UInt8]

    init(bytes: [UInt8]) {
        precondition(bytes.count == Self.size, "settings must be \(Self.size) bytes")
        self.bytes = bytes
    }

    // MARK: Header (offsets 0x00–0x5C)

    /// Pedal mode, 0…11 (CubeSuite clamps to 11).
    var mode: Int {
        get { Int(bytes[0x00]) }
        set { bytes[0x00] = UInt8(clamping: newValue) }
    }
    /// 0x01: interface type radio button (unverified meaning).
    var interfaceType: UInt8 { get { bytes[0x01] } set { bytes[0x01] = newValue } }
    /// 0x02: MIDI channel for the simple modes, 0-based (shown +1).
    var midiChannel: Int {
        get { Int(bytes[0x02]) }
        set { bytes[0x02] = UInt8(clamping: max(0, min(15, newValue))) }
    }

    // MARK: Custom MIDI mode (mode 3): 8 groups × 4 switches, offset 0x5D

    static let customBase = 0x5D
    static let customGroupStride = 0x684
    static let switchStride = 0x1A1
    static let customGroups = 8

    // MARK: Mix Key mode (mode 11): 6 groups × 4 switches, offset 0x34C5

    static let mixBase = 0x34C5
    static let mixGroupStride = 0x698
    static let mixSwitchStride = 0x1A6
    static let mixGroups = 6

    // MARK: Tail (0x5C55–0x5C5D)

    /// 0x5C55/0x5C56/0x5C57: "Max Group Count" values (which mode each belongs to is unverified).
    var maxGroupCounts: [UInt8] { Array(bytes[0x5C55...0x5C57]) }
    func maxGroupCount(_ i: Int) -> Int { Int(bytes[0x5C55 + i]) }
    mutating func setMaxGroupCount(_ i: Int, _ v: Int) { bytes[0x5C55 + i] = UInt8(clamping: v) }

    /// 0x5C58: the custom-mode group the pedal is on.
    var customCurrentGroup: Int { get { Int(bytes[0x5C58]) } set { bytes[0x5C58] = UInt8(clamping: newValue) } }
    /// 0x5C5D: the mix-key group the pedal is on.
    var mixCurrentGroup: Int { get { Int(bytes[0x5C5D]) } set { bytes[0x5C5D] = UInt8(clamping: newValue) } }

    /// Offset of switch `sw` (0 = A … 3 = D) in `group`.
    static func customSwitchOffset(group: Int, sw: Int) -> Int {
        customBase + group * customGroupStride + sw * switchStride
    }
    static func mixSwitchOffset(group: Int, sw: Int) -> Int {
        mixBase + group * mixGroupStride + sw * mixSwitchStride
    }

    func customSwitch(group: Int, sw: Int) -> SwitchProgram {
        SwitchProgram(bytes: Array(bytes[Self.customSwitchOffset(group: group, sw: sw)..<(Self.customSwitchOffset(group: group, sw: sw) + Self.switchStride)]))
    }
    mutating func setCustomSwitch(group: Int, sw: Int, _ p: SwitchProgram) {
        let o = Self.customSwitchOffset(group: group, sw: sw)
        bytes.replaceSubrange(o..<(o + Self.switchStride), with: p.bytes)
    }

    func mixSwitch(group: Int, sw: Int) -> MixSwitch {
        let o = Self.mixSwitchOffset(group: group, sw: sw)
        return MixSwitch(bytes: Array(bytes[o..<(o + Self.mixSwitchStride)]))
    }
    mutating func setMixSwitch(group: Int, sw: Int, _ m: MixSwitch) {
        let o = Self.mixSwitchOffset(group: group, sw: sw)
        bytes.replaceSubrange(o..<(o + Self.mixSwitchStride), with: m.bytes)
    }
}

extension PedalSettings {
    /// Human name for a byte offset, for diffs and the raw view.
    static func describe(offset o: Int) -> String {
        let sw = ["A", "B", "C", "D"]
        func inSwitch(_ r: Int) -> String {
            switch r {
            case 0: return "stomp mode"
            case 1..<81: return "bank A msg \((r - 1) / 5 + 1) " + ["present", "channel", "type", "number", "value"][(r - 1) % 5]
            case 81..<161: return "bank B msg \((r - 81) / 5 + 1) " + ["present", "channel", "type", "number", "value"][(r - 81) % 5]
            case 161: return "bank A raw length"
            case 162..<289: return "bank A raw byte \(r - 161)"
            case 289: return "bank B raw length"
            default: return "bank B raw byte \(r - 289)"
            }
        }
        switch o {
        case 0x00: return "mode"
        case 0x01: return "interface type (unverified)"
        case 0x02: return "MIDI channel"
        case 0x03, 0x05, 0x07, 0x09: return "switch \(sw[(o - 3) / 2]) visual behaviour (unverified)"
        case 0x04, 0x06, 0x08, 0x0A: return "switch \(sw[(o - 4) / 2]) combo setting (unverified)"
        case 0x0D..<0x5D: return "interface list msg \((o - 0x0D) / 5 + 1) " + ["present", "channel", "type", "number", "value"][(o - 0x0D) % 5] + " (unverified)"
        case customBase..<keyboardBase:
            let r = o - customBase
            return "custom group \(r / customGroupStride + 1) switch \(sw[(r % customGroupStride) / switchStride]) " + inSwitch(r % switchStride)
        case keyboardBase..<mixBase:
            let r = o - keyboardBase
            return "keyboard group \(r / 12 + 1) switch \(sw[(r % 12) / 3]) " + ["modifier 1", "modifier 2", "key"][r % 3]
        case mixBase..<(mixBase + mixGroups * mixGroupStride):
            let r = o - mixBase, s = r % mixGroupStride % mixSwitchStride
            let head = "mix group \(r / mixGroupStride + 1) switch \(sw[(r % mixGroupStride) / mixSwitchStride]) "
            if s == 0 { return head + "function (0 MIDI, 1 key, 2 page turner)" }
            if s == 1 { return head + "page-turner key" }
            if s < 4 { return head + "key modifier \(s - 1)" }
            if s == 4 { return head + "key" }
            return head + inSwitch(s - 5)
        case 0x5C55: return "PC mode last group (31 = 128 programs)"
        case 0x5C56: return "CC mode last group (31)"
        case 0x5C57: return "custom mode group count (unverified)"
        case 0x5C58: return "custom current group"
        case 0x5C59: return "keyboard current group"
        case 0x5C5A...0x5C5C: return "checkbox \(o - 0x5C5A + 1) (unverified)"
        case 0x5C5D: return "mix current group"
        default: return "unknown"
        }
    }
}

/// What a footswitch does when stepped on. Values from CubeSuite's
/// "Select Stampede Mode" list, in order.
enum StompMode: Int, CaseIterable, Identifiable {
    case single = 0           // bank A every press
    case toggle = 1           // alternate bank A / bank B
    case pressRelease = 2     // A on press, B on release
    case repeating = 3        // hold: resend A at intervals
    case shortLong = 4        // short press A, long press B

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .single: return "Press"
        case .toggle: return "Toggle A ↔ B"
        case .pressRelease: return "Press A, release B"
        case .repeating: return "Hold to repeat"
        case .shortLong: return "Short A, long B"
        }
    }
    var explanation: String {
        switch self {
        case .single: return "Sends the A messages every time you press."
        case .toggle: return "Sends A, then B on the next press, and so on."
        case .pressRelease: return "Sends A when you press down and B when you lift."
        case .repeating: return "Keeps sending the A messages at intervals while held."
        case .shortLong: return "A quick press sends A; a long press sends B."
        }
    }
    var usesBankB: Bool { self == .toggle || self == .pressRelease || self == .shortLong }
}

/// One MIDI message slot: 5 bytes = present, channel (0-based), type, number, value.
struct MidiMessage: Equatable, Identifiable {
    enum Kind: UInt8, CaseIterable, Identifiable {
        case programChange = 0, controlChange = 1, noteOn = 2, noteOff = 3, custom = 4
        var id: UInt8 { rawValue }
        var title: String {
            switch self {
            case .programChange: return "PC"
            case .controlChange: return "CC"
            case .noteOn: return "Note On"
            case .noteOff: return "Note Off"
            case .custom: return "SysEx / raw"
            }
        }
    }

    var id = UUID()
    var channel: Int = 0          // 0…15
    var kind: Kind = .controlChange
    var number: Int = 0           // PC/CC/note number
    var value: Int = 127          // CC value / velocity

    static func == (a: MidiMessage, b: MidiMessage) -> Bool {
        a.channel == b.channel && a.kind == b.kind && a.number == b.number && a.value == b.value
    }

    init(channel: Int = 0, kind: Kind = .controlChange, number: Int = 0, value: Int = 127) {
        self.channel = channel; self.kind = kind; self.number = number; self.value = value
    }

    init?(slot b: ArraySlice<UInt8>) {
        let s = Array(b)
        guard s[0] != 0 else { return nil }
        channel = Int(s[1] & 0x0F)
        kind = Kind(rawValue: s[2]) ?? .controlChange
        number = Int(s[3])
        value = Int(s[4])
    }

    var slot: [UInt8] {
        [1, UInt8(channel & 0x0F), kind.rawValue, UInt8(clamping: number), UInt8(clamping: value)]
    }

    /// The bytes this sends, for display.
    var wireBytes: [UInt8] {
        let ch = UInt8(channel & 0x0F)
        switch kind {
        case .programChange: return [0xC0 | ch, UInt8(number & 0x7F)]
        case .controlChange: return [0xB0 | ch, UInt8(number & 0x7F), UInt8(value & 0x7F)]
        case .noteOn: return [0x90 | ch, UInt8(number & 0x7F), UInt8(value & 0x7F)]
        case .noteOff: return [0x80 | ch, UInt8(number & 0x7F), UInt8(value & 0x7F)]
        case .custom: return []
        }
    }

    var summary: String {
        switch kind {
        case .programChange: return "PC \(number) · ch \(channel + 1)"
        case .controlChange: return "CC \(number) = \(value) · ch \(channel + 1)"
        case .noteOn: return "Note On \(MidiMessage.noteName(number)) vel \(value) · ch \(channel + 1)"
        case .noteOff: return "Note Off \(MidiMessage.noteName(number)) · ch \(channel + 1)"
        case .custom: return "Raw bytes"
        }
    }

    static func noteName(_ n: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[((n % 12) + 12) % 12])\(n / 12 - 1)"
    }
}

/// One footswitch's program in custom mode: 417 bytes.
///   0        stomp mode
///   1…80     bank A: 16 × 5-byte message slots
///   81…160   bank B: 16 × 5-byte message slots
///   161…288  bank A raw bytes: length, then up to 127 bytes
///   289…416  bank B raw bytes
struct SwitchProgram: Equatable {
    static let slots = 16
    var bytes: [UInt8]

    var stompModeRaw: UInt8 { get { bytes[0] } set { bytes[0] = newValue } }
    var stompMode: StompMode? {
        get { StompMode(rawValue: Int(bytes[0])) }
        set { if let v = newValue { bytes[0] = UInt8(v.rawValue) } }
    }

    private static func bankOffset(_ bank: Int) -> Int { bank == 0 ? 1 : 81 }
    private static func rawOffset(_ bank: Int) -> Int { bank == 0 ? 161 : 289 }

    /// Messages in a bank (0 = A, 1 = B), skipping empty slots.
    func messages(bank: Int) -> [MidiMessage] {
        let o = Self.bankOffset(bank)
        return (0..<Self.slots).compactMap { MidiMessage(slot: bytes[(o + $0 * 5)..<(o + $0 * 5 + 5)]) }
    }

    /// Rewrites a bank's slots, packed from the start, the way CubeSuite does.
    /// A raw-bytes message has to be alone in its bank (CubeSuite's rule).
    mutating func setMessages(bank: Int, _ list: [MidiMessage]) {
        let o = Self.bankOffset(bank)
        for i in 0..<Self.slots {
            let slot: [UInt8] = i < list.count ? list[i].slot : [0, 0, 0, 0, 0]
            bytes.replaceSubrange((o + i * 5)..<(o + i * 5 + 5), with: slot)
        }
    }

    func rawBytes(bank: Int) -> [UInt8] {
        let o = Self.rawOffset(bank)
        let n = min(Int(bytes[o]), 127)
        return Array(bytes[(o + 1)..<(o + 1 + n)])
    }

    mutating func setRawBytes(bank: Int, _ raw: [UInt8]) {
        let o = Self.rawOffset(bank)
        let n = min(raw.count, 127)
        bytes[o] = UInt8(n)
        for i in 0..<127 { bytes[o + 1 + i] = i < n ? raw[i] : 0 }
    }
}

/// One footswitch in Mix Key mode: 422 bytes = 5-byte header + a SwitchProgram.
///   0     what the switch does: 0 custom MIDI, 1 keyboard key, 2 page turner (radio order)
///   1     page-turner key (PedalKeys.turnerNames)
///   2…4   keyboard: modifier 1, modifier 2, key (see Keys.swift)
///   5…    same layout as SwitchProgram
struct MixSwitch: Equatable {
    var bytes: [UInt8]
    var function: UInt8 { get { bytes[0] } set { bytes[0] = newValue } }
    var keyBytes: [UInt8] { Array(bytes[1...4]) }
    var program: SwitchProgram {
        get { SwitchProgram(bytes: Array(bytes[5...])) }
        set { bytes.replaceSubrange(5..., with: newValue.bytes) }
    }
}

/// Pedal modes in CubeSuite's order (index = byte 0x00). Names from its
/// mode list and explanations.
enum PedalMode: Int, CaseIterable, Identifiable {
    case programChange = 0, controlChange, simpleCustom, customMIDI, manufacturer,
         touchScreen, video, keyboardArrows, keyboardPages, multimedia, customKeyboard, mixKey

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .programChange: return "Program Change"
        case .controlChange: return "Control Change"
        case .simpleCustom: return "Custom (simple)"
        case .customMIDI: return "Custom MIDI (advanced)"
        case .manufacturer: return "Manufacturer control"
        case .touchScreen: return "Touch screen (Android)"
        case .video: return "Video"
        case .keyboardArrows: return "Keyboard: arrows"
        case .keyboardPages: return "Keyboard: page turner"
        case .multimedia: return "Multimedia keys"
        case .customKeyboard: return "Custom keyboard"
        case .mixKey: return "Mix Key"
        }
    }
    var explanation: String {
        switch self {
        case .programChange: return "A–D send Program Changes; the E/F combos flip through groups (128 in all)."
        case .controlChange: return "A–D send CCs; the E/F combos flip through groups."
        case .simpleCustom: return "Custom MIDI CC and some common MIDI messages."
        case .customMIDI: return "Full control: per-switch message lists, stomp modes and groups. E/F combos change group."
        case .manufacturer: return "Controls the maker's own devices. See that device's manual."
        case .touchScreen: return "A swipe up · B swipe down · C swipe left · D swipe right."
        case .video: return "A rewind · B fast forward · C play/pause · D loop (YouTube in Chrome, with M-VAVE's extension)."
        case .keyboardArrows: return "A ↑ · B ↓ · C ← · D →."
        case .keyboardPages: return "A Page Up · B Page Down · C Space · D Enter."
        case .multimedia: return "A previous track · B next track · C volume − · D volume +."
        case .customKeyboard: return "Each switch types a key you choose; E/F combos change group."
        case .mixKey: return "Each switch is custom MIDI, a custom key, or the tuner; E/F combos change group."
        }
    }
    /// Modes this editor can edit in full. Others are shown, selectable, and preserved.
    var hasEditor: Bool { self == .customMIDI || self == .mixKey }
}
