# Iron Tide · 钢铁洪流

Iron Tide runs an independent headless Godot world per game. Its native fixed
physics clock owns continuous motion, swept collision, AStar pathfinding,
projectiles, enemy pursuit and victory/defeat. The ETAF application owns the
vector projection, light/dark palettes, native controls and file prompts.
Requiring GameKit never loads or launches this game.

```elisp
(add-to-list 'load-path "/path/to/etaf-games/etaf-tanks")
(require 'etaf-tanks)
(etaf-tanks-open)
```

Install ETAF, etaf-ui and GameKit, including its Godot runtime, before opening.
The bundled project is `native/godot/`, resolved relative to this package's own
entry. The [entry Commentary](../etaf-tanks.el) documents the supported Lisp API.

## Driving and combat

The arena starts paused so you can inspect it before launching. After `P`,
enemies and shells move without further input. The native simulation runs at
60 physics ticks per second; the project requests changed observations at up
to 60 Hz through GameKit's `observation_hz` setting. Physics, state publication
and actual display refresh are different clocks, not a per-command turn system.

| Input | Action |
| --- | --- |
| P / Start–Pause | Begin, freeze or resume the simulation; clear queued movement |
| W A S D / driving buttons | Drive north, west, south or east; repeated input keeps driving |
| Shift+W A S D / aiming buttons | Aim in that direction without moving |
| Space / Fire | Fire when the cannon is loaded |
| X / Stop | Cancel the player's route |
| N / Restart | Restore the initial paused battle |
| C-s / Save, C-o / Load | Pause and choose a local snapshot file |
| T / Light–Dark | Switch the whole interface's palette |
| F1 / Help | Pause and open the field manual |
| Q | Close this instance |

A player shell destroys one enemy tank; an enemy shell deals 20 damage. Walls
block both traffic and shells, and tanks cannot overlap. All three enemy tanks
must be destroyed to win; zero armour is defeat. There is no friendly fire.
The player cannon reloads in 0.28 seconds, enemy cannons in 1.6 seconds. Holding
Space fires as the cannon becomes available. Driving and firing can be sent
together without losing the shot. The native kernel accepts repeated fire
during reload as a no-op; it never shortens the reload or creates extra shells.

Each directional press gives one nearby destination. Key repeat is coalesced
to the current segment and at most one next cell instead of accumulating an
unbounded route. `etaf-tanks-open` pauses when its game buffer is no longer the
selected buffer/window. Help and file input also pause first; dismissing them
does not unexpectedly resume the battle. Close kills only this game's backend.

## Snapshots and programmatic callers

A definition can be started with `etaf-gamekit-start etaf-tanks-game`; the caller
owns its buffer and uses `etaf-gamekit-close` to release it. Read the current
world with `etaf-gamekit-observation`, or use `etaf-gamekit-view` in reactive
views. Commands go through `etaf-gamekit-action`:

- `move` takes integer `:x`/`:y` describing one cardinal step.
- `navigate` takes an integer destination `:x`/`:y` on the 21 × 13 arena.
- `aim` takes `:direction` equal to `"n"`, `"e"`, `"s"` or `"w"`.
- `fire`, `stop`, `pause` and `restart` take no arguments.
- `save` and `load` take an explicit `:path` string.

Movement and firing require an active, nonterminal battle. A rejected order
leaves accepted state unchanged while paused; during a live battle, physics
continues independently of the rejected input. Rejections are available through
`etaf-gamekit-last-error`. A transport failure requires closing that instance
and starting a new one before loading a snapshot.

Wait for `etaf-gamekit-status` to report `ready` before the first command.
Subsequent inputs may overlap under GameKit's bounded outstanding-request
contract. The opening example returns the instance immediately; it does not
block Emacs waiting for the external engine. Commands acknowledge asynchronously.

Snapshots are opaque application files, atomically published after serialization.
They retain tank positions and headings, armour, reload timers, kills, shots,
time and the terminal result. Loading validates the complete candidate before
replacing the world, remains paused, and clears routes, in-flight shells and
transient flashes. Malformed or oversized files leave the existing battle
untouched. No automatic save occurs on close.

## Display and appearance

`etaf-tanks-appearance` selects the initial `auto`, `light` or `dark` palette.
Auto follows the opening frame; every instance can switch independently.
The graphical arena separates immutable terrain from dynamic tank and shell
artwork. Small retained image regions project only the objects intersecting
them, so movement does not decode or repaint the entire map. They use ETAF UI's
public image grid and standard text rows; tracks, hulls, barrels, projectiles
and impacts remain derived from native state. Terminals use text cells as a
fallback.

The graphical arena has twenty text rows and an aspect-correct character width
chosen once when opened: with a 7 × 16 pixel font it is 518 × 320 pixels.
Window resizing reflows surrounding controls, not the arena or sprites. A short
window removes vertical gaps; below the complete table's minimum, clipping and
native scrolling are deliberate. Palette changes affect presentation only;
the running backend does not restart and is not paused by a theme switch.

Correctness lives in `tests/acceptance.json`. The real-backend scenarios cover
independent physics, blocking, ammunition, victory, defeat, restart, snapshots,
themes and independent instances. `scripts/etaf-tanks-gui-scenarios.el` drives
the application in a dedicated existing frame through native keys, real file
prompts, live combat and both themes across the viewport matrix.

Use the enclosing workspace's performance driver with this application's
`benchmarks/performance-scenarios.el`. The `etaf-tanks.keys.*` workloads measure
native Emacs command-loop input, asynchronous native response, committed
canvas changes and the driver's final redisplay. Driving measures the first
visible movement in a fresh live arena, not completion of the travel animation.
Aiming and loaded shots use continuous live battles with autonomous enemies.
The firing fixture aims at aligned raiders during readiness and waits for the
normal reload before timing Space; it plays through victory and restarts a
terminal battle rather than repeatedly shooting one empty direction until
killed. Preparation aiming is not included in the separate Space latency. A projectile
that could end the match is allowed to resolve before admitting another shot;
physics and enemies keep running. Readiness also waits for the displayed player
summary to match the latest accepted state. A winning shot is a valid completion,
recorded in the outcome together with cumulative victories and defeats. Native input
rejections fail promptly with their actual reason rather than waiting for a
visual change that cannot occur. Outcomes record the battle number, position,
shots, elapsed game time and armour. Restart and cooldown time are not claimed
as firing latency.

`etaf-tanks.keys.drive-fire` alternates direction and fires in the same command
loop while enemies and shells keep running. It renews the clear corridor after
four live seconds, outside the measured gesture. Emacs' `pre-redisplay-functions`
records `moving-redraw-gaps-ms`: cumulative intervals between changed player
positions and image displays offered to redisplay during each moving segment,
including harness overhead. These are redraw opportunities, not completed
screen-presentation timestamps. A stationary interval is not counted as a
missed moving frame. Use the last outcome of each series to avoid counting
cumulative data twice. Input latency and redraw cadence are separate checks;
neither the requested physics rate nor a fast first response proves smooth
continued motion. Actual presentation requires the separate GUI capture gate.
Separate theme, pause and resize workloads remain available.

Background GUI results do not certify foreground operating-system input
latency. Screenshots and line-height assertions are separate from timings;
all GC and slow samples stay in the evidence.
