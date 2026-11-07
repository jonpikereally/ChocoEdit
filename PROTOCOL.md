# Chocolate Plus protocol notes

How M-VAVE's CubeSuite (macOS build, `com.sinco.CubeSuite`, Qt, shipped with
debug symbols) talks to the Chocolate Plus. Worked out from the disassembly
on 2026-11-07. **Query, full read and write confirmed on a real Chocolate Plus the same day**
(see "Seen on the real pedal").
CubeSuite's internal name for the pedal is **FootCtrlPlus** (its editor class
is `FootCtrlPlusDlg`; the GAM-10 and AIRMINI share that editor).

## Seen on the real pedal (2026-11-07)

- USB MIDI port name: **SINCO** (the maker, Zhuhai Sinco). Not "Chocolate".
- Query reply: name **`FootCtrlPlus_016`** (model + firmware 0.1.6?), 27-byte payload, checksum good.
- Full 0x5C5E read in 113-byte chunks works.
- The test pedal: mode byte 8, header `08 01 01 00 27 00 21 00 22 00 23 00 07 01 01`,
  custom group 1 A = `01 01 01 27 7F` (CC 39 = 127, ch 2), B = `01 01 01 26 39` (CC 38 = 57, ch 2).
- Unused slots hold `01 00 00 00 00` (present, ch 1, PC 0), so factory switches send PC 0.
- That first-slot `01` repeats every 0x1A1 from 0x5E for **40 switches (10 groups)**, running
  into the Mix Key area, whose own first-slot `01`s sit every 0x1A6 from 0x34CB (24 switches,
  confirming its layout). Probably the factory init over-running; CubeSuite edits 8 custom groups.
- Tail `1F 1F 01 01 00 00 00 00 00`: 0x5C55/56 = 31 = last group index of PC and CC modes
  (128 programs ÷ 4), 0x5C57 = custom-mode group count?, 0x5C58 = 1.
- Write test: `22` packet for 3 bytes at 0x03A2 → reply `00 59 00 01 00 00 00 FF` (status 0);
  read-back matched; a full re-dump differed in exactly those 3 bytes; writing the original back
  restored a byte-identical dump. Writes take effect immediately, no save command needed.
- CubeSuite's Chocolate editor never calls `flash_save_0` (only the SMK25/MIDI keyboard/mixer
  editors do), so writes are presumably permanent. Not yet power-cycle tested.

## Transport

Plain USB MIDI (CoreMIDI through RtMidi), SysEx only. No handshake: CubeSuite
opens the port and sends a query straight away.

### SysEx wrapping (`CMIDITranfer::prepare_sysex_out_buffer`)

The raw packet is a little-endian bit stream cut into 7-bit groups, least
significant first, each in its own byte, between `F0` and `F7`. Leftover bits
at the end go in one last byte. Example (same scheme as the M-VAVE Looper Pro,
documented by michaelforney): `12 34 AB CD` → `F0 12 68 2C 6D 0C F7`.

### Packet (`CUSBConnect::make_*_packet`)

```
00 59 | cmd | len (3 bytes LE) | payload (len bytes) | checksum
```

`checksum = ~(sum of payload bytes) & 0xFF` (`add_checksum` / `verify_checksum`).

| cmd | name | request payload | reply |
|---|---|---|---|
| `11` | query | none | cmd `11`, 34-byte packet: payload[0..15] device name, then version bytes |
| `23` | flash read | type(1) addr(4 LE) len(3 LE) | cmd `23`, same 8 bytes + `len` data bytes (packet = len + 15) |
| `22` | flash write | type addr len + data | cmd `00`, 8-byte packet, payload[0] = status, 0 = OK |
| `21` | flash erase | type addr | (not used by the Chocolate editor) |

Chunk size: CubeSuite reads/writes `packetSize − 15` bytes per packet, where
`packetSize` is 0x80, 0x200 or 0x400 depending on the chip
(`update_hardware_info`). ChocoEdit uses 113 (= 0x80 − 15) to be safe.
Reply timeout in CubeSuite: 2000 ms.

## Settings block

Flash type **4**, address 0, **0x5C5E (23,646) bytes**. CubeSuite reads it all
at once (`initDataByUSB`) and writes individual fields back at their offsets
as you edit (`sendDataToDevice(offset, ptr, len)` → `flash_write(4, offset, …)`).

