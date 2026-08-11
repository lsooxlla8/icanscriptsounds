# ICSS Track Organizer

Track Organizer turns a flat or loosely structured imported multitrack into a
repeatable REAPER layout. It uses the same deterministic classifier in the
Organizer and Rule Manager, so GUI Preview and the real action agree.

The supplied library was built from the active REAPER resource file
`sws-autocoloricon.ini` (301 SWS Auto Color/Icon rules) and expanded with
common recording, mixing, electronic-production, orchestral and post-production
track names. SWS remains responsible for colors/icons; Track Organizer changes
only track order and folder membership.

## Files

- `icss_Track Organizer.lua` — one-Undo project organizer.
- `icss_Track Organizer Rule Manager.lua` — visual rule editor and preview
  window.
- `TrackOrganizer_Core.lua` — shared INI parser, matcher, classifier, validator
  and safe config writer.
- `track-order.ini` — editable rule library and settings.

Keep all four runtime files together. `TrackOrganizer_Core.lua` is a support
module, not a third action: copy it with the other files, but do not add it to
the Action List. Both visible scripts load it automatically.

## Install

1. In REAPER choose **Options > Show REAPER resource path in explorer/finder**.
2. Create `Scripts/ICSS/TrackOrganizer/` inside that resource folder.
3. Copy `icss_Track Organizer.lua`, `icss_Track Organizer Rule Manager.lua`,
   `TrackOrganizer_Core.lua`, and `track-order.ini` into that folder.
4. Open **Actions > Show action list…**, press **New action… > Load ReaScript…**,
   and load both `icss_Track Organizer.lua` and
   `icss_Track Organizer Rule Manager.lua`.
5. Optionally assign shortcuts or toolbar buttons to the two new actions.

Rule Manager uses REAPER's built-in graphics window. ReaImGui is not required.

## Normal workflow

1. Import the multitrack into a new REAPER project.
2. Let SWS Auto Color/Icon apply the existing color/icon rules.
3. Run **icss_Track Organizer**.
4. Review the category folders; unmatched tracks are always moved, in original
   relative order, into `OTHER` at the very end.
5. Open **icss_Track Organizer Rule Manager** to fix a classification, Preview
   all
   matches, inspect conflicts, or add a selected/OTHER track as a rule.
6. Save, then run Organizer again.

Organizer does not set colors and does not call SWS. This intentional separation
makes either action safe to rerun in any order.

## Classification algorithm

Each enabled node can contain positive `patterns` and negative `exclude`
patterns. A track can match several nodes. The candidates are sorted by:

1. higher explicit `priority`;
2. higher specificity (matched length, word count, exact-match bonus and tree
   depth);
3. visual/order path in the rule tree;
4. stable ID as a final deterministic tie-breaker.

This is why `snare bottom` beats `snare`, `bass guitar DI` beats electronic
`bass`, and `vocal fx` beats general `fx`. The technical priority values remain
inside the INI for compatibility; Rule Manager hides them and chooses sensible
values automatically for new child rules.

Inside each category, tracks containing the whole word `intro` form the first
block and tracks containing `outro` form the last block. Other tracks are joined
into connected name families using normalized phrase containment and shared
leading words. This keeps `Kick`, `Kick Shuffle`, `Kick Shuffle 2` together and
also connects `Hit Perc` with `Long Hit Perc`.

Within the same folder/name family, a whole-word `main` modifier is placed before
the corresponding unmarked name. Thus `Main Bass`, `Main Bass 2`, `Bass 2` keeps
the main pair together and ahead of the ordinary numbered variants. Intro/Outro
folder-boundary behavior still has the outermost ordering priority.

The family takes the position of its earliest applicable rule. Therefore
`Snare Fill` stays with `Snare` even if a more specific Fill rule also matches.
Inside a family, natural ordering puts an unnumbered base first, numeric variants
next, and longer processed names afterwards. `preserve_relative_order=true`
still preserves source order when two family/order keys are indistinguishable.

## INI format

Categories and rules have stable IDs in their section headers:

```ini
[category:drums]
name=DRUMS
folder=DRUMS / PERC
order=20
priority=0
enabled=true

[rule:drums.snare]
name=Snare
parent=drums
order=20
priority=105
enabled=true
patterns=snare; sn; snr; sd

[rule:drums.snare.bottom]
name=Snare Bottom
parent=drums.snare
order=20
priority=195
enabled=true
patterns=snare bottom; sn bot; sd bottom
exclude=snare bottom sample

[rule:drums.metal]
name=Metal / Cymbals
parent=drums
folder=METAL
order=60
priority=0
enabled=true
```

`name` and `folder` are display text. Renaming either never changes `id` or
`parent`. `order` is only compared with siblings. Rule Manager renumbers sibling
orders automatically when **UP** or **DOWN** changes the visible row order.

A `folder=` value on a rule turns that rule into a managed subfolder. Tracks are
placed in the deepest folder node on their winning rule path. The supplied tree
uses `DRUMS > KICK/SNARE/METAL/PERC`, `BASS > SUB/BASS`, and
`INSTRUMENTS > STRINGS`.

Patterns are separated by semicolons in both the INI and the editor. A literal
semicolon can be escaped as `\;`.

