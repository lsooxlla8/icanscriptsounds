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
- `icss_Track Organizer - Preset 1.lua` … `Preset 5.lua` — direct actions for
  Music Mixing, Film Post, Sound Design, Podcast and Audiobook, respectively.
- `TrackOrganizer_Core.lua` — shared INI parser, matcher, classifier, validator
  and safe config writer.
- `Factory Presets/*.ini` — package-owned starting templates: Music Mixing,
  Film Post, Sound Design, Podcast and Audiobook.
- `Presets/*.ini` — your editable working copies and any presets you create.
  Missing factory presets are copied here automatically and existing files are
  never overwritten by the scripts.
- `track-order.ini` — source copy of the Music Mixing template. ReaPack installs
  it only as `Factory Presets/01 Music Mixing.ini`, so an older personalized
  `track-order.ini` is left untouched during the upgrade.

Keep the complete `TrackOrganizer` directory together. `TrackOrganizer_Core.lua`
is a support module, not an action: install it with the other files, but do not
add it to the Action List. The visible scripts load it automatically.

## Install

1. In REAPER choose **Options > Show REAPER resource path in explorer/finder**.
2. Create `Scripts/ICSS/TrackOrganizer/` inside that resource folder.
3. Copy the complete contents of this `TrackOrganizer` directory, including its
   `Presets` subdirectory, into that folder.
4. Open **Actions > Show action list…**, press **New action… > Load ReaScript…**,
   and load `icss_Track Organizer.lua`,
   `icss_Track Organizer Rule Manager.lua`, and any of the five
   `icss_Track Organizer - Preset N.lua` actions you want to call directly.
5. Optionally assign shortcuts or toolbar buttons to the main action, Manager,
   and preset-slot actions.

Rule Manager uses REAPER's built-in graphics window. ReaImGui is not required.

## Normal workflow

1. Import the multitrack into a new REAPER project.
2. Let SWS Auto Color/Icon apply the existing color/icon rules.
3. Choose a preset in Rule Manager, or run one of the five preset-slot actions.
   The selection is remembered separately by the current REAPER project.
4. Run **icss_Track Organizer**. It uses the preset remembered by that project;
   if none was chosen, it uses the global default and then Preset 1.
5. Review the category folders; unmatched tracks are always moved, in original
   relative order, into `OTHER` at the very end.
6. Open **icss_Track Organizer Rule Manager** to fix a classification, Preview
   all matches, inspect conflicts, edit order modifiers, or add a selected/OTHER
   track as a rule.
7. Save, then run Organizer again.

**New preset from current rules...** creates a separate named Action List action
for that exact preset. Unlike the numbered Preset 1–5 actions, it does not change
meaning when other presets are added or removed. **Delete current preset...**
removes that preset and unregisters its named action; it never deletes or changes
tracks in the current project. Deleted preset/action files are retained next to
their originals with a `.deleted` suffix for manual recovery.

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

Order modifiers are evaluated after classification and before ordinary family
sorting. The supplied `Intro / Opening` modifier puts matching tracks first,
`Main` puts a marked track before the corresponding unmarked name family, and
`Outro / Ending` puts matching tracks last. These are normal editable config
objects shown in Rule Manager under **ORDERING**, not hidden code. Other tracks
are joined into connected name families using normalized phrase containment and
shared leading words. This keeps `Kick`, `Kick Shuffle`, `Kick Shuffle 2`
together and also connects `Hit Perc` with `Long Hit Perc`.

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
container=folder
order=20
priority=0
enabled=true

[category:book_order]
name=BOOK ORDER
container=order
order=10
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
container=folder
order=60
priority=0
enabled=true

[rule:drums.transitions]
name=Transitions
parent=drums
container=order
order=70
priority=0
enabled=true

