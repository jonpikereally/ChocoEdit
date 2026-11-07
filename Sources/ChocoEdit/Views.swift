import SwiftUI

private let switchNames = ["A", "B", "C", "D"]
private let accent = Color(red: 0.62, green: 0.40, blue: 0.24)   // chocolate

struct ContentView: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 230, ideal: 260)
        } detail: {
            if model.settings == nil {
                Welcome()
            } else {
                MainArea()
            }
        }
        .toolbar { Toolbar() }
        .overlay(alignment: .bottom) { StatusBar() }
        .frame(minWidth: 980, minHeight: 680)
    }
}

// MARK: Toolbar and status

struct Toolbar: ToolbarContent {
    @EnvironmentObject var model: EditorModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("Port", selection: Binding(get: { model.selectedPortName }, set: { model.pickPort($0) })) {
                if model.ports.isEmpty { Text("No MIDI ports").tag(String?.none) }
                ForEach(model.ports) { p in
                    Text(p.looksLikeChocolate ? "🍫 \(p.name)" : p.name).tag(String?.some(p.name))
                }
            }
            .frame(width: 220)
            .help("The pedal's MIDI port. Use USB: Bluetooth may be too slow for reading settings.")
            Button { model.refreshPorts() } label: { Image(systemName: "arrow.clockwise") }
                .help("Look for MIDI ports again")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.readFromPedal() } label: { Label("Read from Pedal", systemImage: "arrow.down.circle") }
                .disabled(model.busy != nil || model.selectedPortName == nil)
                .help("Load the pedal's settings into the editor (a copy goes to ~/Documents/ChocoEdit Backups)")
            Button { model.writeToPedal() } label: { Label("Write to Pedal", systemImage: "arrow.up.circle.fill") }
                .disabled(model.busy != nil || model.settings == nil || model.selectedPortName == nil || !model.isDirty)
                .help("Send your changes to the pedal and check them. The pedal's current settings are backed up first.")
            Menu {
                Button("Open Settings File…") { model.openFile() }
                Button("Save Settings File…") { model.saveFile() }.disabled(model.settings == nil)
                Divider()
                Button("Revert to Pedal") { model.revert() }.disabled(model.baseline == nil || !model.isDirty)
                Button("Show Backups") { NSWorkspace.shared.open(EditorModel.backupFolder) }
            } label: { Label("File", systemImage: "doc") }
        }
    }
}

struct StatusBar: View {
    @EnvironmentObject var model: EditorModel
    var body: some View {
        HStack(spacing: 10) {
            if let b = model.busy {
                ProgressView(value: model.progress).frame(width: 160)
                Text(b)
            } else {
                Image(systemName: model.lastError != nil && model.status.contains("CE-") ? "exclamationmark.triangle.fill" : "circle.fill")
                    .foregroundStyle(model.status.contains("CE-") ? .orange : (model.isConnected ? .green : .secondary))
                    .font(.caption)
                Text(model.status).lineLimit(1)
                    .help(model.status.contains("CE-") ? ErrorReporter.tooltip : model.status)
            }
            Spacer()
            if let id = model.identity { Text("\(id.name) · \(model.connectedPortName ?? "")").foregroundStyle(.secondary) }
            if model.isDirty && model.settings != nil { Text("Unsaved changes").foregroundStyle(accent).bold() }
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.bar)
    }
}

