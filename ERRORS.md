# ChocoEdit error codes

Every error ChocoEdit shows has a code like `CE-206`. Find your code below to
see what happened and what to try.

**Getting help from an AI assistant:** click **Copy Error Details** in the
alert, then paste it into your assistant together with a link to this page (or
its plain-text version:
https://raw.githubusercontent.com/jonpikereally/ChocoEdit/main/ERRORS.md). The
details include the code, what went wrong, and your ChocoEdit and macOS
versions.

Where errors show up:

- **Alerts** show the code, plus **Copy Error Details** and **Open Error List**
  buttons. Hovering over the error text points you here.
- **The status bar** at the bottom of the window shows the last error's code.
- **chocoprobe** and the installers print their code in the Terminal window.
- Every error is also logged to `~/Library/Application Support/ChocoEdit/errors.log`.


## Updates (1xx)

| Code | What happened | What to try |
|---|---|---|
| CE-101 | No update source is set. | Set one with “Update Source…” in the ChocoEdit menu, or leave it empty to use the built-in source. |
| CE-102 | The update source isn't a web link or a file path. | Set one with “Update Source…” in the ChocoEdit menu, or leave it empty to use the built-in source. |
| CE-103 | Couldn't reach the update source. | Check your internet connection and try again. |
| CE-104 | The update server returned an error. | Try again in a few minutes. If it keeps happening, download the latest version from GitHub. |
| CE-105 | The update information is damaged or in the wrong format. | The published update is broken. Download the latest version from GitHub instead. |
| CE-106 | Couldn't download the update. | Try again in a few minutes. If it keeps happening, download the latest version from GitHub. |
| CE-107 | Couldn't unpack the downloaded update. | The published update is broken. Download the latest version from GitHub instead. |
| CE-108 | The downloaded update doesn't contain ChocoEdit. | The published update is broken. Download the latest version from GitHub instead. |
| CE-109 | The downloaded update is a different app. | The published update is broken. Download the latest version from GitHub instead. |
| CE-110 | The downloaded update is damaged. | The published update is broken. Download the latest version from GitHub instead. |
| CE-111 | Couldn't start installing the update. | Make sure ChocoEdit is in ~/Applications and that the folder isn't locked, then try again. |
| CE-112 | Installing the update failed, so the previous version was kept. | Make sure ChocoEdit is in ~/Applications and that the folder isn't locked, then try again. |

## Talking to the pedal (2xx)

| Code | What happened | What to try |
|---|---|---|
| CE-201 | macOS's MIDI system couldn't be opened. | Quit and reopen ChocoEdit. If it keeps happening, restart the Mac. |
| CE-202 | No Chocolate Plus was found. | Switch the pedal on and plug it into the Mac with a USB-C data cable (not charge-only). Its MIDI port is called SINCO; ChocoEdit switches to it as soon as it appears. To use a different port anyway, pick it in the port menu yourself. |
| CE-203 | Couldn't open the pedal's MIDI port. | Unplug the pedal, plug it back in, and click Refresh. Quit CubeSuite if it's open. |
| CE-204 | The pedal isn't connected. | Pick the pedal in the port menu and click Connect. |
| CE-205 | Couldn't send MIDI to the pedal. | Unplug the pedal, plug it back in, and click Refresh. Quit CubeSuite if it's open. |
| CE-206 | The pedal didn't answer. | Use the USB cable rather than Bluetooth, quit CubeSuite, and try again. If it still doesn't answer, switch the pedal off and on. |
| CE-207 | The pedal sent an answer ChocoEdit didn't expect. | Try again. If it keeps happening, copy the details: the pedal's firmware may use a newer protocol. |
| CE-208 | The pedal refused to save a setting. | Read the settings from the pedal again before writing. Your backup from before the write is in ~/Documents/ChocoEdit Backups and can be loaded and written back. |
| CE-209 | A setting read back differently from what was written. | Read the settings from the pedal again before writing. Your backup from before the write is in ~/Documents/ChocoEdit Backups and can be loaded and written back. |
| CE-210 | The connected device isn't a Chocolate Plus. | Pick the Chocolate Plus in the port menu. ChocoEdit only edits the Chocolate Plus. |
| CE-211 | That MIDI port only echoes back what's sent to it, so it isn't the pedal. | This is usually an IAC Driver bus or a MIDI thru. Pick the pedal's port in the menu: over USB it's called SINCO. |

## Files and backups (3xx)

| Code | What happened | What to try |
|---|---|---|
| CE-301 | Couldn't open the settings file. | Check the file is where you think and that the folder isn't locked. |
| CE-302 | That file isn't a Chocolate Plus settings file. | ChocoEdit opens .chocoplus files it saved, and CubeSuite .fcp exports of the same size. |
| CE-303 | Couldn't save the settings file. | Check the file is where you think and that the folder isn't locked. |
| CE-304 | Couldn't save a backup of the pedal's settings, so nothing was written. | Check there's space on the disk and that ~/Documents isn't locked, then try again. |

## Installers (6xx)

| Code | What happened | What to try |
|---|---|---|
| CE-601 | The installer couldn't copy ChocoEdit into ~/Applications. | Check that ~/Applications exists and isn't locked, then run the installer again. |
| CE-602 | The installer couldn't sign ChocoEdit for this Mac. | Install Apple's Command Line Tools (`xcode-select --install`) and run the installer again. |
| CE-603 | ChocoEdit was installed but couldn't be opened. | Open ChocoEdit from ~/Applications yourself. |

## Anything else (9xx)

| Code | What happened | What to try |
|---|---|---|
| CE-999 | Something unexpected went wrong. | Try again. If it keeps happening, copy the details and ask for help. |
