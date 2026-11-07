import AppKit
import SwiftUI

// Renders the editor with sample settings to PNGs (no pedal, no window).
// Usage: snapshot <output dir>

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
_ = NSApplication.shared

@MainActor func render<V: View>(_ view: V, _ name: String, size: CGSize) {
    let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed: \(name)"); return
    }
    try? png.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name)")
}

MainActor.assumeIsolated {
    let model = EditorModel()
    var s = PedalSettings(bytes: [UInt8](repeating: 0, count: PedalSettings.size))
    s.mode = PedalMode.customMIDI.rawValue
    func set(_ g: Int, _ sw: Int, _ f: (inout SwitchProgram) -> Void) { var p = s.customSwitch(group: g, sw: sw); f(&p); s.setCustomSwitch(group: g, sw: sw, p) }
    set(0, 0) { $0.stompMode = .toggle
        $0.setMessages(bank: 0, [MidiMessage(kind: .controlChange, number: 80, value: 127), MidiMessage(kind: .programChange, number: 3)])
        $0.setMessages(bank: 1, [MidiMessage(kind: .controlChange, number: 80, value: 0)]) }
    set(0, 1) { $0.stompMode = .single; $0.setMessages(bank: 0, [MidiMessage(channel: 1, kind: .programChange, number: 12)]) }
    set(0, 2) { $0.stompMode = .pressRelease
        $0.setMessages(bank: 0, [MidiMessage(kind: .noteOn, number: 60, value: 100)])
        $0.setMessages(bank: 1, [MidiMessage(kind: .noteOff, number: 60, value: 0)]) }
    set(0, 3) { $0.stompMode = .single; $0.setMessages(bank: 0, [MidiMessage(kind: .custom)]); $0.setRawBytes(bank: 0, [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]) }
    var b = s.bytes; b[PedalSettings.customSwitchOffset(group: 0, sw: 1) + 4] = 9   // make it look edited
    model.baseline = b
    model.settings = s
    model.identity = Pedal.Identity(name: "FootCtrlPlus", version: "1.2.3", raw: [])
    model.connectedPortName = "Chocolate Plus"
    model.status = "Read 23646 bytes from Chocolate Plus."
    model.liveMessages = [(Date(), "CC 80 = 127 · ch 1"), (Date(), "PC 3 · ch 1")]

    render(VStack(spacing: 0) { MainContent().environmentObject(model); StatusBar().environmentObject(model) }, "main.png", size: CGSize(width: 1000, height: 760))
    model.selectedSwitch = 3
    render(MainContent().environmentObject(model), "raw.png", size: CGSize(width: 1000, height: 620))
    model.updateSettings {
        $0.setKeyboardKey(group: 0, sw: 0, KeyCombo(mod1: 64, mod2: 66, key: 55))
        $0.setKeyboardKey(group: 0, sw: 1, KeyCombo(mod1: 0, mod2: 0, key: 33))
        $0.setKeyboardKey(group: 0, sw: 2, KeyCombo(mod1: 63, mod2: 0, key: 29))
    }
    model.area = .keyboard; model.group = 0; model.selectedSwitch = 0
    render(MainContent().environmentObject(model), "keys.png", size: CGSize(width: 1000, height: 640))
    model.settings = nil
    render(Welcome().environmentObject(model), "welcome.png", size: CGSize(width: 800, height: 500))
}
