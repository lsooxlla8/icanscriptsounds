# icanscriptsounds

A personal collection of scripts for [REAPER](https://www.reaper.fm/), distributed through [ReaPack](https://reapack.com/).

## Install with ReaPack

1. In REAPER, open `Extensions > ReaPack > Import repositories...`.
2. Paste this URL:

   ```text
   https://raw.githubusercontent.com/lsooxlla8/icanscriptsounds/main/index.xml
   ```

3. Synchronize packages.
4. Open `Extensions > ReaPack > Browse packages...`.
5. Find and install the desired script.

Installed scripts are registered in REAPER's Action List.

## Packages

### Freeze Toggle

Toggles every selected track independently:

- unfrozen track → freeze to stereo;
- frozen track → unfreeze one freeze layer.

The script preserves the original track selection and safely handles mixed selections containing both frozen and unfrozen tracks.

### Smart Freeze Toggle

Toggles every selected track independently:

- unfrozen track → measure a safe post-FX tail, then freeze to stereo;
- frozen track → unfreeze one freeze layer.

The silence threshold is set 66 dB below the loudest 50 ms RMS window before
the tail, and the final Freeze keeps five continuous seconds of silence.

The script safely handles mixed selections and requires the
[SWS/S&M extension](https://www.sws-extension.org/).

### Smart Toggle FX Window

Toggles the FX window of the selected track:

- closed window → close all track FX windows, then open its FX chain;
- open window → close all track FX windows.

The script supports normal tracks, the master track, FX chains, floating FX,
and empty FX chains.