[modifier:intro]
name=Intro / Opening
placement=first
order=10
enabled=true
patterns=intro; opening
```

`name` and `folder` are display text. Renaming either never changes `id` or
`parent`. `order` is only compared with siblings. Rule Manager renumbers sibling
orders automatically when **UP** or **DOWN** changes the visible row order.

A `container=folder` node creates a managed REAPER folder track; its `folder=`
value is the physical track name. Tracks are placed in the deepest physical
folder node on their winning rule path. The supplied Music Mixing tree
uses `DRUMS > KICK/SNARE/METAL/PERC`, `BASS > SUB/BASS`,
`GUITARS > GUITARS/BASS GUITARS`, and `INSTRUMENTS > STRINGS`. Guitar, gtr and
guit variants share `GUITARS`; bass guitar and bass gtr variants are kept in the
separate `BASS GUITARS` subfolder and classified by its child `Bass Guitar`
rule.

`container=order` is a virtual order group. It can contain rules and nested
order groups, and its visible position affects sorting exactly like a folder,
but Organizer never creates a REAPER folder track for it. Use this for chapter
order, production stages, print order, or any hierarchy that should be visible
in Manager without changing the physical project folder structure.

`container=none` is a normal leaf or logical parent rule. It may have sibling
rules before and after it, so adding a rule never implicitly puts it inside the
previous row. **ADD BELOW** explicitly creates a sibling; **ADD INSIDE**
explicitly creates a child.

An expandable row is not a separate rule type: it simply has child rules. Use
**ADD INSIDE** to make a logical parent such as `Snare` with `Snare Top` and
`Snare Bottom` beneath it. It only becomes a physical REAPER subfolder when it
is changed to `container=folder`. A virtual hierarchy uses `container=order`.

To move an existing rule, select it and click **MOVE TO...**, then choose a main
group or subfolder. The stable rule ID, patterns, exclusions and complete child
branch are preserved. **UP** and **DOWN** only reorder rules inside their current
parent.

Rule creation is explicit: **ADD BELOW** creates a sibling immediately after the
selected rule, while **ADD INSIDE** creates a child inside the selected main
group, subfolder or rule. **NEW...** contains the less common actions for a new
main group, a new subfolder or a rule based on the selected REAPER track.

Patterns may be separated by semicolons or commas in both the INI and the
editor. Manager saves them in the canonical semicolon-separated form. A literal
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
- `move_existing_folders=true` is retained for config compatibility. This
  version always applies safe content-aware handling: the subtree stays atomic
  and moves to a main category only when every non-container track inside is
  recognized as that same category. Mixed or partly unknown folders move intact
  to `OTHER`. Container folder names themselves do not contaminate this decision.
- `existing_folders=atomic` documents the safety contract. Existing user folder
  contents are never flattened by this version.
- `unknown_tracks=folder` is required: unknown units always go to `OTHER` last.
- `unknown_folder_name=OTHER` changes the displayed folder name without changing
  the stable `other` ID.
- `subfolder_min_tracks=3` creates a configured rule subfolder only when at
  least three project tracks belong to its subtree. An existing managed folder
  is reused rather than deleted if the count later falls below the threshold.
- `subfolder_min_elements=2` additionally requires at least two immediate
  elements after nested folders are formed. `Hat`, `Hat 2`, `Hat 3` may become
  one `HAT` element and therefore do not create a redundant outer `METAL` by
  themselves. Existing managed wrappers are preserved rather than deleted.
- `numbered_family_min_tracks=3` creates an automatic folder only when more than
  two tracks differ by a final number, such as `Hat`, `Hat 2`, `Hat 3` or
  `RimPerc Delayed`, `RimPerc Delayed 2`, `RimPerc Delayed 3`.
- `preserve_relative_order=true` retains source order for equal winners.
- `intro_first`, `outro_last` and `main_first` are legacy compatibility defaults
  used only when an older config has no `[modifier:...]` sections. In current
  presets, edit the visible rules under Rule Manager **ORDERING** instead.
- `group_similar_names=true` keeps normalized base, prefix and contained-phrase
  families adjacent. Names that resolve to the same visible classification
  rule are also one sorting family; edit that rule's match list in Rule Manager.
- `natural_name_sort=true` orders base names and numeric suffixes naturally,
  such as `Hat`, `Hat 2`, `Hat 3`. Since `guitar`, `gtr`, and `guit` are listed
  on the same visible `Guitars` rule, `Guitar`, `Guit 2`, `Guit 3`, `gtr 4`
  are sorted as one family without hard-coded aliases.
- `dry_run=true` prints classification and order to the ReaScript Console and
  makes no project change.
- `debug=true` adds losing matches to dry-run console output.

An empty `OTHER` is not created on a first run. Once created, it remains even if
it later becomes empty. A configured subfolder created at the threshold is also
kept if its population later drops below the threshold.

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

Organizer never calls `DeleteTrack`: no ordinary, managed, retired or automatic
folder track is deleted. Obsolete wrappers are untagged, safely unwrapped and
preserved as ordinary tracks. Unknown ordinary tracks and complete unknown or
mixed user-folder subtrees move to `OTHER` while preserving their relative
order and internal folder structure.

## Rule Manager

The window follows the same basic idea as SWS Auto Color/Icon: one large rule
table whose visible row order is the order used by Organizer. It deliberately
hides stable IDs, numeric order, priority and specificity.

The preset button at the top switches the complete rule library used by the
current project. Unsaved edits must be saved or reloaded before switching.
**MORE > New preset from current rules** clones the active library; **Set current
preset as default** chooses the fallback for projects that have no selection.

In **RULES**, click a row to choose it, double-click to edit, click its ON box to
enable/disable it, and use **UP** / **DOWN** to change order. **ADD BELOW** makes
a sibling; **ADD INSIDE** makes a child. **NEW...** creates a main folder, a
main order group, a subfolder, an order group, or a rule from the currently
selected REAPER track. Physical folders are marked `FOLDER`; virtual groups are
marked `ORDER` and explicitly say that they create no track.

In **ORDERING**, edit the small list of exceptional ordering rules. Each
rule has a name, words to look for, optional exclusions, and one behavior chosen
from a menu: move matches to the beginning, place them before the same name
without that word, or move them to the end. No technical value has to be typed.
This is where Intro, Main and Outro behavior is changed or extended; for
example, `opening` can be added to Intro without touching Lua code.

**OTHER** lists tracks in the current project that are not recognized. Choose a
track and either append its name to the rule last selected in **RULES**, or make
a new child rule. Double-clicking an unknown track is the quick new-rule action.

**PREVIEW** shows exactly where every current atomic track/folder unit will go
without moving anything. Existing folders are marked `FOLDER`; double-click one
to see why its complete subtree moves to one category or remains intact in
`OTHER`. A yellow `multiple matches` note means more than one rule matched;
double-click the row for the actual deciding factor: priority, specificity or
rule order. **MORE > Test a track name...** checks one typed name without
touching the project.

Before Save, Core validates syntax/model integrity, Lua patterns, unique IDs,
parent existence, parent cycles, OTHER uniqueness, sibling order and obvious
cross-rule shadowing. A validated save first writes and re-reads a temporary
file, safely installs `<active preset>.ini.bak`, and then atomically replaces the
active preset. The current preset is never removed before its replacement is
ready. **MORE > Restore previous saved version** first validates that preset's
backup and leaves the active config untouched if it is invalid. The window
clearly marks unsaved changes.

## Extending rules manually

Prefer adding a narrow child with a higher priority instead of making a broad
pattern more aggressive. For example, add `guitars.bass_guitar.picked` under the
stable `guitars.bass_guitar` parent and give it patterns such as `picked bass` and
`bass pick`. Keep abbreviations as whole words, and use `exclude` on broad rules
when a professional naming collision is common.

After manual edits, open Rule Manager and Reload. It will refuse an invalid file
and show line/model errors. Test representative collisions before running the
Organizer on a large session. For the first use on valuable work, save the
project and run with `dry_run=true` once.
