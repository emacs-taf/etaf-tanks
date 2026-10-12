# Iron Tide · 钢铁洪流

A tank battle in Emacs that follows the rules of the 1985 arcade classic:
defend the eagle base at the bottom of the field, destroy every enemy tank of
the stage, and lose when the base falls or your last tank is gone. Twenty
original stages raise the difficulty step by step; basic, fast, power and
four-hit armored enemies arrive in waves, and flashing carriers drop helmet,
clock, shovel, star, grenade and extra-tank bonuses. A map editor creates and
test-plays your own stages.

A headless Godot world owns the rules, the fixed simulation clock and the
pixel-art renderer. ETAF shows its frames, the stage select, the battle panel,
the editor and the settings. Text displays get an equivalent character grid.
All artwork and stages are original.

## Install and play

Requires Emacs 29.1+, ETAF, etaf-ui and GameKit on `load-path`, and Godot
installed through GameKit. Add this repository root to `load-path`:

```elisp
(require 'etaf-tanks)
(etaf-tanks-open)
```

Choose a stage with the arrow keys and press Return or `G`. In battle the arrow
keys drive, `Shift` with an arrow turns in place, and `F` fires. `P` pauses, `S`
opens the settings (game speed, tank speed, key sensitivity, driving mode and
frame rate), `T` switches the light and dark palettes and `F1` lists every key.

The [manual](docs/manual.md) covers the rules, the map format, the editor,
snapshots and the display. The [entry Commentary](etaf-tanks.el) owns the
supported API. `make check` compiles the package and exercises the real Godot
backend through public game and UI interfaces.