- Plain text (`sn bot`) matches a complete normalized word or phrase. Matching
  is not a raw substring search.
- `exact:audio 31` matches the complete normalized track name.
- `wildcard:*neuro growl*` uses `*` and `?` over the normalized full name.
- `lua:^sn%s+bot%s+%d+$` uses a Lua pattern. Use this only when plain matching
  and wildcard matching are insufficient.

CamelCase boundaries, punctuation, underscores and hyphens normalize to spaces,
so `RimPerc Delayed` is matched as `rim perc delayed`. Set
`case_sensitive=true` only if case is deliberately part of the naming scheme.

## Settings

- `create_folders=true` creates/reuses populated main folders and configured
  rule subfolders.
- `move_existing_folders=false` classifies an existing user folder by its own
  folder-track name. When `true`, descendants may help classify an otherwise
  unknown folder, but the subtree still stays atomic.
- `existing_folders=atomic` documents the safety contract. Existing user folder
  contents are never flattened by this version.
- `unknown_tracks=folder` is required: unknown units always go to `OTHER` last.
- `unknown_folder_name=OTHER` changes the displayed folder name without changing
  the stable `other` ID.
- `subfolder_min_tracks=3` creates a configured rule subfolder only when at
  least three project tracks belong to its subtree. An existing managed folder
  is reused rather than deleted if the count later falls below the threshold.
- `numbered_family_min_tracks=3` creates an automatic folder only when more than
  two tracks differ by a final number, such as `Hat`, `Hat 2`, `Hat 3` or
  `RimPerc Delayed`, `RimPerc Delayed 2`, `RimPerc Delayed 3`.
- `preserve_relative_order=true` retains source order for equal winners.
- `intro_first=true` puts names containing the whole word `intro` first inside
  their resulting category folder.
- `outro_last=true` puts names containing the whole word `outro` last.
- `main_first=true` puts `Main X` before the matching unmarked `X` family.
- `group_similar_names=true` keeps normalized base, prefix and contained-phrase
  families adjacent.
- `natural_name_sort=true` orders base names and numeric suffixes naturally,
  such as `Hat`, `Hat 2`, `Hat 3`.
- `dry_run=true` prints classification and order to the ReaScript Console and
  makes no project change.
- `debug=true` adds losing matches to dry-run console output.

An empty `OTHER` is not created on a first run. A previously created managed
folder is never silently deleted, because the user may have added FX, routing or
automation to that track.

## Folder and project safety

Before editing, Organizer starts one Undo block and calls `PreventUIRefresh(1)`.
It uses REAPER's native track reorder operation, so media items, FX, envelopes,
sends and receives remain attached to their existing track objects.

Existing user folders—including nested folders—are treated as balanced atomic
subtrees. Managed category folders and managed subfolders are tagged with a
track ext-state, temporarily unwrapped on rerun, then rebuilt around the newly
sorted units. Nested closures are combined correctly (`-2` when one track closes
a subfolder and its parent). The final `I_FOLDERDEPTH` sum is validated. If
classification/reordering throws an error or folder depth is invalid, Organizer
closes the Undo block and immediately undoes the run. Track selection is restored
after success.

No track is deleted. Unknown ordinary tracks and unknown user-folder subtrees
move to `OTHER` while preserving their original relative order.

## Rule Manager

The window follows the same basic idea as SWS Auto Color/Icon: one large rule
table whose visible row order is the order used by Organizer. It deliberately
hides stable IDs, numeric order, priority and specificity.

In **RULES**, click a row to choose it, double-click to edit, click its ON box to
enable/disable it, and use **UP** / **DOWN** to change order. **ADD** creates a
main group, a child rule, a managed subfolder, or a rule from the currently
selected REAPER track. The destination is simply the row you selected before
pressing Add. Folder rules are visibly marked `FOLDER` in the table.

**OTHER** lists tracks in the current project that are not recognized. Choose a
track and either append its name to the rule last selected in **RULES**, or make
a new child rule. Double-clicking an unknown track is the quick new-rule action.

**PREVIEW** shows exactly where every current track will go without moving
anything. A yellow `multiple matches` note means more than one rule matched;
double-click the row for a plain-language explanation. **MORE > Test a track
name...** checks one typed name without touching the project.

Before Save, Core validates syntax/model integrity, unique IDs, parent existence,
parent cycles, OTHER uniqueness and sibling order. A validated save first writes
a temporary file, creates `track-order.ini.bak`, and only then replaces the main
config. **MORE > Restore previous saved version** restores the last backup. The
window clearly marks unsaved changes.

## Extending rules manually

Prefer adding a narrow child with a higher priority instead of making a broad
pattern more aggressive. For example, add `bass.guitar.picked` under the stable
`instruments.bass_guitar` parent and give it patterns such as `picked bass` and
`bass pick`. Keep abbreviations as whole words, and use `exclude` on broad rules
when a professional naming collision is common.

After manual edits, open Rule Manager and Reload. It will refuse an invalid file
and show line/model errors. Test representative collisions before running the
Organizer on a large session. For the first use on valuable work, save the
project and run with `dry_run=true` once.