struct Welcome: View {
    @EnvironmentObject var model: EditorModel
    var body: some View {
        VStack(spacing: 18) {
            Text("🍫").font(.system(size: 64))
            Text("ChocoEdit").font(.largeTitle.bold())
            Text("An editor for the M-VAVE Chocolate Plus.\nPlug the pedal in with a USB-C data cable, quit CubeSuite, and read its settings.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack {
                Button("Read from Pedal") { model.readFromPedal() }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(model.selectedPortName == nil || model.busy != nil)
                Button("Open Settings File…") { model.openFile() }
            }
            Text("Nothing is written to the pedal until you click Write to Pedal, and every write is backed up first.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        List {
            if let s = model.settings {
                Section("Pedal mode") {
                    Picker("Mode", selection: Binding(get: { s.mode }, set: { v in model.updateSettings { $0.mode = v }; model.followPedalMode() })) {
                        ForEach(PedalMode.allCases) { m in Text(m.title).tag(m.rawValue) }
                        if PedalMode(rawValue: s.mode) == nil { Text("Unknown (\(s.mode))").tag(s.mode) }
                    }
                    .labelsHidden()
                    Text(PedalMode(rawValue: s.mode)?.explanation ?? "A mode this editor doesn't know.")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("Channel \(s.midiChannel + 1)",
                            value: Binding(get: { s.midiChannel + 1 }, set: { v in model.updateSettings { $0.midiChannel = v - 1 } }),
                            in: 1...16)
                        .help("“Send on MIDI Channel” for the Program Change and Control Change modes")
                }
                Section("Edit") {
                    Picker("Area", selection: $model.area) {
                        Text("MIDI").tag(EditArea.custom)
                        Text("Mix Key").tag(EditArea.mix)
                        Text("Keyboard").tag(EditArea.keyboard)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .onChange(of: model.area) { _ in model.group = min(model.group, model.groupCount - 1) }
                    let wanted: PedalMode = model.area == .custom ? .customMIDI : model.area == .mix ? .mixKey : .customKeyboard
                    if s.mode != wanted.rawValue {
                        Text("The pedal isn't in this mode, so these settings won't be used until you switch it to \(wanted.title).")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Switch pedal to \(wanted.title)") { model.updateSettings { $0.mode = wanted.rawValue } }
                            .font(.caption)
                    }
                }
                Section("Groups") {
                    ForEach(0..<model.groupCount, id: \.self) { g in
                        HStack {
                            Text("Group \(g + 1)")
                            Spacer()
                            if g == (model.area == .custom ? s.customCurrentGroup : model.area == .mix ? s.mixCurrentGroup : s.keyboardCurrentGroup) {
                                Text("on pedal").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                        .listRowBackground(model.group == g ? accent.opacity(0.25) : Color.clear)
                        .onTapGesture { model.group = g }
                    }
                }
            }
            Section("Live MIDI from pedal") {
                if model.liveMessages.isEmpty {
                    Text(model.isConnected ? "Step on a switch to see what it sends." : "Read from the pedal (or Listen) to watch what it sends.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.isConnected { Button("Listen") { model.listen() }.disabled(model.selectedPortName == nil) }
                }
                ForEach(Array(model.liveMessages.prefix(12).enumerated()), id: \.offset) { _, m in
                    Text(m.1).font(.system(.caption, design: .monospaced))
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: Main area

struct MainArea: View {
    @EnvironmentObject var model: EditorModel
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            MainContent(showAdvanced: { showAdvanced = true })
        }
        .sheet(isPresented: $showAdvanced) { AdvancedView().environmentObject(model) }
    }
}

struct MainContent: View {
    @EnvironmentObject var model: EditorModel
    var showAdvanced: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(model.area == .custom ? "Custom MIDI" : model.area == .mix ? "Mix Key" : "Custom keyboard") · Group \(model.group + 1)")
                    .font(.title2.bold())
                Spacer()
                Button("Advanced…") { showAdvanced() }
                    .help("Every setting byte, including the ones this editor can't name yet")
            }
            PedalStrip()
            if model.area == .keyboard {
                KeyComboEditor(sw: model.selectedSwitch)
            } else {
                if model.area == .mix { MixFunctionEditor() }
                if model.area == .custom || (model.mixSwitch(sw: model.selectedSwitch)?.function ?? 0) == 0 {
                    SwitchEditor()
                }
            }
        }
        .padding(22)
        .padding(.bottom, 40)
    }
}

/// The four switches drawn like the pedal.
struct PedalStrip: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { sw in
                SwitchTile(sw: sw)
                    .onTapGesture { model.selectedSwitch = sw }
                    .contextMenu {
                        if model.area != .keyboard {
                        ForEach(0..<4, id: \.self) { to in
                            if to != sw { Button("Copy to \(switchNames[to])") { model.copySwitch(sw, to: to) } }
                        }
                        Button("Clear") { model.updateProgram(sw: sw) { p in
                            p.stompMode = .single; p.setMessages(bank: 0, []); p.setMessages(bank: 1, [])
                            p.setRawBytes(bank: 0, []); p.setRawBytes(bank: 1, [])
                        } }
                        } else {
                            Button("Clear key") { model.setKeyCombo(sw: sw, KeyCombo()) }
                        }
                    }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
    }
}

struct SwitchTile: View {
    @EnvironmentObject var model: EditorModel
    let sw: Int

    var body: some View {
        let p = model.program(sw: sw)
        let selected = model.selectedSwitch == sw
        let a = p?.messages(bank: 0) ?? []
        let b = p?.messages(bank: 1) ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(switchNames[sw]).font(.title.bold()).foregroundStyle(.white)
                Spacer()
                Circle().fill(selected ? accent : Color(white: 0.35)).frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color(white: 0.6), lineWidth: 2))
            }
            if model.area == .keyboard, let k = model.keyCombo(sw: sw) {
                Text("Types").font(.caption).foregroundStyle(Color(white: 0.7))
                Text(k.display).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            } else if model.area == .mix, let m = model.mixSwitch(sw: sw), m.function != 0 {
                Text(m.function == 1 ? "Types" : m.function == 2 ? "Page turner" : "Function \(m.function)")
                    .font(.caption).foregroundStyle(Color(white: 0.7))
                Text(m.function == 1 ? m.keyCombo.display
                     : m.function == 2 ? (Int(m.turnerKey) < PedalKeys.turnerNames.count ? PedalKeys.turnerNames[Int(m.turnerKey)] : "code \(m.turnerKey)")
                     : "")
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            } else {
                Text(p?.stompMode?.title ?? "Stomp mode \(p?.stompModeRaw ?? 0)").font(.caption).foregroundStyle(Color(white: 0.7))
                summary("A", a, p, 0)
                if p?.stompMode?.usesBankB == true { summary("B", b, p, 1) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: selected ? 0.24 : 0.18)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }

    @ViewBuilder func summary(_ bank: String, _ list: [MidiMessage], _ p: SwitchProgram?, _ i: Int) -> some View {
        let text: String = list.isEmpty ? "—"
            : list.first?.kind == .custom ? "Raw: " + Hex.format(p?.rawBytes(bank: i) ?? [])
            : list.prefix(2).map(\.summary).joined(separator: "\n") + (list.count > 2 ? "\n+\(list.count - 2) more" : "")
        HStack(alignment: .top, spacing: 4) {
            Text(bank).font(.caption2.bold()).foregroundStyle(accent)
            Text(text).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white).lineLimit(3)
        }
    }
}

// MARK: Switch editor

struct SwitchEditor: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        let sw = model.selectedSwitch
        if let p = model.program(sw: sw) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Switch \(switchNames[sw])").font(.title3.bold())
                    Picker("Stomp mode", selection: Binding(
                        get: { Int(p.stompModeRaw) },
                        set: { v in model.updateProgram(sw: sw) { $0.stompModeRaw = UInt8(v) } })) {
                        ForEach(StompMode.allCases) { m in Text(m.title).tag(m.rawValue) }
                        if p.stompMode == nil { Text("Unknown (\(p.stompModeRaw))").tag(Int(p.stompModeRaw)) }
                    }
                    .frame(maxWidth: 300)
                }
                Text(p.stompMode?.explanation ?? "").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    BankEditor(sw: sw, bank: 0, title: p.stompMode == .pressRelease ? "A · on press" : p.stompMode == .shortLong ? "A · short press" : "Bank A")
                    if p.stompMode?.usesBankB == true {
                        BankEditor(sw: sw, bank: 1, title: p.stompMode == .pressRelease ? "B · on release" : p.stompMode == .shortLong ? "B · long press" : "Bank B")
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
        }
    }
}

