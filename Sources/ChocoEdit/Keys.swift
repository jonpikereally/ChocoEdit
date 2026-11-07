import AppKit

/// The keys a Chocolate Plus can type, decoded from CubeSuite's key menu
/// (FootCtrlPlusDlg::init builds it; the stored byte is the menu position).
///   0 none · 1–26 A–Z · 27–30 ↑ ↓ ← → · 31 Page Up · 32 Page Down · 33 Space
///   34 Enter · 35 Esc · 36 Delete · 37 Caps Lock · 38 Tab · 39–48 0–9
///   49 + · 50 − · 51–62 F1–F12
/// Modifiers are stored as 0x3E + their menu position: 63 Ctrl, 64 Shift,
/// 65 Alt/Option, 66 Win/Command (0 = none).
enum PedalKeys {
    static let names: [String] = {
        var n = ["none"]
        n += (0..<26).map { String(UnicodeScalar(UInt8(65 + $0))) }
        n += ["↑", "↓", "←", "→", "Page Up", "Page Down", "Space", "Enter", "Esc", "Delete", "Caps Lock", "Tab"]
        n += (0...9).map(String.init)
        n += ["+", "−"]
        n += (1...12).map { "F\($0)" }
        return n
    }()

    enum Modifier: UInt8, CaseIterable, Identifiable {
        case control = 63, shift = 64, option = 65, command = 66
        var id: UInt8 { rawValue }
        var symbol: String { ["⌃", "⇧", "⌥", "⌘"][Int(rawValue - 63)] }
        var name: String { ["Control", "Shift", "Option/Alt", "Command/Win"][Int(rawValue - 63)] }
    }

    static func name(_ key: UInt8) -> String {
        Int(key) < names.count ? names[Int(key)] : "code \(key)"
    }

    /// Mac virtual key code → pedal key code. Keys the pedal can't type are missing.
    static let fromMac: [UInt16: UInt8] = {
        var m: [UInt16: UInt8] = [:]
        // A–Z by Mac key code (kVK_ANSI_*).
        let letters: [Character: UInt16] = ["A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06,
            "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
            "T": 0x11, "O": 0x1F, "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28, "N": 0x2D, "M": 0x2E]
        for (ch, code) in letters { m[code] = UInt8(ch.asciiValue! - 64) }
        m[0x7E] = 27; m[0x7D] = 28; m[0x7B] = 29; m[0x7C] = 30          // ↑ ↓ ← →
        m[0x74] = 31; m[0x79] = 32                                         // Page Up / Down
        m[0x31] = 33                                                       // Space
        m[0x24] = 34; m[0x4C] = 34                                         // Return, keypad Enter
        m[0x35] = 35                                                       // Esc
        m[0x33] = 36                                                       // Delete (backspace)
        m[0x39] = 37                                                       // Caps Lock
        m[0x30] = 38                                                       // Tab
        let digits: [UInt16] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]   // 0–9
        let keypad: [UInt16] = [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
        for i in 0...9 { m[digits[i]] = UInt8(39 + i); m[keypad[i]] = UInt8(39 + i) }
        m[0x18] = 49; m[0x45] = 49                                         // = / + key, keypad +
        m[0x1B] = 50; m[0x4E] = 50                                         // - key, keypad −
        let fkeys: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for i in 0..<12 { m[fkeys[i]] = UInt8(51 + i) }
        return m
    }()

    /// Pedal modifiers for a Mac key press, in Ctrl, Shift, Option, Command order.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> [Modifier] {
        var out: [Modifier] = []
        if flags.contains(.control) { out.append(.control) }
        if flags.contains(.shift) { out.append(.shift) }
        if flags.contains(.option) { out.append(.option) }
        if flags.contains(.command) { out.append(.command) }
        return out
    }

    /// The 10 keys Mix Key's "page turner" function can send (CubeSuite's Turner list).
    static let turnerNames = ["↑", "↓", "←", "→", "Page Up", "Page Down", "Previous track", "Next track", "Volume −", "Volume +"]
}

/// A key with up to two modifiers, as the pedal stores it.
struct KeyCombo: Equatable {
    var mod1: UInt8 = 0
    var mod2: UInt8 = 0
    var key: UInt8 = 0

    var modifiers: [PedalKeys.Modifier] { [mod1, mod2].compactMap { PedalKeys.Modifier(rawValue: $0) } }

    var display: String {
        if key == 0 && mod1 == 0 && mod2 == 0 { return "No key" }
        let mods = modifiers.sorted { $0.rawValue < $1.rawValue }.map(\.symbol).joined()
        return mods + (key == 0 ? "" : PedalKeys.name(key))
    }

    /// From a Mac key press; nil if the pedal can't type that key. More than
    /// two modifiers can't be stored, so `droppedModifiers` says if any were lost.
    static func learn(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> (KeyCombo, droppedModifiers: Bool)? {
        guard let key = PedalKeys.fromMac[keyCode] else { return nil }
        let mods = PedalKeys.modifiers(flags)
        return (KeyCombo(mod1: mods.first?.rawValue ?? 0, mod2: mods.count > 1 ? mods[1].rawValue : 0, key: key), mods.count > 2)
    }
}

extension PedalSettings {
    // MARK: Custom keyboard mode (mode 10): 6 groups × 4 switches × 3 bytes at 0x347D
    static let keyboardBase = 0x347D
    static let keyboardGroups = 6

    static func keyboardOffset(group: Int, sw: Int) -> Int { keyboardBase + group * 12 + sw * 3 }

    func keyboardKey(group: Int, sw: Int) -> KeyCombo {
        let o = Self.keyboardOffset(group: group, sw: sw)
        return KeyCombo(mod1: bytes[o], mod2: bytes[o + 1], key: bytes[o + 2])
    }
    mutating func setKeyboardKey(group: Int, sw: Int, _ k: KeyCombo) {
        let o = Self.keyboardOffset(group: group, sw: sw)
        bytes[o] = k.mod1; bytes[o + 1] = k.mod2; bytes[o + 2] = k.key
    }

    /// 0x5C59: the custom-keyboard group the pedal is on.
    var keyboardCurrentGroup: Int { get { Int(bytes[0x5C59]) } set { bytes[0x5C59] = UInt8(clamping: newValue) } }
}

extension MixSwitch {
    /// Mix Key keyboard function: bytes 2 and 3 are modifiers, byte 4 the key.
    var keyCombo: KeyCombo {
        get { KeyCombo(mod1: bytes[2], mod2: bytes[3], key: bytes[4]) }
        set { bytes[2] = newValue.mod1; bytes[3] = newValue.mod2; bytes[4] = newValue.key }
    }
    /// Mix Key page-turner function: byte 1 picks from PedalKeys.turnerNames.
    var turnerKey: UInt8 { get { bytes[1] } set { bytes[1] = newValue } }
}
