# icanscriptsounds

A personal collection of scripts for [REAPER](https://www.reaper.fm/), distributed through [ReaPack](https://reapack.com/).

## Install with ReaPack

   ```text
   https://raw.githubusercontent.com/lsooxlla8/icanscriptsounds/main/index.xml
   ```

## Packages

### Items

#### New Track Copies

- **Duplicate to New Copy of a Track and Move to 0.00** — copies selected items or media-item Razor Edit material to new copies of their source tracks, then shifts the result so its earliest point is at 0.00.
- **Duplicate to New Copy of a Track** — copies selected items or media-item Razor Edit material to new copies of their source tracks at the original timeline position.
- **Move to New Copy of a Track** — moves selected items or media-item Razor Edit material to new copies of their source tracks at the original timeline position.

#### Prepare Selected Items for Mastering

Arranges selected items into mastering blocks, creates one colored region and
Region Render Matrix entry per selected track, and configures multichannel WAV
rendering through the master track. Audio, MIDI, generated-source and empty
items are supported. Foldered tracks share a start position and use separate
visible ruler lanes. Requires REAPER 7.78 or later.

### Track Management

#### Track Organizer

Sorts imported multitracks into a stable folder hierarchy using an editable
rule library. Includes five workflow presets, direct preset actions and
**icss_Track Organizer Rule Manager** for visual editing, ordering, previews
and classification diagnostics. Unmatched tracks are placed in `OTHER` at the
end.

#### Freeze Toggles

- **Freeze Toggle** — toggles every selected track independently: an unfrozen track is frozen to stereo; a frozen track is unfrozen by one freeze layer.
- **Smart Freeze Toggle** — toggles every selected track independently: an unfrozen track gets a measured safe post-FX tail and is then frozen to stereo; a frozen track is unfrozen by one freeze layer. The silence threshold is set 66 dB below the loudest 50 ms RMS window before the tail.

**Smart Freeze Toggle** requires the
[SWS/S&M extension](https://www.sws-extension.org/).

### FX and Automation

#### Add Volume Adjustment Automation

Adds JS: Volume Adjustment to the selected track, sets Adjustment to 0 dB,
shows its automation envelope, and leaves the plug-in window closed.

#### Smart Toggle FX Window

Toggles the FX window of the selected track:

- closed window → close all track FX windows, then open its FX chain;
- open window → close all track FX windows.

### Toolbars

#### Toggle Toolbar at Top

Toggles the toolbar positioned "At top of main window":

- any current toolbar → the configured target toolbar;
- target toolbar → the previously active toolbar.

Set `TARGET_TOOLBAR` in the script to a toolbar number from 1 to 32. The
script requires [js_ReaScriptAPI](https://forum.cockos.com/showthread.php?t=212174).
