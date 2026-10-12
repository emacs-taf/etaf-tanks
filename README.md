# Iron Tide · 钢铁洪流

A real-time tank battle in Emacs. Drive between cover, turn to aim and destroy
three autonomous enemy tanks before your armour is gone. Godot owns the 60 Hz
physics simulation, swept collisions, pathfinding, projectiles and victory;
ETAF presents the battlefield and native controls in daylight and night palettes.
The world keeps moving when you are not pressing keys.

This independent application owns its Godot project, artwork, interface and
tests. GameKit supplies only the shared game instance and backend connection.

## Install and play

Requires Emacs 29.1+, GameKit, ETAF and etaf-ui on `load-path`, and Godot installed
through GameKit. Add this repository root to `load-path`:

```elisp
(require 'etaf-tanks)
(etaf-tanks-open)
```

The battle starts paused. Press `P` to begin, the arrow keys to drive, `Shift` with
an arrow key to aim without moving, and `F` to fire.
The same actions have mouse-accessible controls below the battlefield. `X`
stops movement, `N` restarts, `T` switches palettes and `Q` closes the game.
Opening help or a snapshot prompt pauses the battle first.

The [manual](docs/manual.md) describes controls, snapshots, independent instances
and the display's minimum size. The [entry Commentary](etaf-tanks.el) owns the
supported API. `make check` compiles the package and exercises the real Godot
backend through public game and UI interfaces, including victory and defeat.
