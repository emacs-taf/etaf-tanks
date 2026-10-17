# Changelog

## [Unreleased]

### Added

- `etaf-tanks-doctor` reports whether GameKit's local Godot runtime exists, so
  `M-x etaf-install` shows the missing prerequisite with its one build command
  instead of failing when a battle starts.

### Fixed

- The package entry now puts `lisp/` on `load-path` while the byte compiler
  runs, so an archive installation compiles every module.

### Changed

- `?`, `F1` and the help button now share searchable keyboard help in the
  game buffer. Bindings follow the current screen; rules remain as usage
  notes. Escape exits search editing before closing; clicking the backdrop
  also closes help and restores focus. Every entry pauses a running battle,
  and closing never resumes it automatically.
