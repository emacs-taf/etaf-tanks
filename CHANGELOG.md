# Changelog

## [0.2.8] - 2026-10-25

### Added

- The map editor paints while `Shift` and an arrow key are held, so one held
  key draws a stroke along the cursor's path instead of pressing `F` again at
  every step. A plain arrow still only moves the cursor.

## [0.2.4] - 2026-10-20

### Fixed

- An embedded battle now renders one battle once in its host window and pauses
  when keyboard focus leaves it.
- Each keyboard shortcut is labelled with the key it actually uses.


### Added

- `etaf-tanks-doctor` reports whether GameKit's local Godot runtime exists, so
  `M-x etaf-install` shows the missing prerequisite with its one build command
  instead of failing when a battle starts.

### Fixed

- The package entry now puts `lisp/` on `load-path` while the byte compiler
  runs, so an archive installation compiles every module. The directory comes
  from the file being compiled, not from the script that started the install.

### Changed

- `?`, `F1` and the help button now share searchable keyboard help in the
  game buffer. Bindings follow the current screen; rules remain as usage
  notes. Escape exits search editing before closing; clicking the backdrop
  also closes help and restores focus. Every entry pauses a running battle,
  and closing never resumes it automatically.
