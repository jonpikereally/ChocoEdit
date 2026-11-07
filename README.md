# ChocoEdit

An editor for the **M-VAVE Chocolate Plus** MIDI foot controller on macOS,
in the spirit of the Morningstar editor: pick a group, click a switch, give it
a list of messages, write it to the pedal.

ChocoEdit isn't made or supported by M-VAVE. It speaks the same SysEx protocol
as their CubeSuite app (see [PROTOCOL.md](PROTOCOL.md)).

## What it does

- **Read from Pedal** loads all of the pedal's settings over USB MIDI.
- **Custom MIDI** and **Mix Key** modes: 8 (or 6) groups of 4 switches. Each
  switch has a stomp mode (press, toggle A/B, press/release, hold to repeat,
  short/long) and up to 16 messages per bank (PC, CC, Note On/Off), or raw
  SysEx bytes.
- **Custom keyboard** mode (and Mix Key's keyboard option): click **Learn from
  Keyboard** and press the key or combination a switch should type, like ⌘⇧S
  or F5. The pedal can type A–Z, 0–9, F1–F12, arrows, Page Up/Down, Space,
  Enter, Esc, Delete, Caps Lock, Tab, + and −, with up to two modifiers.
- **Write to Pedal** backs up what's on the pedal to
  `~/Documents/ChocoEdit Backups`, writes only the bytes you changed, then reads
  them back to check.
- **Settings files** (`.chocoplus`, the raw 23,646-byte block) to keep setups.
- **Live MIDI** in the sidebar shows what the pedal sends when you step on it.
- **Advanced…** shows every settings byte with its meaning, including the ones
  not decoded yet. Bytes ChocoEdit doesn't understand are kept exactly as read.

## Connecting

Plug the pedal in with a USB-C data cable and quit CubeSuite. Over USB the
pedal's MIDI port is called **SINCO** (the company that makes M-VAVE gear);
ChocoEdit picks it automatically.

## Build and install

```
./install.sh        # builds, copies to ~/Applications, opens it
./test.sh           # offline tests (codec, packets, layout, fake pedal)
```

## chocoprobe

A command-line companion for checking the protocol against the real pedal:

```
./chocoprobe list                     # MIDI ports (* = looks like the pedal)
./chocoprobe id                       # name and version
./chocoprobe dump a.chocoplus         # read everything into a file
./chocoprobe diff a.chocoplus b.chocoplus   # what changed, by name
./chocoprobe write a.chocoplus --yes  # back up, write changes, verify
```

Add `--verbose` to see every packet, `--port <name>` to pick a port.

## Releases

`./release.sh` builds a universal app into `updates/`; pushing `updates/` to
the public GitHub repo ships it to the in-app updater. Errors: [ERRORS.md](ERRORS.md).
