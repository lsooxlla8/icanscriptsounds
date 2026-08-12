# icanscriptsounds

A personal collection of scripts for [REAPER](https://www.reaper.fm/), distributed through [ReaPack](https://reapack.com/).

## Install with ReaPack

   ```text
   https://raw.githubusercontent.com/lsooxlla8/icanscriptsounds/main/index.xml
   ```

## Packages

### Track Organizer

Sorts imported multitracks into a stable folder hierarchy using an editable
rule library. Includes five workflow presets, direct preset actions and
**icss_Track Organizer Rule Manager** for visual editing, ordering, previews
and classification diagnostics. Unmatched tracks are placed in `OTHER` at the
end.

### Add Volume Adjustment Automation

Adds JS: Volume Adjustment to the selected track, sets Adjustment to 0 dB,
shows its automation envelope, and leaves the plug-in window closed.

### Prepare Selected Items for Mastering

Arranges selected file-backed items into mastering blocks, creates one colored
region and Region Render Matrix entry per item, and configures multichannel WAV
rendering through the master track. Foldered tracks share a start position and
use separate visible ruler lanes. Requires REAPER 7.78 or later.

### Freeze Toggle

Toggles every selected track independently:

- unfrozen track → freeze to stereo;
- frozen track → unfreeze one freeze layer.

### Smart Freeze Toggle

Toggles every selected track independently:

- unfrozen track → measure a safe post-FX tail, then freeze to stereo;
- frozen track → unfreeze one freeze layer.

The silence threshold is set 66 dB below the loudest 50 ms RMS window before
the tail.

The script requires the
[SWS/S&M extension](https://www.sws-extension.org/).

### Smart Toggle FX Window

Toggles the FX window of the selected track:

- closed window → close all track FX windows, then open its FX chain;
- open window → close all track FX windows.

### Toggle Toolbar at Top

Toggles the toolbar positioned "At top of main window":

- any current toolbar → the configured target toolbar;
- target toolbar → the previously active toolbar.

Set `TARGET_TOOLBAR` in the script to a toolbar number from 1 to 32. The
script requires [js_ReaScriptAPI](https://forum.cockos.com/showthread.php?t=212174).
