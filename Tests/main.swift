import Foundation

// Offline tests: the SysEx codec, packet builders, settings layout, and the
// Pedal read/write logic against an in-memory fake pedal that answers the way
// CubeSuite's code expects a real one to.

var failures = 0
var passes = 0
func check(_ ok: Bool, _ what: String, file: String = #file, line: Int = #line) {
    if ok { passes += 1 } else { failures += 1; print("FAIL line \(line): \(what)") }
}

// MARK: Codec

// Worked example from the Looper Pro protocol notes (same CubeSuite family).
check(SysEx.wrap([0x12, 0x34, 0xAB, 0xCD]) == [0xF0, 0x12, 0x68, 0x2C, 0x6D, 0x0C, 0xF7], "wrap matches the documented example")
check(SysEx.unwrap([0xF0, 0x12, 0x68, 0x2C, 0x6D, 0x0C, 0xF7]) == [0x12, 0x34, 0xAB, 0xCD], "unwrap matches the documented example")
var rng = SystemRandomNumberGenerator()
for n in [0, 1, 6, 7, 8, 13, 14, 15, 113, 128, 1009] {
    let data = (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
    let w = SysEx.wrap(data)
    check(w.first == 0xF0 && w.last == 0xF7 && w.dropFirst().dropLast().allSatisfy { $0 < 0x80 }, "wrap(\(n)) is valid SysEx")
    check(SysEx.unwrap(w) == data, "round trip \(n) bytes")
}

// MARK: Packets

check(SysEx.queryPacket() == [0x00, 0x59, 0x11, 0, 0, 0, 0xFF], "query packet (CubeSuite builds 00 59 11 000000 FF)")
let rp = SysEx.readPacket(type: 4, address: 0x0102, length: 113)
check(Array(rp.prefix(6)) == [0x00, 0x59, 0x23, 8, 0, 0], "read packet header")
check(Array(rp[6..<14]) == [4, 0x02, 0x01, 0, 0, 113, 0, 0], "read packet payload")
check(rp[14] == SysEx.checksum(rp[6..<14]), "read packet checksum")
let wp = SysEx.writePacket(type: 4, address: 5, data: [1, 2, 3])
check(Array(wp.prefix(6)) == [0x00, 0x59, 0x22, 11, 0, 0], "write packet header")
check(Array(wp[6..<17]) == [4, 5, 0, 0, 0, 3, 0, 0, 1, 2, 3], "write packet payload")
do {
    _ = try SysEx.parse([0x00, 0x59, 0x00, 1, 0, 0, 0, 0x00])
    check(false, "bad checksum should throw")
} catch { check(true, "bad checksum throws") }
check((try? SysEx.parse([0x00, 0x59, 0x00, 1, 0, 0, 0, 0xFF]))?.payload == [0], "parses a good write reply")

// MARK: Layout

check(PedalSettings.customSwitchOffset(group: 7, sw: 3) + PedalSettings.switchStride == PedalSettings.customBase + 0x3420,
      "custom region ends where CubeSuite's 0x3420-byte write ends")
check(PedalSettings.customBase + 0x3420 <= PedalSettings.mixBase, "custom and mix regions don't overlap")
check(PedalSettings.mixSwitchOffset(group: 5, sw: 3) + PedalSettings.mixSwitchStride <= 0x5C55, "mix region fits before the tail")
check(PedalSettings.customGroupStride == 4 * PedalSettings.switchStride, "4 switches per custom group")
check(PedalSettings.mixGroupStride == 4 * PedalSettings.mixSwitchStride, "4 switches per mix group")

var settings = PedalSettings(bytes: [UInt8](repeating: 0, count: PedalSettings.size))
var prog = settings.customSwitch(group: 2, sw: 1)
prog.stompMode = .toggle
let msgs = [MidiMessage(channel: 0, kind: .controlChange, number: 64, value: 127),
            MidiMessage(channel: 9, kind: .programChange, number: 5, value: 0)]
prog.setMessages(bank: 0, msgs)
prog.setMessages(bank: 1, [MidiMessage(channel: 0, kind: .controlChange, number: 64, value: 0)])
prog.setRawBytes(bank: 0, [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])
settings.setCustomSwitch(group: 2, sw: 1, prog)
let back = settings.customSwitch(group: 2, sw: 1)
check(back.stompMode == .toggle, "stomp mode round trip")
check(back.messages(bank: 0) == msgs, "bank A round trip")
check(back.messages(bank: 1).first?.value == 0, "bank B round trip")
check(back.rawBytes(bank: 0) == [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7], "raw bytes round trip")
let o = PedalSettings.customSwitchOffset(group: 2, sw: 1)
check(Array(settings.bytes[(o + 1)..<(o + 6)]) == [1, 0, 1, 64, 127], "slot bytes: present, channel, type, number, value")
check(settings.bytes[o + 161] == 6, "raw length byte")
check(settings.customSwitch(group: 2, sw: 0).bytes.allSatisfy { $0 == 0 }, "neighbour switch untouched")

var mix = settings.mixSwitch(group: 1, sw: 2)
mix.function = 2
var mp = mix.program
mp.setMessages(bank: 0, [MidiMessage(kind: .noteOn, number: 60, value: 100)])
mix.program = mp
settings.setMixSwitch(group: 1, sw: 2, mix)
check(settings.mixSwitch(group: 1, sw: 2).program.messages(bank: 0).first?.kind == .noteOn, "mix switch program round trip")
check(settings.bytes[PedalSettings.mixSwitchOffset(group: 1, sw: 2) + 5 + 1] == 1, "mix slot starts after the 5-byte header")

// MARK: Keyboard keys (decoded from CubeSuite's key menu)

check(PedalKeys.names.count == 63, "63 key names (none + 62 keys)")
check(PedalKeys.names[1] == "A" && PedalKeys.names[26] == "Z", "letters at 1–26")
check(PedalKeys.names[33] == "Space" && PedalKeys.names[39] == "0" && PedalKeys.names[51] == "F1" && PedalKeys.names[62] == "F12", "space, digits, F-keys positions")
check(PedalKeys.Modifier.control.rawValue == 0x3E + 1 && PedalKeys.Modifier.command.rawValue == 0x3E + 4, "modifiers are 0x3E + menu position")
check(PedalSettings.keyboardOffset(group: 5, sw: 3) + 3 == PedalSettings.mixBase, "keyboard block fills exactly 0x347D–0x34C4")
check(PedalSettings.customBase + PedalSettings.customGroups * PedalSettings.customGroupStride == PedalSettings.keyboardBase, "keyboard block starts where custom MIDI ends")
if let (k, dropped) = KeyCombo.learn(keyCode: 0x60, flags: [.command, .shift]) {   // ⌘⇧F5
    check(k.key == 55 && k.mod1 == 64 && k.mod2 == 66 && !dropped, "learn ⌘⇧F5 → shift, command, F5 (got \(k))")
    check(k.display == "⇧⌘F5", "display ⇧⌘F5 (got \(k.display))")
} else { check(false, "F5 should be learnable") }
check(KeyCombo.learn(keyCode: 0x00, flags: [])?.0.key == 1, "Mac A → pedal A")
check(KeyCombo.learn(keyCode: 0x1D, flags: [])?.0.key == 39, "Mac 0 → pedal 0")
check(KeyCombo.learn(keyCode: 0x31, flags: [])?.0.key == 33, "space")
check(KeyCombo.learn(keyCode: 0x29, flags: []) == nil, "semicolon can't be typed by the pedal")
check(KeyCombo.learn(keyCode: 0x00, flags: [.control, .shift, .option])?.droppedModifiers == true, "third modifier reported as dropped")
var ks = PedalSettings(bytes: [UInt8](repeating: 0, count: PedalSettings.size))
ks.setKeyboardKey(group: 2, sw: 1, KeyCombo(mod1: 63, mod2: 0, key: 3))
check(Array(ks.bytes[(0x347D + 2 * 12 + 3)..<(0x347D + 2 * 12 + 6)]) == [63, 0, 3], "keyboard bytes: mod1, mod2, key")
var mk = ks.mixSwitch(group: 0, sw: 0)
mk.keyCombo = KeyCombo(mod1: 66, mod2: 0, key: 19)   // ⌘S
ks.setMixSwitch(group: 0, sw: 0, mk)
check(Array(ks.bytes[(PedalSettings.mixBase + 2)...(PedalSettings.mixBase + 4)]) == [66, 0, 19], "mix key bytes 2–4")

// MARK: Diff ranges

var a = [UInt8](repeating: 0, count: 200), b = a
b[10] = 1; b[20] = 1; b[100] = 1
check(Pedal.diffRanges(a, b) == [10..<21, 100..<101], "diff merges close changes and splits far ones")
check(Pedal.diffRanges(a, a).isEmpty, "no diff when equal")

// MARK: Fake pedal

final class FakePedal: PedalTransport {
    var flash: [UInt8]
    var outbox: [[UInt8]] = []
    var dropEvery = 0      // drop every nth reply to exercise retries
    var echo = false       // send each request straight back first, like an IAC bus
    var silent = false     // never answer (pure loopback when combined with echo)
    var count = 0
    var writes = 0
    init(_ flash: [UInt8]) { self.flash = flash }
    func clearInbox() { outbox.removeAll() }
    func send(_ bytes: [UInt8]) throws {
        if echo { outbox.append(bytes) }
        if silent { return }
        let raw = SysEx.unwrap(bytes)
        let r = try SysEx.parse(raw)
        count += 1
        var reply: [UInt8]
        switch r.command {
        case 0x11:
            let name = Array("FootCtrlPlus_016".utf8) + [0]
            reply = SysEx.packet(.query, name + [1, 2, 3] + [UInt8](repeating: 0, count: 8))
        case 0x23:
            let addr = Int(SysEx.readLE(r.payload, 1, 4)), n = Int(SysEx.readLE(r.payload, 5, 3))
            reply = SysEx.packet(.flashRead, Array(r.payload.prefix(8)) + Array(flash[addr..<(addr + n)]))
        case 0x22:
            let addr = Int(SysEx.readLE(r.payload, 1, 4)), n = Int(SysEx.readLE(r.payload, 5, 3))
            flash.replaceSubrange(addr..<(addr + n), with: r.payload[8..<(8 + n)])
            writes += n
            reply = SysEx.packet(.response, [0])
        default:
            reply = SysEx.packet(.response, [1])
        }
        if dropEvery > 0 && count % dropEvery == 0 { return }
        outbox.append(SysEx.wrap(reply))
    }
    func nextSysEx(timeout: TimeInterval) -> [UInt8]? { outbox.isEmpty ? nil : outbox.removeFirst() }
}

let original = (0..<PedalSettings.size).map { UInt8(truncatingIfNeeded: $0 &* 7) }
let fake = FakePedal(original)
let pedal = Pedal(fake)
pedal.timeout = 0.01
do {
    let id = try pedal.identify()
    check(id.name == "FootCtrlPlus", "identify name (got \(id.name))")
    let all = try pedal.read(length: PedalSettings.size)
    check(all == original, "full read matches flash")
    var changed = all
    changed[0] = 3
    changed[PedalSettings.customSwitchOffset(group: 0, sw: 0)] = 1
    changed[0x5C5D] = 2
    let n = try pedal.writeChanges(from: all, to: changed)
    check(fake.flash == changed, "writeChanges leaves flash equal to the edit")
    check(n == fake.writes && n < 40, "only changed ranges written (\(n) bytes)")
    fake.dropEvery = 3
    let again = try pedal.read(length: 2000)
    check(again == Array(changed.prefix(2000)), "read survives dropped replies via retries")
} catch {
    check(false, "fake pedal: \(error)")
}

// MARK: Loopback ports (the CE-210 “calls itself ””  bug, 2026-11-07)

let loop = FakePedal(original); loop.echo = true; loop.silent = true
let loopPedal = Pedal(loop); loopPedal.timeout = 0.01; loopPedal.retries = 0
do {
    _ = try loopPedal.identify()
    check(false, "an echo-only port must not count as a pedal")
} catch let e as AppError {
    check(e.code == .echoPort, "echo-only port reports CE-211 (got \(e.code.rawValue))")
} catch { check(false, "unexpected error \(error)") }

let echoing = FakePedal(original); echoing.echo = true
let echoPedal = Pedal(echoing); echoPedal.timeout = 0.01
check((try? echoPedal.identify())?.name == "FootCtrlPlus", "echo followed by the real answer still identifies the pedal")
check((try? echoPedal.read(length: 300)) == Array(original.prefix(300)), "reads work through an echoing port")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