| Offset | Size | Meaning | Status |
|---|---|---|---|
| 0x0000 | 1 | Mode 0–11 (list below) | traced |
| 0x0001 | 1 | Interface type radio | traced, meaning unverified |
| 0x0002 | 1 | MIDI channel, 0-based (“Send on MIDI Channel”) | traced |
| 0x0003, 05, 07, 09 | 1 each | Switch A–D “visual behaviour” toggles | traced, meaning unverified |
| 0x0004, 06, 08, 0A | 1 each | Switch A–D combo-box setting | traced, meaning unverified |
| 0x000C | 1 | Combo-box setting | traced, meaning unverified |
| 0x000D | 80 | “Interface” list: 16 × 5-byte messages | traced, meaning unverified |
| 0x005D | 0x3420 | Custom MIDI: 8 groups × 4 switches × 0x1A1 | traced |
| 0x347D | 0x48 | Custom keyboard: 6 groups × 4 switches × 3 bytes (modifier 1, modifier 2, key) | traced |
| 0x34C5 | 0x2790 | Mix Key: 6 groups × 4 switches × 0x1A6 | traced |
| 0x5C55–57 | 3 | “Max Group Count” values | traced, meaning unverified |
| 0x5C58 | 1 | Custom MIDI current group | traced |
| 0x5C59 | 1 | Custom keyboard current group | traced |
| 0x5C5A–5C | 3 | Three checkboxes (likely among Expression Pedal, TRS-MIDI, Polarity Reversal, PC display) | traced, meaning unverified |
| 0x5C5D | 1 | Mix Key current group | traced |

### Modes (byte 0x0000)

From CubeSuite's explanation list, indexed by this byte: 0 Program Change,
1 Control Change, 2 custom MIDI CC (simple), 3 **advanced custom MIDI**,
4 manufacturer control, 5 touch screen, 6 video, 7 keyboard arrows,
8 keyboard page turner, 9 multimedia keys, 10 custom keyboard, 11 **Mix Key**.
(12 “Speaker mode” exists in the list but the editor clamps to 11.)

### Switch program (0x1A1 = 417 bytes)

| Offset | Size | Meaning |
|---|---|---|
| 0 | 1 | Stomp mode: 0 press, 1 toggle A/B, 2 press A / release B, 3 hold to repeat, 4 short A / long B |
| 1 | 80 | Bank A: 16 slots × 5 bytes |
| 81 | 80 | Bank B: 16 slots × 5 bytes |
| 161 | 128 | Bank A raw bytes: length (≤127), then bytes |
| 289 | 128 | Bank B raw bytes |

Message slot: `present (≠0), channel (0-based), type, number, value`.
Types: 0 PC, 1 CC, 2 Note On, 3 Note Off, 4 raw (“Custom MIDI Code”). CubeSuite
packs slots from the start, and a raw message must be alone in its bank (it
sets slot 0 to type 4 and clears the rest). The list display format is
`[index] channel+1 type number value`.

### Mix Key switch (0x1A6 = 422 bytes)

Byte 0 = function (radio group: 0 Custom MIDI, 1 Custom Keyboard, 2 "Turner",
i.e. page turner), byte 1 = page-turner key (index into ↑ ↓ ← → Page Up,
Page Down, previous song, next song, Vol−, Vol+), bytes 2–3 = modifiers,
byte 4 = key (codes below), byte 5 onward = a switch program as above.

### Keyboard key codes (`FootCtrlPlusDlg::init`, `comBoxChange`)

The key byte is the position in CubeSuite's key menu:
0 none, 1–26 A–Z, 27–30 ↑ ↓ ← →, 31 Page Up, 32 Page Down, 33 Space,
34 Enter, 35 Esc, 36 Delete, 37 Caps Lock, 38 Tab, 39–48 digits 0–9,
49 +, 50 −, 51–62 F1–F12.
Modifier bytes are 0 (none) or 0x3E + menu position: 63 Ctrl, 64 Shift,
65 Alt, 66 Win/Command, continuing the key numbering. CubeSuite refuses the
same modifier twice. Not yet tested on the pedal.

## To verify with a real pedal

1. `chocoprobe id` answers with name `FootCtrlPlus`.
2. `chocoprobe dump before.chocoplus` reads all 23,646 bytes.
3. Change one setting in CubeSuite, dump again, `chocoprobe diff` → confirms
   which byte it is. Do this for each “unverified” row.
4. A first write: change one CC number in ChocoEdit, write, step on the switch
   and watch the live monitor.
