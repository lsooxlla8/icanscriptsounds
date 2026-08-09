# icanscriptsounds

A personal collection of scripts for [REAPER](https://www.reaper.fm/), distributed through [ReaPack](https://reapack.com/).

## Install with ReaPack

   ```text
   https://raw.githubusercontent.com/lsooxlla8/icanscriptsounds/main/index.xml
   ```

## Packages

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