struct BankEditor: View {
    @EnvironmentObject var model: EditorModel
    let sw: Int
    let bank: Int
    let title: String
    @State private var rawText = ""
    @State private var rawError = false

    var body: some View {
        let p = model.program(sw: sw)
        let list = p?.messages(bank: bank) ?? []
        let isRaw = list.first?.kind == .custom
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Picker("", selection: Binding(get: { isRaw }, set: { raw in setRaw(raw, list) })) {
                    Text("Messages").tag(false)
                    Text("Raw SysEx").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 190).labelsHidden()
            }
            if isRaw {
                Text("Bytes sent as-is, in hex (up to 127). For SysEx include F0 … F7.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("F0 00 01 02 F7", text: $rawText)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(rawError ? .red : .primary)
                    .onAppear { rawText = Hex.format(p?.rawBytes(bank: bank) ?? []) }
                    .onChange(of: model.selectedSwitch) { _ in rawText = Hex.format(model.program(sw: sw)?.rawBytes(bank: bank) ?? []) }
                    .onChange(of: model.group) { _ in rawText = Hex.format(model.program(sw: sw)?.rawBytes(bank: bank) ?? []) }
                    .onSubmit { commitRaw() }
                HStack {
                    Button("Apply") { commitRaw() }
                    if rawError { Text("Not valid hex, or longer than 127 bytes").font(.caption).foregroundStyle(.red) }
                }
            } else {
                if list.isEmpty {
                    Text("No messages. This bank sends nothing.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(list.enumerated()), id: \.offset) { i, m in
                    MessageRow(message: m, index: i, count: list.count,
                               onChange: { new in edit(list) { $0[i] = new } },
                               onDelete: { edit(list) { $0.remove(at: i) } },
                               onMove: { d in edit(list) { $0.swapAt(i, i + d) } })
                }
                HStack {
                    Button { edit(list) { $0.append(list.last.map { MidiMessage(channel: $0.channel, kind: $0.kind, number: $0.kind == .controlChange ? $0.number + 1 : $0.number, value: $0.value) } ?? MidiMessage()) } }
                        label: { Label("Add message", systemImage: "plus") }
                        .disabled(list.count >= SwitchProgram.slots)
                    Text("\(list.count)/\(SwitchProgram.slots)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func edit(_ list: [MidiMessage], _ change: (inout [MidiMessage]) -> Void) {
        var l = list
        change(&l)
        model.updateProgram(sw: sw) { $0.setMessages(bank: bank, l) }
    }

    private func setRaw(_ raw: Bool, _ list: [MidiMessage]) {
        if raw {
            let ch = list.first?.channel ?? 0
            model.updateProgram(sw: sw) { $0.setMessages(bank: bank, [MidiMessage(channel: ch, kind: .custom, number: 0, value: 0)]) }
            rawText = Hex.format(model.program(sw: sw)?.rawBytes(bank: bank) ?? [])
        } else {
            model.updateProgram(sw: sw) { $0.setMessages(bank: bank, [MidiMessage()]) }
        }
    }

    private func commitRaw() {
        guard let bytes = Hex.parse(rawText), bytes.count <= 127 else { rawError = true; return }
        rawError = false
        model.updateProgram(sw: sw) { $0.setRawBytes(bank: bank, bytes) }
        rawText = Hex.format(bytes)
    }
}

struct MessageRow: View {
    let message: MidiMessage
    let index: Int
    let count: Int
    let onChange: (MidiMessage) -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
            Picker("", selection: Binding(get: { message.kind }, set: { k in var m = message; m.kind = k; onChange(m) })) {
                ForEach(MidiMessage.Kind.allCases.filter { $0 != .custom }) { k in Text(k.title).tag(k) }
                if message.kind == .custom { Text("Raw").tag(MidiMessage.Kind.custom) }
            }
            .labelsHidden().frame(width: 95)
            Picker("", selection: Binding(get: { message.channel }, set: { c in var m = message; m.channel = c; onChange(m) })) {
                ForEach(0..<16, id: \.self) { c in Text("Ch \(c + 1)").tag(c) }
            }
            .labelsHidden().frame(width: 72)
            NumberField(label: numberLabel, value: message.number) { v in var m = message; m.number = v; onChange(m) }
            if message.kind == .noteOn || message.kind == .noteOff {
                Text(MidiMessage.noteName(message.number)).font(.caption).foregroundStyle(.secondary).fixedSize().frame(width: 34)
            }
            if message.kind != .programChange {
                NumberField(label: message.kind == .controlChange ? "Value" : "Vel", value: message.value) { v in var m = message; m.value = v; onChange(m) }
            }
            Spacer()
            Text(Hex.format(message.wireBytes)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
                .help("The bytes this message sends")
            Button { onMove(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(index == 0)
            Button { onMove(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).disabled(index == count - 1)
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
        }
    }

    var numberLabel: String {
        switch message.kind {
        case .programChange: return "PC"
        case .controlChange: return "CC"
        default: return "Note"
        }
    }
}

struct NumberField: View {
    let label: String
    let value: Int
    let onCommit: (Int) -> Void
    var body: some View {
        HStack(spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
            TextField("", value: Binding(get: { value }, set: { onCommit(max(0, min(127, $0))) }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 48)
            Stepper("", value: Binding(get: { value }, set: { onCommit(max(0, min(127, $0))) }), in: 0...127).labelsHidden()
        }
    }
}

// MARK: Mix Key

struct MixFunctionEditor: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        let sw = model.selectedSwitch
        if let m = model.mixSwitch(sw: sw) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Switch \(switchNames[sw]) does").font(.headline)
                    Picker("", selection: Binding(get: { Int(m.function) }, set: { v in model.updateMix(sw: sw) { $0.function = UInt8(v) } })) {
                        Text("Custom MIDI").tag(0)
                        Text("Keyboard key").tag(1)
                        Text("Page turner").tag(2)
                        if m.function > 2 { Text("Unknown (\(m.function))").tag(Int(m.function)) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 360)
                }
                if m.function == 2 {
                    Picker("Sends", selection: Binding(get: { Int(m.turnerKey) }, set: { v in model.updateMix(sw: sw) { $0.turnerKey = UInt8(v) } })) {
                        ForEach(Array(PedalKeys.turnerNames.enumerated()), id: \.offset) { i, n in Text(n).tag(i) }
                        if Int(m.turnerKey) >= PedalKeys.turnerNames.count { Text("Unknown (\(m.turnerKey))").tag(Int(m.turnerKey)) }
                    }
                    .frame(width: 260)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
            if m.function == 1 { KeyComboEditor(sw: sw) }
        }
    }
}

// MARK: Keyboard keys

/// Edits the key (and up to two modifiers) a switch types, by picking from
/// menus or by pressing the key on the Mac's keyboard.
struct KeyComboEditor: View {
    @EnvironmentObject var model: EditorModel
    let sw: Int
    @State private var learning = false
    @State private var monitor: Any?
    @State private var note: String?
    @State private var noteIsWarning = false

    var body: some View {
        let k = model.keyCombo(sw: sw) ?? KeyCombo()
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Switch \(switchNames[sw]) types").font(.headline)
                    Text(k.display).font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(k.key == 0 ? .secondary : .primary)
                }
                Spacer()
                Button {
                    learning ? stopLearning() : startLearning()
                } label: {
                    Label(learning ? "Press a key on your keyboard…" : "Learn from Keyboard",
                          systemImage: learning ? "keyboard.badge.ellipsis" : "keyboard")
                        .frame(minWidth: 230)
                }
                .buttonStyle(.borderedProminent).tint(learning ? .orange : accent)
                .controlSize(.large)
                .help("Click, then press the key or combination (like ⌘⇧S) you want this switch to type. Click again to cancel.")
                Button("Clear") { model.setKeyCombo(sw: sw, KeyCombo()); note = nil }
            }
            if let note {
                Text(note).font(.callout).foregroundStyle(noteIsWarning ? .orange : .secondary)
            }
            Divider()
            HStack(spacing: 18) {
                Picker("Key", selection: Binding(get: { Int(k.key) }, set: { v in var n = k; n.key = UInt8(v); model.setKeyCombo(sw: sw, n) })) {
                    ForEach(Array(PedalKeys.names.enumerated()), id: \.offset) { i, n in Text(n).tag(i) }
                    if Int(k.key) >= PedalKeys.names.count { Text("Unknown (\(k.key))").tag(Int(k.key)) }
                }
                .frame(width: 200)
                ForEach(PedalKeys.Modifier.allCases) { m in
                    Toggle(isOn: Binding(get: { k.modifiers.contains(m) }, set: { on in setModifier(m, on, k) })) {
                        Text("\(m.symbol) \(m.name)")
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Text("The pedal can type A–Z, 0–9, F1–F12, arrows, Page Up/Down, Space, Enter, Esc, Delete, Caps Lock, Tab, + and −, with up to two modifiers. On a laptop, hold fn while pressing F1–F12. Caps Lock has to be picked from the menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(learning ? Color.orange : Color.secondary.opacity(0.25), lineWidth: learning ? 2 : 1))
        .onChange(of: model.selectedSwitch) { _ in stopLearning(); note = nil }
        .onChange(of: model.group) { _ in stopLearning(); note = nil }
        .onDisappear { stopLearning() }
    }

    private func setModifier(_ m: PedalKeys.Modifier, _ on: Bool, _ k: KeyCombo) {
        var mods = k.modifiers.filter { $0 != m }
        if on {
            guard mods.count < 2 else {
                NSSound.beep()
                note = "The pedal can only hold two modifier keys per switch."
                noteIsWarning = true
                return
            }
            mods.append(m)
        }
        mods.sort { $0.rawValue < $1.rawValue }
        var n = k
        n.mod1 = mods.first?.rawValue ?? 0
        n.mod2 = mods.count > 1 ? mods[1].rawValue : 0
        model.setKeyCombo(sw: sw, n)
    }

    private func startLearning() {
        stopLearning()
        learning = true
        note = "Waiting for a key… (Command-Tab and other system shortcuts can't be captured.)"
        noteIsWarning = false
        let target = sw
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard learning else { return event }
            if let (combo, dropped) = KeyCombo.learn(keyCode: event.keyCode, flags: event.modifierFlags) {
                model.setKeyCombo(sw: target, combo)
                note = dropped ? "Learned \(combo.display). The pedal holds at most two modifiers, so the others were left off."
                               : "Learned \(combo.display). Write to Pedal to save it."
                noteIsWarning = dropped
                stopLearning()
            } else {
                NSSound.beep()
                note = "The pedal can't type that key. Try another, or click the button to stop."
                noteIsWarning = true
            }
            return nil     // keep the key press from doing anything else in the app
        }
    }

    private func stopLearning() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        learning = false
    }
}

// MARK: Advanced

struct AdvancedView: View {
    @EnvironmentObject var model: EditorModel
    @Environment(\.dismiss) var dismiss
    @State private var offsetText = "0"
    @State private var showOnlyNonZero = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("All settings bytes").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("The Chocolate Plus keeps \(PedalSettings.size) bytes of settings. Names marked “unverified” are guesses. Edit with care: everything here is written as-is.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Hide zero bytes outside the header and tail", isOn: $showOnlyNonZero)
            if let s = model.settings {
                let rows = rowsToShow(s)
                List(rows, id: \.self) { o in
                    HStack {
                        Text(String(format: "0x%04X", o)).font(.system(.body, design: .monospaced)).frame(width: 70, alignment: .leading)
                        TextField("", value: Binding(get: { Int(s.bytes[o]) },
                                                     set: { v in model.updateSettings { $0.bytes[o] = UInt8(clamping: v) } }),
                                  format: .number)
                            .frame(width: 60).textFieldStyle(.roundedBorder)
                        Text(String(format: "%02X", s.bytes[o])).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                        if let b = model.baseline, b[o] != s.bytes[o] { Text("was \(b[o])").font(.caption).foregroundStyle(accent) }
                        Text(PedalSettings.describe(offset: o)).font(.caption)
                            .foregroundStyle(PedalSettings.describe(offset: o).contains("unverified") ? .orange : .secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: 600)
    }

    func rowsToShow(_ s: PedalSettings) -> [Int] {
        let header = Array(0..<PedalSettings.customBase)
        let tail = Array(0x5C55..<PedalSettings.size)
        let gap = Array((PedalSettings.customBase + PedalSettings.customGroups * PedalSettings.customGroupStride)..<PedalSettings.mixBase)
        if !showOnlyNonZero { return Array(0..<PedalSettings.size) }
        let middle = (PedalSettings.customBase..<0x5C55).filter { s.bytes[$0] != 0 || (model.baseline?[$0] ?? 0) != 0 }
        return Array(Set(header + gap + middle + tail)).sorted()
    }
}
